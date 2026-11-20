local _, ns = ...
local Core = ezCore

--[[
    Blizzards Auren-Reihe als Dienst (Wunsch vom 13.11.2026: ezCombat für die DoT-Reihe, ezHeal für eigene HoTs am
    Gruppenrahmen). Grundlage ist Blizzards CustomAuraContainerTemplate (Rahmentyp „AuraContainer“, Addon
    Blizzard_AuraContainer, Forever-Quelle 1.60.1.70938): Blizzard sammelt, sortiert und ordnet die Auren selbst an –
    auch dann, wenn ihre Werte im Kampf geheim sind. Befund dazu: docs/roadmap/ezCombat.md, „Geprüft:
    CustomAuraContainerTemplate“.

    Regeln des Dienstes (Leitlinie 5):
      - Anlegen, SetUnit, AddAuraGroup, Gruppen ein/aus, Zeigen und Verankern nur außerhalb des Kampfes. Im Kampf
        merkt sich der Dienst den Soll-Zustand und holt ihn über Core.AfterCombat nach (ein Eintrag je Reihe unter
        QUEUE_PREFIX .. owner .. ":" .. laufende Nummer der Reihe; der letzte Wunsch je Einheit, Gruppe,
        Sichtbarkeit und Lage gewinnt).
      - Zeigt der Container im Kampf etwas Falsches – eine andere Einheit als gewünscht (Blizzard hat den
        Gruppenrahmen neu belegt) oder er soll weg (Release, Hide) –, macht der Dienst ihn bis zum Nachholen nur
        durchsichtig (SetAlpha 0 am eigenen Container; die Deckkraft ist keine geschützte Eigenschaft) und danach
        wieder voll sichtbar (Gesamtreview 18.11.2026, T4-NG1: sonst zeigte ezHeals HoT-Reihe bis Kampfende die HoTs
        des vorigen Mitglieds). reihe:Muted() → true, solange das gilt.
      - Nie zurücklesen: Was angewendet ist, merkt der Dienst selbst. Blizzards Knöpfe in der Reihe sind für Addons
        gesperrt, sobald Auren geheim sind – Werte daraus gibt es nicht (Leuchten am Aktionsknopf bleibt Sache des
        Moduls, z. B. ezCombats eigene Abfrage).
      - Jeder Aufruf an Blizzards Rahmen läuft per pcall; Fehler stehen in der Fehlerliste.
      - Nach dem ersten AddAuraGroup laufen am Container keine fremden Layout-Skripte mehr: eigene Rahmen, die daran
        hängen, brauchen Blizzards Vorlage Core.AuraRows.ANCHOR_TEMPLATE beim Anlegen.

      Core.AuraRow(owner, key, opts) → reihe | nil, grund
        owner  Modulname (Fehlerliste, Schlüssel der Warteschlange)
        key    eigener Schlüssel des Moduls (Text, Zahl oder Tabelle, z. B. Blizzards Gruppenrahmen); derselbe
               owner und key liefern dieselbe Reihe (opts gelten zusätzlich: neue Einheit, Lage, weitere Gruppen)
        opts   parent    Elternrahmen (Pflicht beim ersten Aufruf; z. B. TargetFrame oder ein Gruppenrahmen)
               unit      Einheit, z. B. "target" oder "party1"
               anchor    { punkt, zu, zuPunkt, x, y } (zu Standard: parent) | fn(rahmen, reihe)
               slot      { platz, schlüssel } statt anchor: benannter Platz an Blizzards Gruppenrahmen (parent),
                         Lage aus Core.GroupFrames.SLOTS (z. B. { "midRight", "hots" } für ezHeals HoT-Reihe);
                         reicht der Platz nicht (Core.GroupFrames.SlotFits, etwa das Mittelband mit Blizzards
                         Kraftleiste), bleibt die Reihe ausgeblendet, bis er wieder reicht (shown bleibt der Wunsch);
                         nach jedem Anwenden meldet sich die Reihe bei Core.GroupFrames.Changed (die Mitte rückt
                         nach) – und kurz nach jedem UNIT_AURA ihrer Einheit, wenn Blizzard die Reihe selbst
                         breiter oder schmaler macht (im Kampf gemerkt, danach gemeldet; AR.OnUnitAura)
               groups    { { schlüssel, filter, optionen } … }   wie reihe:AddAuraGroup
               shown     true | false (false: ausgeblendet anlegen; sonst "invalid")
        grund  "missing" (der Client kennt die Vorlage nicht), "invalid" (Parameter), "secret" (geheimer Wert)
               – im Kampf entsteht die Reihe trotzdem (ohne Rahmen), zweiter Wert "combat"

      Methoden, die etwas ändern, geben zurück:
        true               sofort erledigt
        false, "combat"    gemerkt, läuft nach dem Kampf (reihe:Pending() > 0)
        false, grund       "invalid", "secret", "missing" (Vorlage oder Methode fehlt), "taken" (Gruppe gibt es
                           schon), "unknown" (Gruppe gibt es nicht), "error" (steht in der Fehlerliste)

      reihe:SetUnit(einheit)                       einheit nil: keine Einheit (Reihe ausgeblendet)
      reihe:AddAuraGroup(schlüssel, filter, optionen)
                                                   filter wie Blizzards Auren-Filter ("HARMFUL|PLAYER"); optionen
                                                   gehen unverändert an Blizzard (maxFrameCount, candidateFilters,
                                                   layout, templateNames, initializeFrame, sortMethod …)
      reihe:SetEnabled(schlüssel, an)              eine Gruppe ein- oder ausschalten (Blizzards SetAuraGroupEnabled)
      reihe:SetEnabled(an)                         die ganze Reihe zeigen oder ausblenden
      reihe:Show() / :Hide() / :Shown()            dasselbe; Shown → gewünschte Sichtbarkeit
      reihe:Anchor(punkt, zu, zuPunkt, x, y) | reihe:Anchor(fn(rahmen, reihe))
      reihe:Do(fn(rahmen, reihe), schlüssel)       weiteres Geschütztes außerhalb des Kampfes (z. B.
                                                   SetAuraGroupMaxFrameCount); derselbe Schlüssel ersetzt
      reihe:Release()                              ausblenden, Einheit lösen (der Rahmen bleibt – derselbe owner
                                                   und key nutzen ihn weiter)
      reihe:Flush()                                Wartendes jetzt anwenden (macht der Dienst nach dem Kampf selbst)
      reihe:Frame() → Rahmen | nil   :Owner()   :Key()   :Unit() → gewünschte Einheit
      reihe:Groups() → { schlüssel … } gewünschte Gruppen in der Reihenfolge des Anmeldens   :Pending() → Anzahl

      Core.AuraRows.Available() → true | false | nil (im Kampf noch unbekannt)     kennt der Client die Vorlage?
      Core.AuraRows.Get(owner, key) → reihe | nil     .List() → { reihe … }     .Count() → Reihen, davon wartend
      Core.AuraRows.StatusLine() → Zeile für /ez status oder nil
      Core.AuraRows.OnUnitAura(einheit) → true | false   .FlushAuras() → Anzahl     intern (Reihen an Plätzen)
      Core.AuraRows.TEMPLATE, .FRAME_TYPE, .ANCHOR_TEMPLATE, .QUEUE_PREFIX, .AURA_DELAY, .AURA_KEY

    Ausbau Welle 8 (ST-11, EC-105 bis EC-108; Entscheidung des Nutzers 13.11.2026 „Ja, ganz umstellen“ – was
    ezCombats eigene DoT-Reihe kann, kommt hierher):
      Knopf-Vorlage   optionen.button = true | { size, numbers, tooltip, anchor, pandemic, stable } an einer Gruppe
                      (oder AR.ButtonTemplate(opts) → { initializeFrame }): Symbol wie Blizzards Aktionsknopf
                      (Core.StyleIcon), Spirale rückwärts mit Kante und Zahlen (SetDurationCooldown), Stapelzahl ab 2
                      (SetApplicationCount – Blizzard zeigt sie erst ab 2), Maus aus (tooltip = false) bzw. Blizzards
                      Auren-Tooltip mit eigenem Anker, Reihenfolge stabil (stable: sortMethod AuraInstanceIDOnly – die
                      Instanz-IDs sind nie gesperrt, die Reihenfolge springt nicht).
      Pandemie        pandemic = true: Leuchten in der Farbe „dot“ (Core.GlowColor) als Blizzards Pandemie-Region
                      (AddPandemicRegion): Blizzard zeigt sie selbst, auch bei gesperrten Werten, sobald der Client
                      den Pandemie-Wert liefert (C_UnitAuras.GetRefreshCarryOverDuration; AR.PandemicSupported()).
                      Rückfall für eigene Teile der Module (Blizzards Knöpfe sind bei gesperrten Auren für Addons zu,
                      DenyTaintedAccessWhenAurasAreSecret – dort hilft nur Blizzards eigener Wert):
                        AR.PandemicWindow(info) → Sekunden, Quelle   AR.InPandemic(info) → true | false | nil
                          info = { carryOver, duration, expires, castAt, now } – zuerst Blizzards Wert, dann 30 % der
                          Gesamtdauer (AR.PANDEMIC, wie ezCombats Auras.WarnAt), sonst gezählte Zeit seit dem
                          eigenen Zauber (castAt mit duration aus Core.Spells.AuraSeconds); gesperrte Werte → nil
                        AR.PandemicAlpha(dauerObjekt) → ok, alpha – gesperrt über Blizzards Dauer-Objekt und eine
                          Stufenkurve (EvaluateRemainingPercent), alpha nur an SetAlpha weitergeben, nie vergleichen
                        AR.NoteCast(zauberID, guid) / AR.SinceCast(guid, zauberID) – eigene Zauber (UNIT_SPELLCAST_SUCCEEDED)
      Wissen je GUID  AR.Remember(guid, instanz, daten) / AR.Recall(guid, instanz) / AR.Forget(guid): was über eine
                      Aura offen gelesen wurde, bleibt je Gegner (AR.MEMORY_GUIDS, AR.MEMORY_SECONDS) statt beim
                      Zielwechsel geleert zu werden; AR.StableOrder(guid, instanzen) → dieselben IDs in der Reihenfolge
                      ihres ersten Auftauchens (gesperrte IDs zählen nicht)
      Verschieben     opts.mover = { key, label, owner, width, height, anchor }: Core.Mover führt die Lage eines
                      eigenen Halters (unsichtbarer Rahmen unter UIParent, gespeichert unter key – ein alter Schlüssel
                      wie "ezCombat.dots" gilt mit seiner gemerkten Lage weiter); die Reihe hängt am Halter und setzt
                      keinen eigenen Anker. reihe:Mover() → Teil von Core.Mover, reihe:Holder() → Halter
      Vorschau        reihe:Preview(anzahl, opts) → Beispiel-Knöpfe (true) bzw. false, "combat": eigene Knöpfe in der
                      Optik der Vorlage, als Anhänger mit AR.ANCHOR_TEMPLATE, unter UIParent und am Halter bzw. an der
                      Reihe – zu sehen auch ohne Einheit (für „Zeigen“, „Alles vorführen“, „Teile verschieben“ und den
                      Bearbeitungsmodus); opts { icons, size, spacing, pandemic = Index }; anzahl 0 blendet sie aus.
                      Nur außerhalb des Kampfes. reihe:PreviewButtons() → { knopf … }
]]

local ADDON = "ezCore"
local AR = {}
Core.AuraRows = AR

AR.TEMPLATE = "CustomAuraContainerTemplate"
AR.FRAME_TYPE = "AuraContainer"
AR.ANCHOR_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
AR.QUEUE_PREFIX = "AuraRow:"

local rows, order = {}, {}           -- rows[owner][key] = reihe; order = Reihen in der Reihenfolge des Anlegens
local NONE = {}                      -- Platzhalter „keine Einheit“ (nil lässt sich nicht vergleichen)
local known                          -- Vorlage gefunden (bleibt true, sobald einmal bestätigt)
local auraUnits                      -- [einheit] = true für Reihen an Plätzen (nil: neu sammeln, siehe AuraUnits)
local Row = {}
Row.__index = Row

local function Locked()
    return Core.InCombat and Core.InCombat() == true
end

local function Fail(owner, err, where)
    if Core.Error then Core.Error(owner or ADDON, err, "AuraRow " .. where) end
end

-- Blizzards Methode am eigenen Container rufen (pcall). → true | false, "missing" | "error"
local function Invoke(row, where, method, ...)
    local frame = row.frame
    local ok, fn = pcall(function() return frame[method] end)
    if not ok or type(fn) ~= "function" then return false, "missing" end
    local called, err = pcall(fn, frame, ...)
    if not called then
        Fail(row.owner, err, where)
        return false, "error"
    end
    return true
end

function AR.Available()
    if known then return true end
    if type(Core.TemplateExists) ~= "function" then return false end
    local xml = rawget(_G, "C_XMLUtil")
    -- Ohne C_XMLUtil prüft Core.TemplateExists durch Anlegen – das nur außerhalb des Kampfes
    if not (type(xml) == "table" and type(xml.GetTemplateInfo) == "function") and Locked() then return nil end
    local ok, there = pcall(Core.TemplateExists, AR.FRAME_TYPE, AR.TEMPLATE)
    if ok and there == true then
        known = true
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Soll-Zustand anwenden
---------------------------------------------------------------------------

-- Soll-Sichtbarkeit: der Wunsch (want.shown), an einem benannten Platz nur, solange er reicht (opts.slot)
local function WantShown(row)
    local want = row.want.shown
    -- Ohne Einheit bleibt die Reihe ausgeblendet: Blizzards SetUnit nimmt nur eine Zeichenkette (assert in
    -- Blizzard_AuraContainer.lua, SetUnit), die alte Einheit lässt sich dort nicht abmelden.
    if want and row.want.unit == NONE then return false end
    if want and row.slotName then
        local GF = Core.GroupFrames
        if GF and GF.SlotFits and GF.SlotFits(row.parent, row.slotName, row.owner, row.slotKey) == false then return false end
    end
    return want
end

local function Count(row)
    local n = 0
    if not row.frame and not row.failed then n = n + 1 end
    if row.anchorDirty then n = n + 1 end
    if row.want.unit ~= row.done.unit and row.want.unit ~= row.badUnit then n = n + 1 end
    for _, groupKey in ipairs(row.want.groupOrder) do
        if not row.done.groups[groupKey] and not row.badGroups[groupKey] then n = n + 1 end
        -- Eine Gruppe, die Blizzard abgelehnt hat, lässt sich nie ein- oder ausschalten: wartet nicht
        local wantOn = row.want.enabled[groupKey]
        if wantOn ~= nil and not row.badGroups[groupKey] and wantOn ~= row.done.enabled[groupKey] then n = n + 1 end
    end
    if WantShown(row) ~= row.done.shown then n = n + 1 end
    n = n + #row.todo
    return n
end

local function Create(row)
    if row.frame then return true end
    if type(CreateFrame) ~= "function" then return false, "missing" end
    if AR.Available() == false then
        row.failed = "missing"
        return false, "missing"
    end
    local ok, made = pcall(CreateFrame, AR.FRAME_TYPE, nil, row.parent, AR.TEMPLATE)
    if not ok or type(made) ~= "table" then
        Fail(row.owner, made, "CreateFrame")
        row.failed = "error"
        return false, "error"
    end
    row.frame = made
    row.done.shown = true                -- ein neuer Rahmen ist sichtbar
    row.anchorDirty = true
    return true
end

local function ApplyAnchor(row)
    if not row.anchorDirty then return true end
    local anchor = row.want.anchor
    local frame = row.frame
    local ok, err = pcall(function()
        if type(anchor) == "function" then
            anchor(frame, row)
        elseif type(anchor) == "table" then
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2] or row.parent, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)
        else
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", row.parent, "BOTTOMLEFT", 0, 0)
        end
    end)
    row.anchorDirty = nil
    if not ok then
        Fail(row.owner, err, "Anchor")
        return false, "error"
    end
    return true
end

local function ApplyUnit(row)
    local want = row.want.unit
    if want == row.done.unit or want == row.badUnit then return true end
    -- „keine Einheit“ nie an Blizzard geben (dort assert(type(unitToken) == "string")); WantShown blendet aus
    if want == NONE then
        row.done.unit, row.badUnit = NONE, nil
        auraUnits = nil
        return true
    end
    local ok, why = Invoke(row, "SetUnit", "SetUnit", want)
    if ok then
        row.done.unit, row.badUnit = want, nil
        auraUnits = nil                      -- die Reihe hört jetzt auf eine andere Einheit
    else
        row.badUnit = want                   -- dieselbe Einheit nicht bei jedem Aufruf erneut versuchen
    end
    return ok, why
end

local ToBlizzard        -- optionen einer Gruppe für Blizzard (button → initializeFrame, sortMethod), unten

local function ApplyGroup(row, groupKey)
    if row.done.groups[groupKey] or row.badGroups[groupKey] then return true end
    local g = row.want.groups[groupKey]
    local ok, why = Invoke(row, "AddAuraGroup", "AddAuraGroup", groupKey, g.filter, ToBlizzard(g.options, row))
    if ok then
        row.done.groups[groupKey] = true
        row.done.enabled[groupKey] = true     -- Blizzards neue Gruppen sind eingeschaltet
    else
        row.badGroups[groupKey] = why        -- nicht endlos wiederholen
    end
    return ok, why
end

local function ApplyEnabled(row, groupKey)
    local wantOn = row.want.enabled[groupKey]
    if wantOn == nil or not row.done.groups[groupKey] or wantOn == row.done.enabled[groupKey] then return true end
    local ok, why = Invoke(row, "SetEnabled", "SetAuraGroupEnabled", groupKey, wantOn)
    if ok then row.done.enabled[groupKey] = wantOn end
    return ok, why
end

local function ApplyShown(row)
    local want = WantShown(row)
    if want == row.done.shown then return true end
    local ok, why = Invoke(row, "Show", want and "Show" or "Hide")
    if ok then row.done.shown = want end
    return ok, why
end

-- Reihe an einem benannten Platz: Core.GroupFrames Bescheid geben, dass sich an ihr etwas geändert haben kann
-- (Einheit, Gruppen, Sichtbarkeit, Do) – die Mitte des Rahmens rückt nach. Blizzards Container führt nach dem
-- ersten AddAuraGroup keine fremden Layout-Skripte mehr aus; ein Zuhörer an OnSizeChanged erführe es dort nicht.
local function Notify(row)
    if not (row.slotName and row.frame) then return end
    local GF = Core.GroupFrames
    if not (GF and GF.Changed) then return end
    local ok, err = pcall(GF.Changed, row.frame)
    if not ok then Fail(row.owner, err, "Changed") end
end

---------------------------------------------------------------------------
-- Reihen an benannten Plätzen: Auren kommen und gehen
--
-- Blizzards Container hört selbst auf UNIT_AURA seiner Einheit und setzt danach seine Größe neu (Forever-Quelle
-- Blizzard_AuraContainer.lua: OnEvent_Intrinsic → OnUnitAuraUpdate; Blizzard_CustomAuraContainer.lua:
-- OnLayoutComplete → container:SetSize). Das Modul ruft dabei nichts auf, und OnSizeChanged kommt bei Addons nicht
-- an – ohne eigenen Anlass bliebe die Mitte des Rahmens (ezCombats Zahl) unter den neuen Symbolen stehen. Darum
-- hört der Dienst selbst auf UNIT_AURA, sobald es eine Reihe an einem Platz gibt, und meldet die Reihen dieser
-- Einheit kurz danach (AR.AURA_DELAY: Blizzards Reihe ist dann angeordnet) über Core.GroupFrames.Changed. Im Kampf
-- wird nur gemerkt (ein Eintrag in Core.AfterCombat) – die Mitte setzt Core.GroupFrames ohnehin erst danach.
-- Gesetzt werden nur eigene Teile, in Blizzards Rahmen wird nichts geschrieben (Leitlinie 5).
---------------------------------------------------------------------------

AR.AURA_DELAY = 0.1
AR.AURA_KEY = "AuraRow:auras"

local auraDirty = {}                 -- [einheit] = true: seit dem letzten Melden kam UNIT_AURA
local auraDirtyAll = false           -- UNIT_AURA kam mit gesperrter Einheit: welche Reihe es trifft, ist nicht zu sagen
local auraWaiting = false            -- wartet ein Eintrag in Core.AfterCombat?
local auraHooked = false
local auraSoon

-- Einheiten aller Reihen an Plätzen (angewendeter Stand: auf diese Einheit hört Blizzards Container).
local function AuraUnits()
    if auraUnits then return auraUnits end
    auraUnits = {}
    for _, row in ipairs(order) do
        local unit = row.done.unit
        if row.slotName and row.frame and type(unit) == "string" then auraUnits[unit] = true end
    end
    return auraUnits
end

-- Gemerkte Einheiten abarbeiten: jede sichtbare Reihe an einem Platz meldet sich. → Anzahl der Reihen
function AR.FlushAuras()
    if Locked() then
        if not auraWaiting then
            auraWaiting = true
            Core.AfterCombat(AR.FlushAuras, AR.AURA_KEY, ADDON)
        end
        return 0
    end
    auraWaiting = false
    local units, all, n = auraDirty, auraDirtyAll, 0
    auraDirty, auraDirtyAll = {}, false
    for _, row in ipairs(order) do
        if row.slotName and row.frame and row.done.shown and (all or units[row.done.unit]) then
            Notify(row)
            n = n + 1
        end
    end
    return n
end

-- UNIT_AURA: Einheit merken, kurz danach melden (im Kampf: nach dem Kampf). → true, wenn eine Reihe sie zeigt
-- Im Kampf kommt die Einheit gesperrt an (Forever): Sie wird nicht verglichen, sondern alle Reihen an Plätzen
-- werden vorgemerkt – sonst merkte sich die Reihe im Kampf nichts und holte danach nichts nach (wie W-04).
function AR.OnUnitAura(unit)
    if Core.IsSecret(unit) then
        if next(AuraUnits()) == nil then return false end
        auraDirtyAll = true
    elseif type(unit) ~= "string" or not AuraUnits()[unit] then
        return false
    else
        auraDirty[unit] = true
    end
    if Locked() then
        AR.FlushAuras()
    else
        auraSoon()
    end
    return true
end

-- Zuhörer an UNIT_AURA – erst mit der ersten Reihe an einem Platz (ohne ezHeals HoT-Reihe hört niemand zu).
local function WatchAuras()
    auraUnits = nil
    auraSoon = auraSoon or Core.Throttle(AR.FlushAuras, AR.AURA_DELAY, ADDON)
    if auraHooked or type(Core.RegisterEvent) ~= "function" then return end
    auraHooked = Core.RegisterEvent(ADDON, "UNIT_AURA", function(_, unit) AR.OnUnitAura(unit) end) == true
end

-- Zeigt der Container gerade etwas, das nicht mehr gilt? Eine andere Einheit als gewünscht, oder er ist sichtbar und
-- soll es nicht sein (die Lage am Platz zählt nicht: eine zu schmale Mitte ist kein falscher Inhalt).
local function Stale(row)
    if not row.frame then return false end
    if row.want.unit ~= row.done.unit then return true end
    return row.done.shown == true and not row.want.shown
end

-- Durchsichtig machen bzw. wieder zeigen (T4-NG1). Nur die Deckkraft des eigenen Containers – im Kampf erlaubt,
-- anders als Show/Hide und SetUnit; nichts in Blizzards Tabellen (Leitlinie 5).
local function Mute(row, on)
    if not row.frame or (row.muted or false) == on then return end
    local ok = Invoke(row, "Alpha", "SetAlpha", on and 0 or 1)
    if ok then row.muted = on or nil end
end

-- Alles anwenden, was noch fehlt. → true | false, grund (der erste Grund zählt)
local function Apply(row)
    if Locked() then return false, "combat" end
    local made, why = Create(row)
    if not made then return false, why end
    local result, reason = true, nil
    local function note(ok, r)
        if not ok and result then result, reason = false, r end
    end
    note(ApplyAnchor(row))
    note(ApplyUnit(row))
    for _, groupKey in ipairs(row.want.groupOrder) do note(ApplyGroup(row, groupKey)) end
    for _, groupKey in ipairs(row.want.groupOrder) do note(ApplyEnabled(row, groupKey)) end
    note(ApplyShown(row))
    local todo = row.todo
    row.todo, row.todoByKey = {}, {}
    for _, item in ipairs(todo) do
        local ok, err = pcall(item.fn, row.frame, row)
        if not ok then
            Fail(row.owner, err, "Do")
            note(false, "error")
        end
    end
    Notify(row)
    Mute(row, false)                     -- nach dem Nachholen wieder voll sichtbar (Sichtbarkeit regelt ApplyShown)
    return result, reason
end

-- Eigene laufende Nummer je Reihe: tostring(key) hielte die Schlüssel 1 und "1" (oder Tabellen mit __tostring)
-- nicht auseinander, und eine Reihe ersetzte den wartenden Eintrag der anderen.
local serial = 0

local function QueueKey(row)
    return AR.QUEUE_PREFIX .. row.owner .. ":" .. row.serial
end

-- Nach einer Änderung: sofort anwenden oder für nach dem Kampf vormerken.
local function Commit(row)
    if Locked() then
        Mute(row, Stale(row))
        Core.AfterCombat(function() row:Flush() end, QueueKey(row), ADDON)
        return false, "combat"
    end
    return Apply(row)
end

---------------------------------------------------------------------------
-- Methoden
---------------------------------------------------------------------------

function Row:Flush()
    if Locked() then return false, "combat" end
    if Core.CancelAfterCombat then Core.CancelAfterCombat(QueueKey(self)) end
    return Apply(self)
end

function Row:SetUnit(unit)
    if Core.IsSecret(unit) then return false, "secret" end
    if unit ~= nil and (type(unit) ~= "string" or unit == "") then return false, "invalid" end
    self.want.unit = unit or NONE
    return Commit(self)
end

function Row:AddAuraGroup(groupKey, filter, options)
    if Core.IsSecret(groupKey) or Core.IsSecret(filter) then return false, "secret" end
    if type(groupKey) ~= "string" or groupKey == "" or type(filter) ~= "string" or filter == "" then return false, "invalid" end
    if options ~= nil and type(options) ~= "table" then return false, "invalid" end
    local existing = self.want.groups[groupKey]
    if existing then
        -- Vor dem Anwenden gewinnt der letzte Wunsch; danach kennt Blizzard die Gruppe schon
        if self.done.groups[groupKey] then return false, "taken" end
        existing.filter, existing.options = filter, options
    else
        self.want.groups[groupKey] = { filter = filter, options = options }
        self.want.groupOrder[#self.want.groupOrder + 1] = groupKey
    end
    self.badGroups[groupKey] = nil
    return Commit(self)
end

function Row:SetEnabled(groupKey, on)
    -- Zuerst IsSecret: einen geheimen Wert nie mit nil vergleichen (Leitlinie 6)
    if Core.IsSecret(groupKey) or Core.IsSecret(on) then return false, "secret" end
    if on == nil and type(groupKey) == "boolean" then return self:SetShown(groupKey) end
    if type(groupKey) ~= "string" or type(on) ~= "boolean" then return false, "invalid" end
    if not self.want.groups[groupKey] then return false, "unknown" end
    self.want.enabled[groupKey] = on
    return Commit(self)
end

function Row:SetShown(on)
    if Core.IsSecret(on) then return false, "secret" end
    self.want.shown = on and true or false
    return Commit(self)
end

function Row:Show() return self:SetShown(true) end
function Row:Hide() return self:SetShown(false) end
function Row:Shown() return self.want.shown end

function Row:Anchor(point, relative, relPoint, x, y)
    if type(point) == "function" then
        self.want.anchor = point
    else
        if Core.IsSecret(point) or Core.IsSecret(relative) or Core.IsSecret(relPoint) or Core.IsSecret(x) or Core.IsSecret(y) then return false, "secret" end
        if type(point) ~= "string" or (relPoint ~= nil and type(relPoint) ~= "string")
            or (x ~= nil and type(x) ~= "number") or (y ~= nil and type(y) ~= "number")
            or (relative ~= nil and type(relative) ~= "table" and type(relative) ~= "string") then
            return false, "invalid"
        end
        self.want.anchor = { point, relative, relPoint, x, y }
    end
    self.anchorDirty = true
    return Commit(self)
end

function Row:Do(fn, key)
    if type(fn) ~= "function" then return false, "invalid" end
    if Core.IsSecret(key) then return false, "secret" end
    if key ~= nil and self.todoByKey[key] then
        self.todoByKey[key].fn = fn
    else
        local item = { fn = fn }
        self.todo[#self.todo + 1] = item
        if key ~= nil then self.todoByKey[key] = item end
    end
    return Commit(self)
end

function Row:Release()
    self.want.unit = NONE
    self.want.shown = false
    return Commit(self)
end

function Row:Mover() return self.moverPart end
function Row:Holder() return self.holder end

function Row:Frame() return self.frame end
function Row:Owner() return self.owner end
function Row:Key() return self.key end
function Row:Unit()
    local unit = self.want.unit
    if unit == NONE then return nil end
    return unit
end
function Row:Groups()
    local out = {}
    for i, groupKey in ipairs(self.want.groupOrder) do out[i] = groupKey end
    return out
end
function Row:Pending()
    return Count(self)
end
function Row:Muted()
    return self.muted == true
end

---------------------------------------------------------------------------
-- Anlegen
---------------------------------------------------------------------------

-- Jeder Wert zuerst über IsSecret, erst danach Vergleiche (auch mit nil oder "") – Leitlinie 6.
local function CheckOpts(opts)
    if opts == nil then return true end
    if type(opts) ~= "table" then return false, "invalid" end
    if Core.IsSecret(opts.parent) or Core.IsSecret(opts.unit) or Core.IsSecret(opts.shown) or Core.IsSecret(opts.groups) or Core.IsSecret(opts.anchor) then
        return false, "secret"
    end
    if opts.parent ~= nil and type(opts.parent) ~= "table" then return false, "invalid" end
    if opts.unit ~= nil and (type(opts.unit) ~= "string" or opts.unit == "") then return false, "invalid" end
    if opts.shown ~= nil and type(opts.shown) ~= "boolean" then return false, "invalid" end
    if opts.groups ~= nil and type(opts.groups) ~= "table" then return false, "invalid" end
    if Core.IsSecret(opts.mover) then return false, "secret" end
    if opts.mover ~= nil then
        local m = opts.mover
        if type(m) ~= "table" or Core.IsSecret(m.key) or Core.IsSecret(m.label) then
            return false, type(m) == "table" and "secret" or "invalid"
        end
        if type(m.key) ~= "string" or m.key == "" or opts.slot ~= nil or opts.anchor ~= nil then return false, "invalid" end
    end
    if Core.IsSecret(opts.slot) then return false, "secret" end
    if opts.slot ~= nil then
        local s = opts.slot
        if type(s) ~= "table" or Core.IsSecret(s[1]) or Core.IsSecret(s[2]) then return false, type(s) == "table" and "secret" or "invalid" end
        if type(s[1]) ~= "string" or (type(s[2]) ~= "string" and type(s[2]) ~= "number") or opts.anchor ~= nil then
            return false, "invalid"
        end
        local GF = Core.GroupFrames
        if not (GF and GF.SlotSpec and GF.SlotSpec("raid", s[1])) then return false, "invalid" end
    end
    local a = opts.anchor
    if a ~= nil and type(a) ~= "table" and type(a) ~= "function" then return false, "invalid" end
    if type(a) == "table" then
        for i = 1, 5 do if Core.IsSecret(a[i]) then return false, "secret" end end
        if type(a[1]) ~= "string" or (a[3] ~= nil and type(a[3]) ~= "string")
            or (a[4] ~= nil and type(a[4]) ~= "number") or (a[5] ~= nil and type(a[5]) ~= "number")
            or (a[2] ~= nil and type(a[2]) ~= "table" and type(a[2]) ~= "string") then
            return false, "invalid"
        end
    end
    return true
end

-- Eintrag aus opts.groups: { schlüssel, filter, optionen } → true, wenn brauchbar (IsSecret vor jedem Vergleich)
local function GroupEntry(g)
    if type(g) ~= "table" or Core.IsSecret(g[1]) or Core.IsSecret(g[2]) or Core.IsSecret(g[3]) then return false end
    if type(g[1]) ~= "string" or g[1] == "" or type(g[2]) ~= "string" or g[2] == "" then return false end
    return g[3] == nil or type(g[3]) == "table"
end

function Core.AuraRow(owner, key, opts)
    if Core.IsSecret(owner) or Core.IsSecret(key) then return nil, "secret" end
    if type(owner) ~= "string" or owner == "" or key == nil then return nil, "invalid" end
    local okOpts, why = CheckOpts(opts)
    if not okOpts then return nil, why end
    opts = opts or {}
    local byOwner = rows[owner]
    local row = byOwner and byOwner[key]
    if not row then
        if type(opts.parent) ~= "table" then return nil, "invalid" end
        if AR.Available() == false then return nil, "missing" end
        serial = serial + 1
        row = setmetatable({
            owner = owner, key = key, parent = opts.parent, serial = serial,
            want = { unit = NONE, groups = {}, groupOrder = {}, enabled = {}, shown = opts.shown ~= false, anchor = nil },
            done = { unit = NONE, groups = {}, enabled = {}, shown = nil },
            badGroups = {}, todo = {}, todoByKey = {},
        }, Row)
        rows[owner] = byOwner or {}
        rows[owner][key] = row
        order[#order + 1] = row
    elseif opts.shown ~= nil then
        row.want.shown = opts.shown              -- CheckOpts: nicht geheim, true oder false
    end
    row.failed = nil
    local bad
    if opts.unit ~= nil then row.want.unit = opts.unit end
    if opts.slot ~= nil then
        -- Benannter Platz: die Lage kommt aus Core.GroupFrames.SLOTS (eine Stelle für alle Module)
        -- Nach jedem Setzen (auch GF.Relayout nach DefaultCompactUnitFrameSetup) die Sichtbarkeit nachziehen: reicht
        -- der Platz nicht mehr (Kraftleiste an), blendet die Reihe aus, reicht er wieder, zeigt sie sich
        local GF = Core.GroupFrames
        local place = GF and GF.SlotAnchor and GF.SlotAnchor(owner, row.parent, opts.slot[1], opts.slot[2], function()
            if row.frame and not Locked() then ApplyShown(row) end
        end)
        if place then
            row.slotName, row.slotKey = opts.slot[1], opts.slot[2]
            WatchAuras()
            row.want.anchor = function(frame) place(frame) end
            row.anchorDirty = true
        else
            bad = true
        end
    end
    if opts.mover ~= nil and not row.holder then
        -- Core.Mover führt die Lage eines eigenen Halters; die Reihe hängt daran (kein eigener Anker)
        local holder = AR.NewHolder(row, opts.mover)
        if holder then
            row.want.anchor = function(frame)
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            end
            row.anchorDirty = true
        else
            bad = true
        end
    end
    if opts.anchor ~= nil then
        if type(opts.anchor) == "function" then
            row.want.anchor = opts.anchor
        else
            local a = opts.anchor
            row.want.anchor = { a[1], a[2], a[3], a[4], a[5] }
        end
        row.anchorDirty = true
    end
    for _, g in ipairs(opts.groups or {}) do
        if not GroupEntry(g) then
            bad = true
        elseif not row.want.groups[g[1]] then
            row.want.groups[g[1]] = { filter = g[2], options = g[3] }
            row.want.groupOrder[#row.want.groupOrder + 1] = g[1]
        end
    end
    local ok, reason = Commit(row)
    if not ok and reason ~= "combat" and not row.frame then
        -- Ohne Rahmen gibt es die Reihe nicht: vergessen, damit ein späterer Aufruf neu beginnt
        rows[owner][key] = nil
        for i = #order, 1, -1 do if order[i] == row then table.remove(order, i) end end
        return nil, reason
    end
    if bad then return row, "invalid" end
    if not ok then return row, reason end
    return row
end

---------------------------------------------------------------------------
-- Knopf-Vorlage (EC-105): Optik wie Blizzards Aktionsknopf, für jede Gruppe über optionen.button
---------------------------------------------------------------------------

AR.BUTTON_SIZE = 30
AR.PANDEMIC = 0.3                    -- Anteil der Gesamtdauer, den ein neues Setzen mitnimmt (Blizzards Pandemie)
local SORT = rawget(_G, "AuraContainerSortMethod")
AR.SORT_STABLE = type(SORT) == "table" and SORT.AuraInstanceIDOnly or 8   -- Forever-Quelle, AuraContainerShared
AR.GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

local function Try(owner, where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Fail(owner, err, where) end
    return ok
end

-- Teile eines Knopfs anlegen (eigener Knopf der Vorschau oder Blizzards Knopf der Reihe). → Teile
local function BuildButton(frame, spec)
    local size = Core.Num(spec.size) or AR.BUTTON_SIZE
    frame:SetSize(size, size)
    local parts = {}
    parts.icon = Core.StyleIcon(frame)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints()
        if cooldown.SetReverse then cooldown:SetReverse(true) end
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(true) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(spec.numbers == false) end
        parts.cooldown = cooldown
    end
    local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    count:SetJustifyH("RIGHT")
    parts.count = count
    if spec.pandemic then
        local glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
        glow:SetTexture(AR.GLOW_TEXTURE)
        if glow.SetBlendMode then glow:SetBlendMode("ADD") end
        glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -size * 0.45, size * 0.45)
        glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size * 0.45, -size * 0.45)
        glow:SetVertexColor(Core.GlowColor("dot"))
        glow:Hide()
        parts.glow = glow
    end
    return parts
end
AR.BuildButton = BuildButton

-- Rückruf für Blizzards initializeFrame: läuft einmal je neuem Knopf der Reihe, an Blizzards Objekt-Tabelle.
-- Jeder Aufruf an Blizzards Knopf geschützt; was der Client nicht kennt, bleibt weg.
function AR.ButtonTemplate(opts, owner)
    local spec = type(opts) == "table" and opts or {}
    owner = owner or ADDON
    return {
        initializeFrame = function(frame)
            Try(owner, "Vorlage", function()
                local parts = BuildButton(frame, spec)
                if frame.SetIcon then frame:SetIcon(parts.icon) end
                if parts.cooldown and frame.SetDurationCooldown then frame:SetDurationCooldown(parts.cooldown) end
                if frame.SetApplicationCount then frame:SetApplicationCount(parts.count) end
                if parts.glow and frame.AddPandemicRegion then frame:AddPandemicRegion(parts.glow) end
                if spec.tooltip == false then
                    frame:EnableMouse(false)
                elseif type(spec.anchor) == "string" and frame.SetTooltipAnchorPoint then
                    frame:SetTooltipAnchorPoint(spec.anchor, 0, 0)
                end
            end)
        end,
    }
end

-- optionen einer Gruppe für Blizzard: button wird zu initializeFrame (eine eigene initializeFrame gewinnt),
-- stable (Standard an der Vorlage) zu sortMethod; der Schlüssel button geht nicht an Blizzard.
ToBlizzard = function(options, row)
    if type(options) ~= "table" or options.button == nil then return options end
    local out = {}
    for k, v in pairs(options) do
        if k ~= "button" then out[k] = v end
    end
    local spec = options.button
    if spec then
        spec = type(spec) == "table" and spec or {}
        if out.initializeFrame == nil then out.initializeFrame = AR.ButtonTemplate(spec, row and row.owner).initializeFrame end
        if spec.stable ~= false and out.sortMethod == nil then out.sortMethod = AR.SORT_STABLE end
        if spec.pandemic and not AR.PandemicSupported() then AR.WatchCasts() end
    end
    return out
end
AR.ToBlizzard = ToBlizzard

---------------------------------------------------------------------------
-- Pandemie-Fenster mit Rückfall (EC-106)
---------------------------------------------------------------------------

-- Liefert der Client Blizzards Pandemie-Wert? (Dann zeigt Blizzard die Pandemie-Region der Vorlage selbst.)
function AR.PandemicSupported()
    local api = rawget(_G, "C_UnitAuras")
    return type(api) == "table" and type(Core.Peek(api, "GetRefreshCarryOverDuration")) == "function"
end

-- Breite des Pandemie-Fensters in Sekunden und ihre Quelle: "blizzard" (carryOver > 0), "duration" (30 % der
-- Gesamtdauer), "cast" (30 % der vom Client gemerkten Dauer des Zaubers, gezählt ab castAt); nil, wenn nichts
-- Lesbares da ist. Jeder Wert zuerst über IsSecret (Leitlinie 6).
function AR.PandemicWindow(info)
    if type(info) ~= "table" then return nil end
    local carry = not Core.IsSecret(info.carryOver) and Core.Num(info.carryOver) or nil
    if carry and carry > 0 then return carry, "blizzard" end
    local duration = not Core.IsSecret(info.duration) and Core.Num(info.duration) or nil
    if duration and duration > 0 then
        local expires = not Core.IsSecret(info.expires) and Core.Num(info.expires) or nil
        local castAt = not Core.IsSecret(info.castAt) and Core.Num(info.castAt) or nil
        local source = (not expires and castAt) and "cast" or "duration"
        return duration * AR.PANDEMIC, source
    end
    return nil
end

-- Steckt die Aura im Pandemie-Fenster? true/false; nil = unbekannt (gesperrt, keine Dauer, kein Ablauf).
-- Ablauf aus expires, sonst aus castAt + duration (selbst gezählte Zeit seit dem eigenen Zauber).
function AR.InPandemic(info)
    if type(info) ~= "table" then return nil end
    local window = AR.PandemicWindow(info)
    if not window then return nil end
    local now = Core.Num(info.now) or Core.Uptime()
    local expires = not Core.IsSecret(info.expires) and Core.Num(info.expires) or nil
    if not expires then
        local castAt = not Core.IsSecret(info.castAt) and Core.Num(info.castAt) or nil
        local duration = not Core.IsSecret(info.duration) and Core.Num(info.duration) or nil
        if not (castAt and duration) then return nil end
        expires = castAt + duration
    end
    local left = expires - now
    return left > 0 and left <= window
end

local pandemicCurve
-- Gesperrte Restzeit: Blizzards Dauer-Objekt wertet den Rest in Prozent über eine Stufenkurve selbst aus
-- (≤ 30 % → 1, sonst 0). → true, alpha (darf gesperrt sein: nur an SetAlpha geben) | false
function AR.PandemicAlpha(durationObject)
    if type(durationObject) ~= "table" and type(durationObject) ~= "userdata" then return false end
    local evaluate = Core.Peek(durationObject, "EvaluateRemainingPercent")
    if type(evaluate) ~= "function" then return false end
    if not pandemicCurve then
        local util = rawget(_G, "C_CurveUtil")
        local create = type(util) == "table" and util.CreateCurve
        if type(create) ~= "function" then return false end
        local ok, curve = pcall(create)
        if not ok or curve == nil then return false end
        local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
        if step ~= nil and curve.SetType then pcall(curve.SetType, curve, step) end
        pcall(curve.AddPoint, curve, 0, 1)
        pcall(curve.AddPoint, curve, AR.PANDEMIC, 0)
        pandemicCurve = curve
    end
    local ok, alpha = pcall(evaluate, durationObject, pandemicCurve)
    if not ok then return false end
    return true, alpha
end

---------------------------------------------------------------------------
-- Wissen je GUID und stabile Reihenfolge (ST-11)
---------------------------------------------------------------------------

AR.MEMORY_GUIDS = 30                 -- so viele Gegner bleiben gemerkt (der am längsten unbenutzte fällt heraus)
AR.MEMORY_SECONDS = 600              -- unberührte Einträge gelten so lange
local memory, memoryOrder = {}, {}   -- memory[guid] = { at, auras = { [instanz] = daten }, order = { … }, casts = { … } }
local seq = 0

local function Plain(v)
    if Core.IsSecret(v) then return nil end
    return v
end

-- Die GUID aus der Reihenfolge nehmen (jede Kopie).
local function Unlist(guid)
    for i = #memoryOrder, 1, -1 do if memoryOrder[i] == guid then table.remove(memoryOrder, i) end end
end

-- Eintrag eines Gegners; zuletzt benutzte GUIDs stehen hinten, der am längsten unbenutzte fällt vorn heraus.
local function Bucket(guid, create)
    guid = Plain(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local now = Core.Uptime()
    local entry = memory[guid]
    if entry and now - entry.at > AR.MEMORY_SECONDS then
        memory[guid] = nil
        entry = nil
    end
    if not entry and not create then
        Unlist(guid)
        return nil
    end
    Unlist(guid)
    memoryOrder[#memoryOrder + 1] = guid
    if not entry then
        entry = { at = now, auras = {}, order = {}, casts = {} }
        memory[guid] = entry
        while #memoryOrder > AR.MEMORY_GUIDS do
            memory[table.remove(memoryOrder, 1)] = nil
        end
    end
    entry.at = now
    return entry
end

-- Offen gelesenes Wissen über eine Aura merken (je Gegner). → true, wenn gemerkt
function AR.Remember(guid, instance, data)
    instance = Core.Num(Plain(instance))
    if not instance or type(data) ~= "table" then return false end
    local entry = Bucket(guid, true)
    if not entry then return false end
    local copy = {}
    for k, v in pairs(data) do
        if not Core.IsSecret(v) then copy[k] = v end
    end
    entry.auras[instance] = copy
    return true
end

-- Gemerktes Wissen über eine Aura dieses Gegners (Kopie) oder nil.
function AR.Recall(guid, instance)
    instance = Core.Num(Plain(instance))
    local entry = instance and Bucket(guid, false)
    local data = entry and entry.auras[instance]
    if not data then return nil end
    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    return copy
end

-- Wissen über einen Gegner vergessen (ohne guid: alles). → true
function AR.Forget(guid)
    if not Core.IsSecret(guid) and guid == nil then
        memory, memoryOrder = {}, {}
        return true
    end
    guid = Plain(guid)
    if type(guid) ~= "string" then return false end
    memory[guid] = nil
    Unlist(guid)
    return true
end

-- Instanz-IDs in der Reihenfolge ihres ersten Auftauchens bei diesem Gegner (neue hinten). Gesperrte oder
-- unlesbare IDs fallen weg. Ohne lesbare GUID: die IDs in der gegebenen Reihenfolge.
function AR.StableOrder(guid, instances)
    local list = {}
    for _, id in ipairs(type(instances) == "table" and instances or {}) do
        local n = Core.Num(Plain(id))
        if n then list[#list + 1] = n end
    end
    local entry = Bucket(guid, true)
    if not entry then return list end
    for _, id in ipairs(list) do
        if not entry.order[id] then
            seq = seq + 1
            entry.order[id] = seq
        end
    end
    table.sort(list, function(a, b) return entry.order[a] < entry.order[b] end)
    return list
end

-- Eigener Zauber auf einen Gegner: Zeitpunkt merken (Rückfall „gezählte Zeit“ des Pandemie-Fensters).
function AR.NoteCast(spellID, guid, at)
    spellID = Core.Num(Plain(spellID))
    local entry = spellID and Bucket(guid, true)
    if not entry then return false end
    entry.casts[spellID] = Core.Num(at) or Core.Uptime()
    return true
end

-- Zeitpunkt des letzten eigenen Zaubers spellID auf diesen Gegner (Core.Uptime) oder nil.
function AR.SinceCast(guid, spellID)
    spellID = Core.Num(Plain(spellID))
    local entry = spellID and Bucket(guid, false)
    return entry and entry.casts[spellID] or nil
end

-- Eigene Zauber mitzählen: UNIT_SPELLCAST_SUCCEEDED des Spielers, Ziel = aktuelles Ziel (offene GUID).
local castHooked = false
function AR.WatchCasts()
    if castHooked or type(Core.RegisterEvent) ~= "function" then return castHooked end
    castHooked = Core.RegisterEvent(ADDON, "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if not Core.IsSecret(unit) and unit ~= "player" then return end
        local guid = Plain(Core.Call(rawget(_G, "UnitGUID"), "target"))
        if guid then AR.NoteCast(spellID, guid) end
    end, { "player" }) == true
    return castHooked
end

---------------------------------------------------------------------------
-- Verschieben (EC-107) und Vorschau (EC-108)
---------------------------------------------------------------------------

-- Halter für Core.Mover: unsichtbarer Rahmen unter UIParent; ohne gemerkte Lage am Elternrahmen der Reihe.
function AR.NewHolder(row, mover)
    local M = Core.Mover
    if not (M and M.Register and type(CreateFrame) == "function") then return nil end
    local size = AR.BUTTON_SIZE
    local ok, holder = pcall(CreateFrame, "Frame", nil, UIParent)
    if not ok or not holder then return nil end
    holder:SetSize(Core.Num(mover.width) or size * 5, Core.Num(mover.height) or size)
    local anchor = type(mover.anchor) == "table" and mover.anchor or { "TOPLEFT", row.parent, "BOTTOMLEFT", 0, 0 }
    local okPart, part = pcall(M.Register, holder, { key = mover.key, label = mover.label or mover.key,
        owner = mover.owner or row.owner, anchor = anchor, protected = true,
        minWidth = Core.Num(mover.width) or size * 5, minHeight = Core.Num(mover.height) or size })
    if not okPart then
        Fail(row.owner, part, "Mover")
        return nil
    end
    row.holder, row.moverPart = holder, part
    return holder
end

-- Beispiel-Knöpfe zeigen bzw. ausblenden (anzahl 0). → true | false, "combat" | "invalid"
function Row:Preview(count, opts)
    if Core.IsSecret(count) then return false, "secret" end
    count = Core.Num(count) or 0
    if count < 0 or count > 40 then return false, "invalid" end
    if Locked() then return false, "combat" end
    opts = type(opts) == "table" and opts or {}
    local buttons = self.preview or {}
    self.preview = buttons
    local size = Core.Num(opts.size) or AR.BUTTON_SIZE
    local spacing = Core.Num(opts.spacing) or 2
    local anchor = self.holder or self.frame or self.parent
    local icons = type(opts.icons) == "table" and opts.icons or {}
    for i = 1, count do
        local b = buttons[i]
        if not b then
            local ok, made = pcall(CreateFrame, "Frame", nil, UIParent, AR.ANCHOR_TEMPLATE)
            if not ok or not made then made = CreateFrame("Frame", nil, UIParent) end
            b = made
            b.parts = BuildButton(b, { size = size, pandemic = true })
            buttons[i] = b
        end
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", anchor, "TOPLEFT", (i - 1) * (size + spacing), 0)
        b.parts.icon:SetTexture(icons[(i - 1) % math.max(#icons, 1) + 1] or "Interface\\Icons\\Spell_Shadow_AbominationExplosion")
        b.parts.count:SetText(i == 2 and "2" or "")
        if b.parts.glow then b.parts.glow:SetShown(opts.pandemic == i) end
        if b.parts.cooldown and b.parts.cooldown.SetCooldown then
            pcall(b.parts.cooldown.SetCooldown, b.parts.cooldown, Core.Uptime() - i * 3, 18)
        end
        b:Show()
    end
    for i = count + 1, #buttons do buttons[i]:Hide() end
    return true
end

function Row:PreviewButtons()
    local out = {}
    for _, b in ipairs(self.preview or {}) do
        if b:IsShown() then out[#out + 1] = b end
    end
    return out
end

function AR.Get(owner, key)
    if Core.IsSecret(owner) or Core.IsSecret(key) or owner == nil or key == nil then return nil end
    return rows[owner] and rows[owner][key] or nil
end

function AR.List()
    local out = {}
    for i, row in ipairs(order) do out[i] = row end
    return out
end

function AR.Count()
    local total, waiting = 0, 0
    for _, row in ipairs(order) do
        total = total + 1
        if row:Pending() > 0 then waiting = waiting + 1 end
    end
    return total, waiting
end

function AR.StatusLine()
    local total, waiting = AR.Count()
    if total == 0 then return nil end
    local L = Core.L
    if waiting > 0 then return L.STATUS_AURAROW_WAITING:format(total, waiting) end
    return L.STATUS_AURAROW:format(total)
end
