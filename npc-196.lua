local checklist = require("checklist")

local smwStarHandler = {}

function smwStarHandler.onPostNPCCollect(npc, player)
    if npc.id == 196 then
        checklist.collectStar()
        -- Optional: Play sound effect
        SFX.play("StarCollect.wav")
    end
end

registerEvent(smwStarHandler, "onPostNPCCollect")

return smwStarHandler