local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rezeptliste nach der Stufe des hergestellten Gegenstands (Nutzer am 24.11.2026, wörtlich: „eine sortiermöglichkeit nach
    lvl (herstelltbares item) einbauen?“; Pfeil und Stufe je Zeile: Rows.lua).

    Blizzards Liste (Forever-Quelle Blizzard_ProfessionsTemplates: Professions.GenerateCraftingDataProvider) ist ein Baum aus
    Kategorien; eine eigene Reihenfolge hieße, seinen Knoten eine Sortierung zu geben – ein Wert in Blizzards Tabellen
    (Leitlinie 5), den Blizzard beim Auswählen und Herstellen weiterliest. Darum bleibt Blizzards Liste, wie sie ist:
    Solange eine Sortierung gewählt ist, liegt ezCrafts eigene Liste an genau ihrer Stelle (Kind von Blizzards RecipeList,
    Blizzards Zeilen- und Kategorievorlagen, Blizzards ScrollBox), und Blizzards ScrollBox wird nur durchsichtig. Gelesen
    werden ihre Knoten bei jedem Neuaufbau (hooksecurefunc auf SetDataProvider): Suche, Filter, Favoriten und „nicht gelernt“
    gelten also weiter. In Blizzards Reihenfolge (ab Werk) ist nichts davon zu sehen.

    Auswahl   Ein Klick wählt das Rezept über Blizzards eigene Auswahl der Rezeptliste (RecipeList:SelectRecipe, dieselbe,
              die Blizzards Seite nimmt); die gewählte Zeile folgt Blizzards Nachricht „OnRecipeSelected“. Der frühere Weg
              C_TradeSkillUI.OpenRecipe wählte im Spieltest vom 25.11.2026 nichts (Ursache unbekannt). Ausnahme 5 von
              Leitlinie 5 (Nutzer am 25.11.2026: „Ja, Ausnahme (Empfohlen)“): Was Blizzard dabei in seine Felder schreibt
              (gewähltes Rezept, Rezeptbereich), gilt bis /reload als von ezCraft gesetzt. Herstellen ist laut
              TradeSkillUIDocumentation.lua nicht eingeschränkt, und die Berufe-Reiter richtet Blizzard in eigenen Ereignissen
              ein. Darum: ab Werk aus, nie im Kampf, und meldet Blizzard danach eine blockierte Aktion von ezCraft, bleibt bis
              /reload Blizzards Liste (Sort.OnBlocked).
              Umschalt-Klick (Link, Verfolgen) und Rechtsklick (Favorit) wie in Blizzards Zeilen.
    Zugeklapptes  Blizzard wählt nur, was in seiner Liste aufgeklappt ist (SelectElementDataByPredicate sucht ohne
              Zugeklapptes). Nur solche Zeilen stehen darum in der geordneten Liste – ein Favorit in „Favoriten“ und in seiner
              eigenen Kategorie, je nachdem, was offen ist. Eine Zeile am Ende nennt die Zahl der Rezepte, die ganz fehlen.
              Aufklappen geht nur bei Blizzard.
    Ordnung   „hohe zuerst“ oder „niedrige zuerst“ nach nötiger Stufe, bei Gleichstand Gegenstandsstufe, dann Name; ohne Stufe
              (Waren, Hemden) zuletzt, nicht Gelerntes unter Blizzards Trenner. Blizzards Kategorien bleiben stehen (Nutzer am
              24.11.2026 zur Liste ohne sie: „die anordnung ist gut aber es weicht zu sehr vom original ab bzw weiß keiner
              direkt was was davon ist“): die mit dem höchsten bzw. niedrigsten Gegenstand zuerst (Wahl „Nach Stufe“), darin
              geordnet, Favoriten immer oben, Kategorien ohne Stufe unten. Ohne den Haken „Kategorien behalten“ eine Liste
              quer über alle.
    Rollen    Wie Blizzard: nach Suche und Berufswechsel (SetDataProvider ohne „behalten“) und nach einer anderen Reihenfolge
              von oben, sonst bleibt die Stelle; ein Rezept-Link rollt zur Zeile.
    Menü      Abschnitt „Reihenfolge (ezCraft)“ in Blizzards Filtermenü der Rezeptliste (sichtbarer Knopf „Filter“);
              gemerkt in ezCraftDB.window.sort und .sortGroups.

    Nicht mit Blizzards Gamepad-Oberfläche (sie wandert durch Blizzards Zeilen).
]]

local Sort = {}
ns.Sort = Sort

local Plain, Num, Call, Peek = Core.Plain, Core.Num, Core.Call, Core.Peek

Sort.MODES = { "blizzard", "high", "low" }
Sort.ROW, Sort.HEADER, Sort.DIVIDER, Sort.NOTE = 20, 25, 30, 40   -- Zeile und Kategorie wie Blizzards, Trenner, Hinweis
Sort.INDENT = 10                      -- so weit rückt Blizzard Rezepte ein (seine Baumansicht; Platz für „2“ vor dem Zeichen)
Sort.failed = false                   -- Vorlage passt nicht oder Blizzard blockiert: bis /reload Blizzards Liste
Sort.used = false                     -- in der geordneten Liste wurde schon gewählt

local ui                              -- { holder, box, bar, list }
local collapsed = {}                  -- [Schlüssel der Kategorie] = true: in der geordneten Liste zugeklappt (diese Sitzung)
local selected, fighting
local notes = setmetatable({}, { __mode = "k" })      -- Rahmen der Hinweiszeile » eigener Text
local pendingLevels = false           -- beim letzten Aufbau fehlten noch Stufen

local function Store() return type(ns.db) == "table" and ns.db.window or nil end

function Sort.Mode()
    local s = Store()
    local mode = s and s.sort
    return (mode == "high" or mode == "low") and mode or "blizzard"
end

function Sort.Grouped()
    local s = Store()
    return not (s and s.sortGroups == false)
end

local function Gamepad()
    local util = rawget(_G, "InputUtil")
    return type(util) == "table" and Plain(Call(util.IsGamepadUIEnabled)) == true
end

function Sort.Active()
    local combat = fighting or (type(InCombatLockdown) == "function" and InCombatLockdown())
    return Sort.Mode() ~= "blizzard" and not Sort.failed and not combat and not Gamepad()
end

-- ezCrafts sortierte Liste, solange sie zu sehen ist (Skill.ApplyAll zeichnet auch ihre Zeilen)
function Sort.Box()
    return ui and ui.holder:IsShown() and ui.box or nil
end

---------------------------------------------------------------------------
-- Lesen und ordnen
---------------------------------------------------------------------------

-- Blizzards Baum (nur gelesen) → Liste in Blizzards Folge: { info = categoryInfo, key, closed (selbst zugeklappt), inside
-- (in einer zugeklappten), all = { recipeInfo, … }, recipes = davon die, die Blizzard wählen kann (siehe Kopf) }, dazu
-- hidden = Zahl der Rezepte ohne eine solche Zeile
function Sort.Read(provider)
    local groups, shown, hidden = {}, {}, 0
    local function Walk(node, group)
        for _, child in ipairs(Call(node.GetNodes, node) or {}) do
            local data = Call(child.GetData, child)
            if type(data) == "table" and type(data.categoryInfo) == "table" then
                local id = Plain(data.categoryInfo.categoryID)
                local made = { info = data.categoryInfo, closed = Call(child.IsCollapsed, child) == true,
                    inside = group ~= nil and (group.closed or group.inside), parent = group, recipes = {},
                    -- gelernte und nicht gelernte Kategorien tragen dieselbe Kennung
                    key = tostring(id) .. (data.categoryInfo.unlearned and "u" or "") }
                groups[#groups + 1] = made
                Walk(child, made)
            elseif type(data) == "table" and type(data.recipeInfo) == "table" and group then
                local info = data.recipeInfo
                group.recipes[#group.recipes + 1] = info
                if not (group.closed or group.inside) then shown[Num(Plain(info.recipeID)) or 0] = true end
            end
        end
    end
    local root = type(provider) == "table" and Call(provider.GetRootNode, provider)
    if type(root) == "table" then Walk(root, nil) end
    for _, group in ipairs(groups) do
        group.all = group.recipes
        if group.closed or group.inside then
            -- ein Favorit steht zweimal im Baum: gezählt wird er nur in seiner eigenen Kategorie
            for _, info in ipairs(group.all) do
                if not info.favoritesInstance and not shown[Num(Plain(info.recipeID)) or 0] then hidden = hidden + 1 end
            end
            group.recipes = {}
        end
    end
    return groups, hidden
end

-- Kategorien in ihrer Folge: Favoriten, gelernte, nicht gelernte; darin die mit dem höchsten (bzw. niedrigsten) Gegenstand
-- zuerst, ohne Stufe zuletzt, sonst Blizzards Folge. Unterkategorien bleiben unter ihrer Kategorie und zählen für sie mit.
-- → Liste, laden noch Daten?
function Sort.OrderGroups(groups, mode)
    local open, high = false, mode == "high"
    local function Better(a, b)
        if a == nil or b == nil then return a ~= nil end
        if high then return a > b end
        return a < b
    end
    for i, group in ipairs(groups) do
        group.index, group.rank, group.best = i, group.info.unlearned == true and 2 or 1, nil
        for _, info in ipairs(group.all) do
            if info.favoritesInstance then group.rank = 0 end
            local level, _, loading = ns.Rows.Level(info)
            if loading then open = true end
            if Better(level, group.best) then group.best = level end
        end
    end
    -- Unterkategorien stehen hinter ihrer Kategorie: rückwärts reicht jede ihren besten Wert nach oben
    local children, top = {}, {}
    for i = #groups, 1, -1 do
        local group, list = groups[i], top
        local parent = group.parent
        if parent then
            if Better(group.best, parent.best) then parent.best = group.best end
            list = children[parent] or {}
            children[parent] = list
        end
        list[#list + 1] = group
    end
    local out = {}
    local function Add(list)
        table.sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.best ~= b.best then return Better(a.best, b.best) end
            return a.index < b.index
        end)
        for _, group in ipairs(list) do
            out[#out + 1] = group
            if children[group] then Add(children[group]) end
        end
    end
    Add(top)
    return out, open
end

-- Einträge { info, level, itemLevel, learned, name } nach Stufe. → die Liste, laden noch Daten?
function Sort.Order(infos, mode)
    local list, open = {}, false
    for _, info in ipairs(infos) do
        local level, itemLevel, loading = ns.Rows.Level(info)
        if loading then open = true end
        local name = Plain(info.name)
        list[#list + 1] = { info = info, level = level, itemLevel = itemLevel or Num(Plain(info.itemLevel)) or 0,
            learned = Plain(info.learned) ~= false, name = type(name) == "string" and name or "",
            id = Num(Plain(info.recipeID)) or 0 }
    end
    local high = mode == "high"
    table.sort(list, function(a, b)
        if a.learned ~= b.learned then return a.learned end
        if (a.level ~= nil) ~= (b.level ~= nil) then return a.level ~= nil end
        if a.level and a.level ~= b.level then
            if high then return a.level > b.level end
            return a.level < b.level
        end
        if a.level and a.itemLevel ~= b.itemLevel then
            if high then return a.itemLevel > b.itemLevel end
            return a.itemLevel < b.itemLevel
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return list, open
end

local function RecipeElement(info)
    local element = { height = Sort.ROW, data = { recipeInfo = info } }
    function element:GetData() return self.data end
    return element
end

local function HeaderElement(group)
    local element = { height = Sort.HEADER, data = { categoryInfo = group.info }, key = group.key, blizzard = group.closed,
        closed = group.closed or collapsed[group.key] == true }
    function element:GetData() return self.data end
    function element:IsCollapsed() return self.closed end
    return element
end

local function Plainer(kind, height, text)
    return { height = height, kind = kind, text = text, data = {} }
end

-- Liegt die Kategorie in einer, die in der geordneten Liste zugeklappt ist?
local function Folded(group)
    local parent = group.parent
    while parent do
        if collapsed[parent.key] then return true end
        parent = parent.parent
    end
    return false
end

-- Zeilen der geordneten Liste in ihrer Folge. → Elemente, laden noch Daten?
function Sort.Elements(provider)
    local groups, hidden = Sort.Read(provider)
    local out, open, divided = {}, false, false
    local function Divide(unlearned)
        if unlearned and not divided and #out > 0 then out[#out + 1] = Plainer("divider", Sort.DIVIDER) end
        divided = divided or unlearned
    end
    if Sort.Grouped() then
        -- rückwärts (Unterkategorien stehen hinter ihrer Kategorie): eine Überschrift steht, wenn darunter etwas zu sehen ist
        for i = #groups, 1, -1 do
            local group = groups[i]
            group.filled = group.filled or (not group.inside and (group.closed or #group.recipes > 0))
            if group.filled and group.parent then group.parent.filled = true end
        end
        groups, open = Sort.OrderGroups(groups, Sort.Mode())
        for _, group in ipairs(groups) do
            -- wie Blizzard: nichts aus einer zugeklappten Kategorie; selbst zugeklappte bleiben als Überschrift stehen
            if group.filled and not Folded(group) then
                Divide(group.info.unlearned == true)
                local head = HeaderElement(group)
                out[#out + 1] = head
                local list, loading = Sort.Order(group.recipes, Sort.Mode())
                open = open or loading
                if not head.closed then
                    for _, e in ipairs(list) do out[#out + 1] = RecipeElement(e.info) end
                end
            end
        end
    else
        local all, seen = {}, {}
        for _, group in ipairs(groups) do
            for _, info in ipairs(group.recipes) do
                -- Favoriten stehen bei Blizzard ein zweites Mal oben – ohne Kategorien wäre das doppelt
                local id = Num(Plain(info.recipeID)) or info
                if not seen[id] then
                    seen[id] = true
                    all[#all + 1] = info
                end
            end
        end
        local list
        list, open = Sort.Order(all, Sort.Mode())
        for _, e in ipairs(list) do
            Divide(not e.learned)
            out[#out + 1] = RecipeElement(e.info)
        end
    end
    if hidden > 0 then out[#out + 1] = Plainer("note", Sort.NOTE, L.SORT_HIDDEN:format(hidden)) end
    return out, open
end

---------------------------------------------------------------------------
-- Zeilen (Blizzards Vorlagen)
---------------------------------------------------------------------------

-- Ein Rezept in Blizzards Liste wählen (siehe Kopf; Blizzards Nachricht kommt noch in diesem Aufruf). → gewählt?
function Sort.Open(info)
    local id = Num(Plain(info.recipeID))
    if not id then return false end
    if not Sort.Active() then
        -- die geordnete Liste gilt nicht mehr (etwa Gamepad): weglegen, Blizzards Liste steht wieder da
        ns.Try("Sort", Sort.Update)
        return false
    end
    local list = ns.Skill.RecipeList()
    local pick, node = Peek(list, "SelectRecipe"), nil
    if type(pick) == "function" then
        Sort.used = true
        node = Call(pick, list, info, false)
    end
    if type(node) == "table" and selected == id then return true end
    ns.Print(L.SORT_NOT_OPENED)
    return false
end

local function FavoriteMenu(button, info)
    local util, id = rawget(_G, "MenuUtil"), Num(Plain(info.recipeID))
    if not (id and type(util) == "table" and type(util.CreateContextMenu) == "function") then return end
    util.CreateContextMenu(button, function(_, root)
        root:SetTag("MENU_PROFESSIONS_RECIPE_LIST_FAVORITE")
        local favorite = Plain(Call(C_TradeSkillUI.IsRecipeFavorite, id)) == true
        root:CreateButton(favorite and BATTLE_PET_UNFAVORITE or BATTLE_PET_FAVORITE, function()
            Call(C_TradeSkillUI.SetRecipeFavorite, id, not favorite)
        end)
    end)
end

-- Klick wie in Blizzards Rezeptzeile (ProfessionsRecipeListMixin:OnLoad)
function Sort.Click(button, info, mouse)
    local id = Num(Plain(info.recipeID))
    if not id then return end
    if mouse == "RightButton" then
        local P = rawget(_G, "Professions")
        local mine = type(P) ~= "table" or type(P.InLocalCraftingMode) ~= "function" or P.InLocalCraftingMode()
        if Plain(info.learned) == true and mine then FavoriteMenu(button, info) end
    elseif type(IsModifiedClick) == "function" and IsModifiedClick() then
        local link = Plain(Call(C_TradeSkillUI.GetRecipeLink, id))
        local done = type(link) == "string" and type(HandleModifiedItemClick) == "function" and HandleModifiedItemClick(link)
        local P = rawget(_G, "Professions")
        if not done and IsModifiedClick("RECIPEWATCHTOGGLE") and type(P) == "table" and Plain(Call(P.CanTrackRecipe, info)) then
            local tracked = Plain(Call(C_TradeSkillUI.IsRecipeTracked, id, false)) == true
            Call(C_TradeSkillUI.SetRecipeTracked, id, not tracked, false)
        end
    else
        Sort.Open(info)
    end
    Core.PlaySound("UI_90_BLACKSMITHING_TREEITEMCLICK")
end

local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true end
    -- eine Vorlage passt nicht mehr: Blizzards Liste zeigen statt einer halben
    ns.Error(err, "Sort")
    Sort.failed = true
    C_Timer.After(0, function() ns.Try("Sort", Sort.Update) end)
    return false
end

function Sort.InitRow(button, element)
    local info = element.data.recipeInfo
    local list = ns.Skill.RecipeList()
    button:Init(element, Peek(list, "hideCraftableCount"))
    button:SetSelected(selected ~= nil and Num(Plain(info.recipeID)) == selected)
    button:SetScript("OnClick", function(self, mouse) ns.Try("SortClick", Sort.Click, self, info, mouse) end)
    ns.Skill.ApplyRow(button, element)
end

function Sort.InitHeader(button, element)
    button:Init(element)
    button:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        -- bei Blizzard zugeklappt: nur dort aufzuklappen (siehe Kopf)
        if element.blizzard then return ns.Print(L.SORT_CLOSED) end
        collapsed[element.key] = not element.closed or nil
        Guard(Sort.Rebuild, true)
    end)
end

function Sort.InitNote(frame, element)
    local text = notes[frame]
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
        text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        notes[frame] = text
    end
    text:SetText(element.text)
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

local function Build(list, blizzard)
    local holder = CreateFrame("Frame", nil, list)
    -- über Blizzards (durchsichtigen) Zeilen und ihrem Rollbalken; nimmt deren Mausklicks an
    holder:SetPoint("TOPLEFT", blizzard, "TOPLEFT", 0, 0)
    holder:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 5)
    holder:SetFrameLevel((blizzard:GetFrameLevel() or 1) + 50)
    holder:EnableMouse(true)
    holder:Hide()
    local box = CreateFrame("Frame", nil, holder, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 5)      -- wie Blizzards ScrollBox
    local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 0, 0)
    -- Abstände wie Blizzards Baumansicht; links eingerückt wie dort die Rezepte
    local view = CreateScrollBoxListLinearView(5, 5, Sort.INDENT, 5, 1)
    view:SetElementFactory(function(factory, element)
        if element.kind == "divider" then
            factory("ProfessionsRecipeListDividerTemplate")
        elseif element.kind == "note" then
            factory("Frame", function(frame, el) Guard(Sort.InitNote, frame, el) end)
        elseif element.data.categoryInfo then
            factory("ProfessionsRecipeListCategoryTemplate", function(button, el) Guard(Sort.InitHeader, button, el) end)
        else
            factory("ProfessionsRecipeListRecipeTemplate", function(button, el) Guard(Sort.InitRow, button, el) end)
        end
    end)
    view:SetElementExtentCalculator(function(_, element) return element.height end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return { holder = holder, box = box, bar = bar, list = list, blizzard = blizzard }
end

local function BlizzardBox()
    local list = ns.Skill.RecipeList()
    local box = Peek(list, "ScrollBox")
    return type(box) == "table" and box or nil, list
end

-- Blizzards Liste durchsichtig bzw. wieder sichtbar
local function Fade(box, list, hidden)
    local bar = Peek(list, "ScrollBar")
    box:SetAlpha(hidden and 0 or 1)
    if type(bar) == "table" and type(bar.SetAlpha) == "function" then bar:SetAlpha(hidden and 0 or 1) end
end

-- Zeilen neu aufbauen; retain: die Stelle in der Liste bleibt
function Sort.Rebuild(retain)
    local box = BlizzardBox()
    if not (box and ui) then return 0 end
    local elements
    elements, pendingLevels = Sort.Elements(Call(box.GetDataProvider, box))
    local C = rawget(_G, "ScrollBoxConstants") or {}
    ui.box:SetDataProvider(CreateDataProvider(elements), retain and C.RetainScrollPosition or C.DiscardScrollPosition)
    return #elements
end

-- Zur Zeile eines Rezepts rollen (Rezept-Link)
function Sort.ScrollTo(id)
    local box = Sort.Box()
    if not (box and type(box.ScrollToElementDataByPredicate) == "function") then return false end
    box:ScrollToElementDataByPredicate(function(element)
        local info = element.data.recipeInfo
        return info ~= nil and Num(Plain(info.recipeID)) == id
    end)
    return true
end

-- Geordnete Liste zeigen, auffrischen oder weglegen (retain: die Stelle bleibt). → true, wenn sie steht
function Sort.Update(retain)
    local box, list = BlizzardBox()
    if not box then return false end
    if not Sort.Active() then
        if ui then
            ui.holder:Hide()
            Fade(box, list, false)
        end
        return false
    end
    if not ui then
        local ok, made = pcall(Build, list, box)
        if not ok then
            ns.Error(made, "Sort")
            Sort.failed = true
            return false
        end
        ui = made
    end
    if selected == nil then selected = Num(ns.Panel.SelectedRecipeID()) end
    ui.holder:Show()
    Fade(box, list, true)
    local ok = Guard(Sort.Rebuild, retain)
    return ok and not Sort.failed
end

-- Stufen sind nachgeladen: neu ordnen (nur, wenn beim letzten Aufbau welche fehlten)
function Sort.Reorder()
    if pendingLevels and Sort.Box() then Guard(Sort.Rebuild, true) end
end

-- Blizzard hat eine Aktion blockiert, nachdem in der geordneten Liste gewählt wurde: bis /reload Blizzards Liste. Blizzard
-- kann die Blockade auch ezCore zuschreiben (Ereignisse und Helfer laufen über ezCores Rahmen): dann nur, wenn die Aktion zu
-- den Berufen gehört.
Sort.ACTIONS = { "TradeSkill", "Profession", "Recipe", "CastSpell" }
function Sort.OnBlocked(addon, action)
    if Sort.failed or not Sort.used then return false end
    local mine = addon == ADDON
    if addon == Core.name and type(action) == "string" then
        for _, part in ipairs(Sort.ACTIONS) do mine = mine or action:find(part, 1, true) ~= nil end
    end
    if not mine then return false end
    Sort.failed = true
    ns.Try("Sort", Sort.Update)
    ns.Print(L.SORT_BLOCKED)
    return true
end

function Sort.OnSelected(info)
    selected = type(info) == "table" and Num(Plain(info.recipeID)) or nil
    local box = Sort.Box()
    if not box then return end
    pcall(box.ForEachFrame, box, function(button)
        local element = type(button.GetElementData) == "function" and button:GetElementData()
        local row = type(element) == "table" and element.data and element.data.recipeInfo
        if row then button:SetSelected(Num(Plain(row.recipeID)) == selected) end
    end)
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

function Sort.SetMode(mode)
    local s = Store()
    if not s then return end
    s.sort = (mode == "high" or mode == "low") and mode or nil
    ns.Try("Sort", Sort.Update)
end

function Sort.SetGrouped(on)
    local s = Store()
    if not s then return end
    if on then s.sortGroups = nil else s.sortGroups = false end
    ns.Try("Sort", Sort.Update)
end

function Sort.BuildMenu(root)
    local Menu, Icons = Core.Menu, ns.Icons
    local sec = Icons.Section(root, L.SORT_HEAD, { icon = Icons.For("sort"), tip = L.SORT_HEAD_TIP, source = L.SORT_SOURCE })
    for _, mode in ipairs(Sort.MODES) do
        local label = L["SORT_" .. mode]
        local entry = Menu.Radio(sec, label, Sort.Mode, Sort.SetMode, mode)
        Icons.Apply(entry, "sort")
        Menu.Tip(entry, label, L["SORT_" .. mode .. "_TIP"], mode ~= "blizzard" and L.SORT_SOURCE or nil)
    end
    local groups = Menu.Toggle(sec, L.SORT_GROUPS, Sort.Grouped, Sort.SetGrouped)
    Icons.Apply(groups, "sort")
    Menu.Tip(groups, L.SORT_GROUPS, L.SORT_GROUPS_TIP)
    if type(groups) == "table" and type(groups.SetEnabled) == "function" then
        groups:SetEnabled(Sort.Mode() ~= "blizzard")
    end
    return true
end

---------------------------------------------------------------------------
-- Anbinden
---------------------------------------------------------------------------

Sort.registered, Sort.hooked = false, false
function Sort.Hook()
    local blizzardMenu = rawget(_G, "Menu")
    if not Sort.registered and type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function" then
        Sort.registered = pcall(blizzardMenu.ModifyMenu, ns.Skill.MENU_TAG, function(_, root)
            if not Sort.failed and not Gamepad() then ns.Try("SortMenu", Sort.BuildMenu, root) end
        end)
    end
    local box = BlizzardBox()
    if Sort.hooked or not (box and type(box.SetDataProvider) == "function") then return Sort.hooked end
    Sort.hooked = true
    hooksecurefunc(box, "SetDataProvider", function(_, _, retain) ns.Try("Sort", Sort.Update, Plain(retain) == true) end)
    local reg = rawget(_G, "EventRegistry")
    if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        reg:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, info)
            ns.Try("Sort", Sort.OnSelected, info)
        end, Sort)
    end
    return true
end

ns.WhenAddOnLoaded("Blizzard_Professions", Sort.Hook)
ns.On("TRADE_SKILL_SHOW", function()
    Sort.Hook()
    ns.Try("Sort", Sort.Update, true)
end)
-- Rezept-Link oder Zielverfolgung: zur Zeile rollen (nach Blizzards Antwort auf dasselbe Ereignis)
ns.On("OPEN_RECIPE_RESPONSE", function(_, recipeID)
    local id = Num(Plain(recipeID))
    if id and Sort.Box() then
        C_Timer.After(0, function() ns.Try("Sort", Sort.ScrollTo, id) end)
    end
end)
ns.On("PLAYER_REGEN_DISABLED", function()
    fighting = true
    ns.Try("Sort", Sort.Update)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    fighting = nil
    ns.Try("Sort", Sort.Update, true)
end)
ns.On("ADDON_ACTION_BLOCKED", function(_, addon, action) Sort.OnBlocked(Plain(addon), Plain(action)) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(_, addon, action) Sort.OnBlocked(Plain(addon), Plain(action)) end)
