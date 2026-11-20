local _, ns = ...
local T = ns.RotationData.T

-- Volksfähigkeiten (RACIAL) für WoW Forever. ezCombat reiht sie oben in die Rotation des Spielers ein (race = Volk,
-- class = nur diese Klasse). Deshalb trägt jede eine Art (kind), die sie nicht vor die Rotation stellt: große
-- Abklingzeiten als "cooldown" – sie folgen der Einstellung „Große Abklingzeiten vorschlagen“ (Standard: nur gegen
-- Elite und Bosse, Entscheidung des Nutzers vom 13.11.2026) –, alles, was keine Rotationsliste nennt, als
-- "situational" (steht im Zauberbuch, wird nie vorgeschlagen). Format und Felder: Kopf von RotationData.lua.
-- Quellen, abgerufen am 13.11.2026 – nur Fakten, alle Texte in eigenen Worten:
--   https://www.icy-veins.com/wow-forever/racial-tier-list
--   https://www.icy-veins.com/wow-forever/priest-class-quests (Priester)
-- Zauber-IDs geprüft gegen nether.wowhead.com/forever. Nichts stammt aus einem Addon. Name, Symbol, Abklingzeit,
-- Dauer und Wirkung liefert der Client zur Laufzeit; hier stehen nur Zauber-ID und Logik.
-- Gesamtreview 18.11.2026 (T14-1): dazu die übrigen aktiven Volksfähigkeiten der Völker, die ezMacro als Volks-Makros
-- anbietet (Mensch, Zwerg, Nachtelf, Gnom, Untote), als "situational". Volk je Zauber laut Client-Tabellen
-- (SkillLineAbility.RaceMask, Bit laut ChrRaces.PlayableRaceBit; wago.tools, wowf 1.60.1.70938) – die wago-Prüfung
-- (tools/wago_pruefung.lua, Art „volk“) gleicht jeden Eintrag ab. Verzweifeltes Gebet steht laut Volksmaske nur den
-- Zwergen offen (Furchtzauberschutz allen Völkern – darum kein Volkszauber).

ns.RotationData.Add("RACIAL", {
    { race = "Orc", id = 20572, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
      text = T("Zusammen mit den anderen großen Abklingzeiten.", "Together with your other major cooldowns.") },    -- Kochendes Blut / Blood Fury
    { race = "Troll", id = 20554, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
      text = T("Zusammen mit den anderen großen Abklingzeiten.", "Together with your other major cooldowns.") },    -- Berserker / Berserking
    { race = "Tauren", id = 20549, kind = "situational", when = "manual",
      text = T("Bei Bedarf: betäubt die Gegner in der Nähe – zum Entkommen oder Unterbrechen.",
          "As needed: stuns nearby enemies – to escape or to interrupt.") },    -- Kriegsdonner / War Stomp
    { race = "NightElf", class = "PRIEST", id = 10797, kind = "situational", when = "manual",
      text = T("Nach Lage: kanalisierter Fernschaden; keine Rotationsliste nennt ihn.",
          "As needed: channeled ranged damage; no rotation list includes it.") },    -- Sternensplitter / Starshards
    { race = "Undead", class = "PRIEST", id = 2652, kind = "situational", when = "manual",
      text = T("Nach Lage: vor Kämpfen gegen Nahkämpfer; der nächste Treffer verbraucht ihn.",
          "As needed: before fights against melee; the next hit consumes it.") },    -- Berührung der Schwäche / Touch of Weakness
    { race = "Human", id = 20600, kind = "situational", when = "manual",
      text = T("Bei Bedarf: entdeckt eine Weile lang schleichende Gegner leichter.",
          "As needed: spots stealthed enemies more easily for a while.") },    -- Wahrnehmung / Perception
    { race = "Dwarf", id = 20594, kind = "situational", when = "manual",
      text = T("Bei Bedarf: entfernt Gift, Krankheit und Blutung und erhöht die Rüstung.",
          "As needed: removes poison, disease and bleeds and raises your armor.") },    -- Steingestalt / Stoneform
    { race = "Dwarf", id = 2481, kind = "situational", when = "manual",
      text = T("Nach Lage: zeigt Schätze auf der Minikarte.", "As needed: shows treasure on the minimap.") },    -- Schatzsuche / Find Treasure
    { race = "Dwarf", class = "PRIEST", id = 13908, kind = "situational", when = "manual",
      text = T("Für den Notfall: heilt dich sofort.", "For emergencies: heals you instantly.") },    -- Verzweifeltes Gebet / Desperate Prayer
    { race = "NightElf", id = 20580, kind = "situational", when = "manual",
      text = T("Bei Bedarf: verbirgt dich, solange du dich nicht bewegst.",
          "As needed: hides you as long as you don't move.") },    -- Schattenmimik / Shadowmeld
    { race = "Gnome", id = 20589, kind = "situational", when = "manual",
      text = T("Bei Bedarf: befreit dich von Verlangsamung und Bewegungsunfähigkeit.",
          "As needed: frees you from snares and roots.") },    -- Entfesseln / Escape Artist
    { race = "Undead", id = 7744, kind = "situational", when = "manual",
      text = T("Bei Bedarf: befreit dich von Furcht, Bezauberung und Schlaf.",
          "As needed: breaks fear, charm and sleep.") },    -- Wille der Verlassenen / Will of the Forsaken
    { race = "Undead", id = 20577, kind = "situational", when = "manual",
      text = T("Nach dem Kampf: an einer Leiche Leben zurückholen.",
          "After combat: regain health from a corpse.") },    -- Kannibalismus / Cannibalize
})
