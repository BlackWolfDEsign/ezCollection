local _, ns = ...
local L = ns.L
local Core = ezCore

-- Gift und Waffenverzauberung (Schurkengifte, Wetzsteine, Zauberöle, Waffenbuffs des Schamanen):
-- kurz vor Ablauf und beim Ablaufen eine Meldung in Blizzards gelber Hinweiszeile oben in der Bildschirmmitte
-- (UIErrorsFrame), dazu im Chat und auf Wunsch mit Blizzards Warnton.
-- Gesperrte Werte (V-107): Gibt das Spiel nicht heraus, ob eine Hand verzaubert ist oder wie lange noch, ist der
-- Stand unbekannt – nicht „abgelaufen“. Dann kommt keine Meldung, der zuletzt offen gelesene Stand bleibt gemerkt,
-- ns.NoteSecret("enchants"), und /ezk status sowie der Tooltip des Schalters sagen es. Ist der Wert wieder lesbar
-- und die Verzauberung inzwischen weg, rechnet ezCombat die seither vergangene Zeit ab: War sie rechnerisch am
-- Ablaufen, kommt die Meldung „abgelaufen“ nachträglich.
local Enchants = {}
ns.Enchants = Enchants

local CHECK = 5             -- Sekunden zwischen zwei Prüfungen
local GONE_WINDOW = 15      -- war der Rest so klein, ist die Verzauberung abgelaufen (und nicht abgelegt)

local hands = { main = {}, off = {} }

-- Restzeit mit ezCores Text („1 Min. 40 Sek.“), mindestens eine Sekunde.
local function FormatLeft(seconds)
    return Core.Duration(math.max(1, seconds))
end

function Enchants.Warn(text)
    Core.ErrorMessage(text, "warn")     -- Hinweiszeile oben, Rolle statt Farbzahlen (Gesamtreview T18-23)
    ns.Print(text)
    -- Warnton auf dem Kanal „Master“ (docs/design-system.md, „Warntöne“; T16-NM4, T16-NM5)
    if ns.S.enchantSound then Core.PlaySound("RAID_WARNING", "Master") end
end

-- Ein Zustand je Hand: läuft bald ab → einmal warnen; neu aufgetragen → wieder scharf; abgelaufen → melden.
function Enchants.Evaluate(hand, has, expirationMs)
    local slot = hands[hand]
    if has and expirationMs then
        if slot.last and expirationMs > slot.last + 1000 then slot.warned = false end
        if not slot.warned and expirationMs <= ns.S.enchantWarn * 1000 then
            slot.warned = true
            Enchants.Warn(L.ENCHANT_SOON:format(L["HAND_" .. hand], FormatLeft(expirationMs / 1000)))
        end
        slot.last, slot.active, slot.readAt = expirationMs, true, GetTime()
    elseif has then
        -- Verzauberung ohne Ablauf (Core.WeaponEnchantInfo: keine Restzeit): weder „läuft bald ab“ noch „abgelaufen“
        slot.active, slot.last, slot.warned, slot.readAt = false, nil, false, nil
    else
        -- Rest beim letzten offenen Lesen, abzüglich der Zeit seither (eine Sperre kann dazwischen gelegen haben).
        local left = slot.last and (slot.last - (GetTime() - (slot.readAt or GetTime())) * 1000)
        if slot.active and left and left <= GONE_WINDOW * 1000 then
            Enchants.Warn(L.ENCHANT_GONE:format(L["HAND_" .. hand]))
        end
        slot.active, slot.last, slot.warned, slot.readAt = false, nil, false, nil
    end
end

-- Eine Hand auswerten. Gesperrt (verzaubert ja/nein oder die Restzeit) = unbekannt: keine Meldung, der gemerkte
-- Stand bleibt. → true, wenn ausgewertet wurde
function Enchants.CheckHand(hand, has, expirationMs)
    if ns.IsSecret(has) or ns.IsSecret(expirationMs) then
        ns.NoteSecret("enchants")
        return false
    end
    Enchants.Evaluate(hand, has and true or false, ns.Num(expirationMs))
    return true
end

function Enchants.Check()
    if not ns.Enabled("enchants") then return end
    local readable, hasMain, mainMs, hasOff, offMs = Core.WeaponEnchantInfo()   -- V-185: ezCore (C_PaperDollInfo, sonst C_Item, global)
    if not readable then return end
    Enchants.CheckHand("main", hasMain, mainMs)
    Enchants.CheckHand("off", hasOff, offMs)
end

-- Nur für den Spieler (ns.OnUnit: Blizzard weckt den Zuhörer nur für ihn, V-042). Eine gesperrte Einheit stellt
-- ezCore trotzdem zu – sie zählt als der Spieler und wird nie verglichen (Leitlinie 6).
ns.OnUnit("UNIT_INVENTORY_CHANGED", "player", function(_, unit)
    if ns.IsSecret(unit) or unit == "player" then Enchants.Check() end
end)

-- Takt mit Griff, Fehler in ezCombats Fehlerliste (ezCores Ticker-Helfer, Gesamtreview 18.11.2026, T7-3); er läuft nur,
-- solange der Hinweis an ist (Enchants.Check täte sonst nichts; Gegenprüfung P19c).
local function EnchantsOn() return ns.Enabled("enchants") end

ns.OnReady(function()
    Enchants.Check()
    Enchants.ticker = ns.Ticker(CHECK, Enchants.Check, EnchantsOn, "Enchants")
end)
ns.OnSettingChanged(function(key)
    if key == "enchants" and Enchants.ticker then Enchants.ticker:Update() end
end)

-- /ezk status: nur, wenn die Verzauberung wirklich gesperrt gesehen wurde – sagt, was deshalb ruht.
ns.AddStatusLine(function()
    if not (ns.Enabled("enchants") and ns.secretSeen.enchants) then return nil end
    return L.STATUS_ENCHANTS_LOCKED
end)

ns.AddPreview("enchants", 80, function()
    Enchants.Warn(L.ENCHANT_SOON:format(L.HAND_main, FormatLeft(ns.S.enchantWarn)))
    return true
end)
