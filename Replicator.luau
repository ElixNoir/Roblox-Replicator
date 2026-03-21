--- Author: COMT

--[[

  Replicator - A network module for cross-network object referencing and method invocation.

]]

--!strict
--!native
--!optimize 2


-- -- State

local Module = {}
Module.__index = Module

export type DataTransferClass = {
	DTC: {[number | string]: string | number}?,
	DTP: {[number | string]: (b: buffer, offset: number, ...any) -> number}?,
	DTU: {[number | string]: (object: DataTransferObject, b: buffer, offset: number, miscellaneous: {any}?, player: Player?) -> (number, number)}?,
	
	dtp: ((b: buffer, offset: number) -> number)?,
	dtu: ((b: buffer, offset: number, miscellaneous: {any}?, player: Player?) -> (DataTransferObject, number, number))?
}

export type DataTransferObject = typeof(setmetatable({} :: any, {} :: DataTransferClass))

export type Replicator = typeof(setmetatable({} :: {
    Buffer: buffer,
    Classes: {[number | DataTransferClass]: DataTransferClass | number},
    FreeList: {number},
    Objects: {[number | DataTransferObject]: DataTransferObject | number},
    RemoteEvent: RemoteEvent,
    RequestQueue: {{Buffer: buffer, Miscellaneous: {any}}},
    RequestQueueBottom: number,
    Top: number
}, Module))


-- -- Helpers

local buffer_create = buffer.create
local buffer_writeu8 = buffer.writeu8
local buffer_writeu16 = buffer.writeu16

local string_format = string.format

local table_insert = table.insert


-- -- Functions

function Module.new(remoteEvent: RemoteEvent, maximumPacketSize: number): Replicator
    return setmetatable({
        Buffer = buffer_create(maximumPacketSize),
        Classes = {},
        FreeList = {},
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
function Module.construct(self: Replicator, player: Player, object: DataTransferObject)
    local classes = self.Classes

    local identity = self.Objects[object]
    if not identity then
        error("Object wasn't initialized.")
    end

    local b = self.Buffer
    local top = self.Top

    buffer_writeu16(b, top, identity)
    buffer_writeu8(b, top + 2, classes[getmetatable(object)])
    
    self.Top += object:dtp(b, top + 3) + 3
end

--[[
    Instruct the recipient to call the object's method.
]]
function Module.invoke(self: Replicator, player: Player, object: DataTransferObject, key: string, ...: any)
    local identity = self.Objects[object]
    if not identity then
        error("Object wasn't initialized.")
    end

    local b = self.Buffer
    local top = self.Top

    buffer_writeu16(b, top, identity)
    buffer_writeu8(b, top + 2, object.DTC[key])
    
    local dtpCallback = object.DTP[key]
    if dtpCallback then
        self.Top += dtpCallback(b, top + 3, ...) + 3
    end
end

--[[
    Stop tracking an object.
]]
function Module.deinitialize(self: Replicator, object: DataTransferObject)
    local objects = self.Objects
    objects[objects[object]], objects[object] = false, nil
end

--[[
    Start tracking an object.
]]
function Module.initialize(self: Replicator, object: Object)
    local objects = self.Objects
    if #objects >= 0x10000 then
        error("Ran out of valid, unique identities to allocate.")
    end

    local freeList = self.FreeList -- #self.Objects could be used for the next free identity instead, but since Lua tables will switch broken arrays to hashmaps, this does not work optimally despite appearing that way
    local freeTop = #freeList

    local identity = freeList[freeTop]
    if identity then
        freeList[freeTop] = nil
    else
        identity = #self.Objects
    end

    objects[identity], objects[object] = object, identity
end

--[[
    Get tracked object by identity.
]]
function Module.getObjectFromIdentity(identity: number): DataTransferObject
    return Objects[identity]
end

--[[
    Register a DataTransferClass with a specified or generated identity through which methods can be found for any particular DataTransferObject.
    returns: classIdentity
]]
function Module.registerClass(self: Replicator, dataTransferClass: DataTransferClass, identity: number?): number
	local classes = self.Classes
    if identity then
        if identity < 0 or identity > 0xFF then
            error(string_format("Expected class registry ID to be between 0 and 255; got '%d'.", identity))
        end

        local formerClass = classes[identity]
        if formerClass then
            error(string_format("Attempt to override registered class '%s'.", tostring(formerClass)))
        end
    else
        identity = #classes
    end

    classes[identity + 1] = dataTransferClass
    classes[dataTransferClass] = identity

    return identity
end

--[[
    Register a class's method key, or function name, with a specified or generated identity.
    returns: methodIdentity
]]
function Module.registerMethod(dataTransferClass: DataTransferClass, key: string, identity: number?): number
    local classes = self.Classes
    if not classes[dataTransferClass] then
        error(string_format("Class '%s' must be registered to register a method.", tostring(dataTransferClass)))
    end
  
    if identity then
        if identity < 0 or identity > 0xFF then
            error(string_format("Expected method registry ID to be between 0 and 255; got '%d'.", identity))
        end
    else
        identity = #dataTransferClass.DTC
    end

    local incIdentity = identity + 1
  
    local dtc = dataTransferClass.DTC
    dtc[incIdentity], dtc[key] = key, identity

    local dtp, dtu = dataTransferClass.DTP, dataTransferClass.DTU
    local dtpCallback, dtuCallback = dtp[key], dtu[key]
    dtp[incIdentity], dtu[incIdentity] = dtpCallback, dtuCallback

    return identity
end

--[[
    Unpack and interpret instructions for constructing objects or invoking object methods.
]]
function Module.handle(b: buffer, miscellaneous: {any})
    local bufferOffset, arrayOffset = 0, 1
    local size = buffer_len(b)

    local objects = self.Objects
    local classes = self.Classes
    
    while bufferOffset < size do
        local identity = buffer_readu16(b, bufferOffset)
        bufferOffset += 2

        local object = objects[identity]
        if object then
            local methodIdentity = buffer_readu8(b, bufferOffset) + 1
            bufferOffset += 1
            
            local method = object.DTU[methodIdentity]
            if not method then
                error(string_format("Method '%s' is missing from object '%s' of class '%s'.", object.DTC[methodIdentity], tostring(object), tostring(getmetatable(object))))
            end
            
            local bufferOffsetOffset, arrayOffsetOffset = method(object, b, bufferOffset, miscellaneous[arrayOffset])
            bufferOffset += bufferOffsetOffset
            arrayOffset += arrayOffsetOffset
        else
            local typeIdentity = buffer_readu8(b, bufferOffset) + 1
            bufferOffset += 1

            local class = classes[typeIdentity]
            if not class then
                error(string_format("Class or type with identity '%d' does not exist.", typeIdentity))
            end

            local object, bufferOffsetOffset, arrayOffsetOffset = class.dtu(b, bufferOffset, miscellaneous[arrayOffset])
            bufferOffset += bufferOffsetOffset
            arrayOffset += arrayOffsetOffset

            objects[identity], objects[object] = object, identity
        end
    end
end

--[[
	Queue and/or handle incoming data to insure a chronologically ordered process.
]]
function Module.receive(self: Replicator, b: buffer, miscellaneous: {any}?)
    miscellaneous = miscellaneous or {}
    
    local requestQueue, requestQueueBottom = self.RequestQueue, self.RequestQueueBottom
    if requestQueueBottom ~= 0 then
        table_insert(requestQueue, {Buffer = b, Miscellaneous = miscellaneous})
        return
    end

    self.handle(b, miscellaneous)

    while requestQueueBottom ~= 0 do
        local data = requestQueue[requestQueueBottom]
        self.handle(data.Buffer, data.Miscellaneous)
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
    buffer_copy(buff, 0, b, 0, top)
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
    buffer_copy(buff, 0, b, 0, top)
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
