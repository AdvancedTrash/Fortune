local barrel = {}

local npcManager = require("npcManager")
local barrelAI = require("AI/NewlaunchBarrels")

local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local barrelSettings = {
	id = npcID,
	playerCharacter = 5,
}

--Applies NPC settings
npcManager.setNpcSettings(barrelSettings)

barrelAI.registerBarrel(npcID, "rotate")

return barrel