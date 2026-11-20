local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezMail (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ (setzt ezCore) → Themen → „Erweitert“.
local page

-- Knöpfe der Ablaufwarnung (Leitlinie 3: jede Funktion sichtbar, nicht nur per /ezm).
local function ExpiryButtons(p)
    p:Button(L.OPT_EXPIRY_LIST, L.OPT_EXPIRY_LIST_BUTTON, function() ns.Expiry.Report(true) end, L.OPT_EXPIRY_LIST_TIP)
    p:Button(L.OPT_FORGET, L.OPT_FORGET_BUTTON, function(button) ns.Expiry.ShowForgetMenu(button) end, L.OPT_FORGET_TIP)
end

-- Einträge: Schlüssel (Häkchen), { Schlüssel, min, max, Schritt } (Regler) oder function(page) (Knöpfe).
-- Einstellungs-Prüfung vom 19.11.2026: „Alle Anhänge im Tooltip“, „Wert der Anhänge“, „Bald ablaufende Post
-- hervorheben“ und „Betreff bei reinem Gold“ sind immer an (kein Kästchen); „Taschenplätze frei lassen“ wirkt bei jedem
-- Einsammeln und steht darum unter „Am Briefkasten“ (Regler und Menü 0 bis 20).
local KEEP_FREE_MAX = ns.KEEP_FREE_MAX
local SECTIONS = {
    { L.SECTION_INBOX, { "selectBoxes", "ctrlReturn", "takeAllButton", "letterMenu", "attachYield", "summary", "overview", "auctionMail" } },
    { L.SECTION_SEND, { "addressBook", "lastRecipient", "altAttach", "quickAttach", "followUp", "wire", "wireConfirm" } },
    { L.SECTION_MAILBOX, { "blockTrades", { "keepFree", 0, KEEP_FREE_MAX, 1 } } },
    { L.SECTION_AUTO, { "autoExpress", "autoAHSold", "autoMoney", "autoAHWon", "autoTrusted" } },
    { L.SECTION_EXPIRY, { "loginWarning", { "warnDays", 1, 10, 1 }, ExpiryButtons } },
    { L.SECTION_FILTER, { "openAHSold", "openAHWon", "openAHReturned", "openOther", "openTrusted", "moneyOnly" } },
}

-- Zeilen, die nur unter einer Bedingung erscheinen: „Anhänge im Tooltip Auctionator überlassen“ nur, solange ein Addon
-- mit eigenem Post-Tooltip läuft (ezCore: Funktion mailTooltip, heute Auctionator) – ohne es wirkt der Schalter nicht.
-- Reine Auskunft (ns.OtherInfo): Blizzard prüft die Bedingung bei jedem Aufbau der Liste, das ist kein „gewichen“.
local SHOWN = {
    attachYield = function() return ns.OtherInfo("mailTooltip") ~= nil end,
}

-- Unterschalter grau, solange ihr Oberschalter aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung
-- 19.11.2026): was „Beim Öffnen einsammeln“ nimmt, gilt nur für diesen Lauf (Express.lua, Runner.lua WantedAuto);
-- „Nachfragen“ gehört zum Knopf „Überweisen“, den es nur mit wire gibt (Wire.lua). warnDays nicht: die Frist gilt auch
-- für die Hervorhebung, die immer an ist (ezCore Mail.WarnDays).
ns.OPTION_PARENT = {
    autoAHSold = "autoExpress", autoMoney = "autoExpress", autoAHWon = "autoExpress", autoTrusted = "autoExpress",
    wireConfirm = "wire",
}

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end
    for _, section in ipairs(SECTIONS) do
        page:Header(section[1])
        for _, entry in ipairs(section[2]) do
            if type(entry) == "function" then
                entry(page)
            elseif type(entry) == "table" then
                page:Slider(entry[1], entry[2], entry[3], entry[4])
            elseif ns.DEFAULTS[entry] ~= nil then
                page:Checkbox(entry, nil, { shown = SHOWN[entry], parent = ns.OPTION_PARENT[entry] })
            end
        end
    end
    -- Verlauf und Statistik: die Daten zeichnet ezCore auf, der Reiter am Posteingang zeigt sie.
    page:Header(L.SECTION_HISTORY)
    page:Checkbox("history")
    page:Button(L.OPT_STATS, L.OPT_STATS_BUTTON, function() ns.History.PrintStats() end, L.OPT_STATS_TIP)
    -- Absender-Regeln: verwaltet werden sie am Briefkasten (Pfeil-Menüs); hier die Übersicht.
    page:Header(L.SECTION_RULES)
    page:Button(L.OPT_RULES, L.OPT_RULES_BUTTON, function() ns.Rules.PrintList() end, L.OPT_RULES_TIP)

    page:Advanced()
    -- Knopf „Status“ aus ezCore (ruft ns.PrintStatus), mit ezMails eigenem Tooltip
    page:StatusButton(L.OPT_STATUS_TIP)
    page:Checkbox("statusLog")
    -- Erklärblasen beim nächsten Öffnen des Postfensters wieder von vorn (Tour.lua)
    page:TourButton(ns.Tour.Object())
    -- Rückfrage, Zurücksetzen und Meldung kommen aus ezCore; der eigene Tooltip sagt, was bleibt.
    page:ResetButton({ tip = L.OPT_RESET_TIP })
    -- Ergänzende Addons anderer Autoren (Core.AddCompanion): für ezMail derzeit keine – Pflicht ist nur ezCore,
    -- und neben Auctionator lässt ezMail nur auf Wunsch etwas weg (Schalter „attachYield“). Der Abschnitt erscheint,
    -- sobald einer eingetragen ist.
    page:Companions()
    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
