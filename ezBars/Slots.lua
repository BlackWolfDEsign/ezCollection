local _, ns = ...
local L = ns.L

--[[
    Aktionsplätze: Welche Seiten (je 12 Plätze) eine ezBars-Leiste zeigt.

    Forever wie Retail (Blizzard_ActionBar/Shared/MultiActionBars.lua, Zweig „forever“):
      Seite 1        Hauptleiste
      Seite 2        Hauptleiste, zweite Seite (Umschalt+Mausrad, „Aktionsleiste 2“ in der Tastaturbelegung)
      Seite 3 … 6    Blizzards Aktionsleisten 4, 5, 3, 2 (rechts, links, unten rechts, unten links); ist eine davon
                     aus, blättert die Hauptleiste mit „Aktionsleiste 3 … 6“ auf ihre Seite
      Seite 7 … 10   Gestalt- und Haltungsleisten (Krieger, Druide, Schurke, Priester): die Hauptleiste wechselt dorthin
      Seite 11, 12   Blizzards Sonderleisten (Gedankenkontrolle, Fahrzeug) – nie für ezBars
      Seite 13 … 15  Blizzards Aktionsleisten 6, 7, 8 (MultiBar5–7)

    „Automatisch“ nimmt Seiten, die weder eine sichtbare Blizzard-Leiste noch die Gestaltleisten der Klasse nutzen,
    und merkt sie sich je Charakter (ezBarsDB.chars[charKey].pages). Sie bleiben fest, auch wenn später eine
    Blizzard-Leiste dieselben Plätze zeigt – dann meldet ezBars die Überschneidung, „Plätze neu wählen“ löst sie.

    Der Plan der Plätze steht in ezCore (Core.ActionSlots, eine Quelle für ezMacro, ezBars und ezCombat): Plätze je
    Seite, nutzbare Plätze, Blizzards Zusatzleisten je Seite und die Gestalt- und Haltungsseiten je Klasse. Hier steht
    nur, was ezBars daraus macht (welche Seiten wählbar sind und in welcher Reihenfolge „Automatisch“ sucht).
]]

local AS = ezCore.ActionSlots

local Slots = {}
ns.Slots = Slots

Slots.PER_PAGE = AS.PER_PAGE
-- Seite → Blizzards Aktionsleiste { bar, visible, frame } (Verweis auf ezCore, keine eigene Kopie)
Slots.BLIZZARD = AS.BLIZZARD_PAGES
-- Klassen, deren Hauptleiste mit Gestalt oder Haltung auf Seite 7 … 10 wechselt (Verweis auf ezCore)
Slots.STANCE = AS.BONUS_PAGES

local function Contains(list, value)
    for _, entry in ipairs(list or {}) do
        if entry == value then return true end
    end
    return false
end

-- Wählbar: jede Seite, deren Plätze alle nutzbar sind (ezCore: keine Fahrzeug- und Sonderleisten), außer der
-- Hauptleiste (Seite 1) – also 2 … 10 und 13 … 15.
Slots.PAGES = {}
do
    local usable = {}
    for _, slot in ipairs(AS.USABLE) do usable[slot] = true end
    for page = 2, AS.PageOf(AS.MAX) do
        local all = true
        for _, slot in ipairs(AS.SlotsOfPage(page)) do
            if not usable[slot] then all = false end
        end
        if all then Slots.PAGES[#Slots.PAGES + 1] = page end
    end
end

-- Reihenfolge für „Automatisch“: nie gezeigte Seiten zuerst (Gestaltseiten, die die Klasse nicht nutzt, dann
-- Blizzards Leisten 6–8, dann 2, 3, 4, 5); Seite 2 (zweite Seite der Hauptleiste) nur von Hand.
Slots.AUTO_ORDER = {}
for _, page in ipairs({ 7, 8, 9, 10, 13, 14, 15, 6, 5, 3, 4 }) do
    if Contains(Slots.PAGES, page) then Slots.AUTO_ORDER[#Slots.AUTO_ORDER + 1] = page end
end

function Slots.Range(page)
    local slots = AS.SlotsOfPage(page)
    return slots[1], slots[#slots]
end

function Slots.IsAllowed(page) return Contains(Slots.PAGES, page) end

-- Nächste erlaubte Seite nach page (für Leisten mit mehr als 12 Knöpfen bei Seitenwahl von Hand).
function Slots.NextPage(page)
    for _, candidate in ipairs(Slots.PAGES) do
        if candidate > page then return candidate end
    end
    return nil
end

function Slots.Class() return ns.playerClass end

function Slots.IsStancePage(page, class)
    class = class or Slots.Class() or ""
    if AS.IsBonusPage(page, class) then return true end
    local learned = ns.db and ns.db.stancePages and ns.db.stancePages[class]
    return type(learned) == "table" and learned[page] == true
end

-- Dazulernen: Wechselt die Hauptleiste bei einer Klasse, die die Tabelle oben nicht kennt (oder auf einer Seite,
-- die dort fehlt), merkt ezBars die Seite für diese Klasse (ezBarsDB.stancePages) und meldet Überschneidungen.
-- Blizzard: Bonusleiste 1 … 4 = Seite 7 … 10 (C_ActionBar.GetBonusBarIndex bzw. GetBonusBarOffset + 6).
function Slots.LearnBonusBar()
    local class = Slots.Class()
    if not (class and ns.db) then return false end
    local page
    local api = C_ActionBar or {}
    if api.HasBonusActionBar and api.GetBonusBarIndex then
        local ok, active = pcall(api.HasBonusActionBar)
        if not (ok and active == true) then return false end
        local okIndex, value = pcall(api.GetBonusBarIndex)
        page = okIndex and ezCore.Num(value) or nil
    elseif rawget(_G, "GetBonusBarOffset") then
        local ok, offset = pcall(GetBonusBarOffset)
        offset = ok and ezCore.Num(offset) or nil
        if offset and offset > 0 then page = offset + 6 end
    end
    if not (page and page >= 7 and page <= 10) or Slots.IsStancePage(page, class) then return false end
    ns.db.stancePages = type(ns.db.stancePages) == "table" and ns.db.stancePages or {}
    ns.db.stancePages[class] = type(ns.db.stancePages[class]) == "table" and ns.db.stancePages[class] or {}
    ns.db.stancePages[class][page] = true
    return true
end

-- Zeigt eine sichtbare Blizzard-Leiste diese Seite? Dann ihr Name, sonst nil.
function Slots.BlizzardUser(page)
    local info = Slots.BLIZZARD[page]
    if not info then return nil end
    local visible
    local check = rawget(_G, info.visible)
    if type(check) == "function" then
        local ok, value = pcall(check)
        if ok and value ~= nil then visible = value == true end
    end
    if visible == nil then
        local frame = rawget(_G, info.frame)
        visible = type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
    end
    return visible and L.PAGE_BLIZZARD:format(info.bar) or nil
end

-- Name der Seite für die Auswahl und den Status.
function Slots.PageLabel(page)
    if page == 2 then return L.PAGE_2 end
    if Slots.BLIZZARD[page] then return L.PAGE_BLIZZARD:format(Slots.BLIZZARD[page].bar) end
    if page >= 7 and page <= 10 then return L.PAGE_STANCE:format(page - 6) end
    return tostring(page)
end

---------------------------------------------------------------------------
-- Seiten je Leiste
---------------------------------------------------------------------------

-- Anzahl Knöpfe einer Leiste (Spalten × Reihen, höchstens ns.MAX_BUTTONS = 12 × 12) und gewünschte Anzahl.
-- Wie viele davon einen Aktionsplatz bekommen, hängt an den freien Seiten (Slots.FreeButtons); der Rest bleibt leer.
function Slots.ButtonCount(n)
    local wanted = math.max(1, math.floor(ns.BarSetting(n, "Cols") or 1)) * math.max(1, math.floor(ns.BarSetting(n, "Rows") or 1))
    return math.min(wanted, ns.MAX_BUTTONS), wanted
end

function Slots.PagesNeeded(n)
    return math.ceil(Slots.ButtonCount(n) / Slots.PER_PAGE)
end

-- Von Hand gewählte erste Seite oder nil (= automatisch).
function Slots.ManualPage(n)
    local page = tonumber(ns.BarSetting(n, "Page"))
    if page and Slots.IsAllowed(page) then return page end
    return nil
end

local function ManualPages(n)
    local page = Slots.ManualPage(n)
    local pages = { page }
    for _ = 2, Slots.PagesNeeded(n) do
        page = page and Slots.NextPage(page)
        if page then pages[#pages + 1] = page end
    end
    return pages
end

-- Ist die Seite für „Automatisch“ frei? taken = { [Seite] = Leistennummer } der anderen Leisten.
function Slots.IsFree(page, taken, class)
    if taken and taken[page] then return false end
    if Slots.IsStancePage(page, class) then return false end
    if Slots.BlizzardUser(page) then return false end
    return true
end

-- Wählt count freie Seiten (Liste) oder nil, wenn nicht genug frei sind. partial = true: so viele, wie frei sind
-- (auch weniger oder keine) – damit baut ezBars die Leiste mit den freien Plätzen, der Rest bleibt leer.
function Slots.Allocate(count, taken, class, partial)
    local pages = {}
    for _, page in ipairs(Slots.AUTO_ORDER) do
        if #pages >= count then break end
        if Slots.IsFree(page, taken, class) then pages[#pages + 1] = page end
    end
    if #pages < count and not partial then return nil end
    return pages
end

-- Seiten aller Leisten dieses Charakters: { [n] = { Seite, … } }. Von Hand gewählte zuerst, dann die gemerkten
-- automatischen (auch abgeschalteter Leisten: dort liegen weiter ihre Zauber), zuletzt fehlende neu gewählt.
--
-- Resolve() rechnet nur (V-154): Tooltips, Status, /ezbars plaetze und die Schnittstelle fragen damit, ohne etwas zu
-- merken. Gemerkt wird allein mit commit = true – das rufen nur Bars.Apply und „Plätze neu wählen“. Ohne
-- Charakterdaten (vor dem Einloggen) wird nie gemerkt.
--
-- Wird eine Leiste kleiner, gibt sie ihre überzähligen Seiten frei (eine andere Leiste darf sie nehmen), merkt sie
-- sich aber als „frühere Seiten“ (char.spare[n]). Wächst sie wieder, bekommt sie zuerst diese zurück, soweit sie
-- noch frei sind – in derselben Reihenfolge, damit ihre Zauber wieder an derselben Stelle liegen.
function Slots.Resolve(commit)
    local char = ns.Char()
    local stored = char and char.pages or {}
    local spare = char and type(char.spare) == "table" and char.spare or {}
    local result, taken, missing, auto = {}, {}, {}, {}
    for n = 1, ns.MAX_BARS do
        if Slots.ManualPage(n) then
            result[n] = ManualPages(n)
            if #result[n] < Slots.PagesNeeded(n) then result[n].incomplete = true end     -- Seiten ab der gewählten reichen nicht
            if ns.BarSetting(n, "On") then
                for _, page in ipairs(result[n]) do taken[page] = taken[page] or n end
            end
        end
    end
    for n = 1, ns.MAX_BARS do
        if not result[n] then
            local keep = {}
            for _, page in ipairs(type(stored[n]) == "table" and stored[n] or {}) do
                if #keep < Slots.PagesNeeded(n) and Slots.IsAllowed(page) and not taken[page] then
                    keep[#keep + 1] = page
                    taken[page] = n
                end
            end
            result[n] = keep
            auto[n] = true
            if ns.BarSetting(n, "On") and #keep < Slots.PagesNeeded(n) then missing[#missing + 1] = n end
        end
    end
    for _, n in ipairs(missing) do
        local need = Slots.PagesNeeded(n)
        -- zuerst die früheren Seiten dieser Leiste, soweit noch frei
        for _, page in ipairs(type(spare[n]) == "table" and spare[n] or {}) do
            if #result[n] < need and Slots.IsAllowed(page) and Slots.IsFree(page, taken, Slots.Class()) then
                table.insert(result[n], page)
                taken[page] = n
            end
        end
        -- dann so viele Seiten wie frei; reicht es nicht, bekommt die Leiste die freien und der Rest bleibt leer
        local extra = Slots.Allocate(need - #result[n], taken, Slots.Class(), true)
        for _, page in ipairs(extra) do
            table.insert(result[n], page)
            taken[page] = n
        end
        if #result[n] < need then result[n].incomplete = true end
    end
    if commit and char then
        for n = 1, ns.MAX_BARS do
            if auto[n] then Slots.Remember(char, n, result[n]) end
        end
    end
    return result
end

-- Merkt die Seiten der Leiste n (nur aus Resolve(true)): char.pages[n] = Seiten, char.spare[n] = frühere Seiten,
-- die die Leiste gerade nicht nutzt (zuletzt abgegebene zuerst in ihrer alten Reihenfolge, dann ältere).
function Slots.Remember(char, n, pages)
    local old = type(char.pages[n]) == "table" and char.pages[n] or nil
    if not old and #pages == 0 then return false end
    local used, rest = {}, {}
    for _, page in ipairs(pages) do used[page] = true end
    local oldSpare = type(char.spare) == "table" and type(char.spare[n]) == "table" and char.spare[n] or {}
    for _, list in ipairs({ old or {}, oldSpare }) do
        for _, page in ipairs(list) do
            if not used[page] and Slots.IsAllowed(page) then
                used[page] = true
                rest[#rest + 1] = page
            end
        end
    end
    char.pages[n] = { unpack(pages) }
    if #rest > 0 or type(char.spare) == "table" then
        char.spare = type(char.spare) == "table" and char.spare or {}
        char.spare[n] = #rest > 0 and rest or nil
    end
    return true
end

-- Höchstzahl Knöpfe, die Leiste n gerade einen Aktionsplatz geben kann (je freie Seite 12, höchstens 12 × 12):
-- ihre eigenen Seiten plus die Seiten, die weder eine andere ezBars-Leiste, noch eine sichtbare Blizzard-Leiste,
-- noch die Gestalt-/Haltungsleisten der Klasse nutzen. Von Hand gewählt: die wählbaren Seiten ab der gewählten.
function Slots.FreeButtons(n, resolved)
    resolved = resolved or Slots.Resolve()
    local count = 0
    local manual = Slots.ManualPage(n)
    if manual then
        for _, page in ipairs(Slots.PAGES) do
            if page >= manual then count = count + 1 end
        end
    else
        local taken, own = {}, {}
        for m = 1, ns.MAX_BARS do
            -- wie Resolve: gemerkte Seiten abgeschalteter Leisten bleiben reserviert, von Hand gewählte nur, wenn an
            if m ~= n and (not Slots.ManualPage(m) or ns.BarSetting(m, "On")) then
                for _, page in ipairs(resolved[m] or {}) do taken[page] = m end
            end
        end
        for _, page in ipairs(resolved[n] or {}) do own[page] = true end
        for _, page in ipairs(Slots.PAGES) do
            if own[page] or (Contains(Slots.AUTO_ORDER, page) and Slots.IsFree(page, taken)) then count = count + 1 end
        end
    end
    return math.min(count * Slots.PER_PAGE, ns.MAX_BUTTONS)
end

-- Fehlende Plätze der eingeschalteten Leisten: { { n, count = Knöpfe, slots = Plätze, empty = leere Felder }, … }
function Slots.Shortages(resolved)
    resolved = resolved or Slots.Resolve()
    local list = {}
    for n = 1, ns.MAX_BARS do
        if ns.BarSetting(n, "On") then
            local count = Slots.ButtonCount(n)
            local slots = math.min(#(resolved[n] or {}) * Slots.PER_PAGE, count)
            if slots < count then list[#list + 1] = { n = n, count = count, slots = slots, empty = count - slots } end
        end
    end
    return list
end

function Slots.ShortageText(entry)
    return L.SHORT:format(ns.BarName(entry.n), entry.count, entry.slots, entry.empty)
end

function Slots.PagesFor(n)
    return Slots.Resolve()[n] or {}
end

-- Aktionsplatz für Knopf i einer Leiste mit diesen Seiten (oder nil, wenn die Seiten nicht reichen).
function Slots.SlotFor(pages, i)
    local page = pages[math.ceil(i / Slots.PER_PAGE)]
    if not page then return nil end
    return AS.SlotsOfPage(page)[((i - 1) % Slots.PER_PAGE) + 1]
end

-- Gemerkte automatische Seiten dieses Charakters vergessen und neu wählen.
function Slots.Reallocate()
    local char = ns.Char()
    if char then char.pages, char.spare = {}, nil end
    return Slots.Resolve(true)
end

---------------------------------------------------------------------------
-- Überschneidungen und Übersicht
---------------------------------------------------------------------------

-- Meldungen für alle sichtbaren Leisten: andere ezBars-Leiste, sichtbare Blizzard-Leiste, Gestaltleiste, zu wenig Plätze.
function Slots.Conflicts(resolved)
    resolved = resolved or Slots.Resolve()
    local list, owner = {}, {}
    for n = 1, ns.MAX_BARS do
        if ns.BarSetting(n, "On") then
            local pages = resolved[n] or {}
            local count, wanted = Slots.ButtonCount(n)
            local slots = math.min(#pages * Slots.PER_PAGE, count)
            if slots < count then
                list[#list + 1] = Slots.ShortageText({ n = n, count = count, slots = slots, empty = count - slots })
            end
            if wanted > count then list[#list + 1] = L.TRIMMED:format(ns.BarName(n), ns.MAX_BUTTONS, count, wanted) end
            for _, page in ipairs(pages) do
                local first, last = Slots.Range(page)
                if owner[page] then
                    list[#list + 1] = L.CONFLICT_BAR:format(ns.BarName(owner[page]), ns.BarName(n), first, last)
                else
                    owner[page] = n
                end
                local blizzard = Slots.BlizzardUser(page)
                if blizzard then list[#list + 1] = L.CONFLICT_BLIZZARD:format(ns.BarName(n), blizzard, first, last) end
                if Slots.IsStancePage(page) then list[#list + 1] = L.CONFLICT_STANCE:format(ns.BarName(n), first, last) end
            end
        end
    end
    return list
end

-- Zustand einer Seite für /ezbars plaetze.
function Slots.PageState(page, resolved)
    resolved = resolved or Slots.Resolve()
    local users = {}
    for n = 1, ns.MAX_BARS do
        if ns.BarSetting(n, "On") and Contains(resolved[n], page) then users[#users + 1] = ns.BarName(n) end
    end
    local states = {}
    if #users > 0 then states[#states + 1] = L.PAGE_STATE_EZBARS:format(table.concat(users, ", ")) end
    local blizzard = Slots.BlizzardUser(page)
    if blizzard then states[#states + 1] = L.PAGE_STATE_BLIZZARD:format(blizzard) end
    if Slots.IsStancePage(page) then states[#states + 1] = L.PAGE_STATE_STANCE end
    return #states > 0 and table.concat(states, "; ") or L.PAGE_STATE_FREE
end

-- Einträge für die Auswahl „Aktionsplätze“ (Wert als Text, wie Blizzards Dropdown-Einstellungen).
function Slots.DropdownValues()
    local values = { { "auto", L.PAGE_AUTO } }
    for _, page in ipairs(Slots.PAGES) do
        local first, last = Slots.Range(page)
        values[#values + 1] = { tostring(page), L.PAGE_LABEL:format(first, last, Slots.PageLabel(page)) }
    end
    return values
end

-- Für ns.API: Leisten mit Anordnung und Plätzen dieses Charakters.
function Slots.Describe()
    local resolved, list = Slots.Resolve(), {}
    for n = 1, ns.MAX_BARS do
        local count = Slots.ButtonCount(n)
        local slots = {}
        for i = 1, count do slots[#slots + 1] = Slots.SlotFor(resolved[n] or {}, i) end
        list[#list + 1] = {
            index = n, name = ns.BarName(n), shown = ns.BarSetting(n, "On") == true,
            cols = ns.BarSetting(n, "Cols"), rows = ns.BarSetting(n, "Rows"), buttons = count, slots = slots,
            empty = count - #slots,         -- Felder ohne Aktionsplatz (zu wenig freie Seiten)
        }
    end
    return list
end

function Slots.UsedSlots()
    local used = {}
    for _, bar in ipairs(Slots.Describe()) do
        if bar.shown then
            for _, slot in ipairs(bar.slots) do used[slot] = used[slot] or bar.index end
        end
    end
    return used
end
