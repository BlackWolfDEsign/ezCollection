local _, ns = ...
local Core = ezCore

--[[
    Layout-Grundlage (Punkt 6): ein Muster für eigene Fenster, Werkzeugleisten und Menüs. Vorlagen und
    Texturen bleiben Blizzards Forever-Originale (PortraitFrameFlatTemplate, ButtonFrameTemplate,
    SearchBoxTemplate, UIPanelButtonTemplate, Platz-Ring, Chat-Pfeil). Vorher wiederholten ezBag-, ezChat-
    und ezMacro-Fenster dieselben Zeilen, ezBag und ezMail bauten ihre Knöpfe je selbst.

    Maße:  ezCore.LAYOUT.HEADER_Y, HEADER_X (mit Porträt) / HEADER_X_PLAIN, BUTTON_H, SEARCH_H, SEARCH_X,
           SEARCH_Y / SEARCH_Y_PLAIN, EDGE, GAP, FOOTER_H, CONTENT_TOP, TOOL_SIZE, TOOL_GAP

    Fenster:
      local win = ezCore.NewWindow("ezBagWindow", { template = "PortraitFrameFlatTemplate" (Standard) |
                      "ButtonFrameTemplate", portrait = Symbol (nil = ohne), title = Text, width, height,
                      positionKey = "ezBag.window" (ezCoreDB.positions), import = alte Position (einmal),
                      default = { point, relPoint, x, y }, escape = true (Esc schließt) })
      win:HeaderButton(text, width, onClick, tipTitle, tipBody) → Knopf, von links nach rechts in der Kopfzeile
      win:Search(width, onChange, tipTitle, tipBody)          → Suchfeld oben rechts
      win:Footer(text)                                        → Textzeile unten links (win:SetFooter(text))
      win:SettingsButton(page | fn)                           → Knopf „Einstellungen“ unten rechts
      win:Scroll()                                            → ScrollFrame, content (zwischen Kopf- und Fußzeile)
      win:SavePosition(), win:RestorePosition() → true, wenn es eine gemerkte Lage gab, win:ResetPosition() (gespeicherte Lage vergessen, Standardplatz)

    Werkzeugleiste (Muster aus ezBag/Toolbar.lua):
      local bar = ezCore.Toolbar.New(parent, { size, gap, grow = "left" | "right" (Standard "right"),
                                              onResize = fn(breite) (bei jeder Änderung der Breite) })
      bar:Add(key, { icon, onClick = fn(button, mouse), tooltip = fn(button) → title, lines | { title, lines },
                     badge = true (Zahl unten rechts), order = n })  → Knopf (button.badge, button.active)
      bar:Add(key, { button = eigenerKnopf, order = n })   eigenen Knopf aufnehmen (z. B. Blizzards Plus/Minus-Vorlage);
                     er wird nur angeordnet, seine Breite zählt
      bar:Get(key), bar:SetShown(key, shown), bar:SetActive(key, on), bar:SetBadge(key, text), bar.frame
      bar:Layout() → Breite der Leiste
      ezCore.Toolbar.SlotButton(parent, icon, size)    Knopf im Stil von Blizzards Plätzen (Ring, gedrückt, Leuchten)
      ezCore.Toolbar.ArrowButton(parent, onClick, tipTitle, tipBody, opts)   Pfeil nach unten (Menü), wie ezMails Pfeile;
          opts.size (Gesamtreview 18.11.2026, T18-13)
      ezCore.Toolbar.GearButton(parent, onClick, tipTitle, tipBody, opts)    Zahnrad = Einstellungen (T9-9; Symbol aus
          ezCore.Menu.ICON_SETTINGS, opts.size Standard Core.Style.BUTTON.small)
      ezCore.Toolbar.ShowTipWhileDisabled(knopf)       Tooltip auch am gesperrten Knopf (T9-7; alle Knöpfe hier tun es)
      ezCore.Toolbar.Tip(owner, title, lines, anchor)  Tooltip im einen Format (Titel weiß, Zeilen gold; T18-11);
          Zeile = Text, { text, r, g, b } oder { text, role = "hint" | "good" … }

    Menüs (Blizzards MenuUtil, Retail-Engine):
      ezCore.Menu.Open(owner, function(root) … end)    Kontextmenü; false, wenn MenuUtil fehlt
      ezCore.Menu.Title(root, text)  .Divider(root)  .Button(root, text, fn)
      ezCore.Menu.Toggle(root, text, get, set)         Häkchen
      ezCore.Menu.Radio(root, text, get, set, value)   Auswahlpunkt
          (was set zurückgibt, geht an Blizzards Menü: ezCore.Menu.Close() / .Refresh() / .KeepOpen())
      ezCore.Menu.Choice(root, label, options, get, set)   Untermenü „Sortierung: Name“ mit { { value, text } … }
      ezCore.Menu.SetAll(list, get, set, on, skip) → Anzahl geänderter Einträge
          alle Einträge einer Mehrfachauswahl an (on = true) bzw. aus; nur, was abweicht. list = Tabelle | fn() →
          Tabelle, get(eintrag) → an?, set(eintrag, an), skip(eintrag) → true: nicht mitschalten. Gesperrte Werte
          (Core.IsSecret) bleiben unberührt; ein Fehler in get oder skip lässt nur diesen Eintrag aus.
      ezCore.Menu.AllToggle(root, list, get, set, opts) → Eintrag „an“, Eintrag „aus“ (nil, wo weggelassen)
          Baustein „Alle auswählen / Alle abwählen“ für Menüs mit Mehrfachauswahl (Design-System: überall gleich).
          Zwei schlichte Knöpfe wie Blizzards eigener Eintrag UNCHECK_ALL im Menü „Aufspüren“; der Klick ruft
          Menu.SetAll und gibt Menu.Refresh() zurück (Blizzards Häkchen ziehen nach).
          opts = { on = false (ohne „Alle auswählen“), off = false (ohne „Alle abwählen“), onText, offText
                   (Standard: Core.Style.AllText – Blizzards CHECK_ALL / UNCHECK_ALL samt Schutz gegen Blizzards
                   deutsches „Alle Auswählen“ für UNCHECK_ALL, sonst ezCores Text; leerer Text: kein Eintrag),
                   onTip, offTip (Erklärzeile über Menu.Tip), skip = fn(eintrag), after = fn(anzahl, an),
                   at = Stelle (über Blizzards root:Insert an dieser Stelle einfügen, z. B. direkt unter Blizzards
                   eigenem Eintrag; ohne Insert oder MenuUtil.CreateButton wird angehängt),
                   wrap = fn(schalten) → Anzahl (läuft um das Schalten, z. B. einmal neu zeichnen; Welle 27),
                   icons = true (Symbole Menu.ICON_ALL_ON / ICON_ALL_OFF vor den Einträgen) bzw. onIcon, offIcon
                   (eigene Angabe; Fund des code-reviewers vor dem Merge, 17.11.2026: jeder Eintrag mit Symbol) }
      ezCore.Menu.Tip(eintrag, titel, text, quelle)    Tooltip; quelle als graue Zeile (Welle 27)
      ezCore.Menu.Settings(root, ns, opts) → Eintrag „Einstellungen …“ mit Zahnrad (T18-8)
      ezCore.Menu.Dropdown(parent, breite, build, label) → Auswahlfeld (Blizzards Vorlage, sonst Knopf mit Menü;
          feld:RefreshText(); T18-12)
      ezCore.Menu.IconMarkup(icon, size) → "|A…|a" | "|T…|t", Art   Symbol in Zeilengröße (Core.Style "line" = 16):
          Atlas, sonst Datei, sonst Blizzards Fragezeichen (Menu.ICON_FALLBACK) – nie leer (Welle 27)
      ezCore.Menu.Icon(eintrag, icon) → eintrag   Bild vor den Text des Eintrags (eigener Initializer wie Blizzards
          Menü „Aufspüren“); Menu.IconOf(eintrag), Menu.IconText(text, icon), Menu.IconButton/IconToggle/IconTitle
      ezCore.Menu.Section(root, titel, opts) → Hülle um root: Trenner und Überschrift erst mit dem ersten Eintrag
          (opts = { icon, tip, source, first }); hülle:Used(), hülle:Header()
      ezCore.Menu.IconRoot(root, icon, opts) → Hülle: Symbol als Vorgabe für jeden Eintrag eines Bausteins (17.11.2026)
      ezCore.Menu.ProfessionIcon(kennung), Menu.ProfessionOfTitle(titel), Menu.ProfessionIconOfTitle(titel)
          Symbol eines Berufs (Zauber über die API), Beruf aus dem Titel eines Lehrers (auch Wortstamm, 17.11.2026)
      ezCore.Menu.InsertRoot(root, stelle) → Hülle: Einträge an dieser Stelle einfügen (MenuUtil.Create…, root:Insert)
      ezCore.Menu.PLAYER_MENUS   Blizzards Rechtsklick-Menüs mit einem Spieler (Tag für Menu.ModifyMenu und Art)
      ezCore.Menu.PlayerMenus(filter) → { tag, … }, z. B. { offline = false, guild = false } (Welle 16);
        { frame = true } → die Menüs der Gruppen- und Raidrahmen SELF, PARTY, RAID_PLAYER (Welle 23a)
]]

Core.LAYOUT = {
    HEADER_Y = -30, HEADER_X = 60, HEADER_X_PLAIN = 12,
    BUTTON_H = 22, SEARCH_H = 20, SEARCH_X = -14, SEARCH_Y = -31, SEARCH_Y_PLAIN = -33,
    EDGE = 8, GAP = 6, FOOTER_H = 22, CONTENT_TOP = -60,
    TOOL_SIZE = 22, TOOL_GAP = 2,
}
local LAYOUT = Core.LAYOUT

---------------------------------------------------------------------------
-- Tooltip und Knöpfe
---------------------------------------------------------------------------

Core.Toolbar = Core.Toolbar or {}
local Toolbar = Core.Toolbar

-- Tooltip im einen Format (Gesamtreview 18.11.2026, T18-11; design-system 2.7): Titel weiß, Zeilen gold wie
-- Core.ShowTip und Blizzards Einstellungs-Tooltips (vorher Titel gold, Zeilen weiß – umgekehrt zu Core.ShowTip).
-- Eine Zeile als Tabelle behält ihre Farbe ({ text, r, g, b }) bzw. Rolle ({ text, role = "hint" | "good" … }).
function Toolbar.Tip(owner, title, lines, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOM")
    Core.TipTitle(GameTooltip, title or "")
    for _, line in ipairs(lines or {}) do
        if type(line) == "table" and line.role then Core.TipLine(GameTooltip, line[1], line.role, true)
        elseif type(line) == "table" then GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
        else Core.TipText(GameTooltip, line) end
    end
    GameTooltip:Show()
end

-- Ausgeschaltete Knöpfe zeigen ihren Tooltip samt Grund (Gesamtreview 18.11.2026, T9-7; design-system 2.7 und 2.8):
-- ohne SetMotionScriptsWhileDisabled meldet Blizzard OnEnter eines gesperrten Knopfs nicht.
local function ShowTipWhileDisabled(b)
    if type(b) == "table" and type(b.SetMotionScriptsWhileDisabled) == "function" then
        pcall(b.SetMotionScriptsWhileDisabled, b, true)
    end
    return b
end
Toolbar.ShowTipWhileDisabled = ShowTipWhileDisabled

local function HideTip() GameTooltip:Hide() end

function Toolbar.SlotButton(parent, icon, size)
    size = size or LAYOUT.TOOL_SIZE
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexture(icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    ring:SetPoint("CENTER")
    ring:SetSize(size * 64 / 37, size * 64 / 37)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.active = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.active:SetBlendMode("ADD")
    b.active:SetAllPoints()
    b.active:Hide()
    b:SetScript("OnLeave", HideTip)
    return ShowTipWhileDisabled(b)
end

-- Pfeil nach unten für das Menü eines Teils (Pfeil = Menü dieses Teils, design-system 2.2). opts.size: Kantenlänge
-- (Standard LAYOUT.BUTTON_H; T18-13: ezAuction braucht kleinere Pfeile, z. B. Core.Style.BUTTON.small).
function Toolbar.ArrowButton(parent, onClick, tipTitle, tipBody, opts)
    local b = CreateFrame("Button", nil, parent)
    local size = type(opts) == "table" and tonumber(opts.size) or LAYOUT.BUTTON_H
    b:SetSize(size, size)
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function(self, mouse)
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if onClick then onClick(self, mouse) end
    end)
    if tipTitle then b:SetScript("OnEnter", Core.TipScript(tipTitle, tipBody, "ANCHOR_TOP")) end
    b:SetScript("OnLeave", HideTip)
    return ShowTipWhileDisabled(b)
end

-- Zahnrad = Einstellungen (design-system 2.2, T9-9; vorher drei eigene Symbolquellen in ezAuction, ezMacro, ezMap).
-- Symbol aus EINER Quelle: Core.Menu.ICON_SETTINGS (Atlas questlog-icon-setting, sonst Blizzards UI-OptionsButton).
-- onClick(knopf, maustaste); ohne Tooltip-Titel: „Einstellungen …“. opts.size: Standard Core.Style.BUTTON.small (16).
function Toolbar.GearButton(parent, onClick, tipTitle, tipBody, opts)
    opts = type(opts) == "table" and opts or {}
    local b = CreateFrame("Button", nil, parent)
    local style = Core.Style
    local size = tonumber(opts.size) or (style and style.ButtonSize and style.ButtonSize("small")) or 16
    b:SetSize(size, size)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- dieselbe Auflösung wie im Menü (Menu.ResolveIcon): Atlas, sonst die erste Datei, die der Client kennt, sonst „?“
    local kind, value = Core.Menu.ResolveIcon(Core.Menu.ICON_SETTINGS)
    if kind == "atlas" and tex.SetAtlas then
        tex:SetAtlas(value)
    else
        tex:SetTexture(kind == "atlas" and Core.Menu.ICON_FALLBACK or value)
    end
    b.icon = tex
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if onClick then onClick(self, mouse) end
    end)
    b:SetScript("OnEnter", Core.TipScript(tipTitle or Core.L.MENU_OWN_SETTINGS, tipBody, "ANCHOR_TOP"))
    b:SetScript("OnLeave", HideTip)
    return ShowTipWhileDisabled(b)
end

---------------------------------------------------------------------------
-- Werkzeugleiste
---------------------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

function Toolbar.New(parent, opts)
    opts = opts or {}
    local self = setmetatable({ size = opts.size or LAYOUT.TOOL_SIZE, gap = opts.gap or LAYOUT.TOOL_GAP,
        grow = opts.grow or "right", list = {}, byKey = {}, onResize = opts.onResize }, Bar)
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetSize(self.size, self.size)
    return self
end

function Bar:Add(key, spec)
    spec = spec or {}
    if type(spec.button) == "table" then
        -- eigener Knopf des Moduls: nur anordnen (keine Felder hineinschreiben, die Reihenfolge merkt die Leiste)
        self.orders = self.orders or {}
        self.orders[spec.button] = spec.order or (#self.list + 1)
        self.list[#self.list + 1] = spec.button
        self.byKey[key] = spec.button
        self:Sort()
        self:Layout()
        return spec.button
    end
    local b = Toolbar.SlotButton(self.frame, spec.icon, self.size)
    b.key, b.order = key, spec.order or (#self.list + 1)
    if spec.badge then
        b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.badge:SetDrawLayer("OVERLAY", 7)
        b.badge:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if spec.onClick then b:SetScript("OnClick", function(button, mouse) spec.onClick(button, mouse) end) end
    if spec.tooltip then
        b:SetScript("OnEnter", function(button)
            local title, lines = spec.tooltip, nil
            if type(title) == "function" then title, lines = title(button) end
            if type(title) == "table" then title, lines = title.title or title[1], title.lines or title[2] end
            if title then Toolbar.Tip(button, title, lines) end
        end)
    end
    self.list[#self.list + 1] = b
    self.byKey[key] = b
    self:Sort()
    self:Layout()
    return b
end

function Bar:OrderOf(b)
    return (self.orders and self.orders[b]) or b.order or 0
end

function Bar:Sort()
    table.sort(self.list, function(x, y) return self:OrderOf(x) < self:OrderOf(y) end)
end

function Bar:Get(key) return self.byKey[key] end

function Bar:SetShown(key, shown)
    local b = self.byKey[key]
    if b then b:SetShown(shown and true or false) end
    self:Layout()
end

function Bar:SetActive(key, on)
    local b = self.byKey[key]
    if b and b.active then b.active:SetShown(on and true or false) end
end

function Bar:SetBadge(key, text)
    local b = self.byKey[key]
    if b and b.badge then b.badge:SetText(text or "") end
end

-- Sichtbare Knöpfe nebeneinander; die Leiste wird so breit wie nötig. Rückgabe: Breite.
function Bar:Layout()
    local x, n = 0, 0
    local right = self.grow == "left"
    for _, b in ipairs(self.list) do
        b:ClearAllPoints()
        if b:IsShown() then
            if right then b:SetPoint("RIGHT", self.frame, "RIGHT", -x, 0) else b:SetPoint("LEFT", self.frame, "LEFT", x, 0) end
            local w = Core.Num(b.GetWidth and b:GetWidth())
            x = x + ((w and w > 0) and w or self.size) + self.gap
            n = n + 1
        end
    end
    local width = math.max(self.size, n > 0 and (x - self.gap) or self.size)
    self.frame:SetWidth(width)
    if width ~= self.width then
        self.width = width
        if self.onResize then
            local ok, err = pcall(self.onResize, width)
            if not ok then Core.Error(Core.name, err, "Toolbar") end
        end
    end
    return width
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local Window = {}

function Window:HeaderButton(text, width, onClick, tipTitle, tipBody)
    local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    b:SetSize(width or 100, LAYOUT.BUTTON_H)
    local last = self.ezHeader[#self.ezHeader]
    if last then
        b:SetPoint("LEFT", last, "RIGHT", LAYOUT.GAP, 0)
    else
        b:SetPoint("TOPLEFT", self, "TOPLEFT", self.ezPortrait and LAYOUT.HEADER_X or LAYOUT.HEADER_X_PLAIN, LAYOUT.HEADER_Y)
    end
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    if tipTitle then
        b:SetScript("OnEnter", Core.TipScript(tipTitle, tipBody))
        b:SetScript("OnLeave", HideTip)
    end
    self.ezHeader[#self.ezHeader + 1] = b
    return ShowTipWhileDisabled(b)
end

function Window:Search(width, onChange, tipTitle, tipBody)
    local box = CreateFrame("EditBox", nil, self, "SearchBoxTemplate")
    box:SetSize(width or 150, LAYOUT.SEARCH_H)
    box:SetPoint("TOPRIGHT", self, "TOPRIGHT", LAYOUT.SEARCH_X, self.ezPortrait and LAYOUT.SEARCH_Y or LAYOUT.SEARCH_Y_PLAIN)
    box:SetAutoFocus(false)
    if onChange then box:HookScript("OnTextChanged", function(b) onChange(b:GetText() or "", b) end) end
    if tipTitle then
        box:HookScript("OnEnter", Core.TipScript(tipTitle, tipBody))
        box:HookScript("OnLeave", HideTip)
    end
    self.ezSearch = box
    return box
end

function Window:Footer(text)
    if not self.ezFooter then
        local fs = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", LAYOUT.EDGE + 4, 8)
        fs:SetJustifyH("LEFT")
        self.ezFooter = fs
    end
    self.ezFooter:SetText(text or "")
    return self.ezFooter
end
Window.SetFooter = Window.Footer

function Window:SettingsButton(target)
    local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    b:SetSize(110, LAYOUT.BUTTON_H)
    b:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -LAYOUT.EDGE, 4)
    b:SetText(Core.L.WINDOW_SETTINGS)
    b:SetScript("OnClick", function()
        if type(target) == "function" then return target() end
        if type(target) == "table" and target.Open and target:Open() then return end
        Core.OpenSettings()
    end)
    b:SetScript("OnEnter", Core.TipScript(Core.L.WINDOW_SETTINGS, Core.L.WINDOW_SETTINGS_TIP))
    b:SetScript("OnLeave", HideTip)
    if self.ezFooter then self.ezFooter:SetPoint("RIGHT", b, "LEFT", -LAYOUT.GAP, 0) end
    self.ezSettings = b
    return ShowTipWhileDisabled(b)
end

function Window:Scroll()
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, self, "ScrollFrameTemplate")
    if not (ok and scroll) then scroll = CreateFrame("ScrollFrame", nil, self, "UIPanelScrollFrameTemplate") end
    scroll:SetPoint("TOPLEFT", self, "TOPLEFT", LAYOUT.EDGE, LAYOUT.CONTENT_TOP)
    scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -26, LAYOUT.FOOTER_H + 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)
    return scroll, content
end

function Window:SavePosition()
    if self.ezPositionKey then Core.StorePosition(self.ezPositionKey, self) end
end

-- true, wenn es eine gemerkte Lage gab (sonst steht das Fenster am Standardplatz).
function Window:RestorePosition()
    return Core.RestorePosition(self, self.ezPositionKey, self.ezDefault)
end

function Window:ResetPosition()
    if self.ezPositionKey then Core.StorePosition(self.ezPositionKey, nil) end
    self:RestorePosition()
end

function Core.NewWindow(name, opts)
    opts = opts or {}
    local template = opts.template or "PortraitFrameFlatTemplate"
    local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, template)
    if not (ok and frame) then ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate") end
    if not (ok and frame) then frame = CreateFrame("Frame", name, UIParent) end
    for k, fn in pairs(Window) do frame[k] = fn end
    frame.ezHeader, frame.ezPortrait = {}, opts.portrait ~= nil
    frame.ezPositionKey, frame.ezDefault = opts.positionKey, opts.default
    frame:SetSize(opts.width or 400, opts.height or 400)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SavePosition()
    end)
    if opts.portrait then
        if frame.SetPortraitToAsset then frame:SetPortraitToAsset(opts.portrait)
        elseif frame.SetPortraitTexture then frame:SetPortraitTexture(opts.portrait) end
    elseif template == "ButtonFrameTemplate" and ButtonFrameTemplate_HidePortrait then
        pcall(ButtonFrameTemplate_HidePortrait, frame)
    end
    if opts.title then
        if frame.SetTitle then frame:SetTitle(opts.title) elseif frame.TitleText then frame.TitleText:SetText(opts.title) end
    end
    -- alte Position aus dem Modul einmal übernehmen
    if opts.positionKey then Core.ImportPosition(opts.positionKey, opts.import) end
    frame:RestorePosition()
    if name and opts.escape ~= false and type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, name) end
    frame:Hide()
    return frame
end

---------------------------------------------------------------------------
-- Menüs
---------------------------------------------------------------------------

Core.Menu = Core.Menu or {}
local Menu = Core.Menu

function Menu.Open(owner, build)
    local util = rawget(_G, "MenuUtil")
    if type(util) ~= "table" or type(util.CreateContextMenu) ~= "function" then return false end
    local ok, err = pcall(util.CreateContextMenu, owner, function(_, root)
        local okBuild, buildErr = pcall(build, root)
        if not okBuild then Core.Error(Core.name, buildErr, "Menu") end
    end)
    if not ok then Core.Error(Core.name, err, "Menu") end
    return ok
end

function Menu.Title(root, text) return root:CreateTitle(text) end
function Menu.Divider(root) return root:CreateDivider() end
function Menu.Button(root, text, fn) return root:CreateButton(text, fn) end

-- Tooltip an einem Menüeintrag (GEAR-15): Menu.Tip(Menu.Button(root, …), "Titel", "Text", "Quelle") → der Eintrag.
-- Läuft über Blizzards SetTooltip des Eintrags (wie Blizzards eigene Menüs); kennt der Eintrag es nicht, bleibt er
-- ohne Tooltip. Seit Welle 27 (Zweig modul/ezmap-menue, Design-System 2.7: Hinweise grau) eine optionale graue
-- Zeile „Quelle“ (Blizzards GameTooltip_AddDisabledLine, sonst die Farbe der Rolle „disabled“).
function Menu.Tip(entry, title, text, source)
    if Core.IsSecret(entry) or type(entry) ~= "table" or type(entry.SetTooltip) ~= "function" then return entry end
    if Core.IsSecret(title) or type(title) ~= "string" or title == "" then return entry end
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then text = nil end
    if Core.IsSecret(source) or type(source) ~= "string" or source == "" then source = nil end
    pcall(entry.SetTooltip, entry, function(tooltip)
        if type(tooltip) ~= "table" then return end
        local setTitle, addLine = rawget(_G, "GameTooltip_SetTitle"), rawget(_G, "GameTooltip_AddNormalLine")
        if type(setTitle) == "function" then
            setTitle(tooltip, title)
        elseif type(tooltip.SetText) == "function" then
            Core.TipTitle(tooltip, title)
        end
        if text then
            if type(addLine) == "function" then
                addLine(tooltip, text, true)
            elseif type(tooltip.AddLine) == "function" then
                tooltip:AddLine(text, nil, nil, nil, true)
            end
        end
        if source then
            local addGray = rawget(_G, "GameTooltip_AddDisabledLine")
            if type(addGray) == "function" then
                addGray(tooltip, source, true)
            elseif type(tooltip.AddLine) == "function" then
                local r, g, b = 0.5, 0.5, 0.5
                if type(Core.Style) == "table" and type(Core.Style.Color) == "function" then
                    r, g, b = Core.Style.Color("disabled")
                end
                tooltip:AddLine(source, r, g, b, true)
            end
        end
    end)
    return entry
end

-- Was set zurückgibt, geht an Blizzards Menü (MenuResponse): Menu.Close(), Menu.Refresh(), Menu.KeepOpen().
function Menu.Toggle(root, text, get, set)
    return root:CreateCheckbox(text, function() return get() and true or false end, function() return set(not get()) end)
end

function Menu.Radio(root, text, get, set, value)
    return root:CreateRadio(text, function() return get() == value end, function() return set(value) end, value)
end

local function Response(key)
    local response = rawget(_G, "MenuResponse")
    return type(response) == "table" and response[key] or nil
end
function Menu.Close() return Response("Close") end
function Menu.Refresh() return Response("Refresh") end
function Menu.KeepOpen() return Response("Open") end

function Menu.Choice(root, label, options, get, set)
    local current = get()
    local currentText
    for _, o in ipairs(options or {}) do
        if o[1] == current then currentText = o[2] end
    end
    local sub = root:CreateButton(currentText and (label .. ": " .. currentText) or label)
    for _, o in ipairs(options or {}) do Menu.Radio(sub, o[2], get, set, o[1]) end
    return sub
end

-- „Alle auswählen / Alle abwählen“ (Wunsch des Nutzers vom 15.11.2026 abends zum Menü „Aufspüren“; Muster für das
-- Design-System). Beschreibung im Kopf der Datei.
local function MenuList(list)
    if type(list) == "function" then
        local ok, result = pcall(list)
        list = ok and result or nil
    end
    return type(list) == "table" and list or {}
end

function Menu.SetAll(list, get, set, on, skip)
    if type(get) ~= "function" or type(set) ~= "function" then return 0 end
    on = on and true or false
    local changed = 0
    for _, item in ipairs(MenuList(list)) do
        local skipped = false
        if type(skip) == "function" then
            local ok, result = pcall(skip, item)
            skipped = not ok or Core.IsSecret(result) or (result and true or false)
        end
        if not skipped then
            local ok, current = pcall(get, item)
            if ok and not Core.IsSecret(current) and (current and true or false) ~= on then
                local okSet, err = pcall(set, item, on)
                if okSet then changed = changed + 1 else Core.Error(Core.name, err, "Menu.SetAll") end
            end
        end
    end
    return changed
end

local function GlobalText(name)
    local text = rawget(_G, name)
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
    return text
end

-- Wortlaut „Alle auswählen“ / „Alle abwählen“ an einer Stelle (Core.Style.AllText, Regel 2.11 des Design-Systems);
-- fehlt Core.Style, für „an“ Blizzards Text, für „aus“ nur ezCores Text (Blizzards UNCHECK_ALL heißt im deutschen
-- Client „Alle Auswählen“).
local function AllText(on)
    local style = Core.Style
    if type(style) == "table" and type(style.AllText) == "function" then
        local ok, text = pcall(style.AllText, on)
        if ok then return text end
    end
    local L = type(Core.L) == "table" and Core.L or {}
    if on then return GlobalText("CHECK_ALL") or L.ALL_CHECK end
    return L.ALL_UNCHECK
end

function Menu.AllToggle(root, list, get, set, opts)
    opts = type(opts) == "table" and opts or {}
    if type(root) ~= "table" then return nil, nil end
    local at = type(opts.at) == "number" and opts.at or nil
    local function Add(on, text, tip)
        if Core.IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
        local function Click()
            local n
            if type(opts.wrap) == "function" then
                -- opts.wrap(fn) läuft um das Schalten (z. B. einmal neu zeichnen statt je Eintrag) und gibt fn() zurück
                local ok, result = pcall(opts.wrap, function() return Menu.SetAll(list, get, set, on, opts.skip) end)
                if not ok then Core.Error(Core.name, result, "Menu.AllToggle") end
                n = ok and tonumber(result) or 0
            else
                n = Menu.SetAll(list, get, set, on, opts.skip)
            end
            if type(opts.after) == "function" then
                local ok, err = pcall(opts.after, n, on)
                if not ok then Core.Error(Core.name, err, "Menu.AllToggle") end
            end
            return Menu.Refresh()
        end
        local entry
        local util = rawget(_G, "MenuUtil")
        if at and type(root.Insert) == "function" and type(util) == "table" and type(util.CreateButton) == "function" then
            local ok, desc = pcall(util.CreateButton, text, Click)
            if ok and type(desc) == "table" then
                local okInsert, inserted = pcall(root.Insert, root, desc, at)
                if okInsert then
                    entry = type(inserted) == "table" and inserted or desc
                    at = at + 1
                end
            end
        end
        entry = entry or Menu.Button(root, text, Click)
        if tip then Menu.Tip(entry, text, tip) end
        -- je Eintrag getrennt (kein a and b or c: sonst trüge „Alle auswählen“ mit nur offIcon dessen Bild)
        local icon
        if on then
            icon = opts.onIcon or (opts.icons and Menu.ICON_ALL_ON) or nil
        else
            icon = opts.offIcon or (opts.icons and Menu.ICON_ALL_OFF) or nil
        end
        if icon then Menu.Icon(entry, icon) end
        return entry
    end
    local onEntry, offEntry
    if opts.on ~= false then onEntry = Add(true, opts.onText or AllText(true), opts.onTip) end
    if opts.off ~= false then offEntry = Add(false, opts.offText or AllText(false), opts.offTip) end
    return onEntry, offEntry
end

---------------------------------------------------------------------------
-- Symbole an Menüeinträgen und Abschnitte mit Überschrift (Welle 27, Zweig modul/ezmap-menue; Wunsch des Nutzers vom
-- 16.11.2026 „die passenden icons wären der hit“; Design-System 2.3, Rolle line = 16)
---------------------------------------------------------------------------

--[[
    Symbol-Angabe (icon): Name eines Atlas (gilt, wenn der Client ihn kennt, sonst als Dateipfad), Datei-ID (Zahl),
    Funktion → Angabe, oder Tabelle { atlas = Name | { Namen … }, file = Pfad | Datei-ID | { … }, crop = true }. Der
    erste Atlas, den der Client kennt (Core.AtlasExists), gewinnt, dann die erste bekannte Datei (Core.KnownFile;
    Datei-IDs über 0 gelten immer), sonst Blizzards Fragezeichen Menu.ICON_FALLBACK – nie ein leeres Feld. crop
    schneidet den Rand von Zauber- und Gegenstandssymbolen ab (wie Blizzards Menü „Aufspüren“ bei Zaubern).
    Menu.Icon setzt das Bild VOR den Text des Eintrags: über einen eigenen Initializer (Blizzards AddInitializer, wie
    Blizzards CreateCheckboxWithIcon im Menü „Aufspüren“), der nach Blizzards eigenem läuft und dessen Schrift
    (button.fontString) den Text mit Bild gibt; die Breite misst Blizzard danach aus den Bildteilen
    (Blizzard_Menu/Menu.lua, CallInitializers). Der Text des Eintrags selbst bleibt, wie er ist (MenuUtil.GetElementText,
    Tooltips). In Blizzards Tabellen wird nichts geschrieben; welches Bild ein Eintrag trägt, merkt ezCore schwach
    (Menu.IconOf).
]]
Menu.ICON_FALLBACK = Core.ICON_FALLBACK
-- „Alle auswählen“ / „Alle abwählen“ (AllToggle mit opts.icons): Blizzards Häkchen der Haken bzw. das Kreuz „Passen“
-- der Beutewürfel – Dateien, die jeder Client mitbringt (Fund des code-reviewers vor dem Merge, 17.11.2026: auch diese
-- Einträge tragen ein Symbol)
Menu.ICON_ALL_ON = { file = "Interface\\Buttons\\UI-CheckBox-Check" }
Menu.ICON_ALL_OFF = { file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }
Menu.ICON_CROP = ":0:0:64:64:5:59:5:59"       -- etwa 8 % Rand weg, wie Core.SetIcon (0,08 bis 0,92)
-- Zahnrad „Einstellungen“ – die eine Quelle für Menüeinträge (Menu.Settings) und Knöpfe (Toolbar.GearButton) (T9-9):
-- Blizzards Atlas aus dem Questlog, sonst Blizzards Options-Knopf, sonst das Zahnrad-Symbol
Menu.ICON_SETTINGS = { atlas = "questlog-icon-setting",
    file = { "Interface\\Buttons\\UI-OptionsButton", "Interface\\Icons\\INV_Misc_Gear_01" } }

local iconOf = setmetatable({}, { __mode = "k" })

local function IconSize(size)
    if type(size) == "number" and size > 0 then return size end
    local style = Core.Style
    local n = type(style) == "table" and type(style.IconSize) == "function" and style.IconSize("line") or nil
    return type(n) == "number" and n or 16
end

local function AsList(value)
    if type(value) == "table" then return value end
    if value == nil then return {} end
    return { value }
end

-- Symbol-Angabe auflösen → Art "atlas" | "file" | "fallback", Atlas-Name bzw. Datei, crop (true/false). Eine Stelle für
-- Menüeinträge (Menu.IconMarkup) und Knöpfe (Toolbar.GearButton), damit beide dasselbe Bild zeigen (Gegenprüfung D1).
function Menu.ResolveIcon(icon)
    if type(icon) == "function" then
        local ok, result = pcall(icon)
        icon = ok and result or nil
    end
    if Core.IsSecret(icon) then icon = nil end
    local spec
    if type(icon) == "table" then
        spec = icon
    elseif type(icon) == "string" and icon ~= "" then
        spec = { atlas = icon, file = icon }
    elseif type(icon) == "number" then
        spec = { file = icon }
    else
        spec = {}
    end
    for _, atlas in ipairs(AsList(spec.atlas)) do
        if type(atlas) == "string" and not Core.IsSecret(atlas) and atlas ~= "" and Core.AtlasExists(atlas) then
            return "atlas", atlas, false
        end
    end
    for _, file in ipairs(AsList(spec.file)) do
        if not Core.IsSecret(file) then
            local known = (type(file) == "number" and file > 0)
                or (type(file) == "string" and file ~= "" and file:find("[/\\]") ~= nil and Core.KnownFile(file))
            if known then return "file", file, spec.crop and true or false end
        end
    end
    return "fallback", Menu.ICON_FALLBACK, true
end

-- → Bild im Text ("|A…|a" bzw. "|T…|t"), Art "atlas" | "file" | "fallback"
function Menu.IconMarkup(icon, size)
    size = IconSize(size)
    local kind, value, crop = Menu.ResolveIcon(icon)
    if kind == "atlas" then return ("|A:%s:%d:%d|a"):format(value, size, size), kind end
    return ("|T%s:%d:%d%s|t"):format(tostring(value), size, size, crop and Menu.ICON_CROP or ""), kind
end

-- Text mit Bild davor (für Zeilen, die kein Menüeintrag sind, und für Prüfungen) → Text
function Menu.IconText(text, icon, size)
    if Core.IsSecret(text) or type(text) ~= "string" then return text end
    return Menu.IconMarkup(icon, size) .. " " .. text
end

-- Bild vor den Text eines Eintrags setzen → der Eintrag. Trägt der Eintrag schon ein Bild, bleibt es (das erste gilt).
-- Ausnahme seit dem Fund des code-reviewers vom 17.11.2026: ein Bild, das eine Hülle nur als Vorgabe gesetzt hat
-- (Menu.IconRoot), weicht dem ersten ausdrücklichen Menu.Icon des Bausteins – so tragen „Route durch diese Zone“ und
-- „Wo am dichtesten?“ ihr eigenes Symbol statt des Symbols der Hülle. Je Eintrag nur ein Initializer; er liest das
-- Bild erst beim Zeichnen.
local weakIcon = setmetatable({}, { __mode = "k" })
local function SetIcon(entry, icon, size, weak)
    if Core.IsSecret(entry) or type(entry) ~= "table" or icon == nil then return entry end
    local had = iconOf[entry]
    if had and (weak or not weakIcon[entry]) then return entry end
    iconOf[entry] = Menu.IconMarkup(icon, size)
    weakIcon[entry] = weak and true or nil
    if not had and type(entry.AddInitializer) == "function" then
        pcall(entry.AddInitializer, entry, function(button)
            local markup = iconOf[entry]
            local fs = type(button) == "table" and (button.fontString or button.Text) or nil
            if type(markup) ~= "string" or type(fs) ~= "table" or type(fs.GetText) ~= "function" then return end
            local text = fs:GetText()
            if Core.IsSecret(text) or type(text) ~= "string" or text:sub(1, #markup) == markup then return end
            local set = type(fs.SetTextToFit) == "function" and fs.SetTextToFit or fs.SetText
            if type(set) == "function" then set(fs, markup .. " " .. text) end
        end)
    end
    return entry
end

function Menu.Icon(entry, icon, size) return SetIcon(entry, icon, size, false) end

-- Welches Bild trägt der Eintrag? → Bild im Text oder nil
function Menu.IconOf(entry)
    if Core.IsSecret(entry) or type(entry) ~= "table" then return nil end
    return iconOf[entry]
end

function Menu.IconButton(root, text, fn, icon) return Menu.Icon(Menu.Button(root, text, fn), icon) end
function Menu.IconToggle(root, text, get, set, icon) return Menu.Icon(Menu.Toggle(root, text, get, set), icon) end
function Menu.IconTitle(root, text, icon) return Menu.Icon(Menu.Title(root, text), icon) end

--[[
    Menüeintrag „Einstellungen …“ eines Moduls (Gesamtreview 18.11.2026, T18-8; vorher acht eigene Wortlaute:
    „Optionen“, „Einstellungen“, „Einstellungen …“, „Einstellungen von ezHeal“): Menu.Settings(root, mns, opts) → Eintrag
      Text Core.L.MENU_OWN_SETTINGS („Einstellungen …“ – „Optionen“ heißt nur Blizzards Fenster), Zahnrad aus
      Menu.ICON_SETTINGS, Tooltip mit dem Modulnamen; der Klick öffnet die Seite des Moduls (im Kampf vorgemerkt,
      Core.OpenedOrDeferred), geht das nicht, kommt die Hilfe im Chat. opts.text: eigener Text (nur mit Grund).
]]
function Menu.Settings(root, mns, opts)
    opts = type(opts) == "table" and opts or {}
    if type(root) ~= "table" or type(mns) ~= "table" then return nil end
    local L = Core.L
    local owner = mns.moduleName or Core.TITLE
    local entry = Menu.IconButton(root, opts.text or L.MENU_OWN_SETTINGS, function()
        if not Core.OpenedOrDeferred(function() return mns.OpenSettings and mns.OpenSettings() end) then
            if type(mns.PrintHelp) == "function" then mns.PrintHelp() end
        end
    end, Menu.ICON_SETTINGS)
    return Menu.Tip(entry, opts.text or L.MENU_OWN_SETTINGS, L.MENU_OWN_SETTINGS_TIP:format(owner))
end

--[[
    Auswahlfeld (Gesamtreview 18.11.2026, T18-12; vorher dreimal kopiert in ezAuction, ezHeal, ezMacro mit
    verschiedenem Rückfall): Menu.Dropdown(parent, breite, build, label) → Auswahlfeld
      Blizzards WowStyle1DropdownTemplate (DropdownButton, SetupMenu); fehlt die Vorlage, ein Knopf mit Kontextmenü über
      Menu.Open (immer derselbe Rückfall – nie still weiterschalten). build(root) füllt das Menü (Menu.Radio …),
      label() liefert den Text des Rückfall-Knopfs.
      feld:RefreshText()   Text nach einer Änderung auffrischen (Blizzard: GenerateMenu; Rückfall: label()); bewusst
                      nicht „Update“ – den Namen könnte Blizzards Vorlage selbst tragen
      feld.modern     true mit Blizzards Vorlage
]]
function Menu.Dropdown(parent, width, build, label)
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    local box
    if ok and type(dropdown) == "table" and type(dropdown.SetupMenu) == "function" then
        dropdown:SetWidth(width or 150)
        dropdown:SetupMenu(function(_, root)
            local okBuild, err = pcall(build, root)
            if not okBuild then Core.Error(Core.name, err, "Menu.Dropdown") end
        end)
        box = dropdown
        box.modern = true
    else
        box = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        box:SetSize(width or 150, LAYOUT.BUTTON_H)
        box:SetScript("OnClick", function(self) Menu.Open(self, build) end)
        box.modern = false
    end
    function box:RefreshText()
        if self.modern then
            if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        elseif type(label) == "function" then
            local okLabel, text = pcall(label)
            if okLabel and type(text) == "string" then self:SetText(text) end
        end
    end
    box:RefreshText()
    return box
end

--[[
    Symbol als Vorgabe für alle Einträge eines Bausteins (Fund des code-reviewers vor dem Merge, 17.11.2026: vorher als
    MapButton.IconRoot in ezMap; ezCraft- und ezTalent-Menü sollen denselben Helfer nutzen, Leitlinie 2):
    Menu.IconRoot(root, icon, opts) → Hülle um root. Jeder Eintrag, den ein Baustein DIREKT über die Hülle anlegt
    (Knopf, Haken, Auswahlpunkt, Titelzeile; keine Trenner), bekommt icon als Vorgabe; setzt der Baustein danach selbst
    ein Symbol (Menu.Icon), gilt seines. Untermenüs des Bausteins bleiben ohne (ihre Einträge sind Listen).
    opts = { titleIcon = Angabe (eigenes Bild für Titelzeilen, z. B. ein Hinweis-Symbol für Hilfszeilen),
    titles = false (Titelzeilen ohne Bild) }. Ohne icon oder ohne root → root unverändert.
]]
local ICON_KINDS = { CreateButton = true, CreateCheckbox = true, CreateRadio = true }
function Menu.IconRoot(root, icon, opts)
    if icon == nil or type(root) ~= "table" then return root end
    opts = type(opts) == "table" and opts or {}
    local titleIcon = opts.titles ~= false and (opts.titleIcon or icon) or nil
    return setmetatable({}, { __index = function(_, key)
        local value = root[key]
        if type(value) ~= "function" then return value end
        return function(_, ...)
            local entry = value(root, ...)
            if ICON_KINDS[key] then
                SetIcon(entry, icon, nil, true)
            elseif key == "CreateTitle" and titleIcon ~= nil then
                SetIcon(entry, titleIcon, nil, true)
            end
            return entry
        end
    end })
end

--[[
    Symbol eines Berufs (Fund des code-reviewers vor dem Merge, 17.11.2026; vorher ezMap/Icons.lua): Bild des
    Berufszaubers über die API (Core.Spells.ProfessionSpell aus KnowledgeData.PROFESSIONS, Core.Spells.Icon), mit
    abgeschnittenem Rand; Kräuterkunde hat dort keinen Zauber – dann Blizzards Datei Trade_Herbalism.
    Menu.ProfessionIcon(kennung) → Angabe für Menu.IconMarkup (Funktion, rechnet beim Bau des Menüs) oder nil.
]]
Menu.PROFESSION_FILE = { herbalism = "Interface\\Icons\\Trade_Herbalism" }
local function Professions()
    local data = ns.KnowledgeData
    return type(data) == "table" and type(data.PROFESSIONS) == "table" and data.PROFESSIONS or {}
end
function Menu.ProfessionIcon(key)
    if Core.IsSecret(key) or type(key) ~= "string" then return nil end
    local known = false
    for _, p in ipairs(Professions()) do
        if p.key == key then known = true break end
    end
    if not known then return nil end
    return function()
        local Spells = Core.Spells
        local spell = type(Spells) == "table" and type(Spells.ProfessionSpell) == "function" and Spells.ProfessionSpell(key) or nil
        local files = {}
        if spell and type(Spells.Icon) == "function" then
            local ok, icon = pcall(Spells.Icon, spell)
            if ok and not Core.IsSecret(icon) and (type(icon) == "number" or type(icon) == "string") then files[1] = icon end
        end
        files[#files + 1] = Menu.PROFESSION_FILE[key]
        return { file = files, crop = true }
    end
end

--[[
    Beruf aus dem Titel eines Lehrers (Fund des code-reviewers vor dem Merge, 17.11.2026: deutsche Titel sind meist aus
    dem Wortstamm gebildet – „Schneiderlehrer“ zu „Schneiderei“, „Kürschnerlehrer“, „Angellehrer“, „Erste-Hilfe-Lehrer“).
    Verglichen werden alle Berufe aus KnowledgeData.PROFESSIONS (nicht nur eigene), je mit dem Namen aus dem Client
    (Core.Knowledge.ProfessionName) und den deutschen und englischen Namen der Liste; Groß- und Kleinschreibung,
    Leerzeichen und Bindestriche zählen nicht, dazu der Wortstamm ohne die erste passende Endung aus
    Menu.PROFESSION_STEMS (mindestens vier Zeichen). Der längste Treffer gewinnt.
    Menu.ProfessionOfTitle(titel) → Kennung oder nil; Menu.ProfessionIconOfTitle(titel) → Angabe, Kennung | nil
]]
Menu.PROFESSION_STEMS = { { "skunst", "" }, { "kunst", "" }, { "kunde", "" }, { "erei", "er" }, { "ung", "" },
    { "eln", "el" }, { "ing", "" }, { "ism", "is" }, { "ie", "" }, { "y", "" } }
local function Squash(text) return (text:lower():gsub("[%s%-]", "")) end
local function Candidates(name, out)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return out end
    local full = Squash(name)
    out[#out + 1] = full
    for _, rule in ipairs(Menu.PROFESSION_STEMS) do
        local tail = rule[1]
        if #full > #tail and full:sub(-#tail) == tail then
            local stem = full:sub(1, -#tail - 1) .. rule[2]
            if #stem >= 4 then out[#out + 1] = stem end
            break
        end
    end
    return out
end
function Menu.ProfessionOfTitle(title)
    if Core.IsSecret(title) or type(title) ~= "string" or title == "" then return nil end
    local text = Squash(title)
    local K = Core.Knowledge
    local nameOf = type(K) == "table" and type(K.ProfessionName) == "function" and K.ProfessionName or nil
    local best, bestLen
    for _, p in ipairs(Professions()) do
        local names = {}
        if nameOf then
            local ok, name = pcall(nameOf, p.key)
            if ok then Candidates(name, names) end
        end
        Candidates(p.de, names)
        Candidates(p.en, names)
        for _, cand in ipairs(names) do
            if (not bestLen or #cand > bestLen) and text:find(cand, 1, true) then best, bestLen = p.key, #cand end
        end
    end
    return best
end
function Menu.ProfessionIconOfTitle(title)
    local key = Menu.ProfessionOfTitle(title)
    if not key then return nil end
    return Menu.ProfessionIcon(key), key
end

--[[
    Einträge an einer Stelle mitten in einem Menü einfügen (Antwort des Nutzers vom 17.11.2026 zur Kopplung, „B“:
    ezMaps Einträge direkt unter dem passenden Blizzard-Eintrag im Menü „Aufspüren“):
    Menu.InsertRoot(root, at) → Hülle um root. Create… legt den Eintrag über Blizzards MenuUtil.Create… an und fügt ihn
    mit root:Insert an der Stelle at ein (at zählt danach weiter, mehrere Einträge stehen also in ihrer Reihenfolge);
    die Einträge sind echte Beschreibungen – Untermenüs und Tooltips daran wie sonst. Fehlt Insert oder MenuUtil.Create…,
    hängt die Hülle wie root an. hülle:Count() → Zahl der angelegten Einträge. Blizzards eigene Einträge bleiben, wie
    sie sind (nur neue Beschreibungen dazwischen, Leitlinie 5).
]]
local INSERT_KINDS = { CreateButton = true, CreateCheckbox = true, CreateRadio = true, CreateTitle = true,
    CreateDivider = true }
function Menu.InsertRoot(root, at)
    if type(root) ~= "table" then return root end
    local count = 0
    local proxy = {}
    function proxy.Count() return count end
    setmetatable(proxy, { __index = function(_, key)
        local value = root[key]
        if INSERT_KINDS[key] then
            return function(_, ...)
                local util = rawget(_G, "MenuUtil")
                local make = type(util) == "table" and util[key] or nil
                local desc
                if type(at) == "number" and type(root.Insert) == "function" and type(make) == "function" then
                    local ok, made = pcall(make, ...)
                    if ok and type(made) == "table" then
                        local okInsert, inserted = pcall(root.Insert, root, made, at)
                        if okInsert then
                            desc = type(inserted) == "table" and inserted or made
                            at = at + 1
                        end
                    end
                end
                if desc == nil and type(value) == "function" then desc = value(root, ...) end
                if desc ~= nil then count = count + 1 end
                return desc
            end
        end
        if type(value) == "function" then
            return function(self, ...)
                if self == proxy then self = root end
                return value(self, ...)
            end
        end
        return value
    end })
    return proxy
end

--[[
    Abschnitt mit Überschrift, die nur erscheint, wenn der Abschnitt etwas enthält: Menu.Section(root, titel, opts) →
    eine Hülle um root. Der erste Eintrag, den ein Baustein über die Hülle anlegt (Create…), setzt davor einen Trenner
    (ohne opts.first) und die Überschrift (Blizzards Titelzeile, mit opts.icon als Bild, opts.tip/opts.source als
    Tooltip). Alles andere reicht die Hülle an root weiter – Bausteine, die root erwarten, nehmen sie unverändert.
    opts = { icon, tip, source, first = true (ohne Trenner), chain = Tabelle, die mehrere Abschnitte eines Menüs teilen:
    der erste davon, der etwas anlegt, steht ohne Trenner – auch wenn ein Abschnitt davor leer bleibt }.
    hülle:Used() → true, sobald etwas darin steht;
    hülle:Header() → die Überschrift (nil, solange leer). Ein Fehler beim Anlegen der Überschrift kostet den Eintrag nicht.
]]
function Menu.Section(root, title, opts)
    opts = type(opts) == "table" and opts or {}
    if type(root) ~= "table" then return root end
    local header
    local used = false
    local proxy = {}
    local function Head()
        if used then return end
        used = true
        local ok, err = pcall(function()
            local chain = type(opts.chain) == "table" and opts.chain or nil
            local first = opts.first or (chain ~= nil and not chain.used)
            if chain then chain.used = true end
            if not first then Menu.Divider(root) end
            if type(title) == "string" and not Core.IsSecret(title) and title ~= "" then
                header = Menu.Title(root, title)
                if opts.icon ~= nil then Menu.Icon(header, opts.icon) end
                if opts.tip or opts.source then Menu.Tip(header, title, opts.tip, opts.source) end
            end
        end)
        if not ok then Core.Error(Core.name, err, "Menu.Section") end
    end
    function proxy.Used() return used end
    function proxy.Header() return header end
    setmetatable(proxy, { __index = function(_, key)
        local value = root[key]
        if type(value) == "function" and type(key) == "string" and (key:sub(1, 6) == "Create" or key == "Insert") then
            return function(self, ...)
                if self == proxy then self = root end
                Head()
                return value(self, ...)
            end
        end
        if type(value) == "function" then
            return function(self, ...)
                if self == proxy then self = root end
                return value(self, ...)
            end
        end
        return value
    end })
    return proxy
end

-- Blizzards Rechtsklick-Menüs, die einen Spieler zeigen – EINE Liste für alle Module, die sie über Menu.ModifyMenu
-- ergänzen (Welle 16, Wunsch des Nutzers „In Gilde einladen“). Tag „MENU_UNIT_“ .. Menüname, wie Blizzard ihn setzt
-- (Blizzard_UnitPopupShared/UnitPopupShared.lua: rootDescription:SetTag("MENU_UNIT_"..which, contextData); Menüs in
-- UnitPopupSharedMenus.lua und Blizzard_UnitPopup/Camelot/UnitPopupMenus.lua, Zweig forever). Wer welches Menü
-- öffnet, steht in derselben Quelle: Gruppen- und Raidrahmen PARTY/RAID_PLAYER/SELF, Zielfenster und Fokus mit einem
-- freundlichen Spieler PLAYER (TARGET und FOCUS nur bei anderen Einheiten), Chat-Namen, Wer-Liste und Freunde online
-- FRIEND (FriendsFrame_ShowDropdown). Art je Eintrag (fehlt = nein):
--   unit     contextData.unit ist gesetzt (Rahmen, Ziel, Fokus, Raid-Liste)
--   self     der eigene Charakter            enemy    ein Spieler der Gegenfraktion
--   offline  der Spieler ist offline         guild    Mitglieder der eigenen Gilde (Gildenliste)
--   bnet     ein Battle.net-Konto, kein Charakter (contextData.bnetIDAccount)
--   npc      das Menü zeigt auch Einheiten, die keine Spieler sind
--   frame    das Menü der Gruppen- und Raidrahmen (CompactUnitFrame_OpenMenu: SELF, PARTY, RAID_PLAYER; Welle 23a,
--            A79) – Menu.PlayerMenus({ frame = true }) für Module, die nur dort ergänzen (ezBuff)
Menu.PLAYER_MENUS = {
    { tag = "MENU_UNIT_SELF", unit = true, self = true, frame = true },
    { tag = "MENU_UNIT_PARTY", unit = true, frame = true },
    { tag = "MENU_UNIT_RAID_PLAYER", unit = true, frame = true },
    { tag = "MENU_UNIT_RAID", unit = true },
    { tag = "MENU_UNIT_PLAYER", unit = true },
    { tag = "MENU_UNIT_ENEMY_PLAYER", unit = true, enemy = true },
    { tag = "MENU_UNIT_TARGET", unit = true, npc = true },
    { tag = "MENU_UNIT_FOCUS", unit = true, npc = true },
    { tag = "MENU_UNIT_FRIEND" },
    { tag = "MENU_UNIT_FRIEND_OFFLINE", offline = true },
    { tag = "MENU_UNIT_BN_FRIEND", bnet = true },
    { tag = "MENU_UNIT_BN_FRIEND_OFFLINE", bnet = true, offline = true },
    { tag = "MENU_UNIT_GUILD", guild = true },
    { tag = "MENU_UNIT_GUILD_OFFLINE", guild = true, offline = true },
    { tag = "MENU_UNIT_CHAT_ROSTER" },
    { tag = "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", guild = true },
    { tag = "MENU_UNIT_COMMUNITIES_WOW_MEMBER" },
    { tag = "MENU_UNIT_COMMUNITIES_MEMBER", bnet = true },
    { tag = "MENU_UNIT_RECENT_ALLY" },
    { tag = "MENU_UNIT_RECENT_ALLY_OFFLINE", offline = true },
}

-- Tags der Spieler-Menüs, deren Art zum Filter passt: { offline = false } lässt Offline-Menüs weg, { unit = true }
-- nimmt nur Menüs mit Einheit. Ohne Filter alle, in der Reihenfolge der Liste.
function Menu.PlayerMenus(filter)
    local list = {}
    for _, entry in ipairs(Menu.PLAYER_MENUS) do
        local fits = true
        if type(filter) == "table" then
            for key, want in pairs(filter) do
                if (entry[key] == true) ~= (want == true) then fits = false end
            end
        end
        if fits then list[#list + 1] = entry.tag end
    end
    return list
end
