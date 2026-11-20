-- GearView.lua (ModuleScript, nur Client)
-- Zeigt ein Werkzeug-Modell (GearModels) als kleines 3D-Bild in der Oberfläche (ViewportFrame).
--   GearView.new(parent, gearType, props) -> ViewportFrame
--   props: Size, Position, AnchorPoint, LayoutOrder, ZIndex, Spin (dreht sich langsam, Standard: true)
-- Alle drehenden Bilder teilen sich EINE RenderStepped-Verbindung; unsichtbare werden übersprungen.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GearModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearModels"))

local GearView = {}

local spinning = {} -- [ViewportFrame] = { Camera, Center, Distance, Height, Angle }
local connection = nil

local function placeCamera(entry)
	local offset = Vector3.new(math.sin(entry.Angle), 0, math.cos(entry.Angle)) * entry.Distance
	local position = entry.Center + offset + Vector3.new(0, entry.Height, 0)
	entry.Camera.CFrame = CFrame.lookAt(position, entry.Center)
end

local function startLoop()
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(function(dt)
		for frame, entry in pairs(spinning) do
			if not frame.Parent then
				spinning[frame] = nil
			elseif frame.Visible and frame:FindFirstAncestorWhichIsA("LayerCollector") then
				entry.Angle += dt * 0.6
				placeCamera(entry)
			end
		end
	end)
end

function GearView.new(parent, gearType, props)
	props = props or {}
	local frame = Instance.new("ViewportFrame")
	frame.Name = "GearView"
	frame.BackgroundTransparency = 1
	frame.Size = props.Size or UDim2.fromOffset(90, 90)
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.LayoutOrder = props.LayoutOrder or 0
	frame.ZIndex = props.ZIndex or (parent:IsA("GuiObject") and parent.ZIndex or 1)
	frame.Ambient = Color3.fromRGB(170, 170, 170)
	frame.LightColor = Color3.fromRGB(255, 248, 235)
	frame.LightDirection = Vector3.new(-0.6, -1, -0.4)
	frame.Parent = parent

	local model = GearModels.Build(gearType, CFrame.new(), { Ghost = false })
	if not model then
		return frame
	end
	-- Partikel und Lichter zeigt ein ViewportFrame ohnehin nicht; drehende Teile (Tag "Spinner")
	-- bewegt WorldAnimator nur in der Welt, hier bleiben sie stehen
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("ParticleEmitter") or item:IsA("Light") then
			item:Destroy()
		elseif item:IsA("Model") then
			CollectionService:RemoveTag(item, "Spinner")
		end
	end
	model.Parent = frame

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = frame
	frame.CurrentCamera = camera

	local center, radius = GearModels.GetBounds(model)
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local entry = {
		Camera = camera,
		Center = center,
		Distance = distance,
		Height = distance * 0.35,
		Angle = math.rad(-35),
	}
	placeCamera(entry)
	if props.Spin ~= false then
		spinning[frame] = entry
		startLoop()
	end
	return frame
end

return GearView
