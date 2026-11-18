-- The Golden Thugget: Battle Slots window - a modern video slot. A neon
-- cabinet with a colour-cycling sign and chasing LEDs, a bright video screen
-- (turning sunburst, neon-framed glass reels), big-win pop-ups and sparks, and
-- a chrome lever you grab and drag down to spin. On the right, everyone's
-- three spins as they come in.
-- Every spin was fixed by the sealed rolls before anyone pulled; the lever
-- only shows you your next one.
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.SlotsUI = UI
local W = ns.W
local C_ = W.C
local SL -- ns.Games.Slots (set on first use)

local ATLAS = ns.MEDIA .. "slots"
local RAYS = ns.MEDIA .. "slots_screen"
local COIN = ns.MEDIA .. "coin"
local CELL = 76          -- one symbol on a reel
local REEL_W = 104
local GAP = 10
local ROWS = 3           -- symbols in view
local STRIP = 24         -- symbols on a reel strip
local SPARKS = 18
local COINS = 26
local LEDS = 44
-- reel stops (seconds after the pull); the last reel waits longer on a near miss
local STOPS = { 1.15, 1.6, 2.05 }
local TEASE_STOP = 3.1
local SETTLE = 0.18      -- the little bounce as a reel locks
-- the lever
local ARM = 118          -- arm length (pivot to knob)
local PULL = 150         -- how far down you drag for a full pull
local SWING = math.rad(155)
local FIRE_AT = 0.88     -- pulled this far: it spins

-- atlas cells (128px in a 512px sheet)
local function cellTC(i)
	local col, row = i % 4, math.floor(i / 4)
	return col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25
end
local SYMCELL = { 0, 1, 2, 3, 4, 5 } -- 7, BAR, Bell, Plum, Lemon, Cherry
local GLOW, LED, KNOB, PAYLINE, SPARK, SHAFT, BASE, GLASS, FADE = 6, 7, 8, 9, 10, 11, 12, 13, 14

local function tex(parent, layer, cell, blend, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetTexture(ATLAS)
	if cell then t:SetTexCoord(cellTC(cell)) end
	if blend then t:SetBlendMode(blend) end
	return t
end

-- hue (0-1) -> bright r, g, b
local function hue(h, s, v)
	s, v = s or 1, v or 1
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
	return v, p, q
end
local NEON = { { 0.2, 0.95, 1 }, { 1, 0.25, 0.85 }, { 1, 0.85, 0.15 } } -- cyan, magenta, gold

---------------------------------------------------------------------------
-- reels
---------------------------------------------------------------------------
-- pos is the strip coordinate (in cells) at the top edge of the window;
-- symbols move down as pos falls. A reel at rest sits on a whole number and
-- its middle row (the payline) shows strip[pos + 1].
local function newReel(parent, x, k)
	local r = { cells = {}, strip = {}, pos = 0 }
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(REEL_W, CELL * ROWS)
	f:SetPoint("TOPLEFT", x, 0)
	W.Backdrop(f, { 0, 0, 0, 0 }, NEON[k], 2)
	r.frame = f
	local glass = tex(f, "BACKGROUND", GLASS)
	glass:SetPoint("TOPLEFT", 2, -2)
	glass:SetPoint("BOTTOMRIGHT", -2, 2)
	r.tease = tex(f, "BORDER", GLOW, "ADD")
	r.tease:SetPoint("CENTER")
	r.tease:SetSize(REEL_W * 1.6, CELL * ROWS * 1.1)
	r.tease:SetVertexColor(1, 0.8, 0.2)
	r.tease:SetAlpha(0)
	for i = 0, ROWS do
		local t = tex(f, "ARTWORK", 0)
		t:SetSize(CELL, CELL)
		r.cells[i] = t
	end
	for i = 1, STRIP do r.strip[i] = math.random(1, 6) end
	-- the drum curves away at the top and bottom
	local top = tex(f, "OVERLAY", FADE)
	top:SetPoint("TOPLEFT", 2, -2)
	top:SetPoint("TOPRIGHT", -2, -2)
	top:SetHeight(CELL * 0.8)
	local bottom = tex(f, "OVERLAY", FADE)
	local l, rr, t, b = cellTC(FADE)
	bottom:SetTexCoord(l, rr, b, t)
	bottom:SetPoint("BOTTOMLEFT", 2, 2)
	bottom:SetPoint("BOTTOMRIGHT", -2, 2)
	bottom:SetHeight(CELL * 0.8)
	return r
end

-- sample a rotated window of the (square, radial) rays image, sized to the
-- screen's shape: the texture stays put, the picture turns
local RAY_HW, RAY_HH = 0.34, 0.34 * 312 / 432
local function turnRays(t, a)
	local c, s = math.cos(a), math.sin(a)
	local function pt(x, y) return 0.5 + x * c - y * s, 0.5 + x * s + y * c end
	local ulx, uly = pt(-RAY_HW, -RAY_HH)
	local llx, lly = pt(-RAY_HW, RAY_HH)
	local urx, ury = pt(RAY_HW, -RAY_HH)
	local lrx, lry = pt(RAY_HW, RAY_HH)
	t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function stripAt(r, j) return r.strip[(j % STRIP) + 1] end

-- draw a reel at strip position pos; blur dims symbols while it's flying
local function drawReel(r, blur)
	local base = math.floor(r.pos)
	local frac = r.pos - base
	local H = CELL * ROWS
	for i = 0, ROWS do
		local t = r.cells[i]
		local top = (i - frac) * CELL          -- distance from the window top to this cell's top
		local bottom = top + CELL
		local vt, vb = math.max(top, 0), math.min(bottom, H)
		if vb - vt < 0.5 then
			t:Hide()
		else
			local l, rr, tt, bb = cellTC(SYMCELL[stripAt(r, base + i)])
			local span = bb - tt
			t:SetTexCoord(l, rr, tt + span * (vt - top) / CELL, tt + span * (vb - top) / CELL)
			t:ClearAllPoints()
			t:SetPoint("TOP", r.frame, "TOP", 0, -vt)
			t:SetSize(CELL, vb - vt)
			t:SetAlpha(blur and 0.7 or 1)
			t:Show()
		end
	end
end

-- motion: speed up, cruise, brake (constant deceleration), then lock with a bounce
local A, B = 0.08, 0.55
local AREA = A / 2 + (B - A) + (1 - B) / 2
local function travel(u)
	if u <= 0 then return 0 end
	if u >= 1 then return 1 end
	if u < A then return (u * u / (2 * A)) / AREA end
	if u < B then return (A / 2 + (u - A)) / AREA end
	local d, L = u - B, 1 - B
	return (A / 2 + (B - A) + d - d * d / (2 * L)) / AREA
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local st = {} -- animation state (per table)
local lever = { u = 0 } -- the arm: u = 0 up .. 1 pulled all the way down

function UI:Build()
	if self.frame then return end
	SL = ns.Games.Slots
	local f = CreateFrame("Frame", "GoldenThuggetSlotsFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(800, 650)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetFrameLevel(50)
	W.Backdrop(f, { 0.03, 0.02, 0.06, 0.98 }, { 0.35, 0.25, 0.6, 1 }, 2)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetSlotsFrame")
	f:Hide()
	tinsert(UISpecialFrames, "GoldenThuggetSlotsFrame")
	f:SetScript("OnShow", function() driver:SetScript("OnUpdate", function(_, dt) UI:Update(dt) end); UI:Refresh() end)
	f:SetScript("OnHide", function() driver:SetScript("OnUpdate", nil); lever.drag = nil end)

	local crest = W.Logo(f, 44)
	crest:SetPoint("TOPLEFT", 12, -6)
	self.title = W.Text(f, 16, C_.gold)
	self.title:SetPoint("TOPLEFT", 62, -11)
	self.sub = W.Text(f, 12, C_.text)
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
	W.Fit(self.sub, 420, 1)
	self.timer = W.Text(f, 16, C_.text, "OUTLINE")
	self.timer:SetPoint("TOPRIGHT", -40, -14)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.rules = W.RulesButton(f, function() return "slots" end)
	self.rules:SetPoint("TOPRIGHT", -80, -14)

	---------------------------------------------- the cabinet
	local cab = CreateFrame("Frame", nil, f, "BackdropTemplate")
	cab:SetSize(470, 440)
	cab:SetPoint("TOPLEFT", 16, -56)
	W.Backdrop(cab, { 0.05, 0.04, 0.10, 1 }, { 1, 0.3, 0.9, 1 }, 3)
	self.cab = cab
	-- a soft neon wash behind the cabinet edge
	self.cabGlow = tex(cab, "BACKGROUND", GLOW, "ADD", -2)
	self.cabGlow:SetPoint("TOPLEFT", -40, 40)
	self.cabGlow:SetPoint("BOTTOMRIGHT", 40, -40)
	self.cabGlow:SetAlpha(0.18)
	-- LED strip around the cabinet
	self.leds = {}
	local function ledAt(x, y)
		local d = tex(cab, "OVERLAY", LED, "ADD")
		d:SetSize(11, 11)
		d:SetPoint("CENTER", cab, "TOPLEFT", x, -y)
		self.leds[#self.leds + 1] = d
	end
	local per = LEDS / 4
	for i = 0, per - 1 do ledAt(10 + i * (450 / (per - 1)), 7) end
	for i = 0, per - 1 do ledAt(463, 10 + i * (420 / (per - 1))) end
	for i = per - 1, 0, -1 do ledAt(10 + i * (450 / (per - 1)), 433) end
	for i = per - 1, 0, -1 do ledAt(7, 10 + i * (420 / (per - 1))) end

	-- the sign
	self.signGlow = tex(cab, "BORDER", GLOW, "ADD")
	self.signGlow:SetSize(420, 90)
	self.signGlow:SetPoint("TOP", 0, -6)
	self.sign = W.Text(cab, 32, C_.gold, "THICKOUTLINE")
	self.sign:SetPoint("TOP", 0, -24)
	self.sign:SetText("BATTLE SLOTS")

	-- the video screen
	local scr = CreateFrame("Frame", nil, cab, "BackdropTemplate")
	scr:SetSize(436, 316)
	scr:SetPoint("TOP", 0, -72)
	W.Backdrop(scr, { 0.16, 0.03, 0.30, 1 }, { 0.2, 0.95, 1, 1 }, 2)
	self.screen = scr
	local wash = tex(scr, "BACKGROUND", GLOW, "ADD", 1)
	wash:SetPoint("TOPLEFT", 2, -2)
	wash:SetPoint("BOTTOMRIGHT", -2, 2)
	wash:SetVertexColor(1, 0.2, 0.7)
	wash:SetAlpha(0.6)
	self.wash = wash
	-- the sunburst: fixed to the screen; it turns by rotating the part of the
	-- image it samples (so nothing spills past the screen edges)
	self.rays = scr:CreateTexture(nil, "BACKGROUND", nil, 2)
	self.rays:SetTexture(RAYS)
	self.rays:SetPoint("TOPLEFT", 2, -2)
	self.rays:SetPoint("BOTTOMRIGHT", -2, 2)
	self.rays:SetBlendMode("ADD")
	self.rays:SetVertexColor(1, 0.55, 0.95)
	self.rays:SetAlpha(0.3)
	local holder = CreateFrame("Frame", nil, scr)
	holder:SetSize(3 * REEL_W + 2 * GAP, CELL * ROWS)
	holder:SetPoint("TOP", 0, -16)
	self.reelHolder = holder
	self.reels = {}
	for k = 1, 3 do self.reels[k] = newReel(holder, (k - 1) * (REEL_W + GAP), k) end
	-- the payline
	self.payGlow = tex(holder, "OVERLAY", PAYLINE, "ADD")
	self.payGlow:SetPoint("CENTER")
	self.payGlow:SetSize(3 * REEL_W + 2 * GAP + 30, CELL * 1.15)
	self.payGlow:SetAlpha(0)
	self.payLine = tex(holder, "OVERLAY", PAYLINE, "ADD")
	self.payLine:SetPoint("CENTER")
	self.payLine:SetSize(3 * REEL_W + 2 * GAP + 24, 6)
	self.payLine:SetVertexColor(0.3, 1, 1)
	self.payLine:SetAlpha(0.8)
	for _, side in ipairs({ -1, 1 }) do
		local dot = tex(holder, "OVERLAY", LED, "ADD")
		dot:SetSize(16, 16)
		dot:SetVertexColor(0.3, 1, 1)
		dot:SetPoint("CENTER", holder, side < 0 and "LEFT" or "RIGHT", side * 12, 0)
	end
	-- the big-win pop-up over the reels
	local bw = CreateFrame("Frame", nil, scr)
	bw:SetSize(400, 70)
	bw:SetPoint("CENTER", holder, "CENTER", 0, 0)
	bw:SetFrameLevel(holder:GetFrameLevel() + 10)
	bw:Hide()
	self.bigWin = bw
	bw.glow = tex(bw, "BACKGROUND", GLOW, "ADD")
	bw.glow:SetPoint("CENTER")
	bw.glow:SetSize(460, 140)
	bw.text = W.Text(bw, 40, C_.gold, "THICKOUTLINE")
	bw.text:SetPoint("CENTER")
	-- the read-out under the reels: what this spin made, and the spin pips
	self.spinName = W.Text(scr, 22, C_.gold, "THICKOUTLINE")
	self.spinName:SetPoint("TOP", holder, "BOTTOM", 0, -12)
	self.spinName:SetJustifyH("CENTER")
	self.reelLabel = W.Text(scr, 12, { 0.85, 0.85, 1 })
	self.reelLabel:SetPoint("TOP", self.spinName, "BOTTOM", 0, -4)
	self.reelLabel:SetJustifyH("CENTER")
	self.pips = {}
	for k = 1, 3 do
		local p = tex(scr, "OVERLAY", LED, "ADD")
		p:SetSize(18, 18)
		p:SetPoint("BOTTOMLEFT", 12 + (k - 1) * 20, 8)
		self.pips[k] = p
	end
	self.pipLabel = W.Text(scr, 10, { 0.8, 0.8, 1 })
	self.pipLabel:SetPoint("LEFT", self.pips[3], "RIGHT", 4, 0)
	self.readout = W.Text(scr, 11, { 0.6, 1, 1 })
	self.readout:SetPoint("BOTTOMRIGHT", -12, 11)
	self.readout:SetJustifyH("RIGHT")

	-- under the screen: the prompt
	self.prompt = W.Text(cab, 15, { 0.3, 1, 1 }, "OUTLINE")
	self.prompt:SetPoint("TOP", scr, "BOTTOM", 0, -14)
	self.prompt:SetJustifyH("CENTER")

	---------------------------------------------- the lever
	local lv = CreateFrame("Frame", nil, cab)
	lv:SetSize(60, 60)
	lv:SetPoint("CENTER", cab, "RIGHT", 14, 10)
	lv:SetFrameLevel(cab:GetFrameLevel() + 20)
	self.lv = lv
	self.leverBase = tex(lv, "BORDER", BASE)
	self.leverBase:SetSize(54, 54)
	self.leverBase:SetPoint("CENTER")
	self.shaft = tex(lv, "ARTWORK", SHAFT)
	self.knobShadow = tex(lv, "ARTWORK", GLOW, nil, 1)
	self.knobShadow:SetVertexColor(0, 0, 0)
	self.knob = tex(lv, "OVERLAY", KNOB)
	self.knobGlow = tex(lv, "OVERLAY", GLOW, "ADD", 1)
	self.knobGlow:SetVertexColor(1, 0.4, 0.4)
	-- the grip: follows the knob; grab it and drag down
	local grip = CreateFrame("Button", nil, lv)
	grip:SetSize(46, 46)
	grip:SetFrameLevel(lv:GetFrameLevel() + 5)
	grip:RegisterForClicks("LeftButtonUp")
	grip:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then UI:Grab() end end)
	grip:SetScript("OnMouseUp", function() UI:Release() end)
	grip:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.Client:CanSpin() and "Grab the knob and pull it down to spin" or "Not your pull right now")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.grip = grip
	self.pullHint = W.Text(lv, 13, { 1, 0.9, 0.3 }, "OUTLINE")
	self.pullHint:SetText("PULL")

	-- effects
	self.sparks = {}
	for i = 1, SPARKS do
		local sp = tex(f, "OVERLAY", SPARK, "ADD")
		sp:SetAlpha(0)
		self.sparks[i] = sp
	end
	self.coins = {}
	for i = 1, COINS do
		local c = f:CreateTexture(nil, "OVERLAY")
		c:SetTexture(COIN)
		c:SetTexCoord(0, 0.5, 0, 0.5)
		c:SetAlpha(0)
		self.coins[i] = c
	end

	---------------------------------------------- everyone's spins
	local panel = W.Panel(f, 262, 440)
	panel:SetPoint("TOPRIGHT", -14, -56)
	W.Backdrop(panel, { 0.05, 0.03, 0.10, 0.95 }, { 0.2, 0.95, 1, 0.7 }, 2)
	local hdr = W.Text(panel, 12, { 0.3, 1, 1 }, "OUTLINE")
	hdr:SetPoint("TOPLEFT", 10, -9)
	hdr:SetText("THE TABLE")
	self.rows = {}
	for i = 1, 8 do
		local r = CreateFrame("Frame", nil, panel, "BackdropTemplate")
		r:SetSize(246, 48)
		r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 51)
		W.Backdrop(r, { 1, 1, 1, 0.04 }, { 0.5, 0.4, 1, 0.3 })
		r.name = W.Text(r, 12, C_.text)
		r.name:SetPoint("TOPLEFT", 6, -5)
		W.Fit(r.name, 144, 1)
		r.best = W.Text(r, 10, { 1, 0.85, 0.3 })
		r.best:SetPoint("TOPRIGHT", -6, -6)
		r.best:SetJustifyH("RIGHT")
		r.best:SetWidth(98)
		r.spins = {}
		for k = 1, 3 do
			local g = CreateFrame("Frame", nil, r, "BackdropTemplate")
			g:SetSize(74, 24)
			g:SetPoint("BOTTOMLEFT", 6 + (k - 1) * 79, 4)
			W.Backdrop(g, { 0, 0, 0, 0.5 }, { 0.4, 0.35, 0.7, 0.5 })
			g.icons = {}
			for j = 1, 3 do
				local t = tex(g, "ARTWORK", 0)
				t:SetSize(22, 22)
				t:SetPoint("LEFT", 2 + (j - 1) * 24, 0)
				t:Hide()
				g.icons[j] = t
			end
			g.wait = W.Text(g, 11, C_.muted)
			g.wait:SetPoint("CENTER")
			r.spins[k] = g
		end
		self.rows[i] = r
	end

	---------------------------------------------- the paytable (best to worst)
	local pt = CreateFrame("Frame", nil, f, "BackdropTemplate")
	pt:SetSize(768, 102)
	pt:SetPoint("TOPLEFT", cab, "BOTTOMLEFT", 0, -8)
	W.Backdrop(pt, { 0.05, 0.03, 0.10, 0.95 }, { 1, 0.85, 0.2, 0.6 }, 2)
	self.paytable = pt
	self.ptGlow = tex(pt, "BACKGROUND", GLOW, "ADD", 1)
	self.ptGlow:SetPoint("TOPLEFT", -30, 20)
	self.ptGlow:SetPoint("BOTTOMRIGHT", 30, -20)
	self.ptGlow:SetAlpha(0.15)
	local ptHdr = W.Text(pt, 11, { 1, 0.85, 0.3 }, "OUTLINE")
	ptHdr:SetPoint("TOPLEFT", 10, -7)
	ptHdr:SetText("PAYTABLE")
	local ptSub = W.Text(pt, 10, { 0.69, 0.66, 0.82 })
	ptSub:SetPoint("TOPRIGHT", -12, -8)
	ptSub:SetText("best first - your best spin of three counts")
	self.payEntries = {}
	local function entry(parent, x, y, syms, key, tag)
		local e = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		e:SetSize(#syms * 20 + 6, 24)
		e:SetPoint("TOPLEFT", x, y)
		W.Backdrop(e, { 0, 0, 0, 0.45 }, { 0.5, 0.4, 1, 0.35 })
		for j, sy in ipairs(syms) do
			local t = tex(e, "ARTWORK", sy and SYMCELL[sy] or 0)
			t:SetSize(20, 20)
			t:SetPoint("LEFT", 3 + (j - 1) * 20, 0)
			if not sy then t:SetAlpha(0) end
		end
		if tag then
			local tt = W.Text(e, 9, { 1, 0.85, 0.3 }, "OUTLINE")
			tt:SetPoint("BOTTOM", e, "TOP", 0, 1)
			tt:SetText(tag)
		end
		self.payEntries[key] = e
		return e
	end
	local function row(label, y, make)
		local l = W.Text(pt, 11, { 0.3, 1, 1 }, "OUTLINE")
		l:SetPoint("TOPLEFT", 10, y - 6)
		l:SetText(label)
		local x = 70
		for sy = 1, 6 do
			local e = make(sy, x, y)
			x = x + e:GetWidth() + 4
			if sy < 6 then
				local gt = W.Text(pt, 12, { 0.7, 0.65, 0.9 })
				gt:SetPoint("LEFT", pt, "TOPLEFT", x, y - 12)
				gt:SetText(">")
				x = x + 14
			end
		end
		return x
	end
	local endX = row("TRIPLES", -26, function(sy, x, y)
		return entry(pt, x, y, { sy, sy, sy }, "triple" .. sy, sy == 1 and "JACKPOT" or nil)
	end)
	local more = W.Text(pt, 11, { 0.85, 0.85, 1 })
	more:SetPoint("LEFT", pt, "TOPLEFT", endX + 8, -38)
	more:SetText("then...")
	row("PAIRS", -56, function(sy, x, y)
		return entry(pt, x, y, { sy, sy }, "pair" .. sy)
	end)
	local mixed = CreateFrame("Frame", nil, pt, "BackdropTemplate")
	mixed:SetSize(230, 24)
	mixed:SetPoint("TOPRIGHT", -10, -56)
	W.Backdrop(mixed, { 0, 0, 0, 0.45 }, { 0.5, 0.4, 1, 0.35 })
	local mt = W.Text(mixed, 10, { 0.85, 0.85, 1 })
	mt:SetPoint("CENTER")
	mt:SetText("then MIXED: best symbols win")
	self.payEntries.mixed = mixed
	local ties = W.Text(pt, 10, { 0.7, 0.65, 0.9 })
	ties:SetPoint("BOTTOMRIGHT", -12, 5)
	ties:SetText("Pairs: the odd symbol breaks a tie.  Equal best spins: next best, then third, then a sudden-death spin-off.")

	---------------------------------------------- bottom
	self.leave = W.Button(f, "Leave", 96, 24)
	self.leave:SetPoint("BOTTOMRIGHT", -16, 12)
	self.leave:SetScript("OnClick", function() ns.Client:LeaveOrClose() end)
	self.banner = W.Text(f, 13, C_.gold, "OUTLINE")
	self.banner:SetPoint("BOTTOMLEFT", 18, 14)
	W.Fit(self.banner, 800 - 18 - 16 - 96 - 12, 2)
	self.banner:SetJustifyV("BOTTOM")

	self.turnGlow = W.TurnGlow(f)
	self.pop = W.ResultPop(f, -40)
	for k = 1, 3 do drawReel(self.reels[k]) end
	self:LeverDraw(0)
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
-- the lever: drawn as an arm swinging toward you on a pivot. Up, the knob
-- sits above the pivot; pulled, the arm comes at you (bigger) and down past it.
---------------------------------------------------------------------------
function UI:LeverDraw(u)
	if not self.knob then return end
	u = math.max(-0.08, math.min(1, u))
	local th = u * SWING
	local ky = ARM * math.cos(th)          -- knob height above the pivot (screen)
	local near = math.max(0, math.sin(th))  -- how much it points at you
	local sc = 1 + 0.5 * near
	local lv = self.lv
	local sh = self.shaft
	sh:ClearAllPoints()
	sh:SetWidth(11 * (1 + 0.35 * near))
	if ky >= 0 then
		sh:SetPoint("BOTTOM", lv, "CENTER", 0, 0)
		sh:SetHeight(math.max(1, ky))
	else
		sh:SetPoint("TOP", lv, "CENTER", 0, 0)
		sh:SetHeight(math.max(1, -ky))
	end
	-- light catches the shaft as it turns toward you
	local lit = 0.75 + 0.35 * near
	sh:SetVertexColor(lit, lit, lit)
	local ks = 36 * sc
	self.knob:ClearAllPoints()
	self.knob:SetPoint("CENTER", lv, "CENTER", 0, ky)
	self.knob:SetSize(ks, ks)
	self.knobShadow:ClearAllPoints()
	self.knobShadow:SetPoint("CENTER", lv, "CENTER", 6 + 10 * near, ky - 8 - 10 * near)
	self.knobShadow:SetSize(ks * 1.3, ks * 1.3)
	self.knobShadow:SetAlpha(0.35 + 0.25 * near)
	self.knobGlow:ClearAllPoints()
	self.knobGlow:SetPoint("CENTER", lv, "CENTER", 0, ky)
	self.knobGlow:SetSize(ks * 2.2, ks * 2.2)
	self.grip:ClearAllPoints()
	self.grip:SetPoint("CENTER", lv, "CENTER", 0, ky)
	self.grip:SetSize(ks + 12, ks + 12)
	self.pullHint:ClearAllPoints()
	self.pullHint:SetPoint("BOTTOM", self.knob, "TOP", 0, 4)
end

local function cursorY()
	local _, y = GetCursorPosition()
	return y / UIParent:GetEffectiveScale()
end

function UI:Grab()
	if lever.spring then lever.spring = nil end
	lever.drag = { y0 = cursorY(), u0 = lever.u, fired = false, can = ns.Client:CanSpin() }
	ns.Sound.Play("dice_grab")
end

function UI:Release()
	if not lever.drag then return end
	lever.drag = nil
	-- spring back up with a little wobble
	lever.spring = { t0 = GetTime(), from = lever.u }
end

-- an automatic pull (time ran out): the arm drops and comes back by itself
function UI:AutoPull()
	if lever.drag then return end
	lever.spring = nil
	lever.auto = GetTime()
end

local function leverUpdate(self, now)
	local d = lever.drag
	if d then
		if not IsMouseButtonDown("LeftButton") then self:Release() return end
		local u = d.u0 + (d.y0 - cursorY()) / PULL
		-- not yours to pull: it barely gives
		if not d.can then u = math.min(u, 0.1) end
		lever.u = math.max(0, math.min(1, u))
		if d.can and not d.fired and lever.u >= FIRE_AT then
			d.fired = true
			ns.Sound.Play("reel_stop")
			lever.firedByHand = true
			ns.Client:Spin()
			lever.firedByHand = nil
		end
	elseif lever.auto then
		local t = now - lever.auto
		if t < 0.22 then lever.u = t / 0.22
		else lever.auto = nil; lever.spring = { t0 = now, from = 1 } end
	elseif lever.spring then
		local t = now - lever.spring.t0
		local u = lever.spring.from * math.exp(-t * 7) * math.cos(t * 15)
		lever.u = math.max(-0.06, u)
		if t > 1.2 then lever.spring = nil; lever.u = 0 end
	end
	self:LeverDraw(lever.u)
	-- the knob glows when it's yours to pull
	local can = ns.Client:CanSpin()
	local pulse = 0.5 + 0.5 * math.sin(now * 5)
	self.knobGlow:SetAlpha(can and (0.35 + 0.45 * pulse) or 0)
	self.pullHint:SetShown(can and not lever.drag and lever.u < 0.05)
	self.pullHint:SetAlpha(0.6 + 0.4 * pulse)
end

---------------------------------------------------------------------------
-- per-table state
---------------------------------------------------------------------------
local function spinsOf(g, p) return g.result and g.result.slots and g.result.slots.spins[p] end

local function sync(g)
	if st.id == g.id then return end
	st = { id = g.id, revealed = {}, chase = 0, chaseT = 0 }
	lever.drag, lever.spring, lever.auto, lever.u = nil, nil, nil, 0
	if UI.reels then
		for _, r in ipairs(UI.reels) do r.spin = nil; r.tease:SetAlpha(0); drawReel(r) end
		UI.spinName:SetText("")
		UI.reelLabel:SetText("")
		UI.payGlow:SetAlpha(0)
		UI.bigWin:Hide()
		UI:LeverDraw(0)
		st.payHit = nil
	end
	-- reviewing a finished table: everything is already in
	if g.sl and g.sl.final then
		for _, p in ipairs(g.players) do st.revealed[p] = 3 end
		st.finished = true
	end
end

-- who is ahead among the spins shown so far (sorted best scores, then the earlier seat)
local function standings(g)
	local best = {}
	for _, p in ipairs(g.players or {}) do
		local sp, n = spinsOf(g, p), st.revealed[p] or 0
		local list = {}
		for k = 1, n do if sp then list[#list + 1] = (SL.Eval(sp[k])) end end
		table.sort(list, function(a, b) return a > b end)
		best[p] = list
	end
	return best
end

---------------------------------------------------------------------------
-- spinning
---------------------------------------------------------------------------
-- set the reels spinning toward result r (three symbol numbers). Returns how long.
function UI:StartSpin(r, label, quick)
	local now = GetTime()
	local tease = (r[1] == r[2]) and not quick
	for k = 1, 3 do
		local reel = self.reels[k]
		local start = math.floor(reel.pos + 0.5)
		local dur = quick and (0.55 + 0.2 * k) or (k == 3 and tease and TEASE_STOP or STOPS[k])
		local dist = math.floor(dur * 17) + k
		local target = start - dist
		-- the result lands on the payline; its neighbours stay random
		reel.strip[((target + 1) % STRIP) + 1] = r[k]
		reel.spin = { t0 = now, dur = dur, from = start, to = target, tease = tease and k == 3 }
	end
	st.result = r
	st.spinLabel = label
	st.spinEnd = now + (quick and 1.3 or (tease and TEASE_STOP or STOPS[3])) + SETTLE
	st.landed = false
	st.winAt, st.winKind = nil, nil
	self.spinName:SetText("")
	self.reelLabel:SetText(label or "")
	self.payGlow:SetAlpha(0)
	self.bigWin:Hide()
	-- one recording carries the whole spin, its pops timed to the reel stops above
	-- (tools/cut_slot_sound.py cuts it to STOPS / TEASE_STOP / the quick timings)
	ns.Sound.Play(quick and "slot_reels_quick" or (tease and "slot_reels_tease" or "slot_reels"))
	return (st.spinEnd - now) + 0.9
end

-- your spin k: spin, land. Returns seconds until it has landed and shown.
function UI:SpinMine(k)
	local g = ns.Client.game
	if not g then return 0 end
	self:Open()
	sync(g)
	local sp = spinsOf(g, ns.me)
	if not sp then return 0 end
	if not lever.firedByHand then self:AutoPull() end -- time ran out: the arm drops by itself
	st.mineK = k
	st.landFor = ns.me
	local t = self:StartSpin(sp[k], ("Your spin %d of 3"):format(k))
	self:Refresh()
	return t
end

-- someone else's spin k has landed on their machine: it shows in the table
-- panel only (your machine only ever spins your own spins)
function UI:OtherSpun(p, k)
	local g = ns.Client.game
	if not (g and self.frame) then return end
	sync(g)
	st.revealed[p] = math.max(st.revealed[p] or 0, k)
	st.flash = st.flash or {}
	st.flash[p .. ":" .. k] = GetTime()
	self:Refresh()
end

-- everyone's spins are in: the spin-off (if any - each tied player sees only
-- their own spin-off spin on their machine), then the result. Returns duration.
function UI:Finale()
	local g = ns.Client.game
	if not (g and g.result and g.result.slots) then return 0 end
	self:Open()
	sync(g)
	for _, p in ipairs(g.players) do st.revealed[p] = 3 end
	local bonus = g.result.slots.bonus or {}
	local t = 0.6
	if #bonus > 0 then
		st.spinoff = true
		for _, b in ipairs(bonus) do
			if b.p == ns.me then
				C_Timer.After(t, function()
					if st.id ~= g.id then return end
					st.landFor = b.p
					UI:StartSpin(b.r, ("SPIN-OFF %d: your spin"):format(b.round), true)
				end)
			end
			t = t + 2.4
		end
		t = t + 0.4
	else
		t = t + 0.8
	end
	C_Timer.After(t, function()
		if st.id ~= g.id then return end
		st.finished = true
		UI:Refresh()
	end)
	self:Refresh()
	return t
end

---------------------------------------------------------------------------
-- effects
---------------------------------------------------------------------------
local function landed(self)
	st.landed = true
	local r = st.result
	local _, name, kind = SL.Eval(r)
	self.spinName:SetText(kind == "mixed" and ("|cffb0a8d0" .. name .. "|r") or name .. "!")
	st.winKind, st.winAt = kind, GetTime()
	if kind == "triple" then st.payHit = "triple" .. r[1]
	elseif kind == "pair" then st.payHit = "pair" .. ((r[1] == r[2] or r[1] == r[3]) and r[1] or r[2])
	else st.payHit = "mixed" end
	st.payAt = GetTime()
	st.jackpot = r[1] == 1 and r[2] == 1 and r[3] == 1
	if kind == "triple" then
		self.bigWin.text:SetText(st.jackpot and "JACKPOT!" or "BIG WIN!")
		self.bigWin:Show()
		self:Burst(st.jackpot)
		ns.Sound.Play("slot_win")
		if st.jackpot then ns.Sound.Play("jackpot", 0.4) end
	elseif kind == "pair" then
		ns.Sound.Play("slot_pair")
	else
		ns.Sound.Play("slot_lose")
	end
	local g = ns.Client.game
	if g and st.landFor == ns.me and st.mineK then st.revealed[ns.me] = math.max(st.revealed[ns.me] or 0, st.mineK) end
	self:Refresh()
end

function UI:Burst(jackpot)
	st.burstAt = GetTime()
	for i, sp in ipairs(self.sparks) do
		sp.ang = i / SPARKS * 2 * math.pi + math.random() * 0.3
		sp:SetVertexColor(hue(math.random()))
	end
	if jackpot then
		st.coinsAt = GetTime()
		for _, c in ipairs(self.coins) do
			c.x = math.random(40, 760)
			c.vy = -math.random(30, 140)
			c.delay = math.random() * 0.8
			c.spin = 4 + math.random() * 6
			c.size = math.random(18, 30)
		end
	end
end

function UI:Update(dt)
	local g = ns.Client.game
	if not (g and self.frame and self.frame:IsShown() and g.type == "slots") then return end
	local now = GetTime()
	-- reels
	for _, reel in ipairs(self.reels) do
		local s = reel.spin
		if s then
			local t = now - s.t0
			if t < s.dur then
				local dist = (s.from - s.to) + 0.3
				reel.pos = s.from - dist * travel(t / s.dur)
				reel.tease:SetAlpha(s.tease and t > STOPS[3] - 0.3 and (0.4 + 0.4 * math.sin(now * 14)) or 0)
				drawReel(reel, t / s.dur > 0.06 and t / s.dur < 0.7)
			elseif t < s.dur + SETTLE then
				s.stopped = true
				local u = (t - s.dur) / SETTLE
				reel.pos = (s.to - 0.3) + 0.3 * (1 - (1 - u) * (1 - u))
				reel.tease:SetAlpha(0)
				drawReel(reel)
			else
				reel.pos = s.to
				reel.spin = nil
				reel.tease:SetAlpha(0)
				drawReel(reel)
			end
		end
	end
	if st.spinEnd and not st.landed and now >= st.spinEnd then landed(self) end
	leverUpdate(self, now)

	-- the cabinet lights: neon edge and sign cycle colour, LEDs chase a rainbow
	local winning = st.winKind == "triple" and st.winAt and now - st.winAt < 3
	local speed = winning and 0.6 or 0.08
	local h0 = (now * speed) % 1
	local r, gg, b = hue(h0)
	self.cab:SetBackdropBorderColor(r, gg, b, 1)
	if self.paytable then
		self.paytable:SetBackdropBorderColor(hue(h0 + 0.33))
		self.ptGlow:SetVertexColor(hue(h0 + 0.33))
	end
	self.cabGlow:SetVertexColor(r, gg, b)
	self.sign:SetTextColor(hue(h0 + 0.5, 0.35, 1))
	self.signGlow:SetVertexColor(hue(h0 + 0.5))
	self.signGlow:SetAlpha(0.45 + 0.15 * math.sin(now * 3))
	local step = math.floor(now * (winning and 30 or 12))
	for i, d in ipairs(self.leds) do
		local on = winning and (step % 2 == 0) or ((i + step) % 4 ~= 0)
		d:SetVertexColor(hue((i / #self.leds) + h0 * 2))
		d:SetAlpha(on and 1 or 0.15)
	end
	-- the screen: the sunburst turns; it races on a big win
	st.rayAng = ((st.rayAng or 0) + dt * (winning and 1.4 or 0.15)) % (2 * math.pi)
	turnRays(self.rays, st.rayAng)
	self.rays:SetAlpha(winning and (0.5 + 0.15 * math.sin(now * 10)) or 0.3)

	-- payline and winning symbols after a win
	if st.winAt and st.landed then
		local t = now - st.winAt
		local amp = st.winKind == "triple" and 1 or st.winKind == "pair" and 0.55 or 0
		self.payGlow:SetVertexColor(hue(h0 * 3))
		self.payGlow:SetAlpha(amp > 0 and amp * (0.55 + 0.45 * math.cos(t * 7)) * math.max(0.35, 1 - t / 3) or 0)
		local rr = st.result
		for k = 1, 3 do
			local count = 0
			for j = 1, 3 do if rr[j] == rr[k] then count = count + 1 end end
			local cell = self.reels[k].cells[1]
			if count >= 2 and t < 2.5 and not self.reels[k].spin then
				local s = 1 + 0.14 * math.abs(math.sin(t * 6)) * (1 - t / 2.5)
				cell:SetSize(CELL * s, CELL * s)
			elseif not self.reels[k].spin then
				drawReel(self.reels[k])
			end
		end
		-- the big-win pop-up: pops in, pulses, fades
		if self.bigWin:IsShown() then
			local s = t < 0.25 and (0.3 + 0.9 * t / 0.25) or (1.05 + 0.05 * math.sin(t * 8))
			self.bigWin:SetScale(s)
			self.bigWin.text:SetTextColor(hue(h0 * 4 + t, 0.5, 1))
			self.bigWin.glow:SetVertexColor(hue(h0 * 4 + t + 0.5))
			self.bigWin:SetAlpha(t < 2.6 and 1 or math.max(0, 1 - (t - 2.6) / 0.5))
			if t > 3.1 then self.bigWin:Hide() end
		end
	end
	-- the paytable: the entry the last spin landed on stays lit
	if self.payEntries then
		local pulse = st.payAt and math.max(0, 1 - (now - st.payAt) / 1.5) or 0
		for key, e in pairs(self.payEntries) do
			if key == st.payHit then
				local cr, cg, cb = hue(h0 * 2)
				e:SetBackdropBorderColor(cr, cg, cb, 1)
				e:SetBackdropColor(0.35 + 0.4 * pulse, 0.1 + 0.3 * pulse, 0.45, 0.85)
			else
				e:SetBackdropBorderColor(0.5, 0.4, 1, 0.35)
				e:SetBackdropColor(0, 0, 0, 0.45)
			end
		end
	end
	-- sparks
	if st.burstAt then
		local bt = now - st.burstAt
		for i, sp in ipairs(self.sparks) do
			local u = math.min(1, bt / (0.8 + 0.04 * i))
			local rad = 60 + 170 * (1 - (1 - u) * (1 - u))
			sp:ClearAllPoints()
			sp:SetPoint("CENTER", self.reelHolder, "CENTER", math.cos(sp.ang) * rad, math.sin(sp.ang) * rad * 0.7)
			local sz = 26 + 24 * math.sin(math.pi * math.min(1, u * 1.2))
			sp:SetSize(sz, sz)
			sp:SetAlpha(u < 1 and (1 - u) or 0)
		end
		if bt > 2 then st.burstAt = nil; for _, sp in ipairs(self.sparks) do sp:SetAlpha(0) end end
	end
	-- coin shower (7-7-7)
	if st.coinsAt then
		local t = now - st.coinsAt
		local any = false
		for _, c in ipairs(self.coins) do
			local tt = t - c.delay
			if tt > 0 then
				local y = c.vy + 420 * tt * tt
				if y < 560 then
					any = true
					local face = math.abs(math.cos(tt * c.spin))
					c:SetSize(c.size, math.max(2, c.size * face))
					c:ClearAllPoints()
					c:SetPoint("CENTER", self.frame, "TOPLEFT", c.x, -y)
					c:SetAlpha(1)
				else c:SetAlpha(0) end
			end
		end
		if not any and t > 1 then st.coinsAt = nil end
	end
	self:Tick()
end

---------------------------------------------------------------------------
-- state -> widgets
---------------------------------------------------------------------------
function UI:Tick()
	local g = ns.Client.game
	if not (self.frame and g) then return end
	local sl = g.sl
	if sl and sl.deadline and ns.Client:CanSpin() then
		local left = math.max(0, math.ceil(sl.deadline - GetTime()))
		self.timer:SetText((left <= 5 and "|cffff6161" or "|cffece3cc") .. left .. "s|r")
	else
		self.timer:SetText("")
	end
	self.turnGlow:Update(ns.ClientUI.MyTurn())
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local g = ns.Client.game
	if not g or g.type ~= "slots" then
		self.title:SetText("Battle Slots")
		self.sub:SetText("You're not at a slots table.")
		self.banner:SetText("")
		self.prompt:SetText("")
		self.leave:SetEnabled(false)
		for _, r in ipairs(self.rows) do r:Hide() end
		self.pop:Hide()
		return
	end
	sync(g)
	ns.Client:SetLeaveButton(self.leave, g, g.phase == "open")
	local n = #(g.players or {})
	local pot = (g.wager or 0) * math.max(n, 1)
	self.title:SetText((ns.TestTag(g) .. "Battle Slots  %s |cffaaaaaaante|r   Pot %s"):format(ns.Money(g.wager or 0), ns.Money(pot)))
	local sl, d = g.sl, g.dice
	local seated = ns.IndexOf(g.players or {}, ns.me) and not g.watching
	local sub
	if g.phase == "aborted" then sub = "|cffff6161Table cancelled.|r"
	elseif g.phase == "open" then sub = "Waiting for the house to start..."
	elseif g.phase == "commit" or (g.phase == "reveal" and not sl) then sub = "Loading the machines..."
	elseif sl and d and d.done then sub = "Finished"
	elseif sl and st.spinoff and not st.finished then sub = "|cffffd100SPIN-OFF!|r Tied at the top - one more spin each."
	elseif sl and sl.final then sub = "Everyone's in..."
	elseif sl and seated and sl.mine < 3 then sub = sl.busy and "Spinning..." or ("|cff4dffffYour pull!|r  Spin " .. (sl.mine + 1) .. " of 3")
	elseif sl then sub = seated and "Your spins are in - waiting for the table..." or "Players are spinning..."
	else sub = "" end
	self.sub:SetText(sub)
	-- the prompt under the screen
	local can = ns.Client:CanSpin()
	if can then self.prompt:SetText("Grab the lever and pull it down  >>")
	elseif sl and seated and sl.busy then self.prompt:SetText("")
	elseif g.watching then self.prompt:SetText("|cffaaaaaaWatching|r")
	else self.prompt:SetText("") end
	-- spin pips and the read-out on the screen
	for k = 1, 3 do
		local used = sl and seated and k <= sl.mine
		self.pips[k]:SetVertexColor(used and 0.3 or 0.35, used and 1 or 0.3, used and 1 or 0.45)
		self.pips[k]:SetAlpha(used and 1 or 0.5)
	end
	self.pipLabel:SetText(seated and "SPINS" or "")
	local myBest
	if seated and sl then
		local sp = spinsOf(g, ns.me)
		local best = -1
		for k = 1, math.min(st.revealed[ns.me] or 0, sl.mine) do
			local s, name = SL.Eval(sp[k])
			if s > best then best, myBest = s, name end
		end
	end
	self.readout:SetText(("POT %s%s"):format(ns.Money(pot), myBest and ("   BEST " .. myBest:upper()) or ""))
	if not st.spinLabel and seated and sl then self.reelLabel:SetText(sl.mine < 3 and ("Spin " .. (sl.mine + 1) .. " of 3") or "") end

	-- the table panel
	local stand = sl and standings(g) or {}
	local leader
	for _, p in ipairs(g.players or {}) do
		local l = stand[p]
		if l and #l > 0 then
			if not leader then leader = p else
				local a, b = stand[p], stand[leader]
				for i = 1, 3 do
					local x, y = a[i] or -1, b[i] or -1
					if x ~= y then if x > y then leader = p end break end
				end
			end
		end
	end
	local winners = {}
	if d and d.done and g.result and g.result.slots then for _, w in ipairs(g.result.slots.winners) do winners[w] = true end end
	local net = (d and d.done and g.result) and ns.Games.Net(g, g.result) or {}
	for i, row in ipairs(self.rows) do
		local p = g.players and g.players[i]
		if p then
			row:Show()
			local you = p == ns.me
			row.name:SetText(ns.Who(p) .. (you and " |cff4dffff(you)|r" or "") .. (winners[p] and "  |cffffd100WINNER|r" or ""))
			local sp, nrev = spinsOf(g, p), st.revealed[p] or 0
			if you and sl then nrev = math.min(nrev, sl.mine) end
			local bestK, bestS = nil, -1
			for k = 1, 3 do
				local box = row.spins[k]
				local shown = sp and k <= nrev
				for j = 1, 3 do
					local ic = box.icons[j]
					if shown then
						ic:SetTexCoord(cellTC(SYMCELL[sp[k][j]]))
						ic:Show()
					else
						ic:Hide()
					end
				end
				local spinningNow = sl and ((sl.spun[p] or 0) >= k) and not shown
				box.wait:SetText(shown and "" or (spinningNow and "|cff4dffff...|r" or "-"))
				if shown then
					local s = SL.Eval(sp[k])
					if s > bestS then bestS, bestK = s, k end
				end
			end
			for k = 1, 3 do
				local box = row.spins[k]
				local isBest = k == bestK
				local fl = st.flash and st.flash[p .. ":" .. k]
				local glow = fl and math.max(0, 1 - (GetTime() - fl) / 1.2) or 0
				if isBest then box:SetBackdropBorderColor(1, 0.85, 0.2, 1)
				else box:SetBackdropBorderColor(0.3, 1, 1, 0.3 + 0.6 * glow) end
			end
			if bestK then
				local _, name = SL.Eval(sp[bestK])
				row.best:SetText(name)
			else
				row.best:SetText("")
			end
			local hn = net[p]
			if hn and hn ~= 0 then row.best:SetText((hn > 0 and ("|cff59d959+" .. ns.Money(hn)) or ("|cffff6161-" .. ns.Money(-hn))) .. "|r") end
			local lead = (winners[p] or (not next(winners) and leader == p))
			W.Backdrop(row, lead and { 0.35, 0.08, 0.40, 0.7 } or { 1, 1, 1, 0.04 },
				lead and { 1, 0.3, 0.9, 1 } or { 0.5, 0.4, 1, 0.3 }, lead and 2 or 1)
		else
			row:Hide()
		end
	end

	-- result
	local res = g.result
	if res and d and d.done then
		local delta = seated and (g.delta or 0) or nil
		self.banner:SetText((res.summary or "") .. (delta and delta ~= 0 and ("   You " .. ns.WonLost(delta)) or ""))
		if g.id and not g.review then self.pop:Play("slots:" .. g.id, delta, res.summary) end
	else
		self.banner:SetText("")
	end
	self:Tick()
end

function UI:Init() end
