-- The Golden Thugget: Comm — addon messaging that works regardless of where players stand.
--   GUILD / GROUP (party or raid) / CHANNEL (custom chat channel) are broadcast routes.
--   Direct messages go over Battle.net game data when the target is a BNet friend
--   (works cross-realm), otherwise addon WHISPER (same or connected realm).
local _, ns = ...
if ns.skip then return end
local Comm = {}
ns.Comm = Comm

local PREFIX = "GoldThugget"
Comm.PREFIX = PREFIX
local MAXLEN = 250          -- hard limit is 255
-- Pacing: a byte budget like ChatThrottleLib's long-standing safe defaults
-- (800 bytes a second, 4000-byte burst). /gt speedtest on WoW Forever (v3.14.2)
-- showed no client throttle at 30-message bursts or 3/s, so the old 1 message a
-- second was the bottleneck. A full-size message costs ~300, a small one ~80.
local CAP, REFILL = 4000, 800
local OVERHEAD = 40 -- per message, as ChatThrottleLib counts it
local function cost(item) return #item.msg + #PREFIX + OVERHEAD end

-- Two queues: game messages first, lobby chatter (announcements, seat lists,
-- ledger posts) only when there's room, so a busy lobby never delays a roll.
local queue, lowQueue = {}, {}
local tokens = CAP
local lastRefill = 0

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function inLockdown()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local THROTTLED = {}
if Enum and Enum.SendAddonMessageResult then
	local E = Enum.SendAddonMessageResult
	if E.AddonMessageThrottle then THROTTLED[E.AddonMessageThrottle] = true end
	if E.ChannelThrottle then THROTTLED[E.ChannelThrottle] = true end
end

local function rawSend(item)
	if item.bnid then
		local ok = pcall(BNSendGameData, item.bnid, PREFIX, item.msg)
		return true -- either sent or not retryable
	end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.chat, item.target)
	if ok and THROTTLED[res] then return false end -- retry later
	return true
end

local function pump()
	local now = GetTime()
	tokens = math.min(CAP, tokens + (now - lastRefill) * REFILL)
	lastRefill = now
	if inLockdown() then return end
	while true do
		local q = (#queue > 0 and queue) or (#lowQueue > 0 and lowQueue)
		if not q or tokens < cost(q[1]) then break end
		local c = cost(q[1])
		if rawSend(q[1]) then
			table.remove(q, 1)
			tokens = tokens - c
		else
			tokens = 0
			break
		end
	end
end

local partSeq = 0
local function enqueue(msg, chat, target, bnid, low)
	local queue = low and lowQueue or queue
	-- a resend of something still waiting to go out adds nothing (retries pile up when busy)
	for _, it in ipairs(queue) do
		if it.whole == msg and it.target == target and it.chat == chat and it.bnid == bnid then return pump() end
	end
	if #msg <= MAXLEN then
		queue[#queue + 1] = { msg = msg, whole = msg, chat = chat, target = target, bnid = bnid }
	else
		partSeq = partSeq % 999 + 1
		local size = MAXLEN - 16
		local n = math.ceil(#msg / size)
		for i = 1, n do
			queue[#queue + 1] = {
				msg = ("~%d~%d~%d~"):format(partSeq, i, n) .. msg:sub((i - 1) * size + 1, i * size),
				chat = chat, target = target, bnid = bnid, whole = i == n and msg or nil,
			}
		end
	end
	pump()
end

---------------------------------------------------------------------------
-- Custom channel
-- WoW Forever accepts addon messages sent *to* a custom channel but never
-- delivers them. So the channel is only used to see who's in it (a hidden
-- channel the addon joins by itself); messages go to each member as whispers.
---------------------------------------------------------------------------
local members, listStarted = {}, 0

local function chanName() return ns.db.settings.channel end
local function isOurs(...)
	local want = chanName():lower()
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" then
			local base = v:lower():gsub("^%d+%.%s*", "")
			if base == want then return true end
		end
	end
	return false
end

function Comm:ChannelId()
	local id = GetChannelName(chanName())
	if id and id > 0 then return id end
end

local function hideFromChat()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, chanName()) end
	end
end

function Comm:EnsureChannel()
	local id = self:ChannelId()
	if id then return id end
	pcall(JoinTemporaryChannel, chanName())
	C_Timer.After(1, hideFromChat)
	C_Timer.After(2, function() Comm:RefreshMembers() end)
	return self:ChannelId()
end

function Comm:LeaveChannel()
	if self:ChannelId() then pcall(LeaveChannelByName, chanName()) end
	wipe(members)
end

function Comm:RefreshMembers()
	if not self:ChannelId() or not ListChannelByName then return end
	listStarted = GetTime()
	pcall(ListChannelByName, chanName())
end

-- Everyone else currently in the casino channel
function Comm:ChannelMembers()
	local t = {}
	for n in pairs(members) do if n ~= ns.me then t[#t + 1] = n end end
	table.sort(t)
	return t
end

local function addMember(raw)
	local n = raw and raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[%*@%+]+", "")
	n = n and ns.Full(n)
	if n then members[n] = true end
end

local function initChannel()
	-- member list replies (may arrive in several chunks)
	ns.On("CHAT_MSG_CHANNEL_LIST", function(text, _, _, ...)
		if not isOurs(...) then return end
		if GetTime() - listStarted > 3 then listStarted = GetTime() end
		if GetTime() - (Comm.lastListReset or 0) > 3 then wipe(members); Comm.lastListReset = GetTime() end
		for entry in (text or ""):gmatch("[^,]+") do addMember(entry) end
		if Comm.onMembers then Comm.onMembers() end
	end)
	ns.On("CHAT_MSG_CHANNEL_JOIN", function(_, who, _, ...)
		if isOurs(...) then addMember(who); if Comm.onMembers then Comm.onMembers() end end
	end)
	ns.On("CHAT_MSG_CHANNEL_LEAVE", function(_, who, _, ...)
		if isOurs(...) then local n = ns.Full(who); if n then members[n] = nil end end
	end)
	-- keep the channel's housekeeping out of the chat window
	if ChatFrame_AddMessageEventFilter then
		local function filter(_, _, ...)
			if isOurs(select(4, ...), select(9, ...)) then return true end
		end
		for _, e in ipairs({ "CHAT_MSG_CHANNEL_LIST", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
			"CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
			pcall(ChatFrame_AddMessageEventFilter, e, filter)
		end
	end
	C_Timer.After(5, function() Comm:EnsureChannel() end)
	C_Timer.NewTicker(60, function() Comm:RefreshMembers() end)
end

---------------------------------------------------------------------------
-- Battle.net lookup (cross-realm direct messaging)
---------------------------------------------------------------------------
local bnCache, bnCacheTime = {}, -100

local function rebuildBN()
	wipe(bnCache)
	bnCacheTime = GetTime()
	if not (C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and BNGetNumFriends) then return end
	local numFriends = BNGetNumFriends() or 0
	for i = 1, numFriends do
		local n = C_BattleNet.GetFriendNumGameAccounts(i) or 0
		for j = 1, n do
			local info = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if info and info.isOnline and info.characterName and info.realmName
				and info.clientProgram == BNET_CLIENT_WOW
				and (not WOW_PROJECT_ID or not info.wowProjectID or info.wowProjectID == WOW_PROJECT_ID) then
				bnCache[info.characterName .. "-" .. ns.NormRealm(info.realmName)] = info.gameAccountID
			end
		end
	end
end

function Comm:FindBN(fullName)
	if ns.forever then return nil end -- one realm per ruleset: plain whispers reach everyone
	if GetTime() - bnCacheTime > 15 then rebuildBN() end
	return bnCache[fullName]
end

---------------------------------------------------------------------------
-- Public send API
---------------------------------------------------------------------------
-- Direct message to one player, anywhere.
function Comm:SendTo(msg, fullName, low)
	if not fullName or fullName == ns.me then return end
	local bnid = self:FindBN(fullName)
	if bnid then
		enqueue(msg, nil, nil, bnid, low)
	else
		enqueue(msg, "WHISPER", fullName, nil, low)
	end
end

-- how many messages are waiting (for the house window)
function Comm:Backlog() return #queue + #lowQueue end

-- roughly how long until everything waiting now has gone out
function Comm:BacklogSeconds()
	local bytes = 0
	for _, it in ipairs(queue) do bytes = bytes + cost(it) end
	for _, it in ipairs(lowQueue) do bytes = bytes + cost(it) end
	return math.max(0, bytes - tokens) / REFILL
end

-- Broadcast on a shared route. Returns false if the route isn't usable right now.
function Comm:SendRoute(msg, route, low)
	if route == "GUILD" then
		if not IsInGuild() then return false end
		enqueue(msg, "GUILD", nil, nil, low)
	elseif route == "GROUP" then
		local chat
		if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then chat = "INSTANCE_CHAT"
		elseif IsInRaid() then chat = "RAID"
		elseif IsInGroup() then chat = "PARTY" end
		if not chat then return false end
		enqueue(msg, chat, nil, nil, low)
	elseif route == "CHANNEL" then
		-- channel addon messages are never delivered on Forever: whisper each member
		if not self:EnsureChannel() then return false end
		for _, p in ipairs(self:ChannelMembers()) do self:SendTo(msg, p, low) end
	else
		return false
	end
	return true
end

function Comm:RouteAvailable(route)
	if route == "GUILD" then return IsInGuild() end
	if route == "GROUP" then return IsInGroup() or IsInRaid() end
	if route == "CHANNEL" then return self:EnsureChannel() ~= nil end
	return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local parts = {}

local function deliver(sender, msg, via)
	if not sender or sender == ns.me then return end
	local seq, i, n, payload = msg:match("^~(%d+)~(%d+)~(%d+)~(.*)$")
	if seq then
		i, n = tonumber(i), tonumber(n)
		local key = sender .. "#" .. seq
		local buf = parts[key]
		if not buf then
			buf = { n = n, got = 0, t = GetTime() }
			parts[key] = buf
		end
		if not buf[i] then
			buf[i] = payload
			buf.got = buf.got + 1
		end
		if buf.got < buf.n then return end
		parts[key] = nil
		msg = table.concat(buf, "", 1, buf.n)
	end
	if Comm.handler then Comm.handler(sender, msg, via) end
end

function Comm:Init()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	lastRefill = GetTime()

	ns.On("CHAT_MSG_ADDON", function(prefix, msg, chatType, sender)
		if prefix ~= PREFIX then return end
		deliver(ns.Full(sender), msg, chatType)
	end)

	ns.On("BN_CHAT_MSG_ADDON", function(prefix, msg, chatType, gameAccountID)
		if prefix ~= PREFIX then return end
		local info = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(gameAccountID)
		if not (info and info.characterName and info.realmName) then return end
		deliver(info.characterName .. "-" .. ns.NormRealm(info.realmName), msg, "BN")
	end)

	ns.On("BN_FRIEND_INFO_CHANGED", function() bnCacheTime = -100 end)

	C_Timer.NewTicker(0.25, function()
		pump()
		local now = GetTime()
		for k, buf in pairs(parts) do
			if now - buf.t > 60 then parts[k] = nil end
		end
	end)

	-- be in the casino channel so the house can find us
	initChannel()
end
