local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Waffenverzauberung auf Zeit (BF-17, V-148): Gift, Wetzstein, Gewichtsstein, Zauberöl. Fehlt sie auf einer Hand,
    die eine Waffe trägt (oder läuft sie unter „Rechtzeitig erneuern“ aus), wird das eine Aufgabe am Buff-Knopf –
    nur außerhalb des Kampfes wie alles in ezBuff. Der Klick benutzt den besten passenden Gegenstand aus der Tasche
    (Item-Wissen von ezCore: Art „weaponEnchant“) und trägt ihn auf genau diese Hand auf (Makro „/use item:…“ und
    „/use 16“ bzw. „/use 17“ – die zweite Zeile wählt die Waffe als Ziel, wie Blizzards eigene Makros).
    Schalter „weapon“, ab Werk an seit der Einstellungs-Prüfung vom 19.11.2026 (handelt nur auf Klick). Ohne Passendes in der Tasche keine Aufgabe (ein Krieger ohne Wetzstein wird nicht
    gemahnt). Im Kampf warnt weiter ezCombat (Enchants.lua), wenn Gift oder Verzauberung ausläuft.
    Gesperrte Werte (Leitlinie 6): Gibt das Spiel nicht heraus, ob eine Hand verzaubert ist oder wie lange noch, ist
    der Stand unbekannt – keine Aufgabe, ns.NoteSecret("weapon"), /ezbuff status nennt es.
    Waffenzauber des Schamanen (Welle 23, A4; Daten aus ezCores Klassen-Wissen, Spells.WEAPON_IMBUES): Hat der
    Schamane einen gelernt, wirkt der Klick auf die Waffenhand den gewählten bzw. vorgeschlagenen Zauber (Aktion
    „spell“, kein Gegenstand nötig). Welcher Waffenzauber liegt, verrät der Client nicht – es zählt eine liegende
    Verzauberung, gleich welche. Die Wahl ist eine Wahlgruppe wie Segen und Rüstung (id „imbue“, Checks.lua):
    Auswahlfeld auf der Einstellungsseite, Rechtsklick-Menü des Knopfs; ein selbst gewirkter anderer wird gemerkt.
    Die Schildhand bekommt weiter nur einen Gegenstand aus der Tasche (ob der Zauber sie trifft, klärt der Spieltest).
]]

local Weapon = {}
ns.Weapon = Weapon

Weapon.HANDS = { "main", "off" }
Weapon.SLOTS = { main = rawget(_G, "INVSLOT_MAINHAND") or 16, off = rawget(_G, "INVSLOT_OFFHAND") or 17 }
Weapon.MACRO = "/use item:%d\n/use %d"
Weapon.IMBUE_ID = "imbue"     -- id der Wahlgruppe (ns.CharDB().prefer.imbue, Check.CHOICE_KINDS)
-- Vorschlag ohne eigene Wahl: der zuletzt lernbare zuerst (Windzorn ab 30, Flammenzunge ab 10, Frostbrand ab 20,
-- Felsbeißer ab 1). Empfehlung aus Welle 23, umkehrbar über die Wahl (docs/roadmap/ezBuff.md).
Weapon.IMBUE_ORDER = { "windfury", "flametongue", "frostbrand", "rockbiter" }

-- Verzauberung auf Zeit beider Hände: lesbar, hatMain, msMain, hatOff, msOff (wie Blizzards GetWeaponEnchantInfo;
-- die Werte können gesperrt sein). Seit Welle 23 (A3) ezCores gemeinsamer Leser Core.WeaponEnchantInfo (das Globale
-- zuerst, sonst C_Item; dieselbe Regel wie vorher hier); die Funktion bleibt als Weiterleitung (Leitlinie 8).
function Weapon.Info()
    return Core.WeaponEnchantInfo()
end

---------------------------------------------------------------------------
-- Waffenzauber des Schamanen (ezCore: Spells.WeaponImbues, Spells.BestImbueRank)
---------------------------------------------------------------------------

local function Imbues(class)
    local Spells = Core.Spells
    if not (Spells and Spells.WeaponImbues) or ns.IsSecret(class) or type(class) ~= "string" then return {} end
    local list = Core.Call(Spells.WeaponImbues, class)
    return type(list) == "table" and list or {}
end

-- Wahlgruppe „Waffenzauber“ der Klasse (Form wie die Wahlgruppen in Checks.lua) oder nil für Klassen ohne:
-- { id = "imbue", kind = "imbue", imbue = true, entries = { { key, spells, levels } … } } in der Reihenfolge des
-- Vorschlags (IMBUE_ORDER, unbekannte Schlüssel aus ezCore dahinter).
function Weapon.ImbueGroup(class)
    local list, byKey = Imbues(class), {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" and type(entry.key) == "string" then byKey[entry.key] = entry end
    end
    local entries = {}
    for _, key in ipairs(Weapon.IMBUE_ORDER) do
        if byKey[key] then
            entries[#entries + 1] = byKey[key]
            byKey[key] = nil
        end
    end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and byKey[entry.key] then entries[#entries + 1] = entry end
    end
    if #entries == 0 then return nil end
    return { id = Weapon.IMBUE_ID, kind = Weapon.IMBUE_ID, imbue = true, entries = entries, target = "self" }
end

-- Höchster gelernter Rang eines Waffenzaubers (Zauber-ID) oder nil.
function Weapon.ImbueRank(key)
    local Spells = Core.Spells
    if ns.IsSecret(key) or type(key) ~= "string" or not (Spells and Spells.BestImbueRank) then return nil end
    return ns.Num(Core.Call(Spells.BestImbueRank, key))
end

-- Name eines Waffenzaubers: vom Client (gelernter Rang), sonst ezCores Ersatzname des ersten Rangs.
function Weapon.ImbueName(key)
    local spell = Weapon.ImbueRank(key)
    local name = spell and Core.Spells.Name(spell)
    if name then return name end
    for _, entry in ipairs(Imbues(ns.playerClass)) do
        if entry.key == key and type(entry.spells) == "table" and entry.spells[1] then
            return Core.Spells.Name(entry.spells[1])
        end
    end
    return nil
end

-- Wählbare Waffenzauber: { { key, spell, name } } – nur gelernte, in der Reihenfolge des Vorschlags.
function Weapon.ImbueChoices()
    local out = {}
    local group = Weapon.ImbueGroup(ns.playerClass)
    for _, entry in ipairs(group and group.entries or {}) do
        local spell = Weapon.ImbueRank(entry.key)
        if spell then out[#out + 1] = { key = entry.key, spell = spell, name = Weapon.ImbueName(entry.key) } end
    end
    return out
end

-- Vorschlag ohne eigene Wahl: der erste gelernte in IMBUE_ORDER (Schlüssel) oder nil.
function Weapon.DefaultImbue()
    local first = Weapon.ImbueChoices()[1]
    return first and first.key or nil
end

-- Gewählter Waffenzauber: die gemerkte Wahl, wenn gelernt, sonst der Vorschlag. → Schlüssel, Zauber-ID | nil.
function Weapon.ChooseImbue()
    if not Weapon.ImbueGroup(ns.playerClass) then return nil end
    local prefer = ns.db and ns.CharDB().prefer[Weapon.IMBUE_ID]
    if not ns.IsSecret(prefer) and type(prefer) == "string" then
        local spell = Weapon.ImbueRank(prefer)
        if spell then return prefer, spell end
    end
    local key = Weapon.DefaultImbue()
    if key then return key, Weapon.ImbueRank(key) end
    return nil
end

-- Schlüssel des Waffenzaubers zu einer Zauber-ID (jeder Rang) oder nil – für das Merken eines selbst gewirkten.
function Weapon.ImbueKeyOf(spellID)
    if ns.IsSecret(spellID) or type(spellID) ~= "number" then return nil end
    for _, entry in ipairs(Imbues(ns.playerClass)) do
        for _, id in ipairs(type(entry.spells) == "table" and entry.spells or {}) do
            if id == spellID then return entry.key end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Hände und Aufgaben
---------------------------------------------------------------------------

-- Trägt die Hand eine Waffe? Schild und Nebenhand-Gegenstände nehmen keine Verzauberung an, eine Angelrute zählt
-- nicht (Art Waffe, Unterart Angelrute – wie ezGear, Char.Enchantable). Nummern der Arten aus ezCore
-- (Core.ITEM_CLASS), die Unterart aus Blizzards Enum.ItemWeaponSubclass.
function Weapon.HasWeapon(hand)
    local slot = Weapon.SLOTS[hand]
    if not slot then return false end
    local itemID = ns.Num(ns.Value(GetInventoryItemID, "player", slot))
    if not itemID then return false end
    local classID, subClassID = Core.ItemClass(itemID)
    if classID == nil or classID ~= ((Core.ITEM_CLASS or {}).Weapon or 2) then return false end
    local weaponSub = Enum and Enum.ItemWeaponSubclass
    return subClassID ~= (weaponSub and weaponSub.Fishingpole or 20)
end

-- Zustand einer Hand: "ok" | "missing" | "expiring" | "unknown" (gesperrt). minLeft in Sekunden.
function Weapon.State(has, ms, minLeft)
    if ns.IsSecret(has) or ns.IsSecret(ms) then return "unknown" end
    if not has then return "missing" end
    local left = ns.Num(ms)
    if left and left / 1000 <= (ns.Num(minLeft) or 0) then return "expiring" end
    return "ok"
end

-- Längste Restzeit je Hand seit dem letzten Wirken (ms; Weapon.Seen). Der Client nennt nur die Restzeit, nicht die
-- Dauer – die höchste gesehene Restzeit steht für die Dauer, bis die Hand wieder leer ist.
Weapon.seen = {}

function Weapon.Seen(hand, has, ms)
    if ns.IsSecret(has) or ns.IsSecret(ms) then return Weapon.seen[hand] end
    if not has then
        Weapon.seen[hand] = nil
        return nil
    end
    local left = ns.Num(ms)
    if left and left > (Weapon.seen[hand] or 0) then Weapon.seen[hand] = left end
    return Weapon.seen[hand]
end

-- Dauer eines Waffenzaubers in ms und ihre Quelle (Paket modul/ezbuff-reagenzien): zuerst ezCores Client-Wissen
-- (Spells.ImbueDuration – SpellItemEnchantment laut Client-Tabellen; auf Forever 3600 s), sonst als Rückfall die
-- längste gesehene Restzeit seit dem Wirken (Weapon.Seen). → ms, "tables" | "seen" oder nil.
function Weapon.Duration(spell, seenMs)
    local Spells = Core.Spells
    if spell and Spells and Spells.ImbueDuration then
        local seconds = ns.Num((Core.Call(Spells.ImbueDuration, spell)))
        if seconds and seconds > 0 then return seconds * 1000, "tables" end
    end
    local seen = ns.Num(seenMs)
    if seen and seen > 0 then return seen, "seen" end
    return nil
end

-- Schwelle „Rechtzeitig erneuern“ (Sekunden) für eine Hand. Für Waffenzauber des Schamanen gilt wie bei den Auren
-- (Spells.BuffState) höchstens ein Viertel der Dauer, sonst stünde ein frisch gewirkter Zauber sofort wieder als
-- „läuft aus“ am Knopf (Gegenprüfung Welle 23). Die Dauer kommt aus ezCores Client-Wissen (Weapon.Duration); nur
-- ohne sie gilt die gesehene Restzeit (nach /reload mit halb abgelaufenem Zauber also ein Viertel des Rests).
-- Gegenstände (30 Min) behalten die Schwelle.
function Weapon.Threshold(minLeft, seenMs, spell)
    local seconds = ns.Num(minLeft) or 0
    local duration = spell and Weapon.Duration(spell, seenMs)
    if duration and seconds > duration / 4000 then seconds = duration / 4000 end
    return seconds
end

-- Tooltip-Zeile zur Dauer eines Waffenzaubers samt Quelle (Leitlinie 11) oder nil.
function Weapon.DurationNote(spell, seenMs)
    local ms, source = Weapon.Duration(spell, seenMs)
    if not ms then return nil end
    local minutes = Core.Minutes(math.floor(ms / 60000 + 0.5))
    if source == "tables" then
        local CD = Core.ClientData
        local from = CD and type(CD.SourceText) == "function" and CD.SourceText("enchants") or nil
        if from then return L.WEAPON_DURATION:format(minutes, from) end
    end
    return L.WEAPON_DURATION_SEEN:format(minutes)
end

-- Makro für den Klick: Gegenstand benutzen, dann die Waffe dieser Hand als Ziel.
function Weapon.Macro(itemID, hand)
    return Weapon.MACRO:format(itemID, Weapon.SLOTS[hand] or Weapon.SLOTS.main)
end

-- Aufgaben für den Buff-Knopf (Checks.lua): item = bester Gegenstand aus Check.BagItems (weapon) oder nil. Ein
-- gelernter Waffenzauber des Schamanen (Weapon.ChooseImbue) geht auf der Waffenhand dem Gegenstand vor.
function Weapon.Tasks(item, minLeft)
    local out = {}
    if type(item) ~= "table" or not ns.Num(item.itemID) then item = nil end
    local imbueKey, imbueSpell = Weapon.ChooseImbue()
    if not item and not imbueSpell then return out end
    local readable, hasMain, mainMs, hasOff, offMs = Weapon.Info()
    if readable ~= true then return out end
    local values = { main = { hasMain, mainMs }, off = { hasOff, offMs } }
    for _, hand in ipairs(Weapon.HANDS) do
        local spell = hand == "main" and imbueSpell or nil
        local seenMs = Weapon.Seen(hand, values[hand][1], values[hand][2])
        if (spell or item) and Weapon.HasWeapon(hand) then
            local state = Weapon.State(values[hand][1], values[hand][2], Weapon.Threshold(minLeft, seenMs, spell))
            if state == "unknown" then
                ns.NoteSecret("weapon")
            elseif state ~= "ok" then
                local what = L.WHAT_WEAPON:format(L["HAND_" .. hand])
                local task = { kind = "weapon", key = hand, label = L.MISSING_SELF:format(what), what = what,
                    state = state }
                if spell then
                    task.icon, task.imbue = Core.Spells.Icon(spell), imbueKey
                    task.spellName = Core.Spells.Name(spell) or Weapon.ImbueName(imbueKey)
                    task.action = { type = "spell", spell = spell }
                    task.note = Weapon.DurationNote(spell, seenMs)
                else
                    task.icon, task.itemName = item.icon, item.name
                    task.action = { type = "macro", macrotext = Weapon.Macro(item.itemID, hand) }
                end
                out[#out + 1] = task
            end
        end
    end
    return out
end
