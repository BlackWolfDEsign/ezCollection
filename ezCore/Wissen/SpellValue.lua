local _, ns = ...
local Core = ezCore

--[[
    Werte einer Fähigkeit – Grundlage, um Fähigkeiten gegeneinander abzuwägen (Auftrag des Nutzers vom 23.11.2026,
    wörtlich: „ezrotation: muss die stats der fähigkeiten berücksichtigen, z.b. schattenblitz vs zauberstab, was ist im
    moment besser, wenn das geht, voll durchdacht für alle klassen“; Plan: docs/roadmap/ezCombat.md, „Offen: Werte der
    Fähigkeiten abwägen“). Quelle (Leitlinie 11): die ausgelieferten Client-Tabellen Wissen/Client/Direct.lua
    (Sofortwirkung, Kanal) und Wissen/Client/Periodic.lua (über Zeit, ezCore.Periodic), beide laut wago.tools, erzeugt
    von tools/wago_ausliefern.lua; Zauberzeit, globale Abklingzeit und Kosten fragt ezCore den Client (mit Talenten und
    Tempo), Zaubermacht und Angriffskraft wie ezCore.Periodic, den Zauberstab über UnitRangedDamage wie Blizzards
    Charakterfenster (Forever-Quelle Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua: Mittel aus min und max plus
    Boni, mal Prozent, geteilt durch das Tempo).

    Geschätzt wird nur mit offenen Werten (Leitlinie 6). Im Kampf sperrt Forever Zaubermacht und Werte: Dann gilt die
    letzte offene Rechnung desselben Zaubers (meist die vor dem Kampf) – zweiter Rückgabewert "memo"; gab es keine,
    nil und der Grund. Nicht eingerechnet: kritische Treffer, Treffer- und Widerstandschance (beide Seiten eines
    Vergleichs gleich), Schadens-Talente in Prozent, Schwächungen des Ziels, Procs.

      SpellValue.KEY                      "direct" (Schlüssel in ezCore.ClientData)
      SpellValue.GCD                      1,5 – globale Abklingzeit, wenn der Client sie nicht nennt (Annahme wie
                                          tools/talent_sim.lua, Sim.MECH)
      SpellValue.Info(zauber)             → { id, school, kind ("damage" | "heal"), base, perLevel, coefSP, coefAP,
                                             baseLevel, maxLevel, spellLevel, channel (Sekunden, 0 = kein Kanal),
                                             ticks (0 = einmal) } oder nil
      SpellValue.Amount(zauber)           → erwartete Menge je Wurf: Sofortwirkung (× Takte beim Kanal mit
                                             ausgelöstem Zauber) + Wirkung über Zeit (ezCore.Periodic) – oder nil, grund
                                             ("unknown" | "secret")
      SpellValue.Time(zauber)             → Sekunden, die der Wurf bindet: Kanaldauer, sonst die größere von Zauberzeit
                                             und globaler Abklingzeit
      SpellValue.Cost(zauber)             → Mana-Kosten (0 = keine) oder nil, true (gesperrt)
      SpellValue.Of(zauber)               → { id, amount, time, cost, dps, dpm (nil ohne Kosten), at } oder die letzte
                                             offene Rechnung und "memo", oder nil, grund
      SpellValue.Wand()                   → { dps, speed, amount, item } des Zauberstabs im Fernkampfplatz oder die
                                             letzte offene Lesung und "memo", oder nil, grund ("none" | "secret")
      SpellValue.SourceText()             → „geschätzt aus den Client-Tabellen (wago.tools, Build …) und deinen Werten“
]]

local SpellValue = {}
Core.SpellValue = SpellValue

SpellValue.KEY = "direct"
SpellValue.GCD = 1.5

local L = Core.NewLocale({
    SPELLVALUE_SOURCE = "geschätzt aus den Client-Tabellen (wago.tools, Build %s) und deinen Werten",
}, {
    SPELLVALUE_SOURCE = "estimated from the client tables (wago.tools, build %s) and your stats",
})
SpellValue.L = L

local memo, wandMemo = {}, nil

function SpellValue.Info(spellID)
    local id = Core.Num(spellID)
    local CD = Core.ClientData
    local data = id and CD and CD.Table and CD.Table(SpellValue.KEY)
    local row = type(data) == "table" and data[id] or nil
    if type(row) ~= "table" then return nil end
    local info = { id = id, school = row[1] or 0, kind = row[2] == 2 and "heal" or "damage", base = row[3] or 0,
        perLevel = row[4] or 0, coefSP = row[5] or 0, coefAP = row[6] or 0, baseLevel = row[7] or 0,
        maxLevel = row[8] or 0, channel = (row[10] or 0) / 1000, ticks = row[11] or 0 }
    info.spellLevel = row[9] or info.baseLevel
    return info
end

-- Sofortwirkung einmal (ohne Takte) → Menge oder nil, grund
local function Direct(info)
    if (info.base or 0) == 0 and (info.perLevel or 0) == 0 and (info.coefSP or 0) == 0 and (info.coefAP or 0) == 0 then
        return 0
    end
    local Periodic = Core.Periodic
    local level, why = Periodic.Level(info)
    if not level then return nil, why end
    -- Zaubermacht bzw. Heilungsboni und Angriffskraft wie ezCore.Periodic (dessen Art "hot" heißt Heilungsboni)
    local sp, ap = Periodic.Power({ coefSP = info.coefSP, coefAP = info.coefAP, school = info.school,
        kind = info.kind == "heal" and "hot" or "dot" })
    if not sp then return nil, ap end
    local amount = info.base + info.perLevel * (level - info.spellLevel) + info.coefSP * sp + info.coefAP * ap
    if amount < 0 then amount = 0 end
    return amount
end

function SpellValue.Amount(spellID)
    local info = SpellValue.Info(spellID)
    local periodic = Core.Periodic and Core.Periodic.Info(spellID)
    if not info and not periodic then return nil, "unknown" end
    local total = 0
    if info then
        local direct, why = Direct(info)
        if not direct then return nil, why end
        total = total + direct * math.max(1, info.ticks or 0)
    end
    if periodic and periodic.kind ~= "percent" then
        local over, why = Core.Periodic.Total(spellID)
        if not over then return nil, why end
        total = total + over
    end
    return total
end

-- Globale Abklingzeit eines Zaubers laut Client (GetSpellBaseCooldown, zweiter Wert in ms) oder SpellValue.GCD
local function Gcd(spellID)
    local fn = rawget(_G, "GetSpellBaseCooldown")
    if type(fn) == "function" then
        local ok, _, gcd = pcall(fn, spellID)
        if ok and not Core.IsSecret(gcd) then
            gcd = Core.Num(gcd)
            if gcd and gcd > 0 then return gcd / 1000 end
        end
    end
    return SpellValue.GCD
end

-- Zauberzeit in Sekunden laut Client (0 = sofort; gesperrt: die letzte offene Lesung, Core.Spells.CastTime) oder nil,
-- "secret" (gesperrt und nie offen gelesen – nicht dasselbe wie „sofort“)
function SpellValue.CastTime(spellID)
    local seconds, state = Core.Spells.CastTime(spellID)
    if state == "secret" then return nil, "secret" end
    return seconds
end

function SpellValue.Time(spellID)
    local id = Core.Num(spellID)
    if not id then return nil end
    local info = SpellValue.Info(id)
    if info and (info.channel or 0) > 0 then return info.channel end
    local cast, why = SpellValue.CastTime(id)
    if not cast then return nil, why end
    return math.max(cast, Gcd(id))
end

local function ManaType()
    local enum = rawget(_G, "Enum")
    return type(enum) == "table" and type(enum.PowerType) == "table" and enum.PowerType.Mana or 0
end

SpellValue.ManaType = ManaType

function SpellValue.Cost(spellID)
    local Spells = Core.Spells
    if not (Spells and Spells.PowerCost) then return 0 end
    local cost, secret = Spells.PowerCost(spellID, ManaType())
    if secret then return nil, true end
    return cost or 0
end

function SpellValue.Of(spellID)
    local id = Core.Num(spellID)
    if not id then return nil, "unknown" end
    local amount, why = SpellValue.Amount(id)
    local time, timeWhy = SpellValue.Time(id)
    why = why or timeWhy
    local cost, secret = SpellValue.Cost(id)
    if amount and time and time > 0 and not secret then
        local row = { id = id, amount = amount, time = time, cost = cost, dps = amount / time,
            dpm = cost > 0 and amount / cost or nil, at = Core.Uptime() }
        memo[id] = row
        return row
    end
    if memo[id] then return memo[id], "memo" end
    return nil, why or (secret and "secret") or "unknown"
end

-- Zauberstab im Fernkampfplatz: Schaden je Sekunde wie Blizzards Charakterfenster
function SpellValue.Wand()
    local item, why = Core.HandItem("ranged")
    if not item then
        -- leerer Platz: kein Stab; unbekannt (gesperrt): die letzte offene Lesung
        if why == "empty" then wandMemo = nil end
        if wandMemo then return wandMemo, "memo" end
        return nil, why == "empty" and "none" or "secret"
    end
    if Core.ItemWeaponKind(item) ~= "wand" then
        wandMemo = nil
        return nil, "none"
    end
    if wandMemo and wandMemo.item ~= item then wandMemo = nil end    -- anderer Stab: die alte Lesung gilt nicht
    local fn = rawget(_G, "UnitRangedDamage")
    local ok, speed, low, high, plus, minus, percent = false
    if type(fn) == "function" then ok, speed, low, high, plus, minus, percent = pcall(fn, "player") end
    -- jeder Rohwert zuerst über Core.IsSecret – auch ein „or 0“ ist mit einem gesperrten Wert verboten (Leitlinie 6);
    -- Core.Usable zählt über select("#"), auch hinter einem nil
    local open = ok and Core.Usable(speed, low, high, plus, minus, percent)
    if open then
        speed, low, high = Core.Num(speed), Core.Num(low), Core.Num(high)
        plus, minus, percent = Core.Num(plus) or 0, Core.Num(minus) or 0, Core.Num(percent) or 1
        if speed and low and high and speed > 0 and high > 0 then
            local amount = math.max(((low + high) / 2 + plus + minus) * percent, 1)
            wandMemo = { dps = amount / speed, speed = speed, amount = amount, item = item, at = Core.Uptime() }
            return wandMemo
        end
    end
    if wandMemo then return wandMemo, "memo" end
    return nil, "secret"
end

function SpellValue.SourceText()
    local CD = Core.ClientData
    return L.SPELLVALUE_SOURCE:format(CD and CD.Build and CD.Build(SpellValue.KEY) or "?")
end

-- Für Prüfungen: gemerkte Rechnungen vergessen
function SpellValue.Forget()
    memo, wandMemo = {}, nil
end
