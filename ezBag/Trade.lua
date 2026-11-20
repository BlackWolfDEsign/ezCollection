local _, ns = ...

--[[
    Tasche beim Handeln öffnen (Wunsch des Nutzers vom 16.11.2026: „wenn ngehandelt wird, oder man anhandelt muss
    sich auch die tasche öffnen“).

    Blizzard öffnet die Taschen beim Handeln nur mit der Gamepad-Oberfläche (TradeFrame_OnShow in
    Blizzard_UIPanels_Game/Mainline/TradeFrame.lua, Forever-Quelle); Händler, Bank, Post und Gildenbank öffnen sie
    über OpenAllBags(frame). ezBag macht es beim Handelsfenster genauso – egal, wer wen anhandelt, denn beide Wege
    enden in TRADE_SHOW (eine fremde Anfrage ist vorher nur Blizzards Rückfrage „TRADE“ zu TRADE_REQUEST):
      TRADE_SHOW   öffnet mit OpenAllBags(TradeFrame)    (über ezCores Core.OpenPanel("bags", …))
      TRADE_CLOSED schließt mit CloseAllBags(TradeFrame) (Core.ClosePanel)
    Blizzards OpenAllBags merkt sich das Fenster nur, wenn noch keine Tasche offen war; CloseAllBags(frame) schließt
    nur, was dieses Fenster geöffnet hat. War die Tasche vorher offen, bleibt sie also offen.

    Händler und Post: Handelsfenster, Händler- und Postfenster stehen bei Blizzard alle links und sind nicht
    verschiebbar (UIPanelWindows, area "left", pushable 0, Blizzard_UIParentPanelManager/Mainline/UIPanelWindows.lua).
    Das Handelsfenster ersetzt deshalb ein offenes Händler- oder Postfenster (FramePositionDelegate:SetUIPanel), und
    dessen OnHide schließt mit CloseAllBags(MerchantFrame bzw. MailFrame) die Tasche, die es geöffnet hatte. Ob das
    vor oder nach ezBags TRADE_SHOW läuft, hängt an der Reihenfolge der Ereignis-Empfänger. Darum fragt ezBag einen
    Bildaufbau später noch einmal nach: Ist die Tasche dann zu, öffnet OpenAllBags(TradeFrame) sie wieder (diesmal
    mit dem Handelsfenster als Öffner, also schließt sie nach dem Handel); ist sie offen, tut der zweite Aufruf nichts.

    Taint-sicher (Leitlinie 5): nur Blizzards eigene Funktionen gerufen, keine Werte in Blizzards Tabellen. Im Kampf
    öffnet und schließt ezCore keine Fenster; dann holt ezCores Warteschlange (ns.AfterCombat, V-010) den letzten
    Wunsch nach dem Kampf nach – Öffnen und Schließen teilen sich einen Schlüssel, nur der jüngste läuft.
    Rücksicht (Leitlinie 9): Ersetzt ein fremdes Addon die Tasche (Funktionsschlüssel „bags“: Baganator, Bagnon …),
    öffnet ezBag nichts – solche Addons haben eigene Regeln, wann ihre Tasche aufgeht.
]]

local Trade = {}
ns.Trade = Trade

-- Schlüssel in ezCores Warteschlange „nach dem Kampf“ (im Modul: „ezBag:trade“)
Trade.AFTER_COMBAT_KEY = "trade"

local trading = false    -- Handelsfenster offen (zwischen TRADE_SHOW und TRADE_CLOSED)
local opened = false     -- ezBag hat OpenAllBags(TradeFrame) gerufen; nur dann wird beim Schließen etwas zugemacht

-- Soll die Tasche mit dem Handelsfenster aufgehen? (Schalter an, kein fremdes Taschen-Addon)
function Trade.Wanted()
    return ns.S ~= nil and ns.S.openOnTrade == true and ns.OtherBags() == nil
end

-- Tasche zum Handelsfenster öffnen (läuft außerhalb des Kampfes, über ns.AfterCombat).
-- → true, wenn ezCore die Taschen geöffnet hat (bzw. sie schon offen waren)
function Trade.Open()
    local owner = _G.TradeFrame
    if not trading or not owner or not Trade.Wanted() then return false end
    if ezCore.OpenPanel("bags", owner, true) == true then
        opened = true
        return true
    end
    return false
end

-- Was das Handelsfenster geöffnet hat, wieder schließen (Blizzards CloseAllBags(TradeFrame) lässt Fremdes offen).
-- Fragt den Schalter bewusst nicht ab: Wer ihn während des Handels ausschaltet, bekommt die Tasche trotzdem zu.
function Trade.Close()
    if not opened then return false end
    opened = false
    local owner = _G.TradeFrame
    if not owner then return false end
    return ezCore.ClosePanel("bags", owner, true) == true
end

-- Stand für Prüfungen: Handel läuft, von ezBag geöffnet
function Trade.State()
    return trading, opened
end

local function Request(fn)
    return ns.AfterCombat(fn, Trade.AFTER_COMBAT_KEY)
end

ns.On("TRADE_SHOW", function()
    trading = true
    Request(Trade.Open)
    -- Händler- oder Postfenster, das gerade dem Handelsfenster weicht, kann die Tasche noch schließen (siehe oben)
    C_Timer.After(0, function()
        if trading then Request(Trade.Open) end
    end)
end)
ns.On("TRADE_CLOSED", function()
    trading = false
    Request(Trade.Close)
end)
