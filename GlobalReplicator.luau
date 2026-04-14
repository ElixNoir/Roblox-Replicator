--- Author: COMT

--[[

	Replicator - A network module for cross-network object referencing and method invocation.
	Module: GlobalReplicator - A global replicator.
	
	You may use this module to create a server replicator that replicates to all clients or a client replicator that replicates to the server.
	However, if you need to send specific data to specific players, you will need to create multiple replicators on the server, one for each player.

]]


-- -- State

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlobalDTOPool = require(script.Parent.GlobalDTOPool)
export type DataTransferClass = GlobalDTOPool.DataTransferClass
export type DataTransferObject = GlobalDTOPool.DataTransferObject
local GlobalDTCRegistry = require(script.Parent.GlobalDTCRegistry)
local Reliable = ReplicatedStorage:WaitForChild("Reliable")
local Replicator = require(ReplicatedStorage.Modules.Technology.Replicator)

local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local GlobalReplicator = Replicator.fromDTContext(Reliable, 0x8000, GlobalDTCRegistry, GlobalDTOPool)


-- -- Events

if IsClient then
	Reliable.OnClientEvent:Connect(function(b: buffer, miscellaneous: {any}?)
		GlobalReplicator:receive(b, miscellaneous)
	end)
else
	Reliable.OnServerEvent:Connect(function(player: Player, b: buffer, miscellaneous: {any}?)
		GlobalReplicator:receive(b, miscellaneous, player)
	end)
end


-- -- End

return GlobalReplicator
