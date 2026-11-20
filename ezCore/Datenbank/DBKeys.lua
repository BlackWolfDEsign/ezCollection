local _, ns = ...
local Core = ezCore

--[[
    Schlüssel der Entdecker-Datenbank an EINER Stelle (Entwurf docs/archiv/entwurf-entdecker-datenbank.md, Abschnitt 2).
    Kein anderer Teil von ezCore und kein Modul setzt Schlüssel der Datenbank zusammen oder zerlegt sie.
    Abweichung vom Entwurf: Der Entwurf nennt den Dienst `Core.Keys`; diesen Namen trägt seit Welle 7 der
    Tasten-Dienst (Keys.lua). Die Schlüsselbildner stehen deshalb unter `Core.DB.Keys`.

    Jede Funktion prüft zuerst Core.IsSecret und gibt bei gesperrtem Wert nil zurück (nie verglichen, nie gerechnet).

      Keys.KINDS                     Arten von drops und spot: { [art] = { space, levels, drops, spot, explorer } }
      Keys.Build()                   Build-Nummer des Clients als Zahl (0 = unbekannt)
      Keys.Locale()                  Sprache des Clients („deDE“)
      Keys.Guid(guid)                → Art, ID; Creature, Vehicle, GameObject (Feld 6), Item (über den Client);
                                       Player und Pet: nur die Art, nie eine ID
      Keys.Npc(einheit | guid)       → npcID; nichts für spielergesteuerte Einheiten (Spieler, Begleiter, Diener)
      Keys.Object(guid, name, karte, zauber) → objectID oder Notschlüssel
      Keys.Source(guid, ctx)         → Beute-Art, ID; ctx = { fishing, corpse = "skin"|"pick"|"herbCorpse"|"mineCorpse",
                                       name, map, spell }; ohne auflösbare Quelle "unknown"; Spieler: nil
      Keys.Fallback(raum, …)         → "~deDE~raum~…~Text" – der einzige Notschlüssel; Keys.IsFallback(k)
      Keys.GatherFallback(art, itemID) → Notschlüssel eines Sammel-Objekts ohne lesbare GUID: Art (herb, mine) plus
                                       Hauptertrag ("~deDE~obj~gather~herb~765"); Keys.GatherOf(k) → art, itemID
      Keys.Area()                    → Notschlüssel der Unterzone oder 0 (Gebiet bei „fishing“ und „unknown“)
      Keys.MapOf(mapID)              → Speicherkarte: die Dungeon-Ebene oder die nächste Elternkarte vom Typ Zone
      Keys.PlayerSpot()              → Speicherkarte, xy (xi*10000 + yi, je 0–9999) – ohne Karte -instanceID bzw. 0
                                       und xy nil
      Keys.Pack(x, y), Keys.Unpack(xy) Position 0–1 ⇄ gepackte Zahl
      Keys.Cell(xy, art)             → Rasterzelle (Objekte 1 %, sonst 2 % der Karte) zum Einrechnen
      Keys.Offer(art, wer, spellID, name, rang) → Lehrer-Art ("c:MAGE", "pet:HUNTER", "p:<Linie>", "o"), Schlüssel
      Keys.OfferKind(art)            → "class" | "pet" | "profession" | "other", Klasse bzw. Linie (zerlegt die Lehrer-Art)
      Keys.ParseFallback(k)          → Sprache, Raum, { Teile … } eines Notschlüssels (der freie Text ist der letzte Teil)
      Keys.OfferName(k)              → Sprache, Name, Rang eines Notschlüssels aus Keys.Offer
      Keys.Instance(instanceID, name) → instanceID oder Notschlüssel
      Keys.Recipe(id | "L:Beruf:Name", beruf, name) → recipeID oder Notschlüssel (Altschlüssel werden umgeschrieben)
      Keys.Taxi(nodeID, name)        → nodeID oder Notschlüssel (Altbestand ezMapDB.flights)
      Keys.Realm()                   → Laufnummer des Realms in ezCoreDB.realms (Namen nur dort)
      Keys.Side()                    → Seite des eigenen Charakters ("A", "H", "N")
      Keys.Market(ablage)            → Laufnummer des Preis-Bereichs (Realm + Seite) im Träger der Preise, Realm-
                                       Laufnummer dort; die Zuordnung steht in ablage.meta.realms/areas (nur Zahlen)
      Keys.MarketArea(ablage, realm, seite) → dasselbe für eine Realm-Laufnummer aus ezCoreDB.realms (Umzug, Trägerwechsel)
      Keys.Variant(link | ItemKey)   → Schlüssel der Abwandlung oder nil, Bestandteile { sfx, il, bon, linkLvl }:
                                       "s<Suffix>", sonst "x<Bonus-IDs>" (eine Form für Link und Auktions-ItemKey)
      Keys.VariantFromOld(alt)       → Schlüssel und Bestandteile aus dem alten Preis-Schlüssel ("1200", "b1,2")
      Keys.Instance8()               → instanceID, Art, difficultyID der Instanz, in der der Spieler steht (draußen nil)
      Keys.Difficulty()              → difficultyID der Instanz, 0 in der offenen Welt
]]

Core.DB = Core.DB or {}
local DB = Core.DB
local Keys = {}
DB.Keys = Keys

local IsSecret, Num, Plain = Core.IsSecret, Core.Num, Core.Plain

local function G(name) return rawget(_G, name) end

-- Arten der Beute-Zählung (drops) und der Fundorte (spot): Schlüsselraum der ID, Zahl der Schlüssel-Ebenen,
-- Entdecker-Wissen (nur mit OPT_explorer gezeigt). Eine neue Art ist ein Eintrag hier, kein Umzug.
Keys.KINDS = {
    loot = { space = "npc", levels = 1, drops = true },
    skin = { space = "npc", levels = 1, drops = true },
    pick = { space = "npc", levels = 1, drops = true },
    herbCorpse = { space = "npc", levels = 1, drops = true },
    mineCorpse = { space = "npc", levels = 1, drops = true },
    object = { space = "obj", levels = 1, drops = true, spot = true },
    container = { space = "item", levels = 1, drops = true },
    fishing = { space = "area", levels = 2, drops = true, spot = true },   -- Fang-Positionen seit Welle 12 (SAM-05)
    unknown = { space = "area", levels = 2, drops = true },
    npc = { space = "npc", levels = 1, spot = true },
    vignette = { space = "vig", levels = 1, spot = true, explorer = true },
    entrance = { space = "instance", levels = 1, spot = true },
    book = { space = "item", levels = 1, spot = true, explorer = true },
}

function Keys.Build()
    local fn = G("GetBuildInfo")
    if type(fn) ~= "function" then return 0 end
    local ok, _, build = pcall(fn)
    if not ok or IsSecret(build) then return 0 end
    return tonumber(build) or 0
end

function Keys.Locale()
    local fn = G("GetLocale")
    local loc = type(fn) == "function" and Plain(fn()) or nil
    return type(loc) == "string" and loc ~= "" and loc or "enUS"
end

-- Kennung einer GUID: Art und, wo die GUID sie trägt, die ID (Feld 6).
function Keys.Guid(guid)
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local kind = guid:match("^(%a+)%-")
    if not kind then return nil end
    if kind == "Player" or kind == "Pet" then return kind, nil end
    if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
        local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        return kind, tonumber(id)
    end
    if kind == "Item" then
        local api = G("C_Item")
        local fn = type(api) == "table" and api.GetItemIDByGUID
        if type(fn) == "function" then
            local ok, id = pcall(fn, guid)
            if ok then return kind, Num(id) end
        end
        return kind, nil
    end
    return kind, nil
end

local function Yes(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and Core.Bool(v, false) == true
end

-- NPC-ID einer Einheit oder GUID. Spielergesteuerte Einheiten liefern nichts: ihr Name (Jägertiere tragen vom
-- Spieler gewählte Namen), Untertitel (Besitzer), Stufe und Ort werden nie gespeichert (Entwurf, Abschnitt 11).
function Keys.Npc(what)
    if IsSecret(what) or type(what) ~= "string" or what == "" then return nil end
    local guid = what
    if not what:find("-", 1, true) then
        local unit = what
        if Yes(G("UnitIsPlayer"), unit) or Yes(G("UnitPlayerControlled"), unit) or Yes(G("UnitIsOtherPlayersPet"), unit) then
            return nil
        end
        local fn = G("UnitGUID")
        if type(fn) ~= "function" then return nil end
        local ok, g = pcall(fn, unit)
        guid = ok and Plain(g) or nil
        if type(guid) ~= "string" then return nil end
    end
    local kind, id = Keys.Guid(guid)
    if (kind == "Creature" or kind == "Vehicle") and id and id > 0 then return id end
    return nil
end

-- Notschlüssel: beginnt immer mit „~“, trägt Sprache und Schlüsselraum, der freie Text steht am Ende. Der
-- senkrechte Strich (Escape-Zeichen des Clients) wird entfernt. Ein gesperrter Teil: kein Schlüssel.
local function FallbackIn(locale, space, ...)
    if type(space) ~= "string" or space == "" or type(locale) ~= "string" or locale == "" then return nil end
    local parts = { "", locale, space }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if IsSecret(v) then return nil end
        if v == nil then v = 0 end
        v = tostring(v):gsub("|", "")
        if v == "" then return nil end
        parts[#parts + 1] = v
    end
    if #parts < 4 then return nil end
    return table.concat(parts, "~")
end

function Keys.Fallback(space, ...) return FallbackIn(Keys.Locale(), space, ...) end
-- Notschlüssel in einer bestimmten Sprache (Übernahme von Altdaten, die je Sprache gespeichert waren)
Keys.FallbackIn = FallbackIn

function Keys.IsFallback(key)
    return type(key) == "string" and key:sub(1, 1) == "~"
end

function Keys.Object(guid, name, map, spell)
    local kind, id = Keys.Guid(guid)
    if kind == "GameObject" and id and id > 0 then return id end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Keys.Fallback("obj", Num(map) or 0, Num(spell) or 0, name)
end

-- SAM-01: Notschlüssel für einen Sammel-Fund ohne lesbare GameObject-GUID (Art plus itemID des Hauptertrags,
-- gekennzeichnet; beim ersten Fund mit GUID führt Discovery ihn zusammen).
function Keys.GatherFallback(kind, itemID)
    if IsSecret(kind) or IsSecret(itemID) or type(kind) ~= "string" or kind == "" then return nil end
    itemID = Num(itemID)
    if not itemID or itemID <= 0 then return nil end
    return Keys.Fallback("obj", "gather", kind, itemID)
end

function Keys.GatherOf(key)
    if not Keys.IsFallback(key) then return nil end
    local kind, id = key:match("^~[^~]+~obj~gather~([^~]+)~(%d+)$")
    return kind, tonumber(id or "")
end

function Keys.Source(guid, ctx)
    ctx = type(ctx) == "table" and ctx or {}
    if ctx.fishing then return "fishing", nil end
    local kind, id = Keys.Guid(guid)
    if kind == "Player" or kind == "Pet" then return nil end
    if (kind == "Creature" or kind == "Vehicle") and id then
        local corpse = ctx.corpse
        if corpse and Keys.KINDS[corpse] and Keys.KINDS[corpse].space == "npc" then return corpse, id end
        return "loot", id
    elseif kind == "GameObject" then
        local oid = Keys.Object(guid, ctx.name, ctx.map, ctx.spell)
        if oid then return "object", oid end
    elseif kind == "Item" and id then
        return "container", id
    end
    return "unknown", nil
end

function Keys.Area()
    local fn = G("GetSubZoneText")
    local text = type(fn) == "function" and Plain(fn()) or nil
    if type(text) == "string" and text ~= "" then return Keys.Fallback("area", text) or 0 end
    return 0
end

-- Speicherkarte zu einer Karte: die Dungeon-Ebene selbst, sonst die nächste Elternkarte vom Typ Zone.
function Keys.MapOf(mapID)
    mapID = Num(mapID)
    if not mapID or mapID <= 0 then return nil end
    local M = Core.Map
    local info = M and M.Info and M.Info(mapID)
    local mapType = type(info) == "table" and Num(info.mapType) or nil
    if mapType == 4 then return mapID end
    local zone = M and M.Parent and M.Parent(mapID, 3)
    return Num(zone) or mapID
end

function Keys.Pack(x, y)
    x, y = Num(x), Num(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    local xi = math.max(0, math.min(9999, math.floor(x * 10000 + 0.5)))
    local yi = math.max(0, math.min(9999, math.floor(y * 10000 + 0.5)))
    return xi * 10000 + yi
end

function Keys.Unpack(xy)
    xy = Num(xy)
    if not xy then return nil end
    local xi = math.floor(xy / 10000)
    return xi / 10000, (xy - xi * 10000) / 10000
end

function Keys.Cell(xy, kind)
    xy = Num(xy)
    if not xy then return nil end
    local step = kind == "object" and 100 or 200
    local xi = math.floor(xy / 10000)
    local yi = xy - xi * 10000
    return math.floor(xi / step) * 1000 + math.floor(yi / step)
end

-- Instanz, in der der Spieler steht: instanceID (Wert 8 von GetInstanceInfo), Art, difficultyID. Draußen: nil.
function Keys.Instance8()
    local fn = G("GetInstanceInfo")
    if type(fn) ~= "function" then return nil end
    local ok, _, instanceType, difficultyID, _, _, _, _, instanceID = pcall(fn)
    instanceType = ok and Plain(instanceType) or nil
    if not instanceType or instanceType == "none" then return nil end
    return Num(instanceID), instanceType, Num(difficultyID) or 0
end

function Keys.Difficulty()
    local _, _, diff = Keys.Instance8()
    return diff or 0
end

function Keys.PlayerSpot()
    local mapID = Core.PlayerPosition and select(1, Core.PlayerPosition()) or nil
    if not mapID then
        local fn = C_Map and C_Map.GetBestMapForUnit
        if type(fn) == "function" then
            local ok, best = pcall(fn, "player")
            mapID = ok and Num(best) or nil
        end
    end
    local store = Keys.MapOf(mapID)
    if not store then
        local inst = Keys.Instance8()
        return inst and -inst or 0, nil
    end
    local _, x, y = Core.PlayerPosition(store)
    return store, Keys.Pack(x, y)
end

local OFFER_KINDS = { class = "c:", pet = "pet:", profession = "p:" }

function Keys.Offer(kind, who, spellID, name, rank)
    local prefix = OFFER_KINDS[kind]
    local art
    if prefix then
        if IsSecret(who) then return nil end
        art = prefix .. tostring(who or 0)
    else
        art = "o"
    end
    spellID = Num(spellID)
    if spellID and spellID > 0 then return art, spellID end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return art, nil end
    return art, Keys.Fallback("spell", art, name .. "#" .. tostring(Num(rank) or 0))
end

local OFFER_PREFIX = { c = "class", pet = "pet", p = "profession" }

function Keys.OfferKind(art)
    if IsSecret(art) or type(art) ~= "string" then return nil end
    if art == "o" then return "other" end
    local prefix, who = art:match("^(%a+):(.+)$")
    local kind = prefix and OFFER_PREFIX[prefix]
    if not kind then return nil end
    if kind == "profession" then return kind, tonumber(who) or 0 end
    return kind, who
end

function Keys.ParseFallback(key)
    if not Keys.IsFallback(key) then return nil end
    local parts = {}
    for part in key:sub(2):gmatch("[^~]+") do parts[#parts + 1] = part end
    if #parts < 3 then return nil end
    local locale, space = table.remove(parts, 1), table.remove(parts, 1)
    return locale, space, parts
end

function Keys.OfferName(key)
    local locale, space, parts = Keys.ParseFallback(key)
    if space ~= "spell" or not parts then return nil end
    local name, rank = parts[#parts]:match("^(.*)#(%-?%d+)$")
    if not name or name == "" then return nil end
    return locale, name, tonumber(rank) or 0
end

function Keys.Instance(instanceID, name)
    instanceID = Num(instanceID)
    if instanceID and instanceID > 0 then return instanceID end
    return Keys.Fallback("instance", name)
end

-- Laufnummer des Realms. Namen stehen nur in ezCoreDB.realms; die Welt-Tabellen tragen nur die Nummer.
function Keys.Realm()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    local id = Num(Core.Call(G("GetRealmID")))
    local native = Num(Core.Call(G("GetNativeRealmID")))
    local fn = G("GetNormalizedRealmName")
    local name = type(fn) == "function" and Plain(fn()) or nil
    if type(name) ~= "string" or name == "" then name = nil end
    if not ((id and id > 0) or name) then return nil end
    db.realms = type(db.realms) == "table" and db.realms or {}
    for n, r in ipairs(db.realms) do
        if type(r) == "table" then
            if id and id > 0 and r.id == id then return n end
            if not (id and id > 0) and name and type(r.names) == "table" then
                for _, known in ipairs(r.names) do if known == name then return n end end
            end
        end
    end
    db.realms[#db.realms + 1] = { id = id, native = native, names = { name } }
    return #db.realms
end

function Keys.Recipe(recipe, prof, name)
    if IsSecret(recipe) or IsSecret(prof) or IsSecret(name) then return nil end
    local id = Num(recipe)
    if id and id > 0 then return id end
    if type(recipe) == "string" then
        if Keys.IsFallback(recipe) then return recipe end
        local p, n = recipe:match("^L:([^:]*):(.+)$")
        if p then prof, name = p, n end
    end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Keys.Fallback("recipe", (type(prof) == "string" and prof ~= "") and prof or 0, name)
end

function Keys.Taxi(nodeID, name)
    if IsSecret(nodeID) then return nil end
    nodeID = Num(nodeID)
    if nodeID and nodeID > 0 then return nodeID end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Keys.Fallback("taxi", name)
end

local SIDES = { Alliance = "A", Horde = "H" }
function Keys.Side()
    local raw = Core.Call(G("UnitFactionGroup"), "player")
    if IsSecret(raw) or type(raw) ~= "string" or raw == "" then return nil end
    return SIDES[raw] or "N"
end

-- Preis-Bereich: Realm + Seite als lokale Laufnummer im Träger der Preise (Entwurf 1.5). Der Realm wird über
-- GetRealmID()/GetNativeRealmID() gefunden (Keys.Realm); ohne Kennung über seine Laufnummer in ezCoreDB.realms (dort
-- stehen die Namen, nie in der Ablage der Preise). Eine spätere Erkenntnis (verbundene Realms, gemeinsames Haus)
-- ändert nur diese Zuordnung, nie die Schlüssel der Preise.
-- Daneben gibt es den Namensschlüssel des Hauses „Realm-Fraktion“ (ezAuctions „Zuletzt“, Einstell-Verlauf, Übernahme des
-- Altspeichers): er entsteht an genau einer Stelle, Core.HouseKey (Names.lua). Legt eine Probe verbundene Realms zu
-- einem Haus zusammen (offen: GetRealmID oder GetNativeRealmID, docs/datenkatalog-client.md), werden diese Zuordnung
-- und Core.HouseKey gemeinsam angepasst (Gesamtreview 18.11.2026, T4-NR7).
function Keys.Market(root)
    if type(root) ~= "table" then root = DB.Market and DB.Market.Root and DB.Market.Root() end
    return Keys.MarketArea(root, Keys.Realm(), Keys.Side())
end

function Keys.MarketArea(root, core, side)
    if type(root) ~= "table" or type(root.meta) ~= "table" then return nil end
    local info = core and Core.db and type(Core.db.realms) == "table" and Core.db.realms[core]
    if not (core and (side == "A" or side == "H" or side == "N") and type(info) == "table") then return nil end
    local m = root.meta
    m.realms = type(m.realms) == "table" and m.realms or {}
    m.areas = type(m.areas) == "table" and m.areas or {}
    local id = Num(info.id)
    if id and id <= 0 then id = nil end
    local rn
    for i, r in ipairs(m.realms) do
        if type(r) == "table" and ((id and Num(r.id) == id) or (not id and not Num(r.id) and r.core == core)) then
            rn = i
            break
        end
    end
    if not rn then
        m.realms[#m.realms + 1] = { id = id, native = Num(info.native), core = core }
        rn = #m.realms
    end
    for i, a in ipairs(m.areas) do
        if type(a) == "table" and a.realm == rn and a.side == side then return i, rn end
    end
    m.areas[#m.areas + 1] = { realm = rn, side = side, pot = #m.areas + 1 }
    return #m.areas, rn
end

-- Abwandlung (Entwurf 1.5 und 2): Link-Felder nach "item:" – 1 itemID, 7 Suffix, 9 Stufe, 13 Anzahl Bonus-IDs, ab 14
-- die Bonus-IDs; ItemKey – itemSuffix, itemLevel. Ein gesperrter Wert: nichts.
function Keys.Variant(item)
    if IsSecret(item) then return nil end
    if type(item) == "table" then
        local sfx, il = item.itemSuffix, item.itemLevel
        if IsSecret(sfx) or IsSecret(il) then return nil end
        sfx, il = Num(sfx), Num(il)
        local parts = { il = (il and il > 0) and il or nil }
        if sfx and sfx ~= 0 then
            parts.sfx = sfx
            return "s" .. sfx, parts
        end
        return nil, parts
    end
    if type(item) ~= "string" then return nil end
    local body = item:match("item:([%-%d:]+)")
    if not body then return nil end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local parts = { linkLvl = tonumber(fields[9] or "") }
    local ids = {}
    local count = tonumber(fields[13] or "")
    for i = 14, 13 + (count or 0) do
        local b = tonumber(fields[i] or "")
        if b then ids[#ids + 1] = b end
    end
    if #ids > 0 then parts.bon = ids end
    local sfx = tonumber(fields[7] or "")
    if sfx and sfx ~= 0 then
        parts.sfx = sfx
        return "s" .. sfx, parts
    end
    if #ids > 0 then return "x" .. table.concat(ids, ","), parts end
    return nil, parts
end

function Keys.VariantFromOld(old)
    if IsSecret(old) or old == nil then return nil end
    old = tostring(old)
    local sfx = tonumber(old)
    if sfx and sfx ~= 0 then return "s" .. sfx, { sfx = sfx } end
    local list = old:match("^b([%d,]+)$")
    if list then
        local ids = {}
        for id in list:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
        if #ids > 0 then return "x" .. table.concat(ids, ","), { bon = ids } end
    end
    return nil
end
