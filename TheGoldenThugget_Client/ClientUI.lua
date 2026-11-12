-- The Golden Thugget: the player window (Tables + Ledger).
local _, ns = ...
if ns.skip then return end
local W = ns.W
local C_ = W.C

---------------------------------------------------------------------------
-- Client window
---------------------------------------------------------------------------
local UI = {}
ns.ClientUI = UI
local backlog = {}
local WIDTH = 528

-- small game icon: the die for dice games, a card back for card games
function UI.GameIcon(parent, size)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetSize(size, size)
	function t:SetGame(gtype)
		local def = ns.Games.types[gtype]
		if def and def.ui == "hand" then
			self:SetTexture(ns.MEDIA .. "d6")
			self:SetTexCoord(4 * 64 / 512, 5 * 64 / 512, 0, 1)
			self:SetSize(size, size)
		elseif def and def.kind == "cards" then
			self:SetTexture(ns.MEDIA .. "cards")
			self:SetTexCoord(ns.Cards.TexCoord(nil))
			self:SetSize(size * 0.72, size)
		else
			self:SetTexture(ns.MEDIA .. "die")
			self:SetTexCoord(0, 1, 0, 1)
			self:SetSize(size, size)
		end
	end
	return t
end

---------------------------------------------------------------------------
-- Table status: label + color, shown as a badge and a bar down the row's left edge
---------------------------------------------------------------------------
local STATUS = {
	open = { "OPEN", C_.green },
	live = { "IN PROGRESS", C_.gold },
	closed = { "CLOSED", C_.muted },
	cancelled = { "CANCELLED", C_.red },
}
UI.STATUS = STATUS

function UI.Badge(parent)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(84, 16)
	b.text = W.Text(b, 9, C_.text)
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetJustifyH("CENTER")
	function b:SetStatus(s)
		local st = STATUS[s] or STATUS.closed
		local c = st[2]
		self.text:SetText(st[1])
		self.text:SetTextColor(c[1], c[2], c[3])
		W.Backdrop(self, { c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.95 }, { c[1], c[2], c[3], 0.85 })
	end
	return b
end

function UI.StatusBar(parent, w)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", 1, -1)
	t:SetPoint("BOTTOMLEFT", 1, 1)
	t:SetWidth(w)
	function t:SetStatus(s)
		local c = (STATUS[s] or STATUS.closed)[2]
		self:SetColorTexture(c[1], c[2], c[3], 0.9)
	end
	return t
end

-- A button spot that can show a filled (main action) or outlined button
function UI.Slot(parent, w, h)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(w, h)
	s.gold = W.Button(s, "", w, h, "gold")
	s.plain = W.Button(s, "", w, h)
	s.gold:SetAllPoints()
	s.plain:SetAllPoints()
	-- act = { text, onClick, enabled, tooltip, gold } or nil (hidden)
	function s:Set(act)
		if not act then self:Hide() return end
		self:Show()
		local b = act[5] and self.gold or self.plain
		local other = act[5] and self.plain or self.gold
		other:Hide()
		b:Show()
		b:SetText(act[1])
		b:SetScript("OnClick", act[2])
		b:SetEnabled(act[3] and true or false)
		b.tip = act[4]
		b.Paint(false)
	end
	return s
end

---------------------------------------------------------------------------
-- Leaderboard tab (shared with the house window)
---------------------------------------------------------------------------
local RANK = { { 1, 0.84, 0.30 }, { 0.80, 0.82, 0.86 }, { 0.80, 0.52, 0.28 } }

function UI.BuildBoard(parent, width)
	local b = {}
	local tw = math.floor((width - 16) / 3)
	local function tile(i, caption)
		local p = W.Panel(parent, tw, 62)
		p:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
		p.cap = W.Text(p, 10, C_.muted)
		p.cap:SetPoint("TOPLEFT", 10, -8)
		p.cap:SetText(caption:upper())
		p.name = W.Text(p, 13, C_.gold)
		p.name:SetPoint("TOPLEFT", 10, -24)
		p.name:SetWidth(tw - 20)
		p.val = W.Text(p, 12, C_.text)
		p.val:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -3)
		return p
	end
	b.top = tile(1, "Top winner")
	b.bottom = tile(2, "Biggest loser")
	b.most = tile(3, "Most games")

	local sec = W.Section(parent, "Lifetime standings", width)
	sec:SetPoint("TOPLEFT", 2, -76)
	local cols = { { "#", 10 }, { "PLAYER", 40 }, { "NET", width - 300 }, { "W-L", width - 196 }, { "GAMES", width - 136 }, { "BEST", width - 74 } }
	for _, c in ipairs(cols) do
		local h = W.Text(parent, 10, C_.muted)
		h:SetPoint("TOPLEFT", c[2], -96)
		h:SetText(c[1])
	end
	local area = CreateFrame("Frame", nil, parent)
	area:SetPoint("TOPLEFT", 0, -112)
	area:SetSize(width, 11 * 26)
	b.rows = W.RowList(area, 11, 26, function(row)
		row.rank = W.Text(row, 13, C_.muted)
		row.rank:SetPoint("LEFT", 10, 0)
		row.name = W.Text(row, 12, C_.text)
		row.name:SetPoint("LEFT", 40, 0)
		row.name:SetWidth(width - 350)
		row.net = W.Text(row, 13, C_.text)
		row.net:SetPoint("LEFT", width - 300, 0)
		row.wl = W.Text(row, 12, C_.text)
		row.wl:SetPoint("LEFT", width - 196, 0)
		row.games = W.Text(row, 12, C_.text)
		row.games:SetPoint("LEFT", width - 136, 0)
		row.best = W.Text(row, 12, C_.green)
		row.best:SetPoint("LEFT", width - 74, 0)
	end, width)
	b.empty = W.Text(parent, 12, C_.muted)
	b.empty:SetPoint("TOPLEFT", 12, -122)
	b.empty:SetText("No games in the book yet.")
	b.foot = W.Text(parent, 10, C_.muted)
	b.foot:SetPoint("BOTTOMLEFT", 2, 0)
	b.foot:SetWidth(width)
	return b
end

function UI.FillBoard(b, list, asOf)
	local function setTile(t, r, val)
		if r then t.name:SetText(ns.Who(r.name)); t.val:SetText(val) else t.name:SetText("-"); t.val:SetText("") end
	end
	local most, bottom
	for _, r in ipairs(list) do
		if not most or r.played > most.played then most = r end
		if r.net < 0 and (not bottom or r.net < bottom.net) then bottom = r end
	end
	local top = list[1] and list[1].net > 0 and list[1] or nil
	setTile(b.top, top, top and W.Signed(top.net) or "")
	setTile(b.bottom, bottom, bottom and W.Signed(bottom.net) or "")
	setTile(b.most, most, most and (most.played .. " games") or "")
	b.rows:Update(list, function(row, r)
		local i
		for k, x in ipairs(list) do if x == r then i = k break end end
		local col = RANK[i]
		row.rank:SetText(i)
		if col then row.rank:SetTextColor(col[1], col[2], col[3]) else row.rank:SetTextColor(C_.muted[1], C_.muted[2], C_.muted[3]) end
		local me = r.name == ns.me
		row.name:SetText(ns.Who(r.name) .. (me and "  |cffd9b545(you)|r" or ""))
		row.net:SetText(W.Signed(r.net))
		row.wl:SetText(r.won .. "-" .. r.lost)
		row.games:SetText(r.played)
		row.best:SetText(r.best > 0 and ("+" .. ns.Money(r.best)) or "-")
	end)
	b.empty:SetShown(#list == 0)
	b.foot:SetText("Game results only; payments to and from the house don't count." ..
		(asOf and ("   Updated " .. asOf) or "") .. (#list > 11 and "   Scroll for more." or ""))
end

function UI:Build()
	if self.frame then return end
	local f = W.Window("GoldenThuggetFrame", "The Golden Thugget", "Player", 560, 560)
	self.frame = f
	f:SetScript("OnShow", function() UI:Refresh(); ns.Client:RequestLedger() end)
	local _, panels = W.Tabs(f, { "Tables", "Ledger", "Leaderboard", "Activity" })
	-- the house's copy of the player window: a button back to the house window
	if ns.HostUI then
		local house = W.Button(f, "House", 80, 22, "gold")
		house:SetPoint("TOPRIGHT", -34, -10)
		house:SetScript("OnClick", function() ns.HostUI:SwitchToHouse() end)
		W.Tooltip(house, "Back to the house window (table control, Bank).")
		self.houseBtn = house
	end
	f.OnTab = function(i) if i == 2 or i == 3 then ns.Client:RequestLedger() end UI:Refresh() end
	local play, led, act = panels[1], panels[2], panels[4]
	self.board = UI.BuildBoard(panels[3], WIDTH)

	-------------------------------------------------------- Tables
	self.hostLine = W.Text(play, 12, C_.muted)
	self.hostLine:SetPoint("TOPLEFT", 2, 0)
	self.hostLine:SetWidth(WIDTH - 130)
	self.quietBtn = W.Button(play, "", 120, 20)
	self.quietBtn:SetPoint("TOPRIGHT", 0, 2)
	self.quietBtn:SetScript("OnClick", function() ns.Client:SetQuiet(not ns.db.settings.quiet) end)
	W.Tooltip(self.quietBtn, "Quiet: only your turns, results and warnings go to chat. Everything else still shows on the Activity tab.")

	-- the latest table: the one you're at, else the newest open one, else the newest
	local s0 = W.Section(play, "Latest table", WIDTH)
	s0:SetPoint("TOPLEFT", 2, -28)
	local card = W.Panel(play, WIDTH, 96)
	card:SetPoint("TOPLEFT", 0, -46)
	self.top = card
	card.bar = UI.StatusBar(card, 4)
	card.icon = UI.GameIcon(card, 40)
	card.icon:SetPoint("LEFT", 18, 0)
	card.title = W.Text(card, 15, C_.gold)
	card.title:SetPoint("TOPLEFT", 70, -14)
	card.badge = UI.Badge(card)
	card.badge:SetPoint("LEFT", card.title, "RIGHT", 10, 0)
	card.detail = W.Text(card, 11, C_.text)
	card.detail:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -7)
	card.detail:SetWidth(WIDTH - 210)
	card.detail:SetSpacing(3)
	card.a = UI.Slot(card, 112, 26)
	card.a:SetPoint("TOPRIGHT", -12, -14)
	card.b = UI.Slot(card, 112, 24)
	card.b:SetPoint("TOPRIGHT", card.a, "BOTTOMRIGHT", 0, -6)
	card.empty = W.Text(card, 12, C_.muted)
	card.empty:SetPoint("LEFT", 18, 0)
	card.empty:SetWidth(WIDTH - 40)
	card.empty:SetText("No tables yet. When the house opens one, it shows up here.")

	-- everything else, newest first
	local s1 = W.Section(play, "Earlier tables", WIDTH)
	s1:SetPoint("TOPLEFT", 2, -156)
	local area = CreateFrame("Frame", nil, play)
	area:SetPoint("TOPLEFT", 0, -174)
	area:SetSize(WIDTH, 7 * 40)
	self.lobby = W.RowList(area, 7, 40, function(row)
		row.bar = UI.StatusBar(row, 3)
		row.icon = UI.GameIcon(row, 24)
		row.icon:SetPoint("LEFT", 14, 0)
		row.name = W.Text(row, 13, C_.gold)
		row.name:SetPoint("TOPLEFT", 46, -5)
		row.badge = UI.Badge(row)
		row.badge:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.detail = W.Text(row, 11, C_.muted)
		row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
		row.detail:SetWidth(WIDTH - 220)
		row.detail:SetWordWrap(false)
		row.a = UI.Slot(row, 78, 24)
		row.a:SetPoint("RIGHT", -8, 0)
		row.b = UI.Slot(row, 78, 24)
		row.b:SetPoint("RIGHT", row.a, "LEFT", -6, 0)
	end, WIDTH)
	self.lobbyEmpty = W.Text(play, 12, C_.muted)
	self.lobbyEmpty:SetPoint("TOPLEFT", 12, -186)
	self.lobbyEmpty:SetText("Earlier tables from this session show up here.")
	self.lobbyMore = W.Text(play, 10, C_.muted)
	self.lobbyMore:SetPoint("BOTTOMLEFT", 2, 0)

	-------------------------------------------------------- Activity
	self.log = W.Log(act, WIDTH, 440)
	self.log.box:SetPoint("TOPLEFT", 0, 0)

	-------------------------------------------------------- Ledger
	local bal = W.Panel(led, WIDTH, 74)
	bal:SetPoint("TOPLEFT", 0, 0)
	self.myBal = W.Text(bal, 18, C_.text)
	self.myBal:SetPoint("TOPLEFT", 14, -14)
	self.myBal:SetWidth(320)
	self.asOf = W.Text(bal, 11, C_.muted)
	self.asOf:SetPoint("TOPLEFT", self.myBal, "BOTTOMLEFT", 0, -6)
	local pay = W.Button(bal, "Pay the house", 120, 26, "gold")
	pay:SetPoint("TOPRIGHT", -12, -12)
	pay:SetScript("OnClick", function() ns.Client:PayHost() end)
	W.Tooltip(pay, "At a mailbox (Send Mail tab): fills in a mail to the house for what you owe. The subject is tagged with your name, so paying from an alt still credits you.")
	self.payBtn = pay
	local rf = W.Button(bal, "Refresh", 120, 24)
	rf:SetPoint("TOPRIGHT", pay, "BOTTOMRIGHT", 0, -6)
	rf:SetScript("OnClick", function() ns.Client:RequestLedger(true) end)

	local s3 = W.Section(led, "Everyone", WIDTH)
	s3:SetPoint("TOPLEFT", 2, -88)
	local area2 = CreateFrame("Frame", nil, led)
	area2:SetPoint("TOPLEFT", 0, -106)
	area2:SetSize(WIDTH, 7 * 26)
	self.everyone = W.RowList(area2, 7, 26, function(row)
		row.name = W.Text(row, 12, C_.text)
		row.name:SetPoint("LEFT", 12, 0)
		row.name:SetWidth(240)
		row.amt = W.Text(row, 12, C_.text)
		row.amt:SetPoint("RIGHT", -12, 0)
		row.amt:SetJustifyH("RIGHT")
		row.amt:SetWidth(240)
	end, WIDTH)
	self.everyoneEmpty = W.Text(led, 12, C_.muted)
	self.everyoneEmpty:SetPoint("TOPLEFT", 12, -116)
	self.everyoneEmpty:SetText("No ledger from the house yet.")

	local s4 = W.Section(led, "Your history", WIDTH)
	s4:SetPoint("TOPLEFT", 2, -296)
	self.hist = W.Log(led, WIDTH, 148)
	self.hist.box:SetPoint("TOPLEFT", 0, -314)

	for _, line in ipairs(backlog) do self.log:AddMessage(line) end
	backlog = {}
end

-- The window module for a game: DiceUI, HandUI, CardUI or HoldemUI
function UI.WindowFor(g)
	local def = g and ns.Games.types[g.type]
	if not def then return end
	if def.ui == "hand" then return ns.HandUI
	elseif def.ui == "holdem" then return ns.HoldemUI
	elseif def.kind == "cards" then return ns.CardUI end
	return ns.DiceUI
end

-- Is the table waiting on *you* right now? Returns true, deadline (or nil).
-- One answer for every game, used by each window's red glow and the turn alert.
function UI.MyTurn()
	local C = ns.Client
	local g = C and C.game
	if not g or g.watching or g.closeAt or g.phase == "aborted" then return end
	local def = ns.Games.types[g.type]
	if not def then return end
	local c = g.cards
	if g.type == "holdem" then
		local he = c and c.he
		local st = he and he.st
		if st and st.toAct == ns.me and not he.acted and not he.result and he.deadline then return true, he.deadline end
		return
	end
	if def.ui == "hand" then
		if ns.CardClient and (ns.CardClient:CanYRoll() or ns.CardClient:CanStand()) then return true, c and c.deadline end
		return
	end
	if g.type == "guts" then
		if c and c.phase == "decide" and c.myHand and not c.myDecision and ns.IndexOf(c.seats, ns.me) then return true, c.deadline end
		return
	end
	if g.type == "acey" then
		local t = c and c.turn
		if t and t.player == ns.me and c.phase == "bet" and not c.betSent then return true, c.deadline end
		return
	end
	if def.kind ~= "cards" and C:CanRoll() then
		local d = g.dice
		return true, g.awaitRoll and g.rollDeadline or (d and d.deadline)
	end
end

---------------------------------------------------------------------------
-- Your-turn alert: when the table needs you and its window is closed, a red
-- card at the top of the screen with a Show table button.
---------------------------------------------------------------------------
function UI:TurnAlert()
	local mine, deadline = UI.MyTurn()
	local w = mine and UI.WindowFor(ns.Client.game)
	local hidden = w and not (w.frame and w.frame:IsShown())
	local t = self.turnToast
	if not hidden then
		if t and t:IsShown() then t:Hide() end
		return
	end
	if not t then
		t = CreateFrame("Button", "GoldenThuggetTurnToast", UIParent, "BackdropTemplate")
		t:SetSize(320, 58)
		t:SetPoint("TOP", 0, -190)
		t:SetFrameStrata("DIALOG")
		t:SetToplevel(true)
		W.Backdrop(t, { 0.10, 0.03, 0.03, 1 }, C_.red, 2)
		t.icon = UI.GameIcon(t, 30)
		t.icon:SetPoint("LEFT", 12, 0)
		t.title = W.Text(t, 14, C_.gold)
		t.title:SetPoint("TOPLEFT", 52, -11)
		t.title:SetWidth(170)
		t.detail = W.Text(t, 11, C_.text)
		t.detail:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
		t.detail:SetWidth(170)
		t.show = W.Button(t, "Show table", 84, 26, "gold")
		t.show:SetPoint("RIGHT", -10, 0)
		t.show:SetScript("OnClick", function() t:Hide(); ns.Client:OpenTable() end)
		t:SetScript("OnClick", function() t:Hide(); ns.Client:OpenTable() end)
		t:SetScript("OnUpdate", function(self)
			local pulse = math.abs(math.sin(GetTime() * 3))
			self:SetBackdropBorderColor(1, 0.25 * pulse, 0.25 * pulse, 0.6 + 0.4 * pulse)
		end)
		self.turnToast = t
	end
	local g = ns.Client.game
	t.icon:SetGame(g.type)
	t.title:SetText("Your turn - " .. ns.Games.types[g.type].name)
	local left = deadline and math.max(0, math.ceil(deadline - GetTime()))
	t.detail:SetText(left and ((left <= 5 and "|cffff6161" or "") .. left .. "s left|r") or "The table is waiting on you")
	if not t:IsShown() then
		t:Show()
		W.Sound({ "RAID_WARNING", "READY_CHECK" })
	end
end

function UI:ShowTableWindow()
	local g = ns.Client.game
	local def = g and ns.Games.types[g.type]
	if def and def.ui == "hand" then ns.HandUI:Toggle()
	elseif def and def.ui == "holdem" then ns.HoldemUI:Toggle()
	elseif g and g.cards then ns.CardUI:Toggle()
	else ns.DiceUI:Toggle() end
end

---------------------------------------------------------------------------
-- New-table toast: a small card at the top of the screen when the house opens
-- a table and the main window is closed (/gt alerts to turn off)
---------------------------------------------------------------------------
function UI:Toast(a)
	if ns.db.settings.alerts == false then return end
	if self.frame and self.frame:IsShown() then return end
	local t = self.toast
	if not t then
		t = CreateFrame("Frame", "GoldenThuggetToast", UIParent, "BackdropTemplate")
		t:SetSize(380, 64)
		t:SetPoint("TOP", 0, -120)
		t:SetFrameStrata("DIALOG")
		t:SetToplevel(true)
		-- everything sits on the panel: a child frame draws over its parent's text
		local pnl = W.Panel(t, 380, 64)
		pnl:SetAllPoints()
		t.icon = UI.GameIcon(pnl, 34)
		t.icon:SetPoint("LEFT", 12, 0)
		t.title = W.Text(pnl, 13, C_.gold)
		t.title:SetPoint("TOPLEFT", 56, -12)
		t.title:SetWidth(214)
		t.detail = W.Text(pnl, 11, C_.muted)
		t.detail:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
		t.detail:SetWidth(214)
		t.join = W.Button(pnl, "Join", 64, 24, "gold")
		t.join:SetPoint("RIGHT", -34, 0)
		t.join:SetScript("OnClick", function()
			local id = t.id
			t:Hide()
			if id then ns.Client:Join(id) end
		end)
		t.close = W.Button(pnl, "x", 22, 22)
		t.close:SetPoint("TOPRIGHT", -6, -6)
		t.close:SetScript("OnClick", function() t:Hide() end)
		-- how long the invite stays up
		t.bar = pnl:CreateTexture(nil, "OVERLAY")
		t.bar:SetPoint("BOTTOMLEFT", 1, 1)
		t.bar:SetHeight(3)
		t.bar:SetColorTexture(C_.gold[1], C_.gold[2], C_.gold[3], 0.9)
		t:SetScript("OnUpdate", function(self)
			local left = math.max(0, 1 - (GetTime() - (self.shownAt or 0)) / 30)
			self.bar:SetWidth(math.max(1, 378 * left))
		end)
		self.toast = t
	end
	local def = ns.Games.types[a.type]
	t.id = a.id
	t.icon:SetGame(a.type)
	t.title:SetText(("New table: %s  %s%s"):format(def.name, ns.Money(a.wager), def.wagerLabel and (" " .. def.wagerLabel:lower()) or def.kind == "cards" and " ante" or ""))
	local block = ns.Client:JoinBlock(a)
	local seats = a.max and ("   |cff9e948a%d/%d seated|r"):format(a.count or 0, a.max) or ""
	t.detail:SetText(block and "|cffff6161" .. (a.outdated and "Update needed" or "Over your credit limit") .. "|r"
		or ("Max loss %s%s%s"):format(ns.Money(ns.Games.WorstCase(a)), ns.Games.PerHand(a) and " a hand" or "", seats))
	W.Fit(t.title, 214, 1)
	W.Fit(t.detail, 214, 1)
	t.join:SetEnabled(not block)
	t:Show()
	t.shownAt = GetTime()
	local at = t.shownAt
	C_Timer.After(30, function() if t.shownAt == at then t:Hide() end end)
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE then pcall(PlaySound, SOUNDKIT.IG_PLAYER_INVITE) end
end

function UI:HideToast(id)
	if self.toast and (not id or self.toast.id == id) then self.toast:Hide() end
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else
		self.frame:Show()
		self:HideToast()
		ns.Client:RequestHistory() -- fill in tables from before this session
	end
end

function UI:Log(msg)
	local line = "|cff9e948a" .. date("%H:%M") .. "|r  " .. msg
	if self.log then self.log:AddMessage(line) else
		backlog[#backlog + 1] = line
		if #backlog > 100 then table.remove(backlog, 1) end
	end
end

local function ago(t)
	if not t then return "" end
	local m = math.floor((time() - t) / 60)
	if m < 1 then return "just now" end
	if m < 60 then return m .. "m ago" end
	return math.floor(m / 60) .. "h ago"
end

local SEP = "   -   "

-- What the buttons on a table do, by its status and whether you're at it
function UI:Actions(r)
	local C = ns.Client
	local g = C.game
	if g and g.id == r.id and C:Busy() then
		local canShow = g.cards ~= nil or ns.Games.types[g.type].kind ~= "cards"
		local show = { "Show table", function() C:OpenTable() end, canShow, nil, true }
		if not C:Active() then return show end -- result's in, dice still rolling
		if g.watching and r.status == "open" then -- take a seat straight from watching
			local la = C.lobby[r.id]
			local block = la and C:JoinBlock(la)
			local full = la and la.count >= la.max
			return { "Join", function() C:Join(r.id) end, la and not full and not block, block or (full and "The table is full.") or nil, true },
				{ "Stop watching", function() C:Leave() end, true }
		end
		return show, { g.watching and "Stop watching" or "Leave", function() C:Leave() end, true }
	end
	local a = C.lobby[r.id]
	local busy = C:Playing() ~= nil
	local function watch()
		local canWatch = a and (not a.houseVersion or ns.VersionAtLeast(a.houseVersion, ns.WATCH_SINCE))
		local tip = "Follow the table without playing. You see what the players see in public, never anyone's private cards or dice."
		if a and not canWatch then tip = ("The house is on %s. Watching needs %s or newer."):format(a.houseVersion or "?", ns.WATCH_SINCE) end
		if busy then tip = "You're playing at another table." end
		return { "Watch", function() C:Watch(r.id) end, canWatch and not busy, tip }
	end
	if r.status == "open" then
		local block = a and C:JoinBlock(a)
		local full = a and a.count >= a.max
		return { "Join", function() C:Join(r.id) end, a and not busy and not full and not block, block or (busy and "You're already at a table.") or (full and "The table is full.") or nil, true },
			watch()
	elseif r.status == "live" then
		return watch()
	elseif r.status == "closed" then
		if r.fetching then return { "Loading...", function() end, false, "Getting this table from the house." } end
		local can = r.game ~= nil or C:CanFetch(r)
		local tip
		if not can then
			tip = (C.houseVersion and not ns.VersionAtLeast(C.houseVersion, ns.REVIEW_SINCE))
				and ("The house is on %s. Reviewing tables you didn't see needs %s or newer."):format(C.houseVersion, ns.REVIEW_SINCE)
				or "The house no longer has this table. It keeps the last 20."
		elseif C:Busy() then tip = "Finish or leave your current table first."
		elseif not r.game then tip = "Get this table from the house and reopen it as it ended."
		end
		return { "Review", function() C:Review(r.id) end, can and not C:Busy(), tip or "Reopen the table as it ended." }
	end
end

function UI:Detail(r, full)
	local C = ns.Client
	local route = ns.ROUTE_LABEL[r.route] or "?"
	local g = C.game
	local mine = g and g.id == r.id and C:Busy()
	local a = C.lobby[r.id]
	local eyes = ((a and a.watchers) or r.watchers or 0) > 0 and (SEP .. ((a and a.watchers) or r.watchers) .. " watching") or ""
	if r.status == "open" then
		local count, max = (a and a.count) or r.count or #r.players, (a and a.max) or r.max or 2
		local line = ("%s%s%d/%d seated"):format(route, SEP, count, max)
		if mine then
			line = line .. SEP .. (g.watching and "|cff9e948ayou're watching|r" or "|cffd9b545you're seated - waiting for the house to start|r")
		elseif a then
			local block = C:JoinBlock(a)
			line = line .. (a.direct and (SEP .. "|cffd9b545invited|r") or "") .. (a.outdated and (SEP .. "|cffff6161update needed|r") or
				(block and (SEP .. "|cffff6161over credit limit|r")) or (SEP .. ("max loss %s%s"):format(ns.Money(ns.Games.WorstCase(a)), ns.Games.PerHand(a) and " a hand" or "")))
		end
		if full and #r.players > 0 then line = line .. "\nPlayers: " .. ns.ShortList(r.players) end
		return line .. (full and "" or eyes)
	elseif r.status == "live" then
		local n = #r.players > 0 and #r.players or (a and a.count) or 0
		local line = ("%s%s%d playing%s"):format(route, SEP, n, eyes)
		if mine then
			local what = g.watching and "|cff9e948aYou're watching.|r" or "|cffd9b545You're playing.|r"
			if g.awaitRoll then what = "|cffd9b545Your roll! Open the table and click Roll.|r"
			elseif UI.MyTurn() then what = "|cffff6161Your turn!|r |cffd9b545Open the table.|r" end
			line = line .. (full and "\n" or SEP) .. what
		end
		if full and #r.players > 0 then line = line .. "\nPlayers: " .. ns.ShortList(r.players) end
		return line
	elseif r.status == "closed" then
		local res = r.summary and ("|cff59d959" .. r.summary:gsub("^%l", string.upper) .. "|r") or "Finished"
		local you = (r.mine and r.delta) and (r.delta == 0 and "You broke even" or ("You " .. ns.WonLost(r.delta)))
			or (r.mine and "You played") or (r.watched and "|cff9e948awatched|r") or nil
		if full then
			return res .. "\n" .. route .. ((#r.players > 0) and (SEP .. ns.ShortList(r.players)) or "") ..
				SEP .. ago(r.endedAt) .. (you and ("\n" .. you) or "")
		end
		return (you and (you .. SEP) or "") .. res .. SEP .. ago(r.endedAt)
	else
		return "Cancelled" .. (r.reason and (": " .. r.reason) or "") .. SEP .. ago(r.endedAt)
	end
end

function UI:FillTable(w, r, full)
	local def = ns.Games.types[r.type]
	w.icon:SetGame(r.type)
	w.icon:SetAlpha((r.status == "closed" or r.status == "cancelled") and 0.6 or 1)
	local title = ("%s  %s%s"):format(def.name, ns.Money(r.wager or 0), def.wagerLabel and (" |cffece3cc" .. def.wagerLabel:lower() .. "|r") or def.kind == "cards" and " |cffece3ccante|r" or "")
	if w.name then w.name:SetText(title) else w.title:SetText(title) end
	w.badge:SetStatus(r.status)
	w.bar:SetStatus(r.status)
	w.detail:SetText(self:Detail(r, full))
	local a1, a2 = self:Actions(r)
	w.a:Set(a1)
	w.b:Set(a2)
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local C = ns.Client
	local host = C:Host()

	-- Tables
	if host == ns.me then
		self.hostLine:SetText("|cffd9b545You are the house.|r  Run tables from /gth.")
	else
		self.hostLine:SetText("House: " .. (host and ("|cffd9b545" .. ns.Short(host) .. "|r") or "|cffff6161not set|r  (/gt host First Last)"))
	end
	self.quietBtn:SetText(ns.db.settings.quiet and "Chat: Quiet" or "Chat: Full")
	local list = C:TableList()
	local top = list[1]
	local card = self.top
	if top then
		card.empty:Hide()
		card.icon:Show(); card.title:Show(); card.badge:Show(); card.detail:Show(); card.bar:Show()
		self:FillTable(card, top, true)
	else
		card.empty:Show()
		card.icon:Hide(); card.title:Hide(); card.badge:Hide(); card.detail:Hide(); card.bar:Hide()
		card.a:Set(nil); card.b:Set(nil)
	end
	local rest = {}
	for i = 2, #list do rest[#rest + 1] = list[i] end
	self.lobby:Update(rest, function(row, r) UI:FillTable(row, r, false) end)
	self.lobbyEmpty:SetShown(#rest == 0)
	self.lobbyMore:SetText(#rest > 7 and "Scroll for more." or "")

	-- Ledger
	local cache = C:Cache()
	local bal = cache.balances[ns.me] or 0
	if bal > 0 then self.myBal:SetText("The house owes you |cff59d959" .. ns.Money(bal) .. "|r")
	elseif bal < 0 then self.myBal:SetText("You owe the house |cffff6161" .. ns.Money(-bal) .. "|r")
	else self.myBal:SetText("You're square with the house") end
	self.asOf:SetText(cache.ts > 0 and ("Ledger as of " .. date("%m/%d %H:%M", cache.ts)) or "No ledger received yet")
	self.payBtn:SetEnabled(bal < 0 and host ~= ns.me)

	local list = C:SortedBalances()
	self.everyone:Update(list, function(row, b)
		local me = b.name == ns.me
		row.name:SetText(ns.Who(b.name) .. (me and "  |cffd9b545(you)|r" or ""))
		row.amt:SetText(C:BalanceText(b.c))
	end)
	self.everyoneEmpty:SetShown(#list == 0)

	UI.FillBoard(self.board, cache.board or {}, cache.boardTs and cache.boardTs > 0 and date("%m/%d %H:%M", cache.boardTs) or nil)

	self.hist:Clear()
	local lines = cache.history or {}
	if #lines > 0 then
		for i = #lines, 1, -1 do self.hist:AddMessage(ns.ColorCoins(lines[i])) end -- host sends newest first
	else
		for _, m in ipairs(C:MyGames()) do -- local record of your own tables, oldest first
			self.hist:AddMessage("|cff9e948a" .. date("%m/%d %H:%M", m.t) .. "|r  " .. (m.summary or ""))
		end
	end
end

function UI:Init()
	table.insert(ns.logSinks, function(msg) UI:Log(msg) end)
	C_Timer.NewTicker(0.25, function() UI:TurnAlert() end)
end
