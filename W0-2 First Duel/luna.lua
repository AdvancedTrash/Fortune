local littleDialogue = require("littleDialogue")
local cutscenePal = require("cutscenePal")
local animationPal = require("animationPal")
local textplus = require("textplus")
local handycam = require("handycam")
local easing = require("ext/easing")
local cardGameFortune = require("cardGameFortune")
local minFont = textplus.loadFont("minFont.ini")

-- =============================
-- Fortune Duel Intro (Cutscene)
-- =============================
local fortuneIntro = cutscenePal.newScene("fortune_battle_intro")
fortuneIntro.canSkip = true     -- user can skip with Drop/Select
fortuneIntro.hasBars = true     -- cinematic bars

-- configurable data before start():
-- fortuneIntro.data = { opponentName="Koopa Card Man", jingle="music/cardjingles/114 Huh.spc" }

-- simple VS overlay (now with portraits + zoom)
local vsUI = {
    show=false, t=0,
    scale=0.85,         -- starts smaller, eases up to 1.0
    bob=0,              -- subtle vertical bob
    leftImg=nil, rightImg=nil,
}

-- ---------- Fortune Music Snap/Restore ----------
local FortuneMusic = {
    baseline = nil,   -- {fromFile=true/false, path="", id=number}
}

--- Intro images
local function oppPathFullById(id)
    id = tonumber(id) or 1
    local withId = "cardgame/opponents/leader_p2_"..id..".png"
    if Graphics.loadImageResolved(withId) then return withId end
    return "cardgame/opponents/leader_p2.png"
end

function FortuneMusic.snapshotSection()
    -- Capture BEFORE we play the intro jingle
    local sec = player.section
    local S = Section(sec)
    local path = S.musicPath or ""
    local id   = S.music or 0
    FortuneMusic.baseline = {
        fromFile = (path ~= nil and path ~= ""),
        path     = path or "",
        id       = id,
        sec      = sec,
    }
end

function FortuneMusic.restore(fadeMs)
    if not FortuneMusic.baseline then return end
    local b = FortuneMusic.baseline
    local sec = b.sec or player.section
    if b.fromFile and b.path ~= "" then
        Audio.MusicChange(sec, b.path, fadeMs or 500)
    else
        -- Built-in section music id
        Section(sec).music = b.id
        -- If you want a gentle fade in, you can optionally call:
        -- Audio.MusicFadeIn(sec, fadeMs or 500)  -- if available in your build
    end
end

-- call this before fortuneIntro:start() to set portraits per opponent
local function _setIntroPortraits(leftPath, rightPath)
    local function load(p) return p and Graphics.loadImageResolved(p) or nil end
    vsUI.leftImg  = load(leftPath)   -- e.g. "cardgame/baseball.png" (your player)
    vsUI.rightImg = load(rightPath)  -- e.g. "cardgame/chuck.png"   (opponent)
end

local function centerX(str, font, sx, sy)
    sx, sy = sx or 1, sy or 1
    local w = textplus.size(str, font, sx, sy)  -- returns width in pixels
    return (SCREEN_W - w) * 0.5
end

local function drawVS()
    if not vsUI.show then return end
    local a = math.min(1, vsUI.t/18)                     -- fast ease-in
    local y = 220 - (1-a)*20
    -- ease scale and a tiny bob
    local s = vsUI.scale
    local bob = vsUI.bob

    -- darken bg
    Graphics.drawBox{ x=0, y=0, width=camera.width, height=camera.height,
                      color=Color(0,0,0,0.15*a), priority=9.6 }

    -- portraits (draw behind text)
    do
        local L = vsUI.leftImg
        local R = vsUI.rightImg
        -- positions are tuned for 800x600 HUD; adjust if needed
        if L then
            local w,h = L.width, L.height
            local cx, cy = 400-200, 220 + bob
            Graphics.drawBox{
                texture=L,
                x=cx - (w*s)*0.5, y=cy - (h*s)*0.5,
                width=w*s, height=h*s,
                priority=9.75, color=Color.white
            }
        end
        if R then
            local w,h = R.width, R.height
            local cx, cy = 400+200, 220 + bob
            Graphics.drawBox{
                texture=R,
                x=cx - (w*s)*0.5, y=cy - (h*s)*0.5,
                width=w*s, height=h*s,
                priority=9.75, color=Color.white
            }
        end
    end

    -- title & names
    textplus.print{ text="FORTUNE CHALLENGE", pivot = Sprite.align.TOP, x=400, y=y, xscale=2, yscale=2, font = minFont,
                    color=Color.white, priority=9.8 }
    local opp = fortuneIntro.data and fortuneIntro.data.opponentName or "Opponent"
    textplus.print{ text=("Mario  VS  %s"):format(opp), pivot = Sprite.align.TOP, x=400, y=y+40, font = minFont,
                    xscale=2, yscale=2, color=Color(1.0,0.9,0.3,1), priority=9.8 }
end

fortuneIntro.drawFunc = function(self) drawVS() end

-- main timing: play jingle, hold VS for ~3 seconds
function fortuneIntro:mainRoutineFunc()
    vsUI.show, vsUI.t = true, 0
    vsUI.scale, vsUI.bob = 0.85, 0
    if handycam then
      -- focus midpoint between player and the NPC we just talked to (if you have it)
      -- fallback just focuses the player
      local px,py = player.x + player.width*0.5, player.y + player.height*0.5
      local nx,ny = px,py
      if fortuneIntro.data and fortuneIntro.data.npc and fortuneIntro.data.npc.isValid then
          local n = fortuneIntro.data.npc
          nx,ny = n.x + n.width*0.5, n.y + n.height*0.5
      end
      local cx,cy = (px+nx)*0.5, (py+ny)*0.5

      -- quick zoom-in, then we’ll switch to the VS portraits + jingle
      handycam[1]:transition{ time=0.45, zoom=1.5, toX=cx, toY=cy }
      Routine.wait(0.45)
  
      -- cut to your 3s jingle
      local sec = player.section
      
      Audio.MusicChange(sec, (self.data and self.data.jingle) or "music/cardjingles/chaos emerald.spc", 0)

      -- little pop-in
      for i=1,18 do vsUI.t = vsUI.t + 1; Routine.skip(true) end
      -- linger ~2.5s (total ≈ 3.0s)
      Routine.wait(3.35)
    end
end

-- update: ease the zoom and bob a bit while showing
function fortuneIntro:updateFunc()
    if vsUI.show then
        if vsUI.t < 18 then vsUI.t = vsUI.t + 1 end
        -- ease scale up to 1.0 with a soft approach
        vsUI.scale = vsUI.scale + (1.00 - vsUI.scale) * 0.2
        -- subtle bob (slow sine)
        local t = lunatime.tick() * 0.08
        vsUI.bob = math.sin(t) * 3
    end
end


-- when scene stops (natural or skipped), launch the duel
local _introOpponentKey = nil
local function _startDuel()
    if _introOpponentKey then
      handycam[1]:transition{ time=1.35, zoom=1.0 }
        OpenBoardForDuel(_introOpponentKey)
    end
end

function fortuneIntro:stopFunc()
    vsUI.show = false
    FortuneMusic.restore(250)
    _startDuel()
end

function BeginNPCBattleWithIntro(opponentKey, opponentName, playerPortraitPath, oppPortraitPath)
    _introOpponentKey = opponentKey

    -- take the baseline NOW (level bgm), before we swap to the jingle
    FortuneMusic.snapshotSection()

    fortuneIntro.data = {
        opponentName = opponentName or "Opponent",
        jingle       = "music/cardjingles/chaos emerald.spc",
    }
    _setIntroPortraits(playerPortraitPath, oppPortraitPath)
    fortuneIntro:start()
end



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
          local oppKey = "koopa_card_man"
          local oppId  = (cardGameFortune.challengers[oppKey] and cardGameFortune.challengers[oppKey].deckId) or 1

          BeginNPCBattleWithIntro(oppKey,"Koopa Card Man",
              "cardgame/leader_p1.png",       -- left (you)
              oppPathFullById(oppId)          -- right (opponent) by deckId
          )
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


