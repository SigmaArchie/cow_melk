-- GearManager.server.lua
-- Werkzeug-Shop und aufgestelltes Werkzeug auf den Farmen (Daten: CowData.Gears / CowData.GearShop, Logik: GearService):
--   * Remotes.GetGearStock   -> Lager + was der Spieler schon gekauft hat (Shop-Fenster "Gear")
--   * Remotes.BuyGear        -> kaufen (Lager, Coins prüft der Server)
--   * Remotes.GearAction     -> ("Place", Werkzeug, x, z, yaw) irgendwo auf der Farm aufstellen
--                               ("UseOnCow", Werkzeug, KuhId) an einer Kuh benutzen
--                               ("Hotbar", Werkzeug, Platz | nil) / ("Unhotbar", Werkzeug)
--   * jede Sekunde: abgelaufenes Werkzeug abbauen, Modelle + Restzeit auf den Farmen aktuell halten,
--     alle CowData.GearSettings.GrowthTick Sekunden das schnellere Wachsen anrechnen
-- Mutations-Glück (Kuhglocke, Wetterhahn) und Striegel-Bonus rechnet CowManager über GearService ein.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local GearModels = require(ReplicatedStorage.Shared:WaitForChild("GearModels"))
local Palette = require(ReplicatedStorage.Shared:WaitForChild("Palette"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GearService = require(script.Parent:WaitForChild("GearService"))

local Gears = CowData.Gears
local GetGearStock = DataService.GetRemote("GetGearStock", "RemoteFunction")
local BuyGear = DataService.GetRemote("BuyGear", "RemoteFunction")
local GearAction = DataService.GetRemote("GearAction", "RemoteFunction")

local rng = Random.new()
local lastCall = {} -- [player][key] = os.clock()
local ensured = {} -- [player] = true, sobald die Daten einmal geprüft wurden
local built = {} -- [player] = { [gearId] = { Model, Timer } }
local growthPending = {} -- [player] = true, wenn Kälber schneller gewachsen sind (Oberfläche auffrischen)

local function debounce(player, key, cooldown)
	lastCall[player] = lastCall[player] or {}
	local now = os.clock()
	local last = lastCall[player][key]
	if last and now - last < cooldown then
		return false
	end
	lastCall[player][key] = now
	return true
end

local function getData(player)
	local data = DataService.Get(player)
	if data and not ensured[player] then
		GearService.Ensure(data)
		ensured[player] = true
	end
	return data
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

------------------------------------------------------------------------
-- Modelle auf den Farmen
------------------------------------------------------------------------
local function findPlot(player)
	local layout = workspace:FindFirstChild("CowFarmLayout")
	local plots = layout and layout:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- Boden-CFrame eines aufgestellten Werkzeugs (Stelle + Drehung auf der Farm des Spielers)
local function gearCFrame(player, entry)
	local slot = player:GetAttribute("PlotSlot")
	if not slot then
		return nil
	end
	return CowData.GetPlotOrigin(slot)
		* CFrame.new(entry.X, CowData.Map.GroundTop, entry.Z)
		* CFrame.Angles(0, math.rad(entry.Yaw or 0), 0)
end

local function buildModel(player, plot, entry)
	local cf = gearCFrame(player, entry)
	if not cf then
		return nil
	end
	local info = Gears[entry.Type]
	local model = GearModels.Build(entry.Type, cf, { Seed = tonumber(entry.Id:sub(2)) or 7 })
	if not model then
		return nil
	end
	model.Name = entry.Id
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("ExpiresAt", entry.ExpiresAt)
	GearModels.AddRangeRing(model, cf, info.Radius, info.Color)

	-- Schild über dem Werkzeug: Name + Restzeit
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GearLabel"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Palette.Fonts.Heading
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = info.Color
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = info.Icon .. " " .. info.DisplayName
	nameLabel.Parent = billboard
	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.Position = UDim2.fromScale(0, 0.55)
	timer.Size = UDim2.fromScale(1, 0.45)
	timer.BackgroundTransparency = 1
	timer.Font = Palette.Fonts.Body
	timer.TextScaled = true
	timer.TextColor3 = Palette.Colors.Cream
	timer.TextStrokeTransparency = 0.4
	timer.Text = ""
	timer.Parent = billboard

	local folder = plot:FindFirstChild("Gear")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Gear"
		folder.Parent = plot
	end
	model.Parent = folder
	return { Model = model, Timer = timer }
end

-- Modelle passend zu den Daten: abgelaufenes abbauen, fehlendes bauen, Restzeit anzeigen
local function syncModels(player, data, now)
	local removed = GearService.RemoveExpired(data, now)
	for _, entry in ipairs(removed) do
		local info = Gears[entry.Type]
		DataService.Notify(player, ("⏰ %s %s ist aufgebraucht."):format(info.Icon, info.DisplayName), "info")
	end
	if #removed > 0 then
		DataService.FireInventoryChanged(player)
	end

	local plot = findPlot(player)
	local mine = built[player] or {}
	built[player] = mine
	local active = {}
	for _, entry in ipairs(data.PlacedGear) do
		active[entry.Id] = entry
	end
	for id, item in pairs(mine) do
		if not active[id] or not item.Model.Parent or not plot or not item.Model:IsDescendantOf(plot) then
			item.Model:Destroy()
			mine[id] = nil
		end
	end
	if not plot then
		return
	end
	for id, entry in pairs(active) do
		local item = mine[id]
		if not item then
			item = buildModel(player, plot, entry)
			mine[id] = item
		end
		if item then
			item.Timer.Text = "noch " .. formatTime(entry.ExpiresAt - now)
		end
	end
end

------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------
GetGearStock.OnServerInvoke = function(player)
	local data = getData(player)
	if not data then
		return nil
	end
	return GearService.BuildStockInfo(data, os.time())
end

BuyGear.OnServerInvoke = function(player, gearType)
	if not debounce(player, "BuyGear", 0.3) then
		return false, "Langsam!"
	end
	local data = getData(player)
	if not data then
		return false, "Deine Daten sind noch nicht geladen."
	end
	if not CowData.IsValidGear(gearType) then
		return false, "Dieses Werkzeug gibt es nicht."
	end
	local cycle = GearService.GetCycle(os.time())
	local ok, message = GearService.CanBuy(data, gearType, cycle)
	if not ok then
		return false, message
	end
	local info = Gears[gearType]
	if not DataService.SpendCoins(player, info.Price) then
		return false, "Nicht genug Coins!"
	end
	GearService.CompletePurchase(data, gearType, cycle)
	GearService.AutoHotbar(data, gearType) -- wie in Grow a Garden: gleich in die Hotbar, wenn Platz ist
	DataService.FireInventoryChanged(player)
	local where = data.GearHotbar[gearType] and ("Hotbar-Platz " .. data.GearHotbar[gearType]) or "WERKZEUG (Taste G)"
	return true, ("%s %s gekauft! Liegt in: %s."):format(info.Icon, info.DisplayName, where)
end

local function useOnCow(player, data, gearType, cowId)
	local cow = type(cowId) == "string" and data.Cows[cowId] or nil
	local ok, message, result = GearService.UseOnCow(data, gearType, cow, os.time(), rng)
	if not ok then
		return false, message
	end
	local info = Gears[gearType]
	if gearType == "Hay" then
		message = ("🌾 %s hat gefressen und kann sofort gemolken werden!"):format(cow.Name)
	elseif gearType == "Brush" then
		message = ("🧹 %s ist gestriegelt: Der nächste volle Eimer hat 50 %% mehr Milch."):format(cow.Name)
	else
		local mutation = CowData.CowMutations[result.Mutation]
		message = ("%s %s ist jetzt %s! (Milch %s wert)"):format(
			info.Icon,
			cow.Name,
			mutation.DisplayName,
			CowData.FormatMultiplier(mutation.Multiplier)
		)
		for _, combo in ipairs(result.Combos) do
			local combined = CowData.CowMutations[combo.Result]
			DataService.Notify(
				player,
				("%s Verbindung! %s ist jetzt %s (Milch %s wert)"):format(
					combined.Icon,
					cow.Name,
					combined.DisplayName,
					CowData.FormatMultiplier(combined.Multiplier)
				),
				"rare"
			)
		end
	end
	DataService.Notify(player, message, "success")
	DataService.FireInventoryChanged(player)
	return true, message
end

local function place(player, data, gearType, x, z, yaw)
	local plot = findPlot(player)
	if not plot then
		return false, "Du hast noch keine Farm."
	end
	local now = os.time()
	local entry, message = GearService.Place(data, gearType, x, z, yaw, now)
	if not entry then
		return false, message
	end
	syncModels(player, data, now)
	DataService.FireInventoryChanged(player)
	local info = Gears[gearType]
	return true, ("%s %s steht! Wirkt %d Minuten."):format(info.Icon, info.DisplayName, math.floor(info.Duration / 60))
end

GearAction.OnServerInvoke = function(player, action, gearType, a, b, c)
	if not debounce(player, "GearAction", 0.25) then
		return false, "Langsam!"
	end
	local data = getData(player)
	if not data then
		return false, "Deine Daten sind noch nicht geladen."
	end
	if not CowData.IsValidGear(gearType) then
		return false, "Dieses Werkzeug gibt es nicht."
	end
	if action == "Place" then
		return place(player, data, gearType, a, b, c)
	elseif action == "UseOnCow" then
		return useOnCow(player, data, gearType, a)
	elseif action == "Hotbar" or action == "Unhotbar" then
		local ok, message
		if action == "Hotbar" then
			ok, message = GearService.SetHotbar(data, gearType, a)
		else
			ok, message = GearService.RemoveFromHotbar(data, gearType)
		end
		if ok then
			DataService.FireInventoryChanged(player)
		end
		return ok, (not ok) and message or nil
	end
	return false, "Unbekannte Aktion."
end

------------------------------------------------------------------------
-- Schleifen
------------------------------------------------------------------------
local growthTimer = 0
local refreshTimer = 0
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		growthTimer += 1
		refreshTimer += 1
		local doGrowth = growthTimer >= CowData.GearSettings.GrowthTick
		if doGrowth then
			growthTimer = 0
		end
		local doRefresh = refreshTimer >= 30
		if doRefresh then
			refreshTimer = 0
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local data = getData(player)
			if data then
				local ok, err = pcall(function()
					syncModels(player, data, now)
					if doGrowth and GearService.GrowthTick(data, now, CowData.GearSettings.GrowthTick) then
						growthPending[player] = true
					end
					-- Wachstums-Timer in der Oberfläche ab und zu auffrischen
					if doRefresh and growthPending[player] then
						growthPending[player] = nil
						DataService.FireInventoryChanged(player)
					end
				end)
				if not ok then
					warn("[GearManager] Fehler bei", player.Name, err)
				end
			end
		end
	end
end)

-- Neues Lager: seltenes Werkzeug im ganzen Server ansagen
task.spawn(function()
	local lastCycle = GearService.GetCycle(os.time())
	while true do
		task.wait(1)
		local cycle = GearService.GetCycle(os.time())
		if cycle ~= lastCycle and not CowData.IsStudioTest() then
			lastCycle = cycle
			local stock = GearService.GetStock(cycle)
			local rare = {}
			for _, gearType in ipairs(CowData.GearOrder) do
				local info = Gears[gearType]
				if stock[gearType] and info.Price >= CowData.GearShop.AnnounceFrom then
					table.insert(rare, info.Icon .. " " .. info.DisplayName)
				end
			end
			if #rare > 0 then
				DataService.NotifyAll(
					("🧰 Selten im Werkzeug-Shop: %s! Nur bis zum nächsten Lager."):format(table.concat(rare, ", ")),
					"rare"
				)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
	ensured[player] = nil
	built[player] = nil
	growthPending[player] = nil
end)
