
local cardGameFortune = { db = {} }

-- Safe read of a board cell; treats missing rows as empty (nil)
function cardGameFortune.safeBoardCell(s, c, r)
    local b = s and s.board
    if not b then return nil end
    local row = b[r]
    return row and row[c] or nil
end


-- Explain why a click (c,r) is illegal for the currently selected unit su
-- Leader-safe explain; tolerates nil sets and no dist map
function cardGameFortune.debugExplainSelection(su, c, r, legalMoveSet, legalAttackSet)
    local s = cardGameFortune.peek(); if not s then return end
    if not su then return end

    local u = s.board[su.r] and s.board[su.r][su.c]
    if not u then return end

    local isLeader = u.isLeader == true

    -- Build movement sets only for non-leaders (leaders don’t use approach/costs)
    local moves, dist = {}, {}
    if not isLeader then
        moves, dist = cardGameFortune.legalMovesFrom(
            su.c, su.r, { forThreat = true, returnDist = true }
        )
        moves = moves or {}; dist = dist or {}
    end

    local occ = s.board[r] and s.board[r][c]
    local moveOK = (legalMoveSet and legalMoveSet[r] and legalMoveSet[r][c]) and (occ == nil) or false
    local atkOK  = (legalAttackSet and legalAttackSet[r] and legalAttackSet[r][c]) or false

    function cardGameFortune._attackOriginDeltasFor(mt)
        local m = (mt or "normal")
        if m == "bishop" or m == "diagonal" then
            return { { 1, 1},{-1, 1},{ 1,-1},{-1,-1} }                         -- 4-diag
        elseif m == "rook" or m == "orthogonal" then
            return { { 1, 0},{-1, 0},{ 0, 1},{ 0,-1} }                         -- 4-orth
        elseif m == "queen" then
            return { {1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1} }   -- 8-dir
        elseif m == "knight" then
            return { { 2, 1},{ 2,-1},{-2, 1},{-2,-1},{ 1, 2},{ 1,-2},{-1, 2},{-1,-2} }
        else
            -- default melee: 4-orth
            return { { 1, 0},{-1, 0},{ 0, 1},{ 0,-1} }
        end
    end

        -- when an enemy tile (rc) is clicked while a melee unit is selected:
    local function canApproachAndStrike(attacker, target, legalMoveSet, dist)
        -- Keep move data consistent with what you used to draw/pick earlier.
        -- If you truly don't have it, recompute with the SAME opts you use elsewhere.
        if not legalMoveSet then
            -- Prefer: forThreat=false so gates (moved/attacked/summon) match real action.
            -- If you also need distance to pick best, request returnDist too.
            local set, d = cardGameFortune.legalMovesFrom(attacker.c, attacker.r, {returnDist=true})
            legalMoveSet, dist = set, d
        end

        local def = cardGameFortune.db[attacker.cardId] or {}
        local mt  = (def.movementtype or def.movetype) or "normal"
        local deltas = cardGameFortune._attackOriginDeltasFor(mt)

        local bestC, bestR, bestCost

        for _,d in ipairs(deltas) do
            local oc, orr = target.c + d[1], target.r + d[2]
            if cardGameFortune.isOnBoard(oc,orr)
            and cardGameFortune.isEmpty(oc,orr)
            and legalMoveSet[orr] and legalMoveSet[orr][oc] then
                if dist and dist[orr] and dist[orr][oc] then
                    local cost = dist[orr][oc]
                    if not bestCost or cost < bestCost then
                        bestC, bestR, bestCost = oc, orr, cost
                    end
                else
                    -- no distance map; first valid origin is fine
                    return true, oc, orr
                end
            end
        end

        if bestC then return true, bestC, bestR end
        return false
    end


        local lines = {}
        lines[#lines+1] = ("Tile (%d,%d)  occ=%s  moveOK=%s  atkOK=%s")
            :format(c, r, tostring(occ~=nil), tostring(moveOK), tostring(atkOK))

        if isLeader then
            lines[#lines+1] = "Leader: no approach/strike budget; move only to highlighted tiles."
            Misc.dialog(table.concat(lines, "\n"))
            return
        end

        -- For melee approach explanation (non-leader only)
        local def   = cardGameFortune.db[u.cardId]
        local bud   = cardGameFortune.meleeApproachBudget and select(1, cardGameFortune.meleeApproachBudget(def, su.c, su.r)) or nil
        if bud then
            lines[#lines+1] = ("Melee approach budget=%d"):format(bud)
            for _,d in ipairs{{1,0},{-1,0},{0,1},{0,-1}} do
                local ac, ar = c + d[1], r + d[2]
                if cardGameFortune.inBounds(ac, ar) then
                    local aocc = s.board[ar] and s.board[ar][ac]
                    if aocc then
                        lines[#lines+1] = ("adj(%d,%d): occupied"):format(ac, ar)
                    else
                        local cost = dist[ar] and dist[ar][ac]
                        if not cost then
                            lines[#lines+1] = ("adj(%d,%d): unreached"):format(ac, ar)
                        elseif bud and cost > bud then
                            lines[#lines+1] = ("adj(%d,%d): > budget %d"):format(ac, ar, bud)
                        else
                            lines[#lines+1] = ("adj(%d,%d): OK cost=%d"):format(ac, ar, cost)
                        end
                    end
                end
            end
        end

        Misc.dialog(table.concat(lines, "\n"))
end



-- === Duel: Challenger registry ===========================================
cardGameFortune.challengers = cardGameFortune.challengers or {
  koopa_card_man = { name = "Koopa Card Man", deckId = 1 },
  -- add more challengers here…
}

-- Begin a duel by challenger key
function cardGameFortune.beginNPCBattle(challengerKey)
  local entry = cardGameFortune.challengers[challengerKey]
  if not entry then return end

  -- stash for post-match rewards etc.
  STATE = STATE or {}
  STATE.npcDeckID   = entry.deckId
  STATE.opponentKey = challengerKey

  -- fresh match using that deck
  cardGameFortune.newMatch()    -- this already places leaders / terrain
  if UI then
    UI.mode = "hand"            -- start in hand focus
    UI.action = UI.action or {}
    UI.action.focused = false
  end
end



-- CARD REGISTRATION
function cardGameFortune.register(card)
    assert(card.id, "card.id required")
    assert(not cardGameFortune.db[card.id], ("duplicate card id: %s"):format(card.id))

    -- normalize names
    local movetype = card.movementtype or "normal"
    local atktype  = card.atktype  or "melee"
    local rangedLOS = card.rangedLOS or "orthogonal"
    local attackrange = card.attackrange or 1
    local rangedPenetration = card.rangedPenetration or "single" -- "single"|"volley"|"pierce"

    cardGameFortune.db[card.id] = {
        id          = card.id,
        name        = card.name or "Unnamed Card",
        image       = card.image or "cardgame/goombaicon.png",
        icon        = card.icon  or "cardgame/goombaicon.png",
        description = card.description or "No description yet.",
        atk         = card.atk or 0,
        def         = card.def or 0,
        movement    = card.movement or 0,

        -- NEW typing:
        movetype    = movetype,          -- "normal" | "diagonal" | "rook" | "bishop" | "queen" | "knight"
        atktype     = atktype,           -- "melee"|"ranged"
        attackrange = attackrange,       -- used for ranged only
        rangedLOS   = rangedLOS,         -- "orthogonal"|"diagonal"|"any"
        rangedPenetration = rangedPenetration,

        -- existing fields
        type        = card.type or "normal",
        subtype1    = card.subtype1 or "normal",
        subtype2    = card.subtype2 or "normal",
        summoncost  = card.summoncost or 0,
        deckcost    = card.deckcost or 0,
    }
end


cardGameFortune.roleBonus = {
  Melee     = { Grappler = 3, Ranged = 1 },
  Defensive = { Melee = 3, Magic = 1 },
  Grappler  = { Defensive = 3, Tower = 1 },
  Ranged    = { Tower = 3, Grappler = 1 },
  Magic     = { Ranged = 3, Melee = 1 },
  Tower     = { Magic = 3, Defensive = 1},
}

function cardGameFortune.unitType(u)
    local def = u and cardGameFortune.db[u.cardId]
    return (def and def.type) or "neutral"
end

function cardGameFortune.roleAtkBonus(attType, defType)
    local rows = cardGameFortune.roleBonus or {}
    local r = rows[attType]
    return (r and r[defType]) or 0
end


-- ───────────────────────────────────────────────────────────
-- STATE & RULES (new)
-- ───────────────────────────────────────────────────────────
local STATE = {
  open       = false,
  cols       = 7, rows = 7,
  board      = nil,
  whoseTurn  = 1,
  phase      = "main",
  hands      = { {}, {} },
  deck       = { {}, {} },
  discard    = { {}, {} },
  leaderHP   = { 40, 40 },
  energy     = { 3, 3 },
  deathFX    = {},      -- ← add this
  seed       = 0,
}


cardGameFortune.HAND_MAX = 5


cardGameFortune.TERRAIN = {
  ["Overworld"]=true, ["Underground"]=true, ["Underwater"]=true, ["Desert"]=true,
  ["Snow"]=true, ["Sky"]=true, ["Forest"]=true, ["Ghost House"]=true,
  ["Castle"]=true, ["Volcano"]=true, ["Mountain"]=true,
}

cardGameFortune.TERRAIN_IMG = {
  Overworld = "cardgame/terr_overworld.png",
  Underground = "cardgame/terr_underground.png",
  Underwater = "cardgame/terr_underwater.png",
  Desert = "cardgame/terr_desert.png",
  Snow = "cardgame/terr_snow.png",
  Sky = "cardgame/terr_sky.png",
  Forest = "cardgame/terr_forest.png",
  ["Ghost House"] = "cardgame/terr_ghost.png",
  Castle = "cardgame/terr_castle.png",
  Volcano = "cardgame/terr_volcano.png",
  Mountain = "cardgame/terr_mountain.png",
}

-- Look up the terrain of a board tile
local function terrainAt(c,r)
  if not STATE or not STATE.terrain then return "Overworld" end
  local row = STATE.terrain[r]; if not row then return "Overworld" end
  return row[c] or "Overworld"
end

-- subtype1: movement typing
--  ghost  : can enter every tile
--  flying : can enter Sky/Mountain in addition to normal
--  lava   : can enter Volcano in addition to normal
local function canEnter(def, terr)
  local t1 = (def and def.subtype1 or "normal")
  if t1 == "ghost" then return true end
  if terr == "Volcano"  then return (t1=="lava") or (t1=="ghost") end
  if terr == "Sky" or terr == "Mountain" then return (t1=="flying") or (t1=="ghost") end
  return true
end

cardGameFortune.canEnter = canEnter

-- BAD matchups (card subtype2 -> tile terrain that gives -3)
local TERRAIN_PENALTY = {
  Underground = { Sky=true },
  Underwater  = { Volcano=true },
  Desert      = { Snow=true },
  Snow        = { Desert=true },
  Sky         = { Underground=true },
  Forest      = { Mountain=true },
  ["Ghost House"] = { Castle=true },
  Castle      = { ["Ghost House"]=true },
  Volcano     = { Underwater=true },
  Mountain    = { Forest=true },
}

-- Returns ATK/DEF modifier: +3 (match), -3 (penalty), or 0 (neutral)
local function terrainDelta(defTerr, tileTerr)
  if not defTerr or defTerr == "" then return 0 end
  if defTerr == tileTerr then return 3 end
  local pen = TERRAIN_PENALTY[defTerr]
  if pen and pen[tileTerr] then return -3 end
  return 0
end

-- Returns MOVEMENT modifier: +1 (match), -1 (penalty), or 0 (neutral)
local function terrainMovementBonus(defTerr, tileTerr)
  if not defTerr or defTerr == "" then return 0 end
  if defTerr == tileTerr then return 1 end  -- Favorable terrain: +1 movement
  local pen = TERRAIN_PENALTY[defTerr]
  if pen and pen[tileTerr] then return -1 end  -- Penalty terrain: -1 movement
  return 0
end

cardGameFortune.terrainMovementBonus = terrainMovementBonus

-- Return a human terrain name for tile (c,r)
function cardGameFortune.terrainNameAt(c, r)
    return cardGameFortune.terrainAt(c, r)
end


-- Return HUD background image path for that terrain
function cardGameFortune.terrainHudBG(c, r)
    local name = cardGameFortune.terrainNameAt(c, r)
    if not name then return nil end

    -- Normalize "Ghost House" -> "GhostHouse"
    local token = (tostring(name):gsub("%s+", ""):gsub("[^%w]", ""))

    -- Your convention:  cardgame/terr_info<TerrainName>[.png]
    -- We’ll return the path with .png; your tex() usually resolves either way.
    return "cardgame/terr_info" .. token .. ".png"
end

-- =========================================================
-- Terrain generation (seeded, blobby, optional mirroring)
-- Produces STATE.terrain[r][c] as strings:
--   "Overworld","Underground","Underwater","Desert","Snow",
--   "Sky","Forest","Ghost House","Castle","Volcano","Mountain"
-- =========================================================

-- deterministic RNG (LCG)
local function makeRNG(seed)
    local a, c, m = 1664525, 1013904223, 4294967296
    local s = (tonumber(seed) or 12345) % m
    return function(lo, hi)
        s = (a*s + c) % m
        local r = s / m
        if lo then
            if hi then return math.floor(lo + r*(hi - lo + 1)) end
            return math.floor(1 + r*lo)
        end
        return r
    end
end

-- Terrain set + base weights (tweak to taste)
local TERRAIN_LIST = {
    "Overworld","Forest","Mountain","Desert","Snow",
    "Underground","Underwater","Sky","Ghost House","Castle","Volcano",
}
local TERRAIN_WEIGHT = {
    Overworld=10, Forest=10, Mountain=6, Desert=10, Snow=10,
    Underground=10, Underwater=10, Sky=6, GhostHouse=9, ["Ghost House"]=5, Castle=9, Volcano=6,
}

-- Helper: bounds
local function T_in(s, c, r)
    return c>=0 and r>=0 and c<s.cols and r<s.rows
end

-- Weighted pick
local function T_weightedPick(rand)
    local total=0
    for k,v in pairs(TERRAIN_WEIGHT) do total = total + v end
    local t = rand()*total
    for _,name in ipairs(TERRAIN_LIST) do
        local w = TERRAIN_WEIGHT[name] or TERRAIN_WEIGHT[name:gsub("%s","")] or 1
        if t < w then return name end
        t = t - w
    end
    return "Overworld"
end

-- Make an empty terrain grid (nil)
local function T_newGrid(rows, cols)
    local g = {}
    for r=0,rows-1 do
        g[r] = {}
        for c=0,cols-1 do g[r][c] = nil end
    end
    return g
end

-- Seeded blob grow:
-- 1) drop N seeds with weighted terrain types
-- 2) push neighbors randomly until board filled (contiguous patches)
local function T_generate(seed, rows, cols, opts)
    opts = opts or {}
    local rand = makeRNG(seed or 12345)
    local g = T_newGrid(rows, cols)
    local remaining = rows*cols

    -- number of blobs proportional to area (tweak factor)
    local N = math.max(4, math.floor((rows*cols)/40))
    local frontier = {}

    -- place seeds
    for i=1,N do
        local tries = 0
        repeat
            local c = rand(0, cols-1)
            local r = rand(0, rows-1)
            tries = tries + 1
            if not g[r][c] then
                local terr = T_weightedPick(rand)
                g[r][c] = terr
                remaining = remaining - 1
                frontier[#frontier+1] = {c=c, r=r, terr=terr}
                break
            end
        until tries>200
    end

    -- grow
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    while remaining > 0 do
        -- if frontier is empty (tiny boards), drop a fresh seed
        if #frontier == 0 then
            for r=0,rows-1 do
                for c=0,cols-1 do
                    if not g[r][c] then
                        local terr = T_weightedPick(rand)
                        g[r][c] = terr
                        remaining = remaining - 1
                        frontier[#frontier+1] = {c=c, r=r, terr=terr}
                        goto cont_grow
                    end
                end
            end
        end
        ::cont_grow::

        local idx = rand(1, math.max(1,#frontier))
        local n = table.remove(frontier, idx)
        -- push neighbors with same terr
        for k=1,4 do
            local d = dirs[rand(1,4)]
            local nc, nr = n.c + d[1], n.r + d[2]
            if T_in(STATE, nc, nr) and (not g[nr][nc]) then
                g[nr][nc] = n.terr
                remaining = remaining - 1
                frontier[#frontier+1] = {c=nc, r=nr, terr=n.terr}
            end
        end
    end

    -- optional mirroring for fairness
    if opts.mirror == "vertical" then
        for r=0,rows-1 do
            for c=0,math.floor(cols/2)-1 do
                g[r][cols-1-c] = g[r][c]
            end
        end
    elseif opts.mirror == "horizontal" then
        for r=0,math.floor(rows/2)-1 do
            g[rows-1-r] = {}
            for c=0,cols-1 do g[rows-1-r][c] = g[r][c] end
        end
    end

    return g
end

-- Passability + corridor tools
local IMPASSABLE = { Sky=true, Volcano=true, Mountain=true }

local function isPassableTerr(t) return not IMPASSABLE[t] end

-- random passable terrain, biased to match neighbors so it blends in
local PASSABLE_SET = {
  Overworld=true, Forest=true, Desert=true, Snow=true,
  Underground=true, Underwater=true, ["Ghost House"]=true, Castle=true
}
local PASSABLE_LIST = {}
for name,_ in pairs(PASSABLE_SET) do PASSABLE_LIST[#PASSABLE_LIST+1] = name end

local function randomPassable() return PASSABLE_LIST[math.random(#PASSABLE_LIST)] end
local function neighborOrRandomPassable(g, r, c)
  local pick = {}
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  for i=1,4 do
    local rr,cc = r+dirs[i][2], c+dirs[i][1]
    local t = g[rr] and g[rr][cc]
    if t and isPassableTerr(t) and PASSABLE_SET[t] then pick[#pick+1] = t end
  end
  if #pick>0 then return pick[math.random(#pick)] end
  return randomPassable()
end

-- ── Mirror helpers
local function mirrorC(cols, c)         -- horizontal mirror (0-based cols)
    return (cols - 1) - c
end

local function isImpassableTerr(t)
    return (IMPASSABLE and IMPASSABLE[t]) == true
end

-- Carve this cell passable and mirror the carve if the opposite side is impassable
local function carvePassableMirrored(g, cols, r, c)
    local to = neighborOrRandomPassable(g, r, c)
    g[r][c] = to

    local mc = mirrorC(cols, c)
    if mc ~= c then
        local mt = g[r] and g[r][mc]
        if mt and isImpassableTerr(mt) then
            g[r][mc] = to
        end
    end
end

-- BFS reachability on passable tiles
local function pathExists(g, cols, rows, c0,r0, c1,r1)
  local seen = {}
  local function key(c,r) return r*10000 + c end
  local q = {{c=c0,r=r0}}; seen[key(c0,r0)] = true
  local head = 1
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  while q[head] do
    local cur = q[head]; head = head + 1
    if cur.c==c1 and cur.r==r1 then return true end
    for i=1,4 do
      local cc,rr = cur.c+dirs[i][1], cur.r+dirs[i][2]
      if cc>=0 and cc<cols and rr>=0 and rr<rows then
        local t = g[rr] and g[rr][cc]
        if t and isPassableTerr(t) then
          local k = key(cc,rr)
          if not seen[k] then
            seen[k] = true; q[#q+1] = {c=cc,r=rr}
          end
        end
      end
    end
  end
  return false
end

-- A* that returns a list of cells; we’ll only convert IMPASSABLE cells on that path
local function aStarPath(g, cols, rows, c0,r0, c1,r1)
  local function h(c,r) return math.abs(c-c1) + math.abs(r-r1) end
  local function key(c,r) return r*10000 + c end
  local open, gCost, fCost, came = {}, {}, {}, {}
  local function push(c,r)
    local k = key(c,r); fCost[k] = (gCost[k] or 0) + h(c,r); open[#open+1] = {c=c,r=r,k=k}
  end
  gCost[key(c0,r0)] = 0; push(c0,r0)
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}

  while #open>0 do
    table.sort(open, function(a,b) return fCost[a.k] < fCost[b.k] end)
    local cur = table.remove(open,1)
    if cur.c==c1 and cur.r==r1 then
      local path, k = {}, cur.k
      while k do
        local r = math.floor(k/10000); local c = k - r*10000
        path[#path+1] = {c=c,r=r}
        k = came[k]
      end
      return path
    end
    for i=1,4 do
      local cc,rr = cur.c+dirs[i][1], cur.r+dirs[i][2]
      if cc>=0 and cc<cols and rr>=0 and rr<rows then
        local t = g[rr] and g[rr][cc]
        if t then
          local step = isPassableTerr(t) and 1 or 6  -- prefer passable, allow carving if needed
          local nk   = key(cc,rr)
          local ng   = (gCost[cur.k] or 1e9) + step
          if ng < (gCost[nk] or 1e9) then
            gCost[nk] = ng; came[nk] = cur.k; push(cc,rr)
          end
        end
      end
    end
  end
  return nil
end

-- Only fix impassables in the 1-tile summon ring; don't repaint the whole ring
local function softenLeaderRing(g, cols, rows, p)
  for dr=-1,1 do
    for dc=-1,1 do
      local c, r = p.c+dc, p.r+dr
      if c>=0 and c<cols and r>=0 and r<rows then
        local t = g[r][c]
        if t and not isPassableTerr(t) then
          g[r][c] = neighborOrRandomPassable(g, r, c)
        end
      end
    end
  end
end

-- Puncture any fully-impassable rows with 1–2 holes; align holes across consecutive rows
local function punctureImpassableRows(g, cols, rows)
  local lastHoleCol = nil
  for r=0,rows-1 do
    local allBlock = true
    for c=0,cols-1 do
      local t = g[r][c]; if t and isPassableTerr(t) then allBlock=false; break end
    end
    if allBlock then
      local hole = lastHoleCol or math.random(0, cols-1)
      -- drill 1–2 holes in this row; keep first aligned with last row to form a “road”
      local holes = { hole }
      if math.random() < 0.35 then
        local extra = math.max(0, math.min(cols-1, hole + (math.random(0,1)==0 and -2 or 2)))
        holes[#holes+1] = extra
      end
      for i=1,#holes do
        local c = holes[i]
        carvePassableMirrored(g, cols, r, c)
      end
      lastHoleCol = hole
    else
      lastHoleCol = nil
    end
  end
end

-- Keep a neutral ring around each leader so you can always act on turn 1
local function T_neutralizeLeaderRings(g, ringTerr, radius)
  ringTerr = ringTerr or "Overworld"
  radius   = radius or 1
  local s = STATE
  if not (s and s.leaderPos and s.leaderPos[1] and s.leaderPos[2]) then return end
  local normalDef = { subtype1 = "normal" }  -- “ground” unit

  for owner=1,2 do
    local p = s.leaderPos[owner]
    for dr=-radius,radius do
      for dc=-radius,radius do
        local c, r = p.c + dc, p.r + dr
        if c>=0 and r>=0 and c<s.cols and r<s.rows then
          local terr = g[r][c]
          if not cardGameFortune.canEnter(normalDef, terr) then
            g[r][c] = ringTerr
          end
        end
      end
    end
  end
end


-- Safe millisecond timestamp for seeding (works with or without lunatime)
local function nowMs()
    local lt = rawget(_G,"lunatime")
    if lt then
        if type(lt.ms) == "function" then return lt.ms() end
        if type(lt.ms) == "number"  then return lt.ms end
    end
    if type(os.clock) == "function" then
        return math.floor(os.clock()*1000)
    end
    return os.time()*1000
end

-- Should help terrain generation not be impossible after checking the below functions
local function terrWalkableForGround(terr)
  return not (terr == "Mountain" or terr == "Sky" or terr == "Volcano")
end

local function bfsReachable(s, c0,r0, c1,r1)
  local Q, seen = {{c=c0,r=r0}}, {}
  local function key(c,r) return r.."|"..c end
  seen[key(c0,r0)] = true
  while #Q>0 do
    local t = table.remove(Q,1)
    if t.c==c1 and t.r==r1 then return true end
    for _,d in ipairs{{1,0},{-1,0},{0,1},{0,-1}} do
      local cc,rr = t.c+d[1], t.r+d[2]
      if cc>=1 and cc<=s.cols and rr>=1 and rr<=s.rows and not seen[key(cc,rr)] then
        local terr = s.terrain[rr][cc]
        if terrWalkableForGround(terr) then
          seen[key(cc,rr)] = true
          Q[#Q+1] = {c=cc,r=rr}
        end
      end
    end
  end
  return false
end

-- ── SFX helper ─────────────────────────────────────────────
local SFX_MASTER = 0.40 

local function _sfx(path, vol)
    if not path then return end
    local v = (vol or 1.0) * SFX_MASTER   
    pcall(SFX.play, path, v)            
end


-- Callers (so the call sites stay short & consistent)
function cardGameFortune.sfx_move()        _sfx("cardgame/sound/Move.wav") end
function cardGameFortune.sfx_matchStart()  _sfx("cardgame/sound/Match Start.wav") end
function cardGameFortune.sfx_cursorMove()  _sfx("cardgame/sound/Cursor - Move.wav") end
function cardGameFortune.sfx_accept()      _sfx("cardgame/sound/Cursor - Accept.wav") end
function cardGameFortune.sfx_cancel()      _sfx("cardgame/sound/Cursor - Cancel.wav") end
function cardGameFortune.sfx_buzzer()      _sfx("cardgame/sound/Cursor - Buzzer.wav") end
function cardGameFortune.sfx_combat()      _sfx("cardgame/sound/Combat.wav") end
function cardGameFortune.sfx_kill()        _sfx("cardgame/sound/Kill.wav") end
function cardGameFortune.sfx_summon()      _sfx("cardgame/sound/Summon.wav") end

-- Optional: ranged throw mapping per unit; default falls back to Combat.wav
function cardGameFortune.sfx_ranged(def)
    -- allow per-card override: def.rangedSfx = "cardgame/sound/MagicBlast.wav"
    if def and def.rangedSfx then _sfx(def.rangedSfx); return end

    -- examples by name (use whatever your card names are)
    if def and def.name == "Magikoopa"      then _sfx("cardgame/sound/MagicBlast.wav"); return end
    if def and def.name == "Bullet Blaster" then _sfx("cardgame/sound/Cannon.wav");     return end

    -- default
    cardGameFortune.sfx_combat()
end


STATE.deathFX = STATE.deathFX or {}

-- Tiles the leaders cannot path through.
local IMPASSABLE_TERRAIN = {
    Sky=true, Volcano=true, Mountain=true, ["Ghost House"]=false, -- tweak as you like
}

-- Return terrain name for (c,r), or nil
local function terrNameAt(s, c, r)
    if not (s and s.terrain and s.terrain[r] and s.terrain[r][c]) then return nil end
    local t = s.terrain[r][c]
    -- terrain already stored as name strings in your generator; if you ever switch to ids,
    -- translate here (e.g., s.terrainNames[id])
    return t
end

-- Passability check (treat nil as passable so we don't crash during early boot)
local function isPassable(s, c, r)
    if not (s and s.cols and s.rows) then return false end
    if c < 1 or r < 1 or c > s.cols or r > s.rows then return false end
    local name = terrNameAt(s, c, r)
    if not name then return true end
    return not IMPASSABLE_TERRAIN[name]
end

-- Simple BFS to test if target is reachable via passable tiles
local function pathExists(s, c0, r0, c1, r1)
    if not (isPassable(s,c0,r0) and isPassable(s,c1,r1)) then return false end
    local qh, qt = 1, 1
    local Qc, Qr = {c0}, {r0}
    local seen = {}
    local key = function(c,r) return r * 10000 + c end
    seen[key(c0,r0)] = true
    local deltas = {{1,0},{-1,0},{0,1},{0,-1}}

    while qh <= qt do
        local c, r = Qc[qh], Qr[qh]; qh = qh + 1
        if c == c1 and r == r1 then return true end
        for i=1,4 do
            local nc, nr = c + deltas[i][1], r + deltas[i][2]
            local k = key(nc,nr)
            if not seen[k] and isPassable(s,nc,nr) then
                qt = qt + 1
                Qc[qt], Qr[qt] = nc, nr
                seen[k] = true
            end
        end
    end
    return false
end

-- Carve a straight(-ish) corridor by setting tiles to "Overworld"
local function carveCorridor(s, fromC, fromR, toC, toR, maxSteps)
    if not (s and s.terrain) then return end
    local name = "Overworld"
    local dc = (toC > fromC) and 1 or ((toC < fromC) and -1 or 0)
    local dr = (toR > fromR) and 1 or ((toR < fromR) and -1 or 0)
    local c, r = fromC, fromR
    maxSteps = maxSteps or (s.cols + s.rows)

    -- carve outward from the start toward the target
    for _=1,maxSteps do
        if s.terrain[r] and s.terrain[r][c] then
            s.terrain[r][c] = name
            local mc = mirrorC(s.cols, c)
            if mc ~= c then
                local mt = s.terrain[r][mc]
                if mt and isImpassableTerr(mt) then
                    s.terrain[r][mc] = name
                end
            end
        end
        if c == toC and r == toR then break end
        -- greedy step (Manhattan)
        if math.abs(toC - c) > math.abs(toR - r) then
            c = c + dc
        else
            r = r + dr
        end
        -- clamp (paranoia)
        if c < 1 then c = 1 elseif c > s.cols then c = s.cols end
        if r < 1 then r = 1 elseif r > s.rows then r = s.rows end
    end
end

-- Public: make map valid with minimal changes (no guaranteed straight lane)
function cardGameFortune.ensureLeaderConnectivity()
  local s = STATE
  if not (s and s.terrain and s.leaderPos and s.leaderPos[1] and s.leaderPos[2]) then return true end

  local g    = s.terrain
  local rows = s.rows or (#g)
  local cols = s.cols or (#g[0] or #g[1])

  local p1 = s.leaderPos[1]
  local p2 = s.leaderPos[2]
  if not (p1 and p2) then return true end

  -- 1) soften just the summon rings
  softenLeaderRing(g, cols, rows, p1)
  softenLeaderRing(g, cols, rows, p2)

  -- 2) puncture any full impassable rows
  punctureImpassableRows(g, cols, rows)

  -- 3) final check; if still blocked, carve minimal A* path by changing only impassables along that path
  if not pathExists(g, cols, rows, p1.c, p1.r, p2.c, p2.r) then
    local path = aStarPath(g, cols, rows, p1.c, p1.r, p2.c, p2.r)
    if path then
      for i=#path,1,-1 do
        local n = path[i]
        local t = g[n.r][n.c]
        if t and not isPassableTerr(t) then
            carvePassableMirrored(g, cols, n.r, n.c)
        end
      end
    end
  end

  return true
end

function cardGameFortune.uiInvokeAction(id)
    if UI and UI.modal then return end

    if     id == "hand"    then cardGameFortune.uiFocusHand()
    elseif id == "board"   then cardGameFortune.uiFocusBoard()
    elseif id == "guide"   then cardGameFortune.uiOpenGuide()
    elseif id == "grave"   then cardGameFortune.uiOpenGrave()
    elseif id == "end"     then cardGameFortune.endTurn()
    elseif id == "restart" then cardGameFortune.requestRestartMatch()
    elseif id == "concede" then cardGameFortune.requestConcede()
    end

    -- leave bar focus after an action except modal opens (grave/guide)
    if not (id=="grave" or id=="guide") then
        if UI then UI.action.focused = false end
    end
end

function cardGameFortune.uiFocusHand()
  -- Clear board cursors and ensure hand selection is active
  if UI then
    UI.mode = "hand"
    UI.selectedSummon = nil
    UI.selectedBoard  = nil
  end
end

function cardGameFortune.uiFocusBoard()
  if UI then
    UI.mode = "board"
    UI.selectedHand   = nil
  end
end

function cardGameFortune.uiOpenGrave()
  if UI then
    UI.modal = "grave"
    UI.graveSide = UI.graveSide or 1
  end
end

function cardGameFortune.uiOpenGuide()
  if UI then
    UI.modal = "guide"
  end
end

function cardGameFortune.requestRestartMatch()
  if UI then UI.modal = "confirm_restart" end
end

function cardGameFortune.requestConcede()
  if UI then UI.modal = "confirm_concede" end
end

-- Public API
function cardGameFortune.regenTerrain(opts)
    local s = STATE; if not s then return end
    s.terrainSeed = s.terrainSeed or nowMs()
    s.terrain = T_generate(s.terrainSeed, s.rows, s.cols, opts or {mirror="vertical"})
    -- make sure leaders exist before neutralizing rings
    T_neutralizeLeaderRings(s.terrain, ringTerr, 1)
    cardGameFortune.ensureLeaderConnectivity(s.terrain)
end

-- terrainAt(c,r) convenience (keeps your existing calls working)
function cardGameFortune.terrainAt(c,r)
    local s = STATE
    return (s and s.terrain and s.terrain[r] and s.terrain[r][c]) or "Overworld"
end

-- returns effective ATK/DEF on tile, tile terrain, and the signed delta (+2/-2/0)
function cardGameFortune.getEffectiveStats(def, c, r)
    local terr  = terrainAt(c,r)
    local delta = terrainDelta(def and def.subtype2, terr)
    

    local baseATK = (def and def.atk or 0)
    local baseDEF = (def and def.def or 0)

    -- clamp so stats never go below 0
    local eATK = math.max(0, baseATK + delta)
    local eDEF = math.max(0, baseDEF + delta)

    return eATK, eDEF, terr, delta
end


cardGameFortune.SUMMON_NEIGHBORHOOD = "8way"  -- "orthogonal" or "8way"

local function isAdjacent(c1,r1,c2,r2)
    local dc, dr = math.abs(c1-c2), math.abs(r1-r2)
    if cardGameFortune.SUMMON_NEIGHBORHOOD == "orthogonal" then
        return (dc + dr) == 1
    elseif cardGameFortune.SUMMON_NEIGHBORHOOD == "8way" then
        return math.max(dc,dr) == 1
    else
        return (dc + dr) == 1 
    end
end


local function new2D(rows,cols)
  local t = {}
  for r=0,rows-1 do
    t[r] = {}
    for c=0,cols-1 do
      t[r][c] = false
    end
  end
  return t
end

 STATE.terrain = {}
  for r=0,STATE.rows-1 do
    STATE.terrain[r] = {}
    for c=0,STATE.cols-1 do
      STATE.terrain[r][c] = "Overworld"
    end
  end

local function shallowCopy(a)
  local t = {}
  for i=1,#a do t[i]=a[i] end
  return t
end

local function rng(seed)
  local s = seed or 1
  local function nextRand()
    s = (1103515245 * s + 12345) % 2^31
    return s
  end
  local function getSeed() return s end
  return nextRand, getSeed
end

local function shuffle(arr, nextRand)
  for i=#arr,2,-1 do
    local j = (nextRand() % i) + 1
    arr[i], arr[j] = arr[j], arr[i]
  end
end

-- Build a super basic starter deck from your DB (even split)
local function buildStarterDeck()
  local ids = {}
  for id,_ in pairs(cardGameFortune.db) do ids[#ids+1] = id end
  table.sort(ids) -- stable order before shuffle
  -- simple 20-card deck by cycling
  local deck = {}
  local i=1
  while #deck < 20 do
    deck[#deck+1] = ids[i]
    i = i + 1
    if i > #ids then i = 1 end
  end
  return deck
end

-- === Movement & Combat helpers ===========================================

local function inBounds(c,r)
    return STATE and c>=0 and r>=0 and c<STATE.cols and r<STATE.rows
end

cardGameFortune.inBounds = inBounds

local function isEmpty(c,r)
    return inBounds(c,r) and (not STATE.board[r][c])
end

-- terrain lookup (works now even if you don't have a real grid yet)
local function terrainAt(c,r)
    if STATE and STATE.terrain and STATE.terrain[r] then
        return STATE.terrain[r][c] or "Overworld"
    end
    return "Overworld"
end

local function terrainBlocksLOS(terr)
    return terr == "Mountain" or terr == "Volcano"
end

-- tile entry rules
local function canEnterTile(def, c, r)
    if not inBounds(c,r) then return false end
    if STATE.board[r][c] then return false end
    local terr = terrainAt(c,r)
    return cardGameFortune.canEnter(def, terr)
end

local function neighbors8(c,r)
    return {
        {c-1,r-1},{c,  r-1},{c+1,r-1},
        {c-1,r  },          {c+1,r  },
        {c-1,r+1},{c,  r+1},{c+1,r+1},
    }
end

local function neighbors4(c,r)
  return { {c+1,r},{c-1,r},{c,r+1},{c,r-1} }
end

-- === Movement shape primitives ============
cardGameFortune.DIR4   = cardGameFortune.DIR4   or { { 1, 0},{-1, 0},{ 0, 1},{ 0,-1} }
cardGameFortune.DIAG4  = cardGameFortune.DIAG4  or { { 1, 1},{-1, 1},{ 1,-1},{-1,-1} }
cardGameFortune.DIR8   = cardGameFortune.DIR8   or {
    { 1, 0},{-1, 0},{ 0, 1},{ 0,-1},{ 1, 1},{-1, 1},{ 1,-1},{-1,-1}
}
cardGameFortune.KNIGHT = cardGameFortune.KNIGHT or {
    { 1, 2},{ 2, 1},{-1, 2},{-2, 1},{ 1,-2},{ 2,-1},{-1,-2},{-2,-1}
}

local function _stepDeltasFor(def)
    local t = (def and (def.movetype or def.movementtype)) or "normal"
    if t == "diagonal" or t == "bishop" then 
        return cardGameFortune.DIR8, false  -- Use 8-way, not just diagonal
    elseif t == "queen" then return cardGameFortune.DIR8, true
    elseif t == "rook" then return cardGameFortune.DIR4, true
    elseif t == "knight" then return cardGameFortune.KNIGHT, "knight"
    else return cardGameFortune.DIR4, false end
end

local function _isSliding(movetype)
    return (movetype == "rook" or movetype == "bishop" or movetype == "queen")
end

local function _isKnight(movetype)
    return movetype == "knight"
end

-- === Unified reach map (respects movetype, terrain, occupancy) ==========
-- Replace your local function with this exported one
function cardGameFortune._computeReach(c0, r0, def, maxSteps)
    local s = STATE; if not (s and s.board) then return {} end
    local rows, cols = s.rows, s.cols

    local movetype   = (def and (def.movementtype or def.movetype)) or "normal"
    local deltas, kind = _stepDeltasFor(def)
    local passGhost  = (def and def.subtype1 == "ghost")
    local isSliding  = (movetype == "rook" or movetype == "bishop" or movetype == "queen")

    local function inB(c,r) return c>=0 and c<cols and r>=0 and r<rows end
    local function passable(c,r)
        local terr = cardGameFortune.terrainAt(c,r)
        return terr and cardGameFortune.canEnter(def, terr)
    end

    local dist = { [r0] = { [c0] = 0 } }

    if kind == "knight" then
        -- Knights: single hop to each L-shaped position
        for _,dlt in ipairs(deltas) do
            local nc, nr = c0 + dlt[1], r0 + dlt[2]
            if inB(nc,nr) and passable(nc,nr) and not (s.board[nr] and s.board[nr][nc]) then
                if maxSteps >= 1 then
                    dist[nr] = dist[nr] or {}
                    dist[nr][nc] = 1
                end
            end
        end
    elseif isSliding then
        -- Sliding pieces: cast rays in each direction
        for _,dlt in ipairs(deltas) do
            local nc, nr = c0 + dlt[1], r0 + dlt[2]
            local steps = 1
            
            while steps <= maxSteps and inB(nc,nr) do
                -- Check terrain passability
                if not passable(nc,nr) then break end
                
                -- Check occupancy
                local occupied = (s.board[nr] and s.board[nr][nc])
                
                if occupied and not passGhost then
                    break  -- Can't slide through pieces (unless ghost)
                else
                    -- Mark this tile as reachable
                    dist[nr] = dist[nr] or {}
                    dist[nr][nc] = steps
                    
                    if occupied and passGhost then
                        -- Ghost can pass through but still counts the step
                    end
                end
                
                -- Continue sliding
                nc, nr = nc + dlt[1], nr + dlt[2]
                steps = steps + 1
            end
        end
    else
        -- Normal/diagonal: step-by-step BFS
        local Q, head = { {c=c0,r=r0} }, 1
        
        while head <= #Q do
            local n = Q[head]; head = head + 1
            local dHere = dist[n.r][n.c]
            
            if dHere < maxSteps then
                for _,dlt in ipairs(deltas) do
                    local nc, nr = n.c + dlt[1], n.r + dlt[2]
                    
                    if inB(nc,nr) and passable(nc,nr) then
                        local occ = s.board[nr] and s.board[nr][nc]
                        
                        if (not occ) or passGhost then
                            if not (dist[nr] and dist[nr][nc]) then
                                local nd = dHere + 1
                                if nd <= maxSteps then
                                    dist[nr] = dist[nr] or {}
                                    dist[nr][nc] = nd
                                    Q[#Q+1] = { c=nc, r=nr }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return dist
end


-- Where can the attacker STAND to legally melee this target, per movetype?
function cardGameFortune._attackOriginDeltasFor(movetype)
    local mt = movetype or "normal"
    if mt == "diagonal" or mt == "bishop" then
        return { { 1, 1},{-1, 1},{ 1,-1},{-1,-1} }                  -- 4-diag only
    elseif mt == "queen" then
        return { { 1, 0},{-1, 0},{ 0, 1},{ 0,-1},{ 1, 1},{-1, 1},{ 1,-1},{-1,-1} } -- 8-dir
    elseif mt == "knight" then
        return { { 2, 1},{ 2,-1},{-2, 1},{-2,-1},{ 1, 2},{ 1,-2},{-1, 2},{-1,-2} }
    else
        return { { 1, 0},{-1, 0},{ 0, 1},{ 0,-1} }                  -- normal/rook
    end
end

-- cardGameFortune.lua
function cardGameFortune.isMeleeInRange(unitRef, uc, ur, tc, tr)
    if not unitRef then return false end
    local def = cardGameFortune.db[unitRef.cardId]
    local mt  = (def and (def.movementtype or def.movetype)) or "normal"
    local adj = cardGameFortune._attackOriginDeltasFor(mt)
    local dc, dr = tc - uc, tr - ur
    for _,d in ipairs(adj) do
        if d[1] == dc and d[2] == dr then return true end
    end
    return false
end

function cardGameFortune.legalLeaderMovesFrom(c,r)
    local s = STATE; if not s then return {} end
    local u = s.board[r] and s.board[r][c]
    if not u or not u.isLeader or u.hasMoved then return {} end

    local res = {}
    local function inBounds(x,y) return x>=0 and y>=0 and x<s.cols and y<s.rows end
    local function mark(cc,rr)
        if inBounds(cc,rr) and (not s.board[rr][cc]) then
            res[rr] = res[rr] or {}; res[rr][cc] = true
        end

    end

    -- one step 4-way (L/R/U/D)
    mark(c-1,r); mark(c+1,r); mark(c,r-1); mark(c,r+1)
    return res
end

function cardGameFortune.legalMovesFrom(c, r, opts)
    local cell = STATE.board[r] and STATE.board[r][c]
    if not cell or cell.isLeader then return (opts and opts.returnDist) and {}, {} or {} end

    local forThreat  = opts and opts.forThreat
    local returnDist = opts and opts.returnDist

    if (not forThreat) and (cell.summoningSickness or cell.hasMoved or cell.hasAttacked) then
        return returnDist and {}, {} or {}
    end

    local def         = cardGameFortune.db[cell.cardId] or {}
    local startTerr   = cardGameFortune.terrainAt(c, r)
    local baseMov     = def.movement or 0
    local movBonus    = (cardGameFortune.terrainMovementBonus
                      and cardGameFortune.terrainMovementBonus(def.subtype2, startTerr)) or 0
    local maxSteps    = math.max(0, baseMov + movBonus)

    -- Use _computeReach instead of duplicating logic
    local dist = cardGameFortune._computeReach(c, r, def, maxSteps)

    -- Build set from dist (exclude starting position)
    local set = {}
    for rr, row in pairs(dist) do
        for cc, _ in pairs(row) do
            if not (rr == r and cc == c) then
                if not (STATE.board[rr] and STATE.board[rr][cc]) then
                    set[rr] = set[rr] or {}
                    set[rr][cc] = true
                end
            end
        end
    end

    if returnDist then
        return set, dist
    else
        return set
    end
end


-- ── Config ─────────────────────────────────────────────────────────────
cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE = 18
cardGameFortune.HAND_MAX = 5    -- cap visible hand to 5 cards

local function easeSmooth(t) return t*t*(3 - 2*t) end

-- Is any unit currently animating?
function cardGameFortune.anyAnimating()
    local s = STATE; if not s then return false end
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u = s.board[r][c]
            if u and u._anim and u._anim.kind == "slide" then return true end
        end
    end
    return false
end

-- Advance all animations by 1 frame
function cardGameFortune.stepAnimations()
    local s = STATE; if not s then return end
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u = s.board[r][c]
            if u and u._anim and u._anim.kind == "slide" then
                u._anim.t = u._anim.t + 1
                if u._anim.t >= u._anim.dur then
                    u._anim = nil
                end
            end
        end
    end
end


-- Adjacent enemy targets (units or leader)
local function rayFirstHit(c,r, dc,dr, owner)
  local x,y = c+dc, r+dr
  while inBounds(x,y) do
    local terr = terrainAt(x,y)
    if terrainBlocksLOS(terr) then
        return nil,nil  -- LOS blocked before reaching a unit
    end
    local u = STATE.board[y][x]
    if u then
      if u.owner ~= owner then return x,y end
      return nil,nil
    end
    x, y = x+dc, y+dr
  end
  return nil,nil
end

-- Manhattan helper
local function manhattan(c1,r1,c2,r2) return math.abs(c1-c2)+math.abs(r1-r2) end

function cardGameFortune.pickApproachDestination(fromC, fromR, toC, toR)
    local s = STATE
    local A = s.board[fromR] and s.board[fromR][fromC]
    if not A then return nil, nil end

    local def = cardGameFortune.db[A.cardId]
    if (def and (def.atktype or "normal")) ~= "normal" then
        return nil, nil
    end

    local movetype  = (def and (def.movementtype or def.movetype)) or "normal"
    local attackDeltas = cardGameFortune._attackOriginDeltasFor(movetype)
    
    local startTerr = cardGameFortune.terrainAt(fromC, fromR)
    local baseMov   = (def and def.movement) or 0
    local movBonus  = (cardGameFortune.terrainMovementBonus and
                       cardGameFortune.terrainMovementBonus(def and def.subtype2, startTerr)) or 0
    local budget    = math.max(0, baseMov + movBonus - 1)

    local _, dist = cardGameFortune.legalMovesFrom(fromC, fromR, { forThreat = true, returnDist = true })

    -- DEBUG: Show what we're checking
    local debugLines = {
        ("Approach from (%d,%d) to (%d,%d)"):format(fromC, fromR, toC, toR),
        ("movetype=%s budget=%d"):format(movetype, budget),
        "Attack origins:"
    }

    local bestC, bestR, bestCost
    for _, d in ipairs(attackDeltas) do
        local ac, ar = toC + d[1], toR + d[2]
        if cardGameFortune.inBounds(ac, ar) then
            local occ = cardGameFortune.safeBoardCell(s, ac, ar)
            local row  = dist[ar]
            local cost = row and row[ac] or nil
            
            -- DEBUG: Log each check
            debugLines[#debugLines+1] = ("  (%d,%d): occ=%s cost=%s valid=%s"):format(
                ac, ar, 
                tostring(occ ~= nil),
                tostring(cost),
                tostring(occ == nil and cost and cost <= budget)
            )
            
            if occ == nil then
                if cost and cost <= budget and (not bestCost or cost < bestCost) then
                    bestC, bestR, bestCost = ac, ar, cost
                end
            end
        end
    end

    debugLines[#debugLines+1] = ("Best: (%s,%s) cost=%s"):format(
        tostring(bestC), tostring(bestR), tostring(bestCost)
    )
    
    Misc.dialog(table.concat(debugLines, "\n"))

    return bestC, bestR
end



function cardGameFortune.legalAttacksFrom(c, r)
    local res = {}
    local s = STATE
    local A = s.board[r] and s.board[r][c]
    if not A or A.isLeader or A.hasAttacked then return res end

    local def = cardGameFortune.db[A.cardId]
    local atktype = (def and def.atktype) or "normal"

    -- ================= MELEE =================
    if atktype == "normal" then
        local _, dist = cardGameFortune.legalMovesFrom(c, r, { forThreat=true, returnDist=true })

        -- movement budget = base move + start-tile terrain bonus - 1
        local startTerr = cardGameFortune.terrainAt(c, r)
        local movBonus  = (cardGameFortune.terrainMovementBonus and
                           cardGameFortune.terrainMovementBonus(def and def.subtype2, startTerr)) or 0
        local maxSteps  = math.max(0, (def and def.movement or 0) + movBonus)
        local budget    = math.max(0, maxSteps - 1)

        -- movetype-aware attack origins (same as UI check)
        local attackDeltas = cardGameFortune._attackOriginDeltasFor((def and (def.movementtype or def.movetype)) or "normal")

        for rr = 0, s.rows - 1 do
            for cc = 0, s.cols - 1 do
                local D = s.board[rr] and s.board[rr][cc]
                if D and D.owner ~= A.owner then
                    local mark = false

                    -- 1) Direct strike from current tile (movetype-aware)
                    if cardGameFortune.isMeleeInRange(A, c, r, cc, rr) then
                        mark = true
                    else
                        -- 2) Approach: any EMPTY attack-origin tile reachable within budget
                        for _,dlt in ipairs(attackDeltas) do
                            local ac, ar = cc + dlt[1], rr + dlt[2]
                            if cardGameFortune.inBounds(ac, ar) then
                                local occ = cardGameFortune.safeBoardCell(s, ac, ar)
                                if occ == nil then
                                    local row  = dist[ar]
                                    local cost = row and row[ac] or nil
                                    -- CRITICAL: Only mark if reachable within budget
                                    if cost and cost <= budget then
                                        mark = true
                                        break
                                    end
                                end
                            end
                        end
                    end

                    if mark then
                        res[rr] = res[rr] or {}
                        res[rr][cc] = true
                    end
                end
            end
        end

        return res
    end

    -- ================= RANGED =================
    -- Ranged never approaches; it raycasts within attackrange along LOS.
    local range = (def and def.attackrange) or math.huge
    local owner = A.owner
    local shape = (def and def.rangedLOS) or "orthogonal"
    local dirs = (shape == "orthogonal") and cardGameFortune.DIR4
              or (shape == "diagonal")   and cardGameFortune.DIAG4
              or cardGameFortune.DIR8

    for _, d in ipairs(dirs) do
        local x, y = c, r
        for step = 1, range do
            x = x + d[1]; y = y + d[2]
            if not cardGameFortune.inBounds(x, y) then break end
            local terr = cardGameFortune.terrainAt(x, y)
            if cardGameFortune.terrainBlocksLOS and cardGameFortune.terrainBlocksLOS(terr) then break end

            local V = s.board[y] and s.board[y][x]
            if V then
                if V.owner ~= owner then
                    res[y] = res[y] or {}; res[y][x] = true
                end
                break
            end
        end
    end

    return res
end




-- Start a short summon effect on a unit table `u`
function cardGameFortune.addSummonFX(u)
    u._fx = { kind="summon", t=0, dur=22, flash=6, sparks={} }  -- was dur ~18; add flash window
    for i=1,8 do                                                -- a couple more sparks
        local ox = -10 + math.random()*20
        local oy = -10 + math.random()*20
        local life = 12 + math.random(8)                        -- a tad longer
        u._fx.sparks[i] = {x=ox, y=oy, t=0, dur=life}
    end
end

-- ========== HIT FX (flash + light shake) ==========

-- start a quick hit FX on a unit table `u`
function cardGameFortune.addHitFX(u, flashes, shake)
    if not u then return end
    u._hitfx = { t = 0, flashes = flashes or 6, shake = shake or 2 }
end


-- Draw a bright flash *over the sprite* + tiny shake on hit
function cardGameFortune.drawHitFX(u, drawX, drawY)
    local fx = u and u._hitfx
    if not fx then return end

    local t       = fx.t or 0
    local flashes = fx.flashes or 6
    local shake   = fx.shake   or 2

    -- blink on for 1 frame, off for 1 frame, repeat (2*flashes frames total)
    local blinkOn = (t % 2 == 0) and (t < flashes * 2)
    local alpha   = blinkOn and 0.55 or 0

    -- subtle 1px shake left/right
    local ox = 0
    if shake > 0 and t > 0 then
        ox = ((t % 2) == 0) and shake or -shake
    end

    if alpha > 0 then
        -- try to re-draw the unit icon in white to "light up" the sprite
        local def = u.cardId and cardGameFortune.db[u.cardId]
        local texPath = def and def.icon
        local img = texPath and Graphics.loadImage(texPath)

        if img then
            -- white-tinted copy of the sprite (same size, on top of the original)
            Graphics.drawBox{
                texture  = img,
                x        = drawX + ox,
                y        = drawY,
                width    = img.width,
                height   = img.height,
                color    = Color(1,1,1, alpha),
                priority = 5.12,          -- slightly above your unit (you draw units at 5.0)
            }
        else
            -- fallback: slightly oversized white tile to cover the whole cell
            local CELL = (CFG and CFG.CELL) or 32
            Graphics.drawBox{
                x        = drawX - 1 + ox,
                y        = drawY - 1,
                width    = CELL + 2,
                height   = CELL + 2,
                color    = Color(1,1,1, alpha),
                priority = 5.12,
            }
        end
    end
end


function cardGameFortune.stepFX()
    local s = STATE; if not s then return end

    -- advance on-board unit FX (summon / hit) per unit
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u = s.board[r] and s.board[r][c]
            if u then
                -- summon FX
                if u._fx and u._fx.kind == "summon" then
                    u._fx.t = u._fx.t + 1
                    for _,p in ipairs(u._fx.sparks) do p.t = p.t + 1 end
                    if u._fx.t >= u._fx.dur then u._fx = nil end
                end
                -- hit FX
                if u._hitfx then
                    local f = u._hitfx
                    f.t = (f.t or 0) + 1
                    -- each flash is 6 frames (3 on, 3 off)
                    if f.t >= ((f.flashes or 4) * 6) then u._hitfx = nil end
                end
            end
        end
    end

    -- advance "death" FX ONCE per frame (global pool)
    if s.deathFX then
        local i = 1
        while i <= #s.deathFX do
            local f = s.deathFX[i]
            f.t = (f.t or 0) + 1
            if f.t >= (f.dur or 24) then
                table.remove(s.deathFX, i)
            else
                i = i + 1
            end
        end
    end
end



function cardGameFortune.addDeathFXFromUnit(u, c, r, opts)
    if not u then return end
    local def   = cardGameFortune.db[u.cardId]
    local sprite= def and (def.image or def.icon)  -- path used by your tex() loader
    STATE.deathFX = STATE.deathFX or {}
    table.insert(STATE.deathFX, {
        kind   = "death",
        c      = c, r = r,
        sprite = sprite,
        t      = 0,
        dur    = (opts and opts.dur) or 24,   -- <- ~0.4s at 60fps
        scale  = (opts and opts.scale) or 1.0 -- optional
    })
end

local function _easeOut(t) return 1 - (1 - t)*(1 - t) end

function cardGameFortune.drawDeathFX(boardX, boardY, priority)
    local s = STATE; if not (s and s.deathFX) then return end
    local tex = CFG and CFG.tex or Graphics.loadImage -- your tex getter

    for _,f in ipairs(s.deathFX) do
        local T = math.max(0, math.min(1, (f.t or 0) / (f.dur or 24)))
        local alpha = 1 - T                          -- fade to 0
        local scale = 1.0 + 0.25 * _easeOut(T)       -- slight puff out
        local x = boardX + f.c * CFG.CELL
        local y = boardY + f.r * CFG.CELL

        local img = nil
        if f.img then img = tex(f.img) end
        if (not img) and f.icon then img = tex(f.icon) end

        if img then
            local w,h = img.width, img.height
            local dw, dh = math.floor(w*scale), math.floor(h*scale)
            local dx = x + math.floor((CFG.CELL - dw)/2)
            local dy = y + math.floor((CFG.CELL - dh)/2)
            Graphics.drawBox{
                texture = img,
                x = dx, y = dy,
                width = dw, height = dh,
                color = Color(1,1,1, alpha),
                priority = priority or 5.06,
            }
        else
            -- fallback: white fade square
            Graphics.drawBox{
                x = x, y = y, width = CFG.CELL, height = CFG.CELL,
                color = Color(1,1,1, alpha*0.6),
                priority = priority or 5.06,
            }
        end
    end
end


local function _sign(x) return (x>0 and 1) or (x<0 and -1) or 0 end

-- set a single slide animation on this unit
local function _setSlide(u, c1,r1, c2,r2, framesPerTile)
    local base = (framesPerTile or cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE or 18)
    u._anim = {
        kind = "slide",
        fromC = c1, fromR = r1,
        toC   = c2, toR   = r2,
        t     = 0,
        dur   = math.max(1, base),  -- one-tile slide
        ease  = easeSmooth,
    }
end

-- sign helper (if you don’t already have one here)
local function _sgn(x) return (x>0 and 1) or (x<0 and -1) or 0 end

-- Produce a per-tile path for a straight line (horizontal, vertical, or diagonal).
-- It steps one tile per frame chunk so your existing _setSlide/stepAnimations work unchanged.
local function _buildLinePath(c1,r1, c2,r2)
    local path = {}
    local dc, dr = c2 - c1, r2 - r1
    local sc, sr = _sgn(dc), _sgn(dr)
    local steps  = math.max(math.abs(dc), math.abs(dr))
    local c, r   = c1, r1
    for i=1,steps do
        c = c + sc
        r = r + sr
        path[#path+1] = {c=c, r=r}
    end
    return path
end

-- Decide whether this movetype should render as a single straight line (incl. diagonal)
local function _prefersLineAnim(movetype, dc, dr)
    movetype = movetype or "normal"
    local adx, ady = math.abs(dc), math.abs(dr)

    -- bishop/queen diagonal: pure diagonal lines
    if (movetype == "bishop" or movetype == "queen") and adx == ady and adx > 0 then
        return true, "diag"
    end
    -- rook/queen straight: pure horizontal/vertical lines
    if (movetype == "rook" or movetype == "queen") and (adx == 0 or ady == 0) and (adx+ady) > 0 then
        return true, "straight"
    end
    -- checkers-like "diagonal" type: treat any move that uses both axes as a diagonal line
    if movetype == "diagonal" and adx == ady and adx > 0 then
        return true, "diag"
    end
    return false
end

-- Public: animate with the best-looking path for the unit’s movement type.
-- Falls back to your original orthogonal L-path when needed.
function cardGameFortune._animateSmartSlide(u, c1,r1, c2,r2, movetype, framesPerTile)
    local dc, dr = c2 - c1, r2 - r1
    local useLine = _prefersLineAnim(movetype, dc, dr)

    local path
    if useLine then
        path = _buildLinePath(c1,r1, c2,r2)      -- single straight (H/V/diag) path
    else
        -- fallback to the old “orthogonal chain”: first the dominant axis, then the other
        local horizFirst = math.abs(dc) >= math.abs(dr)
        path = {}
        local c, r = c1, r1
        if horizFirst then
            while c ~= c2 do c = c + _sgn(dc); path[#path+1] = {c=c, r=r} end
            while r ~= r2 do r = r + _sgn(dr); path[#path+1] = {c=c, r=r} end
        else
            while r ~= r2 do r = r + _sgn(dr); path[#path+1] = {c=c, r=r} end
            while c ~= c2 do c = c + _sgn(dc); path[#path+1] = {c=c, r=r} end
        end
    end

    -- Play the chain (one _setSlide per tile, same timing you already use)
    Routine.run(function()
        local pc, pr = c1, r1
        local fpt = framesPerTile or cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE or 18
        for i=1,#path do
            local tc, tr = path[i].c, path[i].r
            _setSlide(u, pc, pr, tc, tr, fpt)
            for f=1,fpt do Routine.waitFrames(1) end
            pc, pr = tc, tr
        end
    end)
end


-- Chain L-shaped slides: first along the dominant axis (or always X then Y)
function cardGameFortune._animateOrthogonalSlides(u, c1,r1, c2,r2, framesPerTile)
    local path = {}
    local dc, dr = c2 - c1, r2 - r1
    local horizFirst = math.abs(dc) >= math.abs(dr)  -- or set true to always go X then Y

    local c, r = c1, r1
    if horizFirst then
        while c ~= c2 do c = c + _sign(dc); path[#path+1] = {c=c, r=r} end
        while r ~= r2 do r = r + _sign(dr); path[#path+1] = {c=c, r=r} end
    else
        while r ~= r2 do r = r + _sign(dr); path[#path+1] = {c=c, r=r} end
        while c ~= c2 do c = c + _sign(dc); path[#path+1] = {c=c, r=r} end
    end

    Routine.run(function()
        local pc, pr = c1, r1
        for i=1,#path do
            local tc, tr = path[i].c, path[i].r
            _setSlide(u, pc, pr, tc, tr, framesPerTile)
            -- let the slide play for its duration; your renderer advances u._anim.t each frame
            local frames = math.max(1, framesPerTile or cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE or 8)
            for f=1,frames do Routine.waitFrames(1) end
            pc, pr = tc, tr
        end
    end)
end


function cardGameFortune.moveUnit(c1,r1, c2,r2, opts)   -- <— add opts
    local s = STATE; local u = s.board[r1] and s.board[r1][c1]
    if not u then return false,"no unit" end
    if u.owner ~= s.whoseTurn then return false,"not your unit/turn" end
    if u.hasMoved then return false,"already moved" end
    if s.board[r2] and s.board[r2][c2] then return false,"occupied" end

    local legal = u.isLeader and cardGameFortune.legalLeaderMovesFrom(c1,r1)
                               or  cardGameFortune.legalMovesFrom(c1,r1)
    if not (legal[r2] and legal[r2][c2]) then return false,"illegal dest" end

    -- apply move
    s.board[r2][c2] = u
    s.board[r1][c1] = nil

    do
        local def = cardGameFortune.db[u.cardId]
        if def and def.atktype == "ranged" and (not (opts and opts.keepAttack)) then
            u.hasAttacked = true
        end
    end

    if not u.isLeader then u.pos = "attack" end
    u.hasMoved = true
    cardGameFortune.sfx_move()

    local keep = opts and opts.keepAttack
    if not keep then u.hasAttacked = true end

    if u.isLeader and s.leaderPos and s.leaderPos[u.owner] then
        s.leaderPos[u.owner].c, s.leaderPos[u.owner].r = c2, r2
    end

    local def = u.cardId and cardGameFortune.db[u.cardId]
    local movetype = def and (def.movementtype)
    if cardGameFortune._animateSmartSlide then
        cardGameFortune._animateSmartSlide(u, c1, r1, c2, r2, movetype, cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE)
    end

    return true
end


-- Defeat (fade-out) FX
-- Start a short "corpse fade" on a removed unit
function cardGameFortune.addDeathFX(u, c, r, opts)
    local s = STATE; if not (s and u) then return end
    s.deathFX = s.deathFX or {}

    local def = cardGameFortune.db[u.cardId]
    table.insert(s.deathFX, {
        c = c, r = r,
        img = def and def.image,    -- big art if available
        icon = def and def.icon,    -- fallback to icon
        t = 0,
        dur = (opts and opts.dur) or 24,
        flashes = 0,                 -- not blinking; just fade/scale
    })
end


-- extend your existing FX stepper (keep your old code, just add this block)
do
    local _oldStepFX = cardGameFortune.stepFX
    function cardGameFortune.stepFX()
        if _oldStepFX then _oldStepFX() end

        local list = STATE and STATE.deathFX
        if not list then return end
        local i = 1
        while i <= #list do
            local f = list[i]
            f.t = f.t + 1
            if f.t >= f.dur then table.remove(list, i) else i = i + 1 end
        end
    end
end


-- Switch a unit from ATK to DEF as your "movement" for the turn.
function cardGameFortune.fortifyToDefense(c,r)
    local s = STATE; if not s then return false,"no state" end
    local u = s.board[r] and s.board[r][c]
    if not u or u.isLeader then return false,"no unit" end
    if u.owner ~= s.whoseTurn then return false,"not your unit" end
    if u.summoningSickness then return false,"summoning" end
    if u.hasMoved then return false,"already moved" end 
    if u.hasAttacked then return false,"already attacked" end
    if u.pos == "defense" then return false,"already defense" end

    u.pos = "defense"
    u.hasMoved = true 
    u.hasAttacked = true         
    return true
end

-- YGO-like battle resolution, non-random
function cardGameFortune.resolveBattle(ac,ar, dc,dr)
    local s = STATE; if not s then return false,"no state" end
    local A = s.board[ar] and s.board[ar][ac]
    local D = s.board[dr] and s.board[dr][dc]

    if (not A) or (not D) then return false,"no piece" end
    if A.owner ~= s.whoseTurn then return false,"not your turn" end
    if A.owner == D.owner then return false,"same owner" end
    if A.hasAttacked then return false,"already attacked" end

    if not A.isLeader and A.pos ~= "attack" then
        A.pos = "attack"
    end

    local aDef = cardGameFortune.db[A.cardId]
    local atktype = (aDef and (aDef.atktype or "normal")) or "normal"
    local isMelee = (atktype == "normal")

    if atktype == "normal" then
        cardGameFortune.sfx_combat()
    else
        cardGameFortune.sfx_ranged(aDef)   -- Magikoopa/Bullet Blaster support, else Combat.wav
    end


    -- attacker stats tile:
    --   melee  -> defender's tile
    --   ranged -> attacker's tile
    local atkC, atkR = (isMelee and dc or ac), (isMelee and dr or ar)
    local aATK = select(1, cardGameFortune.getEffectiveStats(aDef, atkC, atkR))
    do
        local aType = cardGameFortune.unitType(A)
        local dType = cardGameFortune.unitType(D)
        aATK = aATK + cardGameFortune.roleAtkBonus(aType, dType)
    end

    local destroyA, destroyD = false, false
    local damagePlayer, damageAmt = nil, 0

    -- ...after deciding outcome, before removals...
    local attackerWillDie = destroyA
    local defenderWillDie = destroyD

    -- Flash whoever takes damage and survives the board state update
    if not defenderWillDie then cardGameFortune.addHitFX(D) end
    if not attackerWillDie and (D.pos == "attack" and aATK < ((cardGameFortune.getEffectiveStats(cardGameFortune.db[D.cardId], dc, dr))) ) then
        -- attacker lost in ATK vs ATK → flash attacker too
        cardGameFortune.addHitFX(A)
    end

    if D.isLeader then
        -- direct hit to leader
        damagePlayer, damageAmt = D.owner, aATK
    else
        local dDef = cardGameFortune.db[D.cardId]
        local dATK, dDEF = cardGameFortune.getEffectiveStats(dDef, dc, dr)
        local rhs = (D.pos == "attack") and dATK or dDEF
        local lhs = aATK

        if D.pos == "attack" then
          if     lhs > rhs then
              destroyD = true
              damagePlayer, damageAmt = D.owner, lhs - rhs
          elseif lhs < rhs then
              destroyA = true
              damagePlayer, damageAmt = A.owner, rhs - lhs
          else
              destroyA, destroyD = true, true
          end

        else 
            if     lhs > rhs then destroyD = true
            elseif lhs < rhs then damagePlayer, damageAmt = A.owner, rhs - lhs
            end
        end
    end

    -- VISUAL HIT FX (non-lethal and lethal both get the flash)
    do
        -- If defender is getting hit (either destroyed or took damage), blink it
        if destroyD or (not D.isLeader and damagePlayer == A.owner and damageAmt > 0) then
            cardGameFortune.addHitFX(D, {dur=14, flashes=4, shake=1})
        end
        -- If attacker is getting hit (either destroyed or took damage), blink it
        if destroyA or (damagePlayer == A.owner and damageAmt > 0 and D.pos == "attack" and not (destroyD and damageAmt == (aATK or 0))) then
            cardGameFortune.addHitFX(A, {dur=14, flashes=4, shake=1})
        end
        -- Leader direct damage: make attacker flash briefly (impact feedback)
        if D.isLeader and damageAmt > 0 then
            cardGameFortune.addHitFX(A, {dur=10, flashes=3, shake=1})
        end
    end

    cardGameFortune.addHitFX(A, 4, 1)
    cardGameFortune.addHitFX(D, 4, 1)

    -- spawn corpse fades *before* we remove them from the board
    if destroyD then cardGameFortune.addDeathFXFromUnit(D, dc, dr, {dur=24}) end
    if destroyA then cardGameFortune.addDeathFXFromUnit(A, ac, ar, {dur=24}) end

    local playedKill = false
    if destroyD and not playedKill then cardGameFortune.sfx_kill(); playedKill = true end
    if destroyA and not playedKill then cardGameFortune.sfx_kill(); playedKill = true end

    -- log to grave before removing from board
    if destroyD then
    cardGameFortune.addDeathFX(D, dc, dr)
    cardGameFortune.sfx_kill()
    if D and D.cardId then cardGameFortune.pushToGrave(D.owner, D.cardId, "KO", A and A.cardId) end
    s.board[dr][dc] = nil
    end
    if destroyA then
        cardGameFortune.addDeathFX(A, ac, ar)
        cardGameFortune.sfx_kill()
        if A and A.cardId then cardGameFortune.pushToGrave(A.owner, A.cardId, "KO", D and D.cardId) end
        s.board[ar][ac] = nil
    end



    -- ADVANCE ON CAPTURE (melee only; do not advance onto leader)
    if isMelee and destroyD and not (D and D.isLeader) then
        local s = STATE
        local mover = s.board[ar] and s.board[ar][ac]   -- attacker still alive?
        if mover then
            -- must be allowed to end on defender's terrain
            local terr = cardGameFortune.terrainAt(dc, dr)
            local mdef = cardGameFortune.db[mover.cardId]
            if cardGameFortune.canEnter(mdef, terr) then
                -- Update board first (same order as moveUnit), then animate from old tile → new tile
                s.board[dr][dc] = mover
                s.board[ar][ac] = nil

                -- keep unit coords in sync if you track them
                mover.c, mover.r = dc, dr

                -- spend the action
                mover.hasAttacked = true

                -- Slide using movetype-aware path (diag for bishop/queen, straight for rook/queen)
                local mdef     = cardGameFortune.db[mover.cardId]
                local movetype = mdef and mdef.movementtype

                if cardGameFortune._animateSmartSlide then
                    cardGameFortune._animateSmartSlide(
                        mover,              -- unit
                        ac, ar,             -- from (approach tile)
                        dc, dr,             -- to (captured tile)
                        movetype,
                        cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE
                    )
                else
                    -- safe fallback if helper not loaded
                    _setSlide(mover, ac, ar, dc, dr, cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE)
                end
            end
        end
    end

    if damagePlayer and damageAmt > 0 then
        s.leaderHP = s.leaderHP or {[1]=40,[2]=40}
        s.leaderHP[damagePlayer] = math.max(0, (s.leaderHP[damagePlayer] or 40) - damageAmt)
    end

    -- mark attack spent if the attacker survived / still exists
    if s.board[ar] and s.board[ar][ac] then
        s.board[ar][ac].hasAttacked = true
    end

    return true, {destroyAttacker=destroyA, destroyDefender=destroyD, leader=damagePlayer, damage=damageAmt}
end



-- Public: start a fresh match
function cardGameFortune.newMatch(seed)
  local nextRand, getSeed = rng(seed or os.time())
  STATE.seed      = getSeed()
  STATE.board     = new2D(STATE.rows, STATE.cols)
  STATE.whoseTurn = 1
  STATE.phase     = "main"
  STATE.leaderHP  = { 40, 40 }
  STATE.energy    = { 6, 6 }
  STATE.discard   = { {}, {} }

  local d1 = buildStarterDeck()
  local d2 = buildStarterDeck()
  shuffle(d1, nextRand)
  shuffle(d2, nextRand)
  STATE.deck  = { d1, d2 }
  STATE.hands = { {}, {} }
  STATE.grave = { [1]={}, [2]={} }

  cardGameFortune.draw(1,5)
  cardGameFortune.draw(2,5)

  -- Center column on top/bottom rows
    local midC = math.floor((STATE.cols-1)/2)
    STATE.leaderPos = { {c=midC, r=STATE.rows-1}, {c=midC, r=0} }

    -- Place leaders as special cells
    STATE.board[STATE.leaderPos[1].r][STATE.leaderPos[1].c] = {
        owner=1, hp=STATE.leaderHP[1] or 40, pos="defense", isLeader=true
    }
    STATE.board[STATE.leaderPos[2].r][STATE.leaderPos[2].c] = {
        owner=2, hp=STATE.leaderHP[2] or 40, pos="defense", isLeader=true
    }
    
    cardGameFortune.ensureLeaderConnectivity()

    cardGameFortune.regenTerrain()
end

local function inBounds(c, r)
    return (STATE ~= nil)
       and (c >= 0 and c < STATE.cols)
       and (r >= 0 and r < STATE.rows)
end

function cardGameFortune.canSummonAt(player, c, r, cardId)
  if not inBounds(c,r) then return false, "Out of bounds" end
  if STATE.board[r][c] then return false, "Tile occupied" end
  local lp = STATE.leaderPos and STATE.leaderPos[player]
  if not lp then return false, "No leader" end
  if not isAdjacent(lp.c, lp.r, c, r) then
    return false, "Must be next to your leader"
  end

  if cardId then
    local def  = cardGameFortune.db[cardId]
    local terr = terrainAt(c,r)
    if not canEnter(def, terr) then
      return false, "Cannot enter "..terr
    end
  end

  return true
end


-- Accessors
function cardGameFortune.isOpen() return STATE.open end
function cardGameFortune.open() STATE.open = true end
function cardGameFortune.close() STATE.open = false end
function cardGameFortune.toggle() STATE.open = not STATE.open end

-- Cards in hand / deck
function cardGameFortune.draw(player, n)
  n = n or 1
  local hand = STATE.hands[player]
  local deck = STATE.deck[player]
  for i=1,n do
    local top = table.remove(deck, 1)
    if not top then break end
    hand[#hand+1] = top
  end
end

function cardGameFortune.pushToGrave(owner, cardId, reason, by)
    local s = STATE; if not s then return end
    s.grave = s.grave or { [1]={}, [2]={} }
    s.grave[1] = s.grave[1] or {}
    s.grave[2] = s.grave[2] or {}
    if not cardId then return end
    table.insert(s.grave[owner], {cardId=cardId, reason=reason or "KO", by=by, turn=s.turn or 0})
end

function cardGameFortune.lastGrave(owner)
  local g = STATE and STATE.grave and STATE.grave[owner]
  if not g or #g == 0 then return nil end
  return g[#g]
end


-- Simple cost check / spend
local function canAfford(player, cardId)
  local card = cardGameFortune.db[cardId]; if not card then return false end
  return (STATE.energy[player] or 0) >= (card.summoncost or 0)
end
local function spend(player, cardId)
  local card = cardGameFortune.db[cardId]
  STATE.energy[player] = STATE.energy[player] - (card.summoncost or 0)
end

-- Place a card from hand onto [c,r] if empty and affordable
-- Returns true/false and a message
function cardGameFortune.playFromHand(player, handIndex, c, r, position)
    
    if STATE.whoseTurn ~= player then return false, "not your turn" end

    local hand   = STATE.hands[player]
    local cardId = hand[handIndex]
    if not cardId then return false, "No card in that hand slot" end

    local ok, err = cardGameFortune.canSummonAt(player, c, r, cardId)
    if not ok then return false, err end

    
    -- position = "attack" or "defense"
    if not inBounds(c,r) then return false,"Out of bounds" end
    if STATE.board[r][c] then return false,"Tile occupied" end

    local hand     = STATE.hands[player]
    local cardId   = hand[handIndex]
    if not cardId then return false,"No card in that hand slot" end
    if not canAfford(player, cardId) then return false,"Not enough energy" end
    local base     = cardGameFortune.db[cardId]

    -- remove from hand + pay
    table.remove(STATE.hands[player], handIndex)
    spend(player, cardId)


    local pos   = (position == "defense") and "defense" or "attack"
    local hpVal = (pos == "defense") and (base.def or 0) or (base.atk or 0)

    -- build the unit, then place it
    local u = {
        cardId = cardId,
        owner  = player,
        atk    = base.atk or 0,
        def    = base.def or 0,
        hp     = hpVal,
        pos    = pos,
        summoningSickness = false,   -- optional: if you use this flag
    }
    STATE.board[r][c] = u

    -- start summon flair (and optional SFX)
    cardGameFortune.addSummonFX(u)
    cardGameFortune.sfx_summon()


    return true, "Placed"
end

-- End the current player's turn (refresh energy and draw)
function cardGameFortune.endTurn()
  local np = (STATE.whoseTurn == 1) and 2 or 1
  STATE.whoseTurn = np
  STATE.phase = "main"

  -- start-of-turn resources for the new active player
  STATE.energy[np] = (STATE.energy[np] or 0) + 3
    if (#STATE.hands[np] or 0) < (cardGameFortune.HAND_MAX or 5) then
        cardGameFortune.draw(np, 1)
    end

  -- refresh per-unit action flags for the new active player
  for r=0,STATE.rows-1 do
    for c=0,STATE.cols-1 do
      local u = STATE.board[r][c]
      if u and u.owner == np then
        u.hasMoved, u.hasAttacked = false, false
        if u.summoningSickness then u.summoningSickness = false end
      end
    end
  end
end

-- Can u at (c,r) hit enemy leader next turn?
local function ai_potentialLeaderThreatFrom(c,r, u)
    local s=STATE; local foe=(u.owner==1) and 2 or 1
    local lp = s.leaderPos and s.leaderPos[foe]; if not lp then return false end
    return cardGameFortune.ai_unitCanHitTile(u, c, r, lp.c, lp.r)
end

-- Count enemies newly threatened from (c,r) by u
local function ai_newThreatsFrom(c,r, u)
    local s=STATE; local foe=(u.owner==1) and 2 or 1; local n=0
    for rr=0,s.rows-1 do
        for cc=0,s.cols-1 do
            local e=s.board[rr] and s.board[rr][cc]
            if e and e.owner==foe and not e.isLeader then
                if cardGameFortune.ai_unitCanHitTile(u, c, r, cc, rr) then n = n + 1 end
            end
        end
    end
    return n
end


-- Tiny combat calculator (expand later with your full tables/terrain)
function cardGameFortune.calcCombat(attackerCell, defenderCell, terrain)
    -- attackerCell and defenderCell are full board entries:
    -- { cardId, owner, atk, def, hp, pos }
    local a = cardGameFortune.db[attackerCell.cardId]
    local d = cardGameFortune.db[defenderCell.cardId]
    if not a or not d then return nil, "invalid cards" end

    local atkVal = a.atk or 0
    local defVal = (defenderCell.pos == "defense") and (d.def or 0) or (d.atk or 0)

    -- base delta
    local delta = atkVal - defVal

    -- apply type / atktype / terrain bonuses here
    local bonus = 0
    -- ... (your existing roleBonus, attackTypeBonus, terrainBonus lookups)
    delta = delta + bonus

    -- resolve outcome
    if defenderCell.pos == "defense" then
        if delta > 0 then
            defenderCell.hp = defenderCell.hp - delta
            if defenderCell.hp <= 0 then return "defender destroyed" end
            return "defense holds"
        else
            return "no damage"
        end
    else
        -- both in attack
        defenderCell.hp = defenderCell.hp - math.max(0, delta)
        attackerCell.hp = attackerCell.hp - math.max(0, -delta)

        if defenderCell.hp <= 0 and attackerCell.hp <= 0 then
            return "both destroyed"
        elseif defenderCell.hp <= 0 then
            return "defender destroyed"
        elseif attackerCell.hp <= 0 then
            return "attacker destroyed"
        else
            return "both survive"
        end
    end
end

-- Can attacker at (ac,ar) attack (dc,dr)? (adjacent 8-way by default)
local function canAttack(ac,ar, dc,dr)
    if not inBounds(ac,ar) or not inBounds(dc,dr) then return false end
    local A = STATE.board[ar][ac]; local D = STATE.board[dr][dc]
    if not A or not D then return false end
    if A.isLeader or D.isLeader then return true end -- allow leader as target
    if A.owner == D.owner then return false end
    local dcAbs, drAbs = math.abs(ac-dc), math.abs(ar-dr)
    return math.max(dcAbs,drAbs) == 1   -- 8-way adjacency
end

-- Non-destructive combat preview: what would happen?
function cardGameFortune.previewCombat(ac,ar, dc,dr)
    local s = STATE
    if not s then return false, "No state" end

    local A = s.board[ar] and s.board[ar][ac]
    local D = s.board[dr] and s.board[dr][dc]
    if (not A) or (not D) then return false, "No valid attacker/target" end
    if A.owner == D.owner then return false, "Same owner" end

    -- Verify target is legal per current attack rules
    local legal = cardGameFortune.legalAttacksFrom(ac,ar)
    if not (legal[dr] and legal[dr][dc]) then
        return false, "Illegal target"
    end

    local aDef = cardGameFortune.db[A.cardId]
    local atktype = (aDef and (aDef.atktype or "normal")) or "normal"
    local isMelee = (atktype == "normal")

    -- Attacker stats tile:
    --   melee  -> defender's tile (dc,dr)
    --   ranged -> attacker's tile (ac,ar)
    local atkC, atkR = (isMelee and dc or ac), (isMelee and dr or ar)

    local aATK, aDEF, aTerr, aDelta = cardGameFortune.getEffectiveStats(aDef, atkC, atkR)

    local aType = cardGameFortune.unitType(A)
    local dType = cardGameFortune.unitType(D)
    local aRoleBonus = cardGameFortune.roleAtkBonus(aType, dType)
    aATK = aATK + aRoleBonus

    -- Leader target: direct damage = attacker ATK
    if D.isLeader then
        return true, {
            mode="vsLEADER",
            aATK=aATK, aDEF=aDEF, aTerr=aTerr, aBonus=aDelta,
            dATK=nil,  dDEF=nil,  dTerr=nil,  dBonus=0,
            using="ATK", against="LEADER",
            diff = aATK,
            destroyAttacker=false, destroyDefender=false,
            leaderDamage = { player=D.owner, amount=aATK },
            attType=aType, defType=dType, aRole=aRoleBonus,
        }
    end

    -- Defender is a unit
    local dDef = cardGameFortune.db[D.cardId]
    local dATK, dDEF, dTerr, dDelta = cardGameFortune.getEffectiveStats(dDef, dc, dr)

    local using   = "ATK"                                     -- attacker always uses ATK
    local against = (D.pos == "attack") and "ATK" or "DEF"    -- defender uses ATK or DEF
    local lhs     = aATK
    local rhs     = (against == "ATK") and dATK or dDEF

    local destroyA, destroyD = false, false
    local leaderDmgPlayer, leaderDmgAmt = nil, 0

    if D.pos == "attack" then
        if     lhs > rhs then destroyD = true; leaderDmgPlayer = D.owner; leaderDmgAmt = lhs - rhs
        elseif lhs < rhs then destroyA = true
        else destroyA, destroyD = true, true
        end
    else -- defense
        if     lhs > rhs then destroyD = true
        elseif lhs < rhs then leaderDmgPlayer = A.owner; leaderDmgAmt = rhs - lhs
        end
    end

    return true, {
        mode="vsUNIT",
        aATK=aATK, aDEF=aDEF, aTerr=aTerr, aBonus=aDelta,
        dATK=dATK, dDEF=dDEF, dTerr=dTerr, dBonus=dDelta,
        using=using, against=against,
        diff = lhs - rhs,
        destroyAttacker = destroyA,
        destroyDefender = destroyD,
        leaderDamage = (leaderDmgAmt>0) and {player=leaderDmgPlayer, amount=leaderDmgAmt} or nil,
        attType=aType, defType=dType, aRole=aRoleBonus,
    }
end



-- Expose state read-only (for UI)
function cardGameFortune.peek()
  -- return lightweight snapshot (avoid leaking internals by reference)
  return {
    open       = STATE.open,
    cols       = STATE.cols, rows = STATE.rows,
    whoseTurn  = STATE.whoseTurn,
    phase      = STATE.phase,
    leaderHP   = { STATE.leaderHP[1], STATE.leaderHP[2] },
    energy     = { STATE.energy[1], STATE.energy[2] },
    hands      = { shallowCopy(STATE.hands[1]), shallowCopy(STATE.hands[2]) },
    deckCounts = { #STATE.deck[1], #STATE.deck[2] },
    discardCounts = { #STATE.discard[1], #STATE.discard[2] },
    board      = STATE.board,
    grave = {
  shallowCopy( (STATE.grave and STATE.grave[1]) or {} ),
  shallowCopy( (STATE.grave and STATE.grave[2]) or {} ),
    },
  }
end

local function newCard(t) return t end

local CARDS = {

-- TEMPLATE
{
  id          = "unique_id_here",
  name        = "Display Name",
  image       = "cardgame/goombacard.png",     -- ok to leave as default path for now
  icon        = "cardgame/goombaicon.png",
  description = "Short flavor or ability text.",
  type        = "melee",                    -- melee|defensive|grappler|ranged|magic|tower
  atk         = 3,
  def         = 2,
  movement    = 1,
  movementtype= "normal",                   -- normal|diagonal|rook|bishop|knight|queen
  atktype     = "normal",                   -- normal|ranged|pierce|volley
  subtype1    = "normal",                   -- normal|flying|ghost|lava
  subtype2    = "overworld",                -- terrain tag
  summoncost  = 1,                          -- cost to summon to board
  deckcost    = 1,                          -- cost to add to deck
},
    
-- MELEE
    newCard{
        id="goomba", name="Goomba",
        image="cardgame/goombacard.png", icon="cardgame/goombaicon.png",
        description="A basic enemy. Weak alone, strong in numbers.",
        type="Melee", atk=3, def=2, movement=1,
        movementtype="normal", atktype="normal",
        subtype1="normal", subtype2="Overworld",
        summoncost=1, deckcost=1
    },

-- DEFENSIVE
    newCard{
        id="green_koopa", name="Green Koopa",
        image="cardgame/koopacard.png", icon="cardgame/koopaicon.png",
        description="Hides in its shell when attacked.",
        type="Defensive", atk=3, def=4, movement=1,
        movementtype="diagonal", atktype="normal",
        subtype1="normal", subtype2="Overworld",
        summoncost=2, deckcost=2
    },

-- GRAPPLER
    newCard{
        id="chargin_chuck", name="Chargin’ Chuck",
        image="cardgame/chuckcard.png", icon="cardgame/chuckicon.png",
        description="Rams into foes with football tackles.",
        type="Grappler", atk=6, def=5, movement=1,
        movementtype="knight", atktype="normal",
        subtype1="normal", subtype2="Overworld",
        summoncost=3, deckcost=3
    },

-- RANGED
    newCard{
        id="hammer_bro", name="Hammer Bro",
        image="cardgame/hammerbrocard.png", icon="cardgame/hammerbroicon.png",
        description="Throws hammers from afar.",
        type="Ranged", atk=7, def=4, movement=1,
        movementtype="bishop", attackrange = 2, atktype="Ranged", rangedLOS="diagonal",
        subtype1="normal", subtype2="Overworld",
        summoncost=4, deckcost=4
    },

-- MAGIC
    newCard{
        id="magikoopa", name="Magikoopa",
        image="cardgame/magikoopacard.png", icon="cardgame/magikoopaicon.png",
        description="Casts unpredictable magic blasts.",
        type="Magic", atk=9, def=5, movement=4,
        movementtype="queen", attackrange = 4, atktype="Ranged", rangedLOS="any",
        subtype1="normal", subtype2="Castle",
        summoncost=5, deckcost=5
    },

-- TOWER
    newCard{
        id="bill_blaster", name="Bill Blaster",
        image="cardgame/billblastercard.png", icon="cardgame/billblastericon.png",
        description="Stationary cannon that fires Bullet Bills.",
        type="Tower", atk=6, def=12, movement=0,
        movementtype="normal", attackrange = 7, atktype="Ranged", rangedLOS="orthogonal",
        subtype1="normal", subtype2="Castle",
        summoncost=6, deckcost=6
    },
}

-- helper to register:
for _,c in ipairs(CARDS) do
  cardGameFortune.register(c)
end

function cardGameFortune.get(id) return cardGameFortune.db[id] end

-- ───────────────────────────────────────────────────────────
-- STEP SCHEDULER (frame-based)
-- ───────────────────────────────────────────────────────────
cardGameFortune.aiState = {busy=false, steps={}, delay=0, stepDelay=14}
cardGameFortune.aiJustEnded = false  -- tells UI to reset when AI finishes

local function aiQueue(fn, delay)
    local st = cardGameFortune.aiState
    st.steps[#st.steps+1] = function()
        fn()
        st.delay = (delay ~= nil) and delay or st.stepDelay
    end
end

function cardGameFortune.aiUpdate()
    local st = cardGameFortune.aiState
    if not st.busy then return end
    if st.delay > 0 then st.delay = st.delay - 1; return end
    local step = table.remove(st.steps, 1)
    if step then
        step()
    else
        st.busy = false
    end
end

-- ───────────────────────────────────────────────────────────
-- Simple helpers (reuse or keep if you don't have them)
-- ───────────────────────────────────────────────────────────

local AI = {
  W_SAFETY    = 100,  -- safety weight in move utility (already high)
  W_PROGRESS  = 1.5,
  W_TERRAIN   = 6,
  W_SUPPORT   = 6,    -- + per friendly adjacent (formation)
  W_LINE      = 8,    -- + per enemy we threaten from the tile (line control)
  W_RINGCOVER = 12,   -- + if we newly cover a leader ring square
  EPS         = 0.25, -- tiny tolerance for “ties”
}

local function ai_unitsOf(owner)
    local out = {}
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local u = STATE.board[rr][cc]
            if u and not u.isLeader and u.owner == owner then
                out[#out+1] = {c=cc,r=rr,cell=u}
            end
        end
    end
    return out
end

local function ai_allEnemySpots(owner)
    local pts = {}
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local u = STATE.board[rr][cc]
            if u and u.owner ~= owner then
                pts[#pts+1] = {c=cc,r=rr,cell=u}
            end
        end
    end
    return pts
end

-- Count how many enemy units can hit each tile (not just boolean threat)
local function ai_buildThreatCount(vsOwner)
    local T = {}
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local e = STATE.board[rr][cc]
            if e and not e.isLeader and e.owner ~= vsOwner then
                local atk = cardGameFortune.legalAttacksFrom(cc,rr)
                if atk then
                    for r2,row in pairs(atk) do
                        T[r2] = T[r2] or {}
                        for c2,_ in pairs(row) do
                            T[r2][c2] = (T[r2][c2] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    return T
end

-- If unit at (c,r) moved away, would any enemy gain LOS to our leader?
local function ai_isPinnedBlockingLeader(u, c, r)
    local s=STATE; if not (s and s.leaderPos and s.leaderPos[u.owner]) then return false end
    local lp = s.leaderPos[u.owner]
    local foe = (u.owner==1) and 2 or 1

    -- only matters if the piece currently lies on a straight path between some enemy and our leader
    for er=0,s.rows-1 do
        for ec=0,s.cols-1 do
            local e = s.board[er] and s.board[er][ec]
            if e and e.owner==foe and not e.isLeader then
                -- does e have straight LOS to (lp.c,lp.r) *with* us removed?
                local def = cardGameFortune.db[e.cardId]
                local atktype = (def and def.atktype) or "normal"
                if atktype ~= "normal" then
                    -- only ranged lines matter
                    if (ec==lp.c or er==lp.r) then
                        -- walk line; treat (c,r) as empty when checking
                        local dc = (lp.c==ec) and 0 or ((lp.c>ec) and 1 or -1)
                        local dr = (lp.r==er) and 0 or ((lp.r>er) and 1 or -1)
                        local x,y = ec+dc, er+dr
                        local blocked=false
                        while x~=lp.c or y~=lp.r do
                            local occ = s.board[y][x]
                            if occ and not (x==c and y==r) then blocked=true; break end
                            x,y = x+dc, y+dr
                        end
                        if not blocked then
                            return true  -- moving would open a shot to our leader
                        end
                    end
                end
            end
        end
    end
    return false
end

-- How much damage could u deal from (c,r) next turn, assuming this posture?
local function ai_potentialDamageNext(c, r, u, asDefense)
    local s=STATE; if not s or not u then return 0 end
    if asDefense then return 0 end  -- staying DEF rarely attacks next turn (keep simple)

    local defU = cardGameFortune.db[u.cardId]
    local atktype = (defU and (defU.atktype or "normal")) or "normal"
    local best = 0
    for tr=0,s.rows-1 do
        for tc=0,s.cols-1 do
            local e = s.board[tr] and s.board[tr][tc]
            if e and e.owner ~= u.owner and not e.isLeader then
                if cardGameFortune.ai_unitCanHitTile(u, c, r, tc, tr) then
                    local melee = (atktype=="normal")
                    local atkC, atkR = melee and tc or c, melee and tr or r
                    local aATK = select(1, cardGameFortune.getEffectiveStats(defU, atkC, atkR))
                    local defE = cardGameFortune.db[e.cardId]
                    local eATK, eDEF = cardGameFortune.getEffectiveStats(defE, tc, tr)
                    local rhs = (e.pos=="attack") and eATK or eDEF
                    best = math.max(best, math.max(0, aATK - rhs))
                end
            end
        end
    end
    return best
end


-- helper: count empty adjacent tiles (for better summon geometry)
local function countEmptyAdj(c,r)
    local s = STATE; local n = 0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local cc, rr = c+dc, r+dr
            if cc>=0 and rr>=0 and cc<s.cols and rr<s.rows and (not s.board[rr][cc]) then
                n = n + 1
            end
        end
    end end
    return n
end

-- ── Wall / board-shaping constants
local WALL = {
  DEF_MIN        = 7,     -- consider units with DEF ≥ this “tanky”
  ATK_MAX        = 7,     -- …and with modest ATK (avoid over-committing attackers)
  LINE_BONUS     = 10,    -- + per adjacent friendly wall segment
  RING_BONUS     = 18,    -- + if guarding own leader ring
  CHOKE_BONUS    = 14,    -- + if tile is a choke
  FILL_GAP_BONUS = 22,    -- + if this tile plugs a gap near leader
  KEEP_WALL_PEN  = 35,    -- − if moving this unit opens a shot to leader
}

local function ai_isWallUnit(u)
  if not u or u.isLeader then return false end
  local def = cardGameFortune.db[u.cardId]; if not def then return false end
  return (def.def or 0) >= WALL.DEF_MIN and (def.atk or 0) <= WALL.ATK_MAX
end

local function ai_adjWallCount(c,r, owner)
  local s=STATE; local n=0
  for dr=-1,1 do for dc=-1,1 do
    if not (dr==0 and dc==0) then
      local x,y = c+dc, r+dr
      if x>=0 and y>=0 and x<s.cols and y<s.rows then
        local v = s.board[y][x]
        if v and v.owner==owner and ai_isWallUnit(v) then n=n+1 end
      end
    end
  end end
  return n
end

local function ai_countSafeMovesFor(owner, cap)
    local s=STATE; cap = cap or 12
    local cnt = 0
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u=s.board[r] and s.board[r][c]
            if u and u.owner==owner and not u.isLeader then
                local legal = cardGameFortune.legalMovesFrom(c,r)
                if legal then
                    for rr,row in pairs(legal) do
                        for cc,_ in pairs(row) do
                            local d = cardGameFortune.ai_expectedDamageAt(cc, rr, u, false)
                            local here = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")
                            if d + 0.01 <= here then
                                cnt = cnt + 1
                                if cnt>=cap then return cnt end
                            end
                        end
                    end
                end
            end
        end
    end
    return cnt
end

local function ai_centerControl(owner)
    local s=STATE; local score=0
    local c1 = math.floor(s.cols/3); local c2 = s.cols - 1 - c1
    local r1 = math.floor(s.rows/3); local r2 = s.rows - 1 - r1
    for r=r1,r2 do
        for c=c1,c2 do
            local u=s.board[r] and s.board[r][c]
            if u and u.owner==owner then
                local d = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")
                if d==0 then score = score + 1 end -- safe central occupancy
            end
        end
    end
    return score
end

local function ai_ringGuardCount(owner)
    local s=STATE; local lp=s.leaderPos and s.leaderPos[owner]; if not lp then return 0 end
    local n=0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local x,y=lp.c+dc, lp.r+dr
            local u=s.board[y] and s.board[y][x]
            if u and u.owner==owner and not u.isLeader then n=n+1 end
        end
    end end
    return n
end

local function ai_openingSpear(owner)
    local s=STATE; local lp=s.leaderPos and s.leaderPos[owner]; if not lp then return end
    if ai_ringGuardCount(owner) < 2 then return end
    local hand=s.hands and s.hands[owner] or {}
    -- try to place a ranged piece one row behind ring, aimed center
    for i=1,#hand do
        local cid = hand[i]; local def=cardGameFortune.db[cid]
        if def and def.atktype and def.atktype~="normal" then
            for _,offset in ipairs{{0,-2},{1,-2},{-1,-2},{0,-3}} do
                local cc,rr = lp.c+offset[1], lp.r+offset[2]
                if inBounds(cc,rr) and (not s.board[rr][cc]) and cardGameFortune.canSummonAt(owner, cc, rr, cid) then
                    local pos = "attack"
                    cardGameFortune.playFromHand(owner, i, cc, rr, pos)
                    return
                end
            end
        end
    end
end


-- crude choke detector: tile has ≤2 exits that aren’t offboard/occupied
local function ai_isChokeTile(c,r)
  local s=STATE; local exits=0
  for _,d in ipairs{{1,0},{-1,0},{0,1},{0,-1}} do
    local x,y=c+d[1], r+d[2]
    if x>=0 and y>=0 and x<s.cols and y<s.rows and (not s.board[y][x]) then exits=exits+1 end
  end
  return exits<=2
end

-- would moving (c,r) leave a clear straight line from some enemy ranged to our leader?
local function ai_wallGapIfMoved(u, c, r)
  local s=STATE; if not (s and s.leaderPos and s.leaderPos[u.owner]) then return false end
  local lp = s.leaderPos[u.owner]
  local foe = (u.owner==1) and 2 or 1
  for er=0,s.rows-1 do
    for ec=0,s.cols-1 do
      local e = s.board[er] and s.board[er][ec]
      if e and e.owner==foe and not e.isLeader then
        local def = cardGameFortune.db[e.cardId]
        if def and def.atktype and def.atktype~="normal" then
          if (ec==lp.c or er==lp.r) then
            local dc = (lp.c==ec) and 0 or ((lp.c>ec) and 1 or -1)
            local dr = (lp.r==er) and 0 or ((lp.r>er) and 1 or -1)
            local x,y = ec+dc, er+dr
            local blocked=false
            while x~=lp.c or y~=lp.r do
              local occ = s.board[y][x]
              if occ and not (x==c and y==r) then blocked=true; break end -- treat (c,r) as empty
              x,y = x+dc, y+dr
            end
            if not blocked then return true end
          end
        end
      end
    end
  end
  return false
end

-- does (c,r) sit on an empty square between an enemy ranged unit and our leader?
local function ai_plugsLeaderGap(c,r, owner)
  local s=STATE; if not s or not (s.leaderPos and s.leaderPos[owner]) then return false end
  local lp = s.leaderPos[owner]
  local foe = (owner==1) and 2 or 1
  for er=0,s.rows-1 do
    for ec=0,s.cols-1 do
      local e = s.board[er] and s.board[er][ec]
      if e and e.owner==foe and not e.isLeader then
        local def = cardGameFortune.db[e.cardId]
        if def and def.atktype and def.atktype~="normal" then
          if (ec==lp.c or er==lp.r) then
            -- check the line and see if (c,r) is one of the empty blockers
            local dc = (lp.c==ec) and 0 or ((lp.c>ec) and 1 or -1)
            local dr = (lp.r==er) and 0 or ((lp.r>er) and 1 or -1)
            local x,y = ec+dc, er+dr
            while x~=lp.c or y~=lp.r do
              if x==c and y==r and (not s.board[y][x]) then return true end
              x,y = x+dc, y+dr
            end
          end
        end
      end
    end
  end
  return false
end


-- Module-level LOS threat test (melee adjacent, ranged/volley straight LOS)
function cardGameFortune.ai_unitCanHitTile(e, ec, er, c, r)
    if not e or e.isLeader then return false end
    if ec==nil or er==nil or c==nil or r==nil then return false end
    local def = cardGameFortune.db[e.cardId]
    local atktype = (def and def.atktype) or "normal"

    if atktype == "normal" then
        -- melee: 8-way adjacency
        return math.max(math.abs(ec - c), math.abs(er - r)) == 1
    else
        -- ranged/volley: straight LOS, blocked by first piece
        if ec ~= c and er ~= r then return false end
        local dc = (c == ec) and 0 or ((c > ec) and 1 or -1)
        local dr = (r == er) and 0 or ((r > er) and 1 or -1)
        local x, y = ec + dc, er + dr
        while x ~= c or y ~= r do
            if STATE.board[y][x] then return false end
            x, y = x + dc, y + dr
        end
        return true
    end
end

-- best destination for the leader this turn (or nil to stay)
local function ai_bestLeaderMove(owner)
    local s = STATE; if not (s and s.leaderPos and s.leaderPos[owner]) then return nil end
    local lp = s.leaderPos[owner]; local c0, r0 = lp.c, lp.r
    local L = s.board[r0] and s.board[r0][c0]; if not (L and L.isLeader and not L.hasMoved) then return nil end

    local legal = cardGameFortune.legalLeaderMovesFrom(c0, r0); if not legal then return nil end

    -- NEW: build multi-threat counts (how many enemies can hit a tile)
    local threats = ai_buildThreatCount(owner)

    local danger_here = cardGameFortune.ai_expectedDamageAt(c0, r0, L, true)
    local empty_here  = countEmptyAdj(c0, r0)

    local foe = (owner==1) and 2 or 1
    local foeLP = s.leaderPos and s.leaderPos[foe]

    local best, bestScore, bestKey = nil, -1e9, nil
    for rr, row in pairs(legal) do
        for cc,_ in pairs(row) do
            -- hard filter: avoid tiles attacked by 2+ enemies
            local multi = (threats[rr] and threats[rr][cc]) or 0
            if multi < 2 then
                local danger = cardGameFortune.ai_expectedDamageAt(cc, rr, L, true)

                -- never pick a strictly worse tile than staying
                if danger <= danger_here then
                    local score = 0

                    -- strongly prefer safer tiles
                    score = score + (danger_here - danger) * 50

                    -- prefer tiles with more empty adjacents (easier guarding/summoning)
                    score = score + (countEmptyAdj(cc, rr) - empty_here) * 8

                    -- mild bias to increase distance from enemy leader
                    if foeLP then
                        local dNow = math.abs(c0-foeLP.c) + math.abs(r0-foeLP.r)
                        local dNew = math.abs(cc-foeLP.c) + math.abs(rr-foeLP.r)
                        score = score + (dNew - dNow) * 2
                    end

                    -- NEW: penalize even single extra attackers a bit (multi-threath intensity)
                    score = score - multi * 40

                    -- deterministic tiebreaker without bit-shifts
                    local key = rr * s.cols + cc
                    if (score > bestScore) or (score==bestScore and (not bestKey or key < bestKey)) then
                        best, bestScore, bestKey = {c=cc, r=rr}, score, key
                    end
                end
            end
        end
    end
    return best
end

-- Score a preview for owner (higher = better)
local function ai_scorePreview(prev, owner)
    local s = 0
    if prev.mode == "vsLEADER" then
        local dmg = (prev.leaderDamage and prev.leaderDamage.amount) or 0
        local who = (prev.leaderDamage and prev.leaderDamage.player)
        if who == owner then s = s - 100*dmg else s = s + 100*dmg end
        s = s + 800                      -- big bias to hit leader at all
        return s
    end

    -- vs unit
    if prev.destroyDefender then s = s + 160 end
    if prev.destroyAttacker then s = s - 120 end
    if prev.leaderDamage then
        local amt, who = prev.leaderDamage.amount, prev.leaderDamage.player
        if who == owner then s = s - 100*amt else s = s + 100*amt end
    end
    s = s + (prev.diff or 0) * 2         -- prefer bigger margin
    return s
end

local function ai_isBad(prev, owner)
    if prev.mode == "vsLEADER" then
        return (prev.leaderDamage and prev.leaderDamage.player == owner)
    end
    local selfLD = (prev.leaderDamage and prev.leaderDamage.player == owner)
    local noPayoff = (not prev.destroyDefender) and (not prev.leaderDamage or prev.leaderDamage.player == owner)
    return selfLD or (prev.destroyAttacker and noPayoff)
end

local function ai_isEarlyGame()
    local s=STATE
    local t = (s.turn or s.turnNo or s.fullturns or 0)
    return t <= 4
end


local function ai_findUnitCell(u)
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            if STATE.board[rr][cc] == u then return cc, rr end
        end
    end
    return nil
end


local function ai_bestAttackFor(c,r, owner)
    local legal = cardGameFortune.legalAttacksFrom(c,r)
    if not legal then return nil end
    local best = nil
    for rr,row in pairs(legal) do
        for cc,_ in pairs(row) do
            local ok, prev = cardGameFortune.previewCombat(c,r,cc,rr)
            if ok and prev and (not ai_isBad(prev, owner)) then
                local score = ai_scorePreview(prev, owner)
                if (not best) or score > best.score then
                    best = {c=cc,r=rr, score=score}
                end
            end
        end
    end
    return best
end

local function ai_enemyLeaderPos(owner)
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local u = STATE.board[rr][cc]
            if u and u.isLeader and u.owner ~= owner then return {c=cc,r=rr} end
        end
    end
    return nil
end

local function ai_buildThreatMap(vsOwner) -- squares enemy can attack
    local T = {}
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local u = STATE.board[rr][cc]
            if u and (not u.isLeader) and u.owner ~= vsOwner then
                local atk = cardGameFortune.legalAttacksFrom(cc,rr)
                if atk then
                    for r2,row in pairs(atk) do
                        T[r2] = T[r2] or {}
                        for c2,_ in pairs(row) do T[r2][c2] = true end
                    end
                end
            end
        end
    end
    return T
end

local function ai_adjFriendlyCount(c,r, owner)
    local s=STATE; local n=0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local x,y=c+dc,r+dr
            if x>=0 and y>=0 and x<s.cols and y<s.rows then
                local u=s.board[y][x]
                if u and u.owner==owner and not u.isLeader then n=n+1 end
            end
        end
    end end
    return n
end

local function ai_threatenedEnemiesFrom(c,r, u)
    local s=STATE; local n=0
    for er=0,s.rows-1 do
        for ec=0,s.cols-1 do
            local e=s.board[er] and s.board[er][ec]
            if e and e.owner~=u.owner and not e.isLeader then
                if cardGameFortune.ai_unitCanHitTile(u, c, r, ec, er) then
                    n = n + 1
                end
            end
        end
    end
    return n
end


-- Find a reachable tile this turn from which we can attack something good next turn,
local function ai_bestFlankMove(c,r, owner)
    local s=STATE; local u=s.board[r] and s.board[r][c]
    if not u or u.isLeader or u.owner~=owner or u.hasMoved or u.summoningSickness then return nil end
    local legal = cardGameFortune.legalMovesFrom(c,r); if not legal then return nil end
    local hereDanger = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")

    local best, bestScore = nil, -1e9
    for rr,row in pairs(legal) do
        for cc,_ in pairs(row) do
            local thereDanger = cardGameFortune.ai_expectedDamageAt(cc, rr, u, false)  -- after move: ATK
            -- Skip flanks that are strictly more dangerous than staying
            if thereDanger <= hereDanger then
                -- From (cc,rr), what can we hit next turn?
                local value = 0
                for tr=0,s.rows-1 do
                    for tc=0,s.cols-1 do
                        local e = s.board[tr] and s.board[tr][tc]
                        if e and e.owner ~= owner and not e.isLeader then
                            -- Could we attack e from (cc,rr) next turn?
                            local canHit = cardGameFortune.ai_unitCanHitTile(u, cc, rr, tc, tr)
                            if canHit then
                                local uDef = cardGameFortune.db[u.cardId]
                                local melee = ((uDef and (uDef.atktype or "normal"))=="normal")
                                local atkC, atkR = melee and tc or cc, melee and tr or rr
                                local aATK = select(1, cardGameFortune.getEffectiveStats(uDef, atkC, atkR))

                                local eDef = cardGameFortune.db[e.cardId]
                                local eATK, eDEF = cardGameFortune.getEffectiveStats(eDef, tc, tr)
                                local rhs = (e.pos=="attack") and eATK or eDEF
                                local dmg = math.max(0, aATK - rhs)

                                -- kill is great, any damage is ok, leaders are highest value
                                value = math.max(value, (dmg>0) and ( (dmg>=rhs) and 200 or (dmg*15) ) or 0)
                            end
                        end
                    end
                end
                -- favor safer tiles; mild progress to enemy leader
                local goal = s.leaderPos and s.leaderPos[(owner==1) and 2 or 1]
                local progress = goal and (20 - (math.abs(cc-goal.c)+math.abs(rr-goal.r))) or 0
                local score = value*1.0 - thereDanger*4 + progress*0.5

                if score > bestScore then best, bestScore = {c=cc,r=rr}, score end
            end
        end
    end
    return best
end


local function ai_bestMoveToward(c,r, owner)
    local s=STATE; local u=s.board[r] and s.board[r][c]
    if not u or u.isLeader or u.owner~=owner or u.hasMoved or u.summoningSickness then return nil end

    local legal = cardGameFortune.legalMovesFrom(c,r); if not legal then return nil end
    local hereDanger = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")
    local wallBreakPenalty = 0
        if ai_isWallUnit(u) and ai_wallGapIfMoved(u, c, r) then
        wallBreakPenalty = WALL.KEEP_WALL_PEN
        end
    local threats = ai_buildThreatCount(owner)
    local goal = s.leaderPos and s.leaderPos[(owner==1) and 2 or 1]

    local best, bestScore, bestKey = nil, -1e9, nil
    for rr,row in pairs(legal) do
        for cc,_ in pairs(row) do
            local thereDanger = cardGameFortune.ai_expectedDamageAt(cc, rr, u, false) -- after move: ATK
            local _,_,_,delta = cardGameFortune.getEffectiveStats(cardGameFortune.db[u.cardId], cc, rr)

            local multi   = (threats[rr] and threats[rr][cc]) or 0
            local support = ai_adjFriendlyCount(cc,rr, owner)

            -- hard rule: don't step onto 2+ threat squares unless we have at least equal cover
            local blocked = (multi >= 2 and support < multi)
            if not blocked then
                local score = 0
                -- 1) Safety first
                score = score - thereDanger * AI.W_SAFETY
                if thereDanger >= hereDanger - AI.EPS then score = score - 50 end

                -- 2) Formation
                score = score + support * AI.W_SUPPORT
                score = score + ai_threatenedEnemiesFrom(cc,rr, u) * AI.W_LINE

                -- 3) Extra penalty for multi-threat exposure; mild bonus if covered
                if multi >= 2 then score = score - (multi-1)*25 end
                score = score + math.min(support, multi) * 6

                -- 4) Leader ring cover + terrain + progress
                if s.leaderPos and s.leaderPos[owner] then
                    local lp = s.leaderPos[owner]
                    if math.max(math.abs(cc-lp.c), math.abs(rr-lp.r)) == 1 then
                        score = score + AI.W_RINGCOVER
                    end
                end
                score = score + (delta or 0) * AI.W_TERRAIN
                if goal then
                    local d = math.abs(cc-goal.c)+math.abs(rr-goal.r)
                    score = score + (20 - d) * AI.W_PROGRESS
                end
                -- WALL shaping
                score = score + ai_adjWallCount(cc,rr, owner) * WALL.LINE_BONUS
                if ai_isChokeTile(cc,rr) then score = score + WALL.CHOKE_BONUS end
                if STATE.leaderPos and STATE.leaderPos[owner] and ai_isWallUnit(u) then
                        local lp = STATE.leaderPos[owner]
                    if math.max(math.abs(cc-lp.c), math.abs(rr-lp.r)) == 1 then
                        score = score + WALL.RING_BONUS
                    end
                end
                score = score - wallBreakPenalty


                local key = rr * s.cols + cc
                if (score > bestScore) or (score==bestScore and (not bestKey or key < bestKey)) then
                    best, bestScore, bestKey = {c=cc,r=rr, danger=thereDanger}, score, key
                end
            end
        end
    end

    -- Only move if it’s strictly safer than staying OR formation gain is significant
    if best and (best.danger + AI.EPS < hereDanger or bestScore > 0) then
        return best
    end
    return nil
end

-- bounds
local function inBounds(c,r) return c>=0 and r>=0 and c<STATE.cols and r<STATE.rows end

-- enemy leader position
local function ai_enemyLeaderPos(owner)
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local u = STATE.board[rr][cc]
            if u and u.isLeader and u.owner ~= owner then return {c=cc,r=rr} end
        end
    end
    return nil
end

-- tiles strictly between (c1,r1) and (c2,r2) on a straight line (no diagonals)
local function ai_lineBetween(c1,r1, c2,r2)
    local out = {}
    if c1 ~= c2 and r1 ~= r2 then return out end
    local dc = (c2==c1) and 0 or ((c2>c1) and 1 or -1)
    local dr = (r2==r1) and 0 or ((r2>r1) and 1 or -1)
    local c, r = c1 + dc, r1 + dr
    while c ~= c2 or r ~= r2 do
        out[#out+1] = {c=c, r=r}
        c, r = c + dc, r + dr
    end
    return out
end

-- Try to move ANY unit onto a lane tile that currently gives a ranged enemy LOS to our leader.
-- Chooses the reachable lane tile with the lowest expected danger.
local function ai_tryInterpose(owner)
    local s=STATE; if not (s and s.leaderPos and s.leaderPos[owner]) then return false end
    local lp = s.leaderPos[owner]               -- our leader
    local foe = (owner==1) and 2 or 1
    local best = nil

    -- 1) collect empty "lane tiles" that, if occupied, would break LOS
    local targets = {}
    for er=0,s.rows-1 do
        for ec=0,s.cols-1 do
            local e = s.board[er] and s.board[er][ec]
            if e and e.owner==foe and not e.isLeader then
                -- use your LOS test so empty lanes count
                if cardGameFortune.ai_unitCanHitTile(e, ec, er, lp.c, lp.r) then
                    -- any empty square on the line would stop the shot
                    for _,t in ipairs(ai_lineBetween(ec,er, lp.c,lp.r)) do
                        if not s.board[t.r][t.c] then
                            targets[#targets+1] = {c=t.c, r=t.r}
                        end
                    end
                end
            end
        end
    end
    if #targets==0 then return false end

    -- 2) find a friendly unit that can reach one of those tiles safely this turn
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u = s.board[r] and s.board[r][c]
            if u and u.owner==owner and not u.isLeader and not u.hasMoved and not u.summoningSickness then
                local legal = cardGameFortune.legalMovesFrom(c,r)
                if legal then
                    local hereDanger = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")
                    for _,t in ipairs(targets) do
                        if legal[t.r] and legal[t.r][t.c] then
                            local thereDanger = cardGameFortune.ai_expectedDamageAt(t.c, t.r, u, false) -- after move: ATK
                            -- prefer moves that reduce danger or at least don't make it worse
                            if thereDanger <= hereDanger then
                                local keyScore = -thereDanger*100 - (math.abs(t.c-lp.c)+math.abs(t.r-lp.r))
                                if (not best) or keyScore > best.keyScore then
                                    best = {fromC=c,fromR=r, toC=t.c,toR=t.r, keyScore=keyScore}
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if best then
        return cardGameFortune.moveUnit(best.fromC,best.fromR, best.toC,best.toR)
    end
    return false
end


-- tiles the enemy can hit next (simple threat map)
local function ai_buildThreatMap(vsOwner)
    local T = {}
    for rr=0,STATE.rows-1 do
        for cc=0,STATE.cols-1 do
            local e = STATE.board[rr][cc]
            if e and (not e.isLeader) and e.owner ~= vsOwner then
                -- mark all tiles this enemy could hit next (even if empty now)
                for r2=0,STATE.rows-1 do
                    for c2=0,STATE.cols-1 do
                        if cardGameFortune.ai_unitCanHitTile(e, cc, rr, c2, r2) then
                            T[r2] = T[r2] or {}
                            T[r2][c2] = true
                        end
                    end
                end
            end
        end
    end
    return T
end


-- local adjacency check (8-way)
local function hasAdjacentEnemy(c,r, owner)
    for _,d in ipairs{{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}} do
        local nc, nr = c+d[1], r+d[2]
        if inBounds(nc,nr) then
            local u = STATE.board[nr][nc]
            if u and u.owner ~= owner then return true end
        end
    end
    return false
end

-- Expected damage helper (define on module)
function cardGameFortune.ai_expectedDamageAt(c, r, u, asDefense)
    local s = STATE; if not (s and u) then return 0 end
    local myDef = cardGameFortune.db[u.cardId]

    local function myStatAt(cc,rr)
        local aATK, aDEF = cardGameFortune.getEffectiveStats(myDef, cc, rr)
        if u.isLeader then return aDEF end         -- leaders defend
        if asDefense then return aDEF end
        local pos = u.pos or "attack"
        return (pos == "defense") and aDEF or aATK
    end

    local dmg = 0
    for er=0,s.rows-1 do
        for ec=0,s.cols-1 do
            local e = s.board[er] and s.board[er][ec]
            if e and e.owner ~= u.owner and not e.isLeader then
                if cardGameFortune.ai_unitCanHitTile(e, ec, er, c, r) then
                    local eDef  = cardGameFortune.db[e.cardId]
                    local atktype = (eDef and eDef.atktype) or "normal"
                    local melee = (atktype == "normal")
                    -- attacker’s terrain tile for stats:
                    local atkC, atkR = melee and c or ec, melee and r or er
                    local eATK = select(1, cardGameFortune.getEffectiveStats(eDef, atkC, atkR))
                    local margin = eATK - myStatAt(c, r)
                    if margin > 0 then dmg = dmg + margin end
                end
            end
        end
    end
    return dmg
end


-- choose stance by comparing expected damage on this exact tile
local function ai_chooseSummonPos(owner, cid, c, r, threats)
    local dummyAtk = { owner=owner, cardId=cid, pos="attack",  isLeader=false }
    local dummyDef = { owner=owner, cardId=cid, pos="defense", isLeader=false }

    local dmgATK = cardGameFortune.ai_expectedDamageAt(c, r, dummyAtk, false)
    local dmgDEF = cardGameFortune.ai_expectedDamageAt(c, r, dummyDef, true)
    local threatened = threats[r] and threats[r][c]

    if threatened or (dmgDEF + 0.01 < dmgATK) then
        return "defense"
    end
    return "attack"
end




-- Decide: fortify here vs move to safer tile vs stay.
local function ai_decideDefenseOrMove(c, r, owner)
    local s=STATE; local u=s.board[r] and s.board[r][c]
    if not u or u.owner~=owner or u.isLeader then return end
    if u.summoningSickness or u.hasMoved then return end

    local danger_stay = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")

    local canFortify = (u.pos ~= "defense") and (not u.hasAttacked)
    local danger_fort = canFortify and cardGameFortune.ai_expectedDamageAt(c, r, u, true) or math.huge

    -- If in ATK and we have a good/safe attack now, take it immediately
    if u.pos=="attack" and (not u.hasAttacked) then
        local tgt = ai_bestAttackFor(c,r, owner)
        if tgt then
            -- quick sanity: don't attack if post-battle square becomes a death trap
            -- (use current tile danger as proxy; battles happen in-place in your rules)
            local hereD = cardGameFortune.ai_expectedDamageAt(c, r, u, false)
            if hereD < 9999 then
                cardGameFortune.resolveBattle(c,r, tgt.c,tgt.r)
                return
            end
        end
    end


    local mv = ai_bestMoveToward(c,r, owner)
    local danger_move = mv and cardGameFortune.ai_expectedDamageAt(mv.c, mv.r, u, false) or math.huge

    -- Small nudge: if this is a wall-capable unit on the ring or a choke, prefer fortify in near-ties
    local fortNudge = 0
    if ai_isWallUnit(u) then
        if STATE.leaderPos and STATE.leaderPos[owner] then
            local lp = STATE.leaderPos[owner]
            if math.max(math.abs(c - lp.c), math.abs(r - lp.r)) == 1 then
                fortNudge = fortNudge + 0.5
            end
        end
        if ai_isChokeTile(c, r) then
            fortNudge = fortNudge + 0.5
        end
    end

    -- choose the lowest danger; nudge makes DEF win close calls on key tiles
    local BEST = math.min(danger_stay, danger_fort, danger_move)

    if mv and danger_move <= BEST then
        cardGameFortune.moveUnit(c, r, mv.c, mv.r)
        return
    end

    if canFortify
    and (danger_fort + 0.01 < danger_stay + fortNudge)
    and (danger_fort <= BEST) then
        cardGameFortune.fortifyToDefense(c, r)  -- consumes move
        return
    end

    -- otherwise, staying is fine this turn
end



local function ai_trySummon()
    local s = STATE
    local hand = s.hands[2] or {}

    -- find P2 leader
    local Lc,Lr
    for rr=0,s.rows-1 do
        for cc=0,s.cols-1 do
            local u = s.board[rr][cc]
            if u and u.isLeader and u.owner==2 then Lc,Lr=cc,rr; break end
        end
        if Lc then break end
    end
    if not Lc then return false end

    local goal    = ai_enemyLeaderPos(2)
    local threats = ai_buildThreatMap(2)
    local best    = nil

    for i=1,#hand do
        local cid = hand[i]
        if cid then
            for dr=-1,1 do
                for dc=-1,1 do
                    if not (dc==0 and dr==0) then
                        local c = Lc+dc; local r = Lr+dr
                        if inBounds(c,r) then
                            local ok = cardGameFortune.canSummonAt(2,c,r,cid)
                            if ok then
                                -- pick stance for THIS tile
                                local pos = ai_chooseSummonPos(2, cid, c, r, threats)

                                -- score: prefer safer tiles first, then distance/terrain
                                local def = cardGameFortune.db[cid]
                                local _,_,_,delta = cardGameFortune.getEffectiveStats(def, c, r)
                                local dist = (goal and (math.abs(c-goal.c) + math.abs(r-goal.r))) or 999

                                -- compute expected damage for the chosen posture on this tile
                                local dmg = (pos == "defense")
                                            and cardGameFortune.ai_expectedDamageAt(c, r, {owner=2, cardId=cid, pos="defense", isLeader=false}, true)
                                            or  cardGameFortune.ai_expectedDamageAt(c, r, {owner=2, cardId=cid, pos="attack",  isLeader=false}, false)

                                -- strong safety weighting so we don't spawn into magikoopa crossfire
                                local W_SAFETY   = 18.0     -- increase if you still see risky spawns
                                local W_DISTANCE = 1.0
                                local W_TERRAIN  = 0.6
                                local threatened = threats[r] and threats[r][c] or false

                                local score = -(dmg * W_SAFETY)                         -- biggest influence
                                            +  (delta or 0) * W_TERRAIN
                                            -  dist * W_DISTANCE
                                            +  ((pos=="defense" and threatened) and 1.5 or 0)
                                -- --- WALL HEURISTICS: encourage board shaping ---
                                local wallScore = 0
                                local def = cardGameFortune.db[cid]
                                local tanky = def and ((def.def or 0) >= WALL.DEF_MIN) and ((def.atk or 0) <= WALL.ATK_MAX)
                                if tanky then
                                if ai_plugsLeaderGap(c, r, 2) then wallScore = wallScore + WALL.FILL_GAP_BONUS end

                                if STATE.leaderPos and STATE.leaderPos[2] then
                                    local lp = STATE.leaderPos[2]
                                    if math.max(math.abs(c - lp.c), math.abs(r - lp.r)) == 1 then
                                        wallScore = wallScore + WALL.RING_BONUS
                                    end
                                end

                                wallScore = wallScore + ai_adjWallCount(c, r, 2) * WALL.LINE_BONUS
                                if ai_isChokeTile(c, r) then wallScore = wallScore + WALL.CHOKE_BONUS end
                                end
                                score = score + wallScore

                                -- Aggressive summon bonus: threaten leader / add threats next turn
                                do
                                    local dummy = {owner=2, cardId=cid, pos=pos, isLeader=false}
                                    if ai_potentialLeaderThreatFrom(c, r, dummy) then
                                        score = score + 20   -- leader pressure
                                    end
                                    -- small bonus per enemy we would threaten from that square
                                    local tmp = ai_newThreatsFrom(c, r, dummy)
                                    score = score + tmp * 2
                                end

                                if (not best) or score > best.score then
                                    best = {i=i, c=c, r=r, pos=pos, score=score, danger=dmg}
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if best then
        return cardGameFortune.playFromHand(2, best.i, best.c, best.r, best.pos)
    end
    return false
end

-- ---------- light state snapshot & sandbox ----------
local function ai_cloneUnit(u)
    return {
        owner=u.owner, isLeader=u.isLeader, pos=u.pos, cardId=u.cardId,
        hasMoved=false, hasAttacked=false, summoningSickness=false,
    }
end

local function ai_snapshotState()
    local s = STATE
    local snap = { rows=s.rows, cols=s.cols, energy={s.energy[1], s.energy[2]} }
    snap.board = {}
    for r=0,s.rows-1 do
        snap.board[r] = {}
        for c=0,s.cols-1 do
            local u = s.board[r][c]
            snap.board[r][c] = u and ai_cloneUnit(u) or nil
        end
    end
    snap.leaderPos = { [1]=s.leaderPos and {c=s.leaderPos[1].c, r=s.leaderPos[1].r} or nil,
                       [2]=s.leaderPos and {c=s.leaderPos[2].c, r=s.leaderPos[2].r} or nil }
    snap.whoseTurn = s.whoseTurn
    return snap
end

local function ai_sandbox(fn, snap)
    local real = STATE
    STATE = snap
    local ok, ret = pcall(fn)
    STATE = real
    if not ok then return nil end
    return ret
end

local function ai_countLeaderEscapes(owner)
    local s=STATE; local lp=s.leaderPos and s.leaderPos[owner]; if not lp then return 0 end
    local count = 0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local x,y=lp.c+dc, lp.r+dr
            if x>=0 and y>=0 and x<s.cols and y<s.rows and (not s.board[y][x]) then
                -- treat leader moving there in DEF
                local dummy = {owner=owner,isLeader=true,pos="defense",cardId=s.board[lp.r][lp.c].cardId}
                if cardGameFortune.ai_expectedDamageAt(x,y, dummy, true) <=
                   cardGameFortune.ai_expectedDamageAt(lp.c,lp.r, dummy, true) then
                    count = count + 1
                end
            end
        end
    end end
    return count
end

local function ai_ringCoverCount(owner)
    local s=STATE; local lp=s.leaderPos and s.leaderPos[owner]; if not lp then return 0 end
    local n=0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local x,y=lp.c+dc, lp.r+dr
            local u=s.board[y] and s.board[y][x]
            if u and u.owner==owner and not u.isLeader then n=n+1 end
        end
    end end
    return n
end

local function ai_losBlockerCount(owner)
    local s=STATE; local lp=s.leaderPos and s.leaderPos[owner]; if not lp then return 0 end
    local foe=(owner==1) and 2 or 1
    local n=0
    for er=0,s.rows-1 do for ec=0,s.cols-1 do
        local e=s.board[er] and s.board[er][ec]
        if e and e.owner==foe and not e.isLeader then
            local def=cardGameFortune.db[e.cardId]
            if def and def.atktype and def.atktype~="normal" then
                if ec==lp.c or er==lp.r then
                    local dc=(lp.c==ec) and 0 or ((lp.c>ec) and 1 or -1)
                    local dr=(lp.r==er) and 0 or ((lp.r>er) and 1 or -1)
                    local x,y=ec+dc,er+dr
                    local blocked=false
                    while x~=lp.c or y~=lp.r do
                        local occ=s.board[y][x]
                        if occ then blocked=true; n=n+1; break end
                        x,y=x+dc,y+dr
                    end
                end
            end
        end
    end end
    return n
end


-- ---------- sandboxed “apply” (no animations, just board edits) ----------
local function ai_applyMove(s, c,r, cc,rr)
    local u = s.board[r] and s.board[r][c]; if not u then return false end
    if s.board[rr][cc] then return false end
    s.board[r][c] = nil
    s.board[rr][cc] = u
    if u.isLeader then
        s.leaderPos[u.owner] = {c=cc, r=rr}
        -- leaders keep "defense" posture
    else
        u.pos = "attack" -- after moving, non-leaders are ATK in our ruleset
    end
    return true
end

local function ai_applyFortify(s, c,r)
    local u = s.board[r] and s.board[r][c]; if not u or u.isLeader then return false end
    u.pos = "defense"
    return true
end

-- ---------- fast opponent best-attack estimate on sandbox ----------
local function ai_bestOpponentAttackValue(owner)
    local foe = (owner==1) and 2 or 1
    local best = 0
    for r=0,STATE.rows-1 do
        for c=0,STATE.cols-1 do
            local A = STATE.board[r][c]
            if A and A.owner==foe and not A.isLeader then
                local atkset = cardGameFortune.legalAttacksFrom(c,r)
                for rr,row in pairs(atkset) do
                    for cc,_ in pairs(row) do
                        local D = STATE.board[rr][cc]
                        if D and D.owner==owner then
                            local defA = cardGameFortune.db[A.cardId]
                            local melee = ((defA and (defA.atktype or "normal"))=="normal")
                            local atkC,atkR = melee and cc or c, melee and rr or r
                            local aATK = select(1, cardGameFortune.getEffectiveStats(defA, atkC, atkR))

                            if D.isLeader then
                                -- treat leader damage as high value
                                best = math.max(best, aATK * 15)
                            else
                                local defD = cardGameFortune.db[D.cardId]
                                local dATK, dDEF = cardGameFortune.getEffectiveStats(defD, cc, rr)
                                local rhs = (D.pos=="attack") and dATK or dDEF
                                local dmg = math.max(0, aATK - rhs)
                                -- reward kills heavily
                                local val = (dmg>0) and (dmg*10 + (aATK>rhs and 200 or 0)) or 0
                                if val > best then best = val end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end


local function ai_isForcingAttack(attacker, ac,ar, tc,tr, owner)
    local D = STATE.board[tr] and STATE.board[tr][tc]
    if D and D.owner==owner then return true end -- capture
    local Lp = STATE.leaderPos and STATE.leaderPos[owner]
    return (Lp and tc==Lp.c and tr==Lp.r) or false
end

local function ai_quiescence(owner, maxDepth)
    maxDepth = maxDepth or 1
    local foe = (owner==1) and 2 or 1
    local function q(depth)
        if depth>maxDepth then return 0 end
        local best = 0
        for r=0,STATE.rows-1 do for c=0,STATE.cols-1 do
            local A = STATE.board[r] and STATE.board[r][c]
            if A and A.owner==foe and not A.isLeader then
                local atk = cardGameFortune.legalAttacksFrom(c,r)
                if atk then for rr,row in pairs(atk) do for cc,_ in pairs(row) do
                    if ai_isForcingAttack(A,c,r,cc,rr, owner) then
                        local defA = cardGameFortune.db[A.cardId]
                        local melee = ((defA and (defA.atktype or "normal"))=="normal")
                        local atkC,atkR = melee and cc or c, melee and rr or r
                        local aATK = select(1, cardGameFortune.getEffectiveStats(defA, atkC, atkR))
                        local val = 0
                        local D = STATE.board[rr][cc]
                        if D and D.owner==owner then
                            if D.isLeader then val = aATK * 15
                            else
                                local defD = cardGameFortune.db[D.cardId]
                                local dATK,dDEF = cardGameFortune.getEffectiveStats(defD, cc, rr)
                                local rhs = (D.pos=="attack") and dATK or dDEF
                                local dmg = math.max(0, aATK - rhs)
                                val = (dmg>0) and (dmg*10 + (aATK>rhs and 200 or 0)) or 0
                            end
                        end
                        best = math.max(best, val)
                        if depth<maxDepth then
                            best = math.max(best, val - 0.5*q(depth+1))
                        end
                    end
                end end end
        end end
        return best
    end
    return q(1)
end end

-- ---------- board evaluation after our action + their reply (2-ply) ----------
local AI2 = {
    W_LEADER_SAFETY = 15,  -- larger = more conservative around leader
    W_UNIT_SAFETY   = 9,   -- safety for the acting unit
    W_TERRAIN       = 4,
    W_SUPPORT       = 4,   -- formation
    W_LINE          = 6,   -- threats we create from the square
    W_OPP_REPLY     = 1.0, -- penalty for opponent best reply value
    EPS             = 0.001,
    W_LEADER_ESCAPE  = 3,   -- + per safe escape square
    W_RING_COVER     = 2.5, -- + per friendly on leader ring
    W_LOS_BLOCKERS   = 5,   -- + per blocker on enemy LOS to leader
    W_MOBILITY = 0.6,  -- + per safe move available (capped)
    W_CENTER   = 0.8,  -- + per safe central occupant
    W_THREAT_LEADER = 6.0,  -- + if we threaten your leader next turn
    W_THREAT_PIECE  = 1.5,  -- + per enemy we newly threaten
    W_STAGNATION    = 8.0,  -- - if our move is a no-op shuffle
}

local function ai_adjFriendlyCount(c,r, owner)
    local n=0
    for dr=-1,1 do for dc=-1,1 do
        if not (dr==0 and dc==0) then
            local x,y=c+dc,r+dr
            if x>=0 and y>=0 and x<STATE.cols and y<STATE.rows then
                local u=STATE.board[y][x]
                if u and u.owner==owner and not u.isLeader then n=n+1 end
            end
        end
    end end
    return n
end

local function ai_threatenedEnemiesFrom(c,r, u)
    local n=0
    for er=0,STATE.rows-1 do
        for ec=0,STATE.cols-1 do
            local e=STATE.board[er] and STATE.board[er][ec]
            if e and e.owner~=u.owner and not e.isLeader then
                if cardGameFortune.ai_unitCanHitTile(u, c, r, ec, er) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- Evaluate after applying an action to unit at (c,r):
-- action.kind = "stay" | "fortify" | "move", plus toC,toR for move
local function ai_evalAction2ply(c,r, owner, action)
    local snap = ai_snapshotState()
    return ai_sandbox(function()
        local u = STATE.board[r][c]; if not u then return -1e9 end

        local startDanger = cardGameFortune.ai_expectedDamageAt(c, r, u, u.pos=="defense")

        -- apply our action
        if action.kind=="move" then
            if not ai_applyMove(STATE, c,r, action.toC,action.toR) then return -1e9 end
            c,r = action.toC, action.toR
        elseif action.kind=="fortify" then
            if not ai_applyFortify(STATE, c,r) then return -1e9 end
        elseif action.kind=="stay" then
            -- no change
        end

        local me   = STATE.board[r][c]
        local lp   = STATE.leaderPos and STATE.leaderPos[owner]
        local terr = 0
        if me then
            local defU = cardGameFortune.db[me.cardId]
            local _,_,_,delta = cardGameFortune.getEffectiveStats(defU, c, r)
            terr = delta or 0
        end

        -- our safety after the action
        local meDanger   = me and cardGameFortune.ai_expectedDamageAt(c, r, me, me.pos=="defense") or 0
        local leaderDmg  = 0
        if lp then
            -- approximate next-turn leader risk after our action
            local dummyL = STATE.board[lp.r][lp.c]
            leaderDmg = dummyL and cardGameFortune.ai_expectedDamageAt(lp.c, lp.r, dummyL, true) or 0
        end

        -- formation value from the resulting square
        local support = me and ai_adjFriendlyCount(c,r, owner) or 0
        local lines   = me and ai_threatenedEnemiesFrom(c,r, me) or 0

        -- opponent best single reply
        local oppBest = ai_bestOpponentAttackValue(owner)
        local oppQ    = ai_quiescence(owner, 1)  -- extend noisy lines a bit
        oppBest = math.max(oppBest, oppQ)


        local score = 0
        local escapes = ai_countLeaderEscapes(owner)
        local cover   = ai_ringCoverCount(owner)
        local blockers= ai_losBlockerCount(owner)
        local mob   = ai_countSafeMovesFor(owner, 12)
        local space = ai_centerControl(owner)
        local threatLeader = (me and ai_potentialLeaderThreatFrom(c,r, me)) and 1 or 0
        local newThreats   = me and ai_newThreatsFrom(c,r, me) or 0

        score = score - leaderDmg * AI2.W_LEADER_SAFETY
        score = score + escapes * AI2.W_LEADER_ESCAPE
        score = score + cover   * AI2.W_RING_COVER
        score = score + blockers* AI2.W_LOS_BLOCKERS
        score = score - meDanger   * AI2.W_UNIT_SAFETY
        score = score + terr       * AI2.W_TERRAIN
        score = score + support    * AI2.W_SUPPORT
        score = score + lines      * AI2.W_LINE
        score = score - oppBest    * AI2.W_OPP_REPLY
        score = score + mob   * AI2.W_MOBILITY
        score = score + space * AI2.W_CENTER
        score = score + threatLeader * AI2.W_THREAT_LEADER
        score = score + newThreats   * AI2.W_THREAT_PIECE

        -- Anti-stall: penalize "shuffle" (no displacement)
        if action.kind=="move" and c== (action.fromC or c) and r==(action.fromR or r) then
            score = score - AI2.W_STAGNATION
        end

        -- tiny reward for reducing our own danger vs staying
        score = score + (startDanger - meDanger)

        return score
    end, snap)
end




-- ───────────────────────────────────────────────────────────
-- Build a paced turn for Player 2 (AI)
-- ───────────────────────────────────────────────────────────
function cardGameFortune.aiBeginTurn()
    local s = STATE
    if not s or s.whoseTurn ~= 2 then return end
    local st = cardGameFortune.aiState
    if st.busy then return end

    st.busy, st.steps, st.delay = true, {}, 10   -- small think pause

    aiQueue(function()
        -- Early spear if we already have 2 ring guards
        ai_openingSpear(2)
    end, 0)


    -- Opening "Fortress": plug leader ring with a tank if early or low LP
    aiQueue(function()
        local s=STATE
        local lowLP = (s.leaderHP and s.leaderHP[2] and s.leaderHP[2] <= 28)
        if ai_isEarlyGame() or lowLP then
            local lp = s.leaderPos and s.leaderPos[2]
            local hand = s.hands and s.hands[2] or {}
            if lp and hand then
                for rr=lp.r-1, lp.r+1 do
                    for cc=lp.c-1, lp.c+1 do
                        if inBounds(cc,rr) and (not s.board[rr][cc]) then
                            -- find first tanky card we can afford
                            for i=1,#hand do
                                local cid = hand[i]; local def = cardGameFortune.db[cid]
                                if def and (def.def or 0) >= WALL.DEF_MIN and (def.atk or 0) <= WALL.ATK_MAX then
                                    if cardGameFortune.canSummonAt(2, cc, rr, cid) then
                                        cardGameFortune.playFromHand(2, i, cc, rr, "defense")
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end, 0)


    --Should leader move?
    aiQueue(function()
        local s = STATE
        if not (s and s.whoseTurn==2 and s.leaderPos and s.leaderPos[2]) then return end
        local mv = ai_bestLeaderMove(2)
        if mv then
            local lp = s.leaderPos[2]
            cardGameFortune.moveUnit(lp.c, lp.r, mv.c, mv.r)
        end
    end)

    aiQueue(function()
        -- try to body-block any ranged lane to our leader
        ai_tryInterpose(2)
    end)

    --Sort units for deterministic action
    local units = ai_unitsOf(2)
    table.sort(units, function(a,b)
    return (a.r==b.r) and (a.c<b.c) or (a.r<b.r)
    end)
    for i,u in ipairs(units) do units[i] = u.cell end

    -- A) Everyone: take a good attack if we have one
    for _,u in ipairs(units) do
        aiQueue(function()
            local c,r = ai_findUnitCell(u)
            if not c then return end
            if u.hasAttacked then return end
            local tgt = ai_bestAttackFor(c,r, 2)
            if tgt then cardGameFortune.resolveBattle(c,r, tgt.c,tgt.r) end
        end)
    end

    -- A.5) per-unit: two-ply choose stay vs fortify vs move (safest candidate)
    for _,u in ipairs(units) do
        aiQueue(function()
            local c,r = ai_findUnitCell(u); if not c then return end
            local s=STATE; local me = s.board[r][c]; if not me then return end
            if me.isLeader or me.hasMoved or me.summoningSickness then return end

            -- candidates
            local actions = { {kind="stay"} }

            if me.pos~="defense" and not me.hasAttacked then
                table.insert(actions, {kind="fortify"})
            end

            -- take up to 5 safest moves as candidates
            local legal = cardGameFortune.legalMovesFrom(c,r)
            if legal then
                local hereDanger = cardGameFortune.ai_expectedDamageAt(c, r, me, me.pos=="defense")
                local moves = {}
                for rr,row in pairs(legal) do
                    for cc,_ in pairs(row) do
                        local d = cardGameFortune.ai_expectedDamageAt(cc, rr, me, false)
                        moves[#moves+1] = {c=cc, r=rr, danger=d}
                    end
                end
                table.sort(moves, function(a,b) return a.danger < b.danger end)
                for i=1, math.min(5, #moves) do
                    -- only consider moves that are not strictly worse than staying
                    if moves[i].danger + AI2.EPS <= hereDanger then
                        table.insert(actions, {kind="move", fromC=c, fromR=r, toC=moves[i].c, toR=moves[i].r})
                    end
                end
            end

            -- evaluate each in sandbox (2-ply) and pick the best
            local bestAct, bestScore = nil, -1e9
            for _,act in ipairs(actions) do
                local sc = ai_evalAction2ply(c,r, 2, act) or -1e9
                if sc > bestScore then bestScore, bestAct = sc, act end
            end

            -- execute the chosen real action
            if bestAct then
                if bestAct.kind=="move" then
                    cardGameFortune.moveUnit(c,r, bestAct.toC,bestAct.toR)
                elseif bestAct.kind=="fortify" then
                    cardGameFortune.fortifyToDefense(c,r)
                else
                    -- stay
                end
            end
        end)
    end



    -- B) Everyone: step toward enemy leader (avoid threatened tiles), if can move
    for _,u in ipairs(units) do
        aiQueue(function()
            local c,r = ai_findUnitCell(u)
            if not c then return end
            if u.hasMoved then return end
            local mv = ai_bestMoveToward(c,r, 2)
            if mv then cardGameFortune.moveUnit(c,r, mv.c,mv.r) end
        end)
    end

    -- C) Everyone: after moving, see if we earned a new attack
    for _,u in ipairs(units) do
        aiQueue(function()
            local c,r = ai_findUnitCell(u)
            if not c then return end
            if u.hasAttacked then return end
            local tgt = ai_bestAttackFor(c,r, 2)
            if tgt then cardGameFortune.resolveBattle(c,r, tgt.c,tgt.r) end
        end)
    end

    -- D) Try a couple of summons (tweak count to taste)
    local SUMMON_TRIES = 2
    for i=1,SUMMON_TRIES do
        aiQueue(function() ai_trySummon() end)
    end

    -- E) End turn → hand back to P1
    aiQueue(function()
        cardGameFortune.endTurn()
        cardGameFortune.aiJustEnded = true
    end, 0)
    aiQueue(function() st.busy = false end, 0)
end




return cardGameFortune