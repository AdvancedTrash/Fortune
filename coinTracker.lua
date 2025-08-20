local coinTracker = {}

function coinTracker.onInitAPI()
    registerEvent(coinTracker, "onStart")
    registerEvent(coinTracker, "onTick")
end

function coinTracker.onStart()
    if SaveData.customCoins == nil then
        SaveData.customCoins = 0
    end
end

function coinTracker.onTick()
    local currentCoins = mem(0x00B2C5A8, FIELD_WORD)

    if coinTracker.prevCoins and currentCoins > coinTracker.prevCoins then
        local gained = currentCoins - coinTracker.prevCoins
        SaveData.customCoins = SaveData.customCoins + gained
        mem(0x00B2C5A8, FIELD_WORD, 0)
    end

    coinTracker.prevCoins = currentCoins
end

return coinTracker
