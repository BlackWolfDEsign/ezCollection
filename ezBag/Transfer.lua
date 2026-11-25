local _, ns = ...
local L = ns.L

--[[
    Umlagern zwischen Tasche und Bank bzw. Gildenbank – nur für Gegenstände, die auf
    der anderen Seite schon liegen. Erst werden angebrochene Stapel aufgefüllt, dann
    (wenn gewünscht) freie Plätze genutzt.

    Anzeige: ein kleiner Pfeil oben links auf dem Platz zeigt zur Gegenseite.
      grün = passt ganz hinein, gelb = passt nur teilweise.
    Verschieben: ein Klick in der Werkzeugleiste legt alles Passende um, Schritt für
    Schritt (jeder Schritt plant neu, gesperrte Plätze werden abgewartet).

    Quellen/Ziele: "bag" (Taschen), "bank" (Charakterbank), "guild" (aktueller Gildenbank-Reiter).

    Entnehmen (weiter unten): bestimmte Mengen bzw. markierte Plätze aus Bank oder Gildenbank in die Tasche holen –
    derselbe Schritt-Ablauf, auch wenn der Gegenstand in der Tasche noch nicht liegt (Transfer.Withdraw,
    Transfer.WithdrawSlots; Schnittstelle ezCore.API("ezBag").Withdraw).
]]

local Transfer = {}
ns.Transfer = Transfer

local GUILD_SLOTS = 98
local STEP_CONTAINER, STEP_GUILD = 0.12, 0.6   -- Wartezeit zwischen zwei Schritten
local MAX_STEPS = 400
local STALL_LIMIT = 6                           -- Sekunden ohne Fortschritt → aufhören

local views = {}       -- [kind] = { view = view, frame = frame }
local marks = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Was ist offen?
---------------------------------------------------------------------------

local function GuildOpen()
    local f = _G.GuildBankFrame
    return f and f:IsShown() and (f.mode == nil or f.mode == "bank") and GetCurrentGuildBankTab ~= nil
end

local function BankOpen()
    local f = _G.BankFrame
    return f and f:IsShown() and true or false
end

-- Wohin geht es von dieser Seite aus? nil = Gegenseite nicht offen.
function Transfer.Target(source)
    if source == "bag" then
        if GuildOpen() then return "guild" end
        if BankOpen() then return "bank" end
        return nil
    elseif source == "bank" then
        return BankOpen() and "bag" or nil
    elseif source == "guild" then
        return GuildOpen() and "bag" or nil
    end
end

local function FrameOf(kind)
    if kind == "bag" then return ns.Layout and ns.Layout.Frame() end
    if kind == "bank" then return _G.BankFrame end
    if kind == "guild" then return _G.GuildBankFrame end
end

-- Pfeilrichtung von der Quelle zur Gegenseite ("left"/"right").
function Transfer.ArrowSide(source)
    local target = Transfer.Target(source)
    local a, b = FrameOf(source), FrameOf(target)
    if not (a and b) then return nil end
    local ax, bx = a:GetCenter(), b:GetCenter()
    if not ax or not bx then return "right" end
    local sa, sb = a:GetEffectiveScale(), b:GetEffectiveScale()
    return (bx * sb < ax * sa) and "left" or "right"
end

---------------------------------------------------------------------------
-- Bestandsaufnahme
---------------------------------------------------------------------------

-- Größter Stapel: ezCores eine Fassung (Core.MaxStack, Welle 23 A6 – dieselbe Regel wie vorher hier:
-- C_Item.GetItemMaxStackSizeByID, sonst GetItemInfo, sonst 1). Nur der erste Wert zählt.
local function MaxStack(itemID)
    return (ezCore.MaxStack(itemID, 1))
end

local function ItemFamily(itemID)
    local fam = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID)
    return type(fam) == "number" and fam or 0
end

-- Taschen zum Umlagern: die eine Liste aus ezCore (Rucksack, Taschen, Reagenzientasche – ohne Schlüsselbund).
function Transfer.BagIDs()
    return ezCore.BagList("sell")
end

-- Reagenzientasche zuerst (Auftrag des Nutzers vom 23.11.2026: „reagenzientasche sollte immer zuerst befüllt werden“):
-- Handwerksmaterial kommt zuerst auf ihre angebrochenen Stapel, dann auf ihre freien Plätze, erst danach in die
-- normalen Taschen. Anderes plant ezBag nie dorthin (sie nimmt nur Handwerksmaterial, Reagent.IsReagentItem).
local function IsReagent(itemID)
    local R = ns.Reagent
    return R ~= nil and R.IsReagentItem(itemID)
end

-- Passendste Tasche (Nutzer am 23.11.2026, wörtlich: „ezbag sollte es der passendste tasche zuordnen und ich habe eine
-- bergbautasche im reagienzentaschenslot“): Was nimmt eine Tasche? Seit der Durchsicht vom 24.11.2026 in ezCore
-- (Core.BagKind) – dort fragen es auch die Zählung der freien Plätze und die Post.
Transfer.BagKind, Transfer.IsProfessionBag = ezCore.BagKind, ezCore.IsProfessionBag
local IsContainerItem = ezCore.IsBagItem

local BAG_RANK = { family = 1, profession = 1, reagent = 2 }   -- Berufstasche vor Reagenzientasche vor normalen Taschen

-- Plätze, die im laufenden Durchgang ein Ablegen abgelehnt haben (Platzschlüssel bag * 1000 + slot): nicht wieder planen
-- (vorher plante jeder Schritt denselben Platz neu – Blizzards Fehlermeldung in Schleife). Leer bei jedem neuen Durchgang.
local badSlots = {}
local badBagItem = {}   -- [bag .. ":" .. itemID]: diese Tasche hat den Gegenstand abgelehnt – im Durchgang nicht mehr
local function LocKey(loc)
    if loc and loc.bag and loc.slot then return loc.bag * 1000 + loc.slot end
end
local function MarkRefused(loc, itemID)
    local key = LocKey(loc)
    if key then badSlots[key] = true end
    if loc and loc.bag and itemID then badBagItem[loc.bag .. ":" .. itemID] = true end
end
local function ClearRefused()
    wipe(badSlots)
    wipe(badBagItem)
end

local function BankIDs()
    return ns.Bank and ns.Bank.ContainerIDs and ns.Bank.ContainerIDs() or {}
end

-- slots: { loc, key, itemID, count, max, locked, bound }, free: { loc, key, family }
local function Snapshot(kind)
    local snap = { kind = kind, items = {}, free = {} }
    if kind == "guild" then
        local tab = GetCurrentGuildBankTab()
        snap.tab = tab
        for slot = 1, GUILD_SLOTS do
            local texture, count, locked = GetGuildBankItemInfo(tab, slot)
            local loc = { guild = true, tab = tab, slot = slot }
            if texture then
                local link = GetGuildBankItemLink(tab, slot)
                local itemID = ezCore.ItemID(link)   -- V-176
                if itemID then
                    snap.items[#snap.items + 1] = { loc = loc, key = slot, itemID = itemID, count = count or 1,
                        max = MaxStack(itemID), locked = locked and true or false }
                else
                    snap.blocked = true
                end
            else
                snap.free[#snap.free + 1] = { loc = loc, key = slot, family = 0 }
            end
        end
        return snap
    end
    local ids = kind == "bank" and BankIDs() or Transfer.BagIDs()
    for _, bag in ipairs(ids) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        local bagKind, family = nil, 0
        if n > 0 and kind == "bag" then
            bagKind, family = Transfer.BagKind(bag)
        elseif n > 0 then
            -- Bank-Fächer und -Taschen: nur die Familie, die der Client nennt (Blizzard prüft Berufstaschen dort nicht)
            family = ezCore.Num(select(2, C_Container.GetContainerNumFreeSlots(bag))) or 0
            if family ~= 0 then bagKind = "family" end
        end
        local special = bagKind ~= nil or nil
        local rank = BAG_RANK[bagKind] or 3
        local holds = bagKind == "profession" and {} or nil   -- was in der Berufstasche schon liegt (nur das darf dazu)
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local loc = { bag = bag, slot = slot }
            local key = bag * 1000 + slot
            local itemID = ns.ItemIDOf(info)
            if itemID then
                snap.items[#snap.items + 1] = { loc = loc, key = key, itemID = itemID,
                    count = info.stackCount or 1, max = MaxStack(itemID),
                    locked = info.isLocked and true or false, bound = info.isBound and true or false,
                    special = special, rank = rank }
                if holds then holds[itemID] = true end
            elseif not info and not badSlots[key] then
                snap.free[#snap.free + 1] = { loc = loc, key = key, family = family or 0, special = special,
                    bagKind = bagKind, holds = holds, rank = rank, order = #snap.free + 1 }
            end
        end
    end
    -- passendste Tasche zuerst: Berufstaschen, dann die Reagenzientasche, dann normale Taschen (sonst Taschenfolge)
    table.sort(snap.free, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.order < b.order
    end)
    return snap
end

-- Darf dieser Gegenstand in den freien Platz? (Spezialtaschen nur passende Arten, die Reagenzientasche nur
-- Handwerksmaterial)
local function FitsFree(free, itemID)
    if free.loc and free.loc.bag and badBagItem[free.loc.bag .. ":" .. tostring(itemID)] then return false end
    local bagKind = free.bagKind
    if bagKind == "reagent" then return IsReagent(itemID) end
    if bagKind == "profession" then return free.holds ~= nil and free.holds[itemID] == true end
    if not free.family or free.family == 0 then return true end
    if IsContainerItem(itemID) then return false end
    return bit.band(ItemFamily(itemID), free.family) ~= 0
end

-- Nimmt diese Tasche den Gegenstand? (Abschnitt Reagenzientasche: Überschrift und Grau) → ja?, Art
function Transfer.BagAccepts(bag, itemID)
    local bagKind, family = Transfer.BagKind(bag)
    local holds
    if bagKind == "profession" then
        holds = {}
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = ns.ItemIDOf(C_Container.GetContainerItemInfo(bag, slot))
            if id then holds[id] = true end
        end
    end
    return FitsFree({ bagKind = bagKind, family = family, holds = holds }, itemID), bagKind
end

-- Angebrochener Stapel im Ziel (für Plan und Entnehmen; Stapel der Reagenzientasche tragen denselben Merker).
local function AddRoom(room, it)
    if badSlots[LocKey(it.loc) or 0] then return end   -- dieser Stapel lehnte im Durchgang ab
    room[it.itemID] = room[it.itemID] or {}
    local list = room[it.itemID]
    local entry = { loc = it.loc, space = it.max - it.count, special = it.special, rank = it.rank or 3, bound = it.bound }
    -- Stapel der passendsten Tasche zuerst (Berufstasche, Reagenzientasche, normale Taschen)
    local at = #list + 1
    for i, r in ipairs(list) do
        if (r.rank or 3) > entry.rank then at = i break end
    end
    table.insert(list, at, entry)
end

-- Ein Stapel mit Platz für n (needAll: für alle n); onlySpecial: nur in der Reagenzientasche. → Platz, Menge
-- bound: Bindung des Quellstapels – ungleich gebundene Stapel tauscht das Spiel, statt sie zu vereinen (nil: egal)
local function TakeStack(stacks, n, needAll, onlySpecial, bound)
    for _, r in ipairs(stacks or {}) do
        if r.space > 0 and (not needAll or r.space >= n) and (not onlySpecial or r.special)
            and (bound == nil or r.bound == nil or r.bound == bound) then
            local fit = math.min(r.space, n)
            r.space = r.space - fit
            return r.loc, fit
        end
    end
end

-- Ein freier Platz für n Stück (der neue Stapel kann weitere Reste aufnehmen). → Platz, n
local function TakeFree(free, room, itemID, n, max, onlySpecial)
    for i, f in ipairs(free) do
        if (not onlySpecial or f.special) and FitsFree(f, itemID) then
            table.remove(free, i)
            room[itemID] = room[itemID] or {}
            table.insert(room[itemID], { loc = f.loc, space = max - n, special = f.special, rank = f.rank })
            return f.loc, n
        end
    end
end

local function GuildRights(tab)
    local _, _, viewable, canDeposit, _, remaining = GetGuildBankTabInfo(tab)
    return viewable ~= false, canDeposit and true or false, remaining
end

---------------------------------------------------------------------------
-- Planen
---------------------------------------------------------------------------

--[[
    Plan(source) → moves, status, waiting
    move    = { from = loc, to = loc, n = Anzahl, whole = ganzer Stapel? }
    status  = [Platzschlüssel der Quelle] = "all" | "part"
    waiting = ein passender Platz der Quelle ist gerade gesperrt (der Server hat einen Schritt noch nicht bestätigt)
]]
function Transfer.Plan(source)
    local target = Transfer.Target(source)
    if not target then return {}, {} end
    local src, dst = Snapshot(source), Snapshot(target)

    local canDeposit, remaining = true, nil
    if target == "guild" then
        local viewable
        viewable, canDeposit = GuildRights(dst.tab)
        if not viewable then return {}, {} end
    elseif source == "guild" then
        local viewable
        viewable, _, remaining = GuildRights(src.tab)
        if not viewable or remaining == 0 then return {}, {} end
    end
    if not canDeposit then return {}, {} end

    -- Ziel: Stapel mit Platz je Gegenstand.
    local present, room = {}, {}
    for _, it in ipairs(dst.items) do
        present[it.itemID] = true
        if not it.locked and it.count < it.max then AddRoom(room, it) end
    end
    local freeList = {}
    if not ns.S.transferStacksOnly then
        for _, f in ipairs(dst.free) do freeList[#freeList + 1] = f end
    end

    local moves, status = {}, {}
    local withdrawals = 0
    local waiting = false   -- ein passender Platz der Quelle ist gerade gesperrt (der Server antwortet noch)
    for _, it in ipairs(src.items) do
        local allowed = present[it.itemID] and not it.locked and not (target == "guild" and it.bound)
        if present[it.itemID] and it.locked and not (target == "guild" and it.bound) then waiting = true end
        if allowed then
            local left = it.count
            local function Fill(onlySpecial)
                while left > 0 do
                    local loc, n = TakeStack(room[it.itemID], left, false, onlySpecial, it.bound)
                    if not loc then return end
                    moves[#moves + 1] = { from = it.loc, to = loc, n = n, whole = (n == it.count), itemID = it.itemID }
                    left = left - n
                end
            end
            local function Free(onlySpecial)
                if left <= 0 then return end
                local loc = TakeFree(freeList, room, it.itemID, left, it.max, onlySpecial)
                if loc then
                    moves[#moves + 1] = { from = it.loc, to = loc, n = left, whole = (left == it.count), itemID = it.itemID }
                    left = 0
                end
            end
            if target == "bag" then
                Fill(true)
                Free(true)
            end
            Fill(false)
            Free(false)
            if left < it.count then
                status[it.key] = (left == 0) and "all" or "part"
                if source == "guild" then withdrawals = withdrawals + 1 end
            end
        end
    end
    -- Gildenbank: Entnahme-Limit je Tag beachten (−1 = unbegrenzt).
    if source == "guild" and remaining and remaining >= 0 and withdrawals > remaining then
        local keep, used, seen = {}, 0, {}
        for _, m in ipairs(moves) do
            if not seen[m.from.slot] then
                if used >= remaining then break end
                seen[m.from.slot] = true
                used = used + 1
            end
            keep[#keep + 1] = m
        end
        moves = keep
    end
    return moves, status, waiting
end

-- Automatisches Nachrücken (Entscheidung des Nutzers vom 23.11.2026: „ja zu automatisches Nachrücken“): Passendes aus
-- den normalen Taschen in die Spezialtaschen (Reagenzien- und Berufstaschen, Seelentasche, Köcher, Munitionsbeutel;
-- Nutzer am 23.11.2026: „es fehlt das munition autom im munitionsbeutel landet, seelensplitter ebenso bestimmt“) – zuerst auf ihre angebrochenen Stapel gleicher Bindung (ungleich
-- gebundene tauscht das Spiel, statt sie zu vereinen), dann auf ihre freien Plätze.
--   refused[itemID] = "free" (die Reagenzientasche lehnt ab) | "stack" (nur ihre Stapel) – bis /reload
--   manual[Platzschlüssel] = itemID: vom Spieler selbst in eine normale Tasche gelegt – bleibt dort, bis der Platz
--   leer oder anders belegt ist
local refused, manual = {}, {}

function Transfer.PlanReagentFill()
    local snap = Snapshot("bag")
    local room, free = {}, {}
    for _, it in ipairs(snap.items) do
        if it.special and not it.locked and it.count < it.max then
            local key = it.itemID .. (it.bound and ":b" or ":u")
            room[key] = room[key] or {}
            table.insert(room[key], { loc = it.loc, space = it.max - it.count, special = true, rank = it.rank })
        end
    end
    for _, f in ipairs(snap.free) do
        manual[f.key] = nil
        if f.special then free[#free + 1] = f end
    end
    local moves, waiting = {}, false
    for _, it in ipairs(snap.items) do
        if manual[it.key] and manual[it.key] ~= it.itemID then manual[it.key] = nil end
    end
    if next(room) == nil and #free == 0 then return moves, false end
    local function FreeFor(itemID)
        if refused[itemID] == "free" then return nil end
        for i, f in ipairs(free) do
            if FitsFree(f, itemID) then return i end
        end
    end
    for _, it in ipairs(snap.items) do
        if not it.special and not manual[it.key] then
            local stacks = refused[it.itemID] ~= "stack" and room[it.itemID .. (it.bound and ":b" or ":u")] or nil
            if (stacks and #stacks > 0) or FreeFor(it.itemID) then
                if it.locked then
                    waiting = true
                else
                    local left = it.count
                    while stacks and left > 0 do
                        local loc, n = TakeStack(stacks, left, false, true)
                        if not loc then break end
                        moves[#moves + 1] = { from = it.loc, to = loc, n = n, whole = (n == it.count), itemID = it.itemID }
                        left = left - n
                    end
                    local i = left > 0 and FreeFor(it.itemID)
                    if i then
                        local f = table.remove(free, i)
                        moves[#moves + 1] = { from = it.loc, to = f.loc, n = left, whole = (left == it.count),
                            itemID = it.itemID, toFree = true }
                    end
                end
            end
        end
    end
    return moves, waiting
end

-- Vom Spieler selbst angefasster Platz einer normalen Tasche (ITEM_LOCK_CHANGED außerhalb von ezBags Abläufen):
-- Handwerksmaterial dort rückt nicht nach.
function Transfer.MarkManual(bag, slot)
    if not (bag and slot) or Transfer.BagKind(bag) ~= nil then return end
    local itemID = ns.ItemIDOf(C_Container.GetContainerItemInfo(bag, slot))
    if itemID then manual[bag * 1000 + slot] = itemID end
end

function Transfer.Count(source)
    local moves, status = Transfer.Plan(source)
    local items = 0
    for _ in pairs(status) do items = items + 1 end
    return #moves, items
end

---------------------------------------------------------------------------
-- Pfeile auf den Plätzen
---------------------------------------------------------------------------

-- Pfeile dieser Einträge ausblenden (der Abschnitt Reagenzientasche wird aufgehoben: Blizzards Knöpfe behielten sie
-- sonst, auch wenn Blizzard sie später für eine andere Tasche nimmt).
function Transfer.ClearMarks(entries)
    for _, entry in ipairs(entries or {}) do
        local tex = entry.button and marks[entry.button]
        if tex then tex:Hide() end
    end
end

-- Für Prüfungen: die Pfeil-Marke eines Knopfs (oder nil)
function Transfer.MarkOf(button) return marks[button] end

local function Arrow(button)
    local tex = marks[button]
    if not tex then
        tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetSize(ezCore.Style.ICON.line, ezCore.Style.ICON.line)   -- Marke in Zeilengröße (16, Core.Style)
        tex:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        marks[button] = tex
    end
    return tex
end

local function EntryKey(kind, entry)
    if kind == "guild" then return entry.slot end
    if entry.bag and entry.slot then return entry.bag * 1000 + entry.slot end
end

Transfer.Arrow = function(button) return Arrow(button) end

local function MarkView(kind)
    local reg = views[kind]
    local view = reg and reg.view
    if not view then return end
    local status, side = nil, nil
    if ns.S.transferArrows and Transfer.Target(kind) then
        local _
        _, status = Transfer.Plan(kind)
        side = Transfer.ArrowSide(kind)
    end
    for _, entry in ipairs(ns.Render.Entries(view)) do   -- auch der Abschnitt Reagenzientasche (view.linked)
        local button = entry.button
        if button then
            local s = status and status[EntryKey(kind, entry)]
            if s then
                local tex = Arrow(button)
                tex:SetTexture(ns.Toolbar.ARROW[side or "right"])
                if s == "all" then tex:SetVertexColor(0.35, 1, 0.35) else tex:SetVertexColor(1, 0.85, 0.2) end
                tex:Show()
            elseif marks[button] then
                marks[button]:Hide()
            end
        end
    end
end

-- Eine Ansicht anmelden (Tasche, Bank, Gildenbank), damit sie Pfeile bekommt.
function Transfer.Register(kind, view, frame, toolbar)
    views[kind] = { view = view, frame = frame, toolbar = toolbar }
end

-- Gedrosselt über ns.Throttle (ezCore); ein Fehler in einer Ansicht hält die anderen nicht auf.
Transfer.Refresh = ns.Throttle(function()
    for kind, reg in pairs(views) do
        if reg.frame and reg.frame:IsShown() then
            local ok, err = pcall(MarkView, kind)
            if not ok then geterrorhandler()(err) end
            if reg.toolbar then reg.toolbar:Update() end
        end
    end
end, 0.05)

---------------------------------------------------------------------------
-- Verschieben
---------------------------------------------------------------------------

local runner = CreateFrame("Frame")
runner:Hide()
local run   -- { source, steps, moved, lastProgress, wait }

local function Pick(loc, n, whole)
    if loc.guild then
        if whole then PickupGuildBankItem(loc.tab, loc.slot) else SplitGuildBankItem(loc.tab, loc.slot, n) end
    else
        if whole then C_Container.PickupContainerItem(loc.bag, loc.slot)
        else C_Container.SplitContainerItem(loc.bag, loc.slot, n) end
    end
end

local function Drop(loc)
    if loc.guild then PickupGuildBankItem(loc.tab, loc.slot)
    else C_Container.PickupContainerItem(loc.bag, loc.slot) end
end

-- Platz gesperrt (der Server hat einen Schritt dorthin bzw. von dort noch nicht bestätigt)? Leer → nil
local function SlotState(loc)
    if loc.guild then
        local texture, _, locked = GetGuildBankItemInfo(loc.tab, loc.slot)
        if not texture then return nil end
        return locked and true or false
    end
    local info = C_Container.GetContainerItemInfo(loc.bag, loc.slot)
    if not info then return nil end
    return info.isLocked == true
end

-- Wartet der vorige Schritt noch auf den Server? Quelle oder Ziel gesperrt, oder das Ziel war frei und zeigt den
-- Stapel noch nicht (der Client zeigt den Platz bis zur Antwort als frei – ein zweiter Schritt dorthin würde tauschen
-- statt ablegen). Höchstens Transfer.CONFIRM_WAIT Sekunden, dann plant der nächste Durchlauf neu.
Transfer.CONFIRM_WAIT = 1.5
local function Unconfirmed(pending)
    if not pending or GetTime() - pending.since > Transfer.CONFIRM_WAIT then return false end
    local from, to = SlotState(pending.from), SlotState(pending.to)
    if from == true or to == true then return true end
    return pending.toWasFree and to == nil
end

local fillBlocked = false                    -- Nachrücken hing (MAX_STEPS oder STALL_LIMIT): bis /reload aus
local fillSaid = { n = 0, t = -math.huge }   -- Meldung des Nachrückens höchstens einmal je Transfer.FILL_SAY_EVERY
Transfer.FILL_SAY_EVERY = 60

local function Finish(reason)
    if not run then return end
    local moved, fill = run.moved, run.fill
    run = nil
    runner:Hide()
    ClearRefused()
    if fill then
        -- Nachrücken läuft ohne Klick: Was am Mauszeiger hängt, gehört dem Spieler (jeder Schritt legt sofort ab) – nie
        -- abräumen. Nur melden, was es gelegt hat, gesammelt höchstens einmal je Minute (Herstellen in Serie).
        fillSaid.n = fillSaid.n + moved
        if fillSaid.n > 0 and GetTime() - fillSaid.t >= Transfer.FILL_SAY_EVERY then
            ns.Print(L.REAGENT_FILLED:format(ns.CountWord("STACK", fillSaid.n)))
            fillSaid.n, fillSaid.t = 0, GetTime()
        end
        Transfer.Refresh()
        return
    end
    if CursorHasItem() then ClearCursor() end
    if reason then ns.Print(reason)
    elseif moved > 0 then ns.Print(L.TRANSFER_DONE:format(ns.CountWord("STACK", moved))) end
    Transfer.Refresh()
end

local WithdrawTick, FinishWithdraw   -- Entnehmen: weiter unten

runner:SetScript("OnUpdate", function(self, elapsed)
    if not run then return self:Hide() end
    run.wait = run.wait - elapsed
    if run.wait > 0 then return end
    if run.withdraw then
        run.wait = STEP_CONTAINER
        return WithdrawTick()
    end
    local guild = not run.fill and (run.source == "guild" or Transfer.Target(run.source) == "guild")
    run.wait = guild and STEP_GUILD or STEP_CONTAINER

    if ns.InCombat() then return Finish(ezCore.CombatText(L.TRANSFER_WHAT)) end
    if not run.fill and not Transfer.Target(run.source) then return Finish() end
    if run.fill and GetCursorInfo() ~= nil then return Finish() end   -- der Spieler hält etwas: Nachrücken weicht
    if CursorHasItem() then
        -- Der Spieler hält gerade etwas – nicht dazwischenfunken.
        if GetTime() - run.lastProgress > STALL_LIMIT then return Finish(L.TRANSFER_STOPPED) end
        return
    end

    if Unconfirmed(run.pending) then return end
    local sent = run.pending
    run.pending = nil
    -- (Quelle wieder entsperrt: der Server hat geantwortet; noch gesperrt heißt nur, er ist langsam)
    if sent and sent.toWasFree and SlotState(sent.to) == nil and SlotState(sent.from) == false then
        -- Abgeschickt, aber nie angekommen (der Server lehnte ab): nicht zählen, Platz und Tasche meiden
        run.moved = math.max(0, run.moved - 1)
        MarkRefused(sent.to, sent.itemID)
        if run.fill and sent.itemID then refused[sent.itemID] = "free" end
    end

    local moves, waiting
    if run.fill then moves, waiting = Transfer.PlanReagentFill()
    else moves, _, waiting = Transfer.Plan(run.source) end
    local stalled = GetTime() - run.lastProgress > STALL_LIMIT
    if #moves == 0 then
        -- Passendes liegt noch auf gesperrten Plätzen: abwarten, dann geht es weiter (statt nach einem Teil aufzuhören)
        if waiting and not stalled then return end
        return Finish()
    end
    if run.steps >= MAX_STEPS or stalled then
        if run.fill then fillBlocked = true end   -- Nachrücken hing: bis /reload nicht wieder anstoßen
        return Finish(L.TRANSFER_STOPPED)
    end

    local m = moves[1]
    run.steps = run.steps + 1
    local toWasFree = SlotState(m.to) == nil
    Pick(m.from, m.n, m.whole)
    if CursorHasItem() then
        Drop(m.to)
        if CursorHasItem() then
            -- Ablegen abgelehnt (der Platz nimmt den Gegenstand nicht): zurücklegen, nicht zählen – bleibt es dabei,
            -- hört das Umlagern nach STALL_LIMIT auf. Beim Nachrücken bleibt dieser Gegenstand danach liegen.
            ClearCursor()
            MarkRefused(m.to, m.itemID)
            if run.fill and m.itemID then refused[m.itemID] = m.toFree and "free" or "stack" end
            return
        end
        run.moved = run.moved + 1
        run.lastProgress = GetTime()
        run.pending = { from = m.from, to = m.to, toWasFree = toWasFree, since = GetTime(), itemID = m.itemID }
    end
end)

-- Ein Klick (Umlagern, Entnehmen) hat Vorrang: laufendes Nachrücken beenden (meldet, was es schon gelegt hat).
local function YieldFill()
    if run and run.fill then Finish() end
end

function Transfer.Run(source)
    YieldFill()
    if run and run.withdraw then return FinishWithdraw("stopped") end
    if run then return Finish(L.TRANSFER_STOPPED) end
    if not Transfer.Target(source) then return end
    if ns.InCombat() then return ezCore.CombatNotice(ns, L.TRANSFER_WHAT) end
    local moves = Transfer.Plan(source)
    if #moves == 0 then return ns.Print(L.TRANSFER_NOTHING) end
    wipe(badSlots)
    run = { source = source, steps = 0, moved = 0, lastProgress = GetTime(), wait = 0 }
    runner:Show()
end

function Transfer.Running()
    return run ~= nil
end

---------------------------------------------------------------------------
-- Entnehmen: aus Bank bzw. Gildenbank in die Tasche (BAG-08, BAG-09)
---------------------------------------------------------------------------

--[[
    Zwei Aufträge über denselben Ablauf wie das Umlagern (ein Schritt je Durchlauf, jeder Schritt plant neu,
    gesperrte Plätze werden abgewartet, nie im Kampf):
      Transfer.Withdraw(itemMap, onDone)      { [itemID] = Anzahl } aus der offenen Bank und dem offenen Fach der
                                              Gildenbank holen, auch Teilmengen eines Stapels. Schnittstelle
                                              ezCore.API("ezBag").Withdraw (z. B. ezCrafts „Aus der Bank holen“)
      Transfer.WithdrawSlots(slots, onDone)   markierte Plätze des offenen Gildenbank-Fachs holen, je ganzer Stapel
                                              (Eintrag „In die Tasche legen (n)“ der Auswahl, Select.lua)
    Gildenbank: Jeder Schritt zählt als eine Entnahme des Rangs (GetGuildBankTabInfo: verbleibende Entnahmen,
    −1 = unbegrenzt). Ist das Limit erreicht, hört der Auftrag mit einer Meldung auf. Darum nimmt die Gildenbank
    zuerst einen Platz, in den der Stapel ganz passt (ein Schritt je Stapel); die Bank füllt zuerst angebrochene
    Stapel. Die Einstellung „nur angebrochene Stapel auffüllen“ gilt hier nicht – der Auftrag nennt, was er will.
    Bestätigung: Ein Schritt zählt erst, wenn beide Seiten ihn zeigen – der Bestand des Gegenstands in der Tasche
    ist um die Menge gestiegen und der Platz der Quelle hat sie abgegeben. Bis dahin wird nicht weitergeplant
    (der Client zeigt den Zielplatz bis zur Antwort des Servers noch als frei; ein zweiter Schritt dorthin würde
    tauschen statt ablegen). Bleibt die Bestätigung aus, endet der Auftrag mit "stopped"; abgerechnet wird immer,
    was wirklich in der Tasche ankam.
    Ende: Meldung im Chat (was in die Tasche kam, was fehlt und warum) und onDone(fehlt, Grund).
    Gründe: nil (fertig), "full" Tasche voll, "limit" Entnahme-Limit, "closed" Bank geschlossen, "combat",
            "stopped" (hängt oder vom Nutzer gestoppt); nur als Rückgabe beim Start: "input", "busy", "nothing".
    Im Stub geprüft (Tests/ui_test.lua); im Spiel zu bestätigen, bevor ein anderes Modul sich darauf verlässt.
]]

local REASON_TEXT = { full = "WITHDRAW_FULL", limit = "WITHDRAW_LIMIT", closed = "WITHDRAW_CLOSED",
    stopped = "TRANSFER_STOPPED", busy = "WITHDRAW_BUSY", nothing = "WITHDRAW_NOTHING" }

-- Text zu einem Grund (auch für Aufrufer, die ihn selbst zeigen); nil ohne Grund oder bei "input". Der Kampf sagt es
-- in ezCores Wortlaut (T18-1).
function Transfer.ReasonText(reason)
    if reason == "combat" then return ezCore.CombatText(L.TRANSFER_WHAT) end
    local key = reason and REASON_TEXT[reason]
    return key and L[key] or nil
end

-- „3× Kupfererz, 1× Leinenstoff“ aus { [itemID] = Anzahl }, nach Namen sortiert; "" ohne Einträge.
local function ItemList(map)
    local list = {}
    for itemID, n in pairs(map or {}) do
        if n > 0 then
            local name = ezCore.ItemNameByID(itemID) or ("%s %d"):format(L.MENU_TITLE_FALLBACK, itemID)
            list[#list + 1] = { name = name, text = L.WITHDRAW_ITEM:format(n, name) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    for i, entry in ipairs(list) do list[i] = entry.text end
    return table.concat(list, ", ")
end
Transfer.ItemList = ItemList

-- Ist die Quelle des Auftrags (noch) offen? Ein Schließen-Ereignis zählt sofort, auch wenn das Fenster noch steht.
local function SourceOpen(kind, job)
    if job and job.closed[kind] then return false end
    if kind == "bank" then return BankOpen() end
    if kind == "guild" then return GuildOpen() and true or false end
    return false
end

-- Wie viele Entnahmen erlaubt das Fach noch? → Zahl oder nil (unbegrenzt); 0, wenn das Fach nicht einsehbar ist.
local function GuildBudget(tab, job)
    local viewable, _, remaining = GuildRights(tab)
    if not viewable then return 0 end
    remaining = ezCore.Plain(remaining)
    local budget
    if type(remaining) == "number" and remaining >= 0 then budget = remaining end
    -- Eigene Zählung daneben: Blizzards Zahl kann der letzten Entnahme hinterherhinken.
    if job and job.guildStart and job.guildTab == tab then
        local own = job.guildStart - job.guildUsed
        if not budget or own < budget then budget = own end
    end
    return budget
end

-- Platz in der Tasche: angebrochene Stapel je Gegenstand und freie Plätze.
local function BagRoom()
    local snap = Snapshot("bag")
    local room, free = {}, {}
    for _, it in ipairs(snap.items) do
        if not it.locked and it.count < it.max then AddRoom(room, it) end
    end
    for _, f in ipairs(snap.free) do free[#free + 1] = f end
    return room, free
end

-- Wohin mit n Stück? → Platz, Menge, die dorthin geht (nil: kein Platz mehr). wholeFirst (Gildenbank, jede
-- Entnahme zählt): erst ein Stapel, in den alles passt, dann ein freier Platz, dann Stapel mit Restplatz.
-- Sonst (Bank): erst angebrochene Stapel auffüllen, dann ein freier Platz.
-- Handwerksmaterial zuerst in die Reagenzientasche (ihre Stapel, dann ihre freien Plätze), danach wie beschrieben.
local function Spot(room, free, itemID, n, max, wholeFirst, bound)
    local loc, fit
    loc, fit = TakeStack(room[itemID], n, wholeFirst, true, bound)
    if not loc then loc, fit = TakeFree(free, room, itemID, n, max, true) end
    if not loc and wholeFirst then
        loc, fit = TakeStack(room[itemID], n, true, nil, bound)
        if not loc then loc, fit = TakeFree(free, room, itemID, n, max) end
    end
    if not loc then loc, fit = TakeStack(room[itemID], n, false, nil, bound) end
    if not loc then loc, fit = TakeFree(free, room, itemID, n, max) end
    return loc, fit
end

-- Ein Platz der Quelle (it) soll „take“ Stück abgeben: Schritte anhängen, solange Tasche und Limit reichen.
-- → wie viel untergebracht wurde
local function PlanTake(ctx, it, take, kind, ref)
    local placed, avail = 0, it.count
    while take > 0 do
        if kind == "guild" and ctx.budget and ctx.budget <= 0 then
            ctx.info.limit = true
            break
        end
        local loc, fit = Spot(ctx.room, ctx.free, it.itemID, take, it.max, kind == "guild", it.bound)
        if not loc then
            ctx.info.full = true
            break
        end
        ctx.moves[#ctx.moves + 1] = { from = it.loc, to = loc, n = fit, whole = (fit == avail), itemID = it.itemID,
            kind = kind, ref = ref }
        avail, take, placed = avail - fit, take - fit, placed + fit
        if kind == "guild" and ctx.budget then ctx.budget = ctx.budget - 1 end
    end
    return placed
end

--[[
    PlanJob(job) → moves, info, fehlt
    move  = { from = loc, to = loc, n = Anzahl, whole = ganzer Stapel?, itemID, kind = "bank"|"guild", ref = Platz des Auftrags }
    info  = { waiting = ein Platz ist gerade gesperrt, full = Tasche voll, limit = Entnahme-Limit erreicht }
    fehlt = { [itemID] = Anzahl } (Auftrag nach Gegenständen) bzw. Zahl der Plätze, die bleiben (Auftrag nach Plätzen)
]]
local function PlanJob(job)
    local room, free = BagRoom()
    local ctx = { room = room, free = free, moves = {}, info = { waiting = false, full = false, limit = false } }
    if job.slots then
        local bySlot, tab = {}, nil
        if SourceOpen("guild", job) then
            local src = Snapshot("guild")
            tab = src.tab
            ctx.budget = GuildBudget(tab, job)
            for _, it in ipairs(src.items) do bySlot[it.key] = it end
        end
        local left = 0
        for _, s in ipairs(job.slots) do
            if not s.done then
                -- Anderes Fach, inzwischen leer oder anders belegt: der Platz bleibt, wie er ist.
                local it = s.tab == tab and bySlot[s.slot] or nil
                if not (it and it.itemID == s.itemID) then
                    left = left + 1
                elseif it.locked then
                    ctx.info.waiting = true
                    left = left + 1
                elseif PlanTake(ctx, it, it.count, "guild", s) < it.count then
                    left = left + 1
                end
            end
        end
        return ctx.moves, ctx.info, left
    end
    local left = {}
    for itemID, n in pairs(job.left) do
        if n > 0 then left[itemID] = n end
    end
    for _, kind in ipairs(job.sources) do
        if SourceOpen(kind, job) then
            local src = Snapshot(kind)
            ctx.budget = kind == "guild" and GuildBudget(src.tab, job) or nil
            for _, it in ipairs(src.items) do
                local need = left[it.itemID]
                if need and need > 0 then
                    if it.locked then
                        ctx.info.waiting = true
                    else
                        left[it.itemID] = need - PlanTake(ctx, it, math.min(need, it.count), kind)
                    end
                end
            end
        end
    end
    local missing = {}
    for itemID, n in pairs(left) do
        if n > 0 then missing[itemID] = n end
    end
    return ctx.moves, ctx.info, missing
end

-- Warum geht (gerade) nichts? Für die Rückgabe beim Start und das Ende des Auftrags.
local function WhyNot(info, atStart)
    if info.limit then return "limit" end
    if info.full then return "full" end
    if atStart then return info.waiting and "busy" or "nothing" end
    return nil
end

-- Bestand eines Gegenstands in der Tasche (alle Plätze der Umlagern-Taschen, auch gesperrte).
local function BagCount(itemID)
    local n = 0
    for _, it in ipairs(Snapshot("bag").items) do
        if it.itemID == itemID then n = n + it.count end
    end
    return n
end

-- Was liegt gerade auf einem Platz der Quelle? → Gegenstand (nil: leer oder unlesbar), Anzahl
local function SourceState(loc)
    if loc.guild then
        local texture, count = GetGuildBankItemInfo(loc.tab, loc.slot)
        if not texture then return nil, 0 end
        local link = GetGuildBankItemLink(loc.tab, loc.slot)
        return ezCore.ItemID(link), count or 1   -- V-176
    end
    local info = C_Container.GetContainerItemInfo(loc.bag, loc.slot)
    if not info then return nil, 0 end
    return ns.ItemIDOf(info), info.stackCount or 1
end

-- Um wie viel ist der Bestand in der Tasche seit dem offenen Schritt gestiegen? (0 … Menge des Schritts)
local function Arrived(p)
    return math.max(0, math.min(p.n, BagCount(p.itemID) - p.bagBefore))
end

-- Ist der offene Schritt bestätigt? Die Tasche zeigt die Menge und der Platz der Quelle hat sie abgegeben
-- (leer, anders belegt oder um die Menge kleiner).
local function Confirmed(p)
    if Arrived(p) < p.n then return false end
    local itemID, count = SourceState(p.from)
    return itemID ~= p.itemID or count <= p.srcBefore - p.n
end

-- Den offenen Schritt abrechnen: „amount“ Stück kamen an. Ein markierter Platz gilt erst als geholt, wenn sein
-- ganzer Stapel ankam.
local function Book(job, amount)
    local p = job.pending
    job.pending = nil
    if not p or amount <= 0 then return end
    job.got[p.itemID] = (job.got[p.itemID] or 0) + amount
    if job.slots then
        if p.whole and p.ref and amount >= p.n then p.ref.done = true end
    else
        job.left[p.itemID] = math.max(0, (job.left[p.itemID] or 0) - amount)
    end
end

local function NewJob(job)
    job.got, job.closed, job.guildUsed = {}, {}, 0
    for _, kind in ipairs(job.sources) do
        if kind == "guild" then
            local tab = GetCurrentGuildBankTab()
            local _, _, remaining = GuildRights(tab)
            remaining = ezCore.Plain(remaining)
            if type(remaining) == "number" and remaining >= 0 then job.guildStart, job.guildTab = remaining, tab end
        end
    end
    return job
end

local function StartJob(job)
    wipe(badSlots)
    run = { withdraw = job, steps = 0, moved = 0, lastProgress = GetTime(), wait = 0 }
    runner:Show()
end

function FinishWithdraw(reason)
    if not (run and run.withdraw) then return end
    local job = run.withdraw
    run = nil
    runner:Hide()
    ClearRefused()
    if CursorHasItem() then ClearCursor() end
    -- Ein noch unbestätigter Schritt zählt mit dem, was bis jetzt in der Tasche ankam.
    if job.pending then Book(job, Arrived(job.pending)) end
    local text = Transfer.ReasonText(reason)
    if text then ns.Print(text) end
    local got = ItemList(job.got)
    if got ~= "" then ns.Print(L.WITHDRAW_DONE:format(got)) end
    local missing
    if job.slots then
        missing = 0
        for _, s in ipairs(job.slots) do
            if not s.done then missing = missing + 1 end
        end
        if missing > 0 then ns.Print(ns.CountText("WITHDRAW_LEFT", missing)) end
    else
        missing = {}
        for itemID, n in pairs(job.left) do
            if n > 0 then missing[itemID] = n end
        end
        local list = ItemList(missing)
        if list ~= "" then ns.Print(L.WITHDRAW_MISSING:format(list)) end
    end
    Transfer.Refresh()
    if type(job.onDone) == "function" then
        local ok, err = pcall(job.onDone, missing, reason)
        if not ok then ns.Error(err, "Withdraw") end
    end
end

function WithdrawTick()
    local job = run.withdraw
    if job.pending and Confirmed(job.pending) then
        Book(job, job.pending.n)
        run.lastProgress = GetTime()
    end
    if ns.InCombat() then return FinishWithdraw("combat") end
    local open = false
    for _, kind in ipairs(job.sources) do
        if SourceOpen(kind, job) then open = true end
    end
    if not open then return FinishWithdraw("closed") end
    local stalled = GetTime() - run.lastProgress > STALL_LIMIT
    if CursorHasItem() then
        -- Der Spieler hält gerade etwas – nicht dazwischenfunken.
        if stalled then return FinishWithdraw("stopped") end
        return
    end
    if job.pending then
        -- Der Server hat den letzten Schritt noch nicht bestätigt: nicht weiterplanen (der Zielplatz gilt im
        -- Client noch als frei).
        if stalled then return FinishWithdraw("stopped") end
        return
    end
    local moves, info = PlanJob(job)
    if #moves == 0 then
        if info.waiting then
            -- Gesperrte Plätze abwarten (z. B. hält der Spieler den Stapel gerade selbst).
            if stalled then return FinishWithdraw("stopped") end
            return
        end
        return FinishWithdraw(WhyNot(info, false))
    end
    if run.steps >= MAX_STEPS or stalled then return FinishWithdraw("stopped") end

    local m = moves[1]
    run.steps = run.steps + 1
    run.wait = m.kind == "guild" and STEP_GUILD or STEP_CONTAINER
    local bagBefore = BagCount(m.itemID)
    local _, srcBefore = SourceState(m.from)
    Pick(m.from, m.n, m.whole)
    if not CursorHasItem() then return end   -- nichts aufgenommen: der nächste Durchlauf plant neu
    Drop(m.to)
    if CursorHasItem() then
        -- Kam nicht an (Ziel inzwischen belegt): zurücklegen, nichts abziehen, neu planen. Kein Sperren wie beim Umlagern:
        -- ein gerade belegtes Ziel ist oft gleich wieder frei; Berufstaschen meidet schon die Planung (FitsFree).
        ClearCursor()
        return
    end
    -- Abgeschickt, noch nicht abgerechnet: got, left und „Platz geholt“ bucht erst die Bestätigung (Book).
    run.moved = run.moved + 1
    run.lastProgress = GetTime()
    if m.kind == "guild" then job.guildUsed = job.guildUsed + 1 end
    job.pending = { itemID = m.itemID, n = m.n, whole = m.whole, ref = m.ref, from = m.from,
        bagBefore = bagBefore, srcBefore = srcBefore }
end

-- Bank oder Gildenbank ging zu: Steht keine Quelle des Auftrags mehr offen, bricht er mit Meldung ab.
local function SourceClosed(kind)
    local job = run and run.withdraw
    if not job then return end
    job.closed[kind] = true
    for _, source in ipairs(job.sources) do
        if SourceOpen(source, job) then return end
    end
    FinishWithdraw("closed")
end

--[[
    Withdraw(itemMap, onDone) → begonnen, fehlt, Grund
      itemMap = { [itemID] = Anzahl }; holt die Mengen aus der offenen Bank und dem offenen Fach der Gildenbank.
      begonnen = true, wenn der Auftrag läuft (er arbeitet dann Schritt für Schritt weiter).
      fehlt    = { [itemID] = Anzahl }: was nach dem Stand beim Start nicht geholt werden kann (leer: alles kommt).
      Grund    = nur ohne Start: "input" (nichts Brauchbares verlangt), "busy" (es wird schon umgelagert), "combat",
                 "closed" (weder Bank noch Gildenbank offen), "nothing" (nichts davon liegt dort), "full", "limit".
      onDone(fehlt, Grund) = am Ende des Auftrags mit dem, was wirklich fehlt (Grund wie im Kopf dieses Abschnitts).
]]
function Transfer.Withdraw(itemMap, onDone)
    local want, any = {}, false
    if type(itemMap) == "table" then
        for itemID, n in pairs(itemMap) do
            itemID, n = ns.PlainID(itemID), ezCore.Plain(n)
            if type(itemID) == "number" and type(n) == "number" and n >= 1 then
                want[itemID] = math.floor(n)
                any = true
            end
        end
    end
    if not any then return false, {}, "input" end
    YieldFill()
    if run then return false, want, "busy" end
    if ns.InCombat() then return false, want, "combat" end
    local sources = {}
    if BankOpen() then sources[#sources + 1] = "bank" end
    if GuildOpen() then sources[#sources + 1] = "guild" end
    if #sources == 0 then return false, want, "closed" end
    local job = NewJob({ left = want, sources = sources, onDone = onDone })
    local moves, info, missing = PlanJob(job)
    if #moves == 0 then return false, missing, WhyNot(info, true) end
    StartJob(job)
    return true, missing
end

--[[
    WithdrawSlots(slots, onDone) → begonnen, Grund
      slots = { { tab = Fach, slot = Platz, itemID = erwarteter Gegenstand }, … } im offenen Fach der Gildenbank;
      je Platz der ganze Stapel. Ein Platz, der inzwischen leer oder anders belegt ist, bleibt unberührt.
      onDone(übrig, Grund) = am Ende mit der Zahl der Plätze, die nicht (ganz) geholt wurden.
]]
function Transfer.WithdrawSlots(slots, onDone)
    local list = {}
    for _, s in ipairs(type(slots) == "table" and slots or {}) do
        if type(s) == "table" and type(s.tab) == "number" and type(s.slot) == "number" and type(s.itemID) == "number" then
            list[#list + 1] = { tab = s.tab, slot = s.slot, itemID = s.itemID }
        end
    end
    if #list == 0 then return false, "input" end
    YieldFill()
    if run then return false, "busy" end
    if ns.InCombat() then return false, "combat" end
    if not GuildOpen() then return false, "closed" end
    local job = NewJob({ slots = list, sources = { "guild" }, onDone = onDone })
    local moves, info = PlanJob(job)
    if #moves == 0 then return false, WhyNot(info, true) end
    StartJob(job)
    return true
end

-- Schnittstelle für andere Module (ezCore.API("ezBag")): Material aus der Bank holen, z. B. für ezCrafts Einkaufsliste.
ns.API = ns.API or {}
ns.API.Withdraw = Transfer.Withdraw

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "GUILDBANKBAGSLOTS_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }) do
    ns.On(event, function(e)
        if (e == "BANKFRAME_CLOSED" or e == "GUILDBANKFRAME_CLOSED") and run then
            if run.withdraw then
                SourceClosed(e == "BANKFRAME_CLOSED" and "bank" or "guild")
            else
                Finish()
            end
        end
        Transfer.Refresh()
    end)
end

ns.OnSettingChanged(function(key)
    if key == "transferArrows" or key == "transferStacksOnly" then Transfer.Refresh() end
end)

---------------------------------------------------------------------------
-- Automatisches Nachrücken in Spezialtaschen (Schalter „In Spezialtaschen nachrücken“, reagentAutoFill)
---------------------------------------------------------------------------

local sortPauseUntil = 0   -- Blizzards „Tasche aufräumen“ läuft: Nachrücken und Merken eigener Plätze ruhen

-- Läuft gerade etwas, in das Nachrücken nicht hineingreifen darf? Kampf, ein anderer Ablauf, etwas am Mauszeiger,
-- Sortieren, ezBags Stapel-Bau oder Anzahl-Feld, Verkaufen/Umlegen (Select.UseAll), ezCores Anhang-Schlange und
-- offene Fenster von Handel, Händler, Post, Auktionshaus oder Blizzards Teil-Fenster.
function Transfer.FillBusy()
    if not (ns.S and ns.S.reagentAutoFill) or fillBlocked or run or ns.InCombat() then return true end
    if GetCursorInfo() ~= nil or GetTime() < sortPauseUntil then return true end
    local St = ns.Stacks
    if St and St.Building and St.Building() then return true end
    local field = St and St.Field and St.Field()
    if field and field.IsShown and field:IsShown() then return true end
    if ns.Select and ns.Select.Busy and ns.Select.Busy() then return true end
    local queue = ezCore.MailQueue
    if queue and ((queue.IsAttaching and queue.IsAttaching()) or (queue.IsBusy and queue.IsBusy())) then return true end
    for _, name in ipairs({ "TradeFrame", "MerchantFrame", "MailFrame", "AuctionHouseFrame", "StackSplitFrame" }) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

-- Jetzt nachrücken? → begonnen?
function Transfer.MaybeFillReagents()
    if Transfer.FillBusy() then return false end
    if #Transfer.PlanReagentFill() == 0 then return false end
    wipe(badSlots)
    run = { fill = true, steps = 0, moved = 0, lastProgress = GetTime(), wait = 0 }
    runner:Show()
    return true
end

-- Nach jeder Taschenänderung, nach dem Kampf, wenn der Mauszeiger frei wird und wenn Händler, Post, Auktionshaus oder
-- Handel schließen: eine halbe Sekunde nach dem letzten Ereignis prüfen (jedes neue Ereignis schiebt die Prüfung).
local fillToken = 0
local function QueueFill()
    fillToken = fillToken + 1
    local mine = fillToken
    C_Timer.After(0.5, function()
        if mine == fillToken then Transfer.MaybeFillReagents() end
    end)
end
Transfer.QueueFill = QueueFill
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED", "MERCHANT_CLOSED", "MAIL_CLOSED",
    "AUCTION_HOUSE_CLOSED", "TRADE_CLOSED" }) do
    ns.On(event, QueueFill)
end

-- Vom Spieler selbst angefasste Plätze merken (nicht während ezBags Abläufen oder Blizzards Sortieren)
ns.On("ITEM_LOCK_CHANGED", function(_, bag, slot)
    if run or GetTime() < sortPauseUntil then return end
    if ns.Select and ns.Select.Busy and ns.Select.Busy() then return end
    if ns.Stacks and ns.Stacks.Building and ns.Stacks.Building() then return end
    Transfer.MarkManual(bag, slot)
end)

-- Blizzards „Tasche aufräumen“: ein paar Sekunden ruhen, danach prüfen
Transfer.SORT_PAUSE = 5
function Transfer.OnSortBags()
    sortPauseUntil = GetTime() + Transfer.SORT_PAUSE
    C_Timer.After(Transfer.SORT_PAUSE + 0.5, QueueFill)
end
if type(hooksecurefunc) == "function" and type(C_Container) == "table" and type(C_Container.SortBags) == "function" then
    hooksecurefunc(C_Container, "SortBags", Transfer.OnSortBags)
end

-- Für Prüfungen: abgelehnte Gegenstände vergessen
function Transfer.ResetRefused() wipe(refused); wipe(manual); fillBlocked = false; sortPauseUntil = 0 end
