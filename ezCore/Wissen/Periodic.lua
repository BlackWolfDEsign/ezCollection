local _, ns = ...
local Core = ezCore

--[[
    Schaden und Heilung über Zeit eigener Zauber – Grundlage für Restschaden und Restheilung am Lebensbalken (Auftrag:
    docs/roadmap/ezCore.md, „Restschaden und Restheilung – Kern“; Wunsch und Entscheidungen des Nutzers vom 22.11.2026
    im ROADMAP-Index). Quelle (Leitlinie 11): die ausgelieferte Client-Tabelle Wissen/Client/Periodic.lua (laut
    wago.tools, erzeugt von tools/wago_ausliefern.lua, A.Periodic). Geschätzt wird nur mit offenen Werten (Leitlinie 6):
    ist Stufe, Zaubermacht oder Angriffskraft gesperrt, gibt es keine Schätzung – nie eine Rechnung mit einem gesperrten
    Wert. Nicht eingerechnet: Talente, Tempo, Boni, kritische Treffer, Widerstände; darum heißt jede Zahl „geschätzt“.

      Periodic.KEY                        "periodic" (Schlüssel in ezCore.ClientData)
      Periodic.KIND                       Art laut Tabelle → "dot" (1), "hot" (2), "percent" (3, Prozent des Höchstlebens)
      Periodic.Info(zauber)               → { id, duration, period (Sekunden), ticks, school (Maske), kind, base,
                                             perLevel, coefSP, coefAP, baseLevel, maxLevel, spellLevel } oder nil
                                             (Tabelle fehlt, Zauber unbekannt, gesperrt). Den Sofortteil desselben
                                             Zaubers führt seit 23.11.2026 ezCore.SpellValue (Client/Direct.lua).
      Periodic.Level(info)                → Stufe für die Punkte je Stufe: eigene Stufe zwischen Grund- und Höchststufe
                                             (Annahme nach der üblichen Formel: gezählt ab der Zauberstufe; in Build
                                             1.60.1.71037 sind Grund- und Zauberstufe bei allen Zeilen mit Punkten je
                                             Stufe gleich) oder nil, "secret"
      Periodic.Power(info)                → Zaubermacht (bei Heilung die Heilungsboni), Angriffskraft – nur die, die der
                                             Tick braucht (sonst 0; der Sofortteil zählt nicht) – oder nil, "secret"
      Periodic.Tick(zauber)               → geschätzte Höhe eines Ticks oder nil, grund ("unknown" | "secret" | "percent")
      Periodic.Total(zauber)              → Tick × Ticks (ohne Sofortteil) oder nil, grund
      Periodic.Left(info, seit)           → noch ausstehende Ticks seit dem Wirken (seit in Sekunden, 0 … ticks) oder nil
      Periodic.Remaining(zauber, seit)    → Rest der Wirkung: Tick × ausstehende Ticks, oder nil, grund
      Periodic.SourceText()               → „geschätzt aus den Client-Tabellen (wago.tools, Build …)“
]]

local Periodic = {}
Core.Periodic = Periodic

Periodic.KEY = "periodic"
Periodic.KIND = { [1] = "dot", [2] = "hot", [3] = "percent" }

local L = Core.NewLocale({
    PERIODIC_SOURCE = "geschätzt aus den Client-Tabellen (wago.tools, Build %s)",
}, {
    PERIODIC_SOURCE = "estimated from the client tables (wago.tools, build %s)",
})
Periodic.L = L

-- Schulmaske → Index für GetSpellBonusDamage (1 körperlich, 2 Heilig, 3 Feuer, 4 Natur, 5 Frost, 6 Schatten, 7 Arkan)
local SCHOOLS = { 1, 2, 4, 8, 16, 32, 64 }

-- Aufruf einer Client-Funktion → offene Zahl, false (gesperrt oder Fehler) bzw. nil (Funktion fehlt)
local function Ask(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or Core.IsSecret(value) then return false end
    return Core.Num(value) or false
end

function Periodic.Info(spellID)
    local id = Core.Num(spellID)
    local CD = Core.ClientData
    local data = id and CD and CD.Table and CD.Table(Periodic.KEY)
    local row = type(data) == "table" and data[id] or nil
    if type(row) ~= "table" then return nil end
    local duration, period = (row[1] or 0) / 1000, (row[2] or 0) / 1000
    if duration <= 0 or period <= 0 then return nil end
    local info = { id = id, duration = duration, period = period, ticks = math.floor(duration / period + 1e-6),
        school = row[3] or 0, kind = Periodic.KIND[row[4]] or "dot", base = row[5] or 0, perLevel = row[6] or 0,
        coefSP = row[7] or 0, coefAP = row[8] or 0, baseLevel = row[9] or 0, maxLevel = row[10] or 0 }
    info.spellLevel = row[11] or info.baseLevel
    return info
end

function Periodic.Level(info)
    if type(info) ~= "table" then return nil, "unknown" end
    if (info.perLevel or 0) == 0 then return info.baseLevel or 0 end   -- ohne Punkte je Stufe egal
    local level = Ask("UnitLevel", "player")
    if not level then return nil, "secret" end
    if (info.maxLevel or 0) > 0 and level > info.maxLevel then level = info.maxLevel end
    if level < (info.baseLevel or 0) then level = info.baseLevel or 0 end
    return level
end

-- Zaubermacht der Schule: die höchste der Schulen in der Maske (Mischschulen)
local function SpellDamage(mask)
    local best
    for index, bitValue in ipairs(SCHOOLS) do
        if bit.band(mask or 0, bitValue) ~= 0 then
            local value = Ask("GetSpellBonusDamage", index)
            if value == false then return nil end
            if value and (not best or value > best) then best = value end
        end
    end
    return best or 0
end

local function AttackPower()
    local fn = rawget(_G, "UnitAttackPower")
    if type(fn) ~= "function" then return 0 end
    local ok, base, plus, minus = pcall(fn, "player")
    if not ok then return nil end
    local total = 0
    -- jeder Rohwert zuerst über Core.IsSecret (kein „or 0“ mit einem gesperrten Wert, Review vom 23.11.2026; Core.Usable
    -- zählt über select("#"), auch hinter einem nil)
    if not Core.Usable(base, plus, minus) then return nil end
    for _, value in pairs({ base, plus, minus }) do
        local n = Core.Num(value)
        if n == nil then return nil end
        total = total + n
    end
    return total
end

function Periodic.Power(info)
    if type(info) ~= "table" then return nil, "unknown" end
    local sp, ap = 0, 0
    if (info.coefSP or 0) ~= 0 then
        if info.kind == "hot" then
            sp = Ask("GetSpellBonusHealing")
            if sp == false then return nil, "secret" end
            sp = sp or 0
        else
            sp = SpellDamage(info.school)
            if sp == nil then return nil, "secret" end
        end
    end
    if (info.coefAP or 0) ~= 0 then
        ap = AttackPower()
        if ap == nil then return nil, "secret" end
    end
    return sp, ap
end

function Periodic.Tick(spellID)
    local info = Periodic.Info(spellID)
    if not info then return nil, "unknown" end
    if info.kind == "percent" then return nil, "percent" end   -- braucht das Höchstleben des Ziels
    local level, why = Periodic.Level(info)
    if not level then return nil, why end
    local sp, ap = Periodic.Power(info)
    if not sp then return nil, ap end
    local tick = info.base + info.perLevel * (level - info.spellLevel) + info.coefSP * sp + info.coefAP * ap
    if tick < 0 then tick = 0 end
    return tick
end

function Periodic.Total(spellID)
    local tick, why = Periodic.Tick(spellID)
    if not tick then return nil, why end
    return tick * Periodic.Info(spellID).ticks
end

function Periodic.Left(info, since)
    since = Core.Num(since)
    if type(info) ~= "table" or not since or since < 0 or (info.period or 0) <= 0 then return nil end
    local done = math.floor(since / info.period + 1e-6)
    if done > info.ticks then done = info.ticks end
    return info.ticks - done
end

function Periodic.Remaining(spellID, since)
    local info = Periodic.Info(spellID)
    if not info then return nil, "unknown" end
    local left = Periodic.Left(info, since)
    if not left then return nil, "unknown" end
    local tick, why = Periodic.Tick(spellID)
    if not tick then return nil, why end
    return tick * left
end

function Periodic.SourceText()
    local CD = Core.ClientData
    return L.PERIODIC_SOURCE:format(CD and CD.Build and CD.Build(Periodic.KEY) or "?")
end
