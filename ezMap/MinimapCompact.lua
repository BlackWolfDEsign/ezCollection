local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Kompakte Minikarte (Schalter „minimapCompact“, ab Werk aus; Spieltest des Nutzers vom 20.11.2026, Bildschirmfoto mit
    Pfeilen, wörtlich „kannst du das so umbauen? + coords kommt ins stadt kästchen, z.b: Auberdine coords zeit“ und
    „und die minimap entsprechend nach oben rücken“; Antwort auf die Rückfrage vom 20.11.2026: „Lücke schließen
    (Empfohlen)“). Blizzards eigene Teile bekommen eine neue Lage, nichts wird nachgebaut (Leitlinie 1):
      - Koordinaten: Blizzards Zeile unter der Minikarte (MinimapCluster.MinimapContainer.PlayerCoords, Forever-Quelle
        Blizzard_Minimap/Mainline/Minimap.xml, MinimapPlayerCoordsMixin) wandert ins Zonenkästchen
        (MinimapCluster.ZoneTextButton) links neben Blizzards Uhr (TimeManagerClockButton,
        Blizzard_TimeManager/Camelot/Blizzard_TimeManagerOverrides.lua: rechts im Kästchen). Das Kästchen wird dafür
        breiter (Compact.HEADER_WIDTH; seine Grafik füllt es, die XML-Textur hat keine eigenen Anker), der Zonenname
        bekommt den Platz links davon. Ob Koordinaten erscheinen, bestimmt weiter Blizzards Einstellung
        (CVar minimapShowPlayerCoords); ist sie aus, bleiben Kästchen und Zonenname in Blizzards Breite.
      - Das Kästchen mit Ortsname, Koordinaten und Uhr steht am unteren Rand des Rings statt darüber (Spieltest
        20.11.2026 mit roten Rechtecken und Pfeilen, wörtlich „die koordinaten liegen immernoch außerhalb an der original
        position“; Antwort auf die Rückfrage: „Die Elemente in den Rechtecken sollten dort hin wo der Pfeil hinzeigt“),
        verankert an der Minikarte (Compact.BELOW). Die Koordinaten stehen mittig zwischen dem Ende des Ortsnamens und
        dem Anfang der Uhrzeit (Spieltest 20.11.2026, Bild 22:48, wörtlich „die koordianten müssen zwischen zone und
        uhrzeit gleichen abstand haben“; Compact.CoordsCenter, neu nach Blizzards Minimap_Update und
        TimeManagerClockButton_Update); kennt das Spiel die Lage noch nicht, stehen sie vor der Uhr.
      - Lupe (Menü „Aufspüren“, MinimapCluster.Tracking) und Kalender (GameTimeFrame, Camelot/GameTimeFrameTemplate.xml:
        rechts am Kästchen) stehen auf dem Ring der Minikarte – Lupe oben links, Kalender rechts unter Blizzards
        Tag-und-Nacht-Anzeige (Camelot/Diel.lua: Mitte 55, 86 vom Mittelpunkt, etwa 57°). Ist die Minikarte eckig
        (ezMaps „Eckige Minikarte“ oder GetMinimapShape() = „SQUARE“), sitzen sie an der Kante des Quadrats statt auf
        dem Kreis. Blizzards Addon-Fach (AddonCompartmentFrame, die Zahl der Addons; Camelot/AddonCompartment.lua, sonst
        unter dem Kalender) steht rechts vom Kalender (Antwort des Nutzers vom 20.11.2026: „Rechts vom Kalender“). Blizzards Post- und Auftragssymbol (MinimapCluster.IndicatorFrame) hängt sonst
        unter der Lupe (Mainline/Minimap.lua: MiniMapIndicatorFrame_UpdatePosition) – es nimmt Blizzards eigenen Platz
        für „Lupe aus“ links am Kästchen. Auf dem Ring sind Lupe und Kalender rund wie Blizzards eigener Knopf dort
        (Spieltest 20.11.2026, wörtlich „die viereckigen rahmen rund wie bei den anderen“; Shared/
        ExternalEventURLMinimapButton.xml: Kreismaske über dem Bild, Rand-Atlas UI-HUD-Minimap-Frame-Cycle): Maske und
        Rand sind eigene Teile am Knopf, Blizzards Hintergrund der Lupe wird unsichtbar; aus wieder eckig.
      - Die Minikarte rückt um Compact.UP Bildpunkte nach oben an den frei gewordenen Platz des Kästchens
        (MinimapContainer; Blizzards Lage, vor dem Umbau gemerkt, TOP x 10, y −30 laut Minimap.xml). Liegt dort
        ezPanels Leiste, ohne dass ezPanel Platz schafft („Platz oben für die Leiste“ aus), rückt sie nur bis unter die
        Leiste (panel.TopCover, neu nach panel.TOPSPACE; Antwort des Nutzers vom 21.11.2026: „Yes, move it down
        (Recommended)“ auf die Frage, ob die Minikarte dann um die Leistenhöhe weniger hoch rücken soll).
      - Mit ezPanel (Antwort des Nutzers vom 20.11.2026, wörtlich „die bestehenden bausteine rechts anordnen und
        blizzards bar am ring unten entfernen“): Beim Einschalten stellt ezMap ezPanels Bausteine „Ort“ und „Uhr“
        einmal rechts ans Ende der Leiste (panel.PlaceBlocks; danach darf der Nutzer sie woandershin ziehen). Solange
        beide auf der Leiste stehen (panel.BlockShown), verbirgt ezMap Blizzards Kästchen, Koordinaten und Uhr unter dem
        Ring (Compact.PANEL_FRAMES) und hält sie verborgen; das Postsymbol steht dann unten links auf dem Ring.
        Schaltet der Nutzer einen der beiden Bausteine oder die Leiste ab (Nachricht panel.LAYOUT) oder die kompakte
        Minikarte aus, kommt das Kästchen zurück – nur, was ezMap selbst verborgen hat. Ohne ezPanel bleibt es am Ring.
    Taint (Leitlinie 5): keiner dieser Rahmen ist geschützt; ezMap ruft nur ihre Methoden (SetPoint, SetWidth,
    SetFrameLevel), schreibt nichts in Blizzards Tabellen (auch nicht in defaultFramePoints, das Blizzards
    ResetFramePoints liest) und baut nur außerhalb des Kampfes um. Blizzards Bearbeitungsmodus setzt die Lage neu
    (MinimapClusterMixin:SetHeaderUnderneath, SetEditModeScale): danach wieder kompakt; das Zurückgeben direkt nach
    SetHeaderUnderneath läuft sofort (der Bearbeitungsmodus ist im Kampf ohnehin zu). Steht das Kästchen unter der
    Minikarte (Einstellung im Bearbeitungsmodus, gelesen an Blizzards Anker des Kästchens), bleibt Blizzards Lage – der
    Umbau gilt nur für das Kästchen oben. Beim Betreten der Welt und nach EDIT_MODE_LAYOUTS_UPDATED baut ezMap eine
    Bildschirmaktualisierung später noch einmal (Spieltest 20.11.2026: im Spiel war vom Umbau nichts zu sehen); warum
    gerade nicht umgebaut ist (fehlende Teile, Fehler, Kampf), sagt die Statuszeile. Ausschalten gibt jedem Teil
    Blizzards Anker, Breite und Ebene zurück (vor dem
    ersten Umbau gemerkt). Gestaltet ein anderes Addon die Minikarte (SexyMap; ezCores Funktionsschlüssel
    „minimapShape“), hält sich ezMap heraus.
]]
local Compact = {}
ns.MinimapCompact = Compact

Compact.HEADER_WIDTH = 190      -- Bildpunkte: Blizzards Kästchen ist 152 breit (MinimapZoneTextButton.xml)
Compact.COORDS_WIDTH = 58       -- Platz für „38.6, 43.0“ (GameFontHighlightSmall)
Compact.CLOCK_GAP = 6           -- Abstand der Koordinaten zur Uhr (deren Zahl steht rechts im Knopf, HitRect links 8)
Compact.EDGE = 8                -- Abstand der Koordinaten zum rechten Rand, solange Blizzards Uhr fehlt
-- so viel rückt die Minikarte nach oben: um den ganzen Platz des Kästchens, ohne Lücke (Blizzards Minikarte steht 30
-- unter seiner Oberkante, Minimap.xml; Spieltest 20.11.2026, wörtlich „mini map um die höhe des balken nach oben
-- setzen, so dass keine lücke mehr ist“ – vorher 26)
Compact.UP = 30
Compact.BELOW = 6               -- Abstand des Kästchens unter der Minikarte: knapp unter dem Ring (im Spiel prüfen)
-- Addon-Fach rechts vom Kalender ohne Abstand (Spieltest 20.11.2026, wörtlich „kalender und zahl dürfen keinen abstand
-- haben“): Blizzards Rand des Rings reicht über den Knopf hinaus, das Bild des Fachs hat einen leeren Rand – darum
-- überlappen die Rahmen; Blizzard legt das Fach ebenso 1 Bildpunkt über den Kalender (Camelot/AddonCompartment.xml)
Compact.COMPARTMENT_GAP = -2
Compact.RING = 5                -- Bildpunkte außerhalb des Kartenrands: Mitte der Knöpfe auf dem Ring
Compact.TRACKING_ANGLE = 135    -- Grad gegen den Uhrzeigersinn von Osten: oben links
Compact.CALENDAR_ANGLE = 30     -- rechts oben, unter Blizzards Tag-und-Nacht-Anzeige (etwa 57°)
-- Runde Rahmen auf dem Ring (Spieltest 20.11.2026, wörtlich „die viereckigen rahmen rund wie bei den anderen“): wie
-- Blizzards eigener Knopf auf dem Ring der Minikarte (Forever-Quelle Blizzard_Minimap/Shared/
-- ExternalEventURLMinimapButton.xml: Bild mit der Kreismaske TempPortraitAlphaMask, darüber der Rand; Camelot/Minimap.lua,
-- ExternalEventURLMinimapButtonStyle: Rand-Atlas UI-HUD-Minimap-Frame-Cycle, 42 auf einen Knopf von 32)
Compact.RING_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Compact.RING_ATLAS = "UI-HUD-Minimap-Frame-Cycle"
Compact.RING_FALLBACK = "Interface\\Common\\RingBorder"        -- Blizzards Rand im XML, bevor der Stil ihn setzt
Compact.RING_RATIO = 42 / 32
-- ezPanels Bausteine, die das Kästchen ersetzen – in dieser Reihenfolge rechts (die Uhr ganz außen, wo Blizzards Uhr war)
Compact.PANEL_BLOCKS = { "location", "clock" }
Compact.PANEL_FRAMES = { "header", "coords", "clock" }      -- Schlüssel aus Parts: was ezPanel dann zeigt
Compact.INDICATOR_ANGLE = 225   -- Postsymbol ohne Kästchen: unten links auf dem Ring

local active = false
local problem                   -- warum zuletzt nicht umgebaut wurde (Statuszeile), nil: kein Problem
local saved = {}                -- [Rahmen] = { points, width, level, scale } – Blizzards Lage vor dem ersten Umbau
local rounds = {}               -- [Knopf] = { mask, border, masked = { [Textur] = true }, alpha = { [Textur] = Wert } }
local inPanel = false           -- Ort und Uhr stehen auf ezPanels Leiste: Blizzards Kästchen ist verborgen
local hiddenByUs = {}           -- [Rahmen] = true: von ezMap verborgen (nur das zeigt ezMap wieder)
local lastCover                 -- zuletzt beim Umbau gemessene Überdeckung durch ezPanels Leiste (Compact.BarCover)

local function Cluster() return rawget(_G, "MinimapCluster") end

-- nur Rahmen (Tabellen) – fehlt ein Teil, bleibt es weg
local function F(v) if type(v) == "table" then return v end return nil end

local function Parts()
    local c = F(Cluster())
    if not c then return nil end
    local container = F(c.MinimapContainer)
    local tracking = F(c.Tracking)
    return {
        trackingButton = tracking and F(tracking.Button) or nil,
        cluster = c,
        header = F(c.ZoneTextButton),
        zoneText = F(rawget(_G, "MinimapZoneText")),
        container = container,
        map = (container and F(container.Minimap)) or F(rawget(_G, "Minimap")),
        coords = container and F(container.PlayerCoords) or nil,
        tracking = F(c.Tracking),
        indicator = F(c.IndicatorFrame),
        calendar = F(rawget(_G, "GameTimeFrame")),
        clock = F(rawget(_G, "TimeManagerClockButton")),
        compartment = F(rawget(_G, "AddonCompartmentFrame")),
    }
end

-- Kästchen unter der Minikarte? Gelesen an Blizzards Anker (den setzt nur Blizzard: SetHeaderUnderneath unten
-- „BOTTOM“, oben die gemerkte Lage „TOP“) – so stimmt es auch, wenn Blizzards Layout vor ezMaps Haken kam.
function Compact.HeaderBelow()
    local c = F(Cluster())
    local header = c and F(c.ZoneTextButton)
    if not (header and header.GetPoint) then return false end
    return header:GetPoint(1) == "BOTTOM"
end

-- Blizzards Koordinaten an? (CVar minimapShowPlayerCoords; unbekannt = an)
function Compact.CoordsShown()
    local get = rawget(_G, "GetCVarBool")
    if type(get) ~= "function" then return true end
    return get("minimapShowPlayerCoords") ~= false
end

-- Eckige Minikarte: ezMaps eigene oder die eines Addons, das GetMinimapShape() meldet
function Compact.Square()
    local shape = ns.MinimapShape
    if shape and shape.Wanted and shape.Wanted() then return true end
    local get = rawget(_G, "GetMinimapShape")
    if type(get) ~= "function" then return false end
    local ok, s = pcall(get)
    return ok and s == "SQUARE"
end

function Compact.Elsewhere() return ns.OtherFor("minimapShape") end
function Compact.Wanted()
    return ns.Enabled("minimapCompact") and not Compact.Elsewhere() and not Compact.HeaderBelow()
end
function Compact.Active() return active end

local function Scale(frame)
    local s = frame and frame.GetScale and Core.Num(frame:GetScale()) or 1
    if not s or s <= 0 then return 1 end
    return s
end

-- Blizzards Lage, Breite und Ebene eines Rahmens merken (einmal, vor dem ersten Umbau); withScale: Versätze gelten in
-- der Skalierung des Rahmens (MinimapContainer, Blizzards ResetFramePoints mit accountForFrameScale)
local function Remember(frame, withWidth, withScale)
    if type(frame) ~= "table" or saved[frame] or type(frame.GetNumPoints) ~= "function" then return end
    local entry = { points = {} }
    for i = 1, frame:GetNumPoints() do
        entry.points[i] = { frame:GetPoint(i) }
    end
    if withWidth and frame.GetWidth then entry.width = frame:GetWidth() end
    if frame.GetFrameLevel then entry.level = frame:GetFrameLevel() end
    if withScale then entry.scale = Scale(frame) end
    saved[frame] = entry
end

-- Versätze des gemerkten Punkts in der heutigen Skalierung (Blizzard rechnet seine nur in SetHeaderUnderneath um)
local function Offsets(frame, entry, p)
    local f = entry.scale and entry.scale / Scale(frame) or 1
    return (p[4] or 0) * f, (p[5] or 0) * f
end

local function Restore(frame)
    local entry = type(frame) == "table" and saved[frame]
    if not entry then return end
    frame:ClearAllPoints()
    for _, p in ipairs(entry.points) do
        local x, y = Offsets(frame, entry, p)
        frame:SetPoint(p[1], p[2], p[3], x, y)
    end
    if entry.width and frame.SetWidth then frame:SetWidth(entry.width) end
    if entry.level and frame.SetFrameLevel then frame:SetFrameLevel(entry.level) end
end

-- nur Breite und Ebene zurück (die Anker setzt Blizzard eben selbst)
local function RestoreSize(frame)
    local entry = type(frame) == "table" and saved[frame]
    if not entry then return end
    if entry.width and frame.SetWidth then frame:SetWidth(entry.width) end
    if entry.level and frame.SetFrameLevel then frame:SetFrameLevel(entry.level) end
end

-- Mitte eines Knopfs auf dem Ring: Winkel in Grad, Abstand in den Maßen des Knopfs (die Minikarte kann im
-- Bearbeitungsmodus anders skaliert sein als der Knopf) → x, y vom Mittelpunkt der Minikarte. Eckige Minikarte: auf
-- der Kante des Quadrats (Abstand je Winkel geteilt durch max(|cos|, |sin|)).
function Compact.RingOffset(parts, angle, square)
    local w = parts.map and parts.map.GetWidth and Core.Num(parts.map:GetWidth()) or nil
    if not w or w <= 0 then return nil end
    local rad = math.rad(angle)
    local c, s = math.cos(rad), math.sin(rad)
    local r = (w / 2 + Compact.RING) * Scale(parts.container)
    if square then r = r / math.max(math.abs(c), math.abs(s)) end
    return r * c, r * s
end

local function OnRing(parts, button, angle)
    if type(button) ~= "table" or not parts.map then return end
    local x, y = Compact.RingOffset(parts, angle, Compact.Square())
    if not x then return end
    Remember(button)
    button:ClearAllPoints()
    button:SetPoint("CENTER", parts.map, "CENTER", x, y)
    -- über dem Ring der Minikarte (sonst läge er unter Blizzards Rahmen)
    if button.SetFrameLevel and parts.map.GetFrameLevel then button:SetFrameLevel(parts.map:GetFrameLevel() + 10) end
end

-- Blizzards eckigen Knopf rund zeigen: seine Bilder (Zustand und Aufhellung; Blizzard tauscht nur deren Atlas, die Maske
-- bleibt) unter die Kreismaske, darüber Blizzards Rand des Rings; Flächen, die nur das Quadrat zeichnen (der Hintergrund
-- der Lupe), unsichtbar. Maske und Rand sind eigene Teile am Knopf – in Blizzards Tabellen wird nichts geschrieben.
local function Ring(button, textures, hide)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function"
        or type(button.CreateMaskTexture) ~= "function" then return false end
    local r = rounds[button]
    if not r then
        r = { masked = {}, alpha = {} }
        r.mask = button:CreateMaskTexture()
        r.mask:SetTexture(Compact.RING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        r.mask:SetAllPoints(button)
        r.border = button:CreateTexture(nil, "OVERLAY")
        local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(Compact.RING_ATLAS)
        if atlas and r.border.SetAtlas then r.border:SetAtlas(Compact.RING_ATLAS) else r.border:SetTexture(Compact.RING_FALLBACK) end
        r.border:SetPoint("CENTER", button, "CENTER", 0, 0)
        rounds[button] = r
    end
    for _, tex in ipairs(textures) do
        if type(tex) == "table" and tex.AddMaskTexture and not r.masked[tex] then
            tex:AddMaskTexture(r.mask)
            r.masked[tex] = true
        end
    end
    -- ohne ein einziges maskiertes Bild kein runder Rand um ein eckiges Bild (Review 20.11.2026)
    if next(r.masked) == nil then
        r.border:Hide()
        return false
    end
    local size = (button.GetWidth and Core.Num(button:GetWidth()) or 0) * Compact.RING_RATIO
    if size > 0 then r.border:SetSize(size, size) end
    r.border:Show()
    for _, tex in ipairs(hide or {}) do
        if type(tex) == "table" and tex.SetAlpha and r.alpha[tex] == nil then
            r.alpha[tex] = tex.GetAlpha and Core.Num(tex:GetAlpha()) or 1
            tex:SetAlpha(0)
        end
    end
    return true
end

-- Blizzards eckige Form zurück (Maske ab, Rand weg, Flächen sichtbar)
local function Unring(button)
    local r = type(button) == "table" and rounds[button]
    if not r then return end
    r.border:Hide()
    for tex in pairs(r.masked) do
        if tex.RemoveMaskTexture then tex:RemoveMaskTexture(r.mask) end
    end
    for tex, alpha in pairs(r.alpha) do tex:SetAlpha(alpha) end
    wipe(r.masked)
    wipe(r.alpha)
end
Compact.Ring, Compact.Unring = Ring, Unring
function Compact.Round(button) return rounds[button] ~= nil and rounds[button].border:IsShown() == true end

local function RingParts(p)
    local tb = p.trackingButton
    Ring(tb, { tb and tb.StateTexture, tb and tb.AddTexture }, { p.tracking and p.tracking.Background })
    local cal = p.calendar
    Ring(cal, { cal and cal.StateTexture, cal and cal.AddTexture })
end

local function UnringParts(p)
    Unring(p.trackingButton)
    Unring(p.calendar)
end

-- Post- und Auftragssymbol an Blizzards eigenen Platz für „Lupe aus“ (MiniMapIndicatorFrame_UpdatePosition) links am
-- Kästchen; ist das Kästchen verborgen (Ort und Uhr in ezPanel), unten links auf den Ring
local function PlaceIndicator(p)
    if not (p.indicator and p.header) then return end
    if inPanel then
        OnRing(p, p.indicator, Compact.INDICATOR_ANGLE)
        return
    end
    Remember(p.indicator)
    RestoreSize(p.indicator)    -- Ebene zurück, falls es eben noch auf dem Ring stand
    p.indicator:ClearAllPoints()
    p.indicator:SetPoint("TOPRIGHT", p.header, "TOPLEFT", -5, -1)
end

-- Koordinaten zurück an Blizzards Platz, Kästchen und Zonenname in Blizzards Breite (Koordinaten aus)
-- (das Kästchen behält seinen Merker: es steht weiter unter der Minikarte und bekommt beim Ausschalten Blizzards Lage)
local function CoordsBack(p)
    Restore(p.coords)
    Restore(p.zoneText)
    RestoreSize(p.header)
    for _, frame in ipairs({ p.coords, p.zoneText }) do
        if frame then saved[frame] = nil end
    end
end

-- Kästchen samt Ortsname, Koordinaten und Uhr an den unteren Rand des Rings (Antwort des Nutzers vom 20.11.2026, wörtlich
-- „Die Elemente in den Rechtecken sollten dort hin wo der Pfeil hinzeigt“: Pfeil vom Kästchen oben durch die Karte an
-- den unteren Rand des Rings). Verankert an der Minikarte selbst – es wandert mit, wenn der Bearbeitungsmodus sie
-- skaliert oder verschiebt.
local function PlaceHeader(p)
    if not (p.header and p.map) then return end
    Remember(p.header, true)
    p.header:ClearAllPoints()
    p.header:SetPoint("TOP", p.map, "BOTTOM", 0, -Compact.BELOW)
end

-- Wo die Koordinaten mittig zwischen Ortsname und Uhr stehen (Spieltest 20.11.2026, wörtlich „die koordianten müssen
-- zwischen zone und uhrzeit gleichen abstand haben“): Ende des Ortsnamens (MinimapZoneText ist linksbündig) und Anfang
-- der Uhrzeit (TimeManagerClockTicker steht mittig im Knopf), Mitte davon. → x vom linken Rand des Kästchens oder nil,
-- solange das Spiel noch keine Lage kennt. Alle Maße in den Einheiten des Kästchens (die Teile können verschieden
-- skaliert sein: die Koordinaten hängen an der Minikarte, die der Bearbeitungsmodus vergrößert). ns.Num: nil, geheim
-- oder keine Zahl → nil (Leitlinie 6)

-- Faktor von Einheiten des Rahmens a in Einheiten des Rahmens b (unbekannt: 1)
local function Ratio(a, b)
    local sa = a and a.GetEffectiveScale and ns.Num(a:GetEffectiveScale())
    local sb = b and b.GetEffectiveScale and ns.Num(b:GetEffectiveScale())
    if not (sa and sb) or sa <= 0 or sb <= 0 then return 1 end
    return sa / sb
end
Compact.Ratio = Ratio

function Compact.CoordsCenter(p)
    if not (p and p.header and p.zoneText) then return nil end
    local left = p.header.GetLeft and ns.Num(p.header:GetLeft())
    local zoneLeft = p.zoneText.GetLeft and ns.Num(p.zoneText:GetLeft())
    local zoneWidth = p.zoneText.GetStringWidth and ns.Num(p.zoneText:GetStringWidth())
    if not (left and zoneLeft and zoneWidth) then return nil end
    local boxWidth = p.zoneText.GetWidth and ns.Num(p.zoneText:GetWidth())
    if boxWidth and zoneWidth > boxWidth then zoneWidth = boxWidth end       -- gekürzter Name endet am Feld
    local zoneEnd = (zoneLeft + zoneWidth) * Ratio(p.zoneText, p.header)
    local clockStart
    local ticker = F(rawget(_G, "TimeManagerClockTicker"))
    -- nur bis zu einer sichtbaren Uhr (ezPanels „Uhr der Minikarte ausblenden“ verbirgt sie)
    local clockShown = p.clock and p.clock.IsShown and p.clock:IsShown()
    if clockShown and ticker and ticker.GetCenter and ticker.GetStringWidth then
        local cx = ns.Num((ticker:GetCenter()))
        local tw = ns.Num(ticker:GetStringWidth())
        if cx and tw then clockStart = (cx - tw / 2) * Ratio(ticker, p.header) end
    end
    if not clockStart then
        local right = p.header.GetRight and ns.Num(p.header:GetRight())
        if not right then return nil end
        clockStart = right - Compact.EDGE
    end
    if clockStart <= zoneEnd then return nil end
    return (zoneEnd + clockStart) / 2 - left
end

-- Koordinaten in die Mitte zwischen Ortsname und Uhr (sonst bleibt der Anker vor der Uhr). Der Versatz gilt in den
-- Einheiten der Koordinaten. Steht sie schon dort, bleibt der Anker. → true, wenn sie mittig stehen
local function CenterCoords(p)
    if not (p and p.coords and p.header) then return false end
    local x = Compact.CoordsCenter(p)
    if not x then return false end
    x = x * Ratio(p.header, p.coords)
    local point, rel, _, ox = p.coords:GetPoint(1)
    if point == "CENTER" and rel == p.header and ox == x then return true end
    p.coords:ClearAllPoints()
    p.coords:SetPoint("CENTER", p.header, "LEFT", x, -1)
    return true
end
Compact.CenterCoords = CenterCoords

-- ezPanel: Ort und Uhr auf der Leiste? (Antwort des Nutzers vom 20.11.2026, wörtlich „die bestehenden bausteine rechts
-- anordnen und blizzards bar am ring unten entfernen“)
local function Panel()
    local api = Core.API and Core.API("ezPanel")
    if type(api) == "table" then return api end
    return nil
end

function Compact.PanelShows()
    local panel = Panel()
    if not (panel and type(panel.BlockShown) == "function") then return false end
    for _, id in ipairs(Compact.PANEL_BLOCKS) do
        if panel.BlockShown(id) ~= true then return false end
    end
    return true
end
function Compact.InPanel() return inPanel end
Compact.HiddenByUs = hiddenByUs          -- für die Prüfungen

-- Einmal beim Einschalten: Ort und Uhr rechts ans Ende der Leiste (und an, auch eine vorher abgeschaltete Uhr – sie
-- ersetzt Blizzards Uhr). Nicht, wenn die kompakte Minikarte gar nicht greift (SexyMap, Kästchen unten). → Anzahl
function Compact.ArrangePanel()
    if not Compact.Wanted() then return 0 end
    local panel = Panel()
    if not (panel and type(panel.PlaceBlocks) == "function") then return 0 end
    return panel.PlaceBlocks(Compact.PANEL_BLOCKS, "right") or 0
end

-- So viel (in den Versatz-Einheiten des Containers) liegt ezPanels Leiste über dem Platz, an den die Minikarte rücken
-- würde: was die Leiste oben einnimmt (panel.TopCover), weniger dem Abstand des Minikarten-Rahmens zum oberen
-- Bildschirmrand – gemessen, nicht aus dem Schalter geschlossen: ezPanels „Platz oben“ rückt den Rahmen nur in
-- Blizzards Standardlage darunter, im Bearbeitungsmodus an den Rand gesetzt bleibt er oben (Fund des code-reviewers).
-- Lage unbekannt: wie am Rand.
function Compact.BarCover(p)
    local panel = Panel()
    if not (p and p.container and panel and type(panel.TopCover) == "function") then return 0 end
    local ok, cover = pcall(panel.TopCover)
    cover = ok and ns.Num(cover) or nil
    if not cover or cover <= 0 then return 0 end
    local ui = rawget(_G, "UIParent")
    local above = 0
    if ui and ui.GetTop and p.cluster and p.cluster.GetTop then
        local uiTop, top = ns.Num(ui:GetTop()), ns.Num(p.cluster:GetTop())
        if uiTop and top then above = math.max(0, uiTop - top * Ratio(p.cluster, ui)) end
    end
    local overlap = cover - above
    if overlap <= 0 then return 0 end
    return overlap * Ratio(ui, p.container)
end

-- Verborgen halten: an OnShow und OnHide gehakt (HookScript – anders als ein Haken an der Methode Show schreibt das
-- nichts in Blizzards Rahmen-Tabelle, Leitlinie 5). Zeigt Blizzard den Rahmen wieder, solange Ort und Uhr in ezPanel
-- stehen, verbirgt ezMap ihn gleich wieder. Verbirgt ihn jemand anderes (Blizzard: Koordinaten aus; ezPanels „Uhr der
-- Minikarte ausblenden“), fällt ezMaps Merker – ezMap zeigt ihn dann nicht wieder. OnHide kommt auch, wenn nur die
-- Minikarte verschwindet (Haustierkampf): dann bleibt IsShown() wahr und der Merker bleibt.
local hidingOwn = false
local hookedShow = {}
local function HideOwn(frame)
    hiddenByUs[frame] = true
    hidingOwn = true
    local ok, err = pcall(frame.Hide, frame)
    hidingOwn = false
    if not ok then ns.Error(err, "MinimapCompact.Hide") end
end

local function KeepHidden(frame)
    if type(frame) ~= "table" or type(frame.Hide) ~= "function" or type(frame.IsShown) ~= "function" then return end
    if not hookedShow[frame] and type(frame.HookScript) == "function" then
        hookedShow[frame] = true
        frame:HookScript("OnShow", function(self)
            if inPanel then HideOwn(self) else hiddenByUs[self] = nil end
        end)
        frame:HookScript("OnHide", function(self)
            if not hidingOwn and not self:IsShown() then hiddenByUs[self] = nil end
        end)
    end
    if frame:IsShown() then HideOwn(frame) end
end

-- Wieder zeigen, was ezMap verborgen hat
local function ShowAgain()
    local list = {}
    for frame in pairs(hiddenByUs) do list[#list + 1] = frame end
    for _, frame in ipairs(list) do
        hiddenByUs[frame] = nil
        frame:Show()
    end
end
Compact.ShowAgain = ShowAgain

local function PanelFrames(p, on)
    inPanel = on
    if on then
        for _, key in ipairs(Compact.PANEL_FRAMES) do
            if key == "coords" and not Compact.CoordsShown() then
                -- Blizzards Einstellung aus: Blizzard verbirgt sie selbst. Verbarg ezMap sie vorher, kam beim
                -- zweiten Verbergen kein OnHide – der Merker fällt hier, sonst zeigte ShowAgain sie später gegen die
                -- Einstellung
                if p.coords then hiddenByUs[p.coords] = nil end
            else
                KeepHidden(p[key])
            end
        end
    else
        ShowAgain()
    end
end

-- Umbau sofort (nur außerhalb des Kampfes; Compact.Apply sorgt dafür)
local function Build(p)
    -- zuerst: davon hängt der Platz des Postsymbols ab
    PanelFrames(p, Compact.PanelShows())
    PlaceHeader(p)
    -- Kästchen breiter, Zonenname links, Koordinaten vor der Uhr – nur, solange Blizzard Koordinaten zeigt
    if not Compact.CoordsShown() then
        CoordsBack(p)
    else
        Remember(p.header, true)
        if p.header and p.header.SetWidth then p.header:SetWidth(Compact.HEADER_WIDTH) end
        -- Platz rechts der Koordinaten: Uhr minus Abstand, sonst der Rand
        local right = Compact.EDGE
        if p.clock and p.clock.GetWidth then
            right = math.max(0, (Core.Num(p.clock:GetWidth()) or 0) - Compact.CLOCK_GAP)
        end
        if p.coords then
            Remember(p.coords, true)
            p.coords:ClearAllPoints()
            if p.clock then
                p.coords:SetPoint("RIGHT", p.clock, "LEFT", Compact.CLOCK_GAP, 0)
            elseif p.header then
                p.coords:SetPoint("RIGHT", p.header, "RIGHT", -Compact.EDGE, -1)
            end
            p.coords:SetWidth(Compact.COORDS_WIDTH)
            if p.coords.SetFrameLevel and p.header and p.header.GetFrameLevel then
                p.coords:SetFrameLevel(p.header:GetFrameLevel() + 2)
            end
        end
        if p.zoneText and p.zoneText.SetWidth then
            Remember(p.zoneText, true)
            p.zoneText:SetWidth(math.max(40, Compact.HEADER_WIDTH - 8 - Compact.COORDS_WIDTH - right))
        end
        CenterCoords(p)
    end
    -- Lupe und Kalender auf den Ring; das Addon-Fach rechts vom Kalender (Antwort des Nutzers vom 20.11.2026, wörtlich
    -- „Rechts vom Kalender“), das Postsymbol links ans Kästchen
    OnRing(p, p.tracking, Compact.TRACKING_ANGLE)
    OnRing(p, p.calendar, Compact.CALENDAR_ANGLE)
    RingParts(p)
    PlaceIndicator(p)
    if p.compartment and p.calendar then
        Remember(p.compartment)
        p.compartment:ClearAllPoints()
        p.compartment:SetPoint("LEFT", p.calendar, "RIGHT", Compact.COMPARTMENT_GAP, 0)
        if p.compartment.SetFrameLevel and p.calendar.GetFrameLevel then
            p.compartment:SetFrameLevel(p.calendar:GetFrameLevel())
        end
    end
    -- Minikarte nach oben an den Platz des Kästchens: Blizzards gemerkter Versatz (in der heutigen Skalierung) plus
    -- Compact.UP, weniger dem, was ezPanels Leiste dort überdeckt (nie tiefer als Blizzards Lage)
    if p.container and p.cluster then
        Remember(p.container, false, true)
        local entry = saved[p.container]
        local first = entry and entry.points[1]
        local scale = Scale(p.container)
        local x, y = 10 / scale, -30 / scale
        if first and first[1] == "TOP" then x, y = Offsets(p.container, entry, first) end
        p.container:ClearAllPoints()
        lastCover = Compact.BarCover(p)
        local up = math.max(0, Compact.UP / scale - lastCover)
        p.container:SetPoint("TOP", p.cluster, "TOP", x, y + up)
    end
end

local function Undo(p)
    PanelFrames(p, false)
    for _, frame in ipairs({ p.header, p.coords, p.zoneText, p.tracking, p.calendar, p.indicator, p.compartment,
        p.container }) do
        Restore(frame)
    end
    UnringParts(p)
    wipe(saved)
end

-- Warum gerade nicht umgebaut (Statuszeile, Spieltest 20.11.2026: der Umbau griff im Spiel nicht, ohne dass man sah,
-- warum). → Text oder nil
function Compact.Problem() return problem end

-- Fehlende Teile Blizzards (Schlüssel aus Parts), mit Komma. → Text oder nil
function Compact.Missing(p)
    local out = {}
    for _, key in ipairs({ "header", "container", "map", "coords", "tracking", "trackingButton", "calendar" }) do
        if not p[key] then out[#out + 1] = key end
    end
    if #out == 0 then return nil end
    return table.concat(out, ", ")
end

function Compact.ApplyNow()
    local p = Parts()
    if not p then
        problem = L.STATUS_COMPACT_MISSING:format("MinimapCluster")
        return false
    end
    if Compact.Wanted() then
        local missing = Compact.Missing(p)
        problem = missing and L.STATUS_COMPACT_MISSING:format(missing) or nil
        local ok, err = pcall(Build, p)
        if not ok then
            problem = L.STATUS_COMPACT_ERROR:format(tostring(err))
            ns.Error(err, "MinimapCompact.Build")
        end
        active = true
    elseif active then
        Undo(p)
        active = false
        problem = nil
    else
        problem = nil
    end
    return true
end

-- Kompakt oder Blizzards Lage, wie gewünscht; im Kampf erst danach (nur der letzte Wunsch zählt). → true, wenn sofort
function Compact.Apply()
    if not Cluster() then return false end
    Compact.Hook()
    return ns.AfterCombat(Compact.ApplyNow, "minimapCompact") == true
end

-- Blizzards Bearbeitungsmodus setzt Kästchen und Minikarte neu. SetHeaderUnderneath setzt Minikarte, Kästchen,
-- Postsymbol und Addon-Fach selbst (oben: Blizzards gemerkte Anker, unten: eigene) – deren Anker bleiben, wie Blizzard
-- sie eben gesetzt hat; ezMap gibt nur zurück, was Blizzard dort nicht anfasst (Koordinaten, Zonenname, Breite und
-- Ebene des Kästchens, Lupe, Kalender, Ebenen), und baut danach – Kästchen oben – mit frisch gemerkter Lage neu.
-- SetEditModeScale ändert die Größe: Ring und Versatz neu rechnen.
local function OnHeaderUnderneath()
    if active then
        local p = Parts()
        if p then
            for _, frame in ipairs({ p.coords, p.zoneText, p.tracking, p.calendar }) do Restore(frame) end
            for _, frame in ipairs({ p.header, p.indicator, p.compartment, p.container }) do RestoreSize(frame) end
            UnringParts(p)      -- Kästchen jetzt unten: Lupe und Kalender wieder eckig an Blizzards Platz
            PanelFrames(p, false)
        end
        wipe(saved)
        active = false
    end
    Compact.Apply()
end

local function OnEditModeScale()
    if active then Compact.Apply() end
end

-- Blizzard hängt das Postsymbol wieder an die Lupe, sobald sie erscheint: zurück an den Platz links am Kästchen
local function OnIndicatorPosition()
    if active then
        local p = Parts()
        if p then PlaceIndicator(p) end
    end
end

-- Blizzard schreibt einen neuen Ortsnamen (Minimap_Update) bzw. eine neue Uhrzeit (TimeManagerClockButton_Update):
-- die Koordinaten wieder in die Mitte
local function CenterNow()
    if active and not inPanel and Compact.CoordsShown() then CenterCoords(Parts()) end
end
-- im Kampf erst danach (Umbau nur außerhalb des Kampfes; nur der letzte Wunsch zählt)
local function OnTextChanged()
    if active and not inPanel then ns.AfterCombat(CenterNow, "minimapCompactCenter") end
end
Compact.OnTextChanged = OnTextChanged

-- je Methode einmal; Compact.Apply ruft es jedes Mal – ersetzt jemand die Methode später, wird die neue gehakt
local hookedFns = {}
function Compact.Hook()
    local c = Cluster()
    if type(c) ~= "table" then return end
    for key, fn in pairs({ SetHeaderUnderneath = OnHeaderUnderneath, SetEditModeScale = OnEditModeScale }) do
        if type(c[key]) == "function" and c[key] ~= hookedFns[key] then
            hooksecurefunc(c, key, fn)
            hookedFns[key] = c[key]
        end
    end
    local upd = rawget(_G, "MiniMapIndicatorFrame_UpdatePosition")
    if type(upd) == "function" and upd ~= hookedFns.indicator then
        hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", OnIndicatorPosition)
        hookedFns.indicator = rawget(_G, "MiniMapIndicatorFrame_UpdatePosition")
    end
    for _, name in ipairs({ "Minimap_Update", "TimeManagerClockButton_Update" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" and fn ~= hookedFns[name] then
            hooksecurefunc(name, OnTextChanged)
            hookedFns[name] = rawget(_G, name)
        end
    end
end

ns.OnReady(function() Compact.Apply() end)
-- Nach dem Laden setzt Blizzard die Lage aus dem Bearbeitungsmodus (EDIT_MODE_LAYOUTS_UPDATED, beim Betreten der Welt):
-- danach noch einmal bauen, eine Bildschirmaktualisierung später – unabhängig davon, ob Blizzard dabei
-- SetHeaderUnderneath ruft (Spieltest 20.11.2026: der Umbau vom Einloggen war im Spiel nicht zu sehen)
local function Later()
    if not ns.Enabled("minimapCompact") then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.Try("MinimapCompact", Compact.Apply) end)
    else
        ns.Try("MinimapCompact", Compact.Apply)
    end
end
Compact.Later = Later
ns.On("PLAYER_ENTERING_WORLD", Later)
ns.On("EDIT_MODE_LAYOUTS_UPDATED", Later)
-- Blizzards Uhr kommt mit Blizzard_TimeManager, das Addon-Fach mit Blizzard_Minimap: danach den Platz neu setzen
ns.WhenAddOnLoaded("Blizzard_TimeManager", function() if active then Compact.Apply() end end)
ns.OnSettingChanged(function(key)
    if key == "minimapCompact" then
        if ns.Enabled("minimapCompact") then Compact.ArrangePanel() end      -- einmal: Ort und Uhr rechts in ezPanel
        Compact.Apply()
    elseif key == "minimapSquare" and active then Compact.Apply() end    -- Kreis oder Kante des Quadrats
end)
ns.On("CVAR_UPDATE", function(_, name)
    if name == "minimapShowPlayerCoords" and active then Compact.Apply() end
end)
Core.Listen("OTHER_ADDONS_CHANGED", function() ns.Try("MinimapCompact", Compact.Apply) end, "ezMap.MinimapCompact")
-- ezPanel hat die Leiste neu angeordnet: Ort oder Uhr an oder aus, Leiste an oder aus → Kästchen verbergen oder zeigen
-- (nur, wenn sich daran etwas ändert; der Name kommt aus ezPanels API, hier ausgeschrieben für Core.MESSAGES)
local function OnPanelLayout()
    if active and Compact.PanelShows() ~= inPanel then ns.Try("MinimapCompact", Compact.Apply) end
end
Compact.OnPanelLayout = OnPanelLayout
Core.Listen("EZPANEL_LAYOUT", OnPanelLayout, "ezMap.MinimapCompact")
-- ezPanel hat den Platz oben neu berechnet („Platz oben“ umgeschaltet, Leiste an, aus, höher, automatisch
-- ausgeblendet): Minikarte neu setzen (Compact.Apply: nur außerhalb des Kampfes, sonst danach)
-- Eine Bildschirmaktualisierung später (ezPanel hat Blizzards Fenster eben erst gerückt, die Lage soll stimmen) und nur,
-- wenn sich die Überdeckung geändert hat (die Nachricht kommt auch für Farbe, Schicht, Bearbeitungsmodus …)
local function TopSpaceNow()
    if not active then return end
    local p = Parts()
    if p and Compact.BarCover(p) ~= lastCover then ns.Try("MinimapCompact", Compact.Apply) end
end
local function OnTopSpace()
    if not active then return end
    if C_Timer and C_Timer.After then C_Timer.After(0, TopSpaceNow) else TopSpaceNow() end
end
Compact.OnTopSpace = OnTopSpace
Core.Listen("EZPANEL_TOPSPACE", OnTopSpace, "ezMap.MinimapCompact")

ns.AddStatusLine(function()
    local other = Compact.Elsewhere()
    if other and ns.Enabled("minimapCompact") then return L.STATUS_COMPACT_OTHER:format(other) end
    if Compact.HeaderBelow() and ns.Enabled("minimapCompact") then return L.STATUS_COMPACT_BELOW end
    if problem and ns.Enabled("minimapCompact") then return problem end
    if active and inPanel then return L.STATUS_COMPACT_PANEL end
    if active then return L.STATUS_COMPACT_ON end
    if ns.Enabled("minimapCompact") then return L.STATUS_COMPACT_WAITING end
    return nil
end)
