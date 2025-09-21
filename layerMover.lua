--[[

    layerMover.lua
    by MrDoubleA

]]

local piranhaPlant = require("npcs/ai/piranhaPlant")

local layerMover = {}


local GM_BLOCK_LOOKUP_MIN = readmem(0xB25758,FIELD_DWORD)
local GM_BLOCK_LOOKUP_MAX = readmem(0xB25774,FIELD_DWORD)

local GM_BLOCKS_SORTED = 0xB2C894


layerMover.layerEntityMap = {}
layerMover.hasInitialisedLayerEntityMap = false


layerMover.NPC_MOVEMENT_BEHAVIOUR = {
    -- Default: will select one of the other types based on config
    DEFAULT = 0,
    -- The NPC is not moved by the layer (except for its spawn position)
    UNAFFECTED = 1,
    -- The NPC's position is directly changed
    SET_POSITION = 2,
    -- The NPC's speed is set to match the layer's
    SET_SPEED = 3,
    -- Both the speed and position of the NPC is set (will generally cause it to move at double speed, unless speed doesn't move it like for vines)
    SET_POSITION_AND_SPEED = 4,
    -- The NPC is not moved, including even its spawn position
    DONT_MOVE_SPAWN = 5,
}

layerMover.npcBehaviourMap = {
    [37]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- SMB3 Thwomp
    [46]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Deprecated donut block
    [91]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED, -- SMB2 grass
    [192] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Deprecated SMW checkpoint
    [197] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Deprecated SMW goal tape
    [211] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED, -- Rinka block

    -- Deprecated Piranha Plants
    [8]   = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [51]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [52]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [74]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [93]  = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [245] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [256] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,
    [257] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION,

    -- X2 NPCs
    [421] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Paddle wheel
    [423] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED, -- Skewer
    [424] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED, -- Skewer
    [428] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- King Bill
    [429] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- King Bill
    [509] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Scuttlebug
    [572] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Frightlight
    [613] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Flutter
    [704] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Fire Chomp
    [707] = layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED, -- Spiky Fire Chomp

    -- Thwomps
    [295] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Thwomp
    [432] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Thwomp
    [435] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Thwomp
    [437] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION, -- Thwomp
    
    -- Bumpers
    [582] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [583] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [584] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [585] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [594] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [595] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [596] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [597] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [598] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [599] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [604] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
    [605] = layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED,
}


-- Returns a value representing how an NPC of a specific ID should react to layer movement.
function layerMover.getNPCBehaviour(npcID)
    local behaviour = layerMover.npcBehaviourMap[npcID]

    if behaviour ~= nil and behaviour ~= layerMover.NPC_MOVEMENT_BEHAVIOUR.DEFAULT then
        return layerMover.npcBehaviourMap[npcID]
    end

    local config = NPC.config[npcID]

    if config.isvine then
        return layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED
    end

    if config.iscoin then
        return layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION
    end

    if npcID > 292 then
        -- Reasonable(?) defaulting
        if config.nogravity and config.noblockcollision then
            if config.playerblock or config.playerblocktop or config.npcblock or config.npcblocktop then
                return layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED
            else
                return layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION
            end
        end
    end

    return layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED
end


local moverFunctions = {}
local moverMT = {__index = moverFunctions}


local function trackEntity(entity)
    local layerName = entity.layerName
    local entityList = layerMover.layerEntityMap[layerName]

    if entityList == nil then
        layerMover.layerEntityMap[layerName] = {entity}
    else
        table.insert(entityList,entity)
    end
end

function layerMover.refreshLayerEntityMap()
    layerMover.layerEntityMap = {}

    for _,block in Block.iterate() do
        trackEntity(block)
    end

    for _,bgo in BGO.iterate() do
        trackEntity(bgo)
    end

    for _,npc in NPC.iterate() do
        trackEntity(npc)
    end

    for _,liquid in ipairs(Liquid.get()) do
        trackEntity(liquid)
    end

    for _,warp in ipairs(Warp.get()) do
        trackEntity(warp)
    end

    layerMover.hasInitialisedLayerEntityMap = true
end


function moverFunctions:checkLayerEntityMap()
    if not layerMover.hasInitialisedLayerEntityMap then
        layerMover.refreshLayerEntityMap()
    end
end

local function iterateLayerEntities(layerName,index)
    local entityList = layerMover.layerEntityMap[layerName]

    if entityList == nil then
        return
    end

    index = index + 1

    while (true) do
        local entity = entityList[index]

        if entity == nil then
            return
        end

        if entity.isValid then
            return index,entity
        end

        table.remove(entityList,index)
    end
end


local function updateBlockIndex(block,oldLeft,oldRight)
    if not readmem(GM_BLOCKS_SORTED,FIELD_BOOL) then
        -- Alas, it would appear that the block array is already glooby...
        return
    end

    -- Update the FirstBlock and LastBlock arrays such that this block will be included in all of the rows that it is inside of
    -- A big improvement over Redigit's equivalent, which is to... clobber FirstBlock and LastBlock, thereby ruining block optimisation.
    -- This library was written largely out of spite for how awful the original layer movement code is, and block movement is a big part of that!
    local minGridIndex = math.max(0,math.floor(math.min(oldLeft,block.x)/32) + 8000)
    local maxGridIndex = math.min(16000,math.floor(math.max(oldRight,block.x + block.width)/32) + 8000)

    for gridIndex = minGridIndex,maxGridIndex do
        local minGridAddr = GM_BLOCK_LOOKUP_MIN + gridIndex*2
        local maxGridAddr = GM_BLOCK_LOOKUP_MAX + gridIndex*2

        if readmem(minGridAddr,FIELD_WORD) > block.idx then
            writemem(minGridAddr,FIELD_WORD,block.idx)
        end

        if readmem(maxGridAddr,FIELD_WORD) < block.idx then
            writemem(maxGridAddr,FIELD_WORD,block.idx)
        end
    end
end


local function moveEntity(entity,dx,dy,translationOnly)
    local entityType = type(entity)

    -- Blocks
    if entityType == "Block" then
        entity.x = entity.x + dx
        entity.y = entity.y + dy

        if not translationOnly then
            entity.speedX = dx
            entity.speedY = dy

            if dx == 0 and dy == 0 then
                entity.speedY = 0.001
            end
        end

        if dx ~= 0 then
            updateBlockIndex(entity,entity.x - dx,entity.x + entity.width - dx)
        end

        return
    end

    -- BGOs
    if entityType == "BGO" then
        entity.x = entity.x + dx
        entity.y = entity.y + dy

        if not translationOnly then
            entity.speedX = dx
            entity.speedY = dy
        end

        return
    end

    -- NPCs
    if entityType == "NPC" then
        if entity.isGenerator then
            entity.x = entity.x + dx
            entity.y = entity.y + dy

            return
        end

        if not entity:mem(0x124,FIELD_BOOL) then
            entity.x = entity.spawnX + (entity.spawnWidth - entity.width)*0.5
            entity.y = entity.spawnY + (entity.spawnHeight - entity.height)*0.5

            if entity.attachedLayerName ~= "" then
                local attachedLayerObj = Layer.get(entity.attachedLayerName)

                if attachedLayerObj ~= nil then
                    attachedLayerObj.speedX = dx
                    attachedLayerObj.speedY = dy
                end
            end

            return
        end

        local behaviour = layerMover.getNPCBehaviour(entity.id)

        if behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.DONT_MOVE_SPAWN then
            return
        end

        if behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED and not entity.isGenerator and entity.forcedState == NPCFORCEDSTATE_NONE then
            return
        end

        -- Set position directly
        if behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION
        or behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED
        or behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.UNAFFECTED
        or translationOnly
        then
            entity.x = entity.x + dx
            entity.y = entity.y + dy
        end

        -- Set speed
        if (behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED
        or behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED)
        and not translationOnly
        then
            entity.speedX = dx
            entity.speedY = dy
        end

        -- For the generator forced state, update the position that the NPC is coming out of
        if entity.forcedState == NPCFORCEDSTATE_WARP then
            if entity.forcedCounter2 == 1 or entity.forcedCounter2 == 3 then
                entity.forcedCounter1 = entity.forcedCounter1 + dy
            else
                entity.forcedCounter1 = entity.forcedCounter1 + dx
            end
        end
        
        -- For Piranha plants, move them and their home positions
        if piranhaPlant.idMap[entity.id] then
            local config = NPC.config[entity.id]
            local data = entity.data._basegame

            if config.isJumping then
                if config.isHorizontal then
                    entity.x = entity.x - dx
                else
                    entity.y = entity.y - dy
                end
            end

            if data.state ~= nil then
                if config.isHorizontal then
                    data.home = data.home + dx
                else
                    data.home = data.home + dy
                end
            end
        end

        return
    end

    entity.x = entity.x + dx
    entity.y = entity.y + dy
end

local function translateEntity(entity,dx,dy,translationOnly)
    local entityType = type(entity)

    if entityType == "Warp" then
        entity.entranceX = entity.entranceX + dx
        entity.entranceY = entity.entranceY + dy
        entity.exitX = entity.exitX + dx
        entity.exitY = entity.exitY + dy
        
        return
    end

    if entityType == "NPC" and layerMover.getNPCBehaviour(entity.id) ~= layerMover.NPC_MOVEMENT_BEHAVIOUR.DONT_MOVE_SPAWN then
        entity.spawnX = entity.spawnX + dx
        entity.spawnY = entity.spawnY + dy
    end

    if entityType == "Warp" then
        return
    end

    moveEntity(entity,dx,dy,translationOnly)
end

local function stopEntity(entity)
    local entityType = type(entity)

    if entityType == "Block" or entityType == "BGO" then
        entity.speedX = 0
        entity.speedY = 0

        return
    end

    if entityType == "NPC" then
        if entity.isGenerator then
            return
        end

        if not entity:mem(0x124,FIELD_BOOL) then
            if entity.attachedLayerName ~= "" then
                local attachedLayerObj = Layer.get(entity.attachedLayerName)

                if attachedLayerObj ~= nil then
                    attachedLayerObj:stop()
                end
            end

            return
        end

        local behaviour = layerMover.getNPCBehaviour(entity.id)

        -- Set speed
        if behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_SPEED
        or behaviour == layerMover.NPC_MOVEMENT_BEHAVIOUR.SET_POSITION_AND_SPEED
        then
            entity.speedX = 0
            entity.speedY = 0
        end

        return
    end
end


local function rotatePoint(x,y,pivot,rotationCos,rotationSin)
    local oldDifferenceX = x - pivot.x
    local oldDifferenceY = y - pivot.y

    local newDifferenceX = oldDifferenceX*rotationCos - oldDifferenceY*rotationSin
    local newDifferenceY = oldDifferenceX*rotationSin + oldDifferenceY*rotationCos

    return newDifferenceX - oldDifferenceX,newDifferenceY - oldDifferenceY
end

local function rotateEntity(entity,pivot,rotationCos,rotationSin,translationOnly)
    local entityType = type(entity)

    if entityType == "Warp" then
        local entranceDX,entranceDY = rotatePoint(entity.entranceX + entity.entranceWidth*0.5,entity.entranceY + entity.entranceHeight*0.5,pivot,rotationCos,rotationSin)
        local exitDX,exitDY = rotatePoint(entity.exitX + entity.exitWidth*0.5,entity.exitY + entity.exitHeight*0.5,pivot,rotationCos,rotationSin)

        entity.entranceX = entity.entranceX + entranceDX
        entity.entranceY = entity.entranceY + entranceDY
        entity.exitX = entity.exitX + exitDX
        entity.exitY = entity.exitY + exitDY
        
        return
    end

    if entityType == "NPC" and layerMover.getNPCBehaviour(entity.id) ~= layerMover.NPC_MOVEMENT_BEHAVIOUR.DONT_MOVE_SPAWN  then
        local spawnDX,spawnDY = rotatePoint(entity.spawnX + entity.spawnWidth*0.5,entity.spawnY + entity.spawnHeight*0.5,pivot,rotationCos,rotationSin)

        entity.spawnX = entity.spawnX + spawnDX
        entity.spawnY = entity.spawnY + spawnDY
    end

    local dx,dy = rotatePoint(entity.x + entity.width*0.5,entity.y + entity.height*0.5,pivot,rotationCos,rotationSin)

    moveEntity(entity,dx,dy,translationOnly)
end


-- Moves a layer by the given X and Y distance.
-- If set to true, the translationOnly argument will prevent speed values from being set on things like blocks.
function moverFunctions:translate(dx,dy,translationOnly)
    for _,entity in self:iterateLayerEntities() do
        translateEntity(entity,dx,dy,translationOnly)
    end
end

-- Rotates the objects on a layer around the given pivot.
-- If set to true, the translationOnly argument will prevent speed values from being set on things like blocks.
function moverFunctions:rotate(pivot,rotation,translationOnly)
    local rotationRad = math.rad(rotation)
    local rotationSin = math.sin(rotationRad)
    local rotationCos = math.cos(rotationRad)

    for _,entity in self:iterateLayerEntities() do
        rotateEntity(entity,pivot,rotationCos,rotationSin,translationOnly)
    end
end

-- Resets the speed of everything on the layer. This should always be called when a layer stops moving.
function moverFunctions:stop()
    for _,entity in self:iterateLayerEntities() do
        stopEntity(entity)
    end
end

-- Iterates through every "entity" on the mover's layer (i.e., NPCs, blocks, BGOs, etc. on the layer).
-- Example usage: for index,entity in mover:iterateLayerEntities() do
function moverFunctions:iterateLayerEntities()
    self:checkLayerEntityMap()

    return iterateLayerEntities,self.layerName,0
end


local function createLayerMover(layerName)
    local mover = setmetatable({},moverMT)

    mover.layerName = layerName

    return mover
end


setmetatable(layerMover,{
    __call = function(_,layerName)
        return createLayerMover(layerName)
    end,
})


return layerMover