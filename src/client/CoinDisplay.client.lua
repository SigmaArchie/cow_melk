-- CoinDisplay.client.lua  (das HUD)
-- Feste Bildschirm-Zonen, nichts überlappt:
--   oben links    Coins + Milch (Zahlen zählen hoch, Münz-Sound)
--   links Mitte   3 Knöpfe: KARTE (M), KÜHE (I), BONUS (mit Streak-Zahl)
--   oben Mitte    Meldungen (max. 3, verschwinden nach 2,5 s)
--   unten rechts  VERKAUFEN (pulsiert, sobald Milch da ist)
-- Stil kommt aus Theme.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Oben links: Coins + Milch
------------------------------------------------------------------------
local currency = Instance.new("Frame")
currency.Name = "Currency"
currency.Position = UDim2.fromOffset(20, 12)
currency.Size = UDim2.fromOffset(210, 0)
currency.AutomaticSize = Enum.AutomaticSize.Y
currency.BackgroundTransparency = 1
currency.Parent = gui
local currencyLayout = Instance.new("UIListLayout")
currencyLayout.Padding = UDim.new(0, 10)
currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
currencyLayout.Parent = currency
Theme.autoScale(currency)

-- Leiste: Symbol in einem farbigen Kreis links (ganz in der Leiste), dahinter die Zahl
local function makeCounter(order, iconBuilder, accent)
	local holder = Instance.new("Frame")
	holder.LayoutOrder = order
	holder.Size = UDim2.fromOffset(200, 46)
	holder.BackgroundTransparency = 1
	holder.Parent = currency

	local bar = Theme.panel(holder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.1,
		Radius = 23,
	})
	local badge = Theme.panel(bar, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Theme.darken(accent, 0.55),
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
	scale.Scale = 1.12
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
			TweenService:Create(shown, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target }):Play()
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
side.Position = UDim2.new(0, 14, 0.5, 0)
side.Size = UDim2.fromOffset(84, 0)
side.AutomaticSize = Enum.AutomaticSize.Y
side.BackgroundTransparency = 1
side.Parent = gui
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 12)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side
Theme.autoScale(side)

local function sideButton(order, text, color, keyHint, drawIcon, onClick)
	local face, holder = Theme.button(side, {
		Name = text,
		Size = UDim2.fromOffset(84, 84),
		Color = color,
		LayoutOrder = order,
		Radius = 16,
		Lip = 6,
	})
	drawIcon(face)
	Theme.label(face, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 17,
		Text = text,
	})
	if keyHint then
		local key = Theme.label(face, {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 0,
			BackgroundColor3 = Colors.Outline,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.BodyFont,
			TextSize = 11,
			Text = keyHint,
			Outline = 0,
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
	icon.Parent = face
	for i, color in ipairs({ Color3.fromRGB(120, 200, 110), Color3.fromRGB(240, 230, 190), Color3.fromRGB(120, 200, 110) }) do
		local panel = Instance.new("Frame")
		panel.Position = UDim2.fromScale((i - 1) / 3, i == 2 and 0.08 or 0)
		panel.Size = UDim2.new(1 / 3, 1, 0.92, 0)
		panel.BackgroundColor3 = color
		panel.BorderSizePixel = 0
		panel.Parent = icon
		Theme.border(panel, 2)
	end
	local pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.5, 0.45)
	pin.Size = UDim2.fromOffset(12, 12)
	pin.BackgroundColor3 = Colors.Red
	pin.Parent = icon
	Theme.corner(pin, UDim.new(1, 0))
	Theme.border(pin, 2)
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
	box.Parent = face
	Theme.corner(box, 4)
	Theme.border(box, 2)
	local ribbon = Instance.new("Frame")
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.fromScale(0.5, 0)
	ribbon.Size = UDim2.new(0, 8, 1, 0)
	ribbon.BackgroundColor3 = Colors.Gold
	ribbon.BorderSizePixel = 0
	ribbon.Parent = box
	local lid = Instance.new("Frame")
	lid.AnchorPoint = Vector2.new(0.5, 1)
	lid.Position = UDim2.new(0.5, 0, 0, 2)
	lid.Size = UDim2.new(1, 6, 0, 9)
	lid.BackgroundColor3 = Theme.darken(Colors.Red, 0.15)
	lid.BorderSizePixel = 0
	lid.Parent = box
	Theme.corner(lid, 3)
	Theme.border(lid, 2)
end

sideButton(1, "KARTE", Colors.Blue, "M", drawMapIcon, function()
	UIBus.ToggleOverview:Fire()
end)
sideButton(2, "KÜHE", Colors.Orange, "I", drawCowIcon, function()
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
	Outline = 2,
})
Theme.corner(badge, UDim.new(1, 0))
Theme.border(badge, 2)
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
sellZone.Position = UDim2.new(1, -16, 1, -16)
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

local sellButton, sellHolder, setSellColor = Theme.button(sellPulse, {
	Name = "SellButton",
	Text = "VERKAUFEN",
	Size = UDim2.fromScale(1, 1),
	Color = Colors.Green,
	TextSize = 30,
	Radius = 18,
	Lip = 7,
})
-- Milchflasche links im Knopf (am Halter, damit der Text-Abstand sie nicht verschiebt)
local sellIcon = Theme.milkIcon(sellHolder, 34, UDim2.new(0, 30, 0.5, -3))
sellIcon.ZIndex = sellButton.ZIndex + 1
local sellPadding = Instance.new("UIPadding")
sellPadding.PaddingLeft = UDim.new(0, 44)
sellPadding.Parent = sellButton

local pulseTween = nil
local function updateSell()
	local hasMilk = (player:GetAttribute("Milk") or 0) > 0
	setSellColor(hasMilk and Colors.Green or Colors.Grey)
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
local KIND_COLORS = {
	success = Colors.Green,
	error = Colors.Red,
	rare = Colors.Gold,
	info = Colors.Blue,
}
local MAX_TOASTS = 3
local TOAST_TIME = 2.5

local toasts = Instance.new("Frame")
toasts.Name = "Toasts"
toasts.AnchorPoint = Vector2.new(0.5, 0)
toasts.Position = UDim2.new(0.5, 0, 0, 10)
toasts.Size = UDim2.fromOffset(460, 0)
toasts.AutomaticSize = Enum.AutomaticSize.Y
toasts.BackgroundTransparency = 1
toasts.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toasts
Theme.autoScale(toasts)

local toastCount = 0
local activeToasts = {}

local function removeToast(toast)
	local index = table.find(activeToasts, toast)
	if index then
		table.remove(activeToasts, index)
	end
	toast:Destroy()
end

local function showToast(message, kind)
	toastCount += 1
	local accent = KIND_COLORS[kind] or Colors.Blue

	local toast = Theme.panel(toasts, {
		Name = "Toast",
		LayoutOrder = toastCount,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Panel,
		Radius = 12,
	})
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 8, 1, 0)
	accentBar.BackgroundColor3 = accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = toast
	Theme.corner(accentBar, 6)
	local text = Theme.label(toast, {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.BodyFont,
		TextSize = 16,
		Text = tostring(message),
		Outline = 0,
	})
	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = toast
	text.TextTransparency = 1

	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = toast
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(text, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()

	table.insert(activeToasts, toast)
	if #activeToasts > MAX_TOASTS then
		removeToast(activeToasts[1])
	end

	task.delay(TOAST_TIME, function()
		if not toast.Parent then
			return
		end
		local fade = TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
		TweenService:Create(text, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(accentBar, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end
		fade:Play()
		fade.Completed:Wait()
		if toast.Parent then
			removeToast(toast)
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(showToast)
