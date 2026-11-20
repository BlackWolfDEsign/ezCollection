local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Die EINE Bewertung „besser“ der ezCollection. ezQuest (Questbelohnung) und ezLoot (Würfelfenster) rufen sie über
    ezCore.API("ezGear") auf, statt sie nachzubauen; ezBag zeigt den Pfeil über seine Platzmarken.

    Wert eines Gegenstands = Summe aus Wert × Gewichtung (Weights.lua). Verglichen wird mit dem, was am passenden Platz
    angelegt ist:
      Ringe und Schmuckstücke     mit dem schwächeren der beiden Plätze (ein leerer Platz zählt 0)
      Zweihänder                  mit Haupt- und Schildhand zusammen
      Einhänder                   mit der Haupthand; wer zwei Waffen führen kann, auch mit der Schildhand
      Schildhand, Schild, Buch    mit der Schildhand – nicht, solange ein Zweihänder angelegt ist
    Nicht tragbare Gegenstände (Klasse, Stufe; aus dem Item-Wissen) sind nie „besser“.
]]

local Score = {}
ns.Score = Score

-- Inventarplätze und equipLoc → Plätze: die EINE Tabelle steht in ezCore (Core.EquipSlots, vorher fünfmal im
-- Paket). Score.SLOT und Score.LOC_SLOTS bleiben als Verweise darauf (LOC_SLOTS nennt dort auch Hemd, Wappenrock
-- und Munition – bewertet wird nur, was Score.ScoredSlots liefert).
-- Die Datei lädt vor der needs-Prüfung von Core.NewModule: fehlt EquipSlots (ezCore zu alt), meldet das die
-- Prüfung – hier also kein nil-Fehler beim Laden, und ohne die Plätze gibt es keine Aussage (ScoredSlots → nil).
local ES = Core.EquipSlots or {}
local SLOT = ES.SLOT or {}
Score.SLOT = ES.SLOT
Score.LOC_SLOTS = ES.LOC_SLOTS

-- equipLoc → Plätze, an denen verglichen wird; Hemd, Wappenrock und Munition werden nicht bewertet (nil).
function Score.ScoredSlots(loc)
    if loc == nil or not ES.ForLoc or not ES.IsCosmetic or ES.IsCosmetic(loc) then return nil end
    local slots = ES.ForLoc(loc)
    if not slots or slots[1] == SLOT.AMMO then return nil end
    return slots
end
local DUAL_WIELD_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true }

---------------------------------------------------------------------------
-- Wert eines Gegenstands (zwischengespeichert je Link, gelöscht bei neuer Gewichtung)
---------------------------------------------------------------------------

local cache, cacheSize, cacheWeights = {}, 0, nil

function ns.ClearScoreCache()
    cache, cacheSize = {}, 0
end

-- Score.Of(link) → Zahl oder nil (Daten noch nicht geladen)
function Score.Of(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    local weights = ns.Weights.Active()
    if weights ~= cacheWeights then
        ns.ClearScoreCache()
        cacheWeights = weights
    end
    local hit = cache[link]
    if hit then return hit end
    local stats = ns.Stats.Read(link)
    if not stats then return nil end
    local sum = 0
    for key, value in pairs(stats) do
        local w = weights[key]
        if w then sum = sum + w * value end
    end
    sum = math.floor(sum * 100 + 0.5) / 100
    if cacheSize > 2000 then ns.ClearScoreCache() end
    cache[link] = sum
    cacheSize = cacheSize + 1
    return sum
end

---------------------------------------------------------------------------
-- Angelegte Ausrüstung
---------------------------------------------------------------------------

local function EquippedLink(slot)
    local link = ns.Plain(ns.Call(GetInventoryItemLink, "player", slot))
    if type(link) == "string" and link ~= "" then return link end
    return nil
end
Score.EquippedLink = EquippedLink

local function EquippedLoc(slot)
    local link = EquippedLink(slot)
    return link and ns.Stats.EquipLoc(link) or nil
end

local function DualWield()
    local can = ns.Plain(ns.Call(_G.CanDualWield))
    if type(can) == "boolean" then return can end
    return DUAL_WIELD_CLASSES[ns.playerClass or ""] == true
end

-- Wert eines Platzes: 0 bei leerem Platz, nil, solange die Daten des angelegten Gegenstands fehlen.
local function SlotScore(slot)
    local link = EquippedLink(slot)
    if not link then return 0, nil end
    return Score.Of(link), link
end

---------------------------------------------------------------------------
-- Vergleich
---------------------------------------------------------------------------

--[[
    Score.Compare(link) → info oder nil (kein Ausrüstungsgegenstand, Daten fehlen)
      info.score       Wert des Gegenstands
      info.base        Wert dessen, was er ersetzen würde (0 = leerer Platz)
      info.delta       score − base
      info.percent     Prozent besser (bei leerem Platz 100), auf ganze Zahlen gerundet
      info.slot        Inventarplatz, der ersetzt würde
      info.replaces    Link des ersetzten Gegenstands (nil = leer)
      info.empty       true, wenn der Platz leer ist
      info.usable      false, wenn die Klasse ihn nicht tragen kann oder die Stufe fehlt
      info.usableFrom  ab dieser Stufe tragbar (nur, wenn die Stufe fehlt; aus dem Item-Wissen)
      info.minLevel    Mindeststufe des Gegenstands (nur neben usableFrom) – liegt usableFrom darüber, beherrscht die
                       Klasse die Rüstungsart erst später (Schwere Rüstung, Platte ab 40)
      info.armorType   Rüstungs- bzw. Waffenart („Leder“), wenn die Klasse ihn nicht tragen kann
      info.equipped    true, wenn genau dieser Gegenstand schon angelegt ist
      info.twoHand     true bei Schildhand-Gegenständen, solange ein Zweihänder angelegt ist (kein Vergleich)
      info.pending     true, wenn Daten noch laden (dann ohne Ergebnis)
]]

local function PlayerLevel()
    local level = ns.Num(ns.Call(UnitLevel, "player"))
    return level or 0
end
function Score.Compare(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    local facts = ns.Stats.Facts(link)
    local loc = ns.Stats.EquipLoc(link, facts)
    local slots = Score.ScoredSlots(loc)
    if not slots then return nil end
    if facts and facts.isEquipment == false then return nil end

    local info = { usable = true }
    if facts and facts.usableNow == false then
        info.usable = false
        local from = ns.Num(facts.usableFrom)
        if from and from > PlayerLevel() then
            info.usableFrom = from
            info.minLevel = ns.Num(facts.minLevel)
        elseif type(facts.subClassName) == "string" and facts.subClassName ~= "" then
            info.armorType = facts.subClassName
        end
    end

    for _, slot in ipairs(slots) do
        if EquippedLink(slot) == link then
            info.equipped, info.slot = true, slot
            return info
        end
    end

    local score = Score.Of(link)
    if score == nil then
        info.pending = true
        return info
    end
    info.score = score

    local base, slot, replaces
    local mainLoc = EquippedLoc(SLOT.MAINHAND)
    if loc == "INVTYPE_2HWEAPON" then
        local main, mainLink = SlotScore(SLOT.MAINHAND)
        local off = SlotScore(SLOT.OFFHAND)
        if main == nil or off == nil then info.pending = true return info end
        base, slot, replaces = main + off, SLOT.MAINHAND, mainLink
    elseif ES.IsOffhand(loc) then
        if mainLoc == "INVTYPE_2HWEAPON" then
            info.twoHand = true
            return info
        end
        base, replaces = SlotScore(SLOT.OFFHAND)
        slot = SLOT.OFFHAND
    elseif loc == "INVTYPE_WEAPON" then
        local main, mainLink = SlotScore(SLOT.MAINHAND)
        if main == nil then info.pending = true return info end
        base, slot, replaces = main, SLOT.MAINHAND, mainLink
        local offLoc = EquippedLoc(SLOT.OFFHAND)
        local offIsWeaponOrEmpty = offLoc == nil or offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND"
        if DualWield() and mainLoc ~= "INVTYPE_2HWEAPON" and offIsWeaponOrEmpty then
            local off, offLink = SlotScore(SLOT.OFFHAND)
            if off == nil then info.pending = true return info end
            if off < base then base, slot, replaces = off, SLOT.OFFHAND, offLink end
        end
    else
        for _, s in ipairs(slots) do
            local value, itemLink = SlotScore(s)
            if value == nil then info.pending = true return info end
            if base == nil or value < base then base, slot, replaces = value, s, itemLink end
        end
    end
    if base == nil then info.pending = true return info end

    info.base, info.slot, info.replaces = base, slot, replaces
    info.empty = replaces == nil
    info.delta = score - base
    if base > 0 then
        info.percent = math.floor((score - base) / base * 100 + 0.5)
    elseif score > 0 then
        info.percent = 100
    else
        info.percent = 0
    end
    return info
end

--[[
    Score.Verdict(info) → Stand eines Vergleichs (eine Regel für Pfeile, Tooltip und Status):
      "better"    besser – grüner Pfeil (mindestens minPercent, oder Platz leer)
      "worse"     schlechter – roter Pfeil (mindestens minPercent bzw. 1 % schlechter, oder ohne zählende Werte
                  gegen etwas Angelegtes)
      "same"      kaum Unterschied
      "nostats"   keine Werte, die für die Gewichtung zählen (und am Platz liegt nichts Besseres)
      "level"     Stufe zu hoch (info.usableFrom)
      "unusable"  die Klasse kann ihn nicht tragen (info.armorType)
      "twohand"   Schildhand, solange ein Zweihänder angelegt ist
      "equipped"  genau dieser ist angelegt
      "pending"   Daten laden noch
    nil, wenn es kein Ausrüstungsgegenstand ist.
]]
function Score.Verdict(info)
    if not info then return nil end
    if info.equipped then return "equipped" end
    if info.twoHand then return "twohand" end
    if info.usable == false then return info.usableFrom and "level" or "unusable" end
    if info.pending or info.score == nil then return "pending" end
    local min = (ns.S and tonumber(ns.S.minPercent)) or 0
    if info.score <= 0 then
        if (info.base or 0) > 0 then return "worse" end
        return "nostats"
    end
    if info.empty then return "better" end
    if info.delta > 0 and info.percent >= min then return "better" end
    if info.delta < 0 and -info.percent >= math.max(min, 1) then return "worse" end
    return "same"
end

-- Score.Check(link) → Stand (siehe Verdict), info
function Score.Check(link)
    local info = Score.Compare(link)
    return Score.Verdict(info), info
end

-- Score.IsUpgrade(link) → true/false, info; nil, solange Daten fehlen
function Score.IsUpgrade(link)
    local kind, info = Score.Check(link)
    if kind == nil then return false, nil end
    if kind == "pending" then return nil, info end
    return kind == "better", info
end

-- Score.IsDowngrade(link) → true/false, info; nil, solange Daten fehlen (tragbar und schlechter als das Angelegte)
function Score.IsDowngrade(link)
    local kind, info = Score.Check(link)
    if kind == nil then return false, nil end
    if kind == "pending" then return nil, info end
    return kind == "worse", info
end

---------------------------------------------------------------------------
-- Auswahl aus mehreren (Questbelohnung, Würfelfenster)
---------------------------------------------------------------------------

--[[
    Score.BestOf(links, counts, total) → upgradeIndex, valueIndex, pending
      total          Zahl der Wahlen (optional): jede Wahl 1..total ohne Link zählt als „Daten fehlen“,
                     damit nie endgültig gewählt wird, solange eine Wahl noch nicht bewertet ist
      upgradeIndex   Index des Gegenstands mit dem größten Gewinn, der „besser“ ist (nil = keiner)
      valueIndex     Index mit dem höchsten Verkaufswert (Preis × Anzahl; nil = alle wertlos oder nur einer)
      pending        true, wenn noch Daten fehlen (später erneut fragen)
]]
function Score.BestOf(links, counts, total)
    local upgradeIndex, bestGain, valueIndex, bestValue, pending = nil, nil, nil, 0, false
    local n = 0
    for i = 1, tonumber(total) or 0 do
        if type(links and links[i]) ~= "string" then pending = true end
    end
    for i, link in pairs(links or {}) do
        if type(link) == "string" then
            n = n + 1
            local up, info = Score.IsUpgrade(link)
            if up == nil then pending = true end
            if up and info then
                local gain = info.empty and math.huge or info.percent
                if bestGain == nil or gain > bestGain then upgradeIndex, bestGain = i, gain end
            end
            local price = ns.Stats.SellPrice(link)
            if price == nil then
                pending = true
            else
                local total = price * math.max(1, tonumber(counts and counts[i]) or 1)
                if total > bestValue then valueIndex, bestValue = i, total end
            end
        end
    end
    if n < 2 then valueIndex = nil end
    return upgradeIndex, valueIndex, pending
end

-- Questbelohnungen des gerade gezeigten Questfensters (Questgeber oder Questlog)
function Score.RewardChoices()
    local links, counts = {}, {}
    local questLog = QuestInfoFrame and QuestInfoFrame.questLog
    local n
    if questLog then
        local questID = ns.Plain(ns.Call(C_QuestLog and C_QuestLog.GetSelectedQuest))
        n = ns.Plain(ns.Call(GetNumQuestLogChoices, questID))
    else
        n = ns.Plain(ns.Call(GetNumQuestChoices))
    end
    for i = 1, tonumber(n) or 0 do
        local link, count
        if questLog then
            link = ns.Plain(ns.Call(GetQuestLogItemLink, "choice", i))
            local _, _, c = ns.Call(GetQuestLogChoiceInfo, i)
            count = c
        else
            link = ns.Plain(ns.Call(GetQuestItemLink, "choice", i))
            local _, _, c = ns.Call(GetQuestItemInfo, "choice", i)
            count = c
        end
        links[i], counts[i] = link, ns.Plain(count)
    end
    return links, counts, tonumber(n) or 0
end

-- Score.BestRewardIndex() → upgradeIndex, valueIndex, pending (Index wie GetQuestItemLink("choice", i))
function Score.BestRewardIndex()
    local links, counts, total = Score.RewardChoices()
    return Score.BestOf(links, counts, total)
end

---------------------------------------------------------------------------
-- Texte für Tooltip und Marken
---------------------------------------------------------------------------

-- Score.Describe(info) → Text, besser?, Stand – für jeden Ausrüstungsgegenstand eine Aussage, warum (Leitlinie 3):
-- „+12 % für Verstärkung“, „−8 % für …“, „Nicht tragbar (Leder)“, „Stufe zu hoch (ab 14)“, „Werte werden gelesen …“.
-- nil nur ohne Aussage (kein Ausrüstungsgegenstand, genau dieser ist angelegt).
function Score.Describe(info)
    local kind = Score.Verdict(info)
    if kind == nil or kind == "equipped" then return nil end
    local label = ns.Weights.Label()
    if kind == "pending" then return L.TIP_PENDING, false, kind end
    if kind == "level" then return L.TIP_LEVEL:format(info.usableFrom), false, kind end
    if kind == "unusable" then
        if info.armorType then return L.TIP_UNUSABLE_TYPE:format(info.armorType), false, kind end
        return L.TIP_UNUSABLE, false, kind
    end
    if kind == "twohand" then return L.TIP_TWOHAND, false, kind end
    if kind == "nostats" then return L.TIP_NOSTATS:format(label), false, kind end
    if info.empty then return L.TIP_EMPTY:format(label), true, kind end
    if info.score <= 0 then return L.TIP_NOSTATS_WORSE:format(label), false, kind end
    if info.percent > 0 then return L.TIP_BETTER:format(info.percent, label), kind == "better", kind end
    if info.percent < 0 then return L.TIP_WORSE:format(-info.percent, label), false, kind end
    return L.TIP_SAME:format(label), false, kind
end

---------------------------------------------------------------------------
-- Schnittstelle für die anderen Module (ezCore.API("ezGear")); im README-Abschnitt beschrieben
---------------------------------------------------------------------------

ns.API = {
    Score = function(link) return Score.Of(link) end,
    Compare = function(link) return Score.Compare(link) end,
    -- true/false (nil = Daten laden noch), Prozent-Gewinn, info wie Compare
    IsUpgrade = function(link)
        local up, info = Score.IsUpgrade(link)
        return up, info and info.percent or nil, info
    end,
    BestOf = function(links, counts) return Score.BestOf(links, counts) end,
    BestRewardIndex = function() return Score.BestRewardIndex() end,
    Describe = function(link) return Score.Describe(Score.Compare(link)) end,
    -- Stand eines Gegenstands (siehe Score.Verdict), Text wie im Tooltip, info wie Compare
    Status = function(link)
        local info = Score.Compare(link)
        local text = Score.Describe(info)
        return Score.Verdict(info), text, info
    end,
    -- true/false (nil = Daten laden noch): tragbar und schlechter als das Angelegte (roter Pfeil)
    IsDowngrade = function(link)
        local down, info = Score.IsDowngrade(link)
        return down, info and info.percent or nil, info
    end,
    ScaleName = function() return ns.Weights.Label() end,
    -- grüner Pfeil, wenn besser; roter Pfeil nach unten, wenn schlechter (Schalter „Roter Pfeil“); link = nil leert
    SetUpgradeIcon = function(button, link) return ns.Marks and ns.Marks.SetUpgrade(button, link) end,
    SetValueIcon = function(button, shown) return ns.Marks and ns.Marks.SetValue(button, shown) end,

    -- Ausrüstungssets (Sets.lua, Swap.lua; Blizzards Ausrüstungsmanager). Angelegt wird nur außerhalb des Kampfes –
    -- im Kampf merkt ezGear den Auftrag vor und holt ihn gleich nach dem Kampf nach (ezCore.AfterCombat).
    -- Sets() → { { id, name, icon, equipped }, … } nach Name (leer ohne Ausrüstungsmanager)
    Sets = function() return ns.Sets.List() end,
    -- SetItems(Name oder ID) → { [Inventarplatz] = itemID } der Plätze, die das Set belegt; nil = kein solches Set
    -- (ein gesperrter Wert wird nicht verglichen: nil)
    SetItems = function(set)
        if ns.IsSecret(set) then return nil end
        local id = set
        if type(set) == "string" then id = ns.Sets.IDByName(set) end
        if ns.IsSecret(id) or type(id) ~= "number" then return nil end
        return ns.Sets.Items(id)
    end,
    -- EquipSet(Name) → true (angelegt) | true, "combat" (vorgemerkt) | false, "unknown" (kein Set dieses Namens)
    EquipSet = function(name) return ns.EquipSetByName(name) end,
    -- Angelausrüstung an/aus (wie der Knopf im Menü „Sets“) →
    -- true, "on" | true, "off" | true, "combat" (vorgemerkt) | false, "noset" (kein Angel-Set gewählt)
    ToggleFishing = function() return ns.ToggleFishing() end,
}

-- /ezgear test [Link]: Vergleich im Chat (ohne Link: alle angelegten Plätze mit Wert)
function ns.PrintCompare(link)
    if link == "" then link = nil end
    if link then
        local info = Score.Compare(link)
        if not info then ns.Print(L.CMD_NO_GEAR) return end
        if info.pending then ns.Print(L.CMD_PENDING) return end
        local text = Score.Describe(info)
        ns.Print(text and ("%s %s"):format(link, text) or L.CMD_NO_VERDICT)
        return
    end
    ns.Print(L.CMD_SCORES:format(ns.Weights.Label()))
    for slot = 1, 18 do
        local equipped = EquippedLink(slot)
        if equipped then ns.Print(("  %s  %s"):format(equipped, tostring(Score.Of(equipped) or "?"))) end
    end
end
