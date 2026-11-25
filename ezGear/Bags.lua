local _, ns = ...
local Core = ezCore

--[[
    Grüner Pfeil „besser“ (und roter Pfeil „schlechter“) an den Taschenplätzen.

    EINE Anmeldestelle: ezCores Platzmarken (Core.SlotMarks.Add, GEAR-09; VP-37, Frage 18 – Empfehlung umgesetzt,
    Antwort offen). Läuft ezBag, reicht ezCore die Marke an ezBag weiter – ezBag zeichnet sie in der
    zusammengefassten Tasche, Bank, Gildenbank und im ezBag-Fenster; in Blizzards einzelnen Taschen zeichnet ezCore. Ohne
    ezBag zeichnet ezCore sie selbst an Blizzards Taschen UND an Blizzards Bank (gepoolte BankPanel-Knöpfe; vorher bekam die Bank den Pfeil nur über ezBag). Alle Marken teilen sich die Ecke oben
    links, niemand hookt dieselben Knöpfe doppelt. Bis Welle 7 hängte sich ezGear ohne ezBag selbst hinter Blizzards
    Taschen (ContainerFrameMixin:UpdateItems) und meldete sich mit ezBag direkt dort an – beides macht jetzt ezCore.

    Läuft ezPanel, meldet ezGear dort die Quelle „besseres Teil in der Tasche“ an (Baustein „Meldungen“; unten).
]]

local Bags = {}
ns.Bags = Bags

local MARK_KEY = "ezGear.upgrade"
Bags.MARK_KEY = MARK_KEY
local ARROW_MARK = { atlas = "bags-greenarrow", useAtlasSize = true, sign = "green" }   -- sign: Zeichen (EC-47)
Bags.ARROW_MARK = ARROW_MARK
-- Roter Pfeil nach unten: derselbe Atlas, gedreht – nur, wo Marken sich drehen lassen (ezCore selbst:
-- SlotMarks.ROTATION; ezBag: SLOT_MARK_ROTATION), sonst stünde ein roter Pfeil nach oben da.
local DOWN_MARK = { atlas = "bags-greenarrow", useAtlasSize = true, rotation = math.pi, desaturate = true,
    r = ns.Marks.DOWN_COLOR[1], g = ns.Marks.DOWN_COLOR[2], b = ns.Marks.DOWN_COLOR[3], sign = "red" }
Bags.DOWN_MARK = DOWN_MARK
-- Gelber Pfeil „besser, sobald gelernt“ bzw. „… sobald die Stufe reicht“ (Score.LATER): derselbe Atlas, entsättigt und gelb getönt; Zeichen „?“ (orange)
local LEARN_MARK = { atlas = "bags-greenarrow", useAtlasSize = true, desaturate = true,
    r = ns.Marks.LEARN_COLOR[1], g = ns.Marks.LEARN_COLOR[2], b = ns.Marks.LEARN_COLOR[3], sign = "orange" }
Bags.LEARN_MARK = LEARN_MARK

local marks           -- ezCores Platzmarken (Core.SlotMarks), sobald ezGear dort angemeldet ist
local missing = false -- es wurde nach einem Gegenstand gefragt, dessen Daten noch fehlen

local function LinkOf(itemID, link)
    if type(link) == "string" and not ns.IsSecret(link) then return link end
    if type(itemID) ~= "number" then return nil end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, itemLink = ns.Call(info, itemID)
    itemLink = ns.Plain(itemLink)
    return type(itemLink) == "string" and itemLink or nil
end

-- Platzmarke: fn(itemID, link, bag, slot, quality) → Marke oder nil
function Bags.MarkFor(itemID, link)
    if not ns.Active("bagArrows") then return nil end
    link = LinkOf(itemID, link)
    if not link then
        if type(itemID) == "number" then missing = true end
        return nil
    end
    local kind = ns.Score.Check(link)
    if kind == "pending" then
        missing = true
        return nil
    end
    if kind == "better" then return ARROW_MARK end
    if ns.Score.LATER[kind] then return LEARN_MARK end
    if kind == "worse" and Bags.DownInEzBag() then return DOWN_MARK end
    return nil
end

-- Zeichnet sie gerade ezBag (ezCore reicht die Marke dorthin weiter)?
function Bags.ViaEzBag()
    return marks ~= nil and type(marks.ViaEzBag) == "function" and marks.ViaEzBag() == true
end

-- Roter Pfeil an den Platzmarken: Schalter an und die zeichnende Stelle kann Marken drehen – ezCore selbst
-- (SlotMarks.ROTATION) bzw. ezBag (SLOT_MARK_ROTATION). Name aus der Zeit, als nur ezBag Platzmarken hatte.
function Bags.DownInEzBag()
    if not ns.Enabled("downArrows") then return false end
    if marks and not Bags.ViaEzBag() then return marks.ROTATION == true end
    local api = Core.API("ezBag")
    return type(api) == "table" and api.SLOT_MARK_ROTATION == true
end

---------------------------------------------------------------------------
-- Neu zeichnen, wenn sich die Bewertung ändert
---------------------------------------------------------------------------

function Bags.Refresh()
    missing = false
    if marks and type(marks.Refresh) == "function" then marks.Refresh() end
end

-- Bei ezCores Platzmarken anmelden (in needs geprüft: SlotMarks.Add) → true
function Bags.Attach()
    if marks then return true end
    local slotMarks = Core.SlotMarks
    if not (slotMarks and type(slotMarks.Add) == "function") then return false end
    local ok, added = pcall(slotMarks.Add, MARK_KEY, {
        order = 10, owner = "ezGear",
        fn = function(itemID, link) return Bags.MarkFor(itemID, link) end,
    })
    if not (ok and added) then return false end
    marks = slotMarks
    return true
end

ns.OnReady(function()
    ns.Try("Bags", Bags.Attach)

    ns.Listen("SCORES_CHANGED", Bags.Refresh)
    -- „Zeichen am Leuchten“ umgelegt (ezCore 1.12.0): Zeichen an den Pfeilen sofort nachziehen
    Core.Listen("GLOW_MARKS_CHANGED", function() Bags.Refresh() end, "ezGear")
    -- Forever++ hat seine Pfeile umgeschaltet: Tasche und Handelsfenster (Trade.lua) folgen gemeinsam
    Core.Listen("OTHER_ADDONS_CHANGED", function() Bags.Refresh() end, "ezGear")
    ns.OnSettingChanged(function(key)
        if key == "bagArrows" then Bags.Refresh() end
    end)
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if missing then Bags.Refresh() end
    end)
    ns.On("BAG_UPDATE_DELAYED", ns.Score.BagsChanged)      -- vor der Meldung unten: Gegenstücke zum Zweihänder neu lesen
end)

---------------------------------------------------------------------------
-- Meldung „besseres Teil in der Tasche“ für ezPanels Baustein „Meldungen“ (ezCore.API("ezPanel").AddWarning,
-- beschrieben in ezPanel/API.lua). ezPanel fragt die Quelle bei jedem Neuzeichnen (alle paar Sekunden) – deshalb
-- wird nur gezählt, wenn sich Taschen oder Bewertung geändert haben. Abschaltbar hier (Schalter „Meldung auf
-- ezPanels Leiste“) und in ezPanels Menü „Quellen“; ohne ezPanel passiert nichts. Zeigt Pawn die Taschen-Pfeile,
-- meldet ezGear auch hier nichts (ns.FOREIGN).
---------------------------------------------------------------------------

local WARNING_KEY = "ezGear.bagUpgrade"
Bags.WARNING_KEY = WARNING_KEY
local panel             -- ezPanels Schnittstelle, sobald die Quelle dort angemeldet ist
local upgrades          -- { Link, …, pending = true|false } der besseren Teile in den Taschen; nil = neu zählen

-- Plätze, die ezGear gerade selbst umgezogen hat (Angel- bzw. Reit-Set, Swap.lua) → { [Platz] = itemID } oder nil.
-- Dort steckt für eine Weile ein Set-Teil (Angelhut, Karotte am Stiel); die eigene, nur vorübergehend abgelegte
-- Ausrüstung liegt in der Tasche und wäre dagegen „besser“ – wie jedes andere Teil für diesen Platz.
function Bags.SwappedSlots()
    local char = ns.Char and ns.Char()
    local state = type(char) == "table" and char.swap or nil
    if type(state) ~= "table" or type(state.items) ~= "table" or next(state.items) == nil then return nil end
    return state.items
end

-- Bags.Upgrades() → Liste der Links mit Stand „besser“ (pending: Daten mindestens eines Teils laden noch).
-- Solange ezGear umgezogen hat, zählen Teile für die umgezogenen Plätze nicht mit (Fund der Gegenprüfung, Welle 3:
-- sonst meldete die Leiste bei jedem Aufsteigen und Angeln die eigene Ausrüstung); nach dem Zurückziehen wieder.
function Bags.Upgrades()
    if upgrades then return upgrades end
    local list = { pending = false }
    local swapped = Bags.SwappedSlots()
    -- Normale Taschen ("bags", wie Bags.Count): Ausrüstung liegt weder in der Reagenzientasche noch am Schlüsselbund.
    Core.ForEachBagItem(function(_, _, info)
        local link = ns.Plain(info.hyperlink)
        local kind, compared
        if type(link) == "string" then kind, compared = ns.Score.Check(link) end
        if kind == "better" then
            -- Angelrute (Zweihänder): auch das eigene Schild in der Tasche wäre im Paar gegen die Rute „besser“
            local moved = swapped and compared and (swapped[compared.slot]
                or (compared.twoHand and swapped[ns.Score.SLOT.MAINHAND]))
            if not moved then list[#list + 1] = link end
        elseif kind == "pending" then
            list.pending = true
        end
    end, "bags")
    upgrades = list
    return list
end

-- Text der Meldung oder nil (nichts besser, abgeschaltet, Pawn übernimmt)
function Bags.WarningText()
    if not ns.Active("panelUpgrade") then return nil end
    local list = Bags.Upgrades()
    if #list == 0 then return nil end
    if #list == 1 then return ns.L.PANEL_UPGRADE_ONE:format(list[1]) end
    return ns.L.PANEL_UPGRADE_MANY:format(#list)
end

-- Taschen oder Bewertung haben sich geändert: neu zählen lassen und ezPanel Bescheid geben
function Bags.RecountUpgrades()
    upgrades = nil
    if panel and type(panel.RefreshWarnings) == "function" then pcall(panel.RefreshWarnings) end
end

-- Bei ezPanel anmelden, falls es läuft und Meldungen anderer Module annimmt → true
function Bags.AttachPanel()
    if panel then return true end
    local api = Core.API("ezPanel")
    if not (api and type(api.AddWarning) == "function") then return false end
    local ok, added = pcall(api.AddWarning, WARNING_KEY, ns.L.PANEL_SOURCE, function() return Bags.WarningText() end)
    if not (ok and added) then return false end
    panel = api
    ns.Listen("SCORES_CHANGED", Bags.RecountUpgrades)
    ns.On("BAG_UPDATE_DELAYED", Bags.RecountUpgrades)
    -- nachgeladene Daten kommen beim Einloggen in Schüben: gesammelt nachzählen, und nur, wenn etwas gefehlt hat
    -- (hat die neue Bewertung selbst schon nachgezählt, Score.OnKnowledge, bleibt es dabei)
    local recountSoon = ns.Throttle(function()
        if upgrades and upgrades.pending then Bags.RecountUpgrades() end
    end, 0.5)
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if upgrades and upgrades.pending then recountSoon() end
    end)
    return true
end

function Bags.ViaPanel() return panel ~= nil end

ns.OnReady(function() ns.Try("PanelWarning", Bags.AttachPanel) end)

ns.AddStatusLine(function()
    return panel and ns.L.STATUS_PANEL_ON or ns.L.STATUS_PANEL_OFF
end)

-- Wie stehen die Teile in den Taschen? → { better, learn, worse, same, nostats, level, unusable, pending, total }
function Bags.Count()
    local count = { better = 0, learn = 0, worse = 0, same = 0, nostats = 0, level = 0, unusable = 0,
        pending = 0, total = 0 }
    -- Nur die normalen Taschen (Core.BagList("bags")): Ausrüstung liegt weder in der Reagenzientasche noch am
    -- Schlüsselbund, "carried" brächte hier nichts (geprüft bei der Umstellung auf ezCores Taschenlisten).
    Core.ForEachBagItem(function(_, _, info)
        local link = ns.Plain(info.hyperlink)
        local kind = type(link) == "string" and ns.Score.Check(link) or nil
        if kind and count[kind] then
            count[kind] = count[kind] + 1
            count.total = count.total + 1
        end
    end, "bags")
    return count
end

ns.AddStatusLine(function()
    local c = Bags.Count()
    return ns.L.STATUS_BAG_COUNT:format(c.total, c.better, c.learn, c.worse, c.unusable, c.level, c.nostats, c.pending)
end)

ns.AddStatusLine(function()
    if Bags.ViaEzBag() and ns.Enabled("downArrows") and not Bags.DownInEzBag() then return ns.L.STATUS_DOWN_EZBAG end
end)

ns.AddStatusLine(function()
    if not marks then return ns.L.STATUS_BAGS_NONE end
    return Bags.ViaEzBag() and ns.L.STATUS_BAGS_EZBAG or ns.L.STATUS_BAGS_BLIZZARD
end)
