local _, ns = ...
local Core = ezCore
local Spells = ezCore.Spells

-- Ist die angezeigte Fähigkeit gerade wirkbar? (Wunsch des Nutzers vom 15.11.2026 abends: „wenn das mittige symbol
-- auftaucht aber genau diese fähigkeit noch ne bereit ist muss man das auch sehen“). Die Anzeige über dem Charakter
-- (Symbol.lua) fragt hier je Eintrag mit Zauber nach und zeichnet es wie Blizzards Aktionsknopf
-- (Gethe/wow-ui-source, Zweig forever, Blizzard_ActionBar/Shared/ActionButton.lua): Abklingzeit als Spirale, zu wenig
-- Kraft blau getönt (0.5, 0.5, 1), sonst nicht nutzbar grau (0.4), außer Reichweite rot.
--
-- Was im Kampf auf Forever lesbar ist (Daten-Probe des Nutzers vom 15.11.2026, Sitzungen 4 und 5, Paladin, Station G):
--   • C_Spell.GetSpellCooldown: startTime, duration, modRate und timeUntilEndOfStartRecovery gesperrt, isActive und
--     isEnabled offen; isOnGCD fehlte in der Antwort (Richturteil 20271 mit laufender Abklingzeit). Ob nur die
--     globale Abklingzeit läuft, sagt dann zuerst das Dauer-Objekt ohne globale Abklingzeit
--     (C_Spell.GetSpellCooldownDuration(…, true):IsZero(), nur wenn die Antwort offen ist), sonst der Vergleich mit
--     der globalen Abklingzeit (ezCore.Spells.GCDActive). Bleibt es offen: Spirale ja, „wartet“ nein.
--   • C_Spell.IsSpellUsable: beide Werte offen (auch im Kampf) – „zu wenig Kraft“ kommt von dort, UnitPower ist im
--     Kampf gesperrt und wird nie gelesen.
--   • C_Spell.IsSpellInRange: in der Probe ohne Ziel mit Reichweite nur nil; laut Forever-Quelle nie gesperrt
--     (ezCore.Spells.InRange). Eine gesperrte oder fehlende Antwort heißt „unbekannt“ – dann wird nichts behauptet.
-- Gesperrte Restzeiten werden nie gelesen oder verglichen: Blizzards Dauer-Objekt geht unverändert an die Spirale
-- (SetCooldownFromDurationObject, wie bei gesperrten DoTs). Dauer-Objekt und „echt oder global?“ kommen seit Welle 23
-- aus ezCore (Spells.DurationObject, Spells.LockedKind); hier bleibt nur, was die Anzeige daraus zeichnet.
local Readiness = {}
ns.Readiness = Readiness

-- Blizzards Tönung des Symbols (ActionBarActionButtonMixin:UpdateUsable; Reichweite: RED_FONT_COLOR, das Blizzard an
-- der Tastenbelegung zeigt – das Symbol der Anzeige hat keine, also färbt es das Symbol).
Readiness.TINT = {
    ready = { 1, 1, 1 },
    power = { 0.5, 0.5, 1 },
    unusable = { 0.4, 0.4, 0.4 },
    range = { 1, 0.125, 0.125 },
}

-- Blizzards Dauer-Objekt der Abklingzeit (ignoreGCD: ohne die globale) und „echte Abklingzeit oder nur die globale?“
-- bei gesperrten Werten: seit Welle 23 (A1) in ezCore (Spells.DurationObject, Spells.LockedKind – dort sagt damit auch
-- Spells.OnCooldown im Kampf wieder ja/nein). Die Namen hier bleiben als Weiterleitung (Leitlinie 8).
Readiness.DurationObject = Spells.DurationObject
Readiness.LockedKind = Spells.LockedKind

-- Abklingzeit eines Zaubers: nil (unbekannt) oder { kind = "none" | "gcd" | "real" | nil, timer = { start,
-- duration } (offen), wait = Sekunden bis bereit (offen, nur "real"), locked = true (gesperrt), durationObject
-- (gesperrt: Blizzards Objekt für die Spirale, nur weitergereicht), shared = Name (gesperrt und sonst unbekannt: ein
-- Zauber derselben Kategorie laut Client-Tabellen klingt ab – ns.SharedOnCooldown, Welle 26) }. Offene Werte enthalten
-- die geteilte Abklingzeit schon (das Spiel legt sie auf jeden Zauber der Kategorie).
-- Gelesen wird seit dem Paket ezcombat/rotation-recherche (20.11.2026) über ezCores Spells.ReadCooldown (SSOT: die eine
-- Stelle für C_Spell.GetSpellCooldown, dieselbe Regel wie vorher hier).
function Readiness.Cooldown(spell)
    if Core.IsSecret(spell) or spell == nil then return nil end
    local kind, start, duration, locked, info = Spells.ReadCooldown(spell)
    if not info then return nil end
    if not locked then
        if kind == "none" then return { kind = "none" } end
        local state = { kind = kind, timer = { start = start, duration = duration } }
        if kind == "real" then state.wait = math.max(0, start + duration - GetTime()) end
        return state
    end
    -- Gesperrt: nur die nie gesperrten Felder, die Restzeit bleibt bei Blizzard.
    if ns.NoteSecret then ns.NoteSecret("cooldown") end
    if kind == "none" then return { kind = "none", locked = true } end
    local shared
    if kind == nil then
        local running, by = ns.SharedOnCooldown(spell)
        if running == true then kind, shared = "real", by end
    end
    local active = kind ~= nil or Core.Plain(Core.Peek(info, "isActive")) == true
    local state = { kind = kind, locked = true, shared = shared }
    if active then state.durationObject = Spells.DurationObject(spell, kind == "real") end
    return state
end

-- Kraft und Nutzbarkeit: "power" (nur die Kraft fehlt), "unusable" (aus anderem Grund nicht nutzbar), "ok" oder nil
-- (unbekannt: keine Abfrage, gesperrte Antwort, Fehler im Aufruf). Die Abfrage selbst macht ezCore (Spells.Usable,
-- SSOT; ein Fehler im pcall kommt dort seit Welle 23 als dritter Wert „unbekannt“), „keine Abfrage heißt unbekannt“
-- ebenso (Spells.UsableState).
-- Seit dem Paket ezcombat/rotation-recherche (20.11.2026) steht die Regel in ezCore (Spells.UsableState, SSOT); der
-- Name hier bleibt als Weiterleitung (Leitlinie 8).
function Readiness.Usable(spell)
    return Spells.UsableState(spell)
end

-- Alles zusammen für die Anzeige: { cooldown = Readiness.Cooldown, usable = Readiness.Usable, inRange = true/false/nil }.
function Readiness.State(spell)
    if Core.IsSecret(spell) or spell == nil then return nil end
    return {
        cooldown = Readiness.Cooldown(spell),
        usable = Readiness.Usable(spell),
        inRange = Spells.InRange(spell, "target"),
    }
end

-- Bereit oder fast bereit? (Spieltest des Nutzers vom 20.11.2026, wörtlich „der goldene rahmen sollte auch erst dann
-- erscheinen taskleiste und symbol mitte wenn der zauber bereit ist oder fast bereit ist“). Das Leuchten am Knopf der
-- Leiste und um das Symbol „Als Nächstes“ in der Mitte folgt dieser Antwort (beide aus derselben Rechnung:
-- Rotation.lua ShowNext gibt sie samt gezählter Restzeit an das Symbol weiter); das Symbol selbst bleibt stehen und
-- sagt mit Tönung und Text, worauf es wartet. Die anderen Plätze („wieder bereit“, „läuft aus“) leuchten wie bisher.
--   false: Blizzard meldet „zu wenig Kraft“ oder „nicht nutzbar“ (C_Spell.IsSpellUsable, im Kampf offen), oder eine
--          echte Abklingzeit läuft länger als Readiness.ALMOST. Die Restzeit ist offen gelesen (cd.wait) oder von der
--          Rotation gezählt (left: Vorwarnung vorn); im Kampf ist sie auf Forever meist gesperrt – ohne gezählte
--          Restzeit gilt eine laufende echte Abklingzeit dann als nicht bereit, bis sie vorbei ist.
--   true:  sonst – auch während der globalen Abklingzeit, bei einer Abklingzeit, die in höchstens ALMOST endet, und bei
--          gesperrter Antwort zur Nutzbarkeit (dann wird nichts behauptet, die Anzeige leuchtet wie bisher).
--   nil:   kein Zauber oder der Zauber selbst ist gesperrt.
-- Kraft, die gleich reicht, ist nicht zu erkennen: Energie, Wut und Mana sind im Kampf gesperrt (Daten-Probe oben);
-- „fast bereit“ gibt es deshalb nur für Abklingzeiten. Reichweite zählt nicht: sie ist keine Eigenschaft des Zaubers.
Readiness.ALMOST = 1.5   -- Sekunden: etwa eine globale Abklingzeit
function Readiness.Ready(spell, state, left)
    if state == nil then state = Readiness.State(spell) end
    if not state then return nil end
    if state.usable == "power" or state.usable == "unusable" then return false end
    local cd = state.cooldown
    if cd and cd.kind == "real" then
        local wait = cd.wait
        if wait == nil and type(left) == "number" and not Core.IsSecret(left) then wait = left end
        if wait then return wait <= Readiness.ALMOST end
        return false
    end
    return true
end

-- Name der eigenen Kraft („Mana“, „Wut“, „Energie“) aus Blizzards Texten; nil, wenn das Spiel sie nicht nennt.
local POWER_TOKEN = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" }
function Readiness.PowerName()
    local fn = rawget(_G, "UnitPowerType")
    if type(fn) ~= "function" then return nil end
    local ok, kind, token = pcall(fn, "player")
    if not ok then return nil end
    token, kind = Core.Plain(token), Core.Plain(kind)
    if type(token) ~= "string" then token = type(kind) == "number" and POWER_TOKEN[kind] or nil end
    local name = token and rawget(_G, token)
    if type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name end
    return nil
end
