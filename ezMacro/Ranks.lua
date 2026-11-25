local _, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

-- Ränge aktualisieren (wie MaxRank, Rank Watch): Auf WoW Forever bringen Lehrer neue Ränge bei, aber Aktionsplätze,
-- Makros mit „(Rang n)“ und Klick-Zauber wirken weiter mit dem alten Rang. ezMacro ersetzt sie durch den höchsten
-- gelernten Rang – per Knopf im Zauberbuch und im Reiter „Werkzeuge“, auf Wunsch automatisch nach dem Lernen.
-- Ausnahmen für bewusstes Downranking („Rang behalten“) gelten je Charakter und Stelle (ezMacroDB.rankKeep).
-- Was ein Rang ist und welcher der höchste gelernte, weiß ezCores Zauber-Wissen (ezCore.Spells).
-- Taint: PlaceAction, EditMacro und Klick-Zauber nur außerhalb des Kampfes, sonst danach (PLAYER_REGEN_ENABLED).
-- Blizzards Klick-Zauber liest und schreibt ezCore (Core.ClickBindings, eine Stelle für ezMacro und ezHeal); läuft
-- ezHeal, tauscht ezHeal die Ränge dort (Ranks.SwapClicks, ezCore.API("ezHeal").ReplaceSpells).
local Ranks = {}
ns.Ranks = Ranks

local Spells = Core.Spells
local UPDATE_KEY = "ranks.update"   -- im Kampf angefordert: nach dem Kampf aktualisieren (ns.AfterCombat)
local lastCount = 0          -- für den Hinweis „neue Ränge“ (nur, wenn es mehr werden)

-- Rücksicht auf Addons, die dasselbe tun (docs/fremd-addons.md): Läuft eines, aktualisiert ezMacro nur auf
-- Knopfdruck und meldet neue Ränge nicht selbst. Welche das sind (MaxRank, Rank Watch, Nova Spell Rank
-- Checker), weiß ezCore (OtherAddOns.lua, Funktion „spellRanks“). Rückgabe: Anzeigename oder nil.
function Ranks.Other()
    return (ns.OtherFor("spellRanks"))
end

function Ranks.Available()
    return type(Spells) == "table" and type(Spells.Highest) == "function" and type(Spells.Rank) == "function"
        and type(Spells.ParseRank) == "function"
end

local function Keep()
    local all = ns.db.rankKeep
    local mine = all[ns.charKey]
    if type(mine) ~= "table" then
        mine = {}
        all[ns.charKey] = mine
    end
    return mine
end

-- Höherer gelernter Rang zu einer ID: neueID, neuerRang, alterRang – sonst nil.
local function Better(id)
    local rank = Spells.Rank(id)
    if not rank or rank <= 0 then return nil end
    local best, bestRank = Spells.Highest(id)
    if best and best ~= id and bestRank and bestRank > rank then return best, bestRank, rank end
    return nil
end

---------------------------------------------------------------------------
-- Makrotext: „Heilung(Rang 2)“ → „Heilung(Rang 4)“
---------------------------------------------------------------------------

-- Zaubername vor der Klammer ohne Befehl, Optionen und Ausrufezeichen („/castsequence reset=3 !Name“ → „Name“,
-- „#showtooltip Name“ → „Name“).
local function SpellNameIn(before)
    local name = before:gsub("^%s*[/#]%S+", ""):gsub("^%s*reset=%S+", ""):gsub("^%s*!", "")
    return Core.Trim(name)
end

-- Liefert den neuen Text und die Änderungen { { name, old, new }, … }. Unbekannte Zauber bleiben, wie sie sind.
function Ranks.UpgradeText(text)
    local changes = {}
    local result = tostring(text or ""):gsub("([^%[%];,\n]-)%(([^%(%)\n]-%d+[^%(%)\n]-)%)", function(before, rankText)
        local rank = Spells.ParseRank(rankText)
        local name = SpellNameIn(before)
        if not rank or name == "" then return nil end
        local best, bestRank = Spells.Highest(name)
        if not best or not bestRank or bestRank <= rank then return nil end
        changes[#changes + 1] = { name = name, old = rank, new = bestRank }
        return before .. "(" .. rankText:gsub("%d+", tostring(bestRank), 1) .. ")"
    end)
    return result, changes
end

---------------------------------------------------------------------------
-- Suchen: Aktionsplätze, Makros, Klick-Zauber
---------------------------------------------------------------------------

-- Blizzards Klick-Zauber über ezCore (Core.ClickBindings): Einträge { kind, id, button, modifiers … }. Ohne den
-- Dienst (älteres ezCore) oder ohne Klick-Zauber im Client: nil – dann gibt es dort nichts zu aktualisieren.
local function ClickBindings()
    local CB = Core.ClickBindings
    if type(CB) == "table" and type(CB.List) == "function" then return CB end
    return nil
end

local function ClickList()
    local CB = ClickBindings()
    local list = CB and CB.List()
    return type(list) == "table" and list or nil
end

-- Wartet noch ein Wunsch an Blizzards Klick-Zauber (im Kampf über Core.ClickBindings gestellt, etwa von ezHeal),
-- zuerst ihn schreiben: Set ersetzt einen wartenden Wunsch (dessen onDone: false, "replaced"), und „Ränge
-- aktualisieren“ kann nach dem Kampf vor ezCores eigenem Nachholen dran sein. Danach liest der Lauf Blizzards neue
-- Belegung und tauscht nur noch die IDs darin.
local function FlushClicks()
    local CB = ClickBindings()
    if CB and type(CB.Pending) == "function" and type(CB.Flush) == "function" and CB.Pending() then CB.Flush() end
end

-- Ein Suchlauf je Ranks.Changed (V-097): Solange Changed läuft, bedienen sich Knopf, Leuchten und Werkzeug aus
-- demselben Ergebnis statt jeder für sich alle Plätze, Makros und Klick-Zauber neu zu lesen.
local scanCache          -- volle Liste (mit „Rang behalten“) oder nil
local scanRuns = 0       -- Zahl der vollen Suchläufe (für die Prüfung)

function Ranks.ScanRuns() return scanRuns end

-- Plätze, die ezBars-Leisten zeigen: { [Platz] = Leistennummer } aus ezCore.API("ezBars").UsedSlots (BARS-07,
-- MACRO-36). Ohne ezBars oder bei einem Fehler dort: leer – die Plätze zählen dann wie jeder andere Platz.
function Ranks.BarSlots()
    local api = Core.API and Core.API("ezBars")
    local fn = type(api) == "table" and api.UsedSlots
    if type(fn) ~= "function" then return {} end
    local ok, used = pcall(fn)
    return ok and type(used) == "table" and used or {}
end

-- Aktionsplätze, auf denen ein Makro liegt (MACRO-36): Blizzard nennt für einen Makro-Platz den Makronamen
-- (ActionSlots.Text, über Core.ActionSlots.Info); zeigt das Makro keinen Zauber, ist die ID der Index des Makros.
-- → { [Makroname] = { Platz, … } }, { [Index] = { Platz, … } } (Plätze ohne Namen),
--   { [Makroname] = { [Index] = { Platz, … } } } (Plätze mit Namen und Index, für gleichnamige Makros)
local function MacroSlots()
    local byName, byIndex, byNameIndex = {}, {}, {}
    local function Add(map, key, slot)
        map[key] = map[key] or {}
        table.insert(map[key], slot)
    end
    for _, slot in ipairs(Core.ActionSlots.USABLE) do
        local info = Core.ActionSlots.Info(slot)
        if info and info.kind == "macro" then
            local index = info.subType ~= "spell" and type(info.id) == "number" and info.id or nil
            if info.text then
                Add(byName, info.text, slot)
                if index then
                    byNameIndex[info.text] = byNameIndex[info.text] or {}
                    Add(byNameIndex[info.text], index, slot)
                end
            elseif index then
                Add(byIndex, index, slot)
            end
        end
    end
    return byName, byIndex, byNameIndex
end

-- Namen, die es als Konto- und als Charaktermakro gibt: Dort sagt der Name nicht, welches der beiden auf dem
-- Platz liegt. Es zählt nur der Index; zeigt das Makro einen Zauber (kein Index), leuchtet lieber nichts als
-- der falsche Knopf.
local function SharedNames(macros)
    local seen, shared = {}, {}
    for _, macro in ipairs(macros) do
        local scope = macro.perChar and "c" or "a"
        if seen[macro.name] and seen[macro.name] ~= scope then shared[macro.name] = true end
        seen[macro.name] = seen[macro.name] or scope
    end
    return shared
end

-- Veraltete Stellen: { key, kind = "slot"|"macro"|"click", name, old, new, kept, … }.
-- Plätze tragen bar (Nummer der ezBars-Leiste oder nil), Makros slots = { Platz, … } (wo sie auf einer Leiste liegen).
-- includeKept: auch die mit „Rang behalten“ (für die Liste im Werkzeug).
function Ranks.Scan(includeKept)
    local list = {}
    if not (Ranks.Available() and ns.db) then return list end
    if scanCache then
        for _, item in ipairs(scanCache) do
            if includeKept or not item.kept then list[#list + 1] = item end
        end
        return list
    end
    scanRuns = scanRuns + 1
    local keep = Keep()
    local barSlots = Ranks.BarSlots()

    -- Plätze über ezCore (ActionSlots): nur Zauber direkt auf dem Platz. Ein Makro, das einen Zauber zeigt,
    -- bleibt ein Makro – sein Text wird unten aktualisiert („(Rang n)“), nie der Platz überschrieben.
    for _, slot in ipairs(Core.ActionSlots.USABLE) do
        local info = Core.ActionSlots.Info(slot)
        local id = info and info.kind == "spell" and info.id
        if type(id) == "number" then
            local best, bestRank, rank = Better(id)
            if best then
                local key = "slot:" .. slot
                local kept = keep[key] == id
                if includeKept or not kept then
                    list[#list + 1] = { key = key, kind = "slot", slot = slot, id = id, newID = best,
                        name = ns.SpellName(id), old = rank, new = bestRank, kept = kept,
                        icon = ns.SpellIcon(best), bar = barSlots[slot] }
                end
            end
        end
    end

    local slotsByName, slotsByIndex, slotsByNameIndex
    local macros = ns.Macros.All()
    local shared = SharedNames(macros)
    for _, macro in ipairs(macros) do
        local body = ns.Import.BodyOf(macro.index) or macro.body
        local newBody, changes = Ranks.UpgradeText(body)
        if #changes > 0 then
            local key = "macro:" .. (macro.perChar and "c:" or "a:") .. macro.name
            local kept = keep[key] == true
            if includeKept or not kept then
                if not slotsByName then slotsByName, slotsByIndex, slotsByNameIndex = MacroSlots() end
                local slots
                if shared[macro.name] then
                    slots = (slotsByNameIndex[macro.name] or {})[macro.index] or slotsByIndex[macro.index] or {}
                else
                    slots = slotsByName[macro.name] or slotsByIndex[macro.index] or {}
                end
                local bars = 0
                for _, slot in ipairs(slots) do if barSlots[slot] then bars = bars + 1 end end
                list[#list + 1] = { key = key, kind = "macro", macro = macro.name, perChar = macro.perChar,
                    newBody = newBody, changes = changes, name = changes[1].name, old = changes[1].old,
                    new = changes[1].new, kept = kept, icon = macro.icon, slots = slots, barCount = bars }
            end
        end
    end

    -- Klick-Zauber: der Schlüssel „click:<Taste>:<Umschalttasten>“ bleibt wie vorher (gespeichertes „Rang behalten“);
    -- gemerkt werden Taste und Umschalttasten statt der Stelle in der Liste
    for _, entry in ipairs(ClickList() or {}) do
        if entry.kind == "spell" and type(entry.id) == "number" then
            local best, bestRank, rank = Better(entry.id)
            if best then
                local modifiers = entry.modifiers or 0
                local key = "click:" .. tostring(entry.button) .. ":" .. tostring(modifiers)
                local kept = keep[key] == entry.id
                if includeKept or not kept then
                    list[#list + 1] = { key = key, kind = "click", button = entry.button, modifiers = modifiers,
                        id = entry.id, newID = best, name = ns.SpellName(entry.id), old = rank, new = bestRank,
                        kept = kept, icon = ns.SpellIcon(best) }
                end
            end
        end
    end
    return list
end

function Ranks.Count()
    return #Ranks.Scan()
end

---------------------------------------------------------------------------
-- Ausnahmen
---------------------------------------------------------------------------

-- „Rang behalten“ an dieser Stelle (bewusstes Downranking) bzw. wieder aufheben.
function Ranks.SetKept(item, kept)
    local keep = Keep()
    if not kept then
        keep[item.key] = nil
    elseif item.kind == "macro" then
        keep[item.key] = true
    else
        keep[item.key] = item.id   -- gilt, solange dort dieser Rang liegt
    end
    Ranks.Changed()
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

-- Ein Besitzer der Klick-Belegung (Paket ezmacro/rangtausch-ezheal; Entscheidung des Nutzers vom 13.11.2026: „ezHeal
-- bleibt die Klick-Schicht“): Läuft ezHeal, tauscht ezHeal die Ränge (ezCore.API("ezHeal").ReplaceSpells) – seine
-- Merkliste und sein „Zurück“ wissen dann davon. Nur ohne ezHeal (oder mit einem ezHeal ohne ReplaceSpells) schreibt
-- ezMacro wie bisher selbst über ezCore. → Schnittstelle von ezHeal | nil
function Ranks.ClickOwner()
    local api = Core.API and Core.API("ezHeal")
    if type(api) == "table" and type(api.ReplaceSpells) == "function" then return api end
    return nil
end

-- Ränge in Blizzards Klick-Zauber tauschen. changes: { { button, modifiers, id, newID } } → Anzahl der Stellen
function Ranks.SwapClicks(changes)
    local owner = Ranks.ClickOwner()
    if owner then
        -- ein Fehler in ezHeal landet in ezCores Fehlerliste unter ezHeal (Core.Try), die Belegung bleibt, wie sie war
        local ok, done, reason = Core.Try("ezHeal", "ReplaceSpells (ezMacro)", owner.ReplaceSpells, changes,
            { via = "ezMacro", quiet = true })
        if not ok or done ~= true then
            if not (ok and reason == "combat") then ns.Print(L.RANKS_CLICK_FAILED) end
            return 0
        end
        return type(reason) == "number" and reason or 0
    end
    local CB = ClickBindings()
    local clicks = ClickList()
    if not (CB and clicks) then return 0 end
    local count = 0
    for _, change in ipairs(changes) do
        local entry = CB.Find(clicks, change.button, change.modifiers)
        if entry and entry.kind == "spell" and entry.id == change.id then
            entry.id = change.newID
            count = count + 1
        end
    end
    if count > 0 then
        -- nur IDs getauscht: Blizzards Standard nicht ergänzen (keepDefaults = false); ezCore sichert die alte
        -- Belegung (Core.ClickBindings.Restore) und wartet im Kampf selbst
        local ok, reason = CB.Set(clicks, { owner = "ezMacro", keepDefaults = false, quiet = true })
        -- gescheitert (nicht nur auf das Kampfende verschoben): nichts getauscht, wie der Weg über ezHeal
        if not ok and reason ~= "combat" then
            ns.Print(L.RANKS_CLICK_FAILED)
            return 0
        end
    end
    return count
end

-- Ersetzt alle veralteten Ränge (ohne Ausnahmen). Im Kampf: nach dem Kampf. Rückgabe: Anzahl der Stellen.
function Ranks.Update(silent)
    if not Ranks.Available() then return 0 end
    if ns.InCombat() then
        if not Core.AfterCombatWaiting("ezMacro:" .. UPDATE_KEY) and not silent then Core.CombatNotice(ns, L.RANKS_COMBAT_WHAT, "later") end
        ns.AfterCombat(function() Ranks.Update(true) end, UPDATE_KEY)
        return 0
    end
    FlushClicks()
    local list = Ranks.Scan()
    local done = 0
    local changes = {}
    for _, item in ipairs(list) do
        if item.kind == "slot" then
            if ns.Profiles.PlaceSpell(item.slot, item.newID) then done = done + 1 end
        elseif item.kind == "macro" then
            local index = ns.Macros.Find(item.macro, item.perChar)
            if index and ns.Import.Rewrite(index, item.newBody) then done = done + 1 end
        elseif item.kind == "click" then
            -- je Fund über Taste und Umschalttasten (stabiler als die Stelle in der Liste)
            changes[#changes + 1] = { button = item.button, modifiers = item.modifiers, id = item.id, newID = item.newID }
        end
    end
    if #changes > 0 then done = done + Ranks.SwapClicks(changes) end
    if not silent or done > 0 then
        ns.Print(done > 0 and L.RANKS_DONE:format(done) or L.RANKS_NOTHING)
    end
    lastCount = 0
    Ranks.Changed()
    return done
end

---------------------------------------------------------------------------
-- Anzeige: Knopf im Zauberbuch, Leuchten, Werkzeug
---------------------------------------------------------------------------

local spellbookTab
local TAB_ICON = { "Spell_ChargePositive", "INV_Misc_Book_11" }

-- Tooltip: was sich ändert (höchstens zehn Zeilen).
local function Describe(item)
    local where
    if item.kind == "slot" then
        where = item.bar and L.RANKS_WHERE_EZBARS:format(item.slot, item.bar) or L.RANKS_WHERE_SLOT:format(item.slot)
    elseif item.kind == "macro" then
        where = L.RANKS_WHERE_MACRO:format(item.macro)
        local count = item.slots and #item.slots or 0
        local bars = item.barCount or 0
        if count == 1 then
            where = where .. "  ·  " .. (bars > 0 and L.RANKS_ON_BAR_ONE_EZBARS or L.RANKS_ON_BAR_ONE)
        elseif count > 1 then
            where = where .. "  ·  " .. (bars > 0 and L.RANKS_ON_BARS_EZBARS:format(count, bars)
                or L.RANKS_ON_BARS:format(count))
        end
    else
        where = L.RANKS_WHERE_CLICK
    end
    return where, L.RANKS_CHANGE:format(item.name or "?", item.old or 0, item.new or 0)
end

function Ranks.Tooltip()
    local list = Ranks.Scan()
    if #list == 0 then return L.RANKS_NONE end
    local lines = { L.RANKS_BUTTON_TIP }
    for index, item in ipairs(list) do
        if index > 10 then
            lines[#lines + 1] = ezCore.More(#list - 10)
            break
        end
        local where, change = Describe(item)
        lines[#lines + 1] = Core.Style.ColorText("highlight", change) .. "  " .. where
    end
    return table.concat(lines, "\n")
end

-- Seitenreiter: Anzahl unten rechts im Symbol, ohne alte Ränge entsättigt.
local function UpdateButton()
    if not spellbookTab then return end
    local n = Ranks.Count()
    spellbookTab.Count:SetText(n > 0 and tostring(n) or "")
    spellbookTab.Icon:SetDesaturated(n == 0 or ns.InCombat())
end

function Ranks.Tab() return spellbookTab end

-- Veraltete Knöpfe leuchten (ezCores Leucht-Dienst Core.Glow, Grund „ezMacro“/„ranks“, Art „rank“; Farbe und
-- Rangfolge aus Core.GLOW_KINDS), bis man aktualisiert oder „Rang behalten“ wählt; der Tooltip des Knopfs sagt, was
-- los ist und wo man es erledigt (Wunsch des Nutzers nach dem ersten Spieltest, 13.11.2026). Einstellung
-- „Veraltete Ränge leuchten lassen“ (rankGlow).
local GLOW_OWNER, GLOW_KEY = "ezMacro", "ranks"
local glowItems = {}         -- [Aktionsplatz] = Stelle aus Ranks.Scan (für den Tooltip)

-- Erklärzeile im Tooltip des Aktionsknopfs: Zauber, alter und neuer Rang, dazu der Handgriff – EINE Zeile
-- (ezCore zeigt je Knopf eine Zeile). Ein Makro-Knopf nennt das Makro und, bei mehreren alten Rängen darin, wie viele.
function Ranks.GlowTip(slot)
    local item = glowItems[slot]
    if not item then return nil end
    local text
    if item.kind == "macro" then
        text = L.RANKS_GLOW_TIP_MACRO:format(item.macro or "?", item.name or "?", item.old or 0, item.new or 0)
        if item.changes and #item.changes > 1 then
            -- weitere alte Ränge im Makro: Rest-Text aus ezCore („… und 2 weitere“, „… und noch 1“) plus Zusatz
            text = text .. " " .. Core.More(#item.changes - 1) .. " " .. L.RANKS_GLOW_TIP_MORE
        end
    else
        text = L.RANKS_GLOW_TIP:format(item.name or "?", item.old or 0, item.new or 0)
    end
    return text .. " – " .. L.RANKS_GLOW_HOW
end

-- Leuchtende Plätze (MACRO-36, Empfehlung umgesetzt, Antwort offen): Zauber direkt auf dem Platz und seit Welle 6
-- auch die Plätze von Makros mit altem Rang („/cast Dämonenhaut(Rang 1)“) – auf Blizzards Leisten wie auf denen von
-- ezBars (der Leucht-Dienst findet jeden Knopf über seinen Platz). Liegt auf einem Platz beides, gilt der Zauber.
function Ranks.GlowSlots()
    local slots, items = {}, {}
    if not (ns.S and ns.S.rankGlow) then return slots, items end
    local list = Ranks.Scan()
    for _, item in ipairs(list) do
        if item.kind == "slot" and not items[item.slot] then
            items[item.slot] = item
            slots[#slots + 1] = item.slot
        end
    end
    for _, item in ipairs(list) do
        if item.kind == "macro" then
            for _, slot in ipairs(item.slots or {}) do
                if not items[slot] then
                    items[slot] = item
                    slots[#slots + 1] = slot
                end
            end
        end
    end
    table.sort(slots)
    return slots, items
end

local function UpdateGlow()
    local glow = Core.Glow
    if not (glow and glow.Set and glow.Clear) then return end
    wipe(glowItems)
    local slots, items = Ranks.GlowSlots()
    for slot, item in pairs(items) do glowItems[slot] = item end
    if #slots > 0 then
        glow.Set(GLOW_OWNER, GLOW_KEY, { slots = slots, kind = "rank", tip = Ranks.GlowTip })
    else
        glow.Clear(GLOW_OWNER, GLOW_KEY)
    end
end

function Ranks.Changed()
    if scanCache then return end   -- läuft schon (ein Zuhörer hat Changed erneut ausgelöst)
    local all = Ranks.Scan(true)
    scanCache = all
    local ok, err = pcall(function()
        UpdateButton()
        UpdateGlow()
        if ns.Tools then ns.Tools.RefreshKey("ranks") end
    end)
    scanCache = nil
    if not ok then ns.Error(err, "Ranks.Changed") end
end

-- Seitenreiter „Ränge aktualisieren“ rechts am Zauberbuch (Blizzard_PlayerSpells, Forever: PlayerSpellsFrame
-- mit SpellBookFrame), wie Blizzards Seitenreiter (ezCore.CreateSideTab, RightSideTabTemplate). Kind des
-- Zauberbuchs, also nur sichtbar, solange es offen ist; im Seitenreiter-Stapel des Zauberbuchs mit der Zahl
-- Ranks.TAB_ORDER = 20 (unter ezMerchants „Was kommt wann“ 10, über ezCombat 30 und ezHeal 40; Gesamtreview
-- 18.11.2026, T16-4 – vorher fest y −114). Nichts an Blizzards Fenster wird verändert.
Ranks.TAB_ORDER = 20
local function CreateSpellbookButton()
    if spellbookTab or not Ranks.Available() then return end
    local frame = PlayerSpellsFrame
    local book = frame and frame.SpellBookFrame
    if type(book) ~= "table" then return end
    spellbookTab = Core.CreateSideTab(book, { key = "ezMacro.ranks", order = Ranks.TAB_ORDER, anchor = frame,
        owner = "ezMacro" })
    spellbookTab.Icon:SetTexture(ns.IconPath(TAB_ICON))
    spellbookTab:SetScript("OnClick", Core.SideTabClick(function() Ranks.Update() end))
    spellbookTab:SetScript("OnEnter", function(self) UI.Tip(self, L.RANKS_BUTTON, Ranks.Tooltip, "ANCHOR_RIGHT") end)
    spellbookTab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if book.HookScript then book:HookScript("OnShow", UpdateButton) end
    UpdateButton()
end

local function Items()
    local items = {}
    for _, item in ipairs(Ranks.Scan(true)) do
        local where, change = Describe(item)
        items[#items + 1] = {
            key = item.key,
            icon = item.icon or ns.DEFAULT_ICON,
            text = change,
            sub = where .. (item.kept and ("  ·  " .. L.RANKS_KEPT) or ""),
            grey = item.kept,
            tip = item.kind == "macro" and L.RANKS_MACRO_TIP:format(#item.changes) or nil,
            item = item,
        }
    end
    return items
end

ns.Tools.Register({
    key = "ranks", order = 5, icon = { "Spell_ChargePositive", "INV_Misc_Book_11" },
    name = L.TOOL_RANKS, why = L.TOOL_RANKS_WHY, desc = L.TOOL_RANKS_DESC,
    shown = Ranks.Available,
    status = function()
        local other = Ranks.Other()
        if other then return UI.Colored("ORANGE_FONT_COLOR", L.RANKS_OTHER:format(other)) end
        local n = Ranks.Count()
        if n == 0 then return UI.Colored("GREEN_FONT_COLOR", L.RANKS_NONE) end
        return L.RANKS_STATUS:format(n)
    end,
    build = function(panel)
        panel.auto = UI.SettingCheck(panel, "rankAuto")
        panel.auto:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -4, -4)
        panel.update = UI.Button(panel, L.RANKS_UPDATE, 150, function() Ranks.Update() end, L.RANKS_UPDATE,
            L.RANKS_UPDATE_TIP)
        panel.update:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 26)
        panel.keep = UI.Button(panel, L.RANKS_KEEP, 130, function()
            local selected = panel.list:Selected()
            if selected then Ranks.SetKept(selected.item, not selected.item.kept) end
        end, L.RANKS_KEEP, L.RANKS_KEEP_TIP)
        panel.keep:SetPoint("LEFT", panel.update, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroRanksList", panel.width, function() ns.Tools.RefreshKey("ranks") end)
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 52)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.RANKS_EMPTY)
        local selected = panel.list:Selected()
        panel.keep:SetEnabled(selected ~= nil)
        panel.keep:SetText(selected and selected.item.kept and L.RANKS_UNKEEP or L.RANKS_KEEP)
        panel.update:SetEnabled(Ranks.Count() > 0 and not ns.InCombat())
        panel.auto.Refresh()
    end,
})

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- Zauberbuch neu gelesen (Lehrer, Stufenaufstieg, Login): automatisch aktualisieren oder einmal Bescheid sagen.
local function OnSpellsChanged()
    if not (ns.db and Ranks.Available()) then return end
    local n = Ranks.Count()
    local other = Ranks.Other()
    if n > 0 and ns.S.rankAuto and not other then
        Ranks.Update(true)
        return
    end
    if n > lastCount and not other then ns.Print(L.RANKS_HINT:format(n)) end
    lastCount = n
    Ranks.Changed()
end

ns.OnReady(function()
    if not Ranks.Available() then return end
    Core.Listen("SPELLS_KNOWN_CHANGED", function() ns.Try("Ranks", OnSpellsChanged) end, "ezMacro")
    ns.WhenAddOnLoaded("Blizzard_PlayerSpells", CreateSpellbookButton)
    CreateSpellbookButton()   -- Rückfall: Zauberbuch schon da, ohne dass der Client es als geladen meldet
end)

-- Ein vergessener Twink (ezCore.ForgetChar, Nachricht CHAR_FORGOTTEN): seine „Rang behalten“-Ausnahmen gehen mit.
-- Sicherungen und lange Makros bleiben (festgelegt 13.11.2026: Sicherungen von ezMacro bleiben).
Core.Listen("CHAR_FORGOTTEN", function(key)
    if key ~= nil and ns.db and type(ns.db.rankKeep) == "table" then ns.db.rankKeep[key] = nil end
end, "ezMacro")

-- Im Kampf nur vormerken (V-097): Plätze wechseln dort ständig (Haltung, Gestalt, Fahrzeug); ein Lauf danach reicht.
local refreshSoon = ns.Throttle(function() ns.AfterCombat(Ranks.Changed, "ranks.changed") end, 0.3)
-- Platz geändert (auch von Hand den neuen Rang aufgelegt, ein Makro mit altem Rang auf eine Leiste gezogen): Zahl
-- am Seitenreiter und Leuchten nachziehen. Mit eingeschaltetem Leuchten immer (MACRO-36: ein Makro auf einem neuen
-- Platz soll gleich leuchten, auch bevor das Zauberbuch geladen ist).
local function Watching() return spellbookTab ~= nil or next(glowItems) ~= nil or (ns.S and ns.S.rankGlow) == true end
ns.On("ACTIONBAR_SLOT_CHANGED", function() if Watching() then refreshSoon() end end)
ns.OnSettingChanged(function(key)
    if key == "rankGlow" then UpdateGlow() end
end)
-- Hinweis am Zauberbuch, wo auch der Knopf „Ränge aktualisieren“ steht (ezCores Hinweis-Helfer, einmal je Account;
-- Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis): „Ränge automatisch aktualisieren“ schreibt ohne Klick Leisten, Makros und
-- Klick-Zauber um. Nur, solange kein anderes Addon die Ränge nachzieht (Ranks.Other).
function Ranks.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting("ezMacro", ns, "rankAuto", {
        window = "spellbook",
        applies = function() return Ranks.Other() == nil end,
    })
end
Ranks.RegisterOptInHint()

-- Makrotext geändert (auch von Hand den Rang angepasst): Leuchten der Makro-Knöpfe nachziehen.
ns.On("UPDATE_MACROS", function() if Watching() then refreshSoon() end end)
-- Reine Anzeige (Symbol im Kampf grau): bleibt ein Zuhörer; das Nachholen selbst läuft über ns.AfterCombat.
ns.On("PLAYER_REGEN_DISABLED", UpdateButton)
ns.On("PLAYER_REGEN_ENABLED", UpdateButton)
