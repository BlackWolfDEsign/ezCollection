local _, ns = ...
local Conv = ns.Conv

-- „tippt gerade“ und Ort teilen – nur zwischen zwei ezChat-Nutzern (Wunsch des Nutzers vom 15.11.2026; eigener
-- Code, Leitlinie 10). Weg: Blizzards Addon-Nachrichten im Flüsterkanal
-- (C_ChatInfo.RegisterAddonMessagePrefix/SendAddonMessage, Präfix „ezChat“). Ob der Forever-Client sie im
-- Flüsterkanal erlaubt, zeigt erst das Spiel: /ezchat diag nennt unter addonMessages, ob das Präfix angemeldet
-- ist und wie viele Meldungen gesendet, abgelehnt und empfangen wurden.
--
-- Datenschutz – ab Werk beides aus (Empfehlung umgesetzt, Antwort offen):
--   shareTyping  „tippt …“ senden und zeigen. Gesendet wird nur, solange du im Gesprächsfenster tippst, höchstens
--                alle 4 Sekunden, nur an Partner, die laut Freundesliste, Gilde oder Battle.net gerade online sind
--                (sonst meldet der Client „Spieler nicht gefunden“)
--   shareZone    Ort (Gebiet) austauschen – nur, wenn BEIDE es eingeschaltet haben: Wer es an hat, fragt beim
--                Öffnen des Gesprächs („Z?“); nur wer es selbst an hat, antwortet mit seinem Gebiet („Z:Gebiet“);
--                eine Antwort zeigt nur, wer es an hat. Höchstens einmal je Minute und Partner
-- Nie im Kampf, nie während Blizzards Chat-Sperre oder einer Addon-Sperre für Chat oder Bosskampf.
-- Empfangene Texte gelten als fremde Daten: nur das Gebiet, ohne Steuerzeichen, höchstens 60 Zeichen.

local Typing = {}
ns.Typing = Typing

Typing.PREFIX = "ezChat"
local SEND_EVERY, SHOW_FOR, ZONE_EVERY, ZONE_FOR = 4, 7, 60, 600
local typingUntil, zones = {}, {}             -- [Schlüssel] = GetTime() bis wann „tippt“; { name, at }
local lastTyping, lastZone, lastAsk = {}, {}, {}
Typing.stats = { registered = "-", sent = 0, refused = 0, received = 0, last = "-" }

local function Refresh(key)
    if ns.Window and ns.Window.RefreshHint then ns.Window.RefreshHint(key) end
end

-- Präfix anmelden. Neuere Clients antworten mit einer Zahl (0 = angemeldet), ältere mit true/false.
function Typing.Register()
    local api = rawget(_G, "C_ChatInfo")
    local fn = type(api) == "table" and api.RegisterAddonMessagePrefix
    if type(fn) ~= "function" then
        Typing.stats.registered = "fehlt"
        return false
    end
    local ok, result = pcall(fn, Typing.PREFIX)
    local good = ok and (result == nil or result == true or result == 0)
    Typing.stats.registered = good and "ja" or ("nein " .. tostring(result))
    return good
end

-- Darf jetzt eine Addon-Nachricht an diesen Partner gehen?
function Typing.CanSend(convo)
    if not convo or convo.bn or not ns.C then return false end
    if ns.InCombat() or ns.InLockdown() then return false end
    if ezCore.RestrictionActive("chat") == true or ezCore.RestrictionActive("encounter") == true then return false end
    return ns.Delivery.IsOnline(convo) == true
end

-- Addon-Nachricht senden; neuere Clients antworten mit einer Zahl (0 = gesendet). → true, wenn gesendet
function Typing.Send(convo, text)
    if not Typing.CanSend(convo) then return false end
    local api = rawget(_G, "C_ChatInfo")
    local fn = type(api) == "table" and api.SendAddonMessage
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, Typing.PREFIX, text, "WHISPER", ns.TellName(convo.name))
    local good = ok and (result == nil or result == true or result == 0)
    if good then
        Typing.stats.sent = Typing.stats.sent + 1
    else
        Typing.stats.refused = Typing.stats.refused + 1
        Typing.stats.last = ok and tostring(result) or "Fehler"
    end
    return good
end

-- Eigenes Gebiet (Blizzards Gebietsname), ohne Steuerzeichen.
local function OwnZone()
    local zone = ezCore.Call(rawget(_G, "GetRealZoneText")) or ezCore.Call(rawget(_G, "GetZoneText"))
    if ns.IsSecret(zone) or type(zone) ~= "string" or zone == "" then return nil end
    return ns.Truncate((zone:gsub("|", "")), 60)
end

-- Im Gesprächsfenster wird getippt (Eingabefeld, nur echte Eingaben).
function Typing.OnEdit(key, text)
    if not (ns.S and ns.S.shareTyping) or type(text) ~= "string" or ns.Trim(text) == "" then return false end
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or GetTime() - (lastTyping[key] or -SEND_EVERY) < SEND_EVERY then return false end
    if not Typing.Send(convo, "T") then return false end
    lastTyping[key] = GetTime()
    return true
end

local function SendZone(key, convo)
    if GetTime() - (lastZone[key] or -ZONE_EVERY) < ZONE_EVERY then return false end
    local zone = OwnZone()
    if not zone or not Typing.Send(convo, "Z:" .. zone) then return false end
    lastZone[key] = GetTime()
    return true
end

-- Gespräch geöffnet bzw. gewählt: nach dem Ort fragen, wenn du ihn teilst (höchstens einmal je Minute und Partner).
function Typing.AskZone(key)
    if not (ns.S and ns.S.shareZone) then return false end
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or GetTime() - (lastAsk[key] or -ZONE_EVERY) < ZONE_EVERY then return false end
    if not Typing.Send(convo, "Z?") then return false end
    lastAsk[key] = GetTime()
    return true
end

-- Eine Addon-Nachricht von key. → was sie bewirkt hat ("typing", "ask", "zone") oder nil
function Typing.Receive(key, text)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or type(text) ~= "string" then return nil end
    Typing.stats.received = Typing.stats.received + 1
    if text == "T" then
        if not ns.S.shareTyping then return nil end
        typingUntil[key] = GetTime() + SHOW_FOR
        Refresh(key)
        C_Timer.After(SHOW_FOR + 0.1, function() Refresh(key) end)
        return "typing"
    end
    if not ns.S.shareZone then return nil end
    if text == "Z?" then
        SendZone(key, convo)
        return "ask"
    end
    local zone = text:match("^Z:(.+)$")
    if not zone then return nil end
    zone = ns.Truncate(ns.Trim((ns.PlainText(zone):gsub("[%c|]", ""))), 60)   -- Farbcodes, Links, Symbole weg
    if zone == "" then return nil end
    zones[key] = { name = zone, at = GetTime() }
    SendZone(key, convo)   -- der Partner teilt seinen Ort: deinen zurück (höchstens einmal je Minute)
    Refresh(key)
    return "zone"
end

-- Für die Anzeige unter dem Verlauf: tippt der Partner gerade? Wo ist er (laut ezChat)?
function Typing.IsTyping(key)
    return ns.S ~= nil and ns.S.shareTyping == true and key ~= nil and (typingUntil[key] or 0) > GetTime()
end

function Typing.Zone(key)
    local entry = key and zones[key]
    if not (entry and ns.S and ns.S.shareZone) or GetTime() - entry.at > ZONE_FOR then return nil end
    return entry.name
end

function Typing.Clear(key)
    if key then typingUntil[key] = nil end
end

-- CHAT_MSG_ADDON: Präfix, Text, Kanal, Absender. Nur Flüstern, nur bekannte Gespräche, nie von dir selbst.
ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if prefix ~= Typing.PREFIX or channel ~= "WHISPER" then return end
    if not ns.C or not ns.Usable(text, sender) or type(sender) ~= "string" then return end
    local full = ns.FullName(sender)
    if not full or ns.IsSelf(full) then return end
    Typing.Receive(Conv.KeyOf(ns.CompleteName(full)), text)
end)

-- Eine echte Nachricht des Partners beendet „tippt …“.
ns.On("CHAT_MSG_WHISPER", function(_, text, sender)
    if not ns.Usable(text, sender) or type(sender) ~= "string" then return end
    local full = ns.FullName(sender)
    if not full then return end
    local key = Conv.KeyOf(ns.CompleteName(full))
    if typingUntil[key] then
        Typing.Clear(key)
        Refresh(key)
    end
end)

-- Hinweis an Blizzards Freundesliste, an der das Gesprächsfenster andockt (ezCores Hinweis-Helfer, einmal je Account;
-- Gesamtreview 18.11.2026, T1-3, Entscheidung 2 des Nutzers): „tippt …“ und Ort schicken ohne Klick Addon-Nachrichten
-- an den Partner. Beide waren nie ab Werk an; sie melden sich trotzdem einmal.
function Typing.RegisterOptInHints()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    local a = Hint.RegisterSetting("ezChat", ns, "shareTyping", { window = "friends" })
    local b = Hint.RegisterSetting("ezChat", ns, "shareZone", { window = "friends" })
    return a and b
end
Typing.RegisterOptInHints()

ns.OnReady(function() Typing.Register() end)
