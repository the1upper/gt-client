-- The Golden Thugget: Thugget Dice table. Five dice you click to hold, up to
-- three rolls, then everyone's dice are shown and the best hand takes the pot.
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.HandUI = UI
local W = ns.W
local C_ = W.C
local TH = ns.Games.Thugget
local D6 = ns.MEDIA .. "d6"

local function face(tex, n) -- n = 1..6, nil = blank
	local i = (n or 7) - 1
	tex:SetTexCoord(i * 64 / 512, (i + 1) * 64 / 512, 0, 1)
end

---------------------------------------------------------------------------
-- animation: rolling dice tumble (random faces + wobble) until they land
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local spinning = {} -- texture -> true
local flick = 0

local function onUpdate(_, dt)
	if not (UI.frame and UI.frame:IsShown()) then return end
	flick = flick + dt
	local swap = flick > 0.07
	if swap then flick = 0 end
	for tex, t in pairs(spinning) do
		t.age = t.age + dt
		tex:SetRotation(math.sin(t.age * 22) * 0.35)
		if swap then face(tex, math.random(1, 6)) end
		if t.untilT and GetTime() >= t.untilT then
			spinning[tex] = nil
			tex:SetRotation(0)
			face(tex, t.final)
		end
	end
	UI:Tick()
end

local function spin(tex, final, delay)
	spinning[tex] = { age = 0, final = final, untilT = final and (GetTime() + (delay or 0.6)) or nil }
end
local function settle(tex, final, delay)
	local t = spinning[tex]
	if t then t.final = final; t.untilT = GetTime() + (delay or 0.25) else face(tex, final) end
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetHandFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(660, 470)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50) -- table windows sit above the main windows
	W.Backdrop(f, C_.felt, C_.gold, 3)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetHandFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetHandFrame")
	f:SetScript("OnShow", function() driver:SetScript("OnUpdate", onUpdate); UI:Refresh() end)
	f:SetScript("OnHide", function() driver:SetScript("OnUpdate", nil) end)

	local mark = W.Logo(f, 300, "BORDER")
	mark:SetPoint("CENTER", -90, -10)
	mark:SetAlpha(0.12)
	local crest = W.Logo(f, 60)
	crest:SetPoint("TOPLEFT", 12, -8)
	self.title = W.Text(f, 18, C_.gold)
	self.title:SetPoint("TOPLEFT", 84, -14)
	self.sub = W.Text(f, 12, C_.text)
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
	self.sub:SetWidth(440)
	self.timer = W.Text(f, 16, C_.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -40, -16)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() return "thugget" end)
	self.rules:SetPoint("TOPRIGHT", -14, -36)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(C_.gold[1], C_.gold[2], C_.gold[3], 0.6)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 14, -62)
	rule:SetPoint("TOPRIGHT", -14, -62)

	-- your five dice (click to hold)
	self.dice = {}
	for i = 1, 5 do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		b:SetSize(68, 68)
		b:SetPoint("TOPLEFT", 24 + (i - 1) * 76, -96)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetPoint("CENTER")
		b.tex:SetSize(60, 60)
		b.tex:SetTexture(D6)
		face(b.tex, nil)
		b.glow = b:CreateTexture(nil, "BACKGROUND")
		b.glow:SetPoint("TOPLEFT", -3, 3)
		b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
		b.glow:SetColorTexture(C_.gold[1], C_.gold[2], C_.gold[3], 0.9)
		b.glow:Hide()
		b.label = W.Text(b, 11, C_.gold, "OUTLINE")
		b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() ns.CardClient:ToggleHold(i) end)
		b:SetScript("OnEnter", function(self)
			if ns.CardClient:CanYRoll() and ns.Client.game.cards.my.rolls >= 1 then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText("Click to hold / release this die", 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		self.dice[i] = b
	end

	self.handName = W.Text(f, 20, C_.gold, "OUTLINE")
	self.handName:SetPoint("TOPLEFT", 26, -196)
	self.handName:SetWidth(380)
	self.handHint = W.Text(f, 11, C_.muted)
	self.handHint:SetPoint("TOPLEFT", self.handName, "BOTTOMLEFT", 0, -4)
	self.handHint:SetWidth(380)

	self.rollBtn = W.Button(f, "ROLL", 180, 40, "gold")
	self.rollBtn:SetPoint("TOPLEFT", 26, -252)
	self.rollBtn:SetScript("OnClick", function() ns.CardClient:YRoll() end)
	self.standBtn = W.Button(f, "STAND", 150, 40)
	self.standBtn:SetPoint("LEFT", self.rollBtn, "RIGHT", 10, 0)
	self.standBtn:SetScript("OnClick", function() ns.CardClient:YStand() end)

	-- hand rankings reminder
	local ranks = W.Text(f, 10, C_.muted)
	ranks:SetPoint("TOPLEFT", 26, -306)
	ranks:SetWidth(380)
	ranks:SetText("HANDS, best first:  Five of a Kind  >  Straight  >  Four of a Kind  >  Full House  >  Small Straight  >  Three of a Kind  >  Pair.  Ties go to the higher dice. No hand scores 0.")

	-- the table
	local panel = W.Panel(f, 222, 360)
	panel:SetPoint("TOPRIGHT", -14, -72)
	W.Backdrop(panel, { 0, 0, 0, 0.35 }, { C_.gold[1], C_.gold[2], C_.gold[3], 0.5 })
	local hdr = W.Text(panel, 11, C_.gold)
	hdr:SetPoint("TOPLEFT", 10, -8)
	hdr:SetText("THE TABLE")
	self.seats = {}
	for i = 1, 8 do
		local r = CreateFrame("Frame", nil, panel)
		r:SetSize(206, 40)
		r:SetPoint("TOPLEFT", 8, -24 - (i - 1) * 42)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
		r.name = W.Text(r, 11, C_.text)
		r.name:SetPoint("TOPLEFT", 6, -4)
		W.Fit(r.name, 120, 1)
		r.status = W.Text(r, 10, C_.muted)
		r.status:SetPoint("TOPRIGHT", -6, -5)
		r.status:SetJustifyH("RIGHT")
		r.status:SetWidth(90)
		r.dice = {}
		for k = 1, 5 do
			local t = r:CreateTexture(nil, "ARTWORK")
			t:SetSize(18, 18)
			t:SetPoint("BOTTOMLEFT", 6 + (k - 1) * 20, 3)
			t:SetTexture(D6)
			face(t, nil)
			r.dice[k] = t
		end
		r.hand = W.Text(r, 10, C_.gold)
		r.hand:SetPoint("BOTTOMRIGHT", -6, 5)
		r.hand:SetJustifyH("RIGHT")
		r.hand:SetWidth(100)
		self.seats[i] = r
	end

	-- result line: under your dice, clear of the table list and the Leave button
	self.banner = W.Text(f, 13, C_.gold, "OUTLINE")
	self.banner:SetPoint("BOTTOMLEFT", 24, 14)
	W.Fit(self.banner, 380, 2)
	self.banner:SetJustifyV("BOTTOM")
	self.leave = W.Button(f, "Leave", 96, 24)
	self.leave:SetPoint("BOTTOMRIGHT", -18, 8)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)

	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, -40)
	self.pop:ClearAllPoints()
	self.pop:SetPoint("CENTER", f, "CENTER", -118, -40) -- over your side, not the table list
end

function UI:Open()
	self:Build()
	if not self.frame:IsShown() then self.frame:Show() end
	self.frame:Raise() -- above the /gt and /gth windows
	self:Refresh()
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

---------------------------------------------------------------------------
-- hooks from CardClient
---------------------------------------------------------------------------
function UI:Spin(mask)
	if not self.frame then return end
	for i, b in ipairs(self.dice) do
		if mask:sub(i, i) ~= "1" then spin(b.tex) end
	end
end

function UI:Land()
	if not self.frame then return end
	local m = ns.Client.game.cards.my
	for i, b in ipairs(self.dice) do settle(b.tex, m.dice[i], 0.15 + i * 0.08) end
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end

function UI:Showdown()
	self:Open()
	local c = ns.Client.game.cards
	local i = 0
	for _, p in ipairs(c.seats) do
		i = i + 1
		local r = self.seats[i]
		if r and c.yshown[p] then
			for k, t in ipairs(r.dice) do spin(t, c.yshown[p][k], 0.5 + i * 0.25 + k * 0.05) end
		end
	end
	self.revealUntil = GetTime() + 0.8 + i * 0.25
	C_Timer.After(0.9 + i * 0.25, function() UI:Refresh() end)
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
function UI:Tick()
	local g = ns.Client.game
	local c = g and g.cards
	if c and c.phase == "roll" and c.deadline then
		local left = math.max(0, math.ceil(c.deadline - GetTime()))
		self.timer:SetText((left <= 10 and "|cffff6161" or "|cffece3cc") .. left .. "s|r")
	else
		self.timer:SetText("")
	end
	self.rollBtn:SetEnabled(ns.CardClient:CanYRoll())
	self.standBtn:SetEnabled(ns.CardClient:CanStand())
	self.turnGlow:Update(ns.ClientUI.MyTurn())
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	local c = g and g.cards
	if not (g and g.type == "thugget" and c) then
		self.title:SetText("Thugget Dice")
		self.sub:SetText("You're not at a Thugget Dice table.")
		self.banner:SetText("")
		for _, r in ipairs(self.seats) do r:Hide() end
		self.rollBtn:Hide(); self.standBtn:Hide(); self.pop:Hide()
		return
	end
	self.title:SetText(("Thugget Dice  %s |cffece3ccante|r   |cff9e948aPot|r %s"):format(ns.Money(g.wager), ns.Money(c.pot > 0 and c.pot or (g.wager * #c.seats))))
	local m = c.my
	local revealing = self.revealUntil and GetTime() < self.revealUntil

	-- status line
	local sub
	if g.phase == "aborted" then sub = "|cffff6161Table cancelled.|r"
	elseif not c.yd then sub = "Waiting for the dice..."
	elseif c.phase == "roll" and m then
		if m.stood then sub = "You're standing. Waiting for the others..."
		elseif m.rolls == 0 then sub = "|cffd9b545Your roll!|r  Click ROLL."
		else sub = ("Roll %d of 3. Click dice to hold them, then roll again or stand."):format(m.rolls) end
	elseif c.phase == "roll" and g.watching then sub = "|cff9e948aWatching|r - the players are rolling..."
	elseif c.phase == "show" or c.phase == "closed" then sub = "Showdown!"
	else sub = "" end
	self.sub:SetText(sub)

	-- my dice
	for i, b in ipairs(self.dice) do
		local held = m and m.held[i] and m.rolls >= 1 and m.rolls < 3 and not m.stood
		b.glow:SetShown(held and true or false)
		b.label:SetText(held and "HELD" or "")
		if m and m.dice[i] and not spinning[b.tex] then face(b.tex, m.dice[i]) end
		b.tex:SetAlpha((m and (m.stood or m.rolls >= 3) and not held) and 1 or 1)
	end
	if m and m.rolls > 0 and not m.pending then
		local _, name = TH.Eval(m.dice)
		self.handName:SetText(name)
		self.handHint:SetText(m.stood and "Final hand" or (3 - m.rolls) .. " roll(s) left")
	else
		self.handName:SetText(m and m.pending and "Rolling..." or "")
		self.handHint:SetText("")
	end
	self.rollBtn:SetText(m and m.rolls >= 1 and ("ROLL AGAIN (" .. (3 - m.rolls) .. ")") or "ROLL")
	-- the buttons only while you can still roll this table
	local seated = ns.IndexOf(c.seats, ns.me) and not g.watching
	local live = seated and g.phase ~= "aborted" and c.phase ~= "show" and c.phase ~= "closed" and not (m and (m.stood or m.rolls >= 3))
	self.rollBtn:SetShown(live and true or false)
	self.standBtn:SetShown(live and true or false)

	-- the table
	local res = c.yres
	for i, r in ipairs(self.seats) do
		local p = c.seats[i]
		if p then
			r:Show()
			local me = p == ns.me
			r.name:SetText(ns.Who(p) .. (me and " |cffd9b545(you)|r" or ""))
			local st = c.yd and c.yd[p]
			local shown = c.yshown and c.yshown[p]
			if shown and not revealing then
				local won = res and res.winners and ns.IndexOf(res.winners, p)
				r.status:SetText(won and "|cff59d959WINNER|r" or "")
				r.hand:SetText(res and res.names[p] or "")
				for k, t in ipairs(r.dice) do if not spinning[t] then face(t, shown[k]) end end
				r.bg:SetColorTexture(1, 1, 1, won and 0.18 or (i % 2 == 0 and 0.04 or 0.08))
			else
				local txt = ""
				if st then txt = st.stood and "|cffd9b545stood|r" or (st.rolls > 0 and ("rolled " .. st.rolls .. "/3") or "rolling...") end
				r.status:SetText(txt)
				r.hand:SetText("")
				if not shown then for _, t in ipairs(r.dice) do if not spinning[t] then face(t, nil) end end end
				r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
			end
		else
			r:Hide()
		end
	end

	-- result
	if res and not revealing then
		local d = c.deltas[ns.me] or 0
		self.banner:SetText(res.summary .. (d ~= 0 and ("   You " .. ns.WonLost(d)) or ""))
		local seated = ns.IndexOf(c.seats, ns.me) and not g.watching
		if g.id and not g.review then self.pop:Play("thugget:" .. g.id, seated and d or nil, res.summary) end
	else
		self.banner:SetText("")
	end
	ns.Client:SetLeaveButton(self.leave, g, g.phase == "playing" and c.phase == "roll")
	self:Tick()
end
