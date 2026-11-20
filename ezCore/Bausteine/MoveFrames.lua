local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    ezCore.Mover, Teil 2: Blizzard-Fenster an der Titelleiste verschieben (Charakter, Zauberbuch, Berufe, Händler,
    Lehrer, Post, Quests …). Schalter „Blizzard-Fenster verschieben“ im Abschnitt „Komfort“ der Seite
    „ezCollection“, Standard aus; daneben ein Knopf, der alle Positionen zurücksetzt.

    So bleibt es taint-sicher (Leitlinien 4 und 5):
      - Ein eigener, unsichtbarer Griff in der Titelleiste (Kind des Fensters) nimmt das Ziehen an; Porträt und
        Schließen-Knopf bleiben frei. Rechtsklick auf den Griff setzt das Fenster zurück.
      - Nichts wird in Blizzards Tabellen geschrieben (UIPanelWindows bleibt unberührt), Blizzards Panel-Verwaltung
        wird nie selbst aufgerufen. Nach Blizzards eigenem Platzieren (OnShow, UpdateUIPanelPositions – nur
        hooksecurefunc/HookScript) setzt ezCore die gespeicherte Lage einen Frame später.
      - Geschützte Fenster nur außerhalb des Kampfes (danach PLAYER_REGEN_ENABLED); Fenster des
        Bearbeitungsmodus (mit .system) nie.
      - Läuft BlizzMove, hält sich ezCore zurück (Core.WhoHandles("moveFrames")).
    Positionen in ezCoreDB.positions["blizz:<Fenstername>"].

    Größe (W-43, Frage 28 – Empfehlung umgesetzt, Antwort offen): eigener Schalter „Blizzard-Fenster skalieren“
    (comfort.frameScale, ab Werk aus, wirkt nur mit „Blizzard-Fenster verschieben“). Strg+Mausrad am Griff oder die
    Knöpfe „−“/„+“, die beim Überfahren der Titelleiste erscheinen, ändern die Größe in Schritten von 5 % (60 bis 150 %);
    Wert in ezCoreDB.comfort.frameScales[<Fenster>]. Blizzards eigene Größe (GetScale beim ersten Ändern) ist der
    Ausgang – „Größe zurücksetzen“ und das Ausschalten stellen sie wieder her. SetScale nur außerhalb des Kampfes
    (geschützte Fenster sonst nach dem Kampf). Je Fenster abwählbar (AI-03 b): Rechtsklick auf den Griff öffnet ein Menü
    (Lage zurücksetzen, Größe zurücksetzen, „Dieses Fenster nicht verschieben“); ausgeschlossene Fenster in
    comfort.moveFramesSkip, der Knopf „Alle wieder zulassen“ steht unter „Komfort“.

      ezCore.MoveFrames.FRAMES       Namen der Fenster (auch die erst später geladenen Blizzard-Addons)
      ezCore.MoveFrames.Enabled()    an und von niemand anderem übernommen?
      ezCore.MoveFrames.Reset(name)  eine Position vergessen (ohne name: alle); gilt beim nächsten Öffnen
      ezCore.MoveFrames.Claim(name, owner)   ein Modul verschiebt dieses Fenster selbst (ezBag: Bank, Gildenbank) –
                                     ezCore zeigt dort keinen Griff und setzt keine Lage (eine Quelle je Fenster)
      ezCore.MoveFrames.Release(name)        wieder freigeben   ezCore.MoveFrames.ClaimedBy(name) → Modul oder nil
      ezCore.MoveFrames.Rearranged() Blizzards Fensterverwaltung hat neu angeordnet (ruft der Hook; auch für Tests)
      ezCore.MoveFrames.ScaleEnabled()        Größe änderbar?   MoveFrames.ScaleOf(name) → gemerkte Größe oder nil
      ezCore.MoveFrames.SetScale(name, wert)  → angewandte Größe (nil = Blizzards eigene; geklemmt auf SCALE_MIN … MAX)
      ezCore.MoveFrames.Step(name, richtung)  ±1 Schritt      MoveFrames.ResetScale(name) (ohne name: alle) → Anzahl
      ezCore.MoveFrames.Skip(name, ja)        Fenster ausschließen bzw. wieder zulassen   MoveFrames.Skipped() → Liste
    Nachricht FRAME_MOVED (name | nil, pos | nil): ein Fenster wurde am Griff verschoben oder an seine gemerkte Lage
    gesetzt (name, pos), oder Blizzard hat seine Fenster neu angeordnet (ohne name – auch bei
    ausgeschaltetem Schalter). Zuhörer: Core.Dock mit follow prüft mitlaufende Seitenteile neu (FP-09).
]]

local MF = {}
Core.MoveFrames = MF

MF.FRAMES = { "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsFrame", "TradeSkillFrame",
    "MerchantFrame", "ClassTrainerFrame", "MailFrame", "QuestFrame", "QuestLogFrame", "GossipFrame", "FriendsFrame",
    "DressUpFrame", "TradeFrame", "AuctionHouseFrame", "CollectionsJournal", "AchievementFrame", "CommunitiesFrame",
    "PVEFrame", "InspectFrame", "ItemSocketingFrame", "TaxiFrame", "BankFrame", "GuildBankFrame", "MacroFrame",
    "TabardFrame", "PetStableFrame", "ItemTextFrame", "ProfessionsCustomerOrdersFrame", "WeeklyRewardsFrame" }

local KEY_PREFIX = "blizz:"
local handles, hooked, pending, claims = {}, {}, {}, {}

Core.OwnDefaults("comfort", { moveFrames = false, frameScale = false })   -- Standardwerte bei den Komfort-Schaltern (V-018)

MF.SCALE_MIN, MF.SCALE_MAX, MF.SCALE_STEP = 0.6, 1.5, 0.05

local function DB()
    local db = Core.db
    if type(db) ~= "table" or not Core.OwnSettings("comfort") then return nil end
    return db
end

function MF.Enabled()
    local db = DB()
    return db ~= nil and db.comfort.moveFrames == true and Core.WhoHandles("moveFrames") == nil
end

function MF.ScaleEnabled()
    return MF.Enabled() and Core.db.comfort.frameScale == true
end

local function Skipped(name)
    local db = DB()
    local skip = db and type(db.comfort.moveFramesSkip) == "table" and db.comfort.moveFramesSkip
    return skip and skip[name] == true or false
end
MF.IsSkipped = Skipped

local Positions = Core.Positions   -- eine Stelle für ezCoreDB.positions (Widgets.lua)

local function Blocked(frame)
    return Core.InCombat() and frame.IsProtected and frame:IsProtected()
end

---------------------------------------------------------------------------
-- Größe (W-43)
---------------------------------------------------------------------------

local original = setmetatable({}, { __mode = "k" })   -- Blizzards eigene Größe je Fenster (vor der ersten Änderung)

local function Scales(create)
    local db = DB()
    if not db then return nil end
    if type(db.comfort.frameScales) ~= "table" then
        if not create then return nil end
        db.comfort.frameScales = {}
    end
    return db.comfort.frameScales
end

function MF.ScaleOf(name)
    local scales = Scales(false)
    return scales and Core.Num(scales[name]) or nil
end

local function Clamp(value)
    value = math.floor(value / MF.SCALE_STEP + 0.5) * MF.SCALE_STEP
    return math.max(MF.SCALE_MIN, math.min(MF.SCALE_MAX, value))
end

-- Größe anwenden: gemerkte Größe, wenn erlaubt; sonst Blizzards eigene zurück (nur, wenn ezCore sie geändert hatte).
local function ApplyScale(frame)
    local name = frame:GetName()
    local want = MF.ScaleEnabled() and not claims[name] and not Skipped(name) and MF.ScaleOf(name) or nil
    if not want and original[frame] == nil then return true end
    if Blocked(frame) then
        Core.AfterCombat(function() ApplyScale(frame) end, "ezCore.frameScale:" .. tostring(name), Core.name)
        return false
    end
    if want then
        if original[frame] == nil then original[frame] = Core.Num(frame:GetScale()) or 1 end
        frame:SetScale(want)
    else
        frame:SetScale(original[frame])
        original[frame] = nil
    end
    return true
end
MF.ApplyScale = ApplyScale

function MF.SetScale(name, value)
    local frame = rawget(_G, name)
    local scales = Scales(true)
    if not scales then return nil end
    value = Core.Num(value)
    if value then
        value = Clamp(value)
        local base = type(frame) == "table" and (original[frame] or Core.Num(frame:GetScale())) or 1
        if math.abs(value - base) < MF.SCALE_STEP / 2 then value = nil end   -- wieder Blizzards Größe
    end
    scales[name] = value
    if type(frame) == "table" and frame.SetScale then ApplyScale(frame) end
    Core.Fire("FRAME_MOVED", name, nil)
    return value
end

-- Ein Schritt am Griff (Knopf oder Strg+Mausrad) – nur mit eingeschaltetem Schalter. → neue Größe oder nil
function MF.Step(name, direction)
    if not MF.ScaleEnabled() then return nil end
    local frame = rawget(_G, name)
    local current = MF.ScaleOf(name) or (type(frame) == "table" and Core.Num(frame:GetScale())) or 1
    return MF.SetScale(name, current + (direction > 0 and MF.SCALE_STEP or -MF.SCALE_STEP))
end

function MF.ResetScale(name)
    local scales = Scales(false)
    if not scales then return 0 end
    local n = 0
    for key in pairs(scales) do
        if not name or key == name then
            scales[key] = nil
            n = n + 1
            local frame = rawget(_G, key)
            if type(frame) == "table" and frame.SetScale then ApplyScale(frame) end
        end
    end
    return n
end

-- quiet: keine Nachricht je Fenster (der Aufrufer meldet einmal für alle).
local function Apply(frame, quiet)
    if frame and frame.SetScale and frame.GetName then ApplyScale(frame) end
    if not MF.Enabled() or not frame:IsShown() or claims[frame:GetName()] or Skipped(frame:GetName()) then return end
    local positions = Positions(false)
    local pos = positions and positions[KEY_PREFIX .. frame:GetName()]
    if not pos then return end
    if Blocked(frame) then
        -- nach dem Kampf nachholen (Core.AfterCombat, je Fenster ein Auftrag)
        pending[frame] = true
        Core.AfterCombat(function()
            if pending[frame] then
                pending[frame] = nil
                Apply(frame)
            end
        end, "ezCore.moveFrames:" .. tostring(frame:GetName()), Core.name)
        return
    end
    pending[frame] = nil
    Core.ApplyPosition(frame, pos)
    if not quiet then Core.Fire("FRAME_MOVED", frame:GetName(), pos) end
end

local function ApplyLater(frame)
    C_Timer.After(0, function() Apply(frame) end)
end

function MF.Reset(name)
    local positions = Positions(false)
    if not positions then return 0 end
    local n = 0
    for key in pairs(positions) do
        if key:sub(1, #KEY_PREFIX) == KEY_PREFIX and (not name or key == KEY_PREFIX .. name) then
            positions[key] = nil
            n = n + 1
        end
    end
    return n
end

local function Handle(frame)
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, 0)   -- Schließen und Maximieren bleiben frei
    handle:SetHeight(22)
    handle:SetFrameLevel(frame:GetFrameLevel() + 2)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if Blocked(frame) then return Core.CombatNotice(Core.name, L.MOVEFRAMES_WHAT) end
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:StartMoving()
        handle.moving = true
    end)
    handle:SetScript("OnDragStop", function()
        if not handle.moving then return end
        handle.moving = false
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end   -- ezCore merkt sich die Lage, nicht Blizzards Layout-Cache
        local positions = Positions(true)
        local pos = Core.QuadrantPos(frame)
        if positions then positions[KEY_PREFIX .. frame:GetName()] = pos end
        Core.Fire("FRAME_MOVED", frame:GetName(), pos)
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if MF.ShowMenu(self, frame:GetName()) then return end
        if MF.Reset(frame:GetName()) > 0 then Core.Print(Core.name, L.MOVEFRAMES_RESET_ONE) end
    end)
    -- W-43: Strg+Mausrad ändert die Größe (nur mit dem Schalter „Blizzard-Fenster skalieren“)
    if handle.EnableMouseWheel then handle:EnableMouseWheel(true) end
    handle:SetScript("OnMouseWheel", function(_, delta)
        if not (MF.ScaleEnabled() and IsControlKeyDown and IsControlKeyDown()) then return end
        if Blocked(frame) then return Core.CombatNotice(Core.name, L.MOVEFRAMES_WHAT) end
        MF.Step(frame:GetName(), delta)
    end)
    -- sichtbare Knöpfe „−“ und „+“ (Leitlinie 3), solange die Maus über der Titelleiste ist
    handle.buttons = {}
    for i, dir in ipairs({ -1, 1 }) do
        local b = CreateFrame("Button", nil, handle, "UIPanelButtonTemplate")
        b:SetSize(20, 18)
        b:SetPoint("RIGHT", handle, "RIGHT", (i - 2) * 22, 0)
        b:SetText(dir < 0 and "-" or "+")
        b:SetScript("OnClick", function()
            if Blocked(frame) then return Core.CombatNotice(Core.name, L.MOVEFRAMES_WHAT) end
            MF.Step(frame:GetName(), dir)
        end)
        b:SetScript("OnEnter", Core.TipScript(dir < 0 and L.MOVEFRAMES_SMALLER or L.MOVEFRAMES_BIGGER, L.MOVEFRAMES_SCALE_TIP))
        b:SetScript("OnLeave", function() GameTooltip:Hide(); if not handle:IsMouseOver() then MF.ShowHandleButtons(handle, false) end end)
        b:Hide()
        handle.buttons[i] = b
    end
    -- sichtbarer Knopf für das Menü (Leitlinie 3: Lage und Größe zurücksetzen, „Dieses Fenster nicht verschieben“ –
    -- der Rechtsklick auf die Titelleiste bleibt zusätzlich)
    local more = CreateFrame("Button", nil, handle, "UIPanelButtonTemplate")
    more:SetSize(24, 18)
    more:SetText("...")
    more:SetScript("OnClick", function(self) MF.ShowMenu(self, frame:GetName()) end)
    more:SetScript("OnEnter", Core.TipScript(L.MOVEFRAMES_MENU_BUTTON, L.MOVEFRAMES_MENU_BUTTON_TIP))
    more:SetScript("OnLeave", function() GameTooltip:Hide(); if not handle:IsMouseOver() then MF.ShowHandleButtons(handle, false) end end)
    more:Hide()
    handle.menuButton = more
    handle:SetScript("OnEnter", function(self)
        MF.ShowHandleButtons(self, true)
        if IsShiftKeyDown and IsShiftKeyDown() then Core.ShowTip(self, L.OPT_moveFrames, L.MOVEFRAMES_HANDLE_TIP, "ANCHOR_TOP") end
    end)
    handle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local over = self.menuButton:IsMouseOver()
        for _, b in ipairs(self.buttons) do over = over or b:IsMouseOver() end
        if not over then MF.ShowHandleButtons(self, false) end
    end)
    handle:SetShown(MF.Enabled() and not claims[frame:GetName()] and not Skipped(frame:GetName()))
    return handle
end

function MF.ShowScaleButtons(handle, show)
    for _, b in ipairs(handle and handle.buttons or {}) do b:SetShown(show and true or false) end
end

-- Knöpfe an der Titelleiste beim Überfahren: „...“ (Menü) immer, „-“ und „+“ nur mit „Blizzard-Fenster skalieren“.
function MF.ShowHandleButtons(handle, show)
    if not handle then return end
    local scale = show and MF.ScaleEnabled() or false
    MF.ShowScaleButtons(handle, scale)
    local more = handle.menuButton
    if more then
        more:ClearAllPoints()
        more:SetPoint("RIGHT", handle, "RIGHT", scale and -46 or 0, 0)
        more:SetShown(show and true or false)
    end
end

-- Rechtsklick-Menü am Griff (Blizzards MenuUtil). → true, wenn es offen ist (sonst setzt der Rechtsklick wie früher
-- die Lage zurück).
function MF.ShowMenu(owner, name)
    local menu = rawget(_G, "MenuUtil")
    if type(menu) ~= "table" or type(menu.CreateContextMenu) ~= "function" then return false end
    local ok = pcall(menu.CreateContextMenu, owner, function(_, root)
        root:CreateTitle(L.OPT_moveFrames)
        root:CreateButton(L.MOVEFRAMES_MENU_RESET, function()
            if MF.Reset(name) > 0 then Core.Print(Core.name, L.MOVEFRAMES_RESET_ONE) end
        end)
        if MF.ScaleOf(name) then
            root:CreateButton(L.MOVEFRAMES_MENU_SCALE, function() MF.ResetScale(name) end)
        end
        root:CreateButton(L.MOVEFRAMES_MENU_SKIP, function()
            MF.Skip(name, true)
            Core.Print(Core.name, L.MOVEFRAMES_SKIPPED:format(name))
        end)
    end)
    return ok
end

-- Ein Fenster ausschließen (Griff weg, Lage und Größe gelten nicht mehr) bzw. wieder zulassen.
function MF.Skip(name, yes)
    local db = DB()
    if not db or type(name) ~= "string" then return false end
    db.comfort.moveFramesSkip = type(db.comfort.moveFramesSkip) == "table" and db.comfort.moveFramesSkip or {}
    db.comfort.moveFramesSkip[name] = yes and true or nil
    MF.Refresh()
    local frame = rawget(_G, name)
    if type(frame) == "table" and frame.SetScale then ApplyScale(frame) end
    return true
end

function MF.Skipped()
    local db = DB()
    local list = {}
    for name in pairs(db and type(db.comfort.moveFramesSkip) == "table" and db.comfort.moveFramesSkip or {}) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

local function Hook(name)
    if hooked[name] or Core.InCombat() then return end   -- im Kampf nichts an Blizzards Fenster hängen (danach erneut)
    local frame = rawget(_G, name)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" or not frame.GetName then return end
    -- Fenster des Bearbeitungsmodus nie
    if rawget(frame, "system") ~= nil or rawget(frame, "systemIndex") ~= nil then
        hooked[name] = "editmode"
        return
    end
    hooked[name] = true
    handles[name] = Handle(frame)
    frame:HookScript("OnShow", ApplyLater)
end

-- Griff eines Fensters (nil, solange es nicht eingehängt ist), z. B. für Tests.
function MF.HandleOf(name) return handles[name] end

-- Ein Modul verschiebt das Fenster selbst: kein Griff, keine Lage von ezCore (sonst zwei Griffe, zwei Lagen).
function MF.Claim(name, owner)
    if type(name) ~= "string" or name == "" then return end
    claims[name] = owner or true
    if handles[name] then handles[name]:Hide() end
end

function MF.Release(name)
    if type(name) ~= "string" or not claims[name] then return end
    claims[name] = nil
    if handles[name] then handles[name]:SetShown(MF.Enabled() and not Skipped(name)) end
end

function MF.ClaimedBy(name)
    local owner = claims[name]
    return owner ~= true and owner or (owner and "?") or nil
end

function MF.HookAll()
    for _, name in ipairs(MF.FRAMES) do Hook(name) end
end

function MF.Refresh()
    local on = MF.Enabled()
    if on then MF.HookAll() end
    for name, handle in pairs(handles) do
        handle:SetShown(on and not claims[name] and not Skipped(name))
        local frame = rawget(_G, name)
        if on then Apply(frame) elseif frame then ApplyScale(frame) end   -- aus: Blizzards eigene Größe zurück
    end
end

-- Blizzards Panel-Verwaltung platziert neu: danach die gespeicherte Lage (nur zuhören) und – auch bei
-- ausgeschaltetem Schalter – einmal die Nachricht FRAME_MOVED, damit angedockte Seitenteile ihren Platz neu prüfen.
-- Mehrere Aufrufe in einem Frame ergeben einen Lauf.
local afterQueued = false
local function AfterBlizzard()
    if afterQueued then return end
    if not MF.Enabled() and not Core.Listening("FRAME_MOVED") then return end
    afterQueued = true
    C_Timer.After(0, function()
        afterQueued = false
        if MF.Enabled() then
            for name in pairs(handles) do
                local frame = rawget(_G, name)
                if frame then Apply(frame, true) end
            end
        end
        Core.Fire("FRAME_MOVED")
    end)
end
MF.Rearranged = AfterBlizzard
if type(UpdateUIPanelPositions) == "function" then hooksecurefunc("UpdateUIPanelPositions", AfterBlizzard) end
local delegate = rawget(_G, "FramePositionDelegate")
if type(delegate) == "table" and type(delegate.UpdateUIPanelPositions) == "function" then
    hooksecurefunc(delegate, "UpdateUIPanelPositions", AfterBlizzard)
end

ns.On("PLAYER_LOGIN", function() if MF.Enabled() then MF.HookAll() end end)
ns.On("ADDON_LOADED", function() if MF.Enabled() then MF.HookAll() end end)
-- Forever++ sagt erst nach seinem READY, ob es Fenster verschiebt: Griffe danach neu zeigen bzw. verbergen.
Core.Listen("OTHER_ADDONS_CHANGED", function() MF.Refresh() end, "ezCore")
-- Griffe, die im Kampf nicht angehängt werden durften, nach jedem Kampf nachholen. Wartende Lagen (pending) setzt
-- Core.AfterCombat (siehe Apply).
ns.On("PLAYER_REGEN_ENABLED", function()
    if MF.Enabled() then MF.HookAll() end
end)


-- Schalter und Knopf im Abschnitt „Komfort“ (Comfort.AddSection ruft es auf).
function MF.AddSettings(cat)
    local db = DB()
    if not (cat and db and Settings and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then return end
    local page = Core.ParentPage()
    if not page then return end
    page:OwnCheckbox("comfort", "moveFrames", { feature = "moveFrames", onChange = function() MF.Refresh() end })
    -- W-43 (Frage 28): Größe, ab Werk aus
    -- grau, solange „Blizzard-Fenster verschieben“ aus ist (Einstellungs-Prüfung 19.11.2026, Nr. 46)
    page:OwnCheckbox("comfort", "frameScale", { feature = "moveFrames", parent = "moveFrames",
        onChange = function() MF.Refresh() end })
    page:Button(L.MOVEFRAMES_RESET_LABEL, L.MOVEFRAMES_RESET_BUTTON, function()
        Core.Print(Core.name, L.MOVEFRAMES_RESET_DONE:format(MF.Reset(), MF.ResetScale()))
    end, L.MOVEFRAMES_RESET_TIP)
    -- AI-03 b: ausgeschlossene Fenster wieder zulassen
    page:Button(L.MOVEFRAMES_SKIP_LABEL, L.MOVEFRAMES_SKIP_BUTTON, function()
        local list = MF.Skipped()
        for _, name in ipairs(list) do MF.Skip(name, false) end
        Core.Print(Core.name, L.MOVEFRAMES_SKIP_DONE:format(#list))
    end, L.MOVEFRAMES_SKIP_TIP)
end
