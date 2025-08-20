--[[
					rankSystem.lua by MrNameless
			A library that overhauls SMBX's score system to
		judge the player's performance in a level in a similar
			manner to Sonic Adventure 2 and Sonic Unleashed.
			
	CREDITS:
	HomingMissile333 - Ripped the C,B,A and S rank sprites from Sonic Rush used here. (https://www.deviantart.com/homingmissile333/art/Sonic-Rush-Ranks-Sprites-376804502)
	piplupfan77 - Ripped the rank reveal SFX from Sonic Adventure 2 used here. (https://youtu.be/xMe1zF2FQ9w?feature=shared)
	Random Talking Bush - Ripped the rank slide & the new record SFX from Sonic Unleashed used here. (https://www.sounds-resource.com/xbox_360/sonicunleashed/sound/33675/)
	Marioman2007 & Chipss - Provided the formatTime function used here.
	KBM-Quine - Used pieces of audioCutoffPrevention.lua to handle stalling/reseting the victory timer. (https://www.smbxgame.com/forums/viewtopic.php?t=29158)
	bonel_ - Used a similar method of lining up the results slide via routines from their rankCounter.lua script. (https://www.smbxgame.com/forums/viewtopic.php?t=30112)
	
	TO DO:
	- Figure out how to get the flagpole & switch palace victory states to be stalled. (they seem to currently have hardcoded victory timers so far)
	- Figure out how to get the script running while the game is paused. (SMW Goal Orb is currently forced to not pause the game because of this)
	- include much more flexible control over the results screen & the sequence of it's events, for other programmers having custom goals.
	
	Version 1.5.0
]]--

local tplus = require("textplus")
local easing = require("ext/easing")

local gamedata
local goaltape
local smwMap

if not isOverworld then
	goaltape = require("npcs/ai/goaltape")
	pcall(function() smwMap = require("smwMap") end)
	GameData.rankSystem = GameData.rankSystem or {}
	GameData.rankSystem[Level.filename()] = GameData.rankSystem[Level.filename()] or {}
	gamedata = GameData.rankSystem[Level.filename()]
	gamedata.currentTime = gamedata.currentTime or 0
end

local rankSystem = {}

SaveData.rankSystem = SaveData.rankSystem or {}

rankSystem.allowCheckpointResets = true
rankSystem.rankFont = tplus.loadFont("minFont.ini")
rankSystem.unrankedImage = Graphics.loadImageResolved("rankSystem/rankSystem-rankNone.png")
rankSystem.rankImage = Graphics.loadImageResolved("rankSystem/rankSystem-ranks.png")
rankSystem.specialNPCs = table.map{90,186,187,188,196,274,310,411} -- feel free to add more NPCs of your choice here

rankSystem.barOffsets = {
	yOffset = -64,
	rankingYOffset = 50,
	barSpacing = 40,
	barHeight = 8,
}

rankSystem.timer = {
	enabled = true,
	x = 782,
	y = 580,
}

rankSystem.sounds = {
	slideSFX = SFX.open(Misc.resolveSoundFile("rankSystem/rankSystem-slideSFX.ogg")),
	rankSFX = SFX.open(Misc.resolveSoundFile("rankSystem/rankSystem-rankingSFX.ogg")),
	newRecordSFX = SFX.open(Misc.resolveSoundFile("rankSystem/rankSystem-newRecordSFX.ogg")),
	drumLoopSFX = SFX.open(Misc.resolveSoundFile("goalTape_countdown_loop.wav")),
	drumEndSFX = SFX.open(Misc.resolveSoundFile("goalTape_countdown_end.wav"))
}

--SFX.open(Misc.resolveSoundFile("goalTape_countdown_loop.wav"))
rankSystem.rankThresholds = {
	0.2, -- 1/5 of the score requirement of a level (D Rank)
	0.4, -- 2/5 of the score requirement of a level (C Rank)
	0.6, -- 3/5 of the score requirement of a level (B Rank)
	0.8, -- 4/5 of the score requirement of a level (A Rank)
	1,	 -- S Rank
}

rankSystem.victory_wait_times = {
	[LEVEL_END_STATE_ROULETTE] = 2.25,
	[LEVEL_END_STATE_SMB3ORB] = 2.5,
	[LEVEL_END_STATE_KEYHOLE] = 9999,
	[LEVEL_END_STATE_SMB2ORB] = 1.35,
	[LEVEL_END_STATE_GAMEEND] = 9,
	[LEVEL_END_STATE_STAR] = 1.05,
	[LEVEL_END_STATE_TAPE] = 2.5,
	[LEVEL_END_STATE_SWITCHPALACE] = 2.5,
	[LEVEL_END_STATE_FLAGPOLE] = 2,
	[LEVEL_END_STATE_SMW] = 2.5,
}

local STATE_ACTIVE = 0
local STATE_DISPLAY = 1
local STATE_CALCULATE = 2
local STATE_REVEAL = 3
local rankingState = STATE_ACTIVE

local loopSFX = nil
local finalScore = nil
local allowLevelExit = false
local initialScore = 0
local finalRanking = 0
local checkpointReset = 0

local directCoiners = table.map{1,3,7,10,11,15}
local bonuses_map = table.map{}
local bonuses = {}

local victoryState = 0
local victoryTimer = 0

local generatedNPCs = {}

local rankLetter = {
	scale = 9,
	opacity = 0,
}

local newRecord = {
	inGeneral = false,
	allowPrint = false,
	bestTime = false,
	highScore = false,
}

function rankSystem.registerLevel(levelname,requirement,timePreset)
	if SaveData.rankSystem[levelname] then 
		local level = SaveData.rankSystem[levelname]
		level.requirement = requirement
		level.timePreset = timePreset
		return 
	end
	SaveData.rankSystem[levelname] = {
		requirement = requirement,
		timePreset = timePreset,
		highScore = 0,
		highestRank = nil,
		bestTime = nil,
	}
end

function rankSystem.removeLevel(levelname)
	if not SaveData.rankSystem[levelname] then return end
	SaveData.rankSystem[levelname] = nil
end

function rankSystem.registerBonus(name,multiplier)
	if bonuses[name] then return end
	table.insert(bonuses_map,name)
	bonuses[name] = {
		curAmount = 0,
		multiplier = multiplier or 1,
		x = -200,
	}
end

function rankSystem.getBonus(name)
	if not bonuses[name] then return nil end
	return bonuses[name]
end

function rankSystem.removeBonus(name)
	if name == "TOTAL SCORE" then return end
	bonuses[name] = nil
	for i = 1, #bonuses_map do
		if bonuses_map[i] == name then
			table.remove(bonuses_map, i)
			break
		end
	end
end

function rankSystem.allLevelsTopRank()
	for i,v in pairs(SaveData.rankSystem) do
		if v.highScore < v.requirement then
			return false
		end
	end
	return true
end

do
	rankSystem.registerBonus("time",1)
	rankSystem.registerBonus("coin",100)
	rankSystem.registerBonus("enemy",100)
	rankSystem.registerBonus("combo",200)
	rankSystem.registerBonus("special",1000)
end

local function formatTime(x)
    local fps     = Misc.GetEngineTPS()
    local mins    = x / (60 * fps) % 60
    local secs    = x / fps % 60
    local minsecs = math.floor((x % fps / fps * 1000)/10)

    local timerFormat = string.format(
        "%.2d:%.2d:%.2d",
        mins, secs, minsecs
    )

    if x < 0 then
        return("-")
    end

    return timerFormat
end

local function isGeneratedNPC(v)
	if not v or not v.isValid then 
		generatedNPCs[v] = nil
		return false 
	end
	
	if v.isGenerator or generatedNPCs[v] then 
		return true 
	end
	
	return false
end

local function handleCombo(obj,address)
	Routine.run(function()
		Routine.skip()
		if not obj or not obj.isValid then return end
		if obj:mem(address,FIELD_WORD) > 1 then
			if bonuses["combo"] then
				bonuses["combo"].curAmount = bonuses["combo"].curAmount + obj:mem(address,FIELD_WORD) - 1
			end
			if obj:mem(address,FIELD_WORD) > 7 and bonuses["special"] then
				bonuses["special"].curAmount = bonuses["special"].curAmount + 1
			end	
		end
	end)
end

local function freezeScore(lastScore)
	if lastScore == nil then
		lastScore = Misc.score()
	end
	Misc.score((0 - Misc.score()) + lastScore)
	Routine.run(function()
		Routine.skip()
		Misc.score((0 - Misc.score()) + lastScore)
	end)
end

local function updateHighscores(level,exited)
	if not level then return end
	---------- sets the values of the scores, time & ranking shown at the results screen ----------
	if not exited then
		initialScore = Misc.score()
		for i = 1, #bonuses_map do
			local v = bonuses[bonuses_map[i]]
			if bonuses_map[i] == "time" then
				v.curAmount = math.max(level.timePreset - v.curAmount,0)
			else
				v.curAmount = v.curAmount * v.multiplier
			end
			Misc.score(v.curAmount)
		end
		
		finalScore = math.floor(Misc.score()) or 0
		
		for i = 1,#rankSystem.rankThresholds do
			if finalScore >= math.floor(level.requirement * rankSystem.rankThresholds[i]) then
				finalRanking = i
			else
				break
			end
		end
		
		rankSystem.onLevelComplete(finalScore,finalRanking,gamedata.currentTime)
		
		if rankSystem.timer.enabled then
			if level.bestTime == nil or gamedata.currentTime < level.bestTime then
				newRecord.inGeneral = true
				newRecord.bestTime = true
			end
		end
		if finalScore >= level.highScore then
			newRecord.inGeneral = true
			newRecord.highScore = true
		end
	else 
	---------- actually saving the scores if the player successfully exited a level without dying ----------
		if level.bestTime == nil then
			level.bestTime = gamedata.currentTime
		else 
			level.bestTime = math.min(gamedata.currentTime,level.bestTime)
		end
		
		if level.highestRank == nil then
			level.highestRank = finalRanking
		else
			level.highestRank = math.max(finalRanking,level.highestRank)
		end
		level.highScore = math.max(finalScore,level.highScore)
	end
end

function rankSystem.onInitAPI()
	if not isOverworld and (not smwMap or Level.filename() ~= smwMap.levelFilename) then
		registerEvent(rankSystem, "onStart")
		registerEvent(rankSystem, "onTickEnd")
		registerEvent(rankSystem, "onDraw")
		registerEvent(rankSystem, "onBlockHit")
		registerEvent(rankSystem, "onNPCHarm")
		registerEvent(rankSystem, "onNPCKill")
		registerEvent(rankSystem, "onNPCTransform")
		registerEvent(rankSystem, "onNPCCollect")
		registerEvent(rankSystem, "onNPCGenerated")
		registerEvent(rankSystem, "onExitLevel")
	else
		registerEvent(rankSystem, "onTick", "onTickOverworld")
		registerEvent(rankSystem, "onDraw", "onDrawOverworld")
	end
	registerCustomEvent(rankSystem, "onLevelComplete")
	registerCustomEvent(rankSystem, "onRankGive")
end

function rankSystem.onStart()
	Misc.score(0 - Misc.score())
	NPC.config[353].startExitTime = 600
	NPC.config[354].startExitTime = 600
	NPC.config[353].doTimerCountdown = false
	NPC.config[354].pausesGame = false
	
	---------- resets the timer if starting at the very beginning ----------
	if bonuses["time"] then
		if Checkpoint.getActiveIndex() > 0 
		or mem(0x00B250B0, FIELD_STRING) ~= "" then
			return
		end
		gamedata.currentTime = 0
	end
end

function rankSystem.onTickEnd()
	if not SaveData.rankSystem[Level.filename()] then return end
	local winningPlayer
	local allPlayersDied = false
	for _,p in ipairs(Player.get()) do
		---------- handles finding out who touched a SMW Goaltape/orb first ----------
		if not winningPlayer then
			if (goaltape and goaltape.playerInfo[p.idx]) or p.forcedState == FORCEDSTATE_FLAGPOLE then
				winningPlayer = p
			end
		end
		---------- done to prevent the incrementing of the level timer if all players are dead ----------
		if p.deathTimer > 0 then
			allPlayersDied = true
		else
			allPlayersDied = false
			break
		end
	end
	local bonus = bonuses

	---------------------------- HANDLES THE TIMER & CHECKING IF THE LEVEL HAS ENDED ----------------------------
	if victoryState == LEVEL_WIN_TYPE_NONE then
		if bonus["time"] and not allPlayersDied then
			gamedata.currentTime = gamedata.currentTime + 1
			bonus["time"].curAmount = gamedata.currentTime
		end
		if Level.winState() ~= LEVEL_WIN_TYPE_NONE then
			victoryState = Level.winState()
		elseif winningPlayer and winningPlayer.forcedState == FORCEDSTATE_FLAGPOLE then
			victoryState = LEVEL_END_STATE_FLAGPOLE
		end
	end
	
	if victoryState == LEVEL_WIN_TYPE_NONE then return end
	victoryTimer = victoryTimer + 1
	
	if allowLevelExit == false then
		if victoryState ~= LEVEL_END_STATE_GAMEEND then
			mem(0x00B2C5A0, FIELD_WORD, 0)
		else
			mem(0x00B2C5A0, FIELD_WORD, math.min(mem(0x00B2C5A0, FIELD_WORD),600))
		end
		if winningPlayer and goaltape.playerInfo[winningPlayer.idx] then
			goaltape.playerInfo[winningPlayer.idx].timer = math.min(goaltape.playerInfo[winningPlayer.idx].timer,595)
		end
	else
		mem(0x00B2C5A0, FIELD_WORD, 9999)
	end
	
	---------------------------- HANDLES SETTING UP FINAL SCORE & THE RANKING SCREEN ----------------------------
	if finalScore == nil and SaveData.rankSystem[Level.filename()] then
		updateHighscores(SaveData.rankSystem[Level.filename()],false)
		Routine.run(function()
			Routine.wait(rankSystem.victory_wait_times[victoryState])
			rankSystem.registerBonus("TOTAL SCORE",1)
			bonus["TOTAL SCORE"].curAmount = initialScore
			rankingState = STATE_DISPLAY
		end)
	end
	
	---------- lock the score to it the moment before the player reaching the goal ----------
	if rankingState == STATE_ACTIVE and finalScore ~= nil and Misc.score() ~= initialScore then 
		freezeScore(initialScore)
	end
	
	---------------------------- HANDLES SLIDING IN BONUSES ----------------------------
	if rankingState == STATE_DISPLAY then
		for i=1, #bonuses_map do
			local v = bonuses[bonuses_map[i]]
	---------- handles moving each bonus's slider to the center of the screen ----------
			if v.x <= -200 then
				SFX.play(rankSystem.sounds.slideSFX)
			end
			v.x = easing.outBounce(20, v.x, ((camera.width * 0.5) - 250) - v.x, 232)
			if math.ceil(v.x) < (camera.width * 0.5) - 425 then break end
		end
	---------- starts up the drumroll & starts the score calculation ----------
		if victoryTimer >= (math.floor(Misc.GetEngineTPS()) * rankSystem.victory_wait_times[victoryState]) + math.floor(Misc.GetEngineTPS()) * 3 then
			rankingState = STATE_CALCULATE
			loopSFX = SFX.play(rankSystem.sounds.drumLoopSFX,1,0)
		end
	end
	
	---------------------------- HANDLES CALCULATING BONUSES ----------------------------
	if rankingState == STATE_CALCULATE then
		local fullyZeroBonuses = true
		for i=1, #bonuses_map do
			local v = bonuses[bonuses_map[i]]
		---------- handles counting down bonuses to 0 ----------
			if i < #bonuses_map then
				v.curAmount = math.floor(math.lerp(v.curAmount,0,0.05)) 
				if player.rawKeys.jump or player.rawKeys.altJump then
					v.curAmount = 0
				end
				if v.curAmount > 0 then
					fullyZeroBonuses = false
				end
		---------- handles counting up the current score to the final one ----------
			else
				v.curAmount = math.ceil(math.lerp(v.curAmount,finalScore,0.05))  
				if player.rawKeys.jump or player.rawKeys.altJump then
					v.curAmount = finalScore
				end
				Misc.score((0 - Misc.score()) + v.curAmount)
				if v.curAmount ~= finalScore then
					fullyZeroBonuses = false
				end
			end
		end
		---------- handles stopping drumroll & start revealing the final rank ----------
		if fullyZeroBonuses == true and loopSFX and loopSFX:isplaying() then
			loopSFX:stop()
			SFX.play(rankSystem.sounds.drumEndSFX)
			if newRecord.inGeneral then
				SFX.play(rankSystem.sounds.newRecordSFX)
				newRecord.allowPrint = true
			end
			Routine.run(function()
				victoryTimer = 0
				Routine.wait(1)
				rankingState = STATE_REVEAL
				SFX.play(rankSystem.sounds.rankSFX)
				rankSystem.onRankGive(finalRanking)
			end)
		end
	end
	
	-------------- HANDLES REVEALING FINAL RANK & ALLOWS EXITING OF LEVEL --------------
	if rankingState == STATE_REVEAL then
		rankLetter.scale = easing.outInQuart(15,rankLetter.scale,1 - rankLetter.scale,100) --math.lerp(rankLetter.scale, 1, 0.25)
		rankLetter.opacity = easing.outInQuart(15,rankLetter.opacity,1 - rankLetter.opacity,150)--math.min(rankLetter.opacity + 0.01,1)
		if victoryTimer >= 225 then 
			allowLevelExit = true
		end
	end
end

---------- handles drawing the score counters at the end of a level ----------
function rankSystem.onDraw()
	if not SaveData.rankSystem[Level.filename()] then return end
	local offsets = rankSystem.barOffsets
	local coords = {
		x = {
			left = -100,
			center = camera.width * 0.5
		},
		y = {
			center = camera.height * 0.5
		}
	}
	if bonuses["time"] and rankSystem.timer.enabled then 
		tplus.print{
			font = rankSystem.rankFont, 
			text = formatTime(gamedata.currentTime),
			x = rankSystem.timer.x, --coords.x.right - 132,
			y = rankSystem.timer.y, --47,
			xscale = 2, yscale = 2,
			pivot = vector(1,0),
		}
		if newRecord.allowPrint and newRecord.bestTime then
			tplus.print{
				font = rankSystem.rankFont, 
				text = "NEW RECORD!",
				color = Color.fromHexRGB(0xFFB500),
				x = rankSystem.timer.x - 132,
				y = rankSystem.timer.y,
				xscale = 2, yscale = 2,
				pivot = vector(1,0),
			}
		end
	end
	if victoryState == LEVEL_WIN_TYPE_NONE then return end
	if rankingState == STATE_ACTIVE then return end
	if finalScore == nil then return end
	local level = SaveData.rankSystem[Level.filename()]
	
	for i = 1, #bonuses_map do
		local v = bonuses[bonuses_map[i]]
		yCoords = (coords.y.center + offsets.yOffset) + (offsets.barSpacing * (i-1))
		local preset = {
			text = string.upper(tostring(bonuses_map[i])) .. " BONUS: " .. v.curAmount,
			vect = vector(0,0),
			color = Color.fromHexRGBA(0x7081ADAA)
		}
		if bonuses_map[i] == "TOTAL SCORE" then
			preset.text = string.upper(tostring(bonuses_map[i])) .. ": " .. v.curAmount .. "/" .. level.requirement
			preset.vect = vector(0.25,0)
			preset.color = Color.fromHexRGBA(0x40A49EBB)
			if newRecord.allowPrint and newRecord.highScore then
				tplus.print{
					font = rankSystem.rankFont, 
					text = "NEW RECORD!",
					color = Color.fromHexRGB(0xFFB500),
					x = v.x,
					y = yCoords + 20,
					xscale = 2, yscale = 2,
					pivot = vector(0,0)
				}
			end
		end
		Graphics.glDraw{
			color = preset.color,
			vertexCoords = {
				-- COORDS FOR FRIST TRIANGLE
				
				-- top left
				coords.x.left - 50, (yCoords + 8) - offsets.barHeight,
				-- top right
				v.x + 392, (yCoords + 8) - offsets.barHeight,
				-- bottom left
				coords.x.left - 50, (yCoords + 8) + offsets.barHeight,
				
				-- COORDS FOR SECOND TRIANGLE
				
				-- top right
				v.x + 392, (yCoords + 8) - offsets.barHeight,
				-- bottom left
				coords.x.left - 50, (yCoords + 8) + offsets.barHeight,
				-- bottom right
				v.x + 392 - 16, (yCoords + 8) + offsets.barHeight
			},
			priority = 0
		}
		tplus.print{
			font = rankSystem.rankFont, 
			text = preset.text,
			x = v.x,
			y = yCoords,
			xscale = 2, yscale = 2,
			pivot = preset.vect,
		}
		if math.ceil(v.x) < coords.x.center - 425 then break end
	end
	if rankingState ~= STATE_REVEAL then return end
	Graphics.drawBox{
		texture = rankSystem.rankImage,	
		priority = 5,
		width = rankSystem.rankImage.width*rankLetter.scale,
		height = (rankSystem.rankImage.height/(#rankSystem.rankThresholds+1))*rankLetter.scale,
		x = coords.x.center + 225, --p.x + (p.width * 0.5),
		y = coords.y.center + rankSystem.barOffsets.rankingYOffset,
		sourceY = rankSystem.rankImage.width * finalRanking,
		sourceHeight = rankSystem.rankImage.height/(#rankSystem.rankThresholds+1),
		color = Color.white .. rankLetter.opacity,
		centered = true,
	}
end

function rankSystem.onBlockHit(token,v,upper,p)
	if token.cancelled then return end
	if v.contentID <= 0 or v.contentID > 99 then return end
	if not p then return end
	if not directCoiners[p.character] then return end
	if not bonuses["coin"] then return end
	bonuses["coin"].curAmount = bonuses["coin"].curAmount + 1
end

---------- handles NPC combo-ing ----------
function rankSystem.onNPCHarm(token,v,harm,c)
	if not v or not v.isValid then return end
	if isGeneratedNPC(v) then 
		freezeScore()
		return
	end
	if victoryState ~= LEVEL_WIN_TYPE_NONE then return end
	if token.cancelled or harm == 9 then return end
	if not c then return end
	if type(c) == "Player" then
		handleCombo(c,0x56)
	elseif type(c) == "NPC" then
		handleCombo(c,0x24)
	end
	if not bonuses["enemy"] then return end
	bonuses["enemy"].curAmount = bonuses["enemy"].curAmount + 1
end

---------- handles eating npcs with a yoshi ----------
function rankSystem.onNPCKill(token,v,harm)
	if not v or not v.isValid then return end
	if isGeneratedNPC(v) then 
		freezeScore()
		return
	end
	if NPC.config[v.id].iscoin or NPC.config[v.id].isinteractable then return end
	if not bonuses["enemy"] then return end
	if v.forcedState ~= 5 or v.forcedCounter1 <= 0 then return end
	bonuses["enemy"].curAmount = bonuses["enemy"].curAmount + 1
end

---------- handles bouncing on npcs that transforms ----------
function rankSystem.onNPCTransform(v,oldID,harm)
	if not v or not v.isValid then return end
	if harm ~= 1 and harm ~= 8 then return end
	if isGeneratedNPC(v) then 
		freezeScore()
		return
	end
	for i,p in ipairs(Player.getIntersecting(v.x - 2,v.y - 4,v.x + v.width + 2,v.y + v.height)) do
		handleCombo(p,0x56)
	end
end

---------- handles collecting coins & "special" npcs (star/dragon coins, 1ups, etc.) ---------- 
function rankSystem.onNPCCollect(token,v,p)
	if not v or not v.isValid then return end
	if victoryState ~= LEVEL_WIN_TYPE_NONE then return end
	if isGeneratedNPC(v) then 
		freezeScore()
		return
	end
	if not p then return end
	if rankSystem.specialNPCs[v.id] and bonuses["special"] then
		bonuses["special"].curAmount = bonuses["special"].curAmount + 1
		return 
	end
	if not NPC.config[v.id].iscoin or not bonuses["coin"] then return end
	bonuses["coin"].curAmount = bonuses["coin"].curAmount + 1
end

---------- done to prevent cheesing S-Ranks by farming generated npcs ----------
function rankSystem.onNPCGenerated(generator,v)
	if not v or not v.isValid then return end
	generatedNPCs[v] = true
end


---------- handles reseting the victory timer, & having a failsafe if the final score is yet to be calculated upon level exit ----------
function rankSystem.onExitLevel(winType)
	mem(0x00B2C5A0, FIELD_WORD, 0)
	if winType > 0 then
		if SaveData.rankSystem[Level.filename()] then
			if finalScore == nil then
				updateHighscores(SaveData.rankSystem[Level.filename()],false)
			end
			updateHighscores(SaveData.rankSystem[Level.filename()],true)
		end
		if gamedata and gamedata.currentTime then
			gamedata.currentTime = nil
		end
	end
end

-------------------------------------------------------- OVERWORLD STUFF --------------------------------------------------------

---------- handles reseting checkpoints ----------
function rankSystem.onTickOverworld()
	if not rankSystem.allowCheckpointResets then return end
	local levelObj
	local curFilename
	if smwMap and Level.filename() == smwMap.levelFilename then 
		levelObj = smwMap.mainPlayer.levelObj
		if levelObj == nil then return end
		curFilename = levelObj.settings.levelFilename
	elseif isOverworld then
		levelObj = world.levelObj
		if levelObj == nil then return end
		curFilename = levelObj.filename
	end
	if curFilename == nil then return end
	
	local gm = GameData.__checkpoints[curFilename]
	if (not gm or not gm.current) and mem(0x00B250B0, FIELD_STRING) == "" then return end
	if player.keys.run == KEYS_DOWN then
		checkpointReset = math.min(checkpointReset + 0.01,1)
		player:mem(0x130,FIELD_BOOL,false)
		if checkpointReset >= 1 then
			if gm ~= nil then
				gm.current = nil
			end
			if smwMap then
				for i=1, #SaveData.smwMap.unlockedCheckpoints[curFilename] do
					SaveData.smwMap.unlockedCheckpoints[curFilename][i] = false
				end
			end
			mem(0x00B250B0, FIELD_STRING, "")
			checkpointReset = 0
			SFX.play(36)
		end
	else
		checkpointReset = 0
	end
end

---------- handles drawing text on the overworld ----------
function rankSystem.onDrawOverworld()
	local centerX = 0 + (camera.width*0.5)
	local levelObj
	local curFilename
	if smwMap and Level.filename() == smwMap.levelFilename then 
		levelObj = smwMap.mainPlayer.levelObj
		if levelObj == nil then return end
		curFilename = levelObj.settings.levelFilename
	elseif isOverworld then
		levelObj = world.levelObj
		if levelObj == nil then return end
		curFilename = levelObj.filename
	end
	if curFilename == nil then return end
	
	if rankSystem.allowCheckpointResets then
		local gm = GameData.__checkpoints[curFilename]
		if (gm and gm.current) or mem(0x00B250B0, FIELD_STRING) ~= "" then
			tplus.print{
				font = rankSystem.rankFont, 
				text = "HOLD RUN TO RESET CHECKPOINTS",
				x = centerX - 328,
				y = 514,
				xscale = 2, yscale = 2,
				color = Color.white .. checkpointReset,
				priority = 5
			}
		end
	end
	if SaveData.rankSystem[curFilename] then
		local stats = SaveData.rankSystem[curFilename]
		local rankingImg = rankSystem.unrankedImage
		if stats.highestRank == nil then
			Graphics.drawBox{
				texture = rankSystem.unrankedImage,	
				priority = 5,
				x = centerX + 300,
				y = 92,
				centered = true,
				priority = 5.1,
			}
			tplus.print{
				font = rankSystem.rankFont, 
				text = "<color 0xF8D870>REQUIRED SCORE: </color>" .. "\n" .. stats.requirement,
				x = centerX - 328,
				y = 548,
				xscale = 2, yscale = 2,
				pivot = vector(0,0),
				priority = 7,
			}
		else
			Graphics.drawBox{
				texture = rankSystem.rankImage,	
				priority = 5,
				width = rankSystem.rankImage.width,
				height = (rankSystem.rankImage.height/(#rankSystem.rankThresholds+1)),
				x = centerX + 300,
				y = 92,
				sourceY = rankSystem.rankImage.width * stats.highestRank,
				sourceHeight = rankSystem.rankImage.height/(#rankSystem.rankThresholds+1),
				centered = true,
				priority = 5.1,
			}
			local textPreset = "<color 0xF8D870>HIGH SCORE: </color>" .. "\n" .. stats.highScore .."/" .. stats.requirement
			if rankSystem.timer.enabled then
				textPreset = "<color 0xF8D870>BEST TIME: </color>".. formatTime(stats.bestTime) .. "<color 0xF8D870>\nHIGH SCORE: </color>" .. stats.highScore .."/" .. stats.requirement
			end
			tplus.print{
				font = rankSystem.rankFont, 
				text = textPreset,
				x = centerX - 328,
				y = 548,
				xscale = 2, yscale = 2,
				pivot = vector(0,0),
				priority = 7,
			}
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------

return rankSystem