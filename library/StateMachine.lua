--[[

	AStateMachine - V1.0
	A lightweight expandable and modular state management system.
	Created for easy accessibility to using states in your game.
	
	Author @TimedTravel
	GitHub: @fetchloop

	Released: 2026/01/15
	
]]

-- 	\\			  //  --
--  //  MODULES   \\  --
--  \\			  //  --

local Signal = require(script.Signal)

-- 	\\					   //  --
--  //  PRIVATE FUNCTIONS  \\  --
--  \\					   //  --

local function debugLog(self: any, message: string, ...)
	if not self._config.DebugEnabled then return end
	print(string.format("%s %s", self._config.DebugPrefix, string.format(message, ...)))
end

local function addToHistory(self: any, from: string?, to: string)
	local entry: TransitionInfo = {
		From = from or "None",
		To = to,
		Timestamp = workspace:GetServerTimeNow()
	}

	table.insert(self.History, 1, entry)

	while #self.History > self._config.HistorySize do
		table.remove(self.History)
	end
end

-- 	\\						//  --
--  //  STATEMACHINE TYPES  \\  --
--  \\						//  --

export type StateMachineConfig = {
	HistorySize: number?,
	DebugEnabled: boolean?,
	DebugPrefix: string?,
	AllowSelfTransition: boolean?,
}

export type StateContext = {
	StateMachine: StateMachine,
	StateData: any?,
	StartTime: number,
	Duration: number,

	GetElapsed: (self: StateContext) -> number,
	GetRemaining: (self: StateContext) -> number,
	GetData: (self: StateContext) -> any?,
	SetData: (self: StateContext, data: any) -> (),
	Goto: (self: StateContext, stateName: string, data: any?) -> boolean,
}

export type StateCallbacks = {
	Name: string,
	Duration: number?,
	
	CanEnter: ((self: StateContext, fromState: string, data: any?) -> boolean)?,
	CanExit: ((self: StateContext, toState: string) -> boolean)?,
	OnEnter: ((self: StateContext, fromState: string, data: any?) -> ())?,
	OnUpdate: ((self: StateContext, deltaTime: number, elapsed: number) -> ())?,
	OnExit: ((self: StateContext, toState: string) -> ())?,
	OnComplete: ((self: StateContext) -> (string?, any?))?,
	OnTimeout: ((self: StateContext) -> ())?,
}

export type TransitionInfo = {
	From: string,
	To: string,
	Timestamp: number,
}

-- Main Type
export type StateMachine = {
	CurrentState: string?,
	States: {[string]: StateCallbacks},
	History: {TransitionInfo},
	IsPaused: boolean,
	
	StateChanged: Signal.Signal<string, string, any?>,
	StateEntered: Signal.Signal<string, any?>,
	StateExited: Signal.Signal<string>,
	TransitionBlocked: Signal.Signal<string, string, string>,

	AddState: (self: StateMachine, state: StateCallbacks) -> StateMachine,
	AddStates: (self: StateMachine, states: {StateCallbacks}) -> StateMachine,
	RemoveState: (self: StateMachine, stateName: string) -> boolean,

	Goto: (self: StateMachine, stateName: string, data: any?) -> boolean,
	ForceGoto: (self: StateMachine, stateName: string, data: any?) -> boolean,
	TryGoto: (self: StateMachine, stateName: string, data: any?) -> boolean,

	Update: (self: StateMachine, deltaTime: number?) -> string?,
	Pause: (self: StateMachine) -> (),
	Resume: (self: StateMachine) -> (),
	Reset: (self: StateMachine, initialState: string?) -> (),

	IsInState: (self: StateMachine, stateName: string) -> boolean,
	IsInAnyState: (self: StateMachine, ...string) -> boolean,
	CanTransitionTo: (self: StateMachine, stateName: string) -> boolean,

	GetState: (self: StateMachine, stateName: string) -> StateCallbacks?,
	GetCurrentStateInfo: (self: StateMachine) -> StateCallbacks?,
	GetElapsedTime: (self: StateMachine) -> number,
	GetRemainingTime: (self: StateMachine) -> number,
	GetHistory: (self: StateMachine, count: number?) -> {TransitionInfo},
	GetPreviousState: (self: StateMachine) -> string?,
	GetStateData: (self: StateMachine) -> any?,

	SetDebug: (self: StateMachine, enabled: boolean) -> StateMachine,
	Destroy: (self: StateMachine) -> (),
}

-- 	\\						 		  //  --
--  //  STATE CONTEXT IMPLEMENTATION  \\  --
--  \\								  //  --

local function createStateContext(stateMachine: StateMachine, duration: number, data: any?): StateContext
	local context = {
		StateMachine = stateMachine,
		StateData = data,
		StartTime = workspace:GetServerTimeNow(),
		Duration = duration,
	}

	function context:GetElapsed(): number
		return workspace:GetServerTimeNow() - self.StartTime
	end

	function context:GetRemaining(): number
		if self.Duration <= 0 then return 0 end
		return math.max(0, self.Duration - self:GetElapsed())
	end

	function context:GetData(): any?
		return self.StateData
	end

	function context:SetData(newData: any)
		self.StateData = newData
	end

	function context:Goto(stateName: string, transitionData: any?): boolean
		return self.StateMachine:Goto(stateName, transitionData)
	end

	return context
end

-- 	\\						 	    //  --
--  //  STATE CLASS IMPLEMENTATION  \\  --
--  \\								//  --

local StateMachineClass = {}
StateMachineClass.__index = StateMachineClass

local DEFAULT_CONFIG: StateMachineConfig = {
	HistorySize = 5,
	DebugEnabled = false,
	DebugPrefix = "[StateMachine]",
	AllowSelfTransition = false,
}

function StateMachineClass:AddState(state: StateCallbacks): StateMachine
	assert(state.Name, "State must have a Name")
	assert(not self.States[state.Name], string.format("State '%s' already exists", state.Name))

	state.Duration = state.Duration or 0
	
	self.States[state.Name] = state
	
	if not self._initialState then
		self._initialState = state.Name
	end

	debugLog(self, "Added state: %s (Duration: %.2f)", state.Name, state.Duration or 0)

	return self
end

function StateMachineClass:AddStates(states: {StateCallbacks}): StateMachine
	for _, state in states do
		self:AddState(state)
	end
	return self
end

function StateMachineClass:RemoveState(stateName: string): boolean
	local state = self.States[stateName]
	if not state then return false end

	if self.CurrentState == stateName then
		warn(string.format("%s Cannot remove active state '%s'", 
			self._config.DebugPrefix, stateName))
		return false
	end

	self.States[stateName] = nil

	debugLog(self, "Removed state: %s", stateName)
	return true
end

function StateMachineClass:Goto(stateName: string, data: any?): boolean
	if self._destroyed then return false end
	if self.IsPaused then return false end

	local targetState = self.States[stateName]
	if not targetState then
		warn(string.format("%s State '%s' does not exist", self._config.DebugPrefix, stateName))
		return false
	end

	local currentStateName = self.CurrentState
	local currentState = currentStateName and self.States[currentStateName]

	if currentStateName == stateName and not self._config.AllowSelfTransition then
		debugLog(self, "Self-transition blocked: %s", stateName)
		
		return false
	end

	if currentState and currentState.CanExit then
		if not currentState.CanExit(self._context, stateName) then
			debugLog(self, "Transition blocked by CanExit: %s -> %s", currentStateName, stateName)
			
			self.TransitionBlocked:Fire(currentStateName, stateName, "CanExit")
			return false
		end
	end

	if targetState.CanEnter then
		local context = createStateContext(self, targetState.Duration or 0, data)
		if not targetState.CanEnter(context, currentStateName or "None", data) then
			debugLog(self, "Transition blocked by CanEnter: %s -> %s", currentStateName or "None", stateName)
			
			self.TransitionBlocked:Fire(currentStateName or "None", stateName, "CanEnter")
			return false
		end
	end

	if currentState then
		if currentState.OnExit then
			currentState.OnExit(self._context, stateName)
		end
		self.StateExited:Fire(currentStateName)
		debugLog(self, "Exited state: %s", currentStateName)
	end

	self.CurrentState = stateName
	self._context = createStateContext(self, targetState.Duration or 0, data)

	addToHistory(self, currentStateName, stateName)

	if targetState.OnEnter then
		targetState.OnEnter(self._context, currentStateName or "None", data)
	end

	self.StateEntered:Fire(stateName, data)
	self.StateChanged:Fire(currentStateName or "None", stateName, data)

	debugLog(self, "Entered state: %s (Duration: %.2f)", stateName, targetState.Duration or 0)

	return true
end

function StateMachineClass:ForceGoto(stateName: string, data: any?): boolean
	if self._destroyed then return false end

	local targetState = self.States[stateName]
	if not targetState then
		warn(string.format("%s State '%s' does not exist", 
			self._config.DebugPrefix, stateName))
		return false
	end

	local currentStateName = self.CurrentState
	local currentState = currentStateName and self.States[currentStateName]

	if currentState and currentState.OnExit then
		currentState.OnExit(self._context, stateName)
		self.StateExited:Fire(currentStateName)
	end

	self.CurrentState = stateName
	self._context = createStateContext(self, targetState.Duration or 0, data)

	addToHistory(self, currentStateName, stateName)

	if targetState.OnEnter then
		targetState.OnEnter(self._context, currentStateName or "None", data)
	end

	self.StateEntered:Fire(stateName, data)
	self.StateChanged:Fire(currentStateName or "None", stateName, data)

	debugLog(self, "Force entered state: %s", stateName)

	return true
end

function StateMachineClass:TryGoto(stateName: string, data: any?): boolean
	if self._destroyed or self.IsPaused then return false end
	if not self.States[stateName] then return false end

	return self:Goto(stateName, data)
end

function StateMachineClass:Update(deltaTime: number?): string?
	if self._destroyed then return nil end
	if self.IsPaused then return self.CurrentState end

	if not self.CurrentState then
		if self._initialState then
			self:Goto(self._initialState)
		end
		return self.CurrentState
	end

	local currentState = self.States[self.CurrentState]
	if not currentState then return self.CurrentState end

	local dt = deltaTime or 0
	local context = self._context
	if not context then return self.CurrentState end

	local elapsed = context:GetElapsed()

	if currentState.OnUpdate then
		currentState.OnUpdate(context, dt, elapsed)
	end

	local duration = currentState.Duration or 0
	if duration > 0 and elapsed >= duration then
		if currentState.OnTimeout then
			currentState.OnTimeout(context)
		end

		if currentState.OnComplete then
			local nextState, nextData = currentState.OnComplete(context)
			if nextState then
				self:Goto(nextState, nextData)
			end
		end
	end

	return self.CurrentState
end

function StateMachineClass:Pause()
	self.IsPaused = true
	debugLog(self, "Paused")
end

function StateMachineClass:Resume()
	self.IsPaused = false
	debugLog(self, "Resumed")
end

function StateMachineClass:Reset(initialState: string?)
	local targetState = initialState or self._initialState

	if self.CurrentState then
		local currentState = self.States[self.CurrentState]
		if currentState and currentState.OnExit then
			currentState.OnExit(self._context, targetState or "None")
		end
	end

	self.CurrentState = nil
	self._context = nil
	table.clear(self.History)
	self.IsPaused = false

	if targetState then
		self:Goto(targetState)
	end

	debugLog(self, "Reset to state: %s", targetState or "None")
end

function StateMachineClass:IsInState(stateName: string): boolean
	return self.CurrentState == stateName
end

function StateMachineClass:IsInAnyState(...: string): boolean
	if not self.CurrentState then return false end

	for _, stateName in {...} do
		if self.CurrentState == stateName then
			return true
		end
	end
	return false
end

function StateMachineClass:CanTransitionTo(stateName: string): boolean
	if self._destroyed or self.IsPaused then return false end

	local targetState = self.States[stateName]
	if not targetState then return false end

	local currentStateName = self.CurrentState
	local currentState = currentStateName and self.States[currentStateName]

	if currentStateName == stateName and not self._config.AllowSelfTransition then
		return false
	end

	if currentState and currentState.CanExit then
		local context = self._context or createStateContext(self, 0, nil)
		if not currentState.CanExit(context, stateName) then
			return false
		end
	end

	if targetState.CanEnter then
		local context = createStateContext(self, targetState.Duration or 0, nil)
		if not targetState.CanEnter(context, currentStateName or "None", nil) then
			return false
		end
	end

	return true
end

function StateMachineClass:GetState(stateName: string): StateCallbacks?
	return self.States[stateName]
end

function StateMachineClass:GetCurrentStateInfo(): StateCallbacks?
	if not self.CurrentState then return nil end
	return self.States[self.CurrentState]
end

function StateMachineClass:GetElapsedTime(): number
	if not self._context then return 0 end
	return self._context:GetElapsed()
end

function StateMachineClass:GetRemainingTime(): number
	if not self._context then return 0 end
	return self._context:GetRemaining()
end

function StateMachineClass:GetHistory(count: number?): {TransitionInfo}
	if not count then return self.History end

	local result = {}
	for i = 1, math.min(count, #self.History) do
		table.insert(result, self.History[i])
	end
	return result
end

function StateMachineClass:GetPreviousState(): string?
	if #self.History < 1 then return nil end
	return self.History[1].From
end

function StateMachineClass:GetStateData(): any?
	if not self._context then return nil end
	return self._context:GetData()
end

function StateMachineClass:SetDebug(enabled: boolean): StateMachine
	self._config.DebugEnabled = enabled
	return self
end

function StateMachineClass:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self.CurrentState then
		local currentState = self.States[self.CurrentState]
		if currentState and currentState.OnExit then
			currentState.OnExit(self._context, "Destroyed")
		end
	end

	self.StateChanged:Destroy()
	self.StateEntered:Destroy()
	self.StateExited:Destroy()
	self.TransitionBlocked:Destroy()

	table.clear(self.States)
	table.clear(self.History)

	self.CurrentState = nil
	self._context = nil

	setmetatable(self, nil)
end

-- 	\\						 		  //  --
--  //  STATE MACHINE IMPLEMENTATION  \\  --
--  \\								  //  --

local StateMachineModule = {}

function StateMachineModule.new(config: StateMachineConfig?): StateMachine
	local mergedConfig = table.clone(DEFAULT_CONFIG)
	if config then
		for key, value in config do
			mergedConfig[key] = value
		end
	end

	local self = setmetatable({
		CurrentState = nil :: string?,
		States = {} :: {[string]: StateCallbacks},
		History = {} :: {TransitionInfo},
		IsPaused = false,

		StateChanged = Signal.new(),
		StateEntered = Signal.new(),
		StateExited = Signal.new(),
		TransitionBlocked = Signal.new(),

		_config = mergedConfig,
		_context = nil :: StateContext?,
		_initialState = nil :: string?,
		_destroyed = false,
	}, StateMachineClass)

	return self :: any
end

function StateMachineModule.blockedFrom(...: string): (context: StateContext, fromState: string, data: any?) -> boolean
	local blockedStates = {...}
	return function(_, fromState, _)
		return not table.find(blockedStates, fromState)
	end
end

function StateMachineModule.allowedFrom(...: string): (context: StateContext, fromState: string, data: any?) -> boolean
	local allowedStates = {...}
	return function(_, fromState, _)
		return table.find(allowedStates, fromState) ~= nil
	end
end

function StateMachineModule.createState(definition: {
	Name: string,
	Duration: number?,
	CanEnter: ((context: StateContext, fromState: string, data: any?) -> boolean)?,
	CanExit: ((context: StateContext, toState: string) -> boolean)?,
	OnEnter: ((context: StateContext, fromState: string, data: any?) -> ())?,
	OnUpdate: ((context: StateContext, dt: number, elapsed: number) -> ())?,
	OnExit: ((context: StateContext, toState: string) -> ())?,
	OnComplete: ((context: StateContext) -> (string?, any?))?,
	OnTimeout: ((context: StateContext) -> ())?,
	}): StateCallbacks
	return {
		Name = definition.Name,
		Duration = definition.Duration or 0,
		CanEnter = definition.CanEnter,
		CanExit = definition.CanExit,
		OnEnter = definition.OnEnter,
		OnUpdate = definition.OnUpdate,
		OnExit = definition.OnExit,
		OnComplete = definition.OnComplete,
		OnTimeout = definition.OnTimeout,
	}
end

return StateMachineModule
