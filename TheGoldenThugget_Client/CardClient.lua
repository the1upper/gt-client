-- The Golden Thugget: card table client. Follows the house's messages, opens your
-- private hand, sends your decisions, re-checks every result with the shared
-- rules in Cards.lua, and audits every card against the real decks at the end.
local _, ns = ...
if ns.skip then return end
local CC = {}
ns.CardClient = CC
local K = ns.Cards
local J = function(...) return ns.Join(...) end

local function refresh()
	if ns.CardUI and ns.CardUI.Refresh then ns.CardUI:Refresh() end
	if ns.HandUI and ns.HandUI.Refresh then ns.HandUI:Refresh() end
	if ns.ClientUI and ns.ClientUI.Refresh then ns.ClientUI:Refresh() end
end

local function myTable(id)
	local g = ns.Client.game
	if g and g.id == id and g.cards and g.phase == "playing" then return g, g.cards end
end

local function flag(c, why)
	if not c.problem then
		c.problem = why
		ns.Notify("|cffff4040Warning:|r " .. why)
	end
end

local function addSeen(c, packed)
	local d, p, code = K.Unpack(packed)
	if d then c.seen[#c.seen + 1] = { d = d, p = p, c = code } end
	return code
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
function CC:Decide(choice)
	local g = ns.Client.game
	local c = g and g.cards
	if not c or c.phase ~= "decide" or c.myDecision or not c.myHand then return end
	c.myDecision = choice
	ns.Client:ToHost(J("DEC", g.id, c.round, choice))
	refresh()
end

-- amount: copper (number) or text like "50s" / "1g 20s"
function CC:Bet(amount)
	local g = ns.Client.game
	local c = g and g.cards
	if not c or c.phase ~= "bet" or not c.turn or c.turn.player ~= ns.me or c.betSent then return end
	if type(amount) ~= "number" then amount = ns.ParseMoney(amount) or 0 end
	amount = math.max(0, math.min(math.floor(amount), K.AceyMaxBet(c.pot, g.param)))
	c.betSent = true
	ns.Client:ToHost(J("BET", g.id, c.n, amount))
	refresh()
end

---------------------------------------------------------------------------
-- Thugget Dice actions
---------------------------------------------------------------------------
local TH = ns.Games.Thugget

local function myDice()
	local g = ns.Client.game
	local c = g and g.cards
	if not (c and c.my and g.phase == "playing" and c.phase == "roll") then return end
	return g, c, c.my
end

function CC:CanYRoll()
	local g, c, m = myDice()
	return (m and not m.stood and not m.pending and m.rolls < 3) and true or false
end

function CC:CanStand()
	local g, c, m = myDice()
	return (m and not m.stood and not m.pending and m.rolls >= 1) and true or false
end

function CC:ToggleHold(i)
	local g, c, m = myDice()
	if not m or m.stood or m.pending or m.rolls < 1 or m.rolls >= 3 then return end
	m.held[i] = not m.held[i]
	refresh()
end

function CC:YRoll()
	if not self:CanYRoll() then return end
	local g, c, m = myDice()
	local mask = ""
	for i = 1, 5 do mask = mask .. ((m.rolls >= 1 and m.held[i]) and "1" or "0") end
	m.pending = true
	m.pendingMask = mask
	m.pendingAt = GetTime()
	ns.Client:ToHost(J("YROLL", g.id, m.rolls + 1, mask))
	if ns.HandUI then ns.HandUI:Spin(mask) end
	refresh()
end

-- Called every second by the client: chase anything private that went missing
function CC:Tick(now)
	if ns.HoldemClient then ns.HoldemClient:Tick(now) end
	local g = ns.Client.game
	local c = g and g.cards
	if not c or g.phase ~= "playing" then return end
	-- Thugget Dice: our roll result never arrived -> ask again (the house resends it)
	local m = c.my
	if m and m.pending and now - (m.pendingAt or now) > 4 then
		m.pendingAt = now
		ns.Client:ToHost(J("YROLL", g.id, m.rolls + 1, m.pendingMask or "00000"))
	end
	-- Guts on a whispered table: our private hand never arrived
	if g.type == "guts" and c.phase == "decide" and not c.myHand and c.roundAt and now - c.roundAt > 4
		and now - (c.lastHNeed or 0) > 4 and ns.IndexOf(c.seats, ns.me) then
		c.lastHNeed = now
		ns.Client:ToHost(J("HNEED", g.id, c.round))
	end
end

function CC:YStand()
	if not self:CanStand() then return end
	local g, c, m = myDice()
	m.stood = true
	ns.Client:ToHost(J("YSTAND", g.id))
	refresh()
end

function CC:MaxBet()
	local g = ns.Client.game
	local c = g and g.cards
	if not c then return 0 end
	return K.AceyMaxBet(c.pot, g.param)
end

---------------------------------------------------------------------------
-- incoming (registered into the client's handler table)
---------------------------------------------------------------------------
local H = ns.Client and ns.Client.H

function CC:OpenHand(g, c, sealed)
	local plain = sealed and K.Open(K.HandKey(g.id, c.round, g.secret), sealed)
	local hand = {}
	for _, packed in ipairs(ns.List(plain or "")) do
		local code = addSeen(c, packed)
		if code then hand[#hand + 1] = code end
	end
	if #hand ~= 3 then return flag(c, "couldn't open your hand.") end
	c.myHand = hand
	local _, name = K.Eval3(hand)
	ns.Print(("Round %d - your hand: %s (%s). Pot %s."):format(c.round, K.TextList(hand), name, ns.Money(c.pot)))
	if ns.CardUI then ns.CardUI:Deal() end
	refresh()
end

local function install()
	H = ns.Client.H

	-- Q^id^seq^<message>: numbered card-table stream, processed strictly in order
	H.Q = function(sender, f, via)
		local g = ns.Client.game
		if not (g and g.id == f[2]) or g.phase == "done" or g.phase == "aborted" then return end
		local seq = tonumber(f[3])
		g.qnext = g.qnext or 1
		if not seq or seq < g.qnext then return end
		g.qbuf = g.qbuf or {}
		g.qbuf[seq] = { select(4, unpack(f)) }
		while g.qbuf[g.qnext] do
			local inner = g.qbuf[g.qnext]
			g.qbuf[g.qnext] = nil
			g.qnext = g.qnext + 1
			local h = H[inner[1]]
			if h then h(sender, inner, via) end
			if g.phase == "done" or g.phase == "aborted" then break end
		end
		g.qgapSince = next(g.qbuf) and (g.qgapSince or GetTime()) or nil
	end

	-- SEATS^id^seats^dropped : table starts / players stand up
	H.SEATS = function(sender, f)
		local g = ns.Client.game
		if not (g and g.id == f[2]) or g.phase == "done" or g.phase == "aborted" then return end
		local seats = ns.List(f[3])
		if not g.cards then
			if not g.watching and not ns.IndexOf(seats, ns.me) then
				ns.Notify("You didn't reveal in time and were left out of this table.")
				g.phase = "aborted"
				return refresh()
			end
			g.phase = "playing"
			g.cards = { seats = seats, deltas = {}, pot = 0, contrib = {}, round = 0, n = 0, seen = {}, ante = g.wager }
			for _, p in ipairs(seats) do g.cards.deltas[p] = 0 end
			ns.Print(("%s is starting: %s."):format(ns.Games.types[g.type].name, ns.ShortList(seats)))
			local ui = ns.Games.types[g.type].ui
			if ui == "hand" then
				if ns.HandUI then ns.HandUI:Open() end
			elseif ui == "holdem" then
				if ns.HoldemUI then ns.HoldemUI:Open() end -- filled in when the house sends HTABLE
			elseif ns.CardUI then ns.CardUI:Open() end
		else
			g.cards.seats = seats
		end
		g.touched = GetTime()
		refresh()
	end

	-- RND^id^round^pot^ante^secs^seats
	H.RND = function(sender, f)
		local g, c = myTable(f[2])
		if not g then return end
		local round = tonumber(f[3])
		if not round or round <= c.round then return end
		if round ~= c.round + 1 or c.phase == "decide" then c.gap = true end
		c.seats = ns.List(f[7])
		if not c.carried then -- where everyone stood before this hand (a redeal continues the same hand)
			c.handStart = {}
			for _, p in ipairs(c.seats) do c.handStart[p] = c.deltas[p] or 0 end
		end
		if f[5] == "1" then
			for _, p in ipairs(c.seats) do
				c.deltas[p] = (c.deltas[p] or 0) - c.ante
				c.pot = c.pot + c.ante
				c.contrib[p] = (c.contrib[p] or 0) + c.ante
			end
		end
		if c.pot ~= tonumber(f[4]) then
			if not c.gap then flag(c, "the pot doesn't match the house's numbers.") end
			c.pot = tonumber(f[4]) or c.pot
		end
		c.round, c.phase = round, "decide"
		c.deadline = GetTime() + (tonumber(f[6]) or 30)
		c.roundAt = GetTime()
		c.myHand, c.myDecision, c.decided, c.shown, c.ins, c.result = nil, nil, {}, nil, nil, nil
		g.touched = GetTime()
		local ph = c.pendingHand
		if ph and tonumber(ph[3]) == round then c.pendingHand = nil; CC:OpenHand(g, c, ph[4]) end
		refresh()
	end

	-- HAND^id^round^sealed : your own hand only (whispered tables)
	H.HAND = function(sender, f)
		local g, c = myTable(f[2])
		if not g then return end
		local round = tonumber(f[3])
		if not round or round < c.round or (round == c.round and c.myHand) then return end
		if round > c.round then c.pendingHand = f return end -- RND not here yet
		CC:OpenHand(g, c, f[4])
	end

	-- HANDS^id^round^sealed1,sealed2,... (seat order; only you can open yours)
	H.HANDS = function(sender, f)
		local g, c = myTable(f[2])
		if not g or tonumber(f[3]) ~= c.round or c.myHand then return end
		local i = ns.IndexOf(c.seats, ns.me)
		if not i then return end
		CC:OpenHand(g, c, ns.List(f[4], true)[i])
	end

	-- DCD^id^round^names-who-have-decided
	H.DCD = function(sender, f)
		local g, c = myTable(f[2])
		if not g or tonumber(f[3]) ~= c.round then return end
		c.decided = {}
		for _, p in ipairs(ns.List(f[4])) do c.decided[p] = true end
		g.touched = GetTime()
		refresh()
	end

	-- SHOW^id^round^inNames^seat:d.p.c/d.p.c/d.p.c;...^potAfter
	H.SHOW = function(sender, f)
		local g, c = myTable(f[2])
		if not g or tonumber(f[3]) ~= c.round or c.phase ~= "decide" then return end
		local ins, hands = {}, {}
		for _, p in ipairs(ns.List(f[4])) do ins[p] = true end
		for chunk in ((f[5] or "") .. ";"):gmatch("([^;]*);") do
			local idx, cards = chunk:match("^(%d+):(.+)$")
			local p = idx and c.seats[tonumber(idx)]
			if p then
				local h = {}
				for packed in (cards .. "/"):gmatch("([^/]*)/") do
					local code = addSeen(c, packed)
					if code then h[#h + 1] = code end
				end
				hands[p] = h
			end
		end
		if c.myHand and ins[ns.me] and hands[ns.me] then
			for k = 1, 3 do
				if hands[ns.me][k] ~= c.myHand[k] then flag(c, "the house showed a different hand than you were dealt.") end
			end
		end
		for p in pairs(ins) do
			if not hands[p] or #hands[p] ~= 3 then return flag(c, "a showdown hand was missing.") end
		end
		local res = K.GutsResolve(c.seats, ins, hands, c.pot, g.param, c.contrib, f[7] == "1")
		K.AddDeltas(c.deltas, res.deltas)
		c.pot, c.contrib = res.pot, res.contrib
		if tostring(res.pot) ~= f[6] and not c.gap then flag(c, "the showdown result doesn't match the rules.") end
		c.phase, c.ins, c.shown, c.result, c.handNames = "show", ins, hands, res.summary, res.hand
		c.carried = res.redeal
		-- what each player won or lost on this hand (ante and stay-in included)
		c.handNet = nil
		if not res.redeal and c.handStart then
			c.handNet = {}
			for _, p in ipairs(c.seats) do c.handNet[p] = (c.deltas[p] or 0) - (c.handStart[p] or 0) end
		end
		ns.Notify(res.summary)
		if c.handNet then
			for _, l in ipairs(ns.PayoutLines(c.handNet, res.hand)) do ns.Print("   " .. l) end
			local mine = c.handNet[ns.me]
			if mine then ns.Notify(ns.YouLine(mine)) end
		end
		g.touched = GetTime()
		if ns.CardUI then ns.CardUI:Showdown() end
		refresh()
	end

	-- TURN^id^n^player^pot^ante^d.p.c/d.p.c^secs
	H.TURN = function(sender, f)
		local g, c = myTable(f[2])
		if not g then return end
		local n = tonumber(f[3])
		if not n or n <= c.n then return end
		if n ~= c.n + 1 then c.gap = true end
		if f[6] == "1" then
			for _, p in ipairs(c.seats) do
				c.deltas[p] = (c.deltas[p] or 0) - c.ante
				c.pot = c.pot + c.ante
			end
		end
		if c.pot ~= tonumber(f[5]) then
			if not c.gap then flag(c, "the pot doesn't match the house's numbers.") end
			c.pot = tonumber(f[5]) or c.pot
		end
		local p1, p2 = (f[7] or ""):match("^([^/]+)/([^/]+)$")
		local c1, c2 = addSeen(c, p1), addSeen(c, p2)
		if not (c1 and c2) then return flag(c, "received a malformed turn.") end
		local secs = tonumber(f[8]) or 0
		c.n = n
		c.turn = { player = f[4], c1 = c1, c2 = c2 }
		c.phase = secs > 0 and "bet" or "draw"
		c.deadline = GetTime() + secs
		c.betSent, c.third, c.outcome = nil, nil, nil
		if f[4] == ns.me and secs > 0 then
			ns.Notify(("Your turn: %s and %s - bet up to %s (pot %s)."):format(K.Text(c1), K.Text(c2), ns.Money(K.AceyMaxBet(c.pot, g.param)), ns.Money(c.pot)))
			if not ns.hush and PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
		end
		g.touched = GetTime()
		if ns.CardUI then ns.CardUI:Deal() end
		refresh()
	end

	-- DRAW^id^n^bet^d.p.c|""^outcome^potAfter
	H.DRAW = function(sender, f)
		local g, c = myTable(f[2])
		if not g or tonumber(f[3]) ~= c.n or not c.turn or c.outcome then return end
		local bet = tonumber(f[4]) or 0
		local c3 = f[5] ~= "" and addSeen(c, f[5]) or nil
		local outcome, delta = K.AceyResolve(c.turn.c1, c.turn.c2, c3, bet)
		if f[6] == "nochance" then
			if not K.AceyNoChance(c.turn.c1, c.turn.c2) then flag(c, "the house skipped a turn that had a gap.") end
			outcome, delta = "nochance", 0
		end
		if bet > K.AceyMaxBet(c.pot, g.param) then flag(c, "a bet above the limit was accepted.") end
		if outcome ~= f[6] then flag(c, "an Acey-Deucey result doesn't match the rules.") end
		local p = c.turn.player
		c.deltas[p] = (c.deltas[p] or 0) + delta
		c.pot = c.pot - delta
		if tostring(c.pot) ~= f[7] and not c.gap then flag(c, "the pot doesn't match the house's numbers.") end
		c.third, c.outcome, c.lastBet, c.phase = c3, outcome, bet, "result"
		-- "Pl1 Stone: 4 and J, bet 50s, drew 9 - in between, won 50s"
		local words = { win = "in between", lose = "outside", post = "hit the post (pays double)", pass = "passed", nochance = "no gap - skipped" }
		local line = ("%s: %s and %s"):format(ns.Short(p), K.Text(c.turn.c1), K.Text(c.turn.c2))
		if bet > 0 then line = line .. (", bet %s, drew %s - %s, %s"):format(ns.Money(bet), K.Text(c3), words[outcome], ns.WonLost(delta))
		else line = line .. " - " .. words[outcome] end
		ns.Log(line)
		if p == ns.me then ns.Print(line) end
		g.touched = GetTime()
		if ns.CardUI then ns.CardUI:Reveal() end
		refresh()
	end

	-- YSTART^id^secs^pot : everyone rolls at once
	H.YSTART = function(sender, f)
		local g, c = myTable(f[2])
		if not g or c.yd then return end
		for _, p in ipairs(c.seats) do
			c.deltas[p] = (c.deltas[p] or 0) - c.ante
			c.pot = c.pot + c.ante
			c.contrib[p] = c.ante
		end
		if tostring(c.pot) ~= f[4] then flag(c, "the pot doesn't match the house's numbers.") end
		c.yd = {}
		for _, p in ipairs(c.seats) do c.yd[p] = { rolls = 0, stood = false } end
		c.yseen = {}
		c.phase = "roll"
		c.deadline = GetTime() + (tonumber(f[3]) or 60)
		if ns.IndexOf(c.seats, ns.me) then
			c.my = { rolls = 0, dice = {}, held = {}, stood = false }
			if not ns.hush and PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
			ns.Notify("Thugget Dice: roll your dice! You have " .. (tonumber(f[3]) or 60) .. "s.")
		end
		g.touched = GetTime()
		refresh()
	end

	-- YD^id^player^k^sealed : someone rolled (only they can read their dice)
	H.YD = function(sender, f)
		local g, c = myTable(f[2])
		if not g or not c.yd then return end
		local p, k = f[3], tonumber(f[4])
		local st = c.yd[p]
		if not st or not k then return end
		st.rolls = math.max(st.rolls, k)
		if k >= 3 then st.stood = true end
		if p == ns.me and c.my then
			local plain = K.Open(K.HandKey(g.id, "y" .. k, g.secret), f[5] or "")
			local kk, mask, digits = (plain or ""):match("^(%d):([01]+):([1-6][1-6][1-6][1-6][1-6])$")
			if not kk or tonumber(kk) ~= k then return flag(c, "couldn't read your dice.") end
			local m = c.my
			if m.pendingMask and m.pendingMask ~= mask and k > 1 then flag(c, "the house used different holds than you chose.") end
			local dice = {}
			for i = 1, 5 do
				local d = tonumber(digits:sub(i, i))
				if k > 1 and mask:sub(i, i) == "1" and m.dice[i] ~= d then flag(c, "a held die changed.") end
				dice[i] = d
			end
			m.dice, m.rolls, m.pending, m.pendingMask = dice, k, false, nil
			c.yseen[#c.yseen + 1] = { k = k, mask = mask, dice = { unpack(dice) } }
			if k >= 3 then m.stood = true end
			if ns.HandUI then ns.HandUI:Land() end
		end
		g.touched = GetTime()
		refresh()
	end

	-- YP^id^seq^name=rolls[s],... : who has rolled / stood (batched snapshot)
	H.YP = function(sender, f)
		local g, c = myTable(f[2])
		local seq = tonumber(f[3])
		if not g or not c.yd or not seq or seq <= (c.ypSeq or 0) then return end
		c.ypSeq = seq
		for _, kv in ipairs(ns.List(f[4])) do
			local p, n, st = kv:match("^(.+)=(%d)(s?)$")
			local y = p and c.yd[p]
			if y then
				y.rolls = math.max(y.rolls, tonumber(n))
				if st == "s" then y.stood = true end
			end
		end
		g.touched = GetTime()
		refresh()
	end

	-- YS^id^player : stood
	H.YS = function(sender, f)
		local g, c = myTable(f[2])
		if not g or not c.yd or not c.yd[f[3]] then return end
		c.yd[f[3]].stood = true
		if f[3] == ns.me and c.my then c.my.stood = true end
		g.touched = GetTime()
		refresh()
	end

	-- YSHOW^id^seat:mask/mask/mask:ddddd;... : everyone's dice
	H.YSHOW = function(sender, f)
		local g, c = myTable(f[2])
		if not g or not c.yd or c.phase == "show" then return end
		local hands = {}
		c.ymasks = {}
		for chunk in ((f[3] or "") .. ";"):gmatch("([^;]*);") do
			local idx, masks, digits = chunk:match("^(%d+):([01/]+):([1-6][1-6][1-6][1-6][1-6])$")
			local p = idx and c.seats[tonumber(idx)]
			if p then
				local d = {}
				for i = 1, 5 do d[i] = tonumber(digits:sub(i, i)) end
				hands[p] = d
				local ml = {}
				for m in (masks .. "/"):gmatch("([01]+)/") do ml[#ml + 1] = m end
				c.ymasks[p] = ml
			end
		end
		for _, p in ipairs(c.seats) do
			if not hands[p] then return flag(c, "a hand was missing at the showdown.") end
		end
		if c.my and c.my.rolls > 0 then
			for i = 1, 5 do if hands[ns.me][i] ~= c.my.dice[i] then flag(c, "the house showed different dice than you rolled.") end end
		end
		local res = TH.Resolve(c.seats, hands, c.pot, c.contrib)
		K.AddDeltas(c.deltas, res.deltas)
		c.pot, c.contrib = 0, {}
		c.phase, c.yshown, c.yres, c.result = "show", hands, res, res.summary
		ns.Notify("Thugget Dice: " .. res.summary)
		for _, l in ipairs(ns.PayoutLines(c.deltas, res.names)) do ns.Print("   " .. l) end
		g.touched = GetTime()
		if ns.HandUI then ns.HandUI:Showdown() end
		refresh()
	end
end
CC.Install = install

---------------------------------------------------------------------------
-- End of table: verify everything we were shown against the real decks
---------------------------------------------------------------------------
function CC:Audit(g, f)
	local c = g.cards
	if not c then g.phase = "done"; return refresh() end
	local forfeits = ns.List(f[3])
	local secrets = ns.List(f[4], true)
	local fset = {}
	for _, n in ipairs(forfeits) do fset[n] = true end
	local ok = g.commits ~= nil
	if ok then
		for i, p in ipairs(g.players) do
			if not fset[p] and (not secrets[i] or ns.CommitHash(g.id, p, secrets[i]) ~= g.commits[i]) then ok = false end
		end
	end
	local verified, bad = false, nil
	if ok then
		local seed = ns.Seed(g.id, g.players, secrets, forfeits)
		if g.type == "thugget" then
			-- rebuild every player's dice from the seed and their holds
			verified = c.yshown ~= nil
			for p, masks in pairs(c.ymasks or {}) do
				local seq = TH.Replay(seed, p, masks)
				local final = seq[#seq]
				for i = 1, 5 do if not final or final[i] ~= c.yshown[p][i] then verified = false end end
			end
			for _, y in ipairs(c.yseen or {}) do
				local seq = TH.Replay(seed, ns.me, (c.ymasks or {})[ns.me] or {})
				local r = seq[y.k]
				for i = 1, 5 do if not r or r[i] ~= y.dice[i] then verified = false end end
			end
			c.seen = c.yseen or {}
		else
			verified, bad = K.VerifySeen(seed, c.seen)
		end
	end
	local refund
	if g.type == "holdem" then refund = {} -- stacks are in the deltas after every hand
	elseif g.type == "guts" or g.type == "thugget" then refund = K.GutsRefund(c.contrib)
	else refund = K.AceyRefund(c.pot, c.seats) end
	-- Hold'em: the seat order and first button were drawn from the seed too
	if ok and verified and g.type == "holdem" and c.he then
		local seed = ns.Seed(g.id, g.players, secrets, forfeits)
		local base = {}
		for _, p in ipairs(g.players) do if not fset[p] then base[#base + 1] = p end end
		for i = #base, 2, -1 do
			local j = ns.Games.Rand(seed, "holdem-seat:" .. i, i)
			base[i], base[j] = base[j], base[i]
		end
		for i, p in ipairs(base) do if c.he.order[i] ~= p then verified = false end end
		if c.he.firstButton ~= base[ns.Games.Rand(seed, "holdem-button", #base)] then verified = false end
	end
	K.AddDeltas(c.deltas, refund)
	local hashOk = K.DeltaHash(c.deltas) == f[5]
	local mine = c.deltas[ns.me] or 0
	g.phase = "done"
	c.phase = "closed"
	local note
	if not ok then note = "|cffff4040the house's revealed secrets don't match the seals|r"
	elseif not verified then note = bad and ("|cffff4040card " .. K.Text(bad.c) .. " doesn't match the shuffled deck|r") or "|cffff4040the deal doesn't match the sealed rolls|r"
	elseif c.problem then note = "|cffff4040problems were reported during play|r"
	elseif not hashOk then note = c.gap and "|cffffff00some hands were missed, so totals couldn't be fully checked|r" or "|cffff4040final totals don't match the house's|r"
	elseif g.type == "thugget" then note = "every die at the table was verified"
	else note = ("all %d cards you saw were verified"):format(#c.seen) end
	if (g.hands or 1) ~= 1 then -- several hands: the table's totals
		ns.Notify(ns.Games.types[g.type].name .. " table closed. Totals:")
		for _, l in ipairs(ns.PayoutLines(c.deltas)) do ns.Notify("   " .. l) end
	elseif g.type == "acey" then
		ns.Notify("Acey-Deucey closed - leftover pot split evenly. Results:")
		for _, l in ipairs(ns.PayoutLines(c.deltas)) do ns.Notify("   " .. l) end
	end
	if c.deltas[ns.me] and not (g.type == "guts" and (g.hands or 1) == 1) then ns.Notify(ns.YouLine(mine)) end -- one Guts hand: already said at the showdown
	ns.Print("Check: " .. note .. ".")
	local disputed = (not ok) or (not verified) or c.problem ~= nil or (not hashOk and not c.gap)
	local list = g.watching and {} or ns.Client:MyGames()
	list[#list + 1] = { id = g.id, t = time(), type = g.type, wager = g.wager, delta = mine, disputed = disputed or nil,
		summary = ("%s, %s %s: %s"):format(ns.Games.types[g.type].name, ns.Money(g.wager), g.type == "holdem" and "buy-in" or "ante", ns.WonLost(mine)) }
	ns.Client:CloseTableSoon(g)
	if not g.review then C_Timer.After(3 + math.random() * 3, function() ns.Client:RequestLedger(true) end) end
	refresh()
end
install()
