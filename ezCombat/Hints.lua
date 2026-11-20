local _, ns = ...
local L = ns.L
local Glow = ns.Glow

-- Hinweise am Aktionsknopf (Blizzards Proc-Leuchten):
--   reaktiv      Überwältigen nach Ausweichen, Rache nach Blocken, Riposte und Gegenangriff nach Parieren,
--                Mungobiss, Hinrichten und Hammer des Zorns unter 20 % Leben
--   unterbrechen das Ziel wirkt etwas, das sich laut Spiel offen unterbrechen lässt, und die Fähigkeit ist bereit
--   Finisher     volle Combo-Punkte
-- Grundlage ist C_Spell.IsSpellUsable: Das Spiel gibt die Antwort nie geheim zurück und kennt die Bedingungen
-- (Ausweichen, Parieren, Lebensgrenze) selbst. Fehlt nur Wut oder Energie, leuchtet der Knopf trotzdem:
-- Blizzard färbt ihn dann blau, die Gelegenheit ist aber da.
--
-- Gesperrte Werte (Spieltest 14.11.2026, Vollprüfung W-03):
--   • Leben: WoW Forever gibt UnitHealth Addons nie heraus – auch nicht außerhalb des Kampfes. TargetHealthFraction
--     liefert dort also immer nil, die eigene 20-%-Nachprüfung für Hinrichten und Hammer des Zorns läuft nie, und es
--     gilt allein die Prüfung des Spiels (SpellUsable). Das ist Dauerzustand und so gewollt, keine Störung:
--     ns.NoteSecret("health") wird zwar bei jedem Durchlauf gesetzt, /ezk status führt es aber als eigene ruhige
--     Zeile und nicht unter „Zuletzt gesperrte Daten“ (ns.SECRET_NORMAL in Core.lua). Die Nachprüfung bleibt für
--     Clients, die das Leben offen liefern.
--   • Combo-Punkte: gesperrt heißt unbekannt (nil) – nie 0 Punkte oder höchstens 5. Der Finisher-Hinweis und die
--     Combo-Leiste ruhen dann; ns.NoteSecret("combo"), eine Zeile in /ezk status und die Tooltips der Schalter
--     sagen es. Gelesen (und vermerkt) wird nur, wo eine Hilfe die Punkte braucht: Klassen ohne Finisher und
--     abgeschaltete Hilfen fragen nicht – bei ihnen ruht nichts, also meldet /ezk status auch nichts.
local Hints = {}
ns.Hints = Hints

local TICK = 0.2    -- im Kampf: so oft nachsehen (Fenster wie „nach Ausweichen“ enden ohne eigenes Ereignis)

-- Ziel gesperrt (UnitExists geheim) zählt als „nein“ – kein Hinweis auf Verdacht (ns.UnitPresent).
local function TargetAttackable()
    return ns.UnitPresent("target") == true and ns.Bool(UnitCanAttack("player", "target"), true)
        and not ns.Bool(UnitIsDead("target"), false)
end

-- Lebensanteil des Ziels, nil wenn geheim oder unbekannt. Zuerst prüfen, ob gesperrt (Leitlinie 6; Durchsicht A71,
-- Welle 23): Nur ein wirklich gesperrter Wert wird als „health“ vermerkt – ein fehlender (kein Ziel, nil) ist kein
-- gesperrter und landet nicht still im selben Zweig.
local function TargetHealthFraction()
    local rawHealth, rawMax = UnitHealth("target"), UnitHealthMax("target")
    if ns.IsSecret(rawHealth) or ns.IsSecret(rawMax) then
        ns.NoteSecret("health")
        return nil
    end
    local health, maxHealth = ns.Num(rawHealth), ns.Num(rawMax)
    if not (health and maxHealth) or maxHealth <= 0 then return nil end
    return health / maxHealth
end
Hints.TargetHealthFraction = TargetHealthFraction

function Hints.Reactive()
    local result = {}
    if not ns.Enabled("reactive") or not TargetAttackable() then return result end
    local fraction
    for name, id in pairs(ns.ClassSpellNames("reactive")) do
        local usable, noPower = ns.SpellUsable(name)
        local ok = usable or noPower
        if ok and ezCore.Spells.IsExecute(id) then
            -- Das Spiel prüft die 20 % selbst; falls nicht, und das Leben ist lesbar, hier nachprüfen.
            fraction = fraction or TargetHealthFraction() or false
            if fraction and fraction > ezCore.Spells.EXECUTE_HEALTH then ok = false end
        end
        if ok and ns.OnCooldown(name) then ok = false end
        if ok then result[name] = true end
    end
    return result
end

-- Wirkt das Ziel gerade etwas Unterbrechbares? Nur, wenn das Spiel die Unterbrechbarkeit offen nennt. Ist sie geheim,
-- gilt sie als unbekannt und der Knopf leuchtet nicht – Blizzards Zauberleiste am Zielfenster zeigt den Schild selbst
-- (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 2: vorher zählte ein gesperrter Wert als unterbrechbar, eine
-- Handlungsempfehlung aus verborgenem Kampfzustand).
function Hints.TargetCastInterruptible()
    if not TargetAttackable() then return false end
    -- Auch der Name kann geheim sein; geheim heißt hier „es wird etwas gewirkt“.
    local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target")
    local casting = ns.IsSecret(name) or name ~= nil
    if not casting then
        name, _, _, _, _, _, notInterruptible = UnitChannelInfo("target")
        casting = ns.IsSecret(name) or name ~= nil
    end
    if not casting then return false end
    if ns.IsSecret(notInterruptible) then
        ns.NoteSecret("interrupt")
        return false
    end
    -- nur ein offenes „nein, nicht geschützt“ (false) zählt; nil (nicht gemeldet) ist unbekannt wie ein gesperrter
    -- Wert (Fund 4 des code-reviewers vor dem Merge, 17.11.2026)
    return notInterruptible == false
end

function Hints.Interrupt()
    local result = {}
    if not ns.Enabled("interrupt") or not Hints.TargetCastInterruptible() then return result end
    for name in pairs(ns.ClassSpellNames("interrupt")) do
        local usable, noPower = ns.SpellUsable(name)
        if (usable or noPower) and not ns.OnCooldown(name) then result[name] = true end
    end
    return result
end

-- Combo-Punkte und ihr Höchstwert → Punkte, Höchstwert. Gesperrt = unbekannt: der betroffene Wert ist nil (nie
-- still 0 bzw. 5, Leitlinie 6) und "combo" wird vermerkt. Fehlt die Abfrage ganz (alter Client): 0 Punkte, höchstens 5.
function Hints.ComboPoints()
    local points, maxPoints, locked = 0, 5, false
    if GetComboPoints then
        local raw = GetComboPoints("player", "target")
        if ns.IsSecret(raw) then
            points, locked = nil, true
        else
            points = ns.Num(raw) or 0
        end
    end
    if UnitPowerMax and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        local raw = UnitPowerMax("player", Enum.PowerType.ComboPoints)
        if ns.IsSecret(raw) then
            maxPoints, locked = nil, true
        else
            maxPoints = ns.Num(raw) or 5
            if maxPoints <= 0 then maxPoints = 5 end
        end
    end
    if locked then ns.NoteSecret("combo") end
    return points, maxPoints
end

function Hints.Finisher()
    local result = {}
    if not ns.Enabled("finisher") or not TargetAttackable() then return result end
    -- Nur Klassen mit Finishern lesen die Punkte: Ein gesperrter Wert würde sonst als Störung vermerkt
    -- (ns.NoteSecret("combo")), obwohl bei einem Krieger oder Magier kein Hinweis ruht.
    local names = ns.ClassSpellNames("finisher")
    if next(names) == nil then return result end
    local points, maxPoints = Hints.ComboPoints()
    -- Unbekannt (gesperrt): kein Hinweis auf Verdacht.
    if not (points and maxPoints) or points < maxPoints then return result end
    for name in pairs(names) do result[name] = true end
    return result
end

function Hints.Update()
    Glow.SetSpells("reactive", Hints.Reactive())
    Glow.SetSpells("interrupt", Hints.Interrupt())
    Glow.SetSpells("finisher", Hints.Finisher())
end

local updateSoon = ns.Throttle(Hints.Update, 0.05)

-- Ereignisse ohne Einheit: jedes zählt (gedrosselt).
for _, event in ipairs({ "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN",
    "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, updateSoon)
end
-- Einheiten-Ereignisse nur für Spieler und Ziel (ns.OnUnit: Blizzard weckt den Zuhörer nur für sie – vorher lief er
-- für jede Plakette und jedes Gruppenmitglied, T8-1). Der Filter liegt bei ezCore; eine gesperrte Einheit zählt dort
-- als Treffer, hier wird sie nie verglichen (T3-1, Leitlinie 6).
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_HEALTH", "UNIT_POWER_FREQUENT" }) do
    ns.OnUnit(event, { "player", "target" }, updateSoon)
end

local ticker
local function StartTicker()
    if ticker or not C_Timer.NewTicker then return end
    ticker = C_Timer.NewTicker(TICK, function() ns.Try("Hints", Hints.Update) end)
end
local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    updateSoon()
end
ns.On("PLAYER_REGEN_DISABLED", StartTicker)
ns.On("PLAYER_REGEN_ENABLED", StopTicker)

ns.OnSettingChanged(function(key)
    if key == "reactive" or key == "interrupt" or key == "finisher" then updateSoon() end
end)
ns.OnReady(updateSoon)

-- /ezk status: nur, wenn die Combo-Punkte wirklich gesperrt gesehen wurden – sagt, was deshalb ruht.
ns.AddStatusLine(function()
    if not ns.secretSeen.combo then return nil end
    return L.STATUS_COMBO_LOCKED
end)

-- Vorschau: die Knöpfe der eigenen reaktiven Fähigkeiten, Unterbrecher und Finisher leuchten 3 Sekunden.
ns.AddPreview("hints", 20, function()
    local names = {}
    for _, kind in ipairs({ "reactive", "interrupt", "finisher" }) do
        for name in pairs(ns.ClassSpellNames(kind)) do names[name] = true end
    end
    local buttons = Glow.ButtonsFor(names)
    for _, button in ipairs(buttons) do Glow.Flash(button, 3) end
    return #buttons > 0
end)
