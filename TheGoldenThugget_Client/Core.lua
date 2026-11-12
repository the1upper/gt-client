-- The Golden Thugget: Core — namespace, events, names, money, saved variables, slash commands
local addonName, ns = ...

-- Two builds share this code: "Golden Thugget Client" and "Golden Thugget Host"
-- (the host includes everything the client does). Enable one per character.
-- If both are enabled the Host loads first (Client lists it as OptionalDeps),
-- and the Client copy switches itself off here.
if _G.GoldenThugget then
	ns.skip = true
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37Golden Thugget|r: " .. (_G.GoldenThugget.isHostBuild and "Host" or "another copy")
			.. " is enabled on this character, so " .. addonName .. " is staying off. You can disable it in the AddOns list.")
	end)
	return
end

ns.name = addonName
ns.isHostBuild = addonName:find("_Host", 1, true) ~= nil
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
ns.version = "3.17.0"
-- Protocol version: bumped whenever clients and the house must match.
-- The house refuses clients below its minimum and tells them to update.
ns.PROTO = 9 -- 8: spectators, live table listings; 9: Texas Hold'em
_G.GoldenThugget = ns

local floor, abs = math.floor, math.abs

---------------------------------------------------------------------------
-- Event dispatcher
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(frame.RegisterEvent, frame, event) -- ignore events this client doesn't have
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then geterrorhandler()(err) end
	end
end)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local TAG = "|cffd4af37The Golden Thugget|r: "

function ns.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	if not (ns.db and ns.db.settings.quiet) then DEFAULT_CHAT_FRAME:AddMessage(TAG .. msg) end
	ns.Log(msg)
end

-- Always reaches chat, even in quiet mode (your turn, warnings, refusals, results)
function ns.Notify(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	DEFAULT_CHAT_FRAME:AddMessage(TAG .. msg)
	ns.Log(msg)
end

-- Log to the addon window(s) only (keeps chat quieter)
ns.logSinks = {}
function ns.Log(msg)
	for _, sink in ipairs(ns.logSinks) do sink(msg) end
end

---------------------------------------------------------------------------
-- Names: everything internal is "Name-Realm" with realm spaces removed
---------------------------------------------------------------------------
local function normRealm(r)
	return (r or ""):gsub("[%s%-']", "")
end
ns.NormRealm = normRealm

-- WoW Forever: one realm per ruleset, and characters have two names
-- ("First Last"). There UnitName("player") returns first name + surname, and chat
-- and addon messages name players "First Last". Everywhere else names are
-- "Name-Realm". ns.forever is set at login.
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function cap(word) return word:sub(1, 1):upper() .. word:sub(2):lower() end

-- For names that come from the game API (already correctly cased)
function ns.Full(name)
	if not name or name == "" then return nil end
	if ns.forever then
		name = trim(name):gsub("%-.*$", "") -- drop any realm suffix
		return name ~= "" and name or nil
	end
	local n, r = name:match("^([^%-]+)%-(.+)$")
	if n then return n .. "-" .. normRealm(r) end
	return name .. "-" .. (ns.realm or "")
end

-- For names a human typed: fixes capitalisation
function ns.CleanName(input)
	if not input then return nil end
	input = trim(input)
	if input == "" then return nil end
	if ns.forever then
		input = input:gsub("%-.*$", "")
		local parts = {}
		for w in input:gmatch("%S+") do parts[#parts + 1] = cap(w) end
		return table.concat(parts, " ")
	end
	local n, r = input:match("^([^%-]+)%-(.+)$")
	n = cap(n or input)
	if r then return n .. "-" .. normRealm(r) end
	return n .. "-" .. (ns.realm or "")
end

-- Short display name: drop realm when it's ours (Forever names are shown whole)
function ns.Short(full)
	if not full then return "?" end
	if ns.forever then return full end
	local n, r = full:match("^([^%-]+)%-(.+)$")
	if n and r == ns.realm then return n end
	return full
end

local function looksLikeMoney(w)
	return w and (w:match("^[%+%-]?%d") ~= nil)
end

-- Read a player name from command words starting at i. In Forever a name is
-- two words ("Bob Stone"). Returns name, index of the next word.
function ns.TakeName(words, i)
	local w1, w2 = words[i], words[i + 1]
	if not w1 then return nil, i end
	if ns.forever and w2 and not looksLikeMoney(w2) and not w1:find("-", 1, true) then
		return ns.CleanName(w1 .. " " .. w2), i + 2
	end
	return ns.CleanName(w1), i + 1
end

-- "Bob Stone, Amy Fields" -> list of names
function ns.NameList(text)
	local t = {}
	for part in (text or ""):gmatch("[^,;]+") do
		local n = ns.CleanName(part)
		if n then t[#t + 1] = n end
	end
	return t
end

---------------------------------------------------------------------------
-- Money (ledger, wagers and bets are all copper)
---------------------------------------------------------------------------
-- Money on screen: the number followed by WoW's own coin icon (like the money
-- frame). /gt coins switches back to colored letters (gold yellow, silver grey,
-- copper bronze).
ns.COIN_COLOR = { g = "ffd100", s = "c7c7cf", c = "eda55f" }
ns.COIN_ICON = {
	g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
function ns.ColorCoins(text)
	local letters = ns.db and ns.db.settings and ns.db.settings.coinText
	return (tostring(text):gsub("%f[%w](%d+)([gsc])%f[%W]", function(n, u)
		if letters then return "|cff" .. ns.COIN_COLOR[u] .. n .. u .. "|r" end
		return "|cffffffff" .. n .. "|r" .. ns.COIN_ICON[u]
	end))
end

---------------------------------------------------------------------------
-- Class colors for names. Classes are learned from what the game shows you:
-- your guild roster, your group, your target / mouseover, and anyone who
-- chats near you. They're remembered between sessions.
---------------------------------------------------------------------------
function ns.SetClass(name, cls)
	if not (name and cls and ns.db and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]) then return end
	name = ns.CleanName(name)
	if name and name ~= "" then ns.db.classes[name] = cls end
end

-- A name for the screen, in its class color when we know it
function ns.Who(name)
	local s = ns.Short(name)
	local cls = name and ns.db and ns.db.classes and ns.db.classes[name]
	local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	if not c then return s end
	return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), s)
end

local function unitFullName(unit)
	local n, r = UnitName(unit)
	if not n or n == "" then return end
	if ns.forever then
		if not r or r == "" then return end -- need both halves of a Forever name
		return n .. " " .. r
	end
	return (r and r ~= "") and (n .. "-" .. r) or n
end

function ns.LearnUnit(unit)
	if not (UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit)) then return end
	local _, cls = UnitClass(unit)
	ns.SetClass(unitFullName(unit), cls)
end

local lastGuildScan = -100
function ns.LearnGuild()
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
	local now = GetTime()
	if now - lastGuildScan < 10 then return end
	lastGuildScan = now
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, _, _, cls = GetGuildRosterInfo(i)
		ns.SetClass(name, cls)
	end
end

function ns.LearnGroup()
	ns.LearnUnit("player")
	for i = 1, 4 do ns.LearnUnit("party" .. i) end
	for i = 1, 40 do ns.LearnUnit("raid" .. i) end
end

local function learnChat(_, _, _, author, _, _, _, _, _, _, _, _, _, guid)
	if not (author and guid and guid ~= "" and GetPlayerInfoByGUID) then return end
	local _, cls = GetPlayerInfoByGUID(guid)
	ns.SetClass(author, cls)
end

function ns.StartClassWatch()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
		"CHAT_MSG_WHISPER", "CHAT_MSG_GUILD", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY",
		"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function(self, e, ...)
		if e == "GUILD_ROSTER_UPDATE" then ns.LearnGuild()
		elseif e == "GROUP_ROSTER_UPDATE" then ns.LearnGroup()
		elseif e == "PLAYER_TARGET_CHANGED" then ns.LearnUnit("target")
		elseif e == "UPDATE_MOUSEOVER_UNIT" then ns.LearnUnit("mouseover")
		else learnChat(self, e, ...) end
	end)
	ns.LearnGroup()
	if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
	ns.LearnGuild()
end

-- Money for the screen (colored). Use ns.MoneyPlain for edit boxes and anything stored or sent.
function ns.Money(c)
	return ns.ColorCoins(ns.MoneyPlain(c))
end

function ns.MoneyPlain(c)
	c = floor((c or 0) + 0.5)
	local neg = c < 0
	c = abs(c)
	local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
	local t = {}
	if g > 0 then t[#t + 1] = g .. "g" end
	if s > 0 then t[#t + 1] = s .. "s" end
	if cp > 0 then t[#t + 1] = cp .. "c" end
	if #t == 0 then t[1] = "0g" end
	return (neg and "-" or "") .. table.concat(t, " ")
end

-- "3.11.0" >= "3.9.2"? (missing or odd versions count as old)
function ns.VersionAtLeast(v, want)
	local a, b = {}, {}
	for n in tostring(v or ""):gmatch("%d+") do a[#a + 1] = tonumber(n) end
	for n in tostring(want):gmatch("%d+") do b[#b + 1] = tonumber(n) end
	if #a == 0 then return false end
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then return x > y end
	end
	return true
end
ns.WATCH_SINCE = "3.11.0" -- the house needs this version for spectators
ns.REVIEW_SINCE = "3.13.0" -- ...and this one to send tables you didn't see

-- Results, the same way everywhere: green "won 50s", red "lost 25s"
function ns.WonLost(c)
	if not c or c == 0 then return "|cff9e948aeven|r" end
	return c > 0 and ("|cff59d959won|r " .. ns.Money(c)) or ("|cffff6161lost|r " .. ns.Money(-c))
end

-- One line per player, biggest winner first: "Pl1 Stone  won 50s  (Pair of Ks)"
function ns.PayoutLines(net, notes)
	local list = {}
	for p, c in pairs(net) do list[#list + 1] = { p = p, c = c } end
	table.sort(list, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.p < b.p end)
	local out = {}
	for i, x in ipairs(list) do
		local note = notes and notes[x.p]
		out[i] = ns.Short(x.p) .. "  " .. ns.WonLost(x.c) .. (note and ("  |cff9e948a(" .. note .. ")|r") or "")
	end
	return out
end

-- The line that tells you what to do about it
function ns.YouLine(c)
	if not c or c == 0 then return "You broke even." end
	return c > 0 and ("You |cff59d959won|r " .. ns.Money(c) .. " - the house will pay you.")
		or ("You |cffff6161lost|r " .. ns.Money(-c) .. " - send it to the house when you can (/gt pay).")
end

-- "150" -> 150 gold; "1g50s", "2g 3s 4c" also accepted. Returns copper or nil.
function ns.ParseMoney(str)
	if not str then return nil end
	str = str:lower():gsub("%s+", "")
	if str == "" then return nil end
	local n = tonumber(str)
	if n then return floor(n * 10000 + 0.5) end
	local total, found = 0, false
	for num, unit in str:gmatch("(%d+%.?%d*)([gsc])") do
		found = true
		num = tonumber(num)
		total = total + num * (unit == "g" and 10000 or unit == "s" and 100 or 1)
	end
	if found and total > 0 then return floor(total + 0.5) end
	return nil
end

---------------------------------------------------------------------------
-- Shared protocol helpers (used by the client and the host addon)
---------------------------------------------------------------------------
-- Message = fields joined by "^"
function ns.Split(msg)
	local t = {}
	for field in (msg .. "^"):gmatch("([^%^]*)%^") do t[#t + 1] = field end
	return t
end

function ns.Join(...)
	local t = {}
	for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
	return table.concat(t, "^")
end

-- Comma lists. KeepEmpty preserves positions ("a,,c" -> {"a","","c"}).
function ns.List(str, keepEmpty)
	local t = {}
	if not str or str == "" then return t end
	if keepEmpty then
		for v in (str .. ","):gmatch("([^,]*),") do t[#t + 1] = v end
	else
		for v in str:gmatch("[^,]+") do t[#t + 1] = v end
	end
	return t
end

function ns.IndexOf(list, v)
	for i, x in ipairs(list) do if x == v then return i end end
end

function ns.ShortList(list)
	local t = {}
	for i, n in ipairs(list) do t[i] = ns.Short(n) end
	return table.concat(t, ", ")
end

function ns.RouteFromVia(via)
	if via == "WHISPER" or via == "BN" then return "WHISPER" end
	if via == "GUILD" or via == "OFFICER" then return "GUILD" end
	if via == "CHANNEL" then return "CHANNEL" end
	return "GROUP"
end

ns.ROUTE_LABEL = { GUILD = "Guild", GROUP = "Party/Raid", CHANNEL = "Channel", WHISPER = "Whisper/BNet" }

local counter = 0
function ns.NewSecret()
	counter = counter + 1
	return ns.SHA256(table.concat({
		tostring(math.random()), tostring(math.random()), tostring(math.random()),
		tostring(GetTime()), tostring(time()), tostring(debugprofilestop and debugprofilestop() or 0),
		tostring(ns.me), tostring(counter),
	}, "|")):sub(1, 32)
end

function ns.NewId()
	counter = counter + 1
	return ("%x%04x%x"):format(time(), math.random(0, 65535), counter % 16)
end

function ns.CommitHash(id, name, secret)
	return ns.SHA256(id .. "|" .. name .. "|" .. secret):sub(1, 32) -- 128 bits is plenty to bind a secret
end

-- Seed = sha256(id - secrets of everyone who revealed, in roster order)
function ns.Seed(id, players, secrets, forfeits)
	local fset = {}
	for _, n in ipairs(forfeits or {}) do fset[n] = true end
	local t = { id }
	for i, p in ipairs(players) do
		if not fset[p] then t[#t + 1] = secrets[i] or secrets[p] or "" end
	end
	return ns.SHA256(table.concat(t, "|"))
end

-- Shown on mail so the host can credit the right player even from an alt
ns.MAIL_TAG = "GT:"

-- Fill the Send Mail tab (works at any mailbox)
function ns.FillMail(to, copper, subject)
	if not (SendMailFrame and SendMailFrame:IsShown()) then
		ns.Print("Open the Send Mail tab at a mailbox first, then click again.")
		return false
	end
	SendMailNameEditBox:SetText(ns.Short(to))
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject or "") end
	if SendMailSendMoneyButton and SendMailSendMoneyButton.Click then SendMailSendMoneyButton:Click() end
	if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
	ns.Print(("Mail filled: %s to %s. Check it and press Send."):format(ns.Money(copper), ns.Short(to)))
	return true
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
	host = "Toilet Bowl",   -- the house: only its tables and ledger are trusted (/gt host to change)
	channel = "GoldenThugget",
	quiet = false,          -- true: only your turns, results and warnings go to chat
	alerts = true,          -- pop-up card when the house opens a table and /gt is closed
}

local function initDB()
	local db
	if ns.isHostBuild then -- the host build keeps everything in its own file
		GoldenThuggetHostDB = GoldenThuggetHostDB or {}
		GoldenThuggetHostDB.client = GoldenThuggetHostDB.client or {}
		db = GoldenThuggetHostDB.client
	else
		GoldenThuggetDB = GoldenThuggetDB or {}
		db = GoldenThuggetDB
	end
	db.settings = db.settings or {}
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	db.cache = db.cache or {}       -- last ledger snapshot per host
	db.myGames = db.myGames or {}   -- per character: games this character played
	db.classes = db.classes or {}   -- name -> class file ("MAGE"), for colored names
	db.settings.pos = db.settings.pos or {} -- window positions
	ns.db = db
end

---------------------------------------------------------------------------
-- Slash commands (client)
---------------------------------------------------------------------------
local HELP = {
	"|cffffd100/gt|r - open/close the window",
	"|cffffd100/gt join [id]|r - join the host's newest (or given) open table",
	"|cffffd100/gt leave|r - leave the table before it locks",
	"|cffffd100/gt balance|r - your balance with the house,  |cffffd100/gt ledger|r - everyone's,  |cffffd100/gt top|r - lifetime leaderboard",
	"|cffffd100/gt pay|r - at a mailbox: fill a mail to the host for what you owe",
	"|cffffd100/gt table|r - show/hide the table window,  |cffffd100/gt quiet|r - quiet chat on/off,  |cffffd100/gt alerts|r - new-table pop-ups on/off,  |cffffd100/gt watch|r - watch the newest table",
	"|cffffd100/gt coins|r - coin icons or g/s/c letters for money,  |cffffd100/gt resetpos|r - put every Golden Thugget window back in the middle",
	"|cffffd100/gt host <First Last>|r - set which player is the house (only their tables/ledger are trusted)",
	"|cffffd100/gt channel <name>|r - custom channel name (must match the host's)",
	"|cffffd100/gt speedtest <First Last>|r - measure how fast addon whispers get through to another character (both need v3.14.2+; the full-size phase needs v3.14.3)",
}

local function words(msg)
	local t = {}
	for w in msg:gmatch("%S+") do t[#t + 1] = w end
	return t
end

local function slash(msg)
	local a = words(msg or "")
	local cmd = (a[1] or ""):lower()
	local C = ns.Client
	if cmd == "" then
		ns.ClientUI:Toggle()
	elseif cmd == "help" then
		for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage(line) end
	elseif cmd == "join" then
		C:Join(a[2])
	elseif cmd == "leave" or cmd == "cancel" then
		C:Leave()
	elseif cmd == "balance" or cmd == "bal" then
		C:PrintBalance()
		C:RequestLedger(true)
	elseif cmd == "ledger" then
		C:PrintLedger()
		C:RequestLedger(true)
	elseif cmd == "top" or cmd == "leaderboard" then
		C:PrintBoard()
		C:RequestLedger(true)
	elseif cmd == "pay" then
		C:PayHost()
	elseif cmd == "quiet" then
		local v = (a[2] or ""):lower()
		C:SetQuiet(v == "on" or (v == "" and not ns.db.settings.quiet))
	elseif cmd == "speedtest" then
		ns.SpeedTest:Start(a[2] and ns.TakeName(a, 2))
	elseif cmd == "version" or cmd == "ver" then
		local hv
		for _, x in pairs(ns.Client.lobby) do hv = x.houseVersion or hv end
		ns.Notify(("Your addon: %s.  The house: %s."):format(ns.version, hv or "unknown (no table open)"))
	elseif cmd == "watch" then
		ns.Client:Watch(a[2])
	elseif cmd == "alerts" then
		local v = (a[2] or ""):lower()
		ns.db.settings.alerts = v == "on" or (v == "" and ns.db.settings.alerts == false)
		ns.Notify("New-table pop-ups " .. (ns.db.settings.alerts and "on." or "off."))
	elseif cmd == "coins" then
		ns.db.settings.coinText = not ns.db.settings.coinText
		ns.Notify("Money shows as " .. (ns.db.settings.coinText and "letters (1g 50s)." or "coin icons.") .. " Windows update as they refresh.")
		if ns.ClientUI then ns.ClientUI:Refresh() end
		if ns.HostUI then ns.HostUI:Refresh() end
	elseif cmd == "resetpos" then
		ns.W.ResetPositions()
		ns.Notify("Window positions reset.")
	elseif cmd == "table" or cmd == "cards" then
		ns.ClientUI:ShowTableWindow()
	elseif cmd == "host" then
		if a[2] then
			ns.db.settings.host = ns.TakeName(a, 2)
			ns.Print("Host set to " .. ns.db.settings.host .. ".")
			C:RequestLedger(true)
		else
			ns.Print("Host: " .. (ns.db.settings.host or "not set (first host you hear is trusted)"))
		end
	elseif cmd == "channel" then
		if a[2] then
			ns.Comm:LeaveChannel()
			ns.db.settings.channel = a[2]
			ns.Comm:EnsureChannel()
		end
		ns.Print("Custom channel: " .. ns.db.settings.channel)
	else
		ns.Print("Unknown command. /gt help")
	end
end

---------------------------------------------------------------------------
-- Startup. The host addon (TheGoldenThugget_Host) registers its own PLAYER_LOGIN
-- handler after this one, so the shared pieces are ready when it runs.
---------------------------------------------------------------------------
ns.On("PLAYER_LOGIN", function()
	local first, second = UnitName("player")
	ns.forever = second ~= nil and second ~= ""
	if ns.forever then
		ns.realm = ""
		local full = GetUnitName and GetUnitName("player", true)
		ns.me = (full and full:find(" ", 1, true)) and full or (first .. " " .. second)
	else
		ns.realm = normRealm((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName())
		ns.me = first .. "-" .. ns.realm
	end
	initDB()
	ns.Comm:Init()
	ns.Comm.handlers = {}
	ns.Comm.handler = function(sender, msg, via)
		local f = ns.Split(msg)
		for _, h in ipairs(ns.Comm.handlers) do
			if h(sender, f, via) then return end
		end
	end
	ns.StartClassWatch()
	ns.Client:Init()
	ns.ClientUI:Init()
	ns.CardUI:Init()

	SLASH_GOLDENTHUGGET1 = "/gt"
	SLASH_GOLDENTHUGGET2 = "/thugget"
	SlashCmdList.GOLDENTHUGGET = slash
	ns.Print("v" .. ns.version .. " loaded. /gt to open, /gt help for commands.")
end)

ns.Slash = slash
