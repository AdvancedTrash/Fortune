UI = UI or {}
UI.pending = UI.pending or nil
UI.modal     = UI.modal     or nil
UI.graveSide = UI.graveSide or 1

UI.action = {
    idx = 1,   -- current selected action index
    items = {
        {id="hand",   label="Hand"},
        {id="board",  label="Board"},
        {id="guide",  label="Guide"},
        {id="grave",  label="Grave"},
        {id="end",    label="End Turn"},
        {id="restart",label="Restart"},
        {id="giveup", label="Give Up"},
    }
}

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
local backgroundAreas = require("backgroundAreas")

--Card stuff--
BOARD_OPEN = false
local boardActive = boardActive or false
local selectedHandIndex = nil
local summonPos = "attack" 
local focus = focus or "hand"
local prevFocus = prevFocus or "hand" 
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
local endTurnLatch      = false
local endTurnCooldown   = 0
local endTurnPrevTurn   = 1
local inBounds = cardGameFortune.inBounds



-- ===========================
-- LEVEL RANK SETUP
-- ===========================

local levels = {
    {"1-1 Adventure Away.lvlx",40000,10000},
    {"1-2 Cavern Depths.lvlx",40000,10000},
    {"1-3 Dolphin Ride.lvlx",40000,10000},
    {"1-4 Barrels of Fun.lvlx",40000,10000},
    {"1-5 Future City.lvlx",40000,10000},
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

local FREEZE_FRAMES = 50
local freezeTimer = 0
local Freeze

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

-- your handler can safely use Freeze now
function onPostNPCCollect(n, p)
    if not p or not n.isValid then return end
    if isPowerup(n.id) then
        if freezeTimer <= 0 then
            Freeze.push(false)
        end
        freezeTimer = math.max(freezeTimer, FREEZE_FRAMES)
    end
end

local function canHumanEndTurn(s)
    if not s then return false end
    if s.whoseTurn ~= 1 then return false end           -- only P1 ends P1's turn
    if cardGameFortune.anyAnimating and cardGameFortune.anyAnimating() then return false end
    if cardGameFortune.aiState and cardGameFortune.aiState.busy then return false end
    return true
end

-- later, define the table and its methods
Freeze = {count = 0, prev = false, savedVel = nil}

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
    if Freeze.count > 0 then
        Freeze.count = Freeze.count - 1
        if Freeze.count == 0 then
            Defines.levelFreeze = Freeze.prev
            if Freeze.savedVel then
                player.speedX, player.speedY = unpack(Freeze.savedVel)
            end
        end
    end
end


local function startFreeze(frames)
    if frames and frames > 0 then
        Freeze.push(false)             -- no need to save velocity for short timers
        freezeTimer = math.max(freezeTimer, frames)
    end
end

local VALID_KEY_FIELDS = {
    left=true, right=true, up=true, down=true,
    jump=true, altJump=true, run=true, altRun=true,
    dropItem=true, pause=true
}

local function swallowPlatformKeys()
    local k = player.keys
    -- only clear fields that exist and are supported
    for name,_ in pairs(VALID_KEY_FIELDS) do
        if k[name] ~= nil then k[name] = false end
    end
end



function onTick()
    -- drive the one-shot timer
    if freezeTimer > 0 then
        freezeTimer = freezeTimer - 1
        if freezeTimer == 0 then
            Freeze.pop()
        end
    end

    if endTurnCooldown > 0 then
        endTurnCooldown = endTurnCooldown - 1
        if endTurnCooldown == 0 then endTurnLatch = false end
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
local CARD_W, CARD_H = 66, 80
local CARD_GAP       = 2
local HAND_W         = (CARD_W * 6) + (CARD_GAP * 5)
local HAND_H         = 84

-- Discard + Description + Hover
local DISC_W,  DISC_H  = 72, HAND_H
local DESC_W,  DESC_H  = 240, HAND_H
local HOVER_W, HOVER_H = 260, 520

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

-- Can the player act on grid/hand?
local function canActNow()
    local s = cardGameFortune.peek()
    if not s or s.whoseTurn ~= 1 then return false end          -- only P1 acts
    if cardGameFortune.anyAnimating and cardGameFortune.anyAnimating() then return false end
    if cardGameFortune.aiState and cardGameFortune.aiState.busy then return false end
    return true
end


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
    if moved then cardGameFortune.sfx_cursorMove() end
    if moved then clampCursor(); moveTimer = MOVE_COOLDOWN end
end

local function enterHandIdle()
    UI.pending = nil
    selectedHandIndex = nil
    selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
    focus = "hand"
    centerCursor()
end

local function graveOpen(side)
    UI.modal = {
        kind   = "grave",
        side   = side or (UI.graveSide or 1),  -- 1=P1, 2=P2 (active pane)
        sel    = { [1]=1, [2]=1 },             -- selection index per side
        scroll = { [1]=0, [2]=0 },             -- scroll row offset per side
    }
    UI.graveSide = UI.modal.side
end

local function graveClose()
    UI.modal = nil
    UI.graveSide = UI.graveSide or 1
end

-- Return {def, owner} of highlighted grave entry (for hover panel)
local function graveHoverCard()
    local m = UI.modal
    if not (m and m.kind=="grave") then return nil end
    local s = cardGameFortune.peek()
    local side = m.side or 1
    local g = s and s.grave and s.grave[side] or {}
    local idx = m.sel[side] or 1
    local e = g[idx]
    if not e then return nil end
    return cardGameFortune.db[e.cardId], side
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

--Terrain Image
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

local _imgCache = {}
local function drawImageDim(path, x, y, w, h, alpha)
    if not path then return end
    local img = _imgCache[path]
    if img == nil then
        img = Graphics.loadImageResolved(path)
        _imgCache[path] = img
    end
    if not img then return end
    Graphics.drawBox{ x=x, y=y, width=w, height=h, color=Color(0,0,0,alpha or 0.5), priority=5 }
    Graphics.drawBox{ texture=img, x=x, y=y, width=w, height=h, priority=5.01 }
end


local function drawActionBar()
    local y = SCREEN_H - 32 -- bottom border height
    local x = BORDER
    local gap = 100
    for i,item in ipairs(UI.action.items) do
        local isHot  = (focus == "menu") and (i == UI.action.idx)
        local color  = isHot and Color(1,1,0,1) or Color(1,1,1,0.6)
        textplus.print{
            text = item.label,
            x = x + (i-1)*gap,
            y = y,
            font = minFont,
            xscale = 2, yscale = 2,
            color = color,
            priority = 9.95
        }
    end
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
local BADGE_ATK = tex("cardgame/attack.png")
local BADGE_DEF = tex("cardgame/defence.png")

local outlineWhite = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_W
}
local outlineRed   = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_R
}
local outlineBlue  = Sprite.box{
  width=CELL, height=CELL, texture=TX_FILL, borderwidth=2, bordertexture=TX_BORDER_B
}

-- ---- outline sprites (cached per color + inset) ----
local OUTLINE_CACHE = { red={}, blue={}, white={} }

local function getOutline(which, inset)
    inset = inset or 0
    local cache = OUTLINE_CACHE[which]
    local spr = cache[inset]
    if not spr then
        local texBorder = (which=="red")  and TX_BORDER_R
                       or (which=="blue") and TX_BORDER_B
                       or                     TX_BORDER_W
        spr = Sprite.box{
            width        = CELL - inset*2,
            height       = CELL - inset*2,
            texture      = TX_FILL,        -- transparent fill
            borderwidth  = 2,              -- try 1 if you want even thinner
            bordertexture= texBorder,
        }
        cache[inset] = spr
    end
    return spr
end

local function drawOutlineSprite(spr, x, y, prio)
    spr.x, spr.y = x, y
    spr:draw{priority = prio or 5.1}
end

-- which: "red"|"blue"|"white"; inset = pixels you want to tuck inward
local function outlineCell(c, r, which, prio, inset)
    inset = inset or 0
    local x = boardX + c*CELL + inset
    local y = boardY + r*CELL + inset
    drawOutlineSprite(getOutline(which, inset), x, y, prio)
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

--Icon loader
local function drawIcon(id, col, row)
    local card = cardGameFortune.db[id]
    if not card then return end
    local img = tex(card.icon or card.image)
    if not img then return end
    Graphics.drawImageWP(img, boardX + col*CELL, boardY + row*CELL, 5)
end

-- Convert a unit's (c,r) to screen XY, applying slide animation if present
local function unitDrawXY(c, r, u)
    local x = boardX + c*CELL
    local y = boardY + r*CELL
    if u and u._anim and u._anim.kind == "slide" then
        local A = u._anim
        local t = math.min(1, A.t / A.dur)
        if A.ease then t = A.ease(t) end
        local fromX = boardX + A.fromC*CELL
        local fromY = boardY + A.fromR*CELL
        local toX   = boardX + A.toC  *CELL
        local toY   = boardY + A.toR  *CELL
        x = fromX + (toX - fromX) * t
        y = fromY + (toY - fromY) * t
    end
    return x, y
end

-- Summon effects
local function drawSummonFX(cell, c, r, drawX, drawY)
    local fx = cell and cell._fx
    if not (fx and fx.kind=="summon") then return end

    -- normalized time 0..1 and fade
    local k = fx.t / math.max(1, fx.dur)  -- progress
    local a = 1 - k                        -- inverse progress for fading

    -- Smooth easing (same idea as your slide anim ease)
    local function ease(t) return t*t*(3 - 2*t) end
    local ke = ease(k)

    -- cell rect
    local x = drawX
    local y = drawY
    local w = CELL
    local h = CELL

    -- 1) Quick impact flash (first few frames)
    if fx.flash and fx.t < fx.flash then
        local flashA = (1 - (fx.t / fx.flash)) * 0.75
        Graphics.drawBox{
            x=x, y=y, width=w, height=h,
            color = Color(1,1,1, flashA),
            priority = 5.13
        }
    end

    -- 2) Pulsing inset rings (owner-colored), eased
    local baseInset = 3
    local pulseMax  = 3            -- how wide the pulse starts
    local inset1    = baseInset + math.floor(pulseMax * (1 - ke))   -- 6 → 3 over time
    local inset2    = inset1 + 2

    local which = (cell.owner==1) and "red" or "blue"
    local ring1 = getOutline(which, inset1)
    ring1.x, ring1.y = x + inset1, y + inset1
    ring1:draw{priority=5.12, color=Color(1,1,1, 0.70 * a)}

    local ring2 = getOutline(which, inset2)
    ring2.x, ring2.y = x + inset2, y + inset2
    ring2:draw{priority=5.115, color=Color(1,1,1, 0.40 * a)}

    -- 3) Soft “core glow” that expands and fades
    do
        local glowA   = 0.35 * a
        local pad     = math.floor(6 + 6*ke) -- expands slightly
        Graphics.drawBox{
            x = x + pad, y = y + pad,
            width  = w - pad*2,
            height = h - pad*2,
            color  = Color(1,1,1, glowA),
            priority = 5.11
        }
    end

    -- 4) Sparkles drifting outward (uses fx.sparks seeded in engine)
    local cx = x + w*0.5
    local cy = y + h*0.5
    if fx.sparks then
        for _,p in ipairs(fx.sparks) do
            local pp = math.min(1, p.t / math.max(1, p.dur))
            local fad = 1 - pp
            -- drift outward and slightly accelerate
            local driftX = p.x * (0.6 + 0.7*pp)
            local driftY = p.y * (0.6 + 0.7*pp)
            local sx = cx + driftX
            local sy = cy + driftY
            local sz = 2 + math.floor(2 * (1-pp))  -- shrink over time

            Graphics.drawBox{
                x = sx - sz*0.5, y = sy - sz*0.5,
                width = sz, height = sz,
                color = Color(1,1,1, 0.85 * fad),
                priority = 5.14
            }
        end
    end
end

local function drawHitFX(cell, drawX, drawY)
    local hf = cell and cell._hitfx
    if not (hf and hf.kind == "hit") then return end

    -- fade from 1 → 0 over [0..dur]
    local t = math.min(1, (hf.t or 0) / (hf.dur or 12))
    local alpha = 1 - t

    -- a tiny shake so hits feel tactile
    local sh = hf.shake or 0
    local ox = (math.random(-sh, sh))
    local oy = (math.random(-sh, sh))

    Graphics.drawBox{
        x        = drawX + ox,
        y        = drawY + oy,
        width    = 32, height = 32,
        color    = Color(1,1,1, alpha * 0.5), -- white flash
        priority = 5.25,                      -- over the sprite, under rings
    }
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
local COL_PLUS  = COL_PLUS  or {0, 210, 90, 255}
local COL_MINUS = COL_MINUS or {210, 60, 60, 255}


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
local MENU_MUSIC = "music/FFV/107 The Battle.spc"
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

-- ===== Board mode glue (single source of truth) =====
BOARD_OPEN = BOARD_OPEN or false
local boardActive = false

local function enterBoardMode()
    if boardActive then return end
    boardActive = true
    if Freeze and Freeze.push then Freeze.push(true) end

    if cardGameFortune and not cardGameFortune.isOpen() then
        local s = cardGameFortune.peek()
        if not (s and s.board) then cardGameFortune.newMatch(12345) end
        cardGameFortune.open()
        -- UI defaults
        focus="hand"; summonPos="attack"; selectedHandIndex=nil
        local s2 = cardGameFortune.peek()
        local h = (s2 and s2.hands and s2.hands[1]) or {}
        for i=1,5 do if h[i] then selectedHandIndex=i; break end end
        centerCursor(); moveTimer = 0
    end

    swapToMenuMusic()
end

local function exitBoardMode()
    if not boardActive then return end
    boardActive = false
    if Freeze and Freeze.pop then Freeze.pop() end
    if cardGameFortune and cardGameFortune.close then cardGameFortune.close() end
    restoreSectionMusic()
end

function OpenBoardForDuel(npcDeckID)
    cardGameFortune.beginNPCBattle(npcDeckID)
    BOARD_OPEN = true
    cardGameFortune.sfx_matchStart()
    enterBoardMode()
end

function CloseBoard()
    BOARD_OPEN = false
    exitBoardMode()  -- your Freeze.pop/close/music restore
end

function CloseBoardWithNPCLine(npcKey, text)
    CloseBoard()

    -- show a line from the opponent one frame later (prevents input bleed)
    Routine.run(function()
        Routine.waitFrames(1)
        local speaker = (cardGameFortune.challengers[npcKey] or {}).name or "Opponent"

        -- littleDialogue may already be required elsewhere; be tolerant:
        local ld = littleDialogue or require("littleDialogue")

        local box = ld.create{
            target = player,  -- or your NPC instance if you track it
            text   = ("<boxStyle ml><speakerName %s>%s"):format(speaker, text),
        }
        if box and box.show then box:show() end
    end)
end



local function enterMenu()
    prevFocus = (focus == "menu") and (prevFocus or "hand") or focus
    focus = "menu"
end

local function exitMenu()
    focus = (prevFocus and prevFocus ~= "menu") and prevFocus or "hand"
end

-- === Action bar router ===
function cardGameFortune.uiInvokeAction(id)
    -- always leave the menu when an action is chosen
    if focus == "menu" then
        if exitMenu then exitMenu() end
    end

    if UI.modal and UI.modal.kind == "grave" then graveClose() end

    -- clear any half-done input
    UI.pending = nil

    if id == "hand" then
        focus = "hand"
        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
        cardGameFortune.sfx_accept()

    elseif id == "board" then
        focus = "board"
        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
        if centerCursor then centerCursor() end
        cardGameFortune.sfx_accept()

    elseif id == "guide" then
        -- open/close your guide modal (or toggle a flag you already draw)
        UI.modal = (UI.modal == "guide") and nil or "guide"
        cardGameFortune.sfx_cancel()

    elseif id == "grave" then
        graveOpen(UI.graveSide or 1)
        cardGameFortune.sfx_cancel()

    elseif id == "end" then
        local s = cardGameFortune.peek()
        if canHumanEndTurn and s and canHumanEndTurn(s) and not endTurnLatch then
            endTurnPrevTurn = s.whoseTurn
            endTurnLatch    = true
            endTurnCooldown = 12
            cardGameFortune.endTurn()

            -- reset UI for next player
            selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
            focus, summonPos = "hand", "attack"

            local ns = cardGameFortune.peek()
            selectedHandIndex = nil
            local h2 = (ns and ns.hands and ns.hands[ns.whoseTurn]) or {}
            for i=1,5 do if h2[i] then selectedHandIndex = i; break end end

            if centerCursor then centerCursor() end
            cardGameFortune.sfx_cancel()
        else
            cardGameFortune.sfx_buzzer()
        end

    elseif id == "restart" then
        cardGameFortune.newMatch()   
        cardGameFortune.open()
        focus, summonPos = "hand", "attack"
        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
        selectedHandIndex = nil
        local s = cardGameFortune.peek()
        local h = (s and s.hands and s.hands[1]) or {}
        for i=1,5 do if h[i] then selectedHandIndex = i; break end end
        if centerCursor then centerCursor() end
        cardGameFortune.sfx_cancel()

    elseif id == "giveup" then
        if cardGameFortune.concede then cardGameFortune.concede(1) end
        -- npc key you started the duel with; change if you track it elsewhere:
        CloseBoardWithNPCLine(STATE and STATE.opponentKey or "koopa_card_man",
                            "Good duel. Come back anytime!")
        cardGameFortune.sfx_buzzer()

    else
        -- unknown id: beep
        cardGameFortune.sfx_buzzer()
    end
end


-- bundle the many locals so big functions only capture this one table
CFG = {
  -- constants
  BORDER=BORDER, SCREEN_W=SCREEN_W, SCREEN_H=SCREEN_H, BOARD_SIZE=BOARD_SIZE,
  CELL=CELL, GRID_COLS=GRID_COLS, GRID_ROWS=GRID_ROWS,
  CARD_W=CARD_W, CARD_H=CARD_H, CARD_GAP=CARD_GAP,
  handX=handX, handY=handY, discX=discX, discY=discY,
  descX=descX, descY=descY, hoverX=hoverX, hoverY=hoverY,
  HOVER_W=HOVER_W, HOVER_H=HOVER_H, boardX=boardX, boardY=boardY,
  RIGHT_W=RIGHT_W, rightPanelX=rightPanelX, rightPanelY=rightPanelY,

  -- frequently used helpers (functions)
  tex=tex, box=box, label=label, wrapIntoLines=wrapIntoLines,
  terrImg=terrImg, drawCardInfo=drawCardInfo, getOutline=getOutline,
}

-- top-level, above updateBoardControls():
local function safeBoardCell(s, c, r)
    local b = s and s.board
    if not b then return nil end
    local row = b[r]
    return row and row[c] or nil
end


local function updateBoardControls()
        ----------------------------------------------------
        -- All interactive logic only when the board is open
        ----------------------------------------------------
        swallowPlatformKeys()

        if BOARD_OPEN then
        local s      = cardGameFortune.peek()
        if not s or not s.board then return end
        local aiBusy = cardGameFortune.aiState and cardGameFortune.aiState.busy
        local myTurn = (s and s.whoseTurn == 1 and not aiBusy)

        -- (Keep the latch in sync while open, too)
        if endTurnLatch then
            if s and s.whoseTurn ~= endTurnPrevTurn then
                endTurnLatch, endTurnCooldown = false, 0
            elseif endTurnCooldown > 0 then
                endTurnCooldown = endTurnCooldown - 1
                if endTurnCooldown == 0 then endTurnLatch = false end
            end
        end

        -- Start AI turn if it's P2 and AI isn't already running
        if s and s.whoseTurn == 2 and not aiBusy then
            if cardGameFortune.aiBeginTurn then cardGameFortune.aiBeginTurn() end
        end
        -- Run one AI step when ready
        if cardGameFortune.aiUpdate then cardGameFortune.aiUpdate() end

        -- If AI just ended, reset P1 UI cleanly
        if cardGameFortune.aiJustEnded then
            selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
            focus, summonPos = "hand", "attack"

            selectedHandIndex = nil
            local h = (s and s.hands and s.hands[1]) or {}
            for i=1,5 do if h[i] then selectedHandIndex = i; break end end

            centerCursor()
            cardGameFortune.aiJustEnded = false
            UI.pending = nil
        end

        if UI.modal and UI.modal.kind == "grave" then
            if player.rawKeys.run == KEYS_PRESSED then
                    graveClose()
                    return
            end
            return
        end

        -- Cancel (B/Esc)
        if UI.pending and player.rawKeys.altJump == KEYS_PRESSED then
            UI.pending = nil
        end

        -- Confirm (A/Jump or Enter)
        if UI.pending and (player.rawKeys.jump == KEYS_PRESSED) then
            local p = UI.pending
            if p.kind == "summon" and p.c and p.r then
                local ok = cardGameFortune.playFromHand(1, p.fromHand, p.c, p.r, p.pos)
                if ok then
                    enterHandIdle()          -- ⬅️ fully resets to hand & removes summon ring
                    cardGameFortune.sfx_accept()
                    return
                end

            elseif p.kind == "move" then
                local ok,reason = cardGameFortune.moveUnit(p.fromC, p.fromR, p.toC, p.toR)
                if ok then
                    selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                    cardGameFortune.sfx_accept()
                else
                    Misc.dialog("Move failed: "..tostring(reason or "unknown"))
                    -- keep selection so you can try another tile
                end
                UI.pending = nil
                return

            elseif p.kind == "attack" then
                cardGameFortune.resolveBattle(p.fromC, p.fromR, p.toC, p.toR)
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
            elseif p.kind == "approachAttack" then
                local moved = cardGameFortune.moveUnit(p.fromC, p.fromR, p.stepC, p.stepR, {keepAttack=true})
                if moved then
                    cardGameFortune.resolveBattle(p.stepC, p.stepR, p.toC, p.toR)
                    selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                else
                    cardGameFortune.sfx_buzzer()
                end
            end
            UI.pending = nil
        end


        ------------------------------------------------
        -- Toggle hand <-> board (not while aiming)
        ------------------------------------------------
        if focus ~= "aim" and player.rawKeys.altJump == KEYS_PRESSED then
            if myTurn then
            if UI.pending then end
            focus = (focus == "hand") and "board" or "hand"
            if focus == "board" then centerCursor() end
            cardGameFortune.sfx_cancel()
            end
        end

        -----------------------------------------------------------------
        -- End Turn (Start): only human, on their turn, AI idle, gated
        -----------------------------------------------------------------
        if player.rawKeys.pause == KEYS_PRESSED then
            if UI.pending then end
            local ss = cardGameFortune.peek()
            if canHumanEndTurn(ss) and (not endTurnLatch) and cardGameFortune.endTurn then
                endTurnPrevTurn = ss.whoseTurn
                endTurnLatch    = true
                endTurnCooldown = 12

                cardGameFortune.endTurn()

                -- reset UI for next player (likely P2/AI)
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                focus, summonPos = "hand", "attack"

                local ns = cardGameFortune.peek()
                selectedHandIndex = nil
                local h2 = (ns and ns.hands and ns.hands[ns.whoseTurn]) or {}
                for i=1,5 do if h2[i] then selectedHandIndex = i; break end end

                centerCursor()
                cardGameFortune.sfx_cancel()
                UI.pending = nil
            else
                cardGameFortune.sfx_buzzer()
            end
        end

        --------------------------------
        -- ========= HAND mode =========
        --------------------------------
        if focus == "hand" then
            if player.rawKeys.dropItem == KEYS_PRESSED then enterMenu(); return end
            if UI.pending then end
            if myTurn then
                local function handCycle(dir)
                    local s2 = cardGameFortune.peek()
                    if not selectedHandIndex then
                        for i=1,5 do if (s2.hands[1] or {})[i] then selectedHandIndex = i; break end end
                        if not selectedHandIndex then return end
                    end
                    local i, start = selectedHandIndex, selectedHandIndex
                    repeat
                        i = ((i - 1 + dir + 6) % 6) + 1
                        if (s2.hands[1] or {})[i] then selectedHandIndex = i; cardGameFortune.sfx_cursorMove(); break end
                    until i == start
                end

                if moveTimer > 0 then moveTimer = moveTimer - 1 end
                local stepped = false
                if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then handCycle(-1); stepped = true end
                if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then handCycle( 1); stepped = true end
                if stepped then moveTimer = MOVE_COOLDOWN end

                if player.rawKeys.run == KEYS_PRESSED then
                    graveOpen(UI.graveSide or 1)
                    return
                end

                -- A) hand -> aim
                if player.rawKeys.jump == KEYS_PRESSED then
                    if not canActNow() then
                        cardGameFortune.sfx_buzzer()
                    else
                        local s3 = cardGameFortune.peek()
                        if selectedHandIndex == nil then
                            for i=1,5 do if (s3.hands[1] or {})[i] then selectedHandIndex = i; break end end
                        end
                        if selectedHandIndex and (s3.hands[1] or {})[selectedHandIndex] then
                            focus = "aim"
                            centerCursor()
                            cardGameFortune.sfx_accept()
                        else
                            cardGameFortune.sfx_cancel()
                        end
                    end
                end

                -- B) small hand reset if desired
                if player.rawKeys.altRun == KEYS_PRESSED then
                    selectedHandIndex = nil
                    summonPos = "attack"
                end
            end

        --------------------------------
        -- ========= AIM mode ==========
        --------------------------------
        elseif focus == "aim" then
            if player.rawKeys.dropItem == KEYS_PRESSED then
                UI.pending = nil
                enterMenu()
                return
            end
            if UI.pending then end
            if moveTimer > 0 then moveTimer = moveTimer - 1 end
            local moved = false
            if not UI.pending then
                if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c - 1, 0, GRID_COLS-1); moved = true end
                if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c + 1, 0, GRID_COLS-1); moved = true end
                if player.rawKeys.up    == KEYS_PRESSED or (player.rawKeys.up    == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r - 1, 0, GRID_ROWS-1); moved = true end
                if player.rawKeys.down  == KEYS_PRESSED or (player.rawKeys.down  == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r + 1, 0, GRID_ROWS-1); moved = true end
                if moved then cardGameFortune.sfx_cursorMove() end
                if moved then moveTimer = MOVE_COOLDOWN end
            end

            if player.rawKeys.run == KEYS_PRESSED then
                summonPos = (summonPos == "attack") and "defense" or "attack"
                cardGameFortune.sfx_cancel()
            end

            if player.rawKeys.altJump == KEYS_PRESSED then
                UI.pending = nil                 
                selectedHandIndex = nil          
                focus = "hand"                  
                cardGameFortune.sfx_cancel()
                return
            end

            if player.rawKeys.jump == KEYS_PRESSED and selectedHandIndex ~= nil then
                local s4   = cardGameFortune.peek()
                local hand = s4 and s4.hands and s4.hands[1]
                local cid  = hand and hand[selectedHandIndex]
                if not cid then cardGameFortune.sfx_cancel(); return end
                if not canActNow() then cardGameFortune.sfx_cancel(); return end

                local def  = cardGameFortune.db[cid]
                local cost = (def and def.summoncost) or 0
                if (s4.energy and (s4.energy[1] or 0) < cost) then
                    cardGameFortune.sfx_buzzer()        
                    return 
                end

                -- Start a pending summon (confirm will execute later)
                UI.pending = {
                    kind    = "summon",
                    cardId  = cid,
                    fromHand= selectedHandIndex,
                    pos     = (summonPos or "attack"),
                    c       = cursor.c,
                    r       = cursor.r,
                }
                cardGameFortune.sfx_accept()
            end

            if player.rawKeys.altRun == KEYS_PRESSED then
                selectedHandIndex = nil
                focus = "hand"
                cardGameFortune.sfx_cancel()
            end

        ------------------------------------
        -- ========= BOARD (inspect) =======
        ------------------------------------
        elseif focus == "board" then
            if player.rawKeys.dropItem == KEYS_PRESSED then enterMenu(); return end
            if UI.pending then end
            if moveTimer > 0 then moveTimer = moveTimer - 1 end
            local moved = false
            if not UI.pending then
                if player.rawKeys.left  == KEYS_PRESSED or (player.rawKeys.left  == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c - 1, 0, GRID_COLS-1); moved = true end
                if player.rawKeys.right == KEYS_PRESSED or (player.rawKeys.right == KEYS_DOWN and moveTimer == 0) then cursor.c = clamp(cursor.c + 1, 0, GRID_COLS-1); moved = true end
                if player.rawKeys.up    == KEYS_PRESSED or (player.rawKeys.up    == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r - 1, 0, GRID_ROWS-1); moved = true end
                if player.rawKeys.down  == KEYS_PRESSED or (player.rawKeys.down  == KEYS_DOWN and moveTimer == 0) then cursor.r = clamp(cursor.r + 1, 0, GRID_ROWS-1); moved = true end
                if moved then cardGameFortune.sfx_cursorMove() end
                if moved then moveTimer = MOVE_COOLDOWN end
            end

            if player.rawKeys.altRun == KEYS_PRESSED then
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                focus = "hand"
                cardGameFortune.sfx_cancel()
            end

            local sb = cardGameFortune.peek()
            local c, r = cursor.c, cursor.r
            local cell = sb.board[r] and sb.board[r][c]

            -- Fortify to DEF (RUN) while friendly, movable non-leader is selected
            if selectedUnit and canActNow() then
                local u = sb.board[selectedUnit.r] and sb.board[selectedUnit.r][selectedUnit.c]
                if u and not u.isLeader and not u.summoningSickness and not u.hasMoved and u.owner == 1 then
                    if player.rawKeys.run == KEYS_PRESSED then
                        local ok = cardGameFortune.fortifyToDefense(selectedUnit.c, selectedUnit.r)
                        cardGameFortune.sfx_accept()
                        if ok then selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil end
                    end
                end
            end

            -- Select / act (Jump)
            if player.rawKeys.jump == KEYS_PRESSED then
                if not canActNow() then
                    
                else
                    local s5 = cardGameFortune.peek()
                    if not (s5 and s5.board) then return end  -- extra safety

                    local curCell = safeBoardCell(s5, c, r)

                    if selectedUnit then
                        -- verify selected still exists
                        local su = selectedUnit
                        local unitCell = (su and safeBoardCell(s5, su.c, su.r)) or nil
                        if not unitCell then
                            selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                            cardGameFortune.sfx_buzzer(); return
                        end

                        local def     = cardGameFortune.db[unitCell.cardId] or {}
                        local atktype = def.atktype or "normal"
                        local meleeAdj = (atktype == "normal") and cardGameFortune.isMeleeInRange(su, su.c, su.r, c, r)

                        -- 1) plain move?
                        if legalMoveSet and legalMoveSet[r] and legalMoveSet[r][c] and (not safeBoardCell(s5, c, r)) then
                            UI.pending = { kind="move", fromC=su.c, fromR=su.r, toC=c, toR=r }
                            cardGameFortune.sfx_accept(); return

                        -- 2) legal attack (already pre-marked)
                        elseif (not su.isLeader) and legalAttackSet and legalAttackSet[r] and legalAttackSet[r][c] then
                            -- Target is pre-marked as legal, so just execute it
                            -- The engine already validated diagonal/knight/approach feasibility
                            if atktype ~= "normal" then
                                -- Ranged: direct strike
                                UI.pending = { kind="attack", fromC=su.c, fromR=su.r, toC=c, toR=r }
                                cardGameFortune.sfx_accept(); return
                            else
                                -- Melee: check if we're already adjacent (direct strike)
                                local unitCell = s5.board[su.r] and s5.board[su.r][su.c]
                                local meleeAdj = unitCell and cardGameFortune.isMeleeInRange(unitCell, su.c, su.r, c, r)
                                if meleeAdj then
                                    UI.pending = { kind="attack", fromC=su.c, fromR=su.r, toC=c, toR=r }
                                    cardGameFortune.sfx_accept(); return
                                else
                                    -- Need to approach first
                                    local stepC, stepR = cardGameFortune.pickApproachDestination(su.c, su.r, c, r)
                                    if stepC and stepR then
                                        UI.pending = {
                                            kind  = "approachAttack",
                                            fromC = su.c, fromR = su.r,
                                            stepC = stepC, stepR = stepR,
                                            toC   = c,     toR   = r,
                                        }
                                        cardGameFortune.sfx_accept(); return
                                    else
                                        -- Approach failed - show why
                                        cardGameFortune.sfx_buzzer()
                                        Misc.dialog("Cannot approach target - no valid attack position reachable")
                                        return
                                    end
                                end
                            end
                        end

                        -- 2.5) enemy clicked BUT not pre-marked → live approach fallback (covers leaders too)
                        do
                            local tgt = safeBoardCell(s5, c, r)
                            if tgt and tgt.owner and (tgt.owner ~= s5.whoseTurn) then
                                local _, dist = cardGameFortune.legalMovesFrom(su.c, su.r, { forThreat=true, returnDist=true })
                                local startTerr = cardGameFortune.terrainAt(su.c, su.r)
                                local movBonus  = (cardGameFortune.terrainMovementBonus and
                                                cardGameFortune.terrainMovementBonus(def.subtype2, startTerr)) or 0
                                local maxSteps  = math.max(0, (def.movement or 0) + movBonus)
                                local budget    = math.max(0, maxSteps - 1)

                                -- movementtype-aware melee origins + safe sparse read
                                local def = cardGameFortune.db[unitCell.cardId] or {}
                                local mt  = (def.movementtype or def.movetype) or "normal"

                                -- use the same origin set your attack uses (not generic DIR4)
                                local deltas = (cardGameFortune._attackOriginDeltasFor and
                                                cardGameFortune._attackOriginDeltasFor(mt))
                                            or cardGameFortune.DIR4

                                local function costAt(cc, rr)
                                    local row = dist[rr]; return row and row[cc] or math.huge
                                end

                                local bestC, bestR, bestCost
                                for _,d in ipairs(deltas) do
                                    local ac, ar = c + d[1], r + d[2]
                                    if cardGameFortune.inBounds(ac, ar)
                                    and not safeBoardCell(s5, ac, ar) then
                                        local cost = costAt(ac, ar)
                                        if legalMoveSet and legalMoveSet[ar] and legalMoveSet[ar][ac] then
                                            if not bestCost or cost < bestCost then
                                                bestC, bestR, bestCost = ac, ar, cost
                                            end
                                        end
                                    end
                                end

                                if bestC and bestR then
                                    UI.pending = {
                                        kind  = "approachAttack",
                                        fromC = su.c, fromR = su.r,
                                        stepC = bestC, stepR = bestR,
                                        toC   = c,     toR   = r,
                                    }
                                    cardGameFortune.sfx_accept(); return
                                else
                                    do
                                        local s5 = cardGameFortune.peek()
                                        local su = selectedUnit
                                        local u  = s5.board[su.r] and s5.board[su.r][su.c]
                                        local isLeader = u and u.isLeader
                                        -- explain precisely why it failed (budget/occupied/unreach)
                                        cardGameFortune.debugExplainSelection(su, c, r, legalMoveSet, legalAttackSet)
                                        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                                        cardGameFortune.sfx_buzzer(); return
                                    end
                                end
                            end
                        end

                        -- 3) nothing else matched → optional explain for empty illegal tiles
                        if not curCell then
                            local _, dist = cardGameFortune.legalMovesFrom(su.c, su.r, { forThreat=true, returnDist=true })
                            local row  = dist[r]
                            local cost = row and row[c] or nil
                            Misc.dialog(("Empty tile (%d,%d) not in legalMoveSet.\ntrueCost=%s"):format(c, r, tostring(cost)))
                        end
                        selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                        cardGameFortune.sfx_buzzer(); return

                    else
                        -- Select our own piece (leader OR unit)
                        if curCell and curCell.owner == s5.whoseTurn then
                            selectedUnit = { c=c, r=r, isLeader = curCell.isLeader }
                            if curCell.isLeader then
                                legalMoveSet   = cardGameFortune.legalLeaderMovesFrom(c, r)
                                legalAttackSet = nil
                            else
                                legalMoveSet   = cardGameFortune.legalMovesFrom(c, r)
                                legalAttackSet = cardGameFortune.legalAttacksFrom(c, r)
                            end
                            cardGameFortune.sfx_accept()
                        end
                    end
                end
            end



            -- Cancel with SpinJump
            if player.rawKeys.altJump == KEYS_PRESSED then
                selectedUnit, legalMoveSet, legalAttackSet = nil, nil, nil
                cardGameFortune.sfx_cancel()
            end

            ---Menu Focus 
            elseif focus == "menu" then
                local used = false
                if player.rawKeys.left  == KEYS_PRESSED then
                    UI.action.idx = (UI.action.idx - 2) % #UI.action.items + 1; used = true
                end
                if player.rawKeys.right == KEYS_PRESSED then
                    UI.action.idx = (UI.action.idx)     % #UI.action.items + 1; used = true
                end
                if player.rawKeys.jump == KEYS_PRESSED or player.rawKeys.run == KEYS_PRESSED then
                    local it = UI.action.items[UI.action.idx]
                    if it then cardGameFortune.uiInvokeAction(it.id) end
                    used = true
                end
                if player.rawKeys.dropItem == KEYS_PRESSED then
                    exitMenu(); used = true
                end
                if used then return 
            end
        end -- focus branch
    end -- if BOARD_OPEN
end -- function end

-- ===========================
-- INPUT
-- ===========================



function onInputUpdate()

        -- Disable map toggle on overworld
    if Level.filename() == "map.lvlx" or Level.isOverworld then
        player.dropItemKeyPressing = false
    end

    -- housekeeping to keep end-turn latch sane (safe even if closed)
    do
        local s = cardGameFortune.peek()
        if endTurnLatch then
            if s and s.whoseTurn ~= endTurnPrevTurn then
                endTurnLatch, endTurnCooldown = false, 0
            elseif endTurnCooldown > 0 then
                endTurnCooldown = endTurnCooldown - 1
                if endTurnCooldown == 0 then endTurnLatch = false end
            end
        end
    end

    -- glue
    if BOARD_OPEN and not boardActive then
        enterBoardMode()
    elseif (not BOARD_OPEN) and boardActive then
        exitBoardMode()
    end

    -- drive the board + block platforming input
    if BOARD_OPEN then
        swallowPlatformKeys()
        updateBoardControls()
    end
end


-- Draw one card’s info into the hover panel.
local function drawCardInfo(def, hoverX, yy, HOVER_W, pos, summonPos, extras)
    if not def then return yy end

    -- name row
    local nameText = tostring(def.name or "Unknown")
    local iconW, gap = 16, 2
    local wTotal = iconW + gap + (#nameText * 16)
    local function centerRowWidth(w) return (hoverX + HOVER_W*0.5) - math.floor(w/2) end
    local x = centerRowWidth(wTotal)
    Graphics.drawImageWP(Graphics.loadImageResolved("cardgame/name.png"), x, yy-6, 5)
    textplus.print{ text=nameText, x=x+iconW+gap, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1.0,0.84,0.3,1} }
    yy = yy + 32

    -- ATK/DEF (effective if a tile position was provided)
    local atkText, defText
    if pos and pos.c and pos.r then
        local eATK,eDEF,_,delta = cardGameFortune.getEffectiveStats(def, pos.c, pos.r)
        local bump = (delta ~= 0) and (" ("..((delta>0) and "+" or "")..delta..")") or ""
        atkText = "ATK: "..eATK..bump
        defText = "DEF: "..eDEF..bump
    else
        atkText = "ATK: "..tostring(def.atk or 0)
        defText = "DEF: "..tostring(def.def or 0)
    end

    do
        local iconW2, gap2, colGap = 16, 2, 24
        local wATK = iconW2 + gap2 + (#atkText * 16)
        local wDEF = iconW2 + gap2 + (#defText * 16)
        local totW = wATK + colGap + wDEF

        local x1 = centerRowWidth(totW)
        Graphics.drawImageWP(Graphics.loadImageResolved("cardgame/attack.png"),  x1, yy-6, 5)
        textplus.print{ text=atkText, x=x1+iconW2+gap2, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1,0.3,0.3,1} }

        local x2 = centerRowWidth(totW) + wATK + colGap
        Graphics.drawImageWP(Graphics.loadImageResolved("cardgame/defence.png"), x2, yy-6, 5)
        textplus.print{ text=defText, x=x2+iconW2+gap2, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={0.4,0.6,1,1} }
    end
    yy = yy + 32

    -- any caller-provided extra lines (must return the next yy)
    if extras then yy = extras(yy) end

    -- movement, type/tags, cost, description
    textplus.print{ text=("MOV: "..tostring(def.movementtype or "normal").."    RANGE: "..tostring(def.movement or 0)),
                    x=hoverX+8, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={0.91,0.73,0.55,1} }
    yy = yy + 32
    textplus.print{ text=("Type: "..tostring(def.type or "?").."   atkType: "..tostring(def.atktype or "?")),
                    x=hoverX+8, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1,1,1,0.85} }
    yy = yy + 32
    textplus.print{ text=("Tags: "..tostring(def.subtype1 or "-").."/"..tostring(def.subtype2 or "-")),
                    x=hoverX+8, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1,1,1,0.85} }
    yy = yy + 32
    if def.summoncost or def.deckcost then
        textplus.print{ text=("Cost: "..tostring(def.summoncost or 0).." / "..tostring(def.deckcost or 0)),
                        x=hoverX+8, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1.0,0.84,0.3,1} }
        yy = yy + 32
    end
    -- description (wrapped)
    local function wrapIntoLines(str, maxPixelWidth, maxLines)
        local maxChars = math.max(1, math.floor(maxPixelWidth / 16))
        local out, line = {}, ""
        for word in tostring(str or ""):gmatch("%S+") do
            if line == "" then line = word
            elseif #line + 1 + #word <= maxChars then line = line.." "..word
            else out[#out+1] = line; line = word; if maxLines and #out >= maxLines then break end
            end
        end
        if (not maxLines or #out < maxLines) and line ~= "" then out[#out+1] = line end
        return out
    end
    local lines = wrapIntoLines(def.description or "", (HOVER_W-16) - 8, 8)
    for i=1,#lines do
        textplus.print{ text=lines[i], x=hoverX+10, y=yy, priority=5, font=minFont, xscale=2, yscale=2, color={1,1,1,1} }
        yy = yy + 32
    end

    return yy
end


-- ===========================
-- HUD DRAW
-- ===========================

function onHUDDraw()
    if not BOARD_OPEN or not SHOW_LAYOUT then return end

    -- pull from CFG into locals (these locals are *inside* this function)
    local BORDER, SCREEN_W, SCREEN_H = CFG.BORDER, CFG.SCREEN_W, CFG.SCREEN_H
    local BOARD_SIZE, CELL = CFG.BOARD_SIZE, CFG.CELL
    local GRID_COLS, GRID_ROWS = CFG.GRID_COLS, CFG.GRID_ROWS
    local CARD_W, CARD_H, CARD_GAP = CFG.CARD_W, CFG.CARD_H, CFG.CARD_GAP
    local handX, handY = CFG.handX, CFG.handY
    local hoverX, hoverY, HOVER_W, HOVER_H = CFG.hoverX, CFG.hoverY, CFG.HOVER_W, CFG.HOVER_H
    local boardX, boardY = CFG.boardX, CFG.boardY
    local tex, box, label, terrImg = CFG.tex, CFG.box, CFG.label, CFG.terrImg

    STATE.boardX, STATE.boardY = boardX, boardY
    STATE.CELL = CELL

    -- Movement/Summoning Animation call:
    if cardGameFortune.stepAnimations then cardGameFortune.stepAnimations() end
    if cardGameFortune.stepFX then cardGameFortune.stepFX() end

    local function drawDeathFX()
        local s = STATE; if not (s and s.deathFX) then return end
        for _,f in ipairs(s.deathFX) do
            local t, dur = f.t or 0, f.dur or 1
            local x = (STATE.boardX or 0) + (f.c * CFG.CELL)
            local y = (STATE.boardY or 0) + (f.r * CFG.CELL)

            local fade = 1 - (t / dur)
            if fade > 0 then
                local blink = (f.flashes and f.flashes > 0) and ((math.floor(t/3) % 2) == 0)
                local alpha = fade * (blink and 1.0 or 0.75)

                if f.img then
                    local tex = CFG.tex(f.img)
                    if tex then
                        Graphics.drawBox{
                            texture = tex, x = x, y = y, width = 32, height = 32,
                            color = Color(1,1,1,alpha), priority = 5.18,
                        }
                    else
                        Graphics.drawBox{ x=x, y=y, width=32, height=32,
                            color=Color(1,1,1,alpha), priority=5.18 }
                    end
                else
                    Graphics.drawBox{ x=x, y=y, width=32, height=32,
                        color=Color(1,1,1,alpha), priority=5.18 }
                end
            end
        end
    end


    -- top HP bar
    drawHPBarTop()

    local s  = cardGameFortune.peek()
    local g1 = (s and s.grave and s.grave[1]) or {}
    local g2 = (s and s.grave and s.grave[2]) or {}

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
                -- one compute per cell
                local drawX, drawY = unitDrawXY(c, r, cell)

                if cell.isLeader then
                    local ltex = tex((cell.owner==1) and "cardgame/leader_p1.png" or "cardgame/leader_p2.png")
                    if ltex then Graphics.drawImageWP(ltex, drawX, drawY, 5.0) end
                    drawSummonFX(cell, c, r, drawX, drawY)
                    cardGameFortune.drawHitFX(cell, drawX, drawY)
                    drawDeathFX()
                else
                    local def = cell.cardId and cardGameFortune.db[cell.cardId]
                    if def and def.icon then
                        local itex = tex(def.icon)
                        if itex then Graphics.drawImageWP(itex, drawX, drawY, 5.0) end
                        drawSummonFX(cell, c, r, drawX, drawY)
                        cardGameFortune.drawHitFX(cell, drawX, drawY)
                        drawDeathFX()

                        -- stance badge (image)
                        do
                            local isDef = (cell.pos == "defense")
                            local img   = isDef and BADGE_DEF or BADGE_ATK
                            if img then
                                -- fade-in for first N frames after summon
                                local fadeFrames = 10
                                local alpha = 1.0
                                local fx = cell._fx
                                if fx and fx.kind == "summon" and fx.t < fadeFrames then
                                    local t = fx.t / fadeFrames
                                    -- smoothstep ease for a softer ramp
                                    t = t * t * (3 - 2 * t)
                                    alpha = t
                                end

                                -- anchor: bottom-right of the cell (your +54 placement)
                                local bx = drawX + 54 - math.floor(img.width  * 0.5)
                                local by = drawY + 54 - math.floor(img.height * 0.5)

                                Graphics.drawBox{
                                    texture = img,
                                    x = bx, y = by,
                                    width = img.width, height = img.height,
                                    color = Color(1,1,1, alpha),     -- <- fade-in here
                                    priority = 5.2,
                                }
                            end
                        end
                    end 
                end 
                -- owner outline (P1 red / P2 blue)
                outlineCell(c, r, (cell.owner==1) and "red" or "blue", 5.1, 3)
            end 
        end 
    end 

    cardGameFortune.drawDeathFX(boardX, boardY, 5.06)


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

    -- hand panel
    Graphics.drawBox{
        x=handX-8, y=handY+22, width=(CARD_W+CARD_GAP)*6 - CARD_GAP + 16, height=CARD_H+20,
        color=Color(0,0,0,0.35), priority=5
    }
    local hx, hy = handX, handY-2
    for i=1,5 do
        local cardId = (s.hands[1] or {})[i]
        box(hx, hy, CARD_W, CARD_H, 255,255,255, 40)
        if cardId then
            local def = cardGameFortune.db[cardId]
            if def and def.image then
                local img2 = tex(def.image); if img2 then Graphics.drawImageWP(img2, hx, hy, 5) end
            end
            if selectedHandIndex == i then
                Graphics.drawBox{ x=hx-2,y=hy-2,width=CARD_W+4,height=CARD_H+4, color=Color.white..0.5, priority=7 }
                if focus == "aim" then
                label((summonPos=="defense") and "DEF" or "ATK", hx+6, hy+CARD_H-24)
                end
            end
        else
            label(tostring(i), hx+4, hy+4)
        end
        hx = hx + CARD_W + CARD_GAP
    end

    -- slot 6 → Graveyard button (shows last KO thumbnail)
    local gx, gy = hx, hy  -- hx was advanced by the loop
    box(gx, gy, CARD_W, CARD_H, 255,255,255, 60)
    label("GRV", gx+6, gy+6, 6, Color.white)

    local last = nil
    do
        -- prefer the most recent overall
        local a = cardGameFortune.lastGrave(1)
        local b = cardGameFortune.lastGrave(2)
        if     (a and b) then last = (a.turn or 0) >= (b.turn or 0) and a or b
        elseif (a)       then last = a
        elseif (b)       then last = b
        end
    end


    if last then
        local def = cardGameFortune.db[last.cardId]
        if def and def.image then
            local img2 = tex(def.image)
            if img2 then
                Graphics.drawBox{ x=hx-2,y=hy-2,width=CARD_W+4,height=CARD_H+4, color=Color.black..0.5, priority=7 }
                tex(def.image); if img2 then Graphics.drawImageWP(img2, hx, hy, 5) end
            end
        end
    end


    -- ==== HOVER PANEL CONTENT ====
    local s      = cardGameFortune.peek()
    if not s then return end                 -- nothing to show if no match
    local board  = s.board or {}
    local hands  = s.hands or {}

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
            label("HP: "..tostring(cell.hp or 0), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
            shown = true

            -- outline the tile the leader is on
        local col = (cell.owner == 1) and Color(1.00,0.35,0.35,0.95) or Color(0.40,0.70,1.00,0.95)
            outlineCell(cursor.c, cursor.r, (cell.owner==1) and "red" or "blue", 5.1, 1)
            fillCell(cursor.c, cursor.r, Color(1,1,1,0.12), 5.05)
        end
    end

    -- ===== HOVER PANEL CONTENT =====
    if s then
           local graveTakesHover = false

        if UI.modal and UI.modal.kind == "grave" then
            local s = cardGameFortune.peek()
            local side = UI.modal.side or 1
            local list = (s and s.grave and s.grave[side]) or {}
            local idx  = (UI.modal.sel and UI.modal.sel[side]) or 1
            local e    = list[idx]
            if e then
                local def = cardGameFortune.db[e.cardId]
                if def then
                    label(def.name or "Unknown", rightPanelX+12, rightPanelY+8,  9.9, COL_NAME)
                    label(("ATK: %d"):format(def.atk or 0), rightPanelX+12, rightPanelY+48, 9.9, COL_ATK)
                    label(("DEF: %d"):format(def.def or 0), rightPanelX+12, rightPanelY+80, 9.9, COL_DEF)
                    label(((side==1) and "From: Player 1" or "From: Player 2"), rightPanelX+12, rightPanelY+112, 9.9, COL_LABEL)
                    graveTakesHover = true
                end
            end
        end

        if not graveTakesHover then
            -- 0) BATTLE PREVIEW (if we have a selected unit and the cursor is on a legal enemy target)
        do
            if (not shown) and selectedUnit and legalAttackSet then
                local srow = s.board[cursor.r]
                local target = srow and srow[cursor.c]
                if target and target.owner and target.owner ~= s.whoseTurn then
                    -- quick legality check using the set we already computed on selection
                    local legalHere = legalAttackSet[cursor.r] and legalAttackSet[cursor.r][cursor.c]
                    if legalHere then
                        local ok, pv = cardGameFortune.previewCombat(selectedUnit.c, selectedUnit.r, cursor.c, cursor.r)
                        if ok and pv then
                            -- Try to look up a terrain name/BG; fall back gracefully
                            local rawName = cardGameFortune.terrainNameAt and cardGameFortune.terrainNameAt(cursor.c, cursor.r)
                            local resolved = cardGameFortune.terrainHudBG and cardGameFortune.terrainHudBG(cursor.c, cursor.r)

                        -- Background: terrain HUD image for the hovered tile (if any)
                            do
                                -- BG behind text, above board
                                local tbg = cardGameFortune.terrainHudBG and cardGameFortune.terrainHudBG(cursor.c, cursor.r)
                                if tbg then
                                    local img = tex(tbg)
                                    if img then
                                        Graphics.drawImageWP(img, hoverX, hoverY, 4.85)
                                        Graphics.drawBox{
                                            x=hoverX, y=hoverY, width=HOVER_W, height=HOVER_H,
                                            color=Color.black..0.35, priority=4.9
                                        }
                                    end
                                end
                            end

                            -- Header: show terrain name (fallback to "Terrain" if unknown)
                            local tname = cardGameFortune.terrainNameAt and cardGameFortune.terrainNameAt(cursor.c, cursor.r) or "Terrain"
                            label(tname, hoverX+8, yy, 5, COL_NAME); yy = yy + MF_LINE

                            -- Attacker lines (Base / Tile / Final)
                            local aFinal  = pv.aATK or 0
                            local aDelta  = (pv.aBonus or 0) + (pv.aRole or 0)  -- terrain + role
                            local atkLine = ("ATK %d"):format(aFinal)
                            if aDelta ~= 0 then atkLine = atkLine .. (" (%+d)"):format(aDelta) end
                            label(atkLine, hoverX+8, yy, 5, COL_ATK); yy = yy + MF_LINE

                            if pv.mode == "vsLEADER" then
                                local dmg = (pv.leaderDamage and pv.leaderDamage.amount) or aFinal
                                label(("- %d"):format(dmg), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
                            else
                                -- Defender stat kind depends on whether we’re hitting ATK or DEF
                                local tag     = (pv.against == "ATK") and "ATK" or "DEF"
                                local dFinal  = (pv.against == "ATK") and (pv.dATK or 0) or (pv.dDEF or 0)
                                local dDelta  = (pv.dBonus or 0) + (pv.dRole or 0)  -- terrain + role
                                local defLine = ("%s %d"):format(tag, dFinal)
                                if dDelta ~= 0 then defLine = defLine .. (" (%+d)"):format(dDelta) end
                                label(defLine, hoverX+8, yy, 5, (tag=="ATK" and COL_ATK or COL_DEF)); yy = yy + MF_LINE

                                -- Outcome summary (same as Step A)
                                local diff = pv.diff or 0
                                local outcome
                                if     diff > 0 and pv.against == "ATK" then outcome = "Win (-" .. diff ..")"
                                elseif diff > 0 and pv.against == "DEF" then outcome = "Win"
                                elseif diff == 0 and pv.against == "ATK" then outcome = "Trade"
                                elseif diff == 0 and pv.against == "DEF" then outcome = "Stalemate"
                                else
                                    if pv.against == "ATK" then
                                        outcome = "Lose (-".. math.abs(diff) ..")"
                                    else
                                        outcome = "Bounce (-" .. math.abs(diff) ..")"
                                    end
                                end
                                label(("Result: %s"):format(outcome), hoverX+8, yy, 5, COL_LABEL); yy = yy + MF_LINE
                            end


                            shown = true
                        end
                    end
                end
            end
        end

        -- 1) Unit under cursor
        do
            local row  = s.board[cursor.r]
            local cell = row and row[cursor.c]
            if cell and cell.cardId then
                local def = cardGameFortune.db[cell.cardId]
                yy = drawCardInfo(def, hoverX, yy, HOVER_W, {c=cursor.c, r=cursor.r}, summonPos, function(y)
                    label("POS: "..(cell.pos or "attack"), hoverX+8, y, 5, COL_LABEL)
                    return y + MF_LINE
                end)
                shown = true
            end
        end

        -- 2) AIM preview
        -- draw terrain background for the hovered tile
        do
            local cc, rr = cursor.c, cursor.r  -- hovered board tile
            local tbg = cardGameFortune.terrainHudBG and cardGameFortune.terrainHudBG(cc, rr)
            if tbg then
                local img = tex(tbg)
                if img then
                    -- draw above board BG, below text
                    Graphics.drawImageWP(img, hoverX, hoverY, 4.95)
                    Graphics.drawBox{
                        x=hoverX, y=hoverY, width=HOVER_W, height=HOVER_H,
                        color=Color.black..0.35, priority=4.97
                    }
                end
            end

            -- header with terrain name
            local tname = cardGameFortune.terrainNameAt and cardGameFortune.terrainNameAt(cc, rr) or "Terrain"
            label(tname .. " • Summon Preview", hoverX+8, yy, 5, COL_NAME)
            yy = yy + MF_LINE
        end

        if (not shown) and focus == "aim" and selectedHandIndex ~= nil then
            local cardId = (s.hands[1] or {})[selectedHandIndex]
            if cardId then
                local def = cardGameFortune.db[cardId]
                yy = drawCardInfo(def, hoverX, yy, HOVER_W, {c=cursor.c, r=cursor.r}, summonPos, function(y)
                    label("PLACE AS: "..((summonPos=="defense") and "DEFENSE" or "ATTACK"),
                        hoverX+8, y, 5, COL_LABEL)
                    return y + MF_LINE
                end)
                shown = true
                end
            end
        end
    end

                -- Call this from your main draw (where you render HUD)
            drawActionBar()
            
            -- footer counters
            label("Deck:"..tostring(s.deckCounts[1]).."  Energy:"..tostring(s.energy[1] or 0), handX, handY - 450)


    -- ── Graveyard Modal Render ──
    if UI.modal and UI.modal.kind == "grave" then
        local s = cardGameFortune.peek()
        local g1 = (s and s.grave and s.grave[1]) or {}
        local g2 = (s and s.grave and s.grave[2]) or {}

        -- board-sized glass first
        Graphics.drawBox{ x=boardX, y=boardY, width=BOARD_SIZE, height=BOARD_SIZE,
                        color=Color(0,0,0,0.55), priority=9.70 }

        local half = math.floor(BOARD_SIZE/2)
        label("GRAVE (P1)", boardX+8,       boardY+6,  9.90, {1,0.35,0.35,1})
        label("GRAVE (P2)", boardX+half+16, boardY+6,  9.90, {0.35,0.65,1,1})

        local function drawPane(side, list, x0)
            local COLS = 3
            local padX, padY = 10, 24
            local cellW = CARD_W + CARD_GAP
            local cellH = CARD_H + CARD_GAP
            local visRows = math.max(1, math.floor((BOARD_SIZE - padY)/cellH))
            local scroll = (UI.modal.scroll and UI.modal.scroll[side]) or 0
            local sel    = (UI.modal.sel    and UI.modal.sel[side])    or 1
            local isActive = (UI.modal.side == side)

            local startRow = scroll
            local endRow   = scroll + visRows - 1

            for idx=1,#list do
                local row0 = math.floor((idx-1)/COLS)
                if row0 >= startRow and row0 <= endRow then
                    local col0  = (idx-1) % COLS
                    local drawR = row0 - startRow
                    local x = x0 + padX + col0*cellW
                    local y = boardY + padY + drawR*cellH

                    local def = cardGameFortune.db[list[idx].cardId]
                    local img = def and tex(def.image or def.icon)
                    if img then Graphics.drawImageWP(img, x, y, 9.82)
                    else       Graphics.drawBox{ x=x, y=y, width=CARD_W, height=CARD_H, color=Color(0,0,0,0.35), priority=9.82 } end

                    if isActive and idx == sel then
                        Graphics.drawBox{ x=x-2, y=y-2, width=CARD_W+4, height=CARD_H+4, color=Color.white..0.9, priority=9.84 }
                    end
                end
            end

            -- scrollbar
            local totalRows = math.max(1, math.ceil(#list / COLS))
            if totalRows > visRows then
                local barH = math.max(12, math.floor((visRows / totalRows) * (BOARD_SIZE - padY)))
                local maxScroll = totalRows - visRows
                local sc = (UI.modal.scroll and UI.modal.scroll[side]) or 0
                local t  = (maxScroll > 0) and (sc / maxScroll) or 0
                local barY = boardY + padY + math.floor(t * ((BOARD_SIZE - padY) - barH))
                local barX = x0 + (half - 12)
                Graphics.drawBox{ x=barX, y=barY, width=6, height=barH, color=Color.white..0.5, priority=9.83 }
            end
        end

        drawPane(1, g1, boardX)            -- left pane
        drawPane(2, g2, boardX + half + 2) -- right pane


        -- tiny debug counters (remove later)
        label(("#P1: %d"):format(#g1), boardX+8, boardY+BOARD_SIZE-18, 9.9, {1,1,1,0.8})
        label(("#P2: %d"):format(#g2), boardX+half+16, boardY+BOARD_SIZE-18, 9.9, {1,1,1,0.8})
    end
end




local function clampToScreen(x, y, textW, textH)
    x = math.max(BORDER, math.min(x, SCREEN_W - BORDER - textW))
    y = math.max(BORDER, math.min(y, SCREEN_H - BORDER - textH))
    return x, y
end
