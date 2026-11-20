local _, ns = ...
local Core = ezCore
local L = ns.L

--[[
    Rundgang mit Erklärblasen am Talentfenster (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026;
    docs/roadmap/ezTalent.md, „Abschlussrunde“). Beim ersten Öffnen des Talentfensters drei Blasen, eine nach der
    anderen, jede dort, wo ihr Teil steht (bis zum Spielbefund vom 19.11.2026 vier – mit dem Klappknopf „Vorlagen »“):

      list          Liste im Seitenteil „Vorlagen“ (Klick lädt die Vorschau; danach Übernehmen, Anpassen, Speichern)
      tabTemplates  Seitenreiter „Vorlagen“ am rechten Rand
      tabEffects    Seitenreiter „Auswirkungen“

    Gebaut mit Core.NewTour({ owner = ns, field = "hints" }): Gesehenes steht in ezTalentDB.hints, „Erweitert“ »
    „Erklärung – Erneut zeigen“ setzt es zurück (page:TourButton in Options.lua). Die Blasen sind Kinder ihres Ziels
    und verschwinden mit ihm – nur ezTalents eigene Teile (Reiter, Seitenteil), Blizzards Rahmen bleiben
    unberührt (Leitlinie 5). Ein Ziel, das gerade nicht zu sehen ist (Seitenteil zugeklappt, Reiter abgeschaltet), wird
    übersprungen und nicht als gesehen gemerkt; seine Blase kommt, sobald es erscheint. Gestartet wird über
    tour:StartSoon: viele Auslöser kurz nacheinander ergeben einen Start, im Kampf erst danach (Core.AfterCombat), nur
    bei offenem Talentfenster und nicht über dem Baum eines betrachteten Spielers.

    Dieselben Bedingungen gelten für eine Blase, die schon steht (Gegenprüfung 14.11.2026: eine unbestätigte Blase blieb
    als Kind ihres Ziels „gezeigt“ und stand beim nächsten Öffnen im Kampf oder über dem Baum eines betrachteten
    Spielers wieder da; „OK“ zeigte dort sogar die nächste). Darum: geht das Talentfenster zu, beginnt ein Kampf oder
    wird ein anderer Spieler betrachtet, verschwinden alle Blasen (tour:HideAll aus ezCore, nichts wird als gesehen
    gemerkt; bei Kampfbeginn Core.ToursCombatStarted, sonst Tour.Soon), und
    jede Blase kommt nur über tour:Next wieder – das prüft ezCore seit Welle 23b selbst (opts.enabled = Tour.Ready für
    Fenster und Betrachten, dazu der Kampf). Nach dem Kampf geht der Rundgang an derselben Stelle weiter.

    Das Vermächtnis-Fenster hat dieselben Reiter, aber keinen Rundgang: wer das Talentfenster kennt, kennt sie.
]]

local Tour = {}
ns.Tour = Tour

Tour.DELAY = 0.3    -- so lange nach dem Öffnen bzw. Umklappen warten, bis Blizzard und UI.Place alles gesetzt haben

local function Host()
    local UI = ns.UI
    return UI and UI.hosts and UI.hosts.class or nil
end

local listStep = { key = "list", text = L.TOUR_LIST, side = "left", target = function()
    local host = Host()
    local panel = host and host.panels.templates
    return panel and panel.scroll
end }

-- Seit dem Spielbefund vom 19.11.2026 („2 vorlagen buttons“) ohne die Blase am Klappknopf „Vorlagen »“ – den Knopf
-- gibt es nicht mehr, der Reiter „Vorlagen“ erklärt sich selbst.
Tour.STEPS = {
    listStep,
    { key = "tabTemplates", text = L.TOUR_TAB_TEMPLATES, side = "left", target = function()
        local host = Host()
        return host and host.tabs.templates
    end },
    { key = "tabEffects", text = L.TOUR_TAB_EFFECTS:format(ezCore.SettingsPathText("ezTalent")), side = "left", target = function()
        local host = Host()
        return host and host.tabs.effects
    end },
}

-- Darf der Rundgang jetzt zeigen? Nur bei sichtbarem Talentfenster und nur am eigenen Baum.
function Tour.Ready()
    local host = Host()
    if not host then return false end
    local parent = host.parent
    if type(parent) ~= "table" or type(parent.IsVisible) ~= "function" or parent:IsVisible() ~= true then return false end
    local ctx = ns.UI.Context(host)
    return not (ctx and ctx.inspecting)
end

-- single = true: immer nur eine Blase (ezCore, Welle 23b A32) – sonst stünde nach dem Aufklappen des Seitenteils die
-- Blase der Liste neben der eines Reiters. tour:Next prüft seit Welle 23b (A33) selbst opts.enabled (Tour.Ready) und
-- den Kampf, auch für „OK“ und das X an einer stehenden Blase; bei Kampfbeginn nimmt ezCore die Blasen jedes Rundgangs
-- weg (Core.ToursCombatStarted). Bis Welle 23 baute ezTalent das als Hülle um tour:Next und mit eigenem
-- PLAYER_REGEN_DISABLED (Tour.CombatStarted) – beides entfällt.
local tour = Core.NewTour({ owner = ns, field = "hints", steps = Tour.STEPS, enabled = Tour.Ready, single = true })
Tour.tour = tour

-- Nächste noch nicht gesehene Blase zeigen, deren Ziel zu sehen ist. → Schlüssel der gezeigten Blase oder nil
function Tour.Continue()
    return tour:Next()
end

-- Start vormerken (Öffnen und Schließen des Talentfensters, Auf- und Zuklappen des Seitenteils, Reiter an/aus).
-- host: das Fenster, das sich gemeldet hat – nur das Talentfenster zählt. → true, wenn ein Start vorgemerkt ist
function Tour.Soon(host)
    if host ~= nil and host.kind ~= "class" then return false end
    host = Host()
    if not host then return false end
    -- Die Blase der Liste ist ein Kind des Seitenteils, nicht des Rollrahmens der Liste (der könnte sie beschneiden)
    listStep.parent = host.panels.templates
    -- Eine Blase von vorhin darf hier nicht stehen bleiben (Fenster zu, betrachteter Spieler, Kampf); gemerkt wird
    -- dabei nichts, sie kommt wieder, sobald sie stehen darf. Bis Welle 23 lief das über die Hülle Tour.HideAll.
    if not Tour.Ready() or ns.InCombat() == true then tour:HideAll() end
    return tour:StartSoon(nil, Tour.DELAY)
end
