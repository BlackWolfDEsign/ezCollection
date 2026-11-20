local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Seitenteil „Ausrüstungs-Check“ am Reiter „Schlachtzug“ (Gesamtreview 18.11.2026, I3; Leitlinie 1: kein eigenes
    Fenster, sondern ezCores Baustein „Seitenteil mit Pfeil“ – Core.NewSidePanel – als Kind von Blizzards RaidFrame;
    es erscheint, verschwindet und wandert mit dem Reiter). Die Bewertung steht in GroupCheck.lua.

    Lage (Blizzards Forever-Quelle, Gethe/wow-ui-source, Zweig forever): RaidFrame füllt sein Elternfenster
    (Blizzard_RaidFrame/Mainline/RaidFrame.lua, ClaimRaidFrame: TOPLEFT/BOTTOMRIGHT 0/0 – im Kontakte-Fenster also so
    groß wie FriendsFrame). Rechts davon liegen ezCores Seitenreiter-Stapel (ezChat 10, ezHeal 30; Core.SideTabs) –
    darum dockt das Feld mit GAP Abstand an, wie ezChats angedocktes Gesprächsfenster. Blizzards Schlachtzugsinfo
    (RaidInfoFrame, RaidFrame.xml: TOPLEFT an RaidFrame TOPRIGHT) liegt an derselben Stelle: Es gilt, was zuletzt
    geöffnet wurde – geht die Schlachtzugsinfo auf, tritt das Feld zurück (und kommt danach wieder); öffnet der
    Spieler das Feld, schließt ezGear die Schlachtzugsinfo (nur außerhalb des Kampfes; nur Hide, nichts in Blizzards
    Tabellen – wie ezCores Panels.lua, das sie zeigt).

    Sichtbar (Leitlinie 3): Pfeil am Reiter (auf/zu), Knopf „Gruppe prüfen“ bzw. „Abbrechen“, je Mitglied eine Zeile
    mit Tooltip. Schalter groupCheck (Einstellungen » ezGear » „Ausrüstungs-Check der Gruppe“). Der Abruf läuft nur
    nach dem Klick und bricht ab, wenn das Feld zugeht, der Reiter schließt oder ein Kampf beginnt.
]]

local Panel = {}
ns.GroupPanel = Panel

Panel.WIDTH = 260
Panel.GAP = 36               -- Platz für die Seitenreiter rechts am Kontakte-Fenster (wie ezChats DOCK_GAP)
Panel.ROW_H = 16
Panel.TOP = 92               -- Abstand der Liste von oben (Titel, Knopf, Stand, Spaltenköpfe)
Panel.NOTE_H = 44            -- Platz unten für den Hinweis „liegt über dem Fenster“ (mode "overlap")
Panel.COL = { name = 10, level = 132, enchant = 172, empty = 210 }

local panel, rows, content, scroll = nil, {}, nil, nil
local hiddenByInfo = false   -- das Feld ist offen, steht aber hinter Blizzards Schlachtzugsinfo zurück

local function RaidFrame() return rawget(_G, "RaidFrame") end
local function RaidInfo() return rawget(_G, "RaidInfoFrame") end
function Panel.Frame() return panel end

local function Color(text, role) Core.Style.SetTextColor(text, role) end

local function Font(parent, role, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY", Core.Style.FONT[role] or Core.Style.FONT.text)
end

-- Namen der Plätze („Umhang, Brust“) aus ezCores Platzliste (Blizzards Namen)
local function SlotNames(list)
    local names = {}
    local slots = Core.EquipSlots
    for _, slot in ipairs(list or {}) do
        names[#names + 1] = (slots and slots.Label and slots.Label(slot)) or tostring(slot)
    end
    return table.concat(names, ", ")
end
Panel.SlotNames = SlotNames

---------------------------------------------------------------------------
-- Tooltip einer Zeile
---------------------------------------------------------------------------

local function AddLine(text, role)
    local r, g, b = Core.Style.Color(role or "highlight")
    GameTooltip:AddLine(text, r, g, b, true)
end

function Panel.RowTip(row)
    local data = row and row.info
    if not data then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(Core.ClassText(data.name or "?", data.class))
    local result = data.data
    if result then
        if result.ilvl then AddLine(L.GC_TIP_LEVEL:format(result.ilvl), "normal") end
        if #result.missing > 0 then
            AddLine(L.GC_TIP_MISSING:format(SlotNames(result.missing)), "bad")
        else
            AddLine(L.GC_TIP_NO_MISSING, "good")
        end
        if #result.empty > 0 then
            AddLine(L.GC_TIP_EMPTY:format(SlotNames(result.empty)), "bad")
        else
            AddLine(L.GC_TIP_NO_EMPTY, "good")
        end
        if result.unknown > 0 then AddLine(L.GC_TIP_UNKNOWN:format(result.unknown), "warn") end
    end
    if data.self then
        AddLine(L.GC_TIP_SELF, "gray")
    elseif result and data.age then
        AddLine(L.GC_TIP_AGE:format(Core.Duration(data.age)), "gray")
    end
    if data.state ~= "done" and data.state ~= "none" then
        AddLine(L["GC_STATE_" .. data.state] or data.state, "warn")
        if data.state == "range" then AddLine(L.GC_TIP_RANGE, "gray") end
    end
    if data.state == "none" then AddLine(L.GC_TIP_NONE, "gray") end
    AddLine(L.GC_TIP_SOURCE, "gray")
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Zeilen
---------------------------------------------------------------------------

local function NewRow(i)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(Panel.ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * Panel.ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Name = Font(row, "text")
    row.Name:SetPoint("LEFT", row, "LEFT", Panel.COL.name - 6, 0)
    row.Name:SetWidth(Panel.COL.level - Panel.COL.name - 6)
    row.Name:SetJustifyH("LEFT")
    if row.Name.SetWordWrap then row.Name:SetWordWrap(false) end
    row.Level = Font(row, "text")
    row.Level:SetPoint("LEFT", row, "LEFT", Panel.COL.level - 6, 0)
    row.Level:SetWidth(36)
    row.Level:SetJustifyH("RIGHT")
    row.Enchant = Font(row, "text")
    row.Enchant:SetPoint("LEFT", row, "LEFT", Panel.COL.enchant - 6, 0)
    row.Enchant:SetWidth(32)
    row.Enchant:SetJustifyH("RIGHT")
    row.Empty = Font(row, "text")
    row.Empty:SetPoint("LEFT", row, "LEFT", Panel.COL.empty - 6, 0)
    row.Empty:SetWidth(28)
    row.Empty:SetJustifyH("RIGHT")
    -- Stand statt der Zahlen („nicht in Reichweite“), über den drei Spalten
    row.State = Font(row, "hint")
    row.State:SetPoint("LEFT", row, "LEFT", Panel.COL.level - 6, 0)
    row.State:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.State:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self) ns.Try("GroupTip", Panel.RowTip, self) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

-- Zahl einer Spalte; unknown > 0 (Plätze noch nicht lesbar) und nichts gefunden: „?“ statt einer grünen 0
-- (Gegenprüfung I3)
local function Count(fs, n, unknown)
    if n == 0 and (unknown or 0) > 0 then
        fs:SetText("?")
        Color(fs, "warn")
        return
    end
    fs:SetText(tostring(n))
    Color(fs, n > 0 and "bad" or "good")
end

function Panel.FillRow(row, info)
    row.info = info
    row.Name:SetText(Core.ClassText(info.name or "?", info.class))
    local result = info.data
    local showState = info.state ~= "done"
    if result then
        row.Level:SetText(result.ilvl and tostring(result.ilvl) or "?")
        Color(row.Level, "highlight")
        -- Verzauberung: ein unbekannter Platz kann eine fehlende verbergen; leer ist ein unbekannter Platz nie
        Count(row.Enchant, #result.missing, result.unknown)
        Count(row.Empty, #result.empty)
    else
        row.Level:SetText("")
        row.Enchant:SetText("")
        row.Empty:SetText("")
    end
    -- Stand nur, wenn keine Zahlen da sind (sonst sagt ihn der Tooltip)
    if showState and not result then
        row.State:SetText(L["GC_STATE_" .. info.state] or "")
    else
        row.State:SetText("")
    end
    row:SetAlpha(showState and result and 0.6 or 1)
    row:Show()
end

---------------------------------------------------------------------------
-- Stand und Knopf
---------------------------------------------------------------------------

function Panel.StatusText()
    local check = ns.GroupCheck
    if check.Running() then
        -- Ein anderes Addon betrachtet gerade: sagen, warum nichts vorangeht (Leitlinie 9 und 11)
        if check.Waiting() == "foreign" then return L.GC_WAIT_FOREIGN end
        local done, total = check.Progress()
        return L.GC_PROGRESS:format(math.min(done + 1, total), total, check.STEP)
    end
    local reason = check.LastReason()
    if reason == "alone" then return L.GC_DONE_NONE end
    if reason == "done" then
        local done, total = check.Progress()
        return total > 0 and L.GC_DONE:format(done, total) or L.GC_DONE_NONE
    end
    if reason and L["GC_STOP_" .. reason] then return L["GC_STOP_" .. reason] end
    return L.GC_IDLE
end

function Panel.Refresh()
    if not panel then return end
    local check = ns.GroupCheck
    local running = check.Running()
    panel.Start:SetText(running and Panel.CancelText() or L.GC_START)
    panel.Status:SetText(Panel.StatusText())
    -- Kein Platz neben dem Kontakte-Fenster: das Feld liegt darüber – Hinweis wie in ezAuction und ezCraft
    -- (Vertrag von Core.NewSidePanel: bei mode "overlap" zeigt das Modul seinen Hinweis; Gegenprüfung I3)
    local overlap = panel.mode == "overlap"
    panel.Note:SetText(overlap and L.GC_OVERLAP or "")
    panel.Note:SetShown(overlap)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, overlap and Panel.NOTE_H or 8)
    if not panel:IsShown() then return end
    local list = check.Rows()
    for i, info in ipairs(list) do
        Panel.FillRow(rows[i] or NewRow(i), info)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(#list * Panel.ROW_H, 1))
end

local function StartTip(self)
    if ns.GroupCheck.Running() then
        Core.ShowTip(self, Panel.CancelText(), L.GC_CANCEL_TIP)
    else
        Core.ShowTip(self, L.GC_START, L.GC_START_TIP)
    end
end

-- Text eines abgelehnten Starts: Kampf in ezCores Wortlaut (T18-1), „aus“ mit dem Weg zum Schalter (T18-18)
function Panel.RefusedText(reason)
    if reason == "combat" then return Core.CombatText(L.GC_COMBAT_WHAT) end
    if reason == "off" then return L.GC_REFUSED_off:format(ns.PathText("OPT_HEADER_GROUP", "OPT_groupCheck")) end
    local key = "GC_REFUSED_" .. tostring(reason)
    return L[key] ~= key and L[key] or nil
end

-- „Abbrechen“ ist Blizzards CANCEL (T18-22) über Core.Word – den Rückfall hält ezCore
function Panel.CancelText() return Core.Word("CANCEL") end

function Panel.OnStartClick()
    local check = ns.GroupCheck
    if check.Running() then
        check.Cancel("cancel")
        return
    end
    local ok, reason = check.Start()
    local text = not ok and reason and Panel.RefusedText(reason)
    if text then panel.Status:SetText(text) end
end

---------------------------------------------------------------------------
-- Sichtbarkeit: Schalter, Schlachtzugsinfo
---------------------------------------------------------------------------

local function InfoShownOnOurSide()
    local info = RaidInfo()
    return panel ~= nil and panel.side ~= "left" and type(info) == "table" and info.IsShown ~= nil and info:IsShown() == true
end

function Panel.ApplyShown()
    if not panel then return end
    local on = ns.Enabled("groupCheck")
    panel.arrow:SetShown(on)
    hiddenByInfo = on and panel:IsOpen() and InfoShownOnOurSide()
    panel:SetShown(on and panel:IsOpen() and not hiddenByInfo)
    if not on or not panel:IsOpen() then ns.GroupCheck.Cancel("closed") end
    Panel.Refresh()
end

function Panel.HiddenByInfo() return hiddenByInfo end

local function OnToggle(open)
    -- Der Spieler hat das Feld geöffnet: Blizzards Schlachtzugsinfo an derselben Stelle tritt zurück
    if open and InfoShownOnOurSide() and not ns.InCombat() then RaidInfo():Hide() end
    Panel.ApplyShown()
end

---------------------------------------------------------------------------
-- Bau
---------------------------------------------------------------------------

local function Build(parent)
    local db = ns.db
    panel = Core.NewSidePanel(parent, { name = "ezGearGroupCheck", width = Panel.WIDTH, gap = Panel.GAP, side = "right",
        store = db and db.ui, key = "groupOpen", open = false, owner = ADDON,
        tip = L.GC_ARROW, tipBody = L.GC_ARROW_TIP,
        onToggle = function(open) ns.Try("GroupPanel", OnToggle, open) end,
        onPlaced = function() ns.Try("GroupPanel", Panel.ApplyShown) end })
    if not panel then return nil end
    local room = Core.SIDEPANEL_ARROW_ROOM or 30
    -- Titel mit Erklärung (Quelle der Angaben, Leitlinie 11)
    panel.Title = CreateFrame("Button", nil, panel)
    panel.Title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    panel.Title:SetSize(Panel.WIDTH - 20 - room, 18)
    panel.Title.Text = Font(panel.Title, "heading", "ARTWORK")
    panel.Title.Text:SetPoint("LEFT", panel.Title, "LEFT", 0, 0)
    panel.Title.Text:SetText(L.GC_TITLE)
    panel.Title:SetScript("OnEnter", Core.TipScript(L.GC_TITLE, L.GC_TITLE_TIP))
    panel.Title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.Start = CreateFrame("Button", "ezGearGroupCheckStart", panel, "UIPanelButtonTemplate")
    panel.Start:SetSize(120, 22)
    panel.Start:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -30)
    panel.Start:SetText(L.GC_START)
    panel.Start:SetScript("OnClick", function() ns.Try("GroupCheck", Panel.OnStartClick) end)
    panel.Start:SetScript("OnEnter", StartTip)
    panel.Start:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.Status = Font(panel, "hint")
    panel.Status:SetPoint("TOPLEFT", panel.Start, "BOTTOMLEFT", 2, -4)
    panel.Status:SetWidth(Panel.WIDTH - 24)
    panel.Status:SetJustifyH("LEFT")

    -- Spaltenköpfe (Gold, klein)
    local heads = { { "name", L.GC_COL_NAME, "LEFT", 100 }, { "level", L.GC_COL_LEVEL, "RIGHT", 36 },
        { "enchant", L.GC_COL_ENCHANT, "RIGHT", 32 }, { "empty", L.GC_COL_EMPTY, "RIGHT", 28 } }
    panel.Heads = {}
    for _, head in ipairs(heads) do
        local fs = Font(panel, "label")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", Panel.COL[head[1]], -(Panel.TOP - 16))
        fs:SetWidth(head[4])
        fs:SetJustifyH(head[3])
        fs:SetText(head[2])
        panel.Heads[head[1]] = fs
    end

    local ok, frame = pcall(CreateFrame, "ScrollFrame", nil, panel, "ScrollFrameTemplate")
    if not (ok and frame) then frame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate") end
    scroll = frame
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -Panel.TOP)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 8)
    -- Hinweis unten, nur bei mode "overlap" (Panel.Refresh)
    panel.Note = Font(panel, "hint")
    panel.Note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
    panel.Note:SetWidth(Panel.WIDTH - 20)
    panel.Note:SetJustifyH("LEFT")
    Color(panel.Note, "warn")
    panel.Note:Hide()
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(Panel.WIDTH - 32, 1)
    scroll:SetScrollChild(content)
    panel.Scroll, panel.Content = scroll, content

    panel:HookScript("OnShow", function() ns.Try("GroupPanel", Panel.Refresh) end)
    parent:HookScript("OnHide", function() ns.GroupCheck.Cancel("closed") end)
    local info = RaidInfo()
    if type(info) == "table" and info.HookScript then
        info:HookScript("OnShow", function() ns.Try("GroupPanel", Panel.ApplyShown) end)
        info:HookScript("OnHide", function() ns.Try("GroupPanel", Panel.ApplyShown) end)
    end
    ns.GroupCheck.OnChange(function() ns.Try("GroupPanel", Panel.Refresh) end)
    Panel.ApplyShown()
    return panel
end
Panel.Build = Build

-- Erst außerhalb des Kampfes bauen (eigene Rahmen an einem Blizzard-Fenster; wie ezHeals Einstiege)
local function Install()
    if panel then return true end
    local parent = RaidFrame()
    if type(parent) ~= "table" then return false end
    if ns.InCombat() then
        ns.AfterCombat(function() ns.Try("GroupPanel", Install) end, "groupPanel")
        return true
    end
    ns.Try("GroupPanel", Build, parent)
    return true
end
Panel.Install = Install

ns.OnReady(function()
    if not Install() then ns.WhenAddOnLoaded("Blizzard_RaidFrame", Install) end
    ns.OnSettingChanged(function(key)
        if key == "groupCheck" then ns.Try("GroupPanel", Panel.ApplyShown) end
    end)
    ns.On("GROUP_ROSTER_UPDATE", function()
        if panel and panel:IsShown() then ns.Try("GroupPanel", Panel.Refresh) end
    end)
end)
