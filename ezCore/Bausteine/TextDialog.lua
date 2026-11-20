local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Mehrzeiliger Text-Dialog (V-171, vorher ezMacro/UI.lua „UI.TextDialog“ mit eigenem Rahmen): ein Fenster aus
    Core.NewWindow (Blizzards Rahmenvorlage, gemerkte Lage „ezCore.textDialog“, Esc schließt) mit einem mehrzeiligen
    Eingabefeld zum Einfügen, Bearbeiten oder Kopieren von Text – Export/Import, Makro als Text, Listen.

    local dialog = Core.TextDialog({
        title = "Makro als Text",          Titel des Fensters
        hint = "Mit Strg+C kopieren …",    Erklärzeile über dem Feld (umbrochen)
        text = "…",                        Anfangstext
        accept = "Übernehmen",             Text des linken Knopfs; true = Standardtext; ohne: nur „Schließen“
        onAccept = fn(text) → false        läuft bei „Übernehmen“; gibt es false zurück, bleibt der Dialog offen
        cancel = "Abbrechen",              Text des rechten Knopfs (Standard: „Abbrechen“ bzw. „Schließen“)
        onCancel = fn(),                   läuft bei „Abbrechen“, Esc und dem X (nicht nach „Übernehmen“)
        select = true,                     Text markieren (zum Kopieren)
        readOnly = true,                   Text lässt sich markieren und kopieren, aber nicht ändern
        maxLetters = 4000,                 0 = unbegrenzt (Standard)
        owner = "ezMacro",                 Modul für die Fehlerliste
        option = { text, tip, checked, onChange = fn(an) }   ein Häkchen unten links neben „Alles markieren“
                                           (EC-45: „Positionen mitnehmen“); onChange darf frame:SetText(text) rufen
        anchor = MacroFrame,               das auslösende Fenster (EC-100, „Extra-Fenster vermeiden“): Der Dialog dockt
                                           rechts daneben an (sonst links), oben bündig; passte er auf keiner Seite auf
                                           den Bildschirm, liegt er mittig über dem Träger. Er wandert mit dem Träger
                                           und schließt mit ihm (wie Abbrechen). Ohne anchor oder solange der Träger
                                           nicht sichtbar ist: die gemerkte Lage wie bisher.
    })
    Es gibt EINEN Dialog: ein neuer Aufruf ersetzt den offenen (dessen onCancel läuft dann nicht).
    Core.TextDialogFrame() → der Rahmen (nil, solange keiner gebaut wurde); frame.edit, frame.accept, frame.cancel,
    frame.hint, frame.option, frame.optionLabel, frame:GetText(), frame:SetText(text), frame:Accept(), frame:Cancel().
]]

local dialog
local current      -- opts des offenen Dialogs
local accepted     -- OnHide nach „Übernehmen“: onCancel nicht rufen

local function Report(err, where)
    Core.Error(current and current.owner or Core.name, err, where)
end

local function Tip(button, title, body)
    button:SetScript("OnEnter", Core.TipScript(title, body))
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local GAP = 4
local anchorHooked = setmetatable({}, { __mode = "k" })   -- Träger → true: OnHide schon gehookt

-- Ist der Träger ein sichtbarer Rahmen?
local function AnchorUsable(anchor)
    if Core.IsSecret(anchor) or type(anchor) ~= "table" or anchor == dialog then return false end
    if type(anchor.IsShown) ~= "function" or type(anchor.GetLeft) ~= "function" then return false end
    local ok, shown = pcall(anchor.IsShown, anchor)
    return ok and Core.Bool(shown, false)
end

-- Dialog am Träger verankern. → "right" | "left" | "center"; nil = kein brauchbarer Träger (Lage bleibt, wie sie ist)
local function PlaceAt(anchor)
    if not AnchorUsable(anchor) then return nil end
    local ok, width = pcall(dialog.GetWidth, dialog)
    width = ok and Core.Num(width) or 480
    local where = "center"
    local right, left = Core.DockRoom(dialog, anchor, "right", GAP), Core.DockRoom(dialog, anchor, "left", GAP)
    if right == nil or right >= width then
        where = "right"          -- Lage unbekannt (Träger noch nie gezeichnet): die Wunschseite
    elseif left and left >= width then
        where = "left"
    end
    dialog:ClearAllPoints()
    if where == "right" then
        dialog:SetPoint("TOPLEFT", anchor, "TOPRIGHT", GAP, 0)
    elseif where == "left" then
        dialog:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -GAP, 0)
    else
        dialog:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    if not anchorHooked[anchor] and type(anchor.HookScript) == "function" then
        anchorHooked[anchor] = true
        -- schließt der Träger, schließt der Dialog, der an ihm hängt (wie Abbrechen)
        pcall(anchor.HookScript, anchor, "OnHide", function()
            if dialog and current and current.anchor == anchor and dialog:IsShown() then dialog:Hide() end
        end)
    end
    return where
end

local function Build()
    local frame = Core.NewWindow("ezCoreTextDialog", { width = 480, height = 360,
        positionKey = "ezCore.textDialog", default = { "CENTER", "CENTER", 0, 80 } })
    if not frame then return nil end
    frame:SetFrameStrata("DIALOG")

    frame.hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
    frame.hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -32)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetJustifyV("TOP")
    frame.hint:SetWordWrap(true)

    -- Feld mit Blizzards Tooltip-Rand wie in der Makroverwaltung
    local okBg, box = pcall(CreateFrame, "Frame", nil, frame, "TooltipBackdropTemplate")
    if not (okBg and box) then box = CreateFrame("Frame", nil, frame) end
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -64)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 40)
    frame.box = box

    local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, box, "ScrollFrameTemplate")
    if not (okScroll and scroll) then okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, box, "UIPanelScrollFrameTemplate") end
    if not (okScroll and scroll) then
        -- Client ohne beide Vorlagen: schlichter Rollrahmen, das Mausrad blättert
        scroll = CreateFrame("ScrollFrame", nil, box)
        if scroll.EnableMouseWheel then
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(self, delta)
                local range = Core.Num(self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
                local now = Core.Num(self.GetVerticalScroll and self:GetVerticalScroll()) or 0
                self:SetVerticalScroll(math.max(0, math.min(range, now - (Core.Num(delta) or 0) * 30)))
            end)
        end
    end
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 8)
    frame.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetPoint("TOPLEFT")
    edit:SetWidth(410)
    scroll:SetScrollChild(edit)
    scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then edit:SetWidth(w) end end)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Nur lesen: getippter Text wird sofort zurückgesetzt, Markieren und Kopieren gehen.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and current and current.readOnly then self:SetText(frame.ezText or "") end
    end)
    -- Ansicht folgt dem Cursor (Tippen, Pfeiltasten) wie in Blizzards Makrofenster – wie vorher in ezMacros Dialog
    if okScroll and ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate and ScrollingEdit_OnTextChanged then
        edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        edit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end)
        edit:HookScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, self:GetParent()) end)
    end
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    frame.edit = edit

    frame.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.cancel:SetSize(110, Core.LAYOUT.BUTTON_H)
    frame.cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    frame.cancel:SetScript("OnClick", function() frame:Cancel() end)

    frame.accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.accept:SetSize(140, Core.LAYOUT.BUTTON_H)
    frame.accept:SetPoint("RIGHT", frame.cancel, "LEFT", -Core.LAYOUT.GAP, 0)
    frame.accept:SetScript("OnClick", function() frame:Accept() end)
    Tip(frame.accept, L.TEXTDIALOG_ACCEPT, L.TEXTDIALOG_ACCEPT_TIP)

    frame.selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAll:SetSize(130, Core.LAYOUT.BUTTON_H)
    frame.selectAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    frame.selectAll:SetText(L.TEXTDIALOG_SELECT)
    frame.selectAll:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    Tip(frame.selectAll, L.TEXTDIALOG_SELECT, L.TEXTDIALOG_SELECT_TIP)

    -- Häkchen für eine Wahl im Dialog (opts.option); ohne opts.option unsichtbar
    frame.option = Core.CreateCheck(frame, 24)
    frame.option:SetPoint("LEFT", frame.selectAll, "RIGHT", Core.LAYOUT.GAP, 0)
    -- eigene Beschriftung (die der Vorlage heißt je nach Client .text oder .Text oder fehlt)
    frame.optionLabel = frame.option:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.optionLabel:SetPoint("LEFT", frame.option, "RIGHT", 2, 0)
    frame.option:SetScript("OnClick", function(self)
        local opts = current and current.option
        if type(opts) == "table" and type(opts.onChange) == "function" then
            local ok, err = pcall(opts.onChange, self:GetChecked() == true)
            if not ok then Report(err, "TextDialog option") end
        end
    end)
    frame.option:Hide()

    function frame:GetText() return edit:GetText() or "" end

    -- Text ersetzen (auch bei readOnly), z. B. nachdem das Häkchen umgelegt wurde
    function frame:SetText(text)
        self.ezText = Core.ResolveGrammar(tostring(text or ""))     -- Eingabefeld löst „|4…;“ nicht auf (Welle 17)
        edit:SetText(self.ezText)
        edit:SetCursorPosition(0)
        if current and current.select then edit:HighlightText() end
    end

    -- „Übernehmen“: onAccept(text); false hält den Dialog offen (z. B. ungültiger Import).
    function frame:Accept()
        local opts = current
        local keep = false
        if opts and type(opts.onAccept) == "function" then
            local ok, result = pcall(opts.onAccept, self:GetText())
            if not ok then Report(result, "TextDialog") elseif result == false then keep = true end
        end
        -- onAccept hat selbst einen neuen Dialog geöffnet (z. B. Ergebnis eines Imports): der bleibt offen
        if current ~= opts then return true end
        if keep then return false end
        accepted = true
        self:Hide()
        return true
    end

    function frame:Cancel() self:Hide() end

    -- Esc, das X und „Abbrechen“ enden alle hier.
    frame:HookScript("OnHide", function()
        local opts, wasAccepted = current, accepted
        current, accepted = nil, nil
        if opts and not wasAccepted and type(opts.onCancel) == "function" then
            local ok, err = pcall(opts.onCancel)
            if not ok then Core.Error(opts.owner or Core.name, err, "TextDialog") end
        end
    end)
    return frame
end

function Core.TextDialog(opts)
    opts = opts or {}
    if not dialog then
        local ok, built = pcall(Build)
        if not (ok and built) then
            if not ok then Core.Error(opts.owner or Core.name, built, "TextDialog") end
            -- ohne Fenster (sehr alter Client): einzeilig im Eingabedialog
            local flat = tostring(opts.text or ""):gsub("\n", " | ")
            Core.AskText(opts.title or "", flat, opts.onAccept, 0)
            return nil
        end
        dialog = built
    end
    -- ein offener Dialog wird ersetzt: sein onCancel läuft nicht
    current, accepted = nil, nil
    if dialog:IsShown() then dialog:Hide() end
    current = opts

    local title = opts.title or ""
    if dialog.SetTitle then dialog:SetTitle(title) elseif dialog.TitleText then dialog.TitleText:SetText(title) end
    dialog.hint:SetText(opts.hint or "")
    dialog.ezText = Core.ResolveGrammar(tostring(opts.text or ""))   -- Eingabefeld löst „|4…;“ nicht auf (Welle 17)
    if dialog.edit.SetMaxLetters then dialog.edit:SetMaxLetters(tonumber(opts.maxLetters) or 0) end
    dialog.edit:SetText(dialog.ezText)
    dialog.edit:SetCursorPosition(0)

    local option = type(opts.option) == "table" and opts.option or nil
    dialog.option:SetShown(option ~= nil)
    if option then
        dialog.option:SetChecked(option.checked == true)
        dialog.optionLabel:SetText(option.text or "")
        Tip(dialog.option, option.text or "", option.tip)
    end

    local hasAccept = opts.accept ~= nil and opts.accept ~= false
    dialog.accept:SetShown(hasAccept)
    dialog.accept:SetText(type(opts.accept) == "string" and opts.accept or L.TEXTDIALOG_ACCEPT)
    local cancelText = opts.cancel or (hasAccept and L.TEXTDIALOG_CANCEL or L.TEXTDIALOG_CLOSE)
    dialog.cancel:SetText(cancelText)
    if hasAccept then
        Tip(dialog.cancel, cancelText, L.TEXTDIALOG_CANCEL_TIP)
    else
        Tip(dialog.cancel, cancelText, L.TEXTDIALOG_CLOSE_TIP)
    end

    dialog:Show()
    -- nach dem Zeigen: Core.NewWindow setzt beim Zeigen die gemerkte Lage, der Träger geht vor
    local placed = PlaceAt(opts.anchor)
    if not placed and dialog.ezPlaced and dialog.RestorePosition then dialog:RestorePosition() end   -- zurück zur gemerkten Lage
    dialog.ezPlaced = placed
    dialog.edit:SetFocus()
    if opts.select then dialog.edit:HighlightText() end
    return dialog
end

function Core.TextDialogFrame()
    return dialog
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5; Welle 23d, Bericht Welle 20, docs/archiv/eroerterung-datenbank.md, vom Nutzer freigegeben „zuerst
-- V1–V5“): EINE Ausgabe von Zahlen als Tabelle mit Tabulatoren, damit nicht jedes Modul eine eigene schreibt
-- (Leitlinie 2). Das Spiel schreibt keine Dateien – der Weg nach draußen ist das Kopierfeld.
---------------------------------------------------------------------------
--[[
    Core.TableText(spalten, zeilen, opts) → Text, Zahl der Zeilen
        spalten: { { key = "price", title = "Preis", personal = true, format = fn(wert, zeile) → Text } … }; ein
                 bloßer Text als Spalte ist der Titel, der Wert steht dann an derselben Stelle der Zeile (Zeilen als Listen).
                 format = "money" (Welle 26): Kupfer als Gold-Zahl mit vier Nachkommastellen (Core.GoldDecimal,
                 „1,2345“ bzw. „1.2345“ nach der Spielsprache) – eine Stelle für ezLoot, ezPanel und ezAuction
        zeilen:  { { price = 120, who = "…" } … } bzw. { { 120, "…" } … }
        opts.names = true: Spalten mit personal (Käufer, Briefpartner – Namen anderer Spieler) kommen mit; ab Werk ohne
                 (Frage E6 des Berichts: Empfehlung „nein, ab Werk ohne Namen“, der Text verlässt das Spiel)
        opts.header = false: ohne Kopfzeile
        Zellen: ganze Zahlen ohne Trennzeichen, andere mit dem Dezimalzeichen der Spielsprache (Core.Decimal, höchstens
        zwei Stellen), wahr/falsch als „ja“/„nein“; Texte ohne Farb-, Link- und Bildcodes (Core.PlainText), mit
        aufgelösten Grammatik-Kodes „|4Einzahl:Mehrzahl;“ (Core.ResolveGrammar); Tabulator und Zeilenumbruch in einer
        Zelle werden Leerzeichen. Gesperrte Werte „?“ (Leitlinie 6), fehlende bleiben leer.
    Core.CopyAsText(opts) → der Dialog: Kopierfeld (Core.TextDialog, nur lesen, markiert) mit der Tabelle.
        opts = { title, hint, columns, rows, anchor, owner, names }; gibt es Spalten mit personal, steht unten das
        Häkchen „Namen mitnehmen“ (ab Werk aus) und schreibt den Text beim Umlegen neu.
    Knöpfe „Als Text kopieren“ bauen die Module in Welle 24 (ezAuction, ezLoot, ezPanel).
]]
local function Cell(value, column, row)
    if type(column) == "table" and column.format == "money" then
        -- gesperrt bleibt gesperrt (unten „?“), fehlend bleibt leer
        if not Core.IsSecret(value) then value = Core.GoldDecimal(value) end
    elseif type(column) == "table" and type(column.format) == "function" then
        local ok, text = pcall(column.format, value, row)
        value = ok and text or value
    end
    if Core.IsSecret(value) then return "?" end
    local kind = type(value)
    if kind == "nil" then return "" end
    if kind == "boolean" then return value and L.YES or L.NO end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "?" end
        if value == math.floor(value) then return ("%d"):format(value) end
        local text = Core.Decimal(value, 2)
        local sep = L.DECIMAL_SEP or "."
        text = text:gsub("0+$", "")
        if text:sub(-#sep) == sep then text = text:sub(1, -#sep - 1) end
        return text
    end
    local text = Core.ResolveGrammar(Core.PlainText(tostring(value)))
    return (text:gsub("[\t\r\n]+", " "))
end

function Core.TableText(columns, rows, opts)
    opts = type(opts) == "table" and opts or {}
    if type(columns) ~= "table" then return "", 0 end
    local cols = {}
    for i, c in ipairs(columns) do
        if type(c) == "table" then
            if opts.names or not c.personal then cols[#cols + 1] = { key = c.key or i, title = c.title or tostring(c.key or i), def = c } end
        else
            cols[#cols + 1] = { key = i, title = tostring(c) }
        end
    end
    local lines = {}
    if opts.header ~= false then
        local head = {}
        for i, c in ipairs(cols) do head[i] = Cell(c.title) end
        lines[1] = table.concat(head, "\t")
    end
    local n = 0
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and not Core.IsSecret(row) then
            local out = {}
            for i, c in ipairs(cols) do out[i] = Cell(row[c.key], c.def, row) end
            lines[#lines + 1] = table.concat(out, "\t")
            n = n + 1
        end
    end
    return table.concat(lines, "\n"), n
end

local function HasPersonal(columns)
    for _, c in ipairs(type(columns) == "table" and columns or {}) do
        if type(c) == "table" and c.personal then return true end
    end
    return false
end

function Core.CopyAsText(opts)
    opts = type(opts) == "table" and opts or {}
    local names = opts.names == true
    local text, n = Core.TableText(opts.columns, opts.rows, { names = names, header = opts.header })
    local option
    if HasPersonal(opts.columns) then
        option = { text = L.COPYTEXT_NAMES, tip = L.COPYTEXT_NAMES_TIP, checked = names, onChange = function(on)
            local frame = Core.TextDialogFrame()
            if frame then frame:SetText((Core.TableText(opts.columns, opts.rows, { names = on, header = opts.header }))) end
        end }
    end
    return Core.TextDialog({ anchor = opts.anchor, title = opts.title or L.COPYTEXT_TITLE,
        hint = opts.hint or L.COPYTEXT_HINT:format(n), text = text, readOnly = true, select = true,
        owner = opts.owner, option = option })
end
