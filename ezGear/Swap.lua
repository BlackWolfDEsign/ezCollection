local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Automatisch umziehen – mit Blizzards eigenen Ausrüstungssets:
      * Reiten: beim Aufsteigen das Set „Reiten“ anlegen (z. B. Karotte am Stiel), beim Absteigen zurück
      * Angeln: beim Auswerfen das Set „Angeln“ (Angelhut, Handschuhe …), nach einer Weile ohne Angeln zurück;
        scheitert der Wurf (die Angel liegt noch im Set), kommt das Set ebenfalls – der nächste Wurf klappt;
        der Knopf „Angelausrüstung an/aus“ im Menü „Sets“ schaltet von Hand (dann ohne Zeitgrenze)
    Welches Set, wählt jeder Charakter im Menü „Sets“ am Charakterfenster; ohne Wahl gilt ein Set mit passendem Namen
    („Reiten“/„Riding“/„Mount“, „Angeln“/„Fishing“). Zurück heißt: nur die Plätze, die das Set geändert hat, und nur,
    solange dort noch das Set-Teil steckt (von Hand Getauschtes bleibt). Der Stand übersteht /reload
    (ezGearDB.chars[charKey].swap). Ausrüsten ist im Kampf gesperrt: dann gleich nach dem Kampf.
]]

local Swap = {}
ns.Swap = Swap

local api = C_EquipmentSet
local lastFishCast = 0
local fishingName
local FISH_KEY = ADDON .. ":fish"    -- der vorgemerkte Angel-Auftrag in ezCores Reihe (ns.AfterCombat(fn, "fish"))

Swap.AUTO_NAMES = {
    mount = { "reiten", "riding", "mount", "reittier" },
    fish = { "angeln", "fishing" },
}

-- Laufzeit der Sitzung (Fristen, nie gespeichert): Core.Uptime, eine Stelle für alle Module (W-14).
local Now = Core.Uptime
-- Zauber „Angeln“ aus ezCore (Spells.FISHING, in needs geprüft; MACRO-18/GEAR-07) – keine eigene Zahl mehr.
local function FishingSpell() return Core.Spells and Core.Spells.FISHING end

local function State() return ns.Char().swap end

-- Gewähltes Set eines Anlasses („mount“, „fish“) → Name oder nil
function Swap.SetName(kind)
    local explicit = ns.Char()[kind .. "Set"]
    if explicit == "" then return nil end
    if type(explicit) == "string" and ns.Sets.IDByName(explicit) then return explicit end
    for _, set in ipairs(ns.Sets.List()) do
        local lower = set.name:lower()
        for _, wanted in ipairs(Swap.AUTO_NAMES[kind] or {}) do
            if lower == wanted then return set.name end
        end
    end
    return nil
end

function Swap.SetChoice(kind, name)
    ns.Char()[kind .. "Set"] = name
end

local function EquipByLink(link, slot)
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    ns.Call(fn, link, slot)
end

-- Set eines Anlasses anlegen und merken, was es ersetzt hat.
function Swap.Wear(kind, manual)
    local name = Swap.SetName(kind)
    local id = name and ns.Sets.IDByName(name)
    if not id or not api then return false end
    if ns.InCombat() then
        ns.AfterCombat(Swap.Evaluate, "swap")
        return false
    end
    local state = State()
    if state and state.kind == kind then return true end
    -- Wechsel von einem Anlass ins andere (Angeln → Reiten, V-114): Das Zurücklegen wirkt erst nach der Antwort des
    -- Servers, im selben Bild stecken noch die Teile des alten Sets. Was vor dem alten Set am Platz war, steht in
    -- dessen gemerktem Stand – der gilt dort als „vorher“, nicht das, was gerade noch zu lesen ist.
    local before = {}
    if state then
        for slot, link in pairs(state.saved or {}) do
            local current = ns.Plain(ns.Call(GetInventoryItemID, "player", slot))
            if current == (state.items or {})[slot] then before[slot] = link end   -- Link oder false (Platz war leer)
        end
        Swap.Restore()
    end
    local items = ns.Sets.Items(id) or {}   -- nur die Plätze, die das Set belegt (ohne ignorierte)
    local saved, setItems = {}, {}
    for slot = 1, 19 do
        local itemID = items[slot]
        if itemID then
            local current = ns.Plain(ns.Call(GetInventoryItemID, "player", slot))
            local previous = before[slot]
            if previous ~= nil then
                current = type(previous) == "string" and tonumber(previous:match("item:(%d+)")) or nil
            end
            if current ~= itemID then
                if previous ~= nil then
                    saved[slot] = previous
                else
                    saved[slot] = ns.Plain(ns.Call(GetInventoryItemLink, "player", slot)) or false
                end
                setItems[slot] = itemID
            end
        end
    end
    if next(setItems) == nil then return true end   -- trägt das Set schon
    ns.Char().swap = { kind = kind, saved = saved, items = setItems, manual = manual or nil }
    ns.Call(api.UseEquipmentSet, id)
    return true
end

-- Zurück zur vorherigen Ausrüstung
function Swap.Restore()
    local state = State()
    if not state then return false end
    if ns.InCombat() then
        ns.AfterCombat(Swap.Evaluate, "swap")
        return false
    end
    for slot, link in pairs(state.saved or {}) do
        local current = ns.Plain(ns.Call(GetInventoryItemID, "player", slot))
        if type(link) == "string" and current == (state.items or {})[slot] then EquipByLink(link, slot) end
    end
    ns.Char().swap = nil
    return true
end

-- Entscheidet nach Lage (Reittier, Angeln, Kampf) – nach jedem passenden Ereignis und nach dem Kampf.
-- Takt alle 15 s (T7-3): Angel-Set ohne eigenen Wechsel nachprüfen.
function Swap.FishTick()
    local state = State()
    if state and state.kind == "fish" and not state.manual then Swap.Evaluate() end
end

function Swap.Evaluate()
    if ns.InCombat() then
        ns.AfterCombat(Swap.Evaluate, "swap")
        return
    end
    local mounted = ns.Plain(ns.Call(IsMounted)) == true
    local state = State()
    if mounted and ns.Active("swapMount") and Swap.SetName("mount") then
        if not state or state.kind ~= "mount" then Swap.Wear("mount") end
        return
    end
    if state and state.kind == "mount" and not mounted then
        Swap.Restore()
        state = nil
    end
    if state and state.kind == "fish" and not state.manual then
        local idle = tonumber(ns.S and ns.S.fishIdle) or 120
        if not ns.Active("swapFishing") or Now() - lastFishCast > idle then Swap.Restore() end
    end
end

function Swap.OnSpellCast(spellID)
    spellID = ns.Plain(spellID)
    if type(spellID) ~= "number" then return end
    fishingName = fishingName or Core.SpellName(FishingSpell())
    local name = Core.SpellName(spellID)
    if not (name and fishingName and name == fishingName) then return end
    lastFishCast = Now()
    if ns.Active("swapFishing") and Swap.SetName("fish") then
        local state = State()
        if not (state and state.kind == "fish") then Swap.Wear("fish") end
    end
end

-- Der Wurf ist gescheitert (V-117): Liegt die Angel im Set, gelingt der erste Wurf nie – dann kommt das Set jetzt,
-- der nächste Wurf klappt. Gilt für jeden gescheiterten Angel-Wurf (auch „kein Wasser“): wer auswirft, will angeln.
function Swap.OnSpellFailed(spellID)
    spellID = ns.Plain(spellID)
    if type(spellID) ~= "number" then return false end
    fishingName = fishingName or Core.SpellName(FishingSpell())
    local name = Core.SpellName(spellID)
    if not (name and fishingName and name == fishingName) then return false end
    if not (ns.Active("swapFishing") and Swap.SetName("fish")) then return false end
    if State() then return false end         -- Angel-Set schon an bzw. gerade das Reit-Set
    if ns.Plain(ns.Call(IsMounted)) == true then return false end
    lastFishCast = Now()
    return Swap.Wear("fish")
end

-- Zielzustand der Angelausrüstung herstellen (true = an, false = aus). Angelegt bzw. abgelegt wird nur, wenn der
-- Stand davon abweicht: Ist sie schon an, gilt sie ab jetzt als „von Hand“ (ohne Zeitgrenze); ist sie schon ab,
-- bleibt es dabei. → true, "on" | true, "off" | false, "noset"
local function ApplyFishing(want)
    local state = State()
    local wearing = state ~= nil and state.kind == "fish"
    if not want then
        if wearing then Swap.Restore() end
        ns.Print(L.SWAP_FISH_OFF)
        return true, "off"
    end
    if wearing then
        state.manual = true
    elseif not Swap.SetName("fish") then
        ns.Print(L.SWAP_NO_FISH_SET)
        return false, "noset"
    else
        Swap.Wear("fish", true)
    end
    lastFishCast = Now()
    ns.Print(L.SWAP_FISH_ON)
    return true, "on"
end

local fishOrder    -- im Kampf vorgemerkter Zielzustand (true = an, false = aus); nil = kein Auftrag wartet

-- Knopf „Angelausrüstung an/aus“ (Menü „Sets“, Einstellungen, /ezg angeln, Schnittstelle ToggleFishing).
-- → true, "on" (angelegt) | true, "off" (abgelegt) | true, "combat" (im Kampf: vorgemerkt, gleich danach) |
--   true, "cancelled" (im selben Kampf noch einmal gedrückt: der vorgemerkte Auftrag ist zurückgenommen) |
--   false, "noset" (kein Angel-Set gewählt)
-- Im Kampf wird der Zielzustand vorgemerkt (an bzw. aus – nicht „umschalten“), unter dem eigenen Schlüssel „fish“,
-- damit ein wartendes Reit-Umziehen bleibt: Swap.Evaluate allein würde ein von Hand angelegtes Angel-Set weder
-- anlegen noch ablegen. Der Zielzustand zählt, weil sich der Stand bis zum Kampfende ändern kann: Läuft im Kampf
-- die Leerlauf-Frist ab, legt das früher vorgemerkte Swap.Evaluate das Angel-Set ab – „umschalten“ legte es danach
-- wieder an (Fund der Gegenprüfung, Welle 3). Noch einmal im selben Kampf gedrückt nimmt den Auftrag zurück.
function ns.ToggleFishing()
    local state = State()
    local wearing = state ~= nil and state.kind == "fish"
    if not ns.InCombat() then
        fishOrder = nil
        return ApplyFishing(not wearing)
    end
    if fishOrder ~= nil then
        fishOrder = nil
        Core.CancelAfterCombat(FISH_KEY)
        ns.Print(L.SWAP_FISH_CANCELLED)
        return true, "cancelled"
    end
    if not wearing and not Swap.SetName("fish") then
        ns.Print(L.SWAP_NO_FISH_SET)
        return false, "noset"
    end
    fishOrder = not wearing
    ns.AfterCombat(function()
        local want = fishOrder
        fishOrder = nil
        if want ~= nil then ApplyFishing(want) end
    end, "fish")
    Core.CombatNotice(ns, fishOrder and L.SWAP_FISH_ON_WHAT or L.SWAP_FISH_OFF_WHAT, "later")   -- ezCores Satz (T18-1)
    return true, "combat"
end

---------------------------------------------------------------------------
-- Menü (im Menü „Sets“ am Charakterfenster)
---------------------------------------------------------------------------

local AUTO = false    -- Wert im Menü für „automatisch nach Name“ (gespeichert als nil; kein Text, damit kein Set-Name ihn trifft)

local function ChoiceMenu(root, kind, label, tip)
    local Menu = Core.Menu
    local current = Swap.SetName(kind)
    local text = label:format(current or L.SWAP_NONE)
    local sub = ns.MenuTip(Menu.Button(root, text), text, tip)
    if not (sub and sub.CreateRadio) then return end
    local function Get()
        local explicit = ns.Char()[kind .. "Set"]
        if explicit == nil then return AUTO end
        return explicit
    end
    local function Set(value)
        if value == AUTO then value = nil end
        Swap.SetChoice(kind, value)
        if kind == "mount" and value == "" then Swap.Evaluate() end
    end
    ns.MenuTip(Menu.Radio(sub, L.SWAP_NONE, Get, Set, ""), L.SWAP_NONE, L.MTIP_SWAP_NONE)
    ns.MenuTip(Menu.Radio(sub, L.SWAP_AUTO, Get, Set, AUTO), L.SWAP_AUTO, L.MTIP_SWAP_AUTO)
    for _, set in ipairs(ns.Sets.List()) do
        ns.MenuTip(Menu.Radio(sub, set.name, Get, Set, set.name), set.name, L.MTIP_SWAP_SET)
    end
end

function ns.AddSwapMenu(root)
    ChoiceMenu(root, "mount", L.SWAP_MOUNT_MENU, L.MTIP_SWAP_MOUNT)
    ChoiceMenu(root, "fish", L.SWAP_FISH_MENU, L.MTIP_SWAP_FISH)
    ns.MenuTip(Core.Menu.Button(root, L.SWAP_FISH_TOGGLE, function() ns.ToggleFishing() end), L.SWAP_FISH_TOGGLE,
        L.OPT_SWAP_FISH_TIP .. " " .. L.MTIP_FISH_CMD)
end

---------------------------------------------------------------------------

ns.OnReady(function()
    ns.On("PLAYER_MOUNT_DISPLAY_CHANGED", function() ns.Try("Swap", Swap.Evaluate) end)
    -- nur die eigenen Zauber (ns.OnUnit: der Client weckt den Zuhörer für andere Einheiten gar nicht)
    ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
        ns.Try("Swap", Swap.OnSpellCast, spellID)
    end)
    for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" }) do
        ns.OnUnit(event, "player", function(_, _, _, spellID)
            ns.Try("Swap", Swap.OnSpellFailed, spellID)
        end)
    end
    -- Griff gemerkt (Swap.ticker) und der ganze Rückruf in ns.Try (Gesamtreview 18.11.2026, T7-3): auch State()
    -- liegt im Schutz, ein Fehler steht in der Fehlerliste.
    if not Swap.ticker and C_Timer and C_Timer.NewTicker then
        Swap.ticker = C_Timer.NewTicker(15, function() ns.Try("Swap", Swap.FishTick) end)
    end
    -- Nach /reload: Reittier weg, Set noch an → zurück
    ns.Try("Swap", Swap.Evaluate)
    ns.OnSettingChanged(function(key)
        if key == "swapMount" or key == "swapFishing" then ns.Try("Swap", Swap.Evaluate) end
    end)
end)

ns.AddStatusLine(function()
    local state = State()
    return L.STATUS_SWAP:format(Swap.SetName("mount") or L.SWAP_NONE, Swap.SetName("fish") or L.SWAP_NONE,
        state and (L["SWAP_KIND_" .. state.kind] or state.kind) or L.SWAP_NONE)
end)
