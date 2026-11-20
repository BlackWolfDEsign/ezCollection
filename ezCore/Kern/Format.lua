local _, ns = ...
local Core = ezCore
local L = Core.L
local floor = math.floor

-- Geld, Zeit, Farben, Klassen und Völker – überall gleich dargestellt.

---------------------------------------------------------------------------
-- Farben
---------------------------------------------------------------------------

Core.GOLD = NORMAL_FONT_COLOR_CODE or "|cffffd100"
Core.WHITE = HIGHLIGHT_FONT_COLOR_CODE or "|cffffffff"
Core.GREY = "|cff9d9d9d"
Core.GREEN = "|cff20ff20"
Core.RED = "|cffff2020"
Core.YELLOW = "|cffffff00"

-- Pfeil in Oberflächentexten („Esc » Optionen » AddOns“). Blizzards Schrift (Friz Quadrata) hat „→“, „▸“ und „►“
-- nicht und zeigt dafür Kästchen (Spieltest 14.11.2026: » › > gehen, ▸ ► nicht) – in Texten für Tooltips, Menüs
-- und Einstellungen deshalb immer dieses Zeichen.
Core.ARROW = "»"

function Core.Gold(text) return Core.GOLD .. tostring(text) .. "|r" end
function Core.White(text) return Core.WHITE .. tostring(text) .. "|r" end
function Core.Grey(text) return Core.GREY .. tostring(text) .. "|r" end
function Core.Green(text) return Core.GREEN .. tostring(text) .. "|r" end
function Core.Red(text) return Core.RED .. tostring(text) .. "|r" end
function Core.Yellow(text) return Core.YELLOW .. tostring(text) .. "|r" end

-- Ampel (V-180; vorher je Modul eigene Farbcodes): Farbcode für einen Wert, bei dem wenig schlecht ist – unter
-- red rot, unter yellow gelb, sonst grün (Tage bis zum Ablauf, Haltbarkeit, freie Plätze). Ist viel schlecht,
-- red größer als yellow angeben: ab red rot, ab yellow gelb, sonst grün (Latenz, Fehlerzahl). Gesperrter oder
-- fehlender Wert: Core.GREY. Mit text kommt der gefärbte Text zurück, sonst nur der Farbcode.
function Core.TrafficColor(value, red, yellow, text)
    value, red, yellow = Core.Num(value), Core.Num(red), Core.Num(yellow)
    local color = Core.GREY
    if value and red and yellow then
        if red <= yellow then
            color = value < red and Core.RED or value < yellow and Core.YELLOW or Core.GREEN
        else
            color = value >= red and Core.RED or value >= yellow and Core.YELLOW or Core.GREEN
        end
    end
    if text ~= nil then return color .. tostring(text) .. "|r" end
    return color
end

---------------------------------------------------------------------------
-- Geld
---------------------------------------------------------------------------

-- Kupfer mit Blizzards Münzsymbolen.
function Core.CoinText(copper)
    copper = copper or 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return tostring(copper)
end

-- Kupfer als Text. style: "coins" (Münzsymbole), "gold" (nur Gold), "text" (12g 34s 56k)
function Core.Money(copper, style, colorNegative)
    copper = Core.Num(copper) or 0
    style = style or "coins"
    local negative = copper < 0
    copper = math.abs(math.floor(copper + 0.5))
    local text
    if style == "gold" then
        local gold = math.floor(copper / 10000)
        text = Core.FormatNumber(gold) .. "|cffffd100" .. L.COIN_G .. "|r"
    elseif style == "text" then
        local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
        local parts = {}
        if g > 0 then parts[#parts + 1] = Core.FormatNumber(g) .. "|cffffd100" .. L.COIN_G .. "|r" end
        if g > 0 or s > 0 then parts[#parts + 1] = s .. "|cffc7c7cf" .. L.COIN_S .. "|r" end
        parts[#parts + 1] = c .. "|cffeda55f" .. L.COIN_C .. "|r"
        text = table.concat(parts, " ")
    else
        text = Core.CoinText(copper)
    end
    if negative then
        text = "-" .. text
        if colorNegative then text = "|cffff2020" .. text .. "|r" end
    end
    return text
end

-- Betrag aus einem getippten Text (Welle 23a, A10; vorher ezAuction Lists.ParseMoney): „5“ oder „5,5“ (Gold),
-- „5g 20s 3c“, „20s“, „3k“ (Kupfer; neben g/s/c/k auch Blizzards GOLD_/SILVER_/COPPER_AMOUNT_SYMBOL und ezCores
-- COIN_G/COIN_S/COIN_C, wenn sie ein Buchstabe sind) → Kupfer; leerer Text → nil; Unsinn, 0 oder mehr als maxKupfer
-- → false. Gesperrter Text → false.
local function CoinFactors()
    local factor = { g = 10000, s = 100, c = 1, k = 1 }
    local function Add(symbol, value)
        if type(symbol) == "string" and not Core.IsSecret(symbol) then
            symbol = symbol:lower()
            if symbol:match("^%a$") and not factor[symbol] then factor[symbol] = value end
        end
    end
    Add(rawget(_G, "GOLD_AMOUNT_SYMBOL"), 10000)
    Add(rawget(_G, "SILVER_AMOUNT_SYMBOL"), 100)
    Add(rawget(_G, "COPPER_AMOUNT_SYMBOL"), 1)
    Add(L.COIN_G, 10000)
    Add(L.COIN_S, 100)
    Add(L.COIN_C, 1)
    return factor
end

function Core.ParseMoney(text, maxCopper)
    if Core.IsSecret(text) or type(text) ~= "string" then return false end
    maxCopper = Core.Num(maxCopper) or math.huge
    text = Core.Trim(text):lower()
    if text == "" then return nil end
    local gold = tonumber((text:gsub(",", ".")):match("^(%d+%.?%d*)$") or "")
    if gold then
        local copper = floor(gold * 10000 + 0.5)
        return copper > 0 and copper <= maxCopper and copper or false
    end
    local factor = CoinFactors()
    local total, rest = 0, text:gsub("%s+", "")
    while rest ~= "" do
        local number, unit, after = rest:match("^(%d+)(%a)(.*)$")
        if not number or not factor[unit] then return false end
        total = total + tonumber(number) * factor[unit]
        rest = after
    end
    return total > 0 and total <= maxCopper and total or false
end

-- Geld als reiner Text ohne Münzbilder und Farben (z. B. für einen Betreff).
function Core.PlainMoney(copper)
    if Core.IsSecret(copper) then return "?" end     -- V-022: wie Core.Money
    copper = Core.Num(copper) or 0
    local gold = floor(copper / 10000)
    local silver = floor(copper / 100) % 100
    local cop = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. (GOLD_AMOUNT_SYMBOL or "g") end
    if silver > 0 then parts[#parts + 1] = silver .. (SILVER_AMOUNT_SYMBOL or "s") end
    if cop > 0 then parts[#parts + 1] = cop .. (COPPER_AMOUNT_SYMBOL or "c") end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Zeit
---------------------------------------------------------------------------

-- 3725 Sekunden → „1 Std. 2 Min.“ (short: „1h 2m“)
function Core.Duration(seconds, short)
    seconds = Core.Num(seconds)
    if not seconds then return "?" end
    if seconds < 0 then seconds = 0 end
    local d = math.floor(seconds / 86400)
    local h = math.floor(seconds / 3600) % 24
    local m = math.floor(seconds / 60) % 60
    local s = math.floor(seconds) % 60
    if d > 0 then return (short and L.FMT_DH_SHORT or L.FMT_DH):format(d, h) end
    if h > 0 then return (short and L.FMT_HM_SHORT or L.FMT_HM):format(h, m) end
    if m > 0 then return (short and L.FMT_MS_SHORT or L.FMT_MS):format(m, s) end
    return (short and L.FMT_S_SHORT or L.FMT_S):format(s)
end

-- Sekunden und Minuten als Zahl mit Einheit aus EINER Stelle (Frage 9, Entscheidung des Nutzers 14.11.2026:
-- „Sek.“/„Min.“; vorher je Modul eigene UNIT_*-Texte): Core.Seconds(90) → „90 Sek.“ / „90 s“,
-- Core.Minutes(5) → „5 Min.“ / „5 min“; digits = Nachkommastellen („0,5 Sek.“ / „0.5 s“ für Schieberegler). Anders als
-- Core.Duration wird nicht umgerechnet (90 Sekunden bleiben 90 Sekunden). Die Einheit kommt aus den Texten, die
-- Core.Duration schon nutzt (FMT_S; die Minuten sind der vordere Teil von FMT_MS) – keine zweite Textstelle.
-- short = true: „90s“, „5m“. Gesperrter oder fehlender Wert: „?“. Nachkommastellen im deutschen Client mit Komma
-- („1,5 Sek.“), im englischen mit Punkt („1.5 s“) – Core.Decimal (Entscheidung des Nutzers vom 16.11.2026, Nr. 41).
local function UnitText(fmt, value, digits)
    value = Core.Num(value)
    if not value then return "?" end
    local number = Core.Decimal(value, digits)
    return (fmt:gsub("%%d", function() return number end, 1))
end

function Core.Seconds(seconds, digits, short)
    return UnitText(short and L.FMT_S_SHORT or L.FMT_S, seconds, digits)
end

function Core.Minutes(minutes, digits, short)
    local fmt = short and L.FMT_MS_SHORT or L.FMT_MS
    -- „%d Min. %d Sek.“ → „%d Min.“: alles vor dem zweiten Platzhalter, ohne den Leerraum davor
    local head = fmt:match("^(.-%%d.-)%s*%%d") or fmt
    return UnitText(head, minutes, digits)
end

-- Stunden wie Core.Minutes (Welle 23a, A8): Core.Hours(2) → „2 Std.“ / „2 h“, short: „2h“. Die Einheit ist der
-- vordere Teil von FMT_HM bzw. FMT_HM_SHORT (dieselben Texte wie Core.Duration) – keine zweite Textstelle.
function Core.Hours(hours, digits, short)
    local fmt = short and L.FMT_HM_SHORT or L.FMT_HM
    local head = fmt:match("^(.-%%d.-)%s*%%d") or fmt
    return UnitText(head, hours, digits)
end

-- Vergangene Zeit seit einem Zeitstempel: „vor 3 Tagen“. base: Basis des Stempels – "local" (Standard, PC-Uhr wie
-- Core.Now) oder "server" (Serveruhr wie Core.DB.Stamp; T16-NZ1, Gesamtreview 18.11.2026).
function Core.Ago(stamp, base)
    stamp = Core.Num(stamp)
    if not stamp or stamp <= 0 then return L.UNKNOWN end
    local diff = Core.Time.Now(base == "server" and "server" or "local") - stamp
    if diff < 120 then return L.AGO_NOW end
    return L.AGO:format(Core.Duration(diff, true))
end

-- Restzeit mit Blizzards Wortlaut (SecondsToTime), höchstens zwei Einheiten, ohne Sekunden – unter einer Minute mit
-- Sekunden (SecondsToTime ohne Sekunden gäbe dort einen leeren Text). Ohne SecondsToTime: Core.Duration (Texte der
-- Spielsprache). Gegenprüfung P19a: vorher stand unter einer Minute „0 h“ (ezMail-Posteingang, seit T16-15 hier).
function Core.TimeLeft(seconds)
    if Core.IsSecret(seconds) then return "?" end    -- V-022: wie Core.Duration
    seconds = math.max(0, floor(Core.Num(seconds) or 0))
    if SecondsToTime then
        local ok, text = pcall(SecondsToTime, seconds, seconds >= 60, false, 2)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return Core.Duration(seconds, true)
end

---------------------------------------------------------------------------
-- Datum, Uhrzeit, Koordinaten (je Sprache; vorher in ezChat, ezBag, ezLoot, ezMail, ezMap, ezPanel)
---------------------------------------------------------------------------

-- Zeitpunkt als Text, immer in der Ortszeit des PCs (Entscheidung 6 vom 18.11.2026). mode nil: heute nur „14:05“,
-- sonst Datum und Uhrzeit; "day": heute „14:05“, sonst nur das Datum; "full": immer Datum und Uhrzeit; "long": mit
-- Jahr; "iso": „2026-11-18 14:05“, "isoSec": mit Sekunden (Maschinen- und Diagnosetexte, in jeder Sprache gleich).
-- base: Basis des Stempels – "local" (Standard, PC-Uhr) oder "server" (Serveruhr wie Core.DB.Stamp); ein Server-
-- Stempel wird vorher auf die PC-Uhr umgerechnet (Core.Time.FromServer).
function Core.DateText(t, mode, base)
    t = Core.Time.AsLocal(t, base)
    if not t then return "" end
    if mode == "iso" then return date("%Y-%m-%d %H:%M", t) end
    if mode == "isoSec" then return date("%Y-%m-%d %H:%M:%S", t) end
    local today = Core.Time.IsToday(t, "local")
    if mode == "long" then return date(L.DATE_LONG, t) end
    if mode ~= "full" and today then return date("%H:%M", t) end
    if mode == "day" then return date(L.DATE_DAY, t) end
    return date(L.DATE_SHORT, t)
end

-- Beschriftung einer Zeitbasis (Entscheidung 6 vom 18.11.2026: „jeweils beschriftet“): „Ortszeit“ bzw. „Serverzeit“.
function Core.Time.Label(base)
    return base == "server" and L.TIME_BASE_SERVER or L.TIME_BASE_LOCAL
end

-- Text mit seiner Zeitbasis: Core.Time.Tagged("heute", "server") → „heute (Serverzeit)“.
function Core.Time.Tagged(text, base)
    if Core.IsSecret(text) then return text end
    return L.TIME_TAGGED:format(tostring(text or ""), Core.Time.Label(base))
end

-- Uhr-Schreibweise für Dauern: 2:05, 1:02:05.
function Core.Clock(seconds)
    seconds = Core.Num(seconds)
    if not seconds then return "-:--" end
    seconds = math.max(0, floor(seconds + 0.5))
    local h, m, s = floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- Koordinaten (0 bis 1 wie Core.PlayerPosition) als „42.3, 70.1“; precision = Nachkommastellen (Standard 1).
function Core.CoordText(x, y, precision)
    x, y = Core.Num(x), Core.Num(y)
    if not (x and y) then return "" end
    local p = Core.Num(precision) or 1
    return ("%." .. p .. "f, %." .. p .. "f"):format(x * 100, y * 100)
end

---------------------------------------------------------------------------
-- Klassen und Völker
---------------------------------------------------------------------------

-- Farbe einer Gegenstandsqualität: r, g, b (unbekannt: weiß) bzw. Farbcode (eine Stelle für alle Module).
function Core.QualityRGB(quality)
    quality = Core.Num(quality)
    if quality then
        local data = ColorManager and ColorManager.GetColorDataForItemQuality and ColorManager.GetColorDataForItemQuality(quality)
        if type(data) == "table" and data.r then return data.r, data.g, data.b end
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then return color.r, color.g, color.b end
    end
    return 1, 1, 1
end

function Core.QualityHex(quality) return Core.ColorCode(Core.QualityRGB(quality)) end

-- Name einer Gegenstandsqualität (Gesamtreview 18.11.2026, T16-6; vorher acht Kopien in den Modulen mit verschiedenen
-- Rückfällen – tostring(q), q als Zahl, eigene Texte, „?“): Blizzards Text (ITEM_QUALITY<q>_DESC), sonst ezCores
-- eigener (L.QUALITY_NAME_<q>, 0 bis 8), sonst die Zahl als Text. Gesperrt oder keine Zahl: „?“.
-- Core.QualityText(q): derselbe Name in der Farbe der Qualität (Core.QualityHex).
function Core.QualityName(quality)
    if Core.IsSecret(quality) then return "?" end
    local q = Core.Num(quality)
    if not q then return "?" end
    q = floor(q)
    local blizzard = rawget(_G, "ITEM_QUALITY" .. q .. "_DESC")
    if type(blizzard) == "string" and not Core.IsSecret(blizzard) and blizzard ~= "" then return blizzard end
    local key = "QUALITY_NAME_" .. q
    local own = Core.L[key]
    if type(own) == "string" and own ~= key then return own end
    return tostring(q)
end

function Core.QualityText(quality)
    return Core.QualityHex(quality) .. Core.QualityName(quality) .. "|r"
end

-- Farbcode „|cffrrggbb“ aus r, g, b (0 bis 1).
function Core.ColorCode(r, g, b)
    local function Byte(v) return math.max(0, math.min(255, floor((Core.Num(v) or 1) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b))
end

-- Farbe der Klasse – eine Quelle für alle Klassenfarben: CUSTOM_CLASS_COLORS (Farb-Addons) hat Vorrang,
-- dann Blizzards C_ClassColor, dann RAID_CLASS_COLORS. Tabelle mit r, g, b (oder nil).
function Core.ClassColor(class)
    if type(class) ~= "string" or Core.IsSecret(class) then return nil end
    local custom = rawget(_G, "CUSTOM_CLASS_COLORS")
    if type(custom) == "table" and type(custom[class]) == "table" and custom[class].r then return custom[class] end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(class)
        if color then return color end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

-- r, g, b der Klasse; unbekannt: Gold.
function Core.ClassRGB(class)
    local c = Core.ClassColor(class)
    if c and c.r then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

-- Text in Klassenfarbe.
function Core.ClassText(text, class)
    local color = Core.ClassColor(class)
    if not color then return text end
    if color.WrapTextInColorCode then return color:WrapTextInColorCode(text) end
    if color.colorStr then return "|c" .. color.colorStr .. text .. "|r" end
    if color.r then return Core.ColorCode(color.r, color.g, color.b) .. text .. "|r" end
    return text
end

function Core.ClassName(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" and names[token] then return names[token] end
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        for id = 1, 20 do
            local info = C_CreatureInfo.GetClassInfo(id)
            if info and info.classFile == token then return info.className end
        end
    end
    return token
end

-- Lokalisierter Klassenname („Magierin“, „Mage“) → Klassen-Token („MAGE“); nil, wenn unbekannt.
local classTokens
function Core.ClassToken(name)
    if type(name) ~= "string" or Core.IsSecret(name) or name == "" then return nil end
    if name:upper() == name and RAID_CLASS_COLORS and RAID_CLASS_COLORS[name] then return name end
    if not classTokens then
        classTokens = {}
        for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
            if type(list) == "table" then
                for token, text in pairs(list) do classTokens[text] = token end
            end
        end
    end
    return classTokens[name]
end

Core.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
Core.RACES = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll" }
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }

function Core.RaceName(token)
    local id = RACE_IDS[token]
    if id and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local info = C_CreatureInfo.GetRaceInfo(id)
        if info and type(info.raceName) == "string" then return info.raceName end
    end
    return L["RACE_" .. token]
end
