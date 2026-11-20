local _, ns = ...
local Core = ezCore

--[[
    Client-Tabellen im Spiel (Welle 26, Paket kern/wago-wissen; Wunsch des Nutzers vom 16.11.2026, wörtlich im
    ROADMAP-Index: „grundsätzlich allen nützlichen infos von wago direkt nutzen z.b. in db oder validierung“).
    Leser der erzeugten Dateien unter Wissen/Client/ (ns.ClientTables, erzeugt von tools/wago_ausliefern.lua aus den
    DB2-Tabellen des Forever-Clients, wie wago.tools sie für das Produkt wowf ausgibt; Herkunft: docs/wago-tools.md,
    Abschnitt 7). Leitlinie 11: Diese Tabellen sind der Client selbst – sie gehen vor jeder Beobachtung; was der Client
    zur Laufzeit selbst sagt (z. B. maxTrivialLevel am offenen Berufefenster, C_Item.GetItemSpell), geht ihnen vor.
    Jede Angabe nennt ihre Quelle: ClientData.SourceText() → „laut Client-Tabellen (wago.tools, Build …)“.
    Alle Rückgaben sind Kopien; fehlt eine Tabelle (Datei nicht geladen), ist die Antwort nil bzw. leer.

      ClientData.Info(schlüssel)        → { build, date } oder nil (recipes, classSpells, locks, taxi, reagents,
                                          categories, consumables, enchants, spellKinds)
      ClientData.SourceText(schlüssel)  → Quelle als Text (Build der Tabelle, sonst der erste gefundene)
      F2  ClientData.RecipeStages(rezept) → { line, learn, orange, yellow, green, gray, exact = { orange, yellow,
              gray = true }, computed = { green = true }, source = "client" } oder nil – grün ab ist die abgerundete
              Mitte zwischen gelb und grau (gerechnet, darum nicht in exact); orange nur, wenn „lernbar ab“ über 1
              liegt (1 ist auf Forever ein Platzhalter; learn nennt den Rohwert)
      F3  ClientData.ClassSpell(zauber, klasse?) → { id, class, level, base, rank, raceMask, pet, triggered } oder nil
          ClientData.ClassSpells(klasse, abStufe, bisStufe, volk) → { { id, class, level, base, rank, raceMask, pet,
              triggered } … } nach
              Stufe und ID (abStufe ausgeschlossen, bisStufe eingeschlossen; ohne Grenzen alle; volk = Volk-ID: nur
              Zauber dieses Volks, ohne volk alle). Lehrer-Kosten führt der Client nicht.
          Welle 26 (Paket kern/ezcore-reste-24): raceMask = Volksmaske aus SkillLineAbility (0 = alle Völker; Bit =
              ChrRaces.PlayableRaceBit des Volks, ClientData.RACE_BITS – gleich Volk-ID minus 1 nur bei den Völkern 1
              bis 11, 22 und 24 bis 32; etwa Priester-Volkszauber und die Teleporte der Magier je Fraktion);
              ClientData.RaceAllows(eintragOderMaske, volk) → true/false; ClientData.RaceBit(volk) → Bit oder nil;
              ClientData.PlayerRace() → Volk-ID des Spielers (UnitRace, sonst über den Volksnamen; nil, wenn unbekannt)
          Welle 27 (Paket kern/review-454): pet = true für Lernzauber des Begleiters (Feld 5 der Tabelle; beim Jäger etwa
              Klaue, Ducken – der Tierausbilder lehrt sie dem Begleiter, nicht dem Spieler); triggered = true für
              ausgelöste Zauber (Feld 5 = 2; Blitzschlagschild 26364 neben 324 – zählen nicht als Rang, tragen die
              Nummer ihres Geschwisters; Gegenprüfung des Reviews zu PR 454)
          Welle 27 (Paket kern/ausgeloeste-zauber): triggered auch für ausgelöste Zauber mit eigenem Namen – ein anderer
              Zauber nennt sie als ausgelösten (Impact 12355, Frostbite 12494, Clearcasting 12536, Unbridled Wrath 12964)
              oder sie sind eine reine Folge ohne Kosten, Abklingzeit und Zauberzeit (Chilled 12484, Master of Elements
              29077, Pyroclasm 18093, Improved Mend Pet 24406, Lightwell Renew 7001/27873/27874); Regeln im Erzeuger
              (tools/wago_ausliefern.lua, A.Triggered). ClientData.RACE_BITS kommt aus derselben Datei (Feld raceBits)
      F4  ClientData.LockSkill(schloss)  → { { lockType, skillLine, kind, skill } … } oder nil – kind: "lockpicking",
              "herb", "mining", "fishing"; ClientData.ItemLockSkill(gegenstand) → dasselbe über das Schloss des
              Gegenstands (Schließkassetten). Welches Spielobjekt welches Schloss hat, weiß nur der Server.
          Welle 27 (F4 b): ClientData.LockStages(kind) → { Stufe … } aufsteigend, alle Schloss-Stufen einer Art;
              ClientData.LocksAt(kind, stufe) → { Schloss … } mit genau dieser Stufe oder nil (Abgleich der selbst
              erhobenen Fertigkeit in Core.Gathering.Required)
      F5  ClientData.TaxiNode(id) → { id, continent, x, y, alliance, horde } oder nil; ClientData.TaxiNodes(kontinent?,
              fraktion?) → Liste nach ID; ClientData.TaxiPaths(von) → { { to, cost } … }; ClientData.TaxiCost(von, nach)
              → Kupfer der direkten Strecke oder nil
      F9  ClientData.Reagents(zauber) → { { item, count } … } oder nil; ClientData.Tools(zauber) → { categories = { … },
              items = { … } } oder nil
      F10 ClientData.Category(zauber) → Kategorie, Aufladungs-Kategorie (0 = keine) oder nil;
          ClientData.SharedCooldown(zauber) → { Zauber-ID … } derselben Kategorie (ohne den Zauber selbst; leer, wenn
              keiner) ; ClientData.CategoryInfo(kategorie) → { charges, chargeTime (ms) } oder nil
      A75 ClientData.Consumable(gegenstand) → { kind ("flask" | "elixir"), level, spell (Aura über ItemXItemEffect,
              Rückfall über den englischen Namen; 0 = keine Aura) }
          ClientData.Consumables(art?) → { [Gegenstand] = { kind, level, spell } }
          Waffenzauber: ClientData.EnchantOfSpell(zauber) → Verzauberung oder nil; ClientData.EnchantInfo(verzauberung)
              → { duration (Sekunden), charges } oder nil; ClientData.EnchantDuration(zauber) → Sekunden oder nil
      F6  ClientData.ITEM_RUNTIME_FIELDS: die Felder der Entdecker-Datenbank, die C_Item zur Laufzeit liefert (DB.Client) –
          darum werden Gegenstände nicht ausgeliefert (docs/wago-tools.md, Abschnitt 7)
]]

local ClientData = {}
Core.ClientData = ClientData

local Num, Plain = Core.Num, Core.Plain

local L = Core.NewLocale({
    CLIENTDATA_SOURCE = "laut Client-Tabellen (wago.tools, Build %s)",
    CLIENTDATA_SOURCE_COMPUTED = "gerechnet aus den Client-Tabellen (wago.tools, Build %s)",
}, {
    CLIENTDATA_SOURCE = "according to the client tables (wago.tools, build %s)",
    CLIENTDATA_SOURCE_COMPUTED = "computed from the client tables (wago.tools, build %s)",
})
ClientData.L = L

ClientData.KEYS = { "recipes", "classSpells", "locks", "taxi", "reagents", "categories", "consumables", "enchants",
    "spellKinds" }   -- spellKinds seit Welle 27 (Paket kern/ausgeloeste-zauber; Leser ezCore.SpellKinds)
-- Fertigkeitslinie einer Schloss-Art » Art (Linien laut SkillLine: 633 Schlossknacken, 182 Kräuterkunde, 186 Bergbau,
-- 356 Angeln)
ClientData.LOCK_KIND = { [633] = "lockpicking", [182] = "herb", [186] = "mining", [356] = "fishing" }
ClientData.CONSUMABLE_KIND = { [2] = "elixir", [3] = "flask" }
-- F6: Feld der Entdecker-Datenbank » Feld, das DB.Client aus C_Item.GetItemInfo füllt (bzw. die Schnittstelle)
ClientData.ITEM_RUNTIME_FIELDS = { level = "il", quality = "q", bind = "bd", stack = "st", sellPrice = "sp",
    minLevel = "ml", class = "cl", subclass = "sc", spell = "Spells.ItemAura" }

local function Table(key)
    local t = ns.ClientTables and ns.ClientTables[key]
    if type(t) == "table" and type(t.data) == "table" then return t end
    return nil
end
ClientData.Table = function(key) local t = Table(key) return t and t.data or nil end

local function Id(v)
    if Core.IsSecret(v) then return nil end
    return Num(Plain(v))
end

function ClientData.Info(key)
    local t = Table(key)
    if not t then return nil end
    return { build = t.build, date = t.date }
end

function ClientData.Build(key)
    if key then
        local t = Table(key)
        return t and t.build or nil
    end
    for _, k in ipairs(ClientData.KEYS) do
        local t = Table(k)
        if t then return t.build end
    end
    return nil
end

function ClientData.SourceText(key, computed)
    local build = ClientData.Build(key) or "?"
    return (computed and L.CLIENTDATA_SOURCE_COMPUTED or L.CLIENTDATA_SOURCE):format(build)
end

---------------------------------------------------------------------------
-- F2 Farbstufen der Rezepte
---------------------------------------------------------------------------

function ClientData.RecipeStages(recipeID)
    recipeID = Id(recipeID)
    local data = recipeID and ClientData.Table("recipes")
    local e = data and data[recipeID]
    if type(e) ~= "table" then return nil end
    local line, learn, yellow, gray = Num(e[1]), Num(e[2]), Num(e[3]), Num(e[4])
    if not (yellow and gray) then return nil end
    -- „lernbar ab“ (MinSkillLineRank) ist auf Forever bei 2 527 von 2 543 Rezepten 1 – ein Platzhalter, nicht die
    -- Lernstufe (Heiltrank 3447: 1, gelb ab 135). Orange gilt darum nur bei einem Wert über 1; learn bleibt roh.
    local orange = learn and learn > 1 and learn or nil
    local out = { line = line, learn = learn, orange = orange, yellow = yellow, gray = gray, source = "client",
        exact = { orange = orange and true or nil, yellow = true, gray = true } }
    if gray > yellow then
        out.green = math.floor((yellow + gray) / 2)
        out.computed = { green = true }
    end
    return out
end

---------------------------------------------------------------------------
-- F3 Klassenzauber
---------------------------------------------------------------------------

local function PlayerClass()
    local ok, _, token = pcall(UnitClass, "player")
    if ok and not Core.IsSecret(token) and type(token) == "string" then return token end
    return nil
end

local function SpellEntry(class, id, e)
    return { id = id, class = class, level = Num(e[1]) or 0, base = Num(e[2]) or id, rank = Num(e[3]) or 0,
        raceMask = Num(e[4]) or 0, pet = Num(e[5]) == 1 or nil, triggered = Num(e[5]) == 2 or nil }
end

-- Volk-IDs laut ChrRaces nach dem Volksnamen von UnitRace (Rückfall, falls UnitRace die ID nicht mitgibt)
ClientData.RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6, Gnome = 7,
    Troll = 8, Goblin = 9, BloodElf = 10, Draenei = 11 }

function ClientData.PlayerRace()
    local ok, _, file, id = pcall(UnitRace, "player")
    if not ok then return nil end
    if not Core.IsSecret(id) and Num(id) and Num(id) > 0 then return Num(id) end
    if not Core.IsSecret(file) and type(file) == "string" then return ClientData.RACE_IDS[file] end
    return nil
end

-- Bit eines Volks in den Volksmasken (RaceMask) laut ChrRaces.PlayableRaceBit (wago.tools, Produkt wowf, Build
-- 1.60.1.70938; tools/daten/wago/klassen.lua, Feld bit – ezCore/Tests/review454_test.lua gleicht ab). Nur bei den
-- klassischen Völkern 1 bis 11 (und 22, 24 bis 32) ist es Volk-ID minus 1; Dunkeleisenzwerge bis Mechagnome, Dracthyr,
-- Irdene, Haranir und die Himmelsgeborenen weichen ab (Bit 32 und 33 passen in keine 32-Bit-Maske der Tabelle: eine
-- Maske, die Völker ausschließt, schließt sie mit aus). Völker ohne spielbares Bit fehlen (Welle 27, Paket
-- kern/review-454, Fund 6 des Reviews).
-- Welle 27 (Paket kern/ausgeloeste-zauber, Fund c des Reviews vor dem Merge von kern/review-454; Leitlinie 10): erzeugt
-- statt Handliste – tools/wago_ausliefern.lua (A.RaceBits) schreibt die Bits aus klassen.lua (races[ID].bit) neben die
-- Klassenzauber (Wissen/Client/ClassSpells.lua, Feld raceBits). Fehlt die Tabelle, ist die Liste leer: dann gelten alle
-- Zauber für jedes Volk (ClientData.RaceAllows).
ClientData.RACE_BITS = {}
do
    local t = ns.ClientTables and ns.ClientTables.classSpells
    for race, b in pairs(type(t) == "table" and type(t.raceBits) == "table" and t.raceBits or {}) do
        if Num(race) and Num(b) then ClientData.RACE_BITS[Num(race)] = Num(b) end
    end
end

function ClientData.RaceBit(race)
    race = Num(race)
    return race and ClientData.RACE_BITS[race] or nil
end

-- Gilt ein Eintrag (oder eine Volksmaske) für dieses Volk? Ohne Maske (0, -1) bzw. ohne bekanntes Volk (oder ohne
-- spielbares Bit): ja.
function ClientData.RaceAllows(entryOrMask, race)
    local mask = type(entryOrMask) == "table" and entryOrMask.raceMask or entryOrMask
    mask = Num(mask)
    local bitPos = ClientData.RaceBit(race)
    if not mask or mask == 0 or mask == -1 or not bitPos then return true end
    if mask < 0 then mask = mask + 4294967296 end   -- vorzeichenbehaftet aus der Tabelle: als 32 Bit lesen
    return math.floor(mask / 2 ^ bitPos) % 2 == 1   -- ohne bit-Bibliothek (Tests ohne bit)
end

function ClientData.ClassSpell(spellID, class)
    spellID = Id(spellID)
    local data = spellID and ClientData.Table("classSpells")
    if not data then return nil end
    if class then
        local e = type(data[class]) == "table" and data[class][spellID]
        return e and SpellEntry(class, spellID, e) or nil
    end
    for _, token in ipairs(Core.SortedKeys and Core.SortedKeys(data) or {}) do
        local e = type(data[token]) == "table" and data[token][spellID]
        if e then return SpellEntry(token, spellID, e) end
    end
    return nil
end

function ClientData.ClassSpells(class, fromLevel, toLevel, race)
    class = class or PlayerClass()
    local data = ClientData.Table("classSpells")
    local list = {}
    local spells = data and class and data[class]
    if type(spells) ~= "table" then return list end
    fromLevel, toLevel = Num(fromLevel), Num(toLevel)
    for id, e in pairs(spells) do
        local level = Num(e[1]) or 0
        if (not fromLevel or level > fromLevel) and (not toLevel or level <= toLevel)
            and (race == nil or ClientData.RaceAllows(Num(e[4]), race)) then
            list[#list + 1] = SpellEntry(class, id, e)
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.id < b.id
    end)
    return list
end

---------------------------------------------------------------------------
-- F4 Schlösser
---------------------------------------------------------------------------

function ClientData.LockSkill(lockID)
    lockID = Id(lockID)
    local data = lockID and ClientData.Table("locks")
    local list = data and type(data.locks) == "table" and data.locks[lockID]
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(list) do
        local lockType = Num(e[1])
        local line = lockType and type(data.types) == "table" and Num(data.types[lockType])
        if line then
            out[#out + 1] = { lockType = lockType, skillLine = line, kind = ClientData.LOCK_KIND[line], skill = Num(e[2]) or 0 }
        end
    end
    return #out > 0 and out or nil
end

function ClientData.ItemLockSkill(itemID)
    itemID = Id(itemID)
    local data = itemID and ClientData.Table("locks")
    local lockID = data and type(data.items) == "table" and data.items[itemID]
    return lockID and ClientData.LockSkill(lockID) or nil
end

-- Welle 27 (Paket kern/sammel-fertigkeit, F4 b): alle Schloss-Stufen einer Art und die Schlösser je Stufe. Ein
-- Spielobjekt verlangt immer eine dieser Stufen (sein Schloss steht in der Tabelle) – damit grenzt Core.Gathering.Required
-- die eigene Beobachtung ein. Arbeitsspeicher je Art, einmal gebaut.
local stagesOf = {}
local function StagesOf(kind)
    local hit = stagesOf[kind]
    if hit then return hit end
    hit = { list = {}, locks = {} }
    local data = ClientData.Table("locks")
    local types = data and type(data.types) == "table" and data.types or {}
    for lockID, list in pairs(data and type(data.locks) == "table" and data.locks or {}) do
        for _, e in ipairs(type(list) == "table" and list or {}) do
            local line = Num(e[1]) and Num(types[Num(e[1])])
            local skill = Num(e[2])
            if line and skill and ClientData.LOCK_KIND[line] == kind then
                if not hit.locks[skill] then
                    hit.locks[skill] = {}
                    hit.list[#hit.list + 1] = skill
                end
                table.insert(hit.locks[skill], lockID)
            end
        end
    end
    table.sort(hit.list)
    for _, ids in pairs(hit.locks) do table.sort(ids) end
    if data then stagesOf[kind] = hit end
    return hit
end

-- → { Stufe … } aufsteigend (Kopie) für kind = "lockpicking" | "herb" | "mining" | "fishing"; leer ohne Tabelle
function ClientData.LockStages(kind)
    local out = {}
    for i, v in ipairs(StagesOf(kind).list) do out[i] = v end
    return out
end

-- → { Schloss … } aufsteigend (Kopie) mit genau dieser Stufe, oder nil
function ClientData.LocksAt(kind, skill)
    skill = Num(skill)
    local ids = skill and StagesOf(kind).locks[skill]
    if not ids then return nil end
    local out = {}
    for i, v in ipairs(ids) do out[i] = v end
    return out
end

---------------------------------------------------------------------------
-- F5 Flugpunkte
---------------------------------------------------------------------------

local function Node(id, n)
    return { id = id, continent = Num(n[1]), x = Num(n[2]), y = Num(n[3]), alliance = n[4] == 1, horde = n[5] == 1 }
end

function ClientData.TaxiNode(id)
    id = Id(id)
    local data = id and ClientData.Table("taxi")
    local n = data and type(data.nodes) == "table" and data.nodes[id]
    return type(n) == "table" and Node(id, n) or nil
end

-- fraktion: "Alliance" | "Horde" | nil (beide)
function ClientData.TaxiNodes(continent, faction)
    local data = ClientData.Table("taxi")
    local list = {}
    continent = Num(continent)
    for id, n in pairs(data and data.nodes or {}) do
        local node = Node(id, n)
        if (not continent or node.continent == continent)
            and (faction == nil or (faction == "Alliance" and node.alliance) or (faction == "Horde" and node.horde)) then
            list[#list + 1] = node
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function ClientData.TaxiPaths(from)
    from = Id(from)
    local data = from and ClientData.Table("taxi")
    local list = {}
    for _, p in ipairs(data and data.paths or {}) do
        if p[1] == from then list[#list + 1] = { to = p[2], cost = Num(p[3]) or 0 } end
    end
    return list
end

function ClientData.TaxiCost(from, to)
    to = Id(to)
    for _, p in ipairs(ClientData.TaxiPaths(from)) do
        if p.to == to then return p.cost end
    end
    return nil
end

---------------------------------------------------------------------------
-- F9 Reagenzien, F10 Kategorien
---------------------------------------------------------------------------

function ClientData.Reagents(spellID)
    spellID = Id(spellID)
    local data = spellID and ClientData.Table("reagents")
    local list = data and type(data.reagents) == "table" and data.reagents[spellID]
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, e in ipairs(list) do out[i] = { item = Num(e[1]), count = Num(e[2]) or 1 } end
    return out
end

function ClientData.Tools(spellID)
    spellID = Id(spellID)
    local data = spellID and ClientData.Table("reagents")
    local list = data and type(data.tools) == "table" and data.tools[spellID]
    if type(list) ~= "table" then return nil end
    local out = { categories = {}, items = {} }
    for _, e in ipairs(list) do
        if e[1] == 1 then out.categories[#out.categories + 1] = Num(e[2])
        elseif e[1] == 2 then out.items[#out.items + 1] = Num(e[2]) end
    end
    return out
end

function ClientData.Category(spellID)
    spellID = Id(spellID)
    local data = spellID and ClientData.Table("categories")
    local e = data and type(data.spells) == "table" and data.spells[spellID]
    if type(e) ~= "table" then return nil end
    return Num(e[1]) or 0, Num(e[2]) or 0
end

function ClientData.SharedCooldown(spellID)
    spellID = Id(spellID)
    local cat = spellID and ClientData.Category(spellID)
    local list = {}
    if not cat or cat == 0 then return list end
    for id, e in pairs(ClientData.Table("categories").spells) do
        if id ~= spellID and e[1] == cat then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

function ClientData.CategoryInfo(category)
    category = Id(category)
    local data = category and ClientData.Table("categories")
    local e = data and type(data.categories) == "table" and data.categories[category]
    if type(e) ~= "table" then return nil end
    return { charges = Num(e[1]) or 0, chargeTime = Num(e[2]) or 0 }
end

---------------------------------------------------------------------------
-- A75 Fläschchen und Elixiere, Waffenzauber
---------------------------------------------------------------------------

local function Consumable(e)
    return { kind = ClientData.CONSUMABLE_KIND[e[1]], level = Num(e[2]) or 0, spell = Num(e[3]) or 0 }
end

function ClientData.Consumable(itemID)
    itemID = Id(itemID)
    local data = itemID and ClientData.Table("consumables")
    local e = data and data[itemID]
    return type(e) == "table" and Consumable(e) or nil
end

function ClientData.Consumables(kind)
    local out = {}
    for id, e in pairs(ClientData.Table("consumables") or {}) do
        local c = Consumable(e)
        if c.kind and (kind == nil or c.kind == kind) then out[id] = c end
    end
    return out
end

function ClientData.EnchantOfSpell(spellID)
    spellID = Id(spellID)
    local data = spellID and ClientData.Table("enchants")
    return data and type(data.spells) == "table" and Num(data.spells[spellID]) or nil
end

function ClientData.EnchantInfo(enchantID)
    enchantID = Id(enchantID)
    local data = enchantID and ClientData.Table("enchants")
    local e = data and type(data.enchants) == "table" and data.enchants[enchantID]
    if type(e) ~= "table" then return nil end
    return { duration = Num(e[1]) or 0, charges = Num(e[2]) or 0 }
end

function ClientData.EnchantDuration(spellID)
    local info = ClientData.EnchantInfo(ClientData.EnchantOfSpell(spellID))
    return info and info.duration > 0 and info.duration or nil
end
