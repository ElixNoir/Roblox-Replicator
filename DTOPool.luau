--- Author: COMT

--[[

	Replicator: A library for replicating data between the server and client.
	Module: DTOPool - A pool of DataTransferObjects.

]]

--!native
--!optimize 2
--!strict


-- -- State

local Types = require(script.Parent.Types)

local Module = {}
Module.__index = Module

export type DataTransferClass = Types.DataTransferClass
export type DataTransferObject = Types.DataTransferObject

export type DTOPool = typeof(setmetatable({} :: {
	FreeList: {number},
	Objects: {[number | DataTransferObject]: (boolean | DataTransferObject | number)?}
}, Module))


-- -- Functions

function Module.new(): DTOPool
	return setmetatable({
		FreeList = {},
		Objects = {}
	}, Module)
end


-- -- Methods

--[[
    Get object by identity.
]]
function Module.getIdentityFromObject(self: DTOPool, object: DataTransferObject): number
	local identity = self.Objects[object] :: number?
	if not identity then
		error(`Object '{tostring(object)}' is not initialized.`)
	end
	return identity
end

--[[
    Get object by identity.
]]
function Module.getObjectFromIdentity(self: DTOPool, identity: number): DataTransferObject
	local object = self.Objects[identity] :: DataTransferObject?
	if not object then
		error(`No object found for identity '{identity}'.`)
	end
	return object
end


-- -- End

return Module
