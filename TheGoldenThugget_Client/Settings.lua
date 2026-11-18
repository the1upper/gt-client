-- The Golden Thugget: the Settings window (the gear on the main and house
-- windows, or /gt settings). Every switch here also has a chat command.
local _, ns = ...
if ns.skip then return end
local W = ns.W
local C = W.C
local UI = {}
ns.SettingsUI = UI

local function S() return ns.db.settings end
local function H() return ns.hdb and ns.hdb.settings end

---------------------------------------------------------------------------
-- a gold checkbox with a label (and an optional muted note under it)
---------------------------------------------------------------------------
local function check(parent, label, note, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(270, note and 34 or 22)
	local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
	box:SetSize(16, 16)
	box:SetPoint("TOPLEFT", 0, -3)
	W.Backdrop(box, { 0.03, 0.025, 0.025, 1 }, C.goldDim)
	local tick = box:CreateTexture(nil, "ARTWORK")
	tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	tick:SetPoint("CENTER", 1, 0)
	tick:SetSize(20, 20)
	local fs = W.Text(b, 12, C.text)
	fs:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, -1)
	fs:SetText(label)
	if note then
		local n = W.Text(b, 10, C.muted)
		n:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
		W.Fit(n, 240, 1)
		n:SetText(note)
		b.note = n
	end
	b.label, b.box, b.tick = fs, box, tick
	function b:Update()
		local on = get() and true or false
		self.on = on
		self.tick:SetShown(on)
		local en = not self.parentCheck or self.parentCheck.on
		self:SetEnabled(en)
		self:SetAlpha(en and 1 or 0.45)
	end
	b:SetScript("OnClick", function(self)
		set(not self.on)
		UI:Refresh()
	end)
	b:SetScript("OnEnter", function() box:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end)
	b:SetScript("OnLeave", function() box:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1) end)
	return b
end

UI.Check = check

-- a labelled text box that applies on Enter (or when it loses focus)
local function field(parent, label, w, get, apply, tip)
	local fs = W.Text(parent, 12, C.text)
	fs:SetText(label)
	local e = W.EditBox(parent, w)
	e:SetPoint("LEFT", fs, "LEFT", 96, 0)
	local function commit()
		local v = (e:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if v ~= (get() or "") then apply(v) end
		e:SetText(get() or "")
	end
	e:SetScript("OnEnterPressed", function() commit(); e:ClearFocus() end)
	e:SetScript("OnEscapePressed", function() e:SetText(get() or ""); e:ClearFocus() end)
	e:HookScript("OnEditFocusLost", commit)
	if tip then W.Tooltip(e, tip) end
	fs.edit, fs.get = e, get
	return fs
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
function UI:Build()
	if self.frame then return end
	local house = H() ~= nil
	local f = W.Window("GoldenThuggetSettings", "Settings", "Sounds, pop-ups and more.  /gt help lists every command.", 620, house and 575 or 510)
	f:SetFrameStrata("DIALOG")
	self.frame = f
	f:SetScript("OnShow", function() UI:Refresh() end)
	local checks, fields = {}, {}
	self.checks, self.fields = checks, fields
	local function add(c) checks[#checks + 1] = c; return c end

	local L, R, TOP = 18, 322, -84
	local function section(x, y, text)
		local s = W.Section(f, text, 280)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end

	------------------------------------------------ left: sound
	section(L, TOP, "Sound")
	local master = add(check(f, "Sounds", "Every sound the casino makes", function() return S().sound ~= false end,
		function(v) S().sound = v end))
	master:SetPoint("TOPLEFT", L, TOP - 22)
	local y = TOP - 60
	for _, o in ipairs({
		{ "soundAlerts", "Table alerts", "Invites, your turn, double or nothing" },
		{ "soundGame", "Game sounds", "Dice, cards, chips, the coin and the reels" },
		{ "soundResults", "Win and lose", "Your results, slot wins, the jackpot" },
	}) do
		local key = o[1]
		local c = add(check(f, o[2], o[3], function() return S()[key] ~= false end, function(v) S()[key] = v end))
		c:SetPoint("TOPLEFT", L + 18, y)
		c.parentCheck = master
		y = y - 36
	end
	local mc = add(check(f, "Play through Master volume", "Heard even with sound effects turned down",
		function() return S().soundChannel == "Master" end, function(v) S().soundChannel = v and "Master" or nil end))
	mc:SetPoint("TOPLEFT", L + 18, y)
	mc.parentCheck = master
	y = y - 40
	local test = W.Button(f, "Test sounds", 110, 22)
	test:SetPoint("TOPLEFT", L + 18, y)
	test:SetScript("OnClick", function() ns.Sound.Test() end)
	W.Tooltip(test, "Plays every sound once, a beat apart (/gt sound test).")

	------------------------------------------------ left: pop-ups
	y = y - 40
	section(L, y, "Pop-ups")
	y = y - 22
	for _, o in ipairs({
		{ "alerts", "New table card", "Join button, 30s, when a table opens" },
		{ "watchAlerts", "Game starting card", "Watch button, 15s, for tables you skipped" },
		{ "turnAlerts", "Your-turn card", "Your move while the table window is closed" },
	}) do
		local key = o[1]
		local c = add(check(f, o[2], o[3], function() return S()[key] ~= false end, function(v) S()[key] = v end))
		c:SetPoint("TOPLEFT", L, y)
		y = y - 36
	end

	------------------------------------------------ right: chat & display
	y = TOP
	section(R, y, "Chat and display")
	y = y - 22
	local quiet = add(check(f, "Quiet chat", "Only turns, results and warnings in chat",
		function() return S().quiet end, function(v) ns.Client:SetQuiet(v) end))
	quiet:SetPoint("TOPLEFT", R, y)
	y = y - 36
	local coins = add(check(f, "Money as letters", "1g 50s instead of coin icons",
		function() return S().coinText end, function(v) ns.SetCoinText(v) end))
	coins:SetPoint("TOPLEFT", R, y)
	y = y - 36
	local mm = add(check(f, "Minimap button", "The GT coin on your minimap",
		function() return S().minimap ~= false end, function(v) ns.Minimap:Slash(v and "on" or "off") end))
	mm:SetPoint("TOPLEFT", R, y)
	y = y - 40
	local reset = W.Button(f, "Reset window positions", 170, 22)
	reset:SetPoint("TOPLEFT", R, y)
	reset:SetScript("OnClick", function() ns.W.ResetPositions(); ns.Notify("Window positions reset.") end)

	------------------------------------------------ right: the house connection
	y = y - 44
	section(R, y, "Connection")
	y = y - 30
	local hf = field(f, "House", 180, function() return S().host end, function(v)
		if v == "" then return end
		S().host = v
		ns.Print("Host set to " .. v .. ".")
		ns.Client:RequestLedger(true)
	end, "The player who runs the casino. Only their tables and ledger are trusted (/gt host).")
	hf:SetPoint("TOPLEFT", R, y)
	fields[#fields + 1] = hf
	y = y - 32
	local cf = field(f, "Channel", 180, function() return S().channel end, function(v)
		if v == "" or v:find("%s") then return end
		ns.Comm:LeaveChannel()
		S().channel = v
		ns.Comm:EnsureChannel()
		ns.Print("Custom channel: " .. v)
	end, "Must match the house's channel (/gt channel).")
	cf:SetPoint("TOPLEFT", R, y)
	fields[#fields + 1] = cf

	------------------------------------------------ the house (host build only)
	if house then
		y = y - 44
		section(R, y, "The house")
		y = y - 22
		local dn = add(check(f, "Offer double or nothing", "After one-on-one results",
			function() return H().offerDouble ~= false end, function(v) H().offerDouble = v end))
		dn:SetPoint("TOPLEFT", R, y)
		y = y - 36
		local auto = add(check(f, "Record trades and mail", "Trade and mail gold, without asking",
			function() return H().autoApply end, function(v) H().autoApply = v end))
		auto:SetPoint("TOPLEFT", R, y)
		y = y - 44
		local lf = field(f, "Credit limit", 120, function()
			local c = H().creditLimit or 0
			return c > 0 and ns.MoneyPlain(c) or "off"
		end, function(v)
			local low = v:lower()
			if low == "off" or low == "0" then H().creditLimit = 0
			else
				local c = ns.ParseMoney(v:gsub("%s", ""))
				if not c then return ns.Print("Credit limit: type an amount like 50g, or off.") end
				H().creditLimit = c
			end
			if ns.HostUI then ns.HostUI:Refresh() end
		end, "How much a player may owe the house, counting the worst case of the table they join. 'off' for no limit (/gth limit).")
		lf:SetPoint("TOPLEFT", R, y)
		fields[#fields + 1] = lf
		y = y - 32
		local tf = field(f, "Testers", 180, function() return table.concat(ns.Host:Testers(), ", ") end, function(v)
			local list = ns.Host:Testers()
			wipe(list)
			for _, n in ipairs(ns.NameList(v)) do list[#list + 1] = n end
			ns.Print(#list > 0 and ("Testers: " .. table.concat(list, ", ")) or "Tester list cleared.")
			if ns.HostUI then ns.HostUI:Refresh() end
		end, "Who hears about tables sent to Testers (the Where menu, or /gth open ... testers). Full names, separated by commas.")
		tf:SetPoint("TOPLEFT", R, y)
		fields[#fields + 1] = tf
	end

	local done = W.Button(f, "Done", 100, 26, "gold")
	done:SetPoint("BOTTOMRIGHT", -16, 14)
	done:SetScript("OnClick", function() f:Hide() end)
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	for _, c in ipairs(self.checks) do c:Update() end
	for _, fs in ipairs(self.fields) do
		if not fs.edit:HasFocus() then fs.edit:SetText(fs.get() or "") end
	end
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self.frame:Raise() end
end

-- the little gear for a window's header band: a flat gold gear in the same
-- dark, gold-edged button as Rules and the other header buttons
function UI.Gear(parent)
	local b = W.Button(parent, "", 24, 22)
	local t = b:CreateTexture(nil, "OVERLAY")
	t:SetTexture(ns.MEDIA .. "gear")
	t:SetSize(16, 16)
	t:SetPoint("CENTER")
	t:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
	b.icon = t
	b:HookScript("OnEnter", function() t:SetVertexColor(1, 0.89, 0.47) end)
	b:HookScript("OnLeave", function() t:SetVertexColor(C.gold[1], C.gold[2], C.gold[3]) end)
	b:SetScript("OnMouseDown", function() t:SetPoint("CENTER", 1, -1) end)
	b:SetScript("OnMouseUp", function() t:SetPoint("CENTER") end)
	b:SetScript("OnClick", function() UI:Toggle() end)
	W.Tooltip(b, "Settings: sounds, pop-ups, chat, the minimap button and more.")
	return b
end
