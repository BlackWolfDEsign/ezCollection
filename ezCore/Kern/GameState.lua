local _, ns = ...
local Core = ezCore

--[[
    Kleine Abfragen zum Zustand des Spiels, die mehrere Module brauchen (Welle 23a, Liste „Reste vor der Doku-Welle“):

      Core.AuctionHouseOpen() → true/false (A12; vorher ezBag Groups.AuctionHouseOpen und ezAuction
          ns.AuctionHouseShown): Blizzards AuctionHouseFrame sichtbar, sonst der gemerkte Stand aus
          AUCTION_HOUSE_SHOW/AUCTION_HOUSE_CLOSED (das Fenster lädt erst beim ersten Besuch). Nur lesen.
      Core.WeaponEnchantInfo() → lesbar, hatMain, msMain, hatOff, msOff (A13; vorher ezCombat ns.WeaponEnchantInfo
          und ezBuff Weapon.Info): Verzauberung auf Zeit (Gift, Wetzstein, Waffenzauber) beider Hände wie Blizzards
          globales GetWeaponEnchantInfo. Zuerst das Globale (laut Daten-Probe auf Forever vorhanden, V-185), sonst
          C_Item.GetWeaponEnchantInfo(Platz) → { { hasEnchant, enchantType, timeLeft, … } } (Blizzards Forever-Quelle,
          ItemDocumentation; Einheit von timeLeft dort nicht genannt – angenommen Millisekunden wie beim Globalen).
          Ohne beide oder bei einem Fehler: false (die Funktion ruht). Der erste Wert ist nie gesperrt; die übrigen
          können es sein und werden hier nie mit nil verglichen. Ist die Art einer Verzauberung gesperrt und keine
          andere lesbar auf Zeit, kommt der gesperrte Wert als „verzaubert?“ zurück – der Aufrufer sieht „unbekannt“
          und behält seinen gemerkten Stand (Leitlinie 6).
]]

---------------------------------------------------------------------------
-- Auktionshaus offen?
---------------------------------------------------------------------------

local auctionOpen = false
ns.On("AUCTION_HOUSE_SHOW", function() auctionOpen = true end)
ns.On("AUCTION_HOUSE_CLOSED", function() auctionOpen = false end)

function Core.AuctionHouseOpen()
    local frame = rawget(_G, "AuctionHouseFrame")
    if type(frame) == "table" and type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not Core.IsSecret(shown) and type(shown) == "boolean" then return shown end
    end
    return auctionOpen
end

---------------------------------------------------------------------------
-- Waffenverzauberung auf Zeit
---------------------------------------------------------------------------

-- Aus einer Liste von C_Item.GetWeaponEnchantInfo: verzaubert?, Restzeit. Eine gesperrte Art merkt sich nur den
-- ersten gesperrten Wert (mit einem eigenen Merker – ein gesperrter Wert darf nicht mit nil verglichen werden).
local function FromList(list)
    if Core.IsSecret(list) or type(list) ~= "table" then return list, nil end
    local temporary = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Temporary
    local locked, hasLocked = nil, false
    for _, info in ipairs(list) do
        if type(info) == "table" and not Core.IsSecret(info) then
            local kind = Core.Peek(info, "enchantType")
            if Core.IsSecret(kind) then
                if not hasLocked then locked, hasLocked = kind, true end
            elseif temporary == nil or kind == temporary then
                return Core.Peek(info, "hasEnchant"), Core.Peek(info, "timeLeft")
            end
        end
    end
    if hasLocked then return locked, nil end
    return false, nil
end

function Core.WeaponEnchantInfo()
    local global = rawget(_G, "GetWeaponEnchantInfo")
    if type(global) == "function" then
        local ok, hasMain, mainMs, _, _, hasOff, offMs = pcall(global)
        if ok then return true, hasMain, mainMs, hasOff, offMs end
        return false
    end
    local api = C_Item and C_Item.GetWeaponEnchantInfo
    local slots = Enum and Enum.WeaponSlot
    if type(api) ~= "function" or type(slots) ~= "table" or slots.MainHand == nil then return false end
    local okMain, main = pcall(api, slots.MainHand)
    if not okMain then return false end
    local hasMain, mainMs = FromList(main)
    local hasOff, offMs = false, nil
    if slots.OffHand ~= nil then
        local okOff, off = pcall(api, slots.OffHand)
        if okOff then hasOff, offMs = FromList(off) end
    end
    return true, hasMain, mainMs, hasOff, offMs
end
