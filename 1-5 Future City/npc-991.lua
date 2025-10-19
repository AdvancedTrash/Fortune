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

local transformID = (npcID-1)
local deathEffectID = (npcID-5)

local mechakoopaSettings = {
	id = npcID,
	
	gfxwidth = 64,
	gfxheight = 64,

	gfxoffsetx = 0,
	gfxoffsety = 2,
	
	width = 32,
	height = 32,
	
	frames = 5,
	framestyle = 1,
	framespeed = 6,
	
	speed = 1,
	score = 0,
	
	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt = true,
	nogravity = false,
	noblockcollision = false,
	nofireball = true,
	noiceball = false,
	noyoshi = false,
	nowaterphysics = false,
	
	jumphurt = true,
	spinjumpsafe = false,
	harmlessgrab = false,
	harmlessthrown = false,

	cliffturn = false,
	grabside = true,
	grabtop = false,

	recoverTime = 585, -- How long the NPC is idle before transforming.
	recoverFrames = 2,

	deacceleration = 0.35,
	kickSpeedX = 6,
	kickSpeedY = -2,

	shakeWhenRecovering = true,
	animateWhenKicked = true,

	transformID = transformID,     -- The ID of the NPC that the NPC will transform into when hit/recovering.
 	deathEffectID = deathEffectID, -- The ID of the effect spawned when the mechakoopa is killed, or can be nil for none.
	deathEffectVariantMap = ai.flyingEffectVariants,
}

npcManager.setNpcSettings(mechakoopaSettings)
npcManager.registerDefines(npcID,{NPC.HITTABLE})
npcManager.registerHarmTypes(npcID,
	{
		--HARM_TYPE_JUMP,
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

ai.register(npcID,ai.TYPE_KNOCKED)

return mechakoopa