local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Schnittstelle für andere Module: ezCore.API("ezChat") (nil, solange ezChat nicht geladen ist).
-- Die Funktionen stehen auch im README-Abschnitt von ezChat.
-- Nutzer: ezSocial (Klick auf eine Gruppen-Nachricht; in der Freundesliste Ungelesen-Zahl und Knopf „Gespräch“),
-- ezPanel (Baustein „Freunde und Gilde“: Totals, ToggleWindow).

local API = {}
ns.API = API

-- Name oder BattleTag → Gesprächspartner wie ezChat ihn speichert, und Schlüssel; nil bei unbrauchbarem
-- Namen (geheim, leer, man selbst, noch nicht eingeloggt). Dieselben Regeln für alle Funktionen hier.
local function Resolve(name, bn)
    if not ns.C or type(name) ~= "string" or not ns.Usable(name) then return nil end
    local target = ns.Trim(name)
    if target == "" then return nil end
    if not bn then
        local full = ns.FullName(target)
        if not full then return nil end
        target = ns.CompleteName(full)
        if ns.IsSelf(target) then return nil end
    end
    return target, Conv.KeyOf(target, bn)
end

-- Gespräch mit einem Spieler öffnen, z. B. nach einem Klick auf eine Gruppen-Nachricht (ezSocial).
--   name: voller Name („Vorname Nachname“ auf Forever, sonst „Name-Realm“; ein bekannter Vorname
--         genügt) oder BattleTag „Name#1234“ mit opts.bn
--   opts: { bn = true (Battle.net-Freund), text = "vorbereitete Antwort" (steht dann im Eingabefeld),
--           inChat = true (im Chatfenster statt im Gesprächsfenster),
--           docked = false (nie an die Freundesliste) | true (angedockt, sobald die Freundesliste offen ist) }
--         oder kurz nur der Text: OpenConversation(name, "Hallo, ist noch Platz?")
--   Ohne docked gilt: Ist Blizzards Freundesliste offen und „An die Freundesliste andocken“ an, geht das
--   Gesprächsfenster angedockt daneben auf, sonst frei.
-- Rückgabe: Schlüssel des Gesprächs (wahr) oder nil (kein Name, man selbst, noch nicht eingeloggt).
function API.OpenConversation(name, opts)
    if type(opts) == "string" then opts = { text = opts } end
    opts = type(opts) == "table" and opts or {}
    local bn = opts.bn and true or false
    local target, key = Resolve(name, bn)
    if not target then return nil end
    if opts.inChat then
        ns.Chat.Start(target, bn)
    else
        local mode
        if opts.docked == false then
            mode = "free"
        elseif ns.FriendsDock and ns.FriendsDock.Active() then
            mode = "docked"
        end
        ns.Window.OpenFor(target, bn, mode)
        if type(opts.text) == "string" and opts.text ~= "" then ns.Window.SetDraft(opts.text) end
    end
    return key
end

-- Stand des Gesprächs mit einem Spieler, ohne eines anzulegen (z. B. für jede Zeile der Freundesliste):
--   { key, unread = ungelesene Nachrichten, queued = Nachrichten, die auf Zustellung warten,
--     last = Zeitpunkt der letzten Nachricht (oder nil), muted, alarm }
-- oder nil, wenn es kein Gespräch gibt bzw. der Name unbrauchbar ist. bn = true für einen BattleTag.
-- Gespräch zum Namen, ohne eines anzulegen (Conv.Get mit create = false): Gespräch, Schlüssel – oder nil.
local function Existing(name, bn)
    local target = Resolve(name, bn)
    if not target then return nil end
    return Conv.Get(target, bn, false)
end

function API.Conversation(name, bn)
    local convo, key = Existing(name, bn and true or false)
    if not convo then return nil end
    local last = convo.msgs[#convo.msgs]
    return { key = key, unread = convo.unread or 0, queued = Conv.CountQueued(convo), last = last and last.t or nil,
        muted = convo.muted == true, alarm = convo.alarm == true }
end

-- Kurzformen: Zahlen statt Tabelle (0, wenn es kein Gespräch gibt).
function API.Unread(name, bn)
    local state = API.Conversation(name, bn)
    return state and state.unread or 0
end

function API.Queued(name, bn)
    local state = API.Conversation(name, bn)
    return state and state.queued or 0
end

-- Für ezSocials Knopf „Gespräch“ (Talk.Counts): ungelesen, wartend – 0, 0 ohne Gespräch, nil bei
-- unbrauchbarem Namen. opts wie bei OpenConversation ({ bn = true } für einen BattleTag).
function API.ConversationCounts(name, opts)
    local bn = type(opts) == "table" and opts.bn and true or false
    local target, key = Resolve(name, bn)   -- einmal auflösen (V-071), dann direkt lesen
    if not target then return nil end
    local convo = key and ns.C.convos[key]
    if not convo then return 0, 0 end
    return convo.unread or 0, Conv.CountQueued(convo)
end

-- Summen über alle Gespräche: ungelesen, wartend (Nachrichten, auch stumm geschalteter Gespräche).
function API.Totals()
    return Conv.UnreadTotal(), Conv.QueuedTotal()
end

-- Zahl der Gespräche mit Ungelesenem, stumm geschaltete nicht mitgezählt – dieselbe Zahl wie ezChats Meldung
-- „n ungelesene Gespräche“ bei ezPanel (Welle 23, A3; Totals zählt Nachrichten). 0 vor dem Einloggen.
function API.UnreadConversations()
    return Conv.UnreadConvos()
end

-- Gesprächsfenster ohne Namen öffnen (das zuletzt gewählte Gespräch, sonst das neueste) bzw. öffnen oder schließen –
-- wie ein Klick auf den Knopf an der Chat-Leiste oder /ezchat ohne Wort (Welle 23, A2; für ezPanel).
-- → true, wenn das Fenster danach offen ist; false vor dem Einloggen bzw. nach dem Schließen.
function API.OpenWindow()
    if not ns.C then return false end
    ns.Window.Open()
    return ns.Window.IsShown() == true
end

function API.ToggleWindow()
    if not ns.C then return false end
    ns.Window.Toggle()
    return ns.Window.IsShown() == true
end

-- Ist ezChats Gesprächsfenster gerade an der Freundesliste angedockt und offen?
function API.IsDocked()
    return ns.Window.IsDocked() and ns.Window.IsShown()
end

-- Änderungen melden: ezCore-Nachricht API.CHANGED (gesammelt, höchstens fünfmal je Sekunde), wenn sich
-- Ungelesen, Warteschlange oder Gespräche ändern. Andere Module hören mit ezCore.Listen(API.CHANGED, fn).
-- Conv.OnChange deckt neue Nachrichten, Warteschlange (eingereiht, zugestellt, abgebrochen, unzustellbar),
-- Umbenennen und Löschen ab; Conv.OnRead das Lesen.
API.CHANGED = "EZCHAT_CONVERSATIONS_CHANGED"
-- Im Verzeichnis der Nachrichten angemeldet (docs/ezcore.md, Namensregel 2; Gesamtreview 18.11.2026, T4-4).
ezCore.RegisterMessage(API.CHANGED, "ezChat", "Gespräche, Ungelesenes oder Warteschlange von ezChat geändert")
local FireSoon = ns.Throttle(function() ezCore.Fire(API.CHANGED) end, 0.2)
Conv.OnChange(function() FireSoon() end)
Conv.OnRead(function() FireSoon() end)

---------------------------------------------------------------------------
-- Meldung auf ezPanels Leiste (Baustein „Meldungen“; Vollprüfung W-25, Frage 17 entschieden 14.11.2026: „Ja, je
-- Quelle abwählbar“): „n ungelesene Gespräche“. Angemeldet im ns.OnReady – dann sind alle Addons geladen; läuft
-- ezPanel nicht (oder eine Fassung ohne AddWarning), passiert nichts. Abwählen lässt sich die Quelle in ezPanels
-- Menü „Meldungen“ → „Quellen“. ezPanel fragt alle 5 Sekunden und nach RefreshWarnings – das ruft ezChat, sobald
-- sich Ungelesenes ändert (API.CHANGED, gesammelt).
---------------------------------------------------------------------------

ns.PANEL_WARNING = "ezChat.unread"   -- Kennung der Quelle bei ezPanel

-- Text der Meldung oder nil, wenn nichts ungelesen ist. Gezählt werden Gespräche, nicht Nachrichten; stumme nicht.
function ns.UnreadWarning()
    local count = Conv.UnreadConvos()
    if count <= 0 then return nil end
    if count == 1 then return L.PANEL_UNREAD_ONE end
    return L.PANEL_UNREAD:format(count)
end

-- Bei ezPanel anmelden. → true, wenn ezPanel läuft und die Quelle angenommen hat.
local refreshing = false
function ns.RegisterPanelWarning()
    local panel = ezCore.API("ezPanel")
    if not (panel and type(panel.AddWarning) == "function") then return false end
    if not panel.AddWarning(ns.PANEL_WARNING, L.PANEL_SOURCE, ns.UnreadWarning) then return false end
    if not refreshing then
        refreshing = true
        ezCore.Listen(API.CHANGED, function()
            local p = ezCore.API("ezPanel")
            if p and type(p.RefreshWarnings) == "function" then p.RefreshWarnings() end
        end, "ezChat")
    end
    return true
end

ns.OnReady(function() ns.Try("PanelWarning", ns.RegisterPanelWarning) end)
