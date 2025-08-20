local smwMap = require("smwMap")

-- SMW Costumes
Player.setCostume(CHARACTER_MARIO,"SMW-Mario",true)
Player.setCostume(CHARACTER_LUIGI,"SMW-Luigi",true)

local rankSystem = require("rankSystem")
local coinTracker = require("coinTracker")
local littleDialogue = require("littleDialogue")
local Damage Pause = require("Damage Pause")
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
	{"1-C The Koopa Kastle.lvlx",40000,10000}, -- Koopa Kastle
	{"1-B8 Kore (Hard Mode).lvlx", 10000, 10000}
	
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