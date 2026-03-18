local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Logger)
local Trove = require(script.Parent.Trove)
local Types = require(script.Parent.Types)

type ComponentConfig = Types.ComponentConfig

local Component = {}
Component.__index = Component

local log = Logger.new("Component")
local tagRegistry: { [string]: any } = {}

function Component.new(config: ComponentConfig)
	assert(type(config.Tag) == "string" and #config.Tag > 0, "Component tag must be a non-empty string.")
	assert(not tagRegistry[config.Tag], "A component with tag '" .. config.Tag .. "' already exists.")

	local self = setmetatable({}, Component)
	self._tag = config.Tag
	self._ancestors = config.Ancestors or { game }
	self._rateLimit = config.RateLimit or 0
	self._instances = {} :: { [Instance]: any }
	self._trove = Trove.new()
	self._started = false

	tagRegistry[config.Tag] = self
	return self
end

function Component.GetFromTag(tag: string): any?
	return tagRegistry[tag]
end

function Component:_isValidAncestor(instance: Instance): boolean
	for _, ancestor in ipairs(self._ancestors) do
		if instance:IsDescendantOf(ancestor) then
			return true
		end
	end
	return false
end

function Component:_attach(instance: Instance)
	if self._instances[instance] then return end
	if not self:_isValidAncestor(instance) then return end

	local instanceTrove = Trove.new()

	local obj = {
		instance = instance,
		trove = instanceTrove,
		_state = {},
	}

	for k, v in pairs(self) do
		if type(v) == "function" and not k:sub(1, 1) == "_" then
			obj[k] = v
		end
	end

	setmetatable(obj, {
		__index = function(_, key)
			local val = self[key]
			if type(val) == "function" then
				return function(s, ...)
					return val(s, ...)
				end
			end
			return val
		end,
	})

	self._instances[instance] = obj

	instanceTrove:BindToInstance(instance)
	instanceTrove:Add(function()
		self:_detach(instance)
	end)

	if type(self.OnStart) == "function" then
		local ok, err = pcall(self.OnStart, obj)
		if not ok then
			log:Error("OnStart failed on '" .. instance:GetFullName() .. "': " .. tostring(err))
			instanceTrove:Clean()
			self._instances[instance] = nil
			return
		end
	end

	if type(self.OnAttributeChanged) == "function" then
		instanceTrove:Connect(instance.AttributeChanged, function(attr: string)
			self.OnAttributeChanged(obj, attr, instance:GetAttribute(attr))
		end)
	end

	log:Debug("Attached '" .. self._tag .. "' to " .. instance.Name)
end

function Component:_detach(instance: Instance)
	local obj = self._instances[instance]
	if not obj then return end

	self._instances[instance] = nil

	if type(self.OnStop) == "function" then
		local ok, err = pcall(self.OnStop, obj)
		if not ok then
			log:Error("OnStop failed on '" .. instance:GetFullName() .. "': " .. tostring(err))
		end
	end

	if obj.trove then
		obj.trove._cleaned = false
		obj.trove:Clean()
	end

	table.clear(obj._state)
	log:Debug("Detached '" .. self._tag .. "' from " .. instance.Name)
end

function Component:Start()
	assert(not self._started, "Component '" .. self._tag .. "' is already started.")
	self._started = true

	for _, instance in ipairs(CollectionService:GetTagged(self._tag)) do
		task.spawn(function()
			self:_attach(instance)
		end)
	end

	self._trove:Connect(CollectionService:GetInstanceAddedSignal(self._tag), function(instance: Instance)
		task.defer(function()
			self:_attach(instance)
		end)
	end)

	self._trove:Connect(CollectionService:GetInstanceRemovedSignal(self._tag), function(instance: Instance)
		self:_detach(instance)
	end)

	if type(self.OnHeartbeat) == "function" then
		local acc = 0
		self._trove:Connect(RunService.Heartbeat, function(dt: number)
			acc += dt
			if self._rateLimit > 0 and acc < self._rateLimit then return end
			acc = 0
			for _, obj in pairs(self._instances) do
				task.spawn(function()
					local ok, err = pcall(self.OnHeartbeat, obj, dt)
					if not ok then
						log:Error("OnHeartbeat error in '" .. self._tag .. "': " .. tostring(err))
					end
				end)
			end
		end)
	end

	log:Info("Component '" .. self._tag .. "' started.")
end

function Component:Stop()
	assert(self._started, "Component '" .. self._tag .. "' is not running.")
	self._started = false

	for instance in pairs(table.clone(self._instances)) do
		self:_detach(instance)
	end

	self._trove:Clean()
	tagRegistry[self._tag] = nil
	log:Info("Component '" .. self._tag .. "' stopped.")
end

function Component:GetAll(): { any }
	local list = {}
	for _, obj in pairs(self._instances) do
		table.insert(list, obj)
	end
	return list
end

function Component:GetFromInstance(instance: Instance): any?
	return self._instances[instance]
end

return Component
