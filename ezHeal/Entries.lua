local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Weitere sichtbare Einstiege zu Blizzards Fenster „Klick-Zauber“ (HL-07, Leitlinie 3). Jeder Einstieg ist ein
    Kind eines Blizzard-Fensters (kein Rahmen unter UIParent, Leitlinie 1), wandert und schließt mit ihm, hat einen
    Tooltip und lässt sich auf der Einstellungsseite („Allgemein“) abschalten. Angelegt wird nur außerhalb des
    Kampfes (sonst gleich nach dem Kampf); von Blizzards Fenstern wird nur gelesen. Ein Klick ruft ns.OpenBlizzard()
    (Core.ClickBindings.Open). Lage nach Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever):

      raid       Schlachtzug-Liste (RaidFrame, Blizzard_RaidFrame/Mainline/RaidFrame.xml; im Kontakte-Fenster
                 FriendsFrame): Seitenreiter rechts im Stapel des Kontakte-Fensters (Core.SideTabs) mit der Zahl 30 –
                 unter ezChats Reiter (10); der Reiter ist Kind von RaidFrame und zeigt sich nur auf dem Reiter
                 „Schlachtzug“.
      group      Gruppen- und Raidverwaltung (CompactRaidFrameManager, Blizzard_CompactRaidFrames/Mainline/
                 Blizzard_CompactRaidFrameManager.xml, 222 breit): kleiner Knopf 20 × 20 im aufgeklappten Teil
                 (displayFrame) links neben der Mitgliederzahl (memberCountLabel, TOPRIGHT −30/−15) – rechts von
                 der Beschriftung „Schlachtzug“/„Gruppe“ (TOPLEFT 10/−15) und vom Auswahlfeld Gruppe/Schlachtzug
                 (TOPLEFT 10/−10, 100 breit). Eingeklappt ist displayFrame versteckt, der Knopf mit ihm.
      spellbook  Zauberbuch (PlayerSpellsFrame.SpellBookFrame): Seitenreiter rechts am festen Platz −202 – unter den
                 vereinbarten Reitern ezMerchant −70, ezMacro −114, ezCombat −158 (Zahl 40 im Zauberbuch, Register
                 Core.SpellbookView.ClaimTab: ist der Platz belegt, rückt der Reiter darunter).
      macro      Makrofenster (MacroFrame, Blizzard_MacroUI.xml, 338 × 424, ButtonFrameTemplate): kleiner Knopf 18 × 18
                 in der Titelleiste links neben dem Schließen-Knopf. Unten ist kein Platz (Löschen 4…84, ezMacros
                 Knopf 86…166, Neu ab 176), rechts dockt ezMacros Seitenfenster an.
]]

local E = {}
ns.Entries = E

E.ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"
E.KEY = "ezHeal.clickbindings"
E.RAID_ORDER = 30
E.SPELLBOOK_Y = -202          -- früherer fester Platz im Zauberbuch (−70 − 3 × 44), nur noch Auskunft (E.SpellbookY)
E.SPELLBOOK_ORDER = 40        -- Zahl im Seitenreiter-Stapel des Zauberbuchs nach ezMerchant 10, ezMacro 20, ezCombat 30
E.GROUP_SIZE, E.MACRO_SIZE = 20, 18
E.buttons = {}                -- [key] = Knopf bzw. Reiter

-- Je Einstieg: Einstellung, Blizzards Addon, Elternrahmen (nur gelesen) und Bau
E.LIST = {
    { key = "raid", setting = "entryRaid", addon = "Blizzard_RaidFrame",
        parent = function() return rawget(_G, "RaidFrame") end },
    { key = "group", setting = "entryGroup", addon = "Blizzard_CompactRaidFrames",
        parent = function()
            local manager = rawget(_G, "CompactRaidFrameManager")
            return type(manager) == "table" and manager.displayFrame or nil
        end },
    { key = "spellbook", setting = "entrySpellbook", addon = "Blizzard_PlayerSpells",
        parent = function()
            local frame = rawget(_G, "PlayerSpellsFrame")
            return type(frame) == "table" and frame.SpellBookFrame or nil
        end },
    { key = "macro", setting = "entryMacro", addon = "Blizzard_MacroUI",
        parent = function() return rawget(_G, "MacroFrame") end },
}

local function Find(key)
    for _, entry in ipairs(E.LIST) do
        if entry.key == key then return entry end
    end
    return nil
end

local function ShowTip(self)
    Core.ShowTip(self, L.ENTRY_TITLE, L.ENTRY_TIP)
end

local function Open() ns.OpenBlizzard() end

-- Seitenreiter wie in Blizzards Zauberbuch (ezCore); opts für den Stapel des Fensters oder nil (Lage setzt E)
local function SideTab(parent, opts)
    local tab = Core.CreateSideTab(parent, opts)
    local icon = tab.Icon   -- aus Blizzards RightSideTabTemplate (ezCore baut es nach, wenn die Vorlage fehlt)
    if type(icon) == "table" and icon.SetTexture then icon:SetTexture(E.ICON) end
    tab:SetScript("OnClick", Core.SideTabClick(Open))
    tab:SetScript("OnEnter", ShowTip)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

-- Kleiner Knopf mit Symbol (Gruppenverwaltung, Titelleiste des Makrofensters)
local function IconButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexture(E.ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", Open)
    button:SetScript("OnEnter", ShowTip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- Lage je Einstieg (nur an Blizzards Teilen verankert, nur gelesen)
function E.AnchorGroup(button, display)
    button:ClearAllPoints()
    local count = display.memberCountLabel
    if type(count) == "table" then
        button:SetPoint("RIGHT", count, "LEFT", -6, 0)
    else
        button:SetPoint("TOPRIGHT", display, "TOPRIGHT", -74, -10)
    end
end

function E.AnchorMacro(button, frame)
    button:ClearAllPoints()
    local close = frame.CloseButton or rawget(_G, "MacroFrameCloseButton")
    if type(close) == "table" then
        button:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -3)
    end
end

function E.SpellbookY()
    local view = Core.SpellbookView
    if view and view.ClaimTab then return view.ClaimTab(E.KEY, E.SPELLBOOK_Y) end
    return E.SPELLBOOK_Y
end

local BUILD = {
    raid = function(parent)
        local friends = rawget(_G, "FriendsFrame")
        return SideTab(parent, { key = E.KEY, order = E.RAID_ORDER, owner = "ezHeal",
            anchor = type(friends) == "table" and friends or parent })
    end,
    group = function(parent)
        local button = IconButton(parent, E.GROUP_SIZE)
        E.AnchorGroup(button, parent)
        return button
    end,
    spellbook = function(parent)
        -- im Seitenreiter-Stapel des Zauberbuchs (Gesamtreview 18.11.2026, T16-4; vorher fest y −202)
        E.SpellbookY()   -- Platz im Register vormerken (Auskunft SpellbookView.TabOwner)
        return SideTab(parent, { key = E.KEY, order = E.SPELLBOOK_ORDER, owner = "ezHeal",
            anchor = rawget(_G, "PlayerSpellsFrame") or parent })
    end,
    macro = function(parent)
        local button = IconButton(parent, E.MACRO_SIZE)
        E.AnchorMacro(button, parent)
        return button
    end,
}

-- Einstieg anlegen (einmal) und nach der Einstellung zeigen. Im Kampf: gleich nach dem Kampf. → Knopf oder nil
function E.Create(key)
    local entry = Find(key)
    if not entry then return nil end
    if E.buttons[key] then return E.Update(key) end
    if not ns.Enabled(entry.setting) then return nil end
    local parent = entry.parent()
    if type(parent) ~= "table" then return nil end
    if ns.InCombat() then
        ns.AfterCombat(function() E.Create(key) end, "entry:" .. key)
        return nil
    end
    local button = BUILD[key](parent)
    E.buttons[key] = button
    return button
end

-- Schalter anwenden: an → anlegen bzw. zeigen, aus → verstecken (eigene, ungeschützte Knöpfe)
function E.Update(key)
    local entry = Find(key)
    local button = entry and E.buttons[key]
    if not button then
        if entry and ns.Enabled(entry.setting) then return E.Create(key) end
        return nil
    end
    button:SetShown(ns.Enabled(entry.setting))
    return button
end

function E.Shown(key)
    local button = E.buttons[key]
    return button ~= nil and button:IsShown() and true or false
end

-- Beim Laden: Gibt es Blizzards Fenster schon (Teil der Grundoberfläche), gleich anlegen; sonst, sobald sein Addon
-- lädt (Zauberbuch, Makrofenster und Raidverwaltung lädt Blizzard erst bei Bedarf).
ns.OnReady(function()
    for _, entry in ipairs(E.LIST) do
        local key = entry.key
        local function Build() ns.Try("Einstieg " .. key, function() E.Create(key) end) end
        if type(entry.parent()) == "table" then Build() else ns.WhenAddOnLoaded(entry.addon, Build) end
    end
end)

ns.OnSettingChanged(function(setting)
    for _, entry in ipairs(E.LIST) do
        if entry.setting == setting then E.Update(entry.key) end
    end
end)
