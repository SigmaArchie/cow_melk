# Cow Farm – Projektübersicht (Roblox, Rojo)

Stand: 06.11.2026 (Pass 1: Bugfixes + UI-Design-System, Pass 2: Welt, Shops, Farmen, Kühe, Pass 3: Tooling + Grow-a-Garden-Update: Kuh-Shop mit wechselndem Lager, neue Kuh-Arten, Milch-Eimer mit Mutationen, Wetter)

Roblox-Farming-Simulator "Cow Farm": Kühe melken (Minispiel), Milch verkaufen, mehr Kühe kaufen / züchten / aus Kisten ziehen, Kühe auf der eigenen Farm in einem Raster aufstellen. Kein Schlachten, keine Fusion. Code in Luau, synchronisiert mit **Rojo 7.7.1** (Tools über rokit: `rojo`, `selene`, `stylua`, `wally`). Alle Texte im Spiel und alle Code-Kommentare sind **Deutsch**. Schulprojekt (5. Klasse, GD).

Status: `rojo build` fehlerfrei, `selene src` 0 Fehler / 0 Warnungen, `stylua --check src` sauber (CI prüft alle drei).
Pass 3: Wetter in Studio geprüft (funktioniert); Shop-Lager, Kuh-Arten, Milch-Eimer und Mutationen sind **noch nicht in Studio gespielt**. In Studio gespielt wurde zuletzt vor der UI-Überarbeitung (Shops öffnen, Tutorial). Das neue Theme (HUD, Fenster, Melk-Minispiel) und die neue Welt (Shops, Farmen, Kuh-Beschriftungen, Effekte) sind **noch nicht in Studio geprüft** – in Pass 1 und 2 gab es keine Studio-Verbindung.

Starten: im Projektordner `rojo serve`, in Studio Rojo-Plugin → Connect (localhost:34872). Nach Änderungen an `default.project.json` Rojo neu starten.

## Ordnerstruktur

```
default.project.json        Rojo-Baum
rokit.toml                  Tools: rojo, selene, stylua, wally (rokit install)
selene.toml / stylua.toml   Lint (std = "roblox", global_usage = deny) / Formatierung (Tabs, 120 Zeichen, LF)
wally.toml                  Pakete (noch keine); Packages/ -> ReplicatedStorage.Packages, ServerPackages/ -> ServerStorage.ServerPackages
.gitattributes              .lua/.luau immer mit LF
.github/workflows/ci.yml    bei Push/PR: stylua --check, selene, rojo build (deploy.yml: Veröffentlichen von Hand)
CLAUDE.md / ARBEIT.md       Regeln für die Claudes + Board "Wer macht gerade was" (vor jeder Aufgabe lesen!)
tools/export_cow.py         Blender-Script: exportiert nur die Kuh-Teile als FBX
tools/make_props.py         Blender-Script (blender -b -P ...): Schemel, Melkeimer, Milch-Eimer -> assets_src/props/PropParts.fbx + PropMeshData.lua
tools/make_tools.py         Blender-Script: Futtereimer, Kuhglocke, Bürste, Werkzeug-Schuppen -> assets_src/tools/ToolParts.fbx + ToolMeshData.lua
assets_src/CowModell.fbx    exportierte Kuh (33 Teile); die .blend-Datei liegt NICHT im Repo
assets/CowModel.rbxm        -> ReplicatedStorage.Assets.CowModel (Blender-Kuh, 9,8 KB; Inhalt noch nicht in Studio geprüft)
assets/PropParts.rbxm       -> Assets.PropParts: 10 MeshParts für Schemel und Eimer (in Studio importiert und geprüft)
assets/ToolParts.rbxm       -> Assets.ToolParts: 14 MeshParts für Werkzeuge + Schuppen (noch nicht im Spiel benutzt)
src/shared/  -> ReplicatedStorage.Shared
  CowData.lua               alle Spielwerte, Kuh-Arten, Shop-Lager, Milch-Mutationen, Wetter, Zucht, Kisten, Karte, Shops, Sounds
  Palette.lua               gemeinsame Farben, Schriften, Welt- und Seltenheitsfarben (Client UND Server; Theme.lua liest hier)
  CowModelBuilder.lua       baut Kuh (Blender-Modell oder Ersatz aus Parts), Schemel, Eimer (aus PropParts, sonst Parts), Seltenheits-Effekte
  PropMeshData.lua          ERZEUGT von tools/make_props.py: Größe + Mittelpunkt der PropParts-Teile
  ToolMeshData.lua          ERZEUGT von tools/make_tools.py: Größe + Mittelpunkt der ToolParts-Teile
  ToolModelBuilder.lua      Build("Futtereimer"|"Kuhglocke"|"Buerste"|"Schuppen", cframe), SetSign(schuppen, text)
  GearModels.lua            3D-Modelle fürs Werkzeug (Heu, Striegel, Futtertrog, Kuhglocke, Goldener Trog, Wetterhahn, Spray)
src/server/  -> ServerScriptService.Server
  DataService.lua           DataStore laden/speichern + API für alle Server-Scripts
  PlayerDataManager.server  Laden/Speichern/Autosave, Starter-Kuh, TutorialDone
  CowManager.server         Plots + Raster, Kühe, Melken (+ Milch-Sorte würfeln), Inventar-Aktionen, Teleport, Verkaufen, Shop-Kauf, Kisten, Zucht, Auto-Melker, Robux
  FarmBuilder.lua           baut den Bauernhof eines Spielers (Boden, Zäune, Tor mit Schild, Scheune, Silo, Bauernhaus, Deko)
  FarmProps.lua             Deko-Bausteine (Bäume, Zäune, Scheune, Silo, Haus, Traktor, Brunnen, Heu, Felder, Windmühle, Teich ...)
  ShopService.lua           Lager des Kuh-Shops (Abschnitt, Lager, was der Spieler schon gekauft hat)
  ShopManager.server        GetShopStock, neues Lager ansagen (ShopRestocked + Meldung)
  GearService.lua           Werkzeug-Logik nur mit Daten (Lager, Kaufen, Aufstellen, Ablaufen, Wirkung, an der Kuh benutzen)
  GearManager.server        Werkzeug-Remotes (GetGearStock, BuyGear, GearAction), Modelle auf den Farmen, Wachstums-Schleife
  WeatherManager.server     Wetter-Events für den ganzen Server (workspace-Attribute Weather / WeatherEndsAt)
  LoginStreak.server        Tagesbonus, 7 Tage am Stück -> Rainbow Cow
  MapBuilder.server         runder Marktplatz mit Brunnen + 4 Shop-Gebäuden (NPC), Feldwege, Landschaft zwischen den Farmen, Wald, Hügel
src/client/  -> StarterPlayerScripts.Client
  Theme.lua                 EIN UI-Stil für alles (Farben, Schrift, Abstände, Knöpfe, Fenster, Balken, Abzeichen, Kuh-Karten, Meldungen, Symbole, Skalierung)
  UIBus.lua                 Signale zwischen Client-Scripts (Fenster öffnen sich gegenseitig)
  CoinDisplay.client        HUD (ScreenGui "HUD"): Coins/Milch, Seitenknöpfe, Meldungen, VERKAUFEN
  InventoryClient.client    Hotbar (Kühe + Milch-Eimer + Werkzeug, Tasten 1-9), Fenster "MEINE KÜHE" mit Reitern Kühe/Eimer, Platzier-Modus, Kuh-Menü
  OverviewClient.client     Fenster "KARTE" mit gezeichneter Karte + Reisen
  GearClient.client         Fenster "MEIN WERKZEUG" (Taste G), Aufstell-Modus (frei auf der Farm), Kuh-Modus, Knöpfe unter dem Kuh-Menü
  GearView.lua              Werkzeug-Modell als drehendes 3D-Bild (ViewportFrame) für Shop und Werkzeug-Fenster
  MenuUI.client             Fenster Kuh-Shop, Kisten, Zucht-Stall, Tagesbonus, Auto-Melker (ScreenGui "MenuUI", Fenster "Window")
  MilkingClient.client      Melk-Minispiel
  TutorialClient.client     Einführung für neue Spieler
  WorldAnimator.client      Welt-Animationen (Kühe laufen herum, Windmühlen, Shops), Melken-Prompt nur beim Besitzer + Sounds
  WeatherClient.client      Wetter-Effekte nur auf dem Client (Regen, Blitze, Schnee, Sternennacht, Farbton)
```

`default.project.json` legt außerdem an: `ReplicatedStorage.Remotes` (alle Remotes), `ReplicatedStorage.Assets`, `Workspace.CowFarmLayout.Plots`, `Workspace.Baseplate`.

## Remotes (ReplicatedStorage.Remotes)

| Name | Typ | Richtung | Zweck |
|---|---|---|---|
| SellMilk | RE | C→S | ganze Milch verkaufen |
| BuyCow | RF | C→S | (Kuh-Art) → ok, msg – nur, was im aktuellen Lager ist |
| GetShopStock | RF | C→S | → { Cycle, RestockAt, ServerTime, Items = { Type, Order, Price, Amount, Remaining } } |
| OpenCrate | RF | C→S | (crateId, payWithRobux) → ok, rarity/msg |
| StartBreeding | RF | C→S | (cowIdA, cowIdB) → ok, readyAt/msg |
| GetInventory | RF | C→S | Coins, Milk, Cows[] (mit Slot/Hotbar/Stored), Breeding, HotbarSize, CellCount … |
| CowAction | RF | C→S | (action, cowId, arg): `milk`, `pickup`, `place` (arg = Feld), `hotbar` (arg = Platz), `store` |
| BucketAction | RF | C→S | (action, bucketId, arg): `sell`, `hotbar` (arg = Platz oder nil), `store` (ins Eimer-Lager) |
| TeleportTo | RE | C→S | "Farm" oder Page-Name eines Shops |
| BuyAutoMilker | RE | C→S | Gamepass-Kaufdialog |
| MilkPull / StopMilking | RE | C→S | Melk-Zug ("Left"/"Right") / abbrechen |
| TutorialDone | RE | C→S | Tutorial als gesehen speichern |
| MilkingStarted / MilkingProgress / MilkingEnded | RE | S→C | Melk-Minispiel; MilkingEnded = (completed, milk, mutations) |
| ShopRestocked | RE | S→C | neues Lager im Kuh-Shop (offenes Shop-Fenster lädt neu) |
| GetGearStock | RF | C→S | Werkzeug-Lager → { Cycle, RestockAt, ServerTime, Items = { Type, Order, Price, Amount, Remaining } } |
| BuyGear | RF | C→S | (Werkzeug) → ok, msg – nur, was im aktuellen Werkzeug-Lager ist |
| GearAction | RF | C→S | ("Place", Werkzeug, x, z, yaw) irgendwo auf der eigenen Farm aufstellen (lokale Plot-Koordinaten) · ("UseOnCow", Werkzeug, cowId) an einer Kuh benutzen · ("Hotbar", Werkzeug, Platz \| nil) / ("Unhotbar", Werkzeug) → ok, msg |
| CowClicked | RE | S→C | eigene Kuh angeklickt → Menü (Melken/Aufheben) |
| OpenShop | RE | S→C | Shop-Gebäude angeklickt → Fenster öffnen |
| Notify | RE | S→C | (text, kind) kind = info/success/error/rare |
| InventoryChanged | RE | S→C | Client lädt Inventar neu |

Spieler-Attribute (Server setzt sie): `Coins`, `Milk` (Liter in allen Eimern), `MilkValue` (Wert aller Eimer in Coins), `CowCount`, `LoginStreak`, `TutorialDone`, `HasAutoMilker`, `PlotSlot`. Plus leaderstats `Coins`, `Kühe`. Workspace-Attribute (WeatherManager): `Weather` ("Clear" | "Rain" | "Storm" | "Snow" | "StarNight"), `WeatherEndsAt` (os.time).

## Daten (DataStore "CowFarm_PlayerData_v1", Key "Player_<UserId>")

```lua
{ Version=1, Coins=100, Milk=0 (Summe der Eimer), TotalMilk=0,
  Buckets = { b1 = { Id, Liters, Mutations={ "Gold", "Choco" }, CowMutations, CowName, CowType, Obtained,
                     Hotbar (1-9) | nil = Eimer-Lager, Auto (Auto-Melker-Eimer, Id "auto") } }, NextBucketId,
  Cows = { c1 = { Id, Rarity, Name, Obtained, MilkReadyAt,
                  Slot (Feld 1-36) | Hotbar (1-9) | Stored (true = Lager),
                  BornAt, GrowTime (Wachstum; fehlen = ausgewachsen), Mutations = { "Wet", ... } (Kuh-Mutationen) } },
  NextCowId, Breeding = {ParentA, ParentB, StartedAt, ReadyAt} | nil,
  LoginStreak = {Streak, LastDay, Best}, Receipts = {[PurchaseId]=time},
  ShopStock = { Cycle, Bought = { [Kuh-Art]=Anzahl } },
  Gears = { [Werkzeug]=Anzahl }, GearHotbar = { [Werkzeug]=Hotbar-Platz },
  PlacedGear = { { Id, Type, X, Z, Yaw, PlacedAt, ExpiresAt } } (alte Einträge mit Corner werden umgerechnet), NextGearId,
  GearStock = { Cycle, Bought = { [Werkzeug]=Anzahl } },   -- Kuh: Brushed = true (gestriegelt)
  ReceivedStarterCow, TutorialDone }
```
`Rarity` einer Kuh ist ihre **Art** (Name aus alten Zeiten). Alte Speicherstände: `MilkStock` (je Sorte ein Eimer) bzw. nur `Milk` (ein Eimer ohne Mutation, "Alte Milch") werden beim Laden zu Eimern im Eimer-Lager. Laden mit 3 Versuchen, fehlende Felder werden aufgefüllt; Speichern erst NACH allen PlayerRemoving-Handlern (`task.defer`), damit z.B. Milch aus einem abgebrochenen Melken noch gespeichert wird; alte Kühe ohne Ort werden beim Laden automatisch auf freie Felder verteilt. Studio ohne API-Zugriff → Testdaten (nicht gespeichert). Live: bei Ladefehler Kick.

## Spielmechanik (Werte in CowData.lua)

- Start: 100 Coins + Gratis-Holstein (als Kalb, nach 5 Min ausgewachsen). Milch = 2 Coins pro Liter. Max. 40 Kühe insgesamt (ein laufendes Kalb zählt als belegter Platz; Robux-Kisten und Login-Bonus ignorieren das Limit bewusst); 36 Felder pro Farm, 9 Hotbar-Plätze (Kühe und Eimer teilen sie sich), Rest im Lager; max. 100 Milch-Eimer.
- Seltenheiten (Milch pro Zug / Melk-Pause in s / Shoppreis): Common 2/20/100 · Uncommon 5/25/600 · Rare 12/30 · Epic 30/45 · Legendary 75/60 · Special: Golden 200 · Rainbow 160 · Ghost 130.
- Kühe bekommen: Kuh-Shop (Common, Uncommon), Zucht, Kisten (Holzkiste 500 Coins, Silberkiste 3000 Coins oder Robux, Premium-Kiste nur Robux mit 5 % Ghost).
- Zucht nach Durchschnitt der Eltern-Stufen; 2x Legendary: 1 % Golden (nur bei 2 echten Legendary). 5–20 Min, läuft auch offline.
- Rainbow Cow nur durch 7-Tage-Login-Streak. Tagesbonus = 25 × Tag (1–7).
- Auto-Melker (Gamepass): alle 3 s Milch von jeder Kuh, die auf der Farm steht.
- **Platzhalter:** `AutoMilkerGamePassId = 0`, `Crates.Super.ProductId = 0`, `Crates.Premium.ProductId = 0`, `MilkingAnimationId = 0`.

## Grow-a-Garden-Update (Pass 3)

**Kuh-Arten** (`CowData.Rarities`, Reihenfolge `CowData.CowTypeOrder`). Jede Art hat Name (`DisplayName`), Seltenheitsstufe (`ClassName`), Milch-Werte und Aussehen. Die alten 8 heißen jetzt nach ihrer Rasse (Holstein, Braunvieh, Blauschimmel, Lavendel-Kuh, Goldfell, Goldene Kuh, Regenbogen-Kuh, Geister-Kuh), die IDs sind gleich geblieben. Neu (nur aus dem Kuh-Shop):

| Art | Stufe | Milch/Zug | Pause | Preis | Im Lager | Besonders |
|---|---|---|---|---|---|---|
| Jersey | Ungewöhnlich | 7 | 25 s | 1.500 | 60 % | + Sahnemilch |
| Schoko-Kuh | Selten | 18 | 35 s | 8.000 | 33 % | + Schokomilch |
| Erdbeer-Kuh | Episch | 40 | 45 s | 20.000 | 20 % | + Erdbeermilch |
| Hochlandrind | Episch | 55 | 50 s | 35.000 | 14 % | + Sahnemilch, Eismilch auch ohne Schnee |
| Donner-Kuh | Legendär | 110 | 60 s | 80.000 | 7 % | Blitzmilch auch ohne Gewitter |
| Mondkuh | Mythisch | 220 | 75 s | 200.000 | 3,5 % | Sternenmilch auch ohne Sternennacht |
| Drachenkuh | Göttlich | 400 | 90 s | 500.000 | 1,5 % | + Goldmilch |
| Kristallkuh | Prismatisch | 700 | 90 s | 1.250.000 | 0,6 % | + Regenbogenmilch |

Effekte der neuen Arten: sie borgen sich ein Set der alten (`Effect`) mit eigener Farbe (`EffectColor`).

**Kuh-Shop mit Lager** (`CowData.Shop`, `ShopService`, `ShopManager`): alle 5 Minuten neues Lager. Pro Art wird gewürfelt, ob sie da ist (`Chance`) und wie viele (`Min`–`Max`). Gewürfelt wird mit einer festen Rechnung aus der Nummer des 5-Minuten-Abschnitts (Hash, kein `Random`), deshalb ist das Lager in **allen Servern und auf dem Client gleich**: das Shop-Fenster zeigt alle Arten sofort, vom Server (`GetShopStock`) kommt nur, wie viele man selbst schon gekauft hat. Jeder Spieler darf bis zur Lager-Menge kaufen; das wird in `ShopStock` gespeichert (Rejoin hilft nicht). Holstein ist immer da (Tutorial!). Neues Lager → Meldung an alle, ab Legendär mit Namen ("🌟 Selten im Kuh-Shop: …"). Das Fenster zeigt alle Arten mit "x2 im Lager" / "Ausverkauft" / "Nicht im Lager" und einen Timer.

**Milch-Eimer mit Mutationen** (`CowData.MilkTypes`, `DataService` Buckets): jedes Melken gibt einen **Eimer** (Gegenstand) mit Litern, Mutationen und der Kuh, von der er kommt. Er kommt auf einen freien Hotbar-Platz, sonst ins **Eimer-Lager** (max. 100; ist es voll, kann man erst nach dem Verkaufen weiter melken). Kühe haben in der Hotbar Vorrang: braucht eine Kuh einen Platz, wandert der billigste Eimer ins Lager.
- Bei einem **vollen** Eimer wird jede Mutation einzeln gewürfelt, ein Eimer kann also mehrere haben. Wert-Faktor = 1 + Summe(Multiplikator − 1), z.B. Schoko (x2) + Gold (x20) = x21. Abgebrochenes Melken = halber Eimer ohne Mutation.
- Der Auto-Melker füllt einen eigenen Eimer ("Auto"), der immer voller wird (ohne Mutationen).
- Hotbar-Platz mit Eimer: Mutation oben (kurzer Name, "+1" bei mehreren), Eimer in der Farbe der wertvollsten Mutation (Symbol wird mit den Litern größer), Liter unten. Maus drüber oder anklicken → Details über der Hotbar (mit Größe: Klein/Mittel/Groß/Riesig), angeklickt mit Knopf "Verkaufen".
- **Eimer tragen:** der angeklickte Hotbar-Eimer wird getragen (`BucketAction` "hold"); nach dem Melken kommt der neue Eimer automatisch in die Hand, beim Melken wird er abgelegt. Kein Roblox-Tool, weil ClickDetector (Kühe, Shops) mit einem Tool in der Hand nicht mehr reagieren. Stattdessen: der Server schweißt das Modell `HeldBucket` an die rechte Hand, an den Griffpunkt `RightGripAttachment` (wie Tools; R15 und R6). `WorldAnimator` spielt beim eigenen Charakter die Roblox-Halteanimation `toolnone` (aus dem Animate-Script, sonst 507768375 / R6 182393478, Priorität Action) – andere Spieler sehen sie automatisch. Nach Verkauf/Ins-Lager weg, nach Respawn wieder da, der Auto-Melker-Eimer wächst mit. Fehler: Meldung über der Hotbar + Warnung im Output.
- **3D-Modell** `CowModelBuilder.BuildMilkBucket(liters, mutations)` (ca. 25 Parts, Holz-Stil wie der Melkeimer): Größe `CowData.GetBucketScale` (20 L = 0,8 … ab ~20.000 L = 2,2; Namen in `CowData.BucketSizes`); Milch in der Farbe der wertvollsten Mutation (ab x20 Neon, Eis glänzt); ein farbiger Reifen pro Mutation (max. 3, sonst 2 aus Metall); Dauben je nach wertvollster "besonderer" Mutation: Blitz dunkles Metall, Regenbogen bunt, Sterne nachtblau, Gold golden, Eis aus Eis, Schoko dunkles Holz; Extras Sahnehäubchen/Erdbeere/Schokostück; Partikel/Licht für Frisch, Eis, Gold, Sterne, Regenbogen, Blitz. PrimaryPart = unsichtbarer `Grip` oben am Henkel. Vorschau: `assets_src/previews/milcheimer.png`.
- Fenster MEINE KÜHE → Reiter EIMER: alle Eimer mit Wert, Herkunft, Ort; Knöpfe Verkaufen / In Hotbar / Ins Lager.
- VERKAUFEN (HUD und Milch-Stand) verkauft alle Eimer; der Wert steht über dem Knopf.

| Sorte | Wert | Grundchance | Wetter |
|---|---|---|---|
| Sahnemilch | x1,5 | 10 % | |
| Frischmilch | x2 | – | Regen/Gewitter +35 % |
| Schokomilch | x2 | 5 % | |
| Erdbeermilch | x3 | 3 % | |
| Eismilch | x8 | – | Schnee +20 % |
| Goldmilch | x20 | 1 % | |
| Sternenmilch | x40 | – | Sternennacht +8 % |
| Regenbogenmilch | x50 | 0,2 % | |
| Blitzmilch | x100 | – | Gewitter +3 % |

Chance je Mutation = Grundchance + Wetter + `MilkBonus` der Art, mal `Luck` des Wetters (Sternennacht = 2), höchstens 95 %. Ab Faktor x8 gibt es eine seltene Meldung, ab x40 hört es der ganze Server.

**Wachstum** (`CowData.Growth`, CowManager `checkGrowth`/`regrowCow`): neue Kühe kommen als **Kalb** und wachsen über die Zeit (Zeitstempel `BornAt` + `GrowTime`, läuft auch offline). Auch die Gratis-Kuh kommt als Kalb. Ausgewachsen starten nur Login-Bonus (Regenbogen), Robux-Kisten und Kühe aus alten Speicherständen.

| Stufe | ab | Größe | Milch |
|---|---|---|---|
| Kalb | 0 % | 50 % | 25 % |
| Jungkuh | 30 % | 68 % | 50 % |
| Fast ausgewachsen | 65 % | 84 % | 75 % |
| Ausgewachsen | 100 % | 100 % | 100 % (volle `MilkPerPull`) |

Wachstumszeit nach Stufe der Art (`TimeByTier`): 5 / 8 / 12 / 18 / 25 / 30 / 40 / 50 Minuten (Holstein 5 Min, Kristallkuh 50 Min). Bei jeder neuen Stufe baut der Server die Kuh in der neuen Größe neu auf (erst neu bauen, dann die alte entfernen – klappt das Bauen nicht, bleibt die alte stehen + Warnung im Output) (`CowModelBuilder.BuildCow(..., scale)` skaliert Teile, Gruppen-Drehpunkte, Attachments, Lichter und die Maße für Schemel/Eimer), mit Funken und Pop-up ("Wächst! Jungkuh" / "Ausgewachsen!" + Meldung). Wird die Kuh gerade gemolken, wartet der Umbau. Milch pro Zug und Auto-Melker richten sich nach der Stufe. **Züchten nur mit ausgewachsenen Kühen.** Anzeige: Namensschild "Kalb · Holstein", Kuh-Menü "Kalb · 25 % Milch · groß in 4:12", Inventar-Karte "Kalb 4:12", Zucht-Liste ausgegraut, Shop-Karte "Wächst · Pause".

**Kuh-Mutationen** (`CowData.CowMutations`, CowManager `rollCowMutations`): dauerhafte Eigenschaften der Kuh, wie die Pflanzen-Mutationen in Grow a Garden. Jede Kuh **auf der Farm** (Kalb oder ausgewachsen) kann sie jederzeit bekommen: alle 15 s wird gewürfelt, Chance nach Wetter, höchstens eine neue pro Wurf. Sie **stapeln** sich und **verbinden** sich, sobald alle Zutaten da sind (auch als Kette). Eine Mutation, die schon in einer Verbindung steckt, kommt nicht nochmal (gefrorene Kuh wird nicht wieder nass).

| Mutation | Wert | Woher |
|---|---|---|
| ☀ Sonnengeküsst | x1,5 | Sonne, 0,08 % pro Wurf |
| 💧 Nass | x2 | Regen/Gewitter, 3 % (ein Regen: ~27 % der Kühe) |
| ❄ Gekühlt | x2 | Schnee, 3 % |
| 🌙 Mondschein | x3 | Sternennacht, 2,5 % |
| ⚡ Geladen | x10 | Gewitter, 0,4 % (ein Gewitter: ~3 %) |
| 🧊 Gefroren | x10 | Nass + Gekühlt |
| 🌈 Regenbogenglanz | x15 | Nass + Sonnengeküsst |
| ✨ Sternenfrost | x30 | Gefroren + Mondschein |
| 🌌 Polarlicht | x60 | Gefroren + Geladen |

- Wert: Kuh-Faktor = 1 + Summe(Multiplikator − 1); Eimer-Wert = Liter × 2 × Milch-Faktor × Kuh-Faktor. Der Eimer merkt sich die Kuh-Mutationen beim Melken (`CowMutations`).
- Aussehen: `CowModelBuilder.ApplyCowMutations` (Tropfen, Schneeflocken, eisiges Fell, Funken, Regenbogen-/Sternen-Partikel, kleines Licht). Neue Mutation → Kuh wird neu gebaut (wie beim Wachsen, nicht während des Melkens), Pop-up + Meldung; Verbindung → seltene Meldung, ab x30 für den ganzen Server.
- Zucht: jede Mutation der Eltern wird mit 25 % vererbt (`InheritChance`), Verbindungen danach.
- Anzeige: Namensschild mit farbiger Mutations-Zeile, Kuh-Menü ("Nass · Gefroren · Milch x11 wert"), Inventar-Karte, Zucht-Liste (Symbole), Eimer-Details ("Kuh: Gefroren (x10)"), Hotbar-Eimer (Symbole).
- Test in Studio: Chancen x5 (`StudioBoost`); Wetter im Server-Modus über das Workspace-Attribut `Weather` setzen.

**Wetter** (`CowData.Weather`, `WeatherManager`, `WeatherClient`): nach 4–7 Minuten Sonne kommt Regen (40), Schnee (25), Gewitter (15) oder Sternennacht (10), je 2–2,5 Minuten. Anzeige mit Restzeit im HUD unter "Nächstes Ziel". In Studio kommt das erste Event schon nach 30 s; zum Testen kann man im Server-Modus am Workspace das Attribut `Weather` setzen.

## Karte

Alles dreht sich um die Kartenmitte (0, 0, 0). Winkel im Uhrzeigersinn von Norden (+Z): Position = Radius · (sin w, 0, cos w). Vorschau-Bilder (gerendert ohne Studio): `assets_src/previews/umbau/`.

- **Marktplatz** (rund, Radius 64, Folder `Hub`): Milch-Brunnen in der Mitte, Ring-Weg darum, Gassen zu den Feldwegen (0°, 60°, ...) und zu den Shop-Türen, **Dorfbaum** (hinter dem Werkzeug-Shop, 90°), **Pavillon** (270°), Spawn, Wegweiser zu den Shops, Bänke, runde Blumenbeete, Laternen.
- **Shop-Gebäude** rund um den Brunnen (Radius 40, Tür zum Brunnen): Kuh-Shop 330°, Zucht-Stall 30°, Werkzeug 90°, Kisten 150°, Auto-Melker 210° (`CowData.Map.Shops`, Lage über `CowData.GetShopCFrame`). Stile: Kuh-Shop = Scheune (Gambrel-Dach, Scheunentore), Kisten = offener Marktstand mit gestreiftem Dach und Kistenstapeln, Zucht-Stall = gemütlicher Stall (Blumenkästen, Heu, Trog), Auto-Melker = Werkstatt aus Metall mit Silo und Schornstein, Werkzeug = Geräteschuppen mit Steinsockel, steilem Dach, Esse und Wetterhahn, Mistgabel/Schaufel/Rechen an der Wand, Werkbank mit Amboss, Futtertrog und Kuhglocke als Schaufenster. Alle: Grundfläche ca. 20×16, Tür vorne (−Z), Holzschild (Symbol + Name), winkender NPC mit Strohhut, Hinweis "Klicken zum Öffnen", Klick → `OpenShop`, Teleport-Punkt 9 Studs vor der Tür.
- **Landschaft** (Folder `Countryside`): Feldwege vom Platz zu jedem Farm-Tor, Ringweg (Radius 108) vor den Toren, Wiese mit Bäumen/Büschen/Blumen. In den Lücken zwischen den Farmen (30°, 90°, ...) je ein Thema links/rechts eines Pfads: Windmühle (Flügel drehen sich, Tag `Spinner`) + Weizenfeld, Teich mit Enten und Steg, Apfel-Obstgarten, Kürbisbeet mit Vogelscheuche, Blumenfeld mit Bienenstöcken und Sonnenblumen, Traktor + Heu; dazu Hecken aus Bäumen entlang der Farm-Zäune. Waldrand hinter den Farmen, **Hügel** (`Hills`) ganz außen (Radius > 600).
- **Farmen** (Bauernhöfe, `FarmBuilder.lua`) im Kreis: bis 6 Spieler im inneren Ring (Mitte bei Radius 185, 0°, 60°, ...; Tor bei Radius 115 zeigt zum Platz), ab Spieler 7 ein zweiter Ring (Radius 350, in den Lücken). Lokale Koordinaten: x −54..54, z −70..70, Tor bei +Z.
  - **Hof** (z 32..70): Steinpfeiler-Tor mit Namensschild (Part `Sign` direkt in `Decor`, vom Tutorial gebraucht) und Laternen, Weg, Hofplatz aus Erde, rote **Scheune** mit Mansarddach und **Silo** (links), Traktor, Schubkarre, Heuballen, Kisten, Baum + Bank, **Milch-Verkaufsstation** (ProximityPrompt F), Brunnen, Milchkannen, **Bauernhaus**, Hühnerstall mit Hühnern, Karren, Blumenbeete, Briefkasten; am Weide-Zaun Wassertrog und Heuraufe.
  - **Weide** (z −70..32): Holzzaun mit offenem Gatter, Wiese mit Flecken, Wildblumen, Steine. **Raster mit 36 Feldern** à 16×16 (`CowData.GetGridCellLocal`, Kühe lokal z −58..22); die Felder sind unsichtbar und nur im Platzier-Modus eingefärbt.
  - **Kühe laufen herum** (nur Darstellung, `WorldAnimator`): jede Kuh läuft auf ihrem Feld umher (Radius je nach Größe 3,3–4,5 Studs, `CowData.CowWander` / `GetWanderRadius`), dreht sich, grast (Kopf runter). Wohin, berechnet jeder Client gleich aus Serverzeit + Kuh-ID (`CowData.HashRoll`), deshalb sehen alle Spieler dasselbe. Auf dem Server steht die Kuh immer auf ihrem Platz. Schemel und Eimer sind nur beim Melken sichtbar; dann steht die Kuh genau auf ihrem Platz.

## Studio-Testmodus

`CowData.Config.StudioTestMode = true` (gilt NUR in Roblox Studio, `CowData.IsStudioTest()`): man startet mit `StudioTestCoins` (10 Mio.), Kuh-Shop und Werkzeug-Shop haben alles im Lager (`StudioTestStock`, keine Ansagen), und es wird **nichts gespeichert** (DataService setzt den Spieler auf "nicht speichern", damit echte Spielstände nicht verändert werden). Hinweis im Output und als Meldung im Spiel. Zum Testen mit Speichern auf `false` stellen. Im veröffentlichten Spiel ist er immer aus.

## Werkzeug-Shop (wie der Gear-Shop in Grow a Garden)

Daten in `CowData.Gears` / `CowData.GearShop` / `CowData.GearSettings`, Logik in `GearService` (nur Daten, getestet), Server in `GearManager`, Oberfläche in `MenuUI` (Seite "Gear") und `GearClient`. Vorschau-Bilder: `assets_src/previews/werkzeug/`.

- **Lager** wie beim Kuh-Shop: alle 5 Minuten neu, in allen Servern gleich (`CowData.RollGearStock`), jeder Spieler darf bis zur Lager-Menge kaufen (`GearStock`). Seltenes (ab 10.000 Coins) wird im Server angesagt.
- **Hotbar:** gekauftes Werkzeug kommt als Stapel (Bild + Anzahl) auf einen freien Hotbar-Platz (`GearService.AutoHotbar`), Kühe und Eimer gehen vor. Im Werkzeug-Fenster "+ Hotbar" / "– Hotbar". Platz anklicken bzw. Zahl drücken = Werkzeug in die Hand (`UIBus.SelectGear`); leerer Stapel gibt den Platz frei.
- **Für eine Kuh** (Werkzeug in die Hand → eigene Kuh anklicken, oder Kuh anklicken → Knöpfe unter dem Kuh-Menü): **Heubündel** 150 (Pause sofort vorbei), **Striegel** 400 (nächster voller Eimer +50 % Milch), **Wunder-Spray** 60.000 (zufällige Kuh-Mutation, Gewichte `SprayWeights`, Verbindungen zählen).
- **Zum Aufstellen** (wie die Sprinkler in Grow a Garden; Hotbar oder Fenster → "Aufstellen"): Vorschau folgt der Maus **irgendwo auf der eigenen Farm** (auch neben dem Bauernhaus), R = drehen, Klick = aufstellen, X = fertig. Die 36 Kuh-Plätze leuchten grün, wenn das Werkzeug sie erreicht; ein Schild zeigt "🐄 3 Kühe in Reichweite". Wirkt auf jede Kuh, deren Platz (Feld-Mitte + `CowOffsetX`) höchstens `Radius` entfernt ist (`CowData.GearCoversCell` / `GetGearCells`). Regeln: auf der Farm mit 2 Studs Rand (`IsGearPositionValid`), mind. 3,5 Studs zu anderem Werkzeug, höchstens 6. Zwischen 4 Feldern erreicht Radius 12 die 4 Plätze rundherum, Radius 26 zwölf. **Futtertrog** 800 (Kälber wachsen x2, kleiner Kreis R 12, 10 Min), **Kuhglocke** 2.500 (Wetter-Mutationen x2, R 12, 10 Min), **Goldener Futtertrog** 10.000 (x3, großer Kreis R 26, 15 Min), **Wetterhahn** 25.000 (Mutationen x3, R 26, 15 Min). Höchstens 6 gleichzeitig. Mehrere Werkzeuge: der beste Faktor zählt.
- Wachstum: alle 5 s bekommen Kälber im Bereich `5 · (Faktor − 1)` Sekunden geschenkt (`BornAt` rückt vor, nie über "ausgewachsen" hinaus); den Umbau zur nächsten Stufe macht wie immer `CowManager.checkGrowth`. Mutations-Glück multipliziert in `rollCowMutations` die Wetter-Chance.
- Auf der Farm: Modell + halbdurchsichtiger Wirkungsbereich + Schild mit Restzeit (Folder `Gear` im Plot). Glocke schwingt, Wetterhahn dreht sich (Tag `Spinner`, `SwingAngle`).
- HUD-Knopf **WERKZEUG** (Taste G) links; Shop-Karten und Werkzeug-Fenster zeigen die Modelle als drehendes 3D-Bild.

## Kuhmodell & Animation

- `CowModelBuilder.BuildCow` nimmt `ReplicatedStorage.Assets.CowModel` (Blender-Kuh), wenn vorhanden: erkennt Teile an den Blender-Namen (Koerper, Kopf, Zitze_…, Fleck_…), dreht, skaliert auf 6.4 Studs, färbt pro Seltenheit. Sonst Ersatz-Kuh aus Parts (rund, niedlich).
- Gruppen `HeadGroup`, `EarLeft`, `EarRight`, `TailGroup`; Tag "Cow". WorldAnimator: herumlaufen + grasen (siehe Karte), schweben, Kopf ±15°, Schwanz wedelt, Ohren flattern; nur in < 160 Studs; Regenbogen-Kuh wechselt jede Sekunde die Farbe.
- Effekte je Seltenheit (bewusst zurückhaltend, wegen vieler Kühe): Common keine · Uncommon wenige grünliche Funken · Rare kleines blaues Licht · Epic lila Licht + wenige Partikel · Legendary warmes Gold-Licht + wenige Funken · Golden Gold-Licht, wenige Münz-Partikel, dünner Strahl · Rainbow sanftes Licht, zarte Farbpartikel, Farbwechsel alle 3 s · Ghost grünlicher Dunst, durchsichtig. Neue Kuh fällt vom Himmel mit dezentem Konfetti.
- Beschriftungen an der Kuh (Server, `Palette`): Namensschild (Name, Seltenheit in Seltenheitsfarbe, Status "Bereit" / "Pause m:ss" / "Zucht m:ss" / "Wird gemolken"), Pop-ups "+X Milch" (Creme) und "+X Coins" (Gold), Prompt "Melken" (Taste E, nur beim Besitzer).
- `assets/CowModel.rbxm` (Modell `CowModel`, MeshParts `Koerper`, `Kopf`, `Zitze_*`, `Ohr_*`, `Schwanz*`, `Schnauze`, `Euter`, `Fleck*`, `Huf*`, `Bein*`, `Auge_*`, `Horn*`; verweist auf eine Mesh-ID aus Roblox): wird benutzt, wenn `Koerper` und `Kopf` gefunden werden; bei Fehlern oder fehlendem Modell baut `CowModelBuilder` die Ersatz-Kuh aus Parts. Ob die Mesh-ID im Spiel lädt, ist ungeprüft.

## Melk-Minispiel

Kuh anklicken → Menü "Melken" (oder neben der Kuh E drücken / "Melken" antippen). Server teleportiert auf den Schemel. Panel mit Kuhgesicht, Fortschrittsbalken, Eimer füllt sich, ◄ ► bzw. Q/E (Controller L1/R1, Aufstehen = B) abwechselnd; falsche Seite = 1 Zug weniger. Nach 10 Zügen: Eimer kippt, "+X MILCH!", Kuh bekommt Pause (Timer über der Kuh). Server prüft alles.

## Benutzeroberfläche (Theme.lua)

- **Stil "Holz-Farm"** (seit 20.11.2026): Fenster aus Holz mit Brett-Fugen und dickem dunkelbraunem Rand, Gras-Streifen mit Zacken oben, Titel auf einem Holzschild mit zwei Äpfeln, eckiges rotes X. Weiße Schrift mit dunkelbraunem Umriss (FredokaOne). Knöpfe mit dunklem Rand und Unterkante: Grün = Kaufen/Coins, Gold = Robux/Seltenes, Blau = Info, Orange = Aktion, Rot = Schließen, helles Holz = Nebenaktion. Bausteine `Theme.grassStrip` und `Theme.titleSign` auch für eigene Panels (z. B. Melk-Minispiel).
- **Design-Werte** in `Theme`: `Colors`, `Font`/`BodyFont`/`TextFont`, `TextSize`, `Spacing`, `Radius`, `Stroke`, `Shadow`, `Time`.
- **Bausteine:** `screenGui` (Safe-Area), `panel`, `label`, `tag`/`rarityBadge`, `button` (+ `primaryButton` grün, `secondaryButton` helles Holz, `destructiveButton` rot; Zustände Hover/gedrückt/ausgegraut), `progressBar`, `cowCard`, `createNotifier` (Meldungen), `window`, `grassStrip`, `titleSign`, `woodGradient`, `woodPlanks`, `coinIcon`/`milkIcon`/`cowIcon`, `autoScale`, `tween`.
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

0. Pass 3 in Studio spielen: Kuh-Shop (Lager, Timer, Ausverkauft), Milch-Eimer (Hotbar-Anzeige, Details, Verkaufen einzeln/alle, Reiter EIMER, großer Text mit Mutationen, Eimer-Lager voll), Wetter (Effekte, Anzeige, Meldungen), neue Kuh-Arten auf der Farm (Farben, Effekte, Blender-Kuh).

1. In Studio prüfen (nie getestet, siehe Pass 1): neues HUD, alle Fenster, Melk-Minispiel (PC, Handy-Emulator, Controller), Hotbar, Kuh aufheben/platzieren, Karte + Reisen, neuer Marktplatz + Bauernhöfe (herumlaufende Kühe, Melken-Prompt, Windmühle), `CowModel.rbxm`.
2. Funktionierende Sound-IDs eintragen.
3. Balancing (erster Kauf nach ca. 2–3 Minuten), Upgrades (größerer Eimer, schnellere Pause), evtl. Bestenliste.
4. Gamepass-/Produkt-IDs eintragen (Platzhalter siehe oben), Spiel veröffentlichen, "Enable Studio Access to API Services" für den DataStore.
5. Pass 3 (Inventar/Hotbar, Karte, Tutorial auf dem Theme) ist im Code fertig; Feinschliff nach dem Studio-Test.
6. UI-Icons (Milch, Eimer, Münze, Kisten, Kuh) aus Blender rendern, in Roblox hochladen und als Asset-IDs eintragen.

## Behobene Fehler

- **Zwei Kühe ineinander** (Pass 3): `CowModelBuilder.BuildCow` wartet beim ersten Mal auf die Mesh-Prüfung. In dieser Zeit haben Gratis-Kuh (`CowAdded`) und Laden der Farm (`onPlayerAdded`) dieselbe Kuh zweimal gebaut. Jetzt merkt sich `farm.Spawning`, welche Kuh gerade gebaut wird; ein zweiter Aufruf wartet darauf.

- **Gekaufte Kühe alle auf demselben Feld**: `DataService.AddCow` schickt die Kuh über ein `BindableEvent` an `CowManager` – Roblox **kopiert** Tabellen dabei. `assignLocation` hat das Feld nur in die Kopie geschrieben, die echte Kuh in den Daten blieb ohne Feld, also bekam jede neue Kuh wieder Feld 1. Jetzt holt sich der `CowAdded`-Handler zuerst die echte Kuh (`data.Cows[cow.Id]`). Merke: über BindableEvents nie Tabellen schicken, die der Empfänger ändern soll.

- **Remote fehlt → Script bricht ab**: Server-Scripts holen neue Remotes über `DataService.GetRemote` – fehlt eines (Rojo nicht neu gestartet), wird es zur Laufzeit angelegt (mit Warnung).

## Bekannte Risiken (Stand Pass 1)

- `GetInventory` ist per Cache begrenzt (0,2 s, solange sich das Inventar nicht ändert); echtes Anfrage-Limit pro Spieler gibt es nicht.
- Der Auto-Melker ignoriert die Melk-Pause der Kühe (so gewollt, aber stark; Balancing prüfen).
- Studio ohne API-Zugriff speichert nichts (bewusst); live kickt ein fehlgeschlagenes Laden den Spieler.
- Beim Verlassen: schlägt das Speichern 3x fehl, gehen die Daten seit dem letzten Autosave (120 s) verloren.
