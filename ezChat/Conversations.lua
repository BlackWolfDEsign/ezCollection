local _, ns = ...

-- Gespräche: ein Datensatz pro Gesprächspartner (Charakter oder Battle.net-Freund).
--
-- ns.C.convos[Schlüssel] = {
--     name   = voller Name (WoW Forever „Vorname Nachname“, sonst „Name-Realm“)
--              oder BattleTag "Name#1234",
--     bn     = true bei Battle.net-Freunden,
--     msgs   = { Nachricht, ... } (zeitlich sortiert),
--     unread = Anzahl ungelesener Nachrichten,
--     last   = Zeit der letzten Nachricht,
--     closed = true: aus der Gesprächsauswahl im Chatfenster entfernt (bis zur nächsten Nachricht),
--     class  = Klasse des Partners ("MAGE" …), sobald bekannt (Klassenfarbe im Gesprächsfenster),
--     alarm  = true: Ton und Blinken, wenn der Partner in Gilde, Gruppe oder einem Kanal schreibt,
--     muted  = true: stumm – Flüstern nur still im Gespräch (nicht im Chatfenster, kein Ton, nicht ungelesen),
--     keepDays = Aufbewahrung in Tagen nur für diesen Partner (0 = nie nach Tagen kürzen; nil = Einstellung keepDays),
-- }
-- Nachricht = {
--     t = Zeit (time()), m = Text,
--     o = true bei eigenen Nachrichten,
--     v = Weg: nil Flüstern, "w" später per Flüstern zugestellt, "b" Battle.net,
--         "p" Brief, "c" Zweier-Community,
--     s = nur eigene: "q" wartet auf Zustellung, "x" abgebrochen/nicht zustellbar,
--     d = Zeitpunkt der späteren Zustellung,
--     a = true bei der automatischen Antwort (Situation.lua): markiert das Gespräch nicht als gelesen,
--     nur wartende eigene Nachrichten (s = "q"; Delivery.lua, Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 9,
--     Welle 28):
--     n = Zahl der Zustellversuche, f = Zeit des ersten Versuchs (time()),
--     h = Zeitpunkt des Anhaltens (time()): angehalten nach Delivery.MAX_TRIES Versuchen bzw. Delivery.MAX_SPAN ab f –
--         wartet ohne weitere Versuche, bis der Spieler „Jetzt zustellen versuchen“ wählt oder dem Partner eine neue
--         Nachricht schreibt (Delivery.Retry bzw. Delivery.Queue setzen n, f und h zurück),
-- }

local Conv = {}
ns.Conv = Conv

local MAX_CONVOS = 50
local listeners = {}

function Conv.OnChange(fn) listeners[#listeners + 1] = fn end

function Conv.Changed(key)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, key)
        if not ok then ns.Error(err) end
    end
end

-- Gelesen: Zähler auf 0 und nur den Zählern Bescheid geben (Chat-Knopfleiste, Freundesliste, Schnittstelle).
-- Bewusst ohne Conv.Changed, das Fenster und Gesprächsansicht neu aufbauen würde.
local readListeners = {}
function Conv.OnRead(fn) readListeners[#readListeners + 1] = fn end

function Conv.MarkRead(convo)
    if not convo or (convo.unread or 0) == 0 then return end
    convo.unread = 0
    for _, fn in ipairs(readListeners) do ns.Try("Read", fn) end
end

function Conv.KeyOf(name, bn)
    if type(name) ~= "string" then return nil end
    return (bn and "bn:" or "") .. name:lower()
end

-- Menüzeile eines Gesprächs: Name (Battle.net hellblau), „(ungelesen)“ in Gold, „wartet“ in Grau – dieselbe
-- Zeile im Menü „Neues Gespräch → Zuletzt“ und in der Gesprächsauswahl am Chat (V-072).
function Conv.MenuLabel(convo)
    local label = Conv.Display(convo)
    if not convo then return label end
    if convo.bn then label = ns.ColorText("bnet", label) end
    local unread, queued = convo.unread or 0, Conv.CountQueued(convo)
    if unread > 0 then label = label .. " " .. ezCore.Gold("(" .. unread .. ")") end
    if queued > 0 then label = label .. " " .. ezCore.Grey(ns.L.ROW_QUEUED:format(queued)) end
    return label
end

function Conv.Display(convo)
    if not convo then return "?" end
    if convo.bn then return convo.name:match("^(.-)#") or convo.name end
    return ns.Short(convo.name)
end

function Conv.Sorted()
    local list = {}
    if not ns.C then return list end
    for key, convo in pairs(ns.C.convos) do
        list[#list + 1] = { key = key, convo = convo }
    end
    table.sort(list, function(a, b)
        local ta, tb = a.convo.last or 0, b.convo.last or 0
        if ta ~= tb then return ta > tb end
        return a.key < b.key
    end)
    return list
end

-- Offene Gespräche (Auswahl in der Reiterleiste), neueste zuerst.
function Conv.Open()
    local list = {}
    for _, item in ipairs(Conv.Sorted()) do
        if not item.convo.closed then list[#list + 1] = item end
    end
    return list
end

function Conv.FirstQueued(convo)
    if not convo then return nil end
    for _, msg in ipairs(convo.msgs) do
        if msg.o and msg.s == "q" then return msg end
    end
    return nil
end

function Conv.CountQueued(convo)
    local count = 0
    if convo then
        for _, msg in ipairs(convo.msgs) do
            if msg.o and msg.s == "q" then count = count + 1 end
        end
    end
    return count
end

-- Ungelesene bzw. wartende Nachrichten über alle Gespräche (Chat-Knopfleiste, Freundesliste, Schnittstelle).
function Conv.UnreadTotal()
    local total = 0
    if ns.C then
        for _, convo in pairs(ns.C.convos) do total = total + (convo.unread or 0) end
    end
    return total
end

-- Anzahl der Gespräche mit ungelesenen Nachrichten (ezPanels Meldung „n ungelesene Gespräche“). Stumme zählen
-- nicht – auch dann nicht, wenn alte Daten dort noch einen Zähler tragen.
function Conv.UnreadConvos()
    local count = 0
    if ns.C then
        for _, convo in pairs(ns.C.convos) do
            if not convo.muted and (convo.unread or 0) > 0 then count = count + 1 end
        end
    end
    return count
end

function Conv.QueuedTotal()
    local total = 0
    if ns.C then
        for _, convo in pairs(ns.C.convos) do total = total + Conv.CountQueued(convo) end
    end
    return total
end

function Conv.QueuedKeys()
    local keys = {}
    if not ns.C then return keys end
    for key, convo in pairs(ns.C.convos) do
        if Conv.FirstQueued(convo) then keys[#keys + 1] = key end
    end
    return keys
end

-- Höchstens MAX_CONVOS Gespräche mit Verlauf; die ältesten ohne wartende Nachrichten fallen weg.
-- Leere Gespräche (nur geöffnet, noch nichts geschrieben) zählen nicht mit und verdrängen keinen
-- Verlauf; sie fallen beim Ausloggen weg. keepKey: das Gespräch, das gerade eine Nachricht bekommt –
-- es bleibt, auch wenn sein Zeitstempel alt ist (früher geöffnet, alter Brief).
function Conv.Prune(keepKey)
    local keep = keepKey and ns.C.convos[keepKey]
    local filled = (keep and #keep.msgs > 0) and 1 or 0   -- zählt vorab mit, damit dafür ein anderes weicht
    for _, item in ipairs(Conv.Sorted()) do
        if item.key ~= keepKey and #item.convo.msgs > 0 then
            filled = filled + 1
            if filled > MAX_CONVOS and not Conv.FirstQueued(item.convo) then ns.C.convos[item.key] = nil end
        end
    end
end

function Conv.Get(name, bn, create)
    local key = Conv.KeyOf(name, bn)
    if not key or not ns.C then return nil end
    local convo = ns.C.convos[key]
    if not convo and create then
        convo = { name = name, bn = bn and true or nil, msgs = {}, unread = 0, last = time() }
        ns.C.convos[key] = convo
        Conv.Prune()
    end
    return convo, key
end

-- Gespräch unter einem neuen Namen führen; gibt es den schon, werden beide zusammengelegt.
function Conv.Rename(key, newName)
    local convo = ns.C and ns.C.convos[key]
    local newKey = Conv.KeyOf(newName, convo and convo.bn)
    if not convo or not newKey then return key end
    if newKey == key then
        convo.name = newName
        return key
    end
    local target = ns.C.convos[newKey]
    ns.C.convos[key] = nil
    if not target then
        convo.name = newName
        ns.C.convos[newKey] = convo
    else
        for _, msg in ipairs(convo.msgs) do target.msgs[#target.msgs + 1] = msg end
        table.sort(target.msgs, function(a, b) return (a.t or 0) < (b.t or 0) end)
        target.last = math.max(target.last or 0, convo.last or 0)
        -- Stumm und Alarm gelten weiter, wenn eines der beiden sie hatte; die Klasse bleibt, wenn das Ziel keine
        -- kennt; offen in der Gesprächsauswahl, sobald eines der beiden offen war (V-070).
        target.muted = (target.muted or convo.muted) and true or nil
        target.alarm = (target.alarm or convo.alarm) and true or nil
        target.class = target.class or convo.class
        if not convo.closed then target.closed = nil end
        target.unread = target.muted and 0 or ((target.unread or 0) + (convo.unread or 0))
        Conv.TrimMessages(target.msgs, ns.Number("keepCount"))
    end
    if ns.Window and ns.Window.Renamed then ns.Window.Renamed(key, newKey) end
    if ns.ChatView and ns.ChatView.Renamed then ns.ChatView.Renamed(key, newKey) end
    Conv.Changed(newKey)
    return newKey
end

-- Namen eines Charakter-Gesprächs vereinheitlichen und auf Forever den Nachnamen
-- ergänzen, wenn er inzwischen bekannt ist. Gibt den (neuen) Schlüssel zurück.
function Conv.Fix(key)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or convo.bn then return key end
    local full = ns.CompleteName(ns.FullName(convo.name) or convo.name)
    if full ~= convo.name then return Conv.Rename(key, full) end
    return key
end

-- Älteste Nachrichten über der Obergrenze entfernen, wartende bleiben immer.
local Trim
function Conv.TrimMessages(msgs, cap) return Trim(msgs, cap) end
function Trim(msgs, cap)
    local excess = #msgs - cap
    if excess <= 0 then return end
    local kept = {}
    for _, msg in ipairs(msgs) do
        if excess > 0 and msg.s ~= "q" then
            excess = excess - 1
        else
            kept[#kept + 1] = msg
        end
    end
    wipe(msgs)
    for i, msg in ipairs(kept) do msgs[i] = msg end
end

-- entry.quiet = true: nicht als ungelesen zählen (z. B. Erstübernahme alter Nachrichten).
function Conv.Add(name, bn, entry)
    local convo, key = Conv.Get(name, bn, true)
    if not convo then return nil end
    local quiet = entry.quiet
    entry.quiet = nil
    entry.t = entry.t or time()

    local msgs = convo.msgs
    local i = #msgs
    while i > 0 and (msgs[i].t or 0) > entry.t do i = i - 1 end
    table.insert(msgs, i + 1, entry)
    Trim(msgs, ns.Number("keepCount"))

    if entry.t > (convo.last or 0) then convo.last = entry.t end
    if #msgs == 1 then Conv.Prune(key) end   -- erst mit der ersten Nachricht zählt das Gespräch zur Obergrenze
    if not convo.muted then convo.closed = nil end   -- neue Nachricht: wieder unter den offenen Gesprächen
    if entry.o and not entry.a then convo.unread = 0 end   -- wer antwortet, hat gelesen (die automatische Antwort nicht)
    if not entry.o and not quiet and not convo.muted then
        convo.unread = (convo.unread or 0) + 1
        if ns.Window then ns.Window.OnIncoming(key) end
        if entry.v == "p" and ns.Chat then ns.Chat.ShowIncoming(key, convo, entry) end
        if ns.Alarms then ns.Alarms.Incoming(convo, entry) end
    end
    Conv.Changed(key)
    return convo, key, entry
end

-- Stumm bzw. Alarm für ein Gespräch umschalten (Knöpfe im Gesprächsfenster, Menü der Gesprächsauswahl).
function Conv.SetFlag(key, flag, value)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or (flag ~= "muted" and flag ~= "alarm") then return end
    convo[flag] = value and true or nil
    if flag == "muted" and value then convo.unread = 0 end
    Conv.Changed(key)
end

---------------------------------------------------------------------------
-- Klasse des Partners (Klassenfarbe im Gesprächsfenster)
---------------------------------------------------------------------------

-- Klasse aus der GUID eines Ereignisses merken (Flüstern liefert sie mit).
function Conv.NoteClass(key, guid)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or convo.bn then return end
    convo.class = ezCore.ClassOfGUID(guid) or convo.class
end

-- Klasse des Partners: gemerkt, sonst aus Freundesliste, Battle.net oder Gilde (und dann gemerkt).
function Conv.ClassOf(convo)
    if not convo then return nil end
    if convo.class then return convo.class end
    local info = ns.Delivery and ns.Delivery.PartnerInfo(convo)
    if info and type(info.classFile) == "string" and info.classFile ~= "" then
        if not convo.bn then convo.class = info.classFile end
        return info.classFile
    end
    return nil
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

-- Passt das Gespräch zur Suche (query klein geschrieben)? Rückgabe: Anzahl passender Nachrichten,
-- die neueste davon und ob der Name passt.
function Conv.Search(convo, query)
    if not convo or type(query) ~= "string" or query == "" then return 0, nil, false end
    local byName = Conv.Display(convo):lower():find(query, 1, true) ~= nil
        or convo.name:lower():find(query, 1, true) ~= nil
    local count, last = 0, nil
    for _, msg in ipairs(convo.msgs) do
        if type(msg.m) == "string" and ns.PlainText(msg.m):lower():find(query, 1, true) then
            count = count + 1
            last = msg
        end
    end
    return count, last, byName
end

function Conv.MessageMatches(msg, query)
    if not query or query == "" then return true end
    return type(msg.m) == "string" and ns.PlainText(msg.m):lower():find(query, 1, true) ~= nil
end

function Conv.Cancel(key)
    local convo = ns.C and ns.C.convos[key]
    if not convo then return 0 end
    local count = 0
    for _, msg in ipairs(convo.msgs) do
        if msg.o and msg.s == "q" then
            msg.s = "x"
            count = count + 1
        end
    end
    if count > 0 then Conv.Changed(key) end
    return count
end

function Conv.Delete(key)
    if not ns.C then return end
    ns.C.convos[key] = nil
    Conv.Changed(key)
end

---------------------------------------------------------------------------
-- Verlaufspflege: Aufbewahrung nach Tagen, Verlauf eines Partners löschen oder kopieren
---------------------------------------------------------------------------

-- Aufbewahrung in Tagen für dieses Gespräch: eigene Wahl (Menü des Gesprächs), sonst die Einstellung keepDays.
-- 0 = nie nach Tagen kürzen (die Obergrenze „Nachrichten je Gespräch“ gilt immer).
function Conv.KeepDays(convo)
    local own = convo and tonumber(convo.keepDays)
    if own then return math.max(0, math.floor(own)) end
    return math.max(0, ns.Number("keepDays"))
end

-- Nachrichten, die älter sind als die Aufbewahrung, entfernen; wartende bleiben immer. Der Bereich „Gefiltert“
-- (Spam.lua) folgt der Einstellung keepDays. → Anzahl entfernter Nachrichten in Gesprächen
function Conv.Expire(now)
    if not ns.C then return 0 end
    now = now or time()
    if ns.Spam then ns.Spam.Expire(now) end
    local removed = 0
    for key, convo in pairs(ns.C.convos) do
        local days = Conv.KeepDays(convo)
        if days > 0 then
            local cutoff, kept = now - days * 86400, {}
            for _, msg in ipairs(convo.msgs) do
                if msg.s == "q" or (msg.t or now) >= cutoff then kept[#kept + 1] = msg end
            end
            if #kept < #convo.msgs then
                removed = removed + #convo.msgs - #kept
                convo.msgs = kept
                if (convo.unread or 0) > #kept then convo.unread = #kept end
                Conv.Changed(key)
            end
        end
    end
    return removed
end

-- Eigene Aufbewahrung eines Gesprächs setzen (nil = wie eingestellt). → Anzahl dabei entfernter Nachrichten
function Conv.SetKeepDays(key, days)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo then return 0 end
    convo.keepDays = days and math.max(0, math.floor(tonumber(days) or 0)) or nil
    local removed = Conv.Expire()
    Conv.Changed(key)
    return removed
end

-- Verlauf eines Partners löschen: das Gespräch bleibt (Stumm, Alarm, Aufbewahrung – auch über das Ausloggen hinaus,
-- Conv.Keeps), wartende Nachrichten auch.
-- → Anzahl gelöschter Nachrichten
function Conv.ClearHistory(key)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo then return 0 end
    local kept = {}
    for _, msg in ipairs(convo.msgs) do
        if msg.s == "q" then kept[#kept + 1] = msg end
    end
    local removed = #convo.msgs - #kept
    convo.msgs = kept
    convo.unread = 0
    Conv.Changed(key)
    return removed
end

-- Verlauf eines Gesprächs als reiner Text zum Kopieren (eine Zeile je Nachricht, ohne Farben und Links).
function Conv.CopyText(convo)
    if not convo then return "" end
    local lines, partner = {}, Conv.Display(convo)
    for _, msg in ipairs(convo.msgs) do
        local who = msg.o and ns.L.YOU or partner
        lines[#lines + 1] = ("[%s] %s: %s"):format(date(ns.L.DATE_YEAR .. " %H:%M", msg.t), who, ns.PlainText(msg.m or ""))
    end
    return table.concat(lines, "\n")
end

-- Ungefähre Größe des gespeicherten Verlaufs (für /ezchat diag): Gespräche, Nachrichten, Bytes (Text und
-- geschätzter Aufwand je Eintrag in der SavedVariables-Datei).
function Conv.StorageSize()
    local convos, msgs, bytes = 0, 0, 0
    for key, convo in pairs(ns.C and ns.C.convos or {}) do
        convos = convos + 1
        bytes = bytes + #key + #(convo.name or "") + 40
        for _, msg in ipairs(convo.msgs) do
            msgs = msgs + 1
            bytes = bytes + #(type(msg.m) == "string" and msg.m or "") + 30
        end
    end
    return convos, msgs, bytes
end

-- Verlauf löschen: alles außer wartenden Nachrichten, dazu der Bereich „Gefiltert“ (Spam.lua).
function Conv.ClearAll()
    if not ns.C then return end
    if ns.Spam then ns.Spam.Clear() end
    for key, convo in pairs(ns.C.convos) do
        local kept = {}
        for _, msg in ipairs(convo.msgs) do
            if msg.s == "q" then kept[#kept + 1] = msg end
        end
        convo.msgs = kept
        convo.unread = 0
        if #kept == 0 then ns.C.convos[key] = nil end
    end
    Conv.Changed(nil)
end

---------------------------------------------------------------------------
-- Flüstern mitschreiben
---------------------------------------------------------------------------

-- Absender/Empfänger eines Flüsterns → voller Name (Nachname notfalls ergänzt).
local function WhisperName(raw)
    local full = ns.FullName(raw)
    return full and ns.CompleteName(full)
end

-- Argument 12 der Flüster-Ereignisse ist die GUID des Partners (für die Klassenfarbe).
-- GUID je Gespräch, nur im Arbeitsspeicher: für Blizzards Spieler-Menü im Gesprächskopf (Window.PlayerMenu).
Conv.guids = {}

ns.On("CHAT_MSG_WHISPER", function(_, text, sender, _, _, _, flags, _, _, _, _, _, guid)
    if not ns.C or not ns.Usable(text, sender) or type(text) ~= "string" then return end
    ns.NoteRaw("whisper", sender)
    local full = WhisperName(sender)
    if not full then return end
    -- Spam (Spam.lua): still in den Bereich „Gefiltert“ – kein Gespräch, kein Ton, keine automatische Antwort
    local reason = ns.Spam and ns.Spam.Check(text, sender, guid, flags)
    if reason then return ns.Spam.Keep(full, text, reason) end
    local _, key = Conv.Add(full, false, { m = text })
    Conv.NoteClass(key, guid)
    if key and not ns.IsSecret(guid) and type(guid) == "string" then Conv.guids[key] = guid end
    if ns.Delivery then ns.Delivery.Online(Conv.KeyOf(full)) end
    if ns.Situation then ns.Situation.OnWhisper(key, full, false) end
end)

ns.On("CHAT_MSG_WHISPER_INFORM", function(_, text, target, _, _, _, _, _, _, _, _, _, guid)
    if not ns.C or not ns.Usable(text, target) or type(text) ~= "string" then return end
    ns.NoteRaw("inform", target)
    local full = WhisperName(target)
    if not full then return end
    local key = Conv.KeyOf(full)
    if ns.Situation and ns.Situation.TakeOwn(key, text) then
        Conv.Add(full, false, { m = text, o = true, a = true })   -- die automatische Antwort
    elseif not (ns.Delivery and ns.Delivery.OnInform(key, text)) then
        Conv.Add(full, false, { m = text, o = true })
    end
    Conv.NoteClass(key, guid)
end)

-- Battle.net: Absender kommt als Konto-ID (Argument 13), gespeichert wird der BattleTag.
ns.On("CHAT_MSG_BN_WHISPER", function(_, text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    if not ns.C or not ns.Usable(text) or type(text) ~= "string" then return end
    local tag = ns.BNTagOf(bnSenderID)
    if not tag then return end
    local _, key = Conv.Add(tag, true, { m = text, v = "b" })
    if ns.Delivery then ns.Delivery.Online(Conv.KeyOf(tag, true)) end
    if ns.Situation then ns.Situation.OnWhisper(key, tag, true, bnSenderID) end
end)

ns.On("CHAT_MSG_BN_WHISPER_INFORM", function(_, text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    if not ns.C or not ns.Usable(text) or type(text) ~= "string" then return end
    local tag = ns.BNTagOf(bnSenderID)
    if not tag then return end
    local key = Conv.KeyOf(tag, true)
    if ns.Situation and ns.Situation.TakeOwn(key, text) then
        Conv.Add(tag, true, { m = text, o = true, v = "b", a = true })   -- die automatische Antwort
        return
    end
    if ns.Delivery and ns.Delivery.OnInform(key, text) then return end
    Conv.Add(tag, true, { m = text, o = true, v = "b" })
end)

-- Gespräche aus 1.0.0 (Forever: nur Vorname mit Realm) auf volle Namen umstellen.
-- Die Gilde lädt ihr Roster erst nach dem Einloggen, darum auch danach noch einmal.
local function FixAll()
    if not ns.C then return end
    local keys = {}
    for key in pairs(ns.C.convos) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do Conv.Fix(key) end
end
ns.OnReady(FixAll)
ns.OnReady(function() Conv.Expire() end)   -- Aufbewahrung nach Tagen: beim Einloggen und beim Ausloggen
local lastFix = 0
ns.On("GUILD_ROSTER_UPDATE", function()
    if not ns.uniqueNames or not ns.C or GetTime() - lastFix < 60 then return end
    lastFix = GetTime()
    for _, convo in pairs(ns.C.convos) do
        if not convo.bn and ns.MissingSurname(convo.name) then return FixAll() end
    end
end)

-- Bleibt ein Gespräch ohne Nachrichten erhalten? Ja, wenn es eigene Schalter trägt: Stumm, Alarm oder eine eigene
-- Aufbewahrung (sonst wären sie nach „Verlauf dieses Partners löschen“ oder der Aufbewahrung beim Ausloggen weg).
function Conv.Keeps(convo)
    return convo ~= nil and (#convo.msgs > 0 or convo.muted == true or convo.alarm == true or convo.keepDays ~= nil)
end

-- Beim Ausloggen: Flüstern nur behalten, wenn "speichern" an ist – auch die gefilterten im Bereich „Gefiltert“.
-- Wartende Nachrichten, Briefe und Community-Nachrichten bleiben immer.
function Conv.Purge()
    if not ns.C then return end
    Conv.Expire()
    if not ns.S.historyWhisper and ns.Spam then ns.Spam.Clear() end
    for key, convo in pairs(ns.C.convos) do
        local keep
        if convo.bn then keep = ns.S.historyBN else keep = ns.S.historyWhisper end
        if not keep then
            local kept = {}
            for _, msg in ipairs(convo.msgs) do
                if msg.s == "q" or msg.v == "p" or msg.v == "c" then kept[#kept + 1] = msg end
            end
            convo.msgs = kept
        end
        if not Conv.Keeps(convo) then ns.C.convos[key] = nil end
    end
end
ns.OnLogout(Conv.Purge)
