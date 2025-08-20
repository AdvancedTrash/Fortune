--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local effectconfig = require("game/effectconfig")
local npcutils = require("npcs/npcutils")

local npcIDs = {}
local sampleNPC = {}

local STATE_WANDER = 0
local STATE_ATTACK = 1

local hitboxOffset = {
[-1] = -64,
[1] = 0
}

function effectconfig.onTick.TICK_KUTLASS(v)
    if v.timer == v.lifetime-1 then
        v.speedX = math.abs(v.speedX)*v.direction
    end

	if v.timer == v.lifetime-1 then
		SFX.play("Klomp die.wav")
	end

    v.animationFrame = math.min(v.frames-1,math.floor((v.lifetime-v.timer)/v.framespeed))
end

--Register events
function sampleNPC.register(id)
	npcManager.registerEvent(id, sampleNPC, "onTickEndNPC")
	npcIDs[id] = true
end

--Register events
function sampleNPC.onInitAPI()
	registerEvent(sampleNPC, "onNPCHarm")
end

function sampleNPC.onTickEndNPC(v)
	--Don't act during time freeze
	if Defines.levelFreeze then return end
	
	local data = v.data
	local plr = Player.getNearest(v.x + v.width/2, v.y + v.height)
	local config = NPC.config[v.id]
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		data.initialized = false
		data.state = STATE_WANDER
		data.timer = 0
		data.turnTimer = 0
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
		data.state = STATE_WANDER
		data.timer = data.timer or 0
		data.turnTimer = data.turnTimer or 0
		data.hitbox = Colliders.Box(v.x,v.y,v.width + 64,v.height)
	end
	
	--Hitbox positions
	data.hitbox.x = v.x + hitboxOffset[v.direction]
	data.hitbox.y = v.y

	data.timer = data.timer + 1

	if data.state == STATE_WANDER then
	
		--Animation stuff
		v.animationFrame = math.floor(data.timer / 5) % 7
		
		--If the player goes within its hitbox, attack
		if Colliders.collide(plr,data.hitbox) then
			data.timer = 0
			v.ai2 = 0
			v.speedX = 0
			data.state = STATE_ATTACK
		--If close to the NPC, move faster
		elseif math.abs(plr.x-v.x)<= 128 then
			v.ai2 = v.ai2 + 1
			if v.ai2 == 1 then npcutils.faceNearestPlayer(v) end
			v.speedX = 2.3 * v.direction
		--If not near the player, wander about
		else
			v.ai2 = 0
			v.speedX = 1.3 * v.direction
		end
		
		--Handle turning frames
		if data.lastDirection == -v.direction then
			data.turnTimer = 1
		end
		if data.turnTimer > 0 and data.turnTimer <= 12 then
			data.turnTimer = data.turnTimer + 1
			v.animationFrame = math.floor((data.turnTimer - 2) / 6) % 2 + 7
			v.speedX = 0
		else
			data.turnTimer = 0
		end
		
		data.lastDirection = v.direction
	else
		--Animation stuff, if swinging its sword down and the player is in range, harm them
		if data.timer <= 44 and data.timer >= 0 then
			v.animationFrame = math.floor((data.timer - 1) / 4) % 11 + 9
			if Colliders.collide(plr,data.hitbox) and v.animationFrame == 19 then
				plr:harm()
			end
			if data.timer >= 32 then
				v.speedX = v.direction
			end
		--Get the sword stuck for a bit, until the timer reacher the configurable recoverTime variable
		elseif data.timer > 44 and data.timer <= 44 + config.recoverTime then
			v.speedX = 0
			if data.timer == 45 then SFX.play("Kutlass sword.wav") end
			v.animationFrame = math.floor((data.timer - 44) / 12) % 2 + 20
		--Set the timer to -24, I couldnt think of a better way to do this
		elseif data.timer > 44 + config.recoverTime then
			data.timer = -24
		else
			--Recover itself and get back to wandering about
			v.animationFrame = math.floor(data.timer / 6) % 4 + 22
			if data.timer == -1 then
				data.timer = 0
				data.state = STATE_WANDER
			end
		end
	end
	
	if Colliders.collide(plr, v) and plr.forcedState == 2 and not v.friendly and plr:mem(0x140,FIELD_WORD) == 0 --[[changing powerup state]] and plr.deathTimer == 0 --[[already dead]] and not Defines.cheat_donthurtme then
		v.ai1 = v.ai1 + 1
		if v.ai1 == 1 then
			SFX.play("Kutlass sword hit.wav")
		end
	else
		v.ai1 = 0
	end
	
	-- animation controlling
	v.animationFrame = npcutils.getFrameByFramestyle(v, {
		frame = data.frame,
		frames = config.frames
	});
	
end

function sampleNPC.onNPCHarm(eventObj, v, reason, culprit)
	--Cancel jump and spinjump damage if its swords are above its head
	if not npcIDs[v.id] then return end
	if (v.animationFrame < 19 or v.animationFrame > 21) and (v.animationFrame < 45 or v.animationFrame > 47) then
		if reason == 1 or reason == 8 then
			eventObj.cancelled = true
			if culprit then
				culprit:harm()
			end
		end
	end
end

--Gotta return the library table!
return sampleNPC