local _, ns = ...

--[[
    Platz oben für die Leiste („Platz oben für die Leiste“, Entscheidung des Nutzers 13.11.2026, Leitlinie 4
    gestrichen): Blizzards Fenster am oberen Bildschirmrand – Minikarte, Buffs und Debuffs, Spieler- und
    Zielfenster in Blizzards klassischer Anordnung, Questverfolgung, Zonen-Anzeige oben in der Mitte … –
    rücken um die Höhe der Leiste (mal ihrer Skalierung) plus etwas Luft nach unten, nach Blizzards Forever-Quelle
    (Blizzard_EditMode/Shared):

      • Fenster des Bearbeitungsmodus verankert Blizzard in EditModeSystemMixin:ApplySystemAnchor nach
        systemInfo.anchorInfo (bzw. anchorInfo2). ezPanel hängt sich mit hooksecurefunc hinter
        ApplySystemAnchor und setzt danach nur den y-Versatz neu – mit frame:SetPointBase, Blizzards
        ursprünglichem SetPoint. Der überschriebene SetPoint des Bearbeitungsmodus (SetPointOverride)
        schreibt in Blizzards Tabellen (snappedToFrame, editModeSystemAnchorDirty) und bleibt unberührt.
      • Nur Fenster in Blizzards Standardlage (IsInDefaultPosition), oben an UIParent verankert (TOP,
        TOPLEFT, TOPRIGHT) und nicht in einem verwalteten Container (unten/rechts). Wer ein Fenster im
        Bearbeitungsmodus selbst verschoben hat, behält es dort. Steht ein Fenster nicht mehr dort, wo
        Blizzard (bzw. ezPanel) es hingestellt hat – etwa weil ein anderes Addon es bewegt –, bleibt es
        ebenfalls unberührt.
      • Fenster ohne Bearbeitungsmodus (EXTRA): ihr erster Anker wird beim ersten Mal gemerkt und um den
        Versatz verschoben; setzt Blizzard ihn neu (hooksecurefunc auf SetPoint), gilt der neue als Ausgang.
      • Nie im Kampf: vorgemerkt über ns.AfterCombat (ezCores Reihe nach dem Kampf). Keine Werte in
        Blizzards Tabellen.
      • Aus (Schalter reserveTop), Leiste aus oder automatisch ausgeblendet: Blizzards Lage sofort zurück.
        Die Höhe folgt Schriftgröße und Skalierung der Leiste.
]]

local GAP = 2   -- Luft zwischen Leiste und Blizzards Fenstern
-- Oben verankerte Fenster außerhalb des Bearbeitungsmodus (Forever: Blizzard_UIWidgetTopCenterFrame.xml, TOP 0/-15).
local EXTRA = { "UIWidgetTopCenterContainerFrame" }

local moved = setmetatable({}, { __mode = "k" })    -- Fenster → Versatz, den ezPanel gesetzt hat
local hooked = setmetatable({}, { __mode = "k" })
local plainBase = setmetatable({}, { __mode = "k" }) -- Fenster ohne Bearbeitungsmodus → { point, rel, relPoint, x, y }
local pending = false
local placing = false

-- Im Kampf nichts verschieben: nach dem Kampf nachholen (ezCores Reihe, ein Aufruf für viele Anlässe).
local function Later()
    pending = true
    ns.AfterCombat(function() ns.ApplyTopSpace() end, "topSpace")
end

local TOP = { TOP = true, TOPLEFT = true, TOPRIGHT = true }

local function IsUIParent(rel)
    return rel == nil or rel == UIParent or rel == "UIParent"
end

local function Resolve(rel)
    if type(rel) == "string" then return _G[rel] end
    return rel
end

-- Versatz in Einheiten von UIParent (0 = kein Platz).
function ns.TopReserve()
    local S = ns.S
    if not (S and S.reserveTop) or not ns.bar or not ns.ReservedHeight then return 0 end
    local height = ns.ReservedHeight(UIParent)
    if height <= 0 then return 0 end
    return height + GAP
end

---------------------------------------------------------------------------
-- Fenster des Bearbeitungsmodus
---------------------------------------------------------------------------

-- Blizzards Anker eines Systems in Standardlage oben an UIParent, sonst nil (nur lesen).
local function DefaultTopAnchors(frame)
    local info = frame.systemInfo
    if type(info) ~= "table" or type(info.anchorInfo) ~= "table" then return nil end
    if type(frame.SetPointBase) ~= "function" or type(frame.IsInDefaultPosition) ~= "function" then return nil end
    local ok, default = pcall(frame.IsInDefaultPosition, frame)
    if not (ok and default) then return nil end
    if frame.isManagedFrame then return nil end   -- liegt in Blizzards Container (unten oder rechts)
    local list = {}
    for _, a in ipairs({ info.anchorInfo, info.anchorInfo2 }) do
        if type(a) == "table" then
            if not (IsUIParent(a.relativeTo) and TOP[a.relativePoint]) then return nil end
            list[#list + 1] = a
        end
    end
    return #list > 0 and list or nil
end

-- Leitlinie 6 (Gesamtreview 18.11.2026, T3-3): GetPoint-Rückgaben zuerst auf gesperrte Werte prüfen; ein gesperrter
-- Wert gilt als „nicht an Blizzards Platz“, das Fenster bleibt unangetastet. Near rechnet nur mit Core.Num.
local function Near(a, b)
    a, b = ezCore.Num(a), ezCore.Num(b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 0.5
end
ns.TopSpaceNear = Near   -- für die Prüfungen

-- Steht das Fenster dort, wo Blizzard es (mit dem bisherigen Versatz von ezPanel) hingestellt hat?
local function InExpectedPlace(frame, anchors, scale, offset)
    for _, a in ipairs(anchors) do
        local found = false
        for i = 1, frame:GetNumPoints() do
            local point, rel, relPoint, x, y = frame:GetPoint(i)
            if not ezCore.Usable(point, rel, relPoint, x, y) then return false end
            if point == a.point then
                found = Resolve(rel) == Resolve(a.relativeTo or UIParent) and relPoint == a.relativePoint
                    and Near(x, a.offsetX / scale) and Near(y, (a.offsetY - offset) / scale)
                break
            end
        end
        if not found then return false end
    end
    return true
end

local function PlaceSystem(frame, dy)
    local anchors = DefaultTopAnchors(frame)
    if not anchors then
        moved[frame] = nil   -- vom Nutzer verschoben oder nicht oben: nicht anfassen
        return false
    end
    local before = moved[frame] or 0
    if dy == before then return false end
    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end
    if not InExpectedPlace(frame, anchors, scale, before) then
        moved[frame] = nil   -- jemand anderes hat es bewegt
        return false
    end
    placing = true
    for _, a in ipairs(anchors) do
        frame:SetPointBase(a.point, a.relativeTo, a.relativePoint, a.offsetX / scale, (a.offsetY - dy) / scale)
    end
    placing = false
    moved[frame] = dy > 0 and dy or nil
    return true
end

local function Systems()
    local manager = rawget(_G, "EditModeManagerFrame")
    local list = manager and manager.registeredSystemFrames
    return type(list) == "table" and list or {}
end

---------------------------------------------------------------------------
-- Fenster ohne Bearbeitungsmodus
---------------------------------------------------------------------------

local function PlacePlain(frame, dy)
    local base = plainBase[frame]
    if not base then
        if dy <= 0 then return false end
        local point, rel, relPoint, x, y = frame:GetPoint(1)
        if not ezCore.Usable(point, rel, relPoint, x, y) then return false end   -- T3-3: gesperrt, nicht anfassen
        if not point or not IsUIParent(rel) or not TOP[relPoint or point] then return false end
        base = { point, rel, relPoint or point, x or 0, y or 0 }
        plainBase[frame] = base
    end
    local before = moved[frame] or 0
    if dy == before then return false end
    placing = true
    frame:SetPoint(base[1], base[2], base[3], base[4], base[5] - dy)
    placing = false
    moved[frame] = dy > 0 and dy or nil
    return true
end

---------------------------------------------------------------------------
-- Haken und Auffrischen
---------------------------------------------------------------------------

local function HookAll()
    for _, frame in ipairs(Systems()) do
        if type(frame) == "table" and not hooked[frame] and type(frame.ApplySystemAnchor) == "function" then
            hooked[frame] = true
            -- Blizzard hat neu verankert (Login, Layout-Wechsel, „Standardlage“): wieder Blizzards Lage,
            -- ezPanels Versatz kommt danach dazu.
            hooksecurefunc(frame, "ApplySystemAnchor", function(self)
                moved[self] = nil
                if ns.InCombat() then return Later() end
                PlaceSystem(self, ns.TopReserve())
            end)
        end
    end
    for _, name in ipairs(EXTRA) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and not hooked[frame] and type(frame.SetPoint) == "function" then
            hooked[frame] = true
            hooksecurefunc(frame, "SetPoint", function(self, point, rel, relPoint, x, y)
                if placing then return end
                if not ezCore.Usable(point, rel, relPoint, x, y) then   -- T3-3: gesperrter Anker, kein Ausgang
                    plainBase[self], moved[self] = nil, nil
                    return
                end
                -- Blizzard setzt einen neuen Anker: der gilt als Ausgang.
                if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
                plainBase[self] = IsUIParent(rel) and TOP[relPoint or point]
                    and { point, rel, relPoint or point, x or 0, y or 0 } or nil
                moved[self] = nil
                if plainBase[self] then
                    if ns.InCombat() then return Later() end
                    PlacePlain(self, ns.TopReserve())
                end
            end)
        end
    end
end

-- Alle Fenster an den aktuellen Versatz anpassen (oder zurückstellen). → Anzahl geänderter Fenster
function ns.ApplyTopSpace()
    if ns.InCombat() then
        Later()
        return 0
    end
    pending = false
    HookAll()
    local dy = ns.TopReserve()
    local count = 0
    for _, frame in ipairs(Systems()) do
        if type(frame) == "table" and PlaceSystem(frame, dy) then count = count + 1 end
    end
    for _, name in ipairs(EXTRA) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and PlacePlain(frame, dy) then count = count + 1 end
    end
    return count
end

-- Versatz, den ezPanel gerade an einem Fenster gesetzt hat (0 = keiner). Für die Tests.
function ns.TopSpaceOffset(frame)
    return moved[frame] or 0
end

-- Anzahl der Fenster, die ezPanel gerade nach unten gerückt hat, und ob noch ein Nachholen nach dem Kampf
-- aussteht. Für die Statuszeile (/ep status, Einstellungen → Erweitert → „Status“).
function ns.TopSpaceCount()
    local count = 0
    for _, frame in ipairs(Systems()) do
        if type(frame) == "table" and moved[frame] then count = count + 1 end
    end
    for _, name in ipairs(EXTRA) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and moved[frame] then count = count + 1 end
    end
    return count, pending
end

ns.OnReady(function() ns.ApplyTopSpace() end)
ns.On("PLAYER_ENTERING_WORLD", function() if ns.ready then ns.ApplyTopSpace() end end)
-- Nach dem Kampf: ns.AfterCombat (Later) statt eines eigenen Zuhörers auf PLAYER_REGEN_ENABLED.
-- Später geladene Blizzard-Teile melden weitere Systeme an.
ns.On("ADDON_LOADED", function() if ns.ready then HookAll() end end)
-- Nach dem Bearbeitungsmodus: neu verankerte Fenster wieder einrücken.
ezCore.EditMode.OnChange(function(active)
    if not active and ns.ready then ns.ApplyTopSpace() end
end, "ezPanel")
