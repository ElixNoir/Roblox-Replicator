--- Author: COMT

--[[

  Replicator - A set of client and server modules that enables class method calling and cross-network object referencing.
  Mod: Client

]]

--!strict
--!native
--!optimize 2


-- -- State

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remote = ReplicatedStorage:WaitForChild("Replication")

local Module = {}
--Module.__index = Module

export type DataTransferClass = {
	DTC: {[number | string]: string | number}?,
	DTP: {[number | string]: (b: buffer, offset: number, ...any) -> number}?,
	DTU: {[number | string]: (object: DataTransferObject, b: buffer, offset: number, miscellaneous: {any}?) -> (number, number)}?,

	dtp: ((b: buffer, offset: number) -> number)?,
	dtu: ((b: buffer, offset: number, miscellaneous: {any}?) -> (DataTransferObject, number, number))?
}

export type DataTransferObject = typeof(setmetatable({}, {} :: DataTransferClass))


-- -- Helpers

local buffer_copy = buffer.copy
local buffer_create = buffer.create
local buffer_fill = buffer.fill
local buffer_len = buffer.len
local buffer_writeu8 = buffer.writeu8
local buffer_writeu16 = buffer.writeu16

local math_min = math.min

local string_format = string.format

local table_clear = table.clear


-- -- Identification

local Classes: {[DataTransferClass | number]: number | DataTransferClass} = {}
local Objects: {[DataTransferObject | number]: number | DataTransferObject} = {}


-- -- Buffer Building

local Buffer, Top, Miscellaneous: {any} = buffer_create(65536), 0, {}


-- -- Functions

--[[
  Reallocate the buffer.
]]
function Module.allocate(size: number)
	if buffer_len(Buffer) == size then
		return
	end

	local newBuffer = buffer_create(size)
	buffer_copy(newBuffer, 0, Buffer, 0, math_min(size, buffer_len(Buffer)))

	Buffer = newBuffer
end

function Module.invoke(player: Player, object: DataTransferObject, key: string, ...: any)
	buffer_writeu16(Buffer, Top, assert(Objects[object], "Object wasn't initialized."))
	buffer_writeu8(Buffer, Top + 2, object.DTC[key])
	Top += 3
	
	local dtpCallback = object.DTP[key]
	if dtpCallback then
		Top += dtpCallback(Buffer, Top, ...)
	end
end

function Module.create(player: Player, object: DataTransferObject)
	buffer_writeu16(Buffer, Top, Objects[object])
	buffer_writeu8(Buffer, Top + 2, Classes[getmetatable(object)])
	Top += 3
	
	Top += object:dtp(Buffer, Top)
end

function Module.deinitialize(object: DataTransferObject)
	local identity = Objects[object]
	Objects[identity], Objects[object] = nil, nil
end

local function handle(b: buffer, miscellaneous: {any})
	local bufferOffset, arrayOffset = 0, 1
	local size = buffer_len(b)

	while bufferOffset < size do
		local identity = buffer_readu16(b, bufferOffset)
		bufferOffset += 2

		local object = Objects[identity]
		if object then
			local methodIdentity = buffer_readu8(b, bufferOffset) + 1
			bufferOffset += 1
			
			local method = object.DTU[methodIdentity]
			if not method then
				error(("Method '%s' is missing from object '%s' of class '%s'."):format(object.DTC[methodIdentity], tostring(object), tostring(getmetatable(object))))
			end
			
			local bufferOffsetOffset, arrayOffsetOffset = method(object, b, bufferOffset, miscellaneous[arrayOffset])
			bufferOffset += bufferOffsetOffset
			arrayOffset += arrayOffsetOffset
		else
			local typeIdentity = buffer.readu8(b, bufferOffset) + 1
			bufferOffset += 1

			local class = assert(Classes[typeIdentity], "Class or type does not exist.")
			local object, bufferOffsetOffset, arrayOffsetOffset = class.dtu(b, bufferOffset, miscellaneous[arrayOffset])
			bufferOffset += bufferOffsetOffset
			arrayOffset += arrayOffsetOffset

			Objects[identity], Objects[object] = object, identity
		end
	end
end

local RequestQueue: {{Buffer: buffer, Miscellaneous: {any}}}, RequestQueueBottom = {}, 0

function Module.receive(b: buffer, miscellaneous: {any}?)
	miscellaneous = miscellaneous or {}
	if RequestQueueBottom ~= 0 then
		table_insert(RequestQueue, {Buffer = b, Miscellaneous = miscellaneous})
		return
	end

	handle(b, miscellaneous)

	while RequestQueueBottom ~= 0 do
		local data = RequestQueue[RequestQueueBottom]
		handle(data.Buffer, data.Miscellaneous)
	end

	RequestQueueBottom = 0
end

function Module.getObjectFromIdentity(identity: number): DataTransferObject
	return Objects[identity]
end

function Module.send(player: Player)
	local buff = buffer_create(Top)
	buffer_copy(buff, 0, Buffer, 0, Top)
	buffer_fill(Buffer, 0, 0, Top)
	Top = 0

	if #Miscellaneous == 0 then
		Remote:FireClient(player, buff)
	else
		Remote:FireClient(player, buff, Miscellaneous)
	end
	
	table_clear(Miscellaneous)
end

-- Register a DataTransferClass for use.
function Module.registerClass(dataTransferClass: DataTransferClass, id: number?)
	if id then
		assert(id >= 0 and id <= 255, "Class registry ID must be between 0 and 255.")
		assert(not Classes[id], "Attempt to override registered class.")
		Classes[id + 1] = dataTransferClass
		Classes[dataTransferClass] = id
	else
		local top = #Classes
		Classes[top + 1] = dataTransferClass
		Classes[dataTransferClass] = top
	end
	
	dataTransferClass.DTC = dataTransferClass.DTC or {}
	dataTransferClass.DTP = dataTransferClass.DTP or {}
	dataTransferClass.DTU = dataTransferClass.DTU or {}
end

-- Associate a method key, or name, with a specified or generated identity.
function Module.registerMethod(dataTransferClass: DataTransferClass, key: string, id: number?)
  	if not Classes[dataTransferClass] then
  		error(string_format("Class '%s' must be registered to register a method.", tostring(dataTransferClass))
  	end
  
  	if id then
        if id < 0 or id > 255 then
            error("Expected method registry ID to be between 0 and 255; got '%d'.", id)
        end
  	else
        id = #dataTransferClass.DTC
  	end
  
  	local dtc = dataTransferClass.DTC
  	dtc[id + 1], dtc[key] = key, id
  
  	local dtp, dtu = dataTransferClass.DTP, dataTransferClass.DTU
  	local dtpCallback, dtuCallback = dtp[key], dtu[key]
  	dtp[id + 1], dtu[id + 1] = dtpCallback, dtuCallback
end


-- -- Events

Remote.OnClientEvent:Connect(Module.receive)


-- -- End

return Module
