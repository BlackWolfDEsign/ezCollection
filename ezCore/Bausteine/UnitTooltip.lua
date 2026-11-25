local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Tooltip-Pipeline für Einheiten (Punkt 9): EIN Eintrag bei
    Blizzards TooltipDataProcessor für Spieler und NPCs, wie die Pipeline für Gegenstände in Tooltip.lua.

      ezCore.Tooltip.AddUnitSection(key, order, fn, owner)   fn(tooltip, unit, data) hängt Zeilen an (Module)
      ezCore.UnitTooltip.Enabled(key)                        eingebaute Zeile an? (Schalter und Rücksicht)

    Eingebaut, je ein Schalter auf der Seite „ezCollection“ → „Tooltip“ (ezCoreDB.tooltip):
      health      Lebenspunkte als Zahl: aktuell / maximal (Prozent), freundlich und feindlich – auch gesperrt
                  (Forever sperrt UnitHealth immer): Core.UnitHealthText reicht die Werte unbesehen durch
      target      Ziel der Einheit („Ziel: Name“, Klassenfarbe; „>> Du <<“, wenn du es bist)
      relation    „Gilde und Freunde“: Gildenrang, dazu Freund, Battle.net-Freund, Gildenmitglied (Zeilen guildRank und
                  relation; bis 19.11.2026 zwei Schalter)
      itemLevel   „Itemlevel und Spezialisierung“: Ø-Itemlevel von Spielern – Blizzards eigene Zahl (wie im
                  Betrachten-Fenster), Entscheidung des Nutzers 13.11.2026; bei anderen über „Betrachten“ außerhalb des
                  Kampfes gelesen, je GUID 10 Min. gemerkt – und die Spezialisierung: bei dir der Talentbaum mit den
                  meisten bestätigten Punkten (Core.Talents), bei anderen (falls das Spiel sie kennt) auf demselben Weg
                  wie das Itemlevel; keine Zeile, wenn sie unbekannt ist oder nur die Klasse nennt („Spezialisierung:
                  Paladin“ unter der Klassenzeile, Spieltest 14.11.2026). Bis 19.11.2026 zwei Schalter (Zeile spec)
      ids         „IDs in Tooltips“: NPC-ID (aus der GUID) und die Quest-ID im Questlog (ezQuest liest denselben
                  Schalter: Core.SharedOn("tooltip", "ids")), Standard aus
    Immer an, ohne Schalter (UT.ALWAYS): classColor – Name von Spielern in Klassenfarbe. Die Rücksicht auf fremde
    Tooltip-Addons bleibt (Core.WhoHandles("unitTooltip")).
    Zusammengelegt nach der Einstellungs-Prüfung vom 19.11.2026 (Nr. 3, 47–49, 93; Entscheidung des Nutzers „Ja, alle
    umsetzen“): UT.SWITCH nennt je Zeile ihren Schalter; die alten Werte übernimmt UT.MigrateSwitches einmal (war eine
    der beiden Zeilen an, bleibt der gemeinsame Schalter an).
    Übrige geheime Werte (im Kampf gesperrt) werden ausgelassen, nie verglichen. Nur GameTooltip, nie verbotene Tooltips.
    Hängt ein anderes Addon eigene Quest-Blöcke an NPC-Tooltips (Questie, Core.WhoHandlesInfo("unitQuestLines")),
    schreiben die Abschnitte der Module einen Augenblick später ans Ende (UT.SectionsLater, Tooltip.Later;
    S-1811-Tooltipabstand) – nicht an Einheitenrahmen, deren Tooltip Blizzard alle 0,2 s neu aufbaut (UT.Periodic).
    Läuft TipTac, TinyTooltip oder Leatrix Plus mit „Tooltip verbessern“, bleiben die eingebauten Zeilen aus
    (Core.WhoHandles("unitTooltip")); Abschnitte der Module laufen weiter. Zeigt ein anderes Addon schon Itemlevel
    bzw. Ausrüstungswert (TacoTip, GearScore: Core.WhoHandles("unitItemLevel")), bleibt die Itemlevel-Zeile aus.
    Betrachten über ezCores Betrachten-Dienst (Core.Inspect, Inspect.lua; geteilt mit ezGears Ausrüstungs-Check der
    Gruppe): höchstens alle 1,5 s eine Anfrage, nie im Kampf, nie bei offenem Betrachten-Fenster (Blizzards
    Fenster hat Vorrang); UT.InspectInfo(guid) → Itemlevel, Spezialisierung aus dem Zwischenspeicher.
]]

local UT = {}
Core.UnitTooltip = UT
local Tooltip = Core.Tooltip
local IsSecret = Core.IsSecret

UT.ORDER = { "health", "target", "guildRank", "relation", "itemLevel", "spec", "classColor", "ids" }
-- Schalter je Zeile (fehlt eine Zeile hier, hat sie ihren eigenen); UT.ALWAYS: immer an, kein Schalter
UT.SWITCH = { guildRank = "relation", spec = "itemLevel" }
UT.ALWAYS = { classColor = true }
-- Kästchen in dieser Reihenfolge (die Zeilen guildRank, spec und classColor haben keins)
UT.SWITCHES = { "health", "target", "relation", "itemLevel", "ids" }
UT.DEFAULTS = { health = true, target = true, relation = true, itemLevel = true, ids = false }

local sections = {}

function Tooltip.AddUnitSection(key, order, fn, owner)
    for i = #sections, 1, -1 do
        if sections[i].key == key then table.remove(sections, i) end
    end
    -- order: Zahl oder Name eines Platzes aus Tooltip.UNIT_ORDER (Tooltip.lua)
    sections[#sections + 1] = { key = key, order = Tooltip.Order(order, Tooltip.UNIT_ORDER), fn = fn, owner = owner or Core.name }
    table.sort(sections, function(a, b) return a.order < b.order end)
end

Core.OwnDefaults("tooltip", UT.DEFAULTS)   -- eine Stelle für die Standardwerte (V-018: Core.DEFAULTS.tooltip)

local function DB()
    return Core.OwnSettings("tooltip")
end

function UT.Enabled(key)
    local t = DB()
    if key == "itemLevel" and Core.WhoHandles("unitItemLevel") then return false end
    if Core.WhoHandles("unitTooltip") ~= nil then return false end
    if UT.ALWAYS[key] then return true end
    return t ~= nil and t[UT.SWITCH[key] or key] == true
end

-- Einmalige Übernahme der alten Einzelschalter (Einstellungs-Prüfung 19.11.2026, Nr. 3, 47–49): guildRank geht in
-- relation auf, spec in itemLevel. Beide standen ab Werk an, und Core.FillDefaults hatte das bei jedem Spieler
-- gespeichert – ein gespeichertes „an“ ist also keine Wahl und schaltet den gemeinsamen Schalter nicht wieder ein
-- (Gegenprüfung 19.11.2026: sonst kam ein bewusst ausgeschaltetes „Gilde und Freunde“ zurück); ein „aus“ der alten
-- Zeile schaltet nichts aus. Es gilt also der gespeicherte Wert von relation bzw. itemLevel; die alten Schlüssel
-- entfallen. classColor ist immer an; sein alter Wert wird nicht mehr gelesen und entfällt.
-- db = ezCoreDB (roh, vor dem Auffüllen gelesen). Merker ezCoreDB.migrated.tooltipMerge19. → true, wenn etwas umgestellt
-- wurde
function UT.MigrateSwitches(db)
    if type(db) ~= "table" then return false end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "tooltipMerge19", function()
        local t = db.tooltip
        if type(t) ~= "table" then return false end
        local changed = false
        for old in pairs(UT.SWITCH) do
            if t[old] ~= nil then t[old], changed = nil, true end
        end
        if t.classColor ~= nil then t.classColor, changed = nil, true end
        return changed
    end) == true
end
Core.Listen("CORE_LOADED", function() UT.MigrateSwitches(Core.db) end, "ezCore.UnitTooltip")

-- Wert nur, wenn er nicht geheim ist (sonst nil): ezCores eine Regel (Core.PlainCall, Util.lua).
local Plain = Core.PlainCall

local function UnitOf(tooltip, data)
    local unit
    if tooltip.GetUnit then
        local ok, _, u = pcall(tooltip.GetUnit, tooltip)
        if ok and not IsSecret(u) then unit = u end
    end
    local guid = data and data.guid
    if type(unit) ~= "string" and type(guid) == "string" and not IsSecret(guid) then
        unit = Plain(UnitTokenFromGUID, guid)
    end
    return type(unit) == "string" and unit ~= "" and unit or nil
end

-- Klassen-Token eines Spielers (nil bei NPCs); die Farbe kommt aus Core.ClassColor (eine Quelle).
local function PlayerClass(unit)
    if not Plain(UnitIsPlayer, unit) then return nil end
    local _, class = Plain(UnitClass, unit)
    return type(class) == "string" and class or nil
end

---------------------------------------------------------------------------
-- Betrachten: Ø-Itemlevel und Spezialisierung anderer Spieler
---------------------------------------------------------------------------

-- Sperre, Drossel (1,5 s) und Frist (V-027: 3 s ohne INSPECT_READY = verloren) stehen im Betrachten-Dienst
-- Core.Inspect (Inspect.lua, Gesamtreview 18.11.2026 I3) – eine Stelle für Tooltip und Gruppen-Check.
local Inspect = Core.Inspect
local CACHE_TIME = 600
UT.INSPECT_TIMEOUT = Inspect.TIMEOUT
local inspectCache = {}       -- [guid] = { ilvl, spec, t }
local waiting                 -- GUID, deren Tooltip auf Zeilen wartet

local Clock = Core.Uptime
local InspectOpen = Inspect.WindowOpen

local function Text(value)
    value = Core.Plain(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function SpecName(specID)
    specID = Core.Num(specID)
    if not specID or specID <= 0 then return nil end
    local _, name = Core.Call(rawget(_G, "GetSpecializationInfoByID"), specID)
    return Text(name)
end

-- Eigener Charakter: Blizzards Ø-Itemlevel der angelegten Ausrüstung und der Talentbaum mit den meisten bestätigten
-- Punkten (Core.Talents). Bis zum 24.11.2026 fragte die Zeile GetSpecialization: Die Globale gibt es auf Forever nicht, und
-- die eine Spezialisierung je Klasse hieße wie die Klasse. Ohne Punkte (unter Stufe 10) oder unbekannt: nil.
local function OwnInfo()
    local _, equipped = Core.Call(rawget(_G, "GetAverageItemLevel"))
    equipped = Core.Num(equipped)
    local spec = Core.Talents.TreeName((Core.Talents.MainTree()))
    return equipped and equipped > 0 and math.floor(equipped + 0.5) or nil, spec
end

-- Betrachteter Spieler: Blizzards Zahl (C_PaperDollInfo.GetInspectItemLevel), sonst das Mittel der angelegten Plätze.
-- Plätze fürs Itemlevel: die eine Liste aus EquipSlots.lua (V-178; vorher eine eigene bis Platz 17, ohne Distanz).
-- Die Rechnung steht an EINER Stelle: Core.SlotText.AverageLevel (mit der Zweihänder-Regel; GEAR-11).
local function InspectedLevel(unit)
    return (Core.SlotText.AverageLevel(unit))
end

-- Gemerkte Werte eines Spielers: Itemlevel, Spezialisierung (nil, wenn unbekannt).
function UT.InspectInfo(guid)
    local cached = type(guid) == "string" and inspectCache[guid]
    if not cached then return nil end
    return cached.ilvl, cached.spec
end

local OnInspected   -- unten: Antwort des Betrachten-Dienstes

-- Betrachten anfragen, wenn erlaubt (über Core.Inspect.Request). Rückgabe: true, wenn eine Anfrage läuft.
function UT.Inspect(unit)
    if Core.InCombat() or InspectOpen() then return false end
    if not Plain(UnitIsPlayer, unit) or Plain(UnitIsUnit, unit, "player") then return false end
    local guid = Plain(UnitGUID, unit)
    if type(guid) ~= "string" then return false end
    local cached = inspectCache[guid]
    if Inspect.Pending() ~= guid and cached and Clock() - cached.t < CACHE_TIME then return false end
    return Inspect.Request(unit, OnInspected, Core.name) == true
end

local function AddLevelLine(tooltip, level)
    if level then Core.TipLine(tooltip, L.UT_ITEM_LEVEL:format(level), "normal") end
end

-- Spezialisierung, die etwas sagt: nicht leer, nicht „Unbekannt“/„Keine“ und nicht bloß der Name der Klasse
-- (ohne gewählte Spezialisierung meldet Forever die Klasse – das stünde doppelt zu Blizzards Klassenzeile).
local function Same(a, b)
    return type(a) == "string" and type(b) == "string" and Core.Trim(a):lower() == Core.Trim(b):lower()
end

local function UsefulSpec(spec, unit)
    spec = Text(spec)
    if not spec or Core.Trim(spec) == "" then return nil end
    for _, word in ipairs({ rawget(_G, "UNKNOWN") or false, rawget(_G, "NONE") or false, L.UNKNOWN, L.NONE }) do
        if Same(spec, word) then return nil end
    end
    local className, token = Plain(UnitClass, unit)
    if Same(spec, className) or Same(spec, token) then return nil end
    if type(token) == "string" then
        local female = rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE")
        if Same(spec, Core.ClassName(token)) or (type(female) == "table" and Same(spec, female[token])) then return nil end
    end
    return spec
end
UT.UsefulSpec = UsefulSpec

local function AddSpecLine(tooltip, spec, unit)
    spec = UsefulSpec(spec, unit)
    if spec then Core.TipLine(tooltip, L.UT_SPEC:format(spec), "highlight") end
end

-- Werte für einen Spieler im Tooltip: eigene sofort, andere aus dem Zwischenspeicher (sonst Anfrage).
local function PlayerInfo(unit)
    if not Plain(UnitIsPlayer, unit) then return nil, nil, false end
    if Plain(UnitIsUnit, unit, "player") then
        local level, spec = OwnInfo()
        return level, spec, true
    end
    local guid = Plain(UnitGUID, unit)
    if type(guid) ~= "string" then return nil, nil, false end
    local level, spec = UT.InspectInfo(guid)
    if UT.Inspect(unit) then waiting = guid end
    return level, spec, true
end

-- Antwort des Betrachten-Dienstes (Core.Inspect ruft danach ClearInspectPlayer); unit ist die Einheit der Anfrage oder
-- über die GUID neu gesucht, nil = der Spieler ist nicht mehr zu finden.
OnInspected = function(unit, guid)
    if unit == nil then return end
    local level = InspectedLevel(unit)
    local spec = SpecName((Core.Call((C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization)
        or rawget(_G, "GetInspectSpecialization"), unit)))
    inspectCache[guid] = { ilvl = level, spec = spec, t = Clock() }
    -- Zeigt der Tooltip den Spieler noch, die Zeilen nachtragen.
    if waiting ~= guid then return end
    waiting = nil
    local tip = rawget(_G, "GameTooltip")
    if type(tip) ~= "table" or not (tip.IsShown and tip:IsShown()) then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    local shown = UnitOf(tip, nil)
    if not shown or Plain(UnitGUID, shown) ~= guid then return end
    if UT.Enabled("itemLevel") then AddLevelLine(tip, level) end
    if UT.Enabled("spec") then AddSpecLine(tip, spec, shown) end
    if tip.Show then tip:Show() end
end
-- INSPECT_READY hört der Betrachten-Dienst (eine Stelle); der Name bleibt für Aufrufer und Tests.
UT.OnInspectReady = Inspect.OnReady

UT.LINES = {
    health = function(tooltip, unit)
        -- UnitHealth ist in Forever immer gesperrt: der Text entsteht unbesehen (Core.UnitHealthText), „ok“ ist
        -- der einzige Wert, der geprüft werden darf.
        local ok, text = Core.UnitHealthText(unit)
        if not ok then return end
        local okLine, line = Core.FormatSecret(L.UT_HEALTH, text)
        if okLine then Core.TipLine(tooltip, line, "good") end
    end,
    target = function(tooltip, unit)
        local target = unit .. "target"
        if not Plain(UnitExists, target) then return end
        if Plain(UnitIsUnit, target, "player") then
            Core.TipLine(tooltip, L.UT_TARGET_YOU, "bad")
            return
        end
        local name = Plain(UnitName, target)
        if type(name) ~= "string" or name == "" then return end
        Core.TipLine(tooltip, L.UT_TARGET:format(Core.ClassText(name, PlayerClass(target))), "normal")
    end,
    guildRank = function(tooltip, unit)
        if not Plain(UnitIsPlayer, unit) then return end
        local guild, rank = Plain(GetGuildInfo, unit)
        if type(guild) ~= "string" or type(rank) ~= "string" or rank == "" then return end
        Core.TipLine(tooltip, L.UT_GUILD_RANK:format(rank), "blue")
    end,
    relation = function(tooltip, unit)
        if not Plain(UnitIsPlayer, unit) or Plain(UnitIsUnit, unit, "player") then return end
        local guid = Plain(UnitGUID, unit)
        local parts = {}
        if type(guid) == "string" and C_FriendList and Plain(C_FriendList.IsFriend, guid) then parts[#parts + 1] = L.UT_FRIEND end
        if type(guid) == "string" and C_BattleNet then
            local info = Plain(C_BattleNet.GetAccountInfoByGUID, guid)
            local tag = type(info) == "table" and Text(info.battleTag)
            if tag then parts[#parts + 1] = L.UT_BNET_FRIEND:format(tag:match("^(.-)#") or tag) end
        end
        if Plain(UnitIsInMyGuild, unit) then parts[#parts + 1] = L.UT_GUILDMATE end
        if #parts > 0 then Core.TipLine(tooltip, table.concat(parts, ", "), "blue") end
    end,
    itemLevel = function(tooltip, unit)
        local level = PlayerInfo(unit)
        AddLevelLine(tooltip, level)
    end,
    spec = function(tooltip, unit)
        local _, spec = PlayerInfo(unit)
        AddSpecLine(tooltip, spec, unit)
    end,
    classColor = function(tooltip, unit)
        local color = Core.ClassColor(PlayerClass(unit))
        local name = tooltip.GetName and tooltip:GetName()
        local line = name and _G[name .. "TextLeft1"]
        if color and color.r and line and line.SetTextColor then line:SetTextColor(color.r, color.g, color.b) end
    end,
    ids = function(tooltip, unit, data)
        local guid = data and data.guid
        if type(guid) ~= "string" or IsSecret(guid) then guid = Plain(UnitGUID, unit) end
        if type(guid) ~= "string" then return end
        local id = Core.NpcID(guid)
        if id then Core.TipLine(tooltip, L.UT_NPC_ID:format(id), "hint") end
    end,
}

--[[
    Abschnitte der Module nach fremden Blöcken (S-1811-Tooltipabstand, Gesamtreview 18.11.2026): Questie hängt seine
    Quest-Blöcke im selben Bild hinter ezCores Abschnitte; ezLoots „Beute bei dir“ klebte dann oben an Questies erstem
    Block. Läuft ein Addon mit solchen Blöcken (Core.WhoHandlesInfo("unitQuestLines")), schreiben die Abschnitte der Module
    bei NPCs einen Augenblick später ans Ende (Tooltip.Later) – jeder mit Abstand (Tooltip.Gap). Die eingebauten Zeilen
    (Leben, Ziel …) gehören zu Blizzards Kopf und bleiben sofort; Spieler bekommen von Questie keine Blöcke.
    Nicht bei Tooltips, die Blizzard regelmäßig neu aufbaut (Gegenprüfung): Am Einheitenrahmen (Ziel, Fokus, Boss,
    Gruppe) setzt Blizzard owner.UpdateTooltip, GameTooltip_OnUpdate ruft es alle TOOLTIP_UPDATE_TIME (0,2 s) auf
    (Forever-Quelle Blizzard_UnitFrame/Mainline/UnitFrame.lua, UnitFrame_UpdateTooltip; Blizzard_GameTooltip/Mainline/
    GameTooltip.lua, GameTooltip_OnUpdate). Ein Bild später hieße dort: alle 0,2 s ein Bild ohne die Zeilen, die Höhe
    springt. Dort schreiben die Abschnitte sofort wie vor S-1811, mit Abstand zu Blizzards Kopf (UT.Periodic).
    Nur Auskunft (Core.WhoHandlesInfo): ezCore schreibt weiter, nur später – kein „gewichen“ in /ez status.
    → Name des Addons oder nil
]]

-- Baut Blizzard diesen Tooltip regelmäßig neu auf (UpdateTooltip am Besitzer oder am Tooltip)? Nur gelesen.
function UT.Periodic(tooltip)
    if type(tooltip) ~= "table" then return false end
    local owner
    if type(tooltip.GetOwner) == "function" then
        local ok, o = pcall(tooltip.GetOwner, tooltip)
        if ok and not IsSecret(o) and type(o) == "table" then owner = o end
    end
    for _, t in ipairs({ owner or false, tooltip }) do
        if t then
            local ok, fn = pcall(function() return t.UpdateTooltip end)
            if ok and not IsSecret(fn) and type(fn) == "function" then return true end
        end
    end
    return false
end

function UT.SectionsLater(unit, tooltip)
    if Plain(UnitIsPlayer, unit) then return nil end
    if tooltip ~= nil and UT.Periodic(tooltip) then return nil end
    return Core.WhoHandlesInfo("unitQuestLines")
end

local function OnUnitTooltip(tooltip, data)
    if tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local unit = UnitOf(tooltip, data)
    if not unit then return end
    Tooltip.Begin(tooltip)
    for _, key in ipairs(UT.ORDER) do
        if UT.Enabled(key) then
            local ok, err = pcall(UT.LINES[key], tooltip, unit, data)
            if not ok then Core.Error(Core.name, err, "Tooltip " .. key) end
        end
    end
    local guid = Plain(UnitGUID, unit)
    if not UT.SectionsLater(unit, tooltip) or type(guid) ~= "string" then
        Tooltip.RunSections(tooltip, sections, unit, data)
        return
    end
    -- später: nur, solange der Tooltip noch dieselbe Einheit zeigt (Einheit neu gesucht, „mouseover“ kann wechseln;
    -- mit dem Rückfall über data.guid wie oben, falls GetUnit gesperrt ist – der GUID-Vergleich schützt weiter)
    Tooltip.Later(tooltip, function(tip)
        local now = UnitOf(tip, data)
        if not now or Plain(UnitGUID, now) ~= guid then return end
        Tooltip.RunSections(tip, sections, now, data)
    end, true)
end
UT.OnUnitTooltip = OnUnitTooltip

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

-- Abschnitt „Tooltip“ auf der Seite „ezCollection“ (nach „Komfort“).
local KEYS = { health = "ttHealth", target = "ttTarget", relation = "ttRelation", itemLevel = "ttItemLevel", ids = "ttIDs" }

function UT.AddSection(cat)
    local t = DB()
    if not (cat and t and Settings and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then return end
    local page = Core.ParentPage()
    if not page then return end
    page:Header(L.UT_HEADER, L.UT_HEADER_TIP)
    -- Design-System, Regel 2.11: „Alle auswählen / Alle abwählen“ über den Kästchen der Gruppe. Die Liste entsteht erst
    -- beim Klick, damit auch die später angelegten Schalter der Gruppe (Sammeln, Zählzeilen, Item-Wissen) dabei sind.
    if page.AllToggle then
        page:AllToggle(function()
            local list = {}
            for _, entry in ipairs(page.own or {}) do
                if entry.group == "tooltip" then list[#list + 1] = entry.setting end
            end
            return list
        end, { label = L.UT_HEADER })
    end
    for _, key in ipairs(UT.SWITCHES) do
        page:OwnCheckbox("tooltip", key, { text = KEYS[key], variable = "ezCore_tt_" .. key, feature = "unitTooltip" })
    end
end
