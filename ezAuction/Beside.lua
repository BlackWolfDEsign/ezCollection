local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Verhalten neben einem fremden Auktionshaus-Addon (Leitlinie 9; Vollprüfung 14.11.2026, Frage 35 – Empfehlung
    umgesetzt, Antwort offen): Läuft Auctionator, bleiben ezAuctions Teile in Blizzards drei Reitern, in den Reitern
    des fremden Addons stehen sie nicht (Core.lua, ns.ForeignView). Nur die Tooltip-Zeile „Auktion“ weicht, solange
    der Schalter „Auch neben anderen Auktions-Addons zeigen“ aus ist (Prices.lua, Scan.HoldBack) – neben jedem Addon,
    das ezCore unter „auctionTooltip“ führt (Auctionator, TradeSkillMaster), nicht nur neben denen aus Beside.ADDONS.
    Diese Datei ist die eine Stelle, die sagt, welcher Teil sich wie verhält – für „/eza status“, die
    Einstellungsseite und die Tooltips der Knöpfe „Preise erfassen“ und „Taschenliste“.
    Gefragt wird nur „läuft es?“ (Core.OtherAddOn) – weder die Einstellungen noch die Rahmen noch der Quelltext
    des fremden Addons werden gelesen, nichts wird dort geschrieben (Leitlinien 5 und 10).
]]

local Beside = {}
ns.Beside = Beside

-- Fremde Addons mit eigenen Reitern am Auktionsfenster: Schlüssel in Core.OTHER_ADDONS (ezCore/Wissen/OtherAddOns.lua).
-- Nur für sie gelten die Sätze unten (BESIDE_HEAD „In den Reitern von …“, SELL_LIST_BESIDE_TIP „der zweite Reiter zum
-- Verkaufen unten“, BESIDE_scan mit der gemeinsamen Sperrzeit des Komplett-Scans). TradeSkillMaster steht bewusst
-- nicht hier (Welle 27): ezCore führt es nur unter „auctionTooltip“ und „salvageValue“, nicht unter „auctionScan“;
-- wie sein Auktionsfenster auf Forever aussieht, ist nicht belegt (seine Dateien sind „All Rights Reserved“ und
-- werden nicht gelesen). Rücksicht (Leitlinie 9) braucht den Eintrag nicht: Doppelt stünde nur die Tooltip-Zeile,
-- und die weicht über ezCore (Scan.HoldBack, Beside.TooltipLine); fremde Ansichten am Auktionsfenster erkennt
-- ns.ForeignView ohne Namensliste. Zeigt der Spieltest Reiter von TSM an Blizzards Fenster, gehört es hierher.
Beside.ADDONS = { "Auctionator" }

-- Anzeigename und Schlüssel des laufenden fremden Addons, sonst nil.
function Beside.Running()
    for _, key in ipairs(Beside.ADDONS) do
        local runs, label = Core.OtherAddOn(key)
        if runs then return label or key, key end
    end
    return nil
end

-- ezAuctions Teile, die es im fremden Addon noch einmal gibt, in der Reihenfolge der Einstellungsseite:
--   key   die Einstellung des Teils (an ihrem Tooltip steht der Satz); „scan“ ist der Knopf „Preise erfassen“
--   text  Schlüssel des Satzes in Locale.lua (%s = Name des fremden Addons)
-- Die Tooltip-Zeile „Auktion“ steht nicht hier: sie weicht als einziger Teil (Beside.TooltipLine).
Beside.PARTS = {
    { key = "shoppingLists", text = "BESIDE_shoppingLists" },
    { key = "sellList", text = "BESIDE_sellList" },
    { key = "cancelButton", text = "BESIDE_cancelButton" },
    { key = "scan", text = "BESIDE_scan" },
}

-- Satz zu einem Teil (nil, solange kein fremdes Addon läuft oder der Teil nicht in der Liste steht).
function Beside.PartLine(key)
    local other = Beside.Running()
    if not other then return nil end
    for _, part in ipairs(Beside.PARTS) do
        if part.key == key then return L[part.text]:format(other, other) end
    end
    return nil
end

-- Satz zur Tooltip-Zeile „Auktion“: wer sie verdrängt bzw. dass sie trotzdem gezeigt wird; nil, wenn nichts zu
-- sagen ist (kein fremdes Addon, oder die Zeile ist ohnehin abgeschaltet). Beide Fälle fragen die Rücksicht je Teil
-- (ns.Yield, Core.lua): so nennt der Satz auch Addons, die nur Tooltip-Preise zeigen (TradeSkillMaster).
function Beside.TooltipLine()
    if not ns.Enabled("tooltipPrice") then return nil end
    -- reine Auskunft (Status, Einstellungsseite): ohne zu zählen, über die Rücksicht je Teil (Core.WhoHandlesInfo) –
    -- Scan.HoldBack zählt seit Welle 23 auch neben Auctionator mit
    local part = ns.Yield and ns.Yield.Part("tooltip")
    local yields = part and part.yields()
    if yields then return L.STATUS_TOOLTIP_YIELD:format(yields, L.OPT_tooltipBeside) end
    -- Schalter „Auch neben anderen Auktions-Addons zeigen“ an: neben wem die Zeile trotzdem steht (bis Welle 27 nur
    -- Beside.Running – neben TradeSkillMaster blieb der Satz deshalb aus)
    local other = part and part.forced()
    if other then return L.STATUS_TOOLTIP_BESIDE:format(other, L.OPT_tooltipBeside) end
    return nil
end

-- Die Sätze, die sich in einer Sitzung nicht ändern: Überschrift und je Teil eine Zeile. Leer, solange kein fremdes
-- Addon aus Beside.ADDONS läuft. Für feste Texte wie den Tooltip der Zeile „Neben Auctionator“ auf der
-- Einstellungsseite – den legt Blizzards Seite einmal beim Anmelden an, der Stand eines Schalters darf dort nicht stehen.
function Beside.PartLines()
    local lines = {}
    local other = Beside.Running()
    if other then
        lines[#lines + 1] = L.BESIDE_HEAD:format(other, other)
        for _, part in ipairs(Beside.PARTS) do lines[#lines + 1] = L[part.text]:format(other, other) end
    end
    return lines
end

-- Alle Sätze für „/eza status“ und den Knopf der Einstellungsseite: Überschrift, je Teil eine Zeile, dazu der
-- Stand der Tooltip-Zeile (hängt an den Schaltern, jedes Mal neu gefragt). Leer, solange kein fremdes Addon läuft
-- und nichts die Tooltip-Zeile verdrängt.
function Beside.Lines()
    local lines = Beside.PartLines()
    lines[#lines + 1] = Beside.TooltipLine()
    return lines
end

-- Tooltip einer Einstellung: ihr eigener Text und darunter der Satz zum fremden Addon. nil, wenn es nichts zu
-- ergänzen gibt – dann nimmt die Einstellungsseite den Text der Einstellung allein.
function Beside.Tip(key, base)
    local line = Beside.PartLine(key)
    if not line then return nil end
    return (base or L["OPT_" .. key .. "_TIP"]) .. "\n\n" .. line
end

-- Blizzards eigener Name seines Reiters „Verkaufen“ (AUCTION_HOUSE_SELL_TAB), sonst der eigene Text.
function Beside.SellTabName()
    local name = Core.Plain(AUCTION_HOUSE_SELL_TAB)
    if type(name) == "string" and name ~= "" then return name end
    return L.OPT_HEADER_SELL
end

-- Zusatz im Tooltip des Knopfs „Taschenliste“ (Frage 7 – Empfehlung umgesetzt, Antwort offen): Unten stehen neben
-- Auctionator zwei Reiter zum Verkaufen; dieser Knopf gehört zu Blizzards. nil ohne fremdes Addon.
function Beside.SellListLine()
    local other = Beside.Running()
    if not other then return nil end
    return L.SELL_LIST_BESIDE_TIP:format(other, Beside.SellTabName(), other)
end

-- In den Chat (Knopf auf der Einstellungsseite).
function Beside.Print()
    local lines = Beside.Lines()
    if #lines == 0 then return ns.Print(L.BESIDE_NONE) end
    for _, line in ipairs(lines) do ns.Print(line) end
end
