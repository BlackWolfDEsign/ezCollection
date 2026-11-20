local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Rezepte und ihre Fundorte (Welle 15b; Wunsch des Nutzers vom 15.11.2026 abends: „rezepte und deren fundorte mit
    ablegen und entsprechend anzeigen / bereitstellen“). Die Daten liegen in ezCore (Knowledge.RecipeWhere: besuchte
    Händler und Lehrer, eigene Beute, QuestieDB zur Laufzeit, Blizzards Quellentext – jede Angabe mit Quelle,
    Leitlinie 11); ezCraft zeigt sie nur:

      Berufefenster  Reiter „Rezept“: bei nicht gelernten Rezepten der Abschnitt „Woher“ mit den Fundorten und dem
                     Kartenknopf „Auf der Karte zeigen“ (Blizzards Weltkarte am Ort, auf Wunsch Blizzards Wegpunkt,
                     Schalter recipeWaypoint); Reiter „Fehlend“ als Liste „Noch zu lernen“ mit Fundort und Stufe,
                     sortiert nach Erreichbarkeit (eigene Fertigkeit, dann dein Gebiet)
      Tooltip        auf Rezept-Gegenständen (Pläne, Muster, Formeln …): „Erhältlich bei: Händler (Gebiet), laut eigenem
                     Besuch“ bzw. „laut Questie“; „Schon gelernt: du, Mira“ bzw. „lernbar ab Fertigkeit n“ mit dem Rang
                     deiner Charaktere in diesem Beruf (ezCore-Charakterdaten, Knowledge.CharProfs)

      Where.List(recipeID, itemID)  → Einträge von Knowledge.RecipeWhere (leer ohne ezCore-Teil)
      Where.Line(e)                 → „Händler: Name (Gebiet) – 1g, begrenzt (2) · bei dir“
      Where.Best(list)              → Eintrag mit Ort zum Zeigen (dein Gebiet zuerst) oder nil
      Where.Show(e)                 → Weltkarte am Ort, Wegpunkt auf Wunsch → true | false, Grund
      Where.ToLearn()               → nicht gelernte Rezepte des offenen Berufs mit where, skill, reach
      Where.TooltipLines(itemID)    → Zeilen { left, color } für den Tooltip eines Rezept-Gegenstands
      Where.TipLine(e)              → „Erhältlich bei: Name (Gebiet), laut eigenem Besuch“ bzw. „Lehrer: …, laut …“
    Entdecker-Wissen (seltene Beute) fragt ezCraft nicht eigens an: ezCore liefert es nur mit „Entdecker-Wissen“.
]]

local Where = {}
ns.Where = Where

Where.MAX_LINES = 4      -- so viele Fundorte zeigt der Reiter „Rezept“ (der Tooltip der Zeile nennt alle)
Where.TIP_MAX = 3        -- so viele „Erhältlich bei“-Zeilen im Tooltip eines Rezept-Gegenstands

local Num, Plain, Call = Core.Num, Core.Plain, Core.Call

local function Knowledge(name)
    local K = Core.Knowledge
    local fn = K and K[name]
    return type(fn) == "function" and fn or nil
end

function Where.Available() return Knowledge("RecipeWhere") ~= nil end

function Where.List(recipeID, itemID)
    local fn = Knowledge("RecipeWhere")
    if not fn then return {} end
    local list = Call(fn, Num(recipeID), { item = Num(itemID) })
    return type(list) == "table" and list or {}
end

-- Quelle in ezCraft-Worten: „laut eigenem Besuch“ für selbst Gesehenes, sonst ezCores Wortlaut („laut Questie“)
function Where.SourceText(e)
    if type(e) ~= "table" then return nil end
    if e.sourceKey == "own" then return L.WHERE_OWN end
    return type(e.source) == "string" and e.source or nil
end

function Where.Line(e)
    local fn = Knowledge("WhereText")
    local text = fn and Plain(Call(fn, e)) or nil
    if not text then return nil end
    local extra = {}
    if Num(e.price) and e.price > 0 then extra[#extra + 1] = Core.Money(e.price) end
    if Num(e.limited) then extra[#extra + 1] = L.WHERE_LIMITED:format(e.limited) end
    if Num(e.skill) and e.skill > 0 then extra[#extra + 1] = L.WHERE_SKILL:format(e.skill) end
    if e.gone then extra[#extra + 1] = L.WHERE_GONE end
    if #extra > 0 then text = text .. " – " .. table.concat(extra, ", ") end
    local src = Where.SourceText(e)
    if src then text = text .. " · " .. src end
    return text
end

-- Ein Ort zum Zeigen: erst dein Gebiet, dann der erste Eintrag mit Karte und Lage
function Where.Best(list)
    local zone = Data.PlayerZone()
    local first
    for _, e in ipairs(list or {}) do
        if Num(e.map) and Num(e.x) and Num(e.y) then
            if zone and e.map == zone then return e end
            first = first or e
        end
    end
    return first
end

-- Blizzards Wegpunkt: über ezMap (merkt Titel und Verlauf), sonst Blizzards C_Map direkt → true | false
local function SetWaypoint(e)
    local api = Core.API("ezMap")
    if type(api) == "table" and type(api.SetWaypoint) == "function" then
        local ok, done = pcall(api.SetWaypoint, e.map, e.x, e.y, e.name)
        return ok and done == true
    end
    local M = rawget(_G, "C_Map")
    if type(M) ~= "table" or type(M.SetUserWaypoint) ~= "function" then return false end
    if type(M.CanSetUserWaypointOnMap) == "function" and not Call(M.CanSetUserWaypointOnMap, e.map) then return false end
    local point
    local P = rawget(_G, "UiMapPoint")
    if type(P) == "table" and type(P.CreateFromCoordinates) == "function" then
        point = Call(P.CreateFromCoordinates, e.map, e.x, e.y)
    end
    point = point or { uiMapID = e.map, position = { x = e.x, y = e.y } }
    local ok, wasSet = pcall(M.SetUserWaypoint, point)
    return ok and wasSet ~= false
end

function Where.Show(e)
    if type(e) ~= "table" or not (Num(e.map) and Num(e.x) and Num(e.y)) then
        ns.Print(L.WHERE_SHOW_NONE)
        return false, "noplace"
    end
    local zone = Core.MapName(e.map) or "?"
    local name = e.name or "?"
    local opened, why
    if ns.InCombat() then
        -- im Kampf öffnet Blizzard die Karte nicht: danach nachholen (der Wegpunkt geht sofort)
        why = "combat"
        ns.AfterCombat(function() Core.OpenPanel("map", e.map, true) end, "WhereShow")
    else
        opened, why = Core.OpenPanel("map", e.map, true)
    end
    if not opened and why ~= "combat" then
        ns.Print(L.WHERE_SHOW_FAIL:format(name, zone))
        return false, why or "nomap"
    end
    local marked = ns.Enabled("recipeWaypoint") and SetWaypoint(e) or false
    if why == "combat" then
        -- ezCores Satz „… kommt gleich nach dem Kampf.“ (T18-1), der Wegpunkt als eigene Zeile
        Core.CombatNotice(ns, L.WHERE_SHOW_MAP:format(name, zone), "later")
        if marked then ns.Print(L.WHERE_SHOW_MARKED) end
    else
        local text = L.WHERE_SHOW_OK:format(name, zone)
        if marked then text = text .. " " .. L.WHERE_SHOW_MARKED end
        ns.Print(text)
    end
    return true, { marked = marked, later = why == "combat" or nil }
end

---------------------------------------------------------------------------
-- Noch zu lernen: nicht gelernte Rezepte des offenen Berufs, sortiert nach Erreichbarkeit
---------------------------------------------------------------------------

-- Fertigkeit im offenen Beruf (Unterberuf zuerst, dann der Beruf; nil ohne Fenster)
function Where.Rank()
    local api = C_TradeSkillUI
    if not api then return nil end
    for _, fn in ipairs({ api.GetChildProfessionInfo, api.GetBaseProfessionInfo }) do
        local info = Plain(Call(fn))
        local rank = type(info) == "table" and Num(Plain(info.skillLevel)) or nil
        if rank and rank > 0 then return rank end
    end
    return nil
end

-- Benötigte Fertigkeit: Lehrer (Angebot), sonst der Rezept-Gegenstand laut Item-Wissen, sonst die beobachtete Grenze
-- „orange ab“ (Knowledge.SkillStages). Die ist immer ungefähr: Sie ist die niedrigste Fertigkeit, bei der ein Charakter,
-- der das Rezept schon kannte, es orange sah – also höchstens zu hoch. SkillStages nennt orange als „genau“, sobald es
-- einmal gesehen wurde (orange ist die erste Farbe); das gilt für die Farbgrenzen, nicht für die Lernstufe.
-- Welle 26 (F2): Nennen ezCores Client-Tabellen „lernbar ab“ (Knowledge.RecipeStages, Quelle "client" – nur bei einem
-- Wert über 1, 1 ist auf Forever ein Platzhalter), ist das die Lernstufe laut Client und genau; sie geht der
-- Beobachtung vor.
-- → Zahl, ungefähr?
function Where.Skill(recipeID, list)
    for _, e in ipairs(list or {}) do
        if Num(e.skill) and e.skill > 0 then return e.skill, false end
    end
    local item = Knowledge("RecipeItem") and Call(Knowledge("RecipeItem"), recipeID)
    local get = Knowledge("Get")
    local f = item and get and Plain(Call(get, item))
    local r = type(f) == "table" and f.recipe
    if type(r) == "table" and Num(r.skill) then return r.skill, false end
    local client = Knowledge("RecipeStages") and Plain(Call(Knowledge("RecipeStages"), recipeID))
    if type(client) == "table" and Num(client.orange) and type(client.source) == "table"
        and client.source.orange == "client" then
        return client.orange, false
    end
    local stages = Knowledge("SkillStages") and Plain(Call(Knowledge("SkillStages"), recipeID))
    if type(stages) == "table" and Num(stages.orange) then return stages.orange, true end
    return nil
end

-- reach: 1 jetzt lernbar, 2 Stufe unbekannt (auch: nur beobachtete Stufe über deiner Fertigkeit – vielleicht schon
-- lernbar), 3 Fertigkeit zu niedrig; inZone: ein Fundort in deinem Gebiet
-- Fundorte und Stufe je Rezept bleiben gemerkt, solange Data.MissingRecipes dieselbe Liste liefert (sie gilt bis zur
-- nächsten Meldung des Berufefensters bzw. „Neu lesen“) – sonst fragte jedes Auffrischen alle Händler neu.
local known = { list = nil, by = {} }
function Where.Forget() known = { list = nil, by = {} } end

function Where.ToLearn()
    local list, total = Data.MissingRecipes()
    if known.list ~= list then known = { list = list, by = {} } end
    local rank, zone = Where.Rank(), Data.PlayerZone()
    local out = {}
    for _, m in ipairs(list) do
        local hit = known.by[m.recipeID]
        if not hit then
            local w = Where.List(m.recipeID)
            hit = { where = w }
            hit.skill, hit.approx = Where.Skill(m.recipeID, w)
            known.by[m.recipeID] = hit
        end
        local where, skill, approx = hit.where, hit.skill, hit.approx
        local reach = not skill and 2 or ((rank and skill <= rank) and 1 or (approx and 2 or 3))
        local inZone, located = false, false
        for _, e in ipairs(where) do
            if Num(e.map) then
                located = true
                if zone and e.map == zone then inZone = true end
            end
        end
        out[#out + 1] = { recipeID = m.recipeID, name = m.name, icon = m.icon, source = m.source, where = where,
            skill = skill, approx = approx, reach = reach, inZone = inZone, located = located }
    end
    table.sort(out, function(a, b)
        if a.reach ~= b.reach then return a.reach < b.reach end
        if a.inZone ~= b.inZone then return a.inZone end
        if a.located ~= b.located then return a.located end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
        return a.name < b.name
    end)
    return out, total, rank
end

-- Kurzform der Stufe für die Liste: „ab 75“, „ab ~75“ bzw. „ab 75 (noch 20)“
function Where.SkillText(entry, rank)
    if not entry.skill then return nil end
    local text = (entry.approx and L.WHERE_FROM_APPROX or L.WHERE_FROM):format(entry.skill)
    if rank and entry.skill > rank then text = text .. " " .. L.WHERE_MORE:format(entry.skill - rank) end
    return text
end

---------------------------------------------------------------------------
-- Tooltip eines Rezept-Gegenstands
---------------------------------------------------------------------------

-- Farben der Zeilen sind Rollen (Core.Style.COLOR, dazu "hint" = Core.GREY), gezeichnet über ns.TipLines (Welle 23, A2)


local SHOWN = { vendor = true, trainer = true, quest = true, drop = true, object = true, container = true }

-- Eine Zeile „Erhältlich bei“: Händler ohne doppelte Art-Vorsilbe („Erhältlich bei: Name (Gebiet), laut eigenem
-- Besuch“), andere Arten mit ihrer eigenen („Lehrer: Name (Gebiet), laut …“, Blizzards Text „…, laut Client“)
function Where.TipLine(e)
    local src = Where.SourceText(e) or "?"
    if e.kind == "vendor" then
        local name = e.name or (e.id and ("#" .. tostring(e.id))) or "?"
        return L.TIP_WHERE:format(e.zone and (name .. " (" .. e.zone .. ")") or name, src)
    end
    local fn = Knowledge("WhereText")
    local text = fn and Plain(Call(fn, e))
    return text and L.TIP_FROM:format(text, src) or nil
end

-- Rang je Charakter im Beruf des Rezepts (ezCore: Knowledge.CharProfs) – nur Charaktere mit dem Beruf
local function Ranks(prof)
    local fn = Knowledge("CharProfs")
    local out = {}
    if not (fn and prof) then return out end
    for key in pairs(Core.Chars and Core.Chars() or {}) do
        local map = Plain(Call(fn, key))
        local rank = type(map) == "table" and Num(map[prof]) or nil
        if rank then out[#out + 1] = { key = key, rank = rank } end
    end
    table.sort(out, function(a, b)
        if (a.key == Core.charKey) ~= (b.key == Core.charKey) then return a.key == Core.charKey end
        return a.key < b.key
    end)
    return out
end

function Where.TooltipLines(itemID)
    local out = {}
    itemID = Num(itemID)
    local profFn = Knowledge("RecipeItemProfession")
    local prof = itemID and profFn and Plain(Call(profFn, itemID))
    if not prof then return out end
    local recipeID = Knowledge("RecipeOfItem") and Num(Plain((Call(Knowledge("RecipeOfItem"), itemID))))
    local n = 0
    local where = Where.List(recipeID, itemID)
    for _, e in ipairs(where) do
        if SHOWN[e.kind] and n < Where.TIP_MAX then
            local text = Where.TipLine(e)
            if text then
                n = n + 1
                out[#out + 1] = { left = text, color = "normal" }
            end
        end
    end
    -- ohne eigene oder fremde Fundorte: Blizzards Quellentext (Leitlinie 11: der Client zuerst)
    if n == 0 then
        for _, e in ipairs(where) do
            local text = e.kind == "text" and Where.TipLine(e)
            if text then
                n = n + 1
                out[#out + 1] = { left = text, color = "normal" }
                break
            end
        end
    end
    -- Gelernt bzw. lernbar ab – für dich und deine Twinks (nur, wer den Beruf hat)
    local crafters = recipeID and Knowledge("Crafters") and Plain(Call(Knowledge("Crafters"), recipeID)) or {}
    local known = {}
    for _, key in ipairs(type(crafters) == "table" and crafters or {}) do known[key] = true end
    local names = {}
    for _, key in ipairs(type(crafters) == "table" and crafters or {}) do names[#names + 1] = Data.CharLabel(key) end
    if #names > 0 then out[#out + 1] = { left = L.TIP_LEARNED:format(table.concat(names, ", ")), color = "good" } end
    local skill, approx
    if recipeID then skill, approx = Where.Skill(recipeID, {}) end
    if not skill then
        local get = Knowledge("Get")
        local f = get and Plain(Call(get, itemID))
        local r = type(f) == "table" and f.recipe
        skill, approx = type(r) == "table" and Num(r.skill) or nil, false
    end
    local parts = {}
    for _, e in ipairs(Ranks(prof)) do
        if not known[e.key] then
            local label = Data.CharLabel(e.key)
            if skill and e.rank < skill then
                parts[#parts + 1] = L.TIP_RANK_MORE:format(label, e.rank, skill - e.rank)
            else
                parts[#parts + 1] = L.TIP_RANK:format(label, e.rank)
            end
        end
    end
    if skill then
        local text = (approx and L.TIP_LEARN_FROM_APPROX or L.TIP_LEARN_FROM):format(skill)
        if #parts > 0 then text = text .. ": " .. table.concat(parts, ", ") end
        out[#out + 1] = { left = text, color = "highlight" }
    elseif #parts > 0 then
        out[#out + 1] = { left = L.TIP_NOT_LEARNED:format(table.concat(parts, ", ")), color = "highlight" }
    end
    if n == 0 then table.insert(out, 1, { left = L.TIP_WHERE_NONE, color = "hint" }) end
    return out
end

Where.ORDER = 28     -- nach „Rezept und Zutaten“ (27), vor der Einkaufsliste (30)

function Where.Draw(tooltip, itemID)
    local lines = Where.TooltipLines(itemID)
    if #lines == 0 then return 0 end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): keine doppelte Leerzeile
    ns.TipLines(tooltip, lines)
    return #lines
end

-- Abschnitt im Tooltip (Schalter recipeWhere) → Zahl der Zeilen
function Where.Section(tooltip, itemID)
    if not ns.Enabled("recipeWhere") then return 0 end
    return Where.Draw(tooltip, itemID)
end
Core.Tooltip.AddItemSection("ezCraft.recipeWhere", Where.ORDER, function(tooltip, itemID)
    Where.Section(tooltip, itemID)
end, ADDON)
