local _, ns = ...
local L = ns.L
local Core = ezCore

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezCraft (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ → Material → Rezepte → Einkaufsliste → Sammelberufe → Post → Entzaubern →
-- „Erweitert“.
local page

-- Tooltip der Einstellung „Materialkosten“: Läuft Auctionator, nennt er es – ezCraft lässt Kosten und Gewinn am Rezept
-- dann weg (CRAFT-02); der Schalter „Kosten auch neben Auctionator“ gibt die Wahl zurück. nil = Standard-Tooltip.
function ns.CostsOptionTip()
    local costOther = ns.Data.CraftCostOther(true)
    return costOther and (L.OPT_costs_TIP .. "\n\n" .. L.OPT_COSTS_OTHER:format(costOther)) or nil
end

local function Register()
    if page then return end
    page = Core.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: ezCraft lebt in Blizzards Berufefenster; hier die Einkaufsliste im Chat und der Hauptschalter.
    page:Button(L.OPT_SHOW_LIST, L.OPT_SHOW_LIST_BUTTON, function() ns.Shopping.Print() end, L.OPT_SHOW_LIST_TIP)
    page:Checkbox("panel")
    page:Checkbox("bookPanel", nil, { parent = "panel" })   -- grau ohne „panel“ (Panel.lua IsOn) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026); Seitenteil auch auf der Seite „Berufe“ (Entscheidung Nr. 22 vom 16.11.2026)
    page:Checkbox("tooltipRecipe", ns.Tooltip.OptionText())   -- Satz über AtlasLoot nur mit ezCores Brücke

    page:Header(L.OPT_HEADER_MATERIAL)
    page:Checkbox("countBank")
    page:Checkbox("countMail")
    page:Checkbox("countGuild")
    page:Checkbox("countAlts")
    page:Checkbox("costs", ns.CostsOptionTip())
    -- beide nur mit „Materialkosten“ (Core.lua Status, Tooltip.lua SumLine) – grau, solange es aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Checkbox("costsBeside", nil, { parent = "costs" })
    page:Checkbox("tooltipCost", nil, { parent = "costs" })    -- „Material ≈ …“ im Tooltip eines hergestellten Gegenstands (AH-32)
    -- Material zum Auffrischen anmelden (AH-39), Farbfilter, Chance auf einen Fertigkeitspunkt und die Tooltip-Zeile
    -- der Einkaufsliste sind seit der Einstellungs-Prüfung vom 19.11.2026 immer an (kein Kästchen)

    page:Header(L.OPT_HEADER_RECIPES)
    -- Läuft SkillUp Forever o. Ä., nennt der Tooltip es (ezCraft zeigt die Skill-Farben dann nicht selbst).
    local other = ns.Data.SkillStagesOther()
    page:Checkbox("skillStages", other and (L.OPT_skillStages_TIP .. "\n\n" .. L.OPT_OTHER_ACTIVE:format(other)) or nil)
    page:Checkbox("missingTab")
    page:Checkbox("recipeWhere")
    page:Checkbox("recipeWaypoint")
    page:Checkbox("chanceNumber")
    page:Checkbox("cooldownTab")

    page:Header(L.OPT_HEADER_SHOPPING)
    -- Woher Fundorte kommen („bei dir“ zuerst; ohne eigene Ernten der Hinweis darauf, SAM-24)
    page:Checkbox("gatherHint", L.OPT_gatherHint_TIP .. "\n\n" .. ns.Data.GatherSourcesText())
    page:Button(L.OPT_CLEAR_LIST, L.OPT_CLEAR_LIST_BUTTON, function()
        ns.Shopping.AskClear()
    end, L.OPT_CLEAR_LIST_TIP)

    page:Header(L.OPT_HEADER_GATHER)   -- Sammelberufe im Berufsbuch (SAM-25)
    page:Checkbox("bookButton")
    page:Checkbox("tooltipSkin")

    page:Header(L.OPT_HEADER_MAIL)
    page:Checkbox("mailTab")
    page:Button(L.OPT_CLEAR_SHIPMENTS, L.OPT_CLEAR_SHIPMENTS_BUTTON, function()
        Core.Confirm(L.SHIP_CLEAR_CONFIRM, function()
            wipe(ns.db.shipments)
            ns.Fire("SHIPMENTS_CHANGED")
        end)
    end, L.OPT_CLEAR_SHIPMENTS_TIP)

    page:Header(L.OPT_HEADER_SALVAGE)
    -- Zeigt ein anderes Addon den Entzauber-Wert schon, nennt der Tooltip es (ezCraft hält sich dann zurück).
    local salvageOther = ns.Salvage.Other()
    page:Checkbox("tooltipSalvage", salvageOther and (L.OPT_tooltipSalvage_TIP .. "\n\n" .. L.OPT_OTHER_ACTIVE:format(salvageOther)) or nil)
    page:Checkbox("salvageTab")
    page:Checkbox("salvageMark")
    page:Button(L.OPT_SALVAGE_RESET, L.OPT_SALVAGE_RESET_BUTTON, function()
        ns.Print(L.SALVAGE_RESET_DONE:format(ns.Salvage.ClearIgnored()))
    end, L.OPT_SALVAGE_RESET_TIP)

    page:Advanced()
    page:ResetButton({ tip = L.OPT_RESET_TIP })   -- Knopf, Rückfrage und Meldung von ezCore
    page:TourButton(ns.Panel.tour, L.OPT_TOUR_TIP)   -- Erklärblasen am Berufefenster wieder von vorn (ezCore)
    page:StatusButton(L.OPT_STATUS_TIP)   -- „Status – Im Chat zeigen“ (Knopf von ezCore, Zeilen aus ns.AddStatusLine)
    page:Companions()   -- Abschnitt „Ergänzende Addons“ mit Knopf „Link kopieren“ (Liste in Core.lua)

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
