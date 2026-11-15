-- The Golden Thugget: Games — deterministic outcomes from a shared seed.
-- Every client computes the same result from the same revealed secrets, so no one
-- has to see anyone else's /roll and no one (host included) can steer the dice.
local _, ns = ...
if ns.skip then return end
local G = {}
ns.Games = G

local floor = math.floor
local Short = function(n) return ns.Short(n) end
local Money = function(c) return ns.Money(c) end -- wagers are copper

-- High-Low counts in the biggest coin that still gives a roll of at least 100:
-- 250g -> 1-250 (gold), 10g -> 1-1000 (silver), 75s -> 1-7500 (copper).
-- A bet that doesn't divide evenly into a coin drops to the next one down.
function G.HighLowUnit(wager)
	wager = wager or 0
	if wager % 10000 == 0 and wager / 10000 >= 100 then return 10000 end
	if wager % 100 == 0 and wager / 100 >= 100 then return 100 end
	return 1
end

-- Death Roll's default start: the bet in its smallest coin, at least 100 (250g starts at 250)
local function deathStart(wager)
	wager = wager or 0
	local u = (wager % 100 ~= 0 and 1) or (wager % 10000 ~= 0 and 100) or 10000
	return math.max(100, math.floor(wager / u))
end

-- Net result per player from a dice result's debts
function G.Net(g, res)
	local net = {}
	for _, p in ipairs(g.players or {}) do net[p] = 0 end
	for _, d in ipairs(res.debts or {}) do
		net[d.from] = (net[d.from] or 0) - d.c
		net[d.to] = (net[d.to] or 0) + d.c
	end
	return net
end

-- Uniform-enough integer in [1, max] from the seed and a label.
function G.Rand(seed, key, max)
	local h = ns.SHA256(seed .. ":" .. key)
	local n = tonumber(h:sub(1, 8), 16) -- 0 .. 2^32-1
	return (n % max) + 1
end

local function debt(res, from, to, copper)
	if copper > 0 and from ~= to then
		res.debts[#res.debts + 1] = { from = from, to = to, c = copper }
	end
end

-- Repeatedly re-roll among tied players until one remains.
local function breakTie(seed, tag, names, max, wantHigh, log, rec)
	local round = 0
	while #names > 1 and round < 60 do
		round = round + 1
		local rolls, best = { list = rec }, nil
		local line = {}
		for _, n in ipairs(names) do
			local r = G.Rand(seed, tag .. round .. ":" .. n, max)
			rolls[n] = r
			if rolls.list then rolls.list[#rolls.list + 1] = { p = n, r = r, max = max, tie = round } end
			line[#line + 1] = Short(n) .. " " .. r
			if not best or (wantHigh and r > best) or (not wantHigh and r < best) then best = r end
		end
		log[#log + 1] = "  Tie-break: " .. table.concat(line, ", ")
		local nxt = {}
		for _, n in ipairs(names) do if rolls[n] == best then nxt[#nxt + 1] = n end end
		names = nxt
	end
	return names[1]
end

-- Coin Flip helpers
G.FACE = { H = "Heads", T = "Tails" }
-- which seat calls it: 1 or 2, from the table id (everyone can work it out).
-- A double-or-nothing flip (setting 1) is called by seat 1: the first game's loser.
function G.CoinCaller(g)
	if g.param == 1 or g.param == 2 then return g.param end
	return G.Rand(g.id or "", "caller", 2)
end
function G.IsDouble(g) return g.type == "coinflip" and (g.param == 1 or g.param == 2) end
-- the call sealed at the end of the caller's secret ("...H" / "...T")
function G.CoinCall(secret)
	local c = type(secret) == "string" and secret:sub(-1) or nil
	return (c == "H" or c == "T") and c or nil
end

G.order = { "deathroll", "highlow", "coinflip", "slots", "thugget", "guts", "acey", "blitz", "holdem" }

G.types = {
	-- Players roll in seat order; each roll is 1 to the one before. Whoever rolls
	-- a 1 pays the player who rolled just before them (the last one to survive).
	-- Protocol 10: older clients resolved it for two players only.
	deathroll = {
		name = "Death Roll",
		paramLabel = "Roll from",
		minPlayers = 2, maxPlayers = 12, minProto = 10,
		defaultParam = deathStart,
		describe = function(g)
			return ("Death Roll from %d - whoever rolls 1 pays the last roller %s"):format(g.param, Money(g.wager))
		end,
		resolve = function(g, seed, res)
			local p = g.players
			local n = #p
			local cur, turn = g.param, 1
			local prev = n -- a 1 on the very first roll pays the last seat
			for k = 1, 100000 do
				local r = G.Rand(seed, "d" .. k, cur)
				res.rolls[#res.rolls + 1] = { p = p[turn], r = r, max = cur }
				res.log[#res.log + 1] = ("%s rolls %d (1-%d)"):format(Short(p[turn]), r, cur)
				if r == 1 then
					local loser, winner = p[turn], p[prev]
					res.winner, res.loser = winner, loser
					debt(res, loser, winner, g.wager)
					res.summary = ("%s rolled 1 - pays %s %s"):format(Short(loser), Short(winner), Money(g.wager))
					return res
				end
				cur, prev, turn = r, turn, turn % n + 1
			end
			return res
		end,
	},

	-- The bet sets the roll, counted in the biggest coin that keeps it at 100 or
	-- more: 10g rolls 1-1000 (silver), 75s rolls 1-7500 (copper). The difference
	-- between the rolls is what's owed, paid in gold/silver/copper as usual.
	-- Protocol 10: older clients counted in the smallest coin (10g = 1-10).
	highlow = {
		name = "High-Low",
		paramLabel = "Max roll", fixedParam = true,
		minPlayers = 2, maxPlayers = 12, minProto = 10,
		defaultParam = function(wager) return wager / G.HighLowUnit(wager) end,
		describe = function(g)
			local u = G.HighLowUnit(g.wager)
			return ("High-Low - everyone rolls 1-%d (%s); lowest pays highest the difference, %s a point"):format(g.param, Money(g.wager), Money(u))
		end,
		resolve = function(g, seed, res)
			local rolls, hi, lo = {}, nil, nil
			for _, n in ipairs(g.players) do
				local r = G.Rand(seed, "r:" .. n, g.param)
				rolls[n] = r
				res.rolls[#res.rolls + 1] = { p = n, r = r, max = g.param }
				res.log[#res.log + 1] = ("%s rolls %d (1-%d)"):format(Short(n), r, g.param)
				hi = (not hi or r > hi) and r or hi
				lo = (not lo or r < lo) and r or lo
			end
			if hi == lo then
				res.summary = "Everyone tied - push, no gold owed"
				return res
			end
			local highs, lows = {}, {}
			for _, n in ipairs(g.players) do
				if rolls[n] == hi then highs[#highs + 1] = n end
				if rolls[n] == lo then lows[#lows + 1] = n end
			end
			local winner = breakTie(seed, "th", highs, g.param, true, res.log, res.rolls)
			local loser = breakTie(seed, "tl", lows, g.param, false, res.log, res.rolls)
			res.winner, res.loser = winner, loser
			local diff = hi - lo
			local owed = diff * G.HighLowUnit(g.wager)
			debt(res, loser, winner, owed)
			res.summary = ("%s rolled %d, %s rolled %d - %s pays %s %s"):format(Short(winner), hi, Short(loser), lo, Short(loser), Short(winner), Money(owed))
			return res
		end,
	},

	-- Two players. The table decides who calls (from its id, so anyone can check);
	-- the caller's HEADS/TAILS is the last letter of their sealed roll, so it's
	-- locked in before anyone - the caller included - can know how the coin lands.
	-- The coin itself comes from the shared seed like every other roll.
	-- Protocol 11 (new game).
	coinflip = {
		name = "Coin Flip", ui = "coin",
		paramLabel = "No setting", noParam = true,
		minPlayers = 2, maxPlayers = 2, minProto = 15, -- 15: double or nothing (setting 1 = seat 1 calls)
		defaultParam = function() return 0 end,
		describe = function(g)
			if G.IsDouble(g) then
				return ("Double or nothing for %s - win the flip and you're square, lose it and you owe double"):format(Money(g.wager))
			end
			return ("Coin Flip - one player calls heads or tails; a right call wins %s, a wrong one pays it"):format(Money(g.wager))
		end,
		resolve = function(g, seed, res, secrets)
			local p = g.players
			local ci = G.CoinCaller(g)
			local call = G.CoinCall(secrets and secrets[ci]) or "H"
			local face = G.Rand(seed, "coin", 2) == 1 and "H" or "T"
			local caller, other = p[ci], p[3 - ci]
			local winner = (call == face) and caller or other
			local loser = winner == caller and other or caller
			res.winner, res.loser = winner, loser
			res.coin = { caller = caller, call = call, face = face }
			debt(res, loser, winner, g.wager)
			res.log[#res.log + 1] = ("%s calls %s"):format(Short(caller), G.FACE[call])
			res.log[#res.log + 1] = ("The coin lands %s"):format(G.FACE[face])
			if G.IsDouble(g) then
				if winner == caller then
					res.summary = ("Double or nothing: %s called %s - it's %s! %s wins it back - all square"):format(Short(caller), G.FACE[call], G.FACE[face], Short(caller))
				else
					res.summary = ("Double or nothing: %s called %s - it's %s! %s owes double (%s in all)"):format(Short(caller), G.FACE[call], G.FACE[face], Short(caller), Money(2 * g.wager))
				end
			else
				res.summary = ("%s called %s - it's %s! %s wins %s"):format(Short(caller), G.FACE[call], G.FACE[face], Short(winner), Money(g.wager))
			end
			return res
		end,
	},

	-- Retired: no longer offered (not in G.order, refused by /gth open). Kept so
	-- old tables in history and Review still show and verify.
	highroll = {
		name = "High Roll", retired = true,
		paramLabel = "Max roll",
		minPlayers = 2, maxPlayers = 12,
		defaultParam = function() return 100 end,
		describe = function(g)
			return ("High Roll 1-%d - highest roll collects %s from each player"):format(g.param, Money(g.wager))
		end,
		resolve = function(g, seed, res)
			local rolls, hi = {}, nil
			for _, n in ipairs(g.players) do
				local r = G.Rand(seed, "r:" .. n, g.param)
				rolls[n] = r
				res.rolls[#res.rolls + 1] = { p = n, r = r, max = g.param }
				res.log[#res.log + 1] = ("%s rolls %d (1-%d)"):format(Short(n), r, g.param)
				hi = (not hi or r > hi) and r or hi
			end
			local highs = {}
			for _, n in ipairs(g.players) do if rolls[n] == hi then highs[#highs + 1] = n end end
			local winner = breakTie(seed, "th", highs, g.param, true, res.log, res.rolls)
			res.winner = winner
			for _, n in ipairs(g.players) do debt(res, n, winner, g.wager) end
			res.summary = ("%s wins %s from each player (%s total)"):format(Short(winner), Money(g.wager), Money(g.wager * (#g.players - 1)))
			return res
		end,
	},
}

-- Battle Slots: everyone antes; three spins each; the best spin takes the pot.
-- Every spin is fixed by the shared seed when the table starts; clicking SPIN
-- only reveals your next one. Spins are weighted so good ones come often:
-- about 1 in 7 spins is a triple, about half are a pair.
local SL = {}
G.Slots = SL
SL.SYM = { "7", "BAR", "Bell", "Plum", "Lemon", "Cherry" }       -- 1 = best
SL.PLURAL = { "7s", "BARs", "Bells", "Plums", "Lemons", "Cherries" }
local TRIPLE_W = { 8, 13, 17, 20, 21, 21 }   -- which triple (7s are the rarest)
local PAIR_W = { 10, 14, 18, 19, 19, 20 }    -- which pair
local P_TRIPLE, P_PAIR = 140, 540            -- out of 1000 (the rest: mixed)

local function pick(seed, key, weights)
	local total = 0
	for _, w in ipairs(weights) do total = total + w end
	local r = G.Rand(seed, key, total)
	for i, w in ipairs(weights) do
		if r <= w then return i end
		r = r - w
	end
	return #weights
end

-- one spin: three symbol numbers (reel 1-3, the payline)
function SL.Spin(seed, key)
	local cat = G.Rand(seed, key .. ":c", 1000)
	if cat <= P_TRIPLE then
		local s = pick(seed, key .. ":t", TRIPLE_W)
		return { s, s, s }
	elseif cat <= P_TRIPLE + P_PAIR then
		local s = pick(seed, key .. ":p", PAIR_W)
		local odd = G.Rand(seed, key .. ":o", 5)
		if odd >= s then odd = odd + 1 end
		-- the odd one out lands on the last reel half the time (the near miss)
		local at = ({ 3, 3, 3, 1, 2, 2 })[G.Rand(seed, key .. ":w", 6)]
		local r = { s, s, s }
		r[at] = odd
		return r
	end
	local a = G.Rand(seed, key .. ":a", 6)
	local b = G.Rand(seed, key .. ":b", 5); if b >= a then b = b + 1 end
	local lo, hi = math.min(a, b), math.max(a, b)
	local c = G.Rand(seed, key .. ":x", 4)
	if c >= lo then c = c + 1 end
	if c >= hi then c = c + 1 end
	return { a, b, c }
end

-- score (higher is better) and name of a spin
function SL.Eval(r)
	local a, b, c = r[1], r[2], r[3]
	if a == b and b == c then
		return 3000 - a * 100, a == 1 and "JACKPOT 7-7-7" or ("Triple " .. SL.PLURAL[a]), "triple"
	end
	local pair, odd
	if a == b then pair, odd = a, c elseif a == c then pair, odd = a, b elseif b == c then pair, odd = b, a end
	if pair then return 2000 - pair * 100 + (7 - odd), "Pair of " .. SL.PLURAL[pair], "pair" end
	local t = { a, b, c }
	table.sort(t)
	return 1000 + (7 - t[1]) * 49 + (7 - t[2]) * 7 + (7 - t[3]), SL.SYM[t[1]] .. " high", "mixed"
end

function SL.Key(p, k) return "slot:" .. p .. ":" .. k end

-- how long a spin takes on its player's machine, pull to the last reel locked
-- (SlotsUI: STOPS[3] or TEASE_STOP when the first two match, plus SETTLE).
-- Everyone else learns the result only after this, so nobody sees it early.
function SL.LandTime(r)
	return ((r and r[1] == r[2]) and 3.1 or 2.05) + 0.18
end

-- everyone's three spins, then the comparison
local function cmpList(x, y) -- sorted scores, best first
	for i = 1, 3 do if x[i] ~= y[i] then return x[i] > y[i] and 1 or -1 end end
	return 0
end

function SL.Play(g, seed)
	local out = { spins = {}, bonus = {} }
	local lists = {}
	for _, p in ipairs(g.players) do
		local sp, sc = {}, {}
		for k = 1, 3 do
			sp[k] = SL.Spin(seed, SL.Key(p, k))
			sc[k] = (SL.Eval(sp[k]))
		end
		out.spins[p] = sp
		table.sort(sc, function(x, y) return x > y end)
		lists[p] = sc
	end
	-- the best list wins; equal lists go to sudden-death spins
	local best = {}
	for _, p in ipairs(g.players) do
		if #best == 0 then best = { p } else
			local d = cmpList(lists[p], lists[best[1]])
			if d > 0 then best = { p } elseif d == 0 then best[#best + 1] = p end
		end
	end
	local round = 0
	while #best > 1 and round < 30 do
		round = round + 1
		local top, nxt = nil, {}
		for _, p in ipairs(best) do
			local r = SL.Spin(seed, SL.Key(p, "tb" .. round))
			local s = (SL.Eval(r))
			out.bonus[#out.bonus + 1] = { p = p, r = r, round = round }
			if not top or s > top then top, nxt = s, { p } elseif s == top then nxt[#nxt + 1] = p end
		end
		best = nxt
	end
	out.winners = best
	return out
end

G.types.slots = {
	name = "Battle Slots", ui = "slots",
	paramLabel = "No setting", noParam = true,
	minPlayers = 2, maxPlayers = 8, minProto = 14,
	defaultParam = function() return 0 end,
	describe = function(g)
		return ("Battle Slots - %s ante; three spins each, the best spin takes the pot"):format(Money(g.wager))
	end,
	resolve = function(g, seed, res)
		local sl = SL.Play(g, seed)
		res.slots = sl
		for _, p in ipairs(g.players) do
			local parts = {}
			for k = 1, 3 do
				local _, name = SL.Eval(sl.spins[p][k])
				parts[k] = name
			end
			res.log[#res.log + 1] = ("%s: %s"):format(Short(p), table.concat(parts, ", "))
		end
		for _, b in ipairs(sl.bonus) do
			local _, name = SL.Eval(b.r)
			res.log[#res.log + 1] = ("  Spin-off %d: %s %s"):format(b.round, Short(b.p), name)
		end
		local W = sl.winners
		-- everyone else pays the ante to the winner (shared if a spin-off never settles it)
		for _, p in ipairs(g.players) do
			if not ns.IndexOf(W, p) then
				local share = floor(g.wager / #W)
				local rem = g.wager - share * #W
				for i, w in ipairs(W) do debt(res, p, w, share + (i == 1 and rem or 0)) end
			end
		end
		res.winner = W[1]
		local bestScore, bestName = -1, ""
		for k = 1, 3 do
			local sc, name = SL.Eval(sl.spins[W[1]][k])
			if sc > bestScore then bestScore, bestName = sc, name end
		end
		local pot = g.wager * #g.players
		if #W == 1 then
			res.summary = ("%s wins with %s%s - takes the pot (%s)"):format(Short(W[1]), bestName, #sl.bonus > 0 and " (after a spin-off)" or "", Money(pot))
		else
			res.summary = ("%s split the pot"):format(ns.ShortList(W))
		end
		return res
	end,
}

-- Card tables (engine in Cards.lua / CardHost.lua). wager = ante (copper).
-- g.hands = how many hands before the table closes (0 = until the house ends it).
local function handsText(g)
	local h = g.hands or 1
	if h == 1 then return "" end
	return h == 0 and "; deals until the house ends it" or ("; %d hands"):format(h)
end
G.types.guts = {
	name = "Guts", kind = "cards", moneyParam = true,
	paramLabel = "Stay-in bet",
	minPlayers = 2, maxPlayers = 8,
	defaultParam = function(wager) return wager end,
	describe = function(g)
		return ("Guts - 3 cards, %s ante; staying in costs %s more, best hand that stays takes the pot%s"):format(Money(g.wager), Money(g.param), handsText(g))
	end,
}
G.types.acey = {
	name = "Acey-Deucey", kind = "cards", oneGame = true, minProto = 13, -- protocol 13: the knockout rules (no call = out)
	paramLabel = "No setting", noParam = true,
	minPlayers = 2, maxPlayers = 8,
	defaultParam = function() return 0 end,
	describe = function(g)
		return ("Acey-Deucey - %s ante; call your third card in or out, wrong calls are knocked out, last one standing takes the pot"):format(Money(g.wager))
	end,
}

G.types.blitz = {
	name = "31 Blitz", kind = "cards", ui = "blitz", oneGame = true, minProto = 16,
	paramLabel = "Lives", paramMin = 1, paramMax = 3,
	minPlayers = 2, maxPlayers = 8,
	defaultParam = function() return 3 end,
	describe = function(g)
		local n = tonumber(g.param) or 3
		return ("31 Blitz - %s ante, %d %s each; get closest to 31 in one suit, last one standing takes the pot"):format(Money(g.wager), n, n == 1 and "life" or "lives")
	end,
}

-- Texas Hold'em (engine in Holdem.lua / HoldemHost.lua). wager = buy-in; the big
-- blind is always buy-in / 50 (everyone starts with 50 BB). param = seconds per decision.
-- g.hands = hands to deal (at least 1). Needs protocol 9.
G.types.holdem = {
	name = "Texas Hold'em", kind = "cards", ui = "holdem",
	paramLabel = "Turn time (s)", wagerLabel = "Buy-in", paramMin = 5, paramMax = 120,
	minPlayers = 2, maxPlayers = 6, minProto = 9, minHands = 1,
	defaultParam = function() return 15 end,
	-- returns an error message, or nil when the buy-in works
	validate = function(wager)
		if wager % 100 ~= 0 then return "The Hold'em buy-in must be a whole number of silver (blinds are buy-in / 50 and / 100), e.g. 50g or 2g 50s." end
		if wager < 100 then return "The Hold'em buy-in must be at least 1s." end
	end,
	describe = function(g)
		local bb = math.floor((g.wager or 0) / 50)
		local h = g.hands or 1
		return ("Texas Hold'em - %s buy-in, blinds %s/%s (50 big blinds each); %s; %ds to act; no-limit"):format(Money(g.wager),
			Money(math.floor(bb / 2)), Money(bb), h <= 1 and "one hand" or (h .. " hands"), g.param or 15)
	end,
}

-- Thugget Dice: 5 dice, up to 3 rolls, hold any dice between rolls.
-- Uses the card-table engine (private dice, numbered messages, audit at close).
-- wager = ante; best hand takes the pot. param = seconds each player gets.
G.types.thugget = {
	oneGame = true, -- one game per table (no hands setting)
	name = "Thugget Dice", kind = "cards", ui = "hand",
	paramLabel = "Turn time (s)",
	minPlayers = 2, maxPlayers = 8,
	defaultParam = function() return 60 end,
	describe = function(g)
		return ("Thugget Dice - %s ante; 5 dice, 3 rolls, hold what you like; best hand takes the pot"):format(Money(g.wager))
	end,
}

---------------------------------------------------------------------------
-- Thugget Dice hands. Ranked by how hard each is to complete in 3 rolls with
-- the best holding strategy (exact odds):
--   Five of a Kind 4.6%  >  Straight 26.1%  >  Four of a Kind 29.1%  >
--   Full House 36.3%  >  Small Straight 61.5%  >  Three of a Kind 74.3%  >
--   Pair 99.9%  >  nothing (scores 0)
-- Ties inside a category go to the higher dice involved, then the other dice.
---------------------------------------------------------------------------
local TH = {}
G.Thugget = TH
TH.CATEGORIES = { "Pair", "Three of a Kind", "Small Straight", "Full House", "Four of a Kind", "Straight", "Five of a Kind" }
local WORD = { "1s", "2s", "3s", "4s", "5s", "6s" }

-- One die: player p, roll k (1-3), slot i (1-5). Fixed by the sealed seed.
function TH.Die(seed, p, k, i)
	return G.Rand(seed, "y:" .. p .. ":" .. k .. ":" .. i, 6)
end

-- Rebuild a player's dice after each roll from their hold masks ("01100" = keep 2 and 3)
function TH.Replay(seed, p, masks)
	local dice, out = { 0, 0, 0, 0, 0 }, {}
	for k, mask in ipairs(masks) do
		for i = 1, 5 do
			if k == 1 or mask:sub(i, i) ~= "1" then dice[i] = TH.Die(seed, p, k, i) end
		end
		out[k] = { dice[1], dice[2], dice[3], dice[4], dice[5] }
	end
	return out
end

local function value(cat, tb)
	local v = cat * 1000000
	local m = 100000
	for _, x in ipairs(tb) do v = v + x * m; m = m / 10 end
	return v
end

-- Returns value (higher wins; 0 = nothing), name, category index (0-7)
function TH.Eval(dice)
	local cnt = { 0, 0, 0, 0, 0, 0 }
	for _, d in ipairs(dice) do cnt[d] = cnt[d] + 1 end
	local desc = { dice[1], dice[2], dice[3], dice[4], dice[5] }
	table.sort(desc, function(a, b) return a > b end)
	local function rest(skipFace, skipN)
		local t, skipped = {}, 0
		for _, d in ipairs(desc) do
			if d == skipFace and skipped < skipN then skipped = skipped + 1 else t[#t + 1] = d end
		end
		return t
	end
	local five, four, three, pairs = nil, nil, nil, {}
	for f = 6, 1, -1 do
		if cnt[f] == 5 then five = f
		elseif cnt[f] == 4 then four = f
		elseif cnt[f] == 3 then three = f
		elseif cnt[f] == 2 then pairs[#pairs + 1] = f end
	end
	local function run(lo, n) for f = lo, lo + n - 1 do if cnt[f] == 0 then return false end end return true end
	if five then return value(7, { five }), "Five of a Kind (" .. WORD[five] .. ")", 7 end
	if run(2, 5) then return value(6, { 6 }), "Straight (2-6)", 6 end
	if run(1, 5) then return value(6, { 5 }), "Straight (1-5)", 6 end
	if four then return value(5, { four, rest(four, 4)[1] }), "Four " .. WORD[four], 5 end
	if three and pairs[1] then return value(4, { three, pairs[1] }), ("Full House (%s over %s)"):format(WORD[three], WORD[pairs[1]]), 4 end
	for lo = 3, 1, -1 do
		if run(lo, 4) then
			-- the die not used in the run
			local used, extra = {}, 0
			for _, d in ipairs(desc) do
				if d >= lo and d <= lo + 3 and not used[d] then used[d] = true else extra = d end
			end
			return value(3, { lo + 3, extra }), ("Small Straight (%d-%d)"):format(lo, lo + 3), 3
		end
	end
	if three then
		local r = rest(three, 3)
		return value(2, { three, r[1], r[2] }), "Three " .. WORD[three], 2
	end
	if pairs[1] then
		local r = rest(pairs[1], 2)
		return value(1, { pairs[1], r[1], r[2], r[3] }), "Pair of " .. WORD[pairs[1]], 1
	end
	return 0, "Nothing (0)", 0
end

-- Showdown: best hand takes the pot (ties split, odd copper to the first seat).
-- If nobody made anything, everyone gets their ante back.
function TH.Resolve(seats, hands, pot, contrib)
	local res = { deltas = {}, values = {}, names = {} }
	local best = 0
	for _, p in ipairs(seats) do
		local v, name = TH.Eval(hands[p])
		res.values[p], res.names[p] = v, name
		if v > best then best = v end
	end
	if best == 0 then
		for p, c in pairs(contrib) do res.deltas[p] = c end
		res.summary = "Nobody made a hand - antes returned"
		return res
	end
	local winners = {}
	for _, p in ipairs(seats) do if res.values[p] == best then winners[#winners + 1] = p end end
	local share = math.floor(pot / #winners)
	local rem = pot - share * #winners
	for i, w in ipairs(winners) do res.deltas[w] = share + (i == 1 and rem or 0) end
	res.winners = winners
	local wn = {}
	for i, w in ipairs(winners) do wn[i] = Short(w) end
	res.summary = ("%s %s %s with %s"):format(table.concat(wn, " & "), #winners > 1 and "split" or "wins",
		ns.Money(pot), res.names[winners[1]])
	return res
end

---------------------------------------------------------------------------
-- Worst case (copper) a player can lose, shown before joining and used for the
-- house's credit limit. Card tables dealing several hands: per hand.
-- Rules text shown in each table window.
---------------------------------------------------------------------------
local WORST = {
	deathroll = function(g) return g.wager end,
	highroll = function(g) return g.wager end,
	highlow = function(g) return math.max(0, (g.param or 2) - 1) * G.HighLowUnit(g.wager) end,
	coinflip = function(g) return g.wager end,
	slots = function(g) return g.wager end,
	thugget = function(g) return g.wager end,
	guts = function(g) return g.wager + (g.param or 0) end,
	acey = function(g) return g.wager end,
	blitz = function(g) return g.wager end,
	holdem = function(g) return g.wager end, -- you can never lose more than your buy-in
}
G.types.guts.perHand = true -- when dealing more than one hand
function G.PerHand(g) return G.types[g.type].perHand and (g.hands or 1) ~= 1 end

function G.WorstCase(g)
	local f = WORST[g.type]
	return f and f(g) or g.wager or 0
end

-- "You could lose up to 499g." / "... per hand"
function G.WorstText(g)
	local w = G.WorstCase(g)
	if G.PerHand(g) then
		return ("You could lose up to %s each hand (%s)."):format(Money(w),
			(g.hands or 1) == 0 and "the table keeps going until the house closes it" or (g.hands .. " hands"))
	end
	return ("You could lose up to %s."):format(Money(w))
end

local RULES = {
	deathroll = "Players take turns rolling in seat order. The first roll is 1 to the start number, and every roll after is 1 to the previous roll. Whoever rolls a 1 loses and pays the wager to the player who rolled just before them.\n\nClick ROLL on your turn. A turn rolls itself after 20 seconds.",
	highroll = "Everyone rolls 1 to the max roll. The highest roll wins and collects the wager from every other player. Tied players roll again.\n\nClick ROLL - your click reveals your sealed roll. It rolls itself after 40 seconds.",
	highlow = "Everyone rolls from 1 up to the bet, counted in the biggest coin that makes the roll at least 100: a 250g bet rolls 1-250 (gold), a 10g bet rolls 1-1000 (silver), a 75s bet rolls 1-7500 (copper). The lowest roller pays the highest roller the difference: with a 10g bet, rolls of 812 and 289 mean 523s, paid as 5g 23s. Tied players roll again.\n\nClick ROLL - your click reveals your sealed roll. It rolls itself after 40 seconds.",
	slots = "Everyone antes, then everyone plays at once: three spins each on your own machine. Grab the lever on the right and drag it down to spin (it pulls itself if you wait too long). Your best spin counts; the best spin at the table takes the pot.\n\nBest first: JACKPOT 7-7-7 > Triple BARs > Triple Bells > Triple Plums > Triple Lemons > Triple Cherries > a pair (7s best, Cherries lowest; the odd symbol breaks a tie) > mixed (the best symbols win).\n\nEqual best spins are settled by your next best, then your third. Still level? A sudden-death spin-off between the tied players.\n\nEvery spin is fixed by the sealed rolls before anyone clicks; the machine is weighted so triples and pairs come up often.",
	coinflip = "Two players. When the table starts, one of you is picked at random to call it: click HEADS or TAILS (it picks for you after 20 seconds). Then the coin is flipped. Call it right and you win the wager from the other player; call it wrong and you pay it.\n\nYour call is sealed into your roll before the coin is tossed, so nobody - you included - can know how it lands before you choose.",
	thugget = "Everyone antes and rolls at the same time. You get 5 dice and up to 3 rolls: click dice to hold them, then roll again or stand. Your dice stay hidden until the showdown. Best hand takes the pot (ties split; if nobody makes a hand, antes come back).\n\nHands, best first: Five of a Kind > Straight (1-5 or 2-6) > Four of a Kind > Full House > Small Straight (4 in a row) > Three of a Kind > Pair > nothing (0). Ties go to the higher dice, then the other dice.",
	guts = "Everyone antes and gets 3 cards, then secretly chooses IN or OUT. Staying IN costs the stay-in bet on top of your ante. Out: you lose only your ante.\n\nIf only one player stays in, they take the pot. If several stay in, the best hand takes it all (exact ties split). If everyone drops, antes come back.\n\nHands, best first: Straight Flush > Three of a Kind > Straight > Flush > Pair > High Card. Equal hands compare the next-highest card, then the last one, so A-K-5 beats A-9-3. Only the same three ranks is a tie.",
	holdem = "No-limit Texas Hold'em. Everyone buys in for the same amount and starts with 50 big blinds. The table plays the number of hands the house set (or until one player has all the chips); then each player's stack minus the buy-in goes on the ledger.\n\nTwo hole cards each, then the flop (3), turn and river. Make the best five-card hand from your two cards and the board. Blinds: small and big blind left of the button (heads-up, the button posts the small blind and acts first before the flop). Minimum bet is a big blind; a raise must be at least the last bet or raise. An all-in for less doesn't reopen the raising. Side pots are split by who put in how much.\n\nYou have the house's turn time to act (15 seconds unless the house set another); when time runs out you check if you can, otherwise you fold. Two timeouts in a row and you're sitting out (you still post blinds) until you click I'm back.\n\nHands, best first: Straight Flush > Four of a Kind > Full House > Flush > Straight > Three of a Kind > Two Pair > Pair > High Card. A-2-3-4-5 is the lowest straight. Ties split; an odd copper goes to the first winner left of the button.",
	blitz = "Everyone antes once and starts with the table's lives (the house sets 1 to 3). Last player with a life left takes the pot.\n\nEach round you get three cards. Your score is your best total in ONE suit: Ace 11, King/Queen/Jack/10 count 10, others their number - up to 31. Three of a kind counts 30.5.\n\nOn your turn: click the deck (only you see the card) or the face-up pile to draw, then click one of your four cards to throw it away. You can't throw back the card you just took from the pile. Or click KNOCK instead of drawing when you think you're ahead: everyone else gets one more turn, then all hands are shown.\n\nHit 31 and it's a BLITZ: the round ends at once and everyone else loses a life.\n\nOtherwise the lowest hand loses a life (ties at the bottom all lose one). If the knocker is lowest, they lose two. If the deck runs out, hands are shown with no knocker.\n\nYou have 20 seconds for your first turn and 15 after. Run out of time and you draw from the deck and throw that card away; miss two turns in a row and you're out of the game.",
	acey = "Everyone antes once, then it's a knockout. Each round, every player still in gets two cards of their own, face up, and calls whether their third card will land IN between them or OUT. A card matching one of your two (the post) counts as OUT. Aces are high.\n\nDealt a pair? Call HIGHER or LOWER instead; a third card of the same rank is wrong either way. Two cards next to each other (a 7 and an 8): nothing is in between, so OUT always wins.\n\nAll the third cards turn over at once. Call it wrong and you're out. If nobody who called got it right, they all go again. The last player standing takes the pot.\n\nYou have 20 seconds to call in the first round and 10 seconds after that. No call in time and you're out. (If nobody calls at all, the table closes and the pot is split among the players still in.)",
}
function G.Rules(gtype) return RULES[gtype] or "" end

-- Players who never revealed their secret forfeit: each pays the wager, split
-- evenly among everyone who did reveal. The game itself is void.
function G.Resolve(g, seed, forfeits, secrets)
	local res = { log = {}, debts = {}, rolls = {} }
	if forfeits and #forfeits > 0 then
		local fset = {}
		for _, n in ipairs(forfeits) do fset[n] = true end
		local active = {}
		for _, p in ipairs(g.players) do if not fset[p] then active[#active + 1] = p end end
		if #active == 0 then
			res.summary = "Nobody revealed - game void"
			return res
		end
		local W = g.wager
		for _, f in ipairs(forfeits) do
			local share = floor(W / #active)
			local rem = W - share * #active
			for i, a in ipairs(active) do debt(res, f, a, share + (i == 1 and rem or 0)) end
			res.log[#res.log + 1] = ("%s did not reveal and forfeits %s"):format(Short(f), Money(g.wager))
		end
		res.summary = "Game void - forfeit penalties applied"
		return res
	end
	return G.types[g.type].resolve(g, seed, res, secrets)
end

-- Short fingerprint of a result so clients can confirm they agree.
function G.ResultHash(res)
	local t = {}
	for _, d in ipairs(res.debts) do t[#t + 1] = d.from .. ">" .. d.to .. ":" .. d.c end
	table.sort(t)
	return ns.SHA256(table.concat(t, ";")):sub(1, 16)
end
