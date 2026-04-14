--- Author: COMT

--[[

	Replicator - A network module for cross-network object referencing and method invocation.
	Module: GlobalDTCRegistry - A global registry for DataTransferClasses.

]]


-- -- State

local DTCRegistry = require(script.Parent.DTCRegistry)
export type DataTransferClass = DTCRegistry.DataTransferClass
export type DataTransferObject = DTCRegistry.DataTransferObject


-- -- End

return DTCRegistry.new()
