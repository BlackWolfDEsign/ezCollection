local _, ns = ...
local Core = ezCore

--[[
    Abschnitte „Anzahl bei Twinks“ und „Item-Wissen“ im Gegenstands-Tooltip – in ezCore (ST-05, entschieden in der
    Sammelrunde 13.11.2026). Vorher meldete nur ezBag sie an (ezBag/Inventory.lua: "ezBag.counts", "ezBag.knowledge");
    ohne ezBag fehlten sie, obwohl die Daten in ezCore liegen. Schalter auf ezCores Seite unter „Tooltip“
    (OPT_ttCounts, OPT_ttKnowledge). Solange ezBag dieselben Abschnitte noch selbst anmeldet, weichen ezCores Abschnitte
    (keine Zeile doppelt); ezBag stellt in seinem Paket um und verweist dann auf diese Schalter.

      ItemTooltip.CountsActive(), ItemTooltip.KnowledgeActive()   → zeigt ezCore den Abschnitt gerade selbst?
      ItemTooltip.AddCounts(tooltip, itemID), ItemTooltip.AddKnowledge(tooltip, itemID, data)
      ItemTooltip.KnowledgeLine(zeile) → Text einer Zeile von Knowledge.DescribeLines (mit Quelle in Grau)
      ItemTooltip.MigrateFromEzBag()   → ezBags Schalter tooltipCounts/itemInfo übernehmen: bei jedem Anmelden, solange
                                         ezBag seine Abschnitte noch selbst anmeldet (dann gilt sein Schalter), danach ein
                                         letztes Mal (migrated.ezBagTooltip)

    Eine Aussage je Zeile (FP-06): ezCore meldet bei Core.Tooltip.ClaimLine an, welche Aussagen das Item-Wissen zeigt –
    "level" (Tragbar/Benutzbar ab Stufe), "class" (Nicht für deine Klasse), "usable" (eins von beiden). ezGear lässt
    seine Begründungszeile weg, wenn Core.Tooltip.Shows(itemID, "level"|"class") wahr ist (in seinem Paket).
]]

local ItemTooltip = {}
Core.ItemTooltip = ItemTooltip
local L = Core.L

Core.OwnDefaults("tooltip", { counts = true, knowledge = true })

local function Enabled(key)
    return Core.OwnSetting("tooltip", key) ~= false
end

function ItemTooltip.CountsActive()
    return Enabled("counts") and not Core.Tooltip.HasSection("ezBag.counts")
end

function ItemTooltip.KnowledgeActive()
    return Enabled("knowledge") and not Core.Tooltip.HasSection("ezBag.knowledge")
end

-- Zeigt überhaupt ein Abschnitt das Item-Wissen (ezCores oder noch ezBags)? Für Knowledge.ShowsLine.
local K = Core.Knowledge
if K then
    function K.SectionActive()
        if Core.Tooltip.HasSection("ezBag.knowledge") then
            local bag = Core.Module and Core.Module("ezBag")
            local S = bag and bag.ns and bag.ns.S
            return not (type(S) == "table" and S.itemInfo == false)
        end
        return Enabled("knowledge")
    end
end

---------------------------------------------------------------------------
-- Anzahl bei Twinks
---------------------------------------------------------------------------

local PARTS = { { "bags", "TTC_BAGS" }, { "bank", "TTC_BANK" }, { "mail", "TTC_MAIL" }, { "equip", "TTC_EQUIPPED" } }

-- Töne aus dem Design-System (Core.Style, docs/design-system.md 2.5): „passt“ (ok) und die Gildenbank-Zeile (guild)
-- in Blizzards Grün, „passt nicht“ (warn) in Blizzards Rot. Empfehlung umgesetzt, Antwort offen – vorher eigene Töne;
-- zurück in dieser Zeile: ok = "|cff40ff40", warn = "|cffff5050", guild = "|cff40ff40" (ein Farbcode statt Rolle).
local TONE_ROLE = { ok = "good", warn = "bad", guild = "good" }

local function Tone(kind, text)
    local role = TONE_ROLE[kind]
    if type(role) ~= "string" then return nil end
    if role:find("^|c") then
        if Core.IsSecret(text) then return text end
        return role .. tostring(text) .. "|r"
    end
    return Core.Style.ColorText(role, text)
end

local function CharRow(tooltip, row)
    local parts, kinds = {}, 0
    for _, part in ipairs(PARTS) do
        local n = Core.Num(row[part[1]]) or 0
        if n > 0 then
            parts[#parts + 1] = L[part[2]] .. " " .. n
            kinds = kinds + 1
        end
    end
    local right = Core.WHITE .. tostring(row.total) .. "|r"
    -- Andere Charaktere nennen den Ort immer, auch wenn alles in den Taschen liegt (Wunsch des Nutzers vom 18.11.2026,
    -- W-1811-ezBag: „es muss auch angezeigt werden, wo die items liegen“); nur die eigene Taschen-Zeile bleibt kurz.
    if kinds > 1 or (Core.Num(row.bags) or 0) == 0 or (kinds > 0 and not row.isMe) then
        right = Core.GREY .. "(" .. table.concat(parts, ", ") .. ")|r  " .. right
    end
    tooltip:AddDoubleLine(Core.CharName(row.c, row.key, "-"), right)
end

function ItemTooltip.AddCounts(tooltip, itemID)
    local all = Core.Inventory and Core.Inventory.CountAll(itemID)
    if type(all) ~= "table" or (Core.Num(all.total) or 0) == 0 then return 0 end
    local chars, guilds = all.chars or {}, all.guilds or {}
    -- Nur in den Taschen dieses Charakters? Das zeigt Blizzards Tooltip schon selbst.
    if #guilds == 0 and #chars == 1 and chars[1].isMe and chars[1].total == chars[1].bags then return 0 end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): nie zwei Leerzeilen, keine oben
    local n = 0
    for _, row in ipairs(chars) do
        if row.isMe then CharRow(tooltip, row) n = n + 1 end
    end
    for _, row in ipairs(chars) do
        if not row.isMe then CharRow(tooltip, row) n = n + 1 end
    end
    for _, row in ipairs(guilds) do
        local name = type(row.g) == "table" and row.g.name or row.key
        tooltip:AddDoubleLine(Tone("guild", L.TTC_GUILD_BANK:format(tostring(name))), Core.WHITE .. row.total .. "|r")
        n = n + 1
    end
    if #chars + #guilds > 1 then
        local r, g, b = Core.Style.Color("normal")
        tooltip:AddDoubleLine(L.TTC_TOTAL, Core.WHITE .. all.total .. "|r", r, g, b)
    end
    return n
end

---------------------------------------------------------------------------
-- Item-Wissen (Beschriftung gold, Wert weiß; grün = passt jetzt, rot = passt nicht; Quelle grau)
---------------------------------------------------------------------------

-- Farben aus dem Design-System (Core.Style, docs/design-system.md): Beschriftung Blizzards Gold, Ton „passt“ bzw.
-- „passt nicht“ über TONE_ROLE oben (Blizzards Grün bzw. Rot), Quelle grau.
local LABEL_COLOR = Core.GOLD

function ItemTooltip.KnowledgeLine(e)
    if type(e) ~= "table" then return nil end
    local value = e.text and e.text ~= "" and ((e.tone ~= "guild" and Tone(e.tone, e.text))
        or (Core.WHITE .. e.text .. "|r")) or nil
    local from = K and K.SourceText and K.SourceText(e.source)
    if value and from then value = value .. " " .. Core.GREY .. "(" .. from .. ")|r" end
    if e.source == "none" and value then value = Core.GREY .. e.text .. "|r" end
    if e.label and e.label ~= "" then
        return LABEL_COLOR .. e.label .. (value and ":|r " or "|r") .. (value or "")
    end
    return value
end

function ItemTooltip.AddKnowledge(tooltip, itemID, data)
    if not (K and K.Get and K.DescribeLines) then return 0 end
    local link = Core.Tooltip.ItemLink(tooltip, data)
    local ok, facts = pcall(K.Get, link or itemID)
    if not ok or type(facts) ~= "table" then return 0 end
    local lines = K.DescribeLines(facts)
    if type(lines) ~= "table" or #lines == 0 then return 0 end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand)
    local n = 0
    for _, e in ipairs(lines) do
        local line = ItemTooltip.KnowledgeLine(e)
        if line then
            Core.TipLine(tooltip, line, "highlight", true)
            n = n + 1
        end
    end
    return n
end

Core.Tooltip.AddItemSection("ezCore.counts", "counts", function(tooltip, itemID)
    if ItemTooltip.CountsActive() then ItemTooltip.AddCounts(tooltip, itemID) end
end, Core.name)
Core.Tooltip.AddItemSection("ezCore.knowledge", "knowledge", function(tooltip, itemID, data)
    if ItemTooltip.KnowledgeActive() then ItemTooltip.AddKnowledge(tooltip, itemID, data) end
end, Core.name)

-- Eine Aussage je Zeile (FP-06)
if K and K.ShowsLine then
    Core.Tooltip.ClaimLine("level", Core.name, function(itemID, link) return K.ShowsLine(link or itemID, "wear") end)
    Core.Tooltip.ClaimLine("class", Core.name, function(itemID, link) return K.ShowsLine(link or itemID, "class") end)
    Core.Tooltip.ClaimLine("usable", Core.name, function(itemID, link)
        return K.ShowsLine(link or itemID, "wear") or K.ShowsLine(link or itemID, "class")
    end)
end

---------------------------------------------------------------------------
-- ezBags Schalter übernehmen; Kästchen auf der Seite „ezCollection“ unter „Tooltip“. Solange ezBag seine Abschnitte
-- selbst anmeldet, gilt sein Schalter (TTC_BAG_NOTE): bei jedem Anmelden beide Werte nachziehen (an und aus). Erst
-- wenn ezBag umgestellt hat, ein letztes Mal übernehmen und den Haken migrated.ezBagTooltip setzen – so geht keine
-- spätere Wahl in ezBag verloren (Fund der Gegenprüfung).
---------------------------------------------------------------------------

function ItemTooltip.MigrateFromEzBag()
    local db = Core.db
    if type(db) ~= "table" then return false end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    if db.migrated.ezBagTooltip then return false end
    local old = rawget(_G, "ezBagDB")
    if type(old) ~= "table" then return false end   -- ezBag (noch) nicht da: beim nächsten Anmelden wieder prüfen
    local S = type(old.settings) == "table" and old.settings or nil
    local own = Core.OwnSettings("tooltip")
    local changed = false
    if S and own then
        if S.tooltipCounts ~= nil and (own.counts ~= false) ~= (S.tooltipCounts ~= false) then
            own.counts, changed = S.tooltipCounts ~= false, true
        end
        if S.itemInfo ~= nil and (own.knowledge ~= false) ~= (S.itemInfo ~= false) then
            own.knowledge, changed = S.itemInfo ~= false, true
        end
    end
    local bagShows = Core.Tooltip.HasSection("ezBag.counts") or Core.Tooltip.HasSection("ezBag.knowledge")
    if not bagShows then db.migrated.ezBagTooltip = true end
    return changed
end

Core.Listen("CHARS_READY", function()
    local ok, err = pcall(ItemTooltip.MigrateFromEzBag)
    if not ok then Core.Error(Core.name, err, "ItemTooltip.MigrateFromEzBag") end
end, "ezCore.ItemTooltip")

function ItemTooltip.AddSettings(cat)
    if not (cat and Settings and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then return end
    local page = Core.ParentPage()
    if not page then return end
    local function Note()
        return (Core.Tooltip.HasSection("ezBag.counts") or Core.Tooltip.HasSection("ezBag.knowledge")) and L.TTC_BAG_NOTE or nil
    end
    page:OwnCheckbox("tooltip", "counts", { text = "ttCounts", variable = "ezCore_tt_counts", note = Note() })
    page:OwnCheckbox("tooltip", "knowledge", { text = "ttKnowledge", variable = "ezCore_tt_knowledge", note = Note() })
end
