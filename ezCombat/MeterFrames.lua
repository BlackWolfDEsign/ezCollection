local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- Stufe 3: Schaden und Heilung an Blizzards Gruppen- und Raidrahmen (Wunsch des Nutzers vom 13.11.2026,
-- Entscheidungen im ROADMAP-Index: Teil von ezCombat; im Kampf Balken und Summe, Rang und Werte pro Sekunde nach
-- dem Kampf; zuerst nur die Rahmen). Der Abschnitt (aktueller Kampf, gesamt, früherer Kampf) ist wählbar – im
-- Zahnrad-Menü von Blizzards Schadensanzeige und in den Einstellungen (Abschnitt „Abschnitt der Balken“ unten).
--
-- Die Zahlen kommen nur aus Blizzards C_DamageMeter (Forever-Quelle, DamageMeterDocumentation) – ezCombat zählt
-- nichts selbst mit. Die Rahmen findet ezCores Dienst Core.GroupFrames (alle fünf Rahmen der Gruppe, auch der eigene,
-- und die Raidrahmen); je Rahmen hängen eigene, mausdurchlässige Halter. In Blizzards Rahmen wird nichts geschrieben.
--
-- Platz am Rahmen (Platzplan „Mittelband teilen“, Entscheidung des Nutzers vom 14.11.2026): Die Lage kommt aus
-- Core.GroupFrames.SLOTS, nicht von hier.
--   • Seit dem Spielbefund des Nutzers vom 18.11.2026 („buffs und co nicht in einem popup sondern über und an dem
--     rahmen, den abstand zu den rahmen untereinander beibehalten“; auf dem Bildschirmfoto hingen die Zeilen in der
--     Lücke zum nächsten Gruppenrahmen und „Platz n · x/s“ rechts daneben) liegt alles IM Rahmen, auch klassisch:
--     zwei Linien auf Blizzards Manabalken ohne Hintergrund (Platz "topLines", Dicke nach dem Regler „Höhe der
--     Balken“, 1–3 px), die Zahl in der kurzen Schreibweise auf dem Lebensbalken links neben ezHeals HoTs (Platz
--     "center", klassisch auch im Kampf) – dieselbe Darstellung wie im Raidstil. Die klassische Zeile mit Symbol,
--     Stern und Zahl am Zeilenende (unten) baut ezCombat nur noch, wenn ein Platz below nennt; das tut seitdem keiner.
--   • Bis zum 18.11.2026 – klassische Rahmen (Gruppe, Spieler; Spieltest des Nutzers vom 15.11.2026: „die balken sollten direkt unter dem
--     rahmen sein“, „woher soll der user wissen was ein balken bedeutet und wer wie gut ist? die höhe der balken ist
--     auch zu klein“; Befund vom 16.11.2026: „der "details" balken muss direkt unterkante zum eigenen rahmen sein
--     und abstand zum nächsten“): ein Streifen direkt an der sichtbaren Unterkante von Blizzards Rahmenbild (Platz
--     "topLines", below, art – nicht am Rechteck, dessen untere 14 px Blizzard für Auren und Begleiter frei hält),
--     mit Abstand zum nächsten Gruppenrahmen (reicht der Platz nicht, werden die Zeilen dünner), je Art eine Zeile –
--     links das Symbol der Art (Blizzards Rollensymbole: Schaden bzw. Heiler),
--     der Balken (Länge relativ zum Besten der Gruppe, Höhe nach dem Regler „Höhe der Balken“, mit Hintergrund) und
--     rechts direkt am Ende der Zeile Wert und Platz in der Farbe der Art (im Kampf die Summe, nach dem Kampf Platz und
--     Wert pro Sekunde, ohne Umbruch). Schaden oben, Heilung darunter. Der Erste je Art trägt nach dem Kampf einen
--     Stern (Blizzards Favoriten-Stern) – nur aus offenen Werten (MF.Ranking), im Kampf nie.
--   • Raidstil (bleibt, wie er ist): zwei Linien à 1 px in den zwei Pixelzeilen an der Oberkante, ohne Hintergrund
--     (der Regler macht sie nicht dicker – darunter beginnen Rollensymbol, Name und bannbare Debuffs); die Zahl am
--     Platz "center" (Mitte zwischen ezBuff und ezHeal, nur außerhalb des Kampfes und ab 30 px Rahmenhöhe) in der
--     kurzen Schreibweise.
--   • Seit dem Spieltest des Nutzers vom 20.11.2026 in einer Gruppe („wer soll die balken verstehen, warum sind die
--     zahlen nicht rechts vom balken?“; auf dem Bildschirmfoto stand „1 - 4…“ abgeschnitten im Lebensbalken des
--     Spielerrahmens, „2. - 1/s“ im Gruppenrahmen): klassisch stehen die Zahlen RECHTS NEBEN dem Rahmen auf Höhe der
--     Linien (Platz "beside" in Core.GroupFrames.SLOTS; der Abstand der Rahmen untereinander bleibt), ausgeschrieben
--     in Blizzards Schrift (MF.SIDE_FONT): nach dem Kampf „Platz 2 · 1,4 DPS“ bzw. „… HPS“, im Kampf die Summe mit
--     dem Namen der Art („12.345 Schaden“). Je Art eine Zeile, nie abgeschnitten (ein Anker, keine feste Breite).
--     Beim Überfahren erklärt ein Tooltip Linien und Zahlen samt Quelle (MF.ShowSideTooltip). Schalter
--     meterFramesNumbers („Zahlen an den Gruppenrahmen“): aus = nur die Linien. Raidstil: unverändert in der Mitte.
-- Erklärung (Leitlinie 11): Beim Überfahren eines Gruppenrahmens Zeilen in Blizzards Einheiten-Tooltip (über
-- Core.Tooltip.AddUnitSection, nur lesen) mit Platz, Wert pro Sekunde und Summe sowie der Quelle („laut Blizzards
-- Schadensanzeige, Abschnitt: …“); fest an, solange eine Art an den Rahmen an ist (Einstellungs-Prüfung 19.11.2026,
-- Nr. 36; bis dahin Schalter meterFramesTooltip).
--
-- Ursache der fehlenden orangen Linie im Spieltest vom 15.11.2026 (Aufgabe A, geprüft an Blizzards Forever-Quelle):
-- Die Ebene war es nicht – der alte Halter lag auf Rahmen + 3, die Linien auf Rahmen + 4, über ManaBar und
-- PartyMemberOverlay (je Rahmen + 1, PartyFrameTemplates.xml; PartyMemberFrame:SetFrameLevel(2)); und ShowLive setzt
-- den Balken für Schaden wie für Heilung (Prüfung in Tests/meter_frames.lua, auch mit gesperrtem session.maxAmount).
-- Die obere Linie (Schaden, 2 px bei y −38 bis −40) lag direkt auf dem unteren Rand von Blizzards Rahmenbild um den
-- Manabalken (UI-HUD-UnitFrame-Party-PortraitOn ab 1/−2), die untere (Heilung, −41 bis −43) schon darunter; 2 px Orange
-- über dem bronzenen Rand fallen nicht auf, Grün darunter schon. Darum liegen die Zeilen jetzt außerhalb von Blizzards
-- Rahmenbild, sind höher und tragen Symbol und Zahl. Belegt wird das im Spieltest (docs/roadmap/ezCombat.md).
--
-- Geheime Werte (Leitlinie 6): GetCombatSession…FromType ist „SecretWhenInCombat“. Jeder Wert geht zuerst durch
-- Core.IsSecret:
--   • im Kampf („live“): der Wert eines Mitglieds über GetCombatSessionSourceFromType(Aktuell, Art, GUID) und das
--     Maximum der Gruppe (session.maxAmount) gehen – ob gesperrt oder nicht – nur an Blizzards Balken (SetMinMaxValues,
--     SetValue) und als kurze Zahl an die Schrift (über Blizzards AbbreviateLargeNumbers). Nie verglichen, nie
--     gerechnet. Scheitert ein Schritt, bleibt die Zeile leer (nichts zeigen statt raten).
--   • nach dem Kampf („after“): die Liste der Sitzung, nur wenn jeder Wert offen ist – dann Rang und Wert pro Sekunde.
--     Ist sie noch gesperrt, bleibt es bei „live“, bis sie lesbar wird (Takt, Ereignisse des Schadensmessers, Ende der
--     Addon-Sperre).
-- Die GUID darf als Argument nicht gesperrt sein (SecretArguments „AllowedWhenUntainted“): ezCombat merkt sich die
-- GUIDs außerhalb des Kampfs; ändert sich die Gruppe im Kampf und sind die GUIDs dann gesperrt, gelten die gemerkten
-- als unsicher und die Zeilen bleiben leer.
--
-- Rücksicht (Leitlinie 9): Details liest dieselbe Quelle und zeigt nichts an Blizzards Rahmen – die Anzeige bleibt,
-- Tooltip und /ezk status nennen es. Ein Rahmen-Ersatz (HealBot, VuhDo, Grid2, Cell) blendet Blizzards Rahmen oft
-- aus: nur ein Hinweis, denn die Zahlen erscheinen nur an Blizzards Rahmen.
--
-- Top-3-Ansicht und weitere Arten (Frage des Nutzers vom 16.11.2026: „zeigt unser detail auch alle plätze am
-- entsprechenden rahmen an? oder gar einfach die ersten 3 ränge von demage, heal, aggro und co?“, Antwort auf
-- „Top-3-Ansicht und weitere Arten an die Rahmen bauen?“: „Ja, beides“): Darstellung wählbar (meterFramesView:
-- "rows" Zeilen wie bisher, "top3" nur Marken für Platz 1–3, "both"); weitere Arten aus Blizzards Schadensanzeige
-- (Unterbrechungen, Bannungen, Tode – MF.EXTRA_TYPES, je ein Schalter) und Aggro aus Blizzards Bedrohungs-Abfrage.
-- Die Marken baut MeterTop.lua; hier stehen die Arten, die Wahl der Darstellung und die Tooltip-Zeilen.
local MF = {}
ns.MeterFrames = MF

MF.PART = "meter"                 -- Schlüssel des Halters der Balken je Rahmen (Core.GroupFrames)
MF.TEXT_PART = "meterText"        -- Schlüssel des Halters der Zahlen je Rahmen (Platz center, seit 18.11.2026 auch klassisch)
MF.LINES_SLOT, MF.TEXT_SLOT = "topLines", "center"   -- Plätze in Core.GroupFrames.SLOTS
MF.TICK = 1                       -- Sekunden: Takt im Kampf und solange die Werte nach dem Kampf gesperrt sind
MF.PREVIEW_SECONDS = 5
MF.HEIGHT_KEY = "meterFramesHeight"     -- Regler „Höhe der Balken“ (Grenzen in ns.LIMITS, Core.lua)
-- Dicke eines Balkens ab Werk (vom 18. bis 20.11.2026: zwei 2-px-Linien auf Blizzards Manabalken, Regler bis 3 px).
-- Seit dem Spieltest vom 20.11.2026 wieder unter dem Rahmen: ab Werk 5 px, gekappt auf halbe Manabalken-Höhe (Platz
-- topLines: line – Gruppe 4 px, Spieler 5 px); mit „Nur, was deine Rolle betrifft“ ein Balken.
MF.BAR_HEIGHT, MF.GAP = 5, 1
MF.LINES_HEIGHT = MF.BAR_HEIGHT                -- ein Balken ab Werk (Vormerkung beim Laden; danach MF.LinesHeight)
MF.TEXT_HEIGHT = 10
MF.LEVEL = 3                      -- Ebene der Halter über Blizzards Rahmen, wo der Platz keine nennt (Raidstil)
MF.STAR_SIZE = 10
MF.ICON_MIN = 4                   -- kleiner wird das Symbol der Art nicht gezeigt (engster Platz, Review Welle 27)
MF.TOOLTIP_ORDER = 54             -- im Einheiten-Tooltip vor ezHeals Klick-Legende (55)
MF.SIDE_SLOT = "beside"           -- Platz rechts neben dem klassischen Rahmen (Spieltest 20.11.2026)
MF.SIDE_FONT = "GameFontNormalSmall"   -- Blizzards Schrift der Namen an Blizzards Gruppenrahmen
MF.SIDE_LINE = 12                 -- Zeilenhöhe der Zahlen neben dem Rahmen (zwei Zeilen im 24 px hohen Platz)
MF.SIDE_GAP = 6                   -- Abstand der Marken hinter den Zahlen neben dem Rahmen
MF.NUMBERS_KEY = "meterFramesNumbers"  -- Schalter „Zahlen an den Gruppenrahmen“ (aus: nur die Linien)
MF.BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- Stern für den Ersten je Art: Blizzards Favoriten-Stern (Auktionshaus bzw. Begleiter-Liste), sonst Blizzards
-- Ruf-Stern. Keine Zielmarkierung – Totenkopf und Stern der Zielmarkierungen stehen für markierte Gegner (die Deutung
-- „also totenkopf und co“ als Symbolwunsch war falsch: der Nutzer meinte damit die Zielmarkierungen im Rechtsklick-Menü).
MF.STAR = { atlas = { "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" }, file = "Interface\\Common\\ReputationStar",
    coords = { 0, 0.5, 0, 0.5 } }

-- Arten in fester Reihenfolge; Farben aus Blizzards Farbobjekten (Rückfall nur, wenn sie fehlen). Symbole: Blizzards
-- Schadensanzeige hat keine Symbole für die Arten (Blizzard_DamageMeter, Forever-Quelle: nur Klassen- und
-- Spezialisierungs-Symbole je Zeile) – darum Blizzards Rollensymbole Schaden und Heiler (Atlas der Rollen, sonst die
-- Datei der Rollen-Symbole mit Blizzards GetTexCoordsForRole), wie sie Gruppensuche und Gruppenrahmen zeigen.
MF.TYPES = {
    { key = "damage", setting = "meterFramesDamage", enumKey = "DamageDone", color = "ORANGE_FONT_COLOR",
        fallback = { 1, 0.5, 0.25 }, justify = "RIGHT",
        icon = { atlas = { "roleicon-tiny-dps", "UI-LFG-RoleIcon-DPS" },
            file = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", role = "DAMAGER" } },
    { key = "healing", setting = "meterFramesHealing", enumKey = "HealingDone", color = "GREEN_FONT_COLOR",
        fallback = { 0.1, 1, 0.1 }, justify = "LEFT",
        icon = { atlas = { "roleicon-tiny-healer", "UI-LFG-RoleIcon-Healer" },
            file = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", role = "HEALER" } },
}

-- Weitere Arten aus Blizzards Schadensanzeige (Enum.DamageMeterType, Forever-Quelle DamageMeterConstantsDocumentation:
-- Interrupts 5, Dispels 6, Deaths 9). Sie sind Zähler: kein Wert pro Sekunde (wie Blizzards Bericht, Meter.lua
-- CountsOnly) und keine Zeile mit Balken – sie erscheinen als Marke am Rahmen (MeterTop.lua) und im Tooltip. Tode
-- haben keinen Platz (noRank): Wer öfter stirbt, ist nicht „besser“ – die Marke zeigt die Zahl der Tode. Ab Werk aus
-- (Empfehlung der Hauptsession, umkehrbar). Symbole: Blizzards eigene Symbole (Tritt für Unterbrechen, Magie bannen,
-- Friedhof bzw. Schädel für Tode), Farben aus Blizzards Farbobjekten (Rollen in ezCore/Bausteine/Style.lua).
-- Eigene Liste statt MF.TYPES: Zeilen, Zusammenfassung nach dem Kampf (MeterSummary.lua) und Verlauf kennen nur
-- Schaden und Heilung.
MF.EXTRA_TYPES = {
    { key = "interrupts", setting = "meterFramesInterrupts", enumKey = "Interrupts", color = "LIGHTBLUE_FONT_COLOR",
        fallback = { 0.53, 0.67, 1 }, counts = true,
        icon = { file = "Interface\\Icons\\Ability_Kick" } },
    { key = "dispels", setting = "meterFramesDispels", enumKey = "Dispels", color = "YELLOW_FONT_COLOR",
        fallback = { 1, 1, 0 }, counts = true,
        icon = { file = "Interface\\Icons\\Spell_Holy_DispelMagic" } },
    { key = "deaths", setting = "meterFramesDeaths", enumKey = "Deaths", color = "GRAY_FONT_COLOR",
        fallback = { 0.5, 0.5, 0.5 }, counts = true, noRank = true,
        icon = { atlas = { "poi-graveyard-neutral" }, file = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" } },
}
-- Aggro: nicht aus der Schadensanzeige, sondern aus Blizzards Bedrohungs-Abfrage (MeterTop.lua). Symbol: Blizzards
-- Rollensymbol Tank (wer die Aggro hält), Farbe Rot wie Blizzards Aggro-Markierung.
MF.THREAT = { key = "threat", setting = "meterFramesThreat", color = "RED_FONT_COLOR", fallback = { 1, 0.1, 0.1 },
    icon = { atlas = { "roleicon-tiny-tank", "UI-LFG-RoleIcon-Tank" },
        file = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", role = "TANK" } }
-- Schalter der weiteren Arten in fester Reihenfolge (Einstellungen und Zahnrad-Menü)
MF.MORE_KEYS = { "meterFramesInterrupts", "meterFramesDispels", "meterFramesDeaths", "meterFramesThreat" }

-- Darstellung an den Rahmen: "rows" Zeilen an jedem Rahmen (Bestand), "top3" nur Marken für Platz 1–3, "both".
MF.VIEW_KEY = "meterFramesView"
function MF.View()
    local value = ns.S and ns.S[MF.VIEW_KEY]
    if value == "top3" or value == "both" then return value end
    return "rows"
end
function MF.ShowRows() return MF.View() ~= "top3" end
function MF.ShowTop() return MF.View() ~= "rows" end
function MF.ViewLabel(value) return L["OPT_meterFramesView_" .. tostring(value)] or tostring(value) end

local GF = Core.GroupFrames

-- Stehen die Zahlen an dieser Rahmenart neben dem Rahmen (Platz "beside": klassischer Gruppen- und Spielerrahmen)
-- oder in der Mitte (Raidstil: dort ist "beside" aus, die Rahmen stoßen aneinander)?
function MF.Side(kind)
    local spec = GF and GF.SlotSpec and GF.SlotSpec(kind or "raid", MF.SIDE_SLOT) or nil
    return spec ~= nil and not spec.off
end
function MF.TextSlot(kind) return MF.Side(kind) and MF.SIDE_SLOT or MF.TEXT_SLOT end
-- Breite einer Schrift neben dem Rahmen (Maus-Fläche MF.SideHover, Anfang der Marken MeterTop.Start – eine Fassung):
-- gemessen, sonst MF.CHAR_WIDTH je Zeichen; ein gesperrter Text (Summe im Kampf) wird nie gelesen oder gezählt – er
-- gilt als MF.SECRET_CHARS Zeichen lang (Leitlinie 6). → px
MF.CHAR_WIDTH, MF.SECRET_CHARS = 6, 8
function MF.TextWidth(fontString)
    local width = Core.Num(fontString:GetStringWidth())
    if width and width > 0 then return width end
    local text = fontString:GetText()
    if Core.IsSecret(text) then return MF.SECRET_CHARS * MF.CHAR_WIDTH end
    return (type(text) == "string" and #text or 0) * MF.CHAR_WIDTH
end
-- Zahlen an? (ab Werk an; nur ein ausdrückliches false schaltet sie ab)
function MF.NumbersOn() return not (ns.S ~= nil and ns.S[MF.NUMBERS_KEY] == false) end

-- Dicke eines Balkens nach dem Regler (in den Grenzen aus ns.LIMITS, 1–5 px; ein früher gespeicherter Wert darüber gilt
-- als 5).
function MF.BarHeight()
    local value = Core.Num(ns.S and ns.S[MF.HEIGHT_KEY]) or MF.BAR_HEIGHT
    local limit = ns.LIMITS and ns.LIMITS[MF.HEIGHT_KEY]
    if limit then value = math.max(limit[1], math.min(limit[2], value)) end
    return math.floor(value + 0.5)
end

-- Höhe des Streifens: so viele Zeilen, wie Arten an sind (mit „Nur, was deine Rolle betrifft“ eine), mit Abstand (der
-- Platz verkleinert sie im Raidstil auf seine 2 px, klassisch auf halbe Manabalken-Höhe).
function MF.LinesHeight()
    return MF.RowsHeight(MF.RowCount(), MF.BarHeight(), MF.GAP)
end
-- Höhe von rows Balken à line px mit gap px Abstand (eine Formel für Vormerkung, Dünnerwerden und Halter)
function MF.RowsHeight(rows, line, gap) return rows * line + (rows - 1) * gap end
-- Zahl der Balken je Rahmen: eingeschaltete Arten, mindestens 1
function MF.RowCount(types) return math.max(1, #(types or MF.ActiveTypes())) end

-- Plätze vormerken (beim Laden ab Werk; MF.ApplyHeight merkt die Höhe nach dem Regler neu vor).
if GF and GF.Reserve then
    GF.Reserve(ADDON, MF.LINES_SLOT, MF.PART, { size = { 0, MF.LINES_HEIGHT } })
    GF.Reserve(ADDON, MF.TEXT_SLOT, MF.TEXT_PART, { size = { 0, MF.TEXT_HEIGHT } })
end
local guids = {}                  -- Einheit → zuletzt offen gelesene GUID
local guidsTrusted = true         -- false: Gruppe änderte sich im Kampf, GUIDs gesperrt – gemerkte gelten nicht
local dirty, livePending = true, false
local rowKeys = nil               -- Arten der Zeilen beim letzten Vormerken der Höhe (MF.Update), z. B. "damage,healing"
local previewUntil = 0
local lastMode = nil              -- "live" | "after" | "secret" | "none" (für /ezk status)

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------

-- Wert vorhanden? Ein gesperrter Wert zählt als vorhanden und wird nie mit nil verglichen.
local function Present(value)
    if Core.IsSecret(value) then return true end
    return value ~= nil
end

local function Api()
    local api = rawget(_G, "C_DamageMeter")
    return type(api) == "table" and api or nil
end

-- Art der Sitzung im Client: "overall" → Gesamt, sonst Aktuell (Forever-Quelle DamageMeterConstantsDocumentation:
-- Overall 0, Current 1, Expired 2).
local function SessionType(key)
    local enum = Enum and Enum.DamageMeterSessionType
    if key == "overall" then return enum and enum.Overall or 0 end
    return enum and enum.Current or 1
end

local function MeterType(entry)
    local enum = Enum and Enum.DamageMeterType
    return enum and enum[entry.enumKey] or nil
end

local function Color(entry)
    local color = rawget(_G, entry.color)
    if type(color) == "table" and type(color.r) == "number" then return color.r, color.g, color.b end
    return entry.fallback[1], entry.fallback[2], entry.fallback[3]
end

function MF.Enabled(entry)
    return ns.S ~= nil and ns.S[entry.setting] == true
end

MF.MeterType, MF.Color = MeterType, Color

-- Nur, was den Spieler betrifft (Spieltest 20.11.2026: „heal etc muss es mir nicht anzeigen wenn ich selbst kein healer
-- bin ... angezeigt wird am rahmen nur, was den spieler betrifft“; Schalter meterFramesOwnRole, ab Werk an): als Heiler
-- Heilung, als Schaden oder Tank Schaden. Rolle aus ezCore (Core.PlayerRole: Gruppe, gesperrt die zuletzt offen
-- gelesene, sonst Spezialisierung). Unbekannt: wer nicht heilen kann (Core.PlayerCanHeal, Klasse), sieht Schaden; eine
-- Klasse, die heilen kann, sieht beides – der Tooltip neben dem Rahmen sagt es (Review 20.11.2026: nicht stumm raten).
-- Im Kampf gelten die Arten vom Kampfbeginn (frozen): ein Wechsel – auch eine im Kampf gesperrte Rolle – legte die
-- Balken sonst um, ohne dass sie neu gesetzt werden dürfen.
MF.ROLE_KEY = "meterFramesOwnRole"
function MF.OwnRoleOnly() return not (ns.S ~= nil and ns.S[MF.ROLE_KEY] == false) end
-- Art der Rolle: "healing" | "damage" | nil (unbekannt, beides)
function MF.RoleType(role)
    if role == nil and Core.PlayerRole then role = Core.PlayerRole() end
    if role == "HEALER" then return "healing" end
    if role ~= nil then return "damage" end
    local canHeal = Core.PlayerCanHeal and Core.PlayerCanHeal()
    if canHeal == false then return "damage" end
    return nil
end
local frozen = nil                -- { key = … } beim Kampfbeginn (MF.OwnType), nil außerhalb des Kampfes
function MF.OwnType()
    if frozen and ns.InCombat() then return frozen.key end
    return MF.RoleType()
end
function MF.FreezeRole(on) frozen = on and { key = MF.RoleType() } or nil end
-- Rolle unbekannt und darum beide Arten (Hinweis im Tooltip)?
function MF.RoleUnknown() return MF.OwnRoleOnly() and MF.OwnType() == nil end

-- Eingeschaltete Arten, für die der Client eine Art im Schadensmesser kennt (Zeilen: Schaden und Heilung) – mit
-- „Nur, was deine Rolle betrifft“ nur die der eigenen Rolle.
function MF.ActiveTypes()
    local list = {}
    local only = MF.OwnRoleOnly() and MF.OwnType() or nil
    for _, entry in ipairs(MF.TYPES) do
        if MF.Enabled(entry) and MeterType(entry) ~= nil and (only == nil or entry.key == only) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Eingeschaltete weitere Arten (Unterbrechungen, Bannungen, Tode), die der Client kennt.
function MF.ActiveExtras()
    local list = {}
    for _, entry in ipairs(MF.EXTRA_TYPES) do
        if MF.Enabled(entry) and MeterType(entry) ~= nil then list[#list + 1] = entry end
    end
    return list
end

-- Alle eingeschalteten Arten der Schadensanzeige: erst Schaden und Heilung, dann die weiteren.
function MF.ActiveKinds()
    local list = MF.ActiveTypes()
    for _, entry in ipairs(MF.ActiveExtras()) do list[#list + 1] = entry end
    return list
end

-- Kann der Spieler Blizzards Schadensmesser nutzen? → true | false, Grund
function MF.Available()
    local api = Api()
    if not api then return false, "missing" end
    if type(api.IsDamageMeterAvailable) ~= "function" then return true end
    local ok, available, reason = pcall(api.IsDamageMeterAvailable)
    if not ok then return false, "error" end
    if Core.IsSecret(available) then return true end          -- unbekannt: versuchen, die Werte sagen den Rest
    if available == false then
        local text = Core.Plain(reason)
        return false, type(text) == "string" and text ~= "" and text or "unavailable"
    end
    return true
end

---------------------------------------------------------------------------
-- Abschnitt der Balken (Entscheidung des Nutzers 13.11.2026: Abschnitt wählbar machen)
--
-- Was der Client kennt (Forever-Quelle, DamageMeterDocumentation und Blizzard_DamageMeter/DamageMeterSessionWindow):
--   • „Aktueller Kampf“ und „Gesamt“ über die Art (…FromType mit Current bzw. Overall),
--   • frühere Kämpfe über GetAvailableCombatSessions() → { sessionID, name, durationSeconds } und …FromID.
--   „Expired“ ist eine Art, die Blizzards eigene Auswahl nicht anbietet – hier auch nicht.
-- Einstellung: meterFramesSession = "current" | "overall" | "combat", dazu ezCombatDB.meterFramesSessionID (welcher
-- frühere Kampf, 0 = der neueste; kein eigenes Steuerelement, gewählt wird er im Zahnrad-Menü). Ist der gemerkte Kampf nicht mehr da (Zurücksetzen, neu geladen), gilt der neueste frühere, ohne
-- frühere Kämpfe der aktuelle. Ein früherer Kampf gilt bis zum nächsten Kampfbeginn, dann wieder die vorige Wahl
-- (aktuell oder gesamt) – sonst stünde im neuen Kampf ein alter an den Rahmen.
---------------------------------------------------------------------------

MF.SESSION_KEYS = { "current", "overall", "combat" }
local sessionBack = "current"     -- Wahl vor einem früheren Kampf (nur bis /reload gemerkt; MF.RememberChoice)

-- Die eine Stelle, die sich „aktueller Kampf“ bzw. „gesamt“ für die Rückkehr merkt: Jede Änderung der Einstellung
-- meterFramesSession kommt hier durch – über das Zahnrad-Menü (MF.SelectValue → ns.SetSetting) ebenso wie über das
-- Auswahlfeld der Einstellungen (Blizzards Einstellung meldet OnSettingChanged, unten). Vorher merkte nur das Menü
-- die Wahl: „Gesamt“ und dann „Früherer Kampf“ im Auswahlfeld ergab beim nächsten Kampf „Aktueller Kampf“.
-- → die gemerkte Wahl ("current" | "overall")
function MF.RememberChoice()
    local key = ns.S and ns.S.meterFramesSession
    if key == "current" or key == "overall" then sessionBack = key end
    return sessionBack
end

-- Wahl, zu der ein früherer Kampf beim nächsten Kampfbeginn zurückkehrt.
function MF.BackChoice() return sessionBack end

-- Gewählter Abschnitt → Auswahl ({ sessionType } oder { sessionID }), Schlüssel, Name, stale
-- (stale: der gemerkte frühere Kampf ist nicht mehr da, es gilt ein Ersatz).
function MF.Selector()
    local S = ns.S or {}
    local key = S.meterFramesSession
    local Meter = ns.Meter
    if key == "combat" then
        local want = Core.Num(ns.db and ns.db.meterFramesSessionID) or 0
        local list = Meter.CombatSessions()
        local found, stale = nil, false
        for _, combat in ipairs(list) do
            if want == 0 or combat.id == want then
                found = combat
                break
            end
        end
        if not found and list[1] then found, stale = list[1], true end
        if found then return { sessionID = found.id }, "combat", Meter.CombatName(found), stale end
        return { sessionType = SessionType("current") }, "current", Meter.SessionName(SessionType("current")), true
    end
    if key ~= "overall" then key = "current" end
    return { sessionType = SessionType(key) }, key, Meter.SessionName(SessionType(key)), false
end

-- Die Auswahl „aktueller Kampf“ (Zusammenfassung nach dem Kampf, MeterSummary.lua).
function MF.CurrentSelector() return { sessionType = SessionType("current") } end

-- Wert der Auswahl für Blizzards Menü: "current" | "overall" | "combat:<ID>"
function MF.ChoiceValue()
    local sel, key = MF.Selector()
    if key == "combat" and sel.sessionID then return "combat:" .. sel.sessionID end
    return key
end

-- Abschnitt wählen: "current", "overall" oder "combat:<ID>" (ohne ID: der neueste frühere Kampf).
function MF.SelectValue(value)
    if type(value) ~= "string" then return end
    local id = value:match("^combat:(%d+)$")
    local db = ns.db
    if id or value == "combat" then
        MF.RememberChoice()   -- die bisherige Wahl, bevor die Einstellung auf „combat“ springt
        if db then db.meterFramesSessionID = tonumber(id) or 0 end
        ns.SetSetting("meterFramesSession", "combat")
    else
        if db then db.meterFramesSessionID = 0 end
        ns.SetSetting("meterFramesSession", value == "overall" and "overall" or "current")
    end
    -- Gleiche Einstellung, anderer Kampf: neu zeichnen, auch wenn sich der Schalter selbst nicht änderte.
    ns.Try("MeterFrames", MF.Update)
end

-- Neuer Kampf: ein früherer Kampf an den Rahmen weicht der vorigen Wahl. → true, wenn umgestellt
function MF.LeaveCombatChoice()
    if not (ns.S and ns.S.meterFramesSession == "combat") then return false end
    MF.SelectValue(sessionBack)
    return true
end

-- Name eines festen Abschnitts für Einstellungen und Menü (Blizzards Texte, sonst eigene).
function MF.SessionLabel(key)
    if key == "combat" then return L.OPT_meterFramesSession_combat end
    return ns.Meter.SessionName(SessionType(key))
end

-- Einträge der Auswahl im Zahnrad-Menü: aktueller Kampf, gesamt, dann die früheren Kämpfe (neueste zuerst).
-- → { { value, text, tip } | { title = true, text } … }
function MF.ChoiceList()
    local list = {
        { value = "current", text = MF.SessionLabel("current"), tip = L.METER_FRAMES_SESSION_CURRENT_TIP },
        { value = "overall", text = MF.SessionLabel("overall"), tip = L.METER_FRAMES_SESSION_OVERALL_TIP },
    }
    local combats = ns.Meter.CombatSessions()
    list[#list + 1] = { title = true, text = #combats > 0 and L.METER_FRAMES_SESSION_EARLIER
        or L.METER_FRAMES_SESSION_NONE }
    for _, combat in ipairs(combats) do
        list[#list + 1] = { value = "combat:" .. combat.id, text = ns.Meter.CombatName(combat),
            tip = L.METER_FRAMES_SESSION_COMBAT_TIP }
    end
    return list
end

-- „Abschnitt: …“ (Tooltip und Status), mit Hinweis, wenn der gemerkte Kampf nicht mehr da ist.
function MF.SessionLine()
    local _, _, name, stale = MF.Selector()
    local line = L.METER_FRAMES_SESSION_CHOSEN:format(name)
    if stale then line = line .. " " .. L.METER_FRAMES_SESSION_STALE end
    return line
end

function MF.SessionTip()
    return L.OPT_meterFramesSession_TIP .. "\n\n" .. MF.SessionLine()
end

---------------------------------------------------------------------------
-- GUIDs der Mitglieder
---------------------------------------------------------------------------

-- Offene GUID der Einheit lesen und merken → guid | nil, gesperrt (true, wenn das Spiel sie sperrt).
-- Gibt es die Einheit nicht mehr (offen nil), wird die gemerkte vergessen.
local function ReadGUID(unit)
    if type(UnitGUID) ~= "function" then return nil, false end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil, false end
    if Core.IsSecret(guid) then return nil, true end
    if type(guid) ~= "string" then
        guids[unit] = nil
        return nil, false
    end
    guids[unit] = guid
    return guid, false
end

-- GUID für die Abfrage: offen gelesen, sonst die gemerkte (nur solange die Gruppe sich im Kampf nicht änderte).
function MF.GUID(unit)
    if unit == "player" and type(ns.playerGUID) == "string" and not Core.IsSecret(ns.playerGUID) then
        return ns.playerGUID
    end
    local guid = ReadGUID(unit)
    if guid then return guid end
    if guidsTrusted or unit == "player" then return guids[unit] end
    return nil
end

local function OnRoster()
    local secret = false
    local units = {}
    for unit in pairs(guids) do units[#units + 1] = unit end
    for _, unit in ipairs(units) do
        local _, locked = ReadGUID(unit)
        if locked and unit ~= "player" then secret = true end
    end
    if not ns.InCombat() then
        guidsTrusted = true
    elseif secret then
        guidsTrusted = false
    end
    dirty = true
end

---------------------------------------------------------------------------
-- Werte aus C_DamageMeter
---------------------------------------------------------------------------

-- Sitzung einer Art im gewählten Abschnitt (sel aus MF.Selector, ohne Angabe der gewählte):
-- Tabelle | nil, Grund ("missing", "error", "secret", "none").
function MF.Session(meterType, sel)
    sel = sel or MF.Selector()
    local api = Api()
    local fn, which
    if sel.sessionID then
        fn, which = api and api.GetCombatSessionFromID, sel.sessionID
    else
        fn, which = api and api.GetCombatSessionFromType, sel.sessionType
    end
    if type(fn) ~= "function" then return nil, "missing" end
    local ok, session = pcall(fn, which, meterType)
    if not ok then return nil, "error" end
    if Core.IsSecret(session) then return nil, "secret" end
    if type(session) ~= "table" then return nil, "none" end
    return session
end
local Session = MF.Session

-- Maximum der Gruppe im Kampf (darf gesperrt sein, geht nur an den Balken) oder nil.
function MF.LiveMax(meterType, sel)
    local session = Session(meterType, sel)
    if not session then return nil end
    local max = session.maxAmount
    if Core.IsSecret(max) or type(max) == "number" then return max end
    return nil
end

-- Summe eines Mitglieds im gewählten Abschnitt (darf gesperrt sein) oder nil.
function MF.LiveAmount(meterType, guid, sel)
    sel = sel or MF.Selector()
    local api = Api()
    if type(guid) ~= "string" or not api then return nil end
    local fn, which
    if sel.sessionID then
        fn, which = api.GetCombatSessionSourceFromID, sel.sessionID
    else
        fn, which = api.GetCombatSessionSourceFromType, sel.sessionType
    end
    if type(fn) ~= "function" then return nil end
    local ok, source = pcall(fn, which, meterType, guid)
    if not ok or Core.IsSecret(source) or type(source) ~= "table" then return nil end
    local amount = source.totalAmount
    if Core.IsSecret(amount) or type(amount) == "number" then return amount end
    return nil
end

-- Rangliste nach dem Kampf, nur aus offenen Werten: { byGUID, mine, max, count } | nil, Grund.
-- Gesperrt ist schon ein einziger gesperrter Wert in der Liste – dann gibt es keine Rangliste (nichts raten).
-- Gleichstand (Top-3-Ansicht, 16.11.2026): gleiche Summen teilen sich den Platz (1, 1, 3) – an Zeile, Stern, Marke
-- und Tooltip derselbe Platz; die Reihenfolge der Liste bleibt die von Blizzard.
function MF.Ranking(meterType, sel)
    local session, why = Session(meterType, sel)
    if not session then return nil, why end
    local sources = session.combatSources
    if Core.IsSecret(sources) then return nil, "secret" end
    if type(sources) ~= "table" then return nil, "none" end
    local list = {}
    for index, source in ipairs(sources) do
        if Core.IsSecret(source) or type(source) ~= "table" then return nil, "secret" end
        local total, rate, guid, me = source.totalAmount, source.amountPerSecond, source.sourceGUID, source.isLocalPlayer
        if Core.IsSecret(total) or Core.IsSecret(rate) or Core.IsSecret(guid) then return nil, "secret" end
        if type(total) == "number" and total > 0 then
            list[#list + 1] = { total = total, rate = type(rate) == "number" and rate or nil, index = index,
                guid = type(guid) == "string" and guid or nil, me = not Core.IsSecret(me) and me == true }
        end
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.index < b.index
    end)
    local ranking = { byGUID = {}, max = 0, count = #list, duration = Core.Num(session.durationSeconds) }
    for position, entry in ipairs(list) do
        local before = list[position - 1]
        entry.rank = (before and before.total == entry.total) and before.rank or position
        if entry.guid then ranking.byGUID[entry.guid] = entry end
        if entry.me then ranking.mine = entry end
        if entry.total > ranking.max then ranking.max = entry.total end
    end
    return ranking
end

---------------------------------------------------------------------------
-- Halter je Rahmen
---------------------------------------------------------------------------

-- Maße der Zeilen an einer Rahmenart: Höhe einer Zeile, Abstand, mit Hintergrund? Die Höhe kommt vom Regler
-- (MF.BarHeight); nennt der Platz eine Höchsthöhe (Core.GroupFrames.SLOTS: line, gap, plain), gilt sie – im Raidstil
-- zwei Linien à 1 px ohne Abstand und ohne Hintergrund, damit der Streifen weder Rollensymbol, Name und bannbare
-- Debuffs noch den Lebensbalken verdeckt. Klassische Rahmen (seit dem 20.11.2026 wieder unter dem Rahmenbild): je
-- Balken höchstens halb so hoch wie Blizzards Manabalken, 1 px Abstand, mit Hintergrund (Platz ohne plain).
-- depth (optional, GF.SlotDepth des Rahmens): so hoch darf der Streifen höchstens sein, damit unter ihm Abstand zum
-- nächsten Gruppenrahmen bleibt (Befund vom 16.11.2026) – dann werden die Balken dünner (mindestens 1 px). rows: Zahl
-- der Balken (ohne Angabe die eingeschalteten Arten; mit „Nur, was deine Rolle betrifft“ einer – der wird nur so weit
-- dünner, wie er allein muss, Review 20.11.2026). Reicht der Platz selbst dafür nicht (unter 3 px: Begleiter-Rahmen
-- und Leiter-Symbol am nächsten Rahmen), liegen die Balken à 1 px ohne Abstand aneinander – sie reichen dann bis zu
-- 2 px in den freien Abstand GF.SLOT_BELOW_GAP; in Blizzards engstem Fall (3 px bis zur Krone) bleibt 1 px frei
-- (Gegenprüfung Welle 27).
function MF.LineStyle(kind, depth, rows)
    rows = rows or MF.RowCount()
    local spec = GF and GF.SlotSpec and GF.SlotSpec(kind or "raid", MF.LINES_SLOT) or nil
    local want = MF.BarHeight()
    local line = spec and spec.line and math.min(spec.line, want) or want
    local gap = spec and spec.gap or MF.GAP
    if type(depth) == "number" and MF.RowsHeight(rows, line, gap) > depth then
        line = math.max(1, math.floor((depth - (rows - 1) * gap) / rows))
        if MF.RowsHeight(rows, line, gap) > depth then gap = 0 end
    end
    return line, gap, not (spec and spec.plain)
end

-- Alte Anordnung (Zeile mit Symbol, Balken, Zahl am Zeilenende unter dem Rahmen, bis zum 18.11.2026)? Der Platz sagt
-- es (classic – seit dem 20.11.2026 liegen die Balken wieder unter dem Rahmen, die Zahl aber steht am Platz beside;
-- classic nennt nur noch die Vorlage der Prüfungen).
function MF.Classic(kind)
    local spec = GF and GF.SlotSpec and GF.SlotSpec(kind or "raid", MF.LINES_SLOT) or nil
    return spec ~= nil and spec.classic == true
end

-- Ebene des Halters über Blizzards Rahmen: vom Platz, wenn er eine nennt (klassisch unter dem Rahmenbild seit dem
-- 20.11.2026: Rahmen + 1, unter Blizzards Aurensymbolen bzw. seiner Klassenleiste), sonst die eigene MF.LEVEL
-- (Raidstil).
function MF.Level(kind)
    local spec = GF and GF.SlotSpec and GF.SlotSpec(kind or "raid", MF.LINES_SLOT) or nil
    return spec and type(spec.level) == "number" and spec.level or MF.LEVEL
end

-- Schrift ohne Umbruch: eine Zeile, auch bei schmalem Platz (Spieltest 15.11.2026: „1. · 2/“ und darunter „s“).
local function NoWrap(fontString)
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(false) end
    if fontString.SetMaxLines then fontString:SetMaxLines(1) end
end
MF.NoWrap = NoWrap

-- Symbol der Art setzen: erster vorhandener Atlas, sonst die Datei (bei Rollen mit Blizzards Ausschnitt).
local function SetIcon(texture, icon)
    local atlas = icon.atlas and Core.FirstAtlas(icon.atlas)
    if atlas then
        texture:SetAtlas(atlas)
        return true
    end
    if not icon.file then return false end
    texture:SetTexture(icon.file)
    local coords = rawget(_G, "GetTexCoordsForRole")
    if icon.role then
        if type(coords) ~= "function" then return false end
        local ok, l, r, t, b = pcall(coords, icon.role)
        if not (ok and type(l) == "number" and type(b) == "number") then return false end
        texture:SetTexCoord(l, r, t, b)
    elseif icon.coords then
        texture:SetTexCoord(unpack(icon.coords))
    end
    return true
end
MF.SetIcon = SetIcon

-- Lage der Zeilen im Halter nach der Höhe vom Regler – beim Anlegen und nach jeder Änderung des Reglers.
-- Klassisch: Symbol links neben dem Balken, Zahl rechts direkt am Ende (Schaden: Schrift wächst von der Unterkante
-- seiner Zeile nach oben, Heilung von der Oberkante ihrer Zeile nach unten – zwei Zeilen untereinander ohne
-- Überlappung, in derselben Reihenfolge wie die Balken), Stern rechts neben der Zahl. Die Balken liegen auf der Ebene
-- des Halters (vom Platz: am Gruppenrahmen unter Blizzards Aurensymbolen, die von der Schadenszeile nur den Rand
-- decken). Ist der Platz bis zum nächsten Gruppenrahmen knapp (holder.depth), werden beide Zeilen dünner.
-- Raidstil: Zahl im Halter der Mitte (Heilung links, Schaden rechts, je bis zur Mitte).
-- Neben dem Rahmen (holder.side): je Art eine Zeile ab dem linken Rand des Halters, übereinander (MF.Stack).
local function SideY(index, count) return ((count + 1) / 2 - index) * MF.SIDE_LINE end

-- Zahlen neben dem Rahmen übereinander: die sichtbaren Zeilen in der Reihenfolge der Arten, zusammen mittig auf
-- Höhe der Linien (eine Zeile mittig, zwei je eine halbe Zeile darüber und darunter). Nach jedem Füllen.
local function Stack(holder)
    if not (holder and holder.side and holder.rows) then return end
    local shown = {}
    for _, entry in ipairs(MF.TYPES) do
        local row = holder.rows[entry.key]
        if row and row.text:IsShown() then shown[#shown + 1] = row end
    end
    for index, row in ipairs(shown) do
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.textHolder, "LEFT", 0, SideY(index, #shown))
    end
end
MF.Stack = Stack

local function Restyle(holder)
    local line, gap = MF.LineStyle(holder.kind, holder.depth)
    local level = holder.GetFrameLevel and holder:GetFrameLevel()
    local order, count = {}, 0
    for position, entry in ipairs(MF.ActiveTypes()) do order[entry.key], count = position, position end
    -- Streifen genau so hoch wie die Balken (die Vormerkung gilt für alle Rahmenarten, die Balken sind je Art
    -- gekappt – Gruppe 4 px, Spieler 5 px): so stehen die Zahlen daneben (beside, after) mittig auf ihrer Höhe.
    -- ezCore setzt beim Neusetzen (GF.Relayout) die Höhe des Platzes – darum läuft Restyle auch danach (MF.Holder).
    if not holder.classic then holder:SetHeight(MF.RowsHeight(math.max(1, count), line, gap)) end
    for _, row in pairs(holder.rows) do
        -- Reihenfolge der eingeschalteten Arten (mit nur einer Art steht sie oben, ohne Lücke darüber)
        local y = -((order[row.key] or row.index) - 1) * (line + gap)
        row.bar:ClearAllPoints()
        row.bar:SetHeight(line)
        row.bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
        row.bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, y)
        row.text:ClearAllPoints()
        if holder.classic then
            if type(level) == "number" and not Core.IsSecret(level) then row.bar:SetFrameLevel(level) end
            -- Symbol so hoch wie Zeile und Abstand; unter MF.ICON_MIN px wäre es nur ein Punkt (engster Platz:
            -- Begleiter-Rahmen und Krone am nächsten Rahmen) – dann bleibt es aus, Farbe, Zahl und Tooltip bleiben.
            -- Größer geht dort nicht: Blizzards Krone liegt links unter den Symbolen (x 42–58).
            local size = line + gap
            row.iconFits = size >= MF.ICON_MIN
            row.icon:SetSize(size, size)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("RIGHT", row.bar, "LEFT", -1, 0)
            if not row.iconFits then row.icon:Hide() end
            if row.index == 1 then
                row.text:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMRIGHT", 3, 0)
            else
                row.text:SetPoint("TOPLEFT", row.bar, "TOPRIGHT", 3, 0)
            end
            row.text:SetJustifyH("LEFT")
            row.star:SetSize(MF.STAR_SIZE, MF.STAR_SIZE)
            row.star:ClearAllPoints()
            row.star:SetPoint("LEFT", row.text, "RIGHT", 2, 0)
        elseif holder.side then
            -- ein Anker, keine Breite: die Zeile ist so lang wie ihr Text, nichts wird abgeschnitten
            row.text:SetPoint("LEFT", row.textHolder, "LEFT", 0, SideY(row.index, #MF.TYPES))
            row.text:SetJustifyH("LEFT")
        else
            local textHolder, outer = row.textHolder, row.justify
            row.text:SetPoint(outer, textHolder, outer, 0, 0)
            row.text:SetPoint(outer == "LEFT" and "RIGHT" or "LEFT", textHolder, "CENTER", 0, 0)
            row.text:SetJustifyH(outer)
        end
    end
    Stack(holder)   -- neben dem Rahmen: gleich die Lage der sichtbaren Zeilen (eine mittig, zwei übereinander)
end
MF.Restyle = Restyle

-- Je Art eine Zeile im Halter (oben die erste Art). Klassisch mit Symbol, Zahl und Stern im Halter selbst; im
-- Raidstil steht die Zahl im Halter der Zahlen (fehlt er, im Halter der Balken).
local function Build(holder, textHolder, kind)
    holder.rows = {}
    holder.kind = kind
    holder.classic = MF.Classic(kind)
    textHolder = (not holder.classic and textHolder) or holder
    holder.side = textHolder.side == true
    if holder.side then textHolder.linesHolder = holder end
    local font = holder.side and MF.SIDE_FONT or "NumberFontNormalSmall"
    local _, _, withBack = MF.LineStyle(kind)
    for index, entry in ipairs(MF.TYPES) do
        local r, g, b = Color(entry)
        local bar = CreateFrame("StatusBar", nil, holder)
        bar:SetStatusBarTexture(MF.BAR_TEXTURE)
        bar:SetStatusBarColor(r, g, b)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        local back
        if withBack then
            back = bar:CreateTexture(nil, "BACKGROUND")
            back:SetAllPoints(bar)
            back:SetColorTexture(0, 0, 0, 0.5)
        end
        local text = textHolder:CreateFontString(nil, "OVERLAY", font)
        text:SetTextColor(r, g, b)
        NoWrap(text)
        local row = { bar = bar, text = text, back = back, state = nil, index = index, key = entry.key,
            justify = entry.justify, textHolder = textHolder }
        if holder.side then
            -- Name der Art hinter der Summe im Kampf („12.345 Schaden“) – eigene Schrift, weil die Summe gesperrt
            -- sein kann (sie geht nur an SetText, wird nie mit Text verkettet)
            row.suffix = textHolder:CreateFontString(nil, "OVERLAY", font)
            row.suffix:SetTextColor(r, g, b)
            NoWrap(row.suffix)
            row.suffix:SetPoint("LEFT", text, "RIGHT", 0, 0)
            row.suffix:Hide()
        end
        if holder.classic then
            row.icon = holder:CreateTexture(nil, "ARTWORK")
            row.hasIcon = SetIcon(row.icon, entry.icon)
            row.star = holder:CreateTexture(nil, "OVERLAY")
            row.hasStar = SetIcon(row.star, MF.STAR)
            row.icon:Hide()
            row.star:Hide()
        end
        bar:Hide()
        text:Hide()
        holder.rows[entry.key] = row
    end
    Restyle(holder)
end

-- Halter eines Rahmens; außerhalb des Kampfs legt ezCore ihn an, im Kampf wartet er (nil). Die Lage kommt vom Platz
-- (Core.GroupFrames.Slot). Den Halter der Zahlen gibt es überall: im Raidstil in der Mitte (center), klassisch neben
-- dem Rahmen (beside, hinter den Balken). Nur in der Vorlage der Prüfungen (Platz mit classic, MF.Classic) steht die
-- Zahl am Ende ihrer Zeile – das tut kein Platz im Spiel.
-- Halter der Zahlen und Marken (einer je Rahmen, für Zeilen und Marken): klassisch neben dem Rahmen (Platz
-- "beside", nimmt die Maus für den Tooltip), im Raidstil in der Mitte (mausdurchlässig – dort erklärt Blizzards
-- Einheiten-Tooltip). Außerhalb des Kampfes legt ezCore ihn an, im Kampf nur den vorhandenen.
function MF.TextHolder(frame, kind)
    if not GF then return nil end
    local holder = GF.Part(ADDON, frame, MF.TEXT_PART)
    if holder or ns.InCombat() then return holder end
    kind = kind or GF.SlotKind(frame)
    local side = MF.Side(kind)
    return GF.Slot(ADDON, frame, MF.TextSlot(kind), MF.TEXT_PART, { level = MF.LEVEL,
        onCreate = side and function(own, blizzard) MF.SetupSide(own, blizzard) end or nil })
end

function MF.Holder(frame, kind)
    if not GF then return nil end
    local holder = GF.Part(ADDON, frame, MF.PART)
    if holder or ns.InCombat() then return holder end
    kind = kind or GF.SlotKind(frame)
    local textHolder
    if not MF.Classic(kind) then textHolder = MF.TextHolder(frame, kind) end
    holder = GF.Slot(ADDON, frame, MF.LINES_SLOT, MF.PART, { level = MF.Level(kind),
        onCreate = function(own) Build(own, textHolder, kind) end })
    -- Zahlen hinter den Balken (beside, after): erst jetzt gibt es die Balken, an denen sie hängen
    if holder and textHolder and textHolder.side then GF.Slot(ADDON, frame, MF.SIDE_SLOT, MF.TEXT_PART, { level = MF.LEVEL }) end
    if holder then
        -- nach jedem Setzen durch ezCore (auch GF.Relayout) Höhe und Lage der Balken neu (Review 20.11.2026)
        local place = GF.SlotAnchor and GF.SlotAnchor(ADDON, frame, MF.LINES_SLOT, MF.PART, function(region)
            if region.rows and not ns.InCombat() then Restyle(region) end
        end)
        if place then place(holder) end
        if GF.SlotClear then holder.clear = GF.SlotClear(frame, MF.LINES_SLOT) end
        if GF.SlotDepth then holder.depth = GF.SlotDepth(frame, MF.LINES_SLOT) end
        if holder.depth and holder.rows then Restyle(holder) end
    end
    return holder
end

-- Halter neu setzen (außerhalb des Kampfes): Höhe vom Regler, ein Begleiter-Rahmen kam bzw. ging oder der Platz
-- bis zum nächsten Gruppenrahmen hat sich geändert.
local function Replace(frame, kind)
    local holder = GF and GF.Part(ADDON, frame, MF.PART)
    if not (holder and holder.rows) or ns.InCombat() then return false end
    kind = holder.kind or kind or GF.SlotKind(frame)
    GF.Slot(ADDON, frame, MF.LINES_SLOT, MF.PART, { level = MF.Level(kind) })
    if GF.SlotClear then holder.clear = GF.SlotClear(frame, MF.LINES_SLOT) end
    if GF.SlotDepth then holder.depth = GF.SlotDepth(frame, MF.LINES_SLOT) end
    Restyle(holder)
    return true
end

-- Höhe der Zeilen nach dem Regler: Platz neu vormerken, alle Halter neu setzen (im Kampf nach dem Kampf – über ezCores
-- Warteschlange ns.AfterCombat mit dem Schlüssel HEIGHT_WAIT_KEY; Gesamtreview 18.11.2026, T16-13, vorher ein eigener Merker
-- heightPending und ein eigener PLAYER_REGEN_ENABLED-Zuhörer).
MF.HEIGHT_WAIT_KEY = "meterHeight"
local function ApplyHeightNow()
    for _, item in ipairs(GF.List()) do Replace(item.frame, item.kind) end
end
function MF.ApplyHeight()
    if not GF then return end
    if GF.Reserve then GF.Reserve(ADDON, MF.LINES_SLOT, MF.PART, { size = { 0, MF.LinesHeight() } }) end
    ns.AfterCombat(ApplyHeightNow, MF.HEIGHT_WAIT_KEY)
end
-- Wartet die Höhe noch auf das Kampfende? (Prüfungen, Refresh)
function MF.HeightPending()
    -- derselbe Schlüssel wie in ns.AfterCombat (Modulname des Gerüsts und Schlüssel)
    local key = tostring(ns.moduleName or ADDON) .. ":" .. MF.HEIGHT_WAIT_KEY
    return Core.AfterCombatWaiting and Core.AfterCombatWaiting(key) == true or false
end

-- Ist ein Begleiter-Rahmen gekommen oder gegangen (GF.SlotClear anders als beim Setzen) oder hat sich der Platz bis
-- zum nächsten Gruppenrahmen geändert (GF.SlotDepth: Mitglied kam oder ging, Leiter-Symbol)? Dann neu setzen. Läuft
-- aus MF.Update, also beim nächsten Takt nach UNIT_PET, Blizzards Schalter showPartyPets, Gruppen- oder
-- Leiterwechsel, Gestalt-, Spezialisierungs- oder Kraftwechsel des Spielers (unten angemeldet).
local function CheckClear(frame, kind)
    local holder = GF.Part(ADDON, frame, MF.PART)
    if not (holder and GF.SlotClear) or ns.InCombat() then return end
    local depth = GF.SlotDepth and GF.SlotDepth(frame, MF.LINES_SLOT) or nil
    if GF.SlotClear(frame, MF.LINES_SLOT) ~= (holder.clear or 0) or depth ~= holder.depth then Replace(frame, kind) end
end

-- Darf die Zahl an dieser Rahmenart gerade zu sehen sein? (Raidstil: nur außerhalb des Kampfes; neben dem Rahmen
-- immer)
function MF.TextAllowed(kind)
    if not ns.InCombat() then return true end
    return not (GF and GF.SlotInCombat) or GF.SlotInCombat(kind or "raid", MF.TextSlot(kind))
end

-- Zustand der Zeilen eines Rahmens (für /ezk status und die Prüfungen): { [art] = { mode, text, rank } }
function MF.State(frame)
    local holder = GF and GF.Part(ADDON, frame, MF.PART)
    if not (holder and holder.rows) then return nil end
    local out = {}
    for key, row in pairs(holder.rows) do out[key] = row.state end
    return out
end

local function HideRow(row)
    row.state = nil
    row.bar:Hide()
    row.text:Hide()
    if row.suffix then row.suffix:Hide() end
    if row.icon then row.icon:Hide() end
    if row.star then row.star:Hide() end
end

-- Name der Art hinter der Zahl neben dem Rahmen (im Kampf: „12.345 Schaden“); label nil oder Zahl verborgen: ohne.
local function SetSuffix(row, label)
    if not row.suffix then return end
    if label and row.text:IsShown() then
        row.suffix:SetText(" " .. label)
        row.suffix:Show()
    else
        row.suffix:Hide()
    end
end

-- Zeile zeigen: Balken (mit Hintergrund) und Symbol der Art; der Stern nur für den Ersten aus offenen Werten.
local function ShowRow(row, first)
    row.bar:Show()
    if row.icon then row.icon:SetShown(row.hasIcon == true and row.iconFits ~= false) end
    if row.star then row.star:SetShown(first == true and row.hasStar == true) end
end

-- Offene Werte: Balken und Text selbst setzen. Der Erste (rank 1) wird hervorgehoben – nach dem Kampf und in der
-- Vorschau, nie im Kampf (dort kommt nichts hier an: ShowLive vergleicht nichts).
local function ShowPlain(row, value, max, text, mode, rank)
    if not (Core.Num(value) and Core.Num(max)) then return HideRow(row) end
    row.bar:SetMinMaxValues(0, math.max(max, 1))
    row.bar:SetValue(value)
    local first = rank == 1 and (mode == "after" or mode == "preview")
    ShowRow(row, first)
    row.text:SetText(text)
    row.text:Show()
    if row.suffix then row.suffix:Hide() end    -- das Wort hinter der Summe gehört nur zum Kampf
    row.state = { mode = mode, text = text, rank = rank, first = first or nil }
end

-- Kurze Zahl für einen gesperrten Wert: nur über Blizzards Funktionen, die Ergebnisse gehen direkt an SetText.
local function SecretText(fontString, value)
    for _, name in ipairs({ "AbbreviateLargeNumbers", "AbbreviateNumbers" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" then
            local ok, text = pcall(fn, value)
            if ok and Present(text) and pcall(fontString.SetText, fontString, text) then return true end
        end
    end
    return false
end

-- Im Kampf: Werte nur durchreichen. value/max dürfen gesperrt sein. allowText false: die Zahl wird gesetzt, bleibt
-- aber verborgen (Raidstil im Kampf, Platzplan) – state.hidden sagt das.
-- Die Zeile bleibt zu sehen, auch wenn Blizzards Balken den Wert nicht nimmt (dann leer, state.empty) – Symbol, Zahl
-- und Hintergrund zeigen, dass es sie gibt.
local function ShowLive(row, value, max, allowText)
    if not Present(value) then return HideRow(row) end
    local secret = Core.IsSecret(value)
    local filled = false
    if Present(max) then
        filled = pcall(function()
            row.bar:SetMinMaxValues(0, max)
            row.bar:SetValue(value)
        end)
    end
    if not filled then
        pcall(row.bar.SetMinMaxValues, row.bar, 0, 1)
        pcall(row.bar.SetValue, row.bar, 0)
    end
    local textShown
    if secret then
        textShown = SecretText(row.text, value)
    else
        textShown = pcall(row.text.SetText, row.text, Core.ShortNumber(value))
    end
    if not (filled or textShown) then return HideRow(row) end
    ShowRow(row, false)
    row.text:SetShown(textShown and allowText ~= false)
    row.state = { mode = "live", text = secret and "secret" or row.text:GetText(), secret = secret,
        hidden = textShown and allowText == false or nil, empty = not filled or nil }
end

-- Platz und Wert pro Sekunde: kurz („3. · 3/s“) – die Mitte des Rahmens ist schmal, im Raidstil wie klassisch auf dem
-- Lebensbalken. Ausgeschrieben („Platz 3 · 3/s“) nur in der Vorlage „unter dem Rahmen“ (classic, MF.Classic), die
-- seit dem 18.11.2026 kein Platz nutzt.
local function AfterText(entry, classic)
    local rate = Core.Num(entry.rate)
    if rate and rate > 0 then
        return (classic and L.METER_FRAMES_PLACE_RATE or L.METER_FRAMES_RANK_RATE):format(entry.rank, MF.RateText(rate, true))
    end
    return (classic and L.METER_FRAMES_PLACE or L.METER_FRAMES_RANK):format(entry.rank)
end
MF.AfterText = AfterText

-- Wert pro Sekunde neben dem Rahmen: unter 100 mit einer Nachkommastelle („1,4“; Spieltest 20.11.2026: „1/s“ sagte
-- nichts), darüber kurz („1.234“, „12,3k“) – beides im Zahlformat der Spielsprache (Core.Decimal, Core.ShortNumber).
-- compact (kurze Zahl in der schmalen Mitte des Raidstils, Review 20.11.2026): die Nachkommastelle nur unter 10
-- („1,4/s“ statt „1/s“), darüber ganze Zahlen – sonst passte die Zahl dort kaum je (MF.TextFits).
function MF.RateText(rate, compact)
    rate = Core.Num(rate)
    if not rate then return "?" end
    if rate < (compact and 10 or 100) then return Core.Decimal(rate, 1) end
    return Core.ShortNumber(rate)
end

-- Ausgeschrieben neben dem Rahmen: „Platz 2 · 1,4 DPS“ bzw. „Platz 1 · 3,0 HPS“; ohne Wert pro Sekunde „Platz 2“.
function MF.SideText(key, entry)
    local rate = Core.Num(entry.rate)
    local format = L["METER_FRAMES_SIDE_" .. tostring(key)]
    if rate and rate > 0 and format then return format:format(entry.rank, MF.RateText(rate)) end
    return L.METER_FRAMES_PLACE:format(entry.rank)
end

-- Passt der Text in seine Hälfte des Halters der Zahlen? Jede Zahl reicht vom Rand bis zur Mitte des Halters
-- (Restyle). Klassisch neben vier HoTs ist der Halter nur rund 25 px breit (Gegenprüfung 18.11.2026) – dann steht
-- nach dem Kampf nur der Platz da, statt abgeschnitten zu werden. Unbekannte Breiten gelten als passend.
local function TextFits(row)
    local text, box = row.text, row.textHolder
    if not (box and type(text.GetStringWidth) == "function" and type(box.GetWidth) == "function") then return true end
    local okText, width = pcall(text.GetStringWidth, text)
    local okBox, room = pcall(box.GetWidth, box)
    if not (okText and okBox) or Core.IsSecret(width) or Core.IsSecret(room) then return true end
    if type(width) ~= "number" or type(room) ~= "number" or room <= 0 then return true end
    return width <= room / 2
end
MF.TextFits = TextFits

local function Fill(holder, unit, plan, kind)
    if not holder.rows then return end
    local numbers = MF.NumbersOn()
    local allowText = MF.TextAllowed(kind) and numbers
    for _, entry in ipairs(MF.TYPES) do
        local row, want = holder.rows[entry.key], plan[entry.key]
        if not want then
            HideRow(row)
        elseif want.mode == "after" then
            local guid = MF.GUID(unit)
            local found = guid and want.ranking.byGUID[guid] or nil
            if not found and unit == "player" then found = want.ranking.mine end
            if found then
                local text = holder.side and MF.SideText(entry.key, found) or AfterText(found, holder.classic)
                ShowPlain(row, found.total, want.ranking.max, text, "after", found.rank)
                if not holder.classic and not holder.side and row.state and not TextFits(row) then
                    local short = L.METER_FRAMES_RANK:format(found.rank)
                    row.text:SetText(short)
                    row.state.text, row.state.short = short, true
                end
                if not numbers and row.state then
                    row.text:Hide()
                    row.state.hidden = true
                end
            else
                HideRow(row)
            end
        elseif want.mode == "live" then
            local guid = MF.GUID(unit)
            ShowLive(row, guid and MF.LiveAmount(want.meterType, guid, want.sel) or nil, want.max, allowText)
            SetSuffix(row, holder.side and L["METER_FRAMES_SIDE_LIVE_" .. entry.key] or nil)
        else
            HideRow(row)
        end
    end
    Stack(holder)
end

-- Neben dem Rahmen nimmt der Halter die Maus (nur das Überfahren, Klicks gehen durch) nur, solange er etwas zeigt,
-- und nur so breit wie das Gezeigte – leer bleibt die Stelle neben dem Rahmen für die Spielwelt frei. Eigener
-- Rahmen, nicht geschützt: auch im Kampf erlaubt. → zeigt etwas?
-- Ohne verfolgten Rahmen (onRemove: Gruppe verlassen, Raidstil statt klassischer Rahmen – Blizzards Spielerrahmen
-- bleibt dann zu sehen) nimmt der Halter keine Maus mehr (Review 20.11.2026).
function MF.SideHover(textHolder)
    if not (textHolder and textHolder.side) then return false end
    local any, width = false, 0
    local tracked = GF and textHolder.blizzard and GF.Unit(textHolder.blizzard) ~= nil
    local lines = tracked and textHolder.linesHolder
    for _, row in pairs(lines and lines.rows or {}) do
        if row.text:IsShown() then
            any = true
            local w = MF.TextWidth(row.text)
            if row.suffix and row.suffix:IsShown() then w = w + MF.TextWidth(row.suffix) end
            if w > width then width = w end
        end
    end
    if tracked and textHolder.badgeState and #textHolder.badgeState > 0 then
        any = true
        width = math.max(width, (textHolder.badgeStart or 0) + (Core.Num(textHolder.badgeUsed) or 0))
    end
    pcall(textHolder.SetMouseMotionEnabled, textHolder, any)
    local full = Core.Num(textHolder:GetWidth())
    local cut = (any and full and width > 0 and width < full) and (full - width) or 0
    pcall(textHolder.SetHitRectInsets, textHolder, 0, cut, 0, 0)
    textHolder.hover, textHolder.hoverCut = any, cut
    if not any and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(textHolder) then GameTooltip:Hide() end
    return any
end

local function HideAll()
    if not GF then return end
    for _, item in ipairs(GF.List()) do
        local holder = GF.Part(ADDON, item.frame, MF.PART)
        if holder and holder.rows then
            for _, row in pairs(holder.rows) do HideRow(row) end
        end
        if MF.Top then MF.Top.Hide(item.frame) end
        MF.SideHover(GF.Part(ADDON, item.frame, MF.TEXT_PART))
    end
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

-- Plan je Art: im Kampf „live“, sonst die Rangliste; ist sie noch gesperrt, „live“ bis sie lesbar wird.
local function Plan(types)
    local plan, inCombat, pending, mode = {}, ns.InCombat(), false, "none"
    local sel = MF.Selector()
    for _, entry in ipairs(types) do
        local meterType = MeterType(entry)
        if inCombat then
            plan[entry.key] = { mode = "live", meterType = meterType, max = MF.LiveMax(meterType, sel), sel = sel }
            mode = "live"
        else
            local ranking, why = MF.Ranking(meterType, sel)
            if ranking then
                plan[entry.key] = { mode = "after", ranking = ranking }
                if mode ~= "secret" then mode = "after" end
            elseif why == "secret" then
                plan[entry.key] = { mode = "live", meterType = meterType, max = MF.LiveMax(meterType, sel), sel = sel }
                pending, mode = true, "secret"
            end
        end
    end
    return plan, inCombat or pending, mode
end

-- Zeilen (Darstellung „Zeilen“ oder „beides“) und Marken (MeterTop.lua: Top-3, weitere Arten, Aggro) getrennt:
-- Ohne Zeilen bleiben die Halter der Zeilen leer; die Marken kommen auch ohne Schadensanzeige (Aggro).
function MF.Update()
    dirty = false
    if GetTime() < previewUntil then return end
    local available = MF.Available()
    local active = MF.ActiveTypes()
    local types = MF.ShowRows() and active or {}
    -- Arten der Zeilen geändert (Rolle, Spezialisierung, Schalter – auch Schaden → Heilung bei gleicher Zahl): Höhe neu
    -- vormerken, Zeilen neu legen
    local keys = {}
    for _, entry in ipairs(active) do keys[#keys + 1] = entry.key end
    keys = table.concat(keys, ",")
    if keys ~= rowKeys then
        rowKeys = keys
        MF.ApplyHeight()
    end
    local top = MF.Top and MF.Top.Plan(available) or nil
    if not GF or ((#types == 0 or not available) and not (top and top.any)) then
        livePending, lastMode = false, available and "none" or "unavailable"
        HideAll()
        return
    end
    local plan, pending, mode = {}, false, available and "none" or "unavailable"
    if #types > 0 and available then plan, pending, mode = Plan(types) end
    livePending = pending or (top ~= nil and top.pending == true)
    lastMode = (#types > 0 and mode) or (top and top.mode) or mode
    if MF.HeightPending() and not ns.InCombat() then MF.ApplyHeight() end
    for _, item in ipairs(GF.List()) do
        local holder = MF.Holder(item.frame, item.kind)
        if holder then
            CheckClear(item.frame, item.kind)
            Fill(holder, item.unit, plan, item.kind)
        end
        if top then MF.Top.Fill(item, top, holder) end
        MF.SideShift(item.frame)
        MF.SideHover(GF.Part(ADDON, item.frame, MF.TEXT_PART))
    end
end

function MF.MarkDirty() dirty = true end

local function Tick()
    if dirty or livePending or ns.InCombat() then ns.Try("MeterFrames", MF.Update) end
end

---------------------------------------------------------------------------
-- Vorschau („Zeigen“): Beispielwerte an den Rahmen, die gerade da sind – erkennbar erfunden
---------------------------------------------------------------------------

function MF.Preview()
    if not GF then return false end
    local list = GF.List()
    if #list == 0 then return false end
    previewUntil = GetTime() + MF.PREVIEW_SECONDS
    local showRows = MF.ShowRows()        -- „Nur die ersten 3“: die Vorschau zeigt wie MF.Update keine Zeilen
    -- nur die Arten, die auch im Kampf stünden (Schalter, eigene Rolle; Review 20.11.2026)
    local shown = {}
    for _, entry in ipairs(MF.ActiveTypes()) do shown[entry.key] = true end
    for index, item in ipairs(list) do
        local holder = MF.Holder(item.frame, item.kind)
        if holder and holder.rows then
            for _, entry in ipairs(MF.TYPES) do
                local row = holder.rows[entry.key]
                if showRows and shown[entry.key] then
                    local sample = { rank = index, rate = 1000 * (#list - index + 1) }
                    local text = holder.side and MF.SideText(entry.key, sample) or AfterText(sample, holder.classic)
                    ShowPlain(row, #list - index + 1, #list, text, "preview", index)
                    if not MF.NumbersOn() then row.text:Hide() end
                else
                    HideRow(row)
                end
            end
            Stack(holder)
        end
        if MF.Top then MF.Top.Preview(item, index, holder) end
        MF.SideHover(GF.Part(ADDON, item.frame, MF.TEXT_PART))
    end
    C_Timer.After(MF.PREVIEW_SECONDS, function()
        previewUntil = 0
        ns.Try("MeterFrames", MF.Update)
    end)
    return true
end

---------------------------------------------------------------------------
-- Rücksicht, Tooltip, Status
---------------------------------------------------------------------------

function MF.OtherMeter() return (ns.OtherFor("damageMeter")) end
function MF.OtherFrames() return (ns.OtherFor("healFrames")) end

-- Tooltip eines Kästchens mit Hinweisen auf fremde Addons.
function MF.Tooltip(key)
    local tip = L["OPT_" .. key .. "_TIP"]
    local meter, frames = MF.OtherMeter(), MF.OtherFrames()
    if meter then tip = tip .. "\n\n" .. L.METER_FRAMES_DETAILS:format(meter) end
    if frames then tip = tip .. "\n\n" .. L.METER_FRAMES_REPLACED:format(frames) end
    local threat = key == "meterFramesThreat" and MF.Top and MF.Top.Other()
    if threat then tip = tip .. "\n\n" .. L.METER_FRAMES_THREAT_OTHER:format(threat) end
    return tip
end

function MF.Mode() return lastMode end

---------------------------------------------------------------------------
-- Erklärung im Einheiten-Tooltip (Leitlinie 11: jede Angabe nennt ihre Quelle)
---------------------------------------------------------------------------

-- Einheit, wenn der Tooltip zu einem Gruppen- oder Raidrahmen gehört (Besitzer oder dessen Eltern-Rahmen, z. B. der
-- Manabalken des klassischen Rahmens) – nur lesen. Seit Welle 23 (A5) ezCores GF.TooltipUnit (eine Fassung für ezHeal
-- und ezCombat); der Name bleibt als Weiterleitung und liefert nur die Einheit.
function MF.FrameUnit(tooltip)
    if not (GF and GF.TooltipUnit) then return nil end
    local unit = GF.TooltipUnit(tooltip)
    return unit
end

-- Zeilen für eine Einheit: { { text, r, g, b } … } – je Art Platz von wie vielen, Wert pro Sekunde und Summe (nur aus
-- offenen Werten), im Kampf mit offenen Werten nur die Summe; gesperrte Werte werden nie verglichen oder gezeigt
-- (eine Zeile sagt dann, dass das Spiel sie geheim hält). Zuletzt die Quelle mit dem gewählten Abschnitt.
-- Weitere Arten (Zähler, MF.EXTRA_TYPES): Platz von wie vielen und die Zahl, ohne Wert pro Sekunde; Tode nur die Zahl.
local function CountText(entry, label, found, ranking)
    if entry.noRank then return L.METER_FRAMES_TIP_COUNT:format(label, Core.FormatNumber(found.total)) end
    return L.METER_FRAMES_TIP_RANK_COUNT:format(label, found.rank, ranking.count, Core.FormatNumber(found.total))
end

function MF.TooltipLines(unit)
    local lines = {}
    if type(unit) ~= "string" or not MF.Available() then return lines end
    local sel, _, name = MF.Selector()
    local guid = MF.GUID(unit)
    local secret = false
    for _, entry in ipairs(MF.ActiveKinds()) do
        local meterType = MeterType(entry)
        local label = L["METER_FRAMES_KIND_" .. entry.key]
        local ranking = MF.Ranking(meterType, sel)
        local text
        if ranking then
            local found = guid and ranking.byGUID[guid] or nil
            if not found and unit == "player" then found = ranking.mine end
            if found and entry.counts then
                text = CountText(entry, label, found, ranking)
            elseif found then
                local rate = Core.Num(found.rate)
                if rate and rate > 0 then
                    text = L.METER_FRAMES_TIP_RANK_RATE:format(label, found.rank, ranking.count, MF.RateText(rate),
                        Core.ShortNumber(found.total))
                else
                    text = L.METER_FRAMES_TIP_RANK:format(label, found.rank, ranking.count, Core.ShortNumber(found.total))
                end
            else
                text = L.METER_FRAMES_TIP_NONE:format(label)
            end
        else
            local amount = guid and MF.LiveAmount(meterType, guid, sel) or nil
            if Core.IsSecret(amount) then
                secret = true
            elseif type(amount) == "number" and entry.counts then
                text = L.METER_FRAMES_TIP_COUNT:format(label, Core.FormatNumber(amount))
            elseif type(amount) == "number" then
                text = L.METER_FRAMES_TIP_TOTAL:format(label, Core.ShortNumber(amount))
            end
        end
        if text then
            local r, g, b = Color(entry)
            lines[#lines + 1] = { text = text, r = r, g = g, b = b }
        end
    end
    if secret then lines[#lines + 1] = { text = L.METER_FRAMES_TIP_SECRET, r = 0.6, g = 0.6, b = 0.6 } end
    if #lines > 0 then
        lines[#lines + 1] = { text = L.METER_FRAMES_TIP_SOURCE:format(tostring(name)), r = 0.6, g = 0.6, b = 0.6 }
    end
    return lines
end

-- Alle Zeilen einer Einheit: Schadensanzeige (MF.TooltipLines), dann Aggro (MeterTop.lua: eigene Quelle, eigene
-- Zeilen) – eine Fassung für den Einheiten-Tooltip und den Tooltip neben dem Rahmen.
function MF.UnitLines(unit)
    local lines = MF.TooltipLines(unit)
    if MF.Top then
        for _, line in ipairs(MF.Top.ThreatLines(unit)) do lines[#lines + 1] = line end
    end
    return lines
end

-- Abschnitt im Einheiten-Tooltip (Core.Tooltip.AddUnitSection): nur am Gruppen- bzw. Raidrahmen; Zeilen nur für die
-- eingeschalteten Arten (MF.ActiveKinds) – ohne Art bleibt der Abschnitt leer.
function MF.AddTooltip(tooltip)
    local unit = MF.FrameUnit(tooltip)
    if not unit then return 0 end
    local lines = MF.UnitLines(unit)
    -- ezCores einer Trenner (S-1811-Tooltipabstand, Spielbefund 18.11.2026): Leerzeile davor, nie zwei
    if #lines > 0 and Core.Tooltip and Core.Tooltip.Gap then Core.Tooltip.Gap(tooltip) end
    for _, line in ipairs(lines) do tooltip:AddLine(line.text, line.r, line.g, line.b, true) end
    return #lines
end

-- Tooltip beim Überfahren der Zahlen neben dem Rahmen (Spieltest 20.11.2026: „wer soll die balken verstehen“):
-- was Linien und Zahlen bedeuten, die Werte des Mitglieds mit ihrer Quelle (Leitlinie 11) und wo man sie abschaltet.
-- Blizzards Symbol „nicht da“ kam oder ging (GF.SlotShift anders als beim Setzen): Halter neben dem Rahmen außerhalb
-- des Kampfes neu setzen (im Kampf beim nächsten Update danach). → true, wenn neu gesetzt
function MF.SideShift(frame)
    local textHolder = GF and GF.Part(ADDON, frame, MF.TEXT_PART)
    if not (textHolder and textHolder.side and GF.SlotShift) or ns.InCombat() then return false end
    local shift = GF.SlotShift(frame, MF.SIDE_SLOT)
    if shift == (textHolder.shift or 0) then return false end
    GF.Slot(ADDON, frame, MF.SIDE_SLOT, MF.TEXT_PART, { level = MF.LEVEL })
    textHolder.shift = shift
    return true
end

function MF.ShowSideTooltip(self)
    local unit = GF and self and self.blizzard and GF.Unit(self.blizzard) or nil
    if type(unit) ~= "string" then return false end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.METER_FRAMES_HOVER_TITLE)
    Core.TipLine(GameTooltip, L.METER_FRAMES_HOVER_EXPLAIN, "highlight", true)
    if MF.RoleUnknown() then Core.TipLine(GameTooltip, L.METER_FRAMES_ROLE_UNKNOWN, "hint", true) end
    local lines = MF.UnitLines(unit)
    if #lines > 0 and Core.Tooltip and Core.Tooltip.Gap then Core.Tooltip.Gap(GameTooltip) end
    for _, line in ipairs(lines) do GameTooltip:AddLine(line.text, line.r, line.g, line.b, true) end
    Core.TipLine(GameTooltip, MF.HoverOptions(), "hint", true)
    GameTooltip:Show()
    return true
end

-- Aufbau des Halters neben dem Rahmen (einmal, außerhalb des Kampfes; ezCore legt ihn mausdurchlässig an): nur das
-- Überfahren nimmt er an – Klicks gehen weiter an die Spielwelt (SetMouseClickEnabled false); die Maus nimmt er erst,
-- wenn er etwas zeigt (MF.SideHover).
-- Wo man die Anzeige abschaltet: Weg zur Einstellung über ezCores Weg-Text (eine Quelle für Abschnitt und Schalter).
function MF.HoverOptions()
    return L.METER_FRAMES_HOVER_OPTIONS:format(ns.PathText("OPT_HEADER_METER", "OPT_" .. MF.NUMBERS_KEY))
end

function MF.SetupSide(own, blizzard)
    own.side, own.blizzard = true, blizzard
    own.shift = GF.SlotShift and GF.SlotShift(blizzard, MF.SIDE_SLOT) or 0
    -- Kommt oder geht Blizzards Symbol „nicht da“, beim nächsten Takt neu setzen (nur zuhören: HookScript, Leitlinie 5)
    local spec = GF.SlotSpec and GF.SlotSpec(GF.SlotKind(blizzard), MF.SIDE_SLOT)
    for path in pairs(spec and type(spec.shift) == "table" and spec.shift or {}) do
        local child = rawget(blizzard, path)
        if type(child) == "table" and type(child.HookScript) == "function" then
            pcall(child.HookScript, child, "OnShow", function() MF.MarkDirty() end)
            pcall(child.HookScript, child, "OnHide", function() MF.MarkDirty() end)
        end
    end
    pcall(own.SetMouseClickEnabled, own, false)
    pcall(own.SetMouseMotionEnabled, own, false)
    own:SetScript("OnEnter", MF.ShowSideTooltip)
    own:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

if Core.Tooltip and Core.Tooltip.AddUnitSection then
    Core.Tooltip.AddUnitSection("ezCombatMeterFrames", MF.TOOLTIP_ORDER, function(tooltip) MF.AddTooltip(tooltip) end, ADDON)
end

-- Darstellung und eingeschaltete Arten für /ezk status: „Darstellung: Nur die ersten 3; Arten: Schaden, Tode.“
function MF.ViewLine()
    local names = {}
    for _, entry in ipairs(MF.ActiveKinds()) do names[#names + 1] = L["METER_FRAMES_KIND_" .. entry.key] end
    return L.STATUS_METER_FRAMES_VIEW:format(MF.ViewLabel(MF.View()), table.concat(names, ", "))
end

function MF.StatusLine()
    if #MF.ActiveKinds() == 0 then
        local any = false
        for _, entry in ipairs(MF.TYPES) do any = any or MF.Enabled(entry) end
        for _, entry in ipairs(MF.EXTRA_TYPES) do any = any or MF.Enabled(entry) end
        return any and L.STATUS_METER_FRAMES_NOTYPE or nil
    end
    local available, reason = MF.Available()
    if not available then return L.STATUS_METER_FRAMES_UNAVAILABLE:format(tostring(reason)) end
    local count = GF and #GF.List() or 0
    local text = L["STATUS_METER_FRAMES_MODE_" .. string.upper(lastMode or "none")] or L.STATUS_METER_FRAMES_MODE_NONE
    local line = L.STATUS_METER_FRAMES:format(count, text) .. " " .. MF.SessionLine() .. " " .. MF.ViewLine()
    local meter, frames = MF.OtherMeter(), MF.OtherFrames()
    if meter then line = line .. " " .. L.METER_FRAMES_DETAILS:format(meter) end
    if frames then line = line .. " " .. L.METER_FRAMES_REPLACED:format(frames) end
    return line
end

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

local function Watch()
    if not GF then return end
    GF.Watch(ADDON, {
        onAdd = function(frame, unit, kind)
            ReadGUID(unit)
            MF.Holder(frame, kind)
            dirty = true
        end,
        onUnit = function(_, unit)
            ReadGUID(unit)
            dirty = true
        end,
        onRemove = function(frame)
            local holder = GF.Part(ADDON, frame, MF.PART)
            if holder and holder.rows then
                for _, row in pairs(holder.rows) do HideRow(row) end
            end
            if MF.Top then MF.Top.Hide(frame) end
            MF.SideHover(GF.Part(ADDON, frame, MF.TEXT_PART))   -- leer: keine Maus neben dem Rahmen
        end,
    })
end

local function Refresh() ns.Try("MeterFrames", MF.Update) end

ns.OnReady(function()
    MF.RememberChoice()
    MF.ApplyHeight()
    Watch()
    -- Takt mit Griff (ezCores Ticker-Helfer, Gesamtreview 18.11.2026, T7-3)
    MF.ticker = ns.Ticker(MF.TICK, Tick, nil, "MeterFrames.Tick")
    Refresh()
end)

for _, event in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET" }) do
    ns.On(event, function() dirty = true end)
end
-- Addon-Sperre des Spiels beginnt oder endet: Zahlen neu lesen (ezCore meldet es, CB-22).
ns.OnRestrictionChanged(function() dirty = true end)
ns.On("GROUP_ROSTER_UPDATE", OnRoster)
-- Begleiter kommt oder geht, Blizzards Schalter für Begleiter-Rahmen ändert sich: Blizzard zeigt den Begleiter-Rahmen
-- dann über UpdatePet, ohne die Gruppenrahmen neu zu setzen (Mainline/PartyMemberFrame.lua) – beim nächsten Takt prüft
-- CheckClear die Lage (außerhalb des Kampfes; im Kampf nach dem Kampf).
ns.OnUnit("UNIT_PET", { "party1", "party2", "party3", "party4" }, function() dirty = true end)
ns.On("CVAR_UPDATE", function(_, name) if name == "showPartyPets" then dirty = true end end)
-- Leiter wechselt: Blizzards Leiter-Symbol über dem nächsten Gruppenrahmen kommt oder geht (GF.SlotDepth)
ns.On("PARTY_LEADER_CHANGED", function() dirty = true end)
-- Rolle in der Gruppe ändert sich (Schalter „Nur, was deine Rolle betrifft“): Zeilen neu
ns.On("PLAYER_ROLES_ASSIGNED", function() dirty = true end)
-- Gestalt, Spezialisierung oder Kraftart des Spielers wechselt: Blizzard zeigt oder verbirgt dann seine Klassenleiste
-- (Combo-Punkte, Runen …) bzw. die zweite Kraftleiste unter dem Spielerrahmen (GF.SlotClear: clearBelow, clear)
ns.On("UPDATE_SHAPESHIFT_FORM", function() dirty = true end)
ns.On("PLAYER_SPECIALIZATION_CHANGED", function() dirty = true end)
ns.OnUnit("UNIT_DISPLAYPOWER", "player", function() dirty = true end)
ns.On("PLAYER_REGEN_DISABLED", function()
    -- neuer Kampf: Rang und Werte pro Sekunde des vorigen gelten nicht mehr; ein früherer Kampf weicht der vorigen Wahl
    MF.FreezeRole(true)               -- Arten vom Kampfbeginn (MF.OwnType)
    MF.LeaveCombatChoice()
    HideAll()
    dirty = true
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    guidsTrusted = true
    MF.FreezeRole(false)
    if MF.HeightPending() then MF.ApplyHeight() end   -- ezCores Warteschlange läuft evtl. erst nach diesem Zuhörer
    Refresh()
end)

ns.OnSettingChanged(function(key)
    if key == "meterFramesSession" then MF.RememberChoice() end
    if key == MF.HEIGHT_KEY then
        MF.ApplyHeight()
        Refresh()
    end
    if key == "meterFramesDamage" or key == "meterFramesHealing" or key == "meterFramesSession"
        or key == MF.VIEW_KEY or key == MF.NUMBERS_KEY or key == MF.ROLE_KEY then
        Refresh()
    end
    for _, more in ipairs(MF.MORE_KEYS) do
        if key == more then Refresh() end
    end
end)

ns.AddPreview("meterFrames", 95, MF.Preview)
ns.AddStatusLine(MF.StatusLine)
