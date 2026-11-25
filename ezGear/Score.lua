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
      Schildhand, Schild, Buch    mit der Schildhand
    Ist ein Zweihänder angelegt, werden Paare verglichen (Nutzer am 24.11.2026, wörtlich: „EZGEAR: fehler? "kein vergleich.
    solange ..." --> wieso? hab doch einen zweihändigen hammer und wenn ich 2 einzelnes anhätte müsste das doch auch gehen,
    was ist das für ein blödsinn?“; vorher stand bei der Schildhand „Kein Vergleich, solange ein Zweihänder angelegt ist“
    und beim Einhänder fehlte die Schildhand): der Gegenstand zusammen mit dem besten Gegenstück aus den Taschen
    (Schildhand: die beste Einhandwaffe; Einhänder: das Beste für die Schildhand, bei zwei Waffen auch die zweite) gegen
    den Zweihänder. Ohne Gegenstück in den Taschen zählt die andere Hand leer, und der Text sagt es.
    Nicht tragbare Gegenstände (Klasse, Stufe; aus dem Item-Wissen) sind nie „besser“. Muss der Charakter nur die Waffen-
    bzw. Rüstungsfertigkeit erst lernen (Waffenmeister, Platte ab 40; ezCore.Proficiency über das Item-Wissen), wird
    verglichen wie bei einem tragbaren – Stand „learn“ (gelber Pfeil) statt „better“ (Entscheidung des Nutzers vom
    23.11.2026 „Vergleich + Hinweis (Empfohlen)“, Paket ezgear/lernbar-tragbar). Ebenso, wenn nur die Stufe fehlt – Stand
    „level“ (Nutzer am 24.11.2026: „ezgear zeigt pfeil nicht mehr weil das lvl höher ist als meins? blöd“).
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

-- Für wen verglichen wird: nil = der Spieler, sonst ein Twink (Alts.lua; Score.For): { class, level, from = tragbar ab
-- dieser Stufe oder nil, links = { [platz] = Link }, weights, cache }
local wearer

local cache, cacheSize, cacheWeights = {}, 0, nil
local waiting = {}        -- [itemID] = true: gefragt, als sein Item-Wissen noch unvollständig war

local mates, mateMark = nil, nil   -- Gegenstücke aus den Taschen (Score.Mate), unten

function ns.ClearScoreCache()
    cache, cacheSize = {}, 0
    mates = nil
    if ns.Alts then ns.Alts.Reset() end
end

-- Gewichtung dessen, für den verglichen wird
local function Weighting() return wearer and wearer.weights or ns.Weights.Active() end

-- Ist das Item-Wissen dieses Gegenstands noch unvollständig, und ist es noch gar nicht da (ezCore.Knowledge.Incomplete,
-- Knowledge.Loading; ein älteres ezCore: beides nein)?
local function Unfinished(facts)
    local K = Core.Knowledge
    if not K or type(K.Incomplete) ~= "function" or K.Incomplete(facts) ~= true then return false, false end
    return true, K.Loading(facts) == true
end

-- nach den Daten dieses Links wurde gefragt, sie fehlen (ganz oder zum Teil): Score.OnKnowledge bewertet danach neu
local function Wait(link)
    local itemID = Core.ItemID(link)
    if type(itemID) == "number" and not Core.IsSecret(itemID) then waiting[itemID] = true end
end

-- Score.Of(link) → Zahl oder nil (Daten noch nicht geladen). Solange der Client die Werte abruft, gibt es keine Zahl;
-- solange das Item-Wissen unvollständig ist, wird sie nicht gemerkt: vorher blieb eine 0 aus halb geladenen Werten im
-- Zwischenspeicher, und der Pfeil fehlte bis zur nächsten Änderung (Auktionshaus, Nutzer am 24.11.2026: „nur sporadisch
-- angezeigt“).
function Score.Of(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    local weights = Weighting()
    if not wearer and weights ~= cacheWeights then
        ns.ClearScoreCache()
        cacheWeights = weights
    end
    local hit = (wearer and wearer.cache or cache)[link]
    if hit then return hit end
    local stats, facts = ns.Stats.Read(link)
    if not stats then
        Wait(link)
        return nil
    end
    local partial, loading = Unfinished(facts)
    if partial then Wait(link) end
    if loading then return nil end
    local sum = 0
    for key, value in pairs(stats) do
        local w = weights[key]
        if w then sum = sum + w * value end
    end
    sum = math.floor(sum * 100 + 0.5) / 100
    if partial then return sum end
    if wearer then
        wearer.cache[link] = sum
        return sum
    end
    if cacheSize > 2000 then ns.ClearScoreCache() end
    cache[link] = sum
    cacheSize = cacheSize + 1
    return sum
end

-- Nachgeladen: Pfeile und Vergleiche neu, wenn nach diesem Gegenstand gefragt wurde, solange er noch lud (itemID nil:
-- alles Wissen ist neu)
function Score.OnKnowledge(itemID)
    if itemID == nil then
        if next(waiting) == nil then return end
        waiting = {}
    elseif waiting[itemID] then
        waiting[itemID] = nil
    else
        return
    end
    ns.Changed()
end

-- Ruht das Ergebnis auf unvollständigem Item-Wissen (Ziel, Ersetztes oder Gegenstück)? Dann kann es sich noch ändern.
local function Provisional(link, replaced, mate)
    if Unfinished(ns.Stats.Facts(link)) or (mate and Unfinished(ns.Stats.Facts(mate))) then return true end
    for _, other in ipairs(replaced or {}) do
        if Unfinished(ns.Stats.Facts(other)) then return true end
    end
    return false
end

--[[
    Score.Trade(link, replaced, mate) → mehr, weniger: gezählte Werte, die gegenüber dem Ersetzten steigen bzw. fallen,
    { { key, diff, part }, … }, der gewichtigste zuerst. replaced = Liste von Links (Zweihänder: Haupt- und Schildhand);
    mate = Link des Gegenstücks aus der Tasche, das mitzählt (Paar gegen Zweihänder). nil, solange Daten fehlen.
]]
function Score.Trade(link, replaced, mate)
    local weights = Weighting()
    local new = ns.Stats.Read(link)
    if not new then return nil end
    if mate then
        local stats = ns.Stats.Read(mate)
        if not stats then return nil end
        local both = {}
        for key, value in pairs(new) do both[key] = value end
        for key, value in pairs(stats) do both[key] = (both[key] or 0) + value end
        new = both
    end
    local old = {}
    for _, other in ipairs(replaced or {}) do
        local stats = ns.Stats.Read(other)
        if not stats then return nil end
        for key, value in pairs(stats) do old[key] = (old[key] or 0) + value end
    end
    local more, less = {}, {}
    for key, w in pairs(weights) do
        local diff = (new[key] or 0) - (old[key] or 0)
        if w > 0 and math.abs(diff) > 0.0001 then
            local list = diff > 0 and more or less
            list[#list + 1] = { key = key, diff = diff, part = math.abs(diff) * w }
        end
    end
    local function Heavier(a, b)
        if a.part ~= b.part then return a.part > b.part end
        return a.key < b.key
    end
    table.sort(more, Heavier)
    table.sort(less, Heavier)
    return more, less
end

---------------------------------------------------------------------------
-- Angelegte Ausrüstung
---------------------------------------------------------------------------

local function EquippedLink(slot)
    if wearer then return wearer.links[slot] end
    local link = ns.Plain(ns.Call(GetInventoryItemLink, "player", slot))
    if type(link) == "string" and link ~= "" then return link end
    return nil
end
Score.EquippedLink = EquippedLink

-- Ist das der angelegte Gegenstand? Beim Twink ist nur die Kennung gemerkt (Core.ItemString), bei älteren Datensätzen und
-- ohne Zusatz nur die itemID
local function IsEquipped(slot, link)
    local worn = EquippedLink(slot)
    if not (wearer and worn) then return worn == link end
    local K = Core.Knowledge
    return Core.ItemID(worn) == Core.ItemID(link)
        and (not worn:find("^item:%d+:") or K.VariantKey(worn) == K.VariantKey(link))
end

local function EquippedLoc(slot)
    local link = EquippedLink(slot)
    return link and ns.Stats.EquipLoc(link) or nil
end

-- Zwei Waffen? Beim Twink zählt, was er in der Schildhand trägt, sonst die Klasse ab DUAL_WIELD_LEVEL (Krieger und Jäger
-- lernen es mit 20, der Schurke früher – darunter lieber nicht)
local DUAL_WIELD_LEVEL = 20
local function DualWield()
    if wearer then
        if DUAL_WIELD_CLASSES[wearer.class] ~= true then return false end
        local loc = EquippedLoc(SLOT.OFFHAND)
        if loc then return loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND" end
        return math.max(wearer.level, wearer.from or 0) >= DUAL_WIELD_LEVEL
    end
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
-- Gegenstück aus den Taschen: was neben einem Einhänder bzw. in der Waffenhand läge, wäre der Zweihänder abgelegt
---------------------------------------------------------------------------

local MAIN_LOC = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
Score.MATE_AGE = 1        -- so viele Sekunden gilt die Liste höchstens (Nachgeladenes, neue Fertigkeit); Taschen: BagsChanged
local mateAt = 0

local function Better(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.link < b.link
end

-- → { main = { { link, score, count } … }, off = { … }, open = Daten fehlen noch }, das Beste zuerst; nur Tragbares
local function Mates()
    if mates and Core.Uptime() - mateAt < Score.MATE_AGE then return mates end
    local list = { main = {}, off = {}, open = false }
    local dual, known = DualWield(), { main = {}, off = {} }
    local function Add(hand, link, score)
        local e = known[hand][link]
        if e then
            e.count = e.count + 1
            return
        end
        e = { link = link, score = score, count = 1 }
        known[hand][link] = e
        list[hand][#list[hand] + 1] = e
    end
    Core.ForEachBagItem(function(_, _, info)
        local link = ns.Plain(info.hyperlink)
        if type(link) ~= "string" then return end
        local loc = ns.Stats.EquipLoc(link)          -- erst der Platz (ohne Server), dann das Item-Wissen
        local main = MAIN_LOC[loc] == true
        local off = (ES.IsOffhand(loc) and (dual or loc ~= "INVTYPE_WEAPONOFFHAND")) or (dual and loc == "INVTYPE_WEAPON")
        if not (main or off) then return end
        local facts = ns.Stats.Facts(link)
        if facts and facts.usableNow == false then return end
        local score = Score.Of(link)
        if score == nil then
            list.open = true
            return
        end
        if main then Add("main", link, score) end
        if off then Add("off", link, score) end
    end, "bags")
    table.sort(list.main, Better)
    table.sort(list.off, Better)
    mates, mateAt = list, Core.Uptime()
    -- ein anderes Gegenstück liegt in den Taschen: Pfeile und Vergleiche neu. Die zwei besten je Hand samt Anzahl – ist der
    -- verglichene Gegenstand selbst der beste, entscheiden der nächste und ob er zweimal da ist.
    local parts = {}
    for _, hand in ipairs({ "main", "off" }) do
        for i = 1, 2 do
            local e = list[hand][i]
            parts[#parts + 1] = e and (e.link .. "x" .. math.min(e.count, 2)) or "-"
        end
    end
    local mark = table.concat(parts, "/")
    if mateMark ~= nil and mateMark ~= mark then
        mateMark = mark
        ns.Changed()
        mates = list
    end
    mateMark = mark
    return list
end

-- Taschen geändert: die Liste neu lesen; ist ein Zweihänder angelegt und wurde schon verglichen, gleich nachsehen, ob
-- jetzt ein anderes Gegenstück gilt (offene Händler-, Auktions- und Beute-Zeilen fragen von selbst nicht noch einmal)
local recheck
function Score.BagsChanged()
    mates = nil
    if mateMark == nil or EquippedLoc(SLOT.MAINHAND) ~= "INVTYPE_2HWEAPON" then return end
    recheck = recheck or ns.Throttle(function() Mates() end, 0.3)
    recheck()
end

-- Score.Mate(hand, link) → bestes Gegenstück für hand ("main", "off") aus den Taschen { link, score } oder nil, Daten
-- fehlen noch? Derselbe Link zählt nur, wenn er zweimal in den Taschen liegt (auch ein Teil beim Händler, in der Bank oder
-- als Belohnung gilt mit dem in der Tasche als dasselbe Exemplar – vorsichtig); für die Schildhand nur, was einen Wert hat.
function Score.Mate(hand, link)
    if wearer then return nil, false end         -- die Taschen eines Twinks zählen nicht mit
    local list = Mates()
    for _, e in ipairs(list[hand]) do
        if (e.link ~= link or e.count > 1) and (hand == "main" or e.score > 0) then return e, list.open end
    end
    return nil, list.open
end

---------------------------------------------------------------------------
-- Vergleich
---------------------------------------------------------------------------

--[[
    Score.Compare(link) → info oder nil (kein Ausrüstungsgegenstand, Daten fehlen)
      info.score       Wert des Gegenstands
      info.base        Wert dessen, was er ersetzen würde (0 = leerer Platz)
      info.total       Wert des Paars (nur bei angelegtem Zweihänder: Gegenstand + Gegenstück aus der Tasche)
      info.floor       worüber das Paar kommen muss: der Zweihänder, oder das Gegenstück, wenn es allein schon mehr wert ist –
                       sonst gälte der Gewinn des Gegenstücks als Gewinn dieses Gegenstands (Review 24.11.2026)
      info.delta       score − base (Paar: total − floor)
      info.percent     Prozent besser (bei leerem Platz 100), auf ganze Zahlen gerundet
      info.slot        Inventarplatz, der ersetzt würde
      info.replaces    Link des ersetzten Gegenstands (nil = leer)
      info.replaced    alle ersetzten Links (Zweihänder: Haupt- und Schildhand; leer = leerer Platz)
      info.rises       true, wenn trotz Wert ≤ 0 ein gezählter Wert gegenüber dem Ersetzten steigt
      info.provisional true, wenn das Item-Wissen noch unvollständig ist (das Ergebnis kann sich noch ändern)
      info.empty       true, wenn der Platz leer ist
      info.usable      false, wenn die Klasse ihn nicht tragen kann oder die Stufe fehlt
      info.usableFrom  ab dieser Stufe tragbar (nur, wenn die Stufe fehlt; aus dem Item-Wissen) – verglichen wird wie bei
                       einem tragbaren Gegenstand (usable bleibt false)
      info.minLevel    Mindeststufe des Gegenstands (nur neben usableFrom) – liegt usableFrom darüber, beherrscht die
                       Klasse die Rüstungsart erst später (Schwere Rüstung, Platte ab 40)
      info.armorType   Rüstungs- bzw. Waffenart („Leder“), wenn die Klasse ihn nicht tragen kann
      info.learn       Weg, wenn die Klasse die Waffen- bzw. Rüstungsfertigkeit lernen kann, der Charakter sie aber noch
                       nicht hat (ezCore.Proficiency.Way: name, from, trainer, place; aus dem Item-Wissen, facts.learn) –
                       dann wird verglichen wie bei einem tragbaren Gegenstand (Paket ezgear/lernbar-tragbar; usable
                       bleibt false). Fehlt dazu die Mindeststufe des Gegenstands, steht auch info.usableFrom da.
      info.learnType   Rüstungs- bzw. Waffenart des Gegenstands neben info.learn („Platte“), wie Blizzards Tooltip sie nennt
      info.equipped    true, wenn genau dieser Gegenstand schon angelegt ist
      info.twoHand     true bei Einhändern und Schildhand, solange ein Zweihänder angelegt ist: verglichen wird das Paar
      info.mate        Link des Gegenstücks aus den Taschen (nil = keines, die andere Hand zählt leer)
      info.mateHand    Hand des Gegenstücks: "main" oder "off"
      info.mateOpen    true, solange Daten möglicher Gegenstücke noch laden
      info.pending     true, wenn Daten noch laden (dann ohne Ergebnis)
]]

local function PlayerLevel()
    if wearer then return wearer.level end
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
    if wearer then
        -- ob seine Klasse es tragen kann, hat Alts.Check geprüft; hier fehlt höchstens die Stufe
        if wearer.from and wearer.from > wearer.level then
            info.usable, info.usableFrom, info.minLevel = false, wearer.from, facts and ns.Num(facts.minLevel) or nil
        end
    elseif facts and facts.usableNow == false then
        info.usable = false
        local from = ns.Num(facts.usableFrom)
        local learn = type(facts.learn) == "table" and facts.learn or nil
        local level, minLevel = PlayerLevel(), ns.Num(facts.minLevel)
        local kind = type(facts.subClassName) == "string" and facts.subClassName ~= "" and facts.subClassName or nil
        if facts.skillMissing then
            -- Berufsfertigkeit fehlt: auch mit Stufe und Waffenmeister nicht tragbar
            local req = type(facts.reqSkill) == "table" and facts.reqSkill or {}
            info.armorType = type(req.name) == "string" and req.name ~= "" and L.TIP_REQ_SKILL:format(req.name, ns.Num(req.rank) or 1) or kind
        elseif learn then
            -- erst lernen (Waffenmeister, Platte ab 40): vergleichen wie tragbar, Stand „learn“ statt „besser“. Fehlt
            -- zugleich die Mindeststufe des Gegenstands, gilt sie (die Stufe der Rüstungsart nennt der Weg)
            info.learn, info.learnType = learn, kind
            if minLevel and minLevel > level then info.usableFrom, info.minLevel = minLevel, minLevel end
        elseif from and from > level then
            -- nur die Stufe fehlt: vergleichen wie tragbar, Stand „level“ statt „besser“
            info.usableFrom, info.minLevel = from, minLevel
        else
            info.armorType = kind
        end
    end

    for _, slot in ipairs(slots) do
        if IsEquipped(slot, link) then
            info.equipped, info.slot = true, slot
            return info
        end
    end

    -- Schildhandwaffe, aber keine zwei Waffen geführt: nicht anlegbar (das Item-Wissen prüft nur Waffenart und Klasse) –
    -- fehlt zugleich die Stufe, nur, wenn es die Klasse auch später nicht lernt
    if loc == "INVTYPE_WEAPONOFFHAND" and not DualWield()
        and (info.usable or wearer or DUAL_WIELD_CLASSES[ns.playerClass or ""] ~= true) then
        info.usable, info.armorType = false, ES.LocLabel and ES.LocLabel(loc) or nil
        info.usableFrom, info.learn = nil, nil
    end

    local score = Score.Of(link)
    if score == nil then
        info.pending = true
        return info
    end
    info.score = score

    local base, slot, replaces, also
    local mainLoc = EquippedLoc(SLOT.MAINHAND)
    local pairOff = mainLoc == "INVTYPE_2HWEAPON" and ES.IsOffhand(loc)
    local pairMain = mainLoc == "INVTYPE_2HWEAPON" and MAIN_LOC[loc] == true
    if pairOff or pairMain then
        -- Paar gegen Zweihänder (Dateikopf)
        local main, mainLink = SlotScore(SLOT.MAINHAND)
        if main == nil then info.pending = true return info end
        local hand = pairOff and "main" or "off"
        local mate, open = Score.Mate(hand, link)
        base, replaces = main, mainLink
        slot = pairOff and SLOT.OFFHAND or SLOT.MAINHAND
        info.twoHand, info.mateHand, info.mate = true, hand, mate and mate.link or nil
        info.total = score + (mate and mate.score or 0)
        info.floor = math.max(main, mate and mate.score or 0)
        info.mateOpen = open or nil
    elseif loc == "INVTYPE_2HWEAPON" then
        local main, mainLink = SlotScore(SLOT.MAINHAND)
        local off = SlotScore(SLOT.OFFHAND)
        if main == nil or off == nil then info.pending = true return info end
        base, slot, replaces = main + off, SLOT.MAINHAND, mainLink
        also = EquippedLink(SLOT.OFFHAND)
    elseif ES.IsOffhand(loc) then
        base, replaces = SlotScore(SLOT.OFFHAND)
        slot = SLOT.OFFHAND
    elseif loc == "INVTYPE_WEAPON" then
        local main, mainLink = SlotScore(SLOT.MAINHAND)
        if main == nil then info.pending = true return info end
        base, slot, replaces = main, SLOT.MAINHAND, mainLink
        local offLoc = EquippedLoc(SLOT.OFFHAND)
        local offIsWeaponOrEmpty = offLoc == nil or offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND"
        if DualWield() and offIsWeaponOrEmpty then
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
    info.replaced = {}
    if replaces then info.replaced[1] = replaces end
    if also then info.replaced[#info.replaced + 1] = also end
    info.empty = replaces == nil
    local total, floor = info.total or score, info.floor or base
    info.delta = total - floor
    if score <= 0 and not info.empty then
        -- „keine Werte, die zählen“ darf nicht dastehen, wenn ein gezählter Wert steigt (ein anderer ist negativ)
        -- (ohne das Gegenstück: was es mitbringt, spricht nicht für diesen Gegenstand)
        local more = Score.Trade(link, info.replaced)
        info.rises = type(more) == "table" and #more > 0 or nil
    end
    if floor > 0 then
        info.percent = math.floor(info.delta / floor * 100 + 0.5)
    else
        info.percent = info.delta > 0 and 100 or info.delta < 0 and -100 or 0
    end
    info.provisional = info.mateOpen or Provisional(link, info.replaced, info.mate) or nil
    return info
end

--[[
    Score.Verdict(info) → Stand eines Vergleichs (eine Regel für Pfeile, Tooltip und Status):
      "better"    besser – grüner Pfeil (mindestens minPercent, oder Platz leer)
      "learn"     wäre besser, sobald der Charakter die Fertigkeit gelernt hat (info.learn) – gelber Pfeil. Zählt nicht
                  als „besser“ (IsUpgrade, Questbelohnung, Meldung in ezPanel): jetzt kann er ihn nicht anlegen.
                  Schlechter oder gleich bleibt „worse“ bzw. „same“ (der Text nennt den Weg trotzdem).
      "level"     wäre besser, sobald die Stufe reicht (info.usableFrom) – gelber Pfeil, sonst wie „learn“; fehlt beides,
                  steht „level“ (der Text nennt Stufe und Weg)
      "worse"     schlechter – roter Pfeil (mindestens minPercent bzw. 1 % schlechter, oder ohne zählende Werte
                  gegen etwas Angelegtes)
      "same"      kaum Unterschied
      "nostats"   keine Werte, die für die Gewichtung zählen (und am Platz liegt nichts Besseres)
      "unusable"  die Klasse kann ihn nicht tragen (info.armorType)
      "equipped"  genau dieser ist angelegt
      "pending"   Daten laden noch
    nil, wenn es kein Ausrüstungsgegenstand ist.
]]
-- Stände „wäre besser, sobald …“: gelber Pfeil, kein Upgrade
Score.LATER = { learn = true, level = true }

-- Lohnt es sich, ein Teil dieses Stands zu behalten (grüner oder gelber Pfeil)? Die eine Regel für alle Module: ezBag
-- („Platz schaffen“), ezCraft (Entzaubern, Zerlegen) und ezAuction („Nur Verbesserungen“); Durchsicht 24.11.2026.
function Score.Keeps(kind) return kind == "better" or Score.LATER[kind] == true end

function Score.Verdict(info)
    if not info then return nil end
    if info.equipped then return "equipped" end
    if info.usable == false and not info.learn and not info.usableFrom then return "unusable" end
    if info.pending or info.score == nil then return "pending" end
    local min = (ns.S and tonumber(ns.S.minPercent)) or 0
    if info.score <= 0 and not info.rises then
        -- im Paar kann das Gegenstück allein besser sein: das macht diesen Gegenstand nicht schlechter
        if (info.base or 0) > 0 and not (info.total and info.delta >= 0) then return "worse" end
        return "nostats"
    end
    if info.empty or (info.delta > 0 and info.percent >= min) then
        return info.usableFrom and "level" or info.learn and "learn" or "better"
    end
    if info.delta < 0 and -info.percent >= math.max(min, 1) then return "worse" end
    return "same"
end

-- Score.For(twink, link) → Stand, info für einen Twink (Alts.List) – dieselbe Regel mit seiner Ausrüstung, Stufe und
-- Gewichtung; nil bei einem Fehler
function Score.For(who, link)
    local before = wearer
    wearer = who
    local ok, info = pcall(Score.Compare, link)
    wearer = before
    if not ok then
        Core.Error("ezGear", info, "Score.For")
        return nil
    end
    return Score.Verdict(info), info
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

-- Score.IsDowngrade(link) → true/false, info; nil, solange Daten fehlen (schlechter als das Angelegte; tragbar oder es
-- fehlt nur die Stufe bzw. die Fertigkeit)
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

-- Weg zur Fertigkeit (info.learn, ezCore.Proficiency.Way) als Text: „Platte ab Stufe 40“, „erst Schwerter lernen
-- (Waffenmeister)“, mit Ort nur aus Selbsterhobenem („(Waffenmeister in Eisenschmiede)“).
-- Wartet der Weg noch auf eine Stufe (Platte ab 40)? Dann sagt dasselbe auch ezCores Item-Wissen („Tragbar ab Stufe:
-- 40 … (Platte erst ab Stufe 40)“) – der Tooltip zeigt den Zusatz dann nicht doppelt (GEAR-01, Tooltip.lua).
function Score.LearnByLevel(info)
    local learn = info and info.learn
    local from = type(learn) == "table" and ns.Num(learn.from) or nil
    return from ~= nil and from > PlayerLevel()
end

function Score.LearnText(info)
    local learn = info and info.learn
    if type(learn) ~= "table" then return nil end
    local what = info.learnType or learn.name or L.TIP_LEARN_ANY
    if Score.LearnByLevel(info) then return L.TIP_LEARN_LEVEL:format(what, ns.Num(learn.from)) end
    local who = (learn.trainer == "weaponmaster" and L.TRAINER_WEAPONMASTER)
        or (learn.trainer == "class" and L.TRAINER_CLASS) or nil
    if not who then return L.TIP_LEARN:format(what) end
    local place = type(learn.place) == "table" and learn.place.zone or nil
    if type(place) == "string" and place ~= "" then who = L.TRAINER_IN:format(who, place) end
    return L.TIP_LEARN_AT:format(what, who)
end

-- Was noch fehlt, als Text: „ab Stufe 24“, „erst Schwerter lernen (Waffenmeister)“, beides mit Komma; nil, wenn nichts
-- fehlt. withoutLevel = true: ohne die Stufen (der Tooltip, wenn das Item-Wissen sie schon nennt).
function Score.WayText(info, withoutLevel)
    if not info then return nil end
    local parts = {}
    if info.usableFrom and not withoutLevel then parts[1] = L.TIP_FROM_LEVEL:format(info.usableFrom) end
    if info.learn then
        -- die Stufe der Rüstungsart (Platte ab 40) steckt in der höheren Mindeststufe des Gegenstands
        local covered = Score.LearnByLevel(info)
            and (withoutLevel or (info.usableFrom or 0) >= (ns.Num(info.learn.from) or 0))
        if not covered then parts[#parts + 1] = Score.LearnText(info) end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Score.Describe(info) → Text, besser?, Stand – für jeden Ausrüstungsgegenstand eine Aussage, warum (Leitlinie 3):
-- „+12 % für Verstärkung“, „−8 % für …“, „Nicht tragbar (Leder)“, „Werte werden gelesen …“.
-- Fehlt nur die Stufe oder die Fertigkeit, hängt an, was fehlt (Score.WayText): „+12 % für Schaden – ab Stufe 24“, „+18 %
-- für Schaden – erst Schwerter lernen (Waffenmeister)“ („besser?“ ist dann false: jetzt nicht anlegbar).
-- withoutLevel = true: ohne die Stufen. nil nur ohne Aussage (kein Ausrüstungsgegenstand, genau dieser ist angelegt).
local DescribeBase   -- unten: die Aussage ohne das, was fehlt
function Score.Describe(info, withoutLevel)
    local text, better, kind = DescribeBase(info)
    local compared = info and kind ~= "pending" and kind ~= "unusable" and ((info.score or 0) > 0 or info.rises)
    local pair = text and compared and Score.PairText(info)
    if pair then text = text .. " " .. pair end
    local later = info and (info.learn or info.usableFrom)
    if text and later and kind ~= "pending" then
        local way = Score.WayText(info, withoutLevel)
        if way then text = text .. " – " .. way end
    end
    if later then better = false end
    return text, better, kind
end

-- Womit verglichen wurde, solange ein Zweihänder angelegt ist: „(mit Spitzhacke in der Waffenhand statt des
-- Zweihänders)“; sonst nil
function Score.PairText(info)
    if not (info and info.twoHand and info.mateHand) then return nil end
    local key = "TIP_PAIR_" .. info.mateHand
    if not info.mate then return info.mateOpen and L.TIP_PAIR_open or L[key .. "_none"] end
    return L[key]:format(Core.ItemName(info.mate) or Core.ItemNameByID(info.mate) or info.mate)
end

-- Schlechter, obwohl ein gezählter Wert steigt: „Mehr: Schaden pro Sekunde (Distanz) 3,2 · Weniger: Ausdauer 4“ –
-- höchstens Score.TRADE_MAX Werte je Seite, der gewichtigste zuerst; sonst nil.
Score.TRADE_MAX = 2
function Score.TradeText(link, info)
    if Score.Verdict(info) ~= "worse" or not info.replaced then return nil end
    local more, less = Score.Trade(link, info.replaced, info.mate)
    if not more or #more == 0 or #less == 0 then return nil end
    local function List(list)
        local out = {}
        for i = 1, math.min(#list, Score.TRADE_MAX) do
            local diff = math.abs(list[i].diff)
            local digits = math.abs(diff - math.floor(diff + 0.5)) > 0.05 and 1 or 0
            out[i] = L.TIP_TRADE_VALUE:format(ns.Stats.Name(list[i].key), Core.Decimal(diff, digits))
        end
        return table.concat(out, ", ")
    end
    return L.TIP_TRADE:format(List(more), List(less))
end

DescribeBase = function(info)
    local kind = Score.Verdict(info)
    if kind == nil or kind == "equipped" then return nil end
    local label = ns.Weights.Label()
    if kind == "pending" then return L.TIP_PENDING, false, kind end
    if kind == "unusable" then
        if info.armorType then return L.TIP_UNUSABLE_TYPE:format(info.armorType), false, kind end
        return L.TIP_UNUSABLE, false, kind
    end
    if kind == "nostats" then return L.TIP_NOSTATS:format(label), false, kind end
    if info.empty then return L.TIP_EMPTY:format(label), true, kind end
    if info.score <= 0 and not info.rises then return L.TIP_NOSTATS_WORSE:format(label), false, kind end
    if info.percent > 0 then return L.TIP_BETTER:format(info.percent, label), kind == "better", kind end
    if info.percent < 0 then return L.TIP_WORSE:format(-info.percent, label), false, kind end
    return L.TIP_SAME:format(label), false, kind
end

---------------------------------------------------------------------------
-- Schnittstelle für die anderen Module (ezCore.API("ezGear")); im README-Abschnitt beschrieben
---------------------------------------------------------------------------

-- Stände, die unvollständiges Item-Wissen (info.provisional) noch zum Pfeil wenden kann
local OPEN_KINDS = { worse = true, same = true, nostats = true }

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
    -- Stand eines Gegenstands (siehe Score.Verdict; "learn" = besser, sobald gelernt, "level" = besser, sobald die Stufe
    -- reicht – beide kein Upgrade für IsUpgrade), Text wie im Tooltip, info wie Compare (info.learn: Weg laut
    -- ezCore.Proficiency.Way, info.usableFrom: ab dieser Stufe)
    Status = function(link)
        local info = Score.Compare(link)
        local text = Score.Describe(info)
        return Score.Verdict(info), text, info
    end,
    -- Stand mit grünem oder gelbem Pfeil? (Stände aus Status)
    Keeps = function(kind) return Score.Keeps(kind) end,
    -- true/false (nil = Daten laden noch): besser als das Angelegte – jetzt oder sobald gelernt bzw. die Stufe reicht. Wer
    -- etwas zum Wegwerfen oder Zerlegen vorschlägt, fragt das. nil auch, solange das Item-Wissen unvollständig ist
    -- (info.provisional) oder Daten möglicher Gegenstücke laden (eine Schildhand gegen einen angelegten Zweihänder steht
    -- bis dahin als „schlechter“ da)
    WorthKeeping = function(link)
        local info = Score.Compare(link)
        local kind = Score.Verdict(info)
        if kind == "pending" or (info and info.mateOpen and not Score.Keeps(kind)) then return nil end
        if info and info.provisional and OPEN_KINDS[kind] then return nil end
        return Score.Keeps(kind)
    end,
    -- true/false (nil = Daten laden noch): schlechter als das Angelegte (roter Pfeil; tragbar oder es fehlt nur die Stufe
    -- bzw. die Fertigkeit)
    IsDowngrade = function(link)
        local down, info = Score.IsDowngrade(link)
        return down, info and info.percent or nil, info
    end,
    ScaleName = function() return ns.Weights.Label() end,
    -- grüner Pfeil, wenn besser; gelber, wenn besser, sobald die Stufe reicht bzw. die Waffen- oder Rüstungsart gelernt
    -- ist; roter Pfeil nach unten, wenn schlechter (Schalter „Roter Pfeil“); link = nil leert
    SetUpgradeIcon = function(button, link) return ns.Marks and ns.Marks.SetUpgrade(button, link) end,
    -- graues Zeichen zu einem Stand ohne Pfeil (Marks.STATUS_SIGNS), sonst nil – damit die Listen anderer Module (ezAuction,
    -- ezCraft) für jede Ausrüstung etwas zeigen; kind = Stand von Status (nil: dieser Platz wird nicht bewertet)
    StatusSign = function(kind) return ns.Marks and ns.Marks.StatusSign(kind) or nil end,
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
