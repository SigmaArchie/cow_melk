-- CoinDisplay.client.lua  (das HUD)
-- Feste Bildschirm-Zonen, nichts überlappt:
--   oben links    Coins + Milch (Zahlen zählen hoch, Münz-Sound)
--   links Mitte   3 Knöpfe: KARTE (M), KÜHE (I), BONUS (mit Streak-Zahl)
--   oben Mitte    Meldungen (max. 3, verschwinden nach 2,5 s)
--   unten rechts  VERKAUFEN (pulsiert, sobald Milch da ist)
-- Stil und Bausteine kommen aus Theme.lua. Safe-Area: Theme.screenGui (CoreUISafe).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))
local UIBus = require(script.Parent:WaitForChild("UIBus"))

local Colors = Theme.Colors
local Config = CowData.Config
local player = Players.LocalPlayer

local function playSound(soundId, volume)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local gui = Theme.screenGui("HUD", 5)
gui.Parent = player:WaitForChild("PlayerGui")

-- Tastenkürzel nur zeigen, wenn es eine Tastatur gibt (nicht auf Handy/Controller)
local showKeyHints = UserInputService.KeyboardEnabled

------------------------------------------------------------------------
-- Oben links: Coins + Milch
------------------------------------------------------------------------
local currency = Instance.new("Frame")
currency.Name = "Currency"
currency.Position = UDim2.fromOffset(Theme.Spacing.L + 4, Theme.Spacing.M)
currency.Size = UDim2.fromOffset(210, 0)
currency.AutomaticSize = Enum.AutomaticSize.Y
currency.BackgroundTransparency = 1
currency.Parent = gui
local currencyLayout = Instance.new("UIListLayout")
currencyLayout.Padding = UDim.new(0, Theme.Spacing.S + 2)
currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
currencyLayout.Parent = currency
Theme.autoScale(currency)

-- Leiste: Symbol in einem Kreis links (ganz in der Leiste), dahinter die Zahl
local function makeCounter(order, iconBuilder, accent)
	local holder = Instance.new("Frame")
	holder.Name = "Counter" .. order
	holder.LayoutOrder = order
	holder.Size = UDim2.fromOffset(200, 46)
	holder.BackgroundTransparency = 1
	holder.Parent = currency
	Theme.softShadow(holder, 23, 4)

	local bar = Theme.panel(holder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.05,
		Radius = 23,
	})
	local badge = Theme.panel(bar, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Theme.darken(accent, 0.6),
		Radius = 18,
		Outline = 0,
	})
	iconBuilder(badge, 28, UDim2.fromScale(0.5, 0.5))

	local value = Theme.label(bar, {
		Name = "Value",
		Position = UDim2.fromOffset(50, 0),
		Size = UDim2.new(1, -60, 1, 0),
		TextSize = 25,
		Text = "0",
	})

	local scale = Instance.new("UIScale")
	scale.Parent = holder
	return value, scale
end

local coinValue, coinScale = makeCounter(1, Theme.coinIcon, Colors.Gold)
local milkValue, milkScale = makeCounter(2, Theme.milkIcon, Colors.Blue)

local function pop(scale)
	scale.Scale = 1.1
	Theme.tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
end

-- Zahl zählt sanft zum neuen Wert
local function bindCounter(attribute, label, scale, onIncrease)
	local shown = Instance.new("NumberValue")
	local known = nil
	shown.Changed:Connect(function(v)
		label.Text = CowData.FormatNumber(v)
	end)
	local function update()
		local target = player:GetAttribute(attribute)
		if target == nil then
			return
		end
		if known == nil then
			shown.Value = target
			label.Text = CowData.FormatNumber(target)
		else
			Theme.tween(shown, { Value = target }, 0.5)
			if target > known then
				pop(scale)
				if onIncrease then
					onIncrease()
				end
			end
		end
		known = target
	end
	player:GetAttributeChangedSignal(attribute):Connect(update)
	update()
end

bindCounter("Coins", coinValue, coinScale, function()
	playSound(Config.CoinSoundId, 0.6)
end)
bindCounter("Milk", milkValue, milkScale)

------------------------------------------------------------------------
-- Links Mitte: KARTE / KÜHE / BONUS
------------------------------------------------------------------------
local side = Instance.new("Frame")
side.Name = "SideButtons"
side.AnchorPoint = Vector2.new(0, 0.5)
side.Position = UDim2.new(0, Theme.Spacing.L, 0.5, 0)
side.Size = UDim2.fromOffset(84, 0)
side.AutomaticSize = Enum.AutomaticSize.Y
side.BackgroundTransparency = 1
side.Parent = gui
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, Theme.Spacing.M)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side
Theme.autoScale(side)

local function sideButton(order, text, color, keyHint, drawIcon, onClick)
	local face, holder = Theme.button(side, {
		Name = text,
		Size = UDim2.fromOffset(84, 84),
		Color = color,
		LayoutOrder = order,
		Radius = Theme.Radius.L,
		Lip = 5,
	})
	drawIcon(face)
	Theme.label(face, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 16,
		Text = text,
	})
	if keyHint and showKeyHints then
		local key = Theme.label(face, {
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Colors.Deep,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.BodyFont,
			TextSize = 11,
			Text = keyHint,
		})
		Theme.corner(key, 5)
	end
	face.Activated:Connect(onClick)
	return face, holder
end

-- Karten-Symbol: drei Felder wie eine gefaltete Karte
local function drawMapIcon(face)
	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -10)
	icon.Size = UDim2.fromOffset(44, 34)
	icon.BackgroundTransparency = 1
	icon.ZIndex = face.ZIndex
	icon.Parent = face
	for i, color in ipairs({ Color3.fromRGB(120, 200, 110), Colors.Cream, Color3.fromRGB(120, 200, 110) }) do
		local panel = Instance.new("Frame")
		panel.Position = UDim2.fromScale((i - 1) / 3, i == 2 and 0.08 or 0)
		panel.Size = UDim2.new(1 / 3, 1, 0.92, 0)
		panel.BackgroundColor3 = color
		panel.BorderSizePixel = 0
		panel.ZIndex = face.ZIndex
		panel.Parent = icon
		Theme.border(panel, 1.5, Colors.Outline)
	end
	local pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.5, 0.45)
	pin.Size = UDim2.fromOffset(12, 12)
	pin.BackgroundColor3 = Colors.Red
	pin.ZIndex = face.ZIndex
	pin.Parent = icon
	Theme.corner(pin, UDim.new(1, 0))
	Theme.border(pin, 1.5, Colors.Outline)
end

local function drawCowIcon(face)
	Theme.cowIcon(face, 42, UDim2.new(0.5, 0, 0.5, -10), Color3.new(1, 1, 1), Color3.fromRGB(30, 30, 35))
end

-- Geschenk-Symbol: Kiste mit Schleife
local function drawGiftIcon(face)
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.new(0.5, 0, 0.5, -8)
	box.Size = UDim2.fromOffset(38, 30)
	box.BackgroundColor3 = Colors.Red
	box.BorderSizePixel = 0
	box.ZIndex = face.ZIndex
	box.Parent = face
	Theme.corner(box, 4)
	Theme.border(box, 1.5, Colors.Outline)
	local ribbon = Instance.new("Frame")
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.fromScale(0.5, 0)
	ribbon.Size = UDim2.new(0, 8, 1, 0)
	ribbon.BackgroundColor3 = Colors.Cream
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = face.ZIndex
	ribbon.Parent = box
	local lid = Instance.new("Frame")
	lid.AnchorPoint = Vector2.new(0.5, 1)
	lid.Position = UDim2.new(0.5, 0, 0, 2)
	lid.Size = UDim2.new(1, 6, 0, 9)
	lid.BackgroundColor3 = Theme.darken(Colors.Red, 0.15)
	lid.BorderSizePixel = 0
	lid.ZIndex = face.ZIndex
	lid.Parent = box
	Theme.corner(lid, 3)
	Theme.border(lid, 1.5, Colors.Outline)
end

sideButton(1, "KARTE", Colors.Blue, "M", drawMapIcon, function()
	UIBus.ToggleOverview:Fire()
end)
sideButton(2, "KÜHE", Colors.Steel, "I", drawCowIcon, function()
	UIBus.ToggleInventory:Fire()
end)
local bonusFace = sideButton(3, "BONUS", Colors.Green, nil, drawGiftIcon, function()
	UIBus.OpenPage:Fire("Daily")
end)

-- Streak-Zahl als rotes Abzeichen am Bonus-Knopf
local badge = Theme.label(bonusFace, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -6, 0, 6),
	Size = UDim2.fromOffset(28, 28),
	BackgroundTransparency = 0,
	BackgroundColor3 = Colors.Red,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 16,
	Text = "0",
	ZIndex = bonusFace.ZIndex + 2,
})
Theme.corner(badge, UDim.new(1, 0))
Theme.border(badge, Theme.Stroke.Normal, Colors.Panel)
local function updateStreak()
	local streak = player:GetAttribute("LoginStreak") or 0
	badge.Text = tostring(streak)
	badge.Visible = streak > 0
end
player:GetAttributeChangedSignal("LoginStreak"):Connect(updateStreak)
updateStreak()

------------------------------------------------------------------------
-- Unten rechts: VERKAUFEN
------------------------------------------------------------------------
local sellZone = Instance.new("Frame")
sellZone.Name = "SellZone"
sellZone.AnchorPoint = Vector2.new(1, 1)
sellZone.Position = UDim2.new(1, -Theme.Spacing.L, 1, -Theme.Spacing.L)
sellZone.Size = UDim2.fromOffset(230, 72)
sellZone.BackgroundTransparency = 1
sellZone.Parent = gui
Theme.autoScale(sellZone)

local sellPulse = Instance.new("Frame") -- eigene Ebene fürs Pulsieren
sellPulse.AnchorPoint = Vector2.new(0.5, 0.5)
sellPulse.Position = UDim2.fromScale(0.5, 0.5)
sellPulse.Size = UDim2.fromScale(1, 1)
sellPulse.BackgroundTransparency = 1
sellPulse.Parent = sellZone
local pulseScale = Instance.new("UIScale")
pulseScale.Parent = sellPulse

local sellButton, sellHolder, _, sellApi = Theme.primaryButton(sellPulse, {
	Name = "SellButton",
	Text = "VERKAUFEN",
	Size = UDim2.fromScale(1, 1),
	TextSize = 28,
	Radius = Theme.Radius.L,
	Lip = 6,
})
-- Milchtüte links im Knopf (am Halter, damit der Text-Abstand sie nicht verschiebt)
local sellIcon = Theme.milkIcon(sellHolder, 34, UDim2.new(0, 30, 0.5, -3))
sellIcon.ZIndex = sellButton.ZIndex + 1
local sellPadding = Instance.new("UIPadding")
sellPadding.PaddingLeft = UDim.new(0, 44)
sellPadding.Parent = sellButton

local pulseTween = nil
local function updateSell()
	local hasMilk = (player:GetAttribute("Milk") or 0) > 0
	sellApi.SetDisabled(not hasMilk)
	if hasMilk and not pulseTween then
		pulseScale.Scale = 1
		pulseTween = TweenService:Create(pulseScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 })
		pulseTween:Play()
	elseif not hasMilk and pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
		pulseScale.Scale = 1
	end
end
player:GetAttributeChangedSignal("Milk"):Connect(updateSell)
updateSell()

local sellCooldown = false
sellButton.Activated:Connect(function()
	if sellCooldown then
		return
	end
	sellCooldown = true
	Remotes.SellMilk:FireServer()
	task.delay(0.5, function()
		sellCooldown = false
	end)
end)

-- Damit das Tutorial den Knopf findet: Verweis direkt unter dem HUD
local sellRef = Instance.new("ObjectValue")
sellRef.Name = "SellButtonRef"
sellRef.Value = sellButton
sellRef.Parent = gui

------------------------------------------------------------------------
-- Oben Mitte: Meldungen
------------------------------------------------------------------------
Remotes.Notify.OnClientEvent:Connect(Theme.createNotifier(gui, { MaxToasts = 3, Time = 2.5 }))
