local ADDON, ns = ...
local Core = ezCore
local L = Core.L
local Intro = Core.Intro

--[[
    Nachfrage nach einem Update (Auftrag des Nutzers vom 23.11.2026, wörtlich: „wenn wir ein update veröffentlichen
    dann muss ezcollection erneut nach der zustimmung "alle annehmen" bzw die neu dazu gekommenen teile, fragen“;
    Entscheidungen vom selben Tag: „Je Konto (Empfohlen)“, „Blase an der Minikarte (Empfohlen)“, Bestand „Alles“).

    Die Einführung (Werkzeuge/FirstStart.lua, Core.Intro) fragt das Einverständnis einmal ab: Angebot nach dem
    Einloggen, „Allem zustimmen“, Seite für Seite. Kommen mit einem Update Zeilen dazu (ein neuer Ablauf ohne Klick in
    Intro.CONSENT, eine neue Anmeldung „on“ in ns.AGREE eines Moduls), erfuhr ein Spieler, der die Einführung schon
    hatte, davon nichts. Jetzt merkt sich ezCore je Zeile, ob sie angeboten wurde – über ihre Kennung (Intro.EntryId),
    nicht über die Versionsnummer –, und fragt nach einem Update genau nach den neuen.

      * Angeboten ist eine Zeile, wenn sie im Angebot der Einführung stand (alle Zeilen von heute), in der Rückfrage von
        „Allem zustimmen“, auf einer Seite der Einführung, die der Spieler verlassen hat, oder in dieser Nachfrage, die er
        geschlossen hat. Gemerkt in ezCoreDB.intro.known (je Konto wie das Angebot der Einführung; die Einstellungen der
        Module gelten kontoweit).
      * Gefragt wird nach Zeilen, die zustimmungspflichtig sind (ab Werk nicht an), beim Spieler aus sind und hier wirken
        können (Intro.CanSwitchOn). Neue Zeilen, die schon an sind, und solche, die ab Werk an sind, aber aus (das hat der
        Spieler selbst entschieden), gelten still als angeboten – bekannte Entscheidungen bleiben unberührt (außer bei
        einem Standard-Wechsel, flip = true, unten).
      * Dazu neue Funktionen, die ab Werk an sind (Spieltest des Nutzers vom 24.11.2026, wörtlich: „ezcore hat
        neuerungen (zauberbuch) nicht erkannt“): Ursache war, dass Intro.Rows nur Intro.CONSENT und die Anmeldungen „on“
        kennt, also nur Schalter, die ab Werk aus sind – „Wo kommt was“ (ezMerchant, ab Werk an) stand in keiner Liste.
        Jedes Modul nennt sie in ns.NEWS neben ns.DEFAULTS ({ "Schlüssel", … } oder { "Schlüssel", needs = Oberschalter,
        available = fn }); die Blase zeigt sie nach den zustimmungspflichtigen mit gesetztem Häkchen und „(ab Werk an)“.
        Wer das Häkchen wegnimmt, schaltet aus; „Alle annehmen“ und „Fertig“ lassen sie, wie sie sind (außer denen mit
        accept = true, unten), und erledigen nur
        die Seiten, die zu sehen waren (weder Tooltip noch Chatzeile nennen sie). Ist der Oberschalter aus, bleibt die
        Zeile offen; hat der Spieler sie schon ausgeschaltet, gilt sie still als erledigt. Neuinstallation und Module,
        die zum ersten Mal laufen (ezCoreDB.intro.modules): Was am ersten Tag an ist, ist nicht neu (Intro.Known).
        tools/Tests/agree_test.lua ist rot, sobald ein neuer Schalter ab Werk an ist und nicht in ns.NEWS steht.
      * accept = true an einem Eintrag in ns.NEWS (Entscheidung des Nutzers vom 25.11.2026 zu ezBags Reagenzientasche, gewählt
        „Immer einschalten (Empfohlen)“): „Allem zustimmen“ und „Alle annehmen“ schalten die Funktion ein, auch wenn sie aus
        ist – nur, wenn ihr Oberschalter an ist (needs) und sie hier wirken kann. Rückfrage, Tooltip und Chatzeile nennen sie.
      * flip = true an einem Eintrag in ns.NEWS: Der Standard wechselte von aus auf an (Entscheidung des Nutzers vom
        27.11.2026 auf die Frage „Soll die Blase nach einem Update Schalter anbieten, deren Standard auf „an“ wechselte?“:
        „Ja, anbieten“). Wer das Modul schon geladen hatte, hat den alten Standard aus gespeichert (Core.FillDefaults).
        Ist die Zeile aus, bietet die Blase sie EINMAL an wie eine Zeile, die ab Werk aus ist: ohne Häkchen, „Alle
        annehmen“ schaltet sie ein, „Fertig“ lässt sie aus (row.flip). Anders als accept schalten spätere „Alle
        annehmen“ und „Allem zustimmen“ sie nicht wieder ein. Ist ihr Oberschalter aus oder wirkt sie hier nicht, bleibt
        sie offen. Eigene Kennung im Merker (Intro.EntryId hängt „#an“ an): Was vor dem Wechsel still gemerkt wurde,
        verhindert das Angebot nicht. tools/Tests/agree_test.lua verlangt flip für jeden Schalter, der zur letzten
        Veröffentlichung ab Werk aus war (tools/Tests/aus_basis.lua) und jetzt ab Werk an ist.
      * Neuinstallation: wie bisher das Angebot der Einführung. Die Nachfrage gibt es nur, wenn der Spieler die
        Einführung schon hatte (angeboten, zugestimmt oder „Nicht mehr anbieten“) und das Angebot nicht mehr kommt.
        „Nicht mehr anbieten“ lehnt nur das Angebot ab, nicht die Nachfrage (vom Nutzer am 23.11.2026 bestätigt: „OK so
        umsetzen und den offenen Punkt schließen“); abschalten lässt sie sich über „Hinweise und Angebote zeigen“.
      * Bestand: Wer die Einführung vor dieser Fassung hatte, hat noch keinen Merker. Beim ersten Mal fragt die Blase nach
        allen zustimmungspflichtigen Zeilen, die bei ihm aus sind (Entscheidung „Alles“), mit eigenem Text (bis zur
        Antwort gemerkt in ezCoreDB.intro.newsFirst); danach nur noch nach dem, was ein Update neu bringt.
      * Nach dem Einloggen (Intro.NEWS_DELAY, nach dem Angebot der Einführung), nie im Kampf (danach), nie in einer
        Instanz: EINE Blase am Addon-Fach der Minikarte (wie das Angebot) mit einem Häkchen je Zeile – Tooltip „Wenn
        an: …“ wie auf den Seiten der Einführung (Intro.FillRows) –, „Alle annehmen“ und „Fertig“. Mehr als
        Intro.NEWS_ROWS Zeilen: blättern mit „Weiter“ (die Seitenzahl steht im Kopf), „Fertig“ auf der letzten Seite.
      * „Alle annehmen“ schaltet alle Zeilen der Liste ein (alle Seiten), die Blizzards Regeln erlauben (nicht
        agree = "risk", Intro.ConsentRisk – die nennt die Blase und lässt sie nur mit Häkchen an). Was sich nicht
        einschalten ließ, bleibt offen und kommt beim nächsten Einloggen wieder (scheitert es jedes Mal, jedes Mal).
        „Fertig“ und das X lassen den Rest aus; beantwortet sind nur die Seiten, die zu sehen waren (Nachlauf zum Review
        von PR 536: erledigt ist nur Gezeigtes) – ein X auf Seite 1 von 3 lässt die Seiten 2 und 3 offen, sie kommen beim
        nächsten Einloggen. Sonst wird erst wieder nach Zeilen gefragt, die ein späteres Update bringt. Ein Kampfbeginn,
        das Schließen des Fensters, an dem die Blase hängt, oder Ausloggen ohne Klick ist keine Antwort: Die Blase kommt
        nach dem Kampf bzw. beim nächsten Einloggen wieder.
      * Knopf „Neu seit dem Update“ auf der Seite „Einführung“ (Leitlinie 3): offene Zeilen, sonst die Zeilen der letzten
        Nachfrage (ezCoreDB.intro.news) – die Blase steht dann an Blizzards Einstellungsfenster.
      * Abschaltbar wie alle Hinweise über „Hinweise und Angebote zeigen“ (OPT_optInHints); der Knopf geht immer.

      Core.Intro.Existing, Core.Intro.OfferPending   in FirstStart.lua (dieselbe Bedingung wie das Angebot)
      Core.Intro.Known()              → { [Kennung] = true } (legt den Merker an)
      Core.Intro.MarkKnown(zeilen)    → Anzahl neu als angeboten gemerkter Zeilen (Zeilen wie Intro.Rows oder Einträge)
      Core.Intro.NewsRows()           → zu fragen (neu, zustimmungspflichtig, aus, hier wirksam; danach row.on: neu und
                                         ab Werk an; row.flip: Standard auf an gewechselt, aus – vor den row.on),
                                         still erledigt (neu, aber an oder ab Werk an und ausgeschaltet)
      Core.Intro.NewsOnRows()         → Zeilen aus ns.NEWS der laufenden Module (row.on)
      Core.Intro.AcceptRows()         → Zeilen mit accept = true, die aus sind (schalten beide Knöpfe ein; row.also)
      Core.Intro.LastNewsRows()       → Zeilen der letzten Nachfrage (laufende Module)
      Core.Intro.TryNews()            → true, wenn die Blase jetzt steht; false, Grund ("off" | "db" | "new" | "offer" |
                                         "shown" | "none" | "combat" | "instance" | "target")
      Core.Intro.ShowNews(vonSeite)   Knopf „Neu seit dem Update“ → true, wenn die Blase steht
      Core.Intro.AcceptNews(zeilen)   „Alle annehmen“ → eingeschaltet, nicht gegangen
      Core.Intro.CloseNews(zeilen)    „Fertig“ und X (ohne zeilen: die gezeigten Seiten) → Anzahl, die aus bleiben
      Core.Intro.NewsBox()            → die Blase oder nil; Core.Intro.NewsPage() → Seite, Seiten
      Core.Intro.NewsRetryPending()   → true, solange die Blase nach dem Kampf wiederkommen soll
]]

Intro.NEWS_DELAY = Intro.OFFER_DELAY + 2   -- Sekunden nach dem Einloggen: nach dem Angebot der Einführung
Intro.NEWS_ROWS = 10                       -- Häkchen je Seite der Blase; mehr: „Weiter“
Intro.NEWS_BUTTON_WIDTH = 120              -- „Alle annehmen“ und „Fertig“ bzw. „Weiter“ nebeneinander
Intro.NEWS_KEY = "ezCore.introNews"        -- Core.AfterCombat: Knopf „Neu seit dem Update“ im Kampf
Intro.NEWS_ACCEPT_KEY = "ezCore.introNewsAccept"   -- Core.AfterCombat: „Alle annehmen“ im Kampf (ersetzt nichts anderes)
Intro.NEWS_HINT = "intro.news"

---------------------------------------------------------------------------
-- Merker: welche Zeilen schon angeboten wurden
---------------------------------------------------------------------------

local ModuleNs = Intro.ModuleNs

-- ns.NEWS eines laufenden Moduls als Einträge (wie in Intro.CONSENT, dazu needs und available). → Liste
local function NewsEntries(name)
    local out = {}
    local mns = name ~= ADDON and ModuleNs(name) or nil
    local list = mns and mns.NEWS
    for _, item in ipairs(type(list) == "table" and list or {}) do
        local entry = { name, type(item) == "table" and item[1] or item }
        if type(item) == "table" then
            entry.needs, entry.available, entry.accept, entry.flip = item.needs, item.available, item.accept, item.flip
        end
        if type(entry[2]) == "string" then out[#out + 1] = entry end
    end
    return out
end

-- Module, die schon einmal liefen (store.modules). Läuft eines zum ersten Mal, ist an ihm nichts „neu seit dem Update“:
-- seine NEWS gelten still als bekannt. Beim ersten Mal (alles, was heute läuft) nur gemerkt.
local function NoteModules(store)
    local first = type(store.modules) ~= "table"
    if first then store.modules = {} end
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        if not store.modules[name] and ModuleNs(name) then
            store.modules[name] = true
            if not first then
                for _, entry in ipairs(NewsEntries(name)) do store.known[Intro.EntryId(entry)] = true end
            end
        end
    end
end

-- Der Merker. Entsteht er, ehe der Spieler die Einführung hatte (Neuinstallation: erstes Angebot, „Allem zustimmen“,
-- eine Seite der Einführung), gehört alles, was heute ab Werk an ist, zum Lieferumfang und ist nicht neu.
function Intro.Known()
    local store = Intro.OfferStore()
    if not store then return nil end
    if type(store.known) ~= "table" then
        store.known = {}
        if not Intro.Existing(store) then
            for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
                for _, entry in ipairs(NewsEntries(name)) do store.known[Intro.EntryId(entry)] = true end
            end
        end
        NoteModules(store)
    end
    return store.known
end

-- Oberschalter (needs: Schlüssel oder Liste) alle an? → bool
local function NeedsOn(entry)
    local needs = entry.needs
    if needs == nil then return true end
    local mns = ModuleNs(entry[1])
    if not mns then return false end
    for _, key in ipairs(type(needs) == "table" and needs or { needs }) do
        local value = mns.S[key]
        if Core.IsSecret(value) or value ~= true then return false end
    end
    return true
end

function Intro.NewsOnRows()
    local rows, seen = {}, {}
    for _, row in ipairs(Intro.Rows(true)) do seen[Intro.EntryId(row.entry)] = true end
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        for _, entry in ipairs(NewsEntries(name)) do
            if not seen[Intro.EntryId(entry)] then
                seen[Intro.EntryId(entry)] = true
                local value = Intro.Get(entry)
                if value ~= nil and Intro.Default(entry) == true then
                    rows[#rows + 1] = { entry = entry, module = name, key = entry[2], value = value, default = true, on = true,
                        label = L.INTRO_NEWS_ON_LABEL:format(Intro.Label(entry)), what = Intro.What(entry) }
                end
            end
        end
    end
    return rows
end

-- Ab Werk an, aber ausgeschaltet, und „Allem zustimmen“/„Alle annehmen“ schalten es trotzdem ein (accept = true in
-- ns.NEWS). Nur bei eingeschaltetem Oberschalter und wo es wirken kann. → Zeilen wie Intro.Rows (row.also, row.accept: in
-- Rückfrage und Chat unter eigenem Satz, denn sie sind ab Werk an und stehen nicht auf der Seite „Einführung“)
function Intro.AcceptRows()
    local out = {}
    for _, row in ipairs(Intro.NewsOnRows()) do
        local entry = row.entry
        if entry.accept == true and row.value == false and NeedsOn(entry) and Intro.CanSwitchOn(entry) then
            out[#out + 1] = { entry = entry, module = row.module, key = row.key, value = false, default = true, also = true, accept = true,
                label = Intro.Label(entry), what = row.what }
        end
    end
    return out
end

-- Standard von aus auf an gewechselt (flip = true): aus und einschaltbar → Zeile wie eine, die ab Werk aus ist (row.flip;
-- „Alle annehmen“ schaltet sie ein, „Fertig“ lässt sie aus), sonst nil
local function OfferRow(row)
    local entry = row.entry
    if entry.flip == true and row.value == false and NeedsOn(entry) and Intro.CanSwitchOn(entry) then
        return { entry = entry, module = row.module, key = row.key, value = false, default = true, flip = true,
            label = Intro.Label(entry), what = row.what }
    end
end

function Intro.MarkKnown(rows)
    local known = Intro.Known()
    if not known or type(rows) ~= "table" then return 0 end
    local n = 0
    for _, row in ipairs(rows) do
        local entry = type(row) == "table" and (row.entry or row) or nil
        if type(entry) == "table" and type(entry[1]) == "string" and type(entry[2]) == "string" then
            local id = Intro.EntryId(entry)
            if not known[id] then
                known[id] = true
                n = n + 1
            end
        end
    end
    return n
end

function Intro.NewsRows()
    local ask, settled = {}, {}
    local known = Intro.Known()
    if not known then return ask, settled end
    NoteModules(Intro.OfferStore())
    for _, row in ipairs(Intro.Rows(true)) do
        if not known[Intro.EntryId(row.entry)] then
            if row.value == true or (row.value == false and row.default == true) then
                -- an, oder ab Werk an und selbst ausgeschaltet: nichts zu entscheiden
                settled[#settled + 1] = row
            elseif row.value == false and Intro.CanSwitchOn(row.entry) then
                ask[#ask + 1] = row
            end
        end
    end
    local on = {}
    for _, row in ipairs(Intro.NewsOnRows()) do
        if not known[Intro.EntryId(row.entry)] then
            local offer = OfferRow(row)
            if offer then
                ask[#ask + 1] = offer         -- Standard auf an gewechselt, aus: anbieten (vor den Zeilen „ab Werk an“)
            elseif row.value == false then
                -- schon selbst ausgeschaltet; ein Standard-Wechsel mit ausgeschaltetem Oberschalter bleibt offen
                if row.entry.flip ~= true then settled[#settled + 1] = row end
            elseif NeedsOn(row.entry) and Intro.CanSwitchOn(row.entry) then
                on[#on + 1] = row
            end
        end
    end
    for _, row in ipairs(on) do ask[#ask + 1] = row end
    return ask, settled
end

function Intro.LastNewsRows()
    local out = {}
    local store = Intro.OfferStore()
    local ids = store and store.news
    if type(ids) ~= "table" then return out end
    local byId = {}
    for _, row in ipairs(Intro.Rows(true)) do byId[Intro.EntryId(row.entry)] = row end
    for _, row in ipairs(Intro.NewsOnRows()) do byId[Intro.EntryId(row.entry)] = OfferRow(row) or row end
    for _, id in ipairs(ids) do
        if type(id) == "string" and byId[id] then out[#out + 1] = byId[id] end
    end
    return out
end

---------------------------------------------------------------------------
-- Blase
---------------------------------------------------------------------------

local newsHints
local function NewsHints()
    if not newsHints then newsHints = Core.NewHints(function() return {} end, L.INTRO_NEWS_ALL) end
    return newsHints
end

-- Stand der Blase: Zeilen, Seite, höchste gezeigte Seite (seen), Ziel, Lage; pending: neue Zeilen; first: erstes Mal
-- ohne Merker (Bestand)
local open = { rows = nil, page = 1, seen = 0 }

function Intro.NewsBox()
    local box = newsHints and newsHints.Box(Intro.NEWS_HINT)
    if box and box:IsShown() then return box end
    return nil
end

local function Pages()
    return math.max(1, math.ceil(#(open.rows or {}) / Intro.NEWS_ROWS))
end

function Intro.NewsPage()
    return open.page, Pages()
end

local function Line(row) return L.INTRO_AGREE_LINE:format(row.module, row.label) end

-- Zeilen, die „Alle annehmen“ auslässt (agree = "risk"), und solche, die es einschaltet; was ab Werk an ist (row.on),
-- fasst es nicht an. → Namen riskant, Namen sonst, Anzahl ab Werk an
local function Split(rows)
    local risk, plain, on = {}, {}, 0
    for _, row in ipairs(rows or {}) do
        if row.on then
            on = on + 1
        elseif Intro.ConsentRisk(row.entry) then
            risk[#risk + 1] = Line(row)
        else
            plain[#plain + 1] = Line(row)
        end
    end
    return risk, plain, on
end

local function AcceptTip()
    local risk, plain, on = Split(open.rows)
    for _, row in ipairs(Intro.AcceptRows()) do plain[#plain + 1] = Line(row) end
    local text
    if #plain == 0 and on > 0 then
        text = L.INTRO_NEWS_ALL_KEEP
    else
        text = L.INTRO_NEWS_ALL_TIP:format(#plain > 0 and table.concat(plain, "\n") or "–")
        if on > 0 then text = text .. "\n\n" .. L.INTRO_NEWS_ALL_ON end
    end
    if #risk > 0 then text = text .. "\n\n" .. L.INTRO_NEWS_RISK:format(table.concat(risk, ", ")) end
    return text
end

local function NewsText()
    local rows, pages = open.rows or {}, Pages()
    local head = Core.Gold(L.INTRO_NEWS_HEAD)
    if pages > 1 then head = head .. " " .. L.INTRO_PAGE_COUNT:format(open.page, pages) end
    local risk, _, on = Split(rows)
    local ask, parts = #rows - on, {}
    if not open.pending then
        parts[1] = L.INTRO_NEWS_AGAIN
    else
        if ask > 0 then parts[1] = (open.first and L.INTRO_NEWS_FIRST or L.INTRO_NEWS):format(ask) end
        if on > 0 then parts[#parts + 1] = L.INTRO_NEWS_ON:format(on) end
    end
    local text = head .. "\n\n" .. table.concat(parts, "\n\n")
    if #risk > 0 then text = text .. "\n\n" .. L.INTRO_NEWS_RISK:format(table.concat(risk, ", ")) end
    return text
end

local Render

-- „Alle annehmen“ (Blizzards Knopf der Blase) und „Weiter“ bzw. „Fertig“ nebeneinander, das X wie „Fertig“ (einmal je
-- Blase)
local function DecorateNews(box)
    if box.ezNewsDone then return end
    if type(box.SetClampedToScreen) == "function" then box:SetClampedToScreen(true) end
    local done = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    done:SetSize(Intro.NEWS_BUTTON_WIDTH, 22)
    done:SetPoint("BOTTOMLEFT", box, "BOTTOM", 2, 12)
    done:SetText(L.INTRO_NEWS_CLOSE)
    done:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if open.page < Pages() then
            open.page = open.page + 1
            Render()
            return
        end
        box:Hide()
        Intro.CloseNews()
    end)
    done:SetScript("OnEnter", function(self)
        if open.page < Pages() then
            Core.ShowTip(self, L.INTRO_NEXT, L.INTRO_NEWS_NEXT_TIP, "ANCHOR_BOTTOM")
        else
            Core.ShowTip(self, L.INTRO_NEWS_CLOSE, L.INTRO_NEWS_CLOSE_TIP, "ANCHOR_BOTTOM")
        end
    end)
    done:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    box.ezNewsDone = done
    local okay = box.OkayButton
    if okay then
        okay:SetSize(Intro.NEWS_BUTTON_WIDTH, 22)
        okay:ClearAllPoints()
        okay:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -2, 12)
        -- Blizzards Teil (NewHints) blendet die Blase aus; danach einschalten
        okay:HookScript("OnClick", function() Intro.AcceptNews() end)
        okay:SetScript("OnEnter", function(self) Core.ShowTip(self, L.INTRO_NEWS_ALL, AcceptTip(), "ANCHOR_BOTTOM") end)
        okay:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    if box.CloseButton then box.CloseButton:HookScript("OnClick", function() Intro.CloseNews() end) end
end

-- Die offene Seite zeigen: Text, Häkchen dieser Seite, „Weiter“ oder „Fertig“. → Blase oder nil
Render = function()
    local rows, size = open.rows or {}, Intro.NEWS_ROWS
    local chunk = {}
    for i = (open.page - 1) * size + 1, math.min(#rows, open.page * size) do
        chunk[#chunk + 1] = rows[i]
        rows[i].shown = true       -- „Alle annehmen“ erledigt ab Werk Eingeschaltetes nur, wenn es zu sehen war
    end
    local box = NewsHints().Show(Intro.NEWS_HINT, open.target, open.target, NewsText(), open.side)
    if not box then return nil end
    DecorateNews(box)
    Intro.FillRows(box, nil, chunk)
    box.ezNewsDone:SetText(open.page < Pages() and L.INTRO_NEXT or L.INTRO_NEWS_CLOSE)
    if open.page > open.seen then open.seen = open.page end
    return box
end

-- Geht das Fenster zu, an dem die Blase hängt (Esc am Einstellungsfenster), geht sie mit – ohne Antwort, nichts gemerkt
-- (sonst bliebe sie mittelbar verborgen und erschiene beim nächsten Öffnen mit altem Stand). Einmal je Rahmen, nur
-- HookScript (Leitlinie 5).
local hookedTargets = setmetatable({}, { __mode = "k" })
local function HookTargetHide(target)
    if hookedTargets[target] or type(target.HookScript) ~= "function" then return end
    hookedTargets[target] = true
    target:HookScript("OnHide", function(self)
        if open.target == self and Intro.NewsBox() then
            newsHints.Hide(Intro.NEWS_HINT)
            open.rows = nil
        end
    end)
end

-- pending: offene Zeilen (ihre Kennungen werden die „letzte Nachfrage“); sonst die Zeilen der letzten Nachfrage
local function ShowBox(rows, target, side, pending, first)
    open.rows, open.page, open.seen, open.target, open.side = rows, 1, 0, target, side
    open.pending, open.first = pending, first
    if not Render() then
        open.rows = nil
        return false
    end
    HookTargetHide(target)
    if pending then
        local store = Intro.OfferStore()
        if store then
            local ids = {}
            for _, row in ipairs(rows) do ids[#ids + 1] = Intro.EntryId(row.entry) end
            store.news = ids
        end
    end
    return true
end

-- Erstes Mal ohne Merker (Bestand vor dieser Fassung): nur aus der Nachfrage selbst (Intro.TryNews, nur Bestand) und
-- vor Intro.NewsRows, das den Merker anlegt; gemerkt in ezCoreDB.intro.newsFirst bis zur Antwort (ein Kampf oder eine
-- Instanz verschiebt die Blase nur) oder bis nichts mehr offen ist. → bool
local function FirstTime(store)
    if type(store.known) ~= "table" then store.newsFirst = true end
    return store.newsFirst == true
end

local function Answered()
    local store = Intro.OfferStore()
    if store then store.newsFirst = nil end
end

-- Nach dem Kampf noch einmal versuchen: ein Merker und PLAYER_REGEN_ENABLED – nicht Core.AfterCombat, denn beim
-- Ereignis PLAYER_REGEN_DISABLED greift Blizzards Kampfsperre noch nicht (es liefe sofort)
local retry = false
local function RetryAfterCombat() retry = true end
function Intro.NewsRetryPending() return retry end

function Intro.TryNews()
    local hint = Core.OptInHint
    if hint and hint.Enabled and not hint.Enabled() then return false, "off" end
    local store = Intro.OfferStore()
    if not store then return false, "db" end
    if not Intro.Existing(store) then return false, "new" end
    if Intro.offeredNow or Intro.OfferPending(store) then return false, "offer" end
    if Intro.NewsBox() then return false, "shown" end
    local first = FirstTime(store)
    local ask, settled = Intro.NewsRows()
    -- an oder selbst ausgeschaltet: nichts zu entscheiden
    Intro.MarkKnown(settled)
    if #ask == 0 then
        Answered()   -- nichts mehr offen (etwa nach „Allem zustimmen“): das nächste Mal ist kein erstes Mal
        return false, "none"
    end
    if Core.InCombat() then
        RetryAfterCombat()
        return false, "combat"
    end
    if Intro.InInstance() then return false, "instance" end
    local target, side = Intro.OfferTarget()
    if not (target and ShowBox(ask, target, side, true, first)) then return false, "target" end
    return true, "bubble"
end

function Intro.ShowNews(fromPage)
    if Core.InCombat() then
        Core.CombatNotice(ns, L.INTRO_WHAT, "later")
        Core.AfterCombat(function() Intro.ShowNews(fromPage) end, Intro.NEWS_KEY, ADDON)
        return false
    end
    local store = Intro.OfferStore()
    local first = type(store) == "table" and store.newsFirst == true
    local ask, settled = Intro.NewsRows()
    Intro.MarkKnown(settled)
    local pending = #ask > 0
    local rows = pending and ask or Intro.LastNewsRows()
    if #rows == 0 then
        ns.Print(L.INTRO_NEWS_NONE)
        return false
    end
    local target, side
    local panel = rawget(_G, "SettingsPanel")
    if fromPage and type(panel) == "table" and panel.IsShown and panel:IsShown() then
        target, side = panel, Intro.SIDE
    else
        target, side = Intro.OfferTarget()
    end
    return target ~= nil and ShowBox(rows, target, side, pending, first and pending)
end

function Intro.AcceptNews(rows)
    rows = rows or open.rows or {}
    open.rows = nil
    if Core.InCombat() then
        Core.CombatNotice(ns, L.INTRO_WHAT, "later")
        Core.AfterCombat(function() Intro.AcceptNews(rows) end, Intro.NEWS_ACCEPT_KEY, ADDON)
        return 0, 0
    end
    local done, agreed, failed, known, risk = {}, {}, {}, {}, {}
    for _, row in ipairs(rows) do
        local entry = row.entry
        local value = Intro.Get(entry)
        if value == nil then
            -- das Modul läuft nicht mehr (oder die Zeile gilt gerade nicht): bleibt offen, kein Merker
        elseif row.on then
            -- ab Werk an: bleibt, wie der Spieler es gelassen hat; erledigt nur, wenn die Seite zu sehen war (weder
            -- Tooltip noch Chatzeile nennen es – sonst erführe er auf Seite 1 nichts von Seite 2)
            if row.shown then known[#known + 1] = row end
        elseif Intro.ConsentRisk(entry) then
            if value == false then risk[#risk + 1] = Line(row) end
            known[#known + 1] = row
        elseif value == false and Intro.CanSwitchOn(entry) then
            if Intro.Set(entry, true) then
                done[#done + 1] = Line(row)
                agreed[#agreed + 1] = row
                known[#known + 1] = row
            else
                -- nicht gegangen: bleibt offen, die nächste Nachfrage fragt wieder (wie „Allem zustimmen“, PR 536)
                failed[#failed + 1] = Line(row)
            end
        else
            known[#known + 1] = row
        end
    end
    -- ab Werk an, ausgeschaltet, und ausdrücklich mit „Alle annehmen“ einzuschalten (accept = true in ns.NEWS)
    for _, row in ipairs(Intro.AcceptRows()) do
        if Intro.Set(row.entry, true) then
            done[#done + 1] = Line(row)
            agreed[#agreed + 1] = row
            known[#known + 1] = row   -- eingeschaltet und im Chat genannt: auch von einer ungezeigten Seite nicht mehr neu
        else
            failed[#failed + 1] = Line(row)
        end
    end
    Intro.SettleAll(agreed)
    Intro.MarkKnown(known)
    Answered()
    if #done > 0 then ns.Print(L.INTRO_NEWS_DONE:format(table.concat(done, ", "))) end
    if #failed > 0 then ns.Print(L.INTRO_AGREE_FAILED:format(#failed, table.concat(failed, ", "))) end
    if #risk > 0 then ns.Print(L.INTRO_AGREE_RISK:format(table.concat(risk, ", "))) end
    -- Hinweise der Module, deren Zeilen eingeschaltet wurden (Intro.Notes, Entscheidung vom 23.11.2026)
    local seen = {}
    for _, row in ipairs(agreed) do
        if not seen[row.module] then
            seen[row.module] = true
            for _, note in ipairs(Intro.Notes(row.module)) do ns.Print(L.INTRO_AGREE_NOTE:format(note.module, note.text)) end
        end
    end
    return #done, #failed
end

function Intro.CloseNews(rows)
    local complete = true
    if not rows then
        -- nur die Seiten, die zu sehen waren (X auf einer mittleren Seite): der Rest bleibt offen
        local all = open.rows or {}
        local upto = math.min(#all, (open.seen or 0) * Intro.NEWS_ROWS)
        rows = {}
        for i = 1, upto do rows[i] = all[i] end
        complete = upto >= #all
    end
    open.rows = nil
    -- gesehen und entschieden wie beim Verlassen einer Seite der Einführung: auch die Hinweise „Einschalten“
    Intro.MarkKnown(rows)
    Intro.SettleAll(rows)
    if complete then Answered() end
    local off = 0
    for _, row in ipairs(rows) do
        if Intro.Get(row.entry) == false then off = off + 1 end
    end
    if off > 0 then ns.Print(L.INTRO_NEWS_LATER:format(off)) end
    return off
end

-- Ein Kampfbeginn nimmt die Blase weg, ohne dass etwas als angeboten gilt; danach kommt sie wieder
ns.On("PLAYER_REGEN_DISABLED", function()
    if Intro.NewsBox() then
        newsHints.Hide(Intro.NEWS_HINT)
        open.rows = nil
        RetryAfterCombat()
    end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not retry then return end
    retry = false
    C_Timer.After(Intro.AFTER_COMBAT_DELAY, function() Core.Try(nil, "Intro.TryNews", Intro.TryNews) end)
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(Intro.NEWS_DELAY, function() Core.Try(nil, "Intro.TryNews", Intro.TryNews) end)
end)
