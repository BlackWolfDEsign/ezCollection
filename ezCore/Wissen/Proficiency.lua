local _, ns = ...
local Core = ezCore

--[[
    Waffen- und Rüstungsfertigkeiten (Paket ezgear/lernbar-tragbar, 23.11.2026). Anlass: Frage des Nutzers vom
    23.11.2026 („Sollte ezgear beim grünen vs roten Pfeil nicht den Charakter berücksichtigen? Kann er es tragen. Könnte
    er es tragen wenn er beim Waffenmeister war oder Paladin und Krieger der erst nur schwere Rüstung tragen kann und
    später platte“), Entscheidung „Vergleich + Hinweis (Empfohlen)“ (Wortlaut im ROADMAP-Index).

    Quellen (Leitlinien 11 und 12):
      * Welche Fertigkeit ein Gegenstand braucht und welche Klasse (und welches Volk) sie ab welcher Stufe hat oder
        lernen kann: die Client-Tabellen dieses Builds (Wissen/Client/Proficiencies.lua, erzeugt von
        tools/wago_ausliefern.lua aus SkillLine, SkillLineAbility, SkillRaceClassInfo, SpellEquippedItems).
      * Ob der Charakter sie schon hat: der Client zur Laufzeit – Core.KnowsSpell(Zauber der Fertigkeit) bzw.
        C_SkillInfo.GetSkillLineInfoByID(Linie). Sagt keiner von beiden „ja“ zu einer Fertigkeit, die der Charakter
        laut Tabelle von Anfang an hat, gilt die Antwort als unzuverlässig (nil) – dann bleibt alles wie ohne diese Datei.
      * Wo man lernt, führt nur der Server: Waffen beim Waffenmeister, Rüstung beim Klassenlehrer (Classic-Regel,
        im Spiel zu bestätigen); hat das Lehrerfenster es schon gezeigt (Entdecker-Datenbank, Tabelle offer), gilt das
        Gesehene, und nur dann steht auch der Ort dabei (Core.Npcs: Gebiet des Lehrers). Hat nur ein anderer Spieler es
        gesehen (Beiträge, ezData; seit 25.11.2026), gelten dessen Lehrer und Ort mit der Quelle „aus Beiträgen …“.
      * Zeilen mit dem Kennzeichen 0x100 (SkillRaceClassInfo.Flags, „nicht beim Lehrer“ – in diesem Build nur
        Schamane + Zweihandäxte/-streitkolben, in Classic ein Talent, das der Forever-Talentbaum nicht führt) zählen
        nicht: Kein Lehrer bringt sie bei, die Klasse bekommt die Fertigkeit also nie – außer der Client sagt, der
        Charakter hat sie schon (ForItem » "known").

      Proficiency.LineFor(itemClassID, subClassID) → Fertigkeitslinie oder nil (keine nötig – Verschiedenes, Angel,
                                       Buchbände – oder die Tabelle fehlt); Stoff ist eine Linie (jede Klasse von Anfang an)
      Proficiency.Info(line)        → { line, spell, kind = "weapon" | "armor", itemClass, subclassMask } oder nil
      Proficiency.Rule(line, class, race) → { from (Stufe, mindestens 1), start (von Anfang an) } oder nil (die Klasse
                                       bekommt die Fertigkeit nie, auch nur Zeilen mit 0x100); race = Volk-ID, nil = jedes Volk
      Proficiency.ClassLevels(itemClassID, subClassID) → { [Klasse] = ab Stufe } (jedes Volk) oder nil, wenn die
                                       Tabellen keine Fertigkeit für diese Art führen (der Aufrufer nimmt seine Regeln)
      Proficiency.Known(line)       → true | false | nil (der Client sagt nichts Verlässliches) – der Spieler; was
                                       Klasse und Volk von Anfang an haben, gilt ohne Frage als bekannt
      Proficiency.Way(line, class)  → { line, spell, kind, name, from, trainer = "weaponmaster" | "class" | nil,
                                       seen (Lehrer gesehen), shared (statt dessen aus Beiträgen: „aus Beiträgen
                                       (n Spieler), Stand Build x“), place = { npc, name, zone, map, x, y } oder nil
                                       (map, x, y nur aus Beiträgen) }
      Proficiency.ForItem(itemClassID, subClassID) → Stand, info – für den Spieler:
                                       nil (keine Fertigkeit nötig, keine Daten, Client unklar), "known", "never",
                                       "learn" (info = Way); ohne Regel für Klasse und Volk "known" nur, wenn der Client
                                       es bejaht, sonst "never"
      Proficiency.Learnable(kind)   → Liste, unklar – was der Spieler noch lernen kann (ezMerchants „Wo kommt was“,
                                       Abschnitt „Waffenmeister“, 24.11.2026): die Wege (Proficiency.Way) der Linien
                                       dieser Art ("weapon" | "armor" | nil = beide), die Klasse und Volk lernen können
                                       und die der Client verneint, nach Stufe, dann Name; unklar = true, wenn der Client
                                       zu einer solchen Linie nichts Verlässliches sagt (sie fehlt dann)
      Proficiency.Recheck(force)    → true, wenn neu gerechnet wurde (Antworten geändert oder force)
      Nachricht PROFICIENCY_CHANGED (Core.Fire), wenn sich ändert, was der Spieler kann (neu gelernt), und nach dem
      Schließen eines Lehrerfensters (der Ort eines Lehrers kann neu bekannt sein).
]]

local Proficiency = {}
Core.Proficiency = Proficiency

local Num, Plain, IsSecret = Core.Num, Core.Plain, Core.IsSecret

Proficiency.CAT_KIND = { [6] = "weapon", [8] = "armor" }
Proficiency.FLAG_NO_TRAINER = 0x100
Proficiency.TRAINER_BY_KIND = { weapon = "weaponmaster", armor = "class" }   -- Classic-Regel (Kopf)

local function Table()
    local t = ns.ClientTables and ns.ClientTables.proficiencies
    if type(t) == "table" and type(t.data) == "table" then return t end
    return nil
end

local function Data()
    local t = Table()
    return t and t.data or nil
end

-- Klassen-ID je Kürzel laut ChrClasses (aus der erzeugten Datei, Feld classIds)
function Proficiency.ClassID(class)
    local t = Table()
    local ids = t and type(t.classIds) == "table" and t.classIds or nil
    return ids and type(class) == "string" and Num(ids[class]) or nil
end

local HasBit = Core.HasBitAt
Proficiency.HasBit = HasBit

local function ClassFits(mask, classID)
    if Num(mask) == -1 then return true end
    return classID ~= nil and HasBit(mask, classID - 1)
end

-- Volk-ID → passt die Zeile (zwei Hälften der 64-Bit-Maske)? Ohne Volk, ohne bekanntes Bit oder mit leerer Maske
-- (0/0 heißt in SkillRaceClassInfo „jedes Volk“, wie -1/-1): ja.
local function RaceFits(lo, hi, race)
    if race == nil then return true end
    if (Num(lo) or 0) == 0 and (Num(hi) or 0) == 0 then return true end
    local CD = Core.ClientData
    local b = CD and CD.RaceBit and CD.RaceBit(race)
    if b == nil then return true end
    if b < 32 then return HasBit(lo, b) end
    return HasBit(hi, b - 32)
end

---------------------------------------------------------------------------
-- Tabellen
---------------------------------------------------------------------------

function Proficiency.LineFor(itemClassID, subClassID)
    itemClassID, subClassID = Num(itemClassID), Num(subClassID)
    local data = Data()
    if not (data and itemClassID and subClassID) then return nil end
    for line, e in pairs(data) do
        if type(e) == "table" and Num(e[3]) == itemClassID and HasBit(e[4], subClassID) then return line end
    end
    return nil
end

function Proficiency.Info(line)
    local data = Data()
    local e = data and Num(line) and data[Num(line)]
    if type(e) ~= "table" then return nil end
    return { line = Num(line), spell = Num(e[1]), kind = Proficiency.CAT_KIND[Num(e[2]) or 0], itemClass = Num(e[3]),
        subclassMask = Num(e[4]) }
end

-- Regel einer Linie für Klasse (Kürzel) und Volk (ID oder nil = jedes): kleinste Stufe über die passenden Zeilen;
-- Zeilen mit 0x100 (kein Lehrer, Kopf) zählen nicht
function Proficiency.Rule(line, class, race)
    local data = Data()
    local e = data and Num(line) and data[Num(line)]
    local classID = Proficiency.ClassID(class)
    if type(e) ~= "table" or type(e[5]) ~= "table" or not classID then return nil end
    local best
    for _, r in ipairs(e[5]) do
        local flags = type(r) == "table" and Num(r[6]) or 0   -- Kennzeichen; 0x100 = kein Lehrer (Kopf)
        if type(r) == "table" and ClassFits(r[1], classID) and RaceFits(r[2], r[3], race)
            and math.floor(flags / Proficiency.FLAG_NO_TRAINER) % 2 == 0 then
            local from = math.max(1, Num(r[5]) or 0)
            local start = Num(r[4]) == 1
            if not best or from < best.from or (from == best.from and start and not best.start) then
                best = { from = from, start = start }
            end
        end
    end
    return best
end

function Proficiency.ClassLevels(itemClassID, subClassID)
    local line = Proficiency.LineFor(itemClassID, subClassID)
    if not line then return nil end
    local out = {}
    for _, class in ipairs(Core.CLASSES or {}) do
        local rule = Proficiency.Rule(line, class, nil)
        if rule then out[class] = rule.from end
    end
    return out
end

---------------------------------------------------------------------------
-- Was der Spieler schon kann (Client zur Laufzeit)
---------------------------------------------------------------------------

-- → true (der Client sagt ja), false (gefragt, nein), nil (keine Antwort)
local function AskClient(line, spell)
    local answered = false
    local known = Core.KnowsSpell(spell)
    if known then return true end
    if known == false then answered = true end
    local api = rawget(_G, "C_SkillInfo")
    local byID = type(api) == "table" and api.GetSkillLineInfoByID or nil
    if type(byID) == "function" then
        local ok, info = pcall(byID, line)
        if ok and not IsSecret(info) then
            if type(info) == "table" and ((Num(Plain(info.maxRank)) or 0) > 0 or (Num(Plain(info.rank)) or 0) > 0) then
                return true
            end
            answered = true
        end
    end
    if answered then return false end
    return nil
end
Proficiency.AskClient = AskClient

local cache, reliable, ways = nil, nil, nil

-- Antworten und Wege vergessen (neu gelernt, Lehrerfenster gesehen, Prüfungen)
function Proficiency.Forget()
    cache, reliable, ways = nil, nil, nil
end

-- Antwortet der Client verlässlich? Ja, sobald er eine Fertigkeit bejaht, die der Charakter laut Tabelle von Anfang
-- an hat (jede Klasse hat eine). Ein Ja bleibt bis /reload; ein Nein wird beim nächsten Mal neu gefragt.
local function Reliable(class, race)
    if reliable then return true end
    local data = Data()
    if not (data and class) then return false end
    for line, e in pairs(data) do
        local rule = Proficiency.Rule(line, class, race)
        if rule and rule.start and AskClient(line, Num(e[1])) == true then
            reliable = true
            return true
        end
    end
    return false
end

function Proficiency.Known(line)
    line = Num(line)
    local info = line and Proficiency.Info(line)
    if not info then return nil end
    cache = cache or {}
    local hit = cache[line]
    if hit ~= nil then
        if hit == "nil" then return nil end
        return hit
    end
    -- Von Anfang an (Availability 1 für Klasse und Volk, etwa Leder beim Schurken): bekannt, ohne zu fragen – verlernen
    -- kann man sie nicht, und ein Client ohne Antwort macht daraus sonst kein „erst lernen“
    local class = Core.PlayerClass()
    local race = Core.ClientData and Core.ClientData.PlayerRace and Core.ClientData.PlayerRace() or nil
    local rule = class and Proficiency.Rule(line, class, race)
    local answer
    if rule and rule.start then
        answer = true
    else
        answer = AskClient(line, info.spell)
        if answer == false and not Reliable(class, race) then answer = nil end
    end
    cache[line] = answer == nil and "nil" or answer
    return answer
end

---------------------------------------------------------------------------
-- Weg: Lehrer, Stufe, Ort (Selbsterhobenes)
---------------------------------------------------------------------------

-- Hat ein Lehrerfenster den Zauber schon angeboten (Entdecker-Datenbank)? → { kind = "class" | "other", npc, name,
-- zone } (der zuletzt gesehene Lehrer, der zu dir passt) oder nil
function Proficiency.Seen(spell)
    spell = Num(spell)
    local DB = Core.DB
    local Keys = DB and DB.Keys
    if not (spell and DB and type(DB.KeysOf) == "function" and type(DB.Get) == "function" and Keys
        and type(Keys.OfferKind) == "function") then
        return nil
    end
    local class = Core.PlayerClass()
    local Npcs = Core.Npcs
    local best
    for _, art in ipairs(DB.KeysOf("offer")) do
        local kind, who = Keys.OfferKind(art)
        if kind == "other" or (kind == "class" and who == class) then
            local row = DB.Get("offer", art)
            local s = type(row) == "table" and type(row.svc) == "table" and row.svc[spell] or nil
            if type(s) == "table" then
                best = best or { kind = kind }
                for npc, t in pairs(type(s.at) == "table" and s.at or {}) do
                    local e = Npcs and type(Npcs.Get) == "function" and Npcs.Get(npc) or nil
                    local fits = e and (type(Npcs.Fits) ~= "function" or Npcs.Fits(e))
                    t = Num(t) or 0
                    if fits and type(e.zone) == "string" and e.zone ~= "" and (not best.npc or t > best.t) then
                        best = { kind = kind, npc = Num(npc), name = e.name, zone = e.zone, t = t }
                    end
                end
            end
        end
    end
    if best then best.t = nil end
    return best
end

-- Dasselbe aus Beiträgen anderer Spieler (ezData): Lehrer deiner Fraktion mit Namen und Gebiet, sonst nur die Lehrerart.
-- → { kind, label, npc, name, zone, map, x, y } oder nil
function Proficiency.Shared(spell)
    spell = Num(spell)
    local Ship = Core.Ship
    if not (spell and Ship and Ship.Offers) then return nil end
    local class = Core.PlayerClass()
    local list, label, kind = Ship.Offers(spell, function(k, who) return k == "other" or (k == "class" and who == class) end)
    if not (label and kind) then return nil end
    for _, t in ipairs(list) do
        local name = Ship.Name("npc", t.npc)
        local p = name and Ship.Place("npc", t.npc) or nil
        if p and p.zone then
            return { kind = t.art, label = label, npc = t.npc, name = name, zone = p.zone, map = p.map, x = p.x, y = p.y }
        end
    end
    return { kind = kind, label = label }
end

-- Der Weg wird je Linie und Klasse gemerkt (das Item-Wissen fragt ihn je Gegenstand; Seen liest die
-- Entdecker-Datenbank) – bis Proficiency.Forget. Rückgabe ist eine Kopie (place ebenso).
local function CopyWay(w)
    if type(w) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(w) do out[k] = v end
    if type(w.place) == "table" then
        out.place = { npc = w.place.npc, name = w.place.name, zone = w.place.zone, map = w.place.map, x = w.place.x,
            y = w.place.y }
    end
    return out
end

local BuildWay
function Proficiency.Way(line, class)
    line, class = Num(line), class or Core.PlayerClass()
    if not (line and class) then return nil end
    ways = ways or {}
    local key = tostring(line) .. ":" .. class
    local hit = ways[key]
    if hit == nil then
        hit = BuildWay(line, class) or false
        ways[key] = hit
    end
    return CopyWay(hit or nil)
end

BuildWay = function(line, class)
    local info = Proficiency.Info(line)
    local race = Core.ClientData and Core.ClientData.PlayerRace and Core.ClientData.PlayerRace() or nil
    local rule = info and Proficiency.Rule(line, class, race)
    if not rule then return nil end
    local way = { line = info.line, spell = info.spell, kind = info.kind, from = rule.from,
        name = info.spell and Core.SpellName and Core.SpellName(info.spell) or nil }
    local seen = Proficiency.Seen(info.spell)
    if seen then
        way.seen = true
        way.trainer = seen.kind == "class" and "class" or "weaponmaster"
        if seen.zone then way.place = { npc = seen.npc, name = seen.name, zone = seen.zone } end
    end
    -- selbst gesehen, aber ohne Ort: Der Ort darf aus Beiträgen kommen – dann nennt ihn auch die Quelle so
    local shared = not way.place and Proficiency.Shared(info.spell) or nil
    if shared and (not seen or shared.zone) then
        way.trainer = way.trainer or (shared.kind == "class" and "class" or "weaponmaster")
        way.shared = shared.label
        if shared.zone then
            way.place = { npc = shared.npc, name = shared.name, zone = shared.zone, map = shared.map, x = shared.x, y = shared.y }
        end
    end
    way.trainer = way.trainer or Proficiency.TRAINER_BY_KIND[info.kind or ""]
    return way
end

function Proficiency.ForItem(itemClassID, subClassID)
    local line = Proficiency.LineFor(itemClassID, subClassID)
    if not line then return nil end
    local class = Core.PlayerClass()
    if not class then return nil end
    local race = Core.ClientData and Core.ClientData.PlayerRace and Core.ClientData.PlayerRace() or nil
    if not Proficiency.Rule(line, class, race) then
        -- kein Lehrer für Klasse und Volk; hat der Charakter sie trotzdem (Client), trägt er es
        if Proficiency.Known(line) == true then return "known" end
        return "never"
    end
    local known = Proficiency.Known(line)
    if known == nil then return nil end
    if known then return "known" end
    return "learn", Proficiency.Way(line, class)
end

-- Was der Spieler noch lernen kann (Kopf). Dieselben Antworten wie ForItem: Regel für Klasse und Volk, Known vom Client.
function Proficiency.Learnable(kind)
    local data = Data()
    local class = Core.PlayerClass()
    local out, unclear = {}, false
    if not (data and class) then return out, false end
    local race = Core.ClientData and Core.ClientData.PlayerRace and Core.ClientData.PlayerRace() or nil
    for line in pairs(data) do
        local info = Proficiency.Info(line)
        if info and (kind == nil or info.kind == kind) and Proficiency.Rule(line, class, race) then
            local known = Proficiency.Known(line)
            if known == nil then
                unclear = true
            elseif known == false then
                local way = Proficiency.Way(line, class)
                if way then out[#out + 1] = way end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.from or 0) ~= (b.from or 0) then return (a.from or 0) < (b.from or 0) end
        local na, nb = tostring(a.name or ""), tostring(b.name or "")
        if na ~= nb then return na < nb end
        return (a.line or 0) < (b.line or 0)
    end)
    return out, unclear
end

---------------------------------------------------------------------------
-- Neu gelernt: Antworten vergessen; hat sich etwas geändert, Item-Wissen und Module neu rechnen lassen
---------------------------------------------------------------------------

local function Signature()
    local data = Data()
    if not data then return "" end
    local parts = {}
    for line in pairs(data) do
        local known = Proficiency.Known(line)
        parts[#parts + 1] = tostring(line) .. "=" .. tostring(known)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Auch die erste Antwort nach dem Anmelden zählt als Änderung: Bis dahin kann das Item-Wissen ohne sie gerechnet haben
-- (Client noch ohne Antwort » nil, „wie bisher“). force = true: auch ohne Änderung neu rechnen lassen (nach dem
-- Lehrerfenster kann der Ort eines Lehrers neu bekannt sein).
local lastSignature = ""
function Proficiency.Recheck(force)
    Proficiency.Forget()
    local sig = Signature()
    if sig == lastSignature and not force then return false end
    lastSignature = sig
    local K = Core.Knowledge
    if K and type(K.RefreshDynamic) == "function" then K.RefreshDynamic() end
    Core.Fire("PROFICIENCY_CHANGED")
    return true
end

if type(ns.On) == "function" then
    local recheck = Core.Throttle(function() Proficiency.Recheck() end, 1, "ezCore")
    for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
        "PLAYER_LEVEL_UP" }) do
        ns.On(event, recheck)
    end
    -- Lehrerfenster zu: Angebot und Ort sind gemerkt (Entdecker-Datenbank) – Wege neu, auch ohne neue Fertigkeit
    local afterTrainer = Core.Throttle(function() Proficiency.Recheck(true) end, 1, "ezCore")
    ns.On("TRAINER_CLOSED", afterTrainer)
end
