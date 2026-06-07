local textplus = require("textplus")
local minFont = textplus.loadFont("minFont.ini")
local emergencyClose = false
local LuigiGame = Graphics.loadImage("LuigiGame.png") 
local myOpacity = 0
local myOpacityChange = -0.05

function onDraw()
    Graphics.drawImage(LuigiGame, 35, 482, myOpacity)
end

function onStart()
    Defines.npc_throwfriendlytimer = 10
end