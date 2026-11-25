local _, ns = ...
local L = ns.L

--[[
    Reagenzientasche als Abschnitt unten in der Tasche (Auftrag des Nutzers vom 23.11.2026: „ressourcentasche sinnvoll
    aber abgegrenzt integrieren in einer anzeige? aka eine tasche“; Entscheidung „Abschnitt unten (Empfohlen)“,
    Schalter ab Werk an).

    Blizzards kombinierte Tasche zeigt nur Rucksack und Taschen 0–4; die Reagenzientasche hat immer ein eigenes Fenster
    daneben (Forever-Quelle, Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua: ENDING_BAG_INDEX = NUM_BAG_FRAMES,
    ContainerFrame_IsGenericHeldBag „excludes the reagent bag except when using gamepad UI“, UpdateContainerFrameAnchors
    beginnt nach der kombinierten Tasche eine neue Spalte). Nichts wird ersetzt:
      - Die Plätze bleiben Blizzards Knöpfe in Blizzards Reagenzien-Fenster. ezBag legt dieses Fenster genau über den
        Abschnitt unten in der kombinierten Tasche (Layout.lua ordnet die Plätze dort in eigenen Gruppen an) und blendet
        nur in der Darstellung Rahmen, Porträt, Titel und Knöpfe des Fensters aus (Alpha 0, nicht anklickbar) – wie die
        Plätze selbst, die ezBag versteckt (ns.ConcealButton). Blizzards Tabellen bleiben unberührt (Leitlinie 5).
      - Das Fenster bleibt in derselben Schicht wie die Tasche und wird nach jedem Klick in die Tasche wieder über sie
        gehoben (Raise; Container-Fenster sind „toplevel“, ein Klick hebt die Tasche über das Fenster). So verdeckt ein
        anderes Fenster, das man über die Tasche zieht, auch den Abschnitt.
      - Geht die Tasche auf, öffnet ezBag die Reagenzientasche mit (Blizzards Rucksack-Klick öffnet nur die kombinierte
        Tasche, B öffnet beide); geht sie zu, schließt ezBag sie mit – beides über ezCore.OpenPanel, nie im Kampf aus
        Addon-Code. Im Kampf bleibt Blizzards Verhalten; nach dem Kampf holt ezBag das Schließen nach.
    Schalter „Reagenzientasche in der Tasche“ (reagentSection), aus = Blizzards Fenster wie vorher.
]]

local Reagent = {}
ns.Reagent = Reagent

Reagent.SECTION_H = 22     -- Trennlinie und Überschrift über dem Abschnitt
Reagent.AFTER_COMBAT_KEY = "ezBag.reagentClose"

local current          -- Blizzards Reagenzien-Fenster, solange es als Abschnitt liegt
local faded = {}       -- Region oder Rahmen → { alpha, mouse } (zum Zurückgeben)
local attachedTo       -- die kombinierte Tasche, über der das Fenster liegt
local watch            -- hebt das Fenster wieder über die Tasche (OnUpdate, nur solange ein Abschnitt liegt)
local header           -- Trennlinie und Überschrift (an der Tasche)
local hooked = setmetatable({}, { __mode = "k" })
local combatHidden       -- { frame, alpha, mouse = { [Knopf] = an? } } solange das Fenster im Kampf unsichtbar ist

function Reagent.BagID()
    return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or nil
end

-- Mit Gamepad-Oberfläche zeigt Blizzards kombinierte Tasche die Reagenzientasche selbst (ENDING_BAG_INDEX =
-- NUM_TOTAL_BAG_FRAMES) – dann braucht es keinen Abschnitt.
local function GamepadUI()
    local util = rawget(_G, "InputUtil")
    if type(util) ~= "table" or type(util.IsGamepadUIEnabled) ~= "function" then return false end
    local ok, on = pcall(util.IsGamepadUIEnabled)
    return ok and on == true
end

-- Ist der Abschnitt gewünscht? (Schalter an, Tasche gruppiert, keine Gamepad-Oberfläche)
function Reagent.Wanted()
    return ns.S ~= nil and ns.S.reagentSection == true and not (ns.Layout and ns.Layout.Blocked()) and not GamepadUI()
end

-- Hat der Charakter eine Reagenzientasche angelegt?
function Reagent.HasBag()
    local id = Reagent.BagID()
    return id ~= nil and (ezCore.Num(C_Container.GetContainerNumSlots(id)) or 0) > 0
end

local function IsReagentFrame(frame)
    local id = Reagent.BagID()
    if not id or type(frame) ~= "table" or type(frame.GetBagID) ~= "function" then return false end
    local ok, bag = pcall(frame.GetBagID, frame)
    return ok and bag == id
end
Reagent.IsReagentFrame = IsReagentFrame

-- Blizzards gezeigtes Reagenzien-Fenster (ein freies ContainerFrameN, kein fester Name) oder nil.
function Reagent.Frame()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() and IsReagentFrame(frame) then return frame end
    end
    return nil
end

-- Freie Plätze der Reagenzientasche (eigene Zahl, die Rucksack-Zahl zählt nur die normalen Taschen).
function Reagent.FreeSlots()
    local id = Reagent.BagID()
    if not id then return 0 end
    return ezCore.Num((C_Container.GetContainerNumFreeSlots(id))) or 0
end

-- Name des Abschnitts: was im Reagenzien-Platz wirklich steckt (Nutzer am 23.11.2026: „ich habe eine bergbautasche im
-- reagienzentaschenslot“) – eine echte Reagenzientasche heißt „Reagenzientasche“, sonst Blizzards Name der Tasche.
function Reagent.SectionName()
    local id = Reagent.BagID()
    local kind = id and ns.Transfer and ns.Transfer.BagKind and ns.Transfer.BagKind(id)
    if kind and kind ~= "reagent" and C_Container.GetBagName then
        local ok, name = pcall(C_Container.GetBagName, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return L.REAGENT_SECTION
end

function Reagent.HeaderText()
    return Reagent.SectionName() .. " · " .. ezCore.FreeSpaceText(Reagent.FreeSlots())
end

-- Darf der Gegenstand in die Reagenzientasche? Sie nimmt nur Handwerksmaterial (Tooltip „Handwerksmaterial“; Wert 17
-- von GetItemInfo, isCraftingReagent). Noch nicht geladene Gegenstände gelten als „nein“ – dann plant ezBag sie nicht
-- dorthin, statt dass der Server den Schritt ablehnt.
-- Rückfall nur, solange GetItemInfo nichts liefert (Gegenstand noch nicht geladen): Handwerkswaren (Gegenstandsklasse 7 –
-- Stoff, Erz, Kräuter, Leder …) über ezCore.ItemClass (GetItemInfoInstant, auch ungeladen bekannt; Spieltest vom 23.11.2026:
-- „klick ich aif erz in der tasche wird die reagenzientasche grau“).
function Reagent.IsReagentItem(itemID)
    if type(itemID) ~= "number" or not C_Item then return false end
    if C_Item.GetItemInfo then
        local ok, isReagent = pcall(function() return select(17, C_Item.GetItemInfo(itemID)) end)
        if ok and isReagent ~= nil then return isReagent == true end   -- der Client sagt es: gilt
    end
    local tradegoods = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
    if ezCore.ItemClass(itemID) == tradegoods then return true end
    return false
end

-- Trägt der Mauszeiger etwas, das nicht in die Reagenzientasche passt? Dann sind ihre Plätze dunkel (Spieltest vom
-- 23.11.2026, Bild 3: „wieso ausgegraut?“) – die Überschrift sagt dann, warum.
function Reagent.CursorBlocked()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or type(itemID) ~= "number" then return false end
    local id = Reagent.BagID()
    if id and ns.Transfer and ns.Transfer.BagAccepts then
        local fits = ns.Transfer.BagAccepts(id, itemID)
        return not fits
    end
    return not Reagent.IsReagentItem(itemID)
end

-- Überschrift samt Hinweis „nur Handwerksmaterial“, solange der Mauszeiger etwas anderes trägt (HeaderText bleibt die
-- Zahl allein: sie gehört zur Signatur der Anordnung, der Hinweis soll nicht neu anordnen).
function Reagent.HeaderLabel()
    local text = Reagent.HeaderText()
    if Reagent.CursorBlocked() then
        local id = Reagent.BagID()
        local kind = id and ns.Transfer and ns.Transfer.BagKind and ns.Transfer.BagKind(id)
        text = text .. " · " .. ezCore.Style.ColorText("bad", (kind == nil or kind == "reagent") and L.REAGENT_ONLY or L.SECTION_NOFIT)
    end
    return text
end

-- Die Plätze des Fensters (Blizzards Knöpfe) → Liste
function Reagent.Buttons(frame)
    local list = {}
    if not (frame and frame.Items and frame.EnumerateValidItems) then return list end
    for _, button in frame:EnumerateValidItems() do
        if button then list[#list + 1] = button end
    end
    return list
end

local function Fade(object, mouse)
    if faded[object] then
        if mouse and object.EnableMouse then object:EnableMouse(false) end
        return
    end
    faded[object] = { alpha = object:GetAlpha(), mouse = mouse and object.IsMouseEnabled and object:IsMouseEnabled() or nil }
    object:SetAlpha(0)
    if mouse and object.EnableMouse then object:EnableMouse(false) end
end

local function Unfade(object)
    local was = faded[object]
    if not was then return end
    object:SetAlpha(was.alpha or 1)
    if was.mouse ~= nil and object.EnableMouse then object:EnableMouse(was.mouse) end
    faded[object] = nil
end

local function IsItemButton(child)
    return type(child.GetObjectType) == "function" and child:GetObjectType() == "ItemButton"
end

-- Rahmen, Porträt, Titel und Knöpfe des Fensters nur in der Darstellung ausblenden. Plätze (die gezeigten Knöpfe und
-- jeder Gegenstands-Knopf aus Blizzards Vorrat) und ezBags eigene Teile (keep) bleiben; ein Platz, der seit dem letzten
-- Mal dazugekommen ist (größere Reagenzientasche), wird wieder sichtbar.
local function FadeChrome(frame, keep)
    local active = {}
    for _, button in ipairs(Reagent.Buttons(frame)) do
        active[button] = true
        Unfade(button)
    end
    for _, region in ipairs({ frame:GetRegions() }) do Fade(region, false) end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not keep[child] and not active[child] and not IsItemButton(child) then Fade(child, true) end
    end
end

local function RestoreChrome()
    for object in pairs(faded) do Unfade(object) end
end

-- Liegt das Fenster nicht mehr über der Tasche (ein Klick hat die Tasche gehoben), wieder darüber. → true, wenn gehoben
function Reagent.KeepOnTop()
    if not (current and attachedTo) or combatHidden then return false end
    if ns.InCombat() and current:IsProtected() then return false end
    if current:GetFrameLevel() > attachedTo:GetFrameLevel() then return false end
    current:Raise()
    return true
end

local function Header(parent)
    if header then return header end
    header = CreateFrame("Frame", nil, parent)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetColorTexture(0.55, 0.46, 0.30, 0.95)   -- Bronze wie die Rahmen der Gruppen (Render.lua, BORDER)
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 3)
    header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 3)
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.text:SetPoint("BOTTOMLEFT", header.line, "TOPLEFT", 2, 3)
    header.text:SetJustifyH("LEFT")
    header:EnableMouse(true)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.REAGENT_SECTION, ns.TipRGB("normal"))
        ns.AddTipLine(L.REAGENT_SECTION_TIP, "highlight", true)
        ns.AddTipLine(L.REAGENT_ONLY_TIP, "normal", true)
        -- Weg zum Schalter in ezCores einer Form (T18-18)
        ns.AddTipLine(ezCore.SettingsPathText("ezBag", "OPT_SECTION_groups", "OPT_reagentSection", L), "hint", true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return header
end

--[[
    Abschnitt setzen (aus Layout.lua, nach dem Anordnen):
      frame       Blizzards Reagenzien-Fenster
      bagFrame    die kombinierte Tasche
      opts.PlaceRect(frame)     Fenster mit zwei Ankern genau über die Gruppen des Abschnitts (Blizzards SetSize
                                ändert daran nichts)
      opts.PlaceHeader(header)  Trennlinie und Überschrift über den Gruppen
      opts.holder               ezBags Fläche auf der Tasche (Eltern der Überschrift)
      opts.keep                 ezBags eigene Teile im Fenster (bleiben sichtbar)
]]
function Reagent.Attach(frame, bagFrame, opts)
    if ns.InCombat() and frame:IsProtected() then return false end
    if current and current ~= frame then Reagent.Release() end
    current, attachedTo = frame, bagFrame
    if frame:GetFrameLevel() <= bagFrame:GetFrameLevel() then frame:Raise() end
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnUpdate", Reagent.KeepOnTop)
    end
    watch:Show()
    FadeChrome(frame, opts.keep or {})
    -- Klicks in Lücken des Abschnitts gehen nicht ans (unsichtbare) Fenster
    Fade(frame, true)
    frame:SetAlpha(1)   -- nur die Maus: das Fenster selbst bleibt sichtbar, sonst wären seine Plätze unsichtbar
    frame:ClearAllPoints()
    opts.PlaceRect(frame)
    local h = Header(opts.holder)
    h:SetFrameLevel(opts.holder:GetFrameLevel() + 2)
    opts.PlaceHeader(h)
    h.text:SetText(Reagent.HeaderLabel())
    h:Show()
end

-- Grau auf den Plätzen des Abschnitts nur mit Grund (Spieltest vom 23.11.2026: „drücke ich "tasche aufräumen" oder
-- ein stack in tasche verschieben --> slots reagenzientasche grau, neu öffnen wieder ok --- ich nehme anderes item aus
-- der tasche in die hand, leg es wieder ab, reagienzentasche bleibt grau“). Gründe für Blizzards Grauschicht: Text im
-- Suchfeld, ein Fenster mit Gegenstands-Kontext (Bank, Aufwerten, Verzaubern …, ItemButtonUtil.GetItemContext) oder ein
-- unpassender Gegenstand am Mauszeiger; für die Entsättigung ein gesperrter Platz. Eine Näherung: ezBag liest Blizzards
-- Gründe nicht je Platz, sondern prüft die Lage im Ganzen. → Grund oder nil
function Reagent.GreyReason()
    for _, name in ipairs({ "BagItemSearchBox", "BankItemSearchBox" }) do   -- Blizzards Suche gilt für alle Fenster
        local box = rawget(_G, name)
        local text = box and box.GetText and box:GetText()
        if type(text) == "string" and text ~= "" then return "search" end
    end
    local util = rawget(_G, "ItemButtonUtil")
    if type(util) == "table" and type(util.GetItemContext) == "function" then
        local ok, context = pcall(util.GetItemContext)
        if ok and context ~= nil then return "context" end
    end
    if Reagent.CursorBlocked() then return "cursor" end
    return nil
end

local GREY_LAYERS = { "ItemContextOverlay", "searchOverlay" }   -- Retail-Vorlage bzw. ältere Vorlage

-- Grau ohne Grund von den Plätzen des Abschnitts nehmen: Blizzards Grauschicht nur ausblenden (Region:Hide – Blizzard
-- setzt sie bei jedem Neubefüllen selbst wieder per SetShown), die Entsättigung über Blizzards eigene Funktion zurück
-- (SetItemButtonDesaturated setzt nur das Symbol). Blizzards Tabellen bleiben unberührt. Dazu der Ebenen-Schutz
-- (KeepAboveBag). → Zahl der zurückgenommenen Stellen
function Reagent.SyncGrey()
    if not current or combatHidden then return 0 end
    local layers, desat = 0, 0
    local reason = Reagent.GreyReason()
    for _, button in ipairs(Reagent.Buttons(current)) do
        if not reason then
            for _, key in ipairs(GREY_LAYERS) do
                local layer = button[key]
                if type(layer) == "table" and layer.IsShown and layer:IsShown() then
                    layer:Hide()
                    layers = layers + 1
                end
            end
        end
        local icon = button.icon or button.Icon
        if type(icon) == "table" and icon.IsDesaturated and icon:IsDesaturated() and button.GetBagID and button.GetID then
            local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
            if not (info and info.isLocked) then
                if type(SetItemButtonDesaturated) == "function" then SetItemButtonDesaturated(button, false)
                else icon:SetDesaturated(false) end
                desat = desat + 1
            end
        end
    end
    local raised, top = Reagent.KeepAboveBag()
    Reagent.lastSync = { t = GetTime(), reason = reason, layers = layers, desat = desat, raised = raised,
        level = current:GetFrameLevel(), bagLevel = attachedTo and attachedTo:GetFrameLevel() or nil, top = top }
    return layers + desat
end

-- Vermutung aus dem Review (nicht belegt): Ein Klick in die Tasche hebt sie als „toplevel“, und ihr halbdurchsichtiger
-- Hintergrund liegt dann über dem Abschnitt – er wirkt grau. KeepOnTop vergleicht nur die Ebene der Tasche selbst; hier
-- zählen auch ihre direkten Kinder (Hintergrund, Rahmen, Plätze). → angehoben?, höchste Ebene der Tasche
function Reagent.KeepAboveBag()
    if not (current and attachedTo) or combatHidden then return false, nil end
    local top = attachedTo:GetFrameLevel()
    for _, child in ipairs({ attachedTo:GetChildren() }) do
        local level = child.GetFrameLevel and child:GetFrameLevel()
        if type(level) == "number" and level > top then top = level end
    end
    if current:GetFrameLevel() > top then return false, top end
    if ns.InCombat() and current:IsProtected() then return false, top end
    current:Raise()
    return true, top
end

-- Diagnose (nur im Bericht von /ez debug, deutsch): was der letzte Abgleich im Abschnitt zurückgenommen hat
function Reagent.DiagnoseLine()
    local s = Reagent.lastSync
    if not s then return "ezBag Abschnitt Reagenzientasche: noch kein Abgleich" end
    return ("ezBag Abschnitt Reagenzientasche: letzter Abgleich vor %s – Grund für Grau: %s; Grauschicht weg: %d, "
        .. "Entsättigung weg: %d; angehoben: %s (Ebene Abschnitt %s, Tasche %s, höchstes Kind der Tasche %s)"):format(
        ezCore.Seconds(math.floor(GetTime() - s.t)), s.reason or "keiner", s.layers, s.desat, s.raised and "ja" or "nein",
        tostring(s.level), tostring(s.bagLevel), tostring(s.top))
end
if ezCore.Debug and type(ezCore.Debug.AddLine) == "function" then
    ezCore.Debug.AddLine("ezBag.reagentGrey", Reagent.DiagnoseLine, "ezBag")
end

-- Mauszeiger nimmt etwas auf oder legt es ab: Hinweis in der Überschrift nachziehen (ohne neu anzuordnen).
function Reagent.UpdateHeader()
    if header and header:IsShown() and current then header.text:SetText(Reagent.HeaderLabel()) end
end
ns.On("CURSOR_CHANGED", Reagent.UpdateHeader)
ns.On("GET_ITEM_INFO_RECEIVED", Reagent.UpdateHeader)   -- Getragenes war noch nicht geladen

-- Abschnitt aufheben: Fenster sieht wieder aus wie Blizzards (Lage setzt Blizzard bzw. Layout.lua neu).
function Reagent.Release()
    if header then header:Hide() end
    Reagent.ShowAfterCombat()
    if not current then return false end
    if ns.InCombat() and current:IsProtected() then return false end
    RestoreChrome()
    if watch then watch:Hide() end
    current, attachedTo = nil, nil
    return true
end

function Reagent.Current() return current end

-- Im Kampf ganz unsichtbar und nicht anklickbar (Tasche zu oder Abschnitt aus): nichts zerfällt sichtbar, bis ezBag nach
-- dem Kampf aufhebt. Nur Alpha und Maus – Lage und Blizzards Tabellen bleiben.
function Reagent.HideForCombat(frame)
    if combatHidden or not frame then return end
    combatHidden = { frame = frame, alpha = frame:GetAlpha(), mouse = {} }
    frame:SetAlpha(0)
    for _, button in ipairs(Reagent.Buttons(frame)) do
        combatHidden.mouse[button] = button:IsMouseEnabled()
        button:EnableMouse(false)
    end
    if header then header:Hide() end
end

function Reagent.ShowAfterCombat()
    local was = combatHidden
    if not was then return false end
    combatHidden = nil
    was.frame:SetAlpha(was.alpha or 1)
    for button, on in pairs(was.mouse) do button:EnableMouse(on) end
    return true
end

-- Tasche geht auf: Reagenzientasche mitöffnen (nicht im Kampf; ezCore sagt im Kampf „false, combat“).
function Reagent.OnBagShown()
    if not Reagent.Wanted() or not Reagent.HasBag() or Reagent.Frame() then return false end
    return ezCore.OpenPanel("reagentBag", nil, true) == true
end

-- Nach dem Kampf: ist die Tasche inzwischen zu, die Reagenzientasche auch schließen.
local function CloseIfBagHidden()
    local bagFrame = ns.Layout and ns.Layout.Frame()
    if bagFrame and bagFrame:IsShown() then return false end
    if not Reagent.Frame() then return false end
    return ezCore.ClosePanel("reagentBag", nil, true) == true
end
Reagent.CloseIfBagHidden = CloseIfBagHidden

-- Tasche geht zu: Abschnitt aufheben und die Reagenzientasche mitschließen (im Kampf nach dem Kampf). Sie gehört zur
-- einen Tasche – auch wenn sie vorher einzeln geöffnet war, geht sie mit zu (wie bei Blizzards B).
function Reagent.OnBagHidden()
    Reagent.Release()
    if not Reagent.Wanted() or not Reagent.Frame() then return false end
    if ns.InCombat() then
        ns.AfterCombat(CloseIfBagHidden, Reagent.AFTER_COMBAT_KEY)
        return false
    end
    return CloseIfBagHidden()
end


-- Blizzards Fenster melden, wenn sich die Reagenzientasche zeigt, versteckt oder neu anordnet (alle ContainerFrameN –
-- Blizzard vergibt sie je Öffnen neu). onChange(frame) und onItems(frame) (Blizzard hat die Plätze neu gefüllt) kommen
-- nur für die Reagenzientasche.
function Reagent.HookFrames(onChange, onItems)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and not hooked[frame] then
            hooked[frame] = true
            local function Changed(self)
                if IsReagentFrame(self) or self == current then onChange(self) end
            end
            frame:HookScript("OnShow", Changed)
            frame:HookScript("OnHide", Changed)   -- aufheben samt Plätzen macht Layout.lua (ReleaseSection)
            if frame.UpdateItemLayout then hooksecurefunc(frame, "UpdateItemLayout", Changed) end
            if frame.UpdateFrameSize then hooksecurefunc(frame, "UpdateFrameSize", Changed) end
            if frame.UpdateItems and onItems then
                hooksecurefunc(frame, "UpdateItems", function(self)
                    if self == current then onItems(self) end
                end)
            end
        end
    end
end
