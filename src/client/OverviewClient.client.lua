-- OverviewClient.client.lua
-- Fenster "KARTE" (Taste M oder Knopf KARTE links):
--   links: gezeichnete Karte (Süd-Platz, Förderbänder, Nord-Markt, alle Farmen,
--          deine golden umrandet, weißer Punkt = du). Häuser und deine Farm anklickbar.
--   rechts: Orte mit "Reisen"-Knopf -> Teleport vor das Haus bzw. auf deine Farm.
-- Stil: Theme.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))
local UIBus = require(script.Parent:WaitForChild("UIBus"))

local Colors = Theme.Colors
local Map = CowData.Map
local player = Players.LocalPlayer

local GRASS = Color3.fromRGB(104, 168, 76)
local STONE = Color3.fromRGB(196, 190, 176)
local CONVEYOR = Color3.fromRGB(40, 40, 46)

local gui = Instance.new("ScreenGui")
gui.Name = "Overview"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local window = Theme.window(gui, {
	Name = "MapWindow",
	Title = "KARTE",
	Color = Colors.Blue,
	Size = Vector2.new(820, 540),
})

------------------------------------------------------------------------
-- Karte (links)
------------------------------------------------------------------------
local MAP_SIZE = Vector2.new(310, 444)
local mapFrame = Theme.panel(window.Body, {
	Name = "Map",
	Size = UDim2.fromOffset(MAP_SIZE.X, MAP_SIZE.Y),
	BackgroundColor3 = GRASS,
	ClipsDescendants = true,
	Radius = 12,
})
local layer = Instance.new("Frame")
layer.Size = UDim2.fromScale(1, 1)
layer.BackgroundTransparency = 1
layer.Parent = mapFrame

local bounds = { MinX = -140, MaxX = 140, MinZ = -105, MaxZ = Map.NorthPlazaZ + Map.NorthPlazaSize.Z / 2 + 5 }
local mapScale, mapOffset = 1, Vector2.zero

local function computeBounds()
	local maxX = 140
	for _, other in ipairs(Players:GetPlayers()) do
		local slot = other:GetAttribute("PlotSlot")
		if slot then
			maxX = math.max(maxX, math.abs(CowData.GetPlotOrigin(slot).Position.X) + Map.PlotDepth / 2 + 5)
		end
	end
	bounds.MinX, bounds.MaxX = -maxX, maxX
	local width, height = bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ
	mapScale = math.min((MAP_SIZE.X - 20) / width, (MAP_SIZE.Y - 20) / height)
	mapOffset = Vector2.new((MAP_SIZE.X - width * mapScale) / 2, (MAP_SIZE.Y - height * mapScale) / 2)
end

local function toMap(x, z)
	return mapOffset + Vector2.new((x - bounds.MinX) * mapScale, (bounds.MaxZ - z) * mapScale)
end

local function rect(centerX, centerZ, sizeX, sizeZ, color)
	local topLeft = toMap(centerX - sizeX / 2, centerZ + sizeZ / 2)
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
	frame.Size = UDim2.fromOffset(sizeX * mapScale, sizeZ * mapScale)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = layer
	return frame
end

local function mapText(text, x, z, size, color)
	local position = toMap(x, z)
	return Theme.label(layer, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(130, size + 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = size,
		TextColor3 = color or Colors.Text,
		Text = text,
		Outline = 2,
	})
end

local teleport -- weiter unten

local function clickable(frame, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Parent = frame
	button.Activated:Connect(callback)
end

local playerDot = Instance.new("Frame")
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
playerDot.Size = UDim2.fromOffset(16, 16)
playerDot.BackgroundColor3 = Color3.new(1, 1, 1)
playerDot.ZIndex = 5
playerDot.Parent = mapFrame
Theme.corner(playerDot, UDim.new(1, 0))
Theme.border(playerDot, 3)
TweenService:Create(playerDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Size = UDim2.fromOffset(20, 20),
}):Play()

local function drawMap()
	for _, child in ipairs(layer:GetChildren()) do
		child:Destroy()
	end
	computeBounds()

	-- Plätze, Allee, Förderbänder
	rect(0, -50, 120, 100, STONE)
	rect(0, Map.NorthPlazaZ, Map.NorthPlazaSize.X, Map.NorthPlazaSize.Z, STONE)
	local avenueEnd = Map.WalkwayStartZ + Map.WalkwayCycle + Map.WalkwayTileLength + 10
	rect(0, avenueEnd / 2, 36, avenueEnd, STONE)
	local laneLength = Map.WalkwayCycle + Map.WalkwayTileLength
	local laneCenter = Map.WalkwayStartZ + laneLength / 2
	for _, lane in ipairs({ { -Map.WalkwayX, "▲" }, { Map.WalkwayX, "▼" } }) do
		local strip = rect(lane[1], laneCenter, Map.WalkwayWidth, laneLength, CONVEYOR)
		for i = 1, 4 do
			Theme.label(strip, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, i / 5),
				Size = UDim2.fromOffset(12, 12),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 10,
				TextColor3 = Colors.Cream,
				Text = lane[2],
				Outline = 0,
			})
		end
	end
	local fountain = rect(0, -50, 16, 16, Colors.Blue)
	Theme.corner(fountain, UDim.new(1, 0))

	-- Farmen
	for _, other in ipairs(Players:GetPlayers()) do
		local slot = other:GetAttribute("PlotSlot")
		if slot then
			local origin = CowData.GetPlotOrigin(slot).Position
			local mine = other == player
			local plot = rect(origin.X, origin.Z, Map.PlotDepth, Map.PlotWidth,
				mine and Color3.fromRGB(150, 205, 100) or Color3.fromRGB(124, 182, 90))
			Theme.corner(plot, 6)
			Theme.border(plot, mine and 3 or 1.5, mine and Colors.Blue or Colors.Outline)
			Theme.label(plot, {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				TextSize = mine and 15 or 11,
				Text = mine and "DU" or other.DisplayName,
				Outline = 2,
			})
			if mine then
				clickable(plot, function()
					teleport("Farm")
				end)
			end
		end
	end

	-- Häuser
	for _, shop in ipairs(Map.Shops) do
		local house = rect(shop.Position.X, shop.Position.Z, 16, 20, shop.Color)
		Theme.corner(house, 4)
		Theme.border(house, 2)
		clickable(house, function()
			teleport(shop.Page)
		end)
		local labelX = shop.Position.X + (shop.Position.X < 0 and -1 or 1) * 2
		mapText(shop.Label, labelX, shop.Position.Z - 16, 11)
	end

	mapText("SÜD-PLATZ", 0, -92, 13, Colors.Text)
	mapText("NORD-MARKT", 0, Map.NorthPlazaZ + 42, 13, Colors.Text)
end

------------------------------------------------------------------------
-- Orte (rechts)
------------------------------------------------------------------------
local places = Instance.new("Frame")
places.Position = UDim2.fromOffset(MAP_SIZE.X + 20, 0)
places.Size = UDim2.new(1, -(MAP_SIZE.X + 20), 1, 0)
places.BackgroundTransparency = 1
places.Parent = window.Body
local placesLayout = Instance.new("UIListLayout")
placesLayout.Padding = UDim.new(0, 10)
placesLayout.SortOrder = Enum.SortOrder.LayoutOrder
placesLayout.Parent = places

Theme.label(places, {
	LayoutOrder = 0,
	Size = UDim2.new(1, 0, 0, 26),
	TextSize = 22,
	TextColor3 = Colors.SubText,
	Text = "REISEN",
	Outline = 0,
})

local function placeRow(order, color, title, subtitle, destination, drawIcon)
	local row = Theme.panel(places, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Colors.Card,
		Radius = 12,
	})
	local swatch = Theme.panel(row, {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = color,
		Radius = 10,
		Outline = 2,
	})
	if drawIcon then
		drawIcon(swatch)
	end
	Theme.label(row, {
		Position = UDim2.fromOffset(66, 9),
		Size = UDim2.new(1, -200, 0, 26),
		TextSize = 22,
		Text = title,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(66, 36),
		Size = UDim2.new(1, -200, 0, 16),
		Font = Theme.BodyFont,
		TextSize = 13,
		TextColor3 = Colors.SubText,
		Text = subtitle,
		Outline = 0,
	})
	local go = Theme.button(row, {
		Text = "Reisen",
		Color = Colors.Green,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(116, 44),
		TextSize = 20,
		Radius = 10,
		Lip = 4,
	})
	go.Activated:Connect(function()
		teleport(destination)
	end)
end

placeRow(1, Colors.Green, "Meine Farm", "Melken, Kühe platzieren, Milch verkaufen", "Farm", function(swatch)
	Theme.cowIcon(swatch, 32, UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1), Color3.fromRGB(30, 30, 35))
end)
for i, shop in ipairs(Map.Shops) do
	placeRow(1 + i, shop.Color, shop.Label, shop.Area, shop.Page, function(swatch)
		Theme.label(swatch, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 24,
			Text = shop.Label:sub(1, 1),
			Outline = 2,
		})
	end)
end

------------------------------------------------------------------------
-- Öffnen / Reisen
------------------------------------------------------------------------
local function toggle()
	if window:IsOpen() then
		window:Close()
	else
		drawMap()
		window:Open()
	end
end

function teleport(destination)
	window:Close()
	Remotes.TeleportTo:FireServer(destination)
end

UIBus.ToggleOverview.Event:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.M then
		toggle()
	end
end)

local function redrawIfOpen()
	if window:IsOpen() then
		drawMap()
	end
end
local function watchPlayer(other)
	other:GetAttributeChangedSignal("PlotSlot"):Connect(redrawIfOpen)
end
Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	redrawIfOpen()
end)
Players.PlayerRemoving:Connect(function()
	task.defer(redrawIfOpen)
end)
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end

RunService.RenderStepped:Connect(function()
	if not window:IsOpen() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	playerDot.Visible = root ~= nil
	if root then
		local position = toMap(root.Position.X, root.Position.Z)
		playerDot.Position = UDim2.fromOffset(position.X, position.Y)
	end
end)
