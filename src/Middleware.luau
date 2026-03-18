local Players = game:GetService("Players")
local Types = require(script.Parent.Types)

type MiddlewareContext = Types.MiddlewareContext
type MiddlewareFn = Types.MiddlewareFn

local Middleware = {}
Middleware.__index = Middleware

local globalPre: { MiddlewareFn } = {}
local globalPost: { (ctx: MiddlewareContext) -> () } = {}
local servicePre: { [string]: { [string]: { MiddlewareFn } } } = {}
local servicePost: { [string]: { [string]: { (ctx: MiddlewareContext) -> () } } } = {}
local validators: { [string]: { [string]: (player: Player, args: { any }) -> (boolean, string?) } } = {}

local rateLimitData: { [Player]: { [string]: { count: number, resetTime: number } } } = {}

Players.PlayerRemoving:Connect(function(player)
	rateLimitData[player] = nil
end)

local function buildPipeline(fns: { MiddlewareFn }, ctx: MiddlewareContext)
	local index = 0
	local function next()
		index += 1
		local fn = fns[index]
		if fn and not ctx.cancelled then
			fn(ctx, next)
		end
	end
	return next
end

local function collect(registry: { [string]: { [string]: { MiddlewareFn } } }, service: string, method: string): { MiddlewareFn }
	local out = {}
	local svc = registry[service]
	if svc then
		if svc["*"] then
			for _, fn in ipairs(svc["*"]) do table.insert(out, fn) end
		end
		if svc[method] then
			for _, fn in ipairs(svc[method]) do table.insert(out, fn) end
		end
	end
	return out
end

function Middleware.AddGlobal(fn: MiddlewareFn)
	assert(type(fn) == "function", "Middleware must be a function.")
	table.insert(globalPre, fn)
end

function Middleware.AddGlobalPost(fn: (ctx: MiddlewareContext) -> ())
	assert(type(fn) == "function", "Post middleware must be a function.")
	table.insert(globalPost, fn)
end

function Middleware.AddForService(service: string, fn: MiddlewareFn)
	assert(type(fn) == "function", "Middleware must be a function.")
	servicePre[service] = servicePre[service] or {}
	servicePre[service]["*"] = servicePre[service]["*"] or {}
	table.insert(servicePre[service]["*"], fn)
end

function Middleware.AddForMethod(service: string, method: string, fn: MiddlewareFn)
	assert(type(fn) == "function", "Middleware must be a function.")
	servicePre[service] = servicePre[service] or {}
	servicePre[service][method] = servicePre[service][method] or {}
	table.insert(servicePre[service][method], fn)
end

function Middleware.AddPostForMethod(service: string, method: string, fn: (ctx: MiddlewareContext) -> ())
	assert(type(fn) == "function", "Post middleware must be a function.")
	servicePost[service] = servicePost[service] or {}
	servicePost[service][method] = servicePost[service][method] or {}
	table.insert(servicePost[service][method], fn)
end

function Middleware.SetValidator(service: string, method: string, fn: (player: Player, args: { any }) -> (boolean, string?))
	assert(type(fn) == "function", "Validator must be a function.")
	validators[service] = validators[service] or {}
	validators[service][method] = fn
end

function Middleware._runServerMiddleware(service: string, method: string, args: { any }): (boolean, { any }?, any?)
	local player = args[1]

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		warn("[Zenith] Rejected call to " .. service .. "." .. method .. ": first argument is not a Player.")
		return false, nil, nil
	end

	local validator = validators[service] and validators[service][method]
	if validator then
		local clientArgs = { table.unpack(args, 2) }
		local ok, reason = validator(player, clientArgs)
		if not ok then
			warn("[Zenith] Validation failed for " .. player.Name .. " -> " .. service .. "." .. method .. ": " .. (reason or "no reason"))
			return false, nil, nil
		end
	end

	local pipeline: { MiddlewareFn } = {}
	for _, fn in ipairs(globalPre) do table.insert(pipeline, fn) end
	for _, fn in ipairs(collect(servicePre, service, method)) do table.insert(pipeline, fn) end

	local ctx: MiddlewareContext = {
		player = player,
		service = service,
		method = method,
		args = args,
		result = nil,
		cancelled = false,
		overrideResult = nil,
	}

	if #pipeline > 0 then
		local run = buildPipeline(pipeline, ctx)
		run()
	end

	if ctx.cancelled then
		return false, nil, nil
	end

	return true, ctx.args, ctx.overrideResult
end

function Middleware._runPostMiddleware(service: string, method: string, result: any): any
	local postPipeline: { (ctx: MiddlewareContext) -> () } = {}
	for _, fn in ipairs(globalPost) do table.insert(postPipeline, fn) end

	local svc = servicePost[service]
	if svc and svc[method] then
		for _, fn in ipairs(svc[method]) do table.insert(postPipeline, fn) end
	end

	if #postPipeline == 0 then return result end

	local ctx: MiddlewareContext = {
		service = service,
		method = method,
		args = {},
		result = result,
		cancelled = false,
	}

	for _, fn in ipairs(postPipeline) do
		fn(ctx)
	end

	return ctx.result
end

function Middleware.RateLimit(maxCalls: number, perSeconds: number): MiddlewareFn
	return function(ctx, next)
		local player = ctx.player
		if not player then next() return end

		local now = os.time()
		rateLimitData[player] = rateLimitData[player] or {}
		local key = ctx.service .. "." .. ctx.method
		local data = rateLimitData[player][key]

		if not data or now >= data.resetTime then
			rateLimitData[player][key] = { count = 1, resetTime = now + perSeconds }
			next()
		elseif data.count < maxCalls then
			data.count += 1
			next()
		else
			ctx.cancelled = true
			warn("[Zenith] Rate limit hit: " .. player.Name .. " -> " .. ctx.service .. "." .. ctx.method)
		end
	end
end

function Middleware.RequireAuth(checkFn: (player: Player) -> boolean): MiddlewareFn
	return function(ctx, next)
		if ctx.player and not checkFn(ctx.player) then
			ctx.cancelled = true
			warn("[Zenith] Auth failed: " .. ctx.player.Name .. " -> " .. ctx.service .. "." .. ctx.method)
			return
		end
		next()
	end
end

function Middleware.Log(): MiddlewareFn
	return function(ctx, next)
		print("[Zenith] " .. ctx.service .. "." .. ctx.method .. " <- " .. (ctx.player and ctx.player.Name or "server"))
		next()
	end
end

function Middleware.Cache(ttl: number): MiddlewareFn
	local cache: { [string]: { value: any, time: number } } = {}
	return function(ctx, next)
		local key = ctx.service .. "." .. ctx.method
		local entry = cache[key]
		if entry and os.time() - entry.time < ttl then
			ctx.overrideResult = entry.value
			return
		end
		next()
		if ctx.result ~= nil then
			cache[key] = { value = ctx.result, time = os.time() }
		end
	end
end

return Middleware
