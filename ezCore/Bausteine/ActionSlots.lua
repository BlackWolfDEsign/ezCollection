local _, ns = ...
local Core = ezCore

--[[
    Aktionsplätze (Core.ActionSlots) – eine Stelle für ezMacro, ezBars und ezCombat (vorher las jedes Modul
    selbst, und der Plan der Plätze stand zweimal: ezMacro Profiles.SLOTS, ezBars Slots).

      MAX = 180, PER_PAGE = 12
      USABLE → { 1…120, 145…180 }; 121–144 sind Fahrzeug-, Übernahme- und Sonderleisten: nie anfassen
      IsUsable(slot) → true für 1–120 und 145–180
      PageOf(slot) → Seite 1–15        SlotsOfPage(page) → { … 12 Plätze }
      BLIZZARD_PAGES[page] = { bar, visible, frame }   Seite → Blizzards Zusatzleiste (Nummer in den Optionen)
      BONUS_PAGES[class] = { … }   Seiten 7–10, auf die die Hauptleiste mit Haltung/Gestalt wechselt
      IsBonusPage(page, class) → true, wenn die Klasse (Standard: eigene) diese Seite mit Haltung nutzt
      BonusPage() → Seite 7–10, auf die die Hauptleiste gerade mit Haltung/Gestalt wechselt, sonst nil
      MainPage() → Seite der Hauptleiste (Haltung, sonst 1); nil, "vehicle", solange Fahrzeug-, Übernahme- oder Sonderleiste
                   zu sehen ist; nil, "page", Seite, solange die Hauptleiste auf eine andere Seite geblättert ist
      BarShown(page) → true/false: ist Blizzards Zusatzleiste dieser Seite (BLIZZARD_PAGES) zu sehen? nil: keine Zusatzleiste
      Has(slot) → true/false (geheim: true, lieber zeigen)
      Info(slot) → { kind, id, subType, text, texture } oder nil (leer oder gesperrt); nie geheime Werte
      Texture(slot) → Symbol oder nil
      Text(slot) → Beschriftung des Platzes (bei Makros der Name) oder nil; leer und gesperrt sind nil
      SpellID(slot) → Zauber-ID, auch aus Makros, die einen Zauber zeigen (Untertyp „spell“ oder GetMacroSpell)
      ClickBindings(kind) → { [actionID] = true } für Blizzards Klick-Zauber ("spell" oder "macro"); liest über
          Core.ClickBindings.IDs (eine Stelle für C_ClickBindings, ClickBindings.lua)
      Cooldown(slot) → "none" | "gcd" | "real" | nil (unbekannt) – Art der Abklingzeit (vorher ezCombat
          Ready.SlotCooldown): C_ActionBar.GetActionCooldown, gesperrt über isActive/isOnGCD (Spells.CooldownKind),
          sonst GetActionCooldown
]]

local AS = {}
Core.ActionSlots = AS

AS.MAX, AS.PER_PAGE = 180, 12
AS.USABLE = {}
for slot = 1, 120 do AS.USABLE[#AS.USABLE + 1] = slot end
for slot = 145, AS.MAX do AS.USABLE[#AS.USABLE + 1] = slot end

AS.BLIZZARD_PAGES = {
    [6] = { bar = 2, visible = "MultiBar1_IsVisible", frame = "MultiBarBottomLeft" },
    [5] = { bar = 3, visible = "MultiBar2_IsVisible", frame = "MultiBarBottomRight" },
    [3] = { bar = 4, visible = "MultiBar3_IsVisible", frame = "MultiBarRight" },
    [4] = { bar = 5, visible = "MultiBar4_IsVisible", frame = "MultiBarLeft" },
    [13] = { bar = 6, visible = "MultiBar5_IsVisible", frame = "MultiBar5" },
    [14] = { bar = 7, visible = "MultiBar6_IsVisible", frame = "MultiBar6" },
    [15] = { bar = 8, visible = "MultiBar7_IsVisible", frame = "MultiBar7" },
}

AS.BONUS_PAGES = {
    WARRIOR = { 7, 8, 9 },          -- Kampf-, Verteidigungs-, Berserkerhaltung
    DRUID = { 7, 8, 9, 10 },        -- Katze, Schleichen, Bär, Mondkin
    ROGUE = { 7, 8 },               -- Verstohlenheit (und Schattentanz)
    PRIEST = { 7 },                 -- Schattengestalt
}

function AS.IsBonusPage(page, class)
    class = class or Core.PlayerClass()
    for _, entry in ipairs(AS.BONUS_PAGES[class] or {}) do
        if entry == page then return true end
    end
    return false
end

-- Wie Blizzards ActionBarController (Build 1.60.1.71091): HasBonusActionBar → GetBonusBarIndex; ältere Clients über
-- GetBonusBarOffset + 6. Andere Seiten als 7–10 (Sonderleisten) zählen nicht.
function AS.BonusPage()
    local api, page = C_ActionBar or {}, nil
    if api.HasBonusActionBar and api.GetBonusBarIndex then
        if Core.Plain((Core.Call(api.HasBonusActionBar))) ~= true then return nil end
        page = Core.Num((Core.Call(api.GetBonusBarIndex)))
    else
        local offset = Core.Num((Core.Call(rawget(_G, "GetBonusBarOffset"))))
        if offset and offset > 0 then page = offset + 6 end
    end
    return page and page >= 7 and page <= 10 and page or nil
end

function AS.MainPage()
    local api = C_ActionBar or {}
    for _, name in ipairs({ "HasVehicleActionBar", "HasOverrideActionBar", "HasTempShapeshiftActionBar" }) do
        local value = Core.Call(api[name] or rawget(_G, name))
        if Core.IsSecret(value) or value == true then return nil, "vehicle" end
    end
    -- Haltungen zählen bei Blizzard nur auf Seite 1
    local shown = Core.Num((Core.Call(api.GetActionBarPage or rawget(_G, "GetActionBarPage"))))
    if shown and shown ~= 1 then return nil, "page", shown end
    return AS.BonusPage() or 1
end

function AS.BarShown(page)
    local info = AS.BLIZZARD_PAGES[Core.Num(page) or 0]
    if not info then return nil end
    local check = rawget(_G, info.visible)
    if type(check) == "function" then
        local value = Core.Plain((Core.Call(check)))
        if value ~= nil then return value == true end
    end
    local frame = rawget(_G, info.frame)
    return type(frame) == "table" and type(frame.IsShown) == "function" and Core.Plain((Core.Call(frame.IsShown, frame))) == true
end

function AS.IsUsable(slot)
    slot = Core.Num(slot)
    return slot ~= nil and slot >= 1 and slot == math.floor(slot) and (slot <= 120 or (slot >= 145 and slot <= AS.MAX))
end

function AS.PageOf(slot)
    slot = Core.Num(slot)
    if not slot or slot < 1 then return nil end
    return math.floor((slot - 1) / AS.PER_PAGE) + 1
end

function AS.SlotsOfPage(page)
    page = Core.Num(page)
    local list = {}
    if not page or page < 1 then return list end
    for i = 1, AS.PER_PAGE do list[i] = (page - 1) * AS.PER_PAGE + i end
    return list
end

function AS.Has(slot)
    slot = Core.Num(slot)
    local api = (C_ActionBar and C_ActionBar.HasAction) or rawget(_G, "HasAction")
    if not (slot and type(api) == "function") then return false end
    local ok, has = pcall(api, slot)
    if not ok then return false end
    if Core.IsSecret(has) then return true end
    return has and true or false
end

function AS.Texture(slot)
    slot = Core.Num(slot)
    if not slot then return nil end
    return Core.Plain(Core.Call((C_ActionBar and C_ActionBar.GetActionTexture) or rawget(_G, "GetActionTexture"), slot))
end

function AS.Text(slot)
    slot = Core.Num(slot)
    if not slot then return nil end
    local text = Core.Plain((Core.Call((C_ActionBar and C_ActionBar.GetActionText) or rawget(_G, "GetActionText"), slot)))
    return type(text) == "string" and text ~= "" and text or nil
end

-- Art, ID, Untertyp ohne geheime Werte; nil für leere oder gesperrte Plätze.
local function Raw(slot)
    slot = Core.Num(slot)
    if not slot or not AS.Has(slot) then return nil end
    local kind, id, subType = Core.Call(rawget(_G, "GetActionInfo"), slot)
    kind, id, subType = Core.Plain(kind), Core.Plain(id), Core.Plain(subType)
    if type(kind) ~= "string" then return nil end
    return kind, id, subType
end

function AS.SpellID(slot)
    local kind, id, subType = Raw(slot)
    if kind == "spell" then return id end
    if kind == "macro" then
        if subType == "spell" then return id end
        return Core.Plain(Core.Call(rawget(_G, "GetMacroSpell"), id))
    end
    return nil
end

function AS.Info(slot)
    local kind, id, subType = Raw(slot)
    if not kind then return nil end
    return {
        kind = kind, id = id,
        subType = type(subType) == "string" and subType ~= "" and subType or nil,
        text = AS.Text(slot),
        texture = AS.Texture(slot),
    }
end

function AS.Cooldown(slot)
    slot = Core.Num(slot)
    if not slot then return nil end
    local kindOf = Core.Spells.CooldownKind
    local api = C_ActionBar and C_ActionBar.GetActionCooldown
    if type(api) == "function" then
        local info = Core.Call(api, slot)
        return kindOf(info)
    end
    local start, duration = Core.Call(rawget(_G, "GetActionCooldown"), slot)
    return kindOf(nil, start, duration)
end

function AS.ClickBindings(kind)
    if not (kind == "spell" or kind == "macro") then return {} end
    local CB = Core.ClickBindings
    if not (CB and CB.IDs) then return {} end
    return CB.IDs(kind)
end
