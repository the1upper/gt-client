-- The Golden Thugget: Client — joins the host's tables, takes part in the fair roll,
-- and shows the host's ledger. The client never keeps its own ledger: the host's
-- book is the only one, so there is nothing to get out of sync.
--
-- Roll protocol (everything goes through the host, so players never need to reach
-- each other — only the host):
--   host ANN -> client JOIN -> host LOCK (final roster)
--   client CMT  = sha256(id|name|secret)          (sealed roll)
--   host   CMTS = every commitment, in roster order
--   client checks its own commitment is in the list, then reveals SEC
--   host   RES  = all secrets + forfeits + result fingerprint
--   client verifies every secret against its commitment and recomputes the result itself.
local _, ns = ...
if ns.skip then return end
local C = {}
ns.Client = C
C.lobby = {}

local NEED_AFTER, STALE_AFTER, LOBBY_TTL = 15, 150, 50
local AUTO_ROLL = 40 -- seconds before an un-clicked Roll rolls itself
local J = function(...) return ns.Join(...) end

local function refresh()
	if C.SyncTables then C:SyncTables() end
	if ns.ClientUI and ns.ClientUI.Refresh then ns.ClientUI:Refresh() end
	if ns.DiceUI and ns.DiceUI.Refresh then ns.DiceUI:Refresh() end
end

---------------------------------------------------------------------------
-- Table list: every table heard about this session, newest first.
--   status: "open" | "live" (in progress) | "closed" | "cancelled"
-- Tables you played or watched keep their final state, so Review can reopen them.
---------------------------------------------------------------------------
C.tables = {}
local KEEP_TABLES = 30

function C:TrackTable(id, a)
	if not id then return end
	local r = self.tables[id]
	if not r then
		r = { id = id, first = GetTime(), status = "open", players = {} }
		self.tables[id] = r
		-- forget the oldest beyond the cap (never the table you're at)
		local list = {}
		for _, x in pairs(self.tables) do list[#list + 1] = x end
		if #list > KEEP_TABLES then
			table.sort(list, function(p, q) return p.first < q.first end)
			for i = 1, #list - KEEP_TABLES do
				if not (self.game and self.game.id == list[i].id) then self.tables[list[i].id] = nil end
			end
		end
	end
	if a then
		r.type = a.type or r.type
		r.wager = a.wager or r.wager
		r.param = a.param or r.param
		r.route = a.route or r.route
		r.max = a.max or r.max
		r.hands = a.hands or r.hands
	end
	return r
end

local function setStatus(r, s)
	if not r or r.status == s then return end
	if r.status == "closed" and s ~= "closed" then return end -- a finished table stays finished
	r.status = s
	if s == "closed" or s == "cancelled" then r.endedAt = r.endedAt or time() end
end
C.SetTableStatus = function(_, r, s) setStatus(r, s) end

-- one-line result for a finished game object
function C:GameSummary(g)
	if g.result and g.result.summary then return g.result.summary end
	local c = g.cards
	if c and c.deltas then
		local parts = {}
		for p, d in pairs(c.deltas) do
			if d ~= 0 then parts[#parts + 1] = ns.Short(p) .. " " .. (d > 0 and "+" or "-") .. ns.Money(math.abs(d)) end
		end
		table.sort(parts)
		return #parts > 0 and table.concat(parts, ", ") or "Everyone broke even"
	end
end

-- Your own table (played or watched) is the most accurate source for its row
function C:SyncTables()
	local g = self.game
	if not (g and g.id and g.type) or g.review then return end
	local r = self:TrackTable(g.id, g)
	if #(g.players or {}) > 0 then r.players = g.players end
	if g.watching then r.watched = true elseif ns.IndexOf(g.players or {}, ns.me) then r.mine = true end
	if g.phase == "commit" or g.phase == "reveal" or g.phase == "playing" then
		setStatus(r, "live")
	elseif g.phase == "done" then
		if g.dice and not g.dice.done then
			setStatus(r, "live") -- the result is fixed but the dice are still rolling
		else
			setStatus(r, "closed")
			r.game = g
			r.summary = self:GameSummary(g) or r.summary
			if r.mine then r.delta = g.delta or (g.cards and g.cards.deltas and g.cards.deltas[ns.me]) or 0 end
		end
	end
end

-- Tables to show: the one you're at (or the newest open one) first, then the rest
function C:TableList()
	local list = {}
	for _, r in pairs(self.tables) do if r.type and ns.Games.types[r.type] then list[#list + 1] = r end end
	table.sort(list, function(a, b) return a.first > b.first end)
	local top
	local g = self:Busy()
	if g then for i, r in ipairs(list) do if r.id == g.id then top = i break end end end
	if not top then for i, r in ipairs(list) do if r.status == "open" or r.status == "live" then top = i break end end end
	if top and top > 1 then table.insert(list, 1, table.remove(list, top)) end
	return list
end

-- Reopen a finished table as it ended. Tables you played or watched this session
-- open from your own copy; anything else is fetched from the house.
local REVIEW_WAIT = 15
function C:Review(id)
	local r = self.tables[id]
	if not r then return end
	if self:Busy() then return ns.Print("Finish or leave your current table first.") end
	if r.game then
		self.game = r.game
		self:OpenTable()
		return refresh()
	end
	if not self:CanFetch(r) then return ns.Print("The house doesn't have that table to send.") end
	if r.fetching then return end
	r.fetching, r.openWhenReady = GetTime(), true
	self:ToHost(J("RQ", id), "WHISPER")
	C_Timer.After(REVIEW_WAIT, function()
		if r.fetching and GetTime() - r.fetching >= REVIEW_WAIT - 0.5 then
			r.fetching, self.rvbuf[id] = nil, nil
			ns.Print("The house didn't send that table. It may be offline, or on a version before " .. ns.REVIEW_SINCE .. ".")
			refresh()
		end
	end)
	refresh()
end

-- Could the house send this table? (its version, and what it told us it kept)
function C:CanFetch(r)
	if r.status ~= "closed" or r.remote == false then return false end
	if self.houseVersion and not ns.VersionAtLeast(self.houseVersion, ns.REVIEW_SINCE) then return false end
	return true
end

-- Ask the house for its recent tables (once a minute at most)
function C:RequestHistory(force)
	local now = GetTime()
	if not force and self.histAt and now - self.histAt < 60 then return end
	if not self:Host() then return end
	if self.houseVersion and not ns.VersionAtLeast(self.houseVersion, ns.REVIEW_SINCE) then return end
	self.histAt = now
	self:ToHost(J("RL"), "WHISPER")
end


-- Open the right window for self.game
function C:OpenTable()
	local g = self.game
	local def = g and ns.Games.types[g.type]
	if not def then return end
	if def.ui == "hand" then if g.cards then ns.HandUI:Open() end
	elseif def.ui == "holdem" then if g.cards then ns.HoldemUI:Open() end
	elseif def.kind == "cards" then if g.cards then ns.CardUI:Open() end
	else ns.DiceUI:Open() end
end

---------------------------------------------------------------------------
-- host / cache
---------------------------------------------------------------------------
function C:Host() return ns.db.settings.host end

function C:Cache()
	local h = self:Host() or "?"
	local c = ns.db.cache[h]
	if not c then
		c = { balances = {}, history = {}, board = {}, ts = 0 }
		ns.db.cache[h] = c
	end
	return c
end

function C:MyGames()
	local t = ns.db.myGames[ns.me]
	if not t then t = {}; ns.db.myGames[ns.me] = t end
	return t
end

function C:Balance() return self:Cache().balances[ns.me] or 0 end

-- Send to the host: over the table's route if it's a shared one, else direct.
function C:ToHost(msg, route)
	local host = self:Host()
	if not host then return false end
	if host == ns.me then -- we are the house: loop back to our own host half
		if ns.HostInbox then
			C_Timer.After(0, function() ns.HostInbox(ns.me, ns.Split(msg), "LOCAL") end)
			return true
		end
		return false
	end
	route = route or (self.game and self.game.route) or self.lastRoute
	-- guild / group: answer on the same route. Whisper and Channel tables: whisper the
	-- house (Forever never delivers addon messages sent to a chat channel).
	if route and route ~= "WHISPER" and route ~= "CHANNEL" and ns.Comm:SendRoute(msg, route) then return true end
	ns.Comm:SendTo(msg, host)
	return true
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
-- Table windows: hide now, or a few seconds after the table finishes
function C:HideTables()
	for _, w in ipairs({ ns.DiceUI, ns.HandUI, ns.CardUI, ns.HoldemUI }) do
		if w and w.frame and w.frame:IsShown() then w.frame:Hide() end
	end
end
C.CLOSE_DELAY = 5
function C:CloseTableSoon(g)
	if g.closeAt then return end
	g.closeAt = GetTime() + self.CLOSE_DELAY
	refresh()
	for _, w in ipairs({ ns.DiceUI, ns.HandUI, ns.CardUI, ns.HoldemUI }) do if w and w.Refresh then w:Refresh() end end
	-- the countdown waits while the mouse is over a table window (still reading)
	-- (the button just says Close while paused, then counts down from 2 once you move away)
	local function tryClose()
		if self.game ~= g then return end -- not if they've moved on to another table
		local now = GetTime()
		if self:TableHovered() then
			g.closeAt = now + 2
			C_Timer.After(0.5, tryClose)
			return
		end
		if now < (g.closeAt or now) - 0.05 then
			C_Timer.After(g.closeAt - now, tryClose)
			return
		end
		self:HideTables()
	end
	C_Timer.After(self.CLOSE_DELAY, tryClose)
end

-- The Leave button doubles as Close (with the countdown) once the table is over.
-- The button ticks its own countdown, so it never depends on a window refresh.
-- the mouse is over an open table window (the close countdown waits)
function C:TableHovered()
	for _, w in ipairs({ ns.DiceUI, ns.HandUI, ns.CardUI, ns.HoldemUI }) do
		local f = w and w.frame
		if f and f:IsShown() and f.IsMouseOver and f:IsMouseOver() then return true end
	end
	return false
end
local function closeText(g)
	if g.closeAt and C:TableHovered() then return "Close" end -- paused while you read
	local left = g.closeAt and math.max(0, math.ceil(g.closeAt - GetTime())) or 0
	return left > 0 and ("Close (" .. left .. ")") or "Close"
end
local cc = setmetatable({}, { __mode = "k" }) -- button -> countdown state
local function tickClose(btn, el)
	local st = cc[btn]
	if not st then return btn:SetScript("OnUpdate", nil) end
	st.acc = st.acc + el
	if st.acc < 0.1 then return end
	st.acc = 0
	local t = closeText(st.g)
	if t ~= st.text then st.text = t; btn:SetText(t) end
end
function C:SetLeaveButton(btn, g, canLeave, label)
	if g and (g.closeAt or g.phase == "aborted") then
		local st = cc[btn]
		if not st or st.g ~= g then
			st = { g = g, acc = 0 }
			cc[btn] = st
		end
		if g.closeAt and not st.ticking then st.ticking = true; btn:SetScript("OnUpdate", tickClose) end
		st.text = closeText(g)
		btn:SetText(st.text)
		btn:SetEnabled(true)
	else
		if cc[btn] then cc[btn] = nil; btn:SetScript("OnUpdate", nil) end
		btn:SetText((g and g.watching and "Stop watching") or label or "Leave")
		btn:SetEnabled((canLeave or (g and g.watching)) and true or false)
	end
end
function C:LeaveOrClose()
	local g = self.game
	if g and g.watching and not g.closeAt then return self:StopWatching() end
	if g and (g.closeAt or g.phase == "aborted") then return self:HideTables() end
	self:Leave()
end

-- Why this player can't join a table right now (nil = they can)
function C:JoinBlock(a)
	if a.outdated then
		return ("Your Golden Thugget Client (v%s) is out of date - the house runs v%s. Get the latest from the house."):format(ns.version, a.houseVersion or "?")
	end
	if a.limit and a.limit > 0 and self:Host() ~= ns.me then
		local owe = -math.min(0, self:Balance())
		local worst = ns.Games.WorstCase(a)
		if owe + worst > a.limit then
			return ("Over your credit limit: you owe the house %s and this table could cost up to %s (limit %s). Pay at any mailbox to play again."):format(
				ns.Money(owe), ns.Money(worst), ns.Money(a.limit))
		end
	end
end

function C:Join(id)
	if not self:Host() then return ns.Print("No house yet. Set one with /gt host <First Last>, or wait for the house to open a table.") end
	if self.game and self.game.watching then self:StopWatching(true) end
	if self.game and self.game.phase ~= "done" and self.game.phase ~= "aborted" then
		return ns.Print("You're already at a table. /gt leave first.")
	end
	local a
	if id and id ~= "" then a = self.lobby[id] else
		for _, x in pairs(self.lobby) do if not a or x.seen > a.seen then a = x end end
	end
	if not a then return ns.Print("No open table from the house right now.") end
	local block = self:JoinBlock(a)
	if block then return ns.Notify(block) end
	self.game = {
		id = a.id, type = a.type, wager = a.wager, param = a.param, route = a.route, hands = a.hands,
		players = {}, phase = "open", touched = GetTime(),
	}
	self:ToHost(J("JOIN", a.id, ns.PROTO), a.route)
	ns.Print(("Joining: %s. %s"):format(ns.Games.types[a.type].describe(a), ns.Games.WorstText(a)))
	if ns.ClientUI and ns.ClientUI.HideToast then ns.ClientUI:HideToast() end
	refresh()
end

---------------------------------------------------------------------------
-- Spectating: follow any table (open or in progress) without playing.
-- You see what the players see in public; nobody's private cards or dice.
---------------------------------------------------------------------------
function C:Watch(id)
	if not self:Host() then return ns.Print("No house yet.") end
	local g = self.game
	if g and g.watching then
		if g.id == id then return self:ShowWatched() end
		self:StopWatching(true)
	elseif self:Active() then
		return ns.Print("You're at a table. Leave it first to watch another.")
	end
	local a = id and self.lobby[id]
	if not a then
		for _, x in pairs(self.lobby) do if not a or x.seen > a.seen then a = x end end
	end
	if not a then return ns.Print("No table to watch right now.") end
	if a.houseVersion and not ns.VersionAtLeast(a.houseVersion, ns.WATCH_SINCE) then
		return ns.Notify(("The house is on Golden Thugget %s. Watching needs the house on %s or newer."):format(a.houseVersion, ns.WATCH_SINCE))
	end
	self.game = {
		id = a.id, type = a.type, wager = a.wager, param = a.param, route = a.route, hands = a.hands,
		players = {}, phase = "open", touched = GetTime(), watching = true,
	}
	self:ToHost(J("WATCH", a.id), a.route)
	ns.Notify(("Watching %s %s."):format(ns.Games.types[a.type].name, ns.Money(a.wager)))
	if ns.ClientUI and ns.ClientUI.HideToast then ns.ClientUI:HideToast() end
	refresh()
end

function C:ShowWatched() return self:OpenTable() end

function C:StopWatching(quiet)
	local g = self.game
	if not (g and g.watching) then return end
	self:ToHost(J("UNWATCH", g.id))
	g.phase = "aborted"
	self:HideTables()
	self.game = nil
	if not quiet then ns.Print("Stopped watching.") end
	refresh()
end

function C:Leave()
	local g = self.game
	if g and g.watching then return self:StopWatching() end
	if not g or g.phase == "done" or g.phase == "aborted" then return ns.Print("You're not at a table.") end
	if g.phase == "open" then
		self:ToHost(J("LEAVE", g.id))
		ns.Print("Left the table.")
	elseif g.phase == "playing" and g.type == "holdem" then
		-- Hold'em seats are fixed: step away instead (check/fold, still posting blinds)
		self:ToHost(J("HAWAY", g.id))
		return ns.Print("Hold'em seats are fixed until the table closes, so you're sitting out: you check or fold and still post blinds. Click |cffffd100I'm back|r in the table window to play again.")
	elseif g.phase == "playing" then
		self:ToHost(J("LEAVE", g.id))
		ns.Print("Leaving after this hand. Your results so far stay on the host's book.")
	else
		ns.Print("Left a locked table. The host will count it as a forfeit.")
	end
	g.phase = "aborted"
	self:HideTables()
	refresh()
end

function C:Active()
	local g = self.game
	if g and g.phase ~= "done" and g.phase ~= "aborted" then return g end
end

-- At a table, including while the dice are still rolling after the result is fixed
function C:Busy()
	local g = self.game
	if not g then return end
	if self:Active() then return g end
	if g.phase == "done" and g.dice and not g.dice.done then return g end
end

-- At a table as a player (not just watching)
function C:Playing()
	local g = self:Active()
	if g and not g.watching then return g end
end

local lastLQ = -100
function C:RequestLedger(force)
	if not force and GetTime() - lastLQ < 10 then return end
	lastLQ = GetTime()
	self:ToHost("LQ")
end

function C:PayHost()
	local host = self:Host()
	if not host then return ns.Print("No host set.") end
	local bal = self:Balance()
	if bal >= 0 then return ns.Print("You don't owe the host anything (as of the last ledger update).") end
	ns.FillMail(host, -bal, ns.MAIL_TAG .. ns.me)
end

function C:BalanceText(c)
	if c > 0 then return "|cff59d959house owes " .. ns.Money(c) .. "|r" end
	if c < 0 then return "|cffff6161owes the house " .. ns.Money(-c) .. "|r" end
	return "|cff9e948asquare|r"
end

function C:PrintBalance()
	local cache = self:Cache()
	local bal = self:Balance()
	local who = self:Host() and ns.Short(self:Host()) or "the host"
	if bal > 0 then ns.Print(("%s owes you %s."):format(who, ns.Money(bal)))
	elseif bal < 0 then ns.Print(("You owe %s %s. At a mailbox: /gt pay"):format(who, ns.Money(-bal)))
	else ns.Print("You're square with " .. who .. ".") end
	if cache.ts > 0 then DEFAULT_CHAT_FRAME:AddMessage("   (ledger as of " .. date("%m/%d %H:%M", cache.ts) .. ")") end
end

function C:SortedBalances()
	local list = {}
	for name, c in pairs(self:Cache().balances) do list[#list + 1] = { name = name, c = c } end
	table.sort(list, function(a, b)
		if a.c ~= b.c then return a.c < b.c end -- biggest debts first
		return a.name < b.name
	end)
	return list
end

function C:PrintBoard()
	local list = self:Cache().board or {}
	if #list == 0 then return ns.Print("No leaderboard from the house yet.") end
	ns.Print("Lifetime leaderboard:")
	for i = 1, math.min(10, #list) do
		local r = list[i]
		DEFAULT_CHAT_FRAME:AddMessage(("   %d. %s  %s  (%d-%d, %d games)"):format(i, ns.Short(r.name), ns.W.Signed(r.net), r.won, r.lost, r.played))
	end
end

function C:PrintLedger()
	local list = self:SortedBalances()
	if #list == 0 then return ns.Print("No ledger received from the host yet.") end
	ns.Print("Host ledger (as of " .. date("%m/%d %H:%M", self:Cache().ts) .. "):")
	for _, b in ipairs(list) do
		DEFAULT_CHAT_FRAME:AddMessage("   " .. ns.Short(b.name) .. ": " .. self:BalanceText(b.c))
	end
end

---------------------------------------------------------------------------
-- incoming
---------------------------------------------------------------------------
local H = {}
C.H = H

---------------------------------------------------------------------------
-- Review: the house's recent tables
---------------------------------------------------------------------------
-- RLE^id^type^wager^param^hands^route^status^ended^players^canReview^summary
H.RLE = function(sender, f)
	local id, gt = f[2], f[3]
	if not (id and ns.Games.types[gt]) then return end
	local ended = tonumber(f[9]) or time()
	local known = C.tables[id]
	local r = C:TrackTable(id, { type = gt, wager = tonumber(f[4]), param = tonumber(f[5]), hands = tonumber(f[6]), route = f[7] ~= "" and f[7] or nil })
	if not known then r.first = GetTime() - math.max(0, time() - ended) end -- sort by when it really ended
	if C.game and C.game.id == id and C:Busy() then return end
	if #r.players == 0 then r.players = ns.List(f[10]) end
	C:SetTableStatus(r, f[8] == "closed" and "closed" or "cancelled")
	if not known or not r.endedAt or r.endedAt > ended then r.endedAt = ended end
	if f[12] and f[12] ~= "" and not r.summary then r.summary = f[12] end
	if f[11] == "0" then r.remote = false elseif f[11] == "1" then r.remote = true end
	if not r.mine and ns.IndexOf(r.players, ns.me) then r.mine = true end -- played before a reload: no local copy
	refresh()
end

-- RVX^id : the house doesn't have that table any more
H.RVX = function(sender, f)
	local r = C.tables[f[2]]
	if r then r.remote, r.fetching = false, nil end
	C.rvbuf[f[2]] = nil
	ns.Print("The house no longer has that table. It keeps the last 20.")
	refresh()
end

-- RV^id^k^n^<message> : one part of a table sent for Review
C.rvbuf = {}
H.RV = function(sender, f)
	local id, k, n = f[2], tonumber(f[3]), tonumber(f[4])
	local r = C.tables[id]
	if not (r and r.fetching and k and n and k >= 1 and k <= n and n <= 400) then return end
	local b = C.rvbuf[id]
	if not b or b.n ~= n then b = { n = n, got = 0, parts = {} }; C.rvbuf[id] = b end
	if b.parts[k] then return end
	b.parts[k] = { select(5, unpack(f)) }
	b.got = b.got + 1
	if b.got < n then return end
	C.rvbuf[id] = nil
	r.fetching = nil
	local ok, g = pcall(C.Rebuild, C, id, b.parts)
	if not ok or not g then
		ns.Print("That table couldn't be rebuilt" .. (ok and "" or (": " .. tostring(g))) .. ".")
		return refresh()
	end
	r.game = g
	r.remote = true
	if r.mine and r.delta == nil then r.delta = g.delta or (g.cards and g.cards.deltas and g.cards.deltas[ns.me]) end
	if not r.summary then r.summary = C:GameSummary(g) end
	if r.openWhenReady and not C:Busy() then
		r.openWhenReady = nil
		C.game = g
		C:OpenTable()
	end
	refresh()
end

-- Rebuild a finished table from what the house kept: the sealed rolls, then the
-- dice result or the card table's public messages. Runs silently: no chat, no
-- sounds, no windows popping, nothing sent to the house.
local function hushed(fn)
	local saved = {}
	local function stub(t, k) if t and type(t[k]) == "function" then saved[#saved + 1] = { t, k, t[k] }; t[k] = function() end end end
	stub(ns, "Notify"); stub(ns, "Print"); stub(ns, "Log")
	for _, ui in ipairs({ ns.CardUI, ns.HandUI, ns.DiceUI, ns.ClientUI, ns.HoldemUI }) do
		for k, v in pairs(ui) do if type(v) == "function" then stub(ui, k) end end
	end
	stub(C, "CloseTableSoon"); stub(C, "RequestLedger"); stub(C, "ToHost"); stub(C, "SyncTables")
	ns.hush = true
	local ok, err = pcall(fn)
	ns.hush = nil
	for i = #saved, 1, -1 do local s = saved[i]; s[1][s[2]] = s[3] end
	if not ok then error(err, 0) end
end

function C:Rebuild(id, parts)
	local m = parts[1]
	if not (m and m[1] == "M" and ns.Games.types[m[2]]) then return nil end
	local g = {
		id = id, type = m[2], wager = tonumber(m[3]) or 0, param = tonumber(m[4]) or 0, hands = tonumber(m[5]) or 1,
		route = m[6] ~= "" and m[6] or nil, players = ns.List(m[7]),
		phase = "reveal", watching = true, review = true,
	}
	local cm = parts[2]
	if cm and cm[1] == "CMTS" then g.commits = ns.List(cm[3], true) end
	local host = self:Host()
	if ns.Games.types[g.type].kind == "cards" then
		local was = self.game
		hushed(function()
			self.game = g
			for i = 3, #parts do
				local h = H[parts[i][1]]
				if h then h(host, parts[i], "REVIEW") end
			end
		end)
		self.game = was
		if g.phase ~= "done" then return nil end
	else
		local res = parts[3]
		if not (res and res[1] == "RES") then return nil end
		local forfeits, secrets = ns.List(res[3]), ns.List(res[4], true)
		local fset = {}
		for _, n in ipairs(forfeits) do fset[n] = true end
		local ok = g.commits ~= nil
		for i, p in ipairs(g.players) do
			if ok and not fset[p] and (not secrets[i] or ns.CommitHash(g.id, p, secrets[i]) ~= g.commits[i]) then ok = false end
		end
		local result = ns.Games.Resolve(g, ns.Seed(g.id, g.players, secrets, forfeits), forfeits)
		if not ok or ns.Games.ResultHash(result) ~= res[5] then g.disputed = true end
		g.phase, g.result = "done", result
		local delta = 0
		for _, d in ipairs(result.debts) do
			if d.to == ns.me then delta = delta + d.c elseif d.from == ns.me then delta = delta - d.c end
		end
		g.delta = delta
		local rolls = result.rolls or {}
		local landed, landedBy = {}, {}
		for i = 1, #rolls do landed[i] = true end
		for _, p in ipairs(g.players) do landedBy[p] = true end
		g.dice = { rolls = rolls, shown = #rolls, sent = {}, done = true, landed = landed, landedBy = landedBy, tiesShown = true }
	end
	g.closeAt = GetTime() - 1 -- the window's button just says Close
	return g
end

H.ANN = function(sender, f, via)
	local id, gtype = f[2], f[3]
	if not ns.Games.types[gtype] then return end
	local isNew = not C.lobby[id]
	local a = {
		id = id, type = gtype, wager = tonumber(f[4]) or 0, param = tonumber(f[5]) or 2,
		route = f[6] ~= "" and f[6] or ns.RouteFromVia(via), count = tonumber(f[7]) or 0,
		max = tonumber(f[8]) or 2, seen = GetTime(), direct = (via == "WHISPER" or via == "BN") and f[6] == "WHISPER",
		whispered = (via == "WHISPER" or via == "BN"),
		minProto = tonumber(f[9]) or 0, houseVersion = f[10], limit = tonumber(f[11]) or 0, hands = tonumber(f[12]) or 1,
		live = f[13] == "live", watchers = tonumber(f[14]) or 0,
	}
	a.outdated = ns.PROTO < a.minProto
	if a.houseVersion and a.houseVersion ~= "" then C.houseVersion = a.houseVersion end
	local tr = C:TrackTable(id, a)
	tr.seenAt = GetTime()
	tr.count, tr.watchers, tr.direct = a.count, a.watchers, a.direct or tr.direct
	if tr.status == "cancelled" or tr.status == "open" or tr.status == "live" then
		if not (C.game and C.game.id == id) then tr.status = a.live and "live" or "open" end
	end
	-- a table in progress that you're playing at isn't something to watch
	if a.live and C.game and C.game.id == id and not C.game.watching then return end
	if a.live then isNew = false end -- only new open tables get announced
	C.lobby[id] = a
	local g = C.game
	if g and g.id == id then g.touched = GetTime() end
	if isNew and not (g and g.id == id) then
		local text = ns.Games.types[gtype].describe(a)
		if a.direct then
			ns.Notify(ns.Short(sender) .. " invites you: " .. text .. ". |cffffd100/gt join|r")
			if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
		elseif sender ~= ns.me then
			ns.Print("Table open: " .. text .. ". |cffffd100/gt join|r")
		end
		if sender ~= ns.me and not C:Playing() and ns.ClientUI and ns.ClientUI.Toast then ns.ClientUI:Toast(a) end
	end
	refresh()
end

-- WOK^id^open|live^players : the house added you as a watcher
H.WOK = function(sender, f)
	local g = C.game
	if not (g and g.watching and g.id == f[2]) then return end
	g.players = ns.List(f[4])
	g.touched, g.wok = GetTime(), true
	if f[3] == "open" and ns.Games.types[g.type].kind ~= "cards" and ns.DiceUI then ns.DiceUI:Open() end
	refresh()
end

H.ROS = function(sender, f)
	local id, roster = f[2], ns.List(f[3])
	local a = C.lobby[id]
	if a then a.count = #roster; a.seen = GetTime() end
	local g = C.game
	if g and g.id == id and g.phase == "open" then
		g.players = roster
		g.touched = GetTime()
		if not g.watching and not ns.IndexOf(roster, ns.me) and a and #roster >= a.max then
			ns.Notify("That table is full.")
			g.phase = "aborted"
		end
	end
	refresh()
end

H.LOCK = function(sender, f)
	local id = f[2]
	local roster = ns.List(f[6])
	local tr = C:TrackTable(id, { type = ns.Games.types[f[3]] and f[3] or nil, wager = tonumber(f[4]), param = tonumber(f[5]), hands = tonumber(f[7]) })
	tr.players, tr.count, tr.seenAt = roster, #roster, GetTime()
	C:SetTableStatus(tr, "live")
	C.lobby[id] = nil
	if ns.ClientUI.HideToast then ns.ClientUI:HideToast(id) end
	local g = C.game
	if not (g and g.id == id and g.phase == "open") then refresh() return end
	if g.watching then
		g.type, g.wager, g.param = f[3], tonumber(f[4]), tonumber(f[5])
		g.hands = tonumber(f[7]) or g.hands or 1
		g.players = roster
		g.phase = "commit"
		g.touched, g.lockedAt = GetTime(), GetTime()
		ns.Print("Watching: " .. ns.ShortList(roster) .. ".")
		if ns.Games.types[g.type].kind ~= "cards" and ns.DiceUI then ns.DiceUI:Open() end
		if g.pendingCmts then local p = g.pendingCmts; g.pendingCmts = nil; H.CMTS(sender, p) end
		return refresh()
	end
	if not ns.IndexOf(roster, ns.me) then
		ns.Print("The table locked without you.")
		g.phase = "aborted"
		refresh()
		return
	end
	g.type, g.wager, g.param = f[3], tonumber(f[4]), tonumber(f[5])
	g.hands = tonumber(f[7]) or g.hands or 1
	g.players = roster
	g.phase = "commit"
	g.touched, g.lockedAt = GetTime(), GetTime()
	g.secret = ns.NewSecret()
	g.myCommit = ns.CommitHash(id, ns.me, g.secret)
	C:ToHost(J("CMT", id, g.myCommit))
	ns.Print("Table locked: " .. ns.ShortList(roster) .. ". Rolling...")
	refresh()
end

H.CMTS = function(sender, f)
	local g = C.game
	if g and g.watching and g.id == f[2] and g.phase == "open" then g.pendingCmts = f; return end -- catch-up arrived before LOCK
	if not (g and g.id == f[2] and (g.phase == "commit" or g.phase == "reveal")) then return end
	local commits = ns.List(f[3], true)
	local i = ns.IndexOf(g.players, ns.me)
	if g.watching then
		g.commits = commits
		g.touched = GetTime()
		if g.phase == "commit" then g.phase, g.revealedAt = "reveal", GetTime() end
		if g.pendingRes then local p = g.pendingRes; g.pendingRes = nil; H.RES(sender, p) end
		return refresh()
	end
	if #commits ~= #g.players or commits[i] ~= g.myCommit then
		ns.Notify("|cffff4040Warning:|r the house's commitment list doesn't include your sealed roll. Not revealing.")
		g.disputed = true
		return
	end
	g.commits = commits
	g.touched = GetTime()
	if g.phase == "commit" then
		g.phase = "reveal"
		g.revealedAt = GetTime()
	end
	-- sealed rolls open straight away; the result is fixed before anyone clicks Roll
	C:ToHost(J("SEC", g.id, g.secret)) -- resending is harmless
	if ns.DiceUI and ns.Games.types[g.type].kind ~= "cards" then ns.DiceUI:Open() end
	if g.pendingRes then
		local p = g.pendingRes
		g.pendingRes = nil
		H.RES(sender, p)
	end
	refresh()
end

H.RES = function(sender, f)
	local g = C.game
	if g and g.watching and g.id == f[2] and g.phase == "open" then g.pendingRes = f; return end -- catch-up arrived early
	if not (g and g.id == f[2]) or g.phase == "done" or g.phase == "aborted" or g.phase == "open" then return end
	if ns.Games.types[g.type].kind == "cards" then return ns.CardClient:Audit(g, f) end
	if not g.commits then
		g.pendingRes = f
		C:ToHost(J("NEED", g.id))
		return
	end
	local forfeits = ns.List(f[3])
	local secrets = ns.List(f[4], true)
	local fset = {}
	for _, n in ipairs(forfeits) do fset[n] = true end
	local ok = true
	for i, p in ipairs(g.players) do
		if not fset[p] then
			if not secrets[i] or ns.CommitHash(g.id, p, secrets[i]) ~= g.commits[i] then ok = false end
		end
	end
	if fset[ns.me] then
		ns.Notify("|cffff4040The house marked you as not revealing|r (connection problem?). Talk to the host if that's wrong.")
	end
	local res = ns.Games.Resolve(g, ns.Seed(g.id, g.players, secrets, forfeits), forfeits)
	if not ok or ns.Games.ResultHash(res) ~= f[5] then
		g.disputed = true
		ns.Notify("|cffff4040Warning:|r this result could not be verified against the sealed rolls. Tell the host.")
	end
	g.phase = "done"
	g.result = res
	local delta = 0
	for _, d in ipairs(res.debts) do
		if d.to == ns.me then delta = delta + d.c elseif d.from == ns.me then delta = delta - d.c end
	end
	local mine = g.watching and {} or C:MyGames()
	mine[#mine + 1] = { id = g.id, t = time(), type = g.type, wager = g.wager, summary = ("%s, %s: %s - %s"):format(ns.Games.types[g.type].name, ns.Money(g.wager), res.summary or "", ns.WonLost(delta)), delta = delta, disputed = g.disputed }
	while #mine > 200 do table.remove(mine, 1) end
	g.delta = delta
	g.dice = { rolls = res.rolls or {}, shown = 0, sent = {} }
	if ns.DiceUI then ns.DiceUI:Open() end
	if g.type == "deathroll" and #g.dice.rolls > 0 then
		-- the house runs the turns: wait for DRT (your turn) / DRR (the roll)
		g.dice.waiting = true
	elseif #g.dice.rolls > 0 then
		-- High Roll / High-Low: everyone clicks Roll at once. Your number shows a
		-- moment after you click; everyone else's as the house hears they rolled.
		g.dice.landed, g.dice.landedBy, g.dice.startedAt = {}, {}, GetTime()
		if ns.IndexOf(g.players, ns.me) then
			g.awaitRoll = true
			g.rollDeadline = GetTime() + AUTO_ROLL
			ns.Notify(("Your turn to roll! Click |cffffd100Roll|r (rolls itself in %ds)."):format(AUTO_ROLL))
			if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
		end
		if g.pendingHRR then local p = g.pendingHRR; g.pendingHRR = nil; H.HRR(sender, p) end
	else
		C:FinishDice(g)
	end
	refresh()
end

C.ROLL_DELAY = 1.2 -- the die spins this long before your number lands

-- A player's first-round roll lands (High Roll / High-Low)
function C:LandPlayer(g, p)
	local d = g.dice
	if not d or not d.landed or d.landedBy[p] then return end
	d.landedBy[p] = true
	for i, r in ipairs(d.rolls) do
		if r.p == p and not r.tie then
			d.landed[i] = true
			if p == ns.me and ns.DiceUI then ns.DiceUI:Land(r.r, r.max) end
		end
	end
	refresh()
	for _, q in ipairs(g.players) do if not d.landedBy[q] then return end end
	if d.tiesShown then return end
	d.tiesShown = true
	-- everyone's in: tie-breaks roll one by one, then the result
	local t = ns.DiceUI and ns.DiceUI:RevealTies() or 0
	C_Timer.After(t + 0.6, function() C:FinishDice(g) end)
end

-- HRR^id^names : these players have rolled (the house's running list)
H.HRR = function(sender, f)
	local g = C.game
	if not (g and g.id == f[2]) then return end
	if not (g.dice and g.dice.landed) then g.pendingHRR = f; return end
	for _, p in ipairs(ns.List(f[3])) do
		if p == ns.me then
			if g.awaitRoll then -- the house rolled for you
				g.awaitRoll = false
				C:LandPlayer(g, p)
			end
		else
			C:LandPlayer(g, p)
		end
	end
	g.touched = GetTime()
end

-- High Roll / High-Low tables need a Roll click; Death Roll rolls per turn
function C:NeedsRollClick(g)
	local def = ns.Games.types[g.type]
	return def and def.kind ~= "cards" and g.type ~= "deathroll"
end

-- Roll button
function C:Roll()
	local g = self.game
	if not g then return end
	if g.awaitRoll then
		g.awaitRoll = false
		g.rolledAt = GetTime()
		self:ToHost(J("HRL", g.id))
		if ns.DiceUI then ns.DiceUI:Shake() end
		C_Timer.After(self.ROLL_DELAY, function() if self.game == g then self:LandPlayer(g, ns.me) end end)
		return refresh()
	end
	local d = g.dice
	local k = d and d.turn
	if k and not d.done and d.rolls[k] and d.rolls[k].p == ns.me and not d.sent[k] then
		d.sent[k] = true
		self:ToHost(J("DRL", g.id, k))
		if ns.DiceUI then ns.DiceUI:Shake() end
		refresh()
	end
end

function C:CanRoll()
	local g = self.game
	if not g then return false end
	if g.awaitRoll then return true end
	local d = g.dice
	local k = d and d.turn
	return (k and not d.done and d.rolls[k] and d.rolls[k].p == ns.me and not d.sent[k]) and true or false
end

-- Dice finished animating: tell the player, refresh the ledger
function C:FinishDice(g)
	local d = g.dice
	if not d or d.done then return end
	d.done, d.turn = true, nil
	d.shown = #d.rolls
	local res = g.result
	for _, l in ipairs(res.log) do ns.Log(l) end
	ns.Notify("|cffffd100" .. (res.summary or "Done") .. "|r")
	for _, l in ipairs(ns.PayoutLines(ns.Games.Net(g, res))) do ns.Print("   " .. l) end
	if ns.IndexOf(g.players, ns.me) then ns.Notify(ns.YouLine(g.delta or 0)) end
	C:CloseTableSoon(g)
	C_Timer.After(2 + math.random() * 3, function() C:RequestLedger(true) end)
	refresh()
end

-- RVD^id^names : who has rolled so far (High Roll / High-Low)
H.RVD = function(sender, f)
	local g = C.game
	if not (g and g.id == f[2]) then return end
	g.rolledSet = {}
	for _, p in ipairs(ns.List(f[3])) do g.rolledSet[p] = true end
	g.touched = GetTime()
	refresh()
end

-- DRT^id^k^secs : Death Roll turn k is up (rolls[k].p rolls next)
H.DRT = function(sender, f)
	local g = C.game
	local d = g and g.id == f[2] and g.dice
	if not d or d.done then return end
	local k = tonumber(f[3])
	if not k or k <= d.shown then return end
	if k - 1 > d.shown then d.shown = k - 1 end -- missed a roll: catch up
	d.turn, d.waiting = k, nil
	d.deadline = GetTime() + (tonumber(f[4]) or 20)
	if d.rolls[k] and d.rolls[k].p == ns.me and PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
		pcall(PlaySound, SOUNDKIT.READY_CHECK)
	end
	g.touched = GetTime()
	refresh()
end

-- DRR^id^k : Death Roll roll k happens (everyone animates it)
H.DRR = function(sender, f)
	local g = C.game
	local d = g and g.id == f[2] and g.dice
	if not d or d.done then return end
	local k = tonumber(f[3])
	if not k or k <= d.shown then return end
	d.shown, d.turn, d.waiting = k, nil, nil
	local t = ns.DiceUI and ns.DiceUI:ShowRoll(k) or 0
	if k >= #d.rolls then C_Timer.After(t, function() C:FinishDice(g) end) end
	g.touched = GetTime()
	refresh()
end

-- NOPE^id^target^reason : the house turned down your join
H.NOPE = function(sender, f)
	if f[3] ~= ns.me then return end
	local g = C.game
	if g and g.id == f[2] and g.phase == "open" then g.phase = "aborted" end
	ns.Notify(f[4] or "The house turned down your join.")
	refresh()
end

-- CLOSE^id[^done|cancelled^summary] : a table is off the list (finished or cancelled).
-- Older houses send just the id: an open table then means cancelled, a live one finished.
H.CLOSE = function(sender, f)
	local tr = C.tables[f[2]]
	local own = C.game and C.game.id == f[2] and (C:Active() or C.game.phase == "done")
	if tr and not own then
		local how = f[3]
		if how ~= "done" and how ~= "cancelled" then how = (tr.status == "open") and "cancelled" or "done" end
		C:SetTableStatus(tr, how == "done" and "closed" or "cancelled")
		if f[4] and f[4] ~= "" then tr.summary = f[4] end
	end
	C.lobby[f[2]] = nil
	if ns.ClientUI.HideToast then ns.ClientUI:HideToast(f[2]) end
	local g = C.game
	if g and g.watching and g.id == f[2] and g.phase == "open" then -- it ended before we got in
		ns.Notify("That table has already finished.")
		C:StopWatching(true)
	end
	refresh()
end

H.ABORT = function(sender, f)
	local tr = C.tables[f[2]]
	if tr then
		C:SetTableStatus(tr, "cancelled")
		if f[3] and f[3] ~= "" then tr.reason = f[3] end
	end
	C.lobby[f[2]] = nil
	if ns.ClientUI.HideToast then ns.ClientUI:HideToast(f[2]) end
	local g = C.game
	if g and g.id == f[2] and g.phase ~= "done" and g.phase ~= "aborted" then
		g.phase = "aborted"
		ns.Notify("The house cancelled the table" .. ((f[3] and f[3] ~= "") and (": " .. f[3]) or "."))
		C:CloseTableSoon(g)
	end
	refresh()
end

-- LS^hostTime^name=copper,name=copper,...
-- Once per session, remind a player who owes the house
local reminded = false
function C:MaybeRemind()
	if reminded or self:Host() == ns.me then return end
	local bal = self:Balance()
	if bal < 0 then
		reminded = true
		ns.Notify(("You owe the house %s. At any mailbox, click |cffffd100Pay the house|r in /gt (or type /gt pay) to fill in the mail."):format(ns.Money(-bal)))
	end
end

function C:SetQuiet(on)
	ns.db.settings.quiet = on and true or false
	ns.Notify(on and "Quiet chat: only your turns, results and warnings go to chat. Everything else is in the /gt window."
		or "Chat: showing everything again.")
	refresh()
end

H.LS = function(sender, f)
	local cache = C:Cache()
	local bal = {}
	for _, kv in ipairs(ns.List(f[3])) do
		local n, c = kv:match("^(.+)=(%-?%d+)$")
		if n then bal[n] = tonumber(c) end
	end
	cache.balances = bal
	cache.ts = time()
	C:MaybeRemind()
	refresh()
end

-- LB^hostTime^name=net:played:won:lost:best:worst,...  (lifetime leaderboard)
H.LB = function(sender, f)
	local cache = C:Cache()
	local list = {}
	for _, kv in ipairs(ns.List(f[3])) do
		local n, net, pl, w, l, b, wo = kv:match("^(.+)=(%-?%d+):(%d+):(%d+):(%d+):(%-?%d+):(%-?%d+)$")
		if n then
			list[#list + 1] = { name = n, net = tonumber(net), played = tonumber(pl), won = tonumber(w), lost = tonumber(l), best = tonumber(b), worst = tonumber(wo) }
		end
	end
	table.sort(list, function(a, b) if a.net ~= b.net then return a.net > b.net end return a.name < b.name end)
	cache.board = list
	cache.boardTs = time()
	refresh()
end

-- LH^target^line#line#...  (your payments and games, from the host's book)
H.LH = function(sender, f)
	if f[2] ~= ns.me then return true end
	local cache = C:Cache()
	cache.history = {}
	for line in ((f[3] or "") .. "#"):gmatch("([^#]*)#") do
		if line ~= "" then cache.history[#cache.history + 1] = line end
	end
	refresh()
end

function C:OnMessage(sender, f, via)
	local h = H[f[1]]
	if not h then return false end
	local host = self:Host()
	if not host and (f[1] == "ANN" or f[1] == "LS") and sender ~= ns.me then
		ns.db.settings.host = sender
		host = sender
		ns.Print("Following the house: " .. ns.Short(sender) .. ". (/gt host <First Last> to change)")
	end
	if sender ~= host then return false end
	if via ~= "WHISPER" and via ~= "BN" and via ~= "LOCAL" then self.lastRoute = ns.RouteFromVia(via) end
	h(sender, f, via)
	return true
end

---------------------------------------------------------------------------
-- dramatic replay of the result (the outcome is already final)
---------------------------------------------------------------------------
function C:Play(g, res, delta)
	local def = ns.Games.types[g.type]
	local lines = { ("|cffffd100%s|r - %s"):format(def.name, ns.ShortList(g.players)) }
	for _, l in ipairs(res.log) do lines[#lines + 1] = l end
	lines[#lines + 1] = "|cffffd100" .. (res.summary or "Done") .. "|r"
	for _, l in ipairs(ns.PayoutLines(ns.Games.Net(g, res))) do lines[#lines + 1] = "   " .. l end
	if delta then lines[#lines + 1] = ns.YouLine(delta) end
	for i, l in ipairs(lines) do
		C_Timer.After((i - 1) * 0.7, function() ns.Print(l) end)
	end
end

---------------------------------------------------------------------------
function C:Init()
	table.insert(ns.Comm.handlers, function(sender, f, via) return C:OnMessage(sender, f, via) end)

	C_Timer.NewTicker(1, function()
		local now = GetTime()
		local changed = false
		for id, a in pairs(C.lobby) do
			-- whispered announcements aren't repeated, so they stay until locked/cancelled
			if now - a.seen > ((a.whispered and not a.live) and 900 or (a.live and 120) or LOBBY_TTL) then
				C.lobby[id] = nil
				changed = true
				-- no longer announced: an in-progress table has finished, an open one is gone
				local tr = C.tables[id]
				if tr and not (C.game and C.game.id == id) then C:SetTableStatus(tr, a.live and "closed" or "cancelled") end
			end
		end
		-- safety net: a table nobody has mentioned for 5 minutes is over
		for id, tr in pairs(C.tables) do
			if (tr.status == "open" or tr.status == "live") and not C.lobby[id] and not (C.game and C.game.id == id)
				and now - (tr.seenAt or tr.first) > 300 then
				C:SetTableStatus(tr, tr.status == "live" and "closed" or "cancelled")
				changed = true
			end
		end
		local rg = C.game
		if rg and rg.awaitRoll and rg.rollDeadline and now > rg.rollDeadline then C:Roll() end
		-- lost the house's "who rolled" list: after the roll window, show everyone
		local rd = rg and rg.dice
		if rd and rd.landed and not rd.tiesShown and rd.startedAt and now > rd.startedAt + 55 then
			for _, p in ipairs(rg.players) do C:LandPlayer(rg, p) end
		end
		if ns.CardClient and ns.CardClient.Tick then ns.CardClient:Tick(now) end
		local g = C:Active()
		if g then
			-- join not acknowledged yet? ask again (a few times)
			if g.watching then
				if g.phase == "open" and not g.wok and now - g.touched > 4 then
					if (g.joinTries or 0) < 3 then
						g.joinTries = (g.joinTries or 0) + 1
						g.touched = now
						C:ToHost(J("WATCH", g.id))
					else
						ns.Notify("The house isn't answering your Watch request. It may need to update the Host addon (type /gth on the house to see its version).")
						C:StopWatching(true)
					end
				end
			elseif g.phase == "open" and not ns.IndexOf(g.players, ns.me) and now - g.touched > 4 and (g.joinTries or 0) < 3 then
				g.joinTries = (g.joinTries or 0) + 1
				g.touched = now
				C:ToHost(J("JOIN", g.id, ns.PROTO))
			end
			if now - g.touched > STALE_AFTER then
				g.phase = "aborted"
				ns.Notify("Lost contact with the house; left the table.")
				changed = true
			elseif g.qnext and ((g.qgapSince and now - g.qgapSince > 3) or now - g.touched > 45)
				and now - (g.lastNeed or 0) > 4 then
				-- card table: missing numbered messages
				g.lastNeed = now
				C:ToHost(J("NEED", g.id, g.qnext))
			elseif (((g.phase == "commit" or g.phase == "reveal") and now - g.touched > NEED_AFTER)
				or (g.phase == "playing" and now - g.touched > 45))
				and now - (g.lastNeed or 0) > NEED_AFTER then
				g.lastNeed = now
				if g.phase == "commit" and not g.watching then C:ToHost(J("CMT", g.id, g.myCommit)) end
				C:ToHost(J("NEED", g.id))
			end
		end
		if changed then refresh() end
	end)

	C_Timer.After(8, function() C:RequestLedger(true) end)

	-- at a mailbox: offer to fill in the payment
	StaticPopupDialogs["GOLDENTHUGGET_PAYPROMPT"] = {
		text = "%s", button1 = "Fill in the mail", button2 = "Not now",
		OnAccept = function()
			if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
			C_Timer.After(0.2, function() C:PayHost() end)
		end,
		timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
	}
	ns.On("MAIL_SHOW", function()
		if C:Host() == ns.me then return end
		local bal = C:Balance()
		if bal < 0 then
			StaticPopup_Show("GOLDENTHUGGET_PAYPROMPT", ("You owe the house (%s) %s.\n\nFill in a payment mail now?"):format(ns.Short(C:Host()), ns.Money(-bal)))
		end
	end)
end
