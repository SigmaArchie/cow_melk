-- TutorialClient.client.lua
-- Die ersten Minuten für NEUE Spieler (Attribut TutorialDone = false):
--   0. Kamera schwenkt 3 Sekunden über die Farm, Willkommens-Fenster mit dem Weg durchs Spiel
--   1. Pfeil zur eigenen Farm        (Startkuh steht schon da)
--   2. Pfeil zur Kuh                 (anklicken -> Melken)
--   3. nach der ersten Milch: Pfeil zum VERKAUFEN-Knopf
--   4. nach dem Verkauf: Pfeil zum Kuh-Shop -> zweite Kuh kaufen
--   5. Pfeil zum Zucht-Stall: Zucht und Kisten kennenlernen
-- Danach (oder bei "Überspringen") meldet der Client Remotes.TutorialDone -> wird gespeichert.
-- Stil: Theme.lua. Das Tutorial braucht: ScreenGui "HUD" mit "SellButtonRef", ScreenGui "MenuUI"
-- mit dem Fenster "Window", den Part "Sign" im Eingang der eigenen Farm (Decor) und die Shop-Gebäude.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))

local Colors = Theme.Colors
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOTAL_STEPS = 5

------------------------------------------------------------------------
-- Nur für neue Spieler
------------------------------------------------------------------------
local function waitForAttribute(name, timeout)
	local start = os.clock()
	while player:GetAttribute(name) == nil and os.clock() - start < timeout do
		task.wait(0.2)
	end
	return player:GetAttribute(name)
end

if waitForAttribute("TutorialDone", 30) ~= false then
	return -- schon gesehen (oder Daten nicht geladen)
end

------------------------------------------------------------------------
-- Welt-Ziele finden
------------------------------------------------------------------------
local layout = workspace:WaitForChild("CowFarmLayout")

local function findMyPlot()
	local plots = layout:FindFirstChild("Plots")
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

local function waitForPlot(timeout)
	local start = os.clock()
	local plot = findMyPlot()
	while not plot and os.clock() - start < timeout do
		task.wait(0.25)
		plot = findMyPlot()
	end
	return plot
end

local function plotSignPosition(plot)
	local decor = plot and plot:FindFirstChild("Decor")
	local sign = decor and decor:FindFirstChild("Sign")
	return sign and sign.Position or nil
end

local function myFirstCowPosition(plot)
	local cows = plot and plot:FindFirstChild("Cows")
	if not cows then
		return nil
	end
	for _, spot in ipairs(cows:GetChildren()) do
		local cow = spot:FindFirstChild("Cow")
		local torso = cow and cow:FindFirstChild("Torso")
		if torso then
			return torso.Position + Vector3.new(0, 5, 0)
		end
	end
	return nil
end

-- Position über einem Shop-Gebäude (Süd-Platz: Folder "Hub", Nord-Markt: "NorthMarket")
local function shopPosition(shopName)
	for _, folderName in ipairs({ "Hub", "NorthMarket" }) do
		local folder = layout:FindFirstChild(folderName)
		local shop = folder and folder:FindFirstChild(shopName)
		local floor = shop and shop:FindFirstChild("Floor")
		if floor then
			return floor.Position + Vector3.new(0, 18, 0)
		end
	end
	return nil
end

------------------------------------------------------------------------
-- GUI: Hinweis-Banner, Pfeil, Überspringen
------------------------------------------------------------------------
local gui = Theme.screenGui("Tutorial", 8, true)
gui.Parent = playerGui

-- Banner direkt über der Hotbar (feste Zone), Schritt-Nummer + Text
local banner = Theme.panel(gui, {
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -100),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = Colors.Panel,
	OutlineColor = Colors.Blue,
	Outline = Theme.Stroke.Normal,
	Visible = false,
	Radius = Theme.Radius.L,
})
local bannerLimit = Instance.new("UISizeConstraint")
bannerLimit.MaxSize = Vector2.new(620, math.huge)
bannerLimit.Parent = banner
Theme.padding(banner, Theme.Spacing.M)
local bannerList = Instance.new("UIListLayout")
bannerList.Padding = UDim.new(0, 2)
bannerList.SortOrder = Enum.SortOrder.LayoutOrder
bannerList.Parent = banner
local bannerStep = Theme.label(banner, {
	LayoutOrder = 1,
	Size = UDim2.fromOffset(0, 16),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = Theme.BodyFont,
	TextSize = Theme.TextSize.Small,
	TextColor3 = Colors.Blue,
	Text = "",
})
local bannerText = Theme.label(banner, {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	TextSize = Theme.TextSize.Heading - 2,
	TextWrapped = true,
	Text = "",
})
local bannerTextLimit = Instance.new("UISizeConstraint")
bannerTextLimit.MaxSize = Vector2.new(580, math.huge)
bannerTextLimit.Parent = bannerText
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner

-- Pfeil (Dreieck-Zeichen), zeigt standardmäßig nach unten
local arrow = Theme.label(gui, {
	Name = "Arrow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(90, 90),
	Font = Enum.Font.GothamBlack,
	TextSize = 76,
	TextColor3 = Colors.Blue,
	TextXAlignment = Enum.TextXAlignment.Center,
	Text = "▼",
	Visible = false,
	Outline = 1.5,
})
local arrowScale = Instance.new("UIScale")
arrowScale.Parent = arrow
game:GetService("TweenService"):Create(
	arrowScale,
	TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.2 }
):Play()

local skipButton = Theme.secondaryButton(gui, {
	Name = "Skip",
	-- unten links (unten rechts ist VERKAUFEN, unten Mitte die Hotbar)
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(190, 40),
	Text = "Tutorial überspringen",
	TextSize = Theme.TextSize.Body - 2,
	Font = Theme.BodyFont,
	Radius = 10,
})
skipButton.Parent.Visible = false

------------------------------------------------------------------------
-- Pfeil-Steuerung
------------------------------------------------------------------------
local target = nil -- { Kind = "World", Get = function() -> Vector3 } oder { Kind = "Gui", Get = function() -> GuiObject }
local hideArrow = false -- z.B. während des Melkens
local bob = 0

local function setStep(text, newTarget, stepNumber)
	bannerText.Text = text
	bannerStep.Text = stepNumber and ("SCHRITT %d VON %d"):format(stepNumber, TOTAL_STEPS) or ""
	bannerStep.Visible = stepNumber ~= nil
	banner.Visible = text ~= ""
	bannerScale.Scale = 1.15
	Theme.tween(bannerScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	target = newTarget
end

RunService.RenderStepped:Connect(function(deltaTime)
	bob += deltaTime * 6
	local camera = workspace.CurrentCamera
	if not target or hideArrow or not camera then
		arrow.Visible = false
		return
	end

	local viewport = camera.ViewportSize
	local screenPos, onScreen, behind

	if target.Kind == "Gui" then
		local element = target.Get()
		if not element or not element.Visible then
			arrow.Visible = false
			return
		end
		-- Pfeil über dem Knopf (Inset beachten, weil diese GUI IgnoreGuiInset nutzt)
		local inset = GuiService:GetGuiInset()
		local center = element.AbsolutePosition + element.AbsoluteSize / 2 + inset
		screenPos = Vector2.new(center.X, center.Y - element.AbsoluteSize.Y / 2 - 50)
		onScreen, behind = true, false
	else
		local worldPos = target.Get()
		if not worldPos then
			arrow.Visible = false
			return
		end
		local point, visible = camera:WorldToViewportPoint(worldPos)
		screenPos = Vector2.new(point.X, point.Y)
		behind = point.Z < 0
		onScreen = visible and not behind
	end

	arrow.Visible = true
	if onScreen then
		-- über dem Ziel, zeigt nach unten und hüpft
		arrow.Rotation = 0
		arrow.Position = UDim2.fromOffset(screenPos.X, screenPos.Y - 40 + math.sin(bob) * 10)
	else
		-- am Bildschirmrand, zeigt in Richtung Ziel
		local center = viewport / 2
		local direction = screenPos - center
		if behind then
			direction = -direction
		end
		if direction.Magnitude < 1 then
			direction = Vector2.new(0, 1)
		end
		local margin = 80
		local half = center - Vector2.new(margin, margin)
		local scale = math.min(half.X / math.max(math.abs(direction.X), 0.001), half.Y / math.max(math.abs(direction.Y), 0.001))
		local edge = center + direction * scale
		arrow.Position = UDim2.fromOffset(edge.X, edge.Y)
		-- "▼" zeigt bei Rotation 0 nach unten (= Winkel 90°)
		arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) - 90
	end
end)

------------------------------------------------------------------------
-- Willkommens-Fenster
------------------------------------------------------------------------
local function showWelcome()
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Colors.Outline
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 20
	overlay.Parent = gui
	Theme.tween(overlay, { BackgroundTransparency = 0.4 }, 0.3)

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(480, 430)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 21
	holder.Parent = overlay
	Theme.softShadow(holder, Theme.Radius.XL)
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.3
	cardScale.Parent = holder
	local area = gui.AbsoluteSize
	local fit = math.clamp(math.min(1, (area.X - 30) / 480, (area.Y - 30) / 430), 0.4, 1)
	Theme.tween(cardScale, { Scale = fit }, 0.5, Enum.EasingStyle.Back)

	local card = Theme.panel(holder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		ZIndex = 22,
		Radius = Theme.Radius.XL,
		Outline = Theme.Stroke.Normal,
		OutlineColor = Colors.Blue,
	})

	-- hüpfende Kuh (gezeichnetes Symbol)
	local bounce = Instance.new("Frame")
	bounce.AnchorPoint = Vector2.new(0.5, 0)
	bounce.Position = UDim2.new(0.5, 0, 0, 22)
	bounce.Size = UDim2.fromOffset(100, 100)
	bounce.BackgroundTransparency = 1
	bounce.ZIndex = 23
	bounce.Parent = card
	Theme.cowIcon(bounce, 92, UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1), Color3.fromRGB(30, 30, 35))
	game:GetService("TweenService"):Create(bounce, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, 0, 0, 10),
		Rotation = 6,
	}):Play()

	local function cardText(text, y, size, font, color, height)
		return Theme.label(card, {
			Position = UDim2.fromOffset(24, y),
			Size = UDim2.new(1, -48, 0, height or size + 12),
			Font = font,
			TextSize = size,
			TextColor3 = color or Colors.Text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = text,
		})
	end
	cardText("Willkommen bei COW FARM!", 134, 30, Theme.Font)
	cardText("Du hast eine GRATIS Kuh bekommen.", 178, 20, Theme.Font, Colors.Blue)
	-- der Weg durchs Spiel in einer Zeile
	cardText("Melken  >  Verkaufen  >  Zweite Kuh kaufen  >  Zucht & Kisten", 218, 16, Theme.BodyFont, Colors.SubText, 44)
	cardText("Der Pfeil zeigt dir jeden Schritt. Unten links kannst du das Tutorial überspringen.", 268, 14, Theme.TextFont, Colors.SubText, 40)

	local go = Theme.primaryButton(card, {
		Text = "Los geht's!",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(240, 60),
		TextSize = 28,
		Radius = Theme.Radius.L,
		Lip = 6,
	})

	local closed = Instance.new("BindableEvent")
	go.Activated:Connect(function()
		Theme.tween(overlay, { BackgroundTransparency = 1 }, 0.25)
		local shrink = Theme.tween(cardScale, { Scale = 0 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		shrink.Completed:Wait()
		overlay:Destroy()
		closed:Fire()
	end)
	if game:GetService("UserInputService").GamepadEnabled then
		GuiService.SelectedObject = go -- Controller: A-Knopf drückt "Los geht's"
	end
	closed.Event:Wait()
	closed:Destroy()
end

------------------------------------------------------------------------
-- Kamerafahrt (3 Sekunden über die Farm)
------------------------------------------------------------------------
local function cinematicIntro(plot)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local TweenService = game:GetService("TweenService")
	local plotPos = plot and plot:GetPivot().Position or Vector3.new(0, 0, 60)
	local startCFrame = CFrame.lookAt(Vector3.new(0, 90, -140), Vector3.new(0, 0, 40))
	local endCFrame = CFrame.lookAt(plotPos + Vector3.new(-plotPos.X * 0.6, 45, -35), plotPos)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = startCFrame
	local tween = TweenService:Create(camera, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = endCFrame })
	tween:Play()
	tween.Completed:Wait()
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

------------------------------------------------------------------------
-- Ablauf
------------------------------------------------------------------------
local finished = false

local function finish()
	if finished then
		return
	end
	finished = true
	target = nil
	Remotes.TutorialDone:FireServer()
	gui:Destroy()
end

skipButton.Activated:Connect(finish)

-- Ereignisse, auf die die Schritte warten
local milkingStarted, firstMilk = false, false
Remotes.MilkingStarted.OnClientEvent:Connect(function()
	milkingStarted = true
	hideArrow = true
end)
Remotes.MilkingEnded.OnClientEvent:Connect(function(_, milk)
	hideArrow = false
	if (milk or 0) > 0 then
		firstMilk = true
	end
end)

local function waitUntil(condition, timeout)
	local start = os.clock()
	while not finished and not condition() do
		if timeout and os.clock() - start > timeout then
			return false
		end
		task.wait(0.15)
	end
	return not finished
end

local function menuWindowVisible()
	local menu = playerGui:FindFirstChild("MenuUI")
	local window = menu and menu:FindFirstChild("Window")
	return window ~= nil and window.Visible
end

task.spawn(function()
	local plot = waitForPlot(15)
	-- kurz warten, bis der Charakter auf der Farm steht
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.5)

	cinematicIntro(plot)
	showWelcome()
	if finished then
		return
	end
	skipButton.Parent.Visible = true

	-- Schritt 1: Deine Farm (mit Startkuh)
	setStep("Das ist DEINE Farm. Dort steht schon deine Gratis-Kuh!", {
		Kind = "World",
		Get = function()
			return plotSignPosition(plot or findMyPlot())
		end,
	}, 1)
	waitUntil(function()
		return false
	end, 3)

	-- Schritt 2: Kuh melken
	setStep("Klicke deine Kuh an und wähle „Melken“ (oder lauf auf die blaue Platte). Wechsle ◄ ► ab (Q / E)!", {
		Kind = "World",
		Get = function()
			return myFirstCowPosition(plot or findMyPlot())
		end,
	}, 2)
	if not waitUntil(function()
		return milkingStarted
	end) then
		return
	end
	banner.Visible = false

	-- Schritt 3: erste Milch -> verkaufen
	if not waitUntil(function()
		return firstMilk or (player:GetAttribute("Milk") or 0) > 0
	end) then
		return
	end
	local coinsBefore = player:GetAttribute("Coins") or 0
	setStep("Erste Milch gesammelt! Drück VERKAUFEN, um Coins zu bekommen.", {
		Kind = "Gui",
		Get = function()
			local hud = playerGui:FindFirstChild("HUD")
			local ref = hud and hud:FindFirstChild("SellButtonRef")
			return ref and ref.Value
		end,
	}, 3)
	if not waitUntil(function()
		return (player:GetAttribute("Coins") or 0) > coinsBefore and (player:GetAttribute("Milk") or 0) == 0
	end) then
		return
	end

	-- Schritt 4: zweite Kuh kaufen
	local earned = (player:GetAttribute("Coins") or 0) - coinsBefore
	local cowsBefore = player:GetAttribute("CowCount") or 1
	local price = CowData.Rarities.Common.ShopPrice
	setStep(("+%s Coins! Geh zum Kuh-Shop und kauf deine zweite Kuh (%s Coins)."):format(
		CowData.FormatNumber(earned),
		CowData.FormatNumber(price)
	), {
		Kind = "World",
		Get = function()
			return shopPosition("CowShop")
		end,
	}, 4)
	waitUntil(function()
		return (player:GetAttribute("CowCount") or 0) > cowsBefore
	end, 240)

	-- Schritt 5: Zucht und Kisten kennenlernen
	if not finished then
		setStep("Im Zucht-Stall kreuzt du zwei Kühe zu einem Kalb. Seltene Kühe gibt es in den Kisten am Nord-Markt (Taste M = Karte).", {
			Kind = "World",
			Get = function()
				return shopPosition("BreedingBarn")
			end,
		}, 5)
		waitUntil(menuWindowVisible, 60)
	end

	if not finished then
		setStep("Super! Jetzt kennst du alles. Das Feld „Nächstes Ziel“ oben links hilft dir weiter. Viel Spaß!", nil)
		task.wait(5)
		finish()
	end
end)
