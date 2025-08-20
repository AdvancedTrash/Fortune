if SaveData.timerStuff == nil then
    SaveData.timerStuff = {}
end

local savedata = SaveData.timerStuff

local DEFAULT_TIME = 300
local SCORE_DEDUCTION = 1000
local QUAKE_INTENSITY = 8

local levelName = Level.filename()

local function timerOnEnd()
    Timer.activate(DEFAULT_TIME)
    SFX.play(38)
    Misc.score(-SCORE_DEDUCTION)
    Defines.earthquake = math.max(Defines.earthquake, QUAKE_INTENSITY)
end

function onStart()
    if savedata.levelName ~= levelName then
        Timer.activate(DEFAULT_TIME)

        savedata.levelName = levelName
        savedata.storedTime = nil
    else
        Timer.activate(savedata.storedTime or DEFAULT_TIME)
    end
end

function onPlayerKill(e, p)
    local value = Timer.getValue()

    if value <= 0 then
        value = DEFAULT_TIME
        timerOnEnd()
    end

    savedata.storedTime = value
    Timer.setActive(false)
end

function Timer.onEnd()
    timerOnEnd()
end