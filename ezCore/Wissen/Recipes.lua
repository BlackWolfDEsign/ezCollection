local _, ns = ...
local Core = ezCore

--[[
    Rezept-Wissen über alle Twinks (Punkt 8, gewünscht von ezCraft). Ergänzt das Item-Wissen:
    Knowledge.lua liest beim offenen Berufefenster jedes Rezept (LearnRetail) und reicht es hierher weiter.

      Knowledge.Recipe(recipeID)       → { n = Name, p = Beruf, o = Produkt-ID, r = { [Zutat-ID] = Anzahl } } oder nil
      Knowledge.Crafters(recipeID)     → { charKey … } alle Twinks, die das Rezept kennen (beim Öffnen ihres Berufs gesehen)
      Knowledge.SkillStages(recipeID)  → { orange, yellow, green, gray } Fertigkeit, ab der die Farbe gilt (beobachtet;
                                          nil = noch nicht gesehen); dazu exact = { farbe = true }, wenn die Grenze genau feststeht
      Knowledge.RecipeStages(recipeID) → dieselben Farben zuerst laut Client-Tabellen (ezCore.ClientData, Welle 26),
                                          Beobachtung als Rückfall und Gegenprobe; source/computed/conflict je Farbe
      Knowledge.RecipeSource(recipeID) → Quelle als Text (Blizzards Quellentext, sonst der Händler, der das Rezept verkauft)
      Knowledge.RecipeFor(itemID)      → recipeID, Rezept: wie ein Gegenstand hergestellt wird (jedes gesehene Rezept,
                                          auch nicht gelernt) oder nil – für „Rezept und Zutaten“ im Tooltip (Nutzer 13.11.2026)
                                          Kennt ezCore kein Rezept mit diesem Produkt, fragt es zuletzt AtlasLoot (Core.Sources
                                          .RecipeFor → Zauber) und ordnet das Produkt einem gesehenen Rezept dieses Zaubers zu
                                          (EC-102, DG-41) – nur, wenn das Rezept noch kein Produkt hat. Diese Zuordnung gilt nur
                                          für die Sitzung und wird nie gespeichert (Leitlinie 10/11); geliefert wird dann eine
                                          Kopie des Rezepts mit o = Produkt und os = "atlasloot".
      Knowledge.AtlasRecipeOf(itemID)  → recipeID, Rezept: die Zuordnung laut AtlasLoot aus dieser Sitzung (ohne neue Frage)
      Knowledge.RecipeForSpell(spellID) → recipeID, Rezept: gesehenes Rezept zu einem Zauber (Berufszauber = Rezept-ID)
      Knowledge.RecipeProduct(recipeID, schema) → itemID, Quelle: Produkt laut Client (Knowledge.lua)
      Knowledge.RecipesUsing(itemID)   → { { recipeID, recipe, count } … } nach Name: wofür ein Gegenstand Zutat ist
      Knowledge.RecipesWithoutProduct(beruf) → Anzahl, { [Beruf] = Anzahl }: gesehene Rezepte ohne Produkt-ID (A62,
                                          Welle 23b; mit beruf nur dessen Anzahl) – für „Rezept gesehen, Produkt
                                          unbekannt“ statt „noch nicht gesehen“
      Gesehen sind die Rezepte, deren Berufsfenster ein Twink einmal geöffnet hat (Forever hat keine Rezept-Datenbank).
      Knowledge.IsResource(itemID)     → Rohstoff bzw. Handwerksware (Klasse 7) oder Reagenz (Klasse 5)?
      Knowledge.VendorSources(itemID)  → { { npc, name, zone, price, stack, limited, seen } … } günstigste zuerst:
                                          Händler, die den Rohstoff verkaufen (beim Ansprechen gemerkt, ezCoreDB.knowledge.vendors)
      Nachricht: RECIPES_CHANGED (Beruf)

    Gespeichert:
      ezCoreDB.chars[charKey].recipes[recipeID] = true   wer was kann (nur der eigene Beruf, nicht verlinkt oder Gilde;
                                    Entwurf 1.6 „Zustand verlässt den Wissens-Ast“). Geschrieben wird nur dort; der
                                    Altspeicher knowledge.known[charKey] bleibt liegen und wird mitgelesen (Weiterleitung,
                                    nichts geht verloren). Ohne Satz in chars bleibt er für diesen Charakter Schreiber.
      knowledge.stages[recipeID] = { [farbe] = { min, max } }   beobachtete Fertigkeit je Farbe
      knowledge.sources[recipeID] = Text                        Quelle eines noch nicht gelernten Rezepts
    Umgezogen in die Entdecker-Datenbank (Träger ezWorld, Discovery.Moved): Rezepte aus held.recipe (Sicht in alter
    Form, Discovery.RecipeView), Händler aus vendor (Discovery.VendorList) – DiscoveryLegacy.lua; Farbgrenzen aus
    recipeObs[Rezept].stages (dieselbe Form), Quelltexte aus text[Sprache].recipeSrc. Danach werden knowledge.stages
    und knowledge.sources nicht mehr geschrieben und bleiben liegen.
    Skill-Farben: Blizzards relativeDifficulty (0 orange, 1 gelb, 2 grün, 3 grau; canSkillUp = false heißt grau).
    Die Grenze einer Farbe steht genau fest, sobald die vorige Farbe einen Punkt darunter beobachtet wurde.
]]

local K = Core.Knowledge
if not K then return end

local Num, Plain = Core.Num, Core.Plain

local COLORS = { "orange", "yellow", "green", "gray" }
local BY_DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

local L = Core.NewLocale({
    SOURCE_VENDOR = "Händler: %s (%s)",
    SOURCE_CLIENT = Core.L.SOURCE_CLIENT,   -- ein Wortlaut für „laut Client“ (Kern/Locale.lua, T10-6)
    WHERE_VENDOR = "Händler: %s", WHERE_VENDOR_AT = "Händler: %s (%s)",
    WHERE_TRAINER = "Lehrer: %s", WHERE_TRAINER_AT = "Lehrer: %s (%s)",
    WHERE_QUEST = "Quest: %s", WHERE_QUEST_AT = "Quest: %s (%s)",
    WHERE_DROP = "Beute von: %s", WHERE_DROP_AT = "Beute von: %s (%s)",
    WHERE_OBJECT = "Liegt in: %s", WHERE_OBJECT_AT = "Liegt in: %s (%s)",
    WHERE_CONTAINER = "Steckt in: %s", WHERE_CONTAINER_AT = "Steckt in: %s (%s)",
}, {
    SOURCE_VENDOR = "Vendor: %s (%s)",
    SOURCE_CLIENT = Core.L.SOURCE_CLIENT,
    WHERE_VENDOR = "Vendor: %s", WHERE_VENDOR_AT = "Vendor: %s (%s)",
    WHERE_TRAINER = "Trainer: %s", WHERE_TRAINER_AT = "Trainer: %s (%s)",
    WHERE_QUEST = "Quest: %s", WHERE_QUEST_AT = "Quest: %s (%s)",
    WHERE_DROP = "Dropped by: %s", WHERE_DROP_AT = "Dropped by: %s (%s)",
    WHERE_OBJECT = "Found in: %s", WHERE_OBJECT_AT = "Found in: %s (%s)",
    WHERE_CONTAINER = "Contained in: %s", WHERE_CONTAINER_AT = "Contained in: %s (%s)",
})

-- ezCoreDB.knowledge bzw. – Rezepte umgezogen – die Sicht der Entdecker-Datenbank (dieselbe Form)
local function Root()
    local D = Core.Discovery
    local view = D and D.RecipeView and D.RecipeView()
    if view then return view end
    local db = Core.db
    return type(db) == "table" and db.knowledge or nil
end

local function Moved(store)
    local D = Core.Discovery
    return D ~= nil and D.Moved ~= nil and D.Moved(store)
end

local function KDB()
    local kdb = Root()
    if type(kdb) ~= "table" then return nil end
    kdb.known = kdb.known or {}
    kdb.stages = kdb.stages or {}
    kdb.sources = kdb.sources or {}
    return kdb
end

-- Kann ein Charakter das Rezept? chars[charKey].recipes, dazu der Altspeicher knowledge.known (nur gelesen)
local function Knows(key, recipeID)
    local c = Core.Char and Core.Char(key)
    if type(c) == "table" and type(c.recipes) == "table" and c.recipes[recipeID] then return true end
    local kdb = KDB()
    local old = kdb and kdb.known[key]
    return type(old) == "table" and old[recipeID] and true or false
end

-- Wohin ein neu gelerntes Rezept geschrieben wird: chars[charKey].recipes (ohne Satz in chars: der Altspeicher)
local function RecipesOf(key)
    local c = Core.Char and Core.Char(key)
    if type(c) == "table" then
        if type(c.recipes) ~= "table" then c.recipes = {} end
        return c.recipes
    end
    local kdb = KDB()
    if not kdb then return nil end
    if type(kdb.known[key]) ~= "table" then kdb.known[key] = {} end
    return kdb.known[key]
end

-- Farbgrenzen und Quelltexte: umgezogen aus recipeObs bzw. text[Sprache].recipeSrc, sonst ezCoreDB.knowledge
local function RecipeKey(recipeID) return Core.DB and Core.DB.Keys.Recipe(recipeID) end

local function Stages(recipeID)
    if Moved("stages") then
        local k = RecipeKey(recipeID)
        local row = k and Core.DB.Get("recipeObs", k)
        return row and type(row.stages) == "table" and row.stages or nil
    end
    local kdb = KDB()
    return kdb and kdb.stages[recipeID]
end

local function Source(recipeID)
    if Moved("sources") then
        local k = RecipeKey(recipeID)
        return k and Core.DB.Text("recipeSrc", k) or nil
    end
    local kdb = KDB()
    return kdb and kdb.sources[recipeID]
end

local function SetSource(recipeID, text)
    if Moved("sources") then
        local k = RecipeKey(recipeID)
        if k then Core.DB.AsOwn(Core.DB.SetText, "recipeSrc", k, text) end
        return
    end
    local kdb = KDB()
    if kdb then kdb.sources[recipeID] = text end
end

-- Farbe mit Fertigkeit rank einrechnen (min, max je Farbe) → geändert?
local function Widen(st, color, rank)
    local e = st[color] or {}
    st[color] = e
    local changed = false
    if not e[1] or rank < e[1] then e[1], changed = rank, true end
    if not e[2] or rank > e[2] then e[2], changed = rank, true end
    return changed
end

local changedProf

function K.NoteRecipe(recipeID, info, prof, isOwn, rank)
    recipeID = Num(recipeID)
    local kdb = recipeID and type(info) == "table" and KDB()
    if not kdb then return end
    local learned = Plain(info.learned) == true
    if isOwn ~= false and Core.charKey then
        local mine = learned and not Knows(Core.charKey, recipeID) and RecipesOf(Core.charKey)
        if mine then
            mine[recipeID] = true
            changedProf = prof or true
        end
    end
    rank = Num(rank)
    if isOwn ~= false and learned and rank then
        local color = Plain(info.canSkillUp) == false and "gray" or BY_DIFFICULTY[Num(info.relativeDifficulty) or -1]
        if color and Moved("stages") then
            local k = RecipeKey(recipeID)
            local st = Stages(recipeID) or {}
            if k and Widen(st, color, rank) then Core.DB.AsOwn(Core.DB.Put, "recipeObs", k, { stages = st }) end
        elseif color then
            local st = kdb.stages[recipeID] or {}
            kdb.stages[recipeID] = st
            Widen(st, color, rank)
        end
    end
    if not learned and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSourceText then
        local ok, text = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
        text = ok and Plain(text)
        if type(text) == "string" and text ~= "" and Source(recipeID) ~= text then SetSource(recipeID, text) end
    end
end

function K.NoteRecipesDone(prof)
    -- Welle 15b: Rezept-Gegenstände früher besuchter Händler jetzt zuordnen (K.LinkVendorRecipes, weiter unten)
    if K.ScheduleRecipeLinks then K.ScheduleRecipeLinks() end
    if changedProf then
        changedProf = nil
        Core.Fire("RECIPES_CHANGED", prof)
    end
end

function K.Recipe(recipeID)
    local kdb = Root()
    local rec = type(kdb) == "table" and type(kdb.recipes) == "table" and kdb.recipes[recipeID]
    return type(rec) == "table" and rec or nil
end

local function RecipeDB()
    local kdb = Root()
    if type(kdb) ~= "table" or type(kdb.recipes) ~= "table" then return nil end
    return kdb
end

local askedSources = {}
-- Produkt » Rezept laut AtlasLoot, nur im Speicher dieser Sitzung: nichts davon kommt in ezCoreDB (Leitlinie 10/11,
-- Sources.lua: „Nichts wird kopiert oder gespeichert“).
local atlasProducts = {}
function K.ForgetAskedSources() askedSources, atlasProducts = {}, {} end

-- Kopie des gespeicherten Rezepts mit dem Produkt laut AtlasLoot; das Original in ezCoreDB bleibt unberührt.
local function AtlasView(rec, itemID)
    local v = {}
    for k, val in pairs(rec) do v[k] = val end
    v.o, v.os = itemID, "atlasloot"
    return v
end

function K.AtlasRecipeOf(itemID)
    itemID = Num(itemID)
    local spell = itemID and atlasProducts[itemID]
    local kdb = spell and RecipeDB()
    local rec = kdb and kdb.recipes[spell]
    if type(rec) == "table" and rec.o == nil then return spell, rec end
    return nil
end
Core.Listen("RECIPES_CHANGED", function() askedSources = {} end, "ezCore.Recipes")   -- neu gesehene Rezepte: neu fragen

function K.RecipeFor(itemID)
    itemID = Num(itemID)
    local kdb = itemID and RecipeDB()
    if not kdb then return nil end
    local key = type(kdb.created) == "table" and kdb.created[itemID]
    if key and type(kdb.recipes[key]) == "table" then return key, kdb.recipes[key] end
    for id, rec in pairs(kdb.recipes) do
        if type(rec) == "table" and rec.o == itemID then return id, rec end
    end
    -- Zuletzt AtlasLoot (Leitlinie 11): welcher Zauber stellt den Gegenstand her? Gehört er zu einem gesehenen Rezept
    -- ohne Produkt, wird das Produkt dort gemerkt (Formprüfung macht Core.Sources; hier nur Zahl und freies Rezept).
    local known, krec = K.AtlasRecipeOf(itemID)
    if known then return known, AtlasView(krec, itemID) end
    if askedSources[itemID] then return nil end
    askedSources[itemID] = true   -- je Sitzung einmal je Gegenstand (der Tooltip fragt bei jedem Zeigen)
    local S = Core.Sources
    local r = S and S.RecipeFor and Core.Call(S.RecipeFor, itemID)
    local spell = type(r) == "table" and Num(r.spell)
    local rec = spell and kdb.recipes[spell]
    if type(rec) == "table" and rec.o == nil then
        atlasProducts[itemID] = spell   -- nur Sitzung, nicht rec.o und nicht kdb.created
        return spell, AtlasView(rec, itemID)
    end
    return nil
end

-- A62 (Welle 23b): gesehene Rezepte ohne Produkt-ID (der Client nannte beim Lesen keins, z. B. Verzauberungen und
-- manche Forever-Rezepte). → Anzahl gesamt, { [Beruf] = Anzahl } (Beruf, wie das Rezept ihn nennt; ohne Beruf "?"),
-- mit prof nur dieser Beruf: Anzahl. Zwischengespeichert bis RECIPES_CHANGED bzw. einem neuen Lesen im Berufefenster.
local noProduct
function K.RecipesWithoutProduct(prof)
    if not noProduct then
        local kdb = RecipeDB()
        local total, byProf = 0, {}
        for _, rec in pairs(kdb and kdb.recipes or {}) do
            if type(rec) == "table" and rec.o == nil then
                total = total + 1
                local p = type(rec.p) == "string" and rec.p ~= "" and rec.p or "?"
                byProf[p] = (byProf[p] or 0) + 1
            end
        end
        noProduct = { total = total, byProf = byProf }
    end
    if prof ~= nil then return noProduct.byProf[prof] or 0 end
    local copy = {}
    for p, n in pairs(noProduct.byProf) do copy[p] = n end
    return noProduct.total, copy
end
function K.ForgetRecipesWithoutProduct() noProduct = nil end
Core.Listen("RECIPES_CHANGED", K.ForgetRecipesWithoutProduct, "ezCore.Recipes")
ns.On("TRADE_SKILL_LIST_UPDATE", K.ForgetRecipesWithoutProduct)

function K.RecipeForSpell(spellID)
    spellID = Num(spellID)
    local kdb = spellID and RecipeDB()
    if not kdb then return nil end
    local rec = kdb.recipes[spellID]
    if type(rec) == "table" then return spellID, rec end
    return nil
end

function K.RecipesUsing(itemID)
    itemID = Num(itemID)
    local kdb = itemID and RecipeDB()
    local list = {}
    if not kdb then return list end
    local set = type(kdb.reagents) == "table" and kdb.reagents[itemID]
    if type(set) == "table" then
        for key in pairs(set) do
            local rec = kdb.recipes[key]
            if type(rec) == "table" and type(rec.r) == "table" and rec.r[itemID] then
                list[#list + 1] = { recipeID = key, recipe = rec, count = rec.r[itemID] }
            end
        end
    end
    table.sort(list, function(a, b)
        local na, nb = tostring(a.recipe.n or ""), tostring(b.recipe.n or "")
        if na ~= nb then return na < nb end
        return tostring(a.recipeID) < tostring(b.recipeID)
    end)
    return list
end

function K.Crafters(recipeID)
    local kdb = KDB()
    local list = {}
    if not kdb then return list end
    local seen = {}
    local function Add(key)
        if type(key) == "string" and not seen[key] and Knows(key, recipeID) then
            seen[key] = true
            list[#list + 1] = key
        end
    end
    for key in pairs(Core.Chars()) do Add(key) end
    for key in pairs(kdb.known) do Add(key) end
    table.sort(list)
    return list
end

function K.SkillStages(recipeID)
    local st = Stages(recipeID)
    local out = { exact = {} }
    if type(st) ~= "table" then return out end
    for i, color in ipairs(COLORS) do
        local e = st[color]
        if type(e) == "table" and e[1] then
            out[color] = e[1]
            local before = COLORS[i - 1] and st[COLORS[i - 1]]
            if i == 1 or (type(before) == "table" and before[2] and before[2] == e[1] - 1) then out.exact[color] = true end
        end
    end
    return out
end

-- Welle 26 (F2, Paket kern/wago-wissen): Farbstufen zuerst aus den Client-Tabellen (ezCore.ClientData.RecipeStages,
-- SkillLineAbility laut wago.tools), die Beobachtung (K.SkillStages) ist Rückfall und Gegenprobe (Leitlinie 11).
-- „grün ab“ der Tabellen ist gerechnet (Mitte zwischen gelb und grau) – eine genaue Beobachtung geht ihm vor.
-- Orange liefern die Tabellen nur bei „lernbar ab“ über 1 (sonst Platzhalter); dann gilt die Beobachtung.
-- → { orange, yellow, green, gray, exact = { [farbe] = true }, computed = { green = true } | nil,
--     source = { [farbe] = "client" | "seen" }, line = Fertigkeitslinie laut Client, sourceText = Quelle als Text,
--     conflict = { [farbe] = beobachteter Wert } | nil (genaue Beobachtung weicht vom Client ab) }
function K.RecipeStages(recipeID)
    local seen = K.SkillStages(recipeID)
    local CD = Core.ClientData
    local client = CD and CD.RecipeStages and CD.RecipeStages(recipeID)
    local out = { exact = {}, source = {} }
    for _, color in ipairs(COLORS) do
        local c, s = client and client[color], seen[color]
        local computed = client and client.computed and client.computed[color]
        if c and not (computed and s and seen.exact[color]) then
            out[color], out.source[color] = c, "client"
            if computed then
                out.computed = out.computed or {}
                out.computed[color] = true
            elseif client.exact[color] then
                out.exact[color] = true
            end
            -- Orange beobachtet heißt nur „bei dieser Fertigkeit war es orange“ (K.SkillStages führt es immer als
            -- genau) – ein Widerspruch ist nur ein Wert unter dem Client-Wert.
            if s and seen.exact[color] and s ~= c and not computed and (color ~= "orange" or s < c) then
                out.conflict = out.conflict or {}
                out.conflict[color] = s
            end
        elseif s then
            out[color], out.source[color] = s, "seen"
            if seen.exact[color] then out.exact[color] = true end
        end
    end
    if client then
        out.line = client.line
        out.sourceText = CD.SourceText("recipes")
    end
    return out
end

-- Quelle als Text: Blizzards Quellentext (gemerkt), sonst der erste Fundort aus Knowledge.RecipeWhere als Satz
-- („Händler: Name (Gebiet)“) – so kennt jeder bisherige Leser auch die neuen Fundorte (Welle 15b).
function K.RecipeSource(recipeID)
    local text = Source(recipeID)
    if type(text) == "string" and text ~= "" then return text end
    if K.RecipeWhere then
        for _, e in ipairs(K.RecipeWhere(recipeID, { noText = true, max = 1 })) do
            local line = K.WhereText(e)
            if line then return line end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Rezept-Fundorte (Welle 15b; Wunsch des Nutzers vom 15.11.2026 abends: „rezepte und deren fundorte mit ablegen und
-- entsprechend anzeigen / bereitstellen“). Nur Client-IDs als Schlüssel, Namen je Sprache aus der Datenbank bzw. dem
-- Client (docs/archiv/entwurf-entdecker-datenbank.md). Quellen nach Leitlinie 11, jede Angabe nennt ihre Quelle:
--   Client     Blizzards Quellentext (C_TradeSkillUI.GetRecipeSourceText, beim offenen Berufefenster gemerkt)
--   bei dir    besuchte Händler (vendor[npc].w – Preis, begrenzte Menge), besuchte Lehrer (offer[p:0].svc[Rezept]
--              mit at = { [npc] = t } und benötigter Fertigkeit), eigene Beute und Objekte (Core.Drops über
--              Core.Sources.WhereFrom „own“); Ort aus Core.Places bzw. Core.Npcs
--   Addons     QuestieDB (Händler, Beute, Quest-Belohnung) über Core.Sources.WhereFrom zur Laufzeit; AtlasLoot nennt
--              den Rezept-Gegenstand (Core.Sources.RecipeFor(...).recipeItem) – nur für diese Sitzung, nie gespeichert
--
--   Knowledge.RecipeOfItem(itemID)  → recipeID, Weg ("seen" gemerkt | "product" Produkt | "name" Name) oder nil
--   Knowledge.RecipeItem(recipeID)  → itemID, Weg ("seen" | "atlasloot") – Gegenstand, der das Rezept lehrt
--   Knowledge.NoteRecipeItem(recipeID, itemID) → true, wenn in recipeObs[Rezept].item gemerkt (Datenversion 2)
--   Knowledge.RecipeWhere(recipeID, opts) → { eintrag … } nach Art (Händler, Lehrer, Quest, Beute, Objekt, Behälter,
--       Text), je Art „bei dir“ vor fremden Quellen; eintrag = { kind | art, name, map | karte, x, y, zone, source |
--       quelle (Wortlaut „bei dir“, „laut Questie“, „laut Client“), sourceKey ("own" | Addon | "client"), npc, id,
--       price, limited, skill, cnt, text, gone }. opts = { item = Rezept-Gegenstand (auch ohne recipeID),
--       noText = ohne Blizzards Text, max = höchstens so viele, explorer = Entdecker-Wissen mitfragen }
--   Knowledge.WhereText(eintrag)    → „Händler: Name (Gebiet)“ bzw. Blizzards Text (erste Zeile)
--   Knowledge.RecipeSpots()         → { { kind = "vendor" | "trainer", npc, name, map, x, y, profs = { [Beruf] =
--       true }, recipes = { { recipeID, item, name, prof, learned, skill, price } … } } … } – besuchte Händler mit
--       Rezept-Gegenständen und besuchte Berufslehrer mit Rezepten, für die Karte (ezMap); 30 s gemerkt
---------------------------------------------------------------------------

K.WHERE_ORDER = { vendor = 1, trainer = 2, quest = 3, drop = 4, object = 5, container = 6, text = 7 }
K.SPOTS_SECONDS = 30

local function DBReady() return Core.DB and Core.DB.Ready and Core.DB.Ready() end
local function ItemClass(itemID)
    local classID, subClassID = Core.ItemClass(itemID)   -- Core.ItemInstant (T16-16)
    return classID, subClassID
end

-- Beruf eines Rezept-Gegenstands laut Client (Unterklasse der Klasse 9 „Rezept“, KnowledgeData.RECIPE_SUBCLASS)
function K.RecipeItemProfession(itemID)
    local classID, sub = ItemClass(Num(itemID))
    if classID ~= 9 then return nil end
    local D = ns.KnowledgeData
    return D and D.RECIPE_SUBCLASS and D.RECIPE_SUBCLASS[sub or -1] or nil
end

local itemOf, recipeOf = {}, {}   -- Sitzung: Rezept » Gegenstand bzw. Gegenstand » Rezept (auch false = keins)
local function ForgetLinks() itemOf, recipeOf = {}, {} end
K.ForgetRecipeLinks = ForgetLinks
Core.Listen("RECIPES_CHANGED", ForgetLinks, "ezCore.Recipes.Where")
-- ein geöffnetes Berufefenster bringt neue (auch nicht gelernte) Rezepte: Name und Produkt neu zuordnen
ns.On("TRADE_SKILL_SHOW", ForgetLinks)
ns.On("TRADE_SKILL_CLOSE", ForgetLinks)

function K.NoteRecipeItem(recipeID, itemID)
    recipeID, itemID = Num(recipeID), Num(itemID)
    if not (recipeID and itemID) then return false end
    itemOf[recipeID], recipeOf[itemID] = { itemID, "seen" }, { recipeID, "seen" }
    if not DBReady() then return false end
    local k = RecipeKey(recipeID)
    local row = k and Core.DB.Get("recipeObs", k)
    if row and row.item == itemID then return true end
    return k ~= nil and Core.DB.AsOwn(Core.DB.Put, "recipeObs", k, { item = itemID }) == true
end

-- Rezept mit diesem Namen (und Beruf) unter den gesehenen Rezepten
local function RecipeByName(name, prof)
    local kdb = name and RecipeDB()
    if not kdb then return nil end
    for id, rec in pairs(kdb.recipes) do
        if type(rec) == "table" and rec.n == name and (prof == nil or rec.p == nil or rec.p == prof) then return id end
    end
    return nil
end

function K.RecipeOfItem(itemID)
    itemID = Num(itemID)
    if not itemID then return nil end
    local hit = recipeOf[itemID]
    if hit ~= nil then
        if hit then return hit[1], hit[2] end
        return nil
    end
    local found, how, partial
    if DBReady() then
        local paths = Core.DB.Index("recipeObs", "item", itemID)
        if paths[1] then found, how = paths[1][1], "seen" end
    end
    if not found and K.RecipeItemProfession(itemID) then
        local f = K.Get and K.Get(itemID)
        -- Teildaten (Item noch nicht im Zwischenspeicher, Knowledge.lua: _partial): kein Nein merken, sonst bliebe
        -- es bis zum nächsten Berufefenster
        partial = type(f) == "table" and f._partial and true or false
        local r = type(f) == "table" and f.recipe
        if type(r) == "table" then
            local kdb = RecipeDB()
            local key = kdb and type(kdb.created) == "table" and r.createdItemID and kdb.created[r.createdItemID]
            if key then found, how = key, "product"
            else
                key = RecipeByName(r.createdName, r.profession)
                if key then found, how = key, "name" end
            end
        end
    end
    if found then
        recipeOf[itemID] = { found, how }
        itemOf[found] = itemOf[found] or { itemID, how }
    elseif not partial then
        recipeOf[itemID] = false
    end
    return found, how
end

-- Rezept-Gegenstände besuchter Händler dem Rezept zuordnen (recipeObs[Rezept].item). Beim Händler-Besuch geht das nur
-- für Rezepte, die ein Berufefenster schon gezeigt hat; wer den Händler vorher besucht hat, bekommt die Zuordnung hier
-- nach dem Lesen des Berufefensters (Knowledge.NoteRecipesDone). Schon zugeordnete Gegenstände werden übersprungen.
-- → Zahl neu gemerkter Zuordnungen
function K.LinkVendorRecipes()
    if not DBReady() then return 0 end
    local DB = Core.DB
    local todo, seen = {}, {}
    DB.Scan("vendor", function(row)
        for itemID in pairs(type(row.w) == "table" and row.w or {}) do
            local id = Num(itemID)
            if id and not seen[id] then
                seen[id] = true
                if K.RecipeItemProfession(id) and not DB.Index("recipeObs", "item", id)[1] then todo[#todo + 1] = id end
            end
        end
    end)
    local n = 0
    for _, id in ipairs(todo) do
        local recipe, how = K.RecipeOfItem(id)
        if recipe and how ~= "seen" and K.NoteRecipeItem(recipe, id) then n = n + 1 end
    end
    return n
end

local linkPending = false
local function ScheduleLinks()
    if linkPending then return end
    linkPending = true
    C_Timer.After(1, function()
        linkPending = false
        Core.Try(nil, "Recipes LinkVendorRecipes", K.LinkVendorRecipes)
    end)
end
K.ScheduleRecipeLinks = ScheduleLinks

function K.RecipeItem(recipeID)
    recipeID = Num(recipeID)
    if not recipeID then return nil end
    local hit = itemOf[recipeID]
    if hit then return hit[1], hit[2] end
    if DBReady() then
        local k = RecipeKey(recipeID)
        local row = k and Core.DB.Get("recipeObs", k)
        local item = row and Num(row.item)
        if item then
            itemOf[recipeID] = { item, "seen" }
            return item, "seen"
        end
    end
    -- AtlasLoot kennt den Gegenstand über das Produkt (nur Sitzung, nie gespeichert – Leitlinie 10/11)
    local rec = K.Recipe(recipeID)
    local S = Core.Sources
    local product = type(rec) == "table" and Num(rec.o)
    local r = product and S and S.RecipeFor and Core.Call(S.RecipeFor, product)
    local item = type(r) == "table" and Num(r.recipeItem)
    if item and Num(r.spell) == recipeID then
        itemOf[recipeID] = { item, "atlasloot" }
        return item, "atlasloot"
    end
    return nil
end

-- Ort eines NPC: Core.Places (häufigster Ort) bzw. Core.Npcs (zuletzt gesehen)
local function NpcPlace(npc)
    local P = Core.Places
    local p = P and P.Of and P.Of("npc", npc)[1]
    if p and Num(p.map) and p.x and p.y then return p.map, p.x, p.y end
    local N = Core.Npcs
    local e = N and N.Get and N.Get(npc)
    if e and e.map and e.x and e.y then return e.map, e.x, e.y end
    return nil
end

local function NpcName(npc)
    local name = DBReady() and Core.DB.Text("npc", npc)
    if type(name) ~= "string" or name == "" then
        local e = Core.Npcs and Core.Npcs.Get and Core.Npcs.Get(npc)
        name = e and e.name
    end
    return type(name) == "string" and name ~= "" and name or nil
end

local function ZoneName(map)
    return Num(map) and Core.MapName and Core.MapName(map) or nil
end

local function OwnLabel()
    local S = Core.Sources
    return S and S.Label and S.Label({ source = "own", sourceKey = "own" }) or (Core.L and Core.L.DB_OWN) or "own"
end

local function Entry(e)
    e.art, e.karte, e.quelle = e.kind, e.map, e.source
    if e.map and not e.zone then e.zone = ZoneName(e.map) end
    return e
end

-- Lehrer, die das Rezept anbieten (offer der Berufslehrer, Notschlüssel ohne Zauber-ID zählen nicht)
local function TrainerEntries(recipeID, out)
    local T = Core.Trainers
    if not (recipeID and T and T.Offers and DBReady()) then return end
    local art = Core.DB.Keys.Offer("profession", 0)
    local row = art and T.Offers(art)
    local svc = row and type(row.svc) == "table" and row.svc[recipeID]
    if type(svc) ~= "table" then return end
    local npcs = {}
    for npc in pairs(type(svc.at) == "table" and svc.at or {}) do npcs[#npcs + 1] = npc end
    table.sort(npcs, function(a, b) return tostring(a) < tostring(b) end)
    for _, npc in ipairs(npcs) do
        local map, x, y = NpcPlace(npc)
        out[#out + 1] = Entry({ kind = "trainer", npc = Num(npc), id = Num(npc), name = NpcName(npc), map = map,
            x = x, y = y, price = Num(svc.pr), skill = Num(svc.skill), source = OwnLabel(), sourceKey = "own",
            gone = svc.gone })
    end
end

-- Besuchte Händler mit dem Rezept-Gegenstand (Preis, begrenzte Menge; nicht mehr gesehene als gone)
local function VendorEntries(itemID, out, seen)
    local V = Core.Vendors
    if not (itemID and V and V.Selling and DBReady()) then return end
    for _, v in ipairs(V.Selling(itemID)) do
        local npc = Num(v.npc)
        if npc then
            seen[npc] = true
            local map, x, y = NpcPlace(npc)
            out[#out + 1] = Entry({ kind = "vendor", npc = npc, id = npc, name = NpcName(npc), map = map, x = x, y = y,
                price = Num(v.pr), limited = Num(v.lim) or nil, source = OwnLabel(), sourceKey = "own", gone = v.gone })
        end
    end
end

local WHERE_LIST = { vendors = "vendor", quests = "quest", drops = "drop", objects = "object", containers = "container" }

-- Woher laut Core.Sources (eigene Beute zuerst, dann QuestieDB) für den Rezept-Gegenstand
local function SourceEntries(itemID, out, seen, opts)
    local S = Core.Sources
    if not (itemID and S and S.WhereFrom) then return end
    local results = Core.Call(S.WhereFrom, itemID, { all = true, explorer = opts.explorer })
    for _, res in ipairs(type(results) == "table" and results or {}) do
        local label = S.Label and S.Label(res) or res.source
        for list, kind in pairs(WHERE_LIST) do
            for _, w in ipairs(type(res[list]) == "table" and res[list] or {}) do
                local npc = kind == "vendor" and Num(w.id) or nil
                if not (npc and seen[npc] and res.sourceKey == "own") then
                    out[#out + 1] = Entry({ kind = kind, id = Num(w.id), npc = npc, name = w.name, map = Num(w.map),
                        x = Num(w.x), y = Num(w.y), zone = w.zone, price = Num(w.price), cnt = Num(w.cnt),
                        source = label, sourceKey = res.sourceKey })
                end
            end
        end
    end
end

function K.RecipeWhere(recipeID, opts)
    opts = type(opts) == "table" and opts or {}
    recipeID = Num(recipeID)
    local itemID = Num(opts.item)
    if recipeID and not itemID then itemID = K.RecipeItem(recipeID) end
    if itemID and not recipeID then recipeID = K.RecipeOfItem(itemID) end
    local out, seen = {}, {}
    VendorEntries(itemID, out, seen)
    TrainerEntries(recipeID, out)
    SourceEntries(itemID, out, seen, opts)
    if not opts.noText and recipeID then
        local text = Source(recipeID)
        if type(text) == "string" and text ~= "" then
            out[#out + 1] = Entry({ kind = "text", text = text, source = L.SOURCE_CLIENT, sourceKey = "client" })
        end
    end
    -- je Art: „bei dir“ vor fremden Quellen, dann Name; stabil über die Lage in der Liste
    for i, e in ipairs(out) do e._i = i end
    table.sort(out, function(a, b)
        local ka, kb = K.WHERE_ORDER[a.kind] or 9, K.WHERE_ORDER[b.kind] or 9
        if ka ~= kb then return ka < kb end
        local oa, ob = a.sourceKey == "own" and 0 or 1, b.sourceKey == "own" and 0 or 1
        if oa ~= ob then return oa < ob end
        if (a.gone and 1 or 0) ~= (b.gone and 1 or 0) then return not a.gone end
        return a._i < b._i
    end)
    local max = Num(opts.max)
    local list = {}
    for i, e in ipairs(out) do
        e._i = nil
        if not max or i <= max then list[#list + 1] = e end
    end
    return list
end

local KIND_TEXT = { vendor = "WHERE_VENDOR", trainer = "WHERE_TRAINER", quest = "WHERE_QUEST", drop = "WHERE_DROP",
    object = "WHERE_OBJECT", container = "WHERE_CONTAINER" }

function K.WhereText(e)
    if type(e) ~= "table" then return nil end
    if e.kind == "text" then
        local first = type(e.text) == "string" and e.text:match("^[^\n]+") or e.text
        return first and Core.Trim(Core.StripColors(first)) or nil
    end
    local key = KIND_TEXT[e.kind]
    if not key then return nil end
    local name = e.name or (e.id and ("#" .. tostring(e.id))) or "?"
    if e.zone then return L[key .. "_AT"]:format(name, e.zone) end
    return L[key]:format(name)
end

-- Punkte für die Karte: besuchte Händler mit Rezept-Gegenständen, besuchte Berufslehrer mit Rezepten
local spots, spotsAt
local function ForgetSpots() spots = nil end
K.ForgetRecipeSpots = ForgetSpots
Core.Listen("RECIPES_CHANGED", ForgetSpots, "ezCore.Recipes.Spots")
Core.Listen("DB_CHANGED", function(name)
    if name == "vendor" or name == "offer" or name == "recipeObs" or name == "spot" then spots = nil end
end, "ezCore.Recipes.Spots")

local function Learned(recipeID)
    return recipeID ~= nil and Core.charKey ~= nil and Knows(Core.charKey, recipeID)
end

local function BuildSpots()
    local list = {}
    if not DBReady() then return list end
    local DB = Core.DB
    DB.Scan("vendor", function(row, _, npc)
        local recipes, profs = {}, {}
        for itemID, w in pairs(type(row.w) == "table" and row.w or {}) do
            local prof = K.RecipeItemProfession(itemID)
            if prof and not (Num(row.tf) and type(w) == "table" and (Num(w.t) or 0) < row.tf) then
                local id = K.RecipeOfItem(itemID)
                local rec = id and K.Recipe(id)
                recipes[#recipes + 1] = { recipeID = id, item = itemID, prof = prof, learned = Learned(id),
                    name = (type(rec) == "table" and rec.n) or (Core.ItemNameByID and Core.ItemNameByID(itemID)) or nil,
                    price = type(w) == "table" and Num(w.pr) or nil }
                profs[prof] = true
            end
        end
        local map, x, y = NpcPlace(npc)
        if #recipes > 0 and map then
            list[#list + 1] = { kind = "vendor", npc = Num(npc), name = NpcName(npc), map = map, x = x, y = y,
                profs = profs, recipes = recipes }
        end
    end)
    local T = Core.Trainers
    local art = DB.Keys.Offer("profession", 0)
    local row = art and T and T.Offers and T.Offers(art)
    local byNpc = {}
    for key, svc in pairs(row and type(row.svc) == "table" and row.svc or {}) do
        local id = Num(key)
        local rec = id and K.Recipe(id)
        if type(rec) == "table" and type(svc) == "table" and not svc.gone then
            for npc in pairs(type(svc.at) == "table" and svc.at or {}) do
                local s = byNpc[npc] or { recipes = {}, profs = {} }
                byNpc[npc] = s
                s.recipes[#s.recipes + 1] = { recipeID = id, name = rec.n, prof = rec.p, learned = Learned(id),
                    skill = Num(svc.skill), price = Num(svc.pr) }
                if rec.p then s.profs[rec.p] = true end
            end
        end
    end
    for npc, s in pairs(byNpc) do
        local map, x, y = NpcPlace(npc)
        if map then
            list[#list + 1] = { kind = "trainer", npc = Num(npc), name = NpcName(npc), map = map, x = x, y = y,
                profs = s.profs, recipes = s.recipes }
        end
    end
    for _, s in ipairs(list) do
        table.sort(s.recipes, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    end
    return list
end

function K.RecipeSpots()
    local now = Core.Uptime and Core.Uptime() or 0
    if spots and spotsAt and now - spotsAt < K.SPOTS_SECONDS then return spots end
    spots, spotsAt = BuildSpots(), now
    return spots
end

-- Rohstoffe und Ressourcen: Handwerkswaren (Klasse 7) und Reagenzien (Klasse 5).
local RESOURCE_CLASSES = { [5] = true, [7] = true }
function K.IsResource(itemID)
    itemID = Num(itemID)
    if not itemID then return false end
    return RESOURCE_CLASSES[Core.ItemClass(itemID) or -1] == true
end

local VENDORS_PER_ITEM = 5

-- Ware i des offenen Händlers über C_MerchantFrame.GetItemInfo. Den Rückfall auf das alte GetMerchantItemInfo gibt es
-- seit Welle 23b nicht mehr (A67): Die Funktion fehlt im Forever-Client (Probe 14.11.2026, docs/archiv/probe-ergebnis-2026-
-- 11-14.md, Abschnitt „Funktionen“; docs/datenkatalog-client.md) – der Zweig lief nie.
local function MerchantItem(i)
    local id = GetMerchantItemID and Num(GetMerchantItemID(i))
    local price, stack, available
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then price, stack, available = info.price, info.stackCount, info.numAvailable end
    end
    return id, Num(price), Num(stack), Num(available)
end

-- Händler mit Rohstoffen merken: je Gegenstand höchstens fünf Händler, der zuletzt gesehene ersetzt den ältesten.
function K.ScanVendorResources()
    if Moved("vendors") then
        -- ein Schreiber: das Sortiment liest die Entdecker-Datenbank (Discovery.ScanVendor, alle Waren). Bei
        -- ausgeschaltetem Sammeln liest der Sammler nicht mit – dann scannt diese eigene Funktion selbst (DB.AsOwn).
        if not Core.DB.Collecting() then Core.DB.AsOwn(Core.Discovery.ScanVendor) end
        local count = 0
        for i = 1, Num(GetMerchantNumItems and GetMerchantNumItems()) or 0 do
            local id, price = MerchantItem(i)
            if id and price and price > 0 and K.IsResource(id) then count = count + 1 end
        end
        return count
    end
    local kdb = KDB()
    if not (kdb and GetMerchantNumItems) then return 0 end
    kdb.vendors = kdb.vendors or {}
    local guid = UnitGUID and Plain(UnitGUID("npc"))
    local npc = guid and Core.NpcID(guid)
    local name = UnitName and Plain(UnitName("npc"))
    if not (npc or name) then return 0 end
    local zone = GetRealZoneText and Plain(GetRealZoneText())
    local count = 0
    for i = 1, Num(GetMerchantNumItems()) or 0 do
        local id, price, stack, available = MerchantItem(i)
        if id and price and price > 0 and K.IsResource(id) then
            local list = kdb.vendors[id] or {}
            kdb.vendors[id] = list
            local key = npc or name
            local entry = list[key] or {}
            local isNew = list[key] == nil
            entry.name, entry.zone, entry.price, entry.stack = name, zone, price, stack or 1
            entry.limited = available ~= nil and available >= 0 or nil
            entry.seen = time and time() or 0
            list[key] = entry
            if isNew then
                local n, oldestKey, oldest = 0, nil, nil
                for k, e in pairs(list) do
                    n = n + 1
                    if type(e) == "table" and (oldest == nil or (e.seen or 0) < oldest) then oldestKey, oldest = k, e.seen or 0 end
                end
                if n > VENDORS_PER_ITEM and oldestKey then list[oldestKey] = nil end
            end
            count = count + 1
        end
    end
    return count
end

function K.VendorSources(itemID)
    if Moved("vendors") then return Core.Discovery.VendorList(itemID) end
    itemID = Num(itemID)
    local kdb = itemID and KDB()
    local list = {}
    local vendors = kdb and type(kdb.vendors) == "table" and kdb.vendors[itemID]
    if type(vendors) ~= "table" then return list end
    local npcs = Core.Npcs
    for key, e in pairs(vendors) do
        if type(e) == "table" then
            local npc = type(key) == "number" and key or nil
            -- Wo der Händler steht, weiß das NPC-Ortswissen (Npcs.lua) – eine Quelle, hier nur nachgeschlagen (V-136).
            local where = npc and npcs and npcs.Get and npcs.Get(npc) or nil
            list[#list + 1] = { npc = npc, name = e.name, zone = e.zone, price = e.price,
                stack = e.stack or 1, limited = e.limited, seen = e.seen,
                map = where and where.map or nil, x = where and where.x or nil, y = where and where.y or nil }
        end
    end
    table.sort(list, function(a, b) return (a.price or 0) / math.max(1, a.stack) < (b.price or 0) / math.max(1, b.stack) end)
    return list
end

-- Händler, die Rezepte verkaufen: Quelle über das hergestellte Produkt (Item-Wissen) dem Rezept zuordnen.
local function ScanMerchant()
    local kdb = KDB()
    if not (kdb and GetMerchantNumItems and GetMerchantItemLink and type(kdb.created) == "table") then return end
    local npc = UnitName and Plain(UnitName("npc"))
    local zone = GetRealZoneText and Plain(GetRealZoneText())
    if not npc then return end
    local text = L.SOURCE_VENDOR:format(npc, zone or "?")
    for i = 1, Num(GetMerchantNumItems()) or 0 do
        local link = Plain(GetMerchantItemLink(i))
        local f = link and K.Get(link)
        local r = f and f.recipe
        local key = r and r.createdItemID and kdb.created[r.createdItemID]
        if key and not Source(key) then SetSource(key, text) end
        -- Welle 15b: welcher Gegenstand lehrt welches Rezept – beim Besuch gemerkt (recipeObs[Rezept].item); die Ware
        -- selbst (Preis, begrenzte Menge) merkt die Entdecker-Datenbank (Discovery.ScanVendor, vendor[npc].w)
        local id = link and Core.ItemID and Core.ItemID(link)
        if id and K.RecipeItemProfession(id) then
            local recipe = K.RecipeOfItem(id)
            if recipe then K.NoteRecipeItem(recipe, id) end
        end
    end
end

ns.On("MERCHANT_SHOW", function()
    C_Timer.After(0.5, function()
        Core.Try(nil, "Recipes ScanMerchant", ScanMerchant)
        Core.Try(nil, "Recipes ScanVendorResources", K.ScanVendorResources)
    end)
end)

-- Vergessener Twink: auch aus „wer kann was“ streichen.
Core.Listen("CHAR_FORGOTTEN", function(key)
    local kdb = KDB()
    if kdb and key then kdb.known[key] = nil end
end, "ezCore.Recipes")
