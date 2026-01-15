--[[

	AStateMachine - V1.0
	A lightweight expandable and modular state management system.
	Created for easy accessibility to using states in your game.
	
	Author @TimedTravel
	GitHub: @fetchloop

	Released: 2026/01/15
	
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StateMachineManager = require(script.StateMachineManager)
local StateMachineModule = require(ReplicatedStorage.State.StateMachine)

local Manager = StateMachineManager.new()

-- Create a state machine with debug enabled
local exampleMachine: StateMachineModule.StateMachine = StateMachineModule.new({
	DebugEnabled = true,
	DebugPrefix = "[Example]",
	HistorySize = 10,
})

local A_State = StateMachineModule.createState({
	Name = "A",
	Duration = 0.5,

	OnEnter = function(context, fromState, data)
		print("Entered A from:", fromState)
		if data then
			print("Received data:", data.message)
		end
	end,

	OnUpdate = function(context, dt, elapsed)
		print(string.format("A update - Elapsed: %.2f, Remaining: %.2f", elapsed, context:GetRemaining()))
	end,

	OnExit = function(context, toState)
		print("Exiting A, going to:", toState)
	end,

	OnComplete = function(context)
		-- Automatically transition to B when duration expires
		return "B", { message = "Auto-transition from A" }
	end,
})

local B_State = StateMachineModule.createState({
	Name = "B",
	Duration = 2,

	CanEnter = function(context, fromState, data)
		-- Only allow entry from A
		return fromState == "A"
	end,

	OnEnter = function(context, fromState, data)
		print("Entered B from:", fromState)
		print("Data:", data.message)
	end,

	OnComplete = function(context)
		return "C"
	end,
})

local C_State = StateMachineModule.createState({
	Name = "C",

	OnEnter = function(context, fromState, data)
		print("Entered C - this state has no duration")

		-- Store and modify state data
		context:SetData({ counter = 0 })
	end,

	OnUpdate = function(context, dt, elapsed)
		local data = context:GetData()
		data.counter += 1
		context:SetData(data)

		-- Manually transition after counter reaches threshold
		if data.counter >= 100 then
			print("Counter reached 100, going back to A")
			context:Goto("A", { message = "Looped back from C" })
		end
	end,
})

-- Add states using chaining
exampleMachine:AddStates({A_State, B_State, C_State}) -- Make sure to wrap the states in a table.

-- You can also add states by passing in a table with your customizations such as;
--[[
exampleMachine:AddState({
	Name = " D ",
	OnUpdate = function(context, delta, elapsed)
		
	end
})
]]
	

-- Connect to signals
exampleMachine.StateChanged:Connect(function(fromState, toState, data)
	print(string.format("Signal: StateChanged %s -> %s", fromState, toState))
end)

exampleMachine.TransitionBlocked:Connect(function(fromState, toState, reason)
	print(string.format("Signal: Transition blocked %s -> %s (%s)", fromState, toState, reason))
end)

-- Add to manager
Manager:Add("General", "ExampleMachine", exampleMachine)

-- Start the machine
exampleMachine:Goto("A", { message = "Initial start" })

-- Update loop
RunService.Stepped:Connect(function(_, dt)
	Manager:UpdateAll()
end)

-- Showcase of other features
task.delay(10, function()
	print("Demonstrating other features")

	-- Check current state
	print("Current state:", exampleMachine.CurrentState)
	print("Is in A?", exampleMachine:IsInState("A"))
	print("Is in A or B?", exampleMachine:IsInAnyState("A", "B"))

	-- Get state info
	local stateInfo = exampleMachine:GetCurrentStateInfo()
	if stateInfo then
		print("Current state name:", stateInfo.Name)
		print("Current state duration:", stateInfo.Duration)
	end

	-- Check transition possibility
	print("Can transition to B?", exampleMachine:CanTransitionTo("B"))
	print("Can transition to C?", exampleMachine:CanTransitionTo("C"))

	-- View history
	print("\nTransition history:")
	for i, entry in exampleMachine:GetHistory(5) do
		print(string.format("  %d. %s -> %s", i, entry.From, entry.To))
	end

	-- Pause and resume
	print("\nPausing machine...")
	exampleMachine:Pause()
	print("Is paused?", exampleMachine.IsPaused)

	task.wait(2)

	print("Resuming machine...")
	exampleMachine:Resume()

	-- Force transition (bypasses CanEnter/CanExit)
	task.wait(3)
	print("\nForce transitioning to B (bypasses CanEnter)...")
	exampleMachine:ForceGoto("B", { message = "Forced entry" })
end)
