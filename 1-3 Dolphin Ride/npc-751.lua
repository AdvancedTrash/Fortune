--[[

	Written by MrDoubleA
	Please give credit!

    Part of MrDoubleA's NPC Pack

]]

local npcManager = require("npcManager")
local npcutils = require("npcs/npcutils")

local blockutils = require("blocks/blockutils")


local blockWings = {}
local npcID = NPC_ID

local blockWingsSettings = {
	id = npcID,
	
	gfxwidth = 32,
	gfxheight = 32,

	gfxoffsetx = 16,
	gfxoffsety = 14,
	
	width = 64,
	height = 50,
	
	frames = 2,
	framestyle = 1,
	framespeed = 16,
	
	speed = 1,
	
	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt = true,
	nogravity = true,
	noblockcollision = true,
	nofireball = true,
	noiceball = true,
	noyoshi = true,
	nowaterphysics = true,
	
	jumphurt = true,
	spinjumpsafe = false,
	harmlessgrab = true,
	harmlessthrown = true,

	ignorethrownnpcs = true,
	notcointransformable = true,
	staticdirection = true,


	searchCentreOffsetX = 0,
	searchCentreOffsetY = -16,

	flyAwaySound = Misc.resolveSoundFile("swooperflap"),
	flyAwayMaxSpeedX = 2,
	flyAwayMaxSpeedY = -8,
	flyAwayAccelerationX = 0.025,
	flyAwayAccelerationY = -0.125,
}

npcManager.setNpcSettings(blockWingsSettings)
npcManager.registerHarmTypes(npcID,{},{})


function blockWings.onInitAPI()
	npcManager.registerEvent(npcID, blockWings, "onTickNPC")
	npcManager.registerEvent(npcID, blockWings, "onDrawNPC")

	registerEvent(blockWings, "onPostBlockHit")
	registerEvent(blockWings, "onDrawEnd")
end


local function setFrames(v,data,config,settings)
	local baseFrame = math.floor(data.animationTimer/config.framespeed) % config.frames

	data.wingFrames[1] = npcutils.getFrameByFramestyle(v,{frame = baseFrame,direction = DIR_LEFT})
	data.wingFrames[2] = npcutils.getFrameByFramestyle(v,{frame = baseFrame,direction = DIR_RIGHT})
end

local function flyAway(v,data,config,settings)
	if data.block ~= nil and data.block.isValid then
		data.block.extraSpeedX = 0
		data.block.extraSpeedY = 0
		data.block._wingsNPC = nil
	end

	data.noBlock = true
	v.spawnId = 0

	if v.despawnTimer > 150 then
		SFX.play(config.flyAwaySound)
	end
end


local function isValidBlock(v,b)
	return (b ~= nil and b.isValid and b.layerName == v.layerName and not b.isHidden)
end

local function isBetterPick(closestBlock,b)
	if closestBlock.contentID == 0 and b.contentID > 0 then
		return true
	end

	local configClosest = Block.config[closestBlock.id]
	local config = Block.config[b.id]

	if not configClosest.bumpable and config.bumpable then
		return true
	end

	return false
end


local function findBlock(v,data,config,settings)
	if data.noBlock then
		return
	elseif data.block ~= nil then
		if data.block.isValid then
			data.block.isHidden = false
		end

		return
	end

	local closestDistance = math.huge
	local closestBlock

	local centreX = v.x + v.width*0.5 + config.searchCentreOffsetX
	local centreY = v.y + v.height + config.searchCentreOffsetY

	for _,b in Block.iterateIntersecting(centreX-4,centreY-4,centreX+4,centreY+4) do
		if isValidBlock(v,b) and b.data._wingsNPC == nil then
			local difference = vector((b.x + b.width*0.5) - centreX,(b.y + b.height*0.5) - centreY)
			local distance = difference.length

			if distance < closestDistance or isBetterPick(closestBlock,b) then
				closestDistance = distance
				closestBlock = b
			end
		end
	end

	if closestBlock ~= nil then
		data.block = closestBlock
		data.blockWidth = closestBlock.width
		data.blockHeight = closestBlock.height

		closestBlock.data._wingsNPC = v

		data.noBlock = false
	else
		data.block = nil
		data.blockWidth = 32
		data.blockHeight = 32

		flyAway(v,data,config,settings)
	end
end

local function initialise(v,data,config,settings)
	data.movementTimer = 0

	data.animationTimer = 0
	data.wingFrames = {0,0}

	findBlock(v,data,config,settings)
	setFrames(v,data,config,settings)

	data.initialized = true
end



-- Movement behaviours
local MOVEMENT_STILL = 0
local MOVEMENT_STRAIGHT_HOR = 1
local MOVEMENT_STRAIGHT_VER = 2
local MOVEMENT_TURN_HOR = 3
local MOVEMENT_TURN_VER = 4
local MOVEMENT_FOLLOW_HOR = 5
local MOVEMENT_FOLLOW_VER = 6

local movementFuncs = {}
local movementIsVertical = {}


local function getSettingSuffix(isVertical)
	if isVertical then
		return "v"
	else
		return "h"
	end
end


local function movementStill(v,data,config,settings,speed,isVertical)
	return 0
end

local function movementFlyStraight(v,data,config,settings,speed,isVertical)
	local settingSuffix = getSettingSuffix(isVertical)

	return (settings["straight_".. settingSuffix.. "_speed"] or 2.5)*v.direction
end

local function movementFlyAndTurn(v,data,config,settings,speed,isVertical)
	local settingSuffix = getSettingSuffix(isVertical)

	local distance = (settings["turn_".. settingSuffix.. "_distance"] or 128)*0.5*v.direction
	local time = (settings["turn_".. settingSuffix.. "_time"] or 320)/(math.pi*2)

	return math.sin(data.movementTimer/time)/time*distance
end

local function movementFollow(v,data,config,settings,speed,isVertical)
	local settingSuffix = getSettingSuffix(isVertical)

	local p = npcutils.getNearestPlayer(v)
	local direction

	if isVertical then
		direction = math.sign((p.y + p.height*0.5) - (v.y + v.height - data.blockHeight*0.5))
	else
		direction = math.sign((p.x + p.width*0.5) - (v.x + v.width*0.5))
	end

	local acceleration = (settings["follow_".. settingSuffix.. "_acceleration"] or 0.1)*direction
	local maxSpeed = settings["follow_".. settingSuffix.. "_maxSpeed"] or 4

	speed = math.clamp(speed + acceleration,-maxSpeed,maxSpeed)

	return speed
end


movementFuncs[MOVEMENT_STILL] = movementStill
movementIsVertical[MOVEMENT_STILL] = false
movementFuncs[MOVEMENT_STRAIGHT_HOR] = movementFlyStraight
movementIsVertical[MOVEMENT_STRAIGHT_HOR] = false
movementFuncs[MOVEMENT_STRAIGHT_VER] = movementFlyStraight
movementIsVertical[MOVEMENT_STRAIGHT_VER] = true
movementFuncs[MOVEMENT_TURN_HOR] = movementFlyAndTurn
movementIsVertical[MOVEMENT_TURN_HOR] = false
movementFuncs[MOVEMENT_TURN_VER] = movementFlyAndTurn
movementIsVertical[MOVEMENT_TURN_VER] = true
movementFuncs[MOVEMENT_FOLLOW_HOR] = movementFollow
movementIsVertical[MOVEMENT_FOLLOW_HOR] = false
movementFuncs[MOVEMENT_FOLLOW_VER] = movementFollow
movementIsVertical[MOVEMENT_FOLLOW_VER] = true



function blockWings.onTickNPC(v)
	if Defines.levelFreeze then return end
	
	local data = v.data
	
	if v.despawnTimer <= 0 then
		if data.initialized then
			if not data.noBlock and isValidBlock(v,data.block) then
				data.block.isHidden = true
			end

			data.initialized = false
		end

		return
	end

	local settings = v.data._settings
	local config = NPC.config[v.id]

	if not data.initialized then
		initialise(v,data,config,settings)
	end


	if not data.noBlock and not isValidBlock(v,data.block) then
		flyAway(v,data,config,settings)
	end

	if not data.noBlock then
		-- Update speed
		local floatSpeed = math.cos(lunatime.tick()/20)*1
		
		if movementIsVertical[settings.movement] then
			v.speedY = movementFuncs[settings.movement](v,data,config,settings,v.speedY,true)
			v.speedX = floatSpeed
		else
			v.speedX = movementFuncs[settings.movement](v,data,config,settings,v.speedX,false)
			v.speedY = floatSpeed
		end

		data.movementTimer = data.movementTimer + 1


		-- Move2 block accordingly
		local newBlockX = v.x + v.speedX + v.width*0.5 - data.block.width*0.5
		local newBlockY = v.y + v.speedY + v.height - data.block.height

		data.block.extraSpeedX = (newBlockX - data.block.x) - data.block.layerSpeedX
		data.block.extraSpeedY = (newBlockY - data.block.y) - data.block.layerSpeedY
		data.blockWidth = data.block.width
		data.blockHeight = data.block.height

		data.block:translate(data.block.extraSpeedX,data.block.extraSpeedY)

		data.animationTimer = data.animationTimer + 1
	else
		v.speedX = math.clamp(v.speedX + v.direction*config.flyAwayAccelerationX,-config.flyAwayMaxSpeedX,config.flyAwayMaxSpeedX)
		v.speedY = math.max(config.flyAwayMaxSpeedY,v.speedY + config.flyAwayAccelerationY)

		data.animationTimer = data.animationTimer + 2
	end

	setFrames(v,data,config,settings)
end


local hiddenBlocks = {}

function blockWings.onDrawNPC(v)
	if v.despawnTimer <= 0 or v.isHidden then return end

	local settings = v.data._settings
	local config = NPC.config[v.id]
	local data = v.data

	if not data.initialized then
		initialise(v,data,config,settings)
	end


	local blockXOffset = 0
	local blockYOffset = 0

	if not data.noBlock and isValidBlock(v,data.block) and not data.block.isHidden and not data.block:mem(0x5A,FIELD_BOOL) then
		local blockImage = Graphics.sprites.block[data.block.id].img
		local blockConfig = Block.config[data.block.id]

		local blockFrame = blockutils.getBlockFrame(data.block.id)

		blockYOffset = data.block:mem(0x56,FIELD_WORD)

		Graphics.drawImageToSceneWP(blockImage,data.block.x,data.block.y + blockYOffset,0,blockFrame*blockConfig.height,data.block.width,data.block.height,-64)

		table.insert(hiddenBlocks,data.block)
		data.block.isHidden = true
	end


	local wingImage = Graphics.sprites.npc[v.id].img

	local wingWidth = config.gfxwidth
	local wingHeight = config.gfxheight

	for wingIndex = 0,1 do
		local wingFrame = data.wingFrames[wingIndex + 1]
		local wingDirection = wingIndex*2 - 1

		local wingX = v.x + v.width*0.5 + (data.blockWidth*0.5 + config.gfxoffsetx)*wingDirection + blockXOffset
		local wingY = v.y + v.height - data.blockHeight - wingHeight + config.gfxoffsety + blockYOffset

		if wingIndex == 1 then
			wingX = wingX - wingWidth
		end

		Graphics.drawImageToSceneWP(wingImage,wingX,wingY,0,wingFrame*wingHeight,wingWidth,wingHeight,-64.1)
	end


	npcutils.hideNPC(v)
end


function blockWings.onDrawEnd()
	local i = 1

	while (true) do
		local b = hiddenBlocks[i]
		if b == nil then
			break
		end

		if b.isValid then
			b.isHidden = false
		end

		hiddenBlocks[i] = nil
		i = i + 1
	end
end


function blockWings.onPostBlockHit(b,fromTop,playerObj)
	local v = b.data._wingsNPC

	if v == nil or not v.isValid or v.despawnTimer <= 0 then
		return
	end

	local data = v.data

	if not data.initialized or data.noBlock or data.block ~= b or not isValidBlock(v,b) then
		return
	end

	local blockConfig = Block.config[b.id]

	if not blockConfig.bumpable and b.contentID == 0 then -- bump won't actually do anything
		return
	end


	local settings = v.data._settings
	local config = NPC.config[v.id]

	if settings.flyAfterHit then
		flyAway(v,data,config,settings)
	end
end


return blockWings