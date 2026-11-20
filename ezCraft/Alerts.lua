local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Meldungen auf ezPanels Leiste (Baustein „Meldungen“; PANEL-14, Vollprüfung V-089). ezCraft meldet zwei Quellen an:

      ezCraft.cooldowns   „Abklingzeit fertig“ – fertige Berufs-Abklingzeiten aller Twinks („Transmutation bei Mira
                          bereit“; Data.ReadyCooldownsMerged, Daten aus Core.Professions.AllCooldowns). Zauber, die
                          sich eine Abklingzeit teilen (Transmutationen), sind je Twink eine Zeile und zählen auf
                          der Leiste einmal. Höchstens drei Zeilen: bei mehr die ersten zwei und „und n weitere
                          Abklingzeiten bereit“
      ezCraft.materials   „Material fehlt“ – was der Einkaufsliste fehlt, gezählt wie im Berufefenster
                          (Shopping.Totals): ein Gegenstand mit Namen und Anzahl, sonst die Zahl der Materialien

    Angemeldet wird im ns.OnReady über ezCore.API("ezPanel").AddWarning(key, name, fn). Jede Quelle lässt sich in
    ezPanel einzeln abwählen (Baustein „Meldungen“ → Menü „Quellen“) – eigene Schalter hat ezCraft dafür nicht, damit
    es nur eine Stelle gibt. Ohne ezPanel (oder mit einer Fassung ohne AddWarning) geschieht nichts: keine
    Anmeldung, keine Zuhörer, keine Statuszeile. Die Statuszeile nennt nur, was ezPanel angenommen hat, und sagt,
    wenn der Baustein „Meldungen“ nicht auf der Leiste steht (ab Werk aus) – dann ruft ezPanel die Quellen nicht.

    ezPanel ruft die Funktionen bei jedem Neuzeichnen (alle fünf Sekunden und nach RefreshWarnings). Die Meldung der
    Einkaufsliste zählt den Bestand aller Twinks und wird deshalb gemerkt, bis sich Liste, Bestand, Rezepte oder
    die Einstellungen „was als vorhanden zählt“ ändern (höchstens MAX_AGE Sekunden); die Abklingzeiten sind eine
    kurze Liste und werden jedes Mal frisch gelesen (eine läuft auch ohne Ereignis ab).
]]

local Alerts = {}
ns.Alerts = Alerts

Alerts.COOLDOWNS = "ezCraft.cooldowns"
Alerts.MATERIALS = "ezCraft.materials"

local MAX_COOLDOWN_LINES = 3
local MAX_AGE = 60           -- Sekunden, die die Meldung der Einkaufsliste ohne Ereignis höchstens gemerkt bleibt
local PANEL_BLOCK = "alerts" -- Kennung von ezPanels Baustein „Meldungen“ (ezPanel/Blocks/Alerts.lua)

local panel                  -- ezPanels Schnittstelle, sobald dort angemeldet
local accepted = {}          -- Namen der Quellen, die ezPanel angenommen hat (Reihenfolge der Anmeldung)
local listening = false
local materialTexts          -- gemerkt: Liste von Texten, false (nichts fehlt) oder nil (neu rechnen)
local materialAt = 0

-- Laufzeit der Sitzung (Frist des Merkers, nie gespeichert): Core.Uptime (W-14)
local Now = Core.Uptime

---------------------------------------------------------------------------
-- Die beiden Quellen (→ nil, wenn es nichts zu melden gibt, sonst eine Liste von Texten)
---------------------------------------------------------------------------

function Alerts.CooldownTexts()
    local ready = Data.ReadyCooldownsMerged()
    if #ready == 0 then return nil end
    local shown = #ready > MAX_COOLDOWN_LINES and MAX_COOLDOWN_LINES - 1 or #ready
    local out = {}
    for i = 1, shown do
        out[i] = L.ALERT_COOLDOWN_READY:format(Data.ReadyCooldownLine(ready[i].entry, ready[i].name))
    end
    -- „und 2 weitere bereit“ – Core.More plus Zusatz (Welle 23; vorher eigener Text ALERT_COOLDOWN_MORE)
    if shown < #ready then out[#out + 1] = Core.More(#ready - shown, true) .. " " .. L.ALERT_COOLDOWN_MORE_READY end
    return out
end

function Alerts.MaterialTexts()
    if materialTexts ~= nil and Now() - materialAt <= MAX_AGE then return materialTexts or nil end
    local missing, first = 0, nil
    for _, row in ipairs(ns.Shopping.Totals()) do
        if row.missing > 0 then
            missing = missing + 1
            first = first or row
        end
    end
    local texts = false
    if missing == 1 then
        texts = { L.ALERT_MATERIAL_ONE:format(first.name, first.missing) }
    elseif missing > 1 then
        texts = { L.ALERT_MATERIAL_MANY:format(missing) }
    end
    -- Ein Platzhalter „#itemID“ (Name noch nicht geladen) wird nicht gemerkt: beim nächsten Mal steht der Name da.
    if missing == 1 and first.name:find("^#") then
        materialTexts = nil
    else
        materialTexts, materialAt = texts, Now()
    end
    return texts or nil
end

---------------------------------------------------------------------------
-- Anmeldung bei ezPanel
---------------------------------------------------------------------------

local function Refresh()
    if panel and type(panel.RefreshWarnings) == "function" then Core.Call(panel.RefreshWarnings) end
end

-- Viele Ereignisse kurz hintereinander (Taschen, Berufefenster) zeichnen nur einmal neu.
local RefreshSoon = ns.Throttle(Refresh, 0.2)

local function MaterialsChanged()
    materialTexts = nil
    RefreshSoon()
end

local function Listen()
    if listening then return end
    listening = true
    Core.Listen("EZCRAFT_SHOPPING_CHANGED", MaterialsChanged, ADDON)
    Core.Listen("INVENTORY_CHANGED", MaterialsChanged, ADDON)
    Core.Listen("GUILDBANK_CHANGED", MaterialsChanged, ADDON)
    Core.Listen("RECIPES_CHANGED", MaterialsChanged, ADDON)
    Core.Listen("CHAR_FORGOTTEN", MaterialsChanged, ADDON)
    Core.Listen("PROF_COOLDOWNS_CHANGED", RefreshSoon, ADDON)
    -- Das Berufefenster liefert andere Zutaten als das Rezept-Wissen, solange es offen ist (Shopping.Invalidate).
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }) do
        ns.On(event, MaterialsChanged)
    end
    ns.OnSettingChanged(MaterialsChanged)   -- was als „vorhanden“ zählt (Bank, Post, Gildenbank, Twinks)
end

-- Meldet beide Quellen an. → true, wenn ezPanel läuft und beide angenommen hat; false ohne ezPanel (dann bleibt
-- alles, wie es ist) oder wenn ezPanel eine Quelle ablehnt.
function Alerts.Register()
    local api = Core.API("ezPanel")
    if not (api and type(api.AddWarning) == "function") then return false end
    local cooldowns = api.AddWarning(Alerts.COOLDOWNS, L.ALERT_COOLDOWNS, Alerts.CooldownTexts) == true
    local materials = api.AddWarning(Alerts.MATERIALS, L.ALERT_MATERIALS, Alerts.MaterialTexts) == true
    if not (cooldowns or materials) then return false end
    panel = api
    accepted = {}
    if cooldowns then accepted[#accepted + 1] = L.ALERT_COOLDOWNS end
    if materials then accepted[#accepted + 1] = L.ALERT_MATERIALS end
    Listen()
    return cooldowns and materials
end

-- Stehen ezCrafts Quellen bei ezPanel?
function Alerts.Registered() return panel ~= nil end

-- Steht ezPanels Baustein „Meldungen“ auf der Leiste? → true | false | nil (ezPanel sagt es nicht). Ab Werk ist er
-- aus; dann ruft ezPanel die Quellen nicht auf und nichts von ezCraft steht auf der Leiste.
function Alerts.BlockShown()
    if not (panel and type(panel.BlockEnabled) == "function") then return nil end
    local shown = Core.Plain(Core.Call(panel.BlockEnabled, PANEL_BLOCK))
    if type(shown) ~= "boolean" then return nil end
    return shown
end

-- Zeile für /ezcraft status: welche Quellen ezPanel angenommen hat und wo sie sich abwählen lassen – oder dass der
-- Baustein „Meldungen“ erst eingeschaltet werden muss. → nil ohne ezPanel.
function Alerts.StatusText()
    if not panel then return nil end
    local names = {}
    for i, name in ipairs(accepted) do names[i] = L.STATUS_ALERTS_QUOTE:format(name) end
    local list = table.concat(names, L.STATUS_ALERTS_AND)
    if Alerts.BlockShown() == false then return L.STATUS_ALERTS_OFF:format(list) end
    return L.STATUS_ALERTS:format(list)
end

ns.OnReady(function() Alerts.Register() end)

-- /ezcraft status: nur mit ezPanel – sagt, was auf der Leiste steht und wo es sich abwählen lässt.
ns.AddStatusLine(Alerts.StatusText)
