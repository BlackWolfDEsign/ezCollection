local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Lehrer:
      - Knopf „Alles lernen (Kosten)“ in Blizzards Lehrerfenster links neben „Lernen“. Reicht das Gold nicht,
        zuerst die höchsten Stufen und Ränge; während des Lernens heißt der Knopf „Anhalten“, Shift hält auch an.
        Nicht beim Tierausbilder (Trainingspunkte) und nie für einen neuen Beruf (Blizzard fragt dort selbst nach).
        Übernimmt schon ein anderes Addon „alles lernen“ (Erkennung in ezCore: Core.WhoHandles("trainAll"), heute
        Tweaks Forever mit seinem Schalter), zeigt ezMerchant seinen Knopf nicht und nennt das Addon im Status
        und im Tooltip der Einstellung (Leitlinie 9).
      - Was beim Lehrer wartet (T.Waiting, aus ezCore) – die Meldung beim Stufenaufstieg baut LevelUp.lua daraus.
      - Zauber beim Namen (T.SpellList, T.Names): „… gelernt für …“ nach „Alles lernen“ und „Neu beim Lehrer“ nennen
        die Zauber mit Rang und Einzelpreis, als Link, wo der Client einen liefert (Einstellung spellNames).
    Die Lehrerdaten lernt ezCore bei jedem Besuch (Core.Spells); hier wird nur angezeigt und auf Knopfdruck gekauft.
]]

local T = {}
ns.Trainer = T

local function Spells() return Core.Spells end

local function PetTrainer()
    local pet = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    if pet == nil or not (C_Trainer and C_Trainer.GetTrainerType) then return false end
    local ok, kind = pcall(C_Trainer.GetTrainerType)
    return ok and kind == pet
end
T.PetTrainer = PetTrainer

-- Übernimmt schon ein anderes Addon „alles lernen“ beim Lehrer? Dann dessen Name, sonst nil (Liste in ezCore,
-- OtherAddOns.lua). Jeder Aufruf liest frisch: ein umgelegter Schalter des fremden Addons gilt sofort.
function T.Other()
    return (ns.OtherFor("trainAll"))
end

-- spellID eines Eintrags im offenen Lehrerfenster laut Client (Core.TrainerSpellID, Welle 23 A45: über
-- C_TooltipInfo.GetTrainerService) oder nil – damit nennt „… gelernt“ den Zauber auch ohne Entdecker-Datenbank und
-- ohne Zauber je Stufe sicher mit Link (T.SpellID nimmt das Feld id zuerst). Gefragt wird nur beim Kauf (vor
-- BuyTrainerService – danach rückt Blizzards Liste nach), nicht bei jedem Neuzeichnen des Knopfs.
function T.ServiceSpellID(index)
    local fn = Core.TrainerSpellID
    if type(fn) ~= "function" then return nil end
    local ok, id = pcall(fn, index)
    return ok and ns.Num(id) or nil
end

-- Was der offene Lehrer jetzt beibringen kann, wichtigstes zuerst: { index, name, rank, level, cost }, Summe.
function T.Learnable()
    local list, total = {}, 0
    if not (GetNumTrainerServices and GetTrainerServiceInfo) or PetTrainer() then return list, total end
    local parse = Spells() and Spells().ParseRank
    for index = 1, GetNumTrainerServices() or 0 do
        local name, serviceType, _, reqLevel, subText = GetTrainerServiceInfo(index)
        name, serviceType = Core.Plain(name), Core.Plain(serviceType)
        if serviceType == "available" and type(name) == "string" and name ~= "" then
            local cost, isProfession = 0, false
            if GetTrainerServiceCost then cost, isProfession = GetTrainerServiceCost(index) end
            if not isProfession then
                cost = ns.Num(cost) or 0
                list[#list + 1] = { index = index, name = name, rank = parse and parse(subText) or 0,
                    level = ns.Num(reqLevel) or 0, cost = cost }
                total = total + cost
            end
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name < b.name
    end)
    return list, total
end

-- Wie viele davon reichen fürs Gold (in der Reihenfolge oben)? Anzahl, Summe.
function T.Affordable(list)
    local money, count, spent = GetMoney(), 0, 0
    for _, entry in ipairs(list) do
        if spent + entry.cost <= money then
            count, spent = count + 1, spent + entry.cost
        end
    end
    return count, spent
end

---------------------------------------------------------------------------
-- Alles lernen: einer nach dem anderen (die Liste verschiebt sich nach jedem Kauf)
---------------------------------------------------------------------------

local learning
-- Abstand zwischen zwei Käufen (Blizzards Liste rückt nach jedem Kauf nach) und Schutz gegen den Doppelklick: ein
-- Klick auf „Anhalten“ kurz nach dem Start zählt nicht – sonst lernte ein Doppelklick einen Zauber und hielte an
-- (früher war der Knopf während des Lernens gesperrt).
local STEP_DELAY, STOP_GUARD = 0.35, 0.4
T.STEP_DELAY, T.STOP_GUARD = STEP_DELAY, STOP_GUARD
local lastBuy                                   -- GetTime() des letzten Kaufs, auch über einen Lauf hinaus

local function Finish(stopped)
    local job = learning
    learning = nil
    if not job then return end
    if job.count == 0 and not stopped then
        ns.Print(L.LEARN_NOTHING_AFFORDABLE)
    else
        -- was gelernt wurde, beim Namen (Einstellung spellNames); ohne Namen wie bisher nur Anzahl und Summe
        local names = job.count > 0 and T.Names(job.bought, { cost = true }) or nil
        if names then
            ns.Print((stopped and L.LEARN_STOPPED_NAMED or L.LEARN_DONE_NAMED):format(job.count, ns.Money(job.spent), names))
        else
            ns.Print((stopped and L.LEARN_STOPPED or L.LEARN_DONE):format(job.count, ns.Money(job.spent)))
        end
    end
    local rest, restCost = T.Learnable()
    if not stopped and #rest > 0 then ns.Print(L.LEARN_LEFT:format(#rest, ns.Money(restCost))) end
    T.Update()
end

-- Ein Schritt gehört zu genau einem Lauf: ein Zeitgeber aus einem angehaltenen Lauf tut nichts (sonst liefen nach
-- „Anhalten“ und erneutem Klick zwei Ketten nebeneinander – doppelte Käufe, „zu wenig Geld“, zu hohe Abschlusszahl).
local Step
local function StepLater(job, delay)
    C_Timer.After(delay, function() Step(job) end)
end

Step = function(job)
    if not job or job ~= learning then return end
    if IsShiftKeyDown() then return Finish(true) end
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then return Finish(true) end
    local money = GetMoney()
    for _, entry in ipairs((T.Learnable())) do
        local key = entry.name .. "#" .. entry.rank
        if not job.tried[key] and entry.cost <= money then
            job.tried[key] = true
            local id = T.ServiceSpellID(entry.index)
            BuyTrainerService(entry.index)
            lastBuy = GetTime()
            job.count, job.spent = job.count + 1, job.spent + entry.cost
            job.bought[#job.bought + 1] = { name = entry.name, rank = entry.rank, level = entry.level, cost = entry.cost,
                id = id }
            StepLater(job, STEP_DELAY)
            return
        end
    end
    Finish(false)
end

function T.LearnAll()
    if learning then return false end
    local list = T.Learnable()
    if #list == 0 then
        ns.Print(L.LEARN_NOTHING)
        return false
    end
    local job = { count = 0, spent = 0, tried = {}, bought = {}, started = GetTime() }
    learning = job
    -- Gleich nach einem angehaltenen Lauf: erst den Abstand zum letzten Kauf abwarten (Blizzards Liste rückt nach).
    local wait = lastBuy and (lastBuy + STEP_DELAY - GetTime()) or 0
    if wait > 0 then
        StepLater(job, wait)
    else
        Step(job)
    end
    T.Update()
    return true
end

function T.Busy() return learning ~= nil end

-- Anhalten (der Knopf heißt während des Lernens „Anhalten“; Shift hält weiter zusätzlich an). → true, wenn
-- ein Lauf angehalten wurde (V-126).
function T.Stop()
    if not learning then return false end
    Finish(true)
    return true
end

-- Klick auf den Knopf: lernt alles bzw. hält den laufenden Lauf an. Der zweite Klick eines Doppelklicks
-- (binnen STOP_GUARD nach dem Start) hält nicht an. → true, wenn etwas gestartet oder angehalten wurde
function T.Click()
    if learning then
        if GetTime() - (learning.started or 0) < STOP_GUARD then return false end
        return T.Stop()
    end
    return T.LearnAll()
end

---------------------------------------------------------------------------
-- Knopf im Lehrerfenster
---------------------------------------------------------------------------

local button

local function ShowTooltip(self)
    local list, total = T.Learnable()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Rollen statt Farbzahlen (T9-6)
    Core.TipTitle(GameTooltip, learning and L.LEARN_STOP or L.LEARN_ALL)
    if learning then
        Core.TipText(GameTooltip, L.LEARN_STOP_TIP)
    elseif #list == 0 then
        Core.TipText(GameTooltip, L.LEARN_NOTHING)
    else
        Core.TipText(GameTooltip, L.LEARN_TIP:format(#list, ns.Money(total)))
        local count, spent = T.Affordable(list)
        if count < #list then
            Core.TipLine(GameTooltip, L.LEARN_TIP_SHORT:format(count, #list, ns.Money(spent)), "bad", true)
        end
        for i = 1, math.min(#list, 8) do
            local entry = list[i]
            local name = entry.rank > 0 and L.SPELL_RANK:format(entry.name, entry.rank) or entry.name
            Core.TipDoubleLine(GameTooltip, name, ns.Money(entry.cost), "highlight", "highlight")
        end
        if #list > 8 then Core.TipLine(GameTooltip, Core.More(#list - 8), "hint") end
    end
    Core.TipLine(GameTooltip, L.LEARN_SHIFT, "hint", true)
    GameTooltip:Show()
end

function T.Update()
    if not button then return end
    -- Ein anderes Addon lernt schon alles: kein zweiter Knopf. Ein laufender Lauf behält seinen Knopf „Anhalten“.
    local shown = ns.Enabled("learnAll") and ClassTrainerFrame ~= nil and ClassTrainerFrame:IsShown() and not PetTrainer()
        and (learning ~= nil or T.Other() == nil)
    button:SetShown(shown)
    if not shown then return end
    T.FitButton()
    if learning then
        -- Während des Lernens bleibt der Knopf bedienbar und hält an (V-126).
        button:SetText(L.LEARN_STOP)
        button:SetEnabled(true)
        return
    end
    local list, total = T.Learnable()
    local text = total > 0 and L.LEARN_ALL_COST:format(Core.PlainMoney(total)) or L.LEARN_ALL
    button:SetText(text)
    -- Passt der Betrag nicht auf den Knopf, steht er nur im Tooltip.
    local label = button.GetFontString and button:GetFontString()
    if label and label.GetStringWidth and label:GetStringWidth() > (button:GetWidth() or 0) - 12 then
        button:SetText(L.LEARN_ALL)
    end
    button:SetEnabled(#list > 0 and not learning and T.Affordable(list) > 0)
end

-- Breite des Knopfs: der Platz zwischen Goldanzeige (endet etwa bei 165 vom linken Fensterrand) und Blizzards
-- „Lernen“. Die Lage bestimmt EIN Anker (RIGHT an „Lernen“ bzw. BOTTOMRIGHT am Fenster) – früher legte ein
-- zweiter Anker die Höhe ein zweites Mal und anders fest (V-123). → Breite
local MONEY_END, WIDTH_DEFAULT, WIDTH_MIN, WIDTH_MAX = 166, 96, 60, 160
function T.ButtonWidth()
    local train = _G.ClassTrainerTrainButton
    local right = train and train.GetLeft and ns.Num(train:GetLeft())
    local left = ClassTrainerFrame and ClassTrainerFrame.GetLeft and ns.Num(ClassTrainerFrame:GetLeft())
    if not (right and left) then return WIDTH_DEFAULT end
    return math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.floor(right - left - MONEY_END)))
end

-- Passt die Breite an, sobald Blizzards Fenster seine Lage kennt (erst sichtbar liefert GetLeft etwas).
function T.FitButton()
    if button then button:SetWidth(T.ButtonWidth()) end
end

local function CreateButton()
    if button or not ClassTrainerFrame then return end
    local ok, b = pcall(CreateFrame, "Button", "ezMerchantLearnAllButton", ClassTrainerFrame, "MagicButtonTemplate")
    if not ok or not b then
        ok, b = pcall(CreateFrame, "Button", "ezMerchantLearnAllButton", ClassTrainerFrame, "UIPanelButtonTemplate")
        if not ok or not b then return end
    end
    button = b
    button:SetHeight(22)
    -- Links neben Blizzards „Lernen“, rechts von der Goldanzeige (die endet etwa bei 165)
    local train = _G.ClassTrainerTrainButton
    if train then
        button:SetPoint("RIGHT", train, "LEFT", 0, 0)
    else
        button:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -80, 4)
    end
    button:SetWidth(T.ButtonWidth())
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnClick", function() ns.Try("LearnAll", T.Click) end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ClassTrainerFrame:HookScript("OnShow", T.Update)
    ClassTrainerFrame:HookScript("OnHide", function()
        if learning then Finish(true) end
    end)
    T.button = button
    T.Update()
end

local UpdateSoon = ns.Throttle(function() T.Update() end, 0.1)
ns.On("TRAINER_UPDATE", function() UpdateSoon() end)
ns.On("TRAINER_SHOW", function() UpdateSoon() end)
ns.On("PLAYER_MONEY", function() if button and button:IsShown() then UpdateSoon() end end)

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_TrainerUI", CreateButton)
end)

---------------------------------------------------------------------------
-- Stufenaufstieg: neue Ränge beim Lehrer
---------------------------------------------------------------------------

-- Was beim Lehrer wartet: Anzahl, Kosten (nil ohne Lehrerbesuch), Quelle ("trainer"/"book"), mit Lehrerbesuch die
-- Liste ({ name, rank, level, cost, … }). Gezählt wird in ezCore (Core.Spells.Waiting), damit ezPanel und ezMerchant
-- dieselbe Zahl zeigen.
function T.Waiting(level)
    local S = Spells()
    if not (S and S.Waiting) then return nil end
    local count, cost, source, list = S.Waiting(level)
    return count, cost, source, list
end

---------------------------------------------------------------------------
-- Zauber beim Namen (Wunsch des Nutzers vom 15.11.2026 zu „Neu beim Lehrer: 1 Zauber oder Rang für 10 Kupfer“ und
-- „1 gelernt für 10 Kupfer“: „hier wärs cool zu wissen welche zauber jetzt lernbar sind“). Daten aus dem Client
-- (Leitlinie 11): die Zauber-ID aus ezCores Lehrer-Angebot (Core.Trainers.Offers – Schlüssel ist die spellID, wenn
-- das Lehrerfenster eine liefert) oder aus den Zaubern je Stufe laut Client (Core.Spells.LevelSpells), der Link
-- vom Client (C_Spell.GetSpellLink); ohne Link der Name aus dem Lehrerfenster bzw. Core.SpellName – nie eine
-- eigene Namenstabelle.
---------------------------------------------------------------------------

T.MAX_NAMES = 5         -- so viele Zauber je Meldung, danach „und n weitere“

-- Zauber-IDs aus ezCores Lehrer-Angebot: { ["Name#Rang"] = spellID }. kind wie bei Core.Spells ("MAGE",
-- "HUNTER:PET"; Standard: eigene Klasse). Angebote ohne spellID (Notschlüssel) fehlen; ohne Datenbank leer.
function T.OfferIDs(kind)
    local out = {}
    local DB, offers = Core.DB, Core.Trainers
    local keys = type(DB) == "table" and DB.Keys
    if not (type(keys) == "table" and type(keys.Offer) == "function" and type(offers) == "table"
        and type(offers.Offers) == "function") then
        return out
    end
    kind = kind or Core.PlayerClass()
    if type(kind) ~= "string" then return out end
    local class, suffix = kind:match("^(%u+)(.*)$")
    if not class or (suffix ~= "" and suffix ~= ":PET") then return out end
    local okArt, art = pcall(keys.Offer, suffix == ":PET" and "pet" or "class", class)
    if not okArt or type(art) ~= "string" then return out end
    local ok, row = pcall(offers.Offers, art)
    local svc = ok and type(row) == "table" and row.svc
    if type(svc) ~= "table" then return out end
    for key, s in pairs(svc) do
        local id = ns.Num(key)
        if id and type(s) == "table" then
            local name = Core.SpellName(id)
            if name then out[name .. "#" .. (ns.Num(s.rank) or 0)] = id end
        end
    end
    return out
end

-- Zauber-IDs deiner Klasse laut Client-Tabellen (Welle 26, wago F3: Core.ClientData.ClassSpells, Rang über den
-- englischen Namen gezählt): { ["Name#Rang"] = spellID }, Name aus dem Client (Spells.Name, nur Client-Namen). Einmal
-- gebaut; bleibt es leer (Namen noch nicht geladen, keine Tabelle), fragt der nächste Aufruf neu.
local tableIDs
function T.TableIDs()
    if tableIDs then return tableIDs end
    local out = {}
    local CD, S = Core.ClientData, Spells()
    if not (type(CD) == "table" and type(CD.ClassSpells) == "function" and S and type(S.Name) == "function") then
        return out
    end
    local class = Core.PlayerClass()
    if type(class) ~= "string" then return out end
    local ok, list = pcall(CD.ClassSpells, class)
    for _, e in ipairs(ok and type(list) == "table" and list or {}) do
        -- ohne Lernzauber des Begleiters und ohne ausgelöste Zauber (Welle 27; ein ausgelöster trägt die Nummer seines
        -- Geschwisters und ersetzte sonst dessen ID unter Name#Rang)
        local id = type(e) == "table" and e.pet ~= true and e.triggered ~= true and ns.Num(e.id)
        if id then
            local okName, name, fromClient = pcall(S.Name, id)
            if okName and fromClient == true and type(name) == "string" and name ~= "" then
                out[name .. "#" .. (ns.Num(e.rank) or 0)] = id
            end
        end
    end
    if next(out) ~= nil then tableIDs = out end
    return out
end

-- Zauber-ID eines Lehrer-Eintrags ({ id, name, rank, level }): das Feld id; sonst ezCores Angebot (gleicher Name und
-- Rang); sonst die Client-Tabellen (gleicher Name und Rang, T.TableIDs; Welle 26); sonst die Zauber, die man laut
-- Client auf seiner Stufe lernt (gleicher Name – zwei gleichen Namens nur mit gleichem Rang). Die beiden letzten nicht
-- für Begleiter, das sind die Listen des Spielers. nil, wenn nichts sicher passt.
function T.SpellID(entry, offers, pet)
    if type(entry) ~= "table" then return nil end
    local id = ns.Num(entry.id)
    if id then return id end
    local name = Core.Plain(entry.name)
    if type(name) ~= "string" or name == "" then return nil end
    local rank = ns.Num(entry.rank) or 0
    id = type(offers) == "table" and offers[name .. "#" .. rank]
    if id then return id end
    if not pet then
        id = T.TableIDs()[name .. "#" .. rank]
        if id then return id end
    end
    local S, level = Spells(), ns.Num(entry.level)
    if pet or not (S and type(S.LevelSpells) == "function" and level) then return nil end
    local ok, ids = pcall(S.LevelSpells, level)
    if not ok or type(ids) ~= "table" then return nil end
    local hits = {}
    for _, candidate in ipairs(ids) do
        if Core.SpellName(candidate) == name then hits[#hits + 1] = candidate end
    end
    if #hits == 1 then return hits[1] end
    for _, candidate in ipairs(hits) do
        local okRank, r = pcall(S.Rank, candidate)
        if okRank and ns.Num(r) == rank then return candidate end
    end
    return nil
end

-- Anklickbarer Zauber-Link vom Client oder nil (keine Schnittstelle, gesperrt, kein Link).
function T.SpellLink(id)
    id = ns.Num(id)
    if not id then return nil end
    local api = rawget(_G, "C_Spell")
    local fns = { type(api) == "table" and api.GetSpellLink or nil, rawget(_G, "GetSpellLink") }
    for i = 1, 2 do
        local fn = fns[i]
        if type(fn) == "function" then
            local ok, link = pcall(fn, id)
            if ok and not ns.IsSecret(link) and type(link) == "string" and link:find("|Hspell:", 1, true) then
                return link
            end
        end
    end
    return nil
end

-- Ein Eintrag als Text: „[Feuerball] (Rang 3, 1 s 20 k)“ – Link, wo der Client einen liefert (nicht mit
-- opts.plain), sonst der Name; Rang, wenn der Link ihn nicht schon nennt; Einzelpreis mit opts.cost (über 0).
function T.SpellLabel(entry, offers, opts)
    opts = opts or {}
    if type(entry) ~= "table" then return nil end
    local id = T.SpellID(entry, offers, opts.pet)
    local text = (not opts.plain and id) and T.SpellLink(id) or nil
    local rank = ns.Num(entry.rank) or 0
    if text and rank > 0 then
        local S = Spells()
        local shown = S and type(S.ParseRank) == "function" and S.ParseRank(text)
        if shown == rank then rank = 0 end              -- der Link nennt den Rang schon
    end
    if not text then
        text = Core.Plain(entry.name)
        if (type(text) ~= "string" or text == "") and id then text = Core.SpellName(id) end
        if type(text) ~= "string" or text == "" then return nil end
    end
    local cost = opts.cost and ns.Num(entry.cost) or nil
    if cost and cost > 0 then
        if rank > 0 then return L.SPELL_RANK_COST:format(text, rank, ns.Money(cost)) end
        return L.SPELL_COST:format(text, ns.Money(cost))
    end
    if rank > 0 then return L.SPELL_RANK:format(text, rank) end
    return text
end

-- Liste als Text: höchstens T.MAX_NAMES Einträge, danach „und n weitere“ (ezCore.More(n, true); mit opts.more = true
-- „… und n weitere“, ein Text in opts.more als Format); nil, wenn keiner einen Namen hat. opts: cost, plain, pet (siehe
-- oben), kind (Lehrer-Art für ezCores Angebot), sep (Trenner, Standard ", "; mit "\n" steht „weitere“ in einer eigenen Zeile).
function T.SpellList(list, opts)
    opts = opts or {}
    if type(list) ~= "table" or #list == 0 then return nil end
    local offers = T.OfferIDs(opts.kind)
    local shown, max = {}, opts.max or T.MAX_NAMES
    for _, entry in ipairs(list) do
        if #shown >= max then break end
        local text = T.SpellLabel(entry, offers, opts)
        if text then shown[#shown + 1] = text end
    end
    if #shown == 0 then return nil end
    local sep = opts.sep or ", "
    local text = table.concat(shown, sep)
    local rest = #list - #shown
    if rest > 0 then
        local more = type(opts.more) == "string" and opts.more:format(rest) or ezCore.More(rest, not opts.more)
        text = text .. (sep == "\n" and "\n" or " ") .. more
    end
    return text
end

-- Wie T.SpellList, aber nur mit der Einstellung spellNames und ohne Fehler nach außen (die Meldung kommt dann wie
-- bisher nur mit Anzahl und Summe).
function T.Names(list, opts)
    if not ns.Enabled("spellNames") then return nil end
    local ok, text = pcall(T.SpellList, list, opts)
    if not ok then
        ns.Error(text, "SpellList")
        return nil
    end
    return text
end

-- Kopie, neueste Stufe zuerst (dann Name, höherer Rang zuerst) – die Zauber dieser Stufe stehen vorn.
function T.Newest(list)
    local copy = {}
    for i, entry in ipairs(type(list) == "table" and list or {}) do copy[i] = entry end
    table.sort(copy, function(a, b)
        local la, lb = ns.Num(a.level) or 0, ns.Num(b.level) or 0
        if la ~= lb then return la > lb end
        if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
        return (ns.Num(a.rank) or 0) > (ns.Num(b.rank) or 0)
    end)
    return copy
end

-- Was jetzt beim Lehrer wartet, als Liste für die Meldung, neueste zuerst: mit Lehrerbesuch die Liste aus
-- Core.Spells.Waiting, sonst die „kommt später“-Zauber bis zur Stufe aus Core.Spells.BookEntries (Zauberbuch und
-- Stufen laut Client – dieselben, die Waiting dann zählt; Welle 23, A44). Zweiter Wert: true mit Lehrerbesuch
-- (Preise bekannt).
function T.WaitingList(level)
    local _, cost, source, list = T.Waiting(level)
    if source == "trainer" and type(list) == "table" then return T.Newest(list), cost ~= nil end
    if source ~= "book" then return {}, false end
    local S = Spells()
    level = ns.Num(level) or Core.PlayerLevel() or 1
    local out = {}
    local ok, future = pcall(S.BookEntries)
    for _, entry in ipairs(ok and type(future) == "table" and future or {}) do
        if type(entry) == "table" and (ns.Num(entry.level) or 0) <= level then out[#out + 1] = entry end
    end
    return T.Newest(out), false
end

-- Die Meldung beim Stufenaufstieg (neue Ränge, Dungeons, jetzt tragbare Teile) steht in LevelUp.lua.

-- Den Tooltip der Einstellung „Knopf „Alles lernen““ mit dem Addon, das es gerade übernimmt, baut ezCore
-- (page:Checkbox mit feature = "trainAll", Options.lua; Welle 23 A42); der Status liest immer frisch.
ns.AddStatusLine(function()
    local other = T.Other()
    return other and L.LEARN_OTHER:format(other) or nil
end)

ns.AddStatusLine(function()
    local S = Spells()
    if not (S and S.TrainerSeen) then return nil end
    local seen = S.TrainerSeen()
    if not seen then return L.STATUS_TRAINER_NONE end
    local count, total = T.Waiting()
    return L.STATUS_TRAINER:format(Core.Ago(seen), count or 0, ns.Money(total or 0))
end)

-- Begleiter (MER-08): wann sein Ausbilder zuletzt gelesen wurde und was jetzt dort für ihn wartet; nur bei Klassen
-- mit Begleiter (Core.Spells.PetKind).
ns.AddStatusLine(function()
    local S = Spells()
    if not (S and S.PetKind and S.TrainerSeen and S.Waiting) then return nil end
    local kind = S.PetKind()
    if not kind then return nil end
    local seen = S.TrainerSeen(kind)
    if not seen then return L.STATUS_PET_TRAINER_NONE end
    -- ohne gerufenen Begleiter zählt die Ansicht nichts als „jetzt“ (Spellbook.lua, U.PetPresent) – hier ebenso
    local U = ns.Upcoming
    if U and U.PetPresent and not U.PetPresent() then return L.STATUS_PET_TRAINER_NOPET:format(Core.Ago(seen)) end
    local count, total = S.Waiting(nil, kind)
    return L.STATUS_PET_TRAINER:format(Core.Ago(seen), ns.Num(count) or 0, ns.Money(ns.Num(total) or 0))
end)
