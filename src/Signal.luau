-- Signal: a small event class.
-- Handlers each run in their own thread (task.spawn), so one slow handler
-- doesn't hold up the others and the order they finish in isn't guaranteed.

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
    if not self.Connected then
        return
    end
    self.Connected = false

    local connections = self._signal._connections
    local index = table.find(connections, self)
    if index then
        table.remove(connections, index)
    end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        _connections = {},
        _waiting = {},
        _destroyed = false,
    }, Signal)
end

function Signal:Connect(handler)
    assert(type(handler) == "function", "Signal:Connect expects a function")
    assert(not self._destroyed, "Can't connect to a destroyed Signal")

    local connection = setmetatable({
        Connected = true,
        _signal = self,
        _handler = handler,
    }, Connection)

    table.insert(self._connections, connection)
    return connection
end

function Signal:Once(handler)
    assert(type(handler) == "function", "Signal:Once expects a function")

    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        handler(...)
    end)
    return connection
end

function Signal:Fire(...)
    if self._destroyed then
        return
    end

    -- work on a copy so a handler disconnecting itself can't skip anyone
    for _, connection in table.clone(self._connections) do
        if connection.Connected then
            task.spawn(connection._handler, ...)
        end
    end

    -- wake up anything sitting in :Wait()
    local waiting = self._waiting
    if #waiting > 0 then
        self._waiting = {}
        for _, thread in waiting do
            task.spawn(thread, ...)
        end
    end
end

function Signal:Wait()
    assert(not self._destroyed, "Can't Wait on a destroyed Signal")

    table.insert(self._waiting, coroutine.running())
    return coroutine.yield()
end

-- drops every connection, but the signal still works afterwards
function Signal:DisconnectAll()
    for _, connection in self._connections do
        connection.Connected = false
    end
    self._connections = {}
end

-- closes the signal for good. Anything stuck in :Wait() gets woken up
-- (with no values) instead of hanging forever.
function Signal:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true

    self:DisconnectAll()

    local waiting = self._waiting
    self._waiting = {}
    for _, thread in waiting do
        task.spawn(thread)
    end
end

return Signal