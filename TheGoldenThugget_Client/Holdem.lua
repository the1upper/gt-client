-- The Golden Thugget: Texas Hold'em rules — hand evaluator, pots and the
-- no-limit betting engine. Pure Lua (no WoW API), shared by the house and every
-- client, so clients can re-check the house's showdowns and pot splits.
--
-- Chips are copper. Every player starts a table with the same buy-in (50 BB).
local _, ns = ...
if ns and ns.skip then return end
local HE = {}
if ns then ns.Holdem = HE end

local floor, max, min = math.floor, math.max, math.min

---------------------------------------------------------------------------
-- Hand evaluator: best 5 of up to 7 cards
---------------------------------------------------------------------------
local RANKS = "23456789TJQKA"
local VAL = {}
for i = 1, 13 do VAL[RANKS:sub(i, i)] = i + 1 end
local function value(code) return VAL[code:sub(1, 1)] end
local function suit(code) return code:sub(2, 2) end
HE.Value = value

local WORD = { [2] = "Two", [3] = "Three", [4] = "Four", [5] = "Five", [6] = "Six", [7] = "Seven", [8] = "Eight",
	[9] = "Nine", [10] = "Ten", [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }
local PLURAL = {}
for v, w in pairs(WORD) do PLURAL[v] = (v == 6) and "Sixes" or (w .. "s") end
HE.WORD, HE.PLURAL = WORD, PLURAL

HE.CATEGORY = { [0] = "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush", "Full House",
	"Four of a Kind", "Straight Flush" }

local B = 15
local function score(cat, t)
	local s = cat
	for i = 1, 5 do s = s * B + (t[i] or 0) end
	return s
end

-- Name of a hand from its category and tie-break ranks
local function handName(cat, t)
	if cat == 8 then return t[1] == 14 and "Royal Flush" or ("Straight Flush, " .. WORD[t[1]] .. " high") end
	if cat == 7 then return "Four of a Kind, " .. PLURAL[t[1]] end
	if cat == 6 then return ("Full House, %s full of %s"):format(PLURAL[t[1]], PLURAL[t[2]]) end
	if cat == 5 then return "Flush, " .. WORD[t[1]] .. " high" end
	if cat == 4 then return "Straight, " .. WORD[t[1]] .. " high" end
	if cat == 3 then return "Three of a Kind, " .. PLURAL[t[1]] end
	if cat == 2 then return ("Two Pair, %s and %s"):format(PLURAL[t[1]], PLURAL[t[2]]) end
	if cat == 1 then return "Pair of " .. PLURAL[t[1]] end
	return "High Card, " .. WORD[t[1]]
end

-- Rank groups, biggest group first then highest rank: {{rank, count}, ...}
local function groups(cards)
	local cnt = {}
	for _, c in ipairs(cards) do local v = value(c); cnt[v] = (cnt[v] or 0) + 1 end
	local g = {}
	for v, n in pairs(cnt) do g[#g + 1] = { v, n } end
	table.sort(g, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] > b[1] end)
	return g
end

-- Exactly 5 cards (or fewer: before the flop / on a partial board, no
-- straights or flushes). Returns score, category, tie-break list.
local function evalFew(cards)
	local g = groups(cards)
	local t = {}
	local cat = 0
	if g[1] and g[1][2] == 4 then cat = 7
	elseif g[1] and g[1][2] == 3 and g[2] and g[2][2] >= 2 then cat = 6
	elseif g[1] and g[1][2] == 3 then cat = 3
	elseif g[1] and g[1][2] == 2 and g[2] and g[2][2] == 2 then cat = 2
	elseif g[1] and g[1][2] == 2 then cat = 1 end
	for _, x in ipairs(g) do t[#t + 1] = x[1] end
	return score(cat, t), cat, t
end

local function eval5(cards)
	local vals = {}
	for i = 1, 5 do vals[i] = value(cards[i]) end
	table.sort(vals, function(a, b) return a > b end)
	local flush = true
	for i = 2, 5 do if suit(cards[i]) ~= suit(cards[1]) then flush = false end end
	local straight, high = false, nil
	local distinct = true
	for i = 2, 5 do if vals[i] == vals[i - 1] then distinct = false end end
	if distinct then
		if vals[1] - vals[5] == 4 then straight, high = true, vals[1]
		elseif vals[1] == 14 and vals[2] == 5 and vals[5] == 2 then straight, high = true, 5 end -- the wheel
	end
	if straight and flush then return score(8, { high }), 8, { high } end
	local s, cat, t = evalFew(cards)
	if cat >= 6 then return s, cat, t end
	if flush then return score(5, vals), 5, vals end
	if straight then return score(4, { high }), 4, { high } end
	return s, cat, t
end

-- Best hand from 2..7 cards. Returns { score, cat, name, cards = best 5 (or all) }
function HE.Eval(cards)
	local n = #cards
	if n < 5 then
		local s, cat, t = evalFew(cards)
		local name
		if cat == 0 then
			local hi = {}
			for _, c in ipairs(cards) do hi[#hi + 1] = value(c) end
			table.sort(hi, function(a, b) return a > b end)
			name = (#hi >= 2 and hi[1] ~= hi[2]) and (WORD[hi[1]] .. "-" .. WORD[hi[2]] .. " high") or ("High Card, " .. WORD[hi[1]])
		else
			name = handName(cat, t)
		end
		local copy = {}
		for i, c in ipairs(cards) do copy[i] = c end
		return { score = s, cat = cat, name = name, cards = copy }
	end
	local best, bestCat, bestT, bestCards
	local pick = {}
	-- every 5-card combination (21 for 7 cards)
	local function rec(start, depth)
		if depth > 5 then
			local s, cat, t = eval5(pick)
			if not best or s > best then
				best, bestCat, bestT = s, cat, t
				bestCards = { pick[1], pick[2], pick[3], pick[4], pick[5] }
			end
			return
		end
		for i = start, n - (5 - depth) do
			pick[depth] = cards[i]
			rec(i + 1, depth + 1)
		end
	end
	rec(1, 1)
	return { score = best, cat = bestCat, name = handName(bestCat, bestT), cards = bestCards }
end

---------------------------------------------------------------------------
-- Pots. contrib = player -> copper put in this hand. Each layer of money is
-- won by the best live hand among players who put in at least that much.
-- A layer only one player paid into is an uncalled bet: it goes back to them.
--   order  : players in seat order (decides the order of eligible lists)
-- Returns { { amount, eligible = {...}, uncalled = true|nil }, ... } main pot first
---------------------------------------------------------------------------
function HE.Pots(order, contrib, folded)
	-- every contribution level, folded players' too, so an uncalled bet always
	-- ends up in a layer of its own
	local levels, seen = {}, {}
	for _, p in ipairs(order) do
		local c = contrib[p] or 0
		if c > 0 and not seen[c] then seen[c] = true; levels[#levels + 1] = c end
	end
	table.sort(levels)
	local layers, prev, carry = {}, 0, 0
	for _, L in ipairs(levels) do
		local amt, payers, payer, elig = 0, 0, nil, {}
		for _, p in ipairs(order) do
			local part = max(0, min(contrib[p] or 0, L) - prev)
			if part > 0 then amt, payers, payer = amt + part, payers + 1, p end
			if not folded[p] and (contrib[p] or 0) >= L then elig[#elig + 1] = p end
		end
		if #elig == 0 then
			-- only folded money at this level (can't normally happen): it stays in the pot below
			if #layers > 0 then layers[#layers].amount = layers[#layers].amount + amt; layers[#layers].uncalled = nil
			else carry = carry + amt end
		else
			local uncalled = (payers == 1 and #elig == 1 and elig[1] == payer) or nil
			layers[#layers + 1] = { amount = amt + carry, eligible = elig, uncalled = (carry == 0 and uncalled) or nil }
			carry = 0
		end
		prev = L
	end
	-- join neighbouring contested layers with the same players
	local pots = {}
	for _, l in ipairs(layers) do
		local p = pots[#pots]
		local same = p and not p.uncalled and not l.uncalled and #p.eligible == #l.eligible
		if same then for i = 1, #l.eligible do if p.eligible[i] ~= l.eligible[i] then same = false end end end
		if same then p.amount = p.amount + l.amount else pots[#pots + 1] = l end
	end
	return pots
end

-- Split every pot. scores: player -> hand score (live hands at showdown).
-- leftOfButton: players starting left of the button (odd copper goes to the first winner).
-- Returns results { {amount, winners = {...}, shares = {p = c}, uncalled} }, won = p -> total
function HE.Award(pots, scores, leftOfButton)
	local rank = {}
	for i, p in ipairs(leftOfButton) do rank[p] = i end
	local results, won = {}, {}
	for _, pot in ipairs(pots) do
		local winners = {}
		if #pot.eligible == 1 then
			winners[1] = pot.eligible[1]
		else
			local best
			for _, p in ipairs(pot.eligible) do
				local s = scores[p]
				if s and (not best or s > best) then best = s end
			end
			for _, p in ipairs(pot.eligible) do if scores[p] == best then winners[#winners + 1] = p end end
		end
		table.sort(winners, function(a, b) return (rank[a] or 99) < (rank[b] or 99) end)
		local share = floor(pot.amount / #winners)
		local rem = pot.amount - share * #winners
		local shares = {}
		for i, w in ipairs(winners) do
			shares[w] = share + (i == 1 and rem or 0)
			won[w] = (won[w] or 0) + shares[w]
		end
		results[#results + 1] = { amount = pot.amount, winners = winners, shares = shares, uncalled = pot.uncalled }
	end
	return results, won
end

---------------------------------------------------------------------------
-- Betting engine (no-limit). One hand at a time.
--   t = { order = { names in seat order }, stacks = { name -> copper },
--         button = name (must have chips), bb = copper, sb = copper }
-- Players with no chips sit the hand out.
---------------------------------------------------------------------------
local Hand = {}
Hand.__index = Hand
HE.HandMeta = Hand

local function post(h, p, amt)
	local a = min(h.stack[p], amt)
	h.stack[p] = h.stack[p] - a
	h.bet[p] = h.bet[p] + a
	h.contrib[p] = h.contrib[p] + a
	if h.stack[p] == 0 then h.allin[p] = true end
	return a
end

function HE.NewHand(t)
	local h = setmetatable({
		order = {}, players = {}, stack = {}, bet = {}, contrib = {}, folded = {}, allin = {},
		needs = {}, acted = {}, reopen = {}, board = {}, street = "preflop", bb = t.bb, sb = t.sb, log = {},
	}, Hand)
	for _, p in ipairs(t.order) do
		h.order[#h.order + 1] = p
		h.stack[p] = t.stacks[p] or 0
		if h.stack[p] > 0 then h.players[#h.players + 1] = p end
	end
	for _, p in ipairs(h.players) do h.bet[p], h.contrib[p] = 0, 0 end
	local n = #h.players
	assert(n >= 2, "need two players with chips")
	local bi = 1
	for i, p in ipairs(h.players) do if p == t.button then bi = i end end
	h.button = h.players[bi]
	-- ring: everyone in the hand starting left of the button, button last
	h.ring = {}
	for k = 1, n do h.ring[k] = h.players[(bi + k - 1) % n + 1] end
	if n == 2 then h.sbP, h.bbP = h.button, h.ring[1] -- heads-up: the button posts the small blind
	else h.sbP, h.bbP = h.ring[1], h.ring[2] end
	post(h, h.sbP, h.sb)
	post(h, h.bbP, h.bb)
	h.curBet, h.minRaise = h.bb, h.bb -- a short all-in big blind still makes the bet a full big blind
	for _, p in ipairs(h.players) do if not h.allin[p] then h.needs[p] = true end end
	-- first to act: heads-up the button (small blind); otherwise left of the big blind
	h:SetTurn(n == 2 and h.sbP or h.ring[3], true)
	return h
end

function Hand:InHand(p) return self.bet[p] ~= nil end
function Hand:Live(p) return self.bet[p] ~= nil and not self.folded[p] end
function Hand:Active(p) return self:Live(p) and not self.allin[p] end

function Hand:Count(fn)
	local n = 0
	for _, p in ipairs(self.players) do if fn(self, p) then n = n + 1 end end
	return n
end

function Hand:Pot()
	local s = 0
	for _, p in ipairs(self.players) do s = s + self.contrib[p] end
	return s
end

local function ringIndex(h, p)
	for i, q in ipairs(h.ring) do if q == p then return i end end
end

-- Does p still have to act on this street?
function Hand:Owes(p)
	if not self:Active(p) then return false end
	local toCall = self.curBet - self.bet[p]
	-- the only player left with chips, nothing to call: no decision to make
	if toCall <= 0 and self:Count(Hand.Active) <= 1 then return false end
	return self.needs[p] or toCall > 0
end

-- Next player (from p, or including p when inclusive) who owes an action
function Hand:SetTurn(from, inclusive)
	local n = #self.ring
	local i = ringIndex(self, from) or 1
	for k = inclusive and 0 or 1, n do
		local q = self.ring[(i + k - 1) % n + 1]
		if self:Owes(q) then self.toAct = q; return q end
	end
	self.toAct = nil
	return nil
end

-- What p may do now
function Hand:Legal(p)
	if p ~= self.toAct then return nil end
	local stack, bet = self.stack[p], self.bet[p]
	local toCall = min(self.curBet - bet, stack)
	local others = 0
	for _, q in ipairs(self.players) do if q ~= p and self:Active(q) then others = others + 1 end end
	local maxTo = bet + stack
	local canRaise = stack > (self.curBet - bet) and others > 0 and (not self.acted[p] or self.reopen[p])
	local minTo = self.curBet == 0 and self.bb or (self.curBet + self.minRaise)
	if minTo > maxTo then minTo = maxTo end -- only all-in is possible
	return {
		check = toCall == 0, call = toCall > 0, toCall = toCall,
		raise = canRaise, minTo = minTo, maxTo = maxTo, bet = self.curBet == 0,
	}
end

-- p acts: "fold" | "check" | "call" | "raise" (to = total bet this street) | "allin"
-- Returns true, or nil and a reason.
function Hand:Act(p, kind, to)
	local L = self:Legal(p)
	if not L then return nil, "not your turn" end
	local before = self.bet[p]
	if kind == "allin" then
		if L.raise and self.bet[p] + self.stack[p] > self.curBet then kind, to = "raise", L.maxTo
		elseif L.call then kind = "call"
		else kind = "check" end
	end
	if kind == "fold" then
		self.folded[p] = true
	elseif kind == "check" then
		if not L.check then return nil, "can't check" end
	elseif kind == "call" then
		if not L.call then return nil, "nothing to call" end
		post(self, p, L.toCall)
	elseif kind == "raise" then
		if not L.raise then return nil, "can't raise" end
		to = floor(tonumber(to) or 0)
		if to < L.minTo or to > L.maxTo then return nil, "bad amount" end
		local inc = to - self.curBet
		post(self, p, to - self.bet[p])
		if inc >= self.minRaise then
			-- a full raise: everyone gets to act (and raise) again
			self.minRaise = inc
			for _, q in ipairs(self.players) do if q ~= p then self.reopen[q] = true end end
		end
		-- a short all-in raise still has to be called, but doesn't reopen the raising
		self.curBet = to
		self.aggressor = p
		for _, q in ipairs(self.players) do if q ~= p and self:Active(q) then self.needs[q] = true end end
	else
		return nil, "unknown action"
	end
	self.needs[p], self.acted[p], self.reopen[p] = false, true, false
	self.log[#self.log + 1] = { p = p, kind = kind, to = self.bet[p], put = self.bet[p] - before, street = self.street }
	self.last = self.log[#self.log]
	if self:Count(Hand.Live) <= 1 then self.toAct = nil; self.over = "fold"; return true end
	self:SetTurn(p, false)
	return true
end

-- Nobody left to act on this street?
function Hand:StreetDone() return self.toAct == nil and not self.over end

-- After a finished street: "flop" / "turn" / "river" (deal it), "runout" (all-in:
-- deal the rest with no more betting) or "showdown".
local NEXT = { preflop = "flop", flop = "turn", turn = "river" }
function Hand:NextStep()
	if self.over then return "over" end
	if self.street == "river" then return "showdown" end
	if self:Count(Hand.Active) <= 1 then return "runout" end
	return NEXT[self.street]
end

-- Start the next betting street (after its cards are on the board)
function Hand:NewStreet(name)
	self.street = name
	for _, p in ipairs(self.players) do self.bet[p] = 0 end
	self.curBet, self.minRaise = 0, self.bb
	self.needs, self.acted, self.reopen, self.aggressor = {}, {}, {}, nil
	for _, p in ipairs(self.players) do if self:Active(p) then self.needs[p] = true end end
	self:SetTurn(self.ring[1], true)
end

-- Showdown order: the last player to bet or raise on the final street shows
-- first, otherwise the first live player left of the button; then clockwise.
function Hand:ShowOrder()
	local start = (self.aggressor and self:Live(self.aggressor)) and ringIndex(self, self.aggressor) or 1
	local out, n = {}, #self.ring
	for k = 0, n - 1 do
		local q = self.ring[(start + k - 1) % n + 1]
		if self:Live(q) then out[#out + 1] = q end
	end
	return out
end

function Hand:Pots()
	local folded = {}
	for _, p in ipairs(self.order) do folded[p] = self.folded[p] or not self.bet[p] end
	return HE.Pots(self.order, self.contrib, folded)
end

-- Finish the hand. holes: player -> {2 codes} (live players). Board must be
-- complete unless everyone else folded. Returns a result:
--   { pots = results from HE.Award, won = p -> c, shows = { p, ... } (in order),
--     hands = p -> Eval, stacks = p -> copper after, uncontested = true|nil }
function Hand:Settle(holes)
	local pots = self:Pots()
	local res = { shows = {}, hands = {} }
	local scores = {}
	if self.over == "fold" then
		res.uncontested = true
	else
		local order = self:ShowOrder()
		for _, p in ipairs(order) do
			local cards = { holes[p][1], holes[p][2] }
			for _, b in ipairs(self.board) do cards[#cards + 1] = b end
			res.hands[p] = HE.Eval(cards)
			scores[p] = res.hands[p].score
		end
		-- who has to show: the first to show, anyone winning a share of a pot, and
		-- everyone when the hand was run out all-in. Others muck.
		res.pots, res.won = HE.Award(pots, scores, self.ring)
		local must = {}
		for _, r in ipairs(res.pots) do
			if #r.winners >= 1 and not r.uncalled then for _, w in ipairs(r.winners) do must[w] = true end end
		end
		for i, p in ipairs(order) do
			if i == 1 or must[p] or self.ranOut then res.shows[#res.shows + 1] = p end
		end
	end
	if not res.pots then res.pots, res.won = HE.Award(pots, scores, self.ring) end
	res.stacks = {}
	for _, p in ipairs(self.order) do
		res.stacks[p] = (self.stack[p] or 0) + (res.won[p] or 0)
	end
	return res
end

---------------------------------------------------------------------------
-- Table helpers
---------------------------------------------------------------------------
-- Next button: the next seat (after the old button) that still has chips
function HE.NextButton(order, stacks, old)
	local n = #order
	local i = 0
	for k, p in ipairs(order) do if p == old then i = k end end
	for k = 1, n do
		local q = order[(i + k - 1) % n + 1]
		if (stacks[q] or 0) > 0 then return q end
	end
end

-- "34 BB (1,700g)" style stack text for the UI
function HE.BB(c, bb)
	if not bb or bb <= 0 then return "0" end
	local v = c / bb
	if v == floor(v) then return tostring(v) end
	return ("%.1f"):format(v)
end

-- Rules text and blinds for a buy-in
function HE.Blinds(buyin)
	local bb = floor(buyin / 50)
	return floor(bb / 2), bb
end

return HE
