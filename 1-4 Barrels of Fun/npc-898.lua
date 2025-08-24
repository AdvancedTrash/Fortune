--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local npcutils = require("npcs/npcutils")
local klonoa = require("characters/klonoa")
klonoa.UngrabableNPCs[NPC_ID] = true
--Create the library table
local QueenB = {}
--NPC_ID is dynamic based on the name of the library file
local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local QueenBSettings = {
	id = npcID,

	-- ANIMATION
	--Sprite size
	gfxwidth = 120,
	gfxheight = 128,
	--Hitbox size. Bottom-center-bound to sprite size.
	width = 64,
	height = 66,
	--Sprite offset from hitbox for adjusting hitbox anchor on sprite.
	gfxoffsetx = 0,
	gfxoffsety = 16,
	--Frameloop-related
	frames = 22,
	framestyle = 1,
	framespeed = 6, -- number of ticks (in-game frames) between animation frame changes

	foreground = false, -- Set to true to cause built-in rendering to render the NPC to Priority -15 rather than -45

	-- LOGIC
	--Movement speed. Only affects speedX by default.
	speed = 1,
	luahandlesspeed = true, -- If set to true, the speed config can be manually re-implemented
	nowaterphysics = true,
	cliffturn = false, -- Makes the NPC turn on ledges
	staticdirection = true, -- If set to true, built-in logic no longer changes the NPC's direction, and the direction has to be changed manually

	--Collision-related
	npcblock = false, -- The NPC has a solid block for collision handling with other NPCs.
	npcblocktop = false, -- The NPC has a semisolid block for collision handling. Overrides npcblock's side and bottom solidity if both are set.
	playerblock = false, -- The NPC prevents players from passing through.
	playerblocktop = false, -- The player can walk on the NPC.

	nohurt=false, -- Disables the NPC dealing contact damage to the player
	nogravity = true,
	noblockcollision = true,
	notcointransformable = false, -- Prevents turning into coins when beating the level
	nofireball = false,
	noiceball = true,
	noyoshi= true, -- If false, Yoshi, Baby Yoshi and Chain Chomp can eat this NPC

	score = 9, -- Score granted when killed
	--  1 = 10,    2 = 100,    3 = 200,  4 = 400,  5 = 800,
	--  6 = 1000,  7 = 2000,   8 = 4000, 9 = 8000, 10 = 1up,
	-- 11 = 2up,  12 = 3up,  13+ = 5-up, 0 = 0

	--Various interactions
	jumphurt = true, --If true, spiny-like (prevents regular jump bounces)
	spinjumpsafe = false, --If true, prevents player hurt when spinjumping and causes a bounce
	harmlessgrab = false, --Held NPC hurts other NPCs if false
	harmlessthrown = false, --Thrown NPC hurts other NPCs if false
	nowalldeath = false, -- If true, the NPC will not die when released in a wall

	linkshieldable = false,
	noshieldfireeffect = false,

	grabside=false,
	grabtop=false,

	nogliding = true, -- The NPC ignores gliding blocks (1f0)

	terminalvelocity = 20, 

	--Define custom properties below
	-- Animation settings
	flyFrames = 4,
	flyFrameSpeed = 6,

	turnAroundFrames = 2,
	turnAroundFrameSpeed = 6,

	hurt1Frames = 3,
	hurt1FrameSpeed = 6,

	hurt2Frames = 2,
	hurt2FrameSpeed = 8,

	sfx_die = Misc.resolveFile("King Zing die.mp3"),
	sfx_shield = Misc.resolveFile("King Zing shield.mp3"),
	sfx_hit = Misc.resolveFile("King Zing hit.mp3"),
	sfx_spike_pop = Misc.resolveFile("King Zing spikes.mp3"),
	sfx_turn = Misc.resolveFile("Zinger_turn.wav"),
	sfx_battlecry = Misc.resolveFile("King Zing battle cry.mp3"),

	hornID = 900,
	zingerID = 901,
	zingerAggroID = 902,

	spikeDelay = 64,
	summonDelay = 720,
}

--Applies NPC settings
npcManager.setNpcSettings(QueenBSettings)

local orbits = require 'queenb_orbits'

--Register the vulnerable harm types for this NPC. The first table defines the harm types the NPC should be affected by, while the second maps an effect to each, if desired.
npcManager.registerHarmTypes(npcID,
	{
		--HARM_TYPE_JUMP,
		--HARM_TYPE_FROMBELOW,
		HARM_TYPE_NPC,
		HARM_TYPE_PROJECTILE_USED,
		--HARM_TYPE_LAVA,
		--HARM_TYPE_HELD,
		--HARM_TYPE_TAIL,
		--HARM_TYPE_SPINJUMP,
		--HARM_TYPE_OFFSCREEN,
		HARM_TYPE_SWORD
	}, 
	{
		--[HARM_TYPE_JUMP]=10,
		--[HARM_TYPE_FROMBELOW]=10,
		[HARM_TYPE_NPC]=npcID,
		--[HARM_TYPE_PROJECTILE_USED]=10,
		--[HARM_TYPE_LAVA]={id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
		--[HARM_TYPE_HELD]=10,
		--[HARM_TYPE_TAIL]=10,
		--[HARM_TYPE_SPINJUMP]=10,
		--[HARM_TYPE_OFFSCREEN]=10,
		--[HARM_TYPE_SWORD]=10,
	}
);

--Custom local definitions below
local STATE = {
	FLYING = 0,
	SUMMON = 1,
	SPIKE = 2,
	HURT = 3,
	KILL = 4,
}
local STATE_ANIM = {
	FLYING = 0,
	HURT1 = 1,
	HURT2 = 2,
}
local waves = {{5,8}, {1,4}}

local function handleFlyAround(v,data,config,settings)
	local verticalDirection
	local verticalDistance = settings.flyAroundVerticalDistance
	local aggro = false
	local speedIncrease = settings.flyAroundVerticalAccelerateIncrease * data.phase
	verticalDirection = data.verticalDirection
	if settings.flyingDirection == 0 then
		if (v.y <= v.spawnY - verticalDistance and data.verticalDirection == -1) or (v.y >= v.spawnY and data.verticalDirection == 1) then
			SFX.play(config.sfx_turn)
			data.verticalDirection = -data.verticalDirection
		end
	elseif settings.flyingDirection == 1 then
		if (v.y >= v.spawnY + verticalDistance and data.verticalDirection == 1) or (v.y <= v.spawnY and data.verticalDirection == -1) then
			SFX.play(config.sfx_turn)
			data.verticalDirection = -data.verticalDirection
		end
	end
	aggro = data.invincible
	if aggro == true then
		v.speedY = math.clamp(v.speedY + (settings.flyAroundVerticalAccelerateAggro + speedIncrease) * verticalDirection, -settings.flyAroundVerticalSpeedCapAggro, settings.flyAroundVerticalSpeedCapAggro)
	else
		v.speedY = math.clamp(v.speedY + (settings.flyAroundVerticalAccelerate + speedIncrease) * verticalDirection, -settings.flyAroundVerticalSpeedCap, settings.flyAroundVerticalSpeedCap)
	end



	data.flyAroundTimer = data.flyAroundTimer + 1

	npcutils.faceNearestPlayer(v)
end

local function handleAnimation(v,data,config,settings)
	-- Initialise the turning direction
	if data.oldDirection ~= v.direction and v:mem(0x12C,FIELD_WORD) == 0 and data.turnTimer % 90 == 0 then
		data.turnActive = true
		data.animationTimer = 0
		SFX.play(config.sfx_turn)
	end
	if data.turnActive then
		data.oldDirection = v.direction
	end

	-- Find the frame/direction to use
	local direction = data.oldDirection
	local frame = 0

	if data.turnActive then
		local turnDuration = config.turnAroundFrames * config.turnAroundFrameSpeed * 2

		frame = math.floor(data.animationTimer / config.turnAroundFrameSpeed)

		if frame >= config.turnAroundFrames then
			frame = config.turnAroundFrames - (frame - config.turnAroundFrames) - 1
		else
			direction = -direction
		end

		frame = frame + config.flyFrames

		data.turnActive = (data.animationTimer+1 < turnDuration)
	elseif data.stateAnimation == STATE_ANIM.FLYING then
		frame = math.floor(data.animationTimer / config.flyFrameSpeed) % config.flyFrames
	elseif data.stateAnimation == STATE_ANIM.HURT1 then
		frame = (math.floor(data.animationTimer / config.hurt1FrameSpeed) % config.hurt1Frames) + config.flyFrames + config.turnAroundFrames
	elseif data.stateAnimation == STATE_ANIM.HURT2 then

		frame = (math.floor(data.animationTimer / config.hurt2FrameSpeed) % config.hurt2Frames) + config.flyFrames + config.hurt1Frames + config.turnAroundFrames
	end

	if data.invincible == true or (data.state == STATE.KILL and data.timer % 8 > 4) then frame = frame + config.flyFrames + config.hurt1Frames + config.turnAroundFrames + config.hurt2Frames end

	v.animationFrame = npcutils.getFrameByFramestyle(v,{frame = frame,direction = direction})

	data.animationTimer = data.animationTimer + 1
end

--Register events
function QueenB.onInitAPI()
	npcManager.registerEvent(npcID, QueenB, "onTickEndNPC")
	npcManager.registerEvent(npcID, QueenB, "onDrawNPC")
	registerEvent(QueenB, "onNPCKill")
	registerEvent(QueenB, "onNPCHarm")
end

function QueenB.onTickEndNPC(v)
	--Don't act during time freeze
	if Defines.levelFreeze then return end
	
	local data = v.data
	local config = NPC.config[v.id]
	local settings = v.data._settings
	local plr = Player.getNearest(v.x + v.width/2, v.y + v.height)
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		data.initialized = false
		data.state = STATE_HOP
		data.timer = 0
		data.invincibleTimer = 64
		data.chaseTimer = 0
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
		data.state = STATE.FLYING
		data.timer = data.timer or 0
		data.health = (settings.health + settings.healthUnique) or 5

		data.invincibleTimer = data.invincibleTimer or 64
		data.chaseTimer = data.chaseTimer or 0
		data.isTurning = false
		data.turnTimer = 0
		data.invincible = false
		data.pinchTimer = 0
		data.spinyPhase = 0

		data.flyAroundTimer = 0

		data.animationTimer = 0

		data.turnActive = false
		data.oldDirection = v.direction

		data.hurtOpacity = 1

		data.stateAnimation = STATE_ANIM.FLYING

		data.verticalDirection = -1 + 2 * settings.flyingDirection
		if settings.phase ~= 3 then
			data.phase = settings.phase
		else
			data.phase = 0
		end
		--Events used for phases for accomodations
		if settings.phase == 3 then
			data.phase2ndEvent = false
			data.phase3rdEvent = false
		else
			data.phase2ndEvent = true
			data.phase3rdEvent = true
		end
		data.useUniqueAttacks = false --A variable which lets it use unique attacks. Setting the unique health settings can help make the phasing at start from not using attacks into using attacks.
		v.ai1 = RNG.randomInt(210,370) --flying delay for spike attack
		v.ai2 = 0 --flying timer for spike attack
		v.ai3 = 0 --consecutive
		v.ai4 = 0 --flying timer for summoning
		v.ai5 = RNG.randomInt(360,510) --flying delay for summoning
		data.attackStyle = 0
		data.movementStyle = 0
		data.beeServants = nil
		data.summonStyle = 0
	end

	--Depending on the NPC, these checks must be handled differently
	if v.heldIndex ~= 0 --Negative when held by NPCs, positive when held by players
	or v.isProjectile   --Thrown
	or v.forcedState > 0--Various forced states
	then
		data.timer = 0
		data.state = STATE.FLYING
	end
	--General timer used for most things
	data.timer = data.timer + 1
	data.invincibleTimer = data.invincibleTimer + 1
	data.turnTimer = data.turnTimer + 1
	local chase = settings.chaseSpeed
	if data.invincible == true then chase = settings.chaseSpeedAggro end
	data.dirVectr = vector.v2(
		(plr.x + plr.width/2) - (v.x + v.width * 0.5),
		(plr.y + plr.height/2) - (v.y + v.height * 0.5)
		):normalize() * (chase + settings.chaseSpeedIncrease * data.phase)
	if settings.phase == 3 then
		if data.useUniqueAttacks == false and data.health <= settings.health then
			data.useUniqueAttacks = true
		end
		if data.health <= settings.health * 2 / 3 and data.phase == 0 then
			data.phase = 1
			data.timer = 0
			data.state = STATE.HURT
			data.animationTimer = 0
			if (settings.second ~= "" and data.phase == 1 and data.phase2ndEvent == false) then
				triggerEvent(settings.second)
				data.phase2ndEvent = true
			end
		elseif data.health <= settings.health * 1 / 3 and data.phase == 1 then
			data.phase = 2
			data.timer = 0
			data.state = STATE.HURT
			data.animationTimer = 0
			if (settings.third ~= "" and data.phase == 2 and data.phase3rdEvent == false) then
				triggerEvent(settings.third)
				data.phase3rdEvent = true
			end
		end
	else
		if data.useUniqueAttacks == false and data.health <= settings.health then
			data.useUniqueAttacks = true
		end
	end
	local summonIntend
	if data.phase == 0 then
		data.movementStyle = settings.movementPlayStyle1
		data.attackStyle = settings.attackPlayStyle1
		summonIntend = settings.summonStyle1
	elseif data.phase == 1 then
		data.movementStyle = settings.movementPlayStyle2
		data.attackStyle = settings.attackPlayStyle2
		summonIntend = settings.summonStyle2
	elseif data.phase == 2 then
		data.movementStyle = settings.movementPlayStyle3
		data.attackStyle = settings.attackPlayStyle3
		summonIntend = settings.summonStyle3
	end
	if summonIntend == 0 then
		data.summonStyle = config.zingerID
	elseif summonIntend == 1 then
		data.summonStyle = config.zingerAggroID
	end
	if data.movementStyle == 1 then
		if data.movementStyle ~= 0 then data.keepXSpeed = 0 data.keepYSpeed = 0 end
	end
	if data.invincible == false then
		data.invincibleCooldown = settings.invincibleDelay
	else
		if data.invincibleCooldown <= 0 then
			data.invincible = false
		else
			if data.state == STATE.FLYING then data.invincibleCooldown = data.invincibleCooldown - 1 end
		end
	end
	if data.beeServants then
		data.beeServants.x = v.x + v.width / 2
		data.beeServants.y = v.y + v.height / 2 + 8
		if data.beeServants.cooldown <= 0 then
			data.beeServants = nil
		end
	end
	if data.state == STATE.FLYING then
		if data.movementStyle == 0 then
			handleFlyAround(v,data,config,settings)
			local speedX = settings.speedX + settings.speedXIncrease * data.phase
			if data.invincible == true then speedX = settings.speedXAggro end
			v.speedX = speedX * data.oldDirection
		elseif data.movementStyle == 1 then
			if data.timer % settings.chaseInterval == 0 then
				v.speedX = math.abs(data.dirVectr.x) * data.oldDirection
				v.speedY = data.dirVectr.y
				SFX.play(config.sfx_turn)
			end
			npcutils.faceNearestPlayer(v)
		end
		data.keepXSpeed = v.speedX
		data.keepYSpeed = v.speedY
		v.ai2 = v.ai2 + 1
		v.ai4 = v.ai4 + 1
		if v.ai2 >= v.ai1 and (data.attackStyle == 1 or data.attackStyle == 3) then
			v.ai1 = RNG.randomInt(210,370)
			v.ai2 = 0
			if data.useUniqueAttacks == true then
				data.state = STATE.SPIKE
				data.timer = 0
			end
		end
		if v.ai4 >= v.ai5 and (data.attackStyle == 2 or data.attackStyle == 3) then
			v.ai5 = RNG.randomInt(360,510)
			v.ai4 = 0
			if data.useUniqueAttacks == true and data.beeServants == nil then
				data.state = STATE.SUMMON
				data.timer = 0
			end
		end
	elseif data.state == STATE.SUMMON then
		v.speedX = 0
		v.speedY = 0
		if data.timer == 1 then SFX.play(config.sfx_battlecry) end
		if data.timer == 96 then
			data.timer = 0
			data.beeID = data.summonStyle
			v.speedX = data.keepXSpeed
			v.speedY = data.keepYSpeed
			data.beeServants = orbits.new{
				x = v.x + v.width / 2,
				y = v.y + v.height / 2,

				attachToNPC = data.beeServants,
				
				section = v.section,
				id = data.beeID,
				number = 4,
				radius = 64,
				
				rotationSpeed = 1,
				cooldown = config.summonDelay,
			}
			data.state = STATE.FLYING
			SFX.play(41)
		end
	elseif data.state == STATE.SPIKE then
		v.speedX = 0
		v.speedY = 0
		if data.timer == 1 then v.ai3 = 0 end
		if data.timer >= config.spikeDelay then
			if data.phase == 0 then
				for i = waves[data.spinyPhase + 1][1], waves[data.spinyPhase + 1][2] do
					local needles = NPC.spawn(config.hornID,v.x + 0.5 * v.width, v.y + 0.5 * v.height,v.section, false, true)
					needles.data._basegame = needles.data._basegame or {}
					local needleData = needles.data._basegame
					needleData.spinyBulletDirection = i
					needles.friendly = v.friendly
					needles.layerName = "Spawned NPCs"
				end
				data.spinyPhase = (data.spinyPhase + 1) % 2
				data.timer = 0
				data.state = STATE.FLYING
				v.speedX = data.keepXSpeed
				v.speedY = data.keepYSpeed
			elseif data.phase == 1 then
				for i = waves[data.spinyPhase + 1][1], waves[data.spinyPhase + 1][2] do
					local needles = NPC.spawn(config.hornID,v.x + 0.5 * v.width, v.y + 0.5 * v.height,v.section, false, true)
					needles.data._basegame = needles.data._basegame or {}
					local needleData = needles.data._basegame
					needleData.spinyBulletDirection = i
					needles.friendly = v.friendly
					needles.layerName = "Spawned NPCs"
				end
				data.spinyPhase = (data.spinyPhase + 1) % 2
				if v.ai3 < 1 then
					v.ai3 = v.ai3 + 1
					data.timer = config.spikeDelay - 1
				else
					data.timer = 0
					data.state = STATE.FLYING
					v.speedX = data.keepXSpeed
					v.speedY = data.keepYSpeed
					v.ai3 = 0
				end
			elseif data.phase == 2 then
				local dir = -vector.right2:rotate(90 + (v.ai3 * 20) * v.direction)
				local bulletDirection
				if v.ai3 <= 1 then
					bulletDirection = 4
				elseif v.ai3 <= 3 then
					if v.direction == -1 then
						bulletDirection = 5
					else
						bulletDirection = 6
					end
				elseif v.ai3 <= 5 then
					if v.direction == -1 then
						bulletDirection = 1
					else
						bulletDirection = 2
					end
				elseif v.ai3 <= 7 then
					if v.direction == -1 then
						bulletDirection = 8
					else
						bulletDirection = 7
					end
				elseif v.ai3 <= 9 then
					bulletDirection = 3
				elseif v.ai3 <= 11 then
					if v.direction == -1 then
						bulletDirection = 7
					else
						bulletDirection = 8
					end
				elseif v.ai3 <= 13 then
					if v.direction == -1 then
						bulletDirection = 2
					else
						bulletDirection = 1
					end
				else
					if v.direction == -1 then
						bulletDirection = 6
					else
						bulletDirection = 5
					end
				end
				local speed = 3
				local needles = NPC.spawn(config.hornID,v.x + 0.5 * v.width, v.y + 0.5 * v.height,v.section, false, true)
				needles.data._basegame = needles.data._basegame or {}
				local needleData = needles.data._basegame
				needleData.spinyBulletDirection = bulletDirection
				needles.friendly = v.friendly
				needles.layerName = "Spawned NPCs"
				needles.speedX = dir.x * speed
				needles.speedY = dir.y * speed
				needles.ai1 = 1
				data.spinyPhase = (data.spinyPhase + 1) % 2
				if v.ai3 < 16 then
					v.ai3 = v.ai3 + 1
					data.timer = config.spikeDelay - 4
				else
					data.timer = 0
					data.state = STATE.FLYING
					v.speedX = data.keepXSpeed
					v.speedY = data.keepYSpeed
					v.ai3 = 0
				end
			end
			SFX.play(config.sfx_spike_pop)
		end
	elseif data.state == STATE.HURT then
		v.speedX = 0
		v.speedY = 0
		if data.timer == 1 then
			SFX.play(config.sfx_hit)
		elseif data.timer >= config.hurt1Frames * config.hurt1FrameSpeed + config.hurt2Frames * config.hurt2FrameSpeed + 80 then
			data.timer = 0
			data.state = STATE.FLYING
			npcutils.faceNearestPlayer(v)
			data.invincibleTimer = 0
			v.speedX = data.keepXSpeed
			v.speedY = data.keepYSpeed
			data.invincible = true
			if (settings.second ~= "" and data.phase == 1 and data.phase2ndEvent == false) then
				triggerEvent(settings.second)
				data.phase2ndEvent = true
			elseif (settings.third ~= "" and data.phase == 2 and data.phase3rdEvent == false) then
				triggerEvent(settings.third)
				data.phase3rdEvent = true
			end
		end
	elseif data.state == STATE.KILL then
		v.friendly = true
		v.speedX = 0
		v.speedY = 0
		if data.timer == 120 then
			Misc.givePoints(9,vector(v.x + (v.width / 2),v.y),true)
		end
		if data.timer <= 120 and data.timer % 16 == 0 then
			SFX.play(config.sfx_hit)
		end
		if data.timer >= 180 then
			v:kill(HARM_TYPE_NPC)
		end
		if data.timer == 1 and data.beeServants then
			data.beeServants.x = -9999999
			data.beeServants.y = -9999999
			data.beeServants = nil
		end
	end
	--Overall Flying Animation Code
	if data.state == STATE.FLYING or data.state == STATE.SPIKE or data.state == STATE.SUMMON then
		data.stateAnimation = STATE_ANIM.FLYING
	else
		if data.timer < config.hurt1Frames * config.hurt1FrameSpeed - 1 then
			data.stateAnimation = STATE_ANIM.HURT1
		else
			data.stateAnimation = STATE_ANIM.HURT2
		end
	end
		
	handleAnimation(v,data,config,settings)
end

function QueenB.onNPCHarm(eventObj,v,reason,culprit)
	local data = v.data
	local config = NPC.config[v.id]
	local settings = v.data._settings
	if v.id ~= npcID then return end
	
	if culprit then
		if culprit.__type == "Player" then
			--Bit of code taken from the basegame chucks
			if (culprit.x + 0.5 * culprit.width) < (v.x + v.width*0.5) then
				culprit.speedX = -4
			else
				culprit.speedX = 4
			end
		end
	end
	if culprit.__type == "NPC" and (culprit.id == 13 or culprit.id == 108 or culprit.id == 17) then
		culprit:kill()
	elseif reason ~= HARM_TYPE_LAVA then
		if (NPC.HITTABLE_MAP[culprit.id] or culprit.id == 45 and v:mem(0x138, FIELD_WORD) == 0) and culprit.id ~= 50 then
			culprit:kill()
		end
	end
	if not data.invincible and data.invincibleTimer >= 48 and data.state ~= STATE.HURT and data.state ~= STATE.KILL then
		if culprit then
			if culprit.__type == "NPC" and (culprit.id == 13 or culprit.id == 108 or culprit.id == 17) then
				data.health = data.health - 0.25
				culprit:kill()
			elseif reason ~= HARM_TYPE_LAVA then
				data.health = data.health - 1
				if (NPC.HITTABLE_MAP[culprit.id] or culprit.id == 45 and v:mem(0x138, FIELD_WORD) == 0) and culprit.id ~= 50 then
					culprit:kill()
				end
			else
				data.health = 0
			end
		else
			if reason == HARM_TYPE_SWORD then
				data.health = data.health - 0.5
				if Colliders.downSlash(player,v) then
					player.speedY = -6
				end
			else
				data.health = 0
			end
		end
		if data.health > 0 then
			if culprit then
				Animation.spawn(75, culprit.x-16, culprit.y-16)
			end
			eventObj.cancelled = true
			
			if culprit and (culprit.__type == "Player" or (culprit.__type == "NPC" and (culprit.id ~= 13 and culprit.id ~= 108 and culprit.id ~= 17))) then
				data.timer = 0
				data.state = STATE.HURT
				data.animationTimer = 0
				SFX.play(9)
			else
				SFX.play(9)
			end
			
			return
		else
			eventObj.cancelled = true
			data.state = STATE.KILL
			data.timer = 0
			v.speedX = 0
		end
	else
		eventObj.cancelled = true
	end
end

function QueenB.onDrawNPC(v)
	if v.id ~= npcID then return end
	local data = v.data

	if not v.isHidden then
		npcutils.drawNPC(v,{priority = -45, opacity = data.hurtOpacity})
		npcutils.hideNPC(v)
	end
end

function QueenB.onNPCKill(eventObj,v,reason)
	local data = v.data
	local config = NPC.config[v.id]
	local settings = v.data._settings
	if v.id ~= npcID then return end
	if reason == HARM_TYPE_OFFSCREEN then return end
	SFX.play(config.sfx_die)
end

--Gotta return the library table!
return QueenB