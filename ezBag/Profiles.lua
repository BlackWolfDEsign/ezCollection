local ADDON, ns = ...
local L = ns.L

--[[
    Layout-Profile: Die Gruppen-Anordnung als Profil speichern und je
    Charakter oder je Klasse merken. Beim Einloggen lädt ezBag das passende Profil:
    zuerst das des Charakters, sonst das seiner Klasse, sonst „Standard“.
    Ein Profil enthält: Reihenfolge, Namen, Sortierung, Unterteilung und „neue Reihe“ der Gruppen,
    eigene Gruppen mit Regeln, Zuweisungen von Gegenständen, Zugeklappt, Spaltenzahl der Tasche,
    Sortierung aller Gruppen. Das aktuelle Layout ist immer das aktive Profil; vor jedem Wechsel
    und beim Ausloggen wird es zurück ins Profil geschrieben.
    Sichtbar: Menü „Layout-Profil“ im Sortierknopf der Werkzeugleiste und auf der Einstellungsseite.
    Als Text exportieren und importieren (ezCore.Serialize): Ein importiertes Layout wird ein neues
    Profil, das aktuelle bleibt unverändert in seinem Profil.
    Seit 1.8 über ezCores Gerüst (Core.NewProfiles, eines für ezBag und ezPanel): Liste, Wechsel,
    Zuordnung, Export/Import, Menü und allgemeine Texte kommen von dort; ezBag liefert nur, was ein
    Layout ist (Snapshot, Apply, Clean) und die Texte, die vom Layout sprechen. Gespeichert wird wie
    bisher in ezBagDB (profiles, activeProfile, profileFor); alte Export-Texte lassen sich weiter lesen.
    Die bisherigen Funktionen bleiben als Weiterleitung.
]]

local Profiles = {}
ns.Profiles = Profiles

local DEFAULT = "Standard"
-- Felder in ezBagDB, die zum Layout gehören (Tabellen werden kopiert).
local DB_KEYS = { "order", "groups", "custom", "customNext", "collapsedBy", "assign", "bagCols" }
local SETTING_KEYS = { "sortMode" }
local KIND, VERSION = "ezBag.groups", 1
local TABLE_KEYS = { order = true, groups = true, custom = true, collapsedBy = true, assign = true }
local NUMBER_KEYS = { customNext = true, bagCols = true }

local Copy = ezCore.CopyTable

-- Aktuelles Layout → Schnappschuss.
function Profiles.Snapshot()
    local snap = { db = {}, settings = {} }
    for _, key in ipairs(DB_KEYS) do snap.db[key] = Copy(ns.db[key]) end
    for _, key in ipairs(SETTING_KEYS) do snap.settings[key] = ns.S[key] end
    return snap
end

-- Schnappschuss → aktuelles Layout.
function Profiles.Apply(snap)
    snap = snap or {}
    local db, settings = snap.db or {}, snap.settings or {}
    for _, key in ipairs(DB_KEYS) do ns.db[key] = Copy(db[key]) end
    for _, key in ipairs(SETTING_KEYS) do ns.S[key] = settings[key] end
    -- Pflichtfelder wie beim Laden (Core.lua)
    ns.db.assign = ns.db.assign or {}
    ns.db.groups = ns.db.groups or {}
    ns.db.custom = ns.db.custom or {}
    ns.db.collapsedBy = ns.db.collapsedBy or { bag = {}, bank = {}, guild = {}, window = {} }
end

local function Refresh()
    if ns.Groups then
        ns.Groups.ResetIndex()
        ns.Groups.RefreshAll()
    end
end

-- Nur bekannte Felder mit passendem Typ übernehmen (der Text kann von irgendwoher kommen).
local function Clean(layout)
    if type(layout) ~= "table" then return nil end
    local db, settings = {}, {}
    for key, v in pairs(type(layout.db) == "table" and layout.db or {}) do
        if (TABLE_KEYS[key] and type(v) == "table") or (NUMBER_KEYS[key] and type(v) == "number") then db[key] = v end
    end
    local s = type(layout.settings) == "table" and layout.settings or {}
    if type(s.sortMode) == "string" then settings.sortMode = s.sortMode end
    return { db = db, settings = settings }
end
Profiles.Clean = Clean

local P = ezCore.NewProfiles({
    owner = ADDON,
    db = function() return ns.db end,
    snapshot = Profiles.Snapshot,
    apply = function(data)
        Profiles.Apply(data)
        Refresh()
    end,
    clean = Clean,
    kind = KIND, version = VERSION, wrap = "layout", default = DEFAULT,
    scopes = { class = true },
    texts = L, print = ns.Print, hint = L.PROFILE_HINT,
})
Profiles.P = P

---------------------------------------------------------------------------
-- Weiterleitungen (die bisherigen Funktionen, Leitlinie 8)
---------------------------------------------------------------------------

function Profiles.Active() return P.Active() end
function Profiles.Label(name) return P.Label(name) end      -- „Standard“ heißt auf Englisch „Default“
function Profiles.Names() return P.Names() end
function Profiles.SaveActive() return P.Save() end
function Profiles.Switch(name, quiet) return P.Switch(name, quiet) end
-- Neues Profil aus dem aktuellen Layout, gleich aktiv → true (gibt es den Namen schon, mit Zusatz).
function Profiles.Create(name) return P.Create(name) ~= nil end
-- Löschen; ist es aktiv, gilt danach „Standard“ (wie in ezCores Gerüst).
function Profiles.Delete(name) return P.Delete(name) end
-- Wer bekommt welches Profil: "char" (dieser Charakter) oder "class" (alle dieser Klasse).
function Profiles.AssignedTo(scope) return P.Assigned(scope) end
function Profiles.Assign(scope, name) return P.Assign(scope, name) end
-- Passendes Profil für diesen Charakter: eigenes, sonst das der Klasse, sonst „Standard“.
function Profiles.Wanted() return P.Wanted() end
function Profiles.OnLogin() return P.Load(false) end
function Profiles.Export() return P.Export() end

-- Text → neues Profil, gleich aktiv → true, Name oder false, Grund.
function Profiles.Import(text)
    local name, reason = P.Import(text)
    if name then return true, name end
    return false, reason
end

function Profiles.ShowExport() return P.ShowExport() end
function Profiles.ShowImport() return P.ShowImport() end

---------------------------------------------------------------------------
-- Menü (Sortierknopf der Werkzeugleiste, Einstellungsseite)
---------------------------------------------------------------------------

function Profiles.AddMenu(root)
    local sub = root:CreateButton(L.PROFILE_MENU:format(P.Label()))
    P.FillMenu(sub)
    return sub
end

function Profiles.OpenMenu(owner)
    ezCore.Menu.Open(owner, function(root) Profiles.AddMenu(root) end)
end

-- Beim Einloggen das passende Profil laden; beim Ausloggen sichert ezCores Gerüst.
ns.OnReady(function() Profiles.OnLogin() end)
