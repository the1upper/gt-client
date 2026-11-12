-- The Golden Thugget: Texas Hold'em table window. Up to six seats round the
-- felt (yours at the bottom), the board in the middle, bet sizing (1/2 pot, pot,
-- all-in, slider), pre-actions, a turn clock, the hand name for your cards, the
-- winning five cards highlighted, and a recap of the last hand.
-- Shows only what a seated player may see; watchers get the same, minus cards.
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.HoldemUI = UI
local K, HE, W = ns.Cards, ns.Holdem, ns.W
local C_ = W.C
local GOLD = C_.gold

local WIDTH, HEIGHT = 800, 580
-- seat spots round the table, clockwise from the bottom centre (you)
local SPOTS = {
	{ 0, -132 }, { -292, -78 }, { -292, 92 }, { 0, 150 }, { 292, 92 }, { 292, -78 },
}
-- which spots to use for n players
local LAYOUT = { [2] = { 1, 4 }, [3] = { 1, 3, 5 }, [4] = { 1, 2, 4, 6 }, [5] = { 1, 2, 3, 5, 6 }, [6] = { 1, 2, 3, 4, 5, 6 } }

local function HC() return ns.HoldemClient end
local function current()
	local g = ns.Client.game
	local c = g and g.type == "holdem" and g.cards
	return g, c, c and c.he
end

local function stackText(c, bb)
	if not bb or bb <= 0 then return ns.Money(c) end
	return ("|cffffffff%s BB|r (%s)"):format(HE.BB(c, bb), ns.Money(c))
end

---------------------------------------------------------------------------
-- glow pulse for highlighted cards (the winning five)
---------------------------------------------------------------------------
local pulsing = {}
local pulser = CreateFrame("Frame")
local function pulseOn(card)
	card.glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	card.glow:Show()
	pulsing[card] = true
	pulser:SetScript("OnUpdate", function()
		local a = 0.55 + 0.4 * math.abs(math.sin(GetTime() * 3))
		local any = false
		for cd in pairs(pulsing) do any = true; cd.glow:SetAlpha(a) end
		if not any then pulser:SetScript("OnUpdate", nil) end
	end)
end
local function pulseOff(card)
	pulsing[card] = nil
	card.glow:Hide()
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local function seatPanel(parent)
	local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	s:SetSize(168, 74)
	W.Backdrop(s, { 0, 0, 0, 0.45 }, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
	s.name = W.Text(s, 12, C_.gold)
	s.name:SetPoint("TOPLEFT", 8, -6)
	s.name:SetWidth(150)
	s.stack = W.Text(s, 11, C_.text)
	s.stack:SetPoint("TOPLEFT", 8, -24)
	s.stack:SetWidth(156)
	s.status = W.Text(s, 11, C_.muted)
	s.status:SetPoint("TOPLEFT", 8, -42)
	s.status:SetWidth(156)
	-- the decision clock under the panel
	s.clock = s:CreateTexture(nil, "OVERLAY")
	s.clock:SetPoint("BOTTOMLEFT", 2, 2)
	s.clock:SetHeight(4)
	s.clock:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	s.clock:Hide()
	s.cards = {}
	for k = 1, 2 do
		local c = ns.CardUI.NewCard(parent, 40, 56)
		s.cards[k] = c
	end
	s.bet = W.Text(parent, 12, C_.text)
	s.dealer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	s.dealer:SetSize(20, 20)
	W.Backdrop(s.dealer, { 0.95, 0.92, 0.85, 1 }, { 0.2, 0.15, 0.1, 1 })
	local d = W.Text(s.dealer, 11, { 0.1, 0.08, 0.05 })
	d:SetPoint("CENTER", 0, 0)
	d:SetText("D")
	return s
end

function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetHoldemFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER", 0, 30)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50)
	W.Backdrop(f, W.C.felt, W.C.gold, 3) -- same solid felt + gold frame as the dice tables
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetHoldemFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetHoldemFrame")
	f:SetScript("OnShow", function() UI:Refresh() end)
	f:SetScript("OnUpdate", function(_, e)
		UI:Glow() -- every frame, so the pulse is smooth
		UI.acc = (UI.acc or 0) + e
		if UI.acc >= 0.1 then UI.acc = 0; UI:Tick() end
	end)

	-- your-turn glow (shared with every table window): red halo + inner ring
	self.glow = W.TurnGlow(f)

	local mark = W.Logo(f, 300, "BORDER")
	mark:SetPoint("CENTER", 0, 4)
	mark:SetAlpha(0.12)
	local crest = W.Logo(f, 56)
	crest:SetPoint("TOPLEFT", 16, -8)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 14, -54)
	line:SetPoint("TOPRIGHT", -14, -54)
	line:SetHeight(1)
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)

	self.title = W.Text(f, 18, C_.gold)
	self.title:SetPoint("TOPLEFT", 82, -12)
	self.sub = W.Text(f, 12, C_.text)
	self.sub:SetPoint("TOPLEFT", 82, -34)
	self.timer = W.Text(f, 16, C_.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -46, -20)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() return "holdem" end)
	self.rules:SetPoint("TOPRIGHT", -96, -18)
	self.recapBtn = W.Button(f, "Last hand", 84, 22)
	self.recapBtn:SetPoint("RIGHT", self.rules, "LEFT", -6, 0)
	self.recapBtn:SetScript("OnClick", function() UI:ToggleRecap() end)
	W.Tooltip(self.recapBtn, "Who showed what and how each pot (side pots too) was split.")

	self.info = W.Text(f, 12, C_.text)
	self.info:SetPoint("TOPLEFT", 24, -62)
	self.info:SetWidth(520)

	-- the table
	local felt = CreateFrame("Frame", nil, f)
	felt:SetPoint("TOPLEFT", 14, -60)
	felt:SetPoint("BOTTOMRIGHT", -14, 84)
	self.felt = felt
	self.pot = W.Text(felt, 15, { 1, 0.93, 0.6 })
	self.pot:SetPoint("CENTER", 0, 72)
	self.pot:SetJustifyH("CENTER")
	self.sidePots = W.Text(felt, 11, C_.text)
	self.sidePots:SetPoint("TOP", self.pot, "BOTTOM", 0, -2)
	self.sidePots:SetJustifyH("CENTER")
	self.board = {}
	for k = 1, 5 do
		local c = ns.CardUI.NewCard(felt, 60, 84)
		c:Home("CENTER", felt, "CENTER", (k - 3) * 66, 4)
		c:Hide()
		self.board[k] = c
	end
	self.result = W.Text(felt, 14, { 1, 0.93, 0.6 }, "OUTLINE")
	self.result:SetPoint("CENTER", 0, -52)
	self.result:SetJustifyH("CENTER")
	self.result:SetWidth(440)

	self.seats = {}
	for i = 1, 6 do
		local s = seatPanel(felt)
		local x, y = SPOTS[i][1], SPOTS[i][2]
		s:SetPoint("CENTER", felt, "CENTER", x, y)
		-- small cards above the panel; bets toward the middle; dealer button beside
		for k = 1, 2 do s.cards[k]:Home("BOTTOM", s, "TOP", (k - 1.5) * 44, 2) end
		s.bet:SetPoint("CENTER", felt, "CENTER", x * 0.55, y * 0.42 + (y > 0 and -18 or 14))
		s.dealer:SetPoint("LEFT", s, "RIGHT", 4, 0)
		if x > 0 then s.dealer:ClearAllPoints(); s.dealer:SetPoint("RIGHT", s, "LEFT", -4, 0) end
		self.seats[i] = s
	end
	-- your own cards, big, left of your seat
	self.mine = {}
	for k = 1, 2 do
		local c = ns.CardUI.NewCard(felt, 62, 87)
		c:Home("RIGHT", self.seats[1], "LEFT", -10 - (2 - k) * 66, 8)
		c:Hide()
		self.mine[k] = c
	end
	self.handName = W.Text(felt, 13, { 1, 0.93, 0.6 })
	self.handName:SetPoint("BOTTOMLEFT", self.seats[1], "TOPLEFT", 0, 4)
	W.Fit(self.handName, 320, 1)
	-- hover your hand's name: the hand rankings, yours highlighted
	local hv = CreateFrame("Frame", nil, felt)
	hv:SetPoint("BOTTOMLEFT", self.handName, "BOTTOMLEFT", -2, -2)
	hv:SetSize(300, 20)
	hv:SetFrameLevel(self.seats[1]:GetFrameLevel() + 2)
	hv:EnableMouse(true)
	hv:SetScript("OnEnter", function(z) UI:ShowRanks(z) end)
	hv:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.rankHover = hv

	-------------------------------------------------- action bar
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("BOTTOMLEFT", 18, 14)
	bar:SetPoint("BOTTOMRIGHT", -18, 14)
	bar:SetHeight(70)
	self.bar = bar
	self.foldBtn = W.Button(bar, "Fold", 86, 30)
	self.foldBtn:SetPoint("BOTTOMLEFT", 0, 0)
	self.foldBtn:SetScript("OnClick", function() HC():Fold() end)
	self.callBtn = W.Button(bar, "Check", 150, 30)
	self.callBtn:SetPoint("LEFT", self.foldBtn, "RIGHT", 8, 0)
	self.callBtn:SetScript("OnClick", function()
		local L = HC():Legal()
		if not L then return end
		if L.check then HC():Check() else HC():Call() end
	end)
	self.raiseBtn = W.Button(bar, "Raise", 170, 30, "gold")
	self.raiseBtn:SetPoint("LEFT", self.callBtn, "RIGHT", 8, 0)
	self.raiseBtn:SetScript("OnClick", function() HC():Raise(UI.raiseTo) end)

	-- sizing row
	local function sizeBtn(text, w, fn)
		local b = W.Button(bar, text, w, 24)
		b:SetScript("OnClick", fn)
		return b
	end
	self.halfBtn = sizeBtn("1/2 Pot", 64, function() UI:SetRaise(HC():PotTo(0.5)) end)
	self.halfBtn:SetPoint("BOTTOMLEFT", 0, 40)
	self.potBtn = sizeBtn("Pot", 50, function() UI:SetRaise(HC():PotTo(1)) end)
	self.potBtn:SetPoint("LEFT", self.halfBtn, "RIGHT", 4, 0)
	self.allBtn = sizeBtn("All-in", 60, function() local L = HC():Legal(); if L then UI:SetRaise(L.maxTo) end end)
	self.allBtn:SetPoint("LEFT", self.potBtn, "RIGHT", 4, 0)
	local sl = CreateFrame("Slider", nil, bar, "BackdropTemplate")
	sl:SetOrientation("HORIZONTAL")
	sl:SetSize(190, 14)
	W.Backdrop(sl, { 0.03, 0.025, 0.025, 0.95 }, C_.goldDim)
	sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	sl:SetMinMaxValues(0, 1)
	sl:SetValue(0)
	pcall(sl.SetValueStep, sl, 1)
	pcall(sl.SetObeyStepOnDrag, sl, true)
	sl:EnableMouseWheel(true)
	sl:SetScript("OnMouseWheel", function(s, d)
		local _, c, he = current()
		local stepC = (he and he.bb) or 1
		s:SetValue(s:GetValue() + d * stepC)
	end)
	sl:SetScript("OnValueChanged", function(_, v)
		if UI.syncing then return end
		local _, c, he = current()
		local L = HC():Legal()
		if not L then return end
		local stepC = he and math.max(1, he.sb) or 1
		local to = math.floor(v / stepC + 0.5) * stepC
		if v >= L.maxTo then to = L.maxTo end
		UI:SetRaise(to, true)
	end)
	sl:SetPoint("LEFT", self.allBtn, "RIGHT", 12, 0)
	self.slider = sl
	self.amount = W.EditBox(bar, 92)
	self.amount:SetPoint("LEFT", sl, "RIGHT", 10, 0)
	self.amount:SetScript("OnEnterPressed", function(e)
		e:ClearFocus()
		local v = ns.ParseMoney(e:GetText())
		if v then UI:SetRaise(v) end
	end)
	W.Tooltip(self.amount, "Raise to this much in total this round, e.g. 12g or 1g 50s. Enter to set it.")
	-- +1 gold / silver / copper (right-click takes it off, shift-click is x10)
	self.coins = {}
	local prevCoin = self.amount
	for _, x in ipairs({ { 10000, "Gold" }, { 100, "Silver" }, { 1, "Copper" } }) do
		local b = W.Button(bar, "", 50, 24)
		b:SetPoint("LEFT", prevCoin, "RIGHT", prevCoin == self.amount and 8 or 4, 0)
		local plus = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		plus:SetPoint("CENTER", -8, 0)
		plus:SetText("+1")
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetSize(14, 14)
		icon:SetPoint("LEFT", plus, "RIGHT", 2, 0)
		icon:SetTexture("Interface\\MoneyFrame\\UI-" .. x[2] .. "Icon")
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button)
			local L = HC():Legal()
			if not (L and L.raise) then return end
			local step = x[1] * (IsShiftKeyDown() and 10 or 1)
			UI:SetRaise((UI.raiseTo or L.minTo) + (button == "RightButton" and -step or step))
		end)
		W.Tooltip(b, ("Add 1 %s to your bet. Right-click takes 1 off; shift-click for 10."):format(x[2]:lower()))
		self.coins[#self.coins + 1] = b
		prevCoin = b
	end

	-- pre-actions (when it isn't your turn)
	self.pre = {}
	local pres = { { "checkfold", "Check/Fold" }, { "check", "Check" }, { "callany", "Call any" } }
	local prev
	for i, x in ipairs(pres) do
		local b = W.Button(bar, x[2], 110, 26)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", 0, 2) end
		b:SetScript("OnClick", function() HC():SetPre(x[1]) end)
		b.kind, b.label = x[1], x[2]
		self.pre[i] = b
		prev = b
	end

	self.pop = W.ResultPop(felt, 86, 320, 96) -- above the board, clear of your seat
	self.pop:SetFrameLevel(f:GetFrameLevel() + 35)
	self.awayBtn = W.Button(bar, "Sit out", 90, 26)
	self.awayBtn:SetPoint("BOTTOMRIGHT", -108, 2)
	self.awayBtn:SetScript("OnClick", function()
		local _, c, he = current()
		local st = he and he.st
		local me = st and st.seat[ns.me]
		if me and me.away then HC():Back() else HC():Away() end
	end)
	self.showBtn = W.Button(bar, "Show cards", 100, 26)
	self.showBtn:SetPoint("BOTTOMRIGHT", -108, 34)
	self.showBtn:SetScript("OnClick", function() HC():ShowCards() end)
	W.Tooltip(self.showBtn, "Everyone folded to you: show your cards anyway.")
	self.leave = W.Button(bar, "Leave", 100, 26)
	self.leave:SetPoint("BOTTOMRIGHT", 0, 2)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)
	self.away = W.Text(f, 13, { 1, 0.85, 0.4 }, "OUTLINE")
	self.away:SetPoint("BOTTOM", f, "BOTTOM", 0, 92)

	-------------------------------------------------- recap overlay
	local rp = CreateFrame("Frame", nil, f, "BackdropTemplate")
	rp:SetPoint("TOPLEFT", 120, -70)
	rp:SetPoint("BOTTOMRIGHT", -120, 96)
	W.Backdrop(rp, { 0.06, 0.04, 0.04, 1 }, C_.gold)
	rp:SetFrameLevel(f:GetFrameLevel() + 30)
	rp:EnableMouse(true)
	rp:Hide()
	rp.title = W.Text(rp, 15, C_.gold)
	rp.title:SetPoint("TOPLEFT", 14, -12)
	rp.text = W.Text(rp, 12, C_.text)
	rp.text:SetPoint("TOPLEFT", 14, -38)
	rp.text:SetPoint("RIGHT", -14, 0)
	rp.text:SetJustifyV("TOP")
	rp.text:SetSpacing(3)
	local ok = W.Button(rp, "Close", 80, 24, "gold")
	ok:SetPoint("BOTTOMRIGHT", -12, 10)
	ok:SetScript("OnClick", function() rp:Hide() end)
	self.recap = rp
end

function UI:Open()
	self:Build()
	self.frame:Show()
	self.frame:Raise()
	self:Refresh()
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

---------------------------------------------------------------------------
-- seat mapping: you at the bottom, then clockwise
---------------------------------------------------------------------------
function UI:Spots(he)
	local n = #he.order
	local start = ns.IndexOf(he.order, ns.me) or 1
	local map = {}
	local spots = LAYOUT[n] or LAYOUT[6]
	for k = 0, n - 1 do
		local p = he.order[(start + k - 1) % n + 1]
		map[p] = spots[k + 1]
	end
	return map
end

---------------------------------------------------------------------------
-- raise sizing
---------------------------------------------------------------------------
function UI:SetRaise(to, fromSlider)
	local L = HC():Legal()
	if not L then return end
	to = math.max(L.minTo, math.min(L.maxTo, math.floor(to or 0)))
	self.raiseTo = to
	self.amount:SetText(ns.MoneyPlain(to))
	if not fromSlider then
		self.syncing = true
		self.slider:SetValue(to)
		self.syncing = false
	end
	self:RefreshButtons()
end

---------------------------------------------------------------------------
-- animation hooks (HoldemClient calls these)
---------------------------------------------------------------------------
local function shown() return UI.frame and UI.frame:IsShown() end

function UI:NewHand()
	if not shown() then return end
	for _, c in ipairs(self.board) do c:Hide(); pulseOff(c) end
	for _, c in ipairs(self.mine) do c:Hide(); pulseOff(c) end
	if self.recap:IsShown() then self:ShowRecap() end
	local g, c, he = current()
	if not he then return end
	local spots = self:Spots(he)
	local delay = 0
	for _, p in ipairs(he.ring or {}) do
		local s = self.seats[spots[p]]
		if s and p ~= ns.me then
			for k = 1, 2 do
				s.cards[k]:Set(nil)
				pulseOff(s.cards[k])
				s.cards[k]:SlideFrom(-SPOTS[spots[p]][1] * 0.8, -SPOTS[spots[p]][2] * 0.8, delay) -- from the middle
				delay = delay + 0.05
			end
		end
	end
	self.dealDelay = delay
	self:Refresh()
end

function UI:DealHole()
	if not shown() then return end
	local g, c, he = current()
	if not (he and he.my) then return end
	local d = self.dealDelay or 0
	for k = 1, 2 do
		local card = self.mine[k]
		card:Set(nil)
		card:SlideFrom(120, 160, d + k * 0.06)
		card:FlipTo(he.my[k], d + 0.45 + k * 0.1)
	end
	self.dealDelay = 0
end

function UI:Board(from)
	if not shown() then return end
	local g, c, he = current()
	if not he then return end
	for k = from, #he.board do
		local card = self.board[k]
		card:Set(nil)
		card:SlideFrom(0, 120, (k - from) * 0.12)
		card:FlipTo(he.board[k], 0.4 + (k - from) * 0.15)
	end
	self:Refresh()
end

function UI:Flip()
	if not shown() then return end
	local g, c, he = current()
	if not he then return end
	local spots = self:Spots(he)
	local delay = 0
	for p, h in pairs(he.shown) do
		local s = self.seats[spots[p]]
		if s and p ~= ns.me then
			for k = 1, 2 do s.cards[k]:Show(); s.cards[k]:FlipTo(h[k], delay); delay = delay + 0.08 end
		end
	end
	self:Refresh()
end

function UI:Showdown()
	if not shown() then return end
	self:Flip()
	local g, c, he = current()
	if not he then return end
	-- the winning five cards glow
	local win = {}
	for _, code in ipairs(he.winCards or {}) do win[code] = true end
	local function mark(card) if card.code and win[card.code] and card:IsShown() then pulseOn(card) else pulseOff(card) end end
	C_Timer.After(0.6, function()
		for _, card in ipairs(self.board) do mark(card) end
		for _, card in ipairs(self.mine) do mark(card) end
		for _, s in ipairs(self.seats) do for k = 1, 2 do mark(s.cards[k]) end end
	end)
	if self.recap:IsShown() then self:ShowRecap() end
end

function UI:State(prev, st)
	if not shown() then return end
	local g, c, he = current()
	-- a new decision for me: start the raise amount at the minimum
	if st.toAct == ns.me and not (prev and prev.toAct == ns.me) then
		self.raiseTo = nil
	end
end

---------------------------------------------------------------------------
-- recap
---------------------------------------------------------------------------
function UI:ToggleRecap()
	if self.recap:IsShown() then self.recap:Hide() else self:ShowRecap() end
end

function UI:RecapText(he)
	local r = he.lastRecap
	if not r then return "No hand finished yet." end
	local lines = {}
	if #r.board > 0 then lines[#lines + 1] = "Board: " .. K.TextList(r.board) end
	if #r.shows > 0 then
		lines[#lines + 1] = " "
		for _, s in ipairs(r.shows) do
			lines[#lines + 1] = ("%s showed %s%s"):format(ns.Who(s.p), K.TextList(s.cards), s.name and ("  |cffd9b545" .. s.name .. "|r") or "")
		end
	end
	local folded = {}
	for _, p in ipairs(he.order) do
		local shownIt = false
		for _, s in ipairs(r.shows) do if s.p == p then shownIt = true end end
		if not shownIt then folded[#folded + 1] = ns.Who(p) end
	end
	if #r.shows > 0 and #folded > 0 then lines[#lines + 1] = "|cff9e948aMucked or folded: " .. table.concat(folded, ", ") .. "|r" end
	lines[#lines + 1] = " "
	local main = true
	for _, pot in ipairs(r.pots) do
		local wn = {}
		for i, p in ipairs(pot.winners) do wn[i] = ns.Who(p) end
		if pot.uncalled then
			lines[#lines + 1] = ("Uncalled %s returned to %s"):format(ns.Money(pot.amount), wn[1] or "?")
		else
			local label = main and "Main pot" or "Side pot"
			main = false
			if #wn > 1 then
				local each = math.floor(pot.amount / #wn)
				lines[#lines + 1] = ("%s %s: split by %s (%s each%s)"):format(label, ns.Money(pot.amount), table.concat(wn, " & "), ns.Money(each),
					pot.amount % #wn ~= 0 and (", odd copper to " .. wn[1]) or "")
			else
				lines[#lines + 1] = ("%s %s: %s"):format(label, ns.Money(pot.amount), wn[1] or "?")
			end
		end
	end
	lines[#lines + 1] = " "
	for _, l in ipairs(ns.PayoutLines(r.net)) do lines[#lines + 1] = l end
	return table.concat(lines, "\n")
end

function UI:ShowRecap()
	local g, c, he = current()
	self.recap.title:SetText(he and he.lastRecap and ("Hand " .. he.lastRecap.hand) or "Last hand")
	self.recap.text:SetText(he and self:RecapText(he) or "No hand finished yet.")
	self.recap:Show()
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
-- the your-turn ring round the window
function UI:Glow()
	self.glow:Update(ns.ClientUI.MyTurn())
end

function UI:Tick()
	local g, c, he = current()
	local st = he and he.st
	if st and st.toAct and he.deadline and not he.result then
		local left = math.max(0, he.deadline - GetTime())
		local secs = math.ceil(left)
		local mine = st.toAct == ns.me
		self.timer:SetText(((secs <= 5) and "|cffff6060" or "|cffffffff") .. secs .. "s|r")
		local spots = self:Spots(he)
		for p, i in pairs(spots) do
			local s = self.seats[i]
			if p == st.toAct and st.secs > 0 then
				s.clock:SetWidth(math.max(1, 164 * left / st.secs))
				s.clock:SetColorTexture(secs <= 5 and 1 or GOLD[1], secs <= 5 and 0.38 or GOLD[2], secs <= 5 and 0.38 or GOLD[3], 0.95)
				s.clock:Show()
			else
				s.clock:Hide()
			end
		end
		if mine and secs <= 5 then self.timer:SetText("|cffff6060" .. secs .. "s - your turn!|r") end
	else
		self.timer:SetText("")
		for _, s in ipairs(self.seats) do s.clock:Hide() end
	end
end

function UI:RefreshButtons()
	local g, c, he = current()
	local L = HC() and HC():Legal()
	local playing = he and not g.watching and HC():Seated(he) and g.phase == "playing"
	local st = he and he.st
	local me = st and st.seat[ns.me]
	local inHand = me and not me.out and not me.folded and not me.allin
	local myTurn = L ~= nil
	-- the decision buttons
	for _, b in ipairs({ self.foldBtn, self.callBtn, self.raiseBtn, self.halfBtn, self.potBtn, self.allBtn }) do b:SetShown(myTurn) end
	self.slider:SetShown(myTurn and L.raise)
	self.amount:SetShown(myTurn and L.raise)
	for _, b in ipairs(self.coins) do b:SetShown(myTurn and L.raise) end
	for _, b in ipairs({ self.halfBtn, self.potBtn, self.allBtn }) do b:SetShown(myTurn and L.raise) end
	if myTurn then
		self.foldBtn:SetEnabled(not L.check) -- never fold when checking is free
		self.callBtn:SetText(L.check and "Check" or ("Call " .. ns.MoneyPlain(L.toCall)))
		if L.raise then
			if not self.raiseTo then
				self.syncing = true
				self.slider:SetMinMaxValues(L.minTo, L.maxTo)
				self.slider:SetValue(L.minTo)
				self.syncing = false
				self.raiseTo = L.minTo
				self.amount:SetText(ns.MoneyPlain(L.minTo))
			else
				self.syncing = true
				self.slider:SetMinMaxValues(L.minTo, L.maxTo)
				self.syncing = false
			end
			local to = math.max(L.minTo, math.min(L.maxTo, self.raiseTo))
			local word = to >= L.maxTo and "All-in" or (L.bet and "Bet" or "Raise to")
			self.raiseBtn:SetText(word .. " " .. ns.MoneyPlain(to))
			self.raiseBtn:SetEnabled(true)
		else
			self.raiseBtn:SetText(L.toCall > 0 and "Can't raise" or "Raise")
			self.raiseBtn:SetEnabled(false)
		end
	end
	-- pre-actions: when you're in the hand and it isn't your turn
	local showPre = playing and inHand and not myTurn and st and st.toAct ~= nil and not he.result
	for _, b in ipairs(self.pre) do
		b:SetShown(showPre and true or false)
		if showPre then
			local on = he.pre == b.kind
			b:SetText((on and "|cff59d959[x]|r " or "[  ] ") .. b.label)
		end
	end
	self.awayBtn:SetShown(playing and me ~= nil)
	self.awayBtn:SetText(me and me.away and "I'm back" or "Sit out")
	self.showBtn:SetShown((playing and he.canShow) and true or false)
end

function UI:Refresh()
	if not shown() then return end
	local g, c, he = current()
	if not he then
		self.title:SetText("Texas Hold'em")
		self.sub:SetText("")
		self.info:SetText(g and g.cards and "Seating the table..." or "You're not at a Hold'em table.")
		for _, s in ipairs(self.seats) do s:Hide(); s.bet:Hide(); s.dealer:Hide(); for k = 1, 2 do s.cards[k]:Hide() end end
		for _, cd in ipairs(self.board) do cd:Hide() end
		for _, cd in ipairs(self.mine) do cd:Hide() end
		self.pot:SetText(""); self.sidePots:SetText(""); self.result:SetText(""); self.handName:SetText("")
		self.leave:SetShown(true)
		ns.Client:SetLeaveButton(self.leave, g, true, "Close")
		self:RefreshButtons()
		return
	end
	local st = he.st
	self.title:SetText(("Texas Hold'em  %s |cffaaaaaabuy-in|r"):format(ns.Money(he.buyin)))
	self.sub:SetText(("Blinds %s / %s    Hand %d of %d"):format(ns.Money(he.sb), ns.Money(he.bb), math.max(1, he.hand), he.hands))
	local mine = c.deltas[ns.me]
	local info = g.watching and "|cff9e948aWatching|r" or ("You: " .. W.Signed(mine or 0) .. (he.st and he.hand > 0 and "" or ""))
	if he.void then info = info .. "   |cffffd100Table ended early.|r" end
	if c.phase == "closed" then info = info .. "   |cffffd100Table closed.|r" end
	if c.problem then info = info .. "   |cffff4040" .. c.problem .. "|r" end
	self.info:SetText(info)
	-- table over after several hands: your total for the table
	if c.phase == "closed" and (he.hands or 1) > 1 and not g.review then
		local seated = not g.watching and HC():Seated(he)
		self.pop:Play("table:" .. (g.id or "?"), seated and (mine or 0) or nil,
			("Table closed after %d hands - %s"):format(math.max(1, he.hand), seated and "your total" or "final stacks in the log"))
	end

	-- pot (and the layers once there are side pots)
	local potTotal = st and st.pot or 0
	self.pot:SetText(potTotal > 0 and ("Pot: " .. ns.Money(potTotal)) or "")
	local side = ""
	if st and not he.result then
		local contrib, folded = {}, {}
		for _, p in ipairs(he.order) do
			local s = st.seat[p]
			contrib[p] = s and s.contrib or 0
			folded[p] = not s or s.folded or s.out
		end
		local pots = HE.Pots(he.order, contrib, folded)
		local contested = {}
		for _, pt in ipairs(pots) do if not pt.uncalled then contested[#contested + 1] = pt end end
		if #contested > 1 then
			local t = {}
			for i, pt in ipairs(contested) do t[i] = (i == 1 and "Main " or "Side ") .. ns.Money(pt.amount) end
			side = table.concat(t, "   ")
		end
	end
	self.sidePots:SetText(side)

	-- board
	for k = 1, 5 do
		local card = self.board[k]
		local code = he.board[k]
		if code then
			if not card:IsShown() then card:Show() end
			if card.code ~= code and not card.flipping then card:Set(code) end
		else
			card:Hide()
			pulseOff(card)
		end
	end

	-- seats
	local spots = self:Spots(he)
	local used = {}
	for _, p in ipairs(he.order) do
		local i = spots[p]
		used[i] = true
		local s = self.seats[i]
		s:Show()
		local seat = st and st.seat[p]
		local stack = seat and seat.stack or he.stacks[p] or 0
		s.name:SetText(ns.Who(p) .. (p == ns.me and " |cffd9b545(you)|r" or ""))
		s.stack:SetText(stackText(stack, he.bb))
		local status, sc = "", C_.muted
		local la = he.lastAct and he.lastAct[p]
		if seat and seat.out then status = (stack > 0) and "sitting this hand out" or "busted"
		elseif seat and seat.folded then status = "folded"
		elseif seat and seat.allin then status, sc = "ALL-IN", C_.red
		elseif st and st.toAct == p and not he.result then status, sc = "thinking...", C_.gold
		elseif la then
			local words = { check = "checked", call = "called", fold = "folded", raise = "raised" }
			status = words[la.kind] or la.kind
		end
		if seat and seat.away then status = status .. (status ~= "" and "  " or "") .. "|cffffd100(away)|r" end
		if he.result and he.result.net[p] then
			local d = he.result.net[p]
			status = d > 0 and ("|cff59d959won " .. ns.MoneyPlain(d) .. "|r") or ("|cffff6161lost " .. ns.MoneyPlain(-d) .. "|r")
		end
		s.status:SetText(status)
		s.status:SetTextColor(sc[1], sc[2], sc[3])
		local acting = st and st.toAct == p and not he.result
		s:SetBackdropColor(acting and 0.18 or 0, acting and 0.13 or 0, 0, (seat and (seat.folded or seat.out)) and 0.25 or 0.5)
		s:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], acting and 1 or 0.35)
		s:SetAlpha((seat and (seat.folded or seat.out)) and 0.6 or 1)
		-- bet in front of the seat
		local bet = seat and seat.bet or 0
		if bet > 0 and not he.result then s.bet:SetText(ns.Money(bet)); s.bet:Show() else s.bet:Hide() end
		s.dealer:SetShown(he.button == p and he.hand > 0)
		-- cards: face down for anyone in the hand, face up once shown
		local inHand = seat and not seat.out
		for k = 1, 2 do
			local card = s.cards[k]
			if p == ns.me and not g.watching then
				card:Hide()
			elseif not inHand or he.hand == 0 or (seat.folded and not he.shown[p]) then
				card:Hide()
				pulseOff(card)
			else
				card:Show()
				local face = he.shown[p] and he.shown[p][k]
				if card.code ~= face and not card.flipping then card:Set(face) end
			end
		end
	end
	for i, s in ipairs(self.seats) do
		if not used[i] then s:Hide(); s.bet:Hide(); s.dealer:Hide(); for k = 1, 2 do s.cards[k]:Hide() end end
	end

	-- your cards and what they make
	local meSeat = st and st.seat[ns.me]
	for k = 1, 2 do
		local card = self.mine[k]
		if he.my and not g.watching then
			card:Show()
			if card.code ~= he.my[k] and not card.flipping then card:Set(he.my[k]) end
			card:SetAlpha((meSeat and meSeat.folded) and 0.45 or 1)
		else
			card:Hide()
		end
	end
	local hand = he.my and HC():MyHand()
	self.myHand = hand
	self.handName:SetText(hand and ((meSeat and meSeat.folded and ("|cff9e948a" .. hand.name .. " (folded)|r") or hand.name)
		.. "  |cff9e948a(?)|r") or "")
	self.rankHover:SetShown(hand and true or false)

	-- result line
	if he.result then
		local r = he.result
		local t = {}
		for _, pot in ipairs(r.pots) do
			if not pot.uncalled then
				local wn = {}
				for i, p in ipairs(pot.winners) do wn[i] = ns.Who(p) end
				t[#t + 1] = ("%s %s %s"):format(table.concat(wn, " & "), #wn > 1 and "split" or "wins", ns.Money(pot.amount))
			end
		end
		self.result:SetText(table.concat(t, "\n") .. (he.winName and ("\n" .. he.winName) or ""))
		if not g.review then
			local seated = not g.watching and HC():Seated(he)
			local mine = seated and (r.net[ns.me] or 0) or nil
			local line = table.concat(t, ", ") .. (he.winName and (" - " .. he.winName) or "")
			if he.hands and he.hands > 1 then line = ("Hand %d of %d: "):format(he.hand, he.hands) .. line end
			self.pop:Play(("holdem:%s:%s"):format(g.id or "?", he.hand or 0), mine, line)
		end
	else
		self.result:SetText("")
	end

	-- away banner, leave/close
	self.away:SetText((meSeat and meSeat.away and not g.watching) and "You're sitting out: you check or fold automatically and still post blinds." or "")
	local live = g.phase == "playing" and not g.closeAt
	self.leave:SetShown(g.watching or not live)
	ns.Client:SetLeaveButton(self.leave, g, not live, "Close")
	self:RefreshButtons()
	self:Tick()
end

function UI:Init() end

---------------------------------------------------------------------------
-- Hand rankings card (tooltip on your hand's name)
---------------------------------------------------------------------------
UI.RANKS = { -- best first: { name, example, category }
	{ "Royal Flush", "A K Q J 10, one suit", 8, true },
	{ "Straight Flush", "five in a row, one suit", 8 },
	{ "Four of a Kind", "four cards of one rank", 7 },
	{ "Full House", "three of a kind + a pair", 6 },
	{ "Flush", "any five of one suit", 5 },
	{ "Straight", "five in a row (A-2-3-4-5 counts)", 4 },
	{ "Three of a Kind", "three cards of one rank", 3 },
	{ "Two Pair", "two different pairs", 2 },
	{ "Pair", "two cards of one rank", 1 },
	{ "High Card", "none of the above", 0 },
}

-- which row is your hand (Royal Flush is a Straight Flush to Ace)
function UI.RankRow(hand)
	if not hand then return end
	for i, r in ipairs(UI.RANKS) do
		if r[3] == hand.cat then
			if r[4] then
				if hand.name == "Royal Flush" then return i end
			else
				return i
			end
		end
	end
end

function UI:ShowRanks(anchor)
	GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
	GameTooltip:AddLine("Hand rankings", 0.83, 0.69, 0.22)
	local mine = UI.RankRow(self.myHand)
	for i, r in ipairs(UI.RANKS) do
		if i == mine then
			GameTooltip:AddDoubleLine("> " .. r[1], r[2], 1, 0.82, 0, 1, 0.82, 0)
		else
			GameTooltip:AddDoubleLine("   " .. r[1], r[2], 0.9, 0.9, 0.9, 0.62, 0.58, 0.54)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Best five of your two cards + the board. Same hand: the higher cards (kickers) win; a true tie splits the pot.", 0.62, 0.58, 0.54, true)
	GameTooltip:Show()
end
