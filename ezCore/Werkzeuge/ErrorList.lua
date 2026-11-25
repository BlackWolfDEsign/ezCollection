local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Fehlerliste zum Kopieren (Punkt 9): ein Fenster mit allen gemerkten Fehlern der ez-Module, dazu Version,
    Client und Status – markiert zum Kopieren für eine Fehlermeldung. Die Daten bleiben in Core.lua
    (Core.Errors, Core.ErrorCount, Nachricht ERRORS_CHANGED); hier nur die Anzeige.

      ezCore.ShowErrorList()      Liste zeigen (Knopf auf der Seite „ezCollection“ → Erweitert, /ez fehler kopieren):
                                  als Unterseite „Fehlerliste“ in Blizzards Einstellungsfenster, wenn der Client
                                  Canvas-Unterseiten kennt (V-024), sonst das eigene Fenster
      ezCore.ShowErrorWindow()    immer das eigene Fenster (Rückfall; auch im Kampf)
      ezCore.ErrorListText()      derselbe Text, z. B. für einen eigenen Dialog; nennt auch das Ergebnis des
                                  letzten Selbsttests (/ez test, Diagnose.lua)
      ezCore.AskClearErrors(fn)   EINE Rückfrage für alle „Leeren“-Wege (Übersicht, Fenster, Unterseite); fn() danach
      ezCore.ErrorListPage()      → Kategorie der Unterseite oder nil
    Fenster aus ezCore.NewWindow (Blizzards PortraitFrameFlatTemplate), Text in einem mehrzeiligen Eingabefeld
    im ScrollFrameTemplate; Tippen ändert nichts, Strg+C kopiert. Die Unterseite nutzt dasselbe Eingabefeld-Muster
    in einem eigenen Rahmen (Settings.RegisterCanvasLayoutSubcategory).
]]

local window, edit, text
local canvas, canvasEdit, canvasText, canvasCategory, canvasFooter

function Core.ErrorListText()
    local lines = {}
    local version, build = "", ""
    if GetBuildInfo then
        local ok, v, b = pcall(GetBuildInfo)
        if ok then version, build = tostring(v or ""), tostring(b or "") end
    end
    -- Datum je Sprache über Core.DateText (vorher fest deutsch, T10-3/T16-NZ5)
    lines[#lines + 1] = L.ERRORLIST_CLIENT:format(Core.DateText(Core.Now(), "long"), version, build)
    local status = Core.StatusLines and Core.StatusLines() or {}
    for _, line in ipairs(status) do
        lines[#lines + 1] = Core.StripColors(line)
    end
    local list = Core.Errors()
    if #list == 0 then
        -- Der Statusblock endet schon mit „Keine Fehler gemerkt.“ (Spieltest 14.11.2026: stand doppelt da);
        -- der eigene Satz kommt nur, wenn es keinen Statusblock gibt.
        if #status == 0 then lines[#lines + 1] = L.ERRORS_EMPTY end
    else
        lines[#lines + 1] = ""
        for _, e in ipairs(list) do
            lines[#lines + 1] = ("%s  %s  %s"):format(Core.DateText(e.t or 0, "full"), tostring(e.m or "?"), Core.ErrorLabel(e))
            -- Aufrufstapel an der Fehlerstelle, eingerückt (Feld s, Gesamtreview 18.11.2026, T7-2)
            if type(e.s) == "string" and e.s ~= "" then
                for line in e.s:gmatch("[^\n]+") do lines[#lines + 1] = "    " .. line end
            end
        end
    end
    -- Ergebnis des letzten Selbsttests (/ez test) – zum Mitkopieren
    local test = Core.SelfTestLines and Core.SelfTestLines()
    if test and #test > 0 then
        lines[#lines + 1] = ""
        for _, line in ipairs(test) do lines[#lines + 1] = Core.StripColors(line) end
    end
    -- Kopierfeld (EditBox) löst „|4Einzahl:Mehrzahl;“ nicht auf: hier vorher (Core.ResolveGrammar, Welle 17)
    -- eigene Namen, Realms und Gilde ersetzt: der Text geht an andere (24.11.2026, „Natürlich anonymer Export“)
    return Core.Anonymous(Core.ResolveGrammar(table.concat(lines, "\n")))
end

-- V-024: EINE Rückfrage für jedes „Fehler leeren“ (Knopf der Übersicht, Fenster, Unterseite). → Dialog
function Core.AskClearErrors(onDone)
    return Core.Confirm(L.ERRORLIST_CLEAR_CONFIRM, function()
        Core.ClearErrors()
        ns.Print(L.ERRORS_CLEARED)
        if type(onDone) == "function" then Core.Try(nil, "AskClearErrors onDone", onDone) end
    end)
end

local function RefreshCanvas()
    if not (canvas and canvasEdit and canvas.IsVisible and canvas:IsVisible()) then return end
    canvasText = Core.ErrorListText()
    canvasEdit:SetText(canvasText)
    canvasEdit:SetCursorPosition(0)
    local total, new = Core.ErrorCount()
    if canvasFooter then canvasFooter:SetText(L.ERRORLIST_FOOTER:format(total, new)) end
end

local function Refresh()
    RefreshCanvas()
    if not (window and window:IsShown()) then return end
    text = Core.ErrorListText()
    edit:SetText(text)
    edit:SetCursorPosition(0)
    local total, new = Core.ErrorCount()
    window:SetFooter(L.ERRORLIST_FOOTER:format(total, new))
end

local function SelectAll()
    edit:SetFocus()
    edit:HighlightText()
end

local function Build()
    if window then return window end
    window = Core.NewWindow("ezCoreErrorList", { title = L.ERRORLIST_TITLE, width = 600, height = 420,
        positionKey = "ezCore.errorList", default = { "CENTER", "CENTER", 0, 60 } })
    if not window then return nil end
    window:SetFrameStrata("DIALOG")
    window:HeaderButton(L.ERRORLIST_SELECT, 120, SelectAll, L.ERRORLIST_SELECT, L.ERRORLIST_SELECT_TIP)
    window:HeaderButton(L.ERRORLIST_CLEAR, 90, function() Core.AskClearErrors() end, L.ERRORLIST_CLEAR, L.OVERVIEW_ERRORS_TIP)
    window:Footer("")
    local scroll = window:Scroll()
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetPoint("TOPLEFT")
    edit:SetWidth(540)
    scroll:SetScrollChild(edit)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then edit:SetWidth(w) end end)
    -- Nur lesen: getippter Text wird sofort zurückgesetzt, Markieren und Kopieren gehen.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and text then self:SetText(text) end
    end)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    window:HookScript("OnShow", Refresh)
    return window
end

---------------------------------------------------------------------------
-- Unterseite „Fehlerliste“ in Blizzards Einstellungsfenster (V-024: Original erweitern statt eigenes Fenster)
---------------------------------------------------------------------------

local function BuildCanvas()
    local frame = CreateFrame("Frame", "ezCoreErrorListPage", UIParent)
    frame:Hide()
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 10, -12)
    title:SetText(L.ERRORLIST_TITLE)
    local function HeaderButton(label, width, onClick, tip, anchor)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        if anchor then button:SetPoint("RIGHT", anchor, "LEFT", -6, 0) else button:SetPoint("TOPRIGHT", -30, -10) end
        button:SetScript("OnClick", onClick)
        button:SetScript("OnEnter", Core.TipScript(label, tip))
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return button
    end
    local back = HeaderButton(L.SETTINGS_BACK_BUTTON, 90, function() Core.OpenSettings() end, L.SETTINGS_BACK_TO_TIP:format(Core.TITLE))
    local clear = HeaderButton(L.ERRORLIST_CLEAR, 90, function() Core.AskClearErrors() end, L.OVERVIEW_ERRORS_TIP, back)
    local select = HeaderButton(L.ERRORLIST_SELECT, 130, function()
        if canvasEdit then canvasEdit:SetFocus() canvasEdit:HighlightText() end
    end, L.ERRORLIST_SELECT_TIP, clear)
    frame.back, frame.clear, frame.select = back, clear, select
    canvasFooter = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    canvasFooter:SetPoint("BOTTOMLEFT", 10, 8)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "ScrollFrameTemplate")
    if not (ok and scroll) then scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate") end
    scroll:SetPoint("TOPLEFT", 10, -44)
    scroll:SetPoint("BOTTOMRIGHT", -30, 26)
    canvasEdit = CreateFrame("EditBox", nil, scroll)
    canvasEdit:SetMultiLine(true)
    canvasEdit:SetAutoFocus(false)
    canvasEdit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    canvasEdit:SetPoint("TOPLEFT")
    canvasEdit:SetWidth(560)
    scroll:SetScrollChild(canvasEdit)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then canvasEdit:SetWidth(w) end end)
    -- Nur lesen: getippter Text wird sofort zurückgesetzt, Markieren und Kopieren gehen.
    canvasEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and canvasText then self:SetText(canvasText) end
    end)
    canvasEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame:HookScript("OnShow", RefreshCanvas)
    frame.OnRefresh = RefreshCanvas      -- Blizzard ruft es, wenn das Einstellungsfenster aufgeht
    frame.edit, frame.scroll = canvasEdit, scroll
    return frame
end

-- Legt die Unterseite an (einmal, vor Core.RegisterSettingsParent; Collection.lua ruft es beim Bau der Übersicht).
-- → Kategorie oder nil (Client ohne Canvas-Unterseiten, Fehler beim Bau: dann bleibt das Fenster).
function Core.RegisterErrorListPage()
    if canvasCategory then return canvasCategory end
    local parent = Core.SettingsParent and Core.SettingsParent()
    if not (parent and Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    local ok, err = pcall(function()
        canvas = canvas or BuildCanvas()
        canvasCategory = Settings.RegisterCanvasLayoutSubcategory(parent, canvas, L.OVERVIEW_ERRORS)
    end)
    if not ok then
        canvasCategory = nil
        Core.Error(Core.name, err, "ErrorListPage")
    end
    return canvasCategory
end

function Core.ErrorListPage() return canvasCategory end

function Core.ShowErrorList()
    -- Unterseite in Blizzards Einstellungen, wenn es sie gibt (im Kampf lieber das eigene Fenster: Blizzards
    -- Einstellungsfenster lässt sich dann nicht verlässlich öffnen).
    if canvasCategory and not Core.InCombat() and Settings and Settings.OpenToCategory and canvasCategory.GetID then
        local ok = pcall(Settings.OpenToCategory, canvasCategory:GetID())
        if ok then
            RefreshCanvas()
            return canvas
        end
    end
    return Core.ShowErrorWindow()
end

function Core.ShowErrorWindow()
    local ok, built = pcall(Build)
    if not (ok and built) then
        window = nil
        -- ohne Fenster (sehr alter Client): einzeilig im Eingabedialog
        local flat = Core.ErrorListText():gsub("\n", " | ")
        return Core.AskText(L.ERRORLIST_TITLE, flat, nil, #flat + 10)
    end
    if window:IsShown() then Refresh() else window:Show() end
    SelectAll()
    return window
end

Core.Listen("ERRORS_CHANGED", Refresh, "ezCore")
