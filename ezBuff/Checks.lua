local _, ns = ...
local L = ns.L
local Core = ezCore
local Buffs = ns.Buffs
local Spells = Core.Spells
local Value = ns.Value

--[[
    Was fehlt? Baut außerhalb des Kampfes eine Aufgabenliste, wichtigstes zuerst:
      rebuff    jemand hat dich gebufft: zurückgeben und danken (Rebuff.lua)
      self      eigener Klassen-Buff fehlt auf dir
      flask     Fläschchen oder Elixier fehlt
      food      Buff-Essen („Satt“) fehlt
      weapon    Waffenverzauberung (Gift, Wetzstein, Öl) fehlt auf einer Hand (Weapon.lua; Schalter ab Werk an)
      group     eigener Klassen-Buff fehlt auf einem Gruppenmitglied
      campfire  Lagerfeuer-Buff fehlt
      other     Buff einer anderen Klasse aus der Gruppe fehlt (nur Meldung)
    Aufgabe: { kind, key, label, icon, action = { type = "item"|"spell", item, spell, unit } oder nil, … }
    Eigene Klassen-Buffs (self, group) nennen in buffKeys ihre Buff-Gruppen: damit leuchten die Aktionsknöpfe
    jedes Rangs (ActionGlow.lua).
    Gegenstände wählt das Item-Wissen aus (ezCore.Knowledge: Buff-Essen, Fläschchen, „gut für <Klasse>“).
]]

local Check = {}
ns.Check = Check

local tasks = {}
local ORDER = { rebuff = 1, self = 2, flask = 3, food = 4, weapon = 4.5, group = 5, campfire = 6, other = 7 }
Check.ORDER = ORDER

function Check.Tasks() return tasks end

-- Erste Aufgabe, die der Knopf ausführen kann (sonst die erste überhaupt).
function Check.First()
    for _, task in ipairs(tasks) do
        if task.action or task.thankOnly then return task end
    end
    return tasks[1]
end

---------------------------------------------------------------------------
-- Gegenstände aus der Tasche (Item-Wissen)
---------------------------------------------------------------------------

local FOOD_KINDS = { food = true, drink = true, foodDrink = true }

-- Wertung: zuerst „gut für meine Klasse“, dann Fläschchen vor Elixier, dann höhere Stufe.
local function Score(f, c, class)
    local score = (f.minLevel or 0)
    if c.goodFor and not f.goodForAll and c.goodFor[class] then score = score + 1000 end
    if c.kind == "flask" then score = score + 500 end
    return score
end

-- Zauber der Aura eines Fläschchens, Elixiers oder einer Waffenverzauberung: zuerst, was das Item-Wissen schon
-- gelesen hat (consumable.auraSpell bzw. useSpellID), sonst ezCore direkt aus dem Client (Spells.ItemAura über
-- C_Item.GetItemSpell; BF-10). nil ohne Antwort.
function Check.AuraSpell(itemID, f)
    local c = type(f) == "table" and f.consumable
    local spell = ns.Num(type(c) == "table" and c.auraSpell) or ns.Num(type(f) == "table" and f.useSpellID)
    if spell then return spell end
    if not Spells.ItemAura then return nil end
    return ns.Num((Core.Call(Spells.ItemAura, itemID)))
end

-- Tasche einmal ganz durchlaufen: bestes Buff-Essen, bestes Fläschchen/Elixier und beste Waffenverzauberung
-- (BF-17: Gift, Wetzstein, Öl – Art „weaponEnchant“ im Item-Wissen), { food = …, flask = …, weapon = … } mit
-- { itemID, name, icon, kind }. Zweiter Wert: der Durchlauf lief ohne Fehler bis zum Ende (nur dann darf das
-- Ergebnis gemerkt werden).
function Check.ScanBags(class)
    local K = Core.Knowledge
    local best = {}
    if not (K and K.Get and Core.ForEachBagItem) then return best, false end
    local scores = {}
    local function Offer(slotKind, itemID, f, c)
        local score = Score(f, c, class)
        if not scores[slotKind] or score > scores[slotKind] then
            scores[slotKind] = score
            best[slotKind] = { itemID = itemID, name = f.name, icon = Core.ItemIcon(itemID), kind = c.kind }
        end
    end
    -- „carried“ (EC-50, V-175): alles, was du bei dir trägst – auch die Reagenzientasche; Buff-Essen und Fläschchen
    -- lassen sich von dort benutzen.
    -- Eigener Code unter ns.Try statt nacktem pcall (Gesamtreview 18.11.2026, T7-1): Ein Fehler im Rückruf steht in
    -- ezCores Fehlerliste, statt bei jedem UNIT_AURA still eine halbe Liste zu liefern.
    local complete = ns.Try("ScanBags", Core.ForEachBagItem, function(_, _, info)
        local itemID = ns.Num(info and info.itemID)
        if not itemID then return end
        local f = K.Get(itemID)
        local c = f and f.consumable
        if not c or f.usableNow == false then return end
        if c.goodFor and class and not c.goodFor[class] then return end
        if c.kind == "flask" or c.kind == "elixir" then
            local spell = Check.AuraSpell(itemID, f)
            if spell then
                Buffs.RememberElixir(spell, c.kind)
                Offer("flask", itemID, f, c)
            end
        elseif c.kind == "weaponEnchant" then
            Offer("weapon", itemID, f, c)
        elseif c.wellFed and FOOD_KINDS[c.kind] then
            Offer("food", itemID, f, c)
        end
    end, "carried")
    return best, complete
end

-- Zwischenspeicher (V-146): Jedes UNIT_AURA der Gruppe stößt eine Prüfung an – die Tasche wird dafür nicht jedes
-- Mal durchlaufen, sondern nur, wenn sich ihr Inhalt oder das Wissen darüber geändert haben kann
-- (Check.ForgetBags: BAG_UPDATE_DELAYED, neues Item-Wissen – nachgeladener Gegenstand, Stufe, Berufe –,
-- Stufenaufstieg, Betreten der Welt). Gemerkt je Klasse („gut für <Klasse>“).
local bagItems, bagClass
function Check.ForgetBags() bagItems, bagClass = nil, nil end

-- Bestes Buff-Essen und bestes Fläschchen/Elixier in der Tasche (aus dem Zwischenspeicher, sonst frisch gelesen):
-- { food = …, flask = … } mit { itemID, name, icon, kind }. Nur lesen – die Tabelle ist die gemerkte.
function Check.BagItems(class)
    if bagItems and bagClass == class then return bagItems end
    local best, complete = Check.ScanBags(class)
    if complete then bagItems, bagClass = best, class end
    return best
end

---------------------------------------------------------------------------
-- Fläschchen und Elixiere anderer Spieler (BF-10): Welche Aura ein Fläschchen ist, weiß ezBuff nur über den
-- Gegenstand dazu. Die eigene Sammlung (ezBuffDB.elixirs, aus der Tasche) bleibt; dazu kommt alles, was ezCores
-- Inventar bei irgendeinem deiner Charaktere kennt (Taschen, Bank, Post, angelegt, gemerkte Gildenbank –
-- Core.Inventory.OwnedSet): Verbrauchsgut laut Client (Core.ItemClass, Nummer aus Core.ITEM_CLASS), Elixier bzw.
-- Fläschchen laut ezCores Item-Wissen (consumable.kind – dieselbe Zuordnung der Unterarten wie in der Tasche, keine
-- zweite Tabelle hier), Aura aus dem Client (Spells.ItemAura). Seit dem Paket modul/ezbuff-reagenzien kommt die Liste
-- aller Fläschchen und Elixiere aus ezCores Client-Wissen dazu (Spells.ElixirItems, Check.LearnClientElixirs) – auch
-- Tränke, die keiner deiner Charaktere je besaß. Das Zeichen „kein bekanntes Fläschchen“ zeigt weiter nur in Dungeon
-- und Schlachtzug (ob auch draußen: docs/roadmap/ezBuff.md, „Offen“).
---------------------------------------------------------------------------

local ELIXIR_KINDS = { flask = true, elixir = true }
local learnedItems = {}     -- [itemID] = true: schon ausgewertet (je Sitzung; ohne Antwort des Clients nicht)
local clientItems = {}      -- [itemID] = true: aus ezCores Liste schon gemerkt (je Sitzung; Check.LearnClientElixirs)

-- Trank-Art eines Gegenstands aus dem Besitz: "flask" | "elixir", false (kein Fläschchen und kein Elixier – nie
-- wieder fragen) oder nil (der Client kennt ihn noch nicht – beim nächsten Lauf). Zweiter Wert: das Item-Wissen.
function Check.ElixirKind(itemID)
    local classID = Core.ItemClass(itemID)
    if classID == nil then return nil end
    if classID ~= ((Core.ITEM_CLASS or {}).Consumable or 0) then return false end
    local K = Core.Knowledge
    local f = K and type(K.Get) == "function" and K.Get(itemID) or nil
    if type(f) ~= "table" then return nil end
    local kind = type(f.consumable) == "table" and f.consumable.kind or nil
    if ELIXIR_KINDS[kind] then return kind, f end
    return false
end

-- Alle Fläschchen und Elixiere aus ezCores Client-Wissen merken (A5; Spells.ElixirItems – Liste aus den
-- Client-Tabellen, ezCore A75; Paket modul/ezbuff-reagenzien): auch Tränke, die keiner deiner Charaktere je besaß.
-- Die Aura nennt zuerst der Client zur Laufzeit (Spells.ItemAura), sonst die Tabelle. Nennt die Tabelle 0 (laut
-- ItemXItemEffect keine Aura: Trank der Giftreinigung, Noggenfogger-Elixier), bleibt der Gegenstand außen vor – auch
-- wenn der Client den Zauber beim Benutzen nennt, denn der liegt nie als Aura auf einer Einheit. Ohne Antwort und ohne
-- Aura in der Tabelle ebenso. → Anzahl neu gelernter Auren.
function Check.LearnClientElixirs()
    local list = ns.db and Spells.ElixirItems and Core.Call(Spells.ElixirItems)
    if type(list) ~= "table" then return 0 end
    local added = 0
    for itemID, e in pairs(list) do
        itemID = ns.Num(itemID)
        if itemID and not clientItems[itemID] and type(e) == "table" and ELIXIR_KINDS[e.kind] and ns.Num(e.spell) ~= 0 then
            local spell = Spells.ItemAura and ns.Num((Core.Call(Spells.ItemAura, itemID))) or nil
            if not spell or spell <= 0 then spell = ns.Num(e.spell) end
            if spell and spell > 0 then
                clientItems[itemID] = true
                if ns.db.elixirs[spell] == nil then added = added + 1 end
                Buffs.RememberElixir(spell, e.kind)
            end
        end
    end
    return added
end

-- Fläschchen und Elixiere aus dem Besitz aller Charaktere merken, danach die Liste aus ezCores Client-Wissen
-- (Check.LearnClientElixirs) → Anzahl neu gelernter Auren.
function Check.LearnElixirs()
    local Inv = Core.Inventory
    if not (Inv and type(Inv.OwnedSet) == "function" and ns.db) then return Check.LearnClientElixirs() end
    local ok, owned = Core.Try("ezBuff", "LearnElixirs", Inv.OwnedSet)   -- T7-1: Fehler in die Fehlerliste
    if not ok or type(owned) ~= "table" then return Check.LearnClientElixirs() end
    local added = 0
    for itemID in pairs(owned) do
        itemID = ns.Num(itemID)
        if itemID and not learnedItems[itemID] then
            local kind, f = Check.ElixirKind(itemID)
            if kind == false then
                learnedItems[itemID] = true            -- kein Trank: nie wieder fragen
            elseif kind then
                local spell = Check.AuraSpell(itemID, f)
                if spell then
                    learnedItems[itemID] = true
                    if ns.db.elixirs[spell] == nil then added = added + 1 end
                    Buffs.RememberElixir(spell, kind)
                end
            end
        end
    end
    return added + Check.LearnClientElixirs()
end

-- Wie viele Fläschchen- und Elixier-Auren kennt ezBuff? (Tooltip des Zeichens, /ezbuff status)
function Check.KnownElixirs()
    local n = 0
    for _ in pairs(ns.db and ns.db.elixirs or {}) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Gruppe
---------------------------------------------------------------------------

function Check.GroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for index = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. index end
    elseif ns.InGroup() then
        for index = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do units[#units + 1] = "party" .. index end
    end
    return units
end

-- Einheit, die man jetzt buffen könnte: { unit, name, class, level } oder nil.
local function Member(unit)
    if not Value(UnitExists, unit) or Value(UnitIsUnit, unit, "player") then return nil end
    if Value(UnitIsConnected, unit) == false or Value(UnitIsDeadOrGhost, unit) then return nil end
    local name = ns.UnitFullName(unit)
    local _, class = UnitClass(unit)
    class = ns.Plain(class)
    if type(name) ~= "string" or type(class) ~= "string" then return nil end
    return { unit = unit, name = name, class = class, level = ns.Num(UnitLevel(unit)),
        visible = Value(UnitIsVisible, unit) ~= false }
end
Check.Member = Member

-- In Reichweite? Über ezCore (Spells.InRange: true/false/nil); ohne C_Spell die alte Abfrage des Clients.
local function InRange(spellID, unit)
    local inRange
    if Spells.InRange and C_Spell and C_Spell.IsSpellInRange then
        inRange = Core.Call(Spells.InRange, spellID, unit)
    elseif IsSpellInRange then
        inRange = Value(IsSpellInRange, spellID, unit)
    end
    if inRange == nil then return true end   -- unbekannt: dem Spiel beim Klick überlassen
    return inRange == true or inRange == 1
end
Check.InRange = InRange

---------------------------------------------------------------------------
-- Klassen-Buffs: Gruppen mit gleichem kind (Segen, Rüstungen) zählen als eine Wahl
---------------------------------------------------------------------------

-- Wahlgruppe eines Eintrags: id aus ezCore (Spells.BuffGroup – kind bzw. Schlüssel), sonst wie bisher.
local function GroupID(entry, class)
    local known = Spells.BuffGroup and Core.Call(Spells.BuffGroup, entry.key, class)
    if type(known) == "table" and type(known.id) == "string" then return known.id end
    return entry.kind or entry.key
end

-- Buffs einer Klasse, zusammengefasst: { { id, entries = {…}, target } }. Für die eigene Klasse kommen die
-- eingeschalteten langen Selbst-Buffs dazu (Buffs.LongSelfBuffs, T14-2; group.long, group.pet).
local function Groups(class)
    local groups, byId = {}, {}
    local function Add(entry)
        if type(entry) ~= "table" or not entry.key then return end
        local id = GroupID(entry, class)
        local group = byId[id]
        if not group then
            group = { id = id, kind = entry.kind, entries = {}, target = entry.target or "any" }
            byId[id] = group
            groups[#groups + 1] = group
        end
        table.insert(group.entries, entry)
        if entry.target == "self" then group.target = "self" end
        if entry.long then group.long = true end
        if entry.pet then group.pet = true end
    end
    for _, entry in ipairs(Buffs.ClassBuffs(class)) do Add(entry) end
    if class ~= nil and class == ns.playerClass then
        for _, entry in ipairs(Buffs.LongSelfBuffs(class)) do Add(entry) end
    end
    return groups
end
Check.Groups = Groups

-- Lässt sich die Gruppe gerade wirken? Ein Buff, der einen Begleiter braucht (Seelenverbindung), nur mit lebendem
-- Begleiter – sonst mahnt ezBuff ihn nicht an.
local function Castable(group)
    return not group.pet or Buffs.PetReady()
end
Check.Castable = Castable

local function GroupHas(auras, group, minLeft)
    for _, entry in ipairs(group.entries) do
        local has, aura = Buffs.Has(auras, entry.key, minLeft)
        if has then return true, aura end
    end
    return false
end

-- Alte Wahl: zuletzt selbst gewirkt (ns.CharDB().prefer), sonst der erste gelernte Eintrag.
-- Rückfall für Gruppen, die ezCores Klassen-Wissen nicht kennt, und für Wahlgruppen in FIRST_LEARNED.
local function ChooseFirst(group, level)
    local prefer = ns.CharDB().prefer[group.id]
    if prefer then
        for _, entry in ipairs(group.entries) do
            if entry.key == prefer then
                local spell = Buffs.BestRank(entry.key, level)
                if spell then return entry, spell end
            end
        end
    end
    for _, entry in ipairs(group.entries) do
        local spell = Buffs.BestRank(entry.key, level)
        if spell then return entry, spell end
    end
    return nil
end
Check.ChooseFirst = ChooseFirst

-- Wahlgruppen, die beim ersten gelernten Eintrag bleiben sollen (ChooseFirst statt Spells.ChooseBuff). Leer: Die Segen
-- laufen seit der Entscheidung des Nutzers vom 13.11.2026 („Alle nach Empfehlung“) über ezCore – Macht bis Stufe 20,
-- ab Segen der Könige dieser, Weisheit & Co. nur als gemerkte Wahl (Spells.BUFFS[…].manual); die gemerkte Wahl gewinnt.
Check.FIRST_LEARNED = {}

-- Vorschlag ohne gemerkte Wahl, je kind: Segen der Könige, sobald gelernt (sonst entscheidet ezCore wie immer).
-- Seit ezCore die Segen selbst so wählt (manual), deckt sich der Vorschlag mit Spells.ChooseBuff; er bleibt als
-- Absicherung für einen ezCore-Stand ohne manual (ROADMAP ezBuff: „DEFAULT_PREFER doppelt?“).
Check.DEFAULT_PREFER = { blessing = "kings" }

-- Gewählter Buff der Gruppe: der beste gelernte aus ezCores Klassen-Wissen (Spells.ChooseBuff).
-- Ein abgelöster Buff (Dämonenhaut nach gelernter Dämonenrüstung, Frostrüstung nach Eisrüstung) wird nie
-- vorgeschlagen, auch nicht als gemerkte Wahl; unter den übrigen gewinnt die gemerkte Wahl
-- (ns.CharDB().prefer), dann der Vorschlag aus DEFAULT_PREFER, sonst der letzte gelernte Eintrag der Gruppe.
local function Choose(group, level)
    if type(group) ~= "table" then return nil end
    if not (group.kind and Check.FIRST_LEARNED[group.kind]) and Spells.ChooseBuff then
        local chosen = ns.CharDB().prefer[group.id]
        local suggested = not chosen and group.kind and Check.DEFAULT_PREFER[group.kind] or nil
        local key, spell = Core.Call(Spells.ChooseBuff, group.id,
            { class = ns.playerClass, level = level, prefer = chosen or suggested })
        spell = ns.Num(spell)
        -- Vorschlag noch nicht gelernt (Segen vor Stufe 20): wie bisher der erste gelernte Eintrag
        if suggested and key ~= suggested then return ChooseFirst(group, level) end
        if type(key) == "string" and spell then
            for _, entry in ipairs(group.entries) do
                if entry.key == key then return entry, spell end
            end
        end
    end
    return ChooseFirst(group, level)
end
Check.Choose = Choose

-- Buff-Gruppen einer Wahl (Segen, Rüstungen: jede zählt) bzw. eines einzelnen Buffs.
local function KeysOf(group)
    local keys = {}
    for _, entry in ipairs(group.entries) do keys[#keys + 1] = entry.key end
    return keys
end
Check.KeysOf = KeysOf

-- Wie eine Gruppe im Text heißt. Eine Wahl (Segen, Rüstung, Schild) heißt nach ihrer Art; steht fest, welcher
-- Zauber gemeint ist (spell: der beste gelernte Rang aus Check.Choose), kommt sein Name dazu:
-- „Rüstung (Dämonenhaut)“. Nennt der Name die Art schon selbst, steht er allein („Dämonenrüstung“,
-- „Segen der Macht“ – nicht „Segen (Segen der Macht)“). Ohne spell (Buff einer anderen Klasse – deren Wahl
-- kennt ezBuff nicht) nur die Art.
local function GroupLabel(group, entry, spell)
    local kind = group.kind and L["KIND_" .. group.kind]
    if not kind then return Buffs.Name(entry or group.entries[1]) end
    local name = spell and entry and Buffs.Name(entry, spell)
    if type(name) == "string" and name ~= "" and name ~= "?" then
        -- Vergleich ohne Groß-/Kleinschreibung: „Wasserschild“ enthält „Schild“ (Umlaute bleiben Byte für Byte gleich)
        if name:lower():find(kind:lower(), 1, true) then return name end
        return L.WHAT_KIND:format(kind, name)
    end
    return kind
end
Check.GroupLabel = GroupLabel

-- Wahl der Gruppe ohne gemerkte Wahl: was Check.Choose vorschlüge, hätte der Spieler nie selbst etwas gewirkt.
local function DefaultKey(group)
    if group.imbue then return ns.Weapon and ns.Weapon.DefaultImbue() or nil end   -- Waffenzauber (Weapon.lua)
    if not (group.kind and Check.FIRST_LEARNED[group.kind]) and Spells.ChooseBuff then
        local key = Core.Call(Spells.ChooseBuff, group.id, { class = ns.playerClass })
        if type(key) == "string" then return key end
    end
    for _, entry in ipairs(group.entries) do
        if Buffs.BestRank(entry.key) then return entry.key end
    end
    return nil
end
Check.DefaultKey = DefaultKey

-- Ziel eines eigenen Zaubers: UNIT_SPELLCAST_SENT nennt den Namen des Ziels, UNIT_SPELLCAST_SUCCEEDED nicht.
-- Gemerkt wird nur der letzte gesendete Zauber (castGUID, Name) – SENT und SUCCEEDED folgen direkt aufeinander.
local lastSent
function Check.NoteSent(castGUID, target)
    if ns.IsSecret(castGUID) or castGUID == nil then lastSent = nil return end
    lastSent = { guid = castGUID, target = (not ns.IsSecret(target) and type(target) == "string") and target or nil }
end

-- Name des Ziels zum Zauber castGUID (nil: unbekannt, gesperrt oder ein anderer Zauber).
function Check.SentTarget(castGUID)
    if ns.IsSecret(castGUID) or castGUID == nil or not lastSent or lastSent.guid ~= castGUID then return nil end
    return lastSent.target
end

-- Erster Teil eines Namens (Forever: der Vorname; sonst der Name ohne „-Realm“), klein geschrieben; nil bei
-- gesperrtem oder leerem Namen. Getrennt wird am Leerzeichen, am Nachnamen-Trennzeichen und am „-“ – das „-“ kann
-- den Realm abtrennen oder, in der Link-Form „Vorname-Nachname“, den Nachnamen (ezCore/Kern/Names.lua).
local function FirstName(name)
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local sep = Core.surnameSep
    if type(sep) == "string" and sep ~= "" and sep ~= " " then
        local at = name:find(sep, 1, true)
        if at then name = name:sub(1, at - 1) end
    end
    local first = name:match("^[^%s%-]+")
    return first and first:lower() or nil
end

-- Wie gut passt der Name aus UNIT_SPELLCAST_SENT zu einer Einheit? (Gesamtreview 18.11.2026, T4-NR9)
--   "exact"  voller Name gleich (Core.FullName: Forever „Vorname Nachname“ auch aus der Link-Form, sonst „Name-Realm“)
--   "first"  nur der erste Teil gleich – und der Name ist unvollständig: ohne Leerzeichen (nur Vorname, Link-Form
--            oder „Name-Realm“) bzw. die Einheit hat keinen Nachnamen. Auf Forever reicht das nicht, um „du selbst“ zu
--            sagen: „Testa-Fremd“ und nur „Testa“ passen auch zu dir, wenn du „Testa Probe“ heißt.
--   nil      passt nicht
-- name: das Ergebnis von Core.FullName(raw); raw: der Name, wie das Ereignis ihn liefert.
-- own (nur für dich): dein voller Name aus ezCore statt UnitName – auf Forever kann UnitName("player") den Nachnamen
-- auslassen, Core.InitIdentity holt ihn dann aus der GUID (Core.fullName).
local function NameMatch(unit, name, raw, own)
    own = own or ns.UnitFullName(unit)
    if ns.IsSecret(own) or type(own) ~= "string" or own == "" then return nil end
    if own:lower() == name:lower() then return "exact" end
    local first = FirstName(raw)
    if not first or first ~= FirstName(own) then return nil end
    if not raw:find(" ", 1, true) or Core.MissingSurname(own) then return "first" end
    return nil
end

local OTHER_UNITS = { "target", "focus", "mouseover", "party1", "party2", "party3", "party4" }
for i = 1, 40 do OTHER_UNITS[#OTHER_UNITS + 1] = "raid" .. i end

-- Ging der Zauber auf einen anderen Spieler? target: Name aus UNIT_SPELLCAST_SENT (oder nil).
--   genau dein voller Name (Core.IsSelf, auch der aus der GUID)                                  nein
--   nur dein Vorname passt und kein anderer trägt ihn                                            nein – wie vor T4-NR9
--   eben ein Klick auf ein anderes Mitglied (Symbol am Rahmen, Durchbuffen, Group.RecentOther)   ja
--   genau der volle Name eines anderen Mitglieds, des Ziels, Fokus oder der Maus                 ja
--   nur der Vorname passt (Link-Form, Name ohne Nachnamen): zu einem anderen                     ja
--                                                        zu dir und zu einem anderen             nil – unklar
--   sonst (kein, gesperrter oder unbekannter Name)                                               nein – wie bisher
-- Zweiter Wert: die Einheit des anderen Spielers, wenn bekannt. Bei nil merkt ezBuff nichts (Check.Remember läuft
-- nicht): im Zweifel bleibt deine Wahl unberührt.
local function OwnFullName()
    local full = Core.fullName
    if not ns.IsSecret(full) and type(full) == "string" and full ~= "" then return full end
    return nil
end

function Check.CastOnOther(target)
    local name = (not ns.IsSecret(target) and type(target) == "string") and Core.FullName(target) or nil
    if name and Core.IsSelf(name) then return false end
    local mine = name and NameMatch("player", name, target, OwnFullName())
    if mine == "exact" then return false end
    -- Erst die anderen ansehen: passt nur dein Vorname und trägt ihn sonst keiner, warst du es – auch nach einem
    -- Klick der letzten Sekunden (Gegenprüfung des Pakets P3).
    local exact, candidate
    if name then
        for _, unit in ipairs(OTHER_UNITS) do
            if Value(UnitExists, unit) and not Value(UnitIsUnit, unit, "player") then
                local match = NameMatch(unit, name, target)
                if match == "exact" then exact = unit break end
                if match and not candidate then candidate = unit end
            end
        end
    end
    if mine and not exact and not candidate then return false end
    local clicked = ns.Group and ns.Group.RecentOther and ns.Group.RecentOther()
    if clicked then return true, clicked end
    if exact then return true, exact end
    if candidate and mine then return nil end
    if candidate then return true, candidate end
    return false
end

-- Selbst gewirkter Buff: merken, welchen der Wahl (Segen, Rüstung) der Spieler nimmt.
-- Gemerkt wird nur eine bewusste Abweichung vom Vorschlag ohne Wahl. Wirkt der Spieler genau diesen, wird die
-- gemerkte Wahl gelöscht – sonst bliebe ein Paladin, der bis Stufe 20 den vorgeschlagenen Segen der Macht wirkt,
-- für immer bei Macht und bekäme den Segen der Könige nie vorgeschlagen.
-- onOther: der Zauber ging auf einen anderen Spieler (Check.CastOnOther) – dann bleibt deine Wahl unberührt. Er
-- wird auch nicht zur Einzelwahl dieses Spielers; die setzt nur das Menü am Rahmen (Check.SetPlayerBlessing).
function Check.Remember(spellID, onOther)
    if onOther then return end
    -- Waffenzauber des Schamanen (Welle 23, A4): dieselbe Regel für die Wahlgruppe „imbue“ (Weapon.lua)
    local imbue = ns.Weapon and ns.Weapon.ImbueKeyOf(spellID)
    if imbue then
        local group = Check.ChoiceGroup(ns.Weapon.IMBUE_ID)
        if group then ns.CharDB().prefer[group.id] = DefaultKey(group) ~= imbue and imbue or nil end
        return
    end
    local key = Buffs.KeyOf(spellID)
    if not key then return end
    for _, group in ipairs(Groups(ns.playerClass)) do
        if group.kind then
            for _, entry in ipairs(group.entries) do
                if entry.key == key then
                    if DefaultKey(group) == key then
                        ns.CharDB().prefer[group.id] = nil
                    else
                        ns.CharDB().prefer[group.id] = key
                    end
                    return
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Sichtbare Wahl je Wahlgruppe (EC-39, ST-10; Leitlinie 3): Segen, Rüstung, Schild der eigenen Klasse, dazu der
-- Waffenzauber des Schamanen (Welle 23, A4; Gruppe aus Weapon.ImbueGroup, keine Aura-Gruppe) – auf der
-- Einstellungsseite (Options.lua) und im Rechtsklick-Menü des Knopfs (Button.OpenMenu). Beide schreiben dieselbe
-- gemerkte Wahl wie das Wirken (ns.CharDB().prefer[gruppe]); Preferred(gruppe) der Schnittstelle liefert sie.
---------------------------------------------------------------------------

Check.CHOICE_KINDS = { "blessing", "armor", "shield", "imbue" }

-- Wahlgruppe der eigenen Klasse zu einer id ("blessing", "armor", "shield", "imbue") oder nil.
local function ChoiceGroup(id)
    if ns.IsSecret(id) or type(id) ~= "string" then return nil end
    -- Waffenzauber: nur, wenn deine Klasse welche hat und du mindestens einen gelernt hast (sonst gäbe es nichts zu wählen)
    if ns.Weapon and id == ns.Weapon.IMBUE_ID then
        local group = ns.Weapon.ImbueGroup(ns.playerClass)
        if group and #ns.Weapon.ImbueChoices() > 0 then return group end
        return nil
    end
    for _, group in ipairs(Groups(ns.playerClass)) do
        if group.id == id and group.kind then return group end
    end
    return nil
end
Check.ChoiceGroup = ChoiceGroup

-- Wahlgruppen der eigenen Klasse in fester Reihenfolge (Segen, Rüstung, Schild, Waffenzauber).
function Check.ChoiceGroups()
    local out = {}
    for _, id in ipairs(Check.CHOICE_KINDS) do
        local group = ChoiceGroup(id)
        if group then out[#out + 1] = group end
    end
    return out
end

-- Wählbare Buffs einer Gruppe: { { key, spell, name } } – gelernt und von ezCore als Wahl angenommen
-- (Spells.ChooseBuff mit prefer gibt ihn zurück; ein abgelöster Buff wie Dämonenhaut nach der Dämonenrüstung fällt
-- weg, das Blitzschlagschild bleibt dank keepChoice). Ohne ezCores Wahl jeder gelernte.
function Check.Choices(id)
    local group, out = ChoiceGroup(id), {}
    if not group then return out end
    if group.imbue then return ns.Weapon.ImbueChoices() end
    for _, entry in ipairs(group.entries) do
        local spell = Buffs.BestRank(entry.key)
        if spell then
            local takes = true
            if not (group.kind and Check.FIRST_LEARNED[group.kind]) and Spells.ChooseBuff then
                local key = Core.Call(Spells.ChooseBuff, group.id, { class = ns.playerClass, prefer = entry.key })
                takes = key == entry.key
            end
            if takes then out[#out + 1] = { key = entry.key, spell = spell, name = Buffs.Name(entry, spell) } end
        end
    end
    return out
end

-- Gemerkte Wahl der Gruppe (Buff-Schlüssel) oder nil = „Automatisch“.
function Check.Prefer(id)
    if ns.IsSecret(id) or type(id) ~= "string" or not ns.db then return nil end
    local key = ns.CharDB().prefer[id]
    if ns.IsSecret(key) or type(key) ~= "string" then return nil end
    return key
end

-- Wahl setzen (key = Buff-Schlüssel der Gruppe) oder löschen (nil, „Automatisch“). → true, wenn gespeichert.
function Check.SetPrefer(id, key)
    local group = ChoiceGroup(id)
    if not group or not ns.db then return false end
    if ns.IsSecret(key) or (key ~= nil and type(key) ~= "string") then return false end
    if key ~= nil then
        local known = false
        for _, entry in ipairs(group.entries) do
            if entry.key == key then known = true end
        end
        if not known then return false end
    end
    ns.CharDB().prefer[id] = key
    Check.Request()
    return true
end

-- Texte für Menü und Auswahlfeld: Name der Art („Rüstung“), „Automatisch (Vorschlag: Magische Rüstung)“ und die
-- jetzige Wahl („Magische Rüstung“ bzw. „Automatisch“).
function Check.KindName(id)
    return L["KIND_" .. tostring(id)] or tostring(id)
end

local function ChoiceName(group, key)
    if group.imbue then return ns.Weapon.ImbueName(key) end
    for _, entry in ipairs(group.entries) do
        if entry.key == key then return Buffs.Name(entry, Buffs.BestRank(entry.key)) end
    end
    return nil
end

function Check.AutoText(id)
    local group = ChoiceGroup(id)
    local key = group and DefaultKey(group)
    local name = key and ChoiceName(group, key)
    if type(name) == "string" and name ~= "" and name ~= "?" then return L.PREFER_AUTO_SUGGEST:format(name) end
    return L.PREFER_AUTO
end

function Check.PreferText(id)
    local group, key = ChoiceGroup(id), Check.Prefer(id)
    local name = group and key and ChoiceName(group, key)
    if type(name) == "string" and name ~= "" then return name end
    return L.PREFER_AUTO
end

---------------------------------------------------------------------------
-- Aufgaben bauen
---------------------------------------------------------------------------

local function Add(list, task)
    task.order = ORDER[task.kind] or 99
    -- Hinweis „Dir fehlt …“ (Reagenz oder Werkzeug, Check.MissingReagents) – nur Anzeige, der Klick bleibt derselbe
    local action = task.action
    if type(action) == "table" and action.type == "spell" and action.spell then
        task.missingReagents, task.reagentSource = Check.MissingReagents(action.spell)
    end
    list[#list + 1] = task
end

-- label: ganzer Satz für Tooltip und Schnittstelle („Rüstung (Dämonenhaut) fehlt“).
-- what:  dasselbe ohne „fehlt“ – für Aufzählungen hinter „Es fehlt: …“ (ns.PrintMissing), sonst stünde es doppelt.
local function SpellTask(kind, key, label, spell, unit, what)
    return { kind = kind, key = key, label = label, what = what, icon = Spells.Icon(spell), spellName = Spells.Name(spell),
        action = { type = "spell", spell = spell, unit = unit } }
end

local function CheckSelf(list, auras, minLeft)
    for _, group in ipairs(Groups(ns.playerClass)) do
        if Castable(group) and not GroupHas(auras, group, minLeft) then
            local entry, spell = Choose(group, nil)
            if entry then
                local what = GroupLabel(group, entry, spell)
                local task = SpellTask("self", group.id, L.MISSING_SELF:format(what), spell, "player", what)
                task.buffKeys = KeysOf(group)
                Add(list, task)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Je Mitglied: welcher meiner Buffs fehlt oder läuft aus? (Abschnitt „Gruppe“ und Gruppen-Aufgaben am Knopf)
---------------------------------------------------------------------------

-- Segen-Wahl (Rechtsklick-Menü an Blizzards Gruppenrahmen, Group.lua), Entscheidung des Nutzers 13.11.2026
-- „Zusätzlich je Spieler“: die Wahl je Klasse bleibt, eine Wahl für einen einzelnen Spieler überstimmt sie.
-- Reihenfolge: Spieler → Klasse → Standard (nil: ezBuff wählt wie für dich).

-- Schlüssel eines Spielers aus Name-Realm (wie Core.charKey) und Anzeigename; nil bei gesperrtem oder fehlendem
-- Namen – dann ist keine Einzelwahl möglich. Rechnet ezCore (Core.UnitKey, EC-112; BF-11): Forever „Vorname
-- Nachname“ plus Realm aus der GUID, sonst „Name-Realm“ – dieselbe Regel wie vorher hier, gespeicherte Schlüssel
-- in ezBuffDB.chars[…].players bleiben gleich. Die Funktion bleibt als Weiterleitung (Leitlinie 8).
function Check.PlayerKey(unit)
    return Core.UnitKey(unit)
end

local function Players()
    local players = ns.CharDB().players
    return type(players) == "table" and players or {}
end

-- Einzelwahl für einen Spieler (Schlüssel aus Check.PlayerKey): Buff-Schlüssel oder nil.
function Check.PlayerBlessing(who)
    if ns.IsSecret(who) or type(who) ~= "string" then return nil end
    local entry = Players()[who]
    local key = type(entry) == "table" and entry.blessing or nil
    return type(key) == "string" and key or nil
end

-- Segen für ein Mitglied: Einzelwahl des Spielers (who = Check.PlayerKey), sonst Wahl der Klasse, sonst nil
-- (Standard). Zweiter Wert: "player" | "class" – woher die Wahl kommt. Ohne who nur die Klasse.
function Check.BlessingFor(class, who)
    local own = Check.PlayerBlessing(who)
    if own then return own, "player" end
    if ns.IsSecret(class) or type(class) ~= "string" then return nil end
    local key = ns.CharDB().blessings[class]
    if type(key) == "string" then return key, "class" end
    return nil
end

function Check.SetBlessing(class, key)
    if type(class) ~= "string" or ns.IsSecret(class) then return false end
    if key ~= nil and type(key) ~= "string" then return false end
    ns.CharDB().blessings[class] = key
    Check.Request()
    return true
end

-- Einzelwahl setzen (key = Segen) oder löschen (key = nil, „Wie Klasse“). class und name nur für die Liste auf
-- der Einstellungsseite. Gesperrter Schlüssel: nichts wird gespeichert.
function Check.SetPlayerBlessing(who, key, class, name)
    if ns.IsSecret(who) or type(who) ~= "string" or who == "" or not ns.db then return false end
    if key ~= nil and type(key) ~= "string" then return false end
    local players = ns.CharDB().players
    if key == nil then
        players[who] = nil
    else
        if ns.IsSecret(class) or type(class) ~= "string" then class = nil end
        if ns.IsSecret(name) or type(name) ~= "string" then name = nil end
        players[who] = { blessing = key, class = class, name = name }
    end
    Check.Request()
    return true
end

-- Alle Einzelwahlen des Charakters, nach Schlüssel sortiert: { { key, name, class, blessing } }. Auch Spieler,
-- die nicht mehr in der Gruppe sind (vergessene Einträge bleiben, bis der Nutzer sie löscht).
function Check.PlayerBlessings()
    local out = {}
    for who, entry in pairs(Players()) do
        if type(who) == "string" and type(entry) == "table" and type(entry.blessing) == "string" then
            out[#out + 1] = { key = who, name = entry.name or who, class = entry.class, blessing = entry.blessing }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Alle Einzelwahlen löschen (Knopf „Einzelwahlen löschen“ unter „Erweitert“): Anzahl der gelöschten.
function Check.ClearPlayerBlessings()
    local n = #Check.PlayerBlessings()
    if ns.db then ns.CharDB().players = {} end
    Check.Request()
    return n
end

-- Zustand einer Buff-Liste auf der Einheit: "ok" | "expiring" (läuft bald aus) | "missing", Aura. Je Schlüssel
-- über Buffs.State – „läuft aus“ nach ezCores Regel (Spells.BuffState), nicht mehr aus eigener Rechnung.
local function StateOf(auras, keys, minLeft)
    local found
    for _, key in ipairs(keys) do
        local state, aura = Buffs.State(auras, key, minLeft)
        if state == "ok" then return "ok", aura end
        if state == "expiring" and not found then found = aura end
    end
    if found then return "expiring", found end
    return "missing"
end
Check.StateOf = StateOf

-- Was braucht ein Mitglied von mir? m = { unit, name, class, level }, own = der Spieler selbst (alle eigenen
-- Buff-Gruppen, auch „nur auf dich“ wie Rüstungen). Liste { key, buffKey, spell, icon, name, state, left, inRange }.
-- Segen: die Einzelwahl für dieses Mitglied, sonst die Wahl für seine Klasse, sonst zählt jeder Segen (und
-- vorgeschlagen wird die eigene Wahl). m.key = Schlüssel aus Check.PlayerKey (sonst aus m.unit gerechnet).
function Check.MemberNeeds(m, auras, minLeft, own)
    local needs = {}
    if type(m) ~= "table" or type(auras) ~= "table" then return needs end
    local level = not own and m.level or nil
    local who = not own and (m.key or Check.PlayerKey(m.unit)) or nil
    for _, group in ipairs(Groups(ns.playerClass)) do
        if (own or group.target == "any") and Castable(group) then
            local keys, entry, spell = KeysOf(group), nil, nil
            local chosen = not own and group.kind == "blessing" and Check.BlessingFor(m.class, who)
            if chosen then
                for _, e in ipairs(group.entries) do
                    if e.key == chosen then entry = e end
                end
                if entry then
                    keys = { entry.key }
                    spell = Buffs.BestRank(entry.key, level)
                end
            end
            local state, aura = StateOf(auras, keys, minLeft)
            if state ~= "ok" then
                if not spell then
                    if group.kind or own then
                        entry, spell = Choose(group, level)
                    else
                        entry = group.entries[1]
                        spell = Buffs.BestRank(entry.key, level)
                    end
                end
                if entry and spell then
                    needs[#needs + 1] = { key = group.id, buffKey = entry.key, keys = keys, spell = spell,
                        icon = Spells.Icon(spell), name = Buffs.Name(entry, spell), state = state,
                        left = aura and Buffs.Left(aura) or nil,
                        inRange = own and true or InRange(spell, m.unit) }
                end
            end
        end
    end
    return needs
end

---------------------------------------------------------------------------
-- Gruppenfassungen (BF-09; Empfehlung umgesetzt, Antwort offen: ab 3 fehlenden Mitgliedern, Schalter ab Werk an,
-- nur mit Reagenz): Fehlt ein Buff mehreren Mitgliedern in Reichweite, wirken Symbol am Rahmen und Durchbuffen die
-- Gruppenfassung (Feld group in Spells.BuffInfo: Arkane Brillanz, Gebete, Gabe der Wildnis, Große Segen) – sofern
-- gelernt und das Reagenz in der Tasche ist (Spells.GroupReagent). Wen sie trifft:
--   Segen (kind "blessing")  alle Mitglieder derselben Klasse (Großer Segen). Nur, wenn jedes Mitglied dieser Klasse
--                            denselben Segen will (Wahl je Spieler, je Klasse bzw. deine eigene Wahl) – sonst
--                            überschriebe der Große Segen eine andere Wahl.
--   sonst                    die Untergruppe des Ziels: in einer Gruppe alle, im Schlachtzug dieselbe Raidgruppe
--                            (GetRaidRosterInfo).
-- Mitgezählt werden Mitglieder, denen der Buff fehlt, die in Reichweite sind und den höchsten gelernten Rang
-- annehmen (ein niedrigstufiges Mitglied bekommt weiter die Einzelfassung im passenden Rang). Was ausläuft, frischt
-- die Gruppenfassung mit auf, zählt aber nicht zur Schwelle.
---------------------------------------------------------------------------

-- Genau dieser Rang gelernt? (Spells.IsKnown nähme bei Rängen irgendeinen.)
local function KnowsRank(id)
    if ns.Value(IsPlayerSpell, id) == true then return true end
    return Spells.IsKnownRank ~= nil and Core.Call(Spells.IsKnownRank, id) == true
end

-- Höchste gelernte Gruppenfassung des Buffs key: Zauber-ID, Reagenz (Gegenstand oder nil), Anzahl in der Tasche,
-- nötige Anzahl, Quelle des Bedarfs ("tables" | "list", Check.ReagentNeeds). nil, wenn der Buff keine
-- Gruppenfassung hat oder keine gelernt ist.
function Check.GroupSpell(key)
    local info = type(key) == "string" and Buffs.Info(key)
    local list = info and info.group
    if type(list) ~= "table" then return nil end
    for index = #list, 1, -1 do
        local id = ns.Num(list[index])
        if id and KnowsRank(id) then
            local needs, source = Check.ReagentNeeds(id)
            local first = needs[1]
            if not first then return id end
            return id, first.item, Core.ItemCount(first.item), first.need, source
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Reagenzien und Werkzeuge (Paket modul/ezbuff-reagenzien, wago F9): Was ein Zauber verbraucht bzw. braucht und was
-- davon in den Taschen fehlt, rechnet seit Welle 26 ezCore (Spells.ReagentNeeds, Spells.MissingReagents – Bedarf laut
-- Client-Tabellen, Anzahl über Blizzards API, Rückfall ezCores Liste der Gruppenfassungen; Texte in ezCore.L). Die
-- Funktionen hier leiten dorthin weiter (Leitlinie 2; eine Rechnung für ezBuff und ezMacro). Nur Anzeige: kein Klick,
-- keine geschützte Aktion ändert sich.
---------------------------------------------------------------------------

-- Bedarf eines Zaubers: { { item, need, tool } … } (leer, wenn nichts) und Quelle "tables" | "list" | nil.
function Check.ReagentNeeds(spellID)
    if type(Spells.ReagentNeeds) ~= "function" then return {} end
    local ok, needs, source = Core.Try("ezBuff", "ReagentNeeds", Spells.ReagentNeeds, spellID)   -- T7-1
    if not ok or type(needs) ~= "table" then return {} end
    return needs, source
end

-- Was fehlt in den Taschen? → { { item, need, have, tool } … } oder nil (nichts fehlt bzw. kein Bedarf), Quelle.
function Check.MissingReagents(spellID)
    if type(Spells.MissingReagents) ~= "function" then return nil end
    local ok, missing, source = Core.Try("ezBuff", "MissingReagents", Spells.MissingReagents, spellID)   -- T7-1
    if not ok then return nil end
    return missing, source
end

-- „Dir fehlt: Arkanes Pulver (0 von 1)“ (Name vom Client, sonst die Nummer).
function Check.ReagentText(missing)
    return Spells.ReagentText(missing)
end

-- Quelle des Hinweises (Leitlinie 11): „Bedarf laut Client-Tabellen (wago.tools, Build …), Anzahl aus deinen Taschen“.
function Check.ReagentSource(source)
    return Spells.ReagentSource(source)
end

-- Raidgruppe einer Einheit (1–8); in einer Gruppe ohne Schlachtzug immer 1; nil, wenn unbekannt oder gesperrt.
function Check.Subgroup(unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    if not (IsInRaid and IsInRaid()) then return 1 end
    local index = tonumber(unit:match("^raid(%d+)$") or "")
    if not index and unit == "player" then
        for i = 1, 40 do
            if Value(UnitIsUnit, "raid" .. i, "player") == true then index = i break end
        end
    end
    if not index or type(GetRaidRosterInfo) ~= "function" then return nil end
    local ok, _, _, subgroup = pcall(GetRaidRosterInfo, index)
    return ok and ns.Num(ns.Plain(subgroup)) or nil
end

-- Welchen Segen will ein Mitglied? Bedarf (need.buffKey), sonst die Einzelwahl bzw. Wahl der Klasse, beim Spieler
-- seine gemerkte Wahl; nil = keine Wahl (jeder Segen zählt).
local function WantedBlessing(m)
    for _, need in ipairs(m.needs or {}) do
        if need.key == "blessing" then return need.buffKey end
    end
    if m.unit == "player" then return Check.Prefer("blessing") end
    return (Check.BlessingFor(m.class, m.key or Check.PlayerKey(m.unit)))
end

-- Gruppenfassungen in die Bedarfe eintragen (nach Check.Members; nur mit „Gruppenfassung ab“ ≥ 2 – 1 heißt aus):
--   need.groupSpell, need.groupCount, need.groupUnits   die Fassung, wie viele ihr fehlen, wen sie mit auffrischt
--   need.groupReagent                                   Schwelle erreicht, aber das Reagenz fehlt (Gegenstand)
function Check.MarkGroupSpells(units)
    if not ns.S or type(units) ~= "table" then return end
    local min = ns.Num(ns.S.groupMin) or 3
    if min < 2 then return end
    local scopes, order = {}, {}
    for unit, m in pairs(units) do
        for _, need in ipairs(m.needs or {}) do
            local scope
            if need.key == "blessing" then
                scope = "class:" .. tostring(m.class) .. ":" .. tostring(need.buffKey)
            else
                local subgroup = Check.Subgroup(unit)
                scope = subgroup and ("group:" .. subgroup .. ":" .. tostring(need.buffKey)) or nil
            end
            local top = need.spell ~= nil and need.spell == Buffs.BestRank(need.buffKey)
            if scope and need.inRange and top then
                local s = scopes[scope]
                if not s then
                    s = { key = need.buffKey, class = m.class, blessing = need.key == "blessing", list = {}, missing = 0 }
                    scopes[scope] = s
                    order[#order + 1] = scope
                end
                s.list[#s.list + 1] = { unit = unit, need = need }
                if need.state == "missing" then s.missing = s.missing + 1 end
            end
        end
    end
    for _, scope in ipairs(order) do
        local s = scopes[scope]
        local spell, reagent, count, needed, source = nil, nil, nil, nil, nil
        if s.missing >= min then spell, reagent, count, needed, source = Check.GroupSpell(s.key) end
        if spell and s.blessing then
            -- Großer Segen: jeder dieser Klasse will genau diesen Segen (oder hat keine Wahl)
            for _, m in pairs(units) do
                if m.class == s.class then
                    local wanted = WantedBlessing(m)
                    if wanted ~= nil and wanted ~= s.key then spell = nil end
                end
            end
        end
        if spell and reagent and (count or 0) < (needed or 1) then
            for _, item in ipairs(s.list) do
                item.need.groupReagent, item.need.groupReagentHave = reagent, count or 0
                item.need.groupReagentNeed, item.need.groupReagentSource = needed or 1, source
            end
        elseif spell then
            local targets = {}
            for _, item in ipairs(s.list) do targets[#targets + 1] = item.unit end
            for _, item in ipairs(s.list) do
                item.need.groupSpell, item.need.groupCount, item.need.groupUnits = spell, s.missing, targets
            end
        end
    end
end

-- Alle Mitglieder einmal lesen (je Mitglied ein Aura-Scan): { [unit] = { unit, name, class, level, needs,
-- food = Buff-Essen fehlt, flask = kein bekanntes Fläschchen/Elixier } }. Nur sichtbare Mitglieder (sonst liefert
-- das Spiel ihre Auren nicht) und nur, wenn ihre Auren ganz lesbar sind. Der Spieler steht als "player" darin.
local byUnit = {}
function Check.ByUnit() return byUnit end

function Check.Members(members, playerAuras, minLeft)
    local out = {}
    if not ns.InGroup() then return out end
    local food = ns.S.food and ns.ContextAllows(ns.S.when)
    local flask = ns.S.flask and ns.InInstance()
    local function Fill(m, auras, own)
        m.needs = Check.MemberNeeds(m, auras, minLeft, own)
        m.food = food and not Buffs.Has(auras, "wellFed", minLeft) or false
        m.flask = flask and not Buffs.Elixir(auras, minLeft) or false
        out[m.unit] = m
    end
    if playerAuras then
        Fill({ unit = "player", name = ns.UnitFullName("player"), class = ns.playerClass,
            level = Core.PlayerLevel(), visible = true }, playerAuras, true)
    end
    for _, member in ipairs(members or {}) do
        if member.visible then
            local auras = Buffs.Scan(member.unit)
            if auras then
                local m = {}
                for k, v in pairs(member) do m[k] = v end
                Fill(m, auras, false)
            end
        end
    end
    Check.MarkGroupSpells(out)
    return out
end

local function CheckGroup(list, members, units)
    for _, member in ipairs(members) do
        local m = units[member.unit]
        for _, need in ipairs(m and m.needs or {}) do
            if need.inRange then
                local task = SpellTask("group", need.key, L.MISSING_ON:format(need.name, m.name), need.spell, m.unit,
                    L.WHAT_ON:format(need.name, m.name))
                task.target = m.name
                task.buffKeys = need.keys
                Add(list, task)
            end
        end
    end
end

-- Wer aus der Gruppe kann den Buff der Wahlgruppe geben? (Spieltest 15.11.2026, Buffs.CanGive) Je Mitglied der
-- Klasse jeder Eintrag der Gruppe (bei Segen jeder Segen): der Client kennt ihn, das Mitglied hat die Lernstufe,
-- du darfst ihn annehmen. Rückgabe: Mitglied, Eintrag, Lernstufe, Quelle – oder nil (dann wird nichts erwartet).
-- Client und Lernstufe werden je Eintrag einmal gefragt (Buffs.Availability), nicht je Mitglied.
local function Giver(group, members, class, playerLevel, clientKeys)
    local avail = {}
    for index, entry in ipairs(group.entries) do avail[index] = Buffs.Availability(entry, clientKeys) end
    for _, m in ipairs(members) do
        if m.class == class then
            for index, entry in ipairs(group.entries) do
                local can, level, source = Buffs.CanGive(entry, m.level, playerLevel, clientKeys, avail[index])
                if can then return m, entry, level, source end
            end
        end
    end
    return nil
end
Check.Giver = Giver

local function CheckOthers(list, auras, members, minLeft)
    local seen = { [ns.playerClass or ""] = true }
    local playerLevel, clientKeys = Core.PlayerLevel(), Buffs.ClientGroupBuffs()
    for _, first in ipairs(members) do
        if not seen[first.class] then
            seen[first.class] = true
            for _, group in ipairs(Groups(first.class)) do
                if group.target == "any" and not GroupHas(auras, group, minLeft) then
                    local m, entry, level, source = Giver(group, members, first.class, playerLevel, clientKeys)
                    if m then
                        local what, who = GroupLabel(group, entry), Core.ClassText(m.name, m.class)
                        Add(list, { kind = "other", key = group.id, label = L.MISSING_FROM:format(what, who),
                            what = L.WHAT_FROM:format(what, who), icon = Spells.Icon(Buffs.SpellOf(entry)),
                            note = level and L.OTHER_NOTE:format(level, Buffs.SourceText(source)) or nil,
                            giver = m.name, learnLevel = level, source = source })
                    end
                end
            end
        end
    end
end

-- Buff-Essen und Fläschchen (nur, wenn „Wann prüfen“ es erlaubt): items = Check.BagItems(klasse)
local function CheckFoodFlask(list, auras, minLeft, items)
    local inInstance = ns.InInstance()
    if ns.S.flask and not Buffs.Elixir(auras, minLeft) then
        local item = items.flask
        if item then
            Add(list, { kind = "flask", key = item.itemID, label = L.MISSING_FLASK, what = L.WHAT_FLASK, icon = item.icon, itemName = item.name,
                action = { type = "item", item = "item:" .. item.itemID } })
        elseif inInstance then
            Add(list, { kind = "flask", key = 0, label = L.MISSING_FLASK_NONE, what = L.WHAT_FLASK_NONE })
        end
    end
    if ns.S.food and not Buffs.Has(auras, "wellFed", minLeft) then
        local item = items.food
        if item then
            Add(list, { kind = "food", key = item.itemID, label = L.MISSING_FOOD, what = L.WHAT_FOOD, icon = item.icon, itemName = item.name,
                action = { type = "item", item = "item:" .. item.itemID } })
        elseif inInstance then
            Add(list, { kind = "food", key = 0, label = L.MISSING_FOOD_NONE, what = L.WHAT_FOOD_NONE })
        end
    end
end

-- „Wann prüfen“ gilt für alles aus der Tasche. Der Waffenzauber des Schamanen braucht keinen Gegenstand und gilt wie
-- eigene Klassen-Buffs immer (Gegenprüfung Welle 23; Empfehlung umgesetzt, Antwort offen – docs/roadmap/ezBuff.md).
local function CheckConsumables(list, auras, minLeft, class)
    local allowed = ns.ContextAllows(ns.S.when)
    local items = allowed and Check.BagItems(class) or {}
    if allowed then CheckFoodFlask(list, auras, minLeft, items) end
    -- Waffenverzauberung (BF-17, Schalter „weapon“, ab Werk an seit 19.11.2026): je Hand eine Aufgabe, mit Passendem in der Tasche
    -- (nur, wenn „Wann prüfen“ es erlaubt) oder dem gelernten Waffenzauber des Schamanen
    if ns.S.weapon and ns.Weapon then
        for _, task in ipairs(ns.Weapon.Tasks(items.weapon, minLeft)) do Add(list, task) end
    end
end

local function CheckCampfire(list, auras)
    if not ns.S.campfire or not ns.ContextAllows(ns.S.when) then return end
    local info = Buffs.Info("cozyFire")
    if not (info and info.cast) or Buffs.Has(auras, "cozyFire", 0) or not Spells.IsKnown(info.cast) then return end
    if info.reagent then
        local count = ns.Num(Core.Call(C_Item and C_Item.GetItemCount or GetItemCount, info.reagent))
        if (count or 0) < 1 then return end
    end
    Add(list, SpellTask("campfire", "cozyFire", L.MISSING_CAMPFIRE, info.cast, nil, L.WHAT_CAMPFIRE))
end

local function Sort(list)
    for index, task in ipairs(list) do task.index = index end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
end

-- Waren die Auren bei der letzten Prüfung lesbar – und sind sie es jetzt? Falsch im Kampf, tot, auf dem Flug
-- oder wenn das Spiel Auren sperrt: Dann sagt eine leere Liste nichts.
-- Falsch auch nach dem Kampf, bis wieder geprüft ist (Check.Stale beim Kampfbeginn): Die Prüfung kommt gedrosselt
-- erst 0,5 s nach PLAYER_REGEN_ENABLED – bis dahin stünde sonst die Liste von vor dem Kampf als „lesbar“ da.
local readable = false
local soloNeeds = {}
function Check.Readable()
    return readable and not ns.InCombat()
end

-- Allein unterwegs (keine Gruppe, Abschnitt „Gruppe“ an): was dir von deinen eigenen Buffs fehlt, in der Form von
-- Check.MemberNeeds (own = true). „Durchbuffen“ (Group.Next) wirkt sie, damit das Makro der Klassen-Vorlage
-- (Macro.lua) auch allein etwas tut. In einer Gruppe leer – dort steht der Spieler in Check.ByUnit.
function Check.SoloNeeds() return soloNeeds end

-- Die letzte Prüfung gilt nach außen nicht mehr, bis Check.Run wieder gelesen hat (Kampfbeginn).
function Check.Stale() readable = false end

-- Alles prüfen (nur außerhalb des Kampfes; im Kampf bleibt die letzte Liste für den Knopf stehen, der dann ohnehin
-- aus ist – nach außen gilt sie nicht: Missing() und die Chat-Meldung fragen vorher Check.Readable).
function Check.Run()
    if ns.InCombat() or not ns.S then return tasks end
    local list = {}
    local dead = Value(UnitIsDeadOrGhost, "player") or Value(UnitOnTaxi, "player")
    local auras = not dead and Buffs.Scan("player")
    readable = auras and true or false
    local units, solo = {}, {}
    if auras then
        local minLeft = (ns.S.minLeft or 0) * 60
        local class = ns.playerClass
        if ns.Rebuff and ns.Rebuff.Active() then
            for _, task in ipairs(ns.Rebuff.Tasks()) do Add(list, task) end
        end
        if ns.S.selfBuffs then CheckSelf(list, auras, minLeft) end
        CheckConsumables(list, auras, minLeft, class)
        local members
        local frames = ns.Group ~= nil and ns.Group.Active()
        if ns.S.groupBuffs or ns.S.otherBuffs or frames then
            members = {}
            for _, unit in ipairs(Check.GroupUnits()) do
                local m = Member(unit)
                if m then members[#members + 1] = m end
            end
        end
        units = (ns.S.groupBuffs or frames) and Check.Members(members, auras, minLeft) or {}
        -- Allein: deine eigenen Buffs für „Durchbuffen“ (Group.Next; Empfehlung umgesetzt, Antwort offen, 15.11.2026)
        solo = frames and not ns.InGroup() and Check.MemberNeeds({ unit = "player", name = ns.UnitFullName("player"),
            class = ns.playerClass, level = Core.PlayerLevel(), visible = true }, auras, minLeft, true) or {}
        if ns.S.groupBuffs then CheckGroup(list, members, units) end
        CheckCampfire(list, auras)
        if ns.S.otherBuffs then CheckOthers(list, auras, members, minLeft) end
        Sort(list)
    end
    tasks, byUnit, soloNeeds = list, units, solo
    ns.Fire("TASKS", tasks)
    Core.Fire("EZBUFF_TASKS")   -- für andere Module (ezCombat spiegelt fehlende Dauer-Buffs)
    return tasks
end

-- Kümmert sich ezBuff um diesen Buff? „Eigene Klassen-Buffs“ ist an und die Gruppe (Buff-Schlüssel wie
-- "demonSkin" oder Wahl wie "armor") gehört zur Klasse des Spielers.
function Check.Watches(value)
    if not (ns.S and ns.S.selfBuffs) or ns.IsSecret(value) or type(value) ~= "string" then return false end
    local class = ns.playerClass
    local id = value
    local known = Spells.BuffGroup and Core.Call(Spells.BuffGroup, value, class)
    if type(known) == "table" then
        if known.class ~= class then return false end
        id = known.id
    end
    for _, group in ipairs(Groups(class)) do
        if group.id == id then return true end
        for _, entry in ipairs(group.entries) do
            if entry.key == id then return true end
        end
    end
    return false
end

local throttled
function Check.Request()
    if not throttled then throttled = ns.Throttle(Check.Run, 0.5) end
    throttled()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- Einheiten, deren UNIT_*-Ereignisse eine Prüfung auslösen: du und die Mitglieder (Gruppe, Schlachtzug). Die Menge
-- geht als Einheiten-Filter an ezCore (ns.OnUnit). Blizzards RegisterUnitEvent nimmt höchstens zwei Einheiten; bei
-- diesen 45 meldet ezCore das Ereignis deshalb am Hauptrahmen für alle Einheiten an und filtert erst in Lua: Namens-
-- plaketten, Ziel-des-Ziels usw. wecken ezCores Verteiler weiter, erreichen ezBuffs Zuhörer aber nicht. Eine gesperrte
-- Einheit (im Kampf) stellt ezCore immer zu (IsWatchedUnit unten). Gesamtreview 18.11.2026, T8-3 – der Kommentar
-- versprach vorher, der Verteiler werde gar nicht geweckt.
Check.WATCHED_UNITS = { "player", "party1", "party2", "party3", "party4" }
for i = 1, 40 do Check.WATCHED_UNITS[#Check.WATCHED_UNITS + 1] = "raid" .. i end
local watched = {}
for _, unit in ipairs(Check.WATCHED_UNITS) do watched[unit] = true end

-- Zählt das Ereignis? Eine gesperrte Einheit (UNIT_AURA im Kampf, Vollprüfung W-04) wird nie verglichen und zählt
-- hinter ns.OnUnit als Treffer – sonst erführe ezBuff nichts von auslaufenden Buffs. Das kostet höchstens eine
-- Anfrage an die gedrosselte Prüfung (Check.Run tut im Kampf nichts und prüft danach ohnehin neu).
local function IsWatchedUnit(unit)
    if ns.IsSecret(unit) then return true end
    return type(unit) == "string" and watched[unit] == true
end
Check.IsWatchedUnit = IsWatchedUnit

local wasInInstance = false

ns.OnReady(function()
    ns.OnUnit("UNIT_AURA", Check.WATCHED_UNITS, function(_, unit)
        if IsWatchedUnit(unit) then Check.Request() end
    end)
    -- Tascheninhalt neu lesen (vor der Prüfung, die dieselben Ereignisse gleich danach anfragen). Der
    -- Stufenaufstieg vergisst hier sofort und – mit Absicht doppelt – noch einmal über Core.Knowledge.OnReady
    -- (unten), sobald ezCore die Aussagen zu den Gegenständen neu gerechnet hat.
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        ns.On(event, Check.ForgetBags)
    end
    -- Kampfbeginn: Die Liste der letzten Prüfung gilt nach außen erst wieder nach der nächsten Prüfung (V-147).
    ns.On("PLAYER_REGEN_DISABLED", Check.Stale)
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP",
        "SPELLS_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA" }) do
        ns.On(event, function() Check.Request() end)
    end
    -- Begleiter gerufen, entlassen oder gestorben: Seelenverbindung braucht ihn (lange Selbst-Buffs, T14-2)
    ns.OnUnit("UNIT_PET", "player", function() Check.Request() end)
    -- UNIT_FLAGS (tot, Geist, im Kampf, offline …) nur für dich und die Mitglieder, nicht für jede Einheit
    ns.OnUnit("UNIT_FLAGS", Check.WATCHED_UNITS, function(_, unit)
        if IsWatchedUnit(unit) then Check.Request() end
    end)
    -- Eigene Zauber: nur die Einheit „player“ (Blizzards RegisterUnitEvent über ezCore). Eine gesperrte Einheit
    -- zählt auch hier als Treffer (W-04); gesperrte Angaben zum Zauber verwerfen NoteSent und die Prüfung darunter.
    ns.OnUnit("UNIT_SPELLCAST_SENT", "player", function(_, unit, target, castGUID)
        if not ns.IsSecret(unit) and unit ~= "player" then return end
        Check.NoteSent(castGUID, target)
    end)
    ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, castGUID, spellID)
        local locked = ns.IsSecret(unit)
        if not locked and unit ~= "player" then return end
        if ns.IsSecret(spellID) or type(spellID) ~= "number" then return end
        -- kein Buff und kein Waffenzauber (Weapon.ImbueKeyOf): nichts zu merken, kein Namensvergleich
        if not Buffs.KeyOf(spellID) and not (ns.Weapon and ns.Weapon.ImbueKeyOf(spellID)) then return end
        local target = Check.SentTarget(castGUID)
        local onOther = Check.CastOnOther(target)
        -- Nur der Vorname war bekannt, und er passt zu dir und zu einem anderen (T4-NR9): nichts merken.
        if onOther == nil then return end
        -- Gesperrte Einheit und kein Ziel bekannt (der Name war ebenfalls gesperrt, kein Klick am Rahmen): Ob der
        -- Buff auf dich oder einen anderen ging, weiß ezBuff dann nicht – deine gemerkte Wahl bleibt unberührt.
        if locked and target == nil and not onOther then return end
        Check.Remember(spellID, onOther)
    end)
    -- Im Kampf prüft Check.Run nicht; ns.PrintMissing meldet dann statt der alten Liste „im Kampf nicht prüfbar“.
    ns.On("READY_CHECK", function()
        Check.Run()
        if ns.S.report then ns.PrintMissing(false) end
    end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        local inside = ns.InInstance()
        local entered = inside and not wasInInstance
        wasInInstance = inside
        C_Timer.After(3, function()
            Check.Run()
            if entered and ns.S.report then ns.PrintMissing(false) end
        end)
    end)
    ns.OnSettingChanged(function() Check.Request() end)
    if Core.Knowledge and Core.Knowledge.OnReady then
        Core.Knowledge.OnReady(function()
            Check.ForgetBags()
            Check.Request()
        end)
    end
    -- Fläschchen und Elixiere aus dem Besitz aller Charaktere (BF-10): kurz nach dem Einloggen und wenn ezCores
    -- Inventar neu erfasst hat (gedrosselt; schon Ausgewertetes fragt ezBuff nicht noch einmal).
    local learn = ns.Throttle(function()
        if Check.LearnElixirs() > 0 then Check.Request() end
    end, 2)
    C_Timer.After(3, learn)
    if Core.Listen then Core.Listen("INVENTORY_CHANGED", learn, ns.moduleName) end
    -- Restzeiten laufen ab, ohne dass ein Ereignis kommt. Takt mit Griff, Fehler in ezBuffs Fehlerliste (ezCores
    -- Ticker-Helfer, Gesamtreview 18.11.2026, T7-3).
    Check.ticker = ns.Ticker(15, function() Check.Request() end, nil, "Check.Tick")
    Check.Request()
end)
