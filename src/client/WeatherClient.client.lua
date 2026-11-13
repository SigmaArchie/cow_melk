-- WeatherClient.client.lua
-- Zeigt das Wetter, das WeatherManager.server.lua am Workspace setzt (Attribut "Weather"):
--   Regen        etwas dunkler, Regenstreifen
--   Gewitter     noch dunkler, mehr Regen, ab und zu ein Blitz (heller Flash)
--   Schnee       kühler Farbton, Schneeflocken
--   Sternennacht es wird Nacht, glitzernder Sternenstaub
-- Alles läuft nur auf dem Client (Lighting-Änderungen sieht nur dieser Spieler).
-- Die Anzeige mit Restzeit steht im HUD (CoinDisplay.client.lua).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local rng = Random.new()

-- So sieht jedes Wetter aus (Light = Faktor für Lighting.Brightness)
local LOOKS = {
	Clear = { Tint = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0, Light = 1 },
	Rain = { Tint = Color3.fromRGB(205, 214, 228), Saturation = -0.2, Contrast = 0.05, Brightness = -0.03, Light = 0.6 },
	Storm = {
		Tint = Color3.fromRGB(176, 186, 210),
		Saturation = -0.35,
		Contrast = 0.1,
		Brightness = -0.06,
		Light = 0.4,
	},
	Snow = { Tint = Color3.fromRGB(226, 236, 255), Saturation = -0.25, Contrast = 0, Brightness = 0.03, Light = 0.9 },
	StarNight = {
		Tint = Color3.fromRGB(205, 196, 255),
		Saturation = 0.05,
		Contrast = 0.05,
		Brightness = 0,
		Light = 1,
		Night = true,
	},
}

-- welche Partikel bei welchem Wetter laufen
local USES = {
	Rain = { "Rain" },
	Storm = { "Rain" },
	Snow = { "Snow" },
	StarNight = { "Stars" },
}

------------------------------------------------------------------------
-- Farbton (nur dieser Client)
------------------------------------------------------------------------
local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "WeatherTint"
tint.Parent = Lighting

------------------------------------------------------------------------
-- Partikel: unsichtbare Platte über der Kamera, Partikel fallen nach unten
------------------------------------------------------------------------
local emitterPart = Instance.new("Part")
emitterPart.Name = "WeatherEmitter"
emitterPart.Anchored = true
emitterPart.CanCollide = false
emitterPart.CanQuery = false
emitterPart.CanTouch = false
emitterPart.CastShadow = false
emitterPart.Transparency = 1
emitterPart.Size = Vector3.new(140, 1, 140)
emitterPart.Parent = workspace -- nur auf diesem Client (wird nicht repliziert)

local function emitter(name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.EmissionDirection = Enum.NormalId.Bottom
	for key, value in pairs(props) do
		e[key] = value
	end
	e.Parent = emitterPart
	return e
end

local emitters = {
	Rain = emitter("Rain", {
		Color = ColorSequence.new(Color3.fromRGB(200, 215, 235)),
		Transparency = NumberSequence.new(0.35),
		Size = NumberSequence.new(0.12),
		Squash = NumberSequence.new(3), -- lange Streifen statt Punkte
		Speed = NumberRange.new(80, 95),
		Lifetime = NumberRange.new(0.7, 0.9),
		Rate = 500,
	}),
	Snow = emitter("Snow", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0.1),
		Size = NumberSequence.new(0.3),
		Speed = NumberRange.new(6, 10),
		Lifetime = NumberRange.new(5, 7),
		Rate = 220,
		SpreadAngle = Vector2.new(25, 25),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = Vector3.new(2, 0, 1), -- leichter Wind
	}),
	Stars = emitter("Stars", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 170, 255)),
		}),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Speed = NumberRange.new(3, 6),
		Lifetime = NumberRange.new(4, 6),
		Rate = 40,
		SpreadAngle = Vector2.new(40, 40),
	}),
}

local anyActive = false
RunService.RenderStepped:Connect(function()
	if anyActive then
		local camera = workspace.CurrentCamera
		if camera then
			emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
		end
	end
end)

------------------------------------------------------------------------
-- Wetter anwenden
------------------------------------------------------------------------
local current = "Clear"
local saved = nil -- Lighting-Werte vor dem ersten Wetter (= "Sonne")
local stormToken = 0

-- Blitz: kurz alles hell, dann zurück
local function flash()
	tint.Brightness = 0.55
	TweenService:Create(tint, TweenInfo.new(0.35), { Brightness = LOOKS.Storm.Brightness }):Play()
end

local function lightningLoop(token)
	while stormToken == token and current == "Storm" do
		task.wait(rng:NextNumber(4, 10))
		if stormToken == token and current == "Storm" then
			flash()
			if rng:NextNumber() < 0.5 then
				task.wait(0.15)
				flash() -- Doppelblitz
			end
		end
	end
end

local function apply(id)
	local look = LOOKS[id] or LOOKS.Clear
	if id ~= "Clear" and not saved then
		saved = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime }
	end
	current = id

	TweenService:Create(tint, FADE, {
		TintColor = look.Tint,
		Saturation = look.Saturation,
		Contrast = look.Contrast,
		Brightness = look.Brightness,
	}):Play()

	if saved then
		local goal = { Brightness = saved.Brightness * look.Light }
		if look.Night then
			goal.ClockTime = 23.9
		else
			if Lighting.ClockTime > 23 and saved.ClockTime < 23 then
				Lighting.ClockTime = 0 -- nach der Nacht über den Morgen zurück zum Tag
			end
			goal.ClockTime = saved.ClockTime
		end
		TweenService:Create(Lighting, FADE, goal):Play()
	end

	local active = {}
	for _, name in ipairs(USES[id] or {}) do
		active[name] = true
	end
	anyActive = next(active) ~= nil
	emitters.Rain.Rate = id == "Storm" and 800 or 500
	for name, e in pairs(emitters) do
		e.Enabled = active[name] == true
	end

	stormToken += 1
	if id == "Storm" then
		task.spawn(lightningLoop, stormToken)
	end
end

workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	apply(workspace:GetAttribute("Weather") or "Clear")
end)
apply(workspace:GetAttribute("Weather") or "Clear")
