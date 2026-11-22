local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Data – alles, was ezCraft rechnet, ohne Oberfläche (deshalb gut zu testen).

    Rezept      Data.Recipe(recipeID) → { recipeID, name, icon, learned, difficulty, canSkillUp, maxTrivial,
                                          product, reagents = { { itemID, count } } }
                live aus Blizzards Berufe-API (C_TradeSkillUI), sonst aus dem Item-Wissen (ezCore).
    Bestände    Data.Stock(itemID) → { bags, bank, mail, guild, alts, altsOther, altList }
                aus ezCore.Inventory.CountAll (alle Twinks, Gildenbanken); Data.Have(stock) zählt nach Einstellung.
    Material    Data.Materials(recipe, menge) → Zeilen mit Bedarf, Bestand, fehlt; dazu herstellbar.
    Skill       Data.SkillStages(recipe) → { orange, yellow, green, gray, current, approx, source, computed, conflict,
                sourceText } – zuerst laut Client-Tabellen (ezCores Knowledge.RecipeStages, Welle 26), sonst beobachtet;
                Data.StageAt(stages, fertigkeit)
    Twinks      Data.Crafters(recipe) → { charKey, … } oder nil (das Item-Wissen kennt es noch nicht)
    Kosten      Data.Price(itemID), Data.Cost(zeilen), Data.ProductValue(recipe, menge) aus ezCore.Prices;
                Data.Profit(recipe, menge, kosten) → Ergebnis und Gewinn nach Auktionsgebühr (Prices.Net, AH-32);
                Data.CostSource(kosten), Data.PriceSource(itemID) → Quelle und Alter in ezCores Wortlaut;
                Data.CraftCostOther() → Name von Auctionator, wenn es Kosten und Gewinn am Rezept zeigt
    Beobachten  Data.WatchItems() → Zutaten der Rezepte auf der Einkaufsliste, der Lieblingsrezepte und der zuletzt
                angesehenen, danach deren Ergebnisse (höchstens Data.WATCH_MAX); angemeldet bei
                Prices.AddWatchProvider (AH-39)
    Fehlend     Data.MissingRecipes() → nicht erlernte Rezepte des offenen Berufs mit Quelle
    Gegenstand  Data.RecipeForItem(itemID) → Rezept, das ihn herstellt; Data.RecipesUsing(itemID) → wofür er Zutat ist
                (Rezept-Wissen von ezCore: jedes Rezept, das ein Twink im Berufefenster einmal gesehen hat)
    Abklingzeit Data.CooldownsByChar() aus ezCore.Professions (alle Twinks);
                Data.ReadyCooldowns() → fertige, Data.ReadyCooldownsMerged() → dieselben, geteilte Abklingzeiten
                (Transmutationen) je Twink zusammengefasst (ezCores Gruppe); Data.ReadyCooldownLine(e) → „Rezept bei
                Twink“; Data.CooldownLabel(e) → Name, bei mehreren Zaubern einer Gruppe der Name der Gruppe
    Sammeln     Data.Gather(itemID) → { here, text, line } aus ezCore.Gathering (eigene Ernten „bei dir“ zuerst);
                Data.ShowGather(itemID) öffnet über ezMap die Weltkarte mit den Fundorten (SAM-24); Data.GatherItems,
                Data.SkinItems, Data.SkinLine für das Menü im Berufsbuch und die Kürschner-Liste (SAM-25)
    Datenbank   Data.SourceRecipeForItem(itemID), Data.SourceRecipesUsing(itemID) → Rezepte „laut AtlasLoot“ über
                ezCores Brücke Core.Sources (nur zur Laufzeit gefragt, nichts kopiert); Data.MaybeCrafted(itemID);
                Data.SourceProblem() → Satz, wenn die Datenbank läuft, aber nicht wie erwartet antwortet

    Was über Rezepte dauerhaft gelernt wird (wer es kann, Skill-Stufen, Quellen), gehört ins Item-Wissen
    von ezCore. Fehlt dort eine Funktion, zeigt ezCraft den Teil nicht an (Data.WaitingLines nennt ihn).
]]

local Data = {}
ns.Data = Data

local floor, huge = math.floor, math.huge
local Plain, Num = Core.Plain, Core.Num
local EMPTY = {}

-- Blizzard-Aufruf, der nie einen Fehler wirft (ezCore): bei Fehler nil, sonst alle Rückgaben.
local Call = Core.Call
Data.Call = Core.Call

local function Knowledge() return Core.Knowledge end

-- Funktion des Item-Wissens, falls ezCore sie schon hat.
local function KnowledgeFn(name)
    local K = Knowledge()
    local fn = K and K[name]
    return type(fn) == "function" and fn or nil
end

---------------------------------------------------------------------------
-- Gegenstände
---------------------------------------------------------------------------

-- Name in der Spielsprache (ezCore lädt fehlende Daten nach); bis dahin „#itemID“.
function Data.ItemName(itemID)
    if not itemID then return "?" end
    return Core.ItemNameByID(itemID) or ("#" .. tostring(itemID))
end

function Data.ItemIcon(itemID)
    if not itemID then return nil end
    return Core.ItemIcon(itemID)
end

---------------------------------------------------------------------------
-- Rezepte
---------------------------------------------------------------------------

-- Rezept aus dem offenen Berufefenster (C_TradeSkillUI). nil, wenn der Client es nicht kennt.
-- Die Zutaten liest ezCores Rezept-Leser (Knowledge.BasicReagents: nur Grundzutaten aus Pflicht-Plätzen, gleiche
-- zusammengezählt) – derselbe Filter wie das Rezept-Wissen, mit und ohne offenes Fenster also dieselbe Liste.
function Data.LiveRecipe(recipeID)
    local api = C_TradeSkillUI
    recipeID = Num(recipeID)
    if not (api and recipeID) then return nil end
    local info = Plain(Call(api.GetRecipeInfo, recipeID))
    local schem = Plain(Call(api.GetRecipeSchematic, recipeID, false))
    if type(schem) ~= "table" then return nil end
    info = type(info) == "table" and info or EMPTY
    -- Produkt: outputItemID des Schemas, sonst ezCores Rückweg (Knowledge.RecipeProduct: Ausgabe-Daten, Rezept-Link –
    -- Forever nennt outputItemID nicht immer, CRAFT-06/DG-41)
    local product = Num(schem.outputItemID)
    if not product then product = Num(Plain((Call(KnowledgeFn("RecipeProduct"), recipeID, schem)))) end
    local recipe = {
        recipeID = recipeID,
        name = Plain(info.name) or Plain(schem.name) or ("#" .. recipeID),
        icon = Plain(info.icon),
        learned = info.learned == true,
        canSkillUp = info.canSkillUp == true,
        difficulty = Num(info.relativeDifficulty),
        maxTrivial = Num(info.maxTrivialLevel),
        product = product,
        makes = Num(schem.quantityMin) or 1,
        reagents = {},
        live = true,
    }
    local _, list = Call(KnowledgeFn("BasicReagents"), schem)
    for _, row in ipairs(type(list) == "table" and list or EMPTY) do
        recipe.reagents[#recipe.reagents + 1] = { itemID = row.itemID, count = row.count }
    end
    return recipe
end

-- Rezept aus dem Item-Wissen (ezCore), falls es dafür eine Funktion gibt: { n, p, o, r = { [itemID] = n } }.
function Data.StoredRecipe(recipeID)
    local fn = KnowledgeFn("Recipe")
    local rec = fn and Plain(Call(fn, recipeID))
    if type(rec) ~= "table" then return nil end
    local recipe = { recipeID = recipeID, name = rec.n or ("#" .. tostring(recipeID)), product = rec.o,
        icon = rec.o and Data.ItemIcon(rec.o) or nil, profession = rec.p, reagents = {} }
    for itemID, count in pairs(rec.r or EMPTY) do
        recipe.reagents[#recipe.reagents + 1] = { itemID = itemID, count = count }
    end
    table.sort(recipe.reagents, function(a, b) return a.itemID < b.itemID end)
    return recipe
end

-- Eine Regel für alle (Einkaufsliste, Berufefenster, Tooltip; V-141): live nur, wenn Blizzard Zutaten nennt.
-- Liefert das Schema keine (Fenster zu, Daten noch nicht da), kommen Zutaten, Produkt und Beruf aus dem
-- Rezept-Wissen; was nur das offene Fenster weiß (gelernt, Skill-Farbe, „grau ab“, Name, Symbol), bleibt.
function Data.Recipe(recipeID)
    local live = Data.LiveRecipe(recipeID)
    if live and #live.reagents > 0 then return live end
    local stored = Data.StoredRecipe(recipeID)
    if not (live and stored) then return live or stored end
    if #stored.reagents == 0 then return live end
    live.reagents = stored.reagents
    live.product = live.product or stored.product
    live.profession = stored.profession
    live.icon = live.icon or stored.icon
    if live.name == "#" .. tostring(live.recipeID) then live.name = stored.name end
    return live
end

-- Name des offenen Berufs (Client-Sprache) oder nil.
function Data.ProfessionName()
    local api = C_TradeSkillUI
    local info = api and Plain(Call(api.GetBaseProfessionInfo))
    local name = type(info) == "table" and Plain(info.professionName)
    return type(name) == "string" and name ~= "" and name or nil
end

-- Gerade im Berufefenster gewähltes Rezept (nil ohne Fenster).
function Data.SelectedRecipeID()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if not (form and form.GetRecipeInfo) then return nil end
    local info = Call(form.GetRecipeInfo, form)
    return type(info) == "table" and Num(info.recipeID) or nil
end

---------------------------------------------------------------------------
-- Bestände: eigener Charakter, Gildenbank, Twinks
---------------------------------------------------------------------------

-- Empfänger und „kann Post bekommen“ für einen eigenen Twink (gleiche Fraktion, erreichbarer Realm).
-- Die Regel liegt in ezCore (Core.AltRecipient, gemeinsam mit ezMails Adressbuch).
function Data.Recipient(key)
    if type(Core.AltRecipient) ~= "function" then return nil, false end
    local name, mailable = Call(Core.AltRecipient, key)
    return name, mailable == true
end

-- Bestand aus der einen Regel „erreichbarer Bestand“ von ezCore (Inventory.Reachable über Inventory.CountAll;
-- Gesamtreview 18.11.2026, T4-NR5 – dieselbe Regel nutzt ezAuction). Gezählt wird, was sich verschicken lässt: Tasche,
-- Bank und Post – Angelegtes nicht; Gildenbank nur die eigene; Twinks getrennt nach „kann Post bekommen“.
function Data.Stock(itemID)
    local stock = { bags = 0, bank = 0, mail = 0, guild = 0, alts = 0, altsOther = 0, altList = {} }
    if not itemID then return stock end
    local inv = Core.Inventory
    local reach = inv and Call(inv.Reachable, itemID)
    if type(reach) ~= "table" then return stock end
    for k in pairs(stock) do
        if k ~= "altList" then stock[k] = Num(reach[k]) or 0 end
    end
    stock.altList = type(reach.altList) == "table" and reach.altList or {}
    return stock
end

-- Was davon als „vorhanden“ zählt (Einstellungen countBank, countMail, countGuild, countAlts).
function Data.Have(stock, S)
    S = S or ns.S or EMPTY
    local n = stock.bags
    if S.countBank then n = n + stock.bank end
    if S.countMail then n = n + stock.mail end
    if S.countGuild then n = n + stock.guild end
    if S.countAlts then n = n + stock.alts end
    return n
end

---------------------------------------------------------------------------
-- Material eines Rezepts
---------------------------------------------------------------------------

-- Zeilen { itemID, name, icon, per, need, stock, have, missing, status } und herstellbar.
-- status: "bags" (reicht in der Tasche), "have" (reicht mit Bank, Post, Twinks …), "missing".
function Data.Materials(recipe, quantity, S)
    quantity = math.max(1, floor(Num(quantity) or 1))
    local rows, bagsOnly, all = {}, huge, huge
    for _, reagent in ipairs(recipe and recipe.reagents or EMPTY) do
        local stock = Data.Stock(reagent.itemID)
        local have = Data.Have(stock, S)
        local need = reagent.count * quantity
        local row = { itemID = reagent.itemID, name = Data.ItemName(reagent.itemID), icon = Data.ItemIcon(reagent.itemID),
            per = reagent.count, need = need, stock = stock, have = have, missing = math.max(0, need - have) }
        row.status = stock.bags >= need and "bags" or (have >= need and "have" or "missing")
        rows[#rows + 1] = row
        bagsOnly = math.min(bagsOnly, floor(stock.bags / reagent.count))
        all = math.min(all, floor(have / reagent.count))
    end
    if #rows == 0 then bagsOnly, all = 0, 0 end
    return rows, { bags = bagsOnly, all = all }
end

---------------------------------------------------------------------------
-- Preise (Preis-Wissen von ezCore, gelernt in Blizzards Auktionshaus)
---------------------------------------------------------------------------

-- { each = Kupfer je Stück, seen = Zeitstempel } oder nil (kein Preis bekannt). Marktwert, sonst Tiefstpreis.
function Data.Price(itemID)
    local prices = Core.Prices
    local info = prices and type(prices.Get) == "function" and Plain(Call(prices.Get, itemID))
    if type(info) ~= "table" then return nil end
    local each = Num(info.market) or Num(info.min)
    if not each then return nil end
    return { each = each, seen = Num(info.seen) }
end

function Data.HasPrices()
    return Core.Prices ~= nil and type(Core.Prices.Get) == "function"
end

-- Kosten von Material-Zeilen (Data.Materials oder Shopping.Totals):
-- { total = alles Gebrauchte, missing = nur das Fehlende, unknown = Zahl der Zutaten ohne Preis, priced = Zahl der
--   Zutaten mit Preis, oldest = Zeitpunkt des ältesten dieser Preise oder nil }.
function Data.Cost(rows)
    local cost = { total = 0, missing = 0, unknown = 0, priced = 0 }
    for _, row in ipairs(rows or EMPTY) do
        local price = Data.Price(row.itemID)
        if price then
            cost.total = cost.total + price.each * row.need
            cost.missing = cost.missing + price.each * (row.missing or 0)
            cost.priced = cost.priced + 1
            if price.seen and (not cost.oldest or price.seen < cost.oldest) then cost.oldest = price.seen end
        else
            cost.unknown = cost.unknown + 1
        end
    end
    return cost
end

-- Auktionswert des Ergebnisses (Menge × Stückzahl je Herstellung) oder nil.
function Data.ProductValue(recipe, quantity)
    if not (recipe and recipe.product) then return nil end
    local price = Data.Price(recipe.product)
    if not price then return nil end
    return price.each * (recipe.makes or 1) * math.max(1, floor(Num(quantity) or 1))
end

-- Quelle eines Preises in ezCores Wortlaut (Prices.SourceText: „laut deinen Erfassungen (Komplett-Scan, vor 2 Std.)“)
-- oder nil.
function Data.PriceSource(itemID)
    local prices = Core.Prices
    if not (prices and type(prices.Get) == "function" and type(prices.SourceText) == "function") then return nil end
    local info = Plain(Call(prices.Get, itemID))
    local text = type(info) == "table" and Plain(Call(prices.SourceText, info))
    return type(text) == "string" and text ~= "" and text or nil
end

-- Quelle einer Materialsumme (Leitlinie 11): „laut deinen Erfassungen, ältester Preis: vor 2 Std.“ – die Zutaten
-- haben verschieden alte Preise, genannt wird der älteste. nil ohne Preis.
function Data.CostSource(cost)
    if not (type(cost) == "table" and cost.oldest) then return nil end
    local prices = Core.Prices
    local own = prices and type(prices.SourceText) == "function" and Plain(Call(prices.SourceText, { source = "own" }))
    if type(own) ~= "string" or own == "" then return nil end
    return L.COST_OLDEST:format(own, Core.Ago(cost.oldest))
end

-- Laufzeit, mit der der Gewinn rechnet (Prices.Net: 1–3; 2 ist Blizzards mittlere Laufzeit).
Data.SELL_DURATION = 2

-- Ergebnis und Gewinn nach Auktionsgebühr (AH-32) oder nil (kein Preis für das Ergebnis):
-- { gross, count, kind, net, fee, feeStand, profit, source, deposit, depositStand }
--   kind "net"   Anteil des Hauses bekannt (ezCore misst ihn an deinen Verkaufsabrechnungen): net = Erlös nach Gebühr,
--                fee = Gebühr, feeStand = „zuletzt gemessen am …“ bzw. „jetzt“ (Prices.StandText)
--   kind "gross" Gebühr noch unbekannt (oder ezCore ohne Prices.Net): der Gewinn ist brutto und heißt auch so
--   profit       Erlös (bzw. Brutto) minus Materialkosten – nur, wenn jede Zutat einen Preis hat (cost.unknown == 0)
--   source       Quelle und Alter des Preises für das Ergebnis (Data.PriceSource)
--   deposit      Anzahlung für SELL_DURATION (Prices.Net: Blizzards Wert am offenen Auktionshaus, sonst die gemessene
--                Regel) – verloren, wenn die Auktion abläuft; depositStand = „jetzt“ bzw. „zuletzt gemessen am …“
-- Die Anzahlung zählt nicht zum Gewinn: Sie kommt beim Verkauf zurück (Welle 23, A3: eigene Zeile im Seitenteil).
-- Prices.Net rät nie – unbekannt bleibt unbekannt.
function Data.Profit(recipe, quantity, cost)
    if not (recipe and recipe.product) then return nil end
    local price = Data.Price(recipe.product)
    if not price then return nil end
    local count = (recipe.makes or 1) * math.max(1, floor(Num(quantity) or 1))
    local out = { gross = price.each * count, count = count, kind = "gross", source = Data.PriceSource(recipe.product) }
    local prices = Core.Prices
    local net = prices and type(prices.Net) == "function"
        and Plain(Call(prices.Net, recipe.product, price.each, Data.SELL_DURATION, count))
    local known = type(net) == "table" and type(net.bekannt) == "table" and net.bekannt.erloes == true
    if known and Num(net.erloes) and Num(net.anteil) then
        out.kind, out.net, out.fee = "net", Num(net.erloes), Num(net.anteil)
        out.gross = Num(net.brutto) or out.gross
        local stand = type(net.stand) == "table" and net.stand.anteil or nil
        local text = stand and type(prices.StandText) == "function" and Plain(Call(prices.StandText, stand))
        out.feeStand = type(text) == "string" and text ~= "" and text or nil
    end
    if type(net) == "table" and type(net.bekannt) == "table" and net.bekannt.anzahlung == true and Num(net.anzahlung) then
        out.deposit = Num(net.anzahlung)
        local stand = type(net.stand) == "table" and net.stand.anzahlung or nil
        local text = stand and type(prices.StandText) == "function" and Plain(Call(prices.StandText, stand))
        out.depositStand = type(text) == "string" and text ~= "" and text or nil
    end
    if type(cost) == "table" and cost.unknown == 0 then out.profit = (out.net or out.gross) - cost.total end
    return out
end

---------------------------------------------------------------------------
-- Stufen der Skill-Farben
---------------------------------------------------------------------------

Data.STAGES = { "orange", "yellow", "green", "gray" }
local IS_STAGE = { orange = true, yellow = true, green = true, gray = true }
-- Enum.TradeskillRelativeDifficulty: Optimal 0, Medium 1, Easy 2, Trivial 3.
local DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

-- Farbe einer Stufe → r, g, b aus ezCores Core.Gathering.SkillRGB (Blizzards TradeSkillTypeColor, sonst dieselben
-- Werte dort) – eine Quelle für ezCraft und ezMap (Welle 23, A1; vorher die eigene Kopie Data.STAGE_RGB).
-- Was keine der vier Stufen ist, zeigt ezCraft grau wie bisher.
function Data.StageRGB(stage)
    return Core.Gathering.SkillRGB(IS_STAGE[stage] and stage or "gray")
end

function Data.IsStage(stage) return IS_STAGE[stage] == true end

function Data.StageColorCode(stage)
    local r, g, b = Data.StageRGB(stage)
    return Core.ColorCode(r, g, b)
end

-- { orange, yellow, green, gray = Fertigkeit ab der die Farbe gilt (nil = unbekannt), current = Farbe jetzt,
--   approx = { [farbe] = true } für Grenzen, die das Item-Wissen nur beobachtet hat (die Farbe gilt spätestens ab da),
--   source = { [farbe] = "client" | "seen" | "live" } (Leitlinie 11: laut Client-Tabellen, bei dir beobachtet, laut
--   offenem Berufefenster), computed = { green = true } (gerechnet), sourceText = Quelle der Client-Tabellen als Text,
--   conflict = { [farbe] = { seen = beobachtet | nil, live = Berufefenster | nil, client = Tabelle } } | nil }
-- Welle 26 (F2, Paket modul/ezcraft-farbstufen): zuerst ezCores Knowledge.RecipeStages – die Client-Tabellen
-- (SkillLineAbility laut wago.tools) für alle Rezepte, auch nie gesehene, die Beobachtung als Rückfall und Gegenprobe;
-- ohne sie (älteres ezCore) wie bisher Knowledge.SkillStages. Eine Abweichung überschreibt nichts still, sie steht
-- unter conflict und im Tooltip.
function Data.SkillStages(recipe)
    local stages = { approx = {}, source = {} }
    if not recipe then return stages end
    local fn = KnowledgeFn("RecipeStages")
    local known = fn and Plain(Call(fn, recipe.recipeID))
    if type(known) ~= "table" then
        fn = KnowledgeFn("SkillStages")
        known = fn and Plain(Call(fn, recipe.recipeID))
    end
    local client = {}
    if type(known) == "table" then
        local exact = type(known.exact) == "table" and known.exact or nil
        local source = type(known.source) == "table" and known.source or EMPTY
        local computed = type(known.computed) == "table" and known.computed or EMPTY
        local conflict = type(known.conflict) == "table" and known.conflict or EMPTY
        for _, stage in ipairs(Data.STAGES) do
            local value = Num(known[stage])
            stages[stage] = value
            if value then
                stages.source[stage] = source[stage] == "client" and "client" or "seen"
                if source[stage] == "client" then client[stage] = value end
                if computed[stage] then
                    stages.computed = stages.computed or {}
                    stages.computed[stage] = true
                elseif exact and exact[stage] ~= true then
                    stages.approx[stage] = true
                end
                local seen = Num(conflict[stage])
                if seen and source[stage] == "client" then
                    stages.conflict = stages.conflict or {}
                    stages.conflict[stage] = { seen = seen, client = value }
                end
            end
        end
        if type(known.sourceText) == "string" then stages.sourceText = known.sourceText end
    end
    -- „grau ab“ nennt Blizzard selbst (maxTrivialLevel) – genauer als jede Beobachtung und als die Tabelle (Leitlinie
    -- 11: was der Client zur Laufzeit sagt, geht vor). Weicht die Tabelle ab, steht das als Hinweis da.
    if recipe.maxTrivial and recipe.maxTrivial > 0 then
        if client.gray and client.gray ~= recipe.maxTrivial then
            stages.conflict = stages.conflict or {}
            local c = stages.conflict.gray or { client = client.gray }
            c.live = recipe.maxTrivial
            stages.conflict.gray = c
        end
        stages.gray, stages.approx.gray, stages.source.gray = recipe.maxTrivial, nil, "live"
        -- gerechnetes Grün aus der Tabelle stimmt nur mit deren Grau – mit dem Wert des Fensters neu rechnen
        if stages.computed and stages.computed.green then stages.green, stages.computed = nil, nil end
    end
    -- „grün ab“ berechnet: abgerundete Mitte zwischen „gelb ab“ und „grau ab“. Regel der Client-Tabelle
    -- SkillLineAbility (gelb ab = TrivialSkillLineRankLow, grau ab = TrivialSkillLineRankHigh), Stichprobe auf
    -- wago.tools für Build 1.60.1.70938 am 15.11.2026: 3275 Erste Hilfe 30/60, 2538 Kochen 45/85, 2330 Alchemie
    -- 55/95, 2963 Schneiderei 25/50 – die Mitte ergibt die bekannten Grün-Werte 45, 65, 75, 37. Nur wenn gelb genau
    -- und grau genau bekannt sind und keine genaue Beobachtung für grün vorliegt; gekennzeichnet als computed.
    local y, g = stages.yellow, stages.gray
    if y and g and not stages.approx.yellow and not stages.approx.gray and g > y
        and (not stages.green or stages.approx.green) then
        stages.green, stages.approx.green = math.floor((y + g) / 2), nil
        stages.computed = { green = true }
        stages.source.green = (stages.source.yellow == "client" and stages.source.gray ~= "seen") and "client" or "seen"
    end
    -- Nicht gelernt meldet der Client keine echte Farbe (Probe 10, Station J3) – dann keine „Farbe jetzt“; was es
    -- gelernt wäre, rechnet Data.StageAt aus den Grenzen.
    if recipe.live and recipe.learned ~= false then
        stages.current = recipe.canSkillUp and DIFFICULTY[recipe.difficulty or -1] or "gray"
    end
    return stages
end

-- Farbe bei einer Fertigkeit aus den Grenzen (Welle 26, F2): für nicht gelernte Rezepte („gelernt wäre es jetzt …“).
-- learnFrom = genaue Lernstufe (Where.Skill mit approx == false: Lehrer, Rezept-Gegenstand, „lernbar ab“ laut Client).
-- Ohne sie zählt nur ein Orange laut Client-Tabellen als Lernstufe. Ein beobachtetes Orange heißt nur „bei dieser
-- Fertigkeit war es orange“ (höchstens zu hoch, wie in Where.Skill) und taugt nicht als Grenze.
-- Unter der Lernstufe "low"; unter „gelb ab“ ohne genaue Lernstufe nil (ob schon lernbar, ist dann offen);
-- nil auch, solange eine nötige Grenze fehlt oder nur ungefähr bekannt ist.
-- → Farbe | "low" | nil, verwendete Lernstufe | nil
function Data.StageAt(stages, rank, learnFrom)
    rank = Num(rank)
    if type(stages) ~= "table" or not rank then return nil end
    local approx = type(stages.approx) == "table" and stages.approx or EMPTY
    local source = type(stages.source) == "table" and stages.source or EMPTY
    local function At(stage) return not approx[stage] and Num(stages[stage]) or nil end
    local learn = Num(learnFrom)
    if not (learn and learn > 0) then learn = source.orange == "client" and At("orange") or nil end
    if learn and rank < learn then return "low", learn end
    local yellow, green, gray = At("yellow"), At("green"), At("gray")
    if gray and rank >= gray then return "gray", learn end
    if not (yellow and gray) then return nil, learn end
    if green and rank >= green then return "green", learn end
    if rank >= yellow then return (green and "yellow" or nil), learn end
    if learn then return "orange", learn end
    return nil
end

-- Rücksicht (Leitlinie 9, W-58/CRAFT-02): Name des Addons, das Materialkosten, Ergebnis und Gewinn am Rezept schon
-- zeigt (Auctionator; ezCore prüft nur „läuft es?“, nie dessen Einstellungen). nil, wenn keins läuft oder der
-- Schalter „costsBeside“ (auch daneben zeigen) an ist; mit any = true unabhängig vom Schalter.
function Data.CraftCostOther(any)
    local label = ns.OtherFor("craftCost")
    if type(label) ~= "string" then return nil end
    if not any and ns.Enabled("costsBeside") then return nil end
    return label
end

---------------------------------------------------------------------------
-- Wer kann es herstellen
---------------------------------------------------------------------------

-- Liste von charKeys, die das Rezept kennen, oder nil, solange das Item-Wissen das nicht weiß.
-- Kennt der aktuelle Charakter es laut offenem Fenster, steht er immer vorn.
function Data.Crafters(recipe)
    if not recipe then return nil end
    local fn = KnowledgeFn("Crafters")
    local list = fn and Plain(Call(fn, recipe.recipeID))
    if type(list) ~= "table" then
        return recipe.learned and { Core.charKey } or nil
    end
    local out, seen = {}, {}
    if recipe.learned and Core.charKey then
        out[1], seen[Core.charKey] = Core.charKey, true
    end
    for _, key in ipairs(list) do
        if type(key) == "string" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    return out
end

-- Name eines Twinks in Klassenfarbe, der aktuelle Charakter als „du“.
function Data.CharLabel(key)
    if key == Core.charKey then return L.YOU end
    return Core.CharName(Core.Char(key), key)
end

function Data.CrafterNames(list)
    local names = {}
    for _, key in ipairs(list or EMPTY) do names[#names + 1] = Data.CharLabel(key) end
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Rezept und Zutaten zu einem Gegenstand (Item-Tooltip)
---------------------------------------------------------------------------

-- Berufsname in der Spielsprache zum Schlüssel des Rezept-Wissens (z. B. "alchemy" → „Alchemie“).
function Data.ProfessionLabel(key)
    local name = key and Call(KnowledgeFn("ProfessionName"), key)
    return type(name) == "string" and name ~= "" and name or nil
end

-- recipeID und Eintrag des Rezept-Wissens, das den Gegenstand herstellt (jedes gesehene, auch nicht gelernte).
function Data.RecipeIDForItem(itemID)
    local recipeID, rec = Call(KnowledgeFn("RecipeFor"), Num(itemID))
    return Num(recipeID), rec
end

-- Dieses Rezept wie Data.Recipe, dazu profession: live aus Blizzards Berufe-API, wenn sie es mit Zutaten kennt,
-- sonst aus ezCores Rezept-Wissen. productSource: woher die Zuordnung Rezept » Gegenstand stammt, wenn nicht vom
-- Client – "atlasloot", wenn ezCore das Produkt eines gesehenen Rezepts ohne Produkt-ID laut AtlasLoot zugeordnet hat
-- (Knowledge.RecipeFor, nur für die Sitzung; CRAFT-06). Die Zeile nennt dann ihre Quelle (Leitlinie 11).
function Data.RecipeForItem(itemID)
    local recipeID, rec = Data.RecipeIDForItem(itemID)
    if not recipeID then return nil end
    local recipe = Data.Recipe(recipeID)   -- der Rückfall auf das Rezept-Wissen steckt dort
    if not recipe then return nil end
    rec = type(rec) == "table" and rec or EMPTY
    recipe.profession = recipe.profession or rec.p
    recipe.product = recipe.product or Num(itemID)
    recipe.productSource = rec.os == "atlasloot" and "atlasloot" or nil
    return recipe
end

-- Rezept-ID zu einem Berufszauber (Datenbank eines Addons nennt den Zauber): das gesehene Rezept dieses Zaubers
-- (Knowledge.RecipeForSpell), sonst der Zauber selbst – bei Blizzards Berufen ist die Rezept-ID die Zauber-ID.
function Data.RecipeIDForSpell(spellID)
    spellID = Num(spellID)
    if not spellID then return nil end
    return Num((Call(KnowledgeFn("RecipeForSpell"), spellID))) or spellID
end

-- Quellenvermerk für eine Zuordnung, die nicht vom Client stammt („laut AtlasLoot“; Wortlaut von ezCore,
-- Knowledge.SourceText) oder nil.
function Data.ProductSourceText(source)
    if source ~= "atlasloot" then return nil end
    local text = Plain(Call(KnowledgeFn("SourceText"), source))
    if type(text) == "string" and text ~= "" then return text end
    return L.SOURCES_ACCORDING:format("AtlasLoot")      -- ezCores Text (Rückfall über ns.L; CRAFT-04)
end

-- Wofür der Gegenstand Zutat ist: { { recipeID, name, count, product } } nach Name (ezCores Reihenfolge).
function Data.RecipesUsing(itemID)
    local list = Call(KnowledgeFn("RecipesUsing"), Num(itemID))
    local out = {}
    for _, e in ipairs(type(list) == "table" and list or EMPTY) do
        local rec = type(e) == "table" and type(e.recipe) == "table" and e.recipe or EMPTY
        local recipeID = type(e) == "table" and e.recipeID or nil
        out[#out + 1] = { recipeID = recipeID, count = Num(e.count) or 1, product = rec.o,
            name = rec.n or (rec.o and Data.ItemName(rec.o)) or ("#" .. tostring(recipeID)) }
    end
    return out
end

-- Handwerksware laut Item-Wissen (Blizzards Kennzeichen oder Warenart), auch wenn noch kein Rezept gesehen ist.
function Data.IsTradeGood(itemID)
    local facts = Call(KnowledgeFn("Get"), Num(itemID))
    return type(facts) == "table" and facts.reagentFor ~= nil
end

---------------------------------------------------------------------------
-- Rezepte aus der Datenbank eines installierten Addons (Regel „Datenquellen“ des Nutzers, 13.11.2026: zuerst der
-- Client, dann die Datenbank eines installierten Addons, dann selbst Gesammeltes; jede Angabe nennt ihre Quelle).
-- Gefragt wird ezCores Brücke Core.Sources (z. B. AtlasLoot) – nur zur Laufzeit, nichts wird kopiert. Fehlt
-- die Brücke (oder eine ihrer Abfragen), liefern diese Funktionen nil bzw. leere Listen.
--   erwartet: Core.Sources.RecipeFor(itemID)    → { recipeID | spellID, name, profession, reagents, source } oder nil
--             Core.Sources.RecipesUsing(itemID) → ezCores Form, beschrieben an Data.SourceRecipesUsing
--   verstanden wird auch die Form des Rezept-Wissens (recipeID, { n, p, o, r, source }); reagents als Liste
--   { { itemID, count } } oder als Karte { [itemID] = Anzahl }; source ist der Anzeigename der Quelle („AtlasLoot“).
---------------------------------------------------------------------------

local function SourcesFn(name)
    local S = Core.Sources
    local fn = type(S) == "table" and S[name]
    return type(fn) == "function" and fn or nil
end

function Data.HasSources() return SourcesFn("RecipeFor") ~= nil end

-- Zutaten in ezCrafts Form { { itemID, count } }, nach itemID.
local function ReagentList(raw)
    local out = {}
    for key, value in pairs(type(raw) == "table" and raw or EMPTY) do
        if type(value) == "table" then
            local itemID = Num(value.itemID) or Num(value.id) or Num(value[1])
            if itemID then out[#out + 1] = { itemID = itemID, count = Num(value.count) or Num(value.n) or Num(value[2]) or 1 } end
        elseif Num(key) and Num(value) then
            out[#out + 1] = { itemID = Num(key), count = Num(value) }
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

local function SourceLabel(rec)
    for _, field in ipairs({ "source", "label", "src" }) do
        local text = Plain(rec[field])
        if type(text) == "string" and text ~= "" then return text end
    end
    return L.SOURCE_DATABASE
end

-- Quellenvermerk einer Antwort der Brücke: ezCores Wortlaut (Core.Sources.Label – „laut AtlasLoot“, für die eigene
-- Datenbank „bei dir“ statt „laut bei dir“; CRAFT-04, W-15), ohne ihn (ältere Brücke) „laut <Quelle>“.
function Data.SourceNote(rec)
    local label = SourcesFn("Label")
    if label and type(rec) == "table" and type(rec.source) == "string" then
        local text = Plain(Call(label, { source = rec.source, sourceKey = Plain(rec.sourceKey) }))
        if type(text) == "string" and text ~= "" then return text end
    end
    return L.SOURCES_ACCORDING:format(type(rec) == "table" and SourceLabel(rec) or L.SOURCE_DATABASE)
end

-- Fertigkeit laut Datenbank: { a, b, c } nur mit echten Schwellen; unbekannt, wenn die Quelle keine nennt (bei
-- Forever-Rezepten laut AtlasLoot der Regelfall; ezCores DG-50 – eine 0 heißt „unbekannt“, nie „ab 0“).
-- → skill | nil, unbekannt (true) | nil – beides nil, wenn die Quelle gar nichts zur Fertigkeit sagt.
local function SourceSkill(rec)
    local raw = Plain(rec.skill)
    if type(raw) == "table" then
        local skill = {}
        for i = 1, #raw do
            local value = Num(Plain(raw[i]))
            if not value or value <= 0 then return nil, true end
            skill[i] = value
        end
        if #skill > 0 then return skill, nil end
        return nil, true
    end
    if Plain(rec.skillUnknown) == true then return nil, true end
    return nil, nil
end

-- Berufsname: Schlüssel des Rezept-Wissens („alchemy“) oder schon der Name aus der fremden Datenbank.
local function SourceProfession(value)
    value = Plain(value)
    if type(value) ~= "string" or value == "" then return nil end
    return Data.ProfessionLabel(value) or value
end

-- Wie der Gegenstand laut Datenbank hergestellt wird: Rezept wie Data.Recipe, dazu source („AtlasLoot“) und
-- professionLabel. nil ohne Brücke, ohne Treffer oder ohne Zutaten.
function Data.SourceRecipeForItem(itemID)
    local fn = SourcesFn("RecipeFor")
    itemID = Num(itemID)
    if not (fn and itemID) then return nil end
    local first, second = Call(fn, itemID)
    first, second = Plain(first), Plain(second)
    local rec = type(first) == "table" and first or (type(second) == "table" and second or nil)
    if not rec then return nil end
    local reagents = ReagentList(rec.reagents or rec.r)
    if #reagents == 0 then return nil end
    local name = Plain(rec.name) or Plain(rec.n)
    -- ezCores Brücke nennt den Berufszauber als spell (CRAFT-12): über ihn findet „Können: …“ die eigenen Charaktere
    local spell = Num(rec.spell) or Num(rec.spellID)
    local skill, skillUnknown = SourceSkill(rec)
    local source = SourceLabel(rec)
    return {
        recipeID = Num(rec.recipeID) or (spell and Data.RecipeIDForSpell(spell)) or Num(rec.id)
            or (type(first) ~= "table" and Num(first)) or nil,
        spell = spell,
        name = type(name) == "string" and name ~= "" and name or Data.ItemName(itemID),
        product = itemID,
        icon = Data.ItemIcon(itemID),
        professionLabel = SourceProfession(rec.profession or rec.p),
        reagents = reagents,
        source = source,
        sourceNote = Data.SourceNote({ source = source, sourceKey = rec.sourceKey }),
        skill = skill,
        skillUnknown = skillUnknown,
    }
end

-- Name eines Rezepts laut Datenbank. ezCores Brücke nennt den Zaubernamen; kennt der Client ihn nicht, setzt sie den
-- Berufsnamen oder „#<Zauber>“ ein – „Zutat für: Alchemie (1×)“ wäre falsch, dann lieber der Name des Produkts.
-- Hat der Client auch den noch nicht geladen, wartet der Eintrag (nil, true), statt „#<Produkt>“ zu zeigen;
-- Core.ItemNameByID stößt das Laden an, beim nächsten Überfahren steht der Name da.
local function UsingName(rec, product)
    local name = Plain(rec.name) or Plain(rec.n)
    if type(name) ~= "string" or name == "" or name:sub(1, 1) == "#" or name == Plain(rec.profession) then
        if product then
            local itemName = Core.ItemNameByID(product)
            if type(itemName) ~= "string" or itemName == "" then return nil, true end
            name = itemName
        end
    end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Wofür der Gegenstand laut Datenbank Zutat ist: { { recipeID, spell, name, count, product, source, sourceNote } }
-- nach Name; dazu pending (wie viele Einträge warten, weil der Client den Namen noch lädt – nicht in der Liste) und
-- pendingNote (ihr Quellenvermerk). ezCores Form (Core.Sources.RecipesUsing, EC-97): { { recipeID, spell, name, count,
-- product, profession, source, sourceKey } … }; verstanden wird auch die Form des Rezept-Wissens
-- ({ recipeID, recipe = { n, o }, count }).
function Data.SourceRecipesUsing(itemID)
    local fn = SourcesFn("RecipesUsing")
    local list = fn and Plain(Call(fn, Num(itemID)))
    local out, pending, pendingFrom = {}, 0, nil
    for _, e in ipairs(type(list) == "table" and list or EMPTY) do
        if type(e) == "table" then
            local rec = type(e.recipe) == "table" and e.recipe or e
            local product = Num(rec.product) or Num(rec.o)
            local name, waiting = UsingName(rec, product)
            if waiting then
                pending = pending + 1
                pendingFrom = pendingFrom or (type(e.source) == "string" and e or rec)
            elseif name then
                local from = type(e.source) == "string" and e or rec
                local source = SourceLabel(from)
                local spell = Num(e.spell) or Num(rec.spell) or Num(rec.spellID)
                out[#out + 1] = { recipeID = Num(e.recipeID) or Num(rec.recipeID) or spell, spell = spell, name = name,
                    count = Num(e.count) or 1, product = product, source = source,
                    sourceNote = Data.SourceNote({ source = source, sourceKey = from.sourceKey }) }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    out.pending = pending
    if pendingFrom then
        out.pendingNote = Data.SourceNote({ source = SourceLabel(pendingFrom), sourceKey = pendingFrom.sourceKey })
    end
    return out
end

-- Läuft ein Addon mit Rezept-Datenbank (AtlasLoot)? → geladen?, Anzeigename (ezCores Erkennung, Core.OtherAddOn).
function Data.RecipeDatabase()
    if type(Core.OtherAddOn) ~= "function" then return false, nil end
    local loaded, label = Call(Core.OtherAddOn, "AtlasLoot")
    return loaded == true, type(label) == "string" and label or nil
end

-- Läuft die Rezept-Datenbank, antwortet aber nicht wie erwartet (ezCores Brücke meldet für AtlasLoot den Stand
-- „shape“ = falsche Form oder „error“ = Fehler beim Lesen)? → ezCores Satz dazu („AtlasLoot antwortet nicht wie
-- erwartet“, Core.Sources.Hint) | nil, wenn die Quelle in Ordnung ist, nicht läuft oder ezCore die Auskunft nicht hat.
-- Der Stand gilt für die letzte Abfrage – also nach Data.SourceRecipeForItem fragen.
local SOURCE_BROKEN = { shape = true, error = true }

function Data.SourceProblem()
    local status, hint = SourcesFn("Status"), SourcesFn("Hint")
    if not (status and hint) then return nil end
    if not SOURCE_BROKEN[Plain(Call(status, "AtlasLoot")) or ""] then return nil end
    local text = Plain(Call(hint, "recipeFor"))
    return type(text) == "string" and text ~= "" and text or nil
end

-- Wird der Gegenstand seiner Art nach üblicherweise hergestellt (laut Client: Trank, Elixier, Fläschchen, Verband
-- oder Tasche)? Nur für den Hinweis „noch nicht gesehen“, wenn weder Rezept-Wissen noch Datenbank etwas sagen.
local CRAFTED_CONSUMABLES = { [1] = true, [2] = true, [3] = true, [7] = true }   -- Trank, Elixier, Fläschchen, Verband

function Data.MaybeCrafted(itemID)
    local classID, subClassID = Call(Core.ItemClass, Num(itemID))
    if not classID then return false end
    local classes = Core.ITEM_CLASS or EMPTY
    if classID == classes.Container then return true end
    return classID == classes.Consumable and CRAFTED_CONSUMABLES[subClassID or -1] == true
end

---------------------------------------------------------------------------
-- Fehlende Rezepte des offenen Berufs
---------------------------------------------------------------------------

-- Quelle eines nicht erlernten Rezepts: Blizzards Text (Händler, Lehrer, Beute …), sonst das Item-Wissen.
function Data.SourceText(recipeID)
    local text = C_TradeSkillUI and Plain(Call(C_TradeSkillUI.GetRecipeSourceText, recipeID))
    if type(text) == "string" and text ~= "" then return text end
    local fn = KnowledgeFn("RecipeSource")
    text = fn and Plain(Call(fn, recipeID))
    return type(text) == "string" and text ~= "" and text or nil
end

-- Die Liste bleibt gemerkt, bis das Berufefenster sich meldet (öffnen, auffrischen, schließen, Rezept gelernt) oder
-- der Knopf „Neu lesen“ gedrückt wird (V-145: vorher bei jedem Auffrischen der Ansicht alle Rezepte neu gelesen).
local missingCache

function Data.InvalidateMissing() missingCache = nil end

-- Liste { recipeID, name, icon, source } und Anzahl aller Rezepte des Berufs. Die Liste nur lesen, nicht verändern.
function Data.MissingRecipes()
    local api = C_TradeSkillUI
    if not api then return {}, 0 end
    if missingCache then return missingCache.list, missingCache.total end
    local ids = api and Plain(Call(api.GetAllRecipeIDs))
    local list, total = {}, 0
    if type(ids) ~= "table" then return list, 0 end
    for _, id in ipairs(ids) do
        id = Num(id)
        local info = id and Plain(Call(api.GetRecipeInfo, id))
        if type(info) == "table" and not info.isDummyRecipe then
            total = total + 1
            if info.learned == false then
                list[#list + 1] = { recipeID = id, name = Plain(info.name) or ("#" .. id), icon = Plain(info.icon),
                    source = Data.SourceText(id) }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if total > 0 then missingCache = { list = list, total = total } end   -- ein leeres Fenster nicht merken
    return list, total
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED",
    "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    ns.On(event, Data.InvalidateMissing)
end

-- Erste Zeile einer Quelle ohne Farbcodes (für die Liste; der Tooltip zeigt alles).
function Data.SourceFirstLine(text)
    if type(text) ~= "string" then return nil end
    local first = text:match("^[^\n]+") or text
    return Core.Trim(Core.StripColors(first))
end

---------------------------------------------------------------------------
-- Berufs-Abklingzeiten aller Twinks (ezCore.Professions)
---------------------------------------------------------------------------

local function ProfessionsLib()
    local P = Core.Professions
    return type(P) == "table" and type(P.AllCooldowns) == "function" and P or nil
end

function Data.HasCooldowns() return ProfessionsLib() ~= nil end

-- Uhrzeit (gespeicherte Zeitpunkte der Abklingzeiten): Core.Now, eine Stelle für alle Module (W-14)
local Now = Core.Now

-- Abklingzeiten { { char, id, name, readyAt, left, ready, group, ids, count } … }, früheste zuerst; left frisch
-- gerechnet. Ohne withReady nur laufende. withReady: auch fertige (ready = true, left = 0) – ezCore merkt sie, bis die
-- Abklingzeit wieder läuft (seit Welle 23b auch beim gespielten Charakter); was während des Zeigens abläuft, wird hier
-- ebenfalls „bereit“. merged (Welle 23, A6): geteilte Abklingzeiten (Transmutationen) fasst ezCore je Twink und
-- Gruppe zu einem Eintrag zusammen (Professions.AllCooldowns(withReady, true): ids, count; der früheste zählt).
function Data.Cooldowns(withReady, merged)
    local P = ProfessionsLib()
    local list = P and Plain(Call(P.AllCooldowns, withReady == true, merged == true))
    local out, now = {}, Now()
    for _, e in ipairs(type(list) == "table" and list or EMPTY) do
        local readyAt = type(e) == "table" and Num(e.readyAt)
        local item
        if readyAt and readyAt > now then
            item = { char = e.char, id = e.id, name = Plain(e.name), readyAt = readyAt, left = readyAt - now }
        elseif readyAt and withReady then
            item = { char = e.char, id = e.id, name = Plain(e.name), readyAt = readyAt, left = 0, ready = true }
        end
        if item then
            item.group = type(e.group) == "string" and e.group or nil
            item.ids = type(e.ids) == "table" and e.ids or { e.id }
            item.count = Num(e.count) or 1
            out[#out + 1] = item
        end
    end
    return out
end

-- Fertige Abklingzeiten aller Twinks („Transmutation bei Mira bereit“), am längsten fertige zuerst.
function Data.ReadyCooldowns()
    local out = {}
    for _, e in ipairs(Data.Cooldowns(true)) do
        if e.ready then out[#out + 1] = e end
    end
    return out
end

-- Nach Twink gruppiert: { { key, label, list } … } – du zuerst, dann wer am frühesten fertig ist. Geteilte
-- Abklingzeiten stehen einmal da (ezCores Gruppe, Welle 23 A6; Name über Data.CooldownLabel).
function Data.CooldownsByChar()
    local groups, byKey = {}, {}
    for _, e in ipairs(Data.Cooldowns(false, true)) do
        local key = e.char or Core.charKey or "?"
        local group = byKey[key]
        if not group then
            group = { key = key, label = Data.CharLabel(key), list = {} }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.list[#group.list + 1] = e
    end
    table.sort(groups, function(a, b)
        if (a.key == Core.charKey) ~= (b.key == Core.charKey) then return a.key == Core.charKey end
        return a.list[1].readyAt < b.list[1].readyAt
    end)
    return groups
end

-- Name und Symbol eines Eintrags: Zauber/Rezept (Zahl) oder Gegenstand („i<itemID>“).
local function CooldownItemID(id)
    return type(id) == "string" and tonumber(id:match("^i(%d+)$")) or nil
end

function Data.CooldownName(e)
    if type(e.name) == "string" and e.name ~= "" then return e.name end
    local itemID = CooldownItemID(e.id)
    if itemID then return Data.ItemName(itemID) end
    local name = type(e.id) == "number" and Core.SpellName(e.id)     -- ezCore: C_Spell zuerst, gesperrt → nil
    return type(name) == "string" and name or ("#" .. tostring(e.id))
end

-- Gruppe einer Abklingzeit laut ezCore (Spells.PROF_COOLDOWNS bzw. PROF_COOLDOWN_ITEMS: Die Transmutationen teilen
-- sich eine) | nil. Seit Welle 23 (A6) nennt ezCore sie am Eintrag (group) bzw. über Professions.CooldownGroup.
function Data.CooldownGroup(e)
    if type(e) ~= "table" then return nil end
    if type(e.group) == "string" then return e.group end
    local P = Core.Professions
    local group = type(P) == "table" and Plain(Call(P.CooldownGroup, e.id)) or nil
    return type(group) == "string" and group or nil
end

-- Zeile einer fertigen Abklingzeit ohne „bereit“: „Transmutation bei Mira“, beim gespielten Charakter „… bei
-- dir“. Eine Stelle für den Seitenreiter „Abklingzeiten“ (Block „Bereit“) und die Meldung auf ezPanels Leiste.
function Data.ReadyCooldownLine(e, name)
    name = name or Data.CooldownName(e)
    local char = e.char or Core.charKey
    if char == Core.charKey then return L.CD_READY_LINE_ME:format(name) end
    return L.CD_READY_LINE:format(name, Data.CharLabel(char))
end

-- Name eines Eintrags für die Anzeige: Stehen mehrere Zauber einer Gruppe dahinter (count > 1, ezCores
-- Zusammenfassung), heißt er wie die Gruppe („Transmutation“), sonst wie der Zauber.
local GROUP_TEXT = { transmute = "CD_GROUP_TRANSMUTE" }

function Data.CooldownLabel(e)
    if type(e) == "table" and (Num(e.count) or 1) > 1 then
        local group = Data.CooldownGroup(e)
        local text = group and GROUP_TEXT[group] and L[GROUP_TEXT[group]]
        if type(text) == "string" then return text end
    end
    return Data.CooldownName(e)
end

-- Fertige Abklingzeiten, geteilte zusammengefasst: Kennt ein Twink mehrere Zauber derselben Gruppe (drei
-- Transmutationen, eine Abklingzeit), ist das ein Eintrag. Seit Welle 23 (A6) fasst ezCore zusammen
-- (Professions.AllCooldowns(withReady, merged)); vorher tat es diese Funktion selbst.
-- → { { entry = der am längsten fertige, name, count = Zahl der Zauber } … }, am längsten fertige zuerst.
function Data.ReadyCooldownsMerged()
    local out = {}
    for _, e in ipairs(Data.Cooldowns(true, true)) do
        if e.ready then out[#out + 1] = { entry = e, name = Data.CooldownLabel(e), count = e.count or 1 } end
    end
    return out
end

function Data.CooldownIcon(id)
    local itemID = CooldownItemID(id)
    if itemID then return Data.ItemIcon(itemID) end
    if type(id) ~= "number" then return nil end
    local icon = Plain(Call(Core.Spells and Core.Spells.Icon, id))     -- Zauber-Symbol aus ezCores Zauber-Wissen
    return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

-- Uhrzeit, zu der eine Abklingzeit endet: heute „18:40“, sonst mit Datum.
function Data.ReadyAtText(readyAt)
    if not (date and readyAt) then return "?" end
    local fmt = date("%Y%m%d", readyAt) == date("%Y%m%d", Now()) and L.CD_TIME_FMT or L.CD_DATE_FMT
    return date(fmt, readyAt)
end

-- Abklingzeiten jetzt neu lesen (Knopf „Neu lesen“): bekannte Zauber und Gegenstände, dazu das offene Berufefenster.
function Data.ScanCooldowns()
    local P = ProfessionsLib()
    if not P then return false end
    if Core.InCombat() then
        Core.CombatNotice(ns, L.CD_SCAN_WHAT)   -- ein Satz zur Kampfsperre für alle Module (T18-1)
        return false
    end
    if type(P.ScanCooldowns) == "function" then Call(P.ScanCooldowns) end
    if type(P.ScanTradeSkill) == "function" then Call(P.ScanTradeSkill) end
    return true
end

---------------------------------------------------------------------------
-- Fundorte (ezCore.Gathering: deine eigenen Ernten „bei dir“ zuerst, angebundene Sammel-Addons mit Quelle „laut …“)
---------------------------------------------------------------------------
--[[
    SAM-24 und SAM-25 (Welle 15, Ablösung von GatherMate): Fundorte kommen aus ezCores Entdecker-Datenbank – deinen
    eigenen Ernten (Core.Finds, Core.Drops) –, ein angebundenes Sammel-Addon steht nur daneben („laut …“, über
    Core.Gathering.Line). Zur Karte führt ezMap (ezCore.API("ezMap").ShowGather): Es öffnet Blizzards Weltkarte in der
    besten Zone mit gesetztem Filter und markiert den nächsten Punkt. Ohne ezMap bleiben die Zahlen sichtbar, der Knopf
    ist ausgegraut und sagt, warum.
      Data.Gather(itemID)          → { here, text, line } oder nil: here = Fundorte in deiner Zone, text = Gebiete
                                     (ezCores Text), line = ganze Zeile „Fundorte: … (bei dir, n Punkte; laut …)“
      Data.CanGather(itemID)       → true, wenn es sich sammeln lässt (Kraut, Erz) oder irgendwo Fundorte hat
      Data.OwnFinds(itemID)        → { { mapID, name, points, count } … }, Summe der Punkte (nur eigene Ernten)
      Data.GatherState(itemID)     → "ok" | "nomap" (ohne ezMap) | "none" (noch kein eigener Fundort)
      Data.ShowGather(itemID, karte) → wie ShowGather, dazu eine Chatzeile mit dem Ergebnis bzw. dem Grund
      Data.GatherItems(art, rang)  → Rohstoffe deiner Ernten einer Art (herb, ore, fish) für das Menü im Berufsbuch:
                                     { { itemID, name, need, needHow, above, points, zones, finds } … } oder nil
                                     (ezCore ohne Core.Gathering.ItemsOf)
      Data.SkinSources(itemID), Data.SkinLine(itemID), Data.SkinItems() → Kürschner-Beute je Gegner aus der
                                     Beute-Zählung (Art „skin“, DG-03)
    Gelesen wird nur über ezCores Fassaden (Core.Gathering mit „Rohstoffe je Art“ Gathering.ItemsOf, Core.Finds,
    Core.Drops, Core.Places, Core.DB.Text für Namen) – seit Welle 23 (A5) liest ezCraft keine Schlüssel der Datenbank
    mehr selbst.
]]

local function GatheringLib()
    local G = Core.Gathering
    return type(G) == "table" and type(G.Text) == "function" and type(G.InZone) == "function" and G or nil
end

function Data.HasGathering() return GatheringLib() ~= nil end

-- Namen der Quellen, die gerade Fundorte liefern („bei dir“ für deine eigenen Ernten; leer = noch keine).
function Data.GatherSources()
    local G = GatheringLib()
    local list = G and type(G.Active) == "function" and Plain(Call(G.Active))
    return type(list) == "table" and list or {}
end

-- Woher Fundorte kommen, als Satz für Status und Einstellungen – ohne fremdes Addon als Voraussetzung.
function Data.GatherSourcesText()
    local sources = Data.GatherSources()
    if #sources > 0 then return L.GATHER_SOURCES:format(table.concat(sources, ", ")) end
    return L.GATHER_SOURCES_NONE
end

-- Deine Zone: die Elternkarte vom Typ Zone der tiefsten Karte (Fundorte liegen auf Zonenkarten) → Zone, tiefste Karte
function Data.PlayerZone()
    local api = rawget(_G, "C_Map")
    local best = type(api) == "table" and Num(Plain(Call(api.GetBestMapForUnit, "player"))) or nil
    if not best then return nil end
    local M = Core.Map
    local zone = type(M) == "table" and type(M.Parent) == "function" and Num((Call(M.Parent, best, "Zone"))) or nil
    return zone or best, best
end

-- { here = Fundorte in deiner Zone, text = „Westfall, Wald von Elwynn (+2)“, line = ganze Zeile mit Quellen } oder nil.
function Data.Gather(itemID)
    local G = GatheringLib()
    if not (G and itemID) then return nil end
    local zone, best = Data.PlayerZone()
    local here = zone and Num(Plain(Call(G.InZone, itemID, zone))) or 0
    if here <= 0 and best and best ~= zone then here = Num(Plain(Call(G.InZone, itemID, best))) or 0 end
    if here <= 0 and not zone then here = Num(Plain(Call(G.InZone, itemID))) or 0 end
    local text = Plain(Call(G.Text, itemID))
    if type(text) ~= "string" then text = nil end
    local line = Plain(Call(G.Line, itemID))
    if type(line) ~= "string" then line = nil end
    if here <= 0 and not text then return nil end
    return { here = here, text = text, line = line }
end

-- Eigene Fundorte eines Materials je Zone (Core.Finds.Of: Ernten und Punkte), meiste Punkte zuerst. Gemerkt je
-- Gegenstand für OWN_SECONDS (das Seitenteil fragt bei jedem Neuzeichnen je fehlendem Material); neue Ernten,
-- Vergessen oder Zusammenlegen (GATHERING_CHANGED) verwerfen alles.
Data.OWN_SECONDS = 30
local ownCache = {}
function Data.ForgetFinds() ownCache = {} end
Core.Listen("GATHERING_CHANGED", function() Data.ForgetFinds() end, "ezCraft")

function Data.OwnFinds(itemID)
    local now = Core.Uptime() or 0
    local hit = itemID and ownCache[itemID]
    if hit and now - hit.t < Data.OWN_SECONDS then return hit.list, hit.total end
    local F = Core.Finds
    local list = itemID and type(F) == "table" and Plain(Call(F.Of, itemID)) or nil
    local out, total = {}, 0
    for _, e in ipairs(type(list) == "table" and list or EMPTY) do
        local mapID, points, count = Num(e.mapID), Num(e.points) or 0, Num(e.count) or 0
        if mapID and (points > 0 or count > 0) then
            out[#out + 1] = { mapID = mapID, name = Core.MapName(mapID), points = points, count = count }
            total = total + points
        end
    end
    table.sort(out, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.count ~= b.count then return a.count > b.count end
        return a.mapID < b.mapID
    end)
    if itemID then ownCache[itemID] = { t = now, list = out, total = total } end
    return out, total
end

-- Lässt es sich sammeln? Kraut oder Erz laut Client (ezCores Gathering.Gatherable) oder mit bekannten Fundorten.
function Data.CanGather(itemID)
    if not itemID then return false end
    local G = GatheringLib()
    if not G then return false end
    if Plain(Call(G.Gatherable, itemID)) == true then return true end
    return Data.Gather(itemID) ~= nil or #(Data.OwnFinds(itemID)) > 0
end

-- Schnittstelle von ezMap, die die Weltkarte mit Fundorten öffnet (SAM-14), oder nil
function Data.MapAPI()
    local api = Core.API("ezMap")
    local fn = type(api) == "table" and api.ShowGather or nil
    return type(fn) == "function" and fn or nil
end

function Data.GatherState(itemID)
    if not Data.MapAPI() then return "nomap" end
    if #(Data.OwnFinds(itemID)) == 0 then return "none" end
    return "ok"
end

-- „Nächste Fundorte“: Weltkarte über ezMap öffnen (mapID: diese Zone, sonst die beste) und im Chat sagen, was
-- geschah. → true, Auskunft von ezMap | false, Grund
function Data.ShowGather(itemID, mapID)
    local show = Data.MapAPI()
    local name = Data.ItemName(itemID)
    if not show then
        ns.Print(L.GATHER_GO_NOMAP)
        return false, "noezmap"
    end
    local ok, done, info = pcall(show, { item = itemID, map = mapID })
    if not ok then
        ns.Error(done, "ezMap.ShowGather")
        return false, "error"
    end
    if done ~= true then
        local why = type(info) == "string" and L["GATHER_GO_WHY_" .. info] or nil
        ns.Print(why and why:format(name) or L.GATHER_GO_FAIL:format(name, tostring(info)))
        return false, info
    end
    info = type(info) == "table" and info or {}
    local zone = Num(info.map) and Core.MapName(info.map) or "?"
    local count = Core.Plural(Num(info.count) or 0, Core.L.GATHER_SPOTS_ONE, Core.L.GATHER_SPOTS_MANY)
    -- Ein Satz je Lage: geöffnet oder (im Kampf) erst danach; „markiert“ nur, wenn ezMap die Markierung setzen
    -- konnte (ezMap setzt sie auch im Kampf sofort), sonst sagt ein eigener Satz, dass Blizzard sie nicht erlaubt.
    if info.later then
        -- im Kampf: ezCores Satz „… kommt gleich nach dem Kampf.“ (T18-1), „markiert“ als eigene Zeile
        Core.CombatNotice(ns, L.GATHER_GO_MAP:format(name, zone, count), "later")
        if info.marked ~= false then ns.Print(L.GATHER_GO_MARKED) end
    else
        local text = L.GATHER_GO_OK:format(name, zone, count)
        if info.marked ~= false then text = text .. " " .. L.GATHER_GO_MARKED end
        ns.Print(text)
    end
    if info.marked == false then ns.Print(L.GATHER_GO_NOMARK) end
    if type(info.other) == "string" and info.other ~= "" then ns.Print(L.GATHER_GO_OTHER:format(info.other)) end
    return true, info
end

Data.MENU_MAX = 30       -- so viele Rohstoffe zeigt das Menü im Berufsbuch höchstens
Data.ZONES_MAX = 10      -- so viele Zonen je Rohstoff
Data.GATHER_KINDS = { herb = true, ore = true, fish = true }   -- Arten des Menüs im Berufsbuch (Kürschnern: SkinItems)

-- Rohstoffe je Art aus ezCore (Core.Gathering.ItemsOf, Welle 23c; Welle 23 A5 – vorher las ezCraft die Schlüssel der
-- Datenbank selbst): { { item, kind, harvests, sources, need, needHow } … } oder nil, wenn ezCore die Fassade nicht hat
local function ItemsOf(kind)
    local G = Core.Gathering
    if not (type(G) == "table" and type(G.ItemsOf) == "function") then return nil end
    local list = Plain(Call(G.ItemsOf, kind))
    return type(list) == "table" and list or {}
end

-- Rohstoffe deiner Ernten einer Art, sortiert nach benötigtem Rang (unbekannt zuletzt), dann nach Ernten.
-- rang (dein Rang laut Berufsbuch) markiert, was darüber liegt (above). → Liste, Zahl ohne Obergrenze; nil ohne
-- ezCores Fassade
function Data.GatherItems(kind, rank)
    if not Data.GATHER_KINDS[kind] then return ItemsOf(kind) and {} or nil, 0 end
    local items = ItemsOf(kind)
    if not items then return nil end
    rank = Num(rank)
    local list = {}
    for _, it in ipairs(items) do
        local itemID, finds = Num(it.item), Num(it.harvests) or 0
        if itemID and finds > 0 then
            local e = { itemID = itemID, finds = finds, need = Num(it.need) }
            e.needHow = e.need and Plain(it.needHow) or nil
            e.zones, e.points = Data.OwnFinds(itemID)
            e.name = Data.ItemName(itemID)
            e.above = (rank ~= nil and e.need ~= nil and e.needHow ~= "upto" and e.need > rank) or nil
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        local na, nb = a.need or huge, b.need or huge
        if na ~= nb then return na < nb end
        if a.finds ~= b.finds then return a.finds > b.finds end
        return a.itemID < b.itemID
    end)
    local count = #list
    for i = count, Data.MENU_MAX + 1, -1 do list[i] = nil end
    return list, count
end

-- „ab 75“ (Rang laut Client bzw. aus Erfolg und Fehlschlag gelernt), „spätestens ab 75“ (gelang schon mit 75),
-- „Rang unbekannt“
function Data.NeedText(e)
    if not (e and e.need) then return L.BOOK_NEED_UNKNOWN end
    if e.needHow == "upto" then return L.BOOK_NEED_UPTO:format(e.need) end
    return L.BOOK_NEED:format(e.need)
end

-- „Kupfererz – ab 1 – 37 Fundorte in 3 Zonen“ (Angeln ohne Rang)
function Data.GatherItemLabel(e, kind)
    local spots = Core.Plural(e.points or 0, Core.L.GATHER_SPOTS_ONE, Core.L.GATHER_SPOTS_MANY)
    local zones = Core.Plural(#(e.zones or EMPTY), L.BOOK_ZONES_ONE, L.BOOK_ZONES_MANY)
    if kind == "fish" then return L.BOOK_ITEM_FISH:format(e.name or "?", spots, zones) end
    return L.BOOK_ITEM:format(e.name or "?", Data.NeedText(e), spots, zones)
end

-- Kürschner-Beute (Art „skin“ der Beute-Zählung, DG-03): je Gegner Name, Zone und wie oft der Gegenstand dabei war
function Data.SkinSources(itemID)
    local D, DB, P = Core.Drops, Core.DB, Core.Places
    local list = itemID and type(D) == "table" and Plain(Call(D.SourcesOf, itemID)) or nil
    local out = {}
    for _, src in ipairs(type(list) == "table" and list or EMPTY) do
        local npc = Num(src.id)
        if src.kind == "skin" and npc and (Num(src.f) or 0) > 0 then
            local name = type(DB) == "table" and Plain(Call(DB.Text, "npc", npc)) or nil
            if type(name) ~= "string" or name == "" then name = L.SKIN_NPC:format(npc) end
            local places = type(P) == "table" and Plain(Call(P.Of, "npc", npc)) or nil
            local first = type(places) == "table" and places[1] or nil
            local map = type(first) == "table" and Num(first.map) or nil
            out[#out + 1] = { npc = npc, name = name, zone = map and map > 0 and Core.MapName(map) or nil,
                times = Num(src.f) or 0 }
        end
    end
    table.sort(out, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        return a.npc < b.npc
    end)
    return out
end

Data.SKIN_MAX = 3   -- so viele Gegner nennt die Zeile im Tooltip

-- „Wolf (Wald von Elwynn) 5×“
function Data.SkinEntry(e)
    local who = e.zone and Core.L.GATHER_LOOT_ZONE:format(e.name, e.zone) or e.name
    return who .. " " .. Core.L.GATHER_TIMES:format(e.times)
end

-- „Wolf (Wald von Elwynn) 5×, Bär 2× (+3)“ oder nil
function Data.SkinLine(itemID, max)
    local list = Data.SkinSources(itemID)
    if #list == 0 then return nil end
    max = max or Data.SKIN_MAX
    local parts = {}
    for i = 1, math.min(max, #list) do parts[i] = Data.SkinEntry(list[i]) end
    local text = table.concat(parts, ", ")
    if #list > max then text = text .. " " .. Core.L.GATHER_MORE:format(#list - max) end
    return text
end

-- Alles, was du je gekürschnert hast: { { itemID, name, finds, sources } … }, häufigstes zuerst; nil ohne ezCores
-- Fassade (Core.Gathering.ItemsOf("skin"), Welle 23 A5)
function Data.SkinItems()
    local items = ItemsOf("skin")
    if not items then return nil end
    local list = {}
    for _, it in ipairs(items) do
        local itemID, n = Num(it.item), Num(it.harvests) or 0
        if itemID and n > 0 then list[#list + 1] = { itemID = itemID, name = Data.ItemName(itemID), finds = n } end
    end
    table.sort(list, function(a, b)
        if a.finds ~= b.finds then return a.finds > b.finds end
        return a.itemID < b.itemID
    end)
    local count = #list
    for i = count, Data.MENU_MAX + 1, -1 do list[i] = nil end
    for _, e in ipairs(list) do e.sources = Data.SkinSources(e.itemID) end
    return list, count
end

---------------------------------------------------------------------------
-- Beobachtetes Material (AH-39): ezCraft meldet sein Material bei ezCores Preis-Wissen an
---------------------------------------------------------------------------
-- Was hier steht, zählt in ezCore als „beobachtet“ (Prices.AddWatchProvider): ezAuctions „Meine Preise“ frischt es
-- gezielt auf (Prices.Refresh über Prices.WatchList) – so kommen frische Preise für Materialkosten und Gewinn auch
-- dann, wenn Forever den Komplett-Scan nicht bedient; der Verlauf hält 30 statt 14 Tage. Reihenfolge, wichtigste
-- zuerst: Rezepte der Einkaufsliste, Lieblingsrezepte (Stern in Blizzards Rezeptliste), zuletzt angesehene Rezepte –
-- je Rezept die Zutaten; erst danach die Ergebnisse dieser Rezepte (für den Gewinn). Fehlt der Dienst, geschieht
-- nichts. Gemerkt wird in ezCraftDB.watch = { recent = { recipeID … } (neueste zuerst), favorites = { [recipeID] = true } }.

Data.WATCH_MAX = 200     -- höchstens so viele Gegenstände meldet ezCraft an (wie ezCores Prices.WATCH_MAX)
Data.RECENT_MAX = 20     -- so viele zuletzt angesehene Rezepte merkt ezCraft
Data.WATCH_KEY = "ezCraft.material"

local function WatchDB()
    local db = ns.db and ns.db.watch
    if type(db) ~= "table" then return nil end
    if type(db.recent) ~= "table" then db.recent = {} end
    if type(db.favorites) ~= "table" then db.favorites = {} end
    return db
end

-- Zeigt das offene Berufefenster einen fremden Beruf (Link im Chat, Gilde, Gildenmitglied, NPC-Werkbank)? Die Prüfung
-- gehört ezCore (Professions.IsForeignTradeSkill, SSOT); fehlt sie, gilt das Fenster als eigenes.
local function ForeignWindow()
    local P = Core.Professions
    return P ~= nil and type(P.IsForeignTradeSkill) == "function" and Call(P.IsForeignTradeSkill) == true
end

-- Ein Rezept wurde im Berufefenster gewählt: vorn in die Liste der zuletzt angesehenen; favorite (aus Blizzards
-- Rezept-Info) setzt bzw. löscht den Stern, nil lässt ihn, wie er ist. Ein fremdes Berufefenster (ForeignWindow)
-- zählt nicht: Sein Rezept wird nicht gemerkt, und dein Stern bleibt. → true, wenn gemerkt
function Data.NoteViewed(recipeID, favorite)
    recipeID = Num(recipeID)
    local db = recipeID and WatchDB()
    if not db or ForeignWindow() then return false end
    for i = #db.recent, 1, -1 do
        if db.recent[i] == recipeID then table.remove(db.recent, i) end
    end
    table.insert(db.recent, 1, recipeID)
    for i = #db.recent, Data.RECENT_MAX + 1, -1 do db.recent[i] = nil end
    if favorite == true then db.favorites[recipeID] = true elseif favorite == false then db.favorites[recipeID] = nil end
    return true
end

-- Lieblingsrezepte des offenen Berufs lesen (Feld favorite der Rezept-Info). Nennt der Client das Feld nicht, bleibt
-- alles, wie es ist; ein fremdes Berufefenster (Link, Gilde, Gildenmitglied, NPC-Werkbank) gehört nicht dir und zählt
-- nicht. → Zahl der Sterne
function Data.ScanFavorites()
    local api = C_TradeSkillUI
    local db = WatchDB()
    if not (api and db) or ForeignWindow() then return 0 end
    local ids = Plain(Call(api.GetAllRecipeIDs))
    if type(ids) ~= "table" then return 0 end
    local n = 0
    for _, id in ipairs(ids) do
        id = Num(id)
        local info = id and Plain(Call(api.GetRecipeInfo, id))
        local favorite = nil
        if type(info) == "table" then favorite = Plain(info.favorite) end
        if type(favorite) == "boolean" then
            db.favorites[id] = favorite or nil
            if favorite then n = n + 1 end
        end
    end
    return n
end

-- Rezepte in der Reihenfolge ihres Gewichts, ohne Doppelte: Einkaufsliste, Lieblingsrezepte, zuletzt angesehene.
function Data.WatchRecipes()
    local out, seen = {}, {}
    local function add(id)
        id = Num(id)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    -- Rezepte aller Listen (ezCores Core.Lists, seit dem 21.11.2026)
    for _, list in ipairs(ns.db and Core.Lists and Core.Lists.All() or EMPTY) do
        for _, entry in ipairs(list.items or EMPTY) do add(entry.recipe) end
    end
    local db = WatchDB()
    if db then
        local favorites = {}
        for id, on in pairs(db.favorites) do
            if on == true and Num(id) then favorites[#favorites + 1] = Num(id) end
        end
        table.sort(favorites)
        for _, id in ipairs(favorites) do add(id) end
        for _, id in ipairs(db.recent) do add(id) end
    end
    return out
end

-- Gegenstände für ezCores „Beobachtetes“ (itemIDs, wichtigste zuerst, höchstens limit bzw. Data.WATCH_MAX).
-- Immer angemeldet seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 19: niemand will schlechtere Preise für die
-- eigenen Rezepte).
function Data.WatchItems(limit)
    limit = Num(limit) or Data.WATCH_MAX
    local out, seen, products = {}, {}, {}
    local function add(itemID)
        itemID = Num(itemID)
        if itemID and not seen[itemID] and #out < limit then
            seen[itemID] = true
            out[#out + 1] = itemID
        end
    end
    for _, recipeID in ipairs(Data.WatchRecipes()) do
        if #out >= limit then break end
        local recipe = Data.Recipe(recipeID)
        if recipe then
            for _, reagent in ipairs(recipe.reagents or EMPTY) do add(reagent.itemID) end
            if recipe.product then products[#products + 1] = recipe.product end
        end
    end
    for _, itemID in ipairs(products) do add(itemID) end
    return out
end

-- Anmeldung bei ezCore. → true, wenn ezCore den Dienst hat (sonst geschieht nichts)
function Data.RegisterWatch()
    local prices = Core.Prices
    if not (prices and type(prices.AddWatchProvider) == "function") then return false end
    return Call(prices.AddWatchProvider, Data.WATCH_KEY, function() return Data.WatchItems() end, Data.WATCH_MAX) == true
end

Data.RegisterWatch()

local ScanFavoritesSoon = ns.Throttle(function() Data.ScanFavorites() end, 1)
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_FAVORITES_CHANGED" }) do
    ns.On(event, ScanFavoritesSoon)
end

---------------------------------------------------------------------------
-- Was noch auf ezCore wartet (für /ezcraft status und den PR)
---------------------------------------------------------------------------

function Data.WaitingLines()
    local lines = {}
    if not KnowledgeFn("Crafters") then lines[#lines + 1] = L.WAIT_CRAFTERS end
    if not KnowledgeFn("SkillStages") then lines[#lines + 1] = L.WAIT_STAGES end
    if not KnowledgeFn("RecipeSource") then lines[#lines + 1] = L.WAIT_SOURCES end
    if not Data.HasPrices() then
        lines[#lines + 1] = L.WAIT_PRICES
    else
        -- AH-32/AH-39: Gewinn nach Gebühr und das Anmelden des Materials brauchen ezCore aus Welle 12
        if type(Core.Prices.Net) ~= "function" then lines[#lines + 1] = L.WAIT_NET end
        if type(Core.Prices.AddWatchProvider) ~= "function" then lines[#lines + 1] = L.WAIT_WATCH end
    end
    if not Data.HasCooldowns() then lines[#lines + 1] = L.WAIT_COOLDOWNS end
    if not Data.HasGathering() then lines[#lines + 1] = L.WAIT_GATHERING end
    if type(Core.WhoHandles) ~= "function" then lines[#lines + 1] = L.WAIT_OTHER end
    return lines
end
