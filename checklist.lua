local checklist = {}

SaveData.checklist = SaveData.checklist or {}

function checklist.registerLevel(levelName, luigiCoinInLevel, starInLevel, miniGameInLevel)
    if SaveData.checklist[levelName] then
        local level = SaveData.checklist[levelName]
        level.luigiCoinInLevel = luigiCoinInLevel
        level.starInLevel = starInLevel
        level.miniGameInLevel = miniGameInLevel
        return
    end

    SaveData.checklist[levelName] = {
        luigiCoinInLevel = luigiCoinInLevel,
        starInLevel = starInLevel,
        miniGameWon = false,
        miniGameHighScore = miniGameHighScore,
        miniGameInLevel = miniGameInLevel,
        miniGameMastered = false,
        luigiCollected = false,
        starCollected = false

    }
end

local levels2 = {
	{"1-1 Adventure Away.lvlx",true,true,false}, -- Adventure Away
	{"1-2 Cavern Depths.lvlx",false,true,true}, -- Cavern Depths
    {"1-3 Dolphin Ride.lvlx",true,false,true}, -- Dolphin Ride
	{"1-C The Koopa Kastle.lvlx",true,true,false}, -- Koopa Kastle
    {"1-B8 Kore (Hard Mode).lvlx",true,false,false} -- Bonus 8: Kore Hard Mode
	
}

for i = 1, #levels2 do
	checklist.registerLevel(
		levels2[i][1], -- registers the levelname per level
		levels2[i][2], -- boolean for if Luigi Coin exists
		levels2[i][3], -- boolean for if Star exists
        levels2[i][4], -- boolean for if Mini Game is in level
        levels2[i][5] -- register the high score
    )
end

function checklist.getLuigiCoinTotal()
    local total = 0
    if SaveData.checklist then
        for _, data in pairs(SaveData.checklist) do
            if data.luigiCollected then
                total = total + 1
            end
        end
    end
    return total
end

function checklist.getStarTotal()
    local total = 0
    if SaveData.checklist then
        for _, data in pairs(SaveData.checklist) do
            if data.starCollected then
                total = total + 1
            end
        end
    end
    return total
end

function checklist.luigiCoinCollectCheck()
    local levelName = Level.filename()
    local data = SaveData.checklist[levelName]

    if data and data.luigiCoinInLevel and not data.luigiCollected then
        data.luigiCollected = true
    end
end

function checklist.collectStar()
    local levelName = Level.filename()
    local data = SaveData.checklist[levelName]

    if data and data.starInLevel and not data.starCollected then
        data.starCollected = true
    end
end

return checklist