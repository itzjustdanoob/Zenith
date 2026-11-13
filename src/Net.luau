local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local isServer = RunService:IsServer()
local FOLDER_NAME = "ZenithNet"

local function getFolder()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		return folder
	end
	if not isServer then
		return ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function getRemote(className, name)
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end
	if not isServer then
		return folder:WaitForChild(name)
	end
	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

local ServerEvent = {}
ServerEvent.__index = ServerEvent

function ServerEvent.new(name)
	local self = setmetatable({
		_remote = getRemote("RemoteEvent", name),
		_hits = {},
		_limit = nil,
	}, ServerEvent)
	Players.PlayerRemoving:Connect(function(player)
		self._hits[player] = nil
	end)
	return self
end

function ServerEvent:Limit(perSecond)
	self._limit = perSecond
	return self
end

function ServerEvent:_allow(player)
	if not self._limit then
		return true
	end
	local now = os.clock()
	local entry = self._hits[player]
	if not entry or now - entry.start >= 1 then
		self._hits[player] = { start = now, count = 1 }
		return true
	end
	entry.count += 1
	return entry.count <= self._limit
end

function ServerEvent:Connect(handler)
	return self._remote.OnServerEvent:Connect(function(player, ...)
		if self:_allow(player) then
			handler(player, ...)
		end
	end)
end

function ServerEvent:Fire(player, ...)
	self._remote:FireClient(player, ...)
end

function ServerEvent:FireAll(...)
	self._remote:FireAllClients(...)
end

function ServerEvent:FireExcept(excluded, ...)
	for _, player in Players:GetPlayers() do
		if player ~= excluded then
			self._remote:FireClient(player, ...)
		end
	end
end

local ClientEvent = {}
ClientEvent.__index = ClientEvent

function ClientEvent.new(name)
	return setmetatable({ _remote = getRemote("RemoteEvent", name) }, ClientEvent)
end

function ClientEvent:Connect(handler)
	return self._remote.OnClientEvent:Connect(handler)
end

function ClientEvent:Fire(...)
	self._remote:FireServer(...)
end

local ServerFunction = {}
ServerFunction.__index = ServerFunction

function ServerFunction.new(name)
	return setmetatable({ _remote = getRemote("RemoteFunction", name) }, ServerFunction)
end

function ServerFunction:Handle(handler)
	self._remote.OnServerInvoke = handler
end

local ClientFunction = {}
ClientFunction.__index = ClientFunction

function ClientFunction.new(name)
	return setmetatable({ _remote = getRemote("RemoteFunction", name) }, ClientFunction)
end

function ClientFunction:Invoke(...)
	return self._remote:InvokeServer(...)
end

local EventClass = if isServer then ServerEvent else ClientEvent
local FunctionClass = if isServer then ServerFunction else ClientFunction

local events = {}
local functions = {}

local Net = {}

function Net.Event(name)
	local event = events[name]
	if not event then
		event = EventClass.new(name)
		events[name] = event
	end
	return event
end

function Net.Function(name)
	local fn = functions[name]
	if not fn then
		fn = FunctionClass.new(name)
		functions[name] = fn
	end
	return fn
end

return Net
