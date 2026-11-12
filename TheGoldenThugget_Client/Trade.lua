-- The Golden Thugget: settle up in the trade window.
-- When you trade the house (or, as the house, a player on the books), a panel
-- under the trade window shows what's owed and a Pay button that puts exactly
-- that gold in your side of the trade. The house's ledger records the trade
-- when it completes (Bank.lua): automatically when the gold matches what was
-- owed, otherwise it asks as before.
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

-- What this trade should move, from your side:
--   pay  = copper you owe them (Pay button fills it)
--   owed = copper they owe you (shown; they fill it from their side)
-- Returns nil when the partner has nothing to do with the Golden Thugget.
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

-- put copper into your side of the trade (through the money boxes when they
-- exist, so they show the amount too)
function T.Fill(c)
	if TradePlayerInputMoneyFrame and MoneyInputFrame_SetCopper then
		pcall(MoneyInputFrame_SetCopper, TradePlayerInputMoneyFrame, c)
	end
	if SetTradeMoney then pcall(SetTradeMoney, c) end
	T.filled = c
end

function T:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "GoldenThuggetTradePanel", UIParent, "BackdropTemplate")
	f:SetSize(338, 74)
	f:SetFrameStrata("HIGH")
	W.Backdrop(f, { 0.055, 0.045, 0.045, 1 }, C_.gold, 2)
	f:Hide()
	local logo = f:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(ns.MEDIA .. "logo")
	logo:SetSize(44, 44)
	logo:SetPoint("LEFT", 10, 0)
	f.title = W.Text(f, 13, C_.gold)
	f.title:SetPoint("TOPLEFT", 62, -11)
	W.Fit(f.title, 260, 1)
	f.line = W.Text(f, 12, C_.text)
	f.line:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	W.Fit(f.line, 170, 2)
	f.pay = W.Button(f, "Pay", 96, 26, "gold")
	f.pay:SetPoint("BOTTOMRIGHT", -10, 10)
	f.pay:SetScript("OnClick", function() T:Pay() end)
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

function T:Pay()
	local d = self.due
	if not d or d.pay <= 0 then return end
	local have = GetMoney and GetMoney() or d.pay
	T.Fill(math.min(d.pay, have))
	self:Refresh()
end

function T:Refresh()
	local f, d, who = self.frame, self.due, self.who
	if not (f and d) then return end
	local name = ns.Who(who)
	f.title:SetText(d.house and ("Golden Thugget - " .. name) or ("Golden Thugget - paying the house"))
	local have = GetMoney and GetMoney() or math.huge
	local mine = GetPlayerTradeMoney and GetPlayerTradeMoney() or (T.filled or 0)
	if d.pay > 0 then
		local fill = math.min(d.pay, have)
		f.line:SetText((d.house and "You owe them " or "You owe the house ") .. ns.Money(d.pay)
			.. (fill < d.pay and ("\n|cffff6161You only have " .. ns.Money(have) .. "|r") or ""))
		f.pay:Show()
		if mine == fill and fill > 0 then
			f.pay:SetText("Filled")
			f.pay:SetEnabled(false)
			f.pay.tip = "That's in the trade. Click Trade to finish; the house's ledger updates when it completes."
		else
			f.pay:SetText(fill < d.pay and "Pay what I have" or "Pay")
			f.pay:SetEnabled(fill > 0)
			f.pay.tip = "Put " .. ns.MoneyPlain(fill) .. " into your side of this trade."
		end
	else
		f.pay:Hide()
		if d.owed > 0 then
			f.line:SetText(d.house and ("They owe you " .. ns.Money(d.owed) .. "\n|cff9e948aThey can fill it from their side|r")
				or ("The house owes you " .. ns.Money(d.owed)))
		else
			f.line:SetText("|cff9e948aSquare - nothing owed|r")
		end
	end
	if not d.house and d.ts and d.ts > 0 then
		f.title:SetText(f.title:GetText() .. "  |cff9e948a(as of " .. date("%H:%M", d.ts) .. ")|r")
	end
end

function T:Show()
	self.who = T.Partner()
	self.due = T.Due(self.who)
	T.filled = nil
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
ns.On("TRADE_MONEY_CHANGED", function() if T.due then T:Refresh() end end)
ns.On("PLAYER_TRADE_MONEY", function() if T.due then T:Refresh() end end)
