# Changelog / Änderungsprotokoll

Written by hand before every release; it describes what each module can do, not every commit. English first, German below each entry.
Von Hand vor jeder Veröffentlichung gepflegt; beschreibt, was jedes Modul kann, nicht jeden Commit. Englisch zuerst, Deutsch darunter.

## v1.0.0-beta6

Sixth beta for WoW Forever: ezCraft shows the chance of a skill point as a percentage in the recipe rows by default, and after an update ezCollection offers switches whose default changed to “on”. It also contains the fix from the updated beta5 package: abilities on the action bars work again. Coming from beta5, a /reload is enough; coming from beta4 or older, restart the game completely. Many features are still untested in the game; please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced).
Sechste Beta für WoW Forever: ezCraft zeigt die Chance auf einen Fertigkeitspunkt ab Werk als Prozentzahl in den Rezeptzeilen, und nach einem Update bietet ezCollection Schalter an, deren Standard auf „an“ wechselte. Dazu enthält sie den Fix aus dem neuen Paket von beta5: Fähigkeiten auf den Aktionsleisten gehen wieder. Von beta5 aus genügt `/reload`; von beta4 oder älter das Spiel bitte ganz neu starten. Vieles ist im Spiel noch ungetestet; Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert).

### ezCore

- After an update, the bubble “New since the update” also offers switches whose default changed from off to on – once and unticked, if you have them off: “Accept all” turns them on, “Done” leaves them off. “Agree to everything” and “Accept all” for later news leave them as they are; the button “New since the update” offers them again.
- Nach einem Update bietet die Blase „Neu seit dem Update“ auch Schalter an, deren Standard von aus auf an wechselte – einmal und ohne Häkchen, wenn du sie aus hast: „Alle annehmen“ schaltet sie ein, „Fertig“ lässt sie aus. „Allem zustimmen“ und „Alle annehmen“ bei späteren Neuerungen lassen sie, wie sie sind; der Knopf „Neu seit dem Update“ bietet sie wieder an.

### ezCraft

- The chance of a skill point as a small percentage on the right of each recipe row where it is known (“Chance as a number next to the name”) is on by default, in the color of the recipe. If you have it off, the bubble “New since the update” offers it once.
- Die Chance auf einen Fertigkeitspunkt als kleine Prozentzahl rechts in jeder Rezeptzeile, wo sie bekannt ist („Chance als Zahl neben dem Namen“), ist ab Werk an, in der Farbe des Rezepts. Hast du sie aus, bietet die Blase „Neu seit dem Update“ sie einmal an.

## v1.0.0-beta5

**Updated package (27 Nov 2026, ezCore 1.19.1):** abilities on the action bars work again. The first package of this version blocked every click on an action button with the message “AddOn 'ezCore' tried to call the protected function 'UNKNOWN()'”. If you downloaded it before, replace it with this one and restart the game completely.
**Neues Paket (27.11.2026, ezCore 1.19.1):** Fähigkeiten auf den Aktionsleisten gehen wieder. Das erste Paket dieser Fassung blockierte jeden Klick auf einen Aktionsknopf mit der Meldung „AddOn 'ezCore' hat versucht die geschützte Funktion 'UNKNOWN()' aufzurufen“. Wer es schon geladen hat, ersetzt es durch dieses und startet das Spiel ganz neu.

Fifth beta for WoW Forever: ezBuff picks a paladin's blessing by class and group role, ezGear rates gear for your level and armor type and tells what an item does for you, ezCollection's settings pages no longer cause an error in Blizzard's settings, the plain right click on party frames stays “Menu”, and right-click menus of units with a hidden name no longer break. Please restart the game completely after updating – this version brings new files, a /reload is not enough. Many features are still untested in the game; please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced).
Fünfte Beta für WoW Forever: ezBuff wählt den Segen des Paladins nach Klasse und Gruppenrolle, ezGear bewertet Ausrüstung für deine Stufe und Rüstungsart und sagt, was ein Teil für dich bewirkt, die Einstellungsseiten der ezCollection lösen in Blizzards Einstellungen keinen Fehler mehr aus, der einfache Rechtsklick auf Gruppenrahmen bleibt „Menü“, und Rechtsklick-Menüs von Einheiten mit verborgenem Namen gehen nicht mehr kaputt. Nach dem Update das Spiel bitte ganz neu starten – diese Fassung bringt neue Dateien, `/reload` genügt nicht. Vieles ist im Spiel noch ungetestet; Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert).

### ezCore

- Using an ability from the action bars works again: the settings search marks for ezCollection's buttons no longer leave Blizzard's settings tainted, so a click on an action button is no longer blocked (“AddOn 'ezCore' tried to call the protected function 'UNKNOWN()'”).
- Fähigkeiten von den Aktionsleisten gehen wieder: Die Suchmarken für die Knöpfe der ezCollection hinterlassen Blizzards Einstellungen nicht mehr verunreinigt, ein Klick auf einen Aktionsknopf wird nicht mehr blockiert („AddOn 'ezCore' hat versucht die geschützte Funktion 'UNKNOWN()' aufzurufen“).
- ezCollection's settings pages leave Blizzard's settings list alone: no more message about the protected function IsUserOAuthed() when scrolling or searching Blizzard's settings. The settings search still finds ezCollection's buttons; a row that depends on another switch turns grey at once and is gone the next time you open the page. A found sub-option is shown without its parent row.
- Die Einstellungsseiten der ezCollection lassen Blizzards Einstellungsliste in Ruhe: keine Meldung mehr über die geschützte Funktion IsUserOAuthed() beim Rollen oder Suchen in Blizzards Einstellungen. Die Suche findet die Knöpfe der ezCollection weiter; eine Zeile, die von einem anderen Schalter abhängt, wird sofort grau und ist beim nächsten Öffnen der Seite weg. Ein gefundener Unterschalter erscheint ohne seine Oberzeile.
- Right-click menus of a unit whose name the game keeps hidden are left as they are; this removes an error in the menu of the target frame, for example after marking enemies.
- Rechtsklick-Menüs einer Einheit, deren Namen das Spiel verbirgt, bleiben, wie sie sind; das behebt einen Fehler im Menü des Zielfensters, etwa nach dem Markieren von Gegnern.

### ezAuction

- “Upgrades only” follows ezGear's new rating: for tanks and melee, an item of a lighter armor type than yours shows the grey “=” and does not count as an upgrade. The slider “Percent below lowest” stands indented below the price rule.
- „Nur Verbesserungen“ folgt ezGears neuer Bewertung: Bei Tanks und Nahkämpfern zeigt ein Teil einer leichteren Rüstungsart als deiner das graue „=“ und zählt nicht als Verbesserung. Der Regler „Prozent unter Tiefstpreis“ steht eingerückt unter der Preisregel.

### ezBag

- “Agree to everything” and “Accept all” also switch on “Combine identical items” and “Reagent bag inside the bag” – the reagent bag even if you had switched it off (only with “Group the bag automatically” on).
- „Allem zustimmen“ und „Alle annehmen“ schalten auch „Gleiche Gegenstände zusammenfassen“ und „Reagenzientasche in der Tasche“ ein – die Reagenzientasche auch dann, wenn du sie ausgeschaltet hattest (nur mit „Tasche automatisch gruppieren“).

### ezBuff

- Paladins: without your own choice ezBuff picks the blessing by class and group role – Might for warriors, rogues, tanks and paladins in the damage role, Wisdom for mages, warlocks, priests, healers and hunters (Blessing of Might only raises melee attack power). A druid in bear or cat form gets Might; otherwise your own blessing. Then only that blessing counts, even if another one is up. Your choice per class or player comes first. Switch “Blessings by class and role”, on by default; in the menu “Same as for you” is now “Automatic (ezBuff picks)”.
- Paladine: Ohne deine Wahl wählt ezBuff den Segen nach Klasse und Gruppenrolle – Macht für Krieger, Schurken, Tanks und Paladine mit Rolle Schaden, Weisheit für Magier, Hexenmeister, Priester, Heiler und Jäger (Segen der Macht erhöht nur die Nahkampf-Angriffskraft). Ein Druide in Bär- oder Katzengestalt bekommt Macht, sonst dein eigener Segen. Dann zählt nur dieser Segen, auch wenn schon ein anderer liegt. Deine Wahl je Klasse oder Spieler geht vor. Schalter „Segen nach Klasse und Rolle“, ab Werk an; im Menü heißt „Wie für dich“ jetzt „Automatisch (ezBuff wählt)“.
- The tooltip on the party frame names the reason; “Who gets which blessing?” » “Show in chat” writes one line per member into the chat. Its entries in right-click menus are left out for a unit with a hidden name.
- Der Tooltip am Gruppenrahmen nennt den Grund; „Wer bekommt welchen Segen?“ » „Im Chat zeigen“ schreibt je Mitglied eine Zeile in den Chat. Seine Einträge in Rechtsklick-Menüs fehlen bei einer Einheit mit verborgenem Namen.

### ezChat

- Its entries in right-click menus are left out for a unit with a hidden name.
- Seine Einträge in Rechtsklick-Menüs fehlen bei einer Einheit mit verborgenem Namen.

### ezGear

- Gear is rated for your level instead of level 60, armor by the game's own formula. For tanks and melee, an item of a lighter armor type than yours gets no green arrow, one of your own type no red arrow against lighter gear; the tooltip says why. The percentage counts on everything you wear (Shift: this item alone).
- Ausrüstung wird für deine Stufe bewertet statt für Stufe 60, Rüstung nach der Formel des Spiels. Für Tanks und Nahkämpfer bekommt ein Teil einer leichteren Rüstungsart als deiner keinen grünen Pfeil, eines deiner eigenen Art keinen roten gegen leichtere Ausrüstung; der Tooltip sagt, warum. Der Prozentwert rechnet auf alles, was du trägst (Umschalt: nur dieses Teil).
- New line “For you” in the tooltip: what the swap does to your health and the melee damage you take (or deal), also in bear form. Switch “Effect on you”, on by default.
- Neue Zeile „Für dich“ im Tooltip: was der Tausch bei deiner Gesundheit und dem erlittenen (oder eigenen) Nahkampfschaden ausmacht, auch in Bärengestalt. Schalter „Wirkung auf dich“, ab Werk an.

### ezHeal

- The plain right click on player, party and raid frames stays “Menu”: if Blizzard's click casting puts something else there, ezHeal puts “Menu” back, removes what was there and names it in the chat. Right click with Shift, Ctrl or Alt stays yours. Switch “Right click stays “Menu””, on by default.
- Der einfache Rechtsklick auf Spieler-, Gruppen- und Raidrahmen bleibt „Menü“: Legt Blizzards Klick-Zaubern etwas anderes darauf, legt ezHeal „Menü“ zurück, entfernt, was dort lag, und nennt es im Chat. Rechtsklick mit Umschalt, Strg oder Alt bleibt deiner. Schalter „Rechtsklick bleibt „Menü““, ab Werk an.

### ezMacro

- “Announce” is left out of the menu of a unit with a hidden name; the button “For target …” still works. After the button “Click cast”, the chat hint adds: not on the plain left or right click.
- „Ansage“ fehlt im Menü einer Einheit mit verborgenem Namen; der Knopf „Zum Ziel …“ geht weiter. Nach dem Knopf „Klick-Zauber“ sagt der Hinweis im Chat dazu: nicht mit dem einfachen Links- oder Rechtsklick.

### ezMap

- Sub-options in its settings stay indented below their switch, now without touching Blizzard's settings list.
- Unterschalter in seinen Einstellungen stehen weiter eingerückt unter ihrem Schalter, jetzt ohne Blizzards Einstellungsliste anzufassen.

### ezPanel

- Rows for alerts in its settings show only for a known source, now without touching Blizzard's settings list.
- Zeilen für Warnungen in seinen Einstellungen erscheinen nur bei bekannter Quelle, jetzt ohne Blizzards Einstellungsliste anzufassen.

### ezSocial

- Its entries in right-click menus are left out for a unit with a hidden name.
- Seine Einträge in Rechtsklick-Menüs fehlen bei einer Einheit mit verborgenem Namen.

### ezTalent

- Its gear weights leave armor to ezGear, which weighs it for your level by the game's formula, and count stamina by the health it gives; ezGear also gets the role and range of your template.
- Seine Gewichtung überlässt die Rüstung ezGear, das sie für deine Stufe nach der Formel des Spiels wiegt, und zählt Ausdauer nach der Gesundheit, die sie bringt; ezGear bekommt dazu Rolle und Reichweite deiner Vorlage.

## v1.0.0-beta4

Fourth beta for WoW Forever: a second spellbook page that tells where you learn what, rotations that go onto your action bars, rescue and dispel hints, an auction house that shows upgrades at a glance, a wider recipe list, a suggestion for full bags, talent templates linked to rotations, an anonymous contribution text made in the game, and all shipped data brought up to client build 1.60.1. Many features are still untested in the game; please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced).
Vierte Beta für WoW Forever: eine zweite Zauberbuch-Seite, die sagt, wo du was lernst, Rotationen, die sich auf deine Aktionsleisten legen, Rettungs- und Bann-Hinweise, ein Auktionshaus, das Verbesserungen auf einen Blick zeigt, eine breitere Rezeptliste, ein Vorschlag bei voller Tasche, Talentvorlagen mit passenden Rotationen, ein anonymer Beitragstext direkt aus dem Spiel und alle mitgelieferten Daten auf dem Stand des Client-Builds 1.60.1. Vieles ist im Spiel noch ungetestet; Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert).

### ezCore

- After an update a bubble at the minimap asks about what is new, with a checkbox per point; the introduction is up to date. “Agree to all” also switches on every kind of tracking, but leaves the fight summary off.
- Nach einem Update fragt eine Blase an der Minikarte nach dem, was neu ist, mit einem Haken je Punkt; die Einführung ist auf dem heutigen Stand. „Allem zustimmen“ schaltet auch alle Arten des Aufspürens ein, lässt die Zusammenfassung nach dem Kampf aber aus.
- “Help out” makes an anonymous text in the game (numbers, places, build and day only) that you copy and send; the copyable error list leaves out your own names. Contributions of other players come with the folder ezData and are shown as “from contributions” – loot, vendors, trainers, flight times, zone levels, disenchanting.
- „Mithelfen“ macht im Spiel einen anonymen Text (nur Nummern, Orte, Build und Tag), den du kopierst und schickst; die Fehlerliste zum Kopieren lässt deine eigenen Namen weg. Beiträge anderer Spieler kommen mit dem Ordner ezData und stehen als „aus Beiträgen“ da – Beute, Händler, Lehrer, Flugzeiten, Gebietsstufen, Entzaubern.
- Recipes, zone levels, dungeon entrances, flight routes, ranks and talents come from the tables of client build 1.60.1. Without a group role your role follows your talents, and your own talent tree is in the player tooltip. Action bar profiles work without ezMacro.
- Rezepte, Zonenstufen, Dungeoneingänge, Flugstrecken, Ränge und Talente stammen aus den Tabellen des Client-Builds 1.60.1. Ohne Gruppenrolle folgt deine Rolle den Talenten, und dein Talentbaum steht im Spieler-Tooltip. Leisten-Profile gehen auch ohne ezMacro.
- “Zoom the camera out further” is set again after login and says what the game accepted. “Deselect all” sits below “Select all”. Paragraphs on the spellbook pages are no longer cut off when they fit.
- „Kamera weiter herauszoomen“ wird nach dem Anmelden noch einmal gesetzt und sagt, was das Spiel angenommen hat. „Alle abwählen“ steht unter „Alle auswählen“. Absätze auf den Zauberbuch-Seiten werden nicht mehr gekürzt, wenn sie hineinpassen.

### ezAuction

- ezGear's arrow stands in a fixed column between price and name. “Upgrades only” hides equipment that is worse for you; what is not known yet stays.
- ezGears Pfeil steht in einer festen Spalte zwischen Preis und Name. „Nur Verbesserungen“ blendet Ausrüstung aus, die schlechter für dich ist; was noch nicht feststeht, bleibt stehen.
- The auction house fee only counts once ezCore has measured it; until then profits are shown as gross.
- Die Gebühr des Auktionshauses zählt erst, wenn ezCore sie gemessen hat; bis dahin sind Gewinne brutto.

### ezBag

- The reagent bag is a section of its own at the bottom of the bag; reagents, arrows, bullets and goods of profession bags move into their bags by themselves.
- Die Reagenzientasche ist ein eigener Abschnitt unten in der Tasche; Reagenzien, Pfeile, Kugeln und Waren der Berufstaschen rücken von selbst in ihre Taschen nach.
- With full bags a button at the loot window suggests which cheap item to destroy for more valuable loot, with both prices and a question first.
- Bei voller Tasche schlägt ein Knopf am Plündernfenster vor, welches billige Teil für wertvollere Beute zerstört wird – mit beiden Preisen und einer Rückfrage.
- ezBag's amount box uses the game's own split key, left and right, and passes the amount to the open window. Junk spares what is better than what you wear.
- ezBags Anzahl-Feld nutzt die Teilen-Taste des Spiels, links wie rechts, und gibt die Anzahl an das offene Fenster weiter. Plunder verschont, was besser ist als das Angelegte.

### ezBars

- Bar 1 is off by default. Bar profiles also work without ezMacro.
- Leiste 1 ist ab Werk aus. Leisten-Profile gehen auch ohne ezMacro.

### ezBuff

- Buff food is reminded for every class, checked at all times by default. The symbol on a party frame casts nothing on someone out of range.
- An Buff-Essen wird bei jeder Klasse erinnert, geprüft wird ab Werk immer. Das Symbol am Gruppenrahmen wirkt auf niemanden außer Reichweite.

### ezChat

- The number of chat windows comes from the game; less work in the background.
- Die Zahl der Chatfenster kommt vom Spiel; weniger Arbeit im Hintergrund.

### ezCombat

- The rotation goes onto action bars 1 and 2 at the push of a button, with a preview, a question and “Back”; all buttons are on the first page. It suggests only one of what excludes each other (curses, stings, seals, aspects, armors) and weighs the filler spell against your wand by your values.
- Die Rotation legt sich auf Knopfdruck auf die Aktionsleisten 1 und 2, mit Vorschau, Rückfrage und „Zurück“; alle Knöpfe stehen auf der ersten Seite. Was sich ausschließt (Flüche, Stiche, Siegel, Aspekte, Rüstungen), schlägt sie nur einmal vor, und sie wägt den Füllzauber nach deinen Werten gegen den Zauberstab ab.
- Near death: the rescue ability in the middle symbol, a potion as a small mark, and your own frame glows; a dispel hint on the portrait when you or a party member can be cleansed by you. One slider for the limit (15 % by default).
- Fast tot: die Rettungsfähigkeit im mittigen Symbol, ein Trank als kleine Marke, dazu leuchtet dein Rahmen; ein Bann-Hinweis auf dem Porträt, wenn du dich oder einen Mitspieler bannen kannst. Ein Regler für die Grenze (ab Werk 15 %).
- Combo points are shown only once, the row of your DoTs, the damage comparison and the fight summary are off by default, expiring DoTs and HoTs are announced earlier. A healer by talents also sees damage on the party frames.
- Combo-Punkte stehen nur noch einmal da, die Reihe deiner DoTs, der Schadensvergleich und die Zusammenfassung nach dem Kampf sind ab Werk aus, auslaufende DoTs und HoTs werden früher angesagt. Wer nur laut Talenten Heiler ist, sieht am Gruppenrahmen auch Schaden.

### ezCraft

- The recipe list shows ezGear's arrow and the required level of what you make, is a little wider, and can be ordered by that level (Filter » Order); a click selects the recipe there too.
- Die Rezeptliste zeigt ezGears Pfeil und die nötige Stufe dessen, was du herstellst, ist etwas breiter und lässt sich nach dieser Stufe ordnen (Filter » Reihenfolge); auch dort wählt ein Klick das Rezept.
- “What comes when” and “What is where” for the open profession, with trainers, vendors and quests. The cost line breaks only between its parts.
- „Was kommt wann“ und „Wo kommt was“ für den offenen Beruf, mit Lehrern, Händlern und Quests. Die Kostenzeile bricht nur zwischen ihren Teilen um.

### ezData

- New folder with contributions of other players, checked by the project. It is still empty and can be switched off in the addon list.
- Neuer Ordner mit Beiträgen anderer Spieler, vom Projekt geprüft. Er ist noch leer und lässt sich in der Addon-Liste ausschalten.

### ezGear

- A yellow arrow for what is better as soon as your level or a weapon or armor skill is enough; two-handers are compared with a pair; weapon damage counts. The arrow also stands in the trade window with another player.
- Gelber Pfeil für alles, was besser ist, sobald Stufe oder Waffen- und Rüstungsfertigkeit reichen; Zweihänder werden mit einem Paar verglichen; Waffenschaden zählt. Der Pfeil steht auch im Handelsfenster mit einem anderen Spieler.
- The tooltip names the alts an item helps. The weighting “Automatic” follows your talent tree.
- Der Tooltip nennt die Twinks, denen ein Gegenstand etwas bringt. Die Gewichtung „Automatisch“ folgt deinem Talentbaum.

### ezHeal

- A heal on a party member out of range no longer hits you: by default ezHeal sets the game's self cast to “key press” (this also applies to your action bars) and checks it after login; its switch brings your old value back.
- Eine Heilung auf einen Mitspieler außer Reichweite trifft nicht mehr dich: ezHeal stellt „Selbstwirken“ des Spiels ab Werk auf „Tastendruck“ (das gilt auch für deine Aktionsleisten) und prüft es nach dem Anmelden; sein Schalter holt deinen alten Wert zurück.
- ezHeal says when “Menu” or “Target” is missing in your click casting and brings it back.
- ezHeal sagt, wenn „Menü“ oder „Ziel“ in deinem Klick-Zauber fehlt, und holt es zurück.

### ezLoot

- Possible loot of creatures and the contents of containers also come from contributions, always with their source.
- Mögliche Beute von Gegnern und der Inhalt von Behältern kommen auch aus Beiträgen, immer mit Quelle.

### ezMacro

- Click casting uses Blizzard's own window; the key menu of its own is gone. New switches “Mouseover for allies” and “Mouseover for enemies” for the class macros, both on by default.
- Klick-Zauber laufen über Blizzards eigenes Fenster; das eigene Tastenmenü ist weg. Neue Schalter „Maus über Mitspieler“ und „Maus über Gegner“ für die Klassenmakros, beide ab Werk an.

### ezMap

- Flight times are estimated from the length of the route and your measured speed until a flight is learned. The flight bar is hidden by a right-click.
- Flugzeiten werden aus der Länge der Strecke und deiner gemessenen Geschwindigkeit geschätzt, bis ein Flug gelernt ist. Die Flugleiste blendet sich per Rechtsklick aus.
- The arrow on the minimap is bigger, its tip stands on the target when in sight and moves on inside a quest area. Herbs and ores also from Questie, without double points.
- Der Pfeil auf der Minikarte ist größer, seine Spitze steht in Sicht auf dem Ziel und springt im Questgebiet weiter. Kräuter und Erze auch laut Questie, ohne doppelte Punkte.

### ezMarket, ezWorld

- Both folders have a symbol in the addon list.
- Beide Ordner haben ein Symbol in der Addon-Liste.

### ezMerchant

- “What is where” in the spellbook: class and weapon trainers, riding, armor skills, pet trainers, class quests and books, the nearest first, with a map button. “What comes when” also lists the warlock's grimoires, and ranks taught by books no longer count as waiting at the trainer.
- „Wo kommt was“ im Zauberbuch: Klassenlehrer und Waffenmeister, Reiten, Rüstungsfertigkeiten, Ausbilder der Begleiter, Klassenquests und Bücher, der nächste zuerst, mit Kartenknopf. „Was kommt wann“ nennt auch die Grimoires der Hexenmeister, und Ränge aus Büchern zählen nicht mehr als „wartet beim Lehrer“.
- “Keep what is worth more at the auction house” is off by default; the merchant filter shows yellow arrows.
- „Im Auktionshaus Wertvolles behalten“ ist ab Werk aus; der Händlerfilter zeigt gelbe Pfeile.

### ezPanel

- Bags and ammunition show only the free slots; instance limit 5 per hour as in the current build.
- Taschen und Munition zeigen nur den freien Platz; Instanzgrenze 5 je Stunde wie im aktuellen Build.

### ezQuest

- The leveling route plans targets as areas with a round trip and knows how big they are. Sharing offers a new party member the quests they lack with a button (sharing without a click is off by default) and catches up when several are accepted at once.
- Die Leveling-Route plant Ziele als Gebiet mit Rundgang und kennt deren Größe. Teilen bietet einem neuen Mitspieler die fehlenden Quests mit einem Knopf an (Teilen ohne Klick ist ab Werk aus) und reicht nach, wenn mehrere auf einmal angenommen werden.

### ezTalent

- Every template names the matching rotations and the other way round. Notes on changed talents are up to date with the build; “Best with n points” respects locked rows.
- Jede Vorlage nennt die passenden Rotationen und umgekehrt. Hinweise zu geänderten Talenten sind auf dem Stand des Builds; „Bestes mit n Punkten“ beachtet gesperrte Reihen.

## v1.0.0-beta3

Third beta for WoW Forever: a reworked auction house with shopping lists shared with ezCraft, icon tabs on the profession window, whole combined stacks from the bags with one click, contents of boxes and chests in the tooltip, more townsfolk in the minimap's tracking menu and a clearer experience bar. The introduction now tells in a few lines what each module can do. Many features are still untested in the game; please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced).
Dritte Beta für WoW Forever: ein überarbeitetes Auktionshaus mit Einkaufslisten, die es mit ezCraft teilt, Symbol-Reiter am Berufefenster, ganze zusammengefasste Stapel aus der Tasche mit einem Klick, der Inhalt von Kisten und Truhen im Tooltip, mehr Stadtbewohner im Minikarten-Menü „Aufspüren“ und eine klarere Erfahrungsleiste. Die Einführung erzählt jetzt in wenigen Zeilen, was jedes Modul kann. Vieles ist im Spiel noch ungetestet; Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert).

### ezCore

- The introduction tells in a few lines what each module can do, next to the question whether to switch it on; the tours match these overviews. “Agree to all” leaves sending letters at the mailbox off and says what you still switch on yourself. Menus have one “All” checkbox instead of “Select all” and “Deselect all”, and checkboxes in menus update right away. Shopping lists are shared by ezAuction and ezCraft (create, rename, delete, add items with Shift+click). Side panels at Blizzard's windows share one width, frame and header. Zones are matched to their map with Questie or QuestieDB, also for Stormwind. If the full auction house scan can't start, the chat line says why.
- Die Einführung erzählt neben der Frage, ob ein Modul eingeschaltet wird, in wenigen Zeilen, was es kann; die Rundgänge passen zu diesem Überblick. „Allem zustimmen“ lässt das Senden von Briefen am Briefkasten aus und sagt, was du weiter selbst einschaltest. Menüs haben einen Haken „Alle“ statt „Alle auswählen“ und „Alle abwählen“, und Haken in Menüs zeigen ihren Stand sofort. Einkaufslisten teilen sich ezAuction und ezCraft (anlegen, umbenennen, löschen, Gegenstände mit Umschalt+Klick hinzufügen). Seitenteile an Blizzards Fenstern haben eine gemeinsame Breite, einen Rahmen und einen Kopf. Gebiete finden ihre Karte über Questie oder QuestieDB, auch Sturmwind. Startet der Komplett-Scan des Auktionshauses nicht, sagt die Chatzeile warum.

### ezAuction

- New layout: “From your bags” on the left at full height, the market always on the right, “Scan prices” at the bottom next to the gold; all side panels are as wide as ezTalent's and use the same list frame. Shopping lists, “Shopping lists”, “Bargains” and “Watched” sit on the left like Blizzard's categories and are deselected the same way; searches use Blizzard's filters. A “Reset” button (red X next to “Recent searches”) clears search text, selection, categories and filters. Shift+click adds an item to the open shopping list. The market shows a month view, gaps in the price history are joined with a dashed line, and a button enlarges the chart. The full scan works again without realm data. The shopping list from ezCraft no longer subtracts what all your characters own. The revenue and “Next:” lines under “Create auction” are gone; the next item stays gold in the bag list. An error with Blizzard's result list is fixed.
- Neue Anordnung: „Aus der Tasche“ links in voller Höhe, der Markt immer rechts, „Preise erfassen“ unten neben dem Gold; alle Seitenteile sind so breit wie bei ezTalent und haben denselben Listenrahmen. Einkaufslisten, „Einkaufslisten“, „Schnäppchen“ und „Beobachtet“ stehen links wie Blizzards Kategorien und lassen sich genauso abwählen; Suchen nutzen Blizzards Filter. Ein Knopf „Zurücksetzen“ (rotes X neben „Letzte Suchen“) leert Suchtext, Auswahl, Kategorien und Filter. Umschalt+Klick legt einen Gegenstand in die offene Einkaufsliste. Der Markt zeigt eine Monatsansicht, Lücken im Preisverlauf sind gestrichelt verbunden, ein Knopf vergrößert das Diagramm. Der Komplett-Scan geht wieder ohne Realm-Daten. Die Einkaufsliste aus ezCraft zieht nicht mehr ab, was alle deine Charaktere besitzen. Erlös- und „Nächster:“-Zeile unter „Auktion erstellen“ entfallen; der nächste Gegenstand bleibt golden in der Taschenliste. Ein Fehler mit Blizzards Ergebnisliste ist behoben.

### ezBag

- A right-click on a combined slot passes on all its stacks at the mailbox, in a trade and at the bank, and sells all of them at a merchant; the slot shows its largest stack first. Shift+right-click opens ezBag's own amount box, as big as Blizzard's split window and at the clicked slot, at a merchant, mailbox, trade or bank up to the total of all stacks; the amount is put into as few stacks as possible. Without a window open the split amount (up to one stack) stays in your hand like with Blizzard; at the guild bank and the auction house Blizzard's window stays. Items dropped on the combined “Free” tile are sorted in right away.
- Ein Rechtsklick auf einen zusammengefassten Platz gibt an der Post, im Handel und an der Bank alle seine Stapel weiter und verkauft beim Händler alle; der Platz zeigt zuerst seinen größten Stapel. Umschalt+Rechtsklick öffnet ezBags eigenes Anzahl-Feld, so groß wie Blizzards Teil-Fenster und am angeklickten Platz, bei Händler, Post, Handel oder Bank bis zur Gesamtzahl aller Stapel; die Anzahl wird zu möglichst wenigen Stapeln zusammengelegt. Ohne offenes Fenster bleibt die geteilte Anzahl (bis zu einem Stapel) in der Hand wie bei Blizzard; an der Gildenbank und im Auktionshaus bleibt Blizzards Fenster. Was auf der zusammengefassten Kachel „Frei“ abgelegt wird, ordnet ezBag gleich ein.

### ezBars

- The introduction says in a few lines what ezBars can do.
- Die Einführung sagt in wenigen Zeilen, was ezBars kann.

### ezBuff

- The introduction says in a few lines what ezBuff can do.
- Die Einführung sagt in wenigen Zeilen, was ezBuff kann.

### ezChat

- In the conversation view the input line whispers the person of the open conversation, and switching back to “General” and the other tabs restores the channel. The whisper sound only plays while you are away. “Show history at login”, which put old whisper, say and yell lines into the general chat, is switched off once for everyone (your own choice counts after that), and neither “Agree to all” nor an import turns it on.
- In der Gesprächsansicht flüstert die Eingabezeile die Person des offenen Gesprächs an, beim Wechsel zurück zu „Allgemein“ und den anderen Reitern kehrt der Kanal zurück. Der Ton bei Flüstern kommt nur noch, wenn du abwesend bist. „Verlauf beim Einloggen zeigen“, das alte Flüster-, Sagen- und Schreien-Zeilen in den allgemeinen Chat stellte, wird einmal für alle ausgeschaltet (danach gilt deine Wahl); „Allem zustimmen“ und ein Import schalten ihn nicht mehr ein.

### ezCombat

- The rotation pages in the spellbook start a section such as “In combat” on a new page and keep even spacing. The cheat sheet shows the full rotation name and folds the calculation details away.
- Die Rotations-Seiten im Zauberbuch beginnen einen Abschnitt wie „Im Kampf“ auf einer neuen Seite und halten gleiche Abstände. Der Spickzettel zeigt den Namen der Rotation ganz und klappt die Berechnungs-Angaben ein.

### ezCraft

- Icon tabs on the profession window like ezAuction and ezTalent; the side panel is as wide as ezTalent's. The “Recipe” view is gone; shopping lists are the default view and can be created, renamed and deleted; Shift+click adds items or recipes. Buttons and a cost line sit in the recipe area. “Auction house” searches every reagent right away while the auction house is open, otherwise it remembers them for the next visit. New items worth disenchanting bring a question: Disenchant, No or Never.
- Symbol-Reiter am Berufefenster, im Stil von ezAuction und ezTalent; das Seitenteil ist so breit wie bei ezTalent. Die Ansicht „Rezept“ entfällt; Einkaufslisten sind die Grundansicht und lassen sich anlegen, umbenennen und löschen; Umschalt+Klick fügt Gegenstände oder Rezepte hinzu. Knöpfe und eine Kostenzeile stehen im Rezeptbereich. „Auktionshaus“ sucht bei offenem Auktionshaus sofort jede Zutat, sonst merkt es sie für den nächsten Besuch vor. Neue Gegenstände, die sich zum Entzaubern lohnen, lösen eine Frage aus: Entzaubern, Nein oder Niemals.

### ezGear

- The introduction and tour say in a few lines what ezGear can do.
- Einführung und Rundgang sagen in wenigen Zeilen, was ezGear kann.

### ezHeal

- Blizzard's click casting panel docks to the right of the spellbook and moves with it; closing the spellbook closes it too, and closing the panel keeps the spellbook open.
- Blizzards Klick-Belegung dockt rechts am Zauberbuch an und wandert mit; schließt du das Zauberbuch, geht sie mit zu, schließt du sie, bleibt das Zauberbuch offen.

### ezLoot

- The tooltip of opened bags, boxes, lockboxes and chests shows what was inside, from your own openings and, when Questie runs, what they can contain according to Questie.
- Der Tooltip geöffneter Beutel, Kisten, Schließkassetten und Truhen zeigt, was darin war – aus deinen eigenen Öffnungen und, wenn Questie läuft, was sie laut Questie enthalten können.

### ezMacro

- Menus use the one “All” checkbox; the introduction says in a few lines what ezMacro can do.
- Menüs nutzen den einen Haken „Alle“; die Einführung sagt in wenigen Zeilen, was ezMacro kann.

### ezMail

- A right-click on a combined bag slot attaches all its stacks to the letter. Menus use the one “All” checkbox; the tour shows the address book.
- Ein Rechtsklick auf einen zusammengefassten Taschenplatz hängt alle seine Stapel an den Brief. Menüs nutzen den einen Haken „Alle“; der Rundgang zeigt das Adressbuch.

### ezMap

- The minimap menu “Tracking” has one trainer entry, flight masters one by one in a submenu, vendors of your zone at Blizzard's “Repair” and an “All” checkbox in place of “Deselect all”; innkeepers, stable masters, auctioneers, bankers and battlemasters get arrows like the trainers and cover the whole continent. Trainers, weapon masters and vendors come from Questie when it runs. The ezMap button and the menu look alike. A new option puts the mail icon at the top right of the minimap, with or without the compact minimap.
- Das Minikarten-Menü „Aufspüren“ hat einen Lehrer-Eintrag, Flugmeister einzeln in einem Untermenü, Händler deiner Zone an Blizzards „Reparieren“ und einen Haken „Alle“ an der Stelle von „Alle abwählen“; Gastwirte, Stallmeister, Auktionatoren, Bankiers und Kampfmeister bekommen Pfeile wie die Lehrer und reichen über den ganzen Kontinent. Lehrer, Waffenmeister und Händler stammen aus Questie, wenn es läuft. ezMap-Knopf und Menü sehen gleich aus. Ein neuer Schalter setzt das Postsymbol oben rechts an die Minikarte, mit und ohne kompakte Minikarte.

### ezMerchant

- The spellbook page “What comes when” starts each section on a new page, keeps even spacing and shows the spell's description instead of grey details.
- Die Zauberbuch-Seite „Was kommt wann“ beginnt jeden Abschnitt auf einer neuen Seite, hält gleiche Abstände und zeigt die Beschreibung des Zaubers statt grauer Angaben.

### ezPanel

- One switch “Other characters in tooltip” instead of five; menus use the one “All” checkbox.
- Ein Schalter „Andere Charaktere im Tooltip“ statt fünf; Menüs nutzen den einen Haken „Alle“.

### ezQuest

- The experience bar shows rested experience again, right after the gold area of your finished quests; Blizzard's rested mark moves along with it, and the stripe under the blue is gone. The levelling route stays in your zone first, the next zone follows as an arrow at the edge, and no line runs across beside the map.
- Die Erfahrungsleiste zeigt die Erholung wieder, direkt nach der goldenen Fläche der fertigen Quests; Blizzards Erholungs-Marke wandert mit, der Streifen unter dem Blau ist weg. Die Leveling-Route bleibt zuerst in deiner Zone, die nächste Zone folgt als Pfeil am Rand, und keine Linie läuft mehr quer neben der Karte.

### ezSocial

- The introduction says in a few lines what ezSocial can do.
- Die Einführung sagt in wenigen Zeilen, was ezSocial kann.

### ezTalent

- The chosen template is highlighted the same way in “Advice” and “Templates”; the recommended template needs no extra background. All side panels look alike, with the header above the frame and the chosen tab in gold; the template sits at the top of the talent window. “Best with n points” shows where it comes from, and its checkbox loads at once.
- Die gewählte Vorlage ist in „Empfehlung“ und „Vorlagen“ gleich hervorgehoben; die empfohlene Vorlage braucht keinen eigenen Hintergrund. Alle Seitenteile sehen gleich aus, mit dem Kopf über dem Kasten und dem gewählten Reiter in Gold; die Vorlage steht oben im Talentfenster. „Bestes mit n Punkten“ zeigt seine Herkunft, sein Haken lädt sofort.

## v1.0.0-beta2

Second beta for WoW Forever: a compact minimap, a talent advisor with play styles, gear advice from your talents, clearer rotations and party frames. “Agree to all” in the introduction now turns on, besides the actions without a click listed there, every other feature that is off by default and allowed by Blizzard's rules – except pure looks and anything that risks Blizzard's rules or a safeguard. Many features are still untested in the game; please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced).
Zweite Beta für WoW Forever: eine kompakte Minikarte, eine Talent-Empfehlung nach Spielweise, Ausrüstungs-Empfehlung aus deinen Talenten, verständlichere Rotationen und Gruppenrahmen. „Allem zustimmen“ in der Einführung schaltet jetzt neben den dort aufgeführten Abläufen ohne Klick auch jede andere Funktion ein, die ab Werk aus ist und die Blizzards Regeln erlauben – außer reiner Optik und allem, was Blizzards Regeln oder einen Schutz riskiert. Vieles ist im Spiel noch ungetestet; Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert).

### ezCore

- “Agree to all” (Introduction) switches on every feature that is off by default and allowed by Blizzard's rules, for example “Move Blizzard windows”; looks (marks, scaling, extra texts) stay your choice, and anything that risks Blizzard's rules or a safeguard (sends, picks, uses up or pays without a click, or lifts a safeguard) stays off. The confirmation names what stays off because of Blizzard's rules, the short overview also what stays your choice. The colour-blind marks on glowing buttons (off by default) use clear signs: > use now, + ready, ? missing or renew, ! right now. Icons fill their round or square frame. Shared quest colours by level for all modules, as in Blizzard's quest log.
- „Allem zustimmen“ (Einführung) schaltet jede Funktion ein, die ab Werk aus ist und die Blizzards Regeln erlauben, etwa „Blizzard-Fenster verschieben“; Optik (Zeichen, Skalierung, zusätzliche Texte) bleibt deine Wahl, und alles, was Blizzards Regeln oder einen Schutz riskiert (sendet, wählt, verbraucht oder zahlt ohne Klick, hebt eine Sicherung auf), bleibt aus. Die Rückfrage nennt, was wegen Blizzards Regeln aus bleibt, die Kurzfassung auch, was deine Wahl bleibt. Die Farbenblind-Zeichen an leuchtenden Knöpfen (ab Werk aus) haben klare Zeichen: > jetzt nutzen, + bereit, ? fehlt oder erneuern, ! sofort. Symbole füllen ihren runden oder eckigen Rahmen. Gemeinsame Questfarben nach Stufe für alle Module, wie in Blizzards Questlog.

### ezAuction

- “Agree to all” also switches on “Sellable on other characters”.
- „Allem zustimmen“ schaltet auch „Bei anderen Charakteren verkaufbar“ ein.

### ezBuff

- The buff button on a party frame shows a missing buff without a debuff border, and its tooltip explains symbol and sign. Stones and oils only go onto a weapon that takes them (sharpening stones on blades, weightstones on blunt weapons, oils as your class uses them). “Agree to all” also switches on “Campfire buff”.
- Der Buff-Knopf am Gruppenrahmen zeigt einen fehlenden Buff ohne Debuff-Rand, sein Tooltip erklärt Symbol und Zeichen. Steine und Öle kommen nur auf eine Waffe, die sie annimmt (Wetzsteine auf Klingen, Gewichtssteine auf Wuchtwaffen, Öle je nach Klasse). „Allem zustimmen“ schaltet auch „Lagerfeuer-Buff“ ein.

### ezChat

- “Agree to all” also switches on “Save say, yell and emotes” and “Arrow keys without Alt”.
- „Allem zustimmen“ schaltet auch „Sagen, Schreien und Emotes speichern“ und „Pfeiltasten ohne Alt“ ein.

### ezCombat

- Rotations checked against current Forever guides; steps that rest on an assumption show an orange “Assumption” line in their tooltip on the spellbook's Rotation page. Affliction: Corruption before Bane of Agony, Nightfall Shadow Bolt before Drain Life; Reckless Swings for Arms and Fury; Kidney Shot and Healing Touch in the lists. Resource steps work even when the game hides the exact number; buttons only glow when the ability is ready or almost ready. Party frames: bars sit below Blizzard's frame, half as high as the mana bar, with the numbers written out to the right (switches “Numbers on the group frames” and “Only what concerns your role”). “Agree to all” also switches on interrupts, dispels, deaths and threat on group frames and “Summary after combat”.
- Rotationen gegen aktuelle Forever-Ratgeber geprüft; Schritte, die auf einer Annahme beruhen, zeigen in ihrem Tooltip auf der Zauberbuch-Seite „Rotation“ eine orange Zeile „Annahme“. Gebrechen: Verderbnis vor Omen der Pein, Nachtfall-Schattenblitz vor Lebensentzug; Tollkühne Schwünge für Waffen und Furor; Nierenhieb und Heilende Berührung in den Listen. Schritte mit Kraft funktionieren auch, wenn das Spiel die genaue Zahl verbirgt; Knöpfe leuchten nur, wenn die Fähigkeit bereit oder fast bereit ist. Gruppenrahmen: Balken unter Blizzards Rahmen, halb so hoch wie der Manabalken, die Zahlen ausgeschrieben rechts daneben (Schalter „Zahlen an den Gruppenrahmen“ und „Nur, was deine Rolle betrifft“). „Allem zustimmen“ schaltet auch Unterbrechungen, Bannungen, Tode und Aggro an Gruppenrahmen und „Zusammenfassung nach dem Kampf“ ein.

### ezGear

- With ezTalent running, “Automatic” weights come from ezTalent's model for your play style (the questionnaire on the “Advice” tab, otherwise your talents); hold Shift on a tooltip to see the source. The tooltip of a melee weapon says whether it fits your play style (green) or what your play style uses (orange); a shield is marked when your play style wants one. Your own choice of role or Pawn scale stays untouched.
- Läuft ezTalent, kommen die Gewichte unter „Automatisch“ aus ezTalents Rechenmodell für deine Spielweise (Fragebogen im Reiter „Empfehlung“, sonst deine Talente); mit Umschalt nennt der Tooltip die Quelle. Der Tooltip einer Nahkampfwaffe sagt, ob sie zu deiner Spielweise passt (grün) oder was deine Spielweise nutzt (orange); ein Schild wird markiert, wenn deine Spielweise einen will. Eine eigene Wahl (Rolle, Pawn-Skala) bleibt unberührt.

### ezHeal

- ezHeal writes all click bindings: macros put on a key from ezMacro and rank updates go through it, so “Undo” knows them and its question names what changed last.
- ezHeal schreibt alle Klick-Belegungen: Makros, die ezMacro auf eine Taste legt, und Rang-Aktualisierungen laufen darüber, so kennt „Zurück“ sie, und seine Rückfrage nennt, was zuletzt geändert wurde.

### ezMacro

- Fishing on its own key (entry in Blizzard's key bindings); the icon puts Blizzard's “Fishing” spell on an action bar. Click-casting explained in the tooltip and per key in the menu; “Buff group” in the “One-click” tab. Poison (Rogue), weapon imbue (Shaman), stone or oil (every class) per hand, only for weapons that take them. The header of “From your abilities” opens its own page. Mouse-over resurrection for Paladin, Shaman and Druid. “Type: All” sits centred on the divider. “Agree to all” also switches on “Note automatic emotes in my chat”.
- Angeln mit eigener Taste (Eintrag in Blizzards Tastaturbelegung); das Symbol legt Blizzards Zauber „Angeln“ auf eine Aktionsleiste. Klick-Zauber im Tooltip und je Taste im Menü erklärt; „Durchbuffen“ im Reiter „Ein-Klick“. Gift (Schurke), Waffenzauber (Schamane), Stein oder Öl (jede Klasse) je Hand, nur für Waffen, die sie annehmen. Die Kopfzeile „Aus deinen Fähigkeiten“ öffnet eine eigene Seite. Wiederbeleben per Maus für Paladin, Schamane und Druide. „Art: Alle“ steht mittig auf der Trennleiste. „Allem zustimmen“ schaltet auch „Automatische Emotes in meinem Chat vermerken“ ein.

### ezMail

- “Agree to all” also switches on “Fill in last recipient”.
- „Allem zustimmen“ schaltet auch „Letzten Empfänger eintragen“ ein.

### ezMap

- New switch “Compact minimap (box below, coordinates in it)” (off by default, on with “Agree to all”): Blizzard's coordinates between location and clock, magnifier and calendar on the ring, round buttons, the addon compartment right of the calendar; with ezPanel, location and clock move onto the bar and the minimap stops just below it. “Agree to all” also switches on “Rare enemy alert”.
- Neuer Schalter „Kompakte Minikarte (Kästchen unten, Koordinaten darin)“ (ab Werk aus, an mit „Allem zustimmen“): Blizzards Koordinaten zwischen Ort und Uhr, Lupe und Kalender auf dem Ring, runde Knöpfe, das Addon-Fach rechts vom Kalender; mit ezPanel wandern Ort und Uhr auf die Leiste, und die Minikarte endet knapp darunter. „Allem zustimmen“ schaltet auch „Hinweis auf seltene Gegner“ ein.

### ezPanel

- “Reset settings” arranges the bar anew: volume, experience, gold, bags and durability on the left, friends and group messages (when switched on) in the middle, location and clock on the right. “Reserve space at the top” is off by default for new setups and comes on with “Agree to all”.
- „Einstellungen zurücksetzen“ ordnet die Leiste neu: Lautstärke, Erfahrung, Gold, Taschen und Haltbarkeit links, Freunde und Gruppen-Nachrichten (wenn eingeschaltet) in der Mitte, Ort und Uhr rechts. „Platz oben für die Leiste“ ist bei neuen Einrichtungen ab Werk aus und kommt mit „Allem zustimmen“.

### ezQuest

- The levelling route weighs each quest by its level against yours and by the time it takes, and the tooltip “Why at this point:” explains the place. The route arrow on the minimap is larger, with an “Arrow size” slider. The experience bar tooltip is wider, with amounts on the right and the colours of the bar explained. Your rested bonus stays visible on the bar: it starts after your finished quests, as quest experience does not use it up. The quest colours on the bar now match the swatches in the tooltip, and the rested marker moves on by your finished quests (can be turned off).
- Die Leveling-Route gewichtet jede Quest nach ihrer Stufe im Vergleich zu deiner und nach dem Zeitaufwand, und der Tooltip „Warum an dieser Stelle:“ erklärt den Platz. Der Pfeil der Route auf der Minikarte ist größer, mit Regler „Größe des Pfeils“. Der Tooltip der Erfahrungsleiste ist breiter, mit Mengen rechts und erklärten Farben der Leiste. Deine Erholung bleibt auf der Leiste zu sehen: sie beginnt nach den fertigen Quests, denn Quest-Erfahrung verbraucht keine Erholung. Die Questfarben auf der Leiste passen jetzt zu den Farbproben im Tooltip, und die Erholungs-Marke rückt um die fertigen Quests weiter (abschaltbar).

### ezSocial

- Levels in the friends list and the Who list use Blizzard's quest colours, based on your effective level.
- Stufen in der Freundesliste und der Wer-Liste haben Blizzards Questfarben, bezogen auf deine wirksame Stufe.

### ezTalent

- New “Advice” tab: a short questionnaire (“How do you want to play?”) recommends a build for your play style, including weapon, pet or form variants and PvP builds for every damage and healing spec (some equal the main build). “Rate” compares your own tree with the best build of the model at exactly your number of points; “Effects” shows your character stats as a table (now, preview, comparison). The computed builds come from a revised model for all classes.
- Neuer Reiter „Empfehlung“: Ein kurzer Fragebogen („Wie willst du spielen?“) empfiehlt eine Verteilung für deine Spielweise, mit Varianten nach Waffe, Begleiter oder Gestalt und PvP-Verteilungen für jede Schadens- und Heiler-Spezialisierung (manche gleichen der Grundverteilung). „Bewerten“ vergleicht deinen eigenen Baum mit der besten Verteilung des Modells bei genau deiner Punktzahl; „Auswirkungen“ zeigt deine Charakterwerte als Tabelle (jetzt, Vorschau, Vergleich). Die berechneten Verteilungen stammen aus einem überarbeiteten Modell für alle Klassen.

## v1.0.0-beta1

First public version for WoW Forever. Every module is its own addon and can be switched on and off separately; all of them need the included base `ezCore` (shown as “ezCollection (Base)”) and the two storage folders `ezWorld` and `ezMarket`. New here? Esc » Options » AddOns » ezCollection » Introduction (or `/ez intro`) explains every module in a few sentences. Settings: Esc » Options » AddOns » ezCollection. Many features have not been tested in the game yet – please report errors with the copyable error list (Esc » Options » AddOns » ezCollection » Advanced). Whatever runs without your click and costs gold, sells, sends mail or changes Blizzard's displays is off by default – including ezQuest's “Make quest objects in the world sparkle” and “Icons above quest objects, herbs and ores”, which switch Blizzard's outline mode and interaction icons (Blizzard's values come back when you switch them off); ezCollection explains such a feature once at the matching Blizzard window, with an “Enable” button (Esc » Options » AddOns » ezCollection » Advanced: “Hints about actions without a click”, “Show hints again”).
Erste öffentliche Fassung für WoW Forever. Jedes Modul ist ein eigenes Addon und lässt sich einzeln ein- und ausschalten; alle brauchen die mitgelieferte Basis `ezCore` („ezCollection (Basis)“) und die beiden Speicher-Ordner `ezWorld` und `ezMarket`. Neu dabei? Esc » Optionen » AddOns » ezCollection » Einführung (oder `/ez einführung`) erklärt jedes Modul in wenigen Sätzen. Einstellungen: Esc » Optionen » AddOns » ezCollection. Vieles ist im Spiel noch ungetestet – Fehler bitte mit der Fehlerliste zum Kopieren melden (Esc » Optionen » AddOns » ezCollection » Erweitert). Was ohne deinen Klick Gold kostet, verkauft, Briefe sendet oder Blizzards Anzeigen umstellt, ist ab Werk aus – auch ezQuests „Quest-Objekte in der Welt funkeln lassen“ und „Symbole über Quest-Objekten, Kräutern und Erzen“, die Blizzards Umriss-Modus und Interaktionssymbole umstellen (Blizzards Werte kommen beim Ausschalten zurück); ezCollection erklärt so eine Funktion einmal am passenden Blizzard-Fenster, mit Knopf „Einschalten“ (Esc » Optionen » AddOns » ezCollection » Erweitert: „Hinweise auf Abläufe ohne Klick“, „Hinweise erneut zeigen“).

### ezCore

- Introduction to the addon and every module, offered once at the first start (Esc » Options » AddOns » ezCollection » Introduction, `/ez intro`, an “Introduction” button on every module page): short on one page or module by module, with every consent and every action without a click in one list. Small item icons in front of items in tooltips and clear gaps between tooltip sections; map icons without dark square frames; the spots of the modules at Blizzard's party frames sit inside the frame instead of between two frames; times are labelled as local time or server time. One behaviour in the addon compartment for all modules (left click: window or main function, right click: settings). Developer tools of the data probe only work with the developer switch.
- Einführung in das Addon und jedes Modul, beim ersten Start einmal angeboten (Esc » Optionen » AddOns » ezCollection » Einführung, `/ez einführung`, Knopf „Einführung“ auf jeder Modulseite): kurz auf einer Seite oder Modul für Modul, alle Einverständnisse und alle Abläufe ohne Klick in einer Liste. Kleine Symbole vor Gegenständen im Tooltip und klare Abstände zwischen den Abschnitten; Kartensymbole ohne dunkle eckige Rahmen; die Plätze der Module an Blizzards Gruppenrahmen liegen im Rahmen statt zwischen zwei Rahmen; Zeiten sind als Ortszeit oder Serverzeit beschriftet. Ein Verhalten im Addon-Fach für alle Module (Linksklick: Fenster oder Hauptfunktion, Rechtsklick: Einstellungen). Entwicklerwerkzeuge der Daten-Probe wirken nur mit dem Entwicklerschalter.
- Shared base for all modules: one settings category with a page per module, character data of all your alts, item, recipe, spell and dungeon knowledge read from the game client, price knowledge, contacts, chat channels, history of loot, gold, mail and auctions, item and unit tooltips, a mail queue, moving Blizzard frames (off by default), comfort switches, auras and cooldowns even while combat data is restricted, hints about actions without a click (once per feature, with an “Enable” button) and a copyable error list. Includes the storage addons `ezWorld` (discovery database: what dropped where, vendors, trainers, gathering spots, entrances, flight times) and `ezMarket` (prices).
- Gemeinsame Basis aller Module: eine Einstellungs-Kategorie mit einer Seite je Modul, Charakterdaten aller Twinks, Item-, Rezept-, Zauber- und Dungeon-Wissen aus dem Client, Preis-Wissen, Kontakte, Chat-Kanäle, Verlauf von Beute, Gold, Post und Auktionen, Tooltips für Gegenstände und Einheiten, Post-Warteschlange, Blizzard-Fenster verschieben (ab Werk aus), Komfort-Schalter, Auren und Abklingzeiten auch bei gesperrten Kampfdaten, Hinweise auf Abläufe ohne Klick (einmal je Funktion, mit Knopf „Einschalten“) und eine Fehlerliste zum Kopieren. Dazu die Speicher-Addons `ezWorld` (Entdecker-Datenbank: Beute, Händler, Lehrer, Fundorte, Eingänge, Flugzeiten) und `ezMarket` (Preise).

### ezBag

- Shows where your other characters' items lie – bags, bank, guild bank – right at the slot and in the tooltip (switch “Show item location”). “Make room” only carries out the kind you chose and never sells in combat; button “Reset settings”.
- Zeigt, wo die Gegenstände deiner anderen Charaktere liegen – Tasche, Bank, Gildenbank – direkt am Platz und im Tooltip (Schalter „Fundort zeigen“). „Platz schaffen“ führt nur die gewählte Art aus und verkauft nie im Kampf; Knopf „Einstellungen zurücksetzen“.
- Blizzard's own bags and bank in framed, adjustable groups; alts, guild bank, collections and library books; withdrawing from bank and guild bank; bags open with the trade window; “make room” suggestions; marks for items worth more at the auction house. Selling junk at vendors is off by default (hint with an “Enable” button at the vendor) and never happens in combat.
- Blizzards Tasche und Bank in eingerahmten, anpassbaren Gruppen; Twinks, Gildenbank, Sammlungen und Bibliotheksbücher; Entnahme aus Bank und Gildenbank; Tasche öffnet mit dem Handelsfenster; Vorschläge „Platz schaffen“; Marke für Gegenstände, die im Auktionshaus mehr wert sind. Plunder beim Händler verkaufen ist ab Werk aus (Hinweis mit Knopf „Einschalten“ am Händler) und geschieht nie im Kampf.

### ezMail

- Mail to your alts works like mail to contacts; greyed-out menu entries say why.
- Post an deine Twinks geht wie an Kontakte; ausgegraute Menüeinträge sagen, warum.
- Comfort for Blizzard's mail window: address book, selecting several letters, filtered “open all”, more than 12 stacks per send, expiry warning, sender rules, sending gold, searching the inbox, history and statistics, value of attachments with source and age.
- Komfort für Blizzards Postfenster: Adressbuch, mehrere Briefe auswählen, gefiltertes „Alle öffnen“, mehr als 12 Stapel, Ablaufwarnung, Absender-Regeln, Gold überweisen, Posteingang durchsuchen, Verlauf und Statistik, Wert der Anhänge mit Quelle und Alter.

### ezChat

- Pointing at a link in the conversation window shows its tooltip without a click. Sending whispers typed in the normal chat later and automatic replies are off by default (hint with an “Enable” button at the chat frame); forgetting an alt also clears its chat data.
- Zeigt die Maus im Gesprächsfenster auf einen Link, erscheint sein Tooltip ohne Klick. Später nachsenden, was du im normalen Chat geflüstert hast, und automatische Antworten sind ab Werk aus (Hinweis mit Knopf „Einschalten“ am Chatfenster); ein vergessener Twink verliert auch seine Chat-Daten.
- Lasting chat history, conversations in the chat frame with visible Send and Dock/Undock buttons, messages to offline players (also by mail), clickable links, highlighting, alerts, search, spam filter, behaviour per situation, Blizzard's player menu in the conversation header; can dock to the friends list. Sending waiting messages as letters by itself at the mailbox is off by default (it costs postage; hint with an “Enable” button at the mailbox); retrying a whisper stops after 12 tries or 24 hours.
- Dauerhafter Chatverlauf, Gespräche im Chatfenster mit sichtbaren Knöpfen „Senden“ und „Andocken“/„Lösen“, Nachrichten an Offline-Spieler (auch per Brief), anklickbare Links, Hervorheben, Alarme, Suche, Spam-Filter, Verhalten je Lage, Blizzards Spieler-Menü im Gesprächskopf; dockt an die Freundesliste an. Wartende Nachrichten von selbst als Brief am Briefkasten senden ist ab Werk aus (kostet Porto; Hinweis mit Knopf „Einschalten“ am Briefkasten); erneutes Flüstern hört nach 12 Versuchen oder 24 Stunden auf.
- Chat history at login is off by default (switch on the ezChat page) and comes without header and footer lines.
- Der Verlauf beim Einloggen ist ab Werk aus (Schalter auf der Seite von ezChat) und kommt ohne Kopf- und Endzeile.

### ezPanel

- Colours of the bar follow Blizzard's colour roles; the consent box of the introduction also switches automatic repair off; repair, selling grey items and switches on the bar never act in combat.
- Die Farben der Leiste folgen Blizzards Farbrollen; das Häkchen der Einführung schaltet auch das automatische Reparieren aus; Reparieren, Graues verkaufen und Schalter auf der Leiste wirken nie im Kampf.
- Information bar in Blizzard's style with blocks (lockouts of all alts, minimap buttons, gold and loot history, error counter, auctions, gathering and more); makes room at the top of the screen (can be switched off, never in combat); other modules can add blocks and warnings. Automatic repair is off by default (hint with an “Enable” button at the vendor).
- Info-Leiste im Blizzard-Stil mit Bausteinen (Sperren aller Twinks, Minikarten-Knöpfe, Gold- und Beute-Verlauf, Fehlerzähler, Auktionen, Sammeln und mehr); schafft oben Platz (abschaltbar, nie im Kampf); andere Module hängen Bausteine und Meldungen an. Automatisch reparieren ist ab Werk aus (Hinweis mit Knopf „Einschalten“ am Händler).

### ezMacro

- Short command `/ezmc` (besides `/ezmacro`); bar profiles from shared text are checked before they are used; automatic thanking and spitting explain themselves once at Blizzard's macro window (hint with an “Enable” button).
- Kurzbefehl `/ezmc` (neben `/ezmacro`); Leisten-Profile aus geteiltem Text werden vor dem Übernehmen geprüft; automatisches Danken und Spucken erklären sich einmal an Blizzards Makroverwaltung (Hinweis mit Knopf „Einschalten“).
- Ready-made macros for every class and race (templates checked against the client tables, plus macros from your own spells), macros grouped by kind, updating spell ranks with glow, one-click macros (food, drink, bandage, potion, mount, hearthstone), fishing with one key, announcements, emote macros and emote bars, bar profiles, long macros, saving and sharing macros. Automatic emotes (off by default) recognise foreign healers only by Blizzard's heal prediction and your killer only by the death recap – never by the combat log.
- Fertige Makros für jede Klasse und jedes Volk (Vorlagen gegen die Client-Tabellen abgeglichen, dazu Makros aus deinen eigenen Fähigkeiten), Makros nach Art gruppiert, Ränge aktualisieren mit Leuchten, Ein-Klick-Makros (Essen, Trinken, Verband, Heiltrank, Reittier, Ruhestein), Angeln mit einer Taste, Ansagen, Emote-Makros und Emote-Leisten, Leisten-Profile, lange Makros, Makros sichern und teilen. Automatische Emotes (ab Werk aus) erkennen fremde Heiler nur über Blizzards Heilvorhersage und deinen Mörder nur über den Todesrückblick – nie über das Kampflog.

### ezCombat

- Less text: the next ability above your character shows only its icon (choice “Text below the icon”: off, name only, everything); damage, healing and aggro at Blizzard's party frames sit inside the frame. Rotations shared as text are checked before use.
- Weniger Text: die nächste Fähigkeit über dem Charakter zeigt nur ihr Symbol (Auswahl „Text unter dem Symbol“: aus, nur Name, alles); Schaden, Heilung und Aggro an Blizzards Gruppenrahmen liegen im Rahmen. Als Text geteilte Rotationen werden vor dem Übernehmen geprüft.
- Combat help in Blizzard's style: the next action of the rotation glows on your action button (per class and talent tree), expiring DoTs and HoTs, reactive abilities, swing timer extras, energy tick, five-second rule, totem and weapon enchant timers (poisons, oils, stones), cooldown numbers; damage, healing and more (top 3, interrupts, dispels, deaths, aggro) at Blizzard's party and raid frames; summary after combat; rotation page in the spellbook as a cheat sheet. In combat the suggestion uses only values the game shows openly; “Count when the game locks values” is off by default (hint with an “Enable” button at the spellbook).
- Kampfhilfen im Blizzard-Stil: die nächste Aktion der Rotation leuchtet am Aktionsknopf (je Klasse und Talentbaum), auslaufende DoTs und HoTs, reaktive Fähigkeiten, Schlagtimer-Extras, Energie-Tick, 5-Sekunden-Regel, Totem- und Waffen-Timer (Gifte, Öle, Steine), Zahlen auf Abklingzeiten; Schaden, Heilung und mehr (erste drei Plätze, Unterbrechungen, Bannungen, Tode, Aggro) an Blizzards Gruppen- und Raidrahmen; Zusammenfassung nach dem Kampf; Seite „Rotation“ im Zauberbuch als Spickzettel. Im Kampf nutzt die Empfehlung nur Werte, die das Spiel offen zeigt; „Mitzählen, wenn das Spiel Werte sperrt“ ist ab Werk aus (Hinweis mit Knopf „Einschalten“ am Zauberbuch).
- Rotation pages in the spellbook: click a step to swap the ability, drag it to change the order, right-click to turn it off (not in combat); “Create” next to “Choose another” starts a rotation of your own; template tooltips are wide with spacing.
- Rotationsseiten im Zauberbuch: Klick auf einen Schritt tauscht die Fähigkeit, Ziehen ändert die Reihenfolge, Rechtsklick schaltet ihn aus (nicht im Kampf); „Erstellen“ neben „Andere wählen“ beginnt eine eigene Rotation; die Tooltips der Vorlagen sind breit und mit Abständen.

### ezGear

- Gear check of the group at Blizzard's raid window (button “Check group”, only on your click, never in combat): average item level, missing enchantments and empty slots per member.
- Ausrüstungs-Check der Gruppe an Blizzards Schlachtzugsfenster (Knopf „Gruppe prüfen“, nur auf deinen Klick, nie im Kampf): Ø-Itemlevel, fehlende Verzauberungen und leere Plätze je Mitglied.
- Recognises better gear: arrow on bag slots and quest rewards, item level at the character frame and when inspecting, stat weights, profiles per character, class or specialisation, equipment sets, durability, “gear to chat”.
- Bessere Ausrüstung erkennen: Pfeil auf Taschenplätzen und Questbelohnungen, Itemlevel am Charakterfenster und beim Betrachten, Gewichtung, Profile je Charakter, Klasse oder Spezialisierung, Ausrüstungssets, Haltbarkeit, „Ausrüstung in den Chat“.

### ezMerchant

- Automatic repair, junk selling and restocking never act in combat; item icons and gaps in the tooltip like everywhere else.
- Automatisch reparieren, Plunder verkaufen und Vorrat auffüllen wirken nie im Kampf; Symbole und Abstände im Tooltip wie überall.
- Vendors and trainers: “learn all”, “what comes when” as a spellbook page, wider vendor frame, automatic repair and junk selling, restocking, trainers on the map, pet trainer help, warning when an item is worth more at the auction house. Automatic repair, junk selling and restocking are off by default, each with a hint and an “Enable” button at the vendor.
- Händler und Lehrer: „Alles lernen“, „Was kommt wann“ als Seite im Zauberbuch, breiteres Händlerfenster, automatisch reparieren und Plunder verkaufen, Vorrat auffüllen, Lehrer auf der Karte, Hilfe beim Tierausbilder, Warnung „im Auktionshaus mehr wert“. Automatisch reparieren, Plunder verkaufen und Vorrat auffüllen sind ab Werk aus, je mit Hinweis und Knopf „Einschalten“ am Händler.

### ezSocial

- A hint at Blizzard's friends list for actions without a click (accept summons and resurrections, decline duels and invitations from strangers); one look for tooltips and buttons.
- Hinweis an Blizzards Freundesliste für Abläufe ohne Klick (Beschwörung und Wiederbelebung annehmen, Duelle und Einladungen von Fremden ablehnen); ein Aussehen für Tooltips und Knöpfe.
- Group finder help with classes, roles and levels; group messages from chat sorted by dungeon; “invite to guild” in the player menu.
- Gruppensuche mit Klassen, Rollen und Stufen; Gruppen-Nachrichten aus dem Chat nach Dungeon; „In Gilde einladen“ im Spieler-Menü.

### ezQuest

- Experience of your quests as a preview on Blizzard's experience bar (finished quests bright, all quests pale, tooltip with the level after turning in). Share accepted quests with your group automatically (off by default, hint with an “Enable” button) or with one click (“Share now”). The levelling route calculates by itself, recalculates when you enter another zone, groups goals of one quest into one step and no longer zigzags. Section “Sparkle and highlight” for quest items in bags and loot window; the tooltip says that only lootable objects sparkle.
- Erfahrung deiner Quests als Vorschau auf Blizzards Erfahrungsleiste (fertige Quests hell, alle Quests blass, Tooltip mit der Stufe nach der Abgabe). Angenommene Quests automatisch mit der Gruppe teilen (ab Werk aus, Hinweis mit Knopf „Einschalten“) oder mit einem Klick („Jetzt teilen“). Die Leveling-Route rechnet von selbst, rechnet beim Wechsel in eine andere Zone neu, fasst Ziele einer Quest zu einem Schritt zusammen und läuft nicht mehr im Zickzack. Abschnitt „Funkeln und Hervorheben“ für Quest-Gegenstände in Tasche und Beutefenster; der Tooltip sagt, dass nur plünderbare Objekte funkeln.
- Adds to Questie and Blizzard's quest windows: level in front of every quest in NPC dialogues, quest items (also ordinary goods a quest needs), automatic accept and turn-in with the checkbox “Automatic” (off by default; never quests that cost gold, quests from players, grey or repeatable quests unless you allow them), new Forever quests tinted, dungeon quests with level range and entrance, quest ID in the quest log tooltip.
- Levelling route through your own quest log (gear menu at the quest log, ezMap's map button, `/ezq route`): the next steps in an order that brings much experience early and avoids walking twice, your level projected along the way (a quest that would turn grey moves forward), vendor and repair stops and herbs and ore along the way if you like, a line on the world map. It navigates with Blizzard's map pin; the arrow comes with ezMap's switch “Turn on navigation” or a click on the pin. Places come from the game client, otherwise from Questie (read only while a route exists, nothing is stored).
- Off by default, each with a hint and an “Enable” button at Blizzard's quest tracker: “Sort tracker by level”, “Restore navigation after sorting” (without it, sorting waits while navigation follows one of the quests), “Make quest objects in the world sparkle” and “Icons above quest objects, herbs and ores” (they change Blizzard's graphics and accessibility settings; if you had them on, the update switches them off once and gives Blizzard's values back – the sparkle goes away after the next game restart). Also off by default in the levelling route: “Next quest of the route in Blizzard's tracker” and “Take the arrow along when moving on”.
- Ergänzt Questie und Blizzards Questfenster: Stufe vor jeder Quest in den NPC-Dialogen, Quest-Gegenstände (auch normale Waren, die eine Quest braucht), automatisch annehmen und abgeben mit dem Häkchen „Automatisch“ (ab Werk aus; nie Quests mit Gold-Kosten, von Spielern, graue oder wiederholbare Quests, außer du erlaubst es), neue Forever-Quests getönt, Dungeon-Quests mit Stufenbereich und Eingang, Quest-ID im Tooltip des Questlogs.
- Leveling-Route durch dein eigenes Questlog (Zahnrad-Menü am Questlog, ezMaps Kartenknopf, `/ezq route`): die nächsten Schritte in einer Reihenfolge, die viel Erfahrung früh bringt und doppelte Wege vermeidet, deine Stufe entlang des Wegs hochgerechnet (eine Quest, die grau würde, rückt nach vorn), auf Wunsch Halte bei Händler und Reparatur sowie Kräuter und Erze am Weg, eine Linie auf der Weltkarte. Geführt wird mit Blizzards Kartenmarkierung; den Pfeil gibt es mit ezMaps Schalter „Zielverfolgung einschalten“ oder einem Klick auf die Markierung. Orte kommen aus dem Client, sonst laut Questie (nur gelesen, solange eine Route besteht, nichts gespeichert).
- Ab Werk aus, je mit Hinweis und Knopf „Einschalten“ an Blizzards Questverfolgung: „Verfolgung nach Stufe sortieren“, „Zielverfolgung nach dem Sortieren zurücksetzen“ (ohne diesen Schalter wartet das Sortieren, solange die Zielverfolgung einer der Quests folgt), „Quest-Objekte in der Welt funkeln lassen“ und „Symbole über Quest-Objekten, Kräutern und Erzen“ (sie stellen Blizzards Grafik- bzw. Barrierefreiheits-Einstellungen um; waren sie bei dir an, stellt das Update sie einmal aus und gibt Blizzards Werte zurück – das Funkeln verschwindet nach dem nächsten Neustart des Spiels). Ebenfalls ab Werk aus in der Leveling-Route: „Nächste Quest der Route in Blizzards Verfolgung“ und „Pfeil beim Weiterrücken mitnehmen“.
- The levelling route is one continuous line from where you stand, is recomputed when you open the world map after moving, avoids crossing paths and can show a small arrow on the minimap towards the next step (“Levelling route arrow on the minimap”).
- Die Leveling-Route ist eine durchgehende Linie ab deinem Standort, wird beim Öffnen der Weltkarte nach einem Ortswechsel neu berechnet, vermeidet überkreuzte Strecken und kann auf der Minikarte einen kleinen Pfeil zum nächsten Schritt zeigen („Pfeil zur Leveling-Route auf der Minikarte“).

### ezMap

- One button at Blizzard's world map with sensible sections (Blizzard's map filter stays free unless you want ezMap there). Route lines start at your position, follow you and dissolve behind you, with arrows in walking direction and numbers at the steps – for the levelling route and the gathering route. Your gathering marker disappears on the minimap while you stand close to it; “Select all” in the tracking menu says which search spells you have to click yourself.
- Ein Knopf an Blizzards Weltkarte, sinnvoll aufgeteilt (Blizzards Kartenfilter bleibt frei, außer du willst ezMap dort). Routenlinien beginnen an deinem Ort, folgen dir und lösen sich hinter dir auf, mit Pfeilen in Laufrichtung und Nummern an den Schritten – für Leveling- und Sammel-Route. Deine Sammel-Markierung verschwindet auf der Minikarte, solange du nah davor stehst; „Alle auswählen“ im Menü „Aufspüren“ sagt, welche Such-Zauber du selbst anklicken musst.
- Map help on Blizzard's own world map and minimap, no arrow of its own: `/way` sets Blizzard's map pin (`/ezway` if TomTom owns `/way`), and the pin goes away a few seconds after you reach it (switch “Remove pin on arrival”).
- Map menu at a button next to Blizzard's pin button and in Blizzard's map filter, with matching icons and the topics “Services in town”, “Gathering”, “Discover”, “Journey” and “Own waypoints and map helpers”: trainers you visited, dungeon entrances, flight masters and the flight points you or your alts still lack, library books, recipes, enemies and objects according to Questie (off by default); every tooltip names its source.
- Flight times learned on your own flights with a flight bar, coordinates on the world map, battleground timers, a square minimap and zooming out by itself (both off by default).
- Destinations of ezMap at the bottom of Blizzard's minimap tracking menu; remembers your selection and can switch together with Blizzard's own entries.
- Your own gathering spots on the world map and minimap from your own harvests: value per harvest, skill needed, routes through the zone (chests only if you want discovery knowledge).
- Off by default, each with a hint and an “Enable” button at the world map: “Turn on navigation” (only with this switch does ezMap turn on Blizzard's arrow, also after your click; otherwise a click on the pin brings the arrow) and “Turn on search spells by itself” (otherwise ezMap offers the remembered search spell for a click in the tracking menu; if Blizzard blocks switching it on, the box turns itself off).
- For other modules: map pin with owner, a path line on the world map (used by ezQuest's levelling route) and `WaypointTracking()`.
- Kartenhilfen auf Blizzards eigener Welt- und Minikarte, ohne eigenen Pfeil: `/way` setzt Blizzards Kartenmarkierung (`/ezway`, wenn TomTom `/way` hat), und die Markierung verschwindet wenige Sekunden nach der Ankunft (Schalter „Markierung bei Ankunft entfernen“).
- Kartenmenü an einem Knopf neben Blizzards Pin-Knopf und in Blizzards Kartenfilter, mit passenden Symbolen und den Themen „Dienste in der Stadt“, „Sammeln“, „Entdecken“, „Reise“ und „Eigene Wegpunkte und Kartenhilfen“: besuchte Lehrer, Dungeoneingänge, Flugmeister und die Flugpunkte, die dir oder deinen Twinks fehlen, Bibliotheksbücher, Rezepte, Gegner und Objekte laut Questie (ab Werk aus); jeder Tooltip nennt seine Quelle.
- Flugzeiten aus den eigenen Flügen mit Flugleiste, Koordinaten auf der Weltkarte, Schlachtfeld-Timer, eckige Minikarte und von selbst herauszoomen (beides ab Werk aus).
- Ziele von ezMap unten in Blizzards Menü „Aufspüren“ an der Minikarte; merkt deine Auswahl und kann mit Blizzards eigenen Einträgen gemeinsam schalten.
- Deine eigenen Sammel-Fundorte auf Welt- und Minikarte aus deinen Ernten: Wert je Ernte, nötige Fertigkeit, Routen durch die Zone (Kisten nur, wenn du Entdecker-Wissen willst).
- Ab Werk aus, je mit Hinweis und Knopf „Einschalten“ an der Weltkarte: „Zielverfolgung einschalten“ (nur mit diesem Schalter schaltet ezMap Blizzards Pfeil ein, auch nach deinem Klick; sonst bringt ein Klick auf die Markierung den Pfeil) und „Such-Zauber selbst einschalten“ (sonst bietet ezMap den gemerkten Such-Zauber im Menü „Aufspüren“ zum Anklicken an; blockiert Blizzard das Einschalten, geht der Haken von selbst aus).
- Für andere Module: Markierung mit Besitzer, eine Weglinie auf der Weltkarte (nutzt ezQuests Leveling-Route) und `WaypointTracking()`.
- Gathering colour filters such as “Red – not yet gatherable” also apply to the gathering route; “Agree to all” in the introduction hides red nodes.
- Die Farbfilter der Sammel-Fundorte wie „Rot – noch nicht abbaubar“ gelten auch für die Sammel-Route; „Allem zustimmen“ in der Einführung blendet rote Fundorte aus.

### ezCraft

- Item icons and clear gaps in the item tooltip; forgetting an alt also clears its craft data.
- Symbole und klare Abstände im Gegenstands-Tooltip; ein vergessener Twink verliert auch seine Berufsdaten.
- Section, button column and side tabs right in Blizzard's profession window (no window of its own): materials in bags, bank, mail, guild bank and on your alts, who can craft a recipe, shopping list for all alts with “Search AH”, missing recipes, profession cooldowns of all alts, material costs, value and profit from your own auction prices, skill-up colors from the game client; disenchant value and a “Disenchant” tab; “Spots” menu in the profession book (gathering spots from your own harvests) and “Color (ezCraft)” in Blizzard's filter menu, both with icons.
- Abschnitt, Knopfspalte und Seitenreiter direkt in Blizzards Berufefenster (kein eigenes Fenster): Material in Tasche, Bank, Post, Gildenbank und bei den Twinks, wer ein Rezept herstellen kann, Einkaufsliste für alle Twinks mit „Im AH suchen“, fehlende Rezepte, Berufs-Abklingzeiten aller Twinks, Materialkosten, Wert und Gewinn aus den eigenen Auktionspreisen, Skill-Farben aus dem Client; Entzauber-Wert und Reiter „Entzaubern“; Menü „Fundorte“ im Berufsbuch (Sammel-Fundorte aus den eigenen Ernten) und „Farbe (ezCraft)“ in Blizzards Filtermenü, beide mit Symbolen.

### ezBuff

- The missing-buff icon sits on Blizzard's party frame instead of hanging between the frames. Long self-buffs are reminded too (Trueshot Aura, Righteous Fury, Soul Link), each can be deselected.
- Das Symbol des fehlenden Buffs sitzt am Gruppenrahmen statt zwischen den Rahmen. Lange Selbst-Buffs werden ebenfalls angemahnt (Aura des Volltreffers, Zorn der Gerechtigkeit, Seelenverbindung), jeder ist abwählbar.
- Reports missing buff food, flasks and class buffs outside combat with a button at Blizzard's buff bar; group section at Blizzard's party frames (buff the whole group, blessings per class or player); hint when a reagent or tool is missing. Returning a buff thanks the giver at most once per buff.
- Meldet außerhalb des Kampfes fehlendes Buff-Essen, Fläschchen und Klassen-Buffs mit einem Knopf an Blizzards Buff-Leiste; Abschnitt „Gruppe“ an Blizzards Gruppenrahmen (durchbuffen, Segen je Klasse oder Spieler); Hinweis, wenn ein Reagenz oder Werkzeug fehlt. Beim Zurückgeben eines Buffs wird höchstens einmal je Buff gedankt.

### ezLoot

- Small item icons in front of every loot line in the tooltips (“Loot with you”, gathering), with quality colour; automatic looting cannot be switched in combat.
- Kleine Symbole vor jeder Beute-Zeile in den Tooltips („Beute bei dir“, Sammeln), mit Qualitätsfarbe; automatisch plündern lässt sich nicht im Kampf umschalten.
- Faster looting, loot and roll frames with item level and “better”, loot history docked to Blizzard's roll results, possible loot of an enemy in the tooltip from your own counts and connected addon databases (each with its source).
- Schneller plündern, Plündern- und Würfelfenster mit Itemlevel und „besser“, Beute-Verlauf an Blizzards Würfelergebnissen, mögliche Beute eines Gegners im Tooltip aus der eigenen Zählung und angebundenen Addon-Datenbanken (jeweils mit Quelle).

### ezBars

- Buttons outside the grid or on a switched-off bar no longer fire through their key binding.
- Knöpfe außerhalb des Rasters oder auf einer abgeschalteten Leiste lösen über ihre Taste nicht mehr aus.
- Extra action bars in Blizzard's style with freely chosen columns and rows, profiles, one move mode, bars with buttons of other modules.
- Zusatzleisten im Blizzard-Stil mit frei wählbaren Spalten und Reihen, Profile, ein Verschiebe-Modus, Leisten mit Knöpfen anderer Module.

### ezAuction

- “Today” in the histories is labelled as local time, price history uses server time; forgetting an alt also clears its auction data.
- „Heute“ in den Verläufen ist als Ortszeit beschriftet, der Preisverlauf rechnet in Serverzeit; ein vergessener Twink verliert auch seine Auktionsdaten.
- Blizzard's auction house with price memory, a “Market” side panel, shopping lists with filters and price limits, sell list with recommendation, “undercut” notices, bargains and watch list, search history and auction history; works without any other auction addon.
- Blizzards Auktionshaus mit Preisgedächtnis, Seitenteil „Markt“, Einkaufslisten mit Filtern und Höchstpreis, Verkaufsliste mit Empfehlung, Meldung „unterboten“, Schnäppchen und Beobachtungsliste, Suchverlauf und Auktionsverlauf; braucht kein anderes Auktions-Addon.

### ezTalent

- Nothing is set while Blizzard's “Apply” is still running; “No” in the question keeps your queued changes.
- Nichts wird gesetzt, solange Blizzards „Übernehmen“ noch läuft; „Nein“ in der Rückfrage behält die vorgemerkten Änderungen.
- Talent and legacy templates right at Blizzard's talent and legacy windows (no window of their own): save, apply as a preview (only Blizzard's own “Apply” makes it real), reset and apply, rename, share and paste; a preselection of typical Forever builds per class with sources and rating; the matching ezCombat rotation; an equipment set from ezGear and an action bar profile from ezMacro per template, picked in a menu with icons, sections by class and the source in every tooltip; effects of the chosen talents and points, an overview of your alts; measuring for the talent simulation (`/ezt values`).
- Talent- und Vermächtnis-Vorlagen direkt an Blizzards Talent- und Vermächtnis-Fenster (kein eigenes Fenster): speichern, als Vorschau anwenden (gültig erst mit Blizzards eigenem „Übernehmen“), zurücksetzen und anwenden, umbenennen, teilen und einfügen; Vorauswahl typischer Forever-Bäume je Klasse mit Quellen und Einstufung; die passende Rotation aus ezCombat; je Vorlage ein Ausrüstungsset aus ezGear und ein Leistenprofil aus ezMacro, gewählt in einem Menü mit Symbolen, Abschnitten nach Klasse und der Quelle in jedem Tooltip; Auswirkungen der gewählten Talente und Vorteile, Übersicht der Twinks; Messung für die Talent-Simulation (`/ezt werte`).

### ezHeal

- Own HoTs sit inside Blizzard's classic party frame; loading a click profile lists its bindings first, and Blizzard's open click casting window shows the new state right away.
- Eigene HoTs liegen im klassischen Gruppenrahmen; ein Klick-Profil nennt vor dem Laden seine Belegung, und Blizzards offenes Fenster „Klick-Zauber“ zeigt den neuen Stand sofort.
- Healing, dispelling, resurrecting and buffing by clicking Blizzard's party and raid frames: templates per class for Blizzard's click casting with preview, backup and undo, own HoTs at the frames, healing macros for every class.
- Heilen, Bannen, Wiederbeleben und Buffen per Klick auf Blizzards Gruppen- und Raidrahmen: Vorlagen je Klasse für Blizzards Klick-Zaubern mit Vorschau, Sicherung und „Zurück“, eigene HoTs am Rahmen, Heil-Makros für jede Klasse.
