local littleDialogue = require("littleDialogue")

local duelHookInstalled = false

-- wherever you register the answers (same place you already call registerAnswer)
local DUEL_PROMPT_ID = "DuelID1"

littleDialogue.registerAnswer(DUEL_PROMPT_ID, {
  text = "Yes!",
  addText = "<boxStyle ml><speakerName Koopa Card Man>Great—let's begin!",
  chosenFunction = function(box)
      -- close now, then open next frame
      if box and box.close then box:close() end
      Routine.run(function()
          Routine.waitFrames(1)
          OpenBoardForDuel("koopa_card_man")
      end)
  end,
})


littleDialogue.registerAnswer(DUEL_PROMPT_ID, {
    text = "No, I don't wish to duel...",
    addText = "<boxStyle ml><speakerName Koopa Card Man>Maybe next time.",
    chosenFunction = function(box)
        if box and box.close then box:close() end
    end,
})

if not duelHookInstalled then
  duelHookInstalled = true

  -- littleDialogue global callback when a question is answered
  if littleDialogue and littleDialogue.onAnswer then
    littleDialogue.onAnswer(function(questionId, choiceIndex, answer)
      -- Our NPC prompt?
      if questionId ~= DUEL_PROMPT_ID then return end

      -- Normalize the selected text (answer.text comes from your registered answer)
      local txt = (answer and answer.text or ""):lower()

      if txt:find("yes") then
        -- Start the duel with this NPC's deck
        -- (change the key if you name the NPC differently)
        OpenBoardForDuel("koopa_card_man")
      else
        -- Player declined: optionally do nothing or play a sfx
      end
    end)
  end
end


