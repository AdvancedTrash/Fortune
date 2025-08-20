--[[

    smwMap.lua
    by MrDoubleA

    See main file for more
	
	Auto-clearing and Lockable Crossroad by SpoonyBardOL

]]

local smwMap = require("smwMap")
local checklist = require("checklist")
local textplus = require("textplus")
local font = textplus.loadFont("minFont.ini")
local starcoin = require("npcs/AI/starcoin")
local QUAKE_INTENSITY = 8


local bor = bit.bor
local npcID = NPC_ID
local crossroadAI = {}

local boxExpandX = 1
local boxExpandY = 1
local starShift = 0
local framesOffset = 0

SaveData.smwMap = SaveData.smwMap or {}
local saveData = SaveData.smwMap

saveData.crossUnlock = saveData.crossUnlock or {}
saveData.crossPathDone = saveData.crossPathDone or {}
saveData.crossRoadFrame = saveData.crossRoadFrame or {}
local unlockFailMessageShown = {}

local directionToWeight = {
	["up"]    = 8,
	["right"] = 4,
	["down"]  = 2,
	["left"]  = 1,
}
local frameOffset = {
	[0] = 0,
	[1] = 17,
	[2] = 34,
	[3] = 51,
}

local npcIDs = {}

function crossroadAI.register(id)
	npcIDs[id] = true
end

function crossroadAI.crossroad_smwMap(v)
	if frameSet == nil then
		frameSet = 0
	end
	local pathType = v.settings.pathType
	if not saveData.crossRoadFrame[v.settings.roadTitle] then
		saveData.crossRoadFrame[v.settings.roadTitle] = 0
	end
	if saveData.crossUnlock[v.settings.roadTitle] then
		v.settings.locked = false
	end
	v.settings.levelFilename = ""
	if v.settings.locked then
		frameSet = 16
	else
		frameSet = saveData.crossRoadFrame[v.settings.roadTitle]
	end

	for _,dirName in ipairs{"up","right","down","left"} do
		if smwMap.pathIsUnlocked(v.settings["path_".. dirName]) then
			saveData.crossRoadFrame[v.settings.roadTitle] = bor(saveData.crossRoadFrame[v.settings.roadTitle], directionToWeight[dirName])
		end
	end
	framesOffset = frameOffset[pathType]
	if v.lockedFade == 0 and not v.settings.locked and not saveData.crossPathDone[v.settings.roadTitle] then
		for _,directionName in ipairs{"up","right","down","left"} do
			local unlockType = (v.settings["unlock_".. directionName])
			if unlockType == true then
				smwMap.unlockPath(v.settings["path_".. directionName],v)
			end
		end
		saveData.crossUnlock[v.settings.roadTitle] = true
		v.settings.locked = false
		v.lockedFade = 0
	end
	if v == smwMap.mainPlayer.levelObj and pathType > 1 and v.lockedFade == 0 then
		smwMap.mainPlayer.isUnderwater = true
	end
	if v == smwMap.mainPlayer.levelObj and smwMap.mainPlayer.state == smwMap.PLAYER_STATE.NORMAL and (v.settings.locked and not saveData.crossUnlock[v.settings.roadTitle]) then
		
        local coinIcon = Graphics.loadImageResolved("hardcoded-33-2.png")
        local starIcon = Graphics.loadImageResolved("hardcoded-33-5.png")
        local sCoinIcon = Graphics.loadImageResolved("dragonCoinCollect.png")
        local lCoinIcon = Graphics.loadImageResolved("luigicoin.png")

        local lineCount = 0

        if v.settings.coins > 0 then
    Graphics.drawImageWP(coinIcon, v.x + 38 - smwMap.camera.x, v.y + 60 + (lineCount * 20) - smwMap.camera.y, -1)
    textplus.print{
        text = "x"..v.settings.coins,
        x = v.x + 54 - smwMap.camera.x,
        y = v.y + 60 + (lineCount * 20) - smwMap.camera.y,
        xscale = 2, yscale = 2,
        font = font,
        priority = 5,
        color = Color.white,
    }
    lineCount = lineCount + 1
end

        if v.settings.starCoins > 0 then
            Graphics.drawImageWP(sCoinIcon, v.x + 38 - smwMap.camera.x, v.y + 60 + (lineCount * 20) - smwMap.camera.y, -1)
            textplus.print{
                text = "x"..v.settings.starCoins,
                x = v.x + 54 - smwMap.camera.x,
                y = v.y + 60 + (lineCount * 20) - smwMap.camera.y,
                xscale = 2, yscale = 2,
                font = font,
                priority = 5,
                color = Color.white,
            }
            lineCount = lineCount + 1
        end

        if v.settings.luigiCoins > 0 then
            Graphics.drawImageWP(lCoinIcon, v.x + 38 - smwMap.camera.x, v.y + 60 + (lineCount * 20) - smwMap.camera.y, -1)
            textplus.print{
                text = "x"..v.settings.luigiCoins,
                x = v.x + 54 - smwMap.camera.x,
                y = v.y + 60 + (lineCount * 20) - smwMap.camera.y,
                xscale = 2, yscale = 2,
                font = font,
                priority = 5,
                color = Color.white,
            }
            lineCount = lineCount + 1
        end

        if v.settings.stars > 0 then
            Graphics.drawImageWP(starIcon, v.x + 38 - smwMap.camera.x, v.y + 60 + (lineCount * 20) - smwMap.camera.y, -1)
            textplus.print{
                text = "x"..v.settings.stars,
                x = v.x + 54 - smwMap.camera.x,
                y = v.y + 60 + (lineCount * 20) - smwMap.camera.y,
                xscale = 2, yscale = 2,
                font = font,
                priority = 5,
                color = Color.white,
            }
            lineCount = lineCount + 1
        end

        local inputPress = player.keys.run or player.keys.jump

        local haveCoins       = (SaveData.customCoins or 0) >= (v.settings.coins or 0)
        local haveStarCoins   = starcoin.getEpisodeCollected() >= (v.settings.starCoins or 0)
        local haveLuigiCoins = checklist.getLuigiCoinTotal() >= (v.settings.luigiCoins or 0)
        local haveStars = mem(0x00B251E0,FIELD_WORD) >= (v.settings.stars or 0)
        local allRequirements = haveCoins and haveStarCoins and haveLuigiCoins and haveStars

        if inputPress and not saveData.crossUnlock[v.settings.roadTitle] then
            if allRequirements then
                Defines.earthquake = math.max(Defines.earthquake, QUAKE_INTENSITY)
                Effect.spawn(10, v)
                if not v.settings.dontRemoveItems then
                    SaveData.customCoins = SaveData.customCoins - (v.settings.coins or 0)
                end

                SFX.play(smwMap.playerSettings.levelDestroyedSound)

                if smwMap.levelDestroyedSmokeEffectID ~= nil then
                    local directionList = {
                        {x = -1, y = -1},
                        {x =  1, y = -1},
                        {x = -1, y =  1},
                        {x =  1, y =  1},
                    }

                    for index, dir in ipairs(directionList) do
                        local smoke = smwMap.createObject(smwMap.levelDestroyedSmokeEffectID, v.x, v.y)
                        smoke.data.directionX = dir.x
                        smoke.data.directionY = dir.y
                        smoke.frameX = index - 1
                    end
                end

                saveData.crossUnlock[v.settings.roadTitle] = true
            else
                if v.unlockMessageTimer == nil then
                    v.unlockMessageTimer = 90
                    SFX.play(38)
                end

                if v.unlockMessageTimer and v.unlockMessageTimer > 0 then
                    textplus.print{
                        text = "You don't have enough!",
                        x = 225,
                        y = 135,
                        xscale = 2, yscale = 2,
                        priority = 6,
                        font = textplus.loadFont("minFont.ini"),
                        color = Color.white
                    }
                    v.unlockMessageTimer = v.unlockMessageTimer - 1
                else
                    v.unlockMessageTimer = nil
                end
            end
        end
    end

	v.frameY = frameSet + framesOffset
end

return crossroadAI
