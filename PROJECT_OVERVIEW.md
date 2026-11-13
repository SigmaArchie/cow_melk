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
tools/export_cow.py         Blender-Script: exportiert nur die Kuh-Teile als FBX
assets_src/CowModell.fbx    exportierte Kuh (33 Teile); die .blend-Datei liegt NICHT im Repo
assets/CowModel.rbxm        -> ReplicatedStorage.Assets.CowModel (Blender-Kuh, 9,8 KB; Inhalt noch nicht in Studio geprüft)
src/shared/  -> ReplicatedStorage.Shared
  CowData.lua               alle Spielwerte, Kuh-Arten, Shop-Lager, Milch-Mutationen, Wetter, Zucht, Kisten, Karte, Shops, Sounds
  Palette.lua               gemeinsame Farben, Schriften, Welt- und Seltenheitsfarben (Client UND Server; Theme.lua liest hier)
  CowModelBuilder.lua       baut Kuh (Blender-Modell oder Ersatz aus Parts), Schemel, Eimer, Seltenheits-Effekte
src/server/  -> ServerScriptService.Server
  DataService.lua           DataStore laden/speichern + API für alle Server-Scripts
  PlayerDataManager.server  Laden/Speichern/Autosave, Starter-Kuh, TutorialDone
  CowManager.server         Plots + Raster, Kühe, Melken (+ Milch-Sorte würfeln), Inventar-Aktionen, Teleport, Verkaufen, Shop-Kauf, Kisten, Zucht, Auto-Melker, Robux
  ShopService.lua           Lager des Kuh-Shops (Abschnitt, Lager, was der Spieler schon gekauft hat)
  ShopManager.server        GetShopStock, neues Lager ansagen (ShopRestocked + Meldung)
  WeatherManager.server     Wetter-Events für den ganzen Server (workspace-Attribute Weather / WeatherEndsAt)
  LoginStreak.server        Tagesbonus, 7 Tage am Stück -> Rainbow Cow
  MapBuilder.server         Süd-Platz, Allee, 2 Förderbänder, Nord-Markt, 4 Shop-Gebäude mit NPC
src/client/  -> StarterPlayerScripts.Client
  Theme.lua                 EIN UI-Stil für alles (Farben, Schrift, Abstände, Knöpfe, Fenster, Balken, Abzeichen, Kuh-Karten, Meldungen, Symbole, Skalierung)
  UIBus.lua                 Signale zwischen Client-Scripts (Fenster öffnen sich gegenseitig)
  CoinDisplay.client        HUD (ScreenGui "HUD"): Coins/Milch, Seitenknöpfe, Meldungen, VERKAUFEN
  InventoryClient.client    Hotbar (Kühe + Milch-Eimer, Tasten 1-9), Fenster "MEINE KÜHE" mit Reitern Kühe/Eimer, Platzier-Modus, Kuh-Menü
  OverviewClient.client     Fenster "KARTE" mit gezeichneter Karte + Reisen
  MenuUI.client             Fenster Kuh-Shop, Kisten, Zucht-Stall, Tagesbonus, Auto-Melker (ScreenGui "MenuUI", Fenster "Window")
  MilkingClient.client      Melk-Minispiel
  TutorialClient.client     Einführung für neue Spieler
  WorldAnimator.client      Welt-Animationen (Förderbänder, Kühe, Shops) + Sounds
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
| CowClicked | RE | S→C | eigene Kuh angeklickt → Menü (Melken/Aufheben) |
| OpenShop | RE | S→C | Shop-Gebäude angeklickt → Fenster öffnen |
| Notify | RE | S→C | (text, kind) kind = info/success/error/rare |
| InventoryChanged | RE | S→C | Client lädt Inventar neu |

Spieler-Attribute (Server setzt sie): `Coins`, `Milk` (Liter in allen Eimern), `MilkValue` (Wert aller Eimer in Coins), `CowCount`, `LoginStreak`, `TutorialDone`, `HasAutoMilker`, `PlotSlot`. Plus leaderstats `Coins`, `Kühe`. Workspace-Attribute (WeatherManager): `Weather` ("Clear" | "Rain" | "Storm" | "Snow" | "StarNight"), `WeatherEndsAt` (os.time).

## Daten (DataStore "CowFarm_PlayerData_v1", Key "Player_<UserId>")

```lua
{ Version=1, Coins=100, Milk=0 (Summe der Eimer), TotalMilk=0,
  Buckets = { b1 = { Id, Liters, Mutations={ "Gold", "Choco" }, CowName, CowType, Obtained,
                     Hotbar (1-9) | nil = Eimer-Lager, Auto (Auto-Melker-Eimer, Id "auto") } }, NextBucketId,
  Cows = { c1 = { Id, Rarity, Name, Obtained, MilkReadyAt,
                  Slot (Feld 1-36) | Hotbar (1-9) | Stored (true = Lager),
                  BornAt, GrowTime (Wachstum; fehlen = ausgewachsen) } },
  NextCowId, Breeding = {ParentA, ParentB, StartedAt, ReadyAt} | nil,
  LoginStreak = {Streak, LastDay, Best}, Receipts = {[PurchaseId]=time},
  ShopStock = { Cycle, Bought = { [Kuh-Art]=Anzahl } },
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

**Wetter** (`CowData.Weather`, `WeatherManager`, `WeatherClient`): nach 4–7 Minuten Sonne kommt Regen (40), Schnee (25), Gewitter (15) oder Sternennacht (10), je 2–2,5 Minuten. Anzeige mit Restzeit im HUD unter "Nächstes Ziel". In Studio kommt das erste Event schon nach 30 s; zum Testen kann man im Server-Modus am Workspace das Attribut `Weather` setzen.

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

0. Pass 3 in Studio spielen: Kuh-Shop (Lager, Timer, Ausverkauft), Milch-Eimer (Hotbar-Anzeige, Details, Verkaufen einzeln/alle, Reiter EIMER, großer Text mit Mutationen, Eimer-Lager voll), Wetter (Effekte, Anzeige, Meldungen), neue Kuh-Arten auf der Farm (Farben, Effekte, Blender-Kuh).

1. In Studio prüfen (nie getestet, siehe Pass 1): neues HUD, alle Fenster, Melk-Minispiel (PC, Handy-Emulator, Controller), Hotbar, Kuh aufheben/platzieren, Karte + Reisen, Förderbänder, Nord-Markt, `CowModel.rbxm`.
2. Funktionierende Sound-IDs eintragen.
3. Balancing (erster Kauf nach ca. 2–3 Minuten), Upgrades (größerer Eimer, schnellere Pause), evtl. Bestenliste.
4. Gamepass-/Produkt-IDs eintragen (Platzhalter siehe oben), Spiel veröffentlichen, "Enable Studio Access to API Services" für den DataStore.
5. Pass 3 (Inventar/Hotbar, Karte, Tutorial auf dem Theme) ist im Code fertig; Feinschliff nach dem Studio-Test.
6. UI-Icons (Milch, Eimer, Münze, Kisten, Kuh) aus Blender rendern, in Roblox hochladen und als Asset-IDs eintragen.

## Behobene Fehler

- **Zwei Kühe ineinander** (Pass 3): `CowModelBuilder.BuildCow` wartet beim ersten Mal auf die Mesh-Prüfung. In dieser Zeit haben Gratis-Kuh (`CowAdded`) und Laden der Farm (`onPlayerAdded`) dieselbe Kuh zweimal gebaut. Jetzt merkt sich `farm.Spawning`, welche Kuh gerade gebaut wird; ein zweiter Aufruf wartet darauf.

- **Remote fehlt → Script bricht ab**: Server-Scripts holen neue Remotes über `DataService.GetRemote` – fehlt eines (Rojo nicht neu gestartet), wird es zur Laufzeit angelegt (mit Warnung).

## Bekannte Risiken (Stand Pass 1)

- `GetInventory` ist per Cache begrenzt (0,2 s, solange sich das Inventar nicht ändert); echtes Anfrage-Limit pro Spieler gibt es nicht.
- Der Auto-Melker ignoriert die Melk-Pause der Kühe (so gewollt, aber stark; Balancing prüfen).
- Studio ohne API-Zugriff speichert nichts (bewusst); live kickt ein fehlgeschlagenes Laden den Spieler.
- Beim Verlassen: schlägt das Speichern 3x fehl, gehen die Daten seit dem letzten Autosave (120 s) verloren.
