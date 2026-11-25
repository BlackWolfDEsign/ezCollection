# Design-System der ezCollection

Regeln und Werte für jede Oberfläche der ezCollection: blizzlike, Blizzards Vorhandenes erweitern statt nachbauen, und überall einheitlich.

| Was | Wo |
|---|---|
| Regeln mit Belegen aus Blizzards Forever-Quelle | diese Datei |
| Werte (Ebenen, Symbol- und Knopfgrößen, Schrift- und Farb-Rollen) und Helfer | `ezCore/Bausteine/Style.lua` (`Core.Style`, Beschreibung in [ezcore.md](ezcore.md), Abschnitt „Design-System: Werte und Helfer“) |
| Bausteine | ezCore: Fenster, Seitenteile, Reiter, Menüs, Tooltips, Leuchten, Dialoge (unten je Regel genannt) |

Die Regeln werden außerhalb des Spiels automatisch geprüft; Ausnahmen stehen mit Begründung in einer Liste. Quelle der Belege: Blizzards UI-Quelle für Forever (Gethe/wow-ui-source, Zweig `forever`, Spieltyp „camelot“), gelesen am 16.11.2026. Pfade unten relativ zu `Interface/AddOns/`.

## 1. Grundsatz

1. **Blizzard zuerst.** Jedes Oberflächenteil erweitert ein Blizzard-Fenster, nimmt eine Blizzard-Vorlage, eine Blizzard-Schrift, eine Blizzard-Farbe und Blizzards Maße. Ein eigener Wert ist nur erlaubt, wo Blizzard keinen hat – dann steht er einmal in `Core.Style` (bzw. ezCores Baustein) und nirgends sonst (eine Quelle, keine Kopien).
2. **Erweitern statt nachbauen.** Ein eigener Rahmen unter `UIParent` nur, wo Blizzard kein passendes Fenster hat – mit Begründung in einer automatisch geprüften Liste; sonst Reiter, Seitenteil, Knopf oder Menüeintrag an Blizzards Fenster.
3. **Einheitlich.** Gleiches sieht überall gleich aus und heißt gleich: dieselbe Rolle nimmt dieselbe Schrift, Farbe, Größe und denselben Wortlaut.
4. **Prüfbar.** Was eine Regel ist, wird automatisch geprüft; Ausnahmen stehen mit Begründung in einer Liste.

## 2. Regeln und Werte

### 2.1 Fenster, Reiter, Seitenteile

- **Fenster:** nur, wo Blizzard keines hat (mit Begründung in der geprüften Liste der eigenen Fenster). Rahmen aus Blizzards Vorlagen: `PortraitFrameFlatTemplate` (Vorgabe von `Core.NewWindow`, wie Blizzards Taschen: `ContainerFrameTemplate inherits="PortraitFrameFlatTemplate"`) bzw. `ButtonFrameTemplate`/`PortraitFrameTemplate` (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`), gebaut über `Core.NewWindow` (Titel, Porträt, Schließen-Knopf `UIPanelCloseButton`, Position merken, Esc über `UISpecialFrames`). Ebene wie Blizzards Fenster: MEDIUM (`ContainerFrameTemplate frameStrata="MEDIUM"`, `Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml`).
- **Reiter am Rand eines Blizzard-Fensters:** `Core.CreateSideTab` / `Core.BuildSideTab` mit `SideTabs.Add` (eine Reihe je Fenster, Reihenfolge über `SideTabs.SetOrder`). Reiter unten wie Blizzards: `PanelTabButtonTemplate` (`SharedUIPanelTemplates.xml`).
- **Seitenteil:** `Core.NewSidePanel` bzw. `Core.Dock`/`Core.DockRoom` – als Kind des Fensters, an dem es hängt, damit es mitwandert und dessen Ebene erbt.
- **Abstände:** Inhalt mit den Einzügen der Blizzard-Vorlage (`Inset` der `ButtonFrameTemplate`); Werte nicht von Hand nachbauen, sondern am Inset bzw. an Blizzards Elementen verankern.

### 2.2 Knöpfe

- Textknopf: `UIPanelButtonTemplate` (`SharedUIPanelTemplates.xml`); im Kopf eines Fensters `Window:HeaderButton`, in einer Leiste `Toolbar.New` (Maße in `Core.LAYOUT`).
- Schließen: `UIPanelCloseButton` (24 × 24, `UIPanelCloseButtonNoScripts`); Haken: `Core.CreateCheck` (Blizzards `UICheckButtonTemplate`; quadratischer Haken ohne Vorlage 20 wie `NineSliceCheckButtonTemplate`); kleiner Info-Knopf 16 wie `UIPanelInfoButton`. Werte: `Core.Style.BUTTON` = { close = 24, check = 20, small = 16 }.
- Knopf mit Symbol: Blizzards Vorlagen (`ActionButtonTemplate`, `ItemButtonTemplate`) oder `Toolbar.SlotButton` (Rahmen aus Blizzards Atlas über `Core.StyleIcon`).
- Jede Funktion hat einen sichtbaren Knopf, Reiter oder Pfeil; Rechtsklick und Befehle nur zusätzlich.
- **Pfeil und Zahnrad**: Pfeil nach unten = Menü dieses Teils (`Core.Toolbar.ArrowButton`, Größe über `opts.size`), Zahnrad = Einstellungen (`Core.Toolbar.GearButton`). Das Zahnrad hat eine Quelle: `Core.Menu.ICON_SETTINGS` (Blizzards Atlas `questlog-icon-setting`, sonst `UI-OptionsButton`) – auch für Menüeinträge. Pfeil, Zahnrad, Platzknopf, Kopf- und Einstellungsknopf von ezCore zeigen ihren Tooltip auch gesperrt (`Toolbar.ShowTipWhileDisabled`, 2.7).
- **Auswahlfeld:** `Core.Menu.Dropdown(parent, breite, build, label)` – Blizzards `WowStyle1DropdownTemplate`, ohne die Vorlage immer ein Knopf mit Kontextmenü (nie still weiterschalten); Text auffrischen über `feld:RefreshText()`.
- **Menüeintrag „Einstellungen …“** eines Moduls: `Core.Menu.Settings(root, ns)` – Text „Einstellungen …“ (`L.MENU_OWN_SETTINGS`; „Optionen“ heißt nur Blizzards Fenster), Zahnrad, Tooltip, im Kampf vorgemerkt, sonst die Hilfe.
- **Zeitbalken:** `Core.NewTimerBar(parent, opts)` – Blizzards `UI-StatusBar` auf halbdunklem Grund, Farbe aus einer Rolle, auf Wunsch mit dem Rand der Zauberleiste.
- **Addon-Fach an der Minikarte**: überall Linksklick = Fenster bzw. Hauptfunktion des Moduls, Rechtsklick = Einstellungen; ohne Fenster öffnet jeder Klick die Einstellungen. Ein Tooltip-Format: Titel, „Linksklick: …“, „Rechtsklick: Einstellungen“ (ohne Fenster „Klick: Einstellungen“), dann die Befehlszeile mit dem geltenden Befehl – alles gebaut von `Core.CompartmentHandlers({ ns, main, mainText, extraLines })`. Der Befehl ohne Wort tut dasselbe wie der Linksklick (`opts.slash.main` im Gerüst).

### 2.3 Symbole

| Rolle | Größe | Beleg (Forever-Quelle) |
|---|---|---|
| `line` – Zeile in Menü und Liste | 16 | `Blizzard_SharedXML/Mainline/UIDropDownMenu.lua` (`icon:SetSize(16,16)`) |
| `aura` – Buff, Debuff | 30 | `Blizzard_BuffFrame/BuffFrameTemplates.xml` (`AuraButtonArtTemplate`, Icon 30 × 30) |
| `small` – kleiner Aktionsknopf | 30 | `Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml` (`SmallActionButtonTemplate`) |
| `item` – Gegenstand, Taschenplatz | 37 | `Blizzard_ItemButton/Shared/ItemButtonTemplate.xml`; Taschenplätze `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml` |
| `action` – Aktionsknopf | 45 | `ActionButtonTemplate.xml` (`ActionButtonTemplate` 45 × 45) |

- Werte: `Core.Style.ICON`, `Core.Style.IconSize(rolle)`. Rahmen und Maske aus Blizzards Atlas über `Core.StyleIcon` (`UI-HUD-ActionBar-IconFrame`, `…-Mask`).
- Symbole im Text (`|T…:0|t`) richten sich nach der Schrift (Größe 0) statt nach einer festen Zahl.
- **Symbole an Menüeinträgen**: Rolle `line` (16), Bild vor dem Text – über `Core.Menu.Icon(eintrag, icon)` bzw. `IconButton`/`IconToggle`/`IconTitle` (eigener Initializer nach Blizzards eigenem, wie Blizzards `CreateCheckboxWithIcon` im Menü „Aufspüren“; der Text des Eintrags selbst bleibt unverändert). Ausnahme zur Größe 0 oben, weil ein Menüeintrag eine feste Zeilenhöhe hat (20, `MenuVariants.CreateFontString`) und Blizzards Menüs ihre Symbole ebenfalls in fester Größe zeigen. Quelle des Bilds in dieser Reihenfolge: Blizzards Bild derselben Sache zur Laufzeit (z. B. `C_Minimap.GetTrackingInfo(i).texture` für Lehrer, Händler, Briefkasten, Reparieren, Flugmeister), Blizzards Atlas, Blizzards Datei (nur, wenn der Client sie kennt), sonst Blizzards Fragezeichen (`Core.Menu.ICON_FALLBACK`) – nie ein leeres Feld, keine eigenen Bilddateien. Zauber- und Gegenstandssymbole mit abgeschnittenem Rand (`crop`). Gleiche Dinge tragen in allen Menüs dasselbe Symbol (eine Tabelle je Modul, z. B. `ezMap/Icons.lua`). Listen in Untermenüs (einzelne Lehrer, Händler, Eingänge) bleiben ohne Symbol.
- **Abschnitte im Menü:** Überschrift (Blizzards Titelzeile, mit Symbol) nur, wenn der Abschnitt etwas enthält – `Core.Menu.Section(root, titel, { icon, tip, source })`. Tooltip je Eintrag: Titel, Beschreibung, Quelle grau (`Core.Menu.Tip(eintrag, titel, text, quelle)`, 2.7).
- Andere quadratische Größen (14, 18, 20 ohne Haken, 22, 24 ohne Schließen, 32 …) sind Abweichungen: Symbole in Zeilen nehmen 16, Knöpfe die BUTTON-Werte; eine Größe, die einem Blizzard-Teil folgt (z. B. Blizzards Kartenknopf 32 neben ezMaps Knopf), bleibt mit Begründung im Kommentar.

### 2.4 Schriften

- Nur Blizzards FontObjects (`Blizzard_Fonts_Shared/Shared/GameFonts.xml`), über `CreateFontString(…, "<Objekt>")` oder `Core.Style.SetFont(text, rolle)`.
- Rollen (`Core.Style.FONT`):

| Rolle | FontObject | wofür |
|---|---|---|
| `title` | `GameFontNormalLarge` | Überschrift eines Fensters oder Abschnitts |
| `heading` | `GameFontNormal` | Kopf einer Gruppe (Gold) |
| `label` | `GameFontNormalSmall` | Beschriftung (Gold, klein) |
| `text` | `GameFontHighlightSmall` | Fließtext und Werte (weiß, klein) |
| `value` | `GameFontHighlight` | hervorgehobener Wert |
| `hint` | `GameFontDisableSmall` | Erklärung, „wartet auf Daten“ |
| `off` | `GameFontDisable` | ausgeschaltet |
| `number` / `numberSmall` | `NumberFontNormal` / `NumberFontNormalSmall` | Zahl auf einem Symbol |
| `error` | `GameFontRedSmall` | Fehler, fehlt |

- Ein Teil, das ein Blizzard-Fenster nachbildet, nimmt dessen Schriften (z. B. ezCores Zauberbuch-Ansicht `SystemFont_*` wie Blizzards Zauberbuch; ezChat `ChatFontNormal` wie Blizzards Chat) – das ist keine Abweichung, steht aber im Bericht als „außerhalb der Rollen“, damit es bewusst bleibt.
- **Von Hand verboten:** Pfade zu Schriftdateien (`Fonts\…`, `.ttf`, `.otf`) außerhalb ezCore – die Prüfung lehnt sie ab. `SetFont` nur mit einer Schriftart, die aus einem Blizzard-Objekt gelesen wird (`GetFont`), und nur mit Begründung (heute: ezPanels Einstellung „Schriftgröße“, ezChats Nachrichtenschicht über Blizzards Chat).

### 2.5 Farben

- Nur Blizzards Farbobjekte und ezCores Leucht-Palette. Rollen (`Core.Style.COLOR`, `Core.Style.Color(rolle)` gibt r, g, b; `Core.Style.ColorText(rolle, text)`):

| Rolle | Blizzards Objekt | ezCores Kurzform |
|---|---|---|
| `normal` | `NORMAL_FONT_COLOR` (Gold) | `Core.GOLD` |
| `highlight` | `HIGHLIGHT_FONT_COLOR` (Weiß) | `Core.WHITE` |
| `disabled` | `DISABLED_FONT_COLOR` | – |
| `gray` | `GRAY_FONT_COLOR` | `Core.GREY`, `Core.Grey(text)` |
| `good` | `GREEN_FONT_COLOR` | `Core.GREEN`, `Core.Green(text)` |
| `bad` | `RED_FONT_COLOR` | `Core.RED`, `Core.Red(text)` |
| `warn` | `YELLOW_FONT_COLOR` | `Core.YELLOW` |

- **Zwei Grautöne:** `Core.GREY`/`Core.Grey` ist `9d9d9d` (Blizzards Qualität „Schlecht“), Blizzards `GRAY_FONT_COLOR` ist `808080`; `Core.Style.ColorText("gray", …)` nimmt im Spiel Blizzards Objekt. Quellen und Hinweise stehen in `Core.GREY`, die Rolle `gray` gilt für ausgegraute Zustände.
- Qualität: `Core.QualityRGB(q)` / `Core.QualityHex(q)` (Blizzards `ColorManager` bzw. `ITEM_QUALITY_COLORS`); Klassen: `RAID_CLASS_COLORS` bzw. `C_ClassColor`; Schwierigkeit: Blizzards Farben über ezCores Helfer.
- Eigene Palette: **nur** `Core.GLOW_COLORS`/`Core.GLOW_KINDS` (Leuchten; `Bausteine/Highlight.lua`) mit `Core.GlowColor`, `Core.GlowLabel`, Zeichen für Farbenblinde (`Core.MarkSign`).
- Rohe Farbcodes `|cffrrggbb` und Zahlen in `SetTextColor` außerhalb ezCores Format-Datei sind Abweichungen; Farben kommen über `Core.Green`, `Core.Red`, `Core.GREY` bzw. die Rollen. Farbcodes in Locale-Texten sind „niedrig“ (besser: Platzhalter und die Farbe im Code).
- Die Töne „passt“/„passt nicht“ in ezCores Item-Wissen und die Gildenbank-Zeile der Zählzeilen sind Blizzards Grün und Rot (Rollen `good`/`bad`; eine Stelle: `TONE_ROLE` in `ezCore/Bausteine/ItemTooltip.lua`).

### 2.6 Ebenen

Regel (`Core.Style.STRATA`, `Core.Style.SetStrata(rahmen, rolle)`):

| Rolle | Ebene | wofür | Beleg (Forever-Quelle) |
|---|---|---|---|
| `world` | LOW | Überlagerungen der Spielwelt (Anzeige über dem Charakter, Halter an Blizzards Leisten) | `Blizzard_UnitFrame/Mainline/PlayerFrame.xml` (`PlayerFrame frameStrata="LOW"`), `DockManagerTemplate` LOW |
| `hud` | MEDIUM | Leisten und Teile wie Blizzards Leisten, eigene Fenster wie Blizzards Fenster; Vorgabe jedes Rahmens unter `UIParent` | `Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.xml` (`ChatTabTemplate`, `ChatFrameMenuButton` MEDIUM), `Blizzard_MapCanvas/Blizzard_MapCanvas.xml` (MEDIUM), `ContainerFrameTemplate` MEDIUM |
| `dialog` | DIALOG | eigene Dialoge und Aufklappteile (Rückfrage, Textfeld, Lautstärke, Knopf-Sammlung) | `Blizzard_EditMode/Shared/EditModeManager.xml` (`EditModeManagerFrame` DIALOG), `BottomPopupScrollBoxTemplate` DIALOG |
| `parent` | Ebene des Elternrahmens | Teile an einem Blizzard-Fenster: als Kind des Fensters (erbt die Ebene); kann es kein Kind sein, übernimmt es die Ebene | – |

- Erlaubt ohne Eintrag: LOW, MEDIUM, DIALOG (`Core.Style.STRATA_RULE`). HIGH, TOOLTIP, FULLSCREEN, FULLSCREEN_DIALOG und BACKGROUND brauchen einen begründeten Eintrag in der Ausnahmeliste der Prüfung (Tabelle unten). Geprüft werden wörtliche Werte, Rückfälle in Ausdrücken (`… or "HIGH"`), Konstanten (`…STRATA = "HIGH"`) samt Verwendung und jeder Name im Ausdruck von `SetFrameStrata`, dem dieselbe Datei einen Ebenen-Namen als Text (`local s = "TOOLTIP"`) oder eine Tabelle mit Ebenen-Namen (`STRATA_UP[x]`) zuweist; jeder Wert zählt mit der Zeile der Verwendung. Grenze: Werte aus einer anderen Datei, aus Funktionswerten oder Parametern bleiben „dynamisch“ (Bericht „niedrig“), ebenso Felder (`t.s = "HIGH"`).
- MEDIUM ist erlaubt, weil Blizzards eigene Leisten, Chat-Knöpfe und Fenster dort liegen und jeder Rahmen ohne Angabe dort landet.
- Ausnahmen (alle geprüft und begründet):

| Datei | Ebene | Stand | Begründung |
|---|---|---|---|
| `ezBag/Render.lua` | TOOLTIP | ok | Zieh-Bild und Einfüge-Marke folgen dem Mauszeiger über allen Fenstern |
| `ezCore/Bausteine/Highlight.lua` | HIGH | ok | Rückfall, wenn die Ebene des Knopfs gesperrt ist: Leuchtrahmen folgt sonst dem Knopf |
| `ezCore/Bausteine/Mover.lua` | HIGH | ok | Auswahl im Bearbeitungsmodus liegt über den Teilen, die sie verschiebt (Teile bis MEDIUM) |
| `ezMap/MapButton.lua` | HIGH | ok | Knopf auf der Weltkarte über Blizzards Kartensymbolen wie Blizzards eigene Kartenknöpfe |
| `ezMap/MapCoords.lua` | HIGH | ok | über Blizzards Kartensymbolen (Rahmenstufen ab 2000, MapCanvas_PinFrameLevelsManager.lua) |
| `ezPanel/Blocks.lua` | TOOLTIP | ok | Zieh-Bild und Einfüge-Marke folgen dem Mauszeiger über allen Fenstern |
| `ezPanel/Blocks/Location.lua` | HIGH | ok | Koordinaten auf der Weltkarte wie ezMaps Zeile (über Blizzards Kartensymbolen) |

- Dynamisch und begründet: ezPanels Leiste nimmt die Ebene aus der Einstellung „Leiste über/unter anderen Fenstern“ des Spielers (unter „Erweitert“) (`ns.S.strata`). Ebenen, die einem Träger folgen (`GetFrameStrata` des Knopfs, des Chatfensters, des Ankers), erfüllen die Regel `parent`.

### 2.7 Tooltips

- Aufbau wie Blizzards Einstellungs- und Menü-Tooltips (`GameTooltip_SetTitle`, `GameTooltip_AddNormalLine`, `GameTooltip_AddInstructionLine` in `SharedTooltipTemplates.lua`): erste Zeile Titel in Weiß (`HIGHLIGHT_FONT_COLOR`; bei Gegenständen die Qualitätsfarbe), dann Beschreibung in Gold (`NORMAL_FONT_COLOR`, umbrechend), Werte als Doppelzeile (Beschriftung Gold, Wert Weiß), Klick- und Befehlshinweise grün (`GREEN_FONT_COLOR`, wie Blizzards Hinweiszeilen), Quellen und Hinweise grau. Die Helfer `Core.ShowTip`, `Core.Toolbar.Tip` und `Core.CompartmentHandlers` zeichnen dasselbe Format.
- **Zeilen in Rollen statt Zahlen:** `Core.TipTitle(tooltip, titel)`, `Core.TipText(tooltip, text)`, `Core.TipLine(tooltip, text, rolle, umbrechen)` (Rollen aus `Core.Style.COLOR`, dazu `"hint"` grau), `Core.TipDoubleLine`, `Core.TipClick(tooltip, text)` für Klick-Hinweise. Klick-Hinweise selbst über `Core.ClickText(taste, zusatz, text)` („Umschalt-Linksklick: alles nehmen“, 2.9). Anker über `Core.TipAnchor`, ganzer Tooltip über `Core.ShowTip`/`Core.TipScript`, im Menü `Core.Menu.Tip`.
- **Abschnitte in Blizzards Tooltips** (Gegenstand, Einheit, Objekt, Zauber): jeder Abschnitt eines Moduls beginnt mit ezCores einem Trenner `Core.Tooltip.Gap(tooltip, gruppe)` – eine Leerzeile, nie zwei, keine oben in einem leeren Tooltip; Abschnitte desselben Themas teilen eine Gruppe und stehen ohne Leerzeile untereinander. Kein eigenes `AddLine(" ")` in Abschnitten.
- **Quellenzeile:** jede Angabe, die nicht vom Client kommt, nennt ihre Quelle („laut Questie“, „bei dir 5×“) – grau in Klammern hinter dem Wert oder als letzte Zeile; nie ein leerer Tooltip ohne Erklärung.
- **Ausgeschaltete Knöpfe zeigen ihren Tooltip** samt Grund (`SetMotionScriptsWhileDisabled(true)` – wie Blizzards `PanelTabButtonTemplate motionScriptsWhileDisabled="true"`; in den Modulen über `Core.Toolbar.ShowTipWhileDisabled(knopf)` bzw. ezMacros `ns.UI.Button`); der Grund steht in der Rolle `hint` bzw. `bad`.
- Jede Einstellung hat `OPT_<key>_TIP`, jeder Knopf auf einer Einstellungsseite einen Tooltip (automatisch geprüft).

### 2.8 Zustände

| Zustand | Aussehen | Text |
|---|---|---|
| aus (Schalter oder Funktion aus) | Knopf `Disable()`, Schrift `off`/`hint` | Tooltip nennt, wo man es einschaltet |
| gesperrt im Kampf | Knopf aus, Tooltip zeigt den Grund; geschützte Aktionen werden nach dem Kampf nachgeholt. Meldung über `Core.CombatNotice(ns, was, art, opts)` im Chat des Moduls, mit `opts.center` zusätzlich in der Mitte (`opts.chat = false`: nur Mitte); derselbe Satz ohne Ausgabe für Tooltips und Gründe über `Core.CombatText(was, art)` | „<was> geht im Kampf nicht – bitte nach dem Kampf noch einmal.“ (`L.COMBAT_NOTICE_BLOCKED`, ohne was `L.SETTINGS_COMBAT_BLOCKED`) bzw. vorgemerkt „<was> kommt gleich nach dem Kampf.“ (`L.COMBAT_NOTICE_LATER`) |
| Hinweis in der Bildschirmmitte | `Core.ErrorMessage(text, "warn")` (gelb, Rolle aus `Core.Style`); ohne Farbe Blizzards Fehlerweg (rot); keine Farbzahlen | – |
| wartet auf Daten | Wert grau (`hint`), kein Fehler | „wartet auf Daten“ mit der Quelle, auf die gewartet wird |
| gesperrter Wert (Forever) | Wert unbesehen durchreichen (`Core.FormatSecret` u. a.), nie rechnen | `ns.SecretLine()` im Status (Gerüst `Core.NewModule`) |

- **Warntöne:** Ein Ton, der vor etwas warnt (seltener Gegner in ezMap, Chat-Alarm in ezChat, auslaufende Waffenverzauberung in ezCombat), spielt auf Blizzards Kanal „Master“ (`PlaySound(kit, "Master")`), damit er auch mit abgeschalteten Soundeffekten zu hören ist; abschaltbar bleibt er über den Schalter des Moduls. Klick-Töne (Häkchen, Reiter) bleiben auf Blizzards Standardkanal. Jede Stelle nennt die Regel im Kommentar.

### 2.9 Texte

- Deutsch und englisch; keine Pfeilzeichen „→“, „▸“, „►“ in Oberflächentexten, sondern „»“ bzw. `Core.ARROW` (automatisch geprüft).
- Ausnahme: Diagnose- und Probe-Berichte (Entwicklerwerkzeuge, nur mit `/ez debug`; etwa die Diagnose von `/ezchat diag` und die Notizen der Stationen der Daten-Probe) bleiben deutsch. Was ein Spieler ohne Entwicklerwerkzeug sieht – Hinweise, Tooltips, Fehlermeldungen, der Hinweis über einem Bericht (`PROBE_HINT`) –, bleibt zweisprachig.
- Einheiten nur über ezCores Helfer: `Core.Seconds`, `Core.Minutes`, `Core.Percent`, `Core.Money`/`Core.CoinText`, `Core.Plural`; Statusausgabe beginnt mit `ns.StatusHeader()`.
- Wortlaut wie Blizzard, wo Blizzard ihn hat (globale Texte wie `CHECK_ALL`, `UNCHECK_ALL`, `OKAY`, `CANCEL`, `CLOSE`, `DELETE`, `ACCEPT`), sonst ezCores gemeinsame Texte (`Core.L`), erst dann eigene. Standardwörter („Schließen“, „Abbrechen“, „Löschen“, „Übernehmen“) übersetzt kein Modul neu.
- **Klick-Hinweise:** Muster „<Taste>: <Wirkung>“, Zusatztasten wie Blizzards deutscher Client („Umschalt“, „Strg“, „Alt“ – nie „Shift“), verbunden mit „-“, „Linksklick:“, sobald es auch „Rechtsklick:“ gibt; gebaut über `Core.ClickText`. Nicht „Shift+Klick“, „Klicken:“ oder „Rechtsklick = …“.
- **Nutzen-Satz in Einstellungs-Tooltips:** deutsch „Das bringt dir:“, englisch „What you get:“ (`L.TIP_BENEFIT`).
- **Wege zu Einstellungen:** eine Form, gebaut über `Core.SettingsPathText(modul, abschnitt, option)` („Einstellung: Esc » Optionen » AddOns » ezCollection » ezGear » Erweitert » „Status“.“); zu Blizzards Tastaturbelegung `Core.KeyBindPathText(gruppe)`.
- **Befehle in Texten:** nie ein fester Kurzbefehl („/eb fenster“), sondern `%s` und `Core.SlashCmd(ns, rest)` – der Kurzbefehl gilt nur, wenn ihn kein anderes Addon belegt. Kurzbefehle stehen in einer Liste (`Core.SLASH_ALIASES`, ezCore/Kern/Slash.lua; /ezm ezMail, /ezmc ezMacro).
- **Glossar:** ein Begriff, ein Wortlaut.

| Sache | Wortlaut | nicht |
|---|---|---|
| Blizzards Fenster für Tasten | „Tastaturbelegung“ (Blizzards `KEY_BINDINGS`) | „Tastenbelegung“ (frei nur für ezMacros eigene „Tastenbelegung übernehmen“ eines Profils) |
| Auktionshaus | „Auktionshaus“ ausgeschrieben | „AH“ |
| die anderen eigenen Charaktere | „Twinks“ | „andere Charaktere“ (außer im Satz „alle Charaktere“, `L.ALL_CHARS`) |
| eigene Einstellungen eines Moduls | „Einstellungen“ | „Optionen“ (heißt nur Blizzards Fenster „Esc » Optionen“) |
| Einstellungen auf den Standard | „Einstellungen zurücksetzen“ (`page:ResetButton`, Befehl „zuruecksetzen“) | „Standard“, „Defaults“ |

### 2.10 Einstellungsseiten

- Aufbau: „Allgemein“ » Themen » „Erweitert“, gebaut über `Core.NewSettingsPage` (Blizzards Einstellungsfenster, `Blizzard_Settings_Shared`); Zurücksetzen und Verschieben unter „Erweitert“ (`page:ResetButton`, `page:MoverResetButton`).
- **„Profile“:** eigenes Thema direkt vor „Erweitert“ (`page:Profiles`, wie in ezBag, ezBars, ezGear, ezHeal, ezPanel), nicht unter „Erweitert“.
- **„Erweitert“ hat auf jeder Modulseite** den Knopf „Status“ (`page:StatusButton(tip)`, Beschriftung von ezCore) und „Einstellungen zurücksetzen“ mit Rückfrage (`page:ResetButton(opts)`) – nie selbst gebaut.
- **Befehle eines Moduls** (Gerüst `Core.NewModule`, opts.slash): ohne Wort = Linksklick im Addon-Fach (`main`, sonst Einstellungen), „optionen“/„einstellungen“/„config“, „status“, „hilfe“, mit `reset` auch „zuruecksetzen“/„reset“ (Rückfrage wie der Knopf); Hilfe in einer Form (Kopf und Standardzeilen aus ezCore, die eigenen Wörter in `L.CMD_HELP_OWN`; mit `main` sagt die zweite Zeile „/x – <mainText>“ und darunter „/x einstellungen – Einstellungen“). Befehlswörter vergleichen Umlaute als ae/oe/ue (`Core.SlashWord`), Schalter verstehen das englische Wort (`ns.TOGGLES`, Feld `en`).
- Gruppen von Kästchen derselben Art bekommen „Alle auswählen / Alle abwählen“ (2.11) über `page:AllToggle` (auf Einstellungsseiten weiter zwei Knopfzeilen).

### 2.11 Mehrfachauswahl: Haken „Alle“ (Menüs) bzw. „Alle auswählen“ / „Alle abwählen“ (Einstellungsseiten)

- **Regel:** Jede Mehrfachauswahl (Menü, Filter, Einstellungsbaum, Kästchen-Gruppe auf einer Einstellungsseite) mit mindestens drei Einträgen derselben Art bietet eine Sammel-Auswahl. **In Menüs** ist das seit dem 21.11.2026 EIN Haken „Alle“ (ezCores `L.ALL_TOGGLE`): angehakt, wenn alle Einträge an sind; ein Klick schaltet dann alle aus, sonst alle an. Gemischt steht er ohne Haken (Blizzards Menü-Haken kennen keinen Zustand „teilweise“), ein Klick schaltet dann alle an; lässt sich ein Eintrag nicht einschalten, schaltet der nächste Klick aus. **Auf Einstellungsseiten** bleiben zwei schlichte Knopfzeilen „Alle auswählen“ und „Alle abwählen“.
- **Wortlaut der Einstellungsseiten:** Blizzards eigene Texte zuerst – `CHECK_ALL` bzw. `UNCHECK_ALL` (Blizzards Menü „Aufspüren“ hat schon „Alle Auswählen“) –, sonst ezCores `L.ALL_CHECK` „Alle auswählen“ / „Check All“ und `L.ALL_UNCHECK` „Alle abwählen“ / „Uncheck All“ (`Core.Style.AllText(an)`). Achtung: Blizzards `UNCHECK_ALL` heißt im deutschen Client „Alle Auswählen“  – `Core.Style.AllText(false)` erkennt das und nimmt dann ezCores „Alle abwählen“; Module nehmen `UNCHECK_ALL` nie selbst als Text. Nie doppelt: hat Blizzards Teil einen der beiden Einträge schon, ergänzt das Modul nur den fehlenden.
- **Lage:** im Menü direkt unter der Überschrift der Gruppe, vor den einzelnen Haken (im Menü „Aufspüren“ an der Stelle von Blizzards „Alle abwählen“, das ezMap dafür ausblendet; nur die Darstellung, Blizzards Eintrag und Tabelle bleiben unberührt); auf der Einstellungsseite als zwei Knopfzeilen über den Kästchen der Gruppe.
- **Bausteine:** Menü `Core.Menu.AllToggle(root, liste, get, set, opts)` (ein Haken; mit `Core.Menu.SetAll` und `Core.Menu.AllOn`), Einstellungsseite `page:AllToggle(keys, opts)` (die zweite Zeile trägt ein Leerzeichen als Beschriftung: Blizzards Vorlage setzt einen Knopf ohne Beschriftung an den linken Rand, so steht „Alle abwählen“ unter „Alle auswählen“; Spielbefund vom 23.11.2026). Beide Zeilen tragen als Suchmarken die Beschriftung der Gruppe und ihren Knopftext (`page:Button` mit `opts.searchTags`), so zeigt Blizzards Suche beide Knöpfe.
- **Gruppen-Zustand** („teilweise“) wie in ezMaps Baum bleibt. Ein Auswahlfeld, das den Zustand einer Gruppe zeigt (ezMaps Einstellungsbaum), nennt den Zustand – „Alle an“, „Alle aus“, „Teilweise“ –, nicht die Handlungswörter „Alle auswählen“/„Alle abwählen“: sonst steht über lauter Haken „Alle abwählen“ (Spielbefund des Nutzers vom 19.11.2026). Die Handlungswörter gehören zu den beiden Knopfzeilen der Einstellungsseite.
- Keine Mehrfachauswahl im Sinn der Regel: Einstellungen verschiedener Art in einem Menü (ezMails Automatik-Schalter, ezCombats Meter-Optionen), Bedingungen eines Makros, die sich ausschließen (ezMacro Builder), und Einzel-Schalter.

### 2.12 Auswahl wird gemerkt

- Jede Auswahl, die ein Spieler setzt (Filter, Haken, Sortierung, Reiter, Gruppenzustand, Menü „Aufspüren“), steht nach `/reload` und beim nächsten Anmelden wieder so da – im SavedVariable des Moduls (je Charakter, wo sie vom Charakter abhängt), nicht nur im Speicher.
- Ausgenommen sind Auswahlen für eine einzelne Handlung (Briefe zum Öffnen markieren, Gegenstände zum Verkaufen markieren); sie enden mit der Handlung.
- Blizzards eigene Auswahl wird nicht überschrieben, sondern ergänzt: Merkt Blizzard etwas nicht (z. B. die Spuren im Menü „Aufspüren“), merkt das Modul es selbst und stellt es taint-sicher wieder her (etwa ezMap beim Menü „Aufspüren“).
