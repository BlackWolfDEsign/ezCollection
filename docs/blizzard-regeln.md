# Blizzards Regeln für Addons – wie ezCollection sie einhält

Diese Datei zeigt, wie ezCollection Blizzards Regeln für Addons und die technischen Sperren der Retail-Engine einhält, auf der WoW Forever läuft: jede Regel mit Beleg im Code, alle Abläufe ohne Klick mit Standard und Drossel, alle Chat-Ausgaben und die geschützten Aufrufe. Belege stehen als Datei und Funktion bzw. Schlüssel; Zeilennummern nur, wo sie nachgelesen sind.

**Begriffe:** *Verstoß* – klar gegen eine Regel oder eine technische Sperre. *Risiko* – kann im Grenzfall gegen eine Regel verstoßen oder Taint auslösen (Blizzard hält eigenen Code für „von einem Addon angefasst“ und meldet im Kampf „Aktion durch AddOn blockiert“). *Hinweis* – sauber, aber dokumentiert. *Ohne Klick* – läuft ohne Klick des Spielers in diesem Moment (Ereignis, Zeitgeber).

## Quellen

1. **UI Add-On Development Policy** – Blizzards Forum, Beitrag vom 19.11.2018 mit Nachträgen von 2009: <https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534>. Abgerufen am 17.11.2026; unten in eigener Zusammenfassung, keine Übernahme des Wortlauts.
2. **Geschützte Funktionen und Taint** – <https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting>: geschützte Funktionen nur aus sicherem Ablauf, Zaubern und Zielen nur auf Klick oder Taste des Spielers, im Kampf gesperrte Rahmen (`InCombatLockdown`), Erweitern über `hooksecurefunc`/`HookScript`.
3. **Regeln der Midnight-Engine** (gelten für Forever, das auf der Retail-Engine läuft) – <https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight>, dazu <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes> und <https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes>: Aussehen, Lage und Darstellung von Kampfinformationen ändern ist erlaubt; geheime Werte werden gezeigt, aber nicht ausgewertet; das Kampflog ist für Addons zu.
4. **Forevers Entwickler-Hinweise:** `C_SuperTrack.SetSuperTrackedUserWaypoint` gehört zu den Aufrufen, die Addon-Code nicht machen soll.
5. **Blizzards Forever-Quelle** (Gethe/wow-ui-source, Zweig `forever`) für Vorlagen und Belege einzelner Stellen (`HelpTip.lua`, `ContainerFrame.lua`, `Bindings_Camelot.xml`).

## 1. Ergebnis

- **Richtlinie 1 bis 8: eingehalten.** ezCollection ist kostenlos, offen lesbar, ohne Werbung und ohne Spendenaufruf im Spiel; kein Modul wirkt Zauber oder wählt Ziele selbst.
- **Kampfinformationen:** Das Kampflog wird nicht gelesen. ezCombats Vorschlag „Als Nächstes“ rechnet ab Werk nur mit offenen Werten; das „Mitzählen“ gesperrter Werte ist ab Werk aus und meldet sich mit einem Hinweis (V1 und V2 in Abschnitt 3).
- **Abläufe ohne Klick, die Gold kosten, verkaufen, senden oder Blizzards Zustände umstellen, sind ab Werk aus.** Wer sie aus einer früheren Fassung gespeichert an hatte, wurde beim Update einmal umgestellt (zuletzt „Auch Flüstern aus dem normalen Chat“ in ezChat, `ns.MigrateWhisperOptIn`). Eine Erklärblase mit Knopf „Einschalten“ (`Core.OptInHint`) meldet jeden davon einmal je Account am passenden Blizzard-Fenster – auch die Abläufe, die nie ab Werk an waren: automatisches Danken (nur, solange der Client die Heilvorhersage nicht sperrt – auf WoW Forever ist sie gesperrt und der Schalter ohne Wirkung) und Spucken (Makroverwaltung) und „Ränge automatisch aktualisieren“ (Zauberbuch) in ezMacro; Nachsenden aus dem normalen Chat und automatische Antwort (Chatfenster, beim Flüstern an andere) sowie „tippt …“ und Ort (Freundesliste) in ezChat; „Handel am Briefkasten blockieren“ und „Beim Öffnen einsammeln“ (Briefkasten) in ezMail; Beschwörung und Wiederbelebung annehmen, Duelle und Einladungen von Fremden ablehnen (Freundesliste) in ezSocial; die Kopplung mit Blizzards Aufspüren (Weltkarte) in ezMap; „Automatisch annehmen und abgeben“ (Questfenster) in ezQuest. Zum Nachsenden aus dem normalen Chat erscheint die Blase auch beim „Spieler nicht gefunden“, wenn eine Zeile nur wegen des ausgeschalteten Schalters nicht wartet. Ohne Hinweis bleiben reine Anzeigen und Abläufe, die nur lesen (etwa „Beim Öffnen erfassen“ in ezAuction: nur Suchanfragen, nichts an Spieler, kein Zustand umgestellt), Regeln, die der Spieler selbst je Absender setzt (ezMail „zurückschicken“), und Schalter, deren Umstellung unmittelbar die Folge des eigenen Klicks ist und danach nichts mehr ohne Klick tut (ezCore „Kamera weiter herauszoomen“: setzt die Kamera-CVar beim Ankreuzen und stellt sie beim Abwählen zurück; beim Einloggen nur derselbe gewählte Wert, nichts an den Server oder an Spieler).
- **„Durchbuffen“ (Risiko 25):** Das Addon wählt Zauber und Ziel, der Spieler drückt; ein Druck wirkt einen Zauber, nur außerhalb des Kampfes. Ein PreClick im Kampf ändert weder die Aktions-Attribute noch ruft er `SetAttribute` noch merkt er bei ezCore etwas vor (Durchbuff-Knopf und Haupt-Knopf; die Symbole am Gruppenrahmen haben keinen PreClick). Beim Kampfbeginn leert ezBuff auch die Aktion des Haupt-Knopfs, wenn sie auf ein nicht festes Kürzel zeigt (`nameplateN`, `target` …; maßgeblich ist die Belegung bei ezCore, auch nachdem der PreClick neu belegt hat – im Kampf kein Zauber auf ein womöglich anderes Ziel), und dankt höchstens einmal je erhaltenem Buff (Abschnitt 6).
- **Nur im Spiel zu klären** sind die Punkte des Taint-Protokolls (Abschnitt 8) und die Zeilen „nur Spielprüfung“ in Abschnitt 4. Die Daten-Probe ist gekennzeichnet: Ihre Sonderproben laufen nur mit dem Entwicklerschalter (Abschnitt 4, Hinweise).

## 2. UI Add-On Development Policy (Richtlinie 1 bis 8)

| Punkt (eigene Zusammenfassung) | erfüllt? | Beleg |
|---|---|---|
| 1. Kostenlos, keine Bezahlfassung, keine Bezahldienste | ja | Datei `LICENSE` (ezCollection-Lizenz 1.0: kostenlos nutzbar, Quelltext einsehbar) und `ezCore/Werkzeuge/Contribute.lua` (`Contribute.LICENSE`); im Code keine Freischaltung, kein Lizenzschlüssel, keine Bezahlstufe. |
| 2. Code nicht verschleiert | ja | Kein `loadstring`, `RunScript`, `setfenv`/`getfenv`, `dofile`/`loadfile` in ausgelieferten Dateien; `ezCore/Kern/Serialize.lua` liest Text Zeichen für Zeichen, ohne Code auszuführen. Datentabellen (`ezCore/Wissen/Client/*.lua`) sind Klartext mit Herkunftskopf. |
| 3. Keine Belastung von Realms und anderen Spielern | ja | Chat nur über `ezCore/Kern/Channels.lua` (`Core.SendChat`, `Core.PerformEmote`) mit Blizzards Chat-Sperre; Flüster-Wiederholung begrenzt auf 12 Versuche bzw. 24 Stunden und 120 s Abstand (`ezChat/Delivery.lua`, `MAX_TRIES`, `MAX_SPAN`, `MIN_GAP`; Risiko 9); automatische Emotes ab Werk aus mit Drossel; Auktionshaus-Suchen über ezCores Warteschlange nach Blizzards Drossel. Leistung des Komplett-Scans: Hinweis in Abschnitt 4. |
| 4. Keine Werbung | ja | Links nur als Quellenangabe und nur auf Wunsch (`ezTalent/Presets.lua`, `ezTalent/UI.lua`); Seiten kostenloser Addons nur auf der Einstellungsseite (`ezCore/Wissen/OtherAddOns.lua`). |
| 5. Keine Spendenaufrufe im Spiel | ja | Ein Spendenlink steht nur in der README, nicht im Spiel. Der Hinweis „Mithelfen“ bittet um Daten, nicht um Geld (`ezCore/Werkzeuge/Contribute.lua`, ab Werk einmal je Account, abschaltbar über den gemeinsamen Schalter „Hinweise und Angebote zeigen“ `OPT_optInHints` und den Knopf „Nicht mehr zeigen“). |
| 6. Inhalte innerhalb der Altersfreigabe | ja | Derbster Text ist das Spucken der automatischen Emotes („spuckt … verächtlich hinterher“, `ezMacro/Locale.lua`), wie Blizzards eigenes `/spit`; ab Werk aus. |
| 7. Nutzungsbedingungen einhalten | ja | Kein Bot, kein selbsttätiges Zaubern oder Zielen (Abschnitt 7). Zu den Midnight-Regeln: Abschnitt 3. |
| 8. Blizzard darf Funktionen abschalten | ja | ezCollection rechnet mit Sperren: Abbruch bei `ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` (`ezCore/Charakter/MailQueue.lua` auch für Briefe mit Anhang, `ezMap/TrackingMemory.lua` mit gespeicherter Sperre `ezMapDB.trackingBlock`); Blizzards Rotations-Assistent `C_AssistedCombat` hat Vorrang (`ezCombat/Rotation.lua`). |
| Nachtrag 2009: keine fremde Musik | ja | Keine Tondateien im Paket; Töne nur über Blizzards `SOUNDKIT` (`ezChat/Alarms.lua`). |

## 3. Geschützte Funktionen, geheime Werte, Kampflog

**V1 – eigene Empfehlung „Als Nächstes“ im Kampf (ezCombat).** Die Midnight-Regeln wenden sich dagegen, aus dem Kampfzustand Empfehlungen abzuleiten. ezCombat nutzt dafür nur Blizzards Lua-Schnittstelle und keine gesperrten Werte; das Risiko ist, dass Blizzard die Lücke schließt. *Stand:* Die Vorhersage bleibt (`rotation = true`, `rotationInCombat = true`, `ezCombat/Core.lua`); ab Werk rechnet sie nur mit offenen Werten, ein gesperrter Schritt gilt als unbekannt und steht in `/ezk status`. Das Mitzählen gesperrter Werte hängt ganz an `rotationEstimate = false` (`ezCombat/Core.lua`, `State.Estimating` in `ezCombat/RotationState.lua`; auch der aus dem gedrückten Knopf erschlossene Name einer gesperrten Aura, Merker `guessed`). Wer es gespeichert an hatte, wurde einmal umgestellt (`estimateOff17`, alter Wert in `estimateOff17Was`); Hinweis mit Knopf „Einschalten“ am Zauberbuch. Mit „Eigene Empfehlung auch im Kampf“ aus gilt im Kampf nur Blizzards Assistent. Nichts wird gewirkt; geheime Werte werden vorher mit `Core.IsSecret` abgefangen.

**V2 – Kampflog in den automatischen Emotes (ezMacro).** *Stand:* entfernt. `ezMacro/AutoEmote.lua` meldet `COMBAT_LOG_EVENT_UNFILTERED` nicht an und ruft `CombatLogGetCurrentEventInfo` nicht auf; erkannt wird nur über Heilvorhersage und Todesrückblick.

**Geschützte Aktionen nur auf Klick bzw. außerhalb des Kampfes.** Zaubern, Benutzen und Zielen nur über ezCores sichere Knöpfe (`ezCore/Bausteine/SecureButton.lua`): Attribute, Lage und Tasten nur außerhalb des Kampfes, ausgelöst nur per Klick oder Taste; keine Datei ruft `CastSpell`, `UseAction`, `TargetUnit` oder `RunMacro` selbst. Einzelheiten in Abschnitt 7.

**Geheime Werte.** Überall `Core.IsSecret`/`Core.Plain`/`Core.Num` vor Vergleich und Rechnung (`ezCore/Kern/Util.lua`). Einheitenvergleiche laufen über `ns.OnUnit` ohne eigenen Vergleich (ezCombat `Hints.lua`, `Combo.lua`, `Swing.lua`); `GetPoint`-Rückgaben prüft ezPanel zuerst mit `Core.Usable` (`ezPanel/TopSpace.lua`: `InExpectedPlace`, `PlacePlain`, der `SetPoint`-Haken).

## 4. Risiken und Hinweise

| Nr. | Modul | Stelle (kurz) | Stand | Beleg |
|---|---|---|---|---|
| 1 | ezCombat | Gesperrte Werte aus eigenen Zaubern nachrechnen („Mitzählen“) | ab Werk aus, mit Hinweis | `rotationEstimate = false` |
| 2 | ezCombat | Unterbrecher leuchtet auch bei gesperrter Unterbrechbarkeit | behoben: leuchtet nur bei offenem `false` für „nicht unterbrechbar“ | `ezCombat/Hints.lua` |
| 3 | ezCombat | Größere Zielauren über Blizzards `SetLargeAuraSize` | nur Spielprüfung | Taint-Protokoll (Abschnitt 8) |
| 4 | ezMacro | Automatisches Danken und Spucken an fremde Spieler | ab Werk aus, Drosseln bleiben, Tooltips nennen „ohne Klick“ und den gesendeten Text; Hinweis an Blizzards Makroverwaltung | `autoThank`/`autoSpit = false` (`ezMacro/Core.lua`), `Auto.RegisterOptInHints` (`ezMacro/AutoEmote.lua`) |
| 5 | ezMacro | Bildschirmfoto blendet `UIParent` aus Addon-Code aus | behoben: Blizzards `SetUIVisibility` (Weg von Alt+Z), `UIParent:Hide` nur als Rückfall; im Kampf erst danach | `ezMacro/InfoTools.lua` |
| 6 | ezMacro | Ansage-Leiste mit sicheren Knöpfen in Blizzards Raid-Verwaltung | nur Spielprüfung | Taint-Protokoll |
| 7 | ezBars | Knöpfe aus Blizzards `ActionBarButtonTemplate` | nur Spielprüfung | Taint-Protokoll |
| 8 | ezChat | Wartende Nachrichten gehen beim Öffnen des Briefkastens als Brief (Porto) | ab Werk aus, einmal umgestellt, Hinweis am Briefkasten | `mailDelivery = false` (`ezChat/Core.lua`), `ns.MigrateMailOptIn` |
| 9 | ezChat | Flüster-Wiederholung ohne Obergrenze | behoben: höchstens 12 Versuche bzw. 24 h, mindestens 120 s Abstand, „Jetzt zustellen versuchen“ setzt zurück | `ezChat/Delivery.lua` |
| 10 | ezCore | Anhang-Schlange bricht bei Sperre erst nach 90 s ab | behoben: Abbruch sofort (`Finish(false, "BLOCKED")`), kein weiterer Brief ohne neuen Klick | `ezCore/Charakter/MailQueue.lua` |
| 11 | ezCore, ezBag | Plunder-Verkauf aus einem Zeitgeber, ohne Kampfprüfung | behoben: nie im Kampf, höchstens 10 Plätze je Runde (`Junk.MAX_PER_ROUND`, `Junk.MAX_ROUNDS = 40`); ezBag `autoSell` ab Werk aus, einmal umgestellt, Hinweis am Händler | `ezCore/Charakter/Junk.lua`, `ezBag/Core.lua` (`ns.MigrateAutoSellOptIn`) |
| 12, 13 | ezCore | Rechengrundlage und Abfragen für die Rotation | bleiben als Nachschlage-Daten; gezählt wird nur mit „Mitzählen“ | `ezCore/Wissen/Spells.lua` (Kopf: nur offene, nie gesperrte Felder) |
| 14 | ezGear | Charakterfenster aus Addon-Code umgeschaltet (`SetRightPaneCollapsed`, `PaperDollFrame_SetSidebar`) | nur Spielprüfung; nur per Menüklick, mit Kampfsperre | `ezGear/Sets.lua`; Taint-Protokoll |
| 15 | ezAuction | Preisregel, Menge und Dauer in Blizzards Verkaufsfelder | behoben: ohne Tor T1 „geht“ nur „Vorschlag“, nichts eingetragen | `ns.SellSetsValues()` (`ezAuction/Core.lua`), `ezAuction/SellTab.lua` |
| 16, 17 | ezAuction | „Bedarf: n“ löst Blizzards Ereignis aus; nächste Zeile nach dem Kauf vorwählen | bleiben ab Werk aus (Tor T1) | `buySetQuantity`, `buyNextSelect = false` (`ezAuction/Core.lua`) |
| 18 | ezAuction | Klick in der Taschenliste legt ohne Tor in Blizzards Verkaufsbereich | behoben: `Sell.Pick` prüft dasselbe Tor; ohne T1 nur Hervorheben und Verweis auf Blizzards Rechtsklick | `ezAuction/SellTab.lua` |
| 19 | ezMap | Aufspüren schaltet Such-Zauber ohne Klick ein | behoben: Such-Zauber selbst einschalten nur mit `trackingSpellAuto` (ab Werk aus, Hinweis an der Weltkarte); nach einer Sperre dauerhaft nur per Klick | `ezMap/Core.lua`, `ezMap/TrackingMemory.lua` (`ezMapDB.trackingBlock`) |
| 20 | ezMap | Blizzards Zielverfolgung ohne Klick (`C_SuperTrack`) | behoben: nur mit `wayTrack` (ab Werk aus, Hinweis), auch nach einem Klick | `ezMap/Core.lua`, `ezMap/Way.lua`, Abfrage `WaypointTracking()` |
| 21 | ezMap | Weltkarte öffnet über `ShowUIPanel` | behoben: über `Core.OpenPanel("map", …)` | `ezMap/Gather.lua` (`Gather.OpenMap`) |
| 22 | ezQuest | Questverfolgung umsortiert und Zielverfolgung gesetzt, Zeitgeber ohne Kampfprüfung | behoben: Zeitgeber prüft den Kampf (`ns.AfterCombat`); `sortTracker` und `sortSuperTrack` ab Werk aus mit Hinweis an der Questverfolgung | `ezQuest/Tracker.lua`, `ezQuest/Core.lua` |
| 23 | ezCraft | „Alle verschicken“ sendet weitere Briefe über einen Zeitgeber | behoben an der Ursache (Nr. 10); Empfänger nur eigene Charaktere | `ezCore/Charakter/MailQueue.lua` |
| 24 | ezTalent | Talentfenster verschoben und verkleinert (`SetScale`/`SetPoint`) | nur Spielprüfung; mit Kampfsperre, Blizzards Lage als Ausgang | `ezTalent/UI.lua` (`makeRoom`); Taint-Protokoll |
| 26 | ezChat | Blizzards Einheiten-Menü (`UnitPopup_OpenMenu` mit `PLAYER`/`PARTY`/`RAID_PLAYER`) aus Addon-Code für einen Partner in Reichweite | behoben: Klick auf den Namen im Gesprächskopf bzw. „Spieler-Menü (Blizzard)“ öffnet immer Blizzards Menü „FRIEND“ (`FriendsFrame_ShowDropdown`, wie ein Klick auf einen Namen im Chat), offline „FRIEND_OFFLINE“. Grund laut Blizzards Forever-Quelle (`Blizzard_UnitPopupShared/UnitPopupSharedMenus.lua`, `UnitPopupSharedButtonMixins.lua`): aus Addon-Code geöffnet blendet sich „Ziel auswählen“ selbst aus (`issecure`), „Fokus setzen“ aber nicht und ruft das geschützte `FocusUnit` – Blizzard blockiert es; „FRIEND“ hat keinen solchen Eintrag. Betrachten und Handeln gehen über Blizzards Einheitenrahmen | `Window.PlayerMenu` (`ezChat/Window.lua`) |
| 25 | ezBuff | „Durchbuffen“: das Addon wählt Zauber und Ziel, der Spieler drückt | technisch erlaubt (ein Druck wirkt einen Zauber, nur außerhalb des Kampfes); Grenzfall, bewusst so gelassen | `ezBuff/Group.lua` (`Next`, `PrepareNext`, PreClick), `ezBuff/Button.lua` (PreClick); Abschnitt 1 |

**Hinweise** (sauber, dokumentiert):

| Modul | Hinweis | Stand |
|---|---|---|
| ezCore | `Core.SendChat`/`Core.PerformEmote` ohne eigene Drossel; kein Aufrufer nutzt SAY, YELL oder CHANNEL (die Arten, die außerhalb von Instanzen einen Tastendruck brauchen) | so gelassen |
| ezCore | Versand ruft Blizzards `MailFrameTab_OnClick` und schreibt in `SendMailNameEditBox` | so gelassen; Taint-Protokoll |
| ezCore | Reparatur: erst Gildengeld, Rest nach 0,5 s aus eigenem Gold, nur bei offenem Händler (`ezCore/Charakter/Durability.lua`) | Automatik ab Werk aus (ein gemeinsamer Schalter `vendor.repairAuto` in ezCore für ezMerchant und ezPanel, mit Hinweis) |
| ezCore | Daten-Probe ist ein Entwicklerwerkzeug mit Serveranfragen, nur nach Rückfrage (`ezCore/Werkzeuge/ProbeStations.lua`); Testschalter `comfort.editModeOpen` öffnet Blizzards Bearbeitungsmodus aus Addon-Code (`ezCore/Bausteine/Mover.lua`) | gekennzeichnet: Sonderproben und Testschalter wirken nur mit dem Entwicklerschalter „Entwicklerwerkzeuge“ (`/ez debug entwickler`, ab Werk aus, unter „Erweitert“); die Automatik der Probe (nur lesend) bleibt |
| ezCore | Komplett-Scan des Auktionshauses liest bis zu 1000 Einträge je Bild (`Prices.SCAN_SLICE_ROWS`) | Leistung im Spiel zu messen |
| ezCore | Hinweis „Mithelfen“ verweist auf die Projektseite (`Core.PROJECT_URL`) | so gelassen |
| ezPanel | Fenster des Bearbeitungsmodus oben unter die Leiste rücken (`SetPointBase`), nie im Kampf | Taint-Protokoll |
| ezPanel | „Graue verkaufen“ hatte eine eigene Schleife ohne Kampfprüfung | behoben: über `Core.Junk.Sell` |
| ezBag | „Leichter zerstören“ füllt Blizzards Zerstören-Dialog vor; `UpdateContainerFrameAnchors` mit `rawget`-Schutz; Bank ohne Kampfprüfung verschoben (ungeschützter Rahmen) | so gelassen |
| ezCombat | Combo-Punkte über Blizzards `LayoutPointsCircle`, Totem-Leuchten ohne `secure`; Slash-Weg des Meter-Berichts fragt `meterReport` nicht ab | Meter-Bericht erledigt: der Schalter `meterReport` entfällt (Einstellungs-Prüfung 19.11.2026, Nr. 35 – der Eintrag handelt nur auf Klick); sonst offen |
| ezMacro | `PlaceSlots` der Schnittstelle belegt Aktionsplätze ohne Rückfrage, derzeit ohne Aufrufer | offen |
| ezQuest | Interaktionssymbole und Funkeln stellen Grafik-CVars um | ab Werk aus, einmal umgestellt, Blizzards Werte kommen zurück, Hinweis an der Questverfolgung |
| ezChat | Briefe mit Betreff „[ezChat]“ werden beim Übernehmen als gelesen markiert | so gelassen (`mailImport`) |

## 5. Abläufe ohne Klick

Abläufe, die nur lesen oder anzeigen (Tooltips, Leisten, Zähler, Entdecker-Sammler, Preis-Erfassung aus Suchergebnissen, Leseanfragen an den Server wie die Gildenliste – ezPanels Baustein „Soziales“ jede Minute, ezChat alle 120 s, solange Nachrichten warten), sind zusammengefasst. „Ab Werk“ ist der Standard im Code; „Hinweis“ heißt: ezCores Erklärblase am genannten Fenster (`Core.OptInHint`, Abschnitt 1); „Bestand umgestellt“: wer es aus einer früheren Fassung an hatte, wurde einmal umgestellt.

| Modul | Ablauf | Auslöser | Ab Werk | Drossel, Sperre |
|---|---|---|---|---|
| ezCore | Plunder beim Händler verkaufen (ein Schalter `vendor.autoSell` für ezBag und ezMerchant; es verkauft ezBag, ohne ezBag ezMerchant) | `MERCHANT_SHOW` | **aus** (Hinweis am Händler; Bestand umgestellt, die alten Schalter der Module einmal übernommen) | über ezCore: 10 Plätze je Runde, nie im Kampf, Shift überspringt |
| ezCore | Automatisch reparieren (ein Schaltersatz `vendor.repairAuto`, `repairGuild`, `repairReport` für ezMerchant und ezPanel; es repariert ezMerchant, ohne ezMerchant ezPanel) | `MERCHANT_SHOW` | **aus** (Hinweis am Händler; die alten Schalter der Module einmal übernommen) | einmal je Besuch; nie im Kampf: wartet bis danach und läuft nur bei noch offenem Händler und noch eingeschaltetem Schalter ohne anderes Addon dafür |
| ezMerchant | Vorrat auffüllen | `MERCHANT_SHOW` | **aus** (Hinweis) | Kostendeckel, nie im Kampf: wartet bis danach und läuft nur bei noch offenem Händler und noch eingeschaltetem Schalter, ein Kampfbeginn hält das automatische Auffüllen an |
| ezChat | Wartende Nachrichten als Brief beim Briefkasten | `MAIL_SHOW` | **aus** (Hinweis am Briefkasten; Bestand umgestellt) | 1,5 s, Abbruch bei Sperre |
| ezChat | Wartende Nachrichten aus dem Gesprächsfenster nachsenden | Zeitgeber, „ist online“ | an (der Spieler wählt das Senden an einen Offline-Partner im Gesprächsfenster selbst) | höchstens 12 Versuche bzw. 24 h, 120 s Abstand |
| ezChat | Flüstern aus dem normalen Chat an Offline-Spieler aufheben und nachsenden (`catchChatWhispers`) | „Spieler nicht gefunden“, danach wie oben | **aus** (Hinweis am Chatfenster; Bestand umgestellt) | wie oben |
| ezChat | Automatische Antwort auf Flüstern | eingehendes Flüstern | aus (Hinweis am Chatfenster) | 30 min je Partner |
| ezChat | „tippt …“ und Ort (Addon-Nachricht an ezChat-Nutzer) | Tippen, Gespräch öffnen | aus (Hinweis an der Freundesliste) | 4 s / 60 s, nie im Kampf |
| ezMail | Einsammeln beim Öffnen | Posteingang | aus (Hinweis am Briefkasten) | nie Nachnahme |
| ezMail | Briefe nach Regel zurückschicken (`ReturnInboxItem`) | Öffnen des Briefkastens, vor dem Einsammeln | nur für Absender, denen der Spieler selbst die Regel „zurückschicken“ gegeben hat (kein Schalter, keine Regel ab Werk) | nie GM-Post, nur zurückschickbare Briefe; ein Brief je Schritt über ezMails Ablauf |
| ezMail | Handel am Briefkasten blockieren (Blizzards CVar `blockTrades`) | `MAIL_SHOW`, zurück bei `MAIL_CLOSED` | aus (Hinweis am Briefkasten; „Einschalten“ am offenen Briefkasten wirkt sofort) | eigener Wert gemerkt und zurückgegeben; im Kampf lehnt das Spiel ab, nach dem Kampf nachgeholt |
| ezMail | Weitere Briefe nachsenden | nach Blizzards Senden (Klick) | an | über ezCores Schlange, Abbruch bei Sperre |
| ezCraft | „Alle verschicken“ | Klick und Rückfrage, dann Zeitgeber | – (Klick) | Abbruch bei Sperre, nur eigene Charaktere |
| ezAuction | Preisregel, Menge, Dauer eintragen | Blizzards Verkaufsbereich | nur mit Tor T1 „geht“, sonst „Vorschlag“ | Sperre gegen Rückkopplung |
| ezAuction | Nach dem Kauf nächste Zeile vorwählen, „Bedarf: n“ | Kauf bzw. Klick | aus | Tor T1 |
| ezAuction | Unterboten prüfen, beim Öffnen erfassen | eigene Auktionen bzw. Öffnen | an bzw. aus | Suchschlange nach Blizzards Drossel, 120 s je Gegenstand bzw. 6 h |
| ezMap | Aufspüren wiederherstellen | Einloggen, Zone | an (ohne Such-Zauber) | 3 s, nie im Kampf oder im Tod |
| ezMap | Such-Zauber selbst einschalten | wie oben | **aus** (Hinweis an der Weltkarte; Bestand umgestellt) | 1,6 s je Zauber; nach einer Sperre dauerhaft nur per Klick |
| ezMap | Zielverfolgung (Pfeil) setzen | Wegpunkt, Route | **aus** (Hinweis; auch nach Klick nur mit Schalter) | nie im Kampf |
| ezMap | Markierung nach Ankunft entfernen | Ankunft | an (5 s) | einmal |
| ezMap | Mit Blizzards „Aufspüren“ gemeinsam schalten | Aufspür-Ereignis | aus (Hinweis an der Weltkarte) | nur außerhalb des Kampfes |
| ezQuest | Verfolgung nach Stufe sortieren, Zielverfolgung zurücksetzen | Quest-Ereignisse | **aus** (Hinweis an der Questverfolgung; Bestand umgestellt) | wartet, solange die Zielverfolgung folgt |
| ezQuest | Funkeln und Symbole in der Welt (Grafik-CVars) | Einloggen | **aus** (Hinweis; Bestand umgestellt) | nie im Kampf, Blizzards Werte kommen zurück |
| ezQuest | Quests annehmen und abgeben | Quest-Fenster | aus (Hinweis am Questfenster, nicht solange andere Addons beides erledigen) | eine Aktion je Ereignis, Shift hält an |
| ezQuest | Angenommene Quest den Mitspielern anbieten (Blizzards Teilen: `QuestLogPushQuest`, laut Forever-Quelle und warcraft.wiki.gg nicht geschützt) | `QUEST_ACCEPTED` in Gruppe oder Schlachtzug | **aus** (`autoShare`, Hinweis an der Questverfolgung beim Annehmen in einer Gruppe) | gebündelt (0,5 s), höchstens eine Quest je 2 s, jede automatisch einmal je Sitzung, nie im Kampf (danach), nicht allein, nicht zurück an den Spieler, der sie geteilt hat, nicht, wenn alle Mitspieler sie lesbar schon haben; Rücksicht, wenn ein anderes Addon Quests teilt; keine Chatzeile je Quest (`ezQuest/Share.lua`) |
| ezQuest | Leveling-Route: nächste Quest in Blizzards Verfolgung | Route rückt weiter | aus | ohne Haken nur die Markierung; den Pfeil beim Weiterrücken und nach einem Klick nur mit ezMaps `wayTrack` (ab Werk aus; den eigenen Haken `routeArrow` gibt es seit der Einstellungs-Prüfung vom 19.11.2026 nicht mehr) |
| ezCombat | Mitzählen gesperrter Werte | eigener Zauber | **aus** (Hinweis am Zauberbuch; Bestand umgestellt) | – |
| ezCombat | Vorschlag „Als Nächstes“ aus offenen Werten | Kampfereignisse, Takt | an (siehe V1, Abschnitt 3) | 0,1 s bzw. 0,25 s |
| ezMacro | Automatisch danken und spucken | Heilung, Tod | aus (Hinweis an der Makroverwaltung; Danken nur bei freier Heilvorhersage) | 60 s gesamt, 10 bzw. 5 min je Spieler, offene Welt |
| ezMacro | Ein-Klick-Makros aktualisieren, „Eine Taste“ belegen | Taschen, Stufe, Zone | an | nie im Kampf, gewirkt nur auf Taste |
| ezMacro | Ränge nachziehen | neue Zauber | aus (Hinweis am Zauberbuch) | nach dem Kampf |
| ezMacro | Makros beim Ausloggen sichern | `PLAYER_LOGOUT` | an | einmal |
| ezHeal | Alte eigene Makros heben (`EditMacro`) | Einloggen + 3 s | ohne Schalter | einmal, nie im Kampf |
| ezGear | Umziehen beim Reiten oder Angeln | Reittier, Angel | an | nie im Kampf (Ausrüstung wechseln ist erlaubt) |
| ezLoot | Schneller plündern | `LOOT_READY` | an, nur mit Blizzards Auto-Plündern | 0,3 s |
| ezSocial | Beschwörung oder Wiederbelebung annehmen, Duell und Einladung von Fremden ablehnen | Anfrage | aus (Hinweis an der Freundesliste, nur ohne ein anderes Addon für dieselbe Funktion) | 10 s bzw. nach dem Kampf |
| ezTalent | Talentfenster rücken | Öffnen | an | nie im Kampf, Blizzards Lage als Ausgang (Risiko 24) |
| ezTalent | Vormerkung ausführen (`PurchaseRank`) | nach Klick „Vormerken“ | – (Klick) | gestaffelt, nie `CommitConfig` |
| ezPanel | Fenster oben unter die Leiste rücken | Einloggen, Bearbeitungsmodus | an | nie im Kampf |
| ezBuff | Knopf, Gruppensymbole, „Durchbuffen“ belegen | Aufgaben, PreClick | an | nie im Kampf (Risiko 25) |
| ezCore | Betrachten-Anfrage (`NotifyInspect`) | Tooltip über Spieler | an | 1,5 s für alle Aufrufer zusammen (`Core.Inspect`), 600 s je Spieler, nie im Kampf, nie bei offenem Betrachten-Fenster (die Pause nach einer fremden Anfrage gilt nur für die Reihe unten) |
| ezGear | Ausrüstungs-Check der Gruppe (`NotifyInspect` je Mitglied) | Klick „Gruppe prüfen“ im Seitenteil am Reiter „Schlachtzug“ | – (Klick) | ein Mitglied je 2 s über `Core.Inspect.NewQueue`, höchstens 40, Ergebnis 5 min frisch; Abbruch beim Kampfbeginn, bei offenem Betrachten-Fenster und beim Schließen; 4 s Pause nach einer fremden Anfrage (Statuszeile sagt es, Abbruch nach 30 s ohne Pause); ferne Mitglieder (`CanInspect`) stehen als „nicht in Reichweite“ in der Liste; keine Addon-Nachrichten |
| ezCore | Kamera weiter herauszoomen (`cameraZoom`, Kamera-CVar) | `PLAYER_LOGIN`, Schalter | aus (kein Hinweis: die Umstellung ist die Folge des eigenen Klicks, Abschnitt 1) | im Kampf vorgemerkt und danach gesetzt; ruht, solange ein anderes Addon den Kamera-Abstand schon erweitert (`Bausteine/Comfort.lua`) |
| ezCore | Hinweis „Mithelfen“, Hinweise auf Abläufe ohne Klick, Angebot der Einführung | Einloggen, Fenster öffnen, Flüstern an andere, „Spieler nicht gefunden“ nach einer nicht wartenden Flüsterzeile | an (ein gemeinsamer Schalter „Hinweise und Angebote zeigen“, `optIn.optInHints`; dazu „Nicht mehr zeigen“ bzw. „Nicht mehr anbieten“ in der Blase) | einmal je Account und Funktion, nie im Kampf |

## 6. Chat- und Emote-Ausgaben

| Ort | Art | Auslöser | Drossel, Schalter |
|---|---|---|---|
| `ezCore/Kern/Channels.lua` (`Core.SendChat`, `Core.PerformEmote`) | zentrale Helfer | nur Aufrufer | verweigern bei Chat-Sperre und geheimem Text |
| `ezMacro/AutoEmote.lua` | Emote Danken/Spucken | **ohne Klick** (Heilung, Tod) | ab Werk aus, Hinweis an der Makroverwaltung; 60 s gesamt, 10 bzw. 5 min je Spieler, offene Welt |
| `ezMacro/Emote.lua`, `ezMacro/EmoteBar.lua`, `ezMacro/Announce.lua` | Emote, Gruppe, Raid, Raidwarnung | Klick bzw. Befehl | Chat-Sperre |
| `ezCombat/Meter.lua` | Bericht in Gruppe oder Gilde | Klick im Zahnrad-Menü bzw. `/ezk bericht` | höchstens 3 bis 10 Zeilen, nie im Kampf |
| `ezPanel/Blocks/Loot.lua` | Würfelsieger in die Gruppe | Menüklick | eine Zeile je Klick |
| `ezMap/Battleground.lua` (über ezMacro) | „Punkt in 0:45“ | Klick auf eine Timer-Zeile | eine je Klick |
| `ezBuff/Rebuff.lua` | Emote Danken an den Spender | Klick auf den Knopf bzw. die Taste „ezBuff: fehlenden Buff wirken“ | höchstens einmal je erhaltenem Buff, auch bei Doppelklick und mehreren Drücken im Kampf (`Rebuff.Done`) |
| `ezChat/Core.lua` | Flüstern, Battle.net | Senden im Gesprächsfenster | Chat-Sperre |
| `ezChat/Community.lua` (`C_Club.SendMessage`) | Nachricht in eine Zweier-Community | Senden im Gesprächsfenster (nur aus einer Eingabe des Spielers) | Schalter `community`, per `pcall` |
| `ezChat/Delivery.lua` | Flüstern (Nachsenden) | **ohne Klick** | 12 Versuche bzw. 24 h, 120 s Abstand; Zeilen aus dem normalen Chat nur mit `catchChatWhispers` (ab Werk aus, Hinweis am Chatfenster) |
| `ezChat/Situation.lua` | Flüstern (automatische Antwort) | **ohne Klick** | ab Werk aus, Hinweis am Chatfenster, 30 min je Partner |
| `ezChat/Typing.lua` (`C_ChatInfo.SendAddonMessage`) | Addon-Nachricht (nicht sichtbar) | Tippen, Gespräch öffnen | ab Werk aus, Hinweis an der Freundesliste; nie im Kampf |
| `ezQuest/Share.lua` | Quest-Angebot an die Gruppe (Blizzards Teilen, kein Chat) | **ohne Klick** (`QUEST_ACCEPTED`) bzw. Klick „Jetzt teilen“ | ab Werk aus; eine Quest je 2 s, nie im Kampf, jede automatisch einmal je Sitzung |
| übrige Module | keine Sendung, nur Zeilen im eigenen Chatfenster | – | – |

Kein Aufrufer verwendet SAY, YELL oder CHANNEL.

## 7. Geschützte Aufrufe und ihre Absicherung

| Aufruf | Wo | Absicherung |
|---|---|---|
| Zauber wirken, Gegenstand benutzen, Ziel wählen | nur ezCores sichere Knöpfe (`ezCore/Bausteine/SecureButton.lua`) | Attribute, Lage, Tasten nur außerhalb des Kampfes; ausgelöst nur per Klick oder Taste |
| `CreateMacro`, `EditMacro`, `DeleteMacro` | `ezCore/Bausteine/Macros.lua`, `ezMacro/Macros.lua` | im Kampf verweigert; Löschen nur nach Rückfrage |
| Aktionsplätze und Tasten (`PlaceAction`, `SetBinding`, `SaveBindings`, `SetOverrideBindingClick`) | `ezMacro/Profiles.lua`, `ezMacro/Import.lua`, `ezCore/Bausteine/Keys.lua`, `ezMacro/Fishing.lua` | außerhalb des Kampfes, nach Klick und Rückfrage bzw. bei Kampfbeginn gelöst |
| Klick-Zauber (`C_ClickBindings`) | `ezCore/Bausteine/ClickBindings.lua` | außerhalb des Kampfes, Wunsch wird nachgeholt |
| Blizzard-Rahmen verschieben, skalieren, Kinder anhängen | `ezCore/Bausteine/MoveFrames.lua`, `ezCore/Bausteine/GroupFrames.lua`, `ezPanel/TopSpace.lua`, `ezTalent/UI.lua`, `ezBag/Layout.lua` | nie im Kampf, sonst Aufschub bis `PLAYER_REGEN_ENABLED` |
| Auktionshaus: `CancelAuction` | `ezAuction/AuctionsTab.lua` | eine Auktion je Klick oder Tastendruck |
| Auktionshaus: Einstellen, Bieten, Kaufen | – | nie aufgerufen, nur mit `hooksecurefunc` mitgehört |
| `SendMail`, `SetSendMailMoney` | `ezCore/Charakter/MailQueue.lua` | Gold nur nach Rückfrage (`ezMail/Wire.lua`); Abbruch bei Sperre für alle Briefarten |
| `DeleteCursorItem` (Zerstören) | `ezBag/Space.lua` („Platz schaffen“) | nur nach Klick und Rückfrage, die das Zerstören nennt; nie im Kampf; vorher geprüft, dass genau der gewählte Gegenstand am Mauszeiger hängt; am Händler wird stattdessen verkauft |
| `UseContainerItem` (Verkauf) | `ezCore/Charakter/Junk.lua`, `ezBag/Select.lua`, `ezBag/Space.lua` | nur bei offenem Händler, nie im Kampf |
| `BuyMerchantItem`, `BuyTrainerService`, `RepairAllItems` | `ezMerchant/Merchant.lua`, `ezMerchant/Trainer.lua`, `ezMerchant/Restock.lua`, `ezMerchant/Repair.lua`, `ezPanel/Blocks/Repair.lua`, `ezCore/Charakter/Durability.lua` | per Klick oder als Automatik, die ab Werk aus ist; die Automatik nie im Kampf (wartet bis danach und prüft dann Händler, Schalter und andere Addons erneut) |
| Post: `TakeInboxMoney`, `TakeInboxItem`, `AutoLootMailItem`, `ReturnInboxItem`, `DeleteInboxItem` | `ezMail/Runner.lua`, `ezMail/OpenMail.lua`, `ezMail/Inbox.lua` | Klick („Alle öffnen“, Zeile, „Zurück“), Löschen nur nach Rückfrage; ohne Klick nur „Beim Öffnen einsammeln“ (ab Werk aus, Hinweis) und „zurückschicken“ für Absender mit eigener Regel (Tabelle 5); nie Nachnahme oder GM-Post; ein Brief je Schritt |
| Ausrüsten: `EquipItemByName`, `C_EquipmentSet.UseEquipmentSet` | `ezGear/Swap.lua`, `ezGear/Sets.lua` | Klick bzw. Umziehen beim Reiten und Angeln (Tabelle 5); nie im Kampf (`ns.AfterCombat`) |
| `LootSlot` | `ezLoot/FastLoot.lua` | nur bei `LOOT_READY` mit Blizzards Auto-Plündern, 0,3 s Abstand; ruht, wenn ein anderes Addon schneller plündert |
| Quests: `AcceptQuest`, `CompleteQuest`, `GetQuestReward` | `ezQuest/Auto.lua` | nur mit Schalter (ab Werk aus), eine Aktion je Ereignis, Shift hält an; nie Quests mit Goldkosten, geteilte oder wiederholbare automatisch |
| Anfragen beantworten: `C_SummonInfo.ConfirmSummon`, `AcceptResurrect`, `CancelDuel`, `DeclineGroup` | `ezSocial/Auto.lua` | nur mit Schalter (ab Werk aus, Hinweis an der Freundesliste); Beschwörung nach 10 s und nach dem Kampf; ablehnen nur bei Fremden |
| Gilde: `C_GuildInfo.Invite` | `ezSocial/GuildInvite.lua` | nur per Klick im Rechtsklick-Menü, nur mit Recht zum Einladen |
| Gruppe: `C_PartyInfo.SetLootMethod`, `ResetInstances` | `ezPanel/Blocks/Loot.lua` | per Menüklick; Instanzen zurücksetzen nur nach Rückfrage und nur allein oder als Gruppenleiter |
| Menüs: `FriendsFrame_ShowDropdown`, `UnitPopup_OpenMenu` | `ezChat/Window.lua` (`Window.PlayerMenu`) | per Klick; nur Blizzards Menüs ohne geschützten Eintrag („FRIEND“, „FRIEND_OFFLINE“, Battle.net), nie das Menü einer Einheit (Risiko 26) |
| `C_Traits` (`PurchaseRank`, `SetSelection`, `ResetTreeByCurrency`/`ResetTree`) | `ezTalent/Traits.lua` | per Klick, gestaffelt, nie im Kampf, nie während Blizzards Bestätigung läuft (`IsCommitInProgress` des Talentfensters, `Traits.Committing`), nie bei gesperrtem Baum, Zurücksetzen nur, wo Blizzards Knopf es erlaubt (`cannotRefund`); nie `CommitConfig` (das bestätigt Blizzards Knopf) |
| `C_Minimap.SetTracking` | `ezMap/TrackingMemory.lua`, `ezMap/TrackingCouple.lua` | nicht im Kampf und nicht im Tod; Such-Zauber nur mit Schalter, nach einer Sperre nur per Klick |
| `C_SuperTrack` | `ezMap/Way.lua`, `ezQuest/Tracker.lua` | nur mit `wayTrack` bzw. `sortSuperTrack`, nie im Kampf |
| `SetCVar` | `ezCore/Kern/Util.lua`: `Core.SetCVar` (über `pcall`, prüft den Kampf nicht selbst; lehnt das Spiel ab, liefert es false und der Aufrufer meldet es), `Core.SwitchCVar` (Schalter auf Klick) | Schalter auf Klick – ezCombat `ns.ToggleCVar` und Schlagtimer (`Swing.SetGameTimer`, Hinweis mit eigenem Text `L.SWING_COMBAT`), ezPanel-Baustein „Kampf“, ezLoot „Automatisch plündern“: im Kampf kein Umschalten, sondern ein Hinweis (`Core.SwitchCVar`). Kästchen der Einstellungen (`Core.CVarSetting`), ezCore-Komfort „Kamera-Abstand“ (`Bausteine/Comfort.lua`), ezQuest `World.lua`: im Kampf vorgemerkt und nach dem Kampf gesetzt. ezMail `TradeBlock.lua`: lehnt das Spiel im Kampf ab, nach dem Kampf nachgeholt. ezPanel-Baustein „Lautstärke“ (`Blocks/Volume.lua`): auch im Kampf, nur Ton-CVars (`Sound_*`) |
| Kampflog | – | keine Anmeldung |
| Blizzard-Funktionen erweitern | überall | nur `hooksecurefunc`, `HookScript`, `Menu.ModifyMenu`; keine Blizzard-Funktion wird ersetzt; eigene Einträge in `UISpecialFrames` und `StaticPopupDialogs`, Blizzards eigene Einträge dort nie geändert |

## 8. Im Spiel zu prüfen (Taint-Protokoll)

Was sich nur im Spiel klären lässt, prüft man mit Blizzards Taint-Protokoll: vorher `/console taintLog 1` und `/reload`, danach `/console taintLog 0`; das Protokoll liegt in `Logs\taint.log` im Forever-Ordner. Erwartet ist je Punkt: keine Zeile mit dem Modulnamen und keine Meldung „Aktion durch AddOn blockiert“. Funde bitte als Issue melden.

## 9. Grenzen

- Es gibt keine lokale Blizzard-Doku zu Forever. Ob `SendMail`, `C_Minimap.SetTracking` für Such-Zauber oder `C_SuperTrack` auf Forever einen Hardware-Klick verlangen oder Taint auslösen, ist nicht aus Blizzards eigenen Dateien belegt; deshalb sind diese Abläufe ab Werk aus bzw. brechen bei einer Sperre ab.
- Nicht jede Zeile ist von Hand nachgelesen; die Stellen sind mit Prüfungen in den Tests der Module belegt.
