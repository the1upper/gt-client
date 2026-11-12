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
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
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

	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, -130)
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
	self.rollBtn:SetShown((seated and not (d and d.done) and g.phase ~= "aborted") and true or false)

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

	-- rows
	local items = {}
	if not d then
		-- before results: who has rolled
		for _, p in ipairs(g.players or {}) do
			local rolled = (g.rolledSet and g.rolledSet[p]) or (p == ns.me and g.awaitRoll == false)
			items[#items + 1] = { name = p, val = rolled and "" or "...", tag = rolled and "|cff59d959rolled|r" or "waiting", muted = not rolled }
		end
	elseif g.type == "deathroll" then
		-- newest first
		for k = math.min(self.revealed, #rolls), 1, -1 do
			local r = rolls[k]
			items[#items + 1] = { name = r.p, val = r.r, tag = "of " .. r.max, lose = r.r == 1, newest = k == self.revealed }
		end
		if d.turn and not d.done and #items < ROWS then
			table.insert(items, 1, { name = rolls[d.turn].p, val = "...", tag = "up next", muted = true })
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
	if res and d and (d.done or (g.type ~= "deathroll" and not self.animating and self.revealed >= #rolls)) then
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
