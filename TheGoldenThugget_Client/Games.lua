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

-- High-Low counts in the smallest coin the bet uses: 5g -> gold, 1g 25s -> silver
function G.HighLowUnit(wager)
	wager = wager or 0
	if wager % 100 ~= 0 then return 1 end
	if wager % 10000 ~= 0 then return 100 end
	return 10000
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

G.order = { "deathroll", "highlow", "highroll", "thugget", "guts", "acey", "holdem" }

G.types = {
	deathroll = {
		name = "Death Roll",
		paramLabel = "Roll from",
		minPlayers = 2, maxPlayers = 2,
		defaultParam = function(wager) return math.max(100, math.floor(wager / G.HighLowUnit(wager))) end, -- 250g starts at 250
		describe = function(g)
			return ("Death Roll from %d - whoever rolls 1 pays %s"):format(g.param, Money(g.wager))
		end,
		resolve = function(g, seed, res)
			local p = g.players
			local cur, turn = g.param, 1
			for k = 1, 100000 do
				local r = G.Rand(seed, "d" .. k, cur)
				res.rolls[#res.rolls + 1] = { p = p[turn], r = r, max = cur }
				res.log[#res.log + 1] = ("%s rolls %d (1-%d)"):format(Short(p[turn]), r, cur)
				if r == 1 then
					local loser, winner = p[turn], p[3 - turn]
					res.winner, res.loser = winner, loser
					debt(res, loser, winner, g.wager)
					res.summary = ("%s rolled 1 - pays %s %s"):format(Short(loser), Short(winner), Money(g.wager))
					return res
				end
				cur, turn = r, 3 - turn
			end
			return res
		end,
	},

	-- The bet sets the roll: 75s rolls 1-75, 1g 25s rolls 1-125 (counted in its
	-- smallest coin), and the difference between the rolls is what's owed.
	highlow = {
		name = "High-Low",
		paramLabel = "Max roll", fixedParam = true,
		minPlayers = 2, maxPlayers = 12,
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

	highroll = {
		name = "High Roll",
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
	name = "Acey-Deucey", kind = "cards", moneyParam = true,
	paramLabel = "Max bet",
	minPlayers = 2, maxPlayers = 8,
	defaultParam = function(wager) return wager * 5 end,
	describe = function(g)
		return ("Acey-Deucey - %s ante; one turn each, bet up to %s (or the pot) that the next card lands in between%s"):format(Money(g.wager), Money(g.param), handsText(g))
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
	thugget = function(g) return g.wager end,
	guts = function(g) return g.wager + (g.param or 0) end,
	acey = function(g) return g.wager + 2 * (g.param or 0) end,
	holdem = function(g) return g.wager end, -- you can never lose more than your buy-in
}
G.types.guts.perHand, G.types.acey.perHand = true, true -- when dealing more than one hand
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
	deathroll = "Two players take turns rolling. The first roll is 1 to the start number, and every roll after is 1 to the previous roll. Whoever rolls a 1 loses and pays the wager.\n\nClick ROLL on your turn. A turn rolls itself after 20 seconds.",
	highroll = "Everyone rolls 1 to the max roll. The highest roll wins and collects the wager from every other player. Tied players roll again.\n\nClick ROLL - your click reveals your sealed roll. It rolls itself after 40 seconds.",
	highlow = "Everyone rolls from 1 up to the bet, counted in its smallest coin: a 75s bet rolls 1-75, a 1g 25s bet rolls 1-125 (silver), a 5g bet rolls 1-5 (gold). The lowest roller pays the highest roller the difference: with a 75s bet, rolls of 55 and 25 mean 30s. Tied players roll again.\n\nClick ROLL - your click reveals your sealed roll. It rolls itself after 40 seconds.",
	thugget = "Everyone antes and rolls at the same time. You get 5 dice and up to 3 rolls: click dice to hold them, then roll again or stand. Your dice stay hidden until the showdown. Best hand takes the pot (ties split; if nobody makes a hand, antes come back).\n\nHands, best first: Five of a Kind > Straight (1-5 or 2-6) > Four of a Kind > Full House > Small Straight (4 in a row) > Three of a Kind > Pair > nothing (0). Ties go to the higher dice, then the other dice.",
	guts = "Everyone antes and gets 3 cards, then secretly chooses IN or OUT. Staying IN costs the stay-in bet on top of your ante. Out: you lose only your ante.\n\nIf only one player stays in, they take the pot. If several stay in, the best hand takes it all (exact ties split). If everyone drops, antes come back.\n\nHands, best first: Straight Flush > Three of a Kind > Straight > Flush > Pair > High Card. Equal hands compare the next-highest card, then the last one, so A-K-5 beats A-9-3. Only the same three ranks is a tie.",
	holdem = "No-limit Texas Hold'em. Everyone buys in for the same amount and starts with 50 big blinds. The table plays the number of hands the house set (or until one player has all the chips); then each player's stack minus the buy-in goes on the ledger.\n\nTwo hole cards each, then the flop (3), turn and river. Make the best five-card hand from your two cards and the board. Blinds: small and big blind left of the button (heads-up, the button posts the small blind and acts first before the flop). Minimum bet is a big blind; a raise must be at least the last bet or raise. An all-in for less doesn't reopen the raising. Side pots are split by who put in how much.\n\nYou have the house's turn time to act (15 seconds unless the house set another); when time runs out you check if you can, otherwise you fold. Two timeouts in a row and you're sitting out (you still post blinds) until you click I'm back.\n\nHands, best first: Straight Flush > Four of a Kind > Full House > Flush > Straight > Three of a Kind > Two Pair > Pair > High Card. A-2-3-4-5 is the lowest straight. Ties split; an odd copper goes to the first winner left of the button.",
	acey = "Everyone antes into the pot, then each player gets one turn. On your turn you see two cards and bet (up to the max bet, never more than the pot) that the next card lands strictly between them.\n\nIn between: win your bet from the pot. Outside: pay your bet into the pot. Matching either card (the post): pay double. Aces are high. A pair or two cards next to each other: no bet that turn.\n\nWhen everyone has had a turn (or the pot is emptied), whatever is left in the pot is split evenly among the players.",
}
function G.Rules(gtype) return RULES[gtype] or "" end

-- Players who never revealed their secret forfeit: each pays the wager, split
-- evenly among everyone who did reveal. The game itself is void.
function G.Resolve(g, seed, forfeits)
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
	return G.types[g.type].resolve(g, seed, res)
end

-- Short fingerprint of a result so clients can confirm they agree.
function G.ResultHash(res)
	local t = {}
	for _, d in ipairs(res.debts) do t[#t + 1] = d.from .. ">" .. d.to .. ":" .. d.c end
	table.sort(t)
	return ns.SHA256(table.concat(t, ";")):sub(1, 16)
end
