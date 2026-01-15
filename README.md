# AStateMachine

A lightweight state machine system for Roblox with timed states, transition guards, signals, and a manager for handling multiple machines.

## Structure

![Structure](assets/struct.png)

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StateMachineManager = require(script.StateMachineManager)
local StateMachineModule = require(ReplicatedStorage.State.StateMachine)

local Manager = StateMachineManager.new()
local machine = StateMachineModule.new({ DebugEnabled = true })

machine:AddStates({
    {
        Name = "Idle",
        Duration = 3,
        OnEnter = function(context, fromState, data)
            print("Entered Idle")
        end,
        OnComplete = function(context)
            return "Active"
        end,
    },
    {
        Name = "Active",
        OnEnter = function(context, fromState, data)
            print("Now active!")
        end,
    },
})

Manager:Add("General", "MyMachine", machine) -- Group, Name, StateMachine
machine:Goto("Idle")

RunService.Stepped:Connect(function()
    Manager:UpdateAll()
end)
```

## State Callbacks

| Callback | Description |
|----------|-------------|
| CanEnter | Guard for entering (return boolean) |
| CanExit | Guard for exiting (return boolean) |
| OnEnter | Called when entering state |
| OnUpdate | Called every update |
| OnExit | Called when exiting state |
| OnComplete | Called when duration expires (return next state) |
| OnTimeout | Called when duration expires |

## License

Free to use. **If your game generates revenue, please credit me.**

## Contact

Creative usages? I'd love to have a look! Discord: **@fetchloop**
