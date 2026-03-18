local Trove = {}
Trove.__index = Trove

type Cleanable =
	RBXScriptConnection
	| { Destroy: (self: any) -> () }
	| { Disconnect: (self: any) -> () }
	| thread
	| () -> ()

function Trove.new()
	return setmetatable({
		_items = {} :: { Cleanable },
		_cleaned = false,
	}, Trove)
end

function Trove:Add<T>(item: T): T
	assert(not self._cleaned, "Cannot add to a cleaned Trove.")

	local t = typeof(item)

	if t == "RBXScriptConnection" then
		table.insert(self._items, item)
	elseif t == "function" then
		table.insert(self._items, item)
	elseif t == "thread" then
		table.insert(self._items, item)
	elseif t == "table" then
		assert(
			type((item :: any).Destroy) == "function" or type((item :: any).Disconnect) == "function",
			"Table added to Trove must have a Destroy or Disconnect method."
		)
		table.insert(self._items, item)
	else
		error("Cannot add type '" .. t .. "' to Trove.")
	end

	return item
end

function Trove:Connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(fn))
end

function Trove:BindToInstance(instance: Instance): Trove
	self:Add(instance.Destroying:Connect(function()
		self:Clean()
	end))
	return self
end

function Trove:Extend(): Trove
	local child = Trove.new()
	self:Add(child)
	return child
end

function Trove:Clean()
	if self._cleaned then return end
	self._cleaned = true

	for i = #self._items, 1, -1 do
		local item = self._items[i]
		local t = typeof(item)

		if t == "RBXScriptConnection" then
			(item :: RBXScriptConnection):Disconnect()
		elseif t == "function" then
			(item :: () -> ())()
		elseif t == "thread" then
			task.cancel(item :: thread)
		elseif t == "table" then
			local asTable = item :: any
			if type(asTable.Destroy) == "function" then
				asTable:Destroy()
			elseif type(asTable.Disconnect) == "function" then
				asTable:Disconnect()
			end
		end
	end

	table.clear(self._items)
end

Trove.Destroy = Trove.Clean
Trove.Disconnect = Trove.Clean

return Trove
