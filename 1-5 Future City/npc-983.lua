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
local deathEffectID = (npcID-1)

local mechakoopaSettings = {
	id = npcID,
	
	gfxwidth = 64,
	gfxheight = 64,

	gfxoffsetx = 0,
	gfxoffsety = 2,
	
	width = 32,
	height = 32,
	
	frames = 10,
	framestyle = 1,
	framespeed = 6,
	
	speed = 1,
	
	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt = false,
	nogravity = false,
	noblockcollision = false,
	nofireball = true,
	noiceball = false,
	noyoshi = false,
	nowaterphysics = false,
	
	jumphurt = false,
	spinjumpsafe = false,
	harmlessgrab = false,
	harmlessthrown = false,

	cliffturn = true,
	grabside = false,
	grabtop = false,

	wanderSpeed = 0.7,
	turnTime = 65, -- How long the NPC must be facing away from the player to turn around.

	attackDistance = 256, -- How close the player must be before the NPC can begin an attack. (Only affects zappa and blasta mechakoopas.)
	attackStartTime = 96, -- How long the NPC will wait before beginning an attack. (Only affects zappa and blasta mechakoopas.)

	attackPrepareTime = 32, -- How long the NPC takes to begin an attack. (Only affects zappa and blasta mechakoopas.)
	attackReturnTime = 32,  -- How long the NPC takes to return to walking after an attack. (Only affects zappa and blasta mechakoopas.)

	attackTime = 128, -- How long the NPC takes to finish its attack. (Only affects zappa and blasta mechakoopas.)
	attackFrames = 6,

	laserSpeed = 16,
	laserKillsNPCs = true,

	laserColor     = 0x3296FFFF,                                                          -- The color of the NPC's laser. Can be either an RGBA hex color or a color object. (Only affects zappa mechakoopas.)
	laserPointGFX  = Graphics.loadImage(Misc.resolveFile("mechakoopa_laser_point.png")),  -- The graphic used for the start and end of the NPC's laser. (Only affects zappa mechakoopas.)
	laserMiddleGFX = Graphics.loadImage(Misc.resolveFile("mechakoopa_laser_middle.png")), -- The graphic used for the middle of the NPC's laser. (Only affects zappa mechakoopas.)

	laserPointPulse = true,
	preLaserEffect = (npcID - 3),
	laserFrames = 3,
	laserPointFrames = 2,
	laserFramespeed = 4,

	prepareSFX = SFX.open(Misc.resolveFile("mechakoopa_laser_prepare.wav")), -- The sound effect played when the NPC prepares an attack. Can be nil for none, a number for a vanilla sound, or a sound effect object/string for a custom sound. (Only affects zappa and blasta mechakoopas.)
	fireSFX    = SFX.open(Misc.resolveFile("mechakoopa_laser_fire.wav")),    -- The sound effect played when the NPC executes an attack. Can be nil for none, a number for a vanilla sound, or a sound effect object/string for a custom sound. (Only affects zappa and blasta mechakoopas.)

	transformID = transformID,     -- The ID of the NPC that the NPC will transform into when hit/recovering.
 	deathEffectID = deathEffectID, -- The ID of the effect spawned when the mechakoopa is killed, or can be nil for none.
	deathEffectVariantMap = ai.effectVariants,
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

ai.register(npcID,ai.TYPE_LASER)

return mechakoopa