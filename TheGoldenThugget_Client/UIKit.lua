-- The Golden Thugget: UI kit — the casino look shared by every window.
-- Dark panels, gold trim, burgundy header band with the house crest, flat
-- gold-underlined tabs, gold-outlined buttons, striped rows.
local _, ns = ...
if ns.skip then return end
local W = {}
ns.W = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
W.FONT = FONT
W.C = {
	bg = { 0.055, 0.045, 0.045, 1 },
	panel = { 0.10, 0.075, 0.07, 1 },
	band = { 0.24, 0.035, 0.075, 1 },
	gold = { 0.86, 0.71, 0.27 },
	goldDim = { 0.52, 0.42, 0.16 },
	text = { 0.93, 0.89, 0.80 },
	muted = { 0.62, 0.58, 0.52 },
	green = { 0.35, 0.85, 0.35 },
	red = { 1, 0.38, 0.38 },
	felt = { 0.05, 0.30, 0.16, 1 }, -- solid: nothing behind may show through
}
local C = W.C

local function backdrop(f, bg, border, edge)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
	f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
W.Backdrop = backdrop

---------------------------------------------------------------------------
-- text
---------------------------------------------------------------------------
function W.Text(parent, size, color, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 12, flags or "")
	local c = color or C.text
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetJustifyH("LEFT")
	return fs
end

-- Keep a text inside its box: wrap, at most `lines` lines, cut with "..." after.
function W.Fit(fs, width, lines)
	if width then fs:SetWidth(width) end
	fs:SetWordWrap(true)
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
	if lines and fs.SetMaxLines then fs:SetMaxLines(lines) end
	fs:SetJustifyV("TOP")
	return fs
end

-- legacy helper (font object based), still used in a few places
function W.Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
	fs:SetText(text or "")
	fs:SetJustifyH("LEFT")
	return fs
end

-- "OPEN TABLES ———————"
function W.Section(parent, text, width)
	local fs = W.Text(parent, 11, C.gold, "")
	fs:SetText(text:upper())
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.7)
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetWidth(math.max(10, (width or 520) - (fs:GetStringWidth() or 80) - 10))
	fs.line = line
	return fs
end

---------------------------------------------------------------------------
-- buttons: "gold" (filled) for the main action, default is outlined
---------------------------------------------------------------------------
function W.Button(parent, text, w, h, style)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w or 90, h or 24)
	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, (h or 24) >= 30 and 14 or 12, "")
	fs:SetPoint("CENTER", 0, 0)
	b:SetFontString(fs)
	b:SetText(text or "")
	local gold = style == "gold"
	-- disabled buttons still show their tooltip (it says why they're disabled)
	if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
	local function paint(hover)
		if not b:IsEnabled() then
			backdrop(b, { 0.12, 0.11, 0.10, 0.9 }, { 0.3, 0.27, 0.22, 0.9 })
			fs:SetTextColor(0.45, 0.42, 0.38)
		elseif gold then
			local k = hover and 1.08 or 1
			backdrop(b, { C.gold[1] * k, C.gold[2] * k, C.gold[3] * k, 1 }, { 1, 0.9, 0.55, 1 })
			fs:SetTextColor(0.15, 0.06, 0.02)
		else
			backdrop(b, hover and { 0.24, 0.16, 0.10, 0.95 } or { 0.15, 0.10, 0.08, 0.95 }, hover and C.gold or C.goldDim)
			fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		end
	end
	b.Paint = paint
	b:SetScript("OnEnter", function(self)
		if self:IsEnabled() then paint(true) end
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() paint(false); GameTooltip:Hide() end)
	b:SetScript("OnEnable", function() paint(false) end)
	b:SetScript("OnDisable", function() paint(false) end)
	b:SetScript("OnMouseDown", function() if b:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end end)
	b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
	paint(false)
	return b
end

function W.Tooltip(widget, text)
	if widget.Paint then widget.tip = text return end -- styled buttons show it themselves
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- inputs and panels
---------------------------------------------------------------------------
function W.EditBox(parent, w)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(w, 24)
	backdrop(e, { 0.03, 0.025, 0.025, 0.95 }, C.goldDim)
	e:SetFont(FONT, 12, "")
	e:SetTextColor(C.text[1], C.text[2], C.text[3])
	e:SetTextInsets(7, 7, 0, 0)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function() e:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end)
	e:SetScript("OnEditFocusLost", function() e:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1) end)
	return e
end

function W.Panel(parent, w, h)
	local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	p:SetSize(w, h)
	backdrop(p, C.panel, { C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.6 })
	return p
end

function W.Log(parent, w, h)
	local box = W.Panel(parent, w, h)
	local m = CreateFrame("ScrollingMessageFrame", nil, box)
	m:SetPoint("TOPLEFT", 8, -6)
	m:SetPoint("BOTTOMRIGHT", -8, 6)
	m:SetFont(FONT, 11, "")
	m:SetTextColor(C.text[1], C.text[2], C.text[3])
	m:SetJustifyH("LEFT")
	m:SetFading(false)
	m:SetMaxLines(300)
	m:EnableMouseWheel(true)
	m:SetScript("OnMouseWheel", function(self, delta) if delta > 0 then self:ScrollUp() else self:ScrollDown() end end)
	m.box = box
	-- anchor helpers act on the visible box
	function m:SetBoxPoint(...) box:SetPoint(...) end
	return m
end

---------------------------------------------------------------------------
-- crest + windows
---------------------------------------------------------------------------
W.LOGO = ns.MEDIA .. "logo"
function W.Logo(parent, width, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(W.LOGO)
	t:SetTexCoord(0, 1, 39 / 512, 472 / 512)
	t:SetSize(width, width * 433 / 512)
	return t
end

---------------------------------------------------------------------------
-- Remembered positions: drag a window and it opens there next time
-- (saved per character; /gt resetpos puts them all back).
---------------------------------------------------------------------------
local remembered = {} -- key -> { frame, default point }
local function positions() return ns.db and ns.db.settings and ns.db.settings.pos end

function W.Remember(f, key)
	remembered[key] = { f = f, home = { f:GetPoint() } }
	local pos = positions()
	local p = pos and pos[key]
	if p then
		f:ClearAllPoints()
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end -- ours, not WoW's layout cache
		local point, _, rel, x, y = self:GetPoint()
		local store = positions()
		if store and point then store[key] = { point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
end

function W.ResetPositions()
	local pos = positions()
	if pos then for k in pairs(pos) do pos[k] = nil end end
	for _, r in pairs(remembered) do
		local h = r.home
		r.f:ClearAllPoints()
		r.f:SetPoint(h[1] or "CENTER", UIParent, h[3] or h[1] or "CENTER", h[4] or 0, h[5] or 0)
	end
end

-- Casino window: header band with crest, title and subtitle. Content starts at y = -84.
function W.Window(globalName, title, subtitle, w, h)
	local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	-- main windows live one layer below the table windows (DIALOG), so a table
	-- window is never drawn through by a main window's panels and buttons
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	backdrop(f, C.bg, C.goldDim, 2)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, globalName)
	f:Hide()
	tinsert(UISpecialFrames, globalName)

	local band = f:CreateTexture(nil, "BORDER")
	band:SetPoint("TOPLEFT", 2, -2)
	band:SetPoint("TOPRIGHT", -2, -2)
	band:SetHeight(66)
	band:SetColorTexture(C.band[1], C.band[2], C.band[3], 1)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
	rule:SetHeight(2)
	rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)

	local crest = W.Logo(f, 70)
	crest:SetPoint("TOPLEFT", 12, -5)
	local t = W.Text(f, 20, C.gold, "")
	t:SetPoint("TOPLEFT", 94, -14)
	t:SetText(title)
	local st = W.Text(f, 11, C.muted)
	st:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 1, -4)
	st:SetText(subtitle or "")
	f.title, f.subtitle = t, st

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	return f
end

-- Flat tabs along the right of the header band; returns tabs, panels, show(i)
function W.Tabs(f, names, contentTop)
	local tabs, panels = {}, {}
	contentTop = contentTop or -84
	local function paint(i, active)
		local b = tabs[i]
		b.text:SetTextColor(active and C.gold[1] or C.muted[1], active and C.gold[2] or C.muted[2], active and C.gold[3] or C.muted[3])
		b.under:SetShown(active)
	end
	local tabW = (#names >= 4 and 90) or (#names > 2 and 104) or 96
	for i, name in ipairs(names) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(tabW, 26)
		b.text = W.Text(b, 13, C.muted)
		b.text:SetPoint("CENTER", 0, 1)
		b.text:SetText(name)
		b.under = b:CreateTexture(nil, "OVERLAY")
		b.under:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
		b.under:SetHeight(2)
		b.under:SetPoint("BOTTOMLEFT", 10, 0)
		b.under:SetPoint("BOTTOMRIGHT", -10, 0)
		if i == 1 then b:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -36 - (#names - 1) * (tabW + 4), -66)
		else b:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0) end
		b:SetScript("OnEnter", function() if not b.active then b.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
		b:SetScript("OnLeave", function() paint(i, b.active) end)
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", 16, contentTop)
		p:SetPoint("BOTTOMRIGHT", -16, 14)
		tabs[i], panels[i] = b, p
	end
	local function show(i)
		for k = 1, #names do
			tabs[k].active = (k == i)
			paint(k, k == i)
			if k == i then panels[k]:Show() else panels[k]:Hide() end
		end
	end
	for i, b in ipairs(tabs) do b:SetScript("OnClick", function() show(i); if f.OnTab then f.OnTab(i) end end) end
	show(1)
	return tabs, panels, show
end

-- Mouse-wheel list of rows with zebra striping.
function W.RowList(parent, count, height, build, width)
	width = width or 528
	local list = { rows = {}, offset = 0, items = {} }
	for i = 1, count do
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(width, height - 2)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * height)
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0.07)
		row.bg = bg
		build(row)
		list.rows[i] = row
	end
	function list:Update(items, fill)
		self.items, self.fill = items or self.items, fill or self.fill
		local maxOff = math.max(0, #self.items - count)
		if self.offset > maxOff then self.offset = maxOff end
		for i, row in ipairs(self.rows) do
			local item = self.items[i + self.offset]
			if item then self.fill(row, item); row:Show() else row:Hide() end
		end
	end
	for _, row in ipairs(list.rows) do
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function(_, delta)
			list.offset = math.max(0, list.offset - delta)
			list:Update()
		end)
	end
	return list
end

---------------------------------------------------------------------------
-- Dropdown: a casino-styled select box.
--   items = { { value=, text=, note=, icon=function(tex) end }, { header = "Dice" }, ... }
--   dd:SetValue(v), dd:GetValue(), dd.onSelect(value)
---------------------------------------------------------------------------
local openMenu
local blocker -- full-screen click catcher that closes an open menu

local function closeMenu()
	if openMenu then openMenu:Hide(); openMenu = nil end
	if blocker then blocker:Hide() end
end
W.CloseMenus = closeMenu

function W.Dropdown(parent, width, items, onSelect)
	local dd = W.Button(parent, "", width, 26)
	dd.items, dd.onSelect = items, onSelect
	local fs = dd:GetFontString()
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", 10, 0)
	fs:SetPoint("RIGHT", -24, 0)
	fs:SetJustifyH("LEFT")
	local arrow = dd:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -6, -3)
	arrow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])

	local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	backdrop(menu, { 0.07, 0.05, 0.05, 1 }, C.gold)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	dd.menu = menu
	menu.rows = {}

	local function build()
		for _, r in ipairs(menu.rows) do r:Hide() end
		local y, i = -4, 0
		for _, it in ipairs(dd.items) do
			i = i + 1
			local r = menu.rows[i]
			if not r then
				r = CreateFrame("Button", nil, menu)
				r.hl = r:CreateTexture(nil, "BACKGROUND")
				r.hl:SetAllPoints()
				r.hl:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.18)
				r.hl:Hide()
				r.icon = r:CreateTexture(nil, "ARTWORK")
				r.icon:SetPoint("LEFT", 8, 0)
				r.text = W.Text(r, 12, C.text)
				r.note = W.Text(r, 10, C.muted)
				r.note:SetJustifyH("RIGHT")
				r.note:SetPoint("RIGHT", -8, 0)
				r:SetScript("OnEnter", function(self) if self.value ~= nil then self.hl:Show() end end)
				r:SetScript("OnLeave", function(self) self.hl:Hide() end)
				r:SetScript("OnClick", function(self)
					if self.value == nil then return end
					closeMenu()
					dd:SetValue(self.value)
					if dd.onSelect then dd.onSelect(self.value) end
				end)
				menu.rows[i] = r
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 4, y)
			r:SetPoint("TOPRIGHT", -4, y)
			r.text:ClearAllPoints()
			if it.header then
				r:SetHeight(20)
				r.value = nil
				r.icon:Hide()
				r.note:SetText("")
				r.text:SetPoint("LEFT", 6, -2)
				r.text:SetFont(FONT, 10, "")
				r.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
				r.text:SetText(it.header:upper())
				y = y - 20
			else
				r:SetHeight(24)
				r.value = it.value
				if it.icon then r.icon:Show(); it.icon(r.icon); r.text:SetPoint("LEFT", 34, 0) else r.icon:Hide(); r.text:SetPoint("LEFT", 10, 0) end
				r.text:SetFont(FONT, 12, "")
				local sel = it.value == dd.value
				local c = sel and C.gold or C.text
				r.text:SetTextColor(c[1], c[2], c[3])
				r.text:SetText(it.text)
				r.note:SetText(it.note or "")
				y = y - 24
			end
			r:Show()
		end
		menu:SetSize(math.max(width, dd.menuWidth or width), -y + 4)
	end

	function dd:SetItems(list) self.items = list; if menu:IsShown() then build() end end
	function dd:SetValue(v)
		self.value = v
		for _, it in ipairs(self.items) do
			if it.value == v then self:SetText(it.label or it.text) end
		end
	end
	function dd:GetValue() return self.value end
	function dd:Open()
		closeMenu()
		build()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
		if not blocker then
			blocker = CreateFrame("Button", nil, UIParent)
			blocker:SetAllPoints(UIParent)
			blocker:SetFrameStrata("FULLSCREEN")
			blocker:SetScript("OnClick", closeMenu)
		end
		blocker:Show()
		menu:Show()
		openMenu = menu
	end
	dd:SetScript("OnClick", function(self)
		if menu:IsShown() then closeMenu() else self:Open() end
	end)
	dd:HookScript("OnHide", function() if openMenu == menu then closeMenu() end end)
	return dd
end

---------------------------------------------------------------------------
-- "Rules" button + overlay for a table window. getType() returns the game.
---------------------------------------------------------------------------
function W.RulesButton(frame, getType)
	local b = W.Button(frame, "Rules", 64, 22)
	local p = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	p:SetPoint("TOPLEFT", 14, -68)
	p:SetPoint("BOTTOMRIGHT", -14, 14)
	backdrop(p, { 0.06, 0.04, 0.04, 1 }, C.gold)
	p:SetFrameLevel(frame:GetFrameLevel() + 40)
	p:EnableMouse(true)
	p:Hide()
	p.title = W.Text(p, 16, C.gold)
	p.title:SetPoint("TOPLEFT", 16, -14)
	p.text = W.Text(p, 12, C.text)
	p.text:SetPoint("TOPLEFT", 16, -42)
	p.text:SetPoint("RIGHT", -16, 0)
	p.text:SetJustifyV("TOP")
	p.text:SetSpacing(3)
	local ok = W.Button(p, "Got it", 100, 26, "gold")
	ok:SetPoint("BOTTOMRIGHT", -14, 12)
	ok:SetScript("OnClick", function() p:Hide() end)
	b:SetScript("OnClick", function()
		if p:IsShown() then return p:Hide() end
		local t = getType()
		local def = t and ns.Games.types[t]
		if not def then return end
		p.title:SetText(def.name .. " - how to play")
		p.text:SetText(ns.Games.Rules(t))
		p:Show()
	end)
	b.panel = p
	return b
end

-- Small stat tile: caption over a big value
function W.Stat(parent, w, caption)
	local p = W.Panel(parent, w, 54)
	p.cap = W.Text(p, 10, C.muted)
	p.cap:SetPoint("TOPLEFT", 10, -8)
	p.cap:SetText(caption:upper())
	p.val = W.Text(p, 17, C.text)
	p.val:SetPoint("BOTTOMLEFT", 10, 9)
	return p
end

-- Grey hint text inside an empty edit box (the value used if you leave it empty)
function W.Placeholder(box, text)
	if not box.ph then
		box.ph = box:CreateFontString(nil, "OVERLAY")
		box.ph:SetFont(FONT, 12, "")
		box.ph:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 0.8)
		box.ph:SetPoint("LEFT", 8, 0)
		box.ph:SetPoint("RIGHT", -6, 0)
		box.ph:SetJustifyH("LEFT")
		box.ph:SetWordWrap(false)
		box:HookScript("OnTextChanged", function(b) b.ph:SetShown(b:GetText() == "") end)
	end
	box.ph:SetText(text or "")
	box.ph:SetShown(box:GetText() == "")
end

-- Money colored for a balance from the player's point of view
function W.Signed(c)
	if c > 0 then return "|cff59d959+|r" .. ns.Money(c) end
	if c < 0 then return "|cffff6161-|r" .. ns.Money(-c) end
	return "|cff9e948a" .. "even" .. "|r"
end

---------------------------------------------------------------------------
-- Your-turn glow: a thick red halo round a table window (layers fading
-- outward) plus a solid red ring just inside its edge. Pulses; faster and
-- brighter in the last 5 seconds. glow:Update(on, deadline) every frame.
---------------------------------------------------------------------------
function W.TurnGlow(f)
	local rings = {}
	local function ring(out, size, alpha, inside)
		local r = CreateFrame("Frame", nil, f, "BackdropTemplate")
		r:SetPoint("TOPLEFT", -out, out)
		r:SetPoint("BOTTOMRIGHT", out, -out)
		r:SetFrameLevel(inside and (f:GetFrameLevel() + 20) or math.max(0, f:GetFrameLevel() - 1))
		r:SetBackdrop({ edgeFile = WHITE, edgeSize = size })
		r.alpha = alpha
		r:EnableMouse(false)
		r:Hide()
		rings[#rings + 1] = r
	end
	ring(24, 8, 0.18)      -- outer haze
	ring(16, 8, 0.35)
	ring(8, 8, 0.6)
	ring(0, 6, 1)          -- right on the window edge
	ring(-7, 4, 0.9, true) -- inside the border, over the felt's edge
	function rings:Update(on, deadline)
		if on then
			local hurry = deadline and (deadline - GetTime() <= 5)
			local pulse = math.abs(math.sin(GetTime() * (hurry and 7 or 3)))
			local a = hurry and (0.55 + 0.45 * pulse) or (0.45 + 0.55 * pulse)
			local gb = hurry and (0.25 * pulse) or 0.08
			for _, r in ipairs(self) do
				r:SetBackdropBorderColor(1, gb, gb, r.alpha * a)
				if not r:IsShown() then r:Show() end
			end
		elseif self[1]:IsShown() then
			for _, r in ipairs(self) do r:Hide() end
		end
	end
	return rings
end

---------------------------------------------------------------------------
-- Result pop: a card that rises over the felt when a hand/table ends.
--   pop:Play(key, delta, line)  delta = your win (+) / loss (-) in copper, nil
--   when you weren't playing. The amount counts up, winners get a coin burst,
--   each outcome has its own sound. Plays once per key; click to dismiss.
---------------------------------------------------------------------------
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local function sound(names, fallback)
	if ns.hush or not PlaySound then return end
	for _, n in ipairs(names) do
		if SOUNDKIT and SOUNDKIT[n] then pcall(PlaySound, SOUNDKIT[n]) return end
	end
	if fallback then pcall(PlaySound, fallback) end
end
W.Sound = sound

function W.ResultPop(f, yOffset, w, h)
	local p = CreateFrame("Button", nil, f, "BackdropTemplate")
	p:SetSize(w or 340, h or 104)
	p:SetPoint("CENTER", 0, yOffset or 0)
	p:SetFrameLevel(f:GetFrameLevel() + 35) -- over the table, under the Rules overlay
	p:Hide()
	p.head = W.Text(p, 12, C.text)
	p.head:SetPoint("TOP", 0, -12)
	p.head:SetJustifyH("CENTER")
	p.amount = W.Text(p, 30, C.gold, "THICKOUTLINE")
	p.amount:SetPoint("TOP", p.head, "BOTTOM", 0, -4)
	p.amount:SetJustifyH("CENTER")
	p.line = W.Text(p, 11, C.text)
	p.line:SetPoint("BOTTOM", 0, 10)
	p.line:SetJustifyH("CENTER")
	W.Fit(p.line, (w or 340) - 24, 2)
	p.line:SetJustifyV("BOTTOM")
	p.coins = {}
	for i = 1, 10 do
		local t = p:CreateTexture(nil, "OVERLAY")
		t:SetTexture(COIN)
		t:SetSize(16, 16)
		t:Hide()
		p.coins[i] = t
	end
	p:SetScript("OnClick", function(self) self:Hide(); self:Next() end)
	p.queue = {}

	local function money(c) return ns.Money(c) end
	local HOLD = 4.5 -- seconds on screen before it fades
	p:SetScript("OnUpdate", function(self)
		local t = GetTime() - self.t0
		-- fade in, count up, hold, fade out
		local a = t < 0.15 and t / 0.15 or (t > HOLD and math.max(0, 1 - (t - HOLD) / 0.6) or 1)
		self:SetAlpha(a)
		if a <= 0 and t > HOLD then self:Hide(); self:Next() return end
		if self.delta and self.delta ~= 0 then
			local k = math.min(1, t / 0.7)
			k = 1 - (1 - k) * (1 - k)
			local v = math.floor(math.abs(self.delta) * k + 0.5)
			if v ~= self.shown then
				self.shown = v
				self.amount:SetText((self.delta > 0 and "|cff59d959+|r" or "|cffff6161-|r") .. money(v))
			end
		end
		-- the border flashes for the first second
		local flash = t < 1 and (0.5 + 0.5 * math.abs(math.sin(t * 9))) or 1
		local c = self.color
		self:SetBackdropBorderColor(c[1], c[2], c[3], flash)
		-- coin burst
		for i, coin in ipairs(self.coins) do
			if self.burst and t < 1.4 then
				local ang = (i / #self.coins) * 6.283 + 0.3
				local d = 30 + 120 * math.min(1, t / 1.1)
				coin:ClearAllPoints()
				coin:SetPoint("CENTER", self.amount, "CENTER", math.cos(ang) * d * 1.3, math.sin(ang) * d * 0.55 + 40 * t - 30 * t * t)
				coin:SetAlpha(math.max(0, 1 - t / 1.4))
				if not coin:IsShown() then coin:Show() end
			elseif coin:IsShown() then
				coin:Hide()
			end
		end
	end)

	-- a result that arrives while another is still being read waits its turn
	function p:Next()
		local q = table.remove(self.queue, 1)
		if q then self:Play(q[1], q[2], q[3], true) end
	end
	function p:Play(key, delta, line, fromQueue)
		if key and key == self.key then return end
		if not fromQueue then
			for _, q in ipairs(self.queue) do if q[1] == key then return end end
			if self:IsShown() and self.t0 and GetTime() - self.t0 < 2.5 then
				self.queue[#self.queue + 1] = { key, delta, line }
				return
			end
		end
		self.key = key
		self.delta, self.shown = delta, nil
		local won, lost = delta and delta > 0, delta and delta < 0
		self.color = won and C.green or lost and C.red or C.gold
		backdrop(self, { 0.04, 0.03, 0.03, 1 }, { self.color[1], self.color[2], self.color[3], 1 }, 2)
		if delta == nil then
			self.head:SetText("|cffd4af37RESULT|r")
			self.amount:SetText("")
		elseif delta == 0 then
			self.head:SetText("|cff9e948aYOU BROKE EVEN|r")
			self.amount:SetText("|cff9e948aPush|r")
		else
			self.head:SetText(won and "|cff59d959YOU WON|r" or "|cffff6161YOU LOST|r")
			self.amount:SetText((won and "|cff59d959+|r" or "|cffff6161-|r") .. money(0))
		end
		self.line:SetText(line or "")
		self.burst = won
		self.t0 = GetTime()
		self:SetAlpha(0)
		self:Show()
		if won then sound({ "LOOT_WINDOW_COIN_SOUND", "IG_BACKPACK_COIN_OK" }, 120)
		elseif lost then sound({ "IG_QUEST_FAILED", "IG_QUEST_LOG_ABANDON_QUEST" }, 847) end
	end
	-- forget the last result (new table): the next one plays even with the same key
	function p:Reset() self.key = nil; self.queue = {}; self:Hide() end
	return p
end
