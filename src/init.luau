local Signal = require(script.Signal)
local Janitor = require(script.Janitor)
local Net = require(script.Net)

local Zenith = {
	Signal = Signal,
	Janitor = Janitor,
	Net = Net,
}

local registry = {}
local order = {}
local started = false
local ready = false
local readySignal = Signal.new()

function Zenith.register(name, module)
	assert(not started, "Zenith: register modules before calling start")
	assert(registry[name] == nil, `Zenith: "{name}" is already registered`)
	registry[name] = module
	table.insert(order, name)
	return module
end

function Zenith.load(container, deep)
	local children = if deep then container:GetDescendants() else container:GetChildren()
	for _, child in children do
		if child:IsA("ModuleScript") then
			Zenith.register(child.Name, require(child))
		end
	end
end

function Zenith.get(name)
	local module = registry[name]
	if module == nil then
		error(`Zenith: nothing registered as "{name}"`, 2)
	end
	return module
end

function Zenith.start()
	assert(not started, "Zenith: already started")
	started = true

	for _, name in order do
		local module = registry[name]
		if type(module) == "table" and type(module.Init) == "function" then
			module:Init()
		end
	end

	for _, name in order do
		local module = registry[name]
		if type(module) == "table" and type(module.Start) == "function" then
			task.spawn(module.Start, module)
		end
	end

	ready = true
	readySignal:Fire()
end

function Zenith.onStart()
	if not ready then
		readySignal:Wait()
	end
end

return Zenith
