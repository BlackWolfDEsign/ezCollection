local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezGear (Seite von ezCore):
-- „Allgemein“ (Gewichtung, Pawn-Skala) → Pfeil (auch der rote) → Tooltip → Charakterfenster → Ausrüstungs-Check der Gruppe → Umziehen
-- → Profile → „Erweitert“.
local page

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Erklärung mit dem Addon, das gerade übernimmt (ns.OptionTip; Leitlinie 9). Als Funktion übergeben: Blizzards
    -- Settings.InitTooltip ruft sie beim Zeigen (Forever-Quelle Blizzard_Settings_Shared/Blizzard_Settings.lua, wie in
    -- ezBuff und ezBars) – so stimmt der Text auch, wenn Forever++ erst nach READY antwortet oder jemand in Pawn bzw.
    -- Forever++ später umschaltet (OTHER_ADDONS_CHANGED).
    local function Check(key) return page:Checkbox(key, function() return ns.OptionTip(key) end) end
    local function Percent(value) return ezCore.Percent(value) end
    local function Seconds(value)
        if value < 60 then return ezCore.Seconds(value) end
        local minutes, seconds = math.floor(value / 60), value % 60
        if seconds == 0 then return ezCore.Minutes(minutes) end
        return ezCore.Duration(value)    -- „1 Min. 30 Sek.“ aus ezCore (Frage 9; vorher „1:30 Min.“)
    end

    -- Allgemein: die Gewichtung bestimmt alles andere
    page:Button(L.OPT_WEIGHTS, L.OPT_WEIGHTS_BUTTON, function() ns.OpenWeightMenu(UIParent) end, L.OPT_WEIGHTS_TIP)
    page:Button(L.OPT_PAWN, L.OPT_PAWN_BUTTON, function() ns.AskPawnScale() end, L.OPT_PAWN_TIP)

    -- Einstellungs-Prüfung 19.11.2026: roter Pfeil unter „Pfeil“ (Abschnitt 3); fest sind die Vergleichszeile samt
    -- „schlechter“ (Nr. 41, 42) und die Haltbarkeit an den Plätzen (Nr. 43); die Meldung bei ezPanel wählt man nur
    -- noch in ezPanels Meldungsquellen (Nr. 77).
    page:Header(L.OPT_HEADER_ARROWS)
    Check("bagArrows")
    Check("downArrows")
    Check("questArrows")
    Check("questCoin")
    page:Slider("minPercent", 0, 20, 1, Percent)

    page:Header(L.OPT_HEADER_TOOLTIP, L.OPT_HEADER_TOOLTIP_TIP)
    Check("recipeCompare")

    page:Header(L.OPT_HEADER_CHARACTER)
    Check("charLevels")
    Check("charEnchant")
    Check("inspectLevels")
    Check("setsButton")
    Check("chatButton")
    page:Button(L.OPT_SETS, L.OPT_SETS_BUTTON, function() ns.OpenSetsMenu(UIParent) end, L.OPT_SETS_TIP)

    page:Header(L.OPT_HEADER_GROUP)
    Check("groupCheck")

    -- Einstellungs-Prüfung 19.11.2026, Nr. 78/79 (Querschnitt „Unterschalter ausgrauen“): „Beim Reiten/Angeln
    -- umziehen“ grau, solange es kein Set für den Anlass gibt (Swap.SetName); der Tooltip sagt dann, was fehlt.
    -- „Wie lange nach dem letzten Auswerfen“ ist grau, solange „Beim Angeln umziehen“ aus ist.
    local function SwapCheck(key, kind)
        -- läuft in Blizzards Einstellungsliste: ein Fehler (fehlende Sets, C_EquipmentSet) landet in der Fehlerliste
        -- und lässt die Zeile bedienbar (code-reviewer 20.11.2026)
        local function HasSet()
            if not (ns.Swap and ns.Swap.SetName) then return true end
            local ok, name = ezCore.Try("ezGear", "Options SwapCheck", ns.Swap.SetName, kind)   -- mit Stapel
            if not ok then return true end
            return name ~= nil
        end
        local _, row = page:Checkbox(key, function()
            local tip = ns.OptionTip(key)
            if HasSet() then return tip end
            return tip .. "\n\n" .. L["SWAP_NEEDS_SET_" .. kind]
        end)
        if type(row) == "table" and type(row.AddModifyPredicate) == "function" then
            pcall(row.AddModifyPredicate, row, HasSet)
        end
    end
    page:Header(L.OPT_HEADER_SWAP)
    SwapCheck("swapMount", "mount")
    SwapCheck("swapFishing", "fish")
    page:Slider("fishIdle", 30, 600, 30, Seconds, nil, { parent = "swapFishing" })
    page:Button(L.OPT_SWAP_FISH, L.OPT_SWAP_FISH_BUTTON, function() ns.ToggleFishing() end, L.OPT_SWAP_FISH_TIP)

    -- Profile (Profiles.lua): Auswahl, „für die Klasse“, „je Spezialisierung“, Neu/Export/Import/Löschen baut ezCore
    -- (page:Profiles, eine Umsetzung für alle Module; Welle 23 – vorher ein Knopf „Profil – Wählen“ mit Menü unter
    -- „Allgemein“). Das Menü bleibt im Menü „Sets“ am Charakterfenster und hinter /ezg profil.
    if ns.Profiles and ns.Profiles.P then
        ns.profileSection = page:Profiles(ns.Profiles.P, { texts = L, header = L.OPT_HEADER_PROFILES,
            headerTip = L.OPT_HEADER_PROFILES_TIP })
    end

    page:Advanced()
    page:Button(L.OPT_COMPARE, L.OPT_COMPARE_BUTTON, function() ns.PrintCompare() end, L.OPT_COMPARE_TIP)
    page:StatusButton(L.OPT_STATUS_TIP)
    if ns.Tour then page:TourButton(ns.Tour) end
    page:ResetButton({ tip = L.OPT_RESET_TIP })
    page:Companions()

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

-- Jede Einstellung, die die Bewertung betrifft, zeichnet Pfeile und Tooltip neu.
ns.OnSettingChanged(function(key)
    if key == "minPercent" or key == "downArrows" then ns.Changed() end
end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
