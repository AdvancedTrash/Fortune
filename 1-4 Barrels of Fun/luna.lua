local minTimer = require("minTimer")
local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")
local timer1 = minTimer.create{initValue = minTimer.toTicks{hrs = 0, mins = 0, secs = 30}, x = 150, y = 552, dontHandleFail = true}
local emergencyClose = false
local LuigiGame = Graphics.loadImage("LuigiGame.png")
local myOpacity = 0
local myOpacityChange = -0.05
local respawnRooms = require("respawnRooms")
local registeredNPCs = {}
local sameSectionCount = {}
local timerChallengeOff = timerChallengeOff or true
local luigiChallengeOff = luigiChallengeOff or true
local bossChallengeOff = luigiChallengeOff or true
local slm = require("simpleLayerMovement")

--DK Barrels
slm.addLayer{name = "dkbarrel1",speed = 132,verticalMovement = slm.MOVEMENT_COSINE,verticalSpeed = 112,verticalDistance = 1.0}
slm.addLayer{name = "dkbarrel2",speed = 96,verticalMovement = slm.MOVEMENT_COSINE,verticalSpeed = 78,verticalDistance = -1.5}
slm.addLayer{name = "dkbarrel3",speed = 128,horizontalMovement = slm.MOVEMENT_COSINE,horizontalSpeed = 78,horizontalDistance = 2.0}

--Barrel Blast
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

--Boss Template by AdvancedTrash
local bossName = "Queen B" -- For name draw
local barMax = 15 -- This is how much HP is on one bar (damage 3 for all but fireball)
local bossMaxHP = bossMaxHP or 12 -- Set in NPC Creator too, couldn't pull the HP data directly for some reason
local bossCurrentHP = bossCurrentHP or 12 -- Set in NPC Creator too, couldn't pull the HP data directly for some reason
local BOSS_ID = 898 -- This will be the boss that is drawn, later we may want to do a table
local bossImmuneNPC = {[416] = true} -- NPC Creator was hurting itself in the bar display
local damageAll = 3 -- All damage except fireball
local damageFireball = 3 -- Fireball damage
local bossHurtCooldown = 0
local bossHurtCooldownTime = 20 

--Set bars
local greenHP = 0 
local yellowHP = 0 
local orangeHP = 0
local redHP = 0
local purpleHP = 0

--Load images
local imgBorder = Graphics.loadImageResolved("../bars/hpBorder.png")
local imgBack = Graphics.loadImageResolved("../bars/hpBackdrop.png")
local imgDamage = Graphics.loadImageResolved("../bars/hpSliceDamage.png")
local imgDummy = Graphics.loadImageResolved("../bars/hpDummy.png")

--images by color
local imgByName = {
  green = Graphics.loadImageResolved("../bars/hpSlicegreen.png"),
  yellow = Graphics.loadImageResolved("../bars/hpSliceyellow.png"),
  orange = Graphics.loadImageResolved("../bars/hpSliceorange.png"),
  red = Graphics.loadImageResolved("../bars/hpSliceRed.png"),
  purple = Graphics.loadImageResolved("../bars/hpSlicePurple.png"),
}

--draw all bars
local minigamebar = Sprite.bar{
   x = camera.width/2 + 265,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.min(1, math.max(0, currentScore / 60)),
   texture = imgByName.green,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

local greenHPbar = Sprite.bar{
   x = camera.width/2 - 15,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.max(0, greenHP / barMax),
   texture = imgByName.green,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

local yellowHPbar = Sprite.bar{
   x = camera.width/2 - 15,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.max(0, yellowHP / barMax),
   texture = imgByName.yellow,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

local orangeHPbar = Sprite.bar{
   x = camera.width/2 - 15,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.max(0, orangeHP / barMax),
   texture = imgByName.orange,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

local redHPbar = Sprite.bar{
   x = camera.width/2 - 15,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.max(0, redHP / barMax),
   texture = imgByName.red,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

local purpleHPbar = Sprite.bar{
   x = camera.width/2 - 15,
   y = 552,
   width = 178,
   height = 12,
   pivot = Sprite.align.TOP,
   value = math.max(0, purpleHP / barMax),
   texture = imgByName.purple,
   trailspeed = 1,
   trailtexture = imgDamage,
   bgtexture = imgDummy,
   borderwidth = 0
}

--this helps the bars with the total HP remaining
local function redistributeBarsFrom(totalHP)
    local remaining = math.max(0, math.min(totalHP, bossMaxHP))

    greenHP  = math.min(barMax, remaining);          remaining = remaining - greenHP
    yellowHP = math.min(barMax, math.max(0, remaining)); remaining = remaining - yellowHP
    orangeHP = math.min(barMax, math.max(0, remaining)); remaining = remaining - orangeHP
    redHP    = math.min(barMax, math.max(0, remaining)); remaining = remaining - redHP
    purpleHP = math.min(barMax, math.max(0, remaining))

    greenHPbar.value  = greenHP  / barMax
    yellowHPbar.value = yellowHP / barMax
    orangeHPbar.value = orangeHP / barMax
    redHPbar.value    = redHP    / barMax
    purpleHPbar.value = purpleHP / barMax
end

--run the HP distribution 
redistributeBarsFrom(bossCurrentHP)

function onDraw()
    if luigiChallengeOff == false then
        Graphics.drawImage(LuigiGame, 35, 482, myOpacity)
        minigamebar:draw{color = Color.white .. myOpacity}
        Graphics.drawImage(minigameImgBorder, 400 - minigameImgBorder.width/2 + 280, 547, myOpacity)
        textplus.print{
                text = string.format("Luigi Block Challenge 4: Barrel Blast!"),
                font = minFont,
                priority = 5,
                wave = 1,
                pivot = Sprite.align.TOP,
                x = camera.width/2, y = 32,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x66CC66FF) * myOpacity
        }

        textplus.print{
                text = string.format("High Score: %d", highScore or 0),
                font = minFont,
                priority = 5,
                x = 216, y = 568,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x98FF98FF) * myOpacity
        }

        textplus.print{
                text = string.format("Score: %d", currentScore or 0),
                font = minFont,
                priority = 5,
                x = 216, y = 552,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0xFFFFFFFF) * myOpacity
        }
    end
    
    --boss draws with boolean (triggered by resizable collectable using event "boss")
    if bossChallengeOff == false then
        Graphics.drawImage(imgBack, 400 - imgBack.width/2 - 9, 551, myOpacity)
        greenHPbar:draw{color = Color.white .. myOpacity}
        yellowHPbar:draw{color = Color.white .. myOpacity}
        orangeHPbar:draw{color = Color.white .. myOpacity}
        redHPbar:draw{color = Color.white .. myOpacity}
        purpleHPbar:draw{color = Color.white .. myOpacity}
        Graphics.drawImage(imgBorder, 400 - imgBorder.width/2, 547, myOpacity)
        textplus.print{
                text = string.format(bossName),
                font = minFont,
                priority = 5,
                pivot = Sprite.align.TOP,
                x = camera.width/2, y = 531,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0xFFFFFFFF) * myOpacity
        }    
    end

    --[[if timerChallengeOff == false then

        textplus.print{
                text = string.format("No mini game here!"),
                font = minFont,
                priority = 5,
                wave = 1,
                pivot = Sprite.align.TOP,
                x = camera.width/2, y = 32,
                xscale = 2, yscale = 2,
                color = Color.fromHexRGBA(0x1E90FFFF) * myOpacity
        }
    end]]
end

local canMove = true
local moveTimer = 0

local function closeTimer()
    timer1:close(minTimer.WIN_FAIL, false)
    luigiChallengeOff = true
    emergencyClose = true
end

function onPlayerKill(p)
    currentScore = 0
    bossChallengeOff = true
    bossCurrentHP = bossMaxHP
    redistributeBarsFrom(bossCurrentHP)
    myOpacityChange = -1
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
    end
end

function onWarpEnter(p)
    if minTimer.activeTimer.id == timer1.id and not emergencyClose then
        closeTimer()
    end
end

function onEvent(eventName)
    if eventName == "minigameStart" and Layer.get("minigameMastery").isHidden then
        timer1:start()
        Layer.get("minigame"):show(false)
        Audio.MusicChange(3, "music/16a Token Tango.spc", 30)
        luigiChallengeOff = false
        emergencyClose = false
        myOpacityChange = 0.05
    elseif eventName == "minigameStop" and minTimer.activeTimer.id == timer1.id then
        
        luigiChallengeOff = true
        data.miniGameWon = true

        if currentScore > highScore then
            highScore = currentScore
            data.miniGameHighScore = currentScore
        end

        if currentScore >= 50 then
            Layer.get("minigameMastery"):show(false)
            data.miniGameMastered = true
        end

        timer1:close(minTimer.WIN_CLEAR, true)
        Audio.MusicChange(3, "music/Final Fantasy VII - Cait Sith's Theme.spc", 30)
        currentScore = 0
        myOpacityChange = -0.05
        emergencyClose = false
    end

    if eventName == "boss" then
        bossChallengeOff = false
        myOpacityChange = 0.05
    elseif eventName == "BossWin" then
        Audio.MusicChange(1, "music/17 Stickerbrush Symphony.spc", 30)
        myOpacityChange = -0.05
    end

end

function timer1:onEnd(win)
    if not win and not emergencyClose then
        player:kill()
        luigiChallengeOff = true
        emergencyClose = false
    end
end

function onStart()
    Defines.npc_throwfriendlytimer = 10
end

function onTick()
    myOpacity = math.clamp(myOpacity + myOpacityChange, 0, 1)
    if bossHurtCooldown > 0 then
        bossHurtCooldown = bossHurtCooldown - 1
    end
    if myOpacity <= 0 and bossCurrentHP <= 0 then
        bossChallengeOff = true
    end
    if not canMove then
        moveTimer = moveTimer + 1
        for k, v in pairs(player.keys) do
            player.keys[k] = false
        end
        if moveTimer >= 32 then
            canMove = true
            moveTimer = 0
        end
    end
    minigamebar.value = math.min(1, math.max(0, currentScore / 60))
end

local STATE = {
	FLYING = 0,
	SUMMON = 1,
	SPIKE = 2,
	HURT = 3,
	KILL = 4,
}

local function applyBossDamage(dmg)
    local boss = NPC.get(BOSS_ID)[1]
    if not boss or not boss.isValid then return end
    if boss.data.invincible or (boss.data.state == STATE.HURT and boss.data.timer >= 2) then return end 

    bossCurrentHP = math.max(0, bossCurrentHP - dmg)
    redistributeBarsFrom(bossCurrentHP)

    if bossCurrentHP <= 0 then
        myOpacityChange = -0.05
        triggerEvent("BossWin")
    end
end

function onPostNPCCollect(npc,p)
    if luigiChallengeOff == true then return end
    if npc.id ~= 33 and npc.id ~= 258 then return end

    if npc.id == 33 then
        currentScore = currentScore + 1
    elseif npc.id == 258 then
        currentScore = currentScore + 5
    end
end

function onNPCHarm(eventObj, v, reason, culprit)
    if not (v and v.id == BOSS_ID) or bossChallengeOff then
        return
    end

     if bossHurtCooldown > 0 then return end
     
    local dmg = 0

    if culprit and culprit.__type == "NPC" then
        if bossImmuneNPC[culprit.id] then
            dmg = 0
        else
            dmg = damageAll
        end
    else
        dmg = damageAll
    end

    if dmg > 0 then
        applyBossDamage(dmg)
        bossHurtCooldown = bossHurtCooldownTime
    end
end