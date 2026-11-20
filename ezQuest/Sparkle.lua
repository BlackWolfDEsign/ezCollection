local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quest-Objekte in der Welt funkeln wieder (Wunsch des Nutzers vom 15.11.2026 abends: „also das quest objekte in der
    welt funkeln“; Wortlaut im ROADMAP-Index und in docs/roadmap/ezQuest.md).
    Was der Client tut: Statt des Funkelns an plünderbaren Quest-Objekten zeigt Forever mit Blizzards Umriss-Modus
    (Grafik, „Umriss-Modus“: 0 aus, 1 mittel, 2 hoch; nur wenn C_VideoOptions.IsOutlineModeSupported() – Forever-Quelle
    Gethe/wow-ui-source, Zweig forever, Blizzard_SettingsDefinitions_Shared/Graphics.lua, GetOutlineModeOptions,
    nachgelesen am 15.11.2026) einen Umriss. Das Funkeln kommt zurück, wenn der Umriss-Modus aus ist und die
    Client-Einstellung outlineModeShowLootEffectWhenDisabled auf 1 steht. Einschalten wirkt sofort, Ausschalten erst
    nach einem Neustart des Spiels; dieselbe Einstellung gilt für Quest-Objekte und Questgeber, und das Spiel zeigt an
    Quest-Objekten entweder Funkeln oder Umriss, nie beides. Quelle dieser Fakten: die öffentliche Beschreibung des
    Addons „Forever Loot Sparkles“ auf CurseForge (https://www.curseforge.com/wow/addons/forever-loot-sparkles, gelesen
    am 15.11.2026) – sein Code ist nicht geöffnet, nichts daraus übernommen (Leitlinie 10).
    Was ezQuest tut (Schalter worldSparkle, ab Werk aus seit Welle 29 – es stellt ohne Klick Blizzards Grafik um;
    Entscheidung des Nutzers vom 18.11.2026, wörtlich „Ab Werk aus, mit Hinweis“; Hinweis an der Questverfolgung über
    ezCores Core.OptInHint, World.RegisterOptInHints; ein gespeichertes „an“ stellt ns.MigrateWorldOptIn einmal aus,
    Sparkle.Login gibt danach Blizzards Werte zurück und sagt einmal, dass es erst nach dem Neustart wirkt):
      - setzt nur, wenn der Client beide Pflicht-Einstellungen kennt und ein Addon sie setzen darf (C_CVar.GetCVarInfo
        zur Laufzeit, World.Known); den Umriss-Modus der Schlachtzug-Grafik (raidGraphicsOutlineMode) zusätzlich,
        falls es ihn gibt – sonst blieben Quest-Objekte mit Blizzards Schlachtzug-Einstellungen umrandet
      - nur außerhalb des Kampfes (sonst nach PLAYER_REGEN_ENABLED, Leitlinie 5)
      - merkt Blizzards vorherige Werte vorher (ezQuestDB.sparkleSaved, dieselben Helfer wie die Symbole in World.lua)
        und gibt beim Ausschalten genau diese zurück – nur dort, wo noch ezQuests Wert steht; im Chat einmal, dass es
        erst nach dem nächsten Neustart des Spiels wirkt
      - ändert der Spieler den Umriss-Modus (oder eine Grafik-Voreinstellung) in Blizzards Grafik-Einstellungen selbst
        (CVAR_UPDATE, Rückfall beim Schließen der Einstellungen, Abgleich beim Anmelden): Schalter aus, Hinweis, nie
        dagegen ankämpfen – wie bei den Interaktionssymbolen
      - beim Abmelden gibt ezQuest nichts zurück (anders als die Symbole): Ausschalten wirkt erst nach einem Neustart,
        ein Hin und Her bei jedem Abmelden brächte nichts; WoW speichert die Werte selbst. Wer ezQuest ganz entfernt,
        nimmt vorher das Häkchen. Sonst bleibt der Umriss-Modus auf „Deaktiviert“ (Blizzards alter Wert steht nur in
        ezQuestDB.sparkleSaved): Rückweg ist, unter Grafik den Umriss-Modus wieder einzustellen (alte Stufe oder eine
        Voreinstellung) – die Funkel-Einstellung wirkt nur bei ausgeschaltetem Umriss-Modus; ganz zurück zusätzlich mit
        /console outlineModeShowLootEffectWhenDisabled 0 und einem Neustart. Allein der /console-Befehl ließe weder
        Umriss noch Funkeln übrig. Der Tooltip (OPT_worldSparkle_TIP) nennt diesen Rückweg.
      - Rücksicht (Leitlinie 9): Läuft Forever Loot Sparkles (ezCore, Funktion questSparkle), setzt ezQuest nichts und
        gibt nichts zurück; der Schalter ist grau, Tooltip und /ezq status sagen, wer es übernimmt
    Geheime Werte (Leitlinie 6): World.Value liefert für gesperrte Werte nil; mit nil wird nie verglichen oder
    gerechnet – unbekannt heißt „nichts tun“.
]]

local World = ns.World
local Sparkle = {}
ns.Sparkle = Sparkle

Sparkle.KEY = "worldSparkle"
Sparkle.SAVED = "sparkleSaved"       -- ezQuestDB.sparkleSaved = { [CVar] = Blizzards Wert vor ezQuest }
Sparkle.FEATURE = "questSparkle"     -- Funktion in ezCore.OTHER_ADDONS (Forever Loot Sparkles)
-- Reihenfolge: erst das Funkeln an, dann der Umriss aus. required: ohne sie gibt es kein Funkeln.
Sparkle.CVARS = {
    { name = "outlineModeShowLootEffectWhenDisabled", value = "1", required = true },
    { name = "graphicsOutlineMode", value = "0", required = true },
    { name = "raidGraphicsOutlineMode", value = "0" },
}

local silent = false   -- ezQuest legt den Schalter selbst um (Wahl des Spielers): kein Hinweis auf den Neustart
local notice = false   -- der Spieler hat ausgeschaltet: einmal „wirkt nach dem nächsten Neustart“, sobald zurückgegeben
local seen = {}        -- [CVar] = true: stand in dieser Sitzung auf ezQuests Wert (für den Abgleich ohne Ereignis)

local function Saved() return World.Saved(Sparkle.SAVED) end

local function Entry(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    for _, c in ipairs(Sparkle.CVARS) do
        if c.name:lower() == key then return c end
    end
    return nil
end

-- Beobachtet Sparkle diese CVar? (kleingeschriebener Name aus World.OnCVarUpdate)
function Sparkle.Watches(key)
    return Entry(key) ~= nil
end

-- Name des Addons, das das Funkeln schon übernimmt (Forever Loot Sparkles), sonst nil
function Sparkle.Other()
    return ns.OtherHandles(Sparkle.FEATURE)
end

-- → Liste der nutzbaren Einträge (leer, wenn eine Pflicht-Einstellung fehlt), Liste der fehlenden { name, reason }
function Sparkle.Available()
    local usable, missing, complete = {}, {}, true
    for _, c in ipairs(Sparkle.CVARS) do
        local ok, reason = World.Known(c.name)
        if ok then
            usable[#usable + 1] = c
        elseif c.required then
            complete = false
            missing[#missing + 1] = { name = c.name, reason = reason }
        end
    end
    if not complete then return {}, missing end
    return usable, missing
end

function Sparkle.Supported()
    return #(Sparkle.Available()) > 0
end

-- Stehen alle nutzbaren Einstellungen auf ezQuests Wert?
function Sparkle.Active()
    local usable = Sparkle.Available()
    if #usable == 0 then return false end
    for _, c in ipairs(usable) do
        if World.Value(c.name) ~= c.value then return false end
    end
    return true
end

-- Funkeln einschalten (Blizzards Werte vorher merken). → Zahl gesetzter Einstellungen, Grund ("other" | "combat")
function Sparkle.Apply()
    if not ns.Enabled(Sparkle.KEY) then return 0 end
    if Sparkle.Other() then return 0, "other" end
    if Core.InCombat() then
        ns.AfterCombat(Sparkle.Sync, Sparkle.KEY)
        return 0, "combat"
    end
    local saved, n = Saved(), 0
    if not saved then return 0 end
    for _, c in ipairs((Sparkle.Available())) do
        local current = World.Value(c.name)
        if current == c.value then
            seen[c.name] = true
        elseif current ~= nil and World.Set(c.name, c.value) then   -- unbekannter (gesperrter) Wert: nichts tun
            if saved[c.name] == nil then saved[c.name] = current end
            seen[c.name] = true
            n = n + 1
        end
    end
    return n
end

-- Blizzards gemerkte Werte zurückgeben, nur wo noch ezQuests Wert steht (sonst gilt, was jemand anders gewählt hat).
-- → Zahl zurückgegebener Einstellungen, Grund ("other" | "combat")
function Sparkle.Restore()
    local saved = Saved()
    if not saved or next(saved) == nil then return 0 end
    if Sparkle.Other() then return 0, "other" end   -- nicht gegen Forever Loot Sparkles arbeiten; gemerkt bleibt es
    if Core.InCombat() then
        ns.AfterCombat(Sparkle.Sync, Sparkle.KEY)
        return 0, "combat"
    end
    local n = 0
    for name, value in pairs(saved) do
        local c = Entry(name)
        if c and World.Value(name) == c.value and value ~= c.value then
            if World.Set(name, value) then n = n + 1 end
        end
        saved[name] = nil
    end
    return n
end

-- Nach dem Schalter richten. → wie Apply bzw. Restore
function Sparkle.Sync()
    if ns.Enabled(Sparkle.KEY) then return Sparkle.Apply() end
    local hadSaved = next(Saved() or {}) ~= nil
    local n, why = Sparkle.Restore()
    if notice and why == nil then
        ns.Print(n > 0 and L.SPARKLE_RESTART or (not hadSaved and L.SPARKLE_NOTHING) or L.SPARKLE_RESTART_KEPT)
    end
    if why ~= "combat" then notice = false end
    wipe(seen)
    return n, why
end

-- Der Spieler (oder eine Grafik-Voreinstellung) hat geändert: das gilt. Schalter aus, Rest zurück, Hinweis.
local function UserChanged()
    silent = true
    ns.SetSetting(Sparkle.KEY, false)   -- » OnSettingChanged » Sync » Restore (nur, wo noch ezQuests Wert steht)
    silent = false
    ns.Print(L.SPARKLE_USER_CHANGED)
    return "user"
end

-- Eine der Einstellungen hat sich geändert, nicht durch ezQuest (das erkennt World.OnCVarUpdate vorher).
-- Nur Einstellungen, die ezQuest gesetzt hat (gemerkt) oder die in dieser Sitzung auf ezQuests Wert standen – wie in
-- Sparkle.Check. Hat ezQuest nichts gesetzt (Client kennt oder sperrt die Funkel-Einstellung, Kampf vor dem ersten
-- Setzen), ist eine Änderung des Umriss-Modus keine Abkehr vom Funkeln: Schalter bleibt, kein Hinweis.
-- → "user" | nil
function Sparkle.OnCVarUpdate(name, value)
    local c = Entry(Core.Plain(name))
    if not c or not ns.Enabled(Sparkle.KEY) or Sparkle.Other() or not Sparkle.Supported() then return nil end
    local saved = Saved() or {}
    if saved[c.name] == nil and not seen[c.name] then return nil end
    value = Core.Plain(value)
    if value ~= nil then value = tostring(value) else value = World.Value(c.name) end
    if value == nil or value == c.value then return nil end   -- unbekannt oder ezQuests Wert: nichts
    return UserChanged()
end

-- Abgleich ohne Ereignis (beim Schließen von Blizzards Einstellungen und beim Anmelden): steht eine Einstellung nicht
-- mehr auf ezQuests Wert, obwohl ezQuest sie gesetzt hatte (gemerkt) bzw. sie in dieser Sitzung so stand, hat der
-- Spieler gewählt. → "user" | nil
function Sparkle.Check(atLogin)
    if Core.InCombat() or not ns.Enabled(Sparkle.KEY) or Sparkle.Other() then return nil end
    local saved = Saved() or {}
    for _, c in ipairs((Sparkle.Available())) do
        local current = World.Value(c.name)
        local ours = saved[c.name] ~= nil or (not atLogin and seen[c.name] == true)
        if ours and current ~= nil and current ~= c.value then return UserChanged() end
    end
    return nil
end

-- Beim Anmelden: erst abgleichen (in der Zwischenzeit selbst gewählt?), dann setzen. Hat das Update den Schalter eben
-- ausgeschaltet (ns.worldSwitched, ns.MigrateWorldOptIn) und gibt Sync Blizzards Werte zurück, sagt der Chat einmal,
-- dass das Funkeln erst nach dem nächsten Neustart verschwindet (im Kampf wartet das Zurückgeben, ohne Meldung).
function Sparkle.Login()
    if Sparkle.Check(true) then return "user" end
    local n, why = Sparkle.Sync()
    local switched = false
    for _, key in ipairs(type(ns.worldSwitched) == "table" and ns.worldSwitched or {}) do
        if key == Sparkle.KEY then switched = true end
    end
    if switched and why == nil and (n or 0) > 0 then
        ns.Print(L.SPARKLE_OFF29 .. " " .. Core.SettingsPathText("ezQuest", "OPT_HEADER_SHINE", "OPT_worldSparkle", L))
    end
    return n, why
end

-- Hinweise für Tooltip und Status. → Liste von Texten (leer: alles bereit)
function Sparkle.Hints()
    local list = {}
    local _, missing = Sparkle.Available()
    for _, m in ipairs(missing) do
        list[#list + 1] = (m.reason == "locked" and L.WORLD_LOCKED or L.SPARKLE_MISSING):format(m.name)
    end
    local other = Sparkle.Other()
    if other then list[#list + 1] = L.SPARKLE_OTHER:format(other) end
    return list
end

-- Zeile für /ezq status (nur bei eingeschaltetem Schalter)
function Sparkle.StatusLine()
    if not Sparkle.Supported() then
        return L.STATUS_SPARKLE_NONE:format(table.concat(Sparkle.Hints(), " "))
    end
    if Sparkle.Other() then return nil end   -- die Zeile des Schalters nennt das Addon schon
    if Sparkle.Active() then return L.STATUS_SPARKLE_ON end
    return L.STATUS_SPARKLE_WAIT
end

---------------------------------------------------------------------------
-- Ereignisse (CVAR_UPDATE hört World.lua und reicht Sparkles Einstellungen hierher weiter)
---------------------------------------------------------------------------

ns.OnReady(function()
    Sparkle.Login()
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) == "table" and type(panel.HookScript) == "function" then
        panel:HookScript("OnHide", function() ns.Try("Sparkle", Sparkle.Check) end)
    end
end)

ns.OnSettingChanged(function(key)
    if key ~= Sparkle.KEY then return end
    if ns.Enabled(Sparkle.KEY) then
        notice = false
        local _, why = Sparkle.Sync()
        if why == "other" then ns.Print(L.SPARKLE_OTHER:format(Sparkle.Other())) end
        if not Sparkle.Supported() then for _, text in ipairs(Sparkle.Hints()) do ns.Print(text) end end
        return
    end
    notice = not silent
    Sparkle.Sync()
end)
