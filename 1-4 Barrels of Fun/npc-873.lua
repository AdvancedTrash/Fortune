--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")

--Create the library table
local sampleNPC = {}
--NPC_ID is dynamic based on the name of the library file
local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local sampleNPCSettings = {
	id = npcID,
	--Sprite size
	gfxwidth = 32,
	gfxheight = 32,
	--Hitbox size. Bottom-center-bound to sprite size.
	width = 32,
	height = 32,
	--Sprite offset from hitbox for adjusting hitbox anchor on sprite.
	gfxoffsetx = 0,
	gfxoffsety = 0,
	--Frameloop-related
	frames = 8,
	framestyle = 1,
	framespeed = 6, --# frames between frame change
	--Movement speed. Only affects speedX by default.
	speed = 1,
	--Collision-related
	--npcblock = true,
	--npcblocktop = true, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	--playerblock = true,
	--playerblocktop = true, --Also handles other NPCs walking atop this NPC.

	nohurt=true,
	nogravity = false,
	noblockcollision = false,
	nofireball = false,
	noiceball = false,
	noyoshi= false,
	nowaterphysics = false,
	luahandlesspeed = true,
	
	--Various interactions
	jumphurt = true, --If true, spiny-like
	spinjumpsafe = false, --If true, prevents player hurt when spinjumping
	harmlessgrab = false, --Held NPC hurts other NPCs if false
	harmlessthrown = false, --Thrown NPC hurts other NPCs if false

	grabside=true,
	grabtop=true,
	
	score=0,

	--Identity-related flags. Apply various vanilla AI based on the flag:
	--iswalker = false,
	--isbot = false,
	--isvegetable = false,
	--isshoe = false,
	--isyoshi = false,
	--isinteractable = false,
	--iscoin = false,
	--isvine = false,
	--iscollectablegoal = false,
	--isflying = false,
	--iswaternpc = false,
	isshell = true,

	--Emits light if the Darkness feature is active:
	--lightradius = 100,
	--lightbrightness = 1,
	--lightoffsetx = 0,
	--lightoffsety = 0,
	--lightcolor = Color.white,

	--Define custom properties below
}

--Applies NPC settings
npcManager.setNpcSettings(sampleNPCSettings)

--Register the vulnerable harm types for this NPC. The first table defines the harm types the NPC should be affected by, while the second maps an effect to each, if desired.
npcManager.registerHarmTypes(npcID,
	{
		--HARM_TYPE_JUMP,
		--HARM_TYPE_FROMBELOW,
		--HARM_TYPE_NPC,
		--HARM_TYPE_PROJECTILE_USED,
		--HARM_TYPE_LAVA,
		--HARM_TYPE_HELD,
		--HARM_TYPE_TAIL,
		--HARM_TYPE_SPINJUMP,
		--HARM_TYPE_OFFSCREEN,
		--HARM_TYPE_SWORD
	}, 
	{
		--[HARM_TYPE_JUMP]=10,
		--[HARM_TYPE_FROMBELOW]=10,
		[HARM_TYPE_NPC]=873,
		--[HARM_TYPE_PROJECTILE_USED]=10,
		--[HARM_TYPE_LAVA]={id=13, xoffset=0.5, xoffsetBack = 0, yoffset=1, yoffsetBack = 1.5},
		--[HARM_TYPE_HELD]=10,
		--[HARM_TYPE_TAIL]=10,
		--[HARM_TYPE_SPINJUMP]=10,
		--[HARM_TYPE_OFFSCREEN]=10,
		--[HARM_TYPE_SWORD]=10,
	}
);

--Custom local definitions below


--Register events
function sampleNPC.onInitAPI()
	npcManager.registerEvent(npcID, sampleNPC, "onTickEndNPC")
	--npcManager.registerEvent(npcID, sampleNPC, "onTickEndNPC")
	--npcManager.registerEvent(npcID, sampleNPC, "onDrawNPC")
	--registerEvent(sampleNPC, "onNPCKill")
end

function sampleNPC.onTickEndNPC(v)
	--Don't act during time freeze
	if Defines.levelFreeze then return end
	
	local data = v.data
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		if data.solid ~= nil then
			if data.solid.isValid then
				data.solid:delete()
			end
		end
		data.initialized = false
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
		data.fadeTimer = 500
	end

	--Depending on the NPC, these checks must be handled differently
	if v:mem(0x12C, FIELD_WORD) > 0    --Grabbed
	or v:mem(0x136, FIELD_BOOL)        --Thrown
	or v:mem(0x138, FIELD_WORD) > 0    --Contained within
	then
		--Handling
	end
	
	--Execute main AI. This template just jumps when it touches the ground.
	v:mem(0x136, FIELD_BOOL, true)

	data.fadeTimer = data.fadeTimer - 1
	
	if data.fadeTimer == 0 then
		v:kill(HARM_TYPE_OFFSCREEN)
		Animation.spawn(10, v.x, v.y)
	elseif data.fadeTimer <= 100 then
		v.animationTimer = v.animationTimer - .5
	end

	v.noblockcollision = false
	if v.collidesBlockLeft or v.collidesBlockRight then
		v:kill(HARM_TYPE_OFFSCREEN)
		Animation.spawn(873, v.x + (v.width / 2), v.y + (v.height / 2))
		--SFX.play(4)
	end
	
	if v.speedX == 5 * v.direction then
		v.speedX = 7 * v.direction
		v.speedY = 0
	end
	
	if Colliders.collide(player, v) and player.holdingNPC ~= v then
		v.friendly = true
		if v.speedX == 0 and v.speedY > -4 then
			if player.x > v.x + (v.width / 2) then
				v.direction = -1
			else
				v.direction = 1
			end
			v.speedX = 7 * v.direction
			SFX.play(9)
		end
	else
		v.friendly = false
	end
end

--Gotta return the library table!
return sampleNPC