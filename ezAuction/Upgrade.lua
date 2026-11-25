local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Pfeil „besser“ an Blizzards Ergebniszeilen und Filter „Nur Verbesserungen“ (AUC-09, VP-35, GEAR-06 – W-27, Rest
    von V-125; ezMerchant als Vorbild). Bewertung und Pfeil kommen aus ezGear (ezCore.API("ezGear"): SetUpgradeIcon,
    IsUpgrade), hier wird nichts nachgebaut. Ohne ezGear gibt es weder Pfeil noch Filter.
    Der Pfeil sitzt auf ezAuctions eigener Auflage der Zeile (ns.RowOverlay).

    „Nur Verbesserungen“ blendet den Rest aus (Spieltest vom 24.11.2026, wörtlich: „sollte nur verbesserungen nicht den
    rest direkt ausblenden anstatt auszugrauen?“): Blizzards Ergebnisliste bekommt nach jedem Neuaufbau eine Auswahl der
    Zeilen (ScrollBox:SetDataProvider – die Einträge sind Blizzards Zeilennummern, Blizzards Daten und Zeilen bleiben
    unverändert). Das ist die Ausnahme (4) von Leitlinie 5 (CLAUDE.md; Nutzer am 24.11.2026: „Ja, Ausnahme“): nur für
    diesen Haken, nur außerhalb des Kampfes, und bis /reload aus, sobald Blizzard ezAuction blockiert (ns.T1Blocked → Upgrade.blocked). Ohne das Ausblenden (Kampf,
    Blockade) gilt der eigene Schleier über den übrigen Zeilen wie zuvor. Umfang der Ausnahme: SetDataProvider aus
    ezAuction baut die Zeilen unsicher auf (rowData der Zeilen; die Zellen teilen sich alle Listen des Auktionshauses) –
    das bleibt bis /reload, auch nach Restore und Block. Eingeschränkt sind laut Blizzards Beschreibung nur Bieten, Kaufen,
    Einstellen und Abbrechen (HasRestrictions, AuctionHouseDocumentation.lua); ob ein Tastendruck dafür genügt, sagt der
    Spieltest (docs/roadmap/ezAuction.md).
    Was ausgeblendet wird (Spieltest vom 24.11.2026, wörtlich: „bild 3: wieso wird ausrüstung bewertet, lol und wtf es reicht
    doch das ausblenden von items mit roten pfeilen“): nur Zeilen, deren Stand schon feststeht und keine Verbesserung ist –
    roter Pfeil oder graues Zeichen (Upgrade.Hides). Grüner und gelber Pfeil, Waren und alles, wozu noch keine Auskunft da
    ist, bleiben stehen; niemand wartet auf eine leere Liste. Der Pfeil ist dieselbe Bewertung: Für das Ausblenden muss ezGear
    auch die Zeilen unter der letzten sichtbaren ansehen, das läuft nebenher (Upgrade.EVAL je Durchgang). Solange eine
    Erfassung läuft (auch zwischen ihren Schritten), bleibt Blizzards Liste, wie sie ist – ohne Ausblenden und Schleier; ihre
    Zeilen gelten nur der Erfassung (Upgrade.Capturing).
    Blizzard lädt weitere Ergebnisse erst, wenn weniger als 30 Zeilen unter der letzten gezeigten stehen – mit
    ausgeblendeten Zeilen nie. Darum fordert der Filter sie an: von selbst höchstens Upgrade.PAGES je Suche, solange weniger
    als Upgrade.ENOUGH Zeilen dastehen (und nur, wenn überhaupt Ausrüstung dabei ist); danach am Ende der Liste,
    sobald der Spieler weiterblättert. Nie neben einem Auftrag in ezCores Warteschlange (Erfassung, Sammelabfrage).
    Gebaut vor dem Spieltest des Pfeils in ezMerchant (Grundsatz 5): Fehlt eine Auskunft, bleibt die Zeile wie bisher.

    Feste Spalte zwischen Preis und Name (Layout.GEAR), und jede Zeile mit Ausrüstung zeigt dort ihren Stand (Nutzer am
    24.11.2026: „im auktionshaus wird ezgear nur sporadisch angezeigt, ezgear pfeile position wie rechteck“): grüner,
    gelber oder roter Pfeil aus ezGear, sonst ein graues Zeichen – „=“ kaum ein Unterschied, „–“ kein Vergleich (nicht
    tragbar, ohne zählende Werte, Zweihänder angelegt, Hemd und Wappenrock), „<“ schlechter, solange ezGears roter Pfeil
    aus ist, „…“ die Daten laden noch. Warum Zeilen leer blieben: fehlende Stufe ohne Pfeil (ezGear), Werte aus halb
    geladenen Gegenständen gemerkt (ezGear), kein neues Zeichnen, wenn ezGear neu bewertet (hier), kein Nachfragen nach
    noch unbekannten Gegenständen (hier), Stände ohne Pfeil (hier).
]]

local Upgrade = {}
ns.Upgrade = Upgrade

local check, emptyText
Upgrade.EVAL = 60        -- so viele neue Bewertungen je Durchgang (der Rest folgt nach 0,3 s)
Upgrade.ENOUGH = 40      -- so viele Zeilen genügen (mehr, als hineinpassen): dann lädt nur noch das Blättern nach
Upgrade.PAGES = 5        -- so oft fordert der Filter je Suche von selbst weitere Ergebnisse an
Upgrade.ANSWER = 5       -- so viele Sekunden gilt eine Anforderung als unterwegs (bis die Antwort da ist)
Upgrade.blocked = false  -- nach einer Blockade durch Blizzard für die Sitzung aus (ns.T1Blocked)

-- ezGears Schnittstelle, wenn ezGear läuft und den Pfeil anbietet; sonst nil.
function Upgrade.Gear()
    local gear = Core.API("ezGear")
    if type(gear) == "table" and type(gear.SetUpgradeIcon) == "function" then return gear end
    return nil
end

-- Pfeil an (Schalter upgradeArrow) und ezGear da?
function Upgrade.Active()
    return ns.Enabled("upgradeArrow") and Upgrade.Gear() ~= nil
end

-- Filter „Nur Verbesserungen“ wirksam? Nur zusammen mit dem Pfeil.
function Upgrade.FilterOn()
    return ns.Enabled("upgradeOnly") and Upgrade.Active()
end

-- [itemID] = { tries, next }: nach seinen Daten ist gefragt, sie sind noch nicht da. Gefragt wird höchstens alle
-- ASK_WAIT Sekunden und ASK_MAX-mal je Sitzung: eine erfolglose Antwort darf nicht gleich wieder fragen (Review).
local ASK_WAIT, ASK_MAX = 10, 3
local waiting = {}
Upgrade.waiting = waiting

local function Ask(itemID)
    local entry, now = waiting[itemID] or { tries = 0, next = 0 }, GetTime()
    if entry.tries >= ASK_MAX or now < entry.next then return end
    entry.tries, entry.next = entry.tries + 1, now + ASK_WAIT
    waiting[itemID] = entry
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

local function PlainLink(link)
    if Core.IsSecret(link) or type(link) ~= "string" or not link:find("item:", 1, true) then return nil end
    return link
end

-- Link zu einer Ergebniszeile, nur für Ausrüstung → Link | nil, Ausrüstung?
-- Der Reihe nach: Blizzards Beispiel-Link aus den Auktionen dieses Schlüssels (GetItemKeySampleLink; gibt es erst, wenn
-- der Client sie kennt) und der Link des Zeilen-Tooltips (C_TooltipInfo.GetItemKey) – beide können die Abwandlung „des
-- Bären“ tragen –, sonst der Link der itemID. Kennt der Client den Gegenstand noch nicht, wird er angefordert.
-- Vorbehalt: Fasst Forever mehrere Abwandlungen unter einem Schlüssel zusammen (itemSuffix war bisher 0), steht der
-- Beispiel-Link für eine davon, nicht unbedingt für die billigste (Spielprüfpunkt 4, docs/roadmap/ezAuction.md).
function Upgrade.LinkOf(itemKey)
    local itemID = type(itemKey) == "table" and Core.Num(itemKey.itemID)
    if not itemID or not Core.IsEquipment(itemID) then return nil, false end
    local api = C_AuctionHouse
    local sample = api and PlainLink(Core.Call(api.GetItemKeySampleLink, itemKey))
    if sample then return sample, true end
    local suffix = Core.Num(itemKey.itemSuffix) or 0
    if suffix ~= 0 and C_TooltipInfo and type(C_TooltipInfo.GetItemKey) == "function" then
        local data = Core.Call(C_TooltipInfo.GetItemKey, itemID, Core.Num(itemKey.itemLevel) or 0, suffix,
            api and Core.Num(Core.Call(api.GetItemKeyRequiredLevel, itemKey)))
        local link = PlainLink(Core.Peek(data, "hyperlink"))
        local K = Core.Knowledge
        if link and K and type(K.VariantKey) == "function" and K.VariantKey(link) then return link, true end
    end
    local fn = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    local link = PlainLink(select(2, Core.Call(fn, itemID)))
    if link then waiting[itemID] = nil else Ask(itemID) end
    return link, true
end

-- Stand laut ezGear (gear.Status: "better", "learn", "level", "worse", "same", "nostats", "unusable", "equipped",
-- "pending") und der Text dazu; "noslot", wenn ezGear diesen Platz nicht bewertet (Hemd, Wappenrock); nil
-- ohne Auskunft.
function Upgrade.Status(link)
    if not Upgrade.Gear() then return nil end
    return Core.GearStatus(ns, link)
end

-- Graues Zeichen der Stände ohne Pfeil: ezGears Tabelle (eine für alle Listen; „<“ nur, solange sein roter Pfeil aus ist)
function Upgrade.SignOf(kind)
    local gear = kind ~= nil and Upgrade.Gear()
    if not (gear and type(gear.StatusSign) == "function") then return nil end
    return Core.Call(gear.StatusSign, kind)
end

-- Zeichen in der Spalte zeigen oder leeren (text nil)
function Upgrade.SetSign(overlay, text)
    if type(overlay) ~= "table" or not overlay.marks then return end
    local fs = overlay.gearSign
    if not fs then
        if not text then return end
        fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("CENTER", overlay.marks, "CENTER", 0, 0)
        overlay.gearSign = fs
    end
    fs:SetText(text or "")
    fs:SetShown(text ~= nil)
end

-- Läuft gerade eine Erfassung? (von ihrem ersten Schritt bis zur Rückkehr der Ansicht, auch zwischen zwei Schritten)
function Upgrade.Capturing()
    local capture = ns.Search and ns.Search.Capture
    if capture == nil then return false end
    return capture.active == true or capture.Owner() ~= nil
end

-- Bleibt dieser Stand unter „Nur Verbesserungen“ stehen (grüner und gelber Pfeil)? Die Regel gehört ezGear.
-- → true/false, nil = ezGear fehlt oder kennt die Regel noch nicht
local function Keeps(kind)
    local gear = Upgrade.Gear()
    if not (gear and type(gear.Keeps) == "function") then return nil end
    return gear.Keeps(kind) == true
end

-- Blendet „Nur Verbesserungen“ diesen Stand aus? true (roter Pfeil, graues Zeichen), false, nil = noch keine Auskunft
function Upgrade.Hides(kind, link)
    if kind == "pending" then return nil end
    if kind ~= nil then
        local keeps = Keeps(kind)
        if keeps ~= nil then return not keeps end
    end
    local up = link and Upgrade.IsUpgrade(link)          -- älteres ezGear ohne Status bzw. ohne Keeps: nur der grüne Pfeil
    if up == nil or not link then return nil end
    return not up
end

-- Laut ezGear besser als das Angelegte? true/false; nil = ezGear fehlt oder die Daten laden noch.
function Upgrade.IsUpgrade(link)
    if not (Upgrade.Gear() and link) then return nil end
    return (Core.AskModule(ns, "ezGear", "IsUpgrade", link))
end

-- Eine Ergebniszeile: Pfeil bzw. Zeichen setzen oder leeren, unter dem Filter abblenden. Rückgabe: Erklärzeile für den
-- Tooltip der Zeile (nil, wenn nichts zu sagen ist).
function Upgrade.Mark(overlay, data)
    local gear = Upgrade.Gear()
    local dim = type(overlay) == "table" and overlay.SetDim
    if not gear then
        if dim then overlay:SetDim(false) end
        Upgrade.SetSign(overlay, nil)
        return nil
    end
    local link, equipment
    if Upgrade.Active() and type(data) == "table" then link, equipment = Upgrade.LinkOf(data.itemKey) end
    -- Der Pfeil liegt auf dem Halter der Auflage (feste Spalte zwischen Preis und Name, ns.RowOverlay)
    if type(overlay) == "table" and overlay.PlaceMarks then overlay:PlaceMarks() end
    local holder = type(overlay) == "table" and overlay.marks or overlay
    local ok, result = pcall(gear.SetUpgradeIcon, holder, link)
    if not ok then ns.Error(result, "SetUpgradeIcon (ezGear)") end
    local kind, text = Upgrade.Status(link)
    if equipment and not link then kind = "pending" end
    -- „besser“ sagt schon der Stand; ein älteres ezGear ohne Status fragt IsUpgrade
    local up
    if kind == nil then up = link and Upgrade.IsUpgrade(link) else up = kind == "better" end
    local hide
    if equipment then hide = Upgrade.Hides(kind, link) end
    if dim then overlay:SetDim(Upgrade.FilterOn() and hide == true and not Upgrade.Hiding() and not Upgrade.Capturing()) end
    if hide ~= nil then Upgrade.Note(data, hide) end
    local sign = Upgrade.SignOf(kind)
    Upgrade.SetSign(overlay, sign)
    if up == true then return L.UPGRADE_ROW_TIP end
    if kind == "learn" or kind == "level" then return L.UPGRADE_ROW_TIP_LATER end
    if kind == "pending" then return L.UPGRADE_ROW_TIP_PENDING:format(sign) end
    if kind == "equipped" then return L.UPGRADE_ROW_TIP_EQUIPPED:format(sign) end
    if kind == "noslot" then return L.UPGRADE_ROW_TIP_NOSLOT:format(sign) end
    if type(text) ~= "string" then return nil end
    if sign then return L.UPGRADE_ROW_TIP_SIGN:format(sign, text) end
    if kind == "worse" then return L.UPGRADE_ROW_TIP_WORSE:format(text) end
    return nil
end

---------------------------------------------------------------------------
-- Ausblenden: Auswahl der Zeilen in Blizzards Ergebnisliste
---------------------------------------------------------------------------

-- [Schlüssel des Gegenstands] = { hide = true/false/nil (noch nie eine Auskunft), open = zuletzt ohne Auskunft, gen =
-- Durchgang der Bewertung, gear = Ausrüstung? }. Ein älterer Stand gilt weiter, bis ein neuer da ist – auch wenn ezGear
-- zwischendurch „lädt noch“ sagt: sonst sprängen die Zeilen unter der Maus.
local verdicts, generation = {}, 1
-- shown, total, provider: was gerade in Blizzards Liste steht (provider nil = Blizzards eigene); pages: von selbst
-- angefordert; asked: eine Anforderung wartet; sent: unterwegs seit; search: Zähler der Suchen; cursor: hier geht es mit offenen Zeilen weiter
local state = { pages = 0, search = 0, cursor = 0 }

local function ItemList()
    local results = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
    return results and results.ItemList, results
end

-- Blizzards Ergebnisse (nur gelesen)
local function Entries()
    local _, results = ItemList()
    local list = results and results.browseResults
    return type(list) == "table" and list or {}
end

-- Darf der Filter jetzt ausblenden? (sonst Schleier; während einer Erfassung keines von beiden)
function Upgrade.CanHide()
    return Upgrade.FilterOn() and not Upgrade.blocked and not ns.InCombat() and not Upgrade.Capturing()
        and type(rawget(_G, "CreateDataProvider")) == "function"
end

-- Blendet der Filter gerade aus?
function Upgrade.Hiding() return state.provider ~= nil end

local function KeyOf(data) return ns.KeyString(type(data) == "table" and data.itemKey or nil) end

-- Eine Zeile ansehen und merken. → der Eintrag in verdicts (hide nil: ezGear hatte noch nie eine Auskunft; Waren: false)
function Upgrade.Judge(data)
    local key = KeyOf(data)
    local e = verdicts[key] or {}
    verdicts[key] = e
    local link, equipment = Upgrade.LinkOf(type(data) == "table" and data.itemKey or nil)
    local hide
    if not equipment then
        hide = false
    elseif link then
        hide = Upgrade.Hides(Upgrade.Status(link), link)
    end
    e.gen, e.gear, e.open = generation, equipment or nil, hide == nil or nil
    if hide ~= nil then e.hide = hide end
    return e
end

-- Die sichtbare Zeile zeigt gerade etwas anderes als gemerkt (Blizzard kennt jetzt den Link mit der Abwandlung): merken
function Upgrade.Note(data, hide)
    local e = verdicts[KeyOf(data)]
    if not e or e.gen ~= generation or (e.hide == hide and not e.open) then return end
    local changed = e.hide ~= hide
    e.hide, e.open = hide, nil
    if not changed then return end
    if state.provider then Upgrade.RedecorateSoon() end
end

-- Nummern der Zeilen, die stehen bleiben → Liste, warten noch nie angesehene?, ist Ausrüstung dabei?, warten noch welche
-- mit veralteter Bewertung? Je Durchgang höchstens Upgrade.EVAL, von oben: zuerst die noch nie angesehenen; dann die ohne
-- Auskunft (höchstens die Hälfte des Rests, solange veraltete warten; der Reihe nach weiter, damit dauerhaft offene die
-- übrigen nicht aufhalten); dann die seit der letzten neuen Bewertung nicht angesehenen – ihr alter Stand gilt so lange.
-- In dieser Reihenfolge, weil ezGear bei jeder nachgeladenen Gegenstandsinfo neu bewertet (Review): sonst fingen die
-- obersten 60 immer wieder von vorn an.
function Upgrade.Indices(entries)
    local budget, unseen = Upgrade.EVAL, false
    local opened, stale = {}, {}
    for index, data in ipairs(entries) do
        local e = verdicts[KeyOf(data)]
        if not e then
            if budget > 0 then
                budget = budget - 1
                e = Upgrade.Judge(data)
                if not e.gear then budget = budget + 1 end      -- keine Ausrüstung: kostet nichts
            else
                unseen = true
            end
        elseif e.gen ~= generation then
            if e.gear then stale[#stale + 1] = index else e.gen = generation end      -- Waren bleiben Waren
        elseif e.open then
            opened[#opened + 1] = index
        end
    end
    if #opened > 0 and budget > 0 then
        local share = math.min(#opened, #stale > 0 and math.ceil(budget / 2) or budget)
        local first = 1
        for at, index in ipairs(opened) do if index > state.cursor then first = at break end end
        for step = 0, share - 1 do
            local index = opened[(first - 1 + step) % #opened + 1]
            Upgrade.Judge(entries[index])
            state.cursor = index
        end
        budget = budget - share
    end
    for at = 1, math.min(budget, #stale) do Upgrade.Judge(entries[stale[at]]) end
    local outdated = #stale > budget
    local out, gear = {}, false
    for index, data in ipairs(entries) do
        local e = verdicts[KeyOf(data)]
        if e and e.gear then gear = true end
        if not (e and e.hide == true) then out[#out + 1] = index end
    end
    return out, unseen, gear, outdated
end

local function Same(a, b)
    if not a or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Text an der Stelle der Liste, wenn keine Zeile übrig bleibt
local function ShowEmpty(list, text)
    if not emptyText then
        if not text then return end
        local holder = CreateFrame("Frame", nil, list)
        holder:SetAllPoints(list.ScrollBox)
        emptyText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER")
        emptyText:SetWidth(360)
    end
    emptyText:SetText(text or "")
    emptyText:SetShown(text ~= nil)
end
function Upgrade.EmptyText() return emptyText and emptyText:IsShown() and emptyText:GetText() or nil end

local function AllLoaded()
    local api = C_AuctionHouse
    return not (api and api.HasFullBrowseResults) or Core.Call(api.HasFullBrowseResults) ~= false
end

-- Hält gerade ein Auftrag Blizzards Ergebnisliste (Erfassung, Sammelabfrage, eigene Suche eines Moduls)?
local function Busy()
    if (ns.Search and ns.Search.running) or Upgrade.Capturing() then return true end
    local queue = ns.Queue()
    local owner = queue and type(queue.Owner) == "function" and Core.Call(queue.Owner)
    return type(owner) == "table" and owner.rank ~= "user"
end

-- Weitere Ergebnisse anfordern (Blizzard täte es erst am Ende der vollen Liste). byPlayer: der Spieler blättert am Ende
-- weiter – dann gilt die Grenze Upgrade.PAGES nicht.
local function More(byPlayer)
    local api = C_AuctionHouse
    if AllLoaded() or state.asked or (state.sent and GetTime() - state.sent < Upgrade.ANSWER)
        or not (api and api.RequestMoreBrowseResults) or Busy() or (not byPlayer and state.pages >= Upgrade.PAGES) then return end
    local search = state.search
    state.asked = true
    ns.WhenThrottleReady(function()
        local mode, browsing = ns.ModeName()
        state.asked = nil
        -- inzwischen eine andere Suche (oder sie läuft noch), ein Auftrag, Kampf, andere Ansicht: nichts mehr zu laden
        if search ~= state.search or #Entries() == 0 or not Upgrade.CanHide() or mode ~= "buy" or browsing ~= true or Busy()
            or AllLoaded() then return end
        if not byPlayer then state.pages = state.pages + 1 end
        state.sent = GetTime()
        Core.Call(api.RequestMoreBrowseResults)
    end)
end

-- Steht unsere Auswahl in Blizzards Liste (Ours), und ist ihre letzte Zeile zu sehen (AtEnd)?
local function Ours(box)
    return state.provider ~= nil and Core.Call(box.GetDataProvider, box) == state.provider
end

local function AtEnd(box)
    if not Ours(box) then return false end
    local last = Core.Num(Core.Call(box.GetDataIndexEnd, box))
    return last ~= nil and last >= #state.shown
end

-- Blizzards Liste wurde geblättert oder neu aufgebaut (CallRefreshCallback): nur echtes Blättern bis ans Ende lädt nach
local function Scrolled(list)
    local box = list.ScrollBox
    if not AtEnd(box) then
        if Ours(box) then state.at = nil end
        return
    end
    local at = Core.Num(Core.Call(box.GetScrollPercentage, box)) or 0
    local moved = at > 0 and at ~= state.at
    state.at = at
    if moved then More(true) end
end

-- Haken-Text: „Nur Verbesserungen (3 von 57)“, solange ausgeblendet wird
local function Caption()
    if not (check and check.label) then return end
    local text = L.OPT_upgradeOnly
    if state.provider then
        text = L.UPGRADE_ONLY_COUNT:format(#state.shown, AllLoaded() and tostring(state.total) or (state.total .. "+"))
    end
    check.label:SetText(text)
end

-- Blizzards vollständige Liste wieder zeigen. → true, wenn der Filter vorher ausblendete
function Upgrade.Restore()
    local provider = state.provider
    state.provider, state.shown = nil, nil
    local list = ItemList()
    if list then ShowEmpty(list, nil) end
    Caption()
    if not provider then return false end
    local box, total = list and list.ScrollBox, #Entries()
    local make = rawget(_G, "CreateIndexRangeDataProvider")
    -- nur, solange noch unsere Auswahl darin steht (Blizzards Neuaufbau hat sie sonst schon ersetzt)
    if box and total > 0 and type(make) == "function" and Core.Call(box.GetDataProvider, box) == provider then
        box:SetDataProvider(make(total), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    end
    return true
end

-- Blizzard hat ezAuction blockiert (ns.T1Blocked): bis /reload nur noch abblenden. Wer den Filter benutzt hat, erfährt es
-- im Chat – ganz sauber sind Blizzards Listen erst nach /reload.
function Upgrade.Block()
    if Upgrade.blocked then return end
    Upgrade.blocked = true
    if state.provider then ns.Try("Upgrade.Restore", Upgrade.Restore) end
    if state.used then ns.Print(L.UPGRADE_ONLY_BLOCKED) end
end

-- Auswahl setzen bzw. auffrischen (nach Blizzards Neuaufbau, neuer Bewertung, Haken). → Zahl der Zeilen oder nil
function Upgrade.Apply()
    local list = ItemList()
    local box = list and list.ScrollBox
    if not box or type(box.SetDataProvider) ~= "function" then return nil end
    local mode, browsing = ns.ModeName()
    if not Upgrade.CanHide() or mode ~= "buy" or browsing ~= true then
        Upgrade.Restore()
        return nil
    end
    local entries = Entries()
    local current = Core.Call(box.GetDataProvider, box)
    -- ohne Ergebnisse, nicht zu sehen oder Blizzard zeigt gerade keine Liste (Fehlertext, Suche läuft): nichts zu filtern
    if #entries == 0 or not list:IsVisible() or current == nil then
        state.provider, state.shown = nil, nil
        ShowEmpty(list, nil)
        Caption()
        return nil
    end
    local indices, unseen, gear, outdated = Upgrade.Indices(entries)
    local ours = state.provider ~= nil and current == state.provider
    if not (ours and Same(state.shown, indices)) then
        local provider = CreateDataProvider(indices)
        state.provider, state.shown, state.used = provider, indices, true
        local ok, err = pcall(box.SetDataProvider, box, provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
        if not ok then
            Upgrade.blocked = true      -- Blizzards Liste nimmt die Auswahl nicht: wie zuvor abblenden
            state.provider, state.shown = nil, nil
            ShowEmpty(list, nil)
            Caption()
            local make = rawget(_G, "CreateIndexRangeDataProvider")
            if type(make) == "function" then Core.Call(box.SetDataProvider, box, make(#entries)) end
            ns.Error(err, "Nur Verbesserungen")
            return nil
        end
    end
    state.total = #entries
    ShowEmpty(list, #indices == 0 and L.UPGRADE_ONLY_NONE:format(#entries) or nil)
    Caption()
    if unseen or outdated then Upgrade.RedecorateSoon() end
    if gear and #indices < Upgrade.ENOUGH and not unseen then More() end
    return #indices
end

---------------------------------------------------------------------------
-- Sichtbarer Schalter „Nur Verbesserungen“ unten neben Blizzards Goldanzeige (nur in der Ergebnisliste)
---------------------------------------------------------------------------

function Upgrade.Update()
    if not check then return end
    local mode, browsing = ns.ModeName()
    local show = ns.AuctionHouseShown() and mode == "buy" and browsing == true and Upgrade.Active()
    check:SetShown(show == true)
    if check.SetChecked then check:SetChecked(ns.Enabled("upgradeOnly")) end
end

-- Knopf, solange zu sehen (für Prüfungen).
function Upgrade.Button()
    return check ~= nil and check:IsVisible() and check or nil
end

local function Build()
    local ok, box = pcall(CreateFrame, "CheckButton", "ezAuctionUpgradeOnly", AuctionHouseFrame, "UICheckButtonTemplate")
    if not ok or not box then box = CreateFrame("CheckButton", "ezAuctionUpgradeOnly", AuctionHouseFrame) end
    check = box
    box:SetSize(Core.Style.BUTTON.check, Core.Style.BUTTON.check)   -- Haken (Design-System 2.3; bis Welle 22 22)
    local money = AuctionHouseFrame.MoneyFrameBorder
    if money then
        -- hinter der Zeile „Preise erfassen“ (Knopf, Pfeil, Zahnrad, „Heute: …“; seit dem 21.11.2026 unten)
        box:SetPoint("LEFT", money, "RIGHT", ns.Layout.UpgradeOffset(), 0)
    else
        local M = ns.Layout.BLIZZARD.money
        box:SetPoint("LEFT", AuctionHouseFrame, "BOTTOMLEFT", M.x + M.w + ns.Layout.UpgradeOffset(), M.y + M.h / 2)
    end
    local label = Core.Peek(box, "Text")
    if type(label) ~= "table" or not label.SetText then
        label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    end
    label:SetText(L.OPT_upgradeOnly)
    box.label = label
    box:SetScript("OnClick", function() ns.SetSetting("upgradeOnly", not ns.Enabled("upgradeOnly")) end)
    box:SetScript("OnEnter", function(self) Core.ShowTip(self, L.OPT_upgradeOnly, L.OPT_upgradeOnly_TIP) end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    box:Hide()
end

local function Redecorate()
    ns.Try("Upgrade.Apply", Upgrade.Apply)
    if ns.Buy and ns.Buy.redecorate then ns.Buy.redecorate() end
end

ns.OnAuctionHouse(function()
    Build()
    Upgrade.Update()
    local list = ItemList()
    -- nach jedem Neuaufbau von Blizzards Liste (die dann wieder alle Zeilen hat)
    if list and list.RefreshScrollFrame then
        hooksecurefunc(list, "RefreshScrollFrame", function() ns.Try("Upgrade.Apply", Upgrade.Apply) end)
    end
    -- am Ende der Auswahl weitergeblättert: weitere Ergebnisse (Blizzards Schwelle zählt die ausgeblendeten mit). Das
    -- Mausrad zählt auch, wenn alle Zeilen hineinpassen.
    if list and list.CallRefreshCallback then
        hooksecurefunc(list, "CallRefreshCallback", function(self) ns.Try("Upgrade.Scrolled", Scrolled, self) end)
    end
    local box = list and list.ScrollBox
    if box and box.HookScript then
        box:HookScript("OnMouseWheel", function(self, delta)
            if (Core.Num(delta) or 0) < 0 and state.provider and AtEnd(self) then ns.Try("Upgrade.More", More, true) end
        end)
    end
end)
-- neue Suche: bis zu Upgrade.PAGES Mal nachladen (weitere Seiten zählen nicht neu)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    state.pages, state.at, state.cursor, state.search, state.sent = 0, nil, 0, state.search + 1, nil
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() state.sent = nil end)
-- Haus zu: ezAuctions Takt verwirft wartende Abfragen, auch unsere
ns.Listen("AH_CLOSED", function() state.asked, state.sent, state.pages, state.at = nil, nil, 0, nil end)
-- im Kampf wird nicht ausgeblendet
ns.On("PLAYER_REGEN_DISABLED", function() if state.provider then ns.Try("Upgrade.Restore", Upgrade.Restore) end end)
ns.On("PLAYER_REGEN_ENABLED", function() if Upgrade.FilterOn() and ns.AuctionHouseShown() then Redecorate() end end)
ns.Listen("AH_SHOW", Upgrade.Update)
-- Nachgeladene Gegenstandsdaten oder eine neue Bewertung von ezGear (Gewichtung, Ausrüstung, Stufe, nachgeladene Werte):
-- Pfeile, Zeichen, Auswahl und Schleier der Zeilen neu (gesammelt; DecorateNow braucht die gezeigte Liste)
local redecorateSoon = ns.Throttle(function()
    if Upgrade.Active() and ns.AuctionHouseShown() then Redecorate() end
end, 0.3)
Upgrade.RedecorateSoon = redecorateSoon
-- Ansicht gewechselt: zurück aus einem fremden Reiter baut Blizzard die Liste auf, bevor der Reiter gewählt ist
ns.Listen("AH_MODE", function()
    Upgrade.Update()
    if Upgrade.FilterOn() then redecorateSoon() end
end)
-- die Warteschlange ist wieder frei: erst jetzt darf der Filter weitere Ergebnisse anfordern; eine Erfassung beginnt bzw.
-- endet: ihre Liste bleibt ungefiltert
Core.Listen("PRICES_QUEUE_CHANGED", function()
    if not Upgrade.FilterOn() then return end
    if state.provider == nil or not Busy() or Upgrade.Capturing() then redecorateSoon() end
end, "ezAuction")
ns.On("GET_ITEM_INFO_RECEIVED", redecorateSoon)
-- Eine erfolglose Antwort zeichnet nicht neu und behält die Sperrfrist (sonst fragte das Zeichnen gleich wieder)
ns.On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
    if Core.IsSecret(itemID) or not waiting[itemID or 0] then return end
    if Core.Plain(success) == false then return end
    waiting[itemID] = nil
    redecorateSoon()
end)
Core.Listen("GEAR_SCORES_CHANGED", function()
    generation = generation + 1     -- alte Bewertungen gelten, bis die neue da ist
    redecorateSoon()
end, "ezAuction")
ns.OnSettingChanged(function(key)
    if key == "upgradeArrow" or key == "upgradeOnly" then
        verdicts = {}
        state.pages = 0
        Upgrade.Update()
        Redecorate()
    end
end)
