--[[

    respawnRooms.lua (v1.0)
    by MrDoubleA

    Editor sizeable graphic based on a graphic by Valentine

]]

local playerManager = require("playerManager")

local bettereffects = require("game/bettereffects")
local blockutils = require("blocks/blockutils")
local switchcolors = require("switchcolors")
local lineguide = require("lineguide")

local montymolehole = require("npcs/ai/montymolehole")
local megashroom = require("npcs/ai/megashroom")
local starman = require("npcs/ai/starman")
local switch = require("blocks/ai/synced")

local easing = require("ext/easing")
local handycam = require("handycam")

local blockEventManager = require("game/blockEventManager")
local npcEventManager = require("game/npcEventManager")

local respawnRooms = {}


local customCamera
pcall(function() customCamera = require("customCamera") end)

local spawnzones
pcall(function() spawnzones = require("spawnzones") end)


-- A bunch of memory addresses
local SIZEABLE_LIST_ADDR = mem(0xB2BED8,FIELD_DWORD)
local SIZEABLE_COUNT_ADDR = 0xB2BEE4

local BLOCKS_SORTED = 0xB2C894
local BLOCK_LOOKUP_MIN = mem(0xB25758,FIELD_DWORD)
local BLOCK_LOOKUP_MAX = mem(0xB25774,FIELD_DWORD)
local BLOCK_LOOKUP_LIMIT = 8000

local HIT_BLOCK_COUNT = 0xB25784

local BGO_BASE_COUNT_ADDR = 0x00B25958 -- BGO count, without lock BGO's
local BGO_LOCK_COUNT_ADDR = 0x00B250D6 -- number of lock BGO's

local PSWITCH_TIMER_ADDR = 0x00B2C62C
local STOPWATCH_TIMER_ADDR = 0x00B2C62E

local CONVEYER_DIRECTION = 0xB2C66C
local LEVEL_END_TIMER = 0xB2C5A0

local QUEUED_EVENT = mem(0xB2D6E8,FIELD_DWORD)
local QUEUED_EVENT_DELAY = mem(0xB2D704,FIELD_DWORD)
local QUEUED_EVENT_COUNT = 0xB2D710

local EVENTS_ADDR = mem(0x00B2C6CC,FIELD_DWORD)
local EVENTS_STRUCT_SIZE = 0x588

local MAX_EVENTS = 255

local STAR_LIST_ADDR = mem(0xB25714,FIELD_DWORD)
local STAR_COUNT_ADDR = 0xB251E0

local function addScore(amount)
    local current = Misc.score()
    local newScore = math.max(0, current + amount)
    Misc.score(newScore - current)
end

-- Reset handling
do
    respawnRooms.levelData = nil
    respawnRooms.levelDataBlocks = nil
    respawnRooms.levelDataBlockCount = 0

    respawnRooms.pSwitchEffectActive = false
    respawnRooms.colorSwitchStates = {}
    respawnRooms.montyMoleHoleIDs = {}
    respawnRooms.lockedBGOCounter = 0


    local blockIsSlippery = {}

    local persistentNPCData = {}

    function respawnRooms.getPersistentNPCData(v)
        local originalIdx = v.data._respawnRoomsOriginalIdx

        return persistentNPCData[originalIdx]
    end



    local function sortBlockData(a,b)
        if a.x ~= b.x then
            return (a.x < b.x)
        elseif a.y ~= b.y then
            return (a.y < b.y)
        else
            local idxA = a.meta.index
            local idxB = b.meta.index

            return (idxA < idxB)
        end
    end


    local layerHiddenCache = {}

    local function layerIsHidden(name)
        local isHidden = layerHiddenCache[name]
    
        if isHidden == nil then
            local layer = Layer.get(name)
            if layer ~= nil then
                isHidden = layer.isHidden
            else
                isHidden = false
            end
    
            layerHiddenCache[name] = isHidden
        end
    
        return isHidden
    end


    local function createBlockLookup()
        -- Based on this: https://github.com/smbx/smbx-legacy-source/blob/master/modSorting.bas#L118
        -- Kinda slow, but it shouldn't be a big deal

        -- Find the minimum indices for each position
        local currentBlockIdx = 1

        for i = -BLOCK_LOOKUP_LIMIT,BLOCK_LOOKUP_LIMIT do
            for blockIdx = currentBlockIdx,Block.count() do
                local b = Block(blockIdx)

                if b.isValid and (b.x + b.width) >= (i*32) then
                    currentBlockIdx = blockIdx
                    break
                end
            end

            mem(BLOCK_LOOKUP_MIN + (i + BLOCK_LOOKUP_LIMIT)*2,FIELD_WORD,currentBlockIdx)
        end

        -- Find the maximum indices for each position
        currentBlockIdx = Block.count()

        for i = BLOCK_LOOKUP_LIMIT,-BLOCK_LOOKUP_LIMIT,-1 do
            for blockIdx = currentBlockIdx,1,-1 do
                local b = Block(blockIdx)

                if b.isValid and b.x <= (i*32) then
                    currentBlockIdx = blockIdx
                    break
                end
            end

            mem(BLOCK_LOOKUP_MAX + (i + BLOCK_LOOKUP_LIMIT)*2,FIELD_WORD,currentBlockIdx)
        end

        -- Set the sorted flag accordingly
        mem(BLOCKS_SORTED,FIELD_BOOL,true)
    end


    local function sortSizeables(a,b)
        if a.y ~= b.y then
            return (a.y < b.y)
        else
            return (a.idx < b.idx)
        end
    end

    local function createSizeablesList()
        -- Gather up all the sizeables
        local sizeableCount = 0
        local sizeables = {}

        for _,b in Block.iterateByFilterMap(Block.SIZEABLE_MAP) do
            sizeableCount = sizeableCount + 1
            table.insert(sizeables,b)
        end

        -- Sort them based on Y position
        -- Higher up blocks are earlier so that they get lower render priority
        table.sort(sizeables,sortSizeables)

        -- Write them into the sizeable array
        for i,b in ipairs(sizeables) do
            mem(SIZEABLE_LIST_ADDR + (i - 1)*2,FIELD_WORD,b.idx)
        end
        
        mem(SIZEABLE_COUNT_ADDR,FIELD_WORD,sizeableCount)
    end


    local function convertExtraSettingsValue(defaultValue,newValue)
        local defaultType = type(defaultValue)
        
        if defaultType == "Color" then
            -- Convert to color
            return Color.parse(newValue)
        end
        
        if defaultType == "Vector2" then
            -- Convert to vector
            return vector(newValue.x,newValue.y)
        end
        
        if defaultType == "table" then
            -- Convert to rect
            if defaultValue.left ~= nil and defaultValue.right ~= nil and defaultValue.top ~= nil and defaultValue.bottom ~= nil then
                return {left = newValue.x,top = newValue.y,right = newValue.x + newValue.w,bottom = newValue.y + newValue.h}
            end
        end

        return newValue
    end

    local function writeExtraSettingsTable(settings,newSettings)
        if newSettings == nil or settings == nil then
            return
        end

        for key,defaultValue in pairs(settings) do
            local newValue = newSettings[key]

            if newValue ~= nil then    
                -- Some extra settings values are in a different format, so we need to convert those
                settings[key] = convertExtraSettingsValue(defaultValue,newValue)
            end
        end
    end

    local function handleExtraSettings(settings,newSettings)
        writeExtraSettingsTable(settings,newSettings["local"])
        writeExtraSettingsTable(settings._global,newSettings["global"])
    end


    local function npcCantBeReset(v)
        if not respawnRooms.resetSettings.resetHeldNPC then
            -- Being held
            if player.holdingNPC == v then
                return true
            end

            -- On Yoshi's tongue/in Yoshi's mouth
            if player:mem(0xB8,FIELD_WORD) == (v.idx + 1) then
                return true
            end
        end

        return false
    end

    local function getNPCSection(x,y,width,height)
        -- Is this in section bounds? If so, use it
        for idx = 0,20 do
            local b = Section(idx).boundary

            if x <= b.right and y <= b.bottom and x+width >= b.left and y+height >= b.top then
                return idx
            end
        end

        -- If not, find the closest section
        local closestDistance = math.huge
        local closestSection = 0

        for idx = 0,20 do
            local b = Section(idx).boundary

            local distLeft = math.abs(b.left - (x + width))
            local distRight = math.abs(b.right - (x))
            local distTop = math.abs(b.top - (y + height))
            local distBottom = math.abs(b.bottom - (y))

            local dist = math.min(distLeft,distRight,distTop,distBottom)

            if dist < closestDistance then
                closestDistance = dist
                closestSection = idx
            end
        end

        return closestSection
    end


    local function clearLevel()
        -- Clear out blocks
        -- Done backwards for weird sorting reasons
        for i = Block.count(), 1, -1 do
            Block(i):delete()

            if i <= respawnRooms.levelDataBlockCount then
                EventManager.callEvent("onBlockInvalidateForReuseInternal",i)
            end
        end

        mem(HIT_BLOCK_COUNT,FIELD_WORD,0) -- blocks in the hit animation

        -- Clear out NPC's (they're weird)
        for _,v in NPC.iterate() do
            if not npcCantBeReset(v) then
                if not v.isGenerator then
                    -- Run onRemove if possible
                    local data = respawnRooms.npcIDData[v.id]

                    if data ~= nil and data.onRemove ~= nil then
                        data.onRemove(v)
                    end

                    -- Rather complicated setup to run onNPCKill
                    local eventObj = {cancelled = false}

                    EventManager.callEvent("onNPCKill",eventObj,v.idx+1,HARM_TYPE_VANISH)
                    
                    if eventObj.cancelled then -- Make sure onPostNPCKill always runs
                        EventManager.callEvent("onPostNPCKill",v,HARM_TYPE_VANISH)
                    end
                end

                -- Get it out of here
                local b = v.sectionObj.boundary

                v.x = b.left - 1024
                v.y = b.top - 1024

                -- Despawn it
                v:mem(0x124,FIELD_BOOL,false)
                v.despawnTimer = -1

                -- Set stuff up so that nothing really happens when it dies
                v.deathEventName = ""
                v.isGenerator = false
                v.id = 58
                
                v.animationFrame = -999

                v:kill(HARM_TYPE_VANISH)
            end
        end

        -- Effects
        for _,v in ipairs(bettereffects.getEffectSpawners()) do
            v:kill()
        end

        for _,v in ipairs(bettereffects.getEffectObjects()) do
            v:kill()
        end

        for _,v in ipairs(Effect.get()) do
            v.animationFrame = -999
            v.timer = 0
            v.x = 0
            v.y = 0
        end


        respawnRooms.lockedBGOCounter = 0
    end


    local blockPSwitchCoinIDs = {
        [89] = 33,
        [188] = 88,[60] = 88,
        [280] = 103,
        [293] = 138,

        other = 10,
    }
    local npcPSwitchBlockIDs = {
        [33] = 89,[258] = 89,
        [88] = 188,
        [103] = 280,
        [138] = 293,

        other = 4,
    }

    local colorSwitchSwapIDs = {
        [171] = {172,switchcolors.colors.yellow},
        [172] = {171,switchcolors.colors.yellow},
        [174] = {175,switchcolors.colors.blue},
        [175] = {174,switchcolors.colors.blue},
        [177] = {178,switchcolors.colors.green},
        [178] = {177,switchcolors.colors.green},
        [180] = {181,switchcolors.colors.red},
        [181] = {180,switchcolors.colors.red},
    }
    local palaceSwitchSwapIDs = {
        [724] = {725,"yellow"},
        [725] = {724,"yellow"},
        [726] = {727,"blue"},
        [727] = {726,"blue"},
        [728] = {729,"green"},
        [729] = {728,"green"},
        [730] = {731,"red"},
        [731] = {730,"red"},
    }

    local function spawnBlock(blockData,idx)
        if idx > respawnRooms.levelDataBlockCount or idx > Block.count() then
            return
        end

        local config = Block.config[blockData.id]

        local layerName = blockData.layer
        local isHidden = layerIsHidden(layerName)


        if respawnRooms.pSwitchEffectActive and config ~= nil and config.pswitchable and not isHidden then
            -- If this is a brick and a P-switch is active, spawn a coin instead
            local npcID = blockPSwitchCoinIDs[blockData.id] or blockPSwitchCoinIDs.other
            local npcConfig = NPC.config[npcID]

            local v = NPC.spawn(npcID,blockData.x + blockData.w*0.5 - npcConfig.width*0.5,blockData.y,nil,true,false)

            v.direction = DIR_LEFT
            v.spawnDirection = v.direction

            v.layerName = layerName
            v.isHidden = isHidden

            v.deathEventName = blockData.eventDestroy
            v.noMoreObjInLayer = blockData.eventEmptyLayer

            v:mem(0x14E,FIELD_WORD,blockData.id) -- P-switch brick ID

            return
        end


        local v = Block(idx)
        
        v.id = blockData.id

        v.x = blockData.x
        v.y = blockData.y

        v.width = blockData.w
        v.height = blockData.h

        v.layerName = layerName
        v.isHidden = isHidden

        if blockData.npcId < 0 then -- coins
            v.contentID = -blockData.npcId
        elseif blockData.npcId > 0 then -- NPC
            v.contentID = 1000 + blockData.npcId
        end

        v:mem(0x5A,FIELD_BOOL,blockData.invisible) -- editor invisible flag
        v.slippery = blockIsSlippery[idx] -- stored weird

        v:mem(0x0C,FIELD_STRING,blockData.eventHit) -- hit event name
        v:mem(0x10,FIELD_STRING,blockData.eventDestroy) -- destroy event name
        v:mem(0x14,FIELD_STRING,blockData.eventEmptyLayer) -- no more objects in layer event name

        -- Special case for spawnzones
        if spawnzones ~= nil and v.id == spawnzones.block then
            v.isHidden = true
        end

        -- Reset a ton of boring properties
        -- Based on ffi_block.lua
        v:mem(0x02,FIELD_WORD,0) -- battle mode respawn timer
        v:mem(0x04,FIELD_WORD,0) -- hit counter
        v:mem(0x06,FIELD_WORD,v.id) -- spawn ID
        v:mem(0x08,FIELD_WORD,v.contentID) -- spawn contentID
        v:mem(0x0A,FIELD_WORD,0) -- padding(?)
        v:mem(0x52,FIELD_WORD,0) -- bonk first half offset
        v:mem(0x54,FIELD_WORD,0) -- bonk latter half offset
        v:mem(0x56,FIELD_WORD,0) -- bonk visual offset
        v:mem(0x58,FIELD_BOOL,false) -- weird removal flag(?)
        v:mem(0x5C,FIELD_WORD,0) -- p-switch coin ID
        v:mem(0x5E,FIELD_WORD,0) -- player owner index
        v:mem(0x60,FIELD_WORD,0) -- NPC owner ID
        v:mem(0x62,FIELD_WORD,0) -- uhhhhhh. clown-car related
        v:mem(0x64,FIELD_WORD,0) -- uhhhhhh. collision bug fix?
        v:mem(0x66,FIELD_WORD,0) -- NPC owner index

        v.collisionGroup = ""
        v.extraSpeedX = 0
        v.extraSpeedY = 0

        -- Reset data table
        v.data = {_basegame = {},_settings = Block.makeDefaultSettings(v.id)}

        -- Swap for colour/palace switches
        local palaceData = palaceSwitchSwapIDs[v.id]
        local switchData = colorSwitchSwapIDs[v.id]

        if switchData ~= nil and respawnRooms.colorSwitchStates[switchData[2]] then
            v.id = switchData[1]
        elseif palaceData ~= nil and SaveData._basegame.bigSwitch[palaceData[2]] then
            v.id = palaceData[1]
        end

        -- Extra settings
        local settingsData = blockData.meta.data

        handleExtraSettings(v.data._settings,settingsData)
    end

    local function spawnNPC(npcData,idx)
        local generatorData = npcData.generator
        local eventData = npcData.event

        local config = NPC.config[npcData.id]

        local layerName = npcData.layer
        local isHidden = layerIsHidden(layerName)

        local data = respawnRooms.npcIDData[npcData.id]

        local section = getNPCSection(npcData.x,npcData.y,config.width,config.height)


        if data ~= nil and data.onPreSpawn ~= nil then
            if data.onPreSpawn(npcData,section,persistentNPCData[idx]) then
                return
            end
        end


        -- If the old NPC still exists, and can't be reset, don't spawn a duplicate
        local currentInstance = persistentNPCData[idx].currentInstance

        if currentInstance.isValid and npcCantBeReset(currentInstance) then
            return
        end


        if respawnRooms.pSwitchEffectActive and config.iscoin and not isHidden then
            -- If this is a coin and a P-switch is active, spawn a brick instead
            local blockID = npcPSwitchBlockIDs[npcData.id] or npcPSwitchBlockIDs.other
            local blockConfig = Block.config[blockID]

            local v = Block.spawn(blockID,npcData.x + config.width*0.5 - blockConfig.width*0.5,npcData.y)

            v.layerName = layerName
            v.isHidden = isHidden

            v:mem(0x10,FIELD_STRING,eventData.die) -- destroy event name
            v:mem(0x14,FIELD_STRING,eventData.emptyLayer) -- no more objects in layer event name

            v:mem(0x5C,FIELD_WORD,npcData.id) -- P-switch NPC ID

            return
        end


        local v = NPC.spawn(npcData.id,npcData.x,npcData.y,section,true,false)

        v.direction = npcData.direction
        v.spawnDirection = v.direction

        v.dontMove = npcData.noMove
        v.friendly = npcData.friendly
        v.legacyBoss = npcData.isBoss
        v.msg = npcData.msg

        v.layerName = layerName
        v.isHidden = isHidden
        v.attachedLayerName = npcData.attachLayer

        v.activateEventName = eventData.activate
        v.deathEventName = eventData.die
        v.talkEventName = eventData.talk
        v.noMoreObjInLayer = eventData.emptyLayer

        v.isGenerator = generatorData.enabled
        v.generatorType = generatorData.type
        v.generatorInterval = generatorData.period
        v.generatorDirection = generatorData.direction


        -- This is data that stays the same between each respawned version of the NPC.
        persistentNPCData[idx].currentInstance = v
        persistentNPCData[idx].originalIdx = idx

        v.data._respawnRoomsOriginalIdx = idx


        -- AI1/AI2 (hardcoded nonsense...)
        if config.isflying or config.iswaternpc or v.id == 260 then
            v.ai1 = npcData.specialData
        elseif v.id > 292 then
            v.ai1 = npcData.contents
            v.ai2 = npcData.specialData
        else
            if v.id == 91 or v.id == 96 or v.id == 283 or v.id == 284 then
                v.ai1 = npcData.contents
            end

            if v.id == 288 or v.id == 289 or (v.id == 91 and v.ai1 == 288) then
                v.ai2 = npcData.specialData
            end
        end

        v.spawnAi1 = v.ai1
        v.spawnAi2 = v.ai2


        -- Extra settings
        local settingsData = npcData.meta.data

        v.data._settings = NPC.makeDefaultSettings(v.id)
        handleExtraSettings(v.data._settings,settingsData)

        -- Setup lineguide data
        if lineguide.registeredNPCMap[v.id] then
            lineguide.onStartNPC(v)
        end

        -- Spawning
        v:mem(0x14C,FIELD_WORD,1)
        v.despawnTimer = 2

        if config.iswaternpc and v.ai1 == 2 then -- for jumping cheep cheeps, special spawn logic
            v:mem(0x124,FIELD_BOOL,false)
            v.despawnTimer = 0
        end

        -- Special code!
        if data ~= nil and data.onSpawn ~= nil then
            data.onSpawn(v)
        end
    end


    local function setupLockBGO(warp,id,x,y)
        local bgo = BGO(mem(BGO_BASE_COUNT_ADDR,FIELD_WORD) + respawnRooms.lockedBGOCounter)
        local config = BGO.config[id]

        bgo.id = id

        bgo.x = x
        bgo.y = y

        bgo.width = config.width
        bgo.height = config.height

        bgo.layerName = warp.layerName
        bgo.isHidden = layerIsHidden(bgo.layerName)

        respawnRooms.lockedBGOCounter = respawnRooms.lockedBGOCounter + 1
    end

    local function setupWarp(idx,warpData,entranceX,entranceY,entranceDirection,exitX,exitY,exitDirection)
        if idx >= Warp.count() then
            return
        end

        local v = Warp(idx)

        v.entranceX = entranceX
        v.entranceY = entranceY
        v.entranceWidth = 32
        v.entranceHeight = 32
        v.entranceSpeedX = 0
        v.entranceSpeedY = 0
        v.entranceDirection = entranceDirection

        v.exitX = exitX
        v.exitY = exitY
        v.exitWidth = 32
        v.exitHeight = 32
        v.exitSpeedX = 0
        v.exitSpeedY = 0
        v.exitDirection = exitDirection


        v.locked = warpData.locked
        v.allowItems = warpData.allowNPC
        v.noYoshi = warpData.noVehicles
        v.warpType = warpData.type

        v.levelFilename = warpData.dstLevel
        v.warpNumber = warpData.dstLevelWarpId

        v.worldMapX = warpData.dstWorldX
        v.worldMapY = warpData.dstWorldY

        v.toOtherLevel = (not warpData.isSetOut)
        v.fromOtherLevel = (not warpData.isSetIn)

        -- Seems like an oversight, but the level data does not actually include stars.
        -- Doesn't really matter though, we can just keep it as-is.
        --v.starsRequired = 0

        -- Reset lock BGO
        if v.warpType == 2 then
            if v.starsRequired > mem(STAR_COUNT_ADDR,FIELD_WORD) then
                setupLockBGO(v,160,v.entranceX + (v.entranceWidth - 24)*0.5,v.entranceY - 24)
            elseif v.locked then
                setupLockBGO(v,98,v.entranceX,v.entranceY)
            end
        end
    end


    local function resetSection(sectionData)
        local idx = sectionData.id

        if idx < 0 or idx > 20 then
            return
        end

        local v = Section(idx)

        -- Boundary
        local b = v.boundary

        b.left = sectionData.sizeLeft
        b.right = sectionData.sizeRight
        b.top = sectionData.sizeTop
        b.bottom = sectionData.sizeBottom

        v.origBoundary = b
        v.boundary = b

        -- Other properties
        if v.musicID ~= sectionData.musicId or v.musicPath ~= sectionData.musicFile then
            v.musicID = sectionData.musicId
            v.musicPath = sectionData.musicFile
        end

        v.backgroundID = sectionData.backgroundId

        v.hasOffscreenExit = sectionData.offScreenExit
        v.noTurnBack = sectionData.lockLeftScrool
        v.isUnderwater = sectionData.isUnderWater

        v.wrapH = sectionData.wrapH
        v.wrapV = sectionData.wrapV
    end

    local function resetLayers()
        -- Reset layer speeds and hidden status
        for _,layerData in ipairs(respawnRooms.levelData.layers) do
            local idx = layerData.meta.arrayId
            local layerObj = Layer(idx - 1)

            if layerObj.name == layerData.name then
                layerObj.isHidden = layerData.hidden
            end

            layerObj.pauseDuringEffect = false
            layerObj.speedX = 0
            layerObj.speedY = 0
        end

        -- Reset room positions
        for _,v in ipairs(respawnRooms.rooms) do
            v.x = v.spawnX
            v.y = v.spawnY
            v.speedX = 0
            v.speedY = 0
        end
    end

    local function resetEvents()
        -- Reset queued events
        mem(QUEUED_EVENT_COUNT,FIELD_WORD,0)
    
        -- Trigger autostart events
        for idx = 0,MAX_EVENTS-1 do
            local ptr = EVENTS_ADDR + idx*EVENTS_STRUCT_SIZE
            local name = mem(ptr + 0x04,FIELD_STRING)
            
            if name == "" then
                break
            end

            local isAutoStart = mem(ptr + 0x586,FIELD_BOOL)
            
            if name == "Level - Start" or isAutoStart then -- If it set to autostart or is the level start event, trigger
                triggerEvent(name)
            end
        end
    end


    local function addStuffFromLevel()
        -- Spawn any blocks
        for idx,blockData in ipairs(respawnRooms.levelDataBlocks) do
            spawnBlock(blockData,idx)
        end

        if Block.count() <= respawnRooms.levelDataBlockCount and not respawnRooms.pSwitchEffectActive then
            createBlockLookup()
        end

        createSizeablesList()

        -- Spawn NPC's
        for idx,npcData in ipairs(respawnRooms.levelData.npc) do
            spawnNPC(npcData,idx)
        end

        -- BGO's
        for i,bgoData in ipairs(respawnRooms.levelData.bgo) do
            if i <= BGO.count() then
                local v = BGO(i - 1)

                v.x = bgoData.x
                v.y = bgoData.y

                v.speedX = 0
                v.speedY = 0
                
                v.layerName = bgoData.layer
                v.isHidden = layerIsHidden(v.layerName)

                -- Reset data table
                local darknessData = v.data._basegame._darkness

                v.data = {_basegame = {_darkness = darknessData},_settings = BGO.makeDefaultSettings(v.id)}

                -- Extra settings
                local settingsData = bgoData.meta.data

                handleExtraSettings(v.data._settings,settingsData)
            end
        end

        -- Liquids
        for i,liquidData in ipairs(respawnRooms.levelData.physEnvZones) do
            local v = Liquid(i)

            v.x = liquidData.x
            v.y = liquidData.y
            v.width = liquidData.w
            v.height = liquidData.h

            v.isQuicksand = (liquidData.envType > 0)

            v.layerName = liquidData.layer

            if v.layerName == respawnRooms.roomSettings.quicksandLayerName and v.isQuicksand then
                v.isHidden = true
            else
                v.isHidden = layerIsHidden(v.isHidden)
            end
        end

        -- Warps
        local warpIdx = 0

        for i,warpData in ipairs(respawnRooms.levelData.warps) do
            setupWarp(warpIdx,warpData,warpData.ix,warpData.iy,warpData.iDirect,warpData.ox,warpData.oy,warpData.oDirect)
            warpIdx = warpIdx + 1
        end

        for i,warpData in ipairs(respawnRooms.levelData.warps) do
            if warpData.twoWay and warpData.isSetIn and warpData.isSetOut then
                setupWarp(warpIdx,warpData,warpData.ox,warpData.oy,warpData.oDirect,warpData.ix,warpData.iy,warpData.iDirect)
                warpIdx = warpIdx + 1
            end
        end
    end


    local function resetSectionMusic()
        playMusic(-1) -- p-switch music (just used as a "placeholder")
        playMusic(player.section) -- actually restart the section's music
    end

    local function resetTimeSwitches()
        local resetMusic = false

        if mem(PSWITCH_TIMER_ADDR,FIELD_WORD) > 0 then
            Misc.doPSwitch(false)
            resetMusic = true
        else
            Misc.doPSwitchRaw(false)
        end

        if mem(STOPWATCH_TIMER_ADDR,FIELD_WORD) > 0 then
            mem(STOPWATCH_TIMER_ADDR,FIELD_WORD,0)
            resetMusic = true
        end

        respawnRooms.pSwitchEffectActive = false
        Defines.levelFreeze = false

        return resetMusic
    end

    local function resetLevelState()
        local resetMusic = resetTimeSwitches()

        if Level.endState() > 0 then
            mem(LEVEL_END_TIMER,FIELD_WORD,0)
            Level.endState(0)

            resetMusic = true
        end

        mem(CONVEYER_DIRECTION,FIELD_WORD,1) -- reset the direction of conveyer belt NPC's
        NPC.config[274].score = 6 -- reset dragon coin score (why did you do it this way, redigit)

        -- Reset music
        if resetMusic then
            resetSectionMusic()
        end

        -- Star coins
        if respawnRooms.resetSettings.starCoinsReset then
            local starCoinData = SaveData._basegame.starcoin[Level.filename()] or {}

            for k,v in ipairs(starCoinData) do
                if v == 3 then
                    starCoinData[k] = 0
                end
            end
        end
    end

    local function resetPlayer()
        player.speedX = 0
        player.speedY = 2 -- ok

        player.deathTimer = 0

        player.forcedState = FORCEDSTATE_NONE
        player.forcedTimer = 0
        player.deathTimer = 0

        player.powerup = respawnRooms.respawnSettings.respawnPowerup
        player.mount = MOUNT_NONE

        player:mem(0x16,FIELD_WORD,1) -- Hearts

        player:mem(0x34,FIELD_WORD,0)     -- Liquid timer
        player:mem(0x36,FIELD_BOOL,false) -- Water flag
        player:mem(0x06,FIELD_WORD,0)     -- Quicksand timer

        player:mem(0x08,FIELD_WORD,0)     -- Link bombs
        player:mem(0x0C,FIELD_BOOL,false) -- Fairy flag
        player:mem(0x12,FIELD_BOOL,false) -- Link key
        player:mem(0x14,FIELD_WORD,0)     -- Link slash timer
        
        player:mem(0x5C,FIELD_BOOL,false) -- Ground pound flag
        player:mem(0x5E,FIELD_BOOL,false) -- Ground pound flag

        player:mem(0x2C,FIELD_DFLOAT,0) -- Climbing NPC
        player:mem(0x40,FIELD_WORD,0)   -- Climbing state

        player:mem(0x154,FIELD_WORD,0)  -- Held NPC
        player:mem(0xB8,FIELD_WORD,0)   -- Yoshi's mouth NPC

        player:mem(0x11E,FIELD_BOOL,false) -- Can jump
        player:mem(0x120,FIELD_BOOL,false) -- Can spin jump

        player:mem(0x50,FIELD_BOOL,false) -- Spinjumping flag
        player:mem(0x04,FIELD_BOOL,false) -- Weirdness flag
        player:mem(0x11C,FIELD_WORD,0)    -- Jump force
        player:mem(0x140,FIELD_WORD,0)    -- Invincibility frames

        player:mem(0x146,FIELD_WORD,0) -- Bottom collision state
        player:mem(0x148,FIELD_WORD,0) -- Left collision state
        player:mem(0x14A,FIELD_WORD,0) -- Top collision state
        player:mem(0x14C,FIELD_WORD,0) -- Right collision state
        player:mem(0x14E,FIELD_WORD,0) -- Layer push state

        player:mem(0x48,FIELD_WORD,0)  -- Slope stood on
        player:mem(0x154,FIELD_WORD,0) -- NPC held
        player:mem(0x176,FIELD_WORD,0) -- NPC stood on

        player:mem(0x12E,FIELD_BOOL,false) -- Ducking

        megashroom.StopMega(player,false)
        starman.stop(player)

        player.frame = 1

        -- Update hitbox
        local settings = PlayerSettings.get(playerManager.getBaseID(player.character),player.powerup)

        player.width = settings.hitboxWidth
        player.height = settings.hitboxHeight

        -- Move to respawn position
        local startPoint = respawnRooms.levelData.players[1]

        if respawnRooms.currentRoom ~= nil and not respawnRooms.respawnSettings.neverUseRespawnBGOs then
            respawnRooms.currentRoom:warpToRespawnBGO(respawnRooms.roomEnterX,respawnRooms.roomEnterY)
        elseif Checkpoint.getActive() ~= nil then
            local c = Checkpoint.getActive()

            player:teleport(c.x,c.y + 32,true)
        elseif startPoint ~= nil then
            player:teleport(startPoint.x + startPoint.w*0.5,startPoint.y + startPoint.h,true)

            local bounds = player.sectionObj.boundary

            if player.x+player.width*0.5 > (bounds.left + bounds.right)*0.5 then
                player.direction = DIR_LEFT
            else
                player.direction = DIR_RIGHT
            end
        end
    end


    function respawnRooms.reset(fromRespawn)
        if fromRespawn == nil then
            fromRespawn = false
        end


        respawnRooms.onPreReset(fromRespawn)

        layerHiddenCache = {}

        if fromRespawn then
            resetLevelState()
            resetPlayer()
        else
            if respawnRooms.resetSettings.timedSwitchesReset then
                local resetMusic = resetTimeSwitches()

                if resetMusic then
                    resetSectionMusic()
                end
            end
        end


        -- Various things to reset
        if fromRespawn or respawnRooms.resetSettings.colorSwitchesReset then
            if switch.state then
                switch.toggle()
            end

            respawnRooms.colorSwitchStates = {}
        end

        if respawnRooms.resetSettings.eventsReset then
            resetLayers()
        end

        if respawnRooms.resetSettings.sectionsReset then
            for _,sectionData in ipairs(respawnRooms.levelData.sections) do
                resetSection(sectionData)
            end
        end


        -- Monty mole holes
        for _,uid in ipairs(respawnRooms.montyMoleHoleIDs) do
            local fakeNPC = {uid = uid,data = {_basegame = {},_settings = {}}}

            montymolehole.removeDirt(fakeNPC)
        end

        respawnRooms.montyMoleHoleIDs = {}


        clearLevel()
        addStuffFromLevel()

        blockutils.resolveSwitchQueue()


        -- Trigger events
        if respawnRooms.resetSettings.eventsReset then
            resetEvents()
        end


        respawnRooms.onPostReset(fromRespawn)

        -- Find a new room
        if fromRespawn then
            if respawnRooms.currentRoom ~= nil then
                respawnRooms.currentRoom:exit()
            end

            respawnRooms.findNewRoom(true)
        end
    end


    function respawnRooms.setupResetVariables()
        -- Get the level's data from FileFormats
        respawnRooms.levelData = FileFormats.getLevelData()

        -- Get the blocks and sort them
        respawnRooms.levelDataBlocks = table.iclone(respawnRooms.levelData.blocks)
        table.sort(respawnRooms.levelDataBlocks,sortBlockData)

        respawnRooms.levelDataBlockCount = #respawnRooms.levelDataBlocks


        -- For each NPC, find its spawned instance and set its IDX
        for idx,npcData in ipairs(respawnRooms.levelData.npc) do
            if idx <= NPC.count() then
                local v = NPC(idx - 1)

                persistentNPCData[idx] = {currentInstance = v,originalIdx = idx}
                v.data._respawnRoomsOriginalIdx = idx

                local data = respawnRooms.npcIDData[npcData.id]

                if data ~= nil and data.onSetup ~= nil then
                    data.onSetup(v)
                end
            end
        end

        -- The slippery flag isn't actually included in the data for some reason,
        -- so we have to do this...
        for idx,blockData in ipairs(respawnRooms.levelDataBlocks) do
            if idx <= Block.count() then
                blockIsSlippery[idx] = Block(idx).slippery
            end
        end
    end


    function respawnRooms.onColorSwitch(colorID)
        -- Swap state
        respawnRooms.colorSwitchStates[colorID] = not respawnRooms.colorSwitchStates[colorID]
    end
    
    function respawnRooms.onEvent(eventName)
        if eventName == "P Switch - Start" then
            respawnRooms.pSwitchEffectActive = true
        elseif eventName == "P Switch - End" then
            respawnRooms.pSwitchEffectActive = false
        end
    end
end


-- Specific NPC exceptions for reset
do
    respawnRooms.npcIDData = {}

    -- Monty Mole
    local originalSpawnDirt = montymolehole.spawnDirt

    function montymolehole.spawnDirt(v)
        table.insert(respawnRooms.montyMoleHoleIDs,v.uid)
        originalSpawnDirt(v)
    end

    respawnRooms.npcIDData[309] = {
        onSpawn = function(v)
            -- Copied from its onStartNPC
            local data = v.data._basegame
            data.wasBuried = 1
            if v.data._settings.startHidden == false then
                data.wasBuried = 0
            else
                data.vanillaFriendly = v.friendly
                v.friendly = true
                v.noblockcollision = true
            end

            data.timer = 0
            data.direction = v.direction
            data.state = data.wasBuried

            v.animationFrame = -999
        end,
    }

    -- Filth coating
    respawnRooms.npcIDData[488] = {
        onRemove = function(v)
            -- Prevents error and effect spawning
            v.data._basegame.block = nil
        end,
    }

    -- Switch platforms
    local function togglePlatformActive(v)
        local data = v.data._basegame.lineguide

        data.active = not data.active
    end

    for colorID = 1,4 do
        respawnRooms.npcIDData[476 + colorID] = {
            onSpawn = function(v)
                if respawnRooms.colorSwitchStates[colorID] then
                    togglePlatformActive(v)
                end
            end,
        }
    end

    for palaceID,palaceName in ipairs{"yellow","blue","green","red"} do
        respawnRooms.npcIDData[480 + palaceID] = {
            onSpawn = function(v)
                if SaveData._basegame.bigSwitch[palaceName] then
                    togglePlatformActive(v)
                end
            end,
        }
    end

    -- Collectable Stars
    local function hasStar(filename,section)
        for i = 1,mem(STAR_COUNT_ADDR,FIELD_WORD) do
            local starPtr = STAR_LIST_ADDR + (i - 1)*8

            local starFilename = mem(starPtr,FIELD_STRING)
            local starSection = mem(starPtr + 4,FIELD_WORD)

            -- Does the saved star match up with the target?
            if starFilename == filename and (starSection == section or starSection == -1) then
                return true
            end
        end

        return false
    end

    respawnRooms.npcIDData[97] = {
        onSpawn = function(v)
            if hasStar(Level.filename(),v.section) then
                v.ai1 = 1
                v.spawnAi1 = v.ai1
            end
        end,
    }
    
    respawnRooms.npcIDData[196] = {
        onPreSpawn = function(npcData,section,persistentData)
            return hasStar(Level.filename(),section)
        end,
    }

    -- Checkpoints
    respawnRooms.npcIDData[430] = {
        onSetup = function(v)
            local persistentData = respawnRooms.getPersistentNPCData(v)

            persistentData.checkpoint = v.data._basegame.checkpoint
        end,
        onSpawn = function(v)
            local persistentData = respawnRooms.getPersistentNPCData(v)

            v.data._basegame.checkpoint = persistentData.checkpoint

            if persistentData.checkpoint == Checkpoint.getActive() then
                v.data._basegame.state = 2
                v.data._basegame.frame = 0
            end
        end,
    }

    respawnRooms.npcIDData[400] = {
        onSetup = function(v)
            local persistentData = respawnRooms.getPersistentNPCData(v)

            persistentData.checkpoint = v.data._basegame.checkpoint
        end,
        onPreSpawn = function(npcData,section,persistentData)
            -- If it's been collected, don't spawn
            return persistentData.checkpoint.collected
        end,
        onSpawn = function(v)
            local persistentData = respawnRooms.getPersistentNPCData(v)

            v.data._basegame.checkpoint = persistentData.checkpoint
        end,
    }

    -- Light sources
    respawnRooms.npcIDData[668] = {
        onSpawn = function(v)
            local data = v.data._basegame
            local s = v.data._settings
            data.light = Darkness.light(0,0,s.radius,s.brightness,s.color,s.flicker)
            data.light:attach(v, true)
            data.light.enabled = not v.isHidden
            Darkness.addLight(data.light)
        end,
    }

    respawnRooms.npcIDData[674] = {
        onSpawn = function(v)
            local data = v.data._basegame
            local s = v.data._settings
            data.light = Darkness.light{x=0, y=0, radius = s.radius, brightness = s.brightness, color = s.color, flicker = s.flicker, type = Darkness.lighttype.SPOT, dir = vector.down2:rotate(s.angle), spotangle = s.spotangle, spotpower = s.spotpower}
            data.light:attach(v, true)
            data.light.enabled = not v.isHidden
            Darkness.addLight(data.light)
        end,
    }

    -- Boo circles
    local boocircle = require("npcs/ai/boocircles")

    respawnRooms.npcIDData[294] = {
        onRemove = function(v)
            -- If onNPCKill runs and the boo table is nil, there's an error, so prevent that
            local data = v.data._basegame

            if data.boos == nil then
                data.boos = {}
            end
        end,
        onSpawn = function(v)
            -- Make sure they're all spawned in
            boocircle.onTickNPC(v)
        end,
    }

    -- Blargg
    respawnRooms.npcIDData[199] = {
        onSpawn = function(v)
            -- Make sure it's in the right position
            local newY = v.spawnY + v.height + 36
            local distance = newY - v.y

            v.y = newY
            v:mem(0x14C,FIELD_WORD,0)

            -- Move the attached layer
            local attachedLayerObj = Layer.get(v.attachedLayerName)

            if attachedLayerObj ~= nil then
                attachedLayerObj.speedX = 0
                attachedLayerObj.speedY = distance
            end
        end,
    }

    -- Bullet bills/banzai bills/eeries
    respawnRooms.npcIDData[17] = {
        onSpawn = function(v)
            -- Forcefully despawn unless 
            v:mem(0x124,FIELD_BOOL,false)
            v.despawnTimer = 0
        end,
    }
    
    respawnRooms.npcIDData[18] = respawnRooms.npcIDData[17]
    respawnRooms.npcIDData[42] = respawnRooms.npcIDData[17]

    -- Goal tape
    local function setGoalTapePosition(v)
        -- Recreation of:
        -- https://github.com/smbx/smbx-legacy-source/blob/master/modNPC.bas#L470
        local highestBlock

        for _,b in Block.iterateIntersecting(v.x,v.y,v.x + v.width,v.y + 8000) do
            if (highestBlock == nil or b.y < highestBlock.y) and b.id ~= respawnRooms.roomBlockID then
                highestBlock = b
            end
        end

        if highestBlock ~= nil then
            v.y = highestBlock.y - v.height
            v.ai2 = highestBlock.y + 4
            
            v.ai1 = 1
        end

        v:mem(0x14C,FIELD_WORD,0)
    end

    respawnRooms.npcIDData[197] = {
        onSetup = function(v)
            v.y = v.spawnY
            setGoalTapePosition(v)
        end,
        onSpawn = function(v)
            setGoalTapePosition(v)
        end,
    }

    -- Ted spawner
    respawnRooms.npcIDData[306] = {
        onSpawn = function(v)
            -- Initialise data table
            -- Fixes a basegame bug where they don't initialise properly if spawned while paused.
            local data = v.data._basegame
            local cfg = NPC.config[v.id]

            data.lastHeld = 0
            data.gripTimer = cfg.delay
            data.gripState = 0
            data.animationFrame = 0

            local yMod = -cfg.traveldistance

            data.startY = v.spawnY + yMod
            v.y = v.y + yMod
            
            data.direction = v.direction
        end,
    }
end


-- Rooms!
do
    local roomMT = {}


    respawnRooms.TRANSITION_STATE = {
        INACTIVE = 0,
        PAN = 1,
        FADE_OUT = 2,
        FADE_WAIT = 3,
        FADE_BACK = 4,
    }


    respawnRooms.roomBlockID = 0

    respawnRooms.rooms = {}
    respawnRooms.currentRoom = nil

    respawnRooms.cameraSection = -1

    respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.INACTIVE
    respawnRooms.transitionTimer = 0
    respawnRooms.transitionFade = 0
    respawnRooms.transitionStartX = 0
    respawnRooms.transitionStartY = 0

    respawnRooms.roomEnterX = 0
    respawnRooms.roomEnterY = 0


    local roomInstanceFuncs = {}
    local roomWriteFuncs = {}
    local roomReadFuncs = {}


    function roomInstanceFuncs:getCollider()
        return Colliders.Box(self.x,self.y,self.width,self.height)
    end

    function roomInstanceFuncs:getBounds()
        return self.x,self.y,self.x + self.width,self.y + self.height
    end

    function roomInstanceFuncs:spawnNPCs()
        local x1,y1,x2,y2 = self:getBounds()

        for _,n in NPC.iterateIntersecting(x1,y1,x2,y2) do
            if not n.isGenerator then
                if n.despawnTimer < 0 and n:mem(0x126,FIELD_BOOL) then
                    n:mem(0x124,FIELD_BOOL,true)
                    n:mem(0x14C,FIELD_WORD,1)
                    n.despawnTimer = 180
                elseif n.despawnTimer > 0 then
                    n.despawnTimer = math.max(10,n.despawnTimer)
                end
            else
                -- Effectively the "on screen" flag for generators
                n:mem(0x74,FIELD_BOOL,true)
            end
        end
    end

    function roomInstanceFuncs:restrictPlayer()
        if player.deathTimer > 0 or player:mem(0x13C,FIELD_BOOL) or player.forcedState ~= FORCEDSTATE_NONE then
            return
        end

        local pushedHorizontally = false
        local pushedVertically = false

        if player.x <= self.x then
            if respawnRooms.getIntersectingRoom(player.x - player.width - 4,player.y,player.width,player.height) == nil then
                player.speedX = math.max(0,player.speedX)
                player.x = self.x

                player:mem(0x148,FIELD_WORD,2)
                pushedHorizontally = true
            end
        elseif player.x >= self.x + self.width - player.width then
            if respawnRooms.getIntersectingRoom(player.x + player.width + 4,player.y,player.width,player.height) == nil then
                player.speedX = math.min(0,player.speedX)
                player.x = self.x + self.width - player.width

                player:mem(0x14C,FIELD_WORD,2)
                pushedHorizontally = true
            end
        end

        if player.y >= self.y + self.height + 64 then
            if respawnRooms.getIntersectingRoom(player.x,player.y + player.height + 4,player.width,player.height) == nil then
                player:kill()
            end
        else
            local minY = self.y - player.height - 32

            if player.y <= minY and respawnRooms.getIntersectingRoom(player.x,player.y - player.height + 4,player.width,player.height) == nil then
                player.y = minY
                pushedVertically = true
            end
        end

        if (pushedHorizontally and self.speedX ~= 0) or (pushedVertically and self.speedY ~= 0) then
            player:mem(0x14E,FIELD_WORD,2)
        end
    end


    function roomInstanceFuncs:enter(instant)
        if respawnRooms.currentRoom == self then
            return
        end

        if respawnRooms.currentRoom ~= nil then
            respawnRooms.currentRoom.active = false
        end

        -- Handle things
        respawnRooms.currentRoom = self
        self.active = true

        respawnRooms.roomEnterX = player.x + player.width*0.5
        respawnRooms.roomEnterY = player.y + player.height

        -- Did the player come from below? If so, give 'em a speed boost
        if (player.y+player.height-player.speedY+8 > self.y+self.height) and player.forcedState == FORCEDSTATE_NONE and respawnRooms.roomSettings.jumpFromBelowSpeed ~= 0 then
            player:mem(0x176,FIELD_WORD,0) -- stood on NPC
            player:mem(0x11C,FIELD_WORD,0) -- jump force
            
            player.speedY = respawnRooms.roomSettings.jumpFromBelowSpeed
        end

        -- Camera transition
        if not instant and respawnRooms.cameraSection == self.section and respawnRooms.roomSettings.transitionType ~= respawnRooms.TRANSITION_TYPE.NONE then
            if respawnRooms.roomSettings.transitionType > 0 then
                -- Fade transitions
                respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.FADE_OUT
            elseif respawnRooms.roomSettings.transitionType < 0 then
                -- Pan transitions
                respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.PAN

                if self.resetWhenEntered and not respawnRooms.roomSettings.onlyResetAtEnd then
                    respawnRooms.reset(false)
                end
            end

            respawnRooms.transitionTimer = 0

            respawnRooms.transitionStartX = camera.x
            respawnRooms.transitionStartY = camera.y

            Misc.pause()
        elseif self.resetWhenEntered then
            respawnRooms.reset(false)
        end

        respawnRooms.onRoomEnter(self)
    end

    function roomInstanceFuncs:exit()
        if respawnRooms.currentRoom == self then
            respawnRooms.currentRoom = nil
            self.active = false
        end
    end


    function roomInstanceFuncs:boundCameraPosToRoom(cameraX,cameraY)
        -- Find the camera's width
        local width = camera.width
        local height = camera.height

        if customCamera ~= nil then
            local _,_,fullWidth,fullHeight = customCamera.getFullCameraPos()

            width = fullWidth
            height = fullHeight
        else
            local handycamObj = rawget(handycam,1)

            if handycamObj ~= nil then
                width = width/handycamObj.zoom
                height = height/handycamObj.zoom
            end
        end

        -- Clamp it to the room's bounds
        local clampedX,clampedY

        if width <= self.width then
            clampedX = math.clamp(cameraX + camera.width*0.5,self.x + width*0.5,self.x + self.width - width*0.5) - camera.width*0.5
        else
            clampedX = self.x + (self.width - width)*0.5
        end

        if height <= self.height then
            clampedY = math.clamp(cameraY + camera.height*0.5,self.y + height*0.5,self.y + self.height - height*0.5) - camera.height*0.5
        else
            clampedY = self.y + (self.height - height)*0.5
        end

        -- Clamp to the section boundaries
        local b = self.sectionObj.boundary

        clampedX = math.clamp(clampedX + camera.width *0.5,b.left + width *0.5,b.right  - width *0.5) - camera.width *0.5
        clampedY = math.clamp(clampedY + camera.height*0.5,b.top  + height*0.5,b.bottom - height*0.5) - camera.height*0.5


        return clampedX,clampedY
    end


    function roomInstanceFuncs:getRespawnBGOs()
        local x1,y1,x2,y2 = self:getBounds()
        local list = {}

        for _,bgo in BGO.iterateIntersecting(x1,y1,x2,y2) do
            if not bgo.isHidden and respawnRooms.respawnSettings.respawnBGODirections[bgo.id] ~= nil then
                table.insert(list,bgo)
            end
        end

        return list
    end

    function roomInstanceFuncs:warpToRespawnBGO(x,y)
        -- Find the closest BGO
        local closestDistance = math.huge
        local closestBGO

        for _,bgo in ipairs(self:getRespawnBGOs()) do
            if x == nil then
                -- If no position is given, just use the first one
                closestBGO = bgo
                break
            end

            -- Is this closer to the given position?
            local distance = vector((bgo.x + bgo.width*0.5) - x,(bgo.y + bgo.height) - y).sqrlength

            if distance < closestDistance then
                closestDistance = distance
                closestBGO = bgo
            end
        end

        -- Warp to it
        if closestBGO ~= nil then
            player:teleport(closestBGO.x + closestBGO.width*0.5,closestBGO.y + closestBGO.height,true)
            player.direction = respawnRooms.respawnSettings.respawnBGODirections[closestBGO.id]
        else
            error("No valid respawn point in room")
        end
    end


    function roomReadFuncs:layerName()
        return self._layerName
    end
    function roomWriteFuncs:layerName(value)
        self._layerName = value
        self._layerObj = Layer.get(value)
    end

    function roomReadFuncs:layerObj()
        return self._layerObj 
    end

    function roomReadFuncs:sectionObj()
        return Section(self.section)
    end


    roomMT.__type = "Room"

    roomMT.__index = function(v,key)
        if roomInstanceFuncs[key] ~= nil then
            return roomInstanceFuncs[key]
        elseif roomReadFuncs[key] ~= nil then
            return roomReadFuncs[key](v)
        end
    end

    roomMT.__newindex = function(v,key,value)
        if roomWriteFuncs[key] ~= nil then
            roomWriteFuncs[key](v,value)
        elseif roomReadFuncs[key] ~= nil then
            error("Room property '".. key.. "' is read-only",2)
        else
            rawset(v,key,value)
        end
    end


    local function checkOption(parent,optionName)
        local value = 0
        if type(parent) == "Block" then
            value = parent.data._settings[optionName]
        end

        if value == 0 then
            return respawnRooms.roomSettings.defaultOptions[optionName]
        else
            return (value == 2)
        end
    end


    local function addRoom(parent)
        local newRoom = setmetatable({},roomMT)

        newRoom.x = parent.x
        newRoom.y = parent.y
        newRoom.width = parent.width
        newRoom.height = parent.height

        newRoom.speedX = 0
        newRoom.speedY = 0
        

        newRoom.section = Section.getIdxFromCoords(newRoom.x,newRoom.y,newRoom.width,newRoom.height)

        newRoom._layerName = parent.layerName
        newRoom._layerObj = Layer.get(newRoom._layerName)

        newRoom.active = false
        newRoom.disabled = false

        -- Resize if exactly 608 pixels tall
        if newRoom.height == 608 then
            newRoom.height = 600
            newRoom.y = newRoom.y + 8
        end

        newRoom.spawnX = newRoom.x
        newRoom.spawnY = newRoom.y

        -- Options
        newRoom.usePhysicalBounds = checkOption(parent,"usePhysicalBounds")
        newRoom.resetWhenEntered = checkOption(parent,"resetWhenEntered")
        newRoom.actAsSpawnZone = checkOption(parent,"actAsSpawnZone")

        -- Handle tags
        newRoom.tagList = {}
        newRoom.tagMap = {}

        if type(parent) == "Block" then
            -- Parse tags
            local tagString = parent.data._settings.tags

            newRoom.tagsList = {}

            for _,tag in ipairs(tagString:split(",")) do
                -- Remove spaces around
                tag = tag:match("%s*(.+)%s*")
                
                if tag ~= nil and tag ~= "" then
                    table.insert(newRoom.tagList,tag)
                    newRoom.tagMap[tag] = true
                end
            end
        end

        -- Add it to the list
        newRoom.idx = #respawnRooms.rooms + 1
        respawnRooms.rooms[newRoom.idx] = newRoom

        return newRoom
    end


    function respawnRooms.getRoomsWithTag(tag)
        local tbl = {}

        for _,v in ipairs(respawnRooms.rooms) do
            if v.tagMap[tag] then
                table.insert(tbl,tag)
            end
        end

        return tbl
    end

    function respawnRooms.getIntersectingRoom(x,y,width,height)
        local col = Colliders.Box(x,y,width,height)

        for _,v in ipairs(respawnRooms.rooms) do
            if not v.disabled and not v.layerObj.isHidden and v:getCollider():collide(col) then
                return v
            end
        end
    end


    function respawnRooms.findNewRoom(instant)
        -- If we're already in a valid room, no need to change
        if respawnRooms.currentRoom ~= nil then
            if not respawnRooms.currentRoom.disabled and respawnRooms.currentRoom:getCollider():collide(player) then
                return
            end
        end

        -- Find a new room
        local newRoom

        for _,v in ipairs(respawnRooms.rooms) do
            if not v.disabled and not v.layerObj.isHidden and v:getCollider():collide(player) then
                if newRoom == nil then
                    newRoom = v
                else -- The player is in multiple rooms, therefore we don't change
                    newRoom = nil
                    break
                end
            end
        end

        -- If we have a new room, enter it.
        -- If the current room is in a different section, leave it.
        if newRoom ~= nil then
            newRoom:enter(instant)
        elseif respawnRooms.currentRoom ~= nil and respawnRooms.currentRoom.section ~= player.section then
            respawnRooms.currentRoom:exit()
        end
    end


    function respawnRooms.createRooms()
        if respawnRooms.roomBlockID > 0 then
            for _,b in Block.iterate(respawnRooms.roomBlockID) do
                addRoom(b)
            end
        end

        for _,l in ipairs(Liquid.get()) do
            if l.layerName == respawnRooms.roomSettings.quicksandLayerName and l.isQuicksand then
                l.isHidden = true
                addRoom(l)
            end
        end

        respawnRooms.findNewRoom(true)
    end


    function respawnRooms.updateRoomsOnTick()
        for _,v in ipairs(respawnRooms.rooms) do
            local layerObj = v.layerObj

            -- Move with layers
            if layerObj ~= nil and not layerObj:isPaused() then
                v.speedX = layerObj.speedX
                v.speedY = layerObj.speedY
            else
                v.speedX = 0
                v.speedY = 0
            end

            v.x = v.x + v.speedX
            v.y = v.y + v.speedY
        end
    end

    function respawnRooms.updateRoomsOnTickEnd()
        respawnRooms.findNewRoom(false)

        if respawnRooms.currentRoom ~= nil then
            if respawnRooms.currentRoom.actAsSpawnZone then
                respawnRooms.currentRoom:spawnNPCs()
            end

            if respawnRooms.currentRoom.usePhysicalBounds then
                respawnRooms.currentRoom:restrictPlayer()
            end
        end
    end


    local stateFuncs = {}

    stateFuncs[respawnRooms.TRANSITION_STATE.INACTIVE] = function()

    end

    stateFuncs[respawnRooms.TRANSITION_STATE.PAN] = function()
        respawnRooms.transitionTimer = respawnRooms.transitionTimer + 1

        if respawnRooms.transitionTimer >= respawnRooms.roomSettings.panTransitionDuration then
            respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.INACTIVE
            respawnRooms.transitionTimer = 0

            if respawnRooms.currentRoom.resetWhenEntered then
                respawnRooms.reset(false)
            end

            Misc.unpause()
        end
    end


    stateFuncs[respawnRooms.TRANSITION_STATE.FADE_OUT] = function()
        respawnRooms.transitionTimer = respawnRooms.transitionTimer + 1
        respawnRooms.transitionFade = math.min(1,respawnRooms.transitionTimer/respawnRooms.roomSettings.fadeOutDuration)
    
        if respawnRooms.transitionFade >= 1 then
            respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.FADE_WAIT
            respawnRooms.transitionTimer = 0
        end
    end
    
    stateFuncs[respawnRooms.TRANSITION_STATE.FADE_WAIT] = function()
        if respawnRooms.transitionTimer == 0 then
            if respawnRooms.currentRoom.resetWhenEntered then
                respawnRooms.reset(false)
            end
        end
        
        respawnRooms.transitionTimer = respawnRooms.transitionTimer + 1
    
        if respawnRooms.transitionTimer >= respawnRooms.roomSettings.fadeWaitTime then
            respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.FADE_BACK
            respawnRooms.transitionTimer = 0
        end
    end
    
    stateFuncs[respawnRooms.TRANSITION_STATE.FADE_BACK] = function()
        respawnRooms.transitionTimer = respawnRooms.transitionTimer + 1
        respawnRooms.transitionFade = math.max(0,1 - respawnRooms.transitionTimer/respawnRooms.roomSettings.fadeBackDuration)
    
        if respawnRooms.transitionFade <= 0 then
            respawnRooms.transitionState = respawnRooms.TRANSITION_STATE.INACTIVE
            respawnRooms.transitionTimer = 0

            Misc.unpause()
        end
    end


    function respawnRooms.updateRoomsOnInput()
        -- Update transition
        stateFuncs[respawnRooms.transitionState]()
    end


    function respawnRooms.boundCamera()
        if respawnRooms.transitionState == respawnRooms.TRANSITION_STATE.PAN then
            local t = respawnRooms.cameraPanFuncs[respawnRooms.roomSettings.transitionType](respawnRooms.transitionTimer/respawnRooms.roomSettings.panTransitionDuration)
            local stopX,stopY = respawnRooms.currentRoom:boundCameraPosToRoom(camera.x,camera.y)

            camera.x = math.lerp(respawnRooms.transitionStartX,stopX,t)
            camera.y = math.lerp(respawnRooms.transitionStartY,stopY,t)
        elseif respawnRooms.transitionState == respawnRooms.TRANSITION_STATE.FADE_OUT then
            camera.x = respawnRooms.transitionStartX
            camera.y = respawnRooms.transitionStartY
        elseif respawnRooms.currentRoom ~= nil then
            camera.x,camera.y = respawnRooms.currentRoom:boundCameraPosToRoom(camera.x,camera.y)
        end

        respawnRooms.cameraSection = player.section
    end

    function respawnRooms.drawTransitionFade()
        if respawnRooms.transitionFade > 0 then
            local closing = (respawnRooms.transitionState == respawnRooms.TRANSITION_STATE.FADE_BACK)
            local t = respawnRooms.transitionFade

            respawnRooms.fadeDrawFuncs[respawnRooms.roomSettings.transitionType](t,closing)
        end
    end
end


-- Respawning
do
    respawnRooms.RESPAWN_STATE = {
        INACTIVE = 0,
        DEATH_ANIM = 1,
        FADE_OUT = 2,
        FADE_WAIT = 3,
        FADE_BACK = 4,
    }

    respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.INACTIVE
    respawnRooms.respawnTimer = 0
    respawnRooms.respawnFade = 0

    respawnRooms.respawnPaused = false


    function respawnRooms.onPlayerKill(eventObj,_)
        if eventObj.cancelled or not respawnRooms.respawnSettings.enabled then
            return
        end
    
        -- Spawn death effect
        local effectID = playerManager.getCharacters()[player.character].deathEffect
        local e = Effect.spawn(effectID,player.x + player.width*0.5,player.y + player.height*0.5)
    
        if playerManager.getBaseID(player.character) == CHARACTER_LINK then
            e.direction = player.direction
            e.speedX = -2*e.direction
        end

        -- Play sound effect
        if respawnRooms.respawnSettings.deathSound ~= nil then
            SFX.play(respawnRooms.respawnSettings.deathSound)
        end

        -- Do screen shake
        if respawnRooms.respawnSettings.deathEarthquake > 0 then
            Defines.earthquake = respawnRooms.respawnSettings.deathEarthquake
        end
    
        -- Start death
        respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.DEATH_ANIM
        respawnRooms.respawnTimer = 0
        respawnRooms.respawnFade = 0

        respawnRooms.respawnPaused = false
        addScore(-20)

        player.deathTimer = 1
    
        eventObj.cancelled = true
    end


    local stateFuncs = {}

    stateFuncs[respawnRooms.RESPAWN_STATE.INACTIVE] = function()
        -- If the player's not dead, don't care
        if player.deathTimer <= 0 or not respawnRooms.respawnSettings.enabled then
            respawnRooms.respawnTimer = 0
            return
        end

        -- There are certain cases where the player can die without onPlayerKill
        -- running (for some reason), so this accounts for it.
        respawnRooms.respawnTimer = respawnRooms.respawnTimer + 1

        if Level.endState() == 0 or respawnRooms.respawnTimer >= 200 then
            -- Start death
            respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.DEATH_ANIM
            respawnRooms.respawnTimer = 0
            respawnRooms.respawnFade = 0

            respawnRooms.respawnPaused = false
        end

        mem(LEVEL_END_TIMER,FIELD_WORD,0)
    end

    stateFuncs[respawnRooms.RESPAWN_STATE.DEATH_ANIM] = function()
        respawnRooms.respawnTimer = respawnRooms.respawnTimer + 1

        if respawnRooms.respawnTimer >= respawnRooms.respawnSettings.deathAnimDuration then
            if respawnRooms.respawnSettings.transitionType ~= respawnRooms.TRANSITION_TYPE.NONE then
                respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.FADE_OUT
                respawnRooms.respawnTimer = 0

                if respawnRooms.respawnSettings.pauseDuringTransition then
                    respawnRooms.respawnPaused = true
                    Misc.pause()
                end
            else
                respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.INACTIVE
                respawnRooms.respawnTimer = 0

                respawnRooms.reset(true)
            end
        end
    end

    stateFuncs[respawnRooms.RESPAWN_STATE.FADE_OUT] = function()
        respawnRooms.respawnTimer = respawnRooms.respawnTimer + 1
        respawnRooms.respawnFade = math.min(1,respawnRooms.respawnTimer/respawnRooms.respawnSettings.fadeOutDuration)

        if respawnRooms.respawnFade >= 1 then
            respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.FADE_WAIT
            respawnRooms.respawnTimer = 0
        end
    end

    stateFuncs[respawnRooms.RESPAWN_STATE.FADE_WAIT] = function()
        if respawnRooms.respawnTimer == 0 then
            respawnRooms.reset(true)
        end

        respawnRooms.respawnTimer = respawnRooms.respawnTimer + 1

        if respawnRooms.respawnTimer >= respawnRooms.respawnSettings.fadeWaitTime then
            respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.FADE_BACK
            respawnRooms.respawnTimer = 0
        end
    end

    stateFuncs[respawnRooms.RESPAWN_STATE.FADE_BACK] = function()
        respawnRooms.respawnTimer = respawnRooms.respawnTimer + 1
        respawnRooms.respawnFade = math.max(0,1 - respawnRooms.respawnTimer/respawnRooms.respawnSettings.fadeBackDuration)

        if respawnRooms.respawnFade <= 0 then
            respawnRooms.respawnState = respawnRooms.RESPAWN_STATE.INACTIVE
            respawnRooms.respawnTimer = 0

            if respawnRooms.respawnPaused then
                respawnRooms.respawnPaused = false
                Misc.unpause()
            end
        end
    end


    function respawnRooms.updateRespawningOnTick()
        if player.deathTimer > 0 and respawnRooms.respawnSettings.enabled then
            player.deathTimer = math.min(100,player.deathTimer)
        end

        if not respawnRooms.respawnPaused then
            stateFuncs[respawnRooms.respawnState]()
        end
    end

    function respawnRooms.updateRespawningOnInput()
        if respawnRooms.respawnPaused then
            stateFuncs[respawnRooms.respawnState]()
        end
    end


    function respawnRooms.drawRespawnFade()
        if respawnRooms.respawnFade > 0 then
            local closing = (respawnRooms.respawnState == respawnRooms.RESPAWN_STATE.FADE_BACK)
            local t = respawnRooms.respawnFade

            respawnRooms.fadeDrawFuncs[respawnRooms.respawnSettings.transitionType](t,closing)
        end
    end
end


-- Transitions
do
    respawnRooms.TRANSITION_TYPE = {
        NONE = 0,

        FADE = 1,
        MOSAIC = 2,
        DIAMOND = 3,
        ROTATING_SQUARE = 4,
        DIAMOND_SWEEP = 5,
        INWARD_SWEEP = 6,
        WIPE = 7,

        PAN_CONSTANT = -1,
        PAN_SMOOTH = -2,
        PAN_SINE = -3,
        PAN_QUAD = -4,
    }


    -- Camera pan functions
    -- Can be used only for room transitions.
    respawnRooms.cameraPanFuncs = {}

    respawnRooms.cameraPanFuncs[respawnRooms.TRANSITION_TYPE.PAN_CONSTANT] = function(t)
        return t
    end
    respawnRooms.cameraPanFuncs[respawnRooms.TRANSITION_TYPE.PAN_SMOOTH] = function(t)
        return easing.outExpo(t,0,1,1)
    end
    respawnRooms.cameraPanFuncs[respawnRooms.TRANSITION_TYPE.PAN_SINE] = function(t)
        return easing.inOutSine(t,0,1,1)
    end
    respawnRooms.cameraPanFuncs[respawnRooms.TRANSITION_TYPE.PAN_QUAD] = function(t)
        return easing.inOutQuad(t,0,1,1)
    end


    -- Fading functions
    -- Can be used for either room transitions or respawn transitions.
    respawnRooms.fadeDrawFuncs = {}

    local screenBuffer = Graphics.CaptureBuffer(800,600)


    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.FADE] = function(t,closing)
        Graphics.drawScreen{color = Color.black.. t,priority = 6}
    end

    local mosaicShader

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.MOSAIC] = function(t,closing)
        -- Apply mosaic effect
        --local pixelSize = math.floor(t*32 + 0.5)
        local pixelSize = math.ceil(t*32)*2

        if pixelSize > 0 then
            if mosaicShader == nil then
                mosaicShader = Shader()
                mosaicShader:compileFromFile(nil,"respawnRooms_mosaic.frag")
            end

            screenBuffer:captureAt(-5.1)

            Graphics.drawScreen{
                texture = screenBuffer,priority = -5.1,
                shader = mosaicShader,uniforms = {
                    bufferSize = vector(screenBuffer.width,screenBuffer.height),
                    pixelSize = pixelSize,
                },
            }
        end

        -- Apply fade
        Graphics.drawScreen{color = Color.black.. t,priority = 6}
    end

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.DIAMOND] = function(t,closing)
        local maxSize = math.max(camera.width,camera.height)*0.9
        local size = easing.outSine(t,0,maxSize,1)
        --local size = t*maxSize

        local x = camera.width*0.5
        local y = camera.height*0.5

        Graphics.glDraw{
            color = Color.black,priority = 6,
            primitive = Graphics.GL_TRIANGLE_STRIP,
            vertexCoords = {
                x,y - size, -- top
                x + size,y, -- right
                x - size,y, -- left
                x,y + size, -- bottom
            },
        }
    end

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.ROTATING_SQUARE] = function(t,closing)
        local maxSize = math.max(camera.width,camera.height)*1.35
        local size = easing.inSine(t,0,maxSize,1)
        --local size = t*maxSize

        local x = camera.width*0.5
        local y = camera.height*0.5

        local rotationTime = t
        if closing then
            rotationTime = 1 - rotationTime
        end

        Graphics.drawBox{
            color = Color.black,priority = 6,centred = true,
            x = x,y = y,width = size,height = size,
            rotation = easing.inSine(rotationTime,45,180,1),
        }
    end

    local diamondWidth = 20
    local diamondHeight = diamondWidth

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.DIAMOND_SWEEP] = function(t,closing)
        local countX = math.ceil(camera.width/diamondWidth)
        local countY = math.ceil(camera.height/diamondHeight)
        local maxCount = math.max(countX,countY)

        local totalWidth = countX*diamondWidth
        local totalHeight = countY*diamondHeight

        local vertexCoords = {}
        local vertexCount = 0

        for gridX = 0,countX do
            for gridY = 0,countY do
                local x = (camera.width  - totalWidth )*0.5 + gridX*diamondWidth
                local y = (camera.height - totalHeight)*0.5 + gridY*diamondHeight

                local scale

                if closing then
                    scale = math.clamp(t*3 - (1 - gridX/maxCount) - (1 - gridY/maxCount))
                else
                    scale = math.clamp(t*3 - gridX/maxCount - gridY/maxCount)
                end

                local width = diamondWidth*scale
                local height = diamondHeight*scale

                -- Left side
                vertexCoords[vertexCount+1 ] = x          -- top
                vertexCoords[vertexCount+2 ] = y - height
                vertexCoords[vertexCount+3 ] = x - width  -- left
                vertexCoords[vertexCount+4 ] = y
                vertexCoords[vertexCount+5 ] = x          -- bottom
                vertexCoords[vertexCount+6 ] = y + height

                -- Right side
                vertexCoords[vertexCount+7 ] = x          -- top
                vertexCoords[vertexCount+8 ] = y - height
                vertexCoords[vertexCount+9 ] = x + width  -- right
                vertexCoords[vertexCount+10] = y
                vertexCoords[vertexCount+11] = x          -- bottom
                vertexCoords[vertexCount+12] = y + height

                vertexCount = vertexCount + 12
            end
        end

        Graphics.glDraw{
            color = Color.black,priority = 6,
            vertexCoords = vertexCoords,
        }
    end

    local gridWidth = 16
    local gridHeight = gridWidth

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.INWARD_SWEEP] = function(t,closing)
        local halfCountX = math.ceil(camera.width/gridWidth*0.5)
        local halfCountY = math.ceil(camera.height/gridHeight*0.5)
        local countX = halfCountX*2
        local countY = halfCountY*2
        local maxHalfCount = math.max(halfCountX,halfCountY)

        local totalWidth = countX*gridWidth
        local totalHeight = countY*gridHeight

        local vertexCoords = {}
        local vertexCount = 0

        for gridX = 0,countX do
            for gridY = 0,countY do
                local x = (camera.width  - totalWidth )*0.5 + gridX*gridWidth
                local y = (camera.height - totalHeight)*0.5 + gridY*gridHeight

                local delayX = 1 - math.abs(gridX - halfCountX)/maxHalfCount
                local delayY = 1 - math.abs(gridY - halfCountY)/maxHalfCount
                local scale = math.clamp(t*3.5 - (delayX + delayY)*1.25)*2

                local width = gridWidth*scale
                local height = gridHeight*scale

                if gridX >= halfCountX then
                    vertexCoords[vertexCount+1] = x + gridWidth
                    vertexCoords[vertexCount+3] = x + gridWidth - width
                    vertexCoords[vertexCount+5] = x + gridWidth
                else
                    vertexCoords[vertexCount+1] = x
                    vertexCoords[vertexCount+3] = x + width
                    vertexCoords[vertexCount+5] = x
                end

                if gridY >= halfCountY then
                    vertexCoords[vertexCount+2] = y + gridHeight
                    vertexCoords[vertexCount+4] = y + gridHeight
                    vertexCoords[vertexCount+6] = y + gridHeight - height
                else
                    vertexCoords[vertexCount+2] = y
                    vertexCoords[vertexCount+4] = y
                    vertexCoords[vertexCount+6] = y + height
                end

                vertexCount = vertexCount + 6
            end
        end

        Graphics.glDraw{
            color = Color.black,priority = 6,
            vertexCoords = vertexCoords,
        }
    end

    local wipeOutTexture,wipeBackTexture
    local wipeShader

    respawnRooms.fadeDrawFuncs[respawnRooms.TRANSITION_TYPE.WIPE] = function(t,closing)
        if wipeShader == nil then
            wipeShader = Shader()
            wipeShader:compileFromFile(nil,"respawnRooms_wipe.frag")

            wipeOutTexture = Graphics.loadImageResolved("respawnRooms_wipe_out.png")
            wipeBackTexture = Graphics.loadImageResolved("respawnRooms_wipe_back.png")
        end

        local wipeTexture
        if closing then
            wipeTexture = wipeBackTexture
        else
            wipeTexture = wipeOutTexture
        end

        screenBuffer:captureAt(6)

        Graphics.drawScreen{
            texture = screenBuffer,priority = 6,
            shader = wipeShader,uniforms = {
                wipeTexture = wipeTexture,
                cutoff = t,
            },
        }
    end
end



function respawnRooms.onDraw()
    if Misc.isPaused() then
        blockEventManager.update()
        npcEventManager.update()
    end
end



function respawnRooms.onInitAPI()
    -- Reset
    registerEvent(respawnRooms,"onStart","setupResetVariables")
    registerEvent(respawnRooms,"onColorSwitch")
    registerEvent(respawnRooms,"onEvent")

    -- Rooms
    registerEvent(respawnRooms,"onStart","createRooms")
    registerEvent(respawnRooms,"onTick","updateRoomsOnTick")
    registerEvent(respawnRooms,"onTickEnd","updateRoomsOnTickEnd")
    registerEvent(respawnRooms,"onInputUpdate","updateRoomsOnInput")
    registerEvent(respawnRooms,"onCameraUpdate","boundCamera")
    registerEvent(respawnRooms,"onDraw","drawTransitionFade")

    -- Respawning
    registerEvent(respawnRooms,"onPlayerKill","onPlayerKill",false)
    registerEvent(respawnRooms,"onTick","updateRespawningOnTick")
    registerEvent(respawnRooms,"onInputUpdate","updateRespawningOnInput")
    registerEvent(respawnRooms,"onDraw","drawRespawnFade")

    -- Silly case
    registerEvent(respawnRooms,"onDraw")


    -- Custom events
    registerCustomEvent(respawnRooms,"onPreReset")
    registerCustomEvent(respawnRooms,"onPostReset")
    registerCustomEvent(respawnRooms,"onRoomEnter")
end


respawnRooms.resetSettings = {
    -- If true, event timers will reset, layer speeds will reset, and auto-start events will trigger again.
    eventsReset = true,
    -- If true, section settings (such as background and music) will reset.
    sectionsReset = true,

    -- If true, star coins will reset when dying if they have not been saved.
    starCoinsReset = false,

    -- If true, p-switches and the stopwatch effect will be reset when going through rooms (they always be reset when dying, regardless of this setting).
    timedSwitchesReset = false,
    -- If true, the 4 color switches and the ON/OFF switch will reset when going through rooms (they always be reset when dying, regardless of this setting).
    colorSwitchesReset = false,

    -- If true, the player's held NPC will be reset when going through a room.
    -- Also affects NPCs in Yoshi's mouth.
    resetHeldNPC = false,
}

respawnRooms.roomSettings = {
    -- Default options for the extra settings of each room.
    -- For quicksand, these'll always be used, no matter what.
    defaultOptions = {
        -- If set, this room will have "solid" walls and a death plane if there isn't an adjacent room.
        usePhysicalBounds = true,
        -- If set, any NPC's inside will be spawned when the player is in the room, regardless of if they are on camera.
        actAsSpawnZone = true,
        -- If set, most of the level will be reset (similar to when respawning) when this room is entered.
        resetWhenEntered = false,
    },

    -- If true, the level will be reset at the end of transition and not the start. Doesn't affect non-panning transitions.
    onlyResetAtEnd = false,

    -- The layer name that quicksand rooms are placed on.
    quicksandLayerName = "Rooms",

    -- The speed that the player will get (in pixels per frame) when entering the room from the bottom.
    -- If 0, there will be no speed boost.
    jumpFromBelowSpeed = -10,

    -- The type of camera movement for the transition. Can be NONE for no transition.
    -- Can be PAN_CONSTANT, PAN_SMOOTH, PAN_SINE, or PAN_QUAD to have the camera move between rooms.
    -- Can be FADE, MOSAIC, DIAMOND, ROTATING_SQUARE, DIAMOND_SWEEP, INWARD_SWEEP, or WIPE to have a fade between rooms.
    transitionType = respawnRooms.TRANSITION_TYPE.PAN_QUAD,

    -- The duration (in frames) that a camera transition lasts.
    panTransitionDuration = 40,

    -- The amount of time (in frames) that the screen will fade to black during a fade transition.
    fadeOutDuration = 32,
    -- The amount of time (in frames) that the screen will fade from black, back to gameplay during a fade transition.
    fadeBackDuration = 32,
    -- The amount of time (in frames) that the screen will remain completely black during a fade transition. This can be 0.
    fadeWaitTime = 4,
}

respawnRooms.respawnSettings = {
    -- If true, quick respawn will be enabled. When the player dies, there will be a brief transition and the level will reset without a loading screen.
    enabled = true,

    -- Powerup that the player will have when respawning.
    respawnPowerup = PLAYER_SMALL,

    -- If true, respawn BGO's will never be used, and the actual start point/checkpoints will be used instead.
    neverUseRespawnBGOs = false,
    -- The directions of each respawn BGO.
    respawnBGODirections = {
        [851] = DIR_RIGHT,
        [852] = DIR_LEFT,
    },

    -- The sound effect played when the player dies. Can be nil, a string, or a number.
    -- Default value is 38, which is the birdo spit sound.
    deathSound = 38,
    -- The amount of screen shake to have when the player dies. Can be 0 for none.
    deathEarthquake = 0,

    -- If true, the game will be paused while the transition is active.
    pauseDuringTransition = true,

    -- The type of transition to use.
    -- Can be NONE, FADE, MOSAIC, DIAMOND, ROTATING_SQUARE, DIAMOND_SWEEP, INWARD_SWEEP, or WIPE.
    transitionType = respawnRooms.TRANSITION_TYPE.MOSAIC,

    -- The amount of time (in frames) to wait between the player dying and the transition starting.
    deathAnimDuration = 0,
    -- The amount of time (in frames) that the screen will fade to black during the transition.
    fadeOutDuration = 32,
    -- The amount of time (in frames) that the screen will fade from black, back to gameplay during the transition.
    fadeBackDuration = 32,
    -- The amount of time (in frames) that the screen will remain completely black during the transition. This can be 0.
    fadeWaitTime = 4,
}


return respawnRooms