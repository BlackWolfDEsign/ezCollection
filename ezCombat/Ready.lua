local _, ns = ...
local L = ns.L
local Glow = ns.Glow
local Core = ezCore
local Slots = ezCore.ActionSlots      -- Aktionsplätze lesen (ezCore): Symbol, belegt?

-- Fähigkeit wieder bereit: Läuft die echte Abklingzeit eines Aktionsknopfs ab, die spürbar lang war, leuchtet der
-- Knopf kurz grün (Blizzards Proc-Leuchten, getönt); auf Wunsch springt das Symbol kurz am Symbolplatz in der
-- Bildschirmmitte auf (Symbol.lua), darunter in derselben Farbe, warum („Todesmantel – wieder bereit“).
--
-- Woher ezCombat das weiß (Abklingzeiten sind auf Forever gesperrt, sobald das Spiel sie einschränkt –
-- SecretWhenCooldownsRestricted laut Forever-Quelle):
--   • Blizzards Knöpfe setzen ihre Abklingzeit-Spirale selbst (SetCooldown) und räumen sie ab (Clear bzw.
--     OnCooldownDone); ezCombat hängt sich per hooksecurefunc an diese Methoden der Cooldown-Rahmen.
--   • Ob es eine echte Abklingzeit ist oder nur die globale: aus Start und Dauer, wenn lesbar, sonst aus den Feldern
--     isActive und isOnGCD von C_ActionBar.GetActionCooldown, die Blizzard nie sperrt (ezCore.ActionSlots.Cooldown
--     und ezCore.Spells.CooldownKind, seit ezCore 1.8.0).
--     Nur die globale Abklingzeit startet keine Messung – vorher zählte eine lange Reihe globaler Abklingzeiten
--     (oder ein verborgener Knopf, dessen Spirale nie „fertig“ meldet) wie eine lange Abklingzeit, und das Symbol
--     des Zaubers (beim Hexer Schattenblitz) sprang ohne Grund in der Mitte auf.
--   • Solange eine echte Abklingzeit läuft, sieht ein leiser Takt nach, ob sie vorbei ist – unabhängig davon, ob
--     Blizzards Spirale ihr Ende meldet.
local Ready = {}
ns.Ready = Ready

local FLASH_SECONDS = 1.5
local WATCH_EVERY = 0.1         -- Sekunden: Takt, solange eine echte Abklingzeit läuft

local owners = setmetatable({}, { __mode = "k" })     -- Cooldown-Rahmen → Aktionsknopf
local running = setmetatable({}, { __mode = "k" })    -- Cooldown-Rahmen → { since, slot, texture, real }
local scriptHooked = setmetatable({}, { __mode = "k" })
local methodsHooked = false
local watcher

-- Art der Abklingzeit auf einem Aktionsplatz: "none", "gcd", "real" oder nil (unbekannt).
-- Weiterleitung an ezCore.ActionSlots.Cooldown (seit ezCore 1.8.0).
function Ready.SlotCooldown(slot)
    return Slots.Cooldown(slot)
end

local function NewRun(button, real)
    return { since = GetTime(), slot = button.action, texture = Slots.Texture(button.action), real = real }
end

-- Blizzard setzt die Spirale: start/duration sind lesbar, gesperrt oder (SetCooldownFromDurationObject) ein
-- Dauer-Objekt – dann entscheiden die nie gesperrten Felder des Platzes.
local function OnStart(cooldown, start, duration)
    local button = owners[cooldown]
    if not button then return end
    local kind
    if ns.Num(start) and ns.Num(duration) then
        kind = ns.CooldownKind(nil, start, duration)
    else
        kind = Ready.SlotCooldown(button.action)
        if ns.IsSecret(start) or ns.IsSecret(duration) then
            ns.NoteSecret("cooldown")
            if kind == nil then Ready.unknownSeen = GetTime() end
        end
    end
    local run = running[cooldown]
    if kind == "real" then
        if not (run and run.real) then
            running[cooldown] = NewRun(button, true)
            Ready.realSeen = (Ready.realSeen or 0) + 1
            Ready.Watch()
        end
    elseif kind == nil and not run then
        -- Weder Werte noch isOnGCD lesbar (sehr alter Client): wie früher die Zeit messen.
        running[cooldown] = NewRun(button, nil)
    end
    -- "gcd"/"none": keine Messung. Eine laufende echte Abklingzeit bleibt; endet sie unter der globalen, sieht es
    -- der Takt (der Platz meldet dann nur noch die globale).
end

---------------------------------------------------------------------------
-- Blizzards Cooldown-Manager (Blizzard_CooldownViewer, lädt auf Forever): Dort kann man je Zauber einen
-- Hinweis „Bereit“ einstellen (Ton, Vorlesen, Rand oder Blinken am Symbol). Meldet der Manager einen Zauber
-- selbst, schweigt ezCombat dafür – kein doppelter Hinweis. ezCombat liest dabei nur (Felder und Getter der
-- angezeigten Einträge) und ruft nichts auf, das Blizzards Daten neu aufbaut.
---------------------------------------------------------------------------

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local function AlertEvent()
    local enum = Enum and Enum.CooldownViewerAlertEventType
    return enum and enum.Available or 1
end

local function ItemAnnounces(item, name, event)
    local alerts = type(item.alertsByEvent) == "table" and item.alertsByEvent[event]
    if type(alerts) ~= "table" or next(alerts) == nil then return false end
    local info = type(item.GetCooldownInfo) == "function" and item:GetCooldownInfo()
    if type(info) ~= "table" then return false end
    for _, id in ipairs({ ns.Plain(info.spellID), ns.Plain(info.overrideSpellID) }) do
        if type(id) == "number" and ns.SpellName(id) == name then return true end
    end
    return false
end

-- Meldet Blizzards Cooldown-Manager diesen Zauber gerade selbst, wenn er bereit ist?
function Ready.ManagerAnnounces(name)
    if type(name) ~= "string" then return false end
    local event = AlertEvent()
    for _, key in ipairs(VIEWERS) do
        local viewer = rawget(_G, key)
        local pool = type(viewer) == "table" and viewer.itemFramePool
        if pool and viewer:IsShown() and type(pool.EnumerateActive) == "function" then
            local ok, found = pcall(function()
                for item in pool:EnumerateActive() do
                    if ItemAnnounces(item, name, event) then return true end
                end
                return false
            end)
            if ok and found then return true end
        end
    end
    return false
end

-- Warum zuletzt nichts kam (/ezk status): Grund und Zauber einer echten Abklingzeit, die nicht gemeldet wurde.
local function Skip(info, name, reason)
    if info.real then Ready.skipped = { when = GetTime(), name = name, reason = reason } end
end

local function OnStop(cooldown)
    local info = running[cooldown]
    if not info then return end
    running[cooldown] = nil
    local button = owners[cooldown]
    -- Anderer Zauber auf dem Platz (Leiste umgeschaltet, Haltung gewechselt): nichts melden.
    if not button or button.action ~= info.slot then return end
    -- Die echte Abklingzeit läuft laut Spiel noch (z. B. Kontrollverlust ersetzt die Spirale): weiter beobachten.
    if info.real and Ready.SlotCooldown(info.slot) == "real" then
        running[cooldown] = info
        Ready.Watch()
        return
    end
    local name = Glow.SpellOf(button)
    -- Ein Schalter für „wieder bereit“: die Auswahl showReady (Einstellungs-Prüfung 19.11.2026, Nr. 70/71)
    if not ns.ShowAny("ready") then return Skip(info, name, "off") end
    if GetTime() - info.since < ns.S.readyMin then return Skip(info, name, "short") end
    if Slots.Texture(button.action) ~= info.texture then return end
    -- Verrät das Spiel noch eine laufende Abklingzeit, ist nichts bereit.
    if name and ns.OnCooldown(name) then return Skip(info, name, "cooldown") end
    -- Blizzards Cooldown-Manager meldet ihn schon: nicht doppelt.
    if name and Ready.ManagerAnnounces(name) then return Skip(info, name, "manager") end
    local visible = button:IsVisible()
    -- Unbekannte Art (weder Werte noch isOnGCD lesbar): nur sichtbare Knöpfe melden.
    if not info.real and not visible then return end
    -- Wo „wieder bereit“ erscheint (CB-N1): Leuchten am Knopf, rechter Platz der Anzeige über dem Charakter, beides.
    if not ns.ShowAny("ready") then return Skip(info, name, "off") end
    if visible and ns.ShowAt("ready", "glow") then Glow.Flash(button, FLASH_SECONDS, "ready") end
    if ns.ShowAt("ready", "center") then Ready.Pulse(info.texture, "ready", name) end
    Ready.last = { when = GetTime(), name = name }
end
Ready.OnStart, Ready.OnStop = OnStart, OnStop

-- Takt, solange eine echte Abklingzeit läuft: Ist sie laut Spiel vorbei (oder nur noch die globale), gilt sie als
-- abgelaufen – auch wenn Blizzards Spirale (verborgene Leiste, ersetzte Spirale) ihr Ende nicht meldet.
function Ready.Check()
    local any = false
    for cooldown, info in pairs(running) do
        if info.real then
            local button = owners[cooldown]
            if not button or button.action ~= info.slot then
                running[cooldown] = nil
            else
                local kind = Ready.SlotCooldown(info.slot)
                if kind == "none" or kind == "gcd" then
                    OnStop(cooldown)
                elseif running[cooldown] then
                    any = true
                end
            end
        end
    end
    return any
end

function Ready.Watch()
    if watcher or not C_Timer.NewTicker then return end
    watcher = C_Timer.NewTicker(WATCH_EVERY, function()
        local ok, any = pcall(Ready.Check)
        if not ok then ns.Error(any, "Ready") end
        if not (ok and any) and watcher then
            watcher:Cancel()
            watcher = nil
        end
    end)
end

function Ready.Watching() return watcher ~= nil end

---------------------------------------------------------------------------
-- Zahlen auf Abklingzeiten: Blizzards eigene Anzeige (CVar countdownForCooldowns, sonst nur unter
-- Optionen → Aktionsleisten). Blizzard aktualisiert alle Aktionsknöpfe selbst, sobald sich die
-- CVar ändert. Ersatz für OmniCC, das auf Forever nicht läuft.
---------------------------------------------------------------------------

local COUNTDOWN_CVAR = "countdownForCooldowns"
Ready.COUNTDOWN_CVAR = COUNTDOWN_CVAR

function Ready.CountdownOn()
    return ns.CVarOn(COUNTDOWN_CVAR)
end

-- Kein eigenes Kästchen mehr (Einstellungs-Prüfung 19.11.2026, Abschnitt 4: doppelt mit Blizzards eigenem Kästchen
-- unter „Aktionsleisten“) – die Statuszeile verweist auf Blizzards Einstellung.
ns.AddStatusLine(function()
    if Ready.CountdownOn() then return L.STATUS_COUNTDOWN_ON end
    return L.STATUS_COUNTDOWN_OFF
end)

-- Was „wieder bereit“ bei gesperrten Abklingzeiten noch kann.
ns.AddStatusLine(function()
    if Ready.unknownSeen then return L.STATUS_READY_UNKNOWN end
    if ns.secretSeen.cooldown then return L.STATUS_READY_SECRET end
end)

-- Was „wieder bereit“ zuletzt gemeldet hat – oder warum nicht (für den Spieltest: „es kommt nichts“).
local function Ago(when) return L.STATUS_AGO:format(Core.Duration(GetTime() - when, true)) end

function Ready.StatusText()
    if not ns.ShowAny("ready") then return L.STATUS_READY_OFF:format(ns.PathText("OPT_HEADER_SYMBOL", "OPT_showReady")) end
    if not Ready.realSeen then return L.STATUS_READY_NONE:format(Core.Duration(ns.S.readyMin)) end
    local last, skipped = Ready.last, Ready.skipped
    if skipped and (not last or skipped.when > last.when) then
        local reason = L["STATUS_READY_SKIP_" .. skipped.reason] or skipped.reason
        if skipped.reason == "short" then reason = reason:format(Core.Duration(ns.S.readyMin)) end
        return L.STATUS_READY_SKIPPED:format(skipped.name or "?", Ago(skipped.when), reason)
    end
    if last then return L.STATUS_READY_LAST:format(last.name or "?", Ago(last.when)) end
    return L.STATUS_READY_RUNNING
end
ns.AddStatusLine(Ready.StatusText)

ns.AddStatusLine(function()
    for _, key in ipairs(VIEWERS) do
        local viewer = rawget(_G, key)
        if type(viewer) == "table" and viewer.IsShown and viewer:IsShown() then return L.STATUS_COOLDOWN_MANAGER end
    end
end)

-- Methoden aller Cooldown-Rahmen einmal einhängen (gemeinsame Methodentabelle der Cooldown-Rahmen), sonst je Rahmen.
local function HookMethods(cooldown)
    if methodsHooked then return end
    local meta = getmetatable(cooldown)
    local index = type(meta) == "table" and meta.__index
    local target = (type(index) == "table" and type(index.SetCooldown) == "function") and index or nil
    local function Hook(tbl)
        hooksecurefunc(tbl, "SetCooldown", OnStart)
        if type(tbl.SetCooldownFromDurationObject) == "function" then
            hooksecurefunc(tbl, "SetCooldownFromDurationObject", OnStart)
        end
        if type(tbl.Clear) == "function" then hooksecurefunc(tbl, "Clear", OnStop) end
    end
    if target then
        Hook(target)
        methodsHooked = true
    else
        Hook(cooldown)
    end
end

function Ready.Attach()
    for _, button in ipairs(Glow.Buttons()) do
        local cooldown = button.cooldown
        if type(cooldown) == "table" and not owners[cooldown] then
            owners[cooldown] = button
            HookMethods(cooldown)
            if not scriptHooked[cooldown] and cooldown.HookScript then
                cooldown:HookScript("OnCooldownDone", OnStop)
                scriptHooked[cooldown] = true
            end
        end
    end
end

---------------------------------------------------------------------------
-- Symbol in der Bildschirmmitte: der gemeinsame Symbolplatz (Symbol.lua) – „wieder bereit“ ist ein kurzer Eintrag
---------------------------------------------------------------------------

local PULSE_SAME_ICON = 0.5     -- dasselbe Symbol auf zwei Leisten springt nur einmal auf
local PULSE_ICON = ns.Symbol.DEFAULT_ICON
local lastPulse, lastPulseTexture = 0, nil

-- Der Symbolplatz (Rahmen „ezCombatReadyPulse“, verschiebbar).
function Ready.PulseFrame() return ns.Symbol.Frame() end

-- Text unter dem Symbol: warum es erscheint, in der Farbe der Art.
function Ready.Label(kind, name)
    if kind == "ready" or kind == nil then
        return name and L.PULSE_READY:format(name) or L.PULSE_READY_PLAIN
    end
    return Core.GlowLabel(kind) or ""
end

-- Symbol aufspringen lassen. kind: Art aus ezCore.GLOW_KINDS (Standard "ready", grün), name: Zaubername für den Text;
-- text: eigener Text darunter (z. B. „Dämonenhaut ist ausgelaufen“), sonst der zur Art. Kurzer Eintrag am
-- Symbolplatz: „ready“, bei Buffs („missing“) „buff“ – Wichtigeres (ein DoT läuft aus) bleibt davor.
function Ready.Pulse(texture, kind, name, text)
    texture = texture or PULSE_ICON
    kind = kind or "ready"
    local now = GetTime()
    if texture == lastPulseTexture and now - lastPulse < PULSE_SAME_ICON then return end
    lastPulse, lastPulseTexture = now, texture
    -- name: Zauber für „noch nicht bereit“ (wieder bereit, aber außer Reichweite oder ohne Kraft: Symbol.lua)
    -- Bei „Text unter dem Symbol: nur Name“ (Symbol.lua) steht nur der Name, ohne „ist wieder bereit“.
    ns.Symbol.Pop(kind == "missing" and "buff" or "ready", texture, text or Ready.Label(kind, name), kind, nil, name,
        { name = name })
end

-- Beispiel beim Verschieben: Solange die Auswahl offen ist, steht ein Beispiel am Symbolplatz (unterster Rang –
-- ein echter Eintrag geht vor).
function Ready.ShowExample()
    if ns.PartsShowing() then
        ns.Symbol.Set("example", PULSE_ICON, L.PULSE_EXAMPLE, "ready")
    else
        ns.Symbol.Clear("example")
    end
end

---------------------------------------------------------------------------

ns.OnReady(Ready.Attach)
ns.On("PLAYER_ENTERING_WORLD", Ready.Attach)
ns.Listen("PARTS_SHOWING", Ready.ShowExample)

-- Vorschau: erster sichtbarer Knopf mit einer Aktion leuchtet, sein Symbol springt auf.
ns.AddPreview("ready", 10, function()
    for _, button in ipairs(Glow.Buttons()) do
        if button:IsVisible() and Slots.Has(button.action) then
            Glow.Flash(button, 2, "ready")
            Ready.Pulse(Slots.Texture(button.action), "ready", Glow.SpellOf(button))
            return true
        end
    end
    Ready.Pulse(nil, "ready")
    return true
end)
