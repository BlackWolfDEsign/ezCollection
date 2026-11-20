local _, ns = ...
local L = ns.L

--[[
    ezBag-Fenster im Stil der Originaltasche:
    - Bank (alle Fächer zusammen, gruppiert): der zuletzt gespeicherte Stand, nur Ansicht. Steht der Charakter
      an der Bank, baut das Fenster sie nicht nach (Entscheidung des Nutzers, 13.11.2026, V-045): Wer die eigene
      Bank öffnen will, bekommt Blizzards Bank nach vorn (Window.ShowBlizzardBank); ein- und ausgelagert wird
      dort – ezBag gruppiert sie im Original (Bank.lua).
    - Das Fenster dockt neben Bank, Gildenbank oder Tasche an und wandert mit (Schalter „dockWindow“,
      V-055/V-059); von Hand gezogen steht es frei, bis es das nächste Mal geöffnet wird.
    - Andere Charaktere offline: Taschen, Bank, Post, angelegt oder alles.
    - Gildenbank: alle Fächer gruppiert (nur Ansicht).
    - Alle Charaktere: alles von allen Twinks und Gildenbanken zusammen, gleiche Gegenstände
      zusammengefasst; mit Suche bleiben nur die Treffer stehen („Bei allen Charakteren suchen“). Mit „Fundort zeigen“
      je Ort ein Platz mit Ortssymbol und Tooltip-Zeilen „Liegt: Ort (Charakter)“ (W-1811-ezBag, Abschnitt „Fundort“).
    - Werkzeugleiste wie in Tasche und Bank (Toolbar.lua): Suchen, Ort bzw. Fach oder Gruppe
      hervorheben, Sortierung, alle auf/zu, unterwegs ansehen.
]]

local Window = {}
ns.Window = Window

local COLS = 12
local SLOT, SPACING = 37, 5
local OWNER_W, LOCATION_W = 140, 100   -- Kopfzeile: Besitzer, Ort, dann Werkzeugleiste und Suche
local AREA_W = COLS * (SLOT + SPACING)
local LOCATIONS = { "all", "bags", "bank", "mail", "equip" }
local ALL = "*all"            -- Besitzer „Alle Charaktere“
-- Blizzards Symbole je Ort: Ort hervorheben (Werkzeugleiste), Fundort am Platz (W-1811-ezBag), „Unterwegs ansehen“.
local LOCATION_ICON = {
    bags = "Interface\\Buttons\\Button-Backpack-Up",
    bank = "Interface\\Icons\\INV_Box_02",
    mail = "Interface\\Icons\\INV_Letter_15",
    equip = "Interface\\Icons\\INV_Chest_Chain",
    guild = "Interface\\Icons\\INV_Misc_TabardPVP_01",
}

local frame, scroll, content, view, toolbar
local ownerButton, locationButton, searchBox, infoText, emptyText
local state = { owner = nil, location = "bank" }
local dirty = false
local displayPool, displayUsed = {}, 0
local holders, liveButtons = {}, {}

---------------------------------------------------------------------------
-- Besitzer und Ort
---------------------------------------------------------------------------

local function GuildKeyOf(owner)
    return type(owner) == "string" and owner:match("^guild:(.+)$") or nil
end

local function OwnerData()
    if state.owner == ALL then return { name = L.ALL_CHARS }, false end
    local guildKey = GuildKeyOf(state.owner)
    if guildKey then return ezCore.Guilds()[guildKey], true end
    return ezCore.Chars()[state.owner], false
end

local function IsLive()
    return state.owner == ns.charKey and state.location == "bank" and ns.Inventory.IsBankOpen()
end

-- Nachgebaute Live-Bank (eigene Platz-Knöpfe an der Bank): seit Welle 2 aus – das Fenster zeigt auch an der Bank
-- den gespeicherten Stand und verweist auf Blizzards Bank. Die Teile dafür (Holder, LiveButton, FillLive,
-- LiveGroups) stehen noch hier; ob sie gelöscht werden, entscheidet der Nutzer (docs/roadmap/ezBag.md).
Window.LIVE_BANK = false

local function UseLive()
    return Window.LIVE_BANK == true and IsLive()
end

-- Gold aller Charaktere (für „Alle Charaktere“ und das Geldfeld der Tasche).
function Window.TotalMoney()
    local _, sum = ezCore.GoldList()
    return sum
end

local function SearchText()
    return searchBox and (searchBox:GetText() or ""):lower() or ""
end

-- Suche graut aus statt auszublenden: alles bleibt an seinem Platz.
local function MarkSearch(groups, search)
    for _, g in ipairs(groups) do
        for _, entry in ipairs(g.entries) do
            entry.searchDim = search ~= "" and not ns.Render.Matches(entry, search) or nil
        end
    end
end

---------------------------------------------------------------------------
-- Plätze
---------------------------------------------------------------------------

local function SlotBackground(button)
    local ok, tex = pcall(button.CreateTexture, button, nil, "BACKGROUND", "ItemSlotBackgroundCombinedBagsTemplate", -6)
    if not ok or not tex then
        tex = button:CreateTexture(nil, "BACKGROUND", nil, -6)
        tex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    end
    tex:SetAllPoints(button)
    return tex
end

local function OnAltRightClick(button, mouse)
    return mouse == "RightButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()
end

---------------------------------------------------------------------------
-- Fundort (Wunsch des Nutzers vom 18.11.2026, W-1811-ezBag: „itemanzeige von einem oder anderen char, es muss auch
-- angezeigt werden, wo die items liegen tasche, bank, gildenbank“). Jeder Anzeige-Platz kennt seine Orte
-- (entry.places: Ort, Charakter bzw. Gilde, Anzahl); der Tooltip nennt sie als „Liegt: Ort (Charakter)“, ein kleines
-- Symbol unten links zeigt den Ort, wo Orte gemischt erscheinen (Alle Charaktere, „Alles“ eines Charakters).
-- Schalter „Fundort zeigen“ (ns.ShowPlace, Search.lua). Daten nur gelesen: ezCore.Chars, ezCore.Guilds.
---------------------------------------------------------------------------

local MAX_PLACE_LINES = 8
local placeIcons = setmetatable({}, { __mode = "k" })   -- Anzeige-Platz → Symbol des Orts (eigene Textur)

-- Ort eines Eintrags (bags, bank, mail, equip, guild oder "tab<n>" in der Ansicht einer Gildenbank) → Schlüssel
-- für LOCATION_ICON und den Namen.
local function PlaceKind(bag)
    if type(bag) ~= "string" then return nil end
    if bag:match("^tab%d+$") then return "guild" end
    return bag
end

-- Ortsname: „Taschen“, „Bank“ … bzw. „Gildenbank, Fach „Name““.
function Window.PlaceName(place)
    local bag = type(place) == "table" and place.bag
    local tab = type(bag) == "string" and tonumber(bag:match("^tab(%d+)$"))
    if tab then
        local g = place.guild and ezCore.Guilds()[place.guild]
        local t = g and g.tabs and g.tabs[tab]
        return L.PLACE_TAB:format(L.LOC_guild, t and t.name or tostring(tab))
    end
    local kind = PlaceKind(bag)
    return kind and L["LOC_" .. kind] or "?"
end

-- Besitzer: Charakter (in Klassenfarbe, wie im Besitzer-Menü) oder Gilde.
function Window.PlaceOwner(place)
    if type(place) ~= "table" then return "?" end
    if place.guild then
        local g = ezCore.Guilds()[place.guild]
        return g and g.name or tostring(place.guild)
    end
    if place.char then return ezCore.CharName(ezCore.Chars()[place.char], place.char) end
    return "?"
end

-- → „Liegt: Bank (Name)“
function Window.PlaceLine(place)
    return L.PLACE_LINE:format(Window.PlaceName(place), Window.PlaceOwner(place))
end

-- Orte eines Platzes zusammenzählen: gleicher Ort und Besitzer → eine Zeile.
local function AddPlace(entry, bag, owner, count)
    entry.places = entry.places or {}
    local char, guild = owner and owner.char, owner and owner.guild
    for _, p in ipairs(entry.places) do
        if p.bag == bag and p.char == char and p.guild == guild then
            p.count = p.count + count
            return
        end
    end
    entry.places[#entry.places + 1] = { bag = bag, char = char, guild = guild, count = count }
    -- Ein Ort für alle Teile? Dann trägt der Platz sein Symbol; gemischt (Schalter aus, alte Zusammenfassung) nicht.
    local kind = PlaceKind(bag)
    if entry.placeKind == nil then
        entry.placeKind = kind or false
    elseif entry.placeKind ~= kind then
        entry.placeKind = false
    end
end

-- Zeigt das Fenster gerade Orte gemischt (dann Symbol am Platz)? Alle Charaktere oder „Alles“ eines Charakters.
-- Ohne die Aufteilung je Ort (Schalter showPlace aus) trägt nur ein Platz mit genau einem Ort sein Symbol (placeKind).
local function WantPlaceIcons()
    if state.owner == ALL then return true end
    return state.location == "all" and not GuildKeyOf(state.owner)
end

-- Orte eines Platzes samt der Stapel, die „Gleiche Gegenstände zusammenfassen“ (Render.Compact) auf ihn gelegt hat
-- → places, placeKind. Ohne zusammengefasste Stapel die des Eintrags selbst.
local function EntryPlaces(entry)
    if type(entry.merged) ~= "table" or #entry.merged == 0 then return entry.places, entry.placeKind end
    local sum = {}
    local function addAll(e)
        for _, p in ipairs(e.places or {}) do AddPlace(sum, p.bag, p, p.count) end
    end
    addAll(entry)
    for _, e in ipairs(entry.merged) do addAll(e) end
    return sum.places, sum.placeKind
end
Window.EntryPlaces = EntryPlaces
Window.WantPlaceIcons = WantPlaceIcons

-- Unterebene des Symbols: über den Marken (Marks.lua, Unterebene 1), unter ezBags Grauschicht für Suche und
-- Hervorheben (Render.SetDimmed, Unterebene 6), damit ein ausgegrauter Platz auch sein Symbol abdunkelt.
local PLACE_ICON_SUBLEVEL = 2
Window.PLACE_ICON_SUBLEVEL = PLACE_ICON_SUBLEVEL

local function HasText(fs)
    local text = fs and fs:GetText()
    return type(text) == "string" and text ~= ""
end

-- Ecke für das Symbol (Gegenprüfung W-1811-ezBag): Der linke Rand gehört den Marken (bis zu zwei untereinander,
-- Marks.lua) und „BoE“ unten links, also sitzt das Symbol rechts. Itemlevel (oben rechts) tragen Ausrüstungsteile,
-- die Anzahl (unten rechts) Stapel; das Symbol nimmt die freie Ecke, bei beiden die Mitte des rechten Rands.
-- → Ankerpunkt, x, y
local function PlaceIconCorner(button, count)
    local o = ezCore.SlotText and ezCore.SlotText.Overlay and ezCore.SlotText.Overlay(button)
    local hasLevel = o and HasText(o.ilvl)
    local hasCount = type(count) == "number" and count > 1
    if not hasLevel then return "TOPRIGHT", -2, -2 end
    if not hasCount then return "BOTTOMRIGHT", -2, 2 end
    return "RIGHT", -2, 0
end
Window.PlaceIconCorner = PlaceIconCorner

-- Symbol am rechten Rand des Platzes (Größe der Marken am Platz aus ezCore.SlotMarks), Ecke aus PlaceIconCorner.
local function SetPlaceIcon(button, placeKind, count)
    local tex = placeIcons[button]
    local kind = WantPlaceIcons() and placeKind
    local file = kind and LOCATION_ICON[kind]
    if not file then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        local size = ezCore.SlotMarks and ezCore.SlotMarks.SIZE or 13
        tex = button:CreateTexture(nil, "OVERLAY", nil, PLACE_ICON_SUBLEVEL)
        tex:SetSize(size, size)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        placeIcons[button] = tex
    end
    tex:SetTexture(file)
    local point, x, y = PlaceIconCorner(button, count)
    tex:ClearAllPoints()
    tex:SetPoint(point, button, point, x, y)
    tex:Show()
end

-- Das Symbol eines Platzes (für Tests): Textur oder nil, wenn keines zu sehen ist.
function Window.PlaceIcon(button)
    local tex = placeIcons[button]
    return tex and tex:IsShown() and tex or nil
end

-- Zeilen „Liegt: Ort (Besitzer)“ mit Anzahl rechts, die größten zuerst, höchstens MAX_PLACE_LINES. Immer, auch ohne
-- Aufteilung je Ort (Einstellungs-Prüfung vom 19.11.2026): dann nennt ein Platz alle Orte seiner Stapel.
function Window.AddPlaceLines(tooltip, places)
    if not (type(places) == "table" and #places > 0) then return 0 end
    local list = {}
    for i, p in ipairs(places) do list[i] = p end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return Window.PlaceLine(a) < Window.PlaceLine(b)
    end)
    ezCore.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): nie zwei Leerzeilen
    local r, g, b = ns.TipRGB("normal")
    local hr, hg, hb = ns.TipRGB("highlight")
    local n = 0
    for i, p in ipairs(list) do
        if i > MAX_PLACE_LINES then
            local gr, gg, gb = ns.TipRGB("hint")
            tooltip:AddLine(L.PLACE_MORE:format(#list - MAX_PLACE_LINES), gr, gg, gb)
            break
        end
        tooltip:AddDoubleLine(Window.PlaceLine(p), tostring(p.count), r, g, b, hr, hg, hb)
        n = n + 1
    end
    return n
end

-- Zeilen „Liegt:“ als Abschnitt in ezCores Tooltip-Pipeline (Gegenprüfung W-1811-ezBag): Baut Blizzard den Tooltip
-- neu auf (RefreshData, z. B. ezGear beim Drücken von Umschalt, oder wenn Daten nachkommen), läuft der Abschnitt
-- wieder mit, die Zeilen bleiben. Nur für eigene Anzeige-Plätze (displayButtons) als Besitzer des Tooltips.
local displayButtons = setmetatable({}, { __mode = "k" })
local placeLinesFor   -- Platz, für den der Abschnitt im laufenden Aufbau schon Zeilen angehängt hat

function Window.PlaceSection(tooltip, itemID)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if not (owner and displayButtons[owner] and owner.itemID == itemID) then return end
    placeLinesFor = owner
    Window.AddPlaceLines(tooltip, owner.places)
end

if ezCore.Tooltip and ezCore.Tooltip.AddItemSection then
    -- direkt vor ezCores „Anzahl bei Twinks“ (Platz counts)
    ezCore.Tooltip.AddItemSection("ezBag.place", ezCore.Tooltip.Order("counts") - 1, Window.PlaceSection, "ezBag")
end

-- Anzeige-Platz (offline): Symbol, Anzahl, Qualität, Tooltip, Chat-Link.
local function DisplayEnter(self)
    placeLinesFor = nil
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then
        GameTooltip:SetHyperlink(self.link)
    elseif self.itemID then
        GameTooltip:SetItemByID(self.itemID)
    end
    -- Ohne Tooltip-Daten (kein Abschnitt gelaufen) hängt der Platz die Zeilen selbst an.
    if placeLinesFor ~= self then Window.AddPlaceLines(GameTooltip, self.places) end
    placeLinesFor = nil
    GameTooltip:Show()
end
Window.DisplayEnter = DisplayEnter   -- für Tests (der Stub ersetzt OnEnter durch den Hover-Haken der Ansicht)

local function DisplayClick(self, mouse)
    if OnAltRightClick(self, mouse) then
        ns.Groups.OpenItemMenuFor(self, self.itemID, self.link, self.quality)
    elseif IsModifiedClick() and self.link then
        HandleModifiedItemClick(self.link)
    end
end

local function NewDisplayButton()
    local ok, button = pcall(CreateFrame, "ItemButton", nil, content)
    if not ok or not button then button = CreateFrame("Button", nil, content, "ItemButtonTemplate") end
    button:SetSize(SLOT, SLOT)
    button:SetFrameLevel(content:GetFrameLevel() + 5)
    SlotBackground(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", DisplayEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", DisplayClick)
    ns.Render.HookHover(button, view)
    displayButtons[button] = true
    return button
end

local function FillDisplay(button, entry)
    button.link, button.itemID, button.quality = entry.link, entry.itemID, entry.quality
    local places, placeKind = EntryPlaces(entry)
    button.places = places
    SetItemButtonTexture(button, C_Item.GetItemIconByID(entry.itemID))
    SetItemButtonCount(button, entry.stackTotal or entry.count)
    SetItemButtonQuality(button, entry.quality, entry.link or entry.itemID)
    SetItemButtonDesaturated(button, false)
    ns.SetItemMarks(button, entry.itemID, entry.link, entry.quality, entry.bound)
    SetPlaceIcon(button, placeKind, entry.stackTotal or entry.count)
end

-- Echter Bank-Platz (live): Blizzards Container-Knopf in einem Halter mit der Taschen-ID.
local function Holder(bag)
    local holder = holders[bag]
    if not holder then
        holder = CreateFrame("Frame", nil, content)
        holder:SetID(bag)
        holder:SetAllPoints(content)
        holder:SetFrameLevel(content:GetFrameLevel() + 4)
        holder.IsCombinedBagContainer = function() return false end
        holders[bag] = holder
    end
    return holder
end

local function LiveButton(bag, slot)
    liveButtons[bag] = liveButtons[bag] or {}
    local button = liveButtons[bag][slot]
    if button then return button end
    if ns.InCombat() then return nil end
    local ok, created = pcall(CreateFrame, "ItemButton", nil, Holder(bag), "ContainerFrameItemButtonTemplate")
    if not ok or not created then return nil end
    created:SetID(slot)
    created.GetItemContextMatchResult = nil
    SlotBackground(created)
    created:HookScript("OnClick", function(self, mouse)
        if OnAltRightClick(self, mouse) then ns.Groups.OpenItemMenu(self) end
    end)
    ns.Render.HookHover(created, view)
    liveButtons[bag][slot] = created
    return created
end

local function Call(button, method, ...)
    local fn = button[method]
    if type(fn) == "function" then pcall(fn, button, ...) end
end

local function FillLive(button)
    local bag, slot = button:GetParent():GetID(), button:GetID()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot) or {}
    local texture = info and info.iconFileID
    local quality = info and info.quality
    if ClearItemButtonOverlay then ClearItemButtonOverlay(button) end
    Call(button, "SetHasItem", texture)
    if button.SetItemButtonTexture then Call(button, "SetItemButtonTexture", texture) else SetItemButtonTexture(button, texture) end
    SetItemButtonQuality(button, quality, info and info.hyperlink, false, info and info.isBound)
    SetItemButtonCount(button, info and info.stackCount)
    SetItemButtonDesaturated(button, info and info.isLocked)
    Call(button, "UpdateQuestItem", quest.isQuestItem, quest.questID, quest.isActive)
    Call(button, "UpdateJunkItem", quality, info and info.hasNoValue)
    Call(button, "UpdateCooldown", texture)
    Call(button, "SetReadable", info and info.isReadable)
    Call(button, "SetMatchesSearch", true)
    ns.SetItemMarks(button, info and info.itemID, info and info.hyperlink, quality, info and info.isBound == true, bag, slot)
end

---------------------------------------------------------------------------
-- Gruppen bauen
---------------------------------------------------------------------------

-- Gespeicherte Einträge { i, l, c, q, b } mit ihrem Ort (Taschen, Bank … bzw. Fach der Gildenbank) und Besitzer
-- (who: { char = Schlüssel } oder { guild = Schlüssel }; für den Fundort, W-1811-ezBag).
local function OfflineList(data, isGuild)
    local list, where, who = {}, {}, {}
    local guildKey = isGuild and GuildKeyOf(state.owner) or nil
    local owner = guildKey and { guild = guildKey } or { char = state.owner }
    local function add(source, place)
        if type(source) ~= "table" then return end
        for _, e in ipairs(source) do
            list[#list + 1] = e
            where[#list] = place
            who[#list] = owner
        end
    end
    if state.owner == ALL then
        local owners = {}
        ns.Search.ForEachStored(function(e, charKey, location, gKey)
            if state.location == "all" or state.location == location then
                list[#list + 1] = e
                where[#list] = location
                local id = gKey and ("guild:" .. gKey) or tostring(charKey)
                owners[id] = owners[id] or (gKey and { guild = gKey } or { char = charKey })
                who[#list] = owners[id]
            end
        end, false)
    elseif isGuild then
        local tabs = {}
        for tab in pairs(data.tabs or {}) do tabs[#tabs + 1] = tab end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do add(data.tabs[tab].items, "tab" .. tab) end
    else
        local items = data.items or {}
        if state.location == "all" then
            for _, location in ipairs(ns.Inventory.LOCATIONS) do add(items[location], location) end
        else
            add(items[state.location], state.location)
        end
    end
    return list, where, who
end

-- merge: gleiche Gegenstände zu einem Platz zusammenfassen (Anzahl addiert) – für „Alle Charaktere“. Mit dem
-- Schalter „Fundort zeigen“ je Ort ein Platz (Taschen, Bank, Gildenbank … getrennt), damit sein Symbol stimmt.
local function OfflineGroups(list, where, merge, who)
    local groups, byKey, merged = {}, {}, {}
    where, who = where or {}, who or {}
    local perPlace = merge and ns.ShowPlace()
    for index, e in ipairs(list) do
        local itemID = ezCore.ItemID(e.i or e.l)   -- V-176: gesperrt oder leer → nil
        if itemID then
            local name = ns.ItemName(e.l) or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ""
            local quality = e.q or (C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(e.l or itemID)) or 1
            local key = ns.ClassifyItem({ itemID = itemID, link = e.l, quality = quality, name = name, bound = e.b })
            local group = byKey[key] or ns.Render.NewGroup(groups, byKey, key, key)
            local count = e.c or 1
            local mergeKey = e.l or itemID
            if perPlace then mergeKey = tostring(mergeKey) .. "@" .. tostring(where[index]) end
            local same = merge and merged[mergeKey]
            if same then
                same.count = same.count + count
                same.sig = itemID .. "x" .. same.count
                AddPlace(same, where[index], who[index], count)
            else
                local entry = {
                    itemID = itemID, quality = quality, name = name, count = count,
                    link = e.l, bound = e.b, order = index, sig = itemID .. "x" .. count, bag = where[index],
                }
                AddPlace(entry, where[index], who[index], count)
                -- „Gleiche Gegenstände zusammenfassen“ legt dann nur Stapel am selben Ort zusammen (Render.Compact) –
                -- nur mit dem Schalter „Gleiche Gegenstände je Ort getrennt zeigen“; aus gilt ein Platz je Gegenstand
                -- auch in „Alles“ eines Charakters (Gegenprüfung zur Einstellungs-Prüfung vom 19.11.2026).
                if WantPlaceIcons() and ns.ShowPlace() then
                    entry.compactKey = tostring(e.l or itemID) .. "@" .. tostring(PlaceKind(where[index]))
                end
                group.entries[#group.entries + 1] = entry
                if merge then merged[mergeKey] = entry end
            end
            if key == "junk" then
                local price = ezCore.VendorPrice(e.l or itemID)
                group.copper = group.copper + (price or 0) * count
            end
        end
    end
    ns.Render.AddEmptyCustomGroups(groups, byKey)
    ns.Render.SortGroups(groups)
    return groups
end

local function LiveGroups()
    local slots = {}
    for _, bag in ipairs(ns.Inventory.BankBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local button = LiveButton(bag, slot)
            if button then slots[#slots + 1] = { button = button, bag = bag, slot = slot } end
        end
    end
    return ns.GroupsFromSlots(slots, false)
end

---------------------------------------------------------------------------
-- Kopfzeile
---------------------------------------------------------------------------

local function TimeText(stamp)
    if not stamp then return L.WINDOW_NEVER end
    return ezCore.DateText(stamp, "full")
end

local function UpdateHeader(live)
    local data, isGuild = OwnerData()
    local ownerName
    if state.owner == ALL then
        ownerName = L.ALL_CHARS
    elseif isGuild then
        ownerName = data and data.name or "?"
    else
        ownerName = data and ezCore.CharName(data, state.owner) or tostring(state.owner)
    end
    local locationName = isGuild and L.LOC_guild or L["LOC_" .. state.location]
    ownerButton:SetText(ownerName)
    locationButton:SetText(locationName)
    locationButton:SetEnabled(not isGuild)
    if frame.SetTitle then frame:SetTitle(L.WINDOW_TITLE:format(data and data.name or "ezBag", locationName)) end

    local parts = {}
    if live then
        parts[#parts + 1] = ezCore.Style.ColorText("good", L.WINDOW_LIVE)   -- Blizzards Grün (Design-System 2.5)
    elseif IsLive() then
        -- An der Bank: nur Ansicht, gearbeitet wird in Blizzards Bank.
        parts[#parts + 1] = ezCore.Style.ColorText("good", L.WINDOW_AT_BANK)
    elseif data then
        local seen
        if isGuild then
            seen = data.seen
        elseif state.location == "bank" then
            seen = data.bankSeen
        elseif state.location == "mail" then
            seen = data.mailSeen
        end
        if isGuild or state.location == "bank" or state.location == "mail" then
            parts[#parts + 1] = L.WINDOW_SEEN:format(TimeText(seen))
        end
    end
    if state.owner == ALL then
        parts[#parts + 1] = ns.ShowPlace() and L.WINDOW_ALL_HINT_PLACE or L.WINDOW_ALL_HINT
        parts[#parts + 1] = ns.CoinText(Window.TotalMoney())
    elseif isGuild then
        parts[#parts + 1] = L.WINDOW_GUILD_HINT
    elseif data and data.money then
        parts[#parts + 1] = ns.CoinText(data.money)
    end
    infoText:SetText(table.concat(parts, "   "))
end

---------------------------------------------------------------------------
-- Zeichnen
---------------------------------------------------------------------------

local function Place(region, left, top)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", content, "TOPLEFT", left, -top)
end

local function Draw()
    dirty = false
    if not frame or not frame:IsShown() then return end
    local search = SearchText()
    local live = UseLive()

    local groups = {}
    if live then
        groups = LiveGroups()
    else
        local data, isGuild = OwnerData()
        if data then
            local list, where, who = OfflineList(data, isGuild)
            groups = OfflineGroups(list, where, state.owner == ALL, who)
        end
    end
    if state.owner == ALL and search ~= "" then
        -- Suche über alle Charaktere: nur die Treffer stehen lassen (eine kurze Ergebnisliste).
        local kept = {}
        for _, g in ipairs(groups) do
            local hits = {}
            for _, entry in ipairs(g.entries) do
                if entry.itemID and ns.Render.Matches(entry, search) then hits[#hits + 1] = entry end
            end
            if #hits > 0 then
                g.entries = hits
                kept[#kept + 1] = g
            end
        end
        groups = kept
    else
        MarkSearch(groups, search)
    end

    local geom = { cols = COLS, w = SLOT, h = SLOT, spX = SPACING, spY = SPACING }
    local out = ns.Render.Flow(groups, geom, { viewKey = "window", searching = search ~= "" })
    content:SetSize(out.width, math.max(out.totalH, 1))

    displayUsed = 0
    local shownLive = {}
    view:Draw(out, Place, function(entry, shown, left, top, g)
        if not shown then return end
        local button = entry.button
        if button then
            FillLive(button)
            ns.SetStackTotal(button, entry.stackTotal)
            shownLive[button] = true
        else
            displayUsed = displayUsed + 1
            button = displayPool[displayUsed]
            if not button then
                button = NewDisplayButton()
                displayPool[displayUsed] = button
            end
            FillDisplay(button, entry)
            entry.display = button
            view.byButton[button] = entry
        end
        Place(button, left, top)
        button:Show()
        ns.SetFreeCount(button, g.compressed and g.count or nil)
    end)
    view:ApplyDim()

    for i = displayUsed + 1, #displayPool do displayPool[i]:Hide() end
    for _, bySlot in pairs(liveButtons) do
        for _, button in pairs(bySlot) do
            if not shownLive[button] then button:Hide() end
        end
    end
    emptyText:SetText(search ~= "" and state.owner == ALL and L.WINDOW_NO_HITS or L.WINDOW_EMPTY)
    emptyText:SetShown(#groups == 0)
    UpdateHeader(live)
    if toolbar then toolbar:Update() end
end

function Window.Refresh(force)
    if not frame or not frame:IsShown() then return end
    if not force and (frame:IsMouseOver() or ns.Render.IsBusy() or CursorHasItem()) then
        dirty = true
        return
    end
    local ok, err = pcall(Draw)
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Menüs für Besitzer und Ort
---------------------------------------------------------------------------

local function SetOwner(owner)
    state.owner = owner
    if not GuildKeyOf(owner) and state.location == "guild" then state.location = "all" end
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    if toolbar then toolbar:ClearFocus() end
    Window.Refresh(true)
end

local function IsOwner(owner) return state.owner == owner end

local function OpenOwnerMenu()
    ezCore.Menu.Open(ownerButton, function(root)
        root:CreateRadio(L.ALL_CHARS, IsOwner, SetOwner, ALL)
        root:CreateTitle(L.WINDOW_CHARACTERS)
        local keys = {}
        for key in pairs(ezCore.Chars()) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            if (a == ns.charKey) ~= (b == ns.charKey) then return a == ns.charKey end
            return a < b
        end)
        for _, key in ipairs(keys) do
            root:CreateRadio(ezCore.CharName(ezCore.Chars()[key], key), IsOwner, SetOwner, key)
        end
        local guildData = ezCore.Guilds()
        local guilds = {}
        for key in pairs(guildData) do guilds[#guilds + 1] = key end
        table.sort(guilds)
        if #guilds > 0 then
            root:CreateTitle(L.WINDOW_GUILDS)
            for _, key in ipairs(guilds) do
                root:CreateRadio(guildData[key].name or key, IsOwner, SetOwner, "guild:" .. key)
            end
        end
    end)
end

local function OpenLocationMenu()
    ezCore.Menu.Open(locationButton, function(root)
        for _, location in ipairs(LOCATIONS) do
            root:CreateRadio(L["LOC_" .. location], function(v) return state.location == v end, function(v)
                state.location = v
                if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
                if toolbar then toolbar:ClearFocus() end
                Window.Refresh(true)
            end, location)
        end
    end)
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

--[[
    Andocken (Entscheidung des Nutzers „Andocken, wo es passt“, V-055/V-059): Mit dem Schalter „dockWindow“ hängt
    das Fenster beim Öffnen neben Bank oder Gildenbank (samt angedockter Tasche außen an der Reihe), sonst neben
    der Tasche – auf der Seite, auf der es ganz auf den Bildschirm passt – und wandert mit. Nur Anker (ezCore.Dock),
    nichts an Blizzards Fenstern. Zieht der Nutzer es weg, steht es frei (Lage gemerkt), bis es wieder geöffnet wird.
    Ohne Schalter oder ohne passendes Fenster: gemerkte Lage, sonst neben der Bank bzw. etwas über der Mitte.
]]
local DOCK_GAP = 2
local dockedTo, movedByUser = nil, false

-- → Fenster zum Andocken, Seite ("left"/"right"), Kante ("top"/"bottom") – oder nil (frei)
function Window.DockTarget()
    if not (ns.S and ns.S.dockWindow) then return nil end
    local bag = ns.Layout and ns.Layout.Frame and ns.Layout.Frame()
    if not (bag and bag:IsShown()) then bag = nil end
    local bank, guild = _G.BankFrame, _G.GuildBankFrame
    local panel = (bank and bank:IsShown() and bank) or (guild and guild:IsShown() and guild) or nil
    local width = (frame and frame:GetWidth() or 0) > 0 and frame:GetWidth() or (AREA_W + 36)
    local height = (frame and frame:GetHeight() or 0) > 0 and frame:GetHeight() or 560
    local screenW = UIParent:GetWidth() or 0

    local function Fits(anchor, side)
        local left, right = anchor:GetLeft(), anchor:GetRight()
        if not (left and right) then return false end
        if side == "left" then return left - DOCK_GAP - width >= 0 end
        return screenW <= 0 or right + DOCK_GAP + width <= screenW
    end
    local candidates = {}
    if panel and bag then
        -- Tasche und Bank stehen nebeneinander: außen an die Reihe, nicht dazwischen und nicht darüber.
        local bagRight = (bag:GetLeft() or 0) >= (panel:GetLeft() or 0)
        local rightmost, leftmost = bagRight and bag or panel, bagRight and panel or bag
        candidates = { { rightmost, "right" }, { leftmost, "left" } }
    elseif panel then
        candidates = { { panel, "right" }, { panel, "left" } }
    elseif bag then
        candidates = { { bag, "left" }, { bag, "right" } }
    end
    for _, c in ipairs(candidates) do
        local anchor, side = c[1], c[2]
        if Fits(anchor, side) then
            -- Oben bündig, wenn das Fenster darunter Platz hat; sonst unten bündig (die Tasche wächst von unten).
            local top = anchor:GetTop()
            local edge = (top == nil or top - height >= 0) and "top" or "bottom"
            return anchor, side, edge
        end
    end
    return nil
end

-- Hängt das Fenster gerade an einem anderen (→ dieses Fenster) oder steht es frei (→ nil)?
function Window.DockedTo() return dockedTo end

-- Frei stellen, ohne zu springen: die aktuelle Lage als festen Anker übernehmen (nichts wird gemerkt).
local function Undock()
    if not dockedTo then return end
    dockedTo = nil
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    frame:SetClampedToScreen(true)
end

local function Position(nextToBank)
    local anchor, side, edge = Window.DockTarget()
    if anchor then
        dockedTo = anchor
        -- Oben oder unten bündig (BAG-13): beides über ezCore.Dock, align = "bottom" statt eines eigenen Ankers.
        ezCore.Dock(frame, anchor, { side = side, gap = DOCK_GAP, matchHeight = false,
            align = edge == "bottom" and "bottom" or nil })
        return true
    end
    dockedTo = nil
    frame:SetClampedToScreen(true)
    if frame:RestorePosition() then return false end
    if nextToBank and BankFrame and BankFrame:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 12, 0)
    end
    return false
end

-- Bank, Gildenbank oder Tasche ging auf oder zu: neu andocken – außer der Nutzer hat das Fenster weggezogen.
-- Fällt das Fenster weg, an dem es hing, bleibt es stehen, wo es ist. Layout.Reposition ruft das nach jedem
-- Umzug der Tasche (Bank, Gildenbank, einen Frame nach dem Öffnen), damit die neue Lage gemessen wird.
function Window.Redock()
    if not (frame and frame:IsShown()) or movedByUser then return false end
    if Window.DockTarget() then return Position(false) end
    Undock()
    return false
end

-- Orte bzw. Fächer für „hervorheben“ in der Werkzeugleiste (passend zu entry.bag aus OfflineList).
local function FocusPlaces()
    local list = {}
    if UseLive() then return list end
    local data, isGuild = OwnerData()
    if isGuild then
        local tabs = {}
        for tab in pairs(data and data.tabs or {}) do tabs[#tabs + 1] = tab end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do
            local t = data.tabs[tab]
            list[#list + 1] = { id = "tab" .. tab, name = t.name or (L.LOC_guild .. " " .. tab), icon = t.icon }
        end
    elseif state.location == "all" and state.owner ~= ALL then
        for _, location in ipairs(ns.Inventory.LOCATIONS) do
            list[#list + 1] = { id = location, name = L["LOC_" .. location], icon = LOCATION_ICON[location] }
        end
    elseif state.location == "all" and ns.ShowPlace() then
        -- Alle Charaktere mit Fundort: jeder Platz hat genau einen Ort, also lässt sich auch hier ein Ort hervorheben.
        for _, location in ipairs(ns.Search.Places()) do
            list[#list + 1] = { id = location, name = L["LOC_" .. location], icon = LOCATION_ICON[location] }
        end
    end
    return list
end

-- Kopfzeile: Besitzer, Ort, dann Werkzeugleiste und Suchfeld rechts.
local function FitHeader()
    if not (frame and toolbar) then return end
    local barW = toolbar:Update() or 0
    local LAYOUT = ezCore.LAYOUT
    local left = LAYOUT.HEADER_X + OWNER_W + LAYOUT.GAP + LOCATION_W + 10
    local w = (frame:GetWidth() or 0) - left + LAYOUT.SEARCH_X - barW - 8
    searchBox:SetWidth(math.max(80, math.min(150, w)))
    toolbar.frame:ClearAllPoints()
    toolbar.frame:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    toolbar.frame:Show()
end

local function Create()
    if frame then return end
    local areaW = AREA_W

    -- Fenster-Muster aus ezCore (PortraitFrameFlatTemplate, verschiebbar, Esc schließt, Lage unter WINDOW_KEY).
    frame = ezCore.NewWindow("ezBagWindow", { portrait = "Interface\\Icons\\INV_Misc_Bag_08", width = areaW + 36, height = 560,
        positionKey = ns.WINDOW_KEY, default = { "CENTER", "CENTER", 0, 40 } })
    -- Von Hand gezogen: frei (NewWindow merkt die Lage), bis das Fenster wieder geöffnet wird.
    frame:HookScript("OnDragStart", function(self)
        movedByUser, dockedTo = true, nil
        self:SetClampedToScreen(true)
    end)
    frame:SetScript("OnHide", function()
        ns.Render.CancelDrag()
        if toolbar then toolbar:ClearFocus() end
    end)
    frame:SetScript("OnUpdate", ns.Render.DeferredUpdate(function() return dirty end, function()
        Window.Refresh(false)
    end))

    ownerButton = frame:HeaderButton("", OWNER_W, OpenOwnerMenu, L.WINDOW_OWNER_TITLE, L.WINDOW_OWNER_TIP)
    locationButton = frame:HeaderButton("", LOCATION_W, OpenLocationMenu, L.WINDOW_LOCATION_TITLE, L.WINDOW_LOCATION_TIP)
    -- Gesperrt bei einer Gildenbank: der Tooltip nennt dann den Grund (T9-7; HeaderButton setzt es schon, hier für
    -- jeden Fall ausdrücklich, auch mit einem älteren ezCore)
    if ezCore.Toolbar and ezCore.Toolbar.ShowTipWhileDisabled then ezCore.Toolbar.ShowTipWhileDisabled(locationButton) end
    -- gesperrt bei einer Gildenbank: der Tooltip sagt warum (T9-7; den Tooltip zeigt ezCores Knopf auch gesperrt)
    locationButton:SetScript("OnEnter", function(self)
        local body = L.WINDOW_LOCATION_TIP
        if not self:IsEnabled() then body = body .. "\n\n" .. ezCore.Style.ColorText("bad", L.WINDOW_LOCATION_GUILD) end
        ezCore.ShowTip(self, L.WINDOW_LOCATION_TITLE, body)
    end)
    searchBox = frame:Search(150, function() Window.Refresh(true) end, L.WINDOW_SEARCH_TITLE, L.WINDOW_SEARCH_TIP)

    scroll, content = frame:Scroll()
    content:SetSize(areaW, 1)
    view = ns.Render.NewView(content, "window")

    toolbar = ns.Toolbar.New(frame, {
        viewKey = "window",
        view = function() return view end,
        bags = FocusPlaces,
        search = function() return searchBox end,
        allChars = false,
        select = true,
        views = function() return Window.ViewEntries() end,
        onResize = FitHeader,
    })
    toolbar.frame:SetFrameLevel(frame:GetFrameLevel() + 20)
    FitHeader()

    infoText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 9)
    infoText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    infoText:SetJustifyH("LEFT")

    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", scroll, "TOPLEFT", 20, -20)
    emptyText:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -20, -20)
    emptyText:SetText(L.WINDOW_EMPTY)
    emptyText:Hide()
end

-- Die eigene Bank ist offen: Blizzards Bank nach vorn holen statt sie im Fenster nachzubauen (V-045) und kurz
-- sagen, warum kein Fenster aufgeht. → true, wenn die Bank offen ist
function Window.ShowBlizzardBank()
    local bank = _G.BankFrame
    if not (bank and bank:IsShown() and ns.Inventory.IsBankOpen()) then return false end
    if bank.Raise and not (ns.InCombat() and bank.IsProtected and bank:IsProtected()) then bank:Raise() end
    ezCore.ErrorMessage(L.WINDOW_USE_BANK, ns.TipRGB("normal"))
    return true
end

-- → true, wenn das Fenster offen ist; false, wenn stattdessen Blizzards Bank nach vorn kam. Der vierte Wert „stored“
-- (an der Bank trotzdem den gespeicherten Stand zeigen) diente nur dem Schalter „Bank öffnet zusätzlich das
-- ezBag-Fenster“ und entfiel mit ihm (Welle 23, Entscheidung des Nutzers vom 16.11.2026, Nr. 15).
function Window.Open(owner, location, nextToBank)
    -- Ausdrücklich die eigene Bank verlangt (Menü „Unterwegs ansehen“, /eb bank) und sie ist offen: dorthin.
    if location == "bank" and (owner == nil or owner == ns.charKey) and Window.ShowBlizzardBank() then
        return false
    end
    Create()
    state.owner = owner or state.owner or ns.charKey
    state.location = location or state.location or "all"
    movedByUser = false
    Position(nextToBank)
    frame:Show()
    Window.Refresh(true)
    return true
end

-- „Bei allen Charakteren suchen“ (Suchknopf der Werkzeugleiste): alle Twinks, Bank, Post, Gildenbank.
function Window.OpenSearch(text)
    Window.Open(ALL, "all")
    if searchBox then searchBox:SetText(text or "") end
    Window.Refresh(true)
end

function Window.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Window.Open()
    end
end

-- Eigene Gilde zuerst, sonst irgendeine gespeicherte (Gildenbanken liegen in ezCore).
local function GuildKey()
    local guilds = ezCore.Guilds()
    local mine = ezCore.Inventory.MyGuildKey()
    if mine and guilds[mine] then return mine end
    return next(guilds)
end

function Window.OpenGuild()
    local key = GuildKey()
    if key then Window.Open("guild:" .. key) else Window.Open(ns.charKey, "all") end
end

-- „Unterwegs ansehen“ im Menü „Tasche, Gruppe oder Bank“ der Werkzeugleiste (Stand vom letzten Besuch).
-- exclude = "bank" oder "guild": den Ort weglassen, an dem man gerade steht.
local VIEW_ICON = {
    bank = LOCATION_ICON.bank,
    guild = LOCATION_ICON.guild,
    all = "Interface\\Icons\\INV_Misc_GroupLooking",
}

local function Stamp(t)
    if type(t) ~= "number" then return " " .. ezCore.Grey(L.VIEW_NEVER) end
    return " " .. ezCore.Grey(L.VIEW_STAND:format(ezCore.DateText(t, "full")))
end

function Window.ViewEntries(exclude)
    local list = {}
    if exclude ~= "bank" then
        local me = ezCore.Char(ns.charKey)
        list[#list + 1] = { text = L.VIEW_BANK .. Stamp(me and me.bankSeen), icon = VIEW_ICON.bank,
            func = function() Window.Open(ns.charKey, "bank") end }
    end
    if exclude ~= "guild" and IsInGuild() then
        local key = GuildKey()
        local g = key and ezCore.Guilds()[key]
        list[#list + 1] = { text = L.VIEW_GUILD .. Stamp(g and g.seen), icon = VIEW_ICON.guild,
            func = Window.OpenGuild }
    end
    list[#list + 1] = { text = L.VIEW_ALL, icon = VIEW_ICON.all,
        func = function() Window.Open(ns.charKey, "all") end }
    return list
end

function Window.OnDataChanged()
    Window.Refresh(false)
end

-- Bank auf oder zu: ein offenes Fenster dockt neu an und zeichnet neu. Von selbst öffnet es sich nicht mehr – der
-- Schalter „Bank öffnet zusätzlich das ezBag-Fenster“ ist gestrichen (Welle 23, Entscheidung des Nutzers vom
-- 16.11.2026, Nr. 15: er zeigte neben der Bank nur deren gespeicherten Stand). Das Fenster bleibt an der Bank über
-- den Knopf oben rechts an der Tasche, „Unterwegs ansehen“ in der Werkzeugleiste der Bank und /eb fenster erreichbar.
function Window.OnBankOpened()
    Window.Redock()
    Window.Refresh(true)
end

function Window.OnBankClosed()
    Window.Redock()
    Window.Refresh(true)
end

-- „Fundort zeigen“ umgeschaltet: Symbole, Tooltip-Zeilen und die Aufteilung je Ort sofort neu (W-1811-ezBag).
-- Ein hervorgehobener Ort unter „Alle Charaktere“ gilt nur mit Fundort (FocusPlaces); ohne ihn wird er aufgehoben,
-- sonst blieben Plätze nach dem Ort ihres ersten Stapels gedimmt (Gegenprüfung).
ns.OnSettingChanged(function(key)
    if key ~= "showPlace" then return end
    if toolbar and view and view.focus and view.focus.kind == "bag" and state.owner == ALL then toolbar:ClearFocus() end
    Window.Refresh(true)
end)

-- Werkzeugleiste und Ansicht des Fensters (für Tests).
function Window.Toolbar() return toolbar, view end

ns.On("ITEM_LOCK_CHANGED", function(_, bag, slot)
    local button = bag and slot and liveButtons[bag] and liveButtons[bag][slot]
    if button and button:IsShown() then FillLive(button) end
end)

---------------------------------------------------------------------------
-- Zugänge: Knopf an der Tasche, Taschen-Menü
---------------------------------------------------------------------------

local bagButton

-- Knopf oben rechts an der Tasche (für den Rundgang, Tour.lua).
function Window.BagButton() return bagButton end
-- Knopf „Ort“ im Kopf des Fensters (für die Prüfungen: Tooltip am gesperrten Knopf, T9-7); nil vor dem ersten Öffnen.
function Window.LocationButton() return locationButton end

local function AddBagButton()
    local bag = _G.ContainerFrameCombinedBags
    if not bag or bagButton then return end
    local button = CreateFrame("Button", nil, bag)
    bagButton = button
    button:SetSize(ezCore.Style.ICON.line, ezCore.Style.ICON.line)   -- Symbol in Zeilengröße (16, Core.Style)
    button:SetPoint("TOPRIGHT", bag, "TOPRIGHT", -29, -4)   -- Mitte wie vorher (18 px an -28, -3)
    -- Über Titelleiste und Rahmen-Kanten (die haben bei Blizzard teils hohe Ebenen).
    button:SetFrameLevel(bag:GetFrameLevel() + 60)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    -- Nicht jedes Symbol gibt es in jedem Client: der Reihe nach probieren.
    for _, path in ipairs({ "Interface\\Icons\\INV_Misc_GroupNeedMore", "Interface\\Minimap\\Tracking\\Banker",
        "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\INV_Misc_Bag_08" }) do
        if icon:SetTexture(path) ~= false then break end
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", Window.Toggle)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local r, g, b = ns.TipRGB("highlight")
        GameTooltip:SetText(L.WINDOW_BUTTON_TIP, r, g, b, 1, true)
        ns.AddTipLine(ns.CmdText(L.WINDOW_BUTTON_CMD), "hint", true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

ns.OnReady(function()
    AddBagButton()
    -- Tasche auf oder zu: ein offenes Fenster dockt neu an bzw. bleibt stehen (nur Zuhören, einen Frame später).
    local bag = _G.ContainerFrameCombinedBags
    if bag and bag.HookScript then
        local function Later() C_Timer.After(0, Window.Redock) end
        bag:HookScript("OnShow", Later)
        bag:HookScript("OnHide", Later)
    end
    if Menu and Menu.ModifyMenu then
        pcall(Menu.ModifyMenu, "MENU_CONTAINER_FRAME_COMBINED", function(_, root)
            root:CreateDivider()
            root:CreateButton(L.MENU_OPEN_WINDOW, function() Window.Open() end)
        end)
    end
end)
