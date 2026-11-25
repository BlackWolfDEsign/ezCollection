local ADDON, ns = ...
local Core = ezCore
local Data = ns.Data

--[[
    „Was kommt wann“ und „Wo kommt was“ für den gewählten Beruf (Nutzer am 24.11.2026, wörtlich: „wtf ich habe doch gesagt
    Berufelehrer gehören ins Berufefenster "wo kommt was" ebenso für "was kommt wann"“, „wenn beruf ausgewählt dann zeige
    die beiden reiter im unteren rechteck an“, „DAS MUSST DU SINNVOLL UND LOGISCH AUFTEILEN; NUR NICHT ZUVIELE REITER ABER
    DENNOCH ÜBERSICHTLICH JE REITER“). Hier nur die Daten; gezeichnet wird in Panel.lua (zwei Symbol-Reiter unter den
    vorhandenen, solange ein Beruf gewählt ist). Die Ansicht „Fehlend“ ist darin aufgegangen: was noch fehlt und ab wann
    steht unter „Was kommt wann“, wo es das gibt unter „Wo kommt was“.

    Aufteilung zum Zauberbuch (ezMerchant): dort Klassenlehrer, Waffenmeister, Reitlehrer, Begleiter, Klassenquests und
    Bücher; hier alles zu den Berufen. Gemeinsam: die Lehrer-Orte aus ezCore (Core.TrainerSpots).

    Gewählter Beruf (Teach.Current): der, dessen Rezepte Blizzards Berufefenster zeigt; auf Blizzards Seite „Berufe“ (kein
    Beruf gewählt) keiner – außer einem Sammelberuf, der über den Knopf „Fundorte“ gewählt wurde (Kräuterkunde und
    Kürschnerei haben in Forever kein eigenes Fenster), bis die Seite wechselt.

    Quellen (Leitlinie 11), jede Angabe nennt ihre: Angebote der Berufslehrer, die du besucht hast
    (Knowledge.ProfessionOffers: Fertigkeit, Stufe, Preis), die nicht erlernten Rezepte in Blizzards Berufefenster
    (Where.ToLearn: Fundorte laut eigenem Besuch, Questie, AtlasLoot, Blizzards Text), die Lehrer-Orte (besucht bzw. laut
    Questie über ezMap).

      Teach.Open()            → gewählter Beruf des Berufefensters { key, name, rank, max, icon, own, foreign } oder nil;
                                foreign: fremdes Fenster (Link, Gilde, NPC-Werkbank) – ohne deinen Rang und deine Angebote
      Teach.Pick(key), Unpick → Sammelberuf auf der Seite „Berufe“ wählen bzw. vergessen
      Teach.Current()         → Beruf oder nil
      Teach.When(prof)        → { now, later, unknown, seen, missing (Rezepte der Fensterliste), total, window, rank, max } –
                                je Eintrag { id, name, icon, skill, approx, lvl, price, rankSpell, npcName, where, source,
                                reach }
      Teach.Where(prof)       → { trainers, pending, withMap, zones = { { name, map, mine, list } }, noplace, taught, blind }
      Teach.OnlyTrainer(e, angeboten) → lehrt das Rezept nur der Berufslehrer? (Blizzards Quellentext allein macht es
                                nicht zum anderen Fundort)
]]

local Teach = {}
ns.Teach = Teach

local Num, Plain, Call = Core.Num, Core.Plain, Core.Call

Teach.SCAN = 80           -- ohne Rezeptliste (Sammelberuf): so viele Rezepte fragt ezCore nach Fundorten

local function Knowledge(name)
    local K = Core.Knowledge
    local fn = K and K[name]
    return type(fn) == "function" and fn or nil
end

local function OwnProfessions()
    local fn = Knowledge("OwnProfessions")
    if not fn then return {} end
    local ok, list = pcall(fn)
    if not ok then
        ns.Error(list, "Teach.OwnProfessions")
        return {}
    end
    return type(list) == "table" and list or {}
end

local function Own(key)
    for _, prof in ipairs(OwnProfessions()) do
        if prof.key == key then
            return { key = key, name = prof.name or key, rank = Num(prof.rank), max = Num(prof.max), icon = prof.icon, own = true }
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Gewählter Beruf
---------------------------------------------------------------------------

local picked

function Teach.Pick(key)
    picked = type(key) == "string" and key or nil
    return picked
end
function Teach.Unpick() picked = nil end
function Teach.Picked() return picked end

-- Beruf der Rezeptliste im Berufefenster (Blizzards GetBaseProfessionInfo: professionID ist die Fertigkeitslinie), auch
-- bei einem fremden (Link, Gilde) – dann own = false und ohne Rang.
function Teach.Open()
    local panel = ns.Panel
    if not (panel and panel.CraftingShown and panel.CraftingShown()) then return nil end
    local api = C_TradeSkillUI
    local info = api and Plain(Call(api.GetBaseProfessionInfo))
    if type(info) ~= "table" then return nil end
    local line, name = Num(Plain(info.professionID)), Plain(info.professionName)
    if type(name) ~= "string" or name == "" then name = nil end
    local ofLine, ofName = Knowledge("ProfessionOfLine"), Knowledge("ProfessionOfName")
    local key = line and ofLine and Call(ofLine, line) or nil
    if not key and name and ofName then key = Call(ofName, name) end
    local P = Core.Professions
    local foreign = P ~= nil and type(P.IsForeignTradeSkill) == "function" and Call(P.IsForeignTradeSkill) == true
    if type(key) ~= "string" then
        if not name then return nil end
        return { key = nil, name = name, own = false, foreign = foreign or nil }
    end
    if foreign then return { key = key, name = name or key, own = false, foreign = true } end
    local prof = Own(key)
    if prof then return prof end
    return { key = key, name = name or key, rank = nil, max = nil, own = false }
end

function Teach.Current()
    local open = Teach.Open()
    if open then return open end
    local panel = ns.Panel
    if picked and panel and panel.OnBook and panel.OnBook() then return Own(picked) end
    return nil
end

-- Rezeptliste des Fensters da? Sonst (Sammelberuf auf der Seite „Berufe“) gälte die Liste des zuletzt offenen Berufs.
local function HasWindow()
    local panel = ns.Panel
    return panel ~= nil and panel.CraftingShown ~= nil and panel.CraftingShown() and true or false
end

local function ToLearn()
    if not HasWindow() then return {}, 0, nil end
    return ns.Where.ToLearn()
end

local function Offers(prof)
    local fn = prof and prof.key and not prof.foreign and Knowledge("ProfessionOffers")
    if not fn then return {}, nil end
    local ok, list, seen = pcall(fn, prof.key)
    if not ok then
        ns.Error(list, "Teach.ProfessionOffers")
        return {}, nil
    end
    return type(list) == "table" and list or {}, seen
end

---------------------------------------------------------------------------
-- Was kommt wann
---------------------------------------------------------------------------

local function BySkill(a, b)
    if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
    if (a.rankSpell and 0 or 1) ~= (b.rankSpell and 0 or 1) then return a.rankSpell == true end
    return tostring(a.name or "") < tostring(b.name or "")
end

-- Jetzt (1), Rang unbekannt (2) oder zu hoch (3)? Ohne verlangte Fertigkeit: jetzt.
local function Reach(skill, rank)
    if not skill or skill <= 0 then return 1 end
    if not rank then return 2 end
    return skill <= rank and 1 or 3
end

function Teach.When(prof)
    local list, total, winRank = ToLearn()
    local offers, seen = Offers(prof)
    local rank = winRank or (prof and prof.rank) or nil
    local level = Core.PlayerLevel and Core.PlayerLevel() or 1
    local out = { now = {}, later = {}, unknown = {}, seen = seen, total = total, window = HasWindow(), rank = rank,
        max = prof and prof.max, all = 0, missing = #list }
    local byID, done = {}, {}
    for _, o in ipairs(offers) do
        if o.id then byID[o.id] = o end
    end
    local function Put(e)
        out.all = out.all + 1
        local tooLow = (e.lvl or 0) > level
        if e.reach == 1 and not tooLow then
            out.now[#out.now + 1] = e
        elseif e.reach == 2 and not tooLow then
            out.unknown[#out.unknown + 1] = e
        else
            out.later[#out.later + 1] = e
        end
    end
    for _, m in ipairs(list) do
        local o = byID[m.recipeID]
        done[m.recipeID] = true
        local e = { id = m.recipeID, name = m.name, icon = m.icon, skill = m.skill, approx = m.approx, where = m.where,
            source = m.source, reach = m.reach }
        if o then     -- der Lehrer nennt Fertigkeit, Stufe und Preis genau
            e.skill, e.approx = (o.skill or 0) > 0 and o.skill or nil, false
            e.lvl, e.price, e.npcName, e.reach = o.lvl, o.price, o.npcName, Reach(o.skill, rank)
        end
        Put(e)
    end
    for _, o in ipairs(offers) do     -- Ränge („Geselle“) und Rezepte, die das Fenster nicht zeigt
        if not o.learned and not done[o.id or ""] then
            Put({ id = o.id, name = o.name, icon = o.icon, skill = o.skill, lvl = o.lvl, price = o.price,
                rankSpell = o.rankSpell, npcName = o.npcName, where = {}, reach = Reach(o.skill, rank) })
        end
    end
    table.sort(out.now, BySkill)
    table.sort(out.later, BySkill)
    return out
end

---------------------------------------------------------------------------
-- Wo kommt was
---------------------------------------------------------------------------

-- Nennt Blizzards Quellentext einen Lehrer („Lehrer“, „Trainer“)? Die Client-Sprachen der Sammlung: deutsch, englisch.
local function TrainerText(text)
    local line = Data.SourceFirstLine(text)
    line = type(line) == "string" and line:lower() or ""
    return line:find("lehrer", 1, true) ~= nil or line:find("trainer", 1, true) ~= nil
end

-- Nur der Berufslehrer lehrt es: kein Fundort außer Lehrern, und wenigstens einer davon, ein gesehenes Angebot oder
-- Blizzards Text nennt einen Lehrer. Blizzards Text (kind "text") hängt ezCore an jede Liste – er ist kein Ort.
function Teach.OnlyTrainer(e, offered)
    local trainer = offered == true
    for _, w in ipairs(e.where or {}) do
        if w.kind == "trainer" then
            trainer = true
        elseif w.kind ~= "text" then
            return false
        end
    end
    return trainer or TrainerText(e.source)
end

-- Bester Fundort abseits der Lehrer: erst dein Gebiet, dann der erste mit Kartenpunkt, dann der erste mit Gebiet
-- → Fundort mit Gebiet oder nil, sonst erster Fundort (auch Blizzards Text)
function Teach.BestPlace(e)
    local rest, text, zone, area = {}, nil, Data.PlayerZone(), nil
    for _, w in ipairs(e.where or {}) do
        if w.kind == "text" then
            text = text or w
        elseif w.kind ~= "trainer" then
            rest[#rest + 1] = w
            if Num(w.map) and (not area or (zone and w.map == zone and area.map ~= zone)) then area = w end
        end
    end
    return ns.Where.Best(rest) or area, rest[1] or text
end

-- Einträge ohne Fenster (Sammelberuf): Rezepte, zu denen ezCore Fundorte abseits der Lehrer kennt
local function Elsewhere(prof)
    local fn = prof.key and Knowledge("RecipesElsewhere")
    if not fn then return {} end
    local ok, list = pcall(fn, prof.key, prof.rank, { limit = Teach.SCAN, scan = Teach.SCAN })
    if not ok then
        ns.Error(list, "Teach.RecipesElsewhere")
        return {}
    end
    local out = {}
    for _, r in ipairs(type(list) == "table" and list or {}) do
        local skill, approx = ns.Where.Skill(r.id, r.where)
        local reach = not skill and 2 or ((prof.rank and skill <= prof.rank) and 1 or (approx and 2 or 3))
        out[#out + 1] = { recipeID = r.id, name = r.name or ("#" .. tostring(r.id)), where = r.where or {}, skill = skill,
            approx = approx, reach = reach }
    end
    return out
end

function Teach.Trainers(prof)
    local TS = Core.TrainerSpots
    if not (prof and prof.key and type(TS) == "table" and type(TS.List) == "function") then return {}, false, false end
    local ok, list, pending, withMap = pcall(TS.List, "prof:" .. prof.key)
    if not ok then
        ns.Error(list, "Teach.Trainers")
        return {}, false, false
    end
    list = type(list) == "table" and list or {}
    -- ohne ezMap kennt ezCore keine Entfernung: dein Gebiet nach vorn
    local zone = Data.PlayerZone()
    if zone and #list > 1 and not list[1].distance then
        local mine, rest = {}, {}
        for _, t in ipairs(list) do
            local into = t.map == zone and mine or rest
            into[#into + 1] = t
        end
        for _, t in ipairs(rest) do mine[#mine + 1] = t end
        list = mine
    end
    return list, pending == true, withMap == true
end

function Teach.Where(prof)
    local out = { zones = {}, noplace = {}, taught = 0, blind = 0, window = HasWindow(), rank = prof and prof.rank }
    if not prof then
        out.trainers = {}
        return out
    end
    out.trainers, out.pending, out.withMap = Teach.Trainers(prof)
    local list, _, winRank = ToLearn()
    if not out.window then list = Elsewhere(prof) end
    out.rank = winRank or prof.rank
    local offered = {}
    for _, o in ipairs((Offers(prof))) do
        if o.id then offered[o.id] = true end
    end
    local zone = Data.PlayerZone()
    local byZone = {}
    for _, e in ipairs(list) do
        if Teach.OnlyTrainer(e, offered[e.recipeID]) then
            out.taught = out.taught + 1
        else
            local best, first = Teach.BestPlace(e)
            if best then
                local z = byZone[best.map]
                if not z then
                    z = { map = best.map, name = Core.MapName(best.map) or best.zone or ("#" .. tostring(best.map)),
                        mine = zone ~= nil and best.map == zone, list = {} }
                    byZone[best.map] = z
                    out.zones[#out.zones + 1] = z
                end
                z.list[#z.list + 1] = { entry = e, place = best }
            elseif first or (type(e.source) == "string" and e.source ~= "") then
                out.noplace[#out.noplace + 1] = { entry = e, place = first }
            else
                out.blind = out.blind + 1
            end
        end
    end
    table.sort(out.zones, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.name ~= b.name then return a.name < b.name end
        return a.map < b.map
    end)
    return out
end
