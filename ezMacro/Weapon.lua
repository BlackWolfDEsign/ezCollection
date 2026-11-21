local _, ns = ...
local Core = ezCore

--[[
    Gift und Waffenzauber je Hand (Paket ezmacro/gifte-waffenzauber; Wunsch des Nutzers vom 20.11.2026: „Können wir
    auch ermöglichen z.b. Waffen ebenso mit Giften zu belegen (schurke) und co? … Blizzard konform?“). Vier Einträge
    im Reiter „Ein-Klick“ (Data\OneClick.lua), dieselbe Technik wie Essen und Trinken (OneClick.lua): Platzhalter
    {i:<art>}, übernommen auf Klick, außerhalb des Kampfes aktuell gehalten.

      {i:poisonMain}  „#showtooltip item:<id>“, „/use item:<id>“, „/use 16“ – Schurke: das beste Gift bzw. die beste
      {i:poisonOff}   Waffenverzauberung bei dir auf die Waffe der Waffenhand (16) bzw. Schildhand (17)
      {i:enhanceMain} wie {i:poisonMain}/{i:poisonOff}, aber für jede Klasse (Entscheidung des Nutzers vom 20.11.2026:
      {i:enhanceOff}  „ja definitv“, „auch für magieöl und co, vollständig“): Wetzstein, Gewichtsstein, Zauberöl,
                      Manaöl – die beste Waffenverzauberung bei dir nach derselben Regel (Core.BestItems.WeaponEnchant)
      {i:imbueMain}   „#showtooltip“, „/cast <Waffenzauber>“ – Schamane: der gewählte Waffenzauber
      {i:imbueOff}    dazu „/use 17“: die Waffe der Schildhand als Ziel (Schamane mit zwei Waffen). Ungeprüft: Ob
                      Blizzard den Waffenzauber so auf die Schildhand legt oder wieder auf die Waffenhand, klärt der
                      Spieltest (docs/roadmap/ezMacro.md; ezBuff gibt der Schildhand deshalb bisher keinen Zauber).

    Eine Quelle (Leitlinie 2): Den Gegenstand wählt ezCore (Core.BestItems.WeaponEnchant – dieselbe Regel wie ezBuffs
    Aufgabe am Buff-Knopf), die Makrozeilen „Gegenstand auf die Waffe“ baut ezCore (Core.Macro.WeaponItem, auch für
    ezBuff), die Plätze stehen in Core.HAND_SLOTS. Den Waffenzauber wählt ezBuff (gemerkte Wahl über
    ezCore.API("ezBuff").Preferred("imbue")), sonst ezCores Vorschlag (Core.Spells.ChooseImbue). ezMacro führt keine
    eigene Liste.

    Blizzard-konform: Ein Tastendruck ist eine Aktion – der Gegenstand bzw. Zauber und die Wahl der Waffe als Ziel
    („/use 16“ bzw. „/use 17“, wie Blizzards eigene Makros). Neu geschrieben wird nur außerhalb des Kampfes
    (EditMacro ist geschützt; OneClick.Refresh wartet sonst auf das Kampfende, Leitlinie 5). Ersetzt das Gift eine
    liegende Verzauberung, fragt Blizzard selbst nach.
    Ohne Waffe in der Hand (Schild, Nebenhand-Gegenstand, Angelrute, leer) liefert der Platzhalter nichts; der Eintrag
    ist grau und nennt den Grund.
]]

local Weapon = {}
ns.WeaponMacros = Weapon

local OC = ns.OneClick
local Plain = Core.Plain

Weapon.POISON = { poisonMain = "main", poisonOff = "off" }
Weapon.ENHANCE = { enhanceMain = "main", enhanceOff = "off" }
Weapon.IMBUE = { imbueMain = "main", imbueOff = "off" }
Weapon.CLASS = { poison = "ROGUE", imbue = "SHAMAN" }

local function Slot(hand)
    local slots = Core.HAND_SLOTS or { main = 16, off = 17 }
    return slots[hand]
end

-- Trägt die Hand eine Waffe, die eine Verzauberung auf Zeit annimmt? (ezCores Core.WeaponEnchantable, dieselbe Regel
-- wie ezBuffs Buff-Knopf; Angelrute, Schild und Nebenhand-Gegenstand nicht)
function Weapon.HasWeapon(hand)
    return Core.WeaponEnchantable(hand) == true
end

-- Makrotext „bester Gegenstand auf diese Hand“ | nil, Grund (noItem: missing, z. B. "no_poison" bzw. "no_enhance";
-- noFit: "no_fit"). Nur, was die Waffe dieser Hand annimmt (Paket ezcore/klinge-wucht: Client-Tabelle
-- SpellEquippedItems über Core.BestItems.WeaponEnchant mit Hand – Wetzstein nur Klingen, Gewichtsstein nur Wuchtwaffen).
function Weapon.ItemLines(hand, missing)
    if not Weapon.HasWeapon(hand) then return nil, "no_weapon_" .. hand end
    local itemID, why = Core.BestItems.WeaponEnchant(nil, hand)
    if not itemID then return nil, (why == "noItem" and missing) or (why == "noFit" and "no_fit") or why end
    local lines = Core.Macro.WeaponItem(itemID, Slot(hand))
    if not lines then return nil, missing end
    return ("#showtooltip item:%d\n"):format(itemID) .. lines
end

-- Makrotext „Gift auf diese Hand“ (nur Schurke) | nil, Grund.
function Weapon.PoisonLines(hand)
    if Core.PlayerClass() ~= Weapon.CLASS.poison then return nil end
    return Weapon.ItemLines(hand, "no_poison")
end

-- Makrotext „Wetzstein, Gewichtsstein oder Öl auf diese Hand“ (jede Klasse) | nil, Grund.
function Weapon.EnhanceLines(hand)
    return Weapon.ItemLines(hand, "no_enhance")
end

-- Gewählter Waffenzauber → Schlüssel, Zauber-ID | nil: ezBuffs gemerkte Wahl, sonst ezCores Vorschlag.
function Weapon.ChosenImbue()
    local api = Core.API and Core.API("ezBuff")
    local prefer = api and type(api.Preferred) == "function" and Plain(Core.Call(api.Preferred, "imbue")) or nil
    return Core.Spells.ChooseImbue(prefer, Weapon.CLASS.imbue)
end

-- Makrotext „Waffenzauber auf diese Hand“ | nil, Grund.
function Weapon.ImbueLines(hand)
    if Core.PlayerClass() ~= Weapon.CLASS.imbue then return nil end
    if not Weapon.HasWeapon(hand) then return nil, "no_weapon_" .. hand end
    local _, spell = Weapon.ChosenImbue()
    local name = spell and ns.SpellName(spell)
    if type(name) ~= "string" or name == "" then return nil, "no_imbue" end
    local text = "#showtooltip\n/cast " .. name
    if hand == "off" then text = text .. "\n/use " .. Slot("off") end
    return text
end

-- Symbol in der Liste, solange kein Text gebaut ist (Waffenzauber: der Zauber; Gift zeigt #showtooltip den Gegenstand).
local function ImbueIcon()
    local _, spell = Weapon.ChosenImbue()
    return spell and ns.SpellIcon(spell) or nil
end

---------------------------------------------------------------------------
-- Anmelden: Platzhalter, Formen (nur so ein Makro schreibt OneClick.Refresh neu), Symbole, Ereignisse
---------------------------------------------------------------------------

-- Form „Gegenstand auf die Waffe dieser Hand“ (eine Stelle für Gift und Stein/Öl)
local function ItemShape(hand) return "^#showtooltip item:%d+\n/use item:%d+\n/use " .. Slot(hand) .. "$" end
for kinds, build in pairs({ [Weapon.POISON] = function(hand) return Weapon.PoisonLines(hand) end,
    [Weapon.ENHANCE] = function(hand) return Weapon.EnhanceLines(hand) end }) do
    for kind, hand in pairs(kinds) do
        ns.Dynamic.Register(kind, function() return build(hand) end)
        OC.SHAPES[kind] = ItemShape(hand)
    end
end
for kind, hand in pairs(Weapon.IMBUE) do
    ns.Dynamic.Register(kind, function() return Weapon.ImbueLines(hand) end)
    OC.SHAPES[kind] = hand == "off" and ("^#showtooltip\n/cast [^\n]+\n/use " .. Slot("off") .. "$") or "^#showtooltip\n/cast [^\n]+$"
    OC.ICONS[kind] = ImbueIcon
end

-- Waffe gewechselt, Zauber gelernt (OneKey hört SPELLS_CHANGED schon), Wahl in ezBuff geändert: neu schreiben
-- (gebündelt, nur außerhalb des Kampfes – OneClick.Schedule/Refresh).
ns.On("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
    if Core.IsSecret(slot) or slot == nil or slot == Slot("main") or slot == Slot("off") then OC.Schedule() end
end)
Core.Listen("EZBUFF_PREFER_CHANGED", function(group)
    if group == "imbue" then OC.Schedule() end
end, "ezMacro")
