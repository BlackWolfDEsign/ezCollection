local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quelle „Auktionen: verkauft oder abgelaufen“ für ezPanels Baustein „Meldungen“ (docs/roadmap/ezPanel.md,
    „Welle 2b“: erste Nutzer von ezCore.API("ezPanel").AddWarning). Frage 17 der Vollprüfung nennt ezAuction nicht
    ausdrücklich – Empfehlung umgesetzt, Antwort offen; abwählbar ist die Quelle in ezPanel (Baustein „Meldungen“,
    Menü „Quellen“).

    Woher: Der Client meldet dem angemeldeten Charakter, wenn eine seiner Auktionen verkauft wurde oder abgelaufen
    ist – dieselbe Nachricht, die Blizzard als gelbe Zeile in den Chat schreibt (Ereignisse
    AUCTION_HOUSE_SHOW_NOTIFICATION und AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION mit einem Wert aus Blizzards
    Enum.AuctionHouseNotification; nachgelesen in Blizzards Schnittstellen-Beschreibung, Zweig forever). ezAuction
    zählt je Charakter mit (ezAuctionDB.ui.notices), bis der Spieler den Briefkasten öffnet (MAIL_SHOW). Ein
    abgelaufener Gegenstand liegt dann dort. Das Gold eines Verkaufs kommt verzögert: zunächst liegt nur Blizzards
    Ankündigung mit der Ankunftszeit im Briefkasten (Brief-Typ "seller_temp_invoice" in Blizzards MailFrame.lua,
    Zweig forever) – deshalb sagt der Text „das Gold kommt mit der Post“, nicht „liegt in der Post“. Gelöscht wird
    die Meldung trotzdem beim ersten Besuch: der Spieler weiß dann Bescheid, wann das Gold da ist, sagt ihm
    Blizzards Brief. Was geschah, während der Charakter nicht angemeldet war, meldet der Client nicht – das zeigt
    weiter nur „neue Post“.

    Ohne ezPanel (oder mit einem ezPanel ohne AddWarning) geschieht nichts: kein Zuhörer, kein Zähler.
]]

local Notice = {}
ns.Notice = Notice

Notice.KEY = "ezAuction.mail"
-- Art → Name in Blizzards Enum.AuctionHouseNotification; fehlt ein Name auf dem Client, zählt er nicht.
Notice.NAMES = { sold = "AuctionSold", expired = "AuctionExpired" }
Notice.ORDER = { "sold", "expired" }

-- Art einer Benachrichtigung des Clients: "sold" | "expired" | nil (alles andere: Gebot, Kauf, Abbruch …).
function Notice.Kind(code)
    local codes = Enum and Enum.AuctionHouseNotification
    if Core.IsSecret(code) or code == nil or type(codes) ~= "table" then return nil end
    for _, kind in ipairs(Notice.ORDER) do
        local value = codes[Notice.NAMES[kind]]
        if value ~= nil and value == code then return kind end
    end
    return nil
end

-- Zähler dieses Charakters (create = true legt ihn an).
local function Store(create)
    local ui = ns.db and ns.db.ui
    local key = ns.charKey
    if not (type(ui) == "table" and key) then return nil end
    if type(ui.notices) ~= "table" then
        if not create then return nil end
        ui.notices = {}
    end
    if type(ui.notices[key]) ~= "table" then
        if not create then return nil end
        ui.notices[key] = {}
    end
    return ui.notices[key]
end

-- Verkauft, abgelaufen – seit dem letzten Besuch am Briefkasten.
function Notice.Counts()
    local mine = Store(false)
    if not mine then return 0, 0 end
    return Core.Num(mine.sold) or 0, Core.Num(mine.expired) or 0
end

-- ezPanels Schnittstelle, wenn sie Meldungen annimmt; sonst nil.
function Notice.Panel()
    local panel = Core.API("ezPanel")
    return type(panel) == "table" and type(panel.AddWarning) == "function" and panel or nil
end

local function Changed()
    local panel = Notice.Panel()
    if panel then Core.Call(panel.RefreshWarnings) end
end

-- Eine Benachrichtigung des Clients mitzählen. Rückgabe: die Art, wenn gezählt wurde, sonst nil.
function Notice.Add(code)
    local kind = Notice.Kind(code)
    local mine = kind and Store(true)
    if not mine then return nil end
    mine[kind] = (Core.Num(mine[kind]) or 0) + 1
    Changed()
    return kind
end

-- Am Briefkasten gewesen: die Meldung ist erledigt. Rückgabe: true, wenn etwas gezählt war.
function Notice.Clear()
    local sold, expired = Notice.Counts()
    local ui = ns.db and ns.db.ui
    if type(ui) == "table" and type(ui.notices) == "table" and ns.charKey then ui.notices[ns.charKey] = nil end
    if sold + expired == 0 then return false end
    Changed()
    return true
end

-- Vergisst ezCore einen Twink (Core.ForgetChar, Nachricht CHAR_FORGOTTEN), geht sein Zähler mit
-- (ezAuctionDB.ui.notices[key]; Gesamtreview 18.11.2026, T4-2). Die Leiste zeigt nur den angemeldeten Charakter –
-- dessen Zähler bleibt. → true, wenn etwas gezählt war.
function Notice.Forget(key)
    local ui = ns.db and ns.db.ui
    if type(key) ~= "string" or key == ns.charKey or type(ui) ~= "table" or type(ui.notices) ~= "table" then
        return false
    end
    if ui.notices[key] == nil then return false end
    ui.notices[key] = nil
    return true
end
Core.Listen("CHAR_FORGOTTEN", function(key) Notice.Forget(key) end, ADDON)

-- Text der Meldung für die Leiste: „Auktionen: 2 verkauft (das Gold kommt mit der Post), 1 abgelaufen (liegt in
-- der Post)“; nil = nichts zu melden.
function Notice.Text()
    local sold, expired = Notice.Counts()
    local parts = {}
    if sold > 0 then parts[#parts + 1] = L.NOTICE_SOLD:format(sold) end
    if expired > 0 then parts[#parts + 1] = L.NOTICE_EXPIRED:format(expired) end
    if #parts == 0 then return nil end
    return L.NOTICE_TEXT:format(table.concat(parts, ", "))
end

-- Bei ezPanel anmelden (einmal, im ns.OnReady – dann sind alle Addons geladen) und erst dann zuhören.
-- Rückgabe: true, wenn die Quelle angemeldet ist.
function Notice.Register()
    if Notice.registered then return true end
    local panel = Notice.Panel()
    if not panel or panel.AddWarning(Notice.KEY, L.NOTICE_SOURCE, Notice.Text) ~= true then return false end
    Notice.registered = true
    ns.On("AUCTION_HOUSE_SHOW_NOTIFICATION", function(_, code) Notice.Add(code) end)
    ns.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", function(_, code) Notice.Add(code) end)
    ns.On("MAIL_SHOW", function() Notice.Clear() end)
    return true
end

ns.OnReady(function() ns.Try("Notice", Notice.Register) end)

ns.AddStatusLine(function()
    if not Notice.registered then return nil end
    return L.STATUS_NOTICE:format(L.NOTICE_SOURCE)
end)
