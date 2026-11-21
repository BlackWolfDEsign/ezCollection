local _, ns = ...
local Core = ezCore

--[[
    Blizzards Gruppen- und Raidrahmen an einer Stelle finden (Wunsch vom 13.11.2026: Anzeigen an allen fünf Rahmen
    der Gruppe und an den Raidrahmen; Nutzer: ezHeal, ezBuff „Gruppe“, ezCombat Stufe 3). Der Dienst baut keine
    Optik – er sagt den Modulen, welcher Rahmen von Blizzard gerade welche Einheit zeigt, hält ihre eigenen Teile
    je Rahmen und legt eigene, mausdurchlässige Kind-Rahmen nur außerhalb des Kampfes an.
    Nichts wird in Blizzards Rahmen geschrieben (Leitlinie 5): Zuordnung und eigene Teile stehen in eigenen
    schwachen Tabellen, gehört wird nur über hooksecurefunc.

    Woher die Rahmen kommen (Namen aus Blizzards Forever-Quelle, Blizzard_UnitFrame und Blizzard_CompactRaidFrames):
      "raid"    Raidstil: hooksecurefunc("CompactUnitFrame_SetUnit") – CompactPartyFrameMember1–5 (auch „Gruppe im
                Raidstil“), CompactRaidFrameN, CompactRaidGroupNMemberM. Dieselbe Funktion bedient auch
                Namensplaketten (Blizzard_NamePlateBase), Arena- und Begleiterrahmen: zuerst frame:IsForbidden(),
                dann nur die Einheiten player, party1–4, raid1–40 annehmen. Alles andere gilt als „Rahmen fiel weg“.
      "party"   klassische Gruppenrahmen: PartyFrame.PartyMemberFramePool:EnumerateActive() nur lesen
                (Einheit aus memberFrame.unitToken); gezählt, solange der Rahmen sichtbar ist und die Einheit existiert.
      "player"  PlayerFrame – nur in der klassischen Ansicht und nur, solange der Spieler in einer Gruppe ist
                (im Raidstil hat der Spieler seinen eigenen Rahmen CompactPartyFrameMember…).

      Core.GroupFrames.Watch(owner, { onAdd = fn(rahmen, einheit, art), onUnit = fn(rahmen, einheit, alteEinheit, art),
                                      onRemove = fn(rahmen, alteEinheit, art) }) → true | false, "invalid"
          Rückrufe anmelden (einer je owner; erneutes Anmelden ersetzt). onAdd läuft sofort für jeden schon
          bekannten Rahmen. Die Rückrufe können IM KAMPF kommen (Gruppe ändert sich) – Geschütztes dort nur über
          Attach oder Core.SecureButton. Fehler landen in der Fehlerliste.
      Core.GroupFrames.Unwatch(owner)
      Core.GroupFrames.List() → { { frame, unit, kind } … }   sortiert: player, party1–4, raid1–40
      Core.GroupFrames.Frame(einheit) → rahmen, art | nil     sichtbare Rahmen zuerst
      Core.GroupFrames.Unit(rahmen) → einheit, art | nil
      Core.GroupFrames.TooltipUnit(tooltip) → einheit, art | nil   Einheit, wenn der Besitzer des Tooltips oder dessen
          Eltern-Rahmen (Blizzard setzt manche Tooltips an ein Kind, etwa den Manabalken) ein Gruppen- oder Raidrahmen
          ist (Welle 23a, A9; vorher ezHeal Legend.FrameUnit und ezCombat MF.FrameUnit). Nur lesen.
      Core.GroupFrames.IsGroupUnit(einheit) → true | false
      Core.GroupFrames.Data(owner, rahmen) → eigene Tabelle des Moduls für diesen Rahmen (bleibt, solange der Rahmen lebt)
      Core.GroupFrames.Attach(owner, rahmen, schlüssel, opts) → kind | nil, grund
          Eigenen Kind-Rahmen an Blizzards Rahmen hängen (Maus aus, Standard: deckt den Rahmen). Derselbe Schlüssel
          liefert dasselbe Kind (opts gelten neu). Im Kampf: gemerkt, läuft nach dem Kampf über Core.AfterCombat
          → nil, "combat" (bzw. kind, "combat", wenn es das Kind schon gibt und nur Lage/Größe warten).
          opts  frameType  Standard "Frame"          template   Vorlage (kennt der Client sie nicht: ohne sie)
                size = { b, h }                       level      Ebene über Blizzards Rahmen (Standard 1)
                anchor = { punkt, zuPunkt, x, y }     relativ zu Blizzards Rahmen | fn(kind, rahmen) setzt selbst
                onCreate = fn(kind, rahmen, einheit)  einmal nach dem Anlegen – Texturen, Schrift, Balken
          grund "invalid" (Parameter), "secret" (geheimer Wert), "forbidden" (verbotener Rahmen), "untracked"
                (kein bekannter Gruppenrahmen), "missing" (kein CreateFrame), "error" (steht in der Fehlerliste)
      Core.GroupFrames.Part(owner, rahmen, schlüssel) → kind | nil
      Core.GroupFrames.Parts(owner, rahmen) → { [schlüssel] = kind }
      Benannte Plätze (Platzplan, Entscheidung des Nutzers vom 14.11.2026 „Mittelband teilen“): Module fragen den
      Platz ab, statt eigene Anker zu setzen. Lage je Rahmenart in GF.SLOTS (eine Stelle, Abschnitt unten). Jeder
      Platz liegt IM Rahmen (Spielbefund des Nutzers vom 18.11.2026: „buffs und co nicht in einem popup sondern über
      und an dem rahmen, den abstand zu den rahmen untereinander beibehalten“) – nie in der Lücke zum nächsten
      Rahmen; Ausnahmen seit dem Spieltest vom 20.11.2026: klassisch hängen die Balken (topLines) wieder an der
      Unterkante von Blizzards Rahmenbild („wieder am rahmen unten“), die Zahlen stehen rechts daneben ("beside");
      Blizzards Rahmen rücken nicht:
        "topLines"  zwei Linien à 1 px an der Oberkante, ohne Hintergrund (klassisch: Balken direkt unter Blizzards
                    Rahmenbild, je halb so hoch wie der Manabalken, mit Hintergrund; Dicke vom Modul bis line) – ezCombat
        "midLeft"   Mitte links, nach rechts wachsend (klassisch: oben links auf dem Porträt) – ezBuff
        "midRight"  Mitte rechts, nach links wachsend (klassisch: rechts auf dem Lebensbalken) – ezHeal
        "center"    Mitte zwischen midLeft und midRight, nur außerhalb des Kampfes und ab 30 px Höhe
                    (klassisch: auf dem Lebensbalken links neben den HoTs) – ezCombats Zahl und Marken im Raidstil
        "beside"    klassisch: rechts neben den Balken (after topLines), mittig auf ihrer Höhe (Spieltest des
                    Nutzers vom 20.11.2026: „warum sind die zahlen nicht rechts vom balken?“); der Abstand der Rahmen
                    untereinander bleibt. Raidstil: aus (die Rahmen stoßen aneinander) – ezCombats Zahlen und Marken
                    am klassischen Gruppen- und Spielerrahmen
      Core.GroupFrames.Reserve(owner, platz, schlüssel, { size = { b, h }, order }) → true | false, grund
          beim Laden des Moduls: Platz vormerken; mehrere Teile teilen einen Platz in der Reihenfolge order
      Core.GroupFrames.Slot(owner, rahmen, platz, schlüssel, opts) → kind | nil, grund   wie Attach, Lage vom Platz
      Core.GroupFrames.SlotAnchor(owner, rahmen, platz, schlüssel, onPlaced) → fn(region)   für SecureButton/AuraRow/
          Attach; onPlaced(region, passt) nach jedem Setzen (AuraRow blendet aus, wenn das Mittelband nicht reicht)
      Core.GroupFrames.SlotBand(rahmen) → { bottom, top, room, y, left, right, where } | nil   Mittelband im
          Raidstil zwischen Blizzards unterer Aurenreihe (mit Kraftleiste) und Name/bannbaren Debuffs; reicht es
          nicht, bleiben midLeft, midRight und center aus (SlotFits/SlotRoom → false). „Buffs oben“: reicht das
          Mittelband nicht, eine freie Stelle – zwischen Name und Buff-Reihe, sonst unten, sonst oben (where
          "upper" | "bottom" | "top"; left/right = Ränder der Lücke unten bzw. oben)
      Core.GroupFrames.Place(region, rahmen, platz, owner, schlüssel)   setzt die Punkte (nur außerhalb des Kampfes)
      Core.GroupFrames.SlotSize(art, platz, b, h) → b, h   verkleinert auf die Höhe des Platzes (Raidstil 10 px)
      Core.GroupFrames.SlotRoom(rahmen, platz, owner, schlüssel) → passt das Teil, ohne in die sichtbaren Teile
          der Gegenseite zu wachsen? (Raidstil: midLeft ↔ midRight; vor dem Zeigen außerhalb des Kampfes fragen)
      Core.GroupFrames.SlotKind(rahmen) → art   .SlotOrganization(rahmen) → "legacy" | "buffsTop" | "buffsRight"
          (je Rahmen gemerkt; neu gelesen nach Relayout, DefaultCompactUnitFrameSetup oder .DropCache(rahmen))
      Core.GroupFrames.SlotSpec(art, platz, anordnung) → Kopie   .SlotInCombat(art, platz)
      Core.GroupFrames.SlotShift(rahmen, platz) → px   wie weit ein Platz mit point nach außen rückt, weil Blizzard
          dort ein Kind zeigt (shift: beside weicht dem Symbol „nicht da“); ändert es sich, setzt das Modul neu
      Core.GroupFrames.SlotClear(rahmen, platz) → px   wie weit ein Streifen unter dem Rahmen (below) ab der
          sichtbaren Unterkante von Blizzards Rahmenbild (art) tiefer rückt, weil Blizzard dort etwas zeigt (clear:
          Kind wie der Begleiter-Rahmen; clearBelow: Rahmen wie die Klassenleiste, gemessen); ändert es sich, setzt
          das Modul sein Teil außerhalb des Kampfes neu (GF.Slot erneut)
      Core.GroupFrames.SlotDepth(rahmen, platz) → px | nil   höchste Höhe dieses Streifens, damit bis zum nächsten
          Gruppenrahmen darunter GF.SLOT_BELOW_GAP px frei bleiben (next; nil: nichts darunter); Place kürzt danach
      Core.GroupFrames.SlotFits(rahmen, platz, owner, schlüssel) → reicht der Platz (Mindestgröße, Mittelband bzw.
          freie Stelle, Breite für dieses Teil – ohne owner/schlüssel für alles Vorgemerkte)?
      Core.GroupFrames.Changed(teil) → true | false   ein Teil an einem Platz hat sich geändert (Breite, Inhalt),
          ohne dass OnShow/OnHide/OnSizeChanged es melden: die Mitte seines Rahmens neu setzen (Core.AuraRow:
          nach jedem Anwenden und kurz nach UNIT_AURA der Einheit, wenn Blizzard die Reihe selbst breiter macht)
      Core.GroupFrames.Reserved(platz)   .Relayout(rahmen)   .RelayoutWaiting()   .Track(…)   .HookSetup()
      .OnFrameSetup()   intern
      Core.GroupFrames.Refresh() → Anzahl     neu einlesen (macht der Dienst bei GROUP_ROSTER_UPDATE,
                                              PLAYER_ENTERING_WORLD, Bearbeitungsmodus und PartyFrame:UpdatePartyFrames selbst)
      Core.GroupFrames.Count() → Rahmen, wartende Teile     .StatusLine() → Zeile für /ez status oder nil
      Core.GroupFrames.Hook() → true, sobald der Zuhörer an CompactUnitFrame_SetUnit hängt (intern)
      Core.GroupFrames.OnSetUnit(rahmen, einheit) / .Flush()   intern
]]

local ADDON = "ezCore"
local GF = {}
Core.GroupFrames = GF

GF.QUEUE_KEY = "GroupFrames"
GF.MAX_PARTY, GF.MAX_RAID, GF.RAID_GROUPS, GF.GROUP_SIZE, GF.MAX_FLAT = 4, 40, 8, 5, 80

local tracked = setmetatable({}, { __mode = "k" })   -- Blizzards Rahmen → { unit, kind }
local store = setmetatable({}, { __mode = "k" })     -- Blizzards Rahmen → { [owner] = { data = {}, parts = { [key] = slot } } }
local watchers, watcherOrder = {}, {}
local queue = {}                                     -- wartende Teile: { frame, owner, key }
local hooked, partyHooked = false, false

-- Verbotene Rahmen (Namensplaketten in Instanzen u. a.) darf ein Addon nicht anfassen; IsForbidden ist das Einzige,
-- was dort erlaubt ist. Alles, was sich nicht sicher als erlaubt zeigt, gilt als verboten.
local function Forbidden(frame)
    if type(frame) ~= "table" then return true end
    local ok, method = pcall(function() return frame.IsForbidden end)
    if not ok then return true end
    if type(method) ~= "function" then return false end
    local called, result = pcall(method, frame)
    if not called or Core.IsSecret(result) then return true end
    return result == true
end

function GF.IsGroupUnit(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return false end
    if unit == "player" then return true end
    local kind, index = unit:match("^(%a+)(%d+)$")
    index = tonumber(index)
    if kind == "party" then return index >= 1 and index <= GF.MAX_PARTY end
    if kind == "raid" then return index >= 1 and index <= GF.MAX_RAID end
    return false
end

local function UnitOrder(unit)
    if unit == "player" then return 0 end
    local kind, index = unit:match("^(%a+)(%d+)$")
    return (kind == "party" and 100 or 200) + (tonumber(index) or 0)
end

local function Fire(what, ...)
    for _, owner in ipairs(watcherOrder) do
        local fn = watchers[owner] and watchers[owner][what]
        if fn then
            local ok, err = pcall(fn, ...)
            if not ok then Core.Error(owner, err, "GroupFrames " .. what) end
        end
    end
end

-- Eine Stelle für jeden Wechsel: unit nil = der Rahmen zeigt kein Gruppenmitglied mehr.
local function Update(frame, unit, kind)
    local entry = tracked[frame]
    if unit == nil then
        if entry then
            tracked[frame] = nil
            Fire("onRemove", frame, entry.unit, entry.kind)
        end
        return
    end
    if not entry then
        tracked[frame] = { unit = unit, kind = kind }
        Fire("onAdd", frame, unit, kind)
    elseif entry.unit ~= unit then
        local old = entry.unit
        entry.unit, entry.kind = unit, kind
        Fire("onUnit", frame, unit, old, kind)
    end
end

---------------------------------------------------------------------------
-- Raidstil: Zuhörer an CompactUnitFrame_SetUnit
---------------------------------------------------------------------------

function GF.OnSetUnit(frame, unit)
    if Forbidden(frame) then return end
    if Core.IsSecret(unit) then return end
    local entry = tracked[frame]
    if entry and entry.kind ~= "raid" then return end
    if not GF.IsGroupUnit(unit) then unit = nil end       -- Namensplakette, Arena, Begleiter, leer
    Update(frame, unit, "raid")
end

function GF.Hook()
    if not hooked and type(hooksecurefunc) == "function" and type(rawget(_G, "CompactUnitFrame_SetUnit")) == "function" then
        hooked = pcall(hooksecurefunc, "CompactUnitFrame_SetUnit", function(frame, unit) GF.OnSetUnit(frame, unit) end)
    end
    if not partyHooked and type(hooksecurefunc) == "function" then
        local party = rawget(_G, "PartyFrame")
        if type(party) == "table" and not Forbidden(party) and type(party.UpdatePartyFrames) == "function" then
            partyHooked = pcall(hooksecurefunc, party, "UpdatePartyFrames", function() GF.ScanClassic() end)
        end
    end
    return hooked
end

-- Rahmen, die schon vor dem Zuhörer eine Einheit hatten (Neuladen in der Gruppe): nur lesen.
local function ReadCompact(frame)
    if Forbidden(frame) then return end
    local ok, unit = pcall(function() return frame.unit end)
    if ok then GF.OnSetUnit(frame, unit) end
end

function GF.ScanCompact()
    local party = rawget(_G, "CompactPartyFrame")
    if type(party) == "table" and not Forbidden(party) and type(party.memberUnitFrames) == "table" then
        for _, frame in ipairs(party.memberUnitFrames) do ReadCompact(frame) end
    end
    for i = 1, GF.MAX_FLAT do
        local frame = rawget(_G, "CompactRaidFrame" .. i)
        if frame == nil then break end
        ReadCompact(frame)
    end
    for group = 1, GF.RAID_GROUPS do
        if rawget(_G, "CompactRaidGroup" .. group) ~= nil then
            for i = 1, GF.GROUP_SIZE do
                local frame = rawget(_G, "CompactRaidGroup" .. group .. "Member" .. i)
                if frame ~= nil then ReadCompact(frame) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Klassische Ansicht: Gruppenrahmen aus Blizzards Vorrat und der Spielerrahmen
---------------------------------------------------------------------------

-- Zeigt Blizzard die Gruppe im Raidstil? (Bearbeitungsmodus „Raidstil-Gruppenrahmen“)
function GF.RaidStyle()
    local manager = rawget(_G, "EditModeManagerFrame")
    if type(manager) == "table" and type(manager.UseRaidStylePartyFrames) == "function" then
        local ok, on = pcall(manager.UseRaidStylePartyFrames, manager)
        if ok and not Core.IsSecret(on) then return on == true end
    end
    local compact = rawget(_G, "CompactPartyFrame")
    if type(compact) == "table" and not Forbidden(compact) and type(compact.IsShown) == "function" then
        local ok, shown = pcall(compact.IsShown, compact)
        return ok and not Core.IsSecret(shown) and shown == true
    end
    return false
end

function GF.ClassicView()
    if type(IsInGroup) ~= "function" then return false end
    local inGroup = IsInGroup()
    if Core.IsSecret(inGroup) or inGroup ~= true then return false end
    if type(IsInRaid) == "function" then
        local inRaid = IsInRaid()
        if not Core.IsSecret(inRaid) and inRaid == true then return false end
    end
    return not GF.RaidStyle()
end

function GF.ScanClassic()
    local seen = {}
    local party = rawget(_G, "PartyFrame")
    local pool = type(party) == "table" and not Forbidden(party) and party.PartyMemberFramePool
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
        local ok, err = pcall(function()
            for member in pool:EnumerateActive() do
                if not Forbidden(member) then
                    local unit = member.unitToken
                    if type(unit) ~= "string" and type(member.layoutIndex) == "number" then unit = "party" .. member.layoutIndex end
                    if GF.IsGroupUnit(unit) and unit ~= "player" and type(UnitExists) == "function" then
                        -- Zuerst IsSecret: Antworten von Blizzard nie ungeprüft vergleichen (Leitlinie 6)
                        local shown, exists = member:IsShown(), UnitExists(unit)
                        if not Core.IsSecret(shown) and shown == true and not Core.IsSecret(exists) and exists == true then
                            seen[member] = unit
                        end
                    end
                end
            end
        end)
        if not ok then Core.Error(ADDON, err, "GroupFrames PartyMemberFramePool") end
    end
    local player = rawget(_G, "PlayerFrame")
    if type(player) == "table" and not Forbidden(player) and GF.ClassicView() then seen[player] = "player" end

    local gone = {}
    for frame, entry in pairs(tracked) do
        if entry.kind ~= "raid" and not seen[frame] then gone[#gone + 1] = { frame = frame, unit = entry.unit } end
    end
    table.sort(gone, function(a, b) return UnitOrder(a.unit) < UnitOrder(b.unit) end)
    for _, item in ipairs(gone) do Update(item.frame, nil) end
    local list = {}
    for frame, unit in pairs(seen) do list[#list + 1] = { frame = frame, unit = unit } end
    table.sort(list, function(a, b) return UnitOrder(a.unit) < UnitOrder(b.unit) end)
    for _, item in ipairs(list) do
        local entry = tracked[item.frame]
        if not entry or entry.kind ~= "raid" then
            Update(item.frame, item.unit, item.unit == "player" and "player" or "party")
        end
    end
end

function GF.Refresh()
    GF.Hook()
    GF.ScanCompact()
    GF.ScanClassic()
    return (GF.Count())
end

---------------------------------------------------------------------------
-- Rückrufe und Abfragen
---------------------------------------------------------------------------

function GF.List()
    local list = {}
    for frame, entry in pairs(tracked) do list[#list + 1] = { frame = frame, unit = entry.unit, kind = entry.kind } end
    table.sort(list, function(a, b)
        local oa, ob = UnitOrder(a.unit), UnitOrder(b.unit)
        if oa ~= ob then return oa < ob end
        return a.kind < b.kind
    end)
    return list
end

function GF.Watch(owner, callbacks)
    if type(owner) ~= "string" or owner == "" or type(callbacks) ~= "table" then return false, "invalid" end
    for _, what in ipairs({ "onAdd", "onUnit", "onRemove" }) do
        if callbacks[what] ~= nil and type(callbacks[what]) ~= "function" then return false, "invalid" end
    end
    if not watchers[owner] then watcherOrder[#watcherOrder + 1] = owner end
    watchers[owner] = { onAdd = callbacks.onAdd, onUnit = callbacks.onUnit, onRemove = callbacks.onRemove }
    if callbacks.onAdd then
        for _, item in ipairs(GF.List()) do
            local ok, err = pcall(callbacks.onAdd, item.frame, item.unit, item.kind)
            if not ok then Core.Error(owner, err, "GroupFrames onAdd") end
        end
    end
    return true
end

function GF.Unwatch(owner)
    if not watchers[owner] then return false end
    watchers[owner] = nil
    for i, name in ipairs(watcherOrder) do
        if name == owner then table.remove(watcherOrder, i) break end
    end
    return true
end

function GF.Unit(frame)
    local entry = type(frame) == "table" and tracked[frame]
    if not entry then return nil end
    return entry.unit, entry.kind
end

local function TrackedUnit(frame)
    if Core.IsSecret(frame) or type(frame) ~= "table" then return nil end
    local unit, kind = GF.Unit(frame)
    if type(unit) == "string" and not Core.IsSecret(unit) then return unit, kind end
    return nil
end

function GF.TooltipUnit(tooltip)
    if Core.IsSecret(tooltip) or type(tooltip) ~= "table" or type(tooltip.GetOwner) ~= "function" then return nil end
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok then return nil end
    local unit, kind = TrackedUnit(owner)
    if unit then return unit, kind end
    if Core.IsSecret(owner) or type(owner) ~= "table" or type(owner.GetParent) ~= "function" then return nil end
    local okParent, parent = pcall(owner.GetParent, owner)
    if okParent then return TrackedUnit(parent) end
    return nil
end

-- Direkt über tracked nachschlagen (läuft bei UNIT_AURA im Raid oft): keine Liste bauen, nichts sortieren.
-- Gleiche Wahl wie die sortierte Liste: sichtbar vor verborgen, bei mehreren die Art in fester Reihenfolge.
function GF.Frame(unit)
    if not GF.IsGroupUnit(unit) then return nil end
    local shown, shownKind, hidden, hiddenKind
    for frame, entry in pairs(tracked) do
        if entry.unit == unit then
            local ok, visible = pcall(frame.IsVisible, frame)
            if ok and not Core.IsSecret(visible) and visible == true then
                if not shown or entry.kind < shownKind then shown, shownKind = frame, entry.kind end
            elseif not hidden or entry.kind < hiddenKind then
                hidden, hiddenKind = frame, entry.kind
            end
        end
    end
    if shown then return shown, shownKind end
    return hidden, hiddenKind
end

---------------------------------------------------------------------------
-- Eigene Teile je Rahmen
---------------------------------------------------------------------------

local function Own(owner, frame)
    local byOwner = store[frame]
    if not byOwner then
        byOwner = {}
        store[frame] = byOwner
    end
    local own = byOwner[owner]
    if not own then
        own = { data = {}, parts = {} }
        byOwner[owner] = own
    end
    return own
end

function GF.Data(owner, frame)
    if type(owner) ~= "string" or owner == "" or Forbidden(frame) then return nil end
    return Own(owner, frame).data
end

function GF.Part(owner, frame, key)
    local byOwner = type(frame) == "table" and store[frame]
    local slot = byOwner and byOwner[owner] and byOwner[owner].parts[key]
    return slot and slot.child or nil
end

function GF.Parts(owner, frame)
    local out = {}
    local byOwner = type(frame) == "table" and store[frame]
    if byOwner and byOwner[owner] then
        for key, slot in pairs(byOwner[owner].parts) do
            if slot.child then out[key] = slot.child end
        end
    end
    return out
end

local function CheckOpts(opts)
    if opts == nil then return true end
    if type(opts) ~= "table" then return false, "invalid" end
    if opts.frameType ~= nil and type(opts.frameType) ~= "string" then return false, "invalid" end
    if opts.template ~= nil and type(opts.template) ~= "string" then return false, "invalid" end
    if opts.onCreate ~= nil and type(opts.onCreate) ~= "function" then return false, "invalid" end
    if Core.IsSecret(opts.level) then return false, "secret" end
    if opts.level ~= nil and type(opts.level) ~= "number" then return false, "invalid" end
    if opts.size ~= nil then
        if type(opts.size) ~= "table" then return false, "invalid" end
        if Core.IsSecret(opts.size[1]) or Core.IsSecret(opts.size[2]) then return false, "secret" end
        if type(opts.size[1]) ~= "number" or type(opts.size[2]) ~= "number" then return false, "invalid" end
    end
    local anchor = opts.anchor
    if anchor ~= nil and type(anchor) ~= "function" then
        if type(anchor) ~= "table" then return false, "invalid" end
        for i = 1, 4 do if Core.IsSecret(anchor[i]) then return false, "secret" end end
        if type(anchor[1]) ~= "string" or (anchor[2] ~= nil and type(anchor[2]) ~= "string")
            or (anchor[3] ~= nil and type(anchor[3]) ~= "number") or (anchor[4] ~= nil and type(anchor[4]) ~= "number") then
            return false, "invalid"
        end
    end
    return true
end

-- Größe, Lage, Ebene des eigenen Kindes (nur außerhalb des Kampfes gerufen).
local function Layout(owner, frame, slot)
    local child, opts = slot.child, slot.opts
    local ok, err = pcall(function()
        if opts.size then child:SetSize(opts.size[1], opts.size[2]) end
        local anchor = opts.anchor
        if type(anchor) == "function" then
            anchor(child, frame)
        elseif type(anchor) == "table" then
            child:ClearAllPoints()
            child:SetPoint(anchor[1], frame, anchor[2] or anchor[1], anchor[3] or 0, anchor[4] or 0)
        else
            child:ClearAllPoints()
            child:SetAllPoints(frame)
        end
        local base = frame:GetFrameLevel()
        if type(base) == "number" and not Core.IsSecret(base) then child:SetFrameLevel(base + (opts.level or 1)) end
    end)
    if not ok then Core.Error(owner, err, "GroupFrames Layout") end
    return ok
end

local function Create(owner, frame, slot)
    if type(CreateFrame) ~= "function" then return nil, "missing" end
    local opts = slot.opts
    local kind = opts.frameType or "Frame"
    local child
    if opts.template then
        local ok, made = pcall(CreateFrame, kind, nil, frame, opts.template)
        if ok and type(made) == "table" then child = made end
    end
    if not child then
        local ok, made = pcall(CreateFrame, kind, nil, frame)
        if not ok or type(made) ~= "table" then
            Core.Error(owner, made, "GroupFrames CreateFrame")
            return nil, "error"
        end
        child = made
    end
    -- Mausdurchlässig: Klicks und Tooltip gehören Blizzards Rahmen darunter.
    pcall(child.EnableMouse, child, false)
    slot.child = child
    Layout(owner, frame, slot)
    if opts.onCreate then
        local entry = tracked[frame]
        local ok, err = pcall(opts.onCreate, child, frame, entry and entry.unit or nil)
        if not ok then Core.Error(owner, err, "GroupFrames onCreate") end
    end
    return child
end

function GF.Flush()
    if Core.InCombat() then return false end
    local todo = queue
    queue = {}
    for _, item in ipairs(todo) do
        local byOwner = store[item.frame]
        local slot = byOwner and byOwner[item.owner] and byOwner[item.owner].parts[item.key]
        if slot and slot.pending then
            slot.pending = nil
            if Forbidden(item.frame) then
                byOwner[item.owner].parts[item.key] = nil
            elseif slot.child then
                Layout(item.owner, item.frame, slot)
            elseif not Create(item.owner, item.frame, slot) then
                byOwner[item.owner].parts[item.key] = nil
            end
        end
    end
    return true
end

local function Later(owner, frame, key, slot)
    if not slot.pending then
        slot.pending = true
        queue[#queue + 1] = { frame = frame, owner = owner, key = key }
    end
    Core.AfterCombat(GF.Flush, GF.QUEUE_KEY, ADDON)
end

function GF.Attach(owner, frame, key, opts)
    if type(owner) ~= "string" or owner == "" or Core.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then
        return nil, "invalid"
    end
    if type(frame) ~= "table" then return nil, "invalid" end
    if Forbidden(frame) then return nil, "forbidden" end
    local okOpts, why = CheckOpts(opts)
    if not okOpts then return nil, why end
    local own = Own(owner, frame)
    local slot = own.parts[key]
    if not slot then
        if not tracked[frame] then return nil, "untracked" end
        slot = { opts = opts or {} }
        own.parts[key] = slot
    elseif opts ~= nil then
        -- onCreate läuft nur einmal: ein späterer Aufruf ändert Größe, Lage und Ebene, nicht den Aufbau
        local first = slot.opts
        slot.opts = opts
        if slot.child == nil and opts.onCreate == nil and first.onCreate ~= nil then
            local merged = {}
            for name, value in pairs(opts) do merged[name] = value end
            merged.onCreate = first.onCreate
            slot.opts = merged
        end
    elseif slot.child and not slot.pending then
        return slot.child
    end
    if Core.InCombat() then
        Later(owner, frame, key, slot)
        return slot.child, "combat"
    end
    slot.pending = nil
    if slot.child then
        Layout(owner, frame, slot)
        return slot.child
    end
    local child, reason = Create(owner, frame, slot)
    if not child then own.parts[key] = nil end
    return child, reason
end

function GF.Count()
    local frames, waiting = 0, 0
    for _ in pairs(tracked) do frames = frames + 1 end
    for _, item in ipairs(queue) do
        local byOwner = store[item.frame]
        local slot = byOwner and byOwner[item.owner] and byOwner[item.owner].parts[item.key]
        if slot and slot.pending then waiting = waiting + 1 end
    end
    return frames, waiting
end

function GF.StatusLine()
    local frames, waiting = GF.Count()
    if frames == 0 and waiting == 0 then return nil end
    local L = Core.L
    if waiting > 0 then return L.STATUS_GROUPFRAMES_WAITING:format(frames, waiting) end
    return L.STATUS_GROUPFRAMES:format(frames)
end

---------------------------------------------------------------------------
-- Benannte Plätze (Platzplan „Mittelband teilen“, Entscheidung des Nutzers vom 14.11.2026)
--
-- Die eine Stelle, an der steht, wo eigene Teile an Blizzards Rahmen sitzen (Leitlinie 2). Lagen aus Blizzards
-- Forever-Quelle (Gethe/wow-ui-source, Zweig forever):
--   raid    Blizzard_UnitFrame/Shared/CompactUnitFrame.lua und .xml – Grundgröße 72 × 36
--           (NATIVE_UNIT_FRAME_WIDTH/HEIGHT), Auren 11 px (NATIVE_UNIT_FRAME_AURA_SIZE), Rollensymbol 17 px;
--           Anordnung „Legacy“ (CompactUnitFrameLayoutTemplates): Rollensymbol TOPLEFT 3/−2, Name rechts daneben
--           bis −3, bannbare Debuffs TOPRIGHT −3/−2, Debuffs BOTTOMLEFT 3/2, Buffs BOTTOMRIGHT −3/2 (je über der
--           Kraftleiste); „Buffs oben, Debuffs unten“: Buffs als Reihe oben rechts, Name in der Mitte; „Buffs rechts,
--           Debuffs links“: Rollensymbol TOPRIGHT −3/−2. Statuszeile „Tot“/„Offline“ Höhe/3 − 2 von unten,
--           Bereitschaftscheck BOTTOM Höhe/3 − 4 (beides nur zeitweise).
--           Kraftleiste: DefaultCompactUnitFrameSetup setzt frame.powerBarUsedHeight = 8, sobald sie zu sehen ist
--           (Lua-Vorgabe DefaultCompactUnitFrameSetupOptions.displayPowerBar = true; CVar raidFramesDisplayPowerBars,
--           „nur Heiler“), sonst 0; Aurengröße frame:GetBuffAuraSize()/GetDebuffAuraSize() (11 × Symbolgröße aus dem
--           Bearbeitungsmodus). Blizzard_PrivateAurasUI.lua (PrivateAuraUnitFrameLayoutTemplates): untere Auren ab
--           CUF_AURA_BOTTOM_OFFSET (2) + powerBarUsedHeight; „Buffs oben“: Buffs TOPRIGHT −3/−3 (bis zu sechs in
--           einer Reihe), Name CENTER, Debuffs BOTTOMRIGHT −3 (drei je Reihe), bannbare Debuffs BOTTOMLEFT 3 (bis
--           zu drei Zeichen à 14 px, CompactDispelDebuffTemplate in Blizzard_PrivateAurasUI.xml).
--           Daraus das Mittelband (GF.SlotBand): zwischen der Oberkante der ersten unteren Aurenreihe und der
--           Unterkante von Name/bannbaren Debuffs. „Buffs oben“ (Entscheidung des Nutzers vom 14.11.2026: „Freie
--           Stelle nutzen“): zuerst das Mittelband zwischen unterer Reihe und Name; reicht es nicht, der Streifen
--           zwischen Name und Buff-Reihe, sonst die Lücke unten zwischen bannbaren Debuffs und Debuffs, sonst die
--           Lücke oben zwischen Rollensymbol und Buff-Reihe; ist keine frei (72 px Breite unter 58 px Höhe:
--           Blizzards Reihen füllen den Rahmen), bleibt der Platz aus.
--   party   Blizzard_UnitFrame/Mainline/PartyFrameTemplates.xml – 120 × 53, Porträt 7/−6 (37 px), Name 46/−6
--           (57 × 12), Rollensymbol TOPRIGHT −5/−5 (12 px), Lebensbalken 45/−19 (70 × 10), Manabalken 41/−30
--           (74 × 7), Auren ab 48/−43, Begleiter 23/−43 (64 × 23), „nicht da“ LEFT an RIGHT +2/−2, Sonderleiste
--           +13/+5. Bis zum 18.11.2026 lag midLeft über der Unterkante des Porträts (Unterkante bei −43, ab x 1) –
--           das sichtbare Rahmenbild endet aber bei −39, Symbol und Zeichen ragten darunter (Absatz „Am Rahmen“).
--           Leiter-Symbol PartyMemberOverlay.LeaderIcon: BOTTOM an TOP −10/−6 (16 × 16, x 42 bis 58, bis −6).
--   player  Blizzard_UnitFrame/Mainline/PlayerFrame.xml – 232 × 100, Porträt 24/−19 (60 px), Name 88/−27,
--           Lebensbalken 85/−40 (124 × 20), Manabalken 85/−61 (124 × 10), Ruhe-Symbol PlayerRestLoop 64/−6 (20 px;
--           sein Bild RestTexture 30 × 30 mittig darin, also x 59 bis 89, −1 bis −31), Leiter-Symbol 86/−10,
--           Rollensymbol 196/−27 (12 px).
--   topLines BIS ZUM 18.11.2026 klassisch „direkt unter dem Rahmen“ – die Fassung, für die die Felder below, art,
--           clear, clearBelow und next sowie GF.SlotClear und GF.SlotDepth gebaut sind; seit dem Spielbefund vom
--           18.11.2026 (Absatz „Am Rahmen“ unten) nutzt kein Platz sie mehr, die Mechanik bleibt geprüft
--           (Tests/unter_rahmen14_test.lua, Tests/lage27_test.lua mit der alten Lage als Vorlage).
--           Wunsch des Nutzers vom 15.11.2026 nach dem Spieltest: „die balken
--           sollten direkt unter dem rahmen sein“; Befund vom 16.11.2026: „der "details" balken muss direkt
--           unterkante zum eigenen rahmen sein und abstand zum nächsten“): Streifen ab der SICHTBAREN Unterkante von
--           Blizzards Rahmenbild nach unten (below, art), so breit wie die Balken (Gruppe: Lebensbalken 45 bis 115,
--           Spieler: 85 bis 209).
--           Ursache des Befunds (Bildschirmfoto, klassische Gruppenrahmen, Maßstab 1): Der Streifen hing an der
--           Unterkante des Rahmen-RECHTECKS (120 × 53, PartyFrameTemplates.xml). Blizzards Rahmenbild endet aber unter
--           den Balken schon bei −39 (Manabalken 41/−30, 74 × 7, darunter der bronzene Rand bis −38; Atlas
--           UI-HUD-UnitFrame-Party-PortraitOn 120 × 49 ab 1/−2 mit durchsichtigem Rand) – die unteren 14 px des
--           Rechtecks sind Raum für Blizzards Aurenreihe und den Begleiter-Rahmen (beide ab −43). Darum klaffte über dem
--           Streifen eine leere Lücke von 14 px, und darunter blieben bis zum nächsten Rahmen nur Blizzards 10 px
--           Abstand: Man ordnete den Streifen dem nächsten Rahmen zu. Jetzt: art = 14 (Streifen ab −39).
--           Was darunter liegt: Begleiter-Rahmen (23/−43, 64 × 23, unten bei −66; nur mit Blizzards Schalter für
--           Begleiter, CVar showPartyPets, und einem Begleiter zu sehen, Mainline/PartyMemberFrame.lua UpdatePet) –
--           nur wenn er gezeigt wird (IsShown), rückt der Streifen 27 px tiefer an seine Unterkante (clear); Blizzard
--           rückt die Rahmen mit showPartyPets von 10 auf 26 px auseinander (Shared/PartyFrame.lua,
--           PartyFrameMixin:UpdateSpacingAndLayout). Blizzards Aurenreihe (48/−43, bis zu vier Debuffs à 15 px mit
--           2 px Abstand bis x 114, Shared/PartyFrameTemplates.xml PartyAuraFrameTemplate, MAX_PARTY_DEBUFFS) wechselt
--           im Kampf ständig und lässt sich nicht taint-sicher verschieben (Leitlinie 5); unter ihr wäre kein Platz
--           mehr vor dem nächsten Rahmen. Der Streifen bleibt darum direkt unter dem Rahmenbild und liegt UNTER den
--           Aurensymbolen (level 1; Symbole auf Rahmen + 2): Blizzards Debuffs bleiben ganz zu sehen, von der
--           Schadenszeile (−39 bis −44) decken sie nur die unteren 2 px samt Rand, die Heilungszeile nur, solange ein
--           Debuff dort steht; Zahl und Stern rechts außen bleiben frei (Empfehlung umgesetzt, Antwort offen – die
--           Frage „über oder unter den Aurensymbolen“ in docs/roadmap/ezCombat.md).
--           Abstand zum nächsten Rahmen (next, GF.SlotDepth): gemessen am nächsten sichtbaren Gruppenrahmen darunter –
--           sein Rahmenbild beginnt 2 px unter seiner Oberkante (Texture 1/−2), Blizzards Leiter- bzw. Führer-Symbol
--           (PartyMemberOverlay.LeaderIcon/GuideIcon, 16 × 16, BOTTOM an TOP −10/−6, Atlas 16 × 16) ragt 10 px darüber.
--           Unter dem Streifen bleiben mindestens GF.SLOT_BELOW_GAP px frei; reicht der Platz nicht (Begleiter-Rahmen
--           und Leiter-Symbol), wird der Streifen niedriger (Place kürzt, ezCombat macht die Zeilen dünner). Blizzards
--           Rahmen rücken nicht auseinander – nicht nötig, und Blizzards Abstand ist Blizzards Wert (Leitlinie 5).
--           Engster Fall bei Blizzard: Begleiter-Rahmen und Krone am nächsten Rahmen lassen 3 px (SlotDepth 0); Place
--           setzt den Halter dann auf 1 px, ezCombat legt zwei Linien à 1 px ohne Abstand aneinander – 1 px bleibt frei.
--           Spielerrahmen: Blizzard setzt seine Klassenleiste (PlayerBottomManagedFrameContainer, TOP an PlayerFrame
--           BOTTOM +30/+25, PlayerFrame.lua) direkt unter sein Rahmenbild – art = 25 (Streifen ab −75 statt −100).
--           Name und Zugriff belegt an Gethe/wow-ui-source, Zweig forever (Stand bebcb6bf, 17.11.2026):
--           Blizzard_UnitFrame/Mainline/PlayerFrame.xml Z. 477 (<Frame name="PlayerBottomManagedFrameContainer" …>,
--           Anker Z. 482), Blizzard_ManagedFrameSystem/Shared/ManagedFrameSystem.lua Z. 9–11 (Blizzards Zugriff
--           GetPlayerBottomManagedFrameContainer() gibt diesen Rahmen zurück), Blizzard_UnitFrame/Mainline/
--           PlayerFrame.lua Z. 635–636 und 705–709 (Anker +25, mit zweiter Kraftleiste +15). clearBelow fragt zuerst
--           Blizzards Zugriff, den globalen Namen nur als Rückfall.
--           Mit Blizzards zweiter Kraftleiste (PlayerFrameContainer.AlternatePowerFrameTexture, Atlas …-ClassResource)
--           rückt Blizzard die Leiste um 10 px tiefer (+15), der Streifen auch (clear). Zeigt Blizzard dort eine
--           Klassenleiste (Combo-Punkte, Runen …), hängt der Streifen unter ihr (clearBelow, gemessen); level 1.
--           Der Raidstil bleibt an der Oberkante (die Rahmen stoßen aneinander; Frage an den Nutzer in
--           docs/roadmap/uebergreifend.md).
--   Am Rahmen (Spielbefund des Nutzers vom 18.11.2026 mit Bildschirmfoto, klassische Gruppenrahmen zweier Mitspieler:
--           ezCombats Zeilen in der Lücke zum nächsten Rahmen, „Platz n · x/s“ rechts daneben, das ezBuff-Symbol
--           unter dem Rahmen; wörtlich: „buffs und co nicht in einem popup sondern über und an dem rahmen, den abstand
--           zu den rahmen untereinander beibehalten“): Jeder Platz liegt innerhalb von Blizzards sichtbarem
--           Rahmenbild (Gruppe 120 × 53 mit Bild bis −39, Spieler 232 × 100 mit Bild bis −75) – auf Blizzards Teilen,
--           wo daneben nichts frei ist, so wie Blizzard selbst Auren über den Lebensbalken legt. Blizzards Abstand der
--           Rahmen untereinander bleibt; kein Teil reicht in ihn hinein. Aufteilung (keine Überdeckung untereinander,
--           Reihenfolge je Platz über GF.Reserve):
--             midLeft   oben links auf dem Porträt (Gruppe 6/−6, Spieler 20/−19 auf dem Ring), Symbol 14 px, die
--                       Zeichen daneben enden vor dem Namen (Gruppe x 44 < 46) bzw. vor Blizzards Ruhe-Bild (Spieler
--                       x 58 < 59); unter Blizzards Leiter-Symbol (Gruppe bis −6, Spieler 86/−10 rechts davon)
--             midRight  rechts auf dem Lebensbalken, nach links wachsend (Gruppe RIGHT −5 auf Höhe −24, 10 px wie der
--                       Balken; Spieler RIGHT −23 auf Höhe −50, 12 px) – wie Blizzards Buffs unten rechts im Raidstil
--             center    auf dem Lebensbalken zwischen seinem Anfang (Gruppe x 46, Spieler x 86) und dem Platz der
--                       HoTs – der ganzen Vormerkung, weil die Zahl auch im Kampf zu sehen ist (Gegenprüfung vom
--                       18.11.2026: HoTs, die erst im Kampf kamen, lagen sonst unter der Zahl)
--             topLines  zwei Linien auf dem Manabalken ohne Hintergrund (Gruppe 41/−30, 74 × 7: Streifen 45 bis 115 ab
--                       −30; Spieler 85/−61, 124 × 10: ab −61), höchstens 3 px je Linie (line), zusammen höchstens 7 px
-- Erste Lage, feinjustiert nach Bildschirmfotos (docs/roadmap/uebergreifend.md, Platzplan).
--
-- Felder je Platz:
--   span, left, right, top, height   ganze Breite: Streifen an der Oberkante (top von oben); mehrere Teile
--                                    stapeln sich nach unten
--   below = true               der Streifen hängt an der Unterkante von Blizzards Rahmen (top zählt ab der Unterkante
--                              nach unten) – folgt der echten Höhe des Rahmens
--   art = px                   Blizzards sichtbares Rahmenbild endet px über der Unterkante des Rechtecks; der
--                              Streifen beginnt dort (nur mit below)
--   clear = { [schlüssel] = px }  ist Blizzards Kind frame[schlüssel] zu sehen (Pfad mit Punkten: frame.a.b), rückt
--                              der Streifen px tiefer (nur mit below; GF.SlotClear)
--   clearBelow = { name | { get, name } … }  ist Blizzards Rahmen zu sehen und reicht er in den Streifen, hängt der
--                              Streifen unter seiner Unterkante (gemessen; GF.SlotClear). Der Rahmen kommt aus Blizzards
--                              Zugriff _G[get]() (nur lesen, per pcall), sonst aus _G[name]
--   next = { inset, icons }    Abstand zum nächsten Rahmen derselben Art darunter (GF.SlotDepth): sein Bild beginnt
--                              inset px unter seiner Oberkante, seine sichtbaren Kinder icons (Pfade) zählen mit
--   level                      Ebene des Teils über Blizzards Rahmen, wenn der Platz sie vorgibt (sonst das Modul)
--   line, gap, plain           Aufteilung des Streifens für das Modul (ezCombat): Höhe einer Linie, Abstand der
--                              Linien, plain = ohne Hintergrund. Raidstil: zwei Linien à 1 px ohne Abstand in den
--                              zwei Pixelzeilen über Blizzards Rollensymbol und bannbaren Debuffs (beide ab −2),
--                              ohne Hintergrund – der Streifen liegt auf Blizzards Lebensbalken und verdeckt nur,
--                              was die Linien selbst füllen. Fehlen die Felder, nimmt das Modul seine eigenen Maße.
--   point, relPoint, x, y      Anker an Blizzards Rahmen; grow "RIGHT" | "LEFT": Teile reihen sich in diese Richtung
--   size                       höchste Höhe eines Teils (GF.SlotSize verkleinert größere im selben Verhältnis)
--   facing                     Platz auf der anderen Seite desselben Bandes (GF.SlotRoom: nicht hineinwachsen;
--                              ein Kind aus GF.Slot blendet der Dienst aus, wenn es hineinwüchse)
--   between = { links, rechts }  Mitte zwischen zwei Plätzen (nimmt, was die sichtbaren Teile dort übrig lassen);
--                              eine Zahl statt eines Platzes ist ein fester Abstand vom Rand (klassisch: Anfang des
--                              Lebensbalkens). Ohne combat = false hält sie die ganze Vormerkung daneben frei
--                              (im Kampf wird nicht neu gesetzt; Gegenprüfung vom 18.11.2026)
--   width, height              feste Größe (Text außen am klassischen Rahmen)
--   after = platz              point/relPoint, x, y gelten am eigenen Teil desselben owners an diesem Platz statt an
--                              Blizzards Rahmen (beside hinter den Balken an topLines; wandert mit). Fehlt das Teil
--                              noch, an Blizzards Rahmen – das Modul setzt neu, sobald es da ist. Gemeint ist das
--                              erste Teil des owners an diesem Platz: after taugt nur, wo er dort genau eines hat
--   classic = true             (nur in der Vorlage der Prüfungen) das Modul baut seine alte Zeile mit Symbol und Zahl
--                              am Zeilenende (ezCombat, MF.Classic) – bis zum 18.11.2026 die Lage unter dem Rahmen
--   shift = { [schlüssel] = px }  ist Blizzards Kind frame[schlüssel] zu sehen, rückt ein Platz mit point px in seine
--                              Richtung nach außen (nach rechts; GF.SlotShift) – beside weicht Blizzards Symbol
--                              „nicht da“; ändert es sich, setzt das Modul sein Teil außerhalb des Kampfes neu
--   minHeight, minWidth        darunter bleibt der Platz leer (GF.Slot blendet das Kind aus)
--   off = true                 in dieser Anordnung kein Platz (GF.SlotFits → false)
--   combat = false             Inhalte nur außerhalb des Kampfes (fragt das Modul über GF.SlotInCombat)
--   band = true                Höhe aus Blizzards Mittelband (GF.SlotBand) statt y; ist das Band niedriger als size
--                              bzw. height, bleibt der Platz aus (GF.SlotFits, GF.SlotRoom → false) – Blizzards Ecken
--                              bleiben frei, auch mit Kraftleiste. Nennt das Band eigene Ränder (freie Stelle in
--                              „Buffs oben“), gelten sie statt x
---------------------------------------------------------------------------

GF.SLOT_NAMES = { "topLines", "midLeft", "midRight", "center", "beside" }
GF.SLOT_GAP = 1
GF.SIDE_GAP = 5                                     -- px vom Ende der Linien bis zu den Zahlen neben dem Rahmen (beside)
GF.SLOT_BELOW_GAP = 3                               -- freie px unter einem Streifen (below) bis zum nächsten Rahmen
GF.ROLE_ICON = 17                                   -- Blizzards Rollensymbol im Raidstil (CompactUnitFrame.xml)
-- Mittelband im Raidstil (Quellen im Kopf des Abschnitts)
GF.AURA_BOTTOM = 2                                  -- CUF_AURA_BOTTOM_OFFSET (Blizzard_PrivateAurasUI.lua)
GF.AURA_SIZE = 11                                   -- NATIVE_UNIT_FRAME_AURA_SIZE (CompactUnitFrame.lua)
GF.NAME_TOP, GF.NAME_HEIGHT = 3, 10                 -- Name TOPRIGHT −3/−3, GameFontHighlightSmall (10 px)
GF.DISPEL_TOP = 2                                   -- bannbare Debuffs TOPRIGHT −3/−2 („Buffs rechts“: TOPLEFT 3/−2)
GF.BUFFS_TOP = 3                                    -- „Buffs oben“: Buffs TOPRIGHT −3/−3
GF.SLOT_HEIGHT = 10                                 -- Höhe der Teile im Mittelband; so viel braucht eine freie Stelle
-- Freie Stelle in „Buffs oben, Debuffs unten“ (PrivateAuraUnitFrameLayoutTemplates, Blizzard_PrivateAurasUI.lua/.xml)
GF.AURA_EDGE = 3                                    -- Abstand von Auren und Rollensymbol zum linken/rechten Rand
GF.AURA_ROW = 3                                     -- Debuffs und bannbare Debuffs je Reihe (GridLayout … 3)
GF.BUFFS_TOP_ROW = 6                                -- Buffs in der Reihe oben (GridLayout … 6, höchstens 6 Buffs)
GF.DISPEL_SIZE = 14                                 -- Zeichen bannbarer Debuffs (CompactDispelDebuffTemplate)
GF.BUFFS_TOP_SPOTS = { "upper", "bottom", "top" }   -- Reihenfolge der Stellen, wenn das Mittelband nicht reicht
-- Reihenfolge der Plätze beim Neusetzen (GF.Relayout): zuerst die Seite mit Vorrang (midRight – ezHeals HoT-Reihe
-- steht auch im Kampf), dann die Seite, die ihr weicht (midLeft – ezBuff fragt GF.SlotRoom). So sieht der Rückruf
-- (onPlaced) eines Teils in midLeft schon, ob die Reihe gegenüber nach dem Neusetzen zu sehen ist.
GF.RELAYOUT_ORDER = { "topLines", "midRight", "midLeft", "center", "beside" }
GF.SLOTS = {
    raid = {
        -- 2 px an der Oberkante: Rollensymbol und bannbare Debuffs beginnen 2 px, Name und Buff-Reihe 3 px darunter
        topLines = { span = true, left = 2, right = 2, top = 0, size = 2, height = 2, line = 1, gap = 0, plain = true },
        -- rechts neben dem Rollensymbol (3 + 17 + 1)
        midLeft = { point = "LEFT", relPoint = "LEFT", x = 21, y = 0, grow = "RIGHT", size = GF.SLOT_HEIGHT, facing = "midRight", band = true },
        midRight = { point = "RIGHT", relPoint = "RIGHT", x = -3, y = 0, grow = "LEFT", size = GF.SLOT_HEIGHT, facing = "midLeft", band = true },
        center = { between = { "midLeft", "midRight" }, y = 0, height = GF.SLOT_HEIGHT, minHeight = 30, minWidth = 20, combat = false, band = true },
        -- die Rahmen stoßen aneinander: kein Platz daneben (die Zahl bleibt in der Mitte)
        beside = { point = "LEFT", relPoint = "RIGHT", x = 0, y = 0, off = true },
    },
    -- Klassisch: im sichtbaren Rahmenbild (Absatz „Am Rahmen“ im Kopf, Spielbefund vom 18.11.2026) – außer den Balken
    -- der Kampfanzeige: seit dem Spieltest vom 20.11.2026 wieder direkt an der Unterkante von Blizzards Rahmenbild
    -- („der balken ist kaum sichtbar ... halb so hoch wie die mana, lebensbalken reicht, und dann bitte wieder am rahmen
    -- unten“), je Balken halb so hoch wie Blizzards Manabalken, mit Hintergrund; die Zahlen rechts daneben (beside)
    party = {
        -- unter dem Rahmenbild (endet 14 px über der Unterkante des Rechtecks, bei −39), so breit wie der Lebensbalken
        -- (45 bis 115); ein Balken 4 px (Manabalken 7 px, halb aufgerundet), zwei mit 1 px Abstand; unter Blizzards
        -- Aurensymbolen (level 1); Begleiter-Rahmen und Abstand zum nächsten Rahmen wie bis zum 18.11.2026 (Absatz
        -- topLines im Kopf: clear, next)
        topLines = { span = true, below = true, art = 14, left = 45, right = 5, top = 0, height = 4, size = 9, line = 4,
            gap = 1, level = 1, clear = { PetFrame = 27 },
            next = { inset = 2, icons = { "PartyMemberOverlay.LeaderIcon", "PartyMemberOverlay.GuideIcon" } } },
        -- oben links auf dem Porträt (7/−6, 37 px): Symbol 14 px, Zeichen daneben bis x 44 (Name ab 46)
        midLeft = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 6, y = -6, grow = "RIGHT", size = 14 },
        -- rechts auf dem Lebensbalken (45/−19, 70 × 10), nach links wachsend
        midRight = { point = "RIGHT", relPoint = "TOPRIGHT", x = -5, y = -24, grow = "LEFT", size = 10 },
        -- auf dem Lebensbalken ab seinem Anfang (x 46) bis an den Platz der HoTs (auch im Kampf zu sehen: die ganze
        -- Vormerkung bleibt frei, bei vier HoTs rund 25 px); Mitte des Balkens 2,5 px über der Rahmenmitte
        center = { between = { 46, "midRight" }, y = 2.5, height = 10, minWidth = 20 },
        -- rechts neben den Balken (Spieltest 20.11.2026: „warum sind die zahlen nicht rechts vom balken?“, „keine
        -- lücke bitte, bzw nur minimal“): GF.SIDE_GAP px hinter dem Ende des eigenen Teils am Platz topLines, mittig
        -- auf seiner Höhe (after – wandert mit, wenn der Begleiter-Rahmen die Balken tiefer rückt). Zwei Zeilen
        -- Schrift à 12 px. Blizzards Symbol „nicht da“ (NotPresentIcon, LEFT an RIGHT +2/−2: andere Phase, andere
        -- Gruppe) reicht bis in diese Höhe – ist es zu sehen, rücken die Zahlen dahinter (shift, GF.SlotShift; 29 px =
        -- 2 px Abstand + Symbol 25 px + 2 px, Größe im Spiel prüfen)
        beside = { after = "topLines", point = "LEFT", relPoint = "RIGHT", x = GF.SIDE_GAP, y = 0, width = 160,
            height = 24, shift = { NotPresentIcon = 29 } },
    },
    player = {
        -- unter dem Rahmenbild (endet 25 px über der Unterkante des Rechtecks, bei −75), so breit wie Lebens- und
        -- Manabalken (85 bis 209); ein Balken 5 px (Manabalken 10 px, halb), zwei mit 1 px Abstand; zweite
        -- Kraftleiste und Klassenleiste rücken ihn tiefer (clear, clearBelow – Absatz topLines im Kopf)
        topLines = { span = true, below = true, art = 25, left = 85, right = 23, top = 0, height = 5, size = 11, line = 5,
            gap = 1, level = 1, clear = { ["PlayerFrameContainer.AlternatePowerFrameTexture"] = 10 },
            clearBelow = { { get = "GetPlayerBottomManagedFrameContainer", name = "PlayerBottomManagedFrameContainer" } } },
        -- oben links am Porträt (24/−19, 60 px), ab x 20 auf dessen Ring: Zeichen enden bei x 58 vor Blizzards
        -- Ruhe-Bild (RestTexture 30 × 30 mittig in PlayerRestLoop 64/−6, 20 × 20: ab x 59; Gegenprüfung 18.11.2026)
        midLeft = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -19, grow = "RIGHT", size = 14 },
        -- rechts auf dem Lebensbalken (85/−40, 124 × 20), nach links wachsend
        midRight = { point = "RIGHT", relPoint = "TOPRIGHT", x = -23, y = -50, grow = "LEFT", size = 12 },
        -- auf dem Lebensbalken ab x 86 bis an den Platz der HoTs (ganze Vormerkung); seine Mitte ist die Rahmenmitte
        center = { between = { 86, "midRight" }, y = 0, height = 10, minWidth = 20 },
        -- rechts neben den Balken (wie party): hinter ihrem Ende (x 209), nicht am Rechteck – das reicht 23 px weiter
        -- als Blizzards Rahmenbild (Spieltest 20.11.2026, Bildschirmfoto „Platz 1 · 33,1 DPS“ mit rund 25 px Lücke)
        beside = { after = "topLines", point = "LEFT", relPoint = "RIGHT", x = GF.SIDE_GAP, y = 0, width = 160, height = 24 },
    },
}
-- Abweichungen im Raidstil je Anordnung der Auren (Bearbeitungsmodus, Enum.RaidAuraOrganizationType; ganze Plätze,
-- die den Eintrag in GF.SLOTS.raid ersetzen). "legacy" ist GF.SLOTS.raid selbst.
GF.SLOT_ORGANIZATION = {
    -- Name steht in der Mitte: keine Zahl darüber. midLeft und midRight bleiben die Plätze aus GF.SLOTS.raid; ihre
    -- Höhe und – an einer freien Stelle – ihre Ränder nennt GF.SlotBand (Mittelband, sonst Lücke unten, sonst oben).
    buffsTop = {
        center = { between = { "midLeft", "midRight" }, y = 0, height = GF.SLOT_HEIGHT, off = true, combat = false, band = true },
    },
    -- Rollensymbol oben rechts: links frei, rechts Platz für das Symbol lassen
    buffsRight = {
        midLeft = { point = "LEFT", relPoint = "LEFT", x = 3, y = 0, grow = "RIGHT", size = GF.SLOT_HEIGHT, facing = "midRight", band = true },
        midRight = { point = "RIGHT", relPoint = "RIGHT", x = -21, y = 0, grow = "LEFT", size = GF.SLOT_HEIGHT, facing = "midLeft", band = true },
    },
}
GF.ORGANIZATION_KEYS = { Legacy = "legacy", BuffsTopDebuffsBottom = "buffsTop", BuffsRightDebuffsLeft = "buffsRight" }

local reserved = {}                                  -- [platz] = { { owner, key, order, w, h } … } sortiert
local generation = 0                                 -- wächst mit jeder Vormerkung (Lagen der Teile ändern sich)

local function SlotName(name)
    if Core.IsSecret(name) or type(name) ~= "string" then return false end
    for _, known in ipairs(GF.SLOT_NAMES) do if known == name then return true end end
    return false
end

local function Spec(kind, name, organization)
    if kind == "raid" and organization and GF.SLOT_ORGANIZATION[organization] then
        local special = GF.SLOT_ORGANIZATION[organization][name]
        if special then return special end
    end
    local byKind = GF.SLOTS[kind] or GF.SLOTS.raid
    return byKind and byKind[name]
end

-- Art des Rahmens für die Plätze: "raid" | "party" | "player" (unbekannt: "raid").
function GF.SlotKind(frame)
    local entry = type(frame) == "table" and tracked[frame]
    return entry and entry.kind or "raid"
end

-- Zwischenspeicher je Rahmen: die Anordnung der Auren. Jeder Platz fragt sie ab (GF.SlotRoom allein drei- bis
-- viermal), Blizzards Abfrage läuft aber über EditModeManagerFrame und pcall. Gemerkt wird, bis sich etwas ändern
-- kann: GF.Relayout ohne middle (Bearbeitungsmodus, Gruppenwechsel, Betreten der Welt), Blizzards Neuaufbau des
-- Rahmens (GF.OnFrameSetup nach DefaultCompactUnitFrameSetup) oder GF.DropCache verwerfen den Eintrag.
local organizations = setmetatable({}, { __mode = "k" })

-- Gemerkte Anordnung verwerfen (frame nil: aller Rahmen).
function GF.DropCache(frame)
    if frame ~= nil then
        organizations[frame] = nil
        return
    end
    for blizzard in pairs(organizations) do organizations[blizzard] = nil end
end

-- Anordnung bei Blizzard lesen (nur lesen, per pcall; unbekannt: "legacy").
local function ReadOrganization(frame)
    local manager = rawget(_G, "EditModeManagerFrame")
    local enum = rawget(_G, "Enum") and Enum.RaidAuraOrganizationType
    if type(manager) ~= "table" or type(manager.GetRaidFrameAuraOrganizationType) ~= "function" or type(enum) ~= "table" then
        return "legacy"
    end
    local ok, value = pcall(function() return manager:GetRaidFrameAuraOrganizationType(frame.groupType) end)
    if not ok or Core.IsSecret(value) or value == nil then return "legacy" end
    for enumKey, slotKey in pairs(GF.ORGANIZATION_KEYS) do
        if enum[enumKey] ~= nil and enum[enumKey] == value then return slotKey end
    end
    return "legacy"
end

-- Anordnung der Auren eines Raidstil-Rahmens: "legacy" | "buffsTop" | "buffsRight" (unbekannt: "legacy").
-- Blizzards Feld groupType und EditModeManagerFrame werden nur gelesen; das Ergebnis ist je Rahmen gemerkt.
function GF.SlotOrganization(frame)
    if type(frame) ~= "table" or GF.SlotKind(frame) ~= "raid" then return "legacy" end
    local known = organizations[frame]
    if known then return known end
    if Forbidden(frame) then return "legacy" end
    known = ReadOrganization(frame)
    organizations[frame] = known
    return known
end

local function FrameSpec(frame, name)
    local kind = GF.SlotKind(frame)
    return Spec(kind, name, kind == "raid" and GF.SlotOrganization(frame) or nil), kind
end

-- Felder eines Platzes als Kopie (die Tabelle selbst bleibt die eine Quelle). organization nur für "raid".
function GF.SlotSpec(kind, name, organization)
    if not SlotName(name) then return nil end
    local spec = Spec(kind, name, organization)
    if not spec then return nil end
    local copy = {}
    for field, value in pairs(spec) do copy[field] = value end
    return copy
end

-- Größe eines Teils in diesem Platz: zu hohe Teile schrumpfen im selben Verhältnis auf spec.size.
function GF.SlotSize(kind, name, width, height)
    local spec = SlotName(name) and Spec(kind, name)
    if not spec or type(width) ~= "number" or type(height) ~= "number" then return width, height end
    local max = spec.size
    if type(max) == "number" and height > max and height > 0 then
        return math.floor(width * max / height + 0.5), max
    end
    return width, height
end

-- Dürfen die Inhalte dieses Platzes im Kampf zu sehen sein? (center im Raidstil: nein)
function GF.SlotInCombat(kind, name)
    local spec = SlotName(name) and Spec(kind, name)
    return not (spec and spec.combat == false)
end

-- Platz vormerken (einmal beim Laden des Moduls): mehrere Teile teilen sich einen Platz ohne Überdeckung, in der
-- Reihenfolge order (kleiner zuerst, Standard 100). size = { breite, höhe } – die Größe ohne Verkleinerung, bei
-- Reihen die größte (z. B. alle HoT-Symbole). Derselbe owner und key ersetzt den Eintrag.
-- → true | false, "invalid" | "secret"
function GF.Reserve(owner, name, key, opts)
    if Core.IsSecret(owner) or Core.IsSecret(key) then return false, "secret" end
    if type(owner) ~= "string" or owner == "" or not SlotName(name) then return false, "invalid" end
    if type(key) ~= "string" and type(key) ~= "number" then return false, "invalid" end
    if type(opts) ~= "table" or type(opts.size) ~= "table" then return false, "invalid" end
    local w, h, order = opts.size[1], opts.size[2], opts.order
    if Core.IsSecret(w) or Core.IsSecret(h) or Core.IsSecret(order) then return false, "secret" end
    if type(w) ~= "number" or type(h) ~= "number" or w < 0 or h < 0 then return false, "invalid" end
    if order ~= nil and type(order) ~= "number" then return false, "invalid" end
    local list = reserved[name] or {}
    reserved[name] = list
    for i = #list, 1, -1 do
        if list[i].owner == owner and list[i].key == key then table.remove(list, i) end
    end
    list[#list + 1] = { owner = owner, key = key, order = order or 100, w = w, h = h }
    generation = generation + 1
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.owner ~= b.owner then return a.owner < b.owner end
        return tostring(a.key) < tostring(b.key)
    end)
    return true
end

-- Vormerkungen eines Platzes in ihrer Reihenfolge: { { owner, key, order, size = { b, h } } … }
function GF.Reserved(name)
    local out = {}
    for i, item in ipairs(reserved[name] or {}) do
        out[i] = { owner = item.owner, key = item.key, order = item.order, size = { item.w, item.h } }
    end
    return out
end

-- Eigene Teile, die schon an einem Platz in Wuchsrichtung stehen: [Blizzards Rahmen][platz][owner \0 key] = Teil.
-- Nur sichtbare zählen für die Mitte und die Gegenseite – ein vorgemerktes Teil, das ein Modul an diesem Rahmen
-- gerade nicht zeigt, nimmt niemandem Platz weg.
local placed = setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })  -- eigene Teile mit Zuhörer an OnShow/OnHide
local placedHooks = setmetatable({}, { __mode = "k" })  -- [eigenes Teil] = fn(teil, passt) aus GF.SlotAnchor

local function PlacedKey(owner, key) return tostring(owner) .. "\0" .. tostring(key) end

local function Shown(region)
    local ok, shown = pcall(function() return region:IsShown() end)
    return ok and not Core.IsSecret(shown) and shown == true
end

local function Size(frame, method)
    local ok, value = pcall(function() return frame[method](frame) end)
    if not ok or Core.IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

-- Länge eines sichtbaren Teils in Wuchsrichtung: vorgemerkt, höchstens so groß wie das Teil gerade ist (eine
-- Auren-Reihe mit zwei von vier HoTs ist kürzer; Blizzard passt ihre Größe selbst an).
local function Length(spec, kind, name, item, region)
    local w, h = GF.SlotSize(kind, name, item.w, item.h)
    local length = spec.span and h or w
    if region then
        local actual = Size(region, spec.span and "GetHeight" or "GetWidth")
        if actual and actual >= 0 and actual < length then length = actual end
    end
    return length
end

-- Abstand eines Teils vom Anfang des Platzes und seine Länge. Die Lage hängt nur an den Vormerkungen (Teile
-- springen nicht, wenn ein früheres fehlt); nicht vorgemerkte Teile stehen hinter allen vorgemerkten.
local function Offset(spec, kind, name, owner, key)
    local offset = 0
    for _, item in ipairs(reserved[name] or {}) do
        local length = Length(spec, kind, name, item)
        if item.owner == owner and item.key == key then return offset, length end
        offset = offset + length + GF.SLOT_GAP
    end
    return offset
end

-- Belegte Länge eines Platzes bis zum Ende des letzten Teils, das an diesem Rahmen zu sehen ist.
local function Extent(frame, name)
    local spec, kind = FrameSpec(frame, name)
    if not spec then return 0 end
    local byName = placed[frame] and placed[frame][name]
    local offset, reach = 0, 0
    for _, item in ipairs(reserved[name] or {}) do
        local entry = byName and byName[PlacedKey(item.owner, item.key)]
        local region = entry and entry.region
        if region and Shown(region) then reach = offset + Length(spec, kind, name, item, region) end
        offset = offset + Length(spec, kind, name, item) + GF.SLOT_GAP
    end
    return reach
end

-- Abstand eines Platzes vom linken bzw. rechten Rand des Rahmens: die Ränder der freien Stelle, wenn das Band
-- welche nennt („Buffs oben“: Lücke unten oder oben), sonst x des Platzes.
local function Inset(spec, band)
    if band and spec.band then
        if spec.grow == "RIGHT" and band.left then return band.left end
        if spec.grow == "LEFT" and band.right then return band.right end
    end
    return math.abs(spec.x or 0)
end

-- Länge alles Vorgemerkten an einem Platz (mit den Abständen dazwischen).
local function Total(spec, kind, name)
    local total = 0
    for i, item in ipairs(reserved[name] or {}) do
        total = total + (i > 1 and GF.SLOT_GAP or 0) + Length(spec, kind, name, item)
    end
    return total
end

-- Linker und rechter Abstand der Mitte (between) vom Rand des Rahmens. Eine Zahl statt eines Platzes ist ein fester
-- Abstand (klassisch: Anfang des Lebensbalkens). Ist die Mitte auch im Kampf zu sehen (ohne combat = false), zählt
-- an einem Platz daneben die ganze Vormerkung, nicht nur, was gerade zu sehen ist: Im Kampf wird die Mitte nicht neu
-- gesetzt, und HoTs, die erst dann kommen, lägen sonst unter der Zahl (Gegenprüfung vom 18.11.2026).
local function Between(frame, spec, band)
    local insets = {}
    for i, side in ipairs(spec.between) do
        if type(side) == "number" then
            insets[i] = side
        else
            local other, otherKind = FrameSpec(frame, side)
            local used = Extent(frame, side)
            if other and spec.combat ~= false then used = math.max(used, Total(other, otherKind, side)) end
            insets[i] = (other and Inset(other, band) or 0) + used + (used > 0 and GF.SLOT_GAP or 0)
        end
    end
    return insets[1], insets[2]
end

-- Zahl aus Blizzards Rahmen nur lesen (Feld oder Methode, per pcall, zuerst auf geheim geprüft); sonst nil.
local function ReadNumber(frame, field, method)
    local ok, value = pcall(function()
        if method then
            local fn = frame[method]
            if type(fn) ~= "function" then return nil end
            return fn(frame)
        end
        return frame[field]
    end)
    if not ok or Core.IsSecret(value) or type(value) ~= "number" or value < 0 then return nil end
    return value
end

-- Ein Band, gemessen von der Unterkante des Rahmens. left/right: eigene Ränder (freie Stelle), sonst nil.
local function Band(height, bottom, top, left, right, where)
    return { bottom = bottom, top = top, room = top - bottom, y = (bottom + top) / 2 - height / 2,
        left = left, right = right, where = where }
end

-- „Buffs oben, Debuffs unten“ (Entscheidung des Nutzers vom 14.11.2026: „Freie Stelle nutzen“). Blizzard belegt
-- oben die Buff-Reihe (bis zu sechs, von rechts) neben dem Rollensymbol, in der Mitte den Namen (Breite je nach
-- Text: gilt als ganze Breite), unten rechts die Debuffs und unten links die Zeichen bannbarer Debuffs (14 px).
-- Gesucht wird in dieser Reihenfolge eine Stelle mit GF.SLOT_HEIGHT Höhe (Höhen für 11-px-Auren):
--   "middle"  ganze Breite zwischen unterer Reihe und Name (ab 62 px Rahmenhöhe, mit Kraftleiste ab 78 px)
--   "upper"   ganze Breite zwischen Name und Buff-Reihe, über der unteren Reihe (ab 58 px Höhe, mit und ohne
--             Kraftleiste; das Rollensymbol reicht tiefer, liegt aber links von midLeft) – Plätze wie im Mittelband
--   "bottom"  Lücke unten zwischen bannbaren Debuffs und Debuffs, bis unter den Namen und unter die Buff-Reihe
--             (ohne Kraftleiste ab 34 px Höhe, mit ihr ab 50 px; Breite des Rahmens − 83 px)
--   "top"     Lücke oben zwischen Rollensymbol und Buff-Reihe, über dem Namen und über der unteren Reihe (die
--             Zeichen bannbarer Debuffs reichen mit Kraftleiste bis 24 px: ab 36 px Höhe, mit Kraftleiste ab
--             37 px; Breite − 91 px)
-- Größere Auren aus dem Bearbeitungsmodus (bis 22 px) zählen mit: Die Buff-Reihe reicht dann tiefer und weiter
-- nach links, Debuffs weiter nach innen. Ist keine Stelle frei – bei 72 px Breite unter 58 px Höhe füllen
-- Blizzards Reihen den Rahmen –, kommt das zu niedrige Mittelband zurück und die Plätze bleiben aus.
local function BuffsTopBand(frame, height, power, buff, debuff)
    local nameBottom, nameTop = (height - GF.NAME_HEIGHT) / 2, (height + GF.NAME_HEIGHT) / 2
    local buffBottom = height - GF.BUFFS_TOP - buff              -- Unterkante von Blizzards Buff-Reihe
    local middle = Band(height, GF.AURA_BOTTOM + power + math.max(debuff, GF.DISPEL_SIZE),
        math.min(buffBottom, nameBottom), nil, nil, "middle")
    if middle.room >= GF.SLOT_HEIGHT then return middle end
    local width = Size(frame, "GetWidth")
    if not width or width <= 0 then return middle end
    for _, where in ipairs(GF.BUFFS_TOP_SPOTS) do
        local spot
        if where == "upper" then
            spot = Band(height, math.max(nameTop, middle.bottom), buffBottom, nil, nil, where)
        elseif where == "bottom" then
            spot = Band(height, GF.AURA_BOTTOM + power, math.min(nameBottom, buffBottom),
                GF.AURA_EDGE + GF.AURA_ROW * GF.DISPEL_SIZE + GF.SLOT_GAP,
                GF.AURA_EDGE + GF.AURA_ROW * debuff + GF.SLOT_GAP, where)
        elseif where == "top" then
            spot = Band(height, math.max(nameTop, middle.bottom), height - GF.BUFFS_TOP,
                GF.AURA_EDGE + GF.ROLE_ICON + GF.SLOT_GAP,
                GF.AURA_EDGE + GF.BUFFS_TOP_ROW * buff + GF.SLOT_GAP, where)
        end
        if spot and spot.room >= GF.SLOT_HEIGHT and width - (spot.left or 0) - (spot.right or 0) >= GF.SLOT_HEIGHT then
            return spot
        end
    end
    return middle
end

-- Mittelband eines Raidstil-Rahmens, gemessen von seiner Unterkante: unten = Oberkante der ersten unteren
-- Aurenreihe (CUF_AURA_BOTTOM_OFFSET + Kraftleiste + Aurengröße), oben = Unterkante von Name und bannbaren Debuffs.
-- „Buffs oben“: das Mittelband zwischen unterer Reihe und Name, sonst eine freie Stelle (BuffsTopBand).
-- → { bottom, top, room, y, left, right, where } | nil (kein Raidstil oder Höhe unbekannt bzw. 0). y: Versatz der
-- Bandmitte zur Mitte des Rahmens (für die Anker LEFT/RIGHT); left/right: Ränder einer Lücke (sonst nil, es gilt
-- x des Platzes); where: "middle" | "upper" | "bottom" | "top". Blizzards Werte nur gelesen:
-- frame.powerBarUsedHeight, frame:GetBuffAuraSize(), frame:GetDebuffAuraSize().
function GF.SlotBand(frame)
    if type(frame) ~= "table" or GF.SlotKind(frame) ~= "raid" or Forbidden(frame) then return nil end
    local height = Size(frame, "GetHeight")
    if not height or height <= 0 then return nil end      -- noch ohne Größe (nicht angeordnet): unbekannt
    local power = ReadNumber(frame, "powerBarUsedHeight") or 0
    local buff = ReadNumber(frame, nil, "GetBuffAuraSize") or GF.AURA_SIZE
    local debuff = ReadNumber(frame, nil, "GetDebuffAuraSize") or GF.AURA_SIZE
    if GF.SlotOrganization(frame) == "buffsTop" then return BuffsTopBand(frame, height, power, buff, debuff) end
    return Band(height, GF.AURA_BOTTOM + power + math.max(buff, debuff),
        math.min(height - GF.NAME_TOP - GF.NAME_HEIGHT, height - GF.DISPEL_TOP - debuff), nil, nil, "middle")
end

-- Band eines Platzes (nur Plätze mit band = true), sonst nil.
local function BandOf(frame, spec)
    if not spec.band then return nil end
    return GF.SlotBand(frame)
end

-- Reicht das Mittelband für diesen Platz (band = true: size bzw. height)? Unbekannt gilt als genug.
local function BandFits(spec, band)
    if not spec.band or not band then return true end
    return band.room >= (spec.size or spec.height or 0)
end

-- Höhe eines Platzes: band → Mitte des Mittelbands, sonst spec.y.
local function SlotY(spec, band)
    if band then return band.y end
    return spec.y or 0
end

-- Passt ein Teil (owner, key) – ohne Angabe alles Vorgemerkte – in die Breite zwischen den Rändern beider Seiten?
-- Nur Plätze im Band mit Gegenseite (Raidstil: midLeft, midRight); was dort gerade steht, zählt GF.SlotRoom.
-- Unbekannte Breite gilt als genug.
local function WidthFits(frame, spec, kind, name, band, owner, key)
    if not (spec.band and spec.grow and spec.facing) then return true end
    local width = Size(frame, "GetWidth")
    if not width or width <= 0 then return true end
    local need
    if owner ~= nil and key ~= nil then
        local offset, length = Offset(spec, kind, name, owner, key)
        need = offset + (length or 0)
    else
        need = Total(spec, kind, name)
    end
    local other = FrameSpec(frame, spec.facing)
    return need <= width - Inset(spec, band) - (other and Inset(other, band) or 0)
end

-- Ist im Rahmen Platz genug (minHeight, minWidth, Mittelband bzw. freie Stelle, nicht off)? owner und key
-- (optional): passt genau dieses Teil in die Breite des Bandes – ohne Angabe alles Vorgemerkte des Platzes.
-- Unbekannte Größe gilt als genug.
function GF.SlotFits(frame, name, owner, key)
    if type(frame) ~= "table" or not SlotName(name) then return false end
    local spec, kind = FrameSpec(frame, name)
    if not spec or spec.off then return false end
    local band = BandOf(frame, spec)
    if not BandFits(spec, band) then return false end
    if not WidthFits(frame, spec, kind, name, band, owner, key) then return false end
    if spec.minHeight then
        local h = Size(frame, "GetHeight")
        if h and h < spec.minHeight then return false end
    end
    if spec.minWidth and spec.between then
        local w = Size(frame, "GetWidth")
        local left, right = Between(frame, spec, band)
        if w and w - left - right < spec.minWidth then return false end
    end
    return true
end

-- Passt ein Teil an seine Stelle, ohne in die sichtbaren Teile der Gegenseite (facing) oder über den Rand zu
-- wachsen? Für Teile, die das Modul nur außerhalb des Kampfes zeigt (ezBuff): vor dem Zeigen fragen. Schließt
-- Band und Breite ein (wer hier passt, passt auch nach GF.SlotFits für dieses Teil); GF.Slot blendet sein Kind
-- danach aus. Plätze ohne Gegenseite (klassisch außen) → true.
function GF.SlotRoom(frame, name, owner, key)
    if type(frame) ~= "table" or not SlotName(name) then return false end
    local spec, kind = FrameSpec(frame, name)
    if not spec or spec.off then return false end
    local band = BandOf(frame, spec)
    if not BandFits(spec, band) then return false end
    if not spec.facing then return true end
    local offset, length = Offset(spec, kind, name, owner, key)
    local width = Size(frame, "GetWidth")
    if not width then return true end
    local other = FrameSpec(frame, spec.facing)
    local otherUsed = Extent(frame, spec.facing)
    local limit = width - Inset(spec, band) - (other and Inset(other, band) or 0) - otherUsed - (otherUsed > 0 and GF.SLOT_GAP or 0)
    return offset + (length or 0) <= limit
end

-- Kind von Blizzards Rahmen über einen Pfad mit Punkten ("PartyMemberOverlay.LeaderIcon"); nur lesen (rawget).
local function Child(frame, path)
    if type(path) ~= "string" then return nil end
    local node = frame
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = rawget(node, part)
    end
    if node == frame or type(node) ~= "table" then return nil end
    return node
end

-- Kanten eines Rahmens oder einer Textur in Bildschirm-Einheiten (mal der wirksamen Skalierung): l, r, b, t, Skala.
-- Nur lesen, per pcall, jeder Wert zuerst auf geheim geprüft; scale: Skala, wenn die Region selbst keine nennt
-- (Texturen). → nil, wenn etwas fehlt
local function Edges(region, scale)
    local ok, l, r, b, t, s = pcall(function()
        local own = type(region.GetEffectiveScale) == "function" and region:GetEffectiveScale() or nil
        return region:GetLeft(), region:GetRight(), region:GetBottom(), region:GetTop(), own
    end)
    if not ok then return nil end
    if Core.IsSecret(s) or type(s) ~= "number" or s <= 0 then s = scale end
    if type(s) ~= "number" or s <= 0 then return nil end
    for _, value in ipairs({ l, r, b, t }) do
        if Core.IsSecret(value) or type(value) ~= "number" then return nil end
    end
    return l * s, r * s, b * s, t * s, s
end

-- Lage eines Streifens unter dem Rahmen (below) in Bildschirm-Einheiten: links, rechts, Unterkante von Blizzards
-- Rahmenbild (art), Skala des Rahmens. → nil, wenn Blizzards Rahmen keine Lage nennt
local function BelowEdges(frame, spec)
    local l, r, b, _, s = Edges(frame)
    if not l then return nil end
    return l + spec.left * s, r - spec.right * s, b + (spec.art or 0) * s, s
end

-- Rahmen aus clearBelow: ein globaler Name oder { get, name } – zuerst Blizzards Zugriff _G[get]() (nur lesen, per
-- pcall; ManagedFrameSystem.lua), sonst der globale Name. → Rahmen | nil
local function BlizzardFrame(entry)
    if type(entry) == "string" then entry = { name = entry } end
    if type(entry) ~= "table" then return nil end
    local get = type(entry.get) == "string" and rawget(_G, entry.get)
    if type(get) == "function" then
        local ok, found = pcall(get)
        if ok and type(found) == "table" then return found end
    end
    local found = type(entry.name) == "string" and rawget(_G, entry.name)
    return type(found) == "table" and found or nil
end

-- Wie weit rückt ein Streifen unter dem Rahmen (below) tiefer, weil Blizzard dort etwas zeigt? Ab der sichtbaren
-- Unterkante von Blizzards Rahmenbild (art) gezählt: Kinder aus clear, wenn sie zu sehen sind (z. B. der
-- Begleiter-Rahmen am klassischen Gruppenrahmen), und Rahmen aus clearBelow, wenn sie zu sehen sind und in den
-- Streifen reichen (Blizzards Klassenleiste unter dem Spielerrahmen; gemessen). Nur lesen (rawget, IsShown und
-- Kanten per pcall, geheime Werte zählen als „nichts im Weg“). → px (0, wenn nichts im Weg ist)
function GF.SlotClear(frame, name)
    if type(frame) ~= "table" or not SlotName(name) then return 0 end
    local spec, kind = FrameSpec(frame, name)
    if not (spec and spec.below) or Forbidden(frame) then return 0 end
    local extra = 0
    for path, px in pairs(type(spec.clear) == "table" and spec.clear or {}) do
        local child = Child(frame, path)
        if child and type(px) == "number" and px > extra and Shown(child) then extra = px end
    end
    if type(spec.clearBelow) ~= "table" then return extra end
    local left, right, art, scale = BelowEdges(frame, spec)
    if not left then return extra end
    local height = math.max(spec.height or 0, Total(spec, kind, name))
    for _, entry in ipairs(spec.clearBelow) do
        local other = BlizzardFrame(entry)
        if type(other) == "table" and not Forbidden(other) and Shown(other) then
            local l, r, b, t = Edges(other, scale)
            -- sichtbar hoch (ab 2 px: Blizzards leerer Container ist 1 px hoch und immer gezeigt, minimumHeight in
            -- PlayerManagedContainerTemplate), waagerecht im Streifen, unten unter dem Rahmenbild, oben im Streifen
            if l and t - b >= 2 * scale and l < right and r > left and b < art and t > art - (extra + height) * scale then
                local px = math.ceil((art - b) / scale - 0.01)
                if px > extra then extra = px end
            end
        end
    end
    return extra
end

-- Wie weit rückt ein Platz mit point nach außen, weil Blizzard dort ein Kind zeigt (shift)? Nur lesen (rawget,
-- IsShown per pcall; geheim zählt als „nicht zu sehen“). → px (0, wenn nichts im Weg ist)
function GF.SlotShift(frame, name)
    if type(frame) ~= "table" or not SlotName(name) then return 0 end
    local spec = FrameSpec(frame, name)
    if not (spec and type(spec.shift) == "table") or Forbidden(frame) then return 0 end
    local extra = 0
    for path, px in pairs(spec.shift) do
        local child = Child(frame, path)
        if child and type(px) == "number" and px > extra and Shown(child) then extra = px end
    end
    return extra
end

-- Wie hoch darf ein Streifen unter dem Rahmen (below) höchstens sein, damit unter ihm GF.SLOT_BELOW_GAP px bis zum
-- nächsten Gruppenrahmen derselben Art frei bleiben? Gemessen am nächsten sichtbaren Rahmen darunter, der den
-- Streifen waagerecht überlappt: sein Rahmenbild beginnt next.inset px unter seiner Oberkante, sichtbare Kinder aus
-- next.icons (Blizzards Leiter-Symbol ragt über den Rahmen) zählen mit. Nur lesen. → px | nil (nichts darunter,
-- unbekannte Lage oder ein Platz ohne next)
function GF.SlotDepth(frame, name)
    if type(frame) ~= "table" or not SlotName(name) then return nil end
    local spec, kind = FrameSpec(frame, name)
    if not (spec and spec.below and type(spec.next) == "table") or Forbidden(frame) then return nil end
    local left, right, art, scale = BelowEdges(frame, spec)
    if not left then return nil end
    local _, _, _, frameTop = Edges(frame)
    local top = art - (spec.top + GF.SlotClear(frame, name)) * scale
    local nearest
    local function consider(edge)
        if edge <= top + 0.01 * scale then
            local depth = (top - edge) / scale
            if not nearest or depth < nearest then nearest = depth end
        end
    end
    for blizzard, entry in pairs(tracked) do
        if blizzard ~= frame and entry.kind == kind and not Forbidden(blizzard) and Shown(blizzard) then
            local l, r, _, t = Edges(blizzard, scale)
            if l and t < frameTop and l < right and r > left then
                consider(t - (spec.next.inset or 0) * scale)
                for _, path in ipairs(type(spec.next.icons) == "table" and spec.next.icons or {}) do
                    local icon = Child(blizzard, path)
                    if icon and Shown(icon) then
                        local il, ir, _, it = Edges(icon, scale)
                        if il and il < right and ir > left then consider(it) end
                    end
                end
            end
        end
    end
    if not nearest then return nil end
    return math.max(0, math.floor(nearest - GF.SLOT_BELOW_GAP + 0.01))
end

-- Eigenes Teil eines owners an einem Platz (für after): das Kind aus GF.Slot mit diesem Platz. → Teil | nil
local function OwnPart(frame, owner, name)
    local byOwner = store[frame] and store[frame][owner]
    for _, slot in pairs(byOwner and byOwner.parts or {}) do
        if slot.child and slot.opts and slot.opts.slotName == name then return slot.child end
    end
    return nil
end

-- Ein eigenes Teil (region) an seinen Platz in Blizzards Rahmen setzen – nur außerhalb des Kampfes rufen (die
-- Dienste SecureButton, AuraRow und Attach tun das über die Anker-Funktion aus GF.SlotAnchor). → true | false
function GF.Place(region, frame, name, owner, key)
    if type(region) ~= "table" or type(frame) ~= "table" or not SlotName(name) then return false end
    local spec, kind = FrameSpec(frame, name)
    if not spec then return false end
    local band = BandOf(frame, spec)
    region:ClearAllPoints()
    if spec.span then
        local offset, h = Offset(spec, kind, name, owner, key)
        h = h or spec.height
        local y = -(spec.top + offset + GF.SlotClear(frame, name))
        local edge = spec.below and "BOTTOM" or "TOP"
        if spec.below then
            y = y + (spec.art or 0)                  -- ab der sichtbaren Unterkante von Blizzards Rahmenbild
            local depth = GF.SlotDepth(frame, name)  -- Abstand zum nächsten Rahmen: lieber niedriger als hinein
            if depth then h = math.max(1, math.min(h, depth - offset)) end
        end
        region:SetPoint("TOPLEFT", frame, edge .. "LEFT", spec.left, y)
        region:SetPoint("TOPRIGHT", frame, edge .. "RIGHT", -spec.right, y)
        region:SetHeight(h)
    elseif spec.between then
        local left, right = Between(frame, spec, band)
        local y = SlotY(spec, band)
        region:SetPoint("LEFT", frame, "LEFT", left, y)
        region:SetPoint("RIGHT", frame, "RIGHT", -right, y)
        region:SetHeight(spec.height)
    else
        local offset = Offset(spec, kind, name, owner, key)
        local dx = spec.grow == "LEFT" and -offset or offset
        -- freie Stelle mit eigenen Rändern („Buffs oben“): ihr Rand statt x des Platzes
        local x = spec.x + GF.SlotShift(frame, name)
        if band and spec.grow == "RIGHT" and band.left then
            x = band.left
        elseif band and spec.grow == "LEFT" and band.right then
            x = -band.right
        end
        local anchor = spec.after and OwnPart(frame, owner, spec.after) or frame
        region:SetPoint(spec.point, anchor, spec.relPoint, x + dx, SlotY(spec, band))
        if spec.width and spec.height then region:SetSize(spec.width, spec.height) end
        if spec.grow then GF.Track(region, frame, name, owner, key) end
    end
    -- Wer selbst über die Sichtbarkeit wacht (Core.AuraRow), erfährt nach jedem Setzen, ob der Platz reicht
    local hook = placedHooks[region]
    if hook then
        local ok, err = pcall(hook, region, GF.SlotFits(frame, name, owner, key))
        if not ok then Core.Error(owner or ADDON, err, "GroupFrames Place") end
    end
    return true
end

-- Skripte eigener Teile, nach denen die Mitte nachrückt: zeigen, verstecken und – ohne beides – breiter oder
-- schmaler werden (eine Auren-Reihe mit mehr oder weniger Symbolen).
GF.TRACK_SCRIPTS = { "OnShow", "OnHide", "OnSizeChanged" }

-- Teil in Wuchsrichtung merken; zeigt oder versteckt das Modul es oder ändert sich seine Größe, rückt die Mitte
-- nach (nur eigene Teile: HookScript an eigenen Rahmen, Leitlinie 5). Im Kampf wartet das über Relayout.
function GF.Track(region, frame, name, owner, key)
    local byFrame = placed[frame] or {}
    placed[frame] = byFrame
    byFrame[name] = byFrame[name] or {}
    byFrame[name][PlacedKey(owner, key)] = { region = region, owner = owner, key = key }
    if watched[region] then return end
    watched[region] = frame
    if type(region.HookScript) ~= "function" then return end
    local function moved() GF.Relayout(watched[region], true) end
    for _, script in ipairs(GF.TRACK_SCRIPTS) do pcall(region.HookScript, region, script, moved) end
end

-- Ein eigenes Teil an einem Platz hat sich geändert, ohne dass seine Skripte es melden: Die Mitte seines Rahmens
-- neu setzen. Für Dienste, deren Rahmen keine Layout-Skripte ausführt – Blizzards Auren-Container sperrt
-- OnSizeChanged für Addons, sobald er eine Gruppe hat (Core.AuraRow meldet sich darum nach jedem Anwenden).
-- → true | false (das Teil steht an keinem Platz)
function GF.Changed(region)
    local frame = type(region) == "table" and watched[region]
    if not frame then return false end
    GF.Relayout(frame, true)
    return true
end

-- Anker-Funktion für die Dienste (Core.SecureButton anchor, Core.AuraRow anchor/slot, GF.Attach anchor):
-- fn(region) setzt das Teil an seinen Platz. onPlaced (optional): fn(region, passt) nach jedem Setzen, auch bei
-- GF.Relayout – für Dienste, die die Sichtbarkeit selbst führen (Core.AuraRow blendet die Reihe aus, wenn das
-- Mittelband nicht reicht). → fn | nil, "invalid"
function GF.SlotAnchor(owner, frame, name, key, onPlaced)
    if type(owner) ~= "string" or owner == "" or type(frame) ~= "table" or not SlotName(name) then return nil, "invalid" end
    if Core.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return nil, "invalid" end
    if onPlaced ~= nil and type(onPlaced) ~= "function" then return nil, "invalid" end
    return function(region)
        if onPlaced and type(region) == "table" then placedHooks[region] = onPlaced end
        GF.Place(region, frame, name, owner, key)
    end
end

-- Eigenes, mausdurchlässiges Kind an einem Platz (wie Attach; Lage aus GF.SLOTS statt eines eigenen Ankers).
-- opts wie Attach ohne anchor. Plätze mit Mindestgröße (oder off) blendet der Dienst selbst ein und aus – das
-- Modul blendet dort nur die Inhalte. Reicht das Mittelband nicht (band) oder wüchse das Kind in die sichtbaren
-- Teile der Gegenseite (facing, GF.SlotRoom), blendet der Dienst es bei jedem Setzen aus – auch bei GF.Relayout,
-- wenn Blizzard den Rahmen verkleinert; zeigen bleibt Sache des Moduls (vorher GF.SlotRoom fragen).
-- → kind | nil, grund (wie Attach)
function GF.Slot(owner, frame, name, key, opts)
    if not SlotName(name) then return nil, "invalid" end
    if opts ~= nil and type(opts) ~= "table" then return nil, "invalid" end
    local merged = {}
    for field, value in pairs(opts or {}) do merged[field] = value end
    merged.anchor = function(child, blizzard)
        GF.Place(child, blizzard, name, owner, key)
        local spec = FrameSpec(blizzard, name)
        if spec and (spec.minHeight or spec.minWidth or spec.off) then
            child:SetShown(GF.SlotFits(blizzard, name, owner, key))
        elseif spec and not GF.SlotRoom(blizzard, name, owner, key) then
            child:Hide()                             -- Band zu niedrig, Lücke zu schmal oder die Gegenseite im Weg
        end
    end
    merged.slotName = name
    return GF.Attach(owner, frame, key, merged)
end

GF.RELAYOUT_KEY = "GroupFrames:relayout"

-- Rahmen, deren Teile im Kampf nicht gesetzt werden durften. Core.AfterCombat hält je Schlüssel nur den letzten
-- Aufruf – darum EIN Eintrag (GF.RELAYOUT_KEY), der nach dem Kampf alle hier gemerkten Rahmen neu setzt.
local waitingFrames = setmetatable({}, { __mode = "k" })
local waitingAll = false

-- Nach dem Kampf: alle vorgemerkten Rahmen neu setzen (einmal „alle“ deckt jeden einzelnen ab). → true | false
function GF.RelayoutWaiting()
    if Core.InCombat() then return false end
    local all, list = waitingAll, {}
    waitingAll = false
    for blizzard in pairs(waitingFrames) do list[#list + 1] = blizzard end
    for _, blizzard in ipairs(list) do waitingFrames[blizzard] = nil end
    if all then
        GF.Relayout()
    else
        for _, blizzard in ipairs(list) do GF.Relayout(blizzard) end
    end
    return true
end

-- Zustand, für den die Teile eines Rahmens zuletzt gesetzt wurden: Breite, Höhe, Kraftleiste, Aurengrößen,
-- Anordnung, Stand der Vormerkungen. Blizzard ruft DefaultCompactUnitFrameSetup bei jedem UpdateAll eines Rahmens
-- (Gruppenwechsel, neue Einheit) – ohne Änderung daran muss nichts neu gesetzt werden (GF.OnFrameSetup).
local applied = setmetatable({}, { __mode = "k" })

local function State(frame)
    return Size(frame, "GetWidth"), Size(frame, "GetHeight"), ReadNumber(frame, "powerBarUsedHeight"),
        ReadNumber(frame, nil, "GetBuffAuraSize"), ReadNumber(frame, nil, "GetDebuffAuraSize"),
        GF.SlotOrganization(frame), generation
end

local function Remember(frame)
    local state = applied[frame] or {}
    applied[frame] = state
    state[1], state[2], state[3], state[4], state[5], state[6], state[7] = State(frame)
end

local function Unchanged(frame)
    local state = applied[frame]
    if not state then return false end
    local width, height, power, buff, debuff, organization, reservedAt = State(frame)
    return state[1] == width and state[2] == height and state[3] == power and state[4] == buff and state[5] == debuff
        and state[6] == organization and state[7] == reservedAt
end

-- Bekannte, erlaubte Rahmen für ein Neusetzen: der genannte oder alle mit eigenen Teilen.
local function RelayoutFrames(frame)
    local frames = {}
    if frame ~= nil then
        if tracked[frame] and not Forbidden(frame) then frames[1] = frame end
        return frames
    end
    local seen = {}
    for _, source in ipairs({ placed, store }) do
        for blizzard in pairs(source) do
            if not seen[blizzard] and tracked[blizzard] and not Forbidden(blizzard) then
                seen[blizzard] = true
                frames[#frames + 1] = blizzard
            end
        end
    end
    return frames
end

-- Teile eines Rahmens an Plätzen in fester Reihenfolge: Plätze nach GF.RELAYOUT_ORDER (die Seite mit Vorrang
-- zuerst; ein Platz, der dort fehlt, folgt in der Reihenfolge von GF.SLOT_NAMES), je Platz nach owner und
-- Schlüssel. pairs() über die Tabellen ließe offen, ob ein Rückruf (onPlaced) die Gegenseite schon im neuen
-- Zustand sieht.
local function PlacedList(blizzard, list)
    local byName = placed[blizzard]
    if not byName then return list end
    local done = {}
    local function add(name)
        local entries = not done[name] and byName[name]
        done[name] = true
        if not entries then return end
        local ids = {}
        for id in pairs(entries) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do list[#list + 1] = { blizzard = blizzard, name = name, entry = entries[id] } end
    end
    for _, name in ipairs(GF.RELAYOUT_ORDER) do add(name) end
    for _, name in ipairs(GF.SLOT_NAMES) do add(name) end
    return list
end

-- Teile an Plätzen neu setzen (Blizzards Größe oder Anordnung änderte sich: Bearbeitungsmodus,
-- DefaultCompactUnitFrameSetup). Im Kampf vorgemerkt (je Rahmen, GF.RelayoutWaiting). frame nil: alle Rahmen;
-- middle true: nur Teile in der Mitte (between). Eigene Kinder (Attach/Slot) setzt Layout neu, andere Teile an
-- Plätzen (sicherer Knopf, Auren-Reihe) setzt GF.Place direkt – nur außerhalb des Kampfes, sonst danach.
-- Ohne middle wird die gemerkte Anordnung der Auren verworfen und neu gelesen (fresh true: sie ist gerade neu
-- gelesen, GF.OnFrameSetup). Die Teile stehen vor dem Setzen in einer Liste (Reihenfolge je Rahmen:
-- GF.RELAYOUT_ORDER): Ein Rückruf (onPlaced) darf dabei weitere Teile anlegen. → Anzahl der Teile
function GF.Relayout(frame, middle, fresh)
    local n = 0
    local frames = RelayoutFrames(frame)
    if not middle then
        if not fresh then GF.DropCache(frame) end
        local list = {}
        for _, blizzard in ipairs(frames) do PlacedList(blizzard, list) end
        local later = false
        for _, item in ipairs(list) do
            n = n + 1
            if Core.InCombat() then
                later = true
            else
                local entry = item.entry
                local ok, err = pcall(GF.Place, entry.region, item.blizzard, item.name, entry.owner, entry.key)
                if not ok then Core.Error(entry.owner, err, "GroupFrames Relayout") end
            end
        end
        if later then
            if frame == nil then waitingAll = true else waitingFrames[frame] = true end
            Core.AfterCombat(GF.RelayoutWaiting, GF.RELAYOUT_KEY, ADDON)
        end
    end
    local kids = {}
    for _, blizzard in ipairs(frames) do
        for owner, own in pairs(store[blizzard] or {}) do
            for key, slot in pairs(own.parts) do
                local name = slot.child and slot.opts.slotName
                local spec = name and FrameSpec(blizzard, name)
                if spec and (not middle or spec.between) then
                    kids[#kids + 1] = { blizzard = blizzard, owner = owner, key = key, slot = slot }
                end
            end
        end
    end
    local inCombat = Core.InCombat()
    for _, kid in ipairs(kids) do
        n = n + 1
        if inCombat then Later(kid.owner, kid.blizzard, kid.key, kid.slot) else Layout(kid.owner, kid.blizzard, kid.slot) end
    end
    if not middle then
        -- Stand merken, für den gesetzt wurde; im Kampf gilt keiner (nach dem Kampf wird neu gesetzt)
        for _, blizzard in ipairs(frames) do
            if inCombat then applied[blizzard] = nil else Remember(blizzard) end
        end
    end
    return n
end

-- Nach Blizzards DefaultCompactUnitFrameSetup (per hooksecurefunc): die Anordnung neu lesen und die Teile nur dann
-- neu setzen, wenn sich etwas geändert hat (Größe, Kraftleiste, Aurengrößen, Anordnung). → Anzahl der Teile
function GF.OnFrameSetup(frame)
    if Forbidden(frame) or not tracked[frame] then return end
    organizations[frame] = nil
    if Unchanged(frame) then return 0 end
    return GF.Relayout(frame, false, true)
end

local setupHooked = false
function GF.HookSetup()
    if not setupHooked and type(hooksecurefunc) == "function" and type(rawget(_G, "DefaultCompactUnitFrameSetup")) == "function" then
        setupHooked = pcall(hooksecurefunc, "DefaultCompactUnitFrameSetup", function(frame) GF.OnFrameSetup(frame) end)
    end
    return setupHooked
end

---------------------------------------------------------------------------
-- Anlässe zum Neu-Einlesen
---------------------------------------------------------------------------

local refresh = Core.Throttle(function()
    GF.Refresh()
    GF.HookSetup()
    GF.Relayout()
end, 0.05, ADDON)
GF.Hook()
GF.HookSetup()
Core.RegisterEvent(ADDON, "GROUP_ROSTER_UPDATE", refresh)
Core.RegisterEvent(ADDON, "PLAYER_ENTERING_WORLD", refresh)
if Core.EditMode and Core.EditMode.OnChange then Core.EditMode.OnChange(refresh, ADDON) end
