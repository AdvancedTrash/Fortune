local npc = {}
local npcManager = require("npcManager")
local effectconfig = require("game/effectconfig")
local id = NPC_ID

npcManager.setNpcSettings{
	id = id,
	gfxheight = 96,
	gfxwidth = 96,
	width = 60,
	height = 66,
	frames = 4,
	framestyle = 1,
	framespeed = 2, 
	speed = 1,

	nogravity = true,
	noblockcollision = true,
	nofireball = true,
	noiceball = true,
	noyoshi= true,
	nowaterphysics = true,
	jumphurt = true, 
	spinjumpsafe = true, 
	nogravity = true,
	noblockcollision = true,
}

local idle = Misc.resolveSoundFile("Zinger_DKC2")
local death = Misc.resolveSoundFile("Zinger_die")
local turn = Misc.resolveSoundFile("Zinger_turn")	
local playSound = false
local idleSoundObj
function effectconfig.onTick.TICK_ZINGER(v)
    if v.timer == v.lifetime-1 then
        v.speedX = math.abs(v.speedX)*-v.direction
    end

    v.animationFrame = math.min(v.frames-1,math.floor((v.lifetime-v.timer)/v.framespeed))
end
function npc.onTick()
    if playSound then
        -- Create the looping sound effect for all of the NPC's
        if idleSoundObj == nil then
			idleSoundObj = SFX.play{sound = idle,loops = 0}
        end
    elseif idleSoundObj ~= nil then -- If the sound is still playing but there's no NPC's, stop it
        idleSoundObj:stop()
        idleSoundObj = nil
    end
    
    -- Clear playSound for the next tick
    playSound = false
end
function npc.onTickEndNPC(v)
	data = v.data
	if data.noise == nil then
		data.noise = true
	end
	if (v.x + v.width > camera.x and v.x < camera.x + 800 and v.y + v.height > camera.y and v.y < camera.y + 600) then
		playSound = true
		data.noise = true
	else
		data.noise = false
	end
end

function npc.onPostNPCHarm(v, r, c)
	if v.id ~= id then return end

	local config = NPC.config[id]
	
	--Only play if the NPC is killed but not by offscreen or if another NPC dies.
	if reason == HARM_TYPE_OFFSCREEN then return end
	SFX.play(death)
	if c.__type == "NPC" and (c.id == 13 or c.id == 108 or c.id == 17) then
		culprit:kill()
	elseif r ~= HARM_TYPE_LAVA then
		if (NPC.HITTABLE_MAP[c.id] or c.id == 45 and v:mem(0x138, FIELD_WORD) == 0) and c.id ~= 50 then
			c:kill()
		end
	end
end

function npc.onNPCHarm(eventObj,v,reason,culprit)
	if v.id ~= id then return end

	local config = NPC.config[id]
	
	--Only play if the NPC is killed but not by offscreen or if another NPC dies.
	if reason == HARM_TYPE_OFFSCREEN then return end
	if culprit.__type == "NPC" and (culprit.id == 13 or culprit.id == 108 or culprit.id == 17) then
		culprit:kill()
	elseif r ~= HARM_TYPE_LAVA then
		if (NPC.HITTABLE_MAP[culprit.id] or culprit.id == 45 and v:mem(0x138, FIELD_WORD) == 0) and culprit.id ~= 50 then
			culprit:kill()
		end
	end
end

function npc.onInitAPI()
	local config = NPC.config[id]
	
	npcManager.registerEvent(id, npc, 'onTickEndNPC')
	npcManager.registerEvent(id, npc, 'onTickNPC')
	npcManager.registerHarmTypes(id,
		{
			HARM_TYPE_NPC,
			HARM_TYPE_PROJECTILE_USED,
			HARM_TYPE_HELD,
		}, 
		{
			[HARM_TYPE_NPC]=800,
			[HARM_TYPE_PROJECTILE_USED]=800,
			[HARM_TYPE_HELD]=800,
		}
	);
	
	registerEvent(npc, 'onPostNPCHarm')
	registerEvent(npc, 'onNPCHarm')
end


return npc