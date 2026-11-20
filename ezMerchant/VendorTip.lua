local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Händler-Sortiment im Tooltip des Händlers (Vorschlag V3 aus docs/archiv/eroerterung-datenbank.md, vom Nutzer am
    16.11.2026 nach Empfehlung freigegeben). Fährt die Maus über einen Händler, den ein eigener Charakter schon
    besucht hat, steht unter Blizzards Zeilen, was dort für den gespielten Charakter wartet:
      - Rezepte für einen eigenen Beruf, die er noch nicht kann (Item-Wissen von ezCore: recipe.known, playerSkill),
      - Waren, die seiner Sammlung fehlen (Core.Collections.Missing; nicht, was nur eine andere Klasse sammelt) –
        dieselbe Regel wie der Stern im Händlerfenster,
      - Waren mit begrenztem Vorrat (Feld lim der Entdecker-Datenbank),
      - sonst „Nichts Neues für dich (n Waren)“ – dann spart man sich den Weg.
    Liegt eine Ware noch nicht im Item-Cache des Clients (kurz nach dem Login), weiß niemand, ob sie neu ist: sie zählt
    als „wird noch geladen“, statt die Zeile „Nichts Neues“ zu verfälschen; ohne Namen erscheint sie nicht als „#ID“.
    Eine solche Zusammenfassung gilt nur V.CACHE_PENDING Sekunden, und Knowledge.OnReady verwirft sie sofort.
    Quelle (Leitlinie 11): das Sortiment aus ezCores Datenbank (Core.Vendors.Of, Art vendor – „bei dir gesehen vor …“),
    die Zeile darunter nennt sie. Nur gelesen, nichts gespeichert. Waren, die beim letzten vollständigen Blick fehlten
    (gone), zählen nicht; was sich seither geändert hat, sieht ezCore erst beim nächsten Besuch.
    Grenzen: nie im Kampf (die GUID kann dann gesperrt sein; Core.DB.Keys.Npc liefert sie ohnehin nur ungesperrt),
    nur NPCs (keine Spieler, keine Begleiter), nur GameTooltip über ezCores Einheiten-Pipeline
    (Core.Tooltip.AddUnitSection). Rücksicht (Leitlinie 9): kein bekanntes Addon zeigt das Sortiment im Tooltip des
    Händlers; Questie ergänzt dort nur Quests – kein Konflikt. Schalter vendorTip (ab Werk an).
]]

local V = {}
ns.VendorTip = V

V.ORDER = 55            -- Einheiten-Tooltip: nach ezCores eingebauten Zeilen, vor ezLoots möglicher Beute (60)
V.MAX_NAMES = 3         -- so viele Waren mit begrenztem Vorrat beim Namen, danach „und n weitere“ (Core.More)
V.CACHE_SECONDS = 5     -- Blizzard frischt den Tooltip einer Einheit laufend auf; so lange gilt die Zusammenfassung
V.CACHE_PENDING = 1     -- so kurz gilt eine Zusammenfassung, in der noch Waren geladen werden

-- NPC-ID einer Einheit (nil bei Spielern, Begleitern, gesperrten Werten) – über ezCores Schlüssel der Datenbank.
function V.UnitNpc(unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local keys = Core.DB and Core.DB.Keys
    if not (type(keys) == "table" and type(keys.Npc) == "function") then return nil end
    local ok, npc = pcall(keys.Npc, unit)
    return ok and ns.Num(npc) or nil
end

-- Item-Wissen von ezCore: Tabelle; false, solange der Client die Ware noch nicht geladen hat (K.Get nil);
-- nil ohne Item-Wissen überhaupt.
local function Facts(itemID)
    local K = Core.Knowledge
    if not (K and type(K.Get) == "function") then return nil end
    local ok, f = pcall(K.Get, itemID)
    if ok and type(f) == "table" then return f end
    return false
end

-- Rezept für einen Beruf dieses Charakters, das er noch nicht kann? (Ohne Beruf oder ohne Daten: nein.)
function V.NewRecipe(itemID)
    local f = Facts(itemID)
    local r = f and f.recipe
    return type(r) == "table" and r.known ~= true and ns.Num(r.playerSkill) ~= nil or false
end

-- Fehlt die Ware der Sammlung dieses Charakters? Antwort von ezCore (wie der Stern im Händlerfenster).
function V.Missing(itemID)
    local C = Core.Collections
    if not (C and type(C.Missing) == "function") then return false end
    local ok, missing, otherClass = pcall(C.Missing, itemID)
    return ok and missing == true and otherClass ~= true or false
end

-- Name in der Spielsprache oder nil, solange der Client die Ware nicht kennt (ezCore fordert sie dann an).
local function ItemName(itemID)
    local name = Core.ItemNameByID and Core.ItemNameByID(itemID)
    return type(name) == "string" and name ~= "" and name or nil
end

--[[
    V.Summary(npcID) → nil (Händler nie besucht, ezCore ohne Datenbank) oder
      { goods = n, recipes = n, missing = n, pending = n, limited = { { id, name, lim } … nach Name }, seen = Zeitstempel }
    pending: Waren, die der Client noch nicht geladen hat (kein Item-Wissen oder, bei begrenztem Vorrat, kein Name).
]]
function V.Summary(npcID)
    npcID = ns.Num(npcID)
    local vendors = Core.Vendors
    if not (npcID and type(vendors) == "table" and type(vendors.Of) == "function") then return nil end
    local ok, row, info = pcall(vendors.Of, npcID)
    if not ok or type(row) ~= "table" or type(row.w) ~= "table" then return nil end
    local out = { goods = 0, recipes = 0, missing = 0, pending = 0, limited = {} }
    for itemID, w in pairs(row.w) do
        itemID = ns.Num(itemID)
        if itemID and type(w) == "table" and not w.gone then
            out.goods = out.goods + 1
            local loading = Facts(itemID) == false
            if not loading then
                if V.NewRecipe(itemID) then out.recipes = out.recipes + 1 end
                if V.Missing(itemID) then out.missing = out.missing + 1 end
            end
            if ns.Num(w.lim) then
                local name = ItemName(itemID)
                if name then out.limited[#out.limited + 1] = { id = itemID, name = name, lim = w.lim } else loading = true end
            end
            if loading then out.pending = out.pending + 1 end
        end
    end
    if out.goods == 0 then return nil end
    table.sort(out.limited, function(a, b) return a.name < b.name end)
    out.seen = type(info) == "table" and ns.Num(info.t) or ns.Num(row.tf)
    return out
end

-- Zeilen für den Tooltip: { { text, rolle } … } (Rolle für Core.Style.Color); leer ohne Zusammenfassung.
function V.Lines(sum)
    local lines = {}
    if type(sum) ~= "table" then return lines end
    if sum.recipes > 0 then
        lines[#lines + 1] = { L.VENDOR_TIP_RECIPES:format(Core.Plural(sum.recipes, L.VENDOR_RECIPES_ONE, L.VENDOR_RECIPES_MANY)), "good" }
    end
    if sum.missing > 0 then
        lines[#lines + 1] = { L.VENDOR_TIP_MISSING:format(Core.Plural(sum.missing, L.VENDOR_WARES_ONE, L.VENDOR_WARES_MANY)), "good" }
    end
    local limited = sum.limited
    if #limited > 0 then
        local names = {}
        -- Symbol der Ware vor dem Namen (ezCores Helfer Core.ItemIconText, Wunsch vom 18.11.2026 „mit den item icons“)
        for i = 1, math.min(#limited, V.MAX_NAMES) do
            local e = limited[i]
            names[i] = type(Core.ItemIconText) == "function" and Core.ItemIconText(e.id, e.name) or e.name
        end
        local text = table.concat(names, ", ")
        if #limited > V.MAX_NAMES then text = text .. " " .. Core.More(#limited - V.MAX_NAMES, true) end
        lines[#lines + 1] = { L.VENDOR_TIP_LIMITED:format(text), "normal" }
    end
    if (sum.pending or 0) > 0 then
        -- unvollständig: nie „Nichts Neues“ behaupten
        lines[#lines + 1] = { L.VENDOR_TIP_LOADING:format(Core.Plural(sum.pending, L.VENDOR_WARES_ONE, L.VENDOR_WARES_MANY)), "gray" }
    elseif #lines == 0 then
        lines[1] = { L.VENDOR_TIP_NOTHING:format(Core.Plural(sum.goods, L.VENDOR_WARES_ONE, L.VENDOR_WARES_MANY)), "gray" }
    end
    -- sum.seen stammt aus der Datenbank (Serveruhr, Core.DB.Stamp; T16-NZ1)
    lines[#lines + 1] = { L.VENDOR_TIP_SOURCE:format(Core.Ago(sum.seen, "server")), "gray" }
    return lines
end

-- Zusammenfassung je Händler für wenige Sekunden merken (der Tooltip einer Einheit wird laufend neu gefüllt).
local cache = {}
function V.Forget() cache = {} end

function V.Cached(npcID)
    local now = type(GetTime) == "function" and GetTime() or 0
    local c = cache[npcID]
    if c and now - c.at < c.ttl then return c.sum end
    local sum = V.Summary(npcID)
    local pending = type(sum) == "table" and sum.pending > 0
    cache[npcID] = { at = now, sum = sum, ttl = pending and V.CACHE_PENDING or V.CACHE_SECONDS, pending = pending }
    return sum
end

-- Eine Ware ist geladen: Zusammenfassungen mit noch ladenden Waren verwerfen (die vollständigen bleiben).
function V.ForgetPending()
    for npcID, c in pairs(cache) do
        if c.pending then cache[npcID] = nil end
    end
end

-- Abschnitt im Einheiten-Tooltip. → Anzahl der Zeilen
function V.AddSection(tooltip, unit)
    if not ns.Enabled("vendorTip") or ns.InCombat() then return 0 end
    local npc = V.UnitNpc(unit)
    if not npc then return 0 end
    local lines = V.Lines(V.Cached(npc))
    -- ezCores einer Trenner (S-1811-Tooltipabstand): Leerzeile vor dem Sortiment; läuft Questie, steht der Abschnitt
    -- hinter dessen Blöcken (ezCore setzt die Abschnitte dann ans Ende) und klebt so nicht an ihnen
    if #lines > 0 and type(Core.Tooltip) == "table" and type(Core.Tooltip.Gap) == "function" then Core.Tooltip.Gap(tooltip) end
    for _, line in ipairs(lines) do
        local r, g, b = Core.Style.Color(line[2])
        tooltip:AddLine(line[1], r, g, b, true)
    end
    return #lines
end

-- Neu gelernt oder neu gesammelt: nicht auf den Ablauf des Merkens warten.
ns.On("NEW_RECIPE_LEARNED", V.Forget)
ns.On("NEW_MOUNT_ADDED", V.Forget)
ns.On("NEW_PET_ADDED", V.Forget)
ns.On("NEW_TOY_ADDED", V.Forget)
ns.On("TRANSMOG_COLLECTION_UPDATED", V.Forget)
ns.On("MERCHANT_CLOSED", V.Forget)        -- nach dem Besuch gilt das frisch gelesene Sortiment
if type(Core.Knowledge) == "table" and type(Core.Knowledge.OnReady) == "function" then
    Core.Knowledge.OnReady(function() V.ForgetPending() end)
end

if type(Core.Tooltip) == "table" and type(Core.Tooltip.AddUnitSection) == "function" then
    Core.Tooltip.AddUnitSection("ezMerchant.vendor", V.ORDER, function(tooltip, unit) V.AddSection(tooltip, unit) end, ADDON)
end
