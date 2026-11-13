-- WeatherManager.server.lua
-- Wetter-Events für den ganzen Server (Daten: CowData.Weather / CowData.WeatherSettings):
--   Sonne -> nach PauseMin..PauseMax Sekunden ein zufälliges Event -> nach Duration Sekunden wieder Sonne.
-- Der Zustand steht als Attribut am Workspace (wird automatisch zu allen Clients übertragen):
--   workspace.Weather       = "Clear" | "Rain" | "Storm" | "Snow" | "StarNight"
--   workspace.WeatherEndsAt = os.time(), wann das Event endet (0 = kein Ende bekannt)
-- CowManager liest Weather beim Melken (Milch-Sorten), WeatherClient zeigt Regen, Schnee usw.
-- Zum Testen in Studio: im Server-Modus am Workspace das Attribut "Weather" von Hand ändern;
-- außerdem kommt in Studio das erste Event schon nach StudioFirstEvent Sekunden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local Settings = CowData.WeatherSettings
local rng = Random.new()

local function pickWeather()
	local total = 0
	for _, id in ipairs(CowData.WeatherOrder) do
		total += CowData.Weather[id].Weight
	end
	local roll = rng:NextNumber() * total
	for _, id in ipairs(CowData.WeatherOrder) do
		roll -= CowData.Weather[id].Weight
		if roll <= 0 then
			return id
		end
	end
	return CowData.WeatherOrder[1]
end

local function setWeather(id, duration)
	workspace:SetAttribute("Weather", id)
	workspace:SetAttribute("WeatherEndsAt", duration and os.time() + duration or 0)
end

setWeather("Clear")

task.spawn(function()
	local firstPause = RunService:IsStudio() and Settings.StudioFirstEvent or nil
	while true do
		task.wait(firstPause or rng:NextInteger(Settings.PauseMin, Settings.PauseMax))
		firstPause = nil

		-- jemand hat in Studio schon ein Wetter gesetzt -> nicht überschreiben
		if workspace:GetAttribute("Weather") == "Clear" then
			local id = pickWeather()
			local info = CowData.Weather[id]
			setWeather(id, info.Duration)
			DataService.NotifyAll(("%s %s! %s"):format(info.Icon, info.DisplayName, info.Hint), "rare")

			-- warten, bis das Event vorbei ist (oder in Studio von Hand geändert wurde)
			local endsAt = os.time() + info.Duration
			while os.time() < endsAt and workspace:GetAttribute("Weather") == id do
				task.wait(1)
			end
			if workspace:GetAttribute("Weather") == id then
				setWeather("Clear")
				DataService.NotifyAll("☀ Das Wetter ist wieder schön.", "info")
			end
		end
	end
end)
