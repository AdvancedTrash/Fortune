
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

cardGameFortune.terrainBonus = {
  forest  = { subtype1 = {forest = 3}, subtype2 = {forest = 3} },
  airship = { subtype1 = {airship = 3}, subtype2 = {airship = 3} },
  normal  = {},
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

-- Public: start a fresh match
function cardGameFortune.newMatch(seed)
  local nextRand, getSeed = rng(seed or os.time())
  STATE.seed      = getSeed()
  STATE.board     = new2D(STATE.rows, STATE.cols)
  STATE.whoseTurn = 1
  STATE.phase     = "main"
  STATE.leaderHP  = { 40, 40 }
  STATE.energy    = { 15, 15 }
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
        owner=1, hp=STATE.leaderHP[1] or 30, pos="defense", isLeader=true
    }
    STATE.board[STATE.leaderPos[2].r][STATE.leaderPos[2].c] = {
        owner=2, hp=STATE.leaderHP[2] or 30, pos="defense", isLeader=true
    }
end

local function inBounds(c, r)
    return (STATE ~= nil)
       and (c >= 0 and c < STATE.cols)
       and (r >= 0 and r < STATE.rows)
end

function cardGameFortune.canSummonAt(player, c, r)
    if not inBounds(c,r) then return false, "Out of bounds" end
    if STATE.board[r][c] then return false, "Tile occupied" end
    local lp = STATE.leaderPos and STATE.leaderPos[player]
    if not lp then return false, "No leader" end
    if not isAdjacent(lp.c, lp.r, c, r) then
        return false, "Must be next to your leader"
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
    local ok, err = cardGameFortune.canSummonAt(player, c, r)
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
  STATE.whoseTurn = (STATE.whoseTurn == 1) and 2 or 1
  STATE.phase = "main"
  STATE.energy[STATE.whoseTurn] = 3
  cardGameFortune.draw(STATE.whoseTurn, 1)
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
        image="cardgame/chuck.png", icon="cardgame/chuckicon.png",
        description="Rams into foes with football tackles.",
        type="grappler", atk=6, def=5, movement=2,
        movementtype="normal", atktype="normal",
        subtype1="normal", subtype2="overworld",
        summoncost=3, deckcost=3
    },

-- RANGED
    newCard{
        id="hammer_bro", name="Hammer Bro",
        image="cardgame/hammerbro.png", icon="cardgame/hammerbroicon.png",
        description="Throws hammers from afar.",
        type="ranged", atk=7, def=4, movement=1,
        movementtype="normal", atktype="ranged",
        subtype1="normal", subtype2="overworld",
        summoncost=3, deckcost=3
    },

-- MAGIC
    newCard{
        id="magikoopa", name="Magikoopa",
        image="cardgame/magikoopa.png", icon="cardgame/magikoopaicon.png",
        description="Casts unpredictable magic blasts.",
        type="magic", atk=12, def=11, movement=1,
        movementtype="normal", atktype="ranged",
        subtype1="normal", subtype2="sky",
        summoncost=4, deckcost=4
    },

-- TOWER
    newCard{
        id="bill_blaster", name="Bill Blaster",
        image="cardgame/billblaster.png", icon="cardgame/billblastericon.png",
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

return cardGameFortune