local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Pfeil und Stufe in Blizzards Rezeptzeilen (Nutzer am 24.11.2026, wörtlich: „kann ezgear auch die bei den rezepten beim
    item was hergestellt werden kann, auch anzeigen lassen was meine ausrüstung verbessert und nicht? (pfeile) und eine eine
    sortiermöglichkeit nach lvl (herstelltbares item) einbauen? oder ggf fenster etwas verbreitern und pfeil und lvl mit ans
    rezept schreiben, siehe bild an/in die zeile mit?“; die Sortierung steht in Sort.lua).

    Pfeil     ezGears eigener Pfeil (ezCore.API("ezGear"): SetUpgradeIcon auf einem eigenen Halter) und sein graues Zeichen
              (StatusSign) für jedes Rezept, das Ausrüstung herstellt. Waren, Tränke und Verzauberungen bleiben ohne. Nur
              mit ezGear; bewertet wird nur dort. Er steht rechts bei Stufe und Prozentzahl – Blizzards oranges
              Doppelzeichen für den Fertigkeitspunkt bleibt links vor dem Namen.
    Stufe     die zum Benutzen nötige Stufe des hergestellten Gegenstands (C_Item.GetItemInfo, itemMinLevel), rot, solange
              deine nicht reicht. Gewählt statt der Gegenstandsstufe, weil sie sagt, ab wann das Teil nützt – so rechnet auch
              ezGears gelber Pfeil. Die Reihenfolge ist fast dieselbe: von 1302 herstellbaren Ausrüstungsteilen mit Daten
              liegt die Gegenstandsstufe bei 1158 genau 5 über der nötigen (Client-Tabellen ItemSparse, Build 1.60.1.71037).
              Ohne nötige Stufe (Stufe 0 oder 1, etwa Hemden) bleibt die Spalte leer. Die Gegenstandsstufe nennt der Tooltip.
    Spalten   von rechts: Pfeil, Stufe, mit Abstand die Prozentzahl. Stufe und Pfeil gehören zum Gegenstand, die Prozentzahl
              zum Zeichen vor dem Namen; vorher stand „7“ neben „100 %“ und las sich wie eine Zahl (Nutzer am 24.11.2026 nach
              dem ersten Bild: „weiß keiner direkt was was davon ist“, Wahl „% | Stufe Pfeil“).
    Breite    Die Liste macht Wide.lua breiter. Reicht es für einen Namen trotzdem nicht, wird seine Schrift kleiner (bis
              Rows.MIN_SCALE), erst dann kürzt der Client mit „…“ – Blizzards Tooltip der Zeile nennt dann den vollen Namen.
              Gefragt wird der Client selbst (IsTruncated): Auf dem ersten Bild lag die gerechnete Breite daneben
              („Runenverzierte Kupferh…“ in fast voller Größe). Spalten, die eine Zeile nicht braucht, bekommt der Name.

    Alles über eigene Regionen; von Blizzards Zeile setzt ezCraft nur Schriftgröße und Breite des Namens (nichts in
    Blizzards Tabellen, kein geschützter Rahmen).

      Rows.Product(info)  → itemID des hergestellten Gegenstands oder nil (info: Blizzards recipeInfo)
      Rows.Facts(itemID)  → { link, level, itemLevel } oder nil (Daten laden noch; sie sind angefordert)
      Rows.Draw(zeile, info)   Prozentzahl, Stufe, Pfeil und Namensbreite einer Zeile
      Rows.TipLines(info) → Zeilen { text, role } für den Tooltip der Rezeptzeile
]]

local Rows = {}
ns.Rows = Rows

local Num, Plain, Call, Peek = Core.Num, Core.Plain, Core.Call, Core.Peek

-- Maße in Blizzards Zeile (ProfessionsRecipeListRecipeTemplate): edge rechts frei, Breite der Spalten Prozentzahl, Stufe,
-- Pfeil und Zeichen der Farbenblind-Hilfe, gap zum Namen und zum Schloss, near zwischen Stufe und Pfeil, apart zwischen
-- Prozentzahl und Stufe; left: Beginn des Namens
-- (SkillUps −9, 26 breit, 4 Luft), lock: Blizzards Schloss an gesperrten Rezepten (17), blizzard: was Blizzard der
-- Namensbreite selbst abzieht (10 Luft + 26 für sein Zeichen)
Rows.W = { edge = 4, chance = 33, level = 15, arrow = 14, sign = 7, gap = 4, near = 3, apart = 9, left = 21, lock = 17, blizzard = 36 }
-- ezGears Pfeil ist Blizzards Atlas bags-greenarrow in seiner Größe (20 × 22, UiTextureAtlasMember); die Zeile ist 20 hoch
Rows.ARROW = { width = 20, height = 22, scale = 0.7 }
Rows.MIN_SCALE = 0.8      -- so klein wird die Schrift langer Namen höchstens (12 → knapp 10)
Rows.SCALE_STEP = 0.05    -- in solchen Schritten
Rows.DELAY = 0.3          -- Neuzeichnen gesammelt: ezGear meldet jede nachgeladene Gegenstandsinfo

local ASK_WAIT, ASK_MAX = 10, 3      -- nach fehlenden Daten höchstens alle 10 s und dreimal je Sitzung fragen

---------------------------------------------------------------------------
-- Was stellt das Rezept her?
---------------------------------------------------------------------------

local products = {}       -- [recipeID] = itemID oder false (der Client nennt keinen)
local facts = {}          -- [itemID] = { link, level, itemLevel }
local asked = {}          -- [itemID] = { tries, next }

-- Reihenfolge: der Link in Blizzards recipeInfo, ezCores Rezept-Wissen, Blizzards Schema (Data.Recipe)
function Rows.Product(info)
    local id = type(info) == "table" and Num(Plain(info.recipeID)) or nil
    if not id then return nil end
    local known = products[id]
    if known ~= nil then return known or nil end
    local link = Plain(info.hyperlink)
    local itemID = type(link) == "string" and link:find("item:", 1, true) and Core.ItemID(link) or nil
    if not itemID then
        local K = Core.Knowledge
        local rec = K and Plain(Call(K.Recipe, id))
        itemID = type(rec) == "table" and Num(rec.o) or nil
    end
    local recipe = not itemID and Data.Recipe(id) or nil
    if recipe then itemID = recipe.product end
    if itemID or recipe then products[id] = itemID or false end
    return itemID
end

-- „Kein Gegenstand“ gilt bis zum nächsten Öffnen eines Berufs: der Client nennt das Produkt manchmal erst später
function Rows.ForgetUnknown()
    for id, itemID in pairs(products) do
        if itemID == false then products[id] = nil end
    end
end

local function Ask(itemID)
    local entry, now = asked[itemID] or { tries = 0, next = 0 }, Core.Uptime()
    if entry.tries >= ASK_MAX or now < entry.next then return end
    entry.tries, entry.next = entry.tries + 1, now + ASK_WAIT
    asked[itemID] = entry
    Call(C_Item and C_Item.RequestLoadItemDataByID, itemID)
end

function Rows.Facts(itemID)
    if not itemID then return nil end
    local f = facts[itemID]
    if f then return f end
    local name, link, _, itemLevel, minLevel = Call((C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo"), itemID)
    name, link = Plain(name), Plain(link)
    if type(name) ~= "string" or name == "" then
        Ask(itemID)
        return nil
    end
    local level = Num(Plain(minLevel))
    f = { link = type(link) == "string" and link:find("item:", 1, true) and link or nil,
        itemLevel = Num(Plain(itemLevel)), level = level and level > 1 and level or nil }
    facts[itemID], asked[itemID] = f, nil
    return f
end

-- Stufe eines Rezepts (zum Sortieren) → Stufe, Gegenstandsstufe, laden seine Daten noch?
function Rows.Level(info)
    local itemID = Rows.Product(info)
    if not itemID then return nil, nil, false end
    local f = Rows.Facts(itemID)
    if not f then
        -- unterwegs, solange noch gefragt wird oder die letzte Frage frisch ist (sonst baute jede Meldung die Liste neu)
        local entry = asked[itemID]
        return nil, nil, entry == nil or entry.tries < ASK_MAX or Core.Uptime() < entry.next
    end
    return f.level, f.itemLevel, false
end

-- Reicht deine Stufe? → Rolle der Farbe
function Rows.LevelRole(level)
    local own = Num(Plain(Call(UnitLevel, "player")))
    return own and level > own and "bad" or "highlight"
end

---------------------------------------------------------------------------
-- ezGear
---------------------------------------------------------------------------

-- ezGears Schnittstelle, wenn ezGear läuft und der Schalter an ist; sonst nil
function Rows.Gear()
    if not ns.Enabled("rowArrow") then return nil end
    local gear = Core.API("ezGear")
    if type(gear) == "table" and type(gear.SetUpgradeIcon) == "function" then return gear end
    return nil
end

-- Stand laut ezGear und Text dazu; "noslot" = Platz, den ezGear nicht bewertet (Hemd, Wappenrock); nil ohne Auskunft
function Rows.Status(gear, link)
    if not gear then return nil end
    return Core.GearStatus(ns, link)
end

function Rows.Sign(gear, kind)
    if kind == nil or type(gear.StatusSign) ~= "function" then return nil end
    return Call(gear.StatusSign, kind)
end

---------------------------------------------------------------------------
-- Eine Zeile zeichnen
---------------------------------------------------------------------------

-- Zeile » { chance, level, holder, sign (eigene Regionen), scaled, fitted, extra, marks (Blizzards Breiten) } – nicht an Blizzards Rahmen gemerkt
local parts = setmetatable({}, { __mode = "k" })
local widest = {}         -- gemessene Breite des breitesten Textes je Spalte

-- gezeichnete Breite eines Textes, auch wenn seine Region schmaler ist
local function TextWidth(fs)
    local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
    return type(measure) == "function" and Num(Plain(Call(measure, fs))) or 0
end

local function Shown(region)
    return type(region) == "table" and type(region.IsShown) == "function" and region:IsShown() and true or false
end

-- Breite einer Textspalte: mindestens die aus Rows.W, mit einer breiteren Schrift mehr (gemessen am breitesten Text)
local function Column(key) return math.max(Rows.W[key], widest[key] or 0) end
Rows.Column = Column

local function TextPart(button, s, key, sample)
    local fs = s[key]
    if fs then return fs end
    fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetText(sample)
    widest[key] = math.max(widest[key] or 0, math.ceil(TextWidth(fs)))
    s[key] = fs
    return fs
end

-- Text einer Spalte an ihrer Stelle (right: Abstand vom rechten Rand) oder weg (text nil)
local function PlaceText(button, s, key, sample, text, right)
    if not text then
        if s[key] then s[key]:Hide() end
        return
    end
    local fs = TextPart(button, s, key, sample)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", button, "RIGHT", -right, 0)
    fs:SetText(text)
    fs:Show()
    return fs
end

local function Holder(button, s)
    if s.holder then return s.holder end
    local A = Rows.ARROW
    s.holder = CreateFrame("Frame", nil, button)
    s.holder:SetSize(A.width, A.height)
    s.holder:SetScale(A.scale)
    if s.holder.EnableMouse then s.holder:EnableMouse(false) end
    return s.holder
end

-- ezGears Pfeil bzw. sein graues Zeichen; link nil leert. Ohne Link, aber Ausrüstung: die Daten laden noch.
local function DrawArrow(button, s, gear, equipment, link, right)
    local sign
    if gear and equipment then
        local holder = Holder(button, s)
        holder:ClearAllPoints()
        holder:SetPoint("RIGHT", button, "RIGHT", -right / Rows.ARROW.scale, 0)
        local ok, err = pcall(gear.SetUpgradeIcon, holder, link)
        if not ok then ns.Error(err, "SetUpgradeIcon (ezGear)") end
        s.arrow = true
        local kind = "pending"
        if link then kind = Rows.Status(gear, link) end
        sign = Rows.Sign(gear, kind)
    elseif s.arrow then
        s.arrow = nil
        local api = gear or Core.API("ezGear")
        if type(api) == "table" and type(api.SetUpgradeIcon) == "function" then pcall(api.SetUpgradeIcon, s.holder, nil) end
    end
    if not sign then
        if s.sign then s.sign:Hide() end
        return
    end
    if not s.sign then
        s.sign = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s.sign:SetPoint("CENTER", s.holder, "CENTER", 0, 0)
    end
    s.sign:SetText(sign)
    s.sign:Show()
end

-- Der Name bekommt, was die Spalten (limit, vom rechten Rand) übrig lassen: erst in voller Größe, dann kleiner, dann kürzt
-- der Client. Ohne Spalten gilt wieder Blizzards Breite.
function Rows.Fit(button, s, limit)
    local label = Peek(button, "Label")
    if type(label) ~= "table" or type(label.SetWidth) ~= "function" then return end
    if limit <= 0 and not s.fitted then return end
    local count = Peek(button, "Count")
    count = type(count) == "table" and count or nil
    local function Scale(value)
        if type(label.SetTextScale) ~= "function" then return false end
        label:SetTextScale(value)
        if count and type(count.SetTextScale) == "function" then count:SetTextScale(value) end
        return true
    end
    if s.scaled then
        Scale(1)
        s.scaled = nil
    end
    local width = Num(Plain(Call(button.GetWidth, button))) or 0
    if width <= 0 then return end
    local name = TextWidth(label)
    if limit <= 0 then
        s.fitted = nil
        label:SetWidth(math.max(1, math.min(width - Rows.W.blizzard, name)))
        return
    end
    local room = math.max(1, width - Rows.W.left - limit - Rows.W.gap)
    local amount = count and Shown(count) and TextWidth(count) or 0
    local scale = 1
    -- Breite in der jetzigen Größe; full: in voller Größe (misst der Client die Größe nicht mit, wird gerechnet)
    local function Now(fs, full)
        local w = TextWidth(fs)
        return scale < 1 and w > full - 0.5 and full * scale or w
    end
    local function Free() return math.max(1, room - (amount > 0 and Now(count, amount) or 0)) end
    -- zu lang? Laut Client oder nach der Messung in dieser Größe
    local function TooLong(free)
        label:SetWidth(free)
        if type(label.IsTruncated) == "function" and Plain(Call(label.IsTruncated, label)) == true then return true end
        return Now(label, name) > free
    end
    local free = Free()
    local long = TooLong(free)
    while long and scale > Rows.MIN_SCALE + 0.001 do
        scale = math.max(Rows.MIN_SCALE, scale - Rows.SCALE_STEP)
        if not Scale(scale) then break end
        s.scaled = true
        free = Free()
        long = TooLong(free)
    end
    s.fitted = true
    -- so schmal wie der Name, damit die Anzahl „[n]“ direkt dahinter steht; kürzte das den Text, gilt der ganze Platz
    local snug = math.ceil(Now(label, name)) + 1
    if long or snug >= free or TooLong(snug) then label:SetWidth(free) end
end

-- Breitere Liste (Wide.lua): Blizzards Markierung und Hervorhebung sind Bilder fester Breite und wachsen mit; der Name
-- einer Zeile ohne Spalten bekommt einmal Blizzards Breite für die neue Zeile
local MARKS = { "SelectedOverlay", "HighlightOverlay" }
local function Widen(button, s, extra)
    if (s.extra or 0) == extra then return end
    s.extra, s.fitted = extra, true
    s.marks = s.marks or {}
    for _, name in ipairs(MARKS) do
        local mark = Peek(button, name)
        if type(mark) == "table" and type(mark.SetWidth) == "function" then
            local width = s.marks[name] or Num(Plain(Call(mark.GetWidth, mark)))
            if width and width > 0 then
                s.marks[name] = width
                mark:SetWidth(width + extra)
            end
        end
    end
end

-- Pfeil, Stufe und Prozentzahl einer Zeile (feste Spalten, von rechts). → true, wenn es etwas zu zeichnen gab
function Rows.Draw(button, info)
    if type(button) ~= "table" or type(button.CreateFontString) ~= "function" or type(info) ~= "table" then return false end
    local W = Rows.W
    local chanceOn, levelOn, gear = ns.Enabled("chanceNumber"), ns.Enabled("rowLevel"), Rows.Gear()
    local extra = ns.Wide.Extra()
    local s = parts[button]
    if not s then
        if not (chanceOn or levelOn or gear or extra > 0) then return false end
        s = {}
        parts[button] = s
    end
    Widen(button, s, extra)
    local right, limit = W.edge, 0
    if Shown(Peek(button, "LockedIcon")) then
        limit = right + W.lock
        right = limit + W.gap
    end
    local itemID = (levelOn or gear) and Rows.Product(info) or nil
    local f = Rows.Facts(itemID)

    local equipment = gear and itemID and Core.IsEquipment(itemID) or false
    if gear and Core.MarksOn() then right = right + W.sign end
    DrawArrow(button, s, gear, equipment, f and f.link, right)
    if equipment then limit = right + W.arrow end
    if gear then right = right + W.arrow + W.near end

    local level = levelOn and f and f.level or nil
    local fs = PlaceText(button, s, "level", "60", level and tostring(level), right)
    if fs then
        Core.Style.SetTextColor(fs, Rows.LevelRole(level))
        limit = right + Column("level")
    end
    if levelOn then right = right + Column("level") + W.near end

    if gear or levelOn then right = right + W.apart - W.near end
    local chance = chanceOn and ns.Skill.ShortText(ns.Skill.Chance(info, ns.Where.Rank())) or nil
    PlaceText(button, s, "chance", Core.Percent(100), chance, right)
    if chance then limit = right + Column("chance") end
    Rows.Fit(button, s, limit)
    return true
end

-- Was eine Zeile gerade zeigt (für Prüfungen und /dump)
function Rows.PartsOf(button) return parts[button] end

---------------------------------------------------------------------------
-- Tooltip der Rezeptzeile
---------------------------------------------------------------------------

local ROLE = { better = "good", worse = "bad", learn = "normal", level = "normal" }

function Rows.TipLines(info)
    local out = {}
    local levelOn, gear = ns.Enabled("rowLevel"), Rows.Gear()
    local itemID = (levelOn or gear) and Rows.Product(info) or nil
    if not itemID then return out end
    local f, equipment = Rows.Facts(itemID), Core.IsEquipment(itemID)
    if levelOn and f then
        if f.level then out[#out + 1] = { text = L.ROW_TIP_LEVEL:format(f.level), role = Rows.LevelRole(f.level) } end
        if equipment and f.itemLevel then out[#out + 1] = { text = L.ROW_TIP_ITEMLEVEL:format(f.itemLevel), role = "hint" } end
    end
    if gear and equipment then
        local kind, text = "pending", nil
        if f and f.link then kind, text = Rows.Status(gear, f.link) end
        local sign = Rows.Sign(gear, kind)
        if kind == "pending" then
            text = L.ROW_TIP_PENDING
        elseif kind == "equipped" then
            text = L.ROW_TIP_EQUIPPED
        elseif kind == "noslot" then
            text = L.ROW_TIP_NOSLOT
        end
        if type(text) == "string" then
            out[#out + 1] = { text = (sign and L.ROW_TIP_GEAR_SIGN:format(sign, text) or L.ROW_TIP_GEAR:format(text)),
                role = ROLE[kind] or "hint" }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Neu zeichnen (gesammelt, nur solange die Rezepte zu sehen sind)
---------------------------------------------------------------------------

Rows.RedrawSoon = ns.Throttle(function()
    if not ns.Panel.CraftingShown() then return end
    ns.Skill.ApplyAll()
    ns.Sort.Reorder()
end, Rows.DELAY)

local function Redraw()
    if ns.Enabled("rowLevel") or Rows.Gear() or ns.Sort.Box() then Rows.RedrawSoon() end
end

-- „[n]“ hinter dem Namen hat sich geändert (Blizzards Zeilen hören selbst darauf; danach passt die Namensbreite nicht mehr)
function Rows.OnCountChanged()
    C_Timer.After(0, function()
        local box = ns.Sort.Box()
        if box then
            local hide = Peek(ns.Skill.RecipeList(), "hideCraftableCount")
            pcall(box.ForEachFrame, box, function(button)
                if type(button.SetCraftableCount) == "function" then button:SetCraftableCount(hide) end
            end)
        end
        ns.Try("RecipeRow", ns.Skill.ApplyAll)
    end)
end
ns.WhenAddOnLoaded("Blizzard_Professions", function()
    local reg = rawget(_G, "EventRegistry")
    if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        reg:RegisterCallback("ProfessionsRecipeListMixin.Event.RefreshCraftableCount", Rows.OnCountChanged, Rows)
    end
end)

-- Erfolglose Antworten zählen nicht: sonst fragte das Zeichnen gleich wieder, im Takt
ns.On("GET_ITEM_INFO_RECEIVED", function(_, _, success)
    if Plain(success) == true then Redraw() end
end)
-- Antwort auf unsere Anforderung; eine erfolglose behält die Sperrfrist (sonst fragte das Zeichnen gleich wieder)
ns.On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
    if Core.IsSecret(itemID) or not asked[itemID or 0] or Plain(success) == false then return end
    Redraw()
end)
ns.On("PLAYER_LEVEL_UP", Redraw)
ns.On("TRADE_SKILL_SHOW", function()
    Rows.ForgetUnknown()
    Redraw()
end)
Core.Listen("GEAR_SCORES_CHANGED", Redraw, ADDON)
Core.Listen("GLOW_MARKS_CHANGED", Redraw, ADDON)      -- Zeichen der Farbenblind-Hilfe am Pfeil
ns.OnSettingChanged(function(key)
    if key == "rowArrow" or key == "rowLevel" then
        ns.Skill.ApplyAll()
        ns.Sort.Reorder()
    end
end)
