local ADDON, ns = ...
local Core = ezCore

--[[
    Tooltip:
      * Zeile „+12 % für Verstärkung“ (grün; schlechtere rot) über ezCores Tooltip-Pipeline, gleich unter dem
        Item-Wissen von ezBag (Reihenfolge 20 → ezGear 25). Gilt überall, wo Blizzard einen Gegenstands-Tooltip zeigt –
        Tasche, Händler, Questbelohnung, Beute, Rezept-Ergebnis. Bei Ausrüstung sagt die Zeile immer, wie es steht
        (Leitlinie 3): besser (mit dem grünen Pfeil wie am Platz), schlechter (rot), keine zählenden Werte, Werte
        werden gelesen – und wenn Pawn die Pfeile übernimmt, dass er es tut. „Nicht tragbar“ schreibt ezGear NICHT in
        den Tooltip: Blizzard zeigt dort schon rot die Rüstungsart (Spieltest 14.11.2026). Fehlt nur die Stufe, steht seit
        dem 24.11.2026 der Vergleich mit „– ab Stufe N“ da (Nutzer: „ezgear zeigt pfeil nicht mehr weil das lvl höher ist
        als meins? blöd“); nennt ezCores Item-Wissen im selben Tooltip schon „Tragbar ab Stufe: 40 …“, bleibt nur der
        Vergleich (ezGear fragt Core.Tooltip.Shows; GEAR-01: je Fall höchstens eine Zeile zur Tragbarkeit). Der Stand
        selbst (Score.Verdict, Score.Describe) bleibt für Pfeile, /ezg status und die Schnittstelle.
        Trägt der Knopf das Gold-Symbol, erklärt eine Zeile es; ebenso das Zeichen „Verzauberung fehlt“ an einem
        Platz des Charakterfensters (Character.lua).
        Mit gedrückter Umschalt-Taste steht unter der Vergleichszeile grau, woher die Gewichtung stammt
        (Regel „Datenquellen“: jede Angabe nennt ihre Quelle; Weights.Source – derselbe Text wie in /ezg status);
        nennt die Zeile einen Weg („erst … lernen“), steht darunter, woher Stufe, Lehrer und Ort stammen.
        Beim Drücken und Loslassen zeichnet der Tooltip neu (RefreshData, wie ezLoot) – auch das Fenster eines
        im Chat angeklickten Links (ItemRefTooltip).
        Darunter (Schalter tooltipEffect, 25.11.2026) „Für dich: Gesundheit −8,8 %, erlittener Nahkampfschaden −2,3 %“ – was der
        Tausch beim Spieler ausmacht, aus Werten des Clients; mit Umschalt auch, wie viel das Teil allein ausmacht.
      * Zeile „Für Twinks: ↑ Mira +18 %“ (Alts.lua, Schalter tooltipAlts; Nutzer am 24.11.2026): wem ein Gegenstand, den du
        weitergeben kannst, etwas bringt. Diese Namen fehlen dann in der Zeile „Twinks“ des Item-Wissens (wer ihn tragen
        kann). Laden die Daten seiner Ausrüstung noch, zeichnet der Tooltip neu, sobald sie da sind.
      * Rezept-Ergebnis im Berufefenster (Idee von Forever Tweaks, hier selbst gebaut): Blizzards Vergleichs-Tooltips mit der angelegten
        Ausrüstung erscheinen von selbst, ohne Umschalt-Taste. Blizzard setzt den Tooltip dort jedes Bild neu
        (SetRecipeResultItem im OnUpdate); ezGear zeigt den Vergleich nur einmal je Gegenstand.
]]

local Tip = {}
ns.Tooltip = Tip

local GREEN = { 0.1, 1, 0.1 }
local YELLOW = { 1, 0.82, 0 }    -- „besser, sobald gelernt“ bzw. „… sobald die Stufe reicht“ (Score.LATER), wie der gelbe Pfeil (Marks.LEARN_COLOR)
local RED = { 1, 0.35, 0.35 }
local GREY = { 0.65, 0.65, 0.65 }

-- Stände, die Blizzards Tooltip schon selbst rot nennt (Rüstungs- bzw. Waffenart, Klassen) – dazu schreibt ezGear keine
-- eigene Zeile.
local SAID_BY_BLIZZARD = { unusable = true }

-- Sagt Blizzards Tooltip diesen Stand schon?
function Tip.SaidByBlizzard(kind)
    return SAID_BY_BLIZZARD[kind] == true
end

-- Stand → Aussage, die ezCores Item-Wissen im selben Tooltip zeigen kann (Core.Tooltip.ClaimLine, FP-06):
-- "level" = „Tragbar ab Stufe“, "class" = „Nicht für deine Klasse“.
local SAID_BY_KNOWLEDGE = { level = "level", unusable = "class" }

-- Sagt das Item-Wissen diesen Stand im selben Tooltip schon (GEAR-01)? Nennt es die Stufe („Tragbar ab Stufe: 40 (Kette
-- erst ab Stufe 40)“), spricht ezGear nur über den Vergleich (Empfehlung „das Item-Wissen behält die Aussage“). Ohne
-- Item-Wissen-Zeile (Abschnitt aus, Schalter aus, ezCore ohne Core.Tooltip.Shows) → false, dann bleibt ezGears Zusatz.
function Tip.SaidByKnowledge(kind, link)
    local what = SAID_BY_KNOWLEDGE[kind]
    local tooltip = Core.Tooltip
    if not what or type(link) ~= "string" or not (tooltip and type(tooltip.Shows) == "function") then return false end
    local ok, shows = pcall(tooltip.Shows, Core.ItemID(link), what, link)
    return ok and shows == true
end

-- Tip.Line(link) → Text, Farbe, Stand (Score.Verdict), info oder nil (kein Ausrüstungsgegenstand, angelegt, oder
-- Blizzard bzw. das Item-Wissen sagt es schon)
function Tip.Line(link)
    local info = ns.Score.Compare(link)
    local text, _, kind = ns.Score.Describe(info)
    if not text or Tip.SaidByBlizzard(kind) then return nil end
    -- Die Stufe fehlt noch (Mindeststufe des Gegenstands, Platte ab 40): Nennt das Item-Wissen im selben Tooltip
    -- „Tragbar ab Stufe: 40 …“, bleibt der Vergleich ohne die Stufe (GEAR-01: je Fall höchstens eine Zeile zur
    -- Tragbarkeit); was beim Waffenmeister zu lernen ist, steht weiter da
    if info and (info.usableFrom or ns.Score.LearnByLevel(info)) and Tip.SaidByKnowledge("level", link) then
        text = ns.Score.Describe(info, true)
    end
    -- „−8 %“ steht immer (Einstellungs-Prüfung 19.11.2026, Nr. 42): sonst wüsste man nicht, ob das Teil schlechter
    -- ist oder gar nicht bewertet wurde
    local color = GREY
    if kind == "better" then
        color = GREEN
        text = ns.Marks.ArrowIcon() .. " " .. text   -- derselbe Pfeil wie am Platz
    elseif ns.Score.LATER[kind] then
        -- „+18 % für Schaden – erst Schwerter lernen (Waffenmeister)“, „+12 % für Schaden – ab Stufe 24“, mit dem
        -- gelben Pfeil wie am Platz
        color = YELLOW
        text = ns.Marks.LearnIcon() .. " " .. text
    elseif kind == "worse" then
        color = RED
    end
    return text, color, kind, info
end

-- Stände, deren Aussage aus der Gewichtung kommt – nur dort nennt die Umschalt-Zeile deren Quelle.
local WEIGHTED = { better = true, learn = true, level = true, worse = true, same = true, nostats = true, armor = true }

-- Tip.SourceLine(kind) → „Quelle der Gewichtung: …“ (Weights.Source) – nur mit gedrückter Umschalt-Taste und nur
-- bei einem Stand, der aus der Gewichtung kommt; sonst nil
function Tip.SourceLine(kind)
    if not WEIGHTED[kind] then return nil end
    if ns.Plain(ns.Call(IsShiftKeyDown)) ~= true then return nil end
    local _, text = ns.Weights.Source()
    return text
end

-- Tip.WaySourceLine(link) → woher der Weg „erst … lernen“ stammt (Leitlinie 11) – nur mit gedrückter Umschalt-Taste
-- und nur, wenn der Vergleich einen Weg nennt: Stufe laut Client-Tabellen, Lehrer und Ort aus deinem Lehrerfenster
-- (Entdecker-Datenbank), aus Beiträgen anderer Spieler (way.shared, seit 25.11.2026) oder nach der Classic-Regel (Waffen beim Waffenmeister, Rüstung beim Klassenlehrer); sonst nil
function Tip.WaySourceLine(link)
    if ns.Plain(ns.Call(IsShiftKeyDown)) ~= true then return nil end
    local info = ns.Score.Compare(link)
    local way = info and info.learn
    if type(way) ~= "table" then return nil end
    if type(way.shared) == "string" then
        -- selbst gesehen, nur der Ort aus Beiträgen | Lehrer und Ort aus Beiträgen | nur der Lehrer (Ort unbekannt)
        local text = way.seen and ns.L.TIP_WAY_SOURCE_SHIP_PLACE
            or way.place and ns.L.TIP_WAY_SOURCE_SHIP or ns.L.TIP_WAY_SOURCE_SHIP_NOPLACE
        return text:format(way.shared)
    end
    if way.seen then return ns.L.TIP_WAY_SOURCE_SEEN end
    if way.trainer then return ns.L.TIP_WAY_SOURCE_RULE end
    return ns.L.TIP_WAY_SOURCE
end

-- Waffe zur Spielweise (Paket ezgear/talent-empfehlung; Weights.WeaponFit): grün „passt“, orange „nutzt …“ – nur mit
-- ezTalents Werten unter „Automatisch“. → Text, Farbe | nil
local ORANGE = { 1, 0.6, 0.2 }
function Tip.WeaponLine(link)
    local fit, want, name, shield = ns.Weights.WeaponFit(link)
    if not fit then return nil end
    name = tostring(name or ns.L.WEIGHTS_TALENT_NAME)
    if fit == "match" then return (shield and ns.L.TIP_SHIELD_MATCH or ns.L.TIP_WEAPON_MATCH):format(name), GREEN end
    return ns.L.TIP_WEAPON_OTHER:format(name, tostring(want)), ORANGE
end

-- Wem der Gegenstand etwas bringt (Alts.lua) → Zeile oder nil, laden noch Daten?
function Tip.AltsLine(link, data)
    local hits, pending = ns.Alts.For(link, ns.Stats.Facts(link), data)
    return hits and ns.Alts.Text(hits), pending
end

-- Hinweis, wenn ein fremdes Addon (Pawn) Pfeile oder Vergleich übernimmt – sonst wüsste niemand, warum sie fehlen.
function Tip.HeldLines(link)
    local lines = {}
    local tipBy = ns.HeldBackBy("tooltip")     -- die Zeile ist fest (Nr. 41), nur Pawn hält sie zurück
    local arrowsBy = ns.Enabled("bagArrows") and ns.HeldBackBy("bagArrows")
    if not (tipBy or arrowsBy) or not ns.Score.Compare(link) then return lines end
    if tipBy then
        lines[#lines + 1] = ns.L.TIP_HELD_COMPARE:format(tipBy)
    elseif arrowsBy then
        lines[#lines + 1] = ns.L.TIP_HELD_ARROWS:format(arrowsBy)
    end
    return lines
end

-- Zeile zum Gold-Symbol, wenn der Knopf unter dem Tooltip es trägt (Questbelohnung, Knöpfe anderer Module)
function Tip.ValueLine(tooltip)
    local owner = tooltip and tooltip.GetOwner and ns.Call(tooltip.GetOwner, tooltip)
    if type(owner) ~= "table" or not ns.Marks.ValueShown(owner) then return nil end
    return ns.Marks.CoinIcon() .. " " .. ns.L.TIP_VALUE
end

-- Zeile zum Zeichen „Verzauberung fehlt“, wenn der Platz-Knopf unter dem Tooltip es trägt (Charakterfenster)
function Tip.EnchantLine(tooltip)
    local owner = tooltip and tooltip.GetOwner and ns.Call(tooltip.GetOwner, tooltip)
    local char = ns.Character
    if type(owner) ~= "table" or not (char and char.EnchantShown and char.EnchantShown(owner)) then return nil end
    return ns.L.TIP_ENCHANT_MISSING
end

-- Zeigt ein Tooltip gerade eine Vergleichszeile aus der Gewichtung? Dann zeichnet ein Wechsel der Umschalt-Taste
-- ihn neu (Tip.OnModifier). Je Tooltip gemerkt – der Abschnitt läuft für GameTooltip und für ItemRefTooltip (das
-- Fenster eines im Chat angeklickten Links; dort ließe sich die Quelle sonst nie einblenden, weil ein Umschalt-Klick
-- auf einen Link ihn einfügt statt das Fenster zu öffnen). Geleert, sobald der Tooltip geleert oder versteckt wird.
local weightedShown = {}     -- [Tooltip] = true
local watched = {}           -- [Tooltip] = true: OnHide und OnTooltipCleared sind angehängt
local altsOpen = {}          -- [Tooltip] = true: Daten für die Zeile „Für Twinks“ laden noch

local function Forget(tooltip) weightedShown[tooltip], altsOpen[tooltip] = nil, nil end

-- Einmal je Tooltip: leeren, wenn er versteckt wird oder etwas anderes zeigt (Einheit, Zauber – dann läuft der
-- Abschnitt unten nicht). Nur HookScript (Leitlinie 5); kennt der Tooltip ein Skript nicht, bleibt das folgenlos.
local function Watch(tooltip)
    if watched[tooltip] then return end
    watched[tooltip] = true
    if type(tooltip.HookScript) ~= "function" then return end
    pcall(tooltip.HookScript, tooltip, "OnHide", Forget)
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Forget)
end

Core.Tooltip.AddItemSection("ezGear.upgrade", 25, function(tooltip, _, data)
    weightedShown[tooltip], altsOpen[tooltip] = nil, nil
    local link = Core.Tooltip.ItemLink(tooltip, data)
    if not link then return end
    -- Abstand (Spielbefund 18.11.2026 „auch hier fehlender abstand“, S-1811-Tooltipabstand): erst sammeln, dann vor
    -- der ersten Zeile ezCores einer Trenner (Core.Tooltip.Gap) – eine Leerzeile, nur wenn der Abschnitt schreibt
    local out = {}
    local function Add(text, rgb, wrap) out[#out + 1] = { text, rgb, wrap } end
    if ns.Active("tooltip") then
        local text, color, kind, info = Tip.Line(link)
        if text then
            -- mit dem Gegenstück bzw. der Rüstungsart wird die Zeile lang: umbrechen
            Add(text, color, info and (info.mateHand ~= nil or info.armorRule ~= nil))
            -- schlechter, obwohl ein gezählter Wert steigt: was dafür und was dagegen spricht (Nutzer am 24.11.2026 zum
            -- Schurken mit Bogen: „stimmt die ezgear aussage“)
            local trade = (kind == "worse" or kind == "armor") and ns.Score.TradeText(link, info)
            if trade then Add(trade, GREY, true) end
            local effect = WEIGHTED[kind] and ns.Enabled("tooltipEffect") and ns.Score.EffectText(link, info)
            if effect then Add(effect, GREY, true) end
            if WEIGHTED[kind] then
                Watch(tooltip)
                weightedShown[tooltip] = true
                local source = Tip.SourceLine(kind)
                local part = source and ns.Score.PartText(info)
                if part then Add(part, GREY, true) end
                if source then Add(source, GREY, true) end
                local way = Tip.WaySourceLine(link)
                if way then Add(way, GREY, true) end
            end
        end
    end
    if ns.Active("tooltip") then
        local weapon, rgb = Tip.WeaponLine(link)
        if weapon then Add(weapon, rgb, true) end
    end
    local alts, altsPending = Tip.AltsLine(link, data)
    if alts then
        Add(alts, GREY, true)
        if ns.Plain(ns.Call(IsShiftKeyDown)) == true then Add(ns.L.TIP_ALTS_SOURCE, GREY, true) end
    end
    if alts or altsPending then
        Watch(tooltip)
        weightedShown[tooltip] = true
        altsOpen[tooltip] = altsPending or nil
    end
    for _, line in ipairs(Tip.HeldLines(link)) do Add(line, GREY) end
    local value = Tip.ValueLine(tooltip)
    if value then Add(value, { 1, 0.82, 0 }) end
    local enchant = Tip.EnchantLine(tooltip)
    if enchant then Add(enchant, RED, true) end
    if #out == 0 then return end
    if Core.Tooltip.Gap then Core.Tooltip.Gap(tooltip) end
    for _, line in ipairs(out) do
        local rgb = line[2]
        if line[3] then tooltip:AddLine(line[1], rgb[1], rgb[2], rgb[3], true) else tooltip:AddLine(line[1], rgb[1], rgb[2], rgb[3]) end
    end
end, ADDON)

-- Einen Tooltip neu zeichnen, wenn er gerade eine Vergleichszeile aus der Gewichtung zeigt → true, wenn gezeichnet
local function Redraw(tooltip)
    if type(tooltip) ~= "table" or not weightedShown[tooltip] then return false end
    if not (tooltip.IsShown and tooltip:IsShown()) then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    if type(tooltip.RefreshData) ~= "function" then return false end
    return pcall(tooltip.RefreshData, tooltip) == true
end

-- Daten sind nachgeladen: Tooltips, deren Zeile „Für Twinks“ noch darauf wartete
function Tip.OnScores()
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if altsOpen[tooltip] then Redraw(tooltip) end
    end
end

-- Umschalt gedrückt oder losgelassen: die Tooltips neu zeichnen, die gerade eine Vergleichszeile aus der
-- Gewichtung zeigen (GameTooltip und das Link-Fenster ItemRefTooltip) – die Zeile zur Quelle erscheint bzw.
-- verschwindet sofort. → true, wenn mindestens einer neu gezeichnet wurde
function Tip.OnModifier(key)
    key = ns.Plain(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return false end
    if not (ns.Active("tooltip") or ns.Enabled("tooltipAlts")) then return false end
    local main = Redraw(GameTooltip)
    local ref = Redraw(ItemRefTooltip)
    return main or ref
end

---------------------------------------------------------------------------
-- Rezept-Ergebnis: Vergleich mit der angelegten Ausrüstung
---------------------------------------------------------------------------

local lastRecipeLink

local function Equippable(link)
    local fn = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
    local result = ns.Plain(ns.Call(fn, link))
    if result ~= nil then return result == true end
    return ns.Stats.EquipLoc(link) ~= nil
end

function Tip.OnRecipeResult(tooltip)
    if not ns.Enabled("recipeCompare") or tooltip ~= GameTooltip then return end
    if IsModifiedClick and IsModifiedClick("COMPAREITEMS") then return end   -- das macht Blizzard dann selbst
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local _, link = ns.Call(tooltip.GetItem, tooltip)
    link = ns.Plain(link)
    if type(link) ~= "string" or not Equippable(link) then return end
    local shopping = ShoppingTooltip1
    if link == lastRecipeLink and shopping and shopping.IsShown and shopping:IsShown() then return end
    lastRecipeLink = link
    if type(GameTooltip_ShowCompareItem) == "function" then
        ns.Call(GameTooltip_ShowCompareItem, tooltip)
    end
end

ns.OnReady(function()
    if GameTooltip and type(GameTooltip.SetRecipeResultItem) == "function" then
        hooksecurefunc(GameTooltip, "SetRecipeResultItem", function(self) ns.Try("RecipeCompare", Tip.OnRecipeResult, self) end)
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnHide", function() lastRecipeLink = nil end)
        Watch(GameTooltip)
    end
    ns.On("MODIFIER_STATE_CHANGED", function(_, key) ns.Try("TooltipShift", Tip.OnModifier, key) end)
    ns.Listen("SCORES_CHANGED", function() ns.Try("TooltipAlts", Tip.OnScores) end)
end)
