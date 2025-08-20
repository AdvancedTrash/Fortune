local blockID = BLOCK_ID

local luigiBlock = {}

function luigiBlock.onInitAPI()
    registerEvent(luigiBlock, "onBlockHit")
end

function luigiBlock.onBlockHit(eventToken, b, fromUpper, player)
    if b.id == blockID and not fromUpper then
        SFX.play("LuigiBlock.wav")
    end
end

return luigiBlock