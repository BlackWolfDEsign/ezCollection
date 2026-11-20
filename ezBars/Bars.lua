local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Die Leisten: ein Rahmen je Leiste, darin Knöpfe aus Blizzards ActionBarButtonTemplate.

    Jeder Knopf zeigt einen festen Aktionsplatz (ID 0 und Attribut „action“, so rechnet Blizzards
    SecureActionButtonMixin:CalculateAction). Name ezBarsBar<n>Button<i>: Blizzards Tastenanzeige und der
    Schnelltastenbelegungsmodus suchen „CLICK <Name>:LeftButton“, die Einträge dafür stehen in Bindings.xml.

    Taint-sicher: Leisten, Knöpfe, Anker, Größe, Plätze und Sichtbarkeit ändert ezBars nur außerhalb des Kampfes
    (sonst gleich danach über ns.AfterCombat, ezCores Reihe für das Kampfende). Die Sichtbarkeit im Kampf regelt Blizzards Zustandstreiber
    (RegisterStateDriver), leere Plätze blendet ezBars nur über die Deckkraft aus (im Kampf erlaubt).
    Blizzards Leisten werden nie verschoben, skaliert oder umgehängt; ezBars hängt seine Leisten nur an sie an.

    Verschieben: jede Leiste ist ein Teil von ezCore.Mover (Schlüssel „ezBars.bar<n>“, geschützt). Mover setzt
    den Standardplatz bzw. die gespeicherte Lage und zeigt die Auswahl im Bearbeitungsmodus und bei
    „Verschieben“; ezBars selbst hat keinen Code für den Bearbeitungsmodus.

    Leisten anderer Module (ns.RegisterBar, Core.lua; unten „Leisten anderer Module“): ein Rahmen je Leiste, darin
    gewöhnliche Knöpfe ohne Aktionsplatz – Symbol, Tooltip und Klick liefert der Anbieter. Raster, Größe, Abstand
    und Sichtbarkeit wie bei den Aktionsleisten, Standardplatz aus Anchors.lua, Mover-Schlüssel
    „ezBars.extra.<Kennung>“. Auch sie baut und ändert ezBars nur außerhalb des Kampfes (der Zustandstreiber der
    Sichtbarkeit lässt sich im Kampf nicht setzen).
]]

local Bars = {}
ns.Bars = Bars

Bars.BUTTON_SIZE = ezCore.Style.ICON.action   -- 45 wie ActionButtonTemplate (Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml)
Bars.GAP = 6                -- Abstand zwischen den Leisten am Standardplatz

--[[
    Knopfgröße und Abstand – EIN Weg für alle Leisten (Aktionsleisten, leere Felder, Leisten anderer Module) und beide
    Ausrichtungen, wie Blizzards Bearbeitungsmodus („Symbolgröße“: EditModeActionBarSystemMixin:
    UpdateSystemSettingIconSize setzt SetScale auf jeden Knopf, GridLayoutUtil verankert mit Breite plus Abstand in
    dessen Maßstab): Jeder Knopf bleibt 45 × 45 in seinen eigenen Einheiten und wird als Ganzes skaliert. Symbol, Maske,
    Rand, Glanz, Spirale und Texte wachsen dadurch gemeinsam, und der Abstand wächst mit (Einstellung „Abstand“ = Pixel
    bei 100 %). Spieltest 15.11.2026 („hier habe die zweite emote leite des ezmacro größer gemacht, skaliert mit icon
    irgendwie nicht korrekt“): vorher bekamen nur die Knöpfe anderer Module per SetSize eine neue Größe, ihr Symbol lag
    ohne Blizzards Maske im gestreckten Rahmen, und der Abstand blieb fest.
]]
function Bars.Scale(key)
    return math.max(0.5, math.min(2, (tonumber(ns.BarSetting(key, "Size")) or 100) / 100))
end

function Bars.Padding(key)
    return math.max(0, tonumber(ns.BarSetting(key, "Padding")) or 0)
end

-- Fläche eines Rasters aus cols × rows Knöpfen in Einheiten der Leiste.
function Bars.GridSize(cols, rows, scale, padding)
    local pitch = Bars.BUTTON_SIZE + padding
    return (cols * pitch - padding) * scale, (rows * pitch - padding) * scale
end

-- Setzt frame in Spalte col, Reihe row (ab 0) des Rasters, gezählt ab der Ecke corner der Leiste; dx, dy: Richtung
-- (1 = nach rechts bzw. oben, -1 = nach links bzw. unten). Der Versatz steht im Maßstab des Knopfes.
function Bars.PlaceInGrid(frame, bar, corner, dx, dy, col, row, scale, padding)
    local pitch = Bars.BUTTON_SIZE + padding
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint(corner, bar, corner, dx * col * pitch, dy * row * pitch)
end

-- Wie Blizzards Leisten: in Fahrzeugen, mit Ersatzleiste und im Haustierkampf aus.
local HIDE = "[petbattle][vehicleui][overridebar] hide; "
Bars.VISIBILITY = {
    always = HIDE .. "show",
    combat = HIDE .. "[combat] show; hide",
    nocombat = HIDE .. "[nocombat] show; hide",
    hidden = "hide",
}

local frames = {}           -- [n] = Rahmen der Leiste
local extraFrames = {}      -- [Kennung] = Rahmen einer Leiste eines anderen Moduls
local slotButtons = {}      -- [Platz] = Knopf einer sichtbaren Leiste
local gridReasons = {}      -- Gründe, aus denen leere Plätze gerade zu sehen sind (Ziehen, Tastenbelegung)
local pending, pendingNotified = false, false
local extraPending = false  -- Leisten anderer Module warten auf das Kampfende
local reported = {}         -- Überschneidungen, die in dieser Sitzung schon gemeldet wurden

function Bars.Frame(n) return frames[n] end
function Bars.Pending() return pending or extraPending end
function Bars.ExtraFrame(id) return extraFrames[id] end
function Bars.ButtonName(n, i) return ("ezBarsBar%dButton%d"):format(n, i) end

-- Belegt? Über ezCore (Core.ActionSlots.Has: gesperrter Wert → true, lieber zeigen).
local function HasAction(slot)
    return slot ~= nil and Core.ActionSlots.Has(slot)
end

---------------------------------------------------------------------------
-- Rahmen und Knöpfe (nur außerhalb des Kampfes)
---------------------------------------------------------------------------

-- Standardplatz, solange ezCore.Mover fehlt: Leiste 1 links neben Blizzards rechten Leisten, jede weitere links
-- daneben. Blizzards Rahmen dienen nur als Anker; wandern sie im Bearbeitungsmodus, wandern die Leisten mit.
function Bars.DefaultAnchor(n)
    if n > 1 and frames[n - 1] then return "RIGHT", frames[n - 1], "LEFT", -Bars.GAP, 0 end
    local left = rawget(_G, "MultiBarLeft")
    if type(left) == "table" then return "RIGHT", left, "LEFT", -Bars.GAP, 0 end
    return "RIGHT", UIParent, "RIGHT", -100, 0
end

-- Speicherplatz der Lage in ezCoreDB.positions: Aktionsleiste n bzw. Kennung einer Leiste eines anderen Moduls.
function Bars.MoverKey(n)
    if type(n) == "number" then return "ezBars.bar" .. n end
    return "ezBars.extra." .. tostring(n)
end

-- Aufklapp-Richtung neu, nachdem Mover eine Leiste verschoben oder zurückgesetzt hat.
local function Moved()
    if ns.InCombat() then
        Bars.Apply()        -- merkt sich die Änderung für nach dem Kampf
    else
        Bars.UpdateFlyouts()
    end
end

-- Meldet die Leiste bei ezCore.Mover an; der setzt sie an ihren Platz. Ohne Mover (alte Basis): Standardplatz.
local function Place(bar, n)
    local mover = Core.Mover
    if not (mover and mover.Register) then
        bar:ClearAllPoints()
        bar:SetPoint(Bars.DefaultAnchor(n))
        return
    end
    local point, relative, relPoint, x, y = Bars.DefaultAnchor(n)
    bar.ezPart = mover.Register(bar, {
        key = Bars.MoverKey(n),
        label = L.MOVER_LABEL:format(n),
        owner = ns.moduleName,
        anchor = { point, relative, relPoint, x, y },
        protected = true,
        enabled = ns.BarSetting(n, "On") == true,
        onMove = Moved,
    })
end

local function CreateBar(n)
    if frames[n] then return frames[n] end
    if n > 1 then CreateBar(n - 1) end      -- Anker für den Standardplatz
    local bar = CreateFrame("Frame", "ezBarsBar" .. n, UIParent)
    ezCore.Style.SetStrata(bar, "hud")   -- MEDIUM wie Blizzards Leisten (Design-System 2.6, Rolle hud)
    bar:SetSize(1, 1)
    bar:Hide()
    bar.ezIndex = n
    bar.buttons = {}
    frames[n] = bar
    Place(bar, n)
    return bar
end

local function GetButton(bar, i)
    local button = bar.buttons[i]
    if button then return button end
    button = CreateFrame("CheckButton", Bars.ButtonName(bar.ezIndex, i), bar, "ActionBarButtonTemplate")
    -- Schnelltastenbelegungsmodus: Blizzard belegt den Befehl in commandName (wie seine eigenen Leisten).
    button.commandName = "CLICK " .. button:GetName() .. ":LeftButton"
    bar.buttons[i] = button
    -- Kennzeichen an Makros der ezCollection (ezCore.MacroBadge, Welle 15): ezCore hängt eine eigene Kind-Textur an
    -- und zeichnet sie bei jedem Update des Knopfs neu; abschaltbar auf der Seite „ezCollection“
    local badge = Core.MacroBadge
    if badge and badge.Watch then badge.Watch(button) end
    return button
end

-- Aufklapp-Richtung der Zauber-Flyouts wie bei Blizzards Leisten: zur Bildschirmmitte hin.
local function FlyoutDirection(bar)
    local _, y = bar:GetCenter()
    local height = GetScreenHeight and GetScreenHeight()
    if y and height and y > height / 2 then return "DOWN" end
    return "UP"
end

-- Feld ohne Aktionsplatz (zu wenig freie Seiten): Blizzards leerer Knopf aus ActionButtonTemplate (Hintergrund
-- „UI-HUD-ActionBar-IconFrame-Background“, Rahmen „UI-HUD-ActionBar-IconFrame“), grau und halb durchsichtig, mit
-- Erklärung im Tooltip. Ein gewöhnlicher Rahmen ohne Aktion (nicht geschützt), angelegt nur außerhalb des Kampfes.
local function GetEmptyField(bar, i)
    bar.emptyFields = bar.emptyFields or {}
    local field = bar.emptyFields[i]
    if field then return field end
    field = CreateFrame("Frame", nil, bar)
    field:SetSize(Bars.BUTTON_SIZE, Bars.BUTTON_SIZE)
    field.Background = field:CreateTexture(nil, "BACKGROUND")
    field.Background:SetAllPoints()
    Core.SetIcon(field.Background, "UI-HUD-ActionBar-IconFrame-Background", "Interface\\Buttons\\UI-EmptySlot-Disabled")
    field.Background:SetDesaturated(true)
    field.Border = field:CreateTexture(nil, "ARTWORK")
    field.Border:SetAllPoints()
    if Core.AtlasExists("UI-HUD-ActionBar-IconFrame") then field.Border:SetAtlas("UI-HUD-ActionBar-IconFrame") end
    field.Border:SetDesaturated(true)
    field:SetAlpha(0.6)
    field:EnableMouse(true)
    field:SetScript("OnEnter", Core.TipScript(L.EMPTY_FIELD, L.EMPTY_FIELD_TIP))
    field:SetScript("OnLeave", function() GameTooltip:Hide() end)
    field.ezEmptyField = true
    bar.emptyFields[i] = field
    return field
end

-- Versteckt alle Rahmen ab Stelle first (Listen mit Lücken: leere Felder beginnen erst nach den Knöpfen).
local function HideFrom(list, first)
    for i, frame in pairs(list or {}) do
        if i >= first then frame:Hide() end
    end
end

--[[
    Knöpfe, die wegfallen (über der Rasterzahl, ohne freien Aktionsplatz, Leiste abgeschaltet), verlieren ihre Aktion
    (Gesamtreview 18.11.2026, T9-NB3): Ihre Taste (CLICK ezBarsBar<n>Button<i>) drückt den Knopf auch versteckt, und
    sein Aktionsplatz wirkte sonst unsichtbar weiter. „action“ bleibt stehen – ohne Wert rechnet Blizzards
    SecureActionButtonMixin:CalculateAction Platz 1 –, gelöst werden „type“ und „typerelease“ (beide setzt Blizzards
    ActionBarActionButtonMixin:OnLoad, Gethe/wow-ui-source Zweig forever, Shared/ActionButton.lua, Zeilen 460 f.).
    Ohne „type“ tut der Klick nichts. Arm setzt beide wieder, sobald Layout den Knopf zeigt. Nur außerhalb des Kampfes (Layout und
    Apply laufen nur dann). Die Sichtbarkeit „Versteckt“ bzw. „Im Kampf“ einer eingeschalteten Leiste lässt die
    Aktion stehen – wie bei Blizzards Leisten wirken die Tasten dann weiter.
]]
Bars.ACTION_TYPE, Bars.RELEASE_TYPE = "action", "actionrelease"

local function Arm(button)
    if button:GetAttribute("type") ~= Bars.ACTION_TYPE then button:SetAttribute("type", Bars.ACTION_TYPE) end
    if button:GetAttribute("typerelease") ~= Bars.RELEASE_TYPE then button:SetAttribute("typerelease", Bars.RELEASE_TYPE) end
end

local function Disarm(button)
    if button:GetAttribute("type") ~= nil then button:SetAttribute("type", nil) end
    if button:GetAttribute("typerelease") ~= nil then button:SetAttribute("typerelease", nil) end
    button:Hide()
end

-- Knöpfe ab Stelle first entwaffnen und verstecken (first = 1: alle Knöpfe der Leiste).
local function DisarmFrom(buttons, first)
    for i, button in pairs(buttons or {}) do
        if i >= first then Disarm(button) end
    end
end

local function Layout(bar, n, pages)
    local count = ns.Slots.ButtonCount(n)
    local cols = math.max(1, math.min(math.floor(ns.BarSetting(n, "Cols") or 1), count))
    local rows = math.ceil(count / cols)
    local scale, padding = Bars.Scale(n), Bars.Padding(n)
    local direction = FlyoutDirection(bar)
    local function Place(frame, i)
        Bars.PlaceInGrid(frame, bar, "TOPLEFT", 1, -1, (i - 1) % cols, math.floor((i - 1) / cols), scale, padding)
    end
    for i = 1, count do
        local slot = ns.Slots.SlotFor(pages, i)
        if slot then
            local button = GetButton(bar, i)
            Place(button, i)
            if button:GetAttribute("action") ~= slot then button:SetAttribute("action", slot) end
            Arm(button)
            if button:GetAttribute("flyoutDirection") ~= direction then button:SetAttribute("flyoutDirection", direction) end
            slotButtons[slot] = button
            button:Show()
            if bar.emptyFields and bar.emptyFields[i] then bar.emptyFields[i]:Hide() end
        else
            -- kein freier Aktionsplatz: Knopf weg (ohne Aktion, T9-NB3), leeres Feld an seiner Stelle
            if bar.buttons[i] then Disarm(bar.buttons[i]) end
            local field = GetEmptyField(bar, i)
            Place(field, i)
            field:Show()
        end
    end
    DisarmFrom(bar.buttons, count + 1)
    HideFrom(bar.emptyFields, count + 1)
    bar:SetSize(Bars.GridSize(cols, rows, scale, padding))
end

-- Leere Felder einer Leiste, die gerade zu sehen sind (Zeile der Leiste in /ezbars status, Core.lua; auch die Tests).
function Bars.EmptyFields(n)
    local bar, shown = frames[n], 0
    for _, field in pairs(bar and bar.emptyFields or {}) do      -- Felder liegen an ihrer Stelle (z. B. ab 133)
        if field:IsShown() then shown = shown + 1 end
    end
    return shown
end

-- Nur außerhalb des Kampfes (Attribute geschützter Knöpfe).
function Bars.UpdateFlyouts()
    if ns.InCombat() then return false end
    for _, bar in pairs(frames) do
        local direction = FlyoutDirection(bar)
        for _, button in ipairs(bar.buttons) do
            if button:GetAttribute("flyoutDirection") ~= direction then button:SetAttribute("flyoutDirection", direction) end
        end
    end
    return true
end

local function SetVisibility(bar, condition)
    if bar.ezDriver == condition then return end
    if bar.ezDriver then UnregisterStateDriver(bar, "visibility") end
    bar.ezDriver = condition
    if condition then
        RegisterStateDriver(bar, "visibility", condition)
    else
        bar:Hide()
    end
end

-- Meldet neue Überschneidungen einmal je Sitzung im Chat (/ezbars status zeigt alle).
-- Fehlende Plätze meldet ezBars gebündelt eine Sekunde später: Wer „Reihen“ zieht, bekommt eine Meldung mit dem
-- Endstand statt einer je Zwischenwert.
local function ReportShortages()
    for _, entry in ipairs(ns.Slots.Shortages()) do
        local text = ns.Slots.ShortageText(entry)
        if not reported[text] then
            reported[text] = true
            ns.Print(text)
        end
    end
end
local ReportShortagesSoon = ns.Throttle(ReportShortages, 1)

local function ReportConflicts(resolved)
    local short = {}
    for _, entry in ipairs(ns.Slots.Shortages(resolved)) do short[ns.Slots.ShortageText(entry)] = true end
    for _, text in ipairs(ns.Slots.Conflicts(resolved)) do
        if not short[text] and not reported[text] then
            reported[text] = true
            ns.Print(text)
        end
    end
    if next(short) then ReportShortagesSoon() end
end

-- Einmal je Kampf sagen, dass ezBars wartet (Aktionsleisten und Leisten anderer Module teilen sich den Hinweis).
local function NotifyPending()
    if pendingNotified then return end
    pendingNotified = true
    Core.CombatNotice(ns, L.APPLY_WHAT, "later")
end

-- Richtet alle Leisten nach den Einstellungen ein. Im Kampf: merken und nach dem Kampf nachholen – über ezCores
-- gemeinsame Reihe (ns.AfterCombat, Schlüssel „apply“: viele Änderungen im Kampf ergeben ein Einrichten danach).
function Bars.Apply()
    if ns.InCombat() then
        pending = true
        ns.AfterCombat(Bars.Apply, "apply")
        NotifyPending()
        return false
    end
    pending, pendingNotified = false, false
    Bars.ready = true                            -- ab jetzt baut auch Bars.ApplyExtras (vorher nur vorgemerkt)
    local resolved = ns.Slots.Resolve(true)      -- die eine Stelle, die Seiten merkt (V-154)
    wipe(slotButtons)
    for n = 1, ns.MAX_BARS do
        local on = ns.BarSetting(n, "On") == true
        local bar = frames[n] or (on and CreateBar(n)) or nil
        if bar then
            if on then
                Layout(bar, n, resolved[n] or {})
                SetVisibility(bar, Bars.VISIBILITY[ns.BarSetting(n, "Show")] or Bars.VISIBILITY.always)
            else
                SetVisibility(bar, nil)
                DisarmFrom(bar.buttons, 1)          -- abgeschaltet: Tasten der Knöpfe wirken nicht weiter (T9-NB3)
                bar:SetSize(1, 1)
            end
            if bar.ezPart then bar.ezPart:SetEnabled(on) end    -- abgeschaltet: keine Auswahl beim Verschieben
        end
    end
    Bars.UpdateEmpty()
    ReportConflicts(resolved)
    Bars.ApplyExtras()                      -- Leisten anderer Module (unten)
    if ns.Tour then ns.Tour.Later() end     -- Erklärblasen, sobald eine Leiste zum ersten Mal zu sehen ist
    return true
end

function Bars.ButtonForSlot(slot)
    local button = slotButtons[slot]
    if button and button:GetParent() and button:GetParent():IsShown() then return button end
    return nil
end

---------------------------------------------------------------------------
-- Leisten anderer Module (ns.RegisterBar): gewöhnliche Knöpfe ohne Aktionsplatz, nur außerhalb des Kampfes gebaut
---------------------------------------------------------------------------

-- Sichtbarkeit ohne die Ausnahmen der Aktionsleisten: Diese Leisten tragen keine Aktionen (Emotes, Ansagen …) und
-- bleiben wie der Chat auch im Fahrzeug stehen.
Bars.VISIBILITY_EXTRA = {
    always = "show",
    combat = "[combat] show; hide",
    nocombat = "[nocombat] show; hide",
    hidden = "hide",
}

-- Blizzards Aktionsknopf-Rahmen (ActionButtonTemplate, wie GetEmptyField oben); fehlt ein Atlas, bleibt das Symbol.
local FRAME_ATLAS, FRAME_DOWN, FRAME_OVER = "UI-HUD-ActionBar-IconFrame", "UI-HUD-ActionBar-IconFrame-Down",
    "UI-HUD-ActionBar-IconFrame-Mouseover"
local NO_ICON = Core.ICON_FALLBACK   -- ezCores Ersatzsymbol (Gesamtreview 18.11.2026, T16-NM6)

-- Fehler in einer Funktion oder Angabe des Anbieters (onClick, tooltip, eigener Anker): in die Fehlerliste seines
-- Moduls (sonst ezBars), nie an den Spieler durch.
local function ProviderError(entry, where, err)
    local owner = entry.owner and Core.Module(entry.owner) and entry.owner or ns.moduleName
    Core.Error(owner, err, "ezBars " .. tostring(entry.id) .. " " .. where)
end

local function CallProvider(entry, where, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return true, a, b end
    ProviderError(entry, where, a)
    return false
end

-- Tooltip zur Bildschirmmitte hin (wie die Erklärblasen in Tour.lua).
local function TipAnchor(bar)
    local x = bar:GetCenter()
    local width = GetScreenWidth and GetScreenWidth()
    if x and width and x > width / 2 then return "ANCHOR_LEFT" end
    return "ANCHOR_RIGHT"
end

-- Tooltip eines Knopfes: Text des Anbieters, oder seine Funktion (gibt Titel und Text zurück oder füllt GameTooltip
-- selbst). Nie leer (Leitlinie 11): Ohne Angabe steht der Name der Leiste da.
local function ExtraEnter(self)
    local bar = self:GetParent()
    local entry, button = ns.Extra(bar.ezId), self.ezButton
    if not (entry and button) then return end
    GameTooltip:SetOwner(self, TipAnchor(bar))
    local title, text = button.tooltip, button.text
    if type(title) == "function" then
        local _, a, b = CallProvider(entry, "tooltip", title, self)
        title, text = a, b
    end
    if type(title) == "string" and title ~= "" then
        Core.TipTitle(GameTooltip, title)          -- Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
        if type(text) == "string" and text ~= "" then GameTooltip:AddLine(text, nil, nil, nil, true) end
    elseif not (GameTooltip.NumLines and (GameTooltip:NumLines() or 0) > 0) then
        Core.TipTitle(GameTooltip, entry.name)
    end
    GameTooltip:Show()
end

local function ExtraLeave() GameTooltip:Hide() end

local function ExtraClick(self, mouseButton)
    local entry, button = ns.Extra(self:GetParent().ezId), self.ezButton
    if entry and button then CallProvider(entry, "onClick", button.onClick, self, mouseButton) end
end

local function ExtraDown(self)
    if self.ezDown and self.Border then self.Border:SetAtlas(FRAME_DOWN) end
end

local function ExtraUp(self)
    if self.ezDown and self.Border then self.Border:SetAtlas(FRAME_ATLAS) end
end

local function GetExtraButton(bar, i)
    local button = bar.buttons[i]
    if button then return button end
    button = CreateFrame("Button", bar:GetName() .. "Button" .. i, bar)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Feste Größe wie Blizzards ActionButtonTemplate; die Knopfgröße der Leiste kommt über SetScale (Bars.PlaceInGrid).
    button:SetSize(Bars.BUTTON_SIZE, Bars.BUTTON_SIZE)
    -- Symbol mit Blizzards Maske „UI-HUD-ActionBar-IconFrame-Mask“ und Rahmen „UI-HUD-ActionBar-IconFrame“ um das
    -- Symbol (ezCores Core.StyleIcon, wie die Auren-Reihe): Das Symbol füllt den Rahmen, ohne Ecken darüber hinaus.
    Core.StyleIcon(button)
    button.Border = button.border
    button.ezDown = button.Border ~= nil and Core.AtlasExists(FRAME_DOWN)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button.Border or button)     -- Glanz auf dem Rahmen wie Blizzards HighlightTexture
    button.ezHighlight = highlight
    if Core.AtlasExists(FRAME_OVER) then
        highlight:SetAtlas(FRAME_OVER)
    else
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")
    end
    button:SetScript("OnMouseDown", ExtraDown)
    button:SetScript("OnMouseUp", ExtraUp)
    button:SetScript("OnClick", ExtraClick)
    button:SetScript("OnEnter", ExtraEnter)
    button:SetScript("OnLeave", ExtraLeave)
    bar.buttons[i] = button
    return button
end

local function CreateExtraBar(id)
    local bar = CreateFrame("Frame", "ezBarsExtra" .. id, UIParent)      -- die eine Stelle, die den Namen bildet
    ezCore.Style.SetStrata(bar, "hud")   -- MEDIUM wie Blizzards Leisten (Design-System 2.6, Rolle hud)
    bar:SetSize(1, 1)
    bar:Hide()
    bar.ezId = id
    bar.buttons = {}
    extraFrames[id] = bar
    return bar
end

-- Von ezCore.Mover verschoben oder zurückgesetzt: Raster und Anker neu – eine verschobene Leiste hängt nicht mehr am
-- Chat, eine zurückgesetzte wieder. Ohne eigenen Hinweis im Chat (im Kampf sagt es, wer zurücksetzt: ns.ExtraHome).
local function ExtraMoved()
    Bars.ApplyExtras(true)
end

-- Standardplatz (Anchors.lua) bzw. gemerkte Lage über ezCore.Mover; ohne Mover nur der Standardplatz.
local function PlaceExtra(bar, entry, index)
    local point, corner, docked = ns.Anchors.Resolve(entry, index)
    local mover = Core.Mover
    local movable = mover ~= nil and mover.Register ~= nil
    -- Verschoben (gemerkte Lage): Die Leiste hängt nicht mehr am Chat. Ihr Raster spiegelt nicht mehr mit seiner
    -- Seite (es beginnt links, wie am Standardplatz bei Chat-Knöpfen links), sie folgt den Reitern nicht in der Ebene,
    -- und ns.ExtraInfo nennt docked = "free" neben moved = true.
    if movable and Core.StoredPosition(Bars.MoverKey(entry.id)) ~= nil then
        corner, docked = (corner:gsub("RIGHT", "LEFT")), "free"
    end
    bar.ezCorner, bar.ezDocked = corner, docked
    if movable then
        -- Register ist wiederholbar: neuer Anker (der Chat hat die Seite gewechselt), neuer Name, Teil wieder an
        bar.ezPart = mover.Register(bar, {
            key = Bars.MoverKey(entry.id),
            label = L.EXTRA_MOVER_LABEL:format(entry.name),
            owner = ns.moduleName,
            anchor = point,
            protected = true,       -- wie die Aktionsleisten: im Kampf weder ziehen noch setzen
            enabled = true,
            onMove = ExtraMoved,
        })
    else
        bar:ClearAllPoints()
        local relative = point[2]
        if type(relative) == "string" then relative = rawget(_G, relative) end
        bar:SetPoint(point[1], relative or UIParent, point[3], point[4], point[5])
    end
    if docked == "chatTop" then ns.Anchors.RaiseAboveTabs(bar) end
end

-- Knöpfe ins Raster: Spalten × Reihen aus den Einstellungen, gefüllt ab der Ecke, die der Anker vorgibt. Liefert der
-- Anbieter mehr Knöpfe, als das Raster fasst, zeigt die Leiste die ersten (Status, Tooltip der Regler und ein Hinweis
-- im Chat nennen die Zahl); liefert er weniger, ist die Leiste nur so groß wie nötig.
local function LayoutExtra(bar, entry)
    local id = entry.id
    local info = ns.ExtraInfo(id)
    local cols, shown = info.cols, info.shown
    local scale, padding = Bars.Scale(id), Bars.Padding(id)
    local corner = bar.ezCorner or "TOPLEFT"
    local dx = corner:find("RIGHT", 1, true) and -1 or 1
    local dy = corner:find("BOTTOM", 1, true) and 1 or -1
    for i = 1, shown do
        local data = entry.buttons[i]
        local button = GetExtraButton(bar, i)
        button.ezButton = data
        Bars.PlaceInGrid(button, bar, corner, dx, dy, (i - 1) % cols, math.floor((i - 1) / cols), scale, padding)
        Core.SetIcon(button.icon, data.atlas, data.icon or NO_ICON)
        button:Show()
    end
    for i = shown + 1, #bar.buttons do
        bar.buttons[i].ezButton = nil
        bar.buttons[i]:Hide()
    end
    local usedCols = math.max(1, math.min(cols, shown))
    local usedRows = math.max(1, math.ceil(shown / cols))
    bar:SetSize(Bars.GridSize(usedCols, usedRows, scale, padding))
end

-- Hinweis im Chat, wenn eine Leiste nicht alle gelieferten Knöpfe zeigt – gebündelt (wer einen Regler zieht, bekommt
-- eine Meldung mit dem Endstand) und je Stand einmal je Sitzung. /ezbars status zeigt es immer.
local function ReportCut()
    for _, entry in ipairs(ns.Extras()) do
        local info = ns.ExtraInfo(entry.id)
        if info.cut > 0 then
            local text = L.EXTRA_CUT:format(ns.ExtraTitle(entry), info.buttons, info.cols, info.rows, info.shown)
            if not reported[text] then
                reported[text] = true
                ns.Print(text)
            end
        end
    end
end
local ReportCutSoon = ns.Throttle(ReportCut, 1)

-- Reiter im Chat neu geordnet: Leisten auf den Reitern wieder eine Ebene darüber (nur die Ebene des eigenen,
-- ungeschützten Rahmens – das ist auch im Kampf erlaubt).
function Bars.RaiseExtras()
    for _, bar in pairs(extraFrames) do
        if bar.ezDocked == "chatTop" and ns.Extra(bar.ezId) then ns.Anchors.RaiseAboveTabs(bar) end
    end
end

local ApplyExtrasSoon = ns.Throttle(function() Bars.ApplyExtras() end, 0.1)

-- Eine Leiste einrichten: an ihren Platz, Knöpfe ins Raster, Sichtbarkeit.
local function SetupExtra(bar, entry, index)
    PlaceExtra(bar, entry, index)
    LayoutExtra(bar, entry)
    SetVisibility(bar, Bars.VISIBILITY_EXTRA[ns.BarSetting(entry.id, "Show")] or Bars.VISIBILITY_EXTRA.always)
end

-- Jede Leiste für sich abgeschirmt: Ein Fehler beim Einrichten (etwa ein eigener Anker des Anbieters, an dem sich
-- nicht verankern lässt – SetPoint wirft dann) kommt in die Fehlerliste des Anbieters und hält weder die übrigen
-- Leisten noch Bars.Apply auf. Die Leiste steht danach frei (entry.anchorFailed, bis der Anbieter sie neu anmeldet;
-- ns.ExtraInfo: docked = "free"); scheitert auch das, bleibt sie versteckt.
local function SetupExtraSafely(bar, entry, index)
    if CallProvider(entry, "anchor", SetupExtra, bar, entry, index) then return true end
    if not entry.anchorFailed then
        entry.anchorFailed = true
        if CallProvider(entry, "setup", SetupExtra, bar, entry, index) then return true end
    end
    pcall(SetVisibility, bar, nil)
    return false
end

-- „Standardplatz“ ließ sich nicht setzen (ns.ExtraHome, Options.lua: ezCore.Mover.Reset warf am Anker des Anbieters):
-- Fehlerliste des Anbieters, die Leiste steht ab jetzt frei.
function Bars.ExtraAnchorFailed(entry, err)
    ProviderError(entry, "anchor", err)
    entry.anchorFailed = true
    return Bars.ApplyExtras(true)
end

-- Richtet die Leisten anderer Module ein: anlegen, an ihren Platz, Knöpfe ins Raster, Sichtbarkeit; abgemeldete
-- Leisten verschwinden. Vor dem Einloggen und im Kampf nur vormerken (Schlüssel „extras“ in ezCores Reihe).
-- quiet: im Kampf ohne den Hinweis „nach dem Kampf“ (der Aufrufer sagt es selbst).
function Bars.ApplyExtras(quiet)
    if not Bars.ready then return false end
    if ns.InCombat() then
        extraPending = true
        ns.AfterCombat(Bars.ApplyExtras, "extras")
        if quiet ~= true then NotifyPending() end
        return false
    end
    extraPending = false
    if not pending then pendingNotified = false end
    local list, wanted = ns.Extras(), {}
    for index, entry in ipairs(list) do
        wanted[entry.id] = true
        SetupExtraSafely(extraFrames[entry.id] or CreateExtraBar(entry.id), entry, index)
    end
    for id, bar in pairs(extraFrames) do
        if not wanted[id] then
            SetVisibility(bar, nil)
            bar:SetSize(1, 1)
            if bar.ezPart then bar.ezPart:SetEnabled(false) end     -- abgemeldet: keine Auswahl beim Verschieben
        end
    end
    if #list > 0 then
        ns.Anchors.Watch(ApplyExtrasSoon, Bars.RaiseExtras)
        ns.Anchors.Placed()                 -- Stand des Chats, nach dem gerade ausgerichtet wurde
        ReportCutSoon()
    end
    return true
end

---------------------------------------------------------------------------
-- Leere Plätze (Deckkraft, auch im Kampf erlaubt)
---------------------------------------------------------------------------

function Bars.ShowGrid(reason, shown)
    gridReasons[reason] = shown and true or nil
    Bars.UpdateEmpty()
end

function Bars.GridShown() return next(gridReasons) ~= nil end

function Bars.UpdateEmpty()
    local showAll = Bars.GridShown()
    for n, bar in pairs(frames) do
        local showEmpty = showAll or ns.BarSetting(n, "Empty") == true
        for _, button in ipairs(bar.buttons) do
            local visible = showEmpty or HasAction(button:GetAttribute("action"))
            button:SetAlpha(visible and 1 or 0)
        end
    end
end

local UpdateEmptySoon = ns.Throttle(Bars.UpdateEmpty, 0.05)

ns.On("ACTIONBAR_SLOT_CHANGED", function() UpdateEmptySoon() end)
ns.On("ACTIONBAR_SHOWGRID", function() Bars.ShowGrid("drag", true) end)
ns.On("ACTIONBAR_HIDEGRID", function() Bars.ShowGrid("drag", false) end)
ns.On("PLAYER_ENTERING_WORLD", function() UpdateEmptySoon() end)

-- Blizzards Schnelltastenbelegungsmodus: leere Plätze zeigen und Knöpfe hervorheben wie Blizzards eigene.
local function QuickKeybind(active)
    Bars.ShowGrid("keybind", active)
    for _, bar in pairs(frames) do
        for _, button in ipairs(bar.buttons) do
            if type(button.DoModeChange) == "function" then pcall(button.DoModeChange, button, active) end
        end
    end
end
local registry = rawget(_G, "EventRegistry")
if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function() QuickKeybind(true) end, Bars)
    registry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function() QuickKeybind(false) end, Bars)
end

---------------------------------------------------------------------------
-- Auslöser
---------------------------------------------------------------------------

ns.OnReady(Bars.Apply)

-- Gestalt/Haltung gewechselt: neue Seite der Klasse lernen und eine Überschneidung sofort melden.
local function BonusBarChanged()
    if ns.Slots.LearnBonusBar() then ReportConflicts(ns.Slots.Resolve()) end
end
ns.On("UPDATE_BONUS_ACTIONBAR", BonusBarChanged)
ns.On("UPDATE_SHAPESHIFT_FORM", BonusBarChanged)

-- Einstellungen (Schieberegler liefern viele Werte hintereinander: gesammelt einmal anwenden).
local ApplySoon = ns.Throttle(function() Bars.Apply() end, 0.1)
ns.OnSettingChanged(function(key)
    if type(key) ~= "string" then return end
    if key:match("^bar%d") then
        ApplySoon()
    elseif ns.ExtraKeyParts(key) then
        ApplyExtrasSoon()
    end
end)
