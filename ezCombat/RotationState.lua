local _, ns = ...
local Core = ezCore
local Spells = Core.Spells

-- Zustand der Rotation je Sitzung: was der Motor nicht aus dem Spiel lesen kann und sich deshalb merkt.
--   Eröffnung       offen nach Zielwechsel, Kampfende, Wechsel oder Anpassung der Rotation; zu, sobald im Kampf
--                   kein Eröffnungsschritt mehr fällig oder unbekannt ist (Rotation.Evaluate schließt sie)
--   once            Schritte „einmal je Gegner / je Kampf“: abgehakt nach dem eigenen erfolgreichen Zauber
--   Zähler          Ladungen für Zyklen (rotation.counters): aus der Aura, sonst aus den eigenen Zaubern gezählt
--   Ersatzuhr       wann ein eigener Zauber zuletzt gewirkt wurde – für Restzeiten, die das Spiel sperrt
--   hold            läuft gerade der eigene Zauber oder Kanal eines Schritts?
--   autorepeat      läuft der automatische Schuss bzw. Zauberstab? (Ereignisse START/STOP_AUTOREPEAT_SPELL)
--   Abklingzeiten   eigene, die das Spiel im Kampf sperrt: zuletzt offen gelesen, sonst eigener Zauber plus Dauer
--                   (State.Cooldown, Welle 27, Paket modul/ezcombat-abklingzeit)
--   gesehen         Auren, die dieser Charakter schon einmal hatte (ezCombatDB.rotationSeen, Ersatz für Talente)
--
-- Eigener erfolgreicher Zauber (UNIT_SPELLCAST_SUCCEEDED, gerufen aus Auras.lua) – der Name in dieser Reihenfolge:
--   1. Zauber-ID lesbar → ihr Name
--   2. sonst der Schritt, dessen Zauber bei der letzten Bewertung (höchstens 0,5 s alt) „wird gerade gewirkt“ war
--      (C_Spell.IsCurrentSpell, nie gesperrt)
--   3. sonst – nur mit „Mitzählen“ (rotationEstimate) – der zuletzt gedrückte Aktionsknopf, wenn der Druck höchstens
--      Zauberzeit + 1 s zurückliegt (erschlossen, nicht gelesen)
--   4. sonst nichts; für once-Schritte mit Abklingzeit gilt zusätzlich: Beginnt im Kampf ihre Abklingzeit, sind sie
--      gewirkt (State.WatchCooldowns). Ein solcher Zauber ohne Namen entwertet jedes zuletzt offen gelesene „bereit“
--      bzw. „fehlt“ (ForgetStaleReads) – er kann es überholt haben.
-- Nichts hier rechnet mit gesperrten Werten: IDs und GUIDs laufen über ns.Num/ns.Plain.
--
-- Blizzards Regeln (Prüfung 17.11.2026, V1 und Risiko 1; entschieden vom Nutzer am 17.11.2026): Alles, was ein im
-- Kampf gesperrtes Wissen aus den eigenen Zaubern nachbaut – Restzeiten aus Zauber plus Dauer, „nie gewirkt heißt
-- fehlt bzw. bereit“, „Dauer vergangen heißt bereit“, „keine eigene Abklingzeit laut Tabellen heißt bereit“,
-- gezählte Ladungen und der Zaubername aus dem gedrückten Knopf –, gilt nur mit „Mitzählen“ (State.Estimating,
-- ab Werk aus). Ohne bleibt ein gesperrter Wert unbekannt: Der Schritt wird übersprungen und in /ezk status genannt.
-- Offen gelesene Werte (auch die letzte offene Lesung, „bereit“ laut Spiel, „wird gerade gewirkt“) gelten immer.
local State = {}
ns.RotationState = State

-- „Mitzählen, wenn das Spiel Werte sperrt“ (rotationEstimate) an? Die eine Stelle, an der der Motor das fragt.
function State.Estimating()
    return ns.S ~= nil and ns.S.rotationEstimate == true
end
local Estimating = State.Estimating

local CURRENT_WINDOW = 0.5      -- Sekunden: so alt darf „wird gerade gewirkt“ sein
local BUTTON_EXTRA = 1          -- Sekunden über der Zauberzeit, die ein Knopfdruck zurückliegen darf
local CAST_MAX = 60             -- Sekunden: länger läuft kein eigener Zauber oder Kanal (Schutz vor verpasstem Ende)
-- Grenzen der Zähler (rotation.counters; Gesamtreview 18.11.2026, T7-NE1): max ist eine ganze Zahl von 1 bis
-- COUNTER_MAX, gain/spend ganze Zahlen von 0 bis max, fallback.seconds über 0 bis COUNTER_SECONDS_MAX. Die Prüfung
-- eigener und geteilter Rotationen (RotationOwn.lua, CounterOK) nimmt dieselben Werte; Count bleibt auch ohne sie
-- begrenzt (keine Endlosschleife bei max < 0, keine Riesenschleife bei gain = 1e8).
State.COUNTER_MAX = 20
State.COUNTER_SECONDS_MAX = 600

local opening = true
local done = {}                 -- [Schlüssel] = "target" | "combat"
local castAt = {}               -- [Zaubername] = { at = Zeit, epoch = Ziel-Zähler }
local counters = {}             -- [Name] = { value, at } oder { entries = { Zeit … } } (each)
local cooldownSeen = {}         -- [Schlüssel] = lief die Abklingzeit beim letzten Blick?
local casting                   -- { name, since, channel }
local autorepeat                -- nil (noch kein Ereignis), true, false
local current                   -- { names = { … }, at = Zeit }: bei der letzten Bewertung „wird gerade gewirkt“
local castSource = "none"
local targetEpoch, lastGUID = 0, nil
local active = {}               -- { rotation, steps }: zuletzt bewertete Rotation
-- Nachgeführte eigene Auren (State.OwnAura): [Name] = { at, id } (eigener Zauber) bzw. { expires, read = true }
-- (zuletzt vollständig offen gelesen) – für den Spieler und je Ziel (GUID, gesperrt: Ziel-Zähler). any: je Ziel die
-- zuletzt vollständig offen gelesenen Debuffs gleich welcher Quelle (für Schritte mit mine = false).
local function NewOwn() return { player = {}, targets = {}, order = {}, any = {} } end
local own = NewOwn()
local forever = {}              -- [Name] = true: offen ohne Ablauf gesehen (Gestalt, Aura) – ein eigener Zauber hält
local OWN_TARGETS = 10          -- so viele Gegner merkt sich die Nachführung (die ältesten fallen heraus)
State.GUESS_SECONDS = 12        -- Annahme: Dauer eines DoTs/Buffs, wenn weder eine offene Lesung noch die
                                -- Zauberbeschreibung des Clients sie nennt (kürzeste übliche DoT-Dauer – lieber
                                -- einmal zu früh erneuern als nie setzen)
local described = {}            -- [Zauber-ID] = Sekunden | false: Dauer aus der Zauberbeschreibung
-- Eigene Abklingzeiten (State.Cooldown): [Name] = { at, when, src = "cast" | "seen" } (Beginn gezählt),
-- { expires, when, src = "read" } (offen gelesen) oder { ready = true, when } (das Spiel sagte offen „bereit“)
local cdRun = {}
local cdLearned = {}            -- [Name] = Sekunden: volle Dauer, offen gelesen (Talente eingerechnet)

---------------------------------------------------------------------------
-- Eröffnung, once
---------------------------------------------------------------------------

function State.Opening() return opening end
function State.OpenOpening() opening = true end
function State.CloseOpening() opening = false end

function State.Done(key) return key ~= nil and done[key] ~= nil end

-- scope: "target" (Standard) oder "combat" – bestimmt, wann das Häkchen wieder fällt.
function State.MarkDone(key, scope)
    if key == nil then return end
    done[key] = scope == "combat" and "combat" or "target"
end

---------------------------------------------------------------------------
-- Zuletzt bewertete Rotation (Rotation.Evaluate und EvaluatePrep melden sie)
---------------------------------------------------------------------------

function State.Use(rotation, steps)
    active.rotation, active.steps = rotation, steps
end

local function ActiveSteps()
    if active.steps then return active.steps, active.rotation end
    local Rotation = ns.Rotation
    if not Rotation then return {}, nil end
    local rotation = Rotation.Selected()
    return Rotation.Steps(rotation), rotation
end

local function StepName(step)
    local _, name = ns.Rotation.StepSpell(step)
    return name
end

---------------------------------------------------------------------------
-- Nachgeführte eigene Auren (Spieltest 15.11.2026, Befund 1: „der überspringt iwie rotation“)
---------------------------------------------------------------------------
-- Im Kampf sperrt Forever die Auren (C_UnitAuras.GetUnitAuraInstanceIDs wirft, jede Aura ist ein gesperrter Wert;
-- docs/archiv/probe-ergebnis-2026-11-14.md, Abschnitte 4 und 7). Dann wüsste die Rotation nie, ob ein eigener DoT oder Buff
-- fehlt, und übersprang „Fehlt oder läuft aus“ – nach Feuerbrand kam sofort der Zauberstab. Deshalb führt sie selbst
-- nach, was sie weiß:
--   - zuletzt vollständig offen gelesen (Rotation.UnitAuras außerhalb der Sperre): Name und Ablaufzeit,
--   - eigener erfolgreicher Zauber (State.OnOwnCast, Name nach der Regel im Dateikopf) auf das jetzige Ziel bzw. auf
--     den Spieler, mit der Dauer aus dem Client: offen gelernt (ezCore.Spells.AuraSeconds), sonst aus der
--     Zauberbeschreibung (State.DescriptionSeconds – im Kampf lesbar; eine offene Lesung eines DoTs gelingt auf
--     Forever fast nie, denn DoTs liegen nur im Kampf), erst dann die Annahme State.GUESS_SECONDS.
-- „Nie gewirkt auf dieses Ziel (und nicht offen gesehen)“ heißt „fehlt“. Das Ziel ist seine GUID, wenn sie lesbar
-- ist (zurück zu einem Gegner: sein Wissen bleibt), sonst der Ziel-Zähler (neues Ziel: alles fehlt). Kampfende leert
-- das Wissen über die Gegner (danach liest die Rotation wieder offen). Gesperrte Werte laufen über ns.Plain/ns.Num.

local function TargetKey()
    local guid = ns.Plain(UnitGUID and UnitGUID("target"))
    if type(guid) == "string" and guid ~= "" then return guid end
    return "epoch:" .. targetEpoch
end

-- Dauer in Sekunden aus einem Beschreibungstext des Clients („im Verlauf von 24 Sek.“, „4 Sek. lang“, „over 18 sec“,
-- „30 Min.“, „1 hour“). Nennt der Text mehrere verschiedene Dauern, entscheidet die Wendung „im Verlauf von“, „über“
-- bzw. „over“ davor, sonst nil (lieber die Annahme als eine falsche Zahl).
local UNIT_SECONDS = { sek = 1, sec = 1, min = 60, std = 3600, hou = 3600 }
local function Distinct(values)
    local one
    for _, value in ipairs(values) do
        if one and one ~= value then return nil end
        one = value
    end
    return one
end

function State.ParseSeconds(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    local all, over = {}, {}
    local start = 1
    while true do
        local first, last, number, unit = text:find("(%d+[%.,]?%d*)%s*(%a+)", start)
        if not first then break end
        local factor = UNIT_SECONDS[unit:sub(1, 3)]
        local value = factor and tonumber((number:gsub(",", ".")))
        if value and value > 0 then
            value = value * factor
            all[#all + 1] = value
            local before = text:sub(math.max(1, first - 16), first - 1)
            if before:find("verlauf von%s*$") or before:find("über%s*$") or before:find("over%s*$") then
                over[#over + 1] = value
            end
        end
        start = last + 1
    end
    return Distinct(all) or Distinct(over)
end

-- Dauer einer Aura aus der Beschreibung ihres Zaubers (C_Spell.GetSpellDescription; gesperrt oder noch nicht
-- geladen: nil, beim nächsten Mal neu gefragt). Gemerkt je Zauber-ID für die Sitzung.
function State.DescriptionSeconds(id)
    id = ns.Num(id)
    if not id then return nil end
    local cached = described[id]
    if cached ~= nil then return cached or nil end
    local api = rawget(_G, "C_Spell")
    local describe = type(api) == "table" and api.GetSpellDescription
    if type(describe) ~= "function" then return nil end
    local ok, text = pcall(describe, id)
    text = ok and ns.Plain(text) or nil
    if type(text) ~= "string" or text == "" then return nil end
    local seconds = State.ParseSeconds(text)
    described[id] = seconds or false
    return seconds
end

-- Schritte auf „pettarget“: Die Nachführung kennt nur das Ziel des Spielers. Sie gilt für das Ziel des Begleiters
-- nur, wenn beide dasselbe sind (beide GUIDs lesbar und gleich); sonst bleibt der Zustand unbekannt.
function State.PetOnTarget()
    if not UnitGUID then return false end
    local pet, target = ns.Plain(UnitGUID("pettarget")), ns.Plain(UnitGUID("target"))
    return type(pet) == "string" and pet ~= "" and pet == target
end

local function TargetMap(create)
    local key = TargetKey()
    local map = own.targets[key]
    if not map and create then
        map = {}
        own.targets[key] = map
        own.order[#own.order + 1] = key
        while #own.order > OWN_TARGETS do
            local old = table.remove(own.order, 1)
            own.targets[old], own.any[old] = nil, nil
        end
    end
    return map
end

-- Vollständig offen gelesene Auren (keine gesperrt, keine unlesbar): Sie ersetzen das Wissen über die Einheit.
-- unit: "player" (HELPFUL) oder "target" (eigene: HARMFUL|PLAYER); list: Einträge aus ezCore.Auras.Scan.
function State.NoteOwnRead(unit, list)
    local map, now = {}, GetTime()
    for _, aura in ipairs(type(list) == "table" and list or {}) do
        if not aura.secret and type(aura.name) == "string" then
            local expires = ns.Num(aura.expires)
            if expires == nil then forever[aura.name] = true end
            map[aura.name] = { expires = expires or math.huge, read = true, id = ns.Num(aura.spellId), when = now }
        end
    end
    if unit == "player" then
        own.player = map
    elseif unit == "target" then
        local old = TargetMap(true)
        for name in pairs(old) do old[name] = nil end
        for name, info in pairs(map) do old[name] = info end
    end
end

-- Vollständig offen gelesene Debuffs des Ziels gleich welcher Quelle ("target"|"HARMFUL"): Wissen für Schritte mit
-- mine = false („egal von wem“) – setzt ein Mitspieler den Debuff vor dem Kampf, bleibt er im Kampf bekannt.
function State.NoteAnyRead(list)
    local map, now = {}, GetTime()
    for _, aura in ipairs(type(list) == "table" and list or {}) do
        if not aura.secret and type(aura.name) == "string" then
            map[aura.name] = { expires = ns.Num(aura.expires) or math.huge, read = true, when = now }
        end
    end
    TargetMap(true)
    own.any[TargetKey()] = map
end

-- Eigener Zauber: auf dem Spieler und dem jetzigen Ziel als „gerade gesetzt“ merken (welche Aura er legt, fragt
-- State.OwnAura über den Namen).
function State.NoteOwnCast(name, id, now)
    if type(name) ~= "string" or name == "" then return end
    now = now or GetTime()
    local info = { at = now, id = ns.Num(id), when = now }
    own.player[name] = info
    TargetMap(true)[name] = info
end

-- Zustand einer eigenen Aura, die das Spiel gerade nicht lesen lässt. unit: "player" oder "target"; names: Namen,
-- unter denen sie liegt (Zauber und Aura, alle Ränge heißen gleich); seconds: Dauer aus dem Client oder nil;
-- any: auch Debuffs anderer Quellen (Schritt mit mine = false, zuletzt offen gelesen, State.NoteAnyRead).
-- → "missing" | "running", Restzeit (nil = unbekannt, math.huge = dauerhaft), Gesamtdauer, geschätzt (Annahme
-- GUESS_SECONDS), Herkunft: "never" (nie gewirkt, nie gesehen – gezählt), "read" (Ablauf aus der letzten offenen
-- Lesung), "forever" (offen ohne Ablauf gesehen), "cast" (eigener Zauber plus Dauer – gezählt) oder "uncounted"
-- (Zustand nur durch Mitzählen zu erfahren – nie gewirkt bzw. eigener Zauber mit unbekannter Restzeit – und
-- „Mitzählen“ (rotationEstimate) ist aus; dann ist auch der Zustand nil).
function State.OwnAura(unit, names, seconds, now, any)
    now = now or GetTime()
    local map = (unit == "player" and own.player) or TargetMap(false) or {}
    local other = unit ~= "player" and any and own.any[TargetKey()] or nil
    local best, bestName
    for _, name in ipairs(type(names) == "table" and names or {}) do
        for _, info in ipairs({ map[name] or false, other and other[name] or false }) do
            if info and (not best or info.when > best.when) then best, bestName = info, name end
        end
    end
    -- „nie gewirkt heißt fehlt“ ist ein Schluss aus den eigenen Zaubern, kein gelesener Wert (Blizzards Regeln, V1)
    if not best then
        if not Estimating() then return nil, nil, nil, nil, "uncounted" end
        return "missing", nil, nil, nil, "never"
    end
    local left, total, guessed, source
    if best.read then
        left, source = best.expires - now, best.expires == math.huge and "forever" or "read"
    elseif forever[bestName] then
        left, source = math.huge, "forever"     -- dauerhaft (so offen gesehen): gilt, bis offen gelesen „weg“
    elseif Estimating() then
        total = ns.Num(seconds) or Spells.AuraSeconds(best.id) or State.DescriptionSeconds(best.id)
        if not total then total, guessed = State.GUESS_SECONDS, true end
        left, source = total - (now - best.at), "cast"
    else
        -- gewirkt, Restzeit nur durch Mitzählen zu erfahren: auch der Zustand ist unbekannt (Fund 3 des code-reviewers
        -- vor dem Merge – vorher "running" mit Herkunft "uncounted"; die Aufrufer werteten die Herkunft schon aus)
        return nil, nil, nil, nil, "uncounted"
    end
    if left and left <= 0 then return "missing", left, total, guessed, source end
    return "running", left, total, guessed, source
end

---------------------------------------------------------------------------
-- Eigene Zauber
---------------------------------------------------------------------------

function State.CastSource() return castSource end

-- Zeitpunkt des letzten eigenen Zaubers dieses Namens; unit = "target": nur, wenn er auf das jetzige Ziel ging.
function State.CastAt(name, unit)
    local entry = name and castAt[name]
    if not entry then return nil end
    if unit ~= nil and unit ~= "player" and entry.epoch ~= targetEpoch then return nil end
    return entry.at
end

-- Rotation.Evaluate meldet die Zauber, die gerade gewirkt werden bzw. eingereiht sind.
function State.NoteCurrent(names)
    if type(names) == "table" and names[1] then
        current = { names = names, at = GetTime() }
    end
end

local function Amount(map, name)
    for id, amount in pairs(type(map) == "table" and map or {}) do
        if ns.SpellName(id) == name then return ns.Num(amount) or 0 end
    end
    return 0
end

local function CounterSeconds(def)
    local seconds = def.aura and Spells.AuraSeconds(def.aura)
    if not seconds and type(def.fallback) == "table" then seconds = ns.Num(def.fallback.seconds) end
    return seconds
end

-- Lebende Einträge eines each-Zählers (die abgelaufenen fallen heraus).
local function LiveEntries(counter, def, now)
    local seconds = CounterSeconds(def)
    local live = {}
    for _, at in ipairs(counter.entries or {}) do
        if not seconds or now - at < seconds then live[#live + 1] = at end
    end
    counter.entries = live
    return live, seconds
end

local function CountedValue(name, def, now)
    local counter = counters[name]
    if not counter then return 0 end
    if def.each then return #LiveEntries(counter, def, now) end
    local seconds = CounterSeconds(def)
    if seconds and counter.at and now - counter.at >= seconds then counter.value = 0 end
    return counter.value or 0
end

local function Count(name, def, cast, now)
    local gain, spend = Amount(def.gain, cast), Amount(def.spend, cast)
    if gain == 0 and spend == 0 then return end
    local maximum = ns.Num(def.max)
    local counter = counters[name] or {}
    counters[name] = counter
    if def.each then
        -- Schleifen nie über die Grenze hinaus (auch für Daten, die an der Prüfung vorbei in den Speicher kamen)
        local cap = State.COUNTER_MAX
        if maximum then cap = math.max(0, math.min(maximum, cap)) end
        local live = LiveEntries(counter, def, now)
        for _ = 1, math.min(spend, #live) do table.remove(live, 1) end
        for _ = 1, math.min(gain, cap) do live[#live + 1] = now end
        while #live > 0 and #live > cap do table.remove(live, 1) end
        return
    end
    local value = CountedValue(name, def, now)
    if gain > 0 then
        value = value + gain
        counter.at = now
    end
    value = math.max(0, value - spend)
    if maximum and value > maximum then value = math.max(0, maximum) end
    counter.value = value
end

-- Ein eigener Zauber dieses Namens ist gelungen: once-Schritte gleichen Namens abhaken, Zähler fortschreiben,
-- Ersatzuhr stellen. (Der Name kommt aus State.OnSpellcast oder – in Tests – direkt.)
function State.OnOwnCast(name, id)
    if type(name) ~= "string" or name == "" then return false end
    local now = GetTime()
    castAt[name] = { at = now, epoch = targetEpoch, id = ns.Num(id) }
    State.NoteOwnCast(name, id, now)
    local steps, rotation = ActiveSteps()
    for _, step in ipairs(steps) do
        if step.once and StepName(step) == name then
            State.MarkDone(ns.Rotation.StepKey(step), step.once)
        end
    end
    for counterName, def in pairs(rotation and type(rotation.counters) == "table" and rotation.counters or {}) do
        if type(def) == "table" then Count(counterName, def, name, now) end
    end
    return true
end

-- UNIT_SPELLCAST_SUCCEEDED des Spielers: id kann gesperrt sein, used = zuletzt gedrückter Aktionsknopf
-- ({ name, when } aus Auras.lua). Bestimmt den Namen (Reihenfolge im Dateikopf) und ruft State.OnOwnCast.
local function CastName(id, used)
    local now = GetTime()
    id = ns.Num(id)
    if id then
        local name = ns.SpellName(id)
        if name then return name, "id" end
    end
    if current and now - current.at <= CURRENT_WINDOW and current.names[1] then
        return current.names[1], "current"
    end
    -- erschlossen statt gelesen: nur mit „Mitzählen“ (Blizzards Regeln, Risiko 1)
    if Estimating() and type(used) == "table" and type(used.name) == "string" and used.when
        and now - used.when <= ns.CastTime(used.name) + BUTTON_EXTRA then
        return used.name, "button"
    end
    return nil
end

-- Ein eigener Zauber, dessen Name sich nicht bestimmen lässt (Zauber-ID gesperrt, nichts „wird gerade gewirkt“, ohne
-- „Mitzählen“ kein Knopf): Er kann jede zuletzt offen gelesene Aussage „bereit“ bzw. „fehlt“ überholt haben – sie
-- gilt nicht mehr, der Zustand ist unbekannt, bis das Spiel wieder offen antwortet. Entwertet werden das gemerkte
-- „bereit“ der Abklingzeiten und offen gelesene Ablaufzeiten, die schon vorbei sind (Abklingzeiten und Auren des
-- Spielers und des jetzigen Ziels); offen „läuft noch“ bleibt. Fund der Gegenprüfung vor dem Merge (17.11.2026): sonst
-- schlug die Rotation ohne „Mitzählen“ einen eben gewirkten Zauber in der globalen Abklingzeit wieder vor – der Befund
-- aus dem Spieltest vom 16.11.2026 („fähigkeit a danach b und danach a obwohl die noch nicht bereit ist“).
local function ForgetStaleReads(now)
    for name, entry in pairs(cdRun) do
        if entry.ready or (entry.src == "read" and entry.expires <= now) then cdRun[name] = nil end
    end
    local key = TargetKey()
    for _, map in ipairs({ own.player, own.targets[key] or false, own.any[key] or false }) do
        if map then
            for name, info in pairs(map) do
                if info.read and info.expires <= now then map[name] = nil end
            end
        end
    end
end

function State.OnSpellcast(id, used)
    local name, source = CastName(id, used)
    if not name then
        ForgetStaleReads(GetTime())
        return false
    end
    castSource = source
    if casting and not casting.channel then casting = nil end
    return State.OnOwnCast(name, ns.Num(id))
end

-- once-Schritte mit Abklingzeit: Beginnt im Kampf ihre Abklingzeit (Wechsel von „läuft nicht“ auf „läuft“), gelten
-- sie als gewirkt – der Rückfall, wenn weder Zauber-ID noch „wird gewirkt“ noch der Knopf den Zauber verraten.
function State.WatchCooldowns(steps, combat)
    for _, step in ipairs(steps or {}) do
        if step.once then
            local key = ns.Rotation.StepKey(step)
            local name = StepName(step)
            local running = name and ns.OnCooldown(name)
            if running ~= nil then
                if combat and cooldownSeen[key] == false and running == true and not done[key] then
                    State.MarkDone(key, step.once)
                    castSource = "cooldown"
                    if name then castAt[name] = { at = GetTime(), epoch = targetEpoch } end
                end
                cooldownSeen[key] = running
            end
        end
    end
end

---------------------------------------------------------------------------
-- Eigene Abklingzeiten, wenn das Spiel sie sperrt (Welle 27, Paket modul/ezcombat-abklingzeit)
---------------------------------------------------------------------------
-- Befund des Nutzers im Spiel am 16.11.2026 (Paladin, wörtlich): „es sagt fähigkeit a danach b und danach a obwohl die
-- noch nicht bereit ist, und obwohl b schon wieder bereit ist“ – A Richturteil, B Heiliger Stoß. Ursache: Im Kampf
-- sperrt Forever Start und Dauer der Abklingzeit; isActive bleibt offen, isOnGCD fehlt. Läuft dazu die globale
-- Abklingzeit, weiß niemand, ob nur sie oder die eigene läuft (ezCore.Spells.OnCooldown → nil), und der Motor wertete
-- den Schritt als bereit. Darum zählt ezCombat die eigene Abklingzeit selbst mit – für jeden Zauber, jede Art von
-- Schritt, jede Klasse und Rotation (Grundsatz des Nutzers vom 16.11.2026: „das muss ja für alle fälle gelten“):
--   1. Das Spiel antwortet offen (Start und Dauer lesbar): es gilt; die volle Dauer wird gemerkt (Talente
--      eingerechnet) und die Ablaufzeit für später (src "read", gelesen – nicht gezählt).
--   2. Das Spiel sagt nur ja oder nein (isActive, LockedKind): es gilt. „Nein“ beendet die gezählte Abklingzeit des
--      letzten Zaubers (verkürzt durch Talent, zurückgesetzt durch einen Proc); „ja“ ohne laufende Zählung beginnt
--      eine (src "seen": Zauber, deren Abklingzeit erst nach dem Ende einer Aura beginnt). Die Restzeit dazu ist dann
--      gezählt (Quelle "game+cast", Kennzeichnung „gezählt“) – ohne „Mitzählen“ bleibt sie unbekannt (keine
--      Vorwarnung, kein Vorrang); der Schritt läuft trotzdem, das sagt das Spiel.
--   3. Das Spiel schweigt (nil): letzte offene Lesung (offen „bereit“ bzw. offen gelesene Ablaufzeit), sonst eigener
--      Zauber plus Dauer – zuerst die offen gelesene, dann ezCore.Spells.BaseCooldown (Client, sonst Client-Tabellen);
--      der Vorschlag trägt dann „gezählt“. Nie gewirkt (seit der letzten offenen Antwort) heißt bereit, ebenso „keine
--      eigene Abklingzeit laut Tabellen“ und „seit dem Zauber ist die volle Dauer vergangen“. All das (alles außer der
--      letzten offenen Lesung) gilt nur mit „Mitzählen“ (rotationEstimate, ab Werk aus – Blizzards Regeln, Prüfung
--      17.11.2026, Risiko 1: vorher liefen „never“, „none“ und „elapsed“ auch ohne); ohne bleibt es unbekannt
--      (Quelle "uncounted").
State.LEARN_TOLERANCE = 0.5   -- Sekunden: so nah muss der offen gelesene Beginn am eigenen Zauber liegen, damit die Dauer gelernt wird
State.COOLDOWN_SETTLE = 0.2     -- Sekunden: so jung darf ein Zauber sein, bevor ein offenes „bereit“ seine Zählung beendet
                                -- (das Spiel legt die Abklingzeit erst mit dem Zauber an)

-- Dauer der eigenen Abklingzeit in Sekunden: offen gelesen (mit Talenten), sonst ezCore.Spells.BaseCooldown.
-- → Sekunden (0 = keine eigene Abklingzeit), Quelle ("read" | "client" | "tables") oder nil (unbekannt)
function State.CooldownSeconds(name, id)
    local learned = name and cdLearned[name]
    if learned then return learned, "read" end
    if type(Spells.BaseCooldown) ~= "function" then return nil end
    local seconds, source = Spells.BaseCooldown(id or name)
    if seconds == nil and id and name then seconds, source = Spells.BaseCooldown(name) end
    return seconds, source
end

local function CountedLeft(entry, name, id, now)
    local seconds = entry.seconds or State.CooldownSeconds(name, id)
    if seconds == nil then return nil, nil end
    if seconds <= Spells.GCD_MAX then return 0, seconds end
    return seconds - (now - entry.at), seconds
end

-- Erklärt ein eigener Zauber derselben Kategorie (laut Client-Tabellen, ns.SharedCooldownSpells) ein offenes „läuft“?
-- → { at = sein Zeitpunkt, seconds = seine Dauer } des jüngsten, der noch läuft, sonst nil (Fund des code-reviewers vor
-- dem Merge, 16.11.2026: vorher begann die Zählung beim ersten „läuft“ mit der eigenen Dauer – eine globale
-- Abklingzeit zu spät bzw. bei verschiedenen Dauern einer Kategorie noch länger „noch nicht bereit“).
function State.SharedCast(id, now)
    if not id or type(ns.SharedCooldownSpells) ~= "function" then return nil end
    local ok, others = pcall(ns.SharedCooldownSpells, id)
    if not ok or type(others) ~= "table" then return nil end
    local best
    for _, other in ipairs(others) do
        local cast = castAt[other.name]
        if cast and now >= cast.at then
            local seconds = State.CooldownSeconds(other.name, other.id)
            if seconds and seconds > Spells.GCD_MAX and now - cast.at < seconds and (not best or cast.at > best.at) then
                best = { at = cast.at, seconds = seconds }
            end
        end
    end
    return best
end

-- Zustand der eigenen Abklingzeit eines Zaubers. running: Antwort des Spiels (ns.OnCooldown: true/false/nil);
-- start, duration: offen gelesene Werte oder nil. → "ready" | "running" | nil (unbekannt), Restzeit (nil = unbekannt),
-- Quelle: "game" (das Spiel hat eben geantwortet), "game+cast" (das Spiel sagt „läuft“, die Restzeit ist gezählt),
-- "read" (letzte offene Lesung), "cast" (eigener Zauber plus Dauer – gezählt), "never" (seit der letzten offenen
-- Antwort nicht gewirkt – gezählt), "none" (keine eigene Abklingzeit laut Client bzw. Tabellen), "uncounted" (das
-- Spiel schweigt, nur durch Mitzählen zu erfahren, „Mitzählen“ aus – Zustand nil) oder "unknown" (gewirkt, Dauer
-- unbekannt). "cast", "never" und "none" gibt es nur mit „Mitzählen“.
function State.Cooldown(name, id, running, start, duration, now)
    if type(name) ~= "string" or name == "" then return nil, nil, "unknown" end
    now = now or GetTime()
    local entry = cdRun[name]
    local cast = castAt[name]
    if cast and (not entry or (entry.when or -math.huge) <= cast.at) then
        entry = { at = cast.at, when = cast.at, src = "cast" }
        cdRun[name] = entry
    end
    start, duration = ns.Num(start), ns.Num(duration)
    if start and duration then
        if start > 0 and duration > Spells.GCD_MAX and start + duration > now then
            -- die Dauer nur lernen, wenn der Beginn zum eigenen Zauber passt – sonst stammt die Sperre von einem Zauber
            -- derselben Kategorie mit anderer Dauer (Fund des code-reviewers vor dem Merge); die Ablaufzeit gilt trotzdem
            if cast and math.abs(start - cast.at) <= State.LEARN_TOLERANCE then cdLearned[name] = duration end
            cdRun[name] = { expires = start + duration, when = now, src = "read" }
            return "running", start + duration - now, "game"
        end
        -- offen keine oder nur die globale Abklingzeit: Das Spiel nennt die längere, die eigene läuft also nicht
        if not entry or entry.ready or now - (entry.at or entry.when or now) >= State.COOLDOWN_SETTLE then
            cdRun[name] = { ready = true, when = now }
        end
        return "ready", 0, "game"
    elseif running == true then
        local left, counted
        if entry and entry.src == "read" then
            left = entry.expires - now
        elseif entry and not entry.ready then
            left, counted = CountedLeft(entry, name, id, now), true
        end
        if not entry or entry.ready or (left and left <= 0) then
            local shared = State.SharedCast(id, now)
            cdRun[name] = { at = shared and shared.at or now, when = now, src = "seen", seconds = shared and shared.seconds }
            left, counted = CountedLeft(cdRun[name], name, id, now), true
        end
        if left and left <= 0 then left = nil end
        -- „läuft“ sagt das Spiel, die Restzeit aber ist gezählt (eigener Zauber plus Dauer): nur mit „Mitzählen“ und
        -- dann gekennzeichnet; ohne bleibt sie unbekannt – keine Vorwarnung, kein Vorrang (Leitlinie 6: nie raten).
        if counted and left then
            if not Estimating() then return "running", nil, "game" end
            return "running", left, "game+cast"
        end
        return "running", left, "game"
    elseif running == false then
        -- offen „bereit“ merken – auch ohne eigenen Zauber (letzte offene Lesung, gilt ohne „Mitzählen“ weiter)
        if not entry or (not entry.ready and now - (entry.at or entry.when or now) >= State.COOLDOWN_SETTLE) then
            cdRun[name] = { ready = true, when = now }
        end
        return "ready", 0, "game"
    end
    -- letzte offene Lesung: „bereit“ bzw. eine offen gelesene Ablaufzeit – gilt auch ohne „Mitzählen“
    if entry and entry.ready then return "ready", 0, "read" end
    if entry and entry.src == "read" then
        local left = entry.expires - now
        if left <= 0 then return "ready", 0, "read" end
        return "running", left, "read"
    end
    -- alles Weitere ist aus den eigenen Zaubern geschlossen (nie gewirkt, keine eigene Abklingzeit laut Tabellen,
    -- Dauer vergangen, Restzeit gezählt): nur mit „Mitzählen“, sonst unbekannt (Blizzards Regeln, Risiko 1 – vorher
    -- liefen „never“, „none“ und „elapsed“ auch ohne)
    if not Estimating() then return nil, nil, "uncounted" end
    if not entry then
        local seconds = State.CooldownSeconds(name, id)
        if seconds and seconds <= Spells.GCD_MAX then return "ready", 0, "none" end
        return "ready", 0, "never"
    end
    local left, seconds = CountedLeft(entry, name, id, now)
    if seconds == nil then return nil, nil, "unknown" end
    if seconds <= Spells.GCD_MAX then return "ready", 0, "none" end
    if left <= 0 then return "ready", 0, "cast" end
    return "running", left, "cast"
end

-- Beruht diese Quelle auf den eigenen Zaubern (Kennzeichnung „gezählt“)?
function State.CooldownCounted(source)
    return source == "cast" or source == "game+cast" or source == "never"
end

---------------------------------------------------------------------------
-- Eigener Zauber oder Kanal läuft (hold)
---------------------------------------------------------------------------

-- Schlüssel des Schritts, dessen eigener Zauber oder Kanal gerade läuft, sonst nil. steps: Schritte, in denen
-- gesucht wird (Standard: die zuletzt bewertete Rotation). Zweiter Wert: der Schritt.
function State.Casting(steps)
    if not casting then return nil end
    if GetTime() - casting.since > CAST_MAX then
        casting = nil
        return nil
    end
    for _, step in ipairs(steps or ActiveSteps()) do
        if StepName(step) == casting.name then return ns.Rotation.StepKey(step), step end
    end
    return nil
end

local function IsPlayer(unit) return not ns.IsSecret(unit) and unit == "player" end

local function OnCastStart(channel)
    return function(_, unit, _, spellID)
        if not IsPlayer(unit) then return end
        local name = CastName(spellID, ns.Auras and ns.Auras.LastUsed and ns.Auras.LastUsed())
        casting = name and { name = name, since = GetTime(), channel = channel } or nil
        if ns.Rotation and ns.Rotation.UpdateSoon then ns.Rotation.UpdateSoon() end
    end
end

local function OnCastEnd(channel)
    return function(_, unit)
        if not IsPlayer(unit) then return end
        if casting and (channel or not casting.channel) then casting = nil end
        if ns.Rotation and ns.Rotation.UpdateSoon then ns.Rotation.UpdateSoon() end
    end
end

-- nur für den Spieler (ns.OnUnit); die Prüfung im Zuhörer bleibt für gesperrte Einheiten
ns.OnUnit("UNIT_SPELLCAST_START", "player", OnCastStart(false))
ns.OnUnit("UNIT_SPELLCAST_CHANNEL_START", "player", OnCastStart(true))
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    ns.OnUnit(event, "player", OnCastEnd(false))
end
ns.OnUnit("UNIT_SPELLCAST_CHANNEL_STOP", "player", OnCastEnd(true))

---------------------------------------------------------------------------
-- Automatischer Schuss / Zauberstab
---------------------------------------------------------------------------

-- true/false nach dem letzten Ereignis; nil, solange noch keines kam.
function State.Autorepeat() return autorepeat end

ns.On("START_AUTOREPEAT_SPELL", function()
    autorepeat = true
    if ns.Rotation and ns.Rotation.UpdateSoon then ns.Rotation.UpdateSoon() end
end)
ns.On("STOP_AUTOREPEAT_SPELL", function()
    autorepeat = false
    if ns.Rotation and ns.Rotation.UpdateSoon then ns.Rotation.UpdateSoon() end
end)

---------------------------------------------------------------------------
-- Zähler (rotation.counters)
---------------------------------------------------------------------------

-- Wert und Quelle ("aura" = gelesen, "counted" = aus den eigenen Zaubern gezählt) oder nil (unbekannt).
-- ctx: Kontext einer Bewertung (liest die Auren des Spielers nur einmal), darf fehlen.
function State.Counter(name, ctx)
    local _, rotation = ActiveSteps()
    if ctx and ctx.rotation then rotation = ctx.rotation end
    local def = rotation and type(rotation.counters) == "table" and rotation.counters[name]
    if type(def) ~= "table" then return nil end
    -- known: eine ID oder eine Liste (alle gelernt) – dieselbe Prüfung wie need.known (Rotation.CHECKS.known), damit
    -- eine Liste nicht als „nie gelernt“ gilt (T7-NE6, Gesamtreview 18.11.2026)
    if def.known ~= nil then
        local checks = ns.Rotation and ns.Rotation.CHECKS
        local known
        if checks and checks.known then known = checks.known(def.known) else known = Spells.IsKnown(def.known) end
        if not known then return 0, "aura" end
    end
    if def.aura then
        local list, unknown = ns.Rotation.UnitAuras(ctx or { now = GetTime() }, "player", "HELPFUL", false)
        local aura = ns.Rotation.FindAura(list, def.aura)
        if aura and not aura.secret then return math.max(aura.count or 0, 1), "aura" end
        if not aura and unknown == 0 then return 0, "aura" end
    end
    if not Estimating() then return nil end
    return CountedValue(name, def, GetTime()), "counted"
end

-- Restzeit des ältesten Eintrags eines each-Zählers in Sekunden; nil ohne Eintrag oder ohne bekannte Dauer – und ohne
-- „Mitzählen“ (die Einträge sind die eigenen Zauber, gezählt; Blizzards Regeln, Risiko 1).
function State.Oldest(name, ctx)
    if not Estimating() then return nil end
    local _, rotation = ActiveSteps()
    if ctx and ctx.rotation then rotation = ctx.rotation end
    local def = rotation and type(rotation.counters) == "table" and rotation.counters[name]
    local counter = counters[name]
    if type(def) ~= "table" or not counter or not def.each then return nil end
    local now = GetTime()
    local live, seconds = LiveEntries(counter, def, now)
    if not live[1] or not seconds then return nil end
    return seconds - (now - live[1])
end

---------------------------------------------------------------------------
-- Gesehene Auren (je Charakter gemerkt)
---------------------------------------------------------------------------

local wanted = {}       -- [Aura-ID] = true: danach fragt eine Rotation (need.seen)

local function SeenStore(create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.rotationSeen) ~= "table" then
        if not create then return nil end
        db.rotationSeen = {}
    end
    local key = Core.charKey or "?"
    if type(db.rotationSeen[key]) ~= "table" then
        if not create then return nil end
        db.rotationSeen[key] = {}
    end
    return db.rotationSeen[key]
end

-- Hat dieser Charakter die Aura schon einmal gehabt? Merkt zugleich, dass nach ihr gefragt wird.
function State.Seen(auraID)
    auraID = ns.Num(auraID)
    if not auraID then return false end
    wanted[auraID] = true
    local store = SeenStore(false)
    return store ~= nil and store[auraID] == true
end

-- Offen gelesene Auren des Spielers: die gefragten merken.
function State.NoteAuras(list)
    if not next(wanted) then return end
    for _, aura in ipairs(list or {}) do
        local id = not aura.secret and ns.Num(aura.spellId)
        if id and wanted[id] then
            local store = SeenStore(true)
            if store and not store[id] then store[id] = true end
        end
    end
end

---------------------------------------------------------------------------
-- Zurücksetzen
---------------------------------------------------------------------------

-- "target": Häkchen „je Gegner“ und die Uhren der Ziel-Auren; "combat": alle Häkchen; "all": alles.
function State.ForgetCooldowns() cdRun, cdLearned = {}, {} end

function State.Reset(what)
    if what == "target" then
        for key, scope in pairs(done) do
            if scope == "target" then done[key] = nil end
        end
        cooldownSeen = {}
        targetEpoch = targetEpoch + 1
    elseif what == "combat" then
        done, cooldownSeen = {}, {}
    else
        -- eigene Zauber als laufende Abklingzeit festhalten, bevor castAt geleert wird (wie State.Cooldown es täte)
        for name, cast in pairs(castAt) do
            local entry = cdRun[name]
            if not entry or (entry.when or -math.huge) <= cast.at then
                cdRun[name] = { at = cast.at, when = cast.at, src = "cast" }
            end
        end
        done, cooldownSeen, counters, castAt = {}, {}, {}, {}
        -- cdRun und cdLearned bleiben: laufende Abklingzeiten und gelernte Dauern gehören zum Charakter, nicht zur Wahl
        -- der Rotation (Wahl, Anpassung, „Nach Talentbaum“ riefen sonst den alten Fehler bis zum nächsten Zauber
        -- hervor; Fund des code-reviewers vor dem Merge); State.ForgetCooldowns() leert sie ausdrücklich
        own, forever, described = NewOwn(), {}, {}
        casting, current = nil, nil
        targetEpoch = targetEpoch + 1
        opening = true
    end
end

ns.On("PLAYER_TARGET_CHANGED", function()
    local guid = ns.Plain(UnitGUID and UnitGUID("target"))
    if guid ~= nil and guid == lastGUID then return end
    lastGUID = guid
    State.Reset("target")
    State.OpenOpening()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    State.Reset("combat")
    own.targets, own.order, own.any = {}, {}, {}   -- Wissen über die Gegner gilt je Kampf (danach liest sie offen)
    State.OpenOpening()
end)

-- Kopie für Tests und /ezk status.
function State.Snapshot()
    local snapshot = { opening = opening, done = {}, counters = {}, casting = casting and casting.name or nil,
        autorepeat = autorepeat, castSource = castSource }
    for key, scope in pairs(done) do snapshot.done[key] = scope end
    for name, counter in pairs(counters) do
        snapshot.counters[name] = counter.entries and #counter.entries or counter.value or 0
    end
    return snapshot
end
