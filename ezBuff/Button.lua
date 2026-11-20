local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Der Knopf: Blizzards Buff-Vorlage (AuraButtonArtTemplate), aber auf einen Blick anders als ein vorhandener
    Buff (Spieltest 13.11.2026: „direkt in der Buffleiste … wird das keinem auffallen“):
      - eine halbe Symbolbreite Abstand zu Blizzards Buffs,
      - pulsierender Rand aus Blizzards Proc-Leuchten (ActionButtonSpellAlertTemplate), getönt nach ezCores
        Leuchtfarben: Orange = Buff fehlt (Symbol entsättigt), Gold = jetzt nutzbar (Buff zurückgeben),
      - darunter „fehlt“ bzw. „danke“ in derselben Farbe, der Tooltip beginnt mit der Bedeutung der Farbe.
    Er hängt an Blizzards Buff-Leiste und wandert im Bearbeitungsmodus mit – die Buff-Leiste selbst wird nie
    verschoben, umgehängt oder angemeldet. Eine eigene Reihe unter den Buffs ginge nicht sauber: dort liegt
    Blizzards Debuff-Leiste (eigener Rahmen im Bearbeitungsmodus).

    Sicher (Core.SecureButton „ezBuffButton“, Blizzards SecureActionButtonTemplate): Linksklick benutzt Gegenstand
    oder Zauber der ersten Aufgabe. Attribute und Sichtbarkeit setzt ezCore nur außerhalb des Kampfes, Lage und
    Größe des Halters ezBuff ebenso; im Kampf blendet Blizzards Zustandstreiber den Halter aus ("[combat] hide;
    show"), danach kommt er von selbst wieder. Rechtsklick: eigene Wahl je Wahlgruppe (Segen, Rüstung, Schild) und
    Einstellungen (Button.OpenMenu).
]]

local Button = {}
ns.Button = Button

local holder, button, secure, glow, tour   -- secure: Griff aus Core.SecureButton, button: sein Rahmen
local failReported              -- Anlegen des Knopfs gescheitert und gemeldet (Build)
local current                   -- Aufgabe, die der Knopf gerade zeigt
local cleared                   -- Aktion zu Kampfbeginn geleert (Button.OnCombatStart): ein Druck im Kampf tut nichts
local previewUntil = 0
local QUESTION = Core.ICON_FALLBACK
local THANK_ICON = "Interface\\Icons\\INV_ValentinesCard02"
local BORDER = "Interface\\Buttons\\UI-TempEnchant-Border"
local MAX_TIP_LINES = 12
local ICON_SIZE = 30            -- Symbol in AuraButtonArtTemplate
local GAP = 0.5                 -- Abstand zu Blizzards Buffs: halbe Symbolbreite (zusätzlich zu iconPadding)
local GLOW_FACTOR = 1.4         -- wie Blizzards Proc-Leuchten: 1,4-mal so groß wie das Symbol
Button.GAP = GAP
Button.ICON_SIZE = ICON_SIZE

---------------------------------------------------------------------------
-- Leuchtfarbe: Orange = Buff fehlt, Gold = jetzt nutzbar (Buff zurückgeben) – Farben aus ezCore.GLOW_KINDS
---------------------------------------------------------------------------

function Button.GlowKind(task)
    if task and task.kind == "rebuff" then return "reactive" end
    return "missing"
end

-- Leuchtrahmen am Symbol aus ezCores Leucht-Dienst (Core.NewGlow, EC-59/BF-14): Blizzards Proc-Leuchten als Schleife
-- ohne den großen Start-Blitz, dazu ein Pulsieren; ohne Blizzards Vorlage ein Rand wie beim Zeigen auf einen
-- Aktionsknopf. Getönt wird beim Zeigen nach der Art. Der Knopf ist geschützt: gebaut wird nur außerhalb des Kampfes.
-- Vorher baute ezBuff diesen Rahmen selbst (Pulse, BuildGlow, eigene Vorlage und Ersatz-Textur).
local function BuildGlow()
    glow = Core.NewGlow(button, { secure = true, start = false, pulse = true, width = ICON_SIZE * GLOW_FACTOR,
        height = ICON_SIZE * GLOW_FACTOR, anchor = button.Icon or button, level = 5 })
end

-- Hüllen um den Rahmen aus ezCore (Leitlinie 8): ShowGlow(art) zeigt bzw. tönt um, Glow() gibt den Rahmen und die
-- Art, solange er sichtbar ist.
function Button.ShowGlow(kind)
    if not glow then return false end
    return glow:Show(kind)
end

function Button.Glow()
    if not glow then return nil end
    return glow.frame, glow:Kind()
end

---------------------------------------------------------------------------
-- Aufbau: der sichere Knopf kommt aus ezCore (Core.SecureButton, EC-60/BF-12), Halter und Optik bleiben
---------------------------------------------------------------------------

-- Ältere Clients ohne Blizzards Buff-Vorlage: gleiche Teile selbst, in den Maßen von Blizzards AuraButtonArtTemplate
-- (Blizzard_BuffFrame/BuffFrameTemplates.xml, Zweig forever: Icon 30 × 30 = Core.Style.ICON.aura, TempEnchantBorder
-- 32 × 32). Die 32 folgt Blizzards Rand um das Symbol und ist darum keine Abweichung (Design-System 2.3).
local function BuildParts(frame)
    frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.Icon:SetSize(Core.Style.ICON.aura, Core.Style.ICON.aura)
    frame.Icon:SetPoint("TOP")
    frame.Duration = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
    frame.Duration:SetPoint("TOP", frame.Icon, "BOTTOM")
    frame.Count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.Count:SetPoint("BOTTOMRIGHT", frame.Icon, -2, 2)
    frame.TempEnchantBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.TempEnchantBorder:SetSize(32, 32)   -- wie Blizzards TempEnchantBorder (siehe oben)
    frame.TempEnchantBorder:SetPoint("CENTER", frame.Icon)
    frame.TempEnchantBorder:SetTexture(BORDER)
end

-- Einmal nach dem Anlegen, außerhalb des Kampfes (onCreate von Core.SecureButton): alles Ungeschützte am Knopf.
-- RegisterForClicks("AnyUp"), useOnKeyDown = false (Mausklick beim Loslassen, unabhängig von „Aktion bei
-- Tastendruck“) und das Ausblenden setzt ezCore.
local function OnCreate(frame, handle)
    button = frame
    if handle:TemplateMissing() or not frame.Icon then BuildParts(frame) end
    frame:SetAllPoints(holder)
    if frame.DebuffBorder then frame.DebuffBorder:Hide() end
    -- Der lila Rand gehört zu Waffen-Verzauberungen: er würde den Knopf wie einen vorhandenen Buff aussehen lassen.
    if frame.TempEnchantBorder then frame.TempEnchantBorder:Hide() end
    if frame.Symbol then frame.Symbol:SetText("") end
    BuildGlow()

    frame:SetScript("PreClick", function(self, mouse)
        if mouse ~= "LeftButton" or ns.InCombat() then return end
        if current and current.refresh and Button.ApplyAction(current.refresh()) then cleared = nil end
    end)
    frame:SetScript("PostClick", function(self, mouse)
        if mouse == "RightButton" then
            Button.OpenMenu(self)
            return
        end
        local task = current
        if not task or GetTime() < previewUntil then return end
        if task.kind == "rebuff" then
            -- Zu Kampfbeginn geleert (Kürzel einer Namensplakette): Der Druck auf die Taste im Kampf wirkt nichts, also
            -- auch kein Dank und das Angebot bleibt. Sonst dankt Rebuff.Done höchstens einmal je erhaltenem Buff.
            if not cleared then ns.Rebuff.Done(task) end
        elseif not task.action then
            ns.PrintMissing(true)
        end
        C_Timer.After(0.5, function() ns.Check.Request() end)
    end)
    frame:SetScript("OnEnter", function(self) Button.ShowTooltip(self) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Im Kampf weg, danach wieder da: Blizzards sicherer Zustandstreiber am Halter (er trägt auch den Durchbuff-Knopf
-- aus Group.lua). RegisterStateDriver setzt Attribute an Blizzards geschütztem SecureStateDriverManager und ist darum
-- im Kampf für Addon-Code gesperrt, an jedem Rahmen (Gesamtreview 18.11.2026, T2-1). Nach einem Neuladen im Kampf
-- meldet ezBuff den Treiber deshalb erst nach dem Kampf an (ns.AfterCombat); bis dahin ist der Halter leer – die
-- sicheren Knöpfe entstehen bei ezCore ebenfalls erst nach dem Kampf – und ungeschützt, ein Hide genügt. Ohne
-- Zustandstreiber (ältere Clients) von Hand zu Kampfbeginn und -ende.
local driver   -- "state": Zustandstreiber angemeldet, "events": von Hand, nil: noch nicht
local function HideInCombat()
    if driver or not holder then return end
    local unprotected = not (holder.IsProtected and holder:IsProtected())
    if not RegisterStateDriver then
        driver = "events"
        ns.On("PLAYER_REGEN_DISABLED", function() holder:Hide() end)
        ns.On("PLAYER_REGEN_ENABLED", function() holder:Show() end)
        if ns.InCombat() and unprotected then holder:Hide() end
        return
    end
    if ns.InCombat() then
        if unprotected then holder:Hide() end
        ns.AfterCombat(HideInCombat, "holderDriver")
        return
    end
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")
    driver = "state"
    holder:Show()   -- nach dem Kampf: das Hide von oben aufheben (außerhalb des Kampfes erlaubt, sonst ohne Wirkung)
end

-- Wie der Halter im Kampf verschwindet: "state" (Zustandstreiber), "events" (von Hand) oder nil (wartet auf das
-- Kampfende) – für die Prüfungen.
function Button.CombatHiding() return driver end

local function Build()
    if secure then return button end
    -- Der Halter entsteht nur einmal: Build läuft bei jedem Zeigen (Einstellungen, Bearbeitungsmodus), und der
    -- Durchbuff-Knopf aus Group.lua hängt am ersten Halter. Scheitert das Anlegen des Knopfs (Name belegt, Fehler),
    -- versucht der nächste Aufruf nur den Knopf erneut.
    if not holder then
        holder = CreateFrame("Frame", "ezBuffHolder", UIParent)
        holder:SetSize(30, 40)
        holder:SetFrameStrata("LOW")
        HideInCombat()
    end
    -- Wird nach einem Neuladen im Kampf angelegt, entsteht der Rahmen erst danach (onCreate setzt button);
    -- Button.Update und Button.Anchor prüfen auf nil.
    local reason
    secure, reason = Core.SecureButton("ezBuffButton", { owner = ns.moduleName, parent = holder,
        template = "AuraButtonArtTemplate", onCreate = OnCreate })
    if not secure and not failReported then
        failReported = true   -- einmal je Sitzung melden, nicht bei jedem Zeigen
        ns.Print(reason == "taken" and L.BUTTON_FAILED_TAKEN or L.BUTTON_FAILED:format(tostring(reason)))
    end
    return button
end

---------------------------------------------------------------------------
-- Lage: mit Abstand neben Blizzards Buffs (nur außerhalb des Kampfes)
---------------------------------------------------------------------------

-- Ohne Blizzards Buff-Leiste (bzw. ohne bekannte Lage): oben rechts, wo sie sonst stünde.
local function AnchorFallback()
    holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -13)
end

function Button.Anchor()
    if not holder or ns.InCombat() then return false end
    holder:ClearAllPoints()
    local frame = BuffFrame
    if type(frame) ~= "table" then
        AnchorFallback()
        return true
    end
    local container = frame.AuraContainer
    local horizontal = not (container and container.isHorizontal == false)
    local toRight = container and container.addIconsToRight == true
    local toTop = container and container.addIconsToTop == true
    local padding = (container and ns.Num(container.iconPadding)) or 5
    local scale = (container and ns.Num(container.iconScale)) or 1
    local parentScale = UIParent:GetEffectiveScale()
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or parentScale
    holder:SetScale((frameScale / parentScale) * scale)

    -- Abstand in Symbol-Einheiten (der Halter hat dieselbe Skalierung wie Blizzards Symbole).
    local gap = padding + ICON_SIZE * GAP
    local last = frame.GetLastActiveAuraFrame and frame:GetLastActiveAuraFrame()
    if last and last.IsShown and last:IsShown() then
        if horizontal then
            if toRight then
                holder:SetPoint("TOPLEFT", last, "TOPRIGHT", gap, 0)
            else
                holder:SetPoint("TOPRIGHT", last, "TOPLEFT", -gap, 0)
            end
        elseif toTop then
            holder:SetPoint("BOTTOMLEFT", last, "TOPLEFT", 0, gap)
        else
            holder:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -gap)
        end
    else
        local corner = (toTop and "BOTTOM" or "TOP") .. (toRight and "LEFT" or "RIGHT")
        holder:SetPoint(corner, container or frame, corner)
    end
    return true
end

-- Kampfbeginn (PLAYER_REGEN_DISABLED, die Sperre greift erst nach dem Ereignis): den Halter von Blizzards Buff-Leiste
-- lösen. Er trägt die sicheren Knöpfe und ist damit geschützt; ein geschützter Rahmen, der an einem Rahmen verankert
-- ist, schützt diesen im Kampf mit – sonst hinge Blizzards gepoolter Aura-Knopf (GetLastActiveAuraFrame) bzw. der
-- AuraContainer im Kampf am Halter (Gesamtreview 18.11.2026, T2-4; dasselbe Muster wie ezCraft, Sal.Disarm). Der Halter
-- bleibt auf derselben Bildschirmlage, jetzt an UIParent; im Kampf ist er ohnehin ausgeblendet. Nach dem Kampf
-- verankert Button.Anchor ihn wieder an Blizzards Buff-Leiste (PLAYER_REGEN_ENABLED, unten).
function Button.Detach()
    if not holder or ns.InCombat() then return false end
    local left, top = holder:GetLeft(), holder:GetTop()
    holder:ClearAllPoints()
    if ns.IsSecret(left) or ns.IsSecret(top) or type(left) ~= "number" or type(top) ~= "number" then
        AnchorFallback()
    else
        -- GetLeft/GetTop und die Abstände von SetPoint rechnen beide in der Skalierung des Halters
        holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    return true
end

---------------------------------------------------------------------------
-- Inhalt
---------------------------------------------------------------------------

-- Sichere Attribute für eine Aktion (nil = Klick tut nichts Geschütztes). Über Core.SecureButton (EC-60):
-- SetAction(aktion, 1) löscht die übrigen Aktions-Attribute und setzt type1, spell1, unit1, item1, macro1,
-- macrotext1 – nur Linksklick wie vorher (type1). Im Kampf wartet der Wunsch bei ezCore: false, "combat".
function Button.ApplyAction(action)
    if not secure then return false end
    if type(action) ~= "table" then action = nil end
    return secure:SetAction(action, 1)
end

-- Farbenblind-Hilfe (EC-47): Ist in ezCore „Zeichen am Leuchten“ an (Core.Glow.MarksEnabled), steht das Zeichen der
-- Art (Core.GlowMark: * + o !) zusätzlich zur Farbe vor dem kurzen Text am Knopf. Seit ezCore 1.12.0 leitet die
-- Funktion auf Core.GlowMarkText weiter (ein Helfer für alle Module); ohne Art bleibt der Text wie bisher ohne Zeichen.
function Button.MarkedText(text, kind)
    if not kind then return text end
    if type(Core.GlowMarkText) == "function" then return Core.GlowMarkText(text, kind) end
    local on = Core.Glow and type(Core.Glow.MarksEnabled) == "function" and Core.Glow.MarksEnabled()
    local mark = on and kind and Core.GlowMark(kind) or nil
    if mark and type(text) == "string" and text ~= "" then return mark .. " " .. text end
    return text
end

local function Show(task, count, preview)
    current = task
    cleared = nil
    Button.ApplyAction(not preview and task.action or nil)
    local kind = Button.GlowKind(task)
    local icon = task.icon or (task.thankOnly and THANK_ICON) or QUESTION
    button.Icon:SetTexture(icon)
    -- Fehlt etwas: Symbol grau wie ein inaktiver Buff, damit es nicht wie ein vorhandener aussieht.
    if button.Icon.SetDesaturated then button.Icon:SetDesaturated(kind == "missing") end
    if button.Duration then
        -- Fehlt dem Zauber ein Reagenz oder Werkzeug (Check.MissingReagents), sagt es der kurze Text („Reagenz“)
        local short = task.kind == "rebuff" and L.BUTTON_REBUFF or (task.missingReagents and L.BUTTON_NO_REAGENT)
            or L.BUTTON_MISSING
        button.Duration:SetText(Button.MarkedText(short, kind))
        if button.Duration.SetTextColor then button.Duration:SetTextColor(Core.GlowColor(kind)) end
        button.Duration:Show()
    end
    if button.Count then button.Count:SetText(count > 1 and tostring(count) or "") end
    Button.Anchor()
    secure:Show()
    Button.ShowGlow(kind)
end

function Button.Update()
    if not button then return end
    -- Im Kampf darf sich der sichere Knopf nicht ändern: einmal nach dem Kampf nachholen (ezCore.AfterCombat, EC-67;
    -- vorher ein eigener Merker und Zuhörer auf PLAYER_REGEN_ENABLED).
    if ns.InCombat() then
        ns.AfterCombat(Button.Update, "button")
        return
    end
    if GetTime() < previewUntil then return end
    local tasks = ns.Check.Tasks()
    local task = ns.Check.First()
    if not ns.Enabled("button") or not task then
        current, cleared = nil, nil
        Button.ApplyAction(nil)
        secure:Hide()
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        return
    end
    Show(task, #tasks, false)
    if GameTooltip:IsOwned(button) then Button.ShowTooltip(button) end
    -- Beim ersten Erscheinen: Rundgang mit Erklärblasen (bis alle Blasen bestätigt sind)
    local t = Button.Tour()
    if not t:Done() then t:Start() end
end

function Button.Current() return current end

---------------------------------------------------------------------------
-- Kampfbeginn: Der Knopf ist im Kampf ausgeblendet, die Taste „ezBuff: fehlenden Buff wirken“ (über ezBuffButtonKey)
-- drückt ihn aber weiter, und im Kampf darf ezBuff die Aktion nicht neu belegen. Feste Kürzel (player, partyN,
-- raidN) zeigen im Kampf weiter auf dieselbe Einheit: eigene Buffs, Gegenstände und Gruppen-Buffs bleiben wie bisher
-- mit einem Druck nutzbar. Ein anderes Kürzel – beim „Buff zurückgeben“ das aus UnitTokenFromGUID, oft nameplateN,
-- oder target/focus/mouseover – kann im Kampf auf jemand anderen zeigen; dann leert ezBuff die Aktion beim
-- Kampfbeginn (PLAYER_REGEN_DISABLED, vor der Sperre – wie Group.OnCombatStart beim Durchbuff-Knopf), und der Druck
-- im Kampf wirkt nichts. Das Makro mit /targetexact (Spieler ohne Kürzel) sucht nach dem Namen und bleibt.
-- Entschieden wird nach der Belegung bei ezCore (Handle:Get, Wunsch für die linke Maustaste), nicht nach der Aktion
-- beim Bau der Aufgabe: Der PreClick belegt über task.refresh neu (aus dem Makro wird ein Zauber auf nameplateN,
-- sobald der Spender sichtbar ist), und bis die Prüfung die Aufgabe abräumt, kann ein Kampf beginnen.
-- Nach dem Kampf belegt Button.Update (bzw. der PreClick) wieder.
---------------------------------------------------------------------------

function Button.FixedUnit(unit)
    if ns.IsSecret(unit) then return false end
    if unit == nil or unit == "player" then return true end
    if type(unit) ~= "string" then return false end
    return unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

function Button.OnCombatStart()
    if not secure or not current or secure:Get("type1") == nil then return false end
    if Button.FixedUnit(secure:Get("unit1")) then return false end
    cleared = true
    Button.ApplyAction(nil)
    return true
end

function Button.OnCombatEnd()
    if not cleared then return false end
    cleared = nil
    Button.Update()
    return true
end

function Button.Cleared() return cleared == true end
function Button.Frame() return button, holder end
function Button.Secure() return secure end

-- Beispiel zeigen (Einstellungen „Zeigen“, Bearbeitungsmodus): Klick tut dabei nichts.
function Button.Preview(seconds)
    Build()
    if ns.InCombat() or not button then return false end
    previewUntil = GetTime() + (seconds or 10)
    Show({ kind = "food", label = L.MISSING_FOOD, icon = "Interface\\Icons\\INV_Misc_Food_15", action = nil, preview = true }, 1, true)
    C_Timer.After((seconds or 10) + 0.05, function()
        if GetTime() >= previewUntil then Button.Update() end
    end)
    return true
end

---------------------------------------------------------------------------
-- Tooltip: zuerst die Bedeutung der Farbe, dann alles, was fehlt, und was ein Klick tut
---------------------------------------------------------------------------

function Button.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    local kind = Button.GlowKind(current)
    local r, g, b = Core.GlowColor(kind)
    GameTooltip:SetText(Core.GlowLabel(kind) or L.TITLE, r, g, b)
    if GetTime() < previewUntil then
        Core.TipLine(GameTooltip, L.TIP_PREVIEW, "highlight", true)
        Core.TipLine(GameTooltip, L.TIP_COMMAND, "hint")
        GameTooltip:Show()
        return
    end
    local tasks = ns.Check.Tasks()
    for index, task in ipairs(tasks) do
        if index > MAX_TIP_LINES then
            Core.TipLine(GameTooltip, ezCore.More(#tasks - MAX_TIP_LINES), "hint")
            break
        end
        -- Rolle statt Farbzahlen (T9-6): die nächste Aufgabe grün, Aufgaben ohne Handlung grau
        local role = "highlight"
        if task == current then role = "good" elseif not task.action and not task.thankOnly then role = "hint" end
        Core.TipLine(GameTooltip, task.label, role)
        -- Quelle der Erwartung (Leitlinie 11), z. B. „ab Stufe 4, laut Client“ beim Buff einer anderen Klasse
        if type(task.note) == "string" then Core.TipLine(GameTooltip, "   " .. task.note, "hint") end
        -- „Dir fehlt: Arkanes Pulver (0 von 1)“ samt Quelle des Bedarfs (Paket modul/ezbuff-reagenzien)
        if task.missingReagents then
            Core.TipLine(GameTooltip, "   " .. ns.Check.ReagentText(task.missingReagents), "orange")
            Core.TipLine(GameTooltip, "   " .. ns.Check.ReagentSource(task.reagentSource), "gray")
        end
    end
    if current then
        local click
        if current.thankOnly then
            click = L.TIP_CLICK_THANK
        elseif current.action and current.kind == "rebuff" and current.thank then
            click = L.TIP_CLICK_REBUFF:format(current.spellName or "?")
        elseif current.action then
            click = L.TIP_CLICK_USE:format(current.itemName or current.spellName or "?")
        else
            click = L.TIP_CLICK_REPORT
        end
        GameTooltip:AddLine(" ")
        Core.TipLine(GameTooltip, click, "normal")
    end
    Core.TipLine(GameTooltip, Button.HasMenu() and L.TIP_RIGHT_MENU or L.TIP_RIGHT, "hint")
    Core.TipLine(GameTooltip, Button.KeyLine(), "hint", true)
    Core.TipLine(GameTooltip, L.TIP_COMMAND, "hint")
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Taste (ezCores Tasten-Dienst, EC-73): Der Eintrag „buff“ in Core.Keys.LIST („ezBuff: fehlenden Buff wirken“,
-- CLICK ezBuffButtonKey:LeftButton in ezCore/Bindings.xml) drückt diesen Knopf – über einen Stellvertreter, der
-- Blizzards „Aktion bei Tastendruck“ folgt (Gesamtreview 18.11.2026, Nachlauf zu T9-NB1; Mausklick bleibt beim
-- Loslassen). ezBuff zeigt die belegte Taste im
-- Tooltip und im Status und führt mit „Taste festlegen“ (Einstellungen, Allgemein) zu Blizzards Tastaturbelegung.
-- Ausführen muss ezBuff nichts (Keys.Register gilt nur für Fenster-Umschalter; ein CLICK-Eintrag läuft über den
-- sicheren Knopf selbst, auch im Kampf).
---------------------------------------------------------------------------

Button.KEY_ID = "buff"

-- Belegte Taste(n) als Text oder nil (ohne Tasten-Dienst oder ohne Belegung). id: Eintrag im Tasten-Dienst, ohne
-- Angabe der des Buff-Knopfs; Group.Key fragt so „buffNext“ (Gegenprüfung P3, ein Weg für beide Tasten).
-- Zweiter Wert: true, wenn der Tasten-Dienst den Eintrag kennt (sonst darf der Aufrufer selbst nachsehen).
function Button.KeyText(id)
    id = id or Button.KEY_ID
    local Keys = Core.Keys
    if not (Keys and type(Keys.KeyText) == "function" and type(Keys.Get) == "function" and Keys.Get(id)) then
        return nil, false
    end
    local text = Core.Call(Keys.KeyText, id)
    if ns.IsSecret(text) or type(text) ~= "string" or text == "" then return nil, true end
    return text, true
end

function Button.KeyLine()
    local key = Button.KeyText()
    if key then return L.TIP_KEY:format(key) end
    return L.TIP_KEY_NONE:format(ns.PathText("SETTINGS_GENERAL", "OPT_BUTTON_KEY"))
end

-- Einstellungen » Allgemein » „Taste festlegen“: Blizzards Tastaturbelegung (über den Tasten-Dienst, sonst direkt).
function Button.OpenKeyBindings()
    if ns.InCombat() then
        Core.CombatNotice(ns, L.KEYS_COMBAT_WHAT)
        return false
    end
    local Keys = Core.Keys
    if Keys and type(Keys.Open) == "function" then return Keys.Open() and true or false end
    return Core.OpenPanel("settings", "keybindings") and true or false
end

---------------------------------------------------------------------------
-- Rechtsklick: eigene Wahl je Wahlgruppe (EC-39, ST-10) und Einstellungen
---------------------------------------------------------------------------

-- Ein Menü gibt es, wenn deine Klasse eine Wahlgruppe hat (Segen, Rüstung, Schild, Waffenzauber) oder Buffs zum Durchbuffen
-- (Eintrag „Makro anlegen“, Macro.lua) und der Client Blizzards Kontextmenü kennt; sonst öffnet der Rechtsklick wie
-- bisher die Einstellungen.
function Button.HasMenu()
    local util = rawget(_G, "MenuUtil")
    if type(util) ~= "table" or type(util.CreateContextMenu) ~= "function" then return false end
    return #ns.Check.ChoiceGroups() > 0 or (ns.Macro ~= nil and ns.Macro.Supported())
end

-- Je Wahlgruppe eine Stufe „Rüstung: Magische Rüstung“ mit „Automatisch (Vorschlag: …)“ und jedem wählbaren Buff;
-- dieselbe gemerkte Wahl wie auf der Einstellungsseite und beim Wirken (Check.SetPrefer). Darunter „Einstellungen“.
function Button.BuildMenu(root)
    root:CreateTitle(L.TITLE)
    for _, group in ipairs(ns.Check.ChoiceGroups()) do
        local id = group.id
        local sub = root:CreateButton(L.MENU_PREFER:format(ns.Check.KindName(id), ns.Check.PreferText(id)))
        sub:CreateRadio(ns.Check.AutoText(id), function() return ns.Check.Prefer(id) == nil end,
            function() ns.Check.SetPrefer(id, nil) end)
        for _, choice in ipairs(ns.Check.Choices(id)) do
            local key = choice.key
            sub:CreateRadio(choice.name, function() return ns.Check.Prefer(id) == key end,
                function() ns.Check.SetPrefer(id, key) end)
        end
    end
    -- Vorlage „Durchbuffen“ (Macro.lua; dasselbe wie der Knopf unter Einstellungen » Gruppe)
    if ns.Macro and ns.Macro.Supported() then root:CreateButton(L.MENU_MACRO, function() ns.Macro.Create() end) end
    root:CreateDivider()
    Core.Menu.Settings(root, ns)   -- „Einstellungen …“ von ezCore (Gesamtreview T18-8)
    return true
end

function Button.OpenMenu(owner)
    if GameTooltip:IsOwned(owner or button) then GameTooltip:Hide() end
    if Button.HasMenu() and Core.Menu.Open(owner or button, Button.BuildMenu) then return true end
    ns.OpenSettings()
    return false
end

---------------------------------------------------------------------------
-- Rundgang mit Erklärblasen (ezCore.NewTour): beim ersten Erscheinen des Knopfs, erneut über
-- Einstellungen → Erweitert → „Erklärung erneut zeigen“
---------------------------------------------------------------------------

local TOUR_STEPS = { "button", "click", "rebuff", "report" }

function Button.Tour()
    if tour then return tour end
    local steps = {}
    for _, key in ipairs(TOUR_STEPS) do
        steps[#steps + 1] = { key = key, target = function() return button end, side = "below",
            text = L["BUFF_TOUR_" .. key:upper()] }
    end
    -- module: die Einführung erledigt die Blasen mit der Seite von ezBuff (Core.ModuleTours, Spieltest 19.11.2026)
    tour = Core.NewTour({ store = function() return ns.db and ns.db.hints end, steps = steps, module = "ezBuff" })
    return tour
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(function()
    Build()
    ns.Listen("TASKS", Button.Update)
    local anchorSoon = ns.Throttle(function() if button and button:IsShown() then Button.Anchor() end end, 0.1)
    -- Eine gesperrte Einheit (UNIT_AURA im Kampf, W-04) wird nie verglichen: hinter ns.OnUnit mit „player“ weckt
    -- Blizzard nur für dich, sie zählt als Treffer. Button.Anchor selbst tut im Kampf nichts (sicherer Knopf).
    ns.OnUnit("UNIT_AURA", "player", function(_, unit)
        if ns.IsSecret(unit) or unit == "player" then anchorSoon() end
    end)
    -- Nach dem Kampf neu ausrichten (das Nachholen von Button.Update läuft vorher über ns.AfterCombat).
    ns.On("PLAYER_REGEN_ENABLED", function()
        Button.OnCombatEnd()
        Button.Anchor()
    end)
    ns.On("PLAYER_REGEN_DISABLED", function()
        Button.OnCombatStart()
        Button.Detach()
    end)
    ns.On("PLAYER_ENTERING_WORLD", function() Button.Anchor() end)
    -- Blizzards Buff-Leiste ordnet neu (Buffs kommen und gehen, Bearbeitungsmodus): mitziehen.
    if type(BuffFrame) == "table" and type(BuffFrame.UpdateAuraButtons) == "function" then
        hooksecurefunc(BuffFrame, "UpdateAuraButtons", anchorSoon)
    end
    Core.EditMode.OnChange(function(active)
        if ns.InCombat() then return end
        if active then
            Button.Preview(3600)
        else
            previewUntil = 0
            Button.Update()
        end
    end, ns.moduleName)
end)
