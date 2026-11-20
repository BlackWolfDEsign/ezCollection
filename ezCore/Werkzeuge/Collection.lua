local ADDON, ns = ...
local Core = ezCore
local L = Core.L

-- Die ezCollection als Ganzes: Übersicht in den Einstellungen, /ezcollection, Status und Fehlerliste.

-- Module der Sammlung, die die Übersicht auch dann nennt, wenn sie nicht geladen sind – alle 18, nach Namen
-- (V-017: vorher nur sechs; ein abgeschaltetes ezGear fehlte ganz, und „/ez gear“ landete in der Hilfe).
-- EINE Quelle: Ein Test vergleicht die Liste mit den Modulordnern des Pakets. Ein neues Modul läuft auch ohne Eintrag
-- (jedes geladene Modul erscheint von selbst in Übersicht, Status und /ez <Modul>); eingetragen wird es, damit es
-- auch abgeschaltet genannt wird. Tooltip: Core.ModuleTip (unten).
Core.KNOWN_MODULES = { "ezAuction", "ezBag", "ezBars", "ezBuff", "ezChat", "ezCombat", "ezCraft", "ezGear", "ezHeal",
    "ezLoot", "ezMacro", "ezMail", "ezMap", "ezMerchant", "ezPanel", "ezQuest", "ezSocial", "ezTalent" }

-- Zustand eines Moduls: "loaded" (läuft) | "disabled" (installiert, nicht geladen) | "absent" (nicht installiert).
-- Kann der Client nicht sagen, ob ein Addon installiert ist, gilt ein nicht geladenes als "disabled".
function Core.ModuleState(name)
    if Core.Module(name) then return "loaded" end
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    if exists then
        local ok, there = pcall(exists, name)
        if ok and there == false then return "absent" end
    end
    return "disabled"
end

-- Bekannte und geladene Module, ohne Doppelte (eine Liste für Übersicht, Status und /ez).
function Core.ModuleNames()
    local list, seen = {}, { [ADDON] = true }
    for _, name in ipairs(Core.KNOWN_MODULES) do
        if not seen[name] then seen[name] = true; list[#list + 1] = name end
    end
    for _, name in ipairs(Core.moduleOrder) do
        if not seen[name] then seen[name] = true; list[#list + 1] = name end
    end
    return list
end

-- Kurzbeschreibung eines Moduls „aus dem Modul selbst“ (EC-18, VP-23; Frage 10, entschieden 14.11.2026): Ist das
-- Modul installiert (auch abgeschaltet), gilt sein eigener Text – „## Notes-<Sprache>“ bzw. „## Notes“ seiner TOC.
-- Nur für ein nicht installiertes Modul (oder eine TOC ohne Notes) beschreibt ezCore es (L.MODULE_TIP_<Modul>, für
-- alle in Core.KNOWN_MODULES, deutsch und englisch). → Text, Quelle ("module" | "core") oder nil
local function TocNotes(name)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    if type(meta) ~= "function" then return nil end
    local ok, notes = pcall(meta, name, "Notes-" .. (GetLocale and GetLocale() or "enUS"))
    if not (ok and type(notes) == "string" and not Core.IsSecret(notes) and notes ~= "") then
        ok, notes = pcall(meta, name, "Notes")
    end
    if ok and type(notes) == "string" and not Core.IsSecret(notes) and notes ~= "" then return notes end
    return nil
end

function Core.ModuleTip(name)
    if type(name) ~= "string" then return nil end
    if Core.ModuleState(name) ~= "absent" then
        local notes = TocNotes(name)
        if notes then return notes, "module" end
    end
    local key = "MODULE_TIP_" .. name
    if L[key] ~= key then return L[key], "core" end
    return nil
end

local function ModuleSettings(name)
    local mod = Core.Module(name)
    local mns = mod and mod.ns
    return mns and mns.OpenSettings
end

-- „bag“, „ezbag“ oder „ezBag“ → „ezBag“ (für /ez bag).
function Core.FindModuleName(word)
    word = tostring(word or ""):lower()
    if word == "" then return nil end
    for _, name in ipairs(Core.ModuleNames()) do
        local low = name:lower()
        if word == low or "ez" .. word == low then return name end
    end
end

-- Öffnet die Unterseite eines Moduls; true bei Erfolg.
function Core.OpenModuleSettings(name)
    local open = ModuleSettings(name)
    return open ~= nil and open() == true
end

---------------------------------------------------------------------------
-- Status und Fehlerliste
---------------------------------------------------------------------------

function Core.StatusLines()
    local lines = { L.STATUS_HEADER:format(Core.Version(ADDON)) }
    for _, name in ipairs(Core.ModuleNames()) do
        if Core.Module(name) then
            local errors = #Core.Module(name).problems
            local text = L.STATUS_MODULE:format(name, Core.Version(name))
            if errors > 0 then text = text .. " " .. Core.Red("(" .. errors .. ")") end
            lines[#lines + 1] = text
        elseif Core.ModuleState(name) ~= "absent" then   -- nicht installierte Module nennt nur die Übersicht
            lines[#lines + 1] = L.STATUS_MODULE_OFF:format(name)
        end
    end
    -- ezCore zu alt für ein Modul (Core.Require): die Meldung gehört in den Status
    for _, name in ipairs(Core.moduleOrder) do
        local req = Core.Requirement and Core.Requirement(name)
        if req and req.text then lines[#lines + 1] = "  " .. Core.Red(req.text) end
    end
    -- Kurzbefehle der Module, die das Gerüst gesetzt hat (V-181: an einer Stelle aufgelistet)
    local short = {}
    for _, name in ipairs(Core.moduleOrder) do
        local alias = Core.SlashAliases and Core.SlashAliases()[name]
        if alias then short[#short + 1] = name .. " " .. alias end
    end
    if #short > 0 then lines[#lines + 1] = L.STATUS_ALIASES:format(table.concat(short, ", ")) end
    -- Fremde Addons, auf die ezCollection Rücksicht nimmt (OtherAddOns.lua)
    local others = {}
    for _, entry in ipairs(Core.OtherAddOns and Core.OtherAddOns() or {}) do others[#others + 1] = entry.label end
    if #others > 0 then lines[#lines + 1] = L.STATUS_OTHER:format(table.concat(others, ", ")) end
    -- Rücksicht-Zähler (AH-14): wie oft ein Modul je Funktion und Addon gewichen ist (nur, wenn es das gab)
    local yielded = Core.YieldStatusLine and Core.YieldStatusLine()
    if yielded then lines[#lines + 1] = yielded end
    -- Leucht-Dienst: wer gerade Gründe angemeldet hat (nur, wenn es welche gibt)
    local glow = Core.Glow and Core.Glow.StatusLine()
    if glow then lines[#lines + 1] = glow end
    -- Sichere Knöpfe (SecureButton.lua): Anzahl und was auf das Kampfende wartet (nur, wenn es welche gibt)
    local secure = Core.SecureButtons and Core.SecureButtons.StatusLine()
    if secure then lines[#lines + 1] = secure end
    -- Gruppen- und Raidrahmen (GroupFrames.lua): wie viele Blizzard-Rahmen der Dienst kennt (nur in einer Gruppe)
    local group = Core.GroupFrames and Core.GroupFrames.StatusLine()
    if group then lines[#lines + 1] = group end
    -- Klick-Zauber (ClickBindings.lua): gespeicherte Profile und was auf das Kampfende wartet (nur, wenn es etwas gibt)
    local clicks = Core.ClickBindings and Core.ClickBindings.StatusLine()
    if clicks then lines[#lines + 1] = clicks end
    -- Auren-Reihen (AuraRow.lua): Anzahl und was auf das Kampfende wartet (nur, wenn es welche gibt)
    local auraRows = Core.AuraRows and Core.AuraRows.StatusLine()
    if auraRows then lines[#lines + 1] = auraRows end
    -- Datenquellen (Sources.lua): welche Datenbanken fremder Addons gerade antworten
    local sources = Core.Sources and Core.Sources.StatusLine()
    if sources then lines[#lines + 1] = sources end
    -- Sammel-Fundorte (SAM-18): Punkte je Art, Karten, geschätzte Größe; Minikarte (SAM-07): an oder warum aus
    local gather = Core.Gathering and Core.Gathering.StatusLine and Core.Gathering.StatusLine()
    if gather then lines[#lines + 1] = gather end
    local minimap = Core.MapPins and Core.MapPins.StatusLine and Core.MapPins.StatusLine()
    if minimap then lines[#lines + 1] = minimap end
    -- Entdecker-Datenbank (DiscoveryView.lua): Einträge, Größe, wo gespeichert, Übernahme, Größe von ezCoreDB (DG-10)
    if Core.Discovery and Core.Discovery.StatusLines then
        local ok, dbLines = pcall(Core.Discovery.StatusLines)
        for _, line in ipairs(ok and dbLines or {}) do lines[#lines + 1] = line end
    end
    -- Abgelöste Funktionen (Core.Deprecated, Framework.lua): wer ruft noch alte Schnittstellen (nur, wenn jemand)
    local old = Core.DeprecatedStatusLine and Core.DeprecatedStatusLine()
    if old then lines[#lines + 1] = old end
    local errors = #Core.Errors()
    lines[#lines + 1] = errors > 0 and L.STATUS_ERRORS:format(errors) or L.STATUS_NO_ERRORS
    return lines
end

function Core.PrintStatus()
    for _, line in ipairs(Core.StatusLines()) do ns.Print(line) end
end

function Core.PrintErrors()
    local list = Core.Errors()
    if #list == 0 then return ns.Print(L.ERRORS_EMPTY) end
    for i = math.min(#list, 20), 1, -1 do
        local e = list[i]
        -- Datum je Sprache (Core.DateText; vorher fest deutsch, T10-3)
        ns.Print(L.ERROR_LINE:format(Core.DateText(e.t or 0, "full"), e.m or "?", Core.ErrorLabel(e)))
    end
end

---------------------------------------------------------------------------
-- Übersicht unter Esc → Optionen → AddOns → ezCollection
---------------------------------------------------------------------------

-- Zeile eines Charakters auf der Unterseite „Charaktere“: „Name – Stufe 12 Priester – zuletzt vor 3 Tagen“.
function Core.CharRowLabel(entry)
    local c = type(entry) == "table" and entry.c or {}
    local parts = { Core.CharName(c, entry.key, " - ", true) }
    local level, class = Core.Num(c.level), c.class and Core.ClassName(c.class) or nil
    if level and class then
        parts[#parts + 1] = L.CHARS_LEVEL_CLASS:format(level, class)
    elseif level then
        parts[#parts + 1] = L.CHARS_LEVEL:format(level)
    elseif class then
        parts[#parts + 1] = class
    end
    if entry.isMe then
        parts[#parts + 1] = L.CHARS_ME
    elseif Core.Num(c.lastSeen) and c.lastSeen > 0 then
        parts[#parts + 1] = L.CHARS_SEEN:format(Core.Ago(c.lastSeen))
    end
    -- T4-NR1: derselbe Charakter unter neuem Namen (gleiche GUID) – der alte Satz zählt doppelt, bis er vergessen ist
    local renamed = not entry.isMe and Core.CharRenamedTo and Core.CharRenamedTo(entry.key)
    if renamed then
        local new = Core.Char(renamed)
        parts[#parts + 1] = L.CHARS_RENAMED:format(Core.CharName(new, renamed, " - ", true))
    end
    return table.concat(parts, " – ")
end

-- Charakterverwaltung auf der Seite „ezCollection“ (V-004, Leitlinie 3): unter „Bekannte Charaktere“ jeder Twink
-- eine Zeile mit Knopf „Vergessen“ (Rückfrage über Core.AskForgetChar). Ein vergessener Twink verschwindet aus der
-- Liste (Blizzards AddShownPredicate); der gespielte Charakter hat keinen Knopf (er steht im Tooltip der
-- Überschrift). Bewusst keine eigene Unterseite: Die Zeilen stehen dort, wo auch „Verlauf leeren“ steht.
-- → Anzahl Zeilen mit Knopf
function Core.AddCharRows(page)
    page = page or Core.ParentPage()
    if not page then return 0 end
    local list, me, rows = Core.CharacterList(), nil, 0
    for _, entry in ipairs(list) do
        if entry.isMe then me = Core.CharRowLabel(entry) end
    end
    page:Header(L.CHARS_HEADER, L.CHARS_HEADER_TIP .. (me and ("\n\n" .. me) or ""))
    for _, entry in ipairs(list) do
        if not entry.isMe then
            local key = entry.key
            local initializer = page:Button(Core.CharRowLabel(entry), L.CHARS_FORGET_BUTTON, function() Core.AskForgetChar(key, ns) end,
                L.CHARS_FORGET_TIP:format(key))
            if initializer and initializer.AddShownPredicate then
                initializer:AddShownPredicate(function() return Core.Chars()[key] ~= nil end)
            end
            rows = rows + 1
        end
    end
    return rows
end

-- Zeile einer gemerkten Gildenbank: „Gilde (Realm) – erfasst vor 3 Tagen – veraltet: …“ (T4-NR3).
function Core.GuildRowLabel(key, g)
    g = type(g) == "table" and g or {}
    local name = type(g.name) == "string" and g.name or (type(key) == "string" and key:match("^(.-)%-")) or tostring(key)
    local realm = g.guildRealm or g.realm or (type(key) == "string" and key:match("%-([^%-]+)$"))
    local parts = { realm and L.GUILDS_NAME_REALM:format(name, realm) or name }
    if Core.Num(g.seen) and g.seen > 0 then parts[#parts + 1] = L.GUILDS_SEEN:format(Core.Ago(g.seen)) end
    local state, holder
    if Core.Inventory and Core.Inventory.GuildState then state, holder = Core.Inventory.GuildState(key) end
    if state == "stale" then
        parts[#parts + 1] = L.GUILDS_STALE
    elseif state == "maybe" and holder then
        -- ein Twink mit noch unbekannter Gilde hält sie: Hinweis, damit „Vergessen“ gefunden wird (Gegenprüfung T4-NR3)
        parts[#parts + 1] = L.GUILDS_MAYBE:format(Core.CharName(Core.Char(holder), holder, " - ", true))
    end
    return table.concat(parts, " – ")
end

-- Zeilen unter „Gemerkte Gildenbanken“: Schlüssel → Initializer (Core.AddGuildRows), damit der Text der Lage folgt.
local guildRows = {}

-- Text der Gildenbank-Zeilen neu bilden (Austritt, Twink vergessen, erneut erfasst – nicht erst nach /reload;
-- Gegenprüfung T4-NR3). Blizzards Liste liest den Namen bei jedem Zeichnen einer Zeile (initializer:GetName() aus
-- GetData().name); das Initializer-Objekt gehört dieser Zeile und wurde von ezCore angelegt. → Anzahl aufgefrischter
function Core.RefreshGuildRows()
    local n = 0
    for key, initializer in pairs(guildRows) do
        local g = Core.Guilds()[key]
        local data = g ~= nil and type(initializer) == "table" and type(initializer.GetData) == "function"
            and initializer:GetData() or nil
        if type(data) == "table" then
            data.name = Core.GuildRowLabel(key, g)
            n = n + 1
        end
    end
    return n
end
Core.Listen("GUILDBANK_CHANGED", function() Core.RefreshGuildRows() end, "ezCore.GuildRows")
Core.Listen("CHAR_FORGOTTEN", function() Core.RefreshGuildRows() end, "ezCore.GuildRows")

-- Rückfrage und Vergessen einer gemerkten Gildenbank (Knopf unter „Gemerkte Gildenbanken“). → true, wenn gefragt wurde
function Core.AskForgetGuild(key, mns)
    mns = type(mns) == "table" and mns or ns
    if type(key) ~= "string" or Core.Guilds()[key] == nil then
        mns.Print(L.GUILDS_NOT_FOUND:format(tostring(key or "")))
        return false, "unknown"
    end
    Core.Confirm(L.GUILDS_FORGET_ASK:format(key), function()
        if Core.ForgetGuild(key) then mns.Print(L.GUILDS_FORGOT:format(key)) end
    end, { alert = true })
    return true
end

-- Gemerkte Gildenbanken mit Knopf „Vergessen“ unter den Charakteren (Gesamtreview 18.11.2026, T4-NR3; Leitlinie 3).
-- Eine Gildenbank, in deren Gilde kein eigener Charakter mehr ist, zählt nicht mehr mit und ist als veraltet markiert.
-- → Anzahl Zeilen
function Core.AddGuildRows(page)
    page = page or Core.ParentPage()
    if not page then return 0 end
    local keys = {}
    for key in pairs(Core.Guilds()) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    if #keys == 0 then return 0 end
    table.sort(keys)
    page:Header(L.GUILDS_HEADER, L.GUILDS_HEADER_TIP)
    for _, key in ipairs(keys) do
        local initializer = page:Button(Core.GuildRowLabel(key, Core.Guilds()[key]), L.CHARS_FORGET_BUTTON,
            function() Core.AskForgetGuild(key, ns) end, L.GUILDS_FORGET_TIP:format(key))
        if initializer and initializer.AddShownPredicate then
            initializer:AddShownPredicate(function() return Core.Guilds()[key] ~= nil end)
        end
        if initializer then guildRows[key] = initializer end
    end
    return #keys
end

-- Abschnitt „Gemeinsame Schalter“ (Einstellungs-Prüfung 19.11.2026, Nr. 59/60, 62, 95/96): Schalter, die mehrere
-- Module lesen, stehen einmal hier; die Seiten der Module zeigen denselben Schalter als Spiegel (page:SharedCheckbox).
-- Eine Zeile erscheint nur, solange ein Modul läuft, das sie liest. → Anzahl der angelegten Zeilen
local SHARED_ROWS = {
    { "vendor", "autoSell", "vendorAutoSell", { "ezBag", "ezMerchant" } },
    { "vendor", "repairAuto", "vendorRepairAuto", { "ezMerchant", "ezPanel" } },
    { "vendor", "repairGuild", "vendorRepairGuild", { "ezMerchant", "ezPanel" } },
    -- meldet nur die automatische Reparatur – grau, solange sie aus ist
    { "vendor", "repairReport", "vendorRepairReport", { "ezMerchant", "ezPanel" }, parent = "vendor.repairAuto" },
    { "itemMarks", "itemLevel", "markItemLevel", { "ezBag", "ezLoot" } },
    { "itemMarks", "boe", "markBoe", { "ezBag", "ezLoot" } },
}
Core.SHARED_ROWS = SHARED_ROWS

local function AnyLoaded(names)
    for _, name in ipairs(names) do
        if Core.ModuleState(name) == "loaded" then return true end
    end
    return false
end

function Core.AddSharedSettings(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return 0 end
    local any = false
    for _, row in ipairs(SHARED_ROWS) do
        if AnyLoaded(row[4]) then any = true end
    end
    if not any then return 0 end
    page:Header(L.SHARED_HEADER, L.SHARED_HEADER_TIP)
    local n = 0
    for _, row in ipairs(SHARED_ROWS) do
        local names = row[4]
        page:OwnCheckbox(row[1], row[2], { text = row[3], variable = "ezCore_" .. row[1] .. "_" .. row[2],
            parent = row.parent, shown = function() return AnyLoaded(names) end })
        n = n + 1
    end
    return n
end

local function BuildOverview()
    local cat, layout = Core.SettingsParent()
    if not (cat and layout and layout.AddInitializer) then return end
    local page = Core.ParentPage()   -- dieselben Helfer wie auf jeder Modulseite (V-018)
    local function Add(initializer) if initializer then layout:AddInitializer(initializer) end end
    -- „Allgemein“ wie auf jeder Seite: hier der Einstieg (Erster Start)
    page:Header(L.SETTINGS_GENERAL)
    if Core.FirstStart then
        page:Button(L.FIRST_LABEL, L.FIRST_BUTTON, function() Core.FirstStart.Show() end, L.FIRST_TIP)
    end
    -- Tasten-Dienst (EC-73): sichtbarer Weg zu Blizzards Tastaturbelegung » AddOns » ezCollection
    if Core.Keys then
        page:Button(L.KEY_LABEL, L.KEY_BUTTON, function() Core.Keys.Open() end, L.KEY_TIP)
    end
    -- Einführung (W-1811-Einfuehrung, FirstStart.lua): Knopf zur Unterseite „Einführung“, die hier entsteht – nach den
    -- Seiten der Module, damit sie alle laufenden Module und ihre Schalter kennt
    if Core.Intro then
        local okIntro, errIntro = pcall(Core.Intro.AddPage, page)
        if not okIntro then Core.Error(ADDON, errIntro, "Intro") end
        page:Button(L.INTRO_LABEL, L.INTRO_BUTTON, function() Core.Intro.Open() end, L.INTRO_TIP)
    end
    if CreateSettingsListSectionHeaderInitializer then
        Add(CreateSettingsListSectionHeaderInitializer(L.OVERVIEW_HEADER, L.OVERVIEW_HEADER_TIP))
    end
    if CreateSettingsButtonInitializer then
        for _, name in ipairs(Core.ModuleNames()) do
            local state = Core.ModuleState(name)
            local label = state == "loaded" and L.OVERVIEW_LOADED:format(name, Core.Version(name))
                or (state == "absent" and L.OVERVIEW_ABSENT or L.OVERVIEW_MISSING):format(name)

            local open = ModuleSettings(name)
            if open then
                Add(CreateSettingsButtonInitializer(label, L.OVERVIEW_OPEN, function() open() end, Core.ModuleTip(name), true))
            elseif CreateSettingsListSectionHeaderInitializer then
                Add(CreateSettingsListSectionHeaderInitializer(label, (Core.ModuleTip(name))))
            end
        end
        -- Abschnitt „Komfort“ (Comfort.lua), danach wie auf jeder Seite „Erweitert“.
        if Core.Comfort then
            local okComfort, errComfort = pcall(Core.Comfort.AddSection, cat)
            if not okComfort then Core.Error(ADDON, errComfort, "Comfort") end
        end
        if Core.UnitTooltip then
            local okTip, errTip = pcall(Core.UnitTooltip.AddSection, cat)
            if not okTip then Core.Error(ADDON, errTip, "Tooltip") end
        end
        if Core.Gathering then
            local okGather, errGather = pcall(Core.Gathering.AddSettings, cat)
            if not okGather then Core.Error(ADDON, errGather, "Gathering") end
        end
        if Core.ItemTooltip then
            local okItem, errItem = pcall(Core.ItemTooltip.AddSettings, cat)
            if not okItem then Core.Error(ADDON, errItem, "ItemTooltip") end
        end
        -- Auktionshaus (Welle 13): Marke „im Auktionshaus mehr wert“, Wochenpunkte des Preisverlaufs
        if Core.Prices and Core.Prices.AddSettings then
            local okPrices, errPrices = pcall(Core.Prices.AddSettings, page)
            if not okPrices then Core.Error(ADDON, errPrices, "Prices") end
        end
        -- Gemeinsame Schalter mehrerer Module (Einstellungs-Prüfung 19.11.2026, Nr. 59/60, 62, 95/96)
        local okShared, errShared = pcall(Core.AddSharedSettings, page)
        if not okShared then Core.Error(ADDON, errShared, "Shared") end
        -- Sammeln (SAM-18, Welle 14): Pflege der eigenen Fundorte, Schalter „Fundorte nicht mehr ändern“
        if Core.Gathering and Core.Gathering.AddCare then
            local okCare, errCare = pcall(Core.Gathering.AddCare, page)
            if not okCare then Core.Error(ADDON, errCare, "GatheringCare") end
        end
        -- Tasten an Blizzards Fenstern (AH-15, Welle 14): je angemeldeter Taste ein Knopf „Taste belegen“
        if Core.Keys and Core.Keys.AddWindowSettings then
            local okKeys, errKeys = pcall(Core.Keys.AddWindowSettings, page)
            if not okKeys then Core.Error(ADDON, errKeys, "WindowKeys") end
        end
        if CreateSettingsListSectionHeaderInitializer and Core.GlowLegend then
            Add(CreateSettingsListSectionHeaderInitializer(L.GLOW_HEADER, L.GLOW_HEADER_TIP .. "\n\n" .. Core.GlowLegend(true)
                .. (Core.Glow and ("\n\n" .. L.GLOW_RANK_TIP:format(Core.Glow.RankText())) or "")))
        end
        -- Farbenblind-Hilfe (V-043): Zeichen zusätzlich zur Farbe
        if Core.Glow and Core.Glow.MarksEnabled then
            page:OwnCheckbox("comfort", "glowMarks", { onChange = function() Core.Glow.MarksChanged() end })
        end
        -- Kennzeichen an Makro-Knöpfen (Welle 15, MacroBadge.lua): Zeichen für „Maus-Überfahren“ und „Durchbuffen“
        if Core.MacroBadge then
            page:OwnCheckbox("comfort", "macroBadge", { feature = "actionBars", onChange = function() Core.MacroBadge.RefreshAll() end })
            -- auch eigene Makros mit Mausziel (Welle 23d, Entscheidung Nr. 37)
            -- grau, solange „Kennzeichen an Makro-Knöpfen“ aus ist (Einstellungs-Prüfung 19.11.2026, Nr. 52)
            page:OwnCheckbox("comfort", "macroBadgeOwn", { feature = "actionBars", parent = "macroBadge",
                onChange = function() Core.MacroBadge.RefreshAll() end })
        end
        -- Daten: Verlauf leeren, Charaktere verwalten (V-004)
        page:Header(L.DATA_HEADER, L.DATA_HEADER_TIP)
        if Core.History and Core.History.ClearAll then
            page:Button(L.HISTORY_CLEAR_LABEL, L.HISTORY_CLEAR_BUTTON, function() Core.AskClearHistory() end, L.HISTORY_CLEAR_TIP)
        end
        -- „Erlebtes in der Datenbank sammeln“ (Spielerschalter mit Datenschutz-Bezug; Einstellungs-Prüfung 19.11.2026)
        if Core.Discovery and Core.Discovery.AddCollectSetting then
            local okCollect, errCollect = pcall(Core.Discovery.AddCollectSetting, page)
            if not okCollect then Core.Error(ADDON, errCollect, "DiscoveryCollect") end
        end
        Core.AddCharRows(page)
        Core.AddGuildRows(page)
        page:Advanced()
        page:Button(L.OVERVIEW_STATUS, L.OVERVIEW_STATUS_BUTTON, Core.PrintStatus, L.OVERVIEW_STATUS_TIP)
        -- Fehlerliste: als Unterseite in Blizzards Einstellungen (V-024), sonst das Fenster
        if Core.RegisterErrorListPage then Core.RegisterErrorListPage() end
        page:Button(L.OVERVIEW_ERRORLIST, L.OVERVIEW_ERRORLIST_BUTTON, function() Core.ShowErrorList() end, L.OVERVIEW_ERRORLIST_TIP)
        page:Button(L.OVERVIEW_ERRORS, L.OVERVIEW_ERRORS_BUTTON, function() Core.AskClearErrors() end, L.OVERVIEW_ERRORS_TIP)
        -- Zurücksetzen der eigenen Schalter (V-018): Komfort, Tooltip, Leucht-Zeichen
        page:ResetButton({ label = L.RESET_OWN_LABEL, ask = L.RESET_OWN_ASK, tip = L.RESET_OWN_TIP })
        if Core.Backup then
            page:Button(L.BACKUP_EXPORT_LABEL, L.BACKUP_EXPORT_BUTTON, function() Core.Backup.ShowExport() end, L.BACKUP_EXPORT_TIP)
            page:Button(L.BACKUP_IMPORT_LABEL, L.BACKUP_IMPORT_BUTTON, function() Core.Backup.ShowImport() end, L.BACKUP_IMPORT_TIP)
        end
        if Core.ResetAllTours then
            page:Button(L.TOURS_ALL_LABEL, L.TOURS_ALL_BUTTON, function() Core.AskResetAllTours() end, L.TOURS_ALL_TIP)
        end
        if Core.Debug then
            page:Button(L.DEBUG_LABEL, L.DEBUG_BUTTON, function() Core.Debug.Toggle() end, L.DEBUG_TIP)
            -- eigener Knopf für den Bericht: „Starten / Stoppen“ würde nach dem Selbststopp neu starten und ihn verwerfen
            page:Button(L.DEBUG_REPORT_LABEL, L.DEBUG_REPORT_BUTTON, function() Core.Debug.Show() end, L.DEBUG_REPORT_TIP)
        end
        if Core.RunSelfTest then
            page:Button(L.SELFTEST_LABEL, L.SELFTEST_BUTTON, function() Core.RunSelfTest() end, L.SELFTEST_TIP)
        end
        if Core.RunSpellCheck then
            page:Button(L.SPELLCHECK_LABEL, L.SPELLCHECK_BUTTON, function() Core.RunSpellCheck() end, L.SPELLCHECK_TIP)
        end
        -- Entwicklerschalter und Testschalter für den Taint-Test (Frage 32, EC-12; Gesamtreview 18.11.2026,
        -- Entscheidung 1): beide Zeilen baut Diagnose.lua, der Testschalter erscheint erst mit dem Entwicklerschalter
        if Core.Debug and Core.Debug.AddDeveloperRows then
            local okDev, errDev = pcall(Core.Debug.AddDeveloperRows, page)
            if not okDev then Core.Error(ADDON, errDev, "Developer") end
        end
        -- Daten-Probe (Probe.lua): Probe an dieser Stelle, Mitschnitt, Tempo, Dokumentation, Sonderproben, Stand, Leeren
        if Core.Probe then
            local okProbe, errProbe = pcall(Core.Probe.AddSettings, page)
            if not okProbe then Core.Error(ADDON, errProbe, "Probe") end
        end
        -- Entdecker-Datenbank (DiscoveryView.lua): Sammeln, Entdecker-Wissen, Größe, Aufräumen (DG-10)
        if Core.Discovery and Core.Discovery.AddSettings then
            local okDB, errDB = pcall(Core.Discovery.AddSettings, page)
            if not okDB then Core.Error(ADDON, errDB, "Discovery") end
        end
        if Core.AddCompanionButtons then
            local okComp, errComp = pcall(Core.AddCompanionButtons, layout, "ezCore")
            if not okComp then Core.Error(ADDON, errComp, "Companions") end
        end
    end
end

-- Im Kampf: Hinweis und nach dem Kampf nachholen (Core.OpenSettingsCategory, Settings.lua; ST-04).
function Core.OpenSettings()
    local cat = Core.SettingsParent()
    if not (cat and Settings and Settings.OpenToCategory) then return false end
    -- Erster Start: beim ersten Öffnen ein kurzer Rundgang (FirstStart.lua); danach tut der Aufruf nichts.
    return Core.OpenSettingsCategory(cat, ADDON, function()
        if Core.FirstStart then Core.Try(nil, "FirstStart.StartTour", Core.FirstStart.StartTour) end
    end)
end

-- „Erklärblasen aller Module erneut zeigen“ mit Rückfrage (betrifft alle Module auf einmal). → Dialog
function Core.AskResetAllTours()
    return Core.Confirm(L.TOURS_ALL_ASK, function()
        ns.Print(L.TOURS_ALL_DONE:format(Core.ResetAllTours()))
    end)
end

-- „Verlauf leeren“ mit Rückfrage (Knopf der Seite „ezCollection“, /ez verlauf leeren). → Dialog
function Core.AskClearHistory()
    local H = Core.History
    local n = H and H.Count and H.Count() or 0
    if n == 0 then
        ns.Print(L.HISTORY_CLEAR_EMPTY)
        return nil
    end
    return Core.Confirm(L.HISTORY_CLEAR_ASK:format(n), function()
        ns.Print(L.HISTORY_CLEAR_DONE:format(H.ClearAll()))
    end, { alert = true })
end
ns.OpenSettings = Core.OpenSettings

---------------------------------------------------------------------------
-- /ezcollection und /ez
---------------------------------------------------------------------------

local function Slash(input)
    local cmd, rest = Core.ParseSlash(input)
    if cmd == "" then
        if not Core.OpenedOrDeferred(Core.OpenSettings) then Core.PrintHelp(ns) end
    elseif cmd == "hilfe" or cmd == "help" then
        Core.PrintHelp(ns)
    elseif cmd == "status" then
        Core.PrintStatus()
    elseif cmd == "fehler" or cmd == "errors" then
        local sub = rest:lower()
        if sub == "leeren" or sub == "clear" then
            Core.AskClearErrors()   -- V-024: mit Rückfrage, wie die Knöpfe
        elseif sub == "kopieren" or sub == "copy" then
            Core.ShowErrorList()
        else
            Core.PrintErrors()
        end
    elseif cmd == "chars" then
        Core.PrintChars(ns)
    elseif cmd == "vergessen" or cmd == "forget" then
        Core.ForgetCommand(ns, rest)
    elseif Core.FindModuleName(cmd) then
        local name = Core.FindModuleName(cmd)
        if not Core.OpenedOrDeferred(function() return Core.OpenModuleSettings(name) end) then
            ns.Print(L.MODULE_OFF:format(name))
        end
    -- Werkzeuge der Basis (jedes hat seinen Knopf auf der Seite „ezCollection“); ein Modul gleichen Namens ginge vor
    elseif cmd == "debug" then
        Core.Debug.Command(rest)
    elseif cmd == "test" then
        Core.RunSelfTest()
    elseif cmd == "zauber" or cmd == "spells" then
        Core.RunSpellCheck()
    elseif cmd == "probe" then
        Core.Probe.Command(rest)
    elseif cmd == "sichern" or cmd == "export" then
        Core.Backup.ShowExport()
    elseif cmd == "übernehmen" or cmd == "Übernehmen" or cmd == "uebernehmen" or cmd == "import" then
        Core.Backup.ShowImport()
    elseif cmd == "start" then
        Core.FirstStart.Show()
    elseif Core.SlashWord(cmd) == "einfuehrung" or cmd == "intro" then
        Core.Intro.Command(rest)
    elseif cmd == "beitrag" or cmd == "contribute" then
        Core.Contribute.Prepare()
    elseif cmd == "mithelfen" or cmd == "helpout" then
        Core.Contribute.ShowHelp()
    elseif cmd == "verlauf" or cmd == "history" then
        Core.AskClearHistory()
    else
        Core.PrintHelp(ns)
    end
end

SLASH_EZCOLLECTION1 = "/ezcollection"
SlashCmdList.EZCOLLECTION = Slash
-- Für Core.SlashCmd (ohne Modul): /ez nur, wenn der Kurzbefehl beim Einloggen frei war (ns.slashAlias, unten)
ns.slashCommand = SLASH_EZCOLLECTION1

-- Addon-Fach an der Minikarte: Klick öffnet die Seite „ezCollection“ (sonst die Hilfe), Tooltip mit Befehl (EC-87:
-- alle drei Compartment-Zeilen in jeder TOC). Der Befehl ist der geltende (Gegenprüfung D1, T18-2): „/ez“ nur, wenn
-- ihn kein anderes Addon belegt, sonst „/ezcollection“.
ezCore_OnAddonCompartmentClick, ezCore_OnAddonCompartmentEnter, ezCore_OnAddonCompartmentLeave = Core.CompartmentHandlers({
    title = "ezCollection",
    lines = function()
        local cmd = Core.SlashCmd(ns)
        return { L.COMPARTMENT_SETTINGS, L.COMPARTMENT_HELP:format(cmd, cmd) }
    end,
    owner = ADDON,
    onClick = function()
        if not Core.OpenedOrDeferred(Core.OpenSettings) then Core.PrintHelp(ns) end
    end,
})

---------------------------------------------------------------------------
-- Start: nach allen Modulen (deren PLAYER_LOGIN-Handler laufen nach diesem)
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    ns.RunReady()
    Core.SettingsParent()
    C_Timer.After(0, function()
        -- Jetzt haben alle Module ihre Unterseiten angelegt: Übersicht bauen und die Kategorie anmelden.
        local ok, err = pcall(BuildOverview)
        if not ok then Core.Error(ADDON, err, "Settings") end
        ok, err = pcall(Core.RegisterSettingsParent)
        if not ok then Core.Error(ADDON, err, "Settings") end
        ns.slashAlias = Core.AddSlashAlias("EZCOLLECTION", 2, { "/ez" }, Slash)
    end)
end)
