local _, ns = ...
local L = ns.L

-- Gemeinsame Bausteine für den Makro-Browser und seine Werkzeuge (vorher lokal in Browser.lua):
-- Blizzards Farbkonstanten, Klänge, Scrollbereich wie in der Makroverwaltung, Knöpfe mit Tooltip und
-- eine schlichte Liste im Stil der Klassenlehrer-Zeilen.
local UI = {}
ns.UI = UI

-- Weiterleitung auf ezCores Ton-Helfer (Gesamtreview 18.11.2026, T16-NM4; vorher der einzige Helfer im Paket)
function UI.PlaySound(key)
    return ezCore.PlaySound(key)
end

-- Blizzards Farbkonstanten (ColorMixin), Hexwert nur als Rückfall.
local FALLBACK_COLORS = {
    RED_FONT_COLOR = "ffff2020", GREEN_FONT_COLOR = "ff20ff20", GRAY_FONT_COLOR = "ff808080",
    NORMAL_FONT_COLOR = "ffffd200", ORANGE_FONT_COLOR = "ffff7f3f", LIGHTBLUE_FONT_COLOR = "ff8080ff",
    HIGHLIGHT_FONT_COLOR = "ffffffff",
}

function UI.Colored(colorName, text)
    local color = _G[colorName]
    if type(color) == "table" and color.WrapTextInColorCode then return color:WrapTextInColorCode(text) end
    return "|c" .. FALLBACK_COLORS[colorName] .. text .. "|r"
end

function UI.SetFontColor(fontString, colorName)
    local color = _G[colorName]
    if type(color) == "table" and color.GetRGB then
        fontString:SetTextColor(color:GetRGB())
    else
        local hex = FALLBACK_COLORS[colorName]
        fontString:SetTextColor(tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
            tonumber(hex:sub(7, 8), 16) / 255)
    end
end

-- Moderne Scrollleiste wie in Blizzards Makroverwaltung (ScrollFrameTemplate mit MinimalScrollBar).
-- x/top/bottom entsprechen den KeyValues von MacroFrameScrollFrameTemplate.
function UI.ScrollFrame(name, parent, hideIfUnscrollable)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", name, parent, "ScrollFrameTemplate")
    if not (ok and scroll) then
        scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    end
    local bar = scroll.ScrollBar
    if type(bar) == "table" and bar.SetHideIfUnscrollable then
        bar:SetHideIfUnscrollable(hideIfUnscrollable and true or false)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -4)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 5)
    end
    return scroll
end

-- Tooltip mit weißem Titel und umbrochenem Text (ezCore.ShowTip); Titel und Text dürfen Funktionen sein, die
-- ihn erst beim Zeigen bauen (Stand der Werkzeuge, Ränge).
function UI.Tip(owner, title, body, anchor)
    if type(title) == "function" then title = title() end
    if type(body) == "function" then body = body() end
    ezCore.ShowTip(owner, title, body, anchor)
end

local function HideTip() GameTooltip:Hide() end

-- Knopf aus Blizzards UIPanelButtonTemplate mit Tooltip; der Tooltip kommt auch am gesperrten Knopf (Angeln und Ränge
-- sperren Knöpfe im Kampf bzw. ohne Auswahl, der Tooltip sagt warum; Gesamtreview 18.11.2026, T9-7).
function UI.Button(parent, text, width, onClick, tipTitle, tipBody, name)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    button:SetText(text)
    button:SetScript("OnClick", function(self, mouseButton)
        UI.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        onClick(self, mouseButton)
    end)
    if tipTitle or tipBody then
        button:SetScript("OnEnter", function(self) UI.Tip(self, tipTitle or text, tipBody) end)
        button:SetScript("OnLeave", HideTip)
        ezCore.Toolbar.ShowTipWhileDisabled(button)
    end
    return button
end

-- Häkchen für eine Einstellung aus ns.S, mit Beschriftung und dem Tooltip der Einstellungsseite.
function UI.SettingCheck(parent, key)
    local check = ezCore.CreateCheck(parent, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    label:SetText(L["OPT_" .. key])
    check.label = label
    check:SetScript("OnClick", function(self)
        ns.SetSetting(key, self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self) UI.Tip(self, L["OPT_" .. key], L["OPT_" .. key .. "_TIP"]) end)
    check:SetScript("OnLeave", HideTip)
    function check.Refresh() check:SetChecked(ns.S[key] and true or false) end
    check.Refresh()
    return check
end

-- Überschrift und umbrochener Text für die Werkzeug-Seiten.
function UI.Text(parent, font, width)
    local text = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    if width then text:SetWidth(width) end
    text:SetSpacing(2)
    return text
end

---------------------------------------------------------------------------
-- Liste: Zeilen mit Symbol, Name und Unterzeile, Auswahl per Klick (Optik wie die Browser-Liste,
-- aber flacher). items = { { icon, text, sub, tip, data, check }, … }
---------------------------------------------------------------------------

local LIST_ROW_H = 30

function UI.List(parent, name, width, onSelect, onDouble)
    local list = { items = {}, rows = {}, selected = nil }
    local ok, bg = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if not (ok and bg) then bg = CreateFrame("Frame", nil, parent) end
    list.frame = bg
    local scroll = UI.ScrollFrame(name, bg, true)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 26, 1)
    scroll:SetScrollChild(content)
    list.scroll, list.content = scroll, content

    list.empty = bg:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.empty:SetPoint("TOPLEFT", 12, -14)
    list.empty:SetPoint("RIGHT", -12, 0)
    list.empty:SetJustifyH("CENTER")

    local function RowClick(row)
        if not row.item then return end
        list.selected = row.item
        list:Refresh()
        if onSelect then onSelect(row.item) end
    end

    local function CreateListRow(index)
        local row = CreateFrame("Button", nil, content)
        row:SetSize(width - 26, LIST_ROW_H)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * LIST_ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAllPoints()
        row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
        row.selectedTex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selectedTex:SetVertexColor(1, 0.82, 0, 0.5)
        row.selectedTex:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 3, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", RowClick)
        row:SetScript("OnDoubleClick", function(self)
            RowClick(self)
            if onDouble and self.item then onDouble(self.item) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.item and self.item.tip then UI.Tip(self, self.item.text, self.item.tip) end
        end)
        row:SetScript("OnLeave", HideTip)
        list.rows[index] = row
        return row
    end

    function list:SetItems(items, emptyText)
        self.items = items or {}
        local keep
        for _, item in ipairs(self.items) do
            if self.selected and item.key ~= nil and item.key == self.selected.key then keep = item end
        end
        self.selected = keep
        self.empty:SetText(emptyText or "")
        self:Refresh()
    end

    function list:Refresh()
        for index = #self.rows + 1, #self.items do CreateListRow(index) end
        content:SetHeight(math.max(1, #self.items * LIST_ROW_H))
        for index, row in ipairs(self.rows) do
            local item = self.items[index]
            row.item = item
            if item then
                row.icon:SetTexture(item.icon or ns.DEFAULT_ICON)
                row.icon:SetDesaturated(item.grey and true or false)
                row.text:SetText(item.text or "")
                UI.SetFontColor(row.text, item.grey and "GRAY_FONT_COLOR" or "NORMAL_FONT_COLOR")
                row.sub:SetText(item.sub or "")
                row.selectedTex:SetShown(item == self.selected)
                row:Show()
            else
                row:Hide()
            end
        end
        self.empty:SetShown(#self.items == 0)
    end

    function list:Selected() return self.selected end

    return list
end

---------------------------------------------------------------------------
-- Textdialog: Hülle um ezCores Dialog (Core.TextDialog – ein Fenster für alle Module, Blizzards Rahmenvorlage,
-- gemerkte Lage, Esc schließt, Knöpfe mit Tooltip). Der eigene Rahmen von früher ist dorthin umgezogen (V-171).
-- opts: title, text, hint, accept (Knopftext; ohne nur „Schließen“), onAccept(text) (false hält den Dialog offen),
-- select (Text markieren), anchor (auslösendes Fenster; Standard: der Makro-Browser).
---------------------------------------------------------------------------

local DIALOG_MAX_LETTERS = 4000   -- wie der frühere eigene Dialog

function UI.TextDialog(opts)
    opts = opts or {}
    local browser = ns.Browser and ns.Browser.Frame and ns.Browser.Frame()
    return ezCore.TextDialog({
        title = opts.title, hint = opts.hint, text = opts.text,
        accept = opts.accept, onAccept = opts.onAccept, cancel = opts.cancel, onCancel = opts.onCancel,
        select = opts.select, readOnly = opts.readOnly,
        maxLetters = opts.maxLetters or DIALOG_MAX_LETTERS,
        owner = "ezMacro",
        -- am auslösenden Fenster verankern: ezCores Dialog dockt neben ihm an, wandert und schließt mit ihm (EC-100,
        -- ezCore/TextDialog.lua; MACRO-14)
        anchor = opts.anchor or (browser and browser:IsShown() and browser or nil),
    })
end

-- Der Rahmen des Dialogs (nil, solange noch keiner gezeigt wurde): .edit, .accept, .cancel.
function UI.Dialog()
    return ezCore.TextDialogFrame()
end
