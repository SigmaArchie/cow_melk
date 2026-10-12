-- MenuUI.client.lua
-- Fenster, die sich öffnen, wenn man ein Shop-Gebäude anklickt (Server -> Remotes.OpenShop)
-- oder sie aus der Übersicht aufruft (UIBus.OpenPage):
--   🐄 Shop        – Common/Uncommon für Coins kaufen          (Gebäude "KUH-SHOP")
--   ✨ Kisten      – Kuh-Kisten für Coins oder Robux öffnen    (Gebäude "KISTEN")
--   💕 Zucht       – zwei Kühe auswählen, Chancen, Zucht       (Gebäude "ZUCHT-STALL")
--   🎁 Tagesbonus  – Login-Streak und Belohnungen der 7 Tage
--   🥛 Auto-Melker – Gamepass kaufen                           (Gebäude "AUTO-MELKER")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIBus = require(script.Parent:WaitForChild("UIBus"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local player = Players.LocalPlayer

local BG = Theme.Colors.Panel
local CARD = Theme.Colors.Card
local CARD_HOVER = Theme.Colors.PanelLight
local TEXT = Theme.Colors.Text
local SUBTEXT = Theme.Colors.SubText
local GREEN = Theme.Colors.Green
local ROBUX = Color3.fromRGB(0, 170, 110)
local PINK = Theme.Colors.Pink
local DISABLED = Theme.Colors.Grey
local ERROR = Color3.fromRGB(255, 120, 120)

local inventory = nil -- letzte Antwort von GetInventory
local serverTimeOffset = 0
local currentPage = nil

------------------------------------------------------------------------
-- kleine UI-Helfer
------------------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 15
	l.TextColor3 = TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 18
	b.TextColor3 = TEXT
	b.BackgroundColor3 = GREEN
	for k, v in pairs(props) do
		b[k] = v
	end
	corner(b, 10)
	Theme.border(b, 3)
	Theme.textOutline(b, 2)
	b.Parent = parent
	return b
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

------------------------------------------------------------------------
-- Grundgerüst
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MenuUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Hauptfenster (gemeinsames Theme-Fenster: ein Fenster zur Zeit, Hintergrund abgedunkelt)
local PAGE_COLORS = {
	Shop = Theme.Colors.Blue,
	Crates = Theme.Colors.Orange,
	Breeding = Theme.Colors.Pink,
	Daily = Theme.Colors.Green,
	AutoMilker = Theme.Colors.Teal,
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
	TextColor3 = ERROR,
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold,
	Text = "",
})

local statusToken = 0
local function showStatus(text, color)
	statusToken += 1
	local token = statusToken
	statusText.Text = text or ""
	statusText.TextColor3 = color or ERROR
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
	win:SetColor(PAGE_COLORS[name] or Theme.Colors.Blue)
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
-- 🛒 Shop
------------------------------------------------------------------------
local shopPage = newPage("Shop", "KUH-SHOP")
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -8, 0, 220)
	grid.CellPadding = UDim2.fromOffset(16, 16)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = shopPage.Frame

	local buyButtons = {} -- [rarity] = button

	local function updateAffordable()
		for rarity, b in pairs(buyButtons) do
			local price = CowData.Rarities[rarity].ShopPrice
			b.BackgroundColor3 = coins() >= price and GREEN or DISABLED
		end
	end

	shopPage.Build = function()
		clear(shopPage.Frame)
		table.clear(buyButtons)

		for order, rarity in ipairs(CowData.RarityOrder) do
			local info = CowData.Rarities[rarity]
			if info.ShopPrice then
				local card = Instance.new("Frame")
				card.LayoutOrder = order
				card.BackgroundColor3 = CARD
				card.Parent = shopPage.Frame
				corner(card, 14)

				local strip = Instance.new("Frame")
				strip.Size = UDim2.new(1, 0, 0, 8)
				strip.BackgroundColor3 = info.UiColor
				strip.BorderSizePixel = 0
				strip.Parent = card
				corner(strip, 4)

				local swatch = Instance.new("Frame")
				swatch.Position = UDim2.fromOffset(16, 24)
				swatch.Size = UDim2.fromOffset(56, 56)
				swatch.BackgroundColor3 = info.Color
				swatch.Parent = card
				corner(swatch, 28)
				if info.SpotColor then
					local spot = Instance.new("Frame")
					spot.Position = UDim2.fromOffset(10, 12)
					spot.Size = UDim2.fromOffset(20, 16)
					spot.BackgroundColor3 = info.SpotColor
					spot.Parent = swatch
					corner(spot, 8)
				end

				label(card, {
					Position = UDim2.fromOffset(84, 24),
					Size = UDim2.new(1, -96, 0, 28),
					Font = Enum.Font.FredokaOne,
					TextSize = 22,
					TextColor3 = info.UiColor,
					Text = info.DisplayName,
				})
				label(card, {
					Position = UDim2.fromOffset(84, 54),
					Size = UDim2.new(1, -96, 0, 20),
					TextColor3 = SUBTEXT,
					Text = "Kuh",
				})
				label(card, {
					Position = UDim2.fromOffset(16, 92),
					Size = UDim2.new(1, -32, 0, 60),
					TextColor3 = SUBTEXT,
					Text = ("🥛 %d Milch pro Zug\n⏳ %d s Pause nach dem Melken"):format(info.MilkPerPull, info.MilkCooldown),
				})

				local buy = button(card, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -14),
					Size = UDim2.new(1, -32, 0, 44),
					Text = "🪙 " .. CowData.FormatNumber(info.ShopPrice),
				})
				buyButtons[rarity] = buy

				buy.Activated:Connect(function()
					if coins() < info.ShopPrice then
						showStatus("Nicht genug Coins! Melke und verkaufe mehr Milch. 🥛")
						return
					end
					buy.Active = false
					local ok, message = Remotes.BuyCow:InvokeServer(rarity)
					buy.Active = true
					if ok then
						showStatus("Gekauft! Deine neue Kuh steht auf der Farm. 🐄", GREEN)
					else
						showStatus(message or "Kauf fehlgeschlagen.")
					end
				end)
			end
		end
		updateAffordable()
	end

	player:GetAttributeChangedSignal("Coins"):Connect(updateAffordable)
end

------------------------------------------------------------------------
-- 🎁 Kisten (mit Enthüllung)
------------------------------------------------------------------------
local reveal = Instance.new("Frame")
reveal.Name = "Reveal"
reveal.Size = UDim2.fromScale(1, 1)
reveal.BackgroundColor3 = Color3.new(0, 0, 0)
reveal.BackgroundTransparency = 0.35
reveal.Visible = false
reveal.ZIndex = 50
reveal.Parent = gui

local revealCard = Instance.new("Frame")
revealCard.AnchorPoint = Vector2.new(0.5, 0.5)
revealCard.Position = UDim2.fromScale(0.5, 0.5)
revealCard.Size = UDim2.fromOffset(340, 220)
revealCard.BackgroundColor3 = BG
revealCard.ZIndex = 51
revealCard.Parent = reveal
corner(revealCard, 20)
local revealStroke = Instance.new("UIStroke")
revealStroke.Thickness = 4
revealStroke.Parent = revealCard
local revealScale = Instance.new("UIScale")
revealScale.Parent = revealCard

local revealTop = label(revealCard, {
	Position = UDim2.fromOffset(0, 24),
	Size = UDim2.new(1, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = SUBTEXT,
	TextSize = 18,
	ZIndex = 52,
	Text = "",
})
local revealRarity = label(revealCard, {
	Position = UDim2.fromOffset(0, 70),
	Size = UDim2.new(1, 0, 0, 60),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.FredokaOne,
	TextSize = 44,
	ZIndex = 52,
	Text = "",
})
local revealHint = label(revealCard, {
	Position = UDim2.fromOffset(0, 150),
	Size = UDim2.new(1, 0, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = SUBTEXT,
	ZIndex = 52,
	Text = "Klicke zum Schließen",
})
local revealClose = Instance.new("TextButton")
revealClose.Size = UDim2.fromScale(1, 1)
revealClose.BackgroundTransparency = 1
revealClose.Text = ""
revealClose.ZIndex = 60
revealClose.Parent = reveal

local revealing = false
revealClose.Activated:Connect(function()
	if not revealing then
		reveal.Visible = false
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

	revealTop.Text = info.IsSpecial and "✨ SPECIAL-KUH! ✨" or "Deine neue Kuh:"
	revealRarity.Text = info.DisplayName
	revealRarity.TextColor3 = info.UiColor
	revealStroke.Color = info.UiColor
	revealScale.Scale = 1.35
	TweenService:Create(revealScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	revealHint.Text = ("🥛 %d pro Zug · Klicke zum Schließen"):format(info.MilkPerPull)
	revealing = false
end

local cratesPage = newPage("Crates", "KISTEN")
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -11, 1, 0)
	grid.CellPadding = UDim2.fromOffset(16, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cratesPage.Frame

	cratesPage.Build = function()
		clear(cratesPage.Frame)

		for order, crateId in ipairs(CowData.CrateOrder) do
			local crate = CowData.Crates[crateId]

			local card = Instance.new("Frame")
			card.LayoutOrder = order
			card.BackgroundColor3 = CARD
			card.Parent = cratesPage.Frame
			corner(card, 14)
			padding(card, 12)

			label(card, {
				Size = UDim2.new(1, 0, 0, 28),
				Font = Enum.Font.FredokaOne,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = (crateId == "Premium" and "💎 " or "📦 ") .. crate.DisplayName,
			})

			-- Inhalt mit Chancen
			local total = 0
			for _, entry in ipairs(crate.Loot) do
				total += entry.Weight
			end
			for i, entry in ipairs(crate.Loot) do
				local info = CowData.Rarities[entry.Rarity]
				label(card, {
					Position = UDim2.fromOffset(0, 34 + (i - 1) * 22),
					Size = UDim2.new(1, 0, 0, 20),
					TextSize = 14,
					TextColor3 = info.UiColor,
					Text = ("%s%s  %s"):format(info.IsSpecial and "✦ " or "• ", info.DisplayName, formatPercent(entry.Weight, total)),
				})
			end

			-- Kaufknöpfe (unten)
			local buttonY = -2
			if crate.ProductId then
				local robux = button(card, {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, buttonY),
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundColor3 = ROBUX,
					Text = "R$ Robux",
				})
				buttonY -= 48
				robux.Activated:Connect(function()
					local ok, message = Remotes.OpenCrate:InvokeServer(crateId, true)
					if not ok then
						showStatus(message or "Kauf nicht möglich.")
					end
					-- Bei Erfolg öffnet sich der Roblox-Kaufdialog,
					-- die Kuh kommt danach per Benachrichtigung.
				end)
			end
			if crate.CoinPrice then
				local coinButton = button(card, {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, buttonY),
					Size = UDim2.new(1, 0, 0, 40),
					Text = "🪙 " .. CowData.FormatNumber(crate.CoinPrice),
				})
				local function updateColor()
					coinButton.BackgroundColor3 = coins() >= crate.CoinPrice and GREEN or DISABLED
				end
				updateColor()
				local connection = player:GetAttributeChangedSignal("Coins"):Connect(updateColor)
				coinButton.Destroying:Connect(function()
					connection:Disconnect()
				end)

				coinButton.Activated:Connect(function()
					if revealing then
						return
					end
					if coins() < crate.CoinPrice then
						showStatus("Nicht genug Coins!")
						return
					end
					local ok, rarityOrMessage = Remotes.OpenCrate:InvokeServer(crateId, false)
					if ok then
						playReveal(crate.DisplayName, rarityOrMessage)
					else
						showStatus(rarityOrMessage or "Öffnen fehlgeschlagen.")
					end
				end)
			end
		end
	end
end

------------------------------------------------------------------------
-- 💕 Zucht
------------------------------------------------------------------------
local breedPage = newPage("Breeding", "ZUCHT-STALL")
do
	local selected = {} -- Liste mit bis zu 2 Kuh-IDs
	local countdownLabel = nil

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
		countdownLabel = nil
		if not inventory then
			label(breedPage.Frame, { Size = UDim2.fromScale(1, 1), Text = "Lade...", TextXAlignment = Enum.TextXAlignment.Center })
			return
		end

		-- Läuft schon eine Zucht?
		local breeding = inventory.Breeding
		if breeding then
			local a, b = findCow(breeding.ParentA), findCow(breeding.ParentB)
			label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 60),
				Size = UDim2.new(1, 0, 0, 40),
				Font = Enum.Font.FredokaOne,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = PINK,
				Text = ("%s 💕 %s"):format(a and a.Name or "?", b and b.Name or "?"),
			})
			countdownLabel = label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 110),
				Size = UDim2.new(1, 0, 0, 60),
				Font = Enum.Font.FredokaOne,
				TextSize = 44,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = formatTime(breeding.ReadyAt - serverNow()),
			})
			countdownLabel:SetAttribute("ReadyAt", breeding.ReadyAt)
			label(breedPage.Frame, {
				Position = UDim2.fromOffset(0, 180),
				Size = UDim2.new(1, 0, 0, 40),
				TextColor3 = SUBTEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "Das Kalb kommt automatisch auf deine Farm – auch wenn du offline bist. 🍼",
			})
			return
		end

		-- Auswahl-Liste (links)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(0.55, -8, 1, 0)
		list.BackgroundColor3 = CARD
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.CanvasSize = UDim2.new()
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = breedPage.Frame
		corner(list, 12)
		padding(list, 8)
		local listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 6)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = list

		-- Info (rechts)
		local side = Instance.new("Frame")
		side.AnchorPoint = Vector2.new(1, 0)
		side.Position = UDim2.fromScale(1, 0)
		side.Size = UDim2.new(0.45, -8, 1, 0)
		side.BackgroundColor3 = CARD
		side.Parent = breedPage.Frame
		corner(side, 12)
		padding(side, 12)

		local pairLabel = label(side, {
			Size = UDim2.new(1, 0, 0, 50),
			Font = Enum.Font.FredokaOne,
			TextSize = 18,
			Text = "",
		})
		local chancesLabel = label(side, {
			Position = UDim2.fromOffset(0, 56),
			Size = UDim2.new(1, 0, 0, 150),
			TextSize = 14,
			RichText = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = SUBTEXT,
			Text = "",
		})
		local startButton = button(side, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = PINK,
			Text = "💕 Zucht starten",
		})

		local rowButtons = {} -- [cowId] = button

		local function updateSide()
			for id, row in pairs(rowButtons) do
				local isSelected = table.find(selected, id) ~= nil
				row.BackgroundColor3 = isSelected and Color3.fromRGB(120, 60, 100) or CARD_HOVER
			end

			local a, b = findCow(selected[1]), findCow(selected[2])
			if not a then
				pairLabel.Text = "Wähle zwei Kühe aus der Liste."
				chancesLabel.Text = ""
				startButton.BackgroundColor3 = DISABLED
				return
			end
			if not b then
				pairLabel.Text = a.Name .. " 💕 ..."
				chancesLabel.Text = "Wähle noch eine zweite Kuh."
				startButton.BackgroundColor3 = DISABLED
				return
			end

			pairLabel.Text = a.Name .. " 💕 " .. b.Name
			local chances = CowData.GetBreedingChances(a.Rarity, b.Rarity)
			local total = 0
			for _, entry in ipairs(chances) do
				total += entry.Weight
			end
			local lines = { "<b>Mögliches Kalb:</b>" }
			for _, entry in ipairs(chances) do
				local info = CowData.Rarities[entry.Rarity]
				local c = info.UiColor
				table.insert(lines, ('<font color="rgb(%d,%d,%d)">%s%s</font>  %s'):format(
					math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255),
					info.IsSpecial and "✦ " or "• ",
					info.DisplayName,
					formatPercent(entry.Weight, total)
				))
			end
			table.insert(lines, "")
			table.insert(lines, "⏳ Dauer: " .. formatTime(CowData.GetBreedTime(a.Rarity, b.Rarity)))
			chancesLabel.Text = table.concat(lines, "\n")
			startButton.BackgroundColor3 = PINK
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
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -4, 0, 40)
			row.BackgroundColor3 = CARD_HOVER
			row.AutoButtonColor = true
			row.Text = ""
			row.Parent = list
			corner(row, 8)

			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0, 0.5)
			dot.Position = UDim2.new(0, 10, 0.5, 0)
			dot.Size = UDim2.fromOffset(20, 20)
			dot.BackgroundColor3 = info.Color
			dot.Parent = row
			corner(dot, 10)

			label(row, {
				Position = UDim2.fromOffset(40, 0),
				Size = UDim2.new(1, -48, 1, 0),
				Font = Enum.Font.GothamBold,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = cow.Name,
			})
			label(row, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.fromScale(0.5, 1),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = info.UiColor,
				TextSize = 13,
				Text = info.DisplayName,
			})

			rowButtons[cow.Id] = row
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
				TextColor3 = SUBTEXT,
				Text = "Du brauchst mindestens 2 Kühe zum Züchten. Kauf eine im Shop! 🛒",
			})
		end

		startButton.Activated:Connect(function()
			if #selected < 2 then
				showStatus("Wähle zuerst zwei Kühe aus.")
				return
			end
			local ok, message = Remotes.StartBreeding:InvokeServer(selected[1], selected[2])
			if ok then
				table.clear(selected)
				refreshInventory()
				breedPage.Build()
			else
				showStatus(message or "Zucht nicht möglich.")
			end
		end)

		updateSide()
	end

	-- Countdown jede Sekunde aktualisieren
	task.spawn(function()
		while true do
			task.wait(1)
			if countdownLabel and countdownLabel.Parent and currentPage == "Breeding" then
				local readyAt = countdownLabel:GetAttribute("ReadyAt") or 0
				local left = readyAt - serverNow()
				countdownLabel.Text = left > 0 and formatTime(left) or "🍼 Gleich da!"
			end
		end
	end)
end

------------------------------------------------------------------------
-- 🤖 Auto-Melker
------------------------------------------------------------------------
local autoPage = newPage("AutoMilker", "AUTO-MELKER")
do
	autoPage.Build = function()
		clear(autoPage.Frame)

		label(autoPage.Frame, {
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 120),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = SUBTEXT,
			Text = ("Der Auto-Melker melkt alle %d Sekunden jede deiner Kühe – auch während du andere Sachen machst!\n\nEinmal kaufen, für immer behalten."):format(CowData.Config.AutoMilkInterval),
		})

		local owned = player:GetAttribute("HasAutoMilker") == true
		local buy = button(autoPage.Frame, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 170),
			Size = UDim2.fromOffset(260, 56),
			TextSize = 22,
			BackgroundColor3 = owned and DISABLED or ROBUX,
			Text = owned and "✅ Aktiv" or "R$ Gamepass kaufen",
		})
		buy.Activated:Connect(function()
			if player:GetAttribute("HasAutoMilker") then
				showStatus("Du hast den Auto-Melker schon! 🤖", GREEN)
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
-- 🎁 Tagesbonus (Login-Streak)
------------------------------------------------------------------------
local dailyPage = newPage("Daily", "TAGESBONUS")
do
	dailyPage.Build = function()
		clear(dailyPage.Frame)
		local config = CowData.Config
		local streak = player:GetAttribute("LoginStreak") or 0
		local cycleDay = streak > 0 and ((streak - 1) % config.RainbowStreakDays) + 1 or 0

		label(dailyPage.Frame, {
			Size = UDim2.new(1, 0, 0, 44),
			Font = Enum.Font.FredokaOne,
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(255, 170, 80),
			Text = ("🔥 %d %s am Stück"):format(streak, streak == 1 and "Tag" or "Tage"),
		})
		label(dailyPage.Frame, {
			Position = UDim2.fromOffset(0, 46),
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = SUBTEXT,
			Text = "Komm jeden Tag wieder! Nach 7 Tagen am Stück bekommst du eine 🌈 Regenbogen-Kuh.",
		})

		-- 7 Tages-Kästchen
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, 100)
		row.Size = UDim2.new(1, 0, 0, 150)
		row.BackgroundTransparency = 1
		row.Parent = dailyPage.Frame
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / 7, -8, 1, 0)
		grid.CellPadding = UDim2.fromOffset(8, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row

		for day = 1, config.RainbowStreakDays do
			local done = day <= cycleDay
			local isToday = day == cycleDay
			local box = Instance.new("Frame")
			box.LayoutOrder = day
			box.BackgroundColor3 = done and Color3.fromRGB(55, 150, 75) or CARD
			box.Parent = row
			corner(box, 12)
			if isToday then
				local todayStroke = Instance.new("UIStroke")
				todayStroke.Color = Color3.fromRGB(255, 220, 80)
				todayStroke.Thickness = 3
				todayStroke.Parent = box
			end
			label(box, {
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 20),
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "Tag " .. day,
			})
			local isRainbow = day == config.RainbowStreakDays
			label(box, {
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, 44),
				TextSize = 34,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = isRainbow and "🌈" or "🪙",
			})
			label(box, {
				Position = UDim2.fromOffset(4, 84),
				Size = UDim2.new(1, -8, 0, 54),
				Font = Enum.Font.FredokaOne,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = (isRainbow and "Kuh +\n" or "") .. CowData.FormatNumber(config.DailyRewardBase * day),
			})
			if done then
				label(box, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -2, 0, 2),
					Size = UDim2.fromOffset(22, 22),
					TextSize = 16,
					Text = "✅",
				})
			end
		end

		label(dailyPage.Frame, {
			Position = UDim2.fromOffset(0, 262),
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = SUBTEXT,
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
	highlight.OutlineColor = Color3.new(1, 1, 1)
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
