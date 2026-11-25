local _, ns = ...
local Core = ezCore
local L = ns.L

--[[
    Auren lesen und Buffs erkennen.

    Auren liest ezCore (Core.Auras.Scan) – nur außerhalb des Kampfes. Gesperrte Auren werden dort gezählt,
    nie verglichen; ist eine dabei oder bleibt eine unlesbar, gibt Scan nil zurück – dann meldet ezBuff lieber nichts als etwas Falsches.

    Welche Klasse welchen Buff gibt, steht im Zauber-Wissen von ezCore (Core.Spells, Buff-Gruppen:
    BuffKey, ClassBuffs, BestBuffRank, BuffInfo, IsBuff, BuffField, BuffKeys – ezCores Leseschnittstelle, nie die
    Rohtabelle Spells.BUFFS). Die Zugriffe laufen über diese Datei; nur ns.PrintStatus (Core.lua) fragt BuffKeys selbst.

    Ob ein Buff „bald ausläuft“, entscheidet ezCore (Spells.BuffState: Rest unter der Schwelle, aber nie mehr als
    ein Viertel seiner Dauer; die Dauer aus der Aura, sonst aus Spells.BuffMinutes) – Buffs.State, Buffs.AuraState.
    Buffs.Has und Check.StateOf sind Weiterleitungen darauf.
]]

local Buffs = {}
ns.Buffs = Buffs

local Spells = Core.Spells

---------------------------------------------------------------------------
-- Zauber-Wissen aus ezCore
---------------------------------------------------------------------------

-- Buff-Gruppe einer Aura ("int", "wellFed", "cozyFire" …) über Zauber-ID, sonst über den Namen.
function Buffs.KeyOf(spellId, name)
    local key = spellId and Core.Call(Spells.BuffKey, spellId)
    if key == nil and name then key = Core.Call(Spells.BuffKey, name) end
    return key
end

-- Buffs, die eine Klasse geben kann: { { key, target = "any"|"self", kind, spells, levels } }
function Buffs.ClassBuffs(class)
    if not class then return {} end
    local list = Core.Call(Spells.ClassBuffs, class)
    return type(list) == "table" and list or {}
end

-- Lange Selbst-Buffs aus Talenten bzw. für eine Rolle (Gesamtreview 18.11.2026, T14-2; Entscheidung des Nutzers vom
-- 19.11.2026 auf die Frage „ezBuff: Sollen lange Selbst-Buffs angemahnt werden, wenn sie fehlen?“: „Ja, anmahnen
-- (Empfohlen)“). ezCore führt sie in Spells.BUFFS, aber außerhalb von BUFF_ORDER – dort stünden sie für jedes Modul in
-- der Liste der Klassen-Buffs (ezCombat, Diagnose, die Makro-Vorlage). ezBuff nimmt sie darum selbst in seine Reihe
-- der Selbst-Buffs auf (Check.Groups), nur für die eigene Klasse, je Buff abwählbar (Einstellung setting), ab der
-- Lernstufe laut ezCore (levels[1]; ohne levels: Talent) und – wie jeder Selbst-Buff – nur, wenn ein Rang gelernt ist
-- (Spells.BestBuffRank). pet = true: nur mit lebendem Begleiter (Seelenverbindung teilt den Schaden mit dem Dämon; ohne
-- ihn gibt es nichts zu wirken). Seelenverbindung hält ohne Dauer (ezCore: fallback.permanent).
Buffs.LONG_SELF = {
    { key = "trueshotAura", setting = "longTrueshotAura" },
    { key = "righteousFury", setting = "longRighteousFury" },
    { key = "soulLink", setting = "longSoulLink", pet = true },
}

-- Gehört der lange Selbst-Buff key zur Klasse class? (auch Sichtbarkeit der Schalter auf der Einstellungsseite)
function Buffs.LongSelfOf(key, class)
    if ns.IsSecret(class) or type(class) ~= "string" then return false end
    return Core.Call(Spells.BuffField, key, "class") == class
end

-- Die eingeschalteten langen Selbst-Buffs der Klasse ab ihrer Lernstufe, die du gelernt hast (Talente lassen sich
-- verlernen – ein nicht gelernter zählt nicht als „von ezBuff betreut“, Check.Watches): { { key, target = "self",
-- spells, levels, long = true, pet } } in der Form von Buffs.ClassBuffs.
function Buffs.LongSelfBuffs(class)
    local out = {}
    if not ns.S then return out end
    local level = ns.Num(Core.PlayerLevel()) or 0
    for _, info in ipairs(Buffs.LONG_SELF) do
        if ns.S[info.setting] == true and Buffs.LongSelfOf(info.key, class) then
            local levels = Core.Call(Spells.BuffField, info.key, "levels")
            local need = type(levels) == "table" and ns.Num(levels[1]) or nil
            if (need == nil or level >= need) and Buffs.BestRank(info.key) then
                out[#out + 1] = { key = info.key, target = "self", spells = Core.Call(Spells.BuffField, info.key, "spells"),
                    levels = levels, long = true, pet = info.pet }
            end
        end
    end
    return out
end

-- Lebender Begleiter? Ein gesperrter Wert zählt nicht als „tot“ (Leitlinie 6: zuerst IsSecret).
function Buffs.PetReady()
    if Core.UnitPresent("pet") ~= true then return false end
    local dead = Core.Call(UnitIsDead, "pet")
    if ns.IsSecret(dead) then return true end
    return dead ~= true
end

-- Höchster gelernter Rang, den ein Ziel der Stufe level annehmen darf (nil = für dich selbst).
function Buffs.BestRank(key, level)
    if not key then return nil end
    return ns.Num(Core.Call(Spells.BestBuffRank, key, level))
end

-- Zusatzdaten einer Gruppe, z. B. Lagerfeuer: { cast = Zauber, reagent = Gegenstand }.
function Buffs.Info(key)
    local info = Core.Call(Spells.BuffInfo, key)
    return type(info) == "table" and info or nil
end

-- Eine Zauber-ID, die für den Buff steht (für Name und Symbol).
function Buffs.SpellOf(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.spell) == "number" then return entry.spell end
    if type(entry.spells) == "table" and type(entry.spells[1]) == "number" then return entry.spells[1] end
    if type(entry.id) == "number" then return entry.id end
    return nil
end

-- Name des Buffs: vom Client, sonst Ersatzname aus ezCore (Spells.Name).
function Buffs.Name(entry, spellID)
    local name = Spells.Name(spellID or Buffs.SpellOf(entry))
    if name then return name end
    return type(entry) == "table" and (entry.name or entry.key) or "?"
end

---------------------------------------------------------------------------
-- Kann jemand in der Gruppe den Buff geben? (Spieltest 15.11.2026: „mir zeigt an dass buff von gruppe fehlt, aber
-- die person hat es noch garnicht gelernt, bzw kann es noch nich lernen“)
--
-- Erwartet wird ein Buff einer anderen Klasse nur, wenn der Client ihn überhaupt kennt (Buffs.InClient) und ein
-- Mitglied dieser Klasse ihn auf seiner Stufe lernen kann (Buffs.LearnLevel). Quellen nach Leitlinie 11: zuerst der
-- Client (C_Spell.DoesSpellExist, C_Spell.GetSpellLevelLearned, C_CooldownViewer.GetGroupBuffItems), dann ezCores
-- Zauber-Wissen (Spells.LevelLearned nennt die Quelle: Client, Zauberbuch, Lehrer oder levels aus SpellData.lua).
-- Für dich selbst zählt weiter nur, was du gelernt hast (Spells.BestBuffRank über Core.KnowsSpell und das Zauberbuch).
---------------------------------------------------------------------------

-- Zauber-IDs eines Buffs (Ränge und Gruppenfassungen): aus dem Eintrag (ClassBuffs) bzw. aus ezCore (Buffs.Info).
local function SpellIDs(entry)
    local key = type(entry) == "table" and entry.key or entry
    local info = type(key) == "string" and Buffs.Info(key) or nil
    local ranks = type(entry) == "table" and type(entry.spells) == "table" and entry.spells or info and info.spells
    local out = {}
    for _, id in ipairs(type(ranks) == "table" and ranks or {}) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out, info and type(info.group) == "table" and info.group or {}, info
end

-- Buff-Gruppen, die der Client selbst nennt (C_CooldownViewer.GetGroupBuffItems, GroupBuffItem mit spellID und
-- displaySpellID): { [Buff-Schlüssel] = true } und die Zahl der Einträge. Nur lesen, gesperrte Werte zählen nicht.
function Buffs.ClientGroupBuffs()
    local keys = {}
    local api = Core.Peek(rawget(_G, "C_CooldownViewer"), "GetGroupBuffItems")
    local list = type(api) == "function" and Core.Call(api) or nil
    if ns.IsSecret(list) or type(list) ~= "table" then return keys, nil end
    local count = 0
    for _, item in ipairs(list) do
        count = count + 1
        for _, field in ipairs({ "spellID", "displaySpellID" }) do
            local id = ns.Num(Core.Peek(item, field))
            local key = id and Buffs.KeyOf(id)
            if key then keys[key] = true end
        end
    end
    return keys, count
end

-- Kennt der Client den Buff? Wahr, wenn er einen Rang oder eine Gruppenfassung kennt (Spells.Exists) oder ihn unter
-- seinen Buff-Gruppen nennt. Fehlt der Zauber im Client (Segen der Rettung, des Lichts und des Refugiums laut
-- Selbsttest des Nutzers vom 15.11.2026), wird der Buff nie erwartet; die Daten in SpellData.lua bleiben (Leitlinie 8).
-- clientKeys: Ergebnis von Buffs.ClientGroupBuffs (für viele Fragen hintereinander), sonst wird gelesen.
function Buffs.InClient(entry, clientKeys)
    local ranks, group = SpellIDs(entry)
    for _, list in ipairs({ ranks, group }) do
        for _, id in ipairs(list) do
            if Core.Call(Spells.Exists, id) == true then return true end
        end
    end
    local key = type(entry) == "table" and entry.key or entry
    return type(key) == "string" and (clientKeys or Buffs.ClientGroupBuffs())[key] == true
end

-- Ab welcher Stufe lernt man den Buff? Kleinste Stufe der Ränge, die der Client kennt, und ihre Quelle ("client",
-- "book", "trainer", "fallback" – Spells.LevelLearned). Ohne Angabe die erste Stufe aus levels (Quelle "fallback").
-- nil, wenn der Client keinen Rang kennt.
function Buffs.LearnLevel(entry)
    local ranks, _, info = SpellIDs(entry)
    local best, source
    for index, id in ipairs(ranks) do
        if Core.Call(Spells.Exists, id) == true then
            local level, from
            if Spells.LevelLearned then level, from = Core.Call(Spells.LevelLearned, id) end
            level = ns.Num(level)
            if not (level and level > 0) then
                local levels = type(entry) == "table" and entry.levels or info and info.levels
                level, from = type(levels) == "table" and ns.Num(levels[index]) or nil, "fallback"
            end
            if level and level > 0 and (not best or level < best) then best, source = level, from end
        end
    end
    return best, source
end

-- Beides auf einmal, für einen Eintrag: { inClient = wahr/falsch, level = Lernstufe oder nil, source = Quelle }.
function Buffs.Availability(entry, clientKeys)
    local inClient = Buffs.InClient(entry, clientKeys)
    local level, source
    if inClient then level, source = Buffs.LearnLevel(entry) end
    return { inClient = inClient, level = level, source = source }
end

-- Woher eine Lernstufe stammt, als Text für Tooltip und Status („laut Client“).
function Buffs.SourceText(source)
    return L["LEVEL_SOURCE_" .. tostring(source)] or L.LEVEL_SOURCE_fallback
end

-- Kann ein Spieler der Stufe giverLevel den Buff geben, und darf ein Ziel der Stufe targetLevel ihn annehmen
-- (Rang-1-Regel wie Spells.BestBuffRank: Zielstufe mindestens Lernstufe − 10)? Stufe unbekannt, 0 oder gesperrt:
-- nicht erwarten. Rückgabe: wahr/falsch, Lernstufe, Quelle.
-- avail: Ergebnis von Buffs.Availability für diesen Eintrag (für viele Mitglieder hintereinander), sonst wird gefragt.
function Buffs.CanGive(entry, giverLevel, targetLevel, clientKeys, avail)
    giverLevel = ns.Num(giverLevel)
    if not (giverLevel and giverLevel > 0) then return false end
    avail = avail or Buffs.Availability(entry, clientKeys)
    if not avail.inClient then return false end
    local level, source = avail.level, avail.source
    if not level then return true, nil, nil end   -- Client kennt den Buff, nennt aber keine Stufe: nicht einschränken
    if giverLevel < level then return false, level, source end
    targetLevel = ns.Num(targetLevel)
    if targetLevel and targetLevel > 0 and targetLevel < level - 10 then return false, level, source end
    return true, level, source
end

-- Buffs aller Klassen, die der Client nicht kennt (für /ezbuff status): Liste der Namen in ezCores Reihenfolge.
function Buffs.Absent()
    local out, clientKeys = {}, Buffs.ClientGroupBuffs()
    local keys = Core.Call(Spells.BuffKeys)
    for _, key in ipairs(type(keys) == "table" and keys or {}) do
        local info = Buffs.Info(key)
        if info and info.class and not Buffs.InClient(key, clientKeys) then
            out[#out + 1] = Buffs.Name(info, Buffs.SpellOf(info))
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Auren
---------------------------------------------------------------------------

-- Hilfreiche Auren einer Einheit (ezCore.Auras): Liste { name, spellId, icon, count, duration, expires, source,
-- instance, key }; nil im Kampf, wenn eine Aura gesperrt ist oder wenn das Spiel eine Aura nicht herausgibt
-- (vierter Wert von Core.Auras.Scan: Instanz-ID da, Daten nicht) – eine unvollständige Liste hieße „fehlt“.
-- Dieselbe Regel wie Core.Auras.Readable (nichts gesperrt, nichts unlesbar, Core.AurasLocked nicht „gesperrt“),
-- aus einem einzigen Lesen.
function Buffs.Scan(unit)
    if ns.InCombat() then return nil end
    local list, secret, _, unread = Core.Auras.Scan(unit, "HELPFUL")
    local locked = Core.AurasLocked and Core.AurasLocked() == true
    if locked or (secret or 0) > 0 or (unread or 0) > 0 or type(list) ~= "table" then
        ns.NoteSecret("auras")
        return nil
    end
    for _, aura in ipairs(list) do aura.key = Buffs.KeyOf(aura.spellId, aura.name) end
    return list
end

-- Restzeit in Sekunden (dauerhafte Auren: math.huge). Nur für die Anzeige („läuft aus (n Min.)“) und den Rückfall
-- in Buffs.AuraState – ob ein Buff als auslaufend gilt, entscheidet ezCore.
function Buffs.Left(aura)
    if not aura or not aura.expires then return math.huge end
    return aura.expires - GetTime()
end

-- Dauer eines Buffs in Minuten und woher sie stammt ("aura": vom Client gelernt, "fallback": ezCores SpellData);
-- nil, wenn ezCore den Buff nicht kennt oder keine Dauer hat (Spells.BuffMinutes). spellID (optional): Zauber der
-- Aura – eine Gruppenfassung hat ihre eigene Dauer (Gebet des Schattenschutzes 27683: 20 statt 10 Min.; Gesamtreview
-- 18.11.2026, T14-NH8). Ein gesperrter Wert zählt als nicht genannt (Leitlinie 6).
function Buffs.Minutes(key, spellID)
    if ns.IsSecret(key) or type(key) ~= "string" or not Spells.BuffMinutes then return nil end
    if ns.IsSecret(spellID) then spellID = nil end
    local minutes, source = Core.Call(Spells.BuffMinutes, key, ns.Num(spellID))
    minutes = ns.Num(minutes)
    if not minutes then return nil end
    return minutes, source
end

-- Die Aura so, wie ezCore sie für seine Regel braucht: Nennt sie ihre Dauer nicht, kommt die Dauer des Buffs aus
-- ezCore (Buffs.Minutes) – sonst könnte Spells.BuffState die Schwelle nicht auf ein Viertel der Dauer begrenzen.
local function WithDuration(aura, key)
    local duration = ns.Num(aura.duration)
    if duration and duration > 0 then return aura end
    local minutes = Buffs.Minutes(key, aura.spellId)
    if not (minutes and minutes > 0) then return aura end
    local copy = {}
    for k, v in pairs(aura) do copy[k] = v end
    copy.duration = minutes * 60
    return copy
end

-- Zustand EINER Aura des Buffs key: "ok" | "expiring". minLeft = Schwelle in Sekunden („Rechtzeitig erneuern“).
-- Kennt ezCore den Buff, gilt seine Regel (Spells.BuffState: Rest unter minLeft, aber nie mehr als ein Viertel der
-- Dauer; dauerhaft = ok). Kennt ezCore ihn nicht (Fläschchen, Elixiere – key = nil) oder findet es die Aura nicht
-- unter diesem Schlüssel, zählt wie früher die Restzeit aus der Aura gegen minLeft.
function Buffs.AuraState(aura, key, minLeft)
    local seconds = ns.Num(minLeft) or 0
    if type(key) == "string" and Spells.BuffState and Core.Call(Spells.IsBuff, key) == true then
        local state = Core.Call(Spells.BuffState, key, { WithDuration(aura, key) }, { minLeft = seconds })
        if state == "ok" or state == "expiring" then return state end
    end
    return Buffs.Left(aura) > seconds and "ok" or "expiring"
end

-- Alle Auren der Liste, die zum Buff key gehören: zuerst über die Gruppe, die Scan jeder Aura gegeben hat; bei
-- Klassen-Buffs danach über ezCore (Spells.FindAura: jeder Rang und jede Gruppenfassung, auch Ränge, die nur das
-- Zauberbuch kennt).
local function AurasOf(auras, key)
    local out, rest = {}, {}
    for _, aura in ipairs(auras or {}) do
        if aura.key == key then out[#out + 1] = aura else rest[#rest + 1] = aura end
    end
    local class = type(key) == "string" and Core.Call(Spells.BuffField, key, "class")
    if class and Spells.FindAura then
        while #rest > 0 do
            local aura = Core.Call(Spells.FindAura, rest, key)
            if type(aura) ~= "table" then break end
            out[#out + 1] = aura
            local removed = false
            for index = #rest, 1, -1 do
                if rest[index] == aura then
                    table.remove(rest, index)
                    removed = true
                end
            end
            if not removed then break end
        end
    end
    return out
end

-- Zustand des Buffs key (genau dieser Schlüssel) in einer lesbaren Aurenliste aus Scan:
--   "ok", Aura         eine Aura des Buffs hat genug Restzeit
--   "expiring", Aura   der Buff liegt, läuft aber bald aus (Regel aus ezCore, siehe Buffs.AuraState)
--   "missing"          keine Aura des Buffs
function Buffs.State(auras, key, minLeft)
    local expiring
    for _, aura in ipairs(AurasOf(auras, key)) do
        if Buffs.AuraState(aura, key, minLeft) == "ok" then return "ok", aura end
        expiring = expiring or aura
    end
    if expiring then return "expiring", expiring end
    return "missing"
end

-- Hat die Einheit einen Buff der Gruppe key mit genug Restzeit? (auras aus Scan) – Weiterleitung auf Buffs.State:
-- wahr und die Aura nur bei "ok"; minLeft = 0 heißt „liegt überhaupt“.
function Buffs.Has(auras, key, minLeft)
    local state, aura = Buffs.State(auras, key, minLeft)
    if state == "ok" then return true, aura end
    return false
end

-- Fläschchen und Elixiere wirken mit dem Zauber, den der Gegenstand benutzt (Item-Wissen: useSpellID).
-- ezBuff merkt sich diese Zauber, damit die Aura auch erkannt wird, wenn der letzte Trank getrunken ist.
function Buffs.Elixir(auras, minLeft)
    local known = ns.db and ns.db.elixirs or {}
    local found
    for _, aura in ipairs(auras or {}) do
        local kind = aura.spellId and known[aura.spellId]
        -- ezCore kennt diese Auren nicht als Buff-Gruppe: Restzeit aus der Aura (Rückfall von Buffs.AuraState)
        if kind and Buffs.AuraState(aura, nil, minLeft) == "ok" then
            if kind == "flask" then return true, aura, kind end
            found = found or aura
        end
    end
    if found then return true, found, "elixir" end
    return false
end

function Buffs.RememberElixir(spellID, kind)
    if ns.db and type(spellID) == "number" and (kind == "flask" or kind == "elixir") then
        ns.db.elixirs[spellID] = kind
    end
end
