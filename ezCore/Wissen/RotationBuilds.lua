local Core = ezCore

--[[
    Welche Rotation (ezCombat) zu welcher Talentvorlage (ezTalent) gehört – n:m, an dieser einen Stelle:
    Core.RotationBuilds (Paket kern/talentbaum-rotationen, 24.11.2026). Anlass: Frage des Nutzers vom 24.11.2026, wörtlich
    „sind die angezeigten rotationen an die talentvorlagen gekoppelt? sodass es für jeden talenbaum eine rotation gibt und
    für jede rotation mindestens ein talentbaum?“, Nachtrag „bzw. beides n:m“ (ROADMAP-Index). Vorher nahm ezTalent zu
    einer Vorlage die erste Rotation desselben Talentbaums – 17 der 44 Rotationen waren so nie dabei (Shockadin bekam
    „Vergeltung“, der Bär die Katze, Überleben – Fernkampf den Nahkampf).

    Form: LINKS[KLASSE] = { { rotations = { Schlüssel … }, builds = { Schlüssel … } } … }
      rotations  Schlüssel aus ezCombat (RotationData/<KLASSE>.lua, RotationComputed.lua); die erste ist die Vorgabe
      builds     Schlüssel aus ezTalent (Presets.lua, Computed.lua); jede Vorlage steht in genau einer Zeile
    Zu einer Rotation gehören die Vorlagen aller Zeilen, in denen sie steht: zuerst die Zeilen, in denen sie die Vorgabe
    ist, dann die übrigen, je in der Reihenfolge hier. Die erste davon ist die Vorgabe der Rotation.

    Wonach zugeordnet ist (Leitlinien 11 und 12 – aus den Daten, nichts nach Namen):
      * derselbe Talentbaum (tree auf beiden Seiten) und
      * die Erkennung der Rotation (pick.known, pick.unknown) passt zu den Talenten der Vorlage;
      * Vorlagen zum Leveln (purpose) haben die Rotation fürs Leveln als Vorgabe (pick.leveling), die übrigen die andere;
        die jeweils andere steht dahinter – „Nach Talentbaum“ wechselt zwischen beiden nach der Stufe;
      * an Vorlagen zum Leveln steht dahinter auch die Rotation für die Zeit, bevor das entscheidende Talent gelernt ist
        („Nach Talentbaum“ nimmt sie bis dahin): Zerstörung beim Hexenmeister, Überleben – Fernkampf beim Jäger;
      * Gestalt (Druide: Katze, Bär) und Nah- oder Fernkampf (Jäger) laut Vorlage (style.form, style.range; ohne diese
        Angaben: tank = Bär, und wer das Nahkampf-Talent hat, ist Nahkampf);
      * eine berechnete Rotation gehört zu der Verteilung, für die sie gerechnet ist (computed.distribution). Alle sind
        vorläufig (ohne Talentwirkungen gerechnet) und stehen deshalb nie vorn.
    Das prüft tools/Tests/rotation_talente_test.lua in beide Richtungen: eine Vorlage ohne Rotation, eine Rotation ohne
    Vorlage, ein unbekannter Schlüssel oder eine Zuordnung, die den Daten widerspricht, ist rot. Eine Lücke braucht einen
    Grund in WITHOUT_BUILD bzw. WITHOUT_ROTATION; den zeigen die Module an (Leitlinie 11: nie leer ohne Erklärung).

      RotationBuilds.Rotations(klasse, vorlage)  → { Rotations-Schlüssel … } (erste = Vorgabe; leer ohne Zuordnung)
      RotationBuilds.Builds(klasse, rotation)    → { Vorlagen-Schlüssel … } (erste = Vorgabe; leer ohne Zuordnung)
      RotationBuilds.Why(klasse, rotation)       → Grund, warum es zu dieser Rotation keine Vorlage gibt | nil
      RotationBuilds.WhyBuild(klasse, vorlage)   → Grund, warum es zu dieser Vorlage keine Rotation gibt | nil
    Geliefert werden Kopien; die Schlüssel löst das jeweilige Modul auf (ezCombat bzw. ezTalent, über ezCore.API).
]]

local RotationBuilds = {}
Core.RotationBuilds = RotationBuilds

-- Lücken mit Grund: [KLASSE] = { [Schlüssel] = { de, en } }
RotationBuilds.WITHOUT_BUILD = {
    MAGE = {
        fire = {
            de = "Diese Rotation ist für einen Feuerbaum ohne „Verbrennung“ am Ende. Alle Talentvorlagen für Feuer enthalten dieses Talent, und für einen Baum ohne es gibt es keine nachprüfbare Quelle mit Rängen.",
            en = "This rotation is for a Fire build without Combustion at the end. Every Fire talent template contains that talent, and there is no verifiable source with ranks for a build without it.",
        },
    },
}
RotationBuilds.WITHOUT_ROTATION = {}

RotationBuilds.LINKS = {
    WARRIOR = {
        { rotations = { "arms", "arms_level" }, builds = { "arms-2h", "sim-arms", "sim-arms-pvp" } },
        { rotations = { "arms_level", "arms" }, builds = { "arms-leveling", "sim-arms-leveling", "sim-arms-survival" } },
        -- sim-fury-2h (Zweihand-Axt): Furor hat nur diese Rotation. Ihre Erklärung spricht von zwei Waffen, kein Schritt
        -- hängt aber an der Zweitwaffe.
        { rotations = { "fury", "fury_level" }, builds = { "fury-dual", "sim-fury", "sim-fury-pvp", "sim-fury-2h" } },
        { rotations = { "fury_level", "fury" }, builds = { "sim-fury-leveling", "sim-fury-survival" } },
        { rotations = { "protection", "protection_level" }, builds = { "prot-tank", "sim-prot" } },
        { rotations = { "protection_level", "protection" }, builds = { "prot-leveling" } },
    },
    PALADIN = {
        { rotations = { "holy" }, builds = { "holy-vigil" } },
        { rotations = { "holy", "sim-holy" }, builds = { "sim-holy" } },
        { rotations = { "holy", "sim-holy-leveling" }, builds = { "sim-holy-leveling" } },
        { rotations = { "holy", "sim-holy-pvp" }, builds = { "sim-holy-pvp" } },
        { rotations = { "protection" }, builds = { "prot-deep", "sim-prot", "sim-prot-leveling" } },
        { rotations = { "retribution" }, builds = { "ret-unsealed", "ret-leveling", "sim-ret", "sim-ret-leveling", "sim-ret-pvp" } },
        { rotations = { "retribution_shock" }, builds = { "shockadin" } },
    },
    HUNTER = {
        { rotations = { "beastmastery" }, builds = { "bm-group", "bm-leveling", "sim-bm", "sim-bm-leveling", "sim-bm-survival" } },
        { rotations = { "marksmanship" }, builds = { "mm-lonewolf", "sim-mm", "sim-mm-leveling", "sim-mm-pvp", "sim-mm-pet" } },
        { rotations = { "survival" }, builds = { "sv-weave", "sim-sv", "sim-sv-pvp" } },
        { rotations = { "survival", "survival_ranged" }, builds = { "sim-sv-leveling", "sim-sv-survival" } },
        { rotations = { "survival_ranged" }, builds = { "sim-sv-ranged" } },
    },
    ROGUE = {
        { rotations = { "assassination", "assassination_level" }, builds = { "assa-mutilate", "sim-assa", "sim-assa-pvp" } },
        { rotations = { "assassination_level", "assassination" }, builds = { "sim-assa-leveling" } },
        { rotations = { "combat_level", "combat" }, builds = { "combat-leveling", "sim-combat-leveling", "sim-combat-survival" } },
        { rotations = { "combat", "combat_level" }, builds = { "combat-end", "sim-combat", "sim-combat-pvp" } },
        { rotations = { "subtlety", "subtlety_level" }, builds = { "sub-bleed", "sim-sub", "sim-sub-pvp" } },
        { rotations = { "subtlety_level", "subtlety" }, builds = { "sim-sub-survival" } },
    },
    PRIEST = {
        { rotations = { "discipline" }, builds = { "disc-shield", "disc-leveling" } },
        { rotations = { "discipline", "sim-disc" }, builds = { "sim-disc" } },
        { rotations = { "discipline", "sim-disc-leveling" }, builds = { "sim-disc-leveling" } },
        { rotations = { "discipline", "sim-disc-pvp" }, builds = { "sim-disc-pvp" } },
        { rotations = { "holy" }, builds = { "holy-group" } },
        { rotations = { "holy", "sim-holy" }, builds = { "sim-holy" } },
        { rotations = { "holy", "sim-holy-leveling" }, builds = { "sim-holy-leveling" } },
        { rotations = { "holy", "sim-holy-pvp" }, builds = { "sim-holy-pvp" } },
        { rotations = { "shadow", "shadow_level" }, builds = { "shadow-end" } },
        { rotations = { "shadow_level", "shadow" }, builds = { "shadow-leveling" } },
        { rotations = { "shadow", "shadow_level", "sim-shadow" }, builds = { "sim-shadow" } },
        { rotations = { "shadow_level", "shadow", "sim-shadow-leveling" }, builds = { "sim-shadow-leveling" } },
        { rotations = { "shadow", "shadow_level", "sim-shadow-pvp" }, builds = { "sim-shadow-pvp" } },
        { rotations = { "shadow_level", "shadow", "sim-shadow-survival" }, builds = { "sim-shadow-survival" } },
    },
    SHAMAN = {
        { rotations = { "elemental" }, builds = { "ele-aoe", "ele-leveling" } },
        { rotations = { "elemental", "sim-ele" }, builds = { "sim-ele" } },
        { rotations = { "elemental", "sim-ele-leveling" }, builds = { "sim-ele-leveling" } },
        { rotations = { "elemental", "sim-ele-pvp" }, builds = { "sim-ele-pvp" } },
        { rotations = { "elemental", "sim-ele-survival" }, builds = { "sim-ele-survival" } },
        { rotations = { "enhancement_level", "enhancement" }, builds = { "enh-leveling", "sim-enh-leveling", "sim-enh-survival" } },
        { rotations = { "enhancement", "enhancement_level" }, builds = { "enh-end", "sim-enh", "sim-enh-aoe", "sim-enh-pvp" } },
        { rotations = { "restoration" }, builds = { "resto-healer" } },
        { rotations = { "restoration", "sim-resto" }, builds = { "sim-resto" } },
        { rotations = { "restoration", "sim-resto-leveling" }, builds = { "sim-resto-leveling" } },
    },
    MAGE = {
        { rotations = { "arcane", "arcane_level" }, builds = { "arcane-fire" } },
        { rotations = { "arcane", "arcane_level", "sim-arcane" }, builds = { "sim-arcane" } },
        { rotations = { "arcane_level", "arcane", "sim-arcane-leveling" }, builds = { "sim-arcane-leveling" } },
        { rotations = { "arcane", "arcane_level", "sim-arcane-pvp" }, builds = { "sim-arcane-pvp" } },
        { rotations = { "arcane_level", "arcane", "sim-arcane-survival" }, builds = { "sim-arcane-survival" } },
        { rotations = { "fire_deep", "fire_level" }, builds = { "fire-arcane" } },
        { rotations = { "fire_deep", "fire_level", "sim-fire" }, builds = { "sim-fire" } },
        { rotations = { "fire_level", "fire_deep", "sim-fire-leveling" }, builds = { "sim-fire-leveling" } },
        { rotations = { "fire_deep", "fire_level", "sim-fire-pvp" }, builds = { "sim-fire-pvp" } },
        { rotations = { "fire_level", "fire_deep", "sim-fire-survival" }, builds = { "sim-fire-survival" } },
        { rotations = { "frost" }, builds = { "frost-leveling", "frost-deep", "frost-raid" } },
        { rotations = { "frost", "sim-frost" }, builds = { "sim-frost" } },
        { rotations = { "frost", "sim-frost-leveling" }, builds = { "sim-frost-leveling" } },
        { rotations = { "frost", "sim-frost-pvp" }, builds = { "sim-frost-pvp" } },
        { rotations = { "frost", "sim-frost-survival" }, builds = { "sim-frost-survival" } },
    },
    WARLOCK = {
        { rotations = { "affliction", "affliction_level" }, builds = { "aff-wrack", "aff-ruin" } },
        { rotations = { "affliction", "affliction_level", "sim-aff" }, builds = { "sim-aff" } },
        { rotations = { "affliction_level", "affliction", "sim-aff-leveling" }, builds = { "sim-aff-leveling" } },
        { rotations = { "affliction", "affliction_level", "sim-aff-pvp" }, builds = { "sim-aff-pvp" } },
        { rotations = { "affliction_level", "affliction", "sim-aff-survival" }, builds = { "sim-aff-survival" } },
        { rotations = { "affliction_level", "affliction" }, builds = { "sim-aff-voidwalker" } },
        { rotations = { "demonology", "demonology_level" }, builds = { "demo-pact" } },
        { rotations = { "demonology", "demonology_level", "sim-demo" }, builds = { "sim-demo" } },
        { rotations = { "demonology_level", "demonology", "sim-demo-leveling" }, builds = { "sim-demo-leveling" } },
        { rotations = { "demonology", "demonology_level", "sim-demo-pvp" }, builds = { "sim-demo-pvp" } },
        { rotations = { "demonology_level", "demonology", "sim-demo-survival" }, builds = { "sim-demo-survival" } },
        { rotations = { "destruction" }, builds = { "destro-sacrifice", "destro-sayaad", "sim-destro-succubus" } },
        { rotations = { "destruction", "sim-destro" }, builds = { "sim-destro" } },
        { rotations = { "destruction", "destruction_level", "sim-destro-leveling" }, builds = { "sim-destro-leveling" } },
        { rotations = { "destruction", "sim-destro-pvp" }, builds = { "sim-destro-pvp" } },
        { rotations = { "destruction", "destruction_level", "sim-destro-survival" }, builds = { "sim-destro-survival" } },
    },
    DRUID = {
        { rotations = { "balance" }, builds = { "balance-raid" } },
        { rotations = { "balance", "sim-balance" }, builds = { "sim-balance" } },
        { rotations = { "balance", "sim-balance-pvp" }, builds = { "sim-balance-pvp" } },
        { rotations = { "feral" }, builds = { "feral-cat", "sim-cat", "sim-cat-pvp", "sim-cat-survival" } },
        { rotations = { "feral", "feral_bear" }, builds = { "feral-leveling" } },
        { rotations = { "feral_bear", "feral" }, builds = { "feral-hybrid" } },
        { rotations = { "feral_bear" }, builds = { "sim-bear" } },
        { rotations = { "restoration" }, builds = { "resto-healer" } },
        { rotations = { "restoration", "sim-resto" }, builds = { "sim-resto" } },
        { rotations = { "restoration", "sim-resto-pvp" }, builds = { "sim-resto-pvp" } },
    },
}

---------------------------------------------------------------------------
-- Abfragen (beide Richtungen aus derselben Tabelle, je Klasse einmal aufgebaut)
---------------------------------------------------------------------------

local index = {}        -- [KLASSE] = { links, rotations = { [Vorlage] = Liste }, builds = { [Rotation] = Liste } }

local function Index(class)
    local links = type(class) == "string" and RotationBuilds.LINKS[class] or nil
    if type(links) ~= "table" then return nil end
    local slot = index[class]
    if slot and slot.links == links then return slot end
    slot = { links = links, rotations = {}, builds = {} }
    for pass = 1, 2 do
        for _, row in ipairs(links) do
            for place, rotation in ipairs(row.rotations) do
                if (place == 1) == (pass == 1) then
                    local list = slot.builds[rotation] or {}
                    slot.builds[rotation] = list
                    for _, build in ipairs(row.builds) do list[#list + 1] = build end
                end
            end
            if pass == 1 then
                for _, build in ipairs(row.builds) do slot.rotations[build] = row.rotations end
            end
        end
    end
    index[class] = slot
    return slot
end

local function Copy(list)
    local out = {}
    for i, key in ipairs(list or {}) do out[i] = key end
    return out
end

function RotationBuilds.Rotations(class, build)
    local slot = Index(class)
    return Copy(slot and build ~= nil and slot.rotations[build] or nil)
end

function RotationBuilds.Builds(class, rotation)
    local slot = Index(class)
    return Copy(slot and rotation ~= nil and slot.builds[rotation] or nil)
end

local function Reason(list, class, key)
    local entry = type(list[class]) == "table" and key ~= nil and list[class][key] or nil
    if type(entry) ~= "table" then return nil end
    return (Core.IsGerman() and entry.de) or entry.en or entry.de
end

function RotationBuilds.Why(class, rotation) return Reason(RotationBuilds.WITHOUT_BUILD, class, rotation) end
function RotationBuilds.WhyBuild(class, build) return Reason(RotationBuilds.WITHOUT_ROTATION, class, build) end
