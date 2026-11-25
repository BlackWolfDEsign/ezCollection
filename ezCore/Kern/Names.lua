local _, ns = ...
local Core = ezCore

--[[
    Namen (vorher ezChat und ezMail): WoW Forever hat regional eindeutige Namen aus Vor- und
    Nachname. UnitName liefert dort den Nachnamen an der Stelle des Realms. Ein Charakter heißt
    „Vorname Nachname“ (Trennzeichen aus Blizzards Konstanten); Spieler-Links und Ereignisse
    können auch „Vorname-Nachname“ liefern. Flüstern und Post brauchen den vollen Namen.
    Auf anderen Clients bleibt es bei „Name-Realm“.

    Core.InitIdentity() (beim Einloggen) setzt:
      Core.realm        normalisierter Realm („DieAldor“), nie leer (Core.ResolveRealm)
      Core.realmSource  woher er stammt: "client", "hint", "guid", "name", "server", "id" (Platzhalter) oder "unknown"
      Core.uniqueNames  Vor- und Nachnamen aktiv?
      Core.surnameSep   Trennzeichen zwischen Vor- und Nachname
      Core.selfName     voller eigener Name
      Core.charKey      Schlüssel der Charakterdaten: voller Name-Realm
      Core.oldCharKey   alter Schlüssel nur mit Vornamen (ezBag/ezMail bis 1.3)
]]

local function UniqueNamesEnabled()
    if type(RegionalUniqueNamesEnabled) ~= "function" then return false end
    local ok, enabled = pcall(RegionalUniqueNamesEnabled)
    return ok and enabled == true
end

local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(sep) == "string" and sep ~= "" then return sep end
    return " "
end

local function Capitalize(word)
    return word:sub(1, 1):upper() .. word:sub(2)
end

-- Realm ohne Leer- und Bindestriche, wie GetNormalizedRealmName.
function Core.NormalizeRealm(realm)
    return ((realm or ""):gsub("[%s%-]", ""))
end

-- Realm als Vergleichsschlüssel: „Die Aldor“, „DieAldor“ und „diealdor“ sind gleich.
function Core.RealmKey(realm)
    return Core.NormalizeRealm(realm):lower()
end

--[[
    Realm ermitteln (Spielbefund vom 22.11.2026): Der Client von WoW Forever liefert keinen Realmnamen
    (GetNormalizedRealmName und GetRealmName leer, GetRealmID 0 – auch noch am Auktionshaus, Spieltest vom 21.11.2026).
    Core.realm wurde dadurch "" und neue Charakter-Sätze hießen „Name-“; derselbe Charakter stand doppelt. Jetzt wird
    nie ein leerer Realm gespeichert. Reihenfolge:
      "client"  GetNormalizedRealmName, sonst GetRealmName
      "hint"    ein früher in dieser Installation gelesener Name zur Realm-Kennung aus der GUID (ezCoreDB.realmHints,
                geschrieben, sobald der Client einen Namen liefert)
      "guid"    der Realm eines gespeicherten Satzes mit derselben Spieler-GUID
      "name"    nur bei regional eindeutigen Namen (Forever): der Realm des einzigen Satzes mit demselben vollen Namen
      "server"  der Realm, den alle gespeicherten Sätze mit derselben Realm-Kennung in der GUID tragen (nur, wenn es
                genau einer ist)
      "id"      Platzhalter „#<Realm-Kennung>“ aus der GUID (Player-<Kennung>-…): trennt Realms, bis ein Name bekannt ist
      "unknown" „?“ (ohne GUID)
    Core.RealmKnown(realm) unterscheidet echte Namen von „?“ und Platzhaltern; Keys.RealmName (Preis-Bereiche) nimmt
    Core.realm nur, wenn er vom Client stammt.
]]

-- Ist realm ein echter Realmname (nicht leer, nicht „?“, kein Platzhalter „#…“)?
function Core.RealmKnown(realm)
    if Core.IsSecret(realm) or type(realm) ~= "string" then return false end
    return realm ~= "" and realm ~= "?" and realm:sub(1, 1) ~= "#"
end

-- Realm laut Client in normalisierter Form, sonst nil.
function Core.ClientRealm()
    for _, fname in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
        local name = Core.Plain(Core.Call(rawget(_G, fname)))
        if type(name) == "string" then
            name = Core.NormalizeRealm(name)
            if name ~= "" then return name end
        end
    end
    return nil
end

-- Realm-Kennung aus einer Spieler-GUID („Player-1234-0A1B2C3D“ → "1234"), sonst nil.
function Core.GuidRealmID(guid)
    if Core.IsSecret(guid) or type(guid) ~= "string" then return nil end
    return guid:match("^Player%-(%d+)%-")
end

-- Anzeigename eines Realms: der gespeicherte Anzeigename, sonst der Schlüssel; ein Platzhalter „#1234“ als „Realm Nr. 1234“.
function Core.RealmLabel(realm, realmName)
    if type(realmName) == "string" and not Core.IsSecret(realmName) and realmName ~= "" then return realmName end
    if type(realm) ~= "string" or Core.IsSecret(realm) or realm == "" then return "?" end
    local id = realm:match("^#(%d+)$")
    if id and Core.L and Core.L.REALM_BY_ID then return Core.L.REALM_BY_ID:format(id) end
    return realm
end

-- Realm eines gespeicherten Satzes: das Feld realm, sonst der Teil hinter dem letzten Bindestrich des Schlüssels.
local function RecordRealm(key, c)
    local realm = type(c) == "table" and c.realm or nil
    if not Core.RealmKnown(realm) and type(key) == "string" then realm = key:match("%-([^%-]+)$") end
    return Core.RealmKnown(realm) and realm or nil
end
Core.RecordRealm = RecordRealm

-- Genau ein Wert in der Menge { [RealmKey] = realm }? → realm
local function OnlyOne(set)
    local one, n = nil, 0
    for _, realm in pairs(set) do one, n = realm, n + 1 end
    if n == 1 then return one end
    return nil
end

-- → realm, quelle (siehe oben). guid und full: GUID und voller Name des gespielten Charakters (fehlen sie, wird gelesen).
function Core.ResolveRealm(guid, full)
    local realm = Core.ClientRealm()
    if realm then return realm, "client" end
    if guid == nil then guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player")) end
    if type(guid) ~= "string" or guid == "" then guid = nil end
    local id = Core.GuidRealmID(guid)
    local db = Core.db
    local hints = type(db) == "table" and type(db.realmHints) == "table" and db.realmHints or nil
    if id and hints and Core.RealmKnown(hints[id]) then return Core.NormalizeRealm(hints[id]), "hint" end
    local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or {}
    local byName, byServer = {}, {}
    local wanted = Core.uniqueNames ~= false and type(full) == "string" and full ~= "" and full:lower() or nil
    for key, c in pairs(chars) do
        local known = type(c) == "table" and RecordRealm(key, c)
        if known then
            if guid and c.guid == guid then return known, "guid" end
            -- derselbe Name, aber eine andere bekannte GUID (Realm-Transfer, neu vergebener Name): kein Treffer
            local other = type(c.guid) == "string" and not Core.IsSecret(c.guid) and c.guid ~= "" and c.guid or nil
            if wanted and type(c.name) == "string" and c.name:lower() == wanted and not (guid and other) then
                byName[Core.RealmKey(known)] = known
            end
            if id and Core.GuidRealmID(c.guid) == id then byServer[Core.RealmKey(known)] = known end
        end
    end
    realm = OnlyOne(byName)
    if realm then return realm, "name" end
    realm = OnlyOne(byServer)
    if realm then return realm, "server" end
    if id then return "#" .. id, "id" end
    return "?", "unknown"
end

-- Liefert der Client jetzt einen Realmnamen, wird er zur Realm-Kennung der GUID gemerkt (ezCoreDB.realmHints), damit das
-- nächste Anmelden ihn auch ohne Client-Antwort kennt. → Name oder nil
function Core.RememberRealmHint(guid)
    local realm = Core.ClientRealm()
    local db = Core.db
    if not realm or type(db) ~= "table" then return nil end
    if guid == nil then guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player")) end
    local id = Core.GuidRealmID(guid)
    if not id then return realm end
    db.realmHints = type(db.realmHints) == "table" and db.realmHints or {}
    db.realmHints[id] = realm
    return realm
end

function Core.InitIdentity()
    local name, surname = UnitName("player")
    name = name or "?"
    local guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), "player"))
    if type(guid) ~= "string" or guid == "" then guid = nil end
    -- Liefert UnitName für den eigenen Charakter einen zweiten Teil, ist es der Nachname (WoW Forever).
    Core.uniqueNames = UniqueNamesEnabled() or (type(surname) == "string" and surname ~= "")
    Core.surnameSep = SurnameSeparator()
    local full
    if Core.uniqueNames then
        if type(surname) == "string" and surname ~= "" then
            full = name .. Core.surnameSep .. surname
        else
            -- Ersatz, wenn der Nachname fehlt: voller Name aus der GUID
            if guid and GetPlayerInfoByGUID then
                local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
                if ok and type(n) == "string" and not Core.IsSecret(n) and n ~= "" then full = n end
            end
        end
    end
    local realm, source = Core.ResolveRealm(guid, full or name)
    Core.realm, Core.realmSource = realm, source
    if source == "client" then Core.RememberRealmHint(guid) end
    Core.selfName = full or (name .. "-" .. realm)
    Core.charKey = (full or name) .. "-" .. realm
    Core.oldCharKey = name .. "-" .. realm
    Core.firstName = name
    Core.fullName = full
    ns.realm, ns.charKey = Core.realm, Core.charKey
    return Core.charKey
end

-- Rohname aus Ereignissen, Listen oder Eingaben → einheitlicher voller Name:
-- WoW Forever „Vorname Nachname“ (ohne Nachnamen nur „Vorname“), sonst „Name-Realm“.
function Core.FullName(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    name = Core.Trim(name):gsub("%s+", " ")
    if name == "" then return nil end
    local left, right = name:match("^(.-)%-(.+)$")
    if left == "" then left = nil end

    if Core.uniqueNames then
        local sep = Core.surnameSep or " "
        if left then
            local isRealm = right:gsub("%s", ""):lower() == (Core.realm or ""):lower()
            if isRealm or left:find(" ", 1, true) then
                name = left                          -- „Vorname Nachname-Realm“, „Vorname-Realm“
            else
                name = left .. sep .. right          -- „Vorname-Nachname“ (Link-Form)
            end
        end
        name = name:gsub(" ", sep)
        local first, rest = name:match("^(%S+)(.*)$")
        return Capitalize(first) .. rest
    end

    local base, realm
    if left then
        base, realm = left, right:gsub("%s", "")
    else
        base, realm = name, Core.realm or ""
    end
    return Capitalize(base) .. "-" .. realm
end

-- Anzeige- und Flüstername: auf Forever der volle Name, sonst ohne eigenen Realm.
function Core.ShortName(full)
    if type(full) ~= "string" then return "?" end
    if Core.uniqueNames then return full end
    local base, realm = full:match("^(.-)%-(.+)$")
    if base and realm == Core.realm then return base end
    return full
end

-- Spieler-Link (|Hplayer:…|h): Blizzard ersetzt dort das Nachnamen-Trennzeichen.
function Core.LinkName(full)
    if Core.uniqueNames and C_NameUtil and C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator then
        local ok, result = pcall(C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator, full)
        if ok and type(result) == "string" then return result end
    end
    return full
end

function Core.IsSelf(full)
    return type(full) == "string" and Core.selfName ~= nil and full:lower() == Core.selfName:lower()
end

-- Hat der Name auf WoW Forever noch keinen Nachnamen?
function Core.MissingSurname(full)
    return Core.uniqueNames and type(full) == "string" and not full:find(Core.surnameSep or " ", 1, true)
end

-- Voller Name einer Einheit (Forever: „Vorname Nachname“, sonst „Name-Realm“ wie Core.FullName);
-- nil bei geheimem oder leerem Namen. Vorher ezBuff.
function Core.UnitFullName(unit)
    if not UnitName then return nil end
    local ok, name, second = pcall(UnitName, unit)
    if not ok or Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if Core.IsSecret(second) or type(second) ~= "string" or second == "" then second = nil end
    if second then
        name = name .. (Core.uniqueNames and (Core.surnameSep or " ") or "-") .. second
    end
    return Core.FullName(name) or name
end

-- Stabiler Schlüssel einer Einheit, „Name-Realm“ wie Core.charKey und die Schlüssel der Charakterdaten, dazu der
-- Anzeigename (EC-112; vorher ezBuff, Check.PlayerKey). → schlüssel, name; nil bei gesperrter Einheit oder
-- gesperrtem bzw. leerem Namen. Forever: „Vorname Nachname“ (Core.UnitFullName; UnitName liefert dort den
-- Nachnamen statt des Realms), der Realm kommt aus der GUID (GetPlayerInfoByGUID, leer = eigener Realm).
-- Andere Clients: Core.UnitFullName liefert schon „Name-Realm“.
function Core.UnitKey(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" or unit == "" then return nil end
    local name = Core.UnitFullName(unit)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name, name end
    local realm
    local guid = Core.Plain(Core.Call(rawget(_G, "UnitGUID"), unit))
    if type(guid) == "string" and guid ~= "" then
        local _, _, _, _, _, _, guidRealm = Core.Call(rawget(_G, "GetPlayerInfoByGUID"), guid)
        if not Core.IsSecret(guidRealm) and type(guidRealm) == "string" and guidRealm ~= "" then
            realm = Core.NormalizeRealm(guidRealm)
        end
    end
    return name .. "-" .. (realm or Core.realm or "?"), name
end

-- Kann Post an einen Charakter dieses Realms gehen? Eine Regel für Twinks (Core.MailTarget) und Kontakte (ezMails
-- Adressbuch): auf WoW Forever (regional eindeutige Namen, Core.uniqueNames) jeder Realm, sonst der eigene und die
-- verbundenen (Core.MailRealms). Gesamtreview 18.11.2026, T4-NR8 – ob Forever-Post wirklich jeden Realm erreicht, prüft
-- der Spieltest (docs/roadmap/ezCore.md, „Im Spiel prüfen“).
function Core.MailReachable(realm)
    if Core.uniqueNames then return true end
    if Core.IsSecret(realm) or realm == nil or realm == "" then return true end
    return Core.MailRealms()[Core.RealmKey(realm)] == true
end

-- Ist Post an diesen Realm sicher zustellbar? Strenger als Core.MailReachable: auf WoW Forever zählt jeder Realm erst,
-- wenn der Spieltest die Post über alle Realms bestätigt hat (dann Core.MAIL_ANY_REALM_CONFIRMED = true setzen);
-- bis dahin der eigene und die verbundenen Realms wie überall. Für Rechnungen, deren Fehler unsichtbar bliebe – den
-- erreichbaren Bestand (Inventory.Reachable: „genug da“, Warnung vor Doppelkauf); Adressbuch und Empfänger bleiben bei
-- Core.MailReachable, dort zeigt ein Fehlschlag Blizzards Post selbst (Gegenprüfung zu T4-NR8/T4-NR5).
Core.MAIL_ANY_REALM_CONFIRMED = false
function Core.MailRealmConfirmed(realm)
    if Core.IsSecret(realm) or realm == nil or realm == "" then return false end   -- unbekannt: nicht sicher erreichbar
    if Core.uniqueNames and Core.MAIL_ANY_REALM_CONFIRMED == true then return true end
    return Core.MailRealms()[Core.RealmKey(realm)] == true
end

-- Empfänger für Post an einen Charakter (Name, Realm, Fraktion) → name, canMail, warum (nil, wenn erreichbar;
-- "realm": Realm nicht erreichbar, "faction": andere Fraktion, "unknown": Fraktion nicht bekannt – zählt nicht als
-- erreichbar, die Anzeige nennt den Grund). Forever: der volle Name ohne Realm (wie bei Kontakten); sonst „Name-Realm“
-- für andere Realms. Die eine Regel hinter Core.AltRecipient (T4-NR8).
function Core.MailTarget(name, realm, faction)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil, false end
    if Core.IsSecret(realm) or realm == "" then realm = nil end
    local sameRealm = realm == nil or Core.RealmKey(realm) == Core.RealmKey(Core.realm)
    local target = (sameRealm or Core.uniqueNames) and name or (name .. "-" .. realm)
    if not (sameRealm or Core.MailReachable(realm)) then return target, false, "realm" end
    local myFaction = UnitFactionGroup and Core.Plain((UnitFactionGroup("player")))
    if Core.IsSecret(faction) or type(faction) ~= "string" or faction == "" then return target, false, "unknown" end
    if type(myFaction) == "string" and myFaction ~= "" and faction ~= myFaction then return target, false, "faction" end
    return target, true
end

-- Empfänger für Post an einen eigenen Twink und ob er sie bekommen kann (gleiche Fraktion, erreichbarer
-- Realm): name, canMail, warum (Core.MailTarget). Eine Regel für ezMails Adressbuch und ezCraft (vorher in beiden
-- gerechnet).
function Core.AltRecipient(key)
    local c = key and Core.Char(key)
    if type(c) ~= "table" then return nil, false end
    local name = c.name or key:match("^(.-)%-")
    local realm = c.realm or key:match("%-([^%-]+)$")
    if not name then return nil, false end
    return Core.MailTarget(name, realm, c.faction)
end

-- Auktionshaus als Name „Realm-Fraktion“ – die eine Stelle für diesen Schlüssel (Core.Prices.Key und damit ezAuctions
-- „Zuletzt“, der Einstell-Verlauf je Haus, Core.SameHouse). Ohne Angaben der gespielte Charakter. Verbundene Realms
-- gelten wie die Preis-Bereiche (Keys.Market) als eigene Häuser; klärt eine Probe, dass sie ein Haus teilen, ändert sich
-- nur diese Zuordnung (T4-NR7).
function Core.HouseKey(realm, faction)
    if Core.IsSecret(realm) or realm == "" then realm = nil end
    if realm == nil then
        realm = Core.realm or (GetRealmName and Core.RealmKey(GetRealmName())) or nil
    else
        realm = Core.NormalizeRealm(realm)
    end
    if faction == nil then faction = UnitFactionGroup and Core.Plain((UnitFactionGroup("player"))) or nil end
    if Core.IsSecret(faction) or faction == "" then faction = nil end
    return tostring(realm or "?") .. "-" .. tostring(faction or "?")
end

-- Haus eines eigenen Charakters (Schlüssel) → „Realm-Fraktion“ oder nil, solange seine Fraktion unbekannt ist.
function Core.CharHouseKey(key)
    if key == nil or key == Core.charKey then return Core.HouseKey() end
    local c = Core.Char and Core.Char(key)
    local realm = type(c) == "table" and c.realm or (type(key) == "string" and key:match("%-([^%-]+)$")) or nil
    local faction = type(c) == "table" and c.faction or nil
    if type(realm) ~= "string" or realm == "" or type(faction) ~= "string" or faction == "" then return nil end
    return Core.HouseKey(realm, faction)
end

-- Steht ein eigener Charakter am selben Auktionshaus wie der gespielte (Core.HouseKey)?
function Core.SameHouse(key)
    local house = Core.CharHouseKey(key)
    return house ~= nil and house:lower() == Core.HouseKey():lower()
end

-- Realms, an die Post gehen kann: der eigene und verbundene Realms (als RealmKey-Menge).
function Core.MailRealms()
    local set = { [Core.RealmKey(Core.realm)] = true }
    local realms = Core.Plain((Core.Call((C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms)
        or rawget(_G, "GetAutoCompleteRealms"))))
    if type(realms) == "table" then
        for _, realm in ipairs(realms) do
            if not Core.IsSecret(realm) then set[Core.RealmKey(realm)] = true end
        end
    end
    return set
end

---------------------------------------------------------------------------
-- Battle.net und bekannte Spieler (vorher ezChat)
---------------------------------------------------------------------------

function Core.BNInfoByID(id)
    if Core.IsSecret(id) or id == nil or not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil end
    local ok, info = pcall(C_BattleNet.GetAccountInfoByID, id)
    if ok and type(info) == "table" then return info end
    return nil
end

function Core.BNTagOf(id)
    local info = Core.BNInfoByID(id)
    local tag = info and info.battleTag
    if type(tag) == "string" and not Core.IsSecret(tag) and tag ~= "" then return tag end
    return nil
end

-- Charakter eines Battle.net-Freundes, der gerade dieses Spiel spielt (sonst nil).
-- Blizzard nennt dafür selbst das Flüsterziel (GetDefaultTitleWhisperTarget).
function Core.BNCharacter(info)
    local game = type(info) == "table" and info.gameAccountInfo
    if type(game) ~= "table" or game.isOnline ~= true then return nil end
    if game.clientProgram ~= (BNET_CLIENT_WOW or "WoW") then return nil end
    if WOW_PROJECT_ID and game.wowProjectID ~= nil and game.wowProjectID ~= WOW_PROJECT_ID then return nil end
    local target
    if C_BattleNet.GetDefaultTitleWhisperTarget and info.bnetAccountID and Core.Usable(info.bnetAccountID) then
        local ok, result = pcall(C_BattleNet.GetDefaultTitleWhisperTarget, info.bnetAccountID)
        if ok and type(result) == "string" and result ~= "" and Core.Usable(result) then target = result end
    end
    if not target then
        local name, realm = game.characterName, game.realmName
        if type(name) ~= "string" or name == "" or not Core.Usable(name, realm) then return nil end
        if not Core.uniqueNames and type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
        target = name
    end
    return Core.FullName(target)
end

-- Alle Battle.net-Freunde, auch offline oder in anderen Spielen:
-- { { id, tag, name (BattleTag ohne #Zahl), online, accountName, character (in diesem Spiel, sonst nil), info } … }
function Core.BNFriends()
    local list = {}
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return list end
    local okN, n = pcall(BNGetNumFriends)
    for i = 1, (okN and Core.Num(n)) or 0 do
        local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
        local tag = ok and type(info) == "table" and Core.Plain(info.battleTag)
        if type(tag) == "string" and tag ~= "" then
            local game = Core.Plain(info.gameAccountInfo)
            local account = Core.Plain(info.accountName)
            list[#list + 1] = {
                id = Core.Plain(info.bnetAccountID), tag = tag, name = tag:match("^(.-)#") or tag,
                online = type(game) == "table" and game.isOnline == true,
                accountName = type(account) == "string" and account ~= "" and account or nil,
                character = Core.BNCharacter(info), info = info,
            }
        end
    end
    return list
end

-- BattleTag → Konto-ID, online?, Kontoname (nur für Blizzards Chatfunktionen)
function Core.BNFind(tag)
    if type(tag) ~= "string" or Core.IsSecret(tag) then return nil end
    local wanted = tag:lower()
    for _, friend in ipairs(Core.BNFriends()) do
        if friend.tag:lower() == wanted then return friend.id, friend.online, friend.accountName end
    end
    return nil
end

-- Blizzards Kontoname (|K…|k eines Flüster-Reiters) → BattleTag; die Umkehrung von BNFind.
function Core.BNTagOfAccountName(accountName)
    if type(accountName) ~= "string" or Core.IsSecret(accountName) or accountName == "" then return nil end
    for _, friend in ipairs(Core.BNFriends()) do
        if friend.accountName == accountName then return friend.tag end
    end
    return nil
end

-- Alle bekannten Spieler: fn(full, online, source, bnLabel, class, level, zone) mit
-- source = "friend" (WoW-Freund), "bnet" (Battle.net-Freund in diesem Spiel), "guild",
-- class = Klassen-Token („MAGE“) oder nil, wenn Blizzard keine Klasse nennt (z. B. Freund offline),
-- level und zone, soweit Blizzard sie nennt (sonst nil).
function Core.ForEachContact(fn)
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, (C_FriendList.GetNumFriends() or 0) do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and type(info) == "table" and type(info.name) == "string" and Core.Usable(info.name) then
                local full = Core.FullName(info.name)
                if full then
                    fn(full, info.connected == true, "friend", nil, Core.ClassToken(info.className), Core.Num(info.level), Core.Plain(info.area))
                end
            end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, (BNGetNumFriends() or 0) do
            local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if ok and type(info) == "table" then
                local full = Core.BNCharacter(info)
                if full then
                    local tag = type(info.battleTag) == "string" and Core.Usable(info.battleTag) and info.battleTag or nil
                    local game = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
                    fn(full, true, "bnet", tag and (tag:match("^(.-)#") or tag), Core.ClassToken(game.className),
                        Core.Num(game.characterLevel), Core.Plain(game.areaName))
                end
            end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, level, _, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if type(name) == "string" and Core.Usable(name, isOnline) then
                local full = Core.FullName(name)
                if full then fn(full, isOnline and true or false, "guild", nil, Core.Plain(classFile), Core.Num(level), Core.Plain(zone)) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Aus einer GUID (vorher in ezChat, ezSocial, ezMap und im Einheiten-Tooltip)
---------------------------------------------------------------------------

-- Klassen-Token („MAGE“) eines Spielers aus seiner GUID, sonst nil.
function Core.ClassOfGUID(guid)
    if Core.IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local _, classFile = Core.Call(rawget(_G, "GetPlayerInfoByGUID"), guid)
    if Core.IsSecret(classFile) or type(classFile) ~= "string" or classFile == "" then return nil end
    return classFile
end

-- NPC-ID aus einer GUID („Creature-0-…-1234-…“ → 1234); nil für Spieler, Gegenstände und Unlesbares.
function Core.NpcID(guid)
    if Core.IsSecret(guid) or type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if id and (kind == "Creature" or kind == "Vehicle" or kind == "Pet") then return tonumber(id) end
    return nil
end

---------------------------------------------------------------------------
-- Text zum Weitergeben ohne eigene Namen (Nutzer, 24.11.2026: „Natürlich anonymer Export“)
---------------------------------------------------------------------------

--[[
    Core.Anonymous(text) → Text, in dem die Namen der eigenen Charaktere (auch Vor- und Nachname einzeln), ihrer Realms,
    die eigene Gilde und die Mitglieder der Gruppe ersetzt sind (L.ANON_CHAR, L.ANON_REALM, L.ANON_GUILD, L.ANON_PLAYER).
    Ersetzt wird nur ein ganzes Wort: „Al“ trifft nicht „Alles“ (Genitiv „Als“ und andere Schreibweisen bleiben). Dazu jede
    Spieler-GUID („Player-…“, nennt Realm und Charakter). Unbekannte Namen (aus Fehlertexten fremder Addons) kennt ezCore
    nicht – der Hinweis an der Fehlerliste bleibt deshalb.
]]
-- Teil eines Wortes: ASCII-Buchstabe, Ziffer oder ein Zeichen aus zwei Bytes ab C3 (Umlaute, Kyrillisch, Griechisch). C2
-- (geschütztes Leerzeichen, »«, ·) und alle Zeichen aus drei Bytes (Striche, Anführungen, Pfeile, Schriften ohne
-- Wortabstand) sind Grenzen: im Zweifel wird eher zu viel ersetzt.
local function PartOfWord(text, i, step)
    local c = text:byte(i)
    if not c then return false end
    if c < 128 then return text:sub(i, i):match("%w") ~= nil end
    if step < 0 then
        while i > 1 and c >= 128 and c < 192 do i = i - 1 c = text:byte(i) end
    end
    return c >= 195 and c < 224
end

local function ReplaceWord(text, word, by)
    local out, from = {}, 1
    while true do
        local a, b = text:find(word, from, true)
        if not a then break end
        if PartOfWord(text, a - 1, -1) or PartOfWord(text, b + 1, 1) then
            out[#out + 1] = text:sub(from, a)
            from = a + 1
        else
            out[#out + 1] = text:sub(from, a - 1) .. by
            from = b + 1
        end
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
end

function Core.Anonymous(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return text end
    local L, words = Core.L, {}
    text = text:gsub("Player%-%d+%-%x+", L.ANON_PLAYER)
    local function Add(name, by)
        if Core.IsSecret(name) or type(name) ~= "string" then return end
        name = Core.Trim(name)
        if #name >= 2 and name ~= "?" and words[name] == nil then words[name] = by end
    end
    local function AddPerson(name, by)
        if Core.IsSecret(name) or type(name) ~= "string" then return end
        Add(name, by)
        for part in name:gmatch("%S+") do Add(part, by) end
    end
    local function AddRealm(realm)
        if Core.RealmKnown(realm) then
            Add(realm, L.ANON_REALM)
            Add(Core.NormalizeRealm(realm), L.ANON_REALM)
        end
    end
    AddPerson(Core.fullName, L.ANON_CHAR)
    AddPerson(Core.firstName, L.ANON_CHAR)
    AddRealm(Core.realm)
    for key, c in pairs(Core.db and type(Core.db.chars) == "table" and Core.db.chars or {}) do
        if type(key) == "string" then AddPerson(key:match("^(.-)%-"), L.ANON_CHAR) end
        if type(c) == "table" then AddPerson(c.name, L.ANON_CHAR) end
        AddRealm(Core.RecordRealm(key, c))
    end
    Add(Core.Plain(Core.Call(rawget(_G, "GetGuildInfo"), "player")), L.ANON_GUILD)
    local unitName = rawget(_G, "UnitName")
    for i = 1, 4 do AddPerson(Core.Plain(Core.Call(unitName, "party" .. i)), L.ANON_PLAYER) end
    if Core.Plain(Core.Call(rawget(_G, "IsInRaid"))) == true then
        for i = 1, 40 do AddPerson(Core.Plain(Core.Call(unitName, "raid" .. i)), L.ANON_PLAYER) end
    end
    -- längere zuerst: der volle Name vor seinen Teilen
    local list = {}
    for name in pairs(words) do list[#list + 1] = name end
    table.sort(list, function(a, b) if #a ~= #b then return #a > #b end return a < b end)
    for _, name in ipairs(list) do text = ReplaceWord(text, name, words[name]) end
    return text
end
