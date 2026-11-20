local ADDON, ns = ...
local Core = ezCore
local Spells = Core.Spells

--[[
    Zauber-Wissen (wie das Item-Wissen): eine Quelle für alles über Zauber, für ezMacro (Ränge aktualisieren),
    ezMerchant (Lehrer, „Was kommt wann“), ezCombat (Klassen-Fähigkeiten), ezPanel (Hinweis „neue Ränge“).

      Namen        Spells.Name(id) → Name, aus dem Client?   Spells.Icon(id)   (Ersatznamen in SpellData.lua)
      Ränge        Spells.Rank(id) → Zahl oder nil            Spells.ParseRank("Rang 4") → 4
      Bekannt      aus dem Zauberbuch, alle gelernten Ränge – auch die, die das Zauberbuch nicht zeigt (Forever zeigt
                   je Zauber nur den höchsten Rang; einen Haken „Alle Ränge zeigen“ hat es im Spiel nicht, Spieltest 14.11.2026):
                   Spells.IsKnown(id), Spells.Known(nameOderID) → { name, ranks = { [Rang] = id }, maxRank, maxID, level }
                   Spells.Highest(nameOderID) → maxID, maxRank   Spells.IsLowRank(id)   Spells.ForEachKnown(fn)
                   Spells.KnowsRank(name, rang)   Spells.Future() → noch nicht gelernte Zauber aus dem Zauberbuch
      Lehrer       lernt bei jedem Besuch (Name, Rang, Stufe, Kosten), je Sprache und Klasse in ezCoreDB.spells:
                   Spells.Trainer(art) → Liste   Spells.Available(stufe, art) → Liste, Kosten
                   Spells.Upcoming(abStufe, bisStufe, art) → Liste, Kosten   Spells.TrainerSeen(art) → Zeit oder nil
                   Spells.Waiting(stufe, art) → Anzahl, Kosten (nil ohne Lehrerbesuch), "trainer"/"book"/"none", Liste
                   (ohne Lehrerbesuch zählt Spells.BookEntries: Zauberbuch „kommt später“ samt Stufen laut Client und,
                   seit Welle 26, den Klassenzaubern laut Client-Tabellen)
      Begleiter    Spells.PetKind(klasse) → "HUNTER:PET" … (Art für Trainer/Available/Upcoming/Waiting), Spells.PetBook()
                   → gelernte Begleiter-Zauber aus dem Begleiter-Zauberbuch, Spells.PetStatus() → woher die Daten kommen
      Je Stufe     Spells.LevelSpells(stufe) → Zauber-IDs (C_SpellBook.GetCurrentLevelSpells, Form geprüft) oder nil,
                   Spells.Coming(abStufe, bisStufe) → { id, name, rank, level, icon, known } aus dem Client,
                   Spells.BookEntries() → Spells.Future ergänzt um Spells.Coming (Welle 23) und Spells.ClientComing
                   (Welle 26), Client geliefert?, Tabellen geliefert? (zwischengespeichert, Welle 27:
                   Spells.ForgetBookEntries() verwirft), Spells.TableEntryOpen(eintrag) → für dich noch offen?,
                   Spells.OpenTableEntries(zeilen) → die offenen Einträge der Client-Tabellen (Welle 27)
      Klassen      Spells.CLASS, Spells.ClassSpellNames(kind, klasse), Spells.IsExecute(id), Spells.AUTO_SHOT
      Buffs        Spells.BUFFS (SpellData.lua; Rohtabelle, nur ezCore liest sie – Module über Funktionen, F7),
                   Spells.BuffKey(idOderName) → Gruppe, Spells.ClassBuffs(klasse) → Liste,
                   Spells.BestBuffRank(gruppe, zielStufe) → Zauber-ID, Spells.BuffInfo(gruppe) → Daten (Kopie),
                   Spells.BuffMissing(gruppe) → fehlt im Client? (Kennzeichen missing, Welle 23),
                   Spells.IsBuff(schlüssel) → true/false, Spells.BuffField(schlüssel, feld) → Wert,
                   Spells.BuffKeys(klasse, andere) → Schlüssel in fester Reihenfolge (Welle 27)
      Waffenzauber Spells.WEAPON_IMBUES (Schamane), Spells.WeaponImbues(klasse) → Liste,
                   Spells.BestImbueRank(schlüssel) → höchster gelernter Rang (Welle 23)
      Abfragen     Spells.CastTime(zauber), Spells.Usable(zauber) → nutzbar, nurKraftFehlt, unbekannt (gesperrt oder
                   Abfrage gescheitert)
                   Spells.OnCooldown(zauber) → true/false (zweiter Wert "secret": aus isActive/isOnGCD bzw.
                   Spells.LockedKind gelesen), oder nil und "secret", wenn das Spiel es nicht verrät
                   Spells.LockedKind(zauber) → "real" | "gcd" | nil (gesperrt, isOnGCD fehlt: Dauer-Objekt, globale
                   Abklingzeit), Spells.DurationObject(zauber, ohneGCD) → Blizzards Dauer-Objekt oder nil
                   Spells.CooldownKind(info, start, dauer) → "none" | "gcd" | "real" | nil, Spells.GCD_MAX (1,55 s)
                   Spells.GCDActive() → läuft die globale Abklingzeit? true/false/nil
                   Spells.BaseCooldown(zauber) → Sekunden (0 = keine eigene), Quelle ("client" | "tables") oder nil
                   (Grund-Abklingzeit ohne Talente; Welle 27, Paket modul/ezcombat-abklingzeit)
                   Blizzards Regeln (Prüfung 17.11.2026, Risiko 13): Die Abfragen für Abklingzeit und Nutzbarkeit lesen
                   nur offene Werte und Felder, die Blizzard nie sperrt (SpellCooldownInfo.isActive und isOnGCD, laut
                   Forever-Quelle „NeverSecret“, dazu das Dauer-Objekt nur weitergereicht); was gesperrt ist, geben sie
                   als unbekannt zurück (nil bzw. dritter Wert von Usable), nie als geraten. BaseCooldown und
                   AuraSeconds sind Nachschlage-Daten (Client, Client-Tabellen, offen gesehene Dauern) – wer daraus im
                   Kampf gesperrte Restzeiten nachrechnet (ezCombat, „Mitzählen“), tut das nur, wenn der Spieler es
                   einschaltet (ab Werk aus).
      Klassen-Wissen (unten, „Klassen-Wissen“; Daten in SpellData.lua, Beschreibung in docs/ezcore.md):
                   Spells.Exists(id), Spells.LevelLearned(id) → Stufe, Quelle, Spells.InRange(id, einheit) → true/false/nil,
                   Spells.IsCurrent(id), Spells.Family(name) → IDs, Daten, Spells.FamilyOf(id) → Name,
                   Spells.BuffGroup(schlüsselOderKind, klasse), Spells.ChooseBuff(schlüsselOderKind, opts) → Schlüssel, Zauber-ID,
                   Spells.AuraIDs(idSchlüsselOderFamilie) → Menge, Spells.FindAura(liste, idSchlüsselOderFamilie) → Aura,
                   Spells.BuffState(schlüsselOderKind, auren, opts) → "ok" | "missing" | "expiring", Aura, Schlüssel, Zauber-ID,
                   Spells.NoteAura(aura), Spells.AuraSeconds(idOderSchlüssel), Spells.BuffMinutes(schlüssel) → Minuten, Quelle,
                   Spells.IsLongBuff(idOderSchlüssel), Spells.FormActive(id) → true/false/nil, Spells.ActiveForm() → ID, 0, nil
                   Heilen, Bannen, Wiederbeleben (Welle 8): Spells.HealSpells(klasse, rolle) → Liste, Spells.DispelSpells(klasse,
                   art), Spells.DispelTypes(klasse) → { magic = true … }, Spells.ResurrectSpells(klasse),
                   Spells.BestKnown(liste) → höchster gelernter Rang der ersten gelernten ID, Spells.GroupReagent(id) →
                   Gegenstand, Spells.ItemAura(gegenstand) → Zauber-ID der Aura (Fläschchen, Elixier, Rolle),
                   Spells.MacroLogic(klasse) → Makro-Logik (MacroLogic.lua), Spells.MacroCondition(bedingung) → Text,
                   Spells.MacroCast(eintrag, opts) → Zauber-Teil der /cast-Zeile (Welle 23a)
      Client-Tabellen (Welle 26, Paket kern/wago-wissen; ezCore.ClientData, Quelle „laut Client-Tabellen“):
                   Spells.ClientComing(abStufe, bisStufe, klasse, volk) → { id, name, rank, level, base, icon, known,
                   pet, triggered, source = "tables" } (F3, für „Was kommt wann“ ohne Lehrerbesuch; Spells.Coming
                   bleibt unverändert; seit Welle 26 nur Zauber deines Volks; pet = true seit Welle 27: Lernzauber des
                   Begleiters, triggered = true: ausgelöste Zauber – beide zählen nicht als Rang des Spielers),
                   Spells.ClassOf(zauber) → Klasse, Quelle (Klasse eines Zaubers, Welle 26),
                   Spells.Reagents(zauber) → { { item, count } … } (F9), Spells.Tools(zauber) (F9),
                   Spells.ReagentNeeds/MissingReagents(zauber, rückfall), Spells.ReagentList/ReagentText(fehlt),
                   Spells.ReagentSource(quelle) – was für einen Zauber fehlt, mit Text und Quelle (Welle 26),
                   Spells.SharedCooldown(zauber) → { Zauber-ID … } derselben Kategorie (F10),
                   Spells.ImbueDuration(zauberOderSchlüssel) → Sekunden (Waffenzauber), Spells.ElixirItems(art) →
                   { [Gegenstand] = { kind, level, spell } } (A75, Fläschchen und Elixiere für ezBuff)
      Nachrichten  SPELLS_KNOWN_CHANGED (Zauberbuch neu gelesen), SPELLS_TRAINER_CHANGED (art)

    „art“ ist die Klasse des Spielers (z. B. "MAGE"), beim Tierausbilder bzw. Lehrer der Begleiter "KLASSE:PET"
    (Spells.PetKind; Wunsch des Nutzers 14.11.2026: „pets jäger und hexer und co sollten auch berücksichtigt werden“).
    Alles nur lesen: kein Wert wird in Blizzards Tabellen geschrieben, Lernen bleibt ein Klick des Spielers.
]]

local function PlayerClass()
    return Core.PlayerClass()
end

local function PlayerLevel()
    return Core.PlayerLevel() or 1
end

---------------------------------------------------------------------------
-- Zaubername
---------------------------------------------------------------------------

-- Zaubername in der Client-Sprache – die EINE Fassung (V-029, vorher eine zweite in Knowledge.lua; bis Welle 11 in
-- Util.lua, EC-53): C_Spell zuerst,
-- sonst das alte GetSpellInfo; nie ein Fehler, nil bei unbekanntem Zauber oder gesperrtem Namen.
function Core.SpellName(id)
    if Core.IsSecret(id) or id == nil then return nil end
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, value = pcall(C_Spell.GetSpellName, id)
        name = ok and Core.Plain(value) or nil
    end
    if type(name) ~= "string" or name == "" then
        local old = rawget(_G, "GetSpellInfo")
        if type(old) == "function" then
            local ok, value = pcall(old, id)
            name = ok and Core.Plain(value) or nil
        end
    end
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

---------------------------------------------------------------------------
-- Namen und Symbole
---------------------------------------------------------------------------

local nameCache = {}

-- Name aus dem Client (Client-Sprache), sonst der Ersatzname aus SpellData.lua.
-- Zweiter Wert: true, wenn der Name vom Client stammt.
function Spells.Name(id)
    id = tonumber(id)
    if not id then return nil, false end
    local cached = nameCache[id]
    if cached then return cached, true end
    local name = Core.SpellName(id)
    if type(name) == "string" and name ~= "" then
        nameCache[id] = name
        return name, true
    end
    local pair = Spells.FALLBACK[id]
    if pair then return (Core.IsGerman() and pair[1] or pair[2]) or pair[1], false end
    return nil, false
end

function Spells.Icon(id)
    id = tonumber(id)
    if not id then return nil end
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(id)
    elseif GetSpellTexture then
        icon = GetSpellTexture(id)
    end
    return Core.Plain(icon)
end

---------------------------------------------------------------------------
-- Ränge
---------------------------------------------------------------------------

-- „Rang 4“, „(Rank 4)“, „Rango 4“ … → 4. Andere Zusätze („Benötigt: Stufe 60“, „Passiv“) → nil.
function Spells.ParseRank(text)
    text = Core.Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    local word = type(RANK) == "string" and RANK ~= "" and RANK or nil
    if word then
        local n = text:match(word .. "%s*(%d+)")
        if n then return tonumber(n) end
    end
    local n = text:match("[Rr]ang%s*(%d+)") or text:match("[Rr]ank%s*(%d+)") or text:match("[Rr]ango%s*(%d+)")
    return n and tonumber(n) or nil
end

---------------------------------------------------------------------------
-- Bekannte Zauber aus dem Zauberbuch
---------------------------------------------------------------------------

local known = { byName = {}, byID = {}, future = {}, pet = nil, petByName = {}, dirty = true }
local auraIDs = {}          -- Zwischenspeicher für Spells.AuraIDs; leer, sobald das Zauberbuch neu gelesen wird

local function ReadSpellBook()
    local byName, byID, future = {}, {}, {}
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) or bank == nil then
        return byName, byID, future
    end
    local types = Enum.SpellBookItemType or {}
    for line = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local info = SB.GetSpellBookSkillLineInfo(line)
        local offset, count = info and Core.Num(info.itemIndexOffset), info and Core.Num(info.numSpellBookItems)
        if offset and count then
            for slot = offset + 1, offset + count do
                local item = SB.GetSpellBookItemInfo(slot, bank)
                local id = item and (Core.Num(item.spellID) or Core.Num(item.actionID))
                local name = item and Core.Plain(item.name)
                if id and type(name) == "string" and name ~= "" then
                    local level = SB.GetSpellBookItemLevelLearned and Core.Num(SB.GetSpellBookItemLevelLearned(slot, bank)) or nil
                    local rank = Spells.ParseRank(item.subName) or 0
                    if types.FutureSpell ~= nil and item.itemType == types.FutureSpell then
                        future[#future + 1] = { id = id, name = name, rank = rank, level = level, icon = Core.Plain(item.iconID) }
                    elseif types.Spell == nil or item.itemType == types.Spell then
                        local entry = byName[name]
                        if not entry then
                            entry = { name = name, ranks = {}, maxRank = -1 }
                            byName[name] = entry
                        end
                        entry.ranks[rank] = id
                        if rank > entry.maxRank then
                            entry.maxRank, entry.maxID, entry.level = rank, id, level
                        end
                        byID[id] = { name = name, rank = rank, level = level }
                    end
                end
            end
        end
    end
    table.sort(future, function(a, b) return (a.level or 0) < (b.level or 0) end)
    return byName, byID, future
end

-- Begleiter-Zauberbuch (Forever-Quelle: SpellBookPetCategoryMixin, Blizzard_SpellBookCategory.lua – Plätze
-- 1 … C_SpellBook.HasPetSpells() in der Bank Enum.SpellBookSpellBank.Pet). Form geprüft: ohne Schnittstelle, ohne
-- Begleiter oder bei gesperrten Angaben nil; sonst { { id, name, rank, icon } … } und { [Name] = höchster Rang }.
local function ReadPetBook()
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if not (SB and SB.HasPetSpells and SB.GetSpellBookItemInfo) or bank == nil then return nil, {} end
    local ok, count = pcall(SB.HasPetSpells)
    count = ok and Core.Num(count) or nil
    if not count or count <= 0 then return nil, {} end
    local list, byName = {}, {}
    for slot = 1, math.min(count, 100) do
        local okItem, item = pcall(SB.GetSpellBookItemInfo, slot, bank)
        if okItem and type(item) == "table" and not Core.IsSecret(item) then
            local id = Core.Num(Core.Peek(item, "spellID")) or Core.Num(Core.Peek(item, "actionID"))
            local name = Core.Plain(Core.Peek(item, "name"))
            if id and type(name) == "string" and name ~= "" then
                local rank = Spells.ParseRank(Core.Peek(item, "subName")) or 0
                list[#list + 1] = { id = id, name = name, rank = rank, icon = Core.Plain(Core.Peek(item, "iconID")) }
                if (byName[name] or -1) < rank then byName[name] = rank end
            end
        end
    end
    return list, byName
end

local function Ensure()
    if known.dirty then
        known.pet, known.petByName = ReadPetBook()
        known.byName, known.byID, known.future = ReadSpellBook()
        known.dirty = false
        auraIDs = {}
    end
    return known
end

-- Eintrag zu einem Zauber (Name oder ID): { name, ranks = { [Rang] = id }, maxRank, maxID, level } oder nil.
-- Rang 0 heißt: der Zauber hat keine Ränge.
function Spells.Known(nameOrID)
    local k = Ensure()
    local name = nameOrID
    if type(nameOrID) == "number" then
        local info = k.byID[nameOrID]
        name = info and info.name or Spells.Name(nameOrID)
    end
    return name and k.byName[name] or nil
end

-- Höchster bekannter Rang: ID und Rang (nil, wenn unbekannt).
function Spells.Highest(nameOrID)
    local entry = Spells.Known(nameOrID)
    if not entry then return nil end
    return entry.maxID, entry.maxRank
end

-- Rang eines Zaubers: aus dem Zauberbuch, sonst aus dem Zusatztext des Clients.
function Spells.Rank(id)
    id = tonumber(id)
    if not id then return nil end
    local info = Ensure().byID[id]
    if info then return info.rank end
    if C_Spell and C_Spell.GetSpellSubtext then
        return Spells.ParseRank(C_Spell.GetSpellSubtext(id))
    end
    return nil
end

-- Ist id ein niedrigerer Rang eines Zaubers, dessen höheren Rang der Spieler kennt?
function Spells.IsLowRank(id)
    id = tonumber(id)
    if not id then return false end
    local entry = Spells.Known(id)
    local rank = Spells.Rank(id)
    return entry ~= nil and rank ~= nil and rank < entry.maxRank
end

-- Kennt der Spieler diesen Rang (oder einen höheren)? Rang 0/nil: den Zauber überhaupt.
function Spells.KnowsRank(name, rank)
    local entry = name and Ensure().byName[name]
    if not entry then return false end
    rank = tonumber(rank) or 0
    return entry.ranks[rank] ~= nil or entry.maxRank >= rank
end

-- fn(entry) für jeden bekannten Zauber (alphabetisch).
function Spells.ForEachKnown(fn)
    local names = {}
    for name in pairs(Ensure().byName) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do fn(known.byName[name]) end
end

-- Zauber, die das Zauberbuch schon zeigt, aber noch nicht gelernt sind: { id, name, rank, level, icon }, nach Stufe.
function Spells.Future()
    return Ensure().future
end

-- Was beim Lehrer wartet – eine Rechnung für ezMerchant und ezPanel: Anzahl, Kosten, Quelle, Liste.
--   Lehrer schon besucht: aus seinen Daten (Kosten bekannt, Quelle "trainer").
--   Sonst aus dem Zauberbuch („kommt später“ bis zur Stufe; Kosten nil, Quelle "book").
-- Bei einer Begleiter-Art ohne Lehrerbesuch: 0, nil, "none" (das Zauberbuch des Spielers zählt dort nicht).
function Spells.Waiting(level, kind)
    level = Core.Num(level) or Core.Num(UnitLevel and UnitLevel("player")) or 1
    if Spells.TrainerSeen(kind) then
        local list, cost = Spells.Available(level, kind)
        list = type(list) == "table" and list or {}
        return #list, cost or 0, "trainer", list
    end
    if Spells.IsPetKind(kind) then return 0, nil, "none", {} end
    local count = 0
    for _, entry in ipairs((Spells.BookEntries())) do
        if (Core.Num(entry.level) or 0) <= level then count = count + 1 end
    end
    return count, nil, "book"
end

-- Kennt der Spieler (oder sein Begleiter) den Zauber? Bei Rängen genügt irgendein Rang (vorher ezMacro).
function Spells.IsKnown(id)
    id = tonumber(id)
    if not id then return false end
    local function Try(fn, ...)
        if type(fn) ~= "function" then return false end
        local ok, result = pcall(fn, ...)
        return ok and result == true
    end
    if Try(IsPlayerSpell, id) then return true end
    if Try(IsSpellKnown, id) or Try(IsSpellKnown, id, true) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if Try(C_SpellBook.IsSpellKnown, id) then return true end
        local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
        if pet and Try(C_SpellBook.IsSpellKnown, id, pet) then return true end
    end
    -- Höhere Ränge haben andere IDs: dann über den Namen.
    if Spells.Known(id) then return true end
    local name = Core.SpellName(id)
    if name and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        local ok, slot = pcall(C_SpellBook.FindSpellBookSlotForSpell, name)
        if ok and slot then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Lehrer: lernt bei jedem Besuch, was er anbietet (wie das Item-Wissen die Rezepte)
---------------------------------------------------------------------------

local function TrainerKind()
    local class = PlayerClass()
    if not class then return nil end
    local pet = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    if pet ~= nil and C_Trainer and C_Trainer.GetTrainerType then
        local ok, kind = pcall(C_Trainer.GetTrainerType)
        if ok and kind == pet then return class .. ":PET" end
    end
    return class
end

-- Umgezogen in die Entdecker-Datenbank? (DiscoveryLegacy.lua; speicher "trainer" bzw. "durations")
local function Moved(store)
    local D = Core.Discovery
    return D ~= nil and D.Moved ~= nil and D.Moved(store)
end

-- ezCoreDB.spells.trainer[Sprache][art] = { ["Name#Rang"] = { n, r, l, c, i, t }, seen = Zeit }. Umgezogen: dieselbe
-- Form zum Lesen aus offer (Discovery.TrainerStore); ezCoreDB.spells.trainer bleibt liegen.
local function TrainerStore(kind, create)
    local db = Core.db
    if type(db) ~= "table" or not kind then return nil end
    if not create and Moved("trainer") then return Core.Discovery.TrainerStore(kind) end
    if not db.spells and not create then return nil end
    db.spells = db.spells or {}
    db.spells.trainer = db.spells.trainer or {}
    local locale = GetLocale and GetLocale() or "enUS"
    local byLocale = db.spells.trainer[locale]
    if not byLocale then
        if not create then return nil end
        byLocale = {}
        db.spells.trainer[locale] = byLocale
    end
    if not byLocale[kind] and create then byLocale[kind] = { list = {} } end
    return byLocale[kind]
end

function Spells.ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return false end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    local kind = TrainerKind()
    if Moved("trainer") then
        -- ein Schreiber: das Angebot liest die Entdecker-Datenbank (Discovery.ScanTrainer)
        local found = Core.DB.AsOwn(Core.Discovery.ScanTrainer) == true   -- auch bei ausgeschaltetem Sammeln
        if found and kind then Core.Fire("SPELLS_TRAINER_CHANGED", kind) end
        return found
    end
    local store = TrainerStore(kind, true)
    if not store then return false end
    local now = time and time() or 0
    local found = 0
    for index = 1, GetNumTrainerServices() or 0 do
        local name, serviceType, icon, reqLevel, subText = GetTrainerServiceInfo(index)
        name, serviceType = Core.Plain(name), Core.Plain(serviceType)
        if type(name) == "string" and name ~= "" and serviceType and serviceType ~= "header" then
            local rank = Spells.ParseRank(subText) or 0
            local cost = GetTrainerServiceCost and Core.Num((GetTrainerServiceCost(index))) or 0
            store.list[name .. "#" .. rank] = {
                n = name, r = rank, l = Core.Num(reqLevel) or 1, c = cost or 0, i = Core.Plain(icon), t = now,
            }
            found = found + 1
        end
    end
    if found > 0 then
        store.seen = now
        Core.Fire("SPELLS_TRAINER_CHANGED", kind)
    end
    return found > 0
end

-- Kennt der Begleiter diesen Rang (oder einen höheren)? Aus dem Begleiter-Zauberbuch; ohne Begleiter false.
function Spells.PetKnowsRank(name, rank)
    local best = name and Ensure().petByName[name]
    return best ~= nil and best >= (tonumber(rank) or 0)
end

local function Entry(raw, pet)
    return { name = raw.n, rank = raw.r, level = raw.l, cost = raw.c, icon = raw.i, pet = pet or nil,
             known = Spells.KnowsRank(raw.n, raw.r) or (pet and Spells.PetKnowsRank(raw.n, raw.r)) or false }
end

local function SortEntries(list)
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.rank < b.rank
    end)
    return list
end

-- Alles, was dieser Lehrer je angeboten hat: { name, rank, level, cost, icon, known }, nach Stufe.
function Spells.Trainer(kind)
    kind = kind or PlayerClass()
    local store = TrainerStore(kind, false)
    local pet = Spells.IsPetKind(kind)
    local list = {}
    for _, raw in pairs(store and store.list or {}) do list[#list + 1] = Entry(raw, pet) end
    return SortEntries(list)
end

-- Wann der Lehrer zuletzt gelesen wurde (nil: noch nie – dann fehlen die Daten).
function Spells.TrainerSeen(kind)
    local store = TrainerStore(kind or PlayerClass(), false)
    return store and store.seen or nil
end

-- Jetzt lernbar (Stufe erreicht, noch nicht bekannt): Liste und Summe der Kosten.
function Spells.Available(level, kind)
    level = tonumber(level) or PlayerLevel()
    local list, total = {}, 0
    for _, entry in ipairs(Spells.Trainer(kind)) do
        if not entry.known and entry.level <= level then
            list[#list + 1] = entry
            total = total + (entry.cost or 0)
        end
    end
    return list, total
end

-- Kommt zwischen zwei Stufen dazu (abStufe ausgeschlossen, bisStufe eingeschlossen): Liste und Summe der Kosten.
function Spells.Upcoming(fromLevel, toLevel, kind)
    fromLevel = tonumber(fromLevel) or PlayerLevel()
    toLevel = tonumber(toLevel) or Core.MaxLevel()
    local list, total = {}, 0
    for _, entry in ipairs(Spells.Trainer(kind)) do
        if not entry.known and entry.level > fromLevel and entry.level <= toLevel then
            list[#list + 1] = entry
            total = total + (entry.cost or 0)
        end
    end
    return list, total
end

---------------------------------------------------------------------------
-- Begleiter-Fähigkeiten (EC-13, ST-18, DG-46): Quelle der Client (Begleiter-Zauberbuch) und das Lehrerfenster
-- (Tierausbilder: C_Trainer.GetTrainerType() == Enum.TrainerType.Pet, laut Forever-Quelle TrainerConstants).
-- Was ein Begleiter noch lernen kann, kennt nur der Lehrer: ohne Besuch nennt ezCore nur, was der Begleiter schon
-- kann, und PetStatus sagt, was fehlt (Leitlinie 11). Defensiv: jede Abfrage geschützt, Form geprüft.
---------------------------------------------------------------------------

-- Klassen mit Begleiter-Fähigkeiten (Jäger: Tierausbilder; Hexenmeister: Dämonen).
Spells.PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- Art der Begleiter-Fähigkeiten einer Klasse (Standard: eigene) für Trainer/Available/Upcoming/Waiting; sonst nil.
function Spells.PetKind(class)
    class = class or PlayerClass()
    if type(class) ~= "string" or not Spells.PET_CLASSES[class] then return nil end
    return class .. ":PET"
end

-- Ist art eine Begleiter-Art ("HUNTER:PET")?
function Spells.IsPetKind(kind)
    return type(kind) == "string" and kind:match(":PET$") ~= nil
end

-- Gelernte Begleiter-Zauber aus dem Begleiter-Zauberbuch: { { id, name, rank, icon } … }; nil ohne Begleiter bzw.
-- ohne Schnittstelle (Kopie).
function Spells.PetBook()
    local list = Ensure().pet
    if not list then return nil end
    local copy = {}
    for i, entry in ipairs(list) do copy[i] = { id = entry.id, name = entry.name, rank = entry.rank, icon = entry.icon } end
    return copy
end

-- Woher die Begleiter-Daten kommen: { kind, trainer = Zeit des letzten Lehrerbesuchs oder nil, book = Zahl der
-- Zauber im Begleiter-Zauberbuch oder nil, missing = "class" | "trainer" | nil }. „trainer“ heißt: ohne Besuch beim
-- Lehrer fehlen Kosten und Lernstufen (Hinweis an den Spieler).
function Spells.PetStatus(class)
    local kind = Spells.PetKind(class)
    if not kind then return { missing = "class" } end
    local pet = Ensure().pet
    local seen = Spells.TrainerSeen(kind)
    return { kind = kind, trainer = seen, book = pet and #pet or nil, missing = (not seen) and "trainer" or nil }
end

---------------------------------------------------------------------------
-- Zauber je Stufe aus dem Client (DG-40): C_SpellBook.GetCurrentLevelSpells(stufe) – laut Forever-Quelle
-- (SpellBookDocumentation) „general, class, and active spec spells that are learned at the specified level“, eine
-- Liste von Zauber-IDs, „MayReturnNothing“. Ränge sagt die Doku nicht zu: Form geprüft (nur Zahlen), der Rang kommt
-- aus dem Zusatztext des Clients. Wartet auf den Spieltest (DG-44); bis dahin bleibt alles wie heute, wenn nil kommt.
---------------------------------------------------------------------------

local levelCache = {}       -- [Stufe] = Liste; leer, sobald das Zauberbuch neu gelesen wird

-- Zauber-IDs, die man auf Stufe level lernt: Liste (Kopie) oder nil (Schnittstelle fehlt, nichts geliefert, falsche
-- Form oder gesperrt).
function Spells.LevelSpells(level)
    level = Core.Num(level)
    if not level or level < 1 then return nil end
    level = math.floor(level)
    local cached = levelCache[level]
    if cached == nil then
        cached = false
        local SB = C_SpellBook
        if SB and type(SB.GetCurrentLevelSpells) == "function" then
            local ok, ids = pcall(SB.GetCurrentLevelSpells, level)
            if ok and type(ids) == "table" and not Core.IsSecret(ids) then
                local list, valid = {}, true
                local okRead = pcall(function()
                    for _, id in ipairs(ids) do
                        local n = Core.Num(id)
                        if not n then valid = false break end
                        list[#list + 1] = n
                    end
                end)
                if okRead and valid then cached = list end
            end
        end
        levelCache[level] = cached
    end
    if not cached then return nil end
    local copy = {}
    for i, id in ipairs(cached) do copy[i] = id end
    return copy
end

-- Was zwischen zwei Stufen dazukommt (abStufe ausgeschlossen, bisStufe eingeschlossen; höchstens 80 Stufen) laut
-- Client: { { id, name, rank, level, icon, known, source = "client" } … } nach Stufe und Name, gelernte bleiben
-- drin (known = true). nil, wenn der Client für keine Stufe eine Liste liefert (dann gilt Future bzw. der Lehrer).
function Spells.Coming(fromLevel, toLevel)
    fromLevel = math.floor(Core.Num(fromLevel) or PlayerLevel())
    toLevel = math.floor(Core.Num(toLevel) or Core.MaxLevel() or fromLevel)
    toLevel = math.min(toLevel, fromLevel + 80)
    local list, any = {}, false
    for level = fromLevel + 1, toLevel do
        local ids = Spells.LevelSpells(level)
        if ids then
            any = true
            for _, id in ipairs(ids) do
                local name = Spells.Name(id)
                list[#list + 1] = { id = id, name = name or ("#" .. id), rank = Spells.Rank(id) or 0, level = level,
                    icon = Spells.Icon(id), known = Spells.IsKnown(id), source = "client" }
            end
        end
    end
    if not any then return nil end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.rank < b.rank
    end)
    return list
end

-- Welle 26 (F3, Paket kern/wago-wissen): was zwischen zwei Stufen dazukommt, laut Client-Tabellen (SkillLineAbility und
-- SpellLevels, ezCore.ClientData.ClassSpells) – auch ohne Lehrerbesuch und wenn C_SpellBook.GetCurrentLevelSpells
-- nichts liefert (Probe 14.11.2026: leer). Lehrer-Kosten führt der Client nicht (bleiben Erhebung beim Lehrer).
-- → { { id, name, rank, level, base, icon, known, source = "tables" } … } nach Stufe, Name, Rang (abStufe
-- ausgeschlossen, bisStufe eingeschlossen; Standard: von deiner Stufe bis zur Höchststufe, deine Klasse); nil ohne
-- Tabelle bzw. für eine Klasse ohne Einträge, {} für einen Bereich ohne neue Zauber (z. B. auf Höchststufe) – so
-- unterscheidet ein Abnehmer „keine Client-Tabelle“ (Rückfall auf Spells.Coming) von „nichts mehr zu lernen“.
-- Talentzauber (Rang 1) führt die Tabelle nicht. Name und Symbol aus dem Client, sonst „#ID“.
-- Welle 26 (Paket kern/ezcore-reste-24): nur Zauber deines Volks (Volksmaske aus SkillLineAbility – Priester-
-- Volkszauber, Teleporte und Portale der Magier je Fraktion); volk: Volk-ID statt des eigenen, false = alle Völker.
-- Ist das eigene Volk nicht zu ermitteln, bleiben alle (wie vorher).
function Spells.ClientComing(fromLevel, toLevel, class, race)
    local CD = Core.ClientData
    if not (CD and CD.ClassSpells) then return nil end
    fromLevel = math.floor(Core.Num(fromLevel) or PlayerLevel())
    toLevel = math.floor(Core.Num(toLevel) or Core.MaxLevel() or fromLevel)
    class = class or PlayerClass()
    if race == nil and CD.PlayerRace then race = CD.PlayerRace() end
    if race == false then race = nil end
    local entries = CD.ClassSpells(class, fromLevel, toLevel, race)
    if #entries == 0 then
        if #CD.ClassSpells(class) == 0 then return nil end
        return {}
    end
    local list = {}
    for _, e in ipairs(entries) do
        local name = Spells.Name(e.id)
        list[#list + 1] = { id = e.id, name = name or ("#" .. e.id), rank = e.rank, level = e.level, base = e.base,
            icon = Spells.Icon(e.id), known = Spells.IsKnown(e.id), pet = e.pet, triggered = e.triggered,
            source = "tables" }
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.rank < b.rank
    end)
    return list
end

-- Klasse eines Zaubers laut Client-Tabellen (Welle 26, Paket kern/ezcore-reste-24; ClientData.ClassSpell aus
-- SkillLineAbility): kein Aufruf des Clients nennt sie (Gegenprüfung des Spickzettels in ezCombat, Fund 4). Ein
-- Talentzauber Rang 1 steht nicht selbst in der Tabelle, aber als Grund-ID seiner höheren Ränge – dann gilt deren
-- Klasse. → Klassen-Token („MAGE“), Quelle als Text („laut Client-Tabellen (wago.tools, Build …)“) oder nil (unbekannt:
-- Volks-, Berufs- und Allgemeinzauber, nur in einem Rang geführte Talente, gesperrt, Tabelle fehlt).
local classOfBase      -- [Grund-ID] = Klasse, beim ersten Bedarf aus der Tabelle gebaut
function Spells.ClassOf(spellID)
    local CD = Core.ClientData
    if Core.IsSecret(spellID) or not (CD and CD.ClassSpell and CD.Table) then return nil end
    spellID = Core.Num(Core.Plain(spellID))
    if not spellID then return nil end
    local e = CD.ClassSpell(spellID)
    local class = e and e.class
    if not class then
        local data = CD.Table("classSpells")
        if type(data) ~= "table" then return nil end
        if not classOfBase then
            classOfBase = {}
            for _, token in ipairs(Core.SortedKeys(data)) do
                for _, row in pairs(type(data[token]) == "table" and data[token] or {}) do
                    local base = type(row) == "table" and Core.Num(row[2])
                    if base and not classOfBase[base] then classOfBase[base] = token end
                end
            end
        end
        class = classOfBase[spellID]
    end
    if not class then return nil end
    return class, CD.SourceText("classSpells")
end

-- Ohne Lehrerbesuch (Welle 23, A44; SSOT für Spells.Waiting, ezMerchant und ezPanel): die „kommt später“-Zauber
-- des Zauberbuchs (Spells.Future), ergänzt um die Zauber je Stufe laut Client (Spells.Coming von Stufe 0 bis zur
-- Höchststufe). Fehlt im Zauberbuch die Stufe, gilt die des Clients; was nur der Client nennt, kommt dazu
-- (client = true). Gelernte Ränge (mit Rang: genau dieser, Spells.KnowsRank) und unbenannte Zauber des Clients
-- bleiben weg. → { { id, name, rank, level, icon, client, tables } … } nach Stufe, Name, Rang; zweiter Wert: hat der
-- Client etwas geliefert? Ohne Client-Stufen und Client-Tabellen ist die Liste genau Spells.Future (als Kopie).
-- Welle 26 (Paket kern/ezcore-reste-24): dazu die Klassenzauber laut Client-Tabellen (Spells.ClientComing, nur dein
-- Volk) – Ränge, die nur die Tabellen kennen, zählen damit auch ohne Lehrerbesuch (tables = true; Reiter in ezMerchant,
-- ezPanel und der Hinweis beim Stufenaufstieg über Spells.Waiting). Nicht dabei: gelernte (genau diese ID oder der
-- Rang), unbenannte und höhere Ränge eines Talents, das du nicht hast (lernbar erst mit dem Talent). Schon bekannte
-- Einträge (gleiche ID, Name und Rang oder Name und Stufe – die Tabellen zählen Ränge über den englischen Namen)
-- bekommen nur eine fehlende Stufe. Dritter Wert: lieferten die Client-Tabellen etwas?
local function EntryKey(name, rank) return tostring(name) .. "#" .. (Core.Num(rank) or 0) end
local function ClientKnowsEntry(c)
    local rank = Core.Num(c.rank) or 0
    if rank > 0 and type(c.name) == "string" then return Spells.KnowsRank(c.name, rank) == true end
    return c.known == true
end
local function TableKnowsEntry(c)
    local exact, id = rawget(_G, "IsPlayerSpell"), Core.Num(c.id)
    if id and type(exact) == "function" then
        local ok, known = pcall(exact, id)
        if ok and known == true then return true end
    end
    return ClientKnowsEntry(c)
end
-- Höherer Rang eines Talents, dessen Rang 1 (aus dem Talentbaum) du nicht kannst: die Grund-ID steht nicht in der
-- Tabelle deiner Klasse.
local function TableTalentMissing(c)
    local base, id = Core.Num(c.base), Core.Num(c.id)
    if not base or base == id then return false end
    local CD = Core.ClientData
    if not (CD and CD.ClassSpell) or CD.ClassSpell(base, PlayerClass()) ~= nil then return false end
    return not Spells.IsKnown(base)
end

-- Zustand eines Eintrags der Client-Tabellen (Spells.ClientComing) für den Spieler: "open" (noch zu lernen), "known"
-- (gelernt: genau diese ID oder der Rang), "talent" (höherer Rang eines Talents, das du nicht hast), "skip" (unbenannt,
-- ohne Stufe, ein Lernzauber des Begleiters, pet = true – den lehrt der Tierausbilder dem Begleiter –, oder ein
-- ausgelöster Zauber, triggered = true – er kommt mit seinem Geschwister, kein Lehrer lehrt ihn).
local function TableEntryState(c)
    if type(c) ~= "table" or c.pet == true or c.triggered == true then return "skip" end
    local name = c.name
    if type(name) ~= "string" or name == "" or name:sub(1, 1) == "#" or not Core.Num(c.level) then return "skip" end
    if TableKnowsEntry(c) then return "known" end
    if TableTalentMissing(c) then return "talent" end
    return "open"
end

-- Welle 27 (Paket kern/review-454, Fund 4 des Reviews zu PR 454; SSOT für ezCore und ezMerchant): Ist ein Eintrag der
-- Client-Tabellen für dich noch offen – benannt, mit Stufe, kein Lernzauber des Begleiters, kein ausgelöster Zauber,
-- nicht gelernt und kein höherer Rang eines Talents, das du nicht hast? → true/false
function Spells.TableEntryOpen(c)
    return TableEntryState(c) == "open"
end

-- Die offenen Einträge einer Liste aus Spells.ClientComing (Spells.TableEntryOpen), in derselben Reihenfolge (die
-- Einträge selbst, keine Kopien). Welle 27 (Fund 2 des Reviews, geschärft nach der Gegenprüfung): Ausgelöste Zauber
-- kennzeichnet schon der Erzeuger (triggered, tools/wago_ausliefern.lua A.GroupRanks: ohne Kosten und globale
-- Abklingzeit neben einem Geschwister derselben Stufe mit einem von beidem – Blitzschlagschild 26364 neben 324,
-- Berührung der Schwäche 2943 neben 2652 …); sie zählen nicht als Rang und verschieben die Nummern nicht mehr. Hier
-- zählt zusätzlich nicht, was Namen, Stufe UND Rang mit einem gelernten Eintrag teilt: denselben Rang tragen nur
-- Einträge, von denen du den einen oder den anderen hast (Siegel der Rechtschaffenheit 21084 ersetzt den automatisch
-- gelernten 20154). Echte zweite Ränge derselben Stufe tragen eine eigene Nummer und bleiben offen (Feuerball 25306
-- neben 10151, Arkane Geschosse 25345 neben 10212, Verwandlung 28271/28272 neben 12826, Wasser herbeizaubern 468766
-- neben 10140, Gebet der Heilung 25316 neben 10961, Meucheln 25300 neben 11281, Feuerbrand 25309 neben 11668,
-- Schattenblitz 25307 neben 11661). Ohne Liste: {}.
local function SameRankKey(c) return c.name .. "@" .. Core.Num(c.level) .. "#" .. (Core.Num(c.rank) or 0) end
function Spells.OpenTableEntries(rows)
    local list, learnedAt, states = {}, {}, {}
    if type(rows) ~= "table" then return list end
    for i, c in ipairs(rows) do
        local state = TableEntryState(c)
        states[i] = state
        if state == "known" then learnedAt[SameRankKey(c)] = true end
    end
    for i, c in ipairs(rows) do
        if states[i] == "open" and not learnedAt[SameRankKey(c)] then list[#list + 1] = c end
    end
    return list
end

-- Zwischenspeicher für Spells.BookEntries (Welle 27, Fund 3 des Reviews: Spells.Waiting läuft ohne Lehrerbesuch bei
-- jedem PLAYER_XP_UPDATE, ezPanel/Blocks/XP.lua). Gültig, solange Stufe, Höchststufe, die Liste des Zauberbuchs
-- (Spells.Future – neu gelesen bei SPELLS_CHANGED, LEARNED_SPELL_IN_SKILL_LINE, PLAYER_LEVEL_UP), Klasse, Volk und die
-- Funktionen dahinter dieselben sind; verworfen bei jedem dieser Ereignisse, nach einem Lehrerbesuch
-- (SPELLS_TRAINER_CHANGED) und mit Spells.ForgetBookEntries(). Fehlten Namen (Client noch nicht bereit), gilt er
-- höchstens BOOK_RETRY Sekunden. Jeder Aufruf bekommt eine eigene Liste; die Einträge sind geteilt (nicht ändern).
local bookCache, bookGeneration = nil, 0
local BOOK_RETRY = 30
function Spells.ForgetBookEntries() bookGeneration = bookGeneration + 1 end

local function BookKey()
    local CD = Core.ClientData
    return { bookGeneration, PlayerLevel(), Core.MaxLevel(), Spells.Future, Spells.Future(), Spells.Coming,
        Spells.ClientComing, Spells.KnowsRank, Spells.IsKnown, rawget(_G, "IsPlayerSpell"), CD and CD.ClassSpell or false,
        PlayerClass() or false, CD and CD.PlayerRace and CD.PlayerRace() or false, Spells.Name }
end

local function SameKey(a, b)
    if not (a and b) then return false end
    for i = 1, 14 do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- flache Kopie: Core.CopyList (Gesamtreview 18.11.2026, T16-7; vorher zweimal in dieser Datei)
local CopyList = Core.CopyList

local BuildBookEntries
function Spells.BookEntries()
    local key = BookKey()
    local c = bookCache
    local now = type(GetTime) == "function" and GetTime() or nil
    if c and SameKey(c.key, key) and not (c.retry and (not now or now >= c.retry)) then
        return CopyList(c.list), c.client, c.tables
    end
    local list, client, tables, partial = BuildBookEntries()
    bookCache = { key = key, list = list, client = client, tables = tables,
        retry = partial and (now and now + BOOK_RETRY or 0) or nil }
    return CopyList(list), client, tables
end

BuildBookEntries = function()
    local list, byID, byKey, byLevel = {}, {}, {}, {}
    local partial = false
    local function Add(entry)
        list[#list + 1] = entry
        local id = Core.Num(entry.id)
        if id then byID[id] = entry end
        byKey[EntryKey(entry.name, entry.rank)] = entry
        local level = Core.Num(entry.level)
        if level then byLevel[tostring(entry.name) .. "@" .. level] = entry end
    end
    for _, e in ipairs(Spells.Future() or {}) do
        if type(e) == "table" then Add({ id = e.id, name = e.name, rank = e.rank, level = e.level, icon = e.icon }) end
    end
    local ok, coming = pcall(Spells.Coming, 0, Core.MaxLevel())
    local client = ok and type(coming) == "table"
    for _, c in ipairs(client and coming or {}) do
        local name = type(c) == "table" and c.name
        if type(name) == "string" and name:sub(1, 1) == "#" then partial = true end
        if type(name) == "string" and name ~= "" and name:sub(1, 1) ~= "#" and not ClientKnowsEntry(c) then
            local hit = byID[Core.Num(c.id) or -1] or byKey[EntryKey(name, c.rank)]
            if hit then
                if not Core.Num(hit.level) then hit.level = Core.Num(c.level) end
            else
                Add({ id = c.id, name = name, rank = c.rank, level = Core.Num(c.level), icon = c.icon, client = true })
            end
        end
    end
    local tables = false
    if type(Spells.ClientComing) == "function" then
        local okT, rows = pcall(Spells.ClientComing, 0, Core.MaxLevel())
        tables = okT and type(rows) == "table"
        for _, c in ipairs(tables and rows or {}) do
            if type(c) == "table" and type(c.name) == "string" and c.name:sub(1, 1) == "#" then partial = true end
        end
        for _, c in ipairs(tables and Spells.OpenTableEntries(rows) or {}) do
            local name, level = c.name, Core.Num(c.level)
            -- gleicher Name und gleiche Stufe nur, wenn der Eintrag keinen höheren Rang trägt (Feuerball 25306, Rang 12,
            -- gehört nicht zu Rang 11 aus dem Zauberbuch; Gegenprüfung des Reviews zu PR 454)
            local same = byLevel[name .. "@" .. level]
            local sameRank = same and Core.Num(same.rank) or 0
            if same and sameRank > 0 and (Core.Num(c.rank) or 0) > sameRank then same = nil end
            local hit = byID[Core.Num(c.id) or -1] or byKey[EntryKey(name, c.rank)] or same
            if hit then
                if not Core.Num(hit.level) then hit.level = level end
            else
                Add({ id = c.id, name = name, rank = c.rank, level = level, icon = c.icon, tables = true })
            end
        end
    end
    table.sort(list, function(a, b)
        local la, lb = Core.Num(a.level) or 0, Core.Num(b.level) or 0
        if la ~= lb then return la < lb end
        local na, nb = tostring(a.name), tostring(b.name)
        if na ~= nb then return na < nb end
        return (Core.Num(a.rank) or 0) < (Core.Num(b.rank) or 0)
    end)
    return list, client, tables, partial
end

---------------------------------------------------------------------------
-- Klassen-Fähigkeiten (vorher ezCombat)
---------------------------------------------------------------------------

-- Namen der Fähigkeiten einer Art für eine Klasse (Standard: eigene): { [Name] = spellID }.
function Spells.ClassSpellNames(kind, class)
    local list = Spells.CLASS[class or PlayerClass() or ""]
    local result = {}
    for _, id in ipairs(list and list[kind] or {}) do
        local name = Spells.Name(id)
        if name then result[name] = id end
    end
    return result
end

function Spells.IsExecute(id)
    return Spells.EXECUTE[tonumber(id) or 0] == true
end

---------------------------------------------------------------------------
-- Abfragen (vorher ezCombat): nie mit geheimen Werten rechnen
---------------------------------------------------------------------------

-- Zauberzeit in Sekunden, 0 wenn unbekannt oder sofort.
function Spells.CastTime(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spell)
        local castTime = ok and type(info) == "table" and Core.Num(info.castTime)
        if castTime then return castTime / 1000 end
    end
    return 0
end

-- Nutzbar? Zweiter Wert: nur die Kraft (Wut, Energie, Mana) fehlt. Dritter Wert: true, wenn die Antwort unbekannt
-- ist – das Spiel hat sie gesperrt oder die Abfrage selbst ist gescheitert (Fehler im pcall, Welle 23, A2); dann sind
-- die ersten beiden falsch und heißen „unbekannt“, nicht „nicht nutzbar“. Ohne Abfrage im Client: false, false.
function Spells.Usable(spell)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not fn then return false, false end
    local ok, usable, noPower = pcall(fn, spell)
    if not ok then return false, false, true end
    local locked = Core.IsSecret(usable) or Core.IsSecret(noPower)
    return Core.Plain(usable) == true, Core.Plain(noPower) == true, locked or nil
end

-- Längste globale Abklingzeit: Was nicht länger dauert, ist keine „echte“ Abklingzeit (vorher ezCombat).
Spells.GCD_MAX = 1.55

-- Art einer Abklingzeit: "none" (keine), "gcd" (nur die globale), "real" (echte Abklingzeit) oder nil (unbekannt).
-- Zuerst Start und Dauer (aus dem Aufruf oder aus info), sonst die Felder, die Blizzard nie sperrt
-- (SpellCooldownInfo.isActive und isOnGCD, laut Forever-Quelle „NeverSecret“) – der Rückfall, wenn das Spiel
-- Abklingzeiten im Kampf sperrt (SecretWhenCooldownsRestricted). Vorher ezCombat (ns.CooldownKind).
function Spells.CooldownKind(info, start, duration)
    start, duration = Core.Num(start), Core.Num(duration)
    if Core.IsSecret(info) or type(info) ~= "table" then info = nil end
    if not (start and duration) and info then
        start, duration = Core.Num(info.startTime), Core.Num(info.duration)
    end
    if start and duration then
        if start <= 0 or duration <= 0 or start + duration - GetTime() <= 0.05 then return "none" end
        if duration <= Spells.GCD_MAX then return "gcd" end
        return "real"
    end
    if not info then return nil end
    local active, onGCD = Core.Plain(info.isActive), Core.Plain(info.isOnGCD)
    if active == false then return "none" end
    if onGCD == true then return "gcd" end
    if active == true and onGCD == false then return "real" end
    return nil
end

-- Zauber der globalen Abklingzeit (Retail-Engine, laut Forever-Quelle in C_Spell nachfragbar). Die Client-Tabelle
-- SpellName des Produkts „wowf“ (Build 1.60.1.70938) führt 61304 nicht – ob C_Spell.GetSpellCooldown(61304) auf Forever
-- trotzdem antwortet, klärt der Spieltest (docs/roadmap/ezCore.md, „Im Spiel prüfen“); die wago-Prüfung nennt die
-- Kennung (Ausnahme „offen“ in tools/wago_ausnahmen.lua; Gesamtreview 18.11.2026, T14-NH3).
Spells.GCD_SPELL = 61304

-- Läuft gerade die globale Abklingzeit? true/false; nil, wenn das Spiel es nicht verrät. Über isActive bzw. isOnGCD
-- (laut Forever-Quelle nie gesperrt), sonst über Start und Dauer. Nutzer: Spells.LockedKind (ezCombat Readiness);
-- ezCombats Rest der globalen Abklingzeit (GcdLeft) fragt GCD_SPELL selbst.
function Spells.GCDActive()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, Spells.GCD_SPELL)
    if not ok or type(info) ~= "table" or Core.IsSecret(info) then return nil end
    local active = Core.Peek(info, "isActive")
    if type(active) == "boolean" and not Core.IsSecret(active) then return active end
    local start, duration = Core.Num(Core.Peek(info, "startTime")), Core.Num(Core.Peek(info, "duration"))
    if not (start and duration) then return nil end
    return start > 0 and duration > 0 and (start + duration) > Core.Uptime()
end

-- Blizzards Dauer-Objekt der Abklingzeit (C_Spell.GetSpellCooldownDuration; ohneGCD: ohne die globale); nil, wenn es
-- das nicht gibt oder es selbst gesperrt ist (dann darf es nicht weitergegeben werden). Vorher ezCombat (Readiness).
function Spells.DurationObject(spell, ignoreGCD)
    local api = C_Spell and C_Spell.GetSpellCooldownDuration
    if type(api) ~= "function" or Core.IsSecret(spell) or spell == nil then return nil end
    local ok, object = pcall(api, spell, ignoreGCD and true or false)
    if not ok or Core.IsSecret(object) or object == nil then return nil end
    return object
end

-- Gesperrte Werte, isActive = true, isOnGCD unbekannt: echte Abklingzeit oder nur die globale? "real", "gcd" oder nil
-- (Welle 23, A1; vorher ezCombat Readiness.LockedKind). Zuerst IsZero() des Dauer-Objekts ohne globale Abklingzeit
-- (null = nur die globale), sonst: läuft die globale Abklingzeit nicht (Spells.GCDActive() == false), ist es eine echte.
function Spells.LockedKind(spell)
    local object = Spells.DurationObject(spell, true)
    local isZero = object and object.IsZero
    if type(isZero) == "function" then
        local ok, zero = pcall(isZero, object)
        -- Erst prüfen, ob gesperrt (Core.Plain), dann vergleichen: Gesperrtes nie mit nil oder true vergleichen.
        if ok then zero = Core.Plain(zero) else zero = nil end
        if type(zero) == "boolean" then return zero and "gcd" or "real" end
    end
    if Spells.GCDActive() == false then return "real" end   -- der Zauber ruht, die globale Abklingzeit läuft nicht
    return nil
end

-- Läuft eine echte Abklingzeit (länger als die globale)? true/false. Zweiter Wert "secret", wenn Start und Dauer
-- gesperrt waren – dann entscheiden isActive und isOnGCD (nie gesperrt), und fehlt isOnGCD bei isActive = true,
-- Spells.LockedKind (Welle 23, A1); verraten auch die nichts: nil, "secret".
function Spells.OnCooldown(spell)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
    if not ok then return nil end
    if Core.IsSecret(info) then return nil, "secret" end
    if type(info) ~= "table" then return nil end
    local locked = not (Core.Num(info.startTime) and Core.Num(info.duration))
    local kind = Spells.CooldownKind(info)
    if kind == nil and locked and Core.Plain(info.isActive) == true then kind = Spells.LockedKind(spell) end
    if kind == nil then return nil, "secret" end
    if locked then return kind == "real", "secret" end
    return kind == "real"
end

-- Grund-Abklingzeit eines Zaubers in Sekunden (Welle 27, Paket modul/ezcombat-abklingzeit): Rechengrundlage, wenn ein
-- Modul eine gesperrte Abklingzeit selbst mitzählt (ezCombat). Quellen (Leitlinie 11): der Client – GetSpellBaseCooldown,
-- laut Probe vom 14.11.2026 auf Forever vorhanden, statische Daten ohne Talente – und die ausgelieferte Tabelle
-- (ClientData "cooldowns", Wissen/Client/Cooldowns.lua: die größere von RecoveryTime und CategoryRecoveryTime laut
-- Client-Tabellen). Es gilt der Client, wenn er mehr als 0 nennt (Client als SSOT, Entscheidung vom 13.11.2026); die
-- Tabelle nur, wenn er nichts liefert (fehlt, gesperrt) oder 0 nennt: Ob GetSpellBaseCooldown eine reine
-- Kategorie-Abklingzeit mitzählt (Heiliger Stoß hat nur sie, 667 Zauber in den Client-Tabellen ebenso), ist im Spiel
-- unbestätigt. Gesperrte Antworten zählen nicht (nie gerechnet). Talente, die die Abklingzeit verkürzen,
-- kennt keine der beiden Quellen – dafür hat der Aufrufer die offen gelesene Dauer.
-- spell: Zauber-ID oder Name eines gelernten Zaubers. → Sekunden (0 = keine eigene Abklingzeit), Quelle ("client" |
-- "tables"); nil nur ohne beide Quellen (dann ist die Dauer unbekannt).
function Spells.BaseCooldown(spell)
    if Core.IsSecret(spell) then return nil end
    local id = Core.Num(spell)
    if not id and type(spell) == "string" then
        local known = Spells.Known(spell)
        id = known and Core.Num(known.maxID)
        if not id and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spell)
            id = ok and type(info) == "table" and not Core.IsSecret(info) and Core.Num(Core.Peek(info, "spellID")) or nil
        end
    end
    if not id then return nil end
    local client
    local api = rawget(_G, "GetSpellBaseCooldown")
    if type(api) == "function" then
        local ok, ms = pcall(api, id)
        client = ok and not Core.IsSecret(ms) and Core.Num(ms) or nil
    end
    local data = Core.ClientData and Core.ClientData.Table and Core.ClientData.Table("cooldowns")
    local tables = type(data) == "table" and Core.Num(data[id]) or nil
    if client and client > 0 then return client / 1000, "client" end
    if tables then return tables / 1000, "tables" end
    if client then return 0, "client" end
    -- Die Tabelle führt jeden Zauber der Klassen, Talente und Volksfähigkeiten mit Abklingzeit: fehlt er dort, hat er keine.
    if type(data) == "table" then return 0, "tables" end
    return nil
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local announce = Core.Throttle(function()
    known.dirty = true
    Ensure()
    Core.Fire("SPELLS_KNOWN_CHANGED")
end, 0.2, ADDON)

for _, event in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP" }) do
    ns.On(event, function() known.dirty = true; levelCache = {}; Spells.ForgetBookEntries(); announce() end)
end
-- nach einem Lehrerbesuch neu zählen (Zwischenspeicher von Spells.BookEntries, Welle 27)
Core.Listen("SPELLS_TRAINER_CHANGED", function() Spells.ForgetBookEntries() end, ADDON)
-- Begleiter gerufen oder entlassen: das Begleiter-Zauberbuch neu lesen
ns.OnUnit("UNIT_PET", "player", function(_, unit)
    if Core.IsSecret(unit) or unit == "player" then known.dirty = true; announce() end
end)

local scanTrainer = Core.Throttle(function() Spells.ScanTrainer() end, 0.2, ADDON)
ns.On("TRAINER_SHOW", scanTrainer)
ns.On("TRAINER_UPDATE", scanTrainer)

---------------------------------------------------------------------------
-- Buff-Gruppen (ezBuff): welche Klasse welchen Buff gibt, welcher Rang zum Ziel passt
---------------------------------------------------------------------------

local buffByID, buffByName

local function PlayerSpell(id)
    if type(IsPlayerSpell) ~= "function" then return false end
    local ok, known = pcall(IsPlayerSpell, id)
    return ok and known == true
end

local function BuffIndex()
    if buffByID then return end
    buffByID, buffByName = {}, {}
    for key, d in pairs(Spells.BUFFS) do
        local function add(id)
            buffByID[id] = key
            local pair = Spells.FALLBACK[id]
            if pair then
                for _, n in ipairs(pair) do buffByName[n:lower()] = key end
            end
        end
        for _, id in ipairs(d.spells or {}) do add(id) end
        for _, id in ipairs(d.group or {}) do add(id) end
    end
end

-- Name einer Aura in der Client-Sprache → Gruppe. Der Client kennt die Namen erst nach und nach:
-- einmal alle lesen, und nur wenn welche fehlten, frühestens nach 30 Sekunden noch einmal.
local clientNamesDone, clientNamesAt = false, nil
local function KeyByClientName(name)
    local now = GetTime and GetTime() or 0
    if clientNamesDone or (clientNamesAt and now - clientNamesAt < 30) then return buffByName[name] end
    clientNamesAt, clientNamesDone = now, true
    for key, d in pairs(Spells.BUFFS) do
        for _, list in ipairs({ d.spells or {}, d.group or {} }) do
            for _, id in ipairs(list) do
                local clientName = Core.SpellName(id)
                if type(clientName) == "string" and clientName ~= "" then
                    buffByName[clientName:lower()] = key
                else
                    clientNamesDone = false
                end
            end
        end
    end
    return buffByName[name]
end

-- Gruppe einer Aura über Zauber-ID oder Namen ("int", "wellFed", "cozyFire" …), sonst nil.
function Spells.BuffKey(value)
    BuffIndex()
    if Core.IsSecret(value) then return nil end
    local id = tonumber(value)
    if id then return buffByID[id] end
    if type(value) ~= "string" or value == "" then return nil end
    local name = value:lower()
    return buffByName[name] or KeyByClientName(name)
end

-- Buffs einer Klasse in fester Reihenfolge: { { key, target, kind, spells, levels, missing } } (missing: Kennzeichen
-- aus BUFFS, etwa "forever" – Spells.BuffMissing sagt, ob es noch gilt).
function Spells.ClassBuffs(class)
    local out = {}
    if Core.IsSecret(class) then return out end
    class = class or PlayerClass()
    for _, key in ipairs(Spells.BUFF_ORDER) do
        local d = Spells.BUFFS[key]
        if d and d.class == class then
            out[#out + 1] = { key = key, target = d.target, kind = d.kind, spells = d.spells, levels = d.levels,
                missing = d.missing }
        end
    end
    return out
end

-- Fehlt der Buff im Client (Welle 23, A72)? true nur, wenn BUFFS ihn als fehlend kennzeichnet (missing) und der
-- Client keinen seiner Ränge und keine Gruppenfassung kennt (Spells.Exists); kennt er einen, gilt der Buff wieder.
-- false für alle anderen Buffs, nil für einen unbekannten Schlüssel.
function Spells.BuffMissing(key)
    if Core.IsSecret(key) then return nil end
    local d = type(key) == "string" and Spells.BUFFS[key]
    if not d then return nil end
    if not d.missing then return false end
    for _, list in ipairs({ d.spells or {}, d.group or {} }) do
        for _, id in ipairs(list) do
            if Spells.Exists(id) then return false end
        end
    end
    return true
end

-- Waffenzauber einer Klasse (Welle 23, A74; Standard: eigene): { { key, spells, levels } … } als Kopie, leer für
-- Klassen ohne. Daten in SpellData.lua (Spells.WEAPON_IMBUES).
-- Die Lernstufen kommen aus der ausgelieferten Client-Tabelle (ClientData.ClassSpell; Gesamtreview 18.11.2026, T14-NH6),
-- levels aus SpellData.lua nur als Rückfall je Rang, wenn die Tabelle den Rang nicht kennt.
function Spells.WeaponImbues(class)
    class = class or PlayerClass()
    local out = {}
    local CD = Core.ClientData
    for _, entry in ipairs((Spells.WEAPON_IMBUES or {})[class or ""] or {}) do
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        local levels = {}
        for i, id in ipairs(entry.spells or {}) do
            local e = CD and CD.ClassSpell and CD.ClassSpell(id, class)
            local level = e and Core.Num(e.level)
            levels[i] = (level and level > 0) and level or (entry.levels and entry.levels[i]) or nil
        end
        copy.levels = levels
        out[#out + 1] = copy
    end
    return out
end

-- Höchster gelernter Rang (Zauber-ID) eines Waffenzaubers ("rockbiter", "flametongue", "frostbrand", "windfury");
-- nil, wenn keiner gelernt oder der Schlüssel unbekannt ist.
function Spells.BestImbueRank(key)
    if Core.IsSecret(key) or type(key) ~= "string" then return nil end
    for _, list in pairs(Spells.WEAPON_IMBUES or {}) do
        for _, entry in ipairs(list) do
            if entry.key == key then
                local best
                for _, id in ipairs(entry.spells) do
                    if PlayerSpell(id) or Spells.IsKnownRank(id) then best = id end
                end
                return best
            end
        end
    end
    return nil
end

-- Dauer eines Waffenzaubers in Sekunden laut Client-Tabellen (Welle 26, Nachtrag A75; SpellItemEnchantment.Duration der
-- Verzauberung, die der Zauber anlegt – auf Forever 3600 s für die Waffenzauber des Schamanen). Nimmt eine Zauber-ID
-- oder einen Schlüssel aus Spells.WEAPON_IMBUES (dann der höchste gelernte Rang, sonst Rang 1). Auch Gifte und
-- Wetzsteine (Zauber des Gegenstands). → Sekunden, Quelle ("tables") oder nil
function Spells.ImbueDuration(spellOrKey)
    local CD = Core.ClientData
    if not (CD and CD.EnchantDuration) or Core.IsSecret(spellOrKey) then return nil end
    local id = Core.Num(spellOrKey)
    if not id and type(spellOrKey) == "string" then
        id = Spells.BestImbueRank(spellOrKey)
        if not id then
            for _, list in pairs(Spells.WEAPON_IMBUES or {}) do
                for _, entry in ipairs(list) do
                    if entry.key == spellOrKey then id = entry.spells[1] end
                end
            end
        end
    end
    local seconds = id and CD.EnchantDuration(id)
    if seconds then return seconds, "tables" end
    return nil
end

-- Höchster gelernter Rang (Zauber-ID), den ein Ziel der Stufe level annimmt; ohne level für dich selbst.
function Spells.BestBuffRank(key, level)
    if Core.IsSecret(key) or Core.IsSecret(level) or type(key) ~= "string" then return nil end
    local d = Spells.BUFFS[key]
    if not (d and d.spells) then return nil end
    level = tonumber(level)
    local best
    for i, id in ipairs(d.spells) do
        local need = d.levels and d.levels[i] or 1
        if (not level or level >= need - 10) and (PlayerSpell(id) or Spells.IsKnownRank(id)) then
            best = id
        end
    end
    return best
end

-- Genau dieser Rang gelernt? IsKnown genügt nicht: es nimmt bei Rängen irgendeinen.
function Spells.IsKnownRank(id)
    local entry = Spells.Known(id)
    local rank = Spells.Rank(id)
    if entry and rank and entry.ranks then return entry.ranks[rank] ~= nil or (entry.maxRank or 0) >= rank end
    return false
end

-- Daten einer Gruppe als Kopie: { key, class, target, kind, spells, levels, group, cast, reagent }.
function Spells.BuffInfo(key)
    if Core.IsSecret(key) or type(key) ~= "string" then return nil end
    local d = Spells.BUFFS[key]
    if not d then return nil end
    local out = { key = key }
    for k, v in pairs(d) do out[k] = v end
    return out
end

-- Leseschnittstelle des Buff-Wissens (F7 „Enterprise-Weg“, Entscheidung des Nutzers vom 16.11.2026; Welle 27): Module
-- (ezBuff, ezHeal, ezCombat …) lesen die Rohtabellen Spells.BUFFS, BUFF_ORDER und BUFF_PRIORITY nicht selbst, sondern
-- nur über diese Funktionen und die übrigen Buff-Abfragen (BuffKey, BuffInfo, ClassBuffs, BuffGroup, ChooseBuff,
-- BestBuffRank, BuffState …). Listen in den Antworten (spells, levels, group …) gehören ezCore: nicht verändern.
-- ezCore/Tests/buffs27_test.lua hält die Regel (Suche über alle Module samt ihren Tests).

-- Gibt es den Buff-Schlüssel? ("int" ja; "blessing" nein – das ist ein kind, siehe Spells.BuffGroup) → true/false
function Spells.IsBuff(key)
    if Core.IsSecret(key) or type(key) ~= "string" then return false end
    return Spells.BUFFS[key] ~= nil
end

-- Ein Feld eines Buffs ohne Kopie des ganzen Eintrags (für häufige Abfragen): class, target, kind, spells, levels,
-- group, groupLevels, cast, reagent, replaces, keepChoice, manual, missing, fallback … → Wert oder nil (auch bei
-- unbekanntem Schlüssel oder Feld).
function Spells.BuffField(key, field)
    if not Spells.IsBuff(key) or Core.IsSecret(field) or type(field) ~= "string" then return nil end
    return Spells.BUFFS[key][field]
end

-- Buff-Schlüssel als neue Liste. class (z. B. "MAGE"): die Klassen-Buffs dieser Klasse in fester Reihenfolge
-- (BUFF_ORDER); ohne class: die Klassen-Buffs aller Klassen in dieser Reihenfolge. others = true hängt (nur ohne class)
-- die Buffs ohne Klasse an (Satt, Lagerfeuer …; nach Schlüssel sortiert).
function Spells.BuffKeys(class, others)
    if Core.IsSecret(class) then return {} end
    local out, seen = {}, {}
    for _, key in ipairs(Spells.BUFF_ORDER) do
        local d = Spells.BUFFS[key]
        if d and d.class and (class == nil or d.class == class) and not seen[key] then
            out[#out + 1], seen[key] = key, true
        end
    end
    if class == nil and others then
        local rest = {}
        for key, d in pairs(Spells.BUFFS) do
            if not seen[key] and not d.class then rest[#rest + 1] = key end
        end
        table.sort(rest)
        for _, key in ipairs(rest) do out[#out + 1] = key end
    end
    return out
end

---------------------------------------------------------------------------
-- Klassen-Wissen (für ezCombat, ezBuff, ezMacro, ezHeal, ezTalent): nur Daten und Abfragen, keine Anzeige.
-- Der Client ist die Quelle (Name, Ränge, gelernt, Lernstufe, Reichweite, Dauer der laufenden Aura, Gestalt);
-- SpellData.lua nennt nur Zauber-IDs, Gruppen, Ersetzungen und gekennzeichnete Rückfälle.
-- Jede Antwort ist wahr, falsch oder unbekannt (nil) – unbekannt heißt für den Aufrufer: nichts verlangen.
---------------------------------------------------------------------------

-- Kennt der Client diese Zauber-ID? (C_Spell.DoesSpellExist, sonst: hat sie einen Namen)
function Spells.Exists(id)
    id = tonumber(id)
    if not id then return false end
    local api = C_Spell and C_Spell.DoesSpellExist
    if type(api) == "function" then
        local ok, there = pcall(api, id)
        there = Core.Plain(there)
        if ok and type(there) == "boolean" then return there end
    end
    local name = Core.SpellName(id)
    return type(name) == "string" and name ~= ""
end

-- Stufe, ab der man den Zauber lernt, und woher sie stammt: "client" (C_Spell.GetSpellLevelLearned), "book"
-- (Zauberbuch, auch „kommt später“), "trainer" (gemerkte Lehrer-Daten), "fallback" (BUFFS[…].levels bzw. groupLevels);
-- sonst nil.
function Spells.LevelLearned(id)
    if Core.IsSecret(id) then return nil end
    id = tonumber(id)
    if not id then return nil end
    local level = Core.Num((Core.Call(C_Spell and C_Spell.GetSpellLevelLearned, id)))
    if level and level > 0 then return level, "client" end
    local k = Ensure()
    local info = k.byID[id]
    if info and info.level and info.level > 0 then return info.level, "book" end
    for _, entry in ipairs(k.future) do
        if entry.id == id and entry.level and entry.level > 0 then return entry.level, "book" end
    end
    local name = Spells.Name(id)
    local store = TrainerStore(PlayerClass(), false)
    local raw = name and store and store.list and store.list[name .. "#" .. (Spells.Rank(id) or 0)]
    if raw and Core.Num(raw.l) then return raw.l, "trainer" end
    local key = Spells.BuffKey(id)
    local d = key and Spells.BUFFS[key]
    if d and d.levels then
        for i, spell in ipairs(d.spells) do
            if spell == id and d.levels[i] then return d.levels[i], "fallback" end
        end
    end
    -- Gruppenfassungen: groupLevels (wago.tools, SpellLevels; SpellData.lua), dieselbe Reihenfolge wie group
    if d and d.groupLevels then
        for i, spell in ipairs(d.group or {}) do
            if spell == id and d.groupLevels[i] then return d.groupLevels[i], "fallback" end
        end
    end
    return nil
end

-- Ist die Einheit (Standard: das Ziel) in Reichweite des Zaubers? true/false; nil = unbekannt (kein Ziel, der
-- Zauber braucht keines, gesperrt). C_Spell.IsSpellInRange ist laut Forever-Quelle nie gesperrt.
function Spells.InRange(spell, unit)
    local api = C_Spell and C_Spell.IsSpellInRange
    -- Leitlinie 6: zuerst IsSecret – ein gesperrter Wert darf nicht einmal mit nil verglichen werden.
    if type(api) ~= "function" or Core.IsSecret(spell) or Core.IsSecret(unit) or spell == nil then return nil end
    local ok, result = pcall(api, spell, unit or "target")
    if not ok or Core.IsSecret(result) then return nil end
    if result == true or result == 1 then return true end
    if result == false or result == 0 then return false end
    return nil
end

-- Wird der Zauber gerade gewirkt oder ist er eingereiht (nächster Schlag, Dauerfeuer)? C_Spell.IsCurrentSpell.
function Spells.IsCurrent(spell)
    local api = C_Spell and C_Spell.IsCurrentSpell
    if type(api) ~= "function" or Core.IsSecret(spell) or spell == nil then return false end
    local ok, result = pcall(api, spell)
    return ok and Core.Plain(result) == true
end

---------------------------------------------------------------------------
-- Familien (Spells.FAMILIES): Siegel, Aspekte, Haltungen, Flüche …
---------------------------------------------------------------------------

local familyByID

-- IDs einer Familie (Kopie) und ihre Daten { class, unit, form, spells }; nil, wenn es sie nicht gibt.
function Spells.Family(name)
    local d = type(name) == "string" and Spells.FAMILIES[name] or nil
    if not d then return nil end
    local ids = {}
    for i, id in ipairs(d.spells) do ids[i] = id end
    return ids, d
end

-- Familie eines Zaubers: über die ID, sonst über den Namen (höhere Ränge tragen andere IDs). → Name oder nil
function Spells.FamilyOf(id)
    id = tonumber(id)
    if not id then return nil end
    if not familyByID then
        familyByID = {}
        for family, d in pairs(Spells.FAMILIES) do
            for _, spell in ipairs(d.spells) do familyByID[spell] = family end
        end
    end
    if familyByID[id] then return familyByID[id] end
    local name = Spells.Name(id)
    if not name then return nil end
    for spell, family in pairs(familyByID) do
        if Spells.Name(spell) == name then return family end
    end
    return nil
end

---------------------------------------------------------------------------
-- Buff-Wahl: welcher Buff einer Gruppe ist der richtige (Dämonenrüstung löst Dämonenhaut ab)
---------------------------------------------------------------------------

-- Wahlgruppe zu einem Buff-Schlüssel oder einem kind: { id, kind, class, keys = { … } } – alle Einträge gleichen
-- kind derselben Klasse in der Reihenfolge von BUFF_ORDER (id = kind), bzw. der einzelne Buff ohne kind
-- (id = Schlüssel). Dieselbe Zusammenfassung wie in ezBuff. nil, wenn unbekannt.
function Spells.BuffGroup(value, class)
    if Core.IsSecret(value) or Core.IsSecret(class) or type(value) ~= "string" then return nil end
    local d = Spells.BUFFS[value]
    local kind
    if d then
        if not d.kind then return { id = value, class = d.class, keys = { value } } end
        kind, class = d.kind, d.class
    else
        kind, class = value, class or PlayerClass()
    end
    local keys = {}
    for _, key in ipairs(Spells.BUFF_ORDER) do
        local entry = Spells.BUFFS[key]
        if entry and entry.kind == kind and entry.class == class then keys[#keys + 1] = key end
    end
    if #keys == 0 then return nil end
    return { id = kind, kind = kind, class = class, keys = keys }
end

-- Der Buff einer Gruppe, den der Spieler wirken soll: Schlüssel und Zauber-ID (höchster gelernter Rang).
--   Kandidaten = gelernte Einträge der Gruppe, die kein gelernter Eintrag ablöst (replaces). Trägt der ablösende
--   Eintrag keepChoice, bleibt der abgelöste als gemerkte Wahl (opts.prefer) Kandidat.
--   opts.prefer (gemerkte Wahl) gewinnt nur, wenn sie Kandidat ist; sonst der letzte Kandidat in BUFF_ORDER, der
--   nicht manual ist (nur als gemerkte Wahl: Segen der Weisheit …); gibt es keinen solchen, der letzte Kandidat.
--   opts.class (bei einem kind: Klasse, Standard die eigene), opts.level (Stufe des Ziels, für BestBuffRank).
-- nil, wenn nichts aus der Gruppe gelernt ist.
function Spells.ChooseBuff(value, opts)
    opts = type(opts) == "table" and opts or {}
    local group = Spells.BuffGroup(value, opts.class)
    if not group then return nil end
    local rank, replaced = {}, {}
    for _, key in ipairs(group.keys) do
        rank[key] = Spells.BestBuffRank(key, opts.level)
    end
    for _, key in ipairs(group.keys) do
        local entry = Spells.BUFFS[key]
        local old = entry.replaces
        if rank[key] and old and not (entry.keepChoice and old == opts.prefer) then replaced[old] = true end
    end
    local inGroup = {}
    for _, key in ipairs(group.keys) do inGroup[key] = true end
    local function Candidate(key) return inGroup[key] and rank[key] and not replaced[key] end
    if not Core.IsSecret(opts.prefer) and opts.prefer ~= nil and Candidate(opts.prefer) then
        return opts.prefer, rank[opts.prefer]
    end
    -- Vorrang je Klasse (Spells.BUFF_PRIORITY, CB-34) bzw. opts.priority
    local priority = opts.priority
    if type(priority) ~= "table" and group.kind then
        local byKind = Spells.BUFF_PRIORITY and Spells.BUFF_PRIORITY[group.kind]
        priority = byKind and byKind[group.class]
    end
    if type(priority) == "table" then
        for _, key in ipairs(priority) do
            if Candidate(key) and not Spells.BUFFS[key].manual then return key, rank[key] end
        end
    end
    local chosen, anyCandidate
    for _, key in ipairs(group.keys) do
        if Candidate(key) then
            anyCandidate = key
            if not Spells.BUFFS[key].manual then chosen = key end
        end
    end
    chosen = chosen or anyCandidate
    if chosen then return chosen, rank[chosen] end
    return nil
end

---------------------------------------------------------------------------
-- Heilen, Bannen, Wiederbeleben (EC-110, ST-16): Gruppen aus SpellData.lua, „gelernt“ und Rang vom Client
---------------------------------------------------------------------------

-- flache Kopie wie oben (Core.CopyList)

-- Zauber-IDs einer Heil-Rolle ("fast", "big", "hot", "shield", "group", "emergency") einer Klasse (Standard: eigene).
-- Ohne Rolle: { [Rolle] = Liste } (Kopie). Unbekannt: leere Liste bzw. leere Tabelle.
function Spells.HealSpells(class, role)
    local data = Spells.HEALS[class or PlayerClass() or ""]
    if role == nil then
        local out = {}
        for key, list in pairs(data or {}) do out[key] = CopyList(list) end
        return out
    end
    return CopyList(data and data[role])
end

-- Bann-Zauber einer Klasse für eine Art ("magic", "curse", "poison", "disease"); ohne Art alle Arten.
function Spells.DispelSpells(class, kind)
    if Core.IsSecret(kind) or Core.IsSecret(class) then return {} end
    local data = Spells.DISPELS[class or PlayerClass() or ""]
    if kind == nil then
        local out = {}
        for key, list in pairs(data or {}) do out[key] = CopyList(list) end
        return out
    end
    if type(kind) ~= "string" then return {} end
    return CopyList(data and data[kind:lower()])
end

-- Welche Arten kann die Klasse bannen? { magic = true, … } – bei known = true nur mit gelerntem Zauber.
function Spells.DispelTypes(class, known)
    local out = {}
    for kind, list in pairs(Spells.DISPELS[class or PlayerClass() or ""] or {}) do
        if not known or Spells.BestKnown(list) then out[kind] = true end
    end
    return out
end

-- Wiederbelebungs-Zauber einer Klasse (Liste) und ob einer auch im Kampf geht.
function Spells.ResurrectSpells(class)
    local data = Spells.RESURRECTS[class or PlayerClass() or ""]
    return CopyList(data), data ~= nil and data.combat == true
end

-- Erste gelernte ID einer Ersatz-Liste, als höchster gelernter Rang: Zauber-ID, Rang; nil, wenn keine gelernt ist.
function Spells.BestKnown(list)
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if Spells.IsKnown(id) then
            local best, rank = Spells.Highest(id)
            return best or id, rank
        end
    end
    return nil
end

-- Gruppenfassungen aus BUFFS (group) als Menge, beim ersten Aufruf gebaut
local groupSpells
local function IsGroupSpell(id)
    if not groupSpells then
        groupSpells = {}
        for _, d in pairs(Spells.BUFFS or {}) do
            for _, spell in ipairs(type(d.group) == "table" and d.group or {}) do groupSpells[spell] = true end
        end
    end
    return groupSpells[id] == true
end

-- Reagenz einer Gruppenfassung (Arkane Brillanz → Arkanes Pulver): Gegenstands-ID oder nil, dazu die Quelle. Zuerst
-- die Client-Tabelle (Spells.Reagents, erstes Reagenz; Quelle "tables"), sonst die Liste Spells.GROUP_REAGENTS ("list";
-- Gesamtreview 18.11.2026, T14-NH6 – Leitlinie 10: liefert der Client die Fakten, gelten sie vor der Handliste). Nur
-- für Gruppenfassungen (BUFFS[…].group bzw. die Liste); andere Zauber → nil wie bisher. Spells.ReagentNeeds fragt
-- Spells.Reagents selbst zuerst und ruft GroupReagent nur ohne Tabelle – dort gilt immer die Liste; der Zweig "tables"
-- dient direkten Aufrufern (Gegenprüfung des Pakets kern/wago-pruefung).
function Spells.GroupReagent(spellID)
    spellID = Core.Num(Core.Plain(spellID))
    if not spellID then return nil end
    local listed = Spells.GROUP_REAGENTS[spellID]
    if not (listed or IsGroupSpell(spellID)) then return nil end
    local reagents = Spells.Reagents(spellID)
    local first = type(reagents) == "table" and type(reagents[1]) == "table" and Core.Num(reagents[1].item) or nil
    if first then return first, "tables" end
    if listed then return listed, "list" end
    return nil
end

-- Aura eines Gegenstands (Fläschchen, Elixier, Rolle, Waffenverzauberung): die Zauber-ID, die der Client dem
-- Gegenstand zuordnet (C_Item.GetItemSpell) – über sie findet Spells.FindAura die laufende Aura. nil ohne Antwort.
-- (Ohne Antwort des Clients nennt Spells.ElixirItems die Aura laut Client-Tabellen – getrennt, damit der Aufrufer
-- weiß, woher sie stammt.)
function Spells.ItemAura(itemID)
    itemID = Core.Num(Core.Plain(itemID))
    if not itemID then return nil end
    local api = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
    if type(api) ~= "function" then return nil end
    local ok, _, spellID = pcall(api, itemID)
    if not ok or Core.IsSecret(spellID) then return nil end
    return Core.Num(spellID)
end

-- Fläschchen und Elixiere laut Client-Tabellen (Welle 26, A75; Item-Klasse 0, Unterklasse 2/3) für ezBuffs
-- Check.LearnElixirs – auch ohne Besitz. art: "flask" | "elixir" | nil (beide). Die Aura kommt aus ItemXItemEffect
-- (Rückfall über den englischen Namen); im Spiel gilt zuerst Spells.ItemAura (C_Item.GetItemSpell).
-- → { [Gegenstand] = { kind, level (nötige Stufe), spell (Aura; 0 = keine Aura, etwa Trank der Giftreinigung) } }
function Spells.ElixirItems(kind)
    local CD = Core.ClientData
    return CD and CD.Consumables and CD.Consumables(kind) or {}
end

-- Reagenzien und Werkzeuge eines Zaubers laut Client-Tabellen (Welle 26, F9; SpellReagents, SpellTotems – nur
-- Klassenzauber). Spells.GroupReagent bleibt die Auswahl für Gruppenfassungen (dieselben Gegenstände).
-- → { { item, count } … } bzw. { categories = { Totem-Kategorie … }, items = { Gegenstand … } } oder nil
function Spells.Reagents(spellID)
    local CD = Core.ClientData
    return CD and CD.Reagents and CD.Reagents(spellID) or nil
end

function Spells.Tools(spellID)
    local CD = Core.ClientData
    return CD and CD.Tools and CD.Tools(spellID) or nil
end

-- „Was fehlt für diesen Zauber?“ (Welle 26, Paket kern/ezcore-reste-24; vorher je eine Rechnung in ezBuff
-- Check.ReagentNeeds/MissingReagents und ezMacro OneKey.MissingReagents – Leitlinie 2). Bedarf laut Client-Tabellen
-- (Spells.Reagents, Spells.Tools; ein Werkzeug als Gegenstand zählt wie ein Reagenz mit Anzahl 1, Totem-Kategorien
-- nennt der Client nicht je Gegenstand), Anzahl über Blizzards API (Core.ItemCount). Kennen die Tabellen den Zauber
-- nicht, gilt der Rückfall: rückfall = Gegenstand des Aufrufers (Quelle „list“, den Text dazu nennt der Aufrufer),
-- ohne rückfall ezCores Liste der Gruppenfassungen (Spells.GroupReagent), rückfall = false: keiner.
--   Spells.ReagentNeeds(zauber, rückfall) → { { item, need, tool } … } (leer, wenn nichts), Quelle "tables" | "list" | nil
--   Spells.MissingReagents(zauber, rückfall) → { { item, need, have, tool } … } oder nil (nichts fehlt), Quelle
--   Spells.ReagentList(fehlt) → „Arkanes Pulver (0 von 1), …“ (Name vom Client, sonst „#ID“)
--   Spells.ReagentText(fehlt) → „Dir fehlt: …“
--   Spells.ReagentSource(quelle, listenText) → „Bedarf laut Client-Tabellen (…), Anzahl aus deinen Taschen“; für „list“
--     listenText, sonst ezCores Satz zur Liste der Gruppenfassungen
function Spells.ReagentNeeds(spellID, fallback)
    local needs = {}
    if Core.IsSecret(spellID) then return needs end
    spellID = Core.Num(Core.Plain(spellID))
    if not spellID then return needs end
    local reagents, tools = Spells.Reagents(spellID), Spells.Tools(spellID)
    if type(reagents) == "table" or type(tools) == "table" then
        for _, r in ipairs(type(reagents) == "table" and reagents or {}) do
            local item = type(r) == "table" and Core.Num(r.item)
            if item then needs[#needs + 1] = { item = item, need = math.max(1, Core.Num(r.count) or 1) } end
        end
        for _, item in ipairs(type(tools) == "table" and type(tools.items) == "table" and tools.items or {}) do
            item = Core.Num(item)
            if item then needs[#needs + 1] = { item = item, need = 1, tool = true } end
        end
        return needs, "tables"
    end
    local item
    if fallback ~= nil then item = fallback and Core.Num(fallback) or nil else item = Spells.GroupReagent(spellID) end
    if item then
        needs[1] = { item = item, need = 1 }
        return needs, "list"
    end
    return needs
end

function Spells.MissingReagents(spellID, fallback)
    local needs, source = Spells.ReagentNeeds(spellID, fallback)
    local missing = {}
    for _, n in ipairs(needs) do
        n.have = Core.Num(Core.ItemCount(n.item)) or 0
        if n.have < n.need then missing[#missing + 1] = n end
    end
    if #missing == 0 then return nil, source end
    return missing, source
end

function Spells.ReagentList(missing)
    local L = Core.L
    local parts = {}
    for _, n in ipairs(type(missing) == "table" and missing or {}) do
        local name = Core.ItemNameByID(n.item) or ("#" .. tostring(n.item))
        parts[#parts + 1] = L.SPELLS_REAGENT_COUNT:format(name, Core.Num(n.have) or 0, Core.Num(n.need) or 1)
    end
    return table.concat(parts, ", ")
end

function Spells.ReagentText(missing)
    return Core.L.SPELLS_REAGENT_MISSING:format(Spells.ReagentList(missing))
end

function Spells.ReagentSource(source, listText)
    local CD, L = Core.ClientData, Core.L
    if source == "tables" and CD and type(CD.SourceText) == "function" then
        return L.SPELLS_REAGENT_SOURCE:format(CD.SourceText("reagents"))
    end
    return listText or L.SPELLS_REAGENT_SOURCE_GROUP
end

-- Zauber, die mit diesem eine Abklingzeit teilen (Welle 26, F10; SpellCategories laut Client-Tabellen, z. B. die
-- Schocks des Schamanen) → { Zauber-ID … } (leer, wenn keiner)
function Spells.SharedCooldown(spellID)
    local CD = Core.ClientData
    return CD and CD.SharedCooldown and CD.SharedCooldown(spellID) or {}
end

---------------------------------------------------------------------------
-- Auren finden: über die Zauber-ID und alle Ränge, nicht nur über den Namen
---------------------------------------------------------------------------

local function AddBuffIDs(ids, key)
    local d = Spells.BUFFS[key]
    for _, id in ipairs(d.spells or {}) do ids[id] = true end
    for _, id in ipairs(d.group or {}) do ids[id] = true end
end

local function AddRanks(ids, id)
    ids[id] = true
    local entry = Spells.Known(id)
    for _, rankID in pairs(entry and entry.ranks or {}) do ids[rankID] = true end
end

-- Alle Zauber-IDs, unter denen eine Aura liegen kann: { [id] = true } (nicht verändern – zwischengespeichert).
--   Buff-Schlüssel ("demonSkin")  alle Ränge und Gruppenfassungen des Eintrags
--   kind ("armor")                dasselbe für jeden Eintrag der Wahlgruppe der eigenen Klasse
--   Familie ("seal")              ihre Zauber samt den gelernten Rängen
--   Zauber-ID                     sie selbst, alle gelernten Ränge und – steht sie in BUFFS – alle Ränge des Eintrags
-- nil bei einem gesperrten oder unbekannten Wert.
function Spells.AuraIDs(value)
    if Core.IsSecret(value) or value == nil then return nil end
    Ensure()
    local cached = auraIDs[value]
    if cached then return cached end
    local ids
    if type(value) == "number" then
        ids = {}
        AddRanks(ids, value)
        local key = Spells.BuffKey(value)
        if key then AddBuffIDs(ids, key) end
    elseif type(value) == "string" then
        if Spells.BUFFS[value] then
            ids = {}
            AddBuffIDs(ids, value)
        elseif Spells.FAMILIES[value] then
            ids = {}
            for _, id in ipairs(Spells.FAMILIES[value].spells) do AddRanks(ids, id) end
        else
            local group = Spells.BuffGroup(value)
            if group then
                ids = {}
                for _, key in ipairs(group.keys) do AddBuffIDs(ids, key) end
            end
        end
    end
    if ids then auraIDs[value] = ids end
    return ids
end

-- Erste Aura einer Liste aus Core.Auras.Scan, die zu dem Zauber, Buff oder der Familie gehört: zuerst über die
-- Zauber-ID (jeder Rang, jede Gruppenfassung), sonst über den Namen (Rückfall, wenn die Aura keine ID trägt oder
-- der Client eine andere ID meldet). Gesperrte Platzhalter zählen nie. → Aura, "id" | "name"; sonst nil.
function Spells.FindAura(list, value)
    local ids = Spells.AuraIDs(value)
    if not ids or type(list) ~= "table" then return nil end
    for _, aura in ipairs(list) do
        if type(aura) == "table" and not aura.secret then
            local id = Core.Num(aura.spellId)
            if id and ids[id] then return aura, "id" end
        end
    end
    local names
    for _, aura in ipairs(list) do
        if type(aura) == "table" and not aura.secret and type(aura.name) == "string" and aura.name ~= "" then
            if not names then
                names = {}
                for id in pairs(ids) do
                    local name = Spells.Name(id)
                    if name then names[name] = true end
                end
            end
            if names[aura.name] then return aura, "name" end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Dauer: aus der laufenden Aura gelernt, feste Minuten nur als Rückfall
---------------------------------------------------------------------------

local function Durations(create)
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if not create and Moved("durations") then return Core.Discovery.DurationStore() end
    if type(db.spells) ~= "table" then
        if not create then return nil end
        db.spells = {}
    end
    if type(db.spells.durations) ~= "table" then
        if not create then return nil end
        db.spells.durations = {}
    end
    return db.spells.durations
end

-- Merkt die Dauer einer offen gelesenen eigenen Aura (Eintrag aus Core.Auras.Scan, source = "player"):
-- ezCoreDB.spells.durations[Zauber-ID] und – ist es ein Rang eines Klassen-Buffs aus BUFFS – [Schlüssel] = Sekunden.
-- Core.Auras.Scan ruft das für jede offene Aura. → true, wenn gemerkt
function Spells.NoteAura(aura)
    if type(aura) ~= "table" or aura.secret or aura.source ~= "player" then return false end
    local seconds, id = Core.Num(aura.duration), Core.Num(aura.spellId)
    if not (seconds and seconds > 0 and id) then return false end
    seconds = math.floor(seconds + 0.5)
    if Moved("durations") then return Core.Discovery.NoteDuration(id, seconds) end   -- spellObs.dur
    local store = Durations(true)
    if not store then return false end
    if store[id] ~= seconds then store[id] = seconds end
    local key = Spells.BuffKey(id)
    local d = key and Spells.BUFFS[key]
    if d and d.class then
        for _, spell in ipairs(d.spells) do            -- Gruppenfassungen (Gebete, Große Segen) laufen anders
            if spell == id then
                if store[key] ~= seconds then store[key] = seconds end
                break
            end
        end
    end
    return true
end

-- Gemerkte Dauer in Sekunden zu einem Buff-Schlüssel oder einer Zauber-ID (auch über den Buff-Eintrag der ID oder
-- einen anderen gelernten Rang); nil, solange der Client sie noch nicht gezeigt hat.
function Spells.AuraSeconds(value)
    if Core.IsSecret(value) or value == nil then return nil end
    local store = Durations(false)
    if not store then return nil end
    if store[value] then return store[value] end
    if type(value) ~= "number" then return nil end
    local key = Spells.BuffKey(value)
    if key and store[key] then return store[key] end
    local entry = Spells.Known(value)
    for _, rankID in pairs(entry and entry.ranks or {}) do
        if store[rankID] then return store[rankID] end
    end
    return nil
end

-- Dauer eines Buffs in Minuten und die Quelle: "aura" (vom Client gelernt) oder "fallback" (SpellData.lua).
-- Bei einem kind der gewählte Buff der Gruppe (sonst ihr erster). nil, wenn beides fehlt (auch bei permanent).
-- spellID (freiwillig): die Zauber-ID der Aura. Ist sie eine Gruppenfassung des Eintrags, gilt deren eigene gemerkte
-- Dauer, sonst fallback.groupMinutes – die Dauer der Einzelränge passt dort nicht (Gebet des Schattenschutzes 20 statt
-- 10 Minuten; Gesamtreview 18.11.2026, T14-NH8).
function Spells.BuffMinutes(key, spellID)
    if Core.IsSecret(key) or type(key) ~= "string" then return nil end
    if not Spells.BUFFS[key] then
        local group = Spells.BuffGroup(key)
        key = group and (Spells.ChooseBuff(key) or group.keys[1]) or nil
        if not key then return nil end
    end
    spellID = not Core.IsSecret(spellID) and Core.Num(spellID) or nil
    if spellID then
        for _, id in ipairs(Spells.BUFFS[key].group or {}) do
            if id == spellID then
                local store = Durations(false)
                local seen = store and Core.Num(store[spellID])
                if seen then return seen / 60, "aura" end
                local fb = Spells.BUFFS[key].fallback
                if fb and fb.groupMinutes then return fb.groupMinutes, "fallback" end
                break
            end
        end
    end
    local seconds = Spells.AuraSeconds(key)
    if seconds then return seconds / 60, "aura" end
    local fallback = Spells.BUFFS[key].fallback
    if fallback and fallback.minutes then return fallback.minutes, "fallback" end
    return nil
end

-- Dauer-Buff (hält mindestens Spells.LONG_BUFF_MINUTES)? Zauber-ID oder Buff-Schlüssel. Unbekannte Dauer: false.
function Spells.IsLongBuff(value)
    if Core.IsSecret(value) or value == nil then return false end
    local minutes
    if type(value) == "number" then
        local key = Spells.BuffKey(value)
        if key then
            minutes = Spells.BuffMinutes(key, value)
        else
            local seconds = Spells.AuraSeconds(value)
            minutes = seconds and seconds / 60 or nil
        end
    else
        minutes = Spells.BuffMinutes(value)
    end
    return minutes ~= nil and minutes >= Spells.LONG_BUFF_MINUTES
end

-- Zustand eines Buffs oder einer Wahlgruppe in einer LESBAREN Aurenliste (Core.Auras.Scan; ob sie lesbar ist,
-- prüft der Aufrufer vorher mit Core.Auras.Readable bzw. den Zählern von Scan – sonst hieße „unbekannt“ hier „fehlt“):
--   "ok" | "missing" | "expiring", Aura, gewählter Schlüssel, Zauber-ID (Wahl wie ChooseBuff mit opts.prefer/level/class)
-- Jeder Buff der Gruppe zählt (eine Rüstung ist eine Rüstung). opts.minLeft: Rest in Sekunden, unter dem der Buff
-- als „läuft bald aus“ gilt (Standard Spells.PREP_LEFT, nie mehr als ein Viertel seiner Dauer); dauerhaft = ok.
-- nil, wenn es den Buff bzw. die Gruppe nicht gibt.
function Spells.BuffState(value, auras, opts)
    opts = type(opts) == "table" and opts or {}
    local group = Spells.BuffGroup(value, opts.class)
    if not group then return nil end
    local key, spell = Spells.ChooseBuff(value, opts)
    local found
    for _, groupKey in ipairs(group.keys) do
        found = Spells.FindAura(auras, groupKey)
        if found then break end
    end
    if not found then return "missing", nil, key, spell end
    local expires = Core.Num(found.expires)
    if expires then
        local minLeft = Core.Num(opts.minLeft) or Spells.PREP_LEFT
        local duration = Core.Num(found.duration)
        if duration and duration > 0 and minLeft > duration / 4 then minLeft = duration / 4 end
        if expires - GetTime() < minLeft then return "expiring", found, key, spell end
    end
    return "ok", found, key, spell
end

---------------------------------------------------------------------------
-- Gestalt, Haltung, Aura der Gestaltleiste
---------------------------------------------------------------------------

-- Gestaltleiste lesen: { { active, spell } … }; nil ohne Schnittstelle oder wenn eine Angabe gesperrt ist.
local function Forms()
    local info = rawget(_G, "GetShapeshiftFormInfo")
    local count = Core.Num((Core.Call(rawget(_G, "GetNumShapeshiftForms"))))
    if not count or type(info) ~= "function" then return nil end
    local list = {}
    for index = 1, count do
        local ok, _, active, _, spellID = pcall(info, index)
        if not ok or Core.IsSecret(active) or Core.IsSecret(spellID) then return nil end
        list[index] = { active = active == true or active == 1, spell = Core.Num(spellID) }
    end
    return list
end

-- Ist diese Gestalt, Haltung oder Aura aktiv? true/false, nil = unbekannt. Zuerst die Gestaltleiste (Zauber-ID oder
-- gleicher Name), sonst Spells.FORM_IDS gegen GetShapeshiftFormID(). Steht der Zauber nicht auf einer vollständig
-- gelesenen Leiste, ist die Antwort false (die Gestalt ist nicht gelernt, also nicht aktiv).
function Spells.FormActive(id)
    id = tonumber(id)
    if not id then return nil end
    local forms = Forms()
    local complete = forms ~= nil
    if forms then
        local name = Spells.Name(id)
        for _, form in ipairs(forms) do
            if not form.spell then
                complete = false
            elseif form.spell == id or (name and Spells.Name(form.spell) == name) then
                return form.active
            end
        end
    end
    local formID = Spells.FORM_IDS[id]
    local api = rawget(_G, "GetShapeshiftFormID")
    if formID and type(api) == "function" then
        local ok, current = pcall(api)
        if not ok or Core.IsSecret(current) then return nil end
        current = Core.Num(current)
        -- Keine Nummer heißt „keine Gestalt“ nur neben einer lesbaren Gestaltleiste; ist sie gesperrt: unbekannt
        if current == nil then
            if forms ~= nil then return false end
            return nil
        end
        return current == formID
    end
    if complete then return false end
    return nil
end

-- Zauber-ID der aktiven Gestalt, Haltung oder Aura; 0 ohne; nil = unbekannt.
function Spells.ActiveForm()
    local forms = Forms()
    if not forms then return nil end
    for _, form in ipairs(forms) do
        if form.active then return form.spell end
    end
    return 0
end
