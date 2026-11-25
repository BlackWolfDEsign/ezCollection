local _, ns = ...
local L = ns.L

--[[
    Ordnet die Plätze der originalen kombinierten Blizzard-Tasche
    (ContainerFrameCombinedBags) im Fließ-Layout (Render.lua) an.

    Es wird nichts ersetzt: Rahmen, Hintergrund, Plätze, Suche, Geld, Sortierknopf
    und Taschenleiste bleiben Blizzards eigene. Wir hängen uns nur mit
    hooksecurefunc hinter Blizzards Layout und verschieben die Plätze.
    Dabei schreiben wir nie Werte in Blizzards Tabellen, damit kein
    "Taint" entsteht und das Benutzen von Gegenständen nie blockiert wird.

    Dazu: Tasche verschieben (Titelleiste ziehen), Breite ändern (Griff unten
    in der Ecke, ändert die Spaltenzahl) und an Bank/Gildenbank andocken.
]]

local Layout = {}
ns.Layout = Layout

local CHECK_INTERVAL = 0.2    -- wie oft eine aufgeschobene Neuordnung geprüft wird
local MIN_COLS, MAX_COLS = 6, 24
local DOCK_GAP = 2
local SEARCH_X, SEARCH_Y = 60, 25   -- Suchfeld direkt unter der Titelleiste (Blizzard: 62, 37)
local AREA_TOP = SEARCH_Y + 20 + 2  -- erste Gruppe gleich unter dem Suchfeld
local TOP_TRIM = 28                 -- Ersatz, solange die Tasche noch keine Position hat

local bagFrame, holder, view, toolbar
local rholder, rview          -- Abschnitt Reagenzientasche (Reagent.lua): Fläche im Reagenzien-Fenster, eigene Ansicht
local sectionFrame            -- Blizzards Reagenzien-Fenster, dessen Plätze ezBag zuletzt im Abschnitt angeordnet hat
local installed = false
local hiddenByUs = setmetatable({}, { __mode = "k" })
local overlays = setmetatable({}, { __mode = "k" })
local clickHooked = setmetatable({}, { __mode = "k" })
local baseHeight              -- Höhe, die Blizzard der Tasche zuletzt gegeben hat
local dirty = false
local applying = false
local lastSignature
local geo = { w = 37, sp = 5, pad = 15, blizzCols = 10 }

---------------------------------------------------------------------------
-- Kleine Helfer
---------------------------------------------------------------------------

ns.QualityColor = ezCore.QualityRGB     -- Farbe der Qualität aus ezCore

local function IsExtended(button)
    return button.IsExtended and button:IsExtended() == true
end

-- Versteckte Plätze (eingeklappt / zusammengefasst) kommen aus dem Bild:
-- unsichtbar, nicht anklickbar und weit außerhalb, damit auch Hintergründe,
-- die am Platz hängen, nirgends durchscheinen.
local function Conceal(button, anchor)
    hiddenByUs[button] = true
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4000, 4000)
    button:SetAlpha(0)
    button:EnableMouse(false)
end
ns.ConcealButton = Conceal

local function Reveal(button)
    if not hiddenByUs[button] then return end
    hiddenByUs[button] = nil
    button:SetAlpha(1)
    -- Gesperrte Erweiterungsplätze hat Blizzard selbst stumm geschaltet.
    button:EnableMouse(not IsExtended(button))
end
ns.RevealButton = Reveal

function ns.SellValue(info)
    if not info or info.hasNoValue then return 0 end
    return (ezCore.VendorPrice(info.hyperlink or info.itemID) or 0) * (info.stackCount or 1)
end

---------------------------------------------------------------------------
-- Overlays auf den Plätzen: Anzahl freier Plätze und Gesamtzahl zusammengefasster Stapel.
-- Itemlevel und „BoE“ zeichnet ezCore.SlotText (eine Fassung für alle Module).
---------------------------------------------------------------------------

local function Overlay(button)
    local o = overlays[button]
    if o then return o end
    o = {}
    o.free = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    o.free:SetDrawLayer("OVERLAY", 7)
    o.free:SetPoint("BOTTOMRIGHT", -3, 3)
    -- Gesamtzahl zusammengefasster Stapel, an der Stelle von Blizzards Anzahl.
    o.stack = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    o.stack:SetDrawLayer("OVERLAY", 7)
    o.stack:SetPoint("BOTTOMRIGHT", -5, 2)
    o.stack:SetJustifyH("RIGHT")
    overlays[button] = o
    return o
end
ns.ItemOverlay = Overlay

-- Itemlevel/BoE und Marken für einen Knopf setzen (Tasche, Bank, Gildenbank, ezBag-Fenster).
-- bound: true/false aus dem Platz, nil = unbekannt (dann kein „BoE“, z. B. offline oder Gildenbank).
function ns.SetItemMarks(button, itemID, link, quality, bound, bag, slot)
    local marks
    itemID = ns.PlainID(itemID)
    -- Itemlevel und „BoE“: gemeinsame Schalter mit ezLoot (ezCore, ns.SHARED in Core.lua)
    local showLevel, showBoe = ns.Enabled("itemLevel"), ns.Enabled("boe")
    if itemID and (showLevel or showBoe) then
        marks = ezCore.SlotText.Marks(link or itemID, {
            itemLevel = showLevel == true,
            bind = showBoe == true and bound ~= nil,
            bound = bound, bag = bag, slot = slot,
        })
    end
    -- Marken oben links (Quest, „nie verkaufen“, Marken anderer Module) – Marks.lua
    if ns.Marks then ns.Marks.Apply(button, itemID, link, quality, bag, slot) end
    -- Funkeln an Quest-Gegenständen (von ezQuest, unter den Marken) – QuestShine.lua
    if ns.QuestShine then ns.QuestShine(button, itemID, link, bag, slot) end
    ezCore.SlotText.Apply(button, marks)
end

function ns.SetFreeCount(button, count)
    local o = overlays[button]
    if not count and not o then return end
    o = o or Overlay(button)
    o.free:SetText(count or "")
end

-- Stapelzahl kurz für die kleinen Knöpfe: ab 10 000 ganze Tausender („12k“), ab 1000 mit einer Nachkommastelle über
-- ezCores Core.ShortNumber (Dezimalzeichen der Spielsprache, deutsch „1,5k“ – Gesamtreview 18.11.2026, T16-2; vorher
-- „1.5k“ mit Punkt), darunter die Zahl.
local function ShortCount(n)
    if n >= 10000 then return math.floor(n / 1000) .. "k" end
    if n >= 1000 then return ezCore.ShortNumber(n, 1000) end
    return tostring(n)
end

-- Zusammengefasste Stapel (Render.Compact): eigene Gesamtzahl, Blizzards Anzahl nur unsichtbar
-- (Alpha), damit nichts in Blizzards Feldern geändert wird.
function ns.SetStackTotal(button, total)
    local o = overlays[button]
    if not total and not o then return end
    o = o or Overlay(button)
    o.stack:SetText(total and ShortCount(total) or "")
    local name = button.GetName and button:GetName()
    local blizz = button.Count or (name and _G[name .. "Count"])
    if type(blizz) == "table" and blizz.SetAlpha then blizz:SetAlpha(total and 0 or 1) end
end

local function UpdateOverlay(button)
    local bag, slot = button:GetBagID(), button:GetID()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = ns.ItemIDOf(info)
    if itemID then
        ns.SetItemMarks(button, itemID, info.hyperlink, info.quality, info.isBound == true, bag, slot)
    else
        ns.SetItemMarks(button)
    end
end

local function UpdateOverlays(frame)
    if not frame.Items then return end
    for _, button in frame:EnumerateValidItems() do
        if button then UpdateOverlay(button) end
    end
end

---------------------------------------------------------------------------
-- Alt+Rechtsklick auf einen Platz → Gruppen-Menü
---------------------------------------------------------------------------

local function OnItemClick(button, mouse)
    if mouse == "RightButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        ns.Groups.OpenItemMenu(button)
        return
    end
    -- Rechtsklick auf zusammengefasste Stapel: die übrigen Stapel folgen Blizzards einem; Umschalt+Klick (Blizzards
    -- Teilen-Taste, links wie rechts): ezBags Anzahl-Feld, „Okay“ gibt die Anzahl ins offene Fenster oder an den Mauszeiger (Stacks.lua)
    ns.Stacks.OnItemClick(ns.Render.ViewOf(button) or view, button, mouse)
end

-- v: Ansicht des Knopfs (ohne Angabe die Tasche; der Abschnitt Reagenzientasche hat eine eigene)
local function HookButton(button, v)
    ns.Render.HookHover(button, v or view)
    if clickHooked[button] then return end
    clickHooked[button] = true
    button:HookScript("OnClick", OnItemClick)
end

---------------------------------------------------------------------------
-- Geometrie der Originaltasche
---------------------------------------------------------------------------

local function Call(frame, method)
    local fn = frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if ok then return value end
end

local function Geometry(frame, firstButton)
    local blizzCols = Call(frame, "GetColumns")
    if type(blizzCols) ~= "number" or blizzCols < 1 then blizzCols = 10 end

    local w, h = firstButton:GetSize()
    if not w or w <= 0 then w, h = 37, 37 end

    -- Abstand und Rand so wie Blizzard sie für die Breite verwendet.
    local sp, pad = 5, 15
    local total, padding = Call(frame, "CalculateWidth"), Call(frame, "GetPaddingWidth")
    if type(total) == "number" and type(padding) == "number" and blizzCols > 1 then
        local value = (total - padding - blizzCols * w) / (blizzCols - 1)
        if value >= 0 and value <= 20 then sp, pad = value, padding end
    end

    -- Derselbe Ankerpunkt wie bei Blizzard: unten rechts über dem Geldfeld.
    local rel, relPoint, ax, ay = frame.MoneyFrame or frame, frame.MoneyFrame and "TOPRIGHT" or "BOTTOMRIGHT",
        frame.MoneyFrame and 0 or -7, frame.MoneyFrame and 4 or 9
    local anchor = Call(frame, "GetInitialItemAnchor")
    if type(anchor) == "table" and anchor.Get then
        local p, r, rp, x, y = anchor:Get()
        if p == "BOTTOMRIGHT" and r then rel, relPoint, ax, ay = r, rp or p, x or 0, y or 0 end
    end

    local cols = ns.db.bagCols or blizzCols
    cols = math.max(MIN_COLS, math.min(MAX_COLS, cols))
    geo.w, geo.sp, geo.pad, geo.blizzCols = w, sp, pad, blizzCols
    return cols, blizzCols, w, h, sp, pad, rel, relPoint, ax, ay
end

local function BlizzardBaseHeight(frame)
    if baseHeight then return baseHeight end
    local value = Call(frame, "CalculateHeight")
    if type(value) == "number" then return value end
    return frame:GetHeight()
end

---------------------------------------------------------------------------
-- Fenster verschieben, andocken und einrasten
---------------------------------------------------------------------------

--[[
    - Tasche: Titelleiste ziehen. An Bank/Gildenbank angedockt: Ziehen = abdocken,
      Shift+Ziehen = beide zusammen verschieben. Nah an die Bank gezogen rastet
      die Tasche wieder ein (rechts oder links daneben, oben bündig).
    - Bank und Gildenbank: Titelleiste ziehen, die angedockte Tasche kommt mit.
    - Einzelne Taschenfenster (ohne kombinierte Tasche): Titelleiste ziehen.
    Alle Positionen werden gespeichert und nach Blizzards Anordnung wieder gesetzt.
]]

local SNAP = 24               -- Abstand (Bildschirmpunkte), ab dem eingerastet wird
local grip, mover
local moving                  -- Rahmen, der gerade gezogen wird
local panelMovers = setmetatable({}, { __mode = "k" })
local bagFrameMovers = setmetatable({}, { __mode = "k" })

-- Lagen nach Bildschirm-Viertel (so wächst ein Fenster in die richtige Richtung) in ezCoreDB.positions:
-- ezCore.StorePosition merkt, StoredPosition liest, ApplyPosition setzt (Schlüssel in Core.lua). Der
-- Zustand des Andockens (bagUndocked, dockSide) bleibt in ezBagDB.
local function SetQuadrantPos(frame, pos) ezCore.ApplyPosition(frame, pos) end

-- Bank und Gildenbank verschiebt ezBag selbst: bei ezCores „Blizzard-Fenster verschieben“ anmelden, damit es
-- dort keinen zweiten Griff und keine zweite Lage gibt. ezBag verschiebt sie immer, darum kein Release.
local PANELS = { "BankFrame", "GuildBankFrame" }
local function ClaimPanels()
    local MF = ezCore.MoveFrames
    if not (MF and MF.Claim) then return end
    for _, name in ipairs(PANELS) do MF.Claim(name, "ezBag") end
end
Layout.ClaimPanels = ClaimPanels

local function NotUserPlaced(frame)
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

-- Rechteck in Bildschirmpunkten (Tasche und Bank sind unterschiedlich skaliert).
local function ScreenRect(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not l then return nil end
    local s = frame:GetEffectiveScale()
    return l * s, r * s, t * s, b * s
end

local function DockFrames()
    local list = {}
    local guild = _G.GuildBankFrame
    if guild and guild:IsShown() then list[#list + 1] = guild end
    local bank = _G.BankFrame
    if bank and bank:IsShown() then list[#list + 1] = bank end
    return list
end

local function DockTarget()
    if not ns.S.dockBank or ns.db.bagUndocked then return nil end
    return DockFrames()[1]
end

-- Was ragt rechts aus Bank/Gildenbank heraus (z. B. die Reiter)? Bildschirmpunkte.
local function RightOverhang(target)
    local right = target:GetRight()
    if not right then return 0 end
    local edge = right * target:GetEffectiveScale()
    local maxRight = edge
    local function Scan(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() then
                local l, r = child:GetLeft(), child:GetRight()
                if l and r then
                    local s = child:GetEffectiveScale()
                    -- Nur was am rechten Rand beginnt und darüber hinausragt.
                    if l * s >= edge - 14 and r * s > maxRight then maxRight = r * s end
                end
                if depth < 2 then Scan(child, depth + 1) end
            end
        end
    end
    Scan(target, 1)
    return math.max(0, maxRight - edge)
end

-- Liegt die Tasche nah an Bank/Gildenbank? "right" = Tasche rechts daneben.
local function SnapSide(target)
    local bl, br, bt, bb = ScreenRect(bagFrame)
    local tl, tr, tt, tb = ScreenRect(target)
    if not bl or not tl then return nil end
    tr = tr + RightOverhang(target)
    if math.min(bt, tt) - math.max(bb, tb) < 20 then return nil end   -- senkrecht überlappen
    local snap = SNAP * UIParent:GetEffectiveScale()
    if math.abs(bl - tr) <= snap then return "right" end
    if math.abs(br - tl) <= snap then return "left" end
    return nil
end

local function TrySnap()
    if not ns.S.dockBank or not bagFrame:IsShown() then return false end
    for _, target in ipairs(DockFrames()) do
        local side = SnapSide(target)
        if side then
            ns.db.bagUndocked = nil
            ns.db.dockSide = side
            return true
        end
    end
    return false
end

local function AnchoredRight()
    if DockTarget() then return ns.db.dockSide == "left" end
    local pos = ezCore.StoredPosition(ns.BAG_KEY)
    if pos and pos.point then return pos.point:find("RIGHT") ~= nil end
    return true   -- Blizzard setzt die Tasche unten rechts an
end

local function PlaceGrip()
    if not grip then return end
    grip:ClearAllPoints()
    local right = AnchoredRight()
    if right then
        grip:SetPoint("BOTTOMLEFT", bagFrame, "BOTTOMLEFT", 3, 3)
    else
        grip:SetPoint("BOTTOMRIGHT", bagFrame, "BOTTOMRIGHT", -3, 3)
    end
    for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do
        if right then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end
    end
end

local customApplied = false

-- Eigene Position (verschoben oder angedockt) nach Blizzards Anordnung setzen.
local function ApplyPosition()
    if not bagFrame or not bagFrame:IsShown() or ns.ClassicUIBagsActive() then return false end
    if ns.InCombat() and bagFrame:IsProtected() then return false end
    if moving == bagFrame then return true end
    customApplied = false
    local target = DockTarget()
    local placed = false
    if target then
        bagFrame:ClearAllPoints()
        if ns.db.dockSide == "left" then
            bagFrame:SetPoint("TOPRIGHT", target, "TOPLEFT", -DOCK_GAP, 0)
        else
            -- Platz für Reiter, die rechts aus der Bank ragen (sonst verdeckt sie die Tasche).
            local gap = DOCK_GAP + RightOverhang(target) / bagFrame:GetEffectiveScale()
            bagFrame:SetPoint("TOPLEFT", target, "TOPRIGHT", gap, 0)
        end
        placed = true
    else
        local pos = ezCore.StoredPosition(ns.BAG_KEY)
        if pos and pos.point then
            SetQuadrantPos(bagFrame, pos)
            bagFrame:SetClampedToScreen(true)
            placed = true
        end
    end
    PlaceGrip()
    customApplied = placed
    return placed
end
Layout.ApplyPosition = ApplyPosition

-- Einzelne Taschenfenster an ihre gespeicherten Plätze (je Taschen-ID).
local function ApplyBagFrames()
    local section = ns.Reagent and ns.Reagent.Current()
    for frame in pairs(bagFrameMovers) do
        local id = frame:IsShown() and frame ~= section and frame:GetID()
        local pos = id and ezCore.StoredPosition(ns.BagFrameKey(id))
        if pos and pos.point and frame ~= moving then
            SetQuadrantPos(frame, pos)
            frame:SetClampedToScreen(true)
        end
    end
end

local function AfterBlizzardAnchors()
    ApplyPosition()
    ApplyBagFrames()
    -- Blizzard hat das Reagenzien-Fenster wieder in seine eigene Spalte gesetzt: zurück in den Abschnitt. Läuft das
    -- gerade während eines eigenen Anordnens (Layout.Reposition → BlizzardAnchors), gleich danach.
    if ns.Reagent and ns.Reagent.Current() and bagFrame and bagFrame:IsShown() then
        lastSignature = nil
        if applying then
            C_Timer.After(0, function()
                if bagFrame:IsShown() then
                    lastSignature = nil
                    Layout.Apply(bagFrame, true)
                end
            end)
        else
            Layout.Apply(bagFrame, true)
        end
    end
end

-- Blizzard die Tasche wieder selbst anordnen lassen (nur mit fertigem Zwischenspeicher).
local function BlizzardAnchors()
    if ns.InCombat() or type(UpdateContainerFrameAnchors) ~= "function" then return end
    local manager = _G.ContainerFrameSettingsManager
    if manager and rawget(manager, "bagsShown") then pcall(UpdateContainerFrameAnchors) end
end

local function Offscreen()
    local top, screenTop = bagFrame:GetTop(), UIParent:GetTop()
    if not top or not screenTop then return false end
    return top * bagFrame:GetEffectiveScale() > screenTop * UIParent:GetEffectiveScale()
end

-- Bank/Gildenbank an ihre gespeicherte Stelle (Blizzard setzt sie beim Öffnen neu).
local function ApplyPanel(frame)
    local name = frame and frame:GetName()
    local pos = name and ezCore.StoredPosition(ns.PanelKey(name))
    if pos and pos.point and frame:IsShown() and frame ~= moving then SetQuadrantPos(frame, pos) end
end

-- Nach dem Öffnen/Schließen von Bank oder Gildenbank und wenn die Tasche wächst.
function Layout.Reposition()
    for frame in pairs(panelMovers) do ApplyPanel(frame) end
    if bagFrame and bagFrame:IsShown() then
        local hadCustom = customApplied
        if not ApplyPosition() and (hadCustom or Offscreen()) then BlizzardAnchors() end
    end
    -- Erst jetzt stehen Bank, Gildenbank und Tasche an ihrem Platz: das ezBag-Fenster misst die neue Reihe und
    -- dockt neu an (sonst bliebe es beim Öffnen der Gildenbank an der alten Lage und läge über ihr).
    if ns.Window and ns.Window.Redock then ns.Window.Redock() end
end

-- Lässt sich die Tasche wieder andocken? Nur, wenn sie abgedockt ist, das Andocken an ist und Bank oder Gildenbank
-- offen stehen (sonst täte der Eintrag nichts).
function Layout.CanRedockBag()
    return ns.db ~= nil and ns.S ~= nil and ns.S.dockBank == true and ns.db.bagUndocked ~= nil and #DockFrames() > 0
end

-- „Wieder andocken“: eine Fassung für das Rechtsklick-Menü der Titelleiste und den Eintrag „Tasche wieder
-- andocken“ im Knopf „Tasche, Gruppe oder Bank“ der Werkzeugleisten (BAG-11). → true, wenn angedockt wurde
function Layout.RedockBag()
    if not Layout.CanRedockBag() then return false end
    ns.db.bagUndocked = nil
    ApplyPosition()
    return true
end

function Layout.ResetPosition()
    ns.db.bagCols, ns.db.bagUndocked, ns.db.dockSide = nil, nil, nil
    ezCore.StorePosition(ns.BAG_KEY, nil)
    for key in pairs(ezCore.Positions(false) or {}) do
        if type(key) == "string" and key:sub(1, #ns.BAGFRAME_PREFIX) == ns.BAGFRAME_PREFIX then ezCore.StorePosition(key, nil) end
    end
    lastSignature = nil
    BlizzardAnchors()
    Layout.Refresh(true)
end

-- Gemerkte Lage von Bank ("BankFrame") oder Gildenbank ("GuildBankFrame") vergessen: gilt ab dem nächsten Öffnen
-- (Rechtsklick auf die Titelleiste und Knopf unter „Erweitert“). → true, wenn es eine gemerkte Lage gab
function Layout.ResetPanel(name)
    local key = ns.PanelKey(name)
    local had = ezCore.StoredPosition(key) ~= nil
    ezCore.StorePosition(key, nil)
    return had
end

local function StartMoving(frame)
    if ns.InCombat() and frame:IsProtected() then return end
    moving = frame
    frame:SetMovable(true)
    frame:StartMoving()
end

local function StopMoving()
    local frame = moving
    moving = nil
    if not frame then return nil end
    frame:StopMovingOrSizing()
    NotUserPlaced(frame)
    return frame
end

-- Rechtsklick-Menü der Titelleiste der Tasche (auch für die Prüfungen erreichbar: Layout.OpenPositionMenu).
local function OpenPositionMenu(owner)
    return ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.MENU_BAG_TITLE)
        root:CreateCheckbox(L.OPT_dockBank, function() return ns.S.dockBank end,
            function() ns.SetSetting("dockBank", not ns.S.dockBank) end)
        if Layout.CanRedockBag() then
            root:CreateButton(L.MENU_REDOCK, function() Layout.RedockBag() end)
        end
        root:CreateButton(L.MENU_RESET_POSITION, Layout.ResetPosition)
    end)
end
Layout.OpenPositionMenu = OpenPositionMenu

-- Unsichtbarer Griff über der Titelleiste eines Fensters.
local function MakeMover(frame, left, right, onStart, onStop, onMenu, onEnter)
    local m = CreateFrame("Button", nil, frame)
    m:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -1)
    m:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, -1)
    m:SetHeight(20)
    m:SetFrameLevel(frame:GetFrameLevel() + 8)
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("RightButtonUp")
    m:SetScript("OnDragStart", onStart)
    m:SetScript("OnDragStop", onStop)
    m:SetScript("OnClick", onMenu)
    m:SetScript("OnEnter", onEnter)
    m:SetScript("OnLeave", GameTooltip_Hide)
    return m
end

local function CreateMover()
    mover = MakeMover(bagFrame, 58, -52,
        function()
            if ns.ClassicUIBagsActive() then return end
            local target = DockTarget()
            if target and IsShiftKeyDown() then
                StartMoving(target)        -- zusammen: Bank ziehen, die Tasche hängt daran
            else
                StartMoving(bagFrame)      -- allein (dockt ab)
            end
        end,
        function()
            local frame = StopMoving()
            if not frame then return end
            if frame ~= bagFrame then
                ezCore.StorePosition(ns.PanelKey(frame:GetName()), frame)
            elseif #DockFrames() > 0 then
                if not TrySnap() then
                    ns.db.bagUndocked = true
                    ezCore.StorePosition(ns.BAG_KEY, bagFrame)
                end
            else
                ezCore.StorePosition(ns.BAG_KEY, bagFrame)
            end
            ApplyPosition()
        end,
        function(self) OpenPositionMenu(self) end,
        function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.MOVER_TITLE, ns.TipRGB("normal"))
            if DockTarget() then
                ns.AddTipLine(L.MOVER_DOCKED, "highlight", true)
            else
                ns.AddTipLine(L.MOVER_DRAG, "highlight", true)
                if #DockFrames() > 0 then ns.AddTipLine(L.MOVER_SNAP, "highlight", true) end
            end
            ns.AddTipLine(L.MOVER_MENU, "highlight", true)
            ns.AddTipLine(ns.CmdText(L.MOVER_CMD), "hint", true)
            GameTooltip:Show()
        end)
end

local function PanelTitle(frame)
    return frame == _G.GuildBankFrame and L.GUILD_BANK_TITLE or L.BANK_TITLE
end

-- Bank und Gildenbank verschiebbar machen.
local function InstallPanelMover(frame)
    if not frame or panelMovers[frame] or not frame:GetName() then return end
    -- Die Bank hat oben links ein Porträt, die Gildenbank nicht.
    local left = frame.PortraitContainer and 60 or 6
    panelMovers[frame] = MakeMover(frame, left, -28,
        function() StartMoving(frame) end,
        function()
            local f = StopMoving()
            if not f then return end
            ezCore.StorePosition(ns.PanelKey(f:GetName()), f)
            -- Abgedockte Tasche nah dran? Dann rastet sie ein.
            if ns.db.bagUndocked and bagFrame and bagFrame:IsShown() then TrySnap() end
            ApplyPosition()
        end,
        function(self)
            ezCore.Menu.Open(self, function(root)
                root:CreateTitle(PanelTitle(frame))
                root:CreateButton(L.MENU_RESET_PANEL, function()
                    Layout.ResetPanel(frame:GetName())
                    ns.Print(L.PANEL_RESET_NEXT)
                end)
            end)
        end,
        function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(PanelTitle(frame), ns.TipRGB("normal"))
            ns.AddTipLine(L.PANEL_MOVER_DRAG, "highlight", true)
            ns.AddTipLine(L.PANEL_MOVER_MENU, "highlight", true)
            GameTooltip:Show()
        end)
    frame:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            ApplyPanel(self)
            Layout.Reposition()
        end)
    end)
end
Layout.InstallPanelMover = InstallPanelMover

-- Einzelne Taschenfenster (wenn die kombinierte Tasche aus ist).
local function InstallBagFrameMovers()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and not bagFrameMovers[frame] then
            bagFrameMovers[frame] = MakeMover(frame, 40, -26,
                function() StartMoving(frame) end,
                function()
                    local f = StopMoving()
                    local id = f and f:GetID()
                    if id then ezCore.StorePosition(ns.BagFrameKey(id), f) end
                end,
                function()
                    local id = frame:GetID()
                    if id then ezCore.StorePosition(ns.BagFrameKey(id), nil) end
                    BlizzardAnchors()
                end,
                function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    ns.AddTipLine(L.BAGFRAME_MOVER, "highlight", true)
                    GameTooltip:Show()
                end)
        end
    end
end

local resizing = false

local function CurrentCols()
    return math.max(MIN_COLS, math.min(MAX_COLS, ns.db.bagCols or geo.blizzCols))
end

local function UpdateResize(self)
    if not resizing then
        self:Hide()
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        resizing = false
        self:Hide()
        return
    end
    local x = GetCursorPosition() / bagFrame:GetEffectiveScale()
    local left, right = bagFrame:GetLeft(), bagFrame:GetRight()
    if not left then return end
    local width = AnchoredRight() and (right - x) or (x - left)
    local cols = math.floor((width - geo.pad + geo.sp) / (geo.w + geo.sp) + 0.5)
    cols = math.max(MIN_COLS, math.min(MAX_COLS, cols))
    if cols ~= CurrentCols() then
        ns.db.bagCols = (cols ~= geo.blizzCols) and cols or nil
        Layout.Refresh(true)
    end
end

local function CreateGrip()
    grip = CreateFrame("Button", nil, bagFrame)
    -- Größe wie Blizzards Griff zum Größe-Ändern (PanelResizeButtonTemplate 16 × 16, Core.Style.BUTTON.small)
    grip:SetSize(ezCore.Style.BUTTON.small, ezCore.Style.BUTTON.small)
    grip:SetFrameLevel(bagFrame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:RegisterForClicks("RightButtonUp")
    local driver = CreateFrame("Frame", nil, grip)
    driver:Hide()
    driver:SetScript("OnUpdate", UpdateResize)
    grip:SetScript("OnMouseDown", function(_, mouse)
        if mouse ~= "LeftButton" then return end
        resizing = true
        driver:Show()
    end)
    grip:SetScript("OnClick", function()
        ns.db.bagCols = nil
        Layout.Refresh(true)
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.GRIP_TITLE, ns.TipRGB("normal"))
        ns.AddTipLine(L.GRIP_TIP:format(CurrentCols()), "highlight", true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    PlaceGrip()
end

---------------------------------------------------------------------------
-- Einsortieren und Anordnen
---------------------------------------------------------------------------

local function CollectButtons(frame)
    local list = {}
    if not frame.Items then return list end
    for _, button in frame:EnumerateValidItems() do
        if button then list[#list + 1] = button end
    end
    return list
end

-- Gruppen aus echten Container-Plätzen (Tasche, Bank, Bank im ezBag-Fenster).
function ns.GroupsFromSlots(slots, allowNew)
    local groups, byKey, families = {}, {}, {}
    for _, s in ipairs(slots) do
        local bag, slot = s.bag, s.slot
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local key = s.locked and "locked" or ns.Classify(bag, slot, info, allowNew)

        local groupKey = key
        if key == "empty" then
            local special = families[bag]
            if special == nil then
                special = ezCore.IsSpecialBag(bag)
                families[bag] = special
            end
            -- Spezialtaschen (Köcher, Seelentasche, Berufstaschen) bekommen ihr eigenes "Frei".
            if special then groupKey = "empty:" .. bag end
        end

        local group = byKey[groupKey] or ns.Render.NewGroup(groups, byKey, key, groupKey)
        local entry = { button = s.button, bag = bag, slot = slot, order = bag * 1000 + slot, sig = bag * 1000 + slot }
        local itemID = ns.ItemIDOf(info)
        if itemID then
            entry.itemID = itemID
            entry.link = info.hyperlink
            entry.quality = info.quality or 1
            entry.name = ns.ItemName(info.hyperlink) or ""
            entry.count = info.stackCount or 1
            if key == "junk" then group.copper = group.copper + ns.SellValue(info) end
        end
        group.entries[#group.entries + 1] = entry
    end
    ns.Render.AddEmptyCustomGroups(groups, byKey)
    ns.Render.SortGroups(groups)
    return groups
end

local function BuildGroups(buttons, v)
    local slots = {}
    for i, button in ipairs(buttons) do
        HookButton(button, v)
        slots[i] = { button = button, bag = button:GetBagID(), slot = button:GetID(), locked = IsExtended(button) }
    end
    return ns.GroupsFromSlots(slots, true)
end

-- Taschen für "Tasche wählen" in der Werkzeugleiste.
local function BagList()
    local list = {}
    for _, bag in ipairs(ns.Transfer.BagIDs()) do
        local total = C_Container.GetContainerNumSlots(bag) or 0
        if total > 0 then
            local icon
            if bag == 0 then
                icon = "Interface\\Buttons\\Button-Backpack-Up"
            elseif C_Container.ContainerIDToInventoryID then
                local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
                icon = ok and inv and GetInventoryItemTexture("player", inv) or nil
            end
            list[#list + 1] = { id = bag, total = total, icon = icon,
                name = C_Container.GetBagName(bag) or (bag == 0 and (BACKPACK_TOOLTIP or "Backpack")) or tostring(bag),
                free = C_Container.GetContainerNumFreeSlots(bag) or 0 }
        end
    end
    return list
end

-- Suchfeld direkt unter die Titelleiste, vom Porträt bis zur Werkzeugleiste und dem Sortierknopf.
local function FitSearchBox(frameWidth)
    local box = _G.BagItemSearchBox
    if not box or box.anchorBag ~= bagFrame then return end
    local barW = toolbar and toolbar:Update() or 0
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", bagFrame, "TOPLEFT", SEARCH_X, -SEARCH_Y)
    box:SetWidth(math.max(60, frameWidth - SEARCH_X - 36 - (barW > 0 and (barW + 4) or 0)))
    local sort = _G.BagItemAutoSortButton
    local sortHere = sort and sort:GetParent() == bagFrame
    if sortHere then
        sort:ClearAllPoints()
        sort:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -7, -(SEARCH_Y - 3))
    end
    if toolbar then
        toolbar.frame:ClearAllPoints()
        if sortHere then
            toolbar.frame:SetPoint("RIGHT", sort, "LEFT", -2, 0)
        else
            toolbar.frame:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -8, -(SEARCH_Y - 1))
        end
        toolbar.frame:Show()
    end
end

-- Abstand von der Unterkante der Tasche bis zu Blizzards Ankerpunkt (über dem Geldfeld).
-- Abschnitt Reagenzientasche: Gruppen aus Blizzards Reagenzien-Fenster, getrennt von der Tasche angeordnet (eigene
-- Gruppen, eigenes Sortieren, Zusammenfassen und „Frei“) → { frame, buttons, out, contentH, height } oder nil
local function BuildSection(cols, w, h, sp, searching)
    local R = ns.Reagent
    local frame = R and R.Wanted() and R.Frame() or nil
    if not frame then return nil end
    local buttons = R.Buttons(frame)
    if #buttons == 0 then return nil end
    if not rholder then
        rholder = CreateFrame("Frame", nil, frame)
        rview = ns.Render.NewView(rholder, "reagent")   -- eigener Zuklapp-Merker; beim Weitergeben wie die Tasche
        view.linked = { rview }                           -- „Auswählen“ und Umlagern-Pfeile auch im Abschnitt
    end
    if rholder:GetParent() ~= frame then rholder:SetParent(frame) end
    rholder:SetAllPoints(frame)
    rholder:SetFrameLevel(frame:GetFrameLevel() + 1)
    rholder:Show()
    rview.focus = view and view.focus or nil
    local out = ns.Render.Flow(BuildGroups(buttons, rview), { cols = cols, w = w, h = h, spX = sp, spY = sp },
        { viewKey = "reagent", searching = searching })
    local contentH = math.max(out.totalH - out.bottomHalf, 0)
    return { frame = frame, buttons = buttons, out = out, contentH = contentH, height = R.SECTION_H + contentH }
end

-- Abschnitt aufheben: Plätze wieder sichtbar, Fenster sieht aus wie Blizzards. reopen: Blizzard soll das noch offene
-- Fenster selbst neu anordnen (Schalter oder Gruppierung aus) – einmal zu und wieder auf, aus Blizzards laufendem Aufruf
-- herausgelöst (C_Timer). Im Kampf wird nichts aufgehoben, solange das Fenster zu sehen ist: Die Plätze hängen an der
-- Tasche und zerfielen sonst bis zum Kampfende; das Fenster wird ganz unsichtbar (Reagent.HideForCombat), nach dem Kampf
-- wird aufgehoben (und neu geöffnet bzw. geschlossen).
local ReleaseSection
ReleaseSection = function(reopen, afterCombat)
    local R = ns.Reagent
    local frame = sectionFrame
    if frame and frame:IsShown() and ns.InCombat() then
        R.HideForCombat(frame)
        -- Markier-Knöpfe und Gruppen-Titel des Abschnitts weder anklickbar noch mitgezählt
        if rview then
            ns.Transfer.ClearMarks(rview.entries)
            rview:HideAll()
        end
        if rholder then rholder:Hide() end
        ns.AfterCombat(function()
            if not (bagFrame and bagFrame:IsShown() and not Layout.Blocked() and R.Wanted()) then
                ReleaseSection(reopen, afterCombat)
            else
                R.ShowAfterCombat()
                lastSignature = nil
                Layout.Apply(bagFrame, true)
            end
            if afterCombat then afterCombat() end
        end, "ezBag.reagentSection")
        return true
    end
    if rview then
        for _, entry in ipairs(rview.entries) do
            if entry.button then ns.Render.SetDimmed(entry.button, false) end
        end
        ns.Transfer.ClearMarks(rview.entries)
        rview:HideAll()
    end
    if rholder then rholder:Hide() end
    sectionFrame = nil
    if not frame then
        if R then R.Release() end
        return false
    end
    for _, button in ipairs(R.Buttons(frame)) do
        Reveal(button)
        ns.SetFreeCount(button, nil)
        ns.SetStackTotal(button, nil)
        ns.SetItemMarks(button)   -- ohne Abschnitt zeichnet ezBag am Einzelfenster keine Marken
    end
    R.Release()
    if reopen and frame:IsShown() then
        C_Timer.After(0, function()
            if ns.InCombat() or not frame:IsShown() then return end
            ezCore.ClosePanel("reagentBag", nil, true)
            ezCore.OpenPanel("reagentBag", nil, true)
        end)
    end
    return true
end
Layout.ReleaseSection = ReleaseSection

local function AnchorFromBottom(frame, rel, relPoint, ay)
    local fb = frame:GetBottom()
    local ry
    if rel ~= frame then ry = (relPoint or ""):find("TOP") and rel:GetTop() or rel:GetBottom() end
    if fb and ry then geo.anchorFromBottom = ry - fb + ay end
    return geo.anchorFromBottom
end

local function DoLayout(frame, fromBlizzard)
    dirty = false
    local buttons = CollectButtons(frame)
    if #buttons == 0 then return end

    local cols, blizzCols, w, h, sp, pad, rel, relPoint, ax, ay = Geometry(frame, buttons[1])
    local searching = BagItemSearchBox and BagItemSearchBox:IsVisible() and (BagItemSearchBox:GetText() or "") ~= ""

    local groups = BuildGroups(buttons)
    local out = ns.Render.Flow(groups, { cols = cols, w = w, h = h, spX = sp, spY = sp },
        { viewKey = "bag", searching = searching })
    local section = BuildSection(cols, w, h, sp, searching)
    local sectionH = section and section.height or 0

    -- Breite: wie Blizzard, nur mit unserer Spaltenzahl.
    local newWidth = cols * w + (cols - 1) * sp + pad
    -- Höhe: Blizzards Höhe, aber mit unserem Layout statt des einfachen Rasters.
    local rows0 = math.ceil(#buttons / blizzCols)
    local gridH = rows0 * h + math.max(rows0 - 1, 0) * sp
    local contentH = math.max(out.totalH - out.bottomHalf, 0)
    -- Oben: Titelleiste, Suchfeld, dann gleich die erste Gruppe. Unten bleibt Blizzards Fuß.
    local fromBottom = AnchorFromBottom(frame, rel, relPoint, ay)
    local newHeight
    if fromBottom then
        newHeight = AREA_TOP + contentH + sectionH + fromBottom
    else
        newHeight = BlizzardBaseHeight(frame) - gridH + contentH + sectionH - TOP_TRIM
    end
    newHeight = math.max(newHeight, 120)
    local sizeChanged = math.abs((frame:GetHeight() or 0) - newHeight) > 0.5
        or math.abs((frame:GetWidth() or 0) - newWidth) > 0.5

    local signature = ns.Render.Signature(out, cols)
    if section then
        signature = signature .. "|reagent|" .. ns.Render.Signature(section.out, cols) .. ns.Reagent.HeaderText()
    end
    if not fromBlizzard and not sizeChanged and signature == lastSignature then
        UpdateOverlays(frame)
        if section then UpdateOverlays(section.frame) end
        return
    end
    lastSignature = signature

    if sizeChanged then frame:SetSize(newWidth, newHeight) end
    FitSearchBox(newWidth)

    -- left/top: Abstand von der linken oberen Ecke des Layouts. Die rechte untere
    -- Ecke des Layouts liegt einen halben Abstand neben Blizzards Ankerpunkt.
    -- Mit Abschnitt Reagenzientasche liegt die Tasche um dessen Höhe weiter oben.
    local width, totalH = out.width, out.totalH
    local rightHalf = sp - math.floor(sp / 2)
    local function Place(region, left, top, ew, eh)
        region:ClearAllPoints()
        region:SetPoint("BOTTOMRIGHT", rel, relPoint, ax + rightHalf - (width - left - ew),
            ay - out.bottomHalf + sectionH + (totalH - top - eh))
    end

    view:Draw(out, Place, function(entry, shown, left, top, g)
        local button = entry.button
        ns.SetFreeCount(button, nil)
        if shown then
            Place(button, left, top, w, h)
            Reveal(button)
            if g.compressed then ns.SetFreeCount(button, g.count) end
            ns.SetStackTotal(button, entry.stackTotal)
        else
            Conceal(button, holder)
            ns.SetStackTotal(button, nil)
        end
    end)
    view:ApplyDim()
    UpdateOverlays(frame)

    if section then
        -- Abschnitt unten: Trennlinie mit Überschrift, darunter die Gruppen der Reagenzientasche (eigene Ansicht)
        local rout = section.out
        local rwidth, rtotalH = rout.width, rout.totalH
        local function RPlace(region, left, top, ew, eh)
            region:ClearAllPoints()
            region:SetPoint("BOTTOMRIGHT", rel, relPoint, ax + rightHalf - (rwidth - left - ew),
                ay - rout.bottomHalf + (rtotalH - top - eh))
        end
        sectionFrame = section.frame
        ns.Reagent.Attach(section.frame, frame, {
            holder = holder,
            keep = { [rholder] = true },
            PlaceRect = function(region)
                region:SetPoint("BOTTOMRIGHT", rel, relPoint, ax + rightHalf, ay - rout.bottomHalf)
                region:SetPoint("TOPLEFT", rel, relPoint, ax + rightHalf - rwidth, ay - rout.bottomHalf + rtotalH)
            end,
            PlaceHeader = function(region)
                region:ClearAllPoints()
                region:SetSize(rwidth, ns.Reagent.SECTION_H)
                region:SetPoint("BOTTOMRIGHT", rel, relPoint, ax + rightHalf, ay + section.contentH)
            end,
        })
        rview:Draw(rout, RPlace, function(entry, shown, left, top, g)
            local button = entry.button
            ns.SetFreeCount(button, nil)
            if shown then
                RPlace(button, left, top, w, h)
                Reveal(button)
                if g.compressed then ns.SetFreeCount(button, g.count) end
                ns.SetStackTotal(button, entry.stackTotal)
            else
                Conceal(button, rholder)
                ns.SetStackTotal(button, nil)
            end
        end)
        rview:ApplyDim()
        UpdateOverlays(section.frame)
        Layout.QueueSectionSync()
        if ns.Select.IsActive(view) then ns.Select.Refresh(view) end
    else
        ReleaseSection(false)
    end

    if searching then
        C_Timer.After(0, function()
            view:ExtendSearch(BagItemSearchBox:GetText())
            if rview and rview.out then rview:ExtendSearch(BagItemSearchBox:GetText()) end
        end)
    end
    if toolbar then toolbar:Update() end
    ns.Transfer.Refresh()

    if sizeChanged and not fromBlizzard then Layout.Reposition() end
end

-- Grau im Abschnitt abgleichen, sobald Blizzard nach Aufräumen, Verschieben, Suchen oder Tragen fertig ist (einmal je
-- Bild): Blizzards Grau ohne Grund zurücknehmen (Reagent.SyncGrey) und ezBags Hervorheben verwandter Gegenstände
-- aufheben, wenn die Maus nicht mehr über dem Abschnitt steht (ein verpasstes OnLeave ließ es sonst stehen).
local syncQueued = false
function Layout.SyncSection()
    syncQueued = false
    if not (sectionFrame and rview) then return end
    ns.Reagent.SyncGrey()
    if not sectionFrame:IsMouseOver() then rview:SetHover(nil) end
end

function Layout.QueueSectionSync()
    if syncQueued or not sectionFrame then return end
    syncQueued = true
    C_Timer.After(0, Layout.SyncSection)
end

for _, event in ipairs({ "CURSOR_CHANGED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_DELAYED", "INVENTORY_SEARCH_UPDATE" }) do
    ns.On(event, Layout.QueueSectionSync)
end

-- Blizzards einfaches Raster wiederherstellen (wenn die Gruppierung ausgeschaltet wird).
local function RestoreGrid(frame, reposition)
    for button in pairs(hiddenByUs) do Reveal(button) end
    for button, o in pairs(overlays) do
        o.free:SetText("")
        ns.SetStackTotal(button, nil)
    end
    for _, entry in ipairs(view.entries) do
        if entry.button then ns.Render.SetDimmed(entry.button, false) end
    end
    view:HideAll()
    view.focus = nil
    if toolbar then toolbar.frame:Hide() end
    lastSignature = nil
    -- Suchfeld und Sortierknopf wieder an Blizzards Stellen.
    local box, sort = _G.BagItemSearchBox, _G.BagItemAutoSortButton
    if box and box.anchorBag == frame then
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -37)
        box:SetWidth(330)
    end
    if sort and sort:GetParent() == frame then
        sort:ClearAllPoints()
        sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -34)
    end
    if not reposition then return end

    local buttons = CollectButtons(frame)
    if #buttons == 0 then return end
    local _, cols, w, h, sp, _, rel, relPoint, ax, ay = Geometry(frame, buttons[1])
    -- Blizzard: gesperrte Erweiterungsplätze zuletzt, sonst in Taschenreihenfolge.
    local normal, extended = {}, {}
    for _, button in ipairs(buttons) do
        table.insert(IsExtended(button) and extended or normal, button)
    end
    for _, button in ipairs(extended) do normal[#normal + 1] = button end
    for i, button in ipairs(normal) do
        local index = i - 1
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", rel, relPoint, ax - (index % cols) * (w + sp), ay + math.floor(index / cols) * (h + sp))
    end
    local width = Call(frame, "CalculateWidth")
    frame:SetSize(type(width) == "number" and width or frame:GetWidth(), BlizzardBaseHeight(frame))
end

---------------------------------------------------------------------------
-- Öffentliche Funktionen
---------------------------------------------------------------------------

function Layout.Blocked()
    return not ns.S or not ns.S.grouping or ns.ClassicUIBagsActive()
end

function Layout.Apply(frame, fromBlizzard)
    if applying or not frame or not view then return end
    if Layout.Blocked() then
        ReleaseSection(true)
        if next(hiddenByUs) or #view.entries > 0 or lastSignature then
            RestoreGrid(frame, not fromBlizzard and frame:IsShown())
        end
        if grip then grip:Hide() end
        return
    end
    if grip then grip:Show() end
    if not fromBlizzard and not frame:IsShown() then return end
    if ns.InCombat() and frame:IsProtected() then
        dirty = true
        return
    end
    applying = true
    local ok, err = pcall(DoLayout, frame, fromBlizzard)
    applying = false
    if not ok then geterrorhandler()(err) end
end

-- Neu ordnen, sobald es niemanden stört (Maus nicht über der Tasche,
-- nichts am Mauszeiger). So springt beim Verkaufen oder Benutzen nichts weg.
function Layout.Request()
    dirty = true
end

function Layout.Refresh(force)
    if not bagFrame or not bagFrame:IsShown() then
        lastSignature = nil
        return
    end
    if force then
        lastSignature = nil
        Layout.Apply(bagFrame, false)
    else
        dirty = true
    end
end

function Layout.RefreshOverlays()
    if bagFrame and bagFrame:IsShown() then UpdateOverlays(bagFrame) end
end

function Layout.Frame()
    return bagFrame
end

-- Für den Rundgang (Tour.lua): Werkzeugleiste, Breiten-Griff und Ansicht der Tasche.
function Layout.Toolbar() return toolbar end
function Layout.Grip() return grip end
function Layout.View() return view end

local function CanRelayoutNow(frame)
    -- Etwas auf die „Frei“-Kachel des Abschnitts Reagenzientasche gelegt: wie bei der Tasche gleich neu ordnen.
    if rview and rview.out and not resizing and rview:FreeTileTaken() and ns.Render.CanRelayout(nil, false) then return true end
    return ns.Render.CanRelayout(frame, resizing, view)
end

local OnHolderUpdate = ns.Render.DeferredUpdate(function() return dirty end, function()
    if CanRelayoutNow(bagFrame) then Layout.Apply(bagFrame, false) end
end, CHECK_INTERVAL)

local function OnItemsUpdated(frame)
    if not ns.S then return end
    if frame.Items then
        for _, button in frame:EnumerateValidItems() do
            if button then HookButton(button) end
        end
    end
    UpdateOverlays(frame)
    if not Layout.Blocked() then dirty = true end
end

local function Install()
    if installed then return end
    bagFrame = _G.ContainerFrameCombinedBags
    if not bagFrame or not bagFrame.UpdateItemLayout then return end
    installed = true

    holder = CreateFrame("Frame", nil, bagFrame)
    holder:SetAllPoints()
    holder:SetFrameLevel(bagFrame:GetFrameLevel() + 1)
    holder:SetScript("OnUpdate", OnHolderUpdate)
    view = ns.Render.NewView(holder, "bag")
    toolbar = ns.Toolbar.New(bagFrame, {
        viewKey = "bag",
        view = function() return view end,
        bags = BagList,
        views = function() return ns.Window and ns.Window.ViewEntries() or {} end,
        transfer = "bag",
        space = true,
        select = true,
        search = function() return _G.BagItemSearchBox end,
        allChars = true,
        onResize = function()
            if not Layout.Blocked() and bagFrame:IsShown() then FitSearchBox(bagFrame:GetWidth() or 0) end
        end,
    })
    toolbar.frame:SetFrameLevel(bagFrame:GetFrameLevel() + 20)
    toolbar.frame:Hide()
    ns.Transfer.Register("bag", view, bagFrame, toolbar)
    -- „Tasche, Gruppe oder Bank“ hebt auch im Abschnitt Reagenzientasche hervor
    local baseSetFocus = view.SetFocus
    view.SetFocus = function(self, focus)
        baseSetFocus(self, focus)
        if rview then rview:SetFocus(focus) end
    end
    -- Abschnitt Reagenzientasche (Reagent.lua): Blizzards Reagenzien-Fenster geht auf, zu oder ordnet neu
    ns.Reagent.HookFrames(function()
        if bagFrame:IsShown() and not Layout.Blocked() then
            lastSignature = nil
            Layout.Apply(bagFrame, true)
        elseif sectionFrame then
            ReleaseSection(false)
        end
    end, function(frame)
        UpdateOverlays(frame)
        if not Layout.Blocked() then dirty = true end
        Layout.QueueSectionSync()
    end)
    bagFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if bagFrame:IsShown() then ns.Reagent.OnBagShown() end
        end)
    end)

    hooksecurefunc(bagFrame, "UpdateFrameSize", function(self)
        baseHeight = self:GetHeight()
        Layout.Apply(self, true)
    end)
    hooksecurefunc(bagFrame, "UpdateItemLayout", function(self)
        Layout.Apply(self, true)
    end)
    if bagFrame.UpdateItems then
        hooksecurefunc(bagFrame, "UpdateItems", OnItemsUpdated)
    end
    if bagFrame.UpdateSearchBox then
        hooksecurefunc(bagFrame, "UpdateSearchBox", function(self)
            if not Layout.Blocked() then FitSearchBox(self:GetWidth() or 0) end
        end)
    end
    if type(UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", AfterBlizzardAnchors)
    end
    bagFrame:HookScript("OnHide", function()
        dirty = false
        resizing = false
        lastSignature = nil
        ns.Render.CancelDrag()
        ns.ClearNewItems()
        if toolbar then toolbar:ClearFocus() end
        -- Abschnitt aufheben und die Reagenzientasche mitschließen (im Kampf beides erst danach)
        if sectionFrame and sectionFrame:IsShown() and ns.InCombat() then
            ReleaseSection(false, ns.Reagent.CloseIfBagHidden)
        else
            ReleaseSection(false)
            ns.Reagent.OnBagHidden()
        end
    end)
    CreateMover()
    CreateGrip()
    ClaimPanels()
    InstallPanelMover(_G.BankFrame)
    InstallBagFrameMovers()
    if type(UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", function()
            for frame in pairs(panelMovers) do ApplyPanel(frame) end
        end)
    end
end

-- Für Prüfungen (Tests/reagenz_test.lua): nachträglich anbinden, wenn die nachgebaute Tasche erst später entsteht.
Layout.Install = Install

-- Sofort installieren: Blizzards Taschenrahmen existiert schon, bevor Addons laden.
-- Die Teile mit gespeicherten Einstellungen warten auf PLAYER_LOGIN.
ns.OnReady(Install)

ns.On("BAG_UPDATE_DELAYED", function() if not Layout.Blocked() then Layout.Request() end end)
ns.On("INVENTORY_SEARCH_UPDATE", function() if not Layout.Blocked() then Layout.Refresh(true) end end)

-- Andocken: Bank und Gildenbank öffnen/schließen.
local function Redock()
    C_Timer.After(0, function() Layout.Reposition() end)
end
ns.On("BANKFRAME_OPENED", Redock)
ns.On("BANKFRAME_CLOSED", Redock)
ns.On("GUILDBANKFRAME_OPENED", function()
    InstallPanelMover(_G.GuildBankFrame)
    Redock()
end)
ns.On("GUILDBANKFRAME_CLOSED", Redock)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Redock)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Redock)

ns.OnSettingChanged(function(key)
    if key == "compactStacks" or key == "sortMode" then
        ns.Groups.RefreshAll()
    elseif key == "grouping" or key == "newItems" or key == "compressEmpty" then
        Layout.Refresh(true)
    elseif key == "reagentSection" then
        if ns.S.reagentSection then
            if bagFrame and bagFrame:IsShown() then ns.Reagent.OnBagShown() end
            Layout.Refresh(true)
        else
            ReleaseSection(true)
            Layout.Refresh(true)
        end
    elseif key == "itemLevel" or key == "boe" then
        Layout.RefreshOverlays()
    elseif key == "dockBank" then
        Layout.Reposition()
    elseif key == "dockWindow" then
        if ns.Window and ns.Window.Redock then ns.Window.Redock() end
    end
end)
