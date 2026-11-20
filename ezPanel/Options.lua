local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezPanel (Unterseiten „Bausteine“ und „Meldungen“).
-- Die Seiten baut ezCore (eine Umsetzung für alle Module).
local page
local blockSettings = {}
local alertSettings = {}   -- [Quellen-ID] = Setting der Unterseite „Meldungen“
local alertState = {}      -- [Quellen-ID] = gezeigt? – Spiegel für die Häkchen; gespeichert ist nur die Abwahl (Alerts.lua)
local syncing = false

-- Ergänzende Addons (Abschlussrunde; „Erweitert“ und README). Pflicht ist nur ezCore. Alle drei bringen
-- eine LibDataBroker-Anzeige mit (Baustein auf der Leiste) und einen Minikarten-Knopf (Baustein
-- „Minikarten-Knöpfe“). Name, Ordner und CurseForge-Link stehen je einmal in ezCore (Core.OTHER_ADDONS, V-138).
ezCore.AddCompanion("ezPanel", { key = "Atlas", role = "optional", why = L.COMPANION_WHY_ATLAS })
ezCore.AddCompanion("ezPanel", { key = "Questie", role = "optional", why = L.COMPANION_WHY_QUESTIE })
ezCore.AddCompanion("ezPanel", { key = "RareScanner", role = "optional", why = L.COMPANION_WHY_RARESCANNER })

local function Percent(v) return ezCore.Percent(math.floor(v * 100 + 0.5)) end
local function Whole(v) return tostring(math.floor(v + 0.5)) end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    page:Header(L.OPT_HEADER_BARS, L.OPT_HEADER_BARS_TIP)
    -- „Automatisch ausblenden“, „Im Kampf ausblenden“ und „Platz oben freihalten“ wirken nur mit „Leiste anzeigen“
    -- (Bar.lua: UpdateBarVisibility, ReservedHeight) – grau, solange sie aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    local UNDER_BAR = { autoHideTop = true, hideInCombat = true, reserveTop = true }
    for _, key in ipairs({ "topBar", "autoHideTop", "hideInCombat", "reserveTop", "viewport", "locked", "tooltipsInCombat" }) do
        page:Checkbox(key, nil, UNDER_BAR[key] and { parent = "topBar" } or nil)
    end

    page:Header(L.OPT_HEADER_LOOK)
    local skins = {}
    for _, id in ipairs(ns.SKIN_ORDER) do skins[#skins + 1] = { id, L["SKIN_" .. id] } end
    page:Dropdown("skin", skins)
    page:Slider("alpha", 0, 1, 0.05, Percent)
    page:Slider("fontSize", 8, 18, 1, Whole)
    page:Slider("spacing", 4, 40, 1, Whole)
    page:Dropdown("moneyStyle", { { "coins", L.MONEY_coins }, { "gold", L.MONEY_gold }, { "text", L.MONEY_text } })

    -- Profile: Auswahl gilt für diesen Charakter (bzw. diese Spezialisierung), nicht für das Profil selbst.
    -- Den Abschnitt baut ezCore (page:Profiles, eine Umsetzung für alle Module; vorher hier selbst gebaut): Auswahl,
    -- „je Spezialisierung“, Neu, Exportieren, Importieren, Löschen – dieselben Funktionen wie das Menü. Die Texte
    -- bleiben ezPanels (sie sprechen vom Inhalt der Leiste); ein Kästchen „für die Klasse“ gibt es hier nicht.
    -- Nach jedem Wechsel (Menü, Spezialisierung) zieht ezCore die Steuerelemente nach.
    ns.profileSection = page:Profiles(ns.Profiles.P, { header = L.OPT_HEADER_PROFILES, headerTip = L.OPT_HEADER_PROFILES_TIP,
        texts = L, class = false })

    page:Advanced()
    -- Prüfung der Einstellungen vom 19.11.2026: „Ebene“ (technischer Wert, jetzt „Leiste über/unter anderen Fenstern“)
    -- und „Skalierung“ (die Schriftgröße vergrößert Höhe, Symbole und Abstände schon) stehen unter „Erweitert“
    page:Slider("scale", 0.5, 2, 0.05, Percent)
    page:Dropdown("strata", {
        { "BACKGROUND", L.STRATA_BACKGROUND }, { "LOW", L.STRATA_LOW },
        { "MEDIUM", L.STRATA_MEDIUM }, { "HIGH", L.STRATA_HIGH },
    })
    -- Rückfrage und Zurücksetzen baut ezCore (wie in den anderen Modulen); Anordnung und Bausteine bleiben.
    page:ResetButton({ ask = L.RESET_SETTINGS_CONFIRM, tip = L.OPT_RESET_SETTINGS_TIP })
    page:Button(L.OPT_RESET_LAYOUT, L.OPT_RESET_BUTTON, function()
        ns.ResetLayout()
        ns.Print(L.CMD_RESET)
    end, L.OPT_RESET_LAYOUT_TIP)
    page:Button(L.OPT_IMPORT_TITAN, L.OPT_IMPORT_BUTTON, function() ns.ImportTitan(true) end, L.OPT_IMPORT_TITAN_TIP)
    -- Erklärblasen erneut zeigen (Tour.lua); sie beginnen, sobald das Einstellungsfenster zu ist.
    if ns.tour then page:TourButton(ns.tour, L.OPT_TOUR_TIP) end
    -- Stand des Moduls in den Chat (derselbe Text wie /ep status): Leiste, Bausteine, Platz oben, Profil.
    page:StatusButton()
    page:Companions()

    -- Unterseite: Bausteine an/aus
    local sub = page:Sub(L.OPT_BLOCKS)
    if sub then
        sub:Header(L.OPT_BLOCKS, L.OPT_BLOCKS_TIP)
        -- Alles, was sonst nur der Rechtsklick auf einen Baustein zeigt (Leitlinie 3, V-076): ein Menü mit
        -- einem Untermenü je Baustein – auch für Bausteine, die gerade nicht auf der Leiste stehen.
        sub:Button(L.OPT_BLOCK_OPTIONS, L.OPT_BLOCK_OPTIONS_BUTTON, function() ns.OpenAllBlockMenus() end,
            L.OPT_BLOCK_OPTIONS_TIP)
        -- „Alle auswählen / Alle abwählen“ über den Häkchen der Bausteine (Design-System 2.11, Welle 22): mit den
        -- Setting-Objekten (jeder Baustein heißt „enabled“ in seiner eigenen Tabelle, als Schlüssel fände
        -- page:AllToggle sie nicht). Die Liste entsteht erst beim Klick – mit später angemeldeten Bausteinen.
        if sub.AllToggle then
            sub:AllToggle(function()
                local list = {}
                for _, def in ipairs(ns.blockList) do
                    if blockSettings[def.id] then list[#list + 1] = blockSettings[def.id] end
                end
                return list
            end, { label = L.OPT_BLOCKS })
        end
        -- Häkchen eines Bausteins; auch für Bausteine, die ein anderes Modul später anmeldet (API.lua).
        function ns.AddBlockSetting(def)
            local id = def.id
            if def.broker or not def.cfg or blockSettings[id] then return end
            sub:Try(function()
                local setting = sub:Setting("enabled", Settings.VarType.Boolean, def.cfg, def.name,
                    def.defaults.enabled == true, "ezPanel_block_" .. id)
                setting:SetValueChangedCallback(function(_, value)
                    if syncing then return end
                    ns.SetBlockEnabled(id, value)
                end)
                local tip = type(def.tip) == "string" and def.tip or nil
                if not tip and not def.external then tip = L["BLOCK_TIP_" .. id] end
                Settings.CreateCheckbox(sub.category, setting, tip or L.BLOCK_TIP_EXTERNAL:format(tostring(
                    type(def.external) == "string" and def.external or def.name)))
                blockSettings[id] = setting
            end)
        end
        for _, def in ipairs(ns.blockList) do ns.AddBlockSetting(def) end
    end

    -- Unterseite: Quellen des Bausteins „Meldungen“ (Frage 17, 14.11.2026: jede Quelle einzeln abwählbar; Leitlinie 3:
    -- nicht nur im Rechtsklick-Menü). Ein Häkchen je Quelle mit Tooltip, was sie meldet – auch für Quellen, die ein
    -- anderes Modul später anmeldet (API.lua); eine wieder abgemeldete Quelle verschwindet.
    local alerts = page:Sub(L.ALERTS_NAME)
    if alerts then
        alerts:Header(L.OPT_ALERT_SOURCES, L.OPT_ALERT_SOURCES_TIP)
        -- „Alle auswählen / Alle abwählen“ über den Quellen (Design-System 2.11, Welle 22), nur sichtbare Quellen
        if alerts.AllToggle then
            alerts:AllToggle(function()
                local list = {}
                for _, source in ipairs(ns.AlertSources()) do
                    local setting = alertSettings[source.id]
                    if setting and ns.AlertSourceKnown(source.id) then list[#list + 1] = setting end
                end
                return list
            end, { label = L.OPT_ALERT_SOURCES })
        end
        function ns.AddAlertSetting(source)
            local id = source.id
            if type(id) ~= "string" or alertSettings[id] or not (ns.blocks.alerts and ns.blocks.alerts.cfg) then return end
            alerts:Try(function()
                alertState[id] = ns.AlertSourceEnabled(id)
                local setting = alerts:Setting(id, Settings.VarType.Boolean, alertState, tostring(source.name or id), true,
                    "ezPanel_alert_" .. id)
                setting:SetValueChangedCallback(function(_, value)
                    if syncing then return end
                    ns.SetAlertSourceEnabled(id, value)
                end)
                local init = Settings.CreateCheckbox(alerts.category, setting, ns.AlertSourceTip(source))
                if type(init) == "table" and init.AddShownPredicate then
                    init:AddShownPredicate(function() return ns.AlertSourceKnown(id) end)
                end
                alertSettings[id] = setting
            end)
        end
        for _, source in ipairs(ns.AlertSources()) do ns.AddAlertSetting(source) end
    end

    page:Register()
end

-- Baustein über Menü oder Befehl umgeschaltet: Häkchen in den Einstellungen nachziehen.
function ns.RefreshBlockSetting(id)
    local setting = blockSettings[id]
    if not setting or syncing then return end
    syncing = true
    pcall(setting.SetValue, setting, ns.BlockEnabled(id))
    syncing = false
end

-- Quelle der Meldungen über das Menü „Quellen“ umgeschaltet: Häkchen der Unterseite „Meldungen“ nachziehen.
function ns.RefreshAlertSetting(id)
    local setting = alertSettings[id]
    if not setting or syncing then return end
    syncing = true
    pcall(setting.SetValue, setting, ns.AlertSourceEnabled(id))
    syncing = false
end

-- Alle Häkchen der Quellen: Die Abwahl gehört zum Profil – ns.ApplyBlockConfigs (Blocks.lua) ruft das, sobald die
-- Optionen der Bausteine ersetzt sind (Profilwechsel, Import), auch wenn der Baustein „Meldungen“ gerade aus ist.
function ns.RefreshAlertSettings()
    for id in pairs(alertSettings) do ns.RefreshAlertSetting(id) end
end

ns.OnReady(function()
    local ok, err = pcall(Register)
    if not ok then ns.Error(err, "Settings") end
end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
