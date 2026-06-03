-- UI_Minimap.lua
-- Minimap Button Management for ShellcoinTicker (Vanilla WoW 1.12)

function ShellcoinTicker.UI:CreateMinimapButton()
    if self.minimapBtn then return end
    
    local minimapBtn = CreateFrame("Button", "ShellcoinTickerMinimapButton", Minimap)
    minimapBtn:SetWidth(31)
    minimapBtn:SetHeight(31)
    minimapBtn:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Icon texture (Named so button bags can manage it, uses relative bounds with no fixed size)
    local icon = minimapBtn:CreateTexture("ShellcoinTickerMinimapButtonIcon", "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 7, -5)
    minimapBtn.icon = icon
    
    -- Overlay (Border) named matching FuBarPlugin-2.0 conventions
    local overlay = minimapBtn:CreateTexture("ShellcoinTickerMinimapButtonOverlay", "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT")
    minimapBtn.overlay = overlay
    
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:RegisterForDrag("LeftButton")
    
    minimapBtn:SetScript("OnDragStart", function()
        this.isDragging = true
        this.dragged = true
        this:LockHighlight()
    end)
    
    minimapBtn:SetScript("OnDragStop", function()
        this.isDragging = false
        this:UnlockHighlight()
    end)
    
    minimapBtn:SetScript("OnUpdate", function()
        if this.isDragging then
            local cx, cy = Minimap:GetCenter()
            local xpos, ypos = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local x = (xpos / scale) - cx
            local y = (ypos / scale) - cy
            local angle = math.deg(math.atan2(y, x))
            if angle < 0 then angle = angle + 360 end
            ShellcoinTickerDB.minimapAngle = angle
            ShellcoinTicker.UI:UpdateMinimapButton()
        end
    end)
    
    minimapBtn:SetScript("OnMouseDown", function()
        this.dragged = false
        local texture = this.icon:GetTexture()
        if texture and string.find(string.lower(texture), "interface\\icons\\", 1, true) == 1 then
            this.icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
        else
            this.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    end)
    
    minimapBtn:SetScript("OnMouseUp", function()
        local texture = this.icon:GetTexture()
        if texture and string.find(string.lower(texture), "interface\\icons\\", 1, true) == 1 then
            this.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        else
            this.icon:SetTexCoord(0, 1, 0, 1)
        end
    end)
    
    minimapBtn:SetScript("OnClick", function()
        if this.dragged then return end
        
        if arg1 == "LeftButton" then
            ShellcoinTicker.UI:ToggleOptionsFrame()
        elseif arg1 == "RightButton" then
            ShellcoinTickerDB.isShown = not ShellcoinTickerDB.isShown
            if ShellcoinTickerDB.isShown then
                ShellcoinTicker.UI.frame:Show()
            else
                ShellcoinTicker.UI.frame:Hide()
            end
            local hudToggle = getglobal("ShellcoinTickerOptionsFrameHUDToggle")
            if hudToggle then
                hudToggle:SetChecked(ShellcoinTickerDB.isShown and 1 or nil)
            end
        end
    end)
    
    minimapBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Shellcoin Ticker", 1, 1, 1)
        GameTooltip:AddLine("Left-click to toggle Options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click to toggle HUD", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("(Drag to move button)", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    self.minimapBtn = minimapBtn
    self:UpdateMinimapButton()
    self:UpdateMinimapIcon()
end

function ShellcoinTicker.UI:UpdateMinimapButton()
    if not ShellcoinTickerDB or not self.minimapBtn then return end
    
    if ShellcoinTickerDB.showMinimapButton then
        self.minimapBtn:Show()
    else
        self.minimapBtn:Hide()
        return
    end
    
    local angle = ShellcoinTickerDB.minimapAngle or 45
    local radAngle = math.rad(angle)
    local x, y
    local isSquare = IsAddOnLoaded("CornerMinimap") or IsAddOnLoaded("SquareMinimap") or IsAddOnLoaded("Squeenix")
    if not isSquare then
        x = 80 * math.cos(radAngle)
        y = 80 * math.sin(radAngle)
    else
        x = 110 * math.cos(radAngle)
        y = 110 * math.sin(radAngle)
        x = math.max(-82, math.min(x, 84))
        y = math.max(-86, math.min(y, 82))
    end
    self.minimapBtn:ClearAllPoints()
    self.minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function ShellcoinTicker.UI:UpdateMinimapIcon()
    if not self.minimapBtn or not self.minimapBtn.icon then return end
    local texture = "Interface\\Icons\\INV_Misc_Coin_01" -- Fallback classic gold coin icon
    
    local info = { GetItemInfo(81118) }
    if table.getn(info) > 0 then
        for i = 1, table.getn(info) do
            local val = info[i]
            if type(val) == "string" and string.find(string.lower(val), "interface", 1, true) == 1 then
                if not string.find(val, "|H", 1, true) and not string.find(val, "item:", 1, true) then
                    texture = val
                    break
                end
            end
        end
    end
    
    self.minimapBtn.icon:SetTexture(texture)
    if string.find(string.lower(texture), "interface\\icons\\", 1, true) == 1 then
        self.minimapBtn.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    else
        self.minimapBtn.icon:SetTexCoord(0, 1, 0, 1)
    end
end
