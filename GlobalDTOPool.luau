--- Author: COMT

--[[

	Replicator - A network module for cross-network object referencing and method invocation.
	Module: GlobalDTOPool - A global registry for DataTransferObjects.

]]


-- -- State

local DTOPool = require(script.Parent.DTOPool)
export type DataTransferClass = DTOPool.DataTransferClass
export type DataTransferObject = DTOPool.DataTransferObject


-- -- End

return DTOPool.new()
