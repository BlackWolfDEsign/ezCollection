local _, ns = ...
local Core = ezCore

--[[
    Tooltip-Pipeline für Gegenstände: EIN Eintrag bei Blizzards TooltipDataProcessor, die Module
    hängen Abschnitte an (vorher hatte ezBag den einzigen Hook; ezAuction & Co. kommen dazu).

    ezCore.Tooltip.AddItemSection(key, order, fn)
      fn(tooltip, itemID, data) fügt Zeilen an; order bestimmt die Reihenfolge (klein zuerst).
      Ein Abschnitt mit demselben key ersetzt den alten.
      order ist eine Zahl oder der Name eines Platzes aus ezCore.Tooltip.ORDER ("price") – benannte Plätze statt
      Zahlen, die die Module in Kommentaren aufeinander abstimmen (W-14). Tooltip.Order(order) → Zahl.
    Nur GameTooltip und ItemRefTooltip, nie verbotene Tooltips, nie geheime Gegenstände.
    Einheiten (Spieler, NPCs): ezCore.Tooltip.AddUnitSection(key, order, fn) in UnitTooltip.lua.

    Tooltip.HasSection(key) → true, wenn ein Abschnitt mit diesem key angemeldet ist (ezCores eigene Abschnitte
      „Anzahl bei Twinks“ und „Item-Wissen“ weichen, solange ezBag dieselben noch anmeldet; ItemTooltip.lua).
    Tooltip.RemoveItemSection(key)
    Zauber: Tooltip.AddSpellSection(key, order, fn) – fn(tooltip, spellID, data) für Zauber-Tooltips (Zauberbuch,
      Aktionsleiste), dieselben Regeln (nur GameTooltip/ItemRefTooltip, nichts Geheimes, Fehler ins Fehler-Log).
    Eine Aussage je Zeile (FP-06): Tooltip.ClaimLine(was, owner, fn(itemID, link) → true) meldet an, dass ein
      Abschnitt eine Aussage zeigt ("usable", "level", "class", "price" …; fn nil hebt auf);
      Tooltip.Shows(itemID, was, link) → true, owner – zeigt schon ein Abschnitt diese Aussage? Dann lässt ein
      anderes Modul seine eigene Zeile dazu weg.
    Spielobjekte (Welle 23c, A29; vorher meldete sich ezQuest selbst bei TooltipDataProcessor an):
      Tooltip.AddObjectSection(key, order, fn, owner) – fn(tooltip, name, data, objectID) für Tooltips von Spielobjekten
        (Kraut, Erzader, Quest-Objekt, Kiste); order eine Zahl oder ein Platz aus Tooltip.OBJECT_ORDER. Nur GameTooltip,
        nie verbotene Tooltips; Fehler ins Fehler-Log. Tooltip.RemoveObjectSection(key).
      Tooltip.ObjectName(tooltip, data) → Name des Objekts: erste Zeile der Tooltip-Daten, sonst die erste Zeile des
        Tooltips (Forevers Objekt-Tooltip trägt nur den Namen, Daten-Probe F8: { dataInstanceID, type = 4 }).
      Tooltip.ObjectID(name) → objectID oder nil: das Objekt, auf das die Interaktion zielt („softinteract“, gleicher
        Name; Zerleger Core.ObjectID in Npcs.lua), sonst die Namensliste der gesehenen Objekte (Discovery.ObjectByName).
      Tooltip.SoftObjectID(name) → objectID oder nil: nur die genaue Kennung aus „softinteract“ (gleicher Name), ohne
        Rückfall auf die Namensliste – für Schreibende, die kein gleichnamiges Objekt treffen dürfen (Welle 27).
    Platz „loot“ (Welle 23c, A28): eigene Beute je Gegenstand (ezLoot, „Beute bei dir: …“) hinter den Fundorten.

    Abstand und Reihenfolge (S-1811-Tooltipabstand, Gesamtreview 18.11.2026; Spielbefund „hier fehlt abstand zwischen
    den quests sowie zum loot reiter“):
      Tooltip.Gap(tooltip, group) – EIN Trenner für alle Abschnitte der Sammlung: eine Leerzeile vor dem ersten Text
        eines Abschnitts, nicht in einem leeren Tooltip und nicht nach einer Leerzeile. Mit group (Text) steht keine
        Leerzeile, wenn der Abschnitt direkt davor in demselben Durchlauf dieselbe Gruppe nannte (ezLoots Beute und
        Kürschnern, ezCores Fundorte und ezLoots „Beute bei dir“, Zeilen derselben Quest). Erst aufrufen, wenn der
        Abschnitt wirklich etwas schreibt. → true, wenn eine Leerzeile dazukam.
      Tooltip.LineBlank(tooltip, i) → true, wenn Zeile i (Standard: die letzte) leer ist; gesperrte oder unlesbare
        Texte gelten als Inhalt (nie verglichen, Leitlinie 6).
      Tooltip.Later(tooltip, fn, defer) – Zeilen nach denen fremder Addons: defer wahr → fn(tooltip) erst im nächsten
        Bild, solange derselbe Tooltip steht (nicht neu aufgebaut, gleiche erste Zeile), danach tooltip:Show(); sonst
        und innerhalb eines solchen späten Durchlaufs sofort. → Rückgabe von fn, true (sofort) bzw. nil, false.
      Tooltip.RunSections(tooltip, list, a, b, c) – ein Durchlauf über angemeldete Abschnitte (alle Pipelines): ruft
        fn(tooltip, a, b, c), Fehler ins Fehler-Log. Tooltip.Begin(tooltip) zählt einen Neuaufbau (späte Durchläufe
        eines älteren Aufbaus verfallen); die Pipelines rufen es selbst, dazu Blizzards OnTooltipCleared (HookScript).
]]

local Tooltip = {}
Core.Tooltip = Tooltip

local sections = {}

---------------------------------------------------------------------------
-- Abstand zwischen Abschnitten, Zeilen nach fremden Addons (S-1811-Tooltipabstand)
---------------------------------------------------------------------------

-- Nur Tabellen in ezCore, nie Werte in Blizzards Tooltip (Leitlinie 5): schwach geschlüsselt nach Tooltip.
local builds = setmetatable({}, { __mode = "k" })    -- [tooltip] = Zahl der Neuaufbauten
local lastGap = setmetatable({}, { __mode = "k" })   -- [tooltip] = { build, pass, group }
local watched = setmetatable({}, { __mode = "k" })   -- [tooltip] = true: OnTooltipCleared angehängt
local passNo, currentPass, latePass = 0, nil, false
local gapCalls = 0                                   -- zählt Gap-Aufrufe (ein Abschnitt ohne Gap löst die Gruppe)

local function Builds(tooltip) return builds[tooltip] or 0 end

function Tooltip.Begin(tooltip)
    if type(tooltip) == "table" then builds[tooltip] = Builds(tooltip) + 1 end
end

local function Watch(tooltip)
    if watched[tooltip] or type(tooltip) ~= "table" then return end
    watched[tooltip] = true
    if type(tooltip.HookScript) == "function" then
        pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) Tooltip.Begin(self) end)
    end
end

-- Linker Text der Zeile i; false = nicht lesbar (kein Urteil möglich).
local function LineText(tooltip, i)
    local name = tooltip.GetName and Core.Plain(tooltip:GetName())
    local fs = type(name) == "string" and rawget(_G, name .. "TextLeft" .. i) or nil
    if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return false end
    local ok, text = pcall(fs.GetText, fs)
    if not ok then return false end
    return text
end

local function NumLines(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.NumLines) ~= "function" then return 0 end
    local ok, n = pcall(tooltip.NumLines, tooltip)
    return ok and Core.Num(n) or 0
end

function Tooltip.LineBlank(tooltip, i)
    if type(tooltip) ~= "table" then return false end
    i = i or NumLines(tooltip)
    if type(i) ~= "number" or i < 1 then return false end
    local text = LineText(tooltip, i)
    if Core.IsSecret(text) or text == false then return false end   -- gesperrt zuerst (Leitlinie 6), dann unlesbar
    if text == nil then return true end
    return type(text) == "string" and text:match("^%s*$") ~= nil
end

function Tooltip.Gap(tooltip, group)
    if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return false end
    Watch(tooltip)   -- ein Neuaufbau (OnTooltipCleared) beendet die Gruppe auch außerhalb der Pipelines
    gapCalls = gapCalls + 1
    local last, build = lastGap[tooltip], Builds(tooltip)
    lastGap[tooltip] = { build = build, pass = currentPass, group = group }
    if group ~= nil and last and last.group == group and last.build == build and last.pass == currentPass then
        return false
    end
    local n = NumLines(tooltip)
    if n < 1 or Tooltip.LineBlank(tooltip, n) then return false end
    tooltip:AddLine(" ")
    return true
end

local function FirstText(tooltip)
    local text = LineText(tooltip, 1)
    if Core.IsSecret(text) or text == false then return nil end
    return text
end

-- Ein Durchlauf: Abschnitte der Reihe nach, Fehler ins Fehler-Log. Schreibt ein Abschnitt Zeilen, ohne Gap zu rufen,
-- gilt die Gruppe davor nicht mehr (sonst klebte der nächste Abschnitt derselben Gruppe an dessen Zeilen).
function Tooltip.RunSections(tooltip, list, a, b, c)
    local outer = currentPass
    passNo = passNo + 1
    currentPass = passNo
    for _, section in ipairs(list) do
        local before, calls = NumLines(tooltip), gapCalls
        local ok, err = pcall(section.fn, tooltip, a, b, c)
        if not ok then Core.Error(section.owner, err, "Tooltip " .. tostring(section.key)) end
        if gapCalls == calls and NumLines(tooltip) > before then lastGap[tooltip] = nil end
    end
    currentPass = outer
end

function Tooltip.Later(tooltip, fn, defer)
    if type(fn) ~= "function" then return nil, false end
    local timer = rawget(_G, "C_Timer")
    local after = type(timer) == "table" and timer.After or nil
    if not defer or latePass or type(after) ~= "function" then return fn(tooltip), true end
    Watch(tooltip)
    local build, first = Builds(tooltip), FirstText(tooltip)
    after(0, function()
        if Builds(tooltip) ~= build or FirstText(tooltip) ~= first then return end
        if not (tooltip.IsShown and tooltip:IsShown()) then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local before = NumLines(tooltip)
        local outerLate, outerPass = latePass, currentPass
        passNo = passNo + 1
        latePass, currentPass = true, passNo
        local ok, err = pcall(fn, tooltip)
        latePass, currentPass = outerLate, outerPass
        if not ok then Core.Error(Core.name, err, "Tooltip später") end
        if NumLines(tooltip) > before and tooltip.Show then tooltip:Show() end
    end)
    return nil, false
end

-- Plätze der Abschnitte im Gegenstands-Tooltip, klein zuerst. Wer einen neuen Abschnitt braucht, trägt hier einen
-- Platz ein, statt eine Zahl zwischen zwei fremde zu legen. Die Zahlen sind die, die die Module heute nennen.
Tooltip.ORDER = {
    counts = 10,        -- Bestand über alle Twinks (ezBag)
    knowledge = 20,     -- Item-Wissen: Schlagwörter, Sammlung, Rezept bekannt (ezBag)
    upgrade = 25,       -- Verbesserung für die Ausrüstung (ezGear)
    recipe = 27,        -- Rezept und Zutaten (ezCraft)
    salvage = 28,       -- Zerlegen (ezCraft)
    shopping = 30,      -- Einkaufsliste (ezCraft)
    price = 40,         -- Auktionspreis (ezAuction)
    default = 50,       -- ohne Angabe
    quest = 70,         -- Questgegenstand (ezQuest)
    gathering = 80,     -- Fundorte (ezCore, Gathering.lua)
    loot = 85,          -- eigene Beute je Gegenstand (ezLoot; Welle 23c, A28)
}
-- Plätze im Einheiten-Tooltip (UnitTooltip.lua, Tooltip.AddUnitSection); die eingebauten Zeilen stehen davor.
Tooltip.UNIT_ORDER = {
    default = 50,
    drops = 60,         -- mögliche Beute (ezLoot)
}

-- Zahl zu einem Platz: Zahl bleibt Zahl, ein Name kommt aus der Tabelle (Standard Tooltip.ORDER), sonst default.
function Tooltip.Order(order, places)
    places = type(places) == "table" and places or Tooltip.ORDER
    if type(order) == "number" then return order end
    if type(order) == "string" and type(places[order]) == "number" then return places[order] end
    return places.default or 50
end

function Tooltip.AddItemSection(key, order, fn, owner)
    for i = #sections, 1, -1 do
        if sections[i].key == key then table.remove(sections, i) end
    end
    sections[#sections + 1] = { key = key, order = Tooltip.Order(order), fn = fn, owner = owner or Core.name }
    table.sort(sections, function(a, b) return a.order < b.order end)
end

function Tooltip.RemoveItemSection(key)
    for i = #sections, 1, -1 do
        if sections[i].key == key then table.remove(sections, i) end
    end
end

function Tooltip.HasSection(key)
    for _, section in ipairs(sections) do
        if section.key == key then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Eine Aussage je Zeile (FP-06)
---------------------------------------------------------------------------

local claims = {}   -- was → { [owner] = fn }

function Tooltip.ClaimLine(what, owner, fn)
    if type(what) ~= "string" or owner == nil then return false end
    claims[what] = claims[what] or {}
    claims[what][owner] = type(fn) == "function" and fn or nil
    return true
end

function Tooltip.Shows(itemID, what, link)
    local list = claims[what]
    if not list or Core.IsSecret(itemID) then return false, nil end
    for owner, fn in pairs(list) do
        local ok, yes = pcall(fn, itemID, link)
        if ok and yes == true then return true, owner end
    end
    return false, nil
end

---------------------------------------------------------------------------
-- Zauber-Tooltips
---------------------------------------------------------------------------

local spellSections = {}

function Tooltip.AddSpellSection(key, order, fn, owner)
    for i = #spellSections, 1, -1 do
        if spellSections[i].key == key then table.remove(spellSections, i) end
    end
    if type(fn) ~= "function" then return false end
    spellSections[#spellSections + 1] = { key = key, order = Tooltip.Order(order), fn = fn, owner = owner or Core.name }
    table.sort(spellSections, function(a, b) return a.order < b.order end)
    return true
end

local function OnSpellTooltip(tooltip, data)
    if #spellSections == 0 then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local spellID = data and data.id
    if Core.IsSecret(spellID) or type(spellID) ~= "number" then return end
    Tooltip.Begin(tooltip)
    Tooltip.RunSections(tooltip, spellSections, spellID, data)
end
Tooltip.OnSpellTooltip = OnSpellTooltip

---------------------------------------------------------------------------
-- Spielobjekte (Welle 23c, A29)
---------------------------------------------------------------------------

-- Plätze im Tooltip eines Spielobjekts; Blizzards Zeile mit dem Namen steht davor.
Tooltip.OBJECT_ORDER = {
    default = 50,
    quest = 55,         -- Quest-Fortschritt (ezQuest)
}

local objectSections = {}

function Tooltip.AddObjectSection(key, order, fn, owner)
    Tooltip.RemoveObjectSection(key)
    if type(fn) ~= "function" then return false end
    objectSections[#objectSections + 1] = { key = key, order = Tooltip.Order(order, Tooltip.OBJECT_ORDER), fn = fn,
        owner = owner or Core.name }
    table.sort(objectSections, function(a, b) return a.order < b.order end)
    return true
end

function Tooltip.RemoveObjectSection(key)
    for i = #objectSections, 1, -1 do
        if objectSections[i].key == key then table.remove(objectSections, i) end
    end
end

local function FirstLine(tooltip)
    local name = tooltip.GetName and Core.Plain(tooltip:GetName())
    local fs = type(name) == "string" and rawget(_G, name .. "TextLeft1") or nil
    return type(fs) == "table" and fs.GetText and Core.Plain(fs:GetText()) or nil
end

function Tooltip.ObjectName(tooltip, data)
    local lines = type(data) == "table" and not Core.IsSecret(data) and data.lines or nil
    local first = type(lines) == "table" and not Core.IsSecret(lines) and lines[1] or nil
    local name = type(first) == "table" and Core.Plain(first.leftText) or nil
    if (type(name) ~= "string" or name == "") and type(tooltip) == "table" then name = FirstLine(tooltip) end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function Tooltip.SoftObjectID(name)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local softName = Core.Plain(Core.Call(rawget(_G, "UnitName"), "softinteract"))
    if softName == name and Core.ObjectID then
        return Core.ObjectID(Core.Call(rawget(_G, "UnitGUID"), "softinteract"))
    end
    return nil
end

function Tooltip.ObjectID(name)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local id = Tooltip.SoftObjectID(name)
    if id then return id end
    local D = Core.Discovery
    if type(D) == "table" and type(D.ObjectByName) == "function" then
        return Core.Num(Core.Call(D.ObjectByName, name))
    end
    return nil
end

local function OnObjectTooltip(tooltip, data)
    if #objectSections == 0 or tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local name = Tooltip.ObjectName(tooltip, data)
    if not name then return end
    local id = Tooltip.ObjectID(name)
    Tooltip.Begin(tooltip)
    Tooltip.RunSections(tooltip, objectSections, name, data, id)
end
Tooltip.OnObjectTooltip = OnObjectTooltip

-- Für Tests und /dump: die Funktion eines angemeldeten Abschnitts (kind = "spell" für Zauber, "object" für
-- Spielobjekte, sonst Gegenstand).
function Tooltip.SectionFn(key, kind)
    local list = kind == "spell" and spellSections or kind == "object" and objectSections or sections
    for _, section in ipairs(list) do
        if section.key == key then return section.fn end
    end
    return nil
end

-- Link des gezeigten Gegenstands (aus den Tooltip-Daten, sonst vom Tooltip selbst).
function Tooltip.ItemLink(tooltip, data)
    local link = data and data.hyperlink
    if (type(link) ~= "string" or Core.IsSecret(link)) and tooltip.GetItem then
        local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
        link = ok and itemLink or nil
    end
    if Core.IsSecret(link) then return nil end
    return link
end

local function OnItemTooltip(tooltip, data)
    if #sections == 0 then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local itemID = data and data.id
    if Core.IsSecret(itemID) or type(itemID) ~= "number" then return end
    Tooltip.Begin(tooltip)
    Tooltip.RunSections(tooltip, sections, itemID, data)
end

Tooltip.OnItemTooltip = OnItemTooltip

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    if Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnSpellTooltip)
    end
    if Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
    end
end
