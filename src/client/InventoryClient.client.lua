-- InventoryClient.client.lua
-- Kühe verwalten:
--   * Hotbar unten in der Mitte (6 Plätze, Tasten 1-6) im Roblox-Stil
--   * Fenster "MEINE KÜHE" (Taste I oder Knopf KÜHE): alle Kühe mit Knöpfen
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

local function hotbarCow(index)
	if not inventory then
		return nil
	end
	for _, cow in ipairs(inventory.Cows) do
		if cow.Hotbar == index then
			return cow
		end
	end
	return nil
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
	slot.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	slot.BackgroundTransparency = 0.35
	slot.Parent = hotbar
	Theme.corner(slot, 10)
	local stroke = Theme.border(slot, 2, Color3.new(1, 1, 1), 0.75)
	Theme.label(slot, {
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.fromOffset(16, 16),
		Font = Theme.BodyFont,
		TextSize = 13,
		Text = tostring(index),
		Outline = 1,
	})
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = slot
	slots[index] = { Button = slot, Stroke = stroke, Content = content }
end

local function renderHotbar()
	for index, widget in ipairs(slots) do
		for _, child in ipairs(widget.Content:GetChildren()) do
			child:Destroy()
		end
		local cow = hotbarCow(index)
		if cow then
			cowIcon(widget.Content, cow.Rarity, 34, UDim2.new(0.5, 0, 0, 27))
			Theme.label(widget.Content, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(1, -6, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Theme.BodyFont,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = rarityInfo(cow.Rarity).UiColor,
				Text = cow.Name,
				Outline = 1,
			})
		end
		local selected = selectedIndex == index
		widget.Stroke.Transparency = selected and 0 or 0.75
		widget.Stroke.Thickness = selected and 3 or 2
		widget.Button.BackgroundTransparency = selected and 0.1 or 0.35
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

local hintToken = 0
local function showHint(text, isError, duration)
	hintToken += 1
	local token = hintToken
	hintText.Text = text
	hintText.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Colors.Text
	cancelButton.Parent.Visible = placingCowId ~= nil
	hint.Visible = true
	if duration then
		task.delay(duration, function()
			if hintToken == token and not placingCowId then
				hint.Visible = false
			end
		end)
	end
end

------------------------------------------------------------------------
-- Platzier-Modus
------------------------------------------------------------------------
local FREE_COLOR = Color3.fromRGB(110, 235, 110)
local TAKEN_COLOR = Color3.fromRGB(240, 90, 80)
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
	placingCowId = cowId
	selectedIndex = cow.Hotbar
	collectMyCells()
	paintCells()
	renderHotbar()
	showHint(("%s platzieren: klicke ein grünes Feld auf deiner Farm"):format(cow.Name))
end

local function selectHotbar(index)
	if selectedIndex == index then
		stopPlacing()
		return
	end
	local cow = hotbarCow(index)
	if cow then
		startPlacing(cow.Id)
	else
		stopPlacing()
	end
end

for index, widget in ipairs(slots) do
	widget.Button.Activated:Connect(function()
		selectHotbar(index)
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
	Size = UDim2.new(1, 0, 0, 22),
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

local function locationText(cow)
	if cow.Slot then
		return "Farm · Feld " .. cow.Slot
	elseif cow.Hotbar then
		return "Hotbar · Platz " .. cow.Hotbar
	end
	return "Lager"
end

local function sortKey(cow)
	local group = cow.Hotbar and 1 or (cow.Slot and 3 or 2)
	return group * 100 - (rarityInfo(cow.Rarity).Tier or 0)
end

local function renderWindow()
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
		local card = Theme.panel(list, {
			Name = cow.Id,
			LayoutOrder = order,
			BackgroundColor3 = Colors.Card,
			Radius = 12,
		})
		-- farbiger Streifen oben = Seltenheit
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 0, 6)
		strip.BackgroundColor3 = info.UiColor
		strip.BorderSizePixel = 0
		strip.Parent = card
		Theme.corner(strip, 4)

		cowIcon(card, cow.Rarity, 48, UDim2.fromOffset(38, 44))
		Theme.label(card, {
			Position = UDim2.fromOffset(72, 14),
			Size = UDim2.new(1, -80, 0, 24),
			TextSize = 21,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = cow.Name,
		})
		Theme.tag(card, {
			Position = UDim2.fromOffset(72, 42),
			Color = info.UiColor,
			Text = (info.IsSpecial and "★ " or "") .. info.DisplayName,
		})
		Theme.label(card, {
			Position = UDim2.fromOffset(12, 74),
			Size = UDim2.new(1, -24, 0, 16),
			Font = Theme.BodyFont,
			TextSize = 12,
			TextColor3 = Colors.SubText,
			Text = ("%s   ·   %d Milch pro Zug"):format(locationText(cow), info.MilkPerPull),
			Outline = 0,
		})

		local buttons = {}
		if cow.Slot then
			table.insert(buttons, { "Aufheben", Colors.Blue, function()
				act("pickup", cow.Id)
			end })
			table.insert(buttons, { "Ins Lager", Colors.Grey, function()
				act("store", cow.Id)
			end })
		else
			table.insert(buttons, { "Platzieren", Colors.Green, function()
				startPlacing(cow.Id)
			end })
			if cow.Hotbar then
				table.insert(buttons, { "Ins Lager", Colors.Grey, function()
					act("store", cow.Id)
				end })
			else
				table.insert(buttons, { "In Hotbar", Colors.Blue, function()
					act("hotbar", cow.Id)
				end })
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
	Size = UDim2.fromOffset(250, 158),
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

local popupCowId = nil
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
	local waitTime = (cow.MilkReadyAt or 0) - (cow.ServerTime or os.time())
	if waitTime > 0 then
		popupStatus.Text = "Braucht noch " .. formatTime(waitTime) .. " Pause"
		popupStatus.TextColor3 = Color3.fromRGB(255, 190, 90)
	else
		popupStatus.Text = "Bereit zum Melken"
		popupStatus.TextColor3 = Color3.fromRGB(130, 240, 140)
	end

	-- neben der Maus, aber ganz im Bild (Inset abziehen, weil diese GUI ihn nicht ignoriert)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local mouse = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
	local w, h = 250 * popupScale.Scale, 158 * popupScale.Scale
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
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
