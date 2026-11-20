local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local CoreTexts = Core.L      -- ezCores allgemeine Profil-Texte (PROFILE_*)

--[[
    Profile (CB-44, Vollprüfung V-110; Entscheidung des Nutzers 13.11.2026: „Profile, wo es klassenabhängig ist“ –
    ezCombat, ezBuff, ezGear, ezBars über ezCores Profil-Gerüst). Bis hierher galten ezCombats Schalter für alle
    Charaktere gemeinsam, obwohl vieles an der Klasse hängt (Combo-Punkte, Totems, Gifte, Energie-Tick, Rotation).
    ezCombat liefert nur, was ein Profil ist; Liste, Wechsel, Zuordnung (Charakter, Klasse, Spezialisierung),
    Export/Import, Sichern beim Ausloggen und die allgemeinen Texte kommen von Core.NewProfiles, der Abschnitt der
    Einstellungsseite von page:Profiles (Options.lua, unter „Erweitert“).

    Ein Profil hält
      settings   alle Schalter, Regler und Auswahlfelder der Einstellungsseite (ns.DEFAULTS) außer rotationChoice
    NICHT im Profil:
      - rotationChoice: Spiegel der Rotation DIESES Charakters (gemerkt in ezCombatDB.rotations[charKey]); ein
        Profil für mehrere Klassen darf einem Krieger keine Magier-Rotation geben,
      - Anpassungen der Rotationen, Erklärblasen, Lagen der Teile (ezCore.Mover), Blizzards CVars.

    Welches Profil gilt (Gerüst): Spezialisierung (wenn an) → Charakter → Klasse → „Standard“. „Standard“ ist das
    gemeinsame Profil aller Charaktere ohne eigene Zuordnung; die Auswahl auf der Seite gilt für diesen Charakter
    (perChar), das Kästchen „für die Klasse“ für alle Charaktere der Klasse ohne eigene Wahl.
    Ausgangsprofil: Beim ersten Einloggen mit Profilen werden die bisherigen Einstellungen als „Standard“ gesichert
    (Profiles.Login) – wer nichts zuordnet, merkt keinen Unterschied.

    Die Arbeitsdaten bleiben ezCombatDB.settings (ns.S, alle Dateien lesen dort). Beim Wechsel sichert das Gerüst sie
    unter dem alten Namen und übernimmt die Werte des neuen Profils in dieselbe Tabelle – jeder geänderte Wert meldet
    sich wie von Hand umgestellt. „Alles sichern“ (ezCore, Core.ExportAll) nimmt ns.S mit, also die Werte des
    gerade aktiven Profils; die Profile selbst haben ihren eigenen Export (wie bei ezBag, ezPanel, ezBars, ezGear).
    Gespeichert (Felder des Gerüsts): ezCombatDB.profiles[name], activeProfile (nil = „Standard“),
    profileFor[charKey | "class:MAGE" | "charKey#Gruppe"], specMode[charKey].
]]

local Profiles = {}
ns.Profiles = Profiles

Profiles.DEFAULT = "Standard"
Profiles.KIND, Profiles.VERSION = "ezCombat.profile", 1
Profiles.SKIP = { rotationChoice = true }   -- je Charakter, nicht im Profil (siehe oben)
Profiles.MAX_TEXT = 40                       -- längere Texte sind kein Wert eines Auswahlfelds

local function InList(list, value)
    for _, known in ipairs(list) do
        if known == value then return true end
    end
    return false
end

-- Gültiger Wert für eine Einstellung im Profil oder nil (unbekannt, nicht im Profil, falscher Typ, gesperrt,
-- außerhalb der Auswahl). Zahlen werden auf die Grenzen der Regler gebracht (ns.LIMITS).
function Profiles.Valid(key, value)
    if type(key) ~= "string" or Profiles.SKIP[key] then return nil end
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

-- Wert setzen: über ezCores Core.ApplySetting (Welle 23, A15; derselbe Weg wie beim Übernehmen einer Sicherung) –
-- zuerst das Setting-Objekt der Einstellungsseite, damit ein offenes Fenster den neuen Wert sofort zeigt, sonst
-- ns.SetSetting. Beides meldet die Änderung wie ein Klick.
local starting = false      -- Profiles.Login läuft: die Teile sind noch nicht eingerichtet
local function Set(key, value)
    if starting then
        -- Beim Einloggen vor allen übrigen Aufgaben: die Teile lesen ns.S erst danach beim Einrichten – still
        -- schreiben, damit kein Zuhörer vor seinem Teil anläuft.
        ns.S[key] = value
        return
    end
    Core.ApplySetting(ns, key, value)
end

-- Werte eines Profils von vor der Einstellungs-Prüfung vom 19.11.2026 (alter Export, alte Sicherung) wie beim Laden
-- umstellen – auf einer Kopie, das übergebene Profil bleibt, wie es ist (Gegenprüfung 19.11.2026).
function Profiles.Adopted(settings)
    if type(settings) ~= "table" then return {} end
    local copy = {}
    for key, value in pairs(settings) do copy[key] = value end
    if ns.AdoptSettings1911 then ns.AdoptSettings1911(copy) end
    return copy
end

-- Profil → Arbeitsdaten: jeder Wert geprüft, Fehlendes und Ungültiges aus dem Standard; rotationChoice bleibt.
function Profiles.Apply(data)
    if not ns.S then return false end
    local src = Profiles.Adopted(type(data) == "table" and data.settings or nil)
    for key, default in pairs(ns.DEFAULTS) do
        if not Profiles.SKIP[key] then
            local value = Profiles.Valid(key, src[key])
            if value == nil then value = default end
            if ns.S[key] ~= value then Set(key, value) end
        end
    end
    return true
end

-- Import: nur bekannte Einstellungen mit gültigem Wert (der Text kann von irgendwoher kommen). nil = unbrauchbar.
function Profiles.Clean(data)
    if type(data) ~= "table" or type(data.settings) ~= "table" then return nil end
    local settings, any, src = {}, false, Profiles.Adopted(data.settings)
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
-- dieses Charakters laden (Spezialisierung → Charakter → Klasse → Standard). → true, wenn das Ausgangsprofil eben
-- angelegt wurde.
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

-- Vor den übrigen Aufgaben beim Einloggen (TOC: gleich nach Core.lua), damit die Teile mit den Werten des richtigen
-- Profils starten.
ns.OnReady(function()
    ns.Try("Profiles", Profiles.Login)
end)

-- Vergessene Twinks (CHAR_FORGOTTEN): ihre Zuordnungen streicht seit Welle 23 (A14) ezCores Profil-Gerüst selbst
-- (P.Forget, Felder specMode und profileFor); das Profil selbst bleibt.

-- /ezk status: welches Profil gilt.
ns.AddStatusLine(function()
    local line = L.STATUS_PROFILE:format(P.Label())
    if P.SpecMode() then line = line .. " – " .. CoreTexts.PROFILE_FOR_SPEC end
    return line
end)
