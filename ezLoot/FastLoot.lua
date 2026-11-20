local _, ns = ...
local Core = ezCore

--[[
    Schneller plündern.
    Plündert das Spiel automatisch (Einstellung „Automatisch plündern“, umgekehrt mit der Taste dafür), holt
    ezLoot alle Plätze sofort, statt Blizzards Pause zwischen den Gegenständen abzuwarten. Ohne automatisches
    Plündern tut ezLoot nichts – dann entscheidet der Spieler im Plündernfenster.
    Gesperrte Plätze (gerade ausgewürfelt oder von jemand anderem beansprucht) bleiben liegen; Gegenstände, die
    beim Aufheben binden, fragt das Spiel wie immer nach. Läuft „Faster auto loot“ von Leatrix Plus, hält sich
    ezLoot zurück (ns.FastLootActive).
]]

local FastLoot = {}
ns.FastLoot = FastLoot

-- Ein Plündern-Vorgang löst LOOT_READY mehrmals aus; innerhalb dieser Zeit nur einmal alles holen.
FastLoot.DELAY = 0.3
local lastRun = -math.huge

-- Will das Spiel jetzt automatisch plündern? autoLoot aus LOOT_READY, sonst wie im Spiel berechnet.
function FastLoot.Wanted(autoLoot)
    if type(autoLoot) == "boolean" and not ns.IsSecret(autoLoot) then return autoLoot end
    local toggled = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") == true
    return ns.AutoLootOn() ~= toggled
end

-- Darf dieser Platz sofort geholt werden?
function FastLoot.Lootable(slot)
    local _, item, quantity, _, _, locked = GetLootSlotInfo(slot)
    if ns.IsSecret(item) or ns.IsSecret(locked) or ns.IsSecret(quantity) then return false end
    if locked then return false end
    if GetLootSlotType and Enum and Enum.LootSlotType then
        local kind = GetLootSlotType(slot)
        if ns.IsSecret(kind) or kind == Enum.LootSlotType.None then return false end
    end
    return item ~= nil or (ns.Num(quantity) or 0) > 0
end

-- Holt alle freien Plätze, von hinten nach vorn (wie Blizzard und Leatrix: Plätze rücken sonst nach).
-- Rückgabe: Anzahl der angestoßenen Plätze.
function FastLoot.Run(autoLoot)
    if not ns.FastLootActive() or not FastLoot.Wanted(autoLoot) then return 0 end
    local now = Core.Uptime()
    if now - lastRun < FastLoot.DELAY then return 0 end
    lastRun = now
    local count = ns.Num(GetNumLootItems()) or 0
    local looted = 0
    for slot = count, 1, -1 do
        if FastLoot.Lootable(slot) then
            LootSlot(slot)
            looted = looted + 1
        end
    end
    return looted
end

ns.On("LOOT_READY", function(_, autoLoot) FastLoot.Run(autoLoot) end)
-- Nach dem Schließen darf der nächste Vorgang sofort starten (z. B. mehrere Leichen hintereinander).
ns.On("LOOT_CLOSED", function() lastRun = -math.huge end)
