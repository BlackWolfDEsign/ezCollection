local _, ns = ...
local L = ns.L

--[[
    Zusammengefasste Stapel ganz weitergeben (Spielbefund vom 21.11.2026: „ezmail bzw ezbag, zeigt mir 29leinenstoff
    in einem slot an (nice) aber wie lege ich alles davon in einen brief mit rechtsklick? ich kann nur einmalig 20
    reinpacken über die tasche“).

    Fasst ezBag gleiche Stapel zu einem Platz zusammen (Render.Compact, Einstellung „Gleiche zusammenfassen“), liegt
    dort Blizzards Knopf des größten Stapels. Blizzards Rechtsklick gibt nur diesen einen Stapel weiter
    (C_Container.UseContainerItem). Danach gibt ezBag die übrigen Stapel desselben Platzes nach (nur Stapel, die
    gleich gebunden sind wie der angeklickte – wie ezMails Alt-Klick):
      Post (Reiter Senden)  0,2 s später; mit ezMail über dessen Anhängen (ezCore.API("ezMail").AttachEntries –
                            dieselben Meldungen und dasselbe Nachsenden wie ezMails Alt-Klick), sonst über ezCores
                            Anhang-Schlange (Core.MailQueue.Attach): nur freie Anhangplätze (12 je Brief), gesperrte und
                            nicht verschickbare Stapel überspringt sie; was nicht passt, bleibt in der Tasche (Meldung).
      Handel                ein Stapel erst, wenn der Server den vorigen bestätigt hat (TRADE_PLAYER_ITEM_CHANGED, auch
                            für Blizzards eigenen), und nur solange ein Handelsplatz frei ist; den Rest nennt der Chat.
                            Kommt nach Stacks.TRADE_WAIT Sekunden keine Bestätigung, hört ezBag still auf.
      Bank                  0,2 s später; aus der Tasche in die Bank, aus der Bankansicht in die Tasche
                            (Select.UseAll wie „Auswählen“ → Einlagern; ein laufender Durchgang bekommt die Plätze dazu).
      Händler               0,2 s später verkauft (Entscheidung des Nutzers vom 21.11.2026: „yes sell all“) – nicht,
                            was nichts wert ist, und nicht, was das Schloss „nie verkaufen“ trägt (ns.NeverSell).
                            Zurückkaufen geht über Blizzards Reiter „Rückkauf“ (dort die letzten 12 Stapel).
    Ohne eines dieser Fenster benutzt Blizzards Klick den Gegenstand – dann tut ezBag nichts dazu.

    Anzahl weitergeben (Wünsche des Nutzers vom 21.11.2026, wörtlich: „shift rechtsklick auf item anzahl auswählen und
    verkauft diese anzahl mit bestätigen durch "OK"“ und „Das mit dem shift+rechtsklick muss generell gelten, auch bei
    der bank, post, händler und co“; Entscheidungen vom selben Tag „Yes, own field“ und – nach „ich hab 24 wollstoff und
    kann 18 auswählen, die zahl kann ich ebenfalls nicht editieren“ – „Eigenes Feld, Ausnahme (Empfohlen)“):
    Umschalt+Rechtsklick auf einen Stapel öffnet erst Blizzards Anzahl-Fenster (StackSplitFrame). Das reicht nur bis
    zum Stapel unter dem Knopf. ezBag schließt es darum gleich wieder (StackSplitFrame:Hide() – Ausnahme 3 von
    Leitlinie 5, CLAUDE.md: Blizzards eigenes Schließen setzt dabei hasStackSplit an Blizzards Taschenknopf; nur, wenn
    Blizzard es bei genau diesem Klick geöffnet hat, mitgehört mit hooksecurefunc an StackSplitFrame:OpenStackSplitFrame,
    und nicht mit Gamepad-Oberfläche) und fragt in seinem eigenen Anzahl-Feld – so groß und an derselben Stelle wie
    Blizzards Teil-Fenster (Abschnitt „Das Anzahl-Feld“ unten)
    nach einer Anzahl bis zur Gesamtzahl aller Stapel des Platzes – die Zahl lässt sich tippen. Strg+Rechtsklick öffnet
    dasselbe Feld direkt.
    „Annehmen“ legt die Anzahl zuerst zu möglichst wenigen Stapeln zusammen (Spielbefund vom 22.11.2026: „11 und 21.
    ja das wird gemacht, aber die sollten einen slot einnehmen...“): bis zur Stapelgröße ein Stapel, darüber volle
    Stapel und der Rest. Dazu legt ezBag Stapel aufeinander oder teilt ab (C_Container.SplitContainerItem und
    PickupContainerItem, ein Schritt nach dem anderen, jeder erst nach der Bestätigung des Servers); nur wenn alle
    übrigen Stapel größer sind als nötig, braucht es einen freien Taschenplatz. Dann gibt ezBag die fertigen Stapel
    weiter wie oben (verkaufen, anhängen, handeln, ein- oder auslagern; aus der Bankansicht in die Tasche). Ist kein
    Händler, keine Post, kein Handel und keine Bank offen, hängt die Anzahl danach am Mauszeiger wie bei Blizzard
    (Entscheidung des Nutzers vom 22.11.2026 „Ja, Feld überall (Empfohlen)“ und danach, wörtlich: „in der tasche muss
    das geteilte in der hand bleiben“); dort reicht das Feld nur bis zur Stapelgröße. Fehlt ein nötiger freier Taschenplatz,
    sind zu wenige Anhang- oder Handelsplätze frei, schließt das Fenster oder klappt ein Schritt nicht, gibt ezBag
    nichts weiter (die Stapel liegen dann vielleicht anders verteilt da). Das Ziel gilt so, wie gefragt: Wechselt das
    Fenster bis „Annehmen“ (aus der Bank wird ein Händler), gibt ezBag nichts weiter. Im Kampf, mit einem Gegenstand am
    Mauszeiger oder für einen Stapel, der nicht weitergehen kann (Schloss „nie verkaufen“, gebunden an Post oder
    Handel), bleibt Blizzards Fenster, wie es ist. Anprobierbare Ausrüstung bekommt über Strg+Rechtsklick kein Feld
    (Strg+Klick ist dort Blizzards Anprobe).

    Regeln (docs/blizzard-regeln.md): Anhängen, Handeln, Umlagern und Verkaufen aus Taschen sind keine geschützten
    Aktionen; ezBag ruft sie wie „Auswählen“ (Select.lua) und das Nachsenden (ezCore/Charakter/MailQueue.lua)
    nacheinander, nie im Kampf (sonst ein Satz zur Kampfsperre) und nur, solange das Zielfenster offen ist.
    Taint-sicher (Leitlinie 5): nur HookScript an Blizzards Knopf (Layout.lua, Bank.lua), keine Werte in Blizzards
    Tabellen (StackSplitFrame.owner wird nur gelesen); einzige Ausnahme ist das Schließen von Blizzards Anzahl-Fenster
    oben. Sichtbar (Leitlinie 3): Ist ein Ziel offen, nennt der Tooltip des Platzes, was ein Rechtsklick und was
    Umschalt+Rechtsklick weitergibt.
]]

local Stacks = {}
ns.Stacks = Stacks

Stacks.START_DELAY = 0.2       -- Post, Bank und Händler: bis Blizzards eigener Stapel sicher unterwegs ist
Stacks.TRADE_SLOTS = 6         -- Handelsplätze, die gehandelt werden (der siebte wird nicht gehandelt)
Stacks.TRADE_WAIT = 2          -- so lange auf die Bestätigung eines Handelsplatzes warten
Stacks.SPLIT_STEP = 0.1        -- Zusammenlegen: so oft nachsehen, ob der letzte Schritt angekommen ist
Stacks.SPLIT_WAIT = ezCore.SPLIT_ARRIVE_WAIT or 5   -- … und so lange höchstens je Schritt (der Server bestätigt erst nach einer Weile)

local VIEWS = { bag = true, bank = true }   -- Ansichten, deren Knöpfe Layout.lua bzw. Bank.lua an Stacks melden

local function MailOpen() return SendMailFrame ~= nil and SendMailFrame:IsVisible() == true end
local function TradeOpen()
    local frame = _G.TradeFrame
    return frame ~= nil and frame:IsShown() == true
end
local function BankOpen() return ns.Inventory.IsBankOpen() == true end
-- Händler mit Reiter „Händler“ (im Reiter „Rückkauf“ gibt ezBag nichts weiter; selectedTab wird nur gelesen)
local function AtMerchant()
    if ns.AtMerchant() ~= true then return false end
    local tab = _G.MerchantFrame and _G.MerchantFrame.selectedTab
    return tab == nil or tab == 1
end

-- Wohin gibt Blizzards Rechtsklick gerade weiter? "merchant" | "mail" | "trade" | "bank" | nil (nichts offen)
function Stacks.Target()
    if AtMerchant() then return "merchant" end
    if MailOpen() then return "mail" end
    if TradeOpen() then return "trade" end
    if BankOpen() then return "bank" end
    return nil
end

-- Lässt sich dieser Stapel beim Händler verkaufen? (hat einen Wert, kein Schloss „nie verkaufen“)
local function Sellable(info, itemID)
    if not info or info.hasNoValue then return false end
    return not (ns.NeverSell and ns.NeverSell(itemID, info.quality))
end

-- Bindung des angeklickten Stapels (true/false) und seine Größe; nil, wenn er nicht mehr dort liegt.
local function BoundOf(entry)
    local info = type(entry.bag) == "number" and entry.slot and C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if info and info.itemID == entry.itemID then return info.isBound == true, info.stackCount or 1, info end
    return nil
end

-- Liegt der Platz noch so da (gleicher Gegenstand, nicht gesperrt, gleich gebunden)? → Info oder nil
local function Live(s, bound)
    local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
    if not (info and info.itemID == s.itemID) or info.isLocked then return nil end
    if bound ~= nil and (info.isBound == true) ~= bound then return nil end
    return info
end

-- Übrige Stapel eines zusammengefassten Platzes, die noch daliegen, frei und gleich gebunden sind wie der angeklickte
-- (bound: dessen Bindung; ohne Angabe die jetzige). forSale: nur verkäufliche (Händler).
-- → { { bag, slot, itemID, count } }
function Stacks.Rest(entry, bound, forSale)
    local list = {}
    if type(entry) ~= "table" or type(entry.merged) ~= "table" then return list end
    if bound == nil then bound = BoundOf(entry) end
    for _, e in ipairs(entry.merged) do
        if type(e.bag) == "number" and e.slot and e.itemID and not (e.bag == entry.bag and e.slot == entry.slot) then
            local info = Live(e, bound)
            if info and (not forSale or Sellable(info, e.itemID)) then
                list[#list + 1] = { bag = e.bag, slot = e.slot, itemID = e.itemID, count = info.stackCount or 1 }
            end
        end
    end
    return list
end

-- Freie Handelsplätze auf der eigenen Seite.
function Stacks.FreeTradeSlots()
    local n = 0
    for i = 1, Stacks.TRADE_SLOTS do
        if not GetTradePlayerItemLink(i) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Handel: ein Stapel je Bestätigung des Servers
---------------------------------------------------------------------------

local tradeJob   -- { list, pos, waiting, token }

local function TradeFinish(job)
    if tradeJob == job then tradeJob = nil end
end

local function TradeWait(job)
    job.waiting = true
    job.token = (job.token or 0) + 1
    local token = job.token
    C_Timer.After(Stacks.TRADE_WAIT, function()
        if tradeJob == job and job.waiting and job.token == token then TradeFinish(job) end
    end)
end

function Stacks.TradeStep()
    local job = tradeJob
    if not job or job.waiting then return end
    if not TradeOpen() then return TradeFinish(job) end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.STACKS_WHAT)
        return TradeFinish(job)
    end
    local s
    while job.pos <= #job.list do
        local c = job.list[job.pos]
        if Live(c) then
            s = c
            break
        end
        job.pos = job.pos + 1
    end
    if not s then return TradeFinish(job) end
    if Stacks.FreeTradeSlots() == 0 then
        local left = 0
        for i = job.pos, #job.list do if Live(job.list[i]) then left = left + 1 end end
        ns.Print(ns.CountText("STACKS_TRADE_FULL", left))
        return TradeFinish(job)
    end
    job.pos = job.pos + 1
    C_Container.UseContainerItem(s.bag, s.slot)
    TradeWait(job)
end

-- Stand für Prüfungen: läuft ein Handels-Durchgang, wartet er, wie viele Plätze stehen noch an?
function Stacks.TradeState()
    local job = tradeJob
    if not job then return false end
    return true, job.waiting == true, #job.list - job.pos + 1
end

ns.On("TRADE_PLAYER_ITEM_CHANGED", function()
    local job = tradeJob
    if job and job.waiting then
        job.waiting = false
        C_Timer.After(0, Stacks.TradeStep)
    end
end)
ns.On("TRADE_CLOSED", function() tradeJob = nil end)

-- now = true: ohne Blizzards eigenen Stapel davor (Strg+Rechtsklick) – gleich den ersten Stapel legen.
local function StartTrade(rest, now)
    local job = tradeJob
    if job then
        local seen = {}
        for _, s in ipairs(job.list) do seen[s.bag .. ":" .. s.slot] = true end
        for _, s in ipairs(rest) do
            if not seen[s.bag .. ":" .. s.slot] then job.list[#job.list + 1] = s end
        end
        return
    end
    job = { list = rest, pos = 1 }
    tradeJob = job
    if now then
        Stacks.TradeStep()
    else
        TradeWait(job)   -- erst Blizzards eigenen Stapel bestätigen lassen
    end
end

---------------------------------------------------------------------------
-- Post, Bank und Händler
---------------------------------------------------------------------------

local pending = setmetatable({}, { __mode = "k" })   -- [entry] = true: Nachgeben ist schon eingeplant

local function CombatText() return ezCore.CombatText(L.STACKS_WHAT) end

-- Die übrigen Stapel an Post, Bank oder Händler geben (läuft kurz nach Blizzards Klick).
-- → Zahl der Stapel, die ezBag weitergibt
function Stacks.Run(target, entry, bound)
    pending[entry] = nil
    if Stacks.Target() ~= target then return 0 end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.STACKS_WHAT)
        return 0
    end
    local rest = Stacks.Rest(entry, bound, target == "merchant")
    if #rest == 0 then return 0 end

    if target == "mail" then
        local entries = {}
        for i, s in ipairs(rest) do entries[i] = { bag = s.bag, slot = s.slot, itemID = s.itemID } end
        -- Mit ezMail: dessen Anhängen (Meldungen, Nachsenden wie beim Alt-Klick); sonst ezCores Schlange direkt
        local mailAPI = ezCore.API and ezCore.API("ezMail")
        if mailAPI and type(mailAPI.AttachEntries) == "function" then
            return mailAPI.AttachEntries(entries) and #entries or 0
        end
        local queue = ezCore.MailQueue
        if not (queue and queue.Attach) then return 0 end
        if queue.IsAttaching() or queue.IsBusy() then
            ns.Print(L.STACKS_MAIL_BUSY)
            return 0
        end
        queue.Attach(entries, function(left)
            local n = type(left) == "table" and #left or 0
            if n > 0 then ns.Print(ns.CountText("SELECT_MAIL_FULL", n)) end
        end)
        return #entries
    end

    if target == "merchant" then
        ns.Select.UseAll(rest, AtMerchant, ezCore.CombatText(L.SELL_WHAT), true)
    else
        ns.Select.UseAll(rest, BankOpen, CombatText(), true)
    end
    return #rest
end

-- Rechtsklick auf einen Platz ist durch (HookScript nach Blizzards OnClick). → true, wenn ezBag nachgibt
function Stacks.AfterClick(entry, viewKey)
    local target = Stacks.Target()
    if not target or CursorHasItem() then return false end
    if target == "merchant" and viewKey ~= nil and viewKey ~= "bag" then return false end   -- verkauft wird aus der Tasche
    local bound, _, info = BoundOf(entry)
    -- Händler: Was Blizzard am angeklickten Stapel nicht verkaufen soll (Schloss, ohne Wert), verkauft ezBag auch nicht
    if target == "merchant" and info and not Sellable(info, entry.itemID) then return false end
    local rest = Stacks.Rest(entry, bound, target == "merchant")
    if #rest == 0 then return false end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.STACKS_WHAT)
        return false
    end
    if target == "trade" then
        StartTrade(rest)
        return true
    end
    if pending[entry] then return true end   -- zweiter Klick, bevor der erste nachgegeben hat
    pending[entry] = true
    C_Timer.After(Stacks.START_DELAY, function() Stacks.Run(target, entry, bound) end)
    return true
end

---------------------------------------------------------------------------
-- Anzahl weitergeben (Umschalt+ oder Strg+Rechtsklick): ezBags eigenes Feld bis zur Gesamtzahl
---------------------------------------------------------------------------

-- Fenster, in die man eine Anzahl am Mauszeiger zieht (Gildenbank, Auktionshaus): Ist eines offen, bleibt ohne Ziel
-- Blizzards Anzahl-Fenster (Review 22.11.2026)
local DROP_FRAMES = { "GuildBankFrame", "AuctionHouseFrame", "AuctionFrame" }
local function DropFrameOpen()
    for _, name in ipairs(DROP_FRAMES) do
        local frame = rawget(_G, name)
        if frame and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

-- Ziel einer Anzahl in einer Ansicht: aus der Tasche jedes offene Ziel (Händler, Post, Handel, Bank), ohne offenes
-- Ziel "none" (Anzahl an den Mauszeiger; nicht bei offener Gildenbank oder offenem Auktionshaus); aus der
-- Bankansicht "bag" (in die Tasche). → Ziel oder nil
function Stacks.SplitTarget(viewKey)
    local target = Stacks.Target()
    if viewKey == "bank" then return target == "bank" and "bag" or nil end
    if viewKey == "bag" then
        if target then return target end
        if DropFrameOpen() then return nil end
        return "none"
    end
    return nil
end

-- Ist das Ziel noch offen? ("bag": Bank → Tasche, solange die Bank offen ist; "none": immer)
local function StillOpen(target)
    if target == "bag" then return BankOpen() end
    if target == "none" then return true end
    return Stacks.Target() == target
end

-- Sind mindestens need Anhangplätze frei? ezCores Versand-Schlange zählt (eine Stelle, Leitlinie 2)
local function MailHasRoom(need)
    local queue = ezCore.MailQueue
    return queue ~= nil and type(queue.FreeSendSlots) == "function" and #queue.FreeSendSlots() >= (need or 1)
end

local function IsDressable(itemID)
    return C_Item ~= nil and type(C_Item.IsDressableItemByID) == "function" and C_Item.IsDressableItemByID(itemID) == true
end

-- Wann und für wen Blizzard sein Anzahl-Fenster zuletzt geöffnet hat (hooksecurefunc an
-- StackSplitFrame:OpenStackSplitFrame, nur mitgehört). Review 21.11.2026: Nicht jeder Umschalt+Rechtsklick öffnet es –
-- bei Stapeln mit Beute (Umschalt ist dort Blizzards Selbst-Plündern), einem Link in den Chat oder einem gesperrten
-- Stapel bleibt ein schon offenes Fenster (z. B. von einem Umschalt+Linksklick davor) einfach stehen.
local opened   -- { owner, time }

function Stacks.OnSplitOpened(parent)
    opened = { owner = parent, time = GetTime() }
    -- Blizzards Teil-Fenster geht auf: ezBags Feld zu, sonst landeten Ziffern und Enter im falschen Fenster (Review
    -- 22.11.2026); die Übernahme per Umschalt+Rechtsklick öffnet ezBags Feld danach neu
    if Stacks.FieldCancel then Stacks.FieldCancel() end
end

local splitFrame = rawget(_G, "StackSplitFrame")   -- Blizzards Anzahl-Fenster (beim Laden schon da)
if splitFrame and type(splitFrame.OpenStackSplitFrame) == "function" then
    hooksecurefunc(splitFrame, "OpenStackSplitFrame", function(_, _, parent) Stacks.OnSplitOpened(parent) end)
end

-- Blizzards Anzahl-Fenster, wenn Blizzard es bei genau diesem Klick für diesen Knopf geöffnet hat (gleicher Bildaufbau,
-- noch offen). → Fenster oder nil
local function SplitOpenedFor(button)
    local split = rawget(_G, "StackSplitFrame")
    if not (split ~= nil and split:IsShown() and split.owner == button) then return nil end
    if not (opened and opened.owner == button and opened.time == GetTime()) then return nil end
    return split
end

-- Gamepad-Oberfläche: Blizzards Fenster meldet sich dort beim Steuerungs-Verwalter ab; das soll nicht aus ezBag laufen
local function GamepadUI()
    return InputUtil ~= nil and type(InputUtil.IsGamepadUIEnabled) == "function" and InputUtil.IsGamepadUIEnabled() == true
end

-- Für Layout.lua und Bank.lua: Klick auf Blizzards Platz-Knopf einer Ansicht (nach Blizzards OnClick).
--   Rechtsklick ohne Zusatztaste  zusammengefasste Stapel ganz weitergeben
--   Umschalt+Rechtsklick          Blizzards Anzahl-Fenster schließen, ezBags Feld bis zur Gesamtzahl
--   Strg+Rechtsklick              dasselbe Feld direkt
function Stacks.OnItemClick(view, button, mouse)
    if mouse ~= "RightButton" or IsAltKeyDown() then return false end
    local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
    if ctrl and shift then return false end
    if not view or ns.Select.IsActive(view) then return false end
    local entry = view.byButton and view.byButton[button]
    if not (entry and entry.button == button) then return false end
    if shift then return Stacks.TakeOverSplit(entry, button, view.viewKey) end
    if ctrl then
        if IsDressable(entry.itemID) then return false end   -- Strg+Klick ist dort Blizzards Anprobe
        return Stacks.AskAmount(entry, view.viewKey)
    end
    if not entry.merged then return false end
    return Stacks.AfterClick(entry, view.viewKey)
end

---------------------------------------------------------------------------
-- Das Feld: Stapel sammeln, Anzahl verteilen, abteilen und weitergeben
---------------------------------------------------------------------------

-- Stapel des Platzes, die jetzt weitergehen können (der vordere und die übrigen, gleich gebunden, frei), kleinste
-- zuerst. → Liste oder nil (Platz nicht mehr da, gesperrt, beim Händler unverkäuflich, gebunden an Post oder Handel)
function Stacks.AllStacks(entry, target)
    local bound, count, info = BoundOf(entry)
    if bound == nil or info.isLocked then return nil end
    local forSale = target == "merchant"
    if forSale and not Sellable(info, entry.itemID) then return nil end
    if (target == "mail" or target == "trade") and bound then return nil end
    local list = { { bag = entry.bag, slot = entry.slot, itemID = entry.itemID, count = count } }
    for _, s in ipairs(Stacks.Rest(entry, bound, forSale)) do list[#list + 1] = s end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count < b.count end
        return a.bag * 1000 + a.slot < b.bag * 1000 + b.slot
    end)
    return list
end

-- Zielgrößen für n Stück bei Stapelgröße max: so viele volle Stapel wie nötig, dann der Rest. → { max, …, rest }
function Stacks.Targets(n, max)
    local out = {}
    max = math.max(1, math.floor(max or 1))
    while n > max do
        out[#out + 1] = max
        n = n - max
    end
    if n > 0 then out[#out + 1] = n end
    return out
end

-- Liegt der Stapel s noch da? → Anzahl, gesperrt (nil, wenn nicht)
local function Count(s)
    local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
    if not (info and info.itemID == s.itemID) then return nil end
    return info.stackCount or 1, info.isLocked == true
end

local buildJob   -- { sources, targets, ti, base, built, expect, waited, used, target, itemID, done, ticker }

function Stacks.Building() return buildJob ~= nil end

local function BuildFinish(job, why)
    if buildJob == job then buildJob = nil end
    if job.ticker then job.ticker:Cancel() end
    if why == true then return job.done(job.built) end
    if why then ns.Print(why) end
end

-- Warten auf den Server; nach SPLIT_WAIT je Schritt gibt ezBag auf
local function BuildWait(job)
    job.waited = job.waited + Stacks.SPLIT_STEP
    if job.waited > Stacks.SPLIT_WAIT then BuildFinish(job, L.STACKS_BUILD_FAILED) end
end

-- Einen Stapel (ganz, oder n davon) auf den Platz to legen; to leer oder mit demselben Gegenstand. → true, wenn bewegt
local function Move(from, to, n)
    if n then
        if not pcall(C_Container.SplitContainerItem, from.bag, from.slot, n) then return false end
    else
        C_Container.PickupContainerItem(from.bag, from.slot)
    end
    if not CursorHasItem() then return false end
    C_Container.PickupContainerItem(to.bag, to.slot)
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

-- Ein Schritt: erst warten, bis der letzte angekommen ist, dann die nächste Zielgröße bauen.
function Stacks.BuildStep()
    local job = buildJob
    if not job then return end
    if not StillOpen(job.target) then return BuildFinish(job, L.STACKS_ASK_GONE) end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.STACKS_WHAT)
        return BuildFinish(job)
    end
    if CursorHasItem() then return BuildWait(job) end
    if job.expect then
        local c, locked = Count(job.expect)
        if c ~= job.expect.count or locked then return BuildWait(job) end
        job.expect = nil
    end
    -- die übrigen Stapel, wie sie jetzt liegen (gesperrt: noch unterwegs – warten)
    local src = {}
    for _, q in ipairs(job.sources) do
        local c, locked = Count(q)
        if c then
            if locked then return BuildWait(job) end
            q.count = c
            src[#src + 1] = q
        end
    end
    job.sources = src
    job.waited = 0

    local want = job.targets[job.ti]
    if not want then return BuildFinish(job, true) end
    local base = job.base
    if base then
        local have = Count(base)
        if have then
            base.fresh = nil                           -- die erste Lieferung ist da
        elseif base.fresh and C_Container.GetContainerItemInfo(base.bag, base.slot) == nil then
            have = 0                                   -- neuer, noch leerer Platz
        end
        if not have or have > want then return BuildFinish(job, L.STACKS_BUILD_FAILED) end
        if have == want then
            job.built[#job.built + 1] = { bag = base.bag, slot = base.slot, itemID = job.itemID, count = have,
                inBag = base.inBag }
            job.base, job.ti = nil, job.ti + 1
            return
        end
        local need = want - have
        local pick, split
        for _, q in ipairs(src) do   -- ein ganzer Stapel, der passt (der größte)
            if q.count <= need and (not pick or q.count > pick.count) then pick = q end
        end
        if not pick then             -- sonst vom kleinsten, der größer ist, abteilen
            for _, q in ipairs(src) do
                if q.count > need and (not pick or q.count < pick.count) then pick = q end
            end
            split = need
        end
        if not pick then return BuildFinish(job, L.STACKS_BUILD_FAILED) end
        if not Move(pick, base, split) then return BuildFinish(job, L.STACKS_BUILD_FAILED) end
        job.expect = { bag = base.bag, slot = base.slot, itemID = job.itemID, count = have + (split or pick.count) }
        return
    end
    -- neue Zielgröße: ein Stapel genau so groß, sonst der größte kleinere als Grundlage, sonst ein freier Taschenplatz
    -- (ohne Ziel kommt es nur zum freien Platz, wenn PassAmount allein den kleinsten Stapel übergibt, der reicht)
    local exact, smaller, bigger
    for _, q in ipairs(src) do
        if q.count == want and not exact then exact = q end
        if q.count < want and (not smaller or q.count > smaller.count) then smaller = q end
        if q.count > want and (not bigger or q.count < bigger.count) then bigger = q end
    end
    local function Take(q)
        for k, x in ipairs(job.sources) do
            if x == q then table.remove(job.sources, k) break end
        end
    end
    if exact then
        Take(exact)
        job.built[#job.built + 1] = { bag = exact.bag, slot = exact.slot, itemID = job.itemID, count = want,
            inBag = exact.inBag }
        job.ti = job.ti + 1
        return
    end
    if smaller then
        Take(smaller)
        job.base = smaller
        return Stacks.BuildStep()
    end
    if not (smaller or bigger) then return BuildFinish(job, L.STACKS_BUILD_FAILED) end
    local eBag, eSlot = ezCore.EmptyBagSlot(job.used)
    if not eBag then return BuildFinish(job, L.STACKS_BUILD_NO_SPACE) end
    job.used[eBag * 1000 + eSlot] = true
    job.base = { bag = eBag, slot = eSlot, itemID = job.itemID, inBag = true, fresh = true }
    return Stacks.BuildStep()
end

-- Zusammenlegen starten: list (Stapel aus Stacks.AllStacks), targets (Stacks.Targets), done(fertige Stapel).
local function StartBuild(list, targets, target, itemID, inBag, done)
    local sources = {}
    for k, q in ipairs(list) do
        sources[k] = { bag = q.bag, slot = q.slot, itemID = q.itemID, count = q.count, inBag = inBag }
    end
    local job = { sources = sources, targets = targets, ti = 1, built = {}, waited = 0, used = {}, target = target,
        itemID = itemID, done = done }
    buildJob = job
    Stacks.BuildStep()
    if buildJob == job then job.ticker = C_Timer.NewTicker(Stacks.SPLIT_STEP, Stacks.BuildStep) end
end

-- Die fertigen Stapel weitergeben wie Blizzards Rechtsklick (bzw. an der Post über ezMail oder ezCores Schlange).
local function PassBuilt(target, built)
    if #built == 0 then return end
    if target == "none" then
        -- ohne Ziel: der zusammengelegte Stapel an den Mauszeiger, wie Blizzards Abteilen
        if #built == 1 and not CursorHasItem() then C_Container.PickupContainerItem(built[1].bag, built[1].slot) end
        if not CursorHasItem() then ns.Print(L.STACKS_HAND_LEFT) end
        return
    end
    if target == "mail" then
        local entries = {}
        for k, q in ipairs(built) do entries[k] = { bag = q.bag, slot = q.slot, itemID = q.itemID, count = q.count } end
        local mailAPI = ezCore.API and ezCore.API("ezMail")
        if mailAPI and type(mailAPI.AttachEntries) == "function" then
            mailAPI.AttachEntries(entries)
            return
        end
        local queue = ezCore.MailQueue
        if not (queue and queue.Attach) then return end
        if queue.IsAttaching() or queue.IsBusy() then return ns.Print(L.STACKS_MAIL_BUSY) end
        queue.Attach(entries, function(left)
            local k = type(left) == "table" and #left or 0
            if k > 0 then ns.Print(ns.CountText("SELECT_MAIL_FULL", k)) end
        end)
    elseif target == "trade" then
        StartTrade(built, true)
    elseif target == "bag" then
        -- Bank → Tasche: was in der Bank zusammengelegt wurde, wie Blizzards Rechtsklick; ein abgeteilter Stapel liegt
        -- schon in der Tasche
        local list = {}
        for _, q in ipairs(built) do if not q.inBag then list[#list + 1] = q end end
        if #list > 0 then ns.Select.UseAll(list, BankOpen, CombatText(), true) end
    elseif target == "merchant" then
        ns.Select.UseAll(built, AtMerchant, ezCore.CombatText(L.SELL_WHAT), true)
    else
        ns.Select.UseAll(built, BankOpen, CombatText(), true)
    end
end

-- Die gewählte Anzahl zusammenlegen und weitergeben. wanted: das Ziel, für das gefragt wurde (wechselt das Fenster bis
-- „Annehmen“, gibt ezBag nichts weiter). → Zahl der Stücke, die ezBag zusammenlegt (0: nichts)
function Stacks.PassAmount(entry, viewKey, n, wanted)
    local target = Stacks.SplitTarget(viewKey)
    if type(n) ~= "number" or n < 1 then return 0 end
    if not target or (wanted ~= nil and target ~= wanted) then
        ns.Print(L.STACKS_ASK_GONE)
        return 0
    end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.STACKS_WHAT)
        return 0
    end
    if buildJob then
        ns.Print(L.STACKS_BUILD_BUSY)
        return 0
    end
    local list = Stacks.AllStacks(entry, target)
    if not list then
        ns.Print(L.STACKS_ASK_GONE)
        return 0
    end
    local total, largest = 0, 1
    for _, q in ipairs(list) do
        total = total + q.count
        if q.count > largest then largest = q.count end
    end
    local max = ezCore.MaxStack(entry.itemID, largest)
    local sum = math.min(n, total)
    if target == "none" then
        -- ohne Ziel an den Mauszeiger (Spielbefund vom 22.11.2026: „in der tasche muss das geteilte in der hand
        -- bleiben“): höchstens ein Stapel, und zwar ein echter. Blizzards Abteilen hängt nur eine Anzahl an den
        -- Mauszeiger, die noch am alten Platz liegt – mit ihr einen Spieler anhandeln legte den ganzen Stapel in den
        -- Handel (Spielbefund vom 22.11.2026: „wenn ich aber teile und diesen stack zu anhandeln nehme, dann ist es der
        -- komplette stack anstatt den 11“). Darum: ein Stapel genau so groß → aufnehmen; sonst die Anzahl erst auf
        -- einen freien Platz abteilen (oder auf einem vorhandenen Stapel zusammenlegen) und den dann aufnehmen. Nur ohne
        -- freien Platz und ohne kleineren Stapel bleibt Blizzards Abteilen.
        sum = math.min(sum, max)
        if CursorHasItem() then return 0 end
        if sum < n then ns.Print(L.STACKS_ASK_LESS:format(sum)) end
        local best, smaller
        for _, q in ipairs(list) do
            if q.count >= sum and (not best or q.count < best.count) then best = q end
            if q.count < sum then smaller = q end
        end
        if best and best.count == sum then
            C_Container.PickupContainerItem(best.bag, best.slot)
            if CursorHasItem() then return sum end
            ns.Print(L.STACKS_ASK_GONE)
            return 0
        end
        if best and ezCore.EmptyBagSlot() then
            -- nur vom kleinsten Stapel, der reicht, auf einen freien Platz abteilen (ein Schritt)
            list = { best }
        elseif best and not smaller then
            pcall(C_Container.SplitContainerItem, best.bag, best.slot, sum)
            if CursorHasItem() then return sum end
            ns.Print(L.STACKS_ASK_GONE)
            return 0
        end
    end
    local targets = Stacks.Targets(sum, max)

    -- Vorab: genug Anhang- bzw. Handelsplätze – sonst gar nichts
    if target == "mail" and not MailHasRoom(#targets) then
        ns.Print(L.STACKS_SPLIT_MAIL_FULL)
        return 0
    end
    local queue = ezCore.MailQueue
    if target == "mail" and queue and (queue.IsAttaching() or queue.IsBusy()) then
        ns.Print(L.STACKS_MAIL_BUSY)
        return 0
    end
    if target == "trade" and Stacks.FreeTradeSlots() < #targets then
        ns.Print(L.STACKS_SPLIT_TRADE_FULL)
        return 0
    end
    if sum < n and target ~= "none" then ns.Print(L.STACKS_ASK_LESS:format(sum)) end
    StartBuild(list, targets, target, entry.itemID, target ~= "bag", function(built) PassBuilt(target, built) end)
    return sum
end

-- Stapel und Gesamtzahl für das Feld (zusammen mindestens 2 Stück). → list, total oder nil
local function Askable(entry, target)
    local list = Stacks.AllStacks(entry, target)
    if not list then return nil end
    local total = 0
    for _, s in ipairs(list) do total = total + s.count end
    if total < 2 then return nil end
    -- ohne Ziel nur für Stapelbares und höchstens ein Stapel (mehr passt nicht an den Mauszeiger)
    if target == "none" then
        local max = ezCore.MaxStack(entry.itemID, 1)
        if max < 2 then return nil end
        total = math.min(total, max)
    end
    return list, total
end

---------------------------------------------------------------------------
-- Das Anzahl-Feld: so groß und an derselben Stelle wie Blizzards Teil-Fenster (StackSplitFrame). Wünsche des Nutzers
-- vom 22.11.2026, wörtlich: „das fenster zum teilen sollte dort landen wie das originale, an dessen position“, „das
-- ezbag anzahl-feld landet an der selben psotion wie das originale blizz geld“ und „unser exbag feld kann auch so groß
-- sein wie das originale“. Aus Blizzards Teilen nachgebaut (Maße und Lage aus StackSplitFrame.xml und
-- ContainerFrameItemButtonMixin/BankPanelItemButtonMixin:OnModifiedClick, Zweig forever): Hintergrund
-- Interface\MoneyFrame\UI-MoneyFrame, Pfeile Interface\MoneyFrame\Arrow-*, „OK“/„Abbrechen“ aus UIPanelButtonTemplate.
-- Eigener Rahmen (Leitlinie 1: Liste FENSTER in tools/lint.lua – Aufklappteil am Taschen- bzw. Bankknopf, schließt mit
-- ihm, im Kampf und mit Esc). Die Zahl lässt sich tippen (Enter = „OK“) und mit den Pfeilen ändern, höchstens bis max.
---------------------------------------------------------------------------

Stacks.FIELD_W, Stacks.FIELD_H = 172, 96

-- Lage wie Blizzards Teil-Fenster: in der Tasche rechtsbündig über dem Platz ("BOTTOMRIGHT" an "TOPRIGHT"), in der
-- Bank linksbündig ("BOTTOMLEFT" an "TOPLEFT"). → { Knopf, Punkt, Bezugspunkt } oder nil
function Stacks.FieldAnchor(button, viewKey)
    if not button then return nil end
    if viewKey == "bank" then return { button, "BOTTOMLEFT", "TOPLEFT" } end
    return { button, "BOTTOMRIGHT", "TOPRIGHT" }
end

local field

-- Zahl setzen (begrenzt auf 1 … max), Pfeile an- oder ausschalten; typed = true: vom Tippen (Text nicht überschreiben)
local function FieldSet(n, typed)
    local f = field
    if n < 1 then typed = false end   -- eine getippte 0 sichtbar auf 1 setzen
    n = math.max(1, math.min(f.max or 1, math.floor(n)))
    f.value = n
    if not typed then f.box:SetText(tostring(n)) end
    f.left:SetEnabled(n > 1)
    f.right:SetEnabled(n < (f.max or 1))
end

function Stacks.FieldCancel()
    if field then field:Hide() end
end

-- „OK“ bzw. Enter: Feld zu, dann die Zahl weitergeben
function Stacks.FieldAccept()
    local f = field
    if not (f and f:IsShown()) then return end
    if not f.value then return end   -- leeres Feld: offen lassen
    local n, cb = f.value, f.cb
    f:Hide()
    if cb and n and n >= 1 then cb(n) end
end

local function NewField()
    local f = CreateFrame("Frame", "ezBagAmountField", UIParent)
    f:SetSize(Stacks.FIELD_W, Stacks.FIELD_H)
    f:SetFrameStrata("DIALOG")   -- wie Blizzards StackSplitFrame
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\MoneyFrame\\UI-MoneyFrame")
    bg:SetTexCoord(0, 0.671875, 0, 0.75)
    bg:SetAllPoints()

    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(80, 20)
    box:SetPoint("RIGHT", f, "RIGHT", -50, 18)
    box:SetFontObject(GameFontHighlight)
    box:SetJustifyH("RIGHT")
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(5)
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local n = tonumber(self:GetText())
        if not n then
            f.value = nil
            return
        end
        if n > (f.max or 1) then FieldSet(f.max) else FieldSet(n, true) end
    end)
    box:SetScript("OnEnterPressed", Stacks.FieldAccept)
    box:SetScript("OnEscapePressed", Stacks.FieldCancel)
    f.box = box

    local function Arrow(side, x, step)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(16, 16)
        if side == "Left" then b:SetPoint("RIGHT", f, "CENTER", x, 18) else b:SetPoint("LEFT", f, "CENTER", x, 18) end
        b:SetNormalTexture("Interface\\MoneyFrame\\Arrow-" .. side .. "-Up")
        b:SetPushedTexture("Interface\\MoneyFrame\\Arrow-" .. side .. "-Down")
        b:SetDisabledTexture("Interface\\MoneyFrame\\Arrow-" .. side .. "-Disabled")
        b:SetScript("OnClick", function() FieldSet((f.value or 1) + step) end)
        return b
    end
    f.left = Arrow("Left", -59, -1)
    f.right = Arrow("Right", 64, 1)

    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetSize(64, 24)
    ok:SetPoint("RIGHT", f, "BOTTOM", -3, 32)
    ok:SetText(OKAY or "OK")
    ok:SetScript("OnClick", Stacks.FieldAccept)
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(64, 24)
    cancel:SetPoint("LEFT", f, "BOTTOM", 5, 32)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", Stacks.FieldCancel)
    f.ok, f.cancel = ok, cancel

    -- Die Frage („Wie viele … verkaufen? (1 bis 24)“) steht als Tooltip über dem Feld, solange es offen ist – sonst sähe
    -- es aus wie Blizzards harmloses Teil-Fenster, obwohl „Okay“ verkauft oder verschickt (Leitlinien 3 und 11; Review
    -- 22.11.2026). Kommt die Maus und geht wieder, zeigt das Feld sie erneut.
    for _, region in ipairs({ f, box, ok, cancel, f.left, f.right }) do
        region:SetScript("OnEnter", function() Stacks.ShowFieldPrompt() end)
        region:SetScript("OnLeave", function() Stacks.ShowFieldPrompt() end)
    end
    -- schließt mit dem Platz (Tasche zu), im Kampf und nach Ablauf
    f:SetScript("OnUpdate", function(self)
        if InCombatLockdown() or not (self.anchor and self.anchor:IsVisible()) then self:Hide() end
    end)
    f:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        self.cb, self.anchor, self.prompt = nil, nil, nil
        self.box:ClearFocus()
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ezBagAmountField") end   -- Esc schließt
    return f
end

-- Das Feld öffnen: prompt (Tooltip), Vorschlag current, höchstens max, cb(n) nach „OK“; anchor aus Stacks.FieldAnchor.
-- Ohne Platz-Anker fragt ezCores Rückfrage-Fenster (Core.AskNumber).
function Stacks.OpenField(prompt, current, max, cb, anchor)
    if not (anchor and anchor[1]) then
        return ezCore.AskNumber(prompt, current, 1, max, cb, function() ns.Print(L.STACKS_ASK_INVALID:format(max)) end)
    end
    field = field or NewField()
    local f = field
    f.max, f.cb, f.prompt, f.anchor = max, cb, prompt, anchor[1]
    f:ClearAllPoints()
    f:SetPoint(anchor[2], anchor[1], anchor[3], 0, 0)
    FieldSet(current or max)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    Stacks.ShowFieldPrompt()
    return f
end

function Stacks.Field() return field end

-- Die Frage des offenen Felds als Tooltip darüber
function Stacks.ShowFieldPrompt()
    local f = field
    if not (f and f:IsShown() and f.prompt) then return end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    local r, g, b = ns.TipRGB("highlight")
    GameTooltip:SetText(f.prompt, r, g, b, 1, true)
    GameTooltip:Show()
end

-- Das Feld mit der Gesamtzahl als Vorschlag. before: läuft gleich vor dem Öffnen (Umschalt+Rechtsklick schließt dort
-- Blizzards Anzahl-Fenster). → true, wenn gefragt
function Stacks.AskAmount(entry, viewKey, before)
    local target = Stacks.SplitTarget(viewKey)
    if not target then return false end
    if ns.InCombat() then
        if target ~= "none" then ezCore.CombatNotice(ns, L.STACKS_WHAT) end   -- ohne Ziel bleibt Blizzards Fenster still
        return false
    end
    if CursorHasItem() then return false end
    local _, total = Askable(entry, target)
    if not total then return false end
    if before then before() end
    local name = entry.link or entry.name or ""
    Stacks.OpenField(L["STACKS_ASK_" .. target]:format(name, total), total, total, function(n)
        Stacks.PassAmount(entry, viewKey, n, target)
    end, Stacks.FieldAnchor(entry.button, viewKey))
    return true
end

-- Umschalt+Rechtsklick (nach Blizzards OnClick): Hat Blizzard sein Anzahl-Fenster für diesen Knopf geöffnet und ist
-- ein Ziel offen (oder ohne Ziel in der Tasche), schließt ezBag es und zeigt sein Feld (Ausnahme 3 von Leitlinie 5;
-- Entscheidungen des Nutzers vom 21.11.2026 „Eigenes Feld, Ausnahme (Empfohlen)“ und vom 22.11.2026 „Ja, Feld überall
-- (Empfohlen)“). Sonst bleibt Blizzards Fenster. → true, wenn übernommen
function Stacks.TakeOverSplit(entry, button, viewKey)
    local split = SplitOpenedFor(button)
    if not split then return false end   -- Blizzard hat bei diesem Klick kein Fenster geöffnet (Stapel von 1, Beute …)
    if GamepadUI() then return false end
    return Stacks.AskAmount(entry, viewKey, function() split:Hide() end)
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

-- Zeile „Rechtsklick: alle 2 Stapel in den Brief (29 Stück)“ für einen zusammengefassten Platz: zählt nur, was ein
-- Rechtsklick jetzt weitergäbe (der angeklickte Stapel und die freien, gleich gebundenen übrigen).
function Stacks.TipText(entry, viewKey)
    local target = Stacks.Target()
    if not target then return nil end
    local bound, count, info = BoundOf(entry)
    if bound == nil then return nil end
    local forSale = target == "merchant"
    if forSale and not Sellable(info, entry.itemID) then return nil end
    local rest = Stacks.Rest(entry, bound, forSale)
    if #rest == 0 then return nil end
    local total = count
    for _, s in ipairs(rest) do total = total + s.count end
    local key = target
    if target == "bank" then key = viewKey == "bank" and "bag" or "bank" end
    return L["STACKS_TIP_" .. key]:format(ns.CountWord("STACK", #rest + 1), total)
end

-- Zeile „Umschalt-Rechtsklick: Anzahl (bis 24) wählen, „Annehmen“ verkauft sie“ (bzw. Brief, Handel, Bank, Tasche).
-- Öffnet Blizzard bei Umschalt kein Fenster (1 Stück, Beute, Gamepad-Oberfläche), nennt sie Strg-Rechtsklick.
function Stacks.SplitTipText(entry, viewKey)
    local target = Stacks.SplitTarget(viewKey)
    if not target then return nil end
    if target == "none" and ns.InCombat() then return nil end   -- dort bleibt im Kampf still Blizzards Fenster
    local _, count, info = BoundOf(entry)
    local _, total = Askable(entry, target)
    if not total then return nil end
    local key = "SHIFT"
    -- Stapel von 1 und Stapel mit Beute: Blizzard öffnet bei Umschalt kein Fenster (bzw. plündert) – Strg nennen
    if not (count and count > 1) or info.hasLoot or GamepadUI() then
        if IsDressable(entry.itemID) then return nil end
        key = "CTRL"
    end
    return ezCore.ClickText("right", key, L["STACKS_SPLIT_" .. target]:format(total))
end

function Stacks.Section(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    local view = owner and ns.Render.ViewOf(owner)
    if not (view and VIEWS[view.viewKey]) then return end
    local entry = view.byButton and view.byButton[owner]
    if not (entry and entry.itemID) then return end
    local all = entry.merged and Stacks.TipText(entry, view.viewKey)
    local split = Stacks.SplitTipText(entry, view.viewKey)
    if not (all or split) then return end
    ezCore.Tooltip.Gap(tooltip)
    local r, g, b = ns.TipRGB("hint")
    if all then tooltip:AddLine(all, r, g, b, true) end
    if split then tooltip:AddLine(split, r, g, b, true) end
end

if ezCore.Tooltip and ezCore.Tooltip.AddItemSection then
    ezCore.Tooltip.AddItemSection("ezBag.stacks", "default", Stacks.Section, "ezBag")
end
