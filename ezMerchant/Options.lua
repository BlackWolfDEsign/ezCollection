local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezMerchant (Seite von ezCore).
-- Aufbau wie jede Modulseite: „Allgemein“ → Themen → „Erweitert“.
local page

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    local function Columns(value) return L.UNIT_COLUMNS:format(value) end
    local function Rows(value) return L.UNIT_ROWS:format(value) end
    local limits = ns.LIMITS

    -- Allgemein: Hauptschalter
    page:Checkbox("merchant")

    -- Spalten, Zeilen, Marken und Stapel-Knopf gehören zum erweiterten Händlerfenster (M.Active verlangt „merchant“) –
    -- grau, solange es aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Header(L.OPT_HEADER_MERCHANT)
    page:Slider("columns", limits.columns[1], limits.columns[2], 1, Columns, nil, { parent = "merchant" })
    page:Slider("rows", limits.rows[1], limits.rows[2], 1, Rows, nil, { parent = "merchant" })
    page:Checkbox("markMissing", nil, { parent = "merchant" })
    page:Checkbox("markUpgrade", nil, { parent = "merchant" })
    page:Checkbox("stackButton", nil, { parent = "merchant" })
    page:Checkbox("vendorTip")      -- Tooltip des Händlers: Sortiment laut deinem letzten Besuch (VendorTip.lua)

    -- Die Filter der Warenliste (Nur nutzbare, Bekanntes ausblenden …) stehen seit der Einstellungs-Prüfung vom
    -- 19.11.2026 nur im Menü am Knopf „Filter“ des Händlerfensters (Merchant.lua, M.BuildMenu).

    -- Reparatur und Plunder-Automatik: Spiegel von ezCores gemeinsamen Schaltern (ns.SHARED in Core.lua). Nur die
    -- Meldung ist grau, solange „Automatisch reparieren“ aus ist; „Zuerst mit Gildengeld“ gilt auch für „Jetzt
    -- reparieren“ und bleibt bedienbar (wie im Abschnitt „Gemeinsame Schalter“ von ezCore; Gegenprüfung 19.11.2026)
    page:Header(L.OPT_HEADER_REPAIR)
    page:Checkbox("repairAuto")
    page:Checkbox("repairGuild")
    page:Checkbox("repairReport", nil, { parent = "repairAuto" })
    page:Button(L.OPT_REPAIR_NOW, L.OPT_REPAIR_NOW_BUTTON, function() ns.API.RepairNow() end, L.OPT_REPAIR_NOW_TIP)

    -- Plunder (Junk.lua): Knopf und Schalter stehen im Menü „Filter“; hier derselbe Schalter wie in ezBag
    page:Header(L.OPT_HEADER_JUNK)
    page:Checkbox("autoSellJunk")
    page:Button(L.OPT_SELL_JUNK, L.OPT_SELL_JUNK_BUTTON, function() ns.Junk.SellNow() end, L.OPT_SELL_JUNK_TIP)
    -- Auktionswert (AH-27): Zeile unter dem Händlerfenster und Auslassen beim Plunder-Verkauf; Rechnung in ezCore
    page:Checkbox("auctionWorth")
    page:Checkbox("keepAuctionWorth")

    -- Vorrat (Restock.lua): Knopf, Automatik und die Übersicht der Sollmengen dieses Charakters
    page:Header(L.OPT_HEADER_RESTOCK)
    page:Checkbox("restock")
    -- Automatik und „Jetzt auffüllen“ ruhen ohne „restock“ (Restock.Run) – grau, solange es aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Checkbox("restockAuto", nil, { parent = "restock" })
    page:Button(L.OPT_RESTOCK_NOW, L.OPT_RESTOCK_NOW_BUTTON, function() ns.Restock.Run(false) end, L.OPT_RESTOCK_NOW_TIP,
        { parent = "restock" })
    page:Button(L.OPT_RESTOCK_LIST, L.OPT_RESTOCK_LIST_BUTTON, function() ns.Restock.PrintList() end, L.OPT_RESTOCK_LIST_TIP)
    -- Blizzards Standardwort „Löschen“ (T18-22) über Core.Word – den Rückfall hält ezCore
    page:Button(L.OPT_RESTOCK_CLEAR, ezCore.Word("DELETE"), function()
        ezCore.Confirm(L.RESTOCK_CLEAR_CONFIRM, function()
            ns.Restock.Clear()
            ns.Print(L.RESTOCK_CLEARED)
        end)
    end, L.OPT_RESTOCK_CLEAR_TIP)

    page:Header(L.OPT_HEADER_TRAINER)
    -- Übernimmt ein anderes Addon „alles lernen“ (Core.OTHER_ADDONS, Funktion trainAll), hängt ezCore den Satz
    -- „Übernimmt schon: …“ selbst an den Tooltip (page:Checkbox mit feature, Welle 23 A42; wie page:OwnCheckbox)
    page:Checkbox("learnAll", nil, { feature = "trainAll" })
    page:Checkbox("upcoming")
    page:Checkbox("where")
    page:Checkbox("petHint")
    page:Checkbox("petTrain")

    -- Stufenaufstieg: alle Meldungen nach dem Aufstieg an einer Stelle (Einstellungs-Prüfung vom 19.11.2026)
    page:Header(L.OPT_HEADER_LEVELUP)
    page:Checkbox("levelHint")
    page:Checkbox("spellNames")     -- „Neu beim Lehrer“ und „… gelernt“ nennen die Zauber
    page:Checkbox("levelDungeons")
    page:Checkbox("levelGear")
    page:Checkbox("levelTalent")

    page:Advanced()
    -- Gesamtreview 18.11.2026: Zurücksetzen mit Rückfrage (T9-3; vorher sofort) und der Status-Knopf von ezCore (T9-2)
    page:ResetButton()
    page:StatusButton(L.OPT_STATUS_TIP)
    page:TourButton(ns.tour)       -- Erklärblasen beim nächsten Öffnen wieder von vorn (Tour.lua)
    page:Companions()              -- ergänzende Addons (heute keine: Pflicht ist nur ezCore)

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
ns.API.OpenSettings = function() return ns.OpenSettings() end
