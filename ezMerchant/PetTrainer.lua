local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Hinweis beim Tierausbilder des Jägers (Wunsch des Nutzers 13.11.2026: „Begleiter kann X noch nicht“; die Idee
    kennt man aus Tweaks Forever – hier selbst gebaut, nichts übernommen).
      - Ein Textknopf in Blizzards Lehrerfenster, an der Stelle von „Alles lernen“ (das es beim Tierausbilder nicht
        gibt): „Begleiter: 2 Ränge fehlen“. Der Tooltip nennt jeden Rang und was zu tun ist.
      - Ränge, die der Begleiter schon kann, werden in Blizzards Liste abgedunkelt.
    Quelle (Leitlinie „Datenquellen“: zuerst der Client, jede Angabe nennt ihre Quelle): Blizzards Lehrerliste
    (GetTrainerServiceInfo) und das Zauberbuch des Begleiters. Dort stehen nur seine aktiven Fähigkeiten mit ihrem
    Rang; passive und solche, die er noch gar nicht kann, fehlen – dazu sagt ezMerchant nichts, statt zu raten.
    Blizzards Lehrerfilter wird nur gelesen, nie umgeschaltet: zeigt die Liste schon Gelerntes nicht, sagt es der
    Tooltip.
    Taint-sicher: eigener Rahmen als Kind von ClassTrainerFrame, hooksecurefunc auf Blizzards Zeilen-Funktion,
    an Blizzards Zeilen nur SetAlpha (und nur beim Tierausbilder; danach wieder 1).

    Knopf „Wildtierausbildung“ (Welle 2b): ein sicherer Knopf über Core.SecureButton oben links im Lehrerfenster
    (dort, wo beim Berufslehrer der Fortschrittsbalken steht – beim Tierausbilder ist der Platz frei). Ein Klick
    wirkt den Zauber und öffnet damit Blizzards Fenster der Wildtierausbildung; ezMerchant lernt und bringt nichts
    selbst bei und schaltet Blizzards Lehrerfilter nicht um. Nur außerhalb des Kampfes: Der Knopf ist ein Kind von
    UIParent (ein geschütztes Kind würde Blizzards Lehrerfenster im Kampf sperren), wird nur außerhalb des Kampfes
    an das Lehrerfenster gehängt und gezeigt und beim Kampfbeginn (PLAYER_REGEN_DISABLED, die Sperre greift erst
    danach) ausgeblendet und wieder vom Lehrerfenster gelöst; nach dem Kampf kommt er wieder.
    Zauber-ID 5149 („Wildtierausbildung“ / „Beast Training“): Blizzards Zauber-ID im klassischen Datenstand,
    Quelle ist der Client (Name, Symbol und „gelernt“ fragt ezMerchant über Core.Spells zur Laufzeit ab; im Spiel
    prüfen: /dump C_Spell.GetSpellName(5149)). ezCore führt die ID noch nicht in SpellData.lua; steht sie dort
    einmal als Spells.BEAST_TRAINING, gilt die von ezCore.
]]

local P = {}
ns.PetTrainer = P

local DIM_ALPHA = 0.45
P.DIM_ALPHA = DIM_ALPHA

local function Spells() return Core.Spells end

-- Zeigt schon ein anderes Addon diesen Hinweis? Dann dessen Name (Liste in ezCore, OtherAddOns.lua), sonst nil.
function P.Other()
    return (ns.OtherFor("petTrainerHint"))
end

-- Hinweis an? Einstellung, Tierausbilder offen, kein anderes Addon.
function P.Active()
    if not ns.Enabled("petHint") or P.Other() then return false end
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then return false end
    return ns.Trainer.PetTrainer() == true
end

---------------------------------------------------------------------------
-- Was kann der Begleiter? (sein Zauberbuch)
---------------------------------------------------------------------------

local function PetBookEntry(index)
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    local ok, name, sub
    if bank ~= nil and C_SpellBook and C_SpellBook.GetSpellBookItemName then
        ok, name, sub = pcall(C_SpellBook.GetSpellBookItemName, index, bank)
    elseif GetSpellBookItemName then
        ok, name, sub = pcall(GetSpellBookItemName, index, "pet")
    end
    if not ok then return nil end
    return Core.Plain(name), Core.Plain(sub)
end

-- Anzahl der Einträge im Zauberbuch des Begleiters. Wie beim Namen zuerst der Retail-Weg (C_SpellBook.HasPetSpells),
-- sonst das alte Global; fehlt beides oder ist die Zahl nicht lesbar: 0.
function P.PetSpellCount()
    local count = C_SpellBook and C_SpellBook.HasPetSpells or HasPetSpells
    if type(count) ~= "function" then return 0 end
    local ok, n = pcall(count)
    return ok and ns.Num(n) or 0
end

-- { [Name] = Rang } der aktiven Fähigkeiten des Begleiters; Rang 0 = ohne Rang, false = Rang (noch) nicht lesbar.
-- nil: kein Begleiter gerufen. Leere Tabelle: Begleiter da, aber sein Zauberbuch ist nicht lesbar (oder leer) –
-- dann gibt es keine Aussage (P.Scan().unreadable), nicht „nichts fehlt“.
function P.PetSpells()
    if Core.UnitPresent("pet") ~= true then return nil end   -- gesperrt oder unbekannt: kein Begleiter (V-184)
    local known = {}
    local count = P.PetSpellCount()
    local parse = Spells() and Spells().ParseRank
    for index = 1, count do
        local name, sub = PetBookEntry(index)
        if type(name) == "string" and name ~= "" then
            local rank
            if sub == nil then
                rank = false                        -- Zusatz gesperrt oder noch nicht geladen
            elseif sub == "" then
                rank = 0
            else
                rank = parse and parse(sub) or 0
            end
            local old = known[name]
            if old == nil or (rank and (not old or rank > old)) then known[name] = rank end
        end
    end
    return known
end

---------------------------------------------------------------------------
-- Lehrerliste gegen das Zauberbuch des Begleiters
---------------------------------------------------------------------------

-- Stand einer Zeile:
--   "nopet"    kein Begleiter gerufen
--   "absent"   steht nicht im Zauberbuch des Begleiters (passiv, nie beigebracht oder nichts für seine Tierart)
--   "unknown"  Rang nicht lesbar – keine Aussage
--   "known"    der Begleiter kann diesen Rang (oder einen höheren)
--   "missing"  der Begleiter kann die Fähigkeit, aber nur einen niedrigeren Rang → zweiter Wert: sein Rang
function P.State(name, rank, pet)
    if pet == nil then return "nopet" end
    local has = pet[name]
    if has == nil then return "absent" end
    if has == false then return "unknown" end
    rank = rank or 0
    if rank == 0 and has > 0 then return "unknown" end
    -- Das Zauberbuch nennt die Fähigkeit ohne Rang, der Lehrer mit: Rang nicht lesbar, nicht „Rang 0“ (sonst
    -- fehlte scheinbar jeder Rang, den der Lehrer führt).
    if has == 0 and rank > 0 then return "unknown" end
    if rank <= has then return "known" end
    return "missing", has
end

-- Zeile index der offenen Lehrerliste: Name, Rang, Art ("available" | "unavailable" | "used" | "header").
function P.Service(index)
    if not GetTrainerServiceInfo then return nil end
    local name, kind, _, _, sub = GetTrainerServiceInfo(index)
    name, kind = Core.Plain(name), Core.Plain(kind)
    if type(name) ~= "string" or name == "" or kind == "header" then return nil end
    local parse = Spells() and Spells().ParseRank
    return name, parse and parse(sub) or 0, kind
end

-- Zeigt Blizzards Liste auch schon Gelerntes? true/false, nil = nicht lesbar. Nur lesen – nie umschalten.
function P.ShowsLearned()
    if not GetTrainerServiceTypeFilter then return nil end
    local ok, shown = pcall(GetTrainerServiceTypeFilter, "used")
    if not ok or ns.IsSecret(shown) then return nil end
    return shown == true or shown == 1
end

-- Auswertung der offenen Liste:
-- { pet = true|false, unreadable = true|false, missing = { { name, rank, has, kind } … }, known = Anzahl,
--   absent = Anzahl, unknown = Anzahl, norank = true|false, learned = true|false|nil }
-- unreadable: Begleiter da, aber kein Eintrag seines Zauberbuchs lesbar – keine Aussage möglich.
-- unknown: Zeilen, deren Rang das Zauberbuch nicht verrät. norank: nichts fehlt, nichts ist bekannt, aber es gibt
-- solche Zeilen – das Zauberbuch nennt keinen Rang, also keine Aussage statt „nichts fehlt“.
-- missing: höchster fehlender Rang je Fähigkeit, den die Liste zeigt und der jetzt etwas nützt
-- (kind "used": du kannst ihn schon – beibringen; "available": hier lernbar). Später lernbare zählen nicht.
function P.Scan()
    local pet = P.PetSpells()
    local result = { pet = pet ~= nil, unreadable = false, missing = {}, known = 0, absent = 0, unknown = 0,
        norank = false, learned = P.ShowsLearned() }
    if not pet then return result end
    if next(pet) == nil then
        result.unreadable = true
        return result
    end
    local best = {}
    for index = 1, (GetNumTrainerServices and ns.Num(GetNumTrainerServices())) or 0 do
        local name, rank, kind = P.Service(index)
        if name then
            local state, has = P.State(name, rank, pet)
            if state == "known" then
                result.known = result.known + 1
            elseif state == "absent" then
                result.absent = result.absent + 1
            elseif state == "unknown" then
                result.unknown = result.unknown + 1
            elseif state == "missing" and (kind == "used" or kind == "available") then
                local entry = best[name]
                if not entry then
                    entry = { name = name, rank = rank, has = has, kind = kind }
                    best[name] = entry
                    result.missing[#result.missing + 1] = entry
                elseif rank > entry.rank then
                    entry.rank, entry.kind = rank, kind
                end
            end
        end
    end
    table.sort(result.missing, function(a, b) return a.name < b.name end)
    result.norank = #result.missing == 0 and result.known == 0 and result.unknown > 0
    return result
end

-- Text auf dem Hinweis.
function P.Text(scan)
    if not scan.pet then return L.PET_HINT_NOPET end
    if scan.unreadable or scan.norank then return L.PET_HINT_UNKNOWN end
    local n = #scan.missing
    if n == 0 then return L.PET_HINT_OK end
    return (n == 1 and L.PET_HINT_ONE or L.PET_HINT_MANY):format(n)
end

-- Zeilen des Tooltips: { text, rolle } – was fehlt, was zu tun ist, woher die Angabe stammt. Die Rolle (Core.TipLine:
-- "highlight", "normal", "hint") statt Farbzahlen (Gesamtreview 18.11.2026, T9-6); ohne Rolle gold wie vorher.
function P.TipLines(scan)
    local lines = {}
    local function Add(text, role) lines[#lines + 1] = { text, role or "normal" } end
    if not scan.pet then
        Add(L.PET_TIP_NOPET, "highlight")
    elseif scan.unreadable then
        Add(L.PET_TIP_UNKNOWN, "highlight")
    else
        local teach, learn = 0, 0
        for _, entry in ipairs(scan.missing) do
            Add(L.PET_TIP_MISSING:format(entry.name, entry.rank, entry.has), "highlight")
            if entry.kind == "used" then teach = teach + 1 else learn = learn + 1 end
        end
        if teach > 0 then Add(L.PET_TIP_TEACH) end
        if learn > 0 then Add(L.PET_TIP_LEARN) end
        if (teach > 0 or learn > 0) and P.TrainShown() then Add(L.PET_TIP_BUTTON:format((P.TrainName()))) end
        if scan.norank then
            Add(L.PET_TIP_NORANK, "highlight")
        elseif #scan.missing == 0 then
            Add(L.PET_TIP_OK, "highlight")
        end
        if scan.known > 0 then Add(L.PET_TIP_DIMMED:format(scan.known), "hint") end
        if (scan.unknown or 0) > 0 then Add(L.PET_TIP_UNREAD:format(scan.unknown), "hint") end
        if scan.absent > 0 then Add(L.PET_TIP_ABSENT:format(scan.absent), "hint") end
        if scan.learned == false then Add(L.PET_TIP_FILTER, "hint") end
    end
    Add(L.PET_TIP_SOURCE, "hint")
    return lines
end

---------------------------------------------------------------------------
-- Hinweis im Lehrerfenster
---------------------------------------------------------------------------

local hint

local function ShowTooltip(self)
    local scan = P.Scan()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    Core.TipTitle(GameTooltip, L.PET_HINT_TITLE)
    for _, line in ipairs(P.TipLines(scan)) do
        Core.TipLine(GameTooltip, line[1], line[2], true)
    end
    GameTooltip:Show()
end

local function CreateHint()
    if hint or not ClassTrainerFrame then return end
    hint = CreateFrame("Button", "ezMerchantPetHint", ClassTrainerFrame)
    hint:SetHeight(22)
    -- an der Stelle von „Alles lernen“ (beim Tierausbilder versteckt): links neben Blizzards „Lernen“
    local train = _G.ClassTrainerTrainButton
    if train then
        hint:SetPoint("RIGHT", train, "LEFT", -4, 0)
    else
        hint:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -84, 4)
    end
    hint.text = hint:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hint.text:SetPoint("RIGHT", hint, "RIGHT", 0, 0)
    hint:SetScript("OnEnter", ShowTooltip)
    hint:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hint:Hide()
    P.hint = hint
end

---------------------------------------------------------------------------
-- Bekannte Ränge in Blizzards Liste abdunkeln
---------------------------------------------------------------------------

local rows = setmetatable({}, { __mode = "k" })     -- Blizzards Zeile → Index in der Lehrerliste
local dimmed = setmetatable({}, { __mode = "k" })   -- Zeilen, die ezMerchant abgedunkelt hat
P.rows, P.dimmed = rows, dimmed

local function DimRow(row, index, pet)
    local dim = false
    if pet and index then
        local name, rank = P.Service(index)
        dim = name ~= nil and P.State(name, rank, pet) == "known"
    end
    if dim then
        dimmed[row] = true
        row:SetAlpha(DIM_ALPHA)
    elseif dimmed[row] then
        dimmed[row] = nil
        row:SetAlpha(1)
    end
    return dim
end

-- Blizzard füllt eine Zeile (hooksecurefunc): merken, welche Zeile welchen Index zeigt, und abdunkeln.
function P.OnRow(row, index)
    if type(row) ~= "table" or not row.SetAlpha then return end
    index = ns.Num(index)
    rows[row] = index
    DimRow(row, index, P.Active() and P.PetSpells() or nil)
end

-- Alle gemerkten Zeilen neu bewerten (Begleiter gerufen, Rang beigebracht, anderer Lehrer). → Anzahl abgedunkelt
function P.RefreshRows()
    local pet = P.Active() and P.PetSpells() or nil
    local count = 0
    for row, index in pairs(rows) do
        if DimRow(row, index, pet) then count = count + 1 end
    end
    return count
end

-- Kann ezMerchant Blizzards Zeilen abdunkeln? (Die Funktion, an die es sich hängt, gibt es nicht in jeder Fassung.)
P.ROW_HOOK = "ClassTrainerFrame_SetServiceButton"
function P.CanDim() return P.hooked == true end

---------------------------------------------------------------------------
-- Knopf „Wildtierausbildung“ (sicherer Knopf über Core.SecureButton; nur außerhalb des Kampfes)
---------------------------------------------------------------------------

local BEAST_TRAINING = 5149                 -- Quelle und Prüfung: Dateikopf
P.TRAIN_BUTTON = "ezMerchantBeastTraining"
-- Lage oben links (wie Blizzards ClassTrainerStatusBar: x 64, y −35, 18 hoch – der Knopf ist 22 hoch, daher −33),
-- Breite aus dem Text, höchstens bis vor Blizzards Filter oben rechts.
local TOP = { x = 64, y = -33, height = 22, pad = 24, gap = 8, min = 60 }
P.TRAIN_TOP = TOP
-- Ebene (Design-System 2.6, Regel „parent“; Welle 22): Der Knopf kann kein Kind des Lehrerfensters sein (ein
-- geschütztes Kind sperrte es im Kampf, Dateikopf), also übernimmt er dessen Ebene und liegt eine Rahmenstufe über
-- allem, was im Lehrerfenster liegt (P.TrainLevel). Bis Welle 22 kam er eine ganze Ebene höher (MEDIUM → HIGH, über
-- jedem anderen Fenster). Gezählt werden die Kinder bis LEVEL_WALK.depth Stufen tief, höchstens LEVEL_WALK.max Rahmen
-- (Blizzard_TrainerUI.xml: Statusbalken, Filter und Knöpfe sind direkte Kinder; die Liste liegt ohnehin weiter unten).
local LEVEL_WALK = { depth = 3, max = 200, top = 10000 }
P.LEVEL_WALK = LEVEL_WALK

local train                                 -- Griff von Core.SecureButton (erst beim ersten Bedarf angelegt)
local trainDocked = false                   -- hängt der Knopf gerade am Lehrerfenster?

-- Zauber-ID der Wildtierausbildung: die von ezCore, sobald SpellData.lua sie führt, sonst die aus dem Dateikopf.
function P.TrainSpell()
    local S = Spells()
    return S and tonumber(S.BEAST_TRAINING) or BEAST_TRAINING
end

-- Name des Zaubers in der Sprache des Clients; zweiter Wert true, wenn der Name vom Client stammt.
function P.TrainName()
    local S = Spells()
    local name, fromClient
    if S and S.Name then name, fromClient = S.Name(P.TrainSpell()) end
    if type(name) ~= "string" or name == "" then return L.PET_TRAIN, false end
    return name, fromClient == true
end

-- Kennt der Spieler den Zauber? (Core.Spells.IsKnown: Zauberbuch des Clients)
function P.TrainKnown()
    local S = Spells()
    return S ~= nil and S.IsKnown ~= nil and S.IsKnown(P.TrainSpell()) == true
end

-- Was der Knopf wirkt: der Name aus dem Client (findet auch einen Rang mit anderer ID), sonst die ID.
function P.TrainAction()
    local name, fromClient = P.TrainName()
    if fromClient then return { type = "spell", spell = name } end
    return { type = "spell", spell = P.TrainSpell() }
end

-- Soll der Knopf jetzt zu sehen sein? Einstellung an, kein anderes Addon zeigt den Hinweis (ns.OtherFor),
-- nicht im Kampf (Core.SecureButton verlangt das Modul über opts.needs), Tierausbilder offen, Begleiter gerufen, Zauber gelernt.
function P.TrainWanted()
    if not ns.Enabled("petTrain") or P.Other() then return false end
    if ns.InCombat() then return false end
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) or ns.Trainer.PetTrainer() ~= true then return false end
    if Core.UnitPresent("pet") ~= true then return false end
    return P.TrainKnown()
end

function P.TrainShown() return train ~= nil and train:Shown() end

-- Breite: Text plus Rand, höchstens bis vor Blizzards Filter (beides erst bekannt, wenn das Fenster offen ist).
function P.TrainWidth(frame)
    local label = frame.GetFontString and frame:GetFontString()
    local text = label and label.GetStringWidth and ns.Num(label:GetStringWidth()) or 0
    local width = math.max(TOP.min, math.floor(text + TOP.pad))
    local drop = ClassTrainerFrame and ClassTrainerFrame.FilterDropdown
    if type(drop) ~= "table" then drop = nil end
    local left = ClassTrainerFrame and ClassTrainerFrame.GetLeft and ns.Num(ClassTrainerFrame:GetLeft())
    local right = drop and drop.GetLeft and ns.Num(drop:GetLeft())
    if left and right then width = math.min(width, math.max(TOP.min, math.floor(right - left - TOP.x - TOP.gap))) end
    return width
end

-- Andocken (läuft über knopf:Anchor, also nur außerhalb des Kampfes): oben links ins Lehrerfenster. Zeigt Blizzard
-- dort doch einen Fortschrittsbalken, links neben den Hinweis bzw. „Lernen“.
function P.TrainPlace(frame)
    frame:ClearAllPoints()
    local status = _G.ClassTrainerStatusBar
    if status and status.IsShown and status:IsShown() then
        local beside = (hint and hint:IsShown() and hint) or _G.ClassTrainerTrainButton
        frame:SetPoint("RIGHT", beside, "LEFT", -4, 0)
    else
        frame:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPLEFT", TOP.x, TOP.y)
    end
    frame:SetHeight(TOP.height)
    frame:SetWidth(P.TrainWidth(frame))
    P.TrainLayer(frame)
end

-- Höchste Rahmenstufe im Lehrerfenster (es selbst und seine Kinder, siehe LEVEL_WALK) plus eins. Gesperrte Werte und
-- Fehler zählen nicht (Leitlinie 6); ohne Lehrerfenster 1.
function P.TrainLevel(host)
    local top, seen = 0, 0
    local function Walk(f, depth)
        if seen >= LEVEL_WALK.max or type(f) ~= "table" or type(f.GetFrameLevel) ~= "function" then return end
        seen = seen + 1
        local ok, level = pcall(f.GetFrameLevel, f)
        level = ok and Core.Plain(level) or nil
        if type(level) == "number" and level > top then top = level end
        if depth < LEVEL_WALK.depth and type(f.GetChildren) == "function" then
            local okChildren, children = pcall(function() return { f:GetChildren() } end)
            if okChildren then
                for _, child in ipairs(children) do Walk(child, depth + 1) end
            end
        end
    end
    Walk(host, 0)
    return math.min(top + 1, LEVEL_WALK.top)
end

-- Ebene des Lehrerfensters übernehmen (gesperrt oder unbekannt: Ebene „hud“ wie Blizzards Fenster) und darüber
-- liegen. Nur über knopf:Anchor, also außerhalb des Kampfes.
function P.TrainLayer(frame)
    local host = ClassTrainerFrame
    local strata = host and host.GetFrameStrata and Core.Plain(host:GetFrameStrata())
    if type(strata) ~= "string" or strata == "" or not (frame.SetFrameStrata and pcall(frame.SetFrameStrata, frame, strata)) then
        Core.Style.SetStrata(frame, "hud")
    end
    if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, P.TrainLevel(host)) end
    P.trainHostLevel = P.HostLevel()
end

-- Rahmenstufe des Lehrerfensters selbst (gesperrt, Fehler oder ohne Fenster: nil, Leitlinie 6).
function P.HostLevel()
    local host = ClassTrainerFrame
    if not (host and type(host.GetFrameLevel) == "function") then return nil end
    local ok, level = pcall(host.GetFrameLevel, host)
    level = ok and Core.Plain(level) or nil
    return type(level) == "number" and level or nil
end

-- Blizzards Lehrerfenster ist „toplevel“ (Forever-Quelle, Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.xml): ein
-- Klick hinein hebt es über alle Rahmen seiner Ebene, der Knopf (Kind von UIParent) wandert nicht mit. Nach jedem
-- Mausklick (GLOBAL_MOUSE_UP) prüfen, ob sich die Stufe des Fensters geändert hat, und den Knopf wieder darüber legen –
-- nur außerhalb des Kampfes und über knopf:Anchor. → true, wenn neu gelegt
function P.TrainRaised()
    if not (train and trainDocked and train:Shown()) or ns.InCombat() then return false end
    local level = P.HostLevel()
    if level == nil or level == P.trainHostLevel then return false end
    train:Anchor(P.TrainPlace)
    return true
end

-- Lösen: an UIParent statt am Lehrerfenster (Blizzard soll sein Fenster im Kampf frei verschieben und schließen).
function P.TrainDetach(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function TrainTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    Core.TipTitle(GameTooltip, (P.TrainName()))
    Core.TipText(GameTooltip, L.PET_TRAIN_TIP)
    Core.TipLine(GameTooltip, L.PET_TRAIN_SOURCE, "hint", true)
    GameTooltip:Show()
end

-- Einmal nach dem Anlegen (außerhalb des Kampfes): Text und Tooltip – alles Ungeschützte baut das Modul selbst.
local function TrainCreated(frame)
    if frame.SetText then frame:SetText((P.TrainName())) end
    frame:HookScript("OnEnter", TrainTooltip)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Ausblenden und vom Lehrerfenster lösen (sofort außerhalb des Kampfes, im Kampf merkt es sich der Dienst).
function P.TrainRelease()
    if not train or not (train:Shown() or trainDocked) then return false end
    train:Hide()
    train:Anchor(P.TrainDetach)
    trainDocked = false
    return true
end

-- Knopf zeigen oder verstecken. → true, wenn er zu sehen sein soll
function P.UpdateTrain()
    if not P.TrainWanted() then
        P.TrainRelease()
        return false
    end
    if not train then
        local handle, reason = Core.SecureButton(P.TRAIN_BUTTON, { owner = ADDON, template = "UIPanelButtonTemplate",
            onCreate = TrainCreated })
        if not handle then
            P.trainFailed = reason
            return false
        end
        train, P.train, P.trainFailed = handle, handle, nil
    end
    local frame = train:Frame()
    if frame and frame.SetText then frame:SetText((P.TrainName())) end
    train:SetAction(P.TrainAction())
    train:Anchor(P.TrainPlace)
    train:Show()
    trainDocked = true
    return true
end

-- Kampfbeginn: Die Sperre greift erst nach PLAYER_REGEN_DISABLED – jetzt noch ausblenden und lösen.
function P.TrainCombat() return P.TrainRelease() end

---------------------------------------------------------------------------
-- Auffrischen
---------------------------------------------------------------------------

function P.Update()
    if not hint then return end
    local active = P.Active()
    P.RefreshRows()
    hint:SetShown(active)
    if active then
        hint.text:SetText(P.Text(P.Scan()))
        local width = hint.text.GetStringWidth and ns.Num(hint.text:GetStringWidth()) or 0
        hint:SetWidth(math.max(40, width + 4))
    end
    ns.Try("PetTrain", P.UpdateTrain)
end

local UpdateSoon = ns.Throttle(function() P.Update() end, 0.1)

local function WhenTrainerOpen()
    if ClassTrainerFrame and ClassTrainerFrame:IsShown() then UpdateSoon() end
end

ns.On("TRAINER_SHOW", function() UpdateSoon() end)
ns.On("TRAINER_UPDATE", function() UpdateSoon() end)
-- Nur für den Spieler (ns.OnUnit: Blizzard weckt den Zuhörer nur für ihn, V-042). Eine gesperrte Einheit stellt
-- ezCore trotzdem zu – sie zählt als der Spieler und wird nie verglichen (Leitlinie 6). Ein UNIT_PET ohne Einheit
-- kommt hinter ns.OnUnit nicht an (die Fassung über ns.On nahm es noch an); der Client nennt immer eine, und
-- PET_BAR_UPDATE und SPELLS_CHANGED frischen denselben Hinweis auf.
ns.OnUnit("UNIT_PET", "player", function(_, unit)
    if ns.IsSecret(unit) or unit == "player" then WhenTrainerOpen() end
end)
ns.On("PET_BAR_UPDATE", WhenTrainerOpen)
ns.On("SPELLS_CHANGED", WhenTrainerOpen)
-- Knopf „Wildtierausbildung“: beim Kampfbeginn weg (sofort, die Sperre greift erst danach), nach dem Kampf wieder.
ns.On("PLAYER_REGEN_DISABLED", function() ns.Try("PetTrainCombat", P.TrainCombat) end)
ns.On("PLAYER_REGEN_ENABLED", WhenTrainerOpen)
-- Klick ins Lehrerfenster hebt es an (toplevel): den Knopf wieder darüber legen (P.TrainRaised).
ns.On("GLOBAL_MOUSE_UP", function() ns.Try("PetTrainRaise", P.TrainRaised) end)

ns.OnSettingChanged(function(key)
    if key == "petHint" or key == "petTrain" then P.Update() end
end)

-- Selbsttest (/ez test): kennt dieser Client die Zauber-ID der Wildtierausbildung? (optional – ohne sie fehlt nur
-- der Knopf)
function P.SelfTest()
    local S, id = Spells(), P.TrainSpell()
    local there = S ~= nil and S.Exists ~= nil and S.Exists(id) == true
    return { { kind = "spell", name = id .. " (" .. L.PET_TRAIN .. ")", there = there, optional = true } }
end
Core.AddSelfTest(ADDON, P.SelfTest)   -- Core.AddSelfTest verlangt das Modul über opts.needs

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_TrainerUI", function()
        CreateHint()
        if not hint then return end
        ClassTrainerFrame:HookScript("OnShow", function() UpdateSoon() end)
        ClassTrainerFrame:HookScript("OnHide", function() P.Update() end)
        if not P.hooked and type(_G[P.ROW_HOOK]) == "function" then
            hooksecurefunc(P.ROW_HOOK, function(row, index) ns.Try("PetRow", P.OnRow, row, index) end)
            P.hooked = true
        end
        P.Update()
    end)
end)

ns.AddStatusLine(function()
    local other = P.Other()
    if other then return L.PET_STATUS_OTHER:format(other) end
    if not ns.Enabled("petHint") then return nil end
    if ClassTrainerFrame and not P.CanDim() then return L.PET_STATUS_NO_DIM end
    return nil
end)

-- Status des Knopfs „Wildtierausbildung“ (nur für Jäger mit dem Zauber und eingeschaltetem Knopf).
function P.TrainStatus()
    if not ns.Enabled("petTrain") or P.Other() or not P.TrainKnown() then return nil end
    -- die Fehlerliste unter ezCores geltendem Befehl (/ez nur, wenn frei – Gesamtreview 18.11.2026, T18-2)
    if P.trainFailed then
        return L.PET_STATUS_TRAIN_FAILED:format(tostring(P.trainFailed), Core.SlashCmd(nil, L.PET_ERRORS_WORD))
    end
    if train and train:Pending() then return L.PET_STATUS_TRAIN_WAITING end
    return nil
end
ns.AddStatusLine(function() return P.TrainStatus() end)
