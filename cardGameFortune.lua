
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
  if (not cell) or cell.isLeader or cell.summoningSickness or cell.hasMoved then
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

function cardGameFortune.moveUnit(c1,r1, c2,r2)
    local s = STATE; if not s then return false,"no state" end
    local u = s.board[r1] and s.board[r1][c1]
    if not u then return false,"no unit" end
    if u.hasMoved then return false,"already moved" end
    if s.board[r2] and s.board[r2][c2] then return false,"occupied" end

    local legal = u.isLeader and cardGameFortune.legalLeaderMovesFrom(c1,r1)
                           or  cardGameFortune.legalMovesFrom(c1,r1)
    if not (legal[r2] and legal[r2][c2]) then return false,"illegal dest" end

    s.board[r2][c2] = u
    s.board[r1][c1] = nil

    -- movement sets stance to ATK
    if not u.isLeader then
        u.pos = "attack"
    end

    u.hasMoved = true

    -- if this was a leader, keep leaderPos in sync (you already added this earlier)
    if u.isLeader and s.leaderPos and s.leaderPos[u.owner] then
        s.leaderPos[u.owner].c, s.leaderPos[u.owner].r = c2, r2
    end
    return true
end

-- Switch a unit from ATK to DEF as your "movement" for the turn.
function cardGameFortune.fortifyToDefense(c,r)
    local s = STATE; if not s then return false,"no state" end
    local u = s.board[r] and s.board[r][c]
    if not u or u.isLeader then return false,"no unit" end
    if u.owner ~= s.whoseTurn then return false,"not your unit" end
    if u.summoningSickness then return false,"summoning" end
    if u.hasMoved then return false,"already moved" end   -- consumes the move
    if u.pos == "defense" then return false,"already defense" end

    u.pos = "defense"
    u.hasMoved = true          -- uses up the move
    -- note: we do NOT touch hasAttacked → you can still attack earlier this turn, then fortify
    return true
end

-- YGO-like battle resolution, non-random
function cardGameFortune.resolveBattle(ac,ar, dc,dr)
    local s = STATE; if not s then return false,"no state" end

    local A = s.board[ar] and s.board[ar][ac]
    local D = s.board[dr] and s.board[dr][dc]

    if not A.isLeader and A.pos ~= "attack" then
    A.pos = "attack"
end
    if (not A) or (not D) then return false,"no piece" end
    if A.owner == D.owner then return false,"same owner" end
    if A.hasAttacked then return false,"already attacked" end

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
    local hand   = STATE.hands[player]
    local cardId = hand[handIndex]
    if not cardId then return false, "No card in that hand slot" end

    local ok, err = cardGameFortune.canSummonAt(player, c, r, cardId)
    if not ok then return false, err end

    
    -- position = "attack" or "defense"
    if not inBounds(c,r) then return false, "Out of bounds" end
    if STATE.board[r][c] then return false, "Tile occupied" end

    local hand = STATE.hands[player]
    local cardId = hand[handIndex]
    if not cardId then return false, "No card in that hand slot" end
    if not canAfford(player, cardId) then return false, "Not enough energy" end
    local base = cardGameFortune.db[cardId]

    -- remove from hand
    hand[handIndex] = nil
    local newHand = {}
    for i=1,#hand do if hand[i]~=nil then newHand[#newHand+1]=hand[i] end end
    STATE.hands[player] = newHand
    spend(player, cardId)

    local pos = (position == "defense") and "defense" or "attack"
    local hpVal = (pos == "defense") and (base.def or 0) or (base.atk or 0)

    STATE.board[r][c] = {
        cardId  = cardId,
        owner   = player,
        atk     = base.atk or 0,
        def     = base.def or 0,
        hp      = hpVal,
        pos     = pos,
    }
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

local function ai_manhattan(a,b) return math.abs(a.c-b.c) + math.abs(a.r-b.r) end

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


local function ai_bestMoveToward(c,r, owner)
    local legal = cardGameFortune.legalMovesFrom(c,r)
    if not legal then return nil end

    local goal = ai_enemyLeaderPos(owner)
    if not goal then return nil end

    local threats = ai_buildThreatMap(owner)  -- tiles enemy can hit next
    local best, bestD, bestSafe = nil, math.huge, nil

    for rr,row in pairs(legal) do
        for cc,_ in pairs(row) do
            local here = {c=cc,r=rr}
            local d = math.abs(here.c - goal.c) + math.abs(here.r - goal.r)

            -- prefer non-threatened squares if possible
            local threatened = threats[rr] and threats[rr][cc]

            -- track best safe option
            if not threatened and d < bestD then
                bestD, bestSafe = d, here
            end

            -- always track best (in case all are threatened)
            if d < bestD or (best and d == bestD and threatened == false) then
                bestD, best = d, here
            end
        end
    end
    return bestSafe or best
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

-- tiles the enemy can hit next (simple threat map)
local function ai_buildThreatMap(vsOwner)
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

-- decide stance to place: "attack" or "defense"
local function ai_chooseSummonPos(owner, cid, c, r, threats)
    local def = cardGameFortune.db[cid]
    local atktype = (def and (def.atktype or "normal")) or "normal"

    local aATK, aDEF, terr, delta = cardGameFortune.getEffectiveStats(def, c, r)
    local threatened  = threats[r] and threats[r][c] or false
    local adjEnemy    = hasAdjacentEnemy(c,r, owner)
    local tanky       = (aDEF >= aATK + 2)           -- skewed to DEF
    local badTerrain  = (delta or 0) < 0             -- unfavourable tile

    -- Ranged units tend to prefer ATK unless they spawn into danger.
    if atktype == "ranged" then
        if threatened and (tanky or badTerrain or adjEnemy) then
            return "defense"
        end
        return "attack"
    end

    -- Melee: go DEF if we’re threatened or right next to an enemy and DEF is decent/better.
    if (threatened or adjEnemy or badTerrain) and (tanky or aDEF >= aATK) then
        return "defense"
    end

    return "attack"
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

                                -- score: closer to enemy leader + terrain delta + tiny bonus if DEF chosen on threat
                                local def = cardGameFortune.db[cid]
                                local _,_,_,delta = cardGameFortune.getEffectiveStats(def, c, r)
                                local dist = (goal and (math.abs(c-goal.c)+math.abs(r-goal.r))) or 999
                                local threatened = threats[r] and threats[r][c] or false
                                local score = -dist + (delta or 0)*0.6 + ((pos=="defense" and threatened) and 1.5 or 0)

                                if (not best) or score > best.score then
                                    best = {i=i, c=c, r=r, pos=pos, score=score}
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



-- ───────────────────────────────────────────────────────────
-- Build a paced turn for Player 2 (AI)
-- ───────────────────────────────────────────────────────────
function cardGameFortune.aiBeginTurn()
    local s = STATE
    if not s or s.whoseTurn ~= 2 then return end
    local st = cardGameFortune.aiState
    if st.busy then return end

    st.busy, st.steps, st.delay = true, {}, 10   -- small think pause

    -- snapshot units (tables) now; we re-find them right before each action
    local units = {}
    for _,u in ipairs(ai_unitsOf(2)) do units[#units+1] = u.cell end

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