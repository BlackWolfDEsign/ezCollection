local _, ns = ...
local L = ns.L

--[[
    Anpassbare Gruppen:
    - Reihenfolge (per Ziehen der Titelzeile), gespeichert in db.order
    - Name, Sortierung und "in neuer Reihe beginnen" je Gruppe, gespeichert in db.groups
    - zugeklappt je Ansicht (Tasche, Bank, Fenster), gespeichert in db.collapsedBy
    - eigene Gruppen ("custom:<id>") mit optionalen Regeln, gespeichert in db.custom
    - Gegenstände einer Gruppe fest zuweisen (Alt+Rechtsklick oder auf den Titel ziehen)
    - im selben Menü am Gegenstand: „Im Auktionshaus suchen“, wenn ezAuction läuft (ezCore.API("ezAuction").Search),
      und „Im Auktionshaus verkaufen“ (ezCore.API("ezAuction").Sell, AH-26)
]]

local Groups = {}
ns.Groups = Groups

local function Refresh()
    ns.Layout.Refresh(true)
    if ns.Bank then ns.Bank.Refresh(true) end
    if ns.GuildBank then ns.GuildBank.Refresh(true) end
    if ns.Window then ns.Window.Refresh(true) end
end
Groups.RefreshAll = Refresh

---------------------------------------------------------------------------
-- Einstellungen je Gruppe
---------------------------------------------------------------------------

local function EnsureConfig(key)
    local c = ns.db.groups[key]
    if not c then
        c = {}
        ns.db.groups[key] = c
    end
    return c
end

local function CleanConfig(key)
    local c = ns.db.groups[key]
    if c and next(c) == nil then ns.db.groups[key] = nil end
end

function Groups.CustomID(key)
    return type(key) == "string" and key:match("^custom:(.+)$") or nil
end

function Groups.DefaultLabel(key)
    local id = Groups.CustomID(key)
    if id then
        local custom = ns.db.custom[id]
        return custom and custom.label or key
    end
    local bag = type(key) == "string" and key:match("^empty:(%-?%d+)$")
    if bag then
        return L.CAT_empty .. ": " .. (C_Container.GetBagName(tonumber(bag)) or bag)
    end
    return L["CAT_" .. key]
end

function Groups.Label(key)
    local c = ns.db.groups[key]
    if c and c.label and c.label ~= "" then return c.label end
    return Groups.DefaultLabel(key)
end

-- Gruppe beginnt immer am Anfang einer Reihe (ergibt ein 4- oder 6-Eck).
function Groups.NewRow(key)
    local c = ns.db.groups[key]
    return c and c.newRow == true or false
end

function Groups.SetNewRow(key, value)
    local c = EnsureConfig(key)
    c.newRow = value and true or nil
    CleanConfig(key)
    Refresh()
end

-- Sortierung innerhalb der Gruppe ("type", "quality", "name", "count" oder aus ns.Knowledge).
function Groups.SortMode(key)
    local c = ns.db.groups[key]
    return (c and c.sort) or ns.S.sortMode or "type"
end

function Groups.SetSortMode(key, mode)
    local c = EnsureConfig(key)
    c.sort = (mode and mode ~= (ns.S.sortMode or "type")) and mode or nil
    CleanConfig(key)
    Refresh()
end

-- Hat irgendeine Gruppe eine eigene Sortierung? (für "alle zurücksetzen" in der Leiste)
function Groups.AnyOwnSort()
    for _, c in pairs(ns.db.groups) do
        if c.sort then return true end
    end
    return false
end

function Groups.ClearOwnSort()
    for key, c in pairs(ns.db.groups) do
        c.sort = nil
        CleanConfig(key)
    end
    Refresh()
end

-- Unterteilen nach einem Merkmal des Item-Wissens (z. B. Beruf, Platz, Stufe),
-- in zwei Stufen: level 1 (c.sub) und level 2 (c.sub2, z. B. Waffe › Schwert).
function Groups.Subdivide(key, level)
    local c = ns.db.groups[key]
    if not c then return nil end
    if level == 2 then return c.sub and c.sub2 or nil end
    return c.sub
end

function Groups.SetSubdivide(key, facet, level, facet2)
    local c = EnsureConfig(key)
    facet = (facet and facet ~= "") and facet or nil
    if level == 2 then
        c.sub2 = facet
    else
        c.sub = facet
        if facet2 ~= nil then c.sub2 = facet2 ~= "" and facet2 or nil end
        if not facet or c.sub2 == facet then c.sub2 = nil end
    end
    CleanConfig(key)
    Refresh()
end

-- Zugeklappt wird je Ansicht getrennt gemerkt: Tasche, Bank und Fenster.
local function CollapsedTable(viewKey)
    local all = ns.db.collapsedBy
    local t = all[viewKey or "bag"]
    if not t then
        t = {}
        all[viewKey or "bag"] = t
    end
    return t
end

function Groups.IsCollapsed(viewKey, key)
    return CollapsedTable(viewKey)[key] == true
end

function Groups.ToggleCollapsed(viewKey, key)
    local t = CollapsedTable(viewKey)
    t[key] = not t[key] or nil
    Refresh()
end

-- Alle angegebenen Gruppen einer Ansicht zu- oder aufklappen.
function Groups.SetAllCollapsed(viewKey, keys, collapsed)
    local t = CollapsedTable(viewKey)
    for _, key in ipairs(keys or {}) do t[key] = collapsed and true or nil end
    Refresh()
end

-- „Alles zuklappen“ für alle Ansichten (Befehl /eb zuklappen, V-050). Gruppen der gespeicherten Reihenfolge
-- sofort; Untergruppen („Unterteilen nach“, Schlüssel „Gruppe|Merkmal“) kennt erst die Anordnung – darum merkt
-- sich jede Ansicht den Wunsch und klappt beim nächsten Anordnen alles zu, was sie dann zeigt (Render.Flow).
local VIEW_KEYS = { "bag", "reagent", "bank", "guild", "window" }   -- reagent: Abschnitt Reagenzientasche (Reagent.lua)
Groups.VIEW_KEYS = VIEW_KEYS
local pendingCollapse = {}

function Groups.CollapseEverything()
    local keys = Groups.OrderKeys()
    for _, viewKey in ipairs(VIEW_KEYS) do
        local t = CollapsedTable(viewKey)
        for _, key in ipairs(keys) do t[key] = true end
        pendingCollapse[viewKey] = true
    end
    Refresh()
end

-- Alle Gruppen aller Ansichten aufklappen (Befehl /eb aufklappen).
function Groups.ExpandEverything()
    for _, t in pairs(ns.db.collapsedBy) do wipe(t) end
    wipe(pendingCollapse)
    Refresh()
end

-- Von Render.Flow: steht „alles zuklappen“ für diese Ansicht noch aus, gilt es für alle Gruppen, die sie jetzt
-- anordnet. → true, wenn etwas zugeklappt wurde
function Groups.ApplyPendingCollapse(viewKey, groups)
    viewKey = viewKey or "bag"
    if not pendingCollapse[viewKey] then return false end
    pendingCollapse[viewKey] = nil
    local t = CollapsedTable(viewKey)
    for _, g in ipairs(groups or {}) do
        if g.groupKey then t[g.groupKey] = true end
    end
    return true
end

function Groups.Reset(key)
    ns.db.groups[key] = nil
    for _, t in pairs(ns.db.collapsedBy) do t[key] = nil end
    Refresh()
end

---------------------------------------------------------------------------
-- Reihenfolge
---------------------------------------------------------------------------

local index, ruleCache

local function Rebuild()
    index = {}
    for i, key in ipairs(ns.db.order) do index[key] = i end
    ruleCache = nil
end

local function Order()
    if not ns.db.order then
        local order = {}
        for _, key in ipairs(ns.CATEGORY_ORDER) do order[#order + 1] = key end
        order[#order + 1] = "locked"
        ns.db.order = order
        index = nil
    end
    if not index then Rebuild() end
    return ns.db.order
end

-- Kopie der Reihenfolge aller Gruppen (legt sie bei einem frischen Profil an).
function Groups.OrderKeys()
    local keys = {}
    for i, key in ipairs(Order()) do keys[i] = key end
    return keys
end

-- Neue Schlüssel an eine sinnvolle Stelle setzen.
local function Insert(key)
    local order = Order()
    local pos
    if Groups.CustomID(key) then
        pos = index.junk                         -- eigene Gruppen vor "Plunder"
    elseif key:match("^empty:") then
        pos = (index.empty or #order) + 1        -- Spezialtaschen hinter "Frei"
        while order[pos] and order[pos]:match("^empty:") do pos = pos + 1 end
    else
        -- Eingebaute Gruppe aus einer neueren Version: vor ihren Standard-Nachfolger.
        local found = false
        for _, k in ipairs(ns.CATEGORY_ORDER) do
            if found and index[k] then
                pos = index[k]
                break
            end
            if k == key then found = true end
        end
    end
    table.insert(order, pos or (#order + 1), key)
    Rebuild()
end

function Groups.Rank(key)
    Order()
    if not index[key] then Insert(key) end
    return index[key]
end

function Groups.Move(key, target, after)
    if not key or not target or key == target then return end
    local order = Order()
    Groups.Rank(key)
    Groups.Rank(target)
    table.remove(order, index[key])
    Rebuild()
    table.insert(order, index[target] + (after and 1 or 0), key)
    Rebuild()
    Refresh()
end

-- Nach nachgeladenem Item-Wissen: Regeln beim nächsten Einsortieren neu auswerten.
function Groups.ClearRuleCache()
    ruleCache = nil
end

-- Nach einem Wechsel des Layout-Profils (Profiles.lua): Reihenfolge und Regeln neu lesen.
function Groups.ResetIndex()
    index = nil
    ruleCache = nil
end

function Groups.ResetOrder()
    ns.db.order = nil
    index = nil
    ruleCache = nil
    Refresh()
end

-- Eigene Gruppen in gespeicherter Reihenfolge.
function Groups.CustomKeys()
    local keys = {}
    for id in pairs(ns.db.custom) do keys[#keys + 1] = "custom:" .. id end
    table.sort(keys, function(a, b) return Groups.Rank(a) < Groups.Rank(b) end)
    return keys
end

-- Eigene Gruppen mit Regeln, in Reihenfolge (für das Einsortieren).
function Groups.RuleGroups()
    if ruleCache then return ruleCache end
    -- Erst alle Schlüssel holen: das kann die Reihenfolge ergänzen (und den Speicher leeren).
    local keys = Groups.CustomKeys()
    local list = {}
    for _, key in ipairs(keys) do
        local custom = ns.db.custom[Groups.CustomID(key)]
        if custom and ns.HasRules(custom.rules) then
            list[#list + 1] = { key = key, rules = custom.rules }
        end
    end
    ruleCache = list
    return list
end

---------------------------------------------------------------------------
-- Eingabe- und Bestätigungsfenster
---------------------------------------------------------------------------

-- Eingabe- und Bestätigungsfenster aus ezCore (vorher stand derselbe Code hier und in ezChat).
local function AskText(prompt, current, callback)
    ezCore.AskText(prompt, current, callback, 40)
end

local function Confirm(prompt, callback)
    ezCore.Confirm(prompt, callback)
end

---------------------------------------------------------------------------
-- Umbenennen, neue und gelöschte Gruppen
---------------------------------------------------------------------------

function Groups.Rename(key)
    local current = Groups.Label(key)
    AskText(L.POPUP_RENAME:format(current), current, function(name)
        local id = Groups.CustomID(key)
        if id then
            if name ~= "" and ns.db.custom[id] then ns.db.custom[id].label = name end
        else
            local c = EnsureConfig(key)
            c.label = (name ~= "" and name ~= Groups.DefaultLabel(key)) and name or nil
            CleanConfig(key)
        end
        Refresh()
    end)
end

function Groups.NewGroup(onCreated)
    AskText(L.POPUP_NEW_GROUP, L.NEW_GROUP_DEFAULT, function(name)
        if name == "" then return end
        local id = tostring((ns.db.customNext or 0) + 1)
        ns.db.customNext = tonumber(id)
        ns.db.custom[id] = { label = name }
        local key = "custom:" .. id
        Groups.Rank(key)
        if onCreated then onCreated(key) end
        Refresh()
    end)
end

function Groups.Delete(key)
    local id = Groups.CustomID(key)
    if not id then return end
    Confirm(L.POPUP_DELETE_GROUP:format(Groups.Label(key)), function()
        ns.db.custom[id] = nil
        ns.db.groups[key] = nil
        for _, t in pairs(ns.db.collapsedBy) do t[key] = nil end
        for itemID, assigned in pairs(ns.db.assign) do
            if assigned == key then ns.db.assign[itemID] = nil end
        end
        local order = Order()
        for i = #order, 1, -1 do
            if order[i] == key then table.remove(order, i) end
        end
        Rebuild()
        Refresh()
    end)
end

---------------------------------------------------------------------------
-- Regeln eigener Gruppen
---------------------------------------------------------------------------

local function Rules(key)
    local custom = ns.db.custom[Groups.CustomID(key)]
    if not custom then return nil end
    custom.rules = custom.rules or {}
    return custom.rules
end

local function RulesChanged()
    ruleCache = nil
    Refresh()
end

-- Namen der Arten und Unterarten: eine Fassung in ezCore (Core.ItemClassName), hier nur Weiterleitungen.
local function ClassName(classID)
    return ezCore.ItemClassName(classID)
end

local function SubClassName(classID, subClassID)
    return ezCore.ItemClassName(classID, subClassID)
end

-- Gegenstandsarten, die es auf diesem Client gibt (Name nicht leer).
local function ItemClasses()
    local list = {}
    for classID = 0, 19 do
        local name = ClassName(classID)
        if name and name ~= "" then
            local subs = {}
            for subClassID = 0, 25 do
                local subName = SubClassName(classID, subClassID)
                if subName and subName ~= "" and subName ~= name then
                    subs[#subs + 1] = { id = subClassID, name = subName }
                end
            end
            list[#list + 1] = { id = classID, name = name, subs = subs }
        end
    end
    return list
end

-- Alle Merkmale, die bei deinen Gegenständen vorkommen (Taschen, Bank, Post, angelegt, Gildenbank).
function Groups.KnownTags()
    local K = ns.Knowledge
    if not (K and K.Get and K.Tags) then return {} end
    local seen, list, done = {}, {}, {}
    local function scan(items)
        if type(items) ~= "table" then return end
        for _, e in ipairs(items) do
            local itemID = ezCore.ItemID(e.i or e.l)   -- V-176
            itemID = ns.PlainID(itemID)
            if itemID and not done[itemID] then
                done[itemID] = true
                local ok, facts = pcall(K.Get, e.l or itemID)
                local ok2, tags = false, nil
                if ok and facts then ok2, tags = pcall(K.Tags, facts) end
                if ok2 and type(tags) == "table" then
                    for _, tag in ipairs(tags) do
                        local family = type(tag) == "table" and tag.key and (tag.key:match("^(%a+):") or "other")
                        -- "class:"/"sub:" doppeln die Regel "Gegenstandsart", "usable"/"unusable" ändern sich mit der Stufe.
                        if family and family ~= "class" and family ~= "sub" and not seen[tag.key]
                            and tag.key ~= "usable" and tag.key ~= "unusable" and tag.key ~= "later" then
                            seen[tag.key] = true
                            list[#list + 1] = { key = tag.key, label = tag.label or tag.key, family = family,
                                familyLabel = L["TAGS_" .. family] ~= ("TAGS_" .. family) and L["TAGS_" .. family] or family }
                        end
                    end
                end
            end
        end
    end
    local me = ezCore.Chars()[ns.charKey]
    if me and me.items then
        for _, location in pairs(me.items) do scan(location) end
    end
    for _, guild in pairs(ezCore.Guilds()) do
        for _, tab in pairs(guild.tabs or {}) do scan(tab.items) end
    end
    table.sort(list, function(a, b)
        if a.familyLabel ~= b.familyLabel then return a.familyLabel < b.familyLabel end
        return a.label < b.label
    end)
    return list
end

local function AddRulesMenu(root, key)
    local rules = Rules(key)
    if not rules then return end
    local menu = root:CreateButton(L.MENU_RULES)

    local function IsClass(token) return rules.classes and rules.classes[token] == true end
    local function ToggleClass(token)
        rules.classes = rules.classes or {}
        rules.classes[token] = not rules.classes[token] or nil
        RulesChanged()
    end

    local kinds = menu:CreateButton(L.MENU_RULE_KIND)
    -- Design-System 2.11 (Mehrfachauswahl): ein Haken „Alle“ (seit 21.11.2026). Einschalten nimmt jede Art ganz (die
    -- Haken „Alle <Art>“), Ausschalten nimmt jeden Haken heraus, auch die der Unterarten. Gemerkt in den Regeln der
    -- Gruppe (2.12).
    local classes = ItemClasses()
    local whole, every = {}, {}
    for _, class in ipairs(classes) do
        whole[#whole + 1] = tostring(class.id)
        every[#every + 1] = tostring(class.id)
        for _, s in ipairs(class.subs) do every[#every + 1] = class.id .. ":" .. s.id end
    end
    local function SetClass(token, on)
        rules.classes = rules.classes or {}
        rules.classes[token] = on or nil
    end
    local function ClassesChanged()
        if rules.classes and not next(rules.classes) then rules.classes = nil end
        RulesChanged()
    end
    if #classes >= 3 then
        ezCore.Menu.AllToggle(kinds, whole, IsClass, SetClass, { offList = every, after = ClassesChanged })
        kinds:CreateDivider()
    end
    for _, class in ipairs(classes) do
        local classToken = tostring(class.id)
        if #class.subs == 0 then
            kinds:CreateCheckbox(class.name, IsClass, ToggleClass, classToken)
        else
            local sub = kinds:CreateButton(class.name)
            sub:CreateCheckbox(L.MENU_RULE_ALL:format(class.name), IsClass, ToggleClass, classToken)
            sub:CreateDivider()
            for _, s in ipairs(class.subs) do
                sub:CreateCheckbox(s.name, IsClass, ToggleClass, class.id .. ":" .. s.id)
            end
        end
    end

    menu:CreateCheckbox(L.MENU_RULE_BOE, function() return rules.boe == true end, function()
        rules.boe = not rules.boe or nil
        RulesChanged()
    end)

    local quality = menu:CreateButton(L.MENU_RULE_QUALITY)
    local function IsQuality(q) return (rules.minQuality or -1) == q end
    local function SetQuality(q)
        rules.minQuality = q >= 0 and q or nil
        RulesChanged()
    end
    quality:CreateRadio(L.MENU_RULE_QUALITY_ANY, IsQuality, SetQuality, -1)
    for q = 0, 5 do
        -- Name und Farbe der Qualität aus ezCore (Core.QualityText; Gesamtreview 18.11.2026, T16-6), keine eigene
        -- CreateColor (Design-System 2.5)
        local text = ezCore.QualityText(q)
        quality:CreateRadio(text, IsQuality, SetQuality, q)
    end

    local textLabel = rules.text and rules.text ~= "" and L.MENU_RULE_TEXT_SET:format(rules.text) or L.MENU_RULE_TEXT
    menu:CreateButton(textLabel, function()
        AskText(L.POPUP_RULE_TEXT, rules.text or "", function(text)
            rules.text = text ~= "" and text or nil
            RulesChanged()
        end)
    end)

    -- Merkmale aus dem Item-Wissen (Beruf, Platz, Material, Buff-Essen, für Klasse ...).
    local known = Groups.KnownTags()
    if #known > 0 then
        local tagsMenu = menu:CreateButton(L.MENU_RULE_TAGS)
        local function IsTag(tag) return rules.tags and rules.tags[tag] == true end
        local function ToggleTag(tag)
            rules.tags = rules.tags or {}
            rules.tags[tag] = not rules.tags[tag] or nil
            if not next(rules.tags) then rules.tags = nil end
            RulesChanged()
        end
        -- Design-System 2.11: ein Haken „Alle“ über alle Schlagwörter (alle Familien).
        if #known >= 3 then
            local keys = {}
            for i, tag in ipairs(known) do keys[i] = tag.key end
            ezCore.Menu.AllToggle(tagsMenu, keys, IsTag, function(tag, on)
                rules.tags = rules.tags or {}
                rules.tags[tag] = on or nil
            end, { after = function()
                if rules.tags and not next(rules.tags) then rules.tags = nil end
                RulesChanged()
            end })
            tagsMenu:CreateDivider()
        end
        local sub, lastFamily
        for _, tag in ipairs(known) do
            if tag.family ~= lastFamily then
                sub = tagsMenu:CreateButton(tag.familyLabel)
                lastFamily = tag.family
            end
            sub:CreateCheckbox(tag.label, IsTag, ToggleTag, tag.key)
        end
    end
    menu:CreateCheckbox(L.MENU_RULE_AND, function() return rules.mode == "and" end, function()
        rules.mode = rules.mode ~= "and" and "and" or nil
        RulesChanged()
    end)

    menu:CreateDivider()
    menu:CreateButton(L.MENU_RULE_CLEAR, function()
        local custom = ns.db.custom[Groups.CustomID(key)]
        if custom then custom.rules = nil end
        RulesChanged()
    end)
end

---------------------------------------------------------------------------
-- Gegenstände zuweisen
---------------------------------------------------------------------------

function Groups.Assign(itemID, value, link, quality)
    local text = link or tostring(itemID)
    if value == "auto" or not value then
        ns.db.assign[itemID] = nil
        ns.Print(L.ASSIGN_RESET:format(text))
    else
        ns.db.assign[itemID] = value
        if value == "junk" then
            ns.Print(L.MARKED_JUNK:format(text))
            if (quality or 0) >= 3 then ns.Print(L.MARKED_RARE_WARN) end
        else
            ns.Print(L.ASSIGNED:format(text, Groups.Label(value)))
        end
    end
    Refresh()
end

-- Gegenstand am Mauszeiger auf einen Gruppentitel fallen lassen.
function Groups.DropCursorItem(key)
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" or not itemID or not ns.IsAssignable(key) then return false end
    local quality = link and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    ClearCursor()
    Groups.Assign(itemID, key, link, quality)
    return true
end

---------------------------------------------------------------------------
-- Im Auktionshaus suchen (ezAuction, AUC-18)
---------------------------------------------------------------------------

-- ezAuctions Suche, wenn ezAuction läuft: ezCore.API("ezAuction").Search(Link oder ID) → true, Suchbegriff |
-- false, Grund ("closed" Auktionshaus zu, "item" Name noch nicht geladen, "missing" Client ohne Suche, "other" Ansicht
-- eines fremden Addons – der Hinweis sagt, erst einen von Blizzards Reitern zu wählen; Welle 23, A5).
local function AuctionSearch()
    local api = ezCore.API("ezAuction")
    local search = api and api.Search
    return type(search) == "function" and search or nil
end

-- Bietet das Menü am Gegenstand „Im Auktionshaus suchen“ an? Nur, wenn ezAuction läuft.
function Groups.CanSearchAuction()
    return AuctionSearch() ~= nil
end

-- Sucht den Gegenstand (Link oder ID) im Auktionshaus. Geht es nicht, sagt ein Hinweis in der Bildschirmmitte,
-- warum. → true, Suchbegriff | false, Grund (wie oben; dazu "none" = ezAuction läuft nicht, "error")
function Groups.SearchAuction(item)
    local search = AuctionSearch()
    if not search then return false, "none" end
    local okCall, found, detail = pcall(search, item)
    if not okCall then
        ns.Error(found, "AuctionSearch")
        return false, "error"
    end
    if found == true then return true, detail end
    local reason = type(detail) == "string" and detail or "item"
    local key = "AUCTION_SEARCH_" .. reason
    local text = L[key]
    if text == key then text = L.AUCTION_SEARCH_item end
    ezCore.ErrorMessage(text, ns.TipRGB("normal"))
    return false, reason
end

---------------------------------------------------------------------------
-- Im Auktionshaus verkaufen (ezAuction, AH-26)
---------------------------------------------------------------------------

-- ezCore.API("ezAuction").Sell(tasche, platz) → true | false, Grund ("closed" Auktionshaus zu, "other" Ansicht eines
-- fremden Addons, "item" nichts Verkaufbares, "missing" Client ohne Einlegen, "t1" ezAuction hebt den Gegenstand in
-- seiner Taschenliste nur hervor; siehe ezAuction/SellTab.lua). Sell handelt sofort – es legt den Gegenstand in
-- Blizzards Verkaufsbereich; eingestellt wird weiter nur mit Blizzards Knopf. Darum fragt ezBag es erst beim Klick.
-- Ohne Folgen vorab prüfbar: ein Platz in einer getragenen Tasche ("bag": nicht aus Bank, Gildenbank oder dem
-- ezBag-Fenster – auch nicht aus dessen Bank-Plätzen, die Taschen- und Platznummer der Bank mitgeben; geprüft vor
-- "closed", weil an der Bank das Auktionshaus immer zu ist und "bag" der Grund ist, der bleibt) und Auktionshaus offen
-- ("closed"). Lehnt Sell einen Platz mit "item" oder "missing" ab, merkt ezBag sich das für
-- diesen Platz und Gegenstand, bis das Auktionshaus auf- oder zugeht – der Eintrag ist dann ausgegraut mit dem Grund.
local function AuctionSell()
    local api = ezCore.API("ezAuction")
    local sell = api and api.Sell
    return type(sell) == "function" and sell or nil
end

-- Bietet das Menü am Gegenstand „Im Auktionshaus verkaufen“ an? Nur, wenn ezAuction die Schnittstelle Sell hat.
function Groups.CanSellAuction()
    return AuctionSell() ~= nil
end

-- Auktionshaus offen? Die eine Prüfung steht in ezCore (Core.AuctionHouseOpen, Welle 23 A7: Blizzards Fenster, sonst
-- AUCTION_HOUSE_SHOW/CLOSED); Groups.AuctionHouseOpen bleibt als Weiterleitung.
function Groups.AuctionHouseOpen()
    return ezCore.AuctionHouseOpen() == true
end

local sellRefused = {}                              -- ["tasche:platz"] = { itemID, reason }
local SELL_REMEMBER = { item = true, missing = true }

local function SlotKey(bag, slot) return bag .. ":" .. slot end

-- Liegt der Platz in einer getragenen Tasche? Dieselbe Liste wie beim Plunder-Verkauf (ezCore.BagList("sell")).
local function InCarriedBag(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return false end
    for _, id in ipairs(ezCore.BagList("sell")) do
        if id == bag then return true end
    end
    return false
end

-- → nil (Eintrag nutzbar) oder der Grund, warum er ausgegraut ist ("none" = ezAuction ohne Sell, "bag", "closed",
-- oder die gemerkte Absage "item"/"missing")
function Groups.SellAuctionBlocked(bag, slot, itemID)
    if not AuctionSell() then return "none" end
    if not InCarriedBag(bag, slot) then return "bag" end
    if not Groups.AuctionHouseOpen() then return "closed" end
    local refused = sellRefused[SlotKey(bag, slot)]
    if refused and refused.itemID == itemID then return refused.reason end
    return nil
end

-- Texte, die „Im Auktionshaus suchen“ schon hat (eine Fassung je Wortlaut)
local SELL_SHARED_TEXT = { closed = "AUCTION_SEARCH_closed" }

-- Text zu einem Grund (unbekannte Gründe: der allgemeine Text zu "item")
function Groups.SellAuctionReason(reason)
    local key = SELL_SHARED_TEXT[reason] or ("AUCTION_SELL_" .. tostring(reason))
    local text = L[key]
    if text == nil or text == key then text = L.AUCTION_SELL_item end
    return text
end

-- Legt den Gegenstand dieses Taschenplatzes über ezAuction in Blizzards Verkaufsbereich. Geht es nicht, sagt ein
-- Hinweis in der Bildschirmmitte, warum. → true | false, Grund (wie oben; dazu "error")
function Groups.SellAuction(bag, slot, itemID)
    local blocked = Groups.SellAuctionBlocked(bag, slot, itemID)
    if blocked then
        if blocked ~= "none" then ezCore.ErrorMessage(Groups.SellAuctionReason(blocked), ns.TipRGB("normal")) end
        return false, blocked
    end
    local okCall, done, detail = pcall(AuctionSell(), bag, slot)
    if not okCall then
        ns.Error(done, "AuctionSell")
        return false, "error"
    end
    if done == true then return true end
    local reason = type(detail) == "string" and detail or "item"
    if SELL_REMEMBER[reason] then sellRefused[SlotKey(bag, slot)] = { itemID = itemID, reason = reason } end
    ezCore.ErrorMessage(Groups.SellAuctionReason(reason), ns.TipRGB("normal"))
    return false, reason
end

local function ForgetSellRefused() sellRefused = {} end
ns.On("AUCTION_HOUSE_SHOW", ForgetSellRefused)
ns.On("AUCTION_HOUSE_CLOSED", ForgetSellRefused)

-- Tooltip an einem Menü-Eintrag (Blizzards Menü: elementDescription:SetTooltip) – seit Welle 7 über ezCores eine
-- Fassung Core.Menu.Tip (GEAR-15; vorher stand hier eine eigene kleine Kopie, ebenso in ezCombat).
local function MenuTip(description, title, text)
    return ezCore.Menu.Tip(description, title, text)
end

-- Menü für einen Gegenstand (aus Tasche, Bank oder dem ezBag-Fenster). bag/slot für „Im Auktionshaus verkaufen“,
-- soweit der Platz sie kennt (Tasche, Bank-Plätze des ezBag-Fensters), sonst nil; verkauft wird nur aus der Tasche.
function Groups.OpenItemMenuFor(owner, itemID, link, quality, bag, slot)
    itemID = ns.PlainID(itemID)
    if not itemID then return end

    local color = type(link) == "string" and link:match("^(|c%x%x%x%x%x%x%x%x)") or ""
    local title = color .. (ns.ItemName(link) or L.MENU_TITLE_FALLBACK) .. (color ~= "" and "|r" or "")

    local function IsSelected(value)
        return (ns.db.assign[itemID] or "auto") == value
    end
    local function SetSelected(value)
        Groups.Assign(itemID, value, link, quality)
    end

    local opened = ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(title)
        root:CreateTitle(L.MENU_GROUP)
        root:CreateRadio(L.MENU_AUTO, IsSelected, SetSelected, "auto")
        root:CreateDivider()
        for _, key in ipairs(ns.ASSIGNABLE) do
            root:CreateRadio(Groups.Label(key), IsSelected, SetSelected, key)
        end
        local customs = Groups.CustomKeys()
        if #customs > 0 then
            root:CreateDivider()
            for _, key in ipairs(customs) do
                root:CreateRadio(Groups.Label(key), IsSelected, SetSelected, key)
            end
        end
        root:CreateDivider()
        root:CreateButton(L.MENU_NEW_GROUP, function()
            Groups.NewGroup(function(key) Groups.Assign(itemID, key, link, quality) end)
        end)
        -- Nur mit ezAuction: den Gegenstand im Auktionshaus suchen (bei geschlossenem Auktionshaus ein Hinweis).
        local canSearch, canSell = Groups.CanSearchAuction(), Groups.CanSellAuction()
        if canSearch or canSell then root:CreateDivider() end
        if canSearch then
            MenuTip(root:CreateButton(L.MENU_AUCTION_SEARCH, function() Groups.SearchAuction(link or itemID) end),
                L.MENU_AUCTION_SEARCH, L.MENU_AUCTION_SEARCH_TIP)
        end
        -- Daneben: in den Verkaufsbereich legen – nur bei offenem Auktionshaus und aus der Tasche, sonst ausgegraut
        -- mit dem Grund im Tooltip (AH-26).
        if canSell then
            local blocked = Groups.SellAuctionBlocked(bag, slot, itemID)
            local entry = root:CreateButton(L.MENU_AUCTION_SELL, function() Groups.SellAuction(bag, slot, itemID) end)
            if blocked and type(entry) == "table" and type(entry.SetEnabled) == "function" then entry:SetEnabled(false) end
            local tip = L.MENU_AUCTION_SELL_TIP
            if blocked then tip = tip .. "\n\n" .. Groups.SellAuctionReason(blocked) end
            MenuTip(entry, L.MENU_AUCTION_SELL, tip)
        end
    end)
    -- Ohne Menü (MenuUtil fehlt): Plunder-Markierung umschalten.
    if not opened then
        local isJunk = ns.IsJunk({ itemID = itemID, quality = quality })
        Groups.Assign(itemID, isJunk and (quality == 0 and "misc" or "auto") or "junk", link, quality)
    end
end

function Groups.OpenItemMenu(button)
    local bag, slot = button:GetBagID(), button:GetID()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = ns.ItemIDOf(info)
    if not itemID then return end
    Groups.OpenItemMenuFor(button, itemID, info.hyperlink, info.quality, bag, slot)
end

---------------------------------------------------------------------------
-- Menü am Gruppentitel (Rechtsklick)
---------------------------------------------------------------------------

-- „Neu“ leeren, ohne die Tasche zu schließen (BetterBags „Clear new“): ezBags Merkliste und
-- Blizzards eigene Neu-Markierung an den Plätzen.
function Groups.ClearNew()
    ns.ClearNewItems()
    if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
    if ns.Layout and ns.Layout.Refresh then ns.Layout.Refresh(true) end
end

-- Inhalt des Gruppen-Menüs – eine Fassung für den Rechtsklick auf den Titel (OpenHeaderMenu) und für das Untermenü
-- „Gruppe anpassen“ im Knopf „Tasche, Gruppe oder Bank“ der Werkzeugleiste (sichtbarer Weg, Leitlinie 3, V-044).
function Groups.FillHeaderMenu(root, key, viewKey, collapseKey, allKeys)
    collapseKey = collapseKey or key

    local function IsSort(mode) return Groups.SortMode(key) == mode end
    local function SetSort(mode) Groups.SetSortMode(key, mode) end
    local function IsSub(facet) return (Groups.Subdivide(key, 1) or "") == facet end
    local function SetSub(facet) Groups.SetSubdivide(key, facet, 1) end
    local function IsSub2(facet) return (Groups.Subdivide(key, 2) or "") == facet end
    local function SetSub2(facet) Groups.SetSubdivide(key, facet, 2) end
    local function IsPreset() return Groups.Subdivide(key, 1) == "class" and Groups.Subdivide(key, 2) == "type" end

    do
        root:CreateTitle(Groups.Label(key))
        if key == "junk" and ns.AtMerchant() then
            root:CreateButton(L.MENU_SELL_NOW, function() ns.Junk.SellNow(true) end)
            root:CreateDivider()
        end
        if key == "new" then
            root:CreateButton(L.MENU_CLEAR_NEW, Groups.ClearNew)
            root:CreateDivider()
        end
        -- Platz schaffen: billigste Gegenstände zum Zerstören bzw. Verkaufen (Space.lua)
        if (key == "junk" or key == "empty") and viewKey == "bag" and ns.Space then
            ns.Space.AddMenu(root)
            root:CreateDivider()
        end
        root:CreateButton(Groups.IsCollapsed(viewKey, collapseKey) and L.MENU_EXPAND or L.MENU_COLLAPSE,
            function() Groups.ToggleCollapsed(viewKey, collapseKey) end)
        if allKeys and #allKeys > 1 then
            root:CreateButton(L.MENU_COLLAPSE_ALL, function() Groups.SetAllCollapsed(viewKey, allKeys, true) end)
            root:CreateButton(L.MENU_EXPAND_ALL, function() Groups.SetAllCollapsed(viewKey, allKeys, false) end)
        end
        root:CreateDivider()
        root:CreateButton(L.MENU_RENAME, function() Groups.Rename(key) end)

        local sort = root:CreateButton(L.MENU_SORT)
        for _, mode in ipairs(ns.Render.SortModes()) do
            sort:CreateRadio(mode.label, IsSort, SetSort, mode.key)
        end
        local K = ns.Knowledge
        if K and type(K.Facets) == "table" and #K.Facets > 0 then
            local sub = root:CreateButton(L.MENU_SUBDIVIDE)
            sub:CreateRadio(L.MENU_SUBDIVIDE_NONE, IsSub, SetSub, "")
            -- Schnellwahl: Hauptart › Unterart (z. B. Ausrüstung › Waffe › Schwert).
            sub:CreateRadio(L.MENU_SUBDIVIDE_PRESET, IsPreset, function()
                Groups.SetSubdivide(key, "class", 1, "type")
            end, "preset")
            sub:CreateDivider()
            for _, facet in ipairs(K.Facets) do
                if facet.key then sub:CreateRadio(facet.label or facet.key, IsSub, SetSub, facet.key) end
            end
            local first = Groups.Subdivide(key, 1)
            if first then
                local sub2 = root:CreateButton(L.MENU_SUBDIVIDE2)
                sub2:CreateRadio(L.MENU_SUBDIVIDE_NONE, IsSub2, SetSub2, "")
                for _, facet in ipairs(K.Facets) do
                    if facet.key and facet.key ~= first then
                        sub2:CreateRadio(facet.label or facet.key, IsSub2, SetSub2, facet.key)
                    end
                end
            end
        end
        root:CreateCheckbox(L.MENU_NEW_ROW, function() return Groups.NewRow(key) end,
            function() Groups.SetNewRow(key, not Groups.NewRow(key)) end)

        if Groups.CustomID(key) then AddRulesMenu(root, key) end

        root:CreateButton(L.MENU_RESET_GROUP, function() Groups.Reset(key) end)
        root:CreateDivider()
        root:CreateButton(L.MENU_NEW_GROUP, function() Groups.NewGroup() end)
        if Groups.CustomID(key) then
            root:CreateButton(L.MENU_DELETE_GROUP, function() Groups.Delete(key) end)
        end
        root:CreateButton(L.MENU_RESET_ORDER, function() Groups.ResetOrder() end)
    end
end

function Groups.OpenHeaderMenu(owner, key, viewKey, collapseKey, allKeys)
    return ezCore.Menu.Open(owner, function(root)
        Groups.FillHeaderMenu(root, key, viewKey, collapseKey, allKeys)
    end)
end

-- Untermenü „Gruppe anpassen“ für die Werkzeugleiste: je Gruppe der Ansicht dasselbe Menü wie am Titel, dazu
-- „Neue Gruppe …“ und „Reihenfolge zurücksetzen“. groups = Gruppen der Anordnung (out.groups, out.chips);
-- Untergruppen („Unterteilen nach“) zählen zu ihrer Elterngruppe. → Zahl der Gruppen im Menü
function Groups.AddEditMenu(root, viewKey, groups, allKeys)
    local sub = root:CreateButton(L.TB_GROUP_EDIT)
    local seen, n = {}, 0
    for _, g in ipairs(groups or {}) do
        local key = g.parentKey or g.groupKey
        if key and not seen[key] then
            seen[key] = true
            n = n + 1
            local entry = sub:CreateButton(Groups.Label(key))
            -- Zuklappen gilt der (ersten) sichtbaren Gruppe dieses Namens – bei Unterteilung der ersten Untergruppe.
            Groups.FillHeaderMenu(entry, key, viewKey, g.groupKey, allKeys)
        end
    end
    if n > 0 then sub:CreateDivider() end
    sub:CreateButton(L.MENU_NEW_GROUP, function() Groups.NewGroup() end)
    sub:CreateButton(L.MENU_RESET_ORDER, function() Groups.ResetOrder() end)
    return n
end
