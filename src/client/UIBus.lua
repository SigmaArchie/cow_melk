-- UIBus.lua (ModuleScript, nur Client)
-- Kleine "Sprechanlage" zwischen den Client-Scripts, damit sich Fenster gegenseitig öffnen können.
--   UIBus.OpenPage:Fire("Daily")          -> MenuUI öffnet ein Fenster (Shop, Crates, Breeding, Daily, AutoMilker)
--   UIBus.ToggleInventory:Fire()          -> InventoryClient öffnet/schließt das Inventar
--   UIBus.ToggleGear:Fire()               -> GearClient öffnet/schließt das Werkzeug-Fenster
--   UIBus.StartPlacement:Fire(cowId)      -> InventoryClient startet den Platzier-Modus
--   UIBus.CloseOverlays:Fire()            -> alle großen Fenster schließen (z.B. vor einem Teleport)

local UIBus = {}

local function newSignal(name)
	local event = Instance.new("BindableEvent")
	event.Name = name
	UIBus[name] = event
end

newSignal("OpenPage")
newSignal("ToggleInventory")
newSignal("ToggleOverview")
newSignal("ToggleGear")
newSignal("StartPlacement")
newSignal("CloseOverlays")

return UIBus
