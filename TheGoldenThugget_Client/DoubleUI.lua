-- The Golden Thugget: the double-or-nothing prompt. When a table ends with one
-- player owing one other, both get this: YES / NO with a 12-second fuse. Both
-- yes and a Coin Flip for the same amount starts right away (the loser calls).
local _, ns = ...
if ns.skip then return end
local UI = {}
ns.DoubleUI = UI
local W = ns.W
local C_ = W.C
local COIN = ns.MEDIA .. "coin"
local TITLE_Y = -68
-- three bounces, each lower than the last, then still
local BOUNCES = { { 0.34, 16 }, { 0.26, 8 }, { 0.18, 3 } }

function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetDoubleFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(380, 230)
	f:SetPoint("CENTER", 0, 140)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	W.Backdrop(f, { 0.05, 0.03, 0.02, 0.97 }, C_.gold, 3)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	W.Remember(f, "GoldenThuggetDoubleFrame")
	f:Hide()

	-- a gold glow and a coin turning slowly behind the title
	self.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.glow:SetTexture(COIN)
	self.glow:SetTexCoord(0.75, 1, 0.5, 0.75)
	self.glow:SetBlendMode("ADD")
	self.glow:SetSize(260, 160)
	self.glow:SetPoint("TOP", 0, 30)
	self.glow:SetAlpha(0.45)
	self.coin = f:CreateTexture(nil, "ARTWORK")
	self.coin:SetTexture(COIN)
	self.coin:SetTexCoord(0, 0.5, 0, 0.5)
	self.coin:SetSize(54, 54)
	self.coin:SetPoint("CENTER", f, "TOP", 0, -37) -- turns in place

	-- the title drops in, bounces three times and settles (easy to read)

	self.title = W.Text(f, 24, C_.gold, "THICKOUTLINE")
	self.title:SetPoint("TOP", 0, TITLE_Y)
	self.title:SetText("DUB OR NUT?")
	self.body = W.Text(f, 12, C_.text)
	self.body:SetPoint("TOP", self.title, "BOTTOM", 0, -8)
	self.body:SetJustifyH("CENTER")
	W.Fit(self.body, 340, 3)

	self.yes = W.Button(f, "YES - FLIP IT", 150, 34, "gold")
	self.yes:SetPoint("BOTTOMLEFT", 24, 30)
	self.yes:SetScript("OnClick", function() ns.Client:AnswerDouble(true) end)
	self.no = W.Button(f, "NO", 150, 34)
	self.no:SetPoint("BOTTOMRIGHT", -24, 30)
	self.no:SetScript("OnClick", function() ns.Client:AnswerDouble(false) end)
	self.status = W.Text(f, 13, C_.gold, "OUTLINE")
	self.status:SetPoint("BOTTOM", 0, 42)
	self.status:SetJustifyH("CENTER")
	W.Fit(self.status, 340, 2)

	-- the fuse: a bar that burns down over the twelve seconds
	local track = f:CreateTexture(nil, "ARTWORK")
	track:SetColorTexture(0, 0, 0, 0.6)
	track:SetPoint("BOTTOMLEFT", 24, 12)
	track:SetPoint("BOTTOMRIGHT", -24, 12)
	track:SetHeight(8)
	self.track = track
	self.fuse = f:CreateTexture(nil, "OVERLAY")
	self.fuse:SetColorTexture(1, 0.8, 0.2, 1)
	self.fuse:SetPoint("LEFT", track, "LEFT", 0, 0)
	self.fuse:SetHeight(8)
	self.fuseLabel = W.Text(f, 11, C_.text, "OUTLINE")
	self.fuseLabel:SetPoint("BOTTOMRIGHT", track, "TOPRIGHT", 0, 2)

	f:SetScript("OnUpdate", function() UI:Tick() end)
end

-- show the offer for d = ns.Client.double
function UI:Show()
	self:Build()
	self.frame:Show()
	self.frame:Raise()
	self.shownAt = GetTime()
	self:Refresh()
end

function UI:Hide()
	if self.frame then self.frame:Hide() end
end

function UI:Refresh()
	local d = ns.Client.double
	if not (self.frame and d) then return end
	local meLoser = d.loser == ns.me
	local other = meLoser and d.winner or d.loser
	if meLoser then
		self.body:SetText(("You owe %s %s\nFlip a coin for double or nothing?\nMax loss: |cffffd100%s|r%s"):format(
			ns.Who(other), ns.Money(d.amount), ns.Money(2 * d.amount), d.test and "  |cffff6161(test)|r" or ""))
	else
		self.body:SetText(("%s owes you %s\nFlip a coin for double or nothing?\nMax win: |cffffd100%s|r%s"):format(
			ns.Who(other), ns.Money(d.amount), ns.Money(2 * d.amount), d.test and "  |cffff6161(test)|r" or ""))
	end
	local answered = d.answer ~= nil
	local open = not d.result and not answered and not d.expired
	self.yes:SetShown(open)
	self.no:SetShown(open)
	local st = ""
	if d.result == "yes" then st = "|cff59d959Both said yes - flip it!|r"
	elseif d.result == "no" then st = "|cffff6161No double.|r " .. (d.why or "") .. "\nThe result stands."
	elseif d.answer == true then st = (d.yes and d.yes[other]) and "Both said yes..." or ("You said yes - waiting for " .. ns.Who(other) .. "...")
	elseif d.answer == false then st = "You said no. The result stands."
	elseif d.expired then st = "Time's up. The result stands." end
	self.status:SetText(st)
end

function UI:Tick()
	local d = ns.Client.double
	if not d then return end
	local now = GetTime()
	local left = math.max(0, d.deadline - now)
	local w = self.track:GetWidth() or 332
	local u = d.result and 0 or (left / d.secs)
	self.fuse:SetWidth(math.max(0.01, w * u))
	self.fuse:SetColorTexture(1, 0.3 + 0.5 * u, 0.2, 1)
	self.fuseLabel:SetText(d.result and "" or (math.ceil(left) .. "s"))
	-- the coin turns
	local c = math.abs(math.cos(now * 2.4))
	self.coin:SetSize(54, math.max(2, 54 * c))
	self.glow:SetAlpha(0.35 + 0.15 * math.sin(now * 4))
	-- the title bounce
	local t, y = now - (self.shownAt or 0), 0
	for _, b in ipairs(BOUNCES) do
		if t < b[1] then y = b[2] * math.sin(math.pi * t / b[1]) break end
		t = t - b[1]
	end
	if y ~= self.titleY then
		self.titleY = y
		self.title:SetPoint("TOP", 0, TITLE_Y + y)
	end
	if not d.result and d.answer == nil and not d.expired and left <= 0 then
		d.expired = true
		ns.Client:AnswerDouble(false, true)
	end
end

function UI:Init() end
