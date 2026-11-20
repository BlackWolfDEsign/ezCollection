local _, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Knopf „Fundorte“ an den Sammelberufen in Blizzards Berufsbuch (SAM-25, Welle 15; Leitlinien 1 und 3).
    Sammelberufe haben in Forever kein Herstellungsfenster – nur die Seite „Berufe“ (Taste K). Dort bekommt die Karte
    von Kräuterkunde, Bergbau, Kürschnerei und Angeln einen kleinen Knopf; er öffnet Blizzards Menü (MenuUtil über
    Core.Menu) – kein eigener Rahmen, deshalb kein Eintrag in der Liste FENSTER von tools/lint.lua.

    Lage laut Forever-Quelle (Gethe/wow-ui-source, Zweig forever):
      Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml    ProfessionsFrame.BookPage (ProfessionsBookPageTemplate –
                                    diese Vorlage steht nicht in der öffentlichen Quelle; Book.Content sucht die Karten)
      Blizzard_ProfessionsBook/Camelot/Blizzard_ProfessionsBookTemplates.xml
                                    ProfessionsBookFrameTemplate.ProfessionsContentFrame mit PrimaryProfession1/2
                                    (664 × 142; ProfessionName oben links, StatusBar rechts mit Abstand 40, SpellButton1/2
                                    unten links) und SecondaryProfession1–3 (225 × 275; Name und StatusBar oben mittig,
                                    SpellButton1–4 von unten links)
      Blizzard_ProfessionsBook/Camelot/Blizzard_ProfessionsBook.lua  ProfessionsBookFrameMixin:Update belegt die Karten
                                    aus GetProfessions(): prof1, prof2, Erste Hilfe, Angeln, Kochen – Primary1 = Platz 1,
                                    Primary2 = 2, Secondary1 = Kochen (5), Secondary2 = Angeln (4), Secondary3 = Erste
                                    Hilfe (3); FormatProfession liest GetProfessionInfo (7. Wert: skillLine)
      Außerhalb von Forever gibt es das freie ProfessionsBookFrame (gleiche Vorlage) – es wird genauso bedient.

    Taint (Leitlinie 5): SpellButton1–4 sind geschützte Zauberknöpfe (SecureFrameTemplate). Nichts wird an ihnen
    verankert, umgehängt oder beschrieben; der eigene Knopf ist ein Kind der Karte und an der Karte verankert. Aufbau
    über HookScript("OnShow") der Buchseite, Blizzards Tabellen bleiben unberührt (gelesen wird nur GetProfessions).

    Sammelberuf über die skillLine (Client-Nummern, sprachfrei): Kräuterkunde 182, Bergbau 186, Angeln 356 und
    Kürschnerei 393 aus ezCores Core.Gathering.PROFESSION_LINES (eine Liste; 393 seit Welle 23c, vorher Book.SKIN_LINE).

    Menü: je Rohstoff ein Untermenü („Kupfererz – ab 1 – 37 Fundorte in 3 Zonen“, Data.GatherItems) mit „Nächster
    Fundort“ und den Zonen; ein Klick ruft ezMaps ShowGather (Data.ShowGather). Kürschnerei: „Leder von“ je Gegenstand
    mit Gegner (Zone) n× (Data.SkinItems). Ohne Daten ein erklärender Eintrag, ohne ezMap der Hinweis darauf.
]]

local Book = {}
ns.Book = Book

Book.CARDS = {
    { key = "PrimaryProfession1", slot = 1 },
    { key = "PrimaryProfession2", slot = 2 },
    { key = "SecondaryProfession1", slot = 5 },   -- Kochen
    { key = "SecondaryProfession2", slot = 4 },   -- Angeln
    { key = "SecondaryProfession3", slot = 3 },   -- Erste Hilfe
}
Book.BUTTON_W, Book.BUTTON_H = 84, 20
-- Kleine Karte (SecondaryProfessionTemplate, Camelot/Blizzard_ProfessionsBookTemplates.xml): ProfessionName steht
-- mittig an TOP mit y −25. Der Knopf ist dort flacher und endet darüber, damit ein langer Name ihn nicht streift.
Book.SMALL_NAME_TOP, Book.SMALL_BUTTON_H, Book.SMALL_BUTTON_Y = 25, 18, -3

local buttons = {}   -- Karte » eigener Knopf
local hooked = {}    -- Buchseite » true (HookScript einmal)

-- skillLine » Art des Menüs ("herb", "ore", "fish", "skin") oder nil
function Book.KindOfLine(line)
    line = Core.Num(line)
    if not line then return nil end
    local G = Core.Gathering
    local lines = type(G) == "table" and type(G.PROFESSION_LINES) == "table" and G.PROFESSION_LINES or {}
    for kind, l in pairs(lines) do
        if l == line then return kind end
    end
    return nil
end

-- Beruf auf Platz slot von GetProfessions → { name, rank, line, kind } oder nil (kein Beruf auf dem Platz)
function Book.Profession(slot)
    local index = select(slot, Core.Call(rawget(_G, "GetProfessions")))
    index = Core.Num(Core.Plain(index))
    if not index then return nil end
    local name, _, rank, _, _, _, line = Core.Call(rawget(_G, "GetProfessionInfo"), index)
    line = Core.Num(Core.Plain(line))
    if not line then return nil end
    name = Core.Plain(name)
    return { name = type(name) == "string" and name or "?", rank = Core.Num(Core.Plain(rank)) or 0, line = line,
        kind = Book.KindOfLine(line) }
end

-- Buchseiten, die es gerade gibt: Forevers Seite im Berufefenster, sonst das freie Berufsbuch
function Book.Pages()
    local out = {}
    local pf = rawget(_G, "ProfessionsFrame")
    if type(pf) == "table" and type(pf.BookPage) == "table" then out[#out + 1] = pf.BookPage end
    local bf = rawget(_G, "ProfessionsBookFrame")
    if type(bf) == "table" then out[#out + 1] = bf end
    return out
end

-- Rahmen mit den Karten: ProfessionsContentFrame (Vorlage ProfessionsBookFrameTemplate), die Seite selbst oder ein
-- direktes Kind, das PrimaryProfession1 trägt (die Vorlage ProfessionsBookPageTemplate steht nicht in der öffentlichen
-- Quelle – darum alle drei Wege; Spieltest W15-2)
function Book.Content(page)
    if type(page.ProfessionsContentFrame) == "table" then return page.ProfessionsContentFrame end
    if type(page.PrimaryProfession1) == "table" then return page end
    if type(page.GetChildren) == "function" then
        for _, child in ipairs({ page:GetChildren() }) do
            if type(child) == "table" and type(child.PrimaryProfession1) == "table" then return child end
            if type(child) == "table" and type(child.ProfessionsContentFrame) == "table" then return child.ProfessionsContentFrame end
        end
    end
    return page
end

local function Cards(page)
    local content = Book.Content(page)
    local out = {}
    for _, c in ipairs(Book.CARDS) do
        local card = content[c.key]
        if type(card) == "table" then out[#out + 1] = { card = card, slot = c.slot } end
    end
    return out
end

function Book.Tip(button)
    local prof = button.prof or {}
    local text
    if button.kind == "skin" then
        text = L.BOOK_BUTTON_TIP_SKIN:format(prof.name or "?")
    else
        text = L.BOOK_BUTTON_TIP:format(prof.name or "?", prof.rank or 0)
        if not Data.MapAPI() then text = text .. "\n\n" .. L.BOOK_NOMAP end
    end
    return text
end

local function MakeButton(card)
    local ok, button = pcall(CreateFrame, "Button", nil, card, "UIPanelButtonTemplate")
    if not (ok and button) then button = CreateFrame("Button", nil, card) end
    button:SetSize(Book.BUTTON_W, Book.BUTTON_H)
    button:SetText(L.BOOK_BUTTON)
    -- Große Karte: oben rechts über dem Ende der Rangleiste (StatusBar an RIGHT −40); kleine Karte: obere rechte Ecke
    -- über dem Berufsnamen (Book.SMALL_NAME_TOP)
    if card.isPrimary then
        button:SetPoint("TOPRIGHT", card, "TOPRIGHT", -40, -18)
    else
        button:SetHeight(Book.SMALL_BUTTON_H)
        button:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, Book.SMALL_BUTTON_Y)
    end
    button:SetScript("OnClick", function(self) Book.OpenMenu(self) end)
    button:SetScript("OnEnter", function(self) Core.ShowTip(self, L.BOOK_BUTTON, Book.Tip(self)) end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    buttons[card] = button
    return button
end

-- Knopf einer Karte zeigen oder verstecken. → der Knopf, wenn er zu sehen ist
function Book.UpdateCard(card, slot)
    local prof = Book.Profession(slot)
    local button = buttons[card]
    if not (prof and prof.kind and ns.Enabled("bookButton")) then
        if button then button:Hide() end
        return nil
    end
    button = button or MakeButton(card)
    button.kind, button.prof = prof.kind, prof
    button:Show()
    return button
end

function Book.Refresh()
    for _, page in ipairs(Book.Pages()) do
        for _, c in ipairs(Cards(page)) do Book.UpdateCard(c.card, c.slot) end
    end
end

function Book.Button(card) return buttons[card] end

-- Einmal je Buchseite: beim Öffnen die Karten neu lesen (Blizzard belegt sie im eigenen OnShow – der Haken läuft danach)
function Book.Attach()
    for _, page in ipairs(Book.Pages()) do
        if not hooked[page] and type(page.HookScript) == "function" then
            hooked[page] = true
            page:HookScript("OnShow", function() ns.Try("Book", Book.Refresh) end)
        end
    end
    Book.Refresh()
    return next(hooked) ~= nil
end

---------------------------------------------------------------------------
-- Menü (Blizzards MenuUtil über Core.Menu)
---------------------------------------------------------------------------

local function Enable(entry, on)
    if type(entry) == "table" and type(entry.SetEnabled) == "function" then pcall(entry.SetEnabled, entry, on) end
    return entry
end

--[[
    Aufbau seit Welle 27 (Zweig modul/ezcraft-menue; Wunsch des Nutzers vom 16.11.2026 „also das menü“, Stil wie das
    ezMap-Menü, Design-System 2.3 und 2.7): Überschrift mit dem Symbol des Berufs; Abschnitt „Rohstoffe deiner Ernten“
    (Core.Menu.Section) mit je Rohstoff seinem Gegenstandssymbol; Rohstoffe über deinem Rang in einem Untermenü
    „Über deinem Rang – n Rohstoffe“ statt am Ende der langen Liste (nur, wenn es auch Rohstoffe für deinen Rang
    gibt – sonst wie bisher direkt); „Nächster Fundort“ mit dem Kartenpunkt; Hinweise und die Quelle mit Blizzards
    „i“. Die Zonen in den Untermenüs sind Listen und bleiben ohne Symbol (Design-System 2.3). Jeder Rohstoff und
    „Nächster Fundort“ hat einen Tooltip (Titel, Beschreibung, Quelle grau). Symbole: ns.Icons (Icons.lua). Eine
    Auswahl gibt es hier nicht – das Menü führt nur zur Karte, nichts ist zu merken (Design-System 2.12).
]]

-- Ein Rohstoff: Untermenü mit „Nächster Fundort“ und den Zonen
local function AddGatherItem(root, e, kind, prof, mapOK)
    local M, Icons = Core.Menu, ns.Icons
    local label = Data.GatherItemLabel(e, kind)
    if e.above then label = Core.Grey(label .. " " .. L.BOOK_ABOVE:format(prof.rank)) end
    local sub = M.Button(root, label)
    Icons.Apply(sub, Icons.Item(e.itemID, kind))
    if #e.zones == 0 then
        -- ohne Fundort: der Tooltip verspricht keinen nächsten Fundort und keine Zonen, er sagt, was fehlt
        M.Tip(sub, e.name or label, L.BOOK_NO_SPOTS, L.BOOK_SOURCE)
        Icons.Apply(M.Title(sub, L.BOOK_NO_SPOTS), "info")
        return sub
    end
    M.Tip(sub, e.name or label, mapOK and L.BOOK_ITEM_TIP or L.BOOK_NOMAP, L.BOOK_SOURCE)
    local itemID = e.itemID
    local nearest = Enable(M.Button(sub, L.BOOK_NEAREST, function() Data.ShowGather(itemID) end), mapOK)
    Icons.Apply(nearest, "nearest")
    M.Tip(nearest, L.BOOK_NEAREST, mapOK and L.BOOK_NEAREST_TIP or L.BOOK_NOMAP, L.BOOK_SOURCE)
    for i = 1, math.min(#e.zones, Data.ZONES_MAX) do
        local z = e.zones[i]
        local spots = Core.Plural(z.points, Core.L.GATHER_SPOTS_ONE, Core.L.GATHER_SPOTS_MANY)
        local mapID = z.mapID
        Enable(M.Button(sub, L.BOOK_ZONE:format(z.name, spots, z.count), function() Data.ShowGather(itemID, mapID) end), mapOK)
    end
    if #e.zones > Data.ZONES_MAX then Icons.Apply(M.Title(sub, ezCore.More(#e.zones - Data.ZONES_MAX)), "info") end
    return sub
end

local function GatherMenu(root, kind, prof)
    local M, Icons = Core.Menu, ns.Icons
    local hint = Icons.Root(root, "info")      -- Hilfszeilen (Titelzeilen) mit Blizzards „i“
    local items, total = Data.GatherItems(kind, prof.rank)
    if items == nil then
        M.Title(hint, L.BOOK_OLD_CORE)
        return
    end
    if #items == 0 then
        M.Title(hint, L.BOOK_EMPTY)
        return
    end
    local mapOK = Data.MapAPI() ~= nil
    if not mapOK then M.Title(hint, L.BOOK_NOMAP) end
    local now, above = {}, {}
    for _, e in ipairs(items) do
        if e.above then above[#above + 1] = e else now[#now + 1] = e end
    end
    if #now == 0 then now, above = above, {} end
    local sec = Icons.Section(root, L.BOOK_SEC_ITEMS, { icon = Icons.Profession(kind), tip = L.BOOK_SEC_ITEMS_TIP,
        source = L.BOOK_SOURCE, first = true })
    for _, e in ipairs(now) do AddGatherItem(sec, e, kind, prof, mapOK) end
    if #above > 0 then
        local title = L.BOOK_ABOVE_MENU:format(Core.Plural(#above, L.BOOK_MATS_ONE, L.BOOK_MATS_MANY))
        local sub = Icons.Apply(M.Button(root, title), "above")
        M.Tip(sub, title, L.BOOK_ABOVE_MENU_TIP:format(prof.rank), L.BOOK_SOURCE)
        for _, e in ipairs(above) do AddGatherItem(sub, e, kind, prof, mapOK) end
    end
    if (total or 0) > #items then M.Title(hint, ezCore.More(total - #items)) end
    M.Divider(root)
    M.Title(hint, L.BOOK_SOURCE)
end

local function SkinMenu(root)
    local M, Icons = Core.Menu, ns.Icons
    local hint = Icons.Root(root, "info")
    local items, total = Data.SkinItems()
    if items == nil then
        M.Title(hint, L.BOOK_OLD_CORE)
        return
    end
    if #items == 0 then
        M.Title(hint, L.BOOK_SKIN_NONE)
        return
    end
    local sec = Icons.Section(root, L.BOOK_SKIN_HEAD, { icon = Icons.Profession("skin"), tip = L.BOOK_SKIN_HEAD_TIP,
        source = L.BOOK_SKIN_SOURCE, first = true })
    for _, e in ipairs(items) do
        local npcs = Core.Plural(#e.sources, L.BOOK_NPCS_ONE, L.BOOK_NPCS_MANY)
        local sub = Icons.Apply(M.Button(sec, L.BOOK_SKIN_ITEM:format(e.name, npcs)), Icons.Item(e.itemID, "skin"))
        M.Tip(sub, e.name or "?", L.BOOK_SKIN_ITEM_TIP, L.BOOK_SKIN_SOURCE)
        for i = 1, math.min(#e.sources, Data.ZONES_MAX) do M.Title(sub, Data.SkinEntry(e.sources[i])) end
        if #e.sources > Data.ZONES_MAX then Icons.Apply(M.Title(sub, ezCore.More(#e.sources - Data.ZONES_MAX)), "info") end
    end
    if (total or 0) > #items then M.Title(hint, ezCore.More(total - #items)) end
    M.Divider(root)
    M.Title(hint, L.BOOK_SKIN_SOURCE)
end

-- Art des Menüs » Baustein (Kräuterkunde, Bergbau und Angeln teilen sich die Fundorte, Kürschnerei hat die Beute)
Book.MENUS = { herb = GatherMenu, ore = GatherMenu, fish = GatherMenu, skin = SkinMenu }

-- Inhalt des Menüs (auch für die Tests): kind "herb" | "ore" | "fish" | "skin", prof = { name, rank }
function Book.BuildMenu(root, kind, prof)
    prof = type(prof) == "table" and prof or { name = "?", rank = 0 }
    local title = Core.Menu.Title(root, L.BOOK_MENU_TITLE:format(prof.name or "?", prof.rank or 0))
    ns.Icons.Apply(title, ns.Icons.Profession(kind))
    local build = Book.MENUS[kind] or GatherMenu
    build(root, kind, prof)
end

function Book.OpenMenu(button)
    local kind, prof = button.kind, button.prof
    if not kind then return false end
    return Core.Menu.Open(button, function(root) Book.BuildMenu(root, kind, prof) end)
end

---------------------------------------------------------------------------
-- Anbindung
---------------------------------------------------------------------------

local function RefreshIfShown()
    for _, page in ipairs(Book.Pages()) do
        if type(page.IsShown) == "function" and page:IsShown() then return ns.Try("Book", Book.Refresh) end
    end
end

ns.OnReady(function()
    -- Blizzard_ProfessionsBook lädt bei Bedarf (in Forever als Abhängigkeit von Blizzard_Professions)
    ns.WhenAddOnLoaded("Blizzard_ProfessionsBook", Book.Attach)
    ns.WhenAddOnLoaded("Blizzard_Professions", Book.Attach)
end)
ns.On("SKILL_LINES_CHANGED", RefreshIfShown)
ns.OnSettingChanged(function() ns.Try("Book", Book.Refresh) end)
