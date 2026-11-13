local function dispose(item)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		task.cancel(item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({ _items = {} }, Janitor)
end

function Janitor:Add(item)
	table.insert(self._items, item)
	return item
end

function Janitor:Connect(signal, handler)
	return self:Add(signal:Connect(handler))
end

function Janitor:Cleanup()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		dispose(items[index])
	end
end

Janitor.Destroy = Janitor.Cleanup

return Janitor
