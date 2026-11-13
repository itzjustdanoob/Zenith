-- Net: remotes that look the same on the server and the client.
-- The server creates them, the client waits for them to show up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "ZenithNet"
local CLIENT_TIMEOUT = 10 -- how long the client waits for a remote before erroring

-- events and functions get different prefixes so Event("X") and Function("X") can't collide
local PREFIX = {
    RemoteEvent = "Event_",
    RemoteFunction = "Function_",
}

local Net = {}

local events = {}
local functions = {}
local limited = {} -- everything on the server that has a rate limit bucket
local folder

local function getFolder()
    if folder then
        return folder
    end

    if IS_SERVER then
        folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = FOLDER_NAME
            folder.Parent = ReplicatedStorage
        end
    else
        folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT)
        if not folder then
            error("Net: the server never made the " .. FOLDER_NAME .. " folder. Is the server running Zenith?", 3)
        end
    end

    return folder
end

local function getRemote(className, name)
    local parent = getFolder()
    local remoteName = PREFIX[className] .. name
    local remote

    if IS_SERVER then
        remote = parent:FindFirstChild(remoteName)
        if not remote then
            remote = Instance.new(className)
            remote.Name = remoteName
            remote.Parent = parent
        end
    else
        remote = parent:WaitForChild(remoteName, CLIENT_TIMEOUT)
        if not remote then
            error(("Net: the server never created %s '%s'. Check the name for typos and make sure the server creates it."):format(className, name), 3)
        end
    end

    if not remote:IsA(className) then
        error(("Net: '%s' exists but it's a %s, not a %s"):format(name, remote.ClassName, className), 3)
    end

    return remote
end

-- rate limiting: a fixed one second window per player.
-- It's checked once per incoming request, no matter how many handlers are connected.
local function setLimit(self, perSecond)
    assert(type(perSecond) == "number" and perSecond > 0, "Limit expects a number above 0")
    self._limit = perSecond
    return self
end

local function allow(self, player)
    local limit = self._limit
    if not limit then
        return true
    end

    local now = os.clock()
    local bucket = self._buckets[player]

    if not bucket or now - bucket.start >= 1 then
        self._buckets[player] = { start = now, count = 1 }
        return true
    end

    bucket.count += 1
    return bucket.count <= limit
end

if IS_SERVER then
    Players.PlayerRemoving:Connect(function(player)
        for _, object in limited do
            object._buckets[player] = nil
        end
    end)
end

-- events

local ServerEvent = {}
ServerEvent.__index = ServerEvent
ServerEvent.Limit = setLimit

function ServerEvent:Connect(handler)
    return self._signal:Connect(handler)
end

function ServerEvent:Fire(player, ...)
    self._remote:FireClient(player, ...)
end

function ServerEvent:FireAll(...)
    self._remote:FireAllClients(...)
end

function ServerEvent:FireExcept(except, ...)
    for _, player in Players:GetPlayers() do
        if player ~= except then
            self._remote:FireClient(player, ...)
        end
    end
end

local function newServerEvent(name)
    local remote = getRemote("RemoteEvent", name)
    local self = setmetatable({
        _remote = remote,
        _signal = Signal.new(),
        _buckets = {},
    }, ServerEvent)

    table.insert(limited, self)

    -- one listener on the remote, then hand it to every handler
    remote.OnServerEvent:Connect(function(player, ...)
        if allow(self, player) then
            self._signal:Fire(player, ...)
        end
    end)

    return self
end

local ClientEvent = {}
ClientEvent.__index = ClientEvent

function ClientEvent:Connect(handler)
    return self._signal:Connect(handler)
end

function ClientEvent:Fire(...)
    self._remote:FireServer(...)
end

local function newClientEvent(name)
    local remote = getRemote("RemoteEvent", name)
    local self = setmetatable({
        _remote = remote,
        _signal = Signal.new(),
    }, ClientEvent)

    remote.OnClientEvent:Connect(function(...)
        self._signal:Fire(...)
    end)

    return self
end

function Net.Event(name)
    assert(type(name) == "string", "Net.Event expects a name")

    local existing = events[name]
    if existing then
        return existing
    end

    local object = if IS_SERVER then newServerEvent(name) else newClientEvent(name)
    events[name] = object
    return object
end

-- functions

local ServerFunction = {}
ServerFunction.__index = ServerFunction
ServerFunction.Limit = setLimit

function ServerFunction:Handle(handler)
    assert(type(handler) == "function", "Handle expects a function")

    if self._handler then
        error(("Net.Function('%s') already has a handler"):format(self._name), 2)
    end
    self._handler = handler

    self._remote.OnServerInvoke = function(player, ...)
        if not allow(self, player) then
            return nil
        end
        return handler(player, ...)
    end
end

function ServerFunction:Invoke()
    error("The server can't invoke the client. Yielding on a client that might never answer can hang a thread.", 2)
end

local function newServerFunction(name)
    local self = setmetatable({
        _name = name,
        _remote = getRemote("RemoteFunction", name),
        _buckets = {},
    }, ServerFunction)

    table.insert(limited, self)
    return self
end

local ClientFunction = {}
ClientFunction.__index = ClientFunction

function ClientFunction:Invoke(...)
    return self._remote:InvokeServer(...)
end

function ClientFunction:Handle()
    error("Only the server can handle a Net.Function", 2)
end

local function newClientFunction(name)
    return setmetatable({
        _name = name,
        _remote = getRemote("RemoteFunction", name),
    }, ClientFunction)
end

function Net.Function(name)
    assert(type(name) == "string", "Net.Function expects a name")

    local existing = functions[name]
    if existing then
        return existing
    end

    local object = if IS_SERVER then newServerFunction(name) else newClientFunction(name)
    functions[name] = object
    return object
end

return Net