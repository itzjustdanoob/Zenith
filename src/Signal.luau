local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(handler)
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_handler = handler,
	}, Connection)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
end

Signal.Destroy = Signal.DisconnectAll

return Signal
