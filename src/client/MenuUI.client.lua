-- MenuUI.client.lua
-- Fenster, die sich öffnen, wenn man ein Shop-Gebäude anklickt (Server -> Remotes.OpenShop)
-- oder sie aus der Übersicht aufruft (UIBus.OpenPage):
--   Shop        – Common/Uncommon für Coins kaufen          (Gebäude "KUH-SHOP")
--   Kisten      – Kuh-Kisten für Coins oder Robux öffnen    (Gebäude "KISTEN")
--   Zucht       – zwei Kühe auswählen, Chancen, Zucht       (Gebäude "ZUCHT-STALL")
--   Tagesbonus  – Login-Streak und Belohnungen der 7 Tage
--   Auto-Melker – Gamepass kaufen                           (Gebäude "AUTO-MELKER")
-- Stil und Bausteine kommen aus Theme.lua (Fenster, Knöpfe, Karten, Abzeichen, Balken).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIBus = require(script.Parent:WaitForChild("UIBus"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local player = Players.LocalPlayer
local Colors = Theme.Colors

local ERROR_COLOR = Color3.fromRGB(255, 150, 140)
local OK_COLOR = Color3.fromRGB(140, 214, 124)

local inventory = nil -- letzte Antwort von GetInventory
local serverTimeOffset = 0
local currentPage = nil

------------------------------------------------------------------------
-- kleine UI-Helfer (alles baut auf Theme auf)
------------------------------------------------------------------------
local function label(parent, props)
	local merged = {
		Font = Theme.TextFont,
		TextSize = Theme.TextSize.Body,
		TextWrapped = true,
		TextColor3 = Colors.Text,
	}
	for key, value in pairs(props) do
		merged[key] = value
	end
	return Theme.label(parent, merged)
end

-- Knopf-Varianten: "primary" (grün), "secondary" (stahlblau), "destructive" (rot) oder eine Farbe
-- Gibt (api, face) zurück. api.SetDisabled(true) = nur optisch ausgegraut, Klick kommt trotzdem an.
local function button(parent, props)
	local variants = {
		primary = Theme.primaryButton,
		secondary = Theme.secondaryButton,
		destructive = Theme.destructiveButton,
	}
	local variant = props.Variant or "primary"
	local build = variants[variant] or Theme.button
	local merged = table.clone(props)
	merged.Variant = nil
	if not variants[variant] then
		merged.Color = variant
	end
	local face, holder, _, api = build(parent, merged)
	return api, face, holder
end

-- Kaufknopf mit Münz-Symbol links und Preis. Gibt (api, face) zurück.
local function priceButton(parent, props)
	local api, face, holder = button(parent, {
		Name = "Buy",
		Text = CowData.FormatNumber(props.Price),
		TextSize = Theme.TextSize.Heading - 2,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
	})
	local coin = Theme.coinIcon(holder, 24, UDim2.new(0, 28, 0.5, -2))
	coin.ZIndex = face.ZIndex + 1
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	pad.Parent = face
	return api, face
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function formatPercent(weight, total)
	local pct = weight / total * 100
	if pct < 1 then
		return ("%.1f%%"):format(pct)
	end
	return ("%d%%"):format(math.floor(pct + 0.5))
end

local function serverNow()
	return os.time() + serverTimeOffset
end

local function coins()
	return player:GetAttribute("Coins") or 0
end

-- Zeile "Name ......... Wert" (Werte rechts)
local function statRow(parent, y, name, value)
	label(parent, {
		Position = UDim2.fromOffset(Theme.Spacing.L, y),
		Size = UDim2.new(0.6, 0, 0, 20),
		TextColor3 = Colors.SubText,
		TextSize = Theme.TextSize.Small,
		Font = Theme.BodyFont,
		Text = name,
	})
	label(parent, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, y),
		Size = UDim2.new(0.4, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Font,
		TextSize = Theme.TextSize.Body,
		Text = value,
	})
end

------------------------------------------------------------------------
-- Grundgerüst
------------------------------------------------------------------------
local gui = Theme.screenGui("MenuUI", 8)
gui.Parent = player:WaitForChild("PlayerGui")

-- Hauptfenster (gemeinsames Theme-Fenster: ein Fenster zur Zeit, Hintergrund abgedunkelt)
local PAGE_COLORS = {
	Shop = Colors.Blue,
	Crates = Colors.Gold, -- Kisten = seltene Belohnungen
	Breeding = Colors.Pink,
	Daily = Colors.Green,
	AutoMilker = Colors.Teal,
}

local win = Theme.window(gui, {
	Name = "Window", -- (das Tutorial prüft MenuUI.Window.Visible)
	Title = "",
	Size = Vector2.new(680, 500),
	OnClose = function()
		currentPage = nil
	end,
})
local window = win.Root

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, -30)
content.BackgroundTransparency = 1
content.Parent = win.Body

local statusText = label(win.Body, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 24),
	TextColor3 = ERROR_COLOR,
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Theme.BodyFont,
	TextWrapped = false,
	Text = "",
})

local statusToken = 0
local function showStatus(text, color)
	statusToken += 1
	local token = statusToken
	statusText.Text = text or ""
	statusText.TextColor3 = color or ERROR_COLOR
	task.delay(4, function()
		if statusToken == token then
			statusText.Text = ""
		end
	end)
end

------------------------------------------------------------------------
-- Seiten
------------------------------------------------------------------------
local pages = {} -- [name] = { Title, Frame, Build = function() }

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function newPage(name, title)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = content
	pages[name] = { Title = title, Frame = frame }
	return pages[name]
end

local function refreshInventory()
	local ok, result = pcall(function()
		return Remotes.GetInventory:InvokeServer()
	end)
	if ok and result then
		inventory = result
		serverTimeOffset = (result.ServerTime or os.time()) - os.time()
	end
	return inventory
end

local function rebuildCurrent()
	if currentPage and pages[currentPage].Build then
		pages[currentPage].Build()
	end
end

-- keepOpen = true: nicht umschalten (Klick aufs Gebäude öffnet immer)
local function openPage(name, keepOpen)
	if not pages[name] then
		return
	end
	if currentPage == name and win:IsOpen() then
		if not keepOpen then
			win:Close()
		end
		return
	end
	for pageName, page in pairs(pages) do
		page.Frame.Visible = pageName == name
	end
	win:SetTitle(pages[name].Title)
	win:SetColor(PAGE_COLORS[name] or Colors.Blue)
	statusText.Text = ""

	-- "Wusch"-Sound
	if CowData.Config.ShopOpenSoundId ~= "" then
		local whoosh = Instance.new("Sound")
		whoosh.SoundId = CowData.Config.ShopOpenSoundId
		whoosh.Volume = 0.6
		whoosh.Parent = SoundService
		whoosh:Play()
		whoosh.Ended:Connect(function()
			whoosh:Destroy()
		end)
	end

	win:Open()
	currentPage = name

	task.spawn(function()
		refreshInventory()
		rebuildCurrent()
	end)
end

------------------------------------------------------------------------
-- Shop
------------------------------------------------------------------------
local shopPage = newPage("Shop", "KUH-SHOP")
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -8, 0, 290)
	grid.CellPadding = UDim2.fromOffset(Theme.Spacing.L, Theme.Spacing.L)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = shopPage.Frame

	local buyButtons = {} -- [rarity] = api

	local function updateAffordable()
		for rarity, api in pairs(buyButtons) do
			api.SetDisabled(coins() < CowData.Rarities[rarity].ShopPrice)
		end
	end

	shopPage.Build = function()
		clear(shopPage.Frame)
		table.clear(buyButtons)

		for order, rarity in ipairs(CowData.RarityOrder) do
			local info = CowData.Rarities[rarity]
			if info.ShopPrice then
				local card = Theme.cowCard(shopPage.Frame, {
					Name = rarity,
					LayoutOrder = order,
					Info = info,
					CowName = "Kuh",
				})
				statRow(card, 90, "Milch pro Zug", CowData.FormatNumber(info.MilkPerPull))
				statRow(card, 118, "Pause nach dem Melken", info.MilkCooldown .. " s")
				statRow(card, 146, "Zuchtdauer", formatTime(info.BreedTime))

				local api, buy = priceButton(card, {
					Price = info.ShopPrice,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -Theme.Spacing.L),
					Size = UDim2.new(1, -32, 0, 48),
				})
				buyButtons[rarity] = api

				buy.Activated:Connect(function()
					if coins() < info.ShopPrice then
						showStatus("Nicht genug Coins! Melke und verkaufe mehr Milch.")
						return
					end
					buy.Active = false
					local called, ok, message = pcall(function()
						return Remotes.BuyCow:InvokeServer(rarity)
					end)
					buy.Active = true
					if called and ok then
						showStatus("Gekauft! Deine neue Kuh steht auf der Farm.", OK_COLOR)
					else
						showStatus((called and message) or "Kauf fehlgeschlagen.")
					end
				end)
			end
		end
		updateAffordable()
	end

	player:GetAttributeChangedSignal("Coins"):Connect(updateAffordable)
end

------------------------------------------------------------------------
-- Kisten (mit Enthüllung)
------------------------------------------------------------------------
local reveal = Instance.new("Frame")
reveal.Name = "Reveal"
reveal.Size = UDim2.fromScale(1, 1)
reveal.BackgroundColor3 = Colors.Outline
reveal.BackgroundTransparency = 0.3
reveal.BorderSizePixel = 0
reveal.Visible = false
reveal.ZIndex = 50
reveal.Parent = gui

local revealHolder = Instance.new("Frame")
revealHolder.AnchorPoint = Vector2.new(0.5, 0.5)
revealHolder.Position = UDim2.fromScale(0.5, 0.5)
revealHolder.Size = UDim2.fromOffset(340, 220)
revealHolder.BackgroundTransparency = 1
revealHolder.ZIndex = 51
revealHolder.Parent = reveal
Theme.softShadow(revealHolder, Theme.Radius.XL)
local revealScale = Instance.new("UIScale")
revealScale.Parent = revealHolder

local revealCard = Theme.panel(revealHolder, {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Panel,
	ZIndex = 52,
	Radius = Theme.Radius.XL,
	Outline = 3, -- Farbe = Seltenheit
})
local revealStroke = revealCard:FindFirstChildOfClass("UIStroke")

local revealTop = label(revealCard, {
	Position = UDim2.fromOffset(0, 24),
	Size = UDim2.new(1, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Colors.SubText,
	TextSize = Theme.TextSize.Heading - 4,
	Text = "",
})
local revealRarity = label(revealCard, {
	Position = UDim2.fromOffset(0, 70),
	Size = UDim2.new(1, 0, 0, 60),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Theme.Font,
	TextSize = 44,
	TextWrapped = false,
	Text = "",
})
local revealHint = label(revealCard, {
	Position = UDim2.fromOffset(0, 150),
	Size = UDim2.new(1, 0, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Colors.SubText,
	Text = "",
})
local revealClose = Instance.new("TextButton")
revealClose.Size = UDim2.fromScale(1, 1)
revealClose.BackgroundTransparency = 1
revealClose.Text = ""
revealClose.ZIndex = 60
local invisibleSelection = Instance.new("Frame") -- unsichtbar: der ganze Bildschirm ist der Knopf
invisibleSelection.BackgroundTransparency = 1
revealClose.SelectionImageObject = invisibleSelection
revealClose.Parent = reveal

local revealing = false
revealClose.Activated:Connect(function()
	if not revealing then
		reveal.Visible = false
		if GuiService.SelectedObject == revealClose then
			GuiService.SelectedObject = nil
		end
	end
end)

local function playReveal(crateName, rarity)
	local info = CowData.Rarities[rarity]
	reveal.Visible = true
	revealing = true
	revealTop.Text = crateName .. " wird geöffnet..."
	revealHint.Text = ""

	-- "Slot-Maschine": kurz durch die möglichen Seltenheiten wechseln
	local order = CowData.RarityOrder
	local delay = 0.05
	for i = 1, 14 do
		local r = CowData.Rarities[order[(i % 5) + 1]]
		revealRarity.Text = r.DisplayName
		revealRarity.TextColor3 = r.UiColor
		revealStroke.Color = r.UiColor
		task.wait(delay)
		delay *= 1.15
	end

	revealTop.Text = info.IsSpecial and "SPECIAL-KUH!" or "Deine neue Kuh:"
	revealRarity.Text = info.DisplayName
	revealRarity.TextColor3 = info.UiColor
	revealStroke.Color = info.UiColor
	revealScale.Scale = 1.3
	Theme.tween(revealScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
	revealHint.Text = ("%d Milch pro Zug · zum Schließen tippen"):format(info.MilkPerPull)
	revealing = false
	if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
		GuiService.SelectedObject = revealClose
	end
end

local cratesPage = newPage("Crates", "KISTEN")
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -11, 1, 0)
	grid.CellPadding = UDim2.fromOffset(Theme.Spacing.L, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cratesPage.Frame

	cratesPage.Build = function()
		clear(cratesPage.Frame)

		for order, crateId in ipairs(CowData.CrateOrder) do
			local crate = CowData.Crates[crateId]

			local card = Theme.panel(cratesPage.Frame, {
				Name = crateId,
				LayoutOrder = order,
				BackgroundColor3 = Colors.Card,
				Radius = Theme.Radius.M,
			})
			Theme.padding(card, Theme.Spacing.M)

			label(card, {
				Size = UDim2.new(1, 0, 0, 28),
				Font = Theme.Font,
				TextSize = Theme.TextSize.Heading - 2,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				Text = crate.DisplayName,
			})
			label(card, {
				Position = UDim2.fromOffset(0, 30),
				Size = UDim2.new(1, 0, 0, 16),
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Tiny + 1,
				TextColor3 = Colors.SubText,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "Chancen",
			})

			-- Inhalt mit Chancen
			local total = 0
			for _, entry in ipairs(crate.Loot) do
				total += entry.Weight
			end
			for i, entry in ipairs(crate.Loot) do
				local info = CowData.Rarities[entry.Rarity]
				local rowY = 54 + (i - 1) * 24
				label(card, {
					Position = UDim2.fromOffset(0, rowY),
					Size = UDim2.new(0.7, 0, 0, 20),
					Font = Theme.BodyFont,
					TextSize = Theme.TextSize.Small,
					TextColor3 = info.UiColor,
					TextWrapped = false,
					Text = (info.IsSpecial and "★ " or "• ") .. info.DisplayName,
				})
				label(card, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, rowY),
					Size = UDim2.new(0.3, 0, 0, 20),
					Font = Theme.BodyFont,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = formatPercent(entry.Weight, total),
				})
			end

			-- Kaufknöpfe (unten)
			local buttonY = 0
			if crate.ProductId then
				local ready = crate.ProductId > 0
				local robux = button(card, {
					Variant = Colors.Teal,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, buttonY),
					Size = UDim2.new(1, 0, 0, 44),
					Text = ready and "R$ Robux" or "R$ bald",
					TextSize = Theme.TextSize.Body + 2,
				})
				robux.SetDisabled(not ready)
				buttonY -= 52
				robux.Face.Activated:Connect(function()
					if not ready then
						showStatus("Der Robux-Kauf ist noch nicht freigeschaltet.")
						return
					end
					local called, ok, message = pcall(function()
						return Remotes.OpenCrate:InvokeServer(crateId, true)
					end)
					if not (called and ok) then
						showStatus((called and message) or "Kauf nicht möglich.")
					end
					-- Bei Erfolg öffnet sich der Roblox-Kaufdialog,
					-- die Kuh kommt danach per Benachrichtigung.
				end)
			end
			if crate.CoinPrice then
				local coinApi, coinFace, coinHolder = priceButton(card, {
					Price = crate.CoinPrice,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, buttonY),
					Size = UDim2.new(1, 0, 0, 46),
				})
				local function updateColor()
					coinApi.SetDisabled(coins() < crate.CoinPrice)
				end
				updateColor()
				local connection = player:GetAttributeChangedSignal("Coins"):Connect(updateColor)
				coinHolder.Destroying:Connect(function()
					connection:Disconnect()
				end)

				coinFace.Activated:Connect(function()
					if revealing then
						return
					end
					if coins() < crate.CoinPrice then
						showStatus("Nicht genug Coins!")
						return
					end
					local called, ok, rarityOrMessage = pcall(function()
						return Remotes.OpenCrate:InvokeServer(crateId, false)
					end)
					if called and ok then
						playReveal(crate.DisplayName, rarityOrMessage)
					else
						showStatus((called and rarityOrMessage) or "Öffnen fehlgeschlagen.")
					end
				end)
			end
		end
	end
end

------------------------------------------------------------------------
-- Zucht
------------------------------------------------------------------------
local breedPage = newPage("Breeding", "ZUCHT-STALL")
do
	local selected = {} -- Liste mit bis zu 2 Kuh-IDs
	local countdown = nil -- { Label, Bar, StartedAt, ReadyAt } solange eine Zucht läuft

	local function findCow(id)
		if not inventory then
			return nil
		end
		for _, cow in ipairs(inventory.Cows) do
			if cow.Id == id then
				return cow
			end
		end
		return nil
	end

	breedPage.Build = function()
		clear(breedPage.Frame)
		countdown = nil
		if not inventory then
			label(breedPage.Frame, { Size = UDim2.fromScale(1, 1), Text = "Lade...", TextXAlignment = Enum.TextXAlignment.Center })
			return
		end

		-- Läuft schon eine Zucht?
		local breeding = inventory.Breeding
		if breeding then
			local a, b = findCow(breeding.ParentA), findCow(breeding.ParentB)
			label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 50),
				Size = UDim2.new(1, 0, 0, 40),
				Font = Theme.Font,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Colors.Pink,
				Text = ("%s  &  %s"):format(a and a.Name or "?", b and b.Name or "?"),
			})
			local timeLabel = label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 100),
				Size = UDim2.new(1, 0, 0, 60),
				Font = Theme.Font,
				TextSize = 44,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = formatTime(breeding.ReadyAt - serverNow()),
			})
			local bar = Theme.progressBar(breedPage.Frame, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 176),
				Size = UDim2.new(0.8, 0, 0, 18),
				Color = Colors.Pink,
			})
			countdown = { Label = timeLabel, Bar = bar, StartedAt = breeding.StartedAt or serverNow(), ReadyAt = breeding.ReadyAt }
			local span = math.max(1, countdown.ReadyAt - countdown.StartedAt)
			bar.SetRatio((serverNow() - countdown.StartedAt) / span, false)
			label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 214),
				Size = UDim2.new(1, 0, 0, 40),
				TextColor3 = Colors.SubText,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "Das Kalb kommt automatisch auf deine Farm – auch wenn du offline bist.",
			})
			return
		end

		-- Auswahl-Liste (links)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(0.55, -8, 1, 0)
		list.BackgroundColor3 = Colors.Deep
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 5
		list.ScrollBarImageColor3 = Colors.Line
		list.CanvasSize = UDim2.new()
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = breedPage.Frame
		Theme.corner(list, Theme.Radius.M)
		Theme.border(list)
		Theme.padding(list, Theme.Spacing.S)
		local listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 6)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = list

		-- Info (rechts)
		local side = Theme.panel(breedPage.Frame, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.45, -8, 1, 0),
			BackgroundColor3 = Colors.Card,
			Radius = Theme.Radius.M,
		})
		Theme.padding(side, Theme.Spacing.M)

		local pairLabel = label(side, {
			Size = UDim2.new(1, 0, 0, 44),
			Font = Theme.Font,
			TextSize = Theme.TextSize.Heading - 4,
			Text = "",
		})
		local chancesFrame = Instance.new("Frame")
		chancesFrame.Position = UDim2.fromOffset(0, 50)
		chancesFrame.Size = UDim2.new(1, 0, 0, 140)
		chancesFrame.BackgroundTransparency = 1
		chancesFrame.Parent = side
		local chancesLayout = Instance.new("UIListLayout")
		chancesLayout.Padding = UDim.new(0, 4)
		chancesLayout.SortOrder = Enum.SortOrder.LayoutOrder
		chancesLayout.Parent = chancesFrame
		local infoLabel = label(side, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -54),
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = Theme.TextSize.Small,
			Font = Theme.BodyFont,
			TextColor3 = Colors.SubText,
			Text = "",
		})
		local startApi, startFace = button(side, {
			Text = "Zucht starten",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 46),
			TextSize = Theme.TextSize.Heading - 4,
		})

		local rowButtons = {} -- [cowId] = { Row, Stroke }

		local function setChances(chances, totalWeight)
			clear(chancesFrame)
			for i, entry in ipairs(chances) do
				local info = CowData.Rarities[entry.Rarity]
				local row = Instance.new("Frame")
				row.LayoutOrder = i
				row.Size = UDim2.new(1, 0, 0, 22)
				row.BackgroundTransparency = 1
				row.Parent = chancesFrame
				label(row, {
					Size = UDim2.new(0, 84, 1, 0),
					Font = Theme.BodyFont,
					TextSize = Theme.TextSize.Small,
					TextColor3 = info.UiColor,
					TextWrapped = false,
					Text = (info.IsSpecial and "★ " or "") .. info.DisplayName,
				})
				local bar = Theme.progressBar(row, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 88, 0.5, 0),
					Size = UDim2.new(1, -138, 0, 10),
					Color = info.UiColor,
				})
				bar.SetRatio(entry.Weight / totalWeight, false)
				label(row, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, 46, 1, 0),
					Font = Theme.BodyFont,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = formatPercent(entry.Weight, totalWeight),
				})
			end
		end

		local function updateSide()
			for id, entry in pairs(rowButtons) do
				local isSelected = table.find(selected, id) ~= nil
				Theme.tween(entry.Row, { BackgroundColor3 = isSelected and Colors.Steel or Colors.Card }, Theme.Time.Fast)
				entry.Stroke.Color = isSelected and Colors.Blue or Colors.Line
				entry.Stroke.Thickness = isSelected and Theme.Stroke.Normal or Theme.Stroke.Thin
			end

			local a, b = findCow(selected[1]), findCow(selected[2])
			clear(chancesFrame)
			if not a then
				pairLabel.Text = "Wähle zwei Kühe aus der Liste."
				infoLabel.Text = ""
				startApi.SetDisabled(true)
				return
			end
			if not b then
				pairLabel.Text = a.Name .. "  &  ..."
				infoLabel.Text = "Wähle noch eine zweite Kuh."
				startApi.SetDisabled(true)
				return
			end

			pairLabel.Text = a.Name .. "  &  " .. b.Name
			local chances = CowData.GetBreedingChances(a.Rarity, b.Rarity)
			local total = 0
			for _, entry in ipairs(chances) do
				total += entry.Weight
			end
			setChances(chances, total)
			infoLabel.Text = "Dauer: " .. formatTime(CowData.GetBreedTime(a.Rarity, b.Rarity))
			startApi.SetDisabled(false)
		end

		-- ungültige Auswahl entfernen (z.B. nach Neuladen)
		for i = #selected, 1, -1 do
			if not findCow(selected[i]) then
				table.remove(selected, i)
			end
		end

		for order, cow in ipairs(inventory.Cows) do
			local info = CowData.Rarities[cow.Rarity]
			local row = Instance.new("TextButton")
			row.Name = cow.Id
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -4, 0, 46)
			row.BackgroundColor3 = Colors.Card
			row.BorderSizePixel = 0
			row.AutoButtonColor = false
			row.Text = ""
			row.Parent = list
			Theme.corner(row, 10)
			local stroke = Theme.border(row)

			Theme.cowIcon(row, 30, UDim2.fromOffset(26, 23), info.Color, info.SpotColor, info.Transparency and 0.3 or 0)
			label(row, {
				Position = UDim2.fromOffset(50, 0),
				Size = UDim2.new(1, -150, 1, 0),
				Font = Theme.BodyFont,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = cow.Name,
			})
			Theme.rarityBadge(row, info, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
			})

			rowButtons[cow.Id] = { Row = row, Stroke = stroke }
			row.MouseEnter:Connect(function()
				if not table.find(selected, cow.Id) then
					Theme.tween(row, { BackgroundColor3 = Colors.PanelLight }, Theme.Time.Fast)
				end
			end)
			row.MouseLeave:Connect(function()
				if not table.find(selected, cow.Id) then
					Theme.tween(row, { BackgroundColor3 = Colors.Card }, Theme.Time.Fast)
				end
			end)
			row.Activated:Connect(function()
				local index = table.find(selected, cow.Id)
				if index then
					table.remove(selected, index)
				else
					if #selected >= 2 then
						table.remove(selected, 1)
					end
					table.insert(selected, cow.Id)
				end
				updateSide()
			end)
		end

		if #inventory.Cows < 2 then
			label(list, {
				LayoutOrder = 999,
				Size = UDim2.new(1, -4, 0, 60),
				TextColor3 = Colors.SubText,
				Text = "Du brauchst mindestens 2 Kühe zum Züchten. Kauf eine im Shop!",
			})
		end

		startFace.Activated:Connect(function()
			if #selected < 2 then
				showStatus("Wähle zuerst zwei Kühe aus.")
				return
			end
			local called, ok, message = pcall(function()
				return Remotes.StartBreeding:InvokeServer(selected[1], selected[2])
			end)
			if called and ok then
				table.clear(selected)
				refreshInventory()
				breedPage.Build()
			else
				showStatus((called and message) or "Zucht nicht möglich.")
			end
		end)

		updateSide()
	end

	-- Countdown jede Sekunde aktualisieren
	task.spawn(function()
		while true do
			task.wait(1)
			if countdown and countdown.Label.Parent and currentPage == "Breeding" then
				local left = countdown.ReadyAt - serverNow()
				countdown.Label.Text = left > 0 and formatTime(left) or "Gleich da!"
				local span = math.max(1, countdown.ReadyAt - countdown.StartedAt)
				countdown.Bar.SetRatio((serverNow() - countdown.StartedAt) / span)
			end
		end
	end)
end

------------------------------------------------------------------------
-- Auto-Melker
------------------------------------------------------------------------
local autoPage = newPage("AutoMilker", "AUTO-MELKER")
do
	autoPage.Build = function()
		clear(autoPage.Frame)

		label(autoPage.Frame, {
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 120),
			TextSize = Theme.TextSize.Heading - 4,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Colors.SubText,
			Text = ("Der Auto-Melker melkt alle %d Sekunden jede deiner Kühe – auch während du andere Sachen machst!\n\nEinmal kaufen, für immer behalten."):format(CowData.Config.AutoMilkInterval),
		})

		local owned = player:GetAttribute("HasAutoMilker") == true
		local ready = CowData.Config.AutoMilkerGamePassId ~= 0
		local api, buy = button(autoPage.Frame, {
			Variant = Colors.Teal,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 170),
			Size = UDim2.fromOffset(280, 56),
			TextSize = Theme.TextSize.Heading,
			Text = owned and "Aktiv" or (ready and "R$ Gamepass kaufen" or "R$ bald verfügbar"),
		})
		api.SetDisabled(owned or not ready)
		buy.Activated:Connect(function()
			if player:GetAttribute("HasAutoMilker") then
				showStatus("Du hast den Auto-Melker schon!", OK_COLOR)
				return
			end
			Remotes.BuyAutoMilker:FireServer()
		end)
	end

	player:GetAttributeChangedSignal("HasAutoMilker"):Connect(function()
		if currentPage == "AutoMilker" then
			autoPage.Build()
		end
	end)
end

------------------------------------------------------------------------
-- Tagesbonus (Login-Streak)
------------------------------------------------------------------------
local dailyPage = newPage("Daily", "TAGESBONUS")
do
	dailyPage.Build = function()
		clear(dailyPage.Frame)
		local config = CowData.Config
		local streak = player:GetAttribute("LoginStreak") or 0
		local cycleDay = streak > 0 and ((streak - 1) % config.RainbowStreakDays) + 1 or 0

		label(dailyPage.Frame, {
			Size = UDim2.new(1, 0, 0, 40),
			Font = Theme.Font,
			TextSize = 32,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ("%d %s am Stück"):format(streak, streak == 1 and "Tag" or "Tage"),
		})
		label(dailyPage.Frame, {
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Colors.SubText,
			Text = "Komm jeden Tag wieder! Nach 7 Tagen am Stück bekommst du eine Regenbogen-Kuh.",
		})
		local bar = Theme.progressBar(dailyPage.Frame, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 88),
			Size = UDim2.new(0.7, 0, 0, 14),
			Color = Colors.Green,
		})
		bar.SetRatio(cycleDay / config.RainbowStreakDays, false)

		-- 7 Tages-Kästchen
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, 116)
		row.Size = UDim2.new(1, 0, 0, 160)
		row.BackgroundTransparency = 1
		row.Parent = dailyPage.Frame
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / 7, -8, 1, 0)
		grid.CellPadding = UDim2.fromOffset(8, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row

		local rainbowInfo = CowData.Rarities.Rainbow
		for day = 1, config.RainbowStreakDays do
			local done = day <= cycleDay
			local isToday = day == cycleDay
			local isRainbow = day == config.RainbowStreakDays
			local box = Theme.panel(row, {
				Name = "Day" .. day,
				LayoutOrder = day,
				BackgroundColor3 = done and Theme.darken(Colors.Green, 0.2) or Colors.Card,
				Radius = Theme.Radius.M,
				Outline = isToday and 2.5 or Theme.Stroke.Thin,
				OutlineColor = isToday and Colors.Blue or (isRainbow and Colors.Gold or Colors.Line), -- Gold: seltene Belohnung
			})
			label(box, {
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 20),
				Font = Theme.BodyFont,
				TextSize = Theme.TextSize.Small,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "Tag " .. day,
			})
			if isRainbow then
				Theme.cowIcon(box, 36, UDim2.new(0.5, 0, 0, 52), rainbowInfo.Color, rainbowInfo.SpotColor)
			else
				Theme.coinIcon(box, 34, UDim2.new(0.5, 0, 0, 52))
			end
			label(box, {
				Position = UDim2.fromOffset(4, 82),
				Size = UDim2.new(1, -8, 0, 56),
				Font = Theme.Font,
				TextSize = Theme.TextSize.Body - 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = (isRainbow and "Kuh +\n" or "") .. CowData.FormatNumber(config.DailyRewardBase * day),
			})
			if done then
				local check = Theme.label(box, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 4),
					Size = UDim2.fromOffset(20, 20),
					BackgroundTransparency = 0,
					BackgroundColor3 = Colors.Green,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextSize = 14,
					Text = "✓",
				})
				Theme.corner(check, UDim.new(1, 0))
			end
		end

		label(dailyPage.Frame, {
			Position = UDim2.fromOffset(0, 292),
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Colors.SubText,
			Text = "Der Bonus wird automatisch gutgeschrieben, sobald du einen neuen Tag spielst.",
		})
	end

	player:GetAttributeChangedSignal("LoginStreak"):Connect(function()
		if currentPage == "Daily" then
			dailyPage.Build()
		end
	end)
end

------------------------------------------------------------------------
-- Andere Scripts (Übersicht, Tutorial) können Fenster öffnen / schließen
------------------------------------------------------------------------
UIBus.OpenPage.Event:Connect(function(page)
	openPage(page, true)
end)
UIBus.CloseOverlays.Event:Connect(function()
	win:Close()
end)

-- Server sagt: Shop-Gebäude wurde angeklickt -> passendes Fenster öffnen
Remotes.OpenShop.OnClientEvent:Connect(function(page)
	openPage(page, true)
end)

------------------------------------------------------------------------
-- Shop-Gebäude auf dem Platz (Tag "ShopBuilding", Attribut "Page")
------------------------------------------------------------------------
local function hookShopBuilding(building)
	local clickDetector = building:FindFirstChildWhichIsA("ClickDetector", true)
		or building:WaitForChild("ClickDetector", 10)
	if not clickDetector then
		return
	end

	-- beim Drüberfahren leuchtet das Gebäude auf
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Colors.Cream
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Adornee = building
	highlight.Parent = building

	clickDetector.MouseHoverEnter:Connect(function()
		highlight.Enabled = true
	end)
	clickDetector.MouseHoverLeave:Connect(function()
		highlight.Enabled = false
	end)
	-- der Klick selbst geht an den Server, der Remotes.OpenShop zurückschickt
end

for _, building in ipairs(CollectionService:GetTagged("ShopBuilding")) do
	task.spawn(hookShopBuilding, building)
end
CollectionService:GetInstanceAddedSignal("ShopBuilding"):Connect(function(building)
	task.spawn(hookShopBuilding, building)
end)

-- Inventar hat sich geändert (neue Kuh, Zucht gestartet/fertig) -> offene Seite neu aufbauen
Remotes.InventoryChanged.OnClientEvent:Connect(function()
	if window.Visible and currentPage then
		refreshInventory()
		rebuildCurrent()
	end
end)
