local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Ausrüstungssets über Blizzards eigenen Ausrüstungsmanager: Forever hat ihn
    (PaperDollFrame.EquipmentManagerPane, C_EquipmentSet; geprüft in Gethe/wow-ui-source, Zweig forever, Camelot).
    ezGear baut keine eigene Set-Verwaltung, sondern einen sichtbaren Knopf „Sets“ links neben der Waffenhand des
    Charakterfensters. Sein Menü: ein Klick legt ein Set an, „Sets bearbeiten“ öffnet Blizzards Reiter, dazu die
    Gewichtung und das automatische Umziehen. Anlegen nur außerhalb des Kampfes (sonst gleich danach).
    Darüber der Knopf „Chat“: angelegte Ausrüstung als Links in den eigenen Chat (unten in dieser Datei).
]]

local Sets = {}
ns.Sets = Sets

local api = C_EquipmentSet

function Sets.Available()
    return api ~= nil and type(api.GetEquipmentSetIDs) == "function"
end

-- Sets.List() → { { id, name, icon, equipped }, … } nach Name
function Sets.List()
    local list = {}
    if not Sets.Available() then return list end
    local ids = ns.Call(api.GetEquipmentSetIDs)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local name, icon, _, equipped = ns.Call(api.GetEquipmentSetInfo, id)
        if type(name) == "string" then
            list[#list + 1] = { id = id, name = name, icon = icon, equipped = equipped == true }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Sets.IDByName(name) → ID des Sets dieses Namens (ohne Groß-/Kleinschreibung) oder nil. Ein gesperrter Name wird
-- weder verglichen noch an den Client gereicht (Leitlinie 6: erst prüfen, dann vergleichen).
function Sets.IDByName(name)
    if ns.IsSecret(name) then return nil end
    if not (Sets.Available() and type(name) == "string" and name ~= "") then return nil end
    local id = ns.Plain(ns.Call(api.GetEquipmentSetID, name))
    if id ~= nil then return id end
    local wanted = name:lower()
    for _, set in ipairs(Sets.List()) do
        if set.name:lower() == wanted then return set.id end
    end
    return nil
end

-- Sets.Items(id) → { [Inventarplatz] = itemID } der Plätze, die das Set belegt (ohne ignorierte und leere Plätze);
-- nil ohne Ausrüstungsmanager oder wenn der Client zum Set nichts liefert. Nur lesen.
function Sets.Items(id)
    if id == nil or not Sets.Available() then return nil end
    local items = ns.Call(api.GetItemIDs, id)
    if type(items) ~= "table" then return nil end
    local ignored = ns.Call(api.GetIgnoredSlots, id)
    local out = {}
    for slot = 1, 19 do
        local itemID = ns.Plain(items[slot])
        if type(itemID) == "number" and itemID > 0 and not (type(ignored) == "table" and ignored[slot]) then
            out[slot] = itemID
        end
    end
    return out
end

-- Set anlegen; im Kampf gleich danach (Blizzard sperrt das Ausrüsten im Kampf).
-- → true (angelegt) | true, "combat" (vorgemerkt, kommt gleich nach dem Kampf) | false (kein Set)
function Sets.Equip(id, name)
    if id == nil then return false end
    local now = ns.AfterCombat(function() ns.Call(api.UseEquipmentSet, id) end, "set")
    if not now then
        Core.CombatNotice(ns, L.SETS_WHAT:format(name or "?"), "later")   -- ezCores Satz (T18-1)
        return true, "combat"
    end
    return true
end

-- → true | true, "combat" | false, "unknown" (kein Set dieses Namens; auch ohne Ausrüstungsmanager)
function ns.EquipSetByName(name)
    local id = Sets.IDByName(name)
    if not id then
        -- ein gesperrter Name kommt auch nicht in die Meldung
        ns.Print(L.SETS_UNKNOWN:format(not ns.IsSecret(name) and type(name) == "string" and name or ""))
        return false, "unknown"
    end
    return Sets.Equip(id, name)
end

-- Welcher Seitenreiter des Charakterfensters ist der Ausrüstungsmanager? Die Reihenfolge ist je Client anders
-- (Forever, Blizzard_UIPanels_Game/Camelot: Werte, Ausrüstungsmanager, Titel, Begleiter; Retail: Werte, Titel,
-- Ausrüstungsmanager) – deshalb keine feste Zahl, sondern der Reiter, hinter dem Blizzards Rahmen
-- PaperDollFrame.EquipmentManagerPane steckt (GetPaperDollSideBarFrame), sonst der Eintrag in PAPERDOLL_SIDEBARS.
-- Nur lesen (Leitlinie 5). → Nummer oder nil (nicht gefunden: dann bleibt der Reiter, wie er ist)
function Sets.ManagerSidebar()
    local bars = _G.PAPERDOLL_SIDEBARS
    local count = type(bars) == "table" and #bars or 0
    if count == 0 then return nil end
    local doll = _G.PaperDollFrame
    local pane = (type(doll) == "table" and doll.EquipmentManagerPane) or _G.PaperDollEquipmentManagerPane
    local frameOf = _G.GetPaperDollSideBarFrame
    if pane and type(frameOf) == "function" then
        for i = 1, count do
            if ns.Call(frameOf, i) == pane then return i end
        end
    end
    local constant = _G.PAPERDOLL_SIDEBARTAB_EQUIPMENTMANAGER
    for i = 1, count do
        local bar = bars[i]
        if constant ~= nil and bar == constant then return i end
        if type(bar) == "table" then
            local frame = bar.frame
            if pane and frame == pane then return i end
            if type(frame) == "string" and frame:find("EquipmentManager", 1, true) then return i end
        end
    end
    return nil
end

-- Forevers Charakterfenster hat einen einklappbaren rechten Teil (Pfeil-Knopf, CharacterFrame:IsRightPaneCollapsed).
-- Eingeklappt zeigt Blizzard keinen Seitenreiter; PaperDollFrame_SetSidebar kennt das nicht und würde die Seite
-- ohne Hintergrund neben das schmale Fenster zeichnen. Deshalb erst über Blizzards eigenen Weg ausklappen
-- (CharacterFrame:SetRightPaneCollapsed(false), das tut auch der Pfeil-Knopf). → true, wenn der rechte Teil
-- offen ist (oder der Client kein Einklappen kennt), false, wenn er zu bleibt
function Sets.ExpandRightPane()
    local frame = _G.CharacterFrame
    if type(frame) ~= "table" or type(frame.IsRightPaneCollapsed) ~= "function" then return true end
    if ns.Call(frame.IsRightPaneCollapsed, frame) ~= true then return true end
    if type(frame.SetRightPaneCollapsed) ~= "function" then return false end
    if ns.InCombat() then return false end
    ns.Call(frame.SetRightPaneCollapsed, frame, false)
    return ns.Call(frame.IsRightPaneCollapsed, frame) ~= true
end

-- Blizzards Reiter „Ausrüstungsmanager“ im Charakterfenster öffnen – über ezCore (Core.OpenPanel): nur außerhalb
-- des Kampfes, im Kampf zeigt ezCore den Hinweis. → true | false, "combat"
function Sets.OpenManager()
    local ok, reason = Core.OpenPanel("character", "PaperDollFrame")
    if not ok and reason == "combat" then return false, reason end
    local index = Sets.ManagerSidebar()
    if index and PaperDollFrame and type(PaperDollFrame_SetSidebar) == "function" and Sets.ExpandRightPane() then
        ns.Call(PaperDollFrame_SetSidebar, PaperDollFrame, index)
    end
    return true
end

local function IconText(icon, text)
    if icon then return ("|T%s:16:16:0:0|t %s"):format(tostring(icon), text) end
    return text
end

-- Einträge „Sets“ in ein Menü (Knopf am Charakterfenster, Slash-Befehl)
function ns.AddSetsMenu(root)
    local Menu = Core.Menu
    local list = Sets.List()
    if #list == 0 then
        Menu.Title(root, L.SETS_NONE)
    end
    for _, set in ipairs(list) do
        ns.MenuTip(Menu.Radio(root, IconText(set.icon, set.name), function() return set.equipped and set.id or nil end,
            function() Sets.Equip(set.id, set.name) end, set.id), set.name, L.MTIP_SET)
    end
    ns.MenuTip(Menu.Button(root, L.SETS_EDIT, function() Sets.OpenManager() end), L.SETS_EDIT, L.MTIP_SETS_EDIT)
end

function ns.OpenSetsMenu(owner)
    local Menu = Core.Menu
    return Menu.Open(owner or UIParent, function(root)
        Menu.Title(root, L.SETS_TITLE)
        ns.AddSetsMenu(root)
        Menu.Divider(root)
        Menu.Title(root, L.WEIGHTS_TITLE)
        ns.AddWeightMenu(root)
        if ns.AddSwapMenu then
            Menu.Divider(root)
            Menu.Title(root, L.SWAP_TITLE)
            ns.AddSwapMenu(root)
        end
        Menu.Divider(root)
        if ns.AddProfileMenu then ns.AddProfileMenu(root) end
        Menu.Settings(root, ns)   -- „Einstellungen …“ mit Zahnrad und Tooltip von ezCore (Gesamtreview T18-8)
    end)
end

---------------------------------------------------------------------------
-- Knopf am Charakterfenster
---------------------------------------------------------------------------

local button

function Sets.Button() return button end

local function UpdateButton()
    if button then button:SetShown(ns.Enabled("setsButton")) end
end

local function CreateButton()
    local parent = PaperDollItemsFrame or PaperDollFrame
    local anchor = CharacterMainHandSlot
    if button or not parent then return end
    button = CreateFrame("Button", "ezGearSetsButton", parent, "UIPanelButtonTemplate")
    button:SetSize(58, 22)
    button:SetText(L.SETS_BUTTON)
    if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, 12)
    end
    button:SetScript("OnClick", function(self) ns.OpenSetsMenu(self) end)
    button:SetScript("OnEnter", Core.TipScript(L.SETS_BUTTON_TIP_TITLE, L.SETS_BUTTON_TIP))
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UpdateButton()
end

---------------------------------------------------------------------------
-- Knopf „Chat“ am Charakterfenster: angelegte Ausrüstung als Links in den eigenen Chat (ns.PrintEquipped,
-- Character.lua). Sitzt über dem Knopf „Sets“; ist „Sets“ abgeschaltet, an dessen Stelle links neben der Waffenhand.
---------------------------------------------------------------------------

local chatButton

function Sets.ChatButton() return chatButton end

local function UpdateChatButton()
    if not chatButton then return end
    chatButton:SetShown(ns.Enabled("chatButton"))
    chatButton:ClearAllPoints()
    if button and ns.Enabled("setsButton") then
        chatButton:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 2)
    elseif CharacterMainHandSlot then
        chatButton:SetPoint("RIGHT", CharacterMainHandSlot, "LEFT", -8, 0)
    else
        chatButton:SetPoint("BOTTOMLEFT", chatButton:GetParent(), "BOTTOMLEFT", 12, 36)
    end
end

local function CreateChatButton()
    local parent = PaperDollItemsFrame or PaperDollFrame
    if chatButton or not parent then return end
    chatButton = CreateFrame("Button", "ezGearChatButton", parent, "UIPanelButtonTemplate")
    chatButton:SetSize(58, 22)
    chatButton:SetText(L.GEARCHAT_BUTTON)
    chatButton:SetScript("OnClick", function() ns.Try("GearChat", ns.PrintEquipped) end)
    chatButton:SetScript("OnEnter", Core.TipScript(L.GEARCHAT_TIP_TITLE, L.GEARCHAT_TIP))
    chatButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UpdateChatButton()
end

ns.OnReady(function()
    ns.Try("SetsButton", CreateButton)
    ns.Try("ChatButton", CreateChatButton)
    ns.OnSettingChanged(function(key)
        if key == "setsButton" then UpdateButton() end
        if key == "setsButton" or key == "chatButton" then UpdateChatButton() end
    end)
end)
