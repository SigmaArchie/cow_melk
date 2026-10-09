-- CoinDisplay.client.lua
-- HUD wie in großen Simulator-Spielen:
--   OBEN (ganze Breite, dunkel): links 🪙 Coins (Zahlen rollen wie ein Spielautomat),
--                                Mitte Logo "🐄 COW FARM", rechts 🥛 Milch + 🔥 Streak
--   UNTEN: großer grüner "MILCH VERKAUFEN 🥛"-Knopf, pulsiert, sobald man Milch hat
--   Benachrichtigungen: gleiten von rechts herein, Karten-Stil, farbig
--                       (grün = gut, rot = Fehler, gold = seltener Fund), nach 2,5 s wieder raus
-- Die runden Seitenknöpfe links (Shop, Zucht, Tagesbonus …) baut MenuUI.client.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = CowData.Config

local player = Players.LocalPlayer

local DARK = Color3.fromRGB(20, 22, 32)
local CHIP = Color3.fromRGB(38, 41, 58)
local TEXT = Color3.new(1, 1, 1)
local COIN_COLOR = Color3.fromRGB(255, 215, 60)
local MILK_COLOR = Color3.fromRGB(215, 235, 255)
local STREAK_COLOR = Color3.fromRGB(255, 160, 70)
local SELL_GREEN = Color3.fromRGB(55, 190, 80)
local SELL_GREY = Color3.fromRGB(80, 84, 104)

------------------------------------------------------------------------
-- Helfer
------------------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function playSound(soundId, volume, speed)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

-- obere Leiste über die ganze Breite
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 64)
topBar.BackgroundColor3 = DARK
topBar.BackgroundTransparency = 0.25
topBar.BorderSizePixel = 0
topBar.Parent = gui
local topGradient = Instance.new("UIGradient")
topGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0.35),
})
topGradient.Rotation = 90
topGradient.Parent = topBar

-- Chip = abgerundete Box mit Icon + Inhalt
local function makeChip(name, icon, anchorX, positionX, color)
	local chip = Instance.new("Frame")
	chip.Name = name
	chip.AnchorPoint = Vector2.new(anchorX, 0.5)
	chip.Position = UDim2.new(positionX, positionX == 0 and 14 or (positionX == 1 and -14 or 0), 0.5, 0)
	chip.Size = UDim2.fromOffset(0, 46)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundColor3 = CHIP
	chip.Parent = topBar
	corner(chip, UDim.new(1, 0))
	stroke(chip, color, 2, 0.3)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = chip

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = chip

	local iconBack = Instance.new("TextLabel")
	iconBack.LayoutOrder = 1
	iconBack.Size = UDim2.fromOffset(36, 36)
	iconBack.BackgroundColor3 = color
	iconBack.BackgroundTransparency = 0.75
	iconBack.Font = Enum.Font.GothamBold
	iconBack.TextSize = 22
	iconBack.Text = icon
	iconBack.Parent = chip
	corner(iconBack, UDim.new(1, 0))

	local scale = Instance.new("UIScale")
	scale.Parent = chip
	return chip, scale
end

------------------------------------------------------------------------
-- Spielautomat-Zähler: jede Ziffer ist eine Rolle mit 0-9, die zur neuen Zahl rollt
------------------------------------------------------------------------
local DIGIT_HEIGHT = 32
local DIGIT_WIDTH = 17

local function createRoller(parent, color, order)
	local holder = Instance.new("Frame")
	holder.Name = "Roller"
	holder.LayoutOrder = order
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(0, DIGIT_HEIGHT)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local columns = {}
	local pattern = ""

	local function digitLabel(parentFrame, textValue, y)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.fromOffset(DIGIT_WIDTH, DIGIT_HEIGHT)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 28
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.6
		label.Text = textValue
		label.Parent = parentFrame
		return label
	end

	local function rebuild(str)
		for _, column in ipairs(columns) do
			column.Frame:Destroy()
		end
		table.clear(columns)
		for i = 1, #str do
			local ch = str:sub(i, i)
			local column = Instance.new("Frame")
			column.LayoutOrder = i
			column.BackgroundTransparency = 1
			column.ClipsDescendants = true
			column.Parent = holder
			if ch:match("%d") then
				column.Size = UDim2.fromOffset(DIGIT_WIDTH, DIGIT_HEIGHT)
				local strip = Instance.new("Frame")
				strip.BackgroundTransparency = 1
				strip.Size = UDim2.fromOffset(DIGIT_WIDTH, DIGIT_HEIGHT * 10)
				strip.Parent = column
				for d = 0, 9 do
					digitLabel(strip, tostring(d), d * DIGIT_HEIGHT)
				end
				strip.Position = UDim2.fromOffset(0, -tonumber(ch) * DIGIT_HEIGHT)
				table.insert(columns, { Frame = column, Strip = strip, Digit = tonumber(ch) })
			else
				column.Size = UDim2.fromOffset(8, DIGIT_HEIGHT)
				local sep = digitLabel(column, ch, 0)
				sep.Size = UDim2.fromOffset(8, DIGIT_HEIGHT)
				table.insert(columns, { Frame = column })
			end
		end
	end

	-- setzt den Zähler; animate = true -> Ziffern rollen
	return function(value, animate)
		local str = CowData.FormatNumber(value)
		local newPattern = str:gsub("%d", "0")
		if newPattern ~= pattern then
			pattern = newPattern
			rebuild(str)
			animate = false
		end
		for i, column in ipairs(columns) do
			if column.Strip then
				local digit = tonumber(str:sub(i, i))
				if digit ~= column.Digit then
					column.Digit = digit
					local target = UDim2.fromOffset(0, -digit * DIGIT_HEIGHT)
					if animate then
						-- rechte Ziffern rollen etwas später -> Spielautomat-Gefühl
						local delayTime = (#columns - i) * 0.04
						task.delay(delayTime, function()
							TweenService:Create(column.Strip, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
								Position = target,
							}):Play()
						end)
					else
						column.Strip.Position = target
					end
				end
			end
		end
	end
end

-- links: Coins
local coinChip, coinScale = makeChip("Coins", "🪙", 0, 0, COIN_COLOR)
local setCoins = createRoller(coinChip, COIN_COLOR, 2)

-- Mitte: Logo
local logo = Instance.new("TextLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.5)
logo.Size = UDim2.fromOffset(260, 46)
logo.BackgroundTransparency = 1
logo.Font = Enum.Font.FredokaOne
logo.TextSize = 34
logo.TextColor3 = TEXT
logo.TextStrokeColor3 = Color3.fromRGB(60, 40, 20)
logo.TextStrokeTransparency = 0
logo.Text = "🐄 COW FARM"
logo.Parent = topBar
local logoGradient = Instance.new("UIGradient")
logoGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 225, 140))
logoGradient.Rotation = 90
logoGradient.Parent = logo

-- rechts: Milch + Streak
local rightGroup = Instance.new("Frame")
rightGroup.Name = "Right"
rightGroup.AnchorPoint = Vector2.new(1, 0.5)
rightGroup.Position = UDim2.new(1, -14, 0.5, 0)
rightGroup.Size = UDim2.fromOffset(0, 46)
rightGroup.AutomaticSize = Enum.AutomaticSize.X
rightGroup.BackgroundTransparency = 1
rightGroup.Parent = topBar
local rightLayout = Instance.new("UIListLayout")
rightLayout.FillDirection = Enum.FillDirection.Horizontal
rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Padding = UDim.new(0, 8)
rightLayout.Parent = rightGroup

local streakChip = makeChip("Streak", "🔥", 1, 1, STREAK_COLOR)
streakChip.LayoutOrder = 1
streakChip.Parent = rightGroup
local streakLabel = Instance.new("TextLabel")
streakLabel.LayoutOrder = 2
streakLabel.BackgroundTransparency = 1
streakLabel.Size = UDim2.fromOffset(0, DIGIT_HEIGHT)
streakLabel.AutomaticSize = Enum.AutomaticSize.X
streakLabel.Font = Enum.Font.FredokaOne
streakLabel.TextSize = 24
streakLabel.TextColor3 = STREAK_COLOR
streakLabel.Text = "0"
streakLabel.Parent = streakChip

local milkChip, milkScale = makeChip("Milk", "🥛", 1, 1, MILK_COLOR)
milkChip.LayoutOrder = 2
milkChip.Parent = rightGroup
local setMilk = createRoller(milkChip, MILK_COLOR, 2)

-- schmale Bildschirme: Logo ausblenden, wenn es eng wird
local function fitTopBar()
	local width = topBar.AbsoluteSize.X
	logo.Visible = width > coinChip.AbsoluteSize.X + rightGroup.AbsoluteSize.X + logo.Size.X.Offset + 40
end
topBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTopBar)
coinChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTopBar)
rightGroup:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTopBar)

------------------------------------------------------------------------
-- Unten: großer Verkaufen-Knopf (Pille)
------------------------------------------------------------------------
local sellButton = Instance.new("TextButton")
sellButton.Name = "SellButton"
sellButton.AnchorPoint = Vector2.new(0.5, 1)
sellButton.Position = UDim2.new(0.5, 0, 1, -18)
sellButton.Size = UDim2.fromOffset(300, 68)
sellButton.BackgroundColor3 = SELL_GREEN
sellButton.AutoButtonColor = true
sellButton.Font = Enum.Font.FredokaOne
sellButton.TextSize = 30
sellButton.TextColor3 = TEXT
sellButton.TextStrokeColor3 = Color3.fromRGB(20, 70, 30)
sellButton.TextStrokeTransparency = 0
sellButton.Text = "MILCH VERKAUFEN 🥛"
sellButton.Parent = gui
corner(sellButton, UDim.new(1, 0))
local sellStroke = stroke(sellButton, Color3.fromRGB(190, 255, 190), 4)
local sellGradient = Instance.new("UIGradient")
sellGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 180, 180))
sellGradient.Rotation = 90
sellGradient.Parent = sellButton
local sellScale = Instance.new("UIScale")
sellScale.Parent = sellButton

local pulseTween = nil
local function updateSellButton()
	local hasMilk = (player:GetAttribute("Milk") or 0) > 0
	sellButton.BackgroundColor3 = hasMilk and SELL_GREEN or SELL_GREY
	sellStroke.Transparency = hasMilk and 0 or 0.7
	sellButton.TextTransparency = hasMilk and 0 or 0.3
	if hasMilk and not pulseTween then
		sellScale.Scale = 1
		pulseTween = TweenService:Create(sellScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 })
		pulseTween:Play()
	elseif not hasMilk and pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
		sellScale.Scale = 1
	end
end

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

------------------------------------------------------------------------
-- Werte verbinden
------------------------------------------------------------------------
local function pop(scale)
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local lastCoins = nil
local function onCoins()
	local coins = player:GetAttribute("Coins")
	if coins == nil then
		return
	end
	local increased = lastCoins ~= nil and coins > lastCoins
	setCoins(coins, lastCoins ~= nil)
	if increased then
		pop(coinScale)
		playSound(Config.CoinSoundId, 0.7)
	end
	lastCoins = coins
end
player:GetAttributeChangedSignal("Coins"):Connect(onCoins)
onCoins()

local lastMilk = nil
local function onMilk()
	local milk = player:GetAttribute("Milk")
	if milk == nil then
		return
	end
	setMilk(milk, lastMilk ~= nil)
	if lastMilk and milk > lastMilk then
		pop(milkScale)
	end
	lastMilk = milk
	updateSellButton()
end
player:GetAttributeChangedSignal("Milk"):Connect(onMilk)
onMilk()
updateSellButton()

local function onStreak()
	streakLabel.Text = tostring(player:GetAttribute("LoginStreak") or 0)
end
player:GetAttributeChangedSignal("LoginStreak"):Connect(onStreak)
onStreak()

------------------------------------------------------------------------
-- Benachrichtigungen (rechts, Karten, 2,5 s)
------------------------------------------------------------------------
local KIND_COLORS = {
	success = Color3.fromRGB(55, 175, 80), -- grün = gut
	error = Color3.fromRGB(215, 60, 60), -- rot = Fehler
	rare = Color3.fromRGB(235, 170, 30), -- gold = seltener Fund
	info = Color3.fromRGB(70, 130, 230),
}
local KIND_ICONS = { success = "✅", error = "⚠️", rare = "🌟", info = "💬" }
local NOTIFICATION_TIME = 2.5
local NOTIFICATION_WIDTH = 330
local MAX_NOTIFICATIONS = 5

local notifyHolder = Instance.new("Frame")
notifyHolder.Name = "Notifications"
notifyHolder.AnchorPoint = Vector2.new(1, 0)
notifyHolder.Position = UDim2.new(1, -12, 0, 78)
notifyHolder.Size = UDim2.fromOffset(NOTIFICATION_WIDTH, 0)
notifyHolder.AutomaticSize = Enum.AutomaticSize.Y
notifyHolder.BackgroundTransparency = 1
notifyHolder.Parent = gui
local notifyLayout = Instance.new("UIListLayout")
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifyLayout.Padding = UDim.new(0, 8)
notifyLayout.Parent = notifyHolder

local counter = 0
local active = {}

local function removeSlot(slot)
	local index = table.find(active, slot)
	if index then
		table.remove(active, index)
	end
	slot:Destroy()
end

local function showNotification(message, kind)
	counter += 1
	local color = KIND_COLORS[kind] or KIND_COLORS.info

	local slot = Instance.new("Frame")
	slot.Name = "Notification"
	slot.LayoutOrder = counter
	slot.Size = UDim2.fromOffset(NOTIFICATION_WIDTH, 0)
	slot.AutomaticSize = Enum.AutomaticSize.Y
	slot.BackgroundTransparency = 1
	slot.Parent = notifyHolder

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Position = UDim2.fromOffset(NOTIFICATION_WIDTH + 40, 0)
	card.BackgroundColor3 = color
	card.Parent = slot
	corner(card, UDim.new(0, 16))
	stroke(card, Color3.new(1, 1, 1), 2, 0.4)
	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170))
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = TEXT
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	label.TextStrokeTransparency = 0.5
	label.Text = (KIND_ICONS[kind] or "💬") .. "  " .. tostring(message)
	label.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = label

	table.insert(active, slot)
	if #active > MAX_NOTIFICATIONS then
		removeSlot(active[1])
	end

	-- von rechts hereingleiten
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()

	-- nach 2,5 s wieder nach rechts raus
	task.delay(NOTIFICATION_TIME, function()
		if not slot.Parent then
			return
		end
		local out = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(NOTIFICATION_WIDTH + 40, 0),
		})
		out:Play()
		out.Completed:Wait()
		if slot.Parent then
			removeSlot(slot)
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(showNotification)
