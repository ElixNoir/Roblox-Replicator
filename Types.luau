--- Author: COMT

--[[

	Replicator - A network module for cross-network object referencing and method invocation.
  Module: Types

]]


-- -- Types

export type DataTransferClass = {
	DTC: {[number | string]: string | number},
	-- returns: bufferOffsetOffset
	DTP: {[number | string]: (self: DataTransferObject, b: buffer, offset: number, ...any) -> number},
	-- returns: (bufferOffsetOffset, arrayOffsetOffset)
	DTU: {[number | string]: (self: DataTransferObject, b: buffer, offset: number, miscellaneous: {any}?, player: Player?) -> (number, number)},

	-- returns: (Object, bufferOffsetOffset)
	dtp: ((self: DataTransferObject, b: buffer, offset: number) -> number),
	-- returns: (Object, bufferOffsetOffset, arrayOffsetOffset)
	dtu: ((b: buffer, offset: number, miscellaneous: {any}?, player: Player?) -> (DataTransferObject, number, number))
}

export type DataTransferObject = typeof(setmetatable({} :: {}, {} :: {__index: DataTransferClass}))


-- -- End

return true
