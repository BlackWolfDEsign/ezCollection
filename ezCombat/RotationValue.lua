local _, ns = ...
local Core = ezCore
local L = ns.L

--[[
    Werte der Fähigkeiten abwägen (Auftrag des Nutzers vom 23.11.2026, wörtlich: „ezrotation: muss die stats der
    fähigkeiten berücksichtigen, z.b. schattenblitz vs zauberstab, was ist im moment besser, wenn das geht, voll
    durchdacht für alle klassen“; Plan und Grenzen: docs/roadmap/ezCombat.md, „Offen: Werte der Fähigkeiten abwägen“).

    Wo: unter den Füllern einer Rotation (kind = "filler") – der erste fällige Füller mit Mana-Kosten (Schattenblitz,
    Zermürben, Göttliche Pein, Frostblitz …) gegen den Zauberstab (Schießen 5019). Die Werte rechnet ezCore.SpellValue
    (Client-Tabellen und deine Werte, im Kampf die letzte offene Rechnung). Regeln, in dieser Reihenfolge:
      1. Steht der Stab als Füller in der Rotation und könnte er jetzt schießen: Vorteil des Zaubers je Wurf
         G = Menge − Stab je Sekunde × Zeit des Zaubers. G ≤ 0: der Stab (er macht je Sekunde mindestens so viel).
      2. G > 0: Bleibt nach dem Zauber mindestens die Reserve (Regler „Mana zurückhalten“), der Zauber, sonst der Stab.
         Mana in Prozent: außerhalb des Kampfes offen; im Kampf nur mit „Mitzählen“ (rotationEstimate, ab Werk aus –
         Blizzards Regeln, Risiko 1): Stand vor dem Kampf − Kosten eigener Würfe + Regeneration, begrenzt durch die
         Spanne aus Blizzards Nutzbarkeit (Spells.PowerBounds); der Vorschlag trägt dann „gezählt“.
      3. Mana unbekannt: Meldet das Spiel beim Zauber „zu wenig Mana“, der Stab; sonst bleibt die Reihenfolge der
         Rotation (sie kennt Procs und Schwächungen, die das Modell nicht rechnet) und der Text nennt den Unterschied.
      4. Steht kein Stab in der Rotation (Schlachtzug, Magier nur als Hinweis): nur wenn der Füller nicht bezahlbar ist
         und ein Stab angelegt und nutzbar ist, der Stab.
    Wählt die Abwägung den Stab und er schießt schon, schlägt ezCombat nichts Neues vor (wie bisher). Sie ändert nur
    einen Vorschlag, der ohnehin ein Füller ist (oder leer); höhere Schritte (DoTs, Abklingzeiten, Mana-Rückholer)
    bleiben vorn.

      Value.WAND                    5019 (Schießen)
      Value.Enabled()               Schalter rotationValues
      Value.Reserve()               Regler rotationManaReserve in Prozent
      Value.ManaPercent(ctx)        → Prozent, Quelle ("open" | "counted") oder nil
      Value.Weigh(found, ctx, steps)→ nil (nichts geändert) oder { step | false, name, note, counted }
      Value.Text(note)              → kurze Zeile für die Anzeige („Stab 11/s ≥ Schattenblitz 9/s“) oder nil
      Value.StatusText(note)        → Zeile für /ezk status mit Quelle oder nil
      Value.ShowFinish(note)        Marke „Stab reicht“ (Ziel fast tot) unten rechts an der Mitte, Abschnitt unten
]]

local Value = {}
ns.RotationValue = Value

Value.WAND = 5019
Value.DEFAULT_RESERVE = 30
Value.FSR = 5               -- Sekunden nach einem Zauber mit Mana-Kosten: Regeneration „beim Zaubern“ (5-Sekunden-Regel)

local function Rotation() return ns.Rotation end
local function State() return ns.RotationState end

function Value.Enabled()
    return ns.S ~= nil and ns.S.rotationValues ~= false
end

function Value.Reserve()
    local value = ns.Num(ns.S and ns.S.rotationManaReserve)
    if not value then return Value.DEFAULT_RESERVE end
    return math.max(0, math.min(100, value))
end

local function ManaType() return Core.SpellValue.ManaType() end

-- Client-Abfrage → zwei offene Zahlen oder nil (gesperrt, Fehler, fehlt) – über ezCores Core.PlainCall
local function Open(name, ...)
    local a, b = Core.PlainCall(rawget(_G, name), ...)
    return ns.Num(a), ns.Num(b)
end

---------------------------------------------------------------------------
-- Mana im Kampf mitzählen (nur mit „Mitzählen“)
---------------------------------------------------------------------------

-- mana, max: letzte offene Lesung; t: bis hierher ist die Regeneration aufgerechnet; spent, regen: seit der Lesung;
-- base, casting: Regeneration je Sekunde ohne bzw. mit 5-Sekunden-Regel (GetManaRegen, offen gelesen);
-- lastCast: letzter eigener Zauber mit Mana-Kosten; broken: im Kampf nicht mehr zu schätzen (Grund)
local count = { spent = 0, regen = 0 }
Value.count = count

-- Offene Lesung: setzt den Zähler auf den Stand des Spiels → true, wenn Mana offen war
function Value.ReadOpen()
    local cur = Open("UnitPower", "player", ManaType())
    local max = Open("UnitPowerMax", "player", ManaType())
    if not (cur and max and max > 0) then return false end
    count.mana, count.max, count.t, count.spent, count.regen, count.broken = cur, max, Core.Uptime(), 0, 0, nil
    local base, casting = Open("GetManaRegen")
    if base and casting then count.base, count.casting = base, casting end
    return true
end

-- Regeneration bis now aufrechnen (beim Zaubern bis Value.FSR nach dem letzten Zauber, danach die freie) – nie über
-- das Höchstmana: was bei vollem Mana „regeneriert“ würde, verfällt (Review vom 23.11.2026)
local function Accrue(now)
    if not (count.t and count.base and count.casting) then
        count.t = now
        return
    end
    local from = count.t
    if now <= from then return end
    local edge = count.lastCast and (count.lastCast + Value.FSR) or from
    local castingUntil = math.min(now, math.max(from, edge))
    local gain = (castingUntil - from) * count.casting + (now - castingUntil) * count.base
    local room = (count.max or 0) - (count.mana - count.spent + count.regen)
    count.regen = count.regen + math.max(0, math.min(gain, room))
    count.t = now
end

-- Mana-Kosten eines eigenen Wurfs: offen gelesen, sonst die letzte offene Rechnung von ezCore.SpellValue
local function CastCost(spellID)
    local SV = Core.SpellValue
    local cost = SV.Cost(spellID)
    if cost then return cost end
    local memo = SV.Of(spellID)
    return memo and memo.cost or nil
end

-- Ist dieser Zauber ein Mana-Rückholer der gewählten Rotation (Art „resource“: Aderlass, Hervorrufung …)?
local function GivesMana(spellID)
    local R = Rotation()
    local rotation = R and R.Selected and R.Selected()
    local name = ns.SpellName(spellID)
    if not (rotation and name) then return false end
    for _, step in ipairs(R.Steps(rotation)) do
        if step.kind == "resource" and ns.SpellName(step.id) == name then return true end
    end
    return false
end

function Value.OnCast(spellID)
    if ns.IsSecret(spellID) then
        -- welcher Zauber, ist gesperrt: RotationState benennt ihn nach seiner Regel (Value.OnNamedCast) oder meldet ihn
        -- als unbekannt (Value.OnUnnamedCast) – unabhängig davon, welcher Empfänger des Ereignisses zuerst läuft
        return
    end
    spellID = ns.Num(spellID)
    if not spellID then return end
    if not ns.InCombat() then
        Value.ReadOpen()
        -- ein Eröffnungszauber mit Mana-Kosten startet die 5-Sekunden-Regel schon vor dem Kampf
        local cost = Core.SpellValue.Cost(spellID)
        if cost and cost > 0 then count.lastCast = Core.Uptime() end
        return
    end
    if not count.mana or count.broken then return end
    if not State().Estimating() then
        count.broken = "estimate"
        return
    end
    local now = Core.Uptime()
    Accrue(now)
    if GivesMana(spellID) then
        count.broken = "gain"          -- was er zurückgibt, steht in keiner Tabelle: bis zur nächsten offenen Lesung unbekannt
        return
    end
    local cost = CastCost(spellID)
    if cost == nil then
        count.broken = "cost"
        return
    end
    if cost > 0 then
        count.spent = count.spent + cost
        count.lastCast = now
    end
end

-- Zauber der gewählten Rotation zu einem Namen (höchster gelernter Rang) oder nil
local function SpellOfName(name)
    local R = Rotation()
    local rotation = R and R.Selected and R.Selected()
    if not (rotation and type(name) == "string") then return nil end
    for _, step in ipairs(R.Steps(rotation)) do
        local spell, stepName = R.StepSpell(step)
        if stepName == name and ns.Num(spell) then return spell end
    end
    return nil
end

-- Eigener Wurf mit gesperrter Zauber-ID, Name aus RotationState (State.OnSpellcast: „wird gerade gewirkt“, mit
-- „Mitzählen“ der gedrückte Knopf). Zweitmeinung zum Spieltest vom 23.11.2026: vorher brach die Zählung beim ersten
-- gesperrten Wurf im Kampf ab. Ein Zauber außerhalb der Rotation hat keine bekannten Kosten: Mana unbekannt.
function Value.OnNamedCast(name)
    local spellID = SpellOfName(name)
    if spellID then return Value.OnCast(spellID) end
    Value.OnUnnamedCast()
end

function Value.OnUnnamedCast()
    if ns.InCombat() and count.mana then count.broken = "secret" end
end

-- Geschätztes Mana in Prozent oder nil. Die Spanne teilt sich die Bewertung mit Rotation.lua (ctx.powerBounds, je
-- Kraftart { lo, hi, loBy, hiBy }) – ein Lauf über die Mana-Zauber je Bewertung
local function Counted(ctx)
    if not (count.mana and count.max and count.max > 0) or count.broken then return nil end
    if not State().Estimating() then return nil end
    Accrue(Core.Uptime())
    local estimate = count.mana - count.spent + count.regen
    local read = Rotation().Bounds("Mana", ctx) or {}
    local bounds = { lo = read.lo or 0, hi = read.hi }
    if estimate < bounds.lo then estimate = bounds.lo end
    if bounds.hi and estimate >= bounds.hi then estimate = bounds.hi - 1 end
    estimate = math.max(0, math.min(count.max, estimate))
    return estimate / count.max * 100
end

function Value.ManaPercent(ctx)
    local open = Rotation().ManaPercent()
    if open then
        Value.ReadOpen()
        return open, "open"
    end
    local counted = Counted(ctx)
    if counted then return counted, "counted" end
    return nil
end

-- Höchstes Mana des Spielers (beim Spieler offen; sonst die letzte Lesung)
local function ManaMax()
    local max = Open("UnitPowerMax", "player", ManaType())
    if max and max > 0 then return max end
    return count.max
end

---------------------------------------------------------------------------
-- Unter Beschuss (Antwort des Nutzers vom 23.11.2026, wörtlich: „unterschied ob mich jmd im nahkampf oder fernkampf
-- angreift, weil nahkampf zaubern eines schattenblitzes vervielfätigt, ist also mehrfach situationsabhänig, nah oder
-- fern, mana, schaden/s“). Nahkampf-Reichweite ist im Kampf nicht sicher offen lesbar; die Verzögerung kommt aber von
-- jedem Treffer auf dich (nah oder fern). Offen: UNIT_COMBAT für "player" (Art des Treffers, nur der Betrag gesperrt).
--   Treffer je Sekunde r: Treffer („WOUND“) der letzten Value.HIT_WINDOW Sekunden (im Kampf kürzer: seit Kampfbeginn).
--   Verzögerung je Treffer p: gemessen (UNIT_SPELLCAST_DELAYED: Ende der eigenen Zauberleiste vorher/nachher, wenn
--   offen), bis dahin Value.PUSHBACK (Annahme).
--   Zauberzeit unter Beschuss: Zauberzeit ÷ (1 − r × p) (jeder Treffer während des Zaubers schiebt ihn weiter;
--   r × p höchstens Value.PUSHBACK_LOAD). Kanal: die Menge sinkt um denselben Anteil (Treffer kürzen ihn), die Zeit
--   bleibt. Stab und Sofortzauber: keine Verzögerung (Annahme, im Spiel prüfen).
---------------------------------------------------------------------------

Value.HIT_WINDOW = 5        -- Sekunden, über die Treffer auf dich gezählt werden (zu Kampfbeginn mindestens die
                            -- Hälfte davon: ein einzelner früher Treffer kippt den Vorschlag nicht, Review 23.11.2026)
Value.PUSHBACK = 0.5        -- Sekunden Verzögerung je Treffer, bis ezCombat sie gemessen hat (Annahme)
Value.PUSHBACK_LOAD = 0.75  -- höchstens dieser Anteil der Zeit geht an Verzögerungen (Wirkzeit höchstens × 4)

local hits = {}             -- Zeitpunkte der Treffer auf dich (Core.Uptime)
local combatStart
local push = { sum = 0, n = 0, castEnd = nil }
Value.push = push

local function Prune(now)
    local keep = {}
    for _, t in ipairs(hits) do if now - t <= Value.HIT_WINDOW then keep[#keep + 1] = t end end
    hits = keep
end

function Value.OnHit(kind)
    if ns.IsSecret(kind) or kind ~= "WOUND" then return end
    local now = Core.Uptime()
    hits[#hits + 1] = now
    Prune(now)
end

-- Treffer je Sekunde auf dich (0 ohne Treffer)
function Value.HitRate()
    local now = Core.Uptime()
    Prune(now)
    if #hits == 0 then return 0 end
    local span = Value.HIT_WINDOW
    if combatStart and now - combatStart < span then span = math.max(Value.HIT_WINDOW / 2, now - combatStart) end
    return #hits / span
end

-- Verzögerung je Treffer → Sekunden, Quelle ("measured" | "assumed")
function Value.Pushback()
    if push.n > 0 then return push.sum / push.n, "measured" end
    return Value.PUSHBACK, "assumed"
end

-- Ende der eigenen Zauberleiste in Sekunden oder nil (gesperrt, keine)
local function CastEnd()
    local fn = rawget(_G, "UnitCastingInfo")
    if type(fn) ~= "function" then return nil end
    local ok, _, _, _, _, endMs = pcall(fn, "player")
    if not ok or ns.IsSecret(endMs) then return nil end
    endMs = ns.Num(endMs)
    return endMs and endMs / 1000 or nil
end

function Value.OnCastStart() push.castEnd = CastEnd() end

function Value.OnCastDelayed()
    local before, after = push.castEnd, CastEnd()
    push.castEnd = after
    if not (before and after) then return end
    local delta = after - before
    if delta > 0 and delta <= 3 then
        push.sum, push.n = push.sum + delta, push.n + 1
    end
end

-- Werte eines Zaubers unter Beschuss: Kopie von row mit verzögerter Zeit bzw. gekürzter Menge (Kanal), dazu
-- { rate, pushback, source, plain = Zeit ohne Beschuss } – oder row selbst, wenn keine Treffer zählen
function Value.UnderFire(row, spellID)
    local rate = Value.HitRate()
    if not row or rate <= 0 then return row, nil end
    local p, source = Value.Pushback()
    local load = math.min(rate * p, Value.PUSHBACK_LOAD)
    local fire = { rate = rate, pushback = p, source = source, plain = row.time }
    local info = Core.SpellValue.Info(spellID)
    local out = {}
    for key, value in pairs(row) do out[key] = value end
    if info and (info.channel or 0) > 0 then
        out.amount = row.amount * (1 - load)
        fire.channel = true
    else
        local cast = Core.SpellValue.CastTime(spellID)
        if not cast or cast <= 0 then return row, nil end       -- Sofortzauber (oder gesperrt): keine Verzögerung
        out.time = math.max(row.time, cast / (1 - load))
        if out.time <= row.time then return row, nil end       -- bleibt unter der globalen Abklingzeit
    end
    out.dps = out.amount / out.time
    out.dpm = (out.cost or 0) > 0 and out.amount / out.cost or nil
    return out, fire
end

---------------------------------------------------------------------------
-- Ziel fast tot: Marke „Stab reicht“ (Entscheidung 3 des Nutzers vom 23.11.2026: „Jetzt in diesem Paket“)
-- Steht der teure Füller in der Mitte, zeigt eine kleine Marke mit dem Zauberstab unten rechts am mittigen Symbol
-- (Symbol.NewLayer, Lage "corner"), sobald das Leben des Ziels unter den Anteil fällt, den der Stab in der Zeit des
-- Zaubers selbst schafft: Anteil = Stab je Sekunde × Zeit des Zaubers (unter Beschuss verzögert) ÷ Höchstleben des
-- Ziels, abgerundet auf ganze Prozent. Darunter stirbt das Ziel am Stab früher, als der Zauber durch ist – der Zauber
-- kostet dann nur Mana. Das Leben des Ziels liest ezCombat nie: Blizzards Kurve setzt die Deckkraft
-- (Core.HealthBelowAlpha, UnitHealthPercent, Leitlinie 6). Das Höchstleben ist im Kampf gesperrt (Daten-Probe vom
-- 23.11.2026, R5); ezCombat merkt es sich offen gelesen beim Anvisieren außerhalb des Kampfes je Gegner (GUID, im Kampf
-- lesbar, Probe R3) und je Art (NPC-ID mit Stufe; ohne offene Stufe die NPC-ID). Unbekannt: keine Marke. Teil des Schalters
-- rotationValues; das Leuchten am Knopf folgt der Kurve nicht (es bräuchte einen Vergleich im Code).
---------------------------------------------------------------------------

Value.FINISH_KEY = "value_finish"
Value.FINISH_STEP = 0.01    -- Anteil auf ganze Prozent abgerundet: eine Kurve je Prozent (Core.HealthCurve merkt sie)
Value.FINISH_MEMO = 200     -- so viele Gegner (GUID) merkt ezCombat, danach beginnt die Liste neu

local health = { guid = {}, kind = {}, guids = 0 }
Value.health = health
local finish = { demoUntil = 0 }
Value.finish = finish

-- GUID, NPC-ID und NPC-ID mit Stufe des Ziels (Schlüssel für das gemerkte Höchstleben) – jeweils nil, wenn gesperrt
local function TargetKeys()
    local guid = Core.PlainCall(rawget(_G, "UnitGUID"), "target")
    if type(guid) ~= "string" or guid == "" then guid = nil end
    local npc = guid and Core.NpcID(guid) or nil
    local level = npc and Open("UnitLevel", "target") or nil
    return guid, npc and tostring(npc) or nil, npc and level and (npc .. ":" .. level) or nil
end

-- Höchstleben des Ziels offen lesen und merken → Zahl oder nil (kein Ziel, gesperrt)
function Value.RememberTarget()
    local max = Open("UnitHealthMax", "target")
    if not max or max <= 0 then return nil end
    local guid, npc, npcLevel = TargetKeys()
    if guid and not health.guid[guid] then
        if health.guids >= Value.FINISH_MEMO then health.guid, health.guids = {}, 0 end
        health.guids = health.guids + 1
    end
    if guid then health.guid[guid] = max end
    if npc then health.kind[npc] = max end
    if npcLevel then health.kind[npcLevel] = max end
    return max
end

-- → Höchstleben, Quelle ("open" | "memo") oder nil. Die NPC-ID allein nur, wenn die Stufe nicht offen ist – Gegner, die
-- mit dir skalieren, haben auf einer anderen Stufe ein anderes Höchstleben (Review vom 23.11.2026)
function Value.TargetMaxHealth()
    local max = Value.RememberTarget()
    if max then return max, "open" end
    local guid, npc, npcLevel = TargetKeys()
    max = guid and health.guid[guid] or npcLevel and health.kind[npcLevel] or not npcLevel and npc and health.kind[npc]
        or nil
    if max then return max, "memo" end
    return nil
end

-- Anteil am Höchstleben des Ziels, unter dem der Stab es in der Zeit des Zaubers selbst schafft → 0,01…1 und Quelle
-- des Höchstlebens, oder nil (Werte oder Höchstleben unbekannt, unter 1 %)
function Value.FinishShare(wand, spell)
    local dps, time = ns.Num(wand and wand.dps), ns.Num(spell and spell.time)
    if not (dps and time) or dps <= 0 or time <= 0 then return nil end
    local max, from = Value.TargetMaxHealth()
    if not max then return nil end
    local share = math.floor(dps * time / max / Value.FINISH_STEP) * Value.FINISH_STEP
    if share < Value.FINISH_STEP then return nil end
    return math.min(share, 1), from
end

-- Die Ebene der Marke (über ezCombats gemeinsame Ebenen); legt sie bei Bedarf an. Rahmen wie die übrigen Symbole:
-- Leuchtrahmen der Art „next“ (Blizzards Gold wie die Mitte; Spieltest 23.11.2026: „wieso grün? wtf“ – keine
-- Sonderfarbe, Leitlinie 1)
Value.FINISH_GLOW = "next"
function Value.FinishLayer()
    if finish.layer then return finish.layer end
    if not (ns.Symbol and ns.Symbol.NewLayer) then return nil end
    finish.layer = ns.Symbol.NewLayer(Value.FINISH_KEY, "corner", Value.FINISH_GLOW)
    return finish.layer
end

local function FinishIcon(wand)
    local item = wand and wand.item
    return item and Core.ItemIcon(item) or Core.Spells.Icon(Value.WAND) or Core.ICON_FALLBACK_ID
end

-- Ziel da und nicht tot (offen gelesen; gesperrt zählt als „nein“ – lieber keine Marke)
local function TargetAlive()
    return ns.UnitPresent("target") == true and not ns.Bool(Core.Call(rawget(_G, "UnitIsDead"), "target"), true)
end

-- Deckkraft aus Blizzards Kurve (1 unter dem Anteil, sonst 0); ohne Kurve lieber nichts zeigen als raten. Ein totes
-- Ziel hat 0 % Leben – bis die Rotation den Füller abräumt, bliebe die Marke sonst nach jedem Sieg kurz voll sichtbar.
function Value.ApplyFinish()
    local layer = finish.layer
    if not layer or not layer:IsShown() then return end
    if GetTime() < finish.demoUntil then
        layer:SetAlpha(1)
        return
    end
    if not (finish.share and TargetAlive() and Core.HealthBelowAlpha(layer, "target", finish.share, false)) then
        layer:SetAlpha(0)
    end
end

-- Marke zur Bewertung der Mitte (note.finish, nil = keine) zeigen oder abbauen; Rotation.lua ruft das bei jeder Anzeige
function Value.ShowFinish(note)
    finish.note = note
    if GetTime() < finish.demoUntil then return end
    local share = type(note) == "table" and ns.Num(note.finish) or nil
    local layer = share and Value.FinishLayer() or finish.layer
    if not layer then return end
    if not share then
        finish.share = nil
        layer:Hide()
        return
    end
    finish.share = share
    layer.icon:SetTexture(FinishIcon(note.wand))
    layer:Show()
    Value.ApplyFinish()
end

-- Vorschau („Zeigen“, Symbol.Demo): die Marke voll sichtbar, danach wie vorher; nur mit Schalter und angelegtem Stab
-- → true, wenn sie zu sehen ist
function Value.FinishDemo(seconds)
    if not (Value.Enabled() and ns.Enabled("rotation")) then return false end
    local wand = Core.SpellValue.Wand()
    local layer = wand and Value.FinishLayer()
    if not layer then return false end
    seconds = ns.Num(seconds) or 4
    local untilTime = GetTime() + seconds
    finish.demoUntil = untilTime
    layer.icon:SetTexture(FinishIcon(wand))
    layer:Show()
    layer:SetAlpha(1)
    C_Timer.After(seconds, function()
        if finish.demoUntil ~= untilTime then return end   -- eine neuere Vorschau läuft noch
        finish.demoUntil = 0
        Value.ShowFinish(finish.note)
    end)
    return true
end

---------------------------------------------------------------------------
-- Abwägen
---------------------------------------------------------------------------

-- Zauberstab-Schritt, wenn die Rotation keinen führt (Regel 4); Text wie die Vorlagen
Value.WAND_STEP = { id = Value.WAND, key = "value:wand", kind = "filler", when = "autorepeat",
    text = { "Zu wenig Mana für den Füller: Zauberstab, bis es reicht.",
        "Not enough mana for your filler: wand until it does." } }

local function IsWand(step) return ns.Num(step and step.id) == Value.WAND end

-- Fällig mit Zusatzschaltern im ctx (ohne sie danach stehen zu lassen)
local function DueWith(step, ctx, flags)
    for key, flag in pairs(flags) do ctx[key] = flag end
    ctx.counted = nil
    local due = Rotation().StepDue(step, ctx)
    for key in pairs(flags) do ctx[key] = nil end
    return due
end

-- Kann der Stab jetzt schießen (Schritt der Rotation oder WAND_STEP)? Der laufende automatische Schuss zählt als
-- „kann“ – die Bedingung „läuft nicht“ prüft hier nicht.
local function WandReady(step, ctx)
    local _, name, known = Rotation().StepSpell(step)
    if not (name and known) then return false end
    return DueWith(step, ctx, { valueAutorepeat = true }) == true
end

local function Choose(step)
    local spell, name = Rotation().StepSpell(step)
    return step, name, spell
end

-- Werte vorab lesen (außerhalb des Kampfes; Rotation.Prime): jeder Füller mit Zauber und der Zauberstab – so liegt im
-- Kampf, wenn Kosten, Zauberzeit und Stab gesperrt sind, die letzte offene Rechnung vor (Spieltest 23.11.2026: vorher
-- nur, wenn vor dem Kampf schon ein Füller vorn stand)
function Value.Prime(steps)
    if not Value.Enabled() or type(steps) ~= "table" then return end
    local R = Rotation()
    for _, step in ipairs(steps) do
        if R.KindOf(step) == "filler" and not step.side and not IsWand(step) then
            local spell, name, known = R.StepSpell(step)
            if spell and name and known then Core.SpellValue.Of(spell) end
        end
    end
    Core.SpellValue.Wand()
end

-- found: der bisherige Vorschlag (nil = keiner). → nil oder { step = Schritt | false (der Stab schießt schon: nichts
-- Neues), name, note = { pick, why, spell, spellName, wand, mana, source, reserve, gain, fire, finish, finishFrom },
-- counted }; finish nur, wenn der teure Füller vorn bleibt (Marke „Stab reicht“)
-- Warum zuletzt nicht abgewogen wurde (/ezk status; Spieltest 23.11.2026: keine Zeile „Werte abwägen“ – nie still,
-- Leitlinie 11): "off" | "notfiller" | "nocostly" | "other" | "wandstep" | "nowand" | "order" | nil (abgewogen)
local function Skip(reason)
    Value.skip = reason
    return nil
end

function Value.Weigh(found, ctx, steps)
    if not Value.Enabled() or type(steps) ~= "table" then return Skip("off") end
    local R = Rotation()
    if found and R.KindOf(found) ~= "filler" then return Skip("notfiller") end
    local wandStep, costly, costlyName, costlySpell
    for _, step in ipairs(steps) do
        if R.KindOf(step) == "filler" and not step.side then
            if IsWand(step) then
                wandStep = wandStep or step
            elseif not costly then
                local spell, name, known = R.StepSpell(step)
                if name and known then
                    local cost = CastCost(spell)     -- im Kampf gesperrt: die letzte offene Rechnung
                    if cost and cost > 0 and DueWith(step, ctx, { valueIgnoreUnusable = Value.WAND }) == true then
                        costly, costlyName, costlySpell = step, name, spell
                    end
                end
            end
        end
    end
    if not costly then return Skip("nocostly") end
    -- Nur ein Vorschlag, der ohnehin einer der beiden ist (oder leer), wird abgewogen
    if found and found ~= costly and found ~= wandStep then return Skip("other") end
    Value.skip = nil
    local usable, noPower = ns.SpellUsable(costlyName)
    local noMana = usable == false and noPower == true
    local reserve = Value.Reserve()
    local note = { spell = Core.SpellValue.Of(costlySpell), spellName = costlyName, reserve = reserve }
    local pick, counted
    if wandStep and WandReady(wandStep, ctx) then
        note.wand = Core.SpellValue.Wand()
        if noMana then
            -- Regel 3 vor den Werten: „zu wenig Mana“ entscheidet auch ohne Rechnung (etwa nach /reload im Kampf)
            pick, note.why = "wand", "nomana"
        elseif not (note.spell and note.wand) then
            note.why, note.missing = "unknown", note.wand and "spell" or "wand"
            return { step = found, name = found and ns.SpellName(found.id), note = note }
        else
            note.spell, note.fire = Value.UnderFire(note.spell, costlySpell)
            note.gain = note.spell.amount - note.wand.dps * note.spell.time
            if note.gain <= 0 then
                pick, note.why = "wand", "dps"
            else
                local mana, source = Value.ManaPercent(ctx)
                local max = ManaMax()
                note.mana, note.source = mana, source
                if mana and max then
                    local after = mana - (note.spell.cost or 0) / max * 100
                    if after >= reserve then pick, note.why = "spell", "mana" else pick, note.why = "wand", "reserve" end
                    counted = source == "counted"
                else
                    note.why = "unknown"
                    if found == costly then note.finish, note.finishFrom = Value.FinishShare(note.wand, note.spell) end
                    return { step = found, name = found and ns.SpellName(found.id), note = note }
                end
            end
        end
    elseif wandStep then
        return Skip("wandstep")     -- Stab-Schritt da, aber nicht fällig (ausgeschaltet, Bedingung): nichts abwägen
    else
        -- Regel 4: kein Stab in der Rotation – nur bei „zu wenig Mana“ für den Füller der Stab
        local wand = Core.SpellValue.Wand()
        if wand == nil or not WandReady(Value.WAND_STEP, ctx) then return Skip("nowand") end
        if not noMana then
            -- der Füller bleibt; steht er vorn, nur die Marke „Stab reicht“ (Ziel fast tot), sonst nichts Neues
            if found ~= costly or not note.spell then return Skip("order") end
            note.wand, note.why = wand, "order"
            note.spell, note.fire = Value.UnderFire(note.spell, costlySpell)
            note.finish, note.finishFrom = Value.FinishShare(wand, note.spell)
            if not note.finish then return Skip("order") end
            note.pick = "spell"
            local step, name = Choose(costly)
            return { step = step, name = name, note = note }
        end
        wandStep = Value.WAND_STEP
        pick, note.why, note.wand = "wand", "nomana", wand
    end
    note.pick = pick
    if pick == "spell" then
        note.finish, note.finishFrom = Value.FinishShare(note.wand, note.spell)
        local step, name = Choose(costly)
        return { step = step, name = name, note = note, counted = counted }
    end
    if State().Autorepeat() == true then
        -- schießt schon: nichts Neues; die Mitte zeigt den Stab mit der Zeile (note.shooting, Rotation.lua ShowNext)
        local _, wandName, wandSpell = Choose(wandStep)
        note.shooting = { spell = wandSpell, name = wandName }
        return { step = false, note = note, counted = counted }
    end
    local step, name = Choose(wandStep)
    return { step = step, name = name, note = note, counted = counted }
end

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------

local function PerSecond(value) return Core.Decimal(value, 1) end
local function Percent(value) return Core.Percent(value, 0) end

local function ManaText(note)
    local text = Percent(note.mana)
    if note.source == "counted" then text = text .. ", " .. L.ROTATION_STATE_COUNTED end
    return text
end

local function FireText(note)
    local fire, spell = note.fire, note.spell
    if not (fire and spell) then return "" end
    if not fire.channel then
        return L.ROTATION_VALUE_FIRE:format(Core.Seconds(spell.time, 1), Core.Seconds(fire.plain, 1))
    end
    return L.ROTATION_VALUE_FIRE_CHANNEL
end

function Value.Text(note)
    if type(note) ~= "table" or not note.why then return nil end
    local text = Value.BaseText(note)
    if text then text = text .. FireText(note) end
    return text
end

function Value.BaseText(note)
    local spell, wand = note.spell, note.wand
    local name = note.spellName or "?"
    if note.why == "dps" and spell and wand then
        return L.ROTATION_VALUE_DPS:format(PerSecond(wand.dps), name, PerSecond(spell.dps))
    elseif note.why == "mana" and note.gain and spell then
        return L.ROTATION_VALUE_MANA:format(name, PerSecond(note.gain / spell.time), ManaText(note))
    elseif note.why == "reserve" then
        return L.ROTATION_VALUE_RESERVE:format(ManaText(note), Percent(note.reserve))
    elseif note.why == "nomana" then
        return L.ROTATION_VALUE_NOMANA:format(name)
    elseif note.why == "unknown" and note.gain and spell then
        return L.ROTATION_VALUE_UNKNOWN:format(name, PerSecond(note.gain / spell.time))
    elseif note.why == "unknown" and note.missing then
        -- Werte fehlen: sagen, welche (Leitlinie 11 – nie still); die Reihenfolge der Rotation gilt
        return L["ROTATION_VALUE_MISSING_" .. note.missing]:format(name)
    end
    return nil
end

function Value.StatusText(note)
    if type(note) ~= "table" or not note.why then return nil end
    local parts = {}
    local spell, wand = note.spell, note.wand
    if spell then
        parts[#parts + 1] = L.STATUS_VALUE_SPELL:format(note.spellName or "?", Core.Decimal(spell.amount, 0),
            PerSecond(spell.dps), spell.dpm and Core.Decimal(spell.dpm, 2) or "–")
    end
    if wand then parts[#parts + 1] = L.STATUS_VALUE_WAND:format(PerSecond(wand.dps)) end
    if note.mana then parts[#parts + 1] = L.STATUS_VALUE_MANA:format(ManaText(note), Percent(note.reserve)) end
    if note.fire then
        parts[#parts + 1] = L.STATUS_VALUE_FIRE:format(Core.Decimal(note.fire.rate, 1), Core.Seconds(note.fire.pushback, 2),
            L["STATUS_VALUE_PUSH_" .. note.fire.source] or note.fire.source)
    end
    if note.finish then
        parts[#parts + 1] = L.STATUS_VALUE_FINISH:format(Percent(note.finish * 100),
            L["STATUS_VALUE_HEALTH_" .. tostring(note.finishFrom)] or tostring(note.finishFrom))
    end
    local text = Value.Text(note)
    return L.STATUS_VALUE:format(table.concat(parts, " · "), text or L["ROTATION_VALUE_WHY_" .. note.why] or note.why,
        Core.SpellValue.SourceText())
end

---------------------------------------------------------------------------
-- Ereignisse: offene Lesungen und eigene Würfe
---------------------------------------------------------------------------

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, _, spellID)
    if ns.IsSecret(unit) or unit ~= "player" then return end
    Value.OnCast(spellID)
end)
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function() Value.ReadOpen() end)
end
ns.OnUnit("UNIT_POWER_FREQUENT", "player", function(_, unit)
    if ns.IsSecret(unit) or unit == "player" then Value.ReadOpen() end
end)
-- Treffer auf dich (Art offen, Betrag gesperrt und ungelesen) und Verzögerung der eigenen Zauber
ns.OnUnit("UNIT_COMBAT", "player", function(_, unit, kind)
    if ns.IsSecret(unit) or unit ~= "player" then return end
    Value.OnHit(kind)
end)
ns.OnUnit("UNIT_SPELLCAST_START", "player", function(_, unit)
    if not ns.IsSecret(unit) and unit == "player" then Value.OnCastStart() end
end)
ns.OnUnit("UNIT_SPELLCAST_DELAYED", "player", function(_, unit)
    if not ns.IsSecret(unit) and unit == "player" then Value.OnCastDelayed() end
end)
-- Höchstleben des Ziels merken, solange es offen ist (vor dem Kampf; PLAYER_REGEN_DISABLED kommt vor der Sperre), und
-- die Deckkraft der Marke „Stab reicht“ der Kurve folgen lassen
ns.On("PLAYER_TARGET_CHANGED", function()
    Value.RememberTarget()
    -- der Anteil galt dem alten Ziel: bis zur nächsten Bewertung (gedrosselt) keine Marke
    finish.share = nil
    Value.ApplyFinish()
end)
ns.OnUnit("UNIT_MAXHEALTH", "target", function()
    Value.RememberTarget()
    Value.ApplyFinish()
end)
ns.OnUnit("UNIT_HEALTH", "target", function() Value.ApplyFinish() end)
ns.On("PLAYER_REGEN_DISABLED", function()
    combatStart = Core.Uptime()
    Value.RememberTarget()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    combatStart = nil
    hits = {}
end)
