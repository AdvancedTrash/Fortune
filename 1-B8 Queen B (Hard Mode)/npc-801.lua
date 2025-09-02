--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local zingers = require("AI/zingers")



--Create the library table
local zinger = {}
--NPC_ID is dynamic based on the name of the library file
local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local zingerSettings = {
	id = npcID,
	gfxheight = 96,
	gfxwidth = 96,
	width = 60,
	height = 66,
	frames = 8,
	framestyle = 1,
	framespeed = 8, 
	speed = 1,

	npcblock = false,
	npcblocktop = false,
	playerblock = false,
	playerblocktop = false, 

	nohurt=false,
	nogravity = true,
	noblockcollision = true,
	nofireball = true,
	noiceball = true,
	noyoshi= true,
	nowaterphysics = true,
	jumphurt = true, 
	spinjumpsafe = true, 
	harmlessgrab = false, 
	harmlessthrown = false, 

	grabside=false,
	grabtop=false,
	
	strong=true,


	--Define custom properties below
	
}local config = npcManager.setNpcSettings(zingerSettings)

--Applies NPC settings
npcManager.setNpcSettings(zingerSettings)

--Register the vulnerable harm types for this NPC. The first table defines the harm types the NPC should be affected by, while the second maps an effect to each, if desired.
npcManager.registerHarmTypes(npcID,
	{
		--HARM_TYPE_JUMP,
		--HARM_TYPE_FROMBELOW,
		--HARM_TYPE_NPC,
		--HARM_TYPE_PROJECTILE_USED,
		--HARM_TYPE_LAVA,
		HARM_TYPE_HELD,
		--HARM_TYPE_TAIL,
		--HARM_TYPE_SPINJUMP,
		--HARM_TYPE_OFFSCREEN,
		--HARM_TYPE_SWORD
	}, 
	{
		--[HARM_TYPE_JUMP]=10,
		--[HARM_TYPE_FROMBELOW]=10,
		--[HARM_TYPE_NPC]=npcID,
		--[HARM_TYPE_PROJECTILE_USED]=npcID,
		--[HARM_TYPE_LAVA]={id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
		[HARM_TYPE_HELD]=npcID,
		--[HARM_TYPE_TAIL]=10,
		--[HARM_TYPE_SPINJUMP]=10,
		--[HARM_TYPE_OFFSCREEN]=10,
		--[HARM_TYPE_SWORD]=10,
	}
);

zingers.register(npcID)


--Gotta return the library table!
return zinger