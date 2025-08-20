--NPCManager is required for setting basic NPC properties
local npcManager = require("npcManager")
local npcutils = require("npcs/npcutils")

--Create the library table
local sampleNPC = {}
--NPC_ID is dynamic based on the name of the library file
local npcID = NPC_ID

--Defines NPC config for our NPC. You can remove superfluous definitions.
local sampleNPCSettings = {
	id = npcID,
	--Sprite size
	gfxheight = 32,
	gfxwidth = 32,
	width = 32,
	height = 32,
	frames = 2,
	framestyle = 0,
	framespeed = 8, --# frames between frame change
	--Collision-related
	npcblock = true,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = false, --Also handles other NPCs walking atop this NPC.

	nohurt=false,
	nogravity = false,
	noblockcollision = false,
	nofireball = true,
	noiceball = true,
	noyoshi= true,
	nowaterphysics = false,
	--Various interactions
	jumphurt = true, --If true, spiny-like
	spinjumpsafe = false, --If true, prevents player hurt when spinjumping
	harmlessgrab = false, --Held NPC hurts other NPCs if false
	harmlessthrown = false, --Thrown NPC hurts other NPCs if false

	grabside=false,
	grabtop=false,
}

--Applies NPC settings
npcManager.setNpcSettings(sampleNPCSettings)

npcManager.registerDefines(npcID, {NPC.UNHITTABLE})

--Register events
function sampleNPC.onInitAPI()
	npcManager.registerEvent(npcID, sampleNPC, "onTickEndNPC")
	npcManager.registerEvent(npcID, sampleNPC, "onDrawNPC")
end

function sampleNPC.onTickEndNPC(v)
	--Don't act during time freeze
	if Defines.levelFreeze then return end
	
	local data = v.data
	local config = NPC.config[v.id]
	local slopeRotation = 0
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		data.initialized = false
		data.offset = 0
		return
	end

	--Initialize
	if not data.initialized then
		--Initialize necessary data.
		data.initialized = true
		data.offset = data.offset or 0
		data.detectBox = Colliders.Box(v.x, v.y, v.width / 2, v.height * 1 + 1);
	end

	--Move collider with NPC
	data.detectBox.x = v.x + sampleNPCSettings.gfxwidth / 4
	data.detectBox.y = v.y + 24
	
	--Code to make the NPC adjust its sprite accordingly with slopes
	local collidingBlocks = Colliders.getColliding{
    a = data.detectBox,
    b = Block.SOLID .. Block.SEMISOLID .. Block.PLAYER,
    btype = Colliders.BLOCK,
	}
	
	for _,block in pairs(collidingBlocks) do
		if Block.config[block.id].floorslope ~= 0 then
			if Block.config[block.id].floorslope == 1 then
				if v.direction == DIR_LEFT then
					slopeRotation =	(1 - Block.config[block.id].height / Block.config[block.id].width * 50 * v.direction)
				else
					slopeRotation =	(1 - Block.config[block.id].height / Block.config[block.id].width * -50 * v.direction)
				end
			elseif Block.config[block.id].floorslope == -1 then
				if v.direction == DIR_LEFT then
					slopeRotation =	(1 - Block.config[block.id].height / Block.config[block.id].width * -50 * v.direction)
				else
					slopeRotation =	(1 - Block.config[block.id].height / Block.config[block.id].width * 50 * v.direction)
				end
			end
			
			--Make the sprite display a little better when on slopes
			if v.collidesBlockBottom then
				data.offset = math.floor(0.2 * slopeRotation) * Block.config[block.id].floorslope
			end
		end
		if v.collidesBlockBottom then
			data.rotation = slopeRotation
		end
	end
end

local function drawSprite(args) -- handy function to draw sprites
	args = args or {}

	args.sourceWidth  = args.sourceWidth  or args.width
	args.sourceHeight = args.sourceHeight or args.height

	if sprite == nil then
		sprite = Sprite.box{texture = args.texture}
	else
		sprite.texture = args.texture
	end

	sprite.x,sprite.y = args.x,args.y
	sprite.width,sprite.height = args.width,args.height

	sprite.pivot = args.pivot or Sprite.align.CENTER
	sprite.rotation = args.rotation or 0

	if args.texture ~= nil then
		sprite.texpivot = args.texpivot or sprite.pivot or Sprite.align.CENTER
		sprite.texscale = args.texscale or vector(args.texture.width*(args.width/args.sourceWidth),args.texture.height*(args.height/args.sourceHeight))
		sprite.texposition = args.texposition or vector(-args.sourceX*(args.width/args.sourceWidth)+((sprite.texpivot[1]*sprite.width)*((sprite.texture.width/args.sourceWidth)-1)),-args.sourceY*(args.height/args.sourceHeight)+((sprite.texpivot[2]*sprite.height)*((sprite.texture.height/args.sourceHeight)-1)))
	end

	sprite:draw{priority = args.priority,color = args.color,sceneCoords = args.sceneCoords or args.scene}
end

function sampleNPC.onDrawNPC(v)
	local config = NPC.config[v.id]
	local data = v.data

	if v:mem(0x12A,FIELD_WORD) <= 0 or not data.rotation then return end

	local priority = -45
	if config.priority then
		priority = -15
	end

	drawSprite{
		texture = Graphics.sprites.npc[v.id].img,

		x = v.x+(v.width/2)+config.gfxoffsetx,y = v.y+v.height-(config.gfxheight/2)+config.gfxoffsety + data.offset,
		width = config.gfxwidth,height = config.gfxheight,

		sourceX = 0,sourceY = v.animationFrame*config.gfxheight,
		sourceWidth = config.gfxwidth,sourceHeight = config.gfxheight,

		priority = priority,rotation = data.rotation,
		pivot = Sprite.align.CENTRE,sceneCoords = true,
	}

	npcutils.hideNPC(v)
end

--Gotta return the library table!
return sampleNPC