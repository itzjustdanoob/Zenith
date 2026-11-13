# Zenith

A small Luau framework for Roblox. It gives you a module loader with a simple lifecycle, networking that doesn't get in your way, signals, and a cleanup helper. No dependencies, around 300 lines total.

I built it because most frameworks do far more than I need. Zenith handles the boring plumbing and then stays out of the way.

## Install

Clone the repo and sync `default.project.json` with Rojo, or just copy the `src` folder into Studio and rename it `Zenith`. Put it in `ReplicatedStorage` so both the server and the client can require it.

## Quick start

Server (a Script in `ServerScriptService`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(ServerScriptService.Services)
Zenith.start()
```

Client (a LocalScript in `StarterPlayerScripts`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(Players.LocalPlayer.PlayerScripts.Controllers)
Zenith.start()
```

Every ModuleScript in the folder gets registered under its name. When you call `start`, Zenith runs `Init` on all of them first, then `Start` on all of them in separate threads.

Use `Init` to set up your own stuff. Use `Start` for anything that talks to other modules. Don't count on the order modules load in, so don't call `Zenith.get` inside `Init` and expect the other module to be ready.

A service looks like this:

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

    -- catch anyone who joined before Start ran
    for _, player in Players:GetPlayers() do
        setup(player)
    end

    -- don't leak balances when people leave
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

Grab another module with `Zenith.get("Coins")`.

## API

### Zenith

- `Zenith.load(container, deep)` requires every ModuleScript in `container` and registers it. Pass `true` to include descendants.
- `Zenith.register(name, module)` registers a module by hand.
- `Zenith.get(name)` returns a registered module, or errors if it doesn't exist.
- `Zenith.start()` runs `Init`, then `Start`, on everything registered.
- `Zenith.onStart()` yields until startup has finished.

### Net

Same code on both sides. The server creates the remotes and the client finds them.

```lua
local Net = Zenith.Net

local Damage = Net.Event("Damage")

Damage:Connect(function(player, targetId)
end)

Damage:Fire(targetId)
```

Server only:

- `event:Fire(player, ...)`
- `event:FireAll(...)`
- `event:FireExcept(player, ...)`
- `event:Limit(perSecond)` drops events from a player who sends more than that per second.

Client only:

- `event:Fire(...)`

Both:

- `event:Connect(handler)`

Functions:

```lua
Net.Function("GetStats"):Handle(function(player)
    return { coins = 10 }
end)

local stats = Net.Function("GetStats"):Invoke()
```

The server can't invoke the client, on purpose. Yielding on a client that might never answer is a good way to hang a thread.

### Signal

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

### Janitor

Collect things, then clean them all up in one go. It handles functions, connections, instances, threads, and anything with `Destroy` or `Disconnect`.

```lua
local janitor = Zenith.Janitor.new()

janitor:Add(Instance.new("Part"))
janitor:Connect(workspace.ChildAdded, handler)
janitor:Add(function()
    print("gone")
end)

janitor:Cleanup()
```

Items are cleaned up in reverse order, last added first.

## Contributing

Found a bug or want something added? Open an issue or a pull request. Small and focused changes are easiest to review.

## License

MIT