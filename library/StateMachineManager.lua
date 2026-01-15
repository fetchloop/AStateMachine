--[[

	AStateMachine - V1.0
	A lightweight expandable and modular state management system.
	Created for easy accessibility to using states in your game.
	
	Author @TimedTravel
	GitHub: @fetchloop

	Released: 2026/01/15
	
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachineManager = {}
StateMachineManager.__index = StateMachineManager

local StateMachineModule = require(ReplicatedStorage.State.StateMachine)

function StateMachineManager.new()
	
	local self = setmetatable({}, StateMachineManager)
	
	self.StateMachines = {}
	
	return self
end

function StateMachineManager:Add(group: string, name: string, machine: StateMachineModule.StateMachine): boolean
	
	local groupExists = self.StateMachines[group] ~= nil
	if groupExists then
		self.StateMachines[group][name] = machine
	else
		self.StateMachines[group] = {}
		self.StateMachines[group][name] = machine
	end
	
	return self.StateMachines[group][name] ~= nil
end

-- Only remove from machines table, not deconstruct the machine itself.
function StateMachineManager:Remove(group: string, name: string): boolean
	local groupExists = self.StateMachines[group] ~= nil
	if groupExists then
		self.StateMachines[group][name] = nil
		return true
	else
		return false
	end
end

function StateMachineManager:Get(group: string, name: string): StateMachineModule.StateMachine?
	local groupTable = self.StateMachines[group]
	if not groupTable then
		return nil
	end
	return groupTable[name]
end

function StateMachineManager:GetMachines() : {}
	local _m = {}
	for _, group: {} in self.StateMachines do
		for _, machine: StateMachineModule.StateMachine in group do
			table.insert(_m, machine)
		end
	end
	return _m
end

function StateMachineManager:GetMachinesInGroup(group: string) : {}
	if self.StateMachines[group] == nil then return {} end
	local _l = {}
	for i, machine in self.StateMachines[group] do
		_l[i] = machine
	end
	return _l
end

-- TODO: Recode to include proper error logging instead of just 'index' failed.
function StateMachineManager:UpdateAll(delta: number?): boolean
	local _errc = 0
	for i, machine: StateMachineModule.StateMachine in self:GetMachines() do
		local success, err = pcall(function()
			machine:Update(delta or nil)
		end)
		if err then
			warn(string.format("[StateMachineManager] Error updating StateMachine with index '%i'", i))
			_errc+=1
		end
	end
	return _errc == 0
end

return StateMachineManager
