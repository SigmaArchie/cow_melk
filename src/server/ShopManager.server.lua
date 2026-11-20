-- ShopManager.server.lua
-- Kuh-Shop mit wechselndem Lager (Daten: CowData.Shop, Logik: ShopService):
--   * Remotes.GetShopStock -> Lager + Zeitpunkt des nächsten Lagers für das Shop-Fenster
--   * neues Lager -> Remotes.ShopRestocked an alle (ein offenes Shop-Fenster lädt neu) + Meldung;
--     seltene Arten (ab CowData.Shop.AnnounceTier) werden im ganzen Server angesagt
-- Gekauft wird über Remotes.BuyCow (CowManager.server.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local GetShopStock = DataService.GetRemote("GetShopStock", "RemoteFunction")
local ShopRestocked = DataService.GetRemote("ShopRestocked", "RemoteEvent")

------------------------------------------------------------------------
-- Lager abfragen
------------------------------------------------------------------------
-- Gleiche Anfragen innerhalb von 0,2 s bekommen dieselbe Antwort (Schutz gegen Spam).
-- Nach einem Kauf ändert sich die Inventar-Version -> neue Antwort.
local CACHE_TIME = 0.2
local cache = {} -- [player] = { Time, Version, Cycle, Result }

GetShopStock.OnServerInvoke = function(player)
	local now = os.clock()
	local version = DataService.GetInventoryVersion(player)
	local cycle = ShopService.GetCycle()
	local entry = cache[player]
	if entry and entry.Version == version and entry.Cycle == cycle and now - entry.Time < CACHE_TIME then
		return entry.Result
	end
	local ok, result = pcall(ShopService.BuildStockInfo, player)
	if not ok then
		warn("[ShopManager] Lager konnte nicht gebaut werden:", result)
		return nil
	end
	cache[player] = { Time = now, Version = version, Cycle = cycle, Result = result }
	return result
end

Players.PlayerRemoving:Connect(function(player)
	cache[player] = nil
end)

------------------------------------------------------------------------
-- Neues Lager ansagen
------------------------------------------------------------------------
local function announceRestock(cycle)
	ShopRestocked:FireAllClients(cycle)
	if CowData.IsStudioTest() then
		return -- im Studio-Testmodus ist immer alles da, keine Ansagen
	end

	local stock = ShopService.GetStock(cycle)
	local rare = {}
	for _, entry in ipairs(CowData.Shop.Stock) do
		local info = CowData.Rarities[entry.Type]
		if stock[entry.Type] and info.Tier >= CowData.Shop.AnnounceTier then
			table.insert(rare, info.DisplayName)
		end
	end

	if #rare > 0 then
		DataService.NotifyAll(
			("🌟 Selten im Kuh-Shop: %s! Nur bis zum nächsten Lager."):format(table.concat(rare, ", ")),
			"rare"
		)
	else
		DataService.NotifyAll("🛒 Der Kuh-Shop hat neue Kühe im Lager!", "info")
	end
end

task.spawn(function()
	local lastCycle = ShopService.GetCycle()
	while true do
		task.wait(1)
		local cycle = ShopService.GetCycle()
		if cycle ~= lastCycle then
			lastCycle = cycle
			announceRestock(cycle)
		end
	end
end)
