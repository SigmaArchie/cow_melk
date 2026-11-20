-- WorldAnimator.client.lua
-- Alles, was sich in der Welt bewegt, läuft hier auf dem Client (flüssig, kein Netzwerkverkehr):
--   * Windmühlen-Flügel (Tag "Spinner"): drehen sich langsam, nach Serverzeit
--   * Kühe (Tag "Cow"): laufen auf ihrem Feld ein wenig herum (wohin, berechnet jeder Client gleich
--     aus Serverzeit + Kuh-ID, siehe CowData.CowWander), grasen, schweben, Kopf dreht, Schwanz wedelt,
--     Ohren flattern -> angewendet einmal pro Frame mit workspace:BulkMoveTo.
--     Beim Melken steht die Kuh genau auf ihrem Platz (dort stehen Schemel und Eimer).
--   * "Melken"-Prompt an der Kuh: nur beim Besitzer sichtbar und nicht während des Melkens
--   * Regenbogen-Kuh: sanfter Farbwechsel alle 3 Sekunden
--   * Shops: Hinweis "Klicken zum Öffnen" atmet ruhig, Verkäufer winkt
--   * Sounds: Hintergrund-Musik, Kühe muhen ab und zu

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Config = CowData.Config
local Wander = CowData.CowWander
local HashRoll = CowData.HashRoll
local localPlayer = Players.LocalPlayer

local random = Random.new()
local ANIMATION_DISTANCE = 160 -- weiter entfernte Kühe bleiben still (spart Leistung)
local MOO_DISTANCE = 90

local function loopTween(instance, duration, goal, style)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		goal
	)
	tween:Play()
	return tween
end

local function cameraPosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

------------------------------------------------------------------------
-- Drehende Teile (Tag "Spinner", z.B. Windmühlen-Flügel, Wetterhahn): drehen sich um die eigene
-- Z-Achse ihres Pivots, Winkel aus der Serverzeit (bei allen Spielern gleich).
-- Mit Attribut SwingAngle schwingen sie stattdessen hin und her (Kuhglocke).
------------------------------------------------------------------------
local SPIN_DISTANCE = 450
local spinners = {} -- [model] = { Pivot, Parts, Offsets, Speed }

local function registerSpinner(model)
	task.wait() -- Teile sind beim Hinzufügen evtl. noch nicht alle da
	-- nur echte Welt-Teile (BulkMoveTo geht nicht mit Teilen in ViewportFrames)
	if not model:IsDescendantOf(workspace) then
		return
	end
	local pivot = model:GetPivot()
	local entry = {
		Pivot = pivot,
		Parts = {},
		Offsets = {},
		Speed = model:GetAttribute("SpinSpeed") or 20,
		Swing = model:GetAttribute("SwingAngle"), -- gesetzt: hin und her schwingen statt drehen (Glocke)
	}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(entry.Parts, part)
			table.insert(entry.Offsets, pivot:ToObjectSpace(part.CFrame))
		end
	end
	spinners[model] = entry
end

for _, model in ipairs(CollectionService:GetTagged("Spinner")) do
	task.spawn(registerSpinner, model)
end
CollectionService:GetInstanceAddedSignal("Spinner"):Connect(function(model)
	task.spawn(registerSpinner, model)
end)
CollectionService:GetInstanceRemovedSignal("Spinner"):Connect(function(model)
	spinners[model] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	local camPos = cameraPosition()
	local parts, cframes = {}, {}
	for _, entry in pairs(spinners) do
		if (entry.Pivot.Position - camPos).Magnitude < SPIN_DISTANCE then
			local angle = entry.Swing and math.sin(now * entry.Speed) * entry.Swing or (now * entry.Speed) % 360
			local pivot = entry.Pivot * CFrame.Angles(0, 0, math.rad(angle))
			for i, part in ipairs(entry.Parts) do
				table.insert(parts, part)
				table.insert(cframes, pivot * entry.Offsets[i])
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

------------------------------------------------------------------------
-- Kühe
------------------------------------------------------------------------
local cows = {} -- [model] = state

local RAINBOW = {
	Color3.fromRGB(246, 128, 128),
	Color3.fromRGB(246, 178, 104),
	Color3.fromRGB(240, 224, 124),
	Color3.fromRGB(132, 208, 144),
	Color3.fromRGB(124, 182, 244),
	Color3.fromRGB(186, 144, 240),
}

local function newValue(state, initial)
	local value = Instance.new("NumberValue")
	value.Value = initial or 0
	table.insert(state.Instances, value)
	return value
end

local function stopCow(cow)
	local state = cows[cow]
	if not state then
		return
	end
	cows[cow] = nil
	state.Alive = false
	for _, tween in ipairs(state.Tweens) do
		tween:Cancel()
	end
	for _, instance in ipairs(state.Instances) do
		instance:Destroy()
	end
end

local function collect(container, relativeTo)
	local parts, offsets = {}, {}
	for _, part in ipairs(container:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
			table.insert(offsets, relativeTo:ToObjectSpace(part.CFrame))
		end
	end
	return parts, offsets
end

------------------------------------------------------------------------
-- Herumlaufen: Die Zeit ist in Abschnitte (Wander.Period) geteilt. In jedem Abschnitt k dreht sich
-- die Kuh erst zum nächsten Punkt, läuft hin und grast dann. Die Punkte kommen aus
-- CowData.HashRoll(Kuh-ID, k) -> jeder Client rechnet für jede Kuh exakt dasselbe aus.
------------------------------------------------------------------------
local function smooth(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function wrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Ziel-Punkt (Versatz vom Platz der Kuh) am Ende von Abschnitt k.
-- Manchmal bleibt sie stehen: dann gilt der Punkt eines früheren Abschnitts.
local function wanderPoint(state, k)
	for depth = 0, 4 do
		local index = k - depth
		if depth == 4 or HashRoll(state.Seed, index, 3) >= Wander.StayChance then
			local angle = HashRoll(state.Seed, index, 1) * math.pi * 2
			local distance = state.Radius * math.sqrt(HashRoll(state.Seed, index, 2))
			return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end
	end
	return Vector3.zero
end

-- Blickrichtung nach Abschnitt k: Richtung des letzten echten Wegs (Kuh schaut nach -Z, wenn 0)
local function wanderHeading(state, k)
	for depth = 0, 4 do
		local delta = wanderPoint(state, k - depth) - wanderPoint(state, k - depth - 1)
		if delta.Magnitude > 0.3 then
			return math.atan2(-delta.X, -delta.Z)
		end
	end
	return 0
end

-- Wo die Kuh laut Plan gerade ist: Versatz, Blickrichtung, läuft sie?, Kopf senken (0..1)
local function wanderPose(state, now)
	local period = Wander.Period
	local t = now + state.TimeOffset
	local k = math.floor(t / period)
	if state.PlanK ~= k then
		state.PlanK = k
		state.From = wanderPoint(state, k - 1)
		state.To = wanderPoint(state, k)
		state.HeadingFrom = wanderHeading(state, k - 1)
		local delta = state.To - state.From
		state.HeadingTo = delta.Magnitude > 0.3 and math.atan2(-delta.X, -delta.Z) or state.HeadingFrom
		state.WalkTime = math.min(delta.Magnitude / state.Speed, period - Wander.TurnTime - 1)
		state.Grazes = HashRoll(state.Seed, k, 4) < 0.6
	end
	local u = t - k * period
	local turnEnd = Wander.TurnTime
	local walkEnd = turnEnd + state.WalkTime
	if u < turnEnd then
		local turn = wrapAngle(state.HeadingTo - state.HeadingFrom)
		return state.From, state.HeadingFrom + turn * smooth(u / turnEnd), false, 0
	elseif u < walkEnd and state.WalkTime > 0.05 then
		return state.From:Lerp(state.To, smooth((u - turnEnd) / state.WalkTime)), state.HeadingTo, true, 0
	end
	local graze = 0
	if state.Grazes then
		graze = smooth((u - walkEnd - 0.4) / 0.6) * smooth((period - u - 0.2) / 0.6)
	end
	return state.To, state.HeadingTo, false, graze
end

-- "Melken"-Prompt: nur der Besitzer sieht ihn, und nicht während gemolken wird
local function setupMilkPrompt(cow, torso)
	local prompt = torso:WaitForChild("MilkPrompt", 5)
	if not prompt then
		return
	end
	local function update()
		prompt.Enabled = cow:GetAttribute("OwnerUserId") == localPlayer.UserId
			and cow:GetAttribute("BeingMilked") ~= true
	end
	update()
	cow:GetAttributeChangedSignal("BeingMilked"):Connect(update)
end

-- Aufrechter Bezugspunkt der Kuh: Boden unter der Kuh-Mitte, nur um die Hochachse gedreht.
-- Der Server schreibt ihn als Attribut "HomeCFrame" an die Kuh. Den Model-Pivot NICHT direkt
-- nehmen: beim Blender-Modell kann er schief sein (gedrehtes Mesh) – dann würde sich die Kuh beim
-- Umdrehen um eine schräge Achse drehen und umkippen.
local function uprightBase(cow)
	local home = cow:GetAttribute("HomeCFrame")
	if typeof(home) == "CFrame" then
		return home
	end
	local pivot = cow:GetPivot()
	local look = pivot.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pivot.Position, pivot.Position + look.Unit)
end

local function startCow(cow)
	if cows[cow] then
		return
	end
	local torso = cow:WaitForChild("Torso", 10)
	local headGroup = cow:WaitForChild("HeadGroup", 10)
	local tailGroup = cow:WaitForChild("TailGroup", 10)
	local earLeft = cow:WaitForChild("EarLeft", 10)
	local earRight = cow:WaitForChild("EarRight", 10)
	if not (torso and headGroup and tailGroup and earLeft and earRight) then
		return
	end

	task.spawn(setupMilkPrompt, cow, torso)

	-- neue Kühe fallen erst noch vom Himmel (Server-Animation) -> warten, bis sie still steht
	task.wait(1.2)
	for _ = 1, 12 do
		local before = torso.Position
		task.wait(0.25)
		if (torso.Position - before).Magnitude < 0.01 then
			break
		end
	end
	if not cow:IsDescendantOf(workspace) then
		return
	end

	local base = uprightBase(cow)
	local headPivot = headGroup:GetPivot()
	local state = {
		Alive = true,
		Base = base,
		Tweens = {},
		Instances = {},
		Torso = torso,
		Rested = false,
		-- Herumlaufen (siehe wanderPose)
		Seed = CowData.HashString(tostring(cow:GetAttribute("CowId") or cow:GetFullName())),
		Radius = cow:GetAttribute("WanderRadius") or Wander.MinRadius,
		Offset = Vector3.zero, -- aktuell angezeigter Versatz vom Platz
		Heading = 0, -- aktuell angezeigte Blickrichtung (Bogenmaß)
		Active = false, -- wurde im letzten Frame bewegt?
	}
	state.TimeOffset = HashRoll(state.Seed, 7, 9) * Wander.Period
	-- Kälber (großer Radius) trippeln etwas schneller
	state.Speed = Wander.Speed * (state.Radius > 3.5 and 1.3 or 1)

	-- Körper = alles, was nicht in einer der Gruppen steckt
	state.BodyParts, state.BodyOffsets = {}, {}
	for _, child in ipairs(cow:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(state.BodyParts, child)
			table.insert(state.BodyOffsets, base:ToObjectSpace(child.CFrame))
		end
	end
	state.HeadRel = base:ToObjectSpace(headPivot)
	state.HeadParts, state.HeadOffsets = collect(headGroup, headPivot)
	state.TailRel = base:ToObjectSpace(tailGroup:GetPivot())
	state.TailParts, state.TailOffsets = collect(tailGroup, tailGroup:GetPivot())
	state.EarLRel = headPivot:ToObjectSpace(earLeft:GetPivot())
	state.EarLParts, state.EarLOffsets = collect(earLeft, earLeft:GetPivot())
	state.EarRRel = headPivot:ToObjectSpace(earRight:GetPivot())
	state.EarRParts, state.EarROffsets = collect(earRight, earRight:GetPivot())

	-- Animationswerte (alle per TweenService)
	state.Float = newValue(state, 0) -- Studs nach oben
	state.HeadYaw = newValue(state, -15) -- Grad
	state.Tail = newValue(state, -20) -- Grad
	state.Ear = newValue(state, 0) -- Grad

	local phase = random:NextNumber(0, 1.5)
	task.delay(phase, function()
		if not state.Alive then
			return
		end
		-- schweben: 0.2 Studs hoch und runter alle 1.5 s
		table.insert(state.Tweens, loopTween(state.Float, 1.5, { Value = 0.2 }))
		-- Kopf: langsam ±15° alle 3 s
		table.insert(state.Tweens, loopTween(state.HeadYaw, 3, { Value = 15 }))
		-- Schwanz: ±20° in 0.8 s (schnell = niedlich)
		table.insert(state.Tweens, loopTween(state.Tail, 0.4, { Value = 20 }))
	end)

	-- Ohren flattern alle 4 s
	task.spawn(function()
		task.wait(random:NextNumber(0, 4))
		while state.Alive do
			for _ = 1, 2 do
				local up = TweenService:Create(state.Ear, TweenInfo.new(0.12), { Value = 25 })
				up:Play()
				up.Completed:Wait()
				local down = TweenService:Create(state.Ear, TweenInfo.new(0.12), { Value = 0 })
				down:Play()
				down.Completed:Wait()
			end
			task.wait(4)
		end
	end)

	-- Regenbogen: sanfter Farbwechsel (alle 3 s, mit langem Übergang)
	if cow:GetAttribute("Rarity") == "Rainbow" then
		local tintParts = {}
		for _, part in ipairs(cow:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("Tint") then
				table.insert(tintParts, part)
			end
		end
		task.spawn(function()
			local index = 1
			while state.Alive do
				index = index % #RAINBOW + 1
				for _, part in ipairs(tintParts) do
					TweenService:Create(part, TweenInfo.new(2.8, Enum.EasingStyle.Sine), { Color = RAINBOW[index] })
						:Play()
				end
				task.wait(1)
			end
		end)
	end

	-- Muhen alle 15-30 s (nur wenn man in der Nähe ist)
	if Config.MooSoundId ~= "" then
		task.spawn(function()
			task.wait(random:NextNumber(2, 20))
			while state.Alive do
				if (cameraPosition() - torso.Position).Magnitude < MOO_DISTANCE then
					local moo = Instance.new("Sound")
					moo.SoundId = Config.MooSoundId
					moo.Volume = 0.6
					moo.PlaybackSpeed = random:NextNumber(0.9, 1.15)
					moo.RollOffMaxDistance = MOO_DISTANCE
					moo.Parent = torso
					moo:Play()
					moo.Ended:Connect(function()
						moo:Destroy()
					end)
				end
				task.wait(random:NextNumber(15, 30))
			end
		end)
	end

	cows[cow] = state
end

for _, cow in ipairs(CollectionService:GetTagged("Cow")) do
	task.spawn(startCow, cow)
end
CollectionService:GetInstanceAddedSignal("Cow"):Connect(function(cow)
	task.spawn(startCow, cow)
end)
CollectionService:GetInstanceRemovedSignal("Cow"):Connect(stopCow)

local function addGroup(parts, cframes, groupParts, groupOffsets, pivot)
	for i, part in ipairs(groupParts) do
		table.insert(parts, part)
		table.insert(cframes, pivot * groupOffsets[i])
	end
end

RunService.Heartbeat:Connect(function(dt)
	local camPos = cameraPosition()
	local now = workspace:GetServerTimeNow()
	local parts, cframes = {}, {}

	for cow, state in pairs(cows) do
		if not cow.Parent then
			stopCow(cow)
		elseif (state.Base.Position - camPos).Magnitude >= ANIMATION_DISTANCE then
			state.Active = false
		else
			local beingMilked = cow:GetAttribute("BeingMilked") == true
			local graze = 0

			-- Während des Melkens steht die Kuh genau auf ihrem Platz und der Körper still
			-- (die Zitzen werden dann vom Melk-Script bewegt)
			local root
			if beingMilked then
				state.Offset, state.Heading = Vector3.zero, 0
				root = state.Base
				if not state.Rested then
					state.Rested = true
					addGroup(parts, cframes, state.BodyParts, state.BodyOffsets, root)
				end
			else
				state.Rested = false
				local targetOffset, targetHeading, walking
				targetOffset, targetHeading, walking, graze = wanderPose(state, now)
				if not state.Active then
					-- gerade erst in Sichtweite gekommen: direkt an die richtige Stelle
					state.Offset, state.Heading = targetOffset, targetHeading
				else
					-- sonst nachlaufen (z.B. nach dem Melken zurück in den Plan), nie springen
					local diff = targetOffset - state.Offset
					local step = dt * state.Speed * 2.5
					state.Offset = diff.Magnitude > step and state.Offset + diff.Unit * step or targetOffset
					local turn = wrapAngle(targetHeading - state.Heading)
					local maxTurn = dt * math.rad(240)
					state.Heading = state.Heading + math.clamp(turn, -maxTurn, maxTurn)
				end
				-- beim Laufen leicht wippen und schaukeln
				local bob, roll = 0, 0
				if walking then
					local stepPhase = now * 2 * math.pi * 1.8
					bob = math.abs(math.sin(stepPhase)) * 0.12
					roll = math.sin(stepPhase) * math.rad(1.5)
				end
				root = state.Base
					* CFrame.new(state.Offset)
					* CFrame.Angles(0, state.Heading, 0)
					* CFrame.new(0, state.Float.Value + bob, 0)
					* CFrame.Angles(0, 0, roll)
				addGroup(parts, cframes, state.BodyParts, state.BodyOffsets, root)
			end
			state.Active = true

			-- Kopf: hin und her schauen, beim Grasen nach unten
			local head = root
				* state.HeadRel
				* CFrame.Angles(0, math.rad(state.HeadYaw.Value) * (1 - graze), 0)
				* CFrame.Angles(math.rad(-28) * graze, 0, 0)
			addGroup(parts, cframes, state.HeadParts, state.HeadOffsets, head)

			local ear = math.rad(state.Ear.Value)
			addGroup(
				parts,
				cframes,
				state.EarLParts,
				state.EarLOffsets,
				head * state.EarLRel * CFrame.Angles(0, 0, -ear)
			)
			addGroup(
				parts,
				cframes,
				state.EarRParts,
				state.EarROffsets,
				head * state.EarRRel * CFrame.Angles(0, 0, ear)
			)

			local tail = root * state.TailRel * CFrame.Angles(0, 0, math.rad(state.Tail.Value))
			addGroup(parts, cframes, state.TailParts, state.TailOffsets, tail)
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

------------------------------------------------------------------------
-- Licht-Budget: nur Kühe in der Nähe leuchten (jedes PointLight kostet Leistung)
--   * Legendary / Golden / Rainbow ("besondere" Kühe): bis 8 Lichter, bis 140 Studs
--   * Rare / Epic / Ghost: nur die 5 nächsten, bis 70 Studs
-- Die Lichter kommen vom Server (CowModelBuilder); hier werden sie nur an- und ausgeschaltet.
------------------------------------------------------------------------
local SPECIAL_LIGHT_RARITIES = {
	Legendary = true,
	Golden = true,
	Rainbow = true,
	Thunder = true,
	Moon = true,
	Dragon = true,
	Crystal = true,
}
local SPECIAL_LIGHT_COUNT, SPECIAL_LIGHT_DISTANCE = 8, 140
local NORMAL_LIGHT_COUNT, NORMAL_LIGHT_DISTANCE = 5, 70

local function applyLightBudget(entries, count, distance)
	table.sort(entries, function(a, b)
		return a.Distance < b.Distance
	end)
	for index, entry in ipairs(entries) do
		entry.Light.Enabled = index <= count and entry.Distance < distance
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		local camPos = cameraPosition()
		local special, normal = {}, {}
		for cow, state in pairs(cows) do
			if cow.Parent then
				if state.Light == nil then
					state.Light = state.Torso:FindFirstChildOfClass("PointLight") or false
				end
				if state.Light then
					local entry = { Light = state.Light, Distance = (state.Base.Position - camPos).Magnitude }
					table.insert(SPECIAL_LIGHT_RARITIES[cow:GetAttribute("Rarity")] and special or normal, entry)
				end
			end
		end
		applyLightBudget(special, SPECIAL_LIGHT_COUNT, SPECIAL_LIGHT_DISTANCE)
		applyLightBudget(normal, NORMAL_LIGHT_COUNT, NORMAL_LIGHT_DISTANCE)
	end
end)

------------------------------------------------------------------------
-- Shops: Hinweis "Klicken zum Öffnen" atmet ruhig, Verkäufer winkt
------------------------------------------------------------------------
local function animateShop(building)
	local billboard = building:WaitForChild("SignAnchor", 10)
	billboard = billboard and billboard:WaitForChild("ShopBillboard", 10)
	local card = billboard and billboard:WaitForChild("Card", 5)
	if card then
		local bounce = card:FindFirstChild("Bounce")
		if bounce then
			bounce.Scale = 1
			loopTween(bounce, 1.2, { Scale = 1.04 }, Enum.EasingStyle.Sine) -- ruhiges Atmen statt Hüpfen
		end
		local hint = card:FindFirstChild("ClickHint")
		local hintShadow = card:FindFirstChild("ClickHintShadow")
		if hint then
			loopTween(hint, 1.2, { TextTransparency = 0.35 }, Enum.EasingStyle.Sine)
		end
		if hintShadow then
			loopTween(hintShadow, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Linear)
		end
	end
end

for _, building in ipairs(CollectionService:GetTagged("ShopBuilding")) do
	task.spawn(animateShop, building)
end
CollectionService:GetInstanceAddedSignal("ShopBuilding"):Connect(function(building)
	task.spawn(animateShop, building)
end)

local function animateShopKeeper(npc)
	local arm = npc:WaitForChild("RightArm", 10)
	if not arm then
		return
	end
	local home = arm.CFrame
	local shoulder = home * CFrame.new(0, 0.9, 0)
	local angle = Instance.new("NumberValue")
	angle.Value = 130
	angle.Changed:Connect(function(value)
		if arm.Parent then
			arm.CFrame = shoulder * CFrame.Angles(0, 0, math.rad(value)) * CFrame.new(0, -0.9, 0)
		end
	end)
	-- winken: Arm hoch und hin und her
	loopTween(angle, 0.35, { Value = 165 })
	npc.Destroying:Connect(function()
		angle:Destroy()
	end)
end

for _, npc in ipairs(CollectionService:GetTagged("ShopKeeper")) do
	task.spawn(animateShopKeeper, npc)
end
CollectionService:GetInstanceAddedSignal("ShopKeeper"):Connect(function(npc)
	task.spawn(animateShopKeeper, npc)
end)

------------------------------------------------------------------------
-- Hintergrund-Musik
------------------------------------------------------------------------
if Config.AmbientSoundId ~= "" then
	local ambient = Instance.new("Sound")
	ambient.Name = "FarmAmbient"
	ambient.SoundId = Config.AmbientSoundId
	ambient.Looped = true
	ambient.Volume = 0.25
	ambient.Parent = SoundService
	ambient:Play()
end

------------------------------------------------------------------------
-- Eimer tragen: solange der EIGENE Charakter einen Eimer trägt (Model "HeldBucket", kommt vom Server),
-- läuft die Roblox-Halteanimation "toolnone" – rechter Arm nach vorne, wie beim Halten eines Tools.
-- Animationen des eigenen Charakters sehen alle anderen Spieler automatisch.
------------------------------------------------------------------------
local TOOLNONE_R15 = "rbxassetid://507768375" -- Standard-Animationen von Roblox (Animate-Script)
local TOOLNONE_R6 = "rbxassetid://182393478"

local function holdAnimationId(character, humanoid)
	-- am liebsten die aus dem Animate-Script des Charakters (passt zu Rig und Animations-Paket)
	local animate = character:FindFirstChild("Animate")
	local folder = animate and animate:FindFirstChild("toolnone")
	local animation = folder and folder:FindFirstChildOfClass("Animation")
	if animation and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return humanoid.RigType == Enum.HumanoidRigType.R6 and TOOLNONE_R6 or TOOLNONE_R15
end

local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animator then
		return
	end
	local track = nil

	local function update()
		local holding = character:FindFirstChild("HeldBucket") ~= nil
		if holding and not track then
			local animation = Instance.new("Animation")
			animation.AnimationId = holdAnimationId(character, humanoid)
			local ok, result = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and result then
				track = result
				track.Priority = Enum.AnimationPriority.Action -- über Laufen/Stehen, nur der rechte Arm
				track.Looped = true
				track:Play(0.2)
			else
				warn("[WorldAnimator] Halteanimation konnte nicht geladen werden:", result)
			end
		elseif not holding and track then
			track:Stop(0.2)
			track = nil
		end
	end

	character.ChildAdded:Connect(function(child)
		if child.Name == "HeldBucket" then
			update()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child.Name == "HeldBucket" then
			task.defer(update) -- beim Wechseln kommt gleich der nächste Eimer -> Animation weiterlaufen lassen
		end
	end)
	update()
end

localPlayer.CharacterAdded:Connect(watchCharacter)
if localPlayer.Character then
	task.spawn(watchCharacter, localPlayer.Character)
end
