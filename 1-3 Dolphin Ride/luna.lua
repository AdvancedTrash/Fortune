local minTimer = require("minTimer")
local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")
local timer1 = minTimer.create{initValue = minTimer.toTicks{hrs = 0, mins = 0, secs = 25}, x = 150, y = 552}
local timer2 = minTimer.create{initValue = minTimer.toTicks{hrs = 0, mins = 0, secs = 30}, x = 64, y = 552, dontHandleFail = true}
local emergencyClose = false
local LuigiGame = Graphics.loadImage("LuigiGame.png") 
local myOpacity = 0
local myOpacityChange = -0.05

--Dolphin Mini-Game
--Scoring for Mini Game at end
local levelName = Level.filename()
local data = SaveData.checklist[levelName]
local currentScore = 0
local highScore = data.miniGameHighScore or 0
local timerChallengeOff = timerChallengeOff or true
local luigiChallengeOff = luigiChallengeOff or true
local minigameImgBorder = Graphics.loadImageResolved("../bars/minigameBorder.png")
local imgBack = Graphics.loadImageResolved("../bars/hpBackdrop.png")
local imgDamage = Graphics.loadImageResolved("../bars/hpSliceDamage.png")
local imgDummy = Graphics.loadImageResolved("../bars/hpDummy.png")
local minigameCollectCooldown = 0 
local minigameCollectCooldownTime = 10

--images by color
local imgByName = {
  green = Graphics.loadImageResolved("../bars/hpSlicegreen.png"),
}

local minigamebar = Sprite.bar{
   x = camera.width/2 + 265,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.min(1, math.max(0, currentScore / 10)),
   texture = imgByName.green,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}


function onDraw()
    if luigiChallengeOff == false then
        Graphics.drawImage(LuigiGame, 35, 482, myOpacity)

        textplus.print{
                text = string.format("Luigi Block Challenge 2: Death Dolphin Panic!"),
                font = minFont,
                priority = 5,
                wave = 1,
                pivot = Sprite.align.TOP,
                x = camera.width/2, y = 32,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x66CC66FF) * myOpacity
        }
    end

    if timerChallengeOff == false then
        Graphics.drawImage(imgBack, 400 - imgBack.width/2 + 271, 551, myOpacity)
        minigamebar:draw{color = Color.white .. myOpacity}
        Graphics.drawImage(minigameImgBorder, 400 - minigameImgBorder.width/2 + 280, 547, myOpacity)
        textplus.print{
                text = string.format("Dolphin Challenge: Hit the blocks!"),
                font = minFont,
                priority = 5,
                wave = 1,
                pivot = Sprite.align.TOP,
                x = camera.width/2, y = 32,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x1E90FFFF) * myOpacity
        }

        textplus.print{
                text = string.format("High Score: %d", highScore or 0),
                font = minFont,
                priority = 5,
                x = 142, y = 568,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x98FF98FF) * myOpacity
        }

        textplus.print{
                text = string.format("Score: %d", currentScore or 0),
                font = minFont,
                priority = 5,
                x = 142, y = 552,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0xFFFFFFFF) * myOpacity
        }
    end
end

--[[
    All args for the create function:

    local myTimer = minTimer.create{
        draw = drawFunc,            -- function that draw this timer, OPTIONAL
        onEnd = endFunc,            -- function that runs when the timer reaches 0 or its max value, OPTIONAL
        runWhilePaused = false      -- OPTIONAL
        type = minTimer.COUNT_DOWN, -- OPTIONAL
        initValue = 0,              -- OPTIONAL
        dontHandleFail = false,     -- OPTIONAL
        x = 400,                    -- OPTIONAL
        y = 552,                    -- OPTIONAL
    }
]]

--[[
    Functions that you can call with the timer object:
        timer1:pause()
        timer1:resume()

        timer1:start()
        timer1:close(win, playAnim)
            - win can be minTimer.WIN_CLEAR or minTimer.WIN_FAIL
            - if playAnim is set to false or not specified the ending animation will not take place
]]

local canMove = true -- boolean to stop the player
local moveTimer = 0  -- timer to release the player

local function closeTimer()
    timer1:close(minTimer.WIN_FAIL, false)
    timer2:close(minTimer.WIN_FAIL, false)
    currentScore = 0
    luigiChallengeOff = true
    timerChallengeOff = true
    emergencyClose = true
end

function onPlayerKill(p)
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
        myOpacityChange = -0.05
    end
    if minTimer.activeTimer.id == timer2.id and not emergencyClose then
        closeTimer()
        myOpacityChange = -0.05
    end
    
end

function onWarpEnter(p)
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
        myOpacityChange = -0.05
    end
    if minTimer.activeTimer.id == timer2.id and not emergencyClose then
        closeTimer()
        myOpacityChange = -0.05
    end
end


function onEvent(eventName)
    --Luigi Challenge
    if eventName == "timerStart" and Layer.get("reward").isHidden then
        timer1:start()
        luigiChallengeOff = false
        emergencyClose = false
        myOpacityChange = 0.05
    elseif eventName == "timerEnd" and minTimer.activeTimer.id == timer1.id then
        timer1:close(minTimer.WIN_CLEAR, true)
        Layer.get("reward"):show(true)
        luigiChallengeOff = true
        myOpacityChange = -0.05
        emergencyClose = false
    end
    --Dolphin Challenge
    if eventName == "DolphinChallenge" then
        timer2:start()
        timerChallengeOff = false
        emergencyClose = false
        myOpacityChange = 0.05
        
    elseif eventName == "DolphinChallengeWin" and minTimer.activeTimer.id == timer2.id then
        
        data.miniGameWon = true

        if currentScore > highScore then
            highScore = currentScore
            data.miniGameHighScore = currentScore
        end

        if currentScore >= 10 then
            Layer.get("dolphinStar"):show(true)
            data.miniGameMastered = true
        end

        currentScore = 0
        timer2:close(minTimer.WIN_CLEAR, true)
        timerChallengeOff = true
        myOpacityChange = -0.05
        emergencyClose = false
    end
end                  

function timer1:onEnd(win)
    if not win and not emergencyClose then
        currentScore = 0
        player:kill()
        myOpacityChange = -1
        emergencyClose = false
        timerChallengeOff = true
    end
end                              

-- this part handles player movement --
function onTick()                         -- function that runs every tick when the game isn't paused
    myOpacity = math.clamp(myOpacity + myOpacityChange, 0, 1)
    if not canMove then                   -- check if the player can't move
        moveTimer = moveTimer + 1         -- increment the player-releasing timer
        for k, v in pairs(player.keys) do -- iterate over all the player keys
            player.keys[k] = false        -- set all the keys input to false
        end                               -- close the check
        if moveTimer >= 32 then           -- check if the player can move again
            canMove = true                -- release the player
            moveTimer = 0                 -- reset the player-releasing timer
        end                               -- close the check
    end                                   -- close the check
    minigamebar.value = math.min(1, math.max(0, currentScore / 10))
    if minigameCollectCooldown > 0 then
        minigameCollectCooldown = minigameCollectCooldown - 1
    end
end                                       -- close the function

function onPostBlockHit(block, p)
    if block.id == 88 and timerChallengeOff == false then

        if minigameCollectCooldown > 0 then return end

        currentScore = currentScore + 1
        minigameCollectCooldown = minigameCollectCooldownTime
    end
end


function onStart()
    Defines.npc_throwfriendlytimer = 10
end

