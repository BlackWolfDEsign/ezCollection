local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Charakterdaten aller Twinks – eine Quelle für alle Module (ezCoreDB.chars).
    Schlüssel: voller Name und normalisierter Realm (siehe Names.lua), z. B. „Testa Probe-Beispielrealm“.

    Felder je Charakter (wer sie schreibt):
      name, realm, realmName, class, faction, level, money,
      lastSeen, online, resting, guid                             ezCore (Characters.lua)
      guild (Schlüssel der Gilde, false ohne Gilde)               ezCore (Inventory.lua)
      bags, bank, equip, mail = { [itemID] = Anzahl },
      items = { bags, bank, mail, equip = { { i, l, c, q, b } } },
      bankSeen, mailSeen, bagFree, bagTotal                        ezCore (Inventory.lua)
      mailbox = { seen, count, unread, money, cod, expires,
                  list = { { e = Ablauf, d = wird gelöscht } }, more }   ezCore (Mail.lua; lesen über Mail.Expiring)
      xp, xpMax, rested, zone, subzone, hearth, played, playedLevel, playedAt     ezCore (Characters.lua)
      profs, profCD                                                ezCore (Professions.lua)
      lockouts, lockoutsAt                                         ezCore (Lockouts.lua)
      ilvl, ilvlAll, gear = { [platz] = { l, q, i } }, gearAt,
      currencies = { [id] = Anzahl }, lastFaction                  ezCore (CharData.lua)
      durability = { pct, low, broken, t }                         ezCore (Durability.lua)
      books = { [questID] = true }                                 ezCore (Collections.lua)
      playedLevelAt                                                ezPanel-Bausteine (alle anderen Felder schreibt ezCore)

    Bis ezCore gab es drei Kopien mit drei Schlüsseln (ezBag: Vorname-Realm, ezPanel: voller
    Name-Realm mit Leerzeichen, ezMail las ezBag). Sie werden einmalig zusammengeführt; die alten
    Tabellen bleiben unverändert als Sicherung liegen.
]]

local Chars = {}
Core.Characters = Chars

---------------------------------------------------------------------------
-- Zugriff
---------------------------------------------------------------------------

function Core.Chars()
    return (Core.db and Core.db.chars) or {}
end

function Core.Char(key)
    local c = Core.Chars()[key or Core.charKey]
    return type(c) == "table" and c or nil
end

-- Schlüssel für Name und Realm (Realm wird normalisiert: „Die Aldor“ → „DieAldor“).
function Core.CharKeyFor(name, realm)
    return tostring(name) .. "-" .. Core.NormalizeRealm(realm or Core.realm)
end

-- Datensatz zu Name und Realm; create = true legt ihn an. Rückgabe: Datensatz, neu angelegt?
function Core.CharRecord(name, realm, create)
    local chars = Core.Chars()
    local key = Core.CharKeyFor(name, realm)
    local c = chars[key]
    if c == nil and create and Core.db then
        c = {}
        chars[key] = c
        return c, true, key
    end
    return c, false, key
end

-- Daten eines Charakters; der gerade gespielte ist immer bekannt, sonst Name und Realm aus dem Schlüssel.
function Core.CharInfo(key)
    local data = Core.Char(key)
    if data and data.name then return data end
    if key == Core.charKey then
        return { name = Core.fullName or Core.firstName or UnitName("player"), realm = Core.realm,
            class = select(2, UnitClass("player")), faction = UnitFactionGroup("player") }
    end
    return { name = key:match("^(.-)%-") or key, realm = key:match("%-([^%-]+)$") }
end

-- Charaktere sortiert: aktueller zuerst, dann der eigene Realm, dann nach Realm und Name.
-- Liste von { key, c, isMe }; filter(c, key) wählt aus.
function Core.CharacterList(filter)
    local list = {}
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" and (not filter or filter(c, key)) then
            list[#list + 1] = { key = key, c = c, isMe = key == Core.charKey }
        end
    end
    local myRealm = Core.RealmKey(Core.realm)
    table.sort(list, function(a, b)
        if a.isMe ~= b.isMe then return a.isMe end
        local ra, rb = Core.RealmKey(a.c.realm), Core.RealmKey(b.c.realm)
        if ra ~= rb then
            if ra == myRealm then return true end
            if rb == myRealm then return false end
            return ra < rb
        end
        return a.key < b.key
    end)
    return list
end

-- Anzeigename: Name, bei anderem Realm mit Realm (Trenner sep, Standard " - "), in Klassenfarbe.
function Core.CharName(c, key, sep, plain)
    local name = c and c.name or (key and key:match("^(.-)%-")) or key or "?"
    if c and c.realm and Core.RealmKey(c.realm) ~= Core.RealmKey(Core.realm) then
        name = name .. (sep or " - ") .. (c.realmName or c.realm)
    end
    if plain then return name end
    return Core.ClassText(name, c and c.class)
end

-- Empfängername (z. B. aus SendMail) → Datensatz und Schlüssel eines eigenen Charakters.
-- Versteht „Name“, „Name-Realm“ und „Vorname Nachname“. Gesamtreview 18.11.2026, T4-NR2: Auf WoW Forever
-- (Core.uniqueNames) ist ein Name ohne Nachnamen ein eigener voller Name (Core.MissingSurname) – dort zählt nur der
-- ganze Name, kein Vornamen-Treffer (sonst hielte ezMail einen fremden „Testa“ für den Twink „Testa Probe“). Weil die
-- Namen dort regional eindeutig sind, findet ein Name ohne Realm-Zusatz auch Twinks anderer Realms (der eigene Realm
-- zuerst, sonst nur ein eindeutiger Treffer). Andere Clients: ein eindeutiger Vorname wie bisher, nur der eigene Realm.
function Core.FindChar(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    name = Core.Trim(name)
    if name == "" then return nil end
    local base, realm = name:match("^(.-)%-([^%-]+)$")
    local anyRealm = false
    if not base then base, realm, anyRealm = name, Core.realm, Core.uniqueNames == true end
    local realmKey, wanted = Core.RealmKey(realm), base:lower()
    local firstMatch, firstKey, firstCount = nil, nil, 0
    local farMatch, farKey, farCount = nil, nil, 0
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" then
            local cname = (c.name or key:match("^(.-)%-") or ""):lower()
            if Core.RealmKey(c.realm or key:match("%-([^%-]+)$")) == realmKey then
                if cname == wanted then return c, key end
                if not Core.uniqueNames and cname:match("^([^%s]+)") == wanted then
                    firstMatch, firstKey, firstCount = c, key, firstCount + 1
                end
            elseif anyRealm and cname == wanted then
                farMatch, farKey, farCount = c, key, farCount + 1
            end
        end
    end
    if firstCount == 1 then return firstMatch, firstKey end
    if farCount == 1 then return farMatch, farKey end
    return nil
end

-- Eingabe für „vergessen“ → Schlüssel. Der volle Schlüssel gewinnt immer; danach der Name (auch „Name“ vor dem
-- Realm), zuletzt der Vorname – beides nur, wenn genau ein Charakter passt (wie Core.FindChar).
-- Mehrdeutig: nil und die Liste der passenden Schlüssel (sortiert), damit der Aufrufer sie nennen kann.
function Core.FindCharKey(wanted)
    wanted = Core.Trim(wanted or ""):lower()
    if wanted == "" then return nil end
    local byName, byFirst = {}, {}
    for key, c in pairs(Core.Chars()) do
        local lower = key:lower()
        if lower == wanted then return key end
        local name = (type(c) == "table" and c.name or ""):lower()
        if name == wanted or lower:sub(1, #wanted + 1) == wanted .. "-" then
            byName[#byName + 1] = key
        elseif name:match("^([^%s]+)") == wanted then
            byFirst[#byFirst + 1] = key
        end
    end
    local list = #byName > 0 and byName or byFirst
    if #list == 1 then return list[1] end
    if #list == 0 then return nil end
    table.sort(list)
    return nil, list
end

-- Charakter aus allen Modulen entfernen. false für den gerade gespielten.
function Core.ForgetChar(key)
    if not key or key == Core.charKey then return false end
    local chars = Core.Chars()
    if chars[key] == nil then return false end
    chars[key] = nil
    local knowledge = Core.db and Core.db.knowledge
    if type(knowledge) == "table" and type(knowledge.charProfs) == "table" then knowledge.charProfs[key] = nil end
    -- Merker „Hinweis auf Umbenennung gegeben“ (T4-NR1) und „alte Ruf-Liste aus ezPanel“ (T4-1: done[key],
    -- done.eligible[key]) gehören zum vergessenen Satz; GUID und Gilde stehen in ihm selbst, g.by räumt Inventory ab
    local migrated = Core.db and Core.db.migrated
    if type(migrated) == "table" and type(migrated.renamedNoted) == "table" then migrated.renamedNoted[key] = nil end
    local factions = type(migrated) == "table" and migrated.ezPanelFactions or nil
    if type(factions) == "table" and key ~= "_at" and key ~= "eligible" then
        factions[key] = nil
        if type(factions.eligible) == "table" then factions.eligible[key] = nil end
    end
    Core.Fire("CHAR_FORGOTTEN", key)
    return true
end

---------------------------------------------------------------------------
-- Stufen, Spielzeit, Ruhe-XP (vorher ezPanel)
---------------------------------------------------------------------------

-- Höchststufe. Wer keine XP mehr bekommt (UnitXPMax = 0), ist ohnehin am Ziel.
function Core.MaxLevel()
    for _, fn in ipairs({ GetMaxPlayerLevel, GetMaxLevelForPlayerExpansion }) do
        if type(fn) == "function" then
            local ok, value = pcall(fn)
            if ok and Core.Num(value) and value > 0 then return value end
        end
    end
    return MAX_PLAYER_LEVEL or 60
end

-- Bis zu welcher Stufe bringt Erfahrung den Charakter? → stufe, probe? Die Höchststufe (Core.MaxLevel) oder, wenn ein
-- Probe-Konto Erfahrung sammelt (GameLimitedMode_IsBankedXPActive), dessen Stufengrenze (GameLimitedMode_GetLevelLimit),
-- falls sie darunter liegt – dort bleibt die Stufe stehen (Blizzards ExpBarMixin:IsCapped, Shared/ExpBar.lua der
-- Forever-Quelle). Für „nach Abgabe Stufe X“ (Core.LevelAfterXP) und Core.XPBlocked; Gegenprüfung I1, 18.11.2026.
function Core.XPLevelCap()
    local max = Core.MaxLevel()
    if Core.Bool(Core.Call(rawget(_G, "GameLimitedMode_IsBankedXPActive")), false) == true then
        local limit = Core.Num(Core.Call(rawget(_G, "GameLimitedMode_GetLevelLimit")))
        if limit and limit > 0 and limit < max then return limit, true end
    end
    return max, false
end

-- Bekommt der Charakter gerade keine Erfahrung? → true, Grund ("disabled": Erfahrung beim Lehrer ausgeschaltet,
-- IsXPUserDisabled; "capped": Stufengrenze eines Probe-Kontos wie Blizzards ExpBarMixin:IsCapped; "max": Höchststufe
-- bzw. UnitXPMax 0; "unknown": Stufe oder Erfahrung gesperrt oder unbekannt) oder false. Feature I1 des Gesamtreviews
-- vom 18.11.2026 (Vorschau auf der Erfahrungsleiste); dieselben Fälle wie ezPanels Baustein XP (AtMax).
function Core.XPBlocked()
    if Core.Bool(Core.Call(rawget(_G, "IsXPUserDisabled")), false) == true then return true, "disabled" end
    local level = Core.PlayerLevel()
    local cap, trial = Core.XPLevelCap()
    if trial and level and level >= cap then return true, "capped" end
    local max = Core.Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    if not level or max == nil then return true, "unknown" end
    if max <= 0 or level >= Core.MaxLevel() then return true, "max" end
    return false
end

--[[
    Stufe nach gain weiteren EP → stufe, anteil (0 bis unter 1), geschätzt?, höchststufe?  (nil bei fehlenden oder
    gesperrten Werten). level, xp, xpMax: jetzige Stufe und Erfahrung (UnitLevel, UnitXP, UnitXPMax); maxLevel frei,
    sonst Core.MaxLevel(). Der Client nennt die nötigen EP nur für die jetzige Stufe (UnitXPMax) – jede weitere Stufe
    rechnet mit derselben Zahl (Vermutung wie die Leveling-Route in ezQuest/LevelRoute.lua, Walk). Darum ist das Ergebnis
    „geschätzt“, sobald es eine Stufe weiter liegt (der Anteil in der neuen Stufe ist dann geschätzt). Auf der
    Höchststufe endet die Rechnung (Anteil 0, höchststufe = true).
]]
function Core.LevelAfterXP(gain, level, xp, xpMax, maxLevel)
    gain, level, xp, xpMax = Core.Num(gain), Core.Num(level), Core.Num(xp), Core.Num(xpMax)
    if not (gain and level and xp and xpMax) or gain < 0 or xpMax <= 0 then return nil end
    maxLevel = Core.Num(maxLevel) or Core.MaxLevel()
    if level >= maxLevel then return level, 0, false, true end
    local have, estimated = math.max(0, xp) + gain, false
    while have >= xpMax do
        have = have - xpMax
        level = level + 1
        estimated = true
        if level >= maxLevel then return maxLevel, 0, true, true end
    end
    return level, have / xpMax, estimated, false
end

-- Gespielte Zeit jetzt (gespeicherter Wert + Zeit seit der Abfrage).
function Core.PlayedNow(c)
    if not c or not c.played then return nil end
    if c == Core.me and c.playedAt then return c.played + (time() - c.playedAt) end
    return c.played
end

-- Gold aller Charaktere – eine Liste für ezBag und ezPanel: { { key, c, money } … } reichste zuerst, Summe.
-- filter.realm / filter.faction = true: nur dieser Realm / die eigene Fraktion; filter.hidden = { [key] = true };
-- filter.sort = "name". Der eigene Charakter steht immer drin (auch mit 0 Gold).
function Core.GoldList(filter)
    filter = filter or {}
    local list, total = {}, 0
    local myRealm = Core.RealmKey(Core.realm)
    local myFaction = Core.me and Core.me.faction
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" and not (filter.hidden and filter.hidden[key]) then
            local ok = not (filter.realm and Core.RealmKey(c.realm) ~= myRealm)
                and not (filter.faction and c.faction ~= myFaction)
            local money = Core.Num(c.money) or 0
            if ok and (money > 0 or key == Core.charKey) then
                list[#list + 1] = { key = key, c = c, money = money }
                total = total + money
            end
        end
    end
    table.sort(list, function(a, b)
        if filter.sort ~= "name" and a.money ~= b.money then return a.money > b.money end
        return a.key < b.key
    end)
    return list, total
end

-- Ruhe-XP, für ausgeloggte Charaktere hochgerechnet (Classic-Regeln: 5 % einer Stufe je 8 Stunden
-- im Gasthaus, ein Viertel davon draußen, höchstens 150 % einer Stufe).
function Core.EstimateRested(c)
    if not c or not c.xpMax or c.xpMax <= 0 then return nil end
    if c.level and c.level >= Core.MaxLevel() then return nil end
    local rested = c.rested or 0
    if c ~= Core.me and c.lastSeen then
        local hours = (time() - c.lastSeen) / 3600
        local perEight = c.xpMax * 0.05 * (c.resting and 1 or 0.25)
        rested = rested + hours / 8 * perEight
    end
    return math.min(rested, c.xpMax * 1.5)
end

---------------------------------------------------------------------------
-- Einmalige Übernahme aus den Modulen
---------------------------------------------------------------------------

-- Tiefe Kopie: Core.CopyTable (Kern/Util.lua; bis zum Gesamtreview vom 18.11.2026, T16-7, stand sie hier – ohne
-- Grenze, ein Zyklus lief über)
local function Copy(value) return Core.CopyTable(value) end

-- Fehlende Felder aus src übernehmen (vorhandene bleiben).
local function Merge(target, src, rename)
    for k, v in pairs(src) do
        local key = rename and rename[k] or k
        if target[key] == nil then target[key] = Copy(v) end
    end
    return target
end

local function FirstName(name)
    if type(name) ~= "string" then return nil end
    return (name:match("^([^%s]+)") or name):lower()
end

-- Ziel für einen Datensatz, der nur den Vornamen kennt (ezBag, ezMail): ein vorhandener Charakter
-- mit genau diesem Vornamen auf dem Realm, sonst der alte Schlüssel.
local function KeyForFirstName(chars, oldKey, first, realm)
    if oldKey == Core.oldCharKey then return Core.charKey end
    local wanted, realmKey = FirstName(first), Core.RealmKey(realm)
    local found, count = nil, 0
    for key, c in pairs(chars) do
        if key ~= oldKey and Core.RealmKey(c.realm) == realmKey and FirstName(c.name) == wanted then
            found, count = key, count + 1
        end
    end
    if count == 1 then return found end
    return oldKey
end

local function MigrateKnowledge(db, map)
    local bag = _G.ezBagDB
    if type(bag) ~= "table" or type(bag.knowledge) ~= "table" then return end
    local hasOwn = next(db.knowledge.recipes or {}) ~= nil
    if not hasOwn then
        local own = db.knowledge
        for k, v in pairs(bag.knowledge) do if own[k] == nil then own[k] = Copy(v) end end
    end
    local profs = db.knowledge.charProfs
    if type(profs) == "table" then
        for old, new in pairs(map) do
            if old ~= new and profs[old] and not profs[new] then
                profs[new], profs[old] = profs[old], nil
            end
        end
    end
end

function Chars.Migrate()
    local db = Core.db
    local chars, done, count = db.chars, db.migrated, 0
    local map = {}   -- alter ezBag-Schlüssel → neuer Schlüssel (für Item-Wissen und ezMail)

    -- ezPanel: voller Name, Realm mit Leerzeichen
    local panel = _G.ezPanelDB
    if not done.ezPanel and type(panel) == "table" and type(panel.chars) == "table" then
        for key, c in pairs(panel.chars) do
            if type(c) == "table" then
                local name = c.name or key:match("^(.-)%-")
                local realm = c.realm or key:match("%-(.+)$")
                local newKey = (name or key) .. "-" .. Core.NormalizeRealm(realm)
                if key == Core.oldCharKey or newKey:lower() == Core.charKey:lower() then newKey = Core.charKey end
                local target = chars[newKey] or {}
                chars[newKey] = target
                Merge(target, c, { mail = "mailbox" })   -- ezPanel: Briefkasten-Stand, ezBag: Anzahl je Gegenstand
                target.realmName = target.realmName or realm
                target.realm = Core.NormalizeRealm(target.realm or realm)
                count = count + 1
            end
        end
        done.ezPanel = true
    end

    -- ezBag: Vorname-Realm, Inhalte von Taschen, Bank, Post, angelegt; Gildenbanken; Item-Wissen
    local bag = _G.ezBagDB
    if not done.ezBag and type(bag) == "table" then
        for key, c in pairs(type(bag.chars) == "table" and bag.chars or {}) do
            if type(c) == "table" then
                local newKey = KeyForFirstName(chars, key, c.name or key:match("^(.-)%-"), c.realm or key:match("%-(.+)$"))
                map[key] = newKey
                local target = chars[newKey] or {}
                local existed = chars[newKey] ~= nil
                chars[newKey] = target
                Merge(target, c)
                if not existed then count = count + 1 end
            end
        end
        for key, g in pairs(type(bag.guilds) == "table" and bag.guilds or {}) do
            if db.guilds[key] == nil then db.guilds[key] = Copy(g) end
        end
        MigrateKnowledge(db, map)
        done.ezBag = true
        done.ezBagMap = map
    end

    -- ezMail: Ablaufzeiten der Post (Schlüssel wie ezBag)
    local mail = _G.ezMailDB
    if not done.ezMail and type(mail) == "table" then
        local bagMap = done.ezBagMap or map
        for key, e in pairs(type(mail.expiry) == "table" and mail.expiry or {}) do
            if type(e) == "table" then
                local newKey = bagMap[key] or KeyForFirstName(chars, key, key:match("^(.-)%-"), key:match("%-(.+)$"))
                local c = chars[newKey]
                if c then
                    c.mailbox = c.mailbox or {}
                    if c.mailbox.list == nil then
                        c.mailbox.list, c.mailbox.more = Copy(e.list), e.more
                        c.mailbox.seen = c.mailbox.seen or e.seen
                    end
                end
            end
        end
        done.ezMail = true
    end

    return count
end

-- Alte Schlüssel des gerade gespielten Charakters (nur Vorname) übernehmen.
local function AdoptOldKey(chars)
    local old = Core.oldCharKey
    if old and old ~= Core.charKey and type(chars[old]) == "table" then
        local target = chars[Core.charKey] or {}
        chars[Core.charKey] = target
        Merge(target, chars[old])
        chars[old] = nil
        local profs = Core.db.knowledge and Core.db.knowledge.charProfs
        if type(profs) == "table" and profs[old] then
            profs[Core.charKey] = profs[Core.charKey] or profs[old]
            profs[old] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Der aktuelle Charakter
---------------------------------------------------------------------------

local function UpdateMe()
    local me = Core.me
    if not me then return end
    me.name = Core.fullName or Core.firstName
    me.realm = Core.realm
    me.realmName = GetRealmName and GetRealmName() or me.realmName
    me.class = select(2, UnitClass("player"))
    me.faction = UnitFactionGroup("player")
    me.level = UnitLevel("player")
    me.money = GetMoney()
    -- feste Kennung für Core.CharRenamedTo (T4-NR1); nur ein lesbarer Wert wird gemerkt
    local guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player"))
    if type(guid) == "string" and guid ~= "" then me.guid = guid end
end

--[[
    Umbenannte Twinks (Gesamtreview 18.11.2026, T4-NR1): Eine Umbenennung legt beim nächsten Anmelden einen neuen
    Datensatz an; der alte behielte Gold und Bestände und zählte doppelt. Trägt ein anderer Satz dieselbe Spieler-GUID
    (me.guid, seit diesem Paket gemerkt) und wurde später gesehen, ist der alte „wahrscheinlich umbenannt“: die Zeile unter
    „Bekannte Charaktere“ sagt es (Knopf „Vergessen“ daneben), und beim Anmelden kommt einmal ein Hinweis. Verschoben oder
    gelöscht wird nichts von selbst – ob die GUID eine Umbenennung übersteht, prüft der Spieltest; nach einem Realm-Wechsel
    ändert sie sich (die Realm-Kennung ist Teil der GUID), dann bleibt nur „Vergessen“.
      Core.CharRenamedTo(key) → Schlüssel des neueren Satzes mit derselben GUID oder nil
]]
-- Nur der Vorname des anderen? Auf WoW Forever wird der Schlüssel zu „Vorname-Realm“ (Core.oldCharKey), wenn der
-- Nachname bei einer Anmeldung fehlt; das ist kein neuer Name (AdoptOldKey führt die Sätze beim nächsten Mal zusammen).
local function FirstNameOf(a, b)
    local nameA, realmA = tostring(a):match("^(.-)%-([^%-]+)$")
    local nameB, realmB = tostring(b):match("^(.-)%-([^%-]+)$")
    if not (nameA and nameB) or Core.RealmKey(realmA) ~= Core.RealmKey(realmB) then return false end
    local sep = Core.surnameSep or " "
    local function First(n)
        local i = n:find(sep, 1, true)
        return i and n:sub(1, i - 1):lower() or nil
    end
    return First(nameA) == nameB:lower() or First(nameB) == nameA:lower()
end

function Core.CharRenamedTo(key)
    local c = type(key) == "string" and Core.Char(key)
    if type(c) ~= "table" or type(c.guid) ~= "string" or c.guid == "" then return nil end
    local seen = Core.Num(c.lastSeen) or 0
    local best, bestSeen
    for other, o in pairs(Core.Chars()) do
        if other ~= key and type(o) == "table" and o.guid == c.guid and not FirstNameOf(key, other) then
            local t = other == Core.charKey and math.huge or (Core.Num(o.lastSeen) or 0)
            if t > seen and (not bestSeen or t > bestSeen) then best, bestSeen = other, t end
        end
    end
    return best
end

-- Einmal je altem Satz: Hinweis beim Anmelden, dass er wahrscheinlich umbenannt ist (Merker db.migrated.renamedNoted).
function Chars.NoteRenamed()
    local db = Core.db
    if type(db) ~= "table" then return 0 end
    db.migrated = type(db.migrated) == "table" and db.migrated or {}
    local noted = type(db.migrated.renamedNoted) == "table" and db.migrated.renamedNoted or {}
    db.migrated.renamedNoted = noted
    local n = 0
    for key in pairs(Core.Chars()) do
        if key ~= Core.charKey and not noted[key] and Core.CharRenamedTo(key) == Core.charKey then
            noted[key] = Core.charKey
            n = n + 1
            ns.Print(L.CHARS_RENAMED_NOTICE:format(key))
        end
    end
    return n
end

function Chars.Login()
    Core.InitIdentity()
    local db = Core.db
    local before = 0
    for _ in pairs(db.chars) do before = before + 1 end
    local ok, migrated = pcall(Chars.Migrate)
    if not ok then
        Core.Error(Core.name, migrated, "Migrate")
        migrated = 0
    end
    AdoptOldKey(db.chars)

    local me = db.chars[Core.charKey] or {}
    db.chars[Core.charKey] = me
    Core.me, ns.me = me, me
    Core.previousLastSeen = me.lastSeen   -- für ezPanels Sitzung (übersteht /reload)
    UpdateMe()
    me.lastSeen = time()
    me.online = true
    Chars.SaveProgress()

    if migrated > 1 and before == 0 then
        C_Timer.After(5, function() ns.Print(L.MIGRATED_CHARS:format(migrated)) end)
    end
    C_Timer.After(6, function() ns.Try("NoteRenamed", Chars.NoteRenamed) end)
    Core.Fire("CHARS_READY", me)
end

ns.On("PLAYER_MONEY", function()
    if Core.me then Core.me.money = GetMoney() end
end)

ns.On("PLAYER_LEVEL_UP", function(_, level)
    if Core.me then Core.me.level = Core.Num(level) or UnitLevel("player") end
end)

---------------------------------------------------------------------------
-- Erfahrung, Ruhe, Ort, Ruhestein, Spielzeit (vorher nur ezPanel; ohne ezPanel blieben
-- Core.EstimateRested und Core.PlayedNow leer)
---------------------------------------------------------------------------

local function SaveXP()
    local me = Core.me
    if not me then return end
    me.level = Core.Num(UnitLevel and UnitLevel("player")) or me.level
    me.xp = Core.Num(Core.Call(rawget(_G, "UnitXP"), "player")) or me.xp
    me.xpMax = Core.Num(Core.Call(rawget(_G, "UnitXPMax"), "player")) or me.xpMax
    me.rested = Core.Num(Core.Call(rawget(_G, "GetXPExhaustion"))) or 0
    me.resting = Core.Call(rawget(_G, "IsResting")) == true
end

local function SaveZone()
    local me = Core.me
    if not me then return end
    local zone = Core.Plain(Core.Call(rawget(_G, "GetRealZoneText"))) or Core.Plain(Core.Call(rawget(_G, "GetZoneText")))
    if type(zone) == "string" and zone ~= "" then me.zone = zone end
    me.subzone = Core.Plain(Core.Call(rawget(_G, "GetSubZoneText"))) or me.subzone
end

local function SaveHearth()
    local me = Core.me
    if not me then return end
    local hearth = Core.Plain(Core.Call(rawget(_G, "GetBindLocation")))
    if type(hearth) == "string" and hearth ~= "" then me.hearth = hearth end
end

function Chars.SaveProgress()
    SaveXP()
    SaveZone()
    SaveHearth()
end

for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" }) do ns.On(event, SaveXP) end
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do ns.On(event, SaveZone) end
ns.On("HEARTHSTONE_BOUND", SaveHearth)
ns.On("TIME_PLAYED_MSG", function(_, total, level)
    local me = Core.me
    total = Core.Num(total)
    if not (me and total) then return end
    me.played, me.playedLevel, me.playedAt = total, Core.Num(level), time()
end)

ns.On("PLAYER_LOGOUT", function()
    local me = Core.me
    if not me then return end
    me.lastSeen = time()
    me.resting = IsResting and IsResting() and true or false
    me.online = nil
    me.money = GetMoney()
end)

-- ezCore zuerst: alle Module finden beim Einloggen fertige Charakterdaten vor.
ns.On("PLAYER_LOGIN", Chars.Login)
