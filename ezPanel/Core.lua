local ADDON, ns = ...
local L = ns.L

--[[
    ezPanel – Info-Leiste im Originalstil von WoW Forever.

    Aufbau:
      Core.lua     Helfer, Ereignisse, Datenbank, Charakterdaten, Slash-Befehle
      Bar.lua      die Leiste (oben), Hintergrund, Ausblenden, Spielwelt-Platz
      TopSpace.lua Platz oben: Blizzards Fenster am oberen Rand rücken unter die Leiste
      Blocks.lua   Bausteine: Anzeige, Anordnung, Ziehen, Tooltip, Rechtsklick-Menü
      Blocks\*.lua die einzelnen Bausteine (Gold, XP, Uhr, …)
      Import.lua   einmalige Übernahme der Titan-Panel-Einstellungen
      Options.lua  Einstellungen unter Esc → Optionen → AddOns → ezPanel

    Keine geschützten Frames: ezPanel legt sich über den Bildschirm. Blizzards
    Fenster am oberen Rand rücken nur taint-sicher und abschaltbar unter die
    Leiste (TopSpace.lua); die Spielwelt verkleinert Bar.lua auf Wunsch.
]]

ns.DEFAULTS = {
    topBar = true,
    skin = "title",
    alpha = 1,
    fontSize = 10,
    scale = 1,
    spacing = 16,
    strata = "MEDIUM",
    autoHideTop = false,
    hideInCombat = false,
    -- Blizzards Fenster oben rücken unter die Leiste (TopSpace.lua). Ab Werk aus, „Allem zustimmen“ schaltet es ein
    -- (Intro.CONSENT; Entscheidung des Nutzers vom 21.11.2026, wörtlich „ja die 3 default aus: mit "allem einverstanden" an aus bleibt aber Zeichen am Leuchten“). Gespeicherte Werte
    -- bleiben: ezCores Gerüst schreibt den Standard beim Laden in ezPanelDB.settings (Core.FillDefaults) – wer ezPanel
    -- schon hatte, hat „an“ gespeichert und behält es; nur neue Installationen starten aus
    reserveTop = false,
    viewport = false,
    locked = false,
    tooltipsInCombat = true,
    moneyStyle = "coins",
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
ns.AGREE = {
    viewport = "choice", autoHideTop = "choice", hideInCombat = "choice", locked = "choice",
}

-- Reihenfolge für Slash-Befehle (Schlüssel, deutscher Befehl).
-- en: englisches Wort (Gesamtreview T10-1; nie die Kennung eines Bausteins – Schalter gehen vor Bausteinen)
ns.TOGGLES = {
    { "topBar", "leiste", en = "bar" },
    { "autoHideTop", "auto", en = "autohide" },
    { "hideInCombat", "kampf", en = "hideincombat" },
    { "reserveTop", "oben", en = "top" },
    { "viewport", "platz", en = "viewport" },
    { "locked", "sperren", en = "lock" },
}

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore
-- Print, Error, On, OnReady, OnSettingChanged, SettingChanged, SetSetting, AfterCombat, AddStatusLine …
-- Dazu ezCores Gerüst (Framework.lua): Datenbank beim ADDON_LOADED (Standardwerte mit Typprüfung), die Befehle
-- /ezpanel und /ep mit „optionen“, „status“, „hilfe“ und den Schaltern aus ns.TOGGLES; die eigenen Wörter
-- (Bausteine, titan, chars …) laufen über ns.SlashExtra weiter unten. Fehlt dem installierten ezCore einer
-- der genannten Dienste, meldet ezCore das einmal im Chat und ezPanel bleibt still (statt nil-Fehlern).
-- core: die ezCore-Fassung, die beim Start der Welle 5 in main stand. Einzelne Helfer stehen zusätzlich in needs –
-- frühe Stände einer Fassung hatten sie noch nicht (UnitHealthText/UnitPowerText für „Regeneration“, W-03;
-- BagSpaceOf für die Taschenplätze der Twinks, PANEL-08; seit Welle 7 die Dienste aus Welle 6: Sitzung, Ruf,
-- Reparieren, Export-Filter und Profil-Abschnitt – PANEL-02/03/04/09).
Core.NewModule(ADDON, ns, {
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.XPBlocked, Core.Durability.ReportText, Core.SwitchCVar, Core.ItemIconText
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    needs = { "AfterCombat", "OpenPanel", "OpenChatWith", "ItemCount", "ForEachBagItem", "Lockouts.List",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Reparatur-Meldung (T16-12), Ersatzsymbol (T16-NM6)
        "Durability.ReportText", "ICON_FALLBACK",
        "Currencies.Known", "ItemLevelOf", "LastFaction", "UnitHealthText", "UnitPowerText", "scaffoldHelpers",
        "InInstance", "BagList", "ItemClass", "PlayerClass", "PlayerLevel", "SkillLines", "BagSpaceOf",
        "DateText", "SetCVar", "Session.Data", "Session.Reset", "Factions.Info", "Factions.Watched",
        "Factions.Known", "Factions.Remember", "Durability.RepairAll", "ColorCode", "Style.Color", "Style.AllText",
        "Menu.AllToggle",
        -- Welle 15: Bausteine „Sammeln“ und „Auktionen“ (SAM-26, AH-34; nachgetragen in Welle 23)
        "Gathering.SessionStats", "History.AuctionMail",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 26 (ezCore-Paket kern/ezcore-reste-24, ohne neue Nummer): Geld-Spalte „money“ (Core.GoldDecimal)
        "GoldDecimal",
        -- Gesamtreview 18.11.2026 (P14): Baustein „Kampf“ schaltet im Kampf nicht um (ohne neue Versionsnummer)
        "SwitchCVar",
        -- Gesamtreview 18.11.2026 (P13 Teil D2): Addon-Fach, Hilfe, Zurücksetzen, Klick-Hinweise, Kampfsperre, Menüeintrag
        "compartmentMain", "slashMain", "SlashCmd", "SlashReset", "ClickText", "CombatNotice", "Menu.Settings",
        -- Gesamtreview 18.11.2026 (T9-6): Tooltip-Zeilen in Rollen
        "TipLine", "TipDoubleLine",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "ICON_FALLBACK", "QualityText", "XPBlocked",
    -- Einstellungs-Prüfung 19.11.2026 (ezCore ohne neue Versionsnummer): gemeinsamer Schaltersatz „Automatisch reparieren“
    "SharedOn", "SetShared", "Junk.RepairSettings", "Junk.AdoptPanelRepair", "Junk.RepairMixedOff", "Junk.RepairPathText",
    -- 20.11.2026 (ohne neue Versionsnummer): „Im Auktionshaus Wertvolles behalten“ als eine Stelle in ezCore
    "Junk.MerchantKeeps", "Junk.ShowKept" },
    db = "ezPanelDB",
    tables = { "blocks", "tour" },   -- blocks: je Baustein an/aus, Bereich, Reihenfolge, Optionen; tour: gesehene Erklärblasen
    onLoad = function(db)
        -- Alte Werte: Goldrand (Classic) und „blizzard“ (Tooltip, früherer Standard) → Titelstreifen.
        if db.settings.skin == "gold" or db.settings.skin == "blizzard" then
            db.settings.skin, db.settings.alpha = "title", 1   -- der Titelstreifen ist im Original deckend
        end
        db.settings.bottomBar, db.settings.autoHideBottom = nil, nil   -- untere Leiste entfällt
        -- Charakterdaten liegen seit ezCore in ezCoreDB.chars; db.chars bleibt als Sicherung liegen.
    end,
    slash = {
        key = "EZPANEL", commands = { "/ezpanel" },
        alias = "/ep",   -- nur, wenn kein anderes Addon es schon belegt (Prüfung in ezCore)
        extra = function(cmd, rest, input) return ns.SlashExtra(cmd, rest, input) end,
    },
})

-- ns.IsSecret, ns.Num, ns.Plain, ns.InCombat, ns.IsLoaded und ns.OtherFor(funktion) setzt das Gerüst (Core.NewModule,
-- scaffoldHelpers); die eigenen Verweise darauf sind in Welle 4 entfallen (UE-07).
ns.LoadAddOn = Core.LoadAddOn
ns.CVar = Core.CVar
ns.SetCVar = Core.SetCVar
ns.Round = Core.Round
ns.Number = Core.FormatNumber          -- 12345 → „12.345“
ns.Short = Core.ShortNumber            -- große Zahlen kurz: 1,2k / 3,4 Mio.
ns.Percent = Core.Percent
ns.Duration = Core.Duration
ns.Ago = Core.Ago
ns.ClassColor = Core.ClassColor
ns.ClassText = Core.ClassText
ns.Gradient = Core.Gradient

-- Kupfer als Text im gewählten Stil (Einstellung moneyStyle: coins, gold, text).
function ns.Money(copper, style, colorNegative)
    return Core.Money(copper, style or (ns.S and ns.S.moneyStyle) or "coins", colorNegative)
end

---------------------------------------------------------------------------
-- Optik: immer der eigene Stil von WoW Forever
---------------------------------------------------------------------------

--[[
    ezCore: WoW Forever hat die Retail-Oberfläche. ezPanel nutzt deshalb nur die
    Vorlagen und Atlanten des Clients selbst (NineSlice-Layouts, Atlanten,
    Blizzard-Templates) – nie ClassicUI-Optik oder alte Classic-Texturdateien.
    Fehlt etwas auf einem Client, gibt es einen schlichten Ersatz, keinen fremden Stil.
]]

ns.AtlasExists = Core.AtlasExists
ns.FirstAtlas = Core.FirstAtlas   -- erster vorhandener Atlas aus einer Liste

-- Hintergrund genau wie die Tooltips des Clients (NineSlice „TooltipDefaultLayout“).
function ns.CreateTooltipBackground(parent)
    local layout = NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout("TooltipDefaultLayout")
    if layout then
        local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "NineSlicePanelTemplate")
        if ok and frame then
            NineSliceUtil.ApplyLayout(frame, layout)
            frame.ezEdge = 6
            return frame
        end
    end
    local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "TooltipBackdropTemplate")
    if ok and frame then
        frame.ezEdge = 5
        return frame
    end
    -- Letzter Ersatz: schlichte dunkle Fläche ohne Rand.
    frame = CreateFrame("Frame", nil, parent)
    frame.ezFill = frame:CreateTexture(nil, "BACKGROUND")
    frame.ezFill:SetAllPoints()
    frame.ezEdge = 0
    return frame
end

-- Titelstreifen der Client-Fenster (Optionen, Kombinierter Rucksack): oberer Rand
-- des NineSlice-Layouts „ButtonFrameTemplateNoPortrait“, Atlas „_UI-Frame-Metal-EdgeTop“.
-- Der Client wählt dafür je nach Spiel eine eigene Grafik. Wo darin der deckende
-- Streifen liegt, ist an den Texturen gemessen (Zeilen von oben, ohne Schatten):
--   WoW Forever, „c60“-Grafik (Datei 8069118, 190 Zeilen): 26–81, Goldkante oben und unten
--   Retail (Datei 2406987, 150 Zeilen): 36–76, Metallkante
-- Unbekannte Grafik: kein Titelstreifen, die Leiste nimmt dann die Tooltip-Optik.
local TITLE_ATLAS = "_UI-Frame-Metal-EdgeTop"
local TITLE_BANDS = {
    forever = { top = 26 / 190, bottom = 81 / 190, file = 8069118, height = 95 },
    retail = { top = 36 / 150, bottom = 76 / 150, file = 2406987, height = 75 },
}

local function TitleBand(info)
    if type(info) ~= "table" then return nil end
    for _, band in pairs(TITLE_BANDS) do
        if info.file == band.file then return band end
    end
    for _, band in pairs(TITLE_BANDS) do
        if info.height == band.height then return band end
    end
    return nil
end

function ns.CreateTitleBackground(parent)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, TITLE_ATLAS)
    local band = ok and TitleBand(info)
    if not band then return nil end
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetHorizTile(info.tilesHorizontally or false)   -- wie NineSliceUtil
    tex:SetAtlas(TITLE_ATLAS)
    tex.ezBand = band
    return tex
end

-- Legt den Titelstreifen so, dass sein deckender Teil genau „height“ hoch ist und
-- oben bündig mit dem Frame abschließt; der Schatten fällt darunter.
function ns.PlaceTitleBackground(tex, frame, height)
    local band = tex.ezBand
    local full = height / (band.bottom - band.top)
    local above = full * band.top
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, above)
    tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, above)
    tex:SetHeight(full)
end

-- Farben wie beim Tooltip des Clients, Deckkraft frei wählbar.
function ns.SetTooltipBackgroundAlpha(frame, alpha)
    local r, g, b = 0.09, 0.09, 0.19
    local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    if c and c.GetRGB then r, g, b = c:GetRGB() end
    local br, bg, bb = 1, 1, 1
    local d = TOOLTIP_DEFAULT_COLOR
    if d and d.GetRGB then br, bg, bb = d:GetRGB() end
    local border = math.min(1, alpha + 0.3)
    if frame.ezFill then
        frame.ezFill:SetColorTexture(r, g, b, alpha)
    elseif frame.SetCenterColor then
        frame:SetCenterColor(r, g, b, alpha)
        if frame.SetBorderColor then frame:SetBorderColor(br, bg, bb, border) end
    elseif frame.SetBackdropColor then
        frame:SetBackdropColor(r, g, b, alpha)
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(br, bg, bb, border) end
    end
end

ns.GOLD, ns.WHITE, ns.GREY, ns.GREEN, ns.RED = Core.GOLD, Core.WHITE, Core.GREY, Core.GREEN, Core.RED
ns.YELLOW = Core.YELLOW

-- Blizzards Farbobjekt als Farbcode (Design-System 2.5, Welle 22): das erste vorhandene der genannten Objekte, sonst
-- fallback. Für Töne, die ezCore (noch) nicht als Kurzform führt – vorher standen sie als eigene Farbcodes in den
-- Bausteinen (ff8000/ff8040 bzw. 8080ff/4080ff).
local function BlizzardCode(fallback, ...)
    for i = 1, select("#", ...) do
        local obj = rawget(_G, (select(i, ...)))
        if type(obj) == "table" and type(obj.GetRGB) == "function" then
            local ok, r, g, b = pcall(obj.GetRGB, obj)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return Core.ColorCode(r, g, b) end
        end
    end
    return fallback
end
-- Orange (bald leer, zum Lehrer, Abklingzeit): Blizzards ORANGE_FONT_COLOR, sonst ezCores Gelb.
function ns.OrangeCode() return BlizzardCode(Core.YELLOW, "ORANGE_FONT_COLOR") end
-- Blau (Erholung, Mana): Blizzards LIGHTBLUE_FONT_COLOR bzw. BATTLENET_FONT_COLOR, sonst Weiß.
function ns.BlueCode() return BlizzardCode(Core.WHITE, "LIGHTBLUE_FONT_COLOR", "BATTLENET_FONT_COLOR") end
ns.Gold, ns.White, ns.Grey = Core.Gold, Core.White, Core.Grey
-- Tooltip-Zeilen in ezCores Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6; docs/design-system.md 2.5/2.7):
-- "normal" Gold (Überschrift, Bezeichnung), "highlight" Weiß (Wert), "hint" ezCores Grau (Quelle, Erklärung, Stand),
-- "good"/"bad" Grün/Rot (Gewinn/Verlust, alles gut, Fehler), "orange" (bald fällig, zum Lehrer).
ns.TipLine, ns.TipDoubleLine = Core.TipLine, Core.TipDoubleLine
ns.StripColors = Core.StripColors   -- Farbcodes entfernen (für „Werte nicht einfärben“)

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------

-- ezPanelDB legt ezCores Gerüst an (Core.NewModule oben: db, tables, onLoad); es setzt ns.db und ns.S.
local FillDefaults = Core.FillDefaults
ns.FillDefaults = FillDefaults

---------------------------------------------------------------------------
-- Charakter
---------------------------------------------------------------------------

--[[
    Die Charakterdaten kommen aus ezCore (ezCoreDB.chars, Schlüssel „Voller Name-Realm“).
    Alle Bausteine greifen weiter über ns.me (aktueller Charakter), ns.Characters, ns.CharName und
    die Helfer unten darauf zu. Felder, die ezPanel-Bausteine schreiben:
      playedLevelAt                                                    XP
    (die Sitzung lag bis Welle 6 als me.session hier; jetzt Core.Session, siehe unten)
    Alles andere hält ezCore für alle Module aktuell: Name, Realm, Klasse, Fraktion, Stufe, Erfahrung,
    Ruhe-XP, Gebiet, Ruhestein, Spielzeit, Geld, letzter Login, Taschenplätze, Briefkasten (mailbox) und
    seit Welle 2 auch Gegenstandsstufe (ilvl, gear), Währungen (currencies), zuletzt geänderte Fraktion
    (lastFaction) und Sperren (lockouts) – ezPanel schreibt diese Felder nicht mehr, es liest sie über
    ezCore.ItemLevelOf, ezCore.Currencies, ezCore.LastFaction und ezCore.Lockouts.
]]

--[[
    Sitzung: Gold-, XP- und Rufgewinne seit dem Einloggen. Anders als bei Titan übersteht die Sitzung ein /reload.
    Seit Welle 7 (PANEL-03, W-13) ist das ezCores Sitzung (Core.Session, die EINE der ezCollection): Beginn,
    Startgold, Einnahmen und Ausgaben zählt ezCore; ezPanel liest sie (ns.SessionStart, Core.Session.Earned …).
    ns.session ist ezPanels Tabelle darin (Core.Session.Data("ezPanel")) für die eigenen Zähler der Bausteine:
    xp, kills (XP), rep, repStart (Ruf), prof (Berufe), cur (Währungen). Sie leert sich mit der Sitzung.
    Die frühere eigene Sitzung lag in ezCores Charakter-Datensatz (me.session); sie wird beim ersten Anmelden einmal
    übernommen (nur die eigenen Zähler) und dann gelöscht – nur, wenn sie nach der Regel von ezCore (Session.GAP)
    weitergelaufen wäre UND ezCores Sitzung selbst weiterläuft und nicht später begann. Sonst hingen XP und Ruf einer
    langen Spielzeit an einer kurzen Sitzung („XP pro Stunde“ viel zu hoch).
]]
local START_SLACK = 5   -- Sekunden: beide Sitzungen begannen beim selben Anmelden, nur nicht im selben Augenblick
local CORE_SESSION_FIELDS = { start = true, money = true, earned = true, spent = true }

-- ezPanels Tabelle der laufenden Sitzung neu holen (nach dem Anmelden und nach „Sitzung zurücksetzen“).
local function UseSession()
    ns.session = Core.Session.Data(ADDON) or ns.session or {}
    return ns.session
end

-- Einmalige Übernahme der alten Sitzung aus me.session (PANEL-03). → true, wenn etwas übernommen wurde.
function ns.MigrateSession(me, last)
    local old = type(me) == "table" and me.session
    if old == nil then return false end
    me.session = nil   -- gehört nicht in ezCores Datensatz; ab jetzt Core.Session
    local gap = ns.Num(Core.Session.GAP) or 60
    if type(old) ~= "table" or not ns.Num(last) or time() - last > gap then return false end
    -- ezCores Sitzung muss dieselbe sein: weitergelaufen (/reload) und nicht nach der alten begonnen
    if not Core.Session.IsContinued() then return false end
    local start, oldStart = ns.Num(Core.Session.Start()), ns.Num(old.start)
    if not start or (oldStart and oldStart < start - START_SLACK) then return false end
    local data = Core.Session.Data(ADDON)
    if type(data) ~= "table" then return false end
    local moved = false
    for key, value in pairs(old) do
        if not CORE_SESSION_FIELDS[key] and data[key] == nil then   -- was die laufende Sitzung schon hat, bleibt
            data[key] = value
            moved = true
        end
    end
    return moved
end

-- „Sitzung zurücksetzen“ (Menü von Gold und XP): eine neue Sitzung in ezCore – für alle Module.
-- Weiterleitung der bisherigen Funktion (Leitlinie 8); die Nachricht SESSION_RESET zieht ns.session nach.
function ns.NewSession()
    Core.Session.Reset()
    return UseSession()
end

-- Beginn der Sitzung (time()); ohne Sitzung jetzt.
function ns.SessionStart()
    return Core.Session.Start() or time()
end

ns.On("PLAYER_LOGIN", function()
    ns.charKey, ns.realm, ns.me = Core.charKey, Core.realm, Core.me
    local ok, err = pcall(ns.MigrateSession, ns.me, Core.previousLastSeen)   -- letzter Login vor diesem
    if not ok then ns.Error(err, "MigrateSession") end
    UseSession()
    ns.RunReady()
end)

-- Sitzung zurückgesetzt (auch aus einem anderen Modul): neue Tabelle, Bausteine neu zeichnen.
Core.Listen("SESSION_RESET", function()
    UseSession()
    if ns.ready and ns.UpdateAllBlocks then ns.UpdateAllBlocks() end
end, ADDON)

-- Charaktere sortiert: aktueller zuerst, dann nach Realm und Name.
function ns.Characters(filter)
    return Core.CharacterList(filter)
end

function ns.CharName(c, key)
    return Core.CharName(c, key)
end

-- Stand gemerkter Werte eines Twinks (Regel „Datenquellen“, PANEL-17): grauer Zusatz „ (Stand 12.11.)“ für die rechte
-- Seite einer Tooltip-Zeile. t = Zeit des Erfassens; ohne sie der letzte Login des Charakters (c.lastSeen, ezCore
-- setzt ihn auch beim Ausloggen). "" ohne brauchbare Zeit.
function ns.AltStand(c, t)
    t = ns.Num(t)
    if not t and type(c) == "table" then t = ns.Num(c.lastSeen) end
    if not t or t <= 0 then return "" end
    return " " .. ns.Grey(L.ALT_STAND:format(Core.DateText(t)))
end

-- Gegenstandsstufe des gespielten Charakters: angelegt (sonst gesamt), gesamt mit Taschen; nil, wenn unbekannt.
-- Eine Stelle für alle Module (ezCore.ItemLevel); die Stufe der Twinks über ezCore.ItemLevelOf(charKey).
ns.ItemLevel = Core.ItemLevel

-- Sekunden bis zum Tages- oder Wochenreset: fn = "GetSecondsUntilDailyReset" | "GetSecondsUntilWeeklyReset"
-- (C_DateAndTime); nil, wenn der Client die Funktion nicht hat oder der Wert gesperrt ist. Für Uhr und Werkzeuge.
function ns.ResetIn(fn)
    if not (C_DateAndTime and C_DateAndTime[fn]) then return nil end
    local ok, seconds = pcall(C_DateAndTime[fn])
    return ok and ns.Num(seconds) or nil
end

-- Höchststufe, gespielte Zeit jetzt, hochgerechnete Ruhe-XP: aus ezCore.
ns.MaxLevel = Core.MaxLevel
ns.PlayedNow = Core.PlayedNow
ns.EstimateRested = Core.EstimateRested

---------------------------------------------------------------------------
-- ezBag (optional)
---------------------------------------------------------------------------

--[[
    Was früher nur ezBag wusste (Bank zuletzt gesehen, Taschenplätze), steht jetzt für jeden
    Charakter in ezCore. ns.ezBag bleibt als Schnittstelle der Bausteine erhalten.
]]
ns.ezBag = {}

function ns.ezBag.Active()
    return Core.IsLoaded("ezBag")
end

-- Datensatz des aktuellen Charakters (oder eines Schlüssels) mit bankSeen, bagFree, bagTotal …
function ns.ezBag.Char(key)
    return Core.Char(key)
end

-- Freie/alle Taschenplätze eines Charakters und wann sie erfasst wurden: frei, gesamt, gesehen – nil, wenn unbekannt.
-- Eine Prüfung für alle Module (PANEL-08): ezCore.BagSpaceOf(charKey) behandelt „0 von 0“ und „mehr frei als
-- vorhanden“ selbst als unbekannt (auch alte Stände aus der Übernahme früherer ezPanel-Daten, Chars.Migrate).
-- key ist der Charakter-Schlüssel; c bleibt als erster Wert der früheren Form stehen und wird nicht mehr gelesen.
function ns.ezBag.Slots(c, key)
    if key == nil then return nil end
    local free, total, _, seen = Core.BagSpaceOf(key)
    if not free then return nil end
    return free, total, seen
end

function ns.ezBag.OpenSettings()
    return Core.OpenModuleSettings("ezBag")
end

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

local function FindBlock(word)
    word = word:lower()
    for _, block in ipairs(ns.blockList or {}) do
        if block.id:lower() == word or (block.command and block.command == word) then return block end
    end
end

-- Die eigenen Befehlswörter von ezPanel. → true, wenn das Wort erledigt ist; sonst übernimmt ezCores Gerüst:
-- ohne Wort und „optionen“ die Einstellungen, „status“, „hilfe“, bei Unbekanntem die Hilfe.
function ns.SlashExtra(cmd, rest)
    if Core.StandardCommand(cmd) then return false end
    if Core.HandleToggle(ns, cmd) then return true end   -- Schalter vor Baustein-Namen, wie bisher

    if cmd == "zuruecksetzen" or cmd == "zurücksetzen" or cmd == "reset" then
        ns.ResetLayout()
        ns.Print(L.CMD_RESET)
    elseif cmd == "standard" or cmd == "defaults" then
        -- Einstellungen zurücksetzen: Rückfrage und Nachlauf wie der Knopf (Core.SlashReset über page:AskReset; vorher
        -- ohne Rückfrage). „zuruecksetzen“ bleibt die Anordnung der Leiste (oben), darum kein slash.reset (T18-20).
        Core.SlashReset(ns)
    elseif cmd == "titan" then
        ns.ImportTitan(true)
    elseif cmd == "bausteine" or cmd == "blocks" then
        ns.Print(L.CMD_BLOCKS)
        for _, block in ipairs(ns.blockList) do
            local state = ns.BlockEnabled(block.id) and L.ON or L.OFF
            -- deutsches Wort und Kennung (beide schalten; die Kennung ist das englische Wort, T10-1)
            local word = block.command and block.command ~= block.id and (block.command .. " | " .. block.id) or block.id
            ns.Print(("  %s – %s (%s)"):format(word, block.name, state))
        end
    elseif cmd == "chars" then
        Core.PrintChars(ns)
    elseif cmd == "vergessen" or cmd == "forget" then
        -- Die Charakterdaten liegen einmal in ezCore: vergessen gilt für alle Module.
        Core.ForgetCommand(ns, rest)
    else
        local block = FindBlock(cmd)
        if not block then return false end
        ns.SetBlockEnabled(block.id, not ns.BlockEnabled(block.id))
        ns.Print((ns.BlockEnabled(block.id) and L.CMD_ON or L.CMD_OFF):format(block.name))
    end
    return true
end

---------------------------------------------------------------------------
-- Status (/ep status und Einstellungen → Erweitert → „Status“)
---------------------------------------------------------------------------

ns.AddStatusLine(function()
    if not (ns.S and ns.ready) then return nil end
    local S = ns.S
    local lines = {}
    local bar = S.topBar and L.ON or L.OFF
    if S.topBar and S.autoHideTop then bar = bar .. " (" .. L.OPT_autoHideTop .. ")" end
    lines[#lines + 1] = L.STATUS_BAR:format(bar)
    local on, total = 0, 0
    for _, def in ipairs(ns.blockList or {}) do
        total = total + 1
        if def.cfg and def.cfg.enabled then on = on + 1 end
    end
    lines[#lines + 1] = L.STATUS_BLOCKS:format(on, total)
    if ns.TopSpaceCount then
        local reserve = ns.TopReserve and ns.TopReserve() or 0
        lines[#lines + 1] = L.STATUS_TOPSPACE:format(S.reserveTop and L.ON or L.OFF, ns.TopSpaceCount(), Core.Pixels(reserve))
    end
    if ns.Profiles and ns.Profiles.P then lines[#lines + 1] = L.STATUS_PROFILE:format(ns.Profiles.P.Label()) end
    return lines
end)

-- Charakter vergessen (auch aus einem anderen Modul): seinen Schlüssel aus cfg.hidden der Bausteine streichen
-- (Profiles.ForgetChar, Gesamtreview 18.11.2026, Nachsuche zu T4-2), dann Bausteine neu zeichnen.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.Profiles and ns.Profiles.ForgetChar then ns.Profiles.ForgetChar(key) end
    if ns.ready and ns.UpdateAllBlocks then ns.UpdateAllBlocks() end
end, ADDON)

-- Addon-Fach an der Minikarte: ezPanel hat kein eigenes Fenster (die Leiste steht immer da) – jeder Klick öffnet die
-- Einstellungen (sonst die Hilfe); Zeilen und Befehl (mit /ep, wenn frei) baut ezCore (Entscheidung 5, T18-3; EC-87:
-- alle drei Compartment-Zeilen in der TOC).
ezPanel_OnAddonCompartmentClick, ezPanel_OnAddonCompartmentEnter, ezPanel_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = ADDON, owner = ADDON })
