-- GearClient.client.lua
-- Werkzeug auf dem Client (Daten: CowData.Gears, Server: GearManager.server.lua):
--   * Fenster "MEIN WERKZEUG" (Taste G oder Knopf WERKZEUG links): was im Rucksack liegt und was
--     auf der Weide steht (mit Restzeit). "Aufstellen" startet den Aufstell-Modus.
--   * Aufstell-Modus: auf der eigenen Weide leuchten die Ecken zwischen den Feldern (grün = frei),
--     dazu eine durchsichtige Vorschau mit Wirkungsbereich. Klick = aufstellen; X / Rechtsklick = Abbrechen.
--   * Kuh anklicken: unter dem Kuh-Menü (InventoryClient) erscheinen Knöpfe für Werkzeug, das man an
--     einer Kuh benutzt (Heubündel, Striegel, Wunder-Spray).
-- Der Server prüft alles (Remotes.GearAction).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local GearModels = require(ReplicatedStorage.Shared:WaitForChild("GearModels"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))
local GearView = require(script.Parent:WaitForChild("GearView"))
local UIBus = require(script.Parent:WaitForChild("UIBus"))

local Colors = Theme.Colors
local Gears = CowData.Gears
local player = Players.LocalPlayer

local FREE_COLOR = Color3.fromRGB(120, 220, 110)
local TAKEN_COLOR = Color3.fromRGB(220, 100, 96)

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

------------------------------------------------------------------------
-- Daten vom Server (dasselbe Inventar wie InventoryClient, der Server merkt sich die Antwort kurz)
------------------------------------------------------------------------
local inventory = nil
local onRefresh = {}

local function refresh()
	local ok, result = pcall(function()
		return Remotes.GetInventory:InvokeServer()
	end)
	if ok and type(result) == "table" then
		inventory = result
		for _, callback in ipairs(onRefresh) do
			task.spawn(callback)
		end
	end
end

local function gearCount(gearType)
	return inventory and inventory.Gears and inventory.Gears[gearType] or 0
end

local function findCow(cowId)
	for _, cow in ipairs(inventory and inventory.Cows or {}) do
		if cow.Id == cowId then
			return cow
		end
	end
	return nil
end

local function gearAction(action, gearType, target)
	local called, ok, message = pcall(function()
		return Remotes:WaitForChild("GearAction", 5):InvokeServer(action, gearType, target)
	end)
	if not called then
		return false, "Keine Antwort vom Server."
	end
	return ok == true, message
end

------------------------------------------------------------------------
-- Oberfläche
------------------------------------------------------------------------
local gui = Theme.screenGui("Gear", 6, false)
gui.Parent = player:WaitForChild("PlayerGui")

-- Hinweis-Leiste (Aufstell-Modus / Fehler)
local hint = Theme.panel(gui, {
	Name = "GearHint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -160),
	Size = UDim2.fromOffset(560, 56),
	BackgroundColor3 = Colors.Panel,
	Visible = false,
})
Theme.autoScale(hint)
local hintText = Theme.label(hint, {
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(1, -150, 1, 0),
	Font = Theme.BodyFont,
	TextSize = 15,
	TextWrapped = true,
	Text = "",
})
local cancelButton = Theme.button(hint, {
	Text = "Abbrechen",
	Color = Colors.Red,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(120, 40),
	TextSize = 17,
	Radius = 10,
	Lip = 4,
})

local hintToken = 0
local function showHint(text, color, duration)
	hintToken += 1
	local token = hintToken
	hintText.Text = text
	hintText.TextColor3 = color or Colors.Text
	hint.Visible = true
	if duration then
		task.delay(duration, function()
			if hintToken == token then
				hint.Visible = false
			end
		end)
	end
end

------------------------------------------------------------------------
-- Aufstell-Modus
------------------------------------------------------------------------
local placing = nil -- { Type, Origin, Plot, Markers = { [corner] = part }, Ghost, Hovered }
local markerFolder = nil

local function findMyPlot()
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

local function takenCorners()
	local taken = {}
	local now = serverNow()
	for _, entry in ipairs(inventory and inventory.PlacedGear or {}) do
		if entry.ExpiresAt > now then
			taken[entry.Corner] = true
		end
	end
	return taken
end

local function stopPlacing()
	if markerFolder then
		markerFolder:Destroy()
		markerFolder = nil
	end
	if placing and placing.Ghost then
		placing.Ghost:Destroy()
	end
	placing = nil
	hint.Visible = false
end

local function paintMarkers()
	if not placing then
		return
	end
	local taken = takenCorners()
	for corner, marker in pairs(placing.Markers) do
		local busy = taken[corner]
		marker.Color = busy and TAKEN_COLOR or FREE_COLOR
		marker.Transparency = corner == placing.Hovered and 0.05 or 0.4
	end
end

local function startPlacing(gearType)
	stopPlacing()
	local slot = player:GetAttribute("PlotSlot")
	local plot = findMyPlot()
	if not slot or not plot then
		showHint("Du hast noch keine Farm.", Colors.Red, 3)
		return
	end
	Theme.closeAllWindows()
	local origin = CowData.GetPlotOrigin(slot)
	placing = { Type = gearType, Origin = origin, Plot = plot, Markers = {}, Hovered = nil }

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "GearPlacement"
	markerFolder.Parent = workspace
	for corner = 1, CowData.GetGearCornerCount() do
		local marker = Instance.new("Part")
		marker.Name = "Corner" .. corner
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CastShadow = false
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.15, 3.2, 3.2)
		marker.Material = Enum.Material.Neon
		marker.CFrame = origin
			* CowData.GetGearCornerLocal(corner)
			* CFrame.new(0, 0.12, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		marker:SetAttribute("Corner", corner)
		marker.Parent = markerFolder
		placing.Markers[corner] = marker
	end

	local info = Gears[gearType]
	local ghost = GearModels.Build(gearType, origin * CowData.GetGearCornerLocal(1), { Ghost = true })
	if ghost then
		local ring = GearModels.AddRangeRing(ghost, origin * CowData.GetGearCornerLocal(1), info.Radius, info.Color)
		ring.Transparency = 0.7
		ghost.Parent = markerFolder
		placing.Ghost = ghost
	end
	paintMarkers()
	showHint(
		("%s %s aufstellen: Klicke auf einen grünen Punkt deiner Weide. (X = Abbrechen)"):format(
			info.Icon,
			info.DisplayName
		)
	)
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

-- Ecke unter der Maus / dem Finger (oder nil).
-- isViewport: Position kommt von GetMouseLocation (mit Inset), sonst von input.Position (ohne)
local function cornerAt(position, isViewport)
	local camera = workspace.CurrentCamera
	if not placing or not camera then
		return nil
	end
	local ray = isViewport and camera:ViewportPointToRay(position.X, position.Y)
		or camera:ScreenPointToRay(position.X, position.Y)
	raycastParams.FilterDescendantsInstances = { placing.Plot, markerFolder }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, raycastParams)
	if not result then
		return nil
	end
	local corner = result.Instance:GetAttribute("Corner")
	if corner then
		return corner
	end
	return CowData.GetNearestGearCorner(placing.Origin:PointToObjectSpace(result.Position), 7)
end

RunService.RenderStepped:Connect(function()
	if not placing then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local corner = cornerAt(mouse, true)
	if corner ~= placing.Hovered then
		placing.Hovered = corner
		paintMarkers()
		if placing.Ghost then
			if corner then
				placing.Ghost:PivotTo(placing.Origin * CowData.GetGearCornerLocal(corner))
			end
			for _, item in ipairs(placing.Ghost:GetDescendants()) do
				if item:IsA("BasePart") then
					item.LocalTransparencyModifier = corner and 0 or 1
				end
			end
		end
	end
end)

local placeBusy = false
local function tryPlace(screenPosition)
	if not placing or placeBusy then
		return
	end
	local corner = cornerAt(screenPosition)
	if not corner then
		showHint("Klicke auf einen grünen Punkt auf deiner Weide.", Colors.Orange)
		return
	end
	if takenCorners()[corner] then
		showHint("Dort steht schon etwas – nimm einen grünen Punkt.", Colors.Orange)
		return
	end
	placeBusy = true
	local gearType = placing.Type
	local ok, message = gearAction("Place", gearType, corner)
	placeBusy = false
	if ok then
		stopPlacing()
		showHint(message or "Aufgestellt!", Color3.fromRGB(140, 214, 124), 3)
		task.spawn(refresh)
	else
		showHint(message or "Aufstellen ging nicht.", Colors.Red)
	end
end

cancelButton.Activated:Connect(stopPlacing)

------------------------------------------------------------------------
-- Fenster "MEIN WERKZEUG"
------------------------------------------------------------------------
local window = Theme.window(gui, {
	Name = "GearWindow",
	Title = "MEIN WERKZEUG",
	Color = Colors.Orange,
	Size = Vector2.new(760, 500),
})
local summary = Theme.label(window.Body, {
	Size = UDim2.new(1, 0, 0, 24),
	Font = Theme.BodyFont,
	TextSize = 15,
	TextColor3 = Colors.SubText,
	Text = "",
})
local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(0, 32)
list.Size = UDim2.new(1, 0, 1, -32)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = Colors.Line
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = Theme.zOf(window.Body)
list.Parent = window.Body
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(226, 186)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list

local timerLabels = {} -- [TextLabel] = ExpiresAt

local function gearCard(order, gearType, title, titleColor)
	local info = Gears[gearType]
	local card = Theme.panel(list, {
		Name = gearType,
		LayoutOrder = order,
		BackgroundColor3 = Colors.Card,
		Radius = Theme.Radius.M,
	})
	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 0, 5)
	strip.BackgroundColor3 = info.Color
	strip.BorderSizePixel = 0
	strip.ZIndex = card.ZIndex
	strip.Parent = card
	Theme.corner(strip, 3)
	GearView.new(card, gearType, {
		Position = UDim2.fromOffset(6, 10),
		Size = UDim2.fromOffset(78, 78),
		ZIndex = card.ZIndex + 1,
	})
	Theme.label(card, {
		Position = UDim2.fromOffset(88, 12),
		Size = UDim2.new(1, -96, 0, 22),
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = info.Color,
		Text = info.Icon .. " " .. info.DisplayName,
	})
	Theme.label(card, {
		Position = UDim2.fromOffset(88, 36),
		Size = UDim2.new(1, -96, 0, 20),
		Font = Theme.BodyFont,
		TextSize = 15,
		TextColor3 = titleColor or Colors.Text,
		Text = title,
	})
	Theme.label(card, {
		Position = UDim2.fromOffset(10, 92),
		Size = UDim2.new(1, -20, 0, 44),
		Font = Theme.BodyFont,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Colors.SubText,
		Text = info.Description,
	})
	return card
end

local function renderWindow()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(timerLabels)
	if not inventory then
		summary.Text = "Lädt ..."
		return
	end

	local owned, order = 0, 0
	for _, gearType in ipairs(CowData.GearOrder) do
		local count = gearCount(gearType)
		if count > 0 then
			owned += count
			order += 1
			local info = Gears[gearType]
			local card = gearCard(order, gearType, ("x%d im Rucksack"):format(count))
			local buttonText = info.Kind == "Place" and "Aufstellen" or "Kuh anklicken"
			local face = Theme.button(card, {
				Text = buttonText,
				Color = info.Kind == "Place" and Colors.Green or Colors.Steel,
				TextSize = 16,
				Radius = 9,
				Lip = 4,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -20, 0, 36),
			})
			face.Activated:Connect(function()
				if info.Kind == "Place" then
					startPlacing(gearType)
				else
					window:Close()
					showHint(
						("%s Klicke eine deiner Kühe an und wähle %s."):format(info.Icon, info.DisplayName),
						nil,
						5
					)
				end
			end)
		end
	end

	local now = serverNow()
	local placed = 0
	for _, entry in ipairs(inventory.PlacedGear or {}) do
		if entry.ExpiresAt > now then
			placed += 1
			order += 1
			local card = gearCard(order, entry.Type, "steht auf der Weide", Color3.fromRGB(140, 214, 124))
			local timer = Theme.label(card, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				Size = UDim2.new(1, -20, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 18,
				TextColor3 = Colors.Gold,
				Text = "",
			})
			timerLabels[timer] = entry.ExpiresAt
		end
	end

	summary.Text = ("%d Werkzeuge im Rucksack  ·  %d / %d auf der Weide"):format(
		owned,
		placed,
		CowData.GearSettings.MaxPlaced
	)
	if order == 0 then
		Theme.label(list, {
			Size = UDim2.fromOffset(226, 186),
			TextWrapped = true,
			TextColor3 = Colors.SubText,
			Text = "Noch kein Werkzeug. Kauf welches im WERKZEUG-Shop am Marktplatz!",
		})
	end
end

table.insert(onRefresh, function()
	if window:IsOpen() then
		renderWindow()
	end
	paintMarkers()
end)

local function toggleWindow()
	if window:IsOpen() then
		window:Close()
	else
		stopPlacing()
		window:Open()
		renderWindow()
		task.spawn(refresh)
	end
end
UIBus.ToggleGear.Event:Connect(toggleWindow)

-- Restzeiten im Fenster
task.spawn(function()
	while true do
		task.wait(1)
		if window:IsOpen() then
			local now = serverNow()
			for timer, expiresAt in pairs(timerLabels) do
				if timer.Parent then
					timer.Text = "⏳ noch " .. formatTime(expiresAt - now)
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Knöpfe unter dem Kuh-Menü (InventoryClient, Frame "CowMenu")
------------------------------------------------------------------------
local cowBar = nil
local barCowId = nil

local function ensureCowBar()
	if cowBar and cowBar.Parent then
		return cowBar
	end
	local inventoryGui = player.PlayerGui:FindFirstChild("Inventory")
	local popup = inventoryGui and inventoryGui:FindFirstChild("CowMenu")
	if not popup then
		return nil
	end
	cowBar = Instance.new("Frame")
	cowBar.Name = "GearBar"
	cowBar.Position = UDim2.new(0, 0, 1, 6)
	cowBar.Size = UDim2.new(1, 0, 0, 44)
	cowBar.BackgroundTransparency = 1
	cowBar.ZIndex = popup.ZIndex
	cowBar.Parent = popup
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = cowBar
	return cowBar
end

local function buildCowBar(cowId)
	local bar = ensureCowBar()
	if not bar then
		return
	end
	barCowId = cowId
	for _, child in ipairs(bar:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local usable = {}
	for _, gearType in ipairs(CowData.GearOrder) do
		if Gears[gearType].Kind == "Cow" and gearCount(gearType) > 0 then
			table.insert(usable, gearType)
		end
	end
	bar.Visible = #usable > 0
	local cow = findCow(cowId)
	for i, gearType in ipairs(usable) do
		local info = Gears[gearType]
		local text = ("%s %s x%d"):format(info.Icon, info.DisplayName, gearCount(gearType))
		if gearType == "Brush" and cow and cow.Brushed then
			text = info.Icon .. " gestriegelt ✓"
		end
		local face = Theme.button(bar, {
			Text = text,
			Color = Colors.Teal,
			TextSize = 13,
			Radius = 9,
			Lip = 3,
			LayoutOrder = i,
			Size = UDim2.new(1 / #usable, -6 * (#usable - 1) / #usable, 1, 0),
		})
		face.TextWrapped = true
		face.Activated:Connect(function()
			local target = barCowId
			if not target then
				return
			end
			bar.Parent.Visible = false
			local ok, message = gearAction("UseOnCow", gearType, target)
			if not ok then
				showHint(message or "Das ging nicht.", Colors.Orange, 3)
			end
			task.spawn(refresh)
		end)
	end
end

Remotes.CowClicked.OnClientEvent:Connect(function(cow)
	if placing or type(cow) ~= "table" then
		return
	end
	buildCowBar(cow.Id)
end)

------------------------------------------------------------------------
-- Eingaben
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		toggleWindow()
	elseif placing then
		if input.KeyCode == Enum.KeyCode.X or input.UserInputType == Enum.UserInputType.MouseButton2 then
			stopPlacing()
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			tryPlace(Vector2.new(input.Position.X, input.Position.Y))
		end
	end
end)

Remotes.InventoryChanged.OnClientEvent:Connect(function()
	task.spawn(refresh)
end)

-- Teleport, Tod usw.: Aufstell-Modus beenden
UIBus.CloseOverlays.Event:Connect(stopPlacing)
player.CharacterRemoving:Connect(stopPlacing)

task.spawn(function()
	while not inventory do
		refresh()
		if not inventory then
			task.wait(1)
		end
	end
end)
