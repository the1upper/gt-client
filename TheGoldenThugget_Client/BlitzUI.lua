-- The Golden Thugget: 31 Blitz table. Opponents across the top (lives as gold
-- coins, their three cards, what they just did), the deck and the discard pile
-- in the middle with the KNOCK button, and your hand along the bottom: click
-- the deck or the pile to draw, then click a card to throw it away.
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.BlitzUI = UI
local K, W = ns.Cards, ns.W
local C_ = W.C
local COIN = ns.MEDIA .. "coin"
local GOLD = { 0.83, 0.69, 0.22 }

local WIN_W, WIN_H = 780, 650
local TILE_W, TILE_H = 180, 96
local PILE_X, PILE_Y = 0, -322       -- pile centre (from the top centre of the window)
local DECK_X = -110
local MY_Y = -518                    -- your cards' centre
local MY_X0, MY_STEP = -138, 92      -- your four card slots

local function tween(...) return ns.CardUI.Tween(...) end
local function NewCard(...) return ns.CardUI.NewCard(...) end

---------------------------------------------------------------------------
-- layout helpers: everything is placed from the window's top centre
---------------------------------------------------------------------------
local function tilePos(i, n)
	-- up to 4 on the first row, the rest on a second row, each row centred
	local row = (i <= 4) and 1 or 2
	local inRow = row == 1 and math.min(n, 4) or (n - 4)
	local k = row == 1 and i or (i - 4)
	local x = (k - (inRow + 1) / 2) * (TILE_W + 10)
	local y = row == 1 and -112 or -212
	return x, y
end

function UI:Build()
	if self.frame then return end
	ns.CardUI:Build() -- the shared card widget and tween driver live there
	local f = CreateFrame("Frame", "GoldenThuggetBlitzFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50)
	W.Backdrop(f, W.C.felt, W.C.gold, 3)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetBlitzFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetBlitzFrame")
	f:SetScript("OnShow", function() UI:Refresh() end)
	f:SetScript("OnUpdate", function() UI:Tick() end)

	local mark = W.Logo(f, 340, "BORDER")
	mark:SetPoint("CENTER", 0, -40)
	mark:SetAlpha(0.12)
	local crest = W.Logo(f, 56)
	crest:SetPoint("TOPLEFT", 16, -8)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 14, -56)
	line:SetPoint("TOPRIGHT", -14, -56)
	line:SetHeight(2)
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
	self.title = W.Text(f, 18, C_.gold)
	self.title:SetPoint("TOPLEFT", 82, -12)
	self.sub = W.Text(f, 12, C_.text)
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
	W.Fit(self.sub, 470, 1)
	self.timer = W.Text(f, 18, C_.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -44, -16)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() return "blitz" end)
	self.rules:SetPoint("TOPRIGHT", -90, -16)

	---------------------------------------------- opponents
	self.tiles = {}
	for i = 1, 7 do
		local t = CreateFrame("Frame", nil, f, "BackdropTemplate")
		t:SetSize(TILE_W, TILE_H)
		W.Backdrop(t, { 0, 0, 0, 0.35 }, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
		t.name = W.Text(t, 12, C_.text)
		t.name:SetPoint("TOPLEFT", 8, -6)
		W.Fit(t.name, 112, 1)
		t.coins = {}
		for k = 1, 3 do
			local c = t:CreateTexture(nil, "ARTWORK")
			c:SetTexture(COIN)
			c:SetTexCoord(0, 0.5, 0, 0.5)
			c:SetSize(15, 15)
			c:SetPoint("TOPRIGHT", -6 - (3 - k) * 16, -5)
			t.coins[k] = c
		end
		t.cards = {}
		for k = 1, 3 do
			local card = NewCard(t, 34, 48)
			card:Home("TOPLEFT", t, "TOPLEFT", 8 + (k - 1) * 38, -24)
			t.cards[k] = card
		end
		t.score = W.Text(t, 13, C_.gold, "OUTLINE")
		t.score:SetPoint("TOPLEFT", 128, -30)
		t.score:SetJustifyH("LEFT")
		W.Fit(t.score, 50, 2)
		t.status = W.Text(t, 10, C_.muted)
		t.status:SetPoint("BOTTOMLEFT", 8, 6)
		W.Fit(t.status, TILE_W - 14, 1)
		t:Hide()
		self.tiles[i] = t
	end

	---------------------------------------------- the middle: deck, pile, knock
	local deck = CreateFrame("Button", nil, f)
	deck:SetSize(64, 90)
	deck:SetPoint("CENTER", f, "TOP", DECK_X, PILE_Y)
	deck.card = NewCard(deck, 64, 90)
	deck.card:Home("CENTER", deck, "CENTER", 0, 0)
	deck.under = NewCard(deck, 64, 90)
	deck.under:Home("CENTER", deck, "CENTER", 3, -3)
	deck.under:SetFrameLevel(deck.card:GetFrameLevel() - 1)
	deck:SetScript("OnClick", function() ns.CardClient:BlitzDraw("deck") end)
	deck:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:SetText("Draw from the deck (only you see it)")
		GameTooltip:Show()
	end)
	deck:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.deck = deck
	self.stock = W.Text(f, 11, C_.muted)
	self.stock:SetPoint("TOP", deck, "BOTTOM", 0, -4)

	local pile = CreateFrame("Button", nil, f)
	pile:SetSize(64, 90)
	pile:SetPoint("CENTER", f, "TOP", PILE_X, PILE_Y)
	pile.under = NewCard(pile, 64, 90)
	pile.under:Home("CENTER", pile, "CENTER", -4, 2)
	pile.card = NewCard(pile, 64, 90)
	pile.card:Home("CENTER", pile, "CENTER", 0, 0)
	pile:SetScript("OnClick", function() ns.CardClient:BlitzDraw("pile") end)
	pile:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:SetText("Take the top card of the pile (everyone sees it)")
		GameTooltip:Show()
	end)
	pile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.pile = pile
	local pileLabel = W.Text(f, 11, C_.muted)
	pileLabel:SetPoint("TOP", pile, "BOTTOM", 0, -4)
	pileLabel:SetText("discard pile")

	self.knock = W.Button(f, "KNOCK", 120, 40, "gold")
	self.knock:SetPoint("CENTER", f, "TOP", 120, PILE_Y)
	self.knock:SetScript("OnClick", function() ns.CardClient:BlitzKnock() end)

	self.action = W.Text(f, 13, C_.text, "OUTLINE")
	self.action:SetPoint("CENTER", f, "TOP", 0, PILE_Y - 70)
	self.action:SetJustifyH("CENTER")
	W.Fit(self.action, 600, 1)

	-- big pop-up words (KNOCK!, BLITZ!)
	local pop = CreateFrame("Frame", nil, f)
	pop:SetSize(400, 80)
	pop:SetPoint("CENTER", f, "TOP", 0, PILE_Y)
	pop:SetFrameLevel(f:GetFrameLevel() + 30)
	pop.text = W.Text(pop, 46, C_.gold, "THICKOUTLINE")
	pop.text:SetPoint("CENTER")
	pop:Hide()
	self.bigWord = pop

	---------------------------------------------- your hand
	self.myLabel = W.Text(f, 15, C_.gold, "OUTLINE")
	self.myLabel:SetPoint("CENTER", f, "TOP", 0, MY_Y + 70)
	self.myLabel:SetJustifyH("CENTER")
	self.myCoins = {}
	for k = 1, 3 do
		local c = f:CreateTexture(nil, "ARTWORK")
		c:SetTexture(COIN)
		c:SetTexCoord(0, 0.5, 0, 0.5)
		c:SetSize(22, 22)
		c:SetPoint("CENTER", f, "TOP", -300 + (k - 1) * 24, MY_Y + 30)
		self.myCoins[k] = c
	end
	self.myLives = W.Text(f, 11, C_.muted)
	self.myLives:SetPoint("CENTER", f, "TOP", -276, MY_Y + 6)
	self.my = {}
	for k = 1, 4 do
		local slot = CreateFrame("Button", nil, f)
		slot:SetSize(76, 106)
		slot:SetPoint("CENTER", f, "TOP", MY_X0 + (k - 1) * MY_STEP, MY_Y)
		slot.card = NewCard(slot, 76, 106)
		slot.card:Home("CENTER", slot, "CENTER", 0, 0)
		slot.x = slot.card:CreateTexture(nil, "OVERLAY")
		slot.x:SetAllPoints()
		slot.x:SetColorTexture(0.8, 0.1, 0.1, 0.35)
		slot.x:Hide()
		slot:SetScript("OnClick", function(b)
			if b.code then ns.CardClient:BlitzDiscard(b.code) end
		end)
		slot:SetScript("OnEnter", function(b)
			if b.code and ns.CardClient:CanThrow(b.code) then
				b.card:Home("CENTER", b, "CENTER", 0, 12)
				b.x:Show()
			end
		end)
		slot:SetScript("OnLeave", function(b)
			b.card:Home("CENTER", b, "CENTER", 0, 0)
			b.x:Hide()
		end)
		self.my[k] = slot
	end
	self.hint = W.Text(f, 12, C_.text)
	self.hint:SetPoint("CENTER", f, "TOP", 300, MY_Y + 6)
	self.hint:SetJustifyH("CENTER")
	W.Fit(self.hint, 150, 3)

	---------------------------------------------- bottom
	self.leave = W.Button(f, "Leave", 96, 24)
	self.leave:SetPoint("BOTTOMRIGHT", -16, 12)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)
	self.banner = W.Text(f, 13, C_.gold, "OUTLINE")
	self.banner:SetPoint("BOTTOMLEFT", 18, 16)
	W.Fit(self.banner, WIN_W - 18 - 16 - 96 - 12, 2)
	self.banner:SetJustifyV("BOTTOM")
	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, -150)
end

function UI:Open()
	self:Build()
	if not self.frame:IsShown() then self.frame:Show() end
	self.frame:Raise()
	self:Refresh()
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local function state()
	local g = ns.Client.game
	local c = g and g.type == "blitz" and g.cards
	return g, c, c and c.bz
end

local function others(g, c)
	local t = {}
	for _, p in ipairs(c.seats or {}) do if p ~= ns.me or g.watching then t[#t + 1] = p end end
	return t
end

local function tileFor(g, c, p)
	for i, q in ipairs(others(g, c)) do if q == p then return UI.tiles[i], i end end
end

-- where a player's cards are (for slides): x, y from the window's top centre
local function seatXY(g, c, p)
	if p == ns.me and not g.watching then return 0, MY_Y end
	local _, i = tileFor(g, c, p)
	if not i then return 0, -60 end
	return tilePos(i, #others(g, c))
end

function UI:Pop(word, r, gg, b)
	local p = self.bigWord
	p.text:SetText(word)
	p.text:SetTextColor(r or GOLD[1], gg or GOLD[2], b or GOLD[3])
	p:Show()
	p:SetAlpha(1)
	tween(0.25, 0, function(e) p:SetScale(0.4 + 0.7 * e) end)
	tween(0.5, 1.3, function(e) p:SetAlpha(1 - e) end, function() p:Hide(); p:SetScale(1) end)
end

---------------------------------------------------------------------------
-- events from CardClient
---------------------------------------------------------------------------
function UI:Deal()
	local g, c, b = state()
	if not b then return end
	self:Open()
	self:Refresh()
	local delay = 0
	for i, p in ipairs(others(g, c)) do
		local t = self.tiles[i]
		if t and ns.IndexOf(c.alive, p) then
			local x, y = tilePos(i, #others(g, c))
			for k = 1, 3 do
				t.cards[k]:Set(nil)
				t.cards[k]:SlideFrom(DECK_X - x, PILE_Y - y, delay)
				delay = delay + 0.04
			end
		end
	end
	if b.my then
		for k = 1, 3 do
			local card = self.my[k].card
			card:Set(nil)
			card:SlideFrom(DECK_X - (MY_X0 + (k - 1) * MY_STEP), PILE_Y - MY_Y, delay)
			card:FlipTo(b.my[k], delay + 0.4)
			delay = delay + 0.06
		end
	end
	self.pile.card:Set(b.pile[#b.pile])
	self.pile.card:SlideFrom(DECK_X - PILE_X, 0, delay + 0.1)
end

function UI:Drew(p, src, code)
	local g, c, b = state()
	if not (b and self.frame and self.frame:IsShown()) then return end
	self:Refresh()
	local fromX = src == "pile" and PILE_X or DECK_X
	if p == ns.me and not g.watching and b.my then
		local k = #b.my
		local slot = self.my[k]
		if slot then
			slot.card:Set(src == "pile" and code or nil)
			slot.card:SlideFrom(fromX - (MY_X0 + (k - 1) * MY_STEP), PILE_Y - MY_Y, 0)
			if src ~= "pile" then slot.card:FlipTo(code, 0.35) end
		end
	else
		local x, y = seatXY(g, c, p)
		local fly = self.flyer or NewCard(self.frame, 34, 48)
		self.flyer = fly
		fly:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		fly:Set(src == "pile" and code or nil)
		fly:Show()
		tween(0.35, 0, function(e)
			fly:ClearAllPoints()
			fly:SetPoint("CENTER", self.frame, "TOP", fromX + (x - fromX) * e, PILE_Y + (y - PILE_Y) * e)
		end, function() fly:Hide() end)
		ns.Sound.Play("card_deal")
	end
end

function UI:Threw(p, code)
	local g, c, b = state()
	if not (b and self.frame and self.frame:IsShown()) then return end
	local x, y = seatXY(g, c, p)
	self.pile.card:Set(code)
	self.pile.card:SlideFrom(x - PILE_X, y - PILE_Y, 0)
	self:Refresh()
end

function UI:Knocked(p)
	if not (self.frame and self.frame:IsShown()) then return end
	ns.Sound.Play("knock")
	self:Pop("KNOCK!", 1, 0.85, 0.3)
	self:Refresh()
end

function UI:Reveal()
	local g, c, b = state()
	if not (b and b.show and self.frame and self.frame:IsShown()) then return end
	self:Refresh()
	local delay = 0
	for i, p in ipairs(others(g, c)) do
		local t = self.tiles[i]
		local h = b.show.hands[p]
		if t and h then
			for k = 1, 3 do t.cards[k]:FlipTo(h[k], delay); delay = delay + 0.05 end
		end
	end
	local s = b.show
	if s.reason == "blitz" then
		C_Timer.After(0.4, function() UI:Pop("BLITZ!", 1, 0.3, 0.3); ns.Sound.Play("jackpot") end)
	end
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
function UI:Tick()
	local g, c, b = state()
	if not (self.frame and b) then
		if self.timer then self.timer:SetText("") end
		return
	end
	local t = b.turn
	if t and t.deadline and c.phase == "blitz" then
		local left = math.max(0, math.ceil(t.deadline - GetTime()))
		self.timer:SetText((left <= 5 and "|cffff6161" or "|cffece3cc") .. left .. "s|r")
	else
		self.timer:SetText("")
	end
	self.turnGlow:Update(ns.ClientUI.MyTurn())
	-- the deck and pile glow when you can draw
	local stage = ns.CardClient:BlitzStage()
	local pulse = 0.55 + 0.45 * math.sin(GetTime() * 5)
	self.deck.card.glow:SetShown(stage == "draw")
	self.pile.card.glow:SetShown(stage == "draw" and #b.pile > 0)
	self.deck.card.glow:SetAlpha(pulse)
	self.pile.card.glow:SetAlpha(pulse)
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local g, c, b = state()
	if not c then
		self.title:SetText("31 Blitz")
		self.sub:SetText("You're not at a 31 Blitz table.")
		for _, t in ipairs(self.tiles) do t:Hide() end
		self.knock:Hide()
		self.banner:SetText("")
		self.leave:SetEnabled(false)
		self.pop:Hide()
		return
	end
	ns.Client:SetLeaveButton(self.leave, g, g.phase == "open")
	local lives0 = tonumber(g.param) or 3
	self.title:SetText((ns.TestTag(g) .. "31 Blitz  %s |cffaaaaaaante|r   Pot %s   |cffaaaaaa%d %s each|r"):format(
		ns.Money(g.wager or 0), ns.Money(c.pot or 0), lives0, lives0 == 1 and "life" or "lives"))
	local t = b and b.turn
	local stage = ns.CardClient:BlitzStage()
	-- status line
	local sub
	if c.phase == "closed" or g.phase == "done" then sub = "Finished"
	elseif not b then sub = "Dealing..."
	elseif c.phase == "show" then sub = ("Round %d - hands shown"):format(c.round)
	elseif stage == "draw" then sub = "|cffd9b545Your turn:|r draw from the deck or the pile" .. (b.knocker and "" or ", or KNOCK")
	elseif stage == "discard" then sub = "|cffd9b545Throw one card away|r (click it)"
	elseif t then sub = ("Round %d - %s is %s..."):format(c.round, ns.Who(t.p), t.stage == "draw" and "drawing" or "discarding")
	else sub = ("Round %d"):format(c.round) end
	if b and b.knocker and c.phase == "blitz" then sub = sub .. ("   |cffffd100%s knocked|r"):format(ns.Short(b.knocker)) end
	self.sub:SetText(sub)

	-- opponents
	local list = others(g, c)
	local alive = {}
	for _, p in ipairs(c.alive or {}) do alive[p] = true end
	local show = b and b.show
	for i, tile in ipairs(self.tiles) do
		local p = list[i]
		if p then
			tile:Show()
			local x, y = tilePos(i, #list)
			tile:ClearAllPoints()
			tile:SetPoint("CENTER", self.frame, "TOP", x, y)
			tile.name:SetText(ns.Who(p))
			local n = (c.lives or {})[p] or 0
			for k = 1, 3 do
				tile.coins[k]:SetShown(k <= lives0)
				tile.coins[k]:SetDesaturated(k > n)
				tile.coins[k]:SetAlpha(k > n and 0.25 or 1)
			end
			local inRound = b and (show and show.hands[p] or (alive[p] and b.pile))
			local h = show and show.hands[p]
			for k = 1, 3 do
				local card = tile.cards[k]
				if not inRound then card:Hide() else
					card:Show()
					if h then
						if not card.flipping and card.code ~= h[k] then card:Set(h[k]) end
					elseif not card.flipping and card.code then card:Set(nil) end
				end
			end
			-- what they're doing / did
			local st = ""
			local lost = show and show.losses[p]
			if c.winner == p then st = "|cffffd100WINNER|r"
			elseif n == 0 and not (show and show.hands[p]) then st = "|cff888888out|r"
			elseif t and t.p == p then st = "|cffffd100" .. (t.stage == "draw" and "thinking..." or "discarding...") .. "|r"
			elseif b and b.acts[p] then st = b.acts[p] end
			if lost then st = (lost >= 99 and "|cffff6161out|r" or ("|cffff6161-" .. lost .. (lost == 1 and " life" or " lives") .. "|r")) .. (n == 0 and "  |cff888888(out)|r" or "") end
			if b and b.knocker == p and c.phase == "blitz" then st = "|cffffd100KNOCKED|r  " .. st end
			tile.status:SetText(st)
			if h then
				local sc = K.BlitzScore(h)
				tile.score:SetText((sc == 62 and "|cffff6161" or "") .. K.BlitzText(sc) .. (sc == 62 and "|r" or ""))
			else
				tile.score:SetText("")
			end
			local mine = t and t.p == p
			tile:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], (mine or c.winner == p) and 1 or 0.35)
			tile:SetAlpha((n == 0 and not h) and 0.5 or 1)
		else
			tile:Hide()
		end
	end

	-- deck and pile
	local inPlay = b and c.phase ~= "closed"
	self.deck:SetShown(inPlay and true or false)
	self.pile:SetShown(inPlay and true or false)
	if b then
		self.stock:SetText(b.stock and (b.stock .. " left") or "")
		local top = b.pile[#b.pile]
		local under = b.pile[#b.pile - 1]
		if top then
			if not self.pile.card.flipping and self.pile.card.code ~= top then self.pile.card:Set(top) end
			self.pile.card:Show()
		else self.pile.card:Hide() end
		if under then self.pile.under:Set(under); self.pile.under:Show() else self.pile.under:Hide() end
		self.deck:SetEnabled(stage == "draw")
		self.pile:SetEnabled(stage == "draw" and top ~= nil)
	end
	self.knock:SetShown(stage == "draw" and not (b and b.knocker))
	self.knock:SetEnabled(ns.CardClient:CanKnock())

	-- last thing that happened
	local act = ""
	if show then
		if show.again then act = "Everyone would be out - the round is replayed."
		elseif show.reason == "blitz" then act = ns.Who(show.who) .. " |cffff6161BLITZ - 31!|r Everyone else loses a life."
		elseif show.reason == "deck" then act = "The deck ran out - hands are shown."
		else act = ns.Who(show.who) .. " knocked." end
	elseif b and t and t.p ~= ns.me and b.acts[t.p] then
		act = ns.Who(t.p) .. " " .. b.acts[t.p]
	end
	self.action:SetText(act)

	-- your hand
	local seated = not g.watching and ns.IndexOf(c.seats, ns.me)
	local my = b and b.my
	local myLives = (c.lives or {})[ns.me] or 0
	for k = 1, 3 do
		self.myCoins[k]:SetShown(seated and k <= lives0 and true or false)
		self.myCoins[k]:SetDesaturated(k > myLives)
		self.myCoins[k]:SetAlpha(k > myLives and 0.25 or 1)
	end
	self.myLives:SetText(seated and ("%d %s left"):format(myLives, myLives == 1 and "life" or "lives") or "")
	for k = 1, 4 do
		local slot = self.my[k]
		local code = my and my[k]
		slot.code = code
		if code and seated then
			slot:Show()
			if not slot.card.flipping and slot.card.code ~= code and slot.card.code ~= nil then slot.card:Set(code)
			elseif not slot.card.flipping and slot.card.code == nil and not slot.card.tweening then slot.card:Set(code) end
			local canThrow = ns.CardClient:CanThrow(code)
			slot:SetEnabled(canThrow)
			slot.card.glow:SetShown(stage == "discard" and canThrow)
			slot.card:SetAlpha((stage == "discard" and not canThrow) and 0.7 or 1)
		else
			slot:Hide()
		end
	end
	if my and seated then
		local sc, name = K.BlitzScore(my)
		if #my == 4 then
			-- holding four: show what you'd keep at best
			local best, bestName = -1, ""
			for k = 1, 4 do
				local three = {}
				for j = 1, 4 do if j ~= k then three[#three + 1] = my[j] end end
				local s3, n3 = K.BlitzScore(three)
				if s3 > best then best, bestName = s3, n3 end
			end
			self.myLabel:SetText("Best keep: " .. bestName)
		else
			self.myLabel:SetText(name)
		end
	elseif seated and myLives == 0 then
		self.myLabel:SetText("|cffff6161You're out|r")
	else
		self.myLabel:SetText(g.watching and "|cffaaaaaaWatching|r" or "")
	end
	local hint = ""
	if stage == "draw" then hint = "Click the |cffd9b545deck|r or the |cffd9b545pile|r" .. (b.knocker and "" or ", or KNOCK")
	elseif stage == "discard" then hint = "Click a card to throw it away" end
	self.hint:SetText(hint)

	-- result
	if c.phase == "closed" or g.phase == "done" then
		local mine = c.deltas and c.deltas[ns.me]
		self.banner:SetText((c.winner and (ns.Who(c.winner) .. " takes the pot!") or "Table closed.") .. (seated and mine and mine ~= 0 and ("   You " .. ns.WonLost(mine)) or ""))
		if g.id and not g.review and seated then self.pop:Play("table:" .. g.id, mine or 0, c.winner and (ns.Who(c.winner) .. " wins") or "") end
	else
		self.banner:SetText("")
	end
	self:Tick()
end

function UI:Init() end
