local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = {
    selectBoxes = true,
    ctrlReturn = true,
    takeAllButton = true,
    letterMenu = true,
    -- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 8, 9 und Abschnitt 4), ohne Schalter: alle Anhänge im
    -- Tooltip, Wert der Anhänge, bald ablaufende Post hervorheben; ebenso der Betreff bei reinem Gold (Nr. 10).
    -- Gespeicherte Werte attachTooltip, attachValue, expiryColors, autoSubject bleiben unbeachtet liegen.
    attachYield = false,        -- neben Auctionator Anhang-Liste und Wert im Tooltip weglassen (MAIL-11); ab Werk aus
    summary = true,
    overview = true,
    auctionMail = true,         -- Zeile „Auktionspost“ über der Briefliste und in der Übersicht (AH-33)
    history = true,
    addressBook = true,
    lastRecipient = false,
    altAttach = true,
    quickAttach = true,
    followUp = true,
    wire = true,
    wireConfirm = true,         -- vor dem Überweisen über die Warteschlange einmal nachfragen (MAIL-01); ab Werk an
    blockTrades = false,
    loginWarning = true,
    warnDays = 3,               -- liegt in ezCore (Mail.WarnDays), siehe SHARED unten; hier nur Standard des Reglers
    -- Gefiltertes „Alle öffnen“
    openAHSold = true,
    openAHWon = true,
    openAHReturned = true,
    openOther = true,
    openTrusted = true,
    moneyOnly = false,
    keepFree = 0,
    -- Beim Öffnen des Briefkastens einsammeln (Auto-Express)
    autoExpress = false,
    autoAHSold = true,
    autoMoney = true,
    autoAHWon = false,
    autoTrusted = true,
    -- Erweitert: Status bei jedem Briefkastenbesuch still in ezMailDB.status mitschreiben (Fehlersuche; V-066)
    statusLog = false,
}

-- Höchstwert von „Taschenplätze frei lassen“ – derselbe für den Regler der Einstellungsseite und das Menü am Knopf
-- „Alle öffnen“ (Einstellungs-Prüfung vom 19.11.2026: vorher Regler bis 20, Menü bis 10)
ns.KEEP_FREE_MAX = 20

-- Schalter für Einstellungen und Slash-Befehle (Schlüssel, deutscher Befehl, en = englisches Wort – T10-1: im
-- englischen Client nennt die Hilfe diese Wörter)
ns.TOGGLES = {
    { "selectBoxes", "auswahl", en = "select" },
    { "ctrlReturn", "strgklick", en = "ctrlclick" },
    { "takeAllButton", "allesnehmen", en = "takeall" },
    { "letterMenu", "briefmenue", en = "lettermenu" },
    { "attachYield", "ruecksicht", en = "yield" },
    { "summary", "summe", en = "summary" },
    { "overview", "uebersicht", en = "overview" },
    { "auctionMail", "auktionspost", en = "auctionmail" },
    { "history", "verlauf", en = "history" },
    { "addressBook", "adressbuch", en = "addressbook" },
    { "lastRecipient", "letzter", en = "last" },
    { "altAttach", "altklick", en = "altclick" },
    { "quickAttach", "schnell", en = "quick" },
    { "followUp", "nachsenden", en = "followup" },
    { "wire", "ueberweisen", en = "wire" },
    { "wireConfirm", "nachfragen", en = "confirm" },
    { "blockTrades", "handel", en = "trade" },
    { "loginWarning", "warnung", en = "warning" },
    { "autoExpress", "express", en = "express" },
}

-- Filter für das gefilterte „Alle öffnen“.
ns.FILTERS = { "openAHSold", "openAHWon", "openAHReturned", "openOther", "openTrusted", "moneyOnly" }

-- Was beim Öffnen des Briefkastens eingesammelt wird (Auto-Express, Express.lua).
ns.AUTO_KINDS = { "autoAHSold", "autoMoney", "autoAHWon", "autoTrusted" }

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore
-- Print, Try (Fehler mit Ort, für /ezm status in ns.problems), Error, On, Listen/Fire (innerhalb
-- von ezMail), OnReady, OnSettingChanged, SettingChanged, SetSetting (Zahlen bleiben Zahlen), AfterCombat …
-- Dazu ezCores Gerüst (Framework.lua): Datenbank (ezMailDB, settings mit Standardwerten, hints, recent), die
-- Befehle /ezmail und /ezm (Einstellungen, status, hilfe, Schalter aus ns.TOGGLES; eigene Wörter in ns.SlashExtra)
-- und die Statuszeilen (ns.AddStatusLine). /ezm gehört ezMail, kommt aber wie jeder Kurzbefehl aus Core.SLASH_ALIASES
-- und nur, wenn ihn kein anderes Addon belegt (Gesamtreview 18.11.2026, T18-15; ezMacro nimmt /ezmc, T18-14).
-- Ist ezCore zu alt (core/needs), meldet es das einmal und ezMail bleibt still.
Core.NewModule(ADDON, ns, {
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CmdText, Core.QualityText, Core.TipTitle
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    -- scaffoldHelpers (ns.InCombat, ns.OtherFor des Gerüsts), Now, Uptime, UnitIs und Mail.CommandPending kamen nach
    -- ezCore 1.11.0 ohne neue Nummer dazu; OpenMail.lua und Runner.lua binden Mail.CommandPending beim Laden.
    needs = { "scaffold", "sideTabStack", "tourOwner", "AfterCombat", "ClosePanel", "Mail.Postage",
        "History.PeriodLabel", "ItemClassName", "scaffoldHelpers", "Now", "Uptime", "UnitIs", "Mail.CommandPending",
        -- Design-System (Welle 22): Farb-Rollen, Knopfgrößen und „Alle auswählen / Alle abwählen“
        "Style.ColorText", "Style.AllText", "Style.BUTTON", "Menu.AllToggle",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More", "ResolveGrammar", "L.ALL_CHARS",
        -- Gesamtreview 18.11.2026 (T4-NR8): eine Erreichbarkeits-Regel für Twinks und Kontakte
        "MailReachable",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer)
        "compartmentMain", "slashMain", "SlashCmd", "TipTitle", "TipLine", "Toolbar.ShowTipWhileDisabled",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CmdText", "Word",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "Migrated", "PlaySound", "QualityText" },
    db = "ezMailDB",
    tables = { "hints", "recent" },   -- recent: [Realm] = { "Name", ... } – zuletzt angeschriebene Empfänger
    onLoad = function(db) return ns.OnLoad(db) end,
    -- /ezm über Core.SLASH_ALIASES (T18-15); ohne Wort wie der Linksklick im Addon-Fach (Entscheidung 5)
    slash = {
        commands = { "/ezmail" },
        extra = function(cmd, rest) return ns.SlashExtra(cmd, rest) end,
        main = function() ns.Expiry.Report(true) end,
        mainText = L.COMPARTMENT_MAIN,
    },
})

-- ns.CmdText(text) (%s durch den geltenden Befehl: „/ezm“, solange kein anderes Addon ihn belegt, sonst „/ezmail“;
-- T18-2) legt Core.NewModule an (Core.CmdText) – erst beim Zeigen aufrufen.

ns.CreateCheck = Core.CreateCheck       -- Häkchen im Blizzard-Stil
ns.CreateSideTab = Core.CreateSideTab   -- Seitenreiter wie im Zauberbuch
ns.SideTabClick = Core.SideTabClick
ns.CoinText = Core.CoinText
ns.PlainMoney = Core.PlainMoney         -- Geld als reiner Text, z. B. für einen Betreff
ns.TimeText = Core.TimeLeft             -- Restzeit mit Blizzards Wortlaut
ns.ClassColored = Core.ClassText
ns.RealmKey = Core.RealmKey
ns.MailRealms = Core.MailRealms
ns.ShowTip = Core.ShowTip
ns.TipScript = Core.TipScript

-- Charakterdaten: eine Quelle für alle Module (ezCore). ezMail führt keine eigene Twink-Liste.
ns.Chars = Core.Chars
ns.CharInfo = Core.CharInfo

-- Briefkasten (ezCore.Mail): Kopfdaten, Wiedererkennen, Auktionshaus-Post, leere Briefe.
ns.NumMails = Core.Mail.NumMails
ns.Header = Core.Mail.Header
ns.Signature = Core.Mail.Signature
ns.MailCategory = Core.Mail.Category
ns.IsEmptyRead = Core.Mail.IsEmptyRead
ns.FreeBagSlots = Core.FreeBagSlots
ns.ForEachBagItem = Core.ForEachBagItem

-- Versand-Warteschlange (ezCore.MailQueue): Meldungen mit ezMail-Vorsatz, Änderungen als QUEUE_CHANGED.
ns.SendQueue = setmetatable({
    Add = function(to, subject, body, entries, callback)
        return Core.MailQueue.Add(to, subject, body, entries, callback, ns)
    end,
}, { __index = Core.MailQueue })
Core.Listen("MAIL_QUEUE_CHANGED", function() ns.Fire("QUEUE_CHANGED") end, ADDON)

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------

-- Grenzwert für ablaufende Post: einer für ezMail und ezPanel, gespeichert in ezCore (Mail.WarnDays).
-- ns.S.warnDays ist nur ein Fenster darauf: Lesen fragt ezCore, Schreiben (Regler, /ezm tage) setzt dort.
-- So bleiben Regler, SetSetting und OnSettingChanged unverändert, und es gibt keinen zweiten Wert.
local settingShared = false     -- ezMail setzt gerade selbst (SetSetting meldet die Änderung dann schon)
local SHARED = {
    warnDays = {
        get = function() return Core.Mail.WarnDays() end,
        set = function(v)
            settingShared = true
            Core.Mail.SetWarnDays(v)
            settingShared = false
        end,
    },
}
-- Ändert ein anderes Modul den Grenzwert (ezPanel), zeichnet ezMail wie nach dem eigenen Regler neu.
Core.Listen("MAIL_WARN_DAYS_CHANGED", function()
    if not settingShared and ns.S then ns.SettingChanged("warnDays") end
end, ADDON)
local SETTINGS_VIEW = {
    __index = function(_, key)
        local shared = SHARED[key]
        if shared then return shared.get() end
    end,
    __newindex = function(t, key, value)
        local shared = SHARED[key]
        if shared then return shared.set(value) end
        rawset(t, key, value)
    end,
}

-- Eigene Werte, die jetzt in ezCore liegen, einmal übernehmen und dann vergessen.
local function MigrateShared(settings)
    local old = rawget(settings, "warnDays")
    if old == nil or type(Core.db) ~= "table" then return end
    old = tonumber(old)
    if old and old ~= ns.DEFAULTS.warnDays then Core.Mail.SetWarnDays(old) end
    rawset(settings, "warnDays", nil)
end

-- Nach dem Gerüst (ezMailDB steht, settings sind aufgefüllt, ns.db und ns.S gesetzt): das Fenster auf ezCores
-- Grenzwert einhängen. Das Gerüst hat warnDays zuvor wie jeden Standardwert eingetragen – ein alter eigener Wert
-- (nicht 3) zieht einmal nach ezCore um, danach liegt in den eigenen Einstellungen keiner mehr.
-- Alte Ablaufzeiten der Post (ezMailDB.expiry, bis 1.4): ezCore übernimmt sie einmal beim Einloggen
-- (Characters.Migrate; Auskunft Core.Migrated("ezMail"), seit dem Gesamtreview vom 18.11.2026, T4-5, statt eines Blicks
-- in ezCoreDB.migrated) nach ezCoreDB.chars[…].mailbox. Danach hat der alte Stand
-- keinen Leser mehr und wird still gelöscht (Entscheidung C vom 13.11.2026, MAIL-03) – vorher nie, sonst ginge er
-- bei einem ersten Start mit neuem ezCore verloren. → true, wenn gelöscht.
function ns.DropOldExpiry(db)
    if type(db) ~= "table" or db.expiry == nil then return false end
    if not (type(Core.Migrated) == "function" and Core.Migrated("ezMail")) then return false end
    db.expiry = nil
    return true
end

function ns.OnLoad(db)
    MigrateShared(db.settings)
    setmetatable(db.settings, SETTINGS_VIEW)
    -- Nur ezMail-eigene Daten; Charakterdaten und Ablaufzeiten der Post liefert ezCore (ezCoreDB.chars[…].mailbox)
    db.chars = nil
    ns.DropOldExpiry(db)
    -- Still mitgeschriebener Status früherer Besuche (V-066): ohne den Schalter „statusLog“ nicht aufheben.
    -- Ein mit /ezm status oder dem Knopf selbst abgelegter Stand bleibt.
    if not db.settings.statusLog and type(db.status) == "table" and db.status.auto then db.status = nil end
end

-- Blizzards Postfenster gibt es in zwei Fassungen (Forever: Mixins, älteres Retail: Globale).
-- Die Weiche steckt in ezCore.Mail und ist die einzige Stelle, die den Unterschied kennt.
ns.UpdateInbox = Core.Mail.UpdateInbox
ns.HookInboxUpdate = Core.Mail.HookInboxUpdate
ns.HookOpenMailUpdate = Core.Mail.HookOpenMailUpdate
ns.OpenMailIndex = Core.Mail.OpenMailIndex
ns.ReturnOpenMail = Core.Mail.ReturnOpenMail

-- Blizzards Postfenster: alles daran erst einhängen, wenn es da ist. Versucht wird beim Einloggen,
-- wenn ein Addon nachlädt und spätestens beim Öffnen des Briefkastens.
ns.MailUIMissing = Core.Mail.UIMissing
local mailUICallbacks = {}

local function TryMailUI(source)
    if ns.mailUIReady or not ns.ready or #ns.MailUIMissing() > 0 then return end
    ns.mailUIReady = source
    for _, entry in ipairs(mailUICallbacks) do ns.Try(entry.where, entry.fn) end
end

-- where: Name für Fehlermeldungen und /ezm status.
function ns.WhenMailUI(where, fn)
    if ns.mailUIReady then
        ns.Try(where, fn)
    else
        table.insert(mailUICallbacks, { where = where, fn = fn })
    end
end

-- Zähler für /ezm status: Kommen die Briefkasten-Ereignisse überhaupt an?
ns.seen = { MAIL_SHOW = 0, MAIL_INBOX_UPDATE = 0, INTERACTION = 0 }

ns.On("ADDON_LOADED", function() TryMailUI("ADDON_LOADED") end)
ns.On("MAIL_SHOW", function()
    ns.seen.MAIL_SHOW = ns.seen.MAIL_SHOW + 1
    TryMailUI("MAIL_SHOW")
end)
ns.On("MAIL_INBOX_UPDATE", function() ns.seen.MAIL_INBOX_UPDATE = ns.seen.MAIL_INBOX_UPDATE + 1 end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function()
    ns.seen.INTERACTION = ns.seen.INTERACTION + 1
    TryMailUI("INTERACTION")
end)

ns.On("PLAYER_LOGIN", function()
    -- Charakter und Realm kommen aus ezCore (dort schon beim Einloggen gesetzt).
    ns.realm, ns.charKey = Core.realm, Core.charKey
    ns.ready = true
    -- ezCores Übernahme der alten Ablaufzeiten lief eben (sein Zuhörer kommt zuerst): den alten Stand jetzt löschen
    ns.DropOldExpiry(ns.db)
    -- ezCore zu alt für ezMail (Core.Require hat es gemeldet): nichts einhängen.
    if ns.RunReady() == false then
        ns.ready = false
        return
    end
    TryMailUI("PLAYER_LOGIN")
end)

---------------------------------------------------------------------------
-- Status (/ezm status): was ist eingehängt, was fehlt, welche Fehler gab es
---------------------------------------------------------------------------

-- Die Zeilen der einzelnen Dateien sammelt ezCores Gerüst (ns.AddStatusLine); ns.OnStatus bleibt als der Name,
-- unter dem ezMails Dateien sie anmelden. ezMail setzt nur den eigenen Kopf davor (Postfenster, Ereignisse).
local ModuleLines = ns.StatusLines
function ns.OnStatus(fn) ns.AddStatusLine(fn) end

-- Versand-Warteschlange (ezCore): Nachsenden mit Anhängen und wartende Textbriefe.
ns.OnStatus(function() return Core.MailQueue.StatusLine() end)

local OPTIONAL_PARTS = { "OpenAllMail", "MailItem1Button", "SendMailNameEditBox", "InboxFrameItem_OnEnter",
    "OpenMailDeleteButton", "MenuUtil", "C_Mail", "SendMailMailButton", "SendMailAttachment1",
    "SendMailAttachment_OnEnter", "OpenMailSubject", "OpenMailScrollChildFrame", "StaticPopup_Show" }

function ns.StatusLines()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    Add(ns.StatusHeader())     -- ezCores Kopfzeile „Version x – Status:“ (Frage 8; ns.Print setzt „ezMail:“ davor)
    Add(L.STATUS_READY:format(ns.ready and L.YES or L.NO,
        ns.mailUIReady and (L.YES .. " (" .. tostring(ns.mailUIReady) .. ")") or L.NO))
    local missing = ns.MailUIMissing()
    Add(L.STATUS_MISSING:format(#missing > 0 and table.concat(missing, ", ") or L.NONE))
    local parts = {}
    for _, name in ipairs(OPTIONAL_PARTS) do
        parts[#parts + 1] = name .. (_G[name] ~= nil and " +" or " –")
    end
    Add("  " .. table.concat(parts, ", "))
    Add(L.STATUS_EVENTS:format(ns.seen.MAIL_SHOW, ns.seen.MAIL_INBOX_UPDATE, ns.seen.INTERACTION))
    local function Visible(name)
        local frame = _G[name]
        if not frame or not frame.IsVisible then return L.STATUS_MISSING_PART end
        return frame:IsVisible() and L.YES or L.NO
    end
    local row = _G.MailItem1Button
    Add(L.STATUS_FRAMES:format(Visible("MailFrame"), Visible("InboxFrame"), Visible("MailItem1"),
        tostring(row and row.index)))
    for _, line in ipairs(ModuleLines()) do Add("  " .. line) end
    local req = Core.Requirement and Core.Requirement(ADDON)
    if req and req.text then Add("  " .. req.text) end
    if #ns.problems == 0 then
        Add(L.STATUS_NO_PROBLEMS)
    else
        Add(L.STATUS_PROBLEMS:format(#ns.problems))
        for i, text in ipairs(ns.problems) do Add("  " .. i .. ") " .. text) end
    end
    return lines
end

-- Zeilen für die Datei: Blizzards „|4Einzahl:Mehrzahl;“ löst nur ein Schriftfeld auf, gespeichert wird aufgelöst
-- (ezCore.ResolveGrammar, Welle 17).
local function Resolved(lines)
    local out = {}
    for i, line in ipairs(lines) do out[i] = Core.ResolveGrammar(line) end
    return out
end

-- Zeigt den Status im Chat und legt ihn in ezMailDB.status ab (nach /reload auf der Festplatte lesbar).
function ns.PrintStatus()
    local lines = ns.StatusLines()
    for _, line in ipairs(lines) do ns.Print(line) end
    ns.db.status = { at = date("%Y-%m-%d %H:%M:%S"), lines = Resolved(lines) }
end

-- Beim Öffnen des Briefkastens den Status still mitschreiben – für die Fehlersuche ohne Screenshot.
-- Nur mit dem Schalter „Status mitschreiben“ unter „Erweitert“ (ab Werk aus, V-066): sonst schriebe ezMail bei
-- jedem Besuch in die gespeicherten Daten, obwohl niemand sucht.
function ns.LogStatus()
    if not (ns.S and ns.S.statusLog) then return false end
    local ok, lines = pcall(ns.StatusLines)
    ns.db.status = { at = date("%Y-%m-%d %H:%M:%S"), auto = true, lines = ok and Resolved(lines) or { tostring(lines) } }
    return true
end
ns.On("MAIL_SHOW", function()
    if not ns.S.statusLog then return end
    C_Timer.After(1.5, ns.LogStatus)
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

-- /ezmail (und /ezm, wenn frei) setzt ezCores Gerüst (Core.NewModule oben): ohne Wort die Hauptfunktion wie der
-- Linksklick im Addon-Fach (slash.main: gespeicherte Post aller Charaktere, Entscheidung 5 vom 18.11.2026),
-- „optionen“ die Einstellungen, „status“, „hilfe“ und die Schalter aus ns.TOGGLES. Hier nur ezMails eigene Wörter;
-- true = erledigt.

function ns.SlashExtra(cmd, rest)
    if cmd == "oeffnen" or cmd == "öffnen" or cmd == "open" then
        ns.Runner.Start("open")
    elseif cmd == "stopp" or cmd == "stop" then
        ns.Runner.Stop()
        ns.SendQueue.Stop()
        ns.Send.ClearFollowUp()
    elseif cmd == "aufraeumen" or cmd == "aufräumen" or cmd == "clean" then
        ns.Inbox.DeleteEmpty()
    elseif cmd == "tage" or cmd == "days" then
        local days = tonumber(rest)
        if days and days >= 1 and days <= 30 then
            ns.SetSetting("warnDays", floor(days))
            ns.Print(L.CMD_DAYS:format(ns.S.warnDays))
        else
            ns.Print(ns.CmdText(L.CMD_DAYS_USAGE))
        end
    elseif cmd == "regel" or cmd == "rule" then
        ns.Rules.Slash(rest)
    elseif cmd == "regeln" or cmd == "rules" then
        ns.Rules.PrintList()
    elseif cmd == "statistik" or cmd == "stats" then
        ns.History.PrintStats(rest)
    elseif cmd == "ablaufliste" or cmd == "post" or cmd == "list" then
        ns.Expiry.Report(true)
    elseif cmd == "leeren" or cmd == "clear" then
        ns.Send.ClearRecent()
        ns.Print(L.BOOK_CLEARED)
    elseif cmd == "vergessen" or cmd == "forget" then
        -- Nur den Briefkasten-Stand (Ablaufzeiten) über ezCore; den Charakter selbst behält ezCore.
        ns.Expiry.ForgetCommand(rest)
    else
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc …; Tooltip und Fehlerschutz über ezCore.CompartmentHandlers,
-- ein Fehler beim Klick landet in ezCores Fehlerliste /ez fehler)
---------------------------------------------------------------------------

-- Entscheidung 5 vom 18.11.2026 (T18-3, T16-10): Linksklick = Hauptfunktion – gespeicherte Post aller Charaktere wie
-- „/ezm post“ (vorher Rechtsklick) –, Rechtsklick = Einstellungen (sonst die Hilfe). Tooltip und Befehlszeile baut ezCore.
ezMail_OnAddonCompartmentClick, ezMail_OnAddonCompartmentEnter, ezMail_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({
        ns = ns, title = L.TITLE, main = function() ns.Expiry.Report(true) end, mainText = L.COMPARTMENT_MAIN,
        owner = ADDON,
    })
-- früherer Name des Klicks: dieselbe Belegung wie das Addon-Fach
function ns.CompartmentClick(button) return ezMail_OnAddonCompartmentClick(nil, button) end
