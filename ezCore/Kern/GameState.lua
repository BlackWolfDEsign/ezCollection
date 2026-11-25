local _, ns = ...
local Core = ezCore

--[[
    Kleine Abfragen zum Zustand des Spiels, die mehrere Module brauchen (Welle 23a, Liste „Reste vor der Doku-Welle“):

      Core.AuctionHouseOpen() → true/false (A12; vorher ezBag Groups.AuctionHouseOpen und ezAuction
          ns.AuctionHouseShown): Blizzards AuctionHouseFrame sichtbar, sonst der gemerkte Stand aus
          AUCTION_HOUSE_SHOW/AUCTION_HOUSE_CLOSED (das Fenster lädt erst beim ersten Besuch). Nur lesen.
      Core.WeaponEnchantInfo() → lesbar, hatMain, msMain, hatOff, msOff (A13; vorher ezCombat ns.WeaponEnchantInfo
          und ezBuff Weapon.Info): Verzauberung auf Zeit (Gift, Wetzstein, Waffenzauber) beider Hände wie Blizzards
          altes globales GetWeaponEnchantInfo. Reihenfolge (seit dem Paket kern/abgeloeste-namen, 24.11.2026):
          1. C_PaperDollInfo.GetTemporaryEnchantmentInfo(Platz) → { remainingTimeMs, hasExpirationTime, … } oder nichts –
             das ruft Blizzards Ersatz für das Globale selbst auf. Läuft die Verzauberung nicht ab
             (hasExpirationTime = false), fehlt die Restzeit (nil) – nie 0, sonst gälte sie als „läuft bald ab“.
          2. C_Item.GetWeaponEnchantInfo(Platz) → { { hasEnchant, enchantType, timeLeft, … } } (Millisekunden:
             Blizzards BuffFrame.lua teilt timeLeft durch 1000).
          3. das Globale (auf Forever nur noch Blizzards Ersatz hinter der CVar loadDeprecationFallbacks).
          Ohne alle drei oder bei einem Fehler: false (die Funktion ruht). Der erste Wert ist nie gesperrt; die übrigen
          können es sein und werden hier nie mit nil verglichen. Ist die Antwort je Platz gesperrt oder die Art einer
          Verzauberung (und keine andere lesbar auf Zeit), kommt der gesperrte Wert als „verzaubert?“ zurück – der
          Aufrufer sieht „unbekannt“ und behält seinen gemerkten Stand (Leitlinie 6).
      Core.KnowsSpell(id, begleiter) → true | false | nil (keine Antwort, gesperrt): hat der Spieler bzw. sein Begleiter
          genau diesen Zauber (auch, was nicht im Zauberbuch steht: Fertigkeiten, Rezepte)? Vorher je Stelle das globale
          IsPlayerSpell; Blizzards Ersatz dafür ruft C_SpellBook.IsSpellKnown – so fragt ezCore jetzt selbst (Paket
          kern/abgeloeste-namen). Die alte Globale bleibt Rückfall (nur Spieler).
      Core.KnowsSpellApi() → die Funktion dahinter oder nil (Schlüssel für Zwischenspeicher).
      Core.SpellInBook(id, begleiter) → true | false | nil: steht genau dieser Zauber im Zauberbuch (ohne Ersetzungen)?
          C_SpellBook.IsSpellInSpellBook (das ruft Blizzards Ersatz für das globale IsSpellKnown), sonst dieses.
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

-- Aus C_PaperDollInfo.GetTemporaryEnchantmentInfo (nichts = keine Verzauberung): lesbar?, verzaubert?, Restzeit.
local function FromSlot(api, slot)
    local ok, info = pcall(api, slot)
    if not ok then return false end
    if Core.IsSecret(info) then return true, info, nil end
    if type(info) ~= "table" then return true, false, nil end
    local expires = Core.Peek(info, "hasExpirationTime")
    if not Core.IsSecret(expires) and expires == false then return true, true, nil end
    return true, true, Core.Peek(info, "remainingTimeMs")
end

function Core.WeaponEnchantInfo()
    local bySlot = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if type(bySlot) == "function" then
        local SLOT = Core.EquipSlots.SLOT
        local okMain, hasMain, mainMs = FromSlot(bySlot, SLOT.MAINHAND)
        local okOff, hasOff, offMs = FromSlot(bySlot, SLOT.OFFHAND)
        if not (okMain and okOff) then return false end
        return true, hasMain, mainMs, hasOff, offMs
    end
    local api = C_Item and C_Item.GetWeaponEnchantInfo
    local slots = Enum and Enum.WeaponSlot
    if type(api) == "function" and type(slots) == "table" and slots.MainHand ~= nil then
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
    local ok, hasMain, mainMs, _, _, hasOff, offMs = Core.PCall(rawget(_G, "GetWeaponEnchantInfo"))
    if not ok then return false end
    return true, hasMain, mainMs, hasOff, offMs
end

---------------------------------------------------------------------------
-- Zauber des Spielers und seines Begleiters (genau diese ID)
---------------------------------------------------------------------------

-- Antwort des Clients: true/false, alles andere (gesperrt, keine Funktion, Fehler) ist „keine Antwort“.
local function YesNo(value)
    if Core.IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

function Core.KnowsSpellApi()
    return (C_SpellBook and C_SpellBook.IsSpellKnown) or rawget(_G, "IsPlayerSpell")
end

function Core.KnowsSpell(id, pet)
    id = Core.Num(id)
    if not id then return nil end
    if pet then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
        if bank == nil then return nil end
        return YesNo((Core.Call(C_SpellBook and C_SpellBook.IsSpellKnown, id, bank)))
    end
    return YesNo((Core.Call(Core.KnowsSpellApi(), id)))      -- ohne Bank: Blizzards Vorgabe „Spieler“
end

function Core.SpellInBook(id, pet)
    id = Core.Num(id)
    if not id then return nil end
    local api = C_SpellBook and C_SpellBook.IsSpellInSpellBook
    if type(api) == "function" then
        local banks = Enum and Enum.SpellBookSpellBank
        local bank
        if banks and pet then bank = banks.Pet elseif banks then bank = banks.Player end
        if bank == nil then return nil end
        return YesNo((Core.Call(api, id, bank, false)))
    end
    return YesNo((Core.Call(rawget(_G, "IsSpellKnown"), id, pet and true or false)))
end
