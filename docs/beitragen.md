# Mithelfen: deine Datenbank an das Projekt schicken

ezCollection merkt sich beim Spielen, was nur im Spiel zu erfahren ist: welche Gegner was fallen lassen, wo Kräuter und Erze stehen, was Händler und Lehrer anbieten. Wer mag, schickt das als **anonymen Text** an das Projekt. Das Projekt prüft die Beiträge, führt sie zusammen und liefert das Ergebnis mit der nächsten Fassung an alle aus. Freiwillig, nie von selbst – ezCollection verschickt nichts; Spieler tauschen untereinander nichts aus.

**Was davon im Spiel zu sehen ist** (immer als „aus Beiträgen (n Spieler), Stand Build x“, nur wo der Client, ein installiertes Addon und deine eigenen Daten nichts wissen): Fundorte von Kräutern und Erz, Angelbeute, die nötige Sammel-Fertigkeit, Beute von Gegnern, Inhalt von Behältern, „fällt von“ und „verkauft von“ am Gegenstand, Lehrer von Rezepten und Waffenfertigkeiten, Flugzeiten, Gebietsstufen und Entzauber-Ergebnisse. Namen werden nicht ausgeliefert: Ein Gegner oder Händler wird erst genannt, wenn dein Client oder Questie seinen Namen kennt. Nicht gebraucht werden Eingänge und Farbgrenzen der Rezepte – die liefern die Client-Tabellen schon.

## Für Helfer (deutsch)

1. **Addons installieren.** ezCollection (Ordner `ezCore`) samt den Ordnern `ezWorld` und `ezMarket` – `ezWorld` trägt die Datenbank, ohne ihn gibt es keine Datei zum Schicken. Nichts einschalten: die Datenbank sammelt ab Werk von selbst (Schalter „Datenbank: Erlebtes sammeln“ unter Esc » Optionen » AddOns » ezCollection » „Erweitert“).
2. **Normal spielen.** Am besten etwa einen Monat; mehr ist nicht zu tun.
3. **„Beitrag vorbereiten“ anklicken und den Text schicken.**
   - Am selben Ort bei „Beitrag vorbereiten“ auf „Vorbereiten“ drücken (oder `/ez beitrag`). Nach deiner Einwilligung erscheint der anonyme Text: Strg+C kopiert ihn ganz. „Lesbar zeigen“ zeigt, was darin steht.
   - Auf der Projektseite ein neues Issue mit der Vorlage „Beitrag zur Datenbank“ öffnen („Adresse zeigen“ bzw. `/ez mithelfen` nennt die Adresse), den Text einfügen, die Einwilligung ankreuzen. Ist er länger als 60 000 Zeichen, im Editor als `beitrag.txt` speichern und hineinziehen (höchstens 25 MB).

**Die Daten-Probe (`/ez probe auto`) brauchst du dafür nicht.** Sie ist ein Entwicklerwerkzeug für offene Fragen an den Client und hat eine eigene Grenze von 3 MB – die gilt nur für die Probe, nicht für die Datenbank (die sammelt weiter; ab 8 MB kommt nur ein Hinweis). Wer dem Entwickler bei solchen Fragen helfen will, schaltet sie nur nach Absprache zusätzlich ein. Ihre Datei (`ezCore.lua`) ist nicht bereinigt, nennt deine Charaktere und gehört nie in ein öffentliches Issue.

**Was drin steht:** Daten über die Spielwelt (Gegner, Objekte, Orte, Händler, Lehrer, Rezepte, Flugzeiten) – nur Nummern und Zahlen, jeweils mit dem Build des Spiels und dem Tag. **Was nicht drin steht:** Namen von Charakteren, Gilden, Realms oder Mitspielern, Realm-Angaben, Uhrzeiten, Namen aus dem Spiel, Chat- und Brieftexte, Gold, Taschen, Einstellungen, seltene Gegner und Schätze (von seltenen Gegnern nur die Nummer). Bereinigt wird im Spiel, bevor es etwas zu kopieren gibt; das Projekt prüft mit denselben Regeln noch einmal außerhalb des Spiels.

**Wie anonym ist das?** Der Text enthält nichts, was auf dich, deinen Charakter oder deinen Realm zeigt. Ablesen lässt sich allenfalls, welche Klasse und Berufe du spielst und an welchen Tagen. Dazu kommt eine **Zufallskennung** deiner Datenbank: Sie verhindert doppeltes Zählen und erlaubt, einen Beitrag zurückzuziehen. Öffentlich sichtbar ist am Issue dein **GitHub-Name** – soll er das nicht, gib den Text jemandem, der ihn für dich einstellt; dann brauchst du auch kein Konto. Die Datei `ezWorld.lua` aus dem Ordner des Spiels bitte nicht anhängen: Sie ist nicht bereinigt.

**Mehrmals schicken** ist ausdrücklich erwünscht: Je Datenbank zählt nur der neueste Beitrag, nichts zählt doppelt. **Zurückziehen:** im Issue schreiben oder die Kennung nennen (`/ez mithelfen` zeigt sie) – der Beitrag bleibt ab der nächsten Fassung draußen.

## For helpers (English)

1. **Install the addons.** ezCollection (folder `ezCore`) together with the folders `ezWorld` and `ezMarket` – `ezWorld` carries the database; without it there is no file to send. Nothing to switch on: the database collects by itself by default (switch “Database: collect what you experience” under Esc » Options » AddOns » ezCollection » “Advanced”).
2. **Play normally.** Ideally for about a month; nothing else to do.
3. **Click “Prepare contribution” and send the text.**
   - In the same place press “Prepare” next to “Prepare contribution” (or `/ez contribute`). After your consent the anonymous text appears: Ctrl+C copies all of it. “Show readable” shows what is in it.
   - On the project page open a new issue with the template “Contribution to the database” (“Show address” or `/ez helpout` names the address), paste the text, tick the consent. If it is longer than 60,000 characters, save it as `beitrag.txt` in a text editor and drag it in (25 MB at most).

**You do not need the data probe (`/ez probe auto`) for this.** It is a developer tool for open questions about the client and has a limit of its own of 3 MB – that applies to the probe only, not to the database (which keeps collecting; from 8 MB on there is only a hint). Volunteers who want to help the developer with such questions switch it on in addition, by arrangement only. Its file (`ezCore.lua`) is not cleaned, names your characters and never belongs in a public issue.

**What it holds:** data about the game world (enemies, objects, places, vendors, trainers, recipes, flight times) – numbers only, each with the game build and the day. **What it does not hold:** names of characters, guilds, realms or other players, realm details, times of day, names from the game, chat and mail texts, gold, bags, settings, rare enemies and treasures (of rare enemies only the number). The game cleans it before there is anything to copy; the project checks it again with the same rules outside the game.

**How anonymous is it?** Nothing in the text points to you, your character or your realm. At most it reveals which class and professions you play and on which days. Added is a **random ID** of your database: it prevents double counting and allows a contribution to be withdrawn. Your **GitHub name** is public on the issue – if it should not appear, give the text to someone who posts it for you; then you need no account either. Please do not attach the file `ezWorld.lua` from the game folder: it is not cleaned.

**What is shown in the game** (always as “from contributions (n players), build x”, only where the client, an installed addon and your own data know nothing): spots of herbs and ore, fishing catches, the required gathering skill, loot of enemies, contents of containers, “drops from” and “sold by” on the item, trainers of recipes and weapon skills, flight times, zone levels and disenchanting results. Names are not shipped: an enemy or vendor is only named once your client or Questie knows the name. Entrances and recipe color thresholds are not needed – the client tables already provide them.

**Sending again** is welcome: per database only the newest contribution counts, nothing is counted twice. **Withdrawing:** say so in the issue or name the ID (`/ez helpout` shows it) – the contribution stays out from the next version on.

## Werte messen (für Helfer, deutsch)

Die berechneten Talentverteilungen (ezTalent) und Rotationen (ezCombat) brauchen die Grundwerte jeder Klasse und jedes Volkes ohne Ausrüstung. Die Client-Tabellen liefern Talente, Zauber und Koeffizienten schon (wago.tools), die Grundwerte stehen nur auf dem Server – darum misst sie, wer mag, im Spiel. Stufe 60 ist nicht nötig: **je Klasse zwei verschiedene Stufen** genügen (am besten mit zwei Völkern), daraus rechnet das Projekt die übrigen Stufen hoch.

1. Alle Gegenstände außer Hemd und Wappenrock ablegen, keine Stärkungszauber, außerhalb des Kampfes.
2. Das Talentfenster einmal öffnen, dann `/ezt werte` (oder Esc » Optionen » AddOns » ezCollection » ezTalent » Erweitert » „Werte für die Simulation messen“) und `/ezk werte` (ezCombat). Englisch auch `/ezt values` und `/ezk values`.
3. Den Text aus dem Fenster kopieren und in ein neues Issue mit der Vorlage „Werte messen“ einfügen (dieselbe Projektseite wie oben).

**Was die Texte enthalten:** Klasse, Volk, Stufe, Sprache, Build, Datum, die gemessenen Werte, Talente und Zauber – keine Namen von Charakteren, Gilden oder Realms. **Wofür:** berechnete Talentverteilungen und Rotationen für alle Spieler. Mehrere Messungen derselben Klasse auf verschiedenen Stufen sind ausdrücklich erwünscht.

## Measuring values (for helpers, English)

The computed talent builds (ezTalent) and rotations (ezCombat) need the base values of every class and race without gear. The client tables already provide talents, spells and coefficients (wago.tools); the base values exist only on the server, so anyone who likes measures them in the game. Level 60 is not required: **two different levels per class** are enough (ideally with two races); the project extrapolates the other levels.

1. Take off all items except shirt and tabard, no buffs, out of combat.
2. Open the talent window once, then `/ezt values` (or Esc » Options » AddOns » ezCollection » ezTalent » Advanced » "Measure values for the simulation") and `/ezk values` (ezCombat).
3. Copy the text from the window and paste it into a new issue with the template "Measure values" (same project page as above).

**What the texts contain:** class, race, level, language, build, date, the measured values, talents and spells – no names of characters, guilds or realms. **What for:** computed talent builds and rotations for every player. Several measurements of the same class at different levels are very welcome.

## Fehler melden und Code beitragen (deutsch)

- **Fehler und Wünsche:** als Kommentar auf CurseForge oder Wago oder als Issue in diesem Repo. Hilfreich ist der Text aus Esc » Optionen » AddOns » ezCollection » „Erweitert“ » „Fehlerliste zum Kopieren“ (oder `/ez fehler kopieren`). Bildschirmfotos nur mit unkenntlich gemachten Namen (Charaktere, Gilden, Realms, Chat).
- **Code, Texte, Übersetzungen:** als Pull Request gegen `main`, ein PR je Modul. Ein Fork ist nur dafür erlaubt; mit dem Beitrag räumst du die Rechte nach Abschnitt 3 der [Lizenz](../LICENSE) ein (maßgeblich ist der englische Text, Übersetzung: [lizenz-deutsch.md](lizenz-deutsch.md)). Der Autor übernimmt angenommene Beiträge von Hand in die nächste Fassung und prüft sie dort mit den automatischen Tests (LuaJIT, ohne Spiel).
- **Regeln für den Code:** Blizzards eigene Fenster, Vorlagen und Texturen erweitern statt eigene Fenster zu bauen ([design-system.md](design-system.md)); gemeinsame Daten und Helfer gehören nach ezCore, keine Kopien in Modulen ([ezcore.md](ezcore.md)); taint-sicher – nur `hooksecurefunc`/`HookScript`, nie Werte in Blizzards Tabellen schreiben, geschützte Aktionen nur außerhalb des Kampfes ([blizzard-regeln.md](blizzard-regeln.md)); geheime Werte zuerst mit `ezCore.IsSecret` prüfen; jede Funktion bekommt einen sichtbaren Knopf, Reiter oder Pfeil; Texte deutsch und englisch, Einstellungen `OPT_<key>` mit Tooltip `OPT_<key>_TIP`; Lua 5.1; kein Code und keine Daten aus anderen Addons.
- **Im Spiel prüfen:** Schreib in den PR, was im Spiel zu prüfen ist – die Tests laufen ohne Spiel.

## Reporting bugs and contributing code (English)

- **Bugs and wishes:** as a comment on CurseForge or Wago, or as an issue in this repository. The text from Esc » Options » AddOns » ezCollection » “Advanced” » “Error list to copy” (or `/ez errors copy`) helps. Screenshots only with names made unreadable (characters, guilds, realms, chat).
- **Code, texts, translations:** as a pull request against `main`, one PR per module. A fork is allowed for this purpose only; by contributing you grant the rights under section 3 of the [licence](../LICENSE). The author takes accepted contributions over by hand into the next version and checks them there with the automated tests (LuaJIT, without the game).
- **Rules for the code:** extend Blizzard's own windows, templates and textures instead of building new windows ([design-system.md](design-system.md), German); shared data and helpers belong in ezCore, no copies in modules ([ezcore.md](ezcore.md), German); taint-safe – only `hooksecurefunc`/`HookScript`, never write into Blizzard's tables, protected actions only out of combat ([blizzard-regeln.md](blizzard-regeln.md), German); check secret values with `ezCore.IsSecret` first; every function gets a visible button, tab or arrow; texts in German and English, settings `OPT_<key>` with tooltip `OPT_<key>_TIP`; Lua 5.1; no code or data from other addons.
- **Checking in the game:** say in the PR what should be checked in the game – the tests run without it.
