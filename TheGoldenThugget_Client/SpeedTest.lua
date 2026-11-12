-- The Golden Thugget: addon-message speed test.  /gt speedtest First Last
-- Measures how fast this WoW client really lets whispers through, and whether
-- the limit is per prefix (so spreading over several prefixes is faster) or
-- shared by the whole addon. Bypasses the addon's own 1-per-second pacing.
-- Both characters need this version. Takes about a minute and a half.
--
--   A  burst  : 30 whispers at once on 1 prefix
--   B  burst  : 30 whispers at once spread over 4 prefixes
--   C  steady : 3 a second for 15 s on 1 prefix
--   D  steady : 3 a second for 15 s spread over 4 prefixes
--   E  heavy  : full-size (~240 byte) messages, 6 a second for 15 s, 1 prefix
--              (about twice what the addon now sends at most)
-- The other character counts what arrives and reports back.
local _, ns = ...
if ns.skip then return end
local ST = {}
ns.SpeedTest = ST

local PREFIXES = { "GoldThugT1", "GoldThugT2", "GoldThugT3", "GoldThugT4" }
local REST = 15          -- seconds between phases (lets any limit refill)
local BURST = 30
local STEADY_RATE, STEADY_SECS = 3, 15
local isTest = {}
for _, p in ipairs(PREFIXES) do isTest[p] = true end

local function J(...) return table.concat({ ... }, "^") end
local function now() return GetTime() end

-- what a send call returned: ok, or the raw refusal
local OK = {}
if Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success then OK[Enum.SendAddonMessageResult.Success] = true end
local function send(prefix, msg, target)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "WHISPER", target)
	if not ok then return false, "error" end
	if res == nil or res == true or res == 0 or OK[res] then return true end
	return false, tostring(res)
end

---------------------------------------------------------------------------
-- sender
---------------------------------------------------------------------------
local PHASES = {
	{ key = "A", label = "Burst, 1 prefix", burst = true, spread = 1 },
	{ key = "B", label = "Burst, 4 prefixes", burst = true, spread = 4 },
	{ key = "C", label = "Steady 3/s, 1 prefix", spread = 1 },
	{ key = "D", label = "Steady 3/s, 4 prefixes", spread = 4 },
	{ key = "E", label = "Full-size 6/s, 1 prefix", spread = 1, rate = 6, pad = 220 },
}

function ST:Start(target)
	if self.run then return ns.Print("A speed test is already running.") end
	if not target or target == "" then return ns.Print("Usage: /gt speedtest First Last  (the other character must be online with v3.14.2+)") end
	target = ns.Full(target)
	if target == ns.me then return ns.Print("Pick another character, not yourself.") end
	local busy = (ns.Client.game and ns.Client.game.phase == "playing") or (ns.Host and ns.Host.Active and ns.Host:Active())
	if busy then return ns.Print("Finish the table first - the test floods whispers on purpose.") end
	local run = tostring(math.random(100000, 999999))
	self.run = { id = run, target = target, sent = {}, pong = false }
	ns.Print(("Speed test with %s: checking they're there..."):format(target))
	send(PREFIXES[1], J("SP", run), target)
	C_Timer.After(4, function()
		local r = self.run
		if not r or r.id ~= run then return end
		if not r.pong then
			self.run = nil
			return ns.Print(target .. " didn't answer. They need to be online with v3.14.2 or newer.")
		end
		ns.Print("They're there. Running 4 phases (about 90 seconds); keep playing normally.")
		self:Phase(1)
	end)
end

function ST:Phase(i)
	local r = self.run
	local ph = PHASES[i]
	if not ph then return C_Timer.After(8, function() self:Query(1) end) end
	local s = { attempted = 0, ok = 0, refused = 0, reasons = {}, t0 = now() }
	r.sent[ph.key] = s
	local rate = ph.rate or STEADY_RATE
	local n = ph.burst and BURST or rate * STEADY_SECS
	local pad = ph.pad and string.rep("x", ph.pad) or nil
	local k = 0
	local function one()
		k = k + 1
		local prefix = PREFIXES[((k - 1) % ph.spread) + 1]
		local good, why = send(prefix, pad and J("ST", r.id, ph.key, k, pad) or J("ST", r.id, ph.key, k), r.target)
		s.attempted = s.attempted + 1
		if good then s.ok = s.ok + 1 else s.refused = s.refused + 1; s.reasons[why] = (s.reasons[why] or 0) + 1 end
	end
	if ph.burst then
		for _ = 1, n do one() end
		C_Timer.After(REST, function() self:Phase(i + 1) end)
	else
		local ticker
		ticker = C_Timer.NewTicker(1 / rate, function()
			one()
			if k >= n then ticker:Cancel(); C_Timer.After(REST, function() self:Phase(i + 1) end) end
		end)
	end
	ns.Print(("  phase %s: %s..."):format(ph.key, ph.label))
end

function ST:Query(try)
	local r = self.run
	if not r or r.report then return end
	if try > 4 then
		self.run = nil
		return ns.Print("No report came back from " .. r.target .. ". Try again in a minute.")
	end
	send(PREFIXES[1], J("SQ", r.id), r.target)
	C_Timer.After(6, function() self:Query(try + 1) end)
end

function ST:Report(f)
	local r = self.run
	if not r or f[2] ~= r.id or r.report then return end
	r.report = true
	local got = {}
	for i = 3, #f do
		local key, n, span = f[i]:match("^(%a):(%d+):(%d+)$")
		if key then got[key] = { n = tonumber(n), span = tonumber(span) / 1000 } end
	end
	local lines = { ("|cffd9b545Speed test with %s|r (paste this to Claude):"):format(r.target) }
	for _, ph in ipairs(PHASES) do
		local s, g = r.sent[ph.key] or {}, got[ph.key] or { n = 0, span = 0 }
		local reasons = {}
		for why, c in pairs(s.reasons or {}) do reasons[#reasons + 1] = why .. "x" .. c end
		lines[#lines + 1] = ("  %s %-24s sent %d, refused by client %d%s, arrived %d over %.1fs"):format(ph.key, ph.label,
			s.attempted or 0, s.refused or 0, #reasons > 0 and (" [" .. table.concat(reasons, ",") .. "]") or "", g.n, g.span)
	end
	local A, B, C, D, E = got.A or { n = 0 }, got.B or { n = 0 }, got.C or { n = 0 }, got.D or { n = 0 }, got.E or { n = 0 }
	local verdict
	if B.n >= A.n + 6 or D.n >= C.n + 8 then
		verdict = "Spreading over several prefixes got more through: the limit is per prefix. Worth building."
	elseif A.n >= BURST - 1 and C.n >= STEADY_RATE * STEADY_SECS - 1 then
		verdict = "Everything arrived even on one prefix: no limit hit at these rates."
	else
		verdict = "Several prefixes didn't help: the limit is shared. Bundling messages is the way to speed up."
	end
	lines[#lines + 1] = "  => " .. verdict
	local eSent = r.sent.E and r.sent.E.attempted or 0
	lines[#lines + 1] = (E.n >= eSent - 1 and eSent > 0) and "  => Full-size at 6/s all arrived: the new pacing (about 3-4 a second) has headroom."
		or ("  => Full-size at 6/s: only %d of %d arrived. Tell Claude - the new pacing may need to come down."):format(E.n, eSent)
	for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage(l) end
	self.lastReport = lines
	self.run = nil
end

---------------------------------------------------------------------------
-- receiver
---------------------------------------------------------------------------
ST.recv = {}

local function onMessage(prefix, msg, sender)
	local f = {}
	for x in (msg .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = x end
	local kind, run = f[1], f[2]
	if not run then return end
	if kind == "SP" then
		send(PREFIXES[1], J("SO", run), sender)
	elseif kind == "SO" then
		if ST.run and ST.run.id == run then ST.run.pong = true end
	elseif kind == "ST" then
		local rec = ST.recv[run] or {}
		ST.recv[run] = rec
		local ph = f[3]
		local p = rec[ph] or { n = 0, seen = {} }
		rec[ph] = p
		if not p.seen[f[4]] then
			p.seen[f[4]] = true
			p.n = p.n + 1
			p.first = p.first or now()
			p.last = now()
		end
		if not rec.noted then rec.noted = true; ns.Print(ns.Short and ns.Short(sender) .. " is running a speed test with you." or "Speed test running.") end
	elseif kind == "SQ" then
		local rec = ST.recv[run] or {}
		local parts = { "SR", run }
		for _, key in ipairs({ "A", "B", "C", "D", "E" }) do
			local p = rec[key]
			parts[#parts + 1] = ("%s:%d:%d"):format(key, p and p.n or 0, p and math.floor(((p.last or 0) - (p.first or 0)) * 1000) or 0)
		end
		send(PREFIXES[1], table.concat(parts, "^"), sender)
	elseif kind == "SR" then
		ST:Report(f)
	end
end

ns.On("PLAYER_LOGIN", function()
	for _, p in ipairs(PREFIXES) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
end)
ns.On("CHAT_MSG_ADDON", function(prefix, msg, chatType, sender)
	if not isTest[prefix] or chatType ~= "WHISPER" then return end
	onMessage(prefix, msg, ns.Full(sender))
end)
