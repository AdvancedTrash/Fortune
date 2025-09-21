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
		local settings = npc.data._settings
		local data = npc.data

		local rotation = math.rad(settings.movement.startAngle)

		data.radiusX = settings.movement.radiusX*32
		data.radiusY = settings.movement.radiusY*32

		data.startOffsetX = math.sin(rotation)*data.radiusX
		data.startOffsetY = -math.cos(rotation)*data.radiusY

		data.offsetX = 0
		data.offsetY = 0
	end,

	updateMovement = function(npc,timer,moveIteration,translationOnly)
		local settings = npc.data._settings
		local data = npc.data

		local rotation = math.rad(settings.movement.startAngle + timer*360)

		local newOffsetX = math.sin(rotation)*data.radiusX - data.startOffsetX
		local newOffsetY = -math.cos(rotation)*data.radiusY - data.startOffsetY

		data.layerMover:translate(newOffsetX - data.offsetX,newOffsetY - data.offsetY,translationOnly)

		data.offsetX = newOffsetX
		data.offsetY = newOffsetY
	end,

	debugGetPreviewsForPoint = function(npc,x,y)
		local settings = npc.data._settings
		local data = npc.data

		--local pivot = vector(npc.x + npc.width*0.5,npc.y + npc.height*0.5)
		--local pivotDifference = vector(x - npc.x - npc.width*0.5,y - npc.y - npc.height*0.5)

		local list = {}

		for baseRotation = 0,270,90 do
			local rotation = math.rad(settings.movement.startAngle + baseRotation)

			local pointX = x + math.sin(rotation)*data.radiusX - data.startOffsetX - data.offsetX
			local pointY = y - math.cos(rotation)*data.radiusY - data.startOffsetY - data.offsetY

			table.insert(list,vector(pointX,pointY))
		end

		return list
	end,
	debugGetCurrentOffset = function(npc)
		local data = npc.data

		return vector(data.offsetX,data.offsetY)
	end,
	debugGetPaths = function(npc)
		local settings = npc.data._settings
		local data = npc.data

		--local startPoint = vector(npc.x + npc.width*0.5,npc.y + npc.height*0.5)
		--local stopPoint = startPoint + vector(settings.movement.distanceX*32,settings.movement.distanceY*32)

		local divisions = 24
		local points = {}

		for i = 0,divisions do
			local rotation = math.rad(settings.movement.startAngle + i/divisions*360)

			local pointX = npc.x + npc.width*0.5 + math.sin(rotation)*data.radiusX - data.startOffsetX
			local pointY = npc.y + npc.height*0.5 - math.cos(rotation)*data.radiusY - data.startOffsetY

			table.insert(points,vector(pointX,pointY))
		end

		return {points}
	end,

	debugColor = Color.fromHexRGB(0xE50959),
},layerControllers.controllerSharedSettings)

npcManager.setNpcSettings(controllerNPCSettings)

layerControllers.registerController(npcID)

return controllerNPC