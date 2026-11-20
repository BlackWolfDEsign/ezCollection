local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    ezHeal – Heilen, Bannen, Wiederbeleben und Buffen per Klick auf Blizzards Gruppen- und Raidrahmen.
    Kein eigenes Fenster, keine eigenen Einheitenrahmen: ezHeal legt Vorlagen auf Blizzards eigenes Klick-Zaubern
    (ezCore.ClickBindings) und hängt die eigenen HoTs als Blizzards Auren-Reihe an Blizzards Rahmen.

      Templates.lua  Vorlagen je Klasse, Vorschau, Übernehmen (sichert vorher), Zurück
      Profiles.lua   benannte Profile der Klick-Belegung: speichern, laden, löschen, teilen (ezCore.ClickBindings)
      Macros.lua     Heil-Makros je Klasse in Blizzards Makrofenster: Vorschau, anlegen (mit Rückfrage), entfernen
      Legend.lua     Klick-Legende im Tooltip von Blizzards Gruppen- und Raidrahmen (ezCore.Tooltip.AddUnitSection)
      HoTs.lua       eigene HoTs als abschaltbare Symbolreihe an Blizzards Rahmen (ezCore.GroupFrames, ezCore.AuraRow)
      Blizzard.lua   Knopf „Vorlagen“ an Blizzards Fenster „Klick-Zauber“
      Preview.lua    Vorschau mit Tastenwahl je Platz in Blizzards Fenster „Klick-Zauber“ (über der Liste)
      Entries.lua    weitere Einstiege zu Blizzards Fenster: Schlachtzug-Liste, Gruppenverwaltung, Zauberbuch, Makros
      Tour.lua       Rundgang mit Erklärblasen beim ersten Öffnen von Blizzards Fenster „Klick-Zauber“
      Options.lua    Einstellungsseite (ezCollection → ezHeal)

    Geändert wird die Klick-Belegung nur außerhalb des Kampfes. Was ein anderes Addon schon übernimmt (Clique,
    HealBot, VuhDo, Grid2, Cell), erkennt ezCore (Core.WhoHandles "clickCast" / "healFrames"); ezHeal nennt es.
]]

ns.DEFAULTS = {
    template = "heal",      -- gewählte Vorlage: "heal" | "buffs" | "all"
    hots = true,            -- eigene HoTs als Symbolreihe an Blizzards Gruppen- und Raidrahmen
    clickLegend = true,     -- Klick-Legende im Tooltip von Blizzards Gruppen- und Raidrahmen (Legend.lua, HL-01)
    -- weitere Einstiege zu Blizzards Fenster „Klick-Zauber“ (Entries.lua, HL-07), je abschaltbar
    entryRaid = true,       -- Seitenreiter an der Schlachtzug-Liste (Kontakte)
    entryGroup = true,      -- Knopf in der Gruppen- und Raidverwaltung
    entrySpellbook = true,  -- Seitenreiter am Zauberbuch
    entryMacro = true,      -- Knopf in der Titelleiste des Makrofensters
}

-- Befehle zusätzlich zu den Standardwörtern des Gerüsts (Optionen, Status, Hilfe)
local COMMANDS = {
    vorschau = "preview", preview = "preview",
    anwenden = "apply", ["übernehmen"] = "apply", uebernehmen = "apply", apply = "apply",
    ["zurück"] = "undo", zurueck = "undo", undo = "undo",
    anfang = "first", first = "first",
    fenster = "window", window = "window",
    tasten = "keys", keys = "keys",
    makros = "macros", macros = "macros",
}

local function Slash(cmd)
    local what = COMMANDS[cmd or ""]
    if not what then return false end
    if what == "preview" then
        ns.PrintPreview()
    elseif what == "apply" then
        ns.AskApply()
    elseif what == "undo" then
        ns.AskRestore()
    elseif what == "first" then
        ns.AskRestore("first")
    elseif what == "window" then
        ns.OpenBlizzard()
    elseif what == "keys" then
        ns.Preview.Open()
    elseif what == "macros" then
        ns.AskMacros()
    end
    return true
end

-- core 1.12.0: Tastentexte und Urheber der Sicherung in Core.ClickBindings (EC-109, EC-115), Core.TextDialog und das
-- Ziel „raidframes“ von Core.OpenPanel. needs: Fähigkeiten statt Versionsnummer – scaffoldHelpers (ns.OtherFor,
-- ns.InCombat des Gerüsts), Now und Spells.HealSpells (Klassen-Wissen Heilen, Bannen, Wiederbeleben aus ezCore
-- Welle 8, ohne neue Nummer; die Vorlagen lesen nur noch dort, HL-03). Die Heil-Makros (Macros.lua) brauchen dazu
-- ezCores Makro-Logik (Spells.MacroLogic, Spells.MacroCondition) und Core.TruncateChars für den Makronamen; die
-- Vorschau Farb-Rollen aus Core.Style (Style.Color, Welle 22). Welle 23: Makros über ezCores Dienst „Makro anlegen“
-- (Macro.Find/Write/Limits/Free), Kennzeichen am Aktionsknopf (MacroBadge.Register), Textfarbe der Vorschau
-- (Style.SetTextColor statt Style.Color), Rest der Klick-Legende (More) und Einheit des Rahmen-Tooltips
-- (GroupFrames.TooltipUnit).
-- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CombatNotice, Core.HelpLines, Core.TipDoubleLine, Core.Tooltip.Gap
-- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
Core.NewModule(ADDON, ns, { title = "ezHeal", db = "ezHealDB", login = true, core = "1.15.0",
    needs = { "ClickBindings", "scaffoldHelpers", "Now", "Spells.HealSpells", "Spells.MacroLogic", "Spells.MacroCondition",
        "TruncateChars", "Style.SetTextColor", "Macro.Find", "Macro.Write", "Macro.Limits", "Macro.Free", "MacroBadge.Register",
        "More", "GroupFrames.TooltipUnit",
        -- Welle 27 (kern/buff-schnittstelle, ohne neue Nummer): Buff-Wissen nur über ezCores Leseschnittstelle (F7)
        "Spells.BuffField",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2): Addon-Fach und Befehl ohne Wort nach Entscheidung 5,
        -- Hilfe aus ezCore, Kampfsperre in ezCores Wortlaut, Menüeintrag und Auswahlfeld aus ezCore
        "compartmentMain", "slashMain", "CombatNotice", "Menu.Settings", "Menu.Dropdown",
        -- Tooltip-Zeilen mit Rollen statt Farbzahlen (T9-6)
        "TipLine", "TipDoubleLine",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText" },
    -- main: „/ezheal“ ohne Wort öffnet wie der Linksklick im Addon-Fach Blizzards Fenster „Klick-Zauber“ (Entscheidung 5,
    -- T18-3); reset: „/ezheal zuruecksetzen“ fragt wie der Knopf „Einstellungen zurücksetzen“ (T18-20)
    slash = { extra = Slash, main = function() ns.OpenBlizzard() end, mainText = L.MAIN_TEXT, reset = true } })

ns.OnReady(function() ns.playerClass = Core.PlayerClass() end)

-- Ein Twink wird vergessen (/ez vergessen): seine eigenen Tasten der Vorlagen auch (db.keys[charKey], Templates.lua).
if Core.Listen then
    Core.Listen("CHAR_FORGOTTEN", function(key)
        if ns.db and type(ns.db.keys) == "table" and key then ns.db.keys[key] = nil end
        -- und was ezHeal auf ihm geschrieben hat (db.applied[charKey], Templates.lua)
        if ns.Templates then ns.Templates.ForgetApplied(key) end
        -- und welche Makros ezHeal auf ihm angelegt hat (db.macros[charKey], Macros.lua)
        if ns.Macros then ns.Macros.Forget(key) end
    end, ADDON)
end

-- Wer übernimmt gerade Klick-Zaubern bzw. die Heilrahmen? → Anzeigename oder nil (Leitlinie 9, Liste in ezCore;
-- ns.OtherFor des Gerüsts fragt Core.WhoHandles, innen gesichert)
function ns.ClickCaster()
    return (ns.OtherFor("clickCast"))
end

function ns.FrameReplacer()
    return (ns.OtherFor("healFrames"))
end

-- Kampfsperre in ezCores Wortlaut (Gesamtreview 18.11.2026, T18-1): Text bzw. Meldung im Chat; what = L.*_COMBAT_WHAT
function ns.CombatText(what) return Core.CombatText(what or L.APPLY_COMBAT_WHAT) end
function ns.CombatNotice(what) return Core.CombatNotice(ns, what or L.APPLY_COMBAT_WHAT) end

-- Hinweise zu fremden Addons (für Vorschau und Status)
function ns.OtherHints()
    local lines = {}
    local clique = ns.ClickCaster()
    if clique then lines[#lines + 1] = L.CLIQUE_HINT:format(clique, clique) end
    local frames = ns.FrameReplacer()
    if frames then lines[#lines + 1] = L.FRAMES_HINT:format(frames) end
    return lines
end

-- Blizzards Fenster „Klick-Zauber“ öffnen (sichtbarer Weg: Einstellungen „Öffnen“, Befehl /ezheal fenster)
function ns.OpenBlizzard()
    local CB = Core.ClickBindings
    if not (CB and CB.Available()) then
        ns.Print(L.ERR_missing)
        return false
    end
    return CB.Open()
end

-- Blizzards Optionen der Raidrahmen öffnen (HL-09, Knopf unter „Anzeige“): für alles, was Blizzards Rahmen schon zeigen
-- Weg zu den Optionen für den Hinweis: Namen aus dem Client (Leitlinie 11), sonst ezHeals Ersatz
local function ClientName(get, fallback)
    local ok, value = pcall(get)
    value = ok and Core.Plain(value) or nil
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

function ns.RaidFramesPath()
    local menu = ClientName(function() return rawget(_G, "GAMEMENU_OPTIONS") end, L.RAIDFRAMES_MENU)
    local category = ClientName(function()
        local settings = rawget(_G, "Settings")
        local id = settings.INTERFACE_CATEGORY_ID
        if Core.IsSecret(id) or id == nil then return nil end
        return settings.GetCategory(id):GetName()
    end, L.RAIDFRAMES_CATEGORY)
    local section = ClientName(function() return rawget(_G, "RAID_FRAMES_LABEL") end, L.RAIDFRAMES_SECTION)
    return menu, category, section
end

function ns.OpenRaidFrameOptions()
    local ok, reason = Core.OpenPanel("raidframes")
    -- Im Kampf meldet Core.OpenPanel das schon selbst (Core.CombatNotice mit PANEL_WHAT); ein Wegweiser hülfe da nicht
    if not ok and reason ~= "combat" then ns.Print(L.ERR_raidframes:format(ns.RaidFramesPath())) end
    return ok and true or false, reason
end

-- Status (/ezheal status, Knopf unter „Erweitert“)
ns.AddStatusLine(function()
    local CB = Core.ClickBindings
    if not (CB and CB.Available()) then return L.STATUS_NO_CB end
    local lines = { L.STATUS_TEMPLATE:format(ns.KindLabel(ns.S and ns.S.template)) }
    local applied = ns.Templates and ns.Templates.Applied()   -- je Charakter (Fund H1)
    if type(applied) == "table" and applied.kind then
        lines[#lines + 1] = L.STATUS_APPLIED:format(ns.KindLabel(applied.kind), tonumber(applied.count) or 0)
    end
    lines[#lines + 1] = L.STATUS_HOTS:format(ns.Enabled("hots") and L.ON or L.OFF, ns.HoTs and ns.HoTs.Count() or 0)
    if ns.Legend then lines[#lines + 1] = ns.Legend.StatusLine() end
    local macros = ns.Macros and ns.Macros.StatusLine()
    if macros then lines[#lines + 1] = macros end
    for _, hint in ipairs(ns.OtherHints()) do lines[#lines + 1] = hint end
    return lines
end)

-- Addon-Fach an der Minikarte (EC-87: alle drei Compartment-Zeilen in jeder TOC), nach Entscheidung 5 vom 18.11.2026
-- (Gesamtreview T18-3, T16-10): Linksklick öffnet Blizzards Fenster „Klick-Zauber“ (dort hängt ezHeal seine Vorlagen
-- an), Rechtsklick die Einstellungen; Tooltip, Befehlszeile und Fehlerfang von ezCore (Core.CompartmentHandlers).
ezHeal_OnAddonCompartmentClick, ezHeal_OnAddonCompartmentEnter, ezHeal_OnAddonCompartmentLeave = Core.CompartmentHandlers({
    ns = ns, title = ADDON, main = function() ns.OpenBlizzard() end, mainText = L.MAIN_TEXT,
})
