local _, ns = ...
local Core = ezCore

--[[
    Bester Gegenstand bei dir (Paket ezmacro/gifte-waffenzauber, Wunsch des Nutzers vom 20.11.2026: „Können wir auch
    ermöglichen z.b. Waffen ebenso mit Giften zu belegen (schurke) und co? … Blizzard konform?“). Eine Regel für
    ezBuff (Aufgabe am Buff-Knopf) und ezMacro (Vorlagen „Gift Waffenhand“ und „Gift Schildhand“), damit beide
    denselben Gegenstand nehmen (Leitlinie 2). Die Regel stand vorher nur in ezBuff (Checks.lua: Score und die
    Vorauswahl in Check.ScanBags); ezBuff ruft sie jetzt hier.

    Wissen über den Gegenstand: ezCores Item-Wissen (Core.Knowledge.Get → facts.consumable; Art „weaponEnchant“ für
    Gift, Wetzstein, Gewichtsstein, Zauberöl). Bestand: Core.ForEachBagItem mit „carried“ (alles, was du bei dir trägst).

      BestItems.Usable(facts, klasse, jedeKlasse?) → passt? Verbrauchsgut, jetzt benutzbar (facts.usableNow ~= false)
                                         und – wenn das Item-Wissen „gut für <Klasse>“ nennt – für diese Klasse. Mit
                                         jedeKlasse zählt „gut für“ nicht (ezBuffs Buff-Essen: Fehler vom Nutzer vom
                                         23.11.2026 „fehlendes bufffood (in tasche vorhanden) beim hexer wird nicht
                                         angezeigt“ – Essen mit ungünstigem Wert ist besser als gar keins)
      BestItems.Fit(facts, klasse)     → "class" | "all" | "other" | nil: passt der Gegenstand laut Item-Wissen zur
                                         Klasse? "class" = „gut für“ nennt sie (nicht für alle); "all" = für alle, ohne
                                         Angabe, ohne Klasse oder einer der Werte nützt laut Item-Wissen jeder Klasse
                                         (keine Klassenliste, etwa Ausdauer – „Ausdauer und Willenskraft“ nennt sonst
                                         nur die Klassen der Willenskraft); "other" = nur andere Klassen; nil ohne
                                         Verbrauchsgut
      BestItems.Score(facts, klasse)   → Wertung: Mindeststufe, +1000 bei Fit "class", −NOT_FOR_CLASS (2000) bei Fit
                                         "other" (nennt das Item-Wissen die Klasse nicht), +500 Fläschchen (vor
                                         Elixier); nil ohne Verbrauchsgut
      BestItems.RULES[art]             → Regel zum Auffüllen (Paket ezmacro/ssot-doppelungen, vorher ezMacro/OneClick.lua):
                                         test(c) → passt die Art? prefer(c) → bevorzugt (ohne Buff, reine Art)?
                                         Arten food, drink, bandage, potion (BestItems.CONSUMABLE_KINDS), dazu
                                         manaPotion (Manatrank; nur für ezCombats Trank im mittigen Symbol, nicht in
                                         CONSUMABLE_KINDS – ezMacros Auffüllen bleibt, wie es ist)
      BestItems.Consumable(art)        → itemID, facts | nil, Grund ("unknown" | "noKnowledge" | "noItem"): bestes
                                         Essen, Getränk, Verband bzw. Heiltrank in den normalen Taschen – benutzbar
                                         (usableNow ~= false) und Mindeststufe ≤ deine Stufe; Rangfolge 1. bevorzugt
                                         (ohne Buff: Buff-Essen verbraucht man nicht zum Auffüllen), 2. höchste
                                         Mindeststufe, 3. höchste Gegenstandsstufe, 4. kleinste ID. Buff-Essen und
                                         Fläschchen wertet dagegen BestItems.Score (ezBuff) – zwei Zwecke, eine Stelle.
      BestItems.WeaponEnchant(klasse, hand?) → itemID, facts | nil, Grund ("noKnowledge" | "noItem" | "noFit"): die
                                         beste Waffenverzauberung bei dir; bei Gleichstand die zuerst gefundene (Taschen-
                                         Reihenfolge, wie ezBuff); bricht der Durchlauf ab, nil, "noKnowledge". Mit hand
                                         ("main" | "off") nur, was die Waffe dieser Hand annimmt (BestItems.FitsHand);
                                         passt nichts davon, nil, "noFit"
      BestItems.FitsHand(facts, hand)  → true | false | nil: nimmt die Waffe dieser Hand den Gegenstand an? Laut Client-
                                         Tabelle SpellEquippedItems zum Zauber des Gegenstands (consumable.auraSpell bzw.
                                         useSpellID; ClientData.EnchantFit): Wetzstein nur Klingen (Axt, Schwert,
                                         Stangenwaffe, Dolch), Gewichtsstein nur Streitkolben, Stab und Faustwaffe, Öle und
                                         Gifte jede Nahkampfwaffe, Fernkampfwaffen nichts davon. nil = unbekannt (kein
                                         Zauber, keine Zeile, Gegenstand noch nicht geladen) – dann schließt die Wahl
                                         nichts aus (wie vorher). Paket ezcore/klinge-wucht (Wunsch des Nutzers vom
                                         20.11.2026: „interessant ist das jeweilige nur für die, die es nutzen können“)
      BestItems.PickWeaponEnchant(kandidaten, hand?) → Eintrag | nil, Grund ("noItem" | "noFit"): aus { { itemID, facts,
                                         score, … } … } in Taschen-Reihenfolge der mit der höchsten Wertung, der zur Hand
                                         passt (FitsHand nicht false), bei Gleichstand der erste. Eine Stelle für
                                         WeaponEnchant und ezBuffs Buff-Knopf (Weapon.Tasks, aus dem Zwischenspeicher)
]]

local BestItems = {}
Core.BestItems = BestItems

local function Consumable(facts)
    local c = type(facts) == "table" and facts.consumable or nil
    return type(c) == "table" and c or nil
end

function BestItems.Usable(facts, class, anyClass)
    local c = Consumable(facts)
    if not c or facts.usableNow == false then return false end
    if anyClass then return true end
    if Core.IsSecret(class) then class = nil end
    if c.goodFor and class and not c.goodFor[class] then return false end
    return true
end

-- Nützt einer der Werte laut Item-Wissen jeder Klasse (K.StatGoodFor ohne Klassenliste, etwa Ausdauer)? Das
-- Item-Wissen übergeht solche Werte beim Schneiden von „gut für“ (Knowledge.lua, BuildGoodFor; dieselbe Wahl der
-- Werte: consumable.stats, sonst facts.stats).
local function StatForAll(facts, c)
    local K = Core.Knowledge
    local stats = type(c.stats) == "table" and c.stats or facts.stats
    if type(stats) ~= "table" or type(K) ~= "table" or type(K.StatGoodFor) ~= "function" then return false end
    for stat in pairs(stats) do
        if type(K.StatGoodFor(stat)) ~= "table" then return true end
    end
    return false
end

function BestItems.Fit(facts, class)
    local c = Consumable(facts)
    if not c then return nil end
    if Core.IsSecret(class) then class = nil end
    if not (type(c.goodFor) == "table" and class) or facts.goodForAll then return "all" end
    if c.goodFor[class] then return "class" end
    if StatForAll(facts, c) then return "all" end
    return "other"
end

-- Abzug bei Fit "other": größer als alles, was Stufe und Fläschchen zusammen bringen – ein solcher Gegenstand steht
-- hinter allem Passenden. Bei den heutigen Aufrufern erreicht ihn nur Buff-Essen (ezBuff: Usable(facts, klasse,
-- true)); wer Score ohne Usable aufruft, bekommt den Abzug ebenso.
BestItems.NOT_FOR_CLASS = 2000

function BestItems.Score(facts, class)
    local c = Consumable(facts)
    if not c then return nil end
    local score = Core.Num(facts.minLevel) or 0
    local fit = BestItems.Fit(facts, class)
    if fit == "class" then score = score + 1000 elseif fit == "other" then score = score - BestItems.NOT_FOR_CLASS end
    if c.kind == "flask" then score = score + 500 end
    return score
end

-- Regeln je Art: test(c) → passt die Art? prefer(c) → bevorzugt (ohne Buff, reine Art)? (vorher RULES in ezMacro)
BestItems.RULES = {
    food = {
        test = function(c) return (c.kind == "food" or c.kind == "foodDrink") and c.restoresHealth == true end,
        prefer = function(c) return c.kind == "food" and not c.buff end,
    },
    drink = {
        test = function(c) return (c.kind == "drink" or c.kind == "foodDrink") and c.restoresMana == true end,
        prefer = function(c) return c.kind == "drink" and not c.buff end,
    },
    bandage = {
        test = function(c) return c.kind == "bandage" end,
    },
    potion = {
        test = function(c) return c.kind == "potion" and c.restoresHealth == true and not c.restoresMana end,
    },
    manaPotion = {
        test = function(c) return c.kind == "potion" and c.restoresMana == true and not c.restoresHealth end,
    },
}
BestItems.CONSUMABLE_KINDS = { "food", "drink", "bandage", "potion" }

-- a besser als b? Schlüssel { bevorzugt, Mindeststufe, Gegenstandsstufe, -ID }
local function Better(a, b)
    if not b then return true end
    for i = 1, #a do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

function BestItems.Consumable(kind)
    local rule = not Core.IsSecret(kind) and BestItems.RULES[kind] or nil
    if not rule then return nil, "unknown" end
    local K = Core.Knowledge
    if type(K) ~= "table" or type(K.Get) ~= "function" then return nil, "noKnowledge" end
    local level = Core.PlayerLevel() or 1          -- gesperrt oder unbekannt → nil (V-179)
    local consumable = Core.ITEM_CLASS and Core.ITEM_CLASS.Consumable or 0
    local seen, bestID, bestFacts, bestKey = {}, nil, nil, nil
    Core.ForEachBagItem(function(_, _, info)
        local id = type(info) == "table" and Core.Num(Core.Plain(info.itemID)) or nil
        if not id or seen[id] then return end
        seen[id] = true
        if Core.ItemClass(id) ~= consumable then return end
        local link = Core.Plain(info.hyperlink)
        local facts = K.Get(type(link) == "string" and link or id)
        local c = type(facts) == "table" and facts.consumable or nil
        if type(c) ~= "table" or not rule.test(c) then return end
        if facts.usableNow == false or (Core.Num(Core.Plain(facts.minLevel)) or 0) > level then return end
        local key = { (rule.prefer and rule.prefer(c)) and 1 or 0, Core.Num(Core.Plain(facts.minLevel)) or 0,
            Core.Num(Core.Plain(facts.itemLevel)) or 0, -id }
        if Better(key, bestKey) then bestID, bestFacts, bestKey = id, facts, key end
    end)
    if not bestID then return nil, "noItem" end
    return bestID, bestFacts
end

local HasBit = Core.HasBitAt

function BestItems.FitsHand(facts, hand)
    local c = Consumable(facts)
    if not c or Core.IsSecret(hand) then return nil end
    local spell = Core.Num(Core.Plain(c.auraSpell)) or Core.Num(Core.Plain(facts.useSpellID))
    local CD = Core.ClientData
    local fit = spell and CD and type(CD.EnchantFit) == "function" and CD.EnchantFit(spell) or nil
    if not fit then return nil end
    -- leerer Platz: nichts passt; gesperrt oder nicht abfragbar: unbekannt (Review)
    local item, why = Core.HandItem(hand or "main")
    if not item then
        if why == "empty" then return false end
        return nil
    end
    local classID, subClassID = Core.ItemClass(item)
    if not classID then return nil end
    if fit.subclassMask ~= 0 then
        if subClassID == nil then return nil end
        -- Unterklassen gelten nur in der genannten Gegenstandsklasse (Waffe)
        if classID ~= fit.itemClass or not HasBit(fit.subclassMask, subClassID) then return false end
    elseif fit.invTypeMask == 0 and fit.itemClass >= 0 and classID ~= fit.itemClass then
        return false
    end
    -- Auslegung: Ohne Unterklassen-Maske entscheidet die Platz-Maske allein, auch über die Gegenstandsklasse – so nimmt
    -- ein Schild (Klasse 4, Platz 14) die Schildbeschichtung an (Klasse 2, Platz-Maske 14), ein Öl (Plätze 13/17/21/22)
    -- dagegen nicht. Laut den ausgelieferten Daten hat kein Gegenstand der Klasse 4 einen dieser Waffenplätze.
    if fit.invTypeMask ~= 0 then
        local api = rawget(_G, "C_Item")
        local inv = Core.Num(Core.Plain((Core.Call(type(api) == "table" and api.GetItemInventoryTypeByID or nil, item))))
        if not inv then return nil end
        if not HasBit(fit.invTypeMask, inv) then return false end
    end
    return true
end

function BestItems.PickWeaponEnchant(candidates, hand)
    if Core.IsSecret(hand) then hand = nil end     -- gesperrte Hand wie keine (Leitlinie: IsSecret zuerst)
    if type(candidates) ~= "table" or not candidates[1] then return nil, "noItem" end
    local best
    for _, e in ipairs(candidates) do
        local score = type(e) == "table" and Core.Num(e.score) or nil
        if score and (not best or score > best.score) and (hand == nil or BestItems.FitsHand(e.facts, hand) ~= false) then
            best = e
        end
    end
    if not best then return nil, "noFit" end
    return best
end

function BestItems.WeaponEnchant(class, hand)
    local K = Core.Knowledge
    if not (type(K) == "table" and type(K.Get) == "function" and type(Core.ForEachBagItem) == "function") then
        return nil, "noKnowledge"
    end
    if Core.IsSecret(class) then class = nil elseif class == nil then class = Core.PlayerClass() end
    local candidates, seen = {}, {}
    local ok = Core.Try("ezCore", "BestItems.WeaponEnchant", Core.ForEachBagItem, function(_, _, info)
        local itemID = Core.Num(type(info) == "table" and info.itemID or nil)
        if not itemID or seen[itemID] then return end
        local facts = K.Get(itemID)
        local c = Consumable(facts)
        if not c or c.kind ~= "weaponEnchant" or not BestItems.Usable(facts, class) then return end
        local score = BestItems.Score(facts, class)
        if score then
            seen[itemID] = true
            candidates[#candidates + 1] = { itemID = itemID, facts = facts, score = score }
        end
    end, "carried")
    -- abgebrochener Durchlauf (Fehler in der Fehlerliste): kein halbes Ergebnis, wie ezBuffs Check.BagItems
    if not ok then return nil, "noKnowledge" end
    local best, why = BestItems.PickWeaponEnchant(candidates, hand)
    if not best then return nil, why end
    return best.itemID, best.facts
end
