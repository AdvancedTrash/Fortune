--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local npcCreator = require("AI/npcCreator")

--Create the library table
local sampleNPC = {}
--NPC_ID is dynamic based on the name of the library file
local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local sampleNPCSettings = {
	id = npcID,
	gfxwidth = 32,
	gfxheight = 32,
	width = 32,
	height = 32,
	speed = 1,
	nowaterphysics = true,
	staticdirection = true,
	
	--Collision-related
	npcblock = false, -- The NPC has a solid block for collision handling with other NPCs.
	npcblocktop = false, -- The NPC has a semisolid block for collision handling. Overrides npcblock's side and bottom solidity if both are set.
	playerblock = false, -- The NPC prevents players from passing through.
	playerblocktop = false, -- The player can walk on the NPC.

	nohurt=true, -- Disables the NPC dealing contact damage to the player
	nogravity = true,
	nofireball = false,
	noiceball = false,
	noyoshi= false,

	jumphurt = true, --If true, spiny-like (prevents regular jump bounces)

	--Collision-related
	npcblock = false, -- The NPC has a solid block for collision handling with other NPCs.
	npcblocktop = false, -- The NPC has a semisolid block for collision handling. Overrides npcblock's side and bottom solidity if both are set.
	playerblock = false, -- The NPC prevents players from passing through.
	playerblocktop = false, -- The player can walk on the NPC.

	grabside=false,
	grabtop=false,
	
	destroyblocktable = {90, 4, 188, 60, 293, 667, 457, 666, 686, 668, 526, 1374, 1375, 192, 193, 5, 224, 2, 225, 226, 88, 89, 115},
	
	--A list of things that NPC does NOT turn around on
	coolListOfThings = {13, 265, 667, 171, 292, 291, 266, 436, 178, 455, 456, 30, 525, 559, 462, 159, 288, 289, 202, 348, 133, 40, 259, 323, 324, 11, 97, 16, 41, 418, 419, 511, 390, 526, 85, 87, 366, 376, 246, 260, 615, 547, 269, 396, 617, 706, 705, 695, 696, 697, 698, 699, 570, 476, 714, 715, 716, 717, 106, 500, 378, 556, 557, 421, 579, 340, 341, 342, 343, 627, 628, 655, 473, 600, 601, 602, 603, 473, 433, 434, 22, 49, 240, 248, 488, 278, 279, 56, 711, 636, 637, 638, 639, 465, 669, 670, 671, 672, 673, 674, 675, 676, 210, 306, 397, 398, 399, 410, 411, 721, 722, 188, 26, 457, 458, 196, 239, 335, 336, 337, 364, 501, 502, 503, 504, 505, 506, 507, 508, 338, 533, 534, 535, 536, 528, 412, 283, 353, 354, 400, 430, 192, 197, 477, 478, 479, 480, 481, 482, 483, 484, 387, 591, 592, 105, 367, 339, 391, 190, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 681, 682, 683, 684, 582, 584, 594, 596, 381, 359, 108, 361, 282, 276, 237, 362, 356, 300, 319, 414, 416, 384, 385, 527},
	
	-- Various interactions
	-- ishot = true,
	-- iscold = true,
	-- durability = -1, -- Durability for elemental interactions like ishot and iscold. -1 = infinite durability
	 weight = 2,
	-- isstationary = true, -- gradually slows down the NPC
	-- nogliding = true, -- The NPC ignores gliding blocks (1f0)
}

--Applies NPC settings
npcManager.setNpcSettings(sampleNPCSettings)

--Register the vulnerable harm types for this NPC. The first table defines the harm types the NPC should be affected by, while the second maps an effect to each, if desired.
npcManager.registerHarmTypes(npcID,
	{
		HARM_TYPE_JUMP,
		HARM_TYPE_FROMBELOW,
		HARM_TYPE_NPC,
		HARM_TYPE_PROJECTILE_USED,
		HARM_TYPE_LAVA,
		HARM_TYPE_HELD,
		HARM_TYPE_TAIL,
		HARM_TYPE_SPINJUMP,
		HARM_TYPE_OFFSCREEN,
		HARM_TYPE_SWORD
	},
	
	{
		[HARM_TYPE_LAVA]={id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
		[HARM_TYPE_SPINJUMP]=10,
		--[HARM_TYPE_OFFSCREEN]=10,
		[HARM_TYPE_SWORD]=10,
	}
);

npcCreator.register(npcID)

--Gotta return the library table!
return sampleNPC