local Core = ezCore

--[[
    Talentbäume des gespielten Charakters: Core.Talents (Paket kern/talentbaum-rotationen, 24.11.2026). Anlass: Frage des
    Nutzers vom 24.11.2026 („sind die angezeigten rotationen an die talentvorlagen gekoppelt? …“, Wortlaut im
    ROADMAP-Index) und der Fehler dabei: ezCombats „Nach Talentbaum“ fragte GetSpecialization nach der Nummer des
    Talentbaums. Forever führt je Klasse genau EINE Spezialisierung (Client-Tabelle ChrSpecialization, Build 1.60.1.71037:
    1482 Magier … 1491 Krieger; Datenprobe A11: C_SpecializationInfo.GetSpecialization() = 1 und
    GetNumSpecializationsForClassID() = 1 für vier Klassen) – sie sagt nie, in welchem Baum die Punkte liegen.

    Quelle (Leitlinie 11): die Trait-Schnittstelle des Clients, wie Blizzards Talentfenster (Gethe/wow-ui-source, Zweig
    forever, Blizzard_PlayerSpells/Camelot/ClassTalents): Konfiguration der aktiven Gruppe über
    C_SpecializationInfo.GetCombatConfigIDForSpecGroup, die drei Bäume als Gruppen über
    C_Traits.GetGroupDisplayInfoByTreeID, ihre Punkte über GetGroupCurrencyInfo. Gelesen wird nur, jeder Aufruf geschützt
    (Core.Call), jeder Wert und jede Tabelle zuerst auf geheim geprüft (Core.Num, Tab, Field).

      Talents.SpecGroup()          → aktive Spezialisierungsgruppe (1 oder 2)
      Talents.ConfigID()           → Konfiguration dieser Gruppe | nil
      Talents.TreeID(configID)     → erster Baum der Konfiguration | nil
      Talents.Groups(configID, treeID) → { { id, name, icon, spent } } (Talentbäume 1–3 in Blizzards Reihenfolge), lesbar
                                     (false: der Client antwortet nicht oder ein Wert ist gesperrt; ein Baum ohne Angabe
                                     zählt 0 Punkte)
      Talents.Primary(groups)      → Nummer des Baums mit den meisten Punkten (Gleichstand: der erste; ohne Punkte nil)
      Talents.GroupText(groups)    → „12 / 31 / 8“
      Talents.HasStaged(configID)  → gibt es unbestätigte Änderungen?
      Talents.Current()            → Stand des Charakters { main (1–3, nil ohne Punkte), spent = { n, n, n }, names = { … },
                                     points } (Kopie) | nil (der Client liefert noch nichts, oder die Punkte der eben
                                     gewählten Spezialisierungsgruppe sind noch nicht gelesen). Nur Bestätigtes: solange
                                     Änderungen vorgemerkt sind, gilt der letzte bestätigte Stand derselben Konfiguration;
                                     gibt es keinen, ist der Stand unbekannt. Gemerkt, bis ein Ereignis kommt.
      Talents.MainTree()           → Nummer (1–3) | nil, bekannt (true: gelesen, nil heißt „keine Punkte“; false: unbekannt)
      Talents.TreeName(n)          → Name des Talentbaums n der eigenen Klasse aus dem Client | nil
      Talents.Role(klasse, n)      → Rolle des Baums ("TANK" | "HEALER" | "DAMAGER"), Reichweite ("melee" | "ranged" |
                                     "caster") | nil (Talents.TREES, die eine Zuordnung)
      Nachricht TALENTS_CHANGED (hauptbaum, stand) – beim ersten Lesen nach dem Einloggen und wenn sich die bestätigten
                                     Punkte je Baum oder die Konfiguration (Spezialisierungsgruppe) geändert haben. Umlernen
                                     mit denselben Summen je Baum meldet sie nicht (dafür gibt es SPELLS_CHANGED).
]]

local Talents = {}
Core.Talents = Talents

local Num = Core.Num

local function Traits(name, ...)
    local api = rawget(_G, "C_Traits")
    if type(api) ~= "table" then return nil end
    return Core.Call(api[name], ...)
end

function Talents.SpecGroup()
    local spec = rawget(_G, "C_SpecializationInfo")
    return type(spec) == "table" and Num(Core.Call(spec.GetActiveSpecGroup)) or 1
end

function Talents.ConfigID()
    local spec = rawget(_G, "C_SpecializationInfo")
    local id = type(spec) == "table" and Num(Core.Call(spec.GetCombatConfigIDForSpecGroup, Talents.SpecGroup())) or nil
    if id then return id end
    local talents = rawget(_G, "C_ClassTalents")
    return type(talents) == "table" and Num(Core.Call(talents.GetActiveConfigID)) or nil
end

-- Tabelle, die gelesen werden darf (keine gesperrte) | nil
local function Tab(value)
    if Core.IsSecret(value) or type(value) ~= "table" then return nil end
    return value
end

function Talents.TreeID(configID)
    if not configID then return nil end
    local info = Tab(Traits("GetConfigInfo", configID))
    local trees = info and Tab(info.treeIDs)
    return trees and Num(trees[1]) or nil
end

function Talents.Groups(configID, treeID)
    local list = {}
    local displays = treeID and Tab(Traits("GetGroupDisplayInfoByTreeID", treeID))
    if not displays then return list, false end
    local order = {}
    for index, raw in ipairs(displays) do
        local d = Tab(raw)
        local id = d and Num(d.groupID)
        if id then
            list[#list + 1] = { id = id, name = Core.Plain(d.displayName) or "", icon = Core.Plain(d.icon), spent = 0 }
            order[id] = (Num(d.orderIndex) or index) * 100 + index
        end
    end
    table.sort(list, function(a, b) return order[a.id] < order[b.id] end)
    local ids = {}
    for i, g in ipairs(list) do ids[i] = g.id end
    local infos = configID and #ids > 0 and Tab(Traits("GetGroupCurrencyInfo", configID, ids))
    if not infos then return list, false end
    -- Ein Baum, den die Antwort nicht nennt, hat 0 Punkte; ein gesperrter Wert macht die ganze Antwort unbrauchbar.
    local locked = false
    local function Field(t, key)
        local value = t and t[key]
        if Core.IsSecret(value) then
            locked = true
            return nil
        end
        return value
    end
    for i = 1, #infos do
        local info = Tab(Field(infos, i))
        local gid = Num(Field(info, "traitNodeGroupID"))
        local currency = Tab(Field(Tab(Field(info, "currencyInfos")), 1))
        local spent = Num(Field(currency, "spent"))
        for _, g in ipairs(list) do
            if g.id == gid and spent then g.spent = spent end
        end
    end
    return list, not locked
end

function Talents.Primary(groups)
    local best, bestSpent = nil, 0
    for i, g in ipairs(groups or {}) do
        if (g.spent or 0) > bestSpent then best, bestSpent = i, g.spent end
    end
    return best
end

function Talents.GroupText(groups)
    local parts = {}
    for i, g in ipairs(groups or {}) do parts[i] = tostring(g.spent or 0) end
    return table.concat(parts, " / ")
end

function Talents.HasStaged(configID)
    return configID ~= nil and Core.Plain(Traits("ConfigHasStagedChanges", configID)) == true
end

---------------------------------------------------------------------------
-- Stand des Charakters (gemerkt, bis ein Ereignis kommt)
---------------------------------------------------------------------------

local READ_GAP = 0.5                    -- solange nichts Lesbares kommt, höchstens so oft neu fragen
local RETRY_GAP, RETRIES = 2, 5         -- nach einem Ereignis ohne lesbare Antwort: so oft von selbst nachfragen

local current, currentConfig, currentGroup     -- letzter bestätigter Stand, seine Konfiguration und Gruppe
local dirty, nextRead, reported, tries = true, 0, "", 0
local checking = false                          -- Check liest gerade und meldet selbst
local CheckSoon

-- Der gemerkte Stand, wenn er zur aktiven Gruppe und (soweit der Client sie nennt) zu ihrer Konfiguration gehört – nach
-- einem Wechsel der Spezialisierungsgruppe nie der Baum der anderen.
local function Kept(group, configID)
    if current and currentGroup == group and (configID == nil or configID == currentConfig) then return current end
    return nil
end

local function Key() return current and (currentConfig .. ":" .. table.concat(current.spent, "/")) or "" end

-- → Stand | nil (unbekannt), Antwort steht aus (true: gesperrt oder noch nicht geladen – später noch einmal fragen)
local function Read()
    if current and not dirty then return current, false end
    local group = Talents.SpecGroup()
    local now = GetTime()
    if now < nextRead then return Kept(group), false end
    nextRead = now + READ_GAP
    local configID = Talents.ConfigID()
    local treeID = Talents.TreeID(configID)
    if not treeID then return Kept(group, configID), true end          -- der Client liefert noch nichts
    -- Vorgemerktes zählt nicht: Blizzards Punkte je Baum enthalten es schon vor „Änderungen anwenden“. Bestätigen und
    -- Verwerfen melden sich selbst (TRAIT_CONFIG_UPDATED).
    if Talents.HasStaged(configID) then return Kept(group, configID), false end
    local groups, readable = Talents.Groups(configID, treeID)
    if not readable then return Kept(group, configID), true end
    local stand = { main = Talents.Primary(groups), spent = {}, names = {}, points = 0 }
    for i, g in ipairs(groups) do
        stand.spent[i], stand.names[i] = g.spent, g.name
        stand.points = stand.points + g.spent
    end
    current, currentConfig, currentGroup, dirty = stand, configID, group, false
    -- erst ein Aufrufer bekam die Antwort, nicht das Ereignis: die Nachricht nachholen
    if not checking and Key() ~= reported then CheckSoon() end
    return current, false
end

local function Copy(stand)
    if not stand then return nil end
    local out = { main = stand.main, points = stand.points, spent = {}, names = {} }
    for i, n in ipairs(stand.spent) do out.spent[i], out.names[i] = n, stand.names[i] end
    return out
end

function Talents.Current() return Copy((Read())) end

function Talents.MainTree()
    local stand = Read()
    if not stand then return nil, false end
    return stand.main, true
end

function Talents.TreeName(n)
    local stand = n and Read()
    local name = stand and stand.names[n]
    return type(name) == "string" and name ~= "" and name or nil
end

---------------------------------------------------------------------------
-- Rolle je Talentbaum
---------------------------------------------------------------------------

-- Klasse → je Talentbaum (1–3, Reihenfolge des Clients) Rolle und Reichweite. Quelle: die Vorlagen desselben Baums in
-- ezTalent (Presets.lua: recherchiert, Quellen dort; Computed.lua: style.role und style.range, Build 1.60.1.71037);
-- tools/Tests/gewichtung_talente_test.lua prüft das bei jedem Lauf. Zwei Bäume haben Vorlagen verschiedener Art, dort gilt
-- die Grundverteilung: Druide „Wilder Kampf“ (Katze: Schaden, Bär: Tank – die Punkte verraten die Gestalt nicht) und Jäger
-- „Überleben“ (Nahkampf, als Spielweise auch Fernkampf).
Talents.TREES = {
    WARRIOR = { { "DAMAGER", "melee" }, { "DAMAGER", "melee" }, { "TANK", "melee" } },
    PALADIN = { { "HEALER", "caster" }, { "TANK", "melee" }, { "DAMAGER", "melee" } },
    HUNTER = { { "DAMAGER", "ranged" }, { "DAMAGER", "ranged" }, { "DAMAGER", "melee" } },
    ROGUE = { { "DAMAGER", "melee" }, { "DAMAGER", "melee" }, { "DAMAGER", "melee" } },
    PRIEST = { { "HEALER", "caster" }, { "HEALER", "caster" }, { "DAMAGER", "caster" } },
    SHAMAN = { { "DAMAGER", "caster" }, { "DAMAGER", "melee" }, { "HEALER", "caster" } },
    MAGE = { { "DAMAGER", "caster" }, { "DAMAGER", "caster" }, { "DAMAGER", "caster" } },
    WARLOCK = { { "DAMAGER", "caster" }, { "DAMAGER", "caster" }, { "DAMAGER", "caster" } },
    DRUID = { { "DAMAGER", "caster" }, { "DAMAGER", "melee" }, { "HEALER", "caster" } },
}

function Talents.Role(class, n)
    local trees = class ~= nil and Talents.TREES[class] or nil
    local tree = trees and n ~= nil and trees[n] or nil
    if not tree then return nil end
    return tree[1], tree[2]
end

-- Nach einem Ereignis neu lesen; nur bei geändertem Stand melden (nie für „unbekannt“). Kommt nichts Lesbares, fragt sie
-- ein paar Mal nach; nach dem Kampf noch einmal.
local function Check()
    dirty, nextRead, checking = true, 0, true
    local stand, pending = Read()
    checking = false
    if stand and not dirty then
        local key = Key()
        if key ~= reported then
            reported = key
            Core.Fire("TALENTS_CHANGED", stand.main, Copy(stand))
        end
    elseif pending and tries < RETRIES then
        tries = tries + 1
        C_Timer.After(RETRY_GAP, function() if dirty then Check() end end)
    end
end

function Talents.Check()
    tries = 0
    Check()
end

-- Alles vergessen (Prüfungen)
function Talents.Forget()
    current, currentConfig, currentGroup, dirty, nextRead, reported, tries = nil, nil, nil, true, 0, "", 0
end

CheckSoon = Core.Throttle(function() Talents.Check() end, 0.2, Core.name)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
    Core.RegisterEvent(Core.name, event, function() CheckSoon() end)
end
Core.RegisterEvent(Core.name, "PLAYER_REGEN_ENABLED", function() if dirty then CheckSoon() end end)
