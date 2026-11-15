-- The Golden Thugget: a minimap button (the coin's GT). Left-click opens the
-- casino window; on the house build, right-click opens the house window.
-- Drag it around the minimap's edge. /gt minimap hides or shows it.
local _, ns = ...
if ns.skip then return end
local M = {}
ns.Minimap = M

local ICON = ns.MEDIA .. "minimap"
local DEFAULT_ANGLE = 200 -- degrees, 0 = right, counter-clockwise (lower left)

local function settings() return ns.db and ns.db.settings or {} end

function M:Place()
	local b = self.button
	if not b then return end
	local a = math.rad(settings().minimapAngle or DEFAULT_ANGLE)
	local r = (Minimap:GetWidth() / 2) + 5
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function dragUpdate(self)
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local s = Minimap:GetEffectiveScale()
	cx, cy = cx / s, cy / s
	settings().minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	M:Place()
end

function M:Build()
	if self.button or not Minimap then return end
	local b = CreateFrame("Button", "GoldenThuggetMinimapButton", Minimap)
	self.button = b
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(21, 21)
	icon:SetPoint("TOPLEFT", 6, -5)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -6) end)
	b:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -5) end)
	b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); icon:SetPoint("TOPLEFT", 6, -5) end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" and ns.HostUI then ns.HostUI:Toggle()
		else ns.ClientUI:Toggle() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("The Golden Thugget", 1, 0.82, 0)
		GameTooltip:AddLine("Left-click: the casino", 1, 1, 1)
		if ns.HostUI then GameTooltip:AddLine("Right-click: the house", 1, 1, 1) end
		GameTooltip:AddLine("Drag to move.  /gt minimap to hide.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self:Place()
end

function M:Refresh()
	if settings().minimap == false then
		if self.button then self.button:Hide() end
		return
	end
	self:Build()
	if self.button then self.button:Show(); self:Place() end
end

-- /gt minimap [on|off]
function M:Slash(v)
	v = (v or ""):lower()
	local s = settings()
	if v == "on" then s.minimap = true elseif v == "off" then s.minimap = false
	else s.minimap = s.minimap == false end
	self:Refresh()
	if ns.SettingsUI then ns.SettingsUI:Refresh() end
	ns.Notify("Minimap button " .. (s.minimap ~= false and "on." or "off. |cffffd100/gt minimap|r brings it back."))
end

function M:Init() self:Refresh() end
