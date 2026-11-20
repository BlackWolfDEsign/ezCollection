local _, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Material bei Twinks anfordern und am Briefkasten verschicken.

    Im Berufefenster fehlt einem Charakter Material, das ein Twink hat: „Bei Twinks anfordern“ legt Sendungen an
    (ezCraftDB.shipments, für alle Twinks gemeinsam):
      { from = charKey des Twinks mit dem Material, to = charKey des Herstellers, items = { [itemID] = Anzahl },
        note = Rezept oder „Einkaufsliste“, created = time() }
    Öffnet der Twink später den Briefkasten, zeigt der Seitenreiter am Senden-Fenster (MailTab.lua) die Sendungen;
    ein Klick verschickt sie über die eine Versand-Warteschlange von ezCore (ezCore.MailQueue).
    Verschickt wird nur, was in der Tasche liegt; ganze Stapel, der Rest wird abgeteilt (MailQueue: split).
    Was wirklich ankam, misst ezCraft an der Tasche vor und nach dem Brief.
]]

local Ship = {}
ns.Shipments = Ship

local min, max = math.min, math.max
local EMPTY = {}

local function List() return ns.db and ns.db.shipments or EMPTY end
local function Changed() ns.Fire("SHIPMENTS_CHANGED") end

local function Find(from, to)
    for index, s in ipairs(List()) do
        if s.from == from and s.to == to then return s, index end
    end
    return nil
end

local function IsEmpty(items)
    for _, n in pairs(items or EMPTY) do
        if n > 0 then return false end
    end
    return true
end

function Ship.All() return List() end

-- Bereits angefordert: von einem Twink (from) bzw. für einen Empfänger (to); nil = alle.
function Ship.Requested(from, to, itemID)
    local n = 0
    for _, s in ipairs(List()) do
        if (from == nil or s.from == from) and (to == nil or s.to == to) then n = n + (s.items[itemID] or 0) end
    end
    return n
end

-- Sendungen, die der aktuelle Charakter verschicken soll, und solche, die zu ihm unterwegs sein sollen.
function Ship.Outgoing()
    local out = {}
    for _, s in ipairs(List()) do
        if s.from == Core.charKey and not IsEmpty(s.items) then out[#out + 1] = s end
    end
    return out
end

function Ship.Incoming()
    local out = {}
    for _, s in ipairs(List()) do
        if s.to == Core.charKey and not IsEmpty(s.items) then out[#out + 1] = s end
    end
    return out
end

function Ship.Counts() return #Ship.Outgoing(), #Ship.Incoming() end

local function Add(from, to, itemID, count, note)
    local s = Find(from, to)
    if not s then
        s = { from = from, to = to, items = {}, created = Core.Now() }
        table.insert(ns.db.shipments, s)
    end
    s.items[itemID] = (s.items[itemID] or 0) + count
    s.note = note or s.note
end

-- needs = { [itemID] = Anzahl, die in der eigenen Tasche fehlt }. Bereits Angefordertes zählt mit.
-- Twinks mit dem meisten Material zuerst (erreichbare, siehe Data.Recipient).
-- Rückgabe: Anzahl angeforderter Gegenstände, Rest { [itemID] = Anzahl }, den kein Twink hat.
function Ship.Request(needs, note)
    local me = Core.charKey
    local requested, rest = 0, {}
    if not (ns.db and me) then return 0, needs end
    for itemID, want in pairs(needs or EMPTY) do
        local left = want - Ship.Requested(nil, me, itemID)
        if left > 0 then
            for _, alt in ipairs(Data.Stock(itemID).altList) do
                if left <= 0 then break end
                if alt.mailable then
                    local free = alt.total - Ship.Requested(alt.key, nil, itemID)
                    local take = min(left, free)
                    if take > 0 then
                        Add(alt.key, me, itemID, take, note)
                        left = left - take
                        requested = requested + take
                    end
                end
            end
        end
        if left > 0 then rest[itemID] = left end
    end
    if requested > 0 then Changed() end
    return requested, rest
end

function Ship.Remove(shipment)
    for index, s in ipairs(List()) do
        if s == shipment then
            table.remove(ns.db.shipments, index)
            Changed()
            return true
        end
    end
    return false
end

-- „Mira: 20× Kupfererz, 5× Leinenstoff“
function Ship.ItemsText(items)
    local parts = {}
    for itemID, n in pairs(items or EMPTY) do
        if n > 0 then parts[#parts + 1] = L.SHIP_ITEM:format(n, Data.ItemName(itemID)) end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function Ship.Describe(s)
    local function Name(key)
        if key == Core.charKey then return L.YOU end
        return Core.CharName(Core.Char(key), key)
    end
    return L.SHIP_LINE:format(Name(s.from), Name(s.to), Ship.ItemsText(s.items))
end

---------------------------------------------------------------------------
-- Verschicken am Briefkasten
---------------------------------------------------------------------------

-- Taschen, aus denen verschickt wird: ezCores Liste "sell" (Rucksack, Taschen und Reagenzientasche, ohne
-- Schlüsselbund) – dieselbe Regel wie beim Verkaufen und Umlagern, statt nur der normalen Taschen.
local SEND_BAGS = "sell"

-- Anzahl eines Gegenstands in den Taschen (live, wie die Einträge für die Warteschlange).
local function BagCount(itemID)
    local n = 0
    Core.ForEachBagItem(function(_, _, info)
        if info.itemID == itemID then n = n + (info.stackCount or 1) end
    end, SEND_BAGS)
    return n
end
Ship.BagCount = BagCount

-- Einträge für ezCore.MailQueue: ganze Stapel, solange sie passen, den Rest abgeteilt.
-- Rückgabe: Einträge, geplant { [itemID] = Anzahl }.
function Ship.Entries(items)
    local slots = {}
    Core.ForEachBagItem(function(bag, slot, info)
        local want = items[info.itemID]
        if want and want > 0 and not info.isLocked and not info.isBound then
            slots[info.itemID] = slots[info.itemID] or {}
            table.insert(slots[info.itemID], { bag = bag, slot = slot, count = info.stackCount or 1 })
        end
    end, SEND_BAGS)
    local entries, planned = {}, {}
    local ids = {}
    for itemID in pairs(items) do ids[#ids + 1] = itemID end
    table.sort(ids)
    for _, itemID in ipairs(ids) do
        local left = items[itemID] or 0
        local list = slots[itemID] or EMPTY
        table.sort(list, function(a, b) return a.count > b.count end)
        for _, s in ipairs(list) do
            if left <= 0 then break end
            if s.count <= left then
                entries[#entries + 1] = { bag = s.bag, slot = s.slot, itemID = itemID }
                left = left - s.count
            else
                entries[#entries + 1] = { bag = s.bag, slot = s.slot, itemID = itemID, split = left }
                left = 0
            end
        end
        local n = (items[itemID] or 0) - left
        if n > 0 then planned[itemID] = n end
    end
    return entries, planned
end

local sending, sendAll
-- Sendungen, von denen in diesem Durchlauf nichts rausging (Stapel nicht verschickbar, Postfach des Empfängers
-- voll …): „Alle verschicken“ fasst sie nicht noch einmal an, sonst liefe es endlos im Kreis (V-142).
local stuck = setmetatable({}, { __mode = "k" })

function Ship.IsSending() return sending ~= nil end
function Ship.IsStuck(shipment) return stuck[shipment] == true end

-- Ist der Briefkasten noch offen? ezCores Stand (Core.Mail.IsOpen, falsch schon während MAILBOX_CLOSED), dazu
-- Blizzards Postfenster. Fehlt beides, gilt er als offen (dann bleibt es bei der bisherigen Meldung).
local function MailboxOpen()
    local M = Core.Mail
    if M and type(M.IsOpen) == "function" then
        local ok, open = pcall(M.IsOpen)
        if ok and not open then return false end
    end
    local frame = _G.MailFrame
    if frame and type(frame.IsShown) == "function" and not frame:IsShown() then return false end
    return true
end

-- Verschickt die erste Sendung des aktuellen Charakters, deren Material in der Tasche liegt.
-- all = true: danach die nächste, bis keine mehr übrig ist.
function Ship.SendNext(all)
    if all ~= nil then
        sendAll = all
        wipe(stuck)   -- neuer Anlauf des Spielers: alles noch einmal versuchen
    end
    local queue = Core.MailQueue
    if sending or not queue or queue.IsBusy() then return false end
    for _, s in ipairs(Ship.Outgoing()) do
        local to, mailable = Data.Recipient(s.to)
        local entries, planned = {}, {}
        if not stuck[s] then entries, planned = Ship.Entries(s.items) end
        if to and mailable and #entries > 0 then
            local before = {}
            for itemID in pairs(planned) do before[itemID] = BagCount(itemID) end
            local subject = Core.TruncateChars(L.SHIP_SUBJECT:format(s.note or L.SHIP_MATERIAL), 60)
            sending = s
            local started = queue.Add(to, subject, L.SHIP_BODY, entries, function(ok)
                sending = nil
                local sentAll = 0
                for itemID, n in pairs(planned) do
                    local sent = max(0, min(n, (before[itemID] or 0) - BagCount(itemID)))
                    local left = (s.items[itemID] or 0) - sent
                    s.items[itemID] = left > 0 and left or nil
                    sentAll = sentAll + sent
                end
                -- Die Warteschlange meldet ok auch, wenn kein Brief rausging (nur übersprungene Stapel): gemessen
                -- wird an der Tasche. Ging nichts raus, bleibt die Sendung für diesen Durchlauf liegen.
                -- Die Begründung „gebunden, gesperrt oder Postfach voll“ stimmt nur, wenn die Warteschlange zu Ende
                -- lief; brach sie ab, nennt ezCore den Grund schon („Nachsenden angehalten (…)“). Briefkasten zu:
                -- die Sendung ist nicht festgefahren und wird beim nächsten Besuch wieder versucht (Fund 6).
                if sentAll == 0 then
                    if ok then
                        stuck[s] = true
                        ns.Print(L.SHIP_NOT_SENT:format(Ship.Describe(s)))
                    elseif not MailboxOpen() then
                        ns.Print(L.SHIP_NOT_SENT_CLOSED:format(Ship.Describe(s)))
                    else
                        stuck[s] = true
                        ns.Print(L.SHIP_NOT_SENT_STOPPED:format(Ship.Describe(s)))
                    end
                end
                if IsEmpty(s.items) then Ship.Remove(s) else Changed() end
                if ok and sendAll then
                    C_Timer.After(1, function() Ship.SendNext() end)
                else
                    sendAll = false
                end
            end, ns)
            if not started then
                sending = nil
                return false
            end
            Changed()
            return true
        end
    end
    sendAll = false
    for _, s in ipairs(Ship.Outgoing()) do
        -- liegen gebliebene sind schon gemeldet (SHIP_NOT_SENT)
        if not stuck[s] then
            ns.Print(L.SHIP_NOTHING_IN_BAGS)
            break
        end
    end
    return false
end
