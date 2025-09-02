local npcManager = require("npcManager")
local effectconfig = require("game/effectconfig")
local redirector = require("redirector")
local npcutils = require("npcs/npcutils")



--Death effect logic taken from MrDoubleA's kritter NPCs.
--MDA also helped teach me about redirectors, and provided the code for it. He also helped with some sound stuff.
--Quine helped early on with some other sound things.
--Thanks to Hoeloe for helping with the onPostExplosionNPC function
--9thCore helped too

--******************************************************
--Graphics made by, and requested by FireSeraphim.
--******************************************************

local zingers = {}

local npcIDs = {}

local STATE_FLY = 0
local STATE_TURN = 1
local idle = Misc.resolveSoundFile("Zinger_DKC2")
local death = Misc.resolveSoundFile("Zinger_die")
local turn = Misc.resolveSoundFile("Zinger_turn")	
local playSound = false
local idleSoundObj
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi


function zingers.register(id)
	npcManager.registerEvent(id, zingers, "onTickEndNPC")
	npcManager.registerEvent(id, zingers, "onPostExplosionNPC")
	npcIDs[id] = true
end

function zingers.onInitAPI()
    registerEvent(zingers, "onPostNPCHarm")
	registerEvent(zingers,"onTick")
end

function zingers:onPostExplosionNPC(explosion, player)
	if Colliders.collide(explosion.collider,self) then
		self:harm(HARM_TYPE_HELD)
	end
end

function zingers.onPostNPCHarm(v, reason, culprit)
	--Only play if the NPC is killed but not by offscreen or if another NPC dies.
	if not npcIDs[v.id] or reason == HARM_TYPE_OFFSCREEN then return end

	SFX.play(death)

end

function effectconfig.onTick.TICK_ZINGER(v)
    if v.timer == v.lifetime-1 then
        v.speedX = math.abs(v.speedX)*-v.direction
    end

    v.animationFrame = math.min(v.frames-1,math.floor((v.lifetime-v.timer)/v.framespeed))
end

function zingers.onTick()
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

function getAnimationFrame(v) 
    local data = v.data
	
	if data.state == STATE_FLY then
		if v.direction == DIR_LEFT then
			v.animationFrame = math.floor(lunatime.tick() / 2) % 4
		else
			v.animationFrame = math.floor(lunatime.tick() / 2) % 4 + 7
		end
	end

	if data.state == STATE_TURN then
		local animTimer = data.turnTimer
		if v.direction == DIR_LEFT then
			v.animationFrame = math.floor((animTimer)/6) % 3 + 4
		else	
			v.animationFrame = math.floor((animTimer)/6) % 3 + 11
		end
	end
	
end 


--Execute various zingers AI patterns.
local function variant1(v, data, settings)
local myplayer=Player.getNearest(v.x,v.y)
	data.w = 11 * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	if math.abs(v.y-myplayer.y) < 512 and math.abs(v.x-myplayer.x) < 470 then
		if v.x < myplayer.x then
			v.direction = 1
		else
			v.direction = -1
		end
	end
		if data.timer % 10 == 0 then
			v.speedY = data.w * sin(data.w*data.timer)
		end
end

local function variant2(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedX = settings.aamplitude * data.w * cos(data.w*data.timer)
end

local function variant3(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedY = settings.aamplitude * data.w * cos(data.w*data.timer)
end

local function variant4(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedX = settings.aamplitude * -data.w * cos(data.w*data.timer)
	v.speedY = settings.aamplitude * -data.w * sin(data.w*data.timer)
end

local function variant5(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer - 1
	v.speedX = settings.aamplitude * -data.w * cos(data.w*data.timer)
	v.speedY = settings.aamplitude * -data.w * sin(data.w*data.timer)
end


local function variant6(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedX = settings.aamplitude * -data.w * cos(data.w*data.timer / 2)
	v.speedY = settings.aamplitude * data.w * sin(data.w*data.timer)
end

local function variant7(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedX = settings.aamplitude * data.w * cos(data.w*data.timer / 2)
	v.speedY = settings.aamplitude * -data.w * sin(data.w*data.timer)
end

local function variant8(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedY = settings.aamplitude * -data.w * cos(data.w*data.timer / 2)
	v.speedX = settings.aamplitude * data.w * sin(data.w*data.timer)
end

local function variant9(v, data, settings)
	data.w = settings.aspeed * pi/65
	data.timer = data.timer or 0
	data.timer = data.timer + 1
	v.speedY = settings.aamplitude * data.w * cos(data.w*data.timer / 2)
	v.speedX = settings.aamplitude * -data.w * sin(data.w*data.timer)
end

local function variant10(v, data, settings)
	for _,bgo in ipairs(BGO.getIntersecting(v.x+(v.width/2)-0.5,v.y+(v.height/2),v.x+(v.width/2)+0.5,v.y+(v.height/2)+0.5)) do
		if redirector.VECTORS[bgo.id] then -- If this is a redirector and has a speed associated with it
			local redirectorSpeed = redirector.VECTORS[bgo.id]*settings.aspeed -- Get the redirector's speed and make it match the speed in the NPC's settings		
			-- Now, just put that speed from earlier onto the NPC
			v.speedX = redirectorSpeed.x
			v.speedY = redirectorSpeed.y
			if settings.aspeed <= -0.1 then
			v.speedX = -redirectorSpeed.x
			v.speedY = -redirectorSpeed.y
			end
		elseif bgo.id == redirector.TERMINUS then -- If this BGO is one of the crosses
			-- Simply make the NPC stop moving
			v.speedX = 0
			v.speedY = 0
		end
	end
end


function zingers.onTickEndNPC(v)
	local data = v.data
	local settings = v.data._settings
	data.algorithm = settings.algorithm
	getAnimationFrame(v)
	data.state = STATE_FLY
	data.turnTimer = data.turnTimer or 0
	data.movetimer = data.movetimer or 0
	
	--Don't act during time freeze
	if Defines.levelFreeze then return end

	--If despawned
	if v:mem(0x12A, FIELD_WORD) <= 0 then
		--Reset our properties, if necessary
		data.initialized = false
		if v.despawnTimer <= 0 then
			data.movetimer = 0
			data.timer = 0
		end
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
	end

	--Depending on the NPC, these checks must be handled differently
	if v:mem(0x12C, FIELD_WORD) > 0    --Grabbed
	or v:mem(0x136, FIELD_BOOL)        --Thrown
	or v:mem(0x138, FIELD_WORD) > 0    --Contained within
	then
		--Handling
	end
	
		--Do this when the NPC changes direction
		if data.lastDirection == -v.direction then
			if data.noise then
				SFX.play(turn)
			end
			data.turnTimer = 1
			if v.direction == 1 then
				v.animationFrame = 0
			else
				v.animationFrame = 7
			end
		end
			if data.turnTimer > 0 and data.turnTimer <=12 then
				data.state = STATE_TURN
				data.turnTimer = data.turnTimer + 1
			else
				data.state = STATE_FLY
				data.turnTimer = 0
			end
			data.lastDirection = v.direction
			
	if not v.friendly and NPC.config[v.id].strong then
        for _,p in ipairs(NPC.getIntersecting(v.x - 5, v.y - 5, v.x + v.width + 5, v.y + v.height + 5)) do
		--If the intersecting NPC is being held or has been thrown.
            if p:mem(0x12A, FIELD_WORD) > 0 and p:mem(0x138, FIELD_WORD) == 0 and (not p.isHidden) and (not p.friendly) then
                if p:mem(0x12C, FIELD_WORD) > 0 or p:mem(0x132, FIELD_WORD) > 0 then
				--List of IDs which do not cause any sound.
				local noSoundNPCs = {22, 26, 31, 32, 35, 49, 154, 155, 156, 157, 171, 191, 193, 238, 278, 279, 433, 434, 451, 452, 453, 454, 457}
                  local isNoSoundNPC = false
                  for _,id in ipairs(noSoundNPCs) do
                        if p.id == id then
                            isNoSoundNPC = true
                            break
                        end                        
                    end
					--Play the death sound if not one of the NPCs listed in noSoundNPCs.
                    if not isNoSoundNPC then
                        p:harm(HARM_TYPE_HELD)
                        SFX.play(death)
                    end
                end
            end
        end
    end
			
		--Makes it so the NPC begins moving if you come back to it on variant 6 and 7 and data.timer is set to its original postion for some settings.
		if math.abs((player.x + 0.5 * player.width) - (v.x + 0.5 * v.width))<436 then
			data.movetimer = data.movetimer + 1
			if data.movetimer == 1 then
				if settings.algorithm ==5 then
					v.speedX = settings.aspeed * v.direction
				elseif settings.algorithm ==6 then
					v.speedY = settings.aspeed
				end
			end
		end	
	if (v.x + v.width > camera.x and v.x < camera.x + 800 and v.y + v.height > camera.y and v.y < camera.y + 600) then
		playSound = true
		data.noise = true
	else
		data.noise = false
	end
		
	if settings.algorithm == 0 then
		variant1(v, data, settings)
	elseif settings.algorithm == 1 then
		variant2(v, data, settings)
	elseif settings.algorithm == 2 then
		variant3(v, data, settings)
	elseif settings.algorithm == 3 then
		variant4(v, data, settings)
	elseif settings.algorithm == 4 then
		variant5(v, data, settings)
	elseif settings.algorithm == 7 then
		variant6(v, data, settings)
	elseif settings.algorithm == 8 then
		variant7(v, data, settings)
	elseif settings.algorithm == 9 then
		variant8(v, data, settings)
	elseif settings.algorithm == 10 then
		variant9(v, data, settings)
	elseif settings.algorithm == 5 or settings.algorithm == 6 then
		variant10(v, data, settings)
	end
end

return zingers