--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")

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
	
	--Collision-related
	npcblock = false, -- The NPC has a solid block for collision handling with other NPCs.
	npcblocktop = false, -- The NPC has a semisolid block for collision handling. Overrides npcblock's side and bottom solidity if both are set.
	playerblock = false, -- The NPC prevents players from passing through.
	playerblocktop = false, -- The player can walk on the NPC.

	nohurt=true, -- Disables the NPC dealing contact damage to the player
	nogravity = true,
	nofireball = true,
	noiceball = true,
	noyoshi= true,

	jumphurt = true, --If true, spiny-like (prevents regular jump bounces)
	ignorethrownNPCs = true,
	noblockcollision = true,
	
	destroyblocktable = {90, 4, 188, 60, 293, 667, 457, 666, 686, 668, 526, 1374, 1375, 192, 193, 5, 224, 2, 225, 226, 88, 89, 115},
}

--Applies NPC settings
npcManager.setNpcSettings(sampleNPCSettings)

--Register events
function sampleNPC.onInitAPI()
	npcManager.registerEvent(npcID, sampleNPC, "onTickNPC")
end

function sampleNPC.onTickNPC(v)
	v.data.waypoint = v.data._settings.waypoint
end

--Gotta return the library table!
return sampleNPC