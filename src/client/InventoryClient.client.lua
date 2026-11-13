-- InventoryClient.client.lua
-- Kühe und Milch-Eimer verwalten:
--   * Hotbar unten in der Mitte (9 Plätze, Tasten 1-9) im Roblox-Stil – für Kühe UND Milch-Eimer.
--     Eimer zeigen Liter und Mutationen; anklicken -> Eimer in der Hand + Details + "Verkaufen"
--   * Fenster "MEINE KÜHE" (Taste I oder Knopf KÜHE) mit zwei Reitern: Kühe / Eimer
--   * Platzier-Modus: Hotbar-Platz wählen -> freie Felder auf der eigenen Farm leuchten grün
--     -> Feld anklicken. Abbrechen: Rechtsklick, Taste X oder "Abbrechen".
--   * Klick auf eine eigene Kuh: kleines Menü (Melken / Aufheben)
-- Der Server prüft alles (Remotes.CowAction). Stil: Theme.lua.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local UIBus = require(script.Parent:WaitForChild("UIBus"))

local Colors = Theme.Colors
local player = Players.LocalPlayer
local HOTBAR_SIZE = CowData.Config.HotbarSize

-- Roblox' eigene Werkzeug-Leiste brauchen wir nicht (sie würde die Tasten 1-6 belegen)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

------------------------------------------------------------------------
-- Daten vom Server
------------------------------------------------------------------------
local inventory = nil
local refreshCallbacks = {}

local function refresh()
	local ok, result = pcall(function()
		return Remotes.GetInventory:InvokeServer()
	end)
	if ok and result then
		inventory = result
		for _, callback in ipairs(refreshCallbacks) do
			task.spawn(callback)
		end
	end
end

local function findCow(cowId)
	if not inventory then
		return nil
	end
	for _, cow in ipairs(inventory.Cows) do
		if cow.Id == cowId then
			return cow
		end
	end
	return nil
end

-- Was liegt auf dem Platz? Gibt (Kuh oder Eimer, "cow" | "bucket") zurück
local function hotbarItem(index)
	if not inventory then
		return nil, nil
	end
	for _, cow in ipairs(inventory.Cows) do
		if cow.Hotbar == index then
			return cow, "cow"
		end
	end
	for _, bucket in ipairs(inventory.Buckets or {}) do
		if bucket.Hotbar == index then
			return bucket, "bucket"
		end
	end
	return nil, nil
end

local function findBucket(bucketId)
	if not inventory then
		return nil
	end
	for _, bucket in ipairs(inventory.Buckets or {}) do
		if bucket.Id == bucketId then
			return bucket
		end
	end
	return nil
end

-- Kuh-Mutationen als farbiger RichText: "Nass · Gefroren" (leer -> "")
local function cowMutationRichText(mutations)
	local parts = {}
	for _, id in ipairs(mutations or {}) do
		local mutation = CowData.CowMutations[id]
		if mutation then
			table.insert(parts, ('<font color="#%s">%s</font>'):format(mutation.Color:ToHex(), mutation.DisplayName))
		end
	end
	return table.concat(parts, " · ")
end

-- Symbole der Kuh-Mutationen: "💧🧊"
local function cowMutationIcons(mutations)
	local icons = ""
	for _, id in ipairs(mutations or {}) do
		local mutation = CowData.CowMutations[id]
		if mutation then
			icons ..= mutation.Icon
		end
	end
	return icons
end

-- Farbe der wertvollsten Mutation (normale Milch = Creme)
local function bucketColor(bucket)
	local top = bucket.Mutations and bucket.Mutations[1]
	return top and CowData.MilkTypes[top].Color or CowData.MilkTypes.Normal.Color
end

-- "Eimer von Berta · 120 L · Schokomilch + Goldmilch (x21) · Wert 4.800 Coins"
local function bucketDescription(bucket)
	local parts = {}
	table.insert(parts, bucket.CowName and ("Eimer von %s"):format(bucket.CowName) or "Eimer")
	table.insert(
		parts,
		("%s L (%s)"):format(CowData.FormatNumber(bucket.Liters), CowData.GetBucketSizeName(bucket.Liters))
	)
	if #bucket.Mutations > 0 then
		table.insert(
			parts,
			("%s (%s)"):format(
				CowData.FormatMutations(bucket.Mutations, #bucket.Mutations > 1),
				CowData.FormatMultiplier(CowData.GetMutationMultiplier(bucket.Mutations))
			)
		)
	else
		table.insert(parts, "keine Mutation")
	end
	local cowMutations = bucket.CowMutations or {}
	if #cowMutations > 0 then
		table.insert(
			parts,
			("Kuh: %s (%s)"):format(
				CowData.FormatCowMutations(cowMutations),
				CowData.FormatMultiplier(CowData.GetCowMutationMultiplier(cowMutations))
			)
		)
	end
	table.insert(parts, "Wert " .. CowData.FormatNumber(bucket.Value) .. " Coins")
	return table.concat(parts, "  ·  ")
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function rarityInfo(rarity)
	return CowData.Rarities[rarity] or CowData.Rarities.Common
end

local function cowIcon(parent, rarity, size, position)
	local info = rarityInfo(rarity)
	return Theme.cowIcon(parent, size, position, info.Color, info.SpotColor, info.Transparency and 0.3 or 0)
end

-- Gezeichneter Melkeimer: Henkel, Metall-Körper, Rand, Milch in der Farbe der Mutation
local function bucketIcon(parent, size, position, milkColor, bandColor)
	local z = Theme.zOf(parent) + 1
	local holder = Instance.new("Frame")
	holder.Name = "BucketIcon"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0)
	handle.Position = UDim2.fromScale(0.5, 0.02)
	handle.Size = UDim2.fromScale(0.62, 0.6)
	handle.BackgroundTransparency = 1
	handle.ZIndex = z
	handle.Parent = holder
	Theme.corner(handle, UDim.new(1, 0))
	Theme.border(handle, math.max(1.5, size / 16), Palette.World.Metal)

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.98)
	body.Size = UDim2.fromScale(0.72, 0.6)
	body.BackgroundColor3 = Palette.World.Metal
	body.BorderSizePixel = 0
	body.ZIndex = z + 1
	body.Parent = holder
	Theme.corner(body, math.max(3, math.floor(size / 8)))
	Theme.border(body, Theme.Stroke.Thin, Colors.Outline)

	local milk = Instance.new("Frame")
	milk.AnchorPoint = Vector2.new(0.5, 0)
	milk.Position = UDim2.fromScale(0.5, 0.1)
	milk.Size = UDim2.fromScale(0.84, 0.34)
	milk.BackgroundColor3 = milkColor
	milk.BorderSizePixel = 0
	milk.ZIndex = z + 2
	milk.Parent = body
	Theme.corner(milk, math.max(2, math.floor(size / 12)))

	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.fromScale(0.5, 0.66)
	band.Size = UDim2.fromScale(1, 0.1)
	band.BackgroundColor3 = bandColor or Theme.darken(Palette.World.Metal, 0.2)
	band.BorderSizePixel = 0
	band.ZIndex = z + 2
	band.Parent = body
	return holder
end

------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Inventory"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Hotbar (unten Mitte)
------------------------------------------------------------------------
local SLOT = 66

local hotbar = Instance.new("Frame")
hotbar.Name = "Hotbar"
hotbar.AnchorPoint = Vector2.new(0.5, 1)
hotbar.Position = UDim2.new(0.5, 0, 1, -14)
hotbar.Size = UDim2.fromOffset(HOTBAR_SIZE * SLOT + (HOTBAR_SIZE - 1) * 6, SLOT)
hotbar.BackgroundTransparency = 1
hotbar.Parent = gui
local hotbarLayout = Instance.new("UIListLayout")
hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
hotbarLayout.Padding = UDim.new(0, 6)
hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
hotbarLayout.Parent = hotbar
Theme.autoScale(hotbar)

local slots = {}
local selectedIndex = nil
local placingCowId = nil

for index = 1, HOTBAR_SIZE do
	local slot = Instance.new("TextButton")
	slot.Name = "Slot" .. index
	slot.LayoutOrder = index
	slot.AutoButtonColor = false
	slot.Text = ""
	slot.Size = UDim2.fromOffset(SLOT, SLOT)
	slot.BackgroundColor3 = Colors.Panel
	slot.BackgroundTransparency = 0.5
	slot.BorderSizePixel = 0
	slot.Parent = hotbar
	Theme.corner(slot, Theme.Radius.M)
	local stroke = Theme.border(slot, Theme.Stroke.Thin, Colors.Line, 0.5)
	local number = Theme.label(slot, {
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.fromOffset(16, 16),
		Font = Theme.BodyFont,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Colors.SubText,
		Text = tostring(index),
	})
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = slot
	slots[index] = { Button = slot, Stroke = stroke, Content = content, Number = number }
end

-- Zustände eines Platzes:
--   leer        – durchsichtig, gestrichelt wirkende dünne Linie, nur die Zahl
--   belegt      – Karte mit Kuhkopf und Name, Rahmen in der Seltenheitsfarbe
--   ausgewählt  – hellblauer, dicker Rahmen (Kuh wird gerade platziert)
local selectedBucketId = nil -- Eimer, dessen Details gerade unten stehen

local function renderHotbar()
	for index, widget in ipairs(slots) do
		for _, child in ipairs(widget.Content:GetChildren()) do
			child:Destroy()
		end
		local item, kind = hotbarItem(index)
		local selected = selectedIndex == index
		local accent = Colors.Line
		if kind == "cow" then
			cowIcon(widget.Content, item.Rarity, 34, UDim2.new(0.5, 0, 0, 27))
			Theme.label(widget.Content, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(1, -6, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Tiny,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = Palette.rarityColor(item.Rarity),
				Text = item.Name,
			})
			accent = Palette.rarityColor(item.Rarity)
		elseif kind == "bucket" then
			-- Eimer: oben die Mutation(en), Mitte der Eimer, unten die Liter
			local color = bucketColor(item)
			-- größerer Eimer = größeres Symbol (wie das Modell in der Hand)
			local iconSize = 22 + math.floor((CowData.GetBucketScale(item.Liters) - 0.8) / 1.4 * 14 + 0.5)
			bucketIcon(widget.Content, iconSize, UDim2.new(0.5, 0, 0, 33), color, #item.Mutations > 0 and color or nil)
			local top = item.Mutations[1]
			local tagText = ""
			if item.Auto then
				tagText = "Auto"
			elseif top then
				tagText = CowData.MilkTypes[top].ShortName
					.. (#item.Mutations > 1 and (" +" .. (#item.Mutations - 1)) or "")
			end
			tagText ..= cowMutationIcons(item.CowMutations)
			Theme.label(widget.Content, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 3),
				Size = UDim2.new(1, -22, 0, 13),
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Tiny,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = item.Auto and Colors.Teal or color,
				Text = tagText,
			})
			Theme.label(widget.Content, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(1, -6, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Tiny,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = Colors.Text,
				Text = CowData.FormatNumber(item.Liters) .. " L",
			})
			accent = #item.Mutations > 0 and color or Colors.Line
		end

		if item then
			widget.Button.BackgroundColor3 = selected and Colors.Steel or Colors.Card
			widget.Button.BackgroundTransparency = 0.05
			widget.Stroke.Color = selected and Colors.Blue or accent
			widget.Stroke.Transparency = selected and 0 or 0.2
		else
			widget.Button.BackgroundColor3 = Colors.Panel
			widget.Button.BackgroundTransparency = 0.5
			widget.Stroke.Color = selected and Colors.Blue or Colors.Line
			widget.Stroke.Transparency = selected and 0 or 0.5
		end
		widget.Stroke.Thickness = selected and 3 or Theme.Stroke.Thin
		widget.Number.TextColor3 = item and Colors.Text or Colors.SubText
	end
end

------------------------------------------------------------------------
-- Hinweis-Leiste über der Hotbar (Platzieren / Fehler)
------------------------------------------------------------------------
local hint = Theme.panel(gui, {
	Name = "PlaceHint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -96),
	Size = UDim2.fromOffset(560, 56),
	BackgroundColor3 = Colors.Panel,
	Visible = false,
})
Theme.autoScale(hint)
local hintText = Theme.label(hint, {
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -170, 1, 0),
	Font = Theme.BodyFont,
	TextSize = 16,
	TextWrapped = true,
	Text = "",
	Outline = 0,
})
local cancelButton = Theme.button(hint, {
	Text = "Abbrechen",
	Color = Colors.Red,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(132, 40),
	TextSize = 18,
	Radius = 10,
	Lip = 4,
})

-- "Verkaufen" für den ausgewählten Eimer (liegt an derselben Stelle wie "Abbrechen")
local sellBucketButton = Theme.button(hint, {
	Text = "Verkaufen",
	Color = Colors.Green,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(132, 40),
	TextSize = 18,
	Radius = 10,
	Lip = 4,
})
sellBucketButton.Parent.Visible = false

local hintToken = 0
local function showHint(text, isError, duration)
	hintToken += 1
	local token = hintToken
	hintText.Text = text
	hintText.TextColor3 = isError and Color3.fromRGB(255, 160, 150) or Colors.Text
	cancelButton.Parent.Visible = placingCowId ~= nil
	sellBucketButton.Parent.Visible = placingCowId == nil and selectedBucketId ~= nil
	hint.Visible = true
	if duration then
		task.delay(duration, function()
			if hintToken == token and not placingCowId then
				if selectedBucketId and findBucket(selectedBucketId) then
					showHint(bucketDescription(findBucket(selectedBucketId)))
				else
					hint.Visible = false
				end
			end
		end)
	end
end

-- Eimer tragen: der ausgewählte Hotbar-Eimer kommt beim Server in die rechte Hand (nil = loslassen)
local heldBucketId = nil
local function setHeld(bucketId)
	if heldBucketId == bucketId then
		return
	end
	heldBucketId = bucketId
	task.spawn(function()
		local called, ok, message = pcall(function()
			return Remotes:WaitForChild("BucketAction", 5):InvokeServer("hold", bucketId)
		end)
		if bucketId ~= nil and (not called or ok == false) then
			warn("[InventoryClient] Eimer tragen ging nicht:", called and message or ok)
			showHint(("Eimer tragen ging nicht: %s"):format(tostring(called and message or "keine Antwort")), true, 3)
			if heldBucketId == bucketId then
				heldBucketId = nil
			end
		end
	end)
end

------------------------------------------------------------------------
-- Platzier-Modus
------------------------------------------------------------------------
local FREE_COLOR = Color3.fromRGB(120, 200, 110) -- freie Felder (sanftes Grün)
local TAKEN_COLOR = Color3.fromRGB(214, 100, 96) -- belegte Felder (sanftes Rot)
local myCells = {}
local hoveredCell = nil

local function collectMyCells()
	table.clear(myCells)
	for _, tile in ipairs(CollectionService:GetTagged("FarmCell")) do
		if tile:GetAttribute("OwnerUserId") == player.UserId then
			myCells[tile:GetAttribute("Cell")] = tile
		end
	end
end

local function occupiedCells()
	local used = {}
	if inventory then
		for _, cow in ipairs(inventory.Cows) do
			if cow.Slot then
				used[cow.Slot] = true
			end
		end
	end
	return used
end

local function paintCells()
	local used = occupiedCells()
	for cell, tile in pairs(myCells) do
		if not placingCowId then
			tile.Color = Color3.new(1, 1, 1)
			tile.Transparency = 0.82
		elseif used[cell] then
			tile.Color = TAKEN_COLOR
			tile.Transparency = 0.6
		else
			tile.Color = FREE_COLOR
			tile.Transparency = cell == hoveredCell and 0.1 or 0.45
		end
	end
end

local function stopPlacing()
	placingCowId = nil
	selectedIndex = nil
	selectedBucketId = nil
	setHeld(nil)
	hoveredCell = nil
	hint.Visible = false
	paintCells()
	renderHotbar()
end

local function startPlacing(cowId)
	local cow = findCow(cowId)
	if not cow or cow.Slot then
		return
	end
	Theme.closeAllWindows()
	selectedBucketId = nil
	setHeld(nil)
	placingCowId = cowId
	selectedIndex = cow.Hotbar
	collectMyCells()
	paintCells()
	renderHotbar()
	showHint(("%s platzieren: klicke ein grünes Feld auf deiner Farm"):format(cow.Name))
end

-- Eimer auswählen: Details + "Verkaufen" in der Leiste über der Hotbar
local function selectBucket(bucket)
	if placingCowId then
		stopPlacing()
	end
	selectedBucketId = bucket.Id
	selectedIndex = bucket.Hotbar
	setHeld(bucket.Id) -- Eimer in die Hand
	renderHotbar()
	showHint(bucketDescription(bucket))
end

local function selectHotbar(index)
	if selectedIndex == index then
		stopPlacing()
		return
	end
	local item, kind = hotbarItem(index)
	if kind == "cow" then
		startPlacing(item.Id)
	elseif kind == "bucket" then
		selectBucket(item)
	else
		stopPlacing()
	end
end

for index, widget in ipairs(slots) do
	widget.Button.Activated:Connect(function()
		selectHotbar(index)
	end)
	-- Maus über einem Eimer: Details zeigen (solange nichts ausgewählt ist)
	widget.Button.MouseEnter:Connect(function()
		local item, kind = hotbarItem(index)
		if kind == "bucket" and not placingCowId and not selectedIndex then
			showHint(bucketDescription(item))
		end
	end)
	widget.Button.MouseLeave:Connect(function()
		if not placingCowId and not selectedIndex then
			hint.Visible = false
		end
	end)
end
cancelButton.Activated:Connect(stopPlacing)
UIBus.StartPlacement.Event:Connect(startPlacing)

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local function cellFromRay(ray)
	local list = {}
	for _, tile in pairs(myCells) do
		table.insert(list, tile)
	end
	raycastParams.FilterDescendantsInstances = list
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	return result and result.Instance:GetAttribute("Cell") or nil
end

RunService.RenderStepped:Connect(function()
	if not placingCowId or not workspace.CurrentCamera then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local cell = cellFromRay(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
	if cell ~= hoveredCell then
		hoveredCell = cell
		paintCells()
	end
end)

local busy = false
local function act(action, cowId, arg)
	if busy then
		return false
	end
	busy = true
	-- pcall: ein Fehler auf dem Server darf die Knöpfe nicht dauerhaft sperren
	local called, ok, message = pcall(function()
		return Remotes.CowAction:InvokeServer(action, cowId, arg)
	end)
	busy = false
	if not called then
		return false
	end
	if not ok and message then
		showHint(message, true, 3)
	end
	return ok
end

-- Eimer-Aktionen: "sell" | "hotbar" | "store"
local function bucketAct(action, bucketId, arg)
	if busy then
		return false
	end
	busy = true
	local called, ok, message = pcall(function()
		return Remotes:WaitForChild("BucketAction", 5):InvokeServer(action, bucketId, arg)
	end)
	busy = false
	if not called then
		showHint("Das hat nicht geklappt – versuch es nochmal.", true, 3)
		return false
	end
	if not ok and message then
		showHint(message, true, 3)
	end
	return ok
end

sellBucketButton.Activated:Connect(function()
	local bucketId = selectedBucketId
	if bucketId and bucketAct("sell", bucketId) then
		stopPlacing()
	end
end)

local function tryPlaceAt(screenPosition)
	local camera = workspace.CurrentCamera
	if not camera or not placingCowId then
		return
	end
	local cell = cellFromRay(camera:ScreenPointToRay(screenPosition.X, screenPosition.Y))
	if not cell then
		return
	end
	if occupiedCells()[cell] then
		showHint("Da steht schon eine Kuh – nimm ein grünes Feld.", true)
		return
	end
	if act("place", placingCowId, cell) then
		stopPlacing()
	end
end

------------------------------------------------------------------------
-- Fenster "MEINE KÜHE"
------------------------------------------------------------------------
local window = Theme.window(gui, {
	Name = "CowsWindow",
	Title = "MEINE KÜHE",
	Color = Colors.Orange,
	Size = Vector2.new(760, 500),
})

local summary = Theme.label(window.Body, {
	Size = UDim2.new(1, -250, 0, 22),
	Font = Theme.BodyFont,
	TextSize = 15,
	TextColor3 = Colors.SubText,
	Text = "",
	Outline = 0,
})

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(0, 32)
list.Size = UDim2.new(1, 0, 1, -32)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = Colors.SubText
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = window.Body
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(226, 150)
grid.CellPadding = UDim2.fromOffset(12, 12)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list
local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingLeft = UDim.new(0, 4)
listPadding.PaddingRight = UDim.new(0, 14)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.Parent = list

local popupCowId = nil -- Kuh, deren kleines Menü gerade offen ist (wird unten gesetzt)

local function sortKey(cow)
	local group = cow.Hotbar and 1 or (cow.Slot and 3 or 2)
	return group * 100 - (rarityInfo(cow.Rarity).Tier or 0)
end

local windowTab = "cows" -- "cows" | "buckets"

local function renderCows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not inventory then
		return
	end
	local cows = table.clone(inventory.Cows)
	table.sort(cows, function(a, b)
		return sortKey(a) < sortKey(b)
	end)
	local onFarm = 0
	for _, cow in ipairs(cows) do
		if cow.Slot then
			onFarm += 1
		end
	end
	local cells = inventory.CellCount or 36
	summary.Text = ("%d Kühe   ·   %d auf der Farm   ·   %d Felder frei"):format(#cows, onFarm, cells - onFarm)

	for order, cow in ipairs(cows) do
		local info = rarityInfo(cow.Rarity)
		local card = Theme.cowCard(list, {
			Name = cow.Id,
			LayoutOrder = order,
			Info = info,
			CowName = cow.Name,
			Size = UDim2.fromOffset(226, 150),
		})
		if cow.Mutations and #cow.Mutations > 0 then
			Theme.label(card, {
				Name = "Mutations",
				Position = UDim2.fromOffset(68, 62),
				Size = UDim2.new(1, -76, 0, 13),
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Tiny,
				TextTruncate = Enum.TextTruncate.AtEnd,
				RichText = true,
				Text = cowMutationRichText(cow.Mutations),
			})
		end
		-- Rahmen: ausgewählte Kuh (wird gerade platziert / Menü offen) in Blau
		local cardStroke = card:FindFirstChildOfClass("UIStroke")
		if cardStroke and (cow.Id == placingCowId or cow.Id == popupCowId) then
			cardStroke.Color = Colors.Blue
			cardStroke.Thickness = 3
		end

		-- Ort: Farm (grün) / Hotbar (blau) / Lager (grau) + Milch pro Zug
		local where, whereColor = "Lager", Colors.Grey
		if cow.Slot then
			where, whereColor = "Farm · Feld " .. cow.Slot, Colors.Green
		elseif cow.Hotbar then
			where, whereColor = "Hotbar " .. cow.Hotbar, Colors.Blue
		end
		local whereTag = Theme.tag(card, {
			Name = "Location",
			Position = UDim2.fromOffset(12, 76),
			Color = whereColor,
			Height = 20,
			Text = where,
		})
		whereTag.TextColor3 = Colors.Cream
		-- rechts: Milch pro Zug, bei Kälbern Stufe + Zeit bis ausgewachsen
		local now = workspace:GetServerTimeNow()
		local grown = CowData.IsGrown(cow, now)
		local _, _, stage = CowData.GetGrowth(cow, now)
		Theme.label(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 77),
			Size = UDim2.fromOffset(92, 18),
			Font = Theme.BodyFont,
			TextSize = Theme.TextSize.Small,
			TextColor3 = grown and Colors.SubText or Colors.Orange,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = grown and (CowData.FormatAmount(info.MilkPerPull) .. " / Zug")
				or (stage.Short .. " " .. formatTime(CowData.GetTimeToGrown(cow, now))),
		})

		local buttons = {}
		if cow.Slot then
			table.insert(buttons, {
				"Aufheben",
				Colors.Blue,
				function()
					act("pickup", cow.Id)
				end,
			})
			table.insert(buttons, {
				"Ins Lager",
				Colors.Grey,
				function()
					act("store", cow.Id)
				end,
			})
		else
			table.insert(buttons, {
				"Platzieren",
				Colors.Green,
				function()
					startPlacing(cow.Id)
				end,
			})
			if cow.Hotbar then
				table.insert(buttons, {
					"Ins Lager",
					Colors.Grey,
					function()
						act("store", cow.Id)
					end,
				})
			else
				table.insert(buttons, {
					"In Hotbar",
					Colors.Blue,
					function()
						act("hotbar", cow.Id)
					end,
				})
			end
		end
		for i, def in ipairs(buttons) do
			local button = Theme.button(card, {
				Text = def[1],
				Color = def[2],
				TextSize = 16,
				Radius = 9,
				Lip = 4,
				Size = UDim2.new(0.5, -15, 0, 36),
				Position = UDim2.new((i - 1) * 0.5, i == 1 and 10 or 5, 1, -46),
			})
			button.Activated:Connect(def[3])
		end
	end
end

-- Reiter "Eimer": alle Milch-Eimer (Hotbar + Eimer-Lager), wertvollste zuerst
local function renderBuckets()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not inventory then
		return
	end
	local buckets = inventory.Buckets or {}
	local liters, value = 0, 0
	for _, bucket in ipairs(buckets) do
		liters += bucket.Liters
		value += bucket.Value
	end
	summary.Text = ("%d / %d Eimer   ·   %s L   ·   Wert %s Coins"):format(
		#buckets,
		inventory.MaxBuckets or 100,
		CowData.FormatNumber(liters),
		CowData.FormatNumber(value)
	)

	for order, bucket in ipairs(buckets) do
		local color = bucketColor(bucket)
		local mutated = #bucket.Mutations > 0
		local card = Theme.panel(list, {
			Name = bucket.Id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(226, 150),
			BackgroundColor3 = Colors.Card,
			Radius = Theme.Radius.M,
		})
		local cardStroke = card:FindFirstChildOfClass("UIStroke")
		if cardStroke and bucket.Id == selectedBucketId then
			cardStroke.Color = Colors.Blue
			cardStroke.Thickness = 3
		end
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 0, 5)
		strip.BackgroundColor3 = mutated and color or Colors.Line
		strip.BorderSizePixel = 0
		strip.ZIndex = card.ZIndex
		strip.Parent = card
		Theme.corner(strip, 3)

		bucketIcon(card, 46, UDim2.fromOffset(36, 44), color, mutated and color or nil)
		Theme.label(card, {
			Position = UDim2.fromOffset(68, 12),
			Size = UDim2.new(1, -76, 0, 22),
			TextSize = Theme.TextSize.Heading - 4,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = mutated and color or Colors.Text,
			Text = bucket.Auto and "Auto-Melker" or CowData.FormatMutations(bucket.Mutations, #bucket.Mutations > 1),
		})
		Theme.label(card, {
			Position = UDim2.fromOffset(68, 36),
			Size = UDim2.new(1, -76, 0, 16),
			Font = Theme.BodyFont,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Colors.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = CowData.FormatNumber(bucket.Liters)
				.. " L"
				.. ((bucket.CowName and not bucket.Auto) and (" · von " .. bucket.CowName) or "")
				.. (
					(bucket.CowMutations and #bucket.CowMutations > 0)
						and (" " .. cowMutationIcons(bucket.CowMutations))
					or ""
				),
		})
		Theme.label(card, {
			Position = UDim2.fromOffset(68, 54),
			Size = UDim2.new(1, -76, 0, 16),
			Font = Theme.BodyFont,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Colors.Gold,
			Text = (function()
				local factor = CowData.GetMutationMultiplier(bucket.Mutations)
					* CowData.GetCowMutationMultiplier(bucket.CowMutations)
				return "Wert "
					.. CowData.FormatNumber(bucket.Value)
					.. (factor > 1 and ("  (" .. CowData.FormatMultiplier(factor) .. ")") or "")
			end)(),
		})

		local where, whereColor = "Eimer-Lager", Colors.Grey
		if bucket.Hotbar then
			where, whereColor = "Hotbar " .. bucket.Hotbar, Colors.Blue
		end
		local whereTag = Theme.tag(card, {
			Name = "Location",
			Position = UDim2.fromOffset(12, 78),
			Color = whereColor,
			Height = 20,
			Text = where,
		})
		whereTag.TextColor3 = Colors.Cream

		local buttons = {
			{
				"Verkaufen",
				Colors.Green,
				function()
					bucketAct("sell", bucket.Id)
				end,
			},
		}
		if bucket.Hotbar then
			table.insert(buttons, {
				"Ins Lager",
				Colors.Grey,
				function()
					bucketAct("store", bucket.Id)
				end,
			})
		else
			table.insert(buttons, {
				"In Hotbar",
				Colors.Blue,
				function()
					bucketAct("hotbar", bucket.Id)
				end,
			})
		end
		for i, def in ipairs(buttons) do
			local button = Theme.button(card, {
				Text = def[1],
				Color = def[2],
				TextSize = 16,
				Radius = 9,
				Lip = 4,
				Size = UDim2.new(0.5, -15, 0, 36),
				Position = UDim2.new((i - 1) * 0.5, i == 1 and 10 or 5, 1, -46),
			})
			button.Activated:Connect(def[3])
		end
	end
end

-- Reiter oben rechts: KÜHE / EIMER
local tabButtons = {}
local function renderWindow()
	for tab, entry in pairs(tabButtons) do
		entry.SetColor(tab == windowTab and Colors.Orange or Colors.Steel)
	end
	local bucketCount = inventory and inventory.Buckets and #inventory.Buckets or 0
	tabButtons.buckets.Face.Text = ("EIMER (%d)"):format(bucketCount)
	if windowTab == "buckets" then
		window:SetTitle("MEINE EIMER")
		renderBuckets()
	else
		window:SetTitle("MEINE KÜHE")
		renderCows()
	end
end

for i, def in ipairs({ { "cows", "KÜHE" }, { "buckets", "EIMER" } }) do
	local face, _, setColor = Theme.button(window.Body, {
		Text = def[2],
		Color = Colors.Steel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, i == 1 and -128 or -4, 0, -4),
		Size = UDim2.fromOffset(118, 30),
		TextSize = 15,
		Radius = 8,
		Lip = 3,
	})
	tabButtons[def[1]] = { Face = face, SetColor = setColor }
	face.Activated:Connect(function()
		windowTab = def[1]
		renderWindow()
	end)
end

local function toggleWindow()
	if window:IsOpen() then
		window:Close()
	else
		window:Open()
		renderWindow()
		task.spawn(refresh)
	end
end
UIBus.ToggleInventory.Event:Connect(toggleWindow)

------------------------------------------------------------------------
-- Klick auf eine eigene Kuh -> kleines Menü neben der Maus
------------------------------------------------------------------------
local popup = Theme.panel(gui, {
	Name = "CowMenu",
	Size = UDim2.fromOffset(250, 178),
	BackgroundColor3 = Colors.Panel,
	Visible = false,
	ZIndex = 30,
})
local popupScale = Theme.autoScale(popup)
local popupName = Theme.label(popup, {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -64, 0, 26),
	TextSize = 23,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
})
local popupStatus = Theme.label(popup, {
	Position = UDim2.fromOffset(14, 66),
	Size = UDim2.new(1, -28, 0, 18),
	Font = Theme.BodyFont,
	TextSize = 13,
	Text = "",
	Outline = 0,
})
-- Wachstum: "Kalb · 25 % Milch · groß in 4:12"
local popupGrowth = Theme.label(popup, {
	Position = UDim2.fromOffset(14, 85),
	Size = UDim2.new(1, -28, 0, 16),
	Font = Theme.BodyFont,
	TextSize = 12,
	TextColor3 = Colors.Orange,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Outline = 0,
})
-- Kuh-Mutationen: "Nass · Gefroren · Milch x11 wert"
local popupMutations = Theme.label(popup, {
	Position = UDim2.fromOffset(14, 103),
	Size = UDim2.new(1, -28, 0, 16),
	Font = Theme.BodyFont,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	RichText = true,
	Text = "",
	Outline = 0,
})
local popupClose = Theme.button(popup, {
	Text = "X",
	Color = Colors.Red,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(34, 34),
	TextSize = 18,
	Radius = 8,
	Lip = 3,
})
local milkButton = Theme.button(popup, {
	Text = "Melken",
	Color = Colors.Green,
	TextSize = 19,
	Radius = 10,
	Lip = 4,
	Position = UDim2.new(0, 12, 1, -54),
	Size = UDim2.new(0.5, -16, 0, 42),
})
local pickupButton = Theme.button(popup, {
	Text = "Aufheben",
	Color = Colors.Blue,
	TextSize = 19,
	Radius = 10,
	Lip = 4,
	Position = UDim2.new(0.5, 4, 1, -54),
	Size = UDim2.new(0.5, -16, 0, 42),
})

local popupToken = 0
local popupTag = nil

local function closePopup()
	popup.Visible = false
	popupCowId = nil
	if popupTag then
		popupTag:Destroy()
		popupTag = nil
	end
end

Remotes.CowClicked.OnClientEvent:Connect(function(cow)
	if placingCowId then
		return
	end
	popupCowId = cow.Id
	popupToken += 1
	local token = popupToken
	popupName.Text = cow.Name
	if popupTag then
		popupTag:Destroy()
	end
	local info = rarityInfo(cow.Rarity)
	popupTag = Theme.tag(popup, {
		Position = UDim2.fromOffset(14, 40),
		Color = info.UiColor,
		Text = (info.IsSpecial and "★ " or "") .. info.DisplayName,
	})
	local now = cow.ServerTime or os.time()
	if CowData.IsGrown(cow, now) then
		popupGrowth.Text = "Ausgewachsen · volle Milch"
		popupGrowth.TextColor3 = Color3.fromRGB(140, 214, 124)
	else
		local _, _, stage = CowData.GetGrowth(cow, now)
		popupGrowth.TextColor3 = Colors.Orange
		popupGrowth.Text = ("%s · %d %% Milch · groß in %s"):format(
			stage.Name,
			math.floor(stage.Milk * 100 + 0.5),
			formatTime(CowData.GetTimeToGrown(cow, now))
		)
	end
	if cow.Mutations and #cow.Mutations > 0 then
		popupMutations.Text = ("%s · Milch %s wert"):format(
			cowMutationRichText(cow.Mutations),
			CowData.FormatMultiplier(CowData.GetCowMutationMultiplier(cow.Mutations))
		)
	else
		popupMutations.Text = '<font color="#9aa0a8">Noch keine Mutation – Wetter abwarten!</font>'
	end
	local waitTime = (cow.MilkReadyAt or 0) - (cow.ServerTime or os.time())
	if waitTime > 0 then
		popupStatus.Text = "Braucht noch " .. formatTime(waitTime) .. " Pause"
		popupStatus.TextColor3 = Colors.Orange
	else
		popupStatus.Text = "Bereit zum Melken"
		popupStatus.TextColor3 = Color3.fromRGB(140, 214, 124)
	end

	-- neben der Maus, aber ganz im Bild (Inset abziehen, weil diese GUI ihn nicht ignoriert)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local mouse = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
	local w, h = 250 * popupScale.Scale, 178 * popupScale.Scale
	popup.Position = UDim2.fromOffset(
		math.clamp(mouse.X + 18, 8, viewport.X - w - 8),
		math.clamp(mouse.Y - h / 2, 8, viewport.Y - h - 110)
	)
	popup.Visible = true
	task.delay(8, function()
		if popupToken == token then
			closePopup()
		end
	end)
end)

popupClose.Activated:Connect(closePopup)
milkButton.Activated:Connect(function()
	local cowId = popupCowId
	closePopup()
	if cowId then
		act("milk", cowId)
	end
end)
pickupButton.Activated:Connect(function()
	local cowId = popupCowId
	closePopup()
	if cowId then
		act("pickup", cowId)
	end
end)

------------------------------------------------------------------------
-- Eingaben
------------------------------------------------------------------------
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local index = NUMBER_KEYS[input.KeyCode]
	if index and index <= HOTBAR_SIZE then
		selectHotbar(index)
	elseif input.KeyCode == Enum.KeyCode.I then
		toggleWindow()
	elseif input.KeyCode == Enum.KeyCode.X or input.UserInputType == Enum.UserInputType.MouseButton2 then
		if placingCowId then
			stopPlacing()
		end
	elseif
		input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	then
		if placingCowId then
			tryPlaceAt(input.Position)
		elseif popup.Visible then
			-- Klick daneben schließt das Kuh-Menü (Klick auf eine andere Kuh öffnet gleich ein neues)
			closePopup()
		end
	end
end)

------------------------------------------------------------------------
-- Aktualisieren
------------------------------------------------------------------------
table.insert(refreshCallbacks, function()
	-- ausgewählter Eimer verkauft oder ins Lager gelegt? -> Auswahl weg, sonst Details auffrischen
	if selectedBucketId and not placingCowId then
		local bucket = findBucket(selectedBucketId)
		if bucket and bucket.Hotbar then
			selectedIndex = bucket.Hotbar
			showHint(bucketDescription(bucket))
		else
			stopPlacing()
		end
	end
	renderHotbar()
	if window:IsOpen() then
		renderWindow()
	end
	if placingCowId then
		local cow = findCow(placingCowId)
		if not cow or cow.Slot then
			stopPlacing()
		else
			paintCells()
		end
	end
end)

-- Beim Melken braucht man beide Hände: getragenen Eimer ablegen
Remotes.MilkingStarted.OnClientEvent:Connect(function()
	if selectedBucketId then
		stopPlacing()
	end
end)

-- Nach dem Melken: den neuen Eimer gleich in die Hand nehmen (wenn er in der Hotbar liegt)
Remotes.MilkingEnded.OnClientEvent:Connect(function(_, _, _, bucketId)
	if type(bucketId) ~= "string" then
		return
	end
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < 3 do
			local bucket = findBucket(bucketId)
			if bucket then
				if bucket.Hotbar and not placingCowId then
					selectBucket(bucket)
				end
				return
			end
			task.wait(0.1)
		end
	end)
end)

Remotes.InventoryChanged.OnClientEvent:Connect(function()
	task.spawn(refresh)
end)
CollectionService:GetInstanceAddedSignal("FarmCell"):Connect(function()
	if placingCowId then
		collectMyCells()
		paintCells()
	end
end)

renderHotbar()
task.spawn(function()
	while not inventory do
		refresh()
		if not inventory then
			task.wait(1)
		end
	end
end)
