-- Theme.lua (ModuleScript, nur Client)
-- EIN Stil für die ganze Oberfläche (orientiert an großen Simulator-Spielen):
--   dunkle Flächen, dicke dunkle Umrandung, kräftige Farben,
--   "dicke" Knöpfe mit dunklerer Unterkante (3D), weiße Schrift mit Umriss.
--
-- Bildschirm-Zonen (damit sich nichts überlappt):
--   oben links     Coins / Milch            (HUD)
--   links Mitte    3 Knöpfe: Karte, Kühe, Bonus (HUD)
--   oben Mitte     Meldungen                (HUD)
--   unten Mitte    Hotbar                   (InventoryClient)
--   über Hotbar    Hinweis-Leiste           (Inventar-Platzieren, Tutorial)
--   unten rechts   VERKAUFEN                (HUD)
--   Mitte          immer nur EIN Fenster, Hintergrund abgedunkelt (Theme.window)

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(32, 36, 54),
	PanelLight = Color3.fromRGB(46, 52, 76),
	Card = Color3.fromRGB(54, 61, 88),
	Outline = Color3.fromRGB(14, 15, 24),
	Text = Color3.new(1, 1, 1),
	SubText = Color3.fromRGB(192, 200, 222),
	Green = Color3.fromRGB(80, 200, 90),
	Blue = Color3.fromRGB(70, 150, 245),
	Red = Color3.fromRGB(232, 72, 72),
	Orange = Color3.fromRGB(250, 158, 45),
	Gold = Color3.fromRGB(255, 205, 50),
	Pink = Color3.fromRGB(236, 100, 160),
	Teal = Color3.fromRGB(50, 190, 165),
	Grey = Color3.fromRGB(96, 104, 128),
}

Theme.Font = Enum.Font.FredokaOne -- Überschriften, Knöpfe, Zahlen
Theme.BodyFont = Enum.Font.GothamBold -- kleinere Texte

------------------------------------------------------------------------
-- Grundbausteine
------------------------------------------------------------------------
function Theme.zOf(parent)
	return (parent and parent:IsA("GuiObject")) and parent.ZIndex or 1
end

function Theme.darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.35)
end

function Theme.corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius or 12)
	c.Parent = object
	return c
end

-- Umrandung der Fläche
function Theme.border(object, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness or 3
	s.Color = color or Theme.Colors.Outline
	s.Transparency = transparency or 0
	s.Parent = object
	return s
end

-- Umriss um Schrift
function Theme.textOutline(label, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Thickness = thickness or 2
	s.Color = Theme.Colors.Outline
	s.Parent = label
	return s
end

-- Text. props.Outline = Dicke des Schrift-Umrisses (0 = keiner)
function Theme.label(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextSize = 18
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = Theme.zOf(parent)
	local outline = props.Outline
	for key, value in pairs(props) do
		if key ~= "Outline" then
			label[key] = value
		end
	end
	if outline ~= 0 then
		Theme.textOutline(label, outline or 2)
	end
	label.Parent = parent
	return label
end

-- dunkle Fläche mit Umrandung
function Theme.panel(parent, props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BorderSizePixel = 0
	frame.ZIndex = Theme.zOf(parent)
	local radius, outline = props.Radius, props.Outline
	for key, value in pairs(props) do
		if key ~= "Radius" and key ~= "Outline" then
			frame[key] = value
		end
	end
	Theme.corner(frame, radius or 14)
	if outline ~= 0 then
		Theme.border(frame, outline or 3)
	end
	frame.Parent = parent
	return frame
end

-- "Dicker" Knopf: Unterkante in dunklerer Farbe, Glanzstreifen oben, Text mit Umriss.
-- Gibt (TextButton, Halter, setColor) zurück. Size/Position/AnchorPoint/LayoutOrder gelten für den Halter.
-- setColor(farbe) färbt den Knopf später um (z.B. grau = nicht verfügbar).
function Theme.button(parent, props)
	local color = props.Color or Theme.Colors.Green
	local lipHeight = props.Lip or 5

	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Button"
	holder.BackgroundTransparency = 1
	holder.Size = props.Size or UDim2.fromOffset(140, 46)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.ZIndex = Theme.zOf(parent)
	holder.Parent = parent

	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.Size = UDim2.fromScale(1, 1)
	lip.BackgroundColor3 = Theme.darken(color, 0.4)
	lip.BorderSizePixel = 0
	lip.ZIndex = holder.ZIndex
	lip.Parent = holder
	Theme.corner(lip, props.Radius or 12)
	local lipStroke = Theme.border(lip, 3)

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.AutoButtonColor = false
	face.Size = UDim2.new(1, 0, 1, -lipHeight)
	face.BackgroundColor3 = color
	face.BorderSizePixel = 0
	face.Font = props.Font or Theme.Font
	face.TextSize = props.TextSize or 20
	face.TextColor3 = Theme.Colors.Text
	face.Text = props.Text or ""
	face.ZIndex = holder.ZIndex + 1
	face.Parent = holder
	Theme.corner(face, props.Radius or 12)
	Theme.textOutline(face, 2)

	-- Glanzstreifen
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 3)
	shine.Size = UDim2.new(1, -10, 0.38, 0)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.82
	shine.BorderSizePixel = 0
	shine.ZIndex = face.ZIndex
	shine.Parent = face
	Theme.corner(shine, props.Radius and math.max(props.Radius - 3, 2) or 9)

	-- Drücken: Fläche sinkt auf die Unterkante
	face.MouseButton1Down:Connect(function()
		face.Position = UDim2.fromOffset(0, lipHeight - 1)
	end)
	local function release()
		face.Position = UDim2.new()
	end
	face.MouseButton1Up:Connect(release)
	face.MouseLeave:Connect(release)

	-- Farbe später ändern (z.B. ausgegraut). Achtung: eigene Funktionen darf man NICHT
	-- an Roblox-Objekte hängen (holder.SetColor = ... wirft einen Fehler) -> eigene Funktion zurückgeben.
	local function setColor(newColor)
		face.BackgroundColor3 = newColor
		lip.BackgroundColor3 = Theme.darken(newColor, 0.4)
	end
	lipStroke.Name = "Outline"
	return face, holder, setColor
end

-- kleines Schild (z.B. Seltenheit): farbiger Hintergrund, dunkle Schrift
function Theme.tag(parent, props)
	local tag = Theme.label(parent, {
		Name = props.Name or "Tag",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = UDim2.fromOffset(0, props.Height or 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = props.Color,
		Font = Theme.BodyFont,
		TextSize = props.TextSize or 12,
		TextColor3 = Theme.Colors.Outline,
		Text = props.Text,
		Outline = 0,
	})
	Theme.corner(tag, 10)
	Theme.border(tag, 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = tag
	return tag
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
	local coin = dot(parent, UDim2.fromOffset(size, size), position, Theme.Colors.Gold, z)
	Theme.border(coin, 3)
	local inner = dot(coin, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 225, 110), z + 1)
	Theme.label(inner, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font,
		TextSize = math.floor(size * 0.5),
		TextColor3 = Color3.fromRGB(190, 130, 20),
		Text = "C",
		Outline = 0,
		ZIndex = z + 2,
	})
	return coin
end

-- Milchtüte: weißer Körper mit blauem Dach-Streifen und blauem Tropfen
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
	body.BackgroundColor3 = Color3.fromRGB(250, 250, 255)
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = z
	body.Parent = holder
	Theme.corner(body, math.max(3, math.floor(size / 8)))
	Theme.border(body, 2)
	local roof = Instance.new("Frame")
	roof.Size = UDim2.fromScale(1, 0.28)
	roof.BackgroundColor3 = Theme.Colors.Blue
	roof.BorderSizePixel = 0
	roof.ZIndex = z + 1
	roof.Parent = body
	local drop = dot(body, UDim2.fromScale(0.42, 0.3), UDim2.fromScale(0.5, 0.64), Theme.Colors.Blue, z + 1)
	drop.BackgroundTransparency = 0.15
	return holder
end

-- Kuhkopf: Kreis in Fellfarbe, Fleck, rosa Schnauze, Augen
function Theme.cowIcon(parent, size, position, bodyColor, spotColor, transparency)
	local z = Theme.zOf(parent) + 1
	local head = dot(parent, UDim2.fromOffset(size, size), position, bodyColor, z)
	head.BackgroundTransparency = transparency or 0
	Theme.border(head, math.max(2, math.floor(size / 16)))
	if spotColor then
		local spot = dot(head, UDim2.fromScale(0.4, 0.34), UDim2.fromScale(0.3, 0.3), spotColor, z + 1)
		spot.BackgroundTransparency = transparency or 0
	end
	for _, x in ipairs({ 0.36, 0.64 }) do
		dot(head, UDim2.fromScale(0.13, 0.15), UDim2.fromScale(x, 0.45), Theme.Colors.Outline, z + 2)
	end
	local snout = dot(head, UDim2.fromScale(0.56, 0.3), UDim2.fromScale(0.5, 0.74), Color3.fromRGB(255, 175, 190), z + 2)
	for _, x in ipairs({ 0.33, 0.67 }) do
		dot(snout, UDim2.fromScale(0.13, 0.32), UDim2.fromScale(x, 0.5), Color3.fromRGB(190, 90, 110), z + 3)
	end
	return head
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
-- Fenster: immer nur eins offen, Hintergrund abgedunkelt
------------------------------------------------------------------------
local windows = {}

function Theme.closeAllWindows(except)
	for _, win in ipairs(windows) do
		if win ~= except and win:IsOpen() then
			win:Close()
		end
	end
end

-- props: Name, Title, Color, Size (Vector2), OnClose
-- Gibt ein Objekt zurück: { Root, Body, Open(), Close(), IsOpen(), SetTitle(text), SetColor(color) }
function Theme.window(gui, props)
	local size = props.Size or Vector2.new(720, 480)
	local win = {}

	local overlay = Instance.new("TextButton")
	overlay.Name = (props.Name or "Window") .. "Dim"
	overlay.AutoButtonColor = false
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromOffset(0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 20
	overlay.Parent = gui

	local root = Theme.panel(gui, {
		Name = props.Name or "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		ZIndex = 21,
		Radius = 18,
		Outline = 4,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = props.Color or Theme.Colors.Blue
	header.BorderSizePixel = 0
	header.ZIndex = root.ZIndex
	header.Parent = root
	Theme.corner(header, 18)
	local headerFill = Instance.new("Frame") -- untere Ecken gerade
	headerFill.Position = UDim2.new(0, 0, 1, -18)
	headerFill.Size = UDim2.new(1, 0, 0, 18)
	headerFill.BackgroundColor3 = header.BackgroundColor3
	headerFill.BorderSizePixel = 0
	headerFill.ZIndex = root.ZIndex
	headerFill.Parent = header
	local headerLine = Instance.new("Frame")
	headerLine.Position = UDim2.fromScale(0, 1)
	headerLine.Size = UDim2.new(1, 0, 0, 4)
	headerLine.BackgroundColor3 = Theme.Colors.Outline
	headerLine.BorderSizePixel = 0
	headerLine.ZIndex = root.ZIndex
	headerLine.Parent = header

	local title = Theme.label(header, {
		Name = "Title",
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -100, 1, 0),
		TextSize = 32,
		Text = props.Title or "",
		Outline = 3,
	})

	local closeButton = Theme.button(header, {
		Name = "Close",
		Text = "X",
		Color = Theme.Colors.Red,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		TextSize = 24,
		Radius = 10,
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(18, 78)
	body.Size = UDim2.new(1, -36, 1, -96)
	body.BackgroundTransparency = 1
	body.ZIndex = root.ZIndex
	body.Parent = root

	local function fit()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		return math.min(1.1, (viewport.X - 40) / size.X, (viewport.Y - 90) / size.Y)
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
		scale.Scale = target * 0.88
		TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	function win:Close()
		if not root.Visible then
			return
		end
		root.Visible = false
		overlay.Visible = false
		overlay.BackgroundTransparency = 1
		if props.OnClose then
			props.OnClose()
		end
	end
	function win:SetTitle(text)
		title.Text = text
	end
	function win:SetColor(color)
		header.BackgroundColor3 = color
		headerFill.BackgroundColor3 = color
	end

	closeButton.Activated:Connect(function()
		win:Close()
	end)
	overlay.Activated:Connect(function()
		win:Close()
	end)

	win.Root = root
	win.Body = body
	win.Header = header
	table.insert(windows, win)
	return win
end

return Theme
