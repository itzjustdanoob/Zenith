local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn: (...any) -> ())
	return setmetatable({
		_signal = signal,
		_fn = fn,
		Connected = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then return end
	self.Connected = false

	local list = self._signal._connections
	for i = #list, 1, -1 do
		if list[i] == self then
			table.remove(list, i)
			break
		end
	end
end

function Signal.new()
	return setmetatable({
		_connections = {},
		_isSignal = true,
	}, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	assert(type(fn) == "function", "Connect expects a function.")
	local conn = Connection.new(self, fn)
	table.insert(self._connections, conn)
	return conn
end

function Signal:Once(fn: (...any) -> ())
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...: any)
	local connections = table.clone(self._connections)
	for _, conn in ipairs(connections) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal:Wait(timeout: number?): (any, boolean)
	local thread = coroutine.running()
	local conn
	local done = false

	conn = self:Once(function(...)
		if done then return end
		done = true
		task.spawn(thread, false, ...)
	end)

	if timeout then
		task.delay(timeout, function()
			if done then return end
			done = true
			conn:Disconnect()
			task.spawn(thread, true)
		end)
	end

	local timedOut, result = coroutine.yield()
	if timedOut then
		return nil, true
	end
	return result, false
end

function Signal:DisconnectAll()
	for _, conn in ipairs(self._connections) do
		conn.Connected = false
	end
	table.clear(self._connections)
end

function Signal:Destroy()
	self:DisconnectAll()
end

function Signal:GetConnectionCount(): number
	return #self._connections
end

return Signal
