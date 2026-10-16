-- Theme.lua (ModuleScript, nur Client)
-- EIN Stil für die ganze Oberfläche:
--   tiefes Marineblau für Flächen, Creme/Off-White für Schrift, Grasgrün für Haupt-Aktionen,
--   Himmelblau als Akzent, Gold NUR für Coins und seltene Belohnungen.
--   Abgerundete Ecken, dünne einheitliche Umrandung, weiche Schatten, kurze Tweens.
--
-- Bildschirm-Zonen (damit sich nichts überlappt):
--   oben links     Coins / Milch            (HUD)
--   links Mitte    3 Knöpfe: Karte, Kühe, Bonus (HUD)
--   oben Mitte     Meldungen                (HUD)
--   unten Mitte    Hotbar                   (InventoryClient)
--   über Hotbar    Hinweis-Leiste           (Inventar-Platzieren, Tutorial)
--   unten rechts   VERKAUFEN                (HUD)
--   Mitte          immer nur EIN Fenster, Hintergrund abgedunkelt (Theme.window)
--
-- Bausteine (alle liefern ihre Objekte zurück):
--   Theme.screenGui        ScreenGui mit Safe-Area
--   Theme.panel/label/tag  Flächen, Text, Abzeichen
--   Theme.button           Knopf (+ primaryButton / secondaryButton / destructiveButton)
--   Theme.window           Fenster mit Kopfzeile + Schließen-Knopf
--   Theme.progressBar      Fortschrittsbalken
--   Theme.rarityBadge      Seltenheits-Abzeichen
--   Theme.cowCard          Kuh-Karte
--   Theme.createNotifier   Meldungen oben Mitte
--   Theme.coinIcon/milkIcon/cowIcon  gezeichnete Symbole

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = {}

------------------------------------------------------------------------
-- Design-Werte
------------------------------------------------------------------------
Theme.Colors = {
	-- Flächen (Marineblau)
	Deep = Color3.fromRGB(14, 22, 42), -- tiefste Fläche (Kopfzeile, Taschen)
	Panel = Color3.fromRGB(24, 36, 64), -- Fenster, Leisten
	PanelLight = Color3.fromRGB(34, 50, 84), -- Zeilen, Eingaben
	Card = Color3.fromRGB(40, 58, 94), -- Karten
	Outline = Color3.fromRGB(10, 16, 32), -- dunkle Tinte (Schrift auf hellen Abzeichen)
	Line = Color3.fromRGB(72, 96, 148), -- dünne Umrandung

	-- Schrift / helle Flächen (Creme)
	Cream = Color3.fromRGB(250, 244, 228),
	Text = Color3.fromRGB(250, 244, 228),
	SubText = Color3.fromRGB(196, 198, 190),

	-- Aktionen & Akzente
	Green = Color3.fromRGB(70, 158, 76), -- Gras: Haupt-Aktionen
	Blue = Color3.fromRGB(78, 164, 232), -- Himmelblau: Akzent
	Steel = Color3.fromRGB(62, 86, 134), -- zweite Aktion
	Red = Color3.fromRGB(208, 78, 78), -- Schließen / Abbrechen
	Gold = Color3.fromRGB(244, 192, 64), -- NUR Coins und seltene Belohnungen
	Orange = Color3.fromRGB(226, 148, 66),
	Pink = Color3.fromRGB(214, 118, 160),
	Teal = Color3.fromRGB(70, 176, 160),
	Grey = Color3.fromRGB(88, 100, 128), -- nicht verfügbar
}

Theme.Font = Enum.Font.FredokaOne -- Überschriften, Knöpfe, Zahlen
Theme.BodyFont = Enum.Font.GothamBold -- kleinere Texte
Theme.TextFont = Enum.Font.GothamMedium -- Fließtext

Theme.TextSize = { Title = 30, Heading = 22, Body = 16, Small = 13, Tiny = 11 }
Theme.Spacing = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }
Theme.Radius = { S = 8, M = 12, L = 16, XL = 20 }
Theme.Stroke = { Thin = 1.5, Normal = 2 }
Theme.Shadow = { Transparency = 0.8, Offset = 5 }
Theme.Time = { Fast = 0.12, Normal = 0.2, Slow = 0.35 }

local Colors = Theme.Colors

------------------------------------------------------------------------
-- Grundbausteine
------------------------------------------------------------------------
function Theme.zOf(parent)
	return (parent and parent:IsA("GuiObject")) and parent.ZIndex or 1
end

function Theme.darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.35)
end

function Theme.lighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.15)
end

-- Kurzer, glatter Tween (Standard 0.2 s)
function Theme.tween(object, props, duration, style, direction)
	local tween = TweenService:Create(
		object,
		TweenInfo.new(duration or Theme.Time.Normal, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

function Theme.corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius or Theme.Radius.M)
	c.Parent = object
	return c
end

-- dünne Umrandung der Fläche
function Theme.border(object, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness or Theme.Stroke.Thin
	s.Color = color or Colors.Line
	s.Transparency = transparency or 0
	s.Parent = object
	return s
end

-- sehr dünner, weicher Umriss um Schrift (nur wo der Hintergrund wechselt, z.B. auf der Karte)
function Theme.textOutline(label, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Thickness = math.min(thickness or 1, 1.5)
	s.Color = Colors.Outline
	s.Transparency = 0.35
	s.Parent = label
	return s
end

function Theme.padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

-- Text. props.Outline > 0 = dünner Umriss (Standard: keiner)
function Theme.label(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextSize = Theme.TextSize.Body
	label.TextColor3 = Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = Theme.zOf(parent)
	local outline = props.Outline
	for key, value in pairs(props) do
		if key ~= "Outline" then
			label[key] = value
		end
	end
	if outline and outline > 0 then
		Theme.textOutline(label, outline)
	end
	label.Parent = parent
	return label
end

-- Marineblaue Fläche mit dünner Umrandung
-- props.Radius, props.Outline (Dicke, 0 = keine), props.OutlineColor
function Theme.panel(parent, props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Colors.Panel
	frame.BorderSizePixel = 0
	frame.ZIndex = Theme.zOf(parent)
	local radius, outline, outlineColor = props.Radius, props.Outline, props.OutlineColor
	for key, value in pairs(props) do
		if key ~= "Radius" and key ~= "Outline" and key ~= "OutlineColor" then
			frame[key] = value
		end
	end
	Theme.corner(frame, radius or Theme.Radius.L)
	if outline ~= 0 then
		Theme.border(frame, outline or Theme.Stroke.Thin, outlineColor)
	end
	frame.Parent = parent
	return frame
end

-- Weicher Schatten: zwei versetzte, durchsichtige Flächen HINTER den Inhalt.
-- holder = durchsichtiger Rahmen, der die Fläche und ihren Schatten gemeinsam trägt
-- (Kinder werden immer über dem Elternobjekt gezeichnet, deshalb ein eigener Halter).
function Theme.softShadow(holder, radius, offset)
	offset = offset or Theme.Shadow.Offset
	local z = holder.ZIndex
	for i, factor in ipairs({ 1, 0.55 }) do
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow" .. i
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.Position = UDim2.new(0.5, 0, 0.5, offset * factor + 2)
		shadow.Size = UDim2.new(1, i * 6 - 6, 1, i * 6 - 6)
		shadow.BackgroundColor3 = Color3.new(0, 0, 0)
		shadow.BackgroundTransparency = Theme.Shadow.Transparency + (i - 1) * 0.08
		shadow.BorderSizePixel = 0
		shadow.ZIndex = z
		shadow.Parent = holder
		Theme.corner(shadow, (radius or Theme.Radius.L) + i * 2)
	end
end

-- ScreenGui mit Safe-Area (Notch, Systemleisten). Voll-Bild-Flächen: ignoreInset = true
function Theme.screenGui(name, displayOrder, ignoreInset)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 1
	-- Standard von Roblox = CoreUISafe (hält Abstand zu Notch, Systemleisten und Roblox-Menü)
	if ignoreInset then
		gui.ScreenInsets = Enum.ScreenInsets.None
	end
	return gui
end

------------------------------------------------------------------------
-- Knöpfe
------------------------------------------------------------------------
-- Auswahlrahmen für Controller (A-Knopf-Auswahl): sichtbarer Himmelblau-Rand
local selectionImage = Instance.new("Frame")
selectionImage.Name = "CowFarmSelection"
selectionImage.BackgroundTransparency = 1
selectionImage.Size = UDim2.fromScale(1, 1)
Theme.corner(selectionImage, Theme.Radius.M)
do
	local s = Instance.new("UIStroke")
	s.Color = Colors.Blue
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = selectionImage
end

-- Knopf mit dünner Unterkante. Zustände: normal / Hover / gedrückt / ausgegraut (kurze Tweens).
-- props: Text, Color, Size, Position, AnchorPoint, LayoutOrder, Radius, Lip, TextSize, Font, Name
-- Gibt (TextButton, Halter, setColor, api) zurück. Size/Position/AnchorPoint/LayoutOrder gelten für den Halter.
--   setColor(farbe)        färbt den Knopf um
--   api.SetDisabled(bool)  nur OPTISCH ausgegraut – der Klick wird weiterhin gemeldet,
--                          damit der Aufrufer eine Erklärung zeigen kann ("Nicht genug Coins")
--   api.SetText(text)
function Theme.button(parent, props)
	local baseColor = props.Color or Colors.Green
	local lipHeight = props.Lip or 4
	local radius = props.Radius or Theme.Radius.M

	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Button"
	holder.BackgroundTransparency = 1
	holder.Size = props.Size or UDim2.fromOffset(140, 44)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.ZIndex = Theme.zOf(parent)
	holder.Parent = parent

	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.Size = UDim2.fromScale(1, 1)
	lip.BackgroundColor3 = Theme.darken(baseColor, 0.45)
	lip.BorderSizePixel = 0
	lip.ZIndex = holder.ZIndex
	lip.Parent = holder
	Theme.corner(lip, radius)

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.AutoButtonColor = false
	face.Size = UDim2.new(1, 0, 1, -lipHeight)
	face.BackgroundColor3 = baseColor
	face.BorderSizePixel = 0
	face.Font = props.Font or Theme.Font
	face.TextSize = props.TextSize or Theme.TextSize.Body + 2
	face.TextColor3 = Colors.Text
	face.Text = props.Text or ""
	face.ZIndex = holder.ZIndex + 1
	face.SelectionImageObject = selectionImage
	face.Parent = holder
	Theme.corner(face, radius)
	Theme.textOutline(face, 1)
	local faceStroke = Theme.border(face, Theme.Stroke.Thin, Theme.darken(baseColor, 0.4), 0.2)

	-- Glanzstreifen (dezent)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 3)
	shine.Size = UDim2.new(1, -12, 0.34, 0)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.88
	shine.BorderSizePixel = 0
	shine.ZIndex = face.ZIndex
	shine.Parent = face
	Theme.corner(shine, math.max(radius - 3, 2))

	local state = { Color = baseColor, Disabled = false, Hover = false, Down = false }

	local function render()
		local shown = state.Disabled and Colors.Grey or state.Color
		if state.Hover and not state.Disabled then
			shown = Theme.lighten(shown, 0.12)
		end
		Theme.tween(face, { BackgroundColor3 = shown }, Theme.Time.Fast)
		Theme.tween(lip, { BackgroundColor3 = Theme.darken(shown, 0.45) }, Theme.Time.Fast)
		Theme.tween(faceStroke, { Color = Theme.darken(shown, 0.4) }, Theme.Time.Fast)
		Theme.tween(face, { TextTransparency = state.Disabled and 0.35 or 0 }, Theme.Time.Fast)
		-- gedrückt: Fläche sinkt auf die Unterkante
		local target = (state.Down and not state.Disabled) and UDim2.fromOffset(0, lipHeight - 1) or UDim2.new()
		Theme.tween(face, { Position = target }, state.Down and 0.04 or Theme.Time.Fast)
	end

	face.MouseEnter:Connect(function()
		state.Hover = true
		render()
	end)
	face.MouseLeave:Connect(function()
		state.Hover = false
		state.Down = false
		render()
	end)
	face.SelectionGained:Connect(function()
		state.Hover = true
		render()
	end)
	face.SelectionLost:Connect(function()
		state.Hover = false
		render()
	end)
	face.MouseButton1Down:Connect(function()
		state.Down = true
		render()
	end)
	face.MouseButton1Up:Connect(function()
		state.Down = false
		render()
	end)

	-- Farbe später ändern. Achtung: eigene Funktionen darf man NICHT an Roblox-Objekte
	-- hängen (holder.SetColor = ... wirft einen Fehler) -> eigene Funktionen zurückgeben.
	local function setColor(newColor)
		state.Color = newColor
		render()
	end

	local api = {
		Face = face,
		Holder = holder,
		SetColor = setColor,
		SetDisabled = function(disabled)
			state.Disabled = disabled == true
			render()
		end,
		SetText = function(text)
			face.Text = text
		end,
	}
	return face, holder, setColor, api
end

local function variantButton(color)
	return function(parent, props)
		local merged = table.clone(props or {})
		merged.Color = merged.Color or color
		return Theme.button(parent, merged)
	end
end

Theme.primaryButton = variantButton(Colors.Green) -- Haupt-Aktion (Kaufen, Verkaufen, Melken)
Theme.secondaryButton = variantButton(Colors.Steel) -- Nebenaktion (Ins Lager, Zurück)
Theme.destructiveButton = variantButton(Colors.Red) -- Schließen, Abbrechen

------------------------------------------------------------------------
-- Abzeichen, Balken, Karten
------------------------------------------------------------------------
-- kleines Schild: farbiger Hintergrund, dunkle Schrift
function Theme.tag(parent, props)
	local tag = Theme.label(parent, {
		Name = props.Name or "Tag",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = UDim2.fromOffset(0, props.Height or 20),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 0,
		BackgroundColor3 = props.Color,
		Font = Theme.BodyFont,
		TextSize = props.TextSize or Theme.TextSize.Small - 1,
		TextColor3 = Colors.Outline,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = props.Text,
	})
	Theme.corner(tag, UDim.new(0, 10))
	local padding = Theme.padding(tag, 0)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	return tag
end

-- Seltenheits-Abzeichen. info = CowData.Rarities[...] (DisplayName, UiColor, IsSpecial)
function Theme.rarityBadge(parent, info, props)
	props = props or {}
	return Theme.tag(parent, {
		Name = props.Name or "RarityBadge",
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Height = props.Height,
		TextSize = props.TextSize,
		Color = info.UiColor,
		Text = (info.IsSpecial and "★ " or "") .. info.DisplayName,
	})
end

-- Fortschrittsbalken. props: Size, Position, AnchorPoint, Color, Height, Text (Standard: kein Text)
-- Gibt { Root, Fill, SetRatio(r, animiert), SetColor(c), SetText(t) } zurück
function Theme.progressBar(parent, props)
	local root = Theme.panel(parent, {
		Name = props.Name or "ProgressBar",
		Size = props.Size or UDim2.new(1, 0, 0, props.Height or 18),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = Colors.Deep,
		ClipsDescendants = true,
		Radius = UDim.new(1, 0),
	})
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.Color or Colors.Green
	fill.BorderSizePixel = 0
	fill.ZIndex = root.ZIndex
	fill.Parent = root
	Theme.corner(fill, UDim.new(1, 0))
	local text = Theme.label(root, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.BodyFont,
		TextSize = Theme.TextSize.Small,
		Text = props.Text or "",
		ZIndex = root.ZIndex + 1,
		Outline = 1,
	})

	local bar = { Root = root, Fill = fill }
	function bar.SetRatio(ratio, animated)
		local size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		if animated == false then
			fill.Size = size
		else
			Theme.tween(fill, { Size = size }, Theme.Time.Normal)
		end
	end
	function bar.SetColor(color)
		Theme.tween(fill, { BackgroundColor3 = color }, Theme.Time.Fast)
	end
	function bar.SetText(value)
		text.Text = value
	end
	return bar
end

------------------------------------------------------------------------
-- Gezeichnete Symbole (statt Emojis)
------------------------------------------------------------------------
local function dot(parent, size, position, color, z)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	Theme.corner(f, UDim.new(1, 0))
	return f
end

-- Münze: Goldkreis mit Rand und "C"
function Theme.coinIcon(parent, size, position)
	local z = Theme.zOf(parent) + 1
	local coin = dot(parent, UDim2.fromOffset(size, size), position, Colors.Gold, z)
	Theme.border(coin, Theme.Stroke.Normal, Theme.darken(Colors.Gold, 0.55))
	local inner = dot(coin, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Theme.lighten(Colors.Gold, 0.3), z + 1)
	Theme.label(inner, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font,
		TextSize = math.floor(size * 0.5),
		TextColor3 = Theme.darken(Colors.Gold, 0.45),
		Text = "C",
		ZIndex = z + 2,
	})
	return coin
end

-- Milchtüte: cremeweißer Körper mit blauem Dach-Streifen und blauem Tropfen
function Theme.milkIcon(parent, size, position)
	local z = Theme.zOf(parent) + 1
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.Position = position
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(0.62, 0.86)
	body.BackgroundColor3 = Colors.Cream
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = z
	body.Parent = holder
	Theme.corner(body, math.max(3, math.floor(size / 8)))
	Theme.border(body, Theme.Stroke.Thin, Colors.Outline)
	local roof = Instance.new("Frame")
	roof.Size = UDim2.fromScale(1, 0.28)
	roof.BackgroundColor3 = Colors.Blue
	roof.BorderSizePixel = 0
	roof.ZIndex = z + 1
	roof.Parent = body
	local drop = dot(body, UDim2.fromScale(0.42, 0.3), UDim2.fromScale(0.5, 0.64), Colors.Blue, z + 1)
	drop.BackgroundTransparency = 0.15
	return holder
end

-- Kuhkopf: Kreis in Fellfarbe, Fleck, rosa Schnauze, Augen
function Theme.cowIcon(parent, size, position, bodyColor, spotColor, transparency)
	local z = Theme.zOf(parent) + 1
	local head = dot(parent, UDim2.fromOffset(size, size), position, bodyColor, z)
	head.BackgroundTransparency = transparency or 0
	Theme.border(head, math.max(1.5, math.floor(size / 20)), Colors.Outline)
	if spotColor then
		local spot = dot(head, UDim2.fromScale(0.4, 0.34), UDim2.fromScale(0.3, 0.3), spotColor, z + 1)
		spot.BackgroundTransparency = transparency or 0
	end
	for _, x in ipairs({ 0.36, 0.64 }) do
		dot(head, UDim2.fromScale(0.13, 0.15), UDim2.fromScale(x, 0.45), Colors.Outline, z + 2)
	end
	local snout = dot(head, UDim2.fromScale(0.56, 0.3), UDim2.fromScale(0.5, 0.74), Color3.fromRGB(255, 175, 190), z + 2)
	for _, x in ipairs({ 0.33, 0.67 }) do
		dot(snout, UDim2.fromScale(0.13, 0.32), UDim2.fromScale(x, 0.5), Color3.fromRGB(190, 90, 110), z + 3)
	end
	return head
end

-- Kuh-Karte: Navy-Karte mit Seltenheits-Streifen, Kuhkopf, Name und Abzeichen.
-- props: Info (CowData.Rarities[...]), Name, Size, Position, LayoutOrder, BodyColor, SpotColor
-- Gibt (card, contentY) zurück: unterhalb von contentY ist Platz für eigene Inhalte
function Theme.cowCard(parent, props)
	local info = props.Info
	local card = Theme.panel(parent, {
		Name = props.Name or "CowCard",
		LayoutOrder = props.LayoutOrder or 0,
		Size = props.Size or UDim2.fromOffset(220, 150),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = Colors.Card,
		Radius = Theme.Radius.M,
	})
	local strip = Instance.new("Frame")
	strip.Name = "RarityStrip"
	strip.Size = UDim2.new(1, 0, 0, 5)
	strip.BackgroundColor3 = info.UiColor
	strip.BorderSizePixel = 0
	strip.ZIndex = card.ZIndex
	strip.Parent = card
	Theme.corner(strip, 3)

	Theme.cowIcon(card, 46, UDim2.fromOffset(36, 42), props.BodyColor or info.Color, props.SpotColor or info.SpotColor,
		info.Transparency and 0.3 or 0)
	Theme.label(card, {
		Name = "CowName",
		Position = UDim2.fromOffset(68, 14),
		Size = UDim2.new(1, -76, 0, 24),
		TextSize = Theme.TextSize.Heading - 2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = props.CowName or "",
	})
	Theme.rarityBadge(card, info, { Position = UDim2.fromOffset(68, 42) })
	return card, 72
end

------------------------------------------------------------------------
-- Größe an den Bildschirm anpassen (Basis 1280 x 720)
------------------------------------------------------------------------
local scalers = {}

local function screenScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1.15)
end

-- Hängt eine UIScale an (skaliert um den AnchorPoint des Objekts)
function Theme.autoScale(guiObject, factor)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Scale = screenScale() * (factor or 1)
	scale.Parent = guiObject
	table.insert(scalers, { Scale = scale, Factor = factor or 1 })
	return scale
end

local function updateScalers()
	local s = screenScale()
	for i = #scalers, 1, -1 do
		local entry = scalers[i]
		if entry.Scale.Parent then
			entry.Scale.Scale = s * entry.Factor
		else
			table.remove(scalers, i)
		end
	end
end

task.spawn(function()
	while not workspace.CurrentCamera do
		task.wait()
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScalers)
	updateScalers()
end)

------------------------------------------------------------------------
-- Meldungen (oben Mitte): max. N gleichzeitig, kurze Ein-/Ausblendung
------------------------------------------------------------------------
local TOAST_COLORS = {
	success = Colors.Green,
	error = Colors.Red,
	rare = Colors.Gold, -- seltene Belohnungen
	info = Colors.Blue,
}

-- Gibt eine Funktion show(text, kind) zurück. kind = info / success / error / rare
function Theme.createNotifier(gui, opts)
	opts = opts or {}
	local maxToasts = opts.MaxToasts or 3
	local lifetime = opts.Time or 2.5

	local container = Instance.new("Frame")
	container.Name = "Toasts"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 10)
	container.Size = UDim2.fromOffset(460, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.Spacing.S - 2)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
	Theme.autoScale(container)

	local counter = 0
	local active = {}

	local function remove(toast)
		local index = table.find(active, toast)
		if index then
			table.remove(active, index)
		end
		toast:Destroy()
	end

	return function(message, kind)
		counter += 1
		local accent = TOAST_COLORS[kind] or Colors.Blue

		local toast = Theme.panel(container, {
			Name = "Toast",
			LayoutOrder = counter,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Colors.Panel,
			OutlineColor = accent,
			Radius = Theme.Radius.M,
		})
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(440, math.huge)
		limit.MinSize = Vector2.new(0, 38)
		limit.Parent = toast
		local accentBar = Instance.new("Frame")
		accentBar.Name = "Accent"
		accentBar.Size = UDim2.new(0, 6, 1, 0)
		accentBar.BackgroundColor3 = accent
		accentBar.BorderSizePixel = 0
		accentBar.ZIndex = toast.ZIndex
		accentBar.Parent = toast
		Theme.corner(accentBar, 3)

		local text = Theme.label(toast, {
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Font = Theme.BodyFont,
			TextSize = Theme.TextSize.Body,
			TextWrapped = true,
			Text = tostring(message),
			TextTransparency = 1,
		})
		local textLimit = Instance.new("UISizeConstraint")
		textLimit.MaxSize = Vector2.new(400, math.huge)
		textLimit.Parent = text
		local pad = Theme.padding(toast, 0)
		pad.PaddingLeft = UDim.new(0, 18)
		pad.PaddingRight = UDim.new(0, 14)
		pad.PaddingTop = UDim.new(0, 9)
		pad.PaddingBottom = UDim.new(0, 9)

		local scale = Instance.new("UIScale")
		scale.Scale = 0.85
		scale.Parent = toast
		Theme.tween(scale, { Scale = 1 }, Theme.Time.Normal, Enum.EasingStyle.Back)
		Theme.tween(text, { TextTransparency = 0 }, Theme.Time.Normal)

		table.insert(active, toast)
		if #active > maxToasts then
			remove(active[1])
		end

		task.delay(lifetime, function()
			if not toast.Parent then
				return
			end
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			if stroke then
				Theme.tween(stroke, { Transparency = 1 }, Theme.Time.Normal)
			end
			Theme.tween(text, { TextTransparency = 1 }, Theme.Time.Normal)
			Theme.tween(accentBar, { BackgroundTransparency = 1 }, Theme.Time.Normal)
			local fade = Theme.tween(toast, { BackgroundTransparency = 1 }, Theme.Time.Normal)
			fade.Completed:Wait()
			if toast.Parent then
				remove(toast)
			end
		end)
	end
end

------------------------------------------------------------------------
-- Fenster: immer nur eins offen, Hintergrund abgedunkelt
------------------------------------------------------------------------
local windows = {}
local BACK_ACTION = "CowFarmWindowBack"

function Theme.closeAllWindows(except)
	for _, win in ipairs(windows) do
		if win ~= except and win:IsOpen() then
			win:Close()
		end
	end
end

function Theme.isAnyWindowOpen()
	for _, win in ipairs(windows) do
		if win:IsOpen() then
			return true
		end
	end
	return false
end

-- Controller: B-Knopf schließt das offene Fenster (nur gebunden, solange eins offen ist)
local function updateBackBinding()
	if Theme.isAnyWindowOpen() then
		ContextActionService:BindActionAtPriority(BACK_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				Theme.closeAllWindows()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(BACK_ACTION)
	end
end

local function usingGamepad()
	local input = UserInputService:GetLastInputType()
	return input.Name:sub(1, 7) == "Gamepad"
end

-- props: Name, Title, Color (Akzentlinie), Size (Vector2), OnClose
-- Gibt ein Objekt zurück: { Root, Panel, Body, Header, Open(), Close(), IsOpen(), SetTitle(text), SetColor(color) }
-- Root = der Halter (das Tutorial prüft Root.Visible), Panel = die eigentliche Fläche.
function Theme.window(gui, props)
	local size = props.Size or Vector2.new(720, 480)
	local win = {}

	local overlay = Instance.new("TextButton")
	overlay.Name = (props.Name or "Window") .. "Dim"
	overlay.AutoButtonColor = false
	overlay.Selectable = false
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Colors.Outline
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 20
	overlay.Parent = gui

	-- Halter trägt Schatten + Fläche und wird skaliert
	local root = Instance.new("Frame")
	root.Name = props.Name or "Window"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 21
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	Theme.softShadow(root, Theme.Radius.XL)

	local panel = Theme.panel(root, {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		ZIndex = 22,
		Radius = Theme.Radius.XL,
		Outline = Theme.Stroke.Normal,
	})

	local HEADER = 58
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER)
	header.BackgroundColor3 = Colors.Deep
	header.BorderSizePixel = 0
	header.ZIndex = panel.ZIndex
	header.Parent = panel
	Theme.corner(header, Theme.Radius.XL)
	local headerFill = Instance.new("Frame") -- untere Ecken gerade
	headerFill.Position = UDim2.new(0, 0, 1, -Theme.Radius.XL)
	headerFill.Size = UDim2.new(1, 0, 0, Theme.Radius.XL)
	headerFill.BackgroundColor3 = header.BackgroundColor3
	headerFill.BorderSizePixel = 0
	headerFill.ZIndex = panel.ZIndex
	headerFill.Parent = header
	local accent = Instance.new("Frame") -- Akzentlinie unter der Kopfzeile
	accent.Name = "Accent"
	accent.Position = UDim2.fromScale(0, 1)
	accent.Size = UDim2.new(1, 0, 0, 3)
	accent.BackgroundColor3 = props.Color or Colors.Blue
	accent.BorderSizePixel = 0
	accent.ZIndex = panel.ZIndex
	accent.Parent = header

	local title = Theme.label(header, {
		Name = "Title",
		Position = UDim2.fromOffset(Theme.Spacing.XL, 0),
		Size = UDim2.new(1, -90, 1, 0),
		TextSize = Theme.TextSize.Title,
		Text = props.Title or "",
	})

	local closeFace = Theme.destructiveButton(header, {
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		TextSize = Theme.TextSize.Heading,
		Radius = 10,
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(Theme.Spacing.L + 2, HEADER + Theme.Spacing.L)
	body.Size = UDim2.new(1, -(Theme.Spacing.L + 2) * 2, 1, -(HEADER + Theme.Spacing.L * 2))
	body.BackgroundTransparency = 1
	body.ZIndex = panel.ZIndex
	body.Parent = panel

	-- Passt das Fenster in den sichtbaren Bereich (Safe-Area, Handy-Bildschirme)
	local function fit()
		local area = gui.AbsoluteSize
		if area.X < 10 or area.Y < 10 then
			local camera = workspace.CurrentCamera
			area = camera and camera.ViewportSize or Vector2.new(1280, 720)
		end
		return math.clamp(math.min(1.1, (area.X - 24) / size.X, (area.Y - 24) / size.Y), 0.4, 1.1)
	end

	function win:IsOpen()
		return root.Visible
	end
	function win:Open()
		if root.Visible then
			return
		end
		Theme.closeAllWindows(win)
		overlay.Visible = true
		root.Visible = true
		local target = fit()
		scale.Scale = target * 0.9
		Theme.tween(overlay, { BackgroundTransparency = 0.45 }, Theme.Time.Fast)
		Theme.tween(scale, { Scale = target }, Theme.Time.Normal, Enum.EasingStyle.Back)
		updateBackBinding()

		-- Controller: erstes Feld auswählen (die Seiten werden kurz nach dem Öffnen gebaut)
		if usingGamepad() then
			task.delay(0.3, function()
				if not root.Visible then
					return
				end
				local first = nil
				for _, descendant in ipairs(body:GetDescendants()) do
					if descendant:IsA("GuiButton") and descendant.Visible and descendant.Selectable then
						first = descendant
						break
					end
				end
				GuiService.SelectedObject = first or closeFace
			end)
		end
	end
	function win:Close()
		if not root.Visible then
			return
		end
		root.Visible = false
		overlay.Visible = false
		overlay.BackgroundTransparency = 1
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		updateBackBinding()
		if props.OnClose then
			props.OnClose()
		end
	end
	function win:SetTitle(text)
		title.Text = text
	end
	function win:SetColor(color)
		Theme.tween(accent, { BackgroundColor3 = color }, Theme.Time.Fast)
	end

	closeFace.Activated:Connect(function()
		win:Close()
	end)
	overlay.Activated:Connect(function()
		win:Close()
	end)

	win.Root = root
	win.Panel = panel
	win.Body = body
	win.Header = header
	table.insert(windows, win)
	return win
end

return Theme
