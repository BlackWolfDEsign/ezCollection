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
      Dock.lua       Blizzards Fenster „Klick-Zauber“ dockt rechts am Zauberbuch an und wandert mit
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
    dockSpellbook = true,   -- Blizzards Fenster „Klick-Zauber“ rechts am Zauberbuch, wandert mit (Dock.lua)
    pairSpellbook = true,   -- Klick-Zauber zu: Zauberbuch bleibt offen; Zauberbuch zu: Klick-Zauber geht mit (Dock.lua)
    -- Blizzards „Selbstwirken: Automatisch“ einmal aus („Tastendruck“; Entscheidung des Nutzers vom 23.11.2026, „Ja, genau
    -- so“); aus = alter Wert zurück (ns.SelfCastApply/ns.SelfCastRestore unten)
    noAutoSelfCast = true,
}

-- Neu seit v1.0.0-beta3 und ab Werk an; Einträge bleiben stehen (ezCore, Werkzeuge/ConsentNews.lua: Intro.NewsOnRows;
-- Nutzer am 24.11.2026): Die Blase „Neu seit dem Update“ nennt sie einmal mit gesetztem Häkchen. tools/Tests/agree_test.lua
-- ist rot, wenn ein neuer Schalter mit true hier fehlt.
ns.NEWS = { "noAutoSelfCast" }

-- Befehle zusätzlich zu den Standardwörtern des Gerüsts (Optionen, Status, Hilfe)
local COMMANDS = {
    vorschau = "preview", preview = "preview",
    anwenden = "apply", ["übernehmen"] = "apply", uebernehmen = "apply", apply = "apply",
    ["zurück"] = "undo", zurueck = "undo", undo = "undo",
    anfang = "first", first = "first",
    fenster = "window", window = "window",
    tasten = "keys", keys = "keys",
    makros = "macros", macros = "macros",
    ["menü"] = "menu", menue = "menu", menu = "menu",
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
    elseif what == "menu" then
        ns.MenuClick.Ask()
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
        "CombatText",
        -- Blizzards Selbstwirken lesen und dessen Option öffnen (Fehler vom 23.11.2026; ohne neue Nummer)
        "ClickBindings.SelfCastKey", "ClickBindings.HitsSelfCast", "ClickBindings.AutoSelfCast", "Panels.SettingsIDByName",
        "SettingsPathText",
        -- „Menü“ und „Ziel“ auf ihren Tasten (Spieltest 24.11.2026; ohne neue Nummer)
        "ClickBindings.Interactions", "ClickBindings.RestoreInteractions" },
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
        -- und die Meldung zu Menü und Ziel (db.menuClick[charKey], MenuClick.lua)
        if ns.MenuClick then ns.MenuClick.Forget(key) end
        -- und seinen gemerkten Wert für „Selbstwirken“, wenn das Spiel ihn je Charakter speichert (db.selfCast.chars)
        local selfCast = ns.db and ns.db.selfCast
        if type(selfCast) == "table" and type(selfCast.chars) == "table" and key then selfCast.chars[key] = nil end
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

-- Blizzards „Selbstwirken“ (Fehler des Nutzers vom 23.11.2026: Klick auf den Rahmen eines Mitspielers außer Reichweite
-- wirkte auf ihn selbst). Ursache im Spiel, nicht in der Belegung: ezHeal belegt Zauber ohne Makro und ohne Rückfall,
-- Blizzards Rahmen gibt seine Einheit an C_ClickBindings.ExecuteBinding – mit „Automatisch“ fällt ein Zauber auf einen
-- Mitspieler außer Reichweite trotzdem auf dein Ziel bzw. dich zurück (Spielfehler, Kommentar bei
-- Core.ClickBindings.SelfCastKey). Abfangen kann ezHeal das nicht (Reichweite ist im Kampf gesperrt, den Zauber wirkt
-- das Spiel); ezHeal sagt es und öffnet Blizzards Option – umstellen tut der Spieler selbst, ezHeal ändert nichts.
-- Weg zur Option: Namen aus dem Client (Leitlinie 11), sonst ezHeals Ersatz
function ns.SelfCastPath()
    local menu = ClientName(function() return rawget(_G, "GAMEMENU_OPTIONS") end, L.RAIDFRAMES_MENU)
    local category = ClientName(function() return rawget(_G, "COMBAT_LABEL") end, L.SELFCAST_CATEGORY)
    local option = ClientName(function() return rawget(_G, "SELF_CAST") end, L.SELFCAST_OPTION)
    return menu, category, option
end

-- „Selbstwirken: Automatisch“ an? → true | false | nil (nicht lesbar; Core.ClickBindings.AutoSelfCast)
function ns.AutoSelfCast()
    local CB = Core.ClickBindings
    if not (CB and type(CB.AutoSelfCast) == "function") then return nil end
    return CB.AutoSelfCast()
end

-- Name der empfohlenen Stellung „Tastendruck“ (Blizzards SELF_CAST_KEY_PRESS, sonst ezHeals Ersatz)
function ns.SelfCastKeyPress()
    return ClientName(function() return rawget(_G, "SELF_CAST_KEY_PRESS") end, L.SELFCAST_KEY_PRESS)
end

-- Weg zum Schalter „Selbstwirken ab Werk aus“ (ezCores Core.SettingsPathText, Einheit T18-18)
function ns.SelfCastSettingPath()
    return Core.SettingsPathText(ADDON, "OPT_HEADER_BINDINGS", "OPT_noAutoSelfCast", L)
end

-- Hinweis für Vorschau, Rückfrage und Status, solange „Automatisch“ an ist → Text | nil. Inhalt nach der Entscheidung
-- des Nutzers vom 23.11.2026: Empfohlen ist „Tastendruck“ (oder der Schalter „Selbstwirken ab Werk aus“).
function ns.AutoSelfCastHint()
    if not ns.AutoSelfCast() then return nil end
    return L.SELFCAST_AUTO_HINT:format(ns.SelfCastKeyPress(), ns.SelfCastPath())
end

-- Blizzards „Selbstwirken“ ab Werk auf „Tastendruck“ (Entscheidung des Nutzers vom 23.11.2026: „kein umbau, beim
-- zustimmen hinweis geben dass standardmäßig aus“, nach der Rückfrage „Ja, genau so“). Schalter noAutoSelfCast (ab Werk
-- an): stellt die CVar autoSelfCast EINMAL auf 0 – die Selbstwirk-Taste bleibt, also „Tastendruck“ bzw. „Keine“ ohne
-- Taste (Forever-Quelle Blizzard_SettingsDefinitions_Frame/Combat.lua: die Option ist ein Proxy, der autoSelfCast und
-- SELFCAST direkt liest). Der alte Wert wird gemerkt (ezHealDB.selfCast = { applied, saved }, je Charakter unter
-- selfCast.chars, wenn das Spiel die CVar je Charakter speichert); Schalter aus holt ihn
-- zurück. Stellt der Spieler „Selbstwirken“ danach in Blizzards Einstellungen selbst um, gilt seine Wahl (store.own,
-- ns.SelfCastSettingsClosed). Steht „Automatisch“ beim Anmelden wieder an, ohne dass er es war – etwa weil das Spiel seine
-- Kontowerte erst danach lädt (ACCOUNT_CVARS_LOADED) –, stellt ezHeal erneut um und sagt es
-- (Meldung des Nutzers vom 24.11.2026, wörtlich „ezheal immernoch ein problem: ich will kollegen aus gruppe heilen der
-- außer range ist, und es heilt dann mich“; vorher einmal und nie wieder). Nur außerhalb des Kampfes (sonst danach,
-- ns.AfterCombat), über die C-Funktion C_CVar.SetCVar (Core.SetCVar) – kein Setting-Objekt aus Addon-Code (Taint).
-- Übernimmt ein fremdes Addon die Option (Core.WhoHandles("autoSelfCast"), Leitlinie 9), hält sich ezHeal zurück.
local SELFCAST_WAIT = "selfCast"
ns.SELFCAST_RECHECK = 5     -- Sekunden: zweiter Blick nach dem Anmelden
local failedSaid            -- „Das Spiel hat abgelehnt“ beim Anmelden schon gesagt

-- Speichert das Spiel „Selbstwirken“ je Charakter (C_CVar.GetCVarInfo, viertes Ergebnis isStoredServerCharacter), merkt
-- sich ezHeal den alten Wert je Charakter (selfCast.chars[charKey]) – sonst stellte nur der erste Charakter um
-- (Review 23.11.2026; ob Forever die CVar je Konto oder je Charakter speichert, prüft „Im Spiel prüfen“ Punkt 14).
local function SelfCastPerChar()
    local info = C_CVar and C_CVar.GetCVarInfo
    if type(info) ~= "function" then return false end
    local ok, value, _, _, perChar = pcall(info, "autoSelfCast")
    if not ok or Core.IsSecret(value) or Core.IsSecret(perChar) or value == nil then return false end
    return perChar == true
end
ns.SelfCastPerChar = SelfCastPerChar

local function SelfCastStore()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.selfCast) ~= "table" then db.selfCast = {} end
    local store = db.selfCast
    if not SelfCastPerChar() then return store end
    local key = ns.charKey or Core.charKey
    if type(key) ~= "string" or key == "" then return nil end
    if type(store.chars) ~= "table" then store.chars = {} end
    if type(store.chars[key]) ~= "table" then store.chars[key] = {} end
    return store.chars[key]
end
ns.SelfCastStore = SelfCastStore

-- Lehnt das Spiel den Wert ab, sagt es der Chat – auch nach dem Warten aufs Kampfende und beim Anmelden, darum hier
-- und nicht im Aufrufer (Review 23.11.2026).
local function SelfCastFailed(login)
    if not (login and failedSaid) then ns.Print(L.SELFCAST_FAILED:format(ns.SelfCastPath())) end
    failedSaid = failedSaid or login
    return false, "failed"
end

-- Umstellen (Schalter an): einmal; login: beim Anmelden auch erneut, wenn „Automatisch“ ohne den Spieler wieder an ist.
-- → true | false, "done" | "off" | "other" | "unknown" | "combat" | "failed"
function ns.SelfCastApply(login)
    local store = SelfCastStore()
    if not store then return false, "unknown" end
    if not ns.Enabled("noAutoSelfCast") then return false, "off" end
    local again = store.applied == true
    if again and (not login or store.own or not ns.AutoSelfCast()) then return false, "done" end
    if ns.OtherFor("autoSelfCast") then return false, "other" end
    local auto = ns.AutoSelfCast()
    if auto == nil then return false, "unknown" end
    if Core.InCombat() then
        ns.AfterCombat(function() ns.SelfCastApply(login) end, SELFCAST_WAIT)
        return false, "combat"
    end
    if auto then
        local old = Core.Plain(Core.CVar("autoSelfCast"))
        if not Core.SetCVar("autoSelfCast", "0") then return SelfCastFailed(login) end
        if not again or store.saved == nil then store.saved = type(old) == "string" and old ~= "" and old or "1" end
        ns.Print((again and L.SELFCAST_AGAIN or L.SELFCAST_SWITCHED_OFF):format(ns.SelfCastKeyPress(), ns.SelfCastSettingPath()))
    end
    store.applied = true
    return true
end

-- Alten Wert zurück (Schalter aus). → true | false, "on" | "unknown" | "combat" | "failed"
function ns.SelfCastRestore()
    local store = SelfCastStore()
    if not store then return false, "unknown" end
    if ns.Enabled("noAutoSelfCast") then return false, "on" end
    if Core.InCombat() then
        ns.AfterCombat(function() ns.SelfCastRestore() end, SELFCAST_WAIT)
        return false, "combat"
    end
    local saved = store.saved
    if saved ~= nil then
        if not Core.SetCVar("autoSelfCast", saved) then return SelfCastFailed() end
        ns.Print(L.SELFCAST_RESTORED)
    end
    store.saved, store.applied, store.own = nil, nil, nil
    return true
end

-- Hat der Spieler Blizzards Option selbst umgestellt? Nur dort, wo er sie umstellt: Wert beim Öffnen und beim Schließen von
-- Blizzards Einstellungen vergleichen (wie ezQuests World.lua; ein Ereignis sagt nicht, wer es war – das Spiel selbst und
-- andere Addons setzen die CVar auch). „Automatisch“ ist dann seine Wahl (store.own), alles andere wieder ezHeals.
local atOpen
function ns.SelfCastSettingsOpened() atOpen = ns.AutoSelfCast() end

-- → true, wenn eine Wahl des Spielers gemerkt wurde
function ns.SelfCastSettingsClosed()
    local before, auto = atOpen, ns.AutoSelfCast()
    atOpen = nil
    if before == nil or auto == nil or before == auto or not ns.Enabled("noAutoSelfCast") then return false end
    local store = SelfCastStore()
    if not (store and store.applied) then return false end
    store.own = auto or nil
    return true
end

-- Beim Anmelden: Schalter an → einmal umstellen. Schalter aus und auf diesem Charakter noch ein alter Wert gemerkt →
-- zurückholen; der Schalter gilt für das Konto, der Merker je Charakter, wenn das Spiel die CVar je Charakter speichert
-- (sonst bliebe ein Charakter, auf dem der Schalter nicht ausgeschaltet wurde, auf „Tastendruck“; Review 23.11.2026).
function ns.SelfCastOnLogin()
    if ns.Enabled("noAutoSelfCast") then return ns.SelfCastApply(true) end
    local store = SelfCastStore()
    if store and store.saved ~= nil then return ns.SelfCastRestore() end
    return false, "off"
end
ns.OnReady(function()
    ns.Try("Selbstwirken", ns.SelfCastOnLogin)
    C_Timer.After(ns.SELFCAST_RECHECK, function() ns.Try("Selbstwirken", ns.SelfCastOnLogin) end)
    ns.On("ACCOUNT_CVARS_LOADED", function() ns.Try("Selbstwirken", ns.SelfCastOnLogin) end)
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) == "table" and type(panel.HookScript) == "function" then
        panel:HookScript("OnShow", function() ns.Try("Selbstwirken", ns.SelfCastSettingsOpened) end)
        panel:HookScript("OnHide", function() ns.Try("Selbstwirken", ns.SelfCastSettingsClosed) end)
    end
end)
ns.OnSettingChanged(function(key)
    if key ~= "noAutoSelfCast" then return end
    if ns.Enabled("noAutoSelfCast") then ns.SelfCastApply() else ns.SelfCastRestore() end
end)

-- Hinweis beim Zustimmen in ezCores Einführung (Core.Intro.Notes; Wortlaut vom Nutzer am 23.11.2026 bestätigt): mit dem
-- Schalter „Selbstwirken ist ab Werk aus …“; ohne ihn, solange „Automatisch“ an ist, die Empfehlung „Tastendruck“
-- „ab Werk aus“ nur, wenn es auch wirklich aus ist (hat der Spieler danach wieder „Automatisch“ gewählt oder ist noch
-- nichts umgestellt, gilt die Empfehlung bzw. nichts; Review 23.11.2026). Anzeige: ns.OtherInfo zählt nicht als „gewichen“.
ns.AGREE_NOTE = function()
    local auto = ns.AutoSelfCast()
    if ns.Enabled("noAutoSelfCast") and auto == false and not ns.OtherInfo("autoSelfCast") then
        local CB = Core.ClickBindings
        local key = CB and type(CB.SelfCastKey) == "function" and CB.SelfCastKey() or nil
        if key and ns.Templates then return L.SELFCAST_OFF_NOTE:format(ns.Templates.SelfCastText(key)) end
        return L.SELFCAST_OFF_NOTE_NOKEY
    end
    if not ns.AutoSelfCast() then return nil end
    return L.SELFCAST_AGREE_NOTE:format(ns.SelfCastKeyPress(), ns.SelfCastPath())
end

-- Knopf „Selbstwirken – Blizzards Option öffnen“ (Einstellungen, „Klick-Belegung“): Blizzards Kampf-Optionen bei der
-- Zeile „Selbstwirken“ (Core.OpenPanel("combat")); geht es nicht, nennt ein Hinweis den Weg
function ns.OpenSelfCastOptions()
    local ok, reason = Core.OpenPanel("combat", "SELF_CAST")
    if not ok and reason ~= "combat" then ns.Print(L.ERR_selfcast:format(ns.SelfCastPath())) end
    return ok and true or false, reason
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
    -- wo Blizzards „Ziel“ und „Menü“ liegen (Spieltest 24.11.2026)
    local menuClick = ns.MenuClick and ns.MenuClick.StatusLine()
    if menuClick then lines[#lines + 1] = menuClick end
    -- Blizzards Selbstwirken (Fehler vom 23.11.2026): Taste und „Automatisch“, wie das Spiel sie gerade meldet
    if type(CB.SelfCastKey) == "function" then
        local key, auto = CB.SelfCastKey(), ns.AutoSelfCast()
        lines[#lines + 1] = L.STATUS_SELFCAST:format(key and ns.Templates.SelfCastText(key) or L.SELFCAST_NO_KEY,
            auto == nil and "?" or (auto and L.ON or L.OFF))
    end
    for _, hint in ipairs(ns.OtherHints()) do lines[#lines + 1] = hint end
    return lines
end)

-- Addon-Fach an der Minikarte (EC-87: alle drei Compartment-Zeilen in jeder TOC), nach Entscheidung 5 vom 18.11.2026
-- (Gesamtreview T18-3, T16-10): Linksklick öffnet Blizzards Fenster „Klick-Zauber“ (dort hängt ezHeal seine Vorlagen
-- an), Rechtsklick die Einstellungen; Tooltip, Befehlszeile und Fehlerfang von ezCore (Core.CompartmentHandlers).
ezHeal_OnAddonCompartmentClick, ezHeal_OnAddonCompartmentEnter, ezHeal_OnAddonCompartmentLeave = Core.CompartmentHandlers({
    ns = ns, title = ADDON, main = function() ns.OpenBlizzard() end, mainText = L.MAIN_TEXT,
})
