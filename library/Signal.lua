--[[

	AStateMachine - V1.0
	A lightweight expandable and modular state management system.
	Created for easy accessibility to using states in your game.
	
	Author @TimedTravel
	GitHub: @fetchloop

	Released: 2026/01/15
	
]]

--// Types \\--

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

--// Implementation \\--

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_connections = {} :: {Connection},
		_waiting = {} :: {thread},
		_destroyed = false,
	}, Signal)

	return self :: any
end

--[[
	Connect a callback to the signal.
	Returns a Connection that can be disconnected.
]]
function Signal:Connect(callback: (...any) -> ()): Connection
	assert(not self._destroyed, "Cannot connect to destroyed signal")
	assert(type(callback) == "function", "Callback must be a function")

	local connection = {
		_callback = callback,
		_signal = self,
		Connected = true,
	}

	function connection:Disconnect()
		if not self.Connected then return end
		self.Connected = false

		local connections = self._signal._connections
		local index = table.find(connections, self)
		if index then
			-- Swap-remove for performance
			local last = #connections
			if index ~= last then
				connections[index] = connections[last]
			end
			connections[last] = nil
		end
	end

	table.insert(self._connections, connection)
	return connection
end

-- Connect a callback that will automatically disconnect after firing once.
function Signal:Once(callback: (...any) -> ()): Connection
	assert(not self._destroyed, "Cannot connect to destroyed signal")

	local connection
	connection = self:Connect(function(...)
		if connection.Connected then
			connection:Disconnect()
			callback(...)
		end
	end)

	return connection
end

--[[
	Fire the signal with the given arguments.
	Connected callbacks will be called with those arguments.
]]
function Signal:Fire(...: any)
	if self._destroyed then return end

	-- Copy connections in case callbacks modify the list
	local connections = table.clone(self._connections)

	for _, connection in connections do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end

	-- Resume waiting threads
	local waiting = self._waiting
	self._waiting = {}

	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end

--[[
	Yield the current thread until the signal is fired.
	Returns the arguments passed to Fire.
]]
function Signal:Wait(): ...any
	assert(not self._destroyed, "Cannot wait on destroyed signal")

	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	return coroutine.yield()
end

-- Disconnects connections signals without destroying the signal.
function Signal:DisconnectAll()
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)

	-- Cancel waiting threads
	for _, thread in self._waiting do
		task.cancel(thread)
	end
	table.clear(self._waiting)
end

-- Destroy the signal and disconnect any connections, permanently.
function Signal:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	self:DisconnectAll()
	setmetatable(self, nil)
end

-- Check if signal has any active connections
function Signal:HasConnections(): boolean
	return #self._connections > 0
end

-- Returns the number of active connections
function Signal:GetConnectionCount(): number
	return #self._connections
end

return Signal
