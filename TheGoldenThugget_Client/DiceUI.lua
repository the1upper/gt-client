-- The Golden Thugget: dice table window. You click Roll, the die spins, the
-- number lands, and every roll at the table is listed. Outcomes are fixed by
-- the sealed rolls; the click is when *your* sealed roll is revealed (High Roll /
-- High-Low) or when your turn's roll is shown (Death Roll).
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.DiceUI = UI
local W = ns.W
local C_ = W.C

local ROW_STEP = 0.55   -- seconds between rows landing (High Roll / High-Low)
local SPIN_TIME = 1.1   -- spin before a Death Roll number lands
local ROWS = 10

---------------------------------------------------------------------------
-- animation driver
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local anim = { spinning = false, angle = 0, flick = 0, pop = 0 }

local function rnd(max) return math.random(1, math.max(1, max or 100)) end

local function onUpdate(_, dt)
	if not UI.frame or not UI.frame:IsShown() then return end
	if UI.coinMode then UI:CoinUpdate(dt) end
	if anim.spinning then
		anim.angle = anim.angle + dt * (anim.slow and 5 or 13)
		UI.die:SetRotation(anim.angle)
		anim.flick = anim.flick + dt
		if anim.flick > 0.06 then
			anim.flick = 0
			local n = rnd(anim.max)
			UI.number:SetText(n)
			UI.faceNum:SetText(n)
		end
	end
	if anim.pop > 0 then
		anim.pop = math.max(0, anim.pop - dt * 2.5)
		UI.numberHolder:SetScale(1 + 0.45 * anim.pop)
	end
	-- rows still "in the air" flicker too
	for i, row in ipairs(UI.rows) do
		if row.flicking and row:IsShown() then
			row.flickT = (row.flickT or 0) + dt
			if row.flickT > 0.07 then row.flickT = 0; row.val:SetText(rnd(row.max)) end
		end
	end
	UI:Tick()
end

local function spin(max)
	if not anim.spinning then ns.Sound.Play("dice_roll") end
	anim.spinning, anim.slow, anim.max = true, false, max
	UI.range:SetText("1 - " .. (max or "?"))
end

local function land(value, max)
	anim.spinning = false
	anim.angle = 0
	UI.die:SetRotation(0)
	UI.number:SetText(value)
	UI.faceNum:SetText(value)
	UI.range:SetText("1 - " .. max)
	anim.pop = 1
	ns.Sound.Play("dice_land")
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetDiceFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(600, 440)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50) -- table windows sit above the main windows
	W.Backdrop(f, C_.felt, C_.gold, 3)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetDiceFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetDiceFrame")
	f:SetScript("OnShow", function() driver:SetScript("OnUpdate", onUpdate); UI:Refresh() end)
	f:SetScript("OnHide", function() driver:SetScript("OnUpdate", nil) end)

	local mark = W.Logo(f, 300, "BORDER")
	mark:SetPoint("CENTER", 0, -20)
	mark:SetAlpha(0.13)
	local crest = W.Logo(f, 60)
	crest:SetPoint("TOPLEFT", 12, -8)
	self.title = W.Text(f, 18, C_.gold)
	self.title:SetPoint("TOPLEFT", 84, -14)
	self.sub = W.Text(f, 12, C_.text)
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
	self.sub:SetWidth(420)
	self.timer = W.Text(f, 16, C_.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -40, -16)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() local g = ns.Client.game; return g and g.type end)
	self.rules:SetPoint("TOPRIGHT", -14, -36)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(C_.gold[1], C_.gold[2], C_.gold[3], 0.6)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 14, -62)
	rule:SetPoint("TOPRIGHT", -14, -62)

	-- the die
	local dieHolder = CreateFrame("Frame", nil, f)
	self.dieHolder = dieHolder
	dieHolder:SetSize(150, 150)
	dieHolder:SetPoint("TOPLEFT", 70, -78)
	self.die = dieHolder:CreateTexture(nil, "ARTWORK")
	self.die:SetAllPoints()
	self.die:SetTexture(ns.MEDIA .. "die")
	self.faceNum = W.Text(dieHolder, 17, { 0.25, 0.15, 0.02 })
	self.faceNum:SetPoint("CENTER", 0, -6)
	self.faceNum:SetJustifyH("CENTER")

	local nh = CreateFrame("Frame", nil, f)
	nh:SetSize(240, 56)
	nh:SetPoint("TOP", dieHolder, "BOTTOM", 0, -6)
	self.numberHolder = nh
	self.number = W.Text(nh, 44, C_.gold, "THICKOUTLINE")
	self.number:SetPoint("CENTER")
	self.number:SetJustifyH("CENTER")
	self.range = W.Text(f, 12, C_.text)
	self.range:SetPoint("TOP", nh, "BOTTOM", 0, -2)
	self.range:SetJustifyH("CENTER")

	self.rollBtn = W.Button(f, "ROLL", 180, 40, "gold")
	self.rollBtn:SetPoint("TOP", self.range, "BOTTOM", 0, -10)
	self.rollBtn:SetScript("OnClick", function() ns.Client:Roll() end)

	-- rolls list
	local panel = W.Panel(f, 260, 300)
	self.panel = panel
	panel:SetPoint("TOPRIGHT", -16, -74)
	W.Backdrop(panel, { 0, 0, 0, 0.35 }, { C_.gold[1], C_.gold[2], C_.gold[3], 0.5 })
	local hdr = W.Text(panel, 11, C_.gold)
	hdr:SetPoint("TOPLEFT", 10, -8)
	hdr:SetText("ROLLS")
	self.rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Frame", nil, panel)
		r:SetSize(244, 26)
		r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 27)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
		r.name = W.Text(r, 12, C_.text)
		r.name:SetPoint("LEFT", 8, 0)
		W.Fit(r.name, 120, 1)
		r.val = W.Text(r, 16, C_.gold, "OUTLINE")
		r.val:SetPoint("RIGHT", -80, 0)
		r.val:SetJustifyH("RIGHT")
		r.tag = W.Text(r, 10, C_.muted)
		r.tag:SetPoint("RIGHT", -6, 0)
		r.tag:SetJustifyH("RIGHT")
		r.tag:SetWidth(74)
		self.rows[i] = r
	end

	-- result line: inside the window, left of the Leave/Close button, 2 lines max
	self.leave = W.Button(f, "Leave", 96, 24)
	self.leave:SetPoint("BOTTOMRIGHT", -16, 14)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)
	self.banner = W.Text(f, 13, C_.gold, "OUTLINE")
	self.banner:SetPoint("BOTTOMLEFT", 18, 12)
	W.Fit(self.banner, 600 - 18 - 16 - 96 - 12, 2)
	self.banner:SetJustifyV("BOTTOM")

	self:BuildCoin(f)
	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, -130)
end

local function slotsTable()
	local g = ns.Client and ns.Client.game
	return g and g.type == "slots" and ns.SlotsUI
end

function UI:Open()
	if slotsTable() then return ns.SlotsUI:Open() end
	self:Build()
	if not self.frame:IsShown() then self.frame:Show() end
	self.frame:Raise() -- above the /gt and /gth windows
	self:Refresh()
end

function UI:Toggle()
	if slotsTable() then return ns.SlotsUI:Toggle() end
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

---------------------------------------------------------------------------
-- per-table display state
---------------------------------------------------------------------------
local function sync(g)
	if UI.gameId ~= g.id then
		UI.gameId = g.id
		UI.revealed = 0       -- rolls whose numbers have landed
		UI.animating = false
		anim.spinning, anim.pop = false, 0
		if UI.frame then
			UI.die:SetRotation(0)
			UI.number:SetText("?")
			UI.faceNum:SetText("")
			UI.range:SetText("")
		end
		UI:CoinReset(g)
		-- reopening a finished table (Review): everything has landed already
		local d = g.dice
		if d and d.done and #d.rolls > 0 then
			UI.revealed = #d.rolls
			local show = d.rolls[#d.rolls]
			for _, r in ipairs(d.rolls) do if r.p == ns.me and not r.tie and g.type ~= "deathroll" then show = r break end end
			if UI.frame then
				UI.number:SetText(show.r)
				UI.faceNum:SetText(show.r)
				UI.range:SetText("1 - " .. show.max)
			end
		end
	end
end

-- Your Roll click: spin until the result arrives
function UI:Shake()
	local g = ns.Client.game
	if not (g and self.frame) then return end
	sync(g)
	local d = g.dice
	local max = (d and d.turn and d.rolls[d.turn] and d.rolls[d.turn].max) or g.param
	spin(max)
	anim.slow = false
end

-- High Roll / High-Low: everyone's numbers land one after another. Returns duration.
function UI:RevealAll()
	local g = ns.Client.game
	if not g or not g.dice then return 0 end
	self:Open()
	sync(g)
	local rolls = g.dice.rolls
	if #rolls == 0 then self:Refresh(); return 0.5 end
	self.animating = true
	spin(g.param)
	local mineAt
	for i, r in ipairs(rolls) do
		local t = 0.5 + i * ROW_STEP
		if r.p == ns.me and not r.tie then mineAt = mineAt or i end
		C_Timer.After(t, function()
			if UI.gameId ~= g.id then return end
			UI.revealed = math.max(UI.revealed, i)
			if i == (mineAt or #rolls) then land(r.r, r.max) end
			UI:Refresh()
		end)
	end
	local total = 0.5 + #rolls * ROW_STEP + 0.4
	C_Timer.After(total, function()
		if UI.gameId ~= g.id then return end
		UI.animating = false
		if anim.spinning then local r = rolls[mineAt or #rolls]; land(r.r, r.max) end
		UI:Refresh()
	end)
	self:Refresh()
	return total
end

-- Your High Roll / High-Low number lands
function UI:Land(value, max)
	local g = ns.Client.game
	if not (g and self.frame) then return end
	self:Open()
	sync(g)
	land(value, max)
	self:Refresh()
end

-- After everyone has rolled: tie-break rolls land one by one. Returns duration.
function UI:RevealTies()
	local g = ns.Client.game
	local d = g and g.dice
	if not (d and d.landed) then return 0 end
	local t, any = 0.3, false
	for i, r in ipairs(d.rolls) do
		if r.tie and not d.landed[i] then
			any = true
			t = t + ROW_STEP
			C_Timer.After(t, function()
				if UI.gameId ~= g.id then return end
				d.landed[i] = true
				if r.p == ns.me and UI.frame then land(r.r, r.max) end
				UI:Refresh()
			end)
		end
	end
	if any and self.frame then spin(g.param) end
	self:Refresh()
	return any and t + 0.4 or 0
end

-- Death Roll: roll k lands (after a short spin). Returns duration.
function UI:ShowRoll(k)
	local g = ns.Client.game
	local d = g and g.dice
	if not d or not d.rolls[k] then return 0 end
	self:Open()
	sync(g)
	if self.revealed < k - 1 then self.revealed = k - 1 end -- missed ones appear at once
	local r = d.rolls[k]
	self.animating = true
	spin(r.max)
	C_Timer.After(SPIN_TIME, function()
		if UI.gameId ~= g.id then return end
		UI.revealed = math.max(UI.revealed, k)
		UI.animating = false
		land(r.r, r.max)
		UI:Refresh()
	end)
	self:Refresh()
	return SPIN_TIME + 0.4
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
function UI:Tick()
	local g = ns.Client.game
	if not g then return self.timer:SetText("") end
	local deadline
	if g.awaitRoll then deadline = g.rollDeadline
	elseif g.awaitCall then deadline = g.callDeadline
	elseif g.dice and g.dice.turn and not g.dice.done then deadline = g.dice.deadline end
	if deadline then
		local left = math.max(0, math.ceil(deadline - GetTime()))
		self.timer:SetText((left <= 5 and "|cffff6161" or "|cffece3cc") .. left .. "s|r")
	else
		self.timer:SetText("")
	end
	self.rollBtn:SetEnabled(ns.Client:CanRoll())
	self.turnGlow:Update(ns.ClientUI.MyTurn())
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	if not g or ns.Games.types[g.type].kind == "cards" then
		self.title:SetText("The Golden Thugget")
		self.sub:SetText("You're not at a dice table.")
		self.banner:SetText("")
		self.leave:SetEnabled(false)
		for _, r in ipairs(self.rows) do r:Hide() end
		self.rollBtn:SetEnabled(false)
		self.rollBtn:Hide()
		self.pop:Hide()
		self:SetCoinMode(false)
		return
	end
	sync(g)
	ns.Client:SetLeaveButton(self.leave, g, g.phase == "open")
	local def = ns.Games.types[g.type]
	local extra = ""
	if g.type == "highlow" and g.wager and g.wager > 0 then
		extra = "  |cff9e948a" .. ns.Money(ns.Games.HighLowUnit(g.wager)) .. "|cff9e948a a point|r"
	end
	self.title:SetText(("%s  %s%s"):format(def.name, ns.Money(g.wager or 0), extra))
	local d = g.dice
	local rolls = d and d.rolls or {}
	-- ROLL only while it can matter to you: gone once the table is over or if you're watching
	local seated = ns.IndexOf(g.players or {}, ns.me) and not g.watching
	self.rollBtn:SetShown((seated and not (d and d.done) and g.phase ~= "aborted" and g.type ~= "coinflip") and true or false)

	-- status line
	local sub
	if g.phase == "aborted" then sub = "|cffff6161Table cancelled.|r"
	elseif g.awaitRoll then sub = "|cffd9b545Your roll!|r  Click ROLL."
	elseif g.phase == "open" then sub = "Waiting for the house to start..."
	elseif g.phase == "commit" then sub = "Sealing rolls..."
	elseif g.phase == "reveal" and not d then sub = "Shuffling..."
	elseif d and d.landed and not d.tiesShown then
		sub = d.landedBy[ns.me] and "Waiting for the others to roll..." or (ns.IndexOf(g.players, ns.me) and "Rolling..." or "Players are rolling...")
	elseif d and d.landed and not d.done then sub = "Tie! Rolling again..."
	elseif d and d.turn and not d.done then
		local r = rolls[d.turn]
		sub = r.p == ns.me and ("|cffd9b545Your roll!|r  1 - " .. r.max) or (ns.Who(r.p) .. " is rolling (1 - " .. r.max .. ")...")
	elseif d and not d.done then sub = "Rolling..."
	elseif d and d.done then sub = "Finished"
	else sub = "" end
	self.sub:SetText(sub)
	if not anim.spinning and self.revealed == 0 and not g.awaitRoll then
		local max = (d and d.turn and rolls[d.turn] and rolls[d.turn].max) or g.param
		self.range:SetText(max and ("1 - " .. max) or "")
	end

	-- Coin Flip has its own stage (coin + two player plates) instead of the die and rows
	local coin = g.type == "coinflip"
	self:SetCoinMode(coin)
	if coin then self:CoinRefresh(g) end
	if coin and not g.awaitCall then
		if g.phase == "commit" then
			local caller = g.players and g.players[ns.Games.CoinCaller(g)]
			self.sub:SetText(caller and (ns.Who(caller) .. " is calling it...") or "")
		elseif g.phase == "reveal" and not d then self.sub:SetText("The call is sealed. Flipping...")
		elseif d and not d.done then self.sub:SetText("Flipping...")
		elseif d and d.done then self.sub:SetText("Finished") end
	elseif coin and g.awaitCall then
		self.sub:SetText("|cffd9b545Your call!|r  Heads or tails?")
	end

	-- rows
	local items = {}
	if not d then
		-- before results: who has rolled
		for _, p in ipairs(g.players or {}) do
			local rolled = (g.rolledSet and g.rolledSet[p]) or (p == ns.me and g.awaitRoll == false)
			items[#items + 1] = { name = p, val = rolled and "" or "...", tag = rolled and "|cff59d959rolled|r" or "waiting", muted = not rolled }
		end
	elseif g.type == "deathroll" then
		-- newest first. The roller's "..." row stays on top through the spin and
		-- turns into their number in the same spot when it lands.
		local landed = math.min(self.revealed, #rolls)
		local pending = d.turn or ((d.shown or 0) > landed and landed + 1) or nil
		if pending and rolls[pending] and (not d.done or self.animating) then
			items[1] = { name = rolls[pending].p, val = "...", tag = d.turn and "up next" or "rolling", muted = true }
		end
		for k = landed, 1, -1 do
			local r = rolls[k]
			items[#items + 1] = { name = r.p, val = r.r, tag = "of " .. r.max, lose = r.r == 1, newest = k == self.revealed }
		end
	elseif d.landed then
		-- each player's number shows as they roll; tie-breaks after everyone has
		for i, r in ipairs(rolls) do
			local landed = d.landed[i]
			if r.tie then
				if d.tiesShown then
					items[#items + 1] = { name = r.p, val = landed and r.r or nil, max = r.max, flick = not landed, tag = "tie-break" }
				end
			else
				items[#items + 1] = { name = r.p, val = landed and r.r or "...", muted = not landed, tag = landed and "" or "rolling" }
			end
		end
	else
		for i, r in ipairs(rolls) do
			local landed = i <= self.revealed
			local tag = r.tie and "tie-break" or ""
			items[#items + 1] = { name = r.p, val = landed and r.r or nil, max = r.max, flick = not landed, tag = tag }
		end
	end
	for i, row in ipairs(self.rows) do
		local it = items[i]
		if it then
			row:Show()
			local me = it.name == ns.me
			row.name:SetText(ns.Who(it.name) .. (me and " |cffd9b545(you)|r" or ""))
			row.flicking, row.max = it.flick, it.max
			if not it.flick then row.val:SetText(it.val or "") end
			if it.lose then row.val:SetTextColor(C_.red[1], C_.red[2], C_.red[3])
			elseif it.muted then row.val:SetTextColor(C_.muted[1], C_.muted[2], C_.muted[3])
			else row.val:SetTextColor(C_.gold[1], C_.gold[2], C_.gold[3]) end
			row.tag:SetText(it.tag or "")
			row.bg:SetColorTexture(1, 1, 1, it.newest and 0.16 or (i % 2 == 0 and 0.04 or 0.08))
			row.name:SetAlpha(1)
			row.val:SetAlpha(1)
		else
			row:Hide()
			row.flicking = false
		end
	end

	-- result banner (after the last number lands)
	local res = g.result
	if res and d and (d.done or (g.type ~= "deathroll" and g.type ~= "coinflip" and not self.animating and self.revealed >= #rolls)) then
		local delta = ns.IndexOf(g.players, ns.me) and not g.watching and (g.delta or 0) or nil
		self.banner:SetText((res.summary or "") .. (delta and delta ~= 0 and ("   You " .. ns.WonLost(delta)) or ""))
		-- each player's result next to their (first) roll; winners lit gold, losers dimmed
		local net, done = ns.Games.Net(g, res), {}
		for i, row in ipairs(self.rows) do
			local it = items[i]
			if it and it.name and not it.flick and not done[it.name] and net[it.name] and net[it.name] ~= 0 then
				done[it.name] = true
				local won = net[it.name] > 0
				row.tag:SetText(won and ("|cff59d959+|r" .. ns.Money(net[it.name])) or ("|cffff6161-|r" .. ns.Money(-net[it.name])))
				row.bg:SetColorTexture(won and C_.gold[1] or 1, won and C_.gold[2] or 1, won and C_.gold[3] or 1, won and 0.28 or 0.03)
				row.name:SetAlpha(won and 1 or 0.7)
				row.val:SetAlpha(won and 1 or 0.7)
			end
		end
		if g.id and not g.review then self.pop:Play("dice:" .. g.id, delta, res.summary) end
	else
		self.banner:SetText("")
	end
	self:Tick()
end

function UI:Init() end

---------------------------------------------------------------------------
-- Coin Flip: a gold coin that hovers while the call is made, then is tossed
-- end over end (its height squashes with the turn, the rim shows as it goes
-- edge-on), arcs toward you and back, hits the felt, hops twice, wobbles flat
-- and lands on the sealed result with a flash of sparkles.
---------------------------------------------------------------------------
local COIN = 128        -- coin size on the felt
local THICK = 9         -- rim thickness when edge-on
local REST_Y = -128     -- coin centre below the top of the stage
local SPARKS = 10
local TC = {            -- coin.tga atlas
	H = { 0, 0.5, 0, 0.5 }, T = { 0.5, 1, 0, 0.5 },
	shadow = { 0, 0.5, 0.5, 0.75 }, spark = { 0.5, 0.75, 0.5, 0.75 }, glow = { 0.75, 1, 0.5, 0.75 },
}
-- the toss (seconds from the click of the thumb)
local WIND, FLIGHT, HOP1, HOP2, SETTLE = 0.22, 2.3, 0.3, 0.17, 0.85
local LAND_AT = WIND + FLIGHT
local REST_AT = LAND_AT + HOP1 + HOP2 + SETTLE
UI.FLIP_TIME = REST_AT + 0.9 -- then the result

local coin = { mode = "idle", theta = 0, t0 = 0 }

local function tex(parent, layer, region, blend)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(ns.MEDIA .. "coin")
	local r = TC[region]
	t:SetTexCoord(r[1], r[2], r[3], r[4])
	if blend then t:SetBlendMode(blend) end
	return t
end

local function plate(parent, side)
	local p = W.Panel(parent, 150, 74)
	p:SetPoint(side == 1 and "LEFT" or "RIGHT", side == 1 and 22 or -22, -10)
	p.name = W.Text(p, 13, C_.text)
	p.name:SetPoint("TOP", 0, -10)
	p.name:SetJustifyH("CENTER")
	W.Fit(p.name, 138, 1)
	p.side = W.Text(p, 15, C_.gold, "OUTLINE")
	p.side:SetPoint("TOP", p.name, "BOTTOM", 0, -6)
	p.side:SetJustifyH("CENTER")
	p.side:SetWidth(140)
	p.amt = W.Text(p, 12, C_.muted)
	p.amt:SetPoint("TOP", p.side, "BOTTOM", 0, -4)
	p.amt:SetJustifyH("CENTER")
	p.amt:SetWidth(140)
	return p
end

function UI:BuildCoin(f)
	local st = CreateFrame("Frame", nil, f)
	st:SetPoint("TOPLEFT", 0, -64)
	st:SetPoint("TOPRIGHT", 0, -64)
	st:SetHeight(310)
	st:Hide()
	self.coinStage = st

	self.coinShadow = tex(st, "BACKGROUND", "shadow")
	self.coinGlow = tex(st, "BORDER", "glow", "ADD")
	self.coinGlow:SetSize(COIN * 2.4, COIN * 2.4)
	self.coinGlow:SetPoint("CENTER", st, "TOP", 0, REST_Y)
	self.coinGlow:SetAlpha(0)
	-- the rim (seen edge-on) sits behind the face
	-- (darkened copies of the coin stacked under the face: its thickness)
	self.coinEdges = {}
	for i = 1, 3 do
		local e = tex(st, "ARTWORK", "H")
		e:SetDrawLayer("ARTWORK", i - 1)
		local k = 0.62 - 0.1 * i
		e:SetVertexColor(k, k * 0.72, k * 0.22)
		self.coinEdges[i] = e
	end
	self.coinFace = tex(st, "ARTWORK", "H")
	self.coinFace:SetDrawLayer("ARTWORK", 3)
	self.coinShine = tex(st, "ARTWORK", "glow", "ADD")
	self.coinShine:SetDrawLayer("ARTWORK", 4)
	self.coinShine:SetAlpha(0)
	self.sparks = {}
	for i = 1, SPARKS do
		local sp = tex(st, "OVERLAY", "spark", "ADD")
		sp:SetAlpha(0)
		self.sparks[i] = sp
	end

	-- the face it landed on, in big letters
	local wh = CreateFrame("Frame", nil, st)
	wh:SetSize(240, 44)
	wh:SetPoint("CENTER", st, "TOP", 0, REST_Y - COIN / 2 - 30)
	self.coinWordHolder = wh
	self.coinWord = W.Text(wh, 30, C_.gold, "THICKOUTLINE")
	self.coinWord:SetPoint("CENTER")
	self.coinWord:SetJustifyH("CENTER")

	self.plates = { plate(st, 1), plate(st, 2) }

	-- the caller's buttons
	self.headsBtn = W.Button(st, "HEADS", 120, 38, "gold")
	self.headsBtn:SetPoint("BOTTOM", st, "BOTTOM", -66, 6)
	self.headsBtn:SetScript("OnClick", function() ns.Client:Call("H") end)
	self.tailsBtn = W.Button(st, "TAILS", 120, 38, "gold")
	self.tailsBtn:SetPoint("BOTTOM", st, "BOTTOM", 66, 6)
	self.tailsBtn:SetScript("OnClick", function() ns.Client:Call("T") end)
	self:CoinDraw(0, 0, 1, 0)
end

function UI:SetCoinMode(on)
	if not self.coinStage or self.coinMode == on then return end
	self.coinMode = on
	self.coinStage:SetShown(on)
	for _, w in ipairs({ self.dieHolder, self.numberHolder, self.range, self.panel }) do w:SetShown(not on) end
end

-- y: height above the rest spot; theta: the turn (0 = face up toward you);
-- scale: nearer/farther; tilt: a slight lean (radians)
function UI:CoinDraw(y, theta, scale, tilt)
	local c = math.cos(theta)
	local sn = math.abs(math.sin(theta))
	local size = COIN * scale
	local h = math.max(1, size * math.abs(c))
	local face = (c >= 0) == (coin.front ~= "T") and "H" or "T"
	if face ~= coin.drawn then
		coin.drawn = face
		local r = TC[face]
		self.coinFace:SetTexCoord(r[1], r[2], r[3], r[4])
	end
	local cy = REST_Y + y
	local f, st = self.coinFace, self.coinStage
	f:ClearAllPoints()
	f:SetPoint("CENTER", st, "TOP", 0, cy)
	f:SetSize(size, h)
	-- light: brightest face-on, a glint as it comes square to you
	local lit = 0.5 + 0.5 * math.abs(c)
	f:SetVertexColor(lit, lit, lit)
	local glint = math.max(0, (math.abs(c) - 0.93) / 0.07)
	self.coinShine:ClearAllPoints()
	self.coinShine:SetPoint("CENTER", st, "TOP", -size * 0.18, cy + h * 0.18)
	self.coinShine:SetSize(size * 0.7, h * 0.7)
	self.coinShine:SetAlpha(coin.mode == "flip" and glint * 0.55 or glint * 0.25)
	-- the rim: the coin's own outline, darker, stepping out as it goes edge-on
	local e = THICK * scale * sn
	local dir = c >= 0 and -1 or 1
	for i, et in ipairs(self.coinEdges) do
		if face ~= et.drawn then
			et.drawn = face
			local r = TC[face]
			et:SetTexCoord(r[1], r[2], r[3], r[4])
		end
		et:ClearAllPoints()
		et:SetPoint("CENTER", st, "TOP", 0, cy + dir * e * i / 3)
		et:SetSize(size, h)
		et:SetAlpha(e > 0.4 and 1 or 0)
	end
	-- the shadow on the felt shrinks and fades as the coin rises
	local lift = math.max(0, y) / 170
	local sw = COIN * (1.05 - 0.45 * lift)
	self.coinShadow:ClearAllPoints()
	self.coinShadow:SetPoint("CENTER", st, "TOP", 6 + 18 * lift, REST_Y - COIN * 0.5 - 4)
	self.coinShadow:SetSize(sw, sw * 0.32)
	self.coinShadow:SetAlpha(0.65 * (1 - 0.7 * lift))
end

local function ease(u) return 1 - (1 - u) * (1 - u) end

function UI:CoinUpdate(dt)
	local now = GetTime()
	if coin.mode == "idle" then
		-- a slow hover, turning over and over
		coin.theta = coin.theta + dt * 1.5
		self:CoinDraw(10 + 5 * math.sin(now * 2.1), coin.theta, 1, 0.05 * math.sin(now * 1.3))
	elseif coin.mode == "flip" then
		local t = now - coin.t0
		if t < WIND then
			-- the thumb cocks: a dip and a squeeze
			local u = t / WIND
			coin.theta = coin.start + 0.4 * u
			self:CoinDraw(10 - 14 * math.sin(math.pi * u), coin.theta, 1 - 0.05 * math.sin(math.pi * u), 0)
		elseif t < LAND_AT then
			if not coin.tossed then coin.tossed = true; ns.Sound.Play("coin_flip") end
			local u = (t - WIND) / FLIGHT
			coin.theta = coin.from + (coin.to - coin.from) * u
			local y = 175 * 4 * u * (1 - u)
			self:CoinDraw(y + 10 * (1 - u) - 4, coin.theta, 1 + 0.38 * math.sin(math.pi * u), 0.18 * math.sin(2 * math.pi * u))
		elseif t < REST_AT then
			if not coin.landed then coin.landed = true; ns.Sound.Play("coin_land") end
			local s = t - LAND_AT
			local y, wob = 0, 0
			if s < HOP1 then
				local u = s / HOP1
				y = 30 * 4 * u * (1 - u)
				wob = 0.75 * math.sin(math.pi * u)
			elseif s < HOP1 + HOP2 then
				local u = (s - HOP1) / HOP2
				y = 9 * 4 * u * (1 - u)
				wob = -0.45 * math.sin(math.pi * u)
			else
				-- spin-down: the wobble shrinks while it speeds up, then it's flat
				local u = (s - HOP1 - HOP2) / SETTLE
				wob = 0.32 * (1 - u) * (1 - u) * math.sin(u * u * 38)
			end
			coin.theta = coin.to + wob
			self:CoinDraw(y, coin.theta, 1, 0.06 * wob)
		else
			coin.mode = "rest"
			coin.theta = coin.to
			self:CoinDraw(0, coin.to, 1, 0)
			self:CoinBurst()
		end
	elseif coin.mode == "rest" then
		self:CoinDraw(0, coin.to or 0, 1, 0)
	end
	-- the landing flash
	if coin.burstAt then
		local b = now - coin.burstAt
		local glow = b < 0.15 and b / 0.15 or math.max(0, 1 - (b - 0.15) / 1.4)
		self.coinGlow:SetAlpha(0.9 * glow)
		for i, sp in ipairs(self.sparks) do
			local a = sp.ang
			local u = math.min(1, b / (0.7 + 0.05 * i))
			local r = 40 + 95 * ease(u)
			sp:ClearAllPoints()
			sp:SetPoint("CENTER", self.coinStage, "TOP", math.cos(a) * r, REST_Y + math.sin(a) * r * 0.75)
			local sz = 26 + 20 * math.sin(math.pi * math.min(1, u * 1.2))
			sp:SetSize(sz, sz)
			sp:SetAlpha(u < 1 and (1 - u) or 0)
		end
		if b > 1.8 then
			coin.burstAt = nil
			self.coinGlow:SetAlpha(0)
			for _, sp in ipairs(self.sparks) do sp:SetAlpha(0) end
		end
		if self.coinWord.pop then
			local k = math.max(0, 1 - b * 3)
			self.coinWordHolder:SetScale(1 + 0.6 * k)
		end
	end
end

function UI:CoinBurst()
	coin.burstAt = GetTime()
	for i, sp in ipairs(self.sparks) do sp.ang = (i / SPARKS) * 2 * math.pi + math.random() * 0.4 end
	self.coinWord:SetText(ns.Games.FACE[coin.face]:upper() .. "!")
	self.coinWord.pop = true
	self:Refresh()
end

-- a new table: back to hovering (or straight to the result when reviewing)
function UI:CoinReset(g)
	coin.mode, coin.theta, coin.front, coin.drawn, coin.burstAt = "idle", 0, "H", nil, nil
	coin.tossed, coin.landed, coin.face = false, false, nil
	if not self.coinWord then return end
	self.coinWord:SetText("")
	self.coinWord.pop = nil
	self.coinGlow:SetAlpha(0)
	for _, sp in ipairs(self.sparks) do sp:SetAlpha(0) end
	local res = g.result
	if g.dice and g.dice.done and res and res.coin then
		coin.mode, coin.face, coin.to = "rest", res.coin.face, res.coin.face == "H" and 0 or math.pi
		self.coinWord:SetText(ns.Games.FACE[res.coin.face]:upper())
	end
end

-- Toss the coin to land on result.face. Returns how long until the result.
function UI:Flip(c)
	local g = ns.Client.game
	if not g then return 0 end
	self:Open()
	sync(g)
	self:SetCoinMode(true)
	coin.face, coin.t0 = c.face, GetTime()
	coin.mode, coin.tossed, coin.landed = "flip", false, false
	coin.start = coin.theta
	coin.from = coin.start + 0.4
	-- whole half-turns from here: an even count shows heads, odd shows tails
	local k = math.ceil(coin.from / math.pi) + 14 + math.random(0, 2) * 2
	if (k % 2 == 0) ~= (c.face == "H") then k = k + 1 end
	coin.to = k * math.pi
	self:Refresh()
	return self.FLIP_TIME
end

function UI:CoinRefresh(g)
	local res, d = g.result, g.dice
	local ci = g.players and #g.players == 2 and ns.Games.CoinCaller(g)
	local landed = coin.mode == "rest" and res and res.coin
	local net = (landed and res) and ns.Games.Net(g, res) or {}
	for i, p in ipairs(self.plates) do
		local who = g.players and g.players[i]
		p:SetShown(who ~= nil)
		if who then
			local me = who == ns.me
			p.name:SetText(ns.Who(who) .. (me and " |cffd9b545(you)|r" or ""))
			local side, amt = "", ""
			if res and res.coin then
				local mine = (i == ci) and res.coin.call or (res.coin.call == "H" and "T" or "H")
				side = (i == ci and "calls " or "has ") .. ns.Games.FACE[mine]:upper()
			elseif g.phase == "commit" or g.phase == "reveal" then
				if i == ci then side = (me and g.awaitCall) and "Your call!" or (me and g.myCall) and ("calls " .. ns.Games.FACE[g.myCall]:upper()) or "calling it..."
				else side = "waiting" end
			elseif g.phase == "open" then side = "seated"
			end
			if landed then
				local n = net[who] or 0
				amt = n > 0 and ("|cff59d959+" .. ns.Money(n) .. "|r") or n < 0 and ("|cffff6161-" .. ns.Money(-n) .. "|r") or ""
			elseif i == ci and (g.phase == "commit" or g.phase == "reveal") then
				amt = "|cff9e948acalls it|r"
			end
			p.side:SetText(side)
			p.amt:SetText(amt)
			local won = landed and (net[who] or 0) > 0
			local lost = landed and (net[who] or 0) < 0
			W.Backdrop(p, won and { 0.30, 0.24, 0.06, 0.95 } or C_.panel,
				won and C_.gold or { C_.goldDim[1], C_.goldDim[2], C_.goldDim[3], 0.6 }, won and 2 or 1)
			p:SetAlpha(lost and 0.6 or 1)
		end
	end
	local can = ns.Client:CanCall()
	self.headsBtn:SetShown(can)
	self.tailsBtn:SetShown(can)
	if not landed and coin.mode ~= "rest" then self.coinWord:SetText("") end
	if coin.mode ~= "flip" and coin.mode ~= "rest" then self:CoinDraw(10, coin.theta, 1, 0) end
end
