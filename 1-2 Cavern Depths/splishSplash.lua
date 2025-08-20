local splishSplash = {}

splishSplash.waterID = 1000
splishSplash.quicksandID = 999

splishSplash.waterSFX = Misc.resolveFile("splort.ogg")
splishSplash.quicksandSFX = Misc.resolveFile("quicksplash.ogg")

splishSplash.quicksandSplash = true
splishSplash.npcSplash = true

local SPLASH_STATE = {
    AIR = 0,
    WATER = 1,
    SCHRODINGER = 2,
}

local function getNewSplashState(p)
    if p.forcedState ~= FORCEDSTATE_NONE or p.deathTimer > 0 then
        return SPLASH_STATE.SCHRODINGER
    end

    if p:mem(0x34,FIELD_WORD) > 0 then
        return SPLASH_STATE.WATER
    else
        return SPLASH_STATE.AIR
    end
end

function splishSplash.onStart() -- initializing of player.data values
    for _,p in ipairs(Player.get()) do
	p.data.splishSplash = {}
	local pData = p.data.splishSplash
		
	pData.splashState = SPLASH_STATE.SCHRODINGER
	pData.newSplashState = SPLASH_STATE.SCHRODINGER
	pData.currentBox = nil
    end
end

function splishSplash.onTick()
    for _,p in ipairs(Player.get()) do
        local pData = p.data.splishSplash

        pData.newSplashState = getNewSplashState(p)

        for k, l in ipairs(Liquid.getIntersecting(p.x,p.y,p.x+p.width,p.y+p.height)) do 
            pData.currentBox = l
        end

        if pData.newSplashState ~= pData.splashState then
            if pData.newSplashState ~= SPLASH_STATE.SCHRODINGER and pData.splashState ~= SPLASH_STATE.SCHRODINGER then
                if pData.currentBox ~= nil then
                    if (table.maxn(Player.getIntersecting(pData.currentBox.x, pData.currentBox.y-16, pData.currentBox.x+pData.currentBox.width, pData.currentBox.y+16)) > 0) then
                        if not pData.currentBox.isQuicksand then
                            local e = Effect.spawn(splishSplash.waterID,p.x + p.width*0.5,pData.currentBox.y)

                            e.x = e.x - e.width*0.5
                            e.y = e.y - e.height

                            if splishSplash.waterSFX then SFX.play(splishSplash.waterSFX) end
                        elseif splishSplash.quicksandSplash then
                            local e = Effect.spawn(splishSplash.quicksandID,p.x + p.width*0.5,pData.currentBox.y)

                            e.x = e.x - e.width*0.5
                            e.y = e.y - e.height

                            if splishSplash.quicksandSFX then SFX.play(splishSplash.quicksandSFX) end
                        end
                    end
                end
            end
            pData.splashState = pData.newSplashState
        end
    end

    -- NPC support

    if not splishSplash.npcSplash then return end

    for _,v in NPC.iterate() do
        local data = v.data
        if not data.int then
            data.splashState = SPLASH_STATE.SCHRODINGER
            data.newSplashState = nil
            data.box = nil
            data.theFunnySplashingTimer = 0
            data.int = true
        end
        data.theFunnySplashingTimer = data.theFunnySplashingTimer + 1
        for k, m in ipairs(Liquid.getIntersecting(v.x,v.y,v.x+v.width,v.y+v.height)) do 
            data.box = m
        end
        if v.forcedState ~= 0 then
            data.newSplashState = SPLASH_STATE.SCHRODINGER
        end

        if v.underwater then
            data.newSplashState = SPLASH_STATE.WATER
        else
            data.newSplashState = SPLASH_STATE.AIR
        end
        if data.newSplashState ~= data.splashState then
            if data.newSplashState ~= SPLASH_STATE.SCHRODINGER and data.splashState ~= SPLASH_STATE.SCHRODINGER then
                if data.box ~= nil and data.theFunnySplashingTimer >= 8 then
                    if (#NPC.getIntersecting(data.box.x, data.box.y-16, data.box.x+data.box.width, data.box.y+16) > 0) and v.y <= v.sectionObj.boundary.bottom then
                        if not data.box.isQuicksand then
                            local e = Effect.spawn(splishSplash.waterID,v.x + v.width*0.5,data.box.y)

                            e.x = e.x - e.width*0.5
                            e.y = e.y - e.height

                            if splishSplash.waterSFX then SFX.play(splishSplash.waterSFX) end
                        elseif splishSplash.quicksandSplash then
                            local e = Effect.spawn(splishSplash.quicksandID,v.x + v.width*0.5,data.box.y)

                            e.x = e.x - e.width*0.5
                            e.y = e.y - e.height

                            if splishSplash.quicksandSFX then SFX.play(splishSplash.quicksandSFX) end
                        end
                    end
                end
            end

            data.splashState = data.newSplashState
        end
    end
end

function splishSplash.onInitAPI()
    registerEvent(splishSplash,"onStart")
    registerEvent(splishSplash,"onTick")
end

return splishSplash