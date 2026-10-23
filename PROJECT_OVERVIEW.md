# Cow Farm – Projektübersicht (Roblox, Rojo)

Stand: 16.10.2026 (Pass 1: Bugfixes + UI-Design-System, Pass 2: Welt, Shops, Farmen, Kühe)

Roblox-Farming-Simulator "Cow Farm": Kühe melken (Minispiel), Milch verkaufen, mehr Kühe kaufen / züchten / aus Kisten ziehen, Kühe auf der eigenen Farm in einem Raster aufstellen. Kein Schlachten, keine Fusion. Code in Luau, synchronisiert mit **Rojo 7.7.1** (Tools über rokit: `rojo`, `selene`). Alle Texte im Spiel und alle Code-Kommentare sind **Deutsch**. Schulprojekt (5. Klasse, GD).

Status: `rojo build` fehlerfrei, `selene src` 0 Fehler / 0 Warnungen. In Studio gespielt wurde zuletzt vor der UI-Überarbeitung (Shops öffnen, Tutorial). Das neue Theme (HUD, Fenster, Melk-Minispiel) und die neue Welt (Shops, Farmen, Kuh-Beschriftungen, Effekte) sind **noch nicht in Studio geprüft** – in Pass 1 und 2 gab es keine Studio-Verbindung.

Starten: im Projektordner `rojo serve`, in Studio Rojo-Plugin → Connect (localhost:34872). Nach Änderungen an `default.project.json` Rojo neu starten.

## Ordnerstruktur

```
default.project.json        Rojo-Baum
rokit.toml / selene.toml    Tools (rojo, selene; std = "roblox")
tools/export_cow.py         Blender-Script: exportiert nur die Kuh-Teile als FBX
assets_src/CowModell.fbx    exportierte Kuh (33 Teile); die .blend-Datei liegt NICHT im Repo
assets/CowModel.rbxm        -> ReplicatedStorage.Assets.CowModel (Blender-Kuh, 9,8 KB; Inhalt noch nicht in Studio geprüft)
src/shared/  -> ReplicatedStorage.Shared
  CowData.lua               alle Spielwerte, Seltenheiten, Zucht, Kisten, Karte, Shops, Sounds, Plot-/Raster-Funktionen
  Palette.lua               gemeinsame Farben, Schriften, Welt- und Seltenheitsfarben (Client UND Server; Theme.lua liest hier)
  CowModelBuilder.lua       baut Kuh (Blender-Modell oder Ersatz aus Parts), Schemel, Eimer, Seltenheits-Effekte
src/server/  -> ServerScriptService.Server
  DataService.lua           DataStore laden/speichern + API für alle Server-Scripts
  PlayerDataManager.server  Laden/Speichern/Autosave, Starter-Kuh, TutorialDone
  CowManager.server         Plots + Raster, Kühe, Melken, Inventar-Aktionen, Teleport, Verkaufen, Shop, Kisten, Zucht, Auto-Melker, Robux
  LoginStreak.server        Tagesbonus, 7 Tage am Stück -> Rainbow Cow
  MapBuilder.server         Süd-Platz, Allee, 2 Förderbänder, Nord-Markt, 4 Shop-Gebäude mit NPC
src/client/  -> StarterPlayerScripts.Client
  Theme.lua                 EIN UI-Stil für alles (Farben, Schrift, Abstände, Knöpfe, Fenster, Balken, Abzeichen, Kuh-Karten, Meldungen, Symbole, Skalierung)
  UIBus.lua                 Signale zwischen Client-Scripts (Fenster öffnen sich gegenseitig)
  CoinDisplay.client        HUD (ScreenGui "HUD"): Coins/Milch, Seitenknöpfe, Meldungen, VERKAUFEN
  InventoryClient.client    Hotbar, Fenster "MEINE KÜHE", Platzier-Modus, Kuh-Menü
  OverviewClient.client     Fenster "KARTE" mit gezeichneter Karte + Reisen
  MenuUI.client             Fenster Kuh-Shop, Kisten, Zucht-Stall, Tagesbonus, Auto-Melker (ScreenGui "MenuUI", Fenster "Window")
  MilkingClient.client      Melk-Minispiel
  TutorialClient.client     Einführung für neue Spieler
  WorldAnimator.client      Welt-Animationen (Förderbänder, Kühe, Shops) + Sounds
```

`default.project.json` legt außerdem an: `ReplicatedStorage.Remotes` (alle Remotes), `ReplicatedStorage.Assets`, `Workspace.CowFarmLayout.Plots`, `Workspace.Baseplate`.

## Remotes (ReplicatedStorage.Remotes)

| Name | Typ | Richtung | Zweck |
|---|---|---|---|
| SellMilk | RE | C→S | ganze Milch verkaufen |
| BuyCow | RF | C→S | (rarity) → ok, msg |
| OpenCrate | RF | C→S | (crateId, payWithRobux) → ok, rarity/msg |
| StartBreeding | RF | C→S | (cowIdA, cowIdB) → ok, readyAt/msg |
| GetInventory | RF | C→S | Coins, Milk, Cows[] (mit Slot/Hotbar/Stored), Breeding, HotbarSize, CellCount … |
| CowAction | RF | C→S | (action, cowId, arg): `milk`, `pickup`, `place` (arg = Feld), `hotbar` (arg = Platz), `store` |
| TeleportTo | RE | C→S | "Farm" oder Page-Name eines Shops |
| BuyAutoMilker | RE | C→S | Gamepass-Kaufdialog |
| MilkPull / StopMilking | RE | C→S | Melk-Zug ("Left"/"Right") / abbrechen |
| TutorialDone | RE | C→S | Tutorial als gesehen speichern |
| MilkingStarted / MilkingProgress / MilkingEnded | RE | S→C | Melk-Minispiel |
| CowClicked | RE | S→C | eigene Kuh angeklickt → Menü (Melken/Aufheben) |
| OpenShop | RE | S→C | Shop-Gebäude angeklickt → Fenster öffnen |
| Notify | RE | S→C | (text, kind) kind = info/success/error/rare |
| InventoryChanged | RE | S→C | Client lädt Inventar neu |

Spieler-Attribute (Server setzt sie): `Coins`, `Milk`, `CowCount`, `LoginStreak`, `TutorialDone`, `HasAutoMilker`, `PlotSlot`. Plus leaderstats `Coins`, `Kühe`.

## Daten (DataStore "CowFarm_PlayerData_v1", Key "Player_<UserId>")

```lua
{ Version=1, Coins=100, Milk=0, TotalMilk=0,
  Cows = { c1 = { Id, Rarity, Name, Obtained, MilkReadyAt,
                  Slot (Feld 1-36) | Hotbar (1-6) | Stored (true = Lager) } },
  NextCowId, Breeding = {ParentA, ParentB, StartedAt, ReadyAt} | nil,
  LoginStreak = {Streak, LastDay, Best}, Receipts = {[PurchaseId]=time},
  ReceivedStarterCow, TutorialDone }
```
Laden mit 3 Versuchen, fehlende Felder werden aufgefüllt; Speichern erst NACH allen PlayerRemoving-Handlern (`task.defer`), damit z.B. Milch aus einem abgebrochenen Melken noch gespeichert wird; alte Kühe ohne Ort werden beim Laden automatisch auf freie Felder verteilt. Studio ohne API-Zugriff → Testdaten (nicht gespeichert). Live: bei Ladefehler Kick.

## Spielmechanik (Werte in CowData.lua)

- Start: 100 Coins + Gratis-Common-Kuh. Milch = 2 Coins pro Liter. Max. 40 Kühe insgesamt (ein laufendes Kalb zählt als belegter Platz; Robux-Kisten und Login-Bonus ignorieren das Limit bewusst); 36 Felder pro Farm, 6 Hotbar-Plätze, Rest im Lager.
- Seltenheiten (Milch pro Zug / Melk-Pause in s / Shoppreis): Common 2/20/100 · Uncommon 5/25/600 · Rare 12/30 · Epic 30/45 · Legendary 75/60 · Special: Golden 200 · Rainbow 160 · Ghost 130.
- Kühe bekommen: Kuh-Shop (Common, Uncommon), Zucht, Kisten (Holzkiste 500 Coins, Silberkiste 3000 Coins oder Robux, Premium-Kiste nur Robux mit 5 % Ghost).
- Zucht nach Durchschnitt der Eltern-Stufen; 2x Legendary: 1 % Golden (nur bei 2 echten Legendary). 5–20 Min, läuft auch offline.
- Rainbow Cow nur durch 7-Tage-Login-Streak. Tagesbonus = 25 × Tag (1–7).
- Auto-Melker (Gamepass): alle 3 s Milch von jeder Kuh, die auf der Farm steht.
- **Platzhalter:** `AutoMilkerGamePassId = 0`, `Crates.Super.ProductId = 0`, `Crates.Premium.ProductId = 0`, `MilkingAnimationId = 0`.

## Karte

- **Süd-Platz** (z −100..0): Milch-Brunnen, Spawn, "COW FARM"-Bogen, Steinwege (Eingang → Brunnen, Türen → Brunnen), Blumenbeete, Bänke, Laternen, Bäume, **Kuh-Shop** und **Zucht-Stall**.
- **2 Förderbänder** in der Allee (Nord / Süd, 36 Studs/s): unsichtbares Band mit `AssemblyLinearVelocity`; 6 Kacheln à 10×0.5×50 bewegt der Client per Heartbeat; Gehäuse an den Enden. Unverändert.
- **Nord-Markt** (z ≈ 350..450): **Kisten** und **Auto-Melker**, gleiche Deko wie der Süd-Platz.
- **Shop-Gebäude** (Daten in `CowData.Map.Shops`, Bau in `MapBuilder`, je ein Stil): Kuh-Shop = Scheune (Gambrel-Dach, Scheunentore), Kisten = offener Marktstand mit gestreiftem Dach und Kistenstapeln, Zucht-Stall = gemütlicher Stall (Blumenkästen, Heu, Trog), Auto-Melker = Werkstatt aus Metall mit Silo und Schornstein. Alle: Grundfläche ca. 20×16, Tür vorne (−Z), kleines Holzschild an der Wand (Symbol + Name), winkender NPC mit Strohhut, kleiner Hinweis "Klicken zum Öffnen" (Palette, atmet ruhig), Klick → `OpenShop`, Teleport-Punkt 9 Studs vor der Tür.
- **Hügel** (`CowFarmLayout.Hills`) nur am Kartenrand (|x| > ~450 bzw. z < −170 / z > 600), nie unter Farmen, Wegen, Bändern oder Spawn.
- **Farmen** links/rechts der Allee (3 Reihen pro Seite, ab Spieler 7 weiter außen): Wiese, Steinkante, weißer Zaun, Torbogen mit Holz-Namensschild (Part `Sign`, vom Tutorial gebraucht) und Laternen, Weg, Deko VOR der Kuhfläche (Blumenbeete, Heuballen, Fässer, Trog; lokal z > 28), Heu in der hinteren Ecke, **Milch-Verkaufsstation** (Podest, Theke, Preistafel, Kasse, Kannen, Schild; ProximityPrompt F), **Raster mit 36 Feldern** (Kühe stehen lokal in z −50..22, dort steht nichts). Jede Kuh hat Schemel, Eimer und blaue Melk-Platte.

## Kuhmodell & Animation

- `CowModelBuilder.BuildCow` nimmt `ReplicatedStorage.Assets.CowModel` (Blender-Kuh), wenn vorhanden: erkennt Teile an den Blender-Namen (Koerper, Kopf, Zitze_…, Fleck_…), dreht, skaliert auf 6.4 Studs, färbt pro Seltenheit. Sonst Ersatz-Kuh aus Parts (rund, niedlich).
- Gruppen `HeadGroup`, `EarLeft`, `EarRight`, `TailGroup`; Tag "Cow". WorldAnimator: schweben, Kopf ±15°, Schwanz wedelt, Ohren flattern, ab und zu umdrehen; nur in < 160 Studs; Regenbogen-Kuh wechselt jede Sekunde die Farbe.
- Effekte je Seltenheit (bewusst zurückhaltend, wegen vieler Kühe): Common keine · Uncommon wenige grünliche Funken · Rare kleines blaues Licht · Epic lila Licht + wenige Partikel · Legendary warmes Gold-Licht + wenige Funken · Golden Gold-Licht, wenige Münz-Partikel, dünner Strahl · Rainbow sanftes Licht, zarte Farbpartikel, Farbwechsel alle 3 s · Ghost grünlicher Dunst, durchsichtig. Neue Kuh fällt vom Himmel mit dezentem Konfetti.
- Beschriftungen an der Kuh (Server, `Palette`): Namensschild (Name, Seltenheit in Seltenheitsfarbe, Status "Bereit" / "Pause m:ss" / "Zucht m:ss" / "Wird gemolken"), Pop-ups "+X Milch" (Creme) und "+X Coins" (Gold), Melk-Platte "Melken".
- `assets/CowModel.rbxm` (Modell `CowModel`, MeshParts `Koerper`, `Kopf`, `Zitze_*`, `Ohr_*`, `Schwanz*`, `Schnauze`, `Euter`, `Fleck*`, `Huf*`, `Bein*`, `Auge_*`, `Horn*`; verweist auf eine Mesh-ID aus Roblox): wird benutzt, wenn `Koerper` und `Kopf` gefunden werden; bei Fehlern oder fehlendem Modell baut `CowModelBuilder` die Ersatz-Kuh aus Parts. Ob die Mesh-ID im Spiel lädt, ist ungeprüft.

## Melk-Minispiel

Kuh anklicken → Menü "Melken" (oder auf die blaue Platte laufen). Server teleportiert auf den Schemel. Panel mit Kuhgesicht, Fortschrittsbalken, Eimer füllt sich, ◄ ► bzw. Q/E (Controller L1/R1, Aufstehen = B) abwechselnd; falsche Seite = 1 Zug weniger. Nach 10 Zügen: Eimer kippt, "+X MILCH!", Kuh bekommt Pause (Timer über der Kuh). Server prüft alles.

## Benutzeroberfläche (Theme.lua)

- **Stil:** tiefes Marineblau für Flächen, Creme/Off-White für Schrift, Grasgrün für Haupt-Aktionen, Himmelblau als Akzent, Gold **nur** für Coins und seltene Belohnungen. Abgerundete Ecken, dünne einheitliche Umrandung (1,5–2 px), weiche Schatten (`Theme.softShadow`), kurze Tweens (0,12–0,35 s), keine dicken Schrift-Umrisse.
- **Design-Werte** in `Theme`: `Colors`, `Font`/`BodyFont`/`TextFont`, `TextSize`, `Spacing`, `Radius`, `Stroke`, `Shadow`, `Time`.
- **Bausteine:** `screenGui` (Safe-Area), `panel`, `label`, `tag`/`rarityBadge`, `button` (+ `primaryButton` grün, `secondaryButton` stahlblau, `destructiveButton` rot; Zustände Hover/gedrückt/ausgegraut), `progressBar`, `cowCard`, `createNotifier` (Meldungen), `window`, `coinIcon`/`milkIcon`/`cowIcon`, `autoScale`, `tween`.
- **Fenster** (`Theme.window`): Kopfzeile mit Titel, Akzentlinie und Schließen-Knopf; immer nur eins offen, Hintergrund abgedunkelt, Klick daneben schließt, Controller: B schließt. `win.Root` ist der Halter (Name = `props.Name`, `.Visible` wird vom Tutorial geprüft), `win.Panel` die Fläche, `win.Body` der Inhalt.
- **Eingabegeräte:** Maus/Touch über `Activated`, Controller über Auswahlrahmen (`SelectionImageObject`) und B; Tastenkürzel-Hinweise (M, I, Q/E) nur mit Tastatur bzw. L1/R1 mit Controller. Safe-Area: alle ScreenGuis laufen mit dem Roblox-Standard `CoreUISafe`, Fenster passen sich über `gui.AbsoluteSize` an.
- Feste Zonen: **oben links** Coins/Milch · **links Mitte** KARTE (M) / KÜHE (I) / BONUS (Streak-Abzeichen) · **oben Mitte** Meldungen (max. 3, 2,5 s) · **unten Mitte** Hotbar (1–6) · **darüber** Hinweis-Leiste · **unten rechts** VERKAUFEN (pulsiert bei Milch).
- Fenster: KARTE, MEINE KÜHE, KUH-SHOP, KISTEN, ZUCHT-STALL, TAGESBONUS, AUTO-MELKER.
- Noch im alten Look bzw. nur über die neue Palette angepasst (Pass 3): Hotbar/Kuh-Menü (InventoryClient), Karte (OverviewClient; "meine Farm" ist jetzt blau, nicht mehr gold), Tutorial.
- Wichtig für Code: an Roblox-Objekte keine eigenen Funktionen hängen (z. B. `frame.SetColor = …` wirft einen Fehler) – `Theme.button` gibt dafür `setColor` (3. Wert) und `api` (4. Wert: `SetColor`, `SetDisabled`, `SetText`) zurück. `api.SetDisabled(true)` graut nur optisch aus; der Klick kommt weiter an, damit der Aufrufer eine Erklärung zeigen kann.

## Tutorial (nur neue Spieler)

3-s-Kamerafahrt, Willkommens-Fenster "Gratis-Kuh", gelber Pfeil: Farm → Kuh melken → VERKAUFEN → Kuh-Shop; "Tutorial überspringen" unten links.

## Sounds (CowData.Config)

Funktioniert vermutlich: Coins `4590662766`, Muhen `535690488`. **Aus** (IDs waren keine Sounds oder gesperrt): Melken, Eimer voll, Hintergrund-Musik, Shop-Öffnen, Fanfare. Neue IDs aus der Toolbox (Audio) eintragen.

## Offen / nächste Schritte

1. In Studio prüfen (nie getestet, siehe Pass 1): neues HUD, alle Fenster, Melk-Minispiel (PC, Handy-Emulator, Controller), Hotbar, Kuh aufheben/platzieren, Karte + Reisen, Förderbänder, Nord-Markt, `CowModel.rbxm`.
2. Funktionierende Sound-IDs eintragen.
3. Balancing (erster Kauf nach ca. 2–3 Minuten), Upgrades (größerer Eimer, schnellere Pause), evtl. Bestenliste.
4. Gamepass-/Produkt-IDs eintragen (Platzhalter siehe oben), Spiel veröffentlichen, "Enable Studio Access to API Services" für den DataStore.
5. Pass 3 (Inventar/Hotbar, Karte, Tutorial auf dem Theme) ist im Code fertig; Feinschliff nach dem Studio-Test.
6. UI-Icons (Milch, Eimer, Münze, Kisten, Kuh) aus Blender rendern, in Roblox hochladen und als Asset-IDs eintragen.

## Bekannte Risiken (Stand Pass 1)

- `GetInventory` ist per Cache begrenzt (0,2 s, solange sich das Inventar nicht ändert); echtes Anfrage-Limit pro Spieler gibt es nicht.
- Der Auto-Melker ignoriert die Melk-Pause der Kühe (so gewollt, aber stark; Balancing prüfen).
- Studio ohne API-Zugriff speichert nichts (bewusst); live kickt ein fehlgeschlagenes Laden den Spieler.
- Beim Verlassen: schlägt das Speichern 3x fehl, gehen die Daten seit dem letzten Autosave (120 s) verloren.
