--- Author: COMT

--[[

	Replicator: A library for replicating data between the server and client.
  Mod: DTCRegistry

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

export type DTCRegistry = typeof(setmetatable({} :: {[number | DataTransferClass]: (DataTransferClass | number)?}, Module))


-- -- Functions

function Module.new(): DTCRegistry
	return setmetatable({}, Module)
end


-- -- Methods

--[[
    Register a DataTransferClass with a specified or generated identity through which methods can be found for any particular DataTransferObject.
    returns: classIdentity
]]
function Module.registerClass(self: DTCRegistry, dataTransferClass: DataTransferClass, identity: number?): number
	if identity then
		if identity < 0 or identity > 0xFF then
			error(`Expected class DTCRegistry ID to be between 0 and 255; got '{identity}'.`)
		end

		local formerClass = self[identity]
		if formerClass then
			error(`Attempt to override registered class '{tostring(formerClass)}'.`)
		end
	else
		identity = #self
	end

	self[identity :: number] = dataTransferClass
	self[dataTransferClass] = identity

	return identity :: number
end

--[[
    Register a class's method key, or function name, with a specified or generated identity.
    returns: methodIdentity
]]
function Module.registerMethod(self: DTCRegistry, dataTransferClass: DataTransferClass, key: string, identity: number?): number
	if not self[dataTransferClass] then
		error(`Class '{tostring(dataTransferClass)}' must be registered to register a method.`)
	end

	if identity then
		if identity < 0 or identity > 0xFF then
			error(`Expected method DTCRegistry ID to be between 0 and 255; got '{identity}'.`)
		end
	else
		identity = #dataTransferClass.DTC
	end

	local dtc = dataTransferClass.DTC
	dtc[identity :: number], dtc[key] = key, identity

	local dtp, dtu = dataTransferClass.DTP, dataTransferClass.DTU
	local dtpCallback, dtuCallback = dtp[key], dtu[key]
	dtp[identity :: number], dtu[identity :: number] = dtpCallback, dtuCallback

	return identity :: number
end


-- -- End

return Module
