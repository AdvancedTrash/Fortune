--[[

	Written by MrDoubleA
	Please give credit!
	
	Credit to Novarender for helping with the logic for the movement of the bullets

	Part of MrDoubleA's NPC Pack

]]

local npcManager = require("npcManager")
local ai = require("mechakoopa_ai")

local bullet = {}
local npcID = NPC_ID

local deathEffectID = (npcID-3)

local explosionType = Explosion.register(48,979,37,true,false)

local bulletSettings = {
	id = npcID,
	
	gfxwidth = 32,
	gfxheight = 32,

	gfxoffsetx = 0,
	gfxoffsety = 0,
	
	width = 32,
	height = 32,
	
	frames = 2,
	framestyle = 0,
	framespeed = 8,
	
	speed = 1,
	
	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt = false,
	nogravity = true,
	noblockcollision = true,
	nofireball = true,
	noiceball = false,
	noyoshi = false,
	nowaterphysics = true,
	
	jumphurt = false,
	spinjumpsafe = false,
	harmlessgrab = false,
	harmlessthrown = false,

	lifetime = 448,        -- How long the NPC waits before exploding.
	rotationSpeed = 0.01, -- How quickly the NPC rotates.

	explosionType = explosionType, -- The type of explosion the NPC spawns when exploding.
}

npcManager.setNpcSettings(bulletSettings)
npcManager.registerDefines(npcID,{NPC.HITTABLE})
npcManager.registerHarmTypes(npcID,
	{
		HARM_TYPE_JUMP,
		HARM_TYPE_FROMBELOW,
		HARM_TYPE_NPC,
		HARM_TYPE_PROJECTILE_USED,
		HARM_TYPE_LAVA,
		HARM_TYPE_HELD,
		HARM_TYPE_TAIL,
		HARM_TYPE_OFFSCREEN,
		HARM_TYPE_SWORD
	}, 
	{ -- Normal death effects have to be spawned manually
		[HARM_TYPE_JUMP]            = deathEffectID,
		[HARM_TYPE_FROMBELOW]       = deathEffectID,
		[HARM_TYPE_NPC]             = deathEffectID,
		[HARM_TYPE_PROJECTILE_USED] = deathEffectID,
		[HARM_TYPE_HELD]            = deathEffectID,
		[HARM_TYPE_TAIL]            = deathEffectID,
		[HARM_TYPE_LAVA] = {id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
	}
)

ai.registerBullet(npcID)


--- Custom Explosion Stuff ---
function bullet.onInitAPI()
	registerEvent(bullet,"onPostExplosion")
end

function bullet.onPostExplosion(v,p)
	if NPC.config[npcID].explosionType <= 5 or v.id ~= NPC.config[npcID].explosionType then return end

	for x=-1,1,2 do
		for y=-1,1,2 do
			local e = Effect.spawn(10,0,0)

			e.x = v.x-(x*(v.radius/2))-(e.width /2)
			e.y = v.y-(y*(v.radius/2))-(e.height/2)
		end
	end

	if not v.strong then return end

	-- Destroy some extra blocks
	for _,w in ipairs(Colliders.getColliding{a = v.collider,b = Block.MEGA_STURDY,btype = Colliders.BLOCK}) do
		w:remove(true,Player(0))
	end
end



return bullet