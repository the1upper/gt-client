-- The Golden Thugget: card table window. Felt table, rendered cards from
-- Media\cards.tga, deal (slide) and flip animations. Shows exactly what a
-- seated player is allowed to see — the house's own seat uses this too.
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.CardUI = UI
local K, W = ns.Cards, ns.W

local ATLAS = ns.MEDIA .. "cards"
local GOLD = { 0.83, 0.69, 0.22 }

---------------------------------------------------------------------------
-- tweens (one OnUpdate driver, idle when nothing animates)
---------------------------------------------------------------------------
local tweens = {}
local driver = CreateFrame("Frame")
local function ease(t) return 1 - (1 - t) * (1 - t) end

local function step(_, elapsed)
	local now = GetTime()
	for i = #tweens, 1, -1 do
		local tw = tweens[i]
		local t = (now - tw.start) / tw.dur
		if t >= 0 then
			if t >= 1 then t = 1 end
			tw.fn(ease(t), t)
			if t >= 1 then
				table.remove(tweens, i)
				if tw.done then tw.done() end
			end
		end
	end
	if UI.frame and UI.frame:IsShown() then UI:Tick() end
	if #tweens == 0 and not (UI.frame and UI.frame:IsShown()) then driver:SetScript("OnUpdate", nil) end
end

local function tween(dur, delay, fn, done)
	tweens[#tweens + 1] = { start = GetTime() + (delay or 0), dur = dur, fn = fn, done = done }
	driver:SetScript("OnUpdate", step)
end
UI.Tween = tween -- shared with the Hold'em window

---------------------------------------------------------------------------
-- card widget
---------------------------------------------------------------------------
local function NewCard(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f.w, f.h = w, h
	local shadow = f:CreateTexture(nil, "BACKGROUND")
	shadow:SetPoint("TOPLEFT", 2, -2)
	shadow:SetPoint("BOTTOMRIGHT", 2, -2)
	shadow:SetColorTexture(0, 0, 0, 0.35)
	f.shadow = shadow
	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(ATLAS)
	f.tex = tex
	local glow = f:CreateTexture(nil, "OVERLAY")
	glow:SetPoint("TOPLEFT", -3, 3)
	glow:SetPoint("BOTTOMRIGHT", 3, -3)
	glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	glow:SetDrawLayer("BACKGROUND", -1)
	glow:Hide()
	f.glow = glow

	function f:Set(code)
		self.code = code
		self.tex:SetTexCoord(K.TexCoord(code))
		self:SetAlpha(1)
		self:Show()
	end
	function f:Home(point, rel, relPoint, x, y)
		self.home = { point, rel, relPoint, x, y }
		self:ClearAllPoints()
		self:SetPoint(point, rel, relPoint, x, y)
	end
	-- slide in from (dx, dy) relative to home
	function f:SlideFrom(dx, dy, delay)
		local h = self.home
		if not h then return end
		ns.Sound.Play("card_deal", delay)
		self:ClearAllPoints()
		self:SetPoint(h[1], h[2], h[3], h[4] + dx, h[5] + dy)
		self:SetAlpha(0)
		tween(0.35, delay, function(e)
			self:SetAlpha(1)
			self:ClearAllPoints()
			self:SetPoint(h[1], h[2], h[3], h[4] + dx * (1 - e), h[5] + dy * (1 - e))
		end)
	end
	-- squeeze to nothing, swap the face, stretch back
	function f:FlipTo(code, delay)
		if self.code == code then return end
		if code then ns.Sound.Play("card_flip", (delay or 0) + 0.14) end
		self.flipping = true
		tween(0.14, delay, function(e) self:SetWidth(math.max(0.5, self.w * (1 - e))) end, function()
			self:Set(code)
			tween(0.14, 0, function(e) self:SetWidth(math.max(0.5, self.w * e)) end, function() self.flipping = false end)
		end)
	end
	f:Set(nil)
	return f
end
UI.NewCard = NewCard

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetTableFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(640, 470)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50) -- table windows sit above the main windows
	W.Backdrop(f, W.C.felt, W.C.gold, 3) -- same solid felt + gold frame as the dice tables
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetTableFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetTableFrame")
	f:SetScript("OnShow", function() driver:SetScript("OnUpdate", step); UI:Refresh() end)

	-- the house crest pressed into the felt
	local mark = W.Logo(f, 330, "BORDER")
	mark:SetPoint("CENTER", 0, -14)
	mark:SetAlpha(0.16)
	local crest = W.Logo(f, 56)
	crest:SetPoint("TOPLEFT", 16, -8)

	-- header rule (as on the dice tables)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 14, -54)
	line:SetPoint("TOPRIGHT", -14, -54)
	line:SetHeight(1)
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)

	self.title = W.Text(f, 18, W.C.gold)
	self.title:SetPoint("TOPLEFT", 82, -20)
	self.pot = W.Text(f, 16, W.C.text, "OUTLINE")
	self.pot:SetPoint("TOP", 0, -22)
	self.timer = W.Text(f, 16, W.C.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -70, -22)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() local g = ns.Client.game; return g and g.type end)
	self.rules:SetPoint("TOPRIGHT", -120, -18)

	self.info = W.Text(f, 12, W.C.text)
	self.info:SetPoint("BOTTOMLEFT", 24, 18)
	W.Fit(self.info, 470, 1)
	self.leave = W.Button(f, "Leave table", 100)
	self.leave:SetPoint("BOTTOMRIGHT", -20, 16)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)

	-------------------------------------------------- Guts layout
	local guts = CreateFrame("Frame", nil, f)
	guts:SetPoint("TOPLEFT", 20, -60)
	guts:SetPoint("BOTTOMRIGHT", -20, 46)
	self.guts = guts
	self.seats = {}
	for i = 1, 8 do -- 7 opponents, or all 8 players when watching
		local s = CreateFrame("Frame", nil, guts, "BackdropTemplate")
		s:SetSize(146, 108)
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		s:SetPoint("TOPLEFT", col * 150, -row * 112)
		s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		s:SetBackdropColor(0, 0, 0, 0.25)
		s:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
		s.name = W.Text(s, 12, W.C.gold)
		s.name:SetPoint("TOPLEFT", 6, -5)
		W.Fit(s.name, 134, 1)
		s.status = W.Text(s, 11, W.C.text)
		s.status:SetPoint("BOTTOMLEFT", 6, 5)
		W.Fit(s.status, 134, 1)
		s.cards = {}
		for k = 1, 3 do
			local c = NewCard(s, 36, 50)
			c:Home("CENTER", s, "CENTER", (k - 2) * 40, 2)
			s.cards[k] = c
		end
		self.seats[i] = s
	end
	self.myArea = CreateFrame("Frame", nil, guts)
	self.myArea:SetPoint("BOTTOMLEFT", 0, 0)
	self.myArea:SetSize(600, 120)
	self.myCards = {}
	for k = 1, 3 do
		local c = NewCard(self.myArea, 72, 101)
		c:Home("BOTTOMLEFT", self.myArea, "BOTTOMLEFT", 10 + (k - 1) * 80, 4)
		self.myCards[k] = c
	end
	self.myHandName = W.Text(self.myArea, 16, W.C.gold)
	self.myHandName:SetPoint("TOPLEFT", 260, -10)
	self.myStatus = W.Text(self.myArea, 12, W.C.text)
	self.myStatus:SetPoint("TOPLEFT", 260, -36)
	W.Fit(self.myStatus, 330, 3)
	self.inBtn = W.Button(self.myArea, "IN", 130, 32)
	self.inBtn:SetPoint("BOTTOMLEFT", 260, 8)
	self.inBtn:SetScript("OnClick", function()
		local g = ns.Client.game
		if g and g.type == "acey" then ns.CardClient:Pick((ns.CardClient:PickChoices())) else ns.CardClient:Decide("in") end
	end)
	self.outBtn = W.Button(self.myArea, "OUT", 90, 32)
	self.outBtn:SetPoint("LEFT", self.inBtn, "RIGHT", 10, 0)
	self.outBtn:SetScript("OnClick", function()
		local g = ns.Client.game
		if g and g.type == "acey" then ns.CardClient:Pick(select(2, ns.CardClient:PickChoices())) else ns.CardClient:Decide("out") end
	end)

	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, 30)
end

function UI:Open()
	self:Build()
	self.frame:Show()
	self.frame:Raise() -- above the /gt and /gth windows
	self:Refresh()
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

local function money(c)
	if c > 0 then return "|cff40ff40+|r" .. ns.Money(c) end
	if c < 0 then return "|cffff6060-|r" .. ns.Money(-c) end
	return "|cffaaaaaa+/-0|r"
end

local function others(c)
	local t = {}
	for _, p in ipairs(c.seats) do if p ~= ns.me then t[#t + 1] = p end end
	return t
end

---------------------------------------------------------------------------
-- animation hooks called by CardClient
---------------------------------------------------------------------------
function UI:Deal()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	local c = g and g.cards
	if not c then return end
	self:Refresh()
	if g.type == "guts" then
		local delay = 0
		for i, p in ipairs(others(c)) do
			local s = self.seats[i]
			if s then
				for k = 1, 3 do
					s.cards[k]:Set(nil)
					s.cards[k]:SlideFrom(0, 140, delay)
					delay = delay + 0.04
				end
			end
		end
		for k = 1, 3 do
			local card = self.myCards[k]
			card:Set(nil)
			card:SlideFrom(240, 220, delay)
			if c.myHand then card:FlipTo(c.myHand[k], delay + 0.45 + k * 0.08) end
			delay = delay + 0.06
		end
	elseif g.type == "acey" then
		-- each player's two cards face up, the third face down between them
		local delay = 0
		local function deal(cards, h, dx, dy)
			for _, k in ipairs({ 1, 3, 2 }) do
				local card = cards[k]
				card:Set(nil)
				card:SetAlpha(1)
				card:SlideFrom(dx, dy, delay)
				if k ~= 2 then card:FlipTo(k == 1 and h[1] or h[2], delay + 0.45) end
				delay = delay + 0.05
			end
		end
		for i, p in ipairs(others(c)) do
			local s, h = self.seats[i], c.ac and c.ac[p]
			if s and h then deal(s.cards, h, 0, 140) end
		end
		local mine = c.ac and c.ac[ns.me]
		if mine and not g.watching then deal(self.myCards, mine, 240, 220) end
	end
end

function UI:Showdown()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	local c = g and g.cards
	if not c or not c.shown then return end
	self:Refresh()
	local delay = 0
	for i, p in ipairs(others(c)) do
		local s = self.seats[i]
		local h = c.shown[p]
		if s and h then
			for k = 1, 3 do s.cards[k]:FlipTo(h[k], delay); delay = delay + 0.07 end
		end
	end
end

function UI:Reveal()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	local c = g and g.cards
	if not (c and c.ac) then return end
	self:Refresh()
	-- every third card turns over at once (yours a beat later, for the drama)
	for i, p in ipairs(others(c)) do
		local s, h = self.seats[i], c.ac[p]
		if s and h and h[3] then s.cards[2]:FlipTo(h[3], 0.05 * i) end
	end
	local mine = c.ac[ns.me]
	if mine and mine[3] and not g.watching then self.myCards[2]:FlipTo(mine[3], 0.5) end
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
function UI:Tick()
	local g = ns.Client.game
	local c = g and g.cards
	if c and c.deadline and (c.phase == "decide" or c.phase == "pick") then
		local left = math.max(0, math.ceil(c.deadline - GetTime()))
		self.timer:SetText((left <= 5 and "|cffff6060" or "|cffffffff") .. left .. "s|r")
	else
		self.timer:SetText("")
	end
	self.turnGlow:Update(ns.ClientUI.MyTurn())
end

-- Clicking IN at Guts commits the stay-in bet: show it right away in your
-- total and the pot (the others only see it at the showdown).
function UI.Pending(g)
	local c = g and g.cards
	if g and g.type == "guts" and c and c.phase == "decide" and c.myDecision == "in" then return g.param or 0 end
	return 0
end
function UI.ShownPot(g)
	return (g.cards.pot or 0) + UI.Pending(g)
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	local c = g and g.cards
	if not c then
		self.title:SetText("The Golden Thugget")
		self.pot:SetText("")
		self.info:SetText("You're not at a card table.")
		self.guts:Hide()
		self.leave:SetEnabled(false)
		self.pop:Hide()
		return
	end
	local def = ns.Games.types[g.type]
	self.title:SetText(def.name .. "  " .. ns.Money(g.wager) .. " |cffaaaaaaante|r")
	self.pot:SetText("Pot: " .. ns.Money(UI.ShownPot(g)))
	ns.Client:SetLeaveButton(self.leave, g, g.phase == "playing", "Leave table")
	local mine = (c.deltas[ns.me] or 0) - UI.Pending(g)
	local info = g.watching and "|cff9e948aWatching|r" or ("You: " .. money(mine))
	if c.phase == "closed" then info = info .. "   |cffffd100Table closed.|r" end
	if c.problem then info = info .. "   |cffff4040" .. c.problem .. "|r" end
	self.info:SetText(info)

	if g.type == "guts" then
		self.guts:Show()
		self.myArea:SetShown(not g.watching)
		local list = others(c)
		for i, s in ipairs(self.seats) do
			local p = list[i]
			if p then
				s:Show()
				s.name:SetText(ns.Who(p) .. "  " .. money((c.deltas[p] or 0) - (p == ns.me and UI.Pending(g) or 0)))
				local status
				if c.phase == "decide" then
					status = c.decided and c.decided[p] and "|cffffd100decided|r" or "|cffaaaaaathinking...|r"
				elseif c.ins then
					if c.ins[p] then
						local _, name = K.Eval3(c.shown[p])
						status = "|cff40ff40IN|r - " .. name
					else
						status = "|cff888888out|r"
					end
				else
					status = ""
				end
				local hn = c.handNet and c.handNet[p]
				if hn and hn ~= 0 then status = status .. "  " .. (hn > 0 and ("|cff59d959+|r" .. ns.Money(hn)) or ("|cffff6161-|r" .. ns.Money(-hn))) end
				s.status:SetText(status)
				local folded = c.ins and not c.ins[p]
				for k = 1, 3 do
					local card = s.cards[k]
					if c.round == 0 then card:Hide() else
						card:Show()
						local face = c.shown and c.shown[p] and c.shown[p][k]
						if not card.flipping and card.code ~= face then card:Set(face) end
						card:SetAlpha(folded and 0.35 or 1)
					end
				end
				s:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], (c.ins and c.ins[p]) and 0.9 or 0.35)
			else
				s:Hide()
			end
		end
		for k = 1, 3 do
			local card = self.myCards[k]
			if c.myHand then
				card:Show()
				if card.code ~= c.myHand[k] and not card.flipping then card:Set(c.myHand[k]) end
			else
				card:Hide()
			end
		end
		if c.myHand then
			local _, name = K.Eval3(c.myHand)
			self.myHandName:SetText(name)
		else
			self.myHandName:SetText(c.round == 0 and "Waiting for the deal..." or "")
		end
		local st
		if c.phase == "decide" then
			st = c.myDecision and ("You're |cffffd100" .. c.myDecision:upper() .. "|r - waiting for the others") or "In or out?"
		elseif c.result then
			local hn = c.handNet and c.handNet[ns.me]
			st = c.result .. (hn and ("\nYou " .. ns.WonLost(hn) .. " this hand") or "")
		else
			st = ""
		end
		self.myStatus:SetText(st)
		local canDecide = c.phase == "decide" and c.myHand and not c.myDecision and ns.IndexOf(c.seats, ns.me)
		self.inBtn:SetText((g.param or 0) > 0 and ("IN  +" .. ns.Money(g.param)) or "IN")
		self.outBtn:SetText("OUT")
		self.outBtn:SetWidth(90)
		self.inBtn:SetEnabled(canDecide and true or false)
		self.outBtn:SetEnabled(canDecide and true or false)
		-- IN/OUT only while there's a decision to make (and after, showing what you picked)
		local deciding = c.phase == "decide" and ns.IndexOf(c.seats, ns.me) and not g.watching
		self.inBtn:SetShown(deciding and true or false)
		self.outBtn:SetShown(deciding and true or false)
		-- this hand's result
		if c.result and not g.review then
			local seated = ns.IndexOf(c.seats, ns.me) and not g.watching
			self.pop:Play(("guts:%s:%s"):format(g.id or "?", c.round or 0), (seated and c.handNet) and (c.handNet[ns.me] or 0) or nil, c.result) -- no handNet = pot carried over
		end
	elseif g.type == "acey" then
		self:AceyRefresh(g, c)
	end
	-- table over: your total, when it's more than the one hand you just saw
	if c.phase == "closed" and not g.review and (g.type == "acey" or (g.hands or 1) ~= 1) then
		local seated = ns.IndexOf(c.seats, ns.me) and not g.watching
		self.pop:Play("table:" .. (g.id or "?"), seated and (c.deltas[ns.me] or 0) or nil,
			"Table closed - " .. (seated and "your total for the table" or "final standings are in the log"))
	end
	self:Tick()
end

-- Acey-Deucey: a tile per player (their two cards, the third between them), your
-- own hand big at the bottom with the two calls your cards allow
local WORD = K.ACEY_WORD
function UI:AceyRefresh(g, c)
	self.guts:Show()
	local me = not g.watching and ns.IndexOf(c.seats, ns.me)
	self.myArea:SetShown(me and true or false)
	local outAt = c.outAt or {}
	local alive = {}
	for _, p in ipairs(c.alive or {}) do alive[p] = true end
	local function status(p)
		if c.winner == p then return "|cffffd100WINNER|r  +" .. ns.Money(c.wonPot or 0), "win" end
		local o = outAt[p]
		if o and not (c.lastOut and ns.IndexOf(c.lastOut, p)) then
			return o.left and "|cff888888left the table|r" or ("|cff888888out in round %d|r"):format(o.round), "gone"
		end
		local h = c.ac and c.ac[p]
		if c.phase == "pick" then
			if not h then return "", "gone" end
			if p == ns.me and c.myPick then return "you called |cffffd100" .. WORD[c.myPick] .. "|r", "wait" end
			return (c.decided and c.decided[p]) and "|cffffd100called|r" or "|cffaaaaaathinking...|r", "wait"
		end
		if c.picks and h and h[3] then
			local call = c.picks[p]
			if c.again == "idle" then return "|cffaaaaaano call|r", "wait" end
			if not call then return "|cffff6060no call - OUT|r", "out" end
			local right = K.AceyCorrect(h[1], h[2], h[3], call)
			if right then return "|cff40ff40" .. WORD[call] .. " - right|r", "right" end
			return "|cffff6060" .. WORD[call] .. " - " .. (c.again and "wrong (goes again)" or "OUT") .. "|r", c.again and "wait" or "out"
		end
		return c.round == 0 and "" or "still in", "wait"
	end
	local list = others(c)
	for i, s in ipairs(self.seats) do
		local p = list[i]
		if p then
			s:Show()
			s.name:SetText(ns.Who(p) .. "  " .. money(c.deltas[p] or 0))
			local text, kind = status(p)
			s.status:SetText(text)
			local h = c.ac and c.ac[p]
			for k = 1, 3 do
				local card = s.cards[k]
				if not h or kind == "gone" then card:Hide() else
					card:Show()
					local face = (k == 1 and h[1]) or (k == 3 and h[2]) or h[3]
					if not card.flipping and card.code ~= face and (k ~= 2 or face) then card:Set(face) end
					card:SetAlpha(kind == "out" and 0.4 or 1)
				end
			end
			s:SetAlpha(kind == "gone" and 0.55 or 1)
			s:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], (kind == "right" or kind == "win") and 0.95 or 0.35)
		else
			s:Hide()
		end
	end
	-- your hand
	local h = c.ac and c.ac[ns.me]
	for k = 1, 3 do
		local card = self.myCards[k]
		if h and me then
			card:Show()
			local face = (k == 1 and h[1]) or (k == 3 and h[2]) or h[3]
			if not card.flipping and card.code ~= face and (k ~= 2 or face) then card:Set(face) end
		else
			card:Hide()
		end
	end
	local a, b = "in", "out"
	if h then a, b = K.AceyChoices(h[1], h[2]) end
	local headline, st = "", ""
	local text, kind = status(ns.me)
	if c.winner == ns.me then
		headline, st = "|cffffd100You win!|r", ("Last one standing - the pot is yours (%s)."):format(ns.Money(c.wonPot or 0))
	elseif kind == "gone" or kind == "out" then
		headline = "|cffff6060You're out|r"
		st = c.winner and (ns.Who(c.winner) .. " won the pot.") or (#(c.alive or {}) .. " still in.")
	elseif c.phase == "pick" and h then
		if a == "hi" then headline = "A pair - HIGHER or LOWER?"
		elseif math.abs(K.Value(h[1]) - K.Value(h[2])) == 1 then headline = "Nothing in between - OUT can't lose"
		else headline = "IN or OUT?" end
		st = c.myPick and ("You called |cffffd100" .. WORD[c.myPick] .. "|r - waiting for the others") or
			("Round %d - %d still in. Call it before the clock runs out - no call and you're out."):format(c.round, #(c.alive or {}))
	elseif c.picks and h then
		headline = text
		st = c.winner and (ns.Who(c.winner) .. " takes the pot.") or c.again == "idle" and "Nobody called in time - the pot is split." or
			c.again and "Nobody who called was right - they go again." or
			(#(c.alive or {}) .. " still in - next round coming.")
	else
		headline = c.round == 0 and "Waiting for the deal..." or ""
	end
	self.myHandName:SetText(headline)
	self.myStatus:SetText(st)
	local can = ns.CardClient:CanPick()
	self.inBtn:SetText(WORD[a])
	self.outBtn:SetText(WORD[b])
	self.outBtn:SetWidth(130)
	local picking = c.phase == "pick" and h and me and alive[ns.me]
	self.inBtn:SetShown(picking and true or false)
	self.outBtn:SetShown(picking and true or false)
	self.inBtn:SetEnabled(can)
	self.outBtn:SetEnabled(can)
end

function UI:Init() end
