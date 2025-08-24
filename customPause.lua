--[[
	customPause.lua (v1)

	by Marioman2007
]]

local easing = require("ext/easing")
local textplus = require("textplus")
local configFileReader = require("configFileReader")

local customPause = {}

customPause.MUSIC_SILENT = 0
customPause.MUSIC_CURRENT = -1

customPause.settings = {
	-- size of the confirmation menu
	confirmMenuSize = vector(600, 128),

	-- priority to draw the menu at
	priority = 6,

	-- map level filename of the smwMap level, or the hub level filename
	mapFilename = "map.lvlx",

	-- the font to use and its scale
	font = textplus.loadFont("minFont.ini"),
	fontScale = 2,

	-- default color and color when the option is selected
	defaultColor = Color.white,
	highlightColor = Color.fromHexRGB(0xFFCC33),

	-- horizontal and vertical distance between the box edges and the options
	border = vector(40, 24),

	-- gap between the top of one option to the top of the next option
	gap = 32,

	-- set to true if you want to override the menu
	dontMakeMenu = false,

	-- music volume when paused
	pausedVolume = 40,

	-- set to customPause.MUSIC_SILENT to simply pause the music
	-- set to customPause.MUSIC_CURRENT to only change the volume and not the music
	-- set to a string to set a different music
	pausedMusic = customPause.MUSIC_CURRENT
}

-- images used for the menu
customPause.images = {
	selector = Graphics.loadImageResolved("customPause/selector.png"),
	box = Graphics.loadImageResolved("customPause/box.png"),
}

-- these can be a number or string, setting to nil, 0 or an empty string will not play the sfx
customPause.sounds = {
	open = 30,
	choose = 26,
	confirm = 47,
	save = 58,
}

local SPEED = 0.1

local p = player
local settings = customPause.settings
local tableinsert = table.insert
local mainMenu = nil
local confirmMenu = nil

local lastVolume = 64
local lastMusic
local lastPos
local musicWasPaused = false
local useCurrentMusic = false

local hasMadeMenu = false
local switchTimer = 0
local watchTimer = 0
local watchMusic = nil

local menuNames = {}
local menuMap = {}
local openMenus = {}

local smwMap
pcall(function() smwMap = require("smwMap") end)

local stateToPowerup = {
	[FORCEDSTATE_POWERUP_BIG]     = p_BIG,
	[FORCEDSTATE_POWERDOWN_FIRE]  = PLAYER_BIG,
	[FORCEDSTATE_POWERDOWN_ICE]   = PLAYER_BIG,
	[FORCEDSTATE_POWERDOWN_SMALL] = PLAYER_SMALL,
	[FORCEDSTATE_POWERUP_FIRE]    = PLAYER_FIREFLOWER,
	[FORCEDSTATE_POWERUP_LEAF]    = PLAYER_LEAF,
	[FORCEDSTATE_POWERUP_TANOOKI] = PLAYER_TANOOKIE,
	[FORCEDSTATE_POWERUP_HAMMER]  = PLAYER_HAMMER,
	[FORCEDSTATE_POWERUP_ICE]     = PLAYER_ICE,
}

local function manageForcedState()
	for k, plyr in ipairs(Player.get()) do
		local newPower = stateToPowerup[plyr.forcedState]
		
		if newPower ~= nil then
			plyr.powerup = newPower
			plyr.forcedState = 0
		end
	end
end

local function playSFX(name)
	local sfx = customPause.sounds[name]

	if sfx ~= nil and sfx ~= 0 and sfx ~= "" then
		return SFX.play(sfx)
	end
end

local function preventJumps()
	if isOverworld then
		p:mem(0x17A, FIELD_BOOL, false)
	else
		p:mem(0x11E, FIELD_BOOL, false)
	end
end

-- given by Emral
local function draw9Slice(args)
	local xpos = args.x
    local ypos =  args.y
    local width = args.texture.width
	local height = args.texture.height

    local cellWidth  = math.floor(width/3)
    local cellHeight = math.floor(height/3)

	local x1 = {0, cellWidth/width, (width - cellWidth)/width}
	local x2 = {cellWidth/width, (width - cellWidth)/width, 1}
	local y1 = {0, cellHeight/height, (height - cellHeight)/height}
	local y2 = {cellHeight/height, (height - cellHeight)/height, 1}
	local w  = {cellWidth, args.width - cellWidth - cellWidth, cellWidth}
	local h  = {cellHeight, args.height - cellHeight - cellHeight, cellHeight}
	local xv = {0, cellWidth, args.width - cellWidth}
	local yv = {0, cellHeight, args.height - cellWidth}

	local vt = {}
    local tx = {}

	for x = 1, 3 do
		for y = 1, 3 do
			tableinsert(vt, xpos + xv[x])
			tableinsert(vt, ypos + yv[y])

			tableinsert(tx, x1[x])
			tableinsert(tx, y1[y])

			for i = 1, 2 do
				tableinsert(vt, xpos + xv[x] + w[x])
				tableinsert(vt, ypos + yv[y])
				tableinsert(tx, x2[x])
				tableinsert(tx, y1[y])

				tableinsert(vt, xpos + xv[x])
				tableinsert(vt, ypos + yv[y] + h[y])
				tableinsert(tx, x1[x])
				tableinsert(tx, y2[y])
			end

			tableinsert(vt, xpos + xv[x] + w[x])
			tableinsert(vt, ypos + yv[y] + h[y])
			tableinsert(tx, x2[x])
			tableinsert(tx, y2[y])
		end
	end

	Graphics.glDraw{
		vertexCoords = vt,
		textureCoords = tx,
        primitive = Graphics.GL_TRIANGLES,
		priority = args.priority,
		texture = args.texture,
        color = args.color,
        target = args.target,
        sceneCoords = args.sceneCoords,
	}
end

local function getLayout(txt, maxWidth)
	return textplus.layout(textplus.parse(txt, {font = settings.font, xscale = settings.fontScale, yscale = settings.fontScale}), maxWidth)
end

local function evenOut(x, upOrDown)
    local x = math.floor(x)
    return x + (x % 2) * (upOrDown or 1)
end


function customPause.removePause()
	Misc.unpause()
	preventJumps()

	Audio.MusicVolume(lastVolume)

	if musicWasPaused then
		if isOverworld then
			Audio.ReleaseStream(-1)
		elseif smwMap ~= nil then
			Audio.MusicResume()
		end

		Audio.MusicSetPos(lastPos)
		musicWasPaused = false

	elseif not useCurrentMusic then
		if smwMap ~= nil then
			smwMap.currentlyPlayingMusic = nil

		elseif not isOverworld then 
			if lastMusic ~= nil then
				Audio.MusicStop()
				Audio.MusicChange(p.section, lastMusic)
			end

			if switchTimer > 0 then
				Misc.doPSwitch(true)
				mem(0x00B2C62C, FIELD_WORD, switchTimer)
				switchTimer = 0
			end

			if watchTimer > 0 then
				Audio.MusicOpen(watchMusic)
				Audio.MusicPlay()
				mem(0x00B2C62E, FIELD_WORD, watchTimer)
				watchTimer = 0
			end

			if lastPos ~= nil then
				Audio.MusicSetPos(lastPos)
			end
		else
			Audio.MusicStop()
			Audio.ReleaseStream(-1)
		end
	end

	lastMusic = nil
	lastPos = nil
	useCurrentMusic = false
end

function customPause.open()
	Misc.pause()
	playSFX("open")

	lastVolume = Audio.MusicVolume()

	local pausedMusic = settings.pausedMusic

	if pausedMusic == customPause.MUSIC_SILENT then
		musicWasPaused = true
		lastPos = Audio.MusicGetPos()

		if isOverworld then
			Audio.SeizeStream(-1)
			Audio.MusicVolume(0)
		elseif smwMap ~= nil then
			Audio.MusicPause()
		else
			Audio.MusicVolume(0)
		end
	else
		Audio.MusicVolume(settings.pausedVolume)

		if pausedMusic ~= customPause.MUSIC_CURRENT then
			if smwMap ~= nil then
				lastPos = Audio.MusicGetPos()
				Audio.MusicOpen(pausedMusic)
				Audio.MusicPlay()

			elseif not isOverworld then
				lastMusic = Section(p.section).music
				lastPos = Audio.MusicGetPos()

				Audio.MusicChange(p.section, pausedMusic)
				Audio.MusicOpen(pausedMusic)
				Audio.MusicPlay()

				switchTimer = mem(0x00B2C62C, FIELD_WORD)
				watchTimer  = mem(0x00B2C62E, FIELD_WORD)
			else
				Audio.SeizeStream(-1)
				Audio.MusicOpen(pausedMusic)
				Audio.MusicPlay()
			end
		else
			useCurrentMusic = true
		end
	end
end

function customPause.resume()
	customPause.removePause()
	playSFX("open")
end

function customPause.restartLevel()
	Graphics.drawScreen{color = Color.black, priority = 100}
	customPause.removePause()
	manageForcedState()
	Level.load(Level.filename())
end

function customPause.exitLevel()
	Graphics.drawScreen{color = Color.black, priority = 100}
	customPause.removePause()
	manageForcedState()
	Level.exit()
end

function customPause.saveGame()
	customPause.removePause()
	Misc.saveGame()
	playSFX("save")
end

function customPause.quitGame()
	Graphics.drawScreen{color = Color.black, priority = 100}
	manageForcedState()
	Misc.unpause()
	Misc.saveGame()
	Misc.exitEngine()
end


function customPause.setupRenderStuff()
	for k, menuName in ipairs(menuNames) do
		local menu = menuMap[menuName]
		local width = menu.width
		local height = menu.height

		local confirmOptions = {}

		for _, optionName in ipairs(menu.optionNames) do
			local option = menu.optionMap[optionName]

			option.nameLt = getLayout(option.name)

			width = math.max(width, option.nameLt.width)
			height = math.max(height, option.nameLt.height)

			if option.confirmText ~= nil then
				table.insert(confirmOptions, option)
			end
		end

		if menu.useGivenSize then
			width = menu.width
			height = menu.height
		else
			width = evenOut(width + settings.border.x * 2)
			height = evenOut(settings.gap * (menu.optionCount - 1) + height + settings.border.y * 2) - 2
		end

		menu.buffer = Graphics.CaptureBuffer(width, height, true)

		draw9Slice{
			texture = customPause.images.box,
			x = 0,
			y = 0,
			width = width,
			height = height,
			target = menu.buffer,
		}

		for _, option in ipairs(confirmOptions) do
			option.confirmLt = getLayout(option.confirmText, settings.confirmMenuSize.x - settings.border.x * 2)
		end
	end
end


function customPause.addOption(menu, args)
	menu = menu or "untitled"
	args = args or {}

	if type(menu) == "string" then
		menu = menuMap[menu]
	end

	local entry = {
		name = args.name or "Button",
		confirmText = args.confirmText,
		confirm = args.confirm or false,
		actionFunc = args.action or function() end,

		nameLt = nil,
		confirmLt = nil,
	}

	menu.optionCount = menu.optionCount + 1

	table.insert(menu.optionNames, entry.name)
	menu.optionMap[entry.name] = entry

	return entry
end


function customPause.getMainMenu()
	return mainMenu
end


function customPause.getConfirmMenu()
	return confirmMenu
end


local function defaultInputFunc(v, up, down)
	local keys = p.rawKeys

	if keys[up] == KEYS_PRESSED then
		v.selection = v.selection - 1
		playSFX("choose")

	elseif keys[down] == KEYS_PRESSED then
		v.selection = v.selection + 1
		playSFX("choose")

	elseif keys.run == KEYS_PRESSED or keys.pause == KEYS_PRESSED then
		v:close()

	elseif keys.jump == KEYS_PRESSED then
		local option = v.optionMap[v.optionNames[v.selection]]

		if not option.confirm then
			option:actionFunc()
		else
			confirmMenu.selectedOption = option
			confirmMenu:open()
		end
	end

	if v.selection < 1 then
		v.selection = v.optionCount
	elseif v.selection > v.optionCount then
		v.selection = 1
	end
end


function customPause.verticalInput(v)
	defaultInputFunc(v, "up", "down")
end


function customPause.horizontalInput(v)
	defaultInputFunc(v, "left", "right")
end


function customPause.sharedDrawFunc(v)
	if v.isOpen then
		v.openTimer = math.min(v.openTimer + SPEED, 1)
	else
		v.openTimer = math.max(v.openTimer - SPEED, 0)
	end

	if v.isClosing then
		v.textOpacity = math.max(v.textOpacity - SPEED * 3, 0)

		if v.textOpacity == 0 then
			v.isOpen = false
		end

	elseif v.openTimer == 1 then
		v.textOpacity = math.min(v.textOpacity + SPEED * 3, 1)
	end

	local easedValue = easing.outSine(v.openTimer, 0, 1, 1)

	Graphics.drawScreen{
		color = Color.black .. easedValue * 0.5,
		priority = settings.priority,
	}

	Graphics.drawBox{
		texture = v.buffer,
		x = camera.width/2 + v.xOffset,
		y = camera.height/2 + v.yOffset,
		width = v.buffer.width * easedValue,
		height = v.buffer.height * easedValue,
		centered = true,
		priority = settings.priority,
		color = Color.white .. easedValue,
	}

	return easedValue
end


function customPause.drawMainMenu(v)
	local easedValue = customPause.sharedDrawFunc(v)
	local xOffset = camera.width/2 - v.buffer.width/2 + settings.border.x + v.xOffset
	local yOffset = camera.height/2 - v.buffer.height/2 + settings.border.y + v.yOffset

	for k, optionName in ipairs(v.optionNames) do
		local option = v.optionMap[optionName]
		local color = settings.defaultColor

		if v.selection == k then
			color = settings.highlightColor
		end

		textplus.render{
			layout = option.nameLt,
			x = xOffset,
			y = yOffset + (k - 1) * settings.gap,
			priority = settings.priority,
			color = color * v.textOpacity,
		}
	end

	local selectorImg = customPause.images.selector

	Graphics.drawImageWP(		
		selectorImg,
		xOffset - selectorImg.width - 4 - (math.sin(lunatime.drawtick() * 0.2) + 1) * 3,
		yOffset + (v.selection - 1) * settings.gap,
		v.textOpacity,
		settings.priority
	)
end


function customPause.drawConfirmMenu(v)
	local easedValue = customPause.sharedDrawFunc(v)
	local xOffset = camera.width/2 - v.buffer.width/2 + v.xOffset
	local yOffset = camera.height/2 - v.buffer.height/2 + v.yOffset

	local partWidth = math.floor(v.buffer.width/(v.optionCount + 1))

	for k, optionName in ipairs(v.optionNames) do
		local option = v.optionMap[optionName]
		local layout = option.nameLt
		local color = settings.defaultColor

		if v.selection == k then
			color = settings.highlightColor
		end

		textplus.render{
			layout = layout,
			x = evenOut(xOffset + k * partWidth - layout.width/2),
			y = yOffset + v.buffer.height - 32,
			priority = settings.priority,
			color = color * v.textOpacity,
		}
	end

	local option = v.selectedOption

	if option.confirmLt then
		textplus.render{
			layout = option.confirmLt,
			x = xOffset + settings.border.x,
			y = yOffset + settings.border.y,
			priority = settings.priority,
			color = Color.white * v.textOpacity,
		}
	end

	local selectorImg = customPause.images.selector

	Graphics.drawImageWP(		
		selectorImg,
		evenOut(xOffset + v.selection * partWidth - 28) - selectorImg.width - (math.sin(lunatime.drawtick() * 0.2) + 1) * 3,
		yOffset + v.buffer.height - 32,
		v.textOpacity,
		settings.priority
	)
end


function customPause.makeMenu(name, args)
	name = name or "untitled"
	args = args or {}

	local entry = {
		name = name,

		inputFunc = args.inputFunc or customPause.verticalInput,
		drawFunc = args.drawFunc or customPause.drawMainMenu,
		openFunc = args.openFunc or function() end,
		closeFunc = args.closeFunc or function() end,

		xOffset = args.xOffset or 0,
		yOffset = args.yOffset or 0,

		optionNames = {},
		optionMap = {},

		addOption = customPause.addOption,
		selection = 1,
		isOpen = false,
		openTimer = 0,
		isClosing = false,
		textOpacity = 0,

		open = function(v)
			v.selection = 1
			v.isOpen = true
			v.openTimer = 0
			v.isClosing = false
			v.textOpacity = 0
			v:openFunc()

			table.insert(openMenus, v)
		end,
		
		close = function(v)
			v.isClosing = true
			v:closeFunc()

			local pos = table.ifind(openMenus, v)
			table.remove(openMenus, pos)
		end,

		isTopMenu = function(v)
			return openMenus[#openMenus] == v
		end,

		buffer = nil,
		width = args.width or 0,
		height = args.height or 0,
		useGivenSize = false,
		optionCount = 0,
	}

	if args.isMainMenu then
		mainMenu = entry
	elseif args.isConfirmMenu then
		confirmMenu = entry
	end

	if args.width ~= nil and args.height ~= nil then
		entry.useGivenSize = true
	end

	table.insert(menuNames, name)
	menuMap[name] = entry

	return entry
end


function customPause.makeDefaultMenu()
	local settings = customPause.settings

	local main = customPause.makeMenu("Main", {
		isMainMenu = true,
		openFunc = customPause.open,
		closeFunc = customPause.resume,
	})

	main:addOption{
		name = "Continue",
		action = function() main:close() end,
	}

	if isOverworld or Level.filename() == settings.mapFilename then
		main:addOption{
			name = "Save Game",
			action = customPause.saveGame,
		}

		main:addOption{
			name = "Save & Quit Game", 
			action = customPause.quitGame,
			confirm = true,
			confirmText = "This will quit the game after saving.",
		}
	else
		main:addOption{
			name = "Restart",
			action = customPause.restartLevel,
			confirm = true,
			confirmText = "This will restart the level and <color 0xFC3737>any unsaved progress will be lost.</color>",
		}

		main:addOption{
			name = "Exit Level",
			action = customPause.exitLevel,
			confirm = true,
			confirmText = "This will exit the level and <color 0xFC3737>any unsaved progress will be lost.</color>",
		}

		main:addOption{
			name = "Quit Game", 
			action = customPause.quitGame,
			confirm = true,
			confirmText = "This will quit the game and <color 0xFC3737>any unsaved progress will be lost.</color>",
		}
	end

	local confirm = customPause.makeMenu("Confirm", {
		isConfirmMenu = true,
		width = settings.confirmMenuSize.x,
		height = settings.confirmMenuSize.y,
		inputFunc = customPause.horizontalInput,
		drawFunc = customPause.drawConfirmMenu,

		openFunc = function()
			playSFX("confirm")
		end,

		closeFunc = function()
			--playSFX("open")
		end,
	})

	confirm:addOption{name = "No",  action = function()
		confirm:close()
	end}

	confirm:addOption{name = "Yes", action = function()
		confirm.selectedOption:actionFunc()
		confirm:close()
	end}
end

-- Register events
function customPause.onInitAPI()
	registerEvent(customPause, "onPause")
	registerEvent(customPause, "onKeyboardPressDirect")
	registerEvent(customPause, "onStart")
	registerEvent(customPause, "onDraw")
	registerEvent(customPause, "onInputUpdate")
end

-- override default pause menu
function customPause.onPause(e)
	if e.cancelled then
		return
	end

	e.cancelled = true

	if hasMadeMenu then
		mainMenu:open()
	end
end

-- keyboard shortcut for testing mode
function customPause.onKeyboardPressDirect(keyCode, repeated, char)
	if not Misc.inEditor() or repeated or confirmMenu.isOpen then
		return
	end

	if keyCode ~= VK_SPACE or not hasMadeMenu then
		return
	end

	if not mainMenu.isOpen then
		mainMenu:open()
	else
		mainMenu:close()
	end
end

-- make the default menu
function customPause.onStart()
	if not customPause.settings.dontMakeMenu then
		customPause.makeDefaultMenu()
	end

	customPause.setupRenderStuff()
	hasMadeMenu = true

	for k, v in ipairs(configFileReader.parseWithHeaders(Misc.resolveFile("music.ini"), {})) do
		if v._header == "special-music-2" then
			watchMusic = v.file
			break
		end
	end

	watchMusic = watchMusic or "music/smb3-switch.spc|0;g=2.7"
end

-- draw the menus
function customPause.onDraw()
	if mainMenu.isOpen and not mainMenu.isClosing and not Misc.isPausedByLua() then
		for k, menuName in ipairs(menuNames) do
			menuMap[menuName]:close()
		end
	end

	for k, menuName in ipairs(menuNames) do
		local menu = menuMap[menuName]

		if menu.isOpen or menu.openTimer > 0 then
			menu:drawFunc()
		end
	end
end

-- handle player input
function customPause.onInputUpdate()
	for k, menuName in ipairs(menuNames) do
		local menu = menuMap[menuName]

		if menu:isTopMenu() and menu.textOpacity == 1 then
			menu:inputFunc()
		end
	end
end


return customPause