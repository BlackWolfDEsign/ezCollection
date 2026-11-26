local _, ns = ...
local Core = ezCore

--[[
    Einstellungen: eine Kategorie „ezCollection“ unter Esc → Optionen → AddOns, darunter eine Seite
    je Modul (vorher fünf eigene Kategorien mit fünfmal demselben Code).

    local page = ezCore.NewSettingsPage(ns)            -- Seite „ezBag“ usw., Variablen „ezBag_<key>“
    page:Header(text, tooltip)
    page:Checkbox(key)                                  -- Text L["OPT_"..key], Tooltip L["OPT_"..key.."_TIP"]
    page:Slider(key, min, max, step, formatter)         -- formatter(value) → Text (optional)
    page:Dropdown(key, values)                          -- values = { { Wert, Text }, … }
    page:Button(label, buttonText, onClick, tooltip)
    page:CVarCheckbox(key, cvar, tooltip, opts)         -- Kästchen für eine CVar von Blizzard (die CVar ist die einzige
                                                        --   Quelle; opts.invert, opts.onChange); Text wie Checkbox
    page:CVarSlider(key, cvar, min, max, step, formatter, tooltip, opts)
    page:ProxyCheckbox(key, get, set, opts)             -- Kästchen für einen Wert, der woanders liegt (Einführung:
                                                        --   dieselben Schalter wie auf den Modulseiten); opts.label,
                                                        --   tooltip, default, shown
    page:MoverButton()                                  -- „Teile verschieben“ (unter „Allgemein“, ezCore.Mover)
    page:MoverResetButton()                             -- „Position zurücksetzen“ (unter „Erweitert“)
    page:Sub(title)                                     -- Unterseite (z. B. ezPanel „Bausteine“)
    page:Setting(key, varType, tbl, name, default, variable)   -- rohes Setting
    page:Register()                                     -- am Ende; danach page:Open()
    page:Advanced(tooltip)                              -- Überschrift „Erweitert“ (Standard für alle Seiten); auf der
                                                        --   Seite „ezCollection“ danach die Schalter des Hinweis-
                                                        --   Helfers (Core.OptInHint.AddSettings, Kern/OptInHint.lua)
    Jedes Steuerelement für sich abgesichert: eines darf scheitern, ohne die Seite zu verhindern.

    ezCores eigene Schalter (Seite „ezCollection“, V-018) laufen über dieselben Helfer:
      ezCore.ParentPage()                                -- Page-Objekt der Elternseite „ezCollection“ (eines)
      ezCore.OwnDefaults(gruppe, { key = wert })         -- Standardwerte anmelden → ezCore.DEFAULTS[gruppe]
      ezCore.OwnRules(gruppe, { limits = { key = { min, max } }, choices = { key = { wert … } } })
                                                         -- erlaubte Werte für eingefügte Texte (Core.ImportAll prüft
                                                         --   damit ezCores eigene Werte wie die der Module; T6-2)
      ezCore.OwnSettings(gruppe)                         -- ezCoreDB[gruppe], mit den Standardwerten aufgefüllt
      page:OwnCheckbox(gruppe, key, opts)                -- Kästchen für ezCoreDB[gruppe][key]; opts.text (Schlüssel
                                                         --   für OPT_<text>), variable, onChange, feature (Hinweis,
                                                         --   wenn ein fremdes Addon die Funktion übernimmt), tip,
                                                         --   shown (fn() → bool: Zeile nur zeigen, solange wahr)
      ezCore.ApplyOwnSetting(gruppe, key, wert)          -- eigenen Schalter setzen wie ein Klick (Kästchen zieht nach)
      ezCore.OwnExportSkip(gruppe, { key = true })       -- Schalter, die „Alles sichern“ nicht mitnimmt
      ezCore.SharedOn / SetShared / AdoptShared / ResetModuleShared, page:SharedCheckbox   -- gemeinsame Schalter mehrerer Module (unten)

    Abhängigkeiten (Unterschalter grau, solange der Oberschalter aus ist; Core.SettingsRows.Child): jedes
    Steuerelement nimmt opts.parent = key | Zeile | Setting und/oder opts.enabledWhen = fn() → bool (page:Checkbox,
    Slider und Dropdown mit opts als letztem Argument, OwnCheckbox, ProxyCheckbox, ProxyDropdown, CVarCheckbox,
    CVarSlider, Button); der Tooltip der gesperrten Zeile nennt den Oberschalter. Beschreibung unten bei DependencyOf.
      page:ResetOwn() / ezCore.ResetOwnSettings()        -- alle eigenen Schalter auf Standard → Anzahl geändert

    Einheitlicher Aufbau jeder Seite (ein Muster für alle Module):
      „Allgemein“  – Überschrift und Knopf zurück zur Übersicht „ezCollection“ setzt ezCore selbst;
                     direkt danach das Modul: Fenster öffnen bzw. Vorschau, dann Hauptschalter
      Themen       – Überschriften des Moduls (page:Header), Aktionen eines Themas stehen bei ihm
      „Erweitert“  – page:Advanced(): Zurücksetzen, Import, Status, Erklärungen neu zeigen (immer zuletzt)
    Texte: Steuerelemente heißen L.OPT_<key>, ihr Tooltip L.OPT_<key>_TIP (deutsch und englisch).
    Unterseiten (page:Sub) beginnen wie jede Seite mit „Allgemein“, darunter der Knopf zurück zu ihrer Modulseite.
    Lange Beschriftungen brechen auf zwei Zeilen um statt mit „…“ zu enden (eine Stelle: Core.WrapSettingsLabel,
    unten); den vollen Namen zeigt Blizzards Tooltip der Zeile ohnehin als Überschrift.

    Fehlt die Unterseiten-API, bekommt das Modul wie früher eine eigene Kategorie.
]]

local parent, parentLayout, parentRegistered

local function SettingsAvailable()
    return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
end

---------------------------------------------------------------------------
-- Beschriftungen: Umbruch statt „…“ – eine Stelle für alle Seiten der ezCollection (Spieltest 14.11.2026)
---------------------------------------------------------------------------
-- Blizzards Zeilen (SettingsListElementTemplate) tragen eine Beschriftung ohne Umbruch, die links der Mitte endet
-- (LEFT +37, RIGHT an CENTER −85); längere Texte endeten mit „…“ („Gegenstände immer vergleic…“). Breiter geht die
-- Spalte nicht, ohne Blizzards Kästchen und Regler zu verschieben – also bricht die Beschriftung um (zwei Zeilen
-- passen in die 26 px hohe Zeile). Den vollen Namen zeigt Blizzards Tooltip der Zeile schon als Überschrift
-- (Settings.InitTooltip), falls auch zwei Zeilen nicht reichen.
-- Taint-sicher: nur hooksecurefunc auf SettingsListElementMixin.Init und Aufrufe an der Beschriftung, nichts wird
-- in Blizzards Tabellen geschrieben. Blizzard verwendet die Zeilen-Rahmen für alle Seiten wieder – zeigt ein
-- Rahmen danach eine fremde Einstellung, bekommt er Blizzards Zustand (ohne Umbruch) zurück.
local ownCategories = setmetatable({}, { __mode = "k" })   -- Kategorie der ezCollection → ihr Layout (true: bei Blizzard erfragen)
local ownRows = setmetatable({}, { __mode = "k" })         -- Zeilen (Initializer) auf den Seiten der ezCollection
local wrappedRows = setmetatable({}, { __mode = "k" })     -- Blizzards Zeilen-Rahmen, deren Beschriftung gerade umbricht
local collectedRows = -1                                   -- Zeilen aller eigenen Seiten beim letzten Einsammeln
local collectedChanges = -1                                -- Core.SettingsRows.changes beim letzten Einsammeln
Core.SETTINGS_LABEL_LINES = 2

local function OwnCategory(category, layout)
    if type(category) == "table" then ownCategories[category] = type(layout) == "table" and layout or true end
    return category
end

local function OwnRow(initializer)
    if type(initializer) == "table" then ownRows[initializer] = true end
    return initializer
end

-- Zeilen einer eigenen Seite (Blizzards Liste des Layouts, nur gelesen): Layout → Liste oder nil.
local function LayoutRows(category, layout, panel)
    if layout == true then
        local getLayout = Core.Peek(panel, "GetLayout")
        if type(getLayout) ~= "function" then return nil end
        local ok, found = pcall(getLayout, panel, category)
        layout = ok and found or nil
    end
    local getRows = Core.Peek(layout, "GetInitializers")
    if type(getRows) ~= "function" then return nil end
    local ok, rows = pcall(getRows, layout)
    return ok and type(rows) == "table" and rows or nil
end

-- Sammelt die Zeilen aller Seiten der ezCollection ein (auch die, die ein Modul an den page:-Helfern vorbei über
-- Settings.CreateCheckbox oder layout:AddInitializer anlegt). Nichts zu tun, solange ihre Zahl gleich bleibt und
-- ezCore keine Liste umgereiht hat (Kern/SettingsRows.lua: sonst kann eine neue Zeile eine ausgereihte ersetzen).
-- → Anzahl der Zeilen.
function Core.CollectOwnSettingsRows()
    local panel = rawget(_G, "SettingsPanel")
    local total = 0
    for category, layout in pairs(ownCategories) do
        local rows = LayoutRows(category, layout, panel)
        if rows then total = total + #rows end
    end
    local changes = Core.SettingsRows and Core.SettingsRows.changes or 0
    if total == collectedRows and changes == collectedChanges then return total end
    for category, layout in pairs(ownCategories) do
        local rows = LayoutRows(category, layout, panel)
        for i = 1, rows and #rows or 0 do OwnRow(rows[i]) end
    end
    collectedRows, collectedChanges = total, changes
    return total
end

-- Gehört die Zeile zur ezCollection? Sie steht auf einer ihrer Seiten – gleich, welche Seite gerade offen ist:
-- Blizzards Suche zeigt Treffer aller Seiten mit denselben Zeilen-Objekten und lässt die offene Seite stehen
-- (Blizzard_SettingsPanel.lua, OnSearchTextChanged). Die offene Seite entscheidet deshalb nichts.
function Core.IsOwnSettingsRow(initializer)
    if type(initializer) ~= "table" then return false end
    if ownRows[initializer] then return true end
    Core.CollectOwnSettingsRows()
    return ownRows[initializer] == true
end

-- Nach Blizzards Init einer Zeile: Beschriftung umbrechen (eigene Zeile) bzw. Blizzards Zustand wiederherstellen.
-- → true, wenn die Beschriftung jetzt umbricht.
function Core.WrapSettingsLabel(frame, initializer)
    if type(frame) ~= "table" then return false end
    local text = Core.Peek(frame, "Text")
    if type(text) ~= "table" or type(text.SetWordWrap) ~= "function" then return false end
    if Core.IsOwnSettingsRow(initializer) then
        Core.SettingsRows.ApplyFont(frame, initializer)
        text:SetWordWrap(true)
        if type(text.SetMaxLines) == "function" then text:SetMaxLines(Core.SETTINGS_LABEL_LINES) end
        wrappedRows[frame] = true
        return true
    end
    if wrappedRows[frame] then
        text:SetWordWrap(false)
        if type(text.SetMaxLines) == "function" then text:SetMaxLines(0) end
        wrappedRows[frame] = nil
    end
    return false
end

do
    local mixin = rawget(_G, "SettingsListElementMixin")
    if type(mixin) == "table" and type(mixin.Init) == "function" and hooksecurefunc then
        hooksecurefunc(mixin, "Init", function(frame, initializer) pcall(Core.WrapSettingsLabel, frame, initializer) end)
    end
end

-- Kategorie „ezCollection“ (einmal angelegt; registriert wird sie nach den Modulseiten).
function Core.SettingsParent()
    if parent or not SettingsAvailable() then return parent, parentLayout end
    parent, parentLayout = Settings.RegisterVerticalLayoutCategory(Core.TITLE)
    if not parentLayout and SettingsPanel and SettingsPanel.GetLayout then parentLayout = SettingsPanel:GetLayout(parent) end
    OwnCategory(parent, parentLayout)
    return parent, parentLayout
end

-- Registriert die Kategorie „ezCollection“ samt allen Unterseiten bei Blizzard (einmal).
function Core.RegisterSettingsParent()
    if parentRegistered or not parent then return end
    parentRegistered = true
    Settings.RegisterAddOnCategory(parent)
end

-- Setting für eine CVar von Blizzard (Proxy: lesen und schreiben direkt die CVar, nichts in SavedVariables).
-- Eigene Variable, weil Blizzard eine CVar nicht zweimal registrieren lässt. Im Kampf wird nach dem Kampf gesetzt.
-- opts: invert (Kästchen an = CVar 0), onChange(value), default (sonst Blizzards Standard der CVar),
--       onRejected(value, roh) – das Spiel hat den Wert abgelehnt (Welle 23a, A70: Core.SetCVar gibt false zurück);
--       ohne onRejected meldet ezCore es im Chat (L.CVAR_REJECTED mit Name, CVar und Wert), owner = Absender
local pendingCVars = {}

-- Rückgabe von Core.SetCVar auswerten (Welle 23a, A70): false heißt, das Spiel hat den Wert nicht angenommen.
local function ApplyCVar(cvar, raw, value, name, opts)
    if Core.SetCVar(cvar, raw) then return true end
    if type(opts.onRejected) == "function" then
        Core.Try(opts.owner, "CVar onRejected " .. tostring(cvar), opts.onRejected, value, raw)
    else
        Core.Print(opts.owner or Core.TITLE, Core.L.CVAR_REJECTED:format(tostring(name or cvar), tostring(cvar), tostring(raw)))
    end
    return false
end

function Core.CVarSetting(category, variable, cvar, varType, name, opts)
    opts = opts or {}
    local isBool = varType == Settings.VarType.Boolean
    local function FromCVar(raw)
        if isBool then
            local on = raw == "1" or raw == 1 or raw == true
            if opts.invert then on = not on end
            return on
        end
        return tonumber(raw)
    end
    local function get()
        local raw = pendingCVars[cvar] or Core.CVar(cvar)
        if Core.IsSecret(raw) then raw = nil end
        local value = FromCVar(raw)
        if value == nil then value = opts.default end
        return value
    end
    local function set(value)
        local raw
        if isBool then
            local on = value and true or false
            if opts.invert then on = not on end
            raw = on and "1" or "0"
        else
            raw = tostring(value)
        end
        if Core.InCombat() then
            -- nach dem Kampf nachholen: je CVar gilt der letzte Wert (Core.AfterCombat ersetzt den wartenden)
            pendingCVars[cvar] = raw
            Core.AfterCombat(function()
                local waiting = pendingCVars[cvar]
                pendingCVars[cvar] = nil
                if waiting ~= nil then ApplyCVar(cvar, waiting, value, name, opts) end
            end, "ezCore.cvar:" .. tostring(cvar), Core.name)
        else
            pendingCVars[cvar] = nil
            ApplyCVar(cvar, raw, value, name, opts)
        end
        if opts.onChange then Core.Try(opts.owner, "CVar onChange " .. tostring(cvar), opts.onChange, value) end
    end
    local default = opts.default
    if default == nil and C_CVar and C_CVar.GetCVarDefault then
        local ok, raw = pcall(C_CVar.GetCVarDefault, cvar)
        if ok and not Core.IsSecret(raw) then default = FromCVar(raw) end
    end
    if default == nil then default = get() end
    if default == nil then default = isBool and false or 0 end
    return Settings.RegisterProxySetting(category, variable, varType, name, default, get, set)
end

-- Wartende CVars setzt Core.AfterCombat nach dem Kampf – kein eigener Zuhörer auf PLAYER_REGEN_ENABLED mehr.


local Page = {}
Page.__index = Page
local RememberSetting

function Page:Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Core.Error(self.owner, err, "Settings") end
    return ok
end

function Page:Setting(key, varType, tbl, name, default, variable)
    -- V-015: „default == nil and DEFAULTS[key] or default“ machte aus dem Standardwert false ein nil.
    if default == nil then
        local defaults = self.ns.DEFAULTS
        if type(defaults) == "table" then default = defaults[key] end
    end
    local setting = Settings.RegisterAddOnSetting(self.category, variable or (self.prefix .. key), key, tbl or self.ns.S,
        varType, name or self.L["OPT_" .. key], default)
    local mns = self.ns
    if not tbl then
        setting:SetValueChangedCallback(function() mns.SettingChanged(key) end)
        self.settings[key] = setting
        RememberSetting(mns, key, setting)
    end
    return setting
end

-- Alle Setting-Objekte eines Moduls, auch die der Unterseiten: mns.settingObjects[key] (für Core.ImportAll).
RememberSetting = function(mns, key, setting)
    if type(mns) ~= "table" then return end
    if type(mns.settingObjects) ~= "table" then mns.settingObjects = {} end
    mns.settingObjects[key] = setting
end

-- Grenzen eines Reglers bzw. Einträge eines Auswahlfelds merken (Gesamtreview 18.11.2026, T6-2): Core.ValidSetting
-- (Backup.lua) prüft eingefügte Werte damit genauso, wie die Seite sie anbietet – für jedes Modul, auch ohne eigene
-- ns.LIMITS/ns.CHOICES. mns.settingLimits[key] = { min, max }, mns.settingChoices[key] = { { wert, text } … }.
local function RememberRange(mns, field, key, value)
    if type(mns) ~= "table" or type(key) ~= "string" or value == nil then return end
    if type(mns[field]) ~= "table" then mns[field] = {} end
    mns[field][key] = value
end

---------------------------------------------------------------------------
-- ezCores eigene Schalter (V-018): Standardwerte an einer Stelle, Kästchen über die Page, Zurücksetzen
---------------------------------------------------------------------------

Core.DEFAULTS = Core.DEFAULTS or {}   -- [gruppe] = { key = Standardwert }; gruppe = Feld in ezCoreDB (comfort, tooltip)

function Core.OwnDefaults(group, values)
    if type(group) ~= "string" then return nil end
    local defaults = Core.DEFAULTS[group]
    if not defaults then
        defaults = {}
        Core.DEFAULTS[group] = defaults
    end
    for key, value in pairs(type(values) == "table" and values or {}) do defaults[key] = value end
    return defaults
end

-- Erlaubte Werte der eigenen Schalter (Gegenprüfung zu T6-2, Gesamtreview 18.11.2026): ezCores eigene Auswahlfelder
-- laufen über page:ProxyDropdown mit anderen Schlüsseln als in ezCoreDB und merken nichts in settingChoices. Die
-- Gruppe meldet ihre Grenzen und Auswahl hier an; Core.ImportAll gibt sie als LIMITS/CHOICES an Core.ValidSetting.
--   limits  = { key = { min, max } }   Zahl wird hineingeklemmt
--   choices = { key = { wert … } }     Text muss darin stehen (Einträge auch als { wert, anzeige })
Core.OWN_LIMITS = Core.OWN_LIMITS or {}
Core.OWN_CHOICES = Core.OWN_CHOICES or {}
function Core.OwnRules(group, rules)
    if type(group) ~= "string" or type(rules) ~= "table" then return end
    for field, store in pairs({ limits = Core.OWN_LIMITS, choices = Core.OWN_CHOICES }) do
        if type(rules[field]) == "table" then
            store[group] = store[group] or {}
            for key, value in pairs(rules[field]) do store[group][key] = value end
        end
    end
end

-- ezCoreDB[gruppe], fehlende oder falsch getypte Werte mit dem Standard gefüllt. nil vor ADDON_LOADED.
function Core.OwnSettings(group)
    local db = Core.db
    if type(db) ~= "table" or type(group) ~= "string" then return nil end
    if type(db[group]) ~= "table" then db[group] = {} end
    local tbl = db[group]
    for key, value in pairs(Core.DEFAULTS[group] or {}) do
        if type(tbl[key]) ~= type(value) then tbl[key] = value end
    end
    return tbl
end

-- Wert eines eigenen Schalters (Standard, solange ezCoreDB noch nicht geladen ist).
function Core.OwnSetting(group, key)
    local tbl = Core.OwnSettings(group)
    if tbl then return tbl[key] end
    local defaults = Core.DEFAULTS[group]
    return defaults and defaults[key]
end

-- Eigene Schalter, die „Alles sichern/übernehmen“ (Werkzeuge/Backup.lua) weder sichert noch übernimmt
-- (Gegenprüfung zum Gesamtreview 18.11.2026, Paket P6): Entwickler- und Testschalter sollen nur über ihr Kästchen
-- bzw. /ez debug entwickler an gehen, nie über einen geteilten Text. Gegenstück zu ns.EXPORT_SKIP der Module.
--   Core.OWN_EXPORT_SKIP[gruppe][key] = true;  Core.OwnExportSkip(gruppe, { key = true })
Core.OWN_EXPORT_SKIP = Core.OWN_EXPORT_SKIP or {}

function Core.OwnExportSkip(group, keys)
    if type(group) ~= "string" then return nil end
    local skip = Core.OWN_EXPORT_SKIP[group]
    if not skip then
        skip = {}
        Core.OWN_EXPORT_SKIP[group] = skip
    end
    for key, on in pairs(type(keys) == "table" and keys or {}) do skip[key] = on and true or nil end
    return skip
end

-- Einen eigenen Schalter setzen wie ein Klick (vorher ApplyOwnValue in Backup.lua; gemeinsam seit der Gegenprüfung
-- zum Gesamtreview 18.11.2026, P6, auch für /ez debug entwickler): zuerst über das Setting-Objekt des Kästchens der
-- Seite „ezCollection“ (Blizzards Anzeige zieht nach, Bedingungen anderer Zeilen werden neu ausgewertet), sonst
-- direkt in ezCoreDB[gruppe] samt onChange. → "setting" | "raw"; nil, solange ezCoreDB nicht geladen ist.
function Core.ApplyOwnSetting(group, key, value)
    local tbl = Core.OwnSettings(group)
    if not tbl then return nil end
    local page = Core.ParentPage and Core.ParentPage()
    for _, entry in ipairs(page and page.own or {}) do
        if entry.group == group and entry.key == key then
            if pcall(entry.setting.SetValue, entry.setting, value) and tbl[key] == value then return "setting" end
            local before = tbl[key]
            tbl[key] = value
            if entry.onChange then Core.Try(nil, "ApplyOwnSetting onChange " .. tostring(key), entry.onChange, value) end
            if before ~= value then Core.Fire(Core.OWN_SETTING_CHANGED, group, key, value) end
            return "raw"
        end
    end
    local before = tbl[key]
    tbl[key] = value
    if before ~= value then Core.Fire(Core.OWN_SETTING_CHANGED, group, key, value) end
    return "raw"
end

---------------------------------------------------------------------------
-- Gemeinsame Schalter mehrerer Module (Einstellungs-Prüfung 19.11.2026, Nr. 50/58, 59/60, 62, 93, 95/96): EIN Wert in
-- ezCoreDB[gruppe][key], den mehrere Module lesen – statt je Modul ein eigener, von dem je nach Lage nur einer wirkt.
--   Core.OWN_SETTING_CHANGED                 Nachricht (gruppe, key, wert) nach jeder Änderung eines eigenen Schalters
--                                            (Kästchen, Spiegel, Core.ApplyOwnSetting) – Module ziehen ihre Anzeige nach
--   Core.SharedOn(gruppe, key)               → true, wenn der Schalter an ist (Standard, solange ezCoreDB fehlt)
--   Core.SetShared(gruppe, key, an)          setzt ihn wie ein Klick (auch das Kästchen der Seite „ezCollection“ zieht
--                                            nach) → neuer Wert
--   Core.AdoptShared(gruppe, key, quelle, alterWert, art)
--                                            übernimmt EINMAL je Quelle (Modul) dessen bisherigen Wert: nur ein „an“
--                                            schaltet ein (was der Spieler sah oder erlaubt hatte, bleibt), ein „aus“
--                                            ändert nichts. art = "first": der Schalter ist neu in ezCore – die erste
--                                            Quelle mit gespeichertem Wert setzt ihn (auch auf aus), jede weitere nur
--                                            noch ein. Ohne gespeicherten Wert (nil) tut sie nichts. Merker
--                                            ezCoreDB.migrated["shared:<gruppe>.<key>:<quelle>"] (und ohne Quelle für
--                                            „first“). → true, wenn der Wert sich änderte; nil, wenn schon übernommen
--   page:SharedCheckbox(gruppe, key, opts)   Spiegel auf einer Modulseite: dasselbe Kästchen wie auf der Seite
--                                            „ezCollection“, ein Wert; opts.text (OPT_<text>), label, tooltip, shown,
--                                            parent, enabledWhen. Der Tooltip sagt, dass der Schalter für mehrere Module gilt.
---------------------------------------------------------------------------
Core.OWN_SETTING_CHANGED = "OWN_SETTING_CHANGED"

function Core.SharedOn(group, key)
    return Core.OwnSetting(group, key) == true
end

function Core.SetShared(group, key, on)
    on = on == true
    Core.ApplyOwnSetting(group, key, on)
    return Core.SharedOn(group, key)
end

-- Ein Modul meldet seine gemeinsamen Schalter an: map = { lokalerSchlüssel = { gruppe, key, mode = "first"?, old = w? } }.
--   mns.SHARED = map: ns.Enabled(lokal) und ns.SetSetting(lokal, wert) lesen bzw. setzen den Wert in ezCore,
--   page:Checkbox(lokal) baut den Spiegel (page:SharedCheckbox), der Slash-Schalter aus ns.TOGGLES schaltet ihn,
--   nach jeder Änderung läuft ns.SettingChanged(lokal) (die Anzeige des Moduls zieht nach wie vorher).
--   Core.AdoptModuleShared(mns, db) beim Laden (onLoad): übernimmt einmal die alten Werte aus db.settings
--   (Core.AdoptShared mit dem Modulnamen als Quelle) und entfernt sie dort. → Anzahl geänderter Werte
--   old = der frühere Standard des Moduls: Core.FillDefaults hat ihn bei jedem Spieler gespeichert, ein gespeicherter
--   Wert gleich old ist also keine Wahl und wird nicht übernommen (Gegenprüfung 19.11.2026: sonst schaltete ein nie
--   angefasster Standard „an“ den gemeinsamen Schalter ein, auch gegen ein bewusstes „aus“ im anderen Modul)
--   Core.ResetModuleShared(mns) setzt die gemeinsamen Schalter des Moduls auf ezCores Standard (Teil von
--   „Einstellungen zurücksetzen“ des Moduls: Page:ResetToDefaults, Core.SlashReset) → Anzahl geänderter Werte
--   Core.SharedChoice(shared, wert) → true, wenn wert ein Wahrheitswert ist, der nicht dem alten Standard entspricht
function Core.ShareSettings(mns, map)
    if type(mns) ~= "table" or type(map) ~= "table" then return nil end
    mns.SHARED = map
    Core.Listen(Core.OWN_SETTING_CHANGED, function(group, key)
        for localKey, shared in pairs(map) do
            if shared[1] == group and shared[2] == key and type(mns.SettingChanged) == "function" then
                mns.SettingChanged(localKey)
            end
        end
    end, mns.moduleName or "ezCore")
    return map
end

function Core.AdoptModuleShared(mns, db)
    if type(mns) ~= "table" or type(mns.SHARED) ~= "table" or type(db) ~= "table" or type(db.settings) ~= "table" then
        return 0
    end
    -- ohne ezCoreDB kann nichts übernommen werden: alte Werte dann liegen lassen statt still zu löschen
    if type(Core.db) ~= "table" then return 0 end
    local changed = 0
    -- feste Reihenfolge (Schlüssel sortiert), damit die Übernahme bei jedem Laden gleich läuft
    local keys = {}
    for localKey in pairs(mns.SHARED) do keys[#keys + 1] = localKey end
    table.sort(keys)
    for _, localKey in ipairs(keys) do
        local shared = mns.SHARED[localKey]
        local value = db.settings[localKey]
        if Core.SharedChoice(shared, value) then
            if Core.AdoptShared(shared[1], shared[2], mns.moduleName, value, shared.mode) then changed = changed + 1 end
        end
        db.settings[localKey] = nil
    end
    return changed
end

function Core.SharedChoice(shared, value)
    if type(value) ~= "boolean" then return false end
    return not (type(shared) == "table" and shared.old ~= nil and value == shared.old)
end

function Core.ResetModuleShared(mns)
    if type(mns) ~= "table" or type(mns.SHARED) ~= "table" then return 0 end
    local changed = 0
    for _, shared in pairs(mns.SHARED) do
        local default = type(shared) == "table" and (Core.DEFAULTS[shared[1]] or {})[shared[2]]
        if type(default) == "boolean" and Core.SharedOn(shared[1], shared[2]) ~= default then
            Core.SetShared(shared[1], shared[2], default)
            changed = changed + 1
        end
    end
    return changed
end

function Core.AdoptShared(group, key, source, value, mode)
    local db = Core.db
    if type(db) ~= "table" or type(group) ~= "string" or type(key) ~= "string" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    local migrated = db.migrated
    local first = "shared:" .. group .. "." .. key
    return Core.MigrateOnce(migrated, first .. ":" .. tostring(source), function()
        if type(value) ~= "boolean" then return false end
        local tbl = Core.OwnSettings(group)
        if not tbl then return false end
        local want = value
        if mode == "first" and not migrated[first] then
            migrated[first] = true          -- die erste Quelle mit Wert bestimmt den neuen Schalter, auch ein „aus“
        elseif value ~= true then
            return false                    -- danach schaltet nur noch ein „an“ ein
        end
        if tbl[key] == want then return false end
        tbl[key] = want
        Core.Fire(Core.OWN_SETTING_CHANGED, group, key, want)
        return true
    end)
end

---------------------------------------------------------------------------
-- Abhängigkeiten: Unterschalter ausgrauen, solange ihr Oberschalter aus ist (Einstellungs-Prüfung 19.11.2026,
-- Querschnitt „Unterschalter ausgrauen“). Blizzards Wege (Forever-Quelle Blizzard_Settings_Shared/
-- Blizzard_SettingControls.lua): AddModifyPredicate – SettingsControlMixin:IsEnabled fragt EvaluateModifyPredicates, das
-- Kästchen, der Regler bzw. das Auswahlfeld wird grau –, data.indent rückt ein, AddEvaluateStateCVar(Variable der Oberzeile)
-- wertet neu aus, sobald sich ihr Wert ändert. Nicht SetParentInitializer: Blizzards Suche liest parentInitializer ungeschützt
-- (Kern/SettingsRows.lua). Ohne Oberzeile (nur opts.enabledWhen) nur AddModifyPredicate.
--   opts.parent       Schlüssel eines Steuerelements dieser Seite (page:Checkbox/OwnCheckbox/ProxyCheckbox …), die
--                     Zeile (Initializer) oder das Setting-Objekt des Oberschalters
--   opts.enabledWhen  fn() → bool: bedienbar, solange wahr (Standard mit opts.parent: der Oberschalter ist an)
--   opts.parentLabel  Name des Oberschalters für den Tooltip (sonst Blizzards Name der Oberzeile)
-- Der Tooltip einer gesperrten Zeile nennt den Oberschalter (L.SETTINGS_NEEDS_PARENT). Ein Fehler im Prädikat landet
-- in der Fehlerliste und lässt die Zeile bedienbar.
---------------------------------------------------------------------------

-- Zeile bzw. Setting merken, damit spätere Zeilen opts.parent = key nennen können.
local function RememberRow(page, key, row, setting)
    if type(page) ~= "table" or type(key) ~= "string" then return end
    page.rows = page.rows or {}
    page.rowSettings = page.rowSettings or {}
    if type(row) == "table" then page.rows[key] = row end
    if type(setting) == "table" then page.rowSettings[key] = setting end
end

-- opts.parent auflösen → Zeile (oder nil), Setting (oder nil)
local function ResolveParent(page, parent)
    if type(parent) == "string" then
        local rows, settings = page.rows or {}, page.rowSettings or {}
        local all = type(page.ns) == "table" and type(page.ns.settingObjects) == "table" and page.ns.settingObjects or {}
        return rows[parent], settings[parent] or page.settings[parent] or all[parent]
    end
    if type(parent) ~= "table" then return nil, nil end
    if type(parent.GetSetting) == "function" or type(parent.AddModifyPredicate) == "function" then
        local ok, setting = pcall(function() return parent:GetSetting() end)
        return parent, ok and type(setting) == "table" and setting or nil
    end
    return nil, parent
end

local function SettingOn(setting)
    if type(setting) ~= "table" or type(setting.GetValue) ~= "function" then return true end
    local ok, value = pcall(setting.GetValue, setting)
    if not ok or Core.IsSecret(value) then return true end
    if type(value) == "number" then return value ~= 0 end
    return value ~= false and value ~= nil
end

-- → Prädikat fn() → bool oder nil, Oberzeile, Name des Oberschalters (fn), Setting des Oberschalters
local function DependencyOf(page, opts)
    if type(opts) ~= "table" or (opts.parent == nil and type(opts.enabledWhen) ~= "function") then return nil end
    local row, setting = ResolveParent(page, opts.parent)
    local owner, when = page.owner, opts.enabledWhen
    local function Enabled()
        if type(when) == "function" then
            local ok, value = Core.Try(owner, "Settings enabledWhen", when)
            return not ok or value and true or false
        end
        return SettingOn(setting)
    end
    local function Name()
        if type(opts.parentLabel) == "string" then return opts.parentLabel end
        for _, obj in ipairs({ row or false, setting or false }) do
            if obj and type(obj.GetName) == "function" then
                local ok, name = pcall(obj.GetName, obj)
                if ok and type(name) == "string" and name ~= "" then return name end
            end
        end
        return nil
    end
    return Enabled, row, Name, setting
end
Core.SettingsDependencyOf = DependencyOf

-- Tooltip mit Abhängigkeit: Blizzards Settings.InitTooltip nimmt auch eine Funktion. Gesperrt hängt ein Absatz an, der den
-- Oberschalter nennt. → Tooltip (Text oder Funktion)
local function DependentTip(page, opts, tip)
    local enabled, _, name = DependencyOf(page, opts)
    if not enabled then return tip end
    return function()
        local text = type(tip) == "function" and tip() or tip
        if enabled() then return text end
        local parentName = name()
        local note = parentName and Core.L.SETTINGS_NEEDS_PARENT:format(parentName) or Core.L.SETTINGS_NEEDS_PARENT_ANY
        if type(text) ~= "string" or text == "" then return note end
        return text .. "\n\n" .. note
    end
end
Core.SettingsDependentTip = DependentTip

-- Abhängigkeit an der fertigen Zeile anmelden (nach Settings.Create…). → true, wenn angemeldet
local function AddDependency(page, row, opts)
    if type(row) ~= "table" then return false end
    local enabled, parentRow, _, setting = DependencyOf(page, opts)
    if not enabled then return false end
    if opts.parent ~= nil then Core.SettingsRows.Child(page, row, parentRow, setting) end
    if type(row.AddModifyPredicate) == "function" then return (pcall(row.AddModifyPredicate, row, enabled)) end
    return false
end
Core.AddSettingsDependency = AddDependency

-- Zeile nur zeigen, solange shown() wahr ist; ein Fehler in shown landet in der Fehlerliste und blendet die Zeile aus.
local function AddShown(page, row, shown, where)
    Core.SettingsRows.ShowWhen(page, row, shown, where)
end

-- dasselbe für eine fertige Zeile (Module: ezPanels Meldungsquellen)
function Page:ShowWhen(row, shown, where)
    return Core.SettingsRows.ShowWhen(self, row, shown, where)
end

function Page:OwnCheckbox(group, key, opts)
    opts = opts or {}
    local page, result, resultRow = self, nil, nil
    self:Try(function()
        local tbl = Core.OwnSettings(group)
        local defaults = Core.DEFAULTS[group] or {}
        if not tbl then return end
        if tbl[key] == nil then tbl[key] = defaults[key] == true end
        local textKey = "OPT_" .. (opts.text or key)
        local setting = page:Setting(key, Settings.VarType.Boolean, tbl, opts.name or page.L[textKey], defaults[key] == true,
            opts.variable or (page.prefix .. key))
        local entry = { setting = setting, group = group, key = key, onChange = opts.onChange }
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
                if entry.onChange then page:Try(entry.onChange, tbl[key]) end
                Core.Fire(Core.OWN_SETTING_CHANGED, group, key, tbl[key])
            end)
        end
        page.own = page.own or {}
        page.own[#page.own + 1] = entry
        local tip = opts.tip or page.L[textKey .. "_TIP"]
        -- reine Auskunft: zählt nicht als „gewichen“ (Core.WhoHandlesInfo, Welle 13)
        local ask = Core.WhoHandlesInfo or Core.WhoHandles
        local who = opts.feature and ask and ask(opts.feature)
        if who then tip = tip .. "\n\n" .. Core.L.COMFORT_HANDLED:format(who) end
        if opts.note then tip = tip .. "\n\n" .. opts.note end
        tip = page:WithNote(tip, "OPT_" .. group .. "_" .. key .. "_NOTE")
        resultRow = OwnRow(Settings.CreateCheckbox(page.category, setting, DependentTip(page, opts, tip)))
        AddShown(page, resultRow, opts.shown, "OwnCheckbox " .. key)
        AddDependency(page, resultRow, opts)
        RememberRow(page, key, resultRow, setting)
        RememberRow(page, group .. "." .. key, resultRow, setting)
        result = setting
    end)
    return result, resultRow
end

-- Alle über OwnCheckbox angelegten Schalter dieser Seite auf Standard. → Anzahl geänderter Schalter.
function Page:ResetOwn()
    local changed = 0
    for _, entry in ipairs(self.own or {}) do
        local tbl = Core.OwnSettings(entry.group)
        local default = (Core.DEFAULTS[entry.group] or {})[entry.key]
        if tbl and default ~= nil and tbl[entry.key] ~= default then
            changed = changed + 1
            if not pcall(entry.setting.SetValue, entry.setting, default) or tbl[entry.key] ~= default then
                tbl[entry.key] = default
                if entry.onChange then self:Try(entry.onChange, default) end
            end
        end
    end
    return changed
end

function Page:Header(text, tooltip)
    local layout = self.layout
    if not (layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer) then return end
    self:Try(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip)) end)
end

-- Checkbox, Slider und Dropdown geben die Einstellung und die Zeile (Initializer) zurück, damit ein Modul die Zeile
-- später ausblenden kann (page:ShowWhen; Wunsch aus ezBars für die Unterseite einer abgemeldeten Leiste).
-- → Setting, Initializer oder nil, wenn der Client es nicht kann oder ein Fehler auftrat (in der Fehlerliste).
-- Dieselbe Reihenfolge wie page:ProxyDropdown und page:OwnCheckbox: zuerst die Einstellung, dann die Zeile.
--   opts.shown  fn() → bool: Zeile nur zeigen, solange fn() wahr ist (wie page:Button und page:ProxyDropdown; vorher
--               bauten ezMacro (ShownIf) und ezBars (ShowWhen) das je selbst)

-- Zweiter Absatz eines Tooltips (Welle 23a, A59): der Text noteKey, wenn es ihn gibt. page:OwnCheckbox fragt
-- OPT_<gruppe>_<schlüssel>_NOTE (eindeutig je ezCore-Schalter – ein Modul mit gleichnamigem eigenem Schalter erbt
-- ihn nicht über den Rückfall von Core.NewLocale), etwa OPT_priceOpts_worthBag_NOTE: mit ezBag gilt dort ezBags Schalter.
function Page:WithNote(tip, noteKey)
    local note = type(noteKey) == "string" and self.L[noteKey]
    if type(note) ~= "string" or note == "" or note == noteKey then return tip end
    if type(tip) ~= "string" or tip == "" then return note end
    return tip .. "\n\n" .. note
end

--   opts.feature (Welle 23a, A42; wie page:OwnCheckbox): Funktionsschlüssel aus Core.OTHER_ADDONS – übernimmt ein
--               fremdes Addon ihn, hängt der Tooltip „Übernimmt schon: …“ an (COMFORT_HANDLED); opts.note: eigener
--               zweiter Absatz.
function Page:Checkbox(key, tooltip, opts)
    local row, setting
    opts = type(opts) == "table" and opts or {}
    -- gemeinsamer Schalter (Core.ShareSettings): dasselbe Kästchen als Spiegel des Werts in ezCore
    local shared = type(self.ns) == "table" and type(self.ns.SHARED) == "table" and self.ns.SHARED[key]
    if shared then
        local mirror = {}
        for k, v in pairs(opts) do mirror[k] = v end
        mirror.text = mirror.text or key
        if tooltip ~= nil then mirror.tooltip = tooltip end
        return self:SharedCheckbox(shared[1], shared[2], mirror)
    end
    self:Try(function()
        setting = self:Setting(key, Settings.VarType.Boolean)
        local tip = tooltip or self.L["OPT_" .. key .. "_TIP"]
        local ask = Core.WhoHandlesInfo or Core.WhoHandles
        local who = opts.feature and ask and ask(opts.feature)
        if who and type(tip) == "string" then tip = tip .. "\n\n" .. Core.L.COMFORT_HANDLED:format(who) end
        if opts.note and type(tip) == "string" then tip = tip .. "\n\n" .. opts.note end
        row = OwnRow(Settings.CreateCheckbox(self.category, setting, DependentTip(self, opts, tip)))
        AddShown(self, row, opts.shown, "Checkbox " .. tostring(key))
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    if row == nil then return nil end
    return setting, row
end

--   page:Slider(…, tooltip, opts) und page:Dropdown(key, values, tooltip, opts): opts.parent, opts.enabledWhen,
--   opts.parentLabel (Abhängigkeit, oben), opts.shown
function Page:Slider(key, minValue, maxValue, step, formatter, tooltip, opts)
    if not (Settings.CreateSlider and Settings.CreateSliderOptions) then return nil end
    opts = type(opts) == "table" and opts or {}
    local row, setting
    self:Try(function()
        setting = self:Setting(key, Settings.VarType.Number)
        if type(minValue) == "number" and type(maxValue) == "number" then
            RememberRange(self.ns, "settingLimits", key, { minValue, maxValue })
        end
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
        end
        row = OwnRow(Settings.CreateSlider(self.category, setting, options,
            DependentTip(self, opts, tooltip or self.L["OPT_" .. key .. "_TIP"])))
        AddShown(self, row, opts.shown, "Slider " .. tostring(key))
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    if row == nil then return nil end
    return setting, row
end

function Page:Dropdown(key, values, tooltip, opts)
    local create = Settings.CreateDropdown or Settings.CreateDropDown
    if not (create and Settings.CreateControlTextContainer) then return nil end
    opts = type(opts) == "table" and opts or {}
    local row, setting
    self:Try(function()
        setting = self:Setting(key, Settings.VarType.String)
        if type(values) == "table" then RememberRange(self.ns, "settingChoices", key, values) end
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, entry in ipairs(values) do container:Add(entry[1], entry[2]) end
            return container:GetData()
        end
        row = OwnRow(create(self.category, setting, GetOptions,
            DependentTip(self, opts, tooltip or self.L["OPT_" .. key .. "_TIP"])))
        AddShown(self, row, opts.shown, "Dropdown " .. tostring(key))
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    if row == nil then return nil end
    return setting, row
end

-- Blizzards Auswahlfeld auf eine Proxy-Einstellung (EC-114; vorher baute ezBuff es für „Segen für <Klasse>“ selbst):
-- der Wert lebt außerhalb von ns.S – z. B. je Charakter – und wird über get() gelesen und set(wert) geschrieben.
--   values       Liste { { wert, text } … } oder fn() → Liste; eine Funktion wird bei jedem Öffnen neu gefragt
--   opts.format  Formatwert für Text und Tooltip: OPT_<key> und OPT_<key>_TIP mit „%s“ („Segen für %s“)
--   opts.id      Zusatz für den Namen der Einstellung, wenn derselbe key mehrfach vorkommt (je Klasse ein Feld)
--   opts.label, opts.tooltip   statt OPT_<key> und OPT_<key>_TIP
--   opts.default Standardwert (sonst der jetzige Wert, sonst ""); opts.varType (Standard Settings.VarType.String)
--   opts.shown   fn() → bool: Zeile nur zeigen, wenn …
-- „Einstellungen zurücksetzen“ lässt den Wert stehen (er gehört nicht zu ns.S). Fehler in get, set, values und
-- shown landen in der Fehlerliste des Moduls. → Setting, Zeile (Initializer) oder nil, wenn der Client es nicht kann.
function Page:ProxyDropdown(key, values, get, set, opts)
    opts = opts or {}
    local create = Settings.CreateDropdown or Settings.CreateDropDown
    if not (Settings.RegisterProxySetting and create and Settings.CreateControlTextContainer) then return nil end
    if type(key) ~= "string" or type(get) ~= "function" or type(set) ~= "function" then return nil end
    local owner = self.owner
    local where = "ProxyDropdown " .. key
    local function Get()
        local ok, value = Core.Try(owner, where .. " get", get)
        if ok and not Core.IsSecret(value) and value ~= nil then return value end
        return nil
    end
    local setting, row
    self:Try(function()
        local label = opts.label or self.L["OPT_" .. key]
        local tip = opts.tooltip or self.L["OPT_" .. key .. "_TIP"]
        if opts.format ~= nil then label, tip = label:format(opts.format), tip:format(opts.format) end
        local default = opts.default
        if default == nil then default = Get() end
        if default == nil then default = "" end
        local variable = self.prefix .. key .. (opts.id ~= nil and ("_" .. tostring(opts.id)) or "")
        setting = Settings.RegisterProxySetting(self.category, variable, opts.varType or Settings.VarType.String, label, default,
            function()
                local value = Get()
                if value == nil then return default end
                return value
            end,
            function(value) Core.Try(owner, where .. " set", set, value) end)
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            local list = values
            if type(list) == "function" then
                local ok, result = Core.Try(owner, where .. " values", list)
                list = ok and result or nil
            end
            for _, entry in ipairs(type(list) == "table" and list or {}) do container:Add(entry[1], entry[2]) end
            return container:GetData()
        end
        row = OwnRow(create(self.category, setting, GetOptions, DependentTip(self, opts, tip)))
        AddShown(self, row, opts.shown, where)
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    return setting, row
end

-- Kästchen für einen Wert, der woanders gespeichert ist (Einführung, Werkzeuge/FirstStart.lua: dieselben Schalter wie
-- auf den Seiten der Module; W-1811-Einfuehrung). Blizzards Kästchen fragt get() bei jedem Zeichnen – die Quelle bleibt
-- dort, wo der Wert liegt; ein Klick ruft set(true|false). Ändert set nichts (abgelehnt), zeigt das Kästchen danach
-- wieder den echten Stand. Wie page:ProxyDropdown:
--   opts.label, opts.tooltip  statt OPT_<key> und OPT_<key>_TIP
--   opts.default              Standard für Blizzards Knopf „Standard“ (sonst der jetzige Wert)
--   opts.shown                fn() → bool: Zeile nur zeigen, wenn …
-- Fehler in get und set landen in der Fehlerliste des Moduls. → Setting, Zeile (Initializer) oder nil
function Page:ProxyCheckbox(key, get, set, opts)
    opts = type(opts) == "table" and opts or {}
    if not (Settings.RegisterProxySetting and Settings.CreateCheckbox) then return nil end
    if type(key) ~= "string" or type(get) ~= "function" or type(set) ~= "function" then return nil end
    local owner = self.owner
    local where = "ProxyCheckbox " .. key
    local function Get()
        local ok, value = Core.Try(owner, where .. " get", get)
        return ok and not Core.IsSecret(value) and value == true
    end
    local setting, row
    -- Blizzards Setting meldet nach dem Schreiben den GEWÜNSCHTEN Wert ans Kästchen (SettingMixin:ApplyValue ruft
    -- TriggerValueChanged(value), Blizzard_Settings_Shared/Blizzard_Setting.lua). Lehnt set ab (Kampf, Schalter nur
    -- einschaltbar, Modul fehlt), zieht NotifyUpdate den echten Stand nach – einen Rahmen später, sonst überschriebe
    -- Blizzards eigene Meldung ihn wieder (Gegenprüfung W-1811-Einfuehrung).
    local function Refresh()
        if type(setting) == "table" and type(setting.NotifyUpdate) == "function" then
            Core.Try(owner, where .. " refresh", setting.NotifyUpdate, setting)
        end
    end
    local function Set(value)
        value = value == true
        Core.Try(owner, where .. " set", set, value)
        if Get() ~= value and C_Timer and C_Timer.After then C_Timer.After(0, Refresh) end
    end
    self:Try(function()
        local label = opts.label or self.L["OPT_" .. key]
        local tip = opts.tooltip or self.L["OPT_" .. key .. "_TIP"]
        local default = opts.default
        if type(default) ~= "boolean" then default = Get() end
        setting = Settings.RegisterProxySetting(self.category, self.prefix .. key, Settings.VarType.Boolean, label, default,
            Get, Set)
        row = OwnRow(Settings.CreateCheckbox(self.category, setting, DependentTip(self, opts, tip)))
        AddShown(self, row, opts.shown, where)
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    return setting, row
end

-- opts wie Core.CVarSetting, dazu opts.parent, opts.enabledWhen, opts.parentLabel (Abhängigkeit) und opts.shown.
-- → Setting, Zeile (Initializer) oder nil
-- Spiegel eines gemeinsamen Schalters von ezCore (oben, „Gemeinsame Schalter“). → Setting, Zeile oder nil
function Page:SharedCheckbox(group, key, opts)
    opts = type(opts) == "table" and opts or {}
    if type(group) ~= "string" or type(key) ~= "string" then return nil end
    local text = "OPT_" .. (opts.text or key)
    local tip = opts.tooltip or self.L[text .. "_TIP"]
    local note = Core.L.SETTINGS_SHARED_NOTE
    if type(tip) == "string" and type(note) == "string" then tip = tip .. "\n\n" .. note end
    local default = (Core.DEFAULTS[group] or {})[key]
    local mirror = {}
    for k, v in pairs(opts) do mirror[k] = v end
    mirror.label = opts.label or self.L[text]
    mirror.tooltip = tip
    mirror.default = default == true
    local setting, row = self:ProxyCheckbox("shared_" .. key, function() return Core.SharedOn(group, key) end,
        function(on) Core.SetShared(group, key, on) end, mirror)
    RememberRow(self, key, row, setting)
    -- auch unter dem Schlüssel des Moduls (page:Checkbox(lokal) übergibt ihn als opts.text), damit opts.parent = lokal greift
    if type(opts.text) == "string" and opts.text ~= key then RememberRow(self, opts.text, row, setting) end
    return setting, row
end

function Page:CVarCheckbox(key, cvar, tooltip, opts)
    if not Settings.RegisterProxySetting then return end
    opts = type(opts) == "table" and opts or {}
    local setting, row
    self:Try(function()
        setting = Core.CVarSetting(self.category, self.prefix .. key, cvar, Settings.VarType.Boolean,
            self.L["OPT_" .. key], opts)
        row = OwnRow(Settings.CreateCheckbox(self.category, setting,
            DependentTip(self, opts, tooltip or self.L["OPT_" .. key .. "_TIP"])))
        AddShown(self, row, opts.shown, "CVarCheckbox " .. tostring(key))
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    return setting, row
end

function Page:CVarSlider(key, cvar, minValue, maxValue, step, formatter, tooltip, opts)
    if not (Settings.RegisterProxySetting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
    opts = type(opts) == "table" and opts or {}
    local setting, row
    self:Try(function()
        setting = Core.CVarSetting(self.category, self.prefix .. key, cvar, Settings.VarType.Number,
            self.L["OPT_" .. key], opts)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        if formatter and options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
        end
        row = OwnRow(Settings.CreateSlider(self.category, setting, options,
            DependentTip(self, opts, tooltip or self.L["OPT_" .. key .. "_TIP"])))
        AddShown(self, row, opts.shown, "CVarSlider " .. tostring(key))
        AddDependency(self, row, opts)
        RememberRow(self, key, row, setting)
    end)
    return setting, row
end

-- opts.protected = true: die Aktion ist im Kampf gesperrt (ST-04: eine offene Seite bleibt offen, ihre geschützten
-- Knöpfe tun im Kampf nichts außer einem Hinweis).
-- opts.shown = fn() → bool: Zeile nur zeigen, solange fn() wahr ist (wie page:Checkbox).
-- opts.parent, opts.enabledWhen, opts.parentLabel: Knopf grau, solange der Oberschalter aus ist (Abhängigkeit, oben).
-- opts.search = false: über Blizzards Suche nicht zu finden (sonst über Beschriftung und Knopftext); opts.searchTags =
-- { text … }: stattdessen über diese Texte (etwa die zweite Zeile von page:AllToggle: Beschriftung " ", gefunden über die der Gruppe).
function Page:Button(label, buttonText, onClick, tooltip, opts)
    local layout = self.layout
    if not (layout and layout.AddInitializer and Core.SettingsRows.Available()) then return end
    local initializer
    if type(opts) == "table" and opts.protected and type(onClick) == "function" then
        local run, owner = onClick, self.owner
        onClick = function(...)
            if Core.InCombat() then
                Core.Print(owner, Core.L.SETTINGS_COMBAT_BLOCKED)
                return
            end
            return run(...)
        end
    end
    self:Try(function()
        local tags = { label, buttonText }
        if type(opts) == "table" then
            if type(opts.searchTags) == "table" then tags = opts.searchTags elseif opts.search == false then tags = nil end
        end
        initializer = OwnRow(Core.SettingsRows.Button(self.category, label, buttonText, onClick, DependentTip(self, opts, tooltip), tags))
        layout:AddInitializer(initializer)
        AddShown(self, initializer, type(opts) == "table" and opts.shown, "Button " .. tostring(label))
        AddDependency(self, initializer, opts)
    end)
    return initializer   -- z. B. für page:ShowWhen(initializer, fn) (Zeile nur zeigen, solange fn() wahr ist)
end

-- „Alle auswählen / Alle abwählen“ auf einer Einstellungsseite (Design-System, Regel „Mehrfachauswahl“,
-- docs/design-system.md; Gegenstück im Menü ist Core.Menu.AllToggle): zwei Knopfzeilen, die die Kästchen dieser
-- Schlüssel an- bzw. ausschalten – nur, was abweicht, über Blizzards Setting-Objekte (die Kästchen ziehen nach,
-- ns.SettingChanged läuft je Schlüssel, die Auswahl bleibt gespeichert). Gesperrte und nicht boolesche Werte bleiben
-- unberührt. keys = { key | Setting … } | fn() → Liste: Schlüssel der Seite oder ihrer Unterseiten, Schlüssel der
-- Schalter aus page:OwnCheckbox oder Setting-Objekte, wie page:Setting(key, …, tbl) sie für eine eigene Tabelle
-- zurückgibt (die stehen in keiner Liste der Seite; Fund der Gegenprüfung: ezPanels Bausteine und Alarm-Quellen,
-- ezCores Gruppe „Tooltip“); opts = { label, tip, onTip,
-- offTip, on = false (ohne „Alle auswählen“), off = false (ohne „Alle abwählen“), onText, offText (Standard: Blizzards
-- CHECK_ALL/UNCHECK_ALL, sonst ezCores Text), shown } → Zeile „an“, Zeile „aus“, SetAll(an) → Anzahl geänderter.
function Page:AllToggle(keys, opts)
    opts = type(opts) == "table" and opts or {}
    local page = self
    local function List()
        local list = keys
        if type(list) == "function" then
            local ok, result = pcall(list)
            list = ok and result or nil
        end
        return type(list) == "table" and list or {}
    end
    local function SetAll(on)
        on = on and true or false
        local changed = 0
        local all = type(page.ns) == "table" and type(page.ns.settingObjects) == "table" and page.ns.settingObjects or {}
        local function Resolve(item)
            if type(item) == "table" then return item end
            local setting = page.settings[item] or all[item]
            if setting then return setting end
            for _, entry in ipairs(page.own or {}) do
                if entry.key == item then return entry.setting end
            end
        end
        for _, item in ipairs(List()) do
            local setting = Resolve(item)
            if type(setting) == "table" and type(setting.GetValue) == "function" and type(setting.SetValue) == "function" then
                local ok, current = pcall(setting.GetValue, setting)
                if ok and not Core.IsSecret(current) and type(current) == "boolean" and current ~= on then
                    if page:Try(setting.SetValue, setting, on) then changed = changed + 1 end
                end
            end
        end
        return changed
    end
    local L = Core.L
    local label = type(opts.label) == "string" and opts.label or ""
    local shownLabel = label ~= "" and label or " "   -- "" setzte den Knopf an den linken Rand (s. u.)
    -- Suchmarken: beide Zeilen über die Beschriftung der Gruppe und ihren Knopftext – Blizzards Suche zeigt sonst nur
    -- „Alle auswählen“ (Spielbefund vom 23.11.2026, Suche „Tooltip“: „Alle abwählen“ fehlte), nie das Leerzeichen
    local onText, offText = opts.onText or Core.Style.AllText(true), opts.offText or Core.Style.AllText(false)
    -- ohne Beschriftung der Gruppe keine Marken: ein „Alle abwählen“ ohne Zusammenhang hilft in der Suche nicht
    local function Tags(text)
        if label ~= "" then return { label, text } end
        return nil
    end
    local onRow, offRow
    if opts.on ~= false then
        onRow = self:Button(shownLabel, onText, function() SetAll(true) end,
            opts.onTip or opts.tip or L.ALL_CHECK_TIP, { shown = opts.shown, searchTags = Tags(onText), search = label ~= "" })
    end
    -- Beschriftung der zweiten Zeile ein Leerzeichen statt "": Blizzards Vorlage setzt den Knopf einer Zeile ohne
    -- Beschriftung an den linken Rand (SettingsButtonControlMixin:Init, name == ""), mit Text steht er in der Spalte
    -- unter „Alle auswählen“ (Spielbefund vom 23.11.2026: „Alle abwählen“ allein links).
    if opts.off ~= false then
        offRow = self:Button(onRow and " " or shownLabel, offText, function() SetAll(false) end,
            opts.offTip or opts.tip or L.ALL_UNCHECK_TIP, { shown = opts.shown, searchTags = Tags(offText), search = label ~= "" })
    end
    return onRow, offRow, SetAll
end

-- Abschnitt „Profile“ einer Einstellungsseite aus ezCores Profil-Gerüst (P = Core.NewProfiles(…)); vorher bauten ihn
-- ezPanel (Options.lua) und ezBars (Options.lua) je selbst. Überschrift, Auswahl „Profil dieses Charakters“, Kästchen
-- „für die Klasse“ (scopes.class) und „je Spezialisierung“ (scopes.spec, wenn der Client Spezialisierungen kennt),
-- Knöpfe Neu, Exportieren, Importieren, Löschen. Die Steuerelemente sind keine Einstellungen von ns.S; nach jedem
-- Wechsel (P.OnChange) ziehen sie nach. opts = { header, headerTip, texts = { OPT_profile = …, … } (eigene Texte mit
-- denselben Schlüsseln), class = false, spec = false (Kästchen weglassen) } → Tabelle { settings, Refresh } oder nil.
function Page:Profiles(P, opts)
    if type(P) ~= "table" or type(P.Active) ~= "function" then return nil end
    opts = opts or {}
    local page = self
    -- Eigene Texte zuerst, sonst ezCores. Die Tabelle des Aufrufers bleibt unberührt: eine Text-Tabelle aus
    -- Core.NewLocale holt ihre Texte erst beim Zugriff über ihre eigene Metatabelle (Fund der Gegenprüfung).
    local texts = type(opts.texts) == "table" and opts.texts or nil
    local T = setmetatable({}, { __index = function(_, key)
        local value = texts and texts[key]
        if value == nil or value == key then value = Core.L[key] end   -- NewLocale liefert für Fehlendes den Schlüssel
        return value
    end })
    local state, controls, syncing = {}, {}, false
    local function Sync()
        state.profile = P.Active()
        state.profileClass = P.ForClass and P.ForClass() == true or false
        state.profileSpec = P.SpecMode and P.SpecMode() == true or false
    end
    local function Refresh()
        if syncing then return end
        syncing = true
        Sync()
        for key, setting in pairs(controls) do pcall(setting.SetValue, setting, state[key]) end
        syncing = false
    end
    self:Header(opts.header or T.PROFILE_SECTION, opts.headerTip or T.PROFILE_SECTION_TIP)
    Sync()
    local create = Settings.CreateDropdown or Settings.CreateDropDown
    if create and Settings.CreateControlTextContainer then
        self:Try(function()
            local setting = page:Setting("profile", Settings.VarType.String, state, T.OPT_profile, P.Active(),
                page.prefix .. "profile")
            setting:SetValueChangedCallback(function(_, value)
                if syncing then return end
                if P.perChar then P.Use(value or state.profile) else P.Switch(value or state.profile) end
            end)
            create(page.category, setting, function()
                local container = Settings.CreateControlTextContainer()
                for _, name in ipairs(P.Names()) do container:Add(name, P.Label(name)) end
                return container:GetData()
            end, T.OPT_profile_TIP)
            controls.profile = setting
        end)
    end
    if opts.class ~= false and P.SetForClass and P.ClassLabel and type(P.scopes) == "table" and P.scopes.class then
        self:Try(function()
            local setting = page:Setting("profileClass", Settings.VarType.Boolean, state,
                T.OPT_profileClass:format(P.ClassLabel()), false, page.prefix .. "profileClass")
            setting:SetValueChangedCallback(function(_, value)
                if syncing then return end
                if value == nil then value = state.profileClass end
                if not P.SetForClass(value == true) then Refresh() end
            end)
            Settings.CreateCheckbox(page.category, setting, T.OPT_profileClass_TIP)
            controls.profileClass = setting
        end)
    end
    if opts.spec ~= false and P.SetSpecMode and P.SpecGroup and P.SpecGroup() then
        self:Try(function()
            local setting = page:Setting("profileSpec", Settings.VarType.Boolean, state, T.OPT_profileSpec, false,
                page.prefix .. "profileSpec")
            setting:SetValueChangedCallback(function(_, value)
                if syncing then return end
                if value == nil then value = state.profileSpec end
                P.SetSpecMode(value == true)
            end)
            Settings.CreateCheckbox(page.category, setting, T.OPT_profileSpec_TIP)
            controls.profileSpec = setting
        end)
    end
    self:Button(T.OPT_PROFILE_NEW, T.OPT_PROFILE_NEW_BUTTON, function() P.AskNew() end, T.OPT_PROFILE_NEW_TIP)
    self:Button(T.OPT_PROFILE_EXPORT, T.OPT_PROFILE_EXPORT_BUTTON, function() P.ShowExport() end, T.OPT_PROFILE_EXPORT_TIP)
    self:Button(T.OPT_PROFILE_IMPORT, T.OPT_PROFILE_IMPORT_BUTTON, function() P.ShowImport() end, T.OPT_PROFILE_IMPORT_TIP)
    self:Button(T.OPT_PROFILE_DELETE, T.OPT_PROFILE_DELETE_BUTTON, function() P.AskDeleteActive() end, T.OPT_PROFILE_DELETE_TIP)
    if P.OnChange then P.OnChange(Refresh) end
    return { settings = controls, Refresh = Refresh }
end

-- Knöpfe für ezCore.Mover: zeigen bzw. zurücksetzen alle angemeldeten Teile dieses Moduls.
function Page:MoverButton()
    local page = self
    -- EC-12 (Frage 32): mit Testschalter öffnet Mover.Open Blizzards Bearbeitungsmodus, sonst den eigenen Modus
    self:Button(Core.L.MOVER_BUTTON_LABEL, Core.L.MOVER_BUTTON, function()
        if Core.Mover then (Core.Mover.Open or Core.Mover.Unlock)(page.owner, page) end
    end, Core.L.MOVER_BUTTON_TIP, { protected = true })
end

function Page:MoverResetButton()
    local owner = self.owner
    self:Button(Core.L.MOVER_RESET_LABEL, Core.L.MOVER_RESET_BUTTON, function()
        if not Core.Mover then return end
        Core.Confirm(Core.L.MOVER_RESET_CONFIRM:format(owner), function()
            Core.Print(Core.name, Core.L.MOVER_RESET_DONE:format(Core.Mover.ResetAll(owner)))
        end)
    end, Core.L.MOVER_RESET_TIP:format(owner))
end

-- Rückfrage, dann ResetToDefaults und opts.onReset – für den Knopf und für „/x zuruecksetzen“ (Core.SlashReset), damit
-- beide gleich fragen und gleich nacharbeiten (Gegenprüfung D1: ezBars wendet nach dem Zurücksetzen die Leisten neu an).
-- Die Angaben merkt sich die Seite bei page:ResetButton (page.resetOpts).
function Page:AskReset()
    local page, owner = self, self.owner
    local opts = type(self.resetOpts) == "table" and self.resetOpts or {}
    return Core.Confirm(opts.ask or Core.L.RESET_SETTINGS_ASK:format(owner), function()
        page:ResetToDefaults()
        if opts.onReset then page:Try(opts.onReset) end
        Core.Print(owner, Core.L.RESET_SETTINGS_DONE)
    end)
end

-- Knopf „Einstellungen zurücksetzen“ unter „Erweitert“ (vorher in elf Modulen gebaut): Rückfrage, dann
-- ResetToDefaults; gespeicherte Daten bleiben. opts.onReset() danach, opts.tip/opts.ask eigene Texte,
-- opts.label/opts.button eigene Beschriftung (die Seite „ezCollection“ nennt ihren Knopf anders).
function Page:ResetButton(opts)
    opts = opts or {}
    local page, owner = self, self.owner
    self.resetOpts = opts
    return self:Button(opts.label or Core.L.RESET_SETTINGS_LABEL, opts.button or Core.L.RESET_SETTINGS_BUTTON, function()
        page:AskReset()
    end, opts.tip or Core.L.RESET_SETTINGS_TIP:format(owner))
end

-- Abschnitt „Ergänzende Addons“ (unter „Erweitert“): je Addon ein Knopf, der den CurseForge-Link zum Kopieren zeigt.
function Page:Companions()
    local page = self
    return self:Try(function() return Core.AddCompanionButtons(page.layout, page.owner, page.category) end)
end

-- Knopf „Status“ (unter „Erweitert“): schreibt den Stand des Moduls in den Chat – der sichtbare Weg zu
-- ns.PrintStatus (Leitlinie 3; der Befehl „/<modul> status“ bleibt zusätzlich).
function Page:StatusButton(tip)
    local mns = self.ns
    self:Button(Core.L.MODULE_STATUS_LABEL, Core.L.MODULE_STATUS_BUTTON, function()
        if type(mns.PrintStatus) == "function" then mns.PrintStatus() end
    end, tip or Core.L.MODULE_STATUS_TIP)
end

-- Knopf „Erklärung erneut zeigen“ (unter „Erweitert“): setzt einen Rundgang (Core.NewTour) zurück.

function Page:TourButton(tour, tip)
    local owner = self.owner
    self:Button(Core.L.TOUR_LABEL, Core.L.TOUR_BUTTON, function()
        if tour and tour.Reset then tour:Reset() end
        Core.Print(owner, Core.L.TOUR_RESET_DONE)
    end, tip or Core.L.TOUR_TIP)
end

function Page:Sub(title)
    if not Settings.RegisterVerticalLayoutSubcategory then return nil end
    local sub = setmetatable({}, Page)
    for k, v in pairs(self) do sub[k] = v end
    sub.category, sub.layout = Settings.RegisterVerticalLayoutSubcategory(self.category, title)
    if not sub.layout and SettingsPanel and SettingsPanel.GetLayout then sub.layout = SettingsPanel:GetLayout(sub.category) end
    OwnCategory(sub.category, sub.layout)
    sub.settings = {}
    -- eigene Zeilen-Merker; ein Oberschalter der Modulseite bleibt auffindbar (opts.parent = key) – auch einer, den die
    -- Modulseite erst nach page:Sub anlegt: ihre Merker entstehen hier, damit __index auf dieselbe Tabelle zeigt
    -- (Gegenprüfung 19.11.2026; vorher zeigte __index auf eine leere Ersatztabelle)
    self.rows = self.rows or {}
    self.rowSettings = self.rowSettings or {}
    sub.rows = setmetatable({}, { __index = self.rows })
    sub.rowSettings = setmetatable({}, { __index = self.rowSettings })
    sub.own, sub.isParent = nil, nil
    -- Wie jede Seite: zuerst „Allgemein“ (Leitlinie 7; Spieltest 14.11.2026: ezPanel „Bausteine“ begann ohne), darunter
    -- der sichtbare Weg zurück zur Modulseite (Blizzards Liste links zeigt Unterseiten nur eingerückt).
    sub:Header(Core.L.SETTINGS_GENERAL)
    local parentPage = self
    local back = self.title or self.owner
    sub:Button(Core.L.SETTINGS_BACK_TO:format(back), Core.L.SETTINGS_BACK_BUTTON,
        function() parentPage:Open() end, Core.L.SETTINGS_BACK_TO_TIP:format(back))
    return sub
end

-- Überschrift „Erweitert“: der letzte Abschnitt jeder Seite.
function Page:Advanced(tooltip)
    self:Header(Core.L.SETTINGS_ADVANCED, tooltip or Core.L.SETTINGS_ADVANCED_TIP)
    -- Seite „ezCollection“: Gesamtschalter OPT_optInHints und „Hinweise erneut zeigen“ des Hinweis-Helfers
    -- (Kern/OptInHint.lua, Welle 28) – hier, damit sie unter „Erweitert“ stehen, ohne die Übersicht umzubauen; nur
    -- einmal je Seite (Merker optInAdded; Fund des code-reviewers zu Welle 28: ein zweiter Aufruf von Advanced hätte
    -- Kästchen und Knopf doppelt angemeldet)
    if self.isParent and not self.optInAdded and Core.OptInHint and Core.OptInHint.AddSettings then
        self.optInAdded = true
        self:Try(Core.OptInHint.AddSettings, self)
    end
end

function Page:Register()
    if self.registered then return end
    self.registered = true
    if self.standalone then
        Settings.RegisterAddOnCategory(self.category)
    end
    self.ns.SettingsRegistered = true
end

function Page:Open()
    return Core.OpenSettingsCategory(self.category, self.owner)
end

---------------------------------------------------------------------------
-- Einstellungsseiten im Kampf (ST-04, entschieden 13.11.2026; EC-64): nicht öffnen, sondern ein Hinweis im Chat und
-- nach dem Kampf nachholen – ein Schlüssel, der letzte Wunsch gewinnt. Gilt für alle Wege (Slash-Befehle,
-- Minikarten-Knopf, Addon-Fach, Knöpfe „Einstellungen“), weil sie alle hier enden (Page:Open, Core.OpenSettings,
-- Core.OpenModuleSettings, Core.OpenPanel("settings", Kategorie-Tabelle) in Panels.lua). Ist eine Seite beim Kampfbeginn schon offen, fasst ezCore Blizzards Fenster nicht an.
--   Core.OpenSettingsCategory(kategorie, owner, after) → true (offen) | false (Kampf: vorgemerkt; ohne Kategorie)
--     after: fn() nach dem Öffnen (auch beim Nachholen), z. B. der Rundgang des ersten Starts
--   Core.SettingsDeferred() → true, solange ein Öffnen auf das Kampfende wartet
--   Core.OpenedOrDeferred(open) → true, wenn open() geöffnet hat oder genau dieser Aufruf im Kampf vorgemerkt hat
--     (für Slash-Befehle: sonst Hilfe bzw. „Modul aus“ – eine ältere Vormerkung zählt nicht)
---------------------------------------------------------------------------

Core.SETTINGS_AFTER_COMBAT = "ezCore.openSettings"
local deferCount = 0   -- zählt jedes Vormerken, damit ein Aufrufer sein eigenes erkennt

-- Ging Blizzards Fenster nicht auf (Spielbefund vom 22.11.2026: „Einstellungen“ in ezMacro öffnete nichts), nennt ein
-- Hinweis im Chat den Weg über Blizzards Menü (Leitlinie 3). Blizzard öffnet über C_SettingsUtil.OpenSettingsPanel und
-- das Ereignis SETTINGS_PANEL_OPEN (Forever-Quelle, Blizzard_Settings.lua und Blizzard_SettingsPanel.lua), also erst
-- danach – geprüft wird nach Core.SETTINGS_CHECK_DELAY Sekunden, nur für den letzten Wunsch (Doppelklick: ein Hinweis).
-- Ging das Fenster seit dem Wunsch einmal auf (OnShow, per HookScript gemerkt), gilt es als geöffnet – auch wenn der
-- Spieler es schon wieder geschlossen hat. Eigene Seiten nennen den Weg über „AddOns“, Blizzards Seiten (etwa aus
-- ezQuest nach dem Kampf nachgeholt) ohne.
--   Core.SettingsPath(kategorie) → „ezCollection » ezMacro“ (Name der Seite samt Oberseiten)
--   Core.IsOwnSettingsCategory(kategorie) → true, wenn die Seite oder eine Oberseite der ezCollection gehört
--   Core.CheckSettingsOpened(kategorie, owner, seit) → true (offen bzw. seit Core.Uptime() = seit aufgegangen) |
--                                                       false (Hinweis gezeigt) | nil (nicht prüfbar)
Core.SETTINGS_CHECK_DELAY = 0.5
local checkSeq, lastShown, watchedPanel = 0, nil, nil

-- Merkt, wann Blizzards Einstellungsfenster zuletzt aufging (HookScript, taint-sicher; einmal je Fenster).
local function WatchSettingsPanel()
    local panel = rawget(_G, "SettingsPanel")
    if panel == watchedPanel or type(panel) ~= "table" or type(panel.HookScript) ~= "function" then return end
    if pcall(panel.HookScript, panel, "OnShow", function() lastShown = Core.Uptime() end) then watchedPanel = panel end
end

function Core.IsOwnSettingsCategory(category)
    local depth = 0
    while type(category) == "table" and depth < 4 do
        depth = depth + 1
        if ownCategories[category] or category == parent then return true end
        local up = Core.Call(category.GetParentCategory, category)
        if up == nil then up = rawget(category, "parentCategory") end
        category = up
    end
    return false
end

function Core.SettingsPath(category)
    local names, depth = {}, 0
    while type(category) == "table" and depth < 4 do
        depth = depth + 1
        local name = Core.Call(category.GetName, category)
        if type(name) == "string" and name ~= "" and not Core.IsSecret(name) then table.insert(names, 1, name) end
        local up = Core.Call(category.GetParentCategory, category)
        if up == nil then up = rawget(category, "parentCategory") end
        category = up
    end
    if #names == 0 then names[1] = Core.TITLE end
    return table.concat(names, " » ")
end

function Core.CheckSettingsOpened(category, owner, since)
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) ~= "table" or type(panel.IsShown) ~= "function" then return nil end
    if Core.Call(panel.IsShown, panel) then return true end
    if since and lastShown and lastShown >= since then return true end
    local text = Core.IsOwnSettingsCategory(category) and Core.L.SETTINGS_NOT_OPENED or Core.L.SETTINGS_NOT_OPENED_BLIZZ
    Core.Print(owner or Core.TITLE, text:format(Core.SettingsPath(category)))
    return false
end

local function OpenNow(category, owner, after)
    if not (category and Settings and Settings.OpenToCategory and category.GetID) then return false end
    WatchSettingsPanel()
    checkSeq = checkSeq + 1
    local seq, since = checkSeq, Core.Uptime()
    Settings.OpenToCategory(category:GetID())
    C_Timer.After(Core.SETTINGS_CHECK_DELAY, function()
        if seq == checkSeq then Core.CheckSettingsOpened(category, owner, since) end
    end)
    if type(after) == "function" then Core.Try(owner, "OpenSettings after", after) end
    return true
end

function Core.OpenSettingsCategory(category, owner, after)
    if not (category and Settings and Settings.OpenToCategory and category.GetID) then return false end
    if Core.InCombat() then
        if not Core.SettingsDeferred() then Core.CombatNotice(owner or Core.name, Core.L.SETTINGS_PAGE_WHAT, "later") end
        Core.AfterCombat(function() OpenNow(category, owner, after) end, Core.SETTINGS_AFTER_COMBAT, owner)
        deferCount = deferCount + 1
        return false
    end
    Core.CancelAfterCombat(Core.SETTINGS_AFTER_COMBAT)
    return OpenNow(category, owner, after)
end

function Core.SettingsDeferred()
    return Core.AfterCombatWaiting(Core.SETTINGS_AFTER_COMBAT) == true
end

function Core.OpenedOrDeferred(open)
    local before = deferCount
    local opened = type(open) == "function" and open() == true
    return opened or deferCount ~= before
end

-- Setzt alle Einstellungen dieser Seite auf ihren Standard (über die Setting-Objekte, damit offene
-- Steuerelemente sofort den neuen Wert zeigen). Die gemeinsamen Schalter des Moduls (mns.SHARED) gehen auf ezCores
-- Standard – sie stehen nicht mehr in mns.DEFAULTS (Gegenprüfung 19.11.2026: sonst blieb z. B. „Automatisch
-- reparieren“ nach „Einstellungen zurücksetzen“ an); das gilt dann für alle Module, die den Schalter lesen.
function Page:ResetToDefaults()
    local mns = self.ns
    if self.own then self:ResetOwn() end
    Core.ResetModuleShared(mns)
    for key, value in pairs(type(mns.DEFAULTS) == "table" and mns.DEFAULTS or {}) do
        local setting = self.settings[key]
        if setting then
            if not pcall(setting.SetValue, setting, value) then mns.SetSetting(key, value) end
        elseif mns.S[key] ~= value then
            mns.SetSetting(key, value)
        end
    end
end

-- Die Elternseite „ezCollection“ als Page-Objekt (V-018): dieselben Helfer wie auf jeder Modulseite (Header, Button,
-- OwnCheckbox, Sub …). Eines für alle; nil ohne Blizzards Einstellungs-API.
local parentPage
function Core.ParentPage()
    if parentPage then return parentPage end
    local cat, layout = Core.SettingsParent()
    if not cat then return nil end
    parentPage = setmetatable({ ns = Core.ns, L = Core.L, owner = Core.name, title = Core.TITLE, prefix = "ezCore_",
        settings = {}, own = {}, isParent = true, category = cat, layout = layout }, Page)
    return parentPage
end

-- Alle eigenen Schalter von ezCore auf Standard (Knopf „Einstellungen zurücksetzen“ der Seite „ezCollection“).
function Core.ResetOwnSettings()
    local page = Core.ParentPage()
    local changed = page and page:ResetOwn() or 0
    -- Schalter ohne Kästchen (z. B. weil die CVar fehlt): direkt im Speicher
    for group, defaults in pairs(Core.DEFAULTS) do
        local tbl = Core.OwnSettings(group)
        for key, value in pairs(tbl and defaults or {}) do
            if tbl[key] ~= value then tbl[key], changed = value, changed + 1 end
        end
    end
    return changed
end

-- Neue Seite für ein Modul. opts.title (Standard: Modulname), opts.prefix (Standard: "<Modul>_").
function Core.NewSettingsPage(mns, opts)
    if not SettingsAvailable() then return nil end
    opts = opts or {}
    local owner = opts.owner or mns.moduleName or Core.name
    local title = opts.title or owner
    local page = setmetatable({ ns = mns, L = mns.L, owner = owner, prefix = opts.prefix or (owner .. "_"), settings = {} }, Page)
    local cat = Core.SettingsParent()
    if cat and Settings.RegisterVerticalLayoutSubcategory then
        page.category, page.layout = Settings.RegisterVerticalLayoutSubcategory(cat, title)
    else
        page.category, page.layout = Settings.RegisterVerticalLayoutCategory(title)
        page.standalone = true
    end
    if not page.layout and SettingsPanel and SettingsPanel.GetLayout then page.layout = SettingsPanel:GetLayout(page.category) end
    OwnCategory(page.category, page.layout)
    if type(mns) == "table" and mns.settingsPage == nil then mns.settingsPage = page end
    -- Abschnitt „Allgemein“ mit dem Weg zurück zur Übersicht, auf jeder Modulseite gleich und an derselben Stelle.
    page:Header(Core.L.SETTINGS_GENERAL)
    if not page.standalone then
        page:Button(Core.L.SETTINGS_BACK, Core.L.SETTINGS_BACK_BUTTON, function() Core.OpenSettings() end, Core.L.SETTINGS_BACK_TIP)
    end
    -- Einführung (W-1811-Einfuehrung): Knopf „Einführung“ unter „Allgemein“ jeder Modulseite, die ezCore einen
    -- Einführungstext hat (INTRO_MOD_<Modul>, Werkzeuge/FirstStart.lua) – eine Stelle für alle Module, kein Modul baut ihn
    local intro = Core.Intro
    if type(intro) == "table" and type(intro.HasPage) == "function" and intro.HasPage(owner) then
        page:Button(Core.L.INTRO_PAGE_LABEL, Core.L.INTRO_PAGE_BUTTON, function() intro.ShowModule(owner) end, intro.PageTip(owner))
    end
    return page
end
