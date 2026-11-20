# Cow Farm – Regeln für Claude

Zwei Leute arbeiten gleichzeitig an diesem Spiel, jeder mit seinem eigenen Claude:
**Archie** (GitHub: SigmaArchie) und **Maxi** (Maximilian). Damit sich die beiden Claudes
nicht gegenseitig Dateien kaputtmachen, gilt das Board in [ARBEIT.md](ARBEIT.md).

Projekt-Details (Ordner, Remotes, Daten, Stil) stehen in [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).
Alle Texte im Spiel und alle Code-Kommentare sind **Deutsch**.

## Vor JEDER neuen Aufgabe (auch kleinen)

1. Neuesten Stand holen:
   ```
   git fetch --all --prune
   git show origin/main:ARBEIT.md
   ```
2. Schauen, was die anderen offenen Branches gerade ändern:
   ```
   git branch -r --no-merged origin/main
   git diff --name-only origin/main...origin/<branch>
   ```
   Das zusammen mit der Tabelle "Gerade in Arbeit" in ARBEIT.md ergibt die **belegten Dateien**.
3. Braucht die Aufgabe eine belegte Datei, dann **nicht anfassen**: dem Nutzer sagen, wer sie
   gerade hat, und eine andere Aufgabe vorschlagen oder warten. Ausnahme nur, wenn der Nutzer
   ausdrücklich sagt, dass er das mit dem anderen abgesprochen hat.
4. Aufgabe **eintragen, bevor Code geschrieben wird**: Zeile in "Gerade in Arbeit" (Wer, Aufgabe,
   Branch, Dateien) direkt auf `main` committen und pushen (nur ARBEIT.md, Nachricht
   `Board: <Wer> nimmt <Aufgabe>`). Wird der Push abgelehnt: `git pull --rebase`, Schritt 2 wiederholen.
5. Eigener Branch pro Aufgabe (`feature/...` oder `fix/...`), **früh pushen**, gern als Draft-PR,
   damit der andere Claude sieht, welche Dateien sich ändern.

## Während der Arbeit

- Lieber **neue Dateien** anlegen (eigenes Modul) als große gemeinsame Dateien umbauen.
  In geteilten Dateien wie `CowData.lua`, `CowManager.server.lua`, `MenuUI.client.lua` nur
  kleine Ergänzungen an einer Stelle.
- Kommt eine weitere Datei dazu, die Zeile in ARBEIT.md ergänzen (wieder nur ARBEIT.md auf `main`).
- Vor dem PR: `git merge origin/main` in den eigenen Branch, dann `stylua src`, `selene src`,
  `rojo build -o cow_melk.rbxlx` (die CI prüft alle drei).

## Wenn die Aufgabe fertig ist

- PR nach `main`, nach dem Merge die Zeile aus "Gerade in Arbeit" nach "Erledigt" schieben
  (ARBEIT.md auf `main`).
- Neue Remotes, Daten oder Spielregeln in PROJECT_OVERVIEW.md nachtragen.

## Stil

- UI im Holz-Farm-Stil über `src/client/Theme.lua` (Holzfenster, Gras-Kopf, Titelschild, rotes X,
  weiße Schrift mit dunklem Umriss, Knöpfe Grün/Gold/Blau/Orange/Rot). Keine eigenen Farben in
  einzelnen Fenstern, sondern `Theme.Colors` / `Palette`.
- 3D-Modelle aus Blender per Skript (`tools/make_props.py`), Einbau über MeshParts aus
  `ReplicatedStorage.Assets` mit Ersatz aus Parts, falls das Modell fehlt.
