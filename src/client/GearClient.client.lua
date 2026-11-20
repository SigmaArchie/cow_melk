-- GearClient.client.lua
-- Werkzeug auf dem Client (Daten: CowData.Gears, Server: GearManager.server.lua):
--   * Fenster "MEIN WERKZEUG" (Taste G oder Knopf WERKZEUG links): was im Rucksack liegt und was
--     auf der Farm steht (mit Restzeit). "Aufstellen" / "In die Hand" startet den passenden Modus,
--     "Hotbar" legt den Stapel in die Hotbar (oder nimmt ihn heraus).
--   * Hotbar (InventoryClient): Werkzeug-Platz anklicken / Zahl drücken -> UIBus.SelectGear.
--   * Aufstell-Modus: Vorschau folgt der Maus irgendwo auf der eigenen Farm, die Kuh-Plätze in
--     Reichweite leuchten grün. Klick = aufstellen, R = drehen, X / Rechtsklick = fertig.
--   * Kuh-Modus (Heubündel, Striegel, Wunder-Spray): eigene Kuh anklicken = benutzen. Zusätzlich gibt
--     es Knöpfe unter dem Kuh-Menü (InventoryClient).
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

local function gearAction(action, gearType, ...)
	local args = table.pack(...)
	local called, ok, message = pcall(function()
		return Remotes:WaitForChild("GearAction", 5):InvokeServer(action, gearType, table.unpack(args, 1, args.n))
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
	cancelButton.Parent.Visible = player:GetAttribute("GearMode") ~= nil
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
-- Aufstell-Modus: Werkzeug irgendwo auf die eigene Farm stellen (wie die Sprinkler in Grow a Garden).
-- Die 36 Kuh-Plätze leuchten grün, wenn das Werkzeug sie von der Mausposition aus erreicht.
-- Kuh-Modus: Werkzeug für Kühe "in der Hand" – eine eigene Kuh anklicken benutzt es.
------------------------------------------------------------------------
local SPOT_IDLE = Color3.fromRGB(236, 236, 226)
local ROTATE_STEP = 45

local placing = nil -- { Type, Origin, GroundY, Ghost, Ring, Label, Spots, X, Z, Yaw, Shown, Valid }
local cowMode = nil -- Werkzeug-Name (Kind "Cow") oder nil
local markerFolder = nil

local function currentMode()
	return placing and placing.Type or cowMode
end

-- InventoryClient fragt das ab: solange Werkzeug in der Hand ist, öffnet ein Kuh-Klick kein Kuh-Menü
local function setModeAttribute(gearType)
	player:SetAttribute("GearMode", gearType)
end

local function activeGear()
	local now = serverNow()
	local list = {}
	for _, entry in ipairs(inventory and inventory.PlacedGear or {}) do
		if entry.ExpiresAt > now and type(entry.X) == "number" then
			table.insert(list, entry)
		end
	end
	return list
end

-- Dieselben Regeln wie GearService.CanPlace (der Server prüft trotzdem selbst)
local function checkSpot(x, z)
	if not CowData.IsGearPositionValid(x, z) then
		return false, "Nur auf deiner eigenen Farm"
	end
	local active = activeGear()
	for _, entry in ipairs(active) do
		if Vector3.new(entry.X - x, 0, entry.Z - z).Magnitude < CowData.GearSettings.MinSpacing then
			return false, "Zu nah an anderem Werkzeug"
		end
	end
	if #active >= CowData.GearSettings.MaxPlaced then
		return false, ("Schon %d Werkzeuge aufgestellt"):format(CowData.GearSettings.MaxPlaced)
	end
	return true
end

-- Anleitung unten in der Hinweis-Leiste (passend zum aktiven Modus)
local function modeHint()
	local gearType = currentMode()
	if not gearType then
		hint.Visible = false
		return
	end
	local info = Gears[gearType]
	if placing then
		showHint(
			("%s %s x%d: Klick auf deine Farm zum Aufstellen. R = drehen, X = fertig"):format(
				info.Icon,
				info.DisplayName,
				gearCount(gearType)
			)
		)
	else
		showHint(
			("%s %s x%d in der Hand: Klicke eine deiner Kühe an. X = weglegen"):format(
				info.Icon,
				info.DisplayName,
				gearCount(gearType)
			)
		)
	end
end

-- kurze Meldung, danach wieder die Anleitung
local function flashHint(text, color)
	showHint(text, color)
	local token = hintToken
	task.delay(2.5, function()
		if hintToken == token then
			modeHint()
		end
	end)
end

-- notify = true: GearClient beendet selbst (Abbrechen, aufgebraucht, ...) -> Hotbar hebt die Auswahl auf
local function endModes(notify)
	local ended = currentMode()
	if markerFolder then
		markerFolder:Destroy()
		markerFolder = nil
	end
	placing = nil
	cowMode = nil
	setModeAttribute(nil)
	hint.Visible = false
	if notify and ended then
		UIBus.GearModeEnded:Fire(ended)
	end
end

local function stopPlacing()
	endModes(true)
end

local function myCowCells()
	local cells = {}
	for _, cow in ipairs(inventory and inventory.Cows or {}) do
		if cow.Slot then
			cells[cow.Slot] = true
		end
	end
	return cells
end

-- Vorschau an die Stelle (x, z) setzen (nil = Maus nicht über dem Boden)
local function updateGhost(x, z, force)
	if not placing then
		return
	end
	if not force and x == placing.X and z == placing.Z and placing.Shown == placing.Yaw then
		return
	end
	placing.X, placing.Z, placing.Shown = x, z, placing.Yaw
	local visible = x ~= nil
	local ok, reason = false, nil
	if visible then
		ok, reason = checkSpot(x, z)
	end
	placing.Valid = ok

	if placing.Ghost then
		if visible then
			placing.Ghost:PivotTo(
				placing.Origin * CFrame.new(x, CowData.Map.GroundTop, z) * CFrame.Angles(0, math.rad(placing.Yaw), 0)
			)
		end
		for _, item in ipairs(placing.Ghost:GetDescendants()) do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = visible and 0 or 1
			end
		end
		if placing.Ring then
			placing.Ring.Color = ok and Gears[placing.Type].Color or TAKEN_COLOR
		end
	end

	-- Kuh-Plätze in Reichweite
	local cows = myCowCells()
	local spots, reached = 0, 0
	for cell, spot in pairs(placing.Spots) do
		local covered = visible and CowData.GearCoversCell(placing.Type, x, z, cell)
		spot.Color = covered and FREE_COLOR or SPOT_IDLE
		spot.Transparency = covered and 0.05 or 0.6
		if covered then
			spots += 1
			if cows[cell] then
				reached += 1
			end
		end
	end

	if placing.Label then
		placing.Label.Enabled = visible
		local text = placing.Label:FindFirstChild("Text")
		if text then
			if ok then
				text.Text = ("🐄 %d %s in Reichweite  ·  %d %s"):format(
					reached,
					reached == 1 and "Kuh" or "Kühe",
					spots,
					spots == 1 and "Platz" or "Plätze"
				)
				text.TextColor3 = Color3.fromRGB(190, 245, 170)
			else
				text.Text = "✖ " .. (reason or "Hier nicht")
				text.TextColor3 = Color3.fromRGB(255, 160, 150)
			end
		end
	end
end

local function startPlacing(gearType)
	endModes(false)
	local info = Gears[gearType]
	local slot = player:GetAttribute("PlotSlot")
	if not info or info.Kind ~= "Place" then
		return
	end
	if not slot then
		showHint("Du hast noch keine Farm.", Colors.Red, 3)
		UIBus.GearModeEnded:Fire(gearType)
		return
	end
	if gearCount(gearType) <= 0 then
		showHint(("Du hast kein %s mehr."):format(info.DisplayName), Colors.Orange, 3)
		UIBus.GearModeEnded:Fire(gearType)
		return
	end
	Theme.closeAllWindows()
	local origin = CowData.GetPlotOrigin(slot)
	placing = {
		Type = gearType,
		Origin = origin,
		GroundY = (origin * CFrame.new(0, CowData.Map.GroundTop, 0)).Position.Y,
		Spots = {},
		Yaw = 0,
	}
	setModeAttribute(gearType)
	UIBus.GearModeStarted:Fire(gearType)

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "GearPlacement"
	markerFolder.Parent = workspace
	for cell = 1, CowData.GetGridCellCount() do
		local spot = Instance.new("Part")
		spot.Name = "Spot" .. cell
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanTouch = false
		spot.CanQuery = false
		spot.CastShadow = false
		spot.Shape = Enum.PartType.Cylinder
		spot.Size = Vector3.new(0.2, 2.8, 2.8)
		spot.Material = Enum.Material.Neon
		spot.Color = SPOT_IDLE
		spot.Transparency = 0.6
		spot.CFrame = origin
			* CFrame.new(CowData.GetCowHomeLocal(cell) + Vector3.new(0, 0.12, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		spot.Parent = markerFolder
		placing.Spots[cell] = spot
	end

	local start = origin * CFrame.new(0, CowData.Map.GroundTop, 0)
	local ghost = GearModels.Build(gearType, start, { Ghost = true })
	if ghost then
		local ring = GearModels.AddRangeRing(ghost, start, info.Radius, info.Color)
		ring.Transparency = 0.6
		placing.Ring = ring
		-- Schild über der Vorschau: wie viele Kühe erreicht werden (oder warum es hier nicht geht)
		local anchor = Instance.new("Part")
		anchor.Name = "LabelAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = start * CFrame.new(0, 8, 0)
		anchor.Parent = ghost
		local label = Instance.new("BillboardGui")
		label.Name = "ReachLabel"
		label.Size = UDim2.fromOffset(280, 34)
		label.AlwaysOnTop = true
		label.LightInfluence = 0
		label.Parent = anchor
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(28, 32, 38)
		text.BackgroundTransparency = 0.25
		text.Font = Theme.BodyFont
		text.TextSize = 17
		text.Text = ""
		text.Parent = label
		Theme.corner(text, 8)
		placing.Label = label
		ghost.Parent = markerFolder
		placing.Ghost = ghost
	end
	updateGhost(nil, nil, true)
	modeHint()
end

local function startCowMode(gearType)
	endModes(false)
	local info = Gears[gearType]
	if not info or info.Kind ~= "Cow" then
		return
	end
	if gearCount(gearType) <= 0 then
		showHint(("Du hast kein %s mehr."):format(info.DisplayName), Colors.Orange, 3)
		UIBus.GearModeEnded:Fire(gearType)
		return
	end
	Theme.closeAllWindows()
	cowMode = gearType
	setModeAttribute(gearType)
	UIBus.GearModeStarted:Fire(gearType)
	modeHint()
end

-- Werkzeug aus der Hotbar / dem Fenster in die Hand nehmen (nil = weglegen)
local function selectGear(gearType)
	local info = gearType and Gears[gearType]
	if not info then
		endModes(false)
	elseif info.Kind == "Place" then
		startPlacing(gearType)
	else
		startCowMode(gearType)
	end
end
UIBus.SelectGear.Event:Connect(selectGear)

-- Stelle auf dem Boden der eigenen Farm unter dem Bildschirmpunkt (lokale x, z; halbe Studs)
-- isViewport: Position kommt von GetMouseLocation (mit Inset), sonst von input.Position (ohne)
local function groundPoint(position, isViewport)
	local camera = workspace.CurrentCamera
	if not placing or not camera then
		return nil
	end
	local ray = isViewport and camera:ViewportPointToRay(position.X, position.Y)
		or camera:ScreenPointToRay(position.X, position.Y)
	if ray.Direction.Y > -0.01 then
		return nil
	end
	local distance = (placing.GroundY - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 or distance > 900 then
		return nil
	end
	local localPoint = placing.Origin:PointToObjectSpace(ray.Origin + ray.Direction * distance)
	local x = math.floor(localPoint.X * 2 + 0.5) / 2
	local z = math.floor(localPoint.Z * 2 + 0.5) / 2
	-- weit neben der Farm: keine Vorschau
	local map = CowData.Map
	if math.abs(x) > map.PlotWidth / 2 + 12 or math.abs(z) > map.PlotDepth / 2 + 12 then
		return nil
	end
	return x, z
end

RunService.RenderStepped:Connect(function()
	if not placing then
		return
	end
	local x, z = groundPoint(UserInputService:GetMouseLocation(), true)
	updateGhost(x, z)
end)

local busy = false
local function tryPlace(screenPosition)
	if not placing or busy then
		return
	end
	local x, z = groundPoint(screenPosition, false)
	if not x then
		flashHint("Klicke auf den Boden deiner Farm.", Colors.Orange)
		return
	end
	local ok, reason = checkSpot(x, z)
	if not ok then
		flashHint(reason .. ".", Colors.Orange)
		return
	end
	busy = true
	local gearType, yaw = placing.Type, placing.Yaw
	local placed, message = gearAction("Place", gearType, x, z, yaw)
	busy = false
	if not placed then
		flashHint(message or "Aufstellen ging nicht.", Colors.Red)
		return
	end
	-- gleich lokal eintragen (die neue Liste kommt kurz danach vom Server)
	if inventory then
		inventory.Gears[gearType] = math.max(0, gearCount(gearType) - 1)
		table.insert(inventory.PlacedGear, {
			Id = "lokal",
			Type = gearType,
			X = x,
			Z = z,
			ExpiresAt = serverNow() + Gears[gearType].Duration,
		})
	end
	if placing and placing.Type == gearType and gearCount(gearType) > 0 then
		flashHint("✅ " .. (message or "Aufgestellt!"), Color3.fromRGB(140, 214, 124))
		updateGhost(placing.X, placing.Z, true)
	else
		endModes(true)
		showHint("✅ " .. (message or "Aufgestellt!"), Color3.fromRGB(140, 214, 124), 3)
	end
	task.spawn(refresh)
end

-- Kuh-Modus: angeklickte Kuh bekommt das Werkzeug
local function useOnClickedCow(cowId)
	if not cowMode or busy then
		return
	end
	busy = true
	local gearType = cowMode
	local ok, message = gearAction("UseOnCow", gearType, cowId)
	busy = false
	if not ok then
		flashHint(message or "Das ging nicht.", Colors.Orange)
		return
	end
	if inventory then
		inventory.Gears[gearType] = math.max(0, gearCount(gearType) - 1)
	end
	if cowMode == gearType and gearCount(gearType) > 0 then
		modeHint()
	else
		endModes(true)
	end
	task.spawn(refresh)
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
			local hotbarSlot = inventory.GearHotbar and inventory.GearHotbar[gearType]
			local title = ("x%d im Rucksack"):format(count)
			if hotbarSlot then
				title = ("x%d · Hotbar %d"):format(count, hotbarSlot)
			end
			local card = gearCard(order, gearType, title)
			local face = Theme.button(card, {
				Text = info.Kind == "Place" and "Aufstellen" or "In die Hand",
				Color = info.Kind == "Place" and Colors.Green or Colors.Steel,
				TextSize = 15,
				Radius = 9,
				Lip = 4,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 8, 1, -8),
				Size = UDim2.new(0.6, -12, 0, 36),
			})
			face.Activated:Connect(function()
				selectGear(gearType)
			end)
			-- in die Hotbar legen / herausnehmen
			local hotbarButton = Theme.button(card, {
				Text = hotbarSlot and "– Hotbar" or "+ Hotbar",
				Color = hotbarSlot and Colors.Red or Colors.Blue,
				TextSize = 14,
				Radius = 9,
				Lip = 4,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -8, 1, -8),
				Size = UDim2.new(0.4, -4, 0, 36),
			})
			hotbarButton.Activated:Connect(function()
				local ok, message = gearAction(hotbarSlot and "Unhotbar" or "Hotbar", gearType)
				if not ok then
					showHint(message or "Das ging nicht.", Colors.Orange, 3)
				end
				task.spawn(refresh)
			end)
		end
	end

	local now = serverNow()
	local placed = 0
	for _, entry in ipairs(inventory.PlacedGear or {}) do
		if entry.ExpiresAt > now then
			placed += 1
			order += 1
			local card = gearCard(order, entry.Type, "steht auf der Farm", Color3.fromRGB(140, 214, 124))
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

	summary.Text = ("%d Werkzeuge im Rucksack  ·  %d / %d auf der Farm"):format(
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
	-- Werkzeug in der Hand aufgebraucht? -> weglegen
	local gearType = currentMode()
	if gearType and gearCount(gearType) <= 0 then
		endModes(true)
	elseif placing then
		updateGhost(placing.X, placing.Z, true)
	end
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
	if type(cow) ~= "table" then
		return
	end
	if cowMode then
		useOnClickedCow(cow.Id) -- Werkzeug in der Hand: gleich benutzen (InventoryClient zeigt kein Menü)
		return
	end
	if placing then
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
	elseif currentMode() then
		if input.KeyCode == Enum.KeyCode.X or input.UserInputType == Enum.UserInputType.MouseButton2 then
			stopPlacing()
		elseif placing and input.KeyCode == Enum.KeyCode.R then
			placing.Yaw = (placing.Yaw + ROTATE_STEP) % 360
		elseif
			placing
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
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
