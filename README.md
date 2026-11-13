# Zenith

A small Luau framework for Roblox. It gives you a module loader with a simple lifecycle, clean networking, signals, and a cleanup helper. That's it. No dependencies, around 300 lines total.

I built it because most frameworks do way more than I need. Zenith does the boring plumbing and stays out of the way.

## Install

**Wally**

```toml
[dependencies]
Zenith = "itzjustdanoob/zenith@0.2.0"
```

**Rojo**

Clone the repo and sync `default.project.json`. Put the result in `ReplicatedStorage` so both server and client can require it.

## Quick start

Server bootstrap (a Script in `ServerScriptService`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(ServerScriptService.Services)
Zenith.start()
```

Client bootstrap (a LocalScript in `StarterPlayerScripts`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Zenith = require(ReplicatedStorage.Zenith)

Zenith.load(Players.LocalPlayer.PlayerScripts.Controllers)
Zenith.start()
```

Every ModuleScript in the folder gets registered under its name. When you call `start`, Zenith runs `Init` on all of them first, then `Start` on all of them in separate threads. Use `Init` to set things up and `Start` for anything that talks to other modules.

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
	Players.PlayerAdded:Connect(function(player)
		self.balances[player] = 0
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
- `Zenith.get(name)` returns a registered module or errors if it doesn't exist.
- `Zenith.start()` runs `Init` then `Start` on everything registered.
- `Zenith.onStart()` yields until startup has finished.

### Net

Same code on both sides. The server creates the remotes, the client finds them.

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

The server can't invoke the client on purpose. Yielding on a client that might never answer is a good way to hang a thread.

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

Collect things, clean them up in one go. It handles functions, connections, instances, threads, and anything with `Destroy` or `Disconnect`.

```lua
local janitor = Zenith.Janitor.new()

janitor:Add(Instance.new("Part"))
janitor:Connect(workspace.ChildAdded, handler)
janitor:Add(function()
	print("gone")
end)

janitor:Cleanup()
```

Items are cleaned in reverse order, last added first.

## License

MIT
