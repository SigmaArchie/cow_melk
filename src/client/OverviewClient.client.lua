-- OverviewClient.client.lua
-- Fenster "KARTE" (Taste M oder Knopf KARTE links):
--   links: gezeichnete Karte (runder Marktplatz mit Brunnen und Shops in der Mitte, Feldwege,
--          alle Farmen im Kreis, deine blau umrandet, weißer Punkt = du). Häuser und deine Farm anklickbar.
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

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local World = Palette.World

-- Kartenfarben aus der gemeinsamen Palette
local GRASS = World.GrassDark
local STONE = World.StonePath
local DIRT = Color3.fromRGB(172, 142, 102)

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
	Size = Vector2.new(900, 540),
})

------------------------------------------------------------------------
-- Karte (links)
------------------------------------------------------------------------
local MAP_SIZE = Vector2.new(444, 444)
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

-- quadratischer Ausschnitt um die Kartenmitte, groß genug für alle Farmen
local bounds = { MinX = -270, MaxX = 270, MinZ = -270, MaxZ = 270 }
local mapScale, mapOffset = 1, Vector2.zero

local function computeBounds()
	local radius = Map.PlotRingRadius + Map.PlotDepth / 2 + 12
	for _, other in ipairs(Players:GetPlayers()) do
		local slot = other:GetAttribute("PlotSlot")
		if slot then
			radius = math.max(radius, CowData.GetPlotOrigin(slot).Position.Magnitude + Map.PlotDepth / 2 + 12)
		end
	end
	bounds.MinX, bounds.MaxX, bounds.MinZ, bounds.MaxZ = -radius, radius, -radius, radius
	local size = radius * 2
	mapScale = math.min((MAP_SIZE.X - 16) / size, (MAP_SIZE.Y - 16) / size)
	mapOffset = Vector2.new((MAP_SIZE.X - size * mapScale) / 2, (MAP_SIZE.Y - size * mapScale) / 2)
end

local function toMap(x, z)
	return mapOffset + Vector2.new((x - bounds.MinX) * mapScale, (bounds.MaxZ - z) * mapScale)
end

-- gedrehtes Rechteck (Mitte cx/cz, Breite quer, Länge entlang "angle"; Winkel wie in CowData:
-- im Uhrzeigersinn von Norden). Auf dem Bildschirm ist Norden oben, darum passt Rotation = angle.
local function box(cx, cz, width, length, angle, color)
	local center = toMap(cx, cz)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(center.X, center.Y)
	frame.Size = UDim2.fromOffset(width * mapScale, length * mapScale)
	frame.Rotation = angle
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = layer
	return frame
end

local function polar(angle, radius)
	local radians = math.rad(angle)
	return radius * math.sin(radians), radius * math.cos(radians)
end

local function mapText(text, x, z, size, color)
	local position = toMap(x, z)
	local pill = Theme.label(layer, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(0, size + 8),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Colors.Deep,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.BodyFont,
		TextSize = size,
		TextColor3 = color or Colors.Text,
		Text = text,
		ZIndex = 4,
	})
	Theme.corner(pill, UDim.new(0.5, 0))
	local pad = Theme.padding(pill, 0)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	return pill
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

	-- Feldwege: vom Platz zu den Farm-Toren und Ringweg davor
	local step = 360 / Map.PlotsPerRing
	local gate = Map.PlotRingRadius - Map.PlotDepth / 2
	for k = 0, Map.PlotsPerRing - 1 do
		local x, z = polar(k * step, (Map.HubRadius + gate) / 2)
		box(x, z, 9, gate - Map.HubRadius, k * step, DIRT)
	end
	local ring = box(0, 0, Map.RingRoadRadius * 2, Map.RingRoadRadius * 2, 0, DIRT)
	ring.BackgroundTransparency = 1
	Theme.corner(ring, UDim.new(1, 0))
	Theme.border(ring, math.max(2, 8 * mapScale), DIRT)

	-- Marktplatz mit Brunnen
	local plaza = box(0, 0, Map.HubRadius * 2, Map.HubRadius * 2, 0, STONE)
	Theme.corner(plaza, UDim.new(1, 0))
	local fountain = box(0, 0, 18, 18, 0, Colors.Blue)
	Theme.corner(fountain, UDim.new(1, 0))

	-- Farmen (gedreht, Tor zur Mitte)
	for _, other in ipairs(Players:GetPlayers()) do
		local slot = other:GetAttribute("PlotSlot")
		if slot then
			local origin = CowData.GetPlotOrigin(slot).Position
			local mine = other == player
			local angle = CowData.GetPlotAngle(slot)
			local plot = box(
				origin.X,
				origin.Z,
				Map.PlotWidth,
				Map.PlotDepth,
				angle + 180,
				mine and World.GrassLight or World.Leaf
			)
			Theme.corner(plot, 6)
			Theme.border(plot, mine and 3 or 1.5, mine and Colors.Blue or Colors.Outline)
			-- Hof (Tor-Seite) etwas heller/erdig
			local yardX, yardZ = polar(angle, origin.Magnitude - (Map.PlotDepth / 2 + Map.PastureFrontZ) / 2)
			local yardDepth = Map.PlotDepth / 2 - Map.PastureFrontZ
			box(yardX, yardZ, Map.PlotWidth - 6, yardDepth - 4, angle + 180, DIRT).BackgroundTransparency = 0.35
			mapText(mine and "DU" or other.DisplayName, origin.X, origin.Z, mine and 15 or 12, Colors.Text)
			if mine then
				clickable(plot, function()
					teleport("Farm")
				end)
			end
		end
	end

	-- Häuser am Platz (Symbol statt Name, die Namen stehen rechts in der Liste)
	for _, shop in ipairs(Map.Shops) do
		local house = box(shop.Position.X, shop.Position.Z, 20, 16, shop.Angle, shop.Color)
		Theme.corner(house, 4)
		Theme.border(house, 2)
		clickable(house, function()
			teleport(shop.Page)
		end)
		local labelX, labelZ = polar(shop.Angle, Map.ShopRadius + 2)
		mapText(shop.Icon, labelX, labelZ, 13)
	end

	mapText("MARKTPLATZ", 0, -Map.HubRadius - 14, 13, Colors.Text)
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
