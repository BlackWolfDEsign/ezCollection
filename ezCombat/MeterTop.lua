local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- Marken an Blizzards Gruppen- und Raidrahmen: Top-3-Ansicht, weitere Arten und Aggro (Frage des Nutzers vom
-- 16.11.2026: „zeigt unser detail auch alle plätze am entsprechenden rahmen an? oder gar einfach die ersten 3 ränge
-- von demage, heal, aggro und co?“ – Antwort auf „Top-3-Ansicht und weitere Arten an die Rahmen bauen?“: „Ja, beides“).
-- Die Zeilen mit Balken stehen in MeterFrames.lua; hier nur die Marken.
--
-- Was eine Marke ist: Symbol der Art (Blizzards Symbole, MF.TYPES/MF.EXTRA_TYPES/MF.THREAT) und rechts daneben eine
-- kurze Zahl – der Platz (1, 2, 3 in Gold, Silber, Bronze über ezCores Farb-Rollen „normal“, „highlight“, „orange“,
-- also Blizzards Farbobjekte NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, ORANGE_FONT_COLOR; keine eigenen Bilddateien,
-- Leitlinie 1) oder bei Zählern die Zahl in der Farbe der Art. Mehrere Marken stehen nebeneinander von links nach
-- rechts, nur so viele, wie in die Breite des Halters passen (der Rest steht im Tooltip). Größe: so hoch wie der
-- Platz „center“ (Core.GroupFrames.SLOT_HEIGHT, 10 px), damit sie in Blizzards Mittelband passen.
--
-- Wo (Platzplan „Mittelband teilen“, Lage aus Core.GroupFrames.SLOTS, Platz "center", Teil MF.TEXT_PART):
--   • klassische Gruppenrahmen und Spielerrahmen: auf Blizzards Lebensbalken links neben ezHeals HoTs (Platz
--     "center"; seit dem Spielbefund vom 18.11.2026 im Rahmen statt rechts daneben) – auch im Kampf. Stehen Marken
--     dort, entfällt für diesen Rahmen die kurze Zahl wie im Raidstil (die Linien auf dem Manabalken bleiben).
--   • Raidstil: in der Mitte des Rahmens wie die kurze Zahl der Zeilen; dieser Platz ist nur außerhalb des Kampfes und
--     ab 30 px Höhe frei (GF.SlotInCombat, minHeight). Stehen Marken dort, entfällt für diesen Rahmen die kurze Zahl
--     (die Linien oben bleiben). Im Kampf bleibt die Mitte frei – auch für Aggro: Blizzards eigene Aggro-Markierung
--     am Raidrahmen bleibt.
--
-- Welche Marken:
--   • Darstellung „Nur die ersten 3“ und „beides“ (MF.ShowTop): je eingeschaltete Art mit Platz (Schaden, Heilung,
--     Unterbrechungen, Bannungen) eine Marke am Rahmen jedes Mitglieds auf Platz 1, 2 oder 3. Gleichstand teilt den
--     Platz (MF.Ranking). Weniger als drei Mitglieder mit Werten: weniger Marken.
--   • Darstellung „Zeilen“: Unterbrechungen und Bannungen als Marke mit der Zahl (sie haben keine Zeile).
--   • Tode immer mit der Zahl der Tode, ohne Platz – öfter sterben ist kein Rang (nur, wer mindestens einmal starb).
--   • Aggro (Schalter meterFramesThreat): live im Kampf, Platz 1–3 der Bedrohung (unten).
-- Plätze nur aus offenen Werten nach dem Kampf (MF.Ranking, Leitlinie 6 – im Kampf wird nie verglichen). Im Kampf
-- bleiben die Marken der Schadensanzeige leer statt „Stand: letzter Kampf“: Der aktuelle Abschnitt beginnt mit dem
-- Kampf neu, die Plätze des vorigen Kampfs passten weder zu den laufenden Balken noch zum Kampf – und die Zeilen
-- verwerfen ihren Platz beim Kampfbeginn ebenso (PLAYER_REGEN_DISABLED in MeterFrames.lua). Der Tooltip sagt, dass
-- die Plätze nach dem Kampf folgen.
--
-- Aggro aus Blizzards Bedrohungs-Abfrage (Forever-Quelle, Blizzard_APIDocumentationGenerated/UnitDocumentation.lua):
-- UnitDetailedThreatSituation(einheit, gegner) → isTanking, status, scaledPercentage, rawPercentage, rawThreat mit
-- „SecretWhenUnitThreatValuesRestricted“ und „SecretArguments: AllowedWhenUntainted“. Ob Forever die Werte im Kampf
-- sperrt, sagt die Dokumentation nicht (die Einschränkung ist eine Bedingung des Spiels) – Prüfpunkt im Spiel.
-- Gegner: das eigene Ziel, wenn man es angreifen kann, sonst das Ziel eines Tanks der Gruppe. Jeder Wert geht zuerst
-- durch Core.IsSecret; ist einer gesperrt, gibt es keine Rangliste und keine Marke (kein Raten) – Blizzards eigene
-- Aggro-Markierung am Rahmen bleibt. Quelle im Tooltip („laut Blizzards Bedrohungsanzeige“).
-- Rücksicht (Leitlinie 9): läuft ein Bedrohungs-Addon (ezCore-Schlüssel "threatMeter"), nennen Tooltip und Status es;
-- die Marken bleiben, denn sie erscheinen nur an Blizzards Rahmen.
-- Taint-sicher: nur lesen, eigene Halter über Core.GroupFrames, nichts in Blizzards Rahmen.

local MF = ns.MeterFrames
local GF = Core.GroupFrames
local Top = {}
MF.Top = Top

Top.PLACES = 3
Top.SIZE = GF and GF.SLOT_HEIGHT or 10    -- Höhe des Platzes "center" (Raidstil-Mittelband, klassisch 10 px)
Top.GAP = 2
Top.CHAR_WIDTH = 6                        -- Breite je Zeichen, wenn die Schrift (noch) keine Breite meldet
Top.CAP_TEXT = "9+"                      -- passt die erste Marke mit ihrer Zahl nicht, steht das (sonst nur das Symbol)
Top.MEDALS = { "normal", "highlight", "orange" }   -- Gold, Silber, Bronze (Farb-Rollen in ezCore/Bausteine/Style.lua)
Top.THREAT_KEY = "meterFramesThreat"
Top.OTHER = "threatMeter"                 -- Schlüssel fremder Bedrohungs-Addons in ezCore (Core.WhoHandles)

local lastThreat = nil                    -- "open" | "secret" | "none" | "missing" | "error" | "idle" (für /ezk status)

function Top.ThreatEnabled() return ns.S ~= nil and ns.S[Top.THREAT_KEY] == true end

-- Arten der Schadensanzeige, die Marken bekommen: mit Top-3 alle eingeschalteten, sonst nur die weiteren.
function Top.Kinds()
    local list = {}
    if MF.ShowTop() then
        for _, entry in ipairs(MF.ActiveTypes()) do list[#list + 1] = entry end
    end
    for _, entry in ipairs(MF.ActiveExtras()) do list[#list + 1] = entry end
    return list
end

---------------------------------------------------------------------------
-- Aggro
---------------------------------------------------------------------------

local function Call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Gegner, den man angreifen kann (offen ja; gesperrt oder unbekannt: nein).
local function Hostile(unit)
    if ns.UnitPresent(unit) ~= true then return false end
    local ok, can = Call("UnitCanAttack", "player", unit)
    return ok and not Core.IsSecret(can) and can == true
end

local function Tank(unit)
    local ok, role = Call("UnitGroupRolesAssigned", unit)
    return ok and not Core.IsSecret(role) and role == "TANK"
end

-- Gegner für die Bedrohung → einheit, "own" | "tank" | nil
function Top.ThreatTarget()
    if Hostile("target") then return "target", "own" end
    if not GF then return nil end
    for _, item in ipairs(GF.List()) do
        if item.unit ~= "player" and Tank(item.unit) then
            local mob = item.unit .. "target"
            if Hostile(mob) then return mob, "tank" end
        end
    end
    return nil
end

-- Rangliste der Bedrohung gegen den Gegner, nur aus offenen Werten:
-- { byUnit = { [einheit] = { rank, value, percent, tanking } }, count, whose } | nil, Grund
-- ("none" kein Gegner, "missing" keine Abfrage, "error", "secret" – ein einziger gesperrter Wert genügt).
function Top.ThreatRanking()
    local mob, whose = Top.ThreatTarget()
    if not mob then return nil, "none" end
    if type(rawget(_G, "UnitDetailedThreatSituation")) ~= "function" then return nil, "missing" end
    local list, seen = {}, {}
    for index, item in ipairs(GF and GF.List() or {}) do
        local unit = item.unit
        if not seen[unit] then
            seen[unit] = true
            local ok, tanking, status, scaled, raw, value = Call("UnitDetailedThreatSituation", unit, mob)
            if not ok then return nil, "error" end
            -- jeden der fünf Werte einzeln prüfen (eine Schleife mit ipairs hörte beim ersten nil auf)
            if Core.IsSecret(tanking) or Core.IsSecret(status) or Core.IsSecret(scaled) or Core.IsSecret(raw)
                or Core.IsSecret(value) then
                return nil, "secret"
            end
            local amount = type(value) == "number" and value or (type(scaled) == "number" and scaled or nil)
            if amount and amount > 0 then
                list[#list + 1] = { unit = unit, value = amount, index = index, tanking = tanking == true,
                    percent = type(scaled) == "number" and scaled or nil }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.index < b.index
    end)
    local ranking = { byUnit = {}, count = #list, whose = whose }
    for position, entry in ipairs(list) do
        local before = list[position - 1]
        entry.rank = (before and before.value == entry.value) and before.rank or position
        ranking.byUnit[entry.unit] = entry
    end
    return ranking
end

---------------------------------------------------------------------------
-- Plan und Marken
---------------------------------------------------------------------------

-- Was die Marken zeigen: { any, kinds = { { entry, ranking } … }, threat, pending, mode }.
-- any: es gibt etwas, wofür Marken gebraucht werden (auch wenn gerade keine zu sehen ist).
function Top.Plan(available)
    local plan = { kinds = {}, any = false, pending = false }
    local kinds = available and Top.Kinds() or {}
    local threat = Top.ThreatEnabled()
    plan.any = #kinds > 0 or threat
    if not plan.any then
        lastThreat = nil
        return plan
    end
    if ns.InCombat() then
        if #kinds > 0 then plan.mode = "toplive" end
        -- Gesamtreview 18.11.2026 (T8-9): Die Bedrohung wird erst gelesen, wenn ein Rahmen Marken zeigen darf
        -- (Top.BadgesFor, nach MF.TextAllowed in Top.Fill) – im Raidstil bleibt die Mitte im Kampf frei, dann liest der
        -- Takt nicht mehr je Sekunde bis zu 40 Einheiten.
        if threat then plan.threatLater = true end
        return plan
    end
    lastThreat = threat and "idle" or nil
    local sel = MF.Selector()
    for _, entry in ipairs(kinds) do
        local ranking, why = MF.Ranking(MF.MeterType(entry), sel)
        if ranking then
            plan.kinds[#plan.kinds + 1] = { entry = entry, ranking = ranking }
            if plan.mode ~= "secret" then plan.mode = "after" end
        elseif why == "secret" then
            plan.pending, plan.mode = true, "secret"
        end
    end
    return plan
end

-- Marken eines Mitglieds: { { key, entry, text, rank | count } … } in der Reihenfolge der Arten, Aggro zuletzt.
local function ReadThreat(plan)
    if not plan.threatLater then return end
    plan.threatLater = nil
    local why
    plan.threat, why = Top.ThreatRanking()
    lastThreat = plan.threat and "open" or why
end
Top.ReadThreat = ReadThreat                  -- für die Prüfungen

function Top.BadgesFor(unit, plan)
    ReadThreat(plan)
    local out = {}
    local guid = MF.GUID(unit)
    local showTop = MF.ShowTop()
    for _, part in ipairs(plan.kinds) do
        local entry, ranking = part.entry, part.ranking
        local found = guid and ranking.byGUID[guid] or nil
        if not found and unit == "player" then found = ranking.mine end
        if found then
            if entry.noRank or (entry.counts and not showTop) then
                out[#out + 1] = { key = entry.key, entry = entry, text = Core.FormatNumber(found.total), count = found.total }
            elseif found.rank <= Top.PLACES then
                out[#out + 1] = { key = entry.key, entry = entry, text = tostring(found.rank), rank = found.rank }
            end
        end
    end
    local found = plan.threat and plan.threat.byUnit[unit]
    if found and found.rank <= Top.PLACES then
        out[#out + 1] = { key = MF.THREAT.key, entry = MF.THREAT, text = tostring(found.rank), rank = found.rank }
    end
    return out
end

-- Halter der Marken (Platz "center", derselbe Teil wie die kurze Zahl der Zeilen im Raidstil). Außerhalb des Kampfes
-- legt ezCore ihn an, im Kampf nur den schon vorhandenen – darum legt ihn Top.Fill schon vor dem Kampf an, sobald
-- Marken gebraucht werden können (any).
function Top.Holder(frame, need)
    if not GF then return nil end
    local holder = GF.Part(ADDON, frame, MF.TEXT_PART)
    if holder or not need or ns.InCombat() then return holder end
    return GF.Slot(ADDON, frame, MF.TEXT_SLOT, MF.TEXT_PART, { level = MF.LEVEL })
end

local function Badge(holder, index)
    holder.badges = holder.badges or {}
    local badge = holder.badges[index]
    if badge then return badge end
    local icon = holder:CreateTexture(nil, "ARTWORK")
    local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    MF.NoWrap(text)
    icon:SetSize(Top.SIZE, Top.SIZE)
    if index == 1 then
        icon:SetPoint("LEFT", holder, "LEFT", 0, 0)
    else
        icon:SetPoint("LEFT", holder.badges[index - 1].text, "RIGHT", Top.GAP, 0)
    end
    text:SetPoint("LEFT", icon, "RIGHT", 1, 0)
    text:SetJustifyH("LEFT")
    icon:Hide()
    text:Hide()
    badge = { icon = icon, text = text }
    holder.badges[index] = badge
    return badge
end

-- Breite einer Marke: Symbol, 1 px, Zahl (gemessene Breite der Schrift; ohne Messung Top.CHAR_WIDTH je Zeichen).
-- Das Symbol zählt auch, wenn es fehlt – die Zahl hängt an seinem Anker.
function Top.BadgeWidth(badge, text)
    local width = Core.Num(badge.text:GetStringWidth())
    if not width or width <= 0 then width = #tostring(text or "") * Top.CHAR_WIDTH end
    return Top.SIZE + 1 + width
end

-- Breite des Halters, offen gelesen (Raidstil: der Raum zwischen midLeft und midRight; klassisch der Lebensbalken
-- links neben den HoTs) | nil, solange keine bekannt ist.
local function HolderWidth(holder)
    local width = Core.Num(holder:GetWidth())
    if width and width > 0 then return width end
    return nil
end

-- Marken zeigen (list leer: alle verbergen). holder.badgeState hält fest, was zu sehen ist (Status, Prüfungen).
-- Nur so viele Marken, wie in die Breite des Halters passen; die erste steht immer, aber gekürzt, wenn ihre Zahl
-- nicht passt („9+“, sonst nur das Symbol – der Platz garantiert nur die Breite einer einstelligen Marke, GF.SLOTS
-- minWidth; Fund des code-reviewers vor dem Merge, 16.11.2026); überzählige bleiben verborgen, damit sie nicht über den Rahmen oder in ezHeals HoT-Reihe
-- (midRight) laufen. Was weggelassen ist, nennt weiter der Einheiten-Tooltip; holder.badgeCut zählt es.
local function Show(holder, list)
    -- T8-9: dieselbe Tabelle je Halter, geleert statt je Takt neu angelegt
    if holder.badgeState then wipe(holder.badgeState) else holder.badgeState = {} end
    local room, used, shown = HolderWidth(holder), 0, 0
    for index, want in ipairs(list) do
        local badge = Badge(holder, index)
        local text = want.text
        badge.text:SetText(text)
        local width = Top.BadgeWidth(badge, text) + (index > 1 and Top.GAP or 0)
        if index > 1 and (not room or used + width > room) then break end
        if index == 1 and room and width > room then
            text = Top.CAP_TEXT
            badge.text:SetText(text)
            width = Top.BadgeWidth(badge, text)
            if width > room then
                text = ""
                badge.text:SetText(text)
                width = Top.SIZE
            end
        end
        used, shown = used + width, index
        if badge.key ~= want.key then
            badge.icon:SetTexCoord(0, 1, 0, 1)        -- Ausschnitt der Rollen-Datei nicht auf ein anderes Symbol tragen
            badge.hasIcon = MF.SetIcon(badge.icon, want.entry.icon)
            badge.key = want.key
        end
        badge.icon:SetShown(badge.hasIcon == true)
        if want.rank then
            Core.Style.SetTextColor(badge.text, Top.MEDALS[want.rank] or "normal")
        else
            local r, g, b = MF.Color(want.entry)
            badge.text:SetTextColor(r, g, b)
        end
        badge.text:Show()
        holder.badgeState[index] = { key = want.key, text = text, rank = want.rank, count = want.count }
    end
    for index = shown + 1, #(holder.badges or {}) do
        local badge = holder.badges[index]
        badge.icon:Hide()
        badge.text:Hide()
    end
    holder.badgeCut = #list - shown
end
Top.Show = Show                              -- für die Prüfungen

-- Marken eines Rahmens setzen. rowsHolder: Halter der Zeilen (Raidstil: ihre kurze Zahl weicht den Marken).
function Top.Fill(item, plan, rowsHolder)
    local holder = Top.Holder(item.frame, plan.any)
    if not holder then return end
    -- Raidstil im Kampf: die Mitte bleibt frei – zuerst fragen, dann erst die Marken bauen (T8-9)
    local list = plan.any and MF.TextAllowed(item.kind) and Top.BadgesFor(item.unit, plan) or {}
    Show(holder, list)
    if #list > 0 and rowsHolder and rowsHolder.rows and not rowsHolder.classic then
        for _, row in pairs(rowsHolder.rows) do
            if row.text:GetParent() == holder and row.text:IsShown() then
                row.text:Hide()
                if row.state then row.state.hidden = true end
            end
        end
    end
end

function Top.Hide(frame)
    local holder = GF and GF.Part(ADDON, frame, MF.TEXT_PART)
    if holder and holder.badges then Show(holder, {}) end
end

-- Marken eines Rahmens: { { key, text, rank | count } … } | nil (für /ezk status und die Prüfungen)
function MF.Badges(frame)
    local holder = GF and GF.Part(ADDON, frame, MF.TEXT_PART)
    return holder and holder.badgeState or nil
end

-- Vorschau („Zeigen“): erfundene Plätze 1–3 an den ersten drei Rahmen, Tode als Zahl, Aggro wie Platz.
function Top.Preview(item, index, rowsHolder)
    local kinds = MF.Available() and Top.Kinds() or {}
    local threat = Top.ThreatEnabled()
    if #kinds == 0 and not threat then return end
    local list = {}
    for _, entry in ipairs(kinds) do
        if entry.noRank or (entry.counts and not MF.ShowTop()) then
            local count = Top.PLACES + 1 - index
            if count > 0 then list[#list + 1] = { key = entry.key, entry = entry, text = tostring(count), count = count } end
        elseif index <= Top.PLACES then
            list[#list + 1] = { key = entry.key, entry = entry, text = tostring(index), rank = index }
        end
    end
    if threat and index <= Top.PLACES then
        list[#list + 1] = { key = MF.THREAT.key, entry = MF.THREAT, text = tostring(index), rank = index }
    end
    if not MF.TextAllowed(item.kind) then list = {} end   -- Raidstil im Kampf: die Mitte bleibt frei, auch in der Vorschau
    local holder = Top.Holder(item.frame, true)
    if not holder then return end
    Show(holder, list)
    if #list > 0 and rowsHolder and rowsHolder.rows and not rowsHolder.classic then
        for _, row in pairs(rowsHolder.rows) do
            if row.text:GetParent() == holder then row.text:Hide() end
        end
    end
end

---------------------------------------------------------------------------
-- Tooltip und Status
---------------------------------------------------------------------------

function Top.Other() return (ns.OtherFor(Top.OTHER)) end

-- Zeilen zur Aggro im Einheiten-Tooltip (nur im Kampf und mit Schalter): Platz von wie vielen und Anteil laut
-- Blizzard, bei gesperrten Werten der Hinweis; zuletzt die Quelle.
function Top.ThreatLines(unit)
    local lines = {}
    if not Top.ThreatEnabled() or not ns.InCombat() or type(unit) ~= "string" then return lines end
    local ranking, why = Top.ThreatRanking()
    local gray = 0.6
    local label = L.METER_FRAMES_KIND_threat
    local r, g, b = MF.Color(MF.THREAT)
    if why == "secret" then
        lines[#lines + 1] = { text = L.METER_FRAMES_TIP_THREAT_SECRET, r = gray, g = gray, b = gray }
        return lines
    end
    if not ranking then return lines end
    local found = ranking.byUnit[unit]
    if found then
        local percent = Core.Num(found.percent)
        local text = percent and L.METER_FRAMES_TIP_THREAT:format(label, found.rank, ranking.count, Core.Percent(percent))
            or L.METER_FRAMES_TIP_RANK:format(label, found.rank, ranking.count, Core.ShortNumber(found.value))
        lines[#lines + 1] = { text = text, r = r, g = g, b = b }
    else
        lines[#lines + 1] = { text = L.METER_FRAMES_TIP_NONE:format(label), r = r, g = g, b = b }
    end
    local source = ranking.whose == "tank" and L.METER_FRAMES_TIP_THREAT_SOURCE_TANK or L.METER_FRAMES_TIP_THREAT_SOURCE
    lines[#lines + 1] = { text = source, r = gray, g = gray, b = gray }
    return lines
end

function Top.Mode() return lastThreat end

function Top.StatusLine()
    if not Top.ThreatEnabled() then return nil end
    -- Im Kampf liest der Takt die Bedrohung nur noch, wenn ein Rahmen Marken zeigen darf (T8-9); der Status fragt dann
    -- selbst (nur auf Abruf).
    if ns.InCombat() then
        local ranking, why = Top.ThreatRanking()
        lastThreat = ranking and "open" or why
    end
    local state = L["STATUS_METER_THREAT_" .. string.upper(lastThreat or "idle")] or L.STATUS_METER_THREAT_IDLE
    local line = L.STATUS_METER_THREAT:format(state)
    local other = Top.Other()
    if other then line = line .. " " .. L.METER_FRAMES_THREAT_OTHER:format(other) end
    return line
end

ns.AddStatusLine(Top.StatusLine)
-- Kein Zuhörer auf Ziel- und Bedrohungswechsel (Gesamtreview 18.11.2026, T8-9; Gegenprüfung P19c): Im Kampf zeichnet
-- der Takt der Kampfanzeige ohnehin jede Sekunde neu und liest dabei die Bedrohung; außerhalb des Kampfes liest er sie
-- gar nicht (Top.Plan: „idle“), nach dem Kampf zeichnet PLAYER_REGEN_ENABLED neu. Die früheren Zuhörer auf
-- PLAYER_TARGET_CHANGED und UNIT_THREAT_* (seit 1ebef973) merkten nur ein Neuzeichnen vor, das nichts änderte.
