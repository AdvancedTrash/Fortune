--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local npcutils = require("npcs/npcutils")
local redirector = require("redirector")
local playerStun = require("playerstun")
local playerManager = require("playermanager")
local lineguide = require("lineguide")
local twisterai = require("npcs/ai/twister")
local easing = require("ext/easing")

local sampleNPC = {}

local npcIDs = {}

sampleNPC.CreatorLineguideSettings = {
	speed = 3,
}

function sampleNPC.register(id)
	npcManager.registerEvent(id, sampleNPC, "onTickNPC")
	npcManager.registerEvent(id, sampleNPC, "onTickEndNPC")
	npcManager.registerEvent(id, sampleNPC, "onDrawNPC")
	npcManager.registerEvent(id, sampleNPC, "onEventNPC")
	
    lineguide.registerNpcs(id)
	twisterai.whitelist(id)
	
	npcIDs[id] = true
end

function sampleNPC.onInitAPI()
    registerEvent(sampleNPC, "onNPCHarm")
	registerEvent(sampleNPC, "onNPCKill")
end

local function getSlopeSteepness(v)
	local greatestSteepness = 0

	for _,b in Block.iterateIntersecting(v.x,v.y + v.height,v.x + v.width,v.y + v.height + 0.2) do
		if not b.isHidden and not b:mem(0x5A,FIELD_BOOL) then
			local config = Block.config[b.id]

			if config ~= nil and config.floorslope ~= 0 and not config.passthrough and config.npcfilter == 0 then
				local steepness = b.height/b.width

				if steepness > math.abs(greatestSteepness) then
					greatestSteepness = steepness*config.floorslope
				end
			end
		end
	end

	return greatestSteepness
end

-- This function takes in a number and returns its binary form as a string
function toBinary(num)
	local bin = ""  -- Create an empty string to store the binary form
	local rem  -- Declare a variable to store the remainder

	-- This loop iterates over the number, dividing it by 2 and storing the remainder each time
	-- It stops when the number has been divided down to 0
	while num > 0 do
		rem = num % 2  -- Get the remainder of the division
		bin = rem .. bin  -- Add the remainder to the string (in front, since we're iterating backwards)
		num = math.floor(num / 2)  -- Divide the number by 2
	end

	return bin  -- Return the string
end

-- Fun fact: this function is based off of the source code!
local coinsPointer = 0x00B2C5A8
local livesPointer = 0x00B2C5AC
local function addCoins(amount)
    mem(coinsPointer,FIELD_WORD,(mem(coinsPointer,FIELD_WORD)+amount))

    if mem(coinsPointer,FIELD_WORD) >= 100 then
        if mem(livesPointer,FIELD_FLOAT) < 99 then
            mem(livesPointer,FIELD_FLOAT,(mem(livesPointer,FIELD_FLOAT)+math.floor(mem(coinsPointer,FIELD_WORD)/100)))
            SFX.play(15)

            mem(coinsPointer,FIELD_WORD,(mem(coinsPointer,FIELD_WORD)%100))
        else
            mem(coinsPointer,FIELD_WORD,99)
        end
    end
end

--This function creates a light source for the NPC if the correct setings are applied
local function lightSettings(v)
	local data = v.data
	local settings = v.data._settings
	
	if not data.npcCreatorlight then
		data.npcCreatorlight = Darkness.light(v.x + (v.width * 0.5) + settings.gfxoffsetx + settings.lightoffsetx, v.y + (v.height * 0.5) + settings.gfxoffsety + settings.lightoffsety, settings.lightradius, settings.lightbrightness, settings.lightcolor, settings.lightflicker)
	end
	
	data.npcCreatorlight.x = v.x + (v.width * 0.5) + settings.gfxoffsetx + settings.lightoffsetx
	data.npcCreatorlight.y = v.y + (v.height * 0.5) + settings.gfxoffsety + settings.lightoffsety
	
	if v.despawnTimer <= 0 then Darkness.removeLight(data.npcCreatorlight) return end
end

local function drawHPBar(v)
	local data = v.data
	local properties = {
		meterTexture = Graphics.loadImageResolved("Additional Assets/npc-hp-meter.png"),
		barTexture = Graphics.loadImageResolved("Additional Assets/npc-hp-bar.png"),
		barPivot = Sprite.align.LEFT,
		barScale = Sprite.barscale.HORIZONTAL,
		targetX = v.x + v.width * 0.5,
		targetY = v.y + v.height * 0.5,
	}
	data.meter = Sprite.box{
			texture = properties.meterTexture,
			pivot = Sprite.align.CENTER,
			x = properties.targetX,
			y = properties.targetY,
	}
	data.bar = Sprite.bar{
		texture = properties.barTexture,
		pivot = Sprite.align.CENTER,
		barpivot = properties.barPivot,
		scaletype = properties.barScale,
		bgtexture = Graphics.loadImageResolved("stock-0.png"),
		value = 1,
		width = properties.barTexture.width,
		height = properties.barTexture.height,
		x = properties.targetX,
		y = properties.targetY,
	}
	data.meter:addChild(data.bar.transform)
end

local soundOptions = {}

local function playSound(v)
	local data = v.data
	local currentSound
	local soundSplit
	
	if data.soundVariable == "" then return end
	
	soundSplit = string.split(data.soundVariable, ",")

	for i = 1,#soundSplit do
		table.insert(soundOptions, soundSplit[i])
	end
	
	currentSound = RNG.irandomEntry(soundOptions)
	
	local sound = tonumber(currentSound)
	if sound then
		SFX.play(sound)
	else
		SFX.play(currentSound)
	end
	
	soundOptions = nil
	soundOptions = {}
	soundSplit = nil
	data.soundVariable = ""
end

local effectOptions = {}

local function spawnEffect(v)
	local data = v.data
	local effectSplit
	
	if data.effectVariable == "" then return end
	
	effectSplit = string.split(data.effectVariable, ",")

	for i = 1,#effectSplit do
		table.insert(effectOptions, tonumber(effectSplit[i]))
	end
	
	local e = Effect.spawn(RNG.irandomEntry(effectOptions), v.x, v.y)
	e.direction = v.direction
	e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + v.data._settings.gfxoffsetx + (data.effectOffset.x * e.direction)
	e.y = v.y - ((e.height - e.height) + 1) + v.data._settings.gfxoffsety + data.effectOffset.y
	if data.effectSpeed then e.speedX, e.speedY = data.effectSpeed.x * v.direction, data.effectSpeed.y end
	effectOptions = nil
	effectSplit = nil
	effectOptions = {}
	data.effectVariable = ""
end

local function spawnNPC(v)
	local data = v.data
	local settings = v.data._settings
	
	data.randomX = data.spawnSpeedX[data.state + 1]
	data.randomY = data.spawnSpeedY[data.state + 1]
	
	for i = 1,data.burst[data.state + 1] do
		local n = NPC.spawn(data.spawnedNPC[data.state + 1], v.x + (v.width / 2) + data.spawnX[data.state + 1], v.y + (v.height / 2) + data.spawnY[data.state + 1], player.section, false)
		
		if data.deathParent[data.state + 1] then n.data.NPCCreatorspawnedNPCID = v.idx end
		
		if data.spawnDirection[data.state + 1] == 1 then
			n.direction = v.direction
		elseif data.spawnDirection[data.state + 1] == 0 or data.spawnDirection[data.state + 1] == 2 then
			n.direction = data.spawnDirection[data.state + 1] - 1
		end
		
		n.x = (v.x - ((n.width / 2) - v.width) - (v.width / 2)) + (data.spawnX[data.state + 1] * n.direction)
		n.y = v.y - ((n.height - v.height) + 1) + data.spawnY[data.state + 1]
		
		--Various parameters
		if data.noblockcollisionSpawned[data.state + 1] then n.noblockcollision = false else n.noblockcollision = true end
		if data.projectileSpawned[data.state + 1] then n.isProjectile = true else n.isProjectile = false end
		if data.friendlySpawned[data.state + 1] then n.friendly = true else n.friendly = false end
		if data.dontmoveSpawned[data.state + 1] then n.dontMove = false else n.dontMove = true end
		
		--Target player's X and Y coords if the option is given
		data.dirVectr = vector.v2(
			(Player.getNearest(v.x + v.width/2, v.y + v.height).x) - (v.x + v.width * 0.5),
			(Player.getNearest(v.x + v.width/2, v.y + v.height).y) - (v.y + v.height * 0.5)
		):normalize() * 6
		
		--Spread shot logic
		local d
		if (i % 2 == 0) then d = 1 else d = -1 end
		data.h = data.h or 0
		data.v = data.v or 0
		if (i % 2 == 0) then data.h = data.h + data.alterX[data.state + 1] data.v = data.v - (data.alterY[data.state + 1] / data.burst[data.state + 1]) end
		local spawnedAmountX = ((data.h) * d)
		local spawnedAmountY = ((data.v) * math.sign(data.spawnSpeedY[data.state + 1]))
		
		--Random movement for when you spawn an npc
		if data.randomCheck[data.state + 1] then
			if data.randomSpeedX[data.state + 1] < data.spawnSpeedX[data.state + 1] then data.randomX = data.randomSpeedX[data.state + 1] end
			if data.randomSpeedY[data.state + 1] < data.spawnSpeedY[data.state + 1] then data.randomY = data.randomSpeedX[data.state + 1] end
		end	
		
		if not data.targetX[data.state + 1] then n.speedX = RNG.random(data.randomX, data.spawnSpeedX[data.state + 1]) * v.direction + (spawnedAmountX) else n.speedX = data.dirVectr.x + (spawnedAmountX) end
		if not data.targetY[data.state + 1] then n.speedY = RNG.random(data.randomY, data.spawnSpeedY[data.state + 1]) + (spawnedAmountY) else n.speedY = data.dirVectr.y + (spawnedAmountY) end
		
		data.split = string.split(data.spawnAI[data.state + 1], ",")
		
		--Fail safe if something isnt inputted correctly
		for i = 1,6 do
			if type(tonumber(data.split[i])) ~= "number" then data.split[i] = 0 end
			if not data.split[i] then data.split[i] = 0 end
		end
		
		--Give any of the AI fields a desired input
		n.ai1, n.ai2, n.ai3, n.ai4, n.ai5, n.ai6 = tonumber(data.split[1]), tonumber(data.split[2]), tonumber(data.split[3]), tonumber(data.split[4]), tonumber(data.split[5]), tonumber(data.split[6])
		
		--Play a death sound when spawning
		
		data.soundVariable = data.spawnSound[data.state + 1]
		playSound(v)
		
	end
	data.h = 0
	data.v = 0
end

local function npcJump(v)
	local data = v.data
	local settings = v.data._settings
	if data.jumpAir[data.state + 1] == 0 then return end
	if v.collidesBlockBottom or data.jumpAir[data.state + 1] then
		v.speedY = -data.jumpHeight[data.state + 1]
		
		data.soundVariable = data.jumpSFX[data.state + 1]
		playSound(v)
		
		if data.jumpSpawn[data.state + 1] then
			spawnNPC(v)
		end
	end
end

function isNearWall(v)
	 v.data.collidingWall = Block.getIntersecting(
		v.x - (v.width * (32 / v.width)),   
		v.y,
		v.x + (((v.width * (32 / v.width))) * (v.width / 16)),
		v.y + v.height - 8
	)

    for _, b in ipairs(v.data.collidingWall) do
		if Block.config[b.id].floorslope ~= 0 then return false end
        if not Block.config[b.id].semisolid 
        and not Block.config[b.id].passthrough
        and not Block.config[b.id].sizable
        and not b.isHidden then
            return true
        end
    end
end

function isNearPit(v)

	 v.data.collidingPit = Block.getIntersecting(
		v.x + (v.width / 2) - 2, 
		v.y,
		v.x + (v.width / 2) + 2,
		v.y + v.height + 16
	)

    for _, b in ipairs(v.data.collidingPit) do
		if b.y >= v.y + v.height or Block.config[b.id].floorslope ~= 0 then
            return true
        end
    end
end

--These are different states the NPC can be in which refer to its "phases"
--The code here doesnt actually do anything, but it's a visual of what each state is
local STATE_1 = 0
local STATE_2 = 1
local STATE_3 = 2
local STATE_4 = 3
local STATE_5 = 4
local STATE_6 = 5
local STATE_7 = 6
local STATE_8 = 7
local STATE_9 = 8
local STATE_10 = 9

local yiYoshi
pcall(function() yiYoshi = require("yiYoshi/yiYoshi") end)

local propertyNames = {"maxHP", "hpdamage", "hpdamagefire", "rotationType", "rotationSpeed", "paralyse", "paralyseAnything", "cliffturn", "blockCollision", "harmless", "killThing", "friendly", "dontMove", "gravity", "water", "spawnTimer", "spawnedNPC", "targetX", "targetY", "spawnSpeedX", "spawnSpeedY", "spawnX", "spawnY", "spawnSound", "spawnDirection", "jumpTimer", "jumpAir", "jumpHeight", "jumpSpawn", "jumpSFX", "playerJump", "paragoombaJump", "knockback", "wallJump", "ledgeJump", "spawnAI", "noblockcollisionSpawned", "projectileSpawned", "friendlySpawned", "dontmoveSpawned", "horizontalMovement", "horizontalMovementSpeed", "horizAmplitude", "horizontalMovementSpeedSine", "sineMovement", "verticalMovement", "verticalMovementSpeed", "vertiAmplitude", "verticalMovementSpeedSine", "sineMovementVertical", "generalMovement", "sincosHorizontal", "sincosVertical", "redirector", "npcharm", "blockharm", "leftRight", "up", "down", "phaseChangeWall", "framesIdle", "framespeedIdle", "frameoffsetIdle", "frameoffsetIdleRight", "framesWalk", "framespeedWalk", "frameoffsetWalk", "frameoffsetWalkRight", "framesJump", "framespeedJump", "frameoffsetJump", "frameoffsetJumpRight", "framesFall", "framespeedFall", "frameoffsetFall", "frameoffsetFallRight", "framesShoot", "framespeedShoot", "frameoffsetShoot", "frameoffsetShootRight", "noHP", "jump", "below", "hitNPC", "hitProjectile", "lava", "held", "tail", "offscreen", "sword", "approachState", "approach", "leaveNPCState", "leaveNPC", "facingLeft", "facingRight", "stateTimed", "stateTimedState", "phaseWidth", "phaseHeight", "phaseSFX", "explode", "die", "phaseEffect", "phaseEvent", "phaseHP", "jumpTimerPhase", "stateTimedPhase", "spawnTimerPhase", "upTrigger", "downTrigger", "stun", "eventChangePhase", "hpdamagefireSFX", "hpdamageSFX", "phaseEffectOffsetX", "phaseEffectOffsetY", "lineGuide", "shake", "burst", "alterX", "alterY", "randomCheck", "randomSpeedX", "randomSpeedY", "hurtfulStomp", "spring", "springForce", "deathParent", "continuousSound", "soundInterval", "generalTimerX", "generalTimerY", "vine", "coin", "coinValue", "collidePlayerState", "collideNPCState", "collideNPCStateIDs", "trailNPCCount", "trailNPCStyle", "trailX", "trailY", "altAnimationTimer", "flipped", "flippedHeld", "resetStateTimer", "phaseEffectSpeed", "inWaterState", "outWaterState", "phaseJump", "phaseDirection", "framesMelee", "framespeedMelee", "frameoffsetMelee", "frameoffsetMeleeRight", "meleeTimer", "meleeTime", "meleeSpeed", "meleeHeight", "meleeWidth", "meleeX", "meleeY", "meleePlayer", "meleeNPC", "meleeBlock", "meleeSpin", "meleeDebug", "meleeTimerPhase", "meleeSFX", "dieHeld", "waypoint", "waypointXY", "waypointExactXY", "waypointStateTimer", "waypointTeleport", "meleePhase", "generalEffect", "generalEffectX", "generalEffectY", "generalEffectRandomX", "generalEffectRandomY", "generalEffectDelay", "phaseSpawnDie", "air"}

local function initSettings(v)
	local data = v.data
	local settings = v.data._settings
	
	for _,name in ipairs(propertyNames) do
		data[name] = {}

		for i = 1,10 do
			data[name][i] = settings[name.. i]
		end
	end
end

local sectionObj = Section(player.section)

local function init(v)
	local data = v.data
	
	data.noHurt = 0
	data.rotation = 0
	data.stateTimer = 0
	data.spawntimer = 0
	data.meleetimer = 0
	data.jumptimer = 0
	data.JumpTableIndex = 0
	data.walkState = 0
	data.walkTimer = 0
	data.walkDirection = -1
	data.exitSide = -1
	data.vineActive = 0
	data.sinOrCosMath = {math.sin, math.cos}
	data.sinOrCos = nil
	data.save = nil
	data.wander = nil
	data.verticalMoveSMWEnemy = nil
	data.stunned = true
	data.miscSettingController = vector.zero2
	
	data.NPCCollision = nil
	data.NPCCollisionSplit = nil
	data.NPCCollision = {}
	if data.collideNPCStateIDs[data.state + 1] ~= "" then
		data.NPCCollisionSplit = string.split(data.collideNPCStateIDs[data.state + 1], ",")
		for i = 1,#data.NPCCollisionSplit do
			table.insert(data.NPCCollision, tonumber(data.NPCCollisionSplit[i]))
		end
	end
	
	if data.generalTimerX[data.state + 1] > -1 then data.miscSettingController.x = data.generalTimerX[data.state + 1] else data.miscSettingController.x = nil end
	if data.generalTimerY[data.state + 1] > -1 then data.miscSettingController.y = data.generalTimerY[data.state + 1] else data.miscSettingController.y = nil end
	
	
	--Make a melee hitbox
	data.melee = nil
	if data.meleeTimer[data.state + 1] >= 0 then
		data.melee = Colliders.Box(v.x, v.y, data.meleeWidth[data.state + 1], data.meleeHeight[data.state + 1])
	end
end

--A bunch of tables for different things
local options = {}
local trailX = {}
local trailY = {}
local vectorAngle = {}

local function changeStates(v)
	local data = v.data
	local settings = v.data._settings
	if data.cantChangeStates then return end
	if data.stateVariable == "" then return end
	if data.bounceAnimation and data.bounceAnimation > 1 then return end
	if lunatime.tick() <= 1 then return end
	
	data.phaseSplit = string.split(data.stateVariable, ",")

	if not data.upTrigger[data.state + 1] and Player.getNearest(v.x + v.width/2, v.y + v.height).y < v.y then return end
	if not data.downTrigger[data.state + 1] and Player.getNearest(v.x + v.width/2, v.y + v.height).y >= v.y then return end

	for i = 1,#data.phaseSplit do
		if type(tonumber(data.phaseSplit[i])) ~= "number" then data.phaseSplit[i] = 0 return end
		if tonumber(data.phaseSplit[i]) <= 0 or tonumber(data.phaseSplit[i]) > 10 then return end
		table.insert(options, tonumber(data.phaseSplit[i]) - 1)
	end
	
	data.trailSplit = nil
	
	if data.trailNPCs then
		for i=#data.trailNPCs,1,-1 do
			if data.trailNPCs[i].isValid and data.trailNPCs[i].heldIndex == 0 and data.trailNPCStyle[data.state + 1] ~= 2 then
				data.trailNPCs[i]:kill(HARM_TYPE_OFFSCREEN)
				data.trailNPCs[i] = nil
			end
		end
	end
	
	data.state = RNG.irandomEntry(options)
	options = nil
	options = {}
	
	data.trailNPCs = nil
	data.trailNPCs = {}
	
	if data.save then
		data.hp = data.maxHP[data.state + 1]
		data.currentMaxHP = data.maxHP[data.state + 1]
		if settings.hpbar then 
			data.barTimer = 0
			data.hpBarTimer = 0
			data.barcolor = Color.green
			data.bar.value = 1
		end
		SFX.play(39)
		data.save = nil
	end
	
	data.damageFire = data.hpdamagefire[data.state + 1]
	data.normalDamage = data.hpdamage[data.state + 1]
	
	--A single line that controls whether or not it should be on lineguides
	if data.lineGuide[data.state + 1] then v.data._basegame.lineguide.state = 2 else v.data._basegame.lineguide.attachCooldown = 2 v.data._basegame.lineguide.state = nil end
	
	v.data._basegame.lineguide.lineSpeed = data.horizontalMovementSpeed[data.state + 1]
	
	--Set width and height
	if data.phaseWidth[data.state + 1] >= -1 then
		v.x = v.x - ((data.phaseWidth[data.state + 1] / 2) - v.width) - (v.width / 2)
		v.width = data.phaseWidth[data.state + 1]
	end
	
	if data.phaseHeight[data.state + 1] >= -1 then
		v.y = v.y - (data.phaseHeight[data.state + 1] - v.height) + 1
		v.height = data.phaseHeight[data.state + 1] - 1
	end
	
	--Play a death sound when changing states
	data.soundVariable = data.phaseSFX[data.state + 1]
	playSound(v)
	
	if data.phaseHP[data.state + 1] >= 0 then
		data.hp = data.phaseHP[data.state + 1]
		data.currentMaxHP = data.phaseHP[data.state + 1]
		if settings.hpbar then 
			data.barTimer = 0
			data.hpBarTimer = 0
			data.barcolor = Color.green
			data.bar.value = 1
		end
	end
	
	--Optionally trigger an event
	if data.phaseEvent[data.state + 1] then
		triggerEvent(data.phaseEvent[data.state + 1])
	end
	
	--die
	if data.die[data.state + 1] then
		settings.ownEffect = 0
		settings.ownEffectSquish = 0
		v:kill(9)
	end
	
	data.effectVariable = data.phaseEffect[data.state + 1]
	data.effectOffset = vector.v2(data.phaseEffectOffsetX[data.state + 1], data.phaseEffectOffsetY[data.state + 1])
	data.effectSpeed = {}
	data.effectSpeed.x, data.effectSpeed.y = data.phaseEffectSpeed[data.state + 1].x, data.phaseEffectSpeed[data.state + 1].y
	spawnEffect(v)
	
	--Spawn trailing NPCs
	
	if data.trailNPCCount[data.state + 1] and data.trailNPCCount[data.state + 1] ~= "" then
		data.trailSplit = string.split(data.trailNPCCount[data.state + 1], ",")
		data.trailSplitX = string.split(data.trailX[data.state + 1], ",")
		data.trailSplitY = string.split(data.trailY[data.state + 1], ",")	
		
		for i = 1,#data.trailSplit do
			data.trailNPCs[i] = NPC.spawn(tonumber(data.trailSplit[i]) or 1, v.x, v.y, player.section, false)
			data.trailNPCs[i].friendly = v.friendly
			data.trailNPCs[i].dontMove = v.dontMove
			data.trailNPCs[i].layerName = v.layerName
			data.trailNPCs[i].collisionGroup = "currentlyBeingTrailed"
			
			if type(tonumber(data.trailSplitX[i])) ~= "number" then data.trailSplitX[i] = 0 end
			if type(tonumber(data.trailSplitY[i])) ~= "number" then data.trailSplitY[i] = 0 end
			
			table.insert(trailX, tonumber(data.trailSplitX[i]) or 0)
			table.insert(trailY, tonumber(data.trailSplitY[i]) or 0)
			
		end
		
		v.collisionGroup = "currentlyTrailing"
		Misc.groupsCollide["currentlyTrailing"]["currentlyBeingTrailed"] = false
		
		data.trailOffset = (data.trailNPCs[1].width * #data.trailSplit * 2) + trailX[1]
		
		data.maxHistoryCount = math.max(#data.trailSplit*data.trailOffset,1)
		data.tailHistory = {}
		data.npcRotation = {}
		data.npcDirection = {}
		
		--The spawn position of the trail NPCs
		local startPos = vector(
            v.x + 0.5 * v.width,
            v.y + 0.5 * v.height)
		for i=1,data.maxHistoryCount do
			data.tailHistory[i] = vector(startPos.x, startPos.y)
			data.npcRotation[i] = data.rotation
			data.npcDirection[i] = v.direction
		end
	end
	
	data.trailXX = trailX
	trailX = nil
	trailX = {}
	
	data.trailYY = trailY
	trailY = nil
	trailY = {}
	
	if data.noSmoke then
		if data.noSmoke == 2 then data.noSmoke = 1 else data.noSmoke = 2 end
	end
	
	init(v)
	data.cantChangeStates = true
	
	if data.phaseSpawnDie[data.state + 1] then
		for _,n in ipairs(NPC.get()) do
			if n.data.NPCCreatorspawnedNPCID and n.data.NPCCreatorspawnedNPCID == v.idx then
				n:kill(9)
			end
		end
	end
	
	if data.jumpTimerPhase[data.state + 1] >= 0 then
		data.jumptimer = data.jumpTimerPhase[data.state + 1]
	end
	
	if data.spawnTimerPhase[data.state + 1] >= 0 then
		data.spawntimer = data.spawnTimerPhase[data.state + 1]
	end
	
	if data.meleeTimerPhase[data.state + 1] >= 0 then
		data.meleetimer = data.meleeTimerPhase[data.state + 1]
	end
	
	if data.stateTimedPhase[data.state + 1] >= 0 then
		data.stateTimer = data.stateTimedPhase[data.state + 1]
	end
	
	--Play a death sound when changing states
	if data.explode[data.state + 1] then
		Explosion.spawn(v.x + (v.width / 2), v.y + (v.height / 2), 3)
	end
		
	--Optionally jump
	if data.phaseJump[data.state + 1] then npcJump(v) end
	
	--Set up waypoint tracking
	if data.waypoint[data.state + 1] ~= "" then
		for _,n in ipairs(NPC.get()) do
			if n.data.waypoint == data.waypoint[data.state + 1] then
				data.activeWaypointID = vector.v2(n.x + 16, n.y + 16)
				data.waypointCountID = n
				
				--Set into the waypoint state, does a different one depending on if gravity is set or not
				if data.gravity[data.state + 1] and data.blockCollision[data.state + 1] then
					data.activeWaypoint = 1
				else
					data.activeWaypoint = 2
					data.lerp = 0
					data.currentX, data.currentY = v.x, v.y
					
				end
				
				--Force the NPC to teleport if the option is set				
				if data.waypointTeleport[data.state + 1] then
					data.activeWaypoint = 2
					data.teleport = true
					data.teleportTimer = 0
				end
			end
		end
	end
	
	--Set direction
	
	if data.phaseDirection[data.state + 1] == 4 then return end
	
	v.direction = (data.phaseDirection[data.state + 1] - 1)
	
	if data.phaseDirection[data.state + 1] == 1 then
		v.direction = RNG.randomSign()
	elseif data.phaseDirection[data.state + 1] == 3 then
		npcutils.faceNearestPlayer(v)
	end
	
end

local function exitWaypoint(v)
	local data = v.data
	--Set exact position of waypoint
	if data.waypointExactXY[data.state + 1] ~= vector.zero2 then
		data.waypointCountID.x = data.waypointExactXY[data.state + 1].x
		data.waypointCountID.y = data.waypointExactXY[data.state + 1].y
	end
	
	--Offset X and Y coords
	data.waypointCountID.x = data.waypointCountID.x + data.waypointXY[data.state + 1].x
	data.waypointCountID.y = data.waypointCountID.y + data.waypointXY[data.state + 1].y
	
	
	data.activeWaypointID = nil
	data.activeWaypoint = nil
end

function sampleNPC.onEventNPC(v, eventName)
	if not npcIDs[v.id] then return end
	local data = v.data
	if not data.state then return end
	if data.eventChangePhase[data.state + 1] == "" then return end
	if eventName == data.eventChangePhase[data.state + 1] then
		data.stateVariable = data.stateTimedState[data.state + 1]				
		changeStates(v)
	end
end

local function checkShouldFreeze()
    local forcedStateFreeze
    for _,p in ipairs(Player.get()) do
        if p.forcedState ~= 0 and p.forcedState ~= 7 and p.forcedState ~= 3 then
            forcedStateFreeze = true
        end
    end
    return forcedStateFreeze or Defines.levelFreeze
end

function sampleNPC.onTickEndNPC(v)
	if Defines.levelFreeze then return end
	
	local data = v.data
	local settings = v.data._settings
	
	if data.initialized then
		--Trails stuff
		if data.trailNPCs and data.trailSplit then
			for i = 1,#data.trailSplit do
				if data.trailNPCs[i] and data.trailNPCs[i].isValid and data.trailNPCs[i].forcedState == 0 and data.trailNPCs[i].heldIndex == 0 and not data.trailNPCs[i].data.justHit then
					
					--Stomp on them, dunno why but this is the only way I could get it to work
					for _,p in ipairs(Player.get()) do
						if Colliders.collide(p, data.trailNPCs[i]) and not data.trailNPCs[i].isHidden and not data.trailNPCs[i].friendly and p.deathTimer <= 0 and p.forcedState == 0 and not NPC.config[data.trailNPCs[i].id].playerblocktop and NPC.HITTABLE_MAP[data.trailNPCs[i].id] and not NPC.config[data.trailNPCs[i].id].jumphurt and not p.isSpinJumping then
							if p.speedY > 0 then
								Colliders.bounceResponse(p, Defines.jumpheight_bounce)
								data.trailNPCs[i]:harm(HARM_TYPE_JUMP)
								data.trailNPCs[i].data.justHit = true
							end
						end
					end
					
					--Three different styles of trailing
					if data.trailNPCStyle[data.state + 1] == 2 then
						--Trail at any position
						data.trailNPCs[i].direction = v.direction
						data.trailNPCs[i].x = v.x - ((data.trailNPCs[i].width / 2) - v.width) - (v.width / 2) + data.trailXX[i]
						data.trailNPCs[i].y = v.y - ((data.trailNPCs[i].height - v.height) + 1) + data.trailYY[i]
					elseif data.trailNPCStyle[data.state + 1] == 1 then
						--Trail like a shield - that is, rotate around the NPC
						data.trailNPCs[i].direction = v.direction
									
						data.trailNPCs[i].data.npcCreatorAngle = (180 / #data.trailSplit) * i
						
						vectorAngle[i] = vector(0, -1):rotate(data.trailNPCs[i].data.npcCreatorAngle)
						
						local otherAng = vectorAngle[i]:rotate(i*180/#data.trailSplit)
						data.trailNPCs[i].data.NPCCreatorShieldX, data.trailNPCs[i].data.NPCCreatorShieldY = otherAng.x * (#data.trailSplit * 16), otherAng.y * (#data.trailSplit * 16)
						
						
						--Chunk of code written by Emral
						if data.trailNPCs[i].data.pivot == nil then
							data.trailNPCs[i].data.pivot = vector(v.x - ((data.trailNPCs[i].width / 2) - v.width) - (v.width / 2), v.y - ((data.trailNPCs[i].height - v.height) + 1))
							data.trailNPCs[i].data.radius = #data.trailSplit * 8 + data.trailXX[i] + 24
							data.trailNPCs[i].data.speed = data.trailNPCs[i].data._settings.speed or 3 + data.trailYY[i]
							data.trailNPCs[i].data.angle = data.trailNPCs[i].data.npcCreatorAngle + data.trailNPCs[i].data.npcCreatorAngle
							data.trailNPCs[i].data.direction = data.trailNPCs[i].direction
						end
						
						data.trailNPCs[i].data.pivot = vector(v.x - ((data.trailNPCs[i].width / 2) - v.width) - (v.width / 2), v.y - ((data.trailNPCs[i].height - v.height) + 1))

						if not Layer.isPaused() then
							data.trailNPCs[i].data.pivot.x = data.trailNPCs[i].data.pivot.x + data.trailNPCs[i].layerObj.speedX
							data.trailNPCs[i].data.pivot.y = data.trailNPCs[i].data.pivot.y + data.trailNPCs[i].layerObj.speedY
						end

						local v0 = vector(0, data.trailNPCs[i].data.radius):rotate(data.trailNPCs[i].data.angle)
						data.trailNPCs[i].x = data.trailNPCs[i].data.pivot.x + v0.x
						data.trailNPCs[i].y = data.trailNPCs[i].data.pivot.y + v0.y

						data.trailNPCs[i].data.angle = (data.trailNPCs[i].data.angle + data.trailNPCs[i].data.speed * data.trailNPCs[i].data.direction) % 360

						local v1 = data.trailNPCs[i].data.pivot + vector(0, data.trailNPCs[i].data.radius):rotate(data.trailNPCs[i].data.angle)
						data.trailNPCs[i].direction = -1
						data.trailNPCs[i].speedX = v1.x - data.trailNPCs[i].x
						data.trailNPCs[i].speedY = v1.y - data.trailNPCs[i].y
					else
						
						--Trail like a flame chomp
						data.tailHistory[1].x = v.x + 0.5 * v.width
						data.tailHistory[1].y = v.y + 0.5 * v.height
						data.npcRotation[1] = data.rotation
						data.npcDirection[1] = v.direction
						
						--Update Position History
						for i=data.maxHistoryCount-1,1,-1 do
							data.tailHistory[i+1].x = data.tailHistory[i].x
							data.tailHistory[i+1].y = data.tailHistory[i].y
							data.npcRotation[i+1] = data.npcRotation[i]
							data.npcDirection[i+1] = data.npcDirection[i]
						end
						
						--Update Tail Position
						if data.trailNPCs[i] and data.trailNPCs[i].isValid then
							data.trailNPCs[i].x = data.tailHistory[i*math.ceil(data.trailOffset / (data.horizontalMovementSpeed[data.state + 1] + 1))].x - 0.5 * data.trailNPCs[i].width
							data.trailNPCs[i].y = data.tailHistory[i*math.ceil(data.trailOffset / (data.horizontalMovementSpeed[data.state + 1] + 1))].y - 0.5 * data.trailNPCs[i].height
							data.trailNPCs[i].despawnTimer = v.despawnTimer
							data.trailNPCs[i].data.rotation = data.npcRotation[i*math.ceil(data.trailOffset / (data.horizontalMovementSpeed[data.state + 1] + 1))]
							data.trailNPCs[i].direction = data.npcDirection[i*math.ceil(data.trailOffset / (data.horizontalMovementSpeed[data.state + 1] + 1))]
						end
					end
				else
					if data.trailNPCs[i] and data.trailNPCs[i].isValid then
						data.trailNPCs[i].collisionGroup = ""
					end
					--Stuff to make the trailing NPCs go down in size
					if data.trailNPCStyle[data.state + 1] == 2 then
						for b = i,#data.trailSplit do
							table.remove(data.trailNPCs,i)
						end
					else
						table.remove(data.trailNPCs,i)
					end
				end
				
				if data.noSmoke and data.noSmoke >= 0 then				
					if data.noSmoke <= #data.trailSplit + 1 then
						local e = Effect.spawn(10, v.x, v.y)
						e.x = data.trailNPCs[i].x - ((data.trailNPCs[i].width / 2) - data.trailNPCs[i].width) - (data.trailNPCs[i].width / 2)
						e.y = data.trailNPCs[i].y - ((data.trailNPCs[i].height - data.trailNPCs[i].height) + 1)
						data.noSmoke = data.noSmoke + 1
					end
				else
					data.noSmoke = -1
				end
			end
		end
	end
end

function sampleNPC.onTickNPC(v)
	--Don't act during time freeze
	if Defines.levelFreeze then return end
	
	local data = v.data
	local plr = Player.getNearest(v.x + v.width/2, v.y + v.height)
	local settings = v.data._settings
	if lunatime.tick() <= 1 then return end

	--Optionally always stay spawned
	if not settings.despawn and v.section == plr.section then v.despawnTimer = 180 end
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		data.initialized = false
		if data.resetHorizontalMovementSpeed then data.horizontalMovementSpeed[data.state + 1] = 0 data.resetHorizontalMovementSpeed = nil end
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
		v.x = v.spawnX
		v.y = v.spawnY
		v.speedX = 0
		data.state = STATE_1
		initSettings(v)
		init(v)
		
		--Set width and height
		v.width, v.height = settings.width, settings.height - 1
		v.x, v.y = v.x - ((settings.width / 2) - 32) - 16, v.y - (settings.height - 32) + 1
		
		--Convert the flagBox referring to harm types into individual variables
		data.harmType = {HARM_TYPE_JUMP, HARM_TYPE_FROMBELOW, HARM_TYPE_NPC, HARM_TYPE_PROJECTILE_USED, HARM_TYPE_HELD, HARM_TYPE_LAVA, HARM_TYPE_TAIL, HARM_TYPE_SPINJUMP, HARM_TYPE_OFFSCREEN, HARM_TYPE_SWORD}
		data.harmType2 = {}
		data.newHarmType = toBinary(settings.harmTypes)
		tostring(data.newHarmType)
		for i = 1,#data.newHarmType do
			table.insert(data.harmType2, tonumber(data.newHarmType:sub(-i, -i)))
		end
		
		--Optionally emit light
		if settings.light then lightSettings(v) Darkness.addLight(data.npcCreatorlight) end
		
		--Default starting state is always STATE_1, and HP is always max
		data.hp = data.maxHP[data.state + 1]
		data.currentMaxHP = data.maxHP[data.state + 1]
		data.damageFire = data.hpdamagefire[data.state + 1]
		data.normalDamage = data.hpdamage[data.state + 1]
		if data.hp == 0 then data.hp = 1 end
		
		data.shieldCollider = Colliders.Box(v.x, v.y, v.width + 16, v.height + 16)
		
		v.data._basegame.lineguide.lineSpeed = data.horizontalMovementSpeed[data.state + 1]
		
		--Initialize the HP bar if set
		if settings.hpbar then
			drawHPBar(v)
			data.barTimer = 0
			data.hpBarTimer = 0
			data.barcolor = Color.green
		end
		
		--A single line that controls whether or not it should be on lineguides
		if data.lineGuide[data.state + 1] then else v.data._basegame.lineguide.attachCooldown = 2 v.data._basegame.lineguide.state = nil end
		
		data.noSmoke = 2
		
		if settings.initialPhase ~= "" then
			local initialPhase = Routine.run(function()
			Routine.waitFrames(1)
			data.noSmoke = nil
			data.stateVariable = settings.initialPhase			
			changeStates(v) end)
		end
	end
	
	data.shieldCollider.x = v.x - 8
	data.shieldCollider.y = v.y - 8
	
	--Display default animations
	
	if data.altAnimationTimer[data.state + 1] then data.animationController = data.stateTimer else data.animationController = lunatime.tick() end
	
	--Die when thrown
	if v.isProjectile and data.dieHeld[data.state + 1] then
		data.bounceAnimation = 2
		data.effectLifetime = 500
		data.horizontalMovementSpeed[data.state + 1] = 4 * v.direction
		data.ySpeedDeathEffect = v.speedY
		v.isProjectile = false
	end
	
	data.animationFrame = math.floor(data.animationController / settings.framespeed) % settings.frames + (((v.direction + 1) * settings.frames / 2)* settings.framestyle)
	
	--Walk frames
	if data.framesWalk[data.state + 1] > 0 then
		data.animationFrame = math.floor(data.animationController / data.framespeedWalk[data.state + 1]) % data.framesWalk[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetWalk[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetWalkRight[data.state + 1]) / 2)))
	end	
	
	if data.horizontalMovementSpeed[data.state + 1] == 0 or v.dontMove then v.speedX = 0 end
	
	--Idle frames
	if v.speedX == 0 and data.framesIdle[data.state + 1] > 0 then
		data.animationFrame = math.floor(data.animationController / data.framespeedIdle[data.state + 1]) % data.framesIdle[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetIdle[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetIdleRight[data.state + 1]) / 2)))
	end
	
	--Jump + Fall frames
	if v.speedY < 0 and data.framesJump[data.state + 1] > 0 then
		data.animationFrame = math.floor(data.animationController / data.framespeedJump[data.state + 1]) % data.framesJump[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetJump[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetJumpRight[data.state + 1]) / 2)))
	elseif (v.speedY > 0 or (data.activeWaypoint and data.activeWaypoint > 1)) and data.framesFall[data.state + 1] > 0 then
		data.animationFrame = math.floor(data.animationController / data.framespeedFall[data.state + 1]) % data.framesFall[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetFall[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetFallRight[data.state + 1]) / 2)))
	end
	
	--Attacking frames
	if data.framesShoot[data.state + 1] > 0 and data.spawnTimer[data.state + 1] >= 0 and data.spawnedNPC[data.state + 1] ~= 0 and data.spawntimer >= data.spawnTimer[data.state + 1] - 20 then
		data.animationFrame = math.floor(data.animationController / data.framespeedShoot[data.state + 1]) % data.framesShoot[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetShoot[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetShootRight[data.state + 1]) / 2)))
	end
	
	if data.framesMelee[data.state + 1] > 0 and data.meleeTimer[data.state + 1] >= 0 and data.meleetimer >= data.meleeTimer[data.state + 1] - 20 then
		data.animationFrame = math.floor(data.animationController / data.framespeedMelee[data.state + 1]) % data.framesMelee[data.state + 1] + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.frameoffsetMelee[data.state + 1] + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.frameoffsetMeleeRight[data.state + 1]) / 2)))
	end
	
	--Optionally emit light
	if settings.light then lightSettings(v) end
	
	--Interaction with iceballs
	if settings.noiceball then
		for _,n in NPC.iterate(265) do
			if Colliders.collide(n, data.shieldCollider) then
				n:kill()
				SFX.play(3)
			end
		end
	end
	
	if checkShouldFreeze() then return end
	
	--Transform when touching an NPC
	if data.collideNPCState[data.state + 1] and data.activeWaypoint ~= 2 then
		for _,n in NPC.iterate() do
			if n:mem(0x138, FIELD_WORD) == 0 and (not n.isHidden) and (not n.friendly) and n:mem(0x12C, FIELD_WORD) == 0 and n.idx ~= v.idx and Colliders.collide(n, data.shieldCollider) then
				if data.NPCCollision[1] ~= nil then
					for _,b in ipairs(data.NPCCollision) do
						if n.id == b then
							--Change states
							data.stateVariable = data.collideNPCState[data.state + 1]				
							changeStates(v)
						end
					end
				else
					--Change states
					data.stateVariable = data.collideNPCState[data.state + 1]				
					changeStates(v)
				end
			end
		end
	end

	--Interaction with Yoshi
	if settings.noyoshi then
		for _,n in ipairs(Player.get()) do
			if (yiYoshi ~= nil and yiYoshi.playerData.tongueTipCollider:collide(data.shieldCollider) and yiYoshi.playerData.tongueState ~= 0) or Colliders.tongue(n, data.shieldCollider) then
				if data.gravity[data.state + 1] then v.y = v.y - 1 end
				NPC.config[v.id].noyoshi = true
				if n:mem(0xB8,FIELD_WORD) ~= 0 then v.x, v.y = data.tongueX, data.tongueY end
				n:mem(0xB8,FIELD_WORD,0)
				if yiYoshi ~= nil then
					yiYoshi.playerData.tongueState = 3
					yiYoshi.playerData.tongueNPC = nil
					SFX.play("yiYoshi/tongue_failed.ogg")
				end
			else
				NPC.config[v.id].noyoshi = false
				data.tongueX, data.tongueY = v.x, v.y
			end
		end
	end
	
	--Can be set to grab
	if Colliders.collide(plr, v) and plr.deathTimer <= 0 and v.heldIndex == 0 and (not data.bounceAnimation or data.bounceAnimation < 2) and data.activeWaypoint ~= 2 then
		if data.flippedHeld[data.state + 1] and (plr.keys.run == KEYS_DOWN or plr.keys.altRun == KEYS_DOWN) and data.noHurt <= 0 then
			if data.harmless[data.state + 1] then data.tempNoHarm = true end
			v.heldIndex = plr.idx
			plr:mem(0x154, FIELD_WORD, v.idx+1)
			SFX.play(23)
			data.tempNoHarm = nil
		end
	end
	
	--Optionally harmful to the touch
	if data.harmless[data.state + 1] or data.collidePlayerState[data.state + 1] then
		for _,p in ipairs(Player.get()) do
			if Colliders.collide(p,v) and p.deathTimer <= 0 then

				if data.collidePlayerState[data.state + 1] then
					--Change states
					data.stateVariable = data.collidePlayerState[data.state + 1]				
					changeStates(v)
				end
				
				if data.harmless[data.state + 1] then
					if not v.friendly and not v.isHidden and v:mem(0x12C, FIELD_WORD) == 0 and v:mem(0x12E, FIELD_WORD) <= 20 and p.deathTimer <= 0 and not data.playerFriendly and not data.playerFriendly2 and not p:isInvincible() then
						if data.killThing[data.state + 1] then p:kill() end
						p:harm()
					end
				end
			end
		end
	end
	
	--This small block of code ensures that the player can be harmed by the NPC, unless they're jumping on it. That bit gets set in onNPCHarm
	--The routine just waits 4 frames before setting the NPC back to being dangerous, so it can account for any situations where the player might be inside the NPC for a frame or two
	if data.playerFriendly or data.playerFriendly2 then
		Routine.run(function()
			Routine.waitFrames(4)
			data.playerFriendly = nil
			data.playerFriendly2 = nil
		end)
	end
	
	--Stuff relating to v.friendly
	if data.friendly[data.state + 1] then
		v.friendly = true
	else
		if data.activeWaypoint == 2 then
			v.friendly = true
		else
			v.friendly = false
		end
	end
	
	--Stuff relating to v.dontMove
	if data.dontMove[data.state + 1] then
		v.dontMove = true
	else
		v.dontMove = false
	end

	if v.width < 0 and v.height < 0 then
		v.friendly = true
	end

	--Give it some i-frames when it gets hurt
	data.noHurt = data.noHurt - 1
	if data.noHurt > 0 then
		v.friendly = true
	end
	
	
	if v.heldIndex ~= 0 --Negative when held by NPCs, positive when held by players
	or v.isProjectile   --Thrown
	or v.forcedState > 0--Various forced states
	then
		data.jumptimer = 0
		data.spawntimer = 0
		data.meleetimer = 0
		if not data.flippedHeld[data.state + 1] then data.stateTimer = 0 end
		v.speedY = v.speedY + Defines.npc_grav
	else
		if not data.activeWaypoint then
			--Slow down in water - this block controls all movement
			if not data.water[data.state + 1] then
				data.speedDeduction = 1
			else
				if v.underwater then
					data.speedDeduction = 0.5
				else
					data.speedDeduction = 1
				end
			end
			
			--Gravity + Movement speed code
			if data.gravity[data.state + 1] then
				v.speedY = v.speedY + Defines.npc_grav * data.speedDeduction
				
				--Optionally stun the player
				if data.stun[data.state + 1] then
					data.stunTimer = data.stunTimer or 0
					if v.collidesBlockBottom then
						data.stunTimer = 0
						if not data.stunned then
							data.stunned = true
							SFX.play(37)
							Defines.earthquake = 2
							
							for i=0, 1 do
								local iOff = i/(1) - 0.5
								local dir = math.sign(iOff)
								local e = Effect.spawn(10, v.x, v.y)
								e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + settings.gfxoffsetx
								e.y = v.y + v.height - 16
								e.speedX = 2 * dir
							end
							
							for k, p in ipairs(Player.get()) do
								if p:isGroundTouching() and not playerStun.isStunned(k) and v:mem(0x146, FIELD_WORD) == player.section then
									playerStun.stunPlayer(k, 64)
								end
							end
						end
					else
						data.stunTimer = data.stunTimer + 1
						if data.stunTimer >= 3 then
							data.stunned = false
						end
					end
				end
				
				if data.jumpTimer[data.state + 1] >= 0 then
					if not data.paralysed and (not data.bounceAnimation or data.bounceAnimation < 2) and not data.activeWaypoint then
						data.jumptimer = data.jumptimer + 1
						if not v.collidesBlockBottom and (not data.jumpAir[data.state + 1] and not data.paragoombaJump[data.state + 1]) then
							data.jumptimer = 0
						end
					end
					if not data.paragoombaJump[data.state + 1] then
						--Jump normally
						if data.jumptimer >= data.jumpTimer[data.state + 1] then
							data.jumptimer = 0
							npcJump(v)
						end
					else
						--Jump like a paragoomba
						if data.jumptimer >= data.jumpTimer[data.state + 1] then
							if v.collidesBlockBottom then
								if data.JumpTableIndex < 3 then
									v.speedY = -4
									data.JumpTableIndex = data.JumpTableIndex + 1
								else
									data.JumpTableIndex = 0
									data.jumptimer = 0
									npcJump(v)
								end
							end
						end
					end
				end
			end
			
			--Jump when player jumps (optional)
			if data.playerJump[data.state + 1] then
				local jump = false
				for _,w in ipairs(Player.get()) do
					if w.forcedState == 0 and w.deathTimer == 0 and not w:mem(0x13C,FIELD_BOOL) and w:mem(0x11C,FIELD_WORD) > 0 then -- If this player is jumping
						jump = true
						break
					end
				end

				if jump then
					npcJump(v)
					data.jumptimer = 0
					data.JumpTableIndex = 0
				end
			end
			
			--Jump at walls and pits
			if (data.ledgeJump[data.state + 1] and not isNearPit(v)) or (data.wallJump[data.state + 1] and isNearWall(v)) then
				npcJump(v)
			end
			
			if not data.paralysed then data.walkTimer = data.walkTimer + 1 end

			
			--Horizontal + Vertical movemement code
			if not data.flipped[data.state + 1] then
				if data.generalMovement[data.state + 1] == 0 then
					if data.horizontalMovement[data.state + 1] == 0 then
						if not data.bounceAnimation or data.bounceAnimation <= 1 then v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * v.direction else data.npcharm[data.state + 1] = true end
					elseif data.horizontalMovement[data.state + 1] == 1 then
						--Walk like a shy guy
						if data.walkState == 0 then
							if data.walkTimer >= (data.miscSettingController.x or 75) or not data.wander then
								data.walkState = RNG.randomInt(0, 1)
								v.direction = RNG.randomInt(0,1) * 2 - 1
								data.walkTimer = 0
								data.wander = true
							end
							v.speedX = 0
						else
							v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * v.direction
							if data.walkTimer >= 45 then
								data.walkState = RNG.randomInt(0, 1)
								data.walkTimer = 0
							end
						end
					elseif data.horizontalMovement[data.state + 1] == 2 then
						--Chase like a monty mole
						v.speedX = math.clamp(v.speedX + (data.miscSettingController.x or 0.25) * v.direction, -data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction, data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction)
						npcutils.faceNearestPlayer(v)
					elseif data.horizontalMovement[data.state + 1] == 3 then
						--Chase like other SMW enemies
						v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * v.direction
						if data.walkTimer % (data.miscSettingController.x or 96) == 0 then
							npcutils.faceNearestPlayer(v)
						end
					elseif data.horizontalMovement[data.state + 1] == 4 then
						--Flee from the player
						v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * -math.sign(plr.x - (v.x - (settings.width / 2) + settings.width))
						v.direction = -math.sign(plr.x - (v.x - (settings.width / 2) + settings.width))
					elseif data.horizontalMovement[data.state + 1] == 5 then
						--Hammer bro movement
						npcutils.faceNearestPlayer(v)
						v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * data.walkDirection
						npcutils.faceNearestPlayer(v)
						if data.walkTimer == (data.miscSettingController.x or 25) then
							data.walkTimer = -(data.miscSettingController.x or 25)
							data.walkDirection = data.walkDirection * -1
						end
					end
					
					if not data.gravity[data.state + 1] then
						if data.verticalMovement[data.state + 1] == 0 then
							v.speedY = data.verticalMovementSpeed[data.state + 1] * data.speedDeduction
						elseif data.verticalMovement[data.state + 1] == 1 then
							--Chase like a monty mole
							v.speedY = math.clamp(v.speedY + (data.miscSettingController.y or 0.25) * math.sign(plr.y - (v.y - (settings.width / 2) + settings.width)), -data.verticalMovementSpeed[data.state + 1] * data.speedDeduction, data.verticalMovementSpeed[data.state + 1] * data.speedDeduction)
						elseif data.verticalMovement[data.state + 1] == 2 then
							--Chase like other SMW enemies
							if data.walkTimer % (data.miscSettingController.y or 96) == 0 or not data.verticalMoveSMWEnemy then
								v.speedY = (data.verticalMovementSpeed[data.state + 1] * data.speedDeduction) * math.sign(plr.y - (v.y - (settings.width / 2) + settings.width))
								data.verticalMoveSMWEnemy = true
							end
						elseif data.verticalMovement[data.state + 1] == 3 then
							--Flee from the player
							v.speedY = (data.verticalMovementSpeed[data.state + 1] * data.speedDeduction) * -math.sign(plr.y - (v.y - (settings.width / 2) + settings.width))
						end
					end
				else
					if data.generalMovement[data.state + 1] == 1 then
						--Override other movement types
						--Chase AI
						local cx = v.x + 0.5 * v.width
						local cy = v.y + 0.5 * v.height
						local p = Player.getNearest(cx, cy)
						local d = -vector(cx - p.x + p.width, cy - p.y):normalize() * 0.1
						local speed = NPC.config[v.id].speed
						v.speedX = v.speedX + d.x * NPC.config[v.id].speed
						v.speedY = v.speedY + d.y * NPC.config[v.id].speed
						if v.collidesBlockUp then
							v.speedY = math.abs(v.speedY) + 3
						end
						v.speedX = math.clamp(v.speedX, -data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction, data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction)
						v.speedY = math.clamp(v.speedY, -data.verticalMovementSpeed[data.state + 1] * data.speedDeduction, data.verticalMovementSpeed[data.state + 1] * data.speedDeduction)
						npcutils.faceNearestPlayer(v)
					elseif data.generalMovement[data.state + 1] == 2 then
						--Chase like a boo
						npcutils.faceNearestPlayer(v)
						if v.x + v.width/2 < plr.x + plr.width/2 then
							if v.speedX < data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction then
								v.speedX = v.speedX + (0.025 * data.speedDeduction)
							end
						else
							if v.speedX > -data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction then
								v.speedX = v.speedX - (0.025 * data.speedDeduction)
							end
						end

						if v.y + v.height/2 < plr.y + plr.height/2 then
							if v.speedY < data.verticalMovementSpeed[data.state + 1] * data.speedDeduction then
								v.speedY = v.speedY + (0.025 * data.speedDeduction)
							end
						elseif v.speedY > -data.verticalMovementSpeed[data.state + 1] * data.speedDeduction then
							v.speedY = v.speedY - (0.025 * data.speedDeduction)
						end
					elseif data.generalMovement[data.state + 1] == 3 then
						-- Accelerate on slopes
						local steepness = getSlopeSteepness(v)
						v.speedX = math.clamp(v.speedX + steepness*(0.05 * data.speedDeduction),-data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction,data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction)
					elseif data.generalMovement[data.state + 1] == 4 then
						--Homing X position
					
						local distX = (plr.x + 0.5 * plr.width) - (v.x + 0.5 * v.width)
						
						if math.abs(distX)> 1 then
							v.speedX = math.clamp(v.speedX + (0.0648 * data.speedDeduction)*math.sign(distX),-data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction,data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction)
						end
						
						--Homing Y position
					
						local distY = (plr.y + 0.5 * plr.height) - (v.y + 0.5 * v.height)
						
						if math.abs(distY)> 1 then
							v.speedY = math.clamp(v.speedY + (0.0648 * data.speedDeduction)*math.sign(distY),-data.verticalMovementSpeed[data.state + 1] * data.speedDeduction,data.verticalMovementSpeed[data.state + 1] * data.speedDeduction)
						end
					elseif data.generalMovement[data.state + 1] == 5 then
						--Phanto code
						local targetCenter
						local center = vector.v2(v.x+0.5*v.width, v.y+0.5*v.height)
						if plr ~= nil  then
							local targetP = plr
							targetCenter = vector.v2(targetP.x+0.5*targetP.width, targetP.y+targetP.height-32)
							data.exitSide = -math.sign(targetCenter.y-center.y)
							if  data.exitSide == 0  then
								data.exitSide = 1
							end

						else
							targetCenter = vector.v2(camera.x+camera.width*0.5, camera.y + 0.5*camera.width + camera.width*data.exitSide)
						end
					
						local toTarget = vector.v2(targetCenter.x-center.x, targetCenter.y-center.y)
						local verticalMovement = 0.15 * data.speedDeduction
						v.speedY = v.speedY + verticalMovement*math.sign(toTarget.y)
						v.speedY = math.clamp(v.speedY, -data.verticalMovementSpeed[data.state + 1] * data.speedDeduction,data.verticalMovementSpeed[data.state + 1] * data.speedDeduction)
					
						-- Horizontal movement
						local chaseAcceleration = 0.15 * data.speedDeduction
						local direction = 1
						local targetP = plr
						if v.x + v.width/2 < targetP.x+0.5*targetP.width then
							direction = 1
						else
							direction = -1
						end
						
						if v.ai5 % 240 < 120 then
							if math.abs(targetP.x+0.5*targetP.width - (v.x + v.width/2)) < 256 then
								chaseAcceleration = chaseAcceleration * -direction
							else
								chaseAcceleration = chaseAcceleration * direction
							end
						else
							chaseAcceleration = chaseAcceleration * direction
						end
						
						v.speedX = v.speedX + verticalMovement*math.sign(toTarget.x)
						v.speedX = math.clamp(v.speedX + chaseAcceleration, -data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction, data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction)
						center = vector.v2(v.x+0.5*v.width, v.y+0.5*v.height)
						
					else
						--Zelda 2 Bot
						
						if data.horizontalMovementSpeed[data.state + 1] ~= 0 then
							v.speedX = data.horizontalMovementSpeed[data.state + 1] * v.direction
						end
						
						local jumpTimer
						if data.generalTimerX[data.state + 1] == -1 then
							jumpTimer = {96, 80, 80}
						else
							jumpTimer = {data.generalTimerX[data.state + 1] + 16, data.generalTimerX[data.state + 1], data.generalTimerX[data.state + 1]}
						end
						
						local ySpeed = {data.verticalMovementSpeed[data.state + 1],data.verticalMovementSpeed[data.state + 1],math.ceil(data.verticalMovementSpeed[data.state + 1] * 1.5)}
						data.currentBotState = data.currentBotState or 1
						
						--data.currentState is the timer which controls when it should do a certain jump and how high it should jump
						--When it reaches the end of the defines table in the NPC config settings, return to the start
						if data.currentBotState > 3 then
							data.currentBotState = 1
						end
						
						--Stop moving when it touches the ground, and keep our timer to 0 so it doesnt mess up its jump timing
						if v.collidesBlockBottom then
							if data.resetHorizontalMovementSpeed then data.horizontalMovementSpeed[data.state + 1] = 0 data.resetHorizontalMovementSpeed = nil end
							--Actually jump and move data.currentBotState up by one
							if data.walkTimer >= jumpTimer[data.currentBotState] then
								data.walkTimer = 0
								npcutils.faceNearestPlayer(v)
								if data.horizontalMovementSpeed[data.state + 1] == 0 then data.resetHorizontalMovementSpeed = true data.horizontalMovementSpeed[data.state + 1] = 2 end
								v.speedX = (data.horizontalMovementSpeed[data.state + 1] * data.speedDeduction) * v.direction
								v.speedY = ySpeed[data.currentBotState] * data.speedDeduction
								data.currentBotState = data.currentBotState + 1
							end
						else
							data.walkTimer = 0
						end
					end
				end
			else
				--Flip like a galoomba!
				if not data.gravity[data.state + 1] then v.speedY = v.speedY + Defines.npc_grav * data.speedDeduction end
				if Colliders.collide(plr, v) and plr.deathTimer <= 0 and v.heldIndex == 0 then
				
					SFX.play(9)
					v.speedX = (-5 * data.speedDeduction) * math.sign(plr.x + plr.width/2 - v.x - v.width/2)
					v.speedY = -2
					data.stateTimer = 0
					v.isProjectile = true
				end
				
				if v.collidesBlockBottom then
					v.speedX = v.speedX * 0.5
					if math.abs(v.speedX) <= 0.1 then
						v.speedX = 0
						v.isProjectile = false
					end
				end
				
				--Indicate that the NPC is about to wake up
				if data.stateTimed[data.state + 1] > -1 and data.stateTimer >= data.stateTimed[data.state + 1] - 64 then
					if not data.x then v.x = v.x - 4 data.x = 1 else v.x = v.x + 4 data.x = nil end
				end
			end

			--Move on redirectors
			if data.redirector[data.state + 1] and data.bounceAnimation <= 1 then
				for _,bgo in ipairs(BGO.getIntersecting(v.x+(v.width/2)-0.5,v.y+(v.height/2),v.x+(v.width/2)+0.5,v.y+(v.height/2)+0.5)) do
					if redirector.VECTORS[bgo.id] then -- If this is a redirector and has a speed associated with it
						local redirectorSpeed = redirector.VECTORS[bgo.id] * data.horizontalMovementSpeed[data.state + 1] -- Get the redirector's speed and make it match the speed in the NPC's settings		
						-- Now, just put that speed from earlier onto the NPC
						if redirectorSpeed.x ~= 0 then v.direction = math.sign(redirectorSpeed.x) end
						data.horizontalMovementSpeed[data.state + 1] = redirectorSpeed.x * v.direction
						data.verticalMovementSpeed[data.state + 1] = redirectorSpeed.y
					elseif bgo.id == redirector.TERMINUS then -- If this BGO is one of the crosses
						-- Simply make the NPC stop moving
						v.speedX = 0
						v.speedY = 0
					end
				end
			end
			
			if not data.sinOrCos then
				data.sinOrCos = vector.v2(data.sincosHorizontal[data.state + 1], data.sincosVertical[data.state + 1])
				data.sinOrCos.x = data.sinOrCos.x + 1
				data.sinOrCos.y = data.sinOrCos.y + 1
			end
			
			if v.data._basegame.lineguide.state ~= 1 then
				if not data.paralysed then
					--Move in a sine motion
					if data.sineMovement[data.state + 1] then
						data.w = data.horizontalMovementSpeedSine[data.state + 1] * math.pi/65
						v.x = v.x + data.horizAmplitude[data.state + 1] * data.w * data.sinOrCosMath[data.sinOrCos.x](data.w*data.walkTimer)
					end
					
					--Move in a sine motion
					if data.sineMovementVertical[data.state + 1] then
						data.w = data.verticalMovementSpeedSine[data.state + 1] * math.pi/65
						v.y = v.y + data.vertiAmplitude[data.state + 1] * data.w * data.sinOrCosMath[data.sinOrCos.y](data.w*data.walkTimer)
					end
				end
			end
			
			--Make the NPC shake optionally
			if data.shake[data.state + 1] then
				if not data.x then v.x = v.x - 4 data.x = 1 else v.x = v.x + 4 data.x = nil end
			end
		elseif data.activeWaypoint == 2 then
			--Lerp to the waypoint
			v.speedX = 0
			v.speedY = 0
			
			if not data.teleport then
				data.lerp = data.lerp + 1
				v.x = easing.outQuad(data.lerp, data.currentX, data.activeWaypointID.x - data.currentX, 32)
				v.y = easing.outQuad(data.lerp, data.currentY, data.activeWaypointID.y - data.currentY, 32)
			
				--End waypoint behaviour
				if math.abs((v.x + v.width * 0.5) - data.activeWaypointID.x) <= v.width / 2 and math.abs((v.y + v.height * 0.5) - data.activeWaypointID.y) <= v.height / 2 then
					exitWaypoint(v)
				end
			else
				--Teleport to the waypoint
				data.teleportTimer = data.teleportTimer + 1
				if data.teleportTimer % 7 <= 4 then data.animationFrame = -50 end
				if data.teleportTimer == 32 then
					v.x = data.activeWaypointID.x
					v.y = data.activeWaypointID.y
				elseif data.teleportTimer == 64 then
					exitWaypoint(v)
					data.teleportTimer = 0
					data.teleport = nil
				end
			end
		elseif data.activeWaypoint == 1 then
			--Run to the waypoint
			v.speedY = v.speedY + Defines.npc_grav
			if (not isNearPit(v) and v.y > data.activeWaypointID.y) or isNearWall(v) then
				npcJump(v)
			end
			
			v.speedX = 2 * math.sign(data.activeWaypointID.x - (v.x - (settings.width / 2) + settings.width))
			
			--Stop going to the waypoint when near it
			if math.abs((v.x + v.width * 0.5) - data.activeWaypointID.x) <= 8 then
				exitWaypoint(v)
			end
		end
	end
	
	--Damage NPCs and blocks if the option is set to
	data.NPCHarm = NPC.getIntersecting(
	v.x - 4, 
	v.y - 4,
	v.x + (v.width + 4),
	v.y + (v.height + 4)
	)
	
	data.noTurn = (data.noTurn or 0) - 1
	
	for _, p in ipairs(data.NPCHarm) do
		if p.idx ~= v.idx then
			for _,e in ipairs(NPC.config[v.id].coolListOfThings) do
				if data.npcharm[data.state + 1] then
					if not p.friendly 
					and NPC.HITTABLE_MAP[p.id]
					and p:mem(0x12A, FIELD_WORD) > 0
					and p:mem(0x138, FIELD_WORD) == 0
					and not p.isHidden
					and p:mem(0x12C, FIELD_WORD) == 0
					then
						p:harm(HARM_TYPE_NPC)
						data.noTurn = 4
						
						if data.bounceAnimation and data.bounceAnimation > 1 then v:kill(HARM_TYPE_NPC) end
					end
				end
				
				if p.id == e then
					data.noTurn = 4
				end
				
				--Turn around on other kinds of NPCs
				if not data.gravity[data.state + 1] or NPC.config[p.id].iscoin or NPC.config[p.id].isvine or NPC.config[p.id].noblockcollision or p.isHidden or p.friendly or p.despawnTimer <= 0 or p.heldIndex ~= 0 or NPC.config[p.id].ignorethrownnpcs then
					data.noTurn = 4
				end
				
				if data.noTurn <= 0 and v.y >= p.y then
					v.direction = -math.sign(p.x - (v.x - (settings.width / 2) + settings.width))
				end
			end
		end
	end
	
	if data.blockharm[data.state + 1] then
		
		data.blockHarm = Block.getIntersecting(
		v.x - 4, 
		v.y - 4,
		v.x + (v.width + 4),
		v.y + (v.height + 4)
		)

		for _, p in ipairs(data.blockHarm) do
			for _,b in ipairs(NPC.config[v.id].destroyblocktable) do
				if not p.isHidden
				and p.isValid
				and not p.invisible
				and p.id == b
				then
					p:remove(true)
				end
			end
		end
		
	end
	
	--Spawn effects
	if data.generalEffect[data.state + 1] ~= "" then
		if data.stateTimer % data.generalEffectDelay[data.state + 1] == 0 then
			local effectOptionsGeneral = {}
			local effectSplitGeneral
			effectSplitGeneral = string.split(data.generalEffect[data.state + 1], ",")
			for i = 1,#effectSplitGeneral do
				table.insert(effectOptionsGeneral, tonumber(effectSplitGeneral[i]))
			end
			
			local e = Effect.spawn(RNG.irandomEntry(effectOptionsGeneral), v.x, v.y)
			e.direction = v.direction
			e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + v.data._settings.gfxoffsetx + (data.generalEffectX[data.state + 1] * e.direction) + RNG.random(0, data.generalEffectRandomX[data.state + 1])
			e.y = v.y - ((e.height - e.height) + 1) + v.data._settings.gfxoffsety + data.generalEffectY[data.state + 1] + RNG.random(0, data.generalEffectRandomY[data.state + 1])
			effectOptionsGeneral = nil
			effectSplitGeneral = nil
			effectOptionsGeneral = {}
			data.effectVariable = ""
		end
	end
	
	--Code to act like a vine
	if data.vine[data.state + 1] then
		for _,p in ipairs(Player.getIntersecting(v.x, v.y, v.x + v.width, v.y + v.height)) do
			if p.forcedState == FORCEDSTATE_NONE and p.mount == 0 then
				if p.keys.up or p.keys.down then
					data.vineActive = data.vineActive + 1
					p:mem(0x2C, FIELD_DFLOAT, v.idx + 1)
					if Defines.player_link_fairyVineEnabled and playerManager.getBaseID(p.character) == 5 then -- does the fairy stuff
						p:mem(0x0E, FIELD_WORD, 0)
						if not p:mem(0x0C, FIELD_BOOL) then
							p:mem(0x0C, FIELD_BOOL, true)
							SFX.play(87)
							p:mem(0x140, FIELD_WORD, 10)
							p.forcedState = FORCEDSTATE_INVISIBLE
							p.forcedTimer = 4
							Animation.spawn(63, p.x + p.width / 2 , p.y + p.height / 2 )
						end
					end
				elseif p.keys.jump == KEYS_PRESSED or p.ClimbingState == 0 then
					data.vineActive = 0
				end
				if Defines.player_link_fairyVineEnabled and playerManager.getBaseID(p.character) == 5 then 
					if p:mem(0x10, FIELD_WORD) ~= -1 and p:mem(0x10, FIELD_WORD) < 20 then p:mem(0x10, FIELD_WORD, 20) end -- keeps the fairy timer from running out
				end
			end
			if data.vineActive >= 1 then
				p.ClimbingState = 3
			end
		end
	end
	
	--AI used from MrDoubleA's Big Coins. Full credit goes to him.
	if data.coin[data.state + 1] then
		for _,p in ipairs(Player.getIntersecting(v.x, v.y, v.x + v.width, v.y + v.height)) do
		
			v:kill(9)
			
			if data.coinValue[data.state + 1] > 0 then
				addCoins(data.coinValue[data.state + 1])
				SFX.play(14)
				local e = Effect.spawn(78, v.x, v.y)
				e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + v.data._settings.gfxoffsetx
				e.y = v.y - (e.height - v.height) + v.data._settings.gfxoffsety
			end
		end
	end
	
	--NPC spawning code
	if data.spawnTimer[data.state + 1] >= 0 and data.spawnedNPC[data.state + 1] ~= 0 then
		if not data.paralysed and (not data.bounceAnimation or data.bounceAnimation < 2) and data.activeWaypoint ~= 2 then data.spawntimer = data.spawntimer + 1 end
		if data.spawntimer >= data.spawnTimer[data.state + 1] then
			data.spawntimer = 0
			spawnNPC(v)
		end
	end
	
	--Melee hitbox stuff
	if data.melee and data.activeWaypoint ~= 2 then
		data.meleetimer = data.meleetimer + 1
		if data.meleetimer >= data.meleeTimer[data.state + 1] then
			
			if data.meleetimer == data.meleeTimer[data.state + 1] then
				data.soundVariable = data.meleeSFX[data.state + 1]
				playSound(v)
			end
			
			--Set X and Y coords
			data.melee.x = (v.x - ((data.meleeWidth[data.state + 1] / 2) - v.width) - (v.width / 2)) + (data.meleeX[data.state + 1] * v.direction)
			data.melee.y = v.y - (data.meleeHeight[data.state + 1] + 1) + data.meleeY[data.state + 1] + 32
			
			if data.meleeSpeed[data.state + 1] then v.speedX = 0 end
			if data.meleeDebug[data.state + 1] then data.melee:draw() end
			
			--Interaction with NPCs and blocks
			for _,n in NPC.iterate() do
				if data.meleeNPC[data.state + 1] then
					if Colliders.collide(n, data.melee)
					and not n.friendly 
					and NPC.HITTABLE_MAP[n.id]
					and n.idx ~= v.idx
					and n:mem(0x12A, FIELD_WORD) > 0
					and n:mem(0x138, FIELD_WORD) == 0
					and not n.isHidden
					and n:mem(0x12C, FIELD_WORD) == 0
					then
						n:harm(HARM_TYPE_NPC)
					end
				end
			end

			if data.meleeBlock[data.state + 1] then
				data.meleeBlockHarm = Block.getIntersecting(
				data.melee.x, 
				data.melee.y,
				data.melee.x + data.meleeWidth[data.state + 1],
				data.melee.y + data.meleeHeight[data.state + 1]
				)

				for _, p in ipairs(data.meleeBlockHarm) do
					for _,b in ipairs(NPC.config[v.id].destroyblocktable) do
						if not p.isHidden
						and p.isValid
						and not p.invisible
						and p.id == b
						then
							p:remove(true)
						end
					end
				end
			end
			
			--Interactions with players
			if Colliders.collide(plr,data.melee) and plr.deathTimer <= 0 then
			
				if data.meleePlayer[data.state + 1] then
					if not v.isHidden and v:mem(0x12C, FIELD_WORD) == 0 and v:mem(0x12E, FIELD_WORD) <= 20 and plr.deathTimer <= 0 and not data.playerFriendly and not data.playerFriendly2 and not plr:isInvincible() and not (plr:mem(0x50, FIELD_BOOL) and data.meleeSpin[data.state + 1]) then
						plr:harm()
					end
				end	
				
				data.stateVariable = data.meleePhase[data.state + 1]
				changeStates(v)
				
				--Spinjump code
				if data.meleeSpin[data.state + 1] and plr:mem(0x50, FIELD_BOOL) and plr.speedY > 0 then
					Colliders.bounceResponse(plr, Defines.jumpheight_bounce)
				end
			end
			
			--Duration of the hitbox
			if data.meleetimer >= data.meleeTimer[data.state + 1] + data.meleeTime[data.state + 1] then
				data.meleetimer = 0
			end
		end
	end
	
	--Code to paralyse the NPC
	if data.paralysed then
		v.speedX = 0
		v.speedY = 0
		if not data.x then v.x = v.x - 4 data.x = 1 else v.x = v.x + 4 data.x = nil end
		data.paralysed = data.paralysed - 1
		if data.paralysed == 0 then
			data.paralysed = nil
			v.speedX, v.speedY = data.keepSpeedX, data.keepSpeedY
			data.keepSpeedX, data.keepSpeedY = nil, nil
		end
	end
	
	--HP bar stuff, thanks to MrNameless for letting me use his code
	if settings.hpbar then
		data.meter.x = v.x + v.width * 0.5 + settings.gfxoffsetx
		data.meter.y = v.y + (v.height - 32) - (settings.gfxheight) + settings.gfxoffsety

		data.barTimer = (math.max(data.barTimer - 1,0))	
		data.hpBarTimer = data.hpBarTimer - 1
	end
	
	--Optional cliffturn code
	if data.cliffturn[data.state + 1] then
		if v.collidesBlockBottom then
			if #Block.getIntersecting(v.x - (v.width / 2) + v.width, v.y + v.height, v.x - (v.width / 2) + v.width + 5, v.y + v.height + 64) == 0 then
				v.direction = -v.direction
				v.x = v.x + 4 * v.direction
			end
		end
	end
	
	
	--Block collision
	if not data.blockCollision[data.state + 1] then
		v.noblockcollision = true
	else
		v.noblockcollision = false
	end
	
	if (not data.bounceAnimation or data.bounceAnimation < 2) and not (data.activeWaypoint and not data.waypointStateTimer[data.state + 1]) then data.stateTimer = data.stateTimer + 1 end
	
	if not data.activeWaypoint then
		if v.collidesBlockLeft or v.collidesBlockRight then
			if data.leftRight[data.state + 1] > 0 then
			data.collidingLeftRight = math.clamp((data.collidingLeftRight or 0) - 1, 0, 2)
			--Turn left and right
				data.collidingLeftRight = data.collidingLeftRight + 3
				if data.collidingLeftRight >= 2 then
					v.direction = -v.direction
				end
			end
			
			--Change states
			data.stateVariable = data.phaseChangeWall[data.state + 1]				
			changeStates(v)
		end
		
		if v.collidesBlockUp then
			data.stateVariable = data.up[data.state + 1]				
			changeStates(v)
		end

		if v.collidesBlockBottom then
			data.stateVariable = data.down[data.state + 1]				
			changeStates(v)
			data.onFloor = 0
		else
			data.onFloor = (data.onFloor or 0) + 1
			if data.onFloor >= 2 then
				data.stateVariable = data.air[data.state + 1]				
				changeStates(v)
			end
		end

		--When stood on by a player
		if (plr.standingNPC ~= nil and plr.standingNPC.idx == v.idx) then
			data.stateVariable = data.jump[data.state + 1]				
			changeStates(v)
		end
		
		--Transform when approached and left
		if data.approach[data.state + 1] and data.approach[data.state + 1] > 0 then
			if math.abs(plr.x - v.x)<= data.approach[data.state + 1] then
				data.stateVariable = data.approachState[data.state + 1]				
				changeStates(v)
			end	
		end
		
		if data.leaveNPC[data.state + 1] and data.leaveNPC[data.state + 1] > 0 then
			if math.abs(plr.x - v.x)<= data.leaveNPC[data.state + 1] then
			else
				data.stateVariable = data.leaveNPCState[data.state + 1]				
				changeStates(v)
			end	
		end
		
		--Transform when facing or not facing player, like a boo
		if not plr:mem(0x50,FIELD_BOOL) then
			if math.sign(plr.x + plr.width * 0.5 - (v.x + 0.5 * v.width)) ~= plr.direction then
				data.stateVariable = data.facingLeft[data.state + 1]				
				changeStates(v)
			else
				data.stateVariable = data.facingRight[data.state + 1]				
				changeStates(v)
			end
		end
		
		--Transform when in or out of water
		if v.underwater and data.inWaterState[data.state + 1] ~= "" then
			local r = Routine.run(function()
				Routine.waitFrames(8)
				data.stateVariable = data.inWaterState[data.state + 1]				
				changeStates(v)
			end)
		elseif not v.underwater and data.outWaterState[data.state + 1] ~= "" then
			local r = Routine.run(function()
				Routine.waitFrames(8)
				data.stateVariable = data.outWaterState[data.state + 1]			
				changeStates(v)
			end)
		end
			
		--Transform with timer
		if data.stateTimed[data.state + 1] > -1 and data.stateTimer >= data.stateTimed[data.state + 1] then
		
			if v.heldIndex ~= 0 and plr:mem(0x154, FIELD_WORD) == v.idx + 1 then
				v.heldIndex = 0
				plr.keys.run = KEYS_UP
				plr.keys.altRun = KEYS_UP
				plr:mem(0x154, FIELD_WORD, -1)
			end
			
			data.stateVariable = data.stateTimedState[data.state + 1]				
			changeStates(v)
		end
	end
	
	--Play a continuous sound
	if data.stateTimer % data.soundInterval[data.state + 1] == 2 and data.continuousSound[data.state + 1] ~= "" and data.harmType then
		data.soundVariable = data.continuousSound[data.state + 1]
		playSound(v)
	end

	if data.cantChangeStates then data.cantChangeStates = false end
	
	if data.bounceAnimation then
		if data.bounceAnimation <= 1 then
			if data.bounceAnimation == 1 then
				--Bounce from being springed on
				data.bounceAnimationGeneralTimer = (data.bounceAnimationGeneralTimer or 0) + 1
				if data.bounceAnimationGeneralTimer <= 8 then
					data.bounceAnimationTimer.x = data.bounceAnimationTimer.x + 3
					data.bounceAnimationTimer.y = data.bounceAnimationTimer.y - 3
				else
					data.bounceAnimationTimer.x = data.bounceAnimationTimer.x - 3
					data.bounceAnimationTimer.y = data.bounceAnimationTimer.y + 3
					if data.bounceAnimationGeneralTimer >= 20 then
						data.bounceAnimationTimer.x = data.bounceAnimationTimer.x + 6
						data.bounceAnimationTimer.y = data.bounceAnimationTimer.y - 6
						if data.bounceAnimationGeneralTimer >= 24 then
							data.bounceAnimation = 0
							data.bounceAnimationTimer = vector.zero2
						end
					end
				end
			else
				--This is what runs most of the time, when the NPC isnt entering these special states
				data.bounceAnimationGeneralTimer = 0
			end
		else
			--Forcefully set a few settings
			data.gravity[data.state + 1] = false
			data.friendly[data.state + 1] = true
			data.shake[data.state + 1] = false
			data.verticalMovementSpeedSine[data.state + 1] = 0
			data.horizontalMovementSpeedSine[data.state + 1] = 0
			data.blockCollision[data.state + 1] = false
			data.bounceAnimationGeneralTimer = (data.bounceAnimationGeneralTimer or 0) + 1
			data.generalMovement[data.state + 1] = 0
			data.horizontalMovement[data.state + 1] = 0
			data.verticalMovement[data.state + 1] = 0
			v.data._basegame.lineguide.state = nil
			data.flippedHeld[data.state + 1] = false
			v.despawnTimer = 180
			data.melee = nil
			data.activeWaypoint = nil
			data.rotationType[data.state + 1] = 0
			
			if v.heldIndex == plr.idx then plr:mem(0x154, FIELD_WORD, -1) end
			
			if data.bounceAnimationGeneralTimer >= data.effectLifetime then
				v:kill(9)
			end
			
			--Display a frame here
			
			data.ownEffectTimer = (data.ownEffectTimer or 0) + 1
			
			data.animationFrame = math.floor(data.ownEffectTimer / data.ownEffectFramespeed) % data.ownEffect + ((v.direction + 1) * (settings.frames / 2)* settings.framestyle) + data.ownEffectFrameOffset + ((math.abs(settings.framestyle - 1)) * ((v.direction + 1) * ((data.ownEffectFrameOffsetRight) / 2)))
			
			if data.bounceAnimation == 2 or data.bounceAnimation == 4 then
				--Fall offscreen and rotate
				data.ySpeedDeathEffect = data.ySpeedDeathEffect or -9
				data.ySpeedDeathEffect = math.clamp(data.ySpeedDeathEffect + Defines.npc_grav * 1.5, -9, 12)
				data.verticalMovementSpeed[data.state + 1] = data.ySpeedDeathEffect
				if data.bounceAnimation == 2 then data.rotationType[data.state + 1] = 1 else data.bounceAnimationTimer.y = -settings.gfxheight * 2 if data.moveByHeight then v.y = v.y - settings.gfxheight data.moveByHeight = false end end
				data.rotationSpeed[data.state + 1] = 10

			elseif data.bounceAnimation == 3 then
				--Squished sprite
				data.horizontalMovementSpeed[data.state + 1] = 0
				data.verticalMovementSpeed[data.state + 1] = 0
				data.bounceAnimationTimer.y = -settings.gfxheight * 0.375
			elseif data.bounceAnimation == 5 then
				--Drop straight down
				data.horizontalMovementSpeed[data.state + 1] = 0
				data.verticalMovementSpeed[data.state + 1] = v.speedY + Defines.npc_grav
				data.bounceAnimationTimer.y = -settings.gfxheight * 2 if data.moveByHeight then v.y = v.y - settings.gfxheight data.moveByHeight = false end
			elseif data.bounceAnimation == 6 then
				--Wiggle and fall like a wiggler
				data.bounceAnimationTimer.y = -settings.gfxheight * 2 if data.moveByHeight then v.y = v.y - settings.gfxheight data.moveByHeight = false end
				data.ySpeedDeathEffect = data.ySpeedDeathEffect or -9
				data.ySpeedDeathEffect = math.clamp(data.ySpeedDeathEffect + Defines.npc_grav, -9, 12)
				data.verticalMovementSpeed[data.state + 1] = data.ySpeedDeathEffect
				data.horizontalMovementSpeed[data.state + 1] = 0
				v.x = v.x + 5 * (6 * math.pi/65) * math.sin((6 * math.pi/65)*lunatime.tick())
			else
				data.horizontalMovementSpeed[data.state + 1] = 0
				data.verticalMovementSpeed[data.state + 1] = 0
			end
		end
	end
	
	--Rotation code
	if data.rotationType[data.state + 1] > 0 then
		if data.rotationType[data.state + 1] == 2 then
			data.rotation = (data.rotation + math.deg((v.speedX*data.rotationSpeed[data.state + 1])/((v.width+v.height))))
		else
			if data.rotationType[data.state + 1] == 3 and not v.collidesBlockBottom then data.rotation = 0 return end
			if (data.rotationType[data.state + 1] == 4 or data.rotationType[data.state + 1] == 5) and v.collidesBlockBottom then data.rotation = 0 return end
			
			if data.rotationType[data.state + 1] < 5 then
				data.rotation = (data.rotation + data.rotationSpeed[data.state + 1] * v.direction)
			else
				data.rotation = math.min(math.max((data.rotation or 0) + v.speedY * v.direction, -90 - (v.speedX * 4 * -v.direction)), 90 + (v.speedX * 4 * -v.direction))
			end
		end
	end
end

function sampleNPC.onNPCHarm(eventObj, v, reason, culprit)
	if not npcIDs[v.id] then return end
	if reason == HARM_TYPE_LAVA or reason == HARM_TYPE_OFFSCREEN then return end
	local data = v.data
	local settings = v.data._settings
	data.kill = nil
	
	if reason == HARM_TYPE_JUMP then
		Audio.sounds[2].muted = true
	end
	
	--Check that the NPC can die to any of the selected methods
	for i = 1, 10 do
		if data.harmType and reason == data.harmType[i] and data.harmType2[i] == 1 then
			data.kill = true
		end
	end
	
	data.jumpKill = nil
	
	--Specific interaction when being jumped on
	if data.harmType then
		if reason == data.harmType[1] and data.harmType2[1] == 1 and data.hurtfulStomp[data.state + 1] or (reason == data.harmType[8] and data.harmType2[8] == 1 and data.harmType2[1] == 0) then
			
			--Act like a spring
			if data.spring[data.state + 1] and (reason == HARM_TYPE_JUMP or reason == HARM_TYPE_SPINJUMP) then eventObj.cancelled = true data.playerFriendly2 = true SFX.play(24) culprit.speedY = -data.springForce[data.state + 1] data.bounceAnimation = 1 data.bounceAnimationTimer = vector.zero2 data.stateVariable = data.jump[data.state + 1]				
			changeStates(v) return end
			
			Colliders.bounceResponse(culprit, Defines.jumpheight_bounce)
			data.actuallyHit = true
			data.playerFriendly = true
			if data.paralyse[data.state + 1] and not data.paralysed then data.paralysed = 32 data.keepSpeedX = v.speedX data.keepSpeedY = v.speedY end
			
			data.stateVariable = data.jump[data.state + 1]				
			changeStates(v)
			
			--Bit of code taken from the basegame chucks
			if data.knockback[data.state + 1] > 0 then
				if culprit and ((culprit.x + 0.5 * culprit.width) < (v.x + v.width*0.5)) then
					culprit.speedX = -data.knockback[data.state + 1]
				else
					culprit.speedX = data.knockback[data.state + 1]
				end
			end
			
			if reason == data.harmType[8] and data.harmType2[8] == 1 and data.harmType2[1] == 0 then eventObj.cancelled = true SFX.play(2) return end
			
			data.jumpKill = true
		else
			
			--Act like a spring
			if data.spring[data.state + 1] and (reason == HARM_TYPE_JUMP or reason == HARM_TYPE_SPINJUMP) then eventObj.cancelled = true data.playerFriendly2 = true SFX.play(24) culprit.speedY = -data.springForce[data.state + 1] data.bounceAnimation = 1 data.bounceAnimationTimer = vector.zero2 data.stateVariable = data.jump[data.state + 1]				
			changeStates(v) return end
		
			--Harm player on jump, unless spinjumping
			if not data.hurtfulStomp[data.state + 1] and reason == data.harmType[8] and data.harmType2[8] == 1 then eventObj.cancelled = true data.playerFriendly2 = true Colliders.bounceResponse(culprit, Defines.jumpheight_bounce) SFX.play(2) return end
		end
	end
	
	if data.state then
		if data.paralyseAnything[data.state + 1] and not data.paralysed then data.paralysed = 32 data.keepSpeedX = v.speedX data.keepSpeedY = v.speedY end
		
		if reason == data.harmType[2] and data.harmType2[2] == 1 then
			data.stateVariable = data.below[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[3] and data.harmType2[3] == 1 then
			data.stateVariable = data.hitNPC[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[4] and data.harmType2[4] == 1 then
			data.stateVariable = data.hitProjectile[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[5] and data.harmType2[5] == 1 then
			data.stateVariable = data.held[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[6] and data.harmType2[6] == 1 then
			data.stateVariable = data.lava[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[7] and data.harmType2[7] == 1 then
			data.stateVariable = data.tail[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[9] and data.harmType2[9] == 1 then
			data.stateVariable = data.offscreen[data.state + 1]				
			changeStates(v)
		end
		
		if reason == data.harmType[10] and data.harmType2[10] == 1 then
			data.stateVariable = data.sword[data.state + 1]				
			changeStates(v)
		end
	end
	
	if reason == HARM_TYPE_JUMP then
		--If the flag is not set to be defeated by a jump
		if not data.jumpKill then
			eventObj.cancelled = true
		else
			Audio.sounds[2].muted = false
		end
	end
	
	--If not, then dont kill the NPC
	if not data.kill then
		eventObj.cancelled = true
		return
	else
		if (not data.hurtfulStomp[data.state + 1] or data.spring[data.state + 1]) and reason == HARM_TYPE_JUMP then
			eventObj.cancelled = true
			return
		end
	end
	
	--However, if the NPC is immune to fireballs, also cancel its death
	if settings.nofireball and (culprit and culprit.id == 13 and type(culprit) == "NPC") then
		eventObj.cancelled = true
		return
	end
	
	--Code down here only applies if hp is enabled, and cycles through until all phases have been completed
	
	--If its hp is greather than 1, do damage checks
	if data.currentMaxHP > 0 and data.noHurt <= 0 then
		if culprit and culprit.id == 13 and type(culprit) == "NPC" then
			data.hp = data.hp - data.damageFire
			
			data.soundVariable = data.hpdamagefireSFX[data.state + 1]
			playSound(v)
			
			if settings.hpbar then data.bar.value = (math.max(data.bar.value - (data.damageFire / data.currentMaxHP),0))
			data.barcolor = math.lerp(Color.red, Color.green, data.bar.value - (data.damageFire / data.currentMaxHP)) end
		else
			if reason ~= data.harmType[8] then
				data.hp = data.hp - data.normalDamage
				
				data.soundVariable = data.hpdamageSFX[data.state + 1]
				playSound(v)

				if settings.hpbar then data.bar.value = (math.max(data.bar.value - (data.normalDamage / data.currentMaxHP),0))
				data.barcolor = math.lerp(Color.red, Color.green, data.bar.value - (data.normalDamage / data.currentMaxHP)) end
			end
		end
		data.hpBarTimer = 64
	end
	
	--Another gate that prevents the NPC from dying if it still has hp left
	if data.hp > 0 then
		eventObj.cancelled = true

		if reason ~= data.harmType[8] then
			if reason == data.harmType[1] or reason == data.harmType[7] or reason == data.harmType[8] then
				SFX.play(2)
			else
				SFX.play(9)
			end
		end
		
		if (reason == data.harmType[1] and data.harmType2[1] == 1) or (reason == data.harmType[8] and data.harmType2[1] == 1) then
			if data.actuallyHit then
				data.noHurt = 24
				data.actuallyHit = nil
			end
		else
			data.noHurt = 24
		end
		
		if settings.hpitems then
			if culprit then
				if type(culprit) == "NPC" and (culprit.id ~= 195 and culprit.id ~= 50) and (NPC.HITTABLE_MAP[culprit.id] or culprit.id == 45) and v:mem(0x138, FIELD_WORD) == 0 then
					culprit:kill(HARM_TYPE_NPC)
				end
			end
		end
		
		return
	else
		if data.noHP[data.state + 1] ~= "" then
			eventObj.cancelled = true
			data.save = true
			data.stateVariable = data.noHP[data.state + 1]				
			changeStates(v)
		end
	end
	
	--Finally, after phase 3 or the designated number of phases, the NPC is defeated
	--[[if (settings.phase2 and data.state == 0 and settings.transform1 == 1) or (settings.phase3 and data.state == 1 and settings.transform2 == 1) or (settings.phase4 and data.state == 2 and settings.transform3 == 1) or (settings.phase5 and data.state == 3 and settings.transform4 == 1) then
		data.state = data.state + 1
		eventObj.cancelled = true
	end]]
end

local reasons = {HARM_TYPE_LAVA, HARM_TYPE_SPINJUMP, HARM_TYPE_OFFSCREEN, HARM_TYPE_SWORD}

function sampleNPC.onNPCKill(eventObj, v, reason)
	if not npcIDs[v.id] then return end
	local data = v.data
	local settings = v.data._settings

	for _,n in ipairs(NPC.get()) do
		if n.data.NPCCreatorspawnedNPCID and n.data.NPCCreatorspawnedNPCID == v.idx then
			n:kill(9)
		end
	end
	
	if data.trailNPCs then
	
		for i=#data.trailNPCs,1,-1 do
			if settings.ownEffect > 0 or settings.ownEffectSquish > 0 and data.trailNPCs[i].isValid and data.trailNPCs[i].heldIndex == 0 then
				if data.trailNPCStyle[data.state + 1] == 2 then
					data.trailNPCs[i].collisionGroup = ""
					table.remove(data.trailNPCs,i)
					data.trailNPCs[i] = nil
					break
				end
			end
		
			if data.trailNPCs[i].isValid and data.trailNPCs[i].heldIndex == 0 and data.trailNPCStyle[data.state + 1] ~= 2 then
				data.trailNPCs[i]:kill(HARM_TYPE_OFFSCREEN)
				data.trailNPCs[i] = nil
			end
		end
	end
	
	--Play a death sound when dying
	data.soundVariable = settings.deathSound
	playSound(v)
	
	if not data.harmType then return end
	
	if settings.light then Darkness.removeLight(data.npcCreatorlight) end

	if (reason == data.harmType[6] and data.harmType2[6] == 0) or (reason == data.harmType[9] and data.harmType2[9] == 0) then eventObj.cancelled = true end
	
	--Recreate the spinjump death effect
	if reason == HARM_TYPE_JUMP and math.abs(Player.getNearest(v.x + v.width/2, v.y + v.height).x - v.x) <= v.width and Player.getNearest(v.x + v.width/2, v.y + v.height).isSpinJumping then
	if not settings.mute then SFX.play(36) end
	local e = Effect.spawn(tonumber(10), v.x, v.y)
	e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + settings.gfxoffsetx + settings.gfxoffsetEffectx
	e.y = v.y - (e.height - v.height) + settings.gfxoffsety + settings.gfxoffsetEffecty
	local e = Effect.spawn(76, v.x, v.y)
	e.x = v.x - ((e.width / 2) - v.width) - (v.width / 2) + settings.gfxoffsetx + settings.gfxoffsetEffectx
	e.y = v.y - (e.height - v.height) + settings.gfxoffsety + settings.gfxoffsetEffecty
	return end
	
	
	if v.ai1 > 0 then
		local n = NPC.spawn(v.ai1, v.x + (v.width / 2), v.y + (v.height / 2), player.section, false)
		n.direction = v.direction
		n.x = v.x - ((n.width / 2) - v.width) - (v.width / 2)
		n.y = v.y - ((n.height - v.height) + 1)
	end
	
	--Display a death effect, unless one of the reasons listed in the table "reasons"
	for _,reasonTable in ipairs(reasons) do
		if reason == reasonTable then return end
	end
	
	--Simulate its own death effect
	
	if data.die[data.state + 1] then return end
	
	if settings.ownEffectSquish > 0 and reason == HARM_TYPE_JUMP then
		eventObj.cancelled = true
		SFX.play(2)
		data.bounceAnimation = settings.ownEffectSquish + 1
		data.effectLifetime = settings.ownEffectLifetime
		data.ownEffect = settings.ownEffectFrameSquish
		data.ownEffectFramespeed = settings.ownEffectFramespeedSquish
		data.ownEffectFrameOffset = settings.ownEffectFrameOffsetSquish
		data.ownEffectFrameOffsetRight = settings.ownEffectFrameOffsetRightSquish
		if settings.ownEffectSquish == 1 or settings.ownEffectSquish == 3 then data.horizontalMovementSpeed[data.state + 1] = RNG.random(-1.5,1.5) end
		data.moveByHeight = true
		return
	elseif settings.ownEffect > 0 and reason ~= HARM_TYPE_JUMP then
		eventObj.cancelled = true
		SFX.play(9)
		data.effectLifetime = settings.ownEffectLifetimeAny
		data.ownEffect = settings.ownEffectFrame
		data.ownEffectFramespeed = settings.ownEffectFramespeed
		data.ownEffectFrameOffset = settings.ownEffectFrameOffset
		data.ownEffectFrameOffsetRight = settings.ownEffectFrameOffsetRight
		data.bounceAnimation = settings.ownEffect + 1
		if settings.ownEffect == 1 or settings.ownEffectSquish == 3 then data.horizontalMovementSpeed[data.state + 1] = RNG.random(-1.5,1.5) end
		data.moveByHeight = true
		return
	end
	
	--Spawn a death effect
	data.effectOffset = vector.v2(settings.gfxoffsetEffectx, settings.gfxoffsetEffecty)
	data.effectSpeed = nil
	if reason == HARM_TYPE_JUMP then
		data.effectVariable = settings.deathStomp
		spawnEffect(v)
	elseif reason == HARM_TYPE_FROMBELOW then
		data.effectVariable = settings.deathBelow
		spawnEffect(v)
	elseif reason == HARM_TYPE_TAIL then
		data.effectVariable = settings.deathTail
		spawnEffect(v)
	else
		data.effectVariable = settings.deathOther
		spawnEffect(v)
	end
	
	
end

--[[************************
Rotation code by MrDoubleA
**************************]]

local function drawSprite(args) -- handy function to draw sprites
	args = args or {}

	args.sourceWidth  = args.sourceWidth  or args.width
	args.sourceHeight = args.sourceHeight or args.height

	if sprite == nil then
		sprite = Sprite.box{texture = args.texture}
	else
		sprite.texture = args.texture
	end

	sprite.x,sprite.y = args.x,args.y
	sprite.width,sprite.height = args.width,args.height

	sprite.pivot = args.pivot or Sprite.align.TOPLEFT
	sprite.rotation = args.rotation or 0

	if args.texture ~= nil then
		sprite.texpivot = args.texpivot or sprite.pivot or Sprite.align.TOPLEFT
		sprite.texscale = args.texscale or vector(args.texture.width*(args.width/args.sourceWidth),args.texture.height*(args.height/args.sourceHeight))
		sprite.texposition = args.texposition or vector(-args.sourceX*(args.width/args.sourceWidth)+((sprite.texpivot[1]*sprite.width)*((sprite.texture.width/args.sourceWidth)-1)),-args.sourceY*(args.height/args.sourceHeight)+((sprite.texpivot[2]*sprite.height)*((sprite.texture.height/args.sourceHeight)-1)))
	end

	sprite:draw{priority = args.priority,color = args.color,sceneCoords = args.sceneCoords or args.scene}
end

local filenames = {'.png', '.jpg', '.gif', '.tiff', '.pdf', '.bmp', '.webp', '.psd', '.raw'}

function sampleNPC.onDrawNPC(v)
	local config = NPC.config[v.id]
	local data = v.data
	local settings = v.data._settings

	if settings.hpbar then 
		if data.hpBarTimer and data.hpBarTimer > 0 then
			data.meter:draw{
				sceneCoords = true,
			}
			data.bar:draw{
				barcolor = data.barcolor,
				sceneCoords = true,
			}
		end
	end

	if settings.image == "" or v.despawnTimer <= 0 or v.isHidden then return end
	
	if not data.img then
		for _,files in ipairs(filenames) do
			data.tempImage = Misc.resolveGraphicsFile(settings.image .. files)
			if data.tempImage then data.img = Graphics.loadImage(data.tempImage) break end
		end
	end

	if data.noHurt and data.noHurt > 0 and settings.hpflash then if data.noHurt % 7 <= 4 then data.animationFrame = -50 return end end
	
	if not data.bounceAnimationTimer then data.bounceAnimationTimer = vector.zero2 end
	
	drawSprite{
		texture = data.img,

		x = v.x+(v.width/2)+settings.gfxoffsetx,y = v.y+v.height-(settings.gfxheight/2)+settings.gfxoffsety + 2 - (data.bounceAnimationTimer.y / 2),
		width = settings.gfxwidth + (data.bounceAnimationTimer.x),height = settings.gfxheight + (data.bounceAnimationTimer.y),

		sourceX = 0,sourceY = (data.animationFrame or 0)*settings.gfxheight,
		sourceWidth = settings.gfxwidth,sourceHeight = settings.gfxheight,

		priority = settings.priority,rotation = data.rotation,
		pivot = Sprite.align.CENTRE,sceneCoords = true,color = settings.color
	}

	npcutils.hideNPC(v)
end

return sampleNPC



--Debug stuff

--[[Text.print(data.harmType2[1],0,0)
Text.print(data.harmType2[2],0,16)
Text.print(data.harmType2[3],0,32)
Text.print(data.harmType2[4],0,48)
Text.print(data.harmType2[5],0,64)
Text.print(data.harmType2[6],0,80)
Text.print(data.harmType2[7],0,96)
Text.print(data.harmType2[8],0,112)
Text.print(data.harmType2[9],0,128)
Text.print(data.harmType2[10],0,144)]]