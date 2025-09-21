--[[

    Layer Controllers
    by MrDoubleA

]]

local npcManager = require("npcManager")

local layerControllers = require("layerControllers")

local controllerNPC = {}
local npcID = NPC_ID

local controllerNPCSettings = table.join({
	id = npcID,

	initialiseMovement = function(npc)
		local data = npc.data

		data.offsetX = 0
		data.offsetY = 0
	end,

	updateMovement = function(npc,timer,moveIteration,translationOnly)
		local settings = npc.data._settings
		local data = npc.data

		if moveIteration%2 == 1 then
			timer = 1 - timer
		end

		local newOffsetX = settings.movement.distanceX*timer*32
		local newOffsetY = settings.movement.distanceY*timer*32

		data.layerMover:translate(newOffsetX - data.offsetX,newOffsetY - data.offsetY,translationOnly)

		data.offsetX = newOffsetX
		data.offsetY = newOffsetY
	end,

	debugGetPreviewsForPoint = function(npc,x,y)
		local settings = npc.data._settings
		local data = npc.data

		return {
			vector(x - data.offsetX,y - data.offsetY),
			vector(x + settings.movement.distanceX*32 - data.offsetX,y + settings.movement.distanceY*32 - data.offsetY),
		}
	end,
	debugGetCurrentOffset = function(npc)
		local data = npc.data

		return vector(data.offsetX,data.offsetY)
	end,
	debugGetPaths = function(npc)
		local settings = npc.data._settings

		local startPoint = vector(npc.x + npc.width*0.5,npc.y + npc.height*0.5)
		local stopPoint = startPoint + vector(settings.movement.distanceX*32,settings.movement.distanceY*32)

		return {
			{startPoint,stopPoint},
			{stopPoint,startPoint},
		}
	end,

	debugColor = Color.fromHexRGB(0x00C715),
},layerControllers.controllerSharedSettings)

npcManager.setNpcSettings(controllerNPCSettings)

layerControllers.registerController(npcID)

return controllerNPC