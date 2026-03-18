local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local Signal = require(script.Parent.Signal)
local Logger = require(script.Parent.Logger)
local Middleware = require(script.Parent.Middleware)
local Promise = require(script.Parent.Promise)
local Trove = require(script.Parent.Trove)
local Types = require(script.Parent.Types)

type ServiceConfig = Types.ServiceConfig
type ControllerConfig = Types.ControllerConfig

local Zenith = {}
Zenith.__index = Zenith

local services: { [string]: ServiceConfig } = {}
local controllers: { [string]: ControllerConfig } = {}
local serverProxies: { [string]: { [string]: any } } = {}
local frameworkTrove = Trove.new()
local started = false
local readySignal = Signal.new()
local isReady = false
local log = Logger.new("Zenith")

function Zenith.OnStart(fn: () -> ())
	if isReady then
		task.spawn(fn)
	else
		readySignal:Once(fn)
	end
end

function Zenith.WaitUntilReady(): ()
	if isReady then return end
	readySignal:Wait()
end

function Zenith.CreateService(config: ServiceConfig): ServiceConfig
	assert(IS_SERVER, "Services can only be created on the server.")
	assert(type(config.Name) == "string", "Service must have a Name.")
	assert(not services[config.Name], "Service '" .. config.Name .. "' already exists.")
	assert(not started, "Cannot create services after Zenith.Start() has been called.")

	config.Client = config.Client or {}
	config.Client._service = config
	config.Dependencies = config.Dependencies or {}

	services[config.Name] = config
	log:Info("Registered service: " .. config.Name)
	return config
end

function Zenith.CreateController(config: ControllerConfig): ControllerConfig
	assert(IS_CLIENT, "Controllers can only be created on the client.")
	assert(type(config.Name) == "string", "Controller must have a Name.")
	assert(not controllers[config.Name], "Controller '" .. config.Name .. "' already exists.")
	assert(not started, "Cannot create controllers after Zenith.Start() has been called.")

	config.Dependencies = config.Dependencies or {}
	controllers[config.Name] = config
	log:Info("Registered controller: " .. config.Name)
	return config
end

function Zenith.Get(name: string): any
	if IS_SERVER then
		local service = services[name]
		if service then return service end
		error("Service '" .. name .. "' not found.")
	else
		local ctrl = controllers[name]
		if ctrl then return ctrl end
		local proxy = serverProxies[name]
		if proxy then return proxy end
		error("'" .. name .. "' not found as a controller or server service proxy.")
	end
end

local function resolveDependencyOrder(registry: { [string]: any }): { any }
	local resolved: { [string]: boolean } = {}
	local order: { any } = {}
	local visiting: { [string]: boolean } = {}

	local function visit(name: string)
		if resolved[name] then return end
		if visiting[name] then
			error("Circular dependency detected involving '" .. name .. "'.")
		end

		visiting[name] = true

		local obj = registry[name]
		if obj and obj.Dependencies then
			for _, dep in ipairs(obj.Dependencies) do
				if not registry[dep] then
					error("'" .. name .. "' depends on '" .. dep .. "' which does not exist.")
				end
				visit(dep)
			end
		end

		visiting[name] = nil
		resolved[name] = true
		table.insert(order, obj)
	end

	for name in pairs(registry) do
		visit(name)
	end

	return order
end

local function runInit(obj: any, name: string): Promise.Promise?
	if type(obj.OnInit) ~= "function" then return nil end

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(obj.OnInit, obj)
		if ok then
			log:Info("OnInit: " .. name)
			resolve()
		else
			log:Error("OnInit failed for " .. name .. ": " .. tostring(err))
			reject(err)
		end
	end)
end

local function runStart(obj: any, name: string)
	if type(obj.OnStart) ~= "function" then return end

	Promise.new(function(resolve, reject)
		local ok, err = pcall(obj.OnStart, obj)
		if ok then
			log:Info("OnStart: " .. name)
			resolve()
		else
			log:Error("OnStart failed for " .. name .. ": " .. tostring(err))
			reject(err)
		end
	end)
end

local function bindRunService(obj: any)
	if type(obj.OnHeartbeat) == "function" then
		frameworkTrove:Connect(RunService.Heartbeat, function(dt: number)
			obj:OnHeartbeat(dt)
		end)
	end

	if type(obj.OnStepped) == "function" then
		frameworkTrove:Connect(RunService.Stepped, function(t: number, dt: number)
			obj:OnStepped(t, dt)
		end)
	end

	if IS_CLIENT and type(obj.OnRenderStepped) == "function" then
		frameworkTrove:Connect(RunService.RenderStepped, function(dt: number)
			obj:OnRenderStepped(dt)
		end)
	end
end

local function runLifecycle(registry: { [string]: any }): Promise.Promise
	local order = resolveDependencyOrder(registry)

	return Promise.new(function(resolve, reject)
		for _, obj in ipairs(order) do
			local p = runInit(obj, obj.Name)
			if p then
				local ok, err = p:await()
				if not ok then
					reject(err)
					return
				end
			end
		end

		for _, obj in ipairs(order) do
			runStart(obj, obj.Name)
		end

		for _, obj in ipairs(order) do
			bindRunService(obj)
		end

		resolve()
	end)
end

local function setupServerBridge()
	local folder = Instance.new("Folder")
	folder.Name = "ZenithComm"
	folder.Parent = game:GetService("ReplicatedStorage")
	frameworkTrove:Add(folder)

	for serviceName, service in pairs(services) do
		if not service.Client then continue end

		local serviceFolder = Instance.new("Folder")
		serviceFolder.Name = serviceName
		serviceFolder.Parent = folder

		for methodName, value in pairs(service.Client) do
			if methodName == "_service" then continue end

			if type(value) == "function" then
				local rf = Instance.new("RemoteFunction")
				rf.Name = methodName
				rf.Parent = serviceFolder

				rf.OnServerInvoke = function(player: Player, ...)
					local args = { player, ... }
					local allowed, modified, override = Middleware._runServerMiddleware(serviceName, methodName, args)
					if not allowed then return nil end
					if override ~= nil then return override end
					local result = value(service.Client, table.unpack(modified or args))
					result = Middleware._runPostMiddleware(serviceName, methodName, result)
					return result
				end

			elseif typeof(value) == "table" and value._isSignal then
				local reToClient = Instance.new("RemoteEvent")
				reToClient.Name = methodName
				reToClient.Parent = serviceFolder

				local reToServer = Instance.new("RemoteEvent")
				reToServer.Name = methodName .. "_toServer"
				reToServer.Parent = serviceFolder

				frameworkTrove:Connect(value, function(...)
					reToClient:FireAllClients(...)
				end)

				frameworkTrove:Connect(reToServer.OnServerEvent, function(player: Player, ...)
					local args = { player, ... }
					local allowed, modified = Middleware._runServerMiddleware(serviceName, methodName .. "_fire", args)
					if not allowed then return end
					value:Fire(table.unpack(modified or args))
				end)
			end
		end
	end

	log:Info("Server bridge ready.")
end

local function setupClientBridge(): Promise.Promise
	return Promise.new(function(resolve, reject)
		local commFolder = nil
		local attempts = 0

		repeat
			attempts += 1
			commFolder = game:GetService("ReplicatedStorage"):WaitForChild("ZenithComm", 3)
			if not commFolder then
				log:Warn("Waiting for ZenithComm... (" .. attempts .. "/5)")
			end
		until commFolder or attempts >= 5

		if not commFolder then
			reject("Could not find ZenithComm after 5 attempts. Did the server call Zenith.Start()?")
			return
		end

		for _, serviceFolder in ipairs(commFolder:GetChildren()) do
			local proxy: { [string]: any } = {}

			for _, remote in ipairs(serviceFolder:GetChildren()) do
				if remote.Name:find("_toServer$") then continue end

				if remote:IsA("RemoteFunction") then
					local rf = remote :: RemoteFunction
					proxy[remote.Name] = function(_: any, ...)
						return rf:InvokeServer(...)
					end

				elseif remote:IsA("RemoteEvent") then
					local re = remote :: RemoteEvent
					local toServer = serviceFolder:FindFirstChild(remote.Name .. "_toServer") :: RemoteEvent?

					proxy[remote.Name] = {
						_isSignal = true,
						Connect = function(_: any, fn: (...any) -> ())
							return re.OnClientEvent:Connect(fn)
						end,
						Once = function(_: any, fn: (...any) -> ())
							return re.OnClientEvent:Once(fn)
						end,
						Fire = function(_: any, ...)
							if toServer then
								toServer:FireServer(...)
							else
								warn("[Zenith] No server-bound remote for " .. remote.Name)
							end
						end,
					}
				end
			end

			serverProxies[serviceFolder.Name] = proxy
		end

		log:Info("Client bridge connected.")
		resolve()
	end)
end

function Zenith.Start(): Promise.Promise
	assert(not started, "Zenith has already been started.")
	started = true

	log:Info("Starting on " .. (IS_SERVER and "Server" or "Client") .. "...")

	local startPromise: Promise.Promise

	if IS_SERVER then
		setupServerBridge()
		startPromise = runLifecycle(services)
	else
		startPromise = setupClientBridge():andThen(function()
			return runLifecycle(controllers)
		end)
	end

	startPromise:andThen(function()
		isReady = true
		readySignal:Fire()
		log:Info("Zenith is running.")
	end)

	startPromise:catch(function(err)
		log:Error("Zenith failed to start: " .. tostring(err))
	end)

	return startPromise
end

function Zenith.Destroy()
	frameworkTrove:Clean()
	readySignal:DisconnectAll()
	isReady = false
	started = false
	table.clear(services)
	table.clear(controllers)
	table.clear(serverProxies)
	log:Info("Zenith destroyed.")
end

Zenith.Signal = Signal
Zenith.Logger = Logger
Zenith.Middleware = Middleware
Zenith.Promise = Promise
Zenith.Trove = Trove

return Zenith
