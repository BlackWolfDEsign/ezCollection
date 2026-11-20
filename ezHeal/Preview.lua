local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorschau mit Tastenwahl in Blizzards Fenster „Klick-Zauber“ (Entscheidung des Nutzers vom 13.11.2026: „Jetzt frei
    wählbar“, „Ja, Vorschlag + wählbar“). Kein eigenes Fenster (Leitlinie 1): ein Aufklappteil als Kind von
    ClickBindingFrame, das für die Dauer der Vorschau genau über Blizzards Liste liegt (gleiche Anker wie Blizzards
    ScrollBoxBackground, dieselbe Vorlage TooltipBackdropTemplate; Aufbau nach Blizzards Forever-Quelle,
    Blizzard_ClickBindingUI.xml: ScrollBoxBackground TOPLEFT 4/−85 bis BOTTOMRIGHT −31/50). Es wandert mit dem
    Fenster und schließt mit ihm (HookScript „OnHide“ – von Blizzards Fenster wird nur gelesen).
    Je Platz eine Zeile: Zauber (Rang) – Art, Auswahlfeld Maustaste, Auswahlfeld Umschalttaste (ezCore.Menu.Dropdown
    mit ezCore.Menu.Radio: Blizzards Dropdown-Vorlage, ohne sie ein Knopf mit Kontextmenü). Doppelbelegungen
    werden rot markiert, „Übernehmen“ ist dann gesperrt (Tooltip und Zeile darüber nennen den Grund).
    Die Auswahlfelder kennzeichnen belegte Kombinationen schon vor der Wahl (HL-14, P.OptionText): hinter der Taste
    steht rot „belegt: <Zauber>“ (anderer Platz der Vorlage oder Blizzards „Ziel“/„Menü“ – sperrt das Übernehmen) bzw.
    grau „ersetzt: <Belegung>“ (liegt heute in Blizzards Klick-Belegung und wiche beim Übernehmen). Wählbar bleibt
    jede Taste: Wer zwei Plätze tauscht, legt den ersten kurz auf die Taste des zweiten.
    Oben: Auswahl der Vorlage, Schließen; unten: „Vorschlag wiederherstellen“ und „Übernehmen …“.
    Die Auswahl der Vorlage ist die Einstellung „template“ (eine Quelle, Einstellungs-Prüfung 19.11.2026, Nr. 74): die
    Wahl hier wird gespeichert, die Seite in den Einstellungen zeigt denselben Wert, und eine Wahl dort zeichnet die
    offene Vorschau neu.
]]

local P = {}
ns.Preview = P

local T = ns.Templates

P.ROW_H, P.TOP, P.PAD = 24, 54, 8
P.NAME_W, P.BUTTON_W, P.MOD_W = 150, 100, 130
P.APPLY_W, P.RESET_W, P.KIND_W = 120, 170, 200
P.rows = {}          -- je Zeile { frame, label, mark, button, mods, slot, data }

local function Parent()
    return rawget(_G, "ClickBindingFrame")
end

-- Tooltip über ezCore (Core.ShowTip); extra = Grund einer Sperre oder Doppelbelegung in Rot darunter
local function ShowTip(owner, title, body, extra)
    Core.ShowTip(owner, title, body)
    if extra then
        Core.TipLine(GameTooltip, extra, "bad", true)   -- Rolle statt Farbzahlen (T9-6)
        GameTooltip:Show()
    end
end

local function HideTip() GameTooltip:Hide() end

-- Auswahlfeld über ezCore (Core.Menu.Dropdown, Gesamtreview T18-12: vorher hier kopiert): Blizzards Dropdown-Vorlage,
-- sonst ein Knopf mit Kontextmenü. → { control, modern, label }; build(root) füllt das Menü (ezCore.Menu.Radio),
-- label() liefert den Text für die Ersatzfassung.
local function NewDropdown(parent, width, build, label)
    local control = Core.Menu.Dropdown(parent, width, build, label)
    return { control = control, modern = control.modern == true, label = label }
end

-- Text des Auswahlfelds nach einer Änderung auffrischen
local function Update(box)
    box.control:RefreshText()
end

-- Eine Taste wählen (Daten in Templates.lua) und die Vorschau neu zeichnen
function P.Choose(slot, button, modifiers)
    local oldButton, oldMods = T.Key(slot)
    if not oldButton then return false end
    local ok = T.SetKey(slot, button or oldButton, modifiers or oldMods)
    P.Refresh()
    return ok
end

-- Text eines Eintrags der Auswahlfelder (HL-14): die Taste, dahinter – wenn sie schon vergeben ist – wer sie hält.
-- Rot „belegt: …“ sperrt das Übernehmen (anderer Platz, „Ziel“/„Menü“), grau „ersetzt: …“ weicht beim Übernehmen
-- (T.KeyUse; die Klick-Belegung liest P.Refresh einmal je Zeichnen nach P.current). Der gewählte Eintrag bleibt ohne
-- Zusatz: Er steht als Text im Auswahlfeld, und seine Doppelbelegung zeigt die rote Zeile.
-- „ersetzt“ nur für Zeilen, die das Übernehmen auch schreibt (data.entry): Ein Platz, dessen Zauber noch nicht gelernt
-- oder nicht belegbar ist, lässt die Taste, wie sie ist – dort bleibt nur „belegt“ (wie in der Zeile selbst, T.Resolve).
function P.OptionText(row, button, modifiers, text)
    if type(row) ~= "table" or not row.slot then return text end
    local written = row.data and row.data.entry ~= nil
    local use, name = T.KeyUse(row.slot, button, modifiers,
        { current = written and P.current or nil, spellID = row.data and row.data.spellID })
    local note = T.KeyUseText(use, name)
    if not note then return text end
    return text .. " – " .. (use == "bound" and Core.Grey(note) or (Core.RED .. note .. "|r"))
end

-- HL-10: Text mit dem Hinweis auf ezBuffs Symbol am Rahmen. ezBuff ist ein eigenes Addon – läuft es nicht, gibt es
-- weder das Symbol noch die genannte Einstellungsseite; dann sagt eine Zeile darunter genau das (ezCores Text
-- MODULE_OFF, eine Stelle für alle Module).
function P.BuffHint(text)
    if Core.Module("ezBuff") then return text end
    return text .. "\n" .. L.MODULE_OFF:format("ezBuff")
end

local function RowTip(row)
    local data = row.data
    if not data then return end
    local spell = data.name
    if data.rank and data.rank > 0 then spell = spell .. " (" .. L.RANK:format(data.rank) .. ")" end
    local body = data.key .. " " .. Core.ARROW .. " " .. spell
    if data.state ~= "ok" then body = body .. "\n" .. (ns.Text("STATE_" .. data.state) or data.state) end
    if data.replaces then body = body .. "\n" .. L.REPLACES:format(data.replaces) end
    body = body .. "\n" .. (data.own and L.OWN_KEY or L.SUGGESTED_KEY)
    -- HL-10: Buff mit Rängen – per Klick gilt immer der höchste; für niedrigstufige Ziele auf ezBuffs Symbol verweisen.
    -- Nur an Zeilen mit Buff-Schlüssel aus ezCore (data.buff): Nur diese Buffs kennt ezBuffs Symbol und wählt ihren
    -- Rang nach der Stufe. Buffs, die die Vorlage als ID-Liste führt (Magier: Magie verstärken, Magie dämpfen), zeigt es nicht.
    if data.buff and data.rank and data.rank > 0 then body = body .. "\n\n" .. P.BuffHint(L.BUFF_RANK_HINT) end
    ShowTip(row.frame, ns.Text("SLOT_" .. data.slot) or L.SLOT_buff, body, data.conflict)
end

local function CreateRow(index)
    local panel = P.frame
    local row = {}
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetHeight(P.ROW_H)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", P.PAD, -P.TOP - (index - 1) * P.ROW_H)
    frame:SetPoint("RIGHT", panel, "RIGHT", -P.PAD, 0)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function() RowTip(row) end)
    frame:SetScript("OnLeave", HideTip)
    row.frame = frame
    -- rote Markierung einer Doppelbelegung
    local mark = frame:CreateTexture(nil, "BACKGROUND")
    mark:SetAllPoints(frame)
    mark:SetColorTexture(1, 0, 0, 0.3)
    mark:Hide()
    row.mark = mark
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", frame, "LEFT", 4, 0)
    label:SetWidth(P.NAME_W)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local function CurrentButton() return (T.Key(row.slot)) end
    local function CurrentMods() return select(2, T.Key(row.slot)) end
    row.mods = NewDropdown(frame, P.MOD_W, function(root)
        local button, chosen = CurrentButton(), CurrentMods()
        for _, mods in ipairs(T.MODIFIERS) do
            local text = T.ModifierText(mods)
            if mods ~= chosen then text = P.OptionText(row, button, mods, text) end
            Core.Menu.Radio(root, text, CurrentMods, function(value) P.Choose(row.slot, nil, value) end, mods)
        end
    end, function() return T.ModifierText(CurrentMods()) end)
    row.mods.control:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    row.button = NewDropdown(frame, P.BUTTON_W, function(root)
        local chosen, mods = CurrentButton(), CurrentMods()
        for _, button in ipairs(T.BUTTONS) do
            local text = T.ButtonText(button)
            if button ~= chosen then text = P.OptionText(row, button, mods, text) end
            Core.Menu.Radio(root, text, CurrentButton, function(value) P.Choose(row.slot, value, nil) end, button)
        end
    end, function() return T.ButtonText(CurrentButton()) end)
    row.button.control:SetPoint("RIGHT", row.mods.control, "LEFT", -4, 0)
    for _, box in ipairs({ row.mods, row.button }) do
        box.control:HookScript("OnEnter", function(self)
            ShowTip(self, box == row.mods and L.KEYS_MODIFIER or L.KEYS_BUTTON, L.KEYS_CHOICE_TIP, row.data and row.data.conflict)
        end)
        box.control:HookScript("OnLeave", HideTip)
    end
    P.rows[index] = row
    return row
end

local function Button(parent, text, width, onClick, tipTitle, tipBody)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    -- gesperrt bleibt der Tooltip sichtbar: er nennt den Grund
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnEnter", function(self) ShowTip(self, tipTitle, tipBody, P.reasons and P.reasons[self]) end)
    button:SetScript("OnLeave", HideTip)
    return button
end

local function SetEnabled(button, enabled, reason)
    P.reasons = P.reasons or {}
    P.reasons[button] = (not enabled) and reason or nil
    P.enabled = P.enabled or {}
    P.enabled[button] = enabled and true or false
    if button.SetEnabled then button:SetEnabled(enabled and true or false) end
end

-- Ist ein Knopf der Vorschau gerade frei? (für Tests und Status)
function P.IsEnabled(button)
    return P.enabled ~= nil and P.enabled[button] == true
end

-- Aufklappteil anlegen (einmal, sobald Blizzards Fenster geladen ist) → Rahmen oder nil
function P.Create()
    if P.frame then return P.frame end
    local parent = Parent()
    if type(parent) ~= "table" then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", nil, parent, "TooltipBackdropTemplate")
    if not ok or not panel then panel = CreateFrame("Frame", nil, parent) end
    P.frame = panel
    local under = parent.ScrollBoxBackground
    panel:ClearAllPoints()
    if type(under) == "table" then
        panel:SetPoint("TOPLEFT", under, "TOPLEFT", 0, 0)
        panel:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", 0, 0)
    else
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -85)
        panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -31, 50)
    end
    panel:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    panel:EnableMouse(true)
    panel:Hide()
    -- deckt Blizzards Liste darunter ab: Blizzards Hintergrund des Fensters (PortraitFrameTemplate)
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    if bg.SetVertTile then bg:SetVertTile(true) end

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() P.Close() end)
    close:SetScript("OnEnter", function(self) ShowTip(self, L.KEYS_CLOSE, L.KEYS_CLOSE_TIP) end)
    close:SetScript("OnLeave", HideTip)
    P.closeButton = close

    P.kindBox = NewDropdown(panel, P.KIND_W, function(root)
        for _, info in ipairs(ns.API.Templates()) do
            Core.Menu.Radio(root, info.label, function() return P.kind end, function(v) P.ChooseKind(v) end, info.kind)   -- Rückgabe von set ginge an Blizzards Menü
        end
    end, function() return ns.KindLabel(P.kind) end)
    P.kindBox.control:SetPoint("TOPLEFT", panel, "TOPLEFT", P.PAD + 2, -P.PAD)
    P.kindBox.control:HookScript("OnEnter", function(self) ShowTip(self, L.OPT_template, P.BuffHint(L.OPT_template_TIP)) end)
    P.kindBox.control:HookScript("OnLeave", HideTip)

    -- Spaltenköpfe
    local function Head(text, anchor, x)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", anchor, -P.TOP + 2 + (x or 0))
        fs:SetText(text)
        return fs
    end
    local inner = P.PAD + 4
    local rowWidth = 405 - 2 * P.PAD
    Head(L.KEYS_SPELL, inner)
    Head(L.KEYS_BUTTON, P.PAD + rowWidth - P.MOD_W - 4 - P.BUTTON_W)
    Head(L.KEYS_MODIFIER, P.PAD + rowWidth - P.MOD_W)

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", panel, "TOPLEFT", P.PAD + 4, -P.TOP - 4)
    empty:SetPoint("RIGHT", panel, "RIGHT", -P.PAD, 0)
    empty:SetJustifyH("LEFT")
    empty:Hide()
    P.empty = empty

    P.applyButton = Button(panel, L.KEYS_APPLY, P.APPLY_W, function() P.Apply() end, L.KEYS_APPLY, L.KEYS_APPLY_TIP)
    P.applyButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -P.PAD, P.PAD)
    P.resetButton = Button(panel, L.KEYS_RESET, P.RESET_W, function() P.Reset() end, L.KEYS_RESET, L.KEYS_RESET_TIP)
    P.resetButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", P.PAD, P.PAD)

    -- Grund der Sperre, sichtbar über den Knöpfen
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    status:SetPoint("BOTTOMLEFT", P.resetButton, "TOPLEFT", 2, 6)
    status:SetPoint("RIGHT", panel, "RIGHT", -P.PAD, 0)
    status:SetJustifyH("LEFT")
    P.status = status

    -- Blizzards Fenster zu → die Vorschau auch (nur zuhören)
    parent:HookScript("OnHide", function() if P.frame then P.frame:Hide() end end)
    return panel
end

-- Vorschau neu zeichnen: Zeilen, Markierungen, Sperre von „Übernehmen“
function P.Refresh()
    local panel = P.frame
    if not panel then return end
    P.kind = ns.ChosenKind(P.kind)
    -- Klick-Belegung einmal je Zeichnen lesen: für „ersetzt“ in den Zeilen (T.Resolve) und in den Auswahlfeldern
    -- (P.OptionText). false = nicht lesbar – dann ohne Vergleich, statt je Auswahlfeld noch einmal zu lesen.
    local cb = Core.ClickBindings
    P.current = cb and cb.Available() and cb.List() or false
    local rows = T.Resolve(P.kind, nil, P.current)
    Update(P.kindBox)
    for index, data in ipairs(rows) do
        local row = P.rows[index] or CreateRow(index)
        row.slot, row.data = data.slot, data
        local spell = data.name
        if data.rank and data.rank > 0 then spell = spell .. " (" .. L.RANK:format(data.rank) .. ")" end
        row.label:SetText(spell)
        -- Farb-Rollen des Design-Systems (docs/design-system.md 2.5/2.8): Doppelbelegung rot, nicht belegbar grau
        -- (ausgeschaltet), sonst weiß – Blizzards RED_/DISABLED_/HIGHLIGHT_FONT_COLOR über Core.Style.SetTextColor
        -- (Welle 23, A5: ezCores Helfer statt eines eigenen Tint; er gibt nur r, g, b weiter, kein Farbobjekt als Alpha)
        Core.Style.SetTextColor(row.label, data.conflict and "bad" or (data.state ~= "ok" and "disabled") or "highlight")
        row.mark:SetShown(data.conflict ~= nil)
        Update(row.button)
        Update(row.mods)
        row.frame:Show()
    end
    for index = #rows + 1, #P.rows do
        P.rows[index].slot, P.rows[index].data = nil, nil
        P.rows[index].frame:Hide()
    end
    P.empty:SetShown(#rows == 0)
    if #rows == 0 then P.empty:SetText(L.PREVIEW_NONE:format(ns.KindLabel(P.kind))) end

    local usable = 0
    for _, data in ipairs(rows) do
        if data.entry then usable = usable + 1 end
    end
    local bad = T.FirstConflict(rows)
    local reason
    if bad then
        reason = L.KEYS_BLOCKED:format(bad.key, bad.conflict)
    elseif #rows > 0 and usable == 0 then
        reason = L.ERR_empty
    end
    P.reason = reason
    P.status:SetText(reason or "")
    SetEnabled(P.applyButton, #rows > 0 and reason == nil, reason or L.PREVIEW_NONE:format(ns.KindLabel(P.kind)))
    SetEnabled(P.resetButton, T.HasOwnKeys(P.kind), L.KEYS_RESET_NONE)
    P.shownRows = rows
    return rows
end

-- Vorlage wählen: gespeichert als Einstellung „template“ (Nr. 74); der Hörer unten zeichnet die Vorschau neu
function P.ChooseKind(kind)
    kind = ns.ChosenKind(kind)
    P.kind = kind
    if ns.S and ns.S.template ~= kind then
        ns.SetSetting("template", kind)
    else
        P.Refresh()
    end
    return kind
end

-- Vorschau öffnen (öffnet Blizzards Fenster, falls nötig) → true | false
function P.Open(kind)
    P.kind = ns.ChosenKind(kind)
    local parent = Parent()
    if not (type(parent) == "table" and parent:IsShown()) then
        if not ns.OpenBlizzard() then return false end
    end
    if not P.Create() then return false end
    P.frame:Show()
    P.Refresh()
    if ns.Tour then ns.Tour.Start() end   -- Schritte zur Vorschau des Rundgangs (Tour.lua)
    return true
end

function P.Close()
    if P.frame then P.frame:Hide() end
end

function P.Shown()
    return P.frame ~= nil and P.frame:IsShown() and true or false
end

-- „Übernehmen …“: gleiche Rückfrage wie überall (ns.AskApply sperrt bei Doppelbelegung selbst noch einmal)
function P.Apply()
    P.Refresh()
    if P.reason then
        ns.Print(P.reason)
        return false
    end
    return ns.AskApply(P.kind)
end

-- „Vorschlag wiederherstellen“: eigene Tasten der gezeigten Vorlage verwerfen
function P.Reset()
    local count = T.ResetKeys(P.kind)
    P.Refresh()
    if count > 0 then ns.Print(L.KEYS_RESET_DONE:format(ns.KindLabel(P.kind))) end
    return count
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.BlizzardButton.ADDON, function() ns.Try("Vorschau", P.Create) end)
end)

-- Wahl auf der Seite in den Einstellungen (oder hier): die offene Vorschau zeigt sie sofort (eine Quelle, Nr. 74)
ns.OnSettingChanged(function(key)
    if key ~= "template" then return end
    P.kind = ns.ChosenKind(ns.S and ns.S.template)
    if P.Shown() then P.Refresh() end
end)
