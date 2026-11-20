local _, ns = ...
local L = ns.L
local Glow = ns.Glow
local Core = ezCore

-- Eigene Buffs laufen aus (Spieltest: „auslaufen einer Fähigkeit wird nicht angezeigt“, z. B. Dämonenhaut):
-- Kurz vor dem Ende leuchtet der Aktionsknopf, der den Buff neu wirkt, in der Farbe „Buff fehlt“ (ezCore.GLOW_KINDS,
-- Art "missing"); auf Wunsch steht sein Symbol am Symbolplatz in der Bildschirmmitte („Dämonenhaut läuft aus“,
-- Rang 2 nach einem auslaufenden DoT). Ist er ausgelaufen, leuchtet der Knopf weiter, bis der Buff wieder wirkt
-- (höchstens eine Minute).
-- Gemeldet werden nur Buffs, die du selbst auf dich gewirkt hast und deren Zauber auf einer Aktionsleiste liegt –
-- so meldet sich kein Proc (Freizauber, Schattentrance …). Liegt der Zauber noch in der Abklingzeit (Schildwall,
-- Sprint …), schweigt ezCombat: neu wirken geht dann nicht. Gerechnet wird nur mit offenen Werten aus
-- ezCore.Auras.Scan. Sind deine Auren gesperrt (im Kampf üblich), gilt für einen vorher offen gelesenen Buff die
-- zuletzt gelesene Ablaufzeit weiter, solange seine Instanz-ID noch auf dir liegt (die Instanz-IDs sperrt das Spiel
-- nie) – so warnt ezCombat auch im Kampf vor dem Ende der Dämonenhaut von vor dem Kampf. Fehlt die Instanz, ist der
-- Buff weg (kurz vor seinem Ende: ausgelaufen). Was im Kampf neu gewirkt wird, kennt ezCombat nicht (weder Name noch
-- Ablaufzeit): Dafür kommt keine Warnung, und /ezk status sagt es.
-- ezBuff meldet fehlende Buffs außerhalb des Kampfes an Blizzards Buff-Leiste; ezCombat warnt am Aktionsknopf,
-- auch im Kampf, in den letzten Sekunden. Ist ezBuff für einen Buff zuständig (Watches) und meldet ihn gerade selbst
-- (außerhalb des Kampfes), leuchtet dort ezBuffs „fehlt“ – ezCombat meldet denselben Knopf dann nicht zusätzlich an (CB-40, Vollprüfung V-105; Entscheidung 13.11.2026 „ezBuff ist die eine Stelle“). Im Kampf schweigt
-- ezBuff, dann warnt ezCombat allein; die Anzeige über dem Charakter bleibt ezCombats.
local Buffs = {}
ns.Buffs = Buffs

local MIN_DURATION = 5      -- Sekunden: kürzere Auren sind Procs, nichts zum Erneuern
local GONE_HOLD = 60        -- Sekunden: so lange leuchtet ein ausgelaufener Buff nach
local NATURAL_END = 0.5     -- Sekunden: verschwindet ein Buff so kurz vor seinem Ende, ist er ausgelaufen
local SHORT_SHARE = 0.3     -- kurze Buffs: frühestens ab diesem Anteil Restdauer warnen
local TICK = 0.25

local tracked = {}          -- [Name] = Aura (Felder wie ezCore.Auras.Scan), zuletzt offen gesehen; stale = gesperrt
                            -- und unbekannt (keine Warnung); recast = seit dem letzten offenen Lesen neu gewirkt
local gone = {}             -- [Name] = { at, icon, expires } von selbst ausgelaufen
local announced = {}        -- [Name] = Ablaufzeit, für die das Symbol schon aufgesprungen ist
local demoUntil = 0

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

-- Ab welcher Restzeit warnen: Einstellung plus Zauberzeit (neu wirken dauert so lange), bei kurzen Buffs
-- (Zerhäckseln, Erneuerung auf dir) frühestens ab 30 % Restdauer – sonst leuchtete es fast ständig.
function Buffs.WarnAt(aura)
    local warn = ns.S.buffWarn + ns.CastTime(aura.spellId or aura.name)
    local cap = aura.duration and aura.duration * SHORT_SHARE
    if cap and cap < warn then return cap end
    return warn
end

-- Zauber auf allen Aktionsleisten (auch verborgenen): { [Name] = true }
function Buffs.BarSpells()
    local names = {}
    for _, button in ipairs(Glow.Buttons()) do
        local name = Glow.SpellOf(button)
        if name then names[name] = true end
    end
    return names
end

-- Gesperrt gelesen: Was weiß ezCombat noch über einen vorher offen gelesenen Buff?
--   "kept"    – seine Instanz-ID liegt noch: Die zuletzt offen gelesene Ablaufzeit gilt weiter.
--   "gone"    – seine Instanz-ID fehlt: Der Buff ist weg (wie offen gelesen).
--   "unknown" – keine Instanz-IDs vom Spiel, keine gemerkte Instanz, oder der Buff wurde seit dem letzten offenen
--               Lesen neu gewirkt (die neue Ablaufzeit kennt ezCombat nicht – nie raten): keine Warnung.
local function LockedState(old, present)
    if not (present and old.instance) then return "unknown" end
    if not present[old.instance] then return "gone" end
    if old.recast then return "unknown" end
    return "kept"
end

-- Eigene Buffs neu lesen. Rückgabe: Anzahl gesperrter Auren.
function Buffs.Scan()
    local now = GetTime()
    -- Ganz gesperrte Auren zählt ezCore über die nie gesperrten Instanz-IDs mit (seit ezCore 1.8.0).
    local auras, secret, ids, unread = Core.Auras.Scan("player", "HELPFUL|PLAYER")
    if secret > 0 then ns.NoteSecret("buffs") end
    -- Unlesbar (Instanz-ID da, keine Daten) zählt wie gesperrt: „nicht in der Liste“ heißt dann nicht „liegt nicht“.
    local locked = secret > 0 or (ns.Num(unread) or 0) > 0
    local present           -- [Instanz-ID] = true; nil, wenn das Spiel keine Instanz-IDs nennt
    if type(ids) == "table" and #ids > 0 then
        present = {}
        for _, id in ipairs(ids) do present[id] = true end
    end
    local seen = {}
    for _, aura in ipairs(auras) do
        if aura.name and aura.expires and aura.duration and aura.duration >= MIN_DURATION then
            seen[aura.name] = aura
        end
    end
    for name, old in pairs(tracked) do
        if not seen[name] then
            local state = locked and LockedState(old, present) or "gone"
            if state == "unknown" then
                -- Gesperrt: Der Buff kann noch da sein (nur unlesbar) – nicht als ausgelaufen werten, nicht warnen.
                old.stale = true
            elseif state == "kept" then
                -- Gesperrt, aber dieselbe Instanz liegt noch: Die offen gelesene Ablaufzeit gilt weiter.
                old.stale = nil
            else
                if old.expires - now <= NATURAL_END then
                    gone[name] = { at = now, icon = old.icon, expires = old.expires }
                end
                tracked[name] = nil
            end
        end
    end
    for name, aura in pairs(seen) do
        tracked[name] = aura
        gone[name] = nil
    end
    return secret
end

---------------------------------------------------------------------------
-- Warnen
---------------------------------------------------------------------------

-- Erste Warnung je Ablauf merken (/ezk status); ausgelaufen springt das Symbol einmal kurz auf, falls vorher
-- keine Warnung kam.
local function Announce(name, icon, expires, gone)
    if announced[name] == expires then return end
    announced[name] = expires
    Buffs.last = { when = GetTime(), name = name }
    if gone and ns.ShowAt("expiring", "center") then
        ns.Symbol.Pop("buff", icon, L.PULSE_BUFF_GONE:format(name), "missing", nil, nil, { name = name })
    end
end

-- Für welche dieser Buffs ist ezBuff gerade zuständig? { [Name] = true }. Zuständig heißt: ezBuff kümmert sich um die
-- Gruppe des Buffs (ezCore.API("ezBuff").Watches mit dem Buff-Schlüssel aus ezCore.Spells.BuffKey) und meldet ihn
-- gerade selbst beim Leucht-Dienst als „fehlt“ (Grund ezBuff/missing in Core.Glow.List). Das tut ezBuff außerhalb des
-- Kampfes, sobald der Buff fehlt oder unter „Restzeit unter“ fällt (ab Werk 2 Minuten – früher als ezCombats
-- Warnzeit); im Kampf, mit ezBuffs Schalter „Knopf leuchtet“ aus oder bevor ezBuff neu geprüft hat, meldet ezBuff ihn
-- nicht – dann bleibt ezCombats Leuchten. Gelesen wird defensiv (pcall, nur true zählt); ohne ezBuff: leer.
function Buffs.HandledByEzBuff(names)
    local handled = {}
    local api = Core.API and Core.API("ezBuff")
    if type(api) ~= "table" or type(api.Watches) ~= "function" then return handled end
    local claimed
    for _, reason in ipairs(Core.Glow.List()) do
        if reason.owner == "ezBuff" and reason.kind == "missing" then
            for _, name in ipairs(reason.names or {}) do
                claimed = claimed or {}
                claimed[name] = true
            end
        end
    end
    if not claimed then return handled end
    for name in pairs(names or {}) do
        local key = claimed[name] and Core.Spells.BuffKey(name)
        if key then
            local ok, watches = pcall(api.Watches, key)
            if ok and watches == true then handled[name] = true end
        end
    end
    return handled
end

local symbolSet = false     -- steht gerade ein dauerhafter Eintrag „buff“ am Symbolplatz?
local symbolName            -- Name des Buffs, der dort als „läuft aus“ steht

-- Name des Buffs, den „Eigene Buffs“ gerade am Symbolplatz als auslaufend zeigt, sonst nil. Die Rotation meldet
-- denselben Buff dann nicht noch einmal unter „Vor dem Kampf“ (eine Meldung je Buff).
function Buffs.Showing()
    return symbolSet and symbolName or nil
end

-- Welche Knöpfe leuchten, was am Symbolplatz steht; Rückgabe true, solange es etwas zu beobachten gibt.
function Buffs.Check()
    local now = GetTime()
    local names = {}
    local first             -- der zuerst auslaufende Buff für den Symbolplatz
    for name, info in pairs(gone) do
        if now - info.at > GONE_HOLD then gone[name] = nil end
    end
    if ns.Enabled("buffs") then
        -- Erst die Kandidaten (Restzeit unter der Warnzeit), nur dann die Aktionsleisten durchsehen.
        local expiring = {}
        for name, aura in pairs(tracked) do
            local left = aura.expires - now
            if not aura.stale and left > 0 and left <= Buffs.WarnAt(aura) then expiring[name] = aura end
        end
        if next(expiring) or next(gone) then
            local bar = Buffs.BarSpells()
            for name, aura in pairs(expiring) do
                if bar[name] and not ns.OnCooldown(name) then
                    names[name] = true
                    Announce(name, aura.icon, aura.expires, false)
                    if not first or aura.expires < first.expires then first = aura end
                end
            end
            for name, info in pairs(gone) do
                if bar[name] and not ns.OnCooldown(name) then
                    names[name] = true
                    Announce(name, info.icon, info.expires, true)
                end
            end
        end
    end
    -- Leuchten am Knopf nur, wenn „läuft aus“ dort erscheinen soll (CB-N1); die Vorschau leuchtet immer.
    if not ns.ShowAt("expiring", "glow") then names = {} end
    -- Was ezBuff gerade selbst als „fehlt“ meldet, nicht noch einmal (CB-40).
    if next(names) then
        for name in pairs(Buffs.HandledByEzBuff(names)) do names[name] = nil end
    end
    if ns.Previewing(demoUntil) and Buffs.demo then names[Buffs.demo] = true end
    Glow.SetSpells("missing", names)
    -- Anzeige über dem Charakter, linker Platz (Rang 2, nach „DoT läuft aus“): der zuerst auslaufende Buff, solange
    -- er ausläuft, mit Restzeit (zuletzt offen gelesene Ablaufzeit).
    if first and ns.ShowAt("expiring", "center") then
        local timer = (ns.Num(first.expires) and ns.Num(first.duration))
            and { start = first.expires - first.duration, duration = first.duration } or nil
        local spell = ns.Plain(first.spellId) or ns.Plain(first.name)     -- für „noch nicht bereit“ (Symbol.lua)
        ns.Symbol.Set("buff", first.icon, L.PULSE_BUFF:format(first.name), "missing", timer, spell,
            { name = first.name })
        symbolSet, symbolName = true, first.name
    elseif symbolSet then
        symbolSet, symbolName = false, nil
        local entry = ns.Symbol.Entry("buff")
        if entry and not entry.untilTime then ns.Symbol.Clear("buff") end
    end
    return next(tracked) ~= nil or next(gone) ~= nil
end

function Buffs.Update()
    Buffs.Scan()
    Buffs.Check()
end

-- Eigener Zauber: Er hat den gleichnamigen Buff neu gewirkt. Ein „ausgelaufen“ ist damit erledigt; ein
-- beobachteter Buff hat eine neue Ablaufzeit, die erst das nächste offene Lesen zeigt (bis dahin: recast).
function Buffs.OnOwnCast(name)
    if type(name) ~= "string" then return end
    gone[name] = nil
    if tracked[name] then tracked[name].recast = true end
end

-- Für die Tests: was gerade beobachtet wird.
function Buffs.Tracked() return tracked end
function Buffs.Gone() return gone end

local updateSoon = ns.Throttle(function() ns.Try("Buffs", Buffs.Update) end, 0.05)

-- Im Kampf kommt UNIT_AURA mit gesperrten Werten, auch die Einheit (Forever-Quelle: SecretWhenAurasRestricted) –
-- ein Vergleich damit ist nicht erlaubt. Der Zuhörer hört deshalb nur auf den Spieler (ns.OnUnit: Blizzard weckt
-- ihn nur dafür) und nimmt eine gesperrte Einheit als den Spieler.
ns.OnUnit("UNIT_AURA", "player", function(_, unit)
    if ns.IsSecret(unit) or unit == "player" then updateSoon() end
end)
ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, _, spellID)
    if not (ns.IsSecret(unit) or unit == "player") then return end
    -- Name aus der Zauber-ID, gesperrt vom zuletzt gedrückten Aktionsknopf (Auras.CastInfo)
    Buffs.OnOwnCast((ns.Auras.CastInfo(spellID)))
    updateSoon()
end)
-- Kampfende, Addon-Sperre des Spiels geändert: Die Sperre fällt, ohne dass sich eine Aura ändert – neu lesen, damit
-- „gesperrt“ nicht stehen bleibt (fällt sie erst nach dem Kampfende, meldet es ezCore: Core.OnRestrictionChanged,
-- CB-22).
ns.On("PLAYER_REGEN_ENABLED", updateSoon)
ns.OnRestrictionChanged(updateSoon)
ns.On("PLAYER_ENTERING_WORLD", updateSoon)
ns.On("ACTIONBAR_SLOT_CHANGED", updateSoon)
ns.OnReady(updateSoon)
ns.OnSettingChanged(function(key)
    if key == "buffs" or key == "buffWarn" or key == "showExpiring" then updateSoon() end
end)

-- Restzeiten laufen ohne Ereignis ab: ein leiser Takt, nur solange ein Buff beobachtet wird. Takt mit Griff, der ganze
-- Rückruf in ezCombats Fehlerliste (ezCores Ticker-Helfer, Gesamtreview 18.11.2026, T7-3); er entsteht erst in OnReady
-- (ein älteres ezCore ohne ns.Ticker meldet dann nur „zu alt“, Gegenprüfung P19c). Er läuft auch bei ausgeschalteter
-- Warnung weiter: Buffs.Check räumt dann Leuchten, Symbolplatz und Vorschau ab (docs/roadmap/ezCombat.md, „Offen“).
ns.OnReady(function()
    Buffs.ticker = ns.Ticker(TICK, function()
        if next(tracked) or next(gone) then Buffs.Check() end
    end, nil, "Buffs")
end)

-- /ezk status: gesperrte Auren und die letzte Warnung.
ns.AddStatusLine(function()
    if ns.secretSeen.buffs then return L.STATUS_BUFFS_SECRET end
end)
ns.AddStatusLine(function()
    if not ns.Enabled("buffs") then return L.STATUS_BUFFS_OFF:format(ns.PathText("OPT_HEADER_BUFFS", "OPT_buffs")) end
    if Buffs.last then
        return L.STATUS_BUFFS_LAST:format(Buffs.last.name,
            L.STATUS_AGO:format(Core.Duration(GetTime() - Buffs.last.when, true)))
    end
    return L.STATUS_BUFFS_NONE
end)

-- Vorschau: ein Knopf mit Zauber leuchtet in der Farbe „Buff fehlt“, danach springt sein Symbol auf.
ns.AddPreview("buffs", 35, function()
    local chosen
    for _, button in ipairs(Glow.Buttons()) do
        if button:IsVisible() and Core.ActionSlots.Has(button.action) then chosen = button end
    end
    local name = chosen and Glow.SpellOf(chosen)
    if name then
        Buffs.demo = name
        demoUntil = GetTime() + 3
        Buffs.Check()
        C_Timer.After(3.1, function() Buffs.demo = nil; Buffs.Check() end)
    end
    local texture = chosen and Core.ActionSlots.Texture(chosen.action)
    ns.Symbol.Pop("buff", texture, L.PULSE_BUFF:format(name or L.PULSE_BUFF_EXAMPLE), "missing", 3, nil,
        { name = name or L.PULSE_BUFF_EXAMPLE })
    return true
end)
