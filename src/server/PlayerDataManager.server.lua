-- PlayerDataManager.server.lua
-- Lädt die Spielerdaten beim Beitreten, speichert beim Verlassen,
-- macht regelmäßige Autosaves und sichert alles beim Server-Shutdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local function onPlayerAdded(player)
	local data = DataService.Load(player)
	if not data then
		return
	end

	-- Neue Spieler bekommen eine Gratis-Kuh (Begrüßung + Tutorial zeigt TutorialClient)
	if not data.ReceivedStarterCow then
		data.ReceivedStarterCow = true
		DataService.AddCow(player, CowData.Config.StarterCow)
	end
end

-- Client meldet: Tutorial fertig (oder übersprungen)
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
Remotes.TutorialDone.OnServerEvent:Connect(function(player)
	local data = DataService.Get(player)
	if data and not data.TutorialDone then
		data.TutorialDone = true
		DataService.Sync(player)
	end
end)

local function onPlayerRemoving(player)
	DataService.Release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Falls Spieler schon da sind, bevor dieses Script läuft
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Autosave
task.spawn(function()
	while true do
		task.wait(CowData.Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(DataService.Save, player)
		end
	end
end)

-- Beim Herunterfahren des Servers alle Daten speichern
game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			DataService.Save(player)
			pending -= 1
		end)
	end

	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.1)
	end
end)
