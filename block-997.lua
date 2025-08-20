--[[

	Editor graphic by Valentine

]]

local respawnRooms = require("respawnRooms")
local blockManager = require("blockManager")

local room = {}
local blockID = BLOCK_ID

local roomSettings = {
	id = blockID,

	sizable = true,
	passthrough = true,
}

blockManager.setBlockSettings(roomSettings)

respawnRooms.roomBlockID = blockID

return room