--[[
	backgroundAreas.lua v1.0 by "Master" of Disaster
	
	See this part in the background? I wonder if you can get there...
	
	requires customCamera.lua
	custom NPCs etc that are drawn via lua only show up in the background if they have a registered draw function for customCamera.lua
	
--]]

local backgroundAreas = {
	bgoID = 997,				-- the id of the background positioner
	blockID = 995,				-- the id of the background area
	tintShaderPath = "AI/shaders/tint.frag",
}

local customCamera = require("customCamera")

local tintShader = Shader()
tintShader:compileFromFile(nil, Misc.resolveFile(backgroundAreas.tintShaderPath))


local function initializeExtraSettings(bgo)
	-- initializes the extra settings for the background positioner.
	-- Returns true if successful, returns false if the backgroundArea of the given id couldn't be found
	local settings = bgo.data._settings
	
	settings.id = settings.id or 0
	
	bgo.data.backgroundAreaBlock = bgo.data.backgroundAreaBlock or backgroundAreas.findBackgroundArea(settings.id)
	
	if not bgo.data.backgroundAreaBlock then
		Misc.warn("Couldn't find backgroundArea sizable with the ID " .. settings.id,1)	-- you are not intended to lie to the bgo
		return false
	end
	
	local settings2 = bgo.data.backgroundAreaBlock.data._settings
	
	settings.scale = settings2.scale or 1
	settings.drawPriority = settings2.drawPriority or -95
	
	settings.x = settings.x or bgo.data.backgroundAreaBlock.x
	settings.y = settings.y or bgo.data.backgroundAreaBlock.y
	settings.width = settings.width or bgo.data.backgroundAreaBlock.width
	settings.height = settings.height or bgo.data.backgroundAreaBlock.height
	
	settings.rotation = settings.rotation or settings2.rotation or 0
	settings.color = settings.color or settings2.color or Color.white .. 1
	
	settings.leftMargin = settings.leftMargin or settings2.leftMargin or 120
	settings.rightMargin = settings.rightMargin or settings2.rightMargin or 120
	settings.topMargin = settings.topMargin or settings2.topMargin or 120
	settings.bottomMargin = settings.bottomMargin or settings2.bottomMargin or 0
	
	settings.anchor = settings.anchor or 0
	
	return true
end


local function initializeAnchorPoints(bgo)
	-- returns the x and y coordinates the background area will be drawn at depending on settings.anchor.
	-- will also return camDistanceX, camDistanceY based on where the anchor is
	
	local settings = bgo.data._settings
	
	
	-- baseline case: center (settings.anchor = 0)
	local camDistanceX = (bgo.x + bgo.width * 0.5) - (camera.x + camera.width * 0.5)
	local camDistanceY = (bgo.y + bgo.height * 0.5) - (camera.y + camera.height * 0.5)
	
	local x = (bgo.width * 0.5)		-- default x
	local y = (bgo.height * 0.5)	-- and y
	
	local anchor = settings.anchor
	
	local topExtra = (settings.height * settings.scale * 0.5) - bgo.height * 0.5	-- add for top, subtract for bottom
	local leftExtra = (settings.width * settings.scale * 0.5) - bgo.width * 0.5		-- add for left, subtract for right
	
	local leftCamExtra = camera.width * 0.5 - bgo.width * 0.5
	local topCamExtra = camera.height * 0.5 - bgo.height * 0.5
	
	if 	   anchor == 1 then	-- top center
		y = y + topExtra
		camDistanceY = camDistanceY + topCamExtra
	elseif anchor == 2 then	-- bottom center
		y = y - topExtra
		camDistanceY = camDistanceY - topCamExtra
	elseif anchor == 3 then	-- left center
		x = x + leftExtra
		camDistanceX = camDistanceX + leftCamExtra
	elseif anchor == 4 then	-- right center
		x = x - leftExtra
		camDistanceX = camDistanceX - leftCamExtra
	elseif anchor == 5 then	-- top left
		x = x + leftExtra
		y = y + topExtra
		camDistanceX = camDistanceX + leftCamExtra
		camDistanceY = camDistanceY + topCamExtra
	elseif anchor == 6 then	-- bottom left
		x = x + leftExtra
		y = y - topExtra
		camDistanceX = camDistanceX + leftCamExtra
		camDistanceY = camDistanceY - topCamExtra
	elseif anchor == 7 then	-- top right
		x = x - leftExtra
		y = y + topExtra
		camDistanceX = camDistanceX - leftCamExtra
		camDistanceY = camDistanceY + topCamExtra
	elseif anchor == 8 then	-- bottom right
		x = x - leftExtra
		y = y - topExtra
		camDistanceX = camDistanceX - leftCamExtra
		camDistanceY = camDistanceY - topCamExtra
	end
	
	
	return x,y, camDistanceX, camDistanceY

end


function backgroundAreas.findBackgroundArea(id)
	-- returns the background area sizable of the given id. 
	-- returns nil if it doesn't exist
	for _,b in ipairs(Block.get(backgroundAreas.blockID)) do
		b.data._settings.id = b.data._settings.id or 0
		if b.data._settings.id == id then
			return b
		end
	end
	
	return nil
end


function backgroundAreas.findSectionObjectByPos(x,y,useCulling)
	-- returns the bgo object that draws the background section the position is located in
	-- returns nil if the section is now drawn or the player is not in a bgo section

	for _, bgo in ipairs(BGO.get(backgroundAreas.bgoID)) do
		
		
		local success = initializeExtraSettings(bgo)
		
		if success then
			
			local settings = bgo.data._settings
			
			if not bgo.data.camDistanceX then
				bgo.data.drawX, bgo.data.drawY,bgo.data.camDistanceX, bgo.data.camDistanceY = initializeAnchorPoints(bgo)
			end
			
			local cullDistanceX = math.abs((bgo.x + bgo.data.drawX) + bgo.data.camDistanceX * (settings.scale - 1) - (camera.x + camera.width * 0.5)) - settings.width * 0.5 * settings.scale
			local cullDistanceY = math.abs((bgo.y + bgo.data.drawY) + bgo.data.camDistanceY * (settings.scale - 1) - (camera.y + camera.height * 0.5)) - settings.height * 0.5 * settings.scale
				
			if ((cullDistanceX <= camera.width * 0.5) and (cullDistanceY <= camera.height * 0.5) or not useCulling) and not bgo.isHidden then		-- not culled
				if (x >= settings.x and x <= settings.x + settings.width and y >= settings.y and y <= settings.y + settings.height) then	-- position fits
					return bgo
				end
			end
			
		end
	end
	return nil
end


function backgroundAreas.calculateScreenPos(x,y,sceneCoords)
	-- calculates the onscreen position of the given coordinates. 
	-- If sceneCoords is true, they will be returned as positions on the scene instead of on the camera.
	-- returns the normal x,y coordinates if the player is not in a drawn bgo section
	
	local bgo = backgroundAreas.findSectionObjectByPos(x,y)
	local newX, newY = x,y
	
	if (bgo) then
		local settings = bgo.data._settings
		
		local distanceMiddleX, distanceMiddleY = newX - (settings.x + settings.width * 0.5), newY - (settings.y +  settings.height * 0.5)
		
		if not bgo.data.camDistanceX then
			bgo.data.drawX, bgo.data.drawY,bgo.data.camDistanceX, bgo.data.camDistanceY = initializeAnchorPoints(bgo)
		end
		
		
		newX = bgo.x + bgo.data.drawX + distanceMiddleX * settings.scale + bgo.data.camDistanceX * (settings.scale - 1)
		newY = bgo.y + bgo.data.drawY + distanceMiddleY * settings.scale + bgo.data.camDistanceY * (settings.scale - 1)
	end
	
	if not sceneCoords then
		newX, newY = newX - camera.x, newY - camera.y
	end
		
	return newX, newY
end

function backgroundAreas.calculateCameraPosition(cam, xPos, yPos, p, bgo, bypassMargins)
	-- returns the position of the camera that would focus on the x and y position. If bgo is given, it calculates the camera position with the backgroundArea in mind.
	-- bypassMargins means that it ignores the edge of backgroundAreas when calculating the camera position
	
	local section = p.sectionObj	-- section where the camera is located
	
	local returnX, returnY = 0,0
	
	local settings = {
		x = section.boundary.left, 
		y = section.boundary.top, 
		width = section.boundary.right - section.boundary.left,
		height = section.boundary.bottom - section.boundary.top, 
		leftMargin = 0, 
		rightMargin = 0, 
		topMargin = 0, 
		bottomMargin = 0,
	}
	if bgo and bgo.data._settings then
		local success = initializeExtraSettings(bgo)
		if not success then return end

		settings = bgo.data._settings
	end

	local leftEdge, topEdge = backgroundAreas.calculateScreenPos(settings.x,settings.y,true)
	local rightEdge, bottomEdge = backgroundAreas.calculateScreenPos(settings.x + settings.width, settings.y + settings.height,true)
	
	local newX, newY = xPos - cam.width * 0.5, yPos - cam.height * 0.5
	
	if bypassMargins then
		returnX = newX
		returnY = newY
	else
		returnX = math.clamp(newX, math.min(p.data.backgroundAreas.prevX, leftEdge - settings.leftMargin), math.max(p.data.backgroundAreas.prevX, rightEdge - cam.width + settings.rightMargin))
		returnY = math.clamp(newY, math.min(p.data.backgroundAreas.prevY, topEdge - settings.topMargin), math.max(p.data.backgroundAreas.prevY, bottomEdge - cam.height + settings.bottomMargin))
	end
	
	returnX = math.clamp(returnX, section.boundary.left, section.boundary.right - cam.width)
	returnY = math.clamp(returnY, section.boundary.top,  section.boundary.bottom - cam.height)
	
	return returnX, returnY
end

function backgroundAreas.setCameraPosition(cam,xPos,yPos,p,bgo,bypassMargins)
	
	cam.x, cam.y = backgroundAreas.calculateCameraPosition(cam,xPos,yPos,p,bgo,bypassMargins)
end

function backgroundAreas.onInitAPI()
	registerEvent(backgroundAreas,"onDraw")
	registerEvent(backgroundAreas,"onCameraUpdate")
end

function backgroundAreas.onCameraUpdate(camIdx)
	-- No multiplayer support as of now. It's possible but handling two cameras and deciding how and when to do that is painful and I don't wanna
	local p = player
	local bgo = backgroundAreas.findSectionObjectByPos(p.x + player.width * 0.5, p.y + p.height)
	if bgo or (p.data.backgroundAreas and p.data.backgroundAreas.camX and p.data.backgroundAreas.camY) then	-- only if the player is in a background section atm
		
		
		--if not success then return end
		
		if p.data.backgroundAreas and p.data.backgroundAreas.prevX and p.data.backgroundAreas.prevY then
			camera.x = p.data.backgroundAreas.prevX	-- act as if the camera was where it was just before entering the backgroundArea
			camera.y = p.data.backgroundAreas.prevY
		else
			p.data.backgroundAreas = p.data.backgroundAreas or {}
			p.data.backgroundAreas.prevX = camera.x
			p.data.backgroundAreas.prevY = camera.y
			
		end
		
		local bypassMargins = false	-- normally false, if true edgeMargins will be ignored
		local x,y = backgroundAreas.calculateScreenPos(p.x + p.width * 0.5,p.y + p.height,true)
		if p.data.backgroundAreas and p.data.backgroundAreas.camX and p.data.backgroundAreas.camY then
			x,y = p.data.backgroundAreas.camX, p.data.backgroundAreas.camY
			p.data.backgroundAreas.camX, p.data.backgroundAreas.camY = nil, nil
			bypassMargins = true	-- bypass edge margins so the camera doesn't get stuck on the edge of a background area when jumping from area to area
		end
		
		backgroundAreas.setCameraPosition(camera,x,y,p,bgo,bypassMargins)
		
	end
	p.data.backgroundAreas = p.data.backgroundAreas or {}
	p.data.backgroundAreas.prevX = camera.x
	p.data.backgroundAreas.prevY = camera.y	
end

function backgroundAreas.onDraw()
	
	for _, bgo in ipairs(BGO.get(backgroundAreas.bgoID)) do
		
		local success = initializeExtraSettings(bgo)
		
		if success then
		
			local data = bgo.data
			local settings = bgo.data._settings
			
			data.drawX, data.drawY,data.camDistanceX, data.camDistanceY = initializeAnchorPoints(bgo)
			
			local cullDistanceX = math.abs((bgo.x + data.drawX) + data.camDistanceX * (settings.scale - 1) - (camera.x + camera.width * 0.5)) - settings.width * 0.5 * settings.scale
			local cullDistanceY = math.abs((bgo.y + data.drawY) + data.camDistanceY * (settings.scale - 1) - (camera.y + camera.height * 0.5)) - settings.height * 0.5 * settings.scale

			
			if (cullDistanceX <= camera.width * 0.5) and (cullDistanceY <= camera.height * 0.5) and not bgo.isHidden then
			-- cull everything that's not on screen, and actually draw the rest
				
				
				data.backgroundBuffer = data.backgroundBuffer or Graphics.CaptureBuffer(settings.width * settings.scale,settings.height * settings.scale,true)
				data.backgroundBuffer:clear(-100)
			
				customCamera.drawScene{				-- draws the area that's in the background on data.backgroundBuffer, so it can be drawn whereever I want
					target = data.backgroundBuffer,
					useScreen = false,
					drawBackgroundToScreen = true,
					minPriority = -100,
					maxPriority = settings.drawPriority,
					scale = settings.scale,
					rotation = 0,
					x = settings.x,
					y = settings.y,
					width = settings.width,
					height = settings.height,
				}

				local colorValue = math.clamp(settings.scale,1,1)	-- the farther back, the more tinted it is
			
				Graphics.drawBox{		-- draws the capture buffer at the bgo's position with parallax imitation
					texture = data.backgroundBuffer,
					x = bgo.x + data.drawX + data.camDistanceX * (settings.scale - 1),
					y = bgo.y + data.drawY + data.camDistanceY * (settings.scale - 1),
					centered = true,
					sceneCoords = true,
					rotation = settings.rotation,
					priority = settings.drawPriority,
					color = Color.white .. 1,
					shader       = (settings.scale < 1 and tintShader) or nil,
					uniforms     = (settings.scale < 1 and {tintColor = settings.color .. 1, tintAlpha = (1 - settings.scale) * settings.color.a}) or nil,
				}
			
			end
		end
	end
end

return backgroundAreas