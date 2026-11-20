local _, ns = ...
local Core = ezCore

--[[
    Inventar (vorher ezBag/Inventory.lua): merkt sich pro Charakter, was in Taschen, Bank, Post und
    angelegt ist, dazu die Gildenbank. Bank, Post und Gildenbank kann das Spiel nur lesen, solange
    sie offen sind – deshalb werden sie beim Öffnen erfasst und bis zum nächsten Besuch gespeichert.
    Post an eigene Twinks zählt sofort mit (beim Empfänger, nach MAIL_SEND_SUCCESS).

    Nachrichten (ezCore.Listen):
      INVENTORY_CHANGED     Taschen (und offene Bank) neu erfasst
      BANK_OPENED, BANK_CLOSED
      GUILDBANK_CHANGED     Gildenbank erfasst
    Daten: Core.me.bags/bank/mail/equip, .items, .bankSeen, .mailSeen, .bagFree/.bagTotal (normale Taschen),
           .bagSpecialFree/.bagSpecialTotal (Berufstaschen, Köcher), .bagSeen – lesen über Core.BagSpaceOf(charKey);
           Core.db.guilds[„Gilde-Realm“] = { name, realm, faction, tabs, counts, seen }
]]

local Inventory = {}
Core.Inventory = Inventory

local bankOpen, guildOpen = false, false
local scanPending = false

Inventory.LOCATIONS = { "bags", "bank", "mail", "equip" }

local function Me() return Core.me end

---------------------------------------------------------------------------
-- Welche Behälter gehören wozu?
---------------------------------------------------------------------------

local carriedLists = {}

-- Alles, was der Charakter bei sich trägt: normale Taschen, Reagenzientasche, Schlüsselbund → Liste, Menge.
-- opts = { keyring = false } bzw. { reagent = false } lässt den Behälter weg (z. B. zum Verkaufen). Die Regel,
-- welche Liste wofür gilt, steht bei Core.BagList (Util.lua); Module nutzen Core.ForEachBagItem(fn, art).
function Inventory.CarriedBags(opts)
    local keyring = not (type(opts) == "table" and opts.keyring == false)
    local reagent = not (type(opts) == "table" and opts.reagent == false)
    local cacheKey = (keyring and "k" or "-") .. (reagent and "r" or "-")
    local cached = carriedLists[cacheKey]
    if cached then return cached.list, cached.set end
    local list, set = {}, {}
    local function add(id)
        if type(id) == "number" and not set[id] then
            set[id] = true
            list[#list + 1] = id
        end
    end
    for bag = 0, Core.NumBagSlots() do add(bag) end
    local E = (Enum and Enum.BagIndex) or {}
    if reagent then add(E.ReagentBag) end
    if keyring then add(E.Keyring) end
    carriedLists[cacheKey] = { list = list, set = set }
    return list, set
end

-- Gekaufte Bankfächer (Retail-Bank mit Fächern) bzw. alte Bank + Bankfächer.
function Inventory.BankBags()
    local _, carried = Inventory.CarriedBags()
    local seen, list = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] and not carried[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(ids) == "table" and #ids > 0 then
            for _, id in ipairs(ids) do add(id) end
            return list
        end
    end
    local E = (Enum and Enum.BagIndex) or {}
    for name, id in pairs(E) do
        if type(name) == "string" and (name == "Bank" or name == "Reagentbank"
            or name:match("^CharacterBankTab_%d+$") or name:match("^BankBag_%d+$")) then
            add(id)
        end
    end
    if not E.CharacterBankTab_1 and not E.BankBag_1 and NUM_BANKBAGSLOTS then
        local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or Core.NumBagSlots()) + 1
        for bag = first, first + NUM_BANKBAGSLOTS - 1 do add(bag) end
    end
    table.sort(list)
    return list
end

function Inventory.IsBankOpen() return bankOpen end
function Inventory.IsGuildBankOpen() return guildOpen end

-- Wie oft liegt ein Gegenstand bei einem Charakter? Rückgabe je Ort und gesamt.
function Inventory.Count(c, itemID)
    local parts, total = {}, 0
    for _, location in ipairs(Inventory.LOCATIONS) do
        local n = c[location] and c[location][itemID] or 0
        parts[location] = n
        total = total + n
    end
    return parts, total
end

-- Alle gemerkten Gildenbanken: { [gildenschlüssel] = { counts, … } } (lesen; vorher griffen Module direkt
-- auf ezCoreDB.guilds zu).
function Core.Guilds()
    local db = Core.db
    return type(db) == "table" and type(db.guilds) == "table" and db.guilds or {}
end

-- Bestand eines Gegenstands über alle Charaktere und Gildenbanken – eine Zählung für ezBag und ezCraft:
-- { chars = { { key, c, bags, bank, mail, equip, total, isMe } … } (nur mit Bestand, größte zuerst),
--   guilds = { { key, g, total, mine } … }, me = { bags, bank, mail, equip, total }, total }
-- Gildenbanken, in denen kein eigener Charakter mehr ist, fehlen (Inventory.ActiveGuilds, T4-NR3).
-- Zwischenspeicher (CRAFT-13, Rest von V-145): Der Rezept-Tooltip zählt je Zutat, der Tooltip je Gegenstand – das
-- Ergebnis gilt je itemID, bis sich Taschen, Bank, Post, Gildenbank oder der Charakter ändern (Nachrichten unten),
-- höchstens Inventory.COUNT_CACHE_TIME Sekunden. Das Ergebnis ist nur zum Lesen; Inventory.CountAllFresh zählt neu.
Inventory.COUNT_CACHE_TIME = 1
local countCache = {}

function Inventory.ForgetCounts()
    countCache = {}
end

function Inventory.CountAll(item)
    local itemID = Core.ItemID(item)
    if not itemID then return Inventory.CountAllFresh(item) end
    local now, guild = Core.Uptime(), Inventory.MyGuildKey()
    local hit = countCache[itemID]
    if hit and hit.guild == guild and now >= hit.t and now - hit.t < Inventory.COUNT_CACHE_TIME then return hit.out end
    local out = Inventory.CountAllFresh(itemID)
    countCache[itemID] = { t = now, guild = guild, out = out }
    return out
end

function Inventory.CountAllFresh(item)
    local itemID = Core.ItemID(item)
    local out = { chars = {}, guilds = {}, total = 0, me = { bags = 0, bank = 0, mail = 0, equip = 0, total = 0 } }
    if not itemID then return out end
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" then
            local parts, total = Inventory.Count(c, itemID)
            parts.total = total
            if key == Core.charKey then out.me = parts end
            if total > 0 then
                parts.key, parts.c, parts.isMe = key, c, key == Core.charKey
                out.chars[#out.chars + 1] = parts
                out.total = out.total + total
            end
        end
    end
    local mine, active = Inventory.MyGuildKey(), Inventory.ActiveGuilds()
    for key, g in pairs(Core.Guilds()) do
        local n = type(g) == "table" and type(g.counts) == "table" and Core.Num(g.counts[itemID]) or 0
        if n > 0 and (active[key] or key == mine) then   -- veraltete Gildenbanken zählen nicht mehr (T4-NR3)
            out.guilds[#out.guilds + 1] = { key = key, g = g, total = n, mine = key == mine }
            out.total = out.total + n
        end
    end
    local function ByTotal(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.key < b.key
    end
    table.sort(out.chars, ByTotal)
    table.sort(out.guilds, ByTotal)
    return out
end

-- Alles, was irgendein Charakter oder eine gemerkte Gildenbank besitzt: { [itemID] = true } – eine Rechnung für
-- viele Fragen auf einmal (Prices: „beobachtet?“ für tausende Gegenstände des Komplett-Scans). Je Aufruf neu.
function Inventory.OwnedSet()
    local set = {}
    for _, c in pairs(Core.Chars()) do
        if type(c) == "table" then
            for _, location in ipairs(Inventory.LOCATIONS) do
                for itemID, n in pairs(type(c[location]) == "table" and c[location] or {}) do
                    if (Core.Num(n) or 0) > 0 then set[itemID] = true end
                end
            end
        end
    end
    local active, mine = Inventory.ActiveGuilds(), Inventory.MyGuildKey()
    for key, g in pairs(Core.Guilds()) do
        if active[key] or key == mine then
            for itemID, n in pairs(type(g) == "table" and type(g.counts) == "table" and g.counts or {}) do
                if (Core.Num(n) or 0) > 0 then set[itemID] = true end
            end
        end
    end
    return set
end

-- Erreichbarer Bestand (Gesamtreview 18.11.2026, T4-NR5) – die eine Regel für ezCraft („vorhanden“) und ezAuction
-- („genug da“, Warnung vor Doppelkauf): Taschen, Bank und Post des gespielten Charakters, dieselben Orte bei Twinks, die
-- Post von ihm bekommen können (Core.AltRecipient: gleiche Fraktion, dazu ein sicher erreichbarer Realm,
-- Core.MailRealmConfirmed – auf Forever bis zum Spieltest der eigene und die verbundenen), und die Gildenbank der eigenen
-- Gilde. Angelegtes zählt nicht, Twinks der anderen Fraktion bzw. unerreichbarer Realms stehen getrennt (altsOther).
-- Aus Inventory.CountAll (Zwischenspeicher dort) bzw. aus dessen schon geholter Antwort all (eine Zählung je Frage).
-- → { bags, bank, mail, guild, alts, altsOther, total (alles
-- Erreichbare), altList = { { key, c, bags, bank, mail, total, mailable } … } (erreichbare zuerst, dann nach Menge) }
function Inventory.Reachable(item, all)
    local out = { bags = 0, bank = 0, mail = 0, guild = 0, alts = 0, altsOther = 0, total = 0, altList = {} }
    if type(all) ~= "table" then all = Inventory.CountAll(item) end
    if type(all) ~= "table" then return out end
    local me = type(all.me) == "table" and all.me or nil
    if not me then
        for _, entry in ipairs(all.chars or {}) do
            if type(entry) == "table" and entry.isMe then me = entry break end
        end
    end
    me = me or {}
    out.bags, out.bank, out.mail = Core.Num(me.bags) or 0, Core.Num(me.bank) or 0, Core.Num(me.mail) or 0
    for _, g in ipairs(all.guilds or {}) do
        if g.mine then out.guild = Core.Num(g.total) or 0 end
    end
    for _, entry in ipairs(all.chars or {}) do
        if not entry.isMe then
            local bags, bank, mail = Core.Num(entry.bags) or 0, Core.Num(entry.bank) or 0, Core.Num(entry.mail) or 0
            local total = bags + bank + mail
            if total > 0 then
                local _, mailable = Core.AltRecipient(entry.key)
                -- nur sicher zustellbare Realms (Core.MailRealmConfirmed): auf Forever ohne Spieltest nicht jeder Realm
                -- (Realm wie in Core.AltRecipient: aus dem gespeicherten Satz, sonst aus dem Schlüssel)
                local c = Core.Char(entry.key)
                local realm = type(c) == "table" and c.realm or (type(entry.key) == "string" and entry.key:match("%-([^%-]+)$"))
                mailable = mailable == true and Core.MailRealmConfirmed(realm) == true
                out.altList[#out.altList + 1] = { key = entry.key, c = entry.c, bags = bags, bank = bank, mail = mail,
                    total = total, mailable = mailable }
                if mailable then out.alts = out.alts + total else out.altsOther = out.altsOther + total end
            end
        end
    end
    table.sort(out.altList, function(a, b)
        if a.mailable ~= b.mailable then return a.mailable end
        if a.total ~= b.total then return a.total > b.total end
        return a.key < b.key
    end)
    out.total = out.bags + out.bank + out.mail + out.guild + out.alts
    return out
end

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

local function ScanContainers(bags)
    local counts, list, slots = {}, {}, 0
    for _, bag in ipairs(bags) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        slots = slots + n
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not Core.IsSecret(id) then
                local count = info.stackCount or 1
                counts[id] = (counts[id] or 0) + count
                list[#list + 1] = { i = id, l = info.hyperlink, c = count, q = info.quality, b = info.isBound == true }
            end
        end
    end
    return counts, list, slots
end

-- Stand der Taschenplätze brauchbar? Jeder Charakter hat einen Rucksack: „0 von 0“ (oder mehr frei als vorhanden)
-- ist kein Stand, sondern ein Lesen, bevor bzw. nachdem der Client die Taschen kannte.
local function SpaceValid(free, total)
    free, total = Core.Num(free), Core.Num(total)
    return free ~= nil and total ~= nil and total > 0 and free >= 0 and free <= total
end

-- Taschen des gespielten Charakters erfassen. Geschrieben wird nur, was wirklich lesbar war (FP-07; Spieltest:
-- beim Twink stand „0 / 0 frei“, obwohl seine Gegenstände bekannt waren): Kennt der Client die Taschen gerade nicht
-- (früh beim Laden, beim Abmelden – 0 Plätze), bleiben der gemerkte Inhalt und die gemerkten Plätze stehen.
-- → true, wenn die Taschen lesbar waren.
local function ScanBags()
    local me = Me()
    if not me then return false end
    me.items = me.items or {}
    local counts, list, slots = ScanContainers((Inventory.CarriedBags()))
    local readable = slots > 0
    if readable then me.bags, me.items.bags = counts, list end
    me.money = GetMoney()
    me.level = UnitLevel("player")
    local free, total, specialFree, specialTotal = Core.BagSpace()
    if SpaceValid(free, total) then
        me.bagFree, me.bagTotal = free, total
        -- Spezialtaschen getrennt; ohne solche Tasche bleiben die Felder leer
        if SpaceValid(specialFree, specialTotal) then
            me.bagSpecialFree, me.bagSpecialTotal = specialFree, specialTotal
        else
            me.bagSpecialFree, me.bagSpecialTotal = nil, nil
        end
        me.bagSeen = time()
    end
    return readable
end
Inventory.ScanBags = ScanBags

-- Taschenplätze eines Charakters: frei, gesamt, spezial ({ free, total } der Berufstaschen und Köcher oder nil),
-- gesehen (Zeit des Erfassens oder nil). Ohne Schlüssel oder für den gespielten Charakter der Stand von jetzt,
-- sonst der beim letzten Einloggen gemerkte. nil = unbekannt (nie erfasst oder nur ein unbrauchbarer Stand „0 von 0“
-- aus einer älteren Fassung) – die Anzeige schreibt dann „noch nicht erfasst“ statt „0 / 0“.
function Core.BagSpaceOf(charKey)
    if Core.IsSecret(charKey) then return nil end
    if charKey == nil or charKey == Core.charKey then
        local free, total, specialFree, specialTotal = Core.BagSpace()
        if SpaceValid(free, total) then
            return free, total, SpaceValid(specialFree, specialTotal) and { free = specialFree, total = specialTotal } or nil, time()
        end
        charKey = Core.charKey
    end
    local c = type(charKey) == "string" and Core.Char and Core.Char(charKey) or nil
    if type(c) ~= "table" or not SpaceValid(c.bagFree, c.bagTotal) then return nil end
    local special
    if SpaceValid(c.bagSpecialFree, c.bagSpecialTotal) then special = { free = c.bagSpecialFree, total = c.bagSpecialTotal } end
    return c.bagFree, c.bagTotal, special, Core.Num(c.bagSeen)
end

local function ScanEquipped()
    local me = Me()
    if not me then return end
    local counts, list = {}, {}
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        local id = GetInventoryItemID("player", slot)
        if id and not Core.IsSecret(id) then
            counts[id] = (counts[id] or 0) + 1
            list[#list + 1] = { i = id, l = GetInventoryItemLink("player", slot), c = 1,
                q = GetInventoryItemQuality("player", slot), b = true }
        end
    end
    me.items = me.items or {}
    me.equip, me.items.equip = counts, list
end
Inventory.ScanEquipped = ScanEquipped

local function ScanBank()
    local me = Me()
    if not me or not bankOpen then return end
    local counts, list, slots = ScanContainers(Inventory.BankBags())
    -- 0 Plätze heißt: Bankdaten (noch) nicht geladen – alte Werte behalten.
    if slots > 0 then
        me.items = me.items or {}
        me.bank, me.items.bank = counts, list
        me.bankSeen = time()
    end
end

local function ScheduleScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = false
        ScanBags()
        if bankOpen then ScanBank() end
        Core.Fire("INVENTORY_CHANGED")
    end)
end

local function SetBankOpen(open)
    if open then
        bankOpen = true
        C_Timer.After(0.3, function()
            ScanBank()
            Core.Fire("BANK_OPENED")
        end)
    else
        ScanBank()          -- letzter Stand, solange die Daten noch da sind
        bankOpen = false
        Core.Fire("BANK_CLOSED")
    end
end

---------------------------------------------------------------------------
-- Post an eigene Charaktere mitzählen
---------------------------------------------------------------------------

local outgoing

local function CaptureOutgoing(recipient, subject)
    if not GetSendMailItem then return end
    outgoing = { to = recipient, subject = subject, items = {},
        money = GetSendMailMoney and Core.Num(GetSendMailMoney()) or 0, cod = GetSendMailCOD and Core.Num(GetSendMailCOD()) or 0 }
    for attachment = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID, _, count, quality = GetSendMailItem(attachment)
        if itemID then
            outgoing.items[#outgoing.items + 1] = {
                i = itemID, l = GetSendMailItemLink and GetSendMailItemLink(attachment), c = count or 1, q = quality,
            }
        end
    end
end

local function DeliverOutgoing()
    local mail = outgoing
    outgoing = nil
    if not mail then return end
    Core.Fire("MAIL_SENT", mail)   -- Verlauf (History.lua): to, subject, money, cod, items = { { i, l, c, q } … }
    if #mail.items == 0 then return end
    local target = Core.FindChar(mail.to)
    if not target or target == Me() then return end
    target.mail = target.mail or {}
    target.items = target.items or {}
    target.items.mail = target.items.mail or {}
    for _, e in ipairs(mail.items) do
        target.mail[e.i] = (target.mail[e.i] or 0) + e.c
        table.insert(target.items.mail, e)
    end
end

---------------------------------------------------------------------------
-- Gildenbank
---------------------------------------------------------------------------

local queried = {}

--[[
    Schlüssel und Mitgliedschaft der Gildenbanken (Gesamtreview 18.11.2026, T4-NR3 und T4-NR4):
      Core.GuildKey(name, realm)  → „Gilde-Realm“ mit dem Realm der GILDE (GetGuildInfo, 4. Wert; leer = eigener Realm),
                                    damit Twinks auf verbundenen Realms dieselbe Gildenbank teilen. Die eine Regel für
                                    Inventory.MyGuildKey und den Datensatz (bis dahin galt der Realm des Charakters).
      Inventory.MyGuild()         → Name, Realm der Gilde (normalisiert) oder nil ohne Gilde
      c.guild                     je Charakter: Schlüssel seiner Gilde, false ohne Gilde, nil = noch nicht bekannt
                                  (beim Anmelden und bei PLAYER_GUILD_UPDATE gesetzt; Inventory.UpdateGuild)
      Inventory.GuildActive(key)  → false, wenn kein eigener Charakter mehr in dieser Gilde ist (veraltet – zählt nicht
                                    mehr mit); true sonst
      Inventory.GuildState(key)   → "member" | "maybe", schlüssel | "stale": "maybe" hält ein Twink, dessen Gilde noch
                                    unbekannt ist (seit dem Paket nicht angemeldet) – nur, wenn er die Bank selbst
                                    erfasst hat (g.by) oder nach ihrem letzten Erfassen (g.seen) noch angemeldet war
      Core.ForgetGuild(key)       eine gemerkte Gildenbank entfernen (Knopf „Vergessen“ unter „Gemerkte Gildenbanken“)
    Alte Sätze unter „Gilde-<Realm des Charakters>“ übernimmt der erste Login eines Mitglieds einmal unter den neuen
    Schlüssel (der neuere Stand gewinnt; Merker db.migrated.guildKeys[alt] = neu – je altem Schlüssel nur einmal). Nicht
    übernommen wird ein Satz, den ein eigener Charakter als seine Gilde meldet, der schon den Realm der Gilde trägt oder
    der von der anderen Fraktion stammt. Ein vergessener Twink (CHAR_FORGOTTEN) nimmt seine Mitgliedschaft mit, weil sie
    in seinem Datensatz steht, und sein Schlüssel verschwindet aus g.by.
]]
function Core.GuildKey(name, realm)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if Core.IsSecret(realm) or type(realm) ~= "string" or Core.NormalizeRealm(realm) == "" then realm = Core.realm end
    realm = Core.NormalizeRealm(realm or "?")
    if realm == "" then realm = "?" end
    return name .. "-" .. realm, realm
end

function Inventory.MyGuild()
    if not (IsInGuild and Core.Call(IsInGuild) == true) then return nil end
    local name, _, _, realm = Core.Call(rawget(_G, "GetGuildInfo"), "player")
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local _, guildRealm = Core.GuildKey(name, realm)
    return name, guildRealm
end

-- Schlüssel der eigenen Gilde (nil ohne Gilde).
function Inventory.MyGuildKey()
    local name, realm = Inventory.MyGuild()
    return name and Core.GuildKey(name, realm) or nil
end

-- Alten Satz „Gilde-<Realm des Charakters>“ einmal unter den Schlüssel mit dem Realm der Gilde legen (T4-NR4). Eine
-- Gilde auf dem eigenen Realm hat schon den richtigen Schlüssel; ihr Satz bekommt hier den Realm der Gilde, damit ihn
-- kein Twink auf einem verbundenen Realm für den alten Satz seiner gleichnamigen Gilde hält (Gegenprüfung).
local function AdoptGuildKey(name, key)
    local db = Core.db
    if type(db) ~= "table" or type(db.guilds) ~= "table" then return end
    local legacy = name .. "-" .. (Core.realm or "?")
    if legacy == key then
        local own = db.guilds[key]
        if type(own) == "table" and own.guildRealm == nil then own.guildRealm = key:match("%-([^%-]+)$") end
        return
    end
    local old = db.guilds[legacy]
    if type(old) ~= "table" or old.guildRealm ~= nil then return end   -- kein alter Satz bzw. schon ein neuer
    local done = type(db.migrated) == "table" and type(db.migrated.guildKeys) == "table" and db.migrated.guildKeys or nil
    if done and done[legacy] ~= nil then return end                      -- einmal je altem Schlüssel
    -- Gehört der Satz einer anderen Gilde gleichen Namens? Ein eigener Charakter meldet ihn als seine Gilde, oder er
    -- stammt von der anderen Fraktion – dann bleibt er unangetastet.
    for charKey, c in pairs(Core.Chars()) do
        if charKey ~= Core.charKey and type(c) == "table" and c.guild == legacy then return end
    end
    local myFaction = UnitFactionGroup and Core.Plain((UnitFactionGroup("player")))
    if type(old.faction) == "string" and type(myFaction) == "string" and myFaction ~= "" and old.faction ~= myFaction then
        return
    end
    db.migrated = type(db.migrated) == "table" and db.migrated or {}
    db.migrated.guildKeys = type(db.migrated.guildKeys) == "table" and db.migrated.guildKeys or {}
    local current = db.guilds[key]
    if type(current) ~= "table" or (Core.Num(old.seen) or 0) > (Core.Num(current.seen) or 0) then
        db.guilds[key] = old
        old.realm, old.guildRealm = key:match("%-([^%-]+)$"), key:match("%-([^%-]+)$")
    end
    db.guilds[legacy] = nil
    db.migrated.guildKeys[legacy] = key
end

local function GuildRecord()
    local name, realm = Inventory.MyGuild()
    if not name then return nil end
    local key = Core.GuildKey(name, realm)
    AdoptGuildKey(name, key)
    local g = Core.db.guilds[key]
    if not g then
        g = { name = name, realm = realm, guildRealm = realm, faction = UnitFactionGroup("player"), tabs = {}, counts = {},
            by = Core.charKey }
        Core.db.guilds[key] = g
    end
    return g, key
end
Inventory.GuildRecord = GuildRecord

-- Gilde des gespielten Charakters merken (c.guild) und alte Schlüssel übernehmen. Ohne Gilde false; ist der Charakter in
-- einer Gilde, deren Name der Client noch nicht nennt, bleibt der gemerkte Stand. → Schlüssel oder false/nil
function Inventory.UpdateGuild()
    local me = Me()
    if not me or not IsInGuild then return nil end
    local inGuild = Core.Call(IsInGuild)
    if inGuild == false then
        if me.guild ~= false then
            me.guild = false
            Inventory.ForgetCounts()
            Core.Fire("GUILDBANK_CHANGED")   -- welche Gildenbanken zählen, hat sich geändert (Anzeigen, Zeilen der Seite)
        end
        return false
    end
    local name, realm = Inventory.MyGuild()
    if not name then return me.guild end
    local key = Core.GuildKey(name, realm)
    AdoptGuildKey(name, key)
    if me.guild ~= key then
        me.guild = key
        Inventory.ForgetCounts()
        Core.Fire("GUILDBANK_CHANGED")
    end
    return key
end

-- Wie lange vor dem letzten Erfassen einer Gildenbank ein Twink mit unbekannter Gilde angemeldet gewesen sein darf, um
-- sie noch zu halten (lastSeen steht beim Anmelden und Abmelden; ohne sauberes Abmelden nur der Anmeldezeitpunkt).
Inventory.GUILD_UNKNOWN_GRACE = 12 * 3600

-- Welche gemerkten Gildenbanken gehören noch einem eigenen Charakter? → { [schlüssel] = true }, { [schlüssel] = Twink,
-- der sie nur vielleicht hält }; eine Rechnung je Zählung. Aktiv ist ein Satz, den ein Charakter mit c.guild ==
-- schlüssel meldet. Ein Twink mit noch unbekannter Gilde (c.guild == nil: seit dem Paket nicht angemeldet) hält ihn nur,
-- wenn er ihn selbst zuletzt erfasst hat (g.by) oder – auf demselben Realm (der Gilde bzw. bei alten Sätzen des
-- Charakters, der sie erfasst hat) – nach ihrem letzten Erfassen (g.seen) noch angemeldet war. Lange nicht gespielte
-- Twinks halten so keine Gildenbank, die ein anderer Charakter später gesehen hat (Gegenprüfung zu T4-NR3). Der
-- gespielte Charakter zählt hier nicht: für ihn gilt die Gilde aus dem Client (Inventory.MyGuildKey bei den Aufrufern).
function Inventory.ActiveGuilds()
    local claimed, unknown = {}, {}
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" then
            if type(c.guild) == "string" then
                claimed[c.guild] = true
            elseif c.guild == nil and key ~= Core.charKey then
                local realm = c.realm or (type(key) == "string" and key:match("%-([^%-]+)$"))
                unknown[#unknown + 1] = { key = key, seen = Core.Num(c.lastSeen) or 0,
                    realm = type(realm) == "string" and realm ~= "" and Core.RealmKey(realm) or nil,
                    faction = type(c.faction) == "string" and c.faction ~= "" and c.faction or nil }
            end
        end
    end
    table.sort(unknown, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return tostring(a.key) < tostring(b.key)
    end)
    local active, maybe = {}, {}
    for key, g in pairs(Core.Guilds()) do
        if claimed[key] then
            active[key] = true
        else
            local rec = type(g) == "table" and g or {}
            local realm = rec.realm or rec.guildRealm or (type(key) == "string" and key:match("%-([^%-]+)$"))
            realm = type(realm) == "string" and realm ~= "" and Core.RealmKey(realm) or nil
            local seen = Core.Num(rec.seen) or 0
            local faction = type(rec.faction) == "string" and rec.faction ~= "" and rec.faction or nil
            for _, u in ipairs(unknown) do
                local sameRealm = u.realm == nil or realm == nil or u.realm == realm
                -- Twinks der anderen Fraktion halten keine fremde Gildenbank (beide Fraktionen bekannt und verschieden).
                local sameFaction = u.faction == nil or faction == nil or u.faction == faction
                if u.key == rec.by or (sameRealm and sameFaction and u.seen + Inventory.GUILD_UNKNOWN_GRACE >= seen) then
                    active[key], maybe[key] = true, u.key
                    break
                end
            end
        end
    end
    return active, maybe
end

function Inventory.GuildActive(key)
    return Inventory.ActiveGuilds()[key] == true
end

-- Lage einer gemerkten Gildenbank → "member" (ein eigener Charakter ist Mitglied), "maybe", schlüssel (ein Twink mit
-- noch unbekannter Gilde hält sie; zählt mit, bis er sich anmeldet) oder "stale" (veraltet, zählt nicht mit). Die eigene
-- Gilde laut Client ist immer "member".
function Inventory.GuildState(key)
    if key ~= nil and key == Inventory.MyGuildKey() then return "member" end
    local active, maybe = Inventory.ActiveGuilds()
    if not active[key] then return "stale" end
    if maybe[key] then return "maybe", maybe[key] end
    return "member"
end

-- Gemerkte Gildenbank entfernen → true, wenn es sie gab. Die Anzeigen zählen danach neu (GUILDBANK_CHANGED).
function Core.ForgetGuild(key)
    local guilds = Core.Guilds()
    if type(key) ~= "string" or guilds[key] == nil then return false end
    guilds[key] = nil
    Inventory.ForgetCounts()
    Core.Fire("GUILDBANK_CHANGED")
    return true
end

local function ScanGuildTabs()
    if not GetGuildBankItemInfo then return end
    local g = GuildRecord()
    if not g then return end
    g.by = Core.charKey   -- wer sie zuletzt erfasst hat (Inventory.ActiveGuilds)
    local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    if current then queried[current] = true end
    for tab in pairs(queried) do
        local tabName, icon, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            local list = {}
            for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
                local texture, count, _, _, quality = GetGuildBankItemInfo(tab, slot)
                if texture then
                    local link = GetGuildBankItemLink(tab, slot)
                    local itemID = link and Core.ItemInstant(link) or nil
                    list[#list + 1] = { i = itemID, l = link, c = count or 1, q = quality }
                end
            end
            g.tabs[tab] = { name = tabName, icon = icon, items = list }
        end
    end
    local counts = {}
    for _, t in pairs(g.tabs) do
        for _, e in ipairs(t.items) do
            if e.i then counts[e.i] = (counts[e.i] or 0) + (e.c or 1) end
        end
    end
    g.counts = counts
    g.seen = time()
    Core.Fire("GUILDBANK_CHANGED")
end

local function OnGuildBankOpened()
    guildOpen = true
    -- Wer die Gildenbank öffnet, ist Mitglied: Gilde gleich merken (falls IsInGuild beim Anmelden kurz false lieferte).
    Inventory.UpdateGuild()
    wipe(queried)
    if not (GetNumGuildBankTabs and QueryGuildBankTab) then return end
    -- Alle Fächer nacheinander anfragen (der Server drosselt zu schnelle Anfragen).
    for tab = 1, GetNumGuildBankTabs() do
        C_Timer.After(0.6 * tab, function()
            if not guildOpen then return end
            local _, _, viewable = GetGuildBankTabInfo(tab)
            if viewable then
                queried[tab] = true
                QueryGuildBankTab(tab)
            end
        end)
    end
end

local function OnGuildBankClosed()
    guildOpen = false
end

---------------------------------------------------------------------------
-- Start und Ereignisse
---------------------------------------------------------------------------

Core.Listen("CHARS_READY", function(me)
    me.bags, me.bank, me.equip, me.mail = me.bags or {}, me.bank or {}, me.equip or {}, me.mail or {}
    me.items = me.items or {}
    C_Timer.After(2, function()
        ScanBags()
        ScanEquipped()
        Inventory.UpdateGuild()   -- Gilde des Charakters (T4-NR3); der Client kennt sie erst kurz nach dem Anmelden
        Core.Fire("INVENTORY_CHANGED")
    end)
    if type(SendMail) == "function" then hooksecurefunc("SendMail", CaptureOutgoing) end
end)

ns.On("BAG_UPDATE_DELAYED", ScheduleScan)
for _, message in ipairs({ "INVENTORY_CHANGED", "GUILDBANK_CHANGED", "MAILBOX_SCANNED", "MAIL_SENT", "CHAR_FORGOTTEN",
    "CHARS_READY", "BANK_OPENED", "BANK_CLOSED" }) do
    Core.Listen(message, Inventory.ForgetCounts, "ezCore.CountAll")
end
ns.On("BAG_CONTAINER_UPDATE", ScheduleScan)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() C_Timer.After(0.2, ScanEquipped) end)
ns.On("PLAYERBANKSLOTS_CHANGED", ScheduleScan)
ns.On("BANKFRAME_OPENED", function() SetBankOpen(true) end)
ns.On("BANKFRAME_CLOSED", function() if bankOpen then SetBankOpen(false) end end)
ns.On("MAIL_SEND_SUCCESS", DeliverOutgoing)
ns.On("MAIL_FAILED", function() outgoing = nil end)
ns.On("GUILDBANKFRAME_OPENED", OnGuildBankOpened)
ns.On("GUILDBANKFRAME_CLOSED", OnGuildBankClosed)
ns.On("PLAYER_GUILD_UPDATE", function() Inventory.UpdateGuild() end)
-- Ein vergessener Twink verschwindet auch aus „zuletzt erfasst von“ der Gildenbanken (P4: was beim Vergessen geht,
-- trifft auch die neuen Schlüssel).
Core.Listen("CHAR_FORGOTTEN", function(key)
    for _, g in pairs(Core.Guilds()) do
        if type(g) == "table" and g.by ~= nil and g.by == key then g.by = nil end
    end
end, "ezCore.GuildBy")
ns.On("GUILDBANKBAGSLOTS_CHANGED", function() if guildOpen then ScanGuildTabs() end end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
    local T = Enum and Enum.PlayerInteractionType
    if not T then return end
    if kind == T.Banker and not bankOpen then SetBankOpen(true) end
    if kind == T.GuildBanker and not guildOpen then OnGuildBankOpened() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
    local T = Enum and Enum.PlayerInteractionType
    if not T then return end
    if kind == T.Banker and bankOpen then SetBankOpen(false) end
    if kind == T.GuildBanker and guildOpen then OnGuildBankClosed() end
end)
ns.On("PLAYER_LOGOUT", function()
    ScanBags()
    ScanEquipped()
end)
