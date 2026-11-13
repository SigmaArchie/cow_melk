-- ShopService.lua (ModuleScript)
-- Lager des Kuh-Shops. Es wechselt alle CowData.Shop.RestockInterval Sekunden und ist in allen
-- Servern gleich (CowData.RollShopStock würfelt mit der Nummer des Zeitabschnitts).
-- Jeder Spieler darf von jeder Art so viele kaufen, wie im Lager sind. Mitgezählt wird in
-- data.ShopStock = { Cycle, Bought = { [Kuh-Art] = Anzahl } } (wird mitgespeichert, Rejoin hilft also nicht).
-- Das Kaufen selbst (Coins, Platz, neue Kuh) macht CowManager über Remotes.BuyCow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ShopService = {}

local cachedCycle = nil
local cachedStock = nil

function ShopService.GetCycle()
	return CowData.GetShopCycle(os.time())
end

-- Lager eines Zeitabschnitts { [Kuh-Art] = Menge } (Standard: aktueller Abschnitt)
function ShopService.GetStock(cycle)
	cycle = cycle or ShopService.GetCycle()
	if cycle ~= cachedCycle then
		cachedCycle = cycle
		cachedStock = CowData.RollShopStock(cycle)
	end
	return cachedStock
end

-- Gekaufte Anzahlen des Spielers in diesem Abschnitt (ein neuer Abschnitt fängt bei 0 an)
local function boughtTable(data, cycle)
	local shopStock = data.ShopStock
	if type(shopStock) ~= "table" or type(shopStock.Bought) ~= "table" then
		shopStock = { Cycle = cycle, Bought = {} }
		data.ShopStock = shopStock
	end
	if shopStock.Cycle ~= cycle then
		shopStock.Cycle = cycle
		shopStock.Bought = {}
	end
	return shopStock.Bought
end

-- Wie viele kann der Spieler von dieser Art in diesem Abschnitt noch kaufen?
function ShopService.GetRemaining(player, cowType, cycle)
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	cycle = cycle or ShopService.GetCycle()
	local amount = ShopService.GetStock(cycle)[cowType] or 0
	return math.max(0, amount - (boughtTable(data, cycle)[cowType] or 0))
end

-- Einen Kauf mitzählen (vorher GetRemaining mit demselben cycle prüfen)
function ShopService.RecordPurchase(player, cowType, cycle)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local bought = boughtTable(data, cycle or ShopService.GetCycle())
	bought[cowType] = (bought[cowType] or 0) + 1
end

-- Antwort für das Shop-Fenster (alle Arten, auch die gerade nicht im Lager sind)
function ShopService.BuildStockInfo(player)
	local data = DataService.Get(player)
	local cycle = ShopService.GetCycle()
	local stock = ShopService.GetStock(cycle)
	local bought = data and boughtTable(data, cycle) or {}

	local items = {}
	for order, entry in ipairs(CowData.Shop.Stock) do
		local amount = stock[entry.Type] or 0
		table.insert(items, {
			Type = entry.Type,
			Order = order,
			Price = CowData.Rarities[entry.Type].ShopPrice,
			Amount = amount, -- so viele sind im Lager
			Remaining = math.max(0, amount - (bought[entry.Type] or 0)), -- so viele darf dieser Spieler noch kaufen
		})
	end

	return {
		Cycle = cycle,
		RestockAt = CowData.GetRestockTime(cycle),
		ServerTime = os.time(),
		Items = items,
	}
end

return ShopService
