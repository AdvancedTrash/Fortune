local damagePause = {}

function damagePause.onInitAPI()
	registerEvent(damagePause, "onTick", "onTick")
end

function damagePause.onTick()
	for kp,p in ipairs(Player.get()) do
		if p.forcedTimer ~= 0 then
			if #Player.get() == 2 then
				if kp == 1 then
					player2.forcedState = FORCEDSTATE_ONTONGUE
				elseif kp == 2 then
					player.forcedState = FORCEDSTATE_ONTONGUE
				end
			end
			Defines.levelFreeze = true
		else
			Defines.levelFreeze = false
		end
	end
end


return damagePause