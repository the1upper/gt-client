-- The Golden Thugget: Texas Hold'em client. Follows the house's snapshots, opens
-- your own hole cards, sends your actions (and pre-actions), and re-checks every
-- showdown and pot split with the shared rules in Holdem.lua. Every card you saw
-- is audited against the real decks when the table closes (CardClient:Audit).
local _, ns = ...
if ns.skip then return end
local HC = {}
ns.HoldemClient = HC
local K, HE = ns.Cards, ns.Holdem
local J = function(...) return ns.Join(...) end

local function refresh()
	if ns.HoldemUI and ns.HoldemUI.Refresh then ns.HoldemUI:Refresh() end
	if ns.ClientUI and ns.ClientUI.Refresh then ns.ClientUI:Refresh() end
end

local function flag(c, why)
	if not c.problem then
		c.problem = why
		ns.Notify("|cffff4040Warning:|r " .. why)
	end
end

local function addSeen(c, packed)
	local d, p, code = K.Unpack(packed)
	if d then
		c.seenKey = c.seenKey or {}
		local key = d .. "." .. p
		if not c.seenKey[key] then
			c.seenKey[key] = true
			c.seen[#c.seen + 1] = { d = d, p = p, c = code }
		end
	end
	return code
end

local function sound(kit)
	if ns.hush or not (PlaySound and SOUNDKIT) then return end
	local id = SOUNDKIT[kit]
	if id then pcall(PlaySound, id) end
end
HC.Sound = sound

-- the Hold'em state of my current table
local function state(id)
	local g = ns.Client.game
	if g and (not id or g.id == id) and g.cards and g.cards.he and g.phase == "playing" then return g, g.cards, g.cards.he end
end
HC.State = state

function HC:Seated(he) return he and ns.IndexOf(he.order, ns.me) ~= nil end

---------------------------------------------------------------------------
-- what I may do right now (from the latest snapshot)
---------------------------------------------------------------------------
function HC:Legal()
	local g, c, he = state()
	local st = he and he.st
	if not st or not st.toAct or st.toAct ~= ns.me or he.acted then return nil end
	local me = st.seat[ns.me]
	if not me then return nil end
	local toCall = math.min(st.curBet - me.bet, me.stack)
	local maxTo = me.bet + me.stack
	return {
		check = toCall <= 0, call = toCall > 0, toCall = toCall, raise = st.canRaise, bet = st.curBet == 0,
		minTo = math.min(st.minTo, maxTo), maxTo = maxTo, myBet = me.bet, pot = st.pot, curBet = st.curBet,
	}
end

-- Pot-sized raise to (total this street): call, then raise by the pot after the call
function HC:PotTo(fraction)
	local L = self:Legal()
	if not L then return 0 end
	local potAfterCall = L.pot + L.toCall
	local to = L.curBet + math.floor(potAfterCall * (fraction or 1))
	return math.max(L.minTo, math.min(L.maxTo, to))
end

function HC:Act(kind, to)
	local g, c, he = state()
	if not he or not he.st or he.acted or he.st.toAct ~= ns.me then return end
	he.acted = true
	he.pre = nil
	ns.Client:ToHost(J("HA", g.id, he.hand, he.st.v, kind, to or 0))
	refresh()
end
function HC:Fold() self:Act("fold") end
function HC:Check() self:Act("check") end
function HC:Call() self:Act("call") end
function HC:AllIn() self:Act("allin") end
function HC:Raise(to)
	local L = self:Legal()
	if not L or not L.raise then return end
	to = math.max(L.minTo, math.min(L.maxTo, math.floor(tonumber(to) or 0)))
	if to >= L.maxTo then return self:Act("allin") end
	self:Act("raise", to)
end

-- Pre-actions: "checkfold" | "check" | "callany" (cleared when you act or the street ends)
function HC:SetPre(kind)
	local g, c, he = state()
	if not he then return end
	he.pre = (he.pre ~= kind) and kind or nil
	he.preStreet, he.preBet = he.st and he.st.street, he.st and he.st.curBet
	refresh()
end

function HC:Back()
	local g = state()
	if g then ns.Client:ToHost(J("HBACK", g.id)) end
end
function HC:Away()
	local g = state()
	if g then ns.Client:ToHost(J("HAWAY", g.id)) end
end
function HC:ShowCards()
	local g, c, he = state()
	if not he or not he.canShow then return end
	he.canShow = nil
	ns.Client:ToHost(J("HSHOWME", g.id, he.hand))
	refresh()
end

-- My turn came up: play a pre-action if one is set
local function applyPre(he)
	local pre = he.pre
	if not pre then return false end
	local L = HC:Legal()
	if not L then return false end
	if pre == "checkfold" then HC:Act(L.check and "check" or "fold") return true end
	if pre == "check" then
		if L.check then HC:Act("check") return true end
		he.pre = nil -- someone bet: decide yourself
		return false
	end
	if pre == "callany" then HC:Act(L.check and "check" or "call") return true end
	return false
end

---------------------------------------------------------------------------
-- my hand
---------------------------------------------------------------------------
function HC:MyHand()
	local g, c, he = state()
	if not he then
		g = ns.Client.game
		c = g and g.cards
		he = c and c.he
	end
	if not he or not he.my then return nil end
	local cards = { he.my[1], he.my[2] }
	for _, b in ipairs(he.board) do cards[#cards + 1] = b end
	return HE.Eval(cards)
end

function HC:OpenHole(g, c, he, sealed)
	local plain = sealed and sealed ~= "" and K.Open(K.HandKey(g.id, "h" .. he.hand, g.secret), sealed)
	local hole = {}
	for _, packed in ipairs(ns.List(plain or "")) do
		local code = addSeen(c, packed)
		if code then hole[#hole + 1] = code end
	end
	if #hole ~= 2 then return flag(c, "couldn't open your hole cards.") end
	he.my = hole
	he.myPacked = ns.List(plain)
	ns.Print(("Hand %d - your cards: %s."):format(he.hand, K.TextList(hole)))
	if ns.HoldemUI then ns.HoldemUI:DealHole() end
	refresh()
end

---------------------------------------------------------------------------
-- incoming
---------------------------------------------------------------------------
local function parseSeats(he, text)
	local seat, list = {}, ns.List(text, true)
	for i, p in ipairs(he.order) do
		local stack, bet, contrib, fl = (list[i] or ""):match("^(%d+):(%d+):(%d+):(%a*)$")
		if stack then
			seat[p] = {
				stack = tonumber(stack), bet = tonumber(bet), contrib = tonumber(contrib),
				folded = fl:find("f") ~= nil, allin = fl:find("a") ~= nil, out = fl:find("x") ~= nil, away = fl:find("s") ~= nil,
			}
		end
	end
	return seat
end

local function install()
	local H = ns.Client.H

	-- HTABLE^id^order^buttonSeat^buyin^bb^sb^hands^turnTime
	H.HTABLE = function(sender, f)
		local g = ns.Client.game
		local c = g and g.id == f[2] and g.cards
		if not c or c.he then return end
		local he = {
			order = ns.List(f[3]), buyin = tonumber(f[5]) or g.wager, bb = tonumber(f[6]) or 0, sb = tonumber(f[7]) or 0,
			hands = tonumber(f[8]) or 1, decide = tonumber(f[9]) or 15, hand = 0, board = {}, boardPacked = {}, stacks = {}, shown = {}, recaps = {},
		}
		he.button = he.order[tonumber(f[4]) or 1]
		he.firstButton = he.button
		for _, p in ipairs(he.order) do he.stacks[p] = he.buyin; c.deltas[p] = 0 end
		c.seats = { unpack(he.order) }
		c.he = he
		c.phase = "holdem"
		local sb, bb = HE.Blinds(he.buyin)
		if sb ~= he.sb or bb ~= he.bb then flag(c, "the blinds don't match the buy-in.") end
		-- seat order and the first button are drawn from the seed: re-checked at the audit
		g.touched = GetTime()
		if ns.HoldemUI then ns.HoldemUI:Open() end
		refresh()
	end

	-- HSTART^id^hand^buttonSeat^sbSeat^bbSeat
	H.HSTART = function(sender, f)
		local g, c, he = state(f[2])
		if not he then return end
		local hand = tonumber(f[3])
		if not hand or hand <= he.hand then return end
		he.hand = hand
		he.button = he.order[tonumber(f[4])] or he.button
		he.sbP, he.bbP = he.order[tonumber(f[5])], he.order[tonumber(f[6])]
		he.board, he.boardPacked, he.shown, he.my, he.myPacked = {}, {}, {}, nil, nil
		he.st, he.acted, he.pre, he.result, he.canShow, he.flipped = nil, nil, nil, nil, nil, nil
		he.handStart = {}
		for _, p in ipairs(he.order) do he.handStart[p] = he.stacks[p] end
		he.startAt = GetTime()
		-- everyone with chips is dealt in, starting left of the button
		he.ring = {}
		local n = #he.order
		local bi = ns.IndexOf(he.order, he.button) or 1
		for k = 1, n do
			local p = he.order[(bi + k - 1) % n + 1]
			if (he.stacks[p] or 0) > 0 then he.ring[#he.ring + 1] = p end
		end
		g.touched = GetTime()
		local ph = he.pendingHole
		if ph and tonumber(ph[3]) == hand then he.pendingHole = nil; HC:OpenHole(g, c, he, ph[4]) end
		if ns.HoldemUI then ns.HoldemUI:NewHand() end
		refresh()
	end

	-- HHOLE^id^hand^sealed : your own hole cards (whispered tables)
	H.HHOLE = function(sender, f)
		local g, c, he = state(f[2])
		if not he then return end
		local hand = tonumber(f[3])
		if not hand or hand < he.hand or (hand == he.hand and he.my) then return end
		if hand > he.hand then he.pendingHole = f return end -- HSTART not here yet
		HC:OpenHole(g, c, he, f[4])
	end

	-- HHOLES^id^hand^sealed,sealed,... (seat order; only you can open yours)
	H.HHOLES = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand or he.my then return end
		local i = ns.IndexOf(he.order, ns.me)
		if not i then return end
		local mine = ns.List(f[4], true)[i]
		if mine and mine ~= "" then HC:OpenHole(g, c, he, mine) end
	end

	-- HST^id^hand^v^street^toActSeat^secs^curBet^minRaise^canRaise^minTo^seats^last
	H.HST = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand then return end
		local v = tonumber(f[4]) or 0
		if he.st and v <= he.st.v then return end
		local prev = he.st
		local st = {
			v = v, street = f[5], toAct = he.order[tonumber(f[6]) or 0], secs = tonumber(f[7]) or 0,
			curBet = tonumber(f[8]) or 0, minRaise = tonumber(f[9]) or 0, canRaise = f[10] == "1", minTo = tonumber(f[11]) or 0,
			seat = parseSeats(he, f[12]),
		}
		local pot = 0
		local chips = 0
		for _, p in ipairs(he.order) do
			local s = st.seat[p]
			if s then pot = pot + s.contrib; chips = chips + s.stack + s.contrib end
		end
		st.pot = pot
		-- chips are conserved: stacks + what's in the pot = every buy-in
		if chips ~= he.buyin * #he.order then flag(c, "the chip count doesn't add up.") end
		-- last action, for the log and the seat labels
		local li, kind, to, put = (f[13] or ""):match("^(%d+):(%a+):(%d+):(%d+)$")
		if li then
			local p = he.order[tonumber(li)]
			st.last = { p = p, kind = kind, to = tonumber(to), put = tonumber(put) }
			he.lastAct = he.lastAct or {}
			he.lastAct[p] = st.last
			local word = kind == "raise" and ((prev and prev.curBet == 0) and "bets" or "raises to") or (kind .. "s")
			local amt = kind == "raise" and (" " .. ns.Money(st.last.to)) or kind == "call" and (" " .. ns.Money(st.last.put)) or ""
			ns.Log(("%s %s%s"):format(ns.Short(p), word, amt))
		end
		if prev and prev.street ~= st.street then he.lastAct = {} end
		he.st = st
		he.deadline = GetTime() + st.secs
		he.warned = nil
		-- every new snapshot is a fresh decision point (the house ignores anything stale,
		-- and a refused action comes back as a new snapshot with your turn still up)
		he.acted = nil
		-- a new street or a bet clears the "check" pre-action
		if he.pre and (he.preStreet ~= st.street) then he.pre = nil end
		if he.pre == "check" and st.curBet > (st.seat[ns.me] and st.seat[ns.me].bet or 0) then he.pre = nil end
		if st.toAct == ns.me and not he.acted then
			if not applyPre(he) then
				if not (prev and prev.toAct == ns.me and prev.street == st.street) then
					sound("READY_CHECK")
					if not g.watching then ns.Notify("Your turn" .. ((st.seat[ns.me] and st.curBet > st.seat[ns.me].bet) and (" - " .. ns.Money(st.curBet - st.seat[ns.me].bet) .. " to call") or "") .. ".") end
				end
			end
		end
		g.touched = GetTime()
		if ns.HoldemUI then ns.HoldemUI:State(prev, st) end
		refresh()
	end

	-- HB^id^hand^street^d.p.c,...
	H.HB = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand then return end
		local want = ({ flop = 0, turn = 3, river = 4 })[f[4]]
		if want == nil or #he.board ~= want then return end
		for _, packed in ipairs(ns.List(f[5])) do
			local code = addSeen(c, packed)
			if code then he.board[#he.board + 1] = code; he.boardPacked[#he.boardPacked + 1] = packed end
		end
		ns.Log(("%s: %s"):format(f[4]:gsub("^%l", string.upper), K.TextList(he.board)))
		g.touched = GetTime()
		if ns.HoldemUI then ns.HoldemUI:Board(want + 1) end
		refresh()
	end

	-- HFLIP^id^hand^seat:d.p.c/d.p.c;... : all-in, every live hand face up
	H.HFLIP = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand then return end
		he.flipped = true
		for chunk in ((f[4] or "") .. ";"):gmatch("([^;]*);") do
			local idx, cards = chunk:match("^(%d+):(.+)$")
			local p = idx and he.order[tonumber(idx)]
			if p then
				local h = {}
				for packed in (cards .. "/"):gmatch("([^/]*)/") do local code = addSeen(c, packed); if code then h[#h + 1] = code end end
				he.shown[p] = h
				if p == ns.me and he.my and (h[1] ~= he.my[1] or h[2] ~= he.my[2]) then flag(c, "the house showed different cards than you were dealt.") end
			end
		end
		g.touched = GetTime()
		if ns.HoldemUI then ns.HoldemUI:Flip() end
		refresh()
	end

	-- HEND^id^hand^fold|show^shows^pots^stacks
	H.HEND = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand or he.result then return end
		local st = he.st
		local uncontested = f[4] == "fold"
		local shows, order = {}, {}
		for chunk in ((f[5] or "") .. ";"):gmatch("([^;]*);") do
			local idx, cards = chunk:match("^(%d+):(.+)$")
			local p = idx and he.order[tonumber(idx)]
			if p then
				local h = {}
				for packed in (cards .. "/"):gmatch("([^/]*)/") do local code = addSeen(c, packed); if code then h[#h + 1] = code end end
				shows[p] = h
				he.shown[p] = h
				order[#order + 1] = p
				if p == ns.me and he.my and (h[1] ~= he.my[1] or h[2] ~= he.my[2]) then flag(c, "the house showed different cards than you were dealt.") end
			end
		end
		local pots = {}
		for chunk in ((f[6] or "") .. ";"):gmatch("([^;]*);") do
			local amt, ws, u = chunk:match("^(%d+)>([%d%.]*)>(u?)$")
			if amt then
				local winners = {}
				for w in ws:gmatch("%d+") do winners[#winners + 1] = he.order[tonumber(w)] end
				pots[#pots + 1] = { amount = tonumber(amt), winners = winners, uncalled = u == "u" }
			end
		end
		local after = {}
		for i, s in ipairs(ns.List(f[7], true)) do after[he.order[i]] = tonumber(s) end
		-- re-check: rebuild the pots from the final snapshot and split them ourselves
		local hands = {}
		local ok = st ~= nil
		if ok then
			local contrib, folded = {}, {}
			for _, p in ipairs(he.order) do
				local s = st.seat[p]
				contrib[p] = s and s.contrib or 0
				folded[p] = not s or s.folded or s.out
			end
			local mine = HE.Pots(he.order, contrib, folded)
			local scores = {}
			for p, h in pairs(shows) do
				local cards = { h[1], h[2] }
				for _, b in ipairs(he.board) do cards[#cards + 1] = b end
				hands[p] = HE.Eval(cards)
				scores[p] = hands[p].score
			end
			if not uncontested and #he.board ~= 5 then ok = false end
			local res, won = HE.Award(mine, scores, he.ring or he.order)
			if #res ~= #pots then ok = false end
			for i, r in ipairs(res) do
				local q = pots[i]
				if not q or q.amount ~= r.amount or #q.winners ~= #r.winners then ok = false
				else for k, w in ipairs(r.winners) do if q.winners[k] ~= w then ok = false end end end
			end
			for _, p in ipairs(he.order) do
				local s = st.seat[p]
				if (s and s.stack or 0) + (won[p] or 0) ~= (after[p] or -1) then ok = false end
			end
		end
		if not ok and not c.gap then flag(c, "a Hold'em pot wasn't split the way the rules say.") end
		local net = 0
		for _, p in ipairs(he.order) do
			he.stacks[p] = after[p] or he.stacks[p]
			c.deltas[p] = he.stacks[p] - he.buyin
			net = net + c.deltas[p]
		end
		if net ~= 0 then flag(c, "the table's totals don't add up to zero.") end
		-- recap of the hand (shown in the window)
		local recap = { hand = he.hand, board = { unpack(he.board) }, shows = {}, pots = pots, uncontested = uncontested, net = {} }
		for _, p in ipairs(order) do recap.shows[#recap.shows + 1] = { p = p, cards = shows[p], name = hands[p] and hands[p].name } end
		for _, p in ipairs(he.order) do
			local d = (he.stacks[p] or 0) - (he.handStart and he.handStart[p] or he.stacks[p])
			if d ~= 0 then recap.net[p] = d end
		end
		he.result = recap
		he.recaps[#he.recaps + 1] = recap
		he.lastRecap = recap
		-- the winning five cards (first pot) for the highlight
		local first = pots[1] and not pots[1].uncalled and pots[1] or pots[2]
		local w = first and first.winners[1]
		he.winCards = (not uncontested and w and hands[w]) and hands[w].cards or nil
		he.winName = (not uncontested and w and hands[w]) and hands[w].name or nil
		-- chat
		local lines = {}
		for _, r in ipairs(pots) do
			local wn = {}
			for i, p in ipairs(r.winners) do wn[i] = ns.Short(p) end
			if r.uncalled then lines[#lines + 1] = ("%s back to %s"):format(ns.Money(r.amount), wn[1] or "?")
			else lines[#lines + 1] = ("%s %s %s%s"):format(table.concat(wn, " & "), #wn > 1 and "split" or "wins", ns.Money(r.amount),
				(hands[r.winners[1]] and (" - " .. hands[r.winners[1]].name)) or "") end
		end
		ns.Notify(("Hand %d: %s"):format(he.hand, table.concat(lines, "; ")))
		local mine = recap.net[ns.me]
		if mine and not g.watching then ns.Print("You " .. ns.WonLost(mine) .. " this hand.") end
		he.canShow = uncontested and pots[1] and pots[1].winners[1] == ns.me and not g.watching and he.my and true or nil
		if st then st.toAct = nil end -- the hand is over: nobody to act
		g.touched = GetTime()
		if ns.HoldemUI then ns.HoldemUI:Showdown() end
		refresh()
	end

	-- HSHOWN^id^hand^seat^d.p.c/d.p.c : the winner showed after all
	H.HSHOWN = function(sender, f)
		local g, c, he = state(f[2])
		if not he or tonumber(f[3]) ~= he.hand then return end
		local p = he.order[tonumber(f[4]) or 0]
		if not p then return end
		local h = {}
		for packed in ((f[5] or "") .. "/"):gmatch("([^/]*)/") do local code = addSeen(c, packed); if code then h[#h + 1] = code end end
		he.shown[p] = h
		if he.lastRecap then he.lastRecap.shows[#he.lastRecap.shows + 1] = { p = p, cards = h } end
		ns.Log(ns.Short(p) .. " shows " .. K.TextList(h))
		if ns.HoldemUI then ns.HoldemUI:Flip() end
		refresh()
	end

	-- HVOID^id^hand^reason : the house reloaded mid-hand; that hand never happened
	H.HVOID = function(sender, f)
		local g = ns.Client.game
		if not (g and g.id == f[2]) or g.phase == "done" or g.phase == "aborted" then return end
		local c = g.cards
		local he = c and c.he
		g.phase = "done"
		if c then c.phase = "closed" end
		local mine = 0
		if he and he.handStart then
			for _, p in ipairs(he.order) do c.deltas[p] = (he.handStart[p] or he.buyin) - he.buyin end
		end
		if c then mine = c.deltas[ns.me] or 0 end
		if he then he.void = f[4] end
		ns.Notify("|cffffd100Hold'em table ended:|r " .. (f[4] or "the house reloaded") .. ".")
		if c and c.deltas[ns.me] and not g.watching then ns.Notify(ns.YouLine(mine)) end
		if not g.watching then
			local list = ns.Client:MyGames()
			list[#list + 1] = { id = g.id, t = time(), type = g.type, wager = g.wager, delta = mine,
				summary = ("Texas Hold'em, %s buy-in: %s (ended early)"):format(ns.Money(g.wager), ns.WonLost(mine)) }
		end
		local tr = ns.Client.tables[g.id]
		if tr then ns.Client:SetTableStatus(tr, "closed") end
		ns.Client:CloseTableSoon(g)
		C_Timer.After(3 + math.random() * 3, function() ns.Client:RequestLedger(true) end)
		refresh()
	end
end
HC.Install = install

-- every second: turn warning, missing hole cards
function HC:Tick(now)
	local g, c, he = state()
	if not he then return end
	local st = he.st
	if st and st.toAct == ns.me and not he.acted and he.deadline and not g.watching then
		if not he.warned and he.deadline - now <= 5 and he.deadline - now > 0 then
			he.warned = true
			sound("RAID_WARNING")
		end
	end
	if he.hand > 0 and not he.my and he.startAt and now - he.startAt > 4 and HC:Seated(he)
		and he.ring and ns.IndexOf(he.ring, ns.me) and now - (he.lastNeed or 0) > 4 and not he.result then
		he.lastNeed = now
		ns.Client:ToHost(J("HHNEED", g.id, he.hand))
	end
end

install()
