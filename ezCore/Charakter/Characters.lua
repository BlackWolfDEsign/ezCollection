local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Charakterdaten aller Twinks – eine Quelle für alle Module (ezCoreDB.chars).
    Schlüssel: voller Name und normalisierter Realm (siehe Names.lua), z. B. „Testa Probe-Beispielrealm“.

    Felder je Charakter (wer sie schreibt):
      name, realm, realmName, class, faction, level, money,
      moneyAt (Zeit des letzten verlässlichen Gold-Stands),
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
      petSpells = { [Linie] = { [Zauber] = Rang } }                ezCore (PetSpells.lua; lesen über PetSpells.List)
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
        name = name .. (sep or " - ") .. Core.RealmLabel(c.realm, c.realmName)
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
-- filter.sort = "name". Der eigene Charakter steht immer drin (auch mit 0 Gold), mit dem Gold, das der Client gerade
-- nennt (ist es 0, der gespeicherte Stand – früh beim Laden kennt der Client das Gold noch nicht).
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
            if key == Core.charKey then
                local live = Core.Num(Core.Call(rawget(_G, "GetMoney")))
                if live and live > 0 then money = live end
            end
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

local MoveCharRefs   -- was außerhalb des Satzes an seinem Schlüssel hängt (unten)

-- Alte Schlüssel des gerade gespielten Charakters (nur Vorname) übernehmen.
function Chars.AdoptOldKey(chars)
    local old = Core.oldCharKey
    if old and old ~= Core.charKey and type(chars[old]) == "table" then
        -- Trägt der alte Satz die GUID eines anderen Charakters (gleicher Vorname, kein Nachname), bleibt er seiner
        local guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player"))
        if type(guid) == "string" and type(chars[old].guid) == "string" and chars[old].guid ~= guid then return end
        local target = chars[Core.charKey] or {}
        chars[Core.charKey] = target
        Merge(target, chars[old])
        chars[old] = nil
        MoveCharRefs(old, Core.charKey, false)
    end
end

---------------------------------------------------------------------------
-- Sätze ohne echten Realm übernehmen (Spielbefund vom 22.11.2026)
---------------------------------------------------------------------------

--[[
    Solange der Client keinen Realmnamen lieferte, war Core.realm "" und neue Sätze hießen „Name-“, ältere
    „Name-<Realm>“: derselbe Charakter stand doppelt, und „dieser Realm“ (Core.GoldList) filterte falsch. Jetzt ist
    Core.realm nie leer (Core.ResolveRealm, Names.lua). Chars.AdoptRealmless führt jeden Satz ohne echten Realm (leer,
    „?“ oder Platzhalter „#…“, Core.RealmKnown) mit dem passenden zusammen:
      - der eigene (gleiche GUID oder – bei regional eindeutigen Namen – gleicher voller Name) → Core.charKey
      - ein Twink → der Satz mit derselben GUID und echtem Realm, sonst (Forever) der einzige mit demselben vollen Namen,
        sonst „Name-<Realm>“ mit dem Realm, den ezCoreDB.realmHints bzw. die übrigen Sätze seiner Realm-Kennung (GUID)
        nennen; ist keiner bekannt, aber die GUID da, „Name-#<Kennung>“ (nie wieder leer)
      - ohne GUID und ohne Treffer bleibt er, wie er ist
    Zusammenführen: der neuere Stand (lastSeen) gewinnt, fehlende Felder kommen vom älteren; das Gold vom Satz mit dem
    jüngeren moneyAt, wo einer es kennt. Nichts wird addiert – der übernommene Satz verschwindet, Gold und Bestände zählen
    einmal. Mit um: Berufe (knowledge.charProfs), Merker renamedNoted und ezPanelFactions, „zuletzt erfasst von“ der
    Gildenbanken, Verläufe (wer) und Sicherungen der Klick-Belegung; für die Daten der Module geht die Nachricht CHAR_KEY_MOVED (alt, neu).
    Läuft bei jedem Anmelden vor dem Anlegen des eigenen Satzes und tut nur etwas, solange solche Sätze da sind;
    db.migrated.realmless[alt] = neu hält fest, was wohin ging.
      Chars.AdoptRealmless(chars) → Anzahl übernommener Sätze
]]

-- Satz mit Schlüssel „Name-Realm“, dessen Realm kein echter ist?
local function IsRealmless(key, c)
    if type(key) ~= "string" or type(c) ~= "table" then return false end
    if Core.RealmKnown(c.realm) then return false end
    local tail = key:match("%-([^%-]*)$")
    if tail == nil then return false end   -- kein Schlüssel der Form „Name-Realm“: nicht anfassen
    return not Core.RealmKnown(tail)
end

local function RecordName(key, c)
    if type(c.name) == "string" and c.name ~= "" and not Core.IsSecret(c.name) then return c.name end
    return key:match("^(.*)%-[^%-]*$")
end

-- Gold beim Zusammenführen: ein Stand mit moneyAt (verlässlich gespeichert) vor einem ohne, bei beiden der jüngere; ohne
-- moneyAt (alle Sätze vor dem 22.11.2026) ein Stand über 0 vor einer 0 – die 0 stammt meist vom Abmelden –, bei zwei
-- Ständen über 0 der neuere Satz (Befund des code-reviewers).
local function PickMoney(newer, older)
    local atNew, atOld = Core.Num(newer.moneyAt), Core.Num(older.moneyAt)
    if atNew or atOld then
        if atOld and (not atNew or atOld > atNew) then return older end
        return newer
    end
    if (Core.Num(newer.money) or 0) <= 0 and (Core.Num(older.money) or 0) > 0 then return older end
    return newer
end

-- Zwei Sätze desselben Charakters → ein neuer Satz, srcNewer. Der neuere (lastSeen) gewinnt Feld für Feld; das Gold
-- nach PickMoney; die Gegenstandslisten (items.bags, .bank, .mail, .equip) je Abschnitt, damit z. B. die Bankliste des
-- älteren Satzes zu seiner Bank-Zählung passt, wenn der neuere die Bank nie gesehen hat.
local function MergeRecords(target, src)
    local srcNewer = (Core.Num(src.lastSeen) or 0) > (Core.Num(target.lastSeen) or 0)
    local newer, older = target, src
    if srcNewer then newer, older = src, target end
    local out = {}
    for k, v in pairs(older) do out[k] = v end
    for k, v in pairs(newer) do out[k] = v end
    local money = PickMoney(newer, older)
    out.money, out.moneyAt = money.money, money.moneyAt
    if type(newer.items) == "table" and type(older.items) == "table" then
        local items = {}
        for k, v in pairs(older.items) do items[k] = v end
        for k, v in pairs(newer.items) do items[k] = v end
        out.items = items
    end
    -- ein leerer Anzeigename aus der Zeit ohne Realm verdrängt keinen echten
    if not Core.RealmKnown(out.realmName) then out.realmName = Core.RealmKnown(older.realmName) and older.realmName or nil end
    return out, srcNewer
end

-- Was außerhalb des Satzes an seinem Schlüssel hängt (in ezCore), vom alten auf den neuen Schlüssel: Berufe, Hinweise,
-- Ruf-Übernahme, Gildenbanken, Verläufe (wer) und die Sicherungen der Klick-Belegung.
function MoveCharRefs(old, new, srcNewer)
    local db = Core.db
    if type(db) ~= "table" then return end
    local profs = type(db.knowledge) == "table" and db.knowledge.charProfs or nil
    if type(profs) == "table" and profs[old] ~= nil then
        if profs[new] == nil or srcNewer then profs[new] = profs[old] end
        profs[old] = nil
    end
    local migrated = type(db.migrated) == "table" and db.migrated or {}
    local noted = migrated.renamedNoted
    if type(noted) == "table" then
        if noted[old] ~= nil then
            if noted[new] == nil then noted[new] = noted[old] end
            noted[old] = nil
        end
        for k, v in pairs(noted) do if v == old then noted[k] = new end end
    end
    local factions = migrated.ezPanelFactions
    if type(factions) == "table" and old ~= "_at" and old ~= "eligible" and new ~= "_at" and new ~= "eligible" then
        if factions[old] ~= nil then
            if factions[new] == nil then factions[new] = factions[old] end
            factions[old] = nil
        end
        local eligible = factions.eligible
        if type(eligible) == "table" and eligible[old] ~= nil then
            if eligible[new] == nil then eligible[new] = eligible[old] end
            eligible[old] = nil
        end
    end
    for _, g in pairs(type(db.guilds) == "table" and db.guilds or {}) do
        if type(g) == "table" and g.by ~= nil and g.by == old then g.by = new end
    end
    for _, list in pairs(type(db.history) == "table" and db.history or {}) do
        for _, e in ipairs(type(list) == "table" and list or {}) do
            if type(e) == "table" and e.c == old then e.c = new end
        end
    end
    -- Sicherungen: der erste Stand ist der älteste, der letzte der jüngste der beiden
    local clicks = type(db.clickBindings) == "table" and db.clickBindings.backups or nil
    local from = type(clicks) == "table" and clicks[old] or nil
    if type(from) == "table" then
        local to = type(clicks[new]) == "table" and clicks[new] or {}
        local function Pick(which, later)
            local a, b = to[which], from[which]
            if type(a) ~= "table" then a = nil end
            if type(b) ~= "table" then b = nil end
            if not (a and b) then return a or b end
            local newer = (Core.Num(b.time) or 0) > (Core.Num(a.time) or 0)
            if newer == later then return b end
            return a
        end
        clicks[new] = { first = Pick("first", false), last = Pick("last", true) }
        clicks[old] = nil
    end
end

-- Zielschlüssel für einen Satz ohne echten Realm → Schlüssel, Realm (oder nil, wenn er bleibt).
local function RealmlessTarget(chars, key, c, myGuid)
    local name = RecordName(key, c)
    if not name or name == "" then return nil end
    local guid = type(c.guid) == "string" and not Core.IsSecret(c.guid) and c.guid ~= "" and c.guid or nil
    -- der gespielte Charakter
    if (guid and myGuid and guid == myGuid)
        or (Core.uniqueNames and Core.fullName and name:lower() == Core.fullName:lower()) then
        return Core.charKey, Core.realm
    end
    -- Sätze mit echtem Realm: dieselbe GUID, sonst (Forever) derselbe volle Name – aber nie ein Satz, dessen GUID bekannt ist
    -- und abweicht (Realm-Transfer oder ein neu vergebener Name; Befund des code-reviewers)
    local wanted, byName, byGuid = name:lower(), {}, {}
    for other, o in pairs(chars) do
        local realm = other ~= key and type(o) == "table" and Core.RecordRealm(other, o)
        if realm then
            local oGuid = type(o.guid) == "string" and not Core.IsSecret(o.guid) and o.guid ~= "" and o.guid or nil
            local oName = RecordName(other, o)
            if guid and oGuid == guid then
                byGuid[#byGuid + 1] = { key = other, realm = realm, name = oName and oName:lower(), seen = Core.Num(o.lastSeen) or 0 }
            elseif Core.uniqueNames and oName and oName:lower() == wanted and not (guid and oGuid) then
                byName[#byName + 1] = { key = other, realm = realm }
            end
        end
    end
    if #byGuid > 0 then
        -- mehrere Sätze mit derselben GUID (Umbenennung): der mit demselben Namen, sonst der zuletzt gesehene; ist auch
        -- das nicht eindeutig, bleibt der Satz, wie er ist
        local pick
        if #byGuid == 1 then pick = byGuid[1] end
        if not pick then
            local same = {}
            for _, e in ipairs(byGuid) do if e.name == wanted then same[#same + 1] = e end end
            if #same == 1 then pick = same[1] end
        end
        if not pick then
            local best, tie
            for _, e in ipairs(byGuid) do
                if not best or e.seen > best.seen then best, tie = e, false elseif e.seen == best.seen then tie = true end
            end
            if not tie then pick = best end
        end
        if not pick then return nil end
        return pick.key, pick.realm
    end
    if #byName == 1 then return byName[1].key, byName[1].realm end
    local id = Core.GuidRealmID(guid)
    if not id then return nil end
    local hints = type(Core.db.realmHints) == "table" and Core.db.realmHints or {}
    local realm = Core.RealmKnown(hints[id]) and Core.NormalizeRealm(hints[id]) or nil
    if not realm then
        local seen, n = nil, 0
        for other, o in pairs(chars) do
            local r = type(o) == "table" and Core.GuidRealmID(o.guid) == id and Core.RecordRealm(other, o)
            if r and (not seen or Core.RealmKey(r) ~= Core.RealmKey(seen)) then seen, n = r, n + 1 end
        end
        if n == 1 then realm = seen end
    end
    -- derselbe Realm wie der gespielte Charakter (gleiche Kennung), auch wenn sein Realm nur ein Platzhalter ist
    if not realm and id == Core.GuidRealmID(myGuid) then realm = Core.realm end
    realm = realm or ("#" .. id)
    local target = name .. "-" .. realm
    if target == key then return nil end
    return target, realm
end

function Chars.AdoptRealmless(chars)
    local db = Core.db
    if type(db) ~= "table" or type(chars) ~= "table" then return 0 end
    local myGuid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player"))
    if type(myGuid) ~= "string" or myGuid == "" then myGuid = nil end
    local todo = {}
    for key, c in pairs(chars) do
        if key ~= Core.charKey and IsRealmless(key, c) then todo[#todo + 1] = key end
    end
    table.sort(todo)
    local n = 0
    for _, key in ipairs(todo) do
        local c = chars[key]
        local target, realm = RealmlessTarget(chars, key, c, myGuid)
        if target and target ~= key then
            local merged, srcNewer = c, true
            if type(chars[target]) == "table" then merged, srcNewer = MergeRecords(chars[target], c) end
            merged.realm = realm
            if not Core.RealmKnown(merged.realmName) then merged.realmName = nil end
            chars[target], chars[key] = merged, nil
            MoveCharRefs(key, target, srcNewer)
            db.migrated = type(db.migrated) == "table" and db.migrated or {}
            db.migrated.realmless = type(db.migrated.realmless) == "table" and db.migrated.realmless or {}
            db.migrated.realmless[key] = target
            Core.Fire("CHAR_KEY_MOVED", key, target)
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Gold: nur verlässliche Stände speichern (Spielbefund vom 22.11.2026)
---------------------------------------------------------------------------

--[[
    Für alle Twinks stand 0 Gold, obwohl einige Silber haben (Spielbefund vom 22.11.2026: ein Twink mit 13 Silber hatte
    nach seiner Sitzung money 0, der Hauptcharakter folgte live über PLAYER_MONEY). Beim Abmelden kennt der Client die
    Taschen nicht mehr (Inventory.ScanBags, FP-07), und GetMoney() liefert dann – wie vermutlich früh beim Laden – 0; jede
    Stelle schrieb das blind. Chars.SaveMoney(sicher, anlass) schreibt jetzt nur:
      - einen Stand über 0 (immer),
      - eine 0 nur aus Blizzards PLAYER_MONEY (sicher = true): dann hat sich das Gold wirklich auf 0 geändert.
    Anmelden, Betreten der Welt, das Nachlesen Chars.MONEY_SETTLE Sekunden danach, der Taschen-Scan und das Abmelden
    schreiben also nur einen Stand über 0. Grenze: Hat ein Twink wirklich 0 Gold und ist ein älterer Stand über 0
    gespeichert, bleibt dieser, bis sich sein Gold einmal ändert. Nach PLAYER_LEAVING_WORLD bis zum nächsten
    PLAYER_ENTERING_WORLD (Ladebildschirm, Abmelden) gilt auch eine 0 aus PLAYER_MONEY nicht als sicher – ob Forever dort
    PLAYER_MONEY mit 0 schickt, ist nicht belegt. moneyAt merkt die Zeit des letzten geschriebenen Stands (für
    Chars.AdoptRealmless). Chars.MoneyTrace hält fest, was der Client wann nannte (/dump ezCore.Characters.MoneyTrace im
    Spiel; zeigt, ob GetMoney() bei PLAYER_LOGIN auf Forever noch 0 liefert); beim Abmelden kommt eine Kopie nach
    ezCoreDB.moneyTrace (nur die letzte Sitzung, mit dem Wert beim Abmelden – /dump ezCore.db.moneyTrace nach dem
    nächsten Anmelden).
      Chars.EventMoney()    → das Gold des Clients bei PLAYER_MONEY; nil, wenn er eine 0 im Ladebildschirm nennt (nicht
                              sicher). Für Verlauf und Sitzung – sonst zählte das ganze Gold als Ausgabe
      Chars.MoneyBaseline() → Ausgangsstand für Gold-Differenzen (Verlauf, Sitzung in History.lua): das Gold des Clients,
                              solange es über 0 liegt, sonst der zuletzt verlässlich gespeicherte Stand, sonst nil.
                              Auch das Gold „jetzt“ für Anzeigen (ezPanel)
]]
Chars.MONEY_SETTLE = 3
Chars.MoneyTrace = {}
-- zwischen PLAYER_LEAVING_WORLD und PLAYER_ENTERING_WORLD – auch ganz am Anfang, bis die Welt das erste Mal da ist
local leaving = true

function Chars.SaveMoney(sure, why)
    local money = Core.Num(Core.Call(rawget(_G, "GetMoney")))
    local trace = Chars.MoneyTrace
    if why then
        trace[why] = money
        if why == "event" then trace.events = (trace.events or 0) + 1 end
    end
    local me = Core.me
    if not me or not money or money < 0 then return false end
    if money > 0 or (sure == true and not leaving) then
        me.money, me.moneyAt = money, time()
        return true
    end
    return false
end

function Chars.EventMoney()
    local money = Core.Num(Core.Call(rawget(_G, "GetMoney")))
    if not money or money < 0 or (money == 0 and leaving) then return nil end
    return money
end

function Chars.MoneyBaseline()
    local live = Core.Num(Core.Call(rawget(_G, "GetMoney")))
    if live and live > 0 then return live end
    local me = Core.me
    local stored = type(me) == "table" and Core.Num(me.money) or nil
    if stored and (stored > 0 or Core.Num(me.moneyAt)) then return stored end
    return nil
end

function Chars.OnLeaveWorld() leaving = true end
ns.On("PLAYER_LEAVING_WORLD", function() Chars.OnLeaveWorld() end)

---------------------------------------------------------------------------
-- Der aktuelle Charakter
---------------------------------------------------------------------------

local function UpdateMe()
    local me = Core.me
    if not me then return end
    me.name = Core.fullName or Core.firstName
    me.realm = Core.realm
    local realmName = Core.Plain(Core.Call(rawget(_G, "GetRealmName")))
    if type(realmName) == "string" and realmName ~= "" then
        me.realmName = realmName
    elseif not Core.RealmKnown(me.realmName) then
        me.realmName = nil   -- leeren Anzeigenamen aus der Zeit ohne Realm nicht stehen lassen
    end
    me.class = select(2, UnitClass("player"))
    me.faction = UnitFactionGroup("player")
    me.level = UnitLevel("player")
    Chars.SaveMoney(false, "login")
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
    local okOld, errOld = pcall(Chars.AdoptOldKey, db.chars)
    if not okOld then Core.Error(Core.name, errOld, "AdoptOldKey") end
    local okAdopt, errAdopt = pcall(Chars.AdoptRealmless, db.chars)
    if not okAdopt then Core.Error(Core.name, errAdopt, "AdoptRealmless") end

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

ns.On("PLAYER_MONEY", function() Chars.SaveMoney(true, "event") end)

-- Nach jedem Ladebildschirm: Gold sofort und nach Chars.MONEY_SETTLE Sekunden noch einmal (beides nur über 0). Liefert der
-- Client inzwischen einen Realmnamen, merkt ezCore ihn fürs nächste Anmelden (Core.RememberRealmHint) – den Schlüssel
-- dieser Sitzung ändert das nicht.
function Chars.OnEnterWorld()
    leaving = false
    Chars.SaveMoney(false, "enter")
    Core.RememberRealmHint()
    if C_Timer and C_Timer.After then
        C_Timer.After(Chars.MONEY_SETTLE, function()
            Chars.SaveMoney(false, "settled")
            Core.RememberRealmHint()
        end)
    end
end
ns.On("PLAYER_ENTERING_WORLD", function() Chars.OnEnterWorld() end)

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
    leaving = true
    Chars.SaveMoney(false, "logout")   -- beim Abmelden liefert der Client oft 0: nur ein Stand über 0 zählt
    -- Verlauf dieser Sitzung für den Spieltest (S6): was GetMoney() wann lieferte, auch beim Abmelden
    if type(Core.db) == "table" then
        local copy = { at = time() }
        for k, v in pairs(Chars.MoneyTrace) do copy[k] = v end
        Core.db.moneyTrace = copy
    end
end)

-- ezCore zuerst: alle Module finden beim Einloggen fertige Charakterdaten vor.
ns.On("PLAYER_LOGIN", Chars.Login)
