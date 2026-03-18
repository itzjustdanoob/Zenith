local Promise = {}
Promise.__index = Promise

type Status = "pending" | "resolved" | "rejected"

local function new(executor: ((resolve: (...any) -> (), reject: (err: any) -> ()) -> ()))
	local self = setmetatable({}, Promise)
	self._status = "pending" :: Status
	self._value = nil
	self._err = nil
	self._thenCallbacks = {}
	self._catchCallbacks = {}
	self._finallyCallbacks = {}

	local function resolve(...)
		if self._status ~= "pending" then return end
		self._status = "resolved"
		self._value = { ... }
		for _, fn in ipairs(self._thenCallbacks) do
			task.spawn(fn, ...)
		end
		for _, fn in ipairs(self._finallyCallbacks) do
			task.spawn(fn)
		end
	end

	local function reject(err: any)
		if self._status ~= "pending" then return end
		self._status = "rejected"
		self._err = err
		for _, fn in ipairs(self._catchCallbacks) do
			task.spawn(fn, err)
		end
		for _, fn in ipairs(self._finallyCallbacks) do
			task.spawn(fn)
		end
	end

	task.spawn(function()
		local ok, err = pcall(executor, resolve, reject)
		if not ok then
			reject(err)
		end
	end)

	return self
end

function Promise:andThen(fn: (...any) -> ())
	if self._status == "resolved" then
		task.spawn(fn, table.unpack(self._value))
	elseif self._status == "pending" then
		table.insert(self._thenCallbacks, fn)
	end
	return self
end

function Promise:catch(fn: (err: any) -> ())
	if self._status == "rejected" then
		task.spawn(fn, self._err)
	elseif self._status == "pending" then
		table.insert(self._catchCallbacks, fn)
	end
	return self
end

function Promise:finally(fn: () -> ())
	if self._status ~= "pending" then
		task.spawn(fn)
	else
		table.insert(self._finallyCallbacks, fn)
	end
	return self
end

function Promise:await(): (boolean, ...any)
	if self._status == "resolved" then
		return true, table.unpack(self._value)
	elseif self._status == "rejected" then
		return false, self._err
	end

	local thread = coroutine.running()
	self:andThen(function(...)
		task.spawn(thread, true, ...)
	end)
	self:catch(function(err)
		task.spawn(thread, false, err)
	end)
	return coroutine.yield()
end

local PromiseModule = {}

function PromiseModule.new(executor): typeof(setmetatable({}, Promise))
	return new(executor)
end

function PromiseModule.resolve(...: any)
	local args = { ... }
	return new(function(resolve)
		resolve(table.unpack(args))
	end)
end

function PromiseModule.reject(err: any)
	return new(function(_, reject)
		reject(err)
	end)
end

function PromiseModule.all(promises: { typeof(setmetatable({}, Promise)) })
	return new(function(resolve, reject)
		local results = {}
		local count = 0
		local total = #promises

		if total == 0 then
			resolve()
			return
		end

		for i, p in ipairs(promises) do
			p:andThen(function(...)
				results[i] = { ... }
				count += 1
				if count == total then
					resolve(table.unpack(results))
				end
			end)
			p:catch(function(err)
				reject(err)
			end)
		end
	end)
end

function PromiseModule.fromTask(fn: () -> ()): typeof(setmetatable({}, Promise))
	return new(function(resolve, reject)
		local ok, err = pcall(fn)
		if ok then
			resolve()
		else
			reject(err)
		end
	end)
end

function PromiseModule.delay(seconds: number): typeof(setmetatable({}, Promise))
	return new(function(resolve)
		task.delay(seconds, resolve)
	end)
end

return PromiseModule
