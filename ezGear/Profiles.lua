local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Profile (Entscheidung des Nutzers 13.11.2026: „Profile, wo es klassenabhängig ist“ – ezCombat, ezBuff, ezGear,
    ezBars über ezCores Profil-Gerüst). ezGear liefert nur, was ein Profil ist; Liste, Wechsel, Zuordnung
    (Charakter, Klasse, Spezialisierung), Export/Import, Menü, Sichern beim Ausloggen und die allgemeinen Texte
    kommen von Core.NewProfiles.

    Ein Profil hält
      settings   die Schalter und Regler der Einstellungsseite (ezGearDB.settings)
      byClass    je Klasse die Wahl des Charakters: Gewichtung (scale), Reit-Set (mountSet), Angel-Set (fishSet)
    Die Wahl liegt weiter je Charakter in ezGearDB.chars[charKey] (Arbeitsdaten) – im Profil je Klasse, damit ein
    Profil, das mehrere Charaktere nutzen, einem Krieger nicht die Gewichtung des Magiers gibt. Pawn-Skalen
    (ezGearDB.scales) gelten für alle und gehören zu keinem Profil; fehlt eine gewählte Skala, gilt „Automatisch“.
    Der Stand des automatischen Umziehens (chars[charKey].swap) gehört nicht ins Profil.
    Der Eintrag einer Klasse gilt für alle Charaktere dieser Klasse, die das Profil nutzen: Beim Wechsel aufs
    Profil wird er übernommen; ist das Profil beim Einloggen schon aktiv (activeProfile gilt für alle; etwa ein
    Profil der Klasse oder „Standard“), übernimmt ihn ein Charakter ohne eigene Wahl (Profiles.Login) – sonst
    würde sein Ausloggen den Eintrag leeren. Hat der Charakter schon eine eigene Wahl, bleibt sie und steht nach dem Ausloggen im Profil.

    Die Arbeitsdaten bleiben ezGearDB.settings (alle Dateien greifen über ns.S darauf zu): Beim Wechsel werden die
    Werte in dieselbe Tabelle geschrieben (ns.SetSetting), alle Verweise bleiben gültig.
    Gespeichert (Felder des Gerüsts): ezGearDB.profiles[name], activeProfile (nil = „Standard“),
    profileFor[charKey | "class:MAGE" | "charKey#Gruppe"], specMode[charKey].

    Sichtbar: Einstellungen → ezGear → Abschnitt „Profile“ (page:Profiles, Options.lua), Menü „Sets“ am
    Charakterfenster → „Profil: …“, zusätzlich /ezg profil [Name].
]]

local Profiles = {}
ns.Profiles = Profiles

local KIND, VERSION = "ezGear.profile", 1
local CHOICES = { "scale", "mountSet", "fishSet" }
Profiles.KIND, Profiles.CHOICES = KIND, CHOICES

local P

local function ClassToken()
    if ns.playerClass then return ns.playerClass end
    return Core.PlayerClass()      -- ezCore: gesperrt oder unbekannt → nil (V-179)
end

-- Wahl einer Klasse: nur Texte ("" = „keins“ bei den Sets), alles andere fällt weg.
local function CleanChoice(entry)
    local out = {}
    if type(entry) ~= "table" then return out end
    for _, key in ipairs(CHOICES) do
        local value = entry[key]
        if type(value) == "string" and not ns.IsSecret(value) and #value <= 200 then out[key] = value end
    end
    return out
end

local function CleanByClass(byClass)
    local out = {}
    for class, entry in pairs(type(byClass) == "table" and byClass or {}) do
        if type(class) == "string" and class:match("^%u+$") and type(entry) == "table" then
            out[class] = CleanChoice(entry)
        end
    end
    return out
end

-- Arbeitsdaten → Profil (Kopie). Die Wahl anderer Klassen bleibt, wie sie im gespeicherten Profil steht.
local function Snapshot()
    local data = { settings = {}, byClass = {} }
    for key, default in pairs(ns.DEFAULTS) do
        local value = ns.S and ns.S[key]
        if type(value) == type(default) then data.settings[key] = value end
    end
    local stored = ns.db and type(ns.db.profiles) == "table" and P and ns.db.profiles[P.Active()]
    if type(stored) == "table" then data.byClass = CleanByClass(stored.byClass) end
    local class = ClassToken()
    if class and ns.db and ns.charKey then data.byClass[class] = CleanChoice(ns.Char()) end
    return data
end
Profiles.Snapshot = Snapshot

-- Wahl der eigenen Klasse aus einem Profil auf den Charakter. true = das Profil hatte einen Eintrag.
local function ApplyChoice(data)
    local class = ClassToken()
    local entry = class and type(data) == "table" and type(data.byClass) == "table" and data.byClass[class]
    if type(entry) ~= "table" or not ns.charKey then return false end
    local char = ns.Char()
    local clean = CleanChoice(entry)
    for _, key in ipairs(CHOICES) do char[key] = clean[key] end
    return true
end

-- Hat der Charakter schon selbst gewählt (Gewichtung, Reit- oder Angel-Set)?
local function HasOwnChoice()
    if not (ns.db and ns.charKey) then return false end
    local char = ns.Char()
    for _, key in ipairs(CHOICES) do
        if char[key] ~= nil then return true end
    end
    return false
end
Profiles.HasOwnChoice = HasOwnChoice

-- Profil → Arbeitsdaten. Jeder geänderte Schalter meldet sich wie von Hand umgestellt (ns.SetSetting).
local function Apply(data)
    if type(data) ~= "table" or not ns.S then return end
    local settings = type(data.settings) == "table" and data.settings or {}
    for key, default in pairs(ns.DEFAULTS) do
        local value = settings[key]
        if type(value) == type(default) and ns.S[key] ~= value then ns.SetSetting(key, value) end
    end
    ApplyChoice(data)
    ns.Changed()
    if ns.Swap and ns.Swap.Evaluate then ns.Try("Swap", ns.Swap.Evaluate) end
end
Profiles.Apply = Apply

-- Import: nur bekannte Schalter mit passendem Typ, nur Texte als Wahl. nil = unbrauchbar.
local function Clean(data)
    if type(data) ~= "table" then return nil end
    local out = { settings = {}, byClass = CleanByClass(data.byClass) }
    local settings = type(data.settings) == "table" and data.settings or {}
    for key, default in pairs(ns.DEFAULTS) do
        local value = settings[key]
        if type(value) == type(default) and not ns.IsSecret(value) then out.settings[key] = value end
    end
    return out
end
Profiles.Clean = Clean

P = Core.NewProfiles({
    owner = ADDON,
    db = function() return ns.db end,
    snapshot = Snapshot,
    apply = Apply,
    clean = Clean,
    kind = KIND, version = VERSION, wrap = "profile",
    scopes = { class = true, spec = true },
    -- Die Auswahl gilt gleich für diesen Charakter bzw. seine Spezialisierung (P.Use), wie bei ezBars, ezCombat und
    -- ezPanel. Ohne perChar stellte page:Profiles nur das kontoweite activeProfile um, und P.Load fiel beim nächsten
    -- Einloggen auf „Standard“ zurück (Fund der Gegenprüfung, Welle 23); das Menü hatte dafür ein eigenes Kästchen
    -- „für diesen Charakter“, der Abschnitt der Einstellungsseite nicht.
    perChar = true,
    texts = L, print = ns.Print, hint = L.PROFILE_HINT,
})
Profiles.P = P

function Profiles.Active() return P.Active() end
function Profiles.Label(name) return P.Label(name) end

---------------------------------------------------------------------------
-- Sichtbar: Menü (Einstellungen, Menü „Sets“), Befehl
---------------------------------------------------------------------------

function ns.OpenProfileMenu(owner)
    return Core.Menu.Open(owner or UIParent, function(root) P.FillMenu(root) end)
end

-- Untermenü „Profil: …“ in einem anderen Menü (Menü „Sets“ am Charakterfenster)
function ns.AddProfileMenu(root)
    local label = L.PROFILE_MENU:format(P.Label())
    local sub = ns.MenuTip(Core.Menu.Button(root, label), label, L.MTIP_PROFILE)
    if sub and sub.CreateTitle then P.FillMenu(sub) end
    return sub
end

-- /ezg profil [Name]: ohne Name das Menü, mit Name wechseln (Groß-/Kleinschreibung egal) – für diesen Charakter
-- bzw. seine Spezialisierung wie die Auswahl der Einstellungsseite (P.Use, perChar)
function ns.SwitchProfileByName(name)
    name = type(name) == "string" and Core.Trim(name) or ""
    if name == "" then return ns.OpenProfileMenu(UIParent) end
    local wanted = name:lower()
    for _, known in ipairs(P.Names()) do
        if known:lower() == wanted or P.Label(known):lower() == wanted then return P.Use(known) end
    end
    ns.Print(L.PROFILE_UNKNOWN:format(name))
    return false
end

---------------------------------------------------------------------------

-- Einloggen: das passende Profil für diesen Charakter (Spezialisierung → Charakter → Klasse → Standard).
-- P.Load übernimmt nur bei einem Wechsel; ist das Profil schon aktiv und der Charakter hat noch keine eigene
-- Wahl, bekommt er hier die Wahl seiner Klasse aus dem gespeicherten Profil. true = übernommen.
function Profiles.Login()
    local before = P.Active()
    P.Load(true)
    if P.Active() ~= before or HasOwnChoice() then return false end
    local stored = ns.db and type(ns.db.profiles) == "table" and ns.db.profiles[P.Active()]
    if not ApplyChoice(stored) or not HasOwnChoice() then return false end
    ns.Changed()
    if ns.Swap and ns.Swap.Evaluate then ns.Try("Swap", ns.Swap.Evaluate) end
    return true
end

ns.OnReady(function()
    ns.Try("Profiles", Profiles.Login)
end)

-- Vergessene Twinks: ihre Zuordnungen (specMode, profileFor samt „charKey#Gruppe“) streicht ezCores Gerüst selbst
-- (P.Forget, Zuhörer auf CHAR_FORGOTTEN in Core.NewProfiles; Welle 23, vorher hier eine Kopie). Das Profil selbst bleibt;
-- die Arbeitsdaten des Charakters (ezGearDB.chars) streicht Core.lua.

ns.AddStatusLine(function()
    local line = L.STATUS_PROFILE:format(P.Label())
    if P.SpecMode() then line = line .. " – " .. L.PROFILE_FOR_SPEC end
    return line
end)
