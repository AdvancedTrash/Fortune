local smwMap = require("smwMap")

-- SMW Costumes
Player.setCostume(CHARACTER_MARIO,"SMW-Mario",true)
Player.setCostume(CHARACTER_LUIGI,"SMW-Luigi",true)

local rankSystem = require("rankSystem")
local coinTracker = require("coinTracker")
local littleDialogue = require("littleDialogue")
local customPause = require("customPause")
local playerphysicspatch = require("playerphysicspatch")
local checklist = require("checklist")
local aw = require("anotherwalljump")
aw.registerAllPlayersDefault()
local twirl = require("twirl")
local customCamera = require("customCamera")
local respawnRooms = require("respawnRooms") 
local minHUD = require("minHUD")
local fastFireballs = require("fastFireballs")
local levelTimerEvent = require("levelTimerEvent")
local warpTransition = require("warpTransition")
local splishSplash = require("splishSplash")
local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")

local levels = {
	{"1-1 Adventure Away.lvlx",40000,10000}, -- Adventure Away
	{"1-2 Cavern Depths.lvlx",40000,10000}, -- Cavern Depths
	{"1-3 Dolphin Ride.lvlx",40000,10000}, -- Dolphin Ride
    {"1-4 Barrels of Fun.lvlx",40000,10000}, -- Barrels of Fun
	{"1-C The Koopa Kastle.lvlx",40000,10000}, -- Koopa Kastle
    {"1-B8 Queen B (Hard Mode).lvlx",10000,10000}, --World 1: Challenge 8 (Queen B Hard Mode)
	{"1-B12 Kore (Hard Mode).lvlx", 10000, 10000}, --World 1: Challenge 12 (Kore Hard Mode)
	
}

for i = 1, #levels do
	rankSystem.registerLevel(
		levels[i][1], -- registers the levelname per level
		levels[i][2], -- registers the requirement per level
		levels[i][3] -- registers the time preset per level
	)
end

function onStart()
	if rankSystem.allLevelsTopRank() then
		SFX.play(29)
	end
end

function rankSystem.onLevelComplete(score,rank,time) -- runs upon the player completing a level
	if rank <= 0 then
		SFX.play(80)
	end
end

function rankSystem.onRankGive(rank) -- runs upon the final rank being revealed
	if rank == #rankSystem.rankThresholds then
		SFX.play(59)
	end
end

function onPlayerHarm(p)
	player:kill()
end

function onInputUpdate()
    if Level.filename() == "map.lvlx" or Level.isOverworld then
        player.dropItemKeyPressing = false
    end
end

--Power-up freeze
local FREEZE_FRAMES = 42
local freezeTimer = 0

function onInitAPI()
    registerEvent(nil, "onTick")
    registerEvent(nil, "onPostNPCCollect")
end

local function isPowerup(id)
    local cfg = NPC.config[id]
    return (cfg and (cfg.ispowerup or cfg.isPowerup or cfg.isPowerUp)) 
           or id == 185   -- Super Mushroom
           or id == 183  -- Fire Flower
           or id == 34  -- Leaf
           or id == 169 -- Tanooki
           or id == 277 -- Ice Flower
           or id == 273
end

function onPostNPCCollect(n, p)
    if not p or not n.isValid then return end
    if isPowerup(n.id) then
        freezeTimer = math.max(freezeTimer, FREEZE_FRAMES)
    end
end

function onTick()
    if freezeTimer > 0 then
        freezeTimer = freezeTimer - 1

        Defines.levelFreeze = true

        player.speedX = 0
        if player.speedY > 0 then player.speedY = 0 end
    else
        Defines.levelFreeze = false
    end
end