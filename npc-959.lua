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

		data.rotation = 0
	end,

	updateMovement = function(npc,timer,moveIteration,translationOnly)
		local settings = npc.data._settings
		local data = npc.data

		local newRotation = timer*360

		if settings.movement.counterclockwise then
			newRotation = -newRotation
		end

		data.layerMover:rotate(vector(npc.x + npc.width*0.5,npc.y + npc.height*0.5),newRotation - data.rotation,translationOnly)
		data.rotation = newRotation
	end,

	debugGetPreviewsForPoint = function(npc,x,y)
		local settings = npc.data._settings
		local data = npc.data

		local pivot = vector(npc.x + npc.width*0.5,npc.y + npc.height*0.5)
		local pivotDifference = vector(x - npc.x - npc.width*0.5,y - npc.y - npc.height*0.5)

		local list = {}

		for rotation = 0,270,90 do
			table.insert(list,pivot + pivotDifference:rotate(rotation - data.rotation))
		end

		return list
	end,

	debugColor = Color.fromHexRGB(0xFFA500),
},layerControllers.controllerSharedSettings)

npcManager.setNpcSettings(controllerNPCSettings)

layerControllers.registerController(npcID)

return controllerNPC