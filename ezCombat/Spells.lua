local _, ns = ...
local Spells = ezCore.Spells

-- Zauber-Wissen kommt aus ezCore (ezCore.Spells, Daten in ezCore/SpellData.lua): Ersatznamen, welche Fähigkeit
-- jeder Klasse wofür zählt (reactive, interrupt, finisher, nextSwing), Hinrichten-Zauber, Zauberzeit, Nutzbarkeit,
-- Abklingzeit. Verglichen wird nach Namen, damit jeder Rang zählt. Hier stehen nur die Kurzformen, die ezCombat
-- überall nutzt, und der Vermerk gesperrter Abklingzeiten für /ezk status – keine eigenen Daten.

-- Name eines Zaubers im Client, sonst der Ersatzname in der Sprache des Clients (nur der Name).
function ns.SpellName(id)
    return (Spells.Name(id))
end

-- Namen der Fähigkeiten einer Art für die eigene Klasse: { [Name] = spellID }.
function ns.ClassSpellNames(kind)
    return Spells.ClassSpellNames(kind, ns.playerClass)
end

-- Zauberzeit in Sekunden (für „rechtzeitig neu setzen“), 0 wenn unbekannt oder sofort.
ns.CastTime = Spells.CastTime

-- Nutzbar? Zweiter Wert: nur die Kraft (Wut, Energie, Mana) fehlt – die Gelegenheit ist aber da.
ns.SpellUsable = Spells.Usable

-- Längste globale Abklingzeit: Was nicht länger dauert, ist keine „echte“ Abklingzeit (ezCore.Spells.GCD_MAX).
ns.GCD_MAX = Spells.GCD_MAX

-- Art einer Abklingzeit: "none" (keine), "gcd" (nur die globale), "real" (echte Abklingzeit) oder nil (unbekannt).
-- Zuerst Start und Dauer, sonst die nie gesperrten Felder isActive und isOnGCD. Weiterleitung an
-- ezCore.Spells.CooldownKind (seit ezCore 1.8.0; die Regel stand vorher hier).
function ns.CooldownKind(info, start, duration)
    return Spells.CooldownKind(info, start, duration)
end

-- Läuft eine echte Abklingzeit (länger als die globale)? nil, wenn das Spiel es gerade nicht verrät.
-- Sind Start und Dauer gesperrt, entscheidet ezCore über isActive und isOnGCD (nie gesperrt); ezCombat vermerkt
-- die Sperre für /ezk status.
function ns.OnCooldown(spell)
    local onCooldown, why = Spells.OnCooldown(spell)
    if why == "secret" then ns.NoteSecret("cooldown") end
    return onCooldown
end

-- Start und Dauer der Abklingzeit, wenn das Spiel sie offen nennt (sonst nil, nil) – nur gelesen, nie verglichen,
-- solange gesperrt (Leitlinie 6).
function ns.CooldownTimes(spell)
    local api = C_Spell and C_Spell.GetSpellCooldown
    if type(api) ~= "function" or ns.IsSecret(spell) or spell == nil then return nil, nil end   -- IsSecret zuerst (T3-6)
    local ok, info = pcall(api, spell)
    if not ok or ns.IsSecret(info) or type(info) ~= "table" then return nil, nil end
    local start, duration = ns.Num(ezCore.Peek(info, "startTime")), ns.Num(ezCore.Peek(info, "duration"))
    if start and duration then return start, duration end
    return nil, nil
end

-- Geteilte Abklingzeiten (Welle 26, Folge-Paket F10 aus docs/wago-tools.md; Paket modul/ezcombat-kategorien): Zauber
-- derselben Kategorie laut Client-Tabellen (ezCore.Spells.SharedCooldown, z. B. die Schocks des Schamanen, die Fallen
-- des Jägers, Eislanze und Feuerschlag auf Forever). Ränge desselben Zaubers zählen nicht – deren Abklingzeit meldet das
-- Spiel schon über den Namen; ohne all nur Zauber, die der Spieler kennt (eine Kategorie mischt Klassen, etwa
-- Feuerschlag, Exorzismus und Gedankenschlag mit den Schocks). spell: Zauber-ID oder Name eines gelernten Zaubers.
-- → { { id, name } … } nach ID, je Name einmal (leer, wenn keiner)
local function SpellIDOf(spell)
    if type(spell) == "number" then return spell end
    if type(spell) ~= "string" or ns.IsSecret(spell) then return nil end
    local known = Spells.Known(spell)
    if known and known.maxID then return known.maxID end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
    local id = type(info) == "table" and ns.Num(info.spellID) or nil
    return id
end

-- Eigene Abklingzeit eines Zaubers für den Rotations-Motor (Welle 27, Paket modul/ezcombat-abklingzeit): die Antwort des
-- Spiels, und wo sie fehlt, die mitgezählte (ns.RotationState.Cooldown – Regeln dort). spell: Zauber-ID (oder Name);
-- name: sein Name (sonst aus der ID). → "ready" | "running" | nil (unbekannt), Restzeit oder nil, Quelle, gezählt (true,
-- wenn die Antwort auf den eigenen Zaubern beruht)
-- Gesamtreview 18.11.2026 (T8-9): reads (optional) ist der Merkzettel einer Bewertung (ctx.cooldownReads in
-- Rotation.lua): Die Antwort des Spiels (ns.OnCooldown, ns.CooldownTimes – je ein C_Spell.GetSpellCooldown) wird dann je
-- Zauber einmal je Bewertung gelesen; vorher las eine Bewertung sie zwei- bis dreimal je Zauber. Die eigene Rechnung
-- (RotationState) läuft weiter bei jedem Aufruf. Ohne reads wird wie bisher frisch gelesen.
local function GameCooldown(name, reads)
    local read = reads and reads[name]
    if read then return read.running, read.start, read.duration end
    local running = ns.OnCooldown(name)
    local start, duration = ns.CooldownTimes(name)
    if reads then reads[name] = { running = running, start = start, duration = duration } end
    return running, start, duration
end

function ns.CooldownState(spell, name, now, reads)
    name = name or (type(spell) == "string" and spell) or (type(spell) == "number" and ns.SpellName(spell)) or nil
    if not name then return nil, nil, "unknown", false end
    if type(reads) ~= "table" then reads = nil end
    local running, start, duration = GameCooldown(name, reads)
    local State = ns.RotationState
    if not (State and State.Cooldown) then
        if running == nil then return nil, nil, "unknown", false end
        return running and "running" or "ready", nil, "game", false
    end
    local state, left, source = State.Cooldown(name, SpellIDOf(spell), running, start,
        duration, now)
    return state, left, source, State.CooldownCounted(source)
end

-- Alle Zauber derselben Kategorie je Zauber-ID, je Name einmal – die Tabelle des Clients ändert sich nicht, darum
-- einmal gesucht (ezCores Suche läuft über die ganze Tabelle; der Motor fragt im Kampf je Schritt). Gemerkt nur, wenn der
-- Client jeden Namen kannte.
local sharedAll = {}
local function SharedAll(id)
    local cached = sharedAll[id]
    if cached then return cached end
    local list, own, seen, complete = {}, ns.SpellName(id), {}, true
    for _, other in ipairs(Spells.SharedCooldown(id)) do
        local name = ns.SpellName(other)
        if not name then
            complete = false
        elseif name ~= own and not seen[name] then
            seen[name] = true
            list[#list + 1] = { id = other, name = name }
        end
    end
    if complete and own then sharedAll[id] = list end
    return list
end

function ns.SharedCooldownSpells(spell, all)
    local out = {}
    local id = SpellIDOf(spell)
    if not id or type(Spells.SharedCooldown) ~= "function" then return out end
    for _, other in ipairs(SharedAll(id)) do
        if all or Spells.Known(other.name) or Spells.IsKnown(other.id) then
            out[#out + 1] = { id = other.id, name = other.name }
        end
    end
    return out
end

-- Läuft für diesen Zauber eine geteilte Abklingzeit, die das Spiel gerade nicht verrät? Gefragt nur, wenn die eigene
-- Antwort fehlt (ns.OnCooldown → nil, im Kampf auf Forever bei gesperrten Werten): Offene Werte des Spiels enthalten die
-- geteilte Abklingzeit schon, dann gilt das Spiel. → true, Name des anderen Zaubers: Bei einem gelernten Zauber
-- derselben Kategorie läuft eine echte Abklingzeit, oder er wurde eben gewirkt (vor weniger als der längsten globalen
-- Abklingzeit – solange zeigt das Spiel nur die globale); false: keiner; nil: unbekannt (gesperrt). Seit Welle 27
-- (Paket modul/ezcombat-abklingzeit) zählt ezCombat die Abklingzeit des anderen Zaubers mit, wenn das Spiel sie sperrt
-- (ns.CooldownState, Dauer des anderen Zaubers – laut Client-Tabellen dieselbe wie die der Kategorie bei den Schocks);
-- dritter Wert: true, wenn die Antwort gezählt ist; vierter: Restzeit in Sekunden, wenn bekannt (Vorwarnung). Unbekannt
-- bleibt nur, was auch gezählt nicht zu erfahren ist („Mitzählen“ aus, Dauer unbekannt). „Eben gewirkt (vor weniger als
-- der längsten globalen Abklingzeit)“ ist ein Schluss aus dem eigenen Zauber: nur mit „Mitzählen“ (Blizzards Regeln,
-- Prüfung 17.11.2026, Risiko 1).
function ns.SharedOnCooldown(spell, now, reads)   -- reads: Merkzettel der Bewertung (T8-9)
    local others = ns.SharedCooldownSpells(spell)
    if #others == 0 then return false end
    now = now or GetTime()
    local State, unknown, counted = ns.RotationState, false, false
    local estimating = State and State.Estimating and State.Estimating()
    for _, other in ipairs(others) do
        local at = State and State.CastAt and State.CastAt(other.name)
        local state, left, _, isCounted = ns.CooldownState(other.id, other.name, now, reads)
        if state == "running" then return true, other.name, isCounted or nil, left end
        if estimating and type(at) == "number" and now >= at and now - at < Spells.GCD_MAX then
            -- erschlossen aus dem eigenen Zauber, also gezählt (Gesamtreview 18.11.2026, T7-NE5)
            return true, other.name, true, Spells.GCD_MAX - (now - at)
        end
        if state == nil then unknown = true end
        if isCounted then counted = true end
    end
    if unknown then return nil end
    return false, nil, counted or nil
end

-- Zeile für Tooltips (Spickzettel, Seite zum Anpassen): „Teilt die Abklingzeit mit … – laut Client-Tabellen (…).“
-- (Leitlinie 11: die Quelle steht dabei) oder nil, wenn der Zauber mit keinem gelernten Zauber eine Abklingzeit teilt.
function ns.SharedCooldownText(spell)
    local others = ns.SharedCooldownSpells(spell)
    if #others == 0 then return nil end
    local names = {}
    for _, other in ipairs(others) do names[#names + 1] = other.name end
    local CD = ezCore.ClientData
    local source = CD and CD.SourceText and CD.SourceText("categories") or nil
    local L = ns.L
    if source then return L.ROTATION_SHARED_CD:format(table.concat(names, ", "), source) end
    return L.ROTATION_SHARED_CD_PLAIN:format(table.concat(names, ", "))
end
