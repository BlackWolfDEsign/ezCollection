local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Profile der Leisten-Einstellungen (Entscheidung des Nutzers 13.11.2026: „Wo es klassenabhängig ist“ – ezBars über
    ezCores Profil-Gerüst, je Charakter bzw. Klasse). Gebaut mit Core.NewProfiles: Liste, Wechsel, Zuordnung,
    Export/Import, Sichern beim Ausloggen, Wechsel mit der Spezialisierung und die allgemeinen Texte kommen von dort.
    ezBars liefert nur, was ein Profil ist (Snapshot, Apply, Clean).

    Ein Profil = alle Leisten-Einstellungen (ns.DEFAULTS): welche Leisten an sind, Spalten, Reihen, Größe, Abstand,
    Sichtbarkeit, leere Plätze zeigen, Wahl der Aktionsplätze – dazu Spalten, Reihen, Größe, Abstand und Sichtbarkeit
    der Leisten anderer Module (ns.RegisterBar; Schlüssel x_<id>_<Name>, auch wenn ihr Anbieter gerade nicht läuft).
    NICHT im Profil:
      - die Zauber auf den Plätzen (die gehören dem Charakter; dafür gibt es je Leiste das Leisten-Profil über ezMacro),
      - die gemerkten Aktionsplätze je Charakter (ezBarsDB.chars),
      - die Lage der Leisten (ezCore.Mover, ezCoreDB.positions).

    Die Arbeitsdaten bleiben ezBarsDB.settings (ns.S, alle Stellen lesen dort). Beim Wechsel sichert das Gerüst sie
    unter dem alten Namen und übernimmt die Werte des neuen Profils in dieselbe Tabelle. Gespeichert (Felder des
    Gerüsts): ezBarsDB.profiles[name], activeProfile (nil = „Standard“), profileFor[charKey | "class:MAGE" |
    "charKey#Gruppe"], specMode[charKey]. Welches Profil gilt: Spezialisierung (wenn an) → Charakter → Klasse →
    „Standard“. Ohne jede Zuordnung bleibt alles wie vor den Profilen: ein „Standard“ für alle.

    Sichtbar: Einstellungen → ezBars → „Profile“ (Auswahl, für die Klasse, je Spezialisierung, Neu, Exportieren,
    Importieren, Löschen) – den Abschnitt baut ezCore (page:Profiles, Options.lua). Im Kampf ändern sich nur die
    Einstellungen; die Leisten richtet Bars.Apply gleich nach dem Kampf ein (ns.AfterCombat).
]]

local Profiles = {}
ns.Profiles = Profiles

Profiles.DEFAULT = "Standard"
Profiles.KIND, Profiles.VERSION = "ezBars.layout", 1

-- Grenzen wie die Regler der Einstellungsseite (Options.lua).
Profiles.LIMITS = { Cols = { 1, 12 }, Rows = { 1, 12 }, Size = { 50, 200 }, Padding = { 0, 20 } }

-- Gültiger Wert für eine Leisten-Einstellung oder nil (unbekannter Schlüssel, falscher Typ, außerhalb der Auswahl).
-- Zahlen werden auf die Grenzen der Regler gebracht.
function Profiles.Valid(key, value)
    local default = ns.DEFAULTS[key]
    local name = type(key) == "string" and key:match("^bar%d+(%a+)$") or nil
    if not name then
        -- Leiste eines anderen Moduls (x_<id>_<Name>): gültig auch, solange ihr Anbieter sie noch nicht angemeldet
        -- hat – ein Profil oder ein Import kann ihre Werte schon tragen
        local _, extraName = ns.ExtraKeyParts(key)
        name = extraName
        if name and default == nil then default = ns.EXTRA_DEFAULTS[name] end
    end
    if default == nil or type(value) ~= type(default) or Core.IsSecret(value) then return nil end
    local limit = name and Profiles.LIMITS[name]
    if limit then
        if value ~= value then return nil end      -- NaN aus einem fremden Text
        return math.max(limit[1], math.min(limit[2], math.floor(value + 0.5)))
    elseif name == "Show" then
        for _, show in ipairs(ns.SHOW_VALUES) do
            if show == value then return value end
        end
        return nil
    elseif name == "Page" then
        if value == "auto" then return value end
        local page = tonumber(value)
        return page and ns.Slots.IsAllowed(page) and tostring(page) or nil
    end
    return value
end

-- Höchstzahl an Leisten anderer Module, deren Werte ein Import tragen darf (der Text kann von irgendwoher kommen).
Profiles.MAX_EXTRA = 64

-- Schlüssel der Leisten anderer Module in einer Tabelle (x_<id>_<Name>) als Menge – auch die von Leisten, deren
-- Anbieter gerade nicht geladen ist.
local function ExtraKeys(tbl, into)
    into = into or {}
    for key in pairs(type(tbl) == "table" and tbl or {}) do
        if ns.ExtraKeyParts(key) then into[key] = true end
    end
    return into
end

-- Arbeitsdaten → Profil (Kopie; nur die Leisten-Einstellungen, auch die der Leisten anderer Module).
function Profiles.Snapshot()
    local settings = {}
    for key in pairs(ns.DEFAULTS) do settings[key] = ns.S and ns.S[key] end
    for key in pairs(ExtraKeys(ns.S)) do settings[key] = ns.S[key] end
    return { settings = settings }
end

-- Wert setzen über Core.ApplySetting (seit Welle 23; vorher eine lokale Hülle Set mit demselben Weg): zuerst über das
-- Setting-Objekt der Einstellungsseite, damit ein offenes Fenster den neuen Wert sofort zeigt (wie
-- page:ResetToDefaults), sonst ns.SetSetting. Beides meldet die Änderung (ns.SettingChanged: Leisten einrichten).
-- Profil → Arbeitsdaten: jeder Wert geprüft, Fehlendes und Ungültiges aus dem Standard.
function Profiles.Apply(data)
    if not ns.S then return false end
    local src = type(data) == "table" and type(data.settings) == "table" and data.settings or {}
    for key, default in pairs(ns.DEFAULTS) do
        local value = Profiles.Valid(key, src[key])
        if value == nil then value = default end
        if ns.S[key] ~= value then Core.ApplySetting(ns, key, value) end
    end
    -- Leisten anderer Module, die (noch) nicht angemeldet sind: Wert aus dem Profil; kennt das Profil die Leiste
    -- nicht, den Wert vergessen – dann gilt bei ihrer Anmeldung der Standard ihres Anbieters
    for key in pairs(ExtraKeys(src, ExtraKeys(ns.S))) do
        if ns.DEFAULTS[key] == nil then
            local value = Profiles.Valid(key, src[key])
            if ns.S[key] ~= value then
                ns.S[key] = value
                ns.SettingChanged(key)
            end
        end
    end
    return true
end

-- Import: nur bekannte Einstellungen mit gültigem Wert (der Text kann von irgendwoher kommen). nil = unbrauchbar.
function Profiles.Clean(data)
    if type(data) ~= "table" or type(data.settings) ~= "table" then return nil end
    local settings, any = {}, false
    for key in pairs(ns.DEFAULTS) do
        local value = Profiles.Valid(key, data.settings[key])
        if value ~= nil then
            settings[key] = value
            any = true
        end
    end
    -- Leisten anderer Module: nur Schlüssel der festen Form mit gültigem Wert, höchstens MAX_EXTRA Leisten
    local ids, count = {}, 0
    local keys = {}
    for key in pairs(ExtraKeys(data.settings)) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if settings[key] == nil then
            local id = ns.ExtraKeyParts(key)
            local value = Profiles.Valid(key, data.settings[key])
            if value ~= nil and (ids[id] or count < Profiles.MAX_EXTRA) then
                if not ids[id] then ids[id], count = true, count + 1 end
                settings[key] = value
                any = true
            end
        end
    end
    if not any then return nil end
    return { settings = settings }
end

local P = Core.NewProfiles({
    owner = ns.moduleName,
    db = function() return ns.db end,
    snapshot = Profiles.Snapshot,
    apply = Profiles.Apply,
    clean = Profiles.Clean,
    kind = Profiles.KIND, version = Profiles.VERSION, wrap = "layout", default = Profiles.DEFAULT,
    perChar = true,                             -- die Auswahl gilt für diesen Charakter
    scopes = { class = true, spec = true },     -- dazu: ein Profil für die Klasse, auf Wunsch je Spezialisierung
    texts = L, print = ns.Print,
})
Profiles.P = P

-- Aktives Profil (Anzeigename) – für den Status.
function Profiles.Label() return P.Label() end

-- „Für die Klasse“ und „Löschen“ der Einstellungsseite gibt es seit ezCore 1.13.0 im Gerüst (auch mit perChar; der
-- Abschnitt „Profile“ kommt aus page:Profiles, Options.lua). Die vier Funktionen bleiben als Weiterleitung (Leitlinie 8):
-- Klasse des Charakters als Text („Magier“), für die Beschriftung von „für die Klasse“.
function Profiles.ClassLabel() return P.ClassLabel() end

-- Gilt das aktive Profil für die Klasse dieses Charakters?
function Profiles.ForClass() return P.ForClass() end

-- Aktives Profil der Klasse zuordnen (on) bzw. die Zuordnung der Klasse lösen. Charaktere der Klasse, die selbst
-- kein Profil gewählt haben, bekommen es beim nächsten Einloggen. Meldet das Ergebnis im Chat. → true, wenn sich
-- etwas geändert hat (ist das aktive Profil schon das der Klasse, bleibt alles, wie es ist: false).
function Profiles.SetForClass(on) return P.SetForClass(on) end

-- „Löschen“ auf der Einstellungsseite: das aktive Profil, nach Rückfrage; „Standard“ bleibt immer (Hinweis, false).
function Profiles.AskDeleteActive() return P.AskDeleteActive() end

-- Einloggen: das Profil dieses Charakters laden – vor dem ersten Einrichten der Leisten (TOC: vor Bars.lua).
ns.OnReady(function()
    P.Load(true)
end)

ns.AddStatusLine(function() return L.STATUS_PROFILE:format(P.Label()) end)
