
local cardGameFortune = { db = {} }

-- ───────────────────────────────────────────────────────────
-- CARD REGISTRATION (yours, unchanged)
-- ───────────────────────────────────────────────────────────
function cardGameFortune.register(card)
  assert(card.id, "card.id required")
  assert(not cardGameFortune.db[card.id], ("duplicate card id: %s"):format(card.id))
  cardGameFortune.db[card.id] = {
    id          = card.id,
    name        = card.name or "Unnamed Card",
    image       = card.image or "cardgame/goombaicon.png",
    icon        = card.icon or "cardgame/goombaicon.png",
    description = card.description or "No description yet.",
    atk         = card.atk or 0,
    def         = card.def or 0,
    movement    = card.movement or 0,
    movementtype= card.movementtype or "normal",
    atktype     = card.atktype or "melee",
    type        = card.type or "normal",
    subtype1    = card.subtype1 or "normal",
    subtype2    = card.subtype2 or "normal",
    summoncost  = card.summoncost or 0,
    deckcost    = card.deckcost or 0,
  }
end

cardGameFortune.roleBonus = {
  melee     = { grappler = 3, ranged = 1 },
  defensive = { melee = 3, magic = 1 },
  grappler  = { defensive = 3, tower = 1 },
  ranged    = { tower = 3, grappler = 1 },
  magic     = { ranged = 3, melee = 1 },
  tower     = { magic = 3, defensive = 1},
}

cardGameFortune.attackTypeBonus = {
  normal = {},
  ranged = { tower = 3, defensive = 1 },
  pierce = { defensive = 3, tower = 1 },
  volley = { tower = 3, melee = -1 },
}

-- ───────────────────────────────────────────────────────────
-- STATE & RULES (new)
-- ───────────────────────────────────────────────────────────
local STATE = {
  open       = false,         -- overlay visibility
  cols       = 7, rows = 7,   -- board size
  board      = nil,           -- 2D array [r][c] = {cardId, owner, hp, atk, def}
  whoseTurn  = 1,             -- 1 or 2
  phase      = "main",        -- "main" | "combat" | "end"
  hands      = { {}, {} },    -- hands[1], hands[2] = array of cardIds
  deck       = { {}, {} },    -- deck[1], deck[2]
  discard    = { {}, {} },    -- discard piles
  leaderHP   = { 40, 40 },    -- simple win condition for now
  energy     = { 3, 3 },      -- per-turn summon points
  seed       = 0,
}

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

-- +2 terrain bonus if subtype2 equals tile terrain (case-insensitive friendly)
local function terrainBonus(def, terr)
  if not def then return 0 end
  local a = tostring(def.subtype2 or ""):lower()
  local b = tostring(terr or ""):lower()
  return (a == b) and 2 or 0
end

-- BAD matchups (card subtype2 -> tile terrain that gives -2)
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

-- Returns +2 (match), -2 (unfit), or 0 (neutral)
local function terrainDelta(defTerr, tileTerr)
  if not defTerr or defTerr == "" then return 0 end
  if defTerr == tileTerr then return 2 end
  local pen = TERRAIN_PENALTY[defTerr]
  if pen and pen[tileTerr] then return -2 end
  return 0
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
    Overworld=20, Forest=10, Mountain=9, Desert=8, Snow=8,
    Underground=8, Underwater=6, Sky=6, GhostHouse=5, ["Ghost House"]=5, Castle=5, Volcano=5,
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

-- Keep a neutral ring around each leader so you can always act on turn 1
local function T_neutralizeLeaderRings(g, ringTerr, radius)
    ringTerr = ringTerr or "Overworld"
    radius = radius or 1
    if not (STATE and STATE.leaderPos) then return end
    for owner=1,2 do
        local p = STATE.leaderPos[owner]
        if p then
            for dr=-radius,radius do
                for dc=-radius,radius do
                    local c, r = p.c + dc, p.r + dr
                    if T_in(STATE, c, r) then
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


-- Public API
function cardGameFortune.regenTerrain(opts)
    local s = STATE; if not s then return end
    s.terrainSeed = s.terrainSeed or nowMs()
    s.terrain = T_generate(s.terrainSeed, s.rows, s.cols, opts or {mirror="vertical"})
    -- make sure leaders exist before neutralizing rings
    T_neutralizeLeaderRings(s.terrain, "Overworld", 1)
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

-- entry rules are soft for now; expand later
local function canEnterTile(def, c, r)
    -- Everyone can enter every tile for now (we’ll tighten when terrain rules harden)
    -- You already have subtype1 = normal|flying|ghost|lava if you want to branch.
    return inBounds(c,r) and (not STATE.board[r][c])
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



-- Return a set { [r]={[c]=true,...}, ... } of reachable tiles for this unit
function cardGameFortune.legalMovesFrom(c,r)
  local cell = STATE.board[r][c]
  if (not cell) or cell.isLeader or cell.summoningSickness or cell.hasMoved or cell.hasAttacked then
    return {}
  end
  local def = cardGameFortune.db[cell.cardId]
  local startTerr = terrainAt(c,r)
  local bonus = (terrainDelta(def and def.subtype2, startTerr) > 0) and 1 or 0
  local maxSteps = math.max(0, (def and def.movement or 0) + bonus)

  local passThroughUnits = (def and def.subtype1 == "ghost")
  local dist, q = {}, {{c=c,r=r}} ; dist[r] = {[c]=0}

  local function tryPush(nc,nr, d)
    if not inBounds(nc,nr) then return end
    local occ = STATE.board[nr][nc]
    if occ and not passThroughUnits then return end
    if not canEnterTile(def, nc, nr) then return end
    dist[nr] = dist[nr] or {}
    if dist[nr][nc] == nil and d <= maxSteps then
      dist[nr][nc] = d ; q[#q+1] = {c=nc,r=nr}
    end
  end

  local head=1
  while head <= #q do
    local node = q[head]; head = head + 1
    local dHere = dist[node.r][node.c]
    if dHere < maxSteps then
      for _,n in ipairs(neighbors4(node.c,node.r)) do
        tryPush(n[1], n[2], dHere+1)
      end
    end
  end

  local set = {}
  for rr,row in pairs(dist) do
    for cc,_ in pairs(row) do
      if not (rr==r and cc==c) and (not STATE.board[rr][cc]) then
        set[rr] = set[rr] or {} ; set[rr][cc] = true
      end
    end
  end
  return set
end

-- ── Config ─────────────────────────────────────────────────────────────
cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE = 8   -- tweak: frames per tile step
-- Easing (0..1 -> 0..1), smoothstep
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
    local u = STATE.board[y][x]
    if u then
      if u.owner ~= owner then return x,y end
      return nil,nil
    end
    x, y = x+dc, y+dr
  end
  return nil,nil
end

function cardGameFortune.legalAttacksFrom(c,r)
  local res = {}
  local A = STATE.board[r][c]; if not A or A.isLeader or A.hasAttacked then return res end
  local def = cardGameFortune.db[A.cardId]
  local atktype = def and def.atktype or "normal"

  if atktype == "normal" then
    -- adjacent 8-way
    for _,n in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}) do
      local nc, nr = c+n[1], r+n[2]
      if inBounds(nc,nr) then
        local D = STATE.board[nr][nc]
        if D and D.owner ~= A.owner then
          res[nr] = res[nr] or {}; res[nr][nc] = true
        end
      end
    end
  else
    -- ray cast in 4 directions (volley/ranged); stop at first unit
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local nc,nr = rayFirstHit(c,r, d[1],d[2], A.owner)
      if nc then res[nr] = res[nr] or {}; res[nr][nc] = true end
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

-- Advance per-frame FX timers
function cardGameFortune.stepFX()
    local s = STATE; if not s then return end
    for r=0,s.rows-1 do
        for c=0,s.cols-1 do
            local u = s.board[r] and s.board[r][c]
            if u and u._fx and u._fx.kind=="summon" then
                u._fx.t = u._fx.t + 1
                for _,p in ipairs(u._fx.sparks) do p.t = p.t + 1 end
                if u._fx.t >= u._fx.dur then u._fx = nil end
            end
        end
    end
end


function cardGameFortune.moveUnit(c1,r1, c2,r2)
    local s = STATE; local u = s.board[r1] and s.board[r1][c1]
    if not u then return false,"no unit" end
    if u.owner ~= s.whoseTurn then return false,"not your unit/turn" end
    if u.hasMoved then return false,"already moved" end
    if s.board[r2] and s.board[r2][c2] then return false,"occupied" end

    local legal = u.isLeader and cardGameFortune.legalLeaderMovesFrom(c1,r1)
                           or  cardGameFortune.legalMovesFrom(c1,r1)
    if not (legal[r2] and legal[r2][c2]) then return false,"illegal dest" end

    -- MOVE: update logic immediately
    s.board[r2][c2] = u
    s.board[r1][c1] = nil

    if not u.isLeader then u.pos = "attack" end
    u.hasMoved = true
    u.hasAttacked = true

    if u.isLeader and s.leaderPos and s.leaderPos[u.owner] then
        s.leaderPos[u.owner].c, s.leaderPos[u.owner].r = c2, r2
    end

    -- ── NEW: attach a slide animation to this unit ─────────
    local dist = math.abs(c2 - c1) + math.abs(r2 - r1)
    local base = cardGameFortune.MOVE_ANIM_FRAMES_PER_TILE
    u._anim = {
        kind  = "slide",
        fromC = c1, fromR = r1,
        toC   = c2, toR   = r2,
        t     = 0,
        dur   = math.max(1, base * math.max(1, dist)),
        ease  = easeSmooth,
    }
    -- ───────────────────────────────────────────────────────

    return true
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

    -- attacker stats tile:
    --   melee  -> defender's tile
    --   ranged -> attacker's tile
    local atkC, atkR = (isMelee and dc or ac), (isMelee and dr or ar)
    local aATK = select(1, cardGameFortune.getEffectiveStats(aDef, atkC, atkR))

    local destroyA, destroyD = false, false
    local damagePlayer, damageAmt = nil, 0

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

    if destroyD then s.board[dr][dc] = nil end
    if destroyA then s.board[ar][ac] = nil end

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
    hand[handIndex] = nil
    local newHand = {}
    for i=1,#hand do if hand[i] ~= nil then newHand[#newHand+1] = hand[i] end end
    STATE.hands[player] = newHand
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
    -- SFX.play(3)

    return true, "Placed"
end

-- End the current player's turn (refresh energy and draw)
function cardGameFortune.endTurn()
  local np = (STATE.whoseTurn == 1) and 2 or 1
  STATE.whoseTurn = np
  STATE.phase = "main"

  -- start-of-turn resources for the new active player
  STATE.energy[np] = (STATE.energy[np] or 0) + 3
  cardGameFortune.draw(np, 1)

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
    board      = STATE.board, -- ok to pass by ref for drawing (read-only by convention)
  }
end

local function newCard(t) return t end

local CARDS = {

-- TEMPLATE
{
  id          = "unique_id_here",
  name        = "Display Name",
  image       = "cardgame/default.png",     -- ok to leave as default path for now
  icon        = "cardgame/default_icon.png",
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
        image="cardgame/goombaicon.png", icon="cardgame/goombaicon.png",
        description="A basic enemy. Weak alone, strong in numbers.",
        type="melee", atk=3, def=2, movement=1,
        movementtype="normal", atktype="normal",
        subtype1="normal", subtype2="overworld",
        summoncost=1, deckcost=1
    },

-- DEFENSIVE
    newCard{
        id="green_koopa", name="Green Koopa",
        image="cardgame/koopaicon.png", icon="cardgame/koopaicon.png",
        description="Hides in its shell when attacked.",
        type="defensive", atk=3, def=4, movement=1,
        movementtype="normal", atktype="normal",
        subtype1="normal", subtype2="overworld",
        summoncost=2, deckcost=2
    },

-- GRAPPLER
    newCard{
        id="chargin_chuck", name="Chargin’ Chuck",
        image="cardgame/chuckicon.png", icon="cardgame/chuckicon.png",
        description="Rams into foes with football tackles.",
        type="grappler", atk=6, def=5, movement=2,
        movementtype="normal", atktype="normal",
        subtype1="normal", subtype2="overworld",
        summoncost=3, deckcost=3
    },

-- RANGED
    newCard{
        id="hammer_bro", name="Hammer Bro",
        image="cardgame/hammerbroicon.png", icon="cardgame/hammerbroicon.png",
        description="Throws hammers from afar.",
        type="ranged", atk=7, def=4, movement=1,
        movementtype="normal", atktype="ranged",
        subtype1="normal", subtype2="overworld",
        summoncost=3, deckcost=3
    },

-- MAGIC
    newCard{
        id="magikoopa", name="Magikoopa",
        image="cardgame/magikoopaicon.png", icon="cardgame/magikoopaicon.png",
        description="Casts unpredictable magic blasts.",
        type="magic", atk=12, def=11, movement=1,
        movementtype="normal", atktype="ranged",
        subtype1="normal", subtype2="sky",
        summoncost=4, deckcost=4
    },

-- TOWER
    newCard{
        id="bill_blaster", name="Bill Blaster",
        image="cardgame/billblastericon.png", icon="cardgame/billblastericon.png",
        description="Stationary cannon that fires Bullet Bills.",
        type="tower", atk=10, def=13, movement=0,
        movementtype="normal", atktype="volley",
        subtype1="normal", subtype2="airship",
        summoncost=4, deckcost=4
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

-- Manhattan helper
local function manhattan(c1,r1,c2,r2) return math.abs(c1-c2)+math.abs(r1-r2) end

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
                                if ai_plugsLeaderGap(cc,rr, 2) then wallScore = wallScore + WALL.FILL_GAP_BONUS end
                                if STATE.leaderPos and STATE.leaderPos[2] then
                                    local lp = STATE.leaderPos[2]
                                    if math.max(math.abs(cc-lp.c), math.abs(rr-lp.r)) == 1 then
                                    wallScore = wallScore + WALL.RING_BONUS
                                    end
                                end
                                wallScore = wallScore + ai_adjWallCount(cc,rr, 2) * WALL.LINE_BONUS
                                if ai_isChokeTile(cc,rr) then wallScore = wallScore + WALL.CHOKE_BONUS end
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

            -- take up to 3 safest moves as candidates
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
                for i=1, math.min(3, #moves) do
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