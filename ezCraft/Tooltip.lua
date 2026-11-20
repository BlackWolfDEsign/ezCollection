local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Rezept und Zutaten im Item-Tooltip (Wunsch des Nutzers 13.11.2026: „z. B. kleiner Heiltrank ist folgendes
    Rezept, mit folgenden Zutaten/Handwerkswaren“).

      Hergestellt   „Rezept (Alchemie): Kleiner Heiltrank“, je Zutat „1× Friedensblume“ mit dem Bestand
                    (grün: genug für einmal Herstellen, rot: zu wenig), dazu „Können: du, Mira“ – kann es keiner
                    deiner Charaktere, die Quelle; „Material ≈ …, n von m mit Preis“ mit Quelle (AH-32)
      Zutat         „Zutat für: Kleiner Heiltrank (1×), …“ – höchstens fünf, mit Shift alle. Ist es laut Item-Wissen
                    eine Handwerksware, aber noch kein Rezept gesehen, sagt die Zeile, woher die Daten kommen

    Daten in fester Reihenfolge (Regel „Datenquellen“ des Nutzers, 13.11.2026):
      1. Rezept-Wissen von ezCore (Knowledge.RecipeFor, RecipesUsing) – gesehen ist, was ein Twink im Berufefenster
         einmal geöffnet hat; Forever hat keine Rezept-Datenbank
      2. die Datenbank eines installierten Addons über ezCores Brücke Core.Sources – gekennzeichnet „laut AtlasLoot“
         (Wortlaut von Core.Sources.Label); „Zutat für“ über Core.Sources.RecipesUsing (CRAFT-07), beim Rezept die
         Fertigkeit laut Quelle oder „unbekannt“, wenn sie keine nennt (nie „0“; ezCores DG-50)
      3. nichts davon: Der Tooltip schweigt nicht, sondern sagt, warum („noch nicht gesehen – Berufefenster
         öffnen“) – bei Handwerkswaren und bei Gegenständen, die ihrer Art nach hergestellt werden (Trank, Tasche …)
    Bestand wie im Berufefenster
    (Data.Have: was als „vorhanden“ zählt, ist einstellbar). Die kurzen Zeilen des Item-Wissens („Rezepte (n): …“,
    „Hergestellt: Beruf“) lässt ezCore weg, solange ezCraft die langen zeigt (Knowledge.CoverLine, falls vorhanden).
]]

local Tip = {}
ns.Tooltip = Tip

local MAX_USES = 5
local ORDER = 27            -- nach dem Item-Wissen (20) und ezGear (25), vor der Einkaufsliste (30)
-- Farben der Zeilen sind Rollen (Core.Style.COLOR, dazu "hint" = Core.GREY), gezeichnet über ns.TipLines (Welle 23, A2)

local function Labeled(label, text)
    return Core.Gold(label .. ":") .. " " .. text
end

local function Line(out, left, right, color, rightColor)
    out[#out + 1] = { left = left, right = right, color = color or "highlight", rightColor = rightColor or "highlight" }
end

local function ReagentLines(out, recipe)
    for _, r in ipairs(recipe.reagents) do
        local have = Data.Have(Data.Stock(r.itemID))
        -- Symbol der Zutat vor ihrem Namen (ezCores Helfer, Wunsch vom 18.11.2026 „mit den item icons“)
        Line(out, "  " .. L.TIP_REAGENT:format(r.count, Core.ItemIconText(r.itemID, Data.ItemName(r.itemID))),
            L.TIP_HAVE:format(have),
            "highlight", have >= r.count and "good" or "bad")
    end
end

-- Materialsumme (AH-32): „Material ≈ 1 g 20 s, 3 von 4 mit Preis“ für einmal Herstellen, rechts die Quelle mit dem
-- Alter des ältesten Preises („laut deinen Erfassungen, ältester Preis: vor 2 Std.“). Hat keine Zutat einen Preis oder
-- ist einer der Schalter „Materialkosten“ (costs, der Hauptschalter aller Preise in ezCraft) oder „tooltipCost“ aus,
-- fehlt die Zeile. Annahme bis zur Spielprüfung W13-3 (docs/roadmap/ezCraft.md): Auctionator zeigt am Item-Tooltip
-- keine Materialsumme, deshalb gilt CRAFT-02 (weglassen neben Auctionator) hier noch nicht, nur für Kosten und Gewinn
-- am Rezept im Seitenteil. Zeigt W13-3 das Gegenteil, fällt die Zeile neben Auctionator ebenso weg.
local function SumLine(out, recipe)
    if not (ns.Enabled("costs") and ns.Enabled("tooltipCost") and Data.HasPrices()) then return end
    local rows = {}
    for _, r in ipairs(recipe.reagents or {}) do rows[#rows + 1] = { itemID = r.itemID, need = r.count } end
    local cost = Data.Cost(rows)
    if cost.priced == 0 then return end
    Line(out, "  " .. L.TIP_MATERIAL_SUM:format(Core.Money(cost.total), cost.priced, #rows), Data.CostSource(cost),
        "highlight", "hint")
end

-- Fertigkeit laut Datenbank (nur bei Rezepten, die keiner deiner Charaktere gesehen hat – sonst nennt das Seitenteil
-- die beobachteten Skill-Farben): die Schwellen so, wie die Quelle sie nennt, oder „unbekannt“, wenn sie keine nennt
-- (AtlasLoot führt bei Forever-Rezepten 0 – das heißt nie „ab 0“; ezCores DG-50). Sagt die Quelle gar nichts zur
-- Fertigkeit, bleibt die Zeile weg.
local function SkillLine(out, known)
    if type(known.skill) == "table" and #known.skill > 0 then
        local parts = {}
        for i, value in ipairs(known.skill) do parts[i] = tostring(value) end
        Line(out, "  " .. Labeled(L.TIP_SKILL, table.concat(parts, " / ")), nil, "highlight")
    elseif known.skillUnknown then
        Line(out, "  " .. Labeled(L.TIP_SKILL, Core.Grey(L.TIP_SKILL_UNKNOWN)), nil, "highlight")
    end
end

-- Kein Rezept gesehen und keine Datenbank weiß etwas: sagen, warum nichts dasteht – aber nur bei Gegenständen, die
-- ihrer Art nach hergestellt werden. Antwortet eine Datenbank (Brücke und Addon da) mit „nichts“, wird der
-- Gegenstand nicht hergestellt: dann keine Zeile. Den Zusatz „mit AtlasLoot auch ohne eigenen Beruf“ gibt es nur,
-- wenn ezCore die Brücke schon hat – ohne sie brächte das Installieren von AtlasLoot nichts.
-- Läuft die Datenbank, antwortet aber nicht wie erwartet (Quellenstatus „shape“ oder „error“), weiß niemand, ob der
-- Gegenstand hergestellt wird: Dann steht ezCores Satz dazu da („AtlasLoot antwortet nicht wie erwartet“) statt
-- eines leeren Tooltips (Regel „Datenquellen“: nie ein leerer Tooltip ohne Erklärung).
local function UnseenLine(out, itemID)
    if not Data.MaybeCrafted(itemID) then return end
    local loaded, label = Data.RecipeDatabase()
    local bridge = Data.HasSources()
    if loaded and bridge then
        local problem = Data.SourceProblem()
        if problem then Line(out, Labeled(L.TIP_RECIPE, Core.Grey(L.TIP_RECIPE_UNSEEN .. " (" .. problem .. ")"))) end
        return
    end
    local text = L.TIP_RECIPE_UNSEEN
    if bridge and not loaded then text = text .. " " .. L.TIP_RECIPE_UNSEEN_DB:format(label or "AtlasLoot") end
    Line(out, Labeled(L.TIP_RECIPE, Core.Grey(text)))
end

-- Wie der Gegenstand hergestellt wird: aus dem Rezept-Wissen, sonst laut Datenbank, sonst der Hinweis.
local function CraftedLines(out, itemID)
    local recipe = Data.RecipeForItem(itemID)
    if not recipe then
        local known = Data.SourceRecipeForItem(itemID)
        if not known then return UnseenLine(out, itemID) end
        -- „Rezept (Alchemie): Schwacher Heiltrank | laut AtlasLoot“
        local prof = known.professionLabel
        Line(out, Labeled(prof and L.TIP_RECIPE_PROF:format(prof) or L.TIP_RECIPE, known.name),
            known.sourceNote or Data.SourceNote(known), "highlight", "hint")
        ReagentLines(out, known)
        SumLine(out, known)
        SkillLine(out, known)
        -- Wer es kann, weiß nur das eigene Rezept-Wissen – gefragt über die Rezept-ID zum Zauber der Datenbank
        -- (CRAFT-12). Kann es keiner deiner Charaktere, bleibt die Zeile weg: die Quelle steht schon oben.
        local crafters = known.recipeID and Data.Crafters({ recipeID = known.recipeID })
        if crafters and #crafters > 0 then Line(out, Labeled(L.TIP_CRAFTERS, Data.CrafterNames(crafters))) end
        return
    end
    local prof = Data.ProfessionLabel(recipe.profession)
    -- Produkt laut AtlasLoot einem gesehenen Rezept ohne Produkt-ID zugeordnet (CRAFT-06): die Zeile nennt die Quelle
    local via = Data.ProductSourceText(recipe.productSource)
    Line(out, Labeled(prof and L.TIP_RECIPE_PROF:format(prof) or L.TIP_RECIPE, recipe.name), via, "highlight", "hint")
    ReagentLines(out, recipe)
    SumLine(out, recipe)
    local crafters = Data.Crafters(recipe)
    if crafters and #crafters > 0 then
        Line(out, Labeled(L.TIP_CRAFTERS, Data.CrafterNames(crafters)))
    else
        local source = Data.SourceFirstLine(Data.SourceText(recipe.recipeID))
        Line(out, Labeled(L.TIP_SOURCE, source or Core.Grey(L.TIP_NOBODY)))
    end
end

-- Wofür der Gegenstand Zutat ist (all: mit Shift alle, sonst höchstens fünf).
local function UsesLines(out, itemID, all)
    local list = Data.RecipesUsing(itemID)
    local note
    if #list == 0 then
        -- nichts gesehen: ezCores Brücke fragen (Core.Sources.RecipesUsing: eigene Datenbank, sonst AtlasLoot zur
        -- Laufzeit; CRAFT-07) – die Zeile nennt die Quelle in ezCores Wortlaut („laut AtlasLoot“)
        list = Data.SourceRecipesUsing(itemID)
        note = list[1] and (list[1].sourceNote or Data.SourceNote(list[1])) or list.pendingNote
    end
    -- Namen, die der Client noch lädt: statt „#<Produkt>“ nur ihre Zahl (beim nächsten Überfahren stehen sie da)
    local pending = type(list.pending) == "number" and list.pending or 0
    if #list == 0 and pending > 0 then
        local text = Core.Grey(L.TIP_USES_PENDING:format(pending))
        if note then text = text .. " " .. Core.Grey("(" .. note .. ")") end
        Line(out, Labeled(L.TIP_USED_FOR, text))
        return
    end
    if #list == 0 then
        if Data.IsTradeGood(itemID) then Line(out, Labeled(L.TIP_USED_FOR, Core.Grey(L.TIP_NO_RECIPE_SEEN))) end
        return
    end
    local shown = all and #list or math.min(#list, MAX_USES)
    local parts = {}
    for i = 1, shown do parts[i] = L.TIP_USE_PART:format(list[i].name, list[i].count) end
    local text = table.concat(parts, ", ")
    -- „A, B und 2 weitere (Shift: alle)“ – Core.More plus Zusatz (Welle 23; vorher eigener Text TIP_MORE)
    if shown < #list then text = text .. " " .. Core.Grey(Core.More(#list - shown, true) .. " " .. L.TIP_MORE_SHIFT) end
    if pending > 0 then text = text .. ", " .. Core.Grey(L.TIP_USES_PENDING:format(pending)) end
    if note then text = text .. " " .. Core.Grey("(" .. note .. ")") end
    Line(out, Labeled(L.TIP_USED_FOR, text))
end

-- Zeilen { left, right, color, rightColor } für einen Gegenstand (auch für die Tests).
function Tip.Lines(itemID, all)
    local out = {}
    if not itemID then return out end
    CraftedLines(out, itemID)
    UsesLines(out, itemID, all)
    return out
end

-- Tooltip des Schalters „Rezept und Zutaten im Tooltip“: Den Satz über AtlasLoot gibt es nur, wenn ezCore die
-- Brücke Core.Sources hat (sonst verspräche er Rezepte, die nicht kommen).
function Tip.OptionText()
    local text = L.OPT_tooltipRecipe_TIP
    if Data.HasSources() then text = text .. "\n\n" .. L.OPT_tooltipRecipe_SOURCES end
    return text
end

-- Zeichnet ezCraft für diesen Gegenstand die lange Fassung? kind: "crafted" (Rezept) oder "recipes" (Zutat für).
function Tip.Covers(kind, itemID)
    if not (ns.Enabled("tooltipRecipe") and itemID) then return false end
    if kind == "crafted" then return Data.RecipeIDForItem(itemID) ~= nil end
    if kind == "recipes" then return #Data.RecipesUsing(itemID) > 0 end
    return false
end

function Tip.Draw(tooltip, itemID)
    local lines = Tip.Lines(itemID, IsShiftKeyDown and IsShiftKeyDown() or false)
    if #lines == 0 then return 0 end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): keine doppelte Leerzeile
    ns.TipLines(tooltip, lines)
    return #lines
end

Core.Tooltip.AddItemSection("ezCraft.recipe", ORDER, function(tooltip, itemID)
    if ns.Enabled("tooltipRecipe") then Tip.Draw(tooltip, itemID) end
end, ADDON)

-- Kürschner-Liste (SAM-25): „Leder von: Wolf (Wald von Elwynn) 5×, … (bei dir)“ aus der eigenen Beute-Zählung (Art
-- „skin“, DG-03) – derselbe Text wie im Menü „Fundorte“ an der Kürschnerei im Berufsbuch. Direkt nach ezCores
-- Fundorten (Platz „gathering“), in deren Farbe; ohne gekürschnerte Beute keine Zeile. Schalter tooltipSkin.
Tip.SKIN_ORDER = 81
function Tip.SkinText(itemID)
    if not (itemID and ns.Enabled("tooltipSkin")) then return nil end
    local line = Data.SkinLine(itemID)
    if not line then return nil end
    return L.SKIN_LINE:format(line, Core.L.GATHER_SOURCE_OWN or Core.L.DB_OWN or "")
end

Core.Tooltip.AddItemSection("ezCraft.skin", Tip.SKIN_ORDER, function(tooltip, itemID)
    local text = Tip.SkinText(itemID)
    if not text then return end
    -- ezCores einer Trenner in der Gruppe der Fundorte (Core.Gathering.TOOLTIP_GROUP, Spielbefund 18.11.2026): direkt
    -- unter ezCores Fundorten keine Leerzeile, sonst eine (vorher klebte die Zeile ohne Fundorte an Blizzards Zeilen)
    local G = Core.Gathering
    Core.Tooltip.Gap(tooltip, type(G) == "table" and G.TOOLTIP_GROUP or "origin")
    ns.TipLine(tooltip, text, "good", true)
end, ADDON)

-- Nichts doppelt: die kurzen Zeilen des Item-Wissens entfallen, wo ezCraft die langen zeigt. Den Schalter baut
-- ezCore (Knowledge.CoverLine); fehlt er, bleibt es beim bisherigen Stand. Rückgabe: angemeldet?
function Tip.RegisterCover()
    local K = Core.Knowledge
    if not (K and type(K.CoverLine) == "function") then return false end
    for _, kind in ipairs({ "crafted", "recipes" }) do
        K.CoverLine(kind, ADDON, function(facts)
            return Tip.Covers(kind, type(facts) == "table" and facts.itemID or nil)
        end)
    end
    return true
end

Tip.RegisterCover()
