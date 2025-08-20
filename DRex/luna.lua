local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")
local timer1 = minTimer.create{initValue = minTimer.toTicks{hrs = 0, mins = 1, secs = 0}, x = 150, y = 552} -- create a timer object
local timer2 = minTimer.create{initValue = minTimer.toTicks{hrs = 0, mins = 0, secs = 20}, x = 64, y = 552, dontHandleFail = true}
local emergencyClose = false
local LuigiGame = Graphics.loadImage("LuigiGame.png") 
local myOpacity = 0
local myOpacityChange = -0.05

function onDraw()
    Graphics.drawImage(LuigiGame, 35, 482, myOpacity)
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
    emergencyClose = true
end

function onPlayerKill(p)
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
    end
    if minTimer.activeTimer.id == timer2.id and not emergencyClose then
        closeTimer()
        Audio.MusicChange(0, "music/OceanPalace.spc", 30)
    end
end

function onWarpEnter(p)
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
    end
    if minTimer.activeTimer.id == timer2.id and not emergencyClose then
        closeTimer()
        Audio.MusicChange(0, "music/OceanPalace.spc", 30)
    end
end

function onEvent(eventName)
    --Luigi Challenge
    if eventName == "timerStart" and Layer.get("reward").isHidden then
        timer1:start()
        emergencyClose = false
        myOpacityChange = 0.05
    elseif eventName == "timerEnd" and minTimer.activeTimer.id == timer1.id then
        timer1:close(minTimer.WIN_CLEAR, true)
        Layer.get("reward"):show(true)
        myOpacityChange = -0.05
        emergencyClose = false
    end
    --Lakitu Challenge
    if eventName == "Water Challenge" then
        timer2:start()
        Audio.MusicChange(0, "music/KnucklesTheme.spc", 120)
        emergencyClose = false
        
    elseif eventName == "Water Challenge Win" and minTimer.activeTimer.id == timer2.id then
        timer2:close(minTimer.WIN_CLEAR, true)
        Audio.MusicChange(0, "music/OceanPalace.spc", 30)
        emergencyClose = false
        
    end
end                  

function timer1:onEnd(win)
    if not win and not emergencyClose then
        player:kill()
        myOpacityChange = -1
        emergencyClose = false
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
end                                       -- close the function


function onStart()
    Defines.npc_throwfriendlytimer = 10
end