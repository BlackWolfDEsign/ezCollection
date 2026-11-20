local _, ns = ...
local L = ns.L

-- Hinweisblasen wie Blizzards Tutorial-Hinweise (GlowBoxTemplate mit Pfeil, „Verstanden“ unten, gelbes X
-- oben rechts; Umsetzung in ezCore/Widgets.lua, eigene Frames statt Blizzards HelpTip-Pool). Jede Blase
-- erscheint, bis man sie bestätigt (ezMacroDB.hints); in den Einstellungen lassen sich alle wieder einschalten.
-- ns.Hint.Show(key, parent, target, text, side), .Hide(key), .Box(key), .Seen(key), .Reset()
-- Den Rundgang durch den Makro-Browser (ezCore.NewTour, ns.Tour in Browser.lua) speichert dieselbe Tabelle.
-- Der Speicher kommt aus dem Gerüst (ns.TourStore("hints"), angelegt über opts.tables); nil vor dem Laden.
function ns.HintStore()
    return ns.TourStore("hints")
end

ns.Hint = ezCore.NewHints(ns.HintStore, L.HINT_OK)

-- Knopf „Erklärung – Erneut zeigen“ (Einstellungen → Erweitert): Rundgang und Blase an der Emote-Leiste wieder
-- zeigen – die Blase an der Leiste sofort, den Rundgang jetzt bzw. beim nächsten Öffnen des Makro-Browsers.
function ns.ResetHints()
    if ns.Tour then ns.Tour:Reset() end
    ns.Hint.Reset()
    if ns.EmoteBar then ns.EmoteBar.PlaceAll() end
    local browser = ns.Browser and ns.Browser.Frame()
    if browser and browser:IsShown() and ns.Tour then ns.Tour:Start(browser) end
end
