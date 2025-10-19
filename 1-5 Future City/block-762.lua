--Blockmanager is required for setting basic Block properties
local blockManager = require("blockManager")

--Create the library table
local boostblock = {}
--BLOCK_ID is dynamic based on the name of the library file
local blockID = BLOCK_ID

--Defines Block config for our Block. You can remove superfluous definitions.
local boostblockSettings = {
	id = blockID,
	--Frameloop-related
	frames = 16,
	framespeed = 6, --# frames between frame change

	--Identity-related flags:
	--semisolid = false, --top-only collision
	--sizable = false, --sizable block
	--passthrough = false, --no collision
	--bumpable = false, --can be hit from below
	--lava = false, --instakill
	--pswitchable = false, --turn into coins when pswitch is hit
	--smashable = 0, --interaction with smashing NPCs. 1 = destroyed but stops smasher, 2 = hit, not destroyed, 3 = destroyed like butter

	--floorslope = 0, -1 = left, 1 = right
	--ceilingslope = 0,

	--Emits light if the Darkness feature is active:
	--lightradius = 100,
	--lightbrightness = 1,
	--lightoffsetx = 0,
	--lightoffsety = 0,
	--lightcolor = Color.white,

	--Define custom properties below
}

--Applies blockID settings
blockManager.setBlockSettings(boostblockSettings)

--Register the vulnerable harm types for this Block. The first table defines the harm types the Block should be affected by, while the second maps an effect to each, if desired.

--Custom local definitions below
local particles = require("particles")
local trail = particles.Emitter(0, 0, Misc.resolveFile("boost_trail.ini"))
local DEFAULT_RUNSPEED = 6      -- SMBX2’s normal top run speed
local boosting        = false   -- you already have this; keep or add
local boost_direction = 1       -- "
local boost_timer     = 0       -- "

--Register events
function boostblock.onInitAPI()
	blockManager.registerEvent(blockID, boostblock, "onTickEndBlock")
	registerEvent(boostblock, "onTickEnd")
	registerEvent(boostblock, "onTick")
	registerEvent(boostblock, "onDraw")
	registerEvent(boostblock, "onInputUpdate")
	trail:Attach(player)
end

local function cancelBoost()
    boosting        = false
    boost_timer     = 0
    Defines.player_runspeed = DEFAULT_RUNSPEED
    if math.abs(player.speedX) > DEFAULT_RUNSPEED then
        player.speedX = player.speedX * 0.8
    end
end

function boostblock.onInputUpdate()
    if boosting and boost_timer > 0 then
        -- opposite to the locked boost_direction?
        local oppositeHeld =
            (boost_direction == 1  and player.leftKeyPressing)  or
            (boost_direction == -1 and player.rightKeyPressing)

        if oppositeHeld then
            cancelBoost()       -- immediate decay + hand control back to physics
        end
    end
end


function boostblock.onDraw()
    trail:Draw(-30)
    for _,v in ipairs(Block.get(blockID)) do
        local a = (v.data and v.data.redfx) or 0
        Graphics.drawBox{
            x = v.x, y = v.y, sceneCoords = true, priority = -1,
            width = 64, height = 32,
            color = Color.yellow .. a
        }
    end
end

function boostblock.onTickEnd()
    if boosting and boost_timer > 0 then
        local dir = boost_direction        -- locked-in direction for this boost
        player.speedX = (math.abs(player.speedX) < 3 and 10 or 12) * dir
        Defines.player_runspeed = math.abs(player.speedX) + 1
    end
end


function boostblock.onTickEndBlock(v)
    -- Don't run code for invisible entities
	if v.isHidden or v:mem(0x5A, FIELD_BOOL) then return end
	
	local data = v.data
	data.redfx = data.redfx or 0
	
	--Execute main AI here. This template hits itself.
	if data.redfx > 0 then
		trail:setParam("rate", 0.1)
		trail:setParam("lifetime", 0.3)
		trail:Emit(1)
		data.redfx = data.redfx - 0.02
	elseif data.redfx < 0 then
		data.redfx = 0
	end

	if v:collidesWith(player) == 1 then
		if not boosting then
			boosting = true
		end
		boost_direction = player.direction
		boost_timer = 65
		data.redfx = 0.7
		SFX.play(86)
	end
end

function boostblock.onTick()
	if boost_timer > 0 then
		boost_timer = boost_timer - 1
	end

	if boost_timer == 0 then
		boosting = false
	end

	if boost_timer > 0 then
		local dir = boost_direction         -- locked-in direction
		if math.abs(player.speedX) < 3 then
			player.speedX = 10 * dir
		else
			player.speedX = 12 * dir
		end
		Defines.player_runspeed = math.abs(player.speedX) + 1
	else
		-- decay runspeed back to normal when not boosting
		if Defines.player_runspeed > 6 then
			Defines.player_runspeed = Defines.player_runspeed - 0.2
			if math.ceil(Defines.player_runspeed) == 6 then
				Defines.player_runspeed = 6
			end
		end
	end

	if player:mem(0x48, FIELD_WORD) ~= 0 and player.speedY == 0 and boosting then
		player.speedX = player.speedX - (2 * player.direction)
	end
end

--Gotta return the library table!
return boostblock