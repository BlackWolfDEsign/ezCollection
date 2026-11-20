local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rezepte auf der Karte (Welle 15b; Wunsch des Nutzers vom 15.11.2026 abends: „ezmap oder so oder mehrere, rezepte und
    deren fundorte mit ablegen und entsprechend anzeigen / bereitstellen“).

    Gruppe „Rezepte“ im Einstellungsbaum der Karte (Tree.lua): Art (Händler, Lehrer) als Schalter recipeVendorPins und
    recipeTrainerPins, darunter je Beruf ein dynamisches Blatt („rprof:<Beruf>“). Ab Werk nur deine eigenen Berufe
    (Empfehlung umgesetzt, Antwort offen) – ein Beruf, den keiner deiner Charaktere hat, ist aus, bis du ihn wählst.
    Punkte über ezCores Punkteschicht (Core.MapPins, Anbieter „ezMap.recipes“, auch auf der Minikarte), keine eigene
    Schicht. Daten aus ezCore (Knowledge.RecipeSpots): besuchte Händler mit Rezept-Gegenständen und besuchte
    Berufslehrer mit Rezepten, Ort aus Core.Places bzw. Core.Npcs – Nachschlage-Wissen, immer sichtbar (Leitlinie 11;
    Entdecker-Wissen wie Fundorte seltener Beute zeigt ezMap hier nicht). Tooltip am Punkt: die Rezepte dort, ob du sie
    kannst, Preis bzw. benötigte Fertigkeit, Quelle „bei dir“. Klick setzt Blizzards Markierung (ns.Way.Set).
]]
local Recipes = {}
ns.Recipes = Recipes

Recipes.PROVIDER = "ezMap.recipes"
Recipes.PIN_SIZE = 14
Recipes.TIP_MAX = 12      -- so viele Rezepte nennt der Tooltip am Punkt (danach „… und n weitere“)
Recipes.ICON = { vendor = "Interface\\Icons\\INV_Scroll_03", trainer = "Interface\\Icons\\INV_Misc_Book_11" }
Recipes.KEY = { vendor = "recipeVendorPins", trainer = "recipeTrainerPins" }

local function Knowledge(name)
    local K = Core.Knowledge
    local fn = K and K[name]
    return type(fn) == "function" and fn or nil
end

local function Spots()
    local fn = Knowledge("RecipeSpots")
    local ok, list = false, nil
    if fn then ok, list = pcall(fn) end
    return ok and type(list) == "table" and list or {}
end

-- Berufe deines Charakters (ezCore-Charakterdaten): { [Beruf] = Rang }
function Recipes.OwnProfessions()
    local fn = Knowledge("CharProfs")
    local map = fn and Core.charKey and fn(Core.charKey)
    return type(map) == "table" and map or {}
end

local function ProfName(key)
    local fn = Knowledge("ProfessionName")
    local name = fn and fn(key)
    return type(name) == "string" and name ~= "" and name or tostring(key)
end

-- Blätter je Beruf: eigene Berufe und alle Berufe, für die es Punkte gibt
function Recipes.ProfLeaves()
    local seen, out = {}, {}
    local function Add(key)
        if type(key) == "string" and not seen[key] then
            seen[key] = true
            out[#out + 1] = { id = "rprof:" .. key, label = ProfName(key), dynOf = "recipeProf" }
        end
    end
    for key in pairs(Recipes.OwnProfessions()) do Add(key) end
    for _, s in ipairs(Spots()) do
        for key in pairs(type(s.profs) == "table" and s.profs or {}) do Add(key) end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- Standard je Beruf: an für eigene Berufe, sonst aus (Empfehlung umgesetzt, Antwort offen)
function Recipes.DefaultFor(id)
    local key = type(id) == "string" and id:match("^rprof:(.+)$")
    return key ~= nil and Recipes.OwnProfessions()[key] ~= nil
end

-- Seit Welle 27 unter „Dienste in der Stadt“ (Rezepte bei Händlern und Lehrern), vorher eigene Gruppe oben
ns.Tree.Add("town", { id = "recipes", children = {
    { key = "recipeVendorPins" }, { key = "recipeTrainerPins" },
    { id = "recipeProf", dyn = true },
} })
ns.Tree.DYN.recipeProf = { prefix = "rprof:", leaves = Recipes.ProfLeaves, default = Recipes.DefaultFor,
    tip = "TREE_RPROF_LEAF_TIP", label = function(id) return ProfName(id:sub(7)) end,
    icon = function(id) return ns.Icons and ns.Icons.Profession(id:sub(7)) or nil end }     -- Symbol des Berufs (Welle 27)

function Recipes.ProfWanted(key) return ns.Tree.Leaf("rprof:" .. tostring(key)) end

-- Passt ein Punkt zum Baum? Art an und mindestens ein gewünschter Beruf darunter
function Recipes.Wanted(spot)
    if type(spot) ~= "table" or not ns.Enabled(Recipes.KEY[spot.kind] or "") then return false end
    for key in pairs(type(spot.profs) == "table" and spot.profs or {}) do
        if Recipes.ProfWanted(key) then return true end
    end
    return false
end

function Recipes.PinsWanted()
    return ns.Enabled("recipeVendorPins") or ns.Enabled("recipeTrainerPins")
end

function Recipes.Points()
    local out = {}
    for _, s in ipairs(Spots()) do
        if Recipes.Wanted(s) and s.map and s.x and s.y then
            out[#out + 1] = { x = s.x, y = s.y, map = s.map, size = Recipes.PIN_SIZE,
                texture = Recipes.ICON[s.kind] or Recipes.ICON.vendor, recipeSpot = s }
        end
    end
    return out
end

-- Tooltip am Punkt: Name, Art, je Rezept „Name – gelernt / ab Fertigkeit n / Preis“, Quelle
function Recipes.PinTooltip(tip, point)
    local s = type(point) == "table" and point.recipeSpot
    if not s then return end
    Core.TipTitle(tip, s.name or ("#" .. tostring(s.npc)))
    Core.TipLine(tip, s.kind == "trainer" and L.RECIPEPIN_TRAINER or L.RECIPEPIN_VENDOR, "hint")
    local shown = 0
    for _, r in ipairs(s.recipes or {}) do
        if Recipes.ProfWanted(r.prof) then
            shown = shown + 1
            if shown > Recipes.TIP_MAX then break end
            local state
            if r.learned then state = L.RECIPEPIN_LEARNED
            elseif ns.Num(r.skill) and r.skill > 0 then state = L.RECIPEPIN_SKILL:format(r.skill)
            else state = L.RECIPEPIN_OPEN end
            local name = r.name or (r.item and Core.ItemNameByID(r.item)) or "?"
            local right = state
            if ns.Num(r.price) and r.price > 0 then right = right .. ", " .. Core.Money(r.price) end
            if r.learned then
                Core.TipDoubleLine(tip, name, right, "gray", "good")   -- gelernt: ausgegraut
            else
                Core.TipDoubleLine(tip, name, right, "highlight", "normal")
            end
        end
    end
    if shown > Recipes.TIP_MAX then
        local total = 0
        for _, r in ipairs(s.recipes or {}) do if Recipes.ProfWanted(r.prof) then total = total + 1 end end
        Core.TipLine(tip, ezCore.More(total - Recipes.TIP_MAX), "hint")
    end
    local S = Core.Sources
    local own = S and S.Label and S.Label({ source = "own", sourceKey = "own" }) or Core.L["DB_OWN"]
    Core.TipLine(tip, L.RECIPEPIN_SOURCE:format(own or ""), "hint", true)
    Core.TipClick(tip, L.RECIPEPIN_HINT)
end

function Recipes.PinClick(point, button)
    local s = type(point) == "table" and point.recipeSpot
    if not s or button == "RightButton" then return false end
    return ns.Way.Set(s.map, s.x, s.y, s.name, true)
end

function Recipes.InitPins()
    local P = Core.MapPins
    if not (type(P) == "table" and type(P.AddProvider) == "function") then return false end
    P.AddProvider(Recipes.PROVIDER, {
        owner = "ezMap",
        order = 40,
        punkte = Recipes.Points,
        minikarte = true,
        sichtbar = function() return Recipes.PinsWanted() end,
        tooltip = Recipes.PinTooltip,
        klick = Recipes.PinClick,
    })
    return true
end

ns.OnReady(function() ns.Try("RecipePins", Recipes.InitPins) end)
ns.OnSettingChanged(function(key)
    local P = Core.MapPins
    if (key == "recipeVendorPins" or key == "recipeTrainerPins") and type(P) == "table" and P.Refresh then P.Refresh() end
end)
-- Betrifft eine Änderung im Baum die Rezepte? Die Gruppe selbst, alles darunter (Berufe „rprof:…“) und jede Gruppe
-- darüber – über Tree.Parent gesucht statt aufgezählt (Fund des code-reviewers vom 17.11.2026: das Thema „Dienste in
-- der Stadt“ fehlte in der Liste, „Alle auswählen“ dort zeichnete die Rezept-Punkte nicht neu)
function Recipes.Affected(id)
    local Tree = ns.Tree
    if id == nil then return false end
    if Tree.DynGroupOf(id) == "recipeProf" then return true end
    local node = Tree.Node(id)
    if node and node.key then return false end      -- Schalter melden sich selbst (OnSettingChanged oben)
    local cur = id
    while cur do
        if cur == "recipes" then return true end
        cur = Tree.Parent(cur)
    end
    cur = Tree.Parent("recipes")
    while cur do
        if cur == id then return true end
        cur = Tree.Parent(cur)
    end
    return false
end

ns.Tree.OnChanged(function(id)
    local P = Core.MapPins
    if Recipes.Affected(id) and type(P) == "table" and P.Refresh then P.Refresh() end
end)
Core.Listen("RECIPES_CHANGED", function()
    local P = Core.MapPins
    if type(P) == "table" and P.Refresh then P.Refresh() end
end, "ezMap.Recipes")

-- /ezmap status: Punkte für Rezepte
ns.AddStatusLine(function()
    if not Recipes.PinsWanted() then return L.STATUS_RECIPES_OFF end
    local n = 0
    for _, s in ipairs(Spots()) do if Recipes.Wanted(s) then n = n + 1 end end
    return L.STATUS_RECIPES:format(n)
end)
