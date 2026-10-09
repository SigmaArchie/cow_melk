-- LoginStreak.server.lua
-- Täglicher Login-Bonus. Wer 7 Tage am Stück spielt, bekommt eine Rainbow Cow.
-- Ein "Tag" ist ein UTC-Tag. Wer einen Tag auslässt, startet wieder bei Tag 1.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local Config = CowData.Config
local SECONDS_PER_DAY = 86400

local function getCurrentDay()
	return math.floor(os.time() / SECONDS_PER_DAY)
end

local function processLogin(player)
	local data = DataService.Get(player)
	if not data then
		return
	end

	local streakData = data.LoginStreak
	local today = getCurrentDay()

	-- Heute schon abgeholt
	if streakData.LastDay == today then
		return
	end

	if streakData.LastDay == today - 1 then
		streakData.Streak += 1
	else
		streakData.Streak = 1
	end
	streakData.LastDay = today
	streakData.Best = math.max(streakData.Best, streakData.Streak)

	-- Tag im aktuellen 7-Tage-Zyklus (1..7)
	local cycleDay = ((streakData.Streak - 1) % Config.RainbowStreakDays) + 1
	local reward = Config.DailyRewardBase * cycleDay

	DataService.AddCoins(player, reward)
	DataService.Sync(player)
	DataService.Notify(
		player,
		("🔥 Login-Streak: Tag %d! Bonus: %s Coins (%d/%d bis zur Rainbow Cow)"):format(
			streakData.Streak,
			CowData.FormatNumber(reward),
			cycleDay,
			Config.RainbowStreakDays
		),
		"success"
	)

	-- Rainbow Cow nach jeweils 7 Tagen am Stück
	if streakData.Streak % Config.RainbowStreakDays == 0 then
		local cow = DataService.AddCow(player, "Rainbow")
		if cow then
			DataService.Notify(player, ("🌈 %d Tage am Stück! %s, deine Rainbow Cow, ist auf deiner Farm!"):format(Config.RainbowStreakDays, cow.Name), "rare")
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then
					DataService.Notify(other, ("🌈 %s hat sich durch einen 7-Tage-Streak eine Rainbow Cow verdient!"):format(player.DisplayName), "rare")
				end
			end
		end
	end
end

local function onPlayerAdded(player)
	local data = DataService.WaitForData(player)
	if not data then
		return
	end
	-- kurz warten, damit der Client die Nachricht sicher empfängt
	task.wait(4)
	if player.Parent then
		processLogin(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Spieler, die über Mitternacht (UTC) online bleiben, bekommen den neuen Tag auch
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(processLogin, player)
		end
	end
end)
