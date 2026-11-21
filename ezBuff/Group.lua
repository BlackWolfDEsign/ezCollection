local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Abschnitt „Gruppe“ (Entscheidung des Nutzers 13.11.2026: „Ja, in ezBuff“ – die Funktionen von Party Buff
    Tracker Forever ohne eigenes Fenster, an Blizzards Gruppen- und Raidrahmen; nichts aus dem Addon übernommen).

      Symbol je Mitglied   Ein kleiner sicherer Knopf in Blizzards Rahmen (Core.GroupFrames sagt, welcher Rahmen wen
                           zeigt; Core.SecureButton baut den Knopf): „dein Buff fehlt“ (graues Symbol)
                           bzw. „läuft aus“ (farbig, Restminuten). Linksklick wirkt ihn auf genau dieses Mitglied;
                           der Rechtsklick geht durch an Blizzards Rahmen (Menü, Group.PassRightClick).
      Essen und Fläschchen kleine Zeichen gleich rechts neben dem Symbol (eigenes, mausdurchlässiges Kind über
                           Core.GroupFrames.Slot): Buff-Essen fehlt; in Dungeon und Schlachtzug auch „kein bekanntes
                           Fläschchen oder Elixier“.
      Platz am Rahmen      Platzplan „Mittelband teilen“ (Entscheidung des Nutzers 14.11.2026): Symbol und Zeichen
                           sitzen am Platz "midLeft" aus Core.GroupFrames.SLOTS – im Raidstil Mitte links neben dem
                           Rollensymbol (auf 10 px verkleinert), klassisch oben links auf dem Porträt (auf 14 px;
                           Spielbefund des Nutzers vom 18.11.2026: „buffs und co nicht in einem popup sondern über
                           und an dem rahmen, den abstand zu den rahmen untereinander beibehalten“ – vorher an der
                           Unterkante des Porträts, wo Symbol und Zeichen unter Blizzards Rahmenbild in die Lücke zum
                           nächsten Rahmen ragten). Immer im Rahmen, nie darunter oder daneben. Wüchsen sie
                           in die sichtbaren HoTs von ezHeal (Gegenseite "midRight"), bleiben sie aus
                           (Core.GroupFrames.SlotRoom); fehlende Zeichen nennt dann der Tooltip des Symbols.
                           Setzt ezCore das Symbol neu (Blizzard ändert Größe, Kraftleiste oder Anordnung) und
                           reicht der Platz nicht mehr – auch wegen der sichtbaren HoTs –, verschwindet es sofort;
                           reicht er wieder, kehrt es zurück (Group.OnPlaced), nicht erst mit der nächsten Prüfung.
                           Die Zeichen blendet ezCore beim Neusetzen aus, wenn sie in die HoTs wüchsen; zurück
                           kommen sie mit dem Symbol, sobald wieder Platz ist (ohne Symbol mit der nächsten
                           Prüfung). In „Buffs oben, Debuffs unten“ sitzt es an der freien Stelle, die ezCore
                           findet (Core.GroupFrames.SlotBand).
      Durchbuffen          Sicherer Knopf ezBuffGroupNext auf einer Taste (Blizzards Tastaturbelegung → AddOns →
                           ezCollection, ezCores Tasten-Dienst, Eintrag „buffNext“, über den Stellvertreter
                           ezBuffGroupNextKey): jeder Druck wirkt den nächsten fehlenden Buff der Gruppe – erst alles, was
                           fehlt, dann was ausläuft; ein eben gebuffter bleibt kurz außen vor (das Spiel meldet die
                           neue Aura etwas später). Nur Mitglieder in Reichweite – beim Druck neu gefragt
                           (Check.InRange); der Knopf wirkt mit fester Einheit, er weicht nie auf dein Ziel aus. Ist
                           jeder, dem etwas fehlt, außer Reichweite, sagt der Chat „<Name> ist außer Reichweite“
                           (Spieltest des Nutzers vom 15.11.2026).
      Gruppenfassung       Fehlt der Buff mehreren Mitgliedern (Schwelle „groupMin“, ab Werk 3), wirken Symbol und
                           Durchbuffen die Gruppenfassung, wenn gelernt und das Reagenz da ist (Check.MarkGroupSpells,
                           BF-09); Symbol und Tooltip nennen sie. Regler „Gruppenfassung ab“ unter „Gruppe“ (1 = aus).
      Segen-Wahl           Paladin: im Rechtsklick-Menü des Rahmens (Menu.ModifyMenu) je Klasse ein Segen, darin
                           „Für <Name>“ eine Einzelwahl für genau diesen Spieler (überstimmt die Klasse). Die Wahl je
                           Klasse steht zusätzlich sichtbar in den Einstellungen (Gruppe → „Segen für <Klasse>“).

    Warum ein eigener sicherer Knopf und nicht Blizzards Klick-Zaubern (Core.ClickBindings): Klick-Zaubern ist eine
    Belegung für ALLE Rahmen des Charakters (dieselbe Taste wirkt überall denselben Zauber) und überschreibt die
    Belegung, die ezHeal und der Spieler pflegen. „Dieser Buff fehlt diesem Mitglied – ein Klick wirkt ihn“ ist ein
    Knopf mit Zauber und Einheit (Blizzards SecureActionButtonTemplate); Core.SecureButton setzt ihn nur außerhalb
    des Kampfes und holt Wünsche aus dem Kampf danach nach. Die Klick-Vorlagen mit Buffs bleiben bei ezHeal.
    Die Einheit steht nicht fest im Symbol: "useparent-unit" lässt Blizzards Vorlage das Attribut unit des Rahmens
    lesen, das Blizzard selbst setzt (Regel in docs/ezcore.md, „Regeln für Knöpfe an Gruppen- und Raidrahmen“) –
    verteilt Blizzard die Rahmen neu, trifft der Klick nie das vorige Mitglied. Der Zauber (Rang nach Stufe des
    Ziels) wird bei jedem Neubelegen des Rahmens (onUnit) außerhalb des Kampfes neu gesetzt.

    Nur außerhalb des Kampfes: Fremde Auren sind im Kampf unlesbar. Beim Kampfbeginn (PLAYER_REGEN_DISABLED, die
    Sperre greift erst danach) leert ezBuff die Aktionen aller Knöpfe und blendet die Zeichen aus; die Symbole blendet
    Blizzards Zustandstreiber aus (hideInCombat). Nach dem Kampf prüft ezBuff neu.
    Taint-sicher (Leitlinie 5): In Blizzards Rahmen wird nichts geschrieben; eigene Daten je Rahmen stehen in
    Core.GroupFrames.Data, das Menü wird nur über Menu.ModifyMenu ergänzt.
    Läuft Party Buff Tracker Forever (Core.WhoHandles("groupBuffs")), hält sich der Abschnitt zurück (Leitlinie 9).
]]

local Group = {}
ns.Group = Group

local OWNER = "ezBuff"
local GF = Core.GroupFrames
local ICON_SIZE = 16
local SIGN_SIZE = 11
local FOOD_ICON = "Interface\\Icons\\INV_Misc_Food_15"
local FLASK_ICON = "Interface\\Icons\\INV_Potion_97"
Group.NEXT_NAME = "ezBuffGroupNext"
-- Derselbe Eintrag wie Keys.LIST „buffNext“ (ezCore/Bindings.xml): ein Stellvertreter, der Blizzards „Aktion bei
-- Tastendruck“ folgt und ezBuffGroupNext drückt (Gesamtreview 18.11.2026, Nachlauf zu T9-NB1); „/click ezBuffGroupNext“
-- im Makro bleibt
Group.BINDING = "CLICK ezBuffGroupNextKey:LeftButton"
Group.KEY_ID = "buffNext"
Group.ICON_PREFIX = "ezBuffGroupIcon"
Group.UNIT_FROM_PARENT = "useparent-unit"   -- Attribut der Symbole: Einheit aus Blizzards Rahmen (nie fest gesetzt)
-- Menüs der Gruppen- und Raidrahmen (Blizzards CompactUnitFrame_OpenMenu: SELF, PARTY, RAID_PLAYER) aus ezCores
-- einer Liste der Spieler-Menüs (Welle 23, A1: Core.Menu.PlayerMenus mit der Art „frame“; vorher eine eigene Liste)
Group.MENUS = Core.Menu.PlayerMenus({ frame = true })
Group.RECENT = 3            -- Sekunden: ein eben gebuffter Eintrag bleibt beim Durchbuffen außen vor
Group.ICON_SIZE, Group.SIGN_SIZE = ICON_SIZE, SIGN_SIZE
Group.SLOT = "midLeft"      -- Platz in Core.GroupFrames.SLOTS (Symbol zuerst, dann die Zeichen)
Group.ICON_KEY, Group.SIGNS_KEY = "icon", "signs"

-- Platz vormerken (einmal beim Laden): Symbol, dann Essen und Fläschchen nebeneinander.
if GF and GF.Reserve then
    GF.Reserve(OWNER, Group.SLOT, Group.ICON_KEY, { size = { ICON_SIZE, ICON_SIZE }, order = 10 })
    GF.Reserve(OWNER, Group.SLOT, Group.SIGNS_KEY, { size = { SIGN_SIZE * 2 + 1, SIGN_SIZE }, order = 20 })
end

-- Größe eines Teils an diesem Rahmen (im Raidstil verkleinert, Core.GroupFrames.SlotSize).
local function SlotSize(frame, width, height)
    if not (GF and GF.SlotSize) then return width, height end
    return GF.SlotSize(GF.SlotKind(frame), Group.SLOT, width, height)
end

-- Passt das Teil, ohne in die sichtbaren HoTs der Gegenseite zu wachsen?
function Group.Room(frame, key)
    if not (GF and GF.SlotRoom) then return true end
    return GF.SlotRoom(frame, Group.SLOT, OWNER, key) == true
end

local recent = {}           -- ["unit:key"] = Zeit des letzten Klicks
local iconOf = setmetatable({}, { __mode = "k" })   -- eigener Knopf-Rahmen → Blizzards Rahmen
local count = 0
local nextButton, nextTarget, nextFar, menuHooked, watching
local lastOther             -- { unit, at }: letzter Klick, der auf ein anderes Mitglied wirkte (Group.RecentOther)

---------------------------------------------------------------------------
-- An oder aus?
---------------------------------------------------------------------------

-- Name des fremden Addons, das die Gruppe schon zeigt (Party Buff Tracker Forever), sonst nil.
function Group.OtherAddOn()
    return (ns.OtherFor("groupBuffs"))
end

function Group.Active()
    return ns.S ~= nil and ns.Enabled("groupFrames") and GF ~= nil and not Group.OtherAddOn()
end

---------------------------------------------------------------------------
-- Was zeigt ein Mitglied? (Daten aus ns.Check.ByUnit: je Mitglied ein Aura-Scan, nur außerhalb des Kampfes)
---------------------------------------------------------------------------

function Group.Entry(unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" or not ns.Check then return nil end
    return ns.Check.ByUnit()[unit]
end

-- Wichtigster Eintrag: zuerst was fehlt, dann was ausläuft (Reihenfolge der Buff-Gruppen).
function Group.FirstNeed(entry)
    if type(entry) ~= "table" then return nil end
    for _, state in ipairs({ "missing", "expiring" }) do
        for _, need in ipairs(entry.needs or {}) do
            if need.state == state then return need end
        end
    end
    return nil
end

local function Minutes(seconds)
    if type(seconds) ~= "number" or seconds == math.huge then return nil end
    return math.max(1, math.ceil(seconds / 60))
end

function Group.NeedText(need)
    if need.state == "expiring" and Minutes(need.left) then
        return L.GROUP_EXPIRING:format(need.name, Minutes(need.left))
    end
    return L.MISSING_SELF:format(need.name)
end

-- Welcher Zauber wirkt ein Klick (Symbol, Durchbuffen)? Die Gruppenfassung, wenn ezBuff sie eingetragen hat
-- (Check.MarkGroupSpells, BF-09: Schwelle erreicht, gelernt, Reagenz da), sonst die Einzelfassung im passenden Rang.
function Group.CastSpell(need)
    if type(need) ~= "table" then return nil end
    return need.groupSpell or need.spell
end

-- Nach einem Klick: wer bekommt den Buff gleich? Bei der Gruppenfassung alle, die sie mit auffrischt – damit
-- Durchbuffen nicht das nächste Mitglied derselben Gruppe einzeln bufft, bevor die Aura ankommt.
function Group.MarkCast(unit, need)
    if type(need) ~= "table" then return end
    if need.groupSpell and type(need.groupUnits) == "table" then
        for _, other in ipairs(need.groupUnits) do
            if other ~= unit then recent[other .. ":" .. tostring(need.key)] = GetTime() end
        end
    end
    Group.MarkRecent(unit, need.key)
end

-- Tooltip-Zeile zur Fassung: was der Klick wirkt (Gruppenfassung mit Zahl, sonst Einzelfassung) und – falls die
-- Schwelle erreicht ist, aber das Reagenz fehlt – warum es die Einzelfassung bleibt. Fehlt dem Zauber, den der Klick
-- wirkt, ein Reagenz oder Werkzeug, folgt „Dir fehlt …“ (Paket modul/ezbuff-reagenzien); jeder Hinweis auf ein
-- Reagenz nennt danach die Quelle des Bedarfs (Leitlinie 11, Check.ReagentSource).
function Group.SpellLines(need, name)
    local lines = {}
    if type(need) ~= "table" then return lines end
    local Check = ns.Check
    local source
    if need.groupSpell then
        lines[#lines + 1] = L.GROUP_CLICK_GROUP:format(Core.Spells.Name(need.groupSpell) or "?", need.groupCount or 0)
    else
        lines[#lines + 1] = L.GROUP_CLICK:format(need.name, name or "?")
        if need.groupReagent then
            lines[#lines + 1] = L.GROUP_NO_REAGENT:format(Core.ItemNameByID(need.groupReagent) or ("#" .. need.groupReagent))
            source = need.groupReagentSource or "list"
        end
    end
    local spell = Group.CastSpell(need)
    local missing, from
    if spell and Check and Check.MissingReagents then missing, from = Check.MissingReagents(spell) end
    if missing then
        lines[#lines + 1] = Check.ReagentText(missing)
        source = from or source
    end
    if source and Check and Check.ReagentSource then lines[#lines + 1] = Check.ReagentSource(source) end
    return lines
end

---------------------------------------------------------------------------
-- Symbol am Rahmen (sicherer Knopf) und Zeichen für Essen/Fläschchen (mausdurchlässiges Kind)
---------------------------------------------------------------------------

local function ShowTooltip(self)
    local frame = iconOf[self]
    local data = frame and GF.Data(OWNER, frame)
    local entry = data and data.entry
    if not entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = Core.GlowColor("missing")
    GameTooltip:SetText(Core.ClassText(entry.name or "?", entry.class), r, g, b)
    -- Was das Symbol ist und woher ezBuff es weiß (Spieltest 20.11.2026: „was soll das rote symbol sein?“; Leitlinie 11)
    Core.TipLine(GameTooltip, L.GROUP_ICON_WHAT, "hint", true)
    for _, need in ipairs(entry.needs or {}) do
        -- Rollen statt Farbzahlen (T9-6): der Buff, den der Klick wirkt, grün
        local text = Group.NeedText(need)
        if not need.inRange then text = text .. " – " .. L.GROUP_OUT_OF_RANGE end
        Core.TipLine(GameTooltip, text, need == data.need and "good" or "highlight")
    end
    if entry.food then Core.TipLine(GameTooltip, L.MISSING_FOOD, "highlight") end
    if entry.flask then
        Core.TipLine(GameTooltip, L.GROUP_FLASK, "highlight")
        -- Leitlinie 11: woher ezBuff weiß, was ein Fläschchen ist (BF-10)
        Core.TipLine(GameTooltip, L.GROUP_FLASK_SOURCE:format(ns.Check.KnownElixirs()), "hint", true)
    end
    if data.need then
        GameTooltip:AddLine(" ")
        for index, line in ipairs(Group.SpellLines(data.need, entry.name)) do
            if index == 1 then Core.TipLine(GameTooltip, line, "normal") else Core.TipLine(GameTooltip, line, "hint", true) end
        end
    end
    Core.TipLine(GameTooltip, Group.KeyLine(), "hint", true)
    Core.TipLine(GameTooltip, L.TIP_COMMAND, "hint")
    GameTooltip:Show()
end

-- Aufbau des Symbols (einmal, außerhalb des Kampfes; alles Ungeschützte). Blizzards Optik eines Buffs am Rahmen
-- (Leitlinie 1): nur das Symbol des Zaubers, grau wenn er fehlt, farbig mit Minuten wenn er ausläuft – wie Blizzards
-- Buffs an Gruppen- und Raidrahmen ohne Rand. Bis zum 20.11.2026 lag Blizzards Debuff-Rand (UI-Debuff-Overlays) in
-- Orange darum; am Spielerrahmen las er sich als rotes Warnzeichen (Spieltest 20.11.2026: „was soll das rote symbol
-- sein?“) – ein Debuff-Rand gehört zu Schwächungen, nicht zu einem fehlenden eigenen Buff.
local function BuildIcon(frame, blizzard)
    iconOf[frame] = blizzard
    pcall(frame.SetFrameLevel, frame, (ns.Num(blizzard:GetFrameLevel()) or 1) + 5)
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetAllPoints()
    frame.Text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.Text:SetPoint("BOTTOMRIGHT", 2, -2)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("PostClick", function(self)
        local data = GF.Data(OWNER, iconOf[self])
        if data and data.unit and data.need then Group.MarkCast(data.unit, data.need) end
        C_Timer.After(0.5, function() ns.Check.Request() end)
    end)
end

-- Fehlen die Zeichen, obwohl sie gewünscht sind und (wieder) Platz hätten? ezCore blendet sie beim Neusetzen nur
-- aus (Core.GroupFrames.Slot); zeigen ist Sache des Moduls.
local function SignsWaiting(frame, data)
    local entry = data.entry
    if not (entry and (entry.food or entry.flask) and ns.Enabled("groupSigns")) then return false end
    local kid = GF.Part(OWNER, frame, Group.SIGNS_KEY)
    if kid and kid:IsShown() then return false end
    return Group.Room(frame, Group.SIGNS_KEY)
end

-- Nach jedem Setzen des Symbols durch ezCore (auch Core.GroupFrames.Relayout nach DefaultCompactUnitFrameSetup:
-- Kraftleiste an oder aus, andere Rahmengröße oder Anordnung der Auren): Reicht der Platz nicht mehr – das Band
-- oder die Breite (fits) oder weil die sichtbaren HoTs gegenüber ihn brauchen (Group.Room) –, verschwindet das
-- Symbol sofort; sonst läge es bis zur nächsten Prüfung über Blizzards Auren oder den HoTs. ezCore setzt die
-- HoT-Reihe vor dem Symbol neu (Core.GroupFrames.RELAYOUT_ORDER), Group.Room sieht also schon ihren neuen Stand.
-- Die Zeichen blendet ezCore selbst aus (Core.GroupFrames.Slot).
-- Reicht der Platz wieder – für das Symbol, wenn noch etwas fehlt, oder für die Zeichen neben dem sichtbaren
-- Symbol –, füllt ezBuff den Rahmen im nächsten Bild neu (nicht in ezCores Schleife über die Teile). Nur dann:
-- Passt das Teil nicht neben die HoTs, scheiterte das Füllen bei jedem Neusetzen wieder an Group.Room.
-- Nur außerhalb des Kampfes; im Kampf setzt ezCore nichts, und nach dem Kampf prüft ezBuff ohnehin neu.
function Group.OnPlaced(frame, fits)
    local data = type(frame) == "table" and GF.Data(OWNER, frame)
    if not (data and data.icon) or ns.InCombat() then return end
    local shown = data.icon:Shown()
    local room = fits and Group.Room(frame, Group.ICON_KEY)
    if shown and not room then
        data.icon:SetAction(nil)
        data.icon:Hide()
        return
    end
    local refill
    if shown then
        refill = SignsWaiting(frame, data)
    else
        refill = room and data.need ~= nil
    end
    if refill and not data.refill then
        data.refill = true
        C_Timer.After(0, function()
            data.refill = nil
            Group.Fill(frame)
        end)
    end
end

function Group.Icon(frame)
    local data = GF.Data(OWNER, frame)
    if not data then return nil end
    if data.icon then return data.icon end
    if ns.InCombat() then return nil end   -- nach dem Kampf prüft ezBuff neu und legt es dann an
    count = count + 1
    local width, height = SlotSize(frame, ICON_SIZE, ICON_SIZE)
    local place = GF.SlotAnchor and GF.SlotAnchor(OWNER, frame, Group.SLOT, Group.ICON_KEY,
        function(_, fits) Group.OnPlaced(frame, fits) end)
    local knopf = Core.SecureButton(Group.ICON_PREFIX .. count, { owner = OWNER, parent = frame,
        clicks = "LeftButtonUp", hideInCombat = true, shown = false, size = { width, height },
        anchor = place, attributes = { [Group.UNIT_FROM_PARENT] = true },
        onCreate = function(own) BuildIcon(own, frame) end })
    Group.PassRightClick(knopf)
    data.icon = knopf
    return knopf
end

-- Rechtsklick auf das Symbol erreicht Blizzards Rahmen darunter (sein Menü mit der Segen-Wahl): Der Knopf nimmt nur
-- Linksklicks an, schluckte aber jeden Mausklick. SetPassThroughButtons ist geschützt – knopf:Do (Core.SecureButton)
-- führt es nur außerhalb des Kampfes aus und holt es sonst nach dem Kampf nach.
Group.PASS_THROUGH = "RightButton"
function Group.PassRightClick(knopf)
    if type(knopf) ~= "table" or type(knopf.Do) ~= "function" then return false end
    return knopf:Do(function(own)
        if type(own.SetPassThroughButtons) == "function" then own:SetPassThroughButtons(Group.PASS_THROUGH) end
    end, "passThrough")
end

local function Paint(knopf, need)
    local frame = knopf:Frame()
    if not frame or not frame.Icon then return end
    -- Gruppenfassung: ihr eigenes Symbol (Arkane Brillanz statt Arkane Intelligenz) – man sieht, was der Klick wirkt
    local icon = need.groupSpell and Core.Spells.Icon(need.groupSpell) or need.icon
    frame.Icon:SetTexture(icon or Core.ICON_FALLBACK)
    if frame.Icon.SetDesaturated then frame.Icon:SetDesaturated(need.state == "missing") end
    frame.Text:SetText(need.state == "expiring" and Minutes(need.left) and tostring(Minutes(need.left)) or "")
    frame:SetAlpha(need.inRange and 1 or 0.5)
end

local function BuildSigns(kid, frame)
    local size = select(2, SlotSize(frame, SIGN_SIZE * 2 + 1, SIGN_SIZE))
    kid.signSize = size
    kid.Food = kid:CreateTexture(nil, "OVERLAY")
    kid.Food:SetSize(size, size)
    kid.Food:SetPoint("BOTTOMLEFT")
    kid.Food:SetTexture(FOOD_ICON)
    kid.Flask = kid:CreateTexture(nil, "OVERLAY")
    kid.Flask:SetSize(size, size)
    kid.Flask:SetPoint("BOTTOMLEFT", size + 1, 0)
    kid.Flask:SetTexture(FLASK_ICON)
end

local function Signs(frame, entry)
    local show = entry ~= nil and ns.Enabled("groupSigns") and (entry.food or entry.flask)
    local kid = GF.Part(OWNER, frame, Group.SIGNS_KEY)
    if show and not ns.InCombat() and Group.Room(frame, Group.SIGNS_KEY) then
        local width, height = SlotSize(frame, SIGN_SIZE * 2 + 1, SIGN_SIZE)
        kid = GF.Slot(OWNER, frame, Group.SLOT, Group.SIGNS_KEY, { size = { width, height }, level = 4, onCreate = BuildSigns })
        if kid and kid.Food then
            local size = kid.signSize or SIGN_SIZE
            kid.Food:SetShown(entry.food == true)
            kid.Flask:SetShown(entry.flask == true)
            kid.Flask:ClearAllPoints()
            kid.Flask:SetPoint("BOTTOMLEFT", entry.food and (size + 1) or 0, 0)
            kid:Show()
        end
    elseif kid then
        kid:Hide()
    end
end

-- Zeichen für Essen und Fläschchen erklären (Spieltest 20.11.2026: „was soll das rote symbol sein?“ – die Zeichen
-- sitzen am selben Platz wie das Symbol, sind mausdurchlässig und hatten keine Erklärung; Fund des code-reviewers):
-- Abschnitt in Blizzards Einheiten-Tooltip am Gruppen- bzw. Raidrahmen (Core.Tooltip.AddUnitSection, nur lesen),
-- solange die Zeichen an diesem Rahmen zu sehen sind – mit Quelle (Leitlinie 11).
Group.TOOLTIP_KEY, Group.TOOLTIP_ORDER = "ezBuffGroupSigns", 53

-- Blizzards Rahmen zum Tooltip: sein Besitzer oder dessen Eltern-Rahmen, wenn Core.GroupFrames ihn kennt (nur lesen).
local function TooltipFrame(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.GetOwner) ~= "function" then return nil end
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok or ns.IsSecret(owner) or type(owner) ~= "table" then return nil end
    if GF.Unit(owner) then return owner end
    if type(owner.GetParent) ~= "function" then return nil end
    local okParent, parent = pcall(owner.GetParent, owner)
    if okParent and not ns.IsSecret(parent) and type(parent) == "table" and GF.Unit(parent) then return parent end
    return nil
end

-- Zeilen zu den sichtbaren Zeichen eines Rahmens: { text … } (leer, wenn keine zu sehen sind).
function Group.SignLines(frame)
    local data = type(frame) == "table" and GF.Data(OWNER, frame)
    local kid = type(frame) == "table" and GF.Part(OWNER, frame, Group.SIGNS_KEY)
    local entry = data and data.entry
    if not (entry and kid and kid:IsShown()) then return {} end
    local lines = {}
    if entry.food and kid.Food and kid.Food:IsShown() then lines[#lines + 1] = L.MISSING_FOOD end
    if entry.flask and kid.Flask and kid.Flask:IsShown() then lines[#lines + 1] = L.GROUP_FLASK end
    return lines
end

function Group.AddTooltip(tooltip)
    if not GF then return 0 end
    local lines = Group.SignLines(TooltipFrame(tooltip))
    if #lines == 0 then return 0 end
    if Core.Tooltip and Core.Tooltip.Gap then Core.Tooltip.Gap(tooltip) end
    Core.TipLine(tooltip, L.GROUP_SIGNS_HEAD, "normal")
    for _, text in ipairs(lines) do Core.TipLine(tooltip, text, "highlight") end
    Core.TipLine(tooltip, L.GROUP_SIGNS_SOURCE:format(ns.PathText("OPT_HEADER_GROUP", "OPT_groupSigns")), "hint", true)
    return #lines
end

if Core.Tooltip and Core.Tooltip.AddUnitSection then
    Core.Tooltip.AddUnitSection(Group.TOOLTIP_KEY, Group.TOOLTIP_ORDER, function(tooltip) Group.AddTooltip(tooltip) end, OWNER)
end

-- Einen Rahmen neu füllen (nach jeder Prüfung, bei neuem Mitglied, nach dem Kampf).
function Group.Fill(frame, unit)
    if type(frame) ~= "table" then return end
    unit = unit or GF.Unit(frame)
    local data = GF.Data(OWNER, frame)
    if not data then return end
    local entry = Group.Active() and not ns.InCombat() and Group.Entry(unit) or nil
    local need = Group.FirstNeed(entry)
    data.unit, data.entry, data.need = unit, entry, need
    if need and Group.Room(frame, Group.ICON_KEY) then
        local knopf = Group.Icon(frame)
        if knopf then
            -- ohne unit: die Einheit liest Blizzards Vorlage aus dem Rahmen (Group.UNIT_FROM_PARENT)
            knopf:SetAction({ type = "spell", spell = Group.CastSpell(need) })
            Paint(knopf, need)
            knopf:Show()
        end
    elseif data.icon then
        data.icon:SetAction(nil)
        data.icon:Hide()
    end
    Signs(frame, entry)
end

function Group.Clear(frame)
    local data = type(frame) == "table" and GF.Data(OWNER, frame)
    if not data then return end
    data.entry, data.need = nil, nil
    if data.icon then
        data.icon:SetAction(nil)
        data.icon:Hide()
    end
    local kid = GF.Part(OWNER, frame, "signs")
    if kid then kid:Hide() end
end

function Group.RefreshAll()
    if not GF then return 0 end
    local shown = 0
    for _, item in ipairs(GF.List()) do
        Group.Fill(item.frame, item.unit)
        local data = GF.Data(OWNER, item.frame)
        if data and data.need then shown = shown + 1 end
    end
    Group.PrepareNext()
    return shown
end

-- Wie viele Symbole zeigen gerade etwas? (/ezbuff status)
function Group.Count()
    local shown = 0
    for _, item in ipairs(GF and GF.List() or {}) do
        local data = GF.Data(OWNER, item.frame)
        if data and data.need then shown = shown + 1 end
    end
    return shown
end

---------------------------------------------------------------------------
-- Durchbuffen: ein Knopf, eine Taste, je Druck ein Zauber
---------------------------------------------------------------------------

local function UnitOrder(unit)
    if unit == "player" then return 0 end
    local kind, index = unit:match("^(%a+)(%d+)$")
    return (kind == "party" and 100 or 200) + (tonumber(index) or 0)
end

function Group.MarkRecent(unit, key)
    if type(unit) == "string" and key ~= nil then recent[unit .. ":" .. tostring(key)] = GetTime() end
    if type(unit) == "string" and unit ~= "player" and ns.Value(UnitIsUnit, unit, "player") ~= true then
        lastOther = { unit = unit, at = GetTime() }
    end
end

-- Einheit, auf die ein Klick (Symbol am Rahmen, Durchbuffen) eben einen Buff gewirkt hat, wenn es nicht du
-- selbst warst und der Klick höchstens seconds (Standard Group.OTHER_WINDOW) her ist; sonst nil.
-- Check.CastOnOther fragt das, damit ein Segen auf einem anderen Mitglied nicht als deine Wahl gemerkt wird.
Group.OTHER_WINDOW = 2
function Group.RecentOther(seconds)
    if not lastOther or GetTime() - lastOther.at >= (seconds or Group.OTHER_WINDOW) then return nil end
    return lastOther.unit
end

local function IsRecent(unit, key)
    local at = recent[unit .. ":" .. tostring(key)]
    return at ~= nil and GetTime() - at < Group.RECENT
end

-- Jetzt in Reichweite? Bei jedem Druck frisch gefragt, in beide Richtungen – die gemerkte Angabe der letzten
-- Prüfung (bis zu 15 s alt) zählt nur, wenn es die Abfrage nicht gibt. Check.InRange: unbekannt zählt als „ja“ –
-- dann meldet Blizzard beim Wirken selbst „Außer Reichweite“; gesperrte Werte prüft ezCore.
local function InRangeNow(need, unit)
    local check = ns.Check.InRange
    if type(check) == "function" then return check(need.spell, unit) ~= false end
    return need.inRange == true
end

-- Nächster Zauber: Einheit, Eintrag – erst alles, was fehlt, dann was ausläuft; nur in Reichweite.
-- Ohne Treffer: nil, nil, Name des ersten Mitglieds, dem etwas fehlt, das aber außer Reichweite ist (sonst nil).
function Group.Next()
    if not Group.Active() or ns.InCombat() then return nil end
    local units = {}
    for unit in pairs(ns.Check.ByUnit()) do units[#units + 1] = unit end
    table.sort(units, function(a, b) return UnitOrder(a) < UnitOrder(b) end)
    local far
    for _, state in ipairs({ "missing", "expiring" }) do
        for _, unit in ipairs(units) do
            local entry = ns.Check.ByUnit()[unit]
            for _, need in ipairs(entry.needs or {}) do
                if need.state == state and not IsRecent(unit, need.key) then
                    if InRangeNow(need, unit) then return unit, need end
                    far = far or entry.name or unit
                end
            end
        end
        -- Allein: deine eigenen Buffs (Check.SoloNeeds; Empfehlung umgesetzt, Antwort offen, 15.11.2026)
        if #units == 0 and ns.Check.SoloNeeds then
            for _, need in ipairs(ns.Check.SoloNeeds()) do
                if need.state == state and not IsRecent("player", need.key) then return "player", need end
            end
        end
    end
    return nil, nil, far
end

-- Aktion des Knopfs auf den nächsten Zauber setzen (nur außerhalb des Kampfes; auch im PreClick).
function Group.PrepareNext()
    if not nextButton or ns.InCombat() then return false end
    local unit, need, far = Group.Next()
    nextTarget = unit and { unit = unit, need = need } or nil
    nextFar = not unit and far or nil
    if unit then
        nextButton:SetAction({ type = "spell", spell = Group.CastSpell(need), unit = unit })
    else
        nextButton:SetAction(nil)
    end
    return unit ~= nil
end

function Group.NextButton()
    if nextButton then return nextButton end
    local _, holder = ns.Button.Frame()
    nextButton = Core.SecureButton(Group.NEXT_NAME, { owner = OWNER, parent = holder, shown = false,
        onCreate = function(frame)
            frame:SetScript("PreClick", function()
                if not ns.InCombat() then Group.PrepareNext() end
            end)
            frame:SetScript("PostClick", function()
                if ns.InCombat() then return end
                local target = nextTarget
                if target then
                    Group.MarkCast(target.unit, target.need)
                elseif nextFar then
                    -- Allen, denen etwas fehlt, ist der Weg zu weit: sagen, wer (kein Ausweichen auf ein anderes Ziel)
                    ns.Print(L.GROUP_NEXT_FAR:format(Core.ShortName(nextFar) or nextFar))
                elseif Group.Active() then
                    -- allein (Check.SoloNeeds) ein eigener Text: dann gibt es keine Gruppe, der etwas fehlen könnte
                    ns.Print(ns.InGroup() and L.GROUP_NEXT_NONE or L.GROUP_NEXT_NONE_SOLO)
                end
                Group.PrepareNext()
                C_Timer.After(0.5, function() ns.Check.Request() end)
            end)
        end })
    return nextButton
end

-- Taste für „Durchbuffen“ (Blizzards Tastaturbelegung): Text für Tooltip und Status. Wie beim Buff-Knopf über
-- ezCores Tasten-Dienst (Eintrag Group.KEY_ID, nennt auch eine zweite Taste); nur ohne ihn selbst nachsehen.
function Group.Key()
    if ns.Button and ns.Button.KeyText then
        local text, served = ns.Button.KeyText(Group.KEY_ID)
        if served then return text end
    end
    local key = Core.Call(GetBindingKey, Group.BINDING)
    if ns.IsSecret(key) or type(key) ~= "string" or key == "" then return nil end
    return (Core.Call(GetBindingText, key)) or key
end

function Group.KeyLine()
    local key = Group.Key()
    if key then return L.GROUP_NEXT_KEY:format(key) end
    return L.GROUP_NEXT_UNBOUND:format(ns.PathText("OPT_HEADER_GROUP", "OPT_GROUP_KEY"))
end

-- Einstellungen » Gruppe » „Taste festlegen“: Blizzards Tastaturbelegung öffnen – derselbe Weg wie der Knopf unter
-- „Allgemein“ (Button.OpenKeyBindings: ezCores Tasten-Dienst Core.Keys.Open, im Kampf nur ein Hinweis).
function Group.OpenKeyBindings()
    return ns.Button.OpenKeyBindings()
end

---------------------------------------------------------------------------
-- Segen-Wahl im Rechtsklick-Menü des Rahmens (Paladin)
---------------------------------------------------------------------------

-- Gelernte Segen: { { key, spell, name } } (leer für andere Klassen).
function Group.Blessings()
    local out = {}
    for _, group in ipairs(ns.Check.Groups(ns.playerClass)) do
        if group.kind == "blessing" then
            for _, entry in ipairs(group.entries) do
                local spell = ns.Buffs.BestRank(entry.key)
                if spell then out[#out + 1] = { key = entry.key, spell = spell, name = ns.Buffs.Name(entry, spell) } end
            end
        end
    end
    return out
end

function Group.AddMenu(root, contextData)
    if not Group.Active() or type(root) ~= "table" or type(contextData) ~= "table" then return false end
    local unit = contextData.unit
    if ns.IsSecret(unit) or type(unit) ~= "string" then return false end
    local _, class = UnitClass(unit)
    class = ns.Plain(class)
    if type(class) ~= "string" then return false end
    local list = Group.Blessings()
    if #list == 0 then return false end
    root:CreateDivider()
    local sub = root:CreateButton(L.MENU_BLESSING:format(Core.ClassName(class) or class))
    sub:CreateRadio(L.MENU_BLESSING_AUTO, function() return ns.Check.BlessingFor(class) == nil end,
        function() ns.Check.SetBlessing(class, nil) end)
    for _, item in ipairs(list) do
        sub:CreateRadio(item.name, function() return ns.Check.BlessingFor(class) == item.key end,
            function() ns.Check.SetBlessing(class, item.key) end)
    end
    Group.AddPlayerMenu(sub, unit, class, list)
    return true
end

-- Zweite Stufe „Für <Name>“ (Entscheidung des Nutzers 13.11.2026 „Zusätzlich je Spieler“): eine Wahl für genau
-- diesen Spieler überstimmt die Klasse, „Wie Klasse“ löscht sie. Nicht für dich selbst (deine eigenen Buffs wählt
-- ezBuff wie bisher) und nicht bei gesperrtem Namen (Check.PlayerKey gibt nil – nichts wird gespeichert).
function Group.AddPlayerMenu(sub, unit, class, list)
    if unit == "player" or ns.Value(UnitIsUnit, unit, "player") == true then return false end
    local who, name = ns.Check.PlayerKey(unit)
    if not who then return false end
    if sub.CreateDivider then sub:CreateDivider() end
    local player = sub:CreateButton(L.MENU_BLESSING_PLAYER:format(Core.ShortName(name)))
    player:CreateRadio(L.MENU_BLESSING_LIKE_CLASS, function() return ns.Check.PlayerBlessing(who) == nil end,
        function() ns.Check.SetPlayerBlessing(who, nil) end)
    for _, item in ipairs(list) do
        player:CreateRadio(item.name, function() return ns.Check.PlayerBlessing(who) == item.key end,
            function() ns.Check.SetPlayerBlessing(who, item.key, class, name) end)
    end
    return true
end

-- Einstellungen → Gruppe → „Segen für <Klasse>“ (Leitlinie 3: die Wahl aus dem Rechtsklick-Menü auch sichtbar als
-- Auswahlfeld, Options.lua). Dieselbe Quelle wie das Menü (Check.BlessingFor/SetBlessing, je Charakter); Group.AUTO
-- steht für „Wie für dich“ (keine Wahl gespeichert).
Group.AUTO = "auto"

-- Nur Paladine sehen die Auswahlfelder (Blizzards AddShownPredicate).
function Group.BlessingSettingsShown() return ns.playerClass == "PALADIN" end

-- Einträge eines Auswahlfelds: { { Wert, Text } … } – „Wie für dich“, dann die gelernten Segen.
function Group.BlessingChoices()
    local list = { { Group.AUTO, L.MENU_BLESSING_AUTO } }
    for _, item in ipairs(Group.Blessings()) do list[#list + 1] = { item.key, item.name } end
    return list
end

function Group.BlessingValue(class)
    return ns.Check.BlessingFor(class) or Group.AUTO
end

function Group.SetBlessingValue(class, value)
    if ns.IsSecret(value) or (value ~= nil and type(value) ~= "string") then return false end
    if value == Group.AUTO or value == "" then value = nil end
    return ns.Check.SetBlessing(class, value)
end

-- Anzeigename eines Segens aus seinem Buff-Schlüssel (für die Liste der Einzelwahlen).
function Group.BlessingName(key)
    for _, group in ipairs(ns.Check.Groups(ns.playerClass)) do
        if group.kind == "blessing" then
            for _, entry in ipairs(group.entries) do
                if entry.key == key then return ns.Buffs.Name(entry, ns.Buffs.BestRank(key)) end
            end
        end
    end
    return tostring(key)
end

-- Liste der Einzelwahlen als Zeilen „Name: Segen“ (Klassenfarbe), auch für Spieler außerhalb der Gruppe.
function Group.PlayerBlessingLines()
    local lines = {}
    for _, item in ipairs(ns.Check.PlayerBlessings()) do
        local name = Core.ShortName(item.name)
        if item.class then name = Core.ClassText(name, item.class) end
        lines[#lines + 1] = L.OPT_PLAYER_BLESSINGS_LINE:format(name, Group.BlessingName(item.blessing))
    end
    return lines
end

-- Tooltip der Zeile „Segen je Spieler“ (Einstellungen → Erweitert): Erklärung und die Liste selbst.
function Group.PlayerBlessingsTip()
    local lines = Group.PlayerBlessingLines()
    local list = #lines > 0 and table.concat(lines, "\n") or L.OPT_PLAYER_BLESSINGS_NONE
    return L.OPT_PLAYER_BLESSINGS_TIP .. "\n\n" .. list
end

-- Knopf „Liste zeigen“: die Einzelwahlen im Chat.
function Group.PrintPlayerBlessings()
    local lines = Group.PlayerBlessingLines()
    if #lines == 0 then
        ns.Print(L.OPT_PLAYER_BLESSINGS_NONE)
        return 0
    end
    ns.Print(L.OPT_PLAYER_BLESSINGS_HEAD:format(#lines))
    for _, line in ipairs(lines) do ns.Print("  " .. line) end
    return #lines
end

-- Knopf „Einzelwahlen löschen“: nach Rückfrage alle Einzelwahlen dieses Charakters löschen (die Wahl je Klasse
-- bleibt).
function Group.ClearPlayerBlessings()
    local n = #ns.Check.PlayerBlessings()
    if n == 0 then
        ns.Print(L.OPT_PLAYER_BLESSINGS_NONE)
        return false
    end
    Core.Confirm(L.OPT_CLEAR_PLAYERS_ASK:format(n), function()
        ns.Print(L.OPT_CLEAR_PLAYERS_DONE:format(ns.Check.ClearPlayerBlessings()))
    end)
    return true
end

function Group.HookMenus()
    if menuHooked then return true end
    if not (Menu and type(Menu.ModifyMenu) == "function") then return false end
    for _, tag in ipairs(Group.MENUS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData) ns.Try("Menu", Group.AddMenu, root, contextData) end)
    end
    menuHooked = true
    return true
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- Kampfbeginn: Die Sperre greift erst nach diesem Ereignis – jetzt noch alle Aktionen leeren und die Zeichen
-- ausblenden (fremde Auren sind im Kampf unlesbar, die Einheiten der Rahmen können wechseln).
function Group.OnCombatStart()
    if nextButton then nextButton:SetAction(nil) end
    nextTarget, nextFar = nil, nil
    for _, item in ipairs(GF and GF.List() or {}) do Group.Clear(item.frame) end
end

function Group.Watch()
    if watching or not GF then return watching == true end
    watching = GF.Watch(OWNER, {
        onAdd = function(frame, unit) Group.Fill(frame, unit) end,
        onUnit = function(frame, unit) Group.Fill(frame, unit) end,
        onRemove = function(frame) Group.Clear(frame) end,
    }) == true
    return watching
end

ns.OnReady(function()
    Group.NextButton()
    Group.Watch()
    Group.HookMenus()
    ns.Listen("TASKS", Group.RefreshAll)
    ns.On("PLAYER_REGEN_DISABLED", Group.OnCombatStart)
end)
