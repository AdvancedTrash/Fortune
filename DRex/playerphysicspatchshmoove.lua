-- SHMOOVE CONFIGURATION
--- No aerial idle deceleration
--- Uncapped speed
--- Fucked up on slopes!!!! SOMEONE HELP ME!!! OH NO!!!

local lastXSpeed = {}
local ppp = {}

ppp.speedXDecelerationModifier = 0.08
ppp.groundTouchingDecelerationMultiplier = 1
ppp.groundNotTouchingDecelerationMultiplier = 2

ppp.accelerationMaxSpeedThereshold = 2
ppp.accelerationMinSpeedThereshold = 0.1
ppp.accelerationSpeedDifferenceThereshold = 0.2
ppp.accelerationMultiplier = 1.5

ppp.aerialIdleDeceleration = 1

ppp.enabled = true

local RUNSPEED = 6
local WALKSPEED = 3

local pSpeedTimer = 0

function ppp.onInitAPI()
    registerEvent(ppp, "onTick")
    registerEvent(ppp, "onTickEnd")
end

function ppp.setWalkSpeed(spd)
    WALKSPEED = spd or 3
end

function ppp.setRunSpeed(spd)
    RUNSPEED = spd or 6
end

function ppp.onTickEnd()
    Defines.player_walkspeed = 16
    Defines.player_runspeed = 16
    local maxspeed = WALKSPEED
    if player.keys.run then maxspeed = RUNSPEED end
    if player.hasStarman then
        maxspeed = maxspeed + 2.5
    end
    local sliding = false
    if player:mem(0x3C, FIELD_BOOL) then
        sliding = true
    end
    if sliding then
        sliding = false
        local slopeIdx = player:mem(0x48, FIELD_WORD)
        if player.speedY > 0 and slopeIdx > 0 then
            local b = Block(slopeIdx)
            if Block.config[b.id].floorslope ~= 0 then
                player.speedX = player.speedX + 0.1 * Block.config[b.id].floorslope
                sliding = true
            end
        end
    end
    if not sliding then
        local decrease = 0.15
        if not player:isOnGround() and not player.keys.left and not player.keys.right then
            decrease = 0
        end
        if player.speedX > maxspeed then
            player.speedX = math.max(player.speedX - decrease, maxspeed)
        elseif player.speedX < -maxspeed then
            player.speedX = math.min(player.speedX + decrease, -maxspeed)
        end
    end

    if math.abs(player.speedX) >= RUNSPEED then
        if math.abs(player.speedX) >= RUNSPEED + 1 and player:isOnGround() then
            pSpeedTimer = pSpeedTimer + 1
        else
            pSpeedTimer = pSpeedTimer - 3
        end
    else
        pSpeedTimer = pSpeedTimer - 3
    end
    pSpeedTimer = math.max(pSpeedTimer, 0)
    player:mem(0x168, FIELD_FLOAT, pSpeedTimer)
end

function ppp.onTick()-- (deceleration tightness)
    if ppp.enabled and player.forcedState == 0 then
        for k,p in ipairs(Player.get()) do
            lastXSpeed[k] = lastXSpeed[k] or 0
            if not player:mem(0x3C, FIELD_BOOL) then
                if (not (p:isGroundTouching() and p:mem(0x12E, FIELD_BOOL))) then
                    local mod = ppp.groundTouchingDecelerationMultiplier
                    if (not p:isGroundTouching()) then
                        mod = ppp.groundNotTouchingDecelerationMultiplier
                    end
                    if p.rightKeyPressing then
                        if p.speedX < 0 then
                            p.speedX = p.speedX + ppp.speedXDecelerationModifier * mod;
                        end
                    elseif p.leftKeyPressing then
                        if  p.speedX > 0 then
                            p.speedX = p.speedX - ppp.speedXDecelerationModifier * mod;
                        end
                    else
                        p.speedX = p.speedX * ppp.aerialIdleDeceleration;	
                    end
                end
            
            -- (acceleration tightness)
                local xspeeddiff = p.speedX - lastXSpeed[k]

                if math.abs(p.speedX) < ppp.accelerationMaxSpeedThereshold and math.abs(p.speedX) > ppp.accelerationMinSpeedThereshold and math.sign(p.speedX * xspeeddiff) == 1 and math.abs(xspeeddiff) <= ppp.accelerationSpeedDifferenceThereshold then
                    p.speedX = p.speedX - xspeeddiff
                    p.speedX = p.speedX + xspeeddiff * ppp.accelerationMultiplier
                end

            end
            lastXSpeed[k] = p.speedX
        end
    end
end

return ppp