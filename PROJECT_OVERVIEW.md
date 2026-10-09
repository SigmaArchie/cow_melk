# Cow Farm – Projektübersicht (Roblox, Rojo)

Roblox-Farming-Tycoon "Cow Farm". Kühe melken (Minispiel), Milch verkaufen, mehr Kühe kaufen/züchten/aus Kisten ziehen. Kein Schlachten, keine Fusion. Code in Luau, synchronisiert mit **Rojo 7.7.1** (Tools über rokit: rojo + selene). Alle Texte im Spiel und alle Code-Kommentare sind **Deutsch**. Schulprojekt (5. Klasse, GD).

Status: baut mit `rojo build` fehlerfrei, selene meldet 0 Fehler (nur 3 Stil-Warnungen in MilkingClient). **Noch nicht in Studio gespielt/getestet.**

## Ordnerstruktur

```
default.project.json        Rojo-Baum (siehe unten)
rokit.toml / selene.toml    Tools (rojo, selene; std = "roblox")
src/shared/   -> ReplicatedStorage.Shared   (ModuleScripts, Server + Client)
  CowData.lua               alle Spielwerte, Seltenheiten, Zucht-Chancen, Kisten, Karte, Sound-IDs
  CowModelBuilder.lua       baut Kuh / Melkschemel / Eimer aus Parts (SpecialMesh-Kugeln)
src/server/   -> ServerScriptService.Server
  DataService.lua           ModuleScript: DataStore laden/speichern, API für alle Server-Scripts
  PlayerDataManager.server  Laden bei Join, Speichern bei Leave/Autosave/BindToClose, Starter-Kuh, TutorialDone
  CowManager.server         Plots, Kühe, Melken, Verkaufen, Shop, Kisten, Zucht, Auto-Melker, Robux
  LoginStreak.server        täglicher Bonus, 7 Tage am Stück -> Rainbow Cow
  MapBuilder.server         Hub-Platz, Allee, 2 Förderbänder, 4 Shop-Gebäude mit NPC
src/client/   -> StarterPlayerScripts.Client
  CoinDisplay.client        HUD (oben Coins/Logo/Milch/Streak, unten VERKAUFEN-Knopf, Benachrichtigungen)
  MenuUI.client             Fenster: Shop, Kisten, Zucht, Tagesbonus, Auto-Melker + runde Seitenknöpfe
  MilkingClient.client      Melk-Minispiel-UI
  WorldAnimator.client      alle Welt-Animationen + Ambient-Sounds
```

`default.project.json` legt außerdem an: `ReplicatedStorage.Remotes` (alle Remotes), `Workspace.CowFarmLayout.Plots`, `Workspace.Baseplate`.

## Remotes (ReplicatedStorage.Remotes)

| Name | Typ | Richtung | Zweck |
|---|---|---|---|
| SellMilk | RE | C→S | ganze Milch verkaufen |
| BuyCow | RF | C→S | (rarity) → ok, msg/cowId |
| OpenCrate | RF | C→S | (crateId, payWithRobux) → ok, rarity/msg, cowId |
| StartBreeding | RF | C→S | (cowIdA, cowIdB) → ok, readyAt/msg |
| GetInventory | RF | C→S | Coins, Milk, Cows[], Breeding, LoginStreak, HasAutoMilker, ServerTime |
| BuyAutoMilker | RE | C→S | Gamepass-Kaufdialog |
| MilkPull | RE | C→S | ("Left"/"Right") ein Zug |
| StopMilking | RE | C→S | Melken abbrechen |
| TutorialDone | RE | C→S | Tutorial als gesehen speichern |
| MilkingStarted | RE | S→C | {CowId, CowName, Rarity, PullsNeeded, MilkPerPull, Penalty, Spot} |
| MilkingProgress | RE | S→C | (pulls, lastSide) echter Stand vom Server |
| MilkingEnded | RE | S→C | (completed, milk) |
| OpenShop | RE | S→C | (page) Shop-Gebäude wurde angeklickt |
| Notify | RE | S→C | (text, kind) kind = info/success/error/rare |
| InventoryChanged | RE | S→C | Menü neu laden |

Spieler-Attribute (vom Server via DataService.Sync): `Coins`, `Milk`, `CowCount`, `LoginStreak`, `TutorialDone`, `HasAutoMilker`. Plus leaderstats `Coins`, `Kühe`.

## Daten (DataStore "CowFarm_PlayerData_v1", Key "Player_<UserId>")

```lua
{ Version=1, Coins=100, Milk=0, TotalMilk=0,
  Cows = { c1 = {Id, Rarity, Name, Obtained, MilkReadyAt} },  NextCowId,
  Breeding = {ParentA, ParentB, StartedAt, ReadyAt} | nil,
  LoginStreak = {Streak, LastDay, Best},
  Receipts = { [PurchaseId] = os.time() },   -- Robux-Doppelvergabe-Schutz
  ReceivedStarterCow, TutorialDone }
```
Laden mit 3 Retries; fehlende Felder werden aufgefüllt (reconcile). In Studio ohne API-Zugriff: Testdaten, kein Speichern. Live: bei Ladefehler Kick. DataService-API: `Load, Save, Release, Get, WaitForData, Sync, AddCoins, SpendCoins, AddMilk, TakeAllMilk, AddCow, CountCows, HasCowSpace, Notify, FireInventoryChanged`, Event `CowAdded(player, cow)`.

## Spielmechanik (Werte in CowData.lua)

- Start: 100 Coins + Gratis-Common-Kuh. Milch = 2 Coins/Liter. Max 40 Kühe (Robux-Käufe dürfen drüber).
- Seltenheiten (MilkPerPull / Melk-Pause s / Shoppreis):
  Common 2/20/100 · Uncommon 5/25/600 · Rare 12/30 · Epic 30/45 · Legendary 75/60 ·
  Special: Golden 200 · Rainbow 160 · Ghost 130 (Pause 60).
- Kühe bekommen: Shop (Common, Uncommon), Zucht, Kisten (Holzkiste 500 Coins, Silberkiste 3000 Coins oder Robux, Premium-Kiste nur Robux mit 5 % Ghost).
- Zucht: Tabelle nach Durchschnitt der Eltern-Stufen (z.B. 2x Common: 90 % Common / 10 % Uncommon; 2x Legendary: 30 % Epic / 69 % Legendary / **1 % Golden**, Golden nur bei 2 echten Legendary). Dauer 5–20 Min, läuft auch offline; Kalb kommt automatisch.
- Rainbow Cow: nur durch 7-Tage-Login-Streak (UTC-Tage). Ghost Cow: nur Premium-Kiste. Täglicher Bonus = 25 × Tag (1–7).
- Auto-Melker (Gamepass): alle 3 s Milch von jeder Kuh.
- **Platzhalter, die noch eingetragen werden müssen:** `AutoMilkerGamePassId = 0`, `Crates.Super.ProductId = 0`, `Crates.Premium.ProductId = 0`, optional `MilkingAnimationId = 0`.

## Melk-Minispiel

1. Kuh anklicken (ClickDetector) **oder** auf die blaue "🥛 Melken"-Platte neben der Kuh laufen (Touched). Nur der Besitzer.
2. Server teleportiert auf den Schemel und setzt den Spieler (Seat:Sit), Kuh bekommt Attribut `BeingMilked`.
3. Client: Bildschirm abgedunkelt, Panel gleitet hoch (Cartoon-Kuhgesicht, Eimer füllt sich, runde Knöpfe ◄ ► bzw. Q/E, Controller L1/R1).
4. Abwechselnd ziehen. Richtig: +1 Zug, Kamera wackelt, Sound, "+X" fliegt hoch. Gleiche Seite nochmal: −1 Zug, Knöpfe rot.
5. 10 Züge = Eimer voll → Milch = Züge × MilkPerPull, "+X Milch!" über der Kuh, Kuh bekommt Cooldown (Timer über der Kuh). Abbruch (Springen/Weglaufen >10 Studs/Aufstehen) gibt anteilige Milch.
6. Server ist maßgeblich (prüft Seite, Rate-Limit `MinPullInterval`) und schickt `MilkingProgress`.

## Karte (CowData.Map)

- Hub-Platz im Süden (z −100..0): Milch-Brunnen, Spawn, "COW FARM"-Bogen, 4 Shop-Gebäude: KUH-SHOP 🐄, KISTEN ✨, ZUCHT-STALL 💕, AUTO-MELKER 🥛. Jedes mit Licht innen, winkendem NPC mit Strohhut, hüpfendem Schild "KLICKEN ZUM ÖFFNEN". Klick → Server → `OpenShop`.
- Allee nach Norden mit **2 Förderbändern** (Nord/Süd, 22 Studs/s): unsichtbares Band mit `AssemblyLinearVelocity` schiebt Spieler; 6 Kacheln à 10×0.5×50 (schwarz mit gelben Pfeilen) bewegt der Client per Heartbeat nach Serverzeit; Rücksprung versteckt in Gehäusen an den Enden.
- Plots: ungerade Slots links (Westen), gerade rechts, Reihen ab z = 70 alle 95 Studs, Tor zeigt zur Allee. Plot = gestreifte Wiese, Steinkante, weißer Zaun, Torbogen mit Namen, Weg, Heuballen, Milch-Stand (ProximityPrompt F = verkaufen). Kühe im Raster 6 Spalten, jede mit Schemel, Eimer, Melk-Platte. Spieler wird beim Spawn auf seine Farm teleportiert. Ca. 8 Spieler passen gut.

## Kuh-Modell & Animation

- Cartoon-Stil: Kopf-Kugel 2.5, Körper 5×3×7, kurze Beine, große Augen, rosa Schnauze, großes Euter mit 4 Zitzen (`TeatLeftA/B` vorne, `TeatRightA/B` hinten), 3–5 Flecken (pro Kuh-ID immer gleich).
- Gruppen für Animation: `HeadGroup`, `EarLeft`, `EarRight`, `TailGroup` (Pivot-Gelenke). Tag "Cow".
- WorldAnimator (Client): schweben, Kopf ±15°, Schwanz wedeln, Ohren flattern, alle 5–12 s umdrehen; TweenService-Werte, angewendet mit `workspace:BulkMoveTo`, nur in < 160 Studs Entfernung. Rainbow wechselt jede Sekunde die Farbe. Während des Melkens steht der Körper still.
- Effekte: Uncommon Funken · Rare blaues Licht · Epic lila Licht + Partikel · Legendary Goldlicht + Sterne · Golden sehr hell + Lichtstrahl + Münz-Partikel · Rainbow bunte Partikel · Ghost 50 % durchsichtig + grünes Licht + Schwaden.
- Neue Kuh: fällt vom Himmel (Bounce), Konfetti, Sound (Fanfare ab Epic).

## UI

- HUD (CoinDisplay): obere Leiste über volle Breite (Coins mit Spielautomat-Ziffern, Logo, Milch, Streak), unten pulsierender grüner "MILCH VERKAUFEN 🥛"-Knopf, Benachrichtigungen rechts (grün/rot/gold/blau, 2,5 s), Coin-Sound.
- MenuUI: runde Knöpfe links (Shop, Kisten, Zucht, Tagesbonus, Auto). Kisten mit "Spielautomat"-Enthüllung, Zucht mit Chancen-Anzeige und Countdown, Tagesbonus mit 7 Tagesfeldern.

## Sounds (CowData.Config)

Melken 5857005819 · Coins 4590662766 · Ambient 1843671818 · Muhen 535690488. Shop-Öffnen `rbxasset://sounds/swoosh.wav` und Fanfare `rbxasset://sounds/victory.wav` sind ungeprüfte eingebaute Sounds (bei Stille eigene IDs eintragen).

## Blender-Kuh (CowModell.blend)

- `tools/export_cow.py` exportiert nur die Kuh-Teile nach `assets_src/CowModell.fbx` (`blender CowModell.blend --background --python tools/export_cow.py`).
- In Studio mit dem 3D-Importer importieren, Modell `CowModel` nennen, per "Save to File" als `assets/CowModel.rbxm` speichern → Rojo legt es nach `ReplicatedStorage.Assets.CowModel`.
- `CowModelBuilder.BuildCow` nimmt automatisch dieses Modell (erkennt Teile an den Blender-Namen Koerper, Kopf, Zitze_…, Fleck_… usw.; dreht, skaliert auf 6.4 Studs, färbt pro Seltenheit). Fehlt es, wird die alte Part-Kuh gebaut.

## Offen / nächste Schritte

1. **Tutorial-Client fehlt noch** (Datenseite ist fertig: `TutorialDone`-Flag, Remote, Alt-Spieler werden übersprungen). Geplant: 3-s-Kameraschwenk, Willkommens-Popup "Gratis-Kuh", gelbe Pfeile Farm → Kuh → Verkaufen-Knopf → Shop. Bis dahin bekommen neue Spieler keine Begrüßung.
2. Playtest in Studio: Förderbänder tragen den Spieler? Giebel-Keile der Shop-Dächer richtig herum? Flecken/Gesicht der Kuh sitzen richtig? 2-Spieler-Test (eigene Plots, fremde Kühe nicht melkbar).
3. Gamepass-/Produkt-IDs eintragen; Studio: "Enable Studio Access to API Services" für DataStore.
4. Starten: `rojo serve` im Projektordner, in Studio Rojo-Plugin → Connect (localhost:34872).
