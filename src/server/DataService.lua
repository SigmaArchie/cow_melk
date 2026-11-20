-- DataService.lua (ModuleScript)
-- Gemeinsamer Datenzugriff für alle Server-Scripts.
-- PlayerDataManager.server.lua lädt/speichert, die anderen Scripts benutzen nur die API hier.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DATASTORE_NAME = "CowFarm_PlayerData_v1"
local MAX_RETRIES = 3

local DataService = {}

local profiles = {} -- [Player] = data
local inventoryVersions = {} -- [Player] = Zahl (zählt Inventar-Änderungen, siehe GetInventoryVersion)
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
		Milk = 0, -- Liter in allen Eimern zusammen (wird aus Buckets berechnet)
		-- Milch-Eimer: ["b1"] = { Id, Liters, Mutations = { "Gold", "Choco" }, CowMutations, CowName, CowType, Obtained,
		--                        Hotbar = Platz 1-9 (nil = Eimer-Lager), Auto = true beim Auto-Melker-Eimer }
		Buckets = {},
		NextBucketId = 1,
		TotalMilk = 0,
		-- ["c1"] = { Id = "c1", Rarity = "Common", Name = "Berta", Obtained = os.time(),
		--           BornAt, GrowTime (Wachstum), Mutations = { "Wet", ... } (Kuh-Mutationen) }
		Cows = {},
		NextCowId = 1,
		-- Breeding = { ParentA = "c1", ParentB = "c2", StartedAt = ..., ReadyAt = ... } (nil = keine Zucht)
		LoginStreak = { Streak = 0, LastDay = 0, Best = 0 },
		Receipts = {}, -- bereits verarbeitete Robux-Käufe
		ShopStock = { Cycle = 0, Bought = {} }, -- im aktuellen Kuh-Shop-Lager schon gekauft: [Kuh-Art] = Anzahl
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

-- Alte Speicherstände (Milch als Zahl bzw. MilkStock je Sorte) werden zu Eimern; kaputte Eimer fliegen raus
local function migrateMilk(data)
	if type(data.Buckets) ~= "table" then
		data.Buckets = {}
	end
	if type(data.NextBucketId) ~= "number" then
		data.NextBucketId = 1
	end

	local function addOld(liters, mutations)
		local id = "b" .. data.NextBucketId
		data.NextBucketId += 1
		data.Buckets[id] = {
			Id = id,
			Liters = liters,
			Mutations = mutations,
			CowName = "Alte Milch",
			Obtained = os.time(),
		}
	end

	local oldTotal = 0
	if type(data.MilkStock) == "table" then
		for milkType, liters in pairs(data.MilkStock) do
			if type(liters) == "number" and liters > 0 then
				oldTotal += liters
				addOld(liters, (milkType ~= "Normal" and CowData.IsValidMilkType(milkType)) and { milkType } or {})
			end
		end
	end
	data.MilkStock = nil
	-- Milch, die nur als Zahl gespeichert war (vor den Eimern)
	local bucketTotal = 0
	for _, bucket in pairs(data.Buckets) do
		if type(bucket) == "table" and type(bucket.Liters) == "number" then
			bucketTotal += bucket.Liters
		end
	end
	if type(data.Milk) == "number" and data.Milk > bucketTotal + 0.5 and oldTotal == 0 then
		addOld(data.Milk - bucketTotal, {})
	end

	for id, bucket in pairs(data.Buckets) do
		if type(bucket) ~= "table" or type(bucket.Liters) ~= "number" or bucket.Liters <= 0 then
			data.Buckets[id] = nil
		else
			bucket.Id = id
			bucket.Mutations = CowData.CleanMutations(bucket.Mutations)
			bucket.CowMutations = CowData.CleanCowMutations(bucket.CowMutations)
		end
	end
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
			warn(
				("[DataService] Laden fehlgeschlagen (%d/%d) für %s: %s"):format(
					attempt,
					MAX_RETRIES,
					player.Name,
					tostring(result)
				)
			)
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
		migrateMilk(data)
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
		warn(
			("[DataService] Speichern fehlgeschlagen (%d/%d) für %s: %s"):format(
				attempt,
				MAX_RETRIES,
				player.Name,
				tostring(err)
			)
		)
		task.wait(attempt)
	end
	return false
end

function DataService.Release(player)
	DataService.Save(player)
	profiles[player] = nil
	canSave[player] = nil
	inventoryVersions[player] = nil
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

-- Ein laufendes Kalb (Zucht) zählt schon als belegter Platz, sonst würde das Limit überschritten
function DataService.HasCowSpace(player, amount)
	local data = profiles[player]
	local reserved = (data and data.Breeding) and 1 or 0
	return DataService.CountCows(player) + reserved + (amount or 1) <= CowData.Config.MaxCows
end

-- true, wenn die Daten des Spielers wirklich gespeichert werden (nicht Studio-Testdaten)
function DataService.IsPersistent(player)
	return canSave[player] == true
end

-- Überträgt die Werte an Attribute (für den Client) und leaderstats
function DataService.Sync(player)
	local data = profiles[player]
	if not data then
		return
	end
	local cowCount = DataService.CountCows(player)

	player:SetAttribute("Coins", data.Coins)
	-- Milch = Summe aller Eimer (Liter und Wert)
	local liters, value = 0, 0
	for _, bucket in pairs(data.Buckets) do
		liters += bucket.Liters
		value += CowData.GetBucketValue(bucket.Liters, bucket.Mutations, bucket.CowMutations)
	end
	data.Milk = liters
	player:SetAttribute("Milk", liters)
	player:SetAttribute("MilkValue", value)
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

------------------------------------------------------------------------
-- Milch-Eimer (jeder Melk-Vorgang = ein Eimer; Hotbar teilen sich Kühe und Eimer)
------------------------------------------------------------------------
-- Was liegt auf welchem Hotbar-Platz? [Platz] = Kuh oder Eimer
function DataService.GetHotbarItems(data)
	local used = {}
	for _, cow in pairs(data.Cows) do
		if cow.Hotbar then
			used[cow.Hotbar] = cow
		end
	end
	for _, bucket in pairs(data.Buckets) do
		if bucket.Hotbar then
			used[bucket.Hotbar] = bucket
		end
	end
	return used
end

local function firstFreeHotbar(data)
	local used = DataService.GetHotbarItems(data)
	for i = 1, CowData.Config.HotbarSize do
		if not used[i] then
			return i
		end
	end
	return nil
end
DataService.FirstFreeHotbar = firstFreeHotbar

function DataService.CountBuckets(player)
	local data = profiles[player]
	local count = 0
	if data then
		for _ in pairs(data.Buckets) do
			count += 1
		end
	end
	return count
end

-- Ist noch Platz für einen Eimer? (sonst erst verkaufen)
function DataService.HasBucketSpace(player)
	return DataService.CountBuckets(player) < CowData.Config.MaxBuckets
end

-- Neuer Eimer nach dem Melken. mutations = Liste aus CowData.RollMilkMutations, cow = Kuh (für Name/Art).
-- Kommt auf einen freien Hotbar-Platz, sonst ins Eimer-Lager. Prüft KEIN Limit (das macht startMilking).
function DataService.AddBucket(player, liters, mutations, cow)
	local data = profiles[player]
	if not data or type(liters) ~= "number" or liters <= 0 then
		return nil
	end
	local id = "b" .. data.NextBucketId
	data.NextBucketId += 1
	local bucket = {
		Id = id,
		Liters = liters,
		Mutations = CowData.CleanMutations(mutations),
		CowName = cow and cow.Name or nil,
		CowMutations = CowData.CleanCowMutations(cow and cow.Mutations), -- machen die Milch mehr wert
		CowType = cow and cow.Rarity or nil,
		Obtained = os.time(),
		Hotbar = firstFreeHotbar(data),
	}
	data.Buckets[id] = bucket
	data.TotalMilk += liters
	DataService.Sync(player)
	DataService.FireInventoryChanged(player)
	return bucket
end

-- Auto-Melker: alles kommt in EINEN Eimer, der immer voller wird (keine Mutationen)
function DataService.AddAutoMilk(player, liters)
	local data = profiles[player]
	if not data or type(liters) ~= "number" or liters <= 0 then
		return
	end
	local bucket = data.Buckets.auto
	if not bucket then
		bucket = {
			Id = "auto",
			Auto = true,
			Liters = 0,
			Mutations = {},
			CowName = "Auto-Melker",
			Obtained = os.time(),
			Hotbar = firstFreeHotbar(data),
		}
		data.Buckets.auto = bucket
	end
	bucket.Liters += liters
	data.TotalMilk += liters
	DataService.Sync(player)
	DataService.FireInventoryChanged(player)
end

-- Verkaufswert aller Eimer in Coins
function DataService.GetMilkValue(player)
	local data = profiles[player]
	local value = 0
	if data then
		for _, bucket in pairs(data.Buckets) do
			value += CowData.GetBucketValue(bucket.Liters, bucket.Mutations, bucket.CowMutations)
		end
	end
	return value
end

-- Nimmt alle Eimer weg (zum Verkaufen). Gibt (Liter, Wert in Coins, Liste der Eimer) zurück.
function DataService.TakeAllMilk(player)
	local data = profiles[player]
	if not data then
		return 0, 0, {}
	end
	local liters, value, list = 0, 0, {}
	for _, bucket in pairs(data.Buckets) do
		liters += bucket.Liters
		value += CowData.GetBucketValue(bucket.Liters, bucket.Mutations, bucket.CowMutations)
		table.insert(list, bucket)
	end
	data.Buckets = {}
	DataService.Sync(player)
	DataService.FireInventoryChanged(player)
	return liters, value, list
end

-- Nimmt einen Eimer weg (zum Verkaufen). Gibt (Eimer, Wert) zurück oder nil.
function DataService.TakeBucket(player, bucketId)
	local data = profiles[player]
	local bucket = data and type(bucketId) == "string" and data.Buckets[bucketId]
	if not bucket then
		return nil, 0
	end
	data.Buckets[bucketId] = nil
	DataService.Sync(player)
	DataService.FireInventoryChanged(player)
	return bucket, CowData.GetBucketValue(bucket.Liters, bucket.Mutations, bucket.CowMutations)
end

------------------------------------------------------------------------
-- Kühe
------------------------------------------------------------------------
-- Fügt eine Kuh hinzu (prüft KEIN Limit, das macht der Aufrufer).
-- Neue Kühe kommen als Kalb und wachsen (CowData.Growth); options.Adult = true -> gleich ausgewachsen.
-- options.Mutations = Kuh-Mutationen von Anfang an (z.B. von den Eltern geerbt)
function DataService.AddCow(player, rarity, options)
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
	local mutations = CowData.CleanCowMutations(options and options.Mutations)
	if #mutations > 0 then
		cow.Mutations = mutations
	end
	if not (options and options.Adult) then
		cow.BornAt = os.time()
		cow.GrowTime = CowData.GetGrowTime(rarity)
	end
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

-- Remote aus ReplicatedStorage.Remotes holen. Fehlt es (Rojo nach einer Änderung an
-- default.project.json nicht neu gestartet), legt der Server es an, statt mit einem Fehler abzubrechen.
function DataService.GetRemote(name, className)
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		warn(("[DataService] Remote %s fehlt (Rojo neu starten) – wird zur Laufzeit angelegt."):format(name))
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end

-- Meldung an alle Spieler im Server (except = diesen Spieler auslassen)
function DataService.NotifyAll(text, kind, except)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= except then
			DataService.Notify(other, text, kind)
		end
	end
end

-- Zählt mit, wie oft sich das Inventar geändert hat (der Server merkt sich damit seine Antworten)
function DataService.GetInventoryVersion(player)
	return inventoryVersions[player] or 0
end

function DataService.FireInventoryChanged(player)
	inventoryVersions[player] = (inventoryVersions[player] or 0) + 1
	if player and player.Parent then
		Remotes.InventoryChanged:FireClient(player)
	end
end

return DataService
