local _, ns = ...
local Core = ezCore

--[[
    Auren lesen (Core.Auras) – eine Stelle für ezCombat und ezBuff (vorher las jedes Modul selbst).

      Scan(unit, filter, opts) → Liste, Anzahl gesperrter Auren, Instanz-IDs (wie InstanceIDs: nil ohne
          Schnittstelle; leer → die Liste kommt aus dem Lesen nach Index), Anzahl unlesbarer Auren
          unlesbar: Es gibt eine Instanz-ID, aber keine Daten (nil) oder der Aufruf schlug fehl; beim Lesen nach
              Index ein Abbruch durch einen Fehler (zählt als 1). Wer wissen will, ob ein Buff FEHLT, wertet
              unlesbar > 0 wie gesperrt: unbekannt, nichts verlangen (Befund 13.11.2026: Der Buff lag, im Kampf kamen
              keine Daten, und das galt als „fehlt“).
          Liste { name, spellId, icon, count, duration, expires, source, instance } (expires nil = dauerhaft),
          über die Instanz-IDs nach Enum.UnitAuraSortRule.Expiration (eigene zuerst – vom Spieler gewirkt, sonst vom
          Spieler wirkbar –, dann die zuerst auslaufende, dauerhafte zuletzt; Forever-Quelle
          UnitAuraSharedDocumentation.lua, Gesamtreview 18.11.2026, T13-10), sonst in Blizzards Reihenfolge
          opts.keepSecret = true: gesperrte stehen als { secret = true, instance, icon } in der Liste (icon darf ein
              gesperrter Wert sein und geht nur unverändert an SetTexture, gerechnet wird damit nie)
          opts.durations = true: jeder Eintrag mit Instanz bekommt durationObject (Blizzards Dauer-Objekt)
          opts.max (Standard 40), opts.sort (Wert aus Enum.UnitAuraSortRule, Standard Expiration)
      InstanceIDs(unit, filter, max, sort) → { id … } (eigene zuerst, dann die zuerst auslaufende; rein nach Ablauf:
          sort = Enum.UnitAuraSortRule.ExpirationOnly) oder nil ohne Schnittstelle
      FromInstances(unit, ids, opts) → Liste, Anzahl gesperrter, Anzahl unlesbarer (opts.keepSecret, opts.durations
          wie bei Scan)
      Readable(unit, filter) → bool: nichts gesperrt, nichts unlesbar und Core.AurasLocked() sagt nicht „gesperrt“ –
          nur dann heißt „nicht in der Liste“ auch „liegt nicht“
      Jede offen gelesene Aura geht an Core.Spells.NoteAura (merkt die Dauer eigener Auren – der Client als Quelle).
      Duration(unit, instance) → Blizzards Dauer-Objekt (C_UnitAuras.GetAuraDuration) oder nil

    Warum über Instanz-IDs (Befund ezCombat, Spieltest 13.11.2026, Forever-Quelle): GetAuraDataByIndex und
    GetAuraDataByAuraInstanceID sind „SecretWhenUnitAuraRestricted“ – gesperrt ist die ganze Aura ein gesperrter
    Wert, nicht nur ihre Felder. Scan hörte dort auf und zählte sie nicht. Nie gesperrt sind GetUnitAuraInstanceIDs
    (nur Zahlen, auf Wunsch nach Ablauf sortiert) und GetAuraDuration (Dauer-Objekt je Instanz). Deshalb zuerst die
    Instanz-IDs und je Instanz die Daten oder ein Platzhalter; ohne diese Schnittstelle (oder ohne IDs) nach Index
    über C_UnitAuras, sonst UnitAura – auch dort zählt eine ganz gesperrte Aura mit, und es geht weiter.
    Geheime Werte werden vor jedem Vergleich geprüft; gelesen wird geschützt (eine gesperrte Tabelle wirft).
]]

local Auras = {}
Core.Auras = Auras

local MAX = 40

local function SortRule(sort)
    if type(sort) == "number" then return sort end
    local enum = Enum and Enum.UnitAuraSortRule
    return enum and enum.Expiration or 3
end

-- Feld einer Aura, die eine gesperrte Tabelle sein kann (Lesen schlägt dann fehl → nil): gemeinsamer Helfer in Util.lua.
local Peek = Core.Peek

local function Blocked(aura)
    return Core.IsSecret(aura.name) or Core.IsSecret(aura.spellId) or Core.IsSecret(aura.expirationTime)
        or Core.IsSecret(aura.duration)
end

-- Offene Aura → Eintrag; nil, wenn eine Angabe gesperrt ist. Läuft geschützt (pcall); instance kommt von außen
-- (Instanz-ID) oder aus der Aura.
local function Entry(aura, instance)
    if Blocked(aura) then return nil end
    local expires = Core.Num(aura.expirationTime)
    if expires and expires <= 0 then expires = nil end
    local source = Core.Plain(aura.sourceUnit)
    return {
        name = type(aura.name) == "string" and aura.name or nil,
        spellId = Core.Num(aura.spellId),
        icon = Core.Plain(aura.icon),
        count = Core.Num(aura.applications) or 0,
        duration = Core.Num(aura.duration),
        expires = expires,
        source = type(source) == "string" and source or nil,
        instance = instance or Core.Num(aura.auraInstanceID),
    }
end

local NoteAura = Core.Spells and Core.Spells.NoteAura

-- Eine Aura (offen, feldweise oder ganz gesperrt) in die Liste; Rückgabe: true, wenn sie gesperrt war.
local function Add(list, data, instance, opts)
    if not Core.IsSecret(data) and type(data) == "table" then
        local ok, entry = pcall(Entry, data, instance)
        if ok and entry then
            list[#list + 1] = entry
            if NoteAura then NoteAura(entry) end
            return false
        end
    end
    if opts.keepSecret then
        list[#list + 1] = { secret = true, instance = instance or Core.Num(Peek(data, "auraInstanceID")),
            icon = Peek(data, "icon") }
    end
    return true
end

local function AttachDurations(unit, list)
    for _, entry in ipairs(list) do
        if entry.instance then entry.durationObject = Auras.Duration(unit, entry.instance) end
    end
end

function Auras.Duration(unit, instance)
    local api = C_UnitAuras and C_UnitAuras.GetAuraDuration
    instance = Core.Num(instance)
    if type(api) ~= "function" or not instance or Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    return (Core.Call(api, unit, instance))
end

function Auras.InstanceIDs(unit, filter, max, sort)
    local api = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if type(api) ~= "function" or Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    max = Core.Num(max) or MAX
    local ids = Core.Call(api, unit, filter, max, SortRule(sort))
    if Core.IsSecret(ids) or type(ids) ~= "table" then return nil end
    local list = {}
    for _, id in ipairs(ids) do
        if #list >= max then break end
        local number = Core.Num(id)
        if number then list[#list + 1] = number end
    end
    return list
end

function Auras.FromInstances(unit, ids, opts)
    opts = opts or {}
    local list, secret, unread = {}, 0, 0
    if type(ids) ~= "table" or Core.IsSecret(unit) or type(unit) ~= "string" then return list, 0, 0 end
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if type(api) ~= "function" then return list, 0, 0 end
    for _, raw in ipairs(ids) do
        local id = Core.Num(raw)
        if id then
            local data = Core.Call(api, unit, id)
            -- nil (erst nach der Prüfung auf „gesperrt“ verglichen): Der Aufruf schlug fehl oder das Spiel gibt zu
            -- dieser Instanz keine Daten – die Aura kann trotzdem liegen, also unlesbar statt „weg“.
            if Core.IsSecret(data) or data ~= nil then
                if Add(list, data, id, opts) then secret = secret + 1 end
            else
                unread = unread + 1
            end
        end
    end
    if opts.durations then AttachDurations(unit, list) end
    return list, secret, unread
end

local function AuraAt(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end
    local legacy = rawget(_G, "UnitAura")
    if type(legacy) ~= "function" then return nil end
    local name, icon, count, _, duration, expirationTime, source, _, _, spellId = legacy(unit, index, filter)
    if Core.IsSecret(name) then return { name = name, icon = icon } end
    if name == nil then return nil end
    return { name = name, icon = icon, applications = count, duration = duration, expirationTime = expirationTime,
        sourceUnit = source, spellId = spellId }
end

-- Rückfall nach Index: Eine ganz gesperrte Aura (gesperrter Wert statt Tabelle) zählt mit, dann geht es weiter.
-- Bricht das Lesen mit einem Fehler ab, ist der Rest unlesbar (zählt als 1).
local function ByIndex(unit, filter, opts)
    local list, secret, unread = {}, 0, 0
    for index = 1, Core.Num(opts.max) or MAX do
        local ok, aura = pcall(AuraAt, unit, index, filter)
        if not ok then
            unread = 1
            break
        end
        if not Core.IsSecret(aura) and type(aura) ~= "table" then break end
        if Add(list, aura, nil, opts) then secret = secret + 1 end
    end
    if opts.durations then AttachDurations(unit, list) end
    return list, secret, unread
end

function Auras.Scan(unit, filter, opts)
    opts = opts or {}
    if Core.IsSecret(unit) or type(unit) ~= "string" then return {}, 0, nil, 0 end
    local ids = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
        and Auras.InstanceIDs(unit, filter, opts.max, opts.sort) or nil
    if ids and #ids > 0 then
        local list, secret, unread = Auras.FromInstances(unit, ids, opts)
        return list, secret, ids, unread
    end
    local list, secret, unread = ByIndex(unit, filter, opts)
    return list, secret, ids, unread
end

-- Sind die Auren der Einheit vollständig lesbar? Nur dann heißt „nicht in der Liste“ auch „liegt nicht“.
function Auras.Readable(unit, filter)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return false end
    local _, secret, _, unread = Auras.Scan(unit, filter)
    return secret == 0 and unread == 0 and (Core.AurasLocked == nil or Core.AurasLocked() ~= true)
end
