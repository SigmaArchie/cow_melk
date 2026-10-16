-- MilkingClient.client.lua
-- Melk-Minispiel auf dem Client (Gefühl wie ein Handy-Klickspiel):
--   * Bildschirm wird abgedunkelt, Panel gleitet von unten herein
--   * Cartoon-Kuhgesicht oben, zwei große runde Knöpfe ◄ / ► (Tasten Q / E, Controller L1 / R1)
--   * Fortschrittsbalken + Eimer in der Mitte füllt sich sichtbar mit weißer Milch
--   * richtiger Zug: Kamera wackelt leicht, Spritz-Sound, "+X" fliegt nach oben
--   * falscher Zug (gleiche Seite zweimal): Knöpfe rot, stärkeres Wackeln, Fortschritt verloren
--   * fertig: Eimer kippt, großes "+X MILCH!" springt auf den Bildschirm
--   * Aufstehen: Knopf, Controller B (am Handy: Knopf antippen)
-- Der Server entscheidet (MilkPull) und schickt den echten Stand zurück (MilkingProgress).
-- Stil und Bausteine kommen aus Theme.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("Theme"))
local Config = CowData.Config
local Colors = Theme.Colors

local player = Players.LocalPlayer

local ACTION_NAME = "CowFarmMilkPull"
local CLIENT_PULL_INTERVAL = 0.12 -- etwas langsamer als der Server erlaubt

local TEXT = Colors.Text
local SUBTEXT = Colors.SubText
local LEFT_COLOR = Colors.Blue
local RIGHT_COLOR = Colors.Green
local WRONG_COLOR = Colors.Red
local MILK_COLOR = Color3.fromRGB(250, 252, 255)
local BUCKET_WOOD = Color3.fromRGB(150, 100, 60)
local WRONG_TEXT = Color3.fromRGB(255, 160, 150)

------------------------------------------------------------------------
-- Zustand
------------------------------------------------------------------------
local session = nil -- { CowId, Needed, Pulls, MilkPerPull, Penalty, LastSide, LastPull, Spot, TeatsHome }
local endToken = 0 -- zählt Sessions; verhindert, dass ein altes MilkingEnded eine neue Session abräumt

------------------------------------------------------------------------
-- UI-Helfer
------------------------------------------------------------------------
local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = TEXT
	l.Font = Theme.Font
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function circle(parent, size, position, color, z)
	local c = frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		Position = position,
		BackgroundColor3 = color,
		ZIndex = z or 1,
	})
	Theme.corner(c, UDim.new(1, 0))
	return c
end

-- Tastenbeschriftung je nach Eingabegerät (Tastatur / Controller / Touch)
local function keyLabels()
	local input = UserInputService:GetLastInputType()
	if input.Name:sub(1, 7) == "Gamepad" then
		return "L1", "R1", true
	end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return "Q", "E", not touchOnly
end

------------------------------------------------------------------------
-- GUI aufbauen
------------------------------------------------------------------------
local gui = Theme.screenGui("MilkingUI", 10)
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- dunkler Schleier über dem Bildschirm
local overlay = frame(gui, {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Outline,
	BackgroundTransparency = 1,
})

local PANEL_SIZE = Vector2.new(440, 380)
local PANEL_SHOWN = UDim2.new(0.5, 0, 1, -20)
local PANEL_HIDDEN = UDim2.new(0.5, 0, 1, PANEL_SIZE.Y + 140)

-- Halter trägt Schatten + Fläche und wird verschoben/skaliert
local panel = frame(gui, {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = PANEL_HIDDEN,
	Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
	BackgroundTransparency = 1,
})
Theme.softShadow(panel, Theme.Radius.XL + 6)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local card = Theme.panel(panel, {
	Name = "Card",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Panel,
	Radius = Theme.Radius.XL + 6,
	Outline = Theme.Stroke.Normal + 0.5, -- Farbe = Seltenheit der Kuh
})
local panelStroke = card:FindFirstChildOfClass("UIStroke")

------------------------------------------------------------------------
-- Cartoon-Kuhgesicht (ragt oben aus dem Panel heraus)
------------------------------------------------------------------------
local face = frame(card, {
	Name = "CowFace",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(130, 120),
	BackgroundTransparency = 1,
	ZIndex = 5,
})
local faceScale = Instance.new("UIScale")
faceScale.Parent = face

local earLeft = circle(face, UDim2.fromOffset(44, 26), UDim2.fromOffset(10, 34), Color3.new(1, 1, 1), 5)
earLeft.Rotation = -25
local earRight = circle(face, UDim2.fromOffset(44, 26), UDim2.new(1, -10, 0, 34), Color3.new(1, 1, 1), 5)
earRight.Rotation = 25
local faceHead = circle(face, UDim2.fromOffset(110, 104), UDim2.fromScale(0.5, 0.52), Color3.new(1, 1, 1), 6)
Theme.border(faceHead, 2.5, Colors.Outline)
local faceSpot = circle(faceHead, UDim2.fromOffset(40, 34), UDim2.fromOffset(26, 30), Color3.fromRGB(30, 30, 35), 7)
local eyes = {}
for _, x in ipairs({ 0.33, 0.67 }) do
	local white = circle(faceHead, UDim2.fromOffset(28, 30), UDim2.fromScale(x, 0.4), Color3.new(1, 1, 1), 8)
	Theme.border(white, 1.5, Colors.Outline)
	circle(white, UDim2.fromOffset(15, 17), UDim2.fromScale(0.55, 0.55), Color3.fromRGB(20, 20, 25), 9)
	circle(white, UDim2.fromOffset(6, 6), UDim2.fromScale(0.68, 0.38), Color3.new(1, 1, 1), 10)
	table.insert(eyes, white)
end
local snout = circle(faceHead, UDim2.fromOffset(68, 40), UDim2.fromScale(0.5, 0.78), Color3.fromRGB(255, 170, 185), 8)
for _, x in ipairs({ 0.32, 0.68 }) do
	circle(snout, UDim2.fromOffset(9, 12), UDim2.fromScale(x, 0.45), Color3.fromRGB(190, 90, 110), 9)
end

-- ab und zu blinzeln
task.spawn(function()
	while true do
		task.wait(math.random(25, 45) / 10)
		if gui.Enabled then
			for _, eye in ipairs(eyes) do
				eye.Size = UDim2.fromOffset(28, 4)
			end
			task.wait(0.1)
			for _, eye in ipairs(eyes) do
				eye.Size = UDim2.fromOffset(28, 30)
			end
		end
	end
end)

local title = text(card, {
	Name = "Title",
	Position = UDim2.fromOffset(0, 70),
	Size = UDim2.new(1, 0, 0, 30),
	TextSize = 26,
	Text = "Melken",
})

local hint = text(card, {
	Name = "Hint",
	Position = UDim2.fromOffset(16, 100),
	Size = UDim2.new(1, -32, 0, 20),
	Font = Theme.BodyFont,
	TextSize = Theme.TextSize.Body - 1,
	TextColor3 = SUBTEXT,
	TextWrapped = true,
	Text = "Abwechselnd ◄ ► ziehen!",
})

-- Fortschritt (richtige Züge)
local progress = Theme.progressBar(card, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 126),
	Size = UDim2.new(0.62, 0, 0, 8),
	Color = Colors.Green,
})

------------------------------------------------------------------------
-- Eimer in der Mitte
------------------------------------------------------------------------
local bucketHolder = frame(card, {
	Name = "BucketHolder",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 146),
	Size = UDim2.fromOffset(120, 140),
	BackgroundTransparency = 1,
	ZIndex = 3,
})
local bucket = frame(bucketHolder, {
	Name = "Bucket",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromOffset(110, 124),
	BackgroundColor3 = BUCKET_WOOD,
	ClipsDescendants = true,
	ZIndex = 3,
})
Theme.corner(bucket, 18)
Theme.border(bucket, 3, Color3.fromRGB(80, 50, 30))
-- Innenraum (dunkler)
local bucketInside = frame(bucket, {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 1, -16),
	BackgroundColor3 = Color3.fromRGB(70, 45, 28),
	ZIndex = 3,
})
Theme.corner(bucketInside, 12)
local milkFill = frame(bucketInside, {
	Name = "Milk",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = MILK_COLOR,
	ZIndex = 4,
})
Theme.corner(milkFill, 12)
-- Metallreifen
for _, y in ipairs({ 0.3, 0.75 }) do
	frame(bucket, {
		Position = UDim2.fromScale(0, y),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Color3.fromRGB(170, 175, 185),
		BackgroundTransparency = 0.2,
		ZIndex = 5,
	})
end
local bucketText = text(bucket, {
	Size = UDim2.fromScale(1, 1),
	TextSize = 26,
	ZIndex = 6,
	Text = "0/10",
})
Theme.textOutline(bucketText, 1.5)

------------------------------------------------------------------------
-- Große runde Knöpfe
------------------------------------------------------------------------
local BUTTON_SIZE = 112

local function makeRoundButton(name, symbol, xScale, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(xScale, 0, 0, 218)
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 48
	button.TextColor3 = TEXT
	button.Text = symbol
	button.ZIndex = 3
	button.Parent = card
	Theme.corner(button, UDim.new(1, 0))
	Theme.textOutline(button, 1.5)

	local stroke = Theme.border(button, 3, Theme.darken(color, 0.45))

	local key = text(button, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(38, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = Colors.Deep,
		Font = Theme.BodyFont,
		TextSize = Theme.TextSize.Small,
		Text = "",
		ZIndex = 4,
	})
	Theme.corner(key, 8)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local entry = { Button = button, Stroke = stroke, Scale = scale, Color = color, Key = key }
	-- Hover (Maus) / Auswahl (Controller): kurz heller
	button.MouseEnter:Connect(function()
		Theme.tween(button, { BackgroundColor3 = Theme.lighten(entry.Color, 0.12) }, Theme.Time.Fast)
	end)
	button.MouseLeave:Connect(function()
		Theme.tween(button, { BackgroundColor3 = entry.Color }, Theme.Time.Fast)
	end)
	return entry
end

local buttons = {
	Left = makeRoundButton("Left", "◄", 0.17, LEFT_COLOR),
	Right = makeRoundButton("Right", "►", 0.83, RIGHT_COLOR),
}

local leaveButton = Theme.secondaryButton(card, {
	Name = "Leave",
	Text = "Aufstehen",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(150, 40),
	TextSize = Theme.TextSize.Body,
	Radius = 10,
})

-- Tastenbeschriftung aktualisieren (Tastatur / Controller / Touch)
local function updateKeyLabels()
	local left, right, visible = keyLabels()
	buttons.Left.Key.Text = left
	buttons.Right.Key.Text = right
	buttons.Left.Key.Visible = visible
	buttons.Right.Key.Visible = visible
	return left, right
end

-- großer Abschluss-Text "+X MILCH!"
local bigReward = text(gui, {
	Name = "BigReward",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromOffset(600, 120),
	TextSize = 76,
	TextColor3 = TEXT,
	Visible = false,
	ZIndex = 20,
})
local bigRewardStroke = Theme.textOutline(bigReward, 1.5)
bigRewardStroke.Color = Colors.Deep
bigRewardStroke.Transparency = 0.2
bigRewardStroke.Thickness = 3
local bigRewardScale = Instance.new("UIScale")
bigRewardScale.Parent = bigReward

------------------------------------------------------------------------
-- Sound
------------------------------------------------------------------------
local function playSound(soundId, volume, speed)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.7
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

------------------------------------------------------------------------
-- Kamera-Wackeln
------------------------------------------------------------------------
local shakeStrength = 0
local SHAKE_BIND = "CowFarmMilkShake"

RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if shakeStrength <= 0.001 then
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		local s = shakeStrength
		camera.CFrame = camera.CFrame * CFrame.new(
			(math.random() - 0.5) * s,
			(math.random() - 0.5) * s,
			0
		) * CFrame.Angles(0, 0, (math.random() - 0.5) * s * 0.05)
	end
	shakeStrength = math.max(0, shakeStrength - deltaTime * 2.5)
end)

local function shake(strength)
	shakeStrength = math.max(shakeStrength, strength)
end

------------------------------------------------------------------------
-- Optionale echte Animation (nur wenn eine ID eingetragen ist)
------------------------------------------------------------------------
local animationTrack = nil

local function startAnimation()
	if not Config.MilkingAnimationId or Config.MilkingAnimationId == 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(Config.MilkingAnimationId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.2)
		animationTrack = track
	end
end

local function stopAnimation()
	if animationTrack then
		animationTrack:Stop(0.2)
		animationTrack = nil
	end
end

------------------------------------------------------------------------
-- Effekte an der echten Kuh (lokal): Zitze zuckt, Milchtropfen in den Eimer
------------------------------------------------------------------------
local function squirtEffect(side)
	if not session or not session.Spot then
		return
	end
	local cow = session.Spot:FindFirstChild("Cow")
	local bucketModel = session.Spot:FindFirstChild("Bucket")
	local bottom = bucketModel and bucketModel.PrimaryPart
	if not cow then
		return
	end

	for _, suffix in ipairs({ "A", "B" }) do
		local teat = cow:FindFirstChild("Teat" .. side .. suffix)
		if teat then
			local home = session.TeatsHome[teat]
			if not home then
				home = teat.CFrame
				session.TeatsHome[teat] = home
			end
			teat.CFrame = home - Vector3.new(0, 0.15, 0) -- nach unten ziehen (Welt-Achse, passt für jedes Modell)
			TweenService:Create(teat, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = home }):Play()

			if bottom then
				local drop = Instance.new("Part")
				drop.Shape = Enum.PartType.Ball
				drop.Size = Vector3.new(0.18, 0.18, 0.18)
				drop.Color = MILK_COLOR
				drop.Anchored = true
				drop.CanCollide = false
				drop.CanQuery = false
				drop.CastShadow = false
				local start = teat.Position - Vector3.new(0, 0.35, 0)
				drop.CFrame = CFrame.new(start)
				drop.Parent = workspace
				local tween = TweenService:Create(drop, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(Vector3.new(start.X, bottom.Position.Y + 0.5, start.Z)),
					Size = Vector3.new(0.1, 0.35, 0.1),
				})
				tween:Play()
				tween.Completed:Connect(function()
					drop:Destroy()
				end)
			end
		end
	end
end

local function resetTeats()
	if not session then
		return
	end
	for teat, home in pairs(session.TeatsHome) do
		if teat.Parent then
			teat.CFrame = home
		end
	end
end

------------------------------------------------------------------------
-- UI-Logik
------------------------------------------------------------------------
local function expectedSide()
	if not session or not session.LastSide then
		return nil -- erster Zug: egal welche Seite
	end
	return session.LastSide == "Left" and "Right" or "Left"
end

local function updateUi()
	if not session then
		return
	end
	local ratio = math.clamp(session.Pulls / session.Needed, 0, 1)
	Theme.tween(milkFill, { Size = UDim2.fromScale(1, ratio) }, 0.25, Enum.EasingStyle.Back)
	progress.SetRatio(ratio)
	bucketText.Text = ("%d/%d"):format(session.Pulls, session.Needed)

	-- der erwartete Knopf leuchtet, der andere ist gedimmt
	local expected = expectedSide()
	for side, entry in pairs(buttons) do
		local active = expected == nil or expected == side
		Theme.tween(entry.Button, { BackgroundTransparency = active and 0 or 0.5 }, Theme.Time.Fast)
		Theme.tween(entry.Stroke, { Transparency = active and 0 or 0.7 }, Theme.Time.Fast)
	end
end

-- "+X" fliegt aus dem Eimer nach oben
local function popNumber(message, color)
	local pop = text(card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-30, 30), 0, 160),
		Size = UDim2.fromOffset(120, 40),
		TextSize = 32,
		TextColor3 = color,
		Text = message,
		ZIndex = 12,
	})
	local stroke = Theme.textOutline(pop, 1.5)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = pop
	Theme.tween(scale, { Scale = 1.2 }, 0.2, Enum.EasingStyle.Back)
	Theme.tween(pop, {
		Position = pop.Position - UDim2.fromOffset(0, 90),
		TextTransparency = 1,
	}, 0.8)
	Theme.tween(stroke, { Transparency = 1 }, 0.8)
	task.delay(0.85, function()
		pop:Destroy()
	end)
end

local function pressButton(entry)
	entry.Scale.Scale = 0.88
	Theme.tween(entry.Scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
end

local function wrongSide()
	for _, entry in pairs(buttons) do
		entry.Button.BackgroundColor3 = WRONG_COLOR
		Theme.tween(entry.Button, { BackgroundColor3 = entry.Color }, 0.45)
	end
	milkFill.BackgroundColor3 = WRONG_COLOR
	Theme.tween(milkFill, { BackgroundColor3 = MILK_COLOR }, 0.45)
	shake(1.2)
	popNumber("-" .. session.Penalty, WRONG_TEXT)
	hint.Text = "Falsche Seite! Jetzt die ANDERE Seite."
	hint.TextColor3 = WRONG_TEXT
end

local function pull(side)
	if not session or session.Finishing then
		return
	end
	local now = os.clock()
	if now - session.LastPull < CLIENT_PULL_INTERVAL then
		return
	end
	session.LastPull = now
	pressButton(buttons[side])

	if side == session.LastSide then
		-- falsche Seite: Fortschritt verlieren (der Server macht dasselbe)
		session.Pulls = math.max(0, session.Pulls - session.Penalty)
		wrongSide()
		playSound(Config.SquirtSoundId, 0.5, 0.55)
	else
		session.LastSide = side
		session.Pulls += 1
		hint.Text = "Super! Weiter abwechseln ◄ ►"
		hint.TextColor3 = SUBTEXT
		squirtEffect(side)
		shake(0.35)
		popNumber("+" .. CowData.FormatNumber(session.MilkPerPull), MILK_COLOR)
		playSound(Config.SquirtSoundId, 0.8, 0.95 + math.random() * 0.25)
		faceScale.Scale = 1.08
		Theme.tween(faceScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		if animationTrack then
			animationTrack:AdjustSpeed(1.6)
			task.delay(0.15, function()
				if animationTrack then
					animationTrack:AdjustSpeed(1)
				end
			end)
		end
	end

	Remotes.MilkPull:FireServer(side)
	updateUi()
end

local function onAction(_, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local key = inputObject.KeyCode
	if key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonL1 then
		pull("Left")
	elseif key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonR1 then
		pull("Right")
	elseif key == Enum.KeyCode.ButtonB then
		Remotes.StopMilking:FireServer() -- Controller: aufstehen
	end
	return Enum.ContextActionResult.Sink
end

buttons.Left.Button.Activated:Connect(function()
	pull("Left")
end)
buttons.Right.Button.Activated:Connect(function()
	pull("Right")
end)
leaveButton.Activated:Connect(function()
	Remotes.StopMilking:FireServer()
end)

------------------------------------------------------------------------
-- Öffnen / Schließen
------------------------------------------------------------------------
local function showPanel()
	gui.Enabled = true
	local area = gui.AbsoluteSize
	if area.X < 10 or area.Y < 10 then
		area = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 800)
	end
	-- passt auch auf kleine Handy-Bildschirme (Safe-Area ist schon abgezogen)
	panelScale.Scale = math.clamp(math.min(1, (area.X - 24) / PANEL_SIZE.X, (area.Y - 60) / (PANEL_SIZE.Y + 60)), 0.5, 1)
	bucket.Rotation = 0
	panel.Position = PANEL_HIDDEN
	Theme.tween(overlay, { BackgroundTransparency = 0.4 }, 0.3)
	Theme.tween(panel, { Position = PANEL_SHOWN }, 0.45, Enum.EasingStyle.Back)
end

local function hidePanel(token)
	Theme.tween(overlay, { BackgroundTransparency = 1 }, 0.3)
	local slide = Theme.tween(panel, { Position = PANEL_HIDDEN }, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	slide.Completed:Wait()
	-- nur ausblenden, wenn in der Zwischenzeit keine neue Session gestartet wurde
	if endToken == token and not session then
		gui.Enabled = false
	end
end

local function cleanupSession()
	ContextActionService:UnbindAction(ACTION_NAME)
	stopAnimation()
	resetTeats()
	session = nil
end

------------------------------------------------------------------------
-- Start / Fortschritt / Ende (vom Server)
------------------------------------------------------------------------
Remotes.MilkingStarted.OnClientEvent:Connect(function(info)
	endToken += 1
	Theme.closeAllWindows() -- während des Melkens ist kein anderes Fenster offen
	session = {
		CowId = info.CowId,
		Needed = info.PullsNeeded,
		MilkPerPull = info.MilkPerPull,
		Penalty = info.Penalty or 1,
		Pulls = 0,
		LastSide = nil,
		LastPull = 0,
		Spot = info.Spot,
		TeatsHome = {},
		Finishing = false,
	}

	local rarityInfo = CowData.Rarities[info.Rarity] or CowData.Rarities.Common
	title.Text = ("%s melken"):format(info.CowName)
	panelStroke.Color = rarityInfo.UiColor
	faceHead.BackgroundColor3 = rarityInfo.Color
	earLeft.BackgroundColor3 = rarityInfo.Color
	earRight.BackgroundColor3 = rarityInfo.Color
	faceSpot.Visible = rarityInfo.SpotColor ~= nil
	if rarityInfo.SpotColor then
		faceSpot.BackgroundColor3 = rarityInfo.SpotColor
	end
	local leftKey, rightKey = updateKeyLabels()
	hint.Text = ("Abwechselnd ◄ ► ziehen! (%s / %s)"):format(leftKey, rightKey)
	hint.TextColor3 = SUBTEXT
	milkFill.Size = UDim2.fromScale(1, 0)
	progress.SetRatio(0, false)
	bigReward.Visible = false
	updateUi()
	showPanel()

	ContextActionService:BindActionAtPriority(
		ACTION_NAME,
		onAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonB
	)
	startAnimation()
end)

-- Echter Stand vom Server (korrigiert, falls ein Zug abgelehnt wurde)
Remotes.MilkingProgress.OnClientEvent:Connect(function(pulls, lastSide)
	if not session then
		return
	end
	if session.Pulls ~= pulls or session.LastSide ~= lastSide then
		session.Pulls = pulls
		session.LastSide = lastSide
		updateUi()
	end
end)

local function celebrate(milk)
	-- Eimer kippt um
	milkFill.Size = UDim2.fromScale(1, 1)
	progress.SetRatio(1)
	bucketText.Text = "VOLL!"
	Theme.tween(bucket, { Rotation = -100 }, 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	shake(0.8)

	-- großes "+X MILCH!" springt auf den Bildschirm
	bigReward.Text = ("+%s MILCH!"):format(CowData.FormatNumber(milk))
	bigReward.Visible = true
	bigReward.TextTransparency = 0
	bigRewardStroke.Transparency = 0.2
	bigReward.Rotation = -8
	bigRewardScale.Scale = 0.2
	Theme.tween(bigRewardScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Elastic)
	Theme.tween(bigReward, { Rotation = 0 }, 0.5, Enum.EasingStyle.Back)
	playSound(Config.MilkDoneSoundId, 1, 0.75)

	task.delay(1.4, function()
		Theme.tween(bigReward, { TextTransparency = 1 }, 0.4)
		Theme.tween(bigRewardStroke, { Transparency = 1 }, 0.4)
		Theme.tween(bigRewardScale, { Scale = 1.4 }, 0.4)
		task.wait(0.45)
		bigReward.Visible = false
	end)
end

Remotes.MilkingEnded.OnClientEvent:Connect(function(completed, milk)
	endToken += 1
	local token = endToken
	if session then
		session.Finishing = true
	end
	ContextActionService:UnbindAction(ACTION_NAME)
	stopAnimation()
	resetTeats()

	if completed then
		celebrate(milk or 0)
		task.wait(1.8) -- großen Text ausklingen lassen
		if endToken ~= token then
			return -- inzwischen läuft schon eine neue Session: nichts abräumen
		end
	end
	session = nil
	hidePanel(token)
end)

player.CharacterAdded:Connect(function()
	-- neuer Charakter -> alte Session aufräumen
	endToken += 1
	cleanupSession()
	gui.Enabled = false
	overlay.BackgroundTransparency = 1
	panel.Position = PANEL_HIDDEN
end)
