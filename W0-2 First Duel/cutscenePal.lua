--[[

    cutscenePal.lua
    by MrDoubleA

    Tool for more easily creating cutscenes

    Documentation is included throughout the file.

]]

local animationPal = require("animationPal")
local easing = require("ext/easing")

local textplus = require("textplus")

local handycam = require("handycam")

local cutscenePal = {}

local littleDialogue
pcall(function() littleDialogue = require("littleDialogue") end)


local VANILLA_PAUSED_ADDR = 0xB250E2
local VANILLA_MESSAGE_ADDR = 0xB250E4


cutscenePal.disableTalk = false -- for testing: if true, actors' :talk function won't do anything.


cutscenePal.activeScene = nil
cutscenePal.barsScene = nil
cutscenePal.skippingScene = nil

cutscenePal.actors = {}


cutscenePal.SKIP_STATE = {
    INACTIVE = 0,
    ENTER = 1,
    BLANK = 2,
    EXIT = 3,
}


-- Scene objects
do
    local sceneMT = {}
    local sceneFunctions = {}

    sceneMT.__type = "Scene"


    --[[

        Cutscene instance properties:

        name                (string)        The internal name of the cutscene. Doesn't do anything on its own, however
                                            you can use it in your own code to identify an active cutscene.
        data                (table)         A general-purpose table that you can use to store things related to the
                                            cutscene, similar to an NPC or block's data table.

        mainRoutineFunc     (function)      A function that will be run as a routine when the cutscene starts. When the routine ends,
                                            so will the cutscene. Most of your code for the cutscene should go in here.
        drawFunc            (function)      A function that will be called each frame to draw stuff for the cutscene if it is active.
                                            Useful for additional effects such as shaders.
        updateFunc          (function)      A function that will be called each frame to update stuff for the cutscene if it is active.
                                            Note that it will still run if the game is paused.
        startFunc           (function)      A function that will be called when the cutscene starts.
        stopFunc            (function)      A function that will be called when the cutscene stops, whether by natural means or by skipping.

        disablesHUD         (boolean)       If true, the HUD will be disabled for the cutscene.
        forcesInputs        (boolean)       If true, the player's keys will be forced to whatever in the forcedKeys table
                                            for the duration of the cutscene.
        forcedKeys          (table)         A table including states for each of the player's players, used for if
                                            forcesInputs is true. Defaults to having all keys be false.

        hasBars             (boolean)       If true, "cinematic bars" will appear for the cutscene. The look of these bars
                                            can be customised through cutscenePal.defaultDrawBarsFunc or the scene's drawBarsFunc.
        barsEnterDuration   (number)        The number of frames it takes for the bars to fully come in. If nil, will default
                                            to the value of cutscenePal.defaultBarEnterDuration.
        barsExitDuration    (number)        The number of frames it takes for the bars to fully leave the screen. If nil, will default
                                            to the value of cutscenePal.defaultBarExitDuration.
        drawBarsFunc        (function)      A function that is run to draw the bars. Takes three arguments: the scene itself, progress,
                                            a 0-to-1 value that represents how far in they are, and closing, a boolean that says whether
                                            or not the bars are currently closing. If nil, will default to the function
                                            cutscenePal.defaultDrawBarsFunc.

        canSkip             (boolean)       If true, the cutscene can be skipped by pressing drop item while it is active. The transition
                                            it uses can be customised through cutscenePal.defaultDrawSkipFunc or the scene's drawSkipFunc.
        skipEnterDuration   (number)        The number of frames it takes for the transition to fully come in. If nil, will default
                                            to the value of cutscenePal.defaultSkipEnterDuration.
        skipExitDuration    (number)        The number of frames it takes for the transition to fully leave the screen. If nil, will default
                                            to the value of cutscenePal.defaultSkipExitDuration.
        skipBlankDuration   (number)        The number of frames that the screen will be completely blank during the transition. If nil,
                                            will default to the value of cutscenePal.defaultSkipBlankDuration.
        drawSkipFunc        (function)      A function that is run to draw the skip transition. Takes three arguments: the scene itself,
                                            progress, a 0-to-1 value that represents how far in the transition is, and closing, a boolean
                                            that says whether or not the bars are currently closing. If nil, will default to the function
                                            cutscenePal.defaultDrawSkipFunc.
        skipRoutineFunc     (function)      A function that will be run as a routine while skipping. The skipping will only finish once
                                            the routine has. Note that you can still skip a cutscene without this, and that this routine
                                            doesn't necessarily have to wait at all.
        skipSound           (sound/number)  A sound (sound effect, string, number or nil) to play when the cutscene is skipped.
        
        

        mainRoutineObj      (Routine)       Stores the main routine object, from mainRoutineFunc.
        skipRoutineObj      (Routine)       Stores the skip routine object, from mainRoutineFunc.
        barsEnterProgress   (number)        The 0-to-1 value passed into drawBarsFunc, representing how far in the bars are.
        skipEnterProgress   (number)        The 0-to-1 value passed into drawSkipFunc, representing how far in the transition is.
        skipState           (number)        The current state of the skip transition, according to the enums from cutscenePal.SKIP_STATE.
        skipTimer           (number)        Used for handling the skip state.
        childRoutines       (table)         Stores any child routines run via :runChildRoutine. Mostly for internal use.
        childActors         (table)         Stroes any child actors created via :spawnChildActor. Mostly for internal use.

    ]]


    function sceneMT:__index(key)
        if key == "playerInactive" then
            return self._playerInactive
        end

        return sceneFunctions[key]
    end

    function sceneMT:__newindex(key,value)
        if key == "playerInactive" then
            self:_setPlayerInactive(value)
            return
        end

        rawset(self,key,value)
    end


    -- Creates a new cutscene object. Its only argument is, optionally, its internal name.
    -- All other properties can be set up later using the object.
    function cutscenePal.newScene(name)
        local scene = setmetatable({},sceneMT)

        scene.name = name or ""

        scene.data = {}

        scene.childRoutines = {}
        scene.childActors = {}


        scene.forcesInputs = true
        scene:resetForcedInputs()

        scene.barsEnterProgress = 0
        scene.hasBars = true

        scene.disablesHUD = true

        scene.canSkip = false

        scene._playerInactive = false
        scene._oldPlayerForcedState = 0
        scene._oldPlayerForcedTimer = 0

        return scene
    end


    -- Returns whether the scene is the current active scene.
    function sceneFunctions:isActive()
        return (cutscenePal.activeScene == self)
    end

    -- Starts the cutscene. If another cutscene is already active, it will be aborted.
    function sceneFunctions:start()
        -- Stop the active cutscene, if there is one
        if cutscenePal.activeScene ~= nil then
            cutscenePal.activeScene:stop()
        end

        cutscenePal.activeScene = self
        cutscenePal.barsScene = self

        self.barsEnterProgress = 0

        self:resetForcedInputs()

        -- Start the scene
        if self.mainRoutineFunc ~= nil then
            self.mainRoutineObj = Routine.run(self.mainRoutineFunc,self)
        end

        if self.startFunc ~= nil then
            self:startFunc()
        end

        if cutscenePal.defaultStartFunc ~= nil then
            cutscenePal.defaultStartFunc(self)
        end

        if self.disablesHUD then
            Graphics.activateHud(false)
        end
    end

    -- Immediately aborts the cutscene, if it is active.
    function sceneFunctions:stop()
        if cutscenePal.activeScene ~= self then
            return
        end

        -- Abort the main routine
        if self.mainRoutineObj ~= nil and self.mainRoutineObj.isValid and self.mainRoutineObj.waiting then
            self.mainRoutineObj:abort()
        end

        -- Abort and clear child routines
        for i = 1,#self.childRoutines do
            local routineObj = self.childRoutines[i]

            if routineObj.isValid and routineObj.waiting then
                routineObj:abort()
            end

            self.childRoutines[i] = nil
        end

        -- Delete and clear child actors
        for i = 1,#self.childActors do
            local actor = self.childActors[i]

            if actor.isValid then
                actor:remove()
            end
        end


        if self.disablesHUD then
            Graphics.activateHud(true)
        end

        self:setPlayerIsInactive(false)

        cutscenePal.activeScene = nil


        if self.stopFunc ~= nil then
            self:stopFunc()
        end

        if cutscenePal.defaultStopFunc ~= nil then
            cutscenePal.defaultStopFunc(self)
        end
    end

    -- Starts skipping the cutscene, if it is active.
    function sceneFunctions:skip()
        for _,routineObj in ipairs(self.childRoutines) do
            if routineObj.isValid and routineObj.waiting then
                routineObj:pause()
            end
        end

        if self.mainRoutineObj ~= nil and self.mainRoutineObj.isValid and self.mainRoutineObj.waiting then
            self.mainRoutineObj:pause()
        end

        if self.skipSound ~= nil then
            SFX.play(self.skipSound)
        elseif cutscenePal.defaultSkipSound ~= nil then
            SFX.play(cutscenePal.defaultSkipSound)
        end

        self.skipState = cutscenePal.SKIP_STATE.ENTER
        self.skipTimer = 0
        self.skipEnterProgress = 0

        cutscenePal.skippingScene = self

        Misc.pause()
    end


    -- Resets the inputs used if forcesInputs is enabled to a state where all are not held.
    function sceneFunctions:resetForcedInputs()
        self.forcedKeys = {
            jump = false,run = false,altJump = false,altRun = false,
            up = false,down = false,left = false,right = false,
            dropItem = false,pause = false,
        }
    end

    -- Sets the player inactive effect. When true, the player is made intangible and invisible.
    -- Useful for replacing the player with an actor for the cutscene or other shenanigans.
    -- When the cutscene stops, the effect will be disabled.
    function sceneFunctions:setPlayerIsInactive(enabled)
        if self._playerInactive == enabled then
            return
        end

        if enabled then
            self._oldPlayerForcedState = player.forcedState
            self._oldPlayerForcedTimer = player.forcedTimer

            player.forcedState = FORCEDSTATE_SWALLOWED
            player.forcedTimer = player.idx
            player:mem(0xBA,FIELD_WORD,player.idx)
        else
            player.forcedState = self._oldPlayerForcedState
            player.forcedTimer = self._oldPlayerForcedTimer
            player:mem(0xBA,FIELD_WORD,0) -- only used for multiplayer, fine to reset here
        end

        self._playerInactive = enabled
    end

    -- Returns whether the player inactive effect is enabled.
    function sceneFunctions:getPlayerIsInactive()
        return self._playerInactive
    end


    -- Runs a routine with Routine.run. However, it will be tied to the cutscene.
    -- This means that if the cutscene stops, any child routines will be aborted.
    function sceneFunctions:runChildRoutine(...)
        if cutscenePal.activeScene ~= self then
            error("Cannot run child routine for an inactive cutscene",2)
        end

        local routineObj = Routine.run(...)

        table.insert(self.childRoutines,routineObj)

        return routineObj
    end

    -- Spawns an actor. However, it will be tied to the cutscene.
    -- This means that if the cutscene stops, any child actors will be remove.d
    function sceneFunctions:spawnChildActor(x,y)
        if cutscenePal.activeScene ~= self then
            error("Cannot spawn child routine for an inactive cutscene",2)
        end

        return cutscenePal.spawnActor(x,y,self)
    end
end


-- Actors
do
    local actorMT = {}
    local actorFunctions = {}

    actorMT.__type = "Actor"

    --[[

        Properties for actors:

        data                (table)         A general-purpose table that you can use to store things related to the
                                            actor, similar to an NPC or block's data table.

        width               (number)        The width of the actor's hitbox.
        height              (number)        The height of the actor's hitbox.
        x                   (number)        X position of the actor, based on the top left of the hitbox.
        y                   (number)        Y position of the actor, based on the top left of the hitbox.

        direction           (number)        Direction that the actor faces, either -1 or 1.

        speedX              (number)        Horizontal speed of the actor.
        speedY              (number)        Vertical speed of the actor.

        isInvisible         (boolean)       If true, the actor will not be rendered, outside of its drawFunc.
        isFrozen            (boolean)       If true, the actor will not be updated, outside of its updateFunc.

        gravity             (number)        The actor's gravity, applied every frame.
        terminalVelocity    (number)        Maximum Y speed of the actor. If 0, does not apply.

        centre              (Vector2)       A vector, representing the middle centre of the actor's hitbox.
                                            Note that it can only be set through direct assignment.
        center              (Vector2)       Alias for centre.
        bottomCentre        (Vector2)       A vector, representing the bottom centre of the actor's hitbox.
                                            Note that it can only be set through direct assignment.
        bottomCenter        (Vector2)       Alias for bottomCentre.

        useAutoFloor        (boolean)       If true, the actor will use a very simple collision check to let
                                            it stand on the floor below it. Note that this does NOT handle walls,
                                            ceilings, or solid NPCs!
        floorY              (number)        If set, the NPC will not go lower than this Y position. If
                                            useAutoFloor is also true, then it will be used if it is higher than
                                            the floor found by auto floor.

        updateWhilePaused   (boolean)       If true, the actor will update even while the game is paused.

        spriteRotation      (number)        Rotation of the actor's sprite, in degrees.
        spriteRotationSpeed (number)        Rotation applied to spriteRotation each frame, in degrees.
        spriteScale         (Vector2)       Scaling of the actor's sprite.
        spriteOffset        (Vector2)       Offset of the actor's sprite.
        spritePivot         (Vector2)       The pivot used for the actor's sprite.
        spritePivotOffset   (Vector2)       An offset, in pixels, to the sprite's pivot.

        frames              (Vector2)       Number of frames that the actor's image has. If specified,
                                            frameWidth/frameHeight are ignored.

        image               (image)         Image used for the actor.
        sprite              (Sprite)        Sprite object used for rendering. Should not be set directly.
        priority            (number)        Render priority for the actor.
        color               (Color)         The coloring tint used when rendering the sprite.
        shader              (Shader)        A shader used when rendering the sprite.
        uniforms            (table)         Uniforms for the sprite's shaders.
        attributes          (table)         Attributes for the sprite's shaders.

        updateFunc          (function)      A function run every time the actor updates. Passes the actor as an argument.
        drawFunc            (function)      A function run every time the actor is drawn. Passes the actor as an argument.

    ]]


    function actorMT:__index(key)
        if key == "centre" or key == "center" then
            return vector(self.x + self.width*0.5,self.y + self.height*0.5)
        elseif key == "bottomCentre" or key == "bottomCenter" then
            return vector(self.x + self.width*0.5,self.y + self.height)
        end

        return actorFunctions[key]
    end

    function actorMT:__newindex(key,value)
        if key == "centre" or key == "center" then
            self.x = value.x - self.width*0.5
            self.y = value.y - self.height*0.5
            return
        elseif key == "bottomCentre" or key == "bottomCenter" then
            self.x = value.x - self.width*0.5
            self.y = value.y - self.height
            return
        end

        rawset(self,key,value)
    end


    -- Sets the hitbox size of the actor.
    function actorFunctions:setSize(width,height)
        self.x = self.x + (self.width - width)*0.5
        self.y = self.y + self.height - height
        self.width = width
        self.height = height
    end

    -- Returns a collider box with the position and size of the actor's hitbox.
    -- Optionally, 'marin' can be provided, extending the effective hitbox.
    function actorFunctions:makeColliderBox(margin)
        margin = margin or 0

        return Colliders.Box(self.x - margin,self.y - margin,self.width + margin*2,self.height + margin*2)
    end

    -- Returns if this actor is colliding with another actor. Much like
    -- :makeColliderBox, a margin can be provided.
    function actorFunctions:collidesWithActor(actorB,margin)
        local colliderA = self:makeColliderBox(margin)
        local colliderB = actorB:makeColliderBox(0)

        return Colliders.collide(colliderA,colliderB)
    end


    -- Sets the number of frames the actor's sprite has, using the size of each frame.
    function actorFunctions:setFrameSize(frameWidth,frameHeight)
        self.frames.x = self.image.width/frameWidth
        self.frames.y = self.image.height/frameHeight
    end

    -- Sets up the animator's actor. Takes the same arguments as animationPal.createAnimator.
    function actorFunctions:setUpAnimator(args)
        self.animator = animationPal.createAnimator(args)
        return self.animator
    end

    -- Sets the actor's animation, if it has an animator.
    function actorFunctions:setAnimation(name,speed,forceRestart)
        if self.animator ~= nil then
            self.animator:setAnimation(name,speed,forceRestart)
        end
    end

    -- Returns the current frame from the animator. If there is no animator, (1,1) will be returned.
    function actorFunctions:getFrame()
        if self.animator ~= nil then
            return self.animator.currentFrame
        else
            return vector.one2
        end
    end

    -- For a routine, waits until the current animation has finished.
    function actorFunctions:waitUntilAnimationFinished()
        while (self.animator ~= nil and not self.animator.animationFinished) do
            Routine.skip(self.updateWhilePaused)
        end
    end


    -- Casts a ray down from the actor to find a solid floor. You may also be interested in the :findFloor method or the useAutoFloor property.
    function actorFunctions:findAutoFloor()
        local startY = self.y + self.height - self.speedY - 8
        local startXA = self.x - 0.01
        local startXB = self.x + self.width - 0.01

        local raycastDistance = vector(0,4096)

        local collider = Colliders.Box(self.x - 1,startY,self.width + 2,raycastDistance.y)
        local blocks = Colliders.getColliding{a = collider,b = Block.SOLID.. Block.SEMISOLID,btype = Colliders.BLOCK}

        if blocks[1] == nil then
            return nil
        end

        local hitA,hitPointA,_,_ = Colliders.raycast(vector(startXA,startY),raycastDistance,blocks,self.debug)
        local hitB,hitPointB,_,_ = Colliders.raycast(vector(startXB,startY),raycastDistance,blocks,self.debug)

        if hitA then
            if hitB then
                return math.min(hitPointA.y,hitPointB.y)
            else
                return hitPointA.y
            end
        elseif hitB then
            return hitPointB.y
        end

        return nil
    end

    -- Returns where the actor's "floor" position is, whether it uses its own value or the useAutoFloor property.
    function actorFunctions:findFloor()
        if self.useAutoFloor then
            local autoFloorY = self:findAutoFloor()

            if self.floorY == nil or autoFloorY <= self.floorY then
                return autoFloorY
            end
        end

        return self.floorY
    end

    -- Teleports the actor to its floor if possible, using :findFloor.
    function actorFunctions:snapToFloor()
        local floorY = self:findFloor()

        if floorY ~= nil then
            self.y = floorY - self.height
        end
    end


    -- Sets the actor's speed such that it will jump to the given point.
    function actorFunctions:setJumpSpeed(distanceX,distanceY,speedPerBlock)
        if distanceX == 0 then
            self.speedX = 0
            self.speedY = 0
        end
        
        self.speedX = (speedPerBlock/32)*distanceX

        local t = math.max(1,math.abs(distanceX/self.speedX))

        self.speedY = distanceY/t - self.gravity*t*0.5
    end

    -- For a routine, causes the actor to jump, optionally including a rise, fall and land animation.
    -- It accepts 3 types of arguments that can set its speed:
    --    speedX + speedY: directly sets speed
    --    distanceX + distanceY + speedPerBlock: sets speed using :setJumpSpeed
    --    goalX + goalY + speedPerBlock: sets speed using :setJumpSpeed
    -- Optionally, it accepts the arguments 'riseAnimation', 'fallAnimation', and 'landAnimation'.
    -- If resetSpeed is passed as true, X speed will be reset upon landing.
    -- If setDirection is passed as true, the actor will face in the direction it is jumping in (if applicable).
    -- If setPosition is passed as true, the actor's position will be set to the goal position upon landing (if applicable.)
    function actorFunctions:jumpAndWait(args)
        -- Set speed
        local goalX,goalY

        if args.speedX ~= nil and args.speedY ~= nil then
            self.speedX = args.speedX
            self.speedY = args.speedY
        elseif args.distanceX ~= nil and args.distanceY ~= nil then
            self:setJumpSpeed(args.distanceX,args.distanceY,args.speedPerBlock or 0.75)

            goalX = self.x + self.width*0.5 + args.distanceX
            goalY = self.y + self.height + args.distanceY
        elseif args.goalX ~= nil and args.goalY ~= nil then
            self:setJumpSpeed(args.goalX - (self.x + self.width*0.5),args.goalY - (self.y + self.height),args.speedPerBlock or 0.75)

            goalX = args.goalX
            goalY = args.goalY
        end

        if args.setDirection and self.speedX ~= 0 then
            self.direction = math.sign(self.speedX)
        end

        -- Rising
        if args.riseAnimation ~= nil then
            self:setAnimation(args.riseAnimation)
        end

        -- Wait for falling
        if self.isOnFloor then
            Routine.skip()
        end

        while (self.speedY <= 0 and not self.isOnFloor) do
            Routine.skip()
        end

        -- Falling
        if args.fallAnimation ~= nil then
            self:setAnimation(args.fallAnimation)
        end

        -- Wait until touching floor
        while (not self.isOnFloor) do
            Routine.skip()
        end

        -- Landing
        if args.landAnimation ~= nil then
            self:setAnimation(args.landAnimation)
        end

        if goalX ~= nil and goalY ~= nil and args.setPosition then
            self.x = goalX - self.width*0.5
            self.y = goalY - self.height
        end

        if args.resetSpeed then
            self.speedX = 0
        end

        self.speedY = 0
    end

    -- For a routine, causes the actor to walk to a given X position.
    -- Requires 'goal' as an argument, to define the position that the actor will walk to.
    -- Requires 'speed' as an argument, to define how fast it will move.
    -- Optionally, it accepts 'walkAnimation' and 'walkAnimationSpeed' to define its animation.
    -- Optionally, it accepts 'stopAnimation' to define its animation after it is done walking.
    -- Optionally, it accepts 'setDirection', which will make the actor face the direction that it moves in.
    function actorFunctions:walkAndWait(args)
        -- Start walking
        local distance = args.goal - (self.x + self.width*0.5)

        if distance ~= 0 then
            -- Set animation
            if args.walkAnimation ~= nil then
                self:setAnimation(args.walkAnimation,args.walkAnimationSpeed or 1)
            end

            -- Loop until we get to the goal
            while (true) do
                local newDistance = args.goal - (self.x + self.width*0.5)
                local newSign = math.sign(newDistance)

                if newSign ~= math.sign(distance) then
                    break
                end

                if args.setDirection then
                    self.direction = newSign
                end

                self.speedX = args.speed*newSign

                Routine.skip()
            end
        end

        -- Stop
        if args.stopAnimation ~= nil then
            self:setAnimation(args.stopAnimation)
        end

        self.x = args.goal - self.width*0.5
        self.speedX = 0
    end

    -- Opens a littleDialogue text box, if it is installed. Accepts all of the arguments of
    -- littleDialogue.create. If speakerObj is not specified, it will default to the actor
    -- itself. If pauses is not specified, it will default to false.
    -- If littleDialogue is not installed, it will use a vanilla text box, only accepting text as an argument.
    function actorFunctions:talk(args)
        if cutscenePal.disableTalk then
            return nil
        end

        if littleDialogue == nil then
            -- Vanilla text boxes
            for _,text in ipairs(args.text or args) do
                Text.showMessageBox(text)
            end

            return
        end

        -- Form arguments to use for littleDialogue
        args = table.clone(args)
        
        if args.text == nil and args[1] ~= nil then
            args.text = args
        end
        
        args.speakerObj = args.speakerObj or self
        args.pauses = args.pauses or false

        local box = littleDialogue.create(args)

        table.insert(self.childTextBoxes,box)

        return box
    end

    -- For a routine, same as :talk, except it will wait until the dialogue has finished.
    -- Also, if littleDialogue is installed, it optionally accepts 'talkAnimation' and 'idleAnimation' to define its animation.
    function actorFunctions:talkAndWait(args)
        local box = self:talk(args)

        while (box ~= nil and box.isValid) do
            if not box.settings.typewriterEnabled or not box.typewriterFinished then
                if args.talkAnimation ~= nil then
                    self:setAnimation(args.talkAnimation)
                end
            elseif args.idleAnimation ~= nil then
                self:setAnimation(args.idleAnimation)
            end

            Routine.skip(true)
        end

        if args.idleAnimation ~= nil then
            self:setAnimation(args.idleAnimation)
        end

        return box
    end


    -- Deletes an actor. Note that it technically won't be immediately deleted, but rather deleted on the next available frame.
    function actorFunctions:remove()
        for _,box in ipairs(self.childTextBoxes) do
            box.state = littleDialogue.BOX_STATE.REMOVE
        end

        self._toRemove = true
    end

    -- Updates the actor, mostly for internal use.
    function actorFunctions:update()
        -- Run extra update function
        if self.updateFunc ~= nil then
            self:updateFunc()
        end

        if not self.isFrozen then
            -- Gravity
            self.speedY = self.speedY + self.gravity

            if self.terminalVelocity ~= 0 then
                self.speedY = math.min(self.terminalVelocity,self.speedY)
            end

            -- Move
            self.spriteRotation = self.spriteRotation + self.spriteRotationSpeed

            self.x = self.x + self.speedX
            self.y = self.y + self.speedY

            -- Floors system
            local floorY = self:findFloor()

            if floorY ~= nil then
                if (self.y + self.height) >= floorY then
                    self.y = floorY - self.height
                    self.speedY = 0

                    self.isOnFloor = true
                else
                    self.isOnFloor = false
                end
            else
                self.isOnFloor = false
            end

            -- Animation
            if self.animator ~= nil then
                self.animator:update()
            end
        end
    end


    -- Sets up properties for the actor's sprite. It takes several arguments, which will overwrite the actor's respective properties.
    function actorFunctions:setUpSprite(x,y,direction,rotation,scale)
        -- Default arguments
        x = x or self.x
        y = y or self.y
        direction = direction or self.direction

        rotation = rotation or self.spriteRotation
        scale = scale or self.spriteScale

        -- Create a new sprite, if necessary
        if self.sprite == nil or self.sprite.texture ~= self.image or self.sprite.frames ~= self.frames then
            self.sprite = Sprite{texture = self.image,frames = self.frames}
        end

        -- Set all of its properties up
        self.sprite.x = x + self.width*0.5 + self.spriteOffset.x*direction + self.spritePivotOffset.x
        self.sprite.y = y + self.height + self.spriteOffset.y + self.spritePivotOffset.y

        self.sprite.scale.x = scale.x*direction*self.imageDirection
        self.sprite.scale.y = scale.y
        
        self.sprite.rotation = rotation

        self.sprite.pivot = vector(
            self.spritePivot.x + self.spritePivotOffset.x/(self.image.width/self.frames.x),
            self.spritePivot.y + self.spritePivotOffset.y/(self.image.height/self.frames.y)
        )
        self.sprite.texpivot = self.sprite.pivot
    end

    -- Draws the actor's sprite. It takes several arguments, which will overwrite the actor's respective properties.
    function actorFunctions:drawSprite(frame,priority,sceneCoords,color,shader,uniforms,attributes)
        -- Default arguments
        frame = frame or self:getFrame()
        priority = priority or self.priority

        color = color or self.color

        shader = shader or self.shader
        uniforms = uniforms or self.uniforms
        attributes = attributes or self.attributes
        
        if sceneCoords == nil then
            sceneCoords = true
        end

        -- Draw the sprite
        self.sprite:draw{
            shader = shader,uniforms = uniforms,attributes = attributes,
            priority = priority,color = color,sceneCoords = sceneCoords,
            frame = frame,
        }
    end

    -- Called whenever the actor needs to be drawn.
    function actorFunctions:draw()
        -- Run extra render function
        if self.drawFunc ~= nil then
            self:drawFunc()
        end

        -- Draw debug hitbox
        if self.debug then
            Graphics.drawBox{
                color = Color.red.. 0.7,priority = -1,sceneCoords = true,
                x = self.x,y = self.y,width = self.width,height = self.height,
            }
        end

        -- Create sprite if necessary
        if self.isInvisible or self.image == nil then
            return
        end

        self:setUpSprite()
        self:drawSprite()
    end


    -- Creates a new actor.
    function cutscenePal.spawnActor(x,y,parentScene)
        local actor = setmetatable({},actorMT)

        -- Set basic variables
        actor.data = {}

        actor.width = 32
        actor.height = 32

        actor.x = x - actor.width*0.5
        actor.y = y - actor.height

        actor.imageDirection = DIR_RIGHT
        actor.direction = DIR_RIGHT

        actor.speedX = 0
        actor.speedY = 0

        actor.gravity = 0
        actor.terminalVelocity = 0

        actor.isOnFloor = false
        actor.useAutoFloor = false
        actor.floorY = nil

        actor.isInvisible = false
        actor.isFrozen = false
    
        actor.updateWhilePaused = false

        actor.spriteRotation = 0
        actor.spriteRotationSpeed = 0
        actor.spriteScale = vector.one2
        actor.spriteOffset = vector.zero2
        actor.spritePivot = vector(0.5,1)
        actor.spritePivotOffset = vector.zero2

        actor.frames = vector.one2

        actor.priority = -44
        actor.color = Color.white

        actor.shader = nil
        actor.uniforms = {}
        actor.attributes = {}

        actor.childTextBoxes = {}

        actor.debug = false


        actor._toRemove = false
        actor.isValid = true

        table.insert(cutscenePal.actors,actor)

        if parentScene ~= nil then
            table.insert(parentScene.childActors,actor)
        end

        return actor
    end
end


-- Convenience functions
do
    local handycamPropertyList = {"x","y","rotation","zoom","targets","xOffset","yOffset"}

    local function handycamIsTransitioning()
        local handycamObj = rawget(handycam,1)

        if handycamObj == nil then
            return false
        end

        for _,k in ipairs(handycamPropertyList) do
            local v = handycamObj._properties[k]

            if type(v) == "table" and v._transition then
                return true
            end
        end

        return false
    end

    -- For a routine, waits until handycam is no longer transitioning any of its values.
    function cutscenePal.waitUntilTransitionFinished()
        while (handycamIsTransitioning()) do
            Routine.skip(true)
        end
    end
end


local function barsAreClosing()
    return (cutscenePal.barsScene ~= cutscenePal.activeScene or not cutscenePal.barsScene.hasBars)
end

function cutscenePal.canSkip()
    local scene = cutscenePal.activeScene

    if cutscenePal.skippingScene == scene then
        return false
    end

    if not scene.canSkip then
        return false
    end

    if mem(VANILLA_PAUSED_ADDR,FIELD_BOOL) then
        return false
    end

    return true
end


function cutscenePal.onInputUpdate()
    -- Update active scene
    local scene = cutscenePal.activeScene

    if scene ~= nil then
        -- Stop the active scene if it has finished
        if scene.mainRoutineObj ~= nil and not scene.mainRoutineObj.isValid then
            scene:stop()
        end

        -- Remove unnecessary child routines
        for i = #scene.childRoutines,1,-1 do
            local routineObj = scene.childRoutines[i]

            if not routineObj.isValid then
                table.remove(scene.childRoutines,i)
            end
        end

        -- Remove unnecessary child actors
        for i = #scene.childActors,1,-1 do
            local actor = scene.childActors[i]

            if actor._toRemove then
                table.remove(scene.childActors,i)
            end
        end

        -- Set inputs if they're forced
        if scene.forcesInputs and not mem(VANILLA_PAUSED_ADDR,FIELD_BOOL) then
            for k,_ in pairs(player.keys) do
                player.keys[k] = scene.forcedKeys[k]
            end
        end

        -- Update function
        if scene ~= nil and scene.updateFunc ~= nil then
            scene:updateFunc()
        end

        if cutscenePal.defaultUpdateFunc ~= nil then
            cutscenePal.defaultUpdateFunc(scene)
        end
    end

    -- Update bars
    local scene = cutscenePal.barsScene

    if scene ~= nil then
        if barsAreClosing() then
            scene.barsEnterProgress = math.max(0,scene.barsEnterProgress - 1/(scene.barsExitDuration or cutscenePal.defaultBarExitDuration))

            if scene.barsEnterProgress <= 0 and cutscenePal.activeScene ~= scene then
                cutscenePal.barsScene = nil
            end
        else
            scene.barsEnterProgress = math.min(1,scene.barsEnterProgress + 1/(scene.barsEnterDuration or cutscenePal.defaultBarEnterDuration))
        end
    end

    -- Update skipping
    local scene = cutscenePal.skippingScene

    if scene ~= nil then
        scene.skipTimer = scene.skipTimer + 1

        if scene.skipState == cutscenePal.SKIP_STATE.ENTER then
            scene.skipEnterProgress = math.min(1,scene.skipEnterProgress + 1/(scene.skipEnterDuration or cutscenePal.defaultSkipEnterDuration))
            
            if scene.skipEnterProgress >= 1 then
                scene.skipState = cutscenePal.SKIP_STATE.BLANK
                scene.skipTimer = 0

                if scene.skipRoutineFunc ~= nil then
                    scene.skipRoutineObj = Routine.run(scene.skipRoutineFunc,scene)
                end
            end
        elseif scene.skipState == cutscenePal.SKIP_STATE.BLANK then
            if scene.skipTimer >= (scene.skipBlankDuration or cutscenePal.defaultSkipBlankDuration) and (scene.skipRoutineFunc == nil or not scene.skipRoutineObj.isValid) then
                scene.skipState = cutscenePal.SKIP_STATE.EXIT
                scene.skipTimer = 0

                cutscenePal.barsScene = nil
                scene:stop()

                Misc.pause()
            end
        elseif scene.skipState == cutscenePal.SKIP_STATE.EXIT then
            scene.skipEnterProgress = math.max(0,scene.skipEnterProgress - 1/(scene.skipEnterDuration or cutscenePal.defaultSkipEnterDuration))

            if scene.skipEnterProgress <= 0 then
                scene.skipState = cutscenePal.SKIP_STATE.INACTIVE
                scene.skipTimer = 0

                cutscenePal.skippingScene = nil

                Misc.unpause()
            end
        end
    end

    -- Update actors
    local i = 1

    while (cutscenePal.actors[i] ~= nil) do
        local actor = cutscenePal.actors[i]

        if actor._toRemove then
            table.remove(cutscenePal.actors,i)
            actor.isValid = false
        else
            if actor.updateWhilePaused or not Misc.isPaused() then
                actor:update()
            end

            i = i + 1
        end
    end
end

function cutscenePal.onDraw()
    -- Draw stuff for the active scene
    local scene = cutscenePal.activeScene

    if scene ~= nil and scene.drawFunc ~= nil then
        scene:drawFunc()
    end

    -- Draw bars
    local scene = cutscenePal.barsScene

    if scene ~= nil and scene.barsEnterProgress > 0 then
        local func = scene.drawBarsFunc or cutscenePal.defaultDrawBarsFunc

        func(scene,scene.barsEnterProgress,barsAreClosing())
    end

    -- Draw skip transition
    local scene = cutscenePal.skippingScene

    if scene ~= nil and scene.skipState ~= cutscenePal.SKIP_STATE.INACTIVE then
        local func = scene.drawSkipFunc or cutscenePal.defaultDrawSkipFunc

        func(scene,scene.skipEnterProgress,(scene.skipState == cutscenePal.SKIP_STATE.EXIT))
    end

    -- Render actors
    for _,actor in ipairs(cutscenePal.actors) do
        if not actor._toRemove then
            actor:draw()
        end
    end
end


function cutscenePal.onInitAPI()
    registerEvent(cutscenePal,"onInputUpdate")
    registerEvent(cutscenePal,"onDraw")
end


-- The default for a scene's drawBarsFunc.
function cutscenePal.defaultDrawBarsFunc(scene,progress,closing)
    local priority = 5.5
    local color = Color.black

    local height = easing.outQuad(progress,0,48,1)

    Graphics.drawBox{
        color = color,priority = priority,
        x = 0,y = 0,width = camera.width,height = height,
    }

    Graphics.drawBox{
        color = color,priority = priority,
        x = 0,y = camera.height - height,width = camera.width,height = height,
    }

    -- Render some text to say that you can skip it
    if scene.canSkip and not mem(VANILLA_PAUSED_ADDR,FIELD_BOOL) then
        textplus.print{
            text = "Press drop item to skip",
            xscale = 2,yscale = 2,
            pivot = vector(1,0.5 - (1 - progress)*0.5),
            priority = priority,

            x = camera.width - 24,
            y = camera.height - height*0.5 + (1 - progress)*4,
        }
    end
end

-- The default for a scene's drawSkipFunc.
function cutscenePal.defaultDrawSkipFunc(scene,progress,closing)
    local priority = 5.6
    local color = Color.black

    local height = easing.outSine(progress,0,camera.height*0.5 + 4,1)

    Graphics.drawBox{
        color = color,priority = priority,
        x = 0,y = 0,width = camera.width,height = height,
    }

    Graphics.drawBox{
        color = color,priority = priority,
        x = 0,y = camera.height - height,width = camera.width,height = height,
    }
end

-- Run along with a scene's updateFunc. This default just handles skipping the cutscene.
function cutscenePal.defaultUpdateFunc(scene)
    -- Start skipping
    if cutscenePal.canSkip() and player.rawKeys.dropItem == KEYS_PRESSED then
        scene:skip()
    end
end

-- Run along with a scene's startFunc. This default doesn't do anything.
function cutscenePal.defaultStartFunc(scene)

end

-- Run along with a scene's stopFunc. This default doesn't do anything.
function cutscenePal.defaultStopFunc(scene)

end


cutscenePal.defaultBarEnterDuration = 16
cutscenePal.defaultBarExitDuration = 16

cutscenePal.defaultSkipEnterDuration = 24
cutscenePal.defaultSkipExitDuration = 32
cutscenePal.defaultSkipBlankDuration = 4

cutscenePal.defaultSkipSound = nil


return cutscenePal