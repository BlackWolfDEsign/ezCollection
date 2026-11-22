local ADDON, ns = ...
local L = ns.L

ns.TAG = "[ezChat]"   -- Betreff-Kennung der Briefe

ns.DEFAULTS = {
    -- Verlauf
    historyGuild = true,
    historyParty = true,
    historyWhisper = true,
    historyBN = true,
    historySay = false,
    restore = false,      -- Verlauf beim Einloggen: ab Werk aus (Entscheidung des Nutzers vom 20.11.2026, ns.MigrateRestoreOff)
    keepCount = 100,      -- gespeicherte Nachrichten pro Kanal bzw. Gesprächspartner
    restoreCount = 25,    -- beim Einloggen höchstens so viele Zeilen pro Chatfenster
    keepDays = 0,         -- Gespräche nach so vielen Tagen kürzen (0 = nie; je Partner abweichend: convo.keepDays)
    -- Offline-Nachrichten
    offlineQueue = true,
    catchChatWhispers = false, -- ab Werk aus: sendet ohne Klick nach (Gesamtreview 18.11.2026, T1-4; Entscheidung 3 des
                          -- Nutzers) – gespeichertes „an“ einmal umgestellt (ns.MigrateWhisperOptIn), Hinweis am Chat
    retryWhisper = true,
    mailDelivery = false, -- ab Werk aus: Porto ohne Klick (Prüfung 17.11.2026, Risiko 8; Antwort des Nutzers 17.11.2026: Opt-in) –
                          -- bestehende Spieler einmal umgestellt, mit Hinweis am Briefkasten (ns.MigrateMailOptIn, Mail.lua)
    mailImport = true,
    community = true,
    -- Chat und Fenster
    chatButtons = true,   -- ezChat-Symbole in der Knopfleiste des Chatfensters
    chatView = true,      -- Gesprächsauswahl in der Reiterleiste, Gespräch im Chatfenster
    friendsDock = true,   -- Seitenreiter an Blizzards Freundesliste: Gesprächsfenster angedockt daneben
    partnerInfo = true,   -- Stufe, Klasse und Gebiet des Partners im Gesprächskopf
    soundLetters = true,  -- Ton bei Briefen und Community-Nachrichten
    -- Blizzards Chatfenster (ChatFormat.lua)
    links = true,         -- Internetadressen anklickbar, ein Klick zeigt sie zum Kopieren
    copyChat = true,      -- Chattext mit der Maus markieren und kopieren
    shortChannels = false,-- Kanalnamen ohne Gebiet („2. Handel“ statt „2. Handel - Stadt“)
    noFade = false,       -- Chattext nicht ausblenden
    arrowKeys = false,    -- Pfeiltasten im Eingabefeld ohne Alt (Leatrix Plus: ns.HANDLED_BY)
    -- Hervorheben und Alarme (ChatFormat.lua, Alarms.lua)
    highlight = true,     -- eigenen Namen und Stichwörter farbig hervorheben
    highlightSound = true,
    keywords = "",        -- Stichwörter, durch Komma getrennt
    alarmGuild = false,
    alarmOfficer = false,
    alarmParty = false,
    alarmRaid = false,
    alarmInstance = false,
    alarmSay = false,
    alarmCommunity = false,
    alarmFlash = true,    -- bei Alarm und Hervorhebung das Spielsymbol in der Taskleiste blinken lassen
    alarmTone = "MAP_PING",
    -- Spam-Filter für Flüstern von Fremden (Spam.lua; Wunsch des Nutzers vom 15.11.2026)
    spamFilter = true,    -- Empfehlung umgesetzt, Antwort offen: an – Gefiltertes geht nie verloren („Gefiltert“)
    spamBusy = false,     -- in Dungeon, Schlachtzug und Kampf nur Freunde, Gilde und Gruppe
    spamLevel = 3,        -- Absender bis zu dieser Stufe filtern, wenn die Stufe lesbar ist (0 = aus)
    spamWords = "gold, cheap, billig, discount, rabatt, usd, €, $, boost, powerlevel, delivery, lieferung, sale",
    -- Verhalten je Lage (Situation.lua): Fenster öffnen "yes"/"no"/"after", Ton, Alarme, automatische Antwort
    -- Fenster bei neuer Nachricht je Lage, ab Werk „nicht öffnen“ (Prüfung der Einstellungen vom 19.11.2026, Nr. 63/64:
    -- die Auswahlen sind der Schalter, der alte Hauptschalter openOnWhisper ist weg; sitPopupOther gilt ohne Lage).
    -- Namen in Klassenfarbe und Link-Tooltip im Gespräch sind immer an (Nr. 23/24). Umstellung: ns.MigrateSettings1911.
    sitPopupCombat = "no",
    sitPopupInstance = "no",
    sitPopupAway = "no",
    sitPopupRest = "no",
    sitPopupOther = "no",
    -- Ton bei Flüstern nur noch abwesend (Entscheidung des Nutzers vom 21.11.2026: „Nur „Abwesend: Ton“ (Empfohlen)“);
    -- die Schalter für Kampf, Dungeon und Stadt sind weg, gespeicherte Werte räumt ns.MigrateToneAway weg
    sitToneAway = false,
    sitAlarmCombat = false,   -- Empfehlung umgesetzt, Antwort offen: im Kampf klingeln ezChats Alarme nicht
    sitAlarmInstance = true,
    sitAlarmAway = true,
    sitAlarmRest = true,
    replyCombat = false,      -- automatische Antworten ab Werk aus: ezChat schreibt nur, wenn du es einschaltest
    replyInstance = false,
    replyAway = false,
    replyRest = false,
    replyTextCombat = "",     -- leer: Vorgabe in der Sprache des Clients (L.REPLY_DEFAULT_<Lage>)
    replyTextInstance = "",
    replyTextAway = "",
    replyTextRest = "",
    replyMinutes = 30,        -- höchstens eine automatische Antwort je Partner in so vielen Minuten
    replyStrangers = false,   -- auch Fremden antworten (sonst nur Freunden, Gilde, Gruppe, bekannten Gesprächen)
    -- Mit anderen ezChat-Nutzern (Typing.lua): ab Werk aus (Datenschutz; Empfehlung umgesetzt, Antwort offen)
    shareTyping = false,
    shareZone = false,
    -- Erweitert
    diagPlain = false,    -- Diagnose (/ezchat diag) speichert Namen im Klartext statt unkenntlich (ns.MaskName)
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
-- risk hier: weitere automatische Antworten senden ohne Klick (an Fremde auch ohne Bekanntschaft)
-- choice hier (Spieltest 20.11.2026, Knopf mit „o fehlt“, wörtlich „mh was soll das sein“): nur Darstellung des Chats – alte Zeilen beim Einloggen zeigen (restore),
-- Kanalnamen kürzen, Text nicht verblassen lassen
ns.AGREE = {
    historySay = "on", restore = "choice", shortChannels = "choice", noFade = "choice", arrowKeys = "on", replyInstance = "risk",
    replyRest = "risk", replyStrangers = "risk", alarmGuild = "choice", alarmOfficer = "choice",
    alarmParty = "choice", alarmRaid = "choice", alarmInstance = "choice", alarmSay = "choice",
    alarmCommunity = "choice", spamBusy = "choice",
    sitToneAway = "choice", sitAlarmCombat = "choice", diagPlain = "choice",
}

-- „Alles sichern“ (ezCore/Backup.lua) nimmt diese Einstellungen nicht mit: Stichwörter sind frei eingegebener Text
-- und können Namen von Mitspielern tragen – ezCores Filter kennt nur die eigenen Charaktere. Ebenso die Texte der
-- automatischen Antworten.
ns.EXPORT_SKIP = { keywords = true, replyTextCombat = true, replyTextInstance = true, replyTextAway = true,
    replyTextRest = true }

-- Schalter für Einstellungen und Slash-Befehle: Schlüssel, deutscher Befehl, Abschnitt, en = englischer Befehl
-- (Core.HandleToggle versteht beide; die englische Hilfe nennt die englischen Wörter – Gesamtreview T10-1).
ns.TOGGLES = {
    { "historyGuild", "gilde", "history", en = "guild" },
    { "historyParty", "gruppe", "history", en = "party" },
    { "historyWhisper", "fluestern", "history", en = "whisper" },
    { "historyBN", "bnet", "history", en = "bnet" },
    { "historySay", "sagen", "history", en = "say" },
    { "restore", "wiederherstellen", "history", en = "restore" },
    { "offlineQueue", "offline", "offline", en = "offline" },
    { "catchChatWhispers", "chat", "offline", en = "chat" },
    { "retryWhisper", "nachhaken", "offline", en = "retry" },
    { "mailDelivery", "briefe", "offline", en = "letters" },
    { "mailImport", "posteingang", "offline", en = "inbox" },
    { "community", "community", "offline", en = "community" },
    { "chatView", "auswahl", "window", en = "selection" },
    { "chatButtons", "symbole", "window", en = "icons" },
    { "friendsDock", "freundesliste", "window", en = "friendslist" },
    { "partnerInfo", "info", "window", en = "info" },
    -- Ton bei Briefen und Community-Nachrichten steht bei den Alarmen (Prüfung der Einstellungen vom 19.11.2026)
    { "soundLetters", "briefton", "alarm", en = "lettersound" },
    { "links", "links", "chat", en = "links" },
    { "copyChat", "kopieren", "chat", en = "copy" },
    { "shortChannels", "kanalnamen", "chat", en = "channelnames" },
    { "noFade", "sichtbar", "chat", en = "visible" },
    { "arrowKeys", "pfeiltasten", "chat", en = "arrowkeys" },
    { "highlight", "hervorheben", "highlight", en = "highlight" },
    { "highlightSound", "hervorhebton", "highlight", en = "highlightsound" },
    { "alarmGuild", "alarmgilde", "alarm", en = "alertguild" },
    { "alarmOfficer", "alarmoffiziere", "alarm", en = "alertofficer" },
    { "alarmParty", "alarmgruppe", "alarm", en = "alertparty" },
    { "alarmRaid", "alarmraid", "alarm", en = "alertraid" },
    { "alarmInstance", "alarminstanz", "alarm", en = "alertinstance" },
    { "alarmSay", "alarmsagen", "alarm", en = "alertsay" },
    { "alarmCommunity", "alarmcommunity", "alarm", en = "alertcommunity" },
    { "alarmFlash", "blinken", "alarm", en = "flash" },
    { "spamFilter", "spam", "spam", en = "spam" },
    { "spamBusy", "spambeschaeftigt", "spam", en = "spambusy" },
    { "sitToneAway", "lagetonweg", "situation", en = "sittoneaway" },
    { "sitAlarmCombat", "lagealarmkampf", "situation", en = "sitalertcombat" },
    { "sitAlarmInstance", "lagealarminstanz", "situation", en = "sitalertinstance" },
    { "sitAlarmAway", "lagealarmweg", "situation", en = "sitalertaway" },
    { "sitAlarmRest", "lagealarmstadt", "situation", en = "sitalertcity" },
    { "replyCombat", "antwortkampf", "reply", en = "replycombat" },
    { "replyInstance", "antwortinstanz", "reply", en = "replyinstance" },
    { "replyAway", "antwortweg", "reply", en = "replyaway" },
    { "replyRest", "antwortstadt", "reply", en = "replycity" },
    { "replyStrangers", "antwortfremde", "reply", en = "replystrangers" },
    { "shareTyping", "tippen", "peers", en = "typing" },
    { "shareZone", "ort", "peers", en = "zone" },
}

-- Töne für Alarme und Hervorhebungen (Schlüssel in Blizzards SOUNDKIT).
ns.TONES = { "MAP_PING", "TELL_MESSAGE", "UI_BNET_TOAST", "READY_CHECK", "RAID_WARNING" }

-- Rücksicht auf fremde Addons (Leitlinie 9): Schalter → Funktion in ezCore (Core.WhoHandles, Liste im Kopf
-- von ezCore/OtherAddOns.lua, Begründungen in docs/fremd-addons.md). Übernimmt ein laufendes Addon die
-- Funktion, hält sich ezChat dort zurück (ns.Active) und nennt es am Schalter.
ns.HANDLED_BY = {
    restore = "chatHistory",          -- Forever Tweaks holt den Chat nach dem Laden selbst zurück
    noFade = "chatFade",              -- Forever Tweaks lässt den Chat nach 30 Sekunden verblassen, Leatrix Plus „Disable chat fade“
    arrowKeys = "chatArrows",         -- Leatrix Plus „Use arrow keys in chat“
    links = "chatLinks",              -- Prat, Chatter, Better Forever Chat (im Gesprächsfenster bleiben ezChats Links)
    copyChat = "chatCopy",            -- Prat, Chatter, Better Forever Chat
    shortChannels = "chatChannelNames", -- Prat, Chatter
    highlight = "chatHighlight",      -- Prat
    highlightSound = "chatHighlight",
    openOnWhisper = "whisperWindows", -- WIM öffnet eigene Flüsterfenster (je Lage: Situation.lua; seit 19.11.2026 nur
                                      -- noch Name der Funktion, kein Schalter: Window.PopupAllowed)
    spamFilter = "whisperWindows",    -- WIM filtert Flüstern selbst („Filtering“): ezChat legt dann nichts ab
}
-- Nur ein Hinweis am Schalter, ezChat bleibt an.
ns.HINT_BY = {
    chatView = "chatStyle",           -- Forever Tweaks zeigt die Chat-Reiter erst beim Überfahren
    linkTooltip = "chatLinkTooltip",  -- Prat zeigt Link-Tooltips in Blizzards Chatfenstern; ezChats gilt nur im Gesprächsfenster
                                      -- (seit 19.11.2026 immer an, kein Schalter: Hinweis im Tooltip der Überschrift
                                      -- „Gesprächsfenster“, Options.lua, und in ezCores Übersicht)
    -- WIM: ob es selbst automatisch antwortet, ist nicht öffentlich beschrieben – nur ein Hinweis, damit niemand
    -- doppelt antwortet
    replyCombat = "whisperWindows",
    replyInstance = "whisperWindows",
    replyAway = "whisperWindows",
    replyRest = "whisperWindows",
}

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore

-- Fehler zusätzlich in ezChatDB.errors (die letzten 20) für /ezchat diag – auch ohne Bildschirm lesbar. Der Zeitpunkt
-- steht als „2026-11-18 14:05:09“ davor (ezCore.DateText "isoSec", in jeder Spielsprache gleich und in der Datei lesbar;
-- vorher fest deutsch „18.11. 14:05:09“, T16-NZ5). Ältere Einträge bleiben, wie sie sind.
local function KeepError(text)
    if type(ezChatDB) ~= "table" then return end
    local list = ezChatDB.errors or {}
    ezChatDB.errors = list
    table.insert(list, 1, Core.DateText(Core.Now(), "isoSec") .. " " .. tostring(text))
    for i = #list, 21, -1 do list[i] = nil end
end

-- Print, Error (an Blizzards Fehleranzeige, ezCore-Fehlerliste und ezChatDB.errors), On, OnReady,
-- OnLogout, OnSettingChanged, SettingChanged, SetSetting … und das Gerüst aus ezCore (Core.ModuleScaffold):
--   db/tables/onLoad  ezChatDB anlegen (auch nach einer beschädigten Datei), Standardwerte auffüllen, ns.db und ns.S
--   slash             /ezchat mit „optionen“, „status“, „hilfe“ und den Schaltern aus ns.TOGGLES; ezChats eigene
--                     Wörter zuerst (ns.SlashExtra, unten); der Kurzbefehl /ezc nur, wenn er frei ist
-- Der Login bleibt hier (ns.C je Charakter, alter Schlüssel), der eigene Fehlerspeicher über onError.
Core.NewModule(ADDON, ns, {
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.SlashCmd, Core.OptInOnce, Core.Ticker, Core.Time.FromServer
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",   -- Mindestversion von ezCore (V-006, VP-41): ns.OtherFor, Core.UnitIs, Abkürzungen des Gerüsts;
    -- 1.12.0 und needs: Farb-Rollen des Design-Systems (Welle 22; orange, bnet, link aus Welle 23a)
    needs = { "Style.Color", "Style.COLOR", "Style.ICON", "Style.AllText", "Menu.AllToggle", "ColorCode", "PREFIX_COLOR",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Takt mit Griff (T7-3)
        "Ticker",
        "Grey", "Gold", "Style.COLOR.orange", "Style.COLOR.bnet", "Style.COLOR.link",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23: Spieler-Menüs aus ezCores Liste (Chat.lua); Kontakte mit Quelle je Angabe und „zuletzt online“
        -- der Gilde (Delivery.lua)
        "Menu.PlayerMenus", "contactFrom", "contactLastOnline",
        -- Gesamtreview 18.11.2026 (T16-NZ4, T16-NZ5): Zeitbasis (Community.lua) und Datum der Fehlerliste (KeepError)
        "Time",
        -- Gesamtreview 18.11.2026 (P13 Teil D2): Addon-Fach, Befehl ohne Wort, Zurücksetzen, Menüeintrag, Weg
        "compartmentMain", "slashMain", "SlashCmd", "SlashWord", "Menu.Settings", "SettingsPathText",
        -- Tooltip am gesperrten Knopf „Senden“ (T9-7)
        "Toolbar.ShowTipWhileDisabled",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound", "OptInOnce", "RoleRGB",
    -- Prüfung der Einstellungen vom 19.11.2026: einmalige Umstellung (ns.MigrateSettings1911)
    "MigrateOnce" },
    onError = KeepError,
    db = "ezChatDB",
    -- chars: je Charakter Verlauf und Gespräche; window: Lage bis 1.2 (einmal übernommen); hints: gesehene
    -- Erklärblasen (ns.Tour); alarmChannels: [ezCore.ChannelKey] = true (alle Charaktere); migrated: Merker
    tables = { "chars", "window", "hints", "alarmChannels", "migrated" },
    onLoad = function(db)
        ns.MigrateChannelKeys(db)
        ns.MigrateMailOptIn(db)
        ns.MigrateWhisperOptIn(db)
        ns.MigrateSettings1911(db)
        ns.MigrateRestoreOff(db)
        ns.MigrateRestoreOff2111(db)
        ns.MigratePopupAfter(db)
        ns.MigrateToneAway(db)
    end,
    -- main: ohne Wort das Gesprächsfenster wie der Linksklick im Addon-Fach (Entscheidung 5); reset: „/ezchat
    -- zuruecksetzen“ fragt wie der Knopf (Core.SlashReset über page:AskReset; Gesamtreview T18-3, T18-20)
    slash = {
        alias = "/ezc",
        extra = function(cmd, rest, input) return ns.SlashExtra(cmd, rest, input) end,
        main = function() ns.ToggleWindow() end,
        mainText = L.MAIN_TEXT,
        reset = true,
    },
})

-- Welches fremde Addon übernimmt die Funktion hinter diesem Schalter? Anzeigename oder nil.
-- Gemerkt bis zum nächsten ADDON_LOADED: der Chatfilter fragt bei jeder Zeile.
-- Schalter, die nur in ns.HINT_BY stehen, fragen ohne zu zählen (ns.OtherInfo aus dem Gerüst): ezChat bleibt dort
-- an, das ist kein „gewichen“ für /ez status (Gegenprüfung zu I2, Gesamtreview 18.11.2026).
local otherCache = {}
function ns.Other(key)
    local cached = otherCache[key]
    if cached ~= nil then return cached or nil end
    local feature = ns.HANDLED_BY[key] or ns.HINT_BY[key]
    local who
    if feature then
        local label
        if not ns.HANDLED_BY[key] and type(ns.OtherInfo) == "function" then
            label = ns.OtherInfo(feature)
        else
            label = ns.OtherFor(feature)
        end
        if type(label) == "string" then who = label end
    end
    otherCache[key] = who or false
    return who
end

function ns.ResetOther() otherCache = {} end
ns.On("ADDON_LOADED", function() ns.ResetOther() end)

-- Schalter an und von keinem fremden Addon übernommen.
function ns.Active(key)
    if not (ns.S and ns.S[key]) then return false end
    return not (ns.HANDLED_BY[key] and ns.Other(key))
end

-- Hinweis am Schalter (Tooltip der Einstellung, Menüs): leer, wenn niemand sonst die Funktion hat.
function ns.OtherNote(key)
    local who = ns.Other(key)
    if not who then return nil end
    if ns.HANDLED_BY[key] then return (key == "links" and L.OTHER_HANDLES_LINKS or L.OTHER_HANDLES):format(who) end
    return L["OTHER_HINT_" .. ns.HINT_BY[key]]:format(who)
end

-- Rohe Namen aus Ereignissen (nur Namen, keine Nachrichtentexte) für /ezchat diag: die letzten 15, nur im
-- Arbeitsspeicher. In die Diagnose kommen sie erst beim Speichern – ab Werk unkenntlich (ns.MaskName).
local rawNames = {}   -- { { Quelle, Name } … }, neueste zuerst
function ns.NoteRaw(source, value)
    if type(value) ~= "string" or not ns.Usable(value) then return end
    table.insert(rawNames, 1, { source, value })
    for i = #rawNames, 16, -1 do rawNames[i] = nil end
end

-- Namen für die Diagnose unkenntlich machen (Vollprüfung W-62). Die Form bleibt, denn um sie geht es bei der
-- Fehlersuche – Länge in Zeichen, Groß- und Kleinschreibung, Leerzeichen, Bindestrich, Realm-Trenner und alle
-- anderen ASCII-Zeichen –, der Name selbst nicht:
--   a–z → x, A–Z → X, 0–9 → 9, jedes Zeichen jenseits von ASCII (Umlaut, Akzent; ein Zeichen, egal wie viele Bytes) → ü
-- Was kein Text ist (nil, Zahl, true), kommt als tostring zurück, ein geheimer Wert als „<secret>“.
ns.MASK_OTHER = "ü"
ns.MASK_LEGEND = "Namen unkenntlich: x/X = Buchstabe, 9 = Ziffer, ü = anderes Zeichen (Umlaut, Akzent); Länge, Leerzeichen und Trennzeichen wie im Original"
function ns.MaskName(value)
    if ns.IsSecret(value) then return "<secret>" end
    if type(value) ~= "string" then return tostring(value) end
    local text = value:gsub("[\194-\244][\128-\191]*", "\1"):gsub("[\128-\255]", "\1")
    text = text:gsub("[a-z]", "x"):gsub("[A-Z]", "X"):gsub("[0-9]", "9")
    return (text:gsub("\1", ns.MASK_OTHER))
end

-- Wie oft Blizzard ezChats Menü- und Reiter-Hooks aufgerufen hat (für /ezchat diag).
local seen = {}
function ns.Seen(label)
    seen[label] = (seen[label] or 0) + 1
end

-- Secret Values (Kampf/Instanz) nie anfassen: prüfen und auslassen.
ns.Usable = Core.Usable
ns.Trim = Core.Trim
ns.Pattern = Core.FormatToPattern   -- Blizzards Formatstring als Suchmuster
ns.PlainText = Core.PlainText       -- Farbcodes, Links und Symbole als reiner Text
ns.Truncate = Core.TruncateBytes    -- kürzen, ohne ein UTF-8-Zeichen zu zerschneiden

-- Zeitpunkt je Sprache aus ezCore: heute „14:05“, sonst mit Datum (DayText: nur das Datum).
function ns.TimeText(t) return Core.DateText(t) end
function ns.DayText(t) return Core.DateText(t, "day") end

---------------------------------------------------------------------------
-- Eingabe- und Bestätigungsfenster (ezCore)
---------------------------------------------------------------------------

function ns.AskText(prompt, current, callback)
    Core.AskText(prompt, current, callback, 60)
end

function ns.Confirm(prompt, callback)
    Core.Confirm(prompt, callback)
end

-- Kontextmenü an einem Knopf über ezCore.Menu; ein Fehler beim Füllen wird als ezChat-Fehler gemeldet.
-- false, wenn es Blizzards MenuUtil nicht gibt.
function ns.OpenMenu(owner, fill)
    if not owner then return false end
    return Core.Menu.Open(owner, function(root) ns.Try("Menu", fill, root) end)
end

---------------------------------------------------------------------------
-- Chatfilter (ezCore, mit Forever-/Retail-Weiche)
---------------------------------------------------------------------------

ns.AddMessageEventFilter = Core.AddMessageEventFilter

---------------------------------------------------------------------------
-- Namen
-- WoW Forever hat regional eindeutige Namen aus Vor- und Nachname (Umsetzung in ezCore/Names.lua):
-- ein Charakter heißt „Vorname Nachname“; Flüstern braucht den vollen Namen, sonst bleibt
-- Blizzards Eingabezeile bei „/w Vorname“ stehen.
---------------------------------------------------------------------------

-- Übernimmt Name, Realm und Schlüssel aus ezCore (ezCore ermittelt sie beim Einloggen; hier nur neu
-- gelesen, falls sich Blizzards Namensregeln geändert haben).
function ns.InitPlayer()
    Core.InitIdentity()
    ns.realm = Core.realm
    ns.uniqueNames = Core.uniqueNames
    ns.surnameSep = Core.surnameSep
    ns.selfName = Core.selfName
    -- Schlüssel der Charakterdaten: voller Name, damit gleiche Vornamen nicht zusammenfallen.
    ns.charKey = Core.charKey
    ns.oldCharKey = Core.oldCharKey   -- bis 1.0.0 nur der Vorname
    if ns.Format then ns.Format.ResetWords() end   -- der eigene Name gehört zu den hervorgehobenen Wörtern
end

ns.FullName = Core.FullName       -- Rohname → einheitlicher voller Name
ns.Short = Core.ShortName         -- Anzeige- und Flüstername
ns.TellName = Core.ShortName      -- Ziel für Flüstern und Briefe
ns.LinkName = Core.LinkName       -- Spieler-Link (|Hplayer:…|h)
ns.IsSelf = Core.IsSelf
ns.MissingSurname = Core.MissingSurname

-- Eingabe „Name Text“ (Forever: „Vorname Nachname Text“ oder „Vorname-Nachname Text“)
-- → voller Name, Text. Ein bekannter Vorname reicht; der Nachname wird ergänzt.
function ns.ParseNameAndText(input)
    local name, text = (input or ""):match("^(%S+)%s*(.-)$")
    local full = ns.FullName(name)
    if not full or not ns.MissingSurname(full) then return full, text end
    local word, after = (text or ""):match("^(%S+)%s*(.-)$")
    local completed = ns.CompleteName(full)
    if completed ~= full then
        local surname = completed:sub(#full + #(ns.surnameSep or " ") + 1)
        if word and word:lower() == surname:lower() then text = after end
        return completed, text
    end
    if word then return ns.FullName(name .. "-" .. word), after end
    return full, text
end

-- Eingetippter Spielername → voller Name, nie man selbst (sonst nil).
function ns.TypedName(text)
    local full = ns.ParseNameAndText(text)
    if full and not ns.IsSelf(full) then return full end
    return nil
end

---------------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------------

-- Battle.net: die Originalfunktion vor dem eigenen Hook merken, damit eigene Zustellversuche nicht im
-- Hook für normales Flüstern landen. Flüstern geht über ezCore.SendChat (Chat-Sperre, Forever/Retail);
-- solange ezChat selbst sendet, überspringt der Hook in Delivery.lua die Zeile (ns.OwnSend).
local rawSendBN = (C_BattleNet and C_BattleNet.SendWhisper) or BNSendWhisper

ns.InLockdown = Core.ChatLocked

local ownSend = false
function ns.OwnSend() return ownSend end

function ns.SendWhisper(target, text)
    ownSend = true
    local ok = Core.SendChat(text, "WHISPER", target)
    ownSend = false
    return ok
end

function ns.SendBNWhisper(accountID, text)
    if not rawSendBN or ns.InLockdown() then return false end
    local ok, err = pcall(rawSendBN, accountID, text)
    if not ok then ns.Error(err) end
    return ok
end

---------------------------------------------------------------------------
-- Battle.net und bekannte Spieler (ezCore)
---------------------------------------------------------------------------

ns.BNInfoByID = Core.BNInfoByID
ns.BNTagOf = Core.BNTagOf
ns.BNCharacter = Core.BNCharacter
ns.BNFind = Core.BNFind
-- Alle bekannten Charaktere: fn(full, online, source, bnLabel), source = friend, bnet, guild.
ns.ForEachCharacter = Core.ForEachContact

-- Forever: fehlt der Nachname („Tarek“ statt „Tarek Hohenfels“), aus Gesprächen, Freunden und Gilde ergänzen,
-- wenn genau ein Charakter mit diesem Vornamen bekannt ist. Die Suche macht ezCore (Core.CompleteName,
-- Vornamen-Verzeichnis der Kontakte, V-069); ezChat reicht nur seine Gespräche als weitere Kandidaten hinein.
local function ConsiderConvos(consider)
    for _, convo in pairs(ns.C and ns.C.convos or {}) do
        if not convo.bn then consider(convo.name) end
    end
end

function ns.CompleteName(full)
    return (Core.CompleteName(full, ConsiderConvos))
end

-- Flüsterfarbe aus Blizzards ChatTypeInfo (eine Stelle für Fenster, Gesprächsansicht und Chat, V-072).
-- which: Chat-Typ („WHISPER“, „BN_WHISPER_INFORM“ …) oder true/false für Battle.net bzw. Flüstern.
ns.WHISPER_FALLBACK = { WHISPER = { 1, 0.5, 1 }, BN_WHISPER = { 0, 1, 0.96 } }
function ns.WhisperColor(which)
    local chatType = which
    if type(which) ~= "string" then chatType = which and "BN_WHISPER" or "WHISPER" end
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if type(info) == "table" and info.r then return info.r, info.g, info.b end
    local c = ns.WHISPER_FALLBACK[(chatType:gsub("_INFORM$", ""))] or { 1, 1, 1 }
    return c[1], c[2], c[3]
end

-- Farben (Design-System 2.5): Farbcodes und Farbwerte nur aus ezCores Rollen (Core.Style.COLOR über Core.Style.Color:
-- Blizzards Objekt zuerst, Rückfall dessen Werte), keine rohen Codes und keine Zahlen im Modul. Genutzt: normal (Gold),
-- highlight (Weiß), gray (Blizzards GRAY_FONT_COLOR), good, bad und seit Welle 23 (A4) auch bnet (Battle.net-Freunde),
-- orange (Marke „stumm“, Stichwörter im Chat) und link (Web-Adressen) – vorher eine eigene Liste ns.COLOR_OBJECTS hier.
-- → "|cffrrggbb" der Rolle; unbekannt: Weiß
-- Ohne Core.Style (ezCore zu alt; die Meldung kommt über needs) Weiß statt eines Fehlers beim Laden.
local function StyleColor(kind)
    local Style = Core.Style
    if type(Style) ~= "table" or type(Style.Color) ~= "function" then return nil end
    return Style.Color(kind)
end
function ns.ColorCode(kind)
    local r, g, b = StyleColor(kind)
    if type(r) ~= "number" then return Core.WHITE end
    return Core.ColorCode(r, g, b)
end

-- r, g, b einer Rolle – genau drei Werte (Style.Color liefert als vierten Blizzards Objekt) für AddLine, AddMessage
-- und SetText (Welle 23, A5; vorher Zahlen an diesen Stellen). "grey" ist ezCores Grau (Core.GREY, wie ezCore.Grey)
-- für Hinweise in Tooltips und gedämpfte Zeilen; unbekannt: Weiß. Seit dem Gesamtreview vom 18.11.2026 (T16-5) ezCores
-- Core.RoleRGB (dieselbe Regel wie ezBag ns.TipRGB), der Name bleibt.
function ns.RGB(kind)
    if type(Core.RoleRGB) ~= "function" then return 1, 1, 1 end   -- ezCore zu alt: die Meldung kommt über needs
    return Core.RoleRGB(kind)
end
function ns.ColorText(kind, text)
    return ns.ColorCode(kind) .. tostring(text) .. "|r"
end

-- ezChat-Hinweis in ein Chatfenster schreiben (ein Präfix für alle Stellen, V-072). false ohne Fenster.
-- Farbe des Namens wie ezCores eigene Chat-Zeilen (Core.PREFIX_COLOR, Kern/Core.lua).
ns.NOTE_PREFIX = Core.PREFIX_COLOR .. "ezChat|r: "
function ns.NoteTo(frame, text)
    if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then return false end
    frame:AddMessage(ns.NOTE_PREFIX .. tostring(text))
    return true
end

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------

function ns.Number(key)
    return math.floor(tonumber(ns.S[key]) or ns.DEFAULTS[key] or 0)
end

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------

-- Alle Teile von ezChat (ns.<Name>), in TOC-Reihenfolge nach Core.
local MODULES = { "Conv", "History", "Delivery", "Mail", "Community", "Format", "Alarms", "Spam", "Situation", "Window",
    "FriendsDock", "Chat", "ChatBar", "ChatView", "Typing" }

-- ezChatDB legt das Gerüst an (Core.NewModule oben: db, tables, onLoad).

-- Bis 1.5.0 hießen Kanal-Alarme nach dem Namen mit Leerzeichen („suche nach gruppe“), seit 1.6.0 nach
-- ezCore.ChannelKey („suchenachgruppe“): einmal umschreiben (Merker migrated.channelKeys).
-- Rückgabe: Anzahl umgeschriebener Schlüssel.
function ns.MigrateChannelKeys(db)
    if type(db) ~= "table" or type(db.alarmChannels) ~= "table" then return 0 end
    db.migrated = db.migrated or {}
    if db.migrated.channelKeys then return 0 end
    local renamed, count = {}, 0
    for key, on in pairs(db.alarmChannels) do
        local new = type(key) == "string" and ezCore.ChannelKey(key)
        if new and on then
            renamed[new] = true
            if new ~= key then count = count + 1 end
        end
    end
    db.alarmChannels = renamed
    db.migrated.channelKeys = true
    return count
end

-- „Als Brief am Briefkasten senden“ ab Werk aus (Antwort des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas
-- hingewiesen werden, er kann es nutzen muss es aber einschalten“; Fund des code-reviewers, Welle 28): Wer den alten
-- Standard (an) gespeichert hat, bekommt einmal den neuen – FillDefaults füllt nur Fehlendes, sonst bliebe es an. Gemerkt
-- wird der alte Wert (migrated.mailOff28Was = true), damit der Hinweis am Briefkasten sagt, dass ezCollection umgestellt
-- hat; der Merker migrated.mailOff28 verhindert ein zweites Umstellen – wer es danach selbst einschaltet, behält es.
-- Rückgabe: true, wenn umgestellt wurde.
-- Seit dem Gesamtreview vom 18.11.2026 (T4-7) über ezCores Core.OptInOnce – Merker (db.migrated) und Verhalten wie
-- vorher.
-- Prüfung der Einstellungen vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“), einmal über ezCores
-- Core.MigrateOnce (Merker db.migrated.settings1911):
--   Nr. 63/64: Der Hauptschalter „Fenster bei neuer Nachricht öffnen“ (openOnWhisper) ist weg, die Auswahlen je Lage
--   sind der Schalter. War er aus (ab Werk), stehen alle Lagen und „Sonst“ auf „nicht öffnen“ – wie bisher öffnet nichts.
--   War er an, bleiben die Lagen, wie sie gespeichert sind, und „Sonst“ öffnet sofort (wie bisher ohne Lage).
--   Nr. 23/24: classColors und linkTooltip sind immer an; ein alter Wert zählt nicht.
-- → true, wenn die Umstellung lief (nil, wenn schon geschehen).
local function Adopt1911(S)
    if S.openOnWhisper == true then
        S.sitPopupOther = "yes"
    else
        for _, key in ipairs({ "sitPopupCombat", "sitPopupInstance", "sitPopupAway", "sitPopupRest", "sitPopupOther" }) do
            S[key] = "no"
        end
    end
    S.openOnWhisper, S.classColors, S.linkTooltip = nil, nil, nil
end

function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "settings1911", function()
        Adopt1911(db.settings)
        return true
    end)
end

-- Ältere Sicherungstexte („Alles übernehmen“, ezCores Core.ImportAll): dieselbe Zuordnung, aber nur, wenn der alte
-- Hauptschalter im Text steht (code-reviewer 20.11.2026: sonst kamen die gespeicherten Lagen ohne ihn zurück und
-- Fenster sprangen auf, obwohl er aus war). values ist eine Kopie.
function ns.ImportLegacy(values)
    if type(values) ~= "table" then return values end
    -- „Verlauf beim Einloggen zeigen“ schaltet eine Sicherung nie ein (Entscheidung des Nutzers vom 21.11.2026:
    -- „„Alles übernehmen“ soll das nicht aktiv einschalten“): ein gespeichertes „an“ fällt weg, der Schalter bleibt,
    -- wie er ist; ein „aus“ wird übernommen. Als erster Schritt, damit ein Fehler weiter unten es nicht überspringt.
    if values.restore == true then values.restore = nil end
    if values.openOnWhisper ~= nil then Adopt1911(values) end
    values.classColors, values.linkTooltip = nil, nil
    for _, key in ipairs(ns.TONE_GONE) do values[key] = nil end   -- Ton nur noch abwesend (21.11.2026)
    -- „nach dem Kampf“ nur noch bei „Kampf: Fenster“ (ns.MigratePopupAfter)
    for _, key in ipairs({ "sitPopupInstance", "sitPopupAway", "sitPopupRest", "sitPopupOther" }) do
        if values[key] == "after" then values[key] = "yes" end
    end
    return values
end

-- Gemeinsamer Rumpf beider Umstellungen von „Verlauf beim Einloggen zeigen“ (je eigener Merker). → wie Core.MigrateOnce
local function RestoreOff(db, flag)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, flag, function()
        db.settings.restore = false
        return true
    end)
end

-- „Verlauf beim Einloggen zeigen“ ab Werk aus (Entscheidung des Nutzers vom 20.11.2026 auf die Frage nach dem Block
-- „N Nachrichten aus dem Verlauf … Ende des Verlaufs“: „Ab Werk aus (Empfohlen)“). Der Nutzer hat den Block als
-- überflüssig gemeldet, darum stellt ezChat auch gespeicherte Stände einmal auf aus (Core.MigrateOnce, Merker
-- db.migrated.restoreOff2011); wer es danach selbst einschaltet, behält es. → true, wenn die Umstellung lief (nil, wenn
-- schon geschehen).
function ns.MigrateRestoreOff(db)
    return RestoreOff(db, "restoreOff2011")
end

-- Noch einmal aus (Entscheidung des Nutzers vom 21.11.2026, Spieltest: alte Zeilen grau im allgemeinen Chat nach dem
-- Login – „das sollte nicht im allg. chat nach dem login angeziegt werden“; Antwort „Einmal ausschalten (Empfohlen)“):
-- Stände, die nach der ersten Umstellung wieder an waren (über „Allem zustimmen“ am Abend des 20.11.2026, als „restore“
-- dort mit „on“ mitkam – 1e71b092 bis baf10ebd), stellt ezChat einmal auf aus (Merker db.migrated.restoreOff2111). Der Schalter bleibt; wer ihn danach
-- einschaltet, behält ihn. → true, wenn die Umstellung lief (nil, wenn sie schon gelaufen ist)
function ns.MigrateRestoreOff2111(db)
    return RestoreOff(db, "restoreOff2111")
end

-- „nach dem Kampf“ gibt es nur noch bei „Kampf: Fenster“ (code-reviewer 20.11.2026): Dungeon, Abwesend und Stadt gelten
-- nur außerhalb des Kampfes, dort öffnete „nach dem Kampf“ schon immer sofort. Ein gespeichertes „after“ dieser Lagen
-- wird einmal „yes“ (gleiche Wirkung; Core.MigrateOnce, Merker db.migrated.popupAfter2011). → true, wenn die Umstellung
-- lief (nil, wenn schon geschehen).
function ns.MigratePopupAfter(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "popupAfter2011", function()
        for _, key in ipairs({ "sitPopupInstance", "sitPopupAway", "sitPopupRest", "sitPopupOther" }) do
            if db.settings[key] == "after" then db.settings[key] = "yes" end
        end
        return true
    end)
end

-- Ton bei Flüstern nur noch abwesend (Entscheidung des Nutzers vom 21.11.2026): die gespeicherten Schalter der übrigen
-- Lagen sind ohne Wirkung und werden einmal entfernt (Core.MigrateOnce, Merker db.migrated.toneAway2111). → true, wenn
-- die Umstellung lief (nil, wenn schon geschehen).
ns.TONE_GONE = { "sitToneCombat", "sitToneInstance", "sitToneRest" }
function ns.MigrateToneAway(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "toneAway2111", function()
        for _, key in ipairs(ns.TONE_GONE) do db.settings[key] = nil end
        return true
    end)
end

function ns.MigrateMailOptIn(db)
    return Core.OptInOnce(db, "mailOff28", { mailDelivery = "mailOff28Was" }, "migrated") ~= nil
end

-- „Auch Flüstern aus dem normalen Chat“ ab Werk aus (Gesamtreview 18.11.2026, T1-4; Entscheidung 3 des Nutzers vom
-- 18.11.2026, „alle empfehlungen umsetzen“): Es schickt eine im normalen Chat getippte Flüsterzeile an einen Offline-
-- Spieler später ohne Klick nach. Wie bei ns.MigrateMailOptIn: Wer den alten Standard (an) gespeichert hat, bekommt
-- einmal den neuen (Merker migrated.whisperOffP17, alter Wert migrated.whisperOffP17Was = true für den Hinweis am
-- Chat); wer es danach selbst einschaltet, behält es. Ein neuer Speicher (FillDefaults mit dem neuen Standard) und
-- neue Twinks (die Einstellungen gelten für den ganzen Account) bleiben unverfälscht.
-- Rückgabe: true, wenn umgestellt wurde.
-- Über Core.OptInOnce wie ns.MigrateMailOptIn (T4-7).
function ns.MigrateWhisperOptIn(db)
    return Core.OptInOnce(db, "whisperOffP17", { catchChatWhispers = "whisperOffP17Was" }, "migrated") ~= nil
end

ns.On("PLAYER_LOGIN", function()
    ns.InitPlayer()
    -- Bis 1.0.0 hieß der Schlüssel nur nach dem Vornamen: Daten übernehmen.
    if not ns.db.chars[ns.charKey] and ns.db.chars[ns.oldCharKey] then
        ns.db.chars[ns.charKey] = ns.db.chars[ns.oldCharKey]
        ns.db.chars[ns.oldCharKey] = nil
    end
    local char = ns.db.chars[ns.charKey] or {}
    ns.db.chars[ns.charKey] = char
    char.history = char.history or {}   -- [Kanal] = { { t, e, n, m }, ... }
    char.convos = char.convos or {}     -- [Schlüssel] = Gespräch (siehe Conversations.lua)
    char.mailSeen = char.mailSeen or {} -- schon übernommene [ezChat]-Briefe
    char.clubs = char.clubs or {}       -- letzte gesehene Community-Nachricht je Zweier-Community
    -- char.filtered (Spam.lua, angelegt beim ersten Fund): gefilterte Flüster-Nachrichten { t, n, m, r };
    -- char.filteredNew: davon noch nicht angesehen; char.spamAllow[Schlüssel] = true: per „Doch zeigen“ freigegeben
    ns.C = char
    ns.loginTime = time()

    ns.RunReady()

    -- Nach einem Update mit neuen Dateien lädt WoW diese erst nach einem Neustart.
    for _, name in ipairs(MODULES) do
        if not ns[name] then
            ns.Print(L.RESTART_NEEDED)
            break
        end
    end

    if not ns.db.privacyShown then
        ns.db.privacyShown = true
        ns.Print(L.PRIVACY_FIRST_RUN)
    end
    ns.Try("OtherAddOns", ns.NoteOthers)
end)

-- Vergisst ezCore einen Twink (Core.ForgetChar, Nachricht CHAR_FORGOTTEN), gehen sein Verlauf, seine Gespräche,
-- gefilterten Flüster-Nachrichten und übernommenen Briefe mit (ns.db.chars[key]; Gesamtreview 18.11.2026, T4-2).
-- Den angemeldeten Charakter vergisst ezCore nie; ns.C bliebe sonst ohne Eintrag in der Datenbank. → true, wenn etwas
-- gemerkt war.
function ns.ForgetChar(key)
    if not (ns.db and type(ns.db.chars) == "table" and type(key) == "string") or key == ns.charKey then return false end
    if ns.db.chars[key] == nil then return false end
    ns.db.chars[key] = nil
    return true
end
Core.Listen("CHAR_FORGOTTEN", function(key) ns.ForgetChar(key) end, ADDON)

-- Einmal im Chat sagen, wo sich ezChat wegen eines fremden Addons zurückhält; wieder, sobald sich das ändert.
function ns.NoteOthers()
    local byWho, order, keys = {}, {}, {}
    for _, entry in ipairs(ns.TOGGLES) do
        local key = entry[1]
        local who = ns.HANDLED_BY[key] and ns.S[key] and ns.Other(key)
        if who then
            if not byWho[who] then
                byWho[who] = {}
                order[#order + 1] = who
            end
            table.insert(byWho[who], L["OPT_" .. key])
            keys[#keys + 1] = who .. ":" .. key
        end
    end
    local signature = table.concat(keys, ",")
    if signature == (ns.db.otherNoted or "") then return end
    ns.db.otherNoted = signature
    for _, who in ipairs(order) do ns.Print(L.OTHER_LOGIN:format(who, table.concat(byWho[who], ", "))) end
end

ns.On("PLAYER_LOGOUT", function()
    if ns.C then ns.RunLogout() end
end)

-- Atlanten, die ezChat setzt (Knopfleiste am Chatfenster, Hinweis auf neue Briefe). /ez test prüft sie über ezCores
-- Selbsttest (Gesamtreview 18.11.2026, T16-NM1 – vorher nur in /ezchat diag mit eigener Abfrage).
ns.ATLASES = { "communities-icon-notification", "communities-icon-invitemail",
    "chatframe-button-up", "chatframe-button-down", "chatframe-button-highlight" }
if Core.AddSelfTest then
    Core.AddSelfTest("ezChat", function()
        local out = {}
        for _, name in ipairs(ns.ATLASES) do
            out[#out + 1] = { kind = "atlas", name = name, there = Core.AtlasExists(name) == true, optional = true }
        end
        return out
    end, "atlases")
end

---------------------------------------------------------------------------
-- Diagnose: /ezchat diag schreibt nach ezChatDB.diag (nach /reload lesbar)
---------------------------------------------------------------------------

local function Safe(value)
    if ns.IsSecret(value) then return "<secret>" end
    return tostring(value)
end

-- Namen (der eigene, Freunde, Battle.net-Freunde, Gilde, Ziel, Absender aus dem Chat) stehen ab Werk unkenntlich
-- in der Diagnose (ns.MaskName, d.masked = true); mit dem Schalter „Namen im Klartext“ (diagPlain) lesbar.
-- Realm, Schnittstellen, Zähler und die Namen fremder Addons sind keine Namen von Spielern und bleiben lesbar.
local function Collect()
    local plain = ns.S ~= nil and ns.S.diagPlain == true
    local Name = plain and Safe or ns.MaskName
    local d = { at = date("%d.%m.%Y %H:%M:%S"), charKey = Name(ns.charKey), realm = ns.realm, masked = not plain }
    if not plain then d.mask = ns.MASK_LEGEND end
    local function Put(label, show, fn, ...)
        if type(fn) ~= "function" then
            d[label] = "<fehlt>"
            return
        end
        local ok, a, b, c = pcall(fn, ...)
        if ok then
            d[label] = show(a) .. " | " .. show(b) .. " | " .. show(c)
        else
            d[label] = "FEHLER " .. tostring(a)
        end
    end
    local function Try(label, fn, ...) Put(label, Safe, fn, ...) end
    local function TryName(label, fn, ...) Put(label, Name, fn, ...) end
    TryName("UnitName", UnitName, "player")
    TryName("UnitFullName", UnitFullName, "player")
    Try("GetNormalizedRealmName", GetNormalizedRealmName)
    Try("GetRealmName", GetRealmName)
    Try("Lockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)

    d.friends = {}
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, math.min(5, C_FriendList.GetNumFriends() or 0) do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and type(info) == "table" then
                d.friends[#d.friends + 1] = Name(info.name) .. (info.connected and " (online)" or " (offline)")
            end
        end
    end
    d.names = {
        uniqueNames = ns.uniqueNames == true,
        separator = "[" .. tostring(ns.surnameSep) .. "]",
        selfName = Name(ns.selfName),
        -- der Link aus dem unkenntlichen Namen: dieselbe Form (Trennzeichen), kein Klartext
        link = Safe(ns.selfName and ns.LinkName(Name(ns.selfName))),
    }
    -- Battle.net-Freunde, die gerade WoW spielen (für das Flüsterziel ihres Charakters)
    d.bnGame = {}
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, (BNGetNumFriends() or 0) do
            local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
            local game = ok and type(info) == "table" and info.gameAccountInfo
            if type(game) == "table" and game.isOnline and #d.bnGame < 5 then
                local target = "-"
                if C_BattleNet.GetDefaultTitleWhisperTarget and info.bnetAccountID then
                    local okTarget, result = pcall(C_BattleNet.GetDefaultTitleWhisperTarget, info.bnetAccountID)
                    target = okTarget and Name(result) or "FEHLER"
                end
                d.bnGame[#d.bnGame + 1] = table.concat({
                    Safe(game.clientProgram), Safe(game.wowProjectID), Name(game.characterName),
                    Name(game.realmName), "Ziel " .. target, Core.ARROW .. " " .. Name(ns.BNCharacter(info)),
                }, " | ")
            end
        end
    end
    d.WOW_PROJECT_ID = Safe(WOW_PROJECT_ID)
    d.guild = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, math.min(5, GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            d.guild[#d.guild + 1] = Name(name) .. " (" .. Safe(online) .. ") " .. Core.ARROW .. " " .. Name(ns.FullName(name))
        end
    end
    if Core.UnitIs("target") == true then   -- V-184: existiert und ist Spieler, gesperrt zählt als nein
        TryName("target_UnitName", UnitName, "target")
        TryName("target_GUIDInfo", function()
            local guid = ns.Plain(UnitGUID("target"))
            if not guid then return nil end
            local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
            return name, realm
        end)
    end
    d.raw = {}
    for i, item in ipairs(rawNames) do d.raw[i] = item[1] .. ": " .. Name(item[2]) end

    local function Has(value) return value ~= nil end
    d.api = {
        C_Club = Has(C_Club),
        SendMail = Has(SendMail),
        ChatFrameUtil_SendTell = Has(ChatFrameUtil and ChatFrameUtil.SendTell),
        ChatFrame_SendTell = Has(ChatFrame_SendTell),
        ChatFrameUtil_AddMessageEventFilter = Has(ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter),
        C_ChatInfo_SendChatMessage = Has(C_ChatInfo and C_ChatInfo.SendChatMessage),
        C_BattleNet_SendWhisper = Has(C_BattleNet and C_BattleNet.SendWhisper),
        Menu_ModifyMenu = Has(Menu and Menu.ModifyMenu),
        GetPlayerInfoByGUID = Has(GetPlayerInfoByGUID),
        ReplaceIconAndGroupExpressions = Has(C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions),
        MenuUtil_CreateContextMenu = Has(MenuUtil and MenuUtil.CreateContextMenu),
        FCF_Tab_OnClick = Has(FCF_Tab_OnClick),
        FCF_OpenTemporaryWindow = Has(FCF_OpenTemporaryWindow),
        FCFOptionsDropDown = Has(FCFOptionsDropDown),   -- alte Dropdown-Menüs statt Menu-API
        -- 1.2: Links vom Typ „addon“, Blinken, Kopieren und Pfeiltasten im Blizzard-Chat
        EventRegistry = Has(EventRegistry and EventRegistry.RegisterCallback),
        FlashClientIcon = Has(FlashClientIcon),
        ChatFrame1_SetTextCopyable = Has(ChatFrame1 and ChatFrame1.SetTextCopyable),
        ChatFrame1_SetFading = Has(ChatFrame1 and ChatFrame1.SetFading),
        ChatFrame1EditBox_SetAltArrowKeyMode = Has(ChatFrame1EditBox and ChatFrame1EditBox.SetAltArrowKeyMode),
        GetChannelList = Has(GetChannelList),
        -- Andocken an die Freundesliste (FriendsDock.lua); blendet Blizzards neues Social-Fenster sie aus?
        FriendsFrame = Has(rawget(_G, "FriendsFrame")),
        SocialUI = Safe(C_SocialUI and C_SocialUI.IsSystemEnabled and select(2, pcall(C_SocialUI.IsSystemEnabled))),
    }
    -- Fremde Addons, wegen denen sich ezChat zurückhält (ezCore.WhoHandles)
    d.others = {}
    for key in pairs(ns.HANDLED_BY) do d.others[key] = ns.Other(key) or "-" end
    for key in pairs(ns.HINT_BY) do d.others[key] = ns.Other(key) or "-" end
    -- Welche ezChat-Dateien geladen sind (neue Dateien in der TOC brauchen einen Neustart).
    d.modules = {}
    for _, name in ipairs(MODULES) do
        d.modules[name] = Has(ns[name])
    end
    d.seen = {}
    for label, count in pairs(seen) do d.seen[label] = count end
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    if getCVar then
        local ok, mode = pcall(getCVar, "whisperMode")
        d.whisperMode = ok and Safe(mode) or "?"
    end
    d.templates = {}
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        for _, name in ipairs({ "PortraitFrameFlatTemplate", "InsetFrameTemplate", "WowScrollBoxList", "MinimalScrollBar", "UIPanelButtonTemplate" }) do
            local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
            d.templates[name] = ok and info ~= nil
        end
    end
    -- Atlanten über ezCores Core.AtlasExists (Gesamtreview 18.11.2026, T16-NM1; vorher eine eigene Abfrage hier); dieselbe
    -- Liste meldet ezChat für /ez test an (unten, Core.AddSelfTest)
    d.atlas = {}
    if C_Texture and C_Texture.GetAtlasInfo then
        for _, name in ipairs(ns.ATLASES) do d.atlas[name] = Core.AtlasExists(name) == true end
    end
    d.pairCommunities = ns.Community and #ns.Community.Pairs() or 0
    -- Speichergröße des Verlaufs (Verlaufspflege): Gespräche, Nachrichten, ungefähre Bytes; dazu Gefiltertes und Kanäle
    local convos, msgs, bytes = ns.Conv.StorageSize()
    local channelLines = 0
    for _, list in pairs(ns.C and ns.C.history or {}) do channelLines = channelLines + #list end
    d.storage = { convos = convos, messages = msgs, bytes = bytes, kib = math.floor(bytes / 102.4 + 0.5) / 10,
        filtered = ns.Spam and ns.Spam.Count() or 0, channelLines = channelLines, keepDays = ns.Number("keepDays") }
    -- „tippt gerade“ und Ort über Addon-Nachrichten (Typing.lua): angemeldet? gesendet, abgelehnt, empfangen
    if ns.Typing then
        local st = ns.Typing.stats
        d.addonMessages = { prefix = ns.Typing.PREFIX, registered = st.registered, sent = st.sent, refused = st.refused,
            received = st.received, last = st.last }
    end
    d.situation = ns.Situation and ns.Situation.Current() or "-"
    d.settingsRegistered = ns.OpenSettings ~= nil and ns.SettingsRegistered == true
    d.errors = #(ezChatDB.errors or {})
    return d
end

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

local function ListQueue()
    if not ns.C then return end
    local any = false
    for _, item in ipairs(ns.Conv.Sorted()) do
        local count = ns.Conv.CountQueued(item.convo)
        if count > 0 then
            any = true
            local first = ns.Conv.FirstQueued(item.convo)
            ns.Print(L.CMD_QUEUE_LINE:format(ns.Conv.Display(item.convo), count, ns.TimeText(first and first.t)))
        end
    end
    if not any then ns.Print(L.CMD_QUEUE_EMPTY) end
end

ns.ListQueue = ListQueue

-- Diagnose speichern (/ezchat diag und Knopf unter „Erweitert“). Die Meldung sagt, ob die Namen unkenntlich sind.
function ns.SaveDiag()
    local ok, result = pcall(Collect)
    if ok then
        ns.db.diag = result
        ns.Print(L.DIAG_SAVED:format(result.masked and L.DIAG_MASKED or L.DIAG_PLAIN))
    else
        ns.Error(result)
    end
end

-- Liegt eine Diagnose in den SavedVariables? Die rohen Namen zählen nicht: sie liegen nur im Arbeitsspeicher und
-- füllen sich mit jeder mitgeschriebenen Chatzeile wieder – gespeichert ist damit nichts.
function ns.HasDiag()
    return ns.db ~= nil and ns.db.diag ~= nil
end

-- Gespeicherte Diagnose und die gesammelten rohen Namen verwerfen. → true, wenn eine Diagnose gespeichert war
-- (danach richtet sich die Meldung im Chat; die rohen Namen gehen still mit).
function ns.ClearDiag()
    local had = ns.HasDiag()
    if ns.db then ns.db.diag = nil end
    for i = #rawNames, 1, -1 do rawNames[i] = nil end
    ns.Print(had and L.DIAG_CLEARED or L.DIAG_NONE)
    return had
end

-- Knopf „Diagnose löschen“ unter „Erweitert“ und /ezchat diag löschen: mit Rückfrage. → true, wenn gefragt wurde.
-- Ohne gespeicherte Diagnose gibt es nichts zu fragen: die rohen Namen gehen still, im Chat steht „Keine Diagnose
-- gespeichert.“
function ns.AskClearDiag()
    if not ns.HasDiag() then
        ns.ClearDiag()
        return false
    end
    ns.Confirm(L.CONFIRM_DIAG_CLEAR, function() ns.ClearDiag() end)
    return true
end

-- Zusatz hinter /ezchat diag, der löscht – in beiden Sprachen und so, wie die Knöpfe heißen („Diagnose löschen“,
-- „Delete diagnostics“). string.lower kennt in Lua 5.1 nur ASCII, darum das große Ö eigens.
local DIAG_CLEAR_WORDS = { ["löschen"] = true, loeschen = true, clear = true, delete = true }
local function DiagWord(rest)
    return (ns.Trim(rest or ""):lower():gsub("Ö", "ö"))
end

-- ezChats eigene Befehlswörter. Der Befehl /ezchat selbst, der Kurzbefehl /ezc (nur wenn frei, sonst gehört er
-- dem anderen Addon), „optionen“, „status“ und „hilfe“ kommen aus ezCores Gerüst (Core.NewModule oben); diese
-- Funktion läuft zuerst und gibt true zurück, wenn sie den Befehl erledigt hat.
function ns.SlashExtra(cmd, rest)
    if not ns.C then return true end   -- vor dem Einloggen: nichts tun (wie bisher)

    if cmd == "an" or cmd == "to" then
        local full, text = ns.ParseNameAndText(rest)
        if not full or ns.IsSelf(full) then
            ns.Print(L.CMD_NEED_NAME)
            return true
        end
        local convo = ns.Conv.Get(full, false, true)
        if text and text ~= "" then ns.Delivery.Send(convo, text) end
        ns.Window.OpenFor(full, false)
        return true
    end
    if cmd == "suche" or cmd == "search" then
        ns.Window.Open()
        ns.Window.SetSearch(rest)
        return true
    end
    if cmd == "stichwoerter" or cmd == "keywords" then
        ns.Format.EditKeywords()
        return true
    end
    if cmd == "post" or cmd == "mail" then
        ns.Mail.SendNow()
        return true
    end
    if cmd == "gefiltert" or cmd == "filtered" then
        ns.Window.OpenFiltered()
        return true
    end
    if cmd == "warteschlange" or cmd == "queue" then
        ListQueue()
        return true
    end
    if cmd == "diag" then
        local word = DiagWord(rest)
        if word == "" then
            ns.SaveDiag()
        elseif DIAG_CLEAR_WORDS[word] then
            ns.AskClearDiag()
        else
            -- unbekannter Zusatz (Tippfehler beim Löschen?): nichts speichern, den Befehl erklären
            ns.Print(L.DIAG_USAGE:format(ns.Trim(rest)))
        end
        return true
    end

    -- Schalter: nach dem Umschalten sagen, wenn ein fremdes Addon die Funktion übernimmt
    if Core.HandleToggle(ns, cmd) then
        local want = Core.SlashWord(cmd)
        for _, entry in ipairs(ns.TOGGLES) do
            local key = entry[1]
            local hit = want == Core.SlashWord(entry[2]) or want == Core.SlashWord(key) or want == Core.SlashWord(entry.en or "")
            if hit and ns.S[key] and ns.OtherNote(key) then ns.Print(ns.OtherNote(key)) end
        end
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Status (/ezchat status, Knopf „Status“ unter Einstellungen → Erweitert): Zeilen für ns.PrintStatus aus ezCore
---------------------------------------------------------------------------

ns.AddStatusLine(function()
    if not ns.C then return nil end
    local count = 0
    for _ in pairs(ns.C.convos) do count = count + 1 end
    return L.STATUS_CONVOS:format(count, ns.Conv.UnreadTotal(), ns.Conv.QueuedTotal())
end)
ns.AddStatusLine(function()
    if not ns.S then return nil end
    local dock = ns.FriendsDock
    local state = L.CMD_OFF
    if ns.S.friendsDock then state = (ns.Window and ns.Window.IsDocked() and ns.Window.IsShown()) and L.STATUS_DOCK_OPEN or L.CMD_ON end
    if ns.S.friendsDock and dock and not dock.Enabled() then state = L.STATUS_DOCK_MISSING end
    return state:format(L.OPT_friendsDock)
end)
-- Liegt eine Diagnose in den SavedVariables? Dann von wann und ob die Namen darin unkenntlich sind (eine Diagnose
-- von vor dieser Fassung trägt kein Kennzeichen und steht im Klartext).
ns.AddStatusLine(function()
    local d = ns.db and ns.db.diag
    if type(d) ~= "table" then return nil end
    return L.STATUS_DIAG:format(tostring(d.at or "?"), d.masked == true and L.DIAG_MASKED or L.DIAG_PLAIN)
end)
-- Wer übernimmt was (Leitlinie 9): je fremdem Addon eine Zeile mit den Schaltern, bei denen ezChat sich zurückhält
ns.AddStatusLine(function()
    if not ns.S then return nil end
    local byWho, order = {}, {}
    for _, entry in ipairs(ns.TOGGLES) do
        local key = entry[1]
        local who = ns.HANDLED_BY[key] and ns.S[key] and ns.Other(key)
        if who then
            if not byWho[who] then
                byWho[who] = {}
                order[#order + 1] = who
            end
            table.insert(byWho[who], L["OPT_" .. key])
        end
    end
    local lines = {}
    for _, who in ipairs(order) do lines[#lines + 1] = L.CHAT_STATUS_OTHER:format(who, table.concat(byWho[who], ", ")) end
    return lines
end)

-- Gesprächsfenster öffnen/schließen – Linksklick im Addon-Fach und Befehl ohne Wort (vor dem Einloggen nichts).
function ns.ToggleWindow()
    if not ns.C then return end
    ns.Window.Toggle()
end

-- Blizzards Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc, …OnEnter, …OnLeave), gebaut von ezCore nach
-- Entscheidung 5 (Gesamtreview T18-3, T16-10): Linksklick Gesprächsfenster, Rechtsklick Einstellungen, Zeilen und
-- Befehl von ezCore; ein Fehler im Klick landet in /ez fehler und ezChatDB.errors.
ezChat_OnAddonCompartmentClick, ezChat_OnAddonCompartmentEnter, ezChat_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, owner = ADDON, title = ADDON, main = ns.ToggleWindow, mainText = L.MAIN_TEXT })
