local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    ezSocial – Gruppensuche und Soziales im Originalstil.

    Erweitert Blizzards eigene Fenster, statt eigene zu bauen:
      Locks.lua        gesperrte Instanzen (ezCore.Lockouts) für „Durchsuchen“, das Menü „Aktivität“ und den
                       Reiter „Aus dem Chat“
      GroupFinder.lua  Fenster „Gruppe suchen“ (Blizzard_GroupFinder_VanillaStyle): Klassen und Rollen der
                       Mitglieder, Stufenbereich, grüner Rahmen bei freiem Platz für deine Rolle, Farben nach Stufe
      ChatLFG.lua      LFG/LFM-Nachrichten aus Handel, Suche nach Gruppe und Welt erkennen und sammeln
      ChatTab.lua      Reiter „Aus dem Chat“ im selben Fenster (Seitenreiter wie Blizzards drei)
      Panel.lua        ezPanel: Quelle „Gruppen-Nachrichten“ bei den Meldungen und Baustein auf der Leiste
      WhoList.lua      Wer-Liste mit Klassen- und Stufenfarben
      Friends.lua      Freundes- und Gildenliste: Klassenfarben, Stufenfarben, Notizen, Twinks der Freunde
      Talk.lua         Knopf „Gespräch“ (ezChat) in Freundesliste, Wer-Liste und „Durchsuchen“
      GuildInvite.lua  Eintrag „In Gilde einladen“ im Rechtsklick-Menü der Spieler (Rahmen, Ziel, Chat, Freunde)
      Auto.lua         Bereitschafts-Timer, Beschwörung und Wiederbelebung annehmen, Duelle und Einladungen
                       von Fremden ablehnen (hält sich zurück, wenn Leatrix Plus dasselbe erledigt)
      Tour.lua         Erklärblasen beim ersten Öffnen von „Gruppe suchen“ und der Freundesliste
    Suchen startet nur der Spieler selbst (Midnight-Regel): ezSocial ruft weder C_LFGList.Search noch
    eine Wer-Abfrage auf, es filtert und färbt nur. Taint-sicher: hooksecurefunc/HookScript, eigene Teile
    in eigenen Tabellen, nie Werte in Blizzards Tabellen.
]]

-- Prüfung der Einstellungen vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): Stufe der Gruppe, gesperrte
-- Instanzen, Twinks der Freunde und den Bereitschafts-Timer zeigt ezSocial immer (reine Anzeigen, Nr. 25–28); die vier
-- Farb-Schalter sind einer (colors, Nr. 65–68). Gespeicherte Werte übernimmt ns.MigrateSettings1911 einmal.
ns.DEFAULTS = {
    -- Namen und Stufen farbig: Zonen und Dungeons in „Gruppe suchen“, Wer-Liste, Freundesliste, Gildenliste
    colors = true,

    -- Gruppe suchen (Blizzards Fenster)
    finderMembers = true,       -- Klassen-Symbole und Rollen der Mitglieder, Leiter zuerst
    finderRoleBorder = true,    -- grün umrandet, wenn deine Rolle noch frei ist

    -- Aus dem Chat
    chatTab = true,             -- Reiter „Aus dem Chat“ und das Mitlesen
    chatTrade = true,
    chatLFG = true,
    chatWorld = true,
    chatGeneral = false,
    chatMaxAge = 15,            -- Minuten
    chatGroup = true,           -- nach Dungeon gruppieren (Dungeon-Tabelle aus ezCore)
    chatReply = true,           -- Klick auf eine Nachricht: Antwortvorschlag im Eingabefeld von ezChat

    -- Freunde
    friendNotes = true,

    -- Gespräche (mit ezChat)
    talkButtons = true,         -- Knopf „Gespräch“ in Freundesliste, Wer-Liste und „Durchsuchen“

    -- Rechtsklick-Menü der Spieler (GuildInvite.lua)
    menuGuildInvite = true,     -- Eintrag „In Gilde einladen“, nur mit Gilde und Recht zum Einladen

    -- Automatik (Rücksicht auf Leatrix Plus: ns.SHARED)
    acceptSummon = false,
    acceptResurrect = false,
    blockDuels = false,
    blockInvites = false,
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
ns.AGREE = {
    chatGeneral = "choice",
}

-- Gerüst aus ezCore (docs/ezcore.md „Gerüst-Dienste“): Datenbank, Login, Befehle und Status kommen von dort.
--   db/tables  ezSocialDB mit settings (ns.DEFAULTS), chat (gesammelte LFG/LFM-Nachrichten und „zuletzt
--              gesehen“, ChatLFG.lua) und
--              tour (gesehene Erklärblasen, Tour.lua). Twinks der Battle.net-Freunde: früher hier, jetzt in
--              ezCore (Core.BNAlts); der alte Speicher ezSocialDB.alts bleibt liegen und wird nicht beschrieben.
--   slash      /ezsocial; der Kurzbefehl /ezs kommt beim Einloggen, wenn er frei ist. Eigene Wörter in extra.
--   core/needs ist ezCore zu alt, bleibt das Modul still und ezCore meldet es (statt eines nil-Fehlers).
Core.NewModule(ADDON, ns, {
    title = "ezSocial",
    -- Mindestversion 1.14.0 (lockoutExpiry kam nach 1.13.0 ohne eigene Nummer); seit 1.13.0: Core.Style (Style.Color, Style.ICON; Welle 22), Core.Menu.PlayerMenus (GuildInvite.lua,
    -- prüft es selbst; Welle 16) und Core.More (Welle 17) fehlen im ausgelieferten ezCore 1.12.0 (Stand 6305793);
    -- Core.Contacts.FirstNameCount (SOCIAL-03) gab es dort schon. Was ezCore danach ohne neue Nummer bekam, prüft needs.
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.NewTimerBar, Core.SlashReset, Core.TipClick, Core.HelpLines
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    needs = { "Menu.ModifyUnits", "AfterCombat", "OpenPanel", "PanelShown", "CompleteName", "Contacts.FirstNameCount", "Contacts.State",
        "scaffoldHelpers", "Uptime", "Style.Color", "Style.ICON",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23: ezCore meldet den Ablauf einer Sperre selbst (Locks.lua, eigener Wecker entfallen)
        "lockoutExpiry",
        -- Gesamtreview 18.11.2026 (P13 Teil D2): Addon-Fach, Befehl ohne Wort, Zurücksetzen, Wege, Zeitbalken, Rollen
        "compartmentMain", "slashMain", "SlashCmd", "SettingsPathText", "NewTimerBar", "TipLine", "TipTitle", "TipText",
        "TipClick", "TipDoubleLine",   -- TipDoubleLine: Baustein-Tooltip in Rollen (T9-6, Nachtrag D3)
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound", "ICON_FALLBACK",
    -- Prüfung der Einstellungen vom 19.11.2026: einmalige Umstellung (ns.MigrateSettings1911)
    "MigrateOnce",
    -- Paket ezsocial/levelfarbe (ezCore ohne neue Versionsnummer): Stufenfarbe aus ezCore
    "QuestDifficultyRGB" },
    db = "ezSocialDB",
    -- migrated: Merker der einmaligen Umstellungen (ns.MigrateSettings1911)
    tables = { "chat", "tour", "migrated" },
    onLoad = function(db) ns.MigrateSettings1911(db) end,
    login = true,
    -- main: ohne Wort der Reiter „Aus dem Chat“ wie der Linksklick im Addon-Fach (Entscheidung 5); reset:
    -- „/ezsocial zuruecksetzen“ fragt wie der Knopf (Core.SlashReset über page:AskReset; Gesamtreview T18-3, T18-20)
    slash = {
        main = function() ns.API.OpenChatTab() end,
        mainText = L.MAIN_TEXT,
        reset = true,
        alias = "/ezs",
        extra = function(cmd)
            if cmd == "chat" then
                ns.API.OpenChatTab()
                return true
            elseif cmd == "suche" or cmd == "finder" or cmd == "lfg" then
                ns.OpenGroupFinder()
                return true
            end
            return false
        end,
    },
})

ns.FINDER_ADDON = "Blizzard_GroupFinder_VanillaStyle"
-- ns.Enabled, ns.Throttle, ns.WhenAddOnLoaded und die Abkürzungen ns.IsSecret, ns.Plain, ns.OtherFor gibt
-- Core.NewModule jedem Modul (die eigenen Verweise ohne Leser sind in Welle 4 entfallen, SOCIAL-05).

-- Rollen-Symbole wie in Blizzards Gruppensuche (Schlüssel wie assignedRole), für die Liste und den Reiter.
ns.ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}

-- Atlanten aus Blizzards Gruppensuche, die ezSocial setzt (Reiter am Chat, Liste, Anführer). /ez test prüft sie über
-- ezCores Selbsttest (Gesamtreview 18.11.2026, T16-NM1; vorher prüfte sie niemand). Die Klassen-Symbole
-- (groupfinder-icon-class-<klasse>) entstehen aus dem Namen der Klasse und stehen nicht in der Liste.
ns.ATLASES = { "groupfinder-highlightbar", "groupfinder-highlightbar-blue", "groupfinder-Stat-StoneBG",
    "groupfinder-background", "groupfinder-icon-leader", ns.ROLE_ATLAS.TANK, ns.ROLE_ATLAS.HEALER, ns.ROLE_ATLAS.DAMAGER }
if Core.AddSelfTest then
    Core.AddSelfTest("ezSocial", function()
        local out = {}
        for _, name in ipairs(ns.ATLASES) do
            out[#out + 1] = { kind = "atlas", name = name, there = Core.AtlasExists(name) == true, optional = true }
        end
        return out
    end, "atlases")
end

-- Teil eines Blizzard-Rahmens (Textur, Schrift, Unterrahmen) nur, wenn es ihn wirklich gibt.
function ns.Region(value)
    return type(value) == "table" and value or nil
end

---------------------------------------------------------------------------
-- Rücksicht auf fremde Addons (Leitlinie 9). Wer was übernimmt, weiß ezCore an einer Stelle
-- (Core.WhoHandles, Liste Core.OTHER_ADDONS in ezCore/OtherAddOns.lua, Begründungen in
-- docs/fremd-addons.md). ezSocial nennt nur seine Funktionen; deren Namen sind die Schlüssel der Einstellungen.
---------------------------------------------------------------------------

-- Funktionen, die es auch in fremden Addons gibt (heute Leatrix Plus). Ist eine dort an, überlässt
-- ezSocial ihm die Arbeit.
ns.SHARED = { "readyTimer", "acceptSummon", "acceptResurrect", "blockDuels", "blockInvites" }
-- Funktionen ohne eigenen Schalter (immer an, solange kein fremdes Addon sie erledigt) und ihr Name im Status
-- (Prüfung der Einstellungen vom 19.11.2026, Nr. 28: der Bereitschafts-Timer ist eine reine Anzeige)
ns.ALWAYS = { readyTimer = "READY_TIMER" }

-- Name des fremden Addons, das die Funktion gerade übernimmt, sonst nil (ns.OtherFor aus dem Gerüst, W-14).
function ns.HandledBy(key)
    return (ns.OtherFor(key))
end

-- Eingeschaltet (bzw. ohne Schalter) und nicht schon von einem fremden Addon erledigt.
function ns.Active(key)
    return (ns.ALWAYS[key] ~= nil or ns.Enabled(key)) and ns.HandledBy(key) == nil
end

-- Name einer Funktion für Status und Hinweise: Name des Schalters, ohne Schalter der eigene Text.
function ns.FeatureName(key)
    local own = ns.ALWAYS[key]
    return own and L[own] or L["OPT_" .. key]
end

-- Einmalige Umstellung der gespeicherten Werte nach der Prüfung der Einstellungen vom 19.11.2026 (ezCores
-- Core.MigrateOnce, Merker db.migrated.settings1911): Hatte jemand einen der vier alten Farb-Schalter aus, bleibt
-- der gemeinsame Schalter „Namen und Stufen farbig“ aus (eine bewusste Abwahl geht nicht verloren). Die Schalter, die
-- es nicht mehr gibt, verschwinden aus dem Speicher; ihr alter Wert zählt nicht (die Anzeigen sind jetzt immer an).
-- → Liste der entfernten Schlüssel (nil, wenn die Umstellung schon lief).
ns.OLD_COLOR_KEYS = { "finderLevelColor", "whoColors", "friendColors", "guildColors" }
ns.OLD_KEYS_1911 = { "finderLevels", "finderLocked", "friendAlts", "readyTimer" }
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "settings1911", function() return ns.Adopt1911(db.settings) end)
end

-- Die Zuordnung selbst (auch für ältere Sicherungstexte) → Liste der entfernten Schlüssel
function ns.Adopt1911(S)
    local changed = {}
    for _, key in ipairs(ns.OLD_COLOR_KEYS) do
        if S[key] == false then S.colors = false end
    end
    for _, list in ipairs({ ns.OLD_COLOR_KEYS, ns.OLD_KEYS_1911 }) do
        for _, key in ipairs(list) do
            if S[key] ~= nil then
                S[key] = nil
                changed[#changed + 1] = key
            end
        end
    end
    return changed
end

-- Ältere Sicherungstexte („Alles übernehmen“, ezCores Core.ImportAll; code-reviewer 20.11.2026: sonst ging ein altes
-- whoColors = false verloren und „Namen und Stufen farbig“ blieb an). values ist eine Kopie.
function ns.ImportLegacy(values)
    if type(values) == "table" then ns.Adopt1911(values) end
    return values
end

-- Addons mit derselben Aufgabe wie die Gruppensuche (ezCore: Funktion „lfgBoard“): ezSocial zeigt einen
-- Hinweis. Eigener Text je Addon, weil jedes etwas anderes doppelt macht; neue bekommen den allgemeinen.
ns.LFG_BOARD = "lfgBoard"
ns.LFG_HINTS = { LFGBulletinBoard = "HINT_BULLETIN_BOARD", LFGForever = "HINT_LFGFOREVER" }

function ns.OtherAddonHints()
    local list = {}
    if not ns.OtherFor(ns.LFG_BOARD) then return list end
    for _, other in ipairs(Core.OtherAddOns()) do
        for _, feature in ipairs(other.features or {}) do
            if feature == ns.LFG_BOARD then
                local text = ns.LFG_HINTS[other.key]
                list[#list + 1] = text and L[text] or L.HINT_LFG_BOARD:format(other.label)
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Farben nach Stufe
---------------------------------------------------------------------------

-- Eigene Stufe für die Farben unten: wie Blizzard die wirksame Stufe (Stufensynchronisierung, Zeitwanderung) –
-- Forever-Quelle Blizzard_FrameXMLUtil/Mainline/DifficultyUtil.lua: GetQuestDifficultyColor rechnet mit
-- UnitEffectiveLevel("player"); ohne sie die Stufe aus ezCore, 1, solange der Client sie nicht kennt.
local function PlayerLevel()
    local effective = Core.Num(Core.Call(rawget(_G, "UnitEffectiveLevel"), "player"))
    if effective and effective > 0 then return effective end
    return Core.PlayerLevel() or 1
end

-- r, g, b für die Stufe eines Spielers aus deiner Sicht: Blizzards Quest-Farben (rot … gelb … grau) über ezCore
-- (Core.QuestDifficultyRGB: zuerst der Client, sonst dieselben Grenzen wie Blizzards Forever-Quelle; Paket
-- ezsocial/levelfarbe – vorher eigene Grenzen, die von Blizzards abwichen). Ohne Stufe weiß.
function ns.LevelRGB(level)
    level = Core.Num(level)
    if not level or level <= 0 then return 1, 1, 1 end
    local r, g, b = Core.QuestDifficultyRGB(level, PlayerLevel())
    if not r then return 1, 1, 1 end
    return r, g, b
end

-- Stufenbereich (Zone, Dungeon): Farbe aus ezCore.Dungeons – weiß passt, rot zu schwer, grau zu leicht.
-- nil, wenn es keinen Bereich gibt.
function ns.RangeRGB(minLevel, maxLevel, level)
    local D = Core.Dungeons
    minLevel, maxLevel = Core.Num(minLevel) or 0, Core.Num(maxLevel) or 0
    if minLevel <= 0 and maxLevel <= 0 then return nil end
    if maxLevel <= 0 then maxLevel = minLevel end
    if minLevel <= 0 then minLevel = maxLevel end
    local key = D.Difficulty(minLevel, maxLevel, level or PlayerLevel())
    if not key then return nil end
    return D.Color(key)
end

function ns.Colored(text, r, g, b)
    if not r then return text end
    return Core.ColorCode(r, g, b) .. tostring(text) .. "|r"
end

-- „St. 24“ bzw. „St. 24–28“ (Blizzards Abkürzung LEVEL_ABBR).
function ns.LevelText(minLevel, maxLevel)
    local abbr = _G.LEVEL_ABBR or L.LEVEL_ABBR
    if not maxLevel or maxLevel == minLevel then return abbr .. " " .. minLevel end
    return abbr .. " " .. minLevel .. "–" .. maxLevel
end

---------------------------------------------------------------------------
-- Bekannte Spieler (Freunde, Battle.net, Gilde): ein Kontaktspeicher in ezCore (Core.ContactSource,
-- Zwischenspeicher und Ereignisse dort)
---------------------------------------------------------------------------

-- Quelle ("friend", "bnet", "guild") für einen Namen, sonst nil.
function ns.ContactSource(name)
    return Core.ContactSource(name)
end

---------------------------------------------------------------------------
-- Blizzards Dialoge schließen, nachdem die Anfrage beantwortet ist (Blizzards StaticPopup_Hide)
---------------------------------------------------------------------------

function ns.HidePopup(which)
    if type(StaticPopup_Hide) == "function" then pcall(StaticPopup_Hide, which) end
end

---------------------------------------------------------------------------
-- Fenster „Gruppe suchen“ öffnen: über ezCores Fenster-Dienst (Core.OpenPanel("groupfinder") – Blizzards eigene
-- Umschaltung wie der Knopf im Mikromenü, lädt das Fenster bei Bedarf). ezSocial wählt dort keinen Reiter selbst.
-- Im Kampf öffnet ezCore nichts und zeigt selbst den Hinweis (eine Meldung für alle Module).
---------------------------------------------------------------------------

function ns.FinderShown()
    return _G.LFGParentFrame ~= nil and _G.LFGParentFrame:IsShown()
end

-- → true, wenn das Fenster offen ist; sonst false und der Grund von ezCore ("combat", "missing", "error").
function ns.OpenGroupFinder()
    if ns.FinderShown() then return true end
    local ok, reason = Core.OpenPanel("groupfinder")
    if not ok then
        if reason == "missing" then ns.Print(L.FINDER_MISSING) end
        return false, reason
    end
    return Core.PanelShown("groupfinder") == true or ns.FinderShown()
end

---------------------------------------------------------------------------
-- Datenbank und Login: Core.NewModule oben (db, tables, login). Hier nur, was ezSocial dazu tut.
---------------------------------------------------------------------------

-- Nach dem Gerüst (das ns.RunReady ruft): Hinweise auf Addons mit derselben Aufgabe.
ns.On("PLAYER_LOGIN", function()
    for _, hint in ipairs(ns.OtherAddonHints()) do ns.Print(hint) end
end)

---------------------------------------------------------------------------
-- Schnittstelle für andere Module: ezCore.API("ezSocial")
---------------------------------------------------------------------------

ns.API = {
    -- Blizzards Fenster „Gruppe suchen“ öffnen (zuletzt gewählter Reiter); false im Kampf.
    OpenGroupFinder = function() return ns.OpenGroupFinder() end,
    -- Reiter „Aus dem Chat“ öffnen.
    OpenChatTab = function() return ns.OpenChatTab and ns.OpenChatTab() end,
    -- Gesammelte Gruppen-Nachrichten, neueste zuerst (Kopien): { time, sender, class, text, kind, roles, dungeons }.
    LFGEntries = function() return ns.Chat and ns.Chat.Entries() or {} end,
    -- Ist die Zeile eine Gruppen-Nachricht? "lfm", "lfg" oder nil.
    ClassifyLFG = function(text) return ns.Chat and ns.Chat.Classify(text) end,
}

---------------------------------------------------------------------------
-- Status und Slash-Befehle
---------------------------------------------------------------------------

-- ns.PrintStatus (Kopf ns.StatusHeader(), dann diese Zeilen), ns.HandleSlash und ns.PrintHelp (L.CMD_HELP_OWN) stellt
-- das Gerüst; die Wörter „chat“, „suche“, „finder“, „lfg“ stehen oben in slash.extra.
ns.AddStatusLine(function() return L.STATUS_DUNGEONS:format(#Core.Dungeons.All()) end)
ns.AddStatusLine(function()
    local chat = Core.API("ezChat")
    return (chat and chat.OpenConversation) and L.STATUS_EZCHAT_ON or L.STATUS_EZCHAT_OFF
end)
ns.AddStatusLine(function()
    return ns.Chat and L.STATUS_CHAT:format(#ns.Chat.Entries()) or nil
end)
ns.AddStatusLine(function()
    return ns.Panel and (ns.Panel.Connected() and L.STATUS_PANEL_ON or L.STATUS_PANEL_OFF) or nil
end)
ns.AddStatusLine(function()
    local lines = {}
    for _, key in ipairs(ns.SHARED) do
        local who = (ns.ALWAYS[key] ~= nil or ns.Enabled(key)) and ns.HandledBy(key)
        if who then lines[#lines + 1] = L.STATUS_HANDLED:format(ns.FeatureName(key), who) end
    end
    for _, hint in ipairs(ns.OtherAddonHints()) do lines[#lines + 1] = hint end
    return lines
end)

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte
---------------------------------------------------------------------------

-- Entscheidung 5 (Gesamtreview T18-3, T16-10): Linksklick Reiter „Aus dem Chat“, Rechtsklick Einstellungen; Zeilen
-- und Befehl baut ezCore.
ezSocial_OnAddonCompartmentClick, ezSocial_OnAddonCompartmentEnter, ezSocial_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, owner = ADDON, title = L.TITLE, main = function() ns.API.OpenChatTab() end,
        mainText = L.MAIN_TEXT })
