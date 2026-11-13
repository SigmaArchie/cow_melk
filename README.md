# Cow Farm (cow_melk)

Roblox-Farming-Spiel: Kühe melken, Milch verkaufen, neue Kühe im Kuh-Shop kaufen, züchten und aus Kisten ziehen.
Der Code liegt in `src/` und wird mit [Rojo](https://rojo.space) nach Roblox Studio synchronisiert.
Alles Wichtige zum Spiel steht in [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).

## Tools installieren

Alle Tools sind in `rokit.toml` festgelegt (Rojo, Selene, StyLua, Wally):

```bash
rokit install
```

Rokit gibt es hier: https://github.com/rojo-rbx/rokit (`aftman.toml` wird nicht mehr gebraucht).

## Entwickeln

```bash
rojo serve
```

Dann in Roblox Studio im Rojo-Plugin auf **Connect** klicken. Nach Änderungen an `default.project.json` Rojo neu starten.
Eine Place-Datei bauen: `rojo build -o cow_melk.rbxlx`

## Prüfen (vor jedem Commit)

```bash
stylua src          # formatiert alles einheitlich (stylua.toml)
selene src          # Linter mit Roblox-Standardbibliothek (selene.toml)
```

Beim ersten `selene src` lädt Selene die Roblox-API herunter, dafür braucht es Internet.

## Pakete (Wally)

Pakete in `wally.toml` eintragen und `wally install` ausführen. Rojo legt sie dann automatisch ab:

- `Packages/` → `ReplicatedStorage.Packages` (Client und Server)
- `ServerPackages/` → `ServerStorage.ServerPackages` (nur Server)

Beide Ordner sind in `.gitignore`; solange es sie nicht gibt, baut Rojo einfach ohne sie.

## GitHub Actions

- `ci.yml` – bei jedem Push auf `main` und bei Pull Requests: `stylua --check`, `selene`, `rojo build`
- `deploy.yml` – nur von Hand: veröffentlicht das Spiel (braucht die Secrets `ROBLOX_API_KEY`, `UNIVERSE_ID`, `PLACE_ID`)

## Ordner

- `src/shared` → `ReplicatedStorage.Shared` – Spielwerte (`CowData`), Farben, Kuh-Modelle
- `src/server` → `ServerScriptService.Server` – alles, was der Server entscheidet (Daten, Kühe, Shop, Wetter)
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client` – Oberfläche, Melk-Minispiel, Animationen, Wetter-Effekte
- `assets` → `ReplicatedStorage.Assets` – Blender-Kuh als `.rbxm`
