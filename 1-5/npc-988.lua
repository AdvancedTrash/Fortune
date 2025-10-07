--[[

	Written by MrDoubleA
	Please give credit!
	
	Credit to Novarender for helping with the logic for the movement of the bullets

	Part of MrDoubleA's NPC Pack

]]

local npcManager = require("npcManager")
local ai = require("mechakoopa_ai")

local mechakoopa = {}
local npcID = NPC_ID

local transformID = (npcID+1)
local deathEffectID = (npcID-3)

local mechakoopaSettings = {
	id = npcID,
	
	gfxwidth = 64,
	gfxheight = 64,

	gfxoffsetx = 0,
	gfxoffsety = 2,
	
	width = 32,
	height = 32,
	
	frames = 4,
	framestyle = 1,
	framespeed = 6,
	
	speed = 1,
	
	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt = false,
	nogravity = true,
	noblockcollision = false,
	nofireball = true,
	noiceball = false,
	noyoshi = false,
	nowaterphysics = false,
	
	jumphurt = false,
	spinjumpsafe = false,
	harmlessgrab = false,
	harmlessthrown = false,

	cliffturn = false,
	grabside = false,
	grabtop = false,

	wanderSpeed = 1,
	turnTime = 65, -- How long the NPC must be facing away from the player to turn around.

	isFlyingMechakoopa = true, -- Is the NPC a Flying Mechakoopa?

	chaseDistance = 320, -- How close the player must be before the NPC can begin chasing.
	priorityRate = 4, -- Determines the logic to satisfy priority conditions.
	patrolTime = 80, -- How long the NPC patrols to turn around.
	decideTime = 32, -- How long the NPC decides before acting.
	checkTime = 32, -- How long the NPC chases before checking.
	flyingSpeed = 1, --How fast will the NPC will chase the player.

	propellorIMG = Graphics.loadImageResolved("npc-"..npcID.."-propellor.png"),
	propellorOffsetX = -10,
	propellorOffsetY = 29,
	propellorFrames = 4,
	propellorFramespeed = 2,

	transformID = transformID,     -- The ID of the NPC that the NPC will transform into when hit/recovering.
 	deathEffectID = deathEffectID, -- The ID of the effect spawned when the mechakoopa is killed, or can be nil for none.
	deathEffectVariantMap = ai.flyingEffectVariants,
}

npcManager.setNpcSettings(mechakoopaSettings)
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
		[HARM_TYPE_LAVA]={id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
	}
)

ai.register(npcID,ai.TYPE_NORMAL)

return mechakoopa