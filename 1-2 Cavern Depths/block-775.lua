
--[[
					Resizable Collectable Triggers by MrNameless
	An alternative version of the Collectable Trigger NPC that's a resizable semisolid.
			
	CREDITS:
	KBM-Quine - Inspiration/Base of the Re-triggering & NPC-Triggering feature, originally found in their event zones for a contest entry.

	Version 3.0.0
]]--


local blockManager = require("blockManager")
local utils = require("blocks/blockutils")
local resizeTrigger = {}

local blockID = BLOCK_ID

local triggerSettings = {
	id = blockID,
	frames = 1,
	framespeed = 8,
	--Identity-related flags:
	sizable = true, 
	passthrough = true,
	semisolid = false,
}

blockManager.setBlockSettings(triggerSettings)

function resizeTrigger.onInitAPI()
	--blockManager.registerEvent(blockID, resizeTrigger, "onCollideBlock") -- ditched this over other methods now.
	blockManager.registerEvent(blockID, resizeTrigger, "onTickEndBlock")
	blockManager.registerEvent(blockID, resizeTrigger, "onCameraDrawBlock")
	blockManager.registerEvent(blockID, resizeTrigger, "onDrawBlock")
end

function resizeTrigger.onTickEndBlock(v) -- the main meat & potatoes of the script.
	if v.isHidden or v:mem(0x5A, FIELD_BOOL) then return end
	local data = v.data

	data.isTouchingPlayer = false
	data.touchTable = {}

	if data._settings.talkMessage ~= "" and data._settings.talkMessage ~= nil then
		data.isFriendly = true
	else
		data.isFriendly = false
	end

	for _,p in ipairs(Player.getIntersecting(v.x,v.y,v.x+v.width,v.y+v.height))do
		if p.isValid and p.deathTimer == 0 then
			table.insert(data.touchTable, p)
		end
	end
	
	if not data.isFriendly and data._settings.npcTriggerable then
		for _,n in NPC.iterateIntersecting(v.x,v.y,v.x+v.width,v.y+v.height) do
			if n.isValid and not n.isHidden and n.despawnTimer > 0 then
				table.insert(data.touchTable, n)
			end
		end
	end

	--Text.print(#data.touchTable,100,100) -- debug purposes
	if #data.touchTable > 0 then
		for i = #data.touchTable,1,-1 do
			local n = data.touchTable[i];
			if type(n) == "Player" and data.isFriendly then
				data.isTouchingPlayer = true
				if n.keys.up == KEYS_PRESSED then
					Text.showMessageBox(data._settings.talkMessage)
					if data._settings.talkEvent ~= nil then triggerEvent(data._settings.talkEvent) end
				end
			elseif not data.isFriendly then
				if not data.isTouched then
					if data._settings.reTriggerable then triggerEvent(v:mem(0x10, FIELD_STRING)) end
					data.isTouched = true
				end
				if not data._settings.reTriggerable then
					v:remove(false)
					Misc.score(-50)
				end
			end	
		end
		
	else
		data.isTouched = false
	end

end

function resizeTrigger.onCameraDrawBlock(v, camIdx) -- handles "Activate" events
	if v.isHidden or v:mem(0x5A, FIELD_BOOL) then return end
	if v.data._settings.activateEvent == nil then return end
	local data = v.data
	if utils.visible(Camera(camIdx),v.x,v.y,v.width,v.height) and not data.didActivate then
		triggerEvent(data._settings.activateEvent)
		data.didActivate = true
	elseif data._settings.reActivatable and not utils.visible(Camera(camIdx),v.x,v.y,v.width,v.height) then
		data.didActivate = false
	end
end

function resizeTrigger.onDrawBlock(v) -- handles drawing the "!" mark when on a "friendly" trigger
	if v.isHidden or v:mem(0x5A, FIELD_BOOL) then return end
	if not v.data.isFriendly then return end
	if v.data.isTouchingPlayer then
		Graphics.draw{
			type = RTYPE_IMAGE,
			image = Graphics.sprites.hardcoded["43"].img,
			sceneCoords = true,				
			x = v.x + (v.width * 0.5) - 6,
			y = v.y - 30,
			priority = -40
		}
	end
end

return resizeTrigger