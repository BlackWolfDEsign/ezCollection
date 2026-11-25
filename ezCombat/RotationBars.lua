local _, ns = ...
local L = ns.L
local Core = ezCore
local Rotation = ns.Rotation
local Book = ns.RotationBook
local AS, BP = Core.ActionSlots, Core.BarProfiles

--[[
    Rotation auf die Aktionsleisten 1 und 2 legen (Wunsch des Nutzers vom 24.11.2026, wörtlich: „"rotationsvorlage" für
    sinnvolle aktionsleistenpresets? --> wenn user mag und blizzard erlaubt“, „gerne für aktionsleisten 1-2“).

    Nur auf Knopfdruck, nach einer Rückfrage und außerhalb des Kampfes (Blizzard: PickupAction, PlaceAction und
    C_Spell.PickupSpell sind im Kampf gesperrt); nichts geschieht von selbst. Plätze und Ablegen kommen aus ezCore
    (Core.ActionSlots, Core.BarProfiles).

    Leiste 1 = die Hauptleiste (in einer Haltung oder Gestalt deren Seite, sonst Seite 1; weitergeblättert oder im Fahrzeug:
    Grund statt Knopf), Leiste 2 = Blizzards Aktionsleiste 2 (Plätze 61–72), solange sie eingeblendet ist.
    Anordnung: Leiste 1 bekommt den Kampf in der Reihenfolge der Rotation, dann den Einstieg; Leiste 2 Abklingzeiten,
    Fläche, Situatives und Vorbereitung. Was nicht passt, rutscht auf die andere Leiste. Nur Gelerntes und Eingeschaltetes;
    Haltungen und Gestalten nicht (dafür hat Blizzard eine eigene Leiste).

    Zurück: Jedes Ablegen ist ein Schritt mit dem Stand davor (nur die geänderten Plätze; je Charakter, höchstens STEPS).
    „Zurück“ nimmt den letzten Schritt zurück; was der Spieler dort seitdem selbst geändert hat, nennt die Rückfrage.
    Gespeichert: ezCombatDB.rotationBars[Charakter] = { { time, name, page, group, slots, before, after }, … } (der letzte
    zuletzt). group: Talentgruppe (Primär/Sekundär) – angeboten werden nur Schritte der aktiven, falls der Client die
    Aktionsplätze je Gruppe führt.

      Bars.Plan(rotation) → { target, entries, unlearned, fill, arrange, … } | nil, Grund (Text)
      Bars.Apply("fill" | "arrange", rotation) → true, wenn die Rückfrage kam
      Bars.UndoInfo() → letzter Schritt | nil      Bars.Undo() → true, wenn die Rückfrage kam
      Bars.Forget() → nächster Plan liest die Leisten neu
]]

local Bars = {}
ns.RotationBars = Bars

Bars.BAR2_PAGE = 6                                                  -- Blizzards Aktionsleiste 2 (ActionSlots.BLIZZARD_PAGES)
Bars.FIRST = { "combat", "opener" }                                 -- Abschnitte für Leiste 1
Bars.SECOND = { "cooldown", "aoe", "situational", "prep" }          -- Abschnitte für Leiste 2
Bars.SETTLE = 1                                                     -- Sekunden, bis der Client die neuen Plätze nennt
Bars.STEPS = 10                                                     -- so viele Schritte merkt „Zurück“ je Charakter
Bars.SCAN_TTL = 2                                                   -- so lange gilt der gelesene Stand der Leisten (Sek.)

local OWNER = "ezCombat"

---------------------------------------------------------------------------
-- Was liegt wo, was soll wohin?
---------------------------------------------------------------------------

-- Plätze der beiden Leisten: { page, bars = { { 12 Plätze }, { 12 Plätze } }, slots } | nil, Grund
function Bars.Target()
    local page, why, shown = AS.MainPage()
    if not page then return nil, why == "page" and L.ROTATION_BARS_PAGED:format(shown) or L.ROTATION_BARS_VEHICLE end
    local target = { page = page, bars = { AS.SlotsOfPage(page) }, slots = {} }
    if AS.BarShown(Bars.BAR2_PAGE) == true then target.bars[2] = AS.SlotsOfPage(Bars.BAR2_PAGE) end
    for _, list in ipairs(target.bars) do
        for _, slot in ipairs(list) do target.slots[#target.slots + 1] = slot end
    end
    return target
end

-- Gelernte, eingeschaltete Fähigkeiten der Rotation, jede einmal: Listen für Leiste 1 und 2, Zahl der nicht gelernten.
function Bars.Wanted(rotation)
    local bySection, seen, missing, unlearned = {}, {}, {}, 0
    for _, section in ipairs(Rotation.Sections(rotation)) do
        bySection[section.key] = bySection[section.key] or {}
        for _, entry in ipairs(section.steps) do
            local step, name = entry.step, entry.name
            if entry.enabled and step.when ~= "form" and type(name) == "string" and Book.StaticApplies(step) then
                if not entry.known then
                    missing[name] = true
                else
                    table.insert(bySection[section.key], { id = entry.id, name = name, icon = entry.icon, section = section.key })
                end
            end
        end
    end
    local function Collect(keys)
        local list = {}
        for _, key in ipairs(keys) do
            for _, item in ipairs(bySection[key] or {}) do
                if not seen[item.name] then
                    seen[item.name] = true
                    list[#list + 1] = item
                end
            end
        end
        return list
    end
    local first, second = Collect(Bars.FIRST), Collect(Bars.SECOND)
    for name in pairs(missing) do
        if not seen[name] then unlearned = unlearned + 1 end
    end
    return first, second, unlearned
end

-- Was auf einem Platz liegt, als Text zum Vergleichen. Makros ohne Index und Zauber: ihr gezeigter Zauber wechselt von selbst.
local function Key(slot)
    local info = AS.Info(slot)
    if info then
        if info.kind == "macro" and info.text then return "macro:" .. info.text end
        return info.kind .. ":" .. tostring(info.id)
    end
    return AS.Has(slot) and "?" or ""
end

-- Name dessen, was auf einem Platz liegt, für die Rückfragen: Makros mit ihrem Namen, niedrige Ränge mit Rang.
local function SlotName(slot)
    local info = AS.Info(slot)
    if info and info.kind == "macro" then
        return info.text and L.ROTATION_BARS_MACRO:format(info.text) or ns.Glow.SlotSpellName(slot) or L.ROTATION_BARS_SOMETHING
    end
    local name = ns.Glow.SlotSpellName(slot) or AS.Text(slot)
    if name and info and info.kind == "spell" and Core.Spells.IsLowRank(info.id) then
        local rank = Core.Num(Core.Spells.Rank(info.id))
        if rank then return L.ROTATION_BARS_RANK:format(name, rank) end
    end
    if not name and info then
        if info.kind == "item" then
            name = Core.Call(C_Item and C_Item.GetItemNameByID, info.id)
        elseif info.kind == "summonmount" then
            name = Core.Call(C_MountJournal and C_MountJournal.GetMountInfoByID, info.id)
        elseif info.kind == "equipmentset" then
            name = info.id
        end
        name = Core.Plain(name)
    end
    return type(name) == "string" and name ~= "" and name or L.ROTATION_BARS_SOMETHING
end

-- Stand der Leisten (was liegt wo, was ist irgendwo zu sehen); gilt bis zum nächsten Leistenereignis (Bars.Forget).
local scan
function Bars.Forget() scan = nil end

local function Scan(target)
    local now = GetTime()
    if scan and scan.page == target.page and #scan.slots == #target.slots and (now - scan.at < Bars.SCAN_TTL or ns.InCombat()) then return scan end
    scan = { page = target.page, slots = target.slots, at = now, has = {}, fixed = {}, spellOn = {}, isMacro = {}, id = {},
        visible = ns.Glow.VisibleNames() }
    local macros = BP.MacroNames()
    for _, slot in ipairs(target.slots) do
        scan.has[slot] = AS.Has(slot)
        if scan.has[slot] then
            local info = AS.Info(slot)
            scan.fixed[slot] = not BP.Movable(slot, macros)
            scan.spellOn[slot] = ns.Glow.SlotSpellName(slot)
            scan.isMacro[slot] = info ~= nil and info.kind == "macro"
            scan.id[slot] = info and info.kind == "spell" and info.id or nil
        end
    end
    return scan
end

-- Verteilt die Fähigkeiten auf freie Plätze: free[leiste] = Liste der Plätze in Reihenfolge (wird verbraucht).
-- Erst jede Liste auf ihre Leiste, dann der Rest auf die andere. place(item, platz) merkt die Wahl. → ohne Platz
local function Distribute(first, second, free, place)
    local rest = {}
    local function Put(list, bar)
        local left = {}
        for _, item in ipairs(list) do
            local slot = free[bar] and table.remove(free[bar], 1)
            if slot then place(item, slot) else left[#left + 1] = item end
        end
        return left
    end
    local a = Put(first, 1)
    local b = Put(second, free[2] and 2 or 1)
    for _, item in ipairs(Put(a, 2)) do rest[#rest + 1] = item end
    for _, item in ipairs(Put(b, 1)) do rest[#rest + 1] = item end
    return rest
end

-- Der ganze Plan für eine Rotation; liest nur. entries in der Reihenfolge der Seite:
--   { id, name, icon, section, slot, bar, index, now = Platz auf diesen Leisten, elsewhere = auf einer anderen }
-- fill = { want, new, noRoom = { Namen } }; arrange = { want, new, moved, dropped = { Plätze }, noRoom, same }
function Bars.Plan(rotation)
    local target, why = Bars.Target()
    if not target then return nil, why end
    local first, second, unlearned = Bars.Wanted(rotation)
    local plan = { target = target, slots = target.slots, unlearned = unlearned, entries = {}, have = 0,
        who = Core.WhoHandlesInfo("actionBars") }
    local state = Scan(target)
    local has, fixed, spellOn, isMacro = state.has, state.fixed, state.spellOn, state.isMacro
    local barOf, indexOf = {}, {}
    for bar, list in ipairs(target.bars) do
        for index, slot in ipairs(list) do barOf[slot], indexOf[slot] = bar, index end
    end
    -- Wo liegt jede Fähigkeit jetzt? Ein Makro, das sie zeigt, vor genau diesem Zauber, vor einem anderen Rang; sonst anderswo
    local byName = {}
    for _, list in ipairs({ first, second }) do
        for _, item in ipairs(list) do
            local best = 0
            for _, slot in ipairs(target.slots) do
                if spellOn[slot] == item.name then
                    local score = isMacro[slot] and 3 or (state.id[slot] == item.id and 2 or 1)
                    if score > best then item.now, best = slot, score end
                end
            end
            item.elsewhere = item.now == nil and state.visible[item.name] or nil
            if item.now or item.elsewhere then plan.have = plan.have + 1 end
            plan.entries[#plan.entries + 1] = item
            byName[item.name] = item
        end
    end
    local function ItemNames(list)
        local out = {}
        for i, item in ipairs(list) do out[i] = item.name end
        return out
    end

    -- 1. Fehlende auf freie Plätze: nichts Vorhandenes wird angefasst
    do
        local free, want, new = {}, {}, 0
        for bar, list in ipairs(target.bars) do
            free[bar] = {}
            for _, slot in ipairs(list) do
                if has[slot] then want[slot] = { from = slot } else table.insert(free[bar], slot) end
            end
        end
        local function Missing(list)
            local out = {}
            for _, item in ipairs(list) do
                if not (item.now or item.elsewhere) then out[#out + 1] = item end
            end
            return out
        end
        local rest = Distribute(Missing(first), Missing(second), free, function(item, slot)
            item.fillSlot = slot
            want[slot] = { spell = item.id }
            new = new + 1
        end)
        plan.fill = { want = want, new = new, noRoom = ItemNames(rest) }
    end

    -- 2. Beide Leisten nach der Rotation ordnen: Vorhandenes tauscht seinen Platz, Übriges rückt auf freie Plätze
    do
        local free, want, used = {}, {}, {}
        local new, moved, dropped = 0, 0, {}
        for bar, list in ipairs(target.bars) do
            free[bar] = {}
            for _, slot in ipairs(list) do
                if fixed[slot] then want[slot] = { from = slot } else table.insert(free[bar], slot) end
            end
        end
        local function Open(list)      -- liegt sie auf einem festen Platz, bleibt sie dort
            local out = {}
            for _, item in ipairs(list) do
                if item.now and fixed[item.now] then item.slot = item.now else out[#out + 1] = item end
            end
            return out
        end
        local rest = Distribute(Open(first), Open(second), free, function(item, slot)
            item.slot = slot
            if item.now then
                want[slot], used[item.now] = { from = item.now }, true
                if item.now ~= slot then moved = moved + 1 end
            else
                want[slot] = { spell = item.id }
                new = new + 1
            end
        end)
        -- Übriges: bleibt, wo es liegt, sonst der nächste freie Platz derselben, dann der anderen Leiste; genau derselbe
        -- Zauber noch einmal zuletzt (andere Ränge sind kein Doppel)
        local homeless, twice = {}, {}
        for _, slot in ipairs(target.slots) do
            if has[slot] and not fixed[slot] and not used[slot] then
                local item = byName[spellOn[slot] or ""]
                if want[slot] == nil then
                    want[slot] = { from = slot }
                elseif item and not isMacro[slot] and state.id[slot] == item.id then
                    twice[#twice + 1] = slot
                else
                    homeless[#homeless + 1] = slot
                end
            end
        end
        for _, slot in ipairs(twice) do homeless[#homeless + 1] = slot end
        for _, slot in ipairs(homeless) do
            local found
            for _, bar in ipairs({ barOf[slot], 3 - barOf[slot] }) do
                for _, other in ipairs(target.bars[bar] or {}) do
                    if not found and want[other] == nil then found = other end
                end
            end
            if found then
                want[found] = { from = slot }
                moved = moved + 1
            else
                dropped[#dropped + 1] = slot
            end
        end
        plan.arrange = { want = want, new = new, moved = moved, dropped = dropped, noRoom = ItemNames(rest),
            same = new == 0 and moved == 0 and #dropped == 0 }
    end
    for _, item in ipairs(plan.entries) do
        if item.slot then item.bar, item.index = barOf[item.slot], indexOf[item.slot] end
        if item.now then item.nowBar, item.nowIndex = barOf[item.now], indexOf[item.now] end
    end
    return plan
end

---------------------------------------------------------------------------
-- Schritte für „Zurück“ (je Charakter)
---------------------------------------------------------------------------

local function Steps()
    local db = ns.db
    if not db then return {} end
    db.rotationBars = type(db.rotationBars) == "table" and db.rotationBars or {}
    local key = Core.charKey or "?"
    db.rotationBars[key] = type(db.rotationBars[key]) == "table" and db.rotationBars[key] or {}
    return db.rotationBars[key]
end

-- Letzter Schritt der aktiven Talentgruppe: { time, name, page, group, slots, before, after } | nil. Unbrauchbares (von
-- Hand verändert) fällt weg. Zweiter Wert: seine Stelle in der Liste.
function Bars.UndoInfo()
    local steps, group = Steps(), Core.Talents.SpecGroup()
    for i = #steps, 1, -1 do
        local step = steps[i]
        if not (type(step) == "table" and type(step.slots) == "table" and type(step.before) == "table"
            and type(step.after) == "table") then
            table.remove(steps, i)
        elseif (step.group or group) == group then
            return step, i
        end
    end
    return nil
end

local function Push(step)
    local steps, same = Steps(), 0
    steps[#steps + 1] = step
    for i = #steps, 1, -1 do
        if steps[i].group == step.group then
            same = same + 1
            if same > Bars.STEPS then table.remove(steps, i) end
        end
    end
end

local function Drop(step)
    local steps = Steps()
    for i = #steps, 1, -1 do
        if steps[i] == step then table.remove(steps, i) end
    end
end

-- Liegt auf dem Platz noch, was das Ablegen dort hinterließ? Ein neu abgelegter Zauber darf seinen Rang nach oben wechseln.
local function Untouched(slot, after)
    if Key(slot) == after then return true end
    local id = type(after) == "string" and tonumber(after:match("^new:(%d+)$")) or nil
    local info = id and AS.Info(slot)
    if not (info and info.kind == "spell") then return false end
    return info.id == id or (ns.SpellName(info.id) == ns.SpellName(id) and not Core.Spells.IsLowRank(info.id))
end

-- Was der Spieler auf den Plätzen dieses Schritts seitdem selbst abgelegt hat und was beim Zurück von der Leiste ginge:
-- { Namen }. Was schon dort lag (before), wandert nur und zählt nicht.
local function OwnChanges(step)
    local names, used = {}, {}
    local function Returns(data)
        for _, slot in ipairs(step.slots) do
            if not used[slot] and BP.Exact(step.before[slot], data) then
                used[slot] = true
                return true
            end
        end
        return false
    end
    for _, slot in ipairs(step.slots) do
        if AS.Has(slot) and not Untouched(slot, step.after[slot]) and not Returns(BP.CaptureSlot(slot)) then
            names[#names + 1] = SlotName(slot)
        end
    end
    return names
end

---------------------------------------------------------------------------
-- Ablegen und zurück
---------------------------------------------------------------------------

local function Changed(plan, want)
    local list = {}
    for _, slot in ipairs(plan.slots) do
        local target = want[slot]
        if target and target.from ~= slot or (not target and AS.Has(slot)) then list[#list + 1] = slot end
    end
    return list
end

-- Abdruck von Plätzen und Vorhaben: Hat sich zwischen Rückfrage und „Ja“ etwas geändert, gilt die Antwort nicht.
local function Stamp(slots, want)
    local parts = {}
    for _, slot in ipairs(slots) do
        local target = want and want[slot]
        parts[#parts + 1] = slot .. "=" .. Key(slot) .. ">" .. tostring(target and (target.from or ("s" .. tostring(target.spell))))
    end
    return table.concat(parts, "|")
end

-- Kampf oder etwas am Mauszeiger: Hinweis. → true, wenn es gerade nicht geht
local function Blocked()
    if ns.InCombat() then
        Core.CombatNotice(ns, L.ROTATION_BARS_WHAT)
        return true
    end
    if type(GetCursorInfo) == "function" and GetCursorInfo() ~= nil then
        ns.Print(L.ROTATION_BARS_CURSOR)
        return true
    end
    return false
end

local function Names(list) return table.concat(list, ", ") end

local function SlotNames(slots)
    local out = {}
    for i, slot in ipairs(slots) do out[i] = SlotName(slot) end
    return out
end

-- Neu lesen und zeichnen, gleich und wenn der Client die neuen Plätze nennt
local function Settle()
    Bars.Forget()
    Book.Refresh()
    C_Timer.After(Bars.SETTLE, function()
        Bars.Forget()
        Book.Refresh()
    end)
end

-- „Aktionsleisten 1–2“ bzw. „Aktionsleiste 1“ (Leiste 2 ausgeblendet)
function Bars.Title(plan)
    return plan.target.bars[2] and L.ROTATION_BARS_BOTH or L.ROTATION_BARS_ONE
end

local function Run(plan, part, changed, name)
    local step = { time = Core.Now(), name = name, page = plan.target.page, group = Core.Talents.SpecGroup(), slots = changed,
        before = {}, after = {} }
    local key, title = {}, {}
    for _, slot in ipairs(plan.slots) do key[slot], title[slot] = Key(slot), AS.Has(slot) and SlotName(slot) or nil end
    for _, slot in ipairs(changed) do step.before[slot] = BP.CaptureSlot(slot) end
    Push(step)      -- vor dem Ablegen: bricht etwas ab, ist der Stand davor schon gemerkt
    local moved, placed, removed, _, result = BP.Rearrange(plan.slots, part.want, { owner = OWNER })
    if not moved then
        Drop(step)
        ns.Print(L.ROTATION_BARS_CHANGED)
        return false
    end
    local failed = {}
    for _, slot in ipairs(plan.slots) do
        local is, want = result[slot], part.want[slot]
        if want and want.spell and not (is and is.spell == want.spell) then
            failed[#failed + 1] = ns.SpellName(want.spell) or L.ROTATION_BARS_SOMETHING
        elseif want and want.from and not (is and is.from == want.from) then
            failed[#failed + 1] = title[want.from] or L.ROTATION_BARS_SOMETHING
        end
        step.after[slot] = is and (is.from and key[is.from] or "new:" .. tostring(is.spell)) or ""
    end
    ns.Print(L.ROTATION_BARS_DONE:format(Bars.Title(plan), placed, moved, removed))
    if #failed > 0 then ns.Print(L.ROTATION_BARS_MISSING:format(Names(failed))) end
    Settle()
    return true
end

-- Fragt und legt ab. mode: "fill" (Fehlende auf freie Plätze) | "arrange" (Leisten ordnen). → true, wenn gefragt wurde
function Bars.Apply(mode, rotation)
    if mode ~= "fill" and mode ~= "arrange" then return false end
    if Blocked() then return false end
    Bars.Forget()
    local plan, why = Bars.Plan(rotation)
    if not plan then ns.Print(why) return false end
    local part = plan[mode]
    if #Changed(plan, part.want) == 0 then ns.Print(L.ROTATION_BARS_NOTHING) return false end
    local name, lines = Rotation.Name(rotation), {}
    if mode == "fill" then
        lines[1] = L.ROTATION_BARS_ASK_FILL:format(name, Bars.Title(plan), part.new)
    else
        lines[1] = L.ROTATION_BARS_ASK_ARRANGE:format(Bars.Title(plan), name, part.new, part.moved)
        if #part.dropped > 0 then lines[#lines + 1] = L.ROTATION_BARS_ASK_DROPPED:format(Names(SlotNames(part.dropped))) end
    end
    if #part.noRoom > 0 then lines[#lines + 1] = L.ROTATION_BARS_ASK_NO_ROOM:format(Names(part.noRoom)) end
    if plan.target.page > 1 then lines[#lines + 1] = L.ROTATION_BARS_STANCE end
    lines[#lines + 1] = L.ROTATION_BARS_ASK_BACK
    local asked = Stamp(plan.slots, part.want)
    Core.Confirm(table.concat(lines, "\n"), function()
        if Blocked() then return end
        Bars.Forget()
        local now = Bars.Plan(rotation)
        if not now or Stamp(now.slots, now[mode].want) ~= asked then
            ns.Print(L.ROTATION_BARS_CHANGED)
            Book.Refresh()
            return
        end
        Run(now, now[mode], Changed(now, now[mode].want), name)
    end)
    return true
end

-- Den letzten Schritt zurücknehmen. → true, wenn gefragt wurde
function Bars.Undo()
    if Blocked() then return false end
    local step = Bars.UndoInfo()
    if not step then return false end
    local lines = { L.ROTATION_BARS_ASK_UNDO:format(tostring(step.name), Core.DateText(step.time), #step.slots) }
    local own = OwnChanges(step)
    if #own > 0 then lines[#lines + 1] = L.ROTATION_BARS_ASK_UNDO_OWN:format(Names(own)) end
    if step.tried then lines[#lines + 1] = L.ROTATION_BARS_ASK_UNDO_LAST end
    local asked = Stamp(step.slots)
    Core.Confirm(table.concat(lines, "\n"), function()
        if Blocked() then return end
        if Bars.UndoInfo() ~= step or Stamp(step.slots) ~= asked then
            ns.Print(L.ROTATION_BARS_CHANGED)
            Book.Refresh()
            return
        end
        local placed, removed, missing = BP.Restore(step.slots, step.before, { owner = OWNER })
        if not placed then ns.Print(L.ROTATION_BARS_CHANGED) return end
        ns.Print(L.ROTATION_BARS_UNDONE:format(placed, removed))
        -- Ließ sich etwas nicht ablegen, bleibt der Schritt für einen zweiten Versuch
        if #missing > 0 then ns.Print(L.ROTATION_BARS_MISSING:format(Names(Bars.BeforeNames(step, missing)))) end
        if #missing == 0 or step.tried then
            Drop(step)
        else
            step.tried = true
            for _, slot in ipairs(step.slots) do step.after[slot] = Key(slot) end
        end
        Settle()
    end)
    return true
end

-- Namen dessen, was vor dem Schritt auf diesen Plätzen lag.
function Bars.BeforeNames(step, slots)
    local out = {}
    for _, slot in ipairs(slots) do
        local data = step.before[slot] or {}
        local name = data.name
        if data.kind == "macro" and name then name = L.ROTATION_BARS_MACRO:format(name) end
        if data.kind == "item" then name = Core.Plain((Core.Call(C_Item and C_Item.GetItemNameByID, data.id))) end
        out[#out + 1] = type(name) == "string" and name or L.ROTATION_BARS_SOMETHING
    end
    return out
end

---------------------------------------------------------------------------
-- Zeilen auf der Seite „Deine Rotation“
---------------------------------------------------------------------------

local function PlaceText(bar, index)
    return bar and index and L.ROTATION_BARS_PLACE:format(bar, index) or nil
end

-- Wo eine Fähigkeit jetzt liegt, in Worten.
function Bars.NowText(item)
    if item.now then
        if item.now == item.slot then return L.ROTATION_BARS_NOW_THERE end
        return L.ROTATION_BARS_NOW_AT:format(PlaceText(item.nowBar, item.nowIndex))
    end
    return item.elsewhere and L.ROTATION_BARS_NOW_OTHER or L.ROTATION_BARS_NOW_NONE
end

-- Wo sie beim Ordnen läge.
function Bars.TargetText(item)
    return PlaceText(item.bar, item.index) or L.ROTATION_BARS_NO_SLOT
end
