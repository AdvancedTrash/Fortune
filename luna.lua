local smwMap = require("smwMap")

-- SMW Costumes
Player.setCostume(CHARACTER_MARIO,"SMW-Mario",true)
Player.setCostume(CHARACTER_LUIGI,"SMW-Luigi",true)

local rankSystem = require("rankSystem")
local coinTracker = require("coinTracker")
local littleDialogue = require("littleDialogue")
local customPause = require("customPause")
local playerphysicspatch = require("playerphysicspatch")
local checklist = require("checklist")
local aw = require("anotherwalljump")
aw.registerAllPlayersDefault()
local twirl = require("twirl")
local customCamera = require("customCamera")
local respawnRooms = require("respawnRooms") 
local minHUD = require("minHUD")
local fastFireballs = require("fastFireballs")
local levelTimerEvent = require("levelTimerEvent")
local warpTransition = require("warpTransition")
local splishSplash = require("splishSplash")
local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")
local layerMover = require("layerMover")
local layerControllers = require("layerControllers")
local cardGameFortune = require("cardGameFortune")
local BOARD_OPEN = false
local selectedHandIndex = nil
local summonPos = "attack" 
local focus = "hand"
local inputLocked = false
local heldInputs  = {}              
local lastInputs  = {} 
local cursor = { c = 0, r = 0 }
local MOVE_COOLDOWN = 5
local moveTimer = 0
local selectedUnit = nil         -- {c=?, r=?} or nil
local legalMoveSet = nil         -- set from rules
local legalAttackSet = nil       -- set from rules
local TERRAIN_IMG = cardGameFortune.TERRAIN_IMG
local END_TURN_PLAYER = 1
local endTurnLatch     = false
local endTurnPrevTurn  = nil
local endTurnCooldown  = 0

local function canHumanEndTurn(s)
    if not s then return false end
    if s.whoseTurn ~= END_TURN_PLAYER then return false end
    if cardGameFortune.aiState and cardGameFortune.aiState.busy then return false end
    if not BOARD_OPEN then return false end
    return true
end





-- ===========================
-- LEVEL RANK SETUP
-- ===========================

local levels = {
    {"1-1 Adventure Away.lvlx",40000,10000},
    {"1-2 Cavern Depths.lvlx",40000,10000},
    {"1-3 Dolphin Ride.lvlx",40000,10000},
    {"1-4 Barrels of Fun.lvlx",40000,10000},
    {"1-C The Koopa Kastle.lvlx",40000,10000},
    {"1-B8 Queen B (Hard Mode).lvlx",10000,10000},
    {"1-B12 Kore (Hard Mode).lvlx", 10000, 10000},
}

for i = 1, #levels do
    rankSystem.registerLevel(levels[i][1], levels[i][2], levels[i][3])
end

function onStart()
    if rankSystem.allLevelsTopRank() then
        SFX.play(29)
    end
end

function rankSystem.onLevelComplete(score,rank,time)
    if rank <= 0 then
        SFX.play(80)
    end
end

function rankSystem.onRankGive(rank)
    if rank == #rankSystem.rankThresholds then
        SFX.play(59)
    end
end

function onPlayerHarm(p)
    player:kill()
end

local FREEZE_FRAMES = 42
local freezeTimer = 0

function onInitAPI()
    registerEvent(nil, "onTick")
    registerEvent(nil, "onTickEnd")
    registerEvent(nil, "onInputUpdate")
    registerEvent(nil, "onPostNPCCollect")
end


local function isPowerup(id)
    local cfg = NPC.config[id]
    return (cfg and (cfg.ispowerup or cfg.isPowerup or cfg.isPowerUp)) 
           or id == 185 or id == 183 or id == 34 or id == 169 or id == 277 or id == 273
end

function onPostNPCCollect(n, p)
    if not p or not n.isValid then return end
    if isPowerup(n.id) then
        freezeTimer = math.max(freezeTimer, FREEZE_FRAMES)
    end
end

-- Freeze manager (stack-safe so multiple features can freeze at once)
local Freeze = {count=0, prev=false, savedVel=nil}

function Freeze.push(saveVel)
    if Freeze.count == 0 then
        Freeze.prev = Defines.levelFreeze
        if saveVel then
            Freeze.savedVel = {player.speedX, player.speedY}
        else
            Freeze.savedVel = nil
        end
    end
    Freeze.count = Freeze.count + 1
    Defines.levelFreeze = true
end

function Freeze.pop()
    if Freeze.count == 0 then return end
    Freeze.count = Freeze.count - 1
    if Freeze.count == 0 then
        Defines.levelFreeze = Freeze.prev
        if Freeze.savedVel then
            player.speedX, player.speedY = Freeze.savedVel[1], Freeze.savedVel[2]
            Freeze.savedVel = nil
        end
    end
end


local function startFreeze(frames)
    if frames and frames > 0 then
        Freeze.push(false)             -- no need to save velocity for short timers
        freezeTimer = math.max(freezeTimer, frames)
    end
end

function onTick()
    -- keep inputs locked only while board is open
    if BOARD_OPEN then
        -- do NOT touch speeds here; Freeze handles freeze
        if inputLocked then
            for k,_ in pairs(player.keys) do
                lastInputs[k]  = lastInputs[k] or player.keys[k]
                player.keys[k] = heldInputs[k] or false
            end
        end
        return
    end

    -- drive the one-shot timer
    if freezeTimer > 0 then
        freezeTimer = freezeTimer - 1
        if freezeTimer == 0 then
            Freeze.pop()
        end
    end
end

function onTickEnd()
    if inputLocked then
        for k,_ in pairs(player.keys) do
            if lastInputs[k] ~= nil then player.keys[k] = lastInputs[k] end
        end
    end
end

-- ===========================
-- BOARD / HUD CONSTANTS
-- ===========================

local SHOW_LAYOUT = true
local BORDER      = 32
local SCREEN_W, SCREEN_H = 800, 600

local BOARD_SIZE = 448

-- Hand config
local CARD_W, CARD_H = 64, 80
local CARD_GAP       = 2
local HAND_W         = (CARD_W * 6) + (CARD_GAP * 5)
local HAND_H         = 84

-- Discard + Description + Hover
local DISC_W,  DISC_H  = 72, HAND_H
local DESC_W,  DESC_H  = 240, HAND_H
local HOVER_W, HOVER_H = 260, 540

-- Positions
local handX = BORDER
local handY = SCREEN_H - BORDER - HAND_H
local discX = handX + HAND_W + 16
local discY = handY
local descX = SCREEN_W - BORDER - DESC_W
local descY = handY
local hoverX = SCREEN_W - (BORDER - 1) - HOVER_W - 18
local hoverY = SCREEN_H - (BORDER - 1) - HOVER_H - 12
local boardX = 32
local boardY = 32
local RIGHT_W = 300
local rightPanelX = SCREEN_W - BORDER - RIGHT_W
local rightPanelY = BORDER

local function gridSize()
    local s = cardGameFortune.peek()
    return (s.cols or 7), (s.rows or 7)
end

local function centerCursor()
    local cols, rows = gridSize()
    cursor.c = math.floor((cols-1)/2)
    cursor.r = math.floor((rows-1)/2)
end

local function clampCursor()
    local cols, rows = gridSize()
    if cursor.c < 0 then cursor.c = 0 elseif cursor.c > cols-1 then cursor.c = cols-1 end
    if cursor.r < 0 then cursor.r = 0 elseif cursor.r > rows-1 then cursor.r = rows-1 end
end

local function updateCursorFromArrows()
    if moveTimer > 0 then moveTimer = moveTimer - 1 end
    local moved = false
    if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then cursor.c = cursor.c - 1; moved = true end
    if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then cursor.c = cursor.c + 1; moved = true end
    if player.rawKeys.up    == KEYS_PRESSED or (player.rawKeys.up    == KEYS_DOWN and moveTimer == 0) then cursor.r = cursor.r - 1; moved = true end
    if player.rawKeys.down  == KEYS_PRESSED or (player.rawKeys.down  == KEYS_DOWN and moveTimer == 0) then cursor.r = cursor.r + 1; moved = true end
    if moved then clampCursor(); moveTimer = MOVE_COOLDOWN end
end

local _tex = {}
local tex
tex = function(path)
    if not path or path == "" then return nil end
    local img = _tex[path]
    if img == nil then
        img = Graphics.loadImageResolved(path)
        _tex[path] = img
    end
    return img
end

local TERRAIN_TEX = {}
local function terrImg(terr)
    local texpath = cardGameFortune.TERRAIN_IMG[terr]    
    if not texpath then return nil end
    local t = TERRAIN_TEX[terr]
    if t == nil then
        t = tex(texpath)                                 
        TERRAIN_TEX[terr] = t
    end
    return t
end


local P_W, P_H = 100, 40
local p1X = (SCREEN_W * 0.5) - P_W + 220
local p2X = (SCREEN_W * 0.5) + 240
local pY  = BORDER

local function box(x, y, w, h, r, g, b, a)
    Graphics.drawBox{ x=x,y=y,width=w,height=h,
        color = Color(r/255,g/255,b/255,(a or 128)/255), priority=5 }
    Graphics.drawBox{ x=x,y=y,width=w,height=h,
        color = Color.white..0.25, priority=5, sceneCoords=false }
end

-- ===========================
-- GRID + ICONS
-- ===========================

local CELL = 64
local GRID_COLS, GRID_ROWS = 7, 7

local TX_FILL      = tex("cardgame/texturetransparent.png")
local TX_BORDER_W  = tex("cardgame/cell_outline_3slice.png")        -- white
local TX_BORDER_R  = tex("cardgame/cell_outline_3slice_red.png")    -- red
local TX_BORDER_B  = tex("cardgame/cell_outline_3slice_blue.png")   -- blue

local outlineWhite = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_W
}
local outlineRed   = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_R
}
local outlineBlue  = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_B
}

local outlineWhite1 = Sprite.box{
  width = CELL-2, height = CELL-2,
  texture = TX_FILL, borderwidth = 2, bordertexture = TX_BORDER_W,
}
local outlineRed1 = Sprite.box{
  width = CELL-2, height = CELL-2,
  texture = TX_FILL, borderwidth = 2, bordertexture = TX_BORDER_R,
}
local outlineBlue1 = Sprite.box{
  width = CELL-2, height = CELL-2,
  texture = TX_FILL, borderwidth = 2, bordertexture = TX_BORDER_B,
}


local function drawOutlineSprite(spr, x, y, prio)
  spr.x = x; spr.y = y
  spr:draw{priority = prio or 5.1}
end

-- which: "red" | "blue" | "white"; inset: 0 (default) or 1 (1px inward)
local function outlineCell(c, r, which, prio, inset)
  inset = inset or 0
  local x = boardX + c*CELL + inset
  local y = boardY + r*CELL + inset

  if which == "red" then
    drawOutlineSprite((inset==1 and outlineRed1  or outlineRed),  x, y, prio)
  elseif which == "blue" then
    drawOutlineSprite((inset==1 and outlineBlue1 or outlineBlue), x, y, prio)
  else
    drawOutlineSprite((inset==1 and outlineWhite1 or outlineWhite), x, y, prio)
  end
end



local function fillCell(c, r, col, prio)
    Graphics.drawBox{
        x = boardX + c*CELL,
        y = boardY + r*CELL,
        width = CELL, height = CELL,
        color = col or (Color.white..0.2),
        priority = prio or 5.0
    }
end


local gridIcons = {

}

local function drawIcon(id, col, row)
    local card = cardGameFortune.db[id]
    if not card then return end
    local img = tex(card.icon or card.image)
    if not img then return end
    Graphics.drawImageWP(img, boardX + col*CELL, boardY + row*CELL, 5)
end

-- ===========================
-- CURSOR + HOVER HELPERS
-- ===========================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function getCardAtCell(col, row)
    for _,g in ipairs(gridIcons) do
        if g.c == col and g.r == row then
            return cardGameFortune.db[g.id], g.id
        end
    end
    return nil, nil
end

local function wrapText(s, maxChars)
    local out, line = {}, ""
    for word in tostring(s or ""):gmatch("%S+") do
        if #line + #word + 1 > maxChars then
            table.insert(out, line)
            line = word
        else
            line = (line == "" and word) or (line .. " " .. word)
        end
    end
    if line ~= "" then table.insert(out, line) end
    return out
end

local function isHeld(k)
    local v = player.rawKeys[k]
    return v == KEYS_PRESSED or v == KEYS_DOWN
end

-- ===== TEXT HELPERS (update) =====
local MF_SCALE_X, MF_SCALE_Y = 2, 2
local MF_LINE = 32
local CHAR_W  = 16         
local OUTLINE_PAD = 2
local function px(n) return math.floor(n+0.5) end

-- Common colors (r,g,b,a)
local COL_WHITE = {1,1,1,1}
local COL_NAME =  {1.0, 0.84, 0.3, 1.0} -- Card name (Gold)
local COL_ATK   = {1,0.3,0.3,1}    -- red-ish for ATK
local COL_DEF   = {0.4,0.6,1,1}    -- blue-ish for DEF
local COL_LABEL = {1,1,1,0.85}
local COL_MOVE = {0.91, 0.73, 0.55, 1.0}

local function label(s, x, y, prio, col, align)
    textplus.print{
        text = tostring(s or ""),
        x = px(x), y = px(y),
        priority = prio or 9,
        font = minFont,
        xscale = MF_SCALE_X, yscale = MF_SCALE_Y,
        color = col or {1,1,1,1},
        align = align or "left",
    }
end

-- basic greedy wrap (char-count based for speed)
local function wrapIntoLines(str, maxPixelWidth, maxLines)
    local CHAR_W = 16
    local maxChars = math.max(1, math.floor(maxPixelWidth / CHAR_W))
    local out, line = {}, ""
    for word in tostring(str or ""):gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= maxChars then
            line = line .. " " .. word
        else
            out[#out+1] = line
            line = word
            if maxLines and #out >= maxLines then break end
        end
    end
    if (not maxLines or #out < maxLines) and line ~= "" then out[#out+1] = line end
    if maxLines and #out > maxLines then
        out = { table.unpack(out, 1, maxLines) }
    end
    if maxLines and #out == maxLines then
        out[#out] = (#out[#out] > 3) and (out[#out]:sub(1, #out[#out]-3) .. "...") or out[#out]
    end
    return out
end

local function labelWrapped(str, x, y, boxW, maxLines, prio, col)
    local innerW = boxW - OUTLINE_PAD*2
    local lines  = wrapIntoLines(str, innerW - 8, maxLines)
    for i=1,#lines do
        textplus.print{
            text = lines[i],
            x = px(x + OUTLINE_PAD), y = px(y + (i-1)*MF_LINE),
            priority = prio or 9,
            font = minFont,
            xscale = MF_SCALE_X, yscale = MF_SCALE_Y,
            color = col or {1,1,1,1},
        }
    end
end

local function textWidth(s) return (#tostring(s or "")) * CHAR_W end

local function centerRowWidth(wTotal)  -- left x so a row of width wTotal is centered in hover box
    return (hoverX + HOVER_W*0.5) - math.floor(wTotal/2)
end

-- load and draw a 16x16 icon (cached)
local _icons = {}
local function icon(path) if not _icons[path] then _icons[path] = Graphics.loadImageResolved(path) end; return _icons[path] end

-- draw a 16x16 icon; returns (x advanced) so you can place text after it
local function drawIcon16(path, x, y, prio)
    local img = icon(path); if not img then return x end
    Graphics.drawImageWP(img, x, y, prio or 5)
    return x + 18 -- 16px icon + 2px gap
end

-- Player panels
local function drawHPBarTop()
    local s = cardGameFortune.peek()
    if not s then return end

    local img = tex("cardgame/hpBorder.png")
    if not img then return end

    -- current + max (fallbacks)
    local hp1  = (s.leaderHP    and s.leaderHP[1])    or 0
    local hp2  = (s.leaderHP    and s.leaderHP[2])    or 0
    local max1 = (s.leaderMaxHP and s.leaderMaxHP[1]) or 40
    local max2 = (s.leaderMaxHP and s.leaderMaxHP[2]) or max1

    local w, h = img.width, img.height
    local x = math.floor(camera.width*0.5 - w*0.5)
    local y = 2

    local inset = 2
    local halfW = math.floor(w*0.5) - inset

    local ratio1 = math.max(0, math.min(1, hp1 / math.max(1, max1)))
    local ratio2 = math.max(0, math.min(1, hp2 / math.max(1, max2)))

    local fillH = h - inset*2
    local p1W   = math.floor((halfW - inset) * ratio1)
    local p2W   = math.floor((halfW - inset) * ratio2)

    -- backgrounds
    Graphics.drawBox{ x=x+inset,   y=y+inset, width=halfW-inset, height=fillH, color=Color(0,0,0,0.35), priority=9.9 }
    Graphics.drawBox{ x=x+halfW,   y=y+inset, width=halfW-inset, height=fillH, color=Color(0,0,0,0.35), priority=9.9 }

    -- fills
    if p1W > 0 then
        Graphics.drawBox{ x=x+inset, y=y+inset, width=p1W, height=fillH, color=Color(1,0.25,0.25,1), priority=9.92 }
    end
    if p2W > 0 then
        Graphics.drawBox{ x=x+w-inset-p2W, y=y+inset, width=p2W, height=fillH, color=Color(0.3,0.65,1,1), priority=9.92 }
    end

    -- border
    Graphics.drawBox{ texture=img, x=x, y=y, width=w, height=h, priority=9.95 }

    -- numbers (draw last so they sit on top)
    label(("%d"):format(hp1), SCREEN_W*0.5 - 166, SCREEN_H - 594, 9.96, {1,0.3,0.3,1})
    label(("%d"):format(hp2), SCREEN_W*0.5 + 128, SCREEN_H - 594, 9.96, {0.3,0.65,1,1}, "right")
end

-- === background config ===
local MENU_BG    = "cardgame/testbg.jpg"      -- backdrop image for the board area

local _bgImg = nil
local function bgTex()
    if not _bgImg then _bgImg = Graphics.loadImageResolved(MENU_BG) end
    return _bgImg
end

-- Card game menu music
local MENU_MUSIC = "music/Alleycat Blues.spc"
local MENU_FADE  = 300                         

-- Store original music (for whatever level you're on!)
local musicSwap = {active=false, secIndex=nil, id=nil, path=nil}

local function swapToMenuMusic()
    local secIndex = player.section
    local sec = Section(secIndex)

    -- remember what the section had
    musicSwap.active   = true
    musicSwap.secIndex = secIndex
    musicSwap.id       = sec.music
    musicSwap.path     = sec.musicPath

    -- this fades into our definition on line 312-313 ^^
    Audio.MusicChange(secIndex, MENU_MUSIC, MENU_FADE)
end

local function restoreSectionMusic()
    if not musicSwap.active then return end
    local secIndex = musicSwap.secIndex or player.section
    local sec = Section(secIndex)

    if musicSwap.path and musicSwap.path ~= "" then
        -- section was using a custom path originally → fade back to it
        Audio.MusicChange(secIndex, musicSwap.path, MENU_FADE)
    else
        -- section was using a built-in track (id). Put it back and re-start section music.
        sec.music     = musicSwap.id or 0
        sec.musicPath = nil
        if Level and Level.playMusic then Level.playMusic() end
    end

    musicSwap.active = false
end


-- ===========================
-- INPUT
-- ===========================

function onInputUpdate()
        -- disable map toggle on overworld
        if Level.filename() == "map.lvlx" or Level.isOverworld then
            player.dropItemKeyPressing = false
        end

        local myTurn = true

        if endTurnLatch then
            if s and s.whoseTurn ~= endTurnPrevTurn then
                endTurnLatch = false
                endTurnCooldown = 0
            elseif endTurnCooldown > 0 then
                endTurnCooldown = endTurnCooldown - 1
                if endTurnCooldown == 0 then endTurnLatch = false end
            end
        end

        -- open/close the board
        if player.rawKeys.dropItem == KEYS_PRESSED then
            BOARD_OPEN   = not BOARD_OPEN
            inputLocked  = BOARD_OPEN      -- tie into the input lock
            player.dropItemKeyPressing = false

            if BOARD_OPEN then
                Freeze.push(true)  
                if not cardGameFortune.isOpen() then
                    cardGameFortune.newMatch(12345)
                    cardGameFortune.open()
                    -- focus + default selection on open
                    focus = "hand"
                    summonPos = "attack"
                    local s = cardGameFortune.peek()
                    selectedHandIndex = nil
                    for i=1,6 do
                        if (s.hands[1] or {})[i] then selectedHandIndex = i; break end
                    end
                    centerCursor()
                    moveTimer = 0
                end
                swapToMenuMusic()
            else
                Freeze.pop()
                cardGameFortune.close()
                restoreSectionMusic()
            end
        end
        
        if BOARD_OPEN then
            local s = cardGameFortune.peek()
            local aiBusy = cardGameFortune.aiState and cardGameFortune.aiState.busy
            local myTurn = (s.whoseTurn == 1) and (not aiBusy)

                if endTurnLatch then
                    if s and s.whoseTurn ~= endTurnPrevTurn then
                        endTurnLatch, endTurnCooldown = false, 0
                    elseif endTurnCooldown > 0 then
                        endTurnCooldown = endTurnCooldown - 1
                        if endTurnCooldown == 0 then endTurnLatch = false end
                    end
                end

            -- Start AI turn if it's P2's turn and AI isn't already running
            if s and s.whoseTurn == 2 and not (cardGameFortune.aiState and cardGameFortune.aiState.busy) then
                if cardGameFortune.aiBeginTurn then cardGameFortune.aiBeginTurn() end
            end

            -- Step AI queue (runs one step when its delay hits 0)
            if cardGameFortune.aiUpdate then cardGameFortune.aiUpdate() end

            -- If AI just ended, reset P1 UI cleanly
            if cardGameFortune.aiJustEnded then
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                focus     = "hand"
                summonPos = "attack"

                -- select first card in P1's hand, if any
                selectedHandIndex = nil
                local h = (s.hands[1] or {})
                for i=1,6 do if h[i] then selectedHandIndex = i; break end end

                centerCursor()
                cardGameFortune.aiJustEnded = false
            end
        end

        -- toggle hand <-> board (not while aiming)
        if focus ~= "aim" and (player.rawKeys.spinJump == KEYS_PRESSED or player.rawKeys.altJump == KEYS_PRESSED) then
            focus = (focus == "hand") and "board" or "hand"
            if focus == "board" then centerCursor() end
            SFX.play(3)
        end

        -- End Turn (RUN) – only human, only on their turn, only when AI idle, only once
        if player.rawKeys.altRun == KEYS_PRESSED then
            local s = cardGameFortune.peek()
            if canHumanEndTurn(s) and (not endTurnLatch) and cardGameFortune.endTurn then
                endTurnPrevTurn = s.whoseTurn
                endTurnLatch    = true
                endTurnCooldown = 12  -- small safety window (frames)

                cardGameFortune.endTurn()

                -- reset UI for the next player (P2/AI)
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                focus     = "hand"
                summonPos = "attack"

                -- pick first card in the new player's hand
                local ss = cardGameFortune.peek()
                selectedHandIndex = nil
                local h = (ss.hands[ss.whoseTurn] or {})
                for i=1,6 do if h[i] then selectedHandIndex = i; break end end

                centerCursor()
                SFX.play(3)
            else
                SFX.play(9)
            end
        end




        -- ========= HAND mode =========
        if focus == "hand" then
             if not (BOARD_OPEN and myTurn) then
                --ignore?--
             else
                local function handCycle(dir)
                local s = cardGameFortune.peek()
                -- if nothing selected yet, select the first filled slot
                if not selectedHandIndex then
                    for i=1,6 do if (s.hands[1] or {})[i] then selectedHandIndex = i; break end end
                    if not selectedHandIndex then return end
                end
                -- move to next filled slot in the given direction (-1 or +1)
                local i, start = selectedHandIndex, selectedHandIndex
                repeat
                    i = ((i - 1 + dir + 6) % 6) + 1
                    if (s.hands[1] or {})[i] then selectedHandIndex = i; SFX.play(3); break end
                until i == start
            end

            -- use arrows to cycle hand slots (does NOT move board)
                if moveTimer > 0 then moveTimer = moveTimer - 1 end
                local stepped = false
                if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then handCycle(-1); stepped = true end
                if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then handCycle( 1); stepped = true end
                if stepped then moveTimer = MOVE_COOLDOWN end

                if player.rawKeys.one   == KEYS_PRESSED then selectedHandIndex = 1 end
                if player.rawKeys.two   == KEYS_PRESSED then selectedHandIndex = 2 end
                if player.rawKeys.three == KEYS_PRESSED then selectedHandIndex = 3 end
                if player.rawKeys.four  == KEYS_PRESSED then selectedHandIndex = 4 end
                if player.rawKeys.five  == KEYS_PRESSED then selectedHandIndex = 5 end
                if player.rawKeys.six   == KEYS_PRESSED then selectedHandIndex = 6 end

                if player.rawKeys.run == KEYS_PRESSED then
                    summonPos = (summonPos == "attack") and "defense" or "attack"
                    SFX.play(3)
                end

                -- A) hand → aim (press Jump in hand)
                if player.rawKeys.jump == KEYS_PRESSED then
                    local s = cardGameFortune.peek()
                    if selectedHandIndex == nil then
                        for i=1,6 do if (s.hands[1] or {})[i] then selectedHandIndex = i; break end end
                    end
                    if selectedHandIndex and (s.hands[1] or {})[selectedHandIndex] then
                        focus = "aim"
                        centerCursor()      -- <— start aiming from center instead of (0,0)
                        SFX.play(1)
                    else
                        SFX.play(3)
                    end
                end

                -- B) hand ↔ board toggle (spinJump or altJump)
                if player.rawKeys.altRun == KEYS_PRESSED then
                    selectedHandIndex = nil
                    summonPos = "attack"
                end
            end

        -- ========= AIM (placing) =========
        elseif focus == "aim" then
            if moveTimer > 0 then moveTimer = moveTimer - 1 end
            local moved = false
            if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c - 1, 0, GRID_COLS-1); moved = true end
            if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c + 1, 0, GRID_COLS-1); moved = true end
            if player.rawKeys.up    == KEYS_PRESSED or (player.rawKeys.up    == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r - 1, 0, GRID_ROWS-1); moved = true end
            if player.rawKeys.down  == KEYS_PRESSED or (player.rawKeys.down  == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r + 1, 0, GRID_ROWS-1); moved = true end
            if moved then moveTimer = MOVE_COOLDOWN end

            if player.rawKeys.run == KEYS_PRESSED then
                summonPos = (summonPos == "attack") and "defense" or "attack"
                SFX.play(3)
            end

            if player.rawKeys.jump == KEYS_PRESSED and selectedHandIndex ~= nil then
                local s = cardGameFortune.peek()
                local hand = s.hands[1]
                if hand and hand[selectedHandIndex] then
                    local ok = select(1, cardGameFortune.playFromHand(1, selectedHandIndex, cursor.c, cursor.r, summonPos))
                    if ok then
                        SFX.play(1)
                        selectedHandIndex = nil
                        summonPos = "attack"
                        focus = "hand"
                    else
                        SFX.play(3)
                    end
                end
            end

            if player.rawKeys.altRun == KEYS_PRESSED then
                focus = "hand"
                SFX.play(3)
            end

        -- ========= BOARD (inspect) =========
        elseif BOARD_OPEN and focus == "board" then
            if moveTimer > 0 then moveTimer = moveTimer - 1 end
            local moved = false
            if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c - 1, 0, GRID_COLS-1); moved = true end
            if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c + 1, 0, GRID_COLS-1); moved = true end
            if player.rawKeys.up    == KEYS_PRESSED or (player.rawKeys.up    == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r - 1, 0, GRID_ROWS-1); moved = true end
            if player.rawKeys.down  == KEYS_PRESSED or (player.rawKeys.down  == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r + 1, 0, GRID_ROWS-1); moved = true end
            if moved then moveTimer = MOVE_COOLDOWN end

            if player.rawKeys.altRun == KEYS_PRESSED then
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                focus = "hand"
                SFX.play(3)
            end

            local s = cardGameFortune.peek()
            local c, r = cursor.c, cursor.r
            local cell = s.board[r][c]
            
            -- Fortify-to-Defense (RUN) while a friendly, movable non-leader is selected.
            do
                if selectedUnit and s then                 -- 's' is from cardGameFortune.peek() above
                    if s.whoseTurn == 1 then               -- or: if myTurn then ...
                        local u = s.board[selectedUnit.r] and s.board[selectedUnit.r][selectedUnit.c]
                        if u and not u.isLeader and not u.summoningSickness and not u.hasMoved and u.owner == s.whoseTurn then
                            if player.rawKeys.run == KEYS_PRESSED then
                                local ok = cardGameFortune.fortifyToDefense(selectedUnit.c, selectedUnit.r)
                                if ok then
                                    SFX.play(3)
                                    -- clear selection & previews (consumes the move)
                                    selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                                else
                                    SFX.play(9)
                                end
                            end
                        end
                    end
                end
            end



            -- Select / act with Jump
            if player.rawKeys.jump == KEYS_PRESSED then
                local s = cardGameFortune.peek()
                local cell = s.board[r] and s.board[r][c]

                if selectedUnit then
                    -- Already have something selected: try MOVE first, then ATTACK (non-leader), else cancel.
                    if legalMoveSet and legalMoveSet[r] and legalMoveSet[r][c] and not s.board[r][c] then
                        local ok = cardGameFortune.moveUnit(selectedUnit.c, selectedUnit.r, c, r)
                        if ok then SFX.play(3) end
                        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil

                    elseif (not selectedUnit.isLeader) and legalAttackSet and legalAttackSet[r] and legalAttackSet[r][c] then
                        local u = s.board[selectedUnit.r][selectedUnit.c]
                        if u and not u.isLeader then u.pos = "attack" end
                        local ok = cardGameFortune.resolveBattle(selectedUnit.c, selectedUnit.r, c, r)
                        SFX.play(ok and 3 or 9)
                        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil

                    else
                        -- clicked an illegal square: deselect
                        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                        SFX.play(2)
                    end

                else
                    -- Nothing selected yet: pick our own piece (leader OR unit) on our turn
                    if cell and cell.owner == s.whoseTurn then
                        selectedUnit = {c=c, r=r, isLeader = cell.isLeader}
                        if cell.isLeader then
                            -- leaders: left/right only
                            legalMoveSet   = cardGameFortune.legalLeaderMovesFrom(c, r)
                            legalAttackSet = nil              -- leaders don't attack
                        else
                            legalMoveSet   = cardGameFortune.legalMovesFrom(c, r)
                            legalAttackSet = cardGameFortune.legalAttacksFrom(c, r)
                        end
                        SFX.play(1)
                    end
                end
            end


            -- Cancel with SpinJump
            if player.rawKeys.spinJump == KEYS_PRESSED or player.rawKeys.altJump == KEYS_PRESSED then
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                SFX.play(2)
            end
        end
end

-- ===========================
-- HUD DRAW
-- ===========================

function onHUDDraw()
    if not BOARD_OPEN or not SHOW_LAYOUT then return end

    -- top HP bar
    drawHPBarTop()

    local s = cardGameFortune.peek()

    -- board backdrop
    local img = bgTex()
    if img then
        Graphics.drawBox{
            texture  = img,
            x        = BORDER,
            y        = BORDER,
            width    = SCREEN_W - (BORDER*2),
            height   = SCREEN_H - (BORDER*2),
            priority = 4.8,
            color    = Color.white,
        }
    end

    -- outer border
    local borderImg = tex("cardgame/border.png")
    if borderImg then
        Graphics.drawBox{
            texture = borderImg,
            x = 0, y = 0,
            width = camera.width, height = camera.height,
            priority = 7,
        }
    end

    -- grid
    local gridImg = tex("cardgame/grid.png")
    if gridImg then
        Graphics.drawImageWP(gridImg, boardX, boardY, 5)
    else
        box(boardX, boardY, BOARD_SIZE, BOARD_SIZE, 60,160,255, 60)
        label("BOARD 448x448", boardX+8, boardY+8)
    end

    local BOARD_TINT = Color(0,0,0,0.45)
        Graphics.drawBox{
            x        = boardX,
            y        = boardY,
            width    = GRID_COLS * CELL,
            height   = GRID_ROWS * CELL,
            color    = BOARD_TINT,
            priority = 4.95,
        }

    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local terr = cardGameFortune.terrainAt(c,r)
            local img  = terrImg(terr)
            if img then
                Graphics.drawImageWP(img, boardX + c*CELL, boardY + r*CELL, 4.9)
            end
        end
    end

    -- draw leaders + units (from real state)
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local cell = s.board[r][c]
            if cell then
                if cell.isLeader then
                    local ltex = tex((cell.owner==1) and "cardgame/leader_p1.png" or "cardgame/leader_p2.png")
                    if ltex then Graphics.drawImageWP(ltex, boardX + c*CELL, boardY + r*CELL, 5) end
                else
                    local def = cell.cardId and cardGameFortune.db[cell.cardId]
                    if def and def.icon then
                        local itex = tex(def.icon)
                        if itex then Graphics.drawImageWP(itex, boardX + c*CELL, boardY + r*CELL, 5) end
                        label(cell.pos == "defense" and "D" or "A", boardX + c*CELL + 48, boardY + r*CELL + 44)
                    end
                end

                do
                -- owner outline: P1 red / P2 blue
                outlineCell(c, r, (cell.owner==1) and "red" or "blue", 5.1, 1)
                end
            end
        end
    end

    -- leader icons (small)
    local leader1Tex = tex("cardgame/leader_p1healthicon.png")
    local leader2Tex = tex("cardgame/leader_p2healthicon.png")
    if leader1Tex then Graphics.drawImageWP(leader1Tex, SCREEN_W*0.5 - 132, SCREEN_H - 600, 9) end
    if leader2Tex then Graphics.drawImageWP(leader2Tex, SCREEN_W*0.5 +  96, SCREEN_H - 600, 9) end

    -- show legal summon tiles while AIMing (with cardId for terrain/type rules)
    if focus == "aim" and selectedHandIndex then
        local handCardId = (s.hands[1] or {})[selectedHandIndex]

        -- find P1 leader
        local lp = s.leaderPos and s.leaderPos[1]
        if not lp then
            for rr=0,s.rows-1 do
                for cc=0,s.cols-1 do
                    local cell = s.board[rr][cc]
                    if cell and cell.isLeader and cell.owner==1 then lp={c=cc,r=rr}; break end
                end
                if lp then break end
            end
        end

        if lp then
            for dy=-1,1 do
                for dx=-1,1 do
                    if not (dx==0 and dy==0) then
                        local cc, rr = lp.c+dx, lp.r+dy
                        if cc>=0 and cc<s.cols and rr>=0 and rr<s.rows then
                            local ok = cardGameFortune.canSummonAt and select(1, cardGameFortune.canSummonAt(1, cc, rr, handCardId))
                            if ok then
                                Graphics.drawBox{
                                    x = boardX + cc*CELL, y = boardY + rr*CELL,
                                    width = CELL, height = CELL,
                                    color = Color(0.2,1,0.2,0.12), priority = 5
                                }
                            end
                        end
                    end
                end
            end
        end
    end

-- Movement & attack highlights for selected unit
    if selectedUnit then
        -- moves: soft blue fill
        for rr,row in pairs(legalMoveSet or {}) do
            for cc,_ in pairs(row) do
                fillCell(cc, rr, Color(0.40, 0.70, 1.00, 0.18), 5.0)
            end
        end

        -- attacks: soft red fill
        for rr,row in pairs(legalAttackSet or {}) do
            for cc,_ in pairs(row) do
                fillCell(cc, rr, Color(1.00, 0.25, 0.25, 0.22), 5.0)
            end
        end

        -- selected unit: subtle white fill (optional)
        fillCell(selectedUnit.c, selectedUnit.r, Color(1,1,1,0.28), 5.3)
    end




    -- cursor highlight (green/red in AIM if legal/illegal)
    if focus ~= "hand" then
        local col = Color(1,1,1,0.18)  -- neutral in board mode
        if focus == "aim" and selectedHandIndex then
            local s   = cardGameFortune.peek()
            local cid = (s.hands[1] or {})[selectedHandIndex]
            local ok  = cardGameFortune.canSummonAt and select(1, cardGameFortune.canSummonAt(1, cursor.c, cursor.r, cid))
            col = ok and Color(0.20, 1.00, 0.20, 0.25) or Color(1.00, 0.20, 0.20, 0.25)
        end
        fillCell(cursor.c, cursor.r, col, 5.2)
    end




    -- section titles
    label("DISC",              discX+8, descY+8)
    label("DESCRIPTION BOX",   descX+8, descY+8)

    -- hand panel
    Graphics.drawBox{
        x=handX-8, y=handY+22, width=(CARD_W+CARD_GAP)*6 - CARD_GAP + 16, height=CARD_H+20,
        color=Color(0,0,0,0.35), priority=5
    }
    local hx, hy = handX, handY-2
    for i=1,6 do
        local cardId = (s.hands[1] or {})[i]
        box(hx, hy, CARD_W, CARD_H, 255,255,255, 40)
        if cardId then
            local def = cardGameFortune.db[cardId]
            if def and def.icon then
                local img2 = tex(def.icon); if img2 then Graphics.drawImageWP(img2, hx, hy, 5) end
            end
            if selectedHandIndex == i then
                Graphics.drawBox{ x=hx-2,y=hy-2,width=CARD_W+4,height=CARD_H+4, color=Color.white..0.5, priority=7 }
                label((summonPos=="defense") and "DEF" or "ATK", hx+4, hy+CARD_H+2)
            end
        else
            label(tostring(i), hx+4, hy+4)
        end
        hx = hx + CARD_W + CARD_GAP
    end

    ----------------------------------------------------------------
    -- INFO PANEL
    ----------------------------------------------------------------
    label("", hoverX + HOVER_W*0.5, hoverY+8, 5, COL_LABEL, "center")
    local yy    = hoverY + 30
    local shown = false

    -- leader info (under cursor)
    do
        local cell = s.board[cursor.r][cursor.c]
        if cell and cell.isLeader then
            local who = (cell.owner==1) and "P1 Leader" or "P2 Leader"
            label(who, hoverX+8, yy, 5, COL_NAME); yy = yy + MF_LINE
            label("POS: "..(cell.pos or "defense").."   HP: "..tostring(cell.hp or 0), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            label("Summon: adjacent tiles", hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            shown = true

            -- outline the tile the leader is on
        local col = (cell.owner == 1) and Color(1.00,0.35,0.35,0.95) or Color(0.40,0.70,1.00,0.95)
            outlineCell(cursor.c, cursor.r, (cell.owner==1) and "red" or "blue", 5.1, 1)
            fillCell(cursor.c, cursor.r, Color(1,1,1,0.12), 5.05)
        end
    end

    -- helper to draw a card’s info; pos is optional {c=,r=}
    local function drawCardInfo(def, header, extras, pos)
        if not def then return end

        -- name row
        local nameText = tostring(def.name or "Unknown")
        local iconW, gap = 16, 2
        local wTotal = iconW + gap + textWidth(nameText)
        local x = centerRowWidth(wTotal)
        drawIcon16("cardgame/name.png", x, yy-6, 5)
        label(nameText, x + iconW + gap, yy, 5, COL_NAME, "left")
        yy = yy + MF_LINE

        -- ATK / DEF (effective if a tile was provided)
        local atkText, defText
        if pos and pos.c and pos.r then
            local eATK,eDEF,terr,delta = cardGameFortune.getEffectiveStats(def, pos.c, pos.r)
            local bump = (delta ~= 0) and (" ("..((delta>0) and "+" or "")..delta..")") or ""
            atkText = "ATK: "..tostring(eATK)..bump
            defText = "DEF: "..tostring(eDEF)..bump
        else
            atkText = "ATK: "..tostring(def.atk or 0)
            defText = "DEF: "..tostring(def.def or 0)
        end

        do
            local iconW2, gap2, colGap = 16, 2, 24
            local wATK   = iconW2 + gap2 + textWidth(atkText)
            local wDEF   = iconW2 + gap2 + textWidth(defText)
            local totW   = wATK + colGap + wDEF

            local x1 = centerRowWidth(totW)
            drawIcon16("cardgame/attack.png",  x1, yy-6, 5)
            label(atkText, x1 + iconW2 + gap2, yy, 5, COL_ATK)

            local x2 = centerRowWidth(totW) + wATK + colGap
            drawIcon16("cardgame/defence.png", x2, yy-6, 5)
            label(defText, x2 + iconW2 + gap2, yy, 5, COL_DEF)
        end
        yy = yy + MF_LINE

        if extras then extras() end

        -- movement, tags, cost, description
        label("MOV: "..tostring(def.movementtype or "normal")..
              "    RANGE: "..tostring(def.movement or 0), hoverX+8, yy, 5, COL_MOVE); yy = yy + MF_LINE
        label("Type: "..tostring(def.type or "?").."   atkType: "..tostring(def.atktype or "?"), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
        label("Tags: "..tostring(def.subtype1 or "-").."/"..tostring(def.subtype2 or "-"), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
        if def.summoncost or def.deckcost then
            label("Cost: "..tostring(def.summoncost or 0).." / "..tostring(def.deckcost or 0), hoverX+8, yy, 5, COL_NAME); yy = yy + MF_LINE
        end
        labelWrapped(def.description or "", hoverX+8, yy, HOVER_W-16, 8, 5, COL_WHITE)
    end

    -- unit under cursor OR AIM preview OR hand-only view
    if not shown and (focus == "board" or focus == "aim") then
        local cell = s.board[cursor.r][cursor.c]
        if cell and cell.cardId then
            local def = cardGameFortune.db[cell.cardId]
            drawCardInfo(def, nil, function()
                label("POS: "..(cell.pos or "attack"), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            end, {c=cursor.c, r=cursor.r})
            shown = true
        elseif focus == "aim" and selectedHandIndex ~= nil and (s.hands[1] or {})[selectedHandIndex] then
            local def = cardGameFortune.db[(s.hands[1])[selectedHandIndex]]
            drawCardInfo(def, nil, function()
                label("PLACE AS: "..((summonPos=="defense") and "DEFENSE" or "ATTACK"), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            end, {c=cursor.c, r=cursor.r})
            shown = true
        end
    end

    if not shown and focus == "hand" and selectedHandIndex ~= nil then
        local cardId = (s.hands[1] or {})[selectedHandIndex]
        if cardId then
            local def = cardGameFortune.db[cardId]
            drawCardInfo(def, nil, function()
                label("PLACE AS: "..((summonPos=="defense") and "DEFENSE" or "ATTACK"), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            end) -- no tile → base stats
            shown = true
        end
    end

    if not shown then
        label((focus=="hand") and "(select a card in your hand)" or "(move the cursor over a unit)", hoverX+8, hoverY+30, 5, COL_LABEL)
    end

    -- footer counters
    label("Deck:"..tostring(s.deckCounts[1]).."  Hand:"..tostring(#s.hands[1]), handX + 300, handY + CARD_H + 16)
    label("Energy:"..tostring(s.energy[1] or 0), handX + 576, handY + CARD_H + 16)
end


local function clampToScreen(x, y, textW, textH)
    x = math.max(BORDER, math.min(x, SCREEN_W - BORDER - textW))
    y = math.max(BORDER, math.min(y, SCREEN_H - BORDER - textH))
    return x, y
end
