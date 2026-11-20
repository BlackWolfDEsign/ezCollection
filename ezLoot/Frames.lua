local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Plündernfenster (LootFrame) und Würfelfenster (GroupLootFrame1–4) erweitern – kein eigenes Fenster.
    Vorlage ist Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever, Blizzard_UIPanels_Game/Mainline):
      LootFrame: ScrollBox mit LootFrameItemElementTemplate; jedes Element hat einen Platzknopf .Item (37×37)
      GroupLootFrame_SetupItemDisplay(frame): füllt ein Würfelfenster; Symbol in frame.IconFrame (34×34)
    Auf den Platzknopf kommen dieselben Markierungen wie in ezBag, gezeichnet von ezCore.SlotText: Itemlevel oben
    rechts (Farbe der Qualität), „BoE“ unten links. Den grünen Pfeil „besser“ oben links zeichnet ezGear selbst an
    den Knopf (ezCore.API("ezGear").SetUpgradeIcon) – eine Bewertung und ein Pfeil für alle Module, nicht nachgebaut.
    Taint-sicher: nur hooksecurefunc und Blizzards ScrollBox-Rückruf; eigene Texte und Texturen hängen am Knopf,
    gemerkt in einer eigenen Tabelle (nie als Feld in Blizzards Rahmen). Das Plündernfenster gehört zum
    Bearbeitungsmodus: ezLoot hängt nur einen eigenen Knopf daran und verschiebt nichts.
]]

local Frames = {}
ns.Frames = Frames

---------------------------------------------------------------------------
-- Markierungen: Itemlevel und „BoE“ zeichnet ezCore.SlotText (ein Dienst für ezBag und ezLoot)
---------------------------------------------------------------------------

local function SlotText()
    local st = Core.SlotText
    if type(st) == "table" and type(st.Marks) == "function" and type(st.Apply) == "function" then return st end
    return nil
end

-- Liefert marks { ilvl, quality, bind } (nil, wenn es nichts zu zeigen gibt) und equipment = true für Ausrüstung.
-- Die Schalter „Itemlevel“ und „BoE“ von ezLoot gehen als Optionen an ezCore.SlotText.Marks.
function Frames.ItemMarks(link)
    local st = SlotText()
    if not st then return nil, false end
    if ns.IsSecret(link) or type(link) ~= "string" or link == "" then return nil, false end
    return st.Marks(link, { itemLevel = ns.Enabled("itemLevel"), bind = ns.Enabled("bind") })
end

-- Texte auf einen Platzknopf; marks = nil löscht sie (Blizzard verwendet die Elemente der Liste wieder).
function Frames.Apply(button, marks)
    local st = SlotText()
    if st then st.Apply(button, marks) end
end

-- Die Texte eines Knopfs (oder nil), z. B. für Tests.
function Frames.Overlay(button)
    local st = SlotText()
    return st and type(st.Overlay) == "function" and st.Overlay(button) or nil
end

-- Pfeil „besser“: zeichnet ezGear (fehlen Itemdaten, versucht es ezGear selbst erneut). link = nil löscht ihn.
-- Ohne ezGear bleibt er aus. Ein Fehler darin landet im Fehlerprotokoll von ezGear und stoppt ezLoot nicht.
function Frames.SetUpgrade(button, link)
    local gear = Core.API("ezGear")
    if not (gear and type(gear.SetUpgradeIcon) == "function") then return end
    local ok, err = pcall(gear.SetUpgradeIcon, button, link)
    if not ok then Core.Error("ezGear", err, "SetUpgradeIcon (ezLoot)") end
end

-- Alle Markierungen eines Knopfs für einen Gegenstand (nil = Knopf leeren).
function Frames.Decorate(button, link)
    local marks, equipment = Frames.ItemMarks(link)
    Frames.Apply(button, marks)
    Frames.SetUpgrade(button, (equipment and ns.Enabled("upgrade")) and link or nil)
end

---------------------------------------------------------------------------
-- Plündernfenster
---------------------------------------------------------------------------

local function SlotLink(slot)
    if ns.IsSecret(slot) or slot == nil then return nil end
    if GetLootSlotType and Enum and Enum.LootSlotType then
        local kind = GetLootSlotType(slot)
        if ns.IsSecret(kind) or kind ~= Enum.LootSlotType.Item then return nil end
    end
    local link = GetLootSlotLink(slot)
    if ns.IsSecret(link) then return nil end
    return link
end

function Frames.DecorateLootElement(element)
    if type(element) ~= "table" or type(element.Item) ~= "table" or type(element.GetSlotIndex) ~= "function" then return end
    local ok, slot = pcall(element.GetSlotIndex, element)
    local link = ok and SlotLink(slot) or nil
    Frames.Decorate(element.Item, link)
    -- Funkeln an Quest-Gegenständen (von ezQuest) – QuestShine.lua
    if ns.QuestShine then ns.QuestShine(element.Item, ok and slot or nil, link) end
end

local lootOwner = {}
local lootHooked = false
function Frames.HookLootFrame()
    if lootHooked then return true end
    -- Init läuft beim Füllen der Liste und bei LOOT_SLOT_CHANGED; die Elemente übernehmen die Mixin-Funktion
    -- beim Erzeugen, deshalb hier vor dem ersten Plündern einhängen.
    if type(LootFrameItemElementMixin) == "table" and type(LootFrameItemElementMixin.Init) == "function" then
        hooksecurefunc(LootFrameItemElementMixin, "Init", function(element)
            ns.Try("LootFrame", Frames.DecorateLootElement, element)
        end)
        lootHooked = true
    end
    -- Zusätzlich Blizzards Rückruf der Liste: erfasst auch Elemente, die vor ezLoot entstanden sind.
    local scrollBox = LootFrame and LootFrame.ScrollBox
    if scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        local ok = pcall(ScrollUtil.AddInitializedFrameCallback, scrollBox, function(_, element)
            ns.Try("LootFrame", Frames.DecorateLootElement, element)
        end, lootOwner, false)
        lootHooked = lootHooked or ok
    end
    return lootHooked
end

function Frames.RefreshLootFrame()
    local scrollBox = LootFrame and LootFrame:IsShown() and LootFrame.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(function(element) Frames.DecorateLootElement(element) end)
    end
end

---------------------------------------------------------------------------
-- Würfelfenster
---------------------------------------------------------------------------

Frames.ROLL_FRAMES = 4      -- NUM_GROUP_LOOT_FRAMES in Blizzards GroupLootFrame.lua

function Frames.DecorateRollFrame(frame)
    if type(frame) ~= "table" or type(frame.IconFrame) ~= "table" then return end
    local rollID, link = frame.rollID, nil
    if not ns.IsSecret(rollID) and rollID ~= nil and GetLootRollItemLink then
        link = GetLootRollItemLink(rollID)
    end
    Frames.Decorate(frame.IconFrame, link)
end

local rollHooked = false
function Frames.HookRollFrames()
    if rollHooked then return true end
    if type(GroupLootFrame_SetupItemDisplay) ~= "function" then return false end
    rollHooked = true
    hooksecurefunc("GroupLootFrame_SetupItemDisplay", function(frame) ns.Try("GroupLoot", Frames.DecorateRollFrame, frame) end)
    return true
end

function Frames.RefreshRollFrames()
    for index = 1, Frames.ROLL_FRAMES do
        local frame = _G["GroupLootFrame" .. index]
        if frame and frame:IsShown() then Frames.DecorateRollFrame(frame) end
    end
end

function Frames.Refresh()
    Frames.RefreshLootFrame()
    Frames.RefreshRollFrames()
end

---------------------------------------------------------------------------
-- Knopf am Plündernfenster: schneller plündern an/aus (sichtbar, Rechtsklick öffnet die Einstellungen)
---------------------------------------------------------------------------

local FAST_ICON = "Interface\\Icons\\Ability_Rogue_Sprint"

function Frames.UpdateFastButton()
    local button = Frames.fastButton
    if not button then return end
    local active = ns.FastLootActive() or ns.FastLootOther() ~= nil
    button.icon:SetDesaturated(not active)
    button.icon:SetAlpha(active and 1 or 0.6)
end

function Frames.FastButtonTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    Core.TipTitle(GameTooltip, L.BUTTON_FAST_TITLE)
    local state
    local other = ns.FastLootOther()
    if other and ns.Enabled("fastLoot") then
        state = L.BUTTON_FAST_OTHER:format(other)
    elseif ns.Enabled("fastLoot") then
        state = ns.AutoLootOn() and L.BUTTON_FAST_ON or L.BUTTON_FAST_ON_NO_AUTO
    else
        state = L.BUTTON_FAST_OFF
    end
    Core.TipText(GameTooltip, state)
    Core.TipClick(GameTooltip, L.BUTTON_FAST_LEFT)
    Core.TipClick(GameTooltip, L.BUTTON_FAST_RIGHT)
    Core.TipClick(GameTooltip, L.BUTTON_FAST_CMD:format(ns.SlashCmd()))
    GameTooltip:Show()
end

function Frames.CreateFastButton()
    if Frames.fastButton or not LootFrame then return Frames.fastButton end
    local button = CreateFrame("Button", nil, LootFrame)
    button:SetSize(16, 16)
    button:SetPoint("TOPLEFT", LootFrame, "TOPLEFT", 7, -3)
    button:SetFrameLevel((LootFrame:GetFrameLevel() or 1) + 10)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    Core.SetIcon(button.icon, nil, FAST_ICON)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.OpenSettings()
        else
            Core.HandleToggle(ns, "schnell")
        end
        Frames.UpdateFastButton()
        if GameTooltip:IsOwned(self) then Frames.FastButtonTooltip(self) end
    end)
    button:SetScript("OnEnter", function(self) Frames.FastButtonTooltip(self) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Frames.fastButton = button
    Frames.UpdateFastButton()
    return button
end

-- Zweiter Knopf daneben: Beute-Verlauf öffnen (History.lua).
local HISTORY_ICON = "Interface\\Icons\\INV_Misc_Note_01"

function Frames.CreateHistoryButton()
    if Frames.historyButton or not LootFrame then return Frames.historyButton end
    local button = CreateFrame("Button", nil, LootFrame)
    button:SetSize(16, 16)
    button:SetPoint("TOPLEFT", LootFrame, "TOPLEFT", 26, -3)
    button:SetFrameLevel((LootFrame:GetFrameLevel() or 1) + 10)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    Core.SetIcon(button.icon, nil, HISTORY_ICON)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function() ns.LootHistory.Toggle() end)
    -- der Text nennt den geltenden Befehl – erst beim Zeigen (der Kurzbefehl steht erst nach dem Einloggen fest)
    button:SetScript("OnEnter", function(self) Core.ShowTip(self, L.HISTORY_TITLE, L.BUTTON_HISTORY_TIP:format(ns.SlashCmd())) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Frames.historyButton = button
    return button
end

---------------------------------------------------------------------------
-- Blizzards Würfelergebnisse (GroupLootHistoryFrame): auf Forever öffnet es sich nie von selbst
---------------------------------------------------------------------------

-- Über ezCore (Core.TogglePanel „loothistory“): true, sonst false und der Grund – "combat" (im Kampf öffnet
-- ezCore kein Blizzard-Fenster und sagt das selbst), "missing" (der Client hat das Fenster nicht), "error".
function ns.ToggleRollHistory()
    return Core.TogglePanel("loothistory")
end

-- Der Weg aller Knöpfe und Befehle: umschalten und sagen, wenn es das Fenster nicht gibt. Im Kampf kommt der
-- Hinweis von ezCore, deshalb hier kein zweiter.
function ns.OpenRollHistory()
    local ok, reason = ns.ToggleRollHistory()
    if not ok and reason ~= "combat" then ns.Print(L.ROLLS_MISSING) end
    -- Blizzards Fenster kann erst jetzt entstanden sein: Seitenreiter und Andocken des Beute-Verlaufs einhängen.
    if ok and ns.LootHistory and ns.LootHistory.SetupDock then ns.LootHistory.SetupDock() end
    return ok, reason
end

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

local refreshSoon = ns.Throttle(function() Frames.Refresh() end, 0.1)

ns.OnReady(function()
    Frames.HookLootFrame()
    Frames.HookRollFrames()
    Frames.CreateFastButton()
    Frames.CreateHistoryButton()
end)

-- Gegenstand war noch nicht im Zwischenspeicher: sobald er da ist, Markierungen nachtragen.
ns.On("GET_ITEM_INFO_RECEIVED", function() refreshSoon() end)
-- ezGear meldet geänderte Gewichtung oder Ausrüstung: „besser“ neu fragen.
Core.Listen("GEAR_SCORES_CHANGED", function() refreshSoon() end, ADDON)

ns.OnSettingChanged(function(key)
    if key == "fastLoot" then
        Frames.UpdateFastButton()
    else
        Frames.Refresh()
    end
end)
