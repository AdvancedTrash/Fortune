local textplus = require("textplus")
local minTimer = {}

minTimer.leastPriority = 4
minTimer.font = textplus.loadFont("timerFont.ini")
minTimer.activeTimer = {}
minTimer.box = Graphics.loadImageResolved("minTimer/box.png")
minTimer.timerBoxHeight = 32

minTimer.SFX = {
    countDown = {id = SFX.open(Misc.resolveSoundFile("SFX/minigame_countDown")), volume = 1},
    start     = {id = SFX.open(Misc.resolveSoundFile("SFX/minigame_start")),     volume = 1},
    clear     = {id = SFX.open(Misc.resolveSoundFile("SFX/minigame_clear")),     volume = 1},
    fail      = {id = SFX.open(Misc.resolveSoundFile("SFX/minigame_fail")),      volume = 1},
    pause     = {id = 30, volume = 1},
    resume    = {id = 30, volume = 1},
}

minTimer.COUNT_DOWN = 1
minTimer.COUNT_UP = 2

minTimer.ANIM_NONE = 0
minTimer.ANIM_START = 1
minTimer.ANIM_END = 2

minTimer.TIMER_NONE = 0
minTimer.TIMER_OPEN = 1
minTimer.TIMER_CLOSE = 2

minTimer.WIN_CLEAR = true
minTimer.WIN_FAIL = false

local timers = {}
local thisTimer = {}
local timerMT = {__index = thisTimer}

registerEvent(minTimer, "onDraw")

local function SFXPlay(name)
    if minTimer.SFX[name] and minTimer.SFX[name].id then
        local volume = minTimer.SFX[name].volume or 1
        SFX.play(minTimer.SFX[name].id, volume)
    end
end

local function getCorrectWidth(x)
    if math.floor(lunatime.toSeconds(x)) < 60 then
        return 104
    elseif math.floor(lunatime.toSeconds(x)) >= 3600 then
        return 212
    end

    return 158
end

local function getWidth(str, scale)
    scale = scale or 1
    return (#str * 18 * scale) - (2 * scale)
end

local function formatTime(v)
    local x = v.timer
    local fps = Misc.GetEngineTPS()
	local timerFormat = {}

    local hrs     = x / (3600 * fps)
    local mins    = x / (60 * fps) % 60
    local secs    = x / fps % 60
    local minsecs = math.floor((x % fps / fps * 1000)/10)

    if v.type == minTimer.COUNT_DOWN then
        if v.initValue >= (3600 * fps) then
            timerFormat = string.format(
                "%.2d:%.2d:%.2d:%.2d",
                hrs, mins, secs, minsecs
            )
        elseif v.initValue >= (60 * fps) then
            timerFormat = string.format(
                "%.2d:%.2d:%.2d",
                mins, secs, minsecs
            )
        else
            timerFormat = string.format(
                "%.2d:%.2d",
                secs, minsecs
            )
        end
    elseif v.type == minTimer.COUNT_UP then
        timerFormat = string.format(
            "%.2d:%.2d:%.2d:%.2d",
            hrs, mins, secs, minsecs
        )
    end

    return timerFormat
end


-- [[-------------------------------------------------------------------------]] --
-- [[-------------------------- Code by MrDoubleA!! --------------------------]] --
-- [[-------------------------------------------------------------------------]] --
local function addQuadToGlDraw(vertexCoords,textureCoords,x,y,width,height,sourceX,sourceY,sourceWidth,sourceHeight)
    local count = #vertexCoords
    local x1 = x
    local y1 = y
    local x2 = x1 + width
    local y2 = y1 + height
    vertexCoords[count + 1] = x1
    vertexCoords[count + 2] = y1
    vertexCoords[count + 3] = x1
    vertexCoords[count + 4] = y2
    vertexCoords[count + 5] = x2
    vertexCoords[count + 6] = y1
    vertexCoords[count + 7] = x1
    vertexCoords[count + 8] = y2
    vertexCoords[count + 9] = x2
    vertexCoords[count + 10] = y1
    vertexCoords[count + 11] = x2
    vertexCoords[count + 12] = y2
    local x1 = sourceX
    local y1 = sourceY
    local x2 = sourceX + sourceWidth
    local y2 = sourceY + sourceHeight
    textureCoords[count + 1] = x1
    textureCoords[count + 2] = y1
    textureCoords[count + 3] = x1
    textureCoords[count + 4] = y2
    textureCoords[count + 5] = x2
    textureCoords[count + 6] = y1
    textureCoords[count + 7] = x1
    textureCoords[count + 8] = y2
    textureCoords[count + 9] = x2
    textureCoords[count + 10] = y1
    textureCoords[count + 11] = x2
    textureCoords[count + 12] = y2
end

local function drawSegmentedBox(image,x,y,width,height,priority,centered,opacity,scale)
    scale = scale or 1
    opacity = opacity or 1
    width = width * scale
    height = height * scale
    local segmentWidth  = (image.width /3)*scale
    local segmentHeight = (image.height/3)*scale
    local vertexCoords = {}
    local textureCoords = {}
    local segmentCountX = math.max(2,math.ceil(width  / segmentWidth ))
    local segmentCountY = math.max(2,math.ceil(height / segmentHeight))
    local cornerWidth  = math.min(width *0.5,segmentWidth )
    local cornerHeight = math.min(height*0.5,segmentHeight)
    local xMod = 0
    local yMod = 0
    if centered then
        xMod = -math.floor(width/2)
        yMod = -math.floor(height/2)
    end
    x = math.floor(x) + xMod
    y = math.floor(y) + yMod
    for segmentX = 1,segmentCountX do
        for segmentY = 1,segmentCountY do
            local offsetX = 0
            local offsetY = 0
            local thisWidth = segmentWidth
            local thisHeight = segmentHeight
            local thisSourceX = 0
            local thisSourceY = 0
            if segmentX == 1 then
                thisWidth = cornerWidth
            elseif segmentX == segmentCountX then
                thisWidth = cornerWidth
                offsetX = width - thisWidth
                thisSourceX = 1 - thisWidth/scale/image.width
            else
                offsetX = (segmentX-1) * segmentWidth
                thisWidth = math.clamp(segmentWidth,0,width-offsetX-segmentWidth)
                thisSourceX = 1/3
            end
            if segmentY == 1 then
                thisHeight = cornerHeight
            elseif segmentY == segmentCountY then
                thisHeight = cornerHeight
                offsetY = height - thisHeight
                thisSourceY = 1 - thisHeight/scale/image.height
            else
                offsetY = (segmentY-1) * segmentHeight
                thisHeight = math.clamp(segmentHeight,0,height-offsetY-segmentHeight)
                thisSourceY = 1/3
            end
            if thisWidth > 0 and thisHeight > 0 then
                addQuadToGlDraw(vertexCoords,textureCoords,x + offsetX,y + offsetY,thisWidth,thisHeight,thisSourceX,thisSourceY,thisWidth/image.width/scale,thisHeight/image.height/scale)
            end
        end
    end
    Graphics.glDraw{
        texture = image,priority = priority,
        vertexCoords = vertexCoords,textureCoords = textureCoords,
        color = (color or Color.white)..opacity,
    }
end
-- [[-------------------------------------------------------------------------]] --
-- [[-------------------------------------------------------------------------]] --
-- [[-------------------------------------------------------------------------]] --


local function drawTimer(v)
    if v.anim ~= minTimer.ANIM_NONE then
        local offset = 0
        v.countDownTimer = v.countDownTimer + 1
        v.cdScale = math.max(v.cdScale - 0.05, 2)
        v.cdImgScale = math.max(v.cdImgScale - 0.05, 1)

        if v.cdFadeType == 1 then
            v.cdOpacity = math.min(v.cdOpacity + 0.05, 1)
        elseif v.cdFadeType == 2 then
            v.cdOpacity = math.max(v.cdOpacity - 0.05, 0)
        end

        if v.countDownTimer % 32 == 0 then
            if v.anim == minTimer.ANIM_START then
                if v.countDown > 1 then
                    SFXPlay("countDown")
                    v.countDown = v.countDown - 1
                    v.cdScale = 3
                    v.cdImgScale = 2
                elseif not v.showCDText then
                    SFXPlay("start")
                    v.cdScale = 3
                    v.cdImgScale = 2
                    v.cdWidth = 248
                    v.cdHeight = 56
                    v.showCDText = true
                    v.showTimer = true
                    v.timeType = minTimer.TIMER_OPEN
                    v.paused = false
                    Misc.unpause()
                elseif v.showCDText then
                    v.cdFadeType = 2
                end
            elseif v.anim == minTimer.ANIM_END then
                if not v.showCDText then
                    v.showCDText = true
                    v.timeType = minTimer.TIMER_CLOSE
                elseif v.showCDText then
                    v.cdFadeType = 2
                end
            end
        end

        if v.anim == minTimer.ANIM_START then
            if v.cdFadeType == 2 and v.cdOpacity == 0 then
                v.anim = minTimer.ANIM_NONE
            end

            if v.showCDText then
                v.cdText = "Start!"
                offset = 4
            else
                v.cdText = tostring(v.countDown)
                offset = 0
            end
        elseif v.anim == minTimer.ANIM_END then
            offset = 4
        end

        drawSegmentedBox(minTimer.box, 400, 300, v.cdWidth, v.cdHeight,minTimer.leastPriority,true,v.cdOpacity,v.cdImgScale)

        textplus.print{
            x = 400 + v.cdScale + offset, y = 300 + 3, text = v.cdText, font = minTimer.font, xscale = v.cdScale, yscale = v.cdScale,
            pivot = {0.5, 0.5}, priority = minTimer.leastPriority + 0.1, color = Color(v.cdOpacity,v.cdOpacity,v.cdOpacity,v.cdOpacity),
        }
    else
        v.cdFadeType = 1
        v.cdOpacity = 1
    end

    if v.showTimer then
        local width

        if v.type == minTimer.COUNT_DOWN then
            if not width then width = getWidth(formatTime(v), 1) + 20 end

            if not v.dontHandleFail and v.timer <= 0 and v.anim == minTimer.ANIM_NONE then
                v:close(minTimer.WIN_FAIL, true)
            end
        elseif v.type == minTimer.COUNT_UP then
            width = 158
        end

        if v.timeType == minTimer.TIMER_OPEN then
            v.timerOpacity = math.min(v.timerOpacity + 0.025, 1)
            v.timerYOffset = math.max(v.timerYOffset - 1.5, 0)
        elseif v.timeType == minTimer.TIMER_CLOSE then
            v.timerOpacity = math.max(v.timerOpacity - 0.025, 0)
            v.timerYOffset = math.min(v.timerYOffset + 1.5, (minTimer.timerBoxHeight + minTimer.timerBoxHeight/2))

            if v.timerOpacity == 0 and v.timerYOffset == (minTimer.timerBoxHeight + minTimer.timerBoxHeight/2) then
                v.timeType = minTimer.TIMER_NONE
                v.showTimer = false
                minTimer.activeTimer = {}
            end
        end

        drawSegmentedBox(minTimer.box, v.x, v.y + v.timerYOffset + minTimer.timerBoxHeight/2, width, minTimer.timerBoxHeight,minTimer.leastPriority,true,v.timerOpacity)

        textplus.print{
            x = v.x+1, y = v.y - 8 + minTimer.timerBoxHeight/2 + v.timerYOffset, text = tostring(formatTime(v)), font = minTimer.font,
            pivot = {0.5, 0}, priority = minTimer.leastPriority + 0.1, color = Color(v.timerOpacity,v.timerOpacity,v.timerOpacity,v.timerOpacity),
        }
    end
end

local function onEndTimer(v, win)
end

function minTimer.create(args)
    local entry = {
        draw = args.draw or drawTimer,    -- function that draw this timer
        onEnd = args.onEnd or onEndTimer, -- function that runs when the timer reaches 0 or its max value
        runWhilePaused = args.runWhilePaused,
        type = args.type or minTimer.COUNT_DOWN,
        initValue = args.initValue or 0,
        dontHandleFail = args.dontHandleFail,
        x = args.x or 400,
        y = args.y or 600 - ((minTimer.timerBoxHeight + minTimer.timerBoxHeight/2) * (#timers + 1)),
        
        -- don't touch
        alreadyClosed = false,
        timer = 0,
        paused = true,
        anim = minTimer.ANIM_NONE,
        countDownTimer = 0,
        countDown = 3,
        cdOpacity = 0,
        showCDText = false,
        showTimer = false,
        cdWidth = 56,
        cdHeight = 56,
        cdText = tostring(3),
        cdFadeType = 1,
        cdScale = 2,
        cdImgScale = 1,
        timerOpacity = 0,
        timerYOffset = minTimer.timerBoxHeight,
        timeType = minTimer.TIMER_NONE,
        id = #timers + 1,
    }

    table.insert(timers, entry)
    setmetatable(entry, timerMT)
    return entry
end

function thisTimer:start()
    if minTimer.activeTimer and minTimer.activeTimer.id == self.id then return end
    -- reset everything

    if self.type == minTimer.COUNT_DOWN then
        self.timer = self.initValue
    else
        self.timer = 0
    end
    self.alreadyClosed = false
    self.anim = minTimer.ANIM_START
    self.paused = true
    self.countDownTimer = 0
    SFXPlay("countDown")
    self.countDown = 3
    self.cdOpacity = 0
    self.showCDText = false
    self.showTimer = false
    self.cdScale = 3
    self.cdImgScale = 2
    self.cdWidth = 56
    self.cdHeight = 56
    self.cdText = tostring(3)
    self.cdFadeType = 1
    self.timerOpacity = 0
    self.timerYOffset = minTimer.timerBoxHeight
    self.timeType = minTimer.TIMER_NONE
    minTimer.activeTimer = self
    Misc.pause()
end

function thisTimer:close(win, playAnim)
    if self.alreadyClosed then return end
    self.alreadyClosed = true
    self.paused = true

    if win then
        SFXPlay("clear")
    else
        SFXPlay("fail")
    end

    if playAnim then
        if win then
            self.cdText = "Clear!"
            self.cdWidth = 248
        else
            self.cdText = "Fail!"
            self.cdWidth = 212
        end
        self.anim = minTimer.ANIM_END
        self.showCDText = false
        self.cdScale = 3
        self.cdImgScale = 2
        self.cdHeight = 56
        self.cdFadeType = 1
        self.cdOpacity = 1
    else
        self.timeType = minTimer.TIMER_CLOSE
    end

    self:onEnd(win)
end

function thisTimer:pause()
    if self.paused then return end
    SFXPlay("pause")
    self.paused = true
end

function thisTimer:resume()
    if not self.paused then return end
    SFXPlay("resume")
    self.paused = false
end

function thisTimer:addTime(x)
    self.timer = math.max(self.timer + x, 0)
end

function minTimer.onDraw()
    if minTimer.activeTimer.id ~= nil then
        if not minTimer.activeTimer.paused and ((Misc.isPaused() and minTimer.activeTimer.runWhilePaused) or not Misc.isPaused()) then
            if minTimer.activeTimer.type == minTimer.COUNT_DOWN then
                minTimer.activeTimer.timer = math.max(minTimer.activeTimer.timer - 1, 0)
            elseif minTimer.activeTimer.type == minTimer.COUNT_UP then
                minTimer.activeTimer.timer = minTimer.activeTimer.timer + 1
            end
        end

        minTimer.activeTimer:draw()
    end
end

function minTimer.toTicks(arg)
    if type(arg) == "table" then
        arg.hrs  = arg.hrs  or 0
        arg.mins = arg.mins or 5
        arg.secs = arg.secs or 0

        local finalHrs  = arg.hrs  * 3600
        local finalMins = arg.mins * 60
        local finalSeconds = finalHrs + finalMins + arg.secs

        return math.floor(lunatime.toTicks(finalSeconds))
    elseif type(arg) == "number" then
        return math.floor(lunatime.toTicks(arg))
    end

    return arg
end

return minTimer