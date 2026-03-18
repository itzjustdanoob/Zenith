# Zenith

A lightweight, structured Roblox game framework written in Luau. Zenith provides a clean architecture for building scalable games with services, controllers, middleware, and a first-class client–server communication bridge.

---

## Features

- **Services & Controllers** — Server-side services and client-side controllers with lifecycle hooks (`OnInit`, `OnStart`, `OnHeartbeat`, `OnStepped`, `OnRenderStepped`)
- **Dependency Resolution** — Topological sort with circular dependency detection
- **Client–Server Bridge** — Automatic `RemoteFunction` / `RemoteEvent` generation from service `.Client` tables, zero boilerplate
- **Middleware Pipeline** — Global and per-method pre/post middleware with built-in `RateLimit`, `RequireAuth`, `Log`, and `Cache` helpers
- **Signal** — Typed, allocation-efficient signal implementation with `Connect`, `Once`, `Wait`, and `DisconnectAll`
- **Promise** — Lightweight promise implementation supporting `andThen`, `catch`, `finally`, and `await`
- **Trove** — Connection and instance lifecycle manager to prevent memory leaks
- **Logger** — Scoped, levelled logging (`DEBUG`, `INFO`, `WARN`, `ERROR`)

---

## Installation

### Wally (recommended)

Add Zenith to your `wally.toml`:

```toml
[dependencies]
Zenith = "yourusername/zenith@0.1.0"
```

Then run:

```sh
wally install
```

### Manual

Copy the `src/` folder into your project and require `Zenith.luau` from your scripts.

---

## Quick Start

### Server (Script)

```lua
local Zenith = require(path.to.Zenith)

local MyService = Zenith.CreateService({
    Name = "MyService",
    Client = {},
})

function MyService:OnInit()
    print("MyService initialised!")
end

function MyService:OnStart()
    print("MyService started!")
end

function MyService.Client:GetMessage(player)
    return "Hello, " .. player.Name
end

Zenith.Start():andThen(function()
    print("Server is running.")
end)
```

### Client (LocalScript)

```lua
local Zenith = require(path.to.Zenith)

local MyController = Zenith.CreateController({
    Name = "MyController",
})

function MyController:OnInit()
    local MyService = Zenith.Get("MyService")
    local msg = MyService:GetMessage()
    print(msg)
end

Zenith.Start()
```

---

## Middleware

```lua
-- Global rate limiting
Zenith.Middleware.AddGlobal(
    Zenith.Middleware.RateLimit(10, 1) -- 10 calls per second
)

-- Auth guard on a specific method
Zenith.Middleware.AddForMethod("MyService", "AdminAction",
    Zenith.Middleware.RequireAuth(function(player)
        return player:GetRankInGroup(12345) >= 100
    end)
)
```

---

## Lifecycle Hooks

| Hook | Context | Description |
|---|---|---|
| `OnInit` | Server & Client | Called sequentially in dependency order. Errors halt startup. |
| `OnStart` | Server & Client | Called concurrently after all `OnInit` complete. |
| `OnHeartbeat(dt)` | Server & Client | Runs every `RunService.Heartbeat`. |
| `OnStepped(t, dt)` | Server & Client | Runs every `RunService.Stepped`. |
| `OnRenderStepped(dt)` | Client only | Runs every `RunService.RenderStepped`. |

---

## API Reference

### Zenith

| Method | Description |
|---|---|
| `Zenith.CreateService(config)` | Register a server-side service |
| `Zenith.CreateController(config)` | Register a client-side controller |
| `Zenith.Get(name)` | Retrieve a service or controller by name |
| `Zenith.Start()` | Start the framework, returns a Promise |
| `Zenith.OnStart(fn)` | Run a callback once Zenith is ready |
| `Zenith.WaitUntilReady()` | Yield until Zenith has fully started |
| `Zenith.Destroy()` | Tear down the framework and clean up all connections |

---

## License

MIT — see [LICENSE](LICENSE).
