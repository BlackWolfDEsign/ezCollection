local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Symbole über Quest-Objekten, Kräutern und Erzadern in der Welt (Wunsch des Nutzers vom 15.11.2026: „sparkles bei
    questgegenstände und questobjekte, ressourcen und co“).
    Grenze, ehrlich: Ein Addon kann Spielobjekte in der 3D-Welt nicht selbst funkeln oder leuchten lassen. Das Funkeln
    an Quest-Objekten zeichnet der Client selbst; in Forevers Seiten Steuerung, Interface und Barrierefreiheit gibt es
    dafür keinen Schalter (Forever-Quelle, Blizzard_SettingsDefinitions_Frame – nachgelesen am 15.11.2026). Zurück
    kommt es über Blizzards Umriss-Modus der Grafik und eine Client-Einstellung – das macht Sparkle.lua (Schalter
    worldSparkle, Blizzards Werte in ezQuestDB.sparkleSaved; dieselben Helfer wie hier). Daneben gibt es Blizzards
    Interaktionssystem (beim Nutzer unter Optionen » Spiel » Steuerung sichtbar,
    Bildschirmfoto vom 15.11.2026, Build 70938): Über dem Objekt, auf das die Interaktionstaste gerade zielt, zeigt
    Blizzard ein Symbol – Hand, Kraut, Spitzhacke, Zahnrad. Welche Arten ein Symbol bekommen, steuern CVars, die
    Blizzards eigene Auswahl „Interaktionssymbole“ (Barrierefreiheit » Allgemein, PROXY_INTERACT_ICONS) setzt:
      SoftTargetIconGameObject  Spielobjekte (Kräuter, Erzadern, Truhen, Quest-Objekte) – ab Werk aus
      SoftTargetIconInteract    NPCs und Objekte, mit denen man sprechen bzw. die man benutzen kann – ab Werk an
    ezQuest schaltet beide an (Schalter worldIcons; ab Werk aus seit Welle 29, weil es ohne Klick Blizzards Einstellung
    umstellt – Entscheidung des Nutzers vom 18.11.2026, wörtlich „Ab Werk aus, mit Hinweis“; Hinweis an der
    Questverfolgung, World.RegisterOptInHints unten), nur die, die der Client kennt und ein Addon setzen darf
    (C_CVar.GetCVarInfo zur Laufzeit), nur außerhalb des Kampfes (Leitlinie 5). Blizzards eigene Werte merkt sich ezQuest
    vorher (ezQuestDB.worldSaved) und gibt sie zurück: beim Ausschalten und bei jedem Abmelden bzw. /reload
    (PLAYER_LOGOUT; beim Anmelden setzt ezQuest sie wieder) – so steht nach dem Abschalten des Addons Blizzards Wert in
    der Konfiguration. Ändert der Spieler eine der CVars in Blizzards Einstellungen, gilt das: ezQuest vergisst den
    gemerkten Wert und schaltet seinen Schalter aus (Rücksicht, Leitlinie 9). Ein Addon, das dieselben CVars setzt,
    ist nur Forever Loot Sparkles in den Fassungen 1.2.0 bis 1.3.1 (laut seiner Beschreibung; docs/fremd-addons.md):
    Läuft eine solche Fassung (erkannt wie beim Funkeln über ezCores Funktion questSparkle, dazu die Version aus seiner
    TOC; World.Other), tritt ezQuest zurück – setzt nichts, gibt nichts zurück, setzt nicht dagegen, der Schalter ist
    grau mit Grund im Tooltip (Welle 23; Entscheidung des Nutzers vom 16.11.2026, vorläufig nach Empfehlung). Kennt
    der Client die Version nicht, gilt die Fassung als neu (die setzt die CVars nicht). Das gilt für jede Wahl in
    Blizzards Auswahl, auch „Alle“, die die
    Objekt-Symbole ebenfalls auf „an“ stellt; ezQuest beobachtet dafür auch die beiden CVars, die nur diese Auswahl
    setzt (World.EXTRA). Grenze: Bei ezQuests Stand zeigt Blizzards Auswahl „Standard“ (Blizzards GetValue nennt jede
    Mischung so). Diesen Eintrag noch einmal zu wählen, ändert in Blizzards Einstellungen nichts (kein SetValue, kein
    CVAR_UPDATE); zum Abschalten wählt man dort „Keine“ oder nimmt ezQuests Häkchen (OPT_WORLD_ICONS_TIP sagt es).
    Die Symbole erscheinen mit Maus und Tastatur nur, wenn „Interaktionstaste aktivieren“ an ist (softTargetInteract =
    Kbm oder Any, Enum.SoftTargetEnableFlags); die Taste „Mit Ziel interagieren“ (Bindung INTERACTTARGET) benutzt das
    Objekt. Fehlt eines, sagen es der Status und die Knöpfe auf der Einstellungsseite.
    Fundorte von Kräutern und Erzen auf Welt- und Minikarte zeigt ezMap (Sammelkarte), nicht ezQuest.
]]

local World = {}
ns.World = World

World.CVARS = { "SoftTargetIconGameObject", "SoftTargetIconInteract" }
-- setzt nur Blizzards Auswahl „Interaktionssymbole“ (ezQuest nie): ändern sie sich, hat der Spieler die Auswahl benutzt
World.EXTRA = { "SoftTargetIconEnemy", "SoftTargetLowPriorityIcons" }
World.ON = "1"
World.INTERACT = "softTargetInteract"   -- Blizzards „Interaktionstaste aktivieren“ (Steuerung)
World.KBM = 2                           -- Enum.SoftTargetEnableFlags.Kbm; Any = 3 (Gamepad = 1, None = 0)
World.BINDING = "INTERACTTARGET"        -- Blizzards Taste „Mit Ziel interagieren“
-- Fassungen von Forever Loot Sparkles, die die Interaktions-CVars selbst setzen (laut seiner Beschreibung, Stand
-- 15.11.2026; docs/fremd-addons.md, Abschnitt 3) – dann tritt worldIcons zurück
World.FEATURE = "questSparkle"
World.OLD_SPARKLES = { from = "1.2.0", to = "1.3.1" }

local Plain = Core.Plain
local applying = false   -- eigene Änderung läuft: CVAR_UPDATE nicht als Wunsch des Spielers lesen
local expected = {}      -- [kleingeschriebener Name] = Wert, den ezQuest eben gesetzt hat (falls CVAR_UPDATE später kommt)

-- Tabelle der gemerkten Werte in ezQuestDB (key: "worldSaved" für die Symbole, "sparkleSaved" für Sparkle.lua)
local function Saved(key)
    key = key or "worldSaved"
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end
World.Saved = Saved

-- Wert der CVar als Text; nil, wenn der Client sie nicht kennt oder der Wert gesperrt ist (Leitlinie 6)
local function Value(name)
    local v = Plain(Core.Call(Core.CVar, name))
    if v == nil then return nil end
    return tostring(v)
end
World.Value = Value

-- Kennt der Client die CVar, und darf ein Addon sie setzen? → true | false, Grund ("missing" | "locked")
function World.Known(name)
    local info = C_CVar and C_CVar.GetCVarInfo
    if type(info) == "function" then
        local ok, value, _, _, _, locked, secure, readOnly = pcall(info, name)
        if not ok or Core.IsSecret(value) or value == nil then return false, "missing" end
        if locked == true or secure == true or readOnly == true then return false, "locked" end
        return true
    end
    if Value(name) == nil then return false, "missing" end
    return true
end

-- → Liste der nutzbaren CVars, Liste der fehlenden { name, reason }
function World.Available()
    local usable, missing = {}, {}
    for _, name in ipairs(World.CVARS) do
        local ok, reason = World.Known(name)
        if ok then usable[#usable + 1] = name else missing[#missing + 1] = { name = name, reason = reason } end
    end
    return usable, missing
end

function World.Supported()
    return #(World.Available()) > 0
end

-- CVar setzen und als eigene Änderung vormerken (CVAR_UPDATE liest sie nicht als Wunsch des Spielers). Auch für
-- Sparkle.lua. → true, wenn gesetzt
local function Set(name, value)
    applying = true
    expected[name:lower()] = tostring(value)
    local ok = Core.SetCVar(name, value)
    applying = false
    return ok
end
World.Set = Set

-- Läuft eine Fassung von Forever Loot Sparkles, die dieselben CVars setzt (World.OLD_SPARKLES)? → Name, Version
-- oder nil. Erkennung wie beim Funkeln: ezCore kennt das Addon (Funktion questSparkle über ns.OtherFor),
-- die Version steht in seiner TOC (Core.Version). Unbekannte Version: nil (neue Fassungen setzen die CVars nicht).
function World.Other()
    local label, key = ns.OtherFor(World.FEATURE)
    local entry = label and type(Core.OTHER_ADDONS) == "table" and Core.OTHER_ADDONS[key] or nil
    if type(entry) ~= "table" then return nil end
    for _, folder in ipairs(type(entry.folders) == "table" and entry.folders or {}) do
        if Core.IsLoaded(folder) then
            local version = Plain(Core.Version(folder))
            local low = Core.CompareVersions(version, World.OLD_SPARKLES.from)
            local high = Core.CompareVersions(version, World.OLD_SPARKLES.to)
            if low and high and low >= 0 and high <= 0 then return label, version end
        end
    end
    return nil
end

-- Symbole einschalten (Blizzards Werte vorher merken). → Zahl geänderter CVars, Grund ("other"); im Kampf wartet es
-- aufs Kampfende.
function World.Apply()
    if not ns.Enabled("worldIcons") then return 0 end
    if World.Other() then return 0, "other" end   -- die alte Fassung von Forever Loot Sparkles setzt sie selbst
    if Core.InCombat() then
        ns.AfterCombat(World.Sync, "worldIcons")
        return 0
    end
    local saved, n = Saved(), 0
    if not saved then return 0 end
    for _, name in ipairs((World.Available())) do
        local current = Value(name)
        if current ~= World.ON then
            if saved[name] == nil then saved[name] = current or "0" end
            if Set(name, World.ON) then n = n + 1 end
        end
    end
    return n
end

-- Blizzards gemerkte Werte zurückgeben. → Zahl zurückgegebener CVars, Grund ("other"); im Kampf wartet es (außer beim
-- Abmelden). Läuft die alte Fassung von Forever Loot Sparkles, bleibt das Gemerkte liegen (nicht gegen sie arbeiten).
function World.Restore(now)
    local saved = Saved()
    if not saved or next(saved) == nil then return 0 end
    if World.Other() then return 0, "other" end
    if Core.InCombat() then
        if not now then ns.AfterCombat(World.Sync, "worldIcons") end
        return 0
    end
    local n = 0
    for name, value in pairs(saved) do
        if Set(name, value) then n = n + 1 end
        saved[name] = nil
    end
    return n
end

-- Nach dem Schalter richten.
function World.Sync()
    if ns.Enabled("worldIcons") then return World.Apply() end
    return World.Restore()
end

-- Was fehlt, damit du die Symbole siehst? → Liste von Texten (leer: alles bereit)
function World.Hints()
    local list = {}
    local other, version = World.Other()
    if other then list[#list + 1] = L.WORLD_OTHER:format(other, version) end
    local usable, missing = World.Available()
    for _, m in ipairs(missing) do
        list[#list + 1] = (m.reason == "locked" and L.WORLD_LOCKED or L.WORLD_MISSING):format(m.name)
    end
    if #usable == 0 then return list end
    local mode = tonumber(Value(World.INTERACT) or "")
    if mode ~= nil and mode < World.KBM then list[#list + 1] = L.WORLD_NO_INTERACT end
    local key = Plain(Core.Call(rawget(_G, "GetBindingKey"), World.BINDING))
    if type(key) ~= "string" or key == "" then list[#list + 1] = L.WORLD_NO_KEY end
    return list
end

-- Zeile für den Status (läuft die alte Fassung von Forever Loot Sparkles, nennt die Zeile des Schalters sie schon)
function World.StatusLine()
    if World.Other() then return nil end
    if not World.Supported() then return L.STATUS_WORLD_NONE end
    local hints = World.Hints()
    if #hints == 0 then return nil end
    return L.STATUS_WORLD_HINT:format(table.concat(hints, " "))
end

---------------------------------------------------------------------------
-- Blizzards Einstellungen öffnen (Leitlinie 1: dort stehen Interaktionstaste, Taste und Symbole)
---------------------------------------------------------------------------

-- Kategorie in Blizzards Einstellungen nach ihrem Namen (CONTROLS_LABEL, ACCESSIBILITY_GENERAL_LABEL)
function World.Category(label)
    label = Plain(label)
    local panel = rawget(_G, "SettingsPanel")
    if type(label) ~= "string" or type(panel) ~= "table" or type(panel.GetAllCategories) ~= "function" then return nil end
    for _, category in ipairs(Core.Call(panel.GetAllCategories, panel) or {}) do
        if type(category) == "table" and category.GetName and Plain(Core.Call(category.GetName, category)) == label then
            return category
        end
    end
    return nil
end

-- which: "controls" (Steuerung: Interaktionstaste, Taste) | "accessibility" (Interaktionssymbole). Fehlt die Kategorie,
-- öffnet sich Blizzards Einstellungsfenster. Danach stehen die Hinweise im Chat. → true | false
function World.OpenBlizzard(which)
    local label = which == "accessibility" and rawget(_G, "ACCESSIBILITY_GENERAL_LABEL") or rawget(_G, "CONTROLS_LABEL")
    local ok = Core.OpenPanel("settings", World.Category(label))   -- ohne Kategorie: nur das Fenster
    local hints = World.Hints()
    if #hints == 0 then ns.Print(L.WORLD_READY) else for _, text in ipairs(hints) do ns.Print(text) end end
    return ok == true
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

World.REAPPLY_MAX = 3   -- je Sitzung: so oft setzt ezQuest eine von außen zurückgesetzte CVar wieder (kein Wettlauf)
local reapplied = 0
World.ReapplySoon = ns.Throttle(function() World.Apply() end, 1)

local function SettingsOpen()
    local panel = rawget(_G, "SettingsPanel")
    return type(panel) == "table" and panel.IsShown ~= nil and panel:IsShown() == true
end

local function Listed(list, key)
    for _, cvar in ipairs(list) do
        if cvar:lower() == key then return true end
    end
    return false
end

--[[
    Eine der beobachteten CVars (World.CVARS, World.EXTRA) hat sich geändert, nicht durch ezQuest (eigenes Setzen
    erkennt ezQuest an applying oder, falls das Ereignis später kommt, am erwarteten Wert):
      bei offenem Einstellungsfenster  der Spieler hat Blizzards Auswahl „Interaktionssymbole“ benutzt – jede Wahl gilt,
                                       auch „Alle“ (Wert „an“): gemerkter Wert vergessen, Schalter aus, Hinweis im Chat
      sonst                            eine von ezQuests CVars steht nicht mehr auf „an“: der Client hat Kontowerte
                                       nachgeladen oder ein anderes Addon war es – ezQuest setzt sie höchstens
                                       World.REAPPLY_MAX-mal je Sitzung wieder
    → "user" | "reapply" | nil
]]
local function UserChanged()
    local saved = Saved()
    if saved then wipe(saved) end
    ns.SetSetting("worldIcons", false)
    ns.Print(L.WORLD_USER_CHANGED)
    return "user"
end

function World.OnCVarUpdate(name, value)
    name, value = Plain(name), Plain(value)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    if value ~= nil then value = tostring(value) else value = Value(name) end   -- Ereignis ohne Wert: aktueller Wert
    if applying or (expected[key] ~= nil and expected[key] == value) then
        expected[key] = nil
        return nil
    end
    -- Umriss-Modus und Funkeln gehören Sparkle.lua (eigenes Setzen ist oben schon erkannt)
    if ns.Sparkle and ns.Sparkle.Watches(key) then return ns.Sparkle.OnCVarUpdate(name, value) end
    if not ns.Enabled("worldIcons") or World.Other() then return nil end   -- nie gegen die alte Fassung setzen
    local own = Listed(World.CVARS, key)
    if not own and not Listed(World.EXTRA, key) then return nil end
    if SettingsOpen() then return UserChanged() end
    if not own or value == World.ON then return nil end
    if reapplied >= World.REAPPLY_MAX then return nil end
    reapplied = reapplied + 1
    World.ReapplySoon()
    return "reapply"
end

-- Beim Öffnen von Blizzards Einstellungen: Stand der CVars, die nur Blizzards Auswahl setzt (für den Rückfall unten)
local before = nil
function World.RememberSettings()
    before = {}
    for _, name in ipairs(World.EXTRA) do before[name] = Value(name) end
end

-- Rückfall, falls CVAR_UPDATE den Namen der CVar anders meldet (die Daten-Probe nennt das Feld „eventName“): Beim
-- Schließen von Blizzards Einstellungen steht eine nutzbare CVar nicht mehr auf „an“, oder eine CVar, die nur Blizzards
-- Auswahl setzt, hat sich seit dem Öffnen geändert (Wahl „Alle“) – dann hat der Spieler die Auswahl benutzt.
-- → "user" | nil
function World.CheckAfterSettings()
    local snapshot = before
    before = nil
    -- im Kampf wartet ezQuests eigenes Setzen noch (Schalter eben umgelegt) – das ist keine Wahl des Spielers
    if applying or Core.InCombat() or not ns.Enabled("worldIcons") or World.Other() then return nil end
    for _, name in ipairs((World.Available())) do
        local current = Value(name)
        if current ~= nil and current ~= World.ON then return UserChanged() end
    end
    if snapshot then
        for _, name in ipairs(World.EXTRA) do
            if Value(name) ~= snapshot[name] then return UserChanged() end
        end
    end
    return nil
end

ns.OnReady(function()
    World.Sync()
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) == "table" and type(panel.HookScript) == "function" then
        panel:HookScript("OnShow", function() ns.Try("World", World.RememberSettings) end)
        panel:HookScript("OnHide", function() ns.Try("World", World.CheckAfterSettings) end)
    end
    ns.On("CVAR_UPDATE", function(_, name, value) World.OnCVarUpdate(name, value) end)
    ns.On("ACCOUNT_CVARS_LOADED", function() World.Sync() end)   -- Kontowerte kommen nach dem Anmelden
    ns.On("PLAYER_LOGOUT", function() World.Restore(true) end)
end)

ns.OnSettingChanged(function(key)
    if key ~= "worldIcons" then return end
    World.Sync()
    if ns.Enabled("worldIcons") then
        for _, text in ipairs(World.Hints()) do ns.Print(text) end
    end
end)

---------------------------------------------------------------------------
-- Hinweis an der Questverfolgung (ezCores Hinweis-Helfer; Entscheidung des Nutzers vom 18.11.2026)
---------------------------------------------------------------------------

-- „Quest-Objekte funkeln“ (Sparkle.lua) und „Symbole über Quest-Objekten“ (hier) stellen ohne Klick Blizzards Grafik
-- bzw. Barrierefreiheit um und sind darum ab Werk aus. Einmal je Account, wenn du eine Quest annimmst und Blizzards
-- Questverfolgung zu sehen ist – zusammen mit dem Sortieren in derselben Blase (ezCore: höchstens eine je Fenster), je
-- Funktion ein Knopf „Einschalten“. Nicht, wenn der Client die Einstellungen nicht kennt oder sperrt, wenn ein anderes
-- Addon sie setzt (Forever Loot Sparkles) und solange die Erklärblase von ezQuests Rundgang an der Verfolgung steht.
-- Für die beim Update umgestellten (ns.MigrateWorldOptIn, Merker …Off29Was) sagt die Blase das dazu.
function World.RegisterOptInHints()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    local function TourShowing()
        return ns.Tracker ~= nil and type(ns.Tracker.TourShowing) == "function" and ns.Tracker.TourShowing() == true
    end
    local function Was(key) return type(ns.db) == "table" and ns.db[ns.WORLD_OPTIN[key]] == true end
    local function Def(key, applies)
        return {
            owner = ADDON,
            window = "tracker",
            label = function() return L["OPT_" .. key] end,
            what = function() return L["OPTIN_" .. key] end,
            isOn = function() return ns.Enabled(key) end,
            enable = function()
                ns.SetSetting(key, true)   -- » OnSettingChanged » Sync » Apply (im Kampf erst danach)
                return ns.Enabled(key)
            end,
            applies = function() return applies() and not TourShowing() end,
            switchedOff = function() return Was(key) end,
        }
    end
    Hint.Register("ezQuest.worldSparkle", Def("worldSparkle", function()
        local Sparkle = ns.Sparkle
        return Sparkle ~= nil and not Sparkle.Other() and Sparkle.Supported()
    end))
    Hint.Register("ezQuest.worldIcons", Def("worldIcons", function()
        return not World.Other() and World.Supported()
    end))
    return true
end
World.RegisterOptInHints()
