local _, ns = ...
local Core = ezCore

-- Bausteine für die Oberfläche, im Blizzard-Stil des Clients. Vorher in ezBag, ezChat, ezMail und ezMacro.

---------------------------------------------------------------------------
-- Eingabe- und Bestätigungsfenster (vorher ezBag/Groups.lua und ezChat/Core.lua, gleicher Code)
---------------------------------------------------------------------------

-- Rückruf je Dialog (EZCORE_TEXT, EZCORE_CONFIRM, EZCORE_CONFIRM_ALERT): die drei können gleichzeitig offen sein,
-- jeder schließt nur seinen eigenen ab. Denselben Dialog zeigt Blizzard nur einmal – der neue Aufruf ersetzt den alten.
-- Beim Ersetzen ruft Blizzard OnCancel des alten mit dem Grund "override" (StaticPopup_Show) – nach dem Eintragen des
-- neuen Rückrufs; darum noCancelOnReuse und der Grund wird übergangen (sonst löschte das Ersetzen den neuen Rückruf).
local pending = {}
local letters = 60   -- Länge für das nächste EZCORE_TEXT; OnShow läuft schon in StaticPopup_Show

local function EditBoxOf(popup)
    return popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox())
end

-- Dialoge, deren Rückruf gerade läuft: Blizzard blendet den Rahmen NACH OnAccept/OnCancel aus (StaticPopup_OnClick:
-- „if hide and which == dialog.which then dialog:Hide()“) – eine neue Frage desselben Dialogs aus dem Rückruf heraus
-- verschwände sofort wieder (Gegenprüfung D1). Core.Confirm stellt sie dann auf den nächsten Frame zurück.
local running = {}

local function Run(which, fn, ...)
    running[which] = true
    local ok, err = pcall(fn, ...)
    running[which] = nil
    if not ok then error(err, 0) end
end

local function Finish(which, text)
    local callback = pending[which]
    pending[which] = nil
    if type(callback) == "table" then callback = callback.accept end
    if callback then Run(which, callback, Core.Trim(text)) end
end

-- true, solange Blizzard den Dialog zeigt; ohne StaticPopup_Visible (ältere Clients, Prüfungen) gilt er als offen.
local function Showing(which)
    if type(StaticPopup_Visible) ~= "function" then return true end
    local ok, frame = pcall(StaticPopup_Visible, which)
    return not ok or frame ~= nil
end

-- „Nein“, Esc oder Schließen einer Rückfrage von Core.Confirm: den wartenden Eintrag leeren und opts.onCancel(grund)
-- rufen (Gesamtreview 18.11.2026, Bedarf aus ezTalent T7-NT2: „Nein“ ließ sich vorher nicht erkennen). grund = "no"
-- (Nein oder Esc), "replaced" (eine neue Frage desselben Dialogs ersetzt sie), "closed" (Core.CancelConfirm).
local function Cancel(which, reason)
    local entry = pending[which]
    pending[which] = nil
    if type(entry) == "table" and type(entry.cancel) == "function" then
        running[which] = true
        local ok, err = pcall(entry.cancel, reason)
        running[which] = nil
        if not ok then Core.Error(entry.owner or Core.name, err, "Confirm onCancel") end
    end
end

StaticPopupDialogs.EZCORE_TEXT = {
    text = "%s",
    button1 = ACCEPT or OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 60,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local box = EditBoxOf(self)
        if box then
            if box.SetMaxLetters then box:SetMaxLetters(letters) end
            box:SetText(type(data) == "string" and data or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    OnAccept = function(self)
        local box = EditBoxOf(self)
        Finish("EZCORE_TEXT", box and box:GetText())
    end,
    noCancelOnReuse = true,
    OnCancel = function(_, _, reason) if reason ~= "override" then pending.EZCORE_TEXT = nil end end,
    EditBoxOnEnterPressed = function(self)
        Finish("EZCORE_TEXT", self:GetText())
        StaticPopup_Hide("EZCORE_TEXT")
    end,
    EditBoxOnEscapePressed = function()
        pending.EZCORE_TEXT = nil
        StaticPopup_Hide("EZCORE_TEXT")
    end,
}

StaticPopupDialogs.EZCORE_CONFIRM = {
    text = "%s",
    button1 = YES or OKAY,
    button2 = NO or CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function() Finish("EZCORE_CONFIRM", "") end,
    noCancelOnReuse = true,
    OnCancel = function(_, _, reason) if reason ~= "override" then Cancel("EZCORE_CONFIRM", "no") end end,
}

-- Wie oben, mit Blizzards Warnsymbol (für Löschen und Ähnliches; vorher ein eigener Dialog in ezMail).
StaticPopupDialogs.EZCORE_CONFIRM_ALERT = {
    text = "%s",
    button1 = YES or OKAY,
    button2 = NO or CANCEL,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function() Finish("EZCORE_CONFIRM_ALERT", "") end,
    noCancelOnReuse = true,
    OnCancel = function(_, _, reason) if reason ~= "override" then Cancel("EZCORE_CONFIRM_ALERT", "no") end end,
}

-- Text abfragen: callback(text) nach „Annehmen“ (getrimmt). maxLetters Standard 60, 0 = unbegrenzt.
function Core.AskText(prompt, current, callback, maxLetters)
    pending.EZCORE_TEXT = callback
    letters = tonumber(maxLetters) or 60   -- vor dem Zeigen: OnShow setzt damit die Länge, bevor es den Text einträgt
    return StaticPopup_Show("EZCORE_TEXT", prompt, nil, current)
end

-- Ja/Nein: callback() nur bei „Ja“. opts.alert = true: mit Warnsymbol; opts.accept: Text des Ja-Knopfs (z. B. DELETE);
-- opts.onCancel(grund): bei „Nein“ oder Esc ("no"), wenn eine neue Frage desselben Dialogs diese ersetzt ("replaced")
-- oder Core.CancelConfirm sie schließt ("closed"); opts.owner: Modul für die Fehlerliste, falls onCancel wirft.
-- Aus dem Ja-Rückruf oder onCancel heraus gestellt, erscheint eine neue Frage desselben Dialogs erst im nächsten Frame
-- (Blizzard blendet den Dialog nach dem Rückruf aus); Rückgabe dann nil. Ein wartender Eintrag, dessen Dialog nicht mehr
-- zu sehen ist (etwa von StaticPopup_Hide des Moduls geschlossen), wird still verworfen statt „replaced“ zu melden.
function Core.Confirm(prompt, callback, opts)
    opts = opts or {}
    local which = opts.alert and "EZCORE_CONFIRM_ALERT" or "EZCORE_CONFIRM"
    if running[which] and C_Timer and C_Timer.After then
        C_Timer.After(0, function() Core.Confirm(prompt, callback, opts) end)
        return nil
    end
    if pending[which] and not Showing(which) then pending[which] = nil end
    if pending[which] then Cancel(which, "replaced") end
    pending[which] = { accept = function() callback() end, cancel = opts.onCancel, prompt = prompt, owner = opts.owner }
    StaticPopupDialogs[which].button1 = opts.accept or YES or OKAY
    return StaticPopup_Show(which, prompt)
end

-- Rückfrage gezielt schließen (Gesamtreview 18.11.2026, Gegenprüfung P2: ezBag suchte dafür ezCores Dialog selbst):
-- schließt Core.Confirm nur, solange er noch genau diese Frage zeigt, leert den wartenden Rückruf (ein späteres „Ja“
-- tut nichts mehr) und ruft opts.onCancel("closed"). → true, wenn geschlossen; false, wenn die Frage nicht (mehr) offen
-- ist oder eine andere dort steht.
function Core.CancelConfirm(prompt)
    if Core.IsSecret(prompt) or prompt == nil then return false end
    for _, which in ipairs({ "EZCORE_CONFIRM", "EZCORE_CONFIRM_ALERT" }) do
        local entry = pending[which]
        if type(entry) == "table" and not Showing(which) then
            pending[which] = nil   -- veraltet: der Dialog ist schon zu (Gegenprüfung D1)
        elseif type(entry) == "table" and entry.prompt == prompt then
            Cancel(which, "closed")
            if type(StaticPopup_Hide) == "function" then pcall(StaticPopup_Hide, which) end
            return true
        end
    end
    return false
end

--[[
    Blizzards Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc, …OnEnter, …OnLeave; vorher in neun Modulen
    gleich gebaut): liefert die drei Funktionen Klick, Betreten, Verlassen.

    Ein Verhalten für alle Module (Entscheidung 5 vom 18.11.2026; Gesamtreview T18-3, T16-10, T18-4):
      Core.CompartmentHandlers({ ns = ns, main = fn(), mainText = "Fenster öffnen", title = … })
        Linksklick = main (Fenster bzw. Hauptfunktion des Moduls), Rechtsklick = Einstellungen des Moduls; ohne main
        öffnet jeder Klick die Einstellungen. Lassen sich die Einstellungen nicht öffnen (keine Seite), kommt die Hilfe.
        Der Tooltip entsteht selbst, in einer Form: Titel (Standard: Name des Moduls), „Linksklick: <mainText>“ und
        „Rechtsklick: Einstellungen“ (ohne main: „Klick: Einstellungen“), dann „Befehl: /x (/x hilfe …)“ mit dem
        geltenden Befehl (Core.SlashCmd – nie ein Kurzbefehl, der einem anderen Addon gehört). opts.extraLines: weitere
        Zeilen vor der Befehlszeile (Text, Liste oder fn → Text | Liste), etwa „Umschalt-Klick: …“ über Core.ClickText.
      Alte Form (bis D2 die Module umstellt): opts.title, opts.lines = { … } | fn → Liste, opts.onClick(button).
    Format (T18-11, design-system 2.7): Titel weiß, Klick- und Befehlszeilen grün wie Blizzards Hinweiszeilen
    (GameTooltip_AddInstructionLine). Ein Fehler im Klick landet in der Fehlerliste von opts.owner bzw. des Moduls.
]]
local function CompartmentLines(opts)
    local mns = type(opts.ns) == "table" and opts.ns or nil
    local lines = opts.lines
    if type(lines) == "function" then
        local ok, result = pcall(lines)
        lines = ok and result or nil
    end
    if type(lines) == "table" then return lines end
    local L = Core.L
    lines = {}
    if type(opts.main) == "function" then
        lines[#lines + 1] = L.COMPARTMENT_LEFT_MAIN:format(tostring(opts.mainText or ""))
        lines[#lines + 1] = L.COMPARTMENT_RIGHT_SETTINGS
    else
        lines[#lines + 1] = L.COMPARTMENT_SETTINGS
    end
    local extra = opts.extraLines
    if type(extra) == "function" then
        local ok, result = pcall(extra)
        extra = ok and result or nil
    end
    if type(extra) == "string" then extra = { extra } end
    for _, line in ipairs(type(extra) == "table" and extra or {}) do lines[#lines + 1] = line end
    if mns then
        local cmd = Core.SlashCmd(mns)
        lines[#lines + 1] = L.COMPARTMENT_HELP:format(cmd, cmd)
    end
    return lines
end

local function OpenModuleSettings(mns)
    if not Core.OpenedOrDeferred(function() return mns.OpenSettings and mns.OpenSettings() end) then
        if type(mns.PrintHelp) == "function" then mns.PrintHelp() end
    end
end

function Core.CompartmentHandlers(opts)
    opts = opts or {}
    local mns = type(opts.ns) == "table" and opts.ns or nil
    local owner = opts.owner or (mns and mns.moduleName) or Core.name
    local onClick = opts.onClick
    if onClick == nil and mns then
        onClick = function(button)
            if button ~= "RightButton" and type(opts.main) == "function" then return opts.main(button) end
            return OpenModuleSettings(mns)
        end
    end
    local function Click(_, button)
        if onClick then
            local ok, err = pcall(onClick, button)
            if not ok then Core.Error(owner, err, "Addon-Fach") end
        end
    end
    local function Enter(_, frame)
        if type(frame) ~= "table" then return end
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
        Core.TipTitle(GameTooltip, opts.title or (mns and mns.moduleName) or "")
        for _, line in ipairs(CompartmentLines(opts)) do Core.TipClick(GameTooltip, line) end
        GameTooltip:Show()
    end
    local function Leave() GameTooltip:Hide() end
    return Click, Enter, Leave
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

-- Methode eines Rahmens geschützt lesen: Zahl oder nil (fehlt, Fehler, gesperrt).
local function FrameNumber(frame, method)
    local fn = Core.Peek(frame, method)            -- geschützt gelesen: fremde Rahmen können beim Lesen werfen
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if not ok then return nil end
    return Core.Num(value)
end

-- Bildschirm in Bildschirm-Punkten (Wert × effektive Skala): Breite, Höhe; nil, solange UIParent keine Lage hat.
local function ScreenSize()
    local parent = rawget(_G, "UIParent")
    local scale = FrameNumber(parent, "GetEffectiveScale")
    local width, height = FrameNumber(parent, "GetWidth"), FrameNumber(parent, "GetHeight")
    if not (scale and width and height) or width <= 0 or height <= 0 then return nil end
    return width * scale, height * scale
end

Core.TIP_TOP_ROOM = 160      -- so viel Platz braucht ein Tooltip über seinem Besitzer (Bildschirm-Punkte)
Core.TIP_WRAP_CHARS = 48     -- längere Titel brechen um

-- Seite für einen Tooltip nach der Lage des Besitzers (FP-08; Spieltest: der Tooltip der Rotationsliste am Zauberbuch
-- ragte über den rechten Bildschirmrand): rechte Bildschirmhälfte » nach links, zu nah am oberen Rand » nach unten.
-- → "ANCHOR_RIGHT" | "ANCHOR_LEFT" | "ANCHOR_BOTTOMRIGHT" | "ANCHOR_BOTTOMLEFT"; ohne bekannte Lage "ANCHOR_RIGHT".
function Core.TipAnchor(owner)
    local screenW, screenH = ScreenSize()
    local scale = FrameNumber(owner, "GetEffectiveScale")
    local left, right, top = FrameNumber(owner, "GetLeft"), FrameNumber(owner, "GetRight"), FrameNumber(owner, "GetTop")
    if not (screenW and scale and left and right) then return "ANCHOR_RIGHT" end
    local toLeft = (left + right) / 2 * scale > screenW / 2
    local below = top ~= nil and top * scale > screenH - Core.TIP_TOP_ROOM
    if below then return toLeft and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT" end
    return toLeft and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

--[[
    Tooltip-Zeilen in den Rollen von Core.Style – EIN Format für alle Tooltips (Gesamtreview 18.11.2026, T18-10,
    T18-11; design-system 2.7), wie Blizzards eigene Helfer (SharedTooltipTemplates):
      Core.TipTitle(tooltip, titel)          Titel weiß (HIGHLIGHT_FONT_COLOR, wie GameTooltip_SetTitle); lange Titel
                                             brechen um (Core.TIP_WRAP_CHARS)
      Core.TipText(tooltip, text)            Beschreibung gold (NORMAL_FONT_COLOR, wie GameTooltip_AddNormalLine),
                                             umbrochen
      Core.TipLine(tooltip, text, rolle, umbrechen)   Zeile in einer Rolle aus Core.Style.COLOR ("normal",
                                             "highlight", "good", "bad", "warn" …) oder "hint" (Quelle und Hinweis in
                                             ezCores Grau Core.GREY, Farbcode im Text); unbekannte Rolle: weiß. Vorher
                                             als ns.TipLine nur in ezCraft.
      Core.TipDoubleLine(tooltip, links, rechts, rolleLinks, rolleRechts)
      Core.TipClick(tooltip, text)           Klick- und Befehlshinweis grün (GREEN_FONT_COLOR, wie Blizzards
                                             GameTooltip_AddInstructionLine), umbrochen – vorher Gold, Grau oder Grün
                                             je Modul, teils im selben Tooltip
    Gesperrte Werte (Leitlinie 6) gehen unverändert weiter; nil zeichnet nichts. An AddLine gehen nur r, g, b – der
    vierte Wert von Style.Color (das Farbobjekt) käme sonst als „umbrechen“ an.
]]
local function RoleRGB(role)
    local Style = Core.Style
    local r, g, b
    if type(Style) == "table" and type(Style.Color) == "function" then
        r, g, b = Style.Color(role ~= "hint" and role or "highlight")
        if type(r) ~= "number" then r, g, b = Style.Color("highlight") end
    end
    if type(r) ~= "number" then r, g, b = 1, 1, 1 end
    return r, g, b
end

-- r, g, b einer Rolle – genau drei Werte für AddLine, AddMessage, SetText und SetTextColor (Gesamtreview 18.11.2026,
-- T16-5; vorher je eine Kopie in ezBag ns.TipRGB und ezChat ns.RGB). Rollen aus Core.Style.COLOR; "hint" (auch "grey")
-- ist ezCores Grau Core.GREY, dasselbe wie Core.Grey im Text; unbekannte Rolle: Weiß.
local hintRGB
function Core.RoleRGB(role)
    if role == "hint" or role == "grey" then
        if not hintRGB then
            local r, g, b = tostring(Core.GREY or ""):match("^|c%x%x(%x%x)(%x%x)(%x%x)")
            if r then hintRGB = { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 } end
        end
        if hintRGB then return hintRGB[1], hintRGB[2], hintRGB[3] end
        role = "gray"
    end
    return RoleRGB(role)
end

local function RoleText(text, role)
    -- Leitlinie 6: zuerst IsSecret, nie einen gesperrten Wert mit nil vergleichen
    if role == "hint" and not Core.IsSecret(text) and text ~= nil then return Core.Grey(text) end
    return text
end

function Core.TipLine(tooltip, text, role, wrap)
    if type(tooltip) ~= "table" or (not Core.IsSecret(text) and text == nil) then return end
    local r, g, b = RoleRGB(role)
    tooltip:AddLine(RoleText(text, role), r, g, b, wrap == true)
end

function Core.TipDoubleLine(tooltip, left, right, leftRole, rightRole)
    if type(tooltip) ~= "table" then return end
    local r1, g1, b1 = RoleRGB(leftRole)
    local r2, g2, b2 = RoleRGB(rightRole)
    tooltip:AddDoubleLine(RoleText(left, leftRole), RoleText(right, rightRole), r1, g1, b1, r2, g2, b2)
end

function Core.TipTitle(tooltip, title)
    if type(tooltip) ~= "table" then return end
    local long = false
    if type(title) == "string" and not Core.IsSecret(title) then
        long = (strlenutf8 and strlenutf8(title) or #title) > Core.TIP_WRAP_CHARS
    end
    local r, g, b = RoleRGB("highlight")
    if long then tooltip:SetText(title, r, g, b, 1, true) else tooltip:SetText(title, r, g, b) end
end

function Core.TipText(tooltip, text) return Core.TipLine(tooltip, text, "normal", true) end
function Core.TipClick(tooltip, text) return Core.TipLine(tooltip, text, "good", true) end

-- Tooltip mit weißem Titel und goldenem, umbrochenem Text (Core.TipTitle, Core.TipText); TipScript liefert dasselbe
-- als OnEnter-Skript. Ohne anchor wählt Core.TipAnchor die Seite nach dem Platz; ein genannter Anker gilt unverändert.
-- Lange Titel brechen um (der Text darunter immer), damit der Tooltip nicht über den Bildschirm hinaus wächst.
function Core.ShowTip(owner, title, body, anchor)
    GameTooltip:SetOwner(owner, anchor or Core.TipAnchor(owner))
    Core.TipTitle(GameTooltip, title)
    if body then Core.TipText(GameTooltip, body) end
    GameTooltip:Show()
end

function Core.TipScript(title, body, anchor)
    return function(self) Core.ShowTip(self, title, body, anchor) end
end

--[[
    Breiter Tooltip mit Abständen für lange Beschreibungen (Vorlagen in der Talentvorschau, Rotationsvorlagen im
    Zauberbuch): Ein Tooltip, dessen Titel kurz ist und dessen Text ganz umbricht, wird sonst so schmal wie der Titel
    und sehr lang.
      Core.TIP_WIDE = 320                     Mindestbreite in Punkten
      Core.TipWide(tooltip, breite)           setzt die Mindestbreite (Blizzards SetMinimumWidth); sie gilt bis zum
                                              nächsten Leeren (OnTooltipCleared) oder Schließen des Tooltips und wird
                                              dann auf 0 zurückgesetzt – nur, wenn ezCore sie gesetzt hat
      Core.TipSections(tooltip, abschnitte)   Abschnitte untereinander, je ein umbrochener Text mit einer Leerzeile
                                              dazwischen (Core.Tooltip.Gap): abschnitte = Text (jede Zeile ein
                                              Abschnitt) oder Liste aus Texten bzw. { text, rolle } (Rolle wie
                                              Core.TipLine, Standard "normal") → Zahl der Abschnitte
      Core.ShowWideTip(besitzer, titel, abschnitte, anker)   wie Core.ShowTip, nur breit und mit Abschnitten
]]
Core.TIP_WIDE = 320
local wideSet = setmetatable({}, { __mode = "k" })       -- [tooltip] = true: Mindestbreite von ezCore gesetzt
local wideWatched = setmetatable({}, { __mode = "k" })

local function ResetWide(tooltip)
    if not wideSet[tooltip] then return end
    wideSet[tooltip] = nil
    if type(tooltip.SetMinimumWidth) == "function" then pcall(tooltip.SetMinimumWidth, tooltip, 0) end
end

function Core.TipWide(tooltip, width)
    if type(tooltip) ~= "table" or type(tooltip.SetMinimumWidth) ~= "function" then return false end
    if not wideWatched[tooltip] and type(tooltip.HookScript) == "function" then
        wideWatched[tooltip] = true
        pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", ResetWide)
        pcall(tooltip.HookScript, tooltip, "OnHide", ResetWide)
    end
    local ok = pcall(tooltip.SetMinimumWidth, tooltip, tonumber(width) or Core.TIP_WIDE)
    if ok then wideSet[tooltip] = true end
    return ok
end

function Core.TipSections(tooltip, sections)
    if type(tooltip) ~= "table" then return 0 end
    local list = sections
    if Core.IsSecret(sections) then
        list = { sections }
    elseif type(sections) == "string" then
        list = {}
        for part in (sections .. "\n"):gmatch("(.-)\n") do
            if part:match("%S") then list[#list + 1] = part end
        end
    end
    if type(list) ~= "table" then return 0 end
    local count = 0
    for _, section in ipairs(list) do
        local text, role = section, "normal"
        if not Core.IsSecret(section) and type(section) == "table" then text, role = section[1], section[2] or "normal" end
        if Core.IsSecret(text) or (type(text) == "string" and text ~= "") then
            if count > 0 then
                if not (Core.Tooltip and Core.Tooltip.Gap and Core.Tooltip.Gap(tooltip)) then
                    if not (Core.Tooltip and Core.Tooltip.LineBlank and Core.Tooltip.LineBlank(tooltip)) then
                        tooltip:AddLine(" ")
                    end
                end
            end
            Core.TipLine(tooltip, text, role, true)
            count = count + 1
        end
    end
    return count
end

function Core.ShowWideTip(owner, title, sections, anchor)
    GameTooltip:SetOwner(owner, anchor or Core.TipAnchor(owner))
    Core.TipTitle(GameTooltip, title)
    Core.TipWide(GameTooltip)
    Core.TipSections(GameTooltip, sections)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Gemeinsame Texte der Oberfläche (Gesamtreview 18.11.2026, P13): Klick-Hinweise, Wege zu Einstellungen und zur
-- Tastaturbelegung, Kampfsperre – je ein Wortlaut aus Core.L statt vieler eigener Formen in den Modulen
---------------------------------------------------------------------------

--[[
    Core.ClickText(taste, zusatz, text) → „Umschalt-Linksklick: alles nehmen“ (T18-9)
      taste   "left" | "right" | "middle" | nil (einfach „Klick“)
      zusatz  "SHIFT" | "CTRL" | "ALT" | "META", mehrere als "SHIFT-CTRL" oder Liste; Reihenfolge Umschalt, Strg, Alt
              wie Blizzards Klick-Zauber (Core.L.CLICK_MOD_*: „Umschalt“, nie „Shift“); verbunden mit „-“
      text    die Wirkung; ohne text nur die Taste („Umschalt-Klick“)
    Unbekannte Zusatztasten fallen weg. Englisch beginnt die Zeile groß („Shift-left-click: …“).
]]
local CLICK_MOD_ORDER = { "SHIFT", "CTRL", "ALT", "META" }
function Core.ClickText(button, mods, text)
    local L = Core.L
    local wanted = {}
    if type(mods) == "string" then
        for part in mods:upper():gmatch("[^%-%+%s]+") do wanted[part] = true end
    elseif type(mods) == "table" then
        for _, part in ipairs(mods) do if type(part) == "string" then wanted[part:upper()] = true end end
    end
    local parts = {}
    for _, key in ipairs(CLICK_MOD_ORDER) do
        if wanted[key] then parts[#parts + 1] = L["CLICK_MOD_" .. key] end
    end
    local hint = L["CLICK_HINT_" .. tostring(button or "any")]
    if type(hint) ~= "string" or hint == "CLICK_HINT_" .. tostring(button) then hint = L.CLICK_HINT_any end
    parts[#parts + 1] = hint
    local label = table.concat(parts, "-"):gsub("^%l", string.upper)
    if Core.IsSecret(text) or text == nil or text == "" then return label end
    return L.CLICK_HINT_LINE:format(label, tostring(text))
end

--[[
    Core.SettingsPathText(modul, abschnitt, option) → „Einstellung: Esc » Optionen » AddOns » ezCollection » ezGear »
      Erweitert » „Status“.“ (T18-18) – eine Form für jeden Weg zu einer Einstellung, auf Basis von L.OPTIN_WHERE.
      modul     Name der Seite („ezGear“); ohne oder „ezCollection“: die Übersichtsseite selbst
      abschnitt Überschrift: Text oder Schlüssel in Core.L („SETTINGS_ADVANCED“) bzw. in den Texten des Moduls
      option    Name der Einstellung: Text oder Schlüssel („OPT_…“); so veraltet der Weg nicht beim Umbenennen
      texts     (5. Wert, freiwillig) Texte des Moduls (ns.L), in denen Schlüssel zuerst gesucht werden
    Core.KeyBindPathText(gruppe) → „Tastaturbelegung: Esc » Optionen » Tastaturbelegung » AddOns » <gruppe>.“ – der eine
      Weg zu Blizzards Tastaturbelegung (Standard: ezCollection; vorher „Esc » Tastaturbelegung“ und andere Formen).
]]
local function Label(value, texts)
    if Core.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    local function From(t)
        if type(t) ~= "table" then return nil end
        local found = t[value]
        if type(found) == "string" and found ~= value then return found end
        return nil
    end
    return From(texts) or From(Core.L) or value
end

function Core.SettingsPathText(module, section, option, texts)
    local parts = {}
    local page = Label(module, texts)
    if page and page ~= Core.TITLE then parts[#parts + 1] = page end
    local head = Label(section, texts)
    if head then parts[#parts + 1] = head end
    local name = Label(option, texts)
    if name then parts[#parts + 1] = Core.L.SETTINGS_PATH_OPTION:format(name) end
    if #parts == 0 then parts[1] = Core.L.SETTINGS_GENERAL end
    -- L.OPTIN_WHERE nennt den Weg bis „ezCollection »“ selbst
    return Core.L.OPTIN_WHERE:format(table.concat(parts, " » "))
end

function Core.KeyBindPathText(group)
    local name = (not Core.IsSecret(group) and type(group) == "string" and group ~= "") and group or Core.TITLE
    return Core.L.KEYBIND_WHERE:format(name)
end

--[[
    Core.CombatNotice(mns, was, art, opts) → der gezeigte Text (T18-1)
      Eine Meldung für Aktionen, die im Kampf gesperrt sind, statt rund 30 eigener Wortlaute:
        art "blocked" (Standard): „<was> geht im Kampf nicht – bitte nach dem Kampf noch einmal.“
        art "later":              „<was> kommt gleich nach dem Kampf.“ (vorgemerkt, z. B. über Core.AfterCombat)
      Ohne was: der allgemeine Satz (L.SETTINGS_COMBAT_BLOCKED bzw. L.COMBAT_NOTICE_LATER_ANY).
      Ausgabe im Chat über mns.Print (Präfix des Moduls); mns darf auch der Name des Moduls sein (Core.Print(name, …),
      etwa opts.owner eines ezCore-Dienstes), ohne Modul ezCollection. opts.center = true zeigt den Satz zusätzlich oben
      in der Bildschirmmitte (Core.ErrorMessage in der Rolle „warn“, T18-23); opts.chat = false lässt den Chat weg (nur
      mit opts.center sinnvoll – Hinweise, die schon bisher nur in der Mitte standen: Fenster öffnen, Klick-Belegung).
    Core.CombatText(was, art) → derselbe Satz ohne Ausgabe – für Tooltips, Statuszeilen und Gründe, die das Modul selbst
      zeigt (vorher je eine Kopie in ezBag ns.CombatText, ezCraft Sal.CombatText, ezHeal, ezMacro und ezTalent).
]]
function Core.CombatText(what, kind)
    local L = Core.L
    if Core.IsSecret(what) or what == "" then what = nil end
    if kind == "later" then
        return what and L.COMBAT_NOTICE_LATER:format(tostring(what)) or L.COMBAT_NOTICE_LATER_ANY
    end
    return what and L.COMBAT_NOTICE_BLOCKED:format(tostring(what)) or L.SETTINGS_COMBAT_BLOCKED
end

function Core.CombatNotice(mns, what, kind, opts)
    local text = Core.CombatText(what, kind)
    opts = type(opts) == "table" and opts or nil
    if not (opts and opts.chat == false) then
        if type(mns) == "table" and type(mns.Print) == "function" then
            mns.Print(text)
        elseif type(mns) == "string" and not Core.IsSecret(mns) and mns ~= "" then
            Core.Print(mns, text)
        else
            Core.Print(Core.TITLE, text)
        end
    end
    if opts and opts.center then Core.ErrorMessage(text, "warn") end
    return text
end

--[[
    Core.Word(name) → Blizzards Standardwort für Knöpfe (globaler Text des Clients: CLOSE „Schließen“, CANCEL
      „Abbrechen“, DELETE „Löschen“, OKAY, ACCEPT, YES, NO …), fehlt es (älterer Client, gesperrt, leer): ezCores eigener
      Text L.WORD_<name> in der Sprache des Spiels, sonst der Name selbst (Gesamtreview 18.11.2026, Wunsch aus ezAuction,
      ezMail und ezMerchant; vorher je eigene Rückfälle wie ezAuction ns.Word, „DELETE or L.DELETE“).
]]
function Core.Word(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return name end
    local text = rawget(_G, name)
    if type(text) == "string" and not Core.IsSecret(text) and text ~= "" then return text end
    local own = Core.L["WORD_" .. name]   -- fehlt der Schlüssel, liefert Core.L den Schlüssel selbst
    if type(own) == "string" and own ~= "" and own ~= "WORD_" .. name then return own end
    return name
end

--[[
    Core.NewTimerBar(parent, opts) → Zeitbalken (T9-8): ein Baustein für Flugleiste, Schlachtfeld-Timer und Restzeit-
      Leisten statt dreier Nachbauten. Blizzards Statusleisten-Textur (UI-StatusBar) auf halbdunklem Grund, Farbe aus
      einer Rolle von Core.Style (Standard „normal“, Gold), Text in der Schrift-Rolle „text“ (GameFontHighlightSmall).
      opts = { width, height (Standard 13), role = "normal", border = true (Rand der Zauberleiste,
               UI-CastingBar-Border, wie die Flugleiste), font = Schrift-Rolle (Standard "text"), name (globaler Name) }
      bar:SetTime(rest, gesamt)   füllt den Balken (0 bis gesamt) und schreibt die Restzeit (Core.Duration) als Text
      bar:SetRole(rolle)          Farbe wechseln (z. B. „bad“ kurz vor dem Ende)
      bar.Text                    die Textzeile (eigener Text: bar.Text:SetText(…))
    Lage, Tooltip, Klick und Verschieben bleiben beim Modul (Rahmen-Lage über Core.Mover oder am Blizzard-Fenster).
]]
Core.TIMER_BAR = { height = 13, bg = 0.5 }
function Core.NewTimerBar(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("StatusBar", opts.name, parent)
    bar:SetSize(opts.width or 195, opts.height or Core.TIMER_BAR.height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, Core.TIMER_BAR.bg)
    bar.Background = bg
    if opts.border then
        local border = bar:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
        border:SetSize(256, 64)
        border:SetPoint("TOP", bar, "TOP", 0, 28)
        bar.Border = border
    end
    bar.Text = bar:CreateFontString(nil, "OVERLAY")
    if not (Core.Style and Core.Style.SetFont(bar.Text, opts.font or "text")) then
        bar.Text:SetFontObject("GameFontHighlightSmall")
    end
    bar.Text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    function bar:SetRole(role)
        local r, g, b = RoleRGB(role or "normal")
        self:SetStatusBarColor(r, g, b)
        self.role = role or "normal"
    end
    function bar:SetTime(rest, total)
        rest, total = Core.Num(rest), Core.Num(total)
        if not rest then
            self:SetValue(0)
            self.Text:SetText("")
            return
        end
        if total and total > 0 then
            self:SetMinMaxValues(0, total)
            self:SetValue(math.max(0, math.min(rest, total)))
        end
        self.Text:SetText(Core.Duration(math.max(0, rest), true))
    end
    bar:SetRole(opts.role)
    return bar
end

---------------------------------------------------------------------------
-- Häkchen und Seitenreiter (vorher ezMail)
---------------------------------------------------------------------------

-- Häkchen im Blizzard-Stil. Fehlt die Vorlage auf einem Client, entsteht es aus Blizzards Texturen.
function Core.CreateCheck(parent, size)
    local ok, check = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not check then
        check = CreateFrame("CheckButton", nil, parent)
        check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    end
    check:SetSize(size, size)
    check:SetHitRectInsets(0, 0, 0, 0)
    return check
end

---------------------------------------------------------------------------
-- Seitenreiter-Stapel (V-168): Reiter verschiedener Module am selben Blizzard-Fenster ordnen sich über eine
-- Reihenfolge-Zahl selbst untereinander. Kein Modul muss mehr wissen, welches andere dort einen Reiter hat.
---------------------------------------------------------------------------

Core.SideTabs = Core.SideTabs or {}
local SideTabs = Core.SideTabs
-- Standard: erster Reiter 70 unter der Oberkante (wie im Zauberbuch) bzw. 40 über der Unterkante, alle 44 der nächste
-- (32 hoch + 12 Abstand); order ohne Angabe 100.
SideTabs.TOP, SideTabs.BOTTOM, SideTabs.STEP, SideTabs.ORDER = -70, 40, 44, 100

local stacks = setmetatable({}, { __mode = "k" })   -- [Fenster] = { top = Stapel, bottom = Stapel }
local tabStack = setmetatable({}, { __mode = "k" }) -- [Reiter] = { anchor, from, entry }

local function Stack(anchor, from, create)
    local both = stacks[anchor]
    if not both then
        if not create then return nil end
        both = {}
        stacks[anchor] = both
    end
    if not both[from] and create then both[from] = { tabs = {} } end
    return both[from]
end

local function SortTabs(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return tostring(a.key) < tostring(b.key)
end

-- Sichtbare Reiter des Fensters lückenlos anordnen (von oben bzw. unten). → Anzahl gesetzter Reiter.
-- from ohne Angabe: beide Seiten. Läuft von selbst, wenn ein Reiter dazukommt, erscheint oder verschwindet.
function SideTabs.Layout(anchor, from)
    if from == nil then
        return SideTabs.Layout(anchor, "top") + SideTabs.Layout(anchor, "bottom")
    end
    local stack = Stack(anchor, from, false)
    if not stack then return 0 end
    table.sort(stack.tabs, SortTabs)
    local bottom = from == "bottom"
    local start = stack.start or (bottom and SideTabs.BOTTOM or SideTabs.TOP)
    local step = stack.step or SideTabs.STEP
    local placed = 0
    for _, entry in ipairs(stack.tabs) do
        local tab = entry.tab
        if tab:IsShown() then
            tab:ClearAllPoints()
            if bottom then
                entry.y = start + placed * step
                tab:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", stack.x or 0, entry.y)
            else
                entry.y = start - placed * step
                tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", stack.x or 0, entry.y)
            end
            placed = placed + 1
        else
            entry.y = nil
        end
    end
    return placed
end

--[[
    SideTabs.Add(tab, anchor, opts) – einen (eigenen) Reiter in den Stapel des Fensters aufnehmen. → tab
      opts.key     eindeutiger Name ("ezMail.history"); bei gleicher order entscheidet er (Namensfolge)
      opts.order   Reihenfolge-Zahl, kleiner = weiter oben (bei from = "bottom": weiter unten). Standard 100
      opts.from    "top" (Standard) | "bottom"
      opts.start, opts.step, opts.x   Lage des ersten Reiters, Abstand, waagerechter Versatz – gilt für den ganzen
                   Stapel; der erste, der es angibt, legt es fest (Standard SideTabs.TOP/BOTTOM/STEP, 0)
    Der Reiter gehört weiter dem Modul (Icon, Klick, Tooltip, Show/Hide); der Stapel setzt nur seine Anker.
]]
function SideTabs.Add(tab, anchor, opts)
    opts = opts or {}
    if type(tab) ~= "table" or type(anchor) ~= "table" then return tab end
    SideTabs.Remove(tab)
    local from = opts.from == "bottom" and "bottom" or "top"
    local stack = Stack(anchor, from, true)
    if stack.start == nil and tonumber(opts.start) then stack.start = tonumber(opts.start) end
    if stack.step == nil and tonumber(opts.step) then stack.step = tonumber(opts.step) end
    if stack.x == nil and tonumber(opts.x) then stack.x = tonumber(opts.x) end
    local entry = { tab = tab, key = opts.key or ("tab" .. (#stack.tabs + 1)), order = tonumber(opts.order) or SideTabs.ORDER,
        owner = opts.owner }
    stack.tabs[#stack.tabs + 1] = entry
    local known = tabStack[tab]
    tabStack[tab] = { anchor = anchor, from = from, entry = entry, hooked = known and known.hooked }
    if not (known and known.hooked) and tab.HookScript then
        tabStack[tab].hooked = true
        local function Relayout()
            local where = tabStack[tab]
            if where and where.anchor then SideTabs.Layout(where.anchor, where.from) end
        end
        tab:HookScript("OnShow", Relayout)
        tab:HookScript("OnHide", Relayout)
    end
    SideTabs.Layout(anchor, from)
    return tab
end

-- Reiter aus seinem Stapel nehmen (die anderen rücken nach). → true, wenn er in einem stand.
function SideTabs.Remove(tab)
    local where = tabStack[tab]
    if not (where and where.anchor) then return false end
    local stack = Stack(where.anchor, where.from, false)
    for i = #(stack and stack.tabs or {}), 1, -1 do
        if stack.tabs[i].tab == tab then table.remove(stack.tabs, i) end
    end
    local anchor, from = where.anchor, where.from
    where.anchor, where.entry = nil, nil
    SideTabs.Layout(anchor, from)
    return true
end

-- Reihenfolge-Zahl nachträglich ändern (z. B. aus einer Einstellung). → true, wenn der Reiter im Stapel steht.
function SideTabs.SetOrder(tab, order)
    local where = tabStack[tab]
    if not (where and where.entry) then return false end
    where.entry.order = tonumber(order) or SideTabs.ORDER
    SideTabs.Layout(where.anchor, where.from)
    return true
end

-- Reiter eines Fensters in ihrer Reihenfolge: { { key, order, owner, tab, shown, y } … } (y nur für sichtbare).
function SideTabs.List(anchor, from)
    from = from == "bottom" and "bottom" or "top"
    local stack = Stack(anchor, from, false)
    local list = {}
    if not stack then return list end
    table.sort(stack.tabs, SortTabs)
    for i, entry in ipairs(stack.tabs) do
        list[i] = { key = entry.key, order = entry.order, owner = entry.owner, tab = entry.tab,
            shown = entry.tab:IsShown() and true or false, y = entry.y }
    end
    return list
end

-- Seitenreiter rechts am Fenster wie in Blizzards Zauberbuch (RightSideTabTemplate), hier als Knopf:
-- er rastet nicht ein. Icon, Zahl unten rechts (Count), Klick und Tooltip setzt der Aufrufer.
-- opts (freiwillig): { key, order, anchor, from, start, step, x, owner } – dann nimmt ihn der Seitenreiter-Stapel
-- des Fensters auf (SideTabs.Add; anchor ohne Angabe = parent) und setzt seine Lage. Ohne opts wie bisher: die Lage
-- setzt der Aufrufer.
function Core.CreateSideTab(parent, opts)
    local tab = Core.BuildSideTab(parent)
    if type(opts) == "table" then SideTabs.Add(tab, opts.anchor or parent, opts) end
    return tab
end

-- Nur der Knopf (intern; Module rufen Core.CreateSideTab).
function Core.BuildSideTab(parent)
    local ok, tab = pcall(CreateFrame, "CheckButton", nil, parent, "RightSideTabTemplate")
    if not ok or not tab then tab = CreateFrame("CheckButton", nil, parent) end
    tab:SetSize(32, 32)
    if not tab.Icon then
        local border = tab:CreateTexture(nil, "BORDER")
        border:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        border:SetSize(64, 64)
        border:SetPoint("TOPLEFT", -3, 11)
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetSize(30, 30)
        tab.Icon:SetPoint("CENTER")
        tab.Icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
        tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    tab.Count = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    tab.Count:SetPoint("BOTTOMRIGHT", -1, 2)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    return tab
end

-- Klick-Skript für einen Seitenreiter: Häkchen sofort wieder lösen, dann fn.
function Core.SideTabClick(fn)
    return function(self, ...)
        self:SetChecked(false)
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        fn(self, ...)
    end
end

---------------------------------------------------------------------------
-- Andocken und Fensterposition
---------------------------------------------------------------------------

local docked = setmetatable({}, { __mode = "k" })      -- child → { parent, opts } des letzten Andockens (Core.Redock)
local dockHooked = setmetatable({}, { __mode = "k" })  -- parent → true: OnShow/OnSizeChanged schon gehookt
local FollowDock                                       -- fn(child): mitlaufendes Teil neu andocken (unten)

-- Platz neben parent auf einer Seite, in den Punkten von child (nach dem Abstand): Zahl; nil, solange die Lage von
-- parent oder der Bildschirm unbekannt ist. Negativ: parent ragt selbst über den Rand.
function Core.DockRoom(child, parent, side, gap)
    local screenW = ScreenSize()
    local scale = FrameNumber(parent, "GetEffectiveScale")
    local left, right = FrameNumber(parent, "GetLeft"), FrameNumber(parent, "GetRight")
    if not (screenW and scale and left and right) then return nil end
    local childScale = FrameNumber(child, "GetEffectiveScale") or scale
    if childScale <= 0 then return nil end
    local room = side == "left" and left * scale or (screenW - right * scale)
    return room / childScale - (Core.Num(gap) or 2)
end

--[[
    Hängt child seitlich an parent an und lässt es mitwandern (vorher ezMacro). Nur Anker.
      opts.side         "right" (Standard) oder "left" – die Wunschseite
      opts.gap          waagerechter Abstand (Standard 2)
      opts.y            senkrechter Versatz der Oberkante (Standard 0)
      opts.matchHeight  false = eigene Höhe behalten; sonst so hoch wie parent
      opts.align        "bottom": mit eigener Höhe unten bündig statt oben (nur mit matchHeight = false)
      opts.check        true: Platz prüfen (FP-09) – reicht der Platz auf der Wunschseite nicht, wechselt child auf die
                        andere Seite. Ohne bekannte Lage (Fenster noch nie gezeigt) bleibt es bei der Wunschseite.
                        Ohne die Angabe dockt child wie bisher ungeprüft an die Wunschseite (die fünf Aufrufer von
                        heute rechnen den Platz teils selbst); der Platz kommt trotzdem als dritter Wert zurück.
      opts.width        Breite von child für die Prüfung, solange es selbst noch keine hat
      opts.overlap      true: passt es auf keiner Seite, liegt child innen an der Wunschseite über parent, statt aus dem
                        Bildschirm zu ragen (das Blizzard-Fenster wird nie verschoben); opts.inset = Abstand zum Rand
                        von parent dabei (Standard 4). Das Modul zeigt dann seinen Hinweis (zweiter Rückgabewert).
      opts.follow       true: neu prüfen, wenn parent erscheint (sofort und einen Frame später – Blizzard und
                        „Blizzard-Fenster verschieben“ setzen die Lage erst nach dem Zeigen) oder seine Größe ändert,
                        wenn ein eigenes Teil verschoben wurde (MOVER_MOVED) und wenn ein Blizzard-Fenster verschoben
                        oder von Blizzard neu angeordnet wurde (FRAME_MOVED); von Hand: Core.Redock(child).
                        Ein geschütztes child wird im Kampf nicht von selbst umgehängt, sondern gleich danach.
      opts.onPlaced     fn(seite, art, platz) nach jedem Andocken
    → seite ("right" | "left"), art ("beside" | "overlap"), platz (Zahl auf der gewählten Seite oder nil = unbekannt)
]]
function Core.Dock(child, parent, opts)
    opts = opts or {}
    local gap = opts.gap or 2
    local side = opts.side == "left" and "left" or "right"
    local mode, room = "beside", Core.DockRoom(child, parent, side, gap)
    if opts.check == true then
        local width = FrameNumber(child, "GetWidth")
        if not width or width <= 0 then width = Core.Num(opts.width) end
        local wanted, other = room, nil
        if width and width > 0 and wanted and wanted < width then
            local otherSide = side == "left" and "right" or "left"
            other = Core.DockRoom(child, parent, otherSide, gap)
            if other and other >= width then
                side, room = otherSide, other
            elseif opts.overlap then
                mode = "overlap"
            end
        end
    end
    local left = side == "left"
    local dx = left and -gap or gap
    local childPoint, parentPoint = left and "RIGHT" or "LEFT", left and "LEFT" or "RIGHT"
    if mode == "overlap" then
        -- innen an der Wunschseite, über dem Fenster
        dx = left and (opts.inset or 4) or -(opts.inset or 4)
        childPoint = parentPoint
    end
    child:ClearAllPoints()
    if opts.matchHeight ~= false then
        child:SetPoint("TOP" .. childPoint, parent, "TOP" .. parentPoint, dx, opts.y or 0)
        child:SetPoint("BOTTOM" .. childPoint, parent, "BOTTOM" .. parentPoint, dx, 0)
    elseif opts.align == "bottom" then
        child:SetPoint("BOTTOM" .. childPoint, parent, "BOTTOM" .. parentPoint, dx, opts.y or 0)
    else
        child:SetPoint("TOP" .. childPoint, parent, "TOP" .. parentPoint, dx, opts.y or 0)
    end
    child:SetClampedToScreen(false)
    docked[child] = { parent = parent, opts = opts }
    if opts.follow and type(parent) == "table" and type(parent.HookScript) == "function" and not dockHooked[parent] then
        dockHooked[parent] = true
        local function Again()
            local list = {}
            for other, info in pairs(docked) do
                if info.parent == parent and info.opts.follow then list[#list + 1] = other end
            end
            for _, other in ipairs(list) do FollowDock(other) end
        end
        -- Beim Zeigen steht das Fenster noch an Blizzards Ausgangslage: gleich prüfen und einen Frame später noch
        -- einmal, wenn Blizzards Fensterverwaltung (und ezCores gemerkte Lage) es gesetzt haben.
        local function Shown()
            Again()
            local timer = rawget(_G, "C_Timer")
            if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, Again) end
        end
        pcall(parent.HookScript, parent, "OnShow", Shown)
        pcall(parent.HookScript, parent, "OnSizeChanged", Again)
    end
    if type(opts.onPlaced) == "function" then Core.Try(opts.owner, "Dock onPlaced", opts.onPlaced, side, mode, room) end
    return side, mode, room
end

-- Das letzte Andocken von child wiederholen (nach dem Verschieben des Trägers, nach einer Breitenänderung).
-- → seite, art, platz wie Core.Dock; nil, wenn child nie angedockt wurde.
function Core.Redock(child)
    local info = child ~= nil and docked[child] or nil
    if not info then return nil end
    return Core.Dock(child, info.parent, info.opts)
end

-- Von selbst neu andocken (follow): ein geschütztes Teil im Kampf erst danach (Leitlinie 5) – je Teil ein Auftrag.
FollowDock = function(child)
    local isProtected = Core.Peek(child, "IsProtected")
    if Core.InCombat() and type(isProtected) == "function" then
        local ok, protected = pcall(isProtected, child)
        if ok and Core.Bool(protected, false) then
            Core.AfterCombat(function() Core.Redock(child) end, "ezCore.dock:" .. tostring(child), Core.name)
            return
        end
    end
    Core.Redock(child)
end

-- Wurde ein eigenes Teil (Mover) oder ein Blizzard-Fenster (MoveFrames, Blizzards Fensterverwaltung) verschoben,
-- können die Träger gewandert sein: alle mitlaufenden Seitenteile neu prüfen.
local function RedockFollowers()
    local list = {}
    for child, info in pairs(docked) do
        if info.opts.follow then list[#list + 1] = child end
    end
    for _, child in ipairs(list) do FollowDock(child) end
end
Core.Listen("MOVER_MOVED", RedockFollowers, Core.name)
Core.Listen("FRAME_MOVED", RedockFollowers, Core.name)

--[[
    Baustein „Seitenteil mit Pfeil“ (FP-09; für ezCraft am Berufefenster, ezAuction „Markt“, ezTalent): ein eigenes
    Feld neben einem Blizzard-Fenster, das ein sichtbarer Pfeil-Knopf an dessen Rand auf- und zuklappt (Leitlinien
    1 und 3). Das Feld ist ein Kind des Blizzard-Fensters – es erscheint, verschwindet und wandert mit ihm; angedockt
    wird über Core.Dock mit Platzprüfung, nichts an Blizzards Fenster wird verändert.

      local teil = Core.NewSidePanel(TradeSkillFrame, { name = "ezCraftSide", width = 260, store = ns.db.side,
          tip = L.SIDE_TIP, tipBody = L.SIDE_TIP_TEXT, onToggle = fn(offen), onPlaced = fn(seite, art) })
      opts.side, gap, y, matchHeight, align, overlap (Standard an), inset   wie Core.Dock
      opts.width        Breite (Standard Core.SIDEPANEL_WIDTH); opts.height nur mit matchHeight = false
      opts.template     Blizzard-Vorlage des Felds (Standard "InsetFrameTemplate"); fehlt sie im Client, ein leerer Rahmen
      opts.store, key   Tabelle und Feld, in dem „offen“ gemerkt wird (Standard key = "open"); opts.open = Startwert
      opts.arrow        { point, relPoint, x, y, size } – feste Lage des Pfeil-Knopfs an parent. Ohne point (Standard):
                        zu = oben außen am Fenster auf der Seite des Felds (y = Abstand von oben, Standard -30; passt er
                        dort nicht mehr auf den Bildschirm, innen am Fensterrand); offen = in der äußeren oberen Ecke
                        des Felds (das Modul hält dort Core.SIDEPANEL_ARROW_ROOM Punkte frei). Der Pfeil liegt immer
                        über dem Feld (Rahmenebene), auch wenn es das Fenster überlappt – er ist der sichtbare Weg zurück.
      opts.tip, tipBody Tooltip des Pfeils (Standard: „Seitenteil öffnen“ / „Seitenteil schließen“)
    Das Feld: teil:Open(), teil:Close(), teil:Toggle(), teil:IsOpen(), teil:Place() → seite, art; teil.arrow (Knopf),
    teil:SetArrowOffset(x, y) → geändert? (A27, Welle 23b: Lage des zugeklappten Pfeils wie opts.arrow.x/y, platziert
    neu), teil:GetArrowOffset() → x, y;
    teil.side, teil.mode ("beside" | "overlap" – bei "overlap" zeigt das Modul seinen Hinweis), teil.arrowAt
    ("outside" | "inside" | "panel" | "fixed"). Auch das geschlossene Feld wird angedockt (nur Anker): so stehen Seite
    und Pfeil schon vor dem ersten Öffnen richtig und wandern mit; opts.onPlaced kommt nur bei offenem Feld.
    Der Pfeil zeigt in die Richtung, in die ein Klick das Feld bewegt: zum Feld hin (öffnen) oder zum Fenster (schließen).
]]
Core.SIDEPANEL_WIDTH = 260
Core.SIDEPANEL_ARROW_ROOM = 30      -- so viel hält ein Modul in der äußeren oberen Ecke des Felds für den Pfeil frei
Core.SIDEPANEL_ARROW_LEVEL = 20     -- Rahmenebenen über dem Feld (über dessen Inhalt)
local ARROW_NEXT = { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down" }
local ARROW_PREV = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down" }

function Core.NewSidePanel(parent, opts)
    opts = opts or {}
    if type(parent) ~= "table" then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", opts.name, parent, opts.template or "InsetFrameTemplate")
    if not ok or not panel then panel = CreateFrame("Frame", opts.name, parent) end
    panel:SetWidth(opts.width or Core.SIDEPANEL_WIDTH)
    if opts.matchHeight == false and opts.height then panel:SetHeight(opts.height) end
    local key = opts.key or "open"
    local store = type(opts.store) == "table" and opts.store or nil
    local open = opts.open == true
    if store and store[key] ~= nil then open = store[key] == true end

    local arrowOpts = type(opts.arrow) == "table" and opts.arrow or {}
    local arrow = CreateFrame("Button", opts.name and (opts.name .. "Arrow") or nil, parent)
    arrow:SetSize(arrowOpts.size or 24, arrowOpts.size or 24)
    arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    panel.arrow = arrow

    local function Refresh()
        local left = panel.side == "left"
        -- offen: der Klick schiebt das Feld zum Fenster zurück; zu: er klappt es zur Seite hin auf
        local towardsPanel = not open
        local textures = (towardsPanel ~= left) and ARROW_NEXT or ARROW_PREV
        arrow:SetNormalTexture(textures[1])
        arrow:SetPushedTexture(textures[2])
        arrow:ClearAllPoints()
        -- immer über dem Feld und seinem Inhalt: im Überlappen-Fall läge er sonst darunter
        arrow:SetFrameLevel((FrameNumber(panel, "GetFrameLevel") or 1) + Core.SIDEPANEL_ARROW_LEVEL)
        local inner, outer = left and "TOPLEFT" or "TOPRIGHT", left and "TOPRIGHT" or "TOPLEFT"
        if arrowOpts.point then
            arrow:SetPoint(arrowOpts.point, parent, arrowOpts.relPoint or arrowOpts.point, arrowOpts.x or 0, arrowOpts.y or 0)
            panel.arrowAt = "fixed"
        elseif open then
            -- äußere obere Ecke des Felds (neben dem Fenster wie darüber)
            arrow:SetPoint(inner, panel, inner, left and 4 or -4, -4)
            panel.arrowAt = "panel"
        else
            local x, y = arrowOpts.x or 0, arrowOpts.y or -30
            local room = Core.DockRoom(arrow, parent, left and "left" or "right", x)
            if room and room < (FrameNumber(arrow, "GetWidth") or 24) then
                -- außen kein Platz mehr auf dem Bildschirm: innen am Fensterrand
                arrow:SetPoint(inner, parent, inner, left and 4 or -4, y)
                panel.arrowAt = "inside"
            else
                arrow:SetPoint(outer, parent, inner, left and -x or x, y)
                panel.arrowAt = "outside"
            end
        end
    end

    function panel:Place()
        local side, mode = Core.Dock(self, parent, { side = opts.side, gap = opts.gap, y = opts.y, matchHeight = opts.matchHeight,
            align = opts.align, check = true, overlap = opts.overlap ~= false, inset = opts.inset, follow = true,
            owner = opts.owner, width = opts.width or Core.SIDEPANEL_WIDTH,
            onPlaced = function(placedSide, placedMode, room)
                panel.side, panel.mode = placedSide, placedMode
                Refresh()
                if open and type(opts.onPlaced) == "function" then Core.Try(opts.owner, "SidePanel onPlaced", opts.onPlaced, placedSide, placedMode, room) end
            end })
        return side, mode
    end

    local function Set(value, quiet)
        open = value and true or false
        if store then store[key] = open end
        if open then panel:Show() else panel:Hide() end
        panel:Place()      -- auch geschlossen: Seite und Pfeil stehen richtig und wandern mit dem Fenster
        if not quiet and type(opts.onToggle) == "function" then Core.Try(opts.owner, "SidePanel onToggle", opts.onToggle, open) end
    end
    function panel:Open() Set(true) end
    function panel:Close() Set(false) end
    function panel:Toggle() Set(not open) end
    function panel:IsOpen() return open end
    -- A27 (Welle 23b): Abstand des zugeklappten Pfeils vom Fensterrand (x) bzw. von oben (y) ändern, ohne opts.arrow
    -- selbst zu beschreiben (ezAuction rückt ihn neben seine Taschenliste). nil lässt den Wert. Platziert nur neu, wenn
    -- sich etwas ändert. → true bei Änderung
    function panel:SetArrowOffset(x, y)
        x, y = Core.Num(x), Core.Num(y)
        local changed = false
        if x and arrowOpts.x ~= x then arrowOpts.x, changed = x, true end
        if y and arrowOpts.y ~= y then arrowOpts.y, changed = y, true end
        if changed then self:Place() end
        return changed
    end
    -- y ab Werk wie in Refresh: 0 bei festem Punkt (opts.arrow.point), sonst -30 (Gegenprüfung Welle 23b)
    function panel:GetArrowOffset() return arrowOpts.x or 0, arrowOpts.y or (arrowOpts.point and 0 or -30) end

    arrow:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        panel:Toggle()
    end)
    arrow:SetScript("OnEnter", function(self)
        local L = Core.L
        local title = opts.tip or (open and L.SIDEPANEL_CLOSE or L.SIDEPANEL_OPEN)
        Core.ShowTip(self, title, opts.tipBody or (open and L.SIDEPANEL_CLOSE_TIP or L.SIDEPANEL_OPEN_TIP))
    end)
    arrow:SetScript("OnLeave", GameTooltip_Hide)

    panel.side, panel.mode = opts.side == "left" and "left" or "right", "beside"
    Set(open, true)
    return panel
end

-- Position nach Bildschirm-Viertel (vorher ezBag): so wächst ein Fenster in die richtige Richtung.
-- Rückgabe { point, relPoint, x, y } relativ zu UIParent, nil wenn das Fenster keine Lage hat.
function Core.QuadrantPos(frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left then return nil end
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local screenW, screenH = UIParent:GetWidth() * ratio, UIParent:GetHeight() * ratio
    local horiz = (left + right) / 2 < screenW / 2 and "LEFT" or "RIGHT"
    local vert = (top + bottom) / 2 > screenH / 2 and "TOP" or "BOTTOM"
    local point = vert .. horiz
    return { point = point, relPoint = point, x = horiz == "LEFT" and left or (right - screenW),
        y = vert == "TOP" and (top - screenH) or bottom }
end

-- Gemerkte Lagen in ezCoreDB.positions (eine Tabelle für Fenster, Mover und Module mit eigener Lage).
function Core.Positions(create)
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.positions) ~= "table" and create then db.positions = {} end
    return type(db.positions) == "table" and db.positions or nil
end

-- Gemerkte Lage eines Schlüssels oder nil.
function Core.StoredPosition(key)
    local positions = key ~= nil and Core.Positions(false)
    local pos = positions and positions[key]
    return type(pos) == "table" and pos or nil
end

-- Lage merken: frame (Lage nach Bildschirmviertel), fertige Tabelle { point, relPoint, x, y } oder nil (vergessen).
function Core.StorePosition(key, what)
    if key == nil then return end
    local pos = what
    if type(what) == "table" and what.GetPoint then pos = Core.QuadrantPos(what) end
    local positions = Core.Positions(pos ~= nil)
    if positions then positions[key] = type(pos) == "table" and pos or nil end
end

-- Die neun Ankerpunkte, die SetPoint kennt (Gesamtreview 18.11.2026, T6-3: ein unbekannter Punkt aus einem
-- Sicherungstext oder einer beschädigten SavedVariables-Datei ließ SetPoint nach ClearAllPoints werfen).
Core.ANCHOR_POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- Größter Versatz einer gemerkten Lage: zweimal die längere Seite von UIParent (ein Fenster mit eigener Skalierung
-- rechnet in seinen Einheiten), mindestens 10000. Was darüber liegt, ist sicher außerhalb des Bildschirms.
function Core.PositionLimit()
    local parent = rawget(_G, "UIParent")
    local w = parent and parent.GetWidth and Core.FiniteNumber(parent:GetWidth()) or 0
    local h = parent and parent.GetHeight and Core.FiniteNumber(parent:GetHeight()) or 0
    return math.max(10000, 2 * math.max(w, h))
end

-- Gültige Lage { point, relPoint, x, y } aus pos ({ point, relPoint, x, y } oder die alte Liste) oder nil (T6-3):
-- beide Punkte aus Core.ANCHOR_POINTS (Groß-/Kleinschreibung egal), x und y endliche Zahlen innerhalb von
-- ±Core.PositionLimit(). lenient = true: fehlendes x/y zählt als 0 (alte gespeicherte Lagen); sonst Pflicht.
-- Eine Fassung für Sicherung (Backup.CleanPosition), Übernahme alter Lagen und Core.ApplyPosition.
function Core.CleanPosition(pos, lenient)
    if type(pos) ~= "table" or Core.IsSecret(pos) then return nil end
    local point = pos.point or pos[1]
    local relPoint = pos.relPoint or pos[2] or point
    if type(point) ~= "string" or type(relPoint) ~= "string" or Core.IsSecret(point) or Core.IsSecret(relPoint) then
        return nil
    end
    point, relPoint = point:upper(), relPoint:upper()
    if not (Core.ANCHOR_POINTS[point] and Core.ANCHOR_POINTS[relPoint]) then return nil end
    local x, y = pos.x or pos[3], pos.y or pos[4]
    if lenient then x, y = x or 0, y or 0 end
    local limit = Core.PositionLimit()
    x, y = Core.FiniteNumber(x, -limit, limit), Core.FiniteNumber(y, -limit, limit)
    if not (x and y) then return nil end
    return { point = point, relPoint = relPoint, x = x, y = y }
end

-- Alte Lage eines Moduls einmal übernehmen ({ point, relPoint, x, y } oder Liste), nur wenn unter key noch
-- nichts gemerkt ist und sie gültig ist (Core.CleanPosition). Rückgabe: true, wenn übernommen.
function Core.ImportPosition(key, old)
    if key == nil or type(old) ~= "table" or Core.StoredPosition(key) then return false end
    local clean = Core.CleanPosition(old, true)
    if not clean then return false end
    Core.StorePosition(key, clean)
    return true
end

-- Gemerkte Lage setzen, sonst default. Rückgabe: true, wenn es eine gemerkte Lage gab (z. B. damit die
-- Tasche ohne eigene Lage neben der Bank aufgeht).
function Core.RestorePosition(frame, key, default)
    return Core.ApplyPosition(frame, Core.StoredPosition(key), default)
end

-- Aktuelle Lage eines frei verschobenen Fensters (erster Anker) als { point, relPoint, x, y }.
function Core.SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return nil end
    return { point = point, relPoint = relPoint, x = x, y = y }
end

-- Lage setzen. pos: { point, relPoint, x, y } oder die alte Form { point, relPoint, x, y } als Liste.
-- default: { point, relPoint, x, y } (Standard: Mitte). Rückgabe: true, wenn pos benutzt wurde.
-- Eine ungültige Lage (unbekannter Ankerpunkt, x/y nicht endlich oder weit außerhalb, Core.CleanPosition) zählt wie
-- keine: das Fenster bekommt default, statt nach ClearAllPoints an SetPoint zu scheitern (T6-3).
function Core.ApplyPosition(frame, pos, default)
    local clean = Core.CleanPosition(pos, true)
    frame:ClearAllPoints()
    if clean then
        frame:SetPoint(clean.point, UIParent, clean.relPoint, clean.x, clean.y)
        return true
    end
    default = Core.CleanPosition(default or { "CENTER", "CENTER", 0, 0 }, true)
        or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    frame:SetPoint(default.point, UIParent, default.relPoint, default.x, default.y)
    return false
end

---------------------------------------------------------------------------
-- Erklärblasen wie Blizzards Tutorial-Hinweise (vorher ezMacro/Hint.lua)
---------------------------------------------------------------------------

--[[
    GlowBoxTemplate mit GlowBoxArrowTemplate, Text GameFontHighlightLeft 196 breit, Knopf unten,
    gelbes X oben rechts, 20 px Abstand zum Ziel (Maße wie Blizzard_SharedXML/HelpTip.xml).
    Eigene Frames statt Blizzards HelpTip-System, damit dessen gemeinsamer Pool nicht verseucht wird.
    local Hint = ezCore.NewHints(function() return meineDB.hints end, okayText)
    Hint.Show(key, parent, target, text, side), Hint.Seen(key), Hint.Hide(key), Hint.Box(key), Hint.Reset()

    Der Pfeil (Spielbericht 14.11.2026: „immer iwie kaputt, falsch gerendert“): GlowBoxArrowTemplate hängt seine
    zwei Texturen ab Werk oben in den Rahmen (Pfeil 53×21 an TOPLEFT, Leuchten 65×28 an TOP, beide zeigen nach
    unten). In einem 61×61 großen Rahmen mit der Mitte auf der Blasenkante lag der Pfeil deshalb IN der Blase über
    dem Knopf, und gedreht passten Pfeil und Leuchten nicht mehr aufeinander (wirkte doppelt). Jetzt:
      - Der Pfeil-Rahmen ist so groß wie der Pfeil (gedreht 21×53) und dockt mit seiner Innenkante an die
        Außenkante der Blase, 3 px überlappend (so hängt Blizzards HelpPlate seine Pfeile an) – nichts ragt in die
        Blase, der Knopf bleibt frei, die Spitze endet 2 px vor dem Ziel.
      - Beide Texturen werden selbst verankert: der Pfeil mittig im Rahmen, das Leuchten mittig darauf und 4 px
        zur Spitze verschoben (Versatz aus Blizzards HelpTip); beide bekommen dieselbe Drehung.
      - Lässt sich nicht drehen (SetClampedTextureRotation fehlt), erscheint nur der Pfeil nach unten („above“).
]]

local WIDTH, TEXT_W, DISTANCE = 226, 196, 20
local ARROW_W, ARROW_H = 53, 21       -- Blizzards Pfeil (HelpPlateArrowDown), zeigt ab Werk nach unten
local ARROW_OVERLAP, GLOW_SHIFT = 3, 4
-- Lage der Blase zum Ziel: Punkt der Blase, Punkt am Ziel, Versatz. arrow: Punkt des Pfeils, Punkt an der Blase,
-- Versatz (in die Blase hinein), Drehung, Richtung der Spitze (x, y).
local SIDES = {
    above = { "BOTTOM", "TOP", 0, DISTANCE, arrow = { "TOP", "BOTTOM", 0, ARROW_OVERLAP, 0, 0, -1 } },
    below = { "TOP", "BOTTOM", 0, -DISTANCE, arrow = { "BOTTOM", "TOP", 0, -ARROW_OVERLAP, 180, 0, 1 } },
    right = { "LEFT", "RIGHT", DISTANCE, 0, arrow = { "RIGHT", "LEFT", ARROW_OVERLAP, 0, 90, -1, 0 } },
    left = { "RIGHT", "LEFT", -DISTANCE, 0, arrow = { "LEFT", "RIGHT", -ARROW_OVERLAP, 0, 270, 1, 0 } },
    -- Spieltest 19.11.2026 (S-1911-Einfuehrung): links vom Ziel, Oberkante bündig mit dem Ziel – für Ziele dicht unter
    -- dem oberen Bildschirmrand (Addon-Fach an der Minikarte). Mittig daneben („left“) ragte die obere Hälfte der Blase
    -- aus dem Bildschirm; so wächst sie nach unten. Der Pfeil sitzt oben an der rechten Kante, seine Oberkante bündig
    -- mit der Blase (Gegenprüfung: mit -12 ragte der seitliche, ARROW_W hohe Pfeil rund 14 Punkte über die Blase und
    -- damit über den Bildschirmrand).
    leftTop = { "TOPRIGHT", "TOPLEFT", -DISTANCE, 0, arrow = { "LEFT", "TOPRIGHT", -ARROW_OVERLAP, -ARROW_W / 2, 270, 1, 0 } },
}
Core.HINT_SIDES = SIDES   -- Lagen der Erklärblase (für Prüfungen; nur lesen)

-- Dreht Pfeil und Leuchten. → true, wenn beide vorhandenen Texturen jetzt in diese Richtung zeigen.
local function Rotate(degrees, ...)
    local rotate = rawget(_G, "SetClampedTextureRotation")
    local done = true
    for i = 1, select("#", ...) do
        local texture = select(i, ...)
        if type(texture) == "table" then
            if type(rotate) == "function" then
                if not pcall(rotate, texture, degrees) then done = false end
            elseif degrees ~= 0 then
                done = false
            end
        end
    end
    return done
end

-- Pfeil an die Außenkante der Blase docken (s: Eintrag aus SIDES).
local function PlaceArrow(box, s)
    local arrow = box.Arrow
    if not arrow then return end
    local a = s.arrow
    local point, boxPoint, x, y, degrees, tipX, tipY = a[1], a[2], a[3], a[4], a[5], a[6], a[7]
    -- Die zwei Texturen der Vorlage (parentKey „Arrow“ und „Glow“); fehlt eine, bleibt sie aus dem Spiel.
    local texture, glow = Core.Peek(arrow, "Arrow"), Core.Peek(arrow, "Glow")
    if not Rotate(degrees, texture, glow) then
        arrow:Hide()                      -- lieber kein Pfeil als einer, der in die falsche Richtung zeigt
        return
    end
    local sideways = tipX ~= 0
    arrow:SetSize(sideways and ARROW_H or ARROW_W, sideways and ARROW_W or ARROW_H)
    arrow:ClearAllPoints()
    arrow:SetPoint(point, box, boxPoint, x, y)
    if type(texture) == "table" and texture.SetPoint then
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", arrow, "CENTER", 0, 0)
    end
    if type(glow) == "table" and glow.SetPoint then
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", arrow, "CENTER", tipX * GLOW_SHIFT, tipY * GLOW_SHIFT)
    end
    arrow:Show()
end

Core.hintSets = Core.hintSets or {}   -- alle Erklärblasen-Sätze (für Core.ResetAllTours, FirstStart.lua)

function Core.NewHints(store, okayText)
    local Hint, boxes = {}, {}
    Core.hintSets[#Core.hintSets + 1] = Hint

    local function Hints() return store() or {} end

    function Hint.Seen(key) return Hints()[key] == true end
    -- Als gesehen merken, ohne sie zu zeigen (Einführung: die Seite des Moduls hat sie erledigt) und ausblenden
    function Hint.MarkSeen(key)
        if key == nil then return false end
        Hints()[key] = true
        if boxes[key] then boxes[key]:Hide() end
        return true
    end

    local function Acknowledge(box)
        Hints()[box.key] = true
        box:Hide()
    end

    local function CreateBox(key, parent)
        local ok, box = pcall(CreateFrame, "Frame", nil, parent, "GlowBoxTemplate")
        if not (ok and box) then box = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate") end
        box.key = key
        box:SetWidth(WIDTH)
        box:SetFrameStrata("DIALOG")
        box:SetToplevel(true)
        box:EnableMouse(true)

        box.Text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
        box.Text:SetWidth(TEXT_W)
        box.Text:SetPoint("TOPLEFT", 15, -15)
        box.Text:SetJustifyH("LEFT")
        box.Text:SetJustifyV("TOP")

        box.OkayButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        box.OkayButton:SetSize(110, 22)
        box.OkayButton:SetPoint("BOTTOM", 0, 12)
        box.OkayButton:SetText(okayText or OKAY)
        box.OkayButton:SetScript("OnClick", function()
            Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            Acknowledge(box)
        end)

        -- Gelbes X wie HelpTipCloseButtonMixin (common-icon-yellowx), sonst Blizzards Schließen-Knopf.
        local close
        if Core.AtlasExists("common-icon-yellowx") then
            close = CreateFrame("Button", nil, box)
            close:SetSize(18, 18)
            close.Texture = close:CreateTexture(nil, "ARTWORK")
            close.Texture:SetAllPoints()
            close.Texture:SetAtlas("common-icon-yellowx")
            close:SetScript("OnMouseDown", function(self) self.Texture:SetAtlas("common-icon-yellowx-down") end)
            close:SetScript("OnMouseUp", function(self) self.Texture:SetAtlas("common-icon-yellowx") end)
        else
            close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
            close:SetSize(24, 24)
        end
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() Acknowledge(box) end)
        box.CloseButton = close

        local okArrow, arrow = pcall(CreateFrame, "Frame", nil, box, "GlowBoxArrowTemplate")
        if okArrow and arrow then
            arrow:SetSize(ARROW_W, ARROW_H)
            box.Arrow = arrow
        end
        return box
    end

    -- Zeigt die Blase „key“ an „target“ (Teil von „parent“, mit dem sie sich ausblendet), solange sie
    -- nicht bestätigt wurde. side: above/below/right/left = Lage der Blase zum Ziel; der Pfeil zeigt aufs Ziel.
    function Hint.Show(key, parent, target, text, side)
        if not (parent and target) or Hint.Seen(key) then return nil end
        local box = boxes[key]
        if not box then
            box = CreateBox(key, parent)
            boxes[key] = box
        elseif box.GetParent and box:GetParent() ~= parent then
            -- dieselbe Erklärung an einem anderen Fenster (z. B. erst Quest-, dann Gossip-Fenster): umhängen
            box:SetParent(parent)
            box:SetFrameStrata("DIALOG")
        end
        local s = SIDES[side] or SIDES.above
        box.Text:SetText(text)
        box:SetHeight((box.Text:GetStringHeight() or 40) + 15 + 10 + 22 + 12)
        box:ClearAllPoints()
        box:SetPoint(s[1], target, s[2], s[3], s[4])
        PlaceArrow(box, s)
        box.side = side
        box:Show()
        return box
    end

    function Hint.Hide(key) if boxes[key] then boxes[key]:Hide() end end
    function Hint.Box(key) return boxes[key] end
    function Hint.Reset()
        wipe(Hints())
        for _, box in pairs(boxes) do box:Hide() end
    end
    -- Anzahl gesehener Blasen (für „alle erneut zeigen“)
    function Hint.SeenCount()
        local n = 0
        for _, seen in pairs(Hints()) do if seen == true then n = n + 1 end end
        return n
    end

    return Hint
end

---------------------------------------------------------------------------
-- Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026)
---------------------------------------------------------------------------

--[[
    local tour = Core.NewTour({ store = function() return ns.db.hints end, okay = L.HINT_OK, steps = {
        { key = "search", target = function() return frame.Search end, text = L.HINT_SEARCH, side = "below" }, … } })
    tour:Start(parent)   die erste noch nicht gesehene Blase; „OK“ oder das X führt zur nächsten
    tour:Reset()         alle wieder zeigen (Knopf: page:TourButton(tour)); tour:Done() → alle gesehen?
    Ein Schritt, dessen Ziel fehlt oder unsichtbar ist, wird übersprungen (nicht als gesehen gemerkt).
]]
--[[
    Gemeinsamer Starter (V-035, vorher in 13 Tour-Dateien je selbst gebaut):
      Core.NewTour({ owner = ns, steps = … })   Speicher ist ns.db.tour (angelegt beim ersten Zugriff); opts.field
                                                wählt ein anderes Feld (z. B. "hints" für Module, die dort schon
                                                speichern). opts.import = "hints": gesehene Schritte aus dem alten
                                                Feld einmal übernehmen (nur die Schlüssel dieses Rundgangs).
      tour:StartSoon(parent, delay)   gebündelt starten: viele Aufrufe in kurzer Zeit (OnShow, Layout …) ergeben einen
                                      Start nach delay Sekunden (Standard 0,5); im Kampf erst danach (Core.AfterCombat);
                                      nichts, wenn schon alles gesehen ist. → true, wenn ein Start vorgemerkt ist
      tour:Cancel()                   vorgemerkten Start streichen
      opts.enabled = fn() → false     Rundgang aus (z. B. Einstellung des Moduls): Start und StartSoon tun nichts
    Welle 23b (A32, A33; vorher baute ezTalent und ezAuction es je selbst als Hülle um tour:Next):
      opts.single = true              immer nur eine Blase: zeigt der Rundgang die nächste (auch nach „OK“ oder dem X),
                                      verschwinden die übrigen dieses Rundgangs
      tour:Next() prüft selbst, was Start und StartSoon prüfen: bei enabled() == false verschwinden alle Blasen des
                                      Rundgangs (nichts wird als gesehen gemerkt), im Kampf ebenso – danach geht es über
                                      tour:StartSoon an derselben Stelle weiter. „OK“ und das X rufen tour:Next, darum gilt
                                      beides auch für stehende Blasen. Beginnt ein Kampf (PLAYER_REGEN_DISABLED), nimmt
                                      ezCore offene Blasen jedes Rundgangs weg und setzt ihn nach dem Kampf fort.
      tour:HideAll()                  alle Blasen des Rundgangs ausblenden (gemerkt wird nichts) → Anzahl ausgeblendeter
      tour:ShownSteps()               Schritte, deren Blase jetzt zu sehen ist (noch nicht bestätigt) → { [Schlüssel] = true }
      tour:MarkSeen(nur)              Schritte (nur: Menge, sonst alle) als gesehen merken → Anzahl neu gemerkter
      Core.TOUR_FEATURES              Merkmale für Core.Has: "TOUR_FEATURES.single", "TOUR_FEATURES.guardNext"
]]
Core.TOUR_FEATURES = { single = true, guardNext = true }
Core.TOUR_COMBAT_DELAY = 0.5   -- so lange nach dem Kampfbeginn wartet der vorgemerkte Neustart (danach über AfterCombat)
local tours = setmetatable({}, { __mode = "k" })   -- alle Rundgänge (für den Kampfbeginn)

function Core.NewTour(opts)
    opts = opts or {}
    local steps = opts.steps or {}
    local store = opts.store
    local owner = type(opts.owner) == "table" and opts.owner or nil
    if store == nil and owner then
        local field, imported = opts.field or "tour", false
        store = function()
            local db = owner.db
            if type(db) ~= "table" then return nil end
            if type(db[field]) ~= "table" then db[field] = {} end
            local seen = db[field]
            if not imported then
                imported = true
                local old = opts.import and db[opts.import]
                if type(old) == "table" and old ~= seen then
                    for _, step in ipairs(steps) do
                        if old[step.key] == true and seen[step.key] == nil then seen[step.key] = true end
                    end
                end
            end
            return seen
        end
    end
    local hints = Core.NewHints(store or function() return nil end, opts.okay)
    local tour = { hints = hints, steps = steps }
    local ownerName = owner and owner.moduleName or Core.name
    -- Zu welchem Modul der Rundgang gehört (Einführung, Core.ModuleTours): owner.moduleName, sonst opts.module (für
    -- Rundgänge mit eigenem Speicher wie ezBuff und ezCombat), sonst nil
    tour.module = (owner and owner.moduleName) or (type(opts.module) == "string" and opts.module) or nil
    local startKey = {}   -- eigener Schlüssel je Rundgang für Core.AfterCombat
    local soon = false

    local function Enabled()
        if type(opts.enabled) ~= "function" then return true end
        local ok, on = pcall(opts.enabled)
        return not ok or on ~= false
    end
    local hooked = setmetatable({}, { __mode = "k" })

    local function Target(step)
        local target = step.target
        if type(target) == "function" then
            local ok, result = pcall(target)
            target = ok and result or nil
        end
        if type(target) ~= "table" or (target.IsVisible and not target:IsVisible()) then return nil end
        return target
    end

    -- alle Blasen dieses Rundgangs weg, ohne etwas als gesehen zu merken → Anzahl der vorher sichtbaren
    function tour:HideAll()
        local n = 0
        for _, step in ipairs(self.steps) do
            local box = hints.Box(step.key)
            if box and box.IsShown and box:IsShown() then n = n + 1 end
            hints.Hide(step.key)
        end
        return n
    end

    function tour:Next()
        -- A33 (Welle 23b): dieselben Bedingungen wie Start und StartSoon, auch für „OK“ und das X an einer stehenden Blase
        if not Enabled() then
            self:HideAll()
            return nil
        end
        if Core.InCombat() then
            self:HideAll()
            self:StartSoon(nil, Core.TOUR_COMBAT_DELAY)
            return nil
        end
        for _, step in ipairs(self.steps) do
            if not hints.Seen(step.key) then
                local target = Target(step)
                if target then
                    -- step.text darf eine Funktion sein (Text erst beim Zeigen, z. B. „welche Module laufen“)
                    local text = step.text
                    if type(text) == "function" then
                        local okText, result = pcall(text)
                        text = okText and result or ""
                    end
                    local box = hints.Show(step.key, step.parent or self.parent or target, target, text, step.side)
                    if box and not hooked[box] then
                        hooked[box] = true
                        for _, button in ipairs({ box.OkayButton, box.CloseButton }) do
                            if button and button.HookScript then button:HookScript("OnClick", function() tour:Next() end) end
                        end
                    end
                    -- A32 (Welle 23b): immer nur eine Blase
                    if box and opts.single then
                        for _, other in ipairs(self.steps) do
                            if other.key ~= step.key then hints.Hide(other.key) end
                        end
                    end
                    return step.key
                end
            end
        end
        return nil
    end

    function tour:Start(parent)
        if parent then self.parent = parent end
        if not Enabled() then return nil end
        return self:Next()
    end

    function tour:StartSoon(parent, delay)
        if parent then self.parent = parent end
        if not Enabled() or self:Done() then return false end
        if soon then return true end
        soon = true
        C_Timer.After(tonumber(delay) or 0.5, function()
            if not soon then return end
            Core.AfterCombat(function()
                if not soon then return end
                soon = false
                tour:Start()
            end, startKey, ownerName)
        end)
        return true
    end

    function tour:Cancel()
        local was = soon
        soon = false
        Core.CancelAfterCombat(startKey)
        return was
    end


    function tour:Reset()
        hints.Reset()
        for _, step in ipairs(self.steps) do hints.Hide(step.key) end
    end

    function tour:Done()
        for _, step in ipairs(self.steps) do
            if not hints.Seen(step.key) then return false end
        end
        return true
    end

    -- Schritte, deren Blase jetzt zu sehen ist und noch nicht bestätigt ist (Einführung, Nachlauf zum Review von PR 536:
    -- nur wirklich Gezeigtes gilt beim Verlassen der Seite als gesehen – ein sichtbares Ziel allein reicht nicht, die
    -- übrigen Schritte des Rundgangs kamen noch gar nicht). IsVisible, nicht IsShown: eine Blase an einem Fenster, das
    -- der Spieler schloss (Händler, Lehrer), bleibt „gezeigt“ (IsShown), ist aber nicht zu sehen. Was beim Zeigen der
    -- Seite und kurz danach zu sehen war, hat Intro.Note da schon gesammelt. → Menge { [Schlüssel] = true }
    function tour:ShownSteps()
        local set = {}
        for _, step in ipairs(self.steps) do
            local box = hints.Box(step.key)
            if box and box.IsVisible and box:IsVisible() and not hints.Seen(step.key) then set[step.key] = true end
        end
        return set
    end

    -- Schritte als gesehen merken und ausblenden, ein vorgemerkter Start entfällt (Spieltest 19.11.2026,
    -- S-1911-Einfuehrung: wer die Seite des Moduls in der Einführung gesehen hat, bekommt die Blasen nicht mehr).
    -- only = Menge { [Schlüssel] = true }: nur diese Schritte (Gegenprüfung: nur, was an dem Fenster der Seite zu sehen
    -- war – die Blasen am Händler bleiben, wenn die Seite am Zauberbuch stand); ohne only alle.
    -- → Anzahl der Schritte, die vorher noch nicht gesehen waren
    function tour:MarkSeen(only)
        if type(only) ~= "table" then only = nil end
        local n = 0
        for _, step in ipairs(self.steps) do
            if not only or only[step.key] then
                if not hints.Seen(step.key) then n = n + 1 end
                hints.MarkSeen(step.key)
            end
        end
        -- ein vorgemerkter Start entfällt nur, wenn nichts mehr zu zeigen ist (sonst kämen die übrigen nicht)
        if self:Done() then self:Cancel() end
        return n
    end

    tours[tour] = true
    return tour
end

-- Rundgänge eines Moduls (tour.module; Einführung, Werkzeuge/FirstStart.lua). → Liste, nach Anlage nicht geordnet
function Core.ModuleTours(name)
    local list = {}
    if type(name) ~= "string" then return list end
    for tour in pairs(tours) do
        if tour.module == name then list[#list + 1] = tour end
    end
    return list
end

-- A33 (Welle 23b): Kampfbeginn – offene Blasen jedes Rundgangs verschwinden, nach dem Kampf geht er weiter (bei
-- PLAYER_REGEN_DISABLED gilt die Sperre noch nicht; StartSoon wartet über Core.AfterCombat)
function Core.ToursCombatStarted()
    local n = 0
    for tour in pairs(tours) do
        if tour:HideAll() > 0 then
            n = n + 1
            tour:StartSoon(nil, Core.TOUR_COMBAT_DELAY)
        end
    end
    return n
end
ns.On("PLAYER_REGEN_DISABLED", function() Core.ToursCombatStarted() end)
