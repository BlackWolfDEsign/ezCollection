local _, ns = ...
local L = ns.L

-- Verhalten je Lage (Wunsch des Nutzers vom 15.11.2026; eigener Code, Leitlinie 10). Vier Lagen, die erste
-- zutreffende gilt:
--   combat    im Kampf
--   instance  in einem Dungeon, Schlachtzug, Szenario, auf einem Schlachtfeld oder in der Arena
--   away      abwesend oder „nicht stören“ (Blizzards /afk bzw. /dnd)
--   rest      in einer Stadt oder einem Gasthaus (Erholungsgebiet)
-- Ohne Lage gilt das gewohnte Verhalten. Je Lage (Einstellungen auf ezChats Seite, Abschnitt „Verhalten je Lage“):
--   sitPopup<Lage>  Gesprächsfenster bei neuer Nachricht öffnen: "yes" sofort, "no" nie, "after" nach dem Kampf
--                   (ab Werk "no"; ohne Lage gilt sitPopupOther – seit der Prüfung der Einstellungen vom 19.11.2026
--                   sind die fünf Auswahlen der Schalter, einen Hauptschalter gibt es nicht mehr)
--   sitTone<Lage>   zusätzlich ezChats Ton bei neuem Flüstern (Blizzards eigener Flüster-Ton bleibt, wie er ist)
--   sitAlarm<Lage>  ezChats Alarme (Kanäle, Partner, Hervorheben, Briefe) dürfen klingeln
--   reply<Lage>     automatische Antwort, Text replyText<Lage> (leer = Vorgabe in der Sprache des Clients)
-- Automatische Antwort: höchstens einmal je Partner in replyMinutes Minuten; nie auf Gefiltertes (Spam.lua), nie an
-- Battle.net-Konten außerhalb der eigenen Freundesliste, an Fremde nur mit replyStrangers; nie während Blizzards
-- Chat-Sperre (ezCore.SendChat prüft sie – Flüstern ist keine geschützte Aktion, im Kampf also erlaubt). Abwesend
-- (/afk, /dnd) antwortet Blizzard selbst auf Flüstern: ezChat antwortet dann nur über Battle.net, nie doppelt.

local Situation = {}
ns.Situation = Situation

Situation.ORDER = { "combat", "instance", "away", "rest" }
local SUFFIX = { combat = "Combat", instance = "Instance", away = "Away", rest = "Rest" }
Situation.SUFFIX = SUFFIX
Situation.POPUP = { "yes", "no", "after" }
local INSTANCE_KINDS = { party = true, raid = true, scenario = true, pvp = true, arena = true }

local function Flag(fn, ...)
    return ezCore.Bool(ezCore.Call(rawget(_G, fn), ...), false)
end

-- Die gerade geltende Lage: "combat", "instance", "away", "rest" oder nil.
function Situation.Current()
    if ns.InCombat() then return "combat" end
    local inside, kind = ezCore.InInstance()
    if inside == true and kind and INSTANCE_KINDS[kind] then return "instance" end
    if Flag("UnitIsAFK", "player") or Flag("UnitIsDND", "player") then return "away" end
    if Flag("IsResting") then return "rest" end
    return nil
end

-- Einstellung einer Lage: Setting(sit, "sitPopup") → ns.S.sitPopupCombat …
function Situation.Setting(sit, prefix)
    local suffix = sit and SUFFIX[sit]
    if not (suffix and ns.S) then return nil end
    return ns.S[prefix .. suffix]
end

-- Fenster bei neuer Nachricht: "yes", "no" oder "after" (nach dem Kampf). Ohne Lage gilt „Sonst“ (sitPopupOther).
-- Außerhalb des Kampfes heißt „nach dem Kampf“ sofort; ein unbekannter Wert heißt „nicht öffnen“ (ab Werk).
function Situation.PopupMode()
    local sit = Situation.Current()
    local mode
    if sit then
        mode = Situation.Setting(sit, "sitPopup")
    else
        mode = ns.S and ns.S.sitPopupOther
    end
    if mode ~= "yes" and mode ~= "after" then mode = "no" end
    if mode == "after" and not ns.InCombat() then mode = "yes" end
    return mode, sit
end

-- Dürfen ezChats Alarme gerade klingeln?
function Situation.AlarmsAllowed()
    local sit = Situation.Current()
    if not sit then return true end
    return Situation.Setting(sit, "sitAlarm") ~= false
end

-- Neue Nachricht im Gespräch (Alarms.Incoming): in dieser Lage zusätzlich ezChats Ton bei Flüstern?
function Situation.Incoming(convo, entry)
    if not convo or convo.muted or (entry.v ~= nil and entry.v ~= "b") then return false end
    local sit = Situation.Current()
    if not (sit and Situation.Setting(sit, "sitTone")) then return false end
    return ns.Alarms.Ring(nil, true)
end

---------------------------------------------------------------------------
-- Automatische Antwort
---------------------------------------------------------------------------

local replied = {}   -- [Schlüssel] = time() der letzten automatischen Antwort (nur diese Sitzung)
local own = {}       -- [Schlüssel] = Text der automatischen Antwort, bis Blizzard sie bestätigt („An X: …“)

function Situation.ReplyText(sit)
    local text = ns.Trim(tostring(Situation.Setting(sit, "replyText") or ""))
    if text ~= "" then return text end
    return L["REPLY_DEFAULT_" .. tostring(sit)]
end

local function Same(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    return (ns.Trim(a):gsub("%s+", " ")) == (ns.Trim(b):gsub("%s+", " "))
end

-- War diese Bestätigung („An X: …“) die automatische Antwort? Dann true (einmal).
function Situation.TakeOwn(key, text)
    if key and own[key] and Same(own[key], text) then
        own[key] = nil
        return true
    end
    return false
end

-- Gedächtnis der automatischen Antwort leeren (Tests).
function Situation.ResetReplies() wipe(replied) wipe(own) end

-- Eingehendes Flüstern (Conversations.lua). name: voller Name bzw. BattleTag; accountID nur bei Battle.net.
-- → true, wenn eine Antwort gesendet wurde.
function Situation.OnWhisper(key, name, bn, accountID)
    if not (key and ns.S) then return false end
    local sit = Situation.Current()
    if not (sit and Situation.Setting(sit, "reply")) then return false end
    if sit == "away" and not bn then return false end          -- Blizzards eigene AFK/DND-Antwort: nicht doppelt
    if bn then
        if not (accountID and ns.BNInfoByID(accountID)) then return false end   -- nie an Battle.net-Fremde
    elseif not ns.S.replyStrangers and not (ns.Spam and ns.Spam.Known(name)) then
        return false
    end
    local now = time()
    local last = replied[key]
    if last and now - last < ns.Number("replyMinutes") * 60 then return false end
    if ns.InLockdown() then return false end                    -- Chat gesperrt: nichts senden, nichts nachholen
    local text = Situation.ReplyText(sit)
    if type(text) ~= "string" or text == "" then return false end
    own[key] = text
    local sent
    if bn then sent = ns.SendBNWhisper(accountID, text) else sent = ns.SendWhisper(ns.TellName(name), text) end
    if not sent then
        own[key] = nil
        return false
    end
    replied[key] = now
    return true
end

-- Antworttext einer Lage bearbeiten (Knöpfe auf der Einstellungsseite). Leer zurück zur Vorgabe.
function Situation.EditReply(sit)
    ezCore.AskText(L.REPLY_PROMPT:format(L["SIT_" .. sit]), Situation.ReplyText(sit), function(text)
        ns.SetSetting("replyText" .. SUFFIX[sit], text or "")
        ns.Print(L.REPLY_SET:format(L["SIT_" .. sit], Situation.ReplyText(sit)))
    end, 200)
end

-- Auswahl je Lage für die Einstellungsseite: { { wert, text } … }. noAfter: ohne „nach dem Kampf“ – für „Sonst“
-- (ohne Lage gibt es keinen Kampf, der Kampf ist selbst eine Lage; Gegenprüfung der Einstellungen vom 19.11.2026) und
-- seit dem 20.11.2026 auch für Dungeon, Abwesend und Stadt: sie gelten nur außerhalb des Kampfes (Current prüft den
-- Kampf zuerst), „nach dem Kampf“ hieß dort „sofort“ (code-reviewer 20.11.2026).
function Situation.PopupValues(noAfter)
    local values = {}
    for _, value in ipairs(Situation.POPUP) do
        if not (noAfter and value == "after") then values[#values + 1] = { value, L["SIT_POPUP_" .. value] } end
    end
    return values
end

-- Hinweis am Chatfenster beim Flüstern an andere (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026,
-- T1-3, Entscheidung 2 des Nutzers: auch für Abläufe, die nie ab Werk an waren, sofern sie senden). Die automatische
-- Antwort flüstert ohne Klick zurück; eine Zeile für alle vier Lagen. „Einschalten“ schaltet Kampf und
-- Dungeon/Schlachtzug ein (dort kann der Spieler gerade nicht antworten); Abwesend und Stadt/Gasthaus bleiben eigene
-- Schalter auf der Einstellungsseite (die Zeile nennt es).
Situation.REPLY_ON = { "replyCombat", "replyInstance" }
function Situation.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezChat.reply", {
        owner = "ezChat",
        window = "chat",
        label = function() return L.SECTION_REPLY end,
        what = function() return L.OPTIN_reply end,
        isOn = function()
            if not ns.S then return false end
            for _, suffix in pairs(SUFFIX) do
                if ns.S["reply" .. suffix] == true then return true end
            end
            return false
        end,
        enable = function()
            for _, key in ipairs(Situation.REPLY_ON) do ns.SetSetting(key, true) end
            return ns.S.replyCombat == true and ns.S.replyInstance == true
        end,
    })
end
Situation.RegisterOptInHint()

-- Für /ezchat status: die gerade geltende Lage.
ns.AddStatusLine(function()
    if not ns.S then return nil end
    local sit = Situation.Current()
    return L.STATUS_SITUATION:format(sit and L["SIT_" .. sit] or L.SIT_NONE)
end)

