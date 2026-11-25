local _, ns = ...
local Core = ezCore

--[[
    Teile verschieben (ezCore.Mover): die eine Anbindung an Blizzards Bearbeitungsmodus für alle Module.
    Ein Modul meldet seine Teile nur an und baut selbst nichts für den Bearbeitungsmodus:

      local part = ezCore.Mover.Register(frame, {
          key = "ezCombat.center",               -- Speicherplatz in ezCoreDB.positions (eindeutig, Pflicht)
          label = L.CENTER,                       -- Name an der Auswahl (Standard: key)
          owner = "ezCombat",                     -- Modul: Knopf „Verschieben“, Zurücksetzen, Fehlerliste
          anchor = { "BOTTOM", "TargetFrame", "TOP", 0, 4 },   -- Standardplatz; an Blizzards Fenster wandert
                                                  -- das Teil mit, solange es nicht verschoben wurde
          onMove = function(frame, pos) end,      -- nach Verschieben und Zurücksetzen (pos nil = Standardplatz)
          protected = true,                       -- geschützter Rahmen: nur außerhalb des Kampfes
                                                  -- (Standard: frame:IsProtected())
          minWidth = 32, minHeight = 32,          -- Mindestgröße der Auswahl (kleine oder leere Teile)
          import = { point, relPoint, x, y },     -- alte Position aus dem Modul, einmal übernommen
      })
      part:Apply()  part:Reset()  part:Position()  part:SetEnabled(bool)  part:SetLabel(text)

    - Beim Öffnen von Blizzards Bearbeitungsmodus bekommt jedes Teil eine Auswahl wie Blizzards Systeme
      (Rahmen editmode-actionbar-highlight bzw. -selected, Name, Einrasten am Raster, wenn Blizzards
      „Einrasten“ und das Raster an sind). Auch versteckte Teile zeigen ihre Auswahl; sie folgt der Größe.
      Linksziehen verschiebt, Rechtsklick öffnet ein Menü mit „Position zurücksetzen“.
    - Mover.Unlock(owner, page) zeigt dieselbe Auswahl ohne Blizzards Bearbeitungsmodus, mit einer Leiste
      „Fertig“ und „Zurücksetzen“ (Rückfall des Knopfs „Verschieben“ der Modulseiten, page:MoverButton()); Blizzards
      Einstellungen schließen dabei und öffnen mit „Fertig“ wieder. Die Leiste nennt den Weg „Esc » Bearbeitungsmodus“.
    - Ein Modus (EC-11, EC-12, Frage 32): „Verschieben“ öffnet immer den eigenen Modus wie oben (Mover.Open).
      Blizzards Bearbeitungsmodus öffnet nur Blizzards eigenes Menü (Esc » Bearbeitungsmodus), nie Addon-Code: aus
      Addon-Code geöffnet lief sein ganzer Ablauf verunreinigt (Spielbefund vom 22.11.2026: Gruppenrahmen mit
      Vorschauwert „IncomingSummonPending“ und gesperrtem outOfRange, „execution tainted by ezCore“). Den Testschalter
      „comfort.editModeOpen“ hat der Nutzer am 22.11.2026 gestrichen („ja entfernen aber noch verschieben danach möglich?“).
    - Im Bearbeitungsmodus (EC-10, Entscheidung „Sofort merken + Hinweis“): Unter Blizzards Fenster steht der Hinweis,
      dass ez-Teile sofort gemerkt werden, mit dem Knopf „ez-Teile verwerfen“. Beim Betreten sichert ezCore die Lage
      aller Teile (Mover.Snapshot); der eigene Knopf und Blizzards „Alle Änderungen verwerfen“ (HookScript am
      RevertAllChangesButton; Blizzard gibt ihn nur frei, wenn es selbst Änderungen hat) setzen sie auf diesen Stand
      zurück (Mover.Revert). Der Hinweis nennt darum den eigenen Knopf. In Blizzards Zustand wird nichts geschrieben.
    - Position relativ zu UIParent in ezCoreDB.positions[key] = { point, relPoint, x, y } (ersetzt
      SavePosition/ApplyPosition in den Modulen); ohne gespeicherte Position bleibt der Standardanker.
    - Blizzards Systeme, ihre Liste und ihre Auswahl bleiben unberührt: kein SelectSystem, keine Anmeldung,
      kein Wert in EditModeManagerFrame. Gelesen werden nur IsSnapEnabled und der Rasterabstand.
    - Geschützte Teile: im Kampf weder ziehen noch setzen; Positionen werden nach dem Kampf nachgeholt.
      Beim Kampfbeginn schließt die eigene Auswahl (Unlock).

    Mover.Register(frame, opts) → part         Mover.Get(key) → part
    Mover.Parts(owner) → { part … }            Mover.Reset(key) → true | Mover.ResetAll(owner) → Anzahl
    Mover.Unlock(owner, page)  Mover.Lock([reopen])  Mover.IsUnlocked()  Mover.IsShowing()
    Mover.Select(key)                          (Auswahl hervorheben, wie ein Klick)
    Mover.Open(owner, page) → "unlock"   (Knopf „Verschieben“: immer der eigene Modus)
    Mover.Snapshot() → Anzahl gesicherter Teile       Mover.Revert() → Anzahl zurückgesetzter Teile
    Einstellungsseiten: page:MoverButton() unter „Allgemein“, page:MoverResetButton() unter „Erweitert“
    Nachrichten: MOVER_MOVED (key, pos | nil)
                 MOVER_SHOWING (active, owner | nil) – Auswahl erscheint oder verschwindet, im Bearbeitungsmodus
                 wie bei „Verschieben“ (owner = Modul von Mover.Unlock); z. B. für Beispiel-Symbole
]]

Core.Mover = Core.Mover or {}
local Mover = Core.Mover
local L = Core.L

local parts, order = {}, {}
local unlocked, unlockOwner, unlockPage = false, nil, nil
local selected
local pending = {}          -- geschützte Teile, deren Position nach dem Kampf gesetzt wird
local bar

local SNAP = 8              -- Einrasten am Raster: Abstand in Bildpunkten
local MIN_SIZE = 32
local KIT_HIGHLIGHT, KIT_SELECTED = "editmode-actionbar-highlight", "editmode-actionbar-selected"

-- Blizzards Layout der Auswahl (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua, dort lokal).
local SELECTION_LAYOUT = {
    ["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    ["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    ["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    ["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    ["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
    ["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
    ["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
    ["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
    ["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local Positions = Core.Positions   -- eine Stelle für ezCoreDB.positions (Widgets.lua)

local function Resolve(rel)
    if type(rel) == "string" then return rawget(_G, rel) end
    return rel
end

local function Owner(part) return part.owner or Core.name end

local function Try(part, where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Core.Error(Owner(part), err, "Mover " .. where) end
    return ok
end

local function IsProtectedPart(part)
    if part.protected ~= nil then return part.protected end
    local frame = part.frame
    if frame.IsProtected then
        local isProtected = frame:IsProtected()
        return isProtected and true or false
    end
    return false
end

local function Blocked(part)
    return IsProtectedPart(part) and Core.InCombat()
end

function Mover.IsUnlocked() return unlocked end

function Mover.IsShowing()
    return unlocked or Core.EditMode.IsActive()
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------

-- Standardlage setzen. Wirft der eigene Anker (etwa ein Rahmen, der selbst an diesem Teil hängt), geht der Fehler
-- an den Aufrufer – Mover.Register und Mover.Reset melden ihn so dem Modul (ezBars reagiert darauf mit freier Lage);
-- Mover.ResetAll schirmt jedes Teil ab (unten).
local function ApplyDefault(part)
    local a = part.anchor
    local frame = part.frame
    frame:ClearAllPoints()
    frame:SetPoint(a[1] or "CENTER", Resolve(a[2]) or UIParent, a[3] or a[1] or "CENTER", a[4] or 0, a[5] or 0)
end

local UpdateSelection

local function Apply(part)
    if Blocked(part) then
        -- nach dem Kampf nachholen: eine Warteschlange für alles (Core.AfterCombat), je Teil ein Auftrag
        pending[part.key] = true
        local key = part.key
        Core.AfterCombat(function()
            if pending[key] and parts[key] then Apply(parts[key]) end
        end, "ezCore.mover:" .. tostring(key), Core.name)
        return false
    end
    pending[part.key] = nil
    local positions = Positions(false)
    local pos = positions and positions[part.key]
    if type(pos) == "table" and pos.point then
        Core.ApplyPosition(part.frame, pos)
    else
        ApplyDefault(part)
    end
    if part.selection and part.selection:IsShown() then UpdateSelection(part) end
    return true
end

local function Notify(part, pos)
    if part.onMove then Try(part, "onMove", part.onMove, part.frame, pos) end
    Core.Fire("MOVER_MOVED", part.key, pos)
end

local function Save(part, pos)
    local positions = Positions(true)
    if positions then positions[part.key] = pos end
    Apply(part)
    Notify(part, pos)
end

function Mover.Reset(key)
    local part = parts[key]
    if not part then return false end
    local positions = Positions(false)
    if positions then positions[key] = nil end
    Apply(part)
    Notify(part, nil)
    return true
end

function Mover.ResetAll(owner)
    local n = 0
    for _, key in ipairs(order) do
        local part = parts[key]
        if not owner or Owner(part) == owner then
            -- Abgeschirmt (Hinweis aus ezBars, Welle 3): Wirft ein Teil beim Zurücksetzen (sein eigener Anker), steht
            -- der Fehler in der Fehlerliste seines Besitzers, das Teil in der Bildschirmmitte, und „Position
            -- zurücksetzen“ läuft für die übrigen Teile weiter.
            local ok, done = pcall(Mover.Reset, key)
            if not ok then
                Core.Error(Owner(part), done, "Mover.ResetAll " .. tostring(key))
                local frame = part.frame
                if frame and not Blocked(part) then
                    pcall(frame.ClearAllPoints, frame)
                    pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
                end
            elseif done then n = n + 1 end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Einrasten am Raster (nur lesen: Blizzards Schalter und Rasterabstand)
---------------------------------------------------------------------------

local function GridSpacing()
    if not Core.EditMode.IsActive() then return nil end
    local manager = rawget(_G, "EditModeManagerFrame")
    if type(manager) ~= "table" or type(manager.IsSnapEnabled) ~= "function" then return nil end
    local ok, snap = pcall(manager.IsSnapEnabled, manager)
    local grid = manager.Grid
    if not (ok and snap and type(grid) == "table" and grid.IsShown and grid:IsShown()) then return nil end
    local spacing = Core.Num(grid.gridSpacing)
    return spacing and spacing > 0 and spacing or nil
end

-- Verschiebung, die die nächste Kante oder Mitte auf eine Rasterlinie legt (0, wenn keine nah genug ist).
function Mover.SnapOffset(lo, hi, center, spacing)
    local best
    for _, v in ipairs({ lo, (lo + hi) / 2, hi }) do
        local line = center + math.floor((v - center) / spacing + 0.5) * spacing
        local d = line - v
        if math.abs(d) <= SNAP and (not best or math.abs(d) < math.abs(best)) then best = d end
    end
    return best or 0
end

---------------------------------------------------------------------------
-- Auswahl
---------------------------------------------------------------------------

local function ApplyKit(frame, kit)
    if frame.ezKit == kit then return end
    frame.ezKit = kit
    local util = rawget(_G, "NineSliceUtil")
    if type(util) == "table" and type(util.ApplyLayout) == "function" and pcall(util.ApplyLayout, frame, SELECTION_LAYOUT, kit) then
        return
    end
    -- Ohne Blizzards NineSlice: schlichte Fläche in Blizzards Blau bzw. Gelb.
    frame.ezFill = frame.ezFill or frame:CreateTexture(nil, "BACKGROUND")
    frame.ezFill:SetAllPoints()
    if kit == KIT_SELECTED then frame.ezFill:SetColorTexture(1, 0.82, 0, 0.3) else frame.ezFill:SetColorTexture(0.25, 0.55, 1, 0.3) end
end

local function UpdateLabel(part)
    local sel = part.selection
    if not sel then return end
    local show = selected == part or sel.ezHover
    sel.label:SetText(part.label or part.key)
    sel.label:SetShown(show and true or false)
end

UpdateSelection = function(part)
    local sel, frame = part.selection, part.frame
    if not sel then return end
    local ratio = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local w, h = (frame:GetWidth() or 0) * ratio, (frame:GetHeight() or 0) * ratio
    sel:ClearAllPoints()
    if w >= part.minWidth and h >= part.minHeight then
        sel:SetAllPoints(frame)
    else
        sel:SetPoint("CENTER", frame, "CENTER", 0, 0)
        sel:SetSize(math.max(w, part.minWidth), math.max(h, part.minHeight))
    end
    ApplyKit(sel, selected == part and KIT_SELECTED or KIT_HIGHLIGHT)
    UpdateLabel(part)
end

function Mover.Select(key)
    local part = key and parts[key]
    local old = selected
    selected = part
    if old and old ~= part then UpdateSelection(old) end
    if part then UpdateSelection(part) end
end

-- Ziehen: die Auswahl wandert (sie ist auch bei verstecktem Teil sichtbar), das Teil folgt ihr.
local function Follow(part)
    local d = part.drag
    if not d then return end
    local sel, frame = part.selection, part.frame
    local dx, dy = (sel:GetLeft() or d.sx) - d.sx, (sel:GetBottom() or d.sy) - d.sy
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", d.fx + dx * d.ratio, d.fy + dy * d.ratio)
end

local function StartDrag(part)
    if Blocked(part) then
        Core.CombatNotice(Core.name, L.MOVER_WHAT:format(part.label or part.key))
        return
    end
    local sel, frame = part.selection, part.frame
    local fx, fy, sx, sy = frame:GetLeft(), frame:GetBottom(), sel:GetLeft(), sel:GetBottom()
    if not (fx and fy and sx and sy) then return end
    Mover.Select(part.key)
    part.drag = { fx = fx, fy = fy, sx = sx, sy = sy,
        ratio = (UIParent:GetEffectiveScale() or 1) / (frame:GetEffectiveScale() or 1) }
    local w, h = sel:GetWidth(), sel:GetHeight()
    sel:ClearAllPoints()
    sel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sx, sy)
    sel:SetSize(w, h)
    sel:StartMoving()
    sel:SetScript("OnUpdate", function()
        if Blocked(part) then return end   -- Kampf hat begonnen: geschütztes Teil bleibt stehen
        Follow(part)
    end)
end

local function StopDrag(part)
    local d = part.drag
    if not d then return end
    local sel = part.selection
    sel:StopMovingOrSizing()
    sel:SetScript("OnUpdate", nil)
    local spacing = GridSpacing()
    if spacing then
        local cx, cy = UIParent:GetCenter()
        local left, right, bottom, top = sel:GetLeft(), sel:GetRight(), sel:GetBottom(), sel:GetTop()
        if left and cx then
            local dx = Mover.SnapOffset(left, right, cx, spacing)
            local dy = Mover.SnapOffset(bottom, top, cy, spacing)
            sel:ClearAllPoints()
            sel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
        end
    end
    if Blocked(part) then
        part.drag = nil
        UpdateSelection(part)
        Core.CombatNotice(Core.name, L.MOVER_WHAT:format(part.label or part.key))
        return
    end
    Follow(part)
    part.drag = nil
    local pos = Core.QuadrantPos(part.frame)
    if pos then Save(part, pos) else Apply(part) end
end

local function ShowMenu(part, sel)
    local menu = rawget(_G, "MenuUtil")
    if type(menu) == "table" and type(menu.CreateContextMenu) == "function" then
        local ok = pcall(menu.CreateContextMenu, sel, function(_, root)
            root:CreateTitle(part.label or part.key)
            root:CreateButton(L.MOVER_RESET_ONE, function() Mover.Reset(part.key) end)
        end)
        if ok then return end
    end
    Core.Confirm(L.MOVER_RESET_ONE_CONFIRM:format(part.label or part.key), function() Mover.Reset(part.key) end)
end

local function CreateSelection(part)
    local ok, sel = pcall(CreateFrame, "Frame", nil, UIParent, "NineSliceCodeTemplate")
    if not (ok and sel) then sel = CreateFrame("Frame", nil, UIParent) end
    sel:SetFrameStrata("HIGH")
    sel:SetToplevel(true)
    sel:EnableMouse(true)
    sel:SetMovable(true)
    sel:SetClampedToScreen(true)
    sel:RegisterForDrag("LeftButton")
    sel:Hide()
    sel.label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    sel.label:SetAllPoints()
    sel.label:Hide()
    sel:SetScript("OnDragStart", function() Try(part, "drag", StartDrag, part) end)
    sel:SetScript("OnDragStop", function() Try(part, "drop", StopDrag, part) end)
    sel:SetScript("OnMouseDown", function(self, button)
        Mover.Select(part.key)
        if button == "RightButton" then Try(part, "menu", ShowMenu, part, self) end
    end)
    sel:SetScript("OnEnter", function(self)
        self.ezHover = true
        UpdateLabel(part)
        Core.ShowTip(self, part.label or part.key, L.MOVER_TIP, "ANCHOR_CURSOR")
    end)
    sel:SetScript("OnLeave", function(self)
        self.ezHover = false
        UpdateLabel(part)
        GameTooltip:Hide()
    end)
    part.selection = sel
    return sel
end

---------------------------------------------------------------------------
-- Leiste „Fertig“ (Unlock ohne Blizzards Bearbeitungsmodus)
---------------------------------------------------------------------------

local function CreateBar()
    local ok, f = pcall(CreateFrame, "Frame", "ezCoreMoverBar", UIParent, "TooltipBackdropTemplate")
    if not (ok and f) then f = CreateFrame("Frame", "ezCoreMoverBar", UIParent) end
    f:SetFrameStrata("DIALOG")
    f:SetSize(340, 74)
    f:SetPoint("TOP", UIParent, "TOP", 0, -110)
    f:EnableMouse(true)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOPLEFT", 12, -12)
    f.text:SetPoint("TOPRIGHT", -12, -12)
    f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.done:SetSize(110, 22)
    f.done:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
    f.done:SetText(L.MOVER_DONE)
    f.done:SetScript("OnClick", function() Mover.Lock() end)
    f.done:SetScript("OnEnter", Core.TipScript(L.MOVER_DONE, L.MOVER_DONE_TIP))
    f.done:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reset:SetSize(110, 22)
    f.reset:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
    f.reset:SetText(L.MOVER_RESET_BUTTON)
    f.reset:SetScript("OnClick", function()
        local owner = unlockOwner
        Core.Confirm(L.MOVER_RESET_CONFIRM:format(owner or Core.TITLE), function()
            Core.Print(Core.name, L.MOVER_RESET_DONE:format(Mover.ResetAll(owner)))
        end)
    end)
    f.reset:SetScript("OnEnter", function(self)
        Core.ShowTip(self, L.MOVER_RESET_BUTTON, L.MOVER_RESET_TIP:format(unlockOwner or Core.TITLE))
    end)
    f.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

local function UpdateBar()
    if not unlocked then
        if bar then bar:Hide() end
        return
    end
    bar = bar or CreateBar()
    -- EC-12: der Weg zu Blizzards Bearbeitungsmodus steht dabei (ein Modus für alles; dort erscheinen dieselben Rahmen)
    bar.text:SetText(L.MOVER_BAR:format(unlockOwner or Core.TITLE) .. "\n" .. L.MOVER_BAR_EDITMODE:format(Core.ARROW or "»"))
    bar:Show()
end

---------------------------------------------------------------------------
-- Bearbeitungsmodus: Hinweis „sofort gemerkt“, Stand beim Betreten, Verwerfen (EC-10)
---------------------------------------------------------------------------

local snapshot   -- { [key] = Kopie der Lage | false (Standardplatz) } beim Betreten
local hint, hookedRevert

local function Copy(pos)
    if type(pos) ~= "table" then return false end
    local out = {}
    for k, v in pairs(pos) do out[k] = v end
    return out
end

local function Same(a, b)
    if a == false or b == false or a == nil or b == nil then return (a or false) == (b or false) end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- Lage aller angemeldeten Teile sichern (beim Betreten des Bearbeitungsmodus). → Anzahl
function Mover.Snapshot()
    snapshot = {}
    local positions = Positions(false)
    local n = 0
    for _, key in ipairs(order) do
        snapshot[key] = Copy(positions and positions[key])
        n = n + 1
    end
    return n
end

-- Alle Teile auf den gesicherten Stand zurück; nur, was sich seitdem geändert hat. Geschützte Teile im Kampf holt
-- Apply nach dem Kampf nach. → Anzahl zurückgesetzter Teile
function Mover.Revert()
    if not snapshot then return 0 end
    local n = 0
    for key, old in pairs(snapshot) do
        local part = parts[key]
        local positions = Positions(old ~= false)
        local now = positions and positions[key]
        if part and not Same(Copy(now), old) then
            if positions then positions[key] = old ~= false and Copy(old) or nil end
            local ok, err = pcall(Apply, part)
            if not ok then Core.Error(Owner(part), err, "Mover.Revert " .. tostring(key)) end
            Notify(part, old ~= false and old or nil)
            n = n + 1
        end
    end
    return n
end

local function RevertAndTell()
    local n = Mover.Revert()
    if n > 0 then Core.Print(Core.name, L.MOVER_REVERTED:format(n)) end
    return n
end

-- Blizzards Knopf „Alle Änderungen verwerfen“: nur HookScript, Blizzards Ablauf bleibt unberührt. Er ist nur
-- anklickbar, wenn Blizzard selbst etwas zu verwerfen hat – darum gibt es den eigenen Knopf am Hinweis.
local function HookRevert()
    local manager = rawget(_G, "EditModeManagerFrame")
    local button = type(manager) == "table" and rawget(manager, "RevertAllChangesButton")
    if hookedRevert or type(button) ~= "table" or type(button.HookScript) ~= "function" then return end
    hookedRevert = button
    button:HookScript("OnClick", function() Core.Try(Core.name, "Mover.Revert", RevertAndTell) end)
end
Mover.HookRevert = HookRevert

local function CreateHint()
    local ok, f = pcall(CreateFrame, "Frame", "ezCoreEditModeHint", UIParent, "TooltipBackdropTemplate")
    if not (ok and f) then f = CreateFrame("Frame", "ezCoreEditModeHint", UIParent) end
    f:SetFrameStrata("DIALOG")
    f:SetSize(380, 80)   -- drei bis vier Zeilen Text und der Knopf
    f:EnableMouse(true)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 10, -9)
    f.text:SetPoint("TOPRIGHT", -10, -9)
    f.text:SetText(L.MOVER_EDITMODE_HINT)
    f.revert = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.revert:SetSize(150, 20)
    f.revert:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    f.revert:SetText(L.MOVER_REVERT_BUTTON)
    f.revert:SetScript("OnClick", function() if RevertAndTell() == 0 then Core.Print(Core.name, L.MOVER_REVERT_NONE) end end)
    f.revert:SetScript("OnEnter", Core.TipScript(L.MOVER_REVERT_BUTTON, L.MOVER_REVERT_TIP))
    f.revert:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

-- Hinweis unter Blizzards Fenster (eigener Rahmen unter UIParent, nur angedockt: EditModeManagerFrame ist ein
-- ResizeLayoutFrame – ein Kind würde seine Größe ändern).
local function UpdateHint(active)
    if not active then
        if hint then hint:Hide() end
        return
    end
    local any = false
    for _, key in ipairs(order) do if parts[key].enabled then any = true break end end
    if not any then return end
    hint = hint or CreateHint()
    local manager = rawget(_G, "EditModeManagerFrame")
    hint:ClearAllPoints()
    if type(manager) == "table" and manager.IsShown and manager:IsShown() then
        hint:SetPoint("TOP", manager, "BOTTOM", 0, -4)
    else
        hint:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
    hint:Show()
end
Mover.HintFrame = function() return hint end   -- für Tests

local function OnEditMode(active)
    if active then
        Mover.Snapshot()
        HookRevert()
        if unlocked then Mover.Lock(false) end   -- ein Modus: der eigene endet, Blizzards übernimmt
    end
    UpdateHint(active)
end

---------------------------------------------------------------------------
-- Zeigen und Verbergen
---------------------------------------------------------------------------

local lastShown = false

local function Refresh()
    local show = Mover.IsShowing() and true or false
    for _, key in ipairs(order) do
        local part = parts[key]
        if show and part.enabled then
            local sel = part.selection or CreateSelection(part)
            UpdateSelection(part)
            sel:Show()
        elseif part.selection then
            if part.drag then Try(part, "drop", StopDrag, part) end
            part.selection:Hide()
            part.selection.ezHover = false
        end
    end
    if not show then selected = nil end
    UpdateBar()
    if show ~= lastShown then
        lastShown = show
        Core.Fire("MOVER_SHOWING", show, unlocked and unlockOwner or nil)
    end
end
Mover.Refresh = Refresh

local reopenSettings = false

function Mover.Unlock(owner, page)
    unlocked, unlockOwner, unlockPage = true, owner, page
    -- Blizzards Einstellungen verdecken die Teile: schließen, „Fertig“ öffnet die Seite wieder. EC-11 (Spieltest:
    -- „Einstellungen bleiben offen“): auch ohne Seite (ezMacro ruft Unlock("ezBars")) – dann öffnet „Fertig“ die
    -- Übersicht „ezCollection“.
    local panel = rawget(_G, "SettingsPanel")
    reopenSettings = false
    -- im Kampf nicht anfassen (ST-04, EC-64): Blizzards Einstellungsfenster bleibt dann, wie es ist
    if not Core.InCombat() and type(panel) == "table" and panel.IsShown and panel:IsShown() and HideUIPanel then
        reopenSettings = pcall(HideUIPanel, panel) and not page
    end
    Refresh()
    local first
    for _, key in ipairs(order) do
        local part = parts[key]
        if part.enabled and (not owner or Owner(part) == owner) then first = first or key end
    end
    if first then Mover.Select(first) elseif owner then Core.Print(Core.name, L.MOVER_NONE:format(owner)) end
end

-- reopen = false: die Einstellungsseite bleibt zu (Kampfbeginn – InCombatLockdown ist im Ereignis noch false).
function Mover.Lock(reopen)
    if not unlocked then return end
    local page, again = unlockPage, reopenSettings
    unlocked, unlockOwner, unlockPage, reopenSettings = false, nil, nil, false
    Refresh()
    if reopen == false or Core.InCombat() then return end
    if page and page.Open then
        Core.Try(nil, "Mover.Lock Open", page.Open, page)
    elseif again and Core.OpenSettings then
        Core.Try(nil, "Mover.Lock OpenSettings", Core.OpenSettings)
    end
end

-- Knopf „Verschieben“ (page:MoverButton, /ezbars verschieben): immer der eigene Modus mit Leiste „Fertig“. Der Weg zu
-- Blizzards Bearbeitungsmodus steht auf der Leiste (Esc » Bearbeitungsmodus); geöffnet wird er nur über Blizzards Menü.
-- Bis zum 22.11.2026 öffnete der Testschalter comfort.editModeOpen ihn hier mit ShowUIPanel – entfernt auf Wunsch des
-- Nutzers (ROADMAP-Index, 22.11.2026). → "unlock" (Rückgabe bleibt für Aufrufer wie ezBars' ns.OpenMover)
function Mover.Open(owner, page)
    Mover.Unlock(owner, page)
    return "unlock"
end

-- Gespeicherten Wert des gestrichenen Testschalters einmal entfernen (nur ezCores eigene Tabelle; nichts liest ihn mehr).
local function ForgetEditModeOpen()
    local c = Core.OwnSettings and Core.OwnSettings("comfort")
    if type(c) == "table" and c.editModeOpen ~= nil then c.editModeOpen = nil end
end
Mover.ForgetEditModeOpen = ForgetEditModeOpen   -- für Tests

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

local Part = {}
Part.__index = Part
function Part:Apply() return Apply(self) end
function Part:Reset() return Mover.Reset(self.key) end
function Part:Position()
    local positions = Positions(false)
    return positions and positions[self.key] or nil
end
function Part:SetEnabled(enabled)
    self.enabled = enabled ~= false
    if Mover.IsShowing() then Refresh() end
end
function Part:SetLabel(text)
    self.label = text
    UpdateLabel(self)
end

function Mover.Register(frame, opts)
    opts = opts or {}
    local key = opts.key
    assert(type(frame) == "table" and type(key) == "string" and key ~= "", "Mover.Register(frame, { key = … })")
    local part = parts[key]
    if not part then
        part = setmetatable({ key = key }, Part)
        parts[key] = part
        order[#order + 1] = key
    end
    part.frame = frame
    part.label = opts.label or part.label or key
    part.owner = opts.owner or part.owner
    part.anchor = type(opts.anchor) == "table" and opts.anchor or { "CENTER", "UIParent", "CENTER", 0, 0 }
    part.onMove = opts.onMove
    part.protected = opts.protected
    part.minWidth = opts.minWidth or MIN_SIZE
    part.minHeight = opts.minHeight or MIN_SIZE
    part.enabled = opts.enabled ~= false
    -- alte Position aus dem Modul einmal übernehmen
    -- (V-021: eine Stelle – Core.ImportPosition prüft Typen und rechnet x/y in Zahlen um)
    if type(opts.import) == "table" then Core.ImportPosition(key, opts.import) end
    -- Größe ändert sich (ezBars: Spalten und Reihen): Auswahl nachziehen
    if not part.sizeHooked and frame.HookScript then
        part.sizeHooked = true
        frame:HookScript("OnSizeChanged", function() if part.selection and part.selection:IsShown() then UpdateSelection(part) end end)
    end
    Apply(part)
    if Mover.IsShowing() then Refresh() end
    return part
end

function Mover.Get(key) return parts[key] end

function Mover.Parts(owner)
    local list = {}
    for _, key in ipairs(order) do
        local part = parts[key]
        if not owner or Owner(part) == owner then list[#list + 1] = part end
    end
    return list
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

Core.EditMode.OnChange(function(active)
    OnEditMode(active)
    Refresh()
    -- EC-11: Rahmen eines Teils, dessen Größe erst nach dem Betreten feststeht (Leiste baut sich auf), ein Bild später
    -- nachziehen
    if active and C_Timer and C_Timer.After then C_Timer.After(0, function() if Mover.IsShowing() then Refresh() end end) end
end, Core.name)

ns.On("PLAYER_LOGIN", function()
    for _, key in ipairs(order) do Apply(parts[key]) end   -- Anker an Blizzards Fenstern und ezCoreDB sind jetzt da
    HookRevert()
    ForgetEditModeOpen()
end)

ns.On("PLAYER_REGEN_DISABLED", function()
    if unlocked then Mover.Lock(false) end
end)

-- Wartende Lagen (pending) setzt Core.AfterCombat nach dem Kampf – kein eigener Zuhörer auf PLAYER_REGEN_ENABLED mehr.

