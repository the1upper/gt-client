-- The Golden Thugget: Cards — deck, private hand sealing, hand ranking and the
-- rules of each card game. Host and clients run exactly the same functions, so
-- every client can check the host's results.
--
-- Fairness model: the deck is shuffled from the same commit-reveal seed as the
-- dice games. Only the house knows the seed while a table runs (deck lives in
-- memory only). Private cards are broadcast encrypted with a key derived from
-- that player's own secret, so only they can read them. When the table closes,
-- all secrets are published and every client re-derives the decks and checks
-- every card it was shown.
local _, ns = ...
if ns.skip then return end
local K = {}
ns.Cards = K

local floor = math.floor
K.RANKS = "23456789TJQKA"
K.SUITS = "shdc"
K.BACK = 52

function K.Code(i) -- 1..52 -> "As"
	local s = floor((i - 1) / 13) + 1
	local r = (i - 1) % 13 + 1
	return K.RANKS:sub(r, r) .. K.SUITS:sub(s, s)
end

function K.Value(code) return K.RANKS:find(code:sub(1, 1), 1, true) + 1 end -- 2..14

function K.Valid(code)
	return type(code) == "string" and #code == 2 and K.RANKS:find(code:sub(1, 1), 1, true) and K.SUITS:find(code:sub(2, 2), 1, true) and true
end

-- Atlas: 1024x1024, 8 columns x 7 rows, cell 128x146, card 104x146 in the cell
function K.TexCoord(code)
	local index = K.BACK
	if code then
		index = (K.SUITS:find(code:sub(2, 2), 1, true) - 1) * 13 + (K.RANKS:find(code:sub(1, 1), 1, true) - 1)
	end
	local col, row = index % 8, floor(index / 8)
	local x, y = col * 128 + 12, row * 146
	return x / 1024, (x + 104) / 1024, y / 1024, (y + 146) / 1024
end

local SUIT_NAME = { s = "Spades", h = "Hearts", d = "Diamonds", c = "Clubs" }
local SUIT_COLOR = { s = "ffe0e0e0", h = "ffff5050", d = "ffff5050", c = "ffe0e0e0" }
-- Chat/log text, e.g. "|cffff5050Qh|r"
function K.Text(code)
	if not code or code == "" then return "??" end
	local r = code:sub(1, 1)
	if r == "T" then r = "10" end
	return "|c" .. SUIT_COLOR[code:sub(2, 2)] .. r .. code:sub(2, 2) .. "|r"
end
function K.TextList(codes)
	local t = {}
	for i, c in ipairs(codes) do t[i] = K.Text(c) end
	return table.concat(t, " ")
end
K.SUIT_NAME = SUIT_NAME

---------------------------------------------------------------------------
-- Decks: deck n of a table is a Fisher-Yates shuffle driven by the seed
---------------------------------------------------------------------------
function K.Deck(seed, n)
	local deck = {}
	for i = 1, 52 do deck[i] = K.Code(i) end
	for i = 52, 2, -1 do
		local j = ns.Games.Rand(seed, "deck" .. n .. ":" .. i, i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

-- A dealt card on the wire: "deck.pos.code"
function K.Pack(d, p, code) return d .. "." .. p .. "." .. code end
function K.Unpack(s)
	local d, p, c = (s or ""):match("^(%d+)%.(%d+)%.(%w%w)$")
	if d and K.Valid(c) then return tonumber(d), tonumber(p), c end
end

-- Check every card a client saw against the real decks.
function K.VerifySeen(seed, seen)
	local decks = {}
	for _, s in ipairs(seen) do
		local deck = decks[s.d]
		if not deck then deck = K.Deck(seed, s.d); decks[s.d] = deck end
		if deck[s.p] ~= s.c then return false, s end
	end
	return true
end

---------------------------------------------------------------------------
-- Sealing private cards (XOR with a SHA-256 keystream from the player's secret)
---------------------------------------------------------------------------
local function keystream(key, n)
	local out, block = {}, 0
	while #out < n do
		local h = ns.SHA256(key .. ":" .. block)
		for i = 1, 63, 2 do out[#out + 1] = tonumber(h:sub(i, i + 1), 16) end
		block = block + 1
	end
	return out
end

function K.HandKey(tableId, round, secret)
	return ns.SHA256("hand|" .. tableId .. "|" .. round .. "|" .. secret)
end

function K.Seal(key, text)
	local ks = keystream(key, #text)
	local t = {}
	for i = 1, #text do t[i] = ("%02x"):format(bit.bxor(text:byte(i), ks[i])) end
	return table.concat(t)
end

function K.Open(key, hex)
	if not hex or #hex % 2 ~= 0 then return nil end
	local n = #hex / 2
	local ks = keystream(key, n)
	local t = {}
	for i = 1, n do
		local b = tonumber(hex:sub(2 * i - 1, 2 * i), 16)
		if not b then return nil end
		t[i] = string.char(bit.bxor(b, ks[i]))
	end
	return table.concat(t)
end

---------------------------------------------------------------------------
-- 3-card poker ranking (Guts)
-- Straight flush > Three of a kind > Straight > Flush > Pair > High card
---------------------------------------------------------------------------
local RANK_WORD = { [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10", [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
local PLURAL = { [6] = "Sixes" }

function K.Eval3(cards)
	local v = { K.Value(cards[1]), K.Value(cards[2]), K.Value(cards[3]) }
	table.sort(v, function(a, b) return a > b end)
	local s1, s2, s3 = cards[1]:sub(2, 2), cards[2]:sub(2, 2), cards[3]:sub(2, 2)
	local flush = s1 == s2 and s2 == s3
	local straight, high = false, v[1]
	if v[1] - v[2] == 1 and v[2] - v[3] == 1 then straight = true
	elseif v[1] == 14 and v[2] == 3 and v[3] == 2 then straight, high = true, 3 end
	local B = 15
	if straight and flush then return 5 * B ^ 3 + high * B * B, "Straight flush" end
	if v[1] == v[3] then return 4 * B ^ 3 + v[1] * B * B, "Three " .. RANK_WORD[v[1]] .. "s" end
	if straight then return 3 * B ^ 3 + high * B * B, "Straight" end
	if flush then return 2 * B ^ 3 + v[1] * B * B + v[2] * B + v[3], "Flush" end
	local function r(x) local c = K.RANKS:sub(x - 1, x - 1); return c == "T" and "10" or c end
	if v[1] == v[2] then return 1 * B ^ 3 + v[1] * B * B + v[3] * B, "Pair of " .. RANK_WORD[v[1]] .. "s, " .. r(v[3]) .. " kicker" end
	if v[2] == v[3] then return 1 * B ^ 3 + v[2] * B * B + v[1] * B, "Pair of " .. RANK_WORD[v[2]] .. "s, " .. r(v[1]) .. " kicker" end
	return v[1] * B * B + v[2] * B + v[3], ("%s-%s-%s high"):format(r(v[1]), r(v[2]), r(v[3]))
end

---------------------------------------------------------------------------
-- Guts: resolve one hand. Every hand stands alone.
--   seats   : players in seat order
--   ins     : set of players who stayed in
--   hands   : player -> {3 codes} (needed for everyone who stayed in)
--   pot     : copper anted this hand,  stay : copper each "in" adds
--   contrib : player -> copper they anted this hand
--   carry   : if nobody stays in, keep the antes in the pot for a redeal
-- Returns { deltas, pot, contrib, summary, hand = player -> hand name }
-- (deltas on top of the antes)
---------------------------------------------------------------------------
function K.GutsResolve(seats, ins, hands, pot, stay, contrib, carry)
	local res = { deltas = {}, pot = 0, contrib = {}, hand = {} }
	local list = {}
	for _, p in ipairs(seats) do if ins[p] then list[#list + 1] = p end end
	if #list == 0 then
		if carry then
			res.pot, res.contrib, res.redeal = pot, contrib, true
			res.summary = "Everyone folded - the antes stay in and the cards are dealt again"
			return res
		end
		for p, c in pairs(contrib) do res.deltas[p] = c end
		res.summary = "Everyone folded again - antes returned"
		return res
	end
	for _, p in ipairs(list) do res.deltas[p] = -stay end
	pot = pot + stay * #list
	if #list == 1 then
		local w = list[1]
		res.deltas[w] = res.deltas[w] + pot
		res.summary = ("%s was the only one in and takes the %s pot"):format(ns.Short(w), ns.Money(pot))
		res.hand[w] = "in alone"
		return res
	end
	local best, vals, names = nil, {}, {}
	for _, p in ipairs(list) do
		vals[p], names[p] = K.Eval3(hands[p])
		if not best or vals[p] > best then best = vals[p] end
	end
	local winners = {}
	for _, p in ipairs(list) do if vals[p] == best then winners[#winners + 1] = p end end
	local share = floor(pot / #winners)
	local rem = pot - share * #winners
	for i, w in ipairs(winners) do res.deltas[w] = res.deltas[w] + share + (i == 1 and rem or 0) end
	local wn = {}
	for i, w in ipairs(winners) do wn[i] = ns.Short(w) end
	res.summary = ("%s %s the %s pot with %s"):format(table.concat(wn, " & "), #winners > 1 and "split" or "takes",
		ns.Money(pot), names[winners[1]])
	for _, p in ipairs(list) do res.hand[p] = names[p] end
	return res
end

-- Guts table closing: unclaimed pot goes back to whoever put it in.
function K.GutsRefund(contrib)
	local d = {}
	for p, c in pairs(contrib) do d[p] = c end
	return d
end

---------------------------------------------------------------------------
-- Acey-Deucey
---------------------------------------------------------------------------
-- No card can land strictly between a pair or two adjacent ranks (aces high).
-- Acey-Deucey (knockout): each player gets two cards and calls whether their
-- third card lands IN between them or OUT (a card matching one of the two, a
-- "post", counts as outside). On a pair the call is HIGHER or LOWER, and a
-- third card of the same rank is wrong either way.
function K.AceyPair(c1, c2) return K.Value(c1) == K.Value(c2) end

function K.AceyChoices(c1, c2)
	if K.AceyPair(c1, c2) then return "hi", "lo" end
	return "in", "out"
end

function K.AceyValidChoice(c1, c2, choice)
	local a, b = K.AceyChoices(c1, c2)
	return choice == a or choice == b
end

function K.AceyCorrect(c1, c2, c3, choice)
	local a, b, v = K.Value(c1), K.Value(c2), K.Value(c3)
	if a == b then
		if choice == "hi" then return v > a end
		if choice == "lo" then return v < a end
		return false
	end
	local lo, hi = math.min(a, b), math.max(a, b)
	local inside = v > lo and v < hi
	if choice == "in" then return inside end
	if choice == "out" then return not inside end
	return false
end

K.ACEY_WORD = { ["in"] = "IN", out = "OUT", hi = "HIGHER", lo = "LOWER" }

-- Round outcome. picks[p] = choice (nil: no call - timed out or left),
-- cards[p] = { c1, c2, c3 }. Returns survivors (seat order) and how it went:
--   false  : the right calls go on, everyone else is out
--   true   : nobody who called was right - the callers go again (no call is still out)
--   "idle" : nobody called at all - nobody can be knocked out fairly; the table
--            closes and the pot is split among them
function K.AceyRound(alive, cards, picks)
	local right, callers = {}, {}
	for _, p in ipairs(alive) do
		local h = cards[p]
		if h and picks[p] then
			callers[#callers + 1] = p
			if K.AceyCorrect(h[1], h[2], h[3], picks[p]) then right[#right + 1] = p end
		end
	end
	if #callers == 0 then return { unpack(alive) }, "idle" end
	if #right == 0 then return callers, true end
	return right, false
end

---------------------------------------------------------------------------
-- 31 Blitz. Three cards; your score is the best total in one suit (Ace 11,
-- face cards 10, others their number), up to 31. Three of a kind is 30.5.
-- Scores are kept in half points: 62 = 31 (a blitz), 61 = three of a kind.
---------------------------------------------------------------------------
function K.BlitzValue(code)
	local r = code:sub(1, 1)
	if r == "A" then return 11 end
	if r == "K" or r == "Q" or r == "J" or r == "T" then return 10 end
	return tonumber(r)
end

local SUIT_SYM = { s = "Spades", h = "Hearts", d = "Diamonds", c = "Clubs" }
-- score (half points), and a short name like "27 in Spades", "Three 7s (30.5)", "BLITZ 31"
function K.BlitzScore(cards)
	if #cards >= 3 then
		local r = cards[1]:sub(1, 1)
		if cards[2]:sub(1, 1) == r and cards[3]:sub(1, 1) == r and #cards == 3 then
			local word = r == "T" and "10" or r
			return 61, ("Three %ss (30.5)"):format(word)
		end
	end
	local best, bestSuit = 0, "s"
	local sums = {}
	for _, c in ipairs(cards) do
		local s = c:sub(2, 2)
		sums[s] = (sums[s] or 0) + K.BlitzValue(c)
	end
	for s, v in pairs(sums) do if v > best or (v == best and s < bestSuit) then best, bestSuit = v, s end end
	if best == 31 then return 62, "BLITZ 31" end
	return best * 2, ("%d in %s"):format(best, SUIT_SYM[bestSuit])
end

function K.BlitzText(half) -- 61 -> "30.5", 54 -> "27"
	if half % 2 == 1 then return ("%d.5"):format((half - 1) / 2) end
	return tostring(half / 2)
end

-- Who loses lives this round. hands[p] = 3 codes; reason = "blitz" | "knock" | "deck".
-- A blitz: everyone without 31 loses one. Otherwise the lowest score loses one
-- (all tied at the bottom do); the knocker loses two if they're among them.
-- Players in out[] (left, or missed two turns) lose all their lives.
-- Returns losses {p = n}.
function K.BlitzLosses(alive, hands, reason, knocker, out)
	local losses = {}
	local scores = {}
	for _, p in ipairs(alive) do scores[p] = (K.BlitzScore(hands[p])) end
	if reason == "blitz" then
		for _, p in ipairs(alive) do if scores[p] < 62 then losses[p] = 1 end end
	else
		local low
		for _, p in ipairs(alive) do if not low or scores[p] < low then low = scores[p] end end
		for _, p in ipairs(alive) do
			if scores[p] == low then losses[p] = (reason == "knock" and p == knocker) and 2 or 1 end
		end
	end
	for p in pairs(out or {}) do if ns.IndexOf(alive, p) then losses[p] = 99 end end
	return losses
end

-- Apply losses. If nobody would be left standing, the round doesn't count
-- (again = true) - except for anyone who left, who is out regardless.
function K.BlitzApply(alive, lives, losses, out)
	local new, survivors = {}, {}
	for _, p in ipairs(alive) do
		new[p] = math.max(0, (lives[p] or 0) - (losses[p] or 0))
		if new[p] > 0 then survivors[#survivors + 1] = p end
	end
	if #survivors == 0 then
		-- everyone went out together: replay it (the leavers still go)
		for _, p in ipairs(alive) do
			if not (out and out[p]) then new[p] = lives[p]; survivors[#survivors + 1] = p end
		end
		return new, survivors, true
	end
	return new, survivors, false
end

-- Acey table closing early: the pot is split evenly among the players still in.
function K.AceyRefund(pot, seats)
	local d = {}
	if #seats == 0 or pot <= 0 then return d end
	local share = floor(pot / #seats)
	local rem = pot - share * #seats
	for i, p in ipairs(seats) do d[p] = share + (i == 1 and rem or 0) end
	return d
end

---------------------------------------------------------------------------
function K.AddDeltas(into, d)
	for p, c in pairs(d) do into[p] = (into[p] or 0) + c end
	return into
end

function K.DeltaHash(deltas)
	local t = {}
	for p, c in pairs(deltas) do if c ~= 0 then t[#t + 1] = p .. "=" .. c end end
	table.sort(t)
	return ns.SHA256(table.concat(t, ";")):sub(1, 16)
end
