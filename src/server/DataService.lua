-- DataService.lua (ModuleScript)
-- Gemeinsamer Datenzugriff für alle Server-Scripts.
-- PlayerDataManager.server.lua lädt/speichert, die anderen Scripts benutzen nur die API hier.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DATASTORE_NAME = "CowFarm_PlayerData_v1"
local MAX_RETRIES = 3

local DataService = {}

local profiles = {} -- [Player] = data
local canSave = {} -- [Player] = true, wenn der DataStore erfolgreich geladen wurde
local rng = Random.new()

local cowAddedEvent = Instance.new("BindableEvent")
DataService.CowAdded = cowAddedEvent.Event -- (player, cow)

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore nicht verfügbar:", result)
	end
end

------------------------------------------------------------------------
-- Standard-Daten
------------------------------------------------------------------------
local function createDefaultData()
	return {
		Version = 1,
		Coins = CowData.Config.StartCoins,
		Milk = 0,
		TotalMilk = 0,
		Cows = {}, -- ["c1"] = { Id = "c1", Rarity = "Common", Name = "Berta", Obtained = os.time() }
		NextCowId = 1,
		-- Breeding = { ParentA = "c1", ParentB = "c2", StartedAt = ..., ReadyAt = ... } (nil = keine Zucht)
		LoginStreak = { Streak = 0, LastDay = 0, Best = 0 },
		Receipts = {}, -- bereits verarbeitete Robux-Käufe
		ReceivedStarterCow = false,
		TutorialDone = false, -- Einführung für neue Spieler schon gesehen?
	}
end

local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and deepCopy(v) or v
	end
	return copy
end

-- Fehlende Felder (z.B. nach einem Update) mit Standardwerten auffüllen
local function reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = type(value) == "table" and deepCopy(value) or value
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function getKey(player)
	return "Player_" .. player.UserId
end

local function setupLeaderstats(player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats

	local cows = Instance.new("IntValue")
	cows.Name = "Kühe"
	cows.Parent = leaderstats

	leaderstats.Parent = player
end

------------------------------------------------------------------------
-- Laden / Speichern (wird von PlayerDataManager aufgerufen)
------------------------------------------------------------------------
function DataService.Load(player)
	if profiles[player] then
		return profiles[player]
	end

	local data = nil
	local loadedOk = false

	if store then
		for attempt = 1, MAX_RETRIES do
			local ok, result = pcall(function()
				return store:GetAsync(getKey(player))
			end)
			if ok then
				data = result
				loadedOk = true
				break
			end
			warn(("[DataService] Laden fehlgeschlagen (%d/%d) für %s: %s"):format(attempt, MAX_RETRIES, player.Name, tostring(result)))
			task.wait(attempt)
		end
	end

	if not loadedOk then
		if RunService:IsStudio() then
			warn("[DataService] Studio ohne DataStore-Zugriff -> es wird mit Testdaten gespielt (NICHT gespeichert).")
			warn("[DataService] Tipp: Game Settings > Security > 'Enable Studio Access to API Services' aktivieren.")
		else
			-- Lieber kicken als mit leeren Daten echte Daten zu überschreiben
			player:Kick("Deine Farm-Daten konnten nicht geladen werden. Bitte versuche es gleich nochmal!")
			return nil
		end
	end

	-- Spieler hat das Spiel während des Ladens verlassen
	if player.Parent == nil then
		return nil
	end

	if type(data) ~= "table" then
		data = createDefaultData()
	else
		-- Spieler von vor dem Tutorial-Update kennen das Spiel schon
		if data.TutorialDone == nil and data.ReceivedStarterCow then
			data.TutorialDone = true
		end
		reconcile(data, createDefaultData())
	end

	profiles[player] = data
	canSave[player] = loadedOk

	setupLeaderstats(player)
	DataService.Sync(player)
	return data
end

function DataService.Save(player)
	local data = profiles[player]
	if not data or not canSave[player] or not store then
		return false
	end

	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			store:UpdateAsync(getKey(player), function()
				return data
			end)
		end)
		if ok then
			return true
		end
		warn(("[DataService] Speichern fehlgeschlagen (%d/%d) für %s: %s"):format(attempt, MAX_RETRIES, player.Name, tostring(err)))
		task.wait(attempt)
	end
	return false
end

function DataService.Release(player)
	DataService.Save(player)
	profiles[player] = nil
	canSave[player] = nil
end

------------------------------------------------------------------------
-- Zugriff
------------------------------------------------------------------------
function DataService.Get(player)
	return profiles[player]
end

-- Wartet, bis die Daten eines Spielers geladen sind (max. 30 Sekunden)
function DataService.WaitForData(player, timeout)
	timeout = timeout or 30
	local start = os.clock()
	while player.Parent and not profiles[player] and os.clock() - start < timeout do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.CountCows(player)
	local data = profiles[player]
	if not data then
		return 0
	end
	local count = 0
	for _ in pairs(data.Cows) do
		count += 1
	end
	return count
end

function DataService.HasCowSpace(player, amount)
	return DataService.CountCows(player) + (amount or 1) <= CowData.Config.MaxCows
end

-- Überträgt die Werte an Attribute (für den Client) und leaderstats
function DataService.Sync(player)
	local data = profiles[player]
	if not data then
		return
	end
	local cowCount = DataService.CountCows(player)

	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Milk", data.Milk)
	player:SetAttribute("CowCount", cowCount)
	player:SetAttribute("LoginStreak", data.LoginStreak.Streak)
	player:SetAttribute("TutorialDone", data.TutorialDone == true)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Coins.Value = data.Coins
		leaderstats["Kühe"].Value = cowCount
	end
end

------------------------------------------------------------------------
-- Coins & Milch
------------------------------------------------------------------------
function DataService.AddCoins(player, amount)
	local data = profiles[player]
	if not data or type(amount) ~= "number" or amount <= 0 then
		return false
	end
	data.Coins += math.floor(amount)
	DataService.Sync(player)
	return true
end

function DataService.SpendCoins(player, amount)
	local data = profiles[player]
	if not data or type(amount) ~= "number" or amount < 0 then
		return false
	end
	if data.Coins < amount then
		return false
	end
	data.Coins -= amount
	DataService.Sync(player)
	return true
end

function DataService.AddMilk(player, amount)
	local data = profiles[player]
	if not data or amount <= 0 then
		return false
	end
	data.Milk += amount
	data.TotalMilk += amount
	DataService.Sync(player)
	return true
end

-- Nimmt die gesamte Milch weg und gibt die Menge zurück (zum Verkaufen)
function DataService.TakeAllMilk(player)
	local data = profiles[player]
	if not data then
		return 0
	end
	local milk = data.Milk
	data.Milk = 0
	DataService.Sync(player)
	return milk
end

------------------------------------------------------------------------
-- Kühe
------------------------------------------------------------------------
-- Fügt eine Kuh hinzu (prüft KEIN Limit, das macht der Aufrufer)
function DataService.AddCow(player, rarity)
	local data = profiles[player]
	if not data or not CowData.IsValidRarity(rarity) then
		return nil
	end

	local id = "c" .. data.NextCowId
	data.NextCowId += 1

	local cow = {
		Id = id,
		Rarity = rarity,
		Name = CowData.RandomName(rng),
		Obtained = os.time(),
	}
	data.Cows[id] = cow

	DataService.Sync(player)
	cowAddedEvent:Fire(player, cow)
	DataService.FireInventoryChanged(player)
	return cow
end

------------------------------------------------------------------------
-- Client-Kommunikation
------------------------------------------------------------------------
-- kind: "info" | "success" | "error" | "rare"
function DataService.Notify(player, text, kind)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "info")
	end
end

function DataService.FireInventoryChanged(player)
	if player and player.Parent then
		Remotes.InventoryChanged:FireClient(player)
	end
end

return DataService
