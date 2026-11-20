local _, ns = ...
local L = ns.L

--[[
    Bausteine.

    Ein Baustein wird mit ns.RegisterBlock(def) angemeldet. Felder:
      id, name, icon, label        Kennung, Name (Menüs/Tooltip), Symbol, Beschriftung auf der Leiste
      command                      deutsches Wort für /ep <wort>
      defaults                     eigene Optionen + enabled/bar/zone/order
      events                       Ereignisse, nach denen der Text neu berechnet wird
      interval                     Sekunden für regelmäßige Aktualisierung (nur solange aktiv)
      colorable                    Menüpunkt „Werte einfärben“ anbieten
      hints                        Hinweiszeilen im Tooltip (Tabelle oder Funktion)
      actions                      Klick-Aktionen als Menüeinträge: Liste { { text = …, fn = function(def) … end } }
                                   oder Funktion(def) → Liste. Alles, was nur per (Umschalt-)Klick erreichbar wäre,
                                   steht so auch im Menü des Bausteins (Leitlinie 3).
    Methoden (alle optional außer GetText):
      def:GetText()                Text auf der Leiste; nil blendet den Baustein vorübergehend aus.
                                   Zweiter Rückgabewert: anderes Symbol.
      def:OnTooltip(tooltip)       Tooltip füllen (Titel steht schon drin)
      def:OnClick(button)          Links-/Mittelklick (Rechtsklick öffnet das Menü)
      def:OnMenu(root)             eigene Einträge im Rechtsklick-Menü (ezCore.Menu, Blizzards MenuUtil)
      def:OnWheel(delta)           Mausrad
      def:OnEnable() / OnDisable()
      def:OnConfigChanged()        die Optionen des Bausteins wurden von außen ersetzt (Profilwechsel) und er bleibt
                                   an: Wirkungen außerhalb der Leiste nachziehen (Abfragen, Minikarte, Weltkarte)
      def:Warnings()               Warnungen als Liste von Texten für den Baustein „Meldungen“
                                   (läuft auch, wenn der Baustein selbst aus ist)
      def:Alert()                  eigene Warnung des Bausteins (ErrorMessage, Chat) prüfen; läuft auch bei
                                   verborgener Leiste, wenn GetText nicht läuft (Taschen voll, Munition knapp)
    Jeder Baustein lässt sich nach Lage ausblenden (cfg.hideIn: combat, instance, city, group),
    Menüpunkt „Ausblenden …“.
]]

ns.blocks = {}
ns.blockList = {}

local COMMON = { enabled = false, zone = "left", order = 500, icon = true, label = true, colored = true, hideIn = {} }
local REFRESH = MenuResponse and MenuResponse.Refresh

--[[
    Optionen eines Bausteins aus einem fremden Text (Profil-Import, Gesamtreview 18.11.2026, T6-7; vorher übernahm der
    Import jede Tabelle unter jedem Namen und kopierte sie dauerhaft nach ezPanelDB.blocks):
      ns.CleanBlockConfig(id, cfg) → neue Tabelle oder nil (keine Tabelle)
        - angemeldeter Baustein: nur Schlüssel aus seinen defaults und COMMON, Typ wie der Standard
        - noch nicht angemeldeter (LDB-Anzeige, Baustein eines anderen Moduls über API.lua): COMMON-Schlüssel wie oben,
          sonst einfache Werte (Core.CleanScalar), höchstens BLOCK_MAX_KEYS Schlüssel
        - Werte, die Tabellen sind (eigene Befehle, ausgeblendete Charaktere, hideIn), nur flach: Schlüssel und Werte
          einfach, höchstens Core.IMPORT_LIST_MAX Einträge (Core.CleanFlatTable)
      ns.BLOCK_MAX_UNKNOWN   höchstens so viele noch nicht angemeldete Bausteine nimmt ein Import mit (Profiles.Clean)
]]
ns.BLOCK_COMMON = COMMON
ns.BLOCK_MAX_KEYS = 64
ns.BLOCK_MAX_UNKNOWN = 64
ns.BLOCK_MAX_ID = 100

function ns.CleanBlockConfig(id, src)
    if type(src) ~= "table" or ezCore.IsSecret(src) then return nil end
    local def = type(id) == "string" and ns.blocks[id] or nil
    local defaults = def and type(def.defaults) == "table" and def.defaults or nil
    local out, n = {}, 0
    for _, key in ipairs(ezCore.SortedKeys(src)) do
        if n >= ns.BLOCK_MAX_KEYS then break end
        if type(key) == "string" and #key <= ns.BLOCK_MAX_ID then
            local value, default = src[key], COMMON[key]
            if defaults and defaults[key] ~= nil then default = defaults[key] end
            local clean
            if def and default == nil then
                clean = nil                                    -- angemeldeter Baustein: kennt den Schlüssel nicht
            elseif type(value) == "table" then
                if default == nil or type(default) == "table" then clean = ezCore.CleanFlatTable(value) end
            else
                clean = ezCore.CleanScalar(value)
                if clean ~= nil and default ~= nil and type(clean) ~= type(default) then clean = nil end
            end
            if clean ~= nil then
                out[key], n = clean, n + 1
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Anmelden und Einstellungen
---------------------------------------------------------------------------

local Activate, Deactivate

---------------------------------------------------------------------------
-- Fehler der Bausteine: eine Stelle für alle Rückrufe (eigene und fremde Bausteine, Quellen von AddWarning)
---------------------------------------------------------------------------

--[[
    Jeder abgefangene Fehler eines Bausteins geht über ns.BlockError → ns.Error in ezCores Fehlerliste
    (/ez fehler, Zähler im Werkzeug-Baustein). ezCore zählt gleiche Meldungen an einem Eintrag und gibt nur die
    erste an Blizzards Fehleranzeige – ein Baustein mit interval = 1 flutet sie also nicht.
    Ein fremder Baustein (def.external, API.lua) und eine Quelle von AddWarning halten nach einem Fehler in GetText
    oder Warnings an: ezPanel ruft beides nicht mehr auf, die Leiste zeigt „?“, der Tooltip sagt warum, das Menü
    hat „Wieder starten“ (ns.RestartBlock); ebenso startet Aus- und wieder Einschalten oder eine neue Anmeldung.
]]
ns.HALTING = { GetText = true, Warnings = true }

function ns.BlockError(def, err, where)
    where = tostring(where or "?")
    local label = where .. " " .. tostring(def and (def.key or def.id) or "?")
    if def and type(def.external) == "string" then label = label .. " (" .. def.external .. ")" end
    ns.Error(err, label)
    if def and def.external and ns.HALTING[where] and not def.halted then
        def.halted = true
        ns.QueueUpdate(def)
        if ns.blocks.alerts then ns.QueueUpdate(ns.blocks.alerts) end
    end
end

-- Angehaltenen Baustein (oder eine Quelle von AddWarning) wieder aufrufen. → true, wenn er angehalten war.
function ns.RestartBlock(def)
    if type(def) == "string" then def = ns.blocks[def] end
    if type(def) ~= "table" or not def.halted then return false end
    def.halted = nil
    ns.QueueUpdate(def)
    if ns.blocks.alerts then ns.QueueUpdate(ns.blocks.alerts) end
    return true
end

function ns.InitBlock(def)
    local cfg = ns.db.blocks[def.id] or {}
    ns.db.blocks[def.id] = cfg
    ns.FillDefaults(cfg, def.defaults)
    ns.FillDefaults(cfg, COMMON)
    cfg.bar = nil   -- früher: obere/untere Leiste; es gibt nur noch die obere
    def.cfg = cfg
    for _, event in ipairs(def.events or {}) do
        ns.On(event, function() ns.QueueUpdate(def) end)
    end
    if def.OnInit then
        local ok, err = pcall(def.OnInit, def)
        if not ok then ns.BlockError(def, err, "OnInit") end
    end
end

function ns.RegisterBlock(def)
    assert(type(def.id) == "string" and not ns.blocks[def.id], "ezPanel: invalid or duplicate block id")
    def.defaults = def.defaults or {}
    def.name = def.name or def.id
    def.index = #ns.blockList + 1
    ns.blocks[def.id] = def
    ns.blockList[def.index] = def
    -- Später angemeldete Bausteine (z. B. LDB-Anzeigen anderer Addons) sofort einrichten.
    if ns.ready then
        ns.InitBlock(def)
        if def.cfg.enabled then Activate(def) end
        ns.RequestLayout()
    end
    return def
end

function ns.BlockEnabled(id)
    local def = ns.blocks[id]
    return def ~= nil and def.cfg ~= nil and def.cfg.enabled == true
end

function ns.SetBlockEnabled(id, on)
    local def = ns.blocks[id]
    if not def or not def.cfg then return end
    on = on and true or false
    if on then def.halted = nil end   -- Einschalten startet einen angehaltenen Baustein neu
    def.cfg.enabled = on
    if on then Activate(def) else Deactivate(def) end
    ns.RequestLayout()
    if ns.RefreshBlockSetting then ns.RefreshBlockSetting(id) end
end

---------------------------------------------------------------------------
-- Aktualisieren (gesammelt im nächsten Frame)
---------------------------------------------------------------------------

local dirty = {}
local layoutPending = false
local Refresh, DoLayout

local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function(self)
    self:Hide()
    local list = dirty
    dirty = {}
    for def in pairs(list) do Refresh(def) end
    if layoutPending then
        layoutPending = false
        DoLayout()
    end
end)

-- Verborgene Leiste (aus, „im Kampf ausblenden“, Auto-Hide, Haustierkampf): die Takte der Bausteine rechnen und
-- zeichnen nicht für einen unsichtbaren Rahmen (Gesamtreview 18.11.2026, T8-6). Der Baustein wird vorgemerkt und beim
-- Einblenden einmal aufgefrischt (ns.FlushHiddenUpdates aus ns.UpdateBarVisibility).
-- Eigene Warnungen (def:Alert, „Taschen voll“, „Munition knapp“) laufen trotzdem sofort – sie gehören nicht zur
-- Zeichnung und kämen sonst erst beim Aufdecken oder gar nicht (Gegenprüfung P19b).
local held = {}

local function BarHidden(def)
    local bar = def.frame.ezBar
    return type(bar) == "table" and type(bar.IsShown) == "function" and not bar:IsShown()
end

function ns.QueueUpdate(def)
    if type(def) == "string" then def = ns.blocks[def] end
    if not def or not def.frame or not def.cfg or not def.cfg.enabled then return end
    if BarHidden(def) then
        held[def] = true
        if def.Alert and not def.halted then
            local ok, err = pcall(def.Alert, def)
            if not ok then ns.BlockError(def, err, "Alert") end
        end
        return
    end
    dirty[def] = true
    updater:Show()
end
ns.UpdateBlock = ns.QueueUpdate

-- Die Leiste ist wieder zu sehen: vorgemerkte Bausteine einmal auffrischen. → Anzahl
function ns.FlushHiddenUpdates()
    local list, n = held, 0
    held = {}
    for def in pairs(list) do
        n = n + 1
        ns.QueueUpdate(def)
    end
    return n
end

function ns.UpdateAllBlocks()
    for _, def in ipairs(ns.blockList) do ns.QueueUpdate(def) end
end

function ns.RequestLayout()
    if not ns.ready then return end
    layoutPending = true
    updater:Show()
end

---------------------------------------------------------------------------
-- Nach Lage ausblenden (Kampf, Instanz, Stadt, Gruppe)
---------------------------------------------------------------------------

ns.SITUATIONS = { "combat", "instance", "city", "group" }

function ns.InSituation(kind)
    if kind == "combat" then
        return ns.InCombat()
    elseif kind == "instance" then
        return ezCore.InInstance() == true   -- gesperrt oder unbekannt: nicht in einer Instanz
    elseif kind == "city" then
        -- Städte und Gasthäuser: dort erholt sich der Charakter (Blizzards „Erholung“).
        return type(IsResting) == "function" and IsResting() == true
    elseif kind == "group" then
        return type(IsInGroup) == "function" and IsInGroup() == true
    end
    return false
end

local function HiddenBySituation(def)
    local hide = def.cfg.hideIn
    if type(hide) ~= "table" then return false end
    for _, kind in ipairs(ns.SITUATIONS) do
        if hide[kind] and ns.InSituation(kind) then return true end
    end
    return false
end

local function UpdateSituational()
    if not ns.ready then return end
    for _, def in ipairs(ns.blockList) do
        if def.cfg and type(def.cfg.hideIn) == "table" and next(def.cfg.hideIn) then ns.QueueUpdate(def) end
    end
end
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    ns.On(event, UpdateSituational)
end

---------------------------------------------------------------------------
-- Darstellung eines Bausteins
---------------------------------------------------------------------------

function ns.IconSize()
    return ns.Px(14)
end

-- Größe und Abstände folgen der Schriftgröße (ns.Px).
local function Resize(b)
    local size, inset, gap = ns.IconSize(), ns.Px(2), ns.Px(3)
    b.icon:SetSize(size, size)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "LEFT", inset, 0)
    b:SetHeight(ns.BarHeight())
    local hasText = (b.text:GetText() or "") ~= ""
    b.text:ClearAllPoints()
    if b.icon:IsShown() then
        b.text:SetPoint("LEFT", b.icon, "RIGHT", gap, 0)
    else
        b.text:SetPoint("LEFT", b, "LEFT", inset, 0)
    end
    local width = 2 * inset
    if b.icon:IsShown() then width = width + size + (hasText and gap or 0) end
    if hasText then
        local tw = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()
        width = width + tw
    end
    width = math.ceil(width)
    if b.width ~= width then
        b.width = width
        b:SetWidth(width)
        if b.zone == "center" then ns.RequestLayout() end
    end
end

local ShowTooltip

Refresh = function(def)
    local b = def.frame
    if not b or not def.cfg.enabled then return end
    local ok, text, icon
    if def.halted then
        text = "?"   -- angehalten nach einem Fehler (ns.BlockError): GetText nicht mehr aufrufen
    else
        ok, text, icon = pcall(def.GetText, def)
        if not ok then
            ns.BlockError(def, text, "GetText")
            text, icon = "?", nil
        end
    end
    local visible = text ~= nil and not HiddenBySituation(def)
    if visible ~= b.visible then
        b.visible = visible
        ns.RequestLayout()
    end
    if not visible then
        b:Hide()
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        return
    end

    text = tostring(text)
    if not def.cfg.colored then text = ns.StripColors(text) end
    local label = def.label
    if type(label) == "function" then label = label(def) end
    if def.cfg.label and label and label ~= "" then
        if text ~= "" then
            text = ns.GOLD .. label .. ":|r " .. ns.WHITE .. text .. "|r"
        else
            text = ns.GOLD .. label .. "|r"
        end
    elseif text ~= "" then
        text = ns.WHITE .. text .. "|r"
    end
    b.text:SetText(text)

    local tex = icon or def.icon
    if def.cfg.icon and tex then
        -- "atlas:NAME" nutzt einen Atlas des Clients; fehlt er, gilt fallbackIcon.
        local atlas = type(tex) == "string" and tex:match("^atlas:(.+)$")
        if atlas and not ns.AtlasExists(atlas) then
            atlas, tex = nil, def.fallbackIcon
        end
        if atlas then
            b.icon:SetAtlas(atlas)
        elseif tex then
            -- Fehlt eine Textur auf diesem Client, auf ein sicheres Symbol ausweichen.
            if b.icon:SetTexture(tex) == false and def.fallbackIcon then
                tex = def.fallbackIcon
                b.icon:SetTexture(tex)
            end
            if type(tex) == "string" and tex:lower():find("^interface\\icons\\") then
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                b.icon:SetTexCoord(0, 1, 0, 1)
            end
        end
        b.icon:SetShown((atlas or tex) and true or false)
    else
        b.icon:Hide()
    end
    -- Weder Symbol noch Text: trotzdem anklickbar lassen.
    if not b.icon:IsShown() and text == "" then
        b.text:SetText(ns.GOLD .. def.name .. "|r")
    end
    Resize(b)
    -- Eigene Tooltips von LDB-Addons (OnEnter) nicht überschreiben.
    if GameTooltip:IsOwned(b) and not def.OnEnterCustom then ShowTooltip(b) end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function AddHint(tooltip, text)
    ns.TipLine(tooltip, text, "good")   -- GREEN_FONT_COLOR über ezCores Rolle (T9-6)
end

ShowTooltip = function(b)
    local def = b.def
    if not ns.S.tooltipsInCombat and ns.InCombat() then return end
    local tooltip = GameTooltip
    tooltip:SetOwner(b, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    local h = (b.zone == "left" and "LEFT") or (b.zone == "right" and "RIGHT") or ""
    tooltip:SetPoint("TOP" .. h, b, "BOTTOM" .. h, 0, -4)

    if not def.noTitle then
        ns.TipLine(tooltip, def.tooltipTitle or def.name, "highlight")
    end
    if def.halted then
        ns.TipLine(tooltip, L.BLOCK_HALTED, "bad", true)
    end
    if def.OnTooltip then
        local ok, err = pcall(def.OnTooltip, def, tooltip)
        if not ok then ns.BlockError(def, err, "OnTooltip") end
    end
    local hints = def.hints
    if type(hints) == "function" then hints = hints(def) end
    tooltip:AddLine(" ")
    for _, line in ipairs(hints or {}) do AddHint(tooltip, line) end
    -- Klick-Hinweis über ezCore (T18-9), Befehl über ns.SlashCmd (nie ein Kurzbefehl eines anderen Addons; T18-2)
    AddHint(tooltip, def.ownRightClick and ezCore.ClickText("right", "SHIFT", L.HINT_MENU_SHIFT) or L.HINT_MENU)
    -- Befehlswort der Sprache: deutsch das Wort des Bausteins, englisch die Kennung (beide schalten; T10-1)
    local word = def.command and (ezCore.IsGerman() and def.command or def.id)
    if word then AddHint(tooltip, L.HINT_COMMAND:format(ns.SlashCmd and ns.SlashCmd(word) or "/ezpanel " .. word)) end
    tooltip:Show()
end

---------------------------------------------------------------------------
-- Rechtsklick-Menü
---------------------------------------------------------------------------

function ns.MenuCheck(root, text, tbl, key, def, onChange)
    return root:CreateCheckbox(text, function() return tbl[key] and true or false end, function()
        tbl[key] = not tbl[key]
        if onChange then onChange(tbl[key]) end
        if def then ns.QueueUpdate(def) end
        return REFRESH
    end)
end

-- „Alle auswählen / Alle abwählen“ über einer Mehrfachauswahl im Menü (Design-System 2.11, Welle 22): ezCores Baustein
-- Core.Menu.AllToggle mit ezCores Wortlaut (Core.Style.AllText) und Erklärzeilen, erst ab ALL_TOGGLE_MIN Einträgen
-- derselben Art. after(anzahl) läuft einmal nach dem Klick, nur wenn sich etwas geändert hat (z. B. Baustein neu
-- zeichnen statt je Eintrag). opts.on = false: nur „Alle abwählen“. Rückgabe wie Core.Menu.AllToggle.
ns.ALL_TOGGLE_MIN = 3
function ns.MenuAllToggle(root, list, get, set, after, opts)
    opts = opts or {}
    local Menu, Style = ezCore.Menu, ezCore.Style
    if type(list) ~= "table" or #list < ns.ALL_TOGGLE_MIN or type(Menu.AllToggle) ~= "function" then return nil, nil end
    return Menu.AllToggle(root, list, get, set, {
        on = opts.on, onText = Style.AllText(true), offText = Style.AllText(false),
        onTip = ezCore.L.ALL_CHECK_TIP, offTip = ezCore.L.ALL_UNCHECK_TIP,
        after = function(changed) if changed > 0 and after then after(changed) end end,
    })
end

function ns.MenuRadio(root, text, tbl, key, value, def, onChange)
    return root:CreateRadio(text, function() return tbl[key] == value end, function()
        tbl[key] = value
        if onChange then onChange(value) end
        if def then ns.QueueUpdate(def) end
        return REFRESH
    end, value)
end

local function ZoneList(zone, except)
    local list = {}
    for _, def in ipairs(ns.blockList) do
        local b = def.frame
        if b and def.cfg.enabled and b.visible and b.ezBar and b.zone == zone and def ~= except then
            list[#list + 1] = def
        end
    end
    table.sort(list, function(a, c)
        if a.cfg.order ~= c.cfg.order then return a.cfg.order < c.cfg.order end
        return a.index < c.index
    end)
    return list
end

local function Renumber(list)
    for i, def in ipairs(list) do def.cfg.order = i * 10 end
end

function ns.MoveBlock(def, zone)
    def.cfg.zone = zone
    local list = ZoneList(zone, def)
    list[#list + 1] = def
    Renumber(list)
    ns.RequestLayout()
end

function ns.ShiftBlock(def, dir)
    local b = def.frame
    if not b or not b.ezBar then return end
    local list = ZoneList(b.zone)
    for i, entry in ipairs(list) do
        if entry == def then
            local j = i + dir
            if list[j] then
                list[i], list[j] = list[j], list[i]
                Renumber(list)
                ns.RequestLayout()
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5, Bericht Welle 20; freigegeben „zuerst V1–V5“): Bausteine geben Spalten und Zeilen,
-- die Tabelle und das Kopierfeld kommen aus ezCore (Core.CopyAsText, Welle 23d) – keine eigene Ausgabe
-- (Leitlinie 2). Spalten mit personal (Namen anderer Spieler) kommen ab Werk nicht mit; das Häkchen „Namen
-- mitnehmen“ im Kopierfeld nimmt sie auf (Frage E6, nach Empfehlung). Fehlt der Dienst (älteres ezCore), zeigen
-- die Bausteine den Menüeintrag nicht (ns.CanCopyText).
---------------------------------------------------------------------------

function ns.CanCopyText()
    return type(ezCore.CopyAsText) == "function"
end

-- opts = { title, columns, rows } → true, wenn das Kopierfeld offen ist; ohne Zeilen ein Hinweis im Chat.
function ns.CopyAsText(opts)
    if not ns.CanCopyText() then return false end
    if type(opts) ~= "table" or type(opts.rows) ~= "table" or #opts.rows == 0 then
        ns.Print(L.COPY_EMPTY)
        return false
    end
    ezCore.CopyAsText({ title = opts.title, columns = opts.columns, rows = opts.rows, owner = "ezPanel" })
    return true
end

-- Zellen: den Zeitpunkt schreiben die Spalten über Core.DateText(t, "long") (Datum mit Jahr und Uhrzeit, Spielsprache);
-- Kupfer als Gold mit vier Stellen: Weiterleitung an ezCores Core.GoldDecimal (Welle 26, eine Stelle für ezLoot, ezPanel
-- und ezAuction; die Spalten nehmen format = "money"). Gesperrt oder fehlend: nil (Leitlinie 6).
function ns.CopyGold(copper)
    return ezCore.GoldDecimal(copper)
end

-- Klick-Aktionen eines Bausteins als Liste { { text, fn } } (def.actions: Tabelle oder Funktion).
function ns.BlockActions(def)
    local actions = def.actions
    if type(actions) == "function" then
        local ok, result = pcall(actions, def)
        if not ok then
            ns.BlockError(def, result, "actions")
            return {}
        end
        actions = result
    end
    local list = {}
    for _, a in ipairs(type(actions) == "table" and actions or {}) do
        if type(a) == "table" and type(a.text) == "string" and type(a.fn) == "function" then list[#list + 1] = a end
    end
    return list
end

--[[
    Füllt das Menü eines Bausteins: Aktionen, eigene Optionen (def:OnMenu), Anzeige, Position, Ausblenden.
    Zwei Wege führen dahin: Rechtsklick auf den Baustein (ns.OpenBlockMenu) und – sichtbar, auch für Bausteine,
    die gerade nicht auf der Leiste stehen – Einstellungen → ezPanel → Bausteine → „Optionen der Bausteine“
    sowie Rechtsklick auf die Leiste (ns.FillAllBlockMenus). inList = true: Eintrag im Sammelmenü (Häkchen
    „Auf der Leiste zeigen“ statt „Baustein ausblenden“, kein Verweis auf die Einstellungen).
]]
function ns.FillBlockMenu(root, def, inList)
    if not inList then root:CreateTitle(def.name) end
    if inList then
        root:CreateCheckbox(L.MENU_SHOW_BLOCK, function() return ns.BlockEnabled(def.id) end, function()
            ns.SetBlockEnabled(def.id, not ns.BlockEnabled(def.id))
            return REFRESH
        end)
    end
    do
        if def.halted then
            -- Leitlinie 3: angehalten nach einem Fehler (ns.BlockError) – sichtbar neu starten
            root:CreateButton(L.MENU_RESTART_BLOCK, function() ns.RestartBlock(def) end)
            root:CreateDivider()
        end
        local actions = ns.BlockActions(def)
        for _, a in ipairs(actions) do
            root:CreateButton(a.text, function()
                local ok, err = pcall(a.fn, def)
                if not ok then ns.BlockError(def, err, "action") end
                ns.QueueUpdate(def)
            end)
        end
        if #actions > 0 or inList then root:CreateDivider() end
        if def.OnMenu then
            local ok, err = pcall(def.OnMenu, def, root)
            if not ok then ns.BlockError(def, err, "OnMenu") end
            root:CreateDivider()
        end

        local display = root:CreateButton(L.MENU_DISPLAY)
        ns.MenuCheck(display, L.MENU_SHOW_ICON, def.cfg, "icon", def)
        if def.label then ns.MenuCheck(display, L.MENU_SHOW_LABEL, def.cfg, "label", def) end
        if def.colorable then ns.MenuCheck(display, L.MENU_COLORED, def.cfg, "colored", def) end

        local pos = root:CreateButton(L.MENU_POSITION)
        for _, zone in ipairs(ns.ZONES) do
            pos:CreateRadio(L["ZONE_" .. zone], function() return def.cfg.zone == zone end, function()
                ns.MoveBlock(def, zone)
                return REFRESH
            end, zone)
        end
        pos:CreateDivider()
        pos:CreateButton(L.MENU_MOVE_LEFT, function() ns.ShiftBlock(def, -1) return REFRESH end)
        pos:CreateButton(L.MENU_MOVE_RIGHT, function() ns.ShiftBlock(def, 1) return REFRESH end)

        local hide = root:CreateButton(L.MENU_HIDE_IN)
        for _, kind in ipairs(ns.SITUATIONS) do
            ns.MenuCheck(hide, L["SITUATION_" .. kind], def.cfg.hideIn, kind, def)
        end

        if not inList then
            root:CreateButton(L.MENU_HIDE, function() ns.SetBlockEnabled(def.id, false) end)
            root:CreateDivider()
            ezCore.Menu.Settings(root, ns)   -- „Einstellungen …“ von ezCore (Zahnrad, Tooltip; T18-8)
        end
    end
end

function ns.OpenBlockMenu(b)
    local def = b.def
    ezCore.Menu.Open(b, function(root) ns.FillBlockMenu(root, def) end)
end

-- Je Baustein ein Untermenü mit allem, was sein Rechtsklick-Menü bietet (Anzeigen anderer Addons gebündelt).
function ns.FillAllBlockMenus(root)
    local brokers
    for _, def in ipairs(ns.blockList) do
        if def.cfg then
            local target = root
            if def.broker then
                brokers = brokers or root:CreateButton(L.MENU_BROKERS)
                target = brokers
            end
            ns.FillBlockMenu(target:CreateButton(def.name), def, true)
        end
    end
end

-- Sichtbarer Weg zu den Optionen aller Bausteine (Knopf auf der Unterseite „Bausteine“): Menü am Mauszeiger.
function ns.OpenAllBlockMenus(owner)
    return ezCore.Menu.Open(owner or _G.SettingsPanel or UIParent, function(root)
        root:CreateTitle(L.MENU_BLOCK_OPTIONS)
        ns.FillAllBlockMenus(root)
    end)
end

---------------------------------------------------------------------------
-- Ziehen und Ablegen
---------------------------------------------------------------------------

local drag = {}

function ns.IsDragging()
    return drag.def ~= nil
end

-- Rechteck eines Frames in UIParent-Koordinaten.
local function Rect(frame)
    local left, bottom, width, height = frame:GetRect()
    if not left then return 0, 0, 0, 0 end
    local f = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * f, (left + width) * f, bottom * f, (bottom + height) * f
end

local function Cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local ghost, marker

local function CreateDragFrames()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(10, 10)   -- unsichtbarer Träger des Zieh-Texts (keine Symbolgröße; Design-System 2.3 betrifft ihn nicht)
    ghost.text = ghost:CreateFontString(nil, "OVERLAY")
    ghost.text:SetFontObject(ns.font)
    ghost.text:SetPoint("CENTER")
    ghost:Hide()

    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    marker.tex = marker:CreateTexture(nil, "OVERLAY")
    marker.tex:SetAllPoints()
    marker.tex:SetColorTexture(1, 0.82, 0, 0.9)
    marker:Hide()
end

local function FindTarget(cx)
    local bar = ns.bar
    if not (bar and bar:IsShown()) then return nil end

    local pad = ns.Px(8) * bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local barL, barR, barB, barT = Rect(bar)
    local width = barR - barL
    local lists = {}
    for _, zone in ipairs(ns.ZONES) do lists[zone] = ZoneList(zone, drag.def) end

    local leftEnd = barL + pad
    local last = lists.left[#lists.left]
    if last then leftEnd = select(2, Rect(last.frame)) end
    local rightStart = barR - pad
    local first = lists.right[1]
    if first then rightStart = Rect(first.frame) end

    -- Grenzen folgen den belegten Bereichen, bleiben aber immer in festen Korridoren:
    -- links bis höchstens 45 %, rechts ab mindestens 55 % – so bleibt jede Zone
    -- erreichbar, auch wenn eine Zone überläuft.
    local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    local leftLimit = Clamp(leftEnd + 40, barL + width * 0.25, barL + width * 0.45)
    local rightLimit = Clamp(rightStart - 40, barR - width * 0.45, barR - width * 0.25)

    local zone
    if cx <= leftLimit then
        zone = "left"
    elseif cx >= rightLimit then
        zone = "right"
    else
        zone = "center"
    end

    local list = lists[zone]
    local index = #list + 1
    for i, def in ipairs(list) do
        local l, r = Rect(def.frame)
        if cx < (l + r) / 2 then
            index = i
            break
        end
    end

    local x
    if #list == 0 then
        x = (zone == "left" and barL + pad) or (zone == "right" and barR - pad) or (barL + barR) / 2
    elseif index <= #list then
        x = Rect(list[index].frame) - 3
    else
        x = select(2, Rect(list[#list].frame)) + 3
    end
    return { zone = zone, index = index, list = list, x = x, bottom = barB, top = barT }
end

local function DragUpdate()
    local cx, cy = Cursor()
    local s = ghost:GetScale()     -- Versatz gilt im eigenen Maßstab des Geists
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, (cy + 14) / s)
    local target = FindTarget(cx)
    drag.target = target
    if target then
        marker:ClearAllPoints()
        marker:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", target.x - 1, target.bottom + 2)
        marker:SetSize(2, math.max(4, target.top - target.bottom - 4))
        marker:Show()
    else
        marker:Hide()
    end
end

local function DragStart(b)
    if ns.S.locked or drag.def then return end
    if not ghost then CreateDragFrames() end
    GameTooltip:Hide()
    drag.def = b.def
    b:SetAlpha(0.35)
    ghost.text:SetText(b.text:GetText())
    ghost:SetScale(b:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:Show()
    ghost:SetScript("OnUpdate", DragUpdate)
    DragUpdate()
end

local function DragStop(b)
    local def = drag.def
    if not def then return end
    local target = drag.target
    drag.def, drag.target = nil, nil
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    marker:Hide()
    b:SetAlpha(1)
    b.dragged = GetTime()
    if target then
        def.cfg.zone = target.zone
        local list = target.list
        table.insert(list, math.min(target.index, #list + 1), def)
        Renumber(list)
    end
    ns.RequestLayout()
    ns.UpdateBarVisibility()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function OnEnter(self)
    if drag.def then return end
    local def = self.def
    if def.OnEnterCustom then
        local ok, err = pcall(def.OnEnterCustom, def, self)
        if not ok then ns.BlockError(def, err, "OnEnterCustom") end
        return
    end
    ShowTooltip(self)
end

local function OnLeave(self)
    local def = self.def
    if def.OnLeaveCustom then pcall(def.OnLeaveCustom, def, self) end
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function OnClick(self, button)
    if self.dragged and GetTime() - self.dragged < 0.3 then return end
    self.dragged = nil
    local def = self.def
    if button == "RightButton" and (not def.ownRightClick or IsShiftKeyDown()) then
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        ns.OpenBlockMenu(self)
        return
    end
    if def.OnClick then
        local ok, err = pcall(def.OnClick, def, button, self)
        if not ok then ns.BlockError(def, err, "OnClick") end
        ns.QueueUpdate(def)
    end
end

local function OnWheel(self, delta)
    local def = self.def
    if def.OnWheel then
        local ok, err = pcall(def.OnWheel, def, delta)
        if not ok then ns.BlockError(def, err, "OnWheel") end
        ns.QueueUpdate(def)
    end
end

local function CreateBlockFrame(def)
    local b = CreateFrame("Button", nil, UIParent)
    b.def = def
    b:Hide()
    b:SetSize(20, ns.BarHeight())
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    -- Hover wie in den Listen der Client-Oberfläche (Atlas), sonst dezent hell.
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if ns.AtlasExists("Options_List_Hover") then
        hl:SetAtlas("Options_List_Hover")
        hl:SetAlpha(0.6)
    else
        hl:SetColorTexture(1, 1, 1, 0.12)
    end
    b.highlight = hl

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(ns.font)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)

    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnDragStart", DragStart)
    b:SetScript("OnDragStop", DragStop)
    if def.OnWheel then
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", OnWheel)
    end
    def.frame = b
    return b
end

Activate = function(def)
    if not def.frame then CreateBlockFrame(def) end
    def.frame.visible = nil
    if def.interval and not def.ticker then
        def.ticker = C_Timer.NewTicker(def.interval, function() ns.QueueUpdate(def) end)
    end
    if def.OnEnable then
        local ok, err = pcall(def.OnEnable, def)
        if not ok then ns.BlockError(def, err, "OnEnable") end
    end
    ns.QueueUpdate(def)
end

Deactivate = function(def)
    if def.ticker then
        def.ticker:Cancel()
        def.ticker = nil
    end
    if def.frame then
        def.frame:Hide()
        def.frame.visible = nil
        if GameTooltip:IsOwned(def.frame) then GameTooltip:Hide() end
    end
    if def.OnDisable then
        local ok, err = pcall(def.OnDisable, def)
        if not ok then ns.BlockError(def, err, "OnDisable") end
    end
end

---------------------------------------------------------------------------
-- Anordnen
---------------------------------------------------------------------------

DoLayout = function()
    local bar = ns.ActiveBar()
    local lists = { left = {}, center = {}, right = {} }
    for _, def in ipairs(ns.blockList) do
        local b = def.frame
        if b then
            if bar and def.cfg.enabled and b.visible then
                local zone = lists[def.cfg.zone] and def.cfg.zone or "left"
                table.insert(lists[zone], def)
            else
                b:Hide()
                b.ezBar = nil
            end
        end
    end
    if not bar then return end

    -- Ränder und Abstand wachsen mit der Schriftgröße (Bezug: Schriftgröße 10).
    local pad, spacing = ns.Px(8), ns.Px(ns.S.spacing)
    local function SortZone(a, c)
        if a.cfg.order ~= c.cfg.order then return a.cfg.order < c.cfg.order end
        return a.index < c.index
    end

    local level = bar:GetFrameLevel() + 3
    for zone, list in pairs(lists) do
        table.sort(list, SortZone)
        for _, def in ipairs(list) do
            local b = def.frame
            b:SetParent(bar)
            b:SetFrameLevel(level)
            b:ClearAllPoints()
            b.ezBar, b.zone = bar, zone
            Resize(b)
            b:Show()
        end
    end

    local left = lists.left
    for i, def in ipairs(left) do
        if i == 1 then
            def.frame:SetPoint("LEFT", bar, "LEFT", pad, 0)
        else
            def.frame:SetPoint("LEFT", left[i - 1].frame, "RIGHT", spacing, 0)
        end
    end

    local right = lists.right
    for i = #right, 1, -1 do
        local def = right[i]
        if i == #right then
            def.frame:SetPoint("RIGHT", bar, "RIGHT", -pad, 0)
        else
            def.frame:SetPoint("RIGHT", right[i + 1].frame, "LEFT", -spacing, 0)
        end
    end

    local center = lists.center
    local total = 0
    for i, def in ipairs(center) do
        total = total + (def.frame.width or def.frame:GetWidth()) + (i > 1 and spacing or 0)
    end
    local x = -total / 2
    for _, def in ipairs(center) do
        def.frame:SetPoint("LEFT", bar, "CENTER", x, 0)
        x = x + (def.frame.width or def.frame:GetWidth()) + spacing
    end
end

-- Werte eines Profils übernehmen (Profiles.lua): je Baustein dieselbe cfg-Tabelle, neu befüllt
-- (falscher Typ → Standard), an- oder ausgeschaltet wie im Profil. Einträge noch nicht
-- angemeldeter Bausteine (LDB-Anzeigen, Bausteine anderer Module über API.lua) bleiben für später liegen.
function ns.ApplyBlockConfigs(map)
    local known = {}
    for _, def in ipairs(ns.blockList) do
        known[def.id] = true
        local cfg = def.cfg
        if cfg then
            local was = cfg.enabled == true
            wipe(cfg)
            local src = map[def.id]
            if type(src) == "table" then
                for k, v in pairs(src) do cfg[k] = type(v) == "table" and CopyTable(v) or v end
            end
            ns.FillDefaults(cfg, def.defaults, true)
            ns.FillDefaults(cfg, COMMON, true)
            cfg.bar = nil
            if cfg.enabled ~= was then
                if cfg.enabled then Activate(def) else Deactivate(def) end
            elseif cfg.enabled then
                -- Bleibt an: Wirkungen außerhalb der Leiste nachziehen (V-084), dann neu zeichnen.
                if def.OnConfigChanged then
                    local ok, err = pcall(def.OnConfigChanged, def)
                    if not ok then ns.BlockError(def, err, "OnConfigChanged") end
                end
                ns.QueueUpdate(def)
            end
            if ns.RefreshBlockSetting then ns.RefreshBlockSetting(def.id) end
        end
    end
    -- Die Abwahl der Meldungs-Quellen steckt in den Optionen des Bausteins „Meldungen“: Häkchen der Unterseite
    -- „Meldungen“ nachziehen (Options.lua).
    if ns.RefreshAlertSettings then ns.RefreshAlertSettings() end
    for id, src in pairs(map) do
        if not known[id] and type(id) == "string" and type(src) == "table" then
            ns.db.blocks[id] = CopyTable(src)
        end
    end
    ns.RequestLayout()
end

function ns.ResetLayout()
    for _, def in ipairs(ns.blockList) do
        local d = def.defaults
        def.cfg.zone = d.zone or COMMON.zone
        def.cfg.order = d.order or COMMON.order
    end
    ns.RequestLayout()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

ns.OnReady(function()
    for _, def in ipairs(ns.blockList) do ns.InitBlock(def) end
    -- Einmalige Übernahme aus Titan Panel, bevor die Bausteine erscheinen.
    if ns.ImportTitan then
        local ok, err = pcall(ns.ImportTitan, false)
        if not ok then geterrorhandler()(err) end
    end
    -- Die Leiste steht schon (Bar.lua lädt vorher): übernommene Werte sofort anwenden.
    if ns.bar then
        ns.ApplyBarStyle()
        ns.UpdateBarVisibility()
        ns.ApplyViewport()
    end
    ns.ready = true
    for _, def in ipairs(ns.blockList) do
        if def.cfg.enabled then Activate(def) end
    end
    ns.RequestLayout()
end)

-- Nach dem Laden alles einmal frisch berechnen (Zonen, Geld, Taschen sind dann bekannt).
ns.On("PLAYER_ENTERING_WORLD", function()
    if ns.ready then ns.UpdateAllBlocks() end
end)

ns.OnSettingChanged(function(key)
    if key == "moneyStyle" then ns.UpdateAllBlocks() end
end)
