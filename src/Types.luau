export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"

export type MiddlewareContext = {
	player: Player?,
	service: string,
	method: string,
	args: { any },
	result: any?,
	cancelled: boolean,
	overrideResult: any?,
}

export type MiddlewareFn = (ctx: MiddlewareContext, next: () -> ()) -> ()

export type PostMiddlewareFn = (ctx: MiddlewareContext) -> ()

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>, timeout: number?) -> (any, boolean),
	DisconnectAll: (self: Signal<T...>) -> (),
	GetConnectionCount: (self: Signal<T...>) -> number,
	_isSignal: boolean,
}

export type ServiceConfig = {
	Name: string,
	Client: { [string]: any }?,
	Dependencies: { string }?,
	[string]: any,
}

export type ControllerConfig = {
	Name: string,
	Dependencies: { string }?,
	[string]: any,
}

export type ComponentConfig = {
	Tag: string,
	Ancestors: { Instance }?,
	RateLimit: number?,
}

export type Promise = {
	andThen: (self: Promise, fn: (...any) -> ()) -> Promise,
	catch: (self: Promise, fn: (err: any) -> ()) -> Promise,
	finally: (self: Promise, fn: () -> ()) -> Promise,
	await: (self: Promise) -> (boolean, ...any),
}

return {}
