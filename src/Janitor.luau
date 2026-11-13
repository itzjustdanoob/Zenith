-- Janitor: toss stuff in, clean it all up at once.

local function isCleanable(item)
    local kind = typeof(item)

    if kind == "function" or kind == "RBXScriptConnection" or kind == "Instance" or kind == "thread" then
        return true
    end

    if kind == "table" then
        return type(item.Destroy) == "function" or type(item.Disconnect) == "function"
    end

    return false
end

local function dispose(item)
    local kind = typeof(item)

    if kind == "function" then
        item()
    elseif kind == "RBXScriptConnection" then
        item:Disconnect()
    elseif kind == "Instance" then
        item:Destroy()
    elseif kind == "thread" then
        -- cancelling the thread we're running in would error
        if item ~= coroutine.running() then
            task.cancel(item)
        end
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
    return setmetatable({ _items = {}, _destroyed = false }, Janitor)
end

function Janitor:Add(item)
    if not isCleanable(item) then
        error("Janitor:Add doesn't know how to clean up a " .. typeof(item), 2)
    end

    if self._destroyed then
        -- the janitor is already closed, so clean it up right away
        dispose(item)
        return item
    end

    table.insert(self._items, item)
    return item
end

function Janitor:Connect(signal, handler)
    return self:Add(signal:Connect(handler))
end

-- take one item out without cleaning it up
function Janitor:Remove(item)
    local index = table.find(self._items, item)
    if index then
        table.remove(self._items, index)
    end
end

-- clean everything, but the janitor can be used again afterwards
function Janitor:Cleanup()
    -- grab the list first so adding during cleanup doesn't loop forever
    local items = self._items
    self._items = {}

    for index = #items, 1, -1 do
        local ok, err = pcall(dispose, items[index])
        if not ok then
            warn("Janitor: failed to clean up an item: " .. tostring(err))
        end
    end
end

-- clean everything and close the janitor for good
function Janitor:Destroy()
    self:Cleanup()
    self._destroyed = true
end

return Janitor