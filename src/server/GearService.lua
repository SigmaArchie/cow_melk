-- GearService.lua (ModuleScript)
-- Spiel-Logik für das Werkzeug (CowData.Gears). Arbeitet nur mit den Spielerdaten (data) und der Zeit,
-- ohne Modelle oder Remotes – dadurch lässt sie sich gut testen. Benutzt von GearManager (Kaufen,
-- Aufstellen, Benutzen, Ablaufen, schnelleres Wachsen) und CowManager (Mutations-Glück, Striegel-Bonus).
--
-- Gespeichert wird in den Spielerdaten:
--   data.Gears       = { [Werkzeug] = Anzahl }                       (im Rucksack)
--   data.PlacedGear  = { { Id, Type, Corner, PlacedAt, ExpiresAt } } (auf der Weide aufgestellt)
--   data.NextGearId  = Zahl
--   data.GearStock   = { Cycle, Bought = { [Werkzeug] = Anzahl } }   (im aktuellen Lager schon gekauft)
--   cow.Brushed      = true, wenn der nächste volle Eimer der Kuh mehr Milch hat

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))

local Gears = CowData.Gears
local Settings = CowData.GearSettings

local GearService = {}

------------------------------------------------------------------------
-- Daten in Ordnung halten
------------------------------------------------------------------------
function GearService.Ensure(data)
	if type(data.Gears) ~= "table" then
		data.Gears = {}
	end
	for gearType, count in pairs(data.Gears) do
		if not Gears[gearType] or type(count) ~= "number" or count < 1 then
			data.Gears[gearType] = nil
		else
			data.Gears[gearType] = math.floor(count)
		end
	end
	if type(data.PlacedGear) ~= "table" then
		data.PlacedGear = {}
	end
	local clean = {}
	for _, entry in ipairs(data.PlacedGear) do
		local info = type(entry) == "table" and Gears[entry.Type]
		if
			info
			and info.Kind == "Place"
			and type(entry.Id) == "string"
			and type(entry.Corner) == "number"
			and entry.Corner >= 1
			and entry.Corner <= CowData.GetGearCornerCount()
			and type(entry.ExpiresAt) == "number"
		then
			table.insert(clean, entry)
		end
	end
	data.PlacedGear = clean
	if type(data.NextGearId) ~= "number" then
		data.NextGearId = 1
	end
	if type(data.GearStock) ~= "table" or type(data.GearStock.Bought) ~= "table" then
		data.GearStock = { Cycle = 0, Bought = {} }
	end
end

function GearService.GetCount(data, gearType)
	return (data.Gears and data.Gears[gearType]) or 0
end

function GearService.AddGear(data, gearType, amount)
	GearService.Ensure(data)
	data.Gears[gearType] = GearService.GetCount(data, gearType) + (amount or 1)
end

local function takeOne(data, gearType)
	local count = GearService.GetCount(data, gearType) - 1
	data.Gears[gearType] = count > 0 and count or nil
end

------------------------------------------------------------------------
-- Shop-Lager (wie der Kuh-Shop: alle paar Minuten neu, in allen Servern gleich)
------------------------------------------------------------------------
local cachedCycle, cachedStock = nil, nil

function GearService.GetCycle(now)
	return CowData.GetGearCycle(now or os.time())
end

function GearService.GetStock(cycle)
	if cycle ~= cachedCycle then
		cachedCycle = cycle
		cachedStock = CowData.RollGearStock(cycle)
	end
	return cachedStock
end

local function boughtTable(data, cycle)
	GearService.Ensure(data)
	if data.GearStock.Cycle ~= cycle then
		data.GearStock.Cycle = cycle
		data.GearStock.Bought = {}
	end
	return data.GearStock.Bought
end

-- Wie viele darf der Spieler von diesem Werkzeug in diesem Lager noch kaufen?
function GearService.GetRemaining(data, gearType, cycle)
	local amount = GearService.GetStock(cycle)[gearType] or 0
	return math.max(0, amount - (boughtTable(data, cycle)[gearType] or 0))
end

-- Prüft alles für einen Kauf (Coins zieht GearManager über DataService ab).
-- Gibt ok, Meldung zurück.
function GearService.CanBuy(data, gearType, cycle)
	local info = Gears[gearType]
	if not info then
		return false, "Dieses Werkzeug gibt es nicht."
	end
	if (GearService.GetStock(cycle)[gearType] or 0) <= 0 then
		return false, info.DisplayName .. " ist gerade nicht im Lager."
	end
	if GearService.GetRemaining(data, gearType, cycle) <= 0 then
		return false, "Ausverkauft! Warte auf das nächste Lager."
	end
	if (data.Coins or 0) < info.Price then
		return false, "Nicht genug Coins!"
	end
	return true
end

-- Nach dem Bezahlen: Werkzeug in den Rucksack + Kauf mitzählen
function GearService.CompletePurchase(data, gearType, cycle)
	local bought = boughtTable(data, cycle)
	bought[gearType] = (bought[gearType] or 0) + 1
	GearService.AddGear(data, gearType, 1)
end

-- Antwort für das Shop-Fenster (alle Werkzeuge, auch die gerade fehlen)
function GearService.BuildStockInfo(data, now)
	local cycle = GearService.GetCycle(now)
	local stock = GearService.GetStock(cycle)
	local bought = boughtTable(data, cycle)
	local items = {}
	for order, entry in ipairs(CowData.GearShop.Stock) do
		local amount = stock[entry.Type] or 0
		table.insert(items, {
			Type = entry.Type,
			Order = order,
			Price = Gears[entry.Type].Price,
			Amount = amount,
			Remaining = math.max(0, amount - (bought[entry.Type] or 0)),
		})
	end
	return { Cycle = cycle, RestockAt = CowData.GetGearRestockTime(cycle), ServerTime = now, Items = items }
end

------------------------------------------------------------------------
-- Aufstellen / Ablaufen
------------------------------------------------------------------------
function GearService.GetActive(data, now)
	local active = {}
	for _, entry in ipairs(data.PlacedGear or {}) do
		if entry.ExpiresAt > now then
			table.insert(active, entry)
		end
	end
	return active
end

function GearService.FindAtCorner(data, corner, now)
	for _, entry in ipairs(GearService.GetActive(data, now)) do
		if entry.Corner == corner then
			return entry
		end
	end
	return nil
end

function GearService.CanPlace(data, gearType, corner, now)
	local info = Gears[gearType]
	if not info or info.Kind ~= "Place" then
		return false, "Das kann man nicht aufstellen."
	end
	if GearService.GetCount(data, gearType) <= 0 then
		return false, "Du hast kein " .. info.DisplayName .. "."
	end
	if
		type(corner) ~= "number"
		or corner ~= math.floor(corner)
		or corner < 1
		or corner > CowData.GetGearCornerCount()
	then
		return false, "Dort kann nichts stehen."
	end
	if GearService.FindAtCorner(data, corner, now) then
		return false, "Dort steht schon etwas."
	end
	if #GearService.GetActive(data, now) >= Settings.MaxPlaced then
		return false, ("Es dürfen höchstens %d Werkzeuge auf der Weide stehen."):format(Settings.MaxPlaced)
	end
	return true
end

-- Gibt den neuen Eintrag zurück (oder nil, Meldung)
function GearService.Place(data, gearType, corner, now)
	GearService.Ensure(data)
	local ok, message = GearService.CanPlace(data, gearType, corner, now)
	if not ok then
		return nil, message
	end
	takeOne(data, gearType)
	local entry = {
		Id = "g" .. data.NextGearId,
		Type = gearType,
		Corner = corner,
		PlacedAt = now,
		ExpiresAt = now + Gears[gearType].Duration,
	}
	data.NextGearId += 1
	table.insert(data.PlacedGear, entry)
	return entry
end

-- Abgelaufenes Werkzeug entfernen. Gibt die entfernten Einträge zurück.
function GearService.RemoveExpired(data, now)
	local kept, removed = {}, {}
	for _, entry in ipairs(data.PlacedGear or {}) do
		table.insert(entry.ExpiresAt > now and kept or removed, entry)
	end
	data.PlacedGear = kept
	return removed
end

------------------------------------------------------------------------
-- Wirkung
------------------------------------------------------------------------

-- Bester Faktor (field = "Growth" | "MutationLuck") aller Werkzeuge, die auf das Feld der Kuh wirken
function GearService.GetBoost(data, cow, now, field)
	if not cow or type(cow.Slot) ~= "number" then
		return 1
	end
	local best = 1
	for _, entry in ipairs(GearService.GetActive(data, now)) do
		local value = Gears[entry.Type][field]
		if value and value > best and CowData.GearCoversCell(entry.Type, entry.Corner, cow.Slot) then
			best = value
		end
	end
	return best
end

function GearService.GetMutationLuck(data, cow, now)
	return GearService.GetBoost(data, cow, now, "MutationLuck")
end

-- Schnelleres Wachsen anrechnen: Kälber im Bereich bekommen dt * (Faktor - 1) Sekunden geschenkt
-- (ihr Geburtszeitpunkt rückt nach vorne). Gibt true zurück, wenn sich etwas geändert hat.
function GearService.GrowthTick(data, now, dt)
	local changed = false
	for _, cow in pairs(data.Cows or {}) do
		if type(cow.BornAt) == "number" and type(cow.GrowTime) == "number" and not CowData.IsGrown(cow, now) then
			local factor = GearService.GetBoost(data, cow, now, "Growth")
			if factor > 1 then
				cow.BornAt = math.max(cow.BornAt - dt * (factor - 1), now - cow.GrowTime)
				changed = true
			end
		end
	end
	return changed
end

-- Striegel: Faktor für den Eimer (verbraucht den Bonus)
function GearService.TakeMilkBonus(cow)
	if cow and cow.Brushed then
		cow.Brushed = nil
		return Gears.Brush.MilkBonus
	end
	return 1
end

------------------------------------------------------------------------
-- An einer Kuh benutzen (Heu, Striegel, Wunder-Spray)
-- Gibt ok, Meldung, Ergebnis zurück. Ergebnis beim Spray: { Mutation = id, Combos = { ... } }
------------------------------------------------------------------------
local function pickSprayMutation(cow, rng)
	local current = cow.Mutations or {}
	local options, total = {}, 0
	for _, id in ipairs(CowData.CowMutationOrder) do
		local weight = Settings.SprayWeights[id]
		if weight and CowData.CanGainCowMutation(current, id) then
			table.insert(options, { Id = id, Weight = weight })
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, option in ipairs(options) do
		roll -= option.Weight
		if roll <= 0 then
			return option.Id
		end
	end
	return options[#options].Id
end

function GearService.UseOnCow(data, gearType, cow, now, rng)
	local info = Gears[gearType]
	if not info or info.Kind ~= "Cow" then
		return false, "Das kann man nicht an einer Kuh benutzen."
	end
	if not cow then
		return false, "Diese Kuh gibt es nicht."
	end
	if GearService.GetCount(data, gearType) <= 0 then
		return false, "Du hast kein " .. info.DisplayName .. "."
	end

	local result = nil
	if gearType == "Hay" then
		if (cow.MilkReadyAt or 0) <= now then
			return false, cow.Name .. " ist schon bereit zum Melken."
		end
		cow.MilkReadyAt = now
	elseif gearType == "Brush" then
		if cow.Brushed then
			return false, cow.Name .. " ist schon gestriegelt."
		end
		cow.Brushed = true
	elseif gearType == "MutationSpray" then
		local id = pickSprayMutation(cow, rng or Random.new())
		if not id then
			return false, cow.Name .. " kann keine neue Mutation mehr bekommen."
		end
		local list = table.clone(cow.Mutations or {})
		table.insert(list, id)
		local newList, made = CowData.ApplyCowMutationCombos(list)
		cow.Mutations = newList
		result = { Mutation = id, Combos = made }
	else
		return false, "Unbekanntes Werkzeug."
	end

	takeOne(data, gearType)
	return true, nil, result
end

return GearService
