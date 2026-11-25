local _, ns = ...
local Core = ezCore

--[[
    Berufe und Berufs-Abklingzeiten aller Twinks als eine Quelle (vorher ezPanel `c.profs` und
    Item-Wissen `charProfs` getrennt erfasst; Abklingzeiten gewünscht von ezPanel und ezCraft).

      Professions.Read()          → { { slot, name, icon, rank, max, line, mod, primary } … }  (jetzt, dieser Charakter)
      Professions.Of(charKey)     → gemerkte Liste eines Twinks (ezCoreDB.chars[key].profs, gleiche Felder; Einträge
                                    aus der Fertigkeitenliste tragen dazu key und src = "skill" – Entwurf 1.6, sie
                                    ersetzen knowledge.charProfs; ohne icon, max und line)
      Professions.Cooldowns(charKey, withReady, merged)  → { { id, name, readyAt, left, group } … } laufende
                                    Abklingzeiten, früheste zuerst
      Professions.AllCooldowns(withReady, merged)  → { { char, id, name, readyAt, left, ready, group } … } über alle
                                    Twinks; withReady = true liefert auch fertige (ready = true, left = 0) – A61 (Welle
                                    23b): eine fertige Abklingzeit bleibt stehen, bis sie wieder läuft (auch beim gespielten
                                    Charakter; vorher strich das nächste Einlesen sie). „Fertig“ heißt: ein Eintrag liegt
                                    vor; „nie benutzt“: kein Eintrag (Wunsch von ezCraft: „Transmutation bei Mira bereit“)
                                    group = Gruppe laut Spells.PROF_COOLDOWNS bzw. PROF_COOLDOWN_ITEMS („transmute“ – die
                                    Transmutationen teilen sich eine Abklingzeit) oder nil. merged = true (A61): je Twink
                                    und Gruppe ein Eintrag mit ids = { … } und count (die früheste Bereitschaft zählt)
      Professions.ScanCooldowns() → liest bekannte Abklingzeit-Zauber und -Gegenstände (außerhalb des Kampfes)
      Nachrichten: PROFESSIONS_CHANGED, PROF_COOLDOWNS_CHANGED

    Abklingzeiten kommen aus zwei Quellen: bekannte Zauber und Gegenstände (Spells.PROF_COOLDOWNS,
    Spells.PROF_COOLDOWN_ITEMS: Transmutationen, Mondstoff, Salzstreuer …) und jedes offene Berufefenster
    (C_TradeSkillUI.GetRecipeCooldown – so kommen neue Forever-Rezepte von selbst dazu).
    Gespeichert je Twink in ezCoreDB.chars[key].profCD = { [id] = { n = Name, r = bereit um (time()) } }.
]]

Core.Professions = Core.Professions or {}
local Professions = Core.Professions
-- Merkmale ohne eigenen Funktionsnamen für Core.Has (Welle 23b): fertige Abklingzeiten bleiben stehen, Zusammenfassen
-- je Gruppe ("Professions.FEATURES.keepReady", "Professions.FEATURES.merged")
Professions.FEATURES = { keepReady = true, merged = true }

--[[
    Fertigkeitenliste (EC-85, V-185; vorher je eine Fassung in Knowledge.lua und in ezPanels Blocks/Stats.lua):
      Core.SkillLines(limit) → lines, complete  oder nil, wenn der Client keine Fertigkeitenliste anbietet
        lines    = { { id, name, header, collapsed, rank, mod, max } … } in Blizzards Reihenfolge (höchstens limit,
                   ohne Angabe 500); gesperrte Werte gelten als unbekannt (nil), header/collapsed sind true/false.
        complete = false, wenn die Liste Lücken haben kann: eine eingeklappte Überschrift versteckt die Zeilen
                   darunter vor der Index-Abfrage (docs/datenkatalog-client.md, Abschnitt 7.1), eine Zeile war
                   gesperrt oder warf, oder die Liste war länger als limit.
      Zuerst C_SkillInfo (Blizzards Forever-Fertigkeitenfenster liest nur darüber; GetNumSkillLines fehlt auf
      Forever 1.60.1, Probe 14.11.2026), sonst die alten Globalen GetNumSkillLines/GetSkillLineInfo.
]]
function Core.SkillLines(limit)
    limit = Core.Num(limit) or 500
    local api = rawget(_G, "C_SkillInfo")
    local viaC = type(api) == "table" and type(api.GetNumSkillLines) == "function"
        and type(api.GetSkillLineInfo) == "function"
    local countFn, lineFn
    if viaC then
        countFn, lineFn = api.GetNumSkillLines, api.GetSkillLineInfo
    else
        countFn, lineFn = rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
    end
    if type(countFn) ~= "function" or type(lineFn) ~= "function" then return nil end
    local okN, n = pcall(countFn)
    n = okN and Core.Num(n) or 0
    local lines, complete = {}, okN and n <= limit
    for i = 1, math.min(n, limit) do
        local line
        if viaC then
            local ok, info = pcall(lineFn, i)
            if ok and type(info) == "table" and not Core.IsSecret(info) then
                local header = Core.Bool(info.isHeader, false)
                line = { id = Core.Num(info.skillID), name = Core.Plain(info.name), header = header,
                    collapsed = header and Core.Bool(info.isCollapsed, false) or false, rank = Core.Num(info.rank),
                    mod = Core.Num(info.modifier), max = Core.Num(info.maxRank) }
            end
        else
            local ok, name, isHeader, isExpanded, rank, _, mod, max = pcall(lineFn, i)
            if ok then
                local header = Core.Bool(isHeader, false)
                line = { name = Core.Plain(name), header = header,
                    collapsed = header and Core.Bool(isExpanded, true) == false or false, rank = Core.Num(rank),
                    mod = Core.Num(mod), max = Core.Num(max) }
            end
        end
        if line then
            lines[#lines + 1] = line
            if line.collapsed then complete = false end
        else
            complete = false
        end
    end
    return lines, complete
end

local Now = Core.Now

function Professions.Read()
    local list = {}
    if not (GetProfessions and GetProfessionInfo) then return list end
    local okAll, a, b, c, d, e, f = pcall(GetProfessions)
    if not okAll then return list end
    local slots = { a, b, c, d, e, f }
    for slot = 1, 6 do
        local index = Core.Num(slots[slot])
        if index then
            local ok, name, icon, rank, maxRank, _, _, skillLine, modifier = pcall(GetProfessionInfo, index)
            name, rank = ok and Core.Plain(name), ok and Core.Num(rank)
            if name and rank then
                list[#list + 1] = { slot = slot, name = name, icon = Core.Plain(icon), rank = rank,
                    max = Core.Num(maxRank) or rank, line = Core.Num(skillLine), mod = Core.Num(modifier) or 0,
                    primary = slot <= 2 }
            end
        end
    end
    return list
end

function Professions.Of(charKey)
    local c = charKey and Core.Char(charKey)
    return c and c.profs or nil
end

local function SaveProfessions()
    local me = Core.me
    if not me then return end
    local list = Professions.Read()
    if #list == 0 and not GetProfessions then return end
    -- Entwurf 1.6: Berufe aus der Fertigkeitenliste (src = "skill", Knowledge.lua) nicht mit einer leeren Antwort
    -- von GetProfessions überschreiben – auf Forever liefert es teils nichts
    if #list == 0 and type(me.profs) == "table" and #me.profs > 0 then
        local onlySkill = true
        for _, p in ipairs(me.profs) do if type(p) ~= "table" or p.src ~= "skill" then onlySkill = false end end
        if onlySkill then return end
    end
    local out = {}
    for _, p in ipairs(list) do
        out[#out + 1] = { name = p.name, icon = p.icon, rank = p.rank, max = p.max, primary = p.primary, line = p.line }
    end
    me.profs = out
    Core.Fire("PROFESSIONS_CHANGED", out)
end
Professions.Save = SaveProfessions

---------------------------------------------------------------------------
-- Abklingzeiten
---------------------------------------------------------------------------

local function Store(create)
    local me = Core.me
    if not me then return nil end
    if not me.profCD and create then me.profCD = {} end
    return me.profCD
end

-- Gruppe einer Abklingzeit (A61): Zauber laut Spells.PROF_COOLDOWNS, Gegenstände („i15846“) laut PROF_COOLDOWN_ITEMS
function Professions.CooldownGroup(id)
    local Sp = Core.Spells
    if not Sp then return nil end
    local group
    if type(id) == "number" then
        group = type(Sp.PROF_COOLDOWNS) == "table" and Sp.PROF_COOLDOWNS[id]
    elseif type(id) == "string" then
        local itemID = tonumber(id:match("^i(%d+)$"))
        group = itemID and type(Sp.PROF_COOLDOWN_ITEMS) == "table" and Sp.PROF_COOLDOWN_ITEMS[itemID]
    end
    return type(group) == "string" and group or nil
end

-- withReady: auch fertige Einträge (sie bleiben stehen, bis die Abklingzeit wieder läuft) mit ready = true.
local function List(cd, now, withReady)
    local out = {}
    for id, e in pairs(cd or {}) do
        local r = type(e) == "table" and Core.Num(e.r)
        if r and r > now then
            out[#out + 1] = { id = id, name = e.n, readyAt = r, left = r - now, group = Professions.CooldownGroup(id) }
        elseif r and withReady then
            out[#out + 1] = { id = id, name = e.n, readyAt = r, left = 0, ready = true, group = Professions.CooldownGroup(id) }
        end
    end
    table.sort(out, function(x, y) return x.readyAt < y.readyAt end)
    return out
end

-- A61: je Twink und Gruppe ein Eintrag (Liste nach readyAt sortiert: der erste ist der früheste)
local function Merge(list)
    local out, byKey = {}, {}
    for _, e in ipairs(list) do
        local key = e.group and (tostring(e.char or "") .. "\031" .. e.group)
        local have = key and byKey[key]
        if have then
            have.ids[#have.ids + 1] = e.id
            have.count = have.count + 1
        else
            e.ids, e.count = { e.id }, 1
            if key then byKey[key] = e end
            out[#out + 1] = e
        end
    end
    return out
end

function Professions.Cooldowns(charKey, withReady, merged)
    local c = Core.Char(charKey or Core.charKey)
    local list = List(c and c.profCD, Now(), withReady)
    if merged then return Merge(list) end
    return list
end

function Professions.AllCooldowns(withReady, merged)
    local out, now = {}, Now()
    for key, c in pairs(Core.Chars()) do
        for _, e in ipairs(List(c.profCD, now, withReady)) do
            e.char = key
            out[#out + 1] = e
        end
    end
    table.sort(out, function(x, y) return x.readyAt < y.readyAt end)
    if merged then return Merge(out) end
    return out
end

-- Rest einer Abklingzeit (start, duration in GetTime-Sekunden) als Uhrzeit; nil = keine (oder nur GCD).
local function ReadyAt(start, duration)
    start, duration = Core.Num(start), Core.Num(duration)
    if not (start and duration and start > 0 and duration > 2) then return nil end
    local left = start + duration - (GetTime and GetTime() or 0)
    if left <= 0 then return nil end
    return Now() + math.floor(left + 0.5)
end

-- Ohne laufende Abklingzeit (readyAt = nil) bleibt ein vorhandener Eintrag als „fertig“ stehen (A61, Welle 23b): ein
-- Rest in der Zukunft wird auf jetzt gesetzt (Blizzard meldet sie nicht mehr), ein abgelaufener bleibt, wie er ist.
local function Set(store, id, name, readyAt)
    local old = store[id]
    if readyAt then
        if not (old and old.r == readyAt) then
            store[id] = { n = name or (old and old.n), r = readyAt }
            return true
        end
    elseif type(old) == "table" then
        local now = Now()
        if (Core.Num(old.r) or 0) > now then
            old.r = now
            return true
        end
    elseif old ~= nil then
        store[id] = nil   -- kaputter Eintrag
        return true
    end
    return false
end

local function KnowsSpell(id)
    if Core.KnowsSpell(id) then return true end
    return Core.Spells and Core.Spells.IsKnown and Core.Spells.IsKnown(id) or false
end

local function SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then return info.startTime, info.duration end
        return nil
    end
    if GetSpellCooldown then
        local ok, start, duration = pcall(GetSpellCooldown, id)
        if ok then return start, duration end
    end
    return nil
end

local function ItemCooldown(itemID)
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return nil end
    local ok, start, duration = pcall(fn, itemID)
    if ok then return start, duration end
    return nil
end

local function HasItem(itemID)
    return Core.ItemCount(itemID) > 0   -- C_Item.GetItemCount, sonst das alte Global (V-037)
end


function Professions.ScanCooldowns()
    if Core.InCombat() then return false end
    local store = Store(true)
    if not store then return false end
    local Sp = Core.Spells
    local changed = false
    for id in pairs(Sp and Sp.PROF_COOLDOWNS or {}) do
        if KnowsSpell(id) then
            local name = Sp.Name and Sp.Name(id) or nil
            changed = Set(store, id, name, ReadyAt(SpellCooldown(id))) or changed
        end
    end
    for itemID in pairs(Sp and Sp.PROF_COOLDOWN_ITEMS or {}) do
        if HasItem(itemID) then
            local name = Core.ItemNameByID(itemID)
            changed = Set(store, "i" .. itemID, name, ReadyAt(ItemCooldown(itemID))) or changed
        end
    end
    if changed then Core.Fire("PROF_COOLDOWNS_CHANGED") end
    return changed
end

-- Zeigt das offene Berufefenster einen fremden Beruf (Link im Chat, Gildenmitglied, NPC-Werkbank)?
function Professions.IsForeignTradeSkill()
    local api = C_TradeSkillUI
    if not api then return false end
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        if type(api[name]) == "function" then
            local ok, value = pcall(api[name])
            if ok and Core.Bool(value, false) then return true end
        end
    end
    return false
end

-- Offenes Berufefenster: jede Abklingzeit eines Rezepts (Forever-Rezepte inbegriffen).
-- Nur das eigene Fenster zählt: Ein verlinktes oder Gilden-Berufefenster nennt die Abklingzeiten nicht (oder die
-- des anderen) und würde die eigenen sonst löschen (V-026).
function Professions.ScanTradeSkill()
    local api = C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeCooldown) then return false end
    if Professions.IsForeignTradeSkill() then return false end
    local store = Store(true)
    if not store then return false end
    local ok, ids = pcall(api.GetAllRecipeIDs)
    if not (ok and type(ids) == "table") then return false end
    local changed = false
    for _, id in ipairs(ids) do
        local okCd, cooldown = pcall(api.GetRecipeCooldown, id)
        cooldown = okCd and Core.Num(cooldown)
        if cooldown and cooldown > 0 then
            local info = api.GetRecipeInfo and select(2, pcall(api.GetRecipeInfo, id))
            local name = type(info) == "table" and Core.Plain(info.name) or nil
            changed = Set(store, id, name, Now() + math.floor(cooldown + 0.5)) or changed
        elseif store[id] then
            changed = Set(store, id, nil, nil) or changed   -- bleibt als „fertig“ stehen (A61)
        end
    end
    if changed then Core.Fire("PROF_COOLDOWNS_CHANGED") end
    return changed
end

local SaveLater = Core.Throttle(SaveProfessions, 0.3, Core.name)
local ScanLater = Core.Throttle(function() Professions.ScanCooldowns() end, 1, Core.name)
local TradeLater = Core.Throttle(function() Professions.ScanTradeSkill() end, 1, Core.name)

Core.Listen("CHARS_READY", function()
    SaveLater()
    C_Timer.After(3, ScanLater)
end)
ns.On("SKILL_LINES_CHANGED", SaveLater)
ns.On("CHAT_MSG_SKILL", SaveLater)
ns.On("TRADE_SKILL_LIST_UPDATE", TradeLater)
ns.On("TRADE_SKILL_SHOW", TradeLater)
ns.On("SPELL_UPDATE_COOLDOWN", ScanLater)
ns.On("BAG_UPDATE_COOLDOWN", ScanLater)
ns.On("PLAYER_REGEN_ENABLED", ScanLater)
