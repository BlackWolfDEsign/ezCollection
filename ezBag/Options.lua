local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezBag (Seite von ezCore).
-- Aufbau wie auf jeder Seite der Sammlung: Allgemein, Themen, Erweitert.
local page

-- Abschnitte in dieser Reihenfolge; welcher Schalter wohin gehört, steht in ns.TOGGLES (Core.lua).
local SECTIONS = { "groups", "display", "bank", "vendor", "space" }

-- Unterschalter, die ohne ihren Oberschalter nichts tun: grau, solange er aus ist (Querschnitt „Unterschalter
-- ausgrauen“, entschieden am 20.11.2026). Beleg: Gruppe „Neu“ (newItems) entsteht nur in den Taschen-Gruppen
-- (Layout.lua, BuildGroups → GroupsFromSlots(…, true); Bank und „Unterwegs ansehen“ rufen es ohne „Neu“). „Freie
-- Plätze zusammenfassen“ und „Gleiche Gegenstände zusammenfassen“ wirken auch in Bank und Gildenbank – sie bleiben
-- bedienbar; Bank- und Gildenbank-Gruppen sind eigene Oberschalter.
ns.OPTION_PARENT = { newItems = "grouping" }

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: das Fenster „Unterwegs ansehen“ (alle Charaktere, Bank, Gildenbank)
    page:Button(L.OPT_OPEN_WINDOW, L.OPT_OPEN_WINDOW_BUTTON, function() ns.Window.Toggle() end, L.OPT_OPEN_WINDOW_TIP)

    local placed = {}
    for _, section in ipairs(SECTIONS) do
        -- „Händler und Handel“ erklärt im Tooltip das Schloss „nie verkaufen“ (seit der Einstellungs-Prüfung vom
        -- 19.11.2026 immer an, ohne eigenes Kästchen)
        page:Header(L["OPT_SECTION_" .. section], section == "vendor" and L.OPT_SECTION_vendor_TIP or nil)
        for _, entry in ipairs(ns.TOGGLES) do
            if entry[3] == section then
                page:Checkbox(entry[1], nil, { feature = entry[4], parent = ns.OPTION_PARENT[entry[1]] })
                placed[entry[1]] = true
            end
        end
        -- Die Tooltip-Zeilen „Anzahl bei Twinks“ und „Item-Wissen“ schaltet seit BAG-05 ezCore (Seite „ezCollection“,
        -- Abschnitt „Tooltip“) – hier nur der Weg dorthin, damit niemand die alten Schalter vermisst.
        if section == "display" then
            page:Button(L.OPT_TOOLTIP_LINES, L.OPT_OPEN_WINDOW_BUTTON, function() ns.OpenTooltipSettings() end,
                L.OPT_TOOLTIP_LINES_TIP)
        end
    end
    -- Layout-Profile: Menü wie im Sortierknopf der Werkzeugleiste
    page:Header(L.OPT_SECTION_profiles)
    page:Button(L.OPT_PROFILES, L.OPT_PROFILES_BUTTON, function(button) ns.Profiles.OpenMenu(type(button) == "table" and button.GetObjectType and button or UIParent) end, L.OPT_PROFILES_TIP)

    -- Neue Schalter ohne Abschnitt gehen nicht verloren
    for _, entry in ipairs(ns.TOGGLES) do
        if not placed[entry[1]] then page:Checkbox(entry[1], nil, { feature = entry[4] }) end
    end

    page:Advanced()
    -- „Einstellungen zurücksetzen“ wie auf jeder Modulseite (ezCores Knopf mit Rückfrage, design-system 2.10; T9-4,
    -- Gesamtreview 18.11.2026): nur ns.DEFAULTS – Gruppen, Zuweisungen und Profile bleiben.
    page:ResetButton({ tip = L.OPT_RESET_SETTINGS_TIP })
    page:Button(L.OPT_RESET_POSITION, L.OPT_RESET_BUTTON, function()
        ns.Layout.ResetPosition()
        ns.Print(L.CMD_POSITION_RESET)
    end, L.OPT_RESET_POSITION_TIP)
    -- Bank und Gildenbank: sonst nur per Rechtsklick auf ihre Titelleiste (V-044)
    page:Button(L.OPT_RESET_BANK, L.OPT_RESET_BUTTON, function()
        ns.Layout.ResetPanel("BankFrame")
        ns.Layout.ResetPanel("GuildBankFrame")
        ns.Print(L.PANEL_RESET_NEXT)
    end, L.OPT_RESET_BANK_TIP)
    page:Button(L.OPT_RESET_ORDER, L.OPT_RESET_BUTTON, function()
        ns.Groups.ResetOrder()
        ns.Print(L.CMD_ORDER_RESET)
    end, L.OPT_RESET_ORDER_TIP)
    -- Bekannte Charaktere: Die Liste mit „Vergessen“ führt ezCore auf der Seite „ezCollection“ (die Daten liegen dort,
    -- einmal für alle Module). ezBag verweist nur dorthin – der sichtbare Weg zu /eb chars und /eb vergessen (BAG-12).
    page:Button(L.OPT_CHARS, L.OPT_OPEN_WINDOW_BUTTON, function() ns.OpenCharacters() end, L.OPT_CHARS_TIP)
    -- Rundgang mit Erklärblasen (Tour.lua) erneut zeigen; ergänzende Addons (ezBag braucht keine fremden)
    if ns.Tour and ns.Tour.tour then page:TourButton(ns.Tour.tour) end
    -- Stand im Chat zeigen (der sichtbare Weg zu /eb status)
    page:StatusButton()
    page:Companions()

    page:Register()
end

ns.OnReady(function()
    local ok, err = pcall(Register)
    if not ok then ns.Error(err, "Settings") end
end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end

-- Seite „ezCollection“ öffnen: dort steht unter „Bekannte Charaktere“ je Charakter eine Zeile mit „Vergessen“.
-- Geht die Seite nicht auf (Client ohne Einstellungs-Fenster), listet der Chat die Charaktere wie /eb chars.
-- Im Kampf merkt ezCore das Öffnen vor und sagt es selbst – dann keine Liste dazu.
-- → true, wenn die Seite aufging oder nach dem Kampf aufgeht
function ns.OpenCharacters()
    if ezCore.OpenSettings and ezCore.OpenedOrDeferred(ezCore.OpenSettings) then return true end
    ezCore.PrintChars(ns)
    return false
end
