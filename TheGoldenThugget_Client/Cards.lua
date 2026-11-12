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
function K.AceyNoChance(c1, c2)
	return math.abs(K.Value(c1) - K.Value(c2)) <= 1
end

-- Largest bet allowed (copper): at most the max bet and at most the pot.
function K.AceyMaxBet(pot, maxBet)
	return math.max(0, math.min(maxBet, pot))
end

-- Returns outcome, delta for the player (copper).
--   win  : strictly between    -> +bet (from the pot)
--   post : matches either card -> -2x bet (into the pot)
--   lose : outside             -> -bet (into the pot)
function K.AceyResolve(c1, c2, c3, bet)
	if bet <= 0 or not c3 then return "pass", 0 end
	local a, b = K.Value(c1), K.Value(c2)
	local lo, hi = math.min(a, b), math.max(a, b)
	local v = K.Value(c3)
	if v > lo and v < hi then return "win", bet end
	if v == lo or v == hi then return "post", -2 * bet end
	return "lose", -bet
end

-- Acey table closing: unclaimed pot is split evenly among players still seated.
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
