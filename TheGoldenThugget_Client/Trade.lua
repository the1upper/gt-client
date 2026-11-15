-- The Golden Thugget: a reminder under the trade window.
-- When you trade the house (or, as the house, a player on the books), a small
-- panel under the trade window shows what's owed, so you know what to put in.
-- It only reads the ledger; it never touches the trade itself.
local _, ns = ...
if ns.skip then return end
local W = ns.W
local C_ = W.C
local T = {}
ns.Trade = T

-- who you're trading with, as the ledger names them
function T.Partner()
	local n = GetUnitName and GetUnitName("NPC", true) or (UnitName and UnitName("NPC"))
	return n and ns.Full(n)
end

-- What's owed, from your side of this trade:
--   pay  = copper you owe them
--   owed = copper they owe you
-- nil when the partner has nothing to do with the Golden Thugget.
function T.Due(who)
	if not who then return end
	if ns.Bank and ns.hdb then -- you're the house
		if not ns.Bank:Known(who) then return end
		local net = ns.Bank:Net(who)
		return { house = true, pay = net > 0 and net or 0, owed = net < 0 and -net or 0 }
	end
	local C = ns.Client
	if who ~= C:Host() then return end
	local bal = C:Balance()
	return { house = false, pay = bal < 0 and -bal or 0, owed = bal > 0 and bal or 0, ts = C:Cache().ts }
end

function T:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetTradePanel", UIParent, "BackdropTemplate")
	f:SetSize(338, 62)
	f:SetFrameStrata("HIGH")
	W.Backdrop(f, { 0.055, 0.045, 0.045, 1 }, C_.gold, 2)
	f:Hide()
	local logo = f:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(ns.MEDIA .. "logo")
	logo:SetSize(40, 40)
	logo:SetPoint("LEFT", 10, 0)
	f.title = W.Text(f, 13, C_.gold)
	f.title:SetPoint("TOPLEFT", 60, -11)
	W.Fit(f.title, 266, 1)
	f.line = W.Text(f, 12, C_.text)
	f.line:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	W.Fit(f.line, 266, 2)
	self.frame = f
end

function T:Place()
	local f = self.frame
	f:ClearAllPoints()
	if TradeFrame and TradeFrame:IsShown() then
		f:SetPoint("TOP", TradeFrame, "BOTTOM", 0, -2)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
end

function T:Refresh()
	local f, d = self.frame, self.due
	if not (f and d) then return end
	local title = d.house and ("Golden Thugget - " .. ns.Who(self.who)) or "Golden Thugget - trading the house"
	if not d.house and d.ts and d.ts > 0 then title = title .. "  |cff9e948a(as of " .. date("%H:%M", d.ts) .. ")|r" end
	f.title:SetText(title)
	if d.pay > 0 then
		f.line:SetText((d.house and "You owe them " or "You owe the house ") .. ns.Money(d.pay))
	elseif d.owed > 0 then
		f.line:SetText((d.house and "They owe you " or "The house owes you ") .. ns.Money(d.owed))
	else
		f.line:SetText("|cff9e948aSquare - nothing owed|r")
	end
end

function T:Show()
	self.who = T.Partner()
	self.due = T.Due(self.who)
	if not self.due then
		if self.frame then self.frame:Hide() end
		return
	end
	self:Build()
	self:Place()
	self:Refresh()
	self.frame:Show()
end

function T:Hide()
	if self.frame then self.frame:Hide() end
	self.due = nil
end

ns.On("TRADE_SHOW", function() T:Show() end)
ns.On("TRADE_CLOSED", function() T:Hide() end)
