--[[

    Layer Controllers
    by MrDoubleA

]]

local layerMover = require("layerMover")

local npcManager = require("npcManager")
local blockutils = require("blocks/blockutils")
local easing = require("ext/easing")

local layerControllers = {}


layerControllers.TIMING_MODE = {
    GLOBAL = 0,
    LOCAL = 1,
}

layerControllers.EASING_FUNCTION = {
    NONE = 0,
    SINE = 1,
    QUAD = 2,
    CUBIC = 3,
    QUART = 4,
    QUINT = 5,
    EXPO = 6,
    CIRC = 7,
    BACK = 8,
    ELASTIC = 9,
    BOUNCE = 10,
    OUT_BOUNCE = 11,
}

layerControllers.ACTIVATION_MODE = {
    ALWAYS = 0,
    WITHIN_RANGE = 1,
    BY_EVENT = 2,
}


layerControllers.controllerSharedSettings = {
    gfxwidth = 32,
	gfxheight = 32,

	width = 32,
	height = 32,

	gfxoffsetx = 0,
	gfxoffsety = 0,

	frames = 1,
	framestyle = 0,
	framespeed = 8,

	luahandlesspeed = true,
	nowaterphysics = true,
	cliffturn = false,
	staticdirection = true,

	npcblock = false,
	npcblocktop = false,
	playerblock = false,
	playerblocktop = false,

	nohurt = true,
	nogravity = true,
	noblockcollision = true,
	notcointransformable = true,
	nofireball = true,
	noiceball = true,
	noyoshi = true,

	jumphurt = true,
	spinjumpsafe = false,
	harmlessgrab = true,
	harmlessthrown = true,
	nowalldeath = false,

	ignorethrownnpcs = true,
    nogliding = true,
}


layerControllers.controllerIDList = {}
layerControllers.controllerIDMap = {}

layerControllers.activeControllers = {}

layerControllers.eventControllerMap = {}


layerControllers.secondLength = 64

layerControllers.unpausingGlobalTimer = 0
layerControllers.pausingGlobalTimer = 0


local easingFunctions = {
    [layerControllers.EASING_FUNCTION.NONE] = function(t)
        return t
    end,
    [layerControllers.EASING_FUNCTION.SINE] = function(t)
        return easing.inOutSine(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.QUAD] = function(t)
        return easing.inOutQuad(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.CUBIC] = function(t)
        return easing.inOutCubic(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.QUART] = function(t)
        return easing.inOutQuart(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.QUINT] = function(t)
        return easing.inOutQuint(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.EXPO] = function(t)
        return easing.inOutExpo(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.CIRC] = function(t)
        return easing.inOutCirc(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.BACK] = function(t)
        return easing.inOutBack(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.ELASTIC] = function(t)
        return easing.inOutElastic(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.BOUNCE] = function(t)
        return easing.inOutBounce(t,0,1,1)
    end,
    [layerControllers.EASING_FUNCTION.OUT_BOUNCE] = function(t)
        return easing.outBounce(t,0,1,1)
    end,
}


function layerControllers.registerController(npcID)
    npcManager.registerEvent(npcID, layerControllers, "onTickNPC", "onTickController")

    if Misc.inEditor() then
        npcManager.registerEvent(npcID, layerControllers, "onDrawNPC", "onDrawController")
    end

    table.insert(layerControllers.controllerIDList,npcID)
    layerControllers.controllerIDMap[npcID] = true

    layerMover.npcBehaviourMap[npcID] = layerMover.NPC_MOVEMENT_BEHAVIOUR.DONT_MOVE_SPAWN
end


local function getControllerTimer(npc)
    local settings = npc.data._settings

    if settings.timing.mode == layerControllers.TIMING_MODE.GLOBAL
    and settings.activationMode ~= layerControllers.ACTIVATION_MODE.BY_EVENT
    then
        -- Use a global timer
        if settings.timing.pauseDuringForcedState then
            return layerControllers.pausingGlobalTimer
        else
            return layerControllers.unpausingGlobalTimer
        end
    end

    -- Use the controller's local timer
    return npc.data.localTimer
end

local function shouldBeActive(npc)
    local settings = npc.data._settings

    if settings.activationMode == layerControllers.ACTIVATION_MODE.WITHIN_RANGE then
        -- Become active when on screen (or close enough to it - the margin setting determines th distance it can be away)
        local x = npc.x + npc.width*0.5
        local y = npc.y + npc.height*0.5

        local margin = (settings.activationMargin or 15)*32

        return (
            x > (camera.x - margin)
            and x < (camera.x + camera.width + margin)
            and y > (camera.y - margin)
            and y < (camera.y + camera.height + margin)
        )
    end

    if settings.activationMode == layerControllers.ACTIVATION_MODE.BY_EVENT then
        -- If the layer is active and its timer is still above zero, continue to be active
        local data = npc.data

        return (data.isActive and data.remainingMoveTime > 0)
    end

    return true
end


local activateController,initialiseController

function activateController(npc)
    local data = npc.data

    if data.isActive then
        return
    end

    if not data.initialised then
        initialiseController(npc)
    end

    local settings = npc.data._settings

    if settings.activationMode == layerControllers.ACTIVATION_MODE.BY_EVENT then
        data.remainingMoveTime = data.cycleDuration*(settings.eventActivationMoveCount or 1)
    end

    data.isActive = true
    data.justActivated = true

    table.insert(layerControllers.activeControllers,npc)
end


function initialiseController(npc)
    local settings = npc.data._settings
    local config = NPC.config[npc.id]
    local data = npc.data

    data.layerMover = layerMover(npc.layerName)
    
    data.movementDuration = settings.timing.movementDuration*layerControllers.secondLength
    data.waitDuration = settings.timing.waitDuration*layerControllers.secondLength
    data.cycleDuration = data.movementDuration + data.waitDuration

    data.remainingMoveTime = 0
    data.localTimer = 0

    data.isActive = false
    data.justActivated = false

    data.initialised = true

    if config.initialiseMovement ~= nil then
        config.initialiseMovement(npc)
    end

    if shouldBeActive(npc) then
        activateController(npc)
    end

    if settings.activationMode == layerControllers.ACTIVATION_MODE.BY_EVENT and settings.activationEventName ~= nil and settings.activationEventName ~= "" then
        local eventName = settings.activationEventName

        layerControllers.eventControllerMap[eventName] = layerControllers.eventControllerMap[eventName] or {}
        table.insert(layerControllers.eventControllerMap[eventName],npc)
    end
end

function layerControllers.onTickController(npc)
    local data = npc.data

    if not data.initialised then
        initialiseController(npc)
    end

    if not data.isActive and shouldBeActive(npc) then
        activateController(npc)
    end
end


local editorImages = {}

function layerControllers.onDrawController(npc)
    if not npc.data._settings.debug or not Misc.inEditor() then
        return
    end

    local data = npc.data

    if not data.initialised or not data.isActive then
        return
    end

    local config = NPC.config[npc.id]

    -- Draw "previews" for where blocks will be
    if config.debugGetPreviewsForPoint ~= nil and npc.layerName ~= "Default" then
        for _,entity in data.layerMover:iterateLayerEntities() do
            if type(entity) == "Block" and not entity.isHidden then
                local points = config.debugGetPreviewsForPoint(npc,entity.x + entity.width*0.5,entity.y + entity.height*0.5)

                for _,point in ipairs(points) do
                    Graphics.drawBox{
                        color = config.debugColor.. 0.35,
                        sceneCoords = true,centred = true,
                        priority = 1,
                        x = point.x,
                        y = point.y,
                        width = entity.width,
                        height = entity.height,
                    }
                end
            end
        end
    end

    -- Draw the path that the layer will take
    if config.debugGetPaths ~= nil then
        local hue,saturation,value = config.debugColor:toHSV()
        local lineColor = Color.fromHSV(hue,saturation*0.5,value,0.5)

        for _,path in ipairs(config.debugGetPaths(npc)) do
            local vertexCoords = {}
            local vertexCounter = 0

            for pointIndex,point in ipairs(path) do
                local previousPoint = path[pointIndex - 1] or point
                local nextPoint = path[pointIndex + 1] or point

                local rotation = math.atan2(nextPoint.y - previousPoint.y,nextPoint.x - previousPoint.x)

                vertexCoords[vertexCounter+1] = point.x + math.sin(rotation)*2
                vertexCoords[vertexCounter+2] = point.y - math.cos(rotation)*2
                vertexCoords[vertexCounter+3] = point.x - math.sin(rotation)*2
                vertexCoords[vertexCounter+4] = point.y + math.cos(rotation)*2

                vertexCounter = vertexCounter + 4
            end

            Graphics.glDraw{
                color = lineColor,
                sceneCoords = true,
                priority = 1.1,
                primitive = Graphics.GL_TRIANGLE_STRIP,
                vertexCoords = vertexCoords,
            }

            Graphics.drawBox{
                color = config.debugColor.. 0.5,
                sceneCoords = true,centred = true,
                priority = 1.2,
                x = path[1].x,
                y = path[1].y,
                width = 8,
                height = 8,
            }
        end
    end

    -- Draw where the layer currently is, relatively
    if config.debugGetCurrentOffset ~= nil then
        local offset = config.debugGetCurrentOffset(npc)

        Graphics.drawBox{
            color = config.debugColor.. 0.75,
            sceneCoords = true,centred = true,
            priority = 1.3,
            x = npc.x + npc.width*0.5 + offset.x,
            y = npc.y + npc.height*0.5 + offset.y,
            width = 10,
            height = 10,
        }
    end

    -- Draw the editor icon
    --[[if editorImages[npc.id] == nil then
        editorImages[npc.id] = Graphics.loadImageResolved("npc-".. npc.id.. "e.png")
    end

    Graphics.drawImageToSceneWP(editorImages[npc.id],npc.x,npc.y,0.5,1.4)]]
end


local layersPaused

local function updateController(npc)
    if not npc.isValid then
        return true
    end
    
    local data = npc.data

    if not data.isActive or not shouldBeActive(npc) then
        data.layerMover:stop()
        data.isActive = false
        return true
    end

    local settings = npc.data._settings
    local config = NPC.config[npc.id]

    -- Layer freezing
    if Defines.levelFreeze or (settings.timing.pauseDuringForcedState and layersPaused) then
        data.layerMover:stop()
        return
    end

    -- Increment timer
    if settings.timing.mode == layerControllers.TIMING_MODE.LOCAL
    or settings.activationMode == layerControllers.ACTIVATION_MODE.BY_EVENT
    then
        data.localTimer = data.localTimer + 1
    end

    if settings.activationMode == layerControllers.ACTIVATION_MODE.BY_EVENT then
        data.remainingMoveTime = math.max(0,data.remainingMoveTime - 1)
    end

    -- Actual movement
    local timer = getControllerTimer(npc)

    local moveIteration = math.floor(timer/data.cycleDuration)
    local moveTimer = math.min(1,(timer % data.cycleDuration)/data.movementDuration)

    if settings.easing.func ~= layerControllers.EASING_FUNCTION.NONE and moveTimer < 1 then
        -- Apply easing to the timer
        moveTimer = easingFunctions[settings.easing.func](moveTimer)
    end

    if config.updateMovement ~= nil then
        config.updateMovement(npc,moveTimer,moveIteration,data.justActivated)
    end

    data.justActivated = false

    return false
end

function layerControllers.onTick()
    -- Increment global timer values
    layersPaused = Layer.isPaused()

    if not Defines.levelFreeze then
        if not layersPaused then
            layerControllers.pausingGlobalTimer = layerControllers.pausingGlobalTimer + 1
        end

        layerControllers.unpausingGlobalTimer = layerControllers.unpausingGlobalTimer + 1
    end

    -- Update each controller
    local i = 1

    while (layerControllers.activeControllers[i] ~= nil) do
        local npc = layerControllers.activeControllers[i]

        local shouldRemove = updateController(npc)

        if shouldRemove then
            table.remove(layerControllers.activeControllers,i)
        else
            i = i + 1
        end
    end
end


function layerControllers.onEvent(eventName)
    -- Trigger controllers that are set to be activated by an event
    local controllers = layerControllers.eventControllerMap[eventName]

    if controllers ~= nil then
        for _,npc in ipairs(controllers) do
            if npc.isValid then
                activateController(npc)
            end
        end
    end
end


function layerControllers.onInitAPI()
    registerEvent(layerControllers,"onTick","onTick",false)
    registerEvent(layerControllers,"onEvent")
end


return layerControllers