local _, ns = ...
local L = ns.L
local UI = ns.UI
local Core = ezCore

--[[
    Vier Helfer „Eine Taste“ (FP-14, Entscheidung des Nutzers vom 14.11.2026: alle vier gewählt; Welle 7,
    MACRO-06 bis MACRO-09). Muster wie „Angeln mit einer Taste“ (Fishing.lua) und die Ein-Klick-Makros (OneClick.lua):
    ein echtes Blizzard-Makro im Reiter „Ein-Klick“, übernommen auf Klick, danach außerhalb des Kampfes aktuell
    gehalten – nur ein Makro, das ezMacro selbst angelegt hat (Gedächtnis ezMacroDB.oneClick, OneClick.Locate). Im
    Kampf bleibt alles, wie es ist; was danach fällig ist, holt ns.AfterCombat nach. Je Helfer ein Schalter
    (OPT_oneKeyConjure, OPT_oneKeyQuest, OPT_oneKeyOpen, OPT_oneKeyPet): aus, und sein Makro bleibt unverändert; ein
    Helfer mit sicherem Knopf (Öffnen, Füttern) leert dann auch den Knopf. Der Hauptschalter „Ein-Klick-Makros aktuell
    halten“ (OPT_oneClickUpdate) gilt für alle vier mit (OneKey.Active).

      Herbeizaubern o. benutzen (MACRO-06)  Magier: Wasser, Essen; Hexenmeister: Gesundheitsstein, Seelenstein.
                     Liegt der Gegenstand in der Tasche, „/use item:<ID>“ (der beste Rang, den du benutzen kannst),
                     sonst „/cast <Herstellzauber>“ – ohne Rang, so wirkt der höchste gelernte.
      Questgegenstand (MACRO-07)  der Gegenstand zum Benutzen aus dem Questlog des Clients
                     (GetQuestLogSpecialItemInfo): zuerst die hervorgehobene Quest, dann verfolgte, dann eine Quest im
                     aktuellen Gebiet, dann die nächste im Log – nur, was in den Taschen liegt.
      Öffnen und Entzaubern (MACRO-08)  das nächste öffenbare Ding (ezCore.Knowledge.IsOpenable), als Schurke zuerst
                     Schlossknacken auf eine Schließkassette, dann der nächste angehakte Gegenstand zum Entzaubern
                     (Liste im Werkzeug „Öffnen und Entzaubern“: nie ohne Häkchen; Teile eines ezGear-Sets sind
                     ausgenommen, ebenso ein Platz mit ezBags Schloss „nie verkaufen“ – Entscheidung des Nutzers
                     vom 16.11.2026, Nr. 18: das Schloss gilt künftig auch für nicht Graues). Die Aktion liegt an einem sicheren
                     Knopf (Core.SecureButton „ezMacroOneKeyOpen“), das Makro sagt „/click“: Zauber auf einen
                     Gegenstand gehen über Blizzards „target-item“ bzw. „target-bag“/„target-slot“ – der Gegenstand
                     wird nur genommen, wenn der Zauber wirklich auf ein Ziel wartet (SecureTemplates.lua, Zweig
                     forever). So kann ein gescheiterter Zauber nie einen Gegenstand anlegen oder benutzen.
      Begleiter je Zustand (MACRO-09)  Hexenmeister: der gewählte Dämon (Einstellung OPT_petDemon), nur ohne bzw. mit
                     totem Begleiter. Jäger: „[@pet,dead] wiederbeleben; [nopet] rufen; heilen“ als Makro-Bedingungen –
                     Leben des Begleiters liest ezMacro nie (auf Forever kann es gesperrt sein, Leitlinie 6). Was keine
                     Bedingung kann, schreibt ezMacro außerhalb des Kampfes dazu: Ist der Begleiter nicht zufrieden
                     (C_PetInfo.GetPetHappiness, nur lesbar ausgewertet), füttert der Knopf außerhalb des Kampfes – mit dem
                     ersten angehakten Futter aus der Tasche (sicherer Knopf „ezMacroOneKeyFeed“, wie oben).
                     Welche Nahrung ein Tier frisst, nennt der Client als Art (C_PetInfo.GetPetFoodTypes); das Futter hakst du
                     im Werkzeug „Begleiter“ selbst an (C_PetInfo.CanPetEatItem je Gegenstand: noch ungenutzt,
                     docs/roadmap/ezMacro.md).

    Fakten mit Quelle (Leitlinie 10, nichts aus Addons): Zauber-IDs geprüft am 15.11.2026 gegen Wowheads
    Forever-Tooltip (nether.wowhead.com/forever/tooltip/spell/<ID>), Name und Klasse. Herbeizaubern (5504, 587),
    Gesundheits- und Seelenstein (6201, 693) samt ihren Gegenständen und dem Prüfstand stehen bei Core.Spells.CONJURED
    (ezCore/Wissen/SpellData.lua). Dazu:
      1804 Schlossknacken (Schurke), 688/697/712/691 Wichtel/Leerwandler/Sukkubus/Teufelsjäger beschwören,
      883 Tier rufen, 982 Tier wiederbeleben, 136 Tier heilen, 6991 Tier füttern (Jäger)
    Entzaubern (13262) kommt aus ezCore (Core.Salvage.KINDS.disenchant), Namen, Ränge und „gelernt“ aus dem Client
    (ezCore.Spells). Ob der Forever-Client jede ID kennt, meldet „/ezmacro pruefen“ nicht (die IDs stehen in keiner
    Vorlage) – Prüfpunkte unter „Im Spiel prüfen (Welle 7)“ in docs/roadmap/ezMacro.md.

    Rücksicht (Leitlinie 9): Öffnen und Entzaubern fragt ns.OtherFor("openItems"). Die Funktion fehlt in ezCores
    Liste noch („Wartet auf ezCore“ in docs/roadmap/ezMacro.md) – bis dahin liefert die Abfrage nil.
]]
local OneKey = {}
ns.OneKey = OneKey

local Plain, Num, Bool, Call = Core.Plain, Core.Num, Core.Bool, Core.Call

-- Hergestellte Gegenstände (Wasser, Essen, Gesundheits- und Seelenstein) und der Seelensplitter liegen in ezCore
-- (Core.Spells.CONJURED, Core.Spells.SOUL_SHARD; Gesamtreview 18.11.2026, T16-9 – vorher hier und in ezCombat je eine
-- Liste mit verschiedener Herkunftsangabe). Die Namen bleiben als Verweis.
OneKey.CONJURE = Core.Spells.CONJURED
OneKey.CONJURE_ORDER = { "conjureWater", "conjureFood", "healthstone", "soulstone" }
OneKey.SOUL_SHARD = Core.Spells.SOUL_SHARD
OneKey.PICK_LOCK = 1804
OneKey.DEMONS = { { key = "imp", spell = 688 }, { key = "voidwalker", spell = 697 }, { key = "succubus", spell = 712 },
    { key = "felhunter", spell = 691 } }
OneKey.HUNTER = { call = 883, revive = 982, mend = 136, feed = 6991 }
OneKey.OPEN_BUTTON = "ezMacroOneKeyOpen"
OneKey.FEED_BUTTON = "ezMacroOneKeyFeed"

local ITEM_TEXT = "#showtooltip item:%d\n/use item:%d"
local AFTER_KEY = "onekey.sync"

local function PlayerClass() return Core.PlayerClass() end

-- Taschen einmal lesen → { [itemID] = { id, count, bag, slot, link, quality } }, Liste in Taschen-Reihenfolge.
local function Bags()
    local byID, list = {}, {}
    Core.ForEachBagItem(function(bag, slot, info)
        local id = Num(info.itemID)
        if not id then return end
        local item = byID[id]
        if not item then
            local link = Plain(info.hyperlink)
            item = { id = id, count = 0, bag = bag, slot = slot, link = type(link) == "string" and link or nil,
                quality = Num(info.quality) }
            byID[id] = item
            list[#list + 1] = item
        end
        item.count = item.count + (Num(info.stackCount) or 1)
    end)
    return byID, list
end
OneKey.Bags = Bags

-- Benutzbar ab Stufe (ezCores Item-Wissen; ohne Auskunft: ja).
local function Usable(id)
    local K = Core.Knowledge
    local facts = type(K) == "table" and type(K.Get) == "function" and K.Get(id) or nil
    local need = type(facts) == "table" and Num(facts.minLevel) or nil
    return not need or need <= (Core.PlayerLevel() or 1)
end

local function Equippable(id)
    local fn = C_Item and C_Item.IsEquippableItem or rawget(_G, "IsEquippableItem")
    return Bool(Call(fn, id), false) == true
end

-- Zustand je Helfer für Statuszeile und Werkzeug-Seiten (zuletzt gebaut).
local last = {}
OneKey.Last = last

---------------------------------------------------------------------------
-- MACRO-06: Herbeizaubern oder benutzen
---------------------------------------------------------------------------

-- → Text | nil, Grund; dazu "use", itemID bzw. "cast".
function OneKey.Conjure(kind)
    local def = OneKey.CONJURE[kind]
    if not def then return nil, "unknown" end
    if PlayerClass() ~= def.class then
        last[kind] = { state = "class" }
        return nil
    end
    local byID = Bags()
    for i = #def.items, 1, -1 do
        local id = def.items[i]
        if byID[id] and Usable(id) then
            last[kind] = { state = "use", item = id }
            return ITEM_TEXT:format(id, id), "use", id
        end
    end
    local name = ns.IsSpellKnown(def.spell) and ns.SpellName(def.spell) or nil
    if type(name) ~= "string" or name == "" then
        last[kind] = { state = "unknown" }
        return nil, "no_" .. kind
    end
    last[kind] = { state = "cast", noShard = def.shard and byID[OneKey.SOUL_SHARD] == nil or nil }
    return "#showtooltip\n/cast " .. name, "cast"
end

---------------------------------------------------------------------------
-- MACRO-07: Questgegenstand
---------------------------------------------------------------------------

-- Quests mit Gegenstand zum Benutzen, der in den Taschen liegt, beste zuerst →
-- { { itemID, questID, title, rank, super, watched, onMap } } | nil, "noQuestLog".
-- Quelle: Questlog des Clients über ezCore (Core.Inventory.QuestUseItems, dieselbe Liste wie ezQuest).
function OneKey.QuestItems()
    local all, why = Core.Inventory.QuestUseItems()
    if not all then return nil, why end
    local byID, list = Bags(), {}
    for _, entry in ipairs(all) do
        if byID[entry.itemID] and not Equippable(entry.itemID) then list[#list + 1] = entry end
    end
    return list
end

function OneKey.Quest()
    local list, why = OneKey.QuestItems()
    if not list then
        last.questItem = { state = why }
        return nil, why
    end
    local best = list[1]
    if not best then
        last.questItem = { state = "none" }
        return nil, "no_questItem"
    end
    last.questItem = { state = "use", item = best.itemID, title = best.title, rank = best.rank, count = #list }
    return ITEM_TEXT:format(best.itemID, best.itemID), "use", best.itemID
end

---------------------------------------------------------------------------
-- MACRO-08: Öffnen und Entzaubern
---------------------------------------------------------------------------

-- „Verschlossen“ liest ezCore je Taschenplatz frisch aus Blizzards Tooltip des Platzes (Knowledge.IsOpenable mit
-- Platz bzw. Knowledge.FreshLocked, Welle 23a): nach dem Schlossknacken sagt der Platz sofort „offen“, zwei gleiche
-- Kassetten sind zwei Schlösser, ein Schloss in der Welt ändert nichts. Das Sitzungs-Gedächtnis „geknackt“ (Merker
-- beim Klick, Cast-GUID aus UNIT_SPELLCAST_SENT) ist darum entfallen (Welle 23, A10).
local pickTarget           -- { key, id, bag, slot }: worauf der Knopf gerade Schlossknacken wirkt

local function SlotKey(bag, slot) return tostring(bag) .. ":" .. tostring(slot) end

-- Gedächtnis je Charakter: ezMacroDB.oneKey[charKey] = { disenchant = { [itemID] = true }, petFood = { … } }
local function Store(field, create)
    local all = ns.db and ns.db.oneKey
    if type(all) ~= "table" or not ns.charKey then return nil end
    local mine = all[ns.charKey]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        all[ns.charKey] = mine
    end
    local store = mine[field]
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        mine[field] = store
    end
    return store
end
OneKey.Store = Store

-- Teile aller ezGear-Sets → { [itemID] = Name des Sets } (ezCore.API("ezGear").Sets/SetItems; ohne ezGear leer).
local function SetItems()
    local out = {}
    local gear = Core.API and Core.API("ezGear")
    if type(gear) ~= "table" or type(gear.Sets) ~= "function" or type(gear.SetItems) ~= "function" then return out end
    local sets = Call(gear.Sets)
    for _, set in ipairs(type(sets) == "table" and sets or {}) do
        local name = type(set) == "table" and Plain(set.name)
        local items = type(name) == "string" and Call(gear.SetItems, set.id or name)
        if type(items) == "table" then
            for _, value in pairs(items) do
                local id = Num(Plain(value))
                if id and not out[id] then out[id] = name end
            end
        end
    end
    return out
end

-- Trägt der Platz ezBags Schloss „nie verkaufen“? (ezCore.API("ezBag").IsLocked je Platz; ohne ezBag, ohne die
-- Abfrage oder bei einem Fehler: nein). Nach der Entscheidung des Nutzers vom 16.11.2026 (Nr. 18) gilt das Schloss
-- künftig auch für nicht graue Gegenstände; die Abfrage nimmt jeden Gegenstand mit Schloss aus, sobald ezBag es
-- setzt – ezMacro braucht dafür keine Änderung.
local function BagLocked(bag, slot)
    local api = Core.API and Core.API("ezBag")
    if type(api) ~= "table" or type(api.IsLocked) ~= "function" then return false end
    return Call(api.IsLocked, bag, slot) == true
end

-- Öffenbares in den Taschen → { { id, link, bag, slot, key, locked } } (ezCore.Knowledge.IsOpenable). Je ID nur das
-- erste Exemplar in Taschen-Reihenfolge: „Benutzen“ mit item:<ID> nimmt das erste, also wird genau dieses geknackt und
-- danach geöffnet; ist es weg, kommt das nächste mit eigenem Schloss dran.
function OneKey.Openables()
    local K = Core.Knowledge
    local list, seen = {}, {}
    if type(K) ~= "table" or type(K.IsOpenable) ~= "function" then return list end
    Core.ForEachBagItem(function(bag, slot, info)
        local id = Num(info.itemID)
        if not id then return end
        local key = SlotKey(bag, slot)
        if seen[id] then return end
        local link = Plain(info.hyperlink)
        local openable, locked = K.IsOpenable(type(link) == "string" and link or id, bag, slot)
        if openable == true and not Equippable(id) then
            -- Meldet das Item-Wissen „verschlossen“, zählt der frische Tooltip des Platzes (falls der Client ihn liefert)
            if locked == true and type(K.FreshLocked) == "function" and K.FreshLocked(bag, slot) == false then
                locked = false
            end
            seen[id] = true
            list[#list + 1] = { id = id, link = type(link) == "string" and link or nil, bag = bag, slot = slot, key = key,
                locked = locked == true }
        end
    end)
    return list
end

-- Gegenstände zum Entzaubern → { { id, link, quality, ilvl, count, ticked, excluded ("lock" | "set"), setName } }.
-- Daten: ezCore.Salvage.For (Ausrüstung grün bis violett); ausgenommen: Teil eines ezGear-Sets, ezBag-Schloss (s. o.).
function OneKey.Disenchantables()
    local S = Core.Salvage
    local list, byID = {}, {}
    if type(S) ~= "table" or type(S.For) ~= "function" then return list end
    local sets = SetItems()
    local ticks = Store("disenchant", false) or {}
    Core.ForEachBagItem(function(bag, slot, info)
        local id = Num(info.itemID)
        if not id or byID[id] == false then return end   -- false: schon gesehen, nicht zu entzaubern
        local item = byID[id]
        if not item then
            local link = Plain(info.hyperlink)
            link = type(link) == "string" and link or nil
            local result = S.For(link or id)
            if type(result) ~= "table" then
                byID[id] = false
                return
            end
            item = { id = id, link = link, quality = Num(result.quality), ilvl = Num(result.ilvl), count = 0,
                ticked = ticks[id] == true }
            if sets[id] then item.excluded, item.setName = "set", sets[id] end
            byID[id] = item
            list[#list + 1] = item
        end
        if not item then return end
        item.count = item.count + (Num(info.stackCount) or 1)
        if BagLocked(bag, slot) then item.excluded = "lock" end   -- ein Exemplar mit Schloss: alle ausgenommen
    end)
    return list
end

-- Haken setzen bzw. nehmen (Rückfrage-Liste im Werkzeug). → neuer Stand
function OneKey.SetTicked(itemID, on)
    itemID = Num(itemID)
    local store = itemID and Store("disenchant", true)
    if not store then return false end
    store[itemID] = on and true or nil
    OneKey.Schedule()
    return on and true or false
end

function OneKey.ClearTicks()
    local store = Store("disenchant", false)
    if store then wipe(store) end
    OneKey.Schedule()
end

-- Was die Taste „Öffnen und Entzaubern“ jetzt tut → { mode ("open" | "pick" | "disenchant"), item } | nil, Grund.
function OneKey.OpenPlan()
    local other = ns.OtherFor("openItems")
    if type(other) == "string" and other ~= "" then return nil, "otherOpen", other end
    local openables = OneKey.Openables()
    for _, item in ipairs(openables) do
        if not item.locked then return { mode = "open", item = item.id } end
    end
    if PlayerClass() == "ROGUE" and ns.IsSpellKnown(OneKey.PICK_LOCK) then
        for _, item in ipairs(openables) do
            if item.locked then
                return { mode = "pick", item = item.id, bag = item.bag, slot = item.slot, key = item.key,
                    spell = OneKey.PICK_LOCK }
            end
        end
    end
    local S = Core.Salvage
    local kind = S and S.KINDS and S.KINDS.disenchant
    if kind then
        local known = type(S.Known) == "function" and S.Known("disenchant") == true
        for _, item in ipairs(OneKey.Disenchantables()) do
            if item.ticked and not item.excluded then
                -- angehakt, aber Entzaubern nicht gelernt: das sagen statt „nichts angehakt“ (Leitlinie 11)
                if not known then return nil, "noDisenchant" end
                return { mode = "disenchant", item = item.id, spell = kind.spell }
            end
        end
    end
    return nil, "no_open"
end

function OneKey.Open()
    local plan, why, other = OneKey.OpenPlan()
    last.open = plan or { state = why, other = other }
    if not plan then return nil, why end
    return ("#showtooltip item:%d\n/click %s"):format(plan.item, OneKey.OPEN_BUTTON), plan.mode, plan.item
end

---------------------------------------------------------------------------
-- MACRO-09: Begleiter je Zustand
---------------------------------------------------------------------------

function OneKey.Demon()
    local key = ns.S and ns.S.petDemon
    for _, demon in ipairs(OneKey.DEMONS) do
        if demon.key == key then return demon end
    end
    return OneKey.DEMONS[1]
end

-- Zufriedenheit des Begleiters (1 unzufrieden, 2 zufrieden, 3 glücklich) | nil (kein Begleiter, gesperrt, unbekannt).
function OneKey.Happiness()
    if Core.UnitPresent("pet") ~= true then return nil end
    if Bool(Call(rawget(_G, "UnitIsDead"), "pet"), true) ~= false then return nil end
    local api = rawget(_G, "C_PetInfo")     -- wie Blizzards PetHappiness.lua; die alte Globale nur als Rückfall
    local value = Num((Call(type(api) == "table" and api.GetPetHappiness or rawget(_G, "GetPetHappiness"))))
    return value and value >= 1 and value <= 3 and value or nil     -- Blizzard kennt nur 1 bis 3
end

-- Erstes angehaktes Futter in den Taschen → itemID | nil
function OneKey.Food()
    local ticks = Store("petFood", false)
    if not ticks then return nil end
    for _, item in ipairs(select(2, Bags())) do
        if ticks[item.id] then return item.id end
    end
    return nil
end

-- Futter-Kandidaten für das Werkzeug: Essen aus der Tasche (ezCores Item-Wissen: Art Essen) →
-- { { id, link, count, ticked } }
function OneKey.FoodCandidates()
    local list = {}
    local K = Core.Knowledge
    if type(K) ~= "table" or type(K.Get) ~= "function" then return list end
    local ticks = Store("petFood", false) or {}
    for _, item in ipairs(select(2, Bags())) do
        local facts = K.Get(item.link or item.id)
        local c = type(facts) == "table" and facts.consumable or nil
        if type(c) == "table" and (c.kind == "food" or c.kind == "foodDrink") then
            list[#list + 1] = { id = item.id, link = item.link, count = item.count, ticked = ticks[item.id] == true }
        end
    end
    return list
end

function OneKey.SetFood(itemID, on)
    itemID = Num(itemID)
    local store = itemID and Store("petFood", true)
    if not store then return false end
    store[itemID] = on and true or nil
    OneKey.Schedule()
    return on and true or false
end

-- Was die Begleiter-Taste füttern würde → itemID | nil, Grund ("happy" | "noFood" | "unknown" | "noPet")
function OneKey.FeedPlan()
    if not ns.IsSpellKnown(OneKey.HUNTER.feed) then return nil, "noSpell" end
    if Core.UnitPresent("pet") ~= true then return nil, "noPet" end
    local happiness = OneKey.Happiness()
    if not happiness then return nil, "unknown" end
    if happiness >= 3 then return nil, "happy" end
    local food = OneKey.Food()
    if not food then return nil, "noFood" end
    return food
end

function OneKey.Pet()
    local class = PlayerClass()
    if class == "WARLOCK" then
        local demon = OneKey.Demon()
        local name = ns.IsSpellKnown(demon.spell) and ns.SpellName(demon.spell) or nil
        if type(name) ~= "string" or name == "" then
            last.pet = { state = "noDemon", demon = demon.key }
            return nil, "no_demon"
        end
        last.pet = { state = "demon", demon = demon.key }
        return "#showtooltip\n/cast [nopet][@pet,dead] " .. name, "demon"
    elseif class == "HUNTER" then
        local H = OneKey.HUNTER
        local call, revive, mend = ns.SpellName(H.call), ns.SpellName(H.revive), ns.SpellName(H.mend)
        if not (ns.IsSpellKnown(H.call) and type(call) == "string" and call ~= "") then
            last.pet = { state = "noCall" }
            return nil, "no_hunterPet"
        end
        local parts = {}
        if ns.IsSpellKnown(H.revive) and type(revive) == "string" then parts[#parts + 1] = "[@pet,dead] " .. revive end
        parts[#parts + 1] = "[nopet] " .. call
        local food, why = OneKey.FeedPlan()
        local healKnown = ns.IsSpellKnown(H.mend) and type(mend) == "string"
        last.pet = { state = food and "feed" or "ready", food = food, feed = why }
        if food then
            if healKnown then parts[#parts + 1] = "[combat] " .. mend end
            return "#showtooltip\n/cast " .. table.concat(parts, "; ")
                .. "\n/click [nocombat,@pet,exists,nodead] " .. OneKey.FEED_BUTTON, "feed", food
        end
        if healKnown then parts[#parts + 1] = mend end
        return "#showtooltip\n/cast " .. table.concat(parts, "; "), "ready"
    end
    last.pet = { state = "class" }
    return nil, "petClass"
end

---------------------------------------------------------------------------
-- Hinweis „Dir fehlt …“ (Paket modul/ezbuff-reagenzien, wago F9): Reagenzien und Werkzeuge des Zaubers, den ein
-- Helfer gerade wirkt (Herbeizaubern ohne passenden Gegenstand in der Tasche, Dämon beschwören). Bedarf, Anzahl und
-- Texte rechnet seit Welle 26 ezCore (Spells.MissingReagents, Spells.ReagentList/ReagentText/ReagentSource – laut
-- Client-Tabellen, Anzahl über Blizzards API; dieselbe Rechnung wie in ezBuff, Leitlinie 2). Ohne Tabelle gilt wie
-- bisher der Seelensplitter der Einträge mit shard (ezMacros Rückfall, Quelle ONEKEY_REAGENT_SOURCE_OWN). Nur ein
-- Hinweis: Makro und Knöpfe bleiben, wie sie sind.
---------------------------------------------------------------------------

-- Zauber, den der Helfer laut letztem Bau wirkt (nil, wenn er einen Gegenstand benutzt oder nichts tut), dazu der
-- Gegenstand des Rückfalls ohne Client-Tabelle (Seelensplitter bei shard).
function OneKey.CastSpell(kind)
    local def = OneKey.CONJURE[kind]
    local s = last[kind]
    if def then
        if s and s.state == "cast" then return def.spell, def.shard and OneKey.SOUL_SHARD or nil end
        return nil
    end
    if kind == "pet" and s and s.state == "demon" then
        for _, demon in ipairs(OneKey.DEMONS) do
            if demon.key == s.demon then return demon.spell end
        end
    end
    return nil
end

-- Was fehlt für den Zauber des Helfers? → { { item, need, have } … } oder nil, Quelle ("tables" | "list"). Liest den
-- letzten Bau (OneKey.Conjure bzw. OneKey.Pet vorher aufrufen; OneKey.ReagentLines tut das selbst).
function OneKey.MissingReagents(kind)
    local spell, fallback = OneKey.CastSpell(kind)
    local Spells = Core.Spells
    if not spell or not (Spells and type(Spells.MissingReagents) == "function") then return nil end
    -- Rückfall nur ezMacros Seelensplitter (false: nicht ezCores Liste der Gruppenfassungen)
    local ok, missing, source = pcall(Spells.MissingReagents, spell, fallback or false)
    if not ok then return nil end
    return missing, source
end

-- „Seelensplitter (0 von 1)“, mehrere mit Komma (Name vom Client, sonst „#<ID>“; ezCores Spells.ReagentList).
function OneKey.ReagentList(missing)
    return Core.Spells.ReagentList(missing)
end

-- Hinweis für die Seite eines Ein-Klick-Makros: { „Dir fehlt: …“, Quelle } oder {} (nichts fehlt, kein Zauber).
function OneKey.ReagentLines(kind)
    if OneKey.CONJURE[kind] then
        OneKey.Conjure(kind)
    elseif kind == "pet" then
        OneKey.Pet()
    else
        return {}
    end
    local missing, source = OneKey.MissingReagents(kind)
    if not missing then return {} end
    local S = Core.Spells
    return { S.ReagentText(missing), S.ReagentSource(source, L.ONEKEY_REAGENT_SOURCE_OWN) }
end

---------------------------------------------------------------------------
-- Sichere Knöpfe (Öffnen/Entzaubern, Füttern): nur außerhalb des Kampfes umgestellt (Core.SecureButton merkt im
-- Kampf vor, ezMacro wartet ohnehin bis danach)
---------------------------------------------------------------------------

local function Button(name, create)
    local knopf = Core.SecureButtons.Get(name)
    if knopf or not create then return knopf end
    return Core.SecureButton(name, { owner = "ezMacro" })
end

-- Aktion auf den Knopf: Gegenstand benutzen (nur Öffenbares, nie Ausrüstung) oder Zauber mit Gegenstand als Ziel.
local function Apply(name, plan)
    local knopf = Button(name, plan ~= nil)
    if not knopf then return end
    -- Ziel des Zaubers: Schlossknacken auf genau den Platz (target-bag/target-slot – ein verrutschter Platz lässt den
    -- Zauber nur scheitern), Entzaubern und Füttern auf die ID (target-item – trifft nie einen anderen Gegenstand).
    -- Blizzards SecureTemplates.lua (Zweig forever) nimmt die Ziele nur, wenn der Zauber auf einen Gegenstand wartet.
    local target = {}
    if plan and plan.mode == "pick" then
        target["target-bag"], target["target-slot"] = plan.bag, plan.slot
    elseif plan and plan.mode ~= "open" then
        target["target-item"] = "item:" .. plan.item
    end
    for _, key in ipairs({ "target-item", "target-bag", "target-slot" }) do
        if knopf:Get(key) ~= target[key] then knopf:Set(key, target[key]) end
    end
    if not plan then
        if knopf:Get("type") ~= nil then knopf:ClearAction() end
        return
    end
    if plan.mode == "open" then
        local item = "item:" .. plan.item
        if knopf:Get("type") ~= "item" or knopf:Get("item") ~= item then knopf:SetAction({ type = "item", item = item }) end
    elseif knopf:Get("type") ~= "spell" or knopf:Get("spell") ~= plan.spell then
        knopf:SetAction({ type = "spell", spell = plan.spell })
    end
end

local WatchPick   -- Zuhörer auf gelungenes Schlossknacken an/aus (unten)

-- Hält ezMacro diesen Helfer gerade aktuell? Sein eigener Schalter und der Hauptschalter „Ein-Klick-Makros aktuell
-- halten“ (OPT_oneClickUpdate) müssen an sein – ohne den schreibt OneClick.Refresh kein Makro um, dann darf auch der
-- Knopf nicht weiterlaufen (sonst zeigte das Makro Gegenstand A, der Knopf wirkte auf B). → true | false, "main" | "off"
function OneKey.Active(setting)
    if not (ns.S and ns.S.oneClickUpdate) then return false, "main" end
    if ns.S[setting] == false then return false, "off" end
    return true
end

-- Stand „aus“ als Text: Hauptschalter oder Schalter des Helfers; Helfer mit Knopf sagen, dass die Taste ruht.
function OneKey.OffText(setting, button)
    local _, why = OneKey.Active(setting)
    if why == "main" then return button and L.ONEKEY_STATE_main_button or L.ONEKEY_STATE_main end
    return button and L.ONEKEY_STATE_off_button or L.ONEKEY_STATE_off
end

-- Beide Knöpfe passend zur Lage stellen. Ein ausgeschalteter Helfer leert seinen Knopf: was er zuletzt tat
-- (z. B. ein Häkchen, das du inzwischen genommen hast), darf er nicht weiter tun. → true | false, "combat"
function OneKey.Sync()
    if not ns.db then return false end
    if ns.InCombat() then
        ns.AfterCombat(OneKey.Sync, AFTER_KEY)
        return false, "combat"
    end
    local plan = OneKey.Active("oneKeyOpen") and OneKey.OpenPlan() or nil
    pickTarget = plan and plan.mode == "pick" and { key = plan.key, id = plan.item, bag = plan.bag, slot = plan.slot } or nil
    WatchPick(pickTarget ~= nil)
    Apply(OneKey.OPEN_BUTTON, plan)
    local food = OneKey.Active("oneKeyPet") and PlayerClass() == "HUNTER" and OneKey.FeedPlan() or nil
    Apply(OneKey.FEED_BUTTON, food and { mode = "feed", item = food, spell = OneKey.HUNTER.feed } or nil)
    return true
end

---------------------------------------------------------------------------
-- Anmelden: Platzhalter, Formen, Symbole, Ereignisse
---------------------------------------------------------------------------

local OC = ns.OneClick
for _, kind in ipairs(OneKey.CONJURE_ORDER) do
    ns.Dynamic.Register(kind, function() return OneKey.Conjure(kind) end)
    OC.SHAPES[kind] = { OC.ITEM_SHAPE, "^#showtooltip\n/cast [^\n]+$" }
    OC.ICONS[kind] = function() return ns.SpellIcon(OneKey.CONJURE[kind].spell) end
end
ns.Dynamic.Register("questItem", OneKey.Quest)
OC.SHAPES.questItem = OC.ITEM_SHAPE
ns.Dynamic.Register("open", OneKey.Open)
OC.SHAPES.open = "^#showtooltip item:%d+\n/click " .. OneKey.OPEN_BUTTON .. "$"
ns.Dynamic.Register("pet", OneKey.Pet)
OC.SHAPES.pet = {
    "^#showtooltip\n/cast %[nopet%]%[@pet,dead%] [^\n]+$",
    "^#showtooltip\n/cast [^\n]*%[nopet%] [^\n]+$",
    "^#showtooltip\n/cast [^\n]*%[nopet%] [^\n]+\n/click %[nocombat,@pet,exists,nodead%] " .. OneKey.FEED_BUTTON .. "$",
}
OC.ICONS.pet = function()
    if PlayerClass() == "WARLOCK" then return ns.SpellIcon(OneKey.Demon().spell) end
    if PlayerClass() == "HUNTER" then return ns.SpellIcon(OneKey.HUNTER.call) end
    return nil
end

-- Gebündelt: erst die Knöpfe, dann die Makros (OneClick.Schedule).
local scheduled = false
function OneKey.Schedule()
    if scheduled or not ns.db then return end
    scheduled = true
    C_Timer.After(0.5, function()
        scheduled = false
        ns.Try("OneKey", OneKey.Sync)
        OC.Schedule()
        for _, key in ipairs({ "onekeyOpen", "onekeyPet" }) do ns.Tools.RefreshKey(key) end
    end)
end

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "EQUIPMENT_SETS_CHANGED" }) do
    ns.On(event, OneKey.Schedule)
end
ns.OnUnit("UNIT_PET", "player", OneKey.Schedule)
ns.OnUnit("UNIT_HAPPINESS", "pet", OneKey.Schedule)
-- ezQuest meldet geänderte Quest-Gegenstände (Questlog, nachgeladene Gegenstände)
Core.Listen("EZQUEST_ITEMS_CHANGED", OneKey.Schedule, "ezMacro")

-- Schlossknacken gelungen: die Lage neu lesen – ezCore liest „Verschlossen“ je Platz frisch, die geknackte Kassette
-- ist dann offen und der Knopf öffnet sie; ein Schloss an einer Truhe oder Tür in der Welt lässt sie verschlossen.
-- Angemeldet nur, solange die Taste ein Schloss knacken soll.
local function IsPickLock(spellID)
    spellID = Num(Plain(spellID))
    if not spellID then return false end
    local name = ns.SpellName(OneKey.PICK_LOCK)
    return spellID == OneKey.PICK_LOCK or (name ~= nil and ns.SpellName(spellID) == name)
end

local function OnCastSucceeded(_, _, _, spellID)
    if pickTarget and IsPickLock(spellID) then OneKey.Schedule() end
end
local listening = false
function WatchPick(on)
    if on == listening then return end
    listening = on
    if on then
        ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", OnCastSucceeded)
    else
        ns.Off("UNIT_SPELLCAST_SUCCEEDED", OnCastSucceeded)
    end
end

ns.OnReady(function() OneKey.Schedule() end)
ns.OnSettingChanged(function(key)
    if key == "oneKeyConjure" or key == "oneKeyQuest" or key == "oneKeyOpen" or key == "oneKeyPet" or key == "petDemon"
        or key == "oneClickUpdate" then
        OneKey.Schedule()
    end
end)

-- Ein vergessener Twink (ezCore.ForgetChar): Häkchen und Futter gehen mit.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if key ~= nil and ns.db and type(ns.db.oneKey) == "table" then ns.db.oneKey[key] = nil end
end, "ezMacro")

---------------------------------------------------------------------------
-- Stand: Statuszeile („Stand zeigen“, /ezmacro status) und Werkzeug-Seiten
---------------------------------------------------------------------------

local function ItemText(id)
    return Core.ItemNameByID(id) or ("item:" .. tostring(id))
end

-- Stand eines Helfers als Text (liest die Lage frisch).
function OneKey.StatusText(kind)
    if OneKey.CONJURE[kind] then
        local text = OneKey.Conjure(kind)
        local s = last[kind] or {}
        if not text then return L.ONEKEY_STATE_unknown end
        if s.state == "use" then return L.ONEKEY_STATE_use:format(ItemText(s.item)) end
        -- Bedarf laut Client-Tabellen (OneKey.MissingReagents), Quelle kurz angehängt (Leitlinie 11); ohne Tabelle wie
        -- bisher der Seelensplitter
        local missing, source = OneKey.MissingReagents(kind)
        if source == "tables" then
            return missing and L.ONEKEY_STATE_cast_missing:format(OneKey.ReagentList(missing)) .. L.ONEKEY_REAGENT_SOURCE_SHORT
                or L.ONEKEY_STATE_cast
        end
        return s.noShard and L.ONEKEY_STATE_cast_noShard or L.ONEKEY_STATE_cast
    elseif kind == "questItem" then
        local text = OneKey.Quest()
        local s = last.questItem or {}
        if not text then return s.state == "noQuestLog" and L.DYN_noQuestLog or L.ONEKEY_QUEST_NONE end
        return L.ONEKEY_QUEST_USE:format(ItemText(s.item), s.title or "?", L["ONEKEY_QUEST_RANK" .. tostring(s.rank)])
    elseif kind == "open" then
        local plan, why, other = OneKey.OpenPlan()
        if not plan then
            if why == "otherOpen" then return L.ONEKEY_OPEN_OTHER:format(other or "?") end
            if why == "noDisenchant" then return L.ONEKEY_OPEN_noDisenchant end
            return L.ONEKEY_OPEN_NONE
        end
        return L["ONEKEY_OPEN_" .. plan.mode]:format(ItemText(plan.item))
    elseif kind == "pet" then
        local text = OneKey.Pet()
        local s = last.pet or {}
        if not text then return s.state == "noDemon" and L.DYN_no_demon or L.DYN_no_hunterPet end
        if s.state == "demon" then
            local missing, source = OneKey.MissingReagents("pet")
            if missing then
                -- Quelle kurz anhängen (Leitlinie 11); die ganze Zeile samt Build zeigt die Seite des Makros
                return L.ONEKEY_PET_DEMON_missing:format(L["OPT_DEMON_" .. s.demon], OneKey.ReagentList(missing))
                    .. (source == "tables" and L.ONEKEY_REAGENT_SOURCE_SHORT or "")
            end
            return L.ONEKEY_PET_DEMON:format(L["OPT_DEMON_" .. s.demon])
        end
        if s.state == "feed" then return L.ONEKEY_PET_FEED:format(ItemText(s.food)) end
        return L["ONEKEY_PET_" .. tostring(s.feed)] or L.ONEKEY_PET_READY
    end
    return ""
end

-- Welche Helfer für diese Klasse gelten (Herbeizaubern nur Magier und Hexenmeister, Begleiter nur Hexenmeister
-- und Jäger).
function OneKey.ConjureKinds()
    local kinds = {}
    for _, kind in ipairs(OneKey.CONJURE_ORDER) do
        if OneKey.CONJURE[kind].class == PlayerClass() then kinds[#kinds + 1] = kind end
    end
    return kinds
end

function OneKey.HasPet()
    local class = PlayerClass()
    return class == "WARLOCK" or class == "HUNTER"
end

ns.AddStatusLine(function()
    local lines = {}
    if not ns.db then return lines end
    local function Add(setting, title, kind)
        local state = OneKey.Active(setting) and OneKey.StatusText(kind) or OneKey.OffText(setting)
        lines[#lines + 1] = title .. ": " .. state
    end
    for _, kind in ipairs(OneKey.ConjureKinds()) do Add("oneKeyConjure", L["ONEKEY_TITLE_" .. kind], kind) end
    Add("oneKeyQuest", L.ONEKEY_TITLE_questItem, "questItem")
    return lines
end)

---------------------------------------------------------------------------
-- Werkzeug „Öffnen und Entzaubern“ (Reiter „Werkzeuge“): Ein/Aus, Stand, Rückfrage-Liste zum Anhaken
---------------------------------------------------------------------------

local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16:0:0|t "
local NO_CHECK = "|TInterface\\Buttons\\UI-CheckBox-Up:16:16:0:0|t "

local function Icon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or ns.DEFAULT_ICON
end

local function Quality(q) return Core.QualityName(q) end   -- ezCore (Gesamtreview 18.11.2026, T16-6)

local function DisenchantItems()
    local items = {}
    local S = Core.Salvage
    for _, item in ipairs(OneKey.Disenchantables()) do
        local sub = L.ONEKEY_DE_SUB:format(Quality(item.quality), item.ilvl or 0, item.count)
        local value = S and type(S.Value) == "function" and Num((S.Value(item.link or item.id, item.count))) or nil
        if value and value > 0 then sub = sub .. "  ·  " .. L.ONEKEY_DE_VALUE:format(Core.Money(value)) end
        if item.excluded == "lock" then
            sub = sub .. "  ·  " .. UI.Colored("ORANGE_FONT_COLOR", L.ONEKEY_DE_LOCK)
        elseif item.excluded == "set" then
            sub = sub .. "  ·  " .. UI.Colored("ORANGE_FONT_COLOR", L.ONEKEY_DE_SET:format(item.setName or "?"))
        end
        items[#items + 1] = {
            key = item.id, data = item, icon = Icon(item.id), grey = item.excluded ~= nil,
            text = ((item.ticked and not item.excluded) and CHECK or NO_CHECK) .. (item.link or ItemText(item.id)),
            sub = sub, tip = L.ONEKEY_DE_ROW_TIP,
        }
    end
    return items
end

local function ToggleSelected(panel)
    local row = panel.list:Selected()
    local item = row and row.data
    if not item or item.excluded then return end
    if item.ticked then
        OneKey.SetTicked(item.id, false)
        ns.Tools.RefreshKey("onekeyOpen")
        return
    end
    local function Tick()
        OneKey.SetTicked(item.id, true)
        ns.Tools.RefreshKey("onekeyOpen")
    end
    -- selten und besser: noch einmal fragen (Leitlinie: entzaubern nie ohne Bestätigung)
    if (item.quality or 0) >= 3 then
        Core.Confirm(L.ONEKEY_DE_CONFIRM:format(item.link or ItemText(item.id)), Tick)
    else
        Tick()
    end
end

local function OpenEntry() return ns.MACRO_BY_ID.onekey_open end

-- Belegte Taste eines Eintrags aus ezCores Tasten-Dienst (Welle 23, A9: oneKeyOpen und oneKeyFeed drücken die
-- sicheren Knöpfe OPEN_BUTTON/FEED_BUTTON – seit dem Gesamtreview 18.11.2026 über je einen Stellvertreter von ezCore,
-- der Blizzards „Aktion bei Tastendruck“ folgt (T9-NB1); die Ausführung liegt am Knopf, Keys.Register braucht es dafür
-- nicht) als Zusatz zum Stand: „ · Taste: F5“, leer ohne belegte Taste oder ohne Tasten-Dienst.
function OneKey.KeyHint(id)
    local keys = Core.Keys
    if not (keys and type(keys.KeyText) == "function" and type(keys.Get) == "function" and keys.Get(id)) then return "" end
    local text = Plain(Call(keys.KeyText, id))
    if type(text) ~= "string" or text == "" then return "" end
    return " · " .. L.ONEKEY_KEY:format(text)
end

ns.Tools.Register({
    key = "onekeyOpen", order = 45, place = "oneclick", icon = { "INV_Misc_Bag_10", "INV_Misc_QuestionMark" },
    name = L.ONEKEY_TITLE_open, why = L.ONEKEY_OPEN_WHY, desc = L.ONEKEY_OPEN_DESC,
    status = function()
        if not OneKey.Active("oneKeyOpen") then return OneKey.OffText("oneKeyOpen", true) end
        return OneKey.StatusText("open") .. OneKey.KeyHint("oneKeyOpen")
    end,
    build = function(panel)
        panel.enable = UI.SettingCheck(panel, "oneKeyOpen")
        panel.enable:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", -4, -4)
        panel.macro = UI.Button(panel, L.ONEKEY_TO_MACRO, 120, function()
            local entry = OpenEntry()
            if entry then ns.Browser.ShowEntry(entry) end
        end, L.ONEKEY_TO_MACRO, L.ONEKEY_TO_MACRO_TIP)
        panel.macro:SetPoint("TOPRIGHT", panel.top, "BOTTOMRIGHT", 0, -6)
        panel.tick = UI.Button(panel, L.ONEKEY_DE_TICK, 130, function() ToggleSelected(panel) end,
            L.ONEKEY_DE_TICK, L.ONEKEY_DE_TICK_TIP)
        panel.tick:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -2)
        panel.clear = UI.Button(panel, L.ONEKEY_DE_CLEAR, 130, function()
            OneKey.ClearTicks()
            ns.Tools.RefreshKey("onekeyOpen")
        end, L.ONEKEY_DE_CLEAR, L.ONEKEY_DE_CLEAR_TIP)
        panel.clear:SetPoint("LEFT", panel.tick, "RIGHT", 4, 0)
        panel.list = UI.List(panel, "ezMacroOneKeyDisenchantList", panel.width,
            function() ns.Tools.RefreshKey("onekeyOpen") end, function() ToggleSelected(panel) end)
        panel.list.frame:SetPoint("TOPLEFT", panel.enable, "BOTTOMLEFT", 4, -6)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 26)
    end,
    refresh = function(panel)
        panel.enable.Refresh()
        panel.list:SetItems(DisenchantItems(), L.ONEKEY_DE_EMPTY)
        local row = panel.list:Selected()
        local item = row and row.data
        panel.tick:SetEnabled(item ~= nil and not item.excluded)
        panel.tick:SetText(item and item.ticked and L.ONEKEY_DE_UNTICK or L.ONEKEY_DE_TICK)
        panel.macro:SetEnabled(OpenEntry() ~= nil)
    end,
})

---------------------------------------------------------------------------
-- Werkzeug „Begleiter“ (nur Hexenmeister und Jäger): Dämon wählen bzw. Futter anhaken, Stand
---------------------------------------------------------------------------

local function FoodItems()
    local items = {}
    for _, item in ipairs(OneKey.FoodCandidates()) do
        items[#items + 1] = { key = item.id, data = item, icon = Icon(item.id),
            text = (item.ticked and CHECK or NO_CHECK) .. (item.link or ItemText(item.id)),
            sub = L.ONEKEY_FOOD_SUB:format(item.count), tip = L.ONEKEY_FOOD_ROW_TIP }
    end
    return items
end

-- Was das Tier frisst (Blizzards Text je Art, C_PetInfo.GetPetFoodTypes: eine Tabelle; die alte Globale als Rückfall
-- gab die Texte einzeln zurück) | nil
function OneKey.Diet()
    local api = rawget(_G, "C_PetInfo")
    local types = { Call(type(api) == "table" and api.GetPetFoodTypes or rawget(_G, "GetPetFoodTypes")) }
    local first = Plain(types[1])
    if type(first) == "table" then types = first end
    local names = {}
    for i = 1, #types do
        local value = Plain(types[i])
        if type(value) == "string" and value ~= "" then names[#names + 1] = value end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

local function DemonMenu(owner)
    Core.Menu.Open(owner, function(root)
        for _, demon in ipairs(OneKey.DEMONS) do
            local entry = Core.Menu.Radio(root, L["OPT_DEMON_" .. demon.key],
                function() return OneKey.Demon().key end,
                function(value)
                    ns.SetSetting("petDemon", value)
                    ns.Tools.RefreshKey("onekeyPet")
                end, demon.key)
            if not ns.IsSpellKnown(demon.spell) then Core.Menu.Tip(entry, L["OPT_DEMON_" .. demon.key], L.ONEKEY_DEMON_UNKNOWN) end
        end
    end)
end

ns.Tools.Register({
    key = "onekeyPet", order = 46, place = "oneclick", icon = { "Ability_Hunter_BeastCall", "Spell_Shadow_SummonImp" },
    name = L.ONEKEY_TITLE_pet, why = L.ONEKEY_PET_WHY, desc = L.ONEKEY_PET_DESC,
    shown = function() return OneKey.HasPet() end,
    status = function()
        if not OneKey.Active("oneKeyPet") then return OneKey.OffText("oneKeyPet", PlayerClass() == "HUNTER") end
        return OneKey.StatusText("pet") .. (PlayerClass() == "HUNTER" and OneKey.KeyHint("oneKeyFeed") or "")
    end,
    build = function(panel)
        panel.enable = UI.SettingCheck(panel, "oneKeyPet")
        panel.enable:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", -4, -4)
        panel.macro = UI.Button(panel, L.ONEKEY_TO_MACRO, 120, function()
            local entry = ns.MACRO_BY_ID.onekey_pet
            if entry then ns.Browser.ShowEntry(entry) end
        end, L.ONEKEY_TO_MACRO, L.ONEKEY_TO_MACRO_TIP)
        panel.macro:SetPoint("TOPRIGHT", panel.top, "BOTTOMRIGHT", 0, -6)
        panel.demon = UI.Button(panel, L.ONEKEY_DEMON, 160, function(self) DemonMenu(self) end,
            L.ONEKEY_DEMON, L.OPT_petDemon_TIP)
        panel.demon:SetPoint("TOPLEFT", panel.enable, "BOTTOMLEFT", 4, -6)
        panel.info = UI.Text(panel, "GameFontHighlightSmall", panel.width)
        panel.info:SetPoint("TOPLEFT", panel.enable, "BOTTOMLEFT", 4, -6)
        panel.tick = UI.Button(panel, L.ONEKEY_FOOD_TICK, 130, function()
            local row = panel.list:Selected()
            local item = row and row.data
            if item then
                OneKey.SetFood(item.id, not item.ticked)
                ns.Tools.RefreshKey("onekeyPet")
            end
        end, L.ONEKEY_FOOD_TICK, L.ONEKEY_FOOD_TICK_TIP)
        panel.tick:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -2)
        panel.list = UI.List(panel, "ezMacroOneKeyFoodList", panel.width,
            function() ns.Tools.RefreshKey("onekeyPet") end, function(item)
                OneKey.SetFood(item.data.id, not item.data.ticked)
                ns.Tools.RefreshKey("onekeyPet")
            end)
        panel.list.frame:SetPoint("TOPLEFT", panel.info, "BOTTOMLEFT", 0, -6)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 26)
    end,
    refresh = function(panel)
        panel.enable.Refresh()
        local warlock = PlayerClass() == "WARLOCK"
        panel.demon:SetShown(warlock)
        panel.demon:SetText(L.ONEKEY_DEMON_BUTTON:format(L["OPT_DEMON_" .. OneKey.Demon().key]))
        panel.info:SetShown(not warlock)
        panel.list.frame:SetShown(not warlock)
        panel.tick:SetShown(not warlock)
        panel.macro:SetEnabled(ns.MACRO_BY_ID.onekey_pet ~= nil)
        if warlock then return end
        local diet = OneKey.Diet()
        local happiness = OneKey.Happiness()
        panel.info:SetText(L.ONEKEY_FOOD_DIET:format(diet or L.ONEKEY_FOOD_DIET_NONE) .. "\n"
            .. L.ONEKEY_FOOD_HAPPY:format(happiness and L["ONEKEY_HAPPY_" .. happiness] or L.ONEKEY_HAPPY_unknown))
        panel.list:SetItems(FoodItems(), L.ONEKEY_FOOD_EMPTY)
        local row = panel.list:Selected()
        panel.tick:SetEnabled(row ~= nil)
        panel.tick:SetText(row and row.data.ticked and L.ONEKEY_FOOD_UNTICK or L.ONEKEY_FOOD_TICK)
    end,
})
