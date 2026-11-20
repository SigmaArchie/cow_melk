-- AUTOMATISCH ERZEUGT von tools/make_tools.py – nicht von Hand ändern.
-- Größe (Size) und Mittelpunkt (Center, relativ zur Boden-Mitte des Werkzeugs) jedes Teils
-- aus assets/ToolParts.rbxm. Tools = welche Teile zu welchem Werkzeug gehören.
return {
	Parts = {
		Buerste_Rolle = { Size = Vector3.new(1.1000, 1.6000, 1.1000), Center = Vector3.new(-1.0500, 2.8500, 0.0000) },
		Buersten_Halter = { Size = Vector3.new(1.0600, 2.3750, 0.5000), Center = Vector3.new(-0.7300, 3.1125, 0.0000) },
		Buersten_Pfosten = { Size = Vector3.new(2.0750, 4.5400, 1.5000), Center = Vector3.new(-0.2875, 2.2700, 0.0000) },
		Futter = { Size = Vector3.new(1.2000, 0.6200, 1.2000), Center = Vector3.new(0.0000, 1.0100, 0.0000) },
		Futtereimer = { Size = Vector3.new(1.4500, 1.6250, 1.3600), Center = Vector3.new(0.0000, 0.8125, 0.0000) },
		Glocke = { Size = Vector3.new(0.8600, 0.9200, 0.8600), Center = Vector3.new(-1.3000, 2.9900, 0.0000) },
		Glocke_Band = { Size = Vector3.new(0.1200, 0.6050, 0.4700), Center = Vector3.new(-1.3000, 3.7325, 0.0000) },
		Glocke_Pfosten = { Size = Vector3.new(2.0000, 4.1200, 0.9000), Center = Vector3.new(-0.5500, 2.0600, 0.0000) },
		Schuppen_Dach = { Size = Vector3.new(17.9252, 5.3246, 13.8000), Center = Vector3.new(0.0000, 10.0777, 0.0000) },
		Schuppen_Glas = { Size = Vector3.new(15.5600, 2.0000, 6.8800), Center = Vector3.new(0.0000, 4.6000, 2.3400) },
		Schuppen_Rahmen = {
			Size = Vector3.new(16.7641, 11.9871, 12.6900),
			Center = Vector3.new(0.0000, 5.9935, 0.0450),
		},
		Schuppen_Schild = { Size = Vector3.new(6.0000, 1.4000, 0.3000), Center = Vector3.new(0.0000, 9.3000, 6.2000) },
		Schuppen_Tuer = { Size = Vector3.new(3.5500, 5.5000, 0.4650), Center = Vector3.new(0.0000, 2.7500, 5.9575) },
		Schuppen_Wand = { Size = Vector3.new(16.0000, 11.9800, 12.0000), Center = Vector3.new(0.0000, 6.0100, 0.0000) },
	},
	Tools = {
		Futtereimer = { "Futtereimer", "Futter" },
		Kuhglocke = { "Glocke_Pfosten", "Glocke_Band", "Glocke" },
		Buerste = { "Buersten_Pfosten", "Buersten_Halter", "Buerste_Rolle" },
		Schuppen = {
			"Schuppen_Wand",
			"Schuppen_Dach",
			"Schuppen_Rahmen",
			"Schuppen_Tuer",
			"Schuppen_Glas",
			"Schuppen_Schild",
		},
	},
}
