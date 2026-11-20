# Wer macht gerade was

Regeln dazu: [CLAUDE.md](CLAUDE.md). Kurz: **vor jeder Aufgabe** dieses Board auf `origin/main`
lesen, belegte Dateien nicht anfassen, eigene Aufgabe hier eintragen und pushen, *bevor* Code
geschrieben wird.

## Gerade in Arbeit

| Wer | Aufgabe | Branch | Belegte Dateien | Stand |
|---|---|---|---|---|
| Maxi | **Werkzeug-Shop** als 5. Shop am Marktplatz (beim Pavillon / Dorfbaum): Futtereimer (Kuh wächst schneller), Kuhglocke (mehr Mutations-Chance für Kühe in der Nähe), Bürste (eine Kuh kurz mehr Milch). Kaufen, auf die Weide stellen, wirkt eine Zeit lang. | noch nicht gepusht | *vermutet, Maxis Claude bitte korrigieren:* `CowData.lua`, `MapBuilder.server.lua`, `MenuUI.client.lua`, `CowManager.server.lua`, `DataService.lua`, `InventoryClient.client.lua`, `WorldAnimator.client.lua`, neue `Tool*`-Module | in Arbeit |
| Archie | Holz-Stil für Melk-Minispiel und Karte | `feature/holz-melken-karte` | `src/client/MilkingClient.client.lua`, `src/client/OverviewClient.client.lua`, `src/client/Theme.lua` | in Arbeit |

## Als Nächstes – Archie (stört den Werkzeug-Shop nicht)

1. **3D-Modelle für die Werkzeuge** in Blender: Futtereimer, Kuhglocke, Bürste und ein kleiner
   Werkzeug-Schuppen. Nur neue Dateien: `tools/make_tools.py`, `assets_src/tools/`,
   `assets/ToolParts.rbxm`, `src/shared/ToolMeshData.lua`.
   **Absprache mit Maxi:** Teile heißen `Futtereimer`, `Kuhglocke`, `Buerste`, `Schuppen` und
   liegen in `ReplicatedStorage.Assets.ToolParts`. Maxis Code nimmt sie, wenn es sie gibt,
   sonst baut er aus Parts.
2. **Holz-Stil für Melk-Minispiel, Karte und Tutorial** (Melken + Karte: in Arbeit): `MilkingClient.client.lua`,
   `OverviewClient.client.lua`, `TutorialClient.client.lua` (+ evtl. `Theme.lua`).
   Falls Maxi einen Tutorial-Schritt für Werkzeuge will: vorher hier absprechen.
3. **Funktionierende Sound-IDs suchen** (Melken, Eimer voll, Musik, Shop öffnen, Fanfare) und
   unten unter "Notizen" sammeln. In `CowData.lua` eintragen erst, wenn der Werkzeug-Shop gemergt ist.
4. **3D-Deko in Blender** (Bäume, Laternen, Bänke, Heuballen, Fässer, Trog, Zaunstück): erst nur
   die Modelle. Einbau in `MapBuilder` erst nach dem Werkzeug-Shop.

## Als Nächstes – Maxi

1. Werkzeug-Shop fertig machen (siehe oben), Branch früh pushen.
2. Werkzeuge im Platzier-Modus der Hotbar aufstellen, in `DataService` speichern, Wirkzeit über
   der Kuh/dem Werkzeug anzeigen (wie die Melk-Pause).
3. Danach: Sounds aus den Notizen in `CowData.lua` eintragen.

## Später (erst wenn beide Branches gemergt sind – betrifft fast alles)

- `CowManager.server.lua` in Module aufteilen (Melken, Zucht, Kisten, Plots, Inventar).
- Anfrage-Limit pro Spieler für alle Remotes (neues Modul `RateLimit.lua`).
- Deko-Modelle und Shop-Gebäude als Meshes in `MapBuilder` einbauen.
- Balancing: Auto-Melker ignoriert die Melk-Pause.

## Erledigt

- 3D-Modelle für die Werkzeuge + Schuppen, ToolModelBuilder, Achsen-Fix für Meshes (Archie, PR #4)
- 3D-Eimer + Schemel aus Blender, Holz-Farm-UI, Kisten-Fix (Archie, PR #2)
- Kuh kippt nicht mehr beim Umdrehen (Maxi, PR #3)
- Bauernhof-Karte umgebaut (PR #1)

## Notizen

- **Für Maxi – Werkzeug-Modelle benutzen** (PR #4 ist gemergt, `git pull origin main`):
  `ToolModelBuilder.Build("Futtereimer" | "Kuhglocke" | "Buerste" | "Schuppen", cframe)` gibt ein fertiges
  Modell zurück (PrimaryPart `Root` = Boden-Mitte, Schuppen-Tür zeigt nach -Z wie bei den Shops),
  `ToolModelBuilder.SetSign(schuppen, "WERKZEUGE")` beschriftet das Schild. Zum Animieren: `Buerste_Rolle`
  drehen, `Glocke` pendeln. Ohne `Assets.ToolParts` kommen Ersatz-Blöcke.
- Sound-IDs: …
