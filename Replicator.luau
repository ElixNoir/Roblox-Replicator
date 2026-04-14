--- Author: COMT

--[[

	Replicator - A network module for cross-network object referencing and method invocation.

]]

--!strict
--!native
--!optimize 2


-- -- State

local DTCRegistry = require(script.DTCRegistry)
export type DataTransferClass = DTCRegistry.DataTransferClass
export type DataTransferObject = DTCRegistry.DataTransferObject
type DTCRegistry = DTCRegistry.DTCRegistry
local DTOPool = require(script.DTOPool)
type DTOPool = DTOPool.DTOPool

local Module = {}
Module.__index = Module

export type Replicator = typeof(setmetatable({} :: {
	Buffer: buffer,
	Classes: DTCRegistry,
	FreeList: {number},
	Miscellaneous: {any},
	Objects: {[number | DataTransferObject]: (boolean | DataTransferObject | number)?},
	RemoteEvent: RemoteEvent,
	RequestQueue: {{Buffer: buffer, Miscellaneous: {any}}},
	RequestQueueBottom: number,
	Top: number
}, Module))


-- -- Helpers

local buffer_copy = buffer.copy
local buffer_create = buffer.create
local buffer_fill = buffer.fill
local buffer_len = buffer.len
local buffer_readu8 = buffer.readu8
local buffer_readu16 = buffer.readu16
local buffer_writeu8 = buffer.writeu8
local buffer_writeu16 = buffer.writeu16

local math_min = math.min

local table_clear = table.clear
local table_insert = table.insert


-- -- Functions

function Module.fromDTContext(remoteEvent: RemoteEvent, maximumPacketSize: number, dtcRegistry: DTCRegistry, dtoPool: DTOPool): Replicator
	return setmetatable({
		Buffer = buffer_create(maximumPacketSize),
		Classes = dtcRegistry,
		FreeList = dtoPool.FreeList,
		Miscellaneous = {},
		Objects = dtoPool.Objects,
		RemoteEvent = remoteEvent,
		RequestQueue = {},
		RequestQueueBottom = 0,
		Top = 0
	}, Module)
end

function Module.fromDTCRegistry(remoteEvent: RemoteEvent, maximumPacketSize: number, dtcRegistry: DTCRegistry): Replicator
	return setmetatable({
		Buffer = buffer_create(maximumPacketSize),
		Classes = dtcRegistry,
		FreeList = {},
		Miscellaneous = {},
		Objects = {},
		RemoteEvent = remoteEvent,
		RequestQueue = {},
		RequestQueueBottom = 0,
		Top = 0
	}, Module)
end

function Module.new(remoteEvent: RemoteEvent, maximumPacketSize: number): Replicator
	return setmetatable({
		Buffer = buffer_create(maximumPacketSize),
		Classes = DTCRegistry.new(),
		FreeList = {},
		Miscellaneous = {},
		Objects = {},
		RemoteEvent = remoteEvent,
		RequestQueue = {},
		RequestQueueBottom = 0,
		Top = 0
	}, Module)
end


-- -- Methods

--[[
    Allocate a new buffer and copy over old data.
]]
function Module.allocate(self: Replicator, size: number)
	local b = self.Buffer
	if buffer_len(b) == size then
		return
	end

	local newBuffer = buffer_create(size)
	buffer_copy(newBuffer, 0, b, 0, math_min(size, buffer_len(b)))

	self.Buffer = newBuffer
end

--[[
    Instruct the recipient to construct an object with the given identity.
]]
function Module.construct(self: Replicator, object: DataTransferObject)
	local classes = self.Classes

	local identity = self.Objects[object] :: number
	if not identity then
		error("Object wasn't initialized.")
	end

	local b = self.Buffer
	local top = self.Top

	buffer_writeu16(b, top, identity)
	buffer_writeu8(b, top + 2, classes[getmetatable(object) :: DataTransferClass] :: number)

	self.Top += object:dtp(b, top + 3) + 3
end

--[[
    Instruct the recipient to call the object's method.
]]
function Module.invoke(self: Replicator, object: DataTransferObject, key: string, ...: any)
	local identity = self.Objects[object] :: number
	if not identity then
		error("Object wasn't initialized.")
	end

	local b = self.Buffer
	local top = self.Top

	buffer_writeu16(b, top, identity)
	buffer_writeu8(b, top + 2, object.DTC[key] :: number)

	local dtpCallback = object.DTP[key]
	if dtpCallback then
		self.Top += dtpCallback(object, b, top + 3, ...) + 3
	end
end

--[[
    Stop tracking an object.
]]
function Module.deinitialize(self: Replicator, object: DataTransferObject)
	local objects = self.Objects
	objects[objects[object] :: number], objects[object] = false, nil
end

--[[
    Start tracking an object.
]]
function Module.initialize(self: Replicator, object: DataTransferObject)
	local objects = self.Objects
	if #objects >= 0x10000 then
		error("Ran out of valid, unique identities to allocate.")
	end

	local freeList = self.FreeList -- #self.Objects could be used for the next free identity instead, but since Lua tables will switch broken arrays to hashmaps, this does not work optimally despite appearing that way
	local freeTop = #freeList + 1

	local identity = freeList[freeTop]
	if identity then
		freeList[freeTop] = nil
	else
		identity = #self.Objects
	end

	objects[identity], objects[object] = object, identity
end

--[[
    Unpack and interpret instructions for constructing objects or invoking object methods.
]]
function Module.handle(self: Replicator, b: buffer, miscellaneous: {any}, player: Player?)
	local bufferOffset, arrayOffset = 0, 1
	local size = buffer_len(b)

	local objects = self.Objects
	local classes = self.Classes

	while bufferOffset < size do
		local identity = buffer_readu16(b, bufferOffset)
		bufferOffset += 2

		local object = objects[identity]
		if object then
			local methodIdentity = buffer_readu8(b, bufferOffset)
			bufferOffset += 1

			local method = (object :: DataTransferObject).DTU[methodIdentity]
			if not method then
				error(`Method '{(object :: DataTransferObject).DTC[methodIdentity]}' is missing from object '{tostring(object)}' of class '{tostring(getmetatable(object))}'.`)
			end

			local bufferOffsetOffset, arrayOffsetOffset = method(object :: DataTransferObject, b, bufferOffset, miscellaneous[arrayOffset], player)
			bufferOffset += bufferOffsetOffset
			arrayOffset += arrayOffsetOffset
		else
			local typeIdentity = buffer_readu8(b, bufferOffset)
			bufferOffset += 1

			local class = classes[typeIdentity]
			if not class then
				error(`Class or type with identity '{typeIdentity}' does not exist.`)
			end

			local object, bufferOffsetOffset, arrayOffsetOffset = (class :: DataTransferClass).dtu(b, bufferOffset, miscellaneous[arrayOffset], player)
			bufferOffset += bufferOffsetOffset
			arrayOffset += arrayOffsetOffset

			objects[identity], objects[object] = object, identity
		end
	end
end

--[[
	Queue and/or handle incoming data to insure a chronologically ordered process.
]]
function Module.receive(self: Replicator, b: buffer, miscellaneous: {any}?, player: Player?)
	miscellaneous = miscellaneous or {}

	local requestQueue, requestQueueBottom = self.RequestQueue, self.RequestQueueBottom
	if requestQueueBottom ~= 0 then
		table_insert(requestQueue, {Buffer = b, Miscellaneous = miscellaneous})
		return
	end

	self:handle(b, miscellaneous, player)

	while requestQueueBottom ~= 0 do
		local data = requestQueue[requestQueueBottom]
		self:handle(data.Buffer, data.Miscellaneous, player)
	end

	self.RequestQueueBottom = 0
end

--[[
    (Server use only)
    Flush the data and send it to a client.
]]
function Module.sendClient(self: Replicator, player: Player)
	local b = self.Buffer
	local remote = self.RemoteEvent
	local top = self.Top
	local miscellaneous = self.Miscellaneous

	local data = buffer_create(top)
	buffer_copy(data, 0, b, 0, top)
	buffer_fill(b, 0, 0, top)
	self.Top = 0

	if #miscellaneous == 0 then
		remote:FireClient(player, data)
	else
		remote:FireClient(player, data, miscellaneous)
		table_clear(miscellaneous)
	end
end

--[[
    (Client use only)
    Flush the data and send it to the server.
]]
function Module.sendServer(self: Replicator)
	local b = self.Buffer
	local remote = self.RemoteEvent
	local top = self.Top
	local miscellaneous = self.Miscellaneous

	local data = buffer_create(top)
	buffer_copy(data, 0, b, 0, top)
	buffer_fill(b, 0, 0, top)
	self.Top = 0

	if #miscellaneous == 0 then
		remote:FireServer(data)
	else
		remote:FireServer(data, miscellaneous)
		table_clear(miscellaneous)
	end
end


-- -- End

return Module
