local backgroundAreas = require("backgroundAreas")
local blockManager = require("blockManager")

local backgroundArea = {}
local blockID = BLOCK_ID


local backgroundAreaSettings = {
	id = blockID,

	sizeable = true,
	passthrough = true,
}

blockManager.setBlockSettings(backgroundAreaSettings)


backgroundAreas.blockID = blockID


return backgroundArea