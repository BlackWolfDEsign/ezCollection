local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Profile je Klasse (Welle 23, A2; Entscheidung des Nutzers 13.11.2026 „Profile: Wo es klassenabhängig ist“ –
    ezCombat, ezBuff, ezGear und ezBars über ezCores Profil-Gerüst). Bis hierher galten ezBuffs Schalter für alle
    Charaktere gemeinsam, obwohl vieles an der Klasse hängt (eigene Klassen-Buffs, Gruppe und Durchbuffen,
    Waffenverzauberung, Zurückgeben). ezBuff liefert nur, was ein Profil ist; Liste, Wechsel, Zuordnung (Charakter,
    Klasse, Spezialisierung), Export/Import, Sichern beim Ausloggen, Vergessen eines Charakters (CHAR_FORGOTTEN) und
    die allgemeinen Texte kommen von Core.NewProfiles, der Abschnitt der Einstellungsseite von page:Profiles
    (Options.lua, unter „Erweitert“).

    Ein Profil hält
      settings   alle Schalter, Regler und Auswahlfelder der Einstellungsseite (ns.DEFAULTS)
    NICHT im Profil (bleibt je Charakter bzw. accountweit wie bisher):
      - die eigene Wahl je Wahlgruppe und die Segen je Klasse und Spieler (ezBuffDB.chars[charKey]),
      - die gemerkten Tränke (ezBuffDB.elixirs) und die gesehenen Erklärblasen (ezBuffDB.hints).

    Welches Profil gilt (Gerüst): Spezialisierung (wenn an) → Charakter → Klasse → „Standard“. Ausgangsprofil: Beim
    ersten Einloggen mit Profilen werden die bisherigen Einstellungen als „Standard“ gesichert (Profiles.Login) – wer
    nichts zuordnet, merkt keinen Unterschied. Die Arbeitsdaten bleiben ezBuffDB.settings (ns.S); beim Wechsel sichert
    das Gerüst sie unter dem alten Namen und übernimmt die Werte des neuen Profils über Core.ApplySetting (jeder
    geänderte Wert meldet sich wie von Hand umgestellt). Gespeichert (Felder des Gerüsts): ezBuffDB.profiles[name],
    activeProfile (nil = „Standard“), profileFor[charKey | "class:MAGE" | "charKey#Gruppe"], specMode[charKey].
]]

local Profiles = {}
ns.Profiles = Profiles

Profiles.DEFAULT = "Standard"
Profiles.KIND, Profiles.VERSION = "ezBuff.profile", 1
Profiles.MAX_TEXT = 40      -- längere Texte sind kein Wert eines Auswahlfelds

local function InList(list, value)
    for _, known in ipairs(list) do
        if known == value then return true end
    end
    return false
end

-- Gültiger Wert für eine Einstellung im Profil oder nil (unbekannt, falscher Typ, gesperrt, außerhalb der Auswahl).
-- Zahlen werden auf die Grenzen der Regler gebracht (ns.LIMITS), Auswahlfelder auf ihre Werte (ns.CHOICES).
function Profiles.Valid(key, value)
    if type(key) ~= "string" then return nil end
    local default = ns.DEFAULTS[key]
    if default == nil or Core.IsSecret(value) or type(value) ~= type(default) then return nil end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end   -- NaN, unendlich
        local limit = ns.LIMITS[key]
        if limit then value = math.max(limit[1], math.min(limit[2], value)) end
        return value
    elseif type(value) == "string" then
        if #value > Profiles.MAX_TEXT then return nil end
        local choices = ns.CHOICES[key]
        if choices and not InList(choices, value) then return nil end
    end
    return value
end

-- Arbeitsdaten → Profil (Kopie).
function Profiles.Snapshot()
    local settings = {}
    for key in pairs(ns.DEFAULTS) do
        local value = Profiles.Valid(key, ns.S and ns.S[key])
        if value ~= nil then settings[key] = value end
    end
    return { settings = settings }
end

-- Wert setzen: wie beim Übernehmen einer Sicherung über Core.ApplySetting (Setting-Objekt der offenen Seite, sonst
-- ns.SetSetting). Beim Einloggen (Profiles.Login, vor allen übrigen Aufgaben) still in ns.S – die Teile lesen die
-- Werte erst danach beim Einrichten.
local starting = false
local function Set(key, value)
    if starting then
        ns.S[key] = value
        return
    end
    Core.ApplySetting(ns, key, value)
end

-- Alte Exporte und Sicherungen (von vor der Einstellungs-Prüfung vom 19.11.2026) wie beim Laden umstellen – auf einer
-- Kopie, nur wenn ein entfernter Schlüssel drinsteht (code-reviewer 20.11.2026: sonst brachte ein alter Export mit
-- groupSpells = false und groupMin = 3 die Gruppenfassung zurück; ein neuer Export mit weapon = false bleibt aus).
function Profiles.Adopted(settings)
    if type(settings) ~= "table" then return settings end
    local old = false
    for _, key in ipairs(ns.REMOVED_SETTINGS or {}) do
        if settings[key] ~= nil then old = true end
    end
    if not (old and ns.AdoptSettings1911) then return settings end
    local copy = {}
    for key, value in pairs(settings) do copy[key] = value end
    ns.AdoptSettings1911(copy)
    return copy
end
ns.ImportLegacy = Profiles.Adopted   -- dieselbe Umstellung für „Alles übernehmen“ (ezCores Core.ImportAll)

-- Profil → Arbeitsdaten: jeder Wert geprüft, Fehlendes und Ungültiges aus dem Standard.
function Profiles.Apply(data)
    if not ns.S then return false end
    local src = type(data) == "table" and type(data.settings) == "table" and Profiles.Adopted(data.settings) or {}
    for key, default in pairs(ns.DEFAULTS) do
        local value = Profiles.Valid(key, src[key])
        if value == nil then value = default end
        if ns.S[key] ~= value then Set(key, value) end
    end
    return true
end

-- Import: nur bekannte Einstellungen mit gültigem Wert (der Text kann von irgendwoher kommen). nil = unbrauchbar.
function Profiles.Clean(data)
    if type(data) ~= "table" or type(data.settings) ~= "table" then return nil end
    local settings, any = {}, false
    local src = Profiles.Adopted(data.settings)
    for key in pairs(ns.DEFAULTS) do
        local value = Profiles.Valid(key, src[key])
        if value ~= nil then
            settings[key] = value
            any = true
        end
    end
    if not any then return nil end
    return { settings = settings }
end

local P = Core.NewProfiles({
    owner = ADDON,
    db = function() return ns.db end,
    snapshot = Profiles.Snapshot,
    apply = Profiles.Apply,
    clean = Profiles.Clean,
    kind = Profiles.KIND, version = Profiles.VERSION, wrap = "profile", default = Profiles.DEFAULT,
    perChar = true,                             -- die Auswahl gilt für diesen Charakter
    scopes = { class = true, spec = true },     -- dazu: ein Profil für die Klasse, auf Wunsch je Spezialisierung
    texts = L, print = ns.Print,
})
Profiles.P = P

function Profiles.Active() return P.Active() end
function Profiles.Label(name) return P.Label(name) end

-- Einloggen: Beim ersten Mal die bisherigen Einstellungen als „Standard“ sichern (Ausgangsprofil), dann das Profil
-- dieses Charakters laden. → true, wenn das Ausgangsprofil eben angelegt wurde.
function Profiles.Login()
    local db = ns.db
    local created = false
    if type(db) == "table" and (type(db.profiles) ~= "table" or db.profiles[P.Active()] == nil) then
        P.Save()
        created = true
    end
    starting = true
    local ok, err = pcall(P.Load, true)
    starting = false
    if not ok then error(err, 0) end
    return created
end

-- Zeile für /ezbuff status („Profil: Standard“, Text aus ezCore).
function Profiles.StatusLine()
    local line = L.PROFILE_MENU:format(P.Label())
    if P.SpecMode() then line = line .. " – " .. Core.L.PROFILE_FOR_SPEC end
    return line
end

-- Vor den übrigen Aufgaben beim Einloggen (TOC: gleich nach Core.lua), damit die Teile mit den Werten des richtigen
-- Profils starten.
ns.OnReady(function()
    ns.Try("Profiles", Profiles.Login)
end)
