-- TutorialClient.client.lua
-- Die ersten Sekunden für NEUE Spieler (Attribut TutorialDone = false):
--   1. Kamera schwenkt 3 Sekunden über die Farm
--   2. Willkommens-Fenster: "Du hast eine GRATIS Kuh bekommen!"
--   3. Pfeil zur eigenen Farm        ("Deine Farm!")
--   4. Pfeil zur Kuh                 ("Klicke deine Kuh an zum Melken!")
--   5. nach der ersten Milch: Pfeil zum VERKAUFEN-Knopf
--   6. nach dem ersten Verkauf: Pfeil zum Kuh-Shop
-- Danach (oder bei "Überspringen") meldet der Client Remotes.TutorialDone -> wird gespeichert.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local YELLOW = Color3.fromRGB(255, 220, 40)
local DARK = Color3.fromRGB(25, 27, 38)
local TEXT = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(55, 190, 80)

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

local function cowShopPosition()
	local hub = layout:FindFirstChild("Hub")
	local shop = hub and hub:FindFirstChild("CowShop")
	local floor = shop and shop:FindFirstChild("Floor")
	return floor and floor.Position + Vector3.new(0, 16, 0) or nil
end

------------------------------------------------------------------------
-- GUI: Hinweis-Banner, Pfeil, Überspringen
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 14)
	c.Parent = parent
	return c
end

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 1)
banner.Position = UDim2.new(0.5, 0, 1, -100) -- direkt über der Hotbar (feste Zone)
banner.Size = UDim2.fromOffset(0, 54)
banner.AutomaticSize = Enum.AutomaticSize.X
banner.BackgroundColor3 = DARK
banner.BackgroundTransparency = 0.05
banner.Font = Enum.Font.FredokaOne
banner.TextSize = 22
banner.TextColor3 = TEXT
banner.Text = ""
banner.Visible = false
banner.Parent = gui
corner(banner)
local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingLeft = UDim.new(0, 22)
bannerPadding.PaddingRight = UDim.new(0, 22)
bannerPadding.Parent = banner
local bannerStroke = Instance.new("UIStroke")
bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bannerStroke.Color = YELLOW
bannerStroke.Thickness = 3
bannerStroke.Parent = banner
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner

-- gelber Pfeil (Dreieck-Zeichen), zeigt standardmäßig nach unten
local arrow = Instance.new("TextLabel")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Size = UDim2.fromOffset(90, 90)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBlack
arrow.TextSize = 80
arrow.TextColor3 = YELLOW
arrow.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
arrow.TextStrokeTransparency = 0
arrow.Text = "▼"
arrow.Visible = false
arrow.Parent = gui
local arrowScale = Instance.new("UIScale")
arrowScale.Parent = arrow
TweenService:Create(arrowScale, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
-- unten links über dem Übersicht-Knopf (unten rechts ist der Verkaufen-Knopf)
skipButton.AnchorPoint = Vector2.new(0, 1)
skipButton.Position = UDim2.new(0, 16, 1, -16)
skipButton.Size = UDim2.fromOffset(150, 38)
skipButton.BackgroundColor3 = Color3.fromRGB(70, 74, 96)
skipButton.Font = Enum.Font.GothamBold
skipButton.TextSize = 15
skipButton.TextColor3 = TEXT
skipButton.Text = "Tutorial überspringen"
skipButton.Visible = false
skipButton.Parent = gui
corner(skipButton, UDim.new(0, 10))

------------------------------------------------------------------------
-- Pfeil-Steuerung
------------------------------------------------------------------------
local target = nil -- { Kind = "World", Get = function() -> Vector3 } oder { Kind = "Gui", Get = function() -> GuiObject }
local hideArrow = false -- z.B. während des Melkens
local bob = 0

local function setStep(text, newTarget)
	banner.Text = text
	banner.Visible = text ~= ""
	bannerScale.Scale = 1.25
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 20
	overlay.Parent = gui
	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(460, 380)
	card.BackgroundColor3 = DARK
	card.ZIndex = 21
	card.Parent = overlay
	corner(card, UDim.new(0, 24))
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = YELLOW
	cardStroke.Thickness = 4
	cardStroke.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.3
	cardScale.Parent = card
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 800)
	local fit = math.min(1, (viewport.X - 30) / 460, (viewport.Y - 30) / 380)
	TweenService:Create(cardScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()

	-- hüpfende Cartoon-Kuh (aus Frames)
	local cow = Instance.new("Frame")
	cow.AnchorPoint = Vector2.new(0.5, 0)
	cow.Position = UDim2.new(0.5, 0, 0, 18)
	cow.Size = UDim2.fromOffset(120, 110)
	cow.BackgroundTransparency = 1
	cow.ZIndex = 22
	cow.Parent = card
	local function blob(parent, size, position, color, z)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = position
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = parent
		corner(f, UDim.new(1, 0))
		return f
	end
	local ears = {
		blob(cow, UDim2.fromOffset(40, 24), UDim2.fromOffset(14, 34), Color3.new(1, 1, 1), 22),
		blob(cow, UDim2.fromOffset(40, 24), UDim2.fromOffset(106, 34), Color3.new(1, 1, 1), 22),
	}
	ears[1].Rotation = -25
	ears[2].Rotation = 25
	local head = blob(cow, UDim2.fromOffset(100, 96), UDim2.fromOffset(60, 56), Color3.new(1, 1, 1), 23)
	local headStroke = Instance.new("UIStroke")
	headStroke.Color = Color3.fromRGB(30, 30, 40)
	headStroke.Thickness = 3
	headStroke.Parent = head
	blob(head, UDim2.fromOffset(34, 30), UDim2.fromOffset(26, 26), Color3.fromRGB(30, 30, 35), 24)
	for _, x in ipairs({ 0.32, 0.68 }) do
		local eye = blob(head, UDim2.fromOffset(24, 26), UDim2.fromScale(x, 0.4), Color3.new(1, 1, 1), 25)
		blob(eye, UDim2.fromOffset(13, 15), UDim2.fromScale(0.55, 0.55), Color3.fromRGB(20, 20, 25), 26)
	end
	local snout = blob(head, UDim2.fromOffset(60, 34), UDim2.fromScale(0.5, 0.78), Color3.fromRGB(255, 170, 185), 25)
	for _, x in ipairs({ 0.32, 0.68 }) do
		blob(snout, UDim2.fromOffset(8, 11), UDim2.fromScale(x, 0.45), Color3.fromRGB(190, 90, 110), 26)
	end
	TweenService:Create(cow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, 0, 0, 6),
		Rotation = 6,
	}):Play()

	local function cardText(text, y, size, font, color)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(20, y)
		label.Size = UDim2.new(1, -40, 0, size + 14)
		label.Font = font
		label.TextSize = size
		label.TextColor3 = color or TEXT
		label.TextWrapped = true
		label.Text = text
		label.ZIndex = 22
		label.Parent = card
		return label
	end
	cardText("Willkommen bei 🐄 COW FARM!", 140, 30, Enum.Font.FredokaOne, YELLOW)
	cardText("Du hast eine GRATIS Kuh bekommen! 🎉", 190, 22, Enum.Font.FredokaOne)
	cardText("Melke sie, verkaufe die Milch und baue die größte Farm!", 226, 16, Enum.Font.GothamBold,
		Color3.fromRGB(200, 205, 220))

	local go = Instance.new("TextButton")
	go.AnchorPoint = Vector2.new(0.5, 1)
	go.Position = UDim2.new(0.5, 0, 1, -24)
	go.Size = UDim2.fromOffset(240, 64)
	go.BackgroundColor3 = GREEN
	go.Font = Enum.Font.FredokaOne
	go.TextSize = 30
	go.TextColor3 = TEXT
	go.TextStrokeColor3 = Color3.fromRGB(20, 70, 30)
	go.TextStrokeTransparency = 0
	go.Text = "Los geht's! ▶"
	go.ZIndex = 22
	go.Parent = card
	corner(go, UDim.new(1, 0))
	local goScale = Instance.new("UIScale")
	goScale.Parent = go
	TweenService:Create(goScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()

	local closed = Instance.new("BindableEvent")
	go.Activated:Connect(function()
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		local shrink = TweenService:Create(cardScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		shrink:Play()
		shrink.Completed:Wait()
		overlay:Destroy()
		closed:Fire()
	end)
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
	skipButton.Visible = true

	-- Schritt: Deine Farm
	setStep("🏡 Das ist DEINE Farm!", {
		Kind = "World",
		Get = function()
			return plotSignPosition(plot or findMyPlot())
		end,
	})
	waitUntil(function()
		return false
	end, 3)

	-- Schritt: Kuh melken
	setStep("🐄 Klicke deine Kuh an und wähle „Melken“ (oder lauf auf die blaue Platte)!", {
		Kind = "World",
		Get = function()
			return myFirstCowPosition(plot or findMyPlot())
		end,
	})
	if not waitUntil(function()
		return milkingStarted
	end) then
		return
	end
	banner.Visible = false

	-- Schritt: erste Milch -> verkaufen
	if not waitUntil(function()
		return firstMilk or (player:GetAttribute("Milk") or 0) > 0
	end) then
		return
	end
	local coinsBefore = player:GetAttribute("Coins") or 0
	setStep("🎉 Erste Milch gesammelt! Jetzt verkaufen!", {
		Kind = "Gui",
		Get = function()
			local hud = playerGui:FindFirstChild("HUD")
			local ref = hud and hud:FindFirstChild("SellButtonRef")
			return ref and ref.Value
		end,
	})
	if not waitUntil(function()
		return (player:GetAttribute("Coins") or 0) > coinsBefore and (player:GetAttribute("Milk") or 0) == 0
	end) then
		return
	end

	-- Schritt: zum Shop
	local earned = (player:GetAttribute("Coins") or 0) - coinsBefore
	setStep(("💰 +%s Coins! Kauf mehr Kühe im Kuh-Shop!"):format(CowData.FormatNumber(earned)), {
		Kind = "World",
		Get = cowShopPosition,
	})
	waitUntil(function()
		local menu = playerGui:FindFirstChild("MenuUI")
		local window = menu and menu:FindFirstChild("Window")
		return window ~= nil and window.Visible
	end, 60)

	if not finished then
		setStep("✅ Super! Jetzt weißt du alles. Viel Spaß auf deiner Farm!", nil)
		task.wait(3)
		finish()
	end
end)
