local Types = require(script.Parent.Types)

type LogLevel = Types.LogLevel

local Logger = {}
Logger.__index = Logger

Logger.GlobalLevel = "DEBUG" :: LogLevel
Logger.ShowTimestamp = true

local levels: { [LogLevel]: number } = {
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
}

local function timestamp(): string
	local dt = DateTime.now():ToLocalTime()
	return string.format("[%02d:%02d:%02d]", dt.Hour, dt.Minute, dt.Second)
end

local function format(tag: string, level: LogLevel, message: string): string
	local parts = {}
	if Logger.ShowTimestamp then
		table.insert(parts, timestamp())
	end
	table.insert(parts, level)
	table.insert(parts, "[" .. tag .. "]")
	table.insert(parts, message)
	return table.concat(parts, " ")
end

function Logger.new(tag: string)
	assert(type(tag) == "string", "Logger tag must be a string.")
	return setmetatable({
		_tag = tag,
		_level = Logger.GlobalLevel :: LogLevel,
		_history = {} :: { { level: LogLevel, message: string, time: string } },
	}, Logger)
end

function Logger:SetLevel(level: LogLevel)
	assert(levels[level], "Invalid log level: " .. tostring(level))
	self._level = level
end

function Logger:_shouldLog(level: LogLevel): boolean
	return levels[level] >= levels[self._level]
end

function Logger:_log(level: LogLevel, message: string)
	if not self:_shouldLog(level) then return end

	local formatted = format(self._tag, level, message)

	table.insert(self._history, {
		level = level,
		message = message,
		time = DateTime.now():ToIsoDate(),
	})

	if #self._history > 500 then
		table.remove(self._history, 1)
	end

	if level == "ERROR" or level == "WARN" then
		warn(formatted)
	else
		print(formatted)
	end
end

function Logger:Debug(message: string) self:_log("DEBUG", message) end
function Logger:Info(message: string)  self:_log("INFO",  message) end
function Logger:Warn(message: string)  self:_log("WARN",  message) end
function Logger:Error(message: string) self:_log("ERROR", message) end

function Logger:GetHistory()
	return table.clone(self._history)
end

function Logger:ClearHistory()
	table.clear(self._history)
end

return Logger
