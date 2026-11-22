local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezQuest (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ → Themen → „Erweitert“.
local page

-- Blizzards Questlog auf- oder zuklappen (ezCore.TogglePanel kennt den Weg je Client). Im Kampf bleibt es zu,
-- ezCore zeigt dann den Hinweis „Im Kampf lässt sich dieses Fenster nicht öffnen …“. Rückgabe: true oder
-- false und der Grund ("combat", "missing", "error").
function ns.OpenQuestLog()
    return ezCore.TogglePanel("questlog")
end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: Blizzards Questlog (das Fenster, das ezQuest erweitert)
    page:Button(L.OPT_OPEN, L.OPT_OPEN_BUTTON, ns.OpenQuestLog, L.OPT_OPEN_TIP)

    page:Header(L.OPT_HEADER_LEVEL)
    page:Checkbox("levelInDialogs")
    page:Checkbox("sortTracker")
    page:Checkbox("sortSuperTrack", nil, { parent = "sortTracker" })     -- Zielverfolgung nach dem Sortieren zurücksetzen (ab Werk aus, Welle 29)
    -- ein Klick: sortiert auch, wenn die Zielverfolgung einer betroffenen Quest folgt, und setzt sie zurück
    -- (im Kampf: gemerkt, gleich danach sortiert; Tracker.SortNow)
    page:Button(L.OPT_SORT_NOW, L.OPT_SORT_NOW_BUTTON, function() ns.Tracker.SortNow() end, L.OPT_SORT_NOW_TIP)

    page:Header(L.OPT_HEADER_AUTO)
    page:Checkbox("autoQuest")
    -- Unterschalter grau, solange „Automatisch annehmen“ aus ist (Auto.On; Querschnitt „Unterschalter ausgrauen“)
    page:Checkbox("autoTrivial", nil, { parent = "autoQuest" })
    page:Checkbox("autoRepeatable", nil, { parent = "autoQuest" })
    page:Checkbox("autoReward", nil, { parent = "autoQuest" })

    -- Quests teilen (Share.lua): automatisch ab Werk aus (sendet ohne Klick), dazu der Knopf für ein Teilen per Klick
    -- (dieselben zwei Einträge stehen im Zahnrad-Menü am Questlog)
    page:Header(L.OPT_HEADER_SHARE)
    page:Checkbox("autoShare")
    page:Button(L.OPT_SHARE_NOW, L.OPT_SHARE_NOW_BUTTON, function() ns.Share.Now() end, L.SHARE_MENU_NOW_TIP)

    page:Header(L.OPT_HEADER_TINT)
    page:Checkbox("tintNew")

    -- (Abschnitt „Quest-Gegenstände“ mit „Quest-Gegenstände erkennen“ entfiel mit Nr. 45 der Einstellungs-Prüfung vom
    -- 19.11.2026: die Erkennung läuft immer)

    -- Funkeln und Hervorheben: Symbole in der Welt (Blizzards CVars), Funkeln in Tasche und Beutefenster, Fortschritt
    -- im Tooltip; dazu die Wege zu Blizzards eigenen Einstellungen (Leitlinie 1)
    page:Header(L.OPT_HEADER_SHINE, L.OPT_HEADER_SHINE_TIP)
    -- Quest-Objekte funkeln (Blizzards Umriss-Modus und Funkeln, Sparkle.lua): grau, wenn der Client die Einstellungen
    -- nicht kennt, ein Addon sie nicht setzen darf oder Forever Loot Sparkles es übernimmt (Grund im Tooltip)
    local sparkleTip
    if ns.Sparkle and #ns.Sparkle.Hints() > 0 then
        sparkleTip = L.OPT_worldSparkle_TIP .. "\n\n" .. table.concat(ns.Sparkle.Hints(), " ")
    end
    local _, sparkleRow = page:Checkbox("worldSparkle", sparkleTip)
    if sparkleRow and sparkleRow.AddModifyPredicate and ns.Sparkle then
        sparkleRow:AddModifyPredicate(function() return ns.Sparkle.Supported() and not ns.Sparkle.Other() end)
    end
    local worldTip
    if ns.World and (not ns.World.Supported() or ns.World.Other()) then
        worldTip = L.OPT_worldIcons_TIP .. "\n\n" .. table.concat(ns.World.Hints(), " ")
    end
    local _, worldRow = page:Checkbox("worldIcons", worldTip)
    if worldRow and worldRow.AddModifyPredicate and ns.World then
        -- grau, wenn der Client keine der CVars kennt, ein Addon sie nicht setzen darf oder eine alte Fassung von
        -- Forever Loot Sparkles sie selbst setzt (Grund im Tooltip)
        worldRow:AddModifyPredicate(function() return ns.World.Supported() and not ns.World.Other() end)
    end
    page:Button(L.OPT_WORLD_CONTROLS, L.OPT_OPEN_BUTTON, function() ns.World.OpenBlizzard("controls") end,
        L.OPT_WORLD_CONTROLS_TIP)
    page:Button(L.OPT_WORLD_ICONS, L.OPT_OPEN_BUTTON, function() ns.World.OpenBlizzard("accessibility") end,
        L.OPT_WORLD_ICONS_TIP)
    -- Funkeln in Tasche und Beutefenster wirkt nur mit ezBag bzw. ezLoot: die Zeile steht nur, wenn das Modul läuft;
    -- ezLoot zeigt denselben Schalter als Spiegel unter „Plündern- und Würfelfenster“ (Einstellungs-Prüfung vom
    -- 19.11.2026, Abschnitt 3; Shine.SetEnabled)
    page:Checkbox("bagShine", nil, { shown = function() return ezCore.IsLoaded("ezBag") end })
    page:Checkbox("lootShine", nil, { shown = function() return ezCore.IsLoaded("ezLoot") end })
    page:Checkbox("progressTip")

    page:Header(L.OPT_HEADER_DUNGEON)
    page:Checkbox("dungeonQuests")
    page:Checkbox("entranceButton")

    -- Quest-ID: Zeile im Tooltip des Questlogs und die Abfrage „Quest mit ID erledigt?“ (auch im Zahnrad-Menü am
    -- Questlog, QuestId.lua)
    page:Header(L.OPT_HEADER_ID)
    page:Checkbox("questIdTip")
    page:Button(L.OPT_ID_CHECK, L.OPT_ID_CHECK_BUTTON, function() ns.QuestId.Ask() end, L.OPT_ID_CHECK_TIP)

    -- Leveling-Route (LevelRoute.lua): Haupt-Schalter, Knopf, Händler, Kräuter und Erze (nur mit Beruf), Abstecher,
    -- schwere Quests, Linie und Verfolgung (ab Werk aus) – dieselben Haken stehen im Zahnrad-Menü am Questlog. Den Pfeil
    -- beim Weiterrücken regelt seit Nr. 94 der Einstellungs-Prüfung vom 19.11.2026 allein ezMaps „Zielverfolgung
    -- einschalten“
    page:Header(L.OPT_HEADER_ROUTE, L.OPT_HEADER_ROUTE_TIP)
    page:Checkbox("levelRoute")
    -- alles darunter grau, solange „Leveling-Route“ aus ist (LR.Compute rechnet dann nicht; Querschnitt „Unterschalter
    -- ausgrauen“)
    local function route() return { parent = "levelRoute" } end
    page:Checkbox("routeAuto", nil, route())          -- ohne Klick rechnen (Wunsch des Nutzers vom 18.11.2026, ab Werk an)
    page:Button(L.OPT_ROUTE_NOW, L.OPT_ROUTE_NOW_BUTTON, function() ns.LevelRoute.Command("") end, L.OPT_ROUTE_NOW_TIP, route())
    page:Checkbox("routeVendor", nil, route())
    -- „Händler einplanen bei höchstens … freien Plätzen“ unter „Händler am Weg einplanen“ (Abschnitt 3): eingerückt und
    -- grau, solange der Händler-Halt aus ist
    page:Slider("routeVendorFree", 0, 20, 1, nil, nil, { parent = "routeVendor" })
    page:Checkbox("routeGather", nil, { parent = "levelRoute", shown = function() return ns.LevelRoute.HasGather() end })
    page:Slider("routeDetour", 0, 200, 10, function(value) return L.GATHER_YARDS:format(value) end, nil, route())
    page:Checkbox("routeHard", nil, route())
    page:Checkbox("routeLine", nil, route())
    page:Checkbox("routeMiniArrow", nil, route())
    -- Größe des Pfeils (Spieltest 20.11.2026): eingerückt und grau, solange der Pfeil aus ist
    page:Slider("routeMiniArrowSize", 12, 48, 2, ezCore.Pixels, nil, { parent = "routeMiniArrow",
        enabledWhen = function() return ns.Enabled("levelRoute") and ns.Enabled("routeMiniArrow") end })
    page:Checkbox("routeWatch", nil, route())

    -- Erfahrungsleiste (XPPreview.lua): Quest-Erfahrung als Vorschau auf Blizzards Leiste (Feature I1, 18.11.2026)
    page:Header(L.OPT_HEADER_XP, L.OPT_HEADER_XP_TIP)
    page:Checkbox("xpPreview")
    page:Checkbox("xpTickFollow", nil, { parent = "xpPreview", enabledWhen = function() return ns.Enabled("xpPreview") end })

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP)   -- „Status – Im Chat zeigen“ (ezCore, T9-2)
    page:TourButton(ns.Tour and ns.Tour.tour)   -- „Erklärung erneut zeigen“ (Erklärblasen, Tour.lua)
    page:ResetButton()   -- „Einstellungen zurücksetzen“ mit Rückfrage (ezCore)
    page:Companions()    -- „Ergänzende Addons“ mit Link zum Kopieren (Core.AddCompanion in Core.lua)

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
