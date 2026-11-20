local _, ns = ...
local L = ns.L
local Core = ezCore

-- Automatische Emotes (standardmäßig aus):
--   * fremden Spielern danken, die dich heilen
--   * dem Spieler hinterherspucken, der dich getötet hat
--
-- Erkennung – nie über das Kampflog (Leitlinie 6 „Kampflog ist zu“, Blizzards Regeln für Addons; Prüfung vom
-- 17.11.2026, V2: der Kampflog-Zweig ist entfernt, ezMacro meldet COMBAT_LOG_EVENT_UNFILTERED nicht mehr an):
--   Heiler: Heilvorhersage des Clients: UnitGetIncomingHeals("player", Einheit) für Ziel, Fokus, Mouseover und
--           Namensplaketten, bestätigt durch UNIT_SPELLCAST_SUCCEEDED. Sofortheilungen, HoTs und Heiler ohne
--           Einheit (keine Plakette) bleiben unerkannt.
--           WoW Forever sperrt die Heilvorhersage (der Wert ist immer geheim, Vollprüfung 14.11.2026 W-03):
--           Liefert der Client einen gesperrten Wert, schaltet ezMacro den Weg ab – Ereignisse abgemeldet, Stand
--           „Heilvorhersage: gesperrt“ (Auto.PredictionState), ein Hinweis im Chat. ezMacro erkennt fremde Heiler
--           dann gar nicht; der Schalter „Fremden Heilern danken“ sagt das in seinem Tooltip.
--   Mörder: Todesrückblick (C_DeathRecap: Quelle des tödlichen Treffers) – nur wenn diese Quelle kurz vorher als
--           feindlicher Spieler gesehen wurde (Ziel, Mouseover, Namensplakette), damit nie ein NPC
--           angespuckt wird.
--
-- Ausführung: C_ChatInfo.PerformEmote(token, name) – Blizzards Chat ruft es genauso auf
-- (/danke Name). Das Ziel wird nur genannt, wenn der Spieler in Reichweite ist. Der Stil
-- „Eigener Text“ sendet stattdessen ein /e-Emote, das den Namen immer enthält.
-- Spucken: WoW Forever nimmt bei SPIT kein Ziel mehr an (Spieltest 14.11.2026) – auch im Stil „Standard-Emote“
-- geht das Hinterherspucken darum als Text-Emote mit dem Namen hinaus (ns.Emote.Perform, Emote.lua).
-- Gedrosselt pro Spieler und global; keine Emotes während Blizzards Chat-Sperre.

local Auto = {}
ns.Auto = Auto

local PREDICTION_UNITS = { "target", "focus", "mouseover", "softfriend", "targettarget", "focustarget" }
-- Einheiten, deren erfolgreicher Zauber eine Heilvorhersage bestätigen kann: genau die, die ScanPredictions abfragt
-- (die Liste oben und die Namensplaketten). Für sie – und nur für sie – hört ezMacro auf UNIT_SPELLCAST_SUCCEEDED.
local CAST_UNITS = {}
for _, unit in ipairs(PREDICTION_UNITS) do CAST_UNITS[#CAST_UNITS + 1] = unit end
for i = 1, 40 do CAST_UNITS[#CAST_UNITS + 1] = "nameplate" .. i end
Auto.CAST_UNITS = CAST_UNITS
local PREDICTION_WINDOW = 5      -- Sekunden zwischen Heilvorhersage und erfolgreichem Zauber
local HOSTILE_MEMORY = 300       -- Sekunden: so lange gilt ein Spieler als „gesehen“
local QUEUE_MAX = 5

-- Heilvorhersage: off (nicht gebraucht) | on | secret (der Client sperrt den Wert – der Weg ist abgeschaltet)
local prediction = { state = "off" }

local lastFired = -math.huge
local perTarget = { thank = {}, spit = {} }
local queue = {}
local predicted = {}
local hostileSeen = {}
local lastAction
local limitedNoticeShown = false
local lockedNoticeShown = false

-- Der Stand der Erkennung hat sich geändert (Weg an oder aus, Sperre erkannt): wer ihn zeigt,
-- frischt auf – die Infozeile im Reiter „Chat“ (Emotes) (Browser.lua, Schlüssel "autoState"). Der Wechsel der Einstellung
-- allein reicht dafür nicht: Browser.lua lädt vor dieser Datei, sein Zuhörer auf „autoThank“ läuft, bevor Apply()
-- den Stand gesetzt hat, und eine Sperre mitten in der Sitzung ändert gar keine Einstellung.
local announcedState = "off"
local function StateChanged()
    local state = prediction.state
    if state == announcedState then return end
    announcedState = state
    ns.SettingChanged("autoState")
end

-- Laufzeit der Sitzung (Drosseln, Fenster; nie gespeichert): Core.Uptime, eine Stelle für alle Module (W-14)
local Now = Core.Uptime

-- Antwort einer Einheiten-Abfrage als Wahrheitswert: ezCores Core.Flag (Leitlinie 6: zuerst IsSecret; nil heißt
-- „nein“, z. B. UnitInRaid außerhalb des Raids). Eine gesperrte Antwort zählt als Rückfallwert – die vorsichtige
-- Seite: „ist kein Freund“, „ist in der Gruppe“, „ist nicht angreifbar“ (Welle 23, A8; vorher der Helfer Answer hier).

---------------------------------------------------------------------------
-- Helfer
---------------------------------------------------------------------------

-- Name aus Einheit oder Todesrückblick → Name für „/danke Name“, wie ihn Blizzards Chat zum Flüstern
-- braucht (ezCore: auf Forever Vor- und Nachname, sonst ohne eigenen Realm). nil bei geheimem oder leerem Namen.
local function TargetName(name)
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local full = Core.FullName(name)
    return full and Core.ShortName(full) or nil
end

local function IsSelf(target)
    return Core.IsSelf(Core.FullName(target))
end

-- „Nur in der offenen Welt“: in einer Instanz nicht (Core.InInstance; unbekannt zählt wie bisher als „draußen“)
local function InAllowedZone()
    if not ns.S.openWorldOnly then return true end
    return Core.InInstance() ~= true
end

local ChatLocked = ns.ChatLocked

-- Über ezCores Sende-Helfer (V-102): Forever/Retail-Weiche und Chat-Sperre an einer Stelle.
local function SendTextEmote(kind, target)
    local text = (kind == "thank" and L.AUTO_THANK_TEXT or L.AUTO_SPIT_TEXT):format(target)
    -- „Spucken mit Ziel: Animation + Text“ gilt auch für den eigenen Text: erst Blizzards Spucken ohne Ziel
    -- (während der Chat-Sperre lehnen Core.PerformEmote und Core.SendChat beide ab)
    if kind == "spit" and ns.Emote.Mode() == "both" then Core.PerformEmote("SPIT") end
    return Core.SendChat(text, "EMOTE") == true
end

local function SendStandardEmote(kind, target)
    local sent = ns.Emote.Perform(kind == "thank" and "THANK" or "SPIT", target)
    if sent == nil then return SendTextEmote(kind, target) end
    return sent
end

-- Führt das Emote aus. manual = Testbefehl: ohne Drosselung und Zonenprüfung.
function Auto.Fire(kind, name, manual)
    local target = TargetName(name)
    if not target or IsSelf(target) then return false end
    local now = Now()

    if not manual then
        if kind == "thank" and not ns.S.autoThank then return false end
        if kind == "spit" and not ns.S.autoSpit then return false end
        if not InAllowedZone() or ChatLocked() then return false end
        if now - lastFired < ns.S.globalCooldown then return false end
        local cooldown = (kind == "thank" and ns.S.thankCooldown or ns.S.spitCooldown) * 60
        local last = perTarget[kind][target]
        if last and now - last < cooldown then return false end
    end

    local sent
    if ns.S.autoStyle == "text" then
        sent = SendTextEmote(kind, target)
    else
        sent = SendStandardEmote(kind, target)
    end
    if not sent then return false end

    lastFired = now
    perTarget[kind][target] = now
    lastAction = (kind == "thank" and L.AUTO_DONE_THANK or L.AUTO_DONE_SPIT):format(target) .. " (" .. date("%H:%M") .. ")"
    if ns.S.announce or manual then ns.Print(lastAction) end
    return true
end

---------------------------------------------------------------------------
-- Heiler
---------------------------------------------------------------------------

local FlushAfterCombat   -- unten, nach FlushQueue

local function Healed(name)
    if not ns.S.autoThank then return end
    local target = TargetName(name)
    if not target then return end
    if ns.S.thankAfterCombat and (ns.InCombat() or UnitAffectingCombat("player")) then
        for _, queued in ipairs(queue) do
            if queued == target then return end
        end
        if #queue < QUEUE_MAX then queue[#queue + 1] = target end
        FlushAfterCombat()
        return
    end
    Auto.Fire("thank", target)
end

local function FlushQueue()
    if #queue == 0 or not ns.S.autoThank then return end
    local pending = queue
    queue = {}
    -- Die globale Drosselung lässt pro Kampf ein Danke durch – der erste Heiler zuerst.
    for _, target in ipairs(pending) do
        if Auto.Fire("thank", target) then break end
    end
end

-- Nach dem Kampf danken: ezCores Warteschlange (ns.AfterCombat) statt eines eigenen Zuhörers auf das Kampfende.
-- Gilt der Spieler schon als „im Kampf“, bevor die Kampfsperre greift, wartet der Aufruf einen Frame auf sie.
function FlushAfterCombat()
    if ns.InCombat() then
        ns.AfterCombat(FlushQueue, "auto.thanks")
    else
        C_Timer.After(0, function() ns.AfterCombat(FlushQueue, "auto.thanks") end)
    end
end

-- Eine Einheit der Heilvorhersage prüfen. → "secret", wenn der Client den Wert sperrt (dann ist der Weg zu), sonst nil.
-- Jede Antwort des Clients zuerst über IsSecret (Leitlinie 6; W-03: vorher standen sie ungeprüft in der Bedingung).
local function CheckPredictionUnit(unit, now)
    -- vorhanden und Spieler, nicht man selbst: Core.UnitIs (gesperrt → nil, dann nicht; V-184)
    if Core.UnitIs(unit) ~= true or Core.UnitIs(unit, "player") ~= false then return end
    if not Core.Flag(UnitIsFriend("player", unit), false) then return end
    if Core.Flag(UnitInParty(unit), true) or Core.Flag(UnitInRaid(unit), true) then return end
    local amount = UnitGetIncomingHeals("player", unit)
    if ns.IsSecret(amount) then return "secret" end
    if type(amount) ~= "number" or amount <= 0 then return end
    local guid, name = ns.Plain(UnitGUID(unit)), Core.UnitFullName(unit)
    if guid and name then predicted[guid] = { name = name, time = now } end
end

local LockPrediction   -- unten, bei SetPrediction

local function ScanPredictions()
    if prediction.state ~= "on" or type(UnitGetIncomingHeals) ~= "function" then return end
    local now = Now()
    local locked = false
    -- Jede Einheit einzeln schützen: ein Fehler bei einer Einheit hält die übrigen nicht auf.
    local function Check(unit)
        local ok, result = pcall(CheckPredictionUnit, unit, now)
        if ok and result == "secret" then locked = true end
    end
    for _, unit in ipairs(PREDICTION_UNITS) do Check(unit) end
    for i = 1, 40 do Check("nameplate" .. i) end
    if locked then LockPrediction() end
end

local function ConfirmPrediction(unit)
    local guid = ns.Plain(UnitGUID(unit))
    if not guid then return end
    local entry = predicted[guid]
    if not entry then return end
    predicted[guid] = nil
    if Now() - entry.time <= PREDICTION_WINDOW then Healed(entry.name) end
end

-- Über ezCores Ereignis-Verteiler (ns.OnUnit: nur für den Spieler) statt eines eigenen Rahmens. Hinter ns.OnUnit
-- zählt eine gesperrte Einheit als Treffer: ezCore stellt sie zu, verglichen wird sie nie (Leitlinie 6).
local function OnHealPrediction(_, unit)
    if ns.IsSecret(unit) or unit == "player" then ScanPredictions() end
end

-- Angemeldet über ns.OnUnit für CAST_UNITS (V-042, Vollprüfung 14.11.2026 W-04): vorher lief der Zuhörer für jede
-- Einheit. Eine gesperrte Einheit wird nur weitergereicht (UnitGUID unter pcall), nie verglichen.
local function OnSpellcastSucceeded(_, unit)
    if not next(predicted) then return end
    if ns.IsSecret(unit) or type(unit) == "string" then pcall(ConfirmPrediction, unit) end
end

---------------------------------------------------------------------------
-- Mörder
---------------------------------------------------------------------------

local function RememberHostile(unit)
    -- Leitlinie 6: jede Antwort zuerst über IsSecret; gesperrt zählt als „nicht gesehen“
    if Core.UnitIs(unit) ~= true or not Core.Flag(UnitCanAttack("player", unit), false) then return end
    local name = TargetName(Core.UnitFullName(unit))
    if name then hostileSeen[name] = Now() end
end

-- ns.Try statt nacktem pcall (Gesamtreview 18.11.2026, T7-1): RememberHostile prüft jede Antwort selbst über
-- IsSecret; ein echter Fehler steht in der Fehlerliste, statt still verdeckt zu werden.
local function ScanHostiles()
    ns.Try("Hostiles", RememberHostile, "target")
    ns.Try("Hostiles", RememberHostile, "mouseover")
    ns.Try("Hostiles", RememberHostile, "softenemy")
    for i = 1, 40 do ns.Try("Hostiles", RememberHostile, "nameplate" .. i) end
end

local function RecapKiller()
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" or ns.IsSecret(events) then return nil end
    local killingBlow = events[1] -- Blizzard: der erste Eintrag ist der tödliche Treffer
    if type(killingBlow) ~= "table" then return nil end
    local source = TargetName(ns.Plain(killingBlow.sourceName))
    if not source then return nil end
    local seen = hostileSeen[source]
    if seen and Now() - seen <= HOSTILE_MEMORY then return source end
    return nil
end

local function FindKiller(attempt)
    if not ns.S.autoSpit then return end
    local killer = RecapKiller()
    if killer then
        Auto.Fire("spit", killer)
    elseif attempt < 2 then
        -- Der Todesrückblick ist manchmal erst einen Moment später gefüllt.
        C_Timer.After(1.5, function() FindKiller(attempt + 1) end)
    end
end

local predicting = false

local function ListenPrediction(wanted)
    if wanted == predicting then return end
    predicting = wanted
    if wanted then
        ns.OnUnit("UNIT_HEAL_PREDICTION", "player", OnHealPrediction)
        ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", CAST_UNITS, OnSpellcastSucceeded)
    else
        ns.Off("UNIT_HEAL_PREDICTION", OnHealPrediction)
        ns.Off("UNIT_SPELLCAST_SUCCEEDED", OnSpellcastSucceeded)
    end
end

-- Sperrt der Client die Heilvorhersage? Probe ohne Rechnen: die Vorhersage für den Spieler selbst (alle Heiler).
-- WoW Forever liefert dort immer einen gesperrten Wert. Ein freier Wert oder nil sagt noch nichts – dann zeigt es
-- der erste gesperrte Wert beim Abfragen einer Einheit (ScanPredictions).
local function PredictionSecret()
    if type(UnitGetIncomingHeals) ~= "function" then return false end
    local ok, amount = pcall(UnitGetIncomingHeals, "player")
    return ok and ns.IsSecret(amount)
end

-- Der Client sperrt die Heilvorhersage: den Weg ehrlich abschalten (W-03) – nichts mehr abfragen, Ereignisse
-- abmelden, Stand „gesperrt“. Einmal je Sitzung ein Hinweis.
function LockPrediction()
    prediction.state = "secret"
    prediction.lockedSeen = true   -- gemerkt für die Sitzung: der Schalter bleibt danach grau (T14-6)
    ListenPrediction(false)
    wipe(predicted)
    if ns.S.autoThank and not lockedNoticeShown then
        lockedNoticeShown = true
        ns.Print(L.AUTO_LOCKED)
    end
    StateChanged()
end

-- Beim Einschalten neu geprüft: ein Wechsel der Einstellung fragt den Client noch einmal.
local function SetPrediction(wanted)
    if not wanted then
        prediction.state = "off"
        ListenPrediction(false)
        wipe(predicted)
    elseif prediction.state == "off" then
        if PredictionSecret() then
            LockPrediction()
        else
            prediction.state = "on"
            ListenPrediction(true)
        end
    end
end

local function Apply()
    local thank = ns.S.autoThank
    SetPrediction(thank and true or false)
    -- Der Hinweis „nur gewirkte Heilungen“ gilt nur, solange die Heilvorhersage liefert; ist sie gesperrt, hat
    -- LockPrediction den anderen Hinweis gezeigt.
    if thank and prediction.state == "on" and not limitedNoticeShown then
        limitedNoticeShown = true
        ns.Print(L.AUTO_LIMITED)
    end
    if not thank then wipe(queue) end
    StateChanged()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(Apply)
ns.OnSettingChanged(function(key)
    if key == "autoThank" or key == "autoSpit" then Apply() end
end)

ns.On("PLAYER_DEAD", function()
    if not ns.S.autoSpit then return end
    ScanHostiles()
    C_Timer.After(0.5, function() FindKiller(0) end)
end)

local function OnUnitSeen(_, unit)
    if ns.S.autoSpit then ns.Try("Hostiles", RememberHostile, unit or "target") end   -- T7-1
end
ns.On("PLAYER_TARGET_CHANGED", function() OnUnitSeen(nil, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() OnUnitSeen(nil, "mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", OnUnitSeen)

---------------------------------------------------------------------------
-- Status (/ezmacro status)
---------------------------------------------------------------------------

-- Stand der Heilvorhersage: "off" | "on" | "secret" (der Client sperrt den Wert, der Weg ist abgeschaltet).
function Auto.PredictionState() return prediction.state end

-- „Fremden Heilern danken“ ist an, kann aber nichts erkennen: Heilvorhersage gesperrt (Infozeile im Reiter
-- „Chat“ (Emotes)). Ein anderer Weg bleibt nicht: Das Kampflog nutzt ezMacro nie (Leitlinie 6).
function Auto.ThankBlocked()
    return ns.S.autoThank == true and prediction.state == "secret"
end

-- Lässt sich „Fremden Heilern danken“ sinnvoll einschalten? (Gesamtreview 18.11.2026, T14-6) Sperrt der Client die
-- Heilvorhersage (in dieser Sitzung gesehen oder jetzt geprüft), dankt ezMacro nie – dann zeigt die Einstellungsseite den
-- Schalter grau (Blizzards AddModifyPredicate). Ist er an, bleibt er bedienbar, damit man ihn ausschalten kann.
function Auto.ThankSwitchable()
    if ns.S.autoThank == true then return true end
    if prediction.state == "secret" or prediction.lockedSeen then return false end
    return not PredictionSecret()
end

-- Heiler-Erkennung: Heilvorhersage, oder – gesperrt – nichts (W-03: ehrlich sagen).
local function HealMode()
    if prediction.state ~= "secret" then return L.AUTO_MODE_PREDICT end
    return L.AUTO_MODE_PREDICT_LOCKED .. " – " .. L.AUTO_MODE_NONE
end

-- Die drei Zeilen des Stands (Befehl „status“ und „Stand zeigen“ unter Erweitert).
function Auto.StatusLines()
    local heal = ns.S.autoThank and HealMode() or L.AUTO_MODE_OFF
    local kill = ns.S.autoSpit and L.AUTO_MODE_RECAP or L.AUTO_MODE_OFF
    return {
        L.CMD_STATUS_HEAL:format(heal),
        L.CMD_STATUS_KILL:format(kill),
        L.CMD_STATUS_LAST:format(lastAction or L.CMD_STATUS_NONE),
    }
end

-- „/ezmacro status“ und der Knopf „Stand zeigen“ laufen über das Gerüst (ns.PrintStatus): diese Zeilen gehören dazu.
ns.AddStatusLine(Auto.StatusLines)

-- Hinweis an Blizzards Makroverwaltung (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis):
-- Danken und Spucken schicken ein Emote ohne Klick an fremde Spieler. Danken nur, solange der Client die Heilvorhersage
-- nicht sperrt (Gegenprüfung P17): auf WoW Forever ist sie immer gesperrt, der Schalter bliebe ohne Wirkung – dann kein
-- „Einschalten“ dafür (Probe ohne Rechnen wie beim Einschalten, PredictionSecret).
function Auto.HealerHintApplies()
    return prediction.state ~= "secret" and not PredictionSecret()
end

function Auto.RegisterOptInHints()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    local a = Hint.RegisterSetting("ezMacro", ns, "autoThank", { window = "macro", applies = Auto.HealerHintApplies })
    local b = Hint.RegisterSetting("ezMacro", ns, "autoSpit", { window = "macro" })
    return a and b
end
Auto.RegisterOptInHints()
