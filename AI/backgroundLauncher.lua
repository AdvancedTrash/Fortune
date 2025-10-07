--[[
	backgroundLauncher.lua v1.0 by "Master" of Disaster
	
	tie in for backgroundAreas.lua, used for npcs that can launch you to backgroundAreas
--]]

local backgroundLauncher = {
	launchHitboxHeight = 8,	-- the height of the hitbox above the launcher that checks whether the player above jumps
	launchSpeedXY = 6,	-- how many frames it takes to traverse 1 tile when launching
	launchSpeedZ = 50,	-- how many frames it addtionally takes to traverse 1 scale point
	cameraDistance = 64,	-- how far away the player is from the top left corner of the camera when jumping offscreen (the player is put out of camera view while jumping)
}

--[[ 
	jumpSmall: animation frames when launching upwards while being small
	fallSmall: animation frames when launching downwards while being small
	jumpBig: animation frames when launching upwards while being big (p.powerup > 1)
	fallBig: animation frames when launching downwards while being big
	
	the respective framespeeds are only necessary if there's more than one frame given and acts as the framespeed of the given animation part
	
	index 0: default data if the player is not registered on their own
--]]
backgroundLauncher.jumpFrames = {
	[0] = {jumpSmall = {3}, 	jumpSmallFrameSpeed = 8, 	fallSmall = {3},	fallSmallFrameSpeed = 8,
						 jumpBig = {4}, 		jumpBigFrameSpeed = 8, 		fallBig = {5}, 	fallBigFrameSpeed = 8
						},
	[CHARACTER_MARIO] = {jumpSmall = {3}, 	jumpSmallFrameSpeed = 8, 	fallSmall = {3},	fallSmallFrameSpeed = 8,
						 jumpBig = {4}, 		jumpBigFrameSpeed = 8, 		fallBig = {5}, 	fallBigFrameSpeed = 8
						},
						
}

local npcIDs = {}
local npcManager = require("npcManager")
local backgroundAreas = require("backgroundAreas")
local easing = require("ext/easing")

local tintShader = Shader()
tintShader:compileFromFile(nil, Misc.resolveFile(backgroundAreas.tintShaderPath))


function backgroundLauncher.onInitAPI()
	registerEvent(backgroundLauncher,"onTick")
	registerEvent(backgroundLauncher,"onDraw")
end

function backgroundLauncher.register(id)
	npcManager.registerEvent(id, backgroundLauncher, "onTickNPC")
	npcIDs[id] = true
end

function backgroundLauncher.getLandingPoint(id)
	for _, bgo in ipairs(BGO.get()) do
		bgo.data._settings.landingID = bgo.data._settings.landingID or 0
		if bgo.data._settings.landingID == id then
			return bgo
		end
	end
	return nil
end

function backgroundLauncher.launchPlayerIntoBackground(p,x,y)
	p.data.backgroundAreas = p.data.backgroundAreas or {}
	local pdata = p.data.backgroundAreas
	--pdata = pdata or {}
	
	pdata.launchTo = vector(x - p.width * 0.5,y - p.height)
	pdata.startAt = vector(p.x,p.y)
	pdata.drawX = pdata.startAt.x
	pdata.drawY = pdata.startAt.y
	--pdata.tintColor = Color.white .. 1
	pdata.startBgo = backgroundAreas.findSectionObjectByPos(p.x,p.y,useCulling)
	pdata.scale = 1
	if pdata.startBgo then
		pdata.scale = pdata.startBgo.data._settings.scale
		pdata.color = pdata.startBgo.data._settings.color
	end
	
	pdata.launchTimer = 0
end

local function animatePlayer(p,prevY)
	--p:mem(0x118,FIELD_WORD)	-- animation timer
	
	if p.mount ~= MOUNT_NONE then return end	-- don't animate player when they are mounting something
	
	local pdata = p.data.backgroundAreas
	local data = backgroundLauncher.jumpFrames[p.character] or backgroundLauncher.jumpFrames[0]
	
	local jumpFrames, fallFrames, jumpFrameSpeed, fallFrameSpeed = data.jumpBig, data.fallBig, data.jumpBigFrameSpeed, data.fallBigFrameSpeed
	if p.powerup == 1 then
		jumpFrames, fallFrames, jumpFrameSpeed, fallFrameSpeed = data.jumpSmall, data.fallSmall, data.jumpSmallFrameSpeed, data.fallSmallFrameSpeed
	end
	
	local useFrames = jumpFrames	-- useFrames set to jumpFrames if going upwards, fallFrames if going downwards
	if prevY < pdata.drawY then
		useFrames = fallFrames
	end
	
	local i = 0	-- animation frame
	if table.maxn(useFrames) > 1 then
		if p:mem(0x118,FIELD_WORD) < table.maxn(useFrames) * jumpFrameSpeed then
			p:mem(0x118,FIELD_WORD, p:mem(0x118,FIELD_WORD) + 1)	-- count up animationTimer
		else
			p:mem(0x118,FIELD_WORD,0)	-- reset animationTimer
		end
		i = math.floor(p:mem(0x118,FIELD_WORD) / jumpFrameSpeed)	-- animationTimer would be between 3 * jumpFrameSpeed and 3.999 * jumpFrameSpeed etc for frame 3
	end

	p:setFrame(useFrames[i + 1])	-- set the current frame
end

local function restrictPlayerInput(p)
	-- make player invulnerable to everything and unable to do anything
	p.keys.left = false
	p.keys.right = false
	p.keys.up = false
	p.keys.down = false
	p.keys.run = false
	p.keys.altRun = false
	p.keys.altJump = false
	p.keys.jump = false
	
	p.speedX = -Defines.player_grav
	p.speedY = 0
	p.noblockcollision = true
	p.nonpcinteraction = true
	p.invincibilityTimer = 1
	--p.slashTimer = 2
	p.warpCooldown = 2
	p.mountingCooldown = 2
	p.tanookiStatueCooldown = 2
	p.slidingOnSlope = false
	p.isDucking = false
	p.isSpinJumping = false
	p.isTanookiStatue = false
	p.rainbowShellSurfing = false
	
	p:mem(0x00,FIELD_BOOL,false)	-- no double jump for Toad
	p:mem(0x0C,FIELD_BOOL,false)	-- no fairy
	p:mem(0x18,FIELD_BOOL,false)	-- no hover for Peach
	--p:mem(0x62,FIELD_WORD,2)		-- can't let go of held npcs
	p:mem(0x11C,FIELD_WORD,0)		-- no jumping momentum
	p:mem(0x142,FIELD_BOOL,true)	-- don't flicker despite having I frames
	p:mem(0x162,FIELD_WORD,2)		-- link projectile cooldown
	
end

function backgroundLauncher.onTickNPC(v)

	--Don't act during time freeze
	if Defines.levelFreeze or not NPC.config[v.id].actAsLauncherPlatform then return end
	
	local data = v.data
	local settings = data._settings
	local config = NPC.config[v.id]
	
	--If despawned
	if v.despawnTimer <= 0 then
		--Reset our properties, if necessary
		data.backgroundLauncherInitialized = false
		return
	end

	--Initialize
	if not data.backgroundLauncherInitialized then
		--Initialize necessary data.
		settings.landingID = settings.landingID or 0
		
		data.landingPoint = backgroundLauncher.getLandingPoint(settings.landingID)
		
		if not data.landingPoint then
			Misc.warn("Couldn't find landingPoint bgo with the ID " .. settings.id,1)	-- you are not intended to lie to the launcher
			return
		end
		
		data.idleAnimationTimer = 0
		data.backgroundLauncherInitialized = true
	end
	
	for _,p in ipairs(Player.getIntersecting(v.x, v.y - backgroundLauncher.launchHitboxHeight, v.x + v.width, v.y)) do
		if p.keys.up and p.keys.jump == KEYS_PRESSED then
			backgroundLauncher.launchPlayerIntoBackground(p,data.landingPoint.x + data.landingPoint.width * 0.5, data.landingPoint.y + data.landingPoint.height)
			v.animationFrame = config.idleframes
			v.animationTimer = 0
			SFX.play(config.launchSFX)
		end
	end
	
	if v.animationFrame < config.idleframes then
		v.animationTimer = 0
		
		if data.idleAnimationTimer >= config.idleframespeed then		-- handle animation when not launching
			data.idleAnimationTimer = 0
			v.animationFrame = (v.animationFrame + 1) % config.idleframes
		else
			data.idleAnimationTimer = data.idleAnimationTimer + 1
		end
	else
		v.animationTimer = 0
		if data.idleAnimationTimer >= config.framespeed then		-- handle animation when launching. Custom behaviour necessary for right facing sprites
			data.idleAnimationTimer = 0
			v.animationFrame = (v.animationFrame + 1) % config.frames
		else
			data.idleAnimationTimer = data.idleAnimationTimer + 1
		end
	end

end

function backgroundLauncher.onTick()

	for _,p in ipairs(Player.get()) do
		local pdata = p.data.backgroundAreas
			
		if pdata and pdata.launchTo and pdata.launchTimer then
			restrictPlayerInput(p)	-- make player invulnerable and unable to do anything while in the jump transition
			
			local startX, startY = backgroundAreas.calculateScreenPos(pdata.startAt.x,pdata.startAt.y,true)
			
			local startScale = 1
			local startRotation = 0
			local startTint
			local startPriority = -25
			if pdata.startBgo then
				local settings = pdata.startBgo.data._settings
				startScale = settings.scale
				startRotation = settings.rotation
				startTint = settings.color
				startPriority = settings.drawPriority
			end
			
			local goalX, goalY = backgroundAreas.calculateScreenPos(pdata.launchTo.x,pdata.launchTo.y,true)
			local goalBgo = backgroundAreas.findSectionObjectByPos(pdata.launchTo.x,pdata.launchTo.y,false)
			
			local goalScale = 1
			local goalRotation = 0
			local goalTint = Color.white .. 1
			local goalPriority = -25
			if goalBgo then
				--Misc.dialog(goalBgo.data._settings)
				local settings = goalBgo.data._settings
				goalScale = settings.scale
				goalRotation = settings.rotation
				goalTint = settings.color
				if not startTint then
					startTint = settings.color
				end
				goalPriority = settings.drawPriority
			end
			if not startTint then
				startTint = Color.white .. 1
			end
			
			local duration = math.max(1,backgroundLauncher.launchSpeedZ * math.abs(startScale - goalScale) + backgroundLauncher.launchSpeedXY * math.abs(math.sqrt((goalX - startX)^2 + (goalY - startY)^2)) / 32)
			
			
			p.direction = math.sign(goalX - startX)	-- make player face in the direction they are moving
		
			local prevX = pdata.drawX
			local prevY = pdata.drawY
			pdata.drawX = easing.linear(pdata.launchTimer, startX,goalX - startX, duration) + p.width * 0.5 * pdata.scale

			local dx, dy = goalX - startX, goalY - startY
			local grav = Defines.player_grav
			if grav == 0 then
				grav = 0.0001
			end
			local a = - dy / (grav * duration) + 0.5 * duration
			local posYTimer = (pdata.launchTimer)
			pdata.drawY =  startY + ((posYTimer - a)^2 - a^2) * grav * 0.5 + p.height * 0.5 * pdata.scale
			
			pdata.scale = easing.linear(pdata.launchTimer, startScale,goalScale - startScale, duration)
			pdata.rotation = easing.linear(pdata.launchTimer, startRotation, goalRotation - startRotation, duration)
			pdata.priority = easing.linear(pdata.launchTimer, startPriority, goalPriority - startPriority, duration)
			pdata.color = easing.linear(pdata.launchTimer, startTint, goalTint - startTint, duration)
			--Text.print("!",pdata.drawX - camera.x,pdata.drawY - camera.y)
			
			pdata.camX = easing.outQuad(pdata.launchTimer, startX, goalX - startX, duration) + p.width * 0.5 * pdata.scale
			pdata.camY = easing.outQuad(pdata.launchTimer, startY, goalY - startY, duration) + p.height * pdata.scale
			
			animatePlayer(p,prevY)	-- sets the player frame depending on backgroundLauncher.jumpFrames
			
			if pdata.launchTimer >= duration then
				p.x = pdata.launchTo.x
				p.y = pdata.launchTo.y
				p.speedX = (pdata.drawX - prevX) / pdata.scale * 0.9
				p.speedY = (pdata.drawY - prevY) / pdata.scale * 0.9
				
				p.noblockcollision = false
				p.nonpcinteraction = false
				
				pdata.launchTo = nil
			else
				p.x = camera.x - backgroundLauncher.cameraDistance
				p.y = camera.y - backgroundLauncher.cameraDistance
				pdata.launchTimer = pdata.launchTimer + 1
				--pdata.camX = pdata.drawX
				--pdata.camY = pdata.drawY
		
				--backgroundAreas.setCameraPosition(camera,x,y,p.sectionObj,bgo)
			end
		end
	end
end

function backgroundLauncher.onDraw()
	for _,p in ipairs(Player.get()) do
		local pdata = p.data.backgroundAreas
		
		if pdata and pdata.launchTo and pdata.launchTimer then
			pdata.playerBuffer = pdata.playerBuffer or Graphics.CaptureBuffer(400,150)
			pdata.playerBuffer:clear(-100)
			
			-- Normal rendering
			local topLeftX = (pdata.playerBuffer.width  - p.width) * 0.5
			local topLeftY = (pdata.playerBuffer.height - p.height) * 0.5
		
			p:render{
				target = pdata.playerBuffer,
				drawPlayer = false,
				sceneCoords = false,
				priority = pdata.priority,
				ignorestate = (p.forcedState == 73), -- noclip cheat fix
				x = topLeftX,
				y = topLeftY,
			}
			
			p:setFrame(-50)
			
			Graphics.drawBox{
					texture = pdata.playerBuffer,
					x = pdata.drawX,
					y = pdata.drawY,
					centered = true,
					sceneCoords = true,
					width = pdata.playerBuffer.width * pdata.scale,
					height = pdata.playerBuffer.height * pdata.scale,
					rotation = pdata.rotation,
					priority = pdata.priority,
					color = Color.white .. 1,
					shader       = (pdata.scale < 1 and tintShader) or nil,
					uniforms     = (pdata.scale < 1 and {tintColor = pdata.color .. 1, tintAlpha = (1 - pdata.scale) * pdata.color.a}) or nil,
				}
			
			
		end
	end
end

return backgroundLauncher