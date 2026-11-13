-- Zenith: loads your modules, runs Init and Start on them, and hands out
-- the little helpers (Net, Signal, Janitor).

local Signal = require(script.Signal)
local Net = require(script.Net)
local Janitor = require(script.Janitor)

local Zenith = {}
Zenith.Signal = Signal
Zenith.Net = Net
Zenith.Janitor = Janitor

local modules = {} -- name -> module table
local order = {}   -- names, in the order they were registered
local started = false
local ready = false
local readySignal = Signal.new()

function Zenith.register(name, module)
    assert(type(name) == "string", "Zenith.register needs a name")
    assert(type(module) == "table", "Zenith.register needs a table for '" .. tostring(name) .. "'")

    if started then
        error("Can't register '" .. name .. "' after Zenith.start() already ran", 2)
    end

    if modules[name] then
        error(("Zenith: there's already a module called '%s'. Rename one, or give it another name with Zenith.register(name, module)."):format(name), 2)
    end

    modules[name] = module
    table.insert(order, name)
end

-- requires every ModuleScript in the container. Pass true as the second
-- argument to also include everything nested inside folders.
function Zenith.load(container, deep)
    local children = if deep then container:GetDescendants() else container:GetChildren()

    -- sorted so the order is the same every run
    table.sort(children, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    for _, child in children do
        if child:IsA("ModuleScript") then
            local ok, result = pcall(require, child)
            if not ok then
                error(("Zenith: couldn't require %s:\n%s"):format(child:GetFullName(), tostring(result)), 2)
            end
            if type(result) ~= "table" then
                error(("Zenith: %s has to return a table, got %s"):format(child:GetFullName(), typeof(result)), 2)
            end

            Zenith.register(child.Name, result)
        end
    end
end

function Zenith.get(name)
    local module = modules[name]
    if not module then
        error(("Zenith: no module called '%s'"):format(name), 2)
    end
    return module
end

local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

-- Runs Init on everything one at a time, then Start on everything in its own thread.
-- If a module errors it gets logged and skipped, the rest keep going.
function Zenith.start()
    if started then
        warn("Zenith.start() was already called")
        return
    end
    started = true

    local failed = {}

    for _, name in order do
        local module = modules[name]
        if type(module.Init) == "function" then
            local ok, err = xpcall(module.Init, traceback, module)
            if not ok then
                failed[name] = true
                warn(("Zenith: %s:Init() failed, skipping it.\n%s"):format(name, err))
            end
        end
    end

    for _, name in order do
        local module = modules[name]
        if not failed[name] and type(module.Start) == "function" then
            task.spawn(function()
                local ok, err = xpcall(module.Start, traceback, module)
                if not ok then
                    warn(("Zenith: %s:Start() failed.\n%s"):format(name, err))
                end
            end)
        end
    end

    -- "ready" means every Init finished and every Start has been kicked off
    -- (each one ran until it finished or first yielded). It doesn't wait for
    -- Start functions to return, since some of them loop forever on purpose.
    ready = true
    readySignal:Fire()
end

-- yields until start() is done
function Zenith.onStart()
    if ready then
        return
    end
    readySignal:Wait()
end

return Zenith