local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezLoot (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ → Themen → „Erweitert“.
local page

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: Beute-Verlauf (Fenster aus Blizzards Vorlagen) und Blizzards Würfelergebnisse
    page:Button(L.OPT_HISTORY, L.OPT_HISTORY_BUTTON, function() ns.LootHistory.Show() end, L.OPT_HISTORY_TIP)
    page:Button(L.OPT_ROLLS, L.OPT_ROLLS_BUTTON, function() ns.OpenRollHistory() end, L.OPT_ROLLS_TIP)
    -- („Beute-Verlauf an die Würfelergebnisse andocken“ entfiel mit der Einstellungs-Prüfung vom 19.11.2026: er dockt
    -- immer an, Wegziehen löst ihn)
    page:Button(L.POSSIBLE_TITLE, L.OPT_POSSIBLE_BUTTON, function() ns.LootHistory.ShowPossible() end, L.OPT_POSSIBLE_TIP)

    -- Tooltip (Einstellungs-Prüfung vom 19.11.2026, Abschnitt 3: sechs Tooltip-Schalter standen unter „Allgemein“).
    -- „Wert je Tötung“ und „Hinweis bei nie geplünderten Gegnern“ wirken nur mit „Beute im Tooltip von Gegnern“:
    -- eingerückt darunter
    page:Header(L.OPT_HEADER_TOOLTIP, L.OPT_HEADER_TOOLTIP_TIP)
    -- eingerückt und grau, solange der Oberschalter aus ist (ezCores opts.parent) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Checkbox("npcLoot")
    page:Checkbox("npcWorth", nil, { parent = "npcLoot" })     -- „Wert je Tötung“ unter der eigenen Beute (V2, Welle 24)
    page:Checkbox("npcLootHint", nil, { parent = "npcLoot" })  -- „noch nicht geplündert“ (ab Werk an, Entscheidung 13.11.2026)
    page:Checkbox("npcSkin")        -- „Kürschnern: ab …“ im Gegner-Tooltip (Welle 27, F4 b; Wert aus ezCore)
    page:Checkbox("itemLoot")       -- neben „Beute im Tooltip von Gegnern“: eigener Schalter für Gegenstände (Frage 7)
    page:Checkbox("itemOrigin")     -- „Herkunft laut …“ an Nicht-Rohstoffen (Welle 23, Entscheidung Nr. 24)

    -- Schneller plündern: Blizzards „Automatisch plündern“ als Kästchen, das den Stand des Spiels zeigt (vorher ein
    -- Knopf „An/Aus“ ohne sichtbaren Stand; Einstellungs-Prüfung vom 19.11.2026, Abschnitt 4 nach Empfehlung).
    -- „Schneller plündern“ eingerückt darunter, aber nicht grau: auch ohne „Automatisch plündern“ plündert die Taste
    -- (Standard: Umschalt) automatisch, und dann greift es (FastLoot.Wanted; code-reviewer 20.11.2026)
    page:Header(L.OPT_HEADER_FAST)
    if page.ProxyCheckbox then
        page:ProxyCheckbox("autoLoot", ns.AutoLootOn, function(on)
            if ns.AutoLootOn() ~= on then ns.ToggleAutoLoot() end
        -- fester Standard „aus“ wie Blizzards CVar autoLootDefault: ohne ihn setzte Blizzards Knopf „Standard“ den Stand
        -- beim Einloggen zurück (Nachlauf des code-reviewers vom 20.11.2026)
        end, { label = L.OPT_AUTOLOOT, tooltip = L.OPT_AUTOLOOT_TIP, default = ns.AUTOLOOT_DEFAULT })
    end
    page:Checkbox("fastLoot", nil, { parent = "autoLoot", enabledWhen = function() return true end })

    page:Header(L.OPT_HEADER_FRAMES)
    page:Checkbox("itemLevel")
    page:Checkbox("bind")
    page:Checkbox("upgrade")
    -- Spiegel von ezQuests „Quest-Gegenstände im Beutefenster funkeln“ (ein Wert, in ezQuest; Einstellungs-Prüfung vom
    -- 19.11.2026, Abschnitt 3) – nur, solange ezQuest ihn anbietet
    if page.ProxyCheckbox then
        local function Quest() return ezCore.API("ezQuest") end
        page:ProxyCheckbox("lootShine", function()
            local api = Quest()
            return type(api) == "table" and type(api.ShineEnabled) == "function" and api.ShineEnabled("loot") == true
        end, function(on)
            local api = Quest()
            if type(api) == "table" and type(api.SetShine) == "function" then api.SetShine("loot", on) end
        end, { shown = function()
            local api = Quest()
            return type(api) == "table" and type(api.SetShine) == "function"
        end })
    end

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP)     -- „Status – Im Chat zeigen“ (ezCore), ruft ns.PrintStatus
    page:Button(L.OPT_HISTORY_POS, L.OPT_RESET_BUTTON, function()
        ns.LootHistory.ResetPosition()
        ns.Print(L.HISTORY_POS_RESET)
    end, L.OPT_HISTORY_POS_TIP)
    if ns.Tour and page.TourButton then page:TourButton(ns.Tour) end
    page:ResetButton()
    if page.Companions then page:Companions() end

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
