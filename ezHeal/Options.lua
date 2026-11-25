local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezHeal (Seite von ezCore):
-- Allgemein (Blizzards Fenster „Klick-Zauber“ öffnen, weitere Einstiege an Blizzards Fenstern, am Zauberbuch
-- andocken) → Klick-Belegung
-- (Vorlage, Tasten wählen, Vorschau im Chat, Übernehmen, Zurück, Belegung vor dem ersten Übernehmen, Menü und Ziel
-- zurückholen, Blizzards Selbstwirken) → Makros
-- (Heil-Makros für die Klasse anlegen, Vorschau im Chat, eigene Makros entfernen) → Profile
-- (speichern, laden/teilen/löschen, einfügen) → Anzeige (eigene HoTs am Rahmen, Klick-Legende im Rahmen-Tooltip,
-- Blizzards Raidrahmen-Optionen) →
-- Erweitert (Status, Erklärung erneut zeigen, Einstellungen zurücksetzen, ergänzende Addons).
local page

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    page:Button(L.OPT_OPEN, L.OPT_OPEN_BUTTON, function() ns.OpenBlizzard() end, L.OPT_OPEN_TIP)
    -- weitere Einstiege zu Blizzards Fenster „Klick-Zauber“ (Entries.lua, HL-07), je abschaltbar
    page:Checkbox("entryRaid")
    page:Checkbox("entryGroup")
    page:Checkbox("entrySpellbook")
    page:Checkbox("entryMacro")
    page:Checkbox("dockSpellbook", nil, { feature = "moveFrames" })   -- Blizzards Fenster rechts am Zauberbuch (Dock.lua)
    -- Zauberbuch und Klick-Zauber zusammen schließen (Dock.lua); ausgeblendet, solange ezCore Klick-Zauber nicht aus
    -- Addon-Code öffnen darf (Entscheidung des Nutzers vom 23.11.2026 „Ausblenden (Empfohlen)“)
    page:Checkbox("pairSpellbook", nil, { shown = function() return ns.PairSpellbookShown() end })

    page:Header(L.OPT_HEADER_BINDINGS)
    page:Dropdown("template", {
        { "heal", L.KIND_heal },
        { "buffs", L.KIND_buffs },
        { "all", L.KIND_all },
    })
    page:Button(L.OPT_KEYS, L.OPT_KEYS_BUTTON, function() ns.Preview.Open() end, L.OPT_KEYS_TIP)
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, function() ns.PrintPreview() end, L.OPT_PREVIEW_TIP)
    page:Button(L.OPT_APPLY, L.OPT_APPLY_BUTTON, function() ns.AskApply() end, L.OPT_APPLY_TIP)
    page:Button(L.OPT_RESTORE, L.OPT_RESTORE_BUTTON, function() ns.AskRestore() end, L.OPT_RESTORE_TIP)
    page:Button(L.OPT_RESTORE_FIRST, L.OPT_RESTORE_FIRST_BUTTON, function() ns.AskRestore("first") end,
        L.OPT_RESTORE_FIRST_TIP)
    -- Rechtsklick öffnet kein Menü, Linksklick wählt kein Ziel (MenuClick.lua, Spieltest 24.11.2026)
    page:Button(L.OPT_MENUCLICK, L.OPT_MENUCLICK_BUTTON, function() ns.MenuClick.Ask() end, L.OPT_MENUCLICK_TIP)
    -- Blizzards „Selbstwirken“ (Fehler vom 23.11.2026): Taste und „Automatisch“ lenken Klicks auf dich um (Core.lua)
    page:Checkbox("noAutoSelfCast")   -- „Selbstwirken: Automatisch“ einmal aus, aus = alter Wert zurück (Core.lua)
    page:Button(L.OPT_SELFCAST, L.OPT_SELFCAST_BUTTON, function() ns.OpenSelfCastOptions() end, L.OPT_SELFCAST_TIP)

    -- Heil-Makros je Klasse in Blizzards Makrofenster (Macros.lua)
    page:Header(L.OPT_HEADER_MACROS)
    page:Button(L.OPT_MACROS, L.OPT_MACROS_BUTTON, function() ns.AskMacros() end, L.OPT_MACROS_TIP)
    page:Button(L.OPT_MACROS_PREVIEW, L.OPT_MACROS_PREVIEW_BUTTON, function() ns.PrintMacros() end, L.OPT_MACROS_PREVIEW_TIP)
    page:Button(L.OPT_MACROS_REMOVE, L.OPT_MACROS_REMOVE_BUTTON, function() ns.AskRemoveMacros() end, L.OPT_MACROS_REMOVE_TIP)

    -- benannte Profile der Klick-Belegung (Profiles.lua, HL-08)
    page:Header(L.OPT_HEADER_PROFILES)
    page:Button(L.OPT_PROFILE_SAVE, L.OPT_PROFILE_SAVE_BUTTON, function() ns.Profiles.AskSave() end, L.OPT_PROFILE_SAVE_TIP)
    page:Button(L.OPT_PROFILES, L.OPT_PROFILES_BUTTON, function() ns.Profiles.OpenMenu() end, L.OPT_PROFILES_TIP)
    page:Button(L.OPT_PROFILE_IMPORT, L.OPT_PROFILE_IMPORT_BUTTON, function() ns.Profiles.AskImport() end,
        L.OPT_PROFILE_IMPORT_TIP)

    page:Header(L.OPT_HEADER_DISPLAY)
    page:Checkbox("hots")
    -- Klick-Legende im Tooltip der Rahmen (Legend.lua, HL-01); der Tooltip nennt ein Addon, das sie schon zeigt
    page:Checkbox("clickLegend", ns.Legend and ns.Legend.OptionTip() or nil)
    -- was Blizzards Rahmen schon zeigen, steht in Blizzards Optionen der Raidrahmen (HL-09, kein Nachbau)
    page:Button(L.OPT_RAIDFRAMES, L.OPT_RAIDFRAMES_BUTTON, function() ns.OpenRaidFrameOptions() end, L.OPT_RAIDFRAMES_TIP)

    page:Advanced()
    page:StatusButton()
    page:TourButton(ns.Tour.tour, L.OPT_TOUR_TIP)   -- Erklärblasen in Blizzards Fenster „Klick-Zauber“ wieder von vorn
    page:ResetButton()   -- „Einstellungen zurücksetzen“ (ezCore); die Klick-Belegung selbst bleibt
    -- Ergänzende Addons: keines (Clique, HealBot, VuhDo, Grid2 und Cell überschneiden sich – Hinweis nach Leitlinie 9
    -- in Core.lua); der Abschnitt bleibt, damit ein später angemeldetes Addon dort erscheint.
    page:Companions()

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
