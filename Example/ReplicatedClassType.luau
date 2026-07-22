--- Author:

--[[

	ReplicatedClassType - 

]]

--!strict
--!native


-- -- Dependencies

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Codec_CFrame, GlobalDTCRegistry, Replicator
do
	local network = ReplicatedStorage.Modules.Network
	Codec_CFrame = require(network.Codec.CFrame)
	GlobalDTCRegistry = require(network.Replicator.GlobalDTCRegistry)
	Replicator = require(network.Replicator)
end


-- -- State

local Module = {
	DTC = {},
	DTP = {},
	DTU = {}
}
Module.__index = Module

export type ReplicatedClassType = typeof(setmetatable({} :: {
	
	-- Members/fields
	
	IsAwesome: boolean,
	IsCool: boolean,
	IsCooler: boolean,
	IsCoolest: boolean,
	IsFreaky: boolean,
	IsIncredible: boolean,
	IsMajestic: boolean,
	RocksHard: boolean
	
}, Module))


-- -- Functions

function Module.dtp(self: ReplicatedClassType, b: buffer, offset: number): number
	buffer.writeu8(b, offset, bit32.bor(
		self.IsAwesome and 1 or 0,
		self.IsCool and 2 or 0,
		self.IsCooler and 4 or 0,
		self.IsCoolest and 8 or 0,
		self.IsFreaky and 16 or 0,
		self.IsIncredible and 32 or 0,
		self.IsMajestic and 64 or 0,
		self.RocksHard and 128 or 0
	))
	
	return 1 -- number of consumed bytes
end

function Module.dtu(b: buffer, offset: number, miscellaneous: {any}?, player: Player?): (ReplicatedClassType, number, number)
	return Module.fromMask(buffer.readu8(b, offset)), 1, 0 -- object, number of consumed bytes, number of items consumed from miscellaneous
end

function Module.fromMask(mask: number): ReplicatedClassType
	return setmetatable({
		IsAwesome = bit32.bor(mask, 1) == 1,
		IsCool = bit32.bor(mask, 2) == 2,
		IsCooler = bit32.bor(mask, 4) == 4,
		IsCoolest = bit32.bor(mask, 8) == 8,
		IsFreaky = bit32.bor(mask, 16) == 16,
		IsIncredible = bit32.bor(mask, 32) == 32,
		IsMajestic = bit32.bor(mask, 64) == 64,
		RocksHard = bit32.bor(mask, 128) == 128
	}, Module)
end

function Module.new(): ReplicatedClassType
	return setmetatable({
		IsAwesome = true,
		IsCool = true,
		IsCooler = true,
		IsCoolest = true,
		IsFreaky = true,
		IsIncredible = true,
		IsMajestic = true,
		RocksHard = true
	}, Module)
end


-- -- Methods

do -- .destroy

	function Module.destroy(self: ReplicatedClassType)
		--[[
			Assuming you need to automatically replicate destruction to only one client and not all clients,
			you can use the `Replicator` module to send a message to a specific client.  GlobalReplicator is
			not typically best for states that exist on all clients unless they are very carefully tracked.
			
			It is often better to use per-player replicators to tailor to clients' needs and to enforce valid
			state tracking.
			
			It is also true that you may not always want to replicate certain methods automatically, especially
			if the object is not tracked anywhere, if it is expensive to replicate, or the method is entirely 
			internal.
			
			For these reasons, this method is left empty.
		]]
		
		-- Destruction logic
	end

	function Module.DTP.destroy(self: ReplicatedClassType, b: buffer, offset: number, message: string): number
		-- Example use of buffer in DTP method
		local length = #message
		buffer.writeu16(b, offset, length)
		buffer.writestring(b, offset + 2, message)
		
		return length + 2 -- number of consumed bytes
	end

	function Module.DTU.destroy(self: ReplicatedClassType, b: buffer, offset: number, miscellaneous: {any}?, player: Player?): (number, number)
		-- Example use of buffer in DTU method
		local length = buffer.readu16(b, offset)
		print(buffer.readstring(b, offset + 2, length))
		
		return length + 2, 0 -- number of consumed bytes, number of items consumed from miscellaneous
	end

	GlobalDTCRegistry:registerMethod(Module, "destroy")

end


-- -- End

GlobalDTCRegistry:registerClass(Module)

return Module
