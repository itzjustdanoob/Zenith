# zenith

a small luau framework for roblox. it loads your modules, runs init and start on them, and comes with a few helpers for networking, signals and cleanup. no dependencies.

i made it because most frameworks do way more than i need. zenith handles the boring plumbing and then gets out of the way.

## install

clone the repo and sync `default.project.json` with rojo, or just copy the `src` folder into studio and rename it `Zenith`. put it in replicatedstorage so both the server and the client can require it.

## quick start

server (a script in serverscriptservice):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(ServerScriptService.Services)
Zenith.start()
```

client (a localscript in starterplayerscripts):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(Players.LocalPlayer.PlayerScripts.Controllers)
Zenith.start()
```

every modulescript in the folder gets registered under its own name. when you call `start`, zenith runs `Init` on all of them one at a time, then runs `Start` on all of them in separate threads. if a module errors, it gets logged and skipped and the rest keep going.

use `Init` to set up your own stuff. use `Start` for anything that talks to other modules. modules load in a fixed order (sorted by name) but dont lean on that, so dont call `Zenith.get` inside `Init` and expect the other module to be ready.

here is what a service looks like:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zenith = require(ReplicatedStorage.Zenith)

local Coins = {}

function Coins:Init()
    self.balances = {}
    self.changed = Zenith.Net.Event("CoinsChanged")
end

function Coins:Start()
    local function setup(player)
        self.balances[player] = 0
    end

    Players.PlayerAdded:Connect(setup)

    -- catch anyone who joined before start ran
    for _, player in Players:GetPlayers() do
        setup(player)
    end

    -- dont leak balances when people leave
    Players.PlayerRemoving:Connect(function(player)
        self.balances[player] = nil
    end)
end

function Coins:Add(player, amount)
    self.balances[player] += amount
    self.changed:Fire(player, self.balances[player])
end

return Coins
```

grab another module any time with `Zenith.get("Coins")`.

## api

### zenith

- `Zenith.load(container, deep)` requires every modulescript in the container and registers it. pass `true` to include everything nested inside folders too.
- `Zenith.register(name, module)` registers a module by hand.
- `Zenith.get(name)` gives you a registered module, or errors if it does not exist.
- `Zenith.start()` runs `Init`, then `Start`, on everything registered.
- `Zenith.onStart()` yields until startup has finished.

### net

the code looks the same on both sides. the server creates the remotes and the client waits for them to show up (it gives up after 10 seconds and errors).

```lua
local Net = Zenith.Net

local Damage = Net.Event("Damage")
```

on the server:

```lua
Damage:Connect(function(player, targetId)
    -- handle it
end)
```

on the client:

```lua
Damage:Fire(targetId)
```

server only:

- `event:Fire(player, ...)`
- `event:FireAll(...)`
- `event:FireExcept(player, ...)`
- `event:Limit(perSecond)` drops events from a player who sends more than that per second.

client only:

- `event:Fire(...)`

both:

- `event:Connect(handler)`

functions:

```lua
-- server
Net.Function("GetStats"):Handle(function(player)
    return { coins = 10 }
end)

-- client
local stats = Net.Function("GetStats"):Invoke()
```

the server cant invoke the client, on purpose. waiting on a client that might never answer is a good way to hang a thread.

one thing to know: if you set a limit on a function and a player goes over it, they get back `nil`. thats the same thing a normal handler could return, so keep that in mind.

### signal

```lua
local changed = Zenith.Signal.new()

local connection = changed:Connect(function(value)
    print(value)
end)

changed:Fire(5)
changed:Once(handler)
changed:Wait()
connection:Disconnect()
changed:Destroy()
```

each handler runs in its own thread, so the order they finish in is not guaranteed.

### janitor

toss stuff in, clean it all up at once. it handles functions, connections, instances, threads, and anything with a `Destroy` or `Disconnect` method.

```lua
local janitor = Zenith.Janitor.new()

janitor:Add(Instance.new("Part"))
janitor:Connect(workspace.ChildAdded, handler)
janitor:Add(function()
    print("gone")
end)

janitor:Cleanup()
```

things get cleaned up in reverse order, last added first. `Cleanup` leaves the janitor usable. `Destroy` cleans up and closes it for good.

## contributing

found a bug or want something added? open an issue or a pull request. small focused changes are the easiest to look at.

## license

mit