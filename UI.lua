-- UI.lua
-- HUD Layout, Frame Creation, and Updates for ShellcoinTicker (Vanilla WoW 1.12)

ShellcoinTicker.UI = {
    MAX_POINTS = 100,
    frame = nil,
    priceText = nil,
    trendText = nil,
    holdingsText = nil,
    valueText = nil,
    newsText = nil,
    investedText = nil,
    profitLossText = nil,
    graphFrame = nil,
    graphDots = {},
    graphHLines = {},
    graphVLines = {},
    graphMaxText = nil,
    graphMinText = nil,
    graphHoverFrames = {},
    graphHighlightLine = nil,
    trendHoverFrame = nil,
    btn1h = nil,
    btn1d = nil,
    btn1w = nil,
    btn1mo = nil,
    btn1y = nil
}

function ShellcoinTicker.UI:SetTimeframe(tf)
    if not ShellcoinTickerDB then return end
    ShellcoinTickerDB.selectedTimeframe = tf
    self:UpdateDisplay()
    self:UpdateTimeframeButtonHighlights()
end

function ShellcoinTicker.UI:UpdateTimeframeButtonHighlights()
    if not ShellcoinTickerDB then return end
    local tf = ShellcoinTickerDB.selectedTimeframe
    if tf == "10m" or not tf then
        tf = "1h"
        ShellcoinTickerDB.selectedTimeframe = "1h"
    end
    local buttons = {
        ["1h"] = self.btn1h,
        ["1d"] = self.btn1d,
        ["1w"] = self.btn1w,
        ["1mo"] = self.btn1mo,
        ["1y"] = self.btn1y,
        ["10y"] = self.btn10y
    }
    for key, btn in pairs(buttons) do
        if btn then
            if key == tf then
                btn:GetFontString():SetTextColor(1, 0.82, 0)    -- Gold
            else
                btn:GetFontString():SetTextColor(0.6, 0.6, 0.6) -- Gray
            end
        end
    end
end

function ShellcoinTicker.UI:CreateMainFrame()
    if self.frame then return end

    -- Main container frame (Height expanded to 240 to fit scale buttons)
    local frame = CreateFrame("Frame", "ShellcoinTickerFrame", UIParent)
    frame:SetWidth(280)
    frame:SetHeight(240)

    -- Set position from SavedVariables or default to center
    if ShellcoinTickerDB and ShellcoinTickerDB.x and ShellcoinTickerDB.y then
        frame:SetPoint(ShellcoinTickerDB.point or "CENTER", UIParent, ShellcoinTickerDB.point or "CENTER",
            ShellcoinTickerDB.x, ShellcoinTickerDB.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Frame settings
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true) -- Prevent dragging the frame off the screen
    frame:SetScale(ShellcoinTickerDB.hudScale or 1.0)

    -- Sleek background backdrop configuration
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)            -- semi-transparent pitch black
    frame:SetBackdropBorderColor(0.8, 0.6, 0.0, 0.8) -- luxurious gold border

    -- Dragging functionality (using 1.12 'this' global reference inside scripts)
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)

    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = this:GetPoint()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.point = point
            ShellcoinTickerDB.x = xOfs
            ShellcoinTickerDB.y = yOfs
        end
    end)

    -- Title label
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -8)
    titleText:SetText("|cffffd700🐢 Shellcoin Ticker (SHELL)|r")

    -- Close button (uses standard Blizzard UI assets)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.isShown = false
        end
        frame:Hide()
    end)

    -- Real-time Invested Label
    local investedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    investedText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -26)
    self.investedText = investedText

    -- Real-time Profit/Loss Label
    local profitLossText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    profitLossText:SetPoint("TOPLEFT", investedText, "BOTTOMLEFT", 0, -4)
    self.profitLossText = profitLossText

    -- Price Display
    local priceText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    priceText:SetPoint("TOPLEFT", profitLossText, "BOTTOMLEFT", 0, -4)
    self.priceText = priceText

    -- Sparkline/Trend Indicator
    local trendText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trendText:SetPoint("TOPLEFT", priceText, "BOTTOMLEFT", 0, -4)
    self.trendText = trendText

    -- Hover frame to show trend details tooltip
    local trendHoverFrame = CreateFrame("Frame", nil, frame)
    self.trendHoverFrame = trendHoverFrame
    trendHoverFrame:SetPoint("TOPLEFT", trendText, "TOPLEFT")
    trendHoverFrame:SetPoint("BOTTOMRIGHT", trendText, "BOTTOMRIGHT")
    trendHoverFrame:EnableMouse(true)
    trendHoverFrame:RegisterForDrag("LeftButton")
    trendHoverFrame:SetScript("OnDragStart", function()
        this:GetParent():StartMoving()
    end)
    trendHoverFrame:SetScript("OnDragStop", function()
        this:GetParent():StopMovingOrSizing()
        local parent = this:GetParent()
        local point, _, relativePoint, xOfs, yOfs = parent:GetPoint()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.point = point
            ShellcoinTickerDB.x = xOfs
            ShellcoinTickerDB.y = yOfs
        end
    end)
    trendHoverFrame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Recent Trend Details", 1, 0.82, 0)
        GameTooltip:AddLine(" ")

        local history = ShellcoinTickerDB and ShellcoinTickerDB.history
        local numPoints = history and table.getn(history) or 0
        local activeHistory = {}
        if history then
            for i = 1, numPoints do
                local entry = history[i]
                if entry and type(entry) == "table" and entry.price and entry.price > 0 then
                    table.insert(activeHistory, entry)
                end
            end
        end
        local numActivePoints = table.getn(activeHistory)

        if numActivePoints > 1 then
            local startIdx = math.max(2, numActivePoints - 19)
            for i = startIdx, numActivePoints do
                local prevEntry = activeHistory[i - 1]
                local currEntry = activeHistory[i]
                local prev = prevEntry.price or 0
                local curr = currEntry.price or 0
                local t = currEntry.time or 0

                local diff = curr - prev
                local percent = (prev > 0) and ((diff / prev) * 100) or 0
                local changeText
                if diff > 0 then
                    changeText = "|cff00ff00+" .. string.format("%.2f%%", percent) .. "|r"
                elseif diff < 0 then
                    changeText = "|cffff0000-" .. string.format("%.2f%%", math.abs(percent)) .. "|r"
                else
                    changeText = "|cff8888880.00%|r"
                end

                local timeStr = date("%m/%d %H:%M", t)
                GameTooltip:AddDoubleLine(
                    "|cffffffff" .. timeStr .. "|r   " .. ShellcoinTicker:FormatMoney(curr),
                    changeText,
                    1, 1, 1, 1, 1, 1
                )
            end
        else
            GameTooltip:AddLine("No recent trend data available.", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    trendHoverFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Timeframe selection frame container (Width 256, Height 18)
    local tfFrame = CreateFrame("Frame", "ShellcoinTickerTimeframe", frame)
    self.tfFrame = tfFrame
    tfFrame:SetWidth(256)
    tfFrame:SetHeight(18)
    tfFrame:SetPoint("TOPLEFT", trendText, "BOTTOMLEFT", 0, -6)

    local function CreateTFButton(text, tf, parent, xOfs)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetWidth(40)
        btn:SetHeight(16)
        btn:SetPoint("LEFT", parent, "LEFT", xOfs, 0)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(text)
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn:SetFontString(fs)

        btn:SetScript("OnClick", function()
            ShellcoinTicker.UI:SetTimeframe(tf)
        end)

        return btn
    end

    self.btn1h = CreateTFButton("1H", "1h", tfFrame, 0)
    self.btn1d = CreateTFButton("1D", "1d", tfFrame, 44)
    self.btn1w = CreateTFButton("1W", "1w", tfFrame, 88)
    self.btn1mo = CreateTFButton("1Mo", "1mo", tfFrame, 132)
    self.btn1y = CreateTFButton("1Y", "1y", tfFrame, 176)
    self.btn10y = CreateTFButton("10Y", "10y", tfFrame, 220)
    self.btn10y:Hide()

    -- Inner Graph Frame (Width 256, Height 60, aligned below tfFrame)
    local graphFrame = CreateFrame("Frame", "ShellcoinTickerGraph", frame)
    graphFrame:SetWidth(256)
    graphFrame:SetHeight(60)
    graphFrame:SetPoint("TOPLEFT", tfFrame, "BOTTOMLEFT", 0, -4)
    graphFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    graphFrame:SetBackdropColor(0, 0, 0, 0.5) -- darker inner background
    graphFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.4)
    graphFrame:EnableMouse(true)
    graphFrame:RegisterForDrag("LeftButton")
    graphFrame:SetScript("OnDragStart", function()
        this:GetParent():StartMoving()
    end)
    graphFrame:SetScript("OnDragStop", function()
        this:GetParent():StopMovingOrSizing()
        local parent = this:GetParent()
        local point, _, relativePoint, xOfs, yOfs = parent:GetPoint()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.point = point
            ShellcoinTickerDB.x = xOfs
            ShellcoinTickerDB.y = yOfs
        end
    end)
    graphFrame:SetScript("OnEnter", function()
        this:SetScript("OnUpdate", ShellcoinTicker.UI.Graph_OnUpdate)
    end)
    graphFrame:SetScript("OnLeave", function()
        this:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
        local ui = ShellcoinTicker.UI
        if ui.graphHighlightLine then
            ui.graphHighlightLine:Hide()
        end
        -- Hide only the active dot instead of iterating all MAX_POINTS
        if ui.activeGraphIndex and ui.graphDots[ui.activeGraphIndex] then
            ui.graphDots[ui.activeGraphIndex]:Hide()
        end
        ui.activeGraphIndex = nil
    end)
    self.graphFrame = graphFrame

    -- Graph Min/Max overlay texts
    local graphMaxText = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphMaxText:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", 6, -4)
    graphMaxText:SetTextColor(0.8, 0.8, 0.8, 0.8)
    self.graphMaxText = graphMaxText

    local graphMinText = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphMinText:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", 6, 4)
    graphMinText:SetTextColor(0.8, 0.8, 0.8, 0.8)
    self.graphMinText = graphMinText

    -- Pre-create graph elements pool
    self.graphDots = {}
    self.graphHLines = {}
    self.graphVLines = {}
    self.graphBars = {}

    for i = 1, self.MAX_POINTS do
        local dot = graphFrame:CreateTexture(nil, "OVERLAY")
        dot:SetWidth(4)
        dot:SetHeight(4)
        dot:SetTexture(0, 0.65, 1, 0.9)
        dot:Hide()
        table.insert(self.graphDots, dot)
    end

    for i = 1, self.MAX_POINTS - 1 do
        local hline = graphFrame:CreateTexture(nil, "ARTWORK")
        hline:SetHeight(1.5)
        hline:SetTexture(0, 0.65, 1, 0.8)
        hline:Hide()
        table.insert(self.graphHLines, hline)

        local vline = graphFrame:CreateTexture(nil, "ARTWORK")
        vline:SetWidth(1.5)
        vline:SetTexture(0, 0.65, 1, 0.8)
        vline:Hide()
        table.insert(self.graphVLines, vline)

        local bar = graphFrame:CreateTexture(nil, "BACKGROUND")
        bar:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bar:SetGradientAlpha("VERTICAL", 0, 0.65, 1, 0.02, 0, 0.65, 1, 0.30)
        bar:Hide()
        table.insert(self.graphBars, bar)
    end

    -- Highlight line for hovered graph point
    local highlightLine = graphFrame:CreateTexture(nil, "OVERLAY")
    highlightLine:SetWidth(1.5)
    highlightLine:SetTexture(1, 1, 1, 0.25) -- semi-transparent white
    highlightLine:Hide()
    self.graphHighlightLine = highlightLine

    -- Hover frames for tooltip interactivity (data structures only)
    self.graphHoverFrames = {}
    for i = 1, self.MAX_POINTS do
        local hf = CreateFrame("Frame", nil, graphFrame)
        hf:EnableMouse(false)
        hf:SetFrameLevel(graphFrame:GetFrameLevel() + 5)
        hf:Hide()
        table.insert(self.graphHoverFrames, hf)
    end

    -- Holdings Counter (positioned below graphFrame)
    local holdingsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holdingsText:SetPoint("TOPLEFT", graphFrame, "BOTTOMLEFT", 0, -8)
    self.holdingsText = holdingsText

    -- Holdings Net Value
    local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("TOPLEFT", holdingsText, "BOTTOMLEFT", 0, -4)
    self.valueText = valueText

    -- Hover frame to show character breakdown tooltip
    local hoverFrame = CreateFrame("Frame", nil, frame)
    self.holdingsHoverFrame = hoverFrame
    hoverFrame:SetPoint("TOPLEFT", holdingsText, "TOPLEFT")
    hoverFrame:SetPoint("BOTTOMRIGHT", valueText, "BOTTOMRIGHT")
    hoverFrame:EnableMouse(true)
    hoverFrame:RegisterForDrag("LeftButton")
    hoverFrame:SetScript("OnDragStart", function()
        this:GetParent():StartMoving()
    end)
    hoverFrame:SetScript("OnDragStop", function()
        this:GetParent():StopMovingOrSizing()
        local parent = this:GetParent()
        local point, _, relativePoint, xOfs, yOfs = parent:GetPoint()
        if ShellcoinTickerDB then
            ShellcoinTickerDB.point = point
            ShellcoinTickerDB.x = xOfs
            ShellcoinTickerDB.y = yOfs
        end
    end)
    hoverFrame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Shellcoin Holdings", 1, 0.82, 0)

        local currentRealm = GetRealmName()
        local accountTotal = 0
        local realmTotal = 0
        local currentPrice = ShellcoinTickerDB.price or 0

        -- 1. Current Realm list
        local hasCurrentRealmChars = false
        if ShellcoinTickerDB and ShellcoinTickerDB.characters then
            for name, data in pairs(ShellcoinTickerDB.characters) do
                local bags = data.bags or 0
                local bank = data.bank or 0
                local charTotal = bags + bank
                if charTotal > 0 then
                    if not hasCurrentRealmChars then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Current Realm (" .. currentRealm .. "):", 0.5, 0.8, 1)
                        hasCurrentRealmChars = true
                    end
                    realmTotal = realmTotal + charTotal
                    accountTotal = accountTotal + charTotal
                    GameTooltip:AddDoubleLine("|cffffffff" .. name .. "|r",
                        charTotal .. " SHELL (|cffc7c7c7Bags: " .. bags .. ", Bank: " .. bank .. "|r)", 1, 1, 1, 1, 1, 1)
                end
            end
        end

        -- 2. Other Realms list
        local hasOtherRealms = false
        for realmName, realmData in pairs(ShellcoinTickerDB) do
            if realmName ~= currentRealm and type(realmData) == "table" and realmData.characters then
                for name, data in pairs(realmData.characters) do
                    local bags = data.bags or 0
                    local bank = data.bank or 0
                    local charTotal = bags + bank
                    if charTotal > 0 then
                        if not hasOtherRealms then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Other Realms:", 0.5, 0.8, 1)
                            hasOtherRealms = true
                        end
                        accountTotal = accountTotal + charTotal
                        GameTooltip:AddDoubleLine("|cffc7c7c7" .. name .. " (" .. realmName .. ")|r",
                            charTotal .. " SHELL (|cff888888Bags: " .. bags .. ", Bank: " .. bank .. "|r)", 0.7, 0.7, 0.7,
                            0.7, 0.7, 0.7)
                    end
                end
            end
        end

        local totalValue = accountTotal * currentPrice

        GameTooltip:AddLine("--------------------------------------------------", 0.5, 0.5, 0.5)
        GameTooltip:AddDoubleLine("|cffffd700Realm Total:|r", "|cffffd700" .. realmTotal .. " SHELL|r", 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("|cffffd700Account Total:|r", "|cffffd700" .. accountTotal .. " SHELL|r", 1, 1, 1, 1, 1,
            1)
        GameTooltip:AddDoubleLine("|cffffd700Account Net Worth:|r", ShellcoinTicker:FormatMoney(totalValue), 1, 1, 1, 1,
            1, 1)
        GameTooltip:Show()
    end)
    hoverFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- News Feed Label
    local newsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newsText:SetPoint("TOPLEFT", valueText, "BOTTOMLEFT", 0, -8)
    newsText:SetWidth(256)
    newsText:SetHeight(24)
    newsText:SetJustifyH("LEFT")
    newsText:SetJustifyV("TOP")
    self.newsText = newsText

    self.frame = frame

    -- Setup OnUpdate script for time accumulators
    local timeSinceSimUpdate = 0
    local timeSinceBagScan = 0
    local timeSinceServerSync = 0

    frame:SetScript("OnUpdate", function()
        local elapsed = arg1 -- 1.12 passes elapsed time in global arg1
        if not elapsed then return end

        -- Throttled inventory scan & Speedrun simulation
        timeSinceBagScan = timeSinceBagScan + elapsed
        if timeSinceBagScan >= 1.0 then
            timeSinceBagScan = 0

            -- Speedrun Simulation Tick
            if ShellcoinTicker.speedrunMode then
                if ShellcoinTicker.virtualTime and ShellcoinTicker.virtualTime < time() then
                    -- Advance by 10 minutes (600s)
                    ShellcoinTicker.virtualTime = ShellcoinTicker.virtualTime + 600

                    local currentPrice = ShellcoinTickerDB.price or 100000
                    local change = -0.05 + (math.random() * 0.11)
                    local newPrice = math.max(100, math.floor(currentPrice * (1.0 + change)))
                    ShellcoinTickerDB.price = newPrice

                    -- Record history
                    table.insert(ShellcoinTickerDB.history, { time = ShellcoinTicker.virtualTime, price = newPrice })

                    -- Prune
                    local cutoff = ShellcoinTicker.virtualTime - 315360000
                    local pruned = {}
                    for i = 1, table.getn(ShellcoinTickerDB.history) do
                        local entry = ShellcoinTickerDB.history[i]
                        if entry and entry.time >= cutoff then
                            table.insert(pruned, entry)
                        end
                    end
                    ShellcoinTickerDB.history = pruned

                    ShellcoinTicker.lastEventMsg = "Speedrunning... " ..
                    date("%m/%d %H:%M", ShellcoinTicker.virtualTime) ..
                    " (" .. ShellcoinTicker:FormatMoney(newPrice) .. ")"
                    ShellcoinTicker.UI:UpdateDisplay()
                else
                    ShellcoinTicker.speedrunMode = false
                    DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00ShellcoinTicker: Speedrun simulation completed! Returned to normal mock mode.|r")
                    ShellcoinTicker.lastEventMsg = "Speedrun simulation completed."
                    ShellcoinTicker.UI:UpdateDisplay()
                end
            end

            if ShellcoinTicker.scanPending and not CursorHasItem() then
                ShellcoinTicker:ScanBags()
                ShellcoinTicker.scanPending = false
                ShellcoinTicker.UI:UpdateDisplay()
            end
        end

        -- Throttled price fluctuation update (every 15 seconds)
        timeSinceSimUpdate = timeSinceSimUpdate + elapsed
        if timeSinceSimUpdate >= 15.0 then
            timeSinceSimUpdate = 0
            if not ShellcoinTicker.speedrunMode then
                ShellcoinTicker:UpdateSimulation()
            end
        end

        -- Throttled server sync via .shellcoin command (configurable interval)
        local syncInterval = ShellcoinTickerDB and ShellcoinTickerDB.syncInterval or 600
        if syncInterval > 0 and ShellcoinTickerDB and not ShellcoinTickerDB.mockMode and not ShellcoinTicker.speedrunMode then
            timeSinceServerSync = timeSinceServerSync + elapsed
            if timeSinceServerSync >= syncInterval then
                timeSinceServerSync = 0
                ShellcoinTicker.isSilentSync = true
                SendChatMessage(".shellcoin", "SAY")
            end
        else
            timeSinceServerSync = 0
        end
    end)

    -- Apply initial visibility
    if ShellcoinTickerDB and ShellcoinTickerDB.isShown == false then
        frame:Hide()
    else
        frame:Show()
    end

    -- Initial update & button highlights
    self:LayoutHUD()
    self:UpdateDisplay()
    self:UpdateTimeframeButtonHighlights()

    -- Create Minimap Button
    self:CreateMinimapButton()
end

function ShellcoinTicker.UI:LayoutHUD()
    if not self.frame or not ShellcoinTickerDB then return end

    -- Clear all points first
    self.investedText:ClearAllPoints()
    self.profitLossText:ClearAllPoints()
    self.priceText:ClearAllPoints()
    self.trendText:ClearAllPoints()
    if self.tfFrame then
        self.tfFrame:ClearAllPoints()
    end
    if self.graphFrame then
        self.graphFrame:ClearAllPoints()
    end
    self.holdingsText:ClearAllPoints()
    self.valueText:ClearAllPoints()
    self.newsText:ClearAllPoints()

    -- Cache settings, default to true if nil
    local showFin = ShellcoinTickerDB.showFinancials
    if showFin == nil then showFin = true end
    local showPrice = ShellcoinTickerDB.showPriceTrend
    if showPrice == nil then showPrice = true end
    local showTF = ShellcoinTickerDB.showTimeframe
    if showTF == nil then showTF = true end
    local showChart = ShellcoinTickerDB.showChart
    if showChart == nil then showChart = true end
    local showHold = ShellcoinTickerDB.showHoldings
    if showHold == nil then showHold = true end
    local showFeed = ShellcoinTickerDB.showFeed
    if showFeed == nil then showFeed = true end

    -- Set visibilities
    if showFin then
        self.investedText:Show()
        self.profitLossText:Show()
    else
        self.investedText:Hide()
        self.profitLossText:Hide()
    end

    if showPrice then
        self.priceText:Show()
        self.trendText:Show()
        if self.trendHoverFrame then self.trendHoverFrame:Show() end
    else
        self.priceText:Hide()
        self.trendText:Hide()
        if self.trendHoverFrame then self.trendHoverFrame:Hide() end
    end

    if self.tfFrame then
        if showTF then
            self.tfFrame:Show()
        else
            self.tfFrame:Hide()
        end
    end

    if self.graphFrame then
        if showChart then
            self.graphFrame:Show()
        else
            self.graphFrame:Hide()
        end
    end

    if showHold then
        self.holdingsText:Show()
        self.valueText:Show()
        if self.holdingsHoverFrame then self.holdingsHoverFrame:Show() end
    else
        self.holdingsText:Hide()
        self.valueText:Hide()
        if self.holdingsHoverFrame then self.holdingsHoverFrame:Hide() end
    end

    if showFeed then
        self.newsText:Show()
    else
        self.newsText:Hide()
    end

    -- Sequential positioning
    local lastAnchor = self.frame
    local relativePoint = "TOPLEFT"
    local xOffset = 12
    local yOffset = -26

    local isFirst = true
    local height = 26 -- starting height (header)

    -- 1. Financials
    if showFin then
        self.investedText:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        self.profitLossText:SetPoint("TOPLEFT", self.investedText, "BOTTOMLEFT", 0, -4)
        lastAnchor = self.profitLossText
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -4

        height = height + 28
        isFirst = false
    end

    -- 2. Price & Trend
    if showPrice then
        if not isFirst then
            height = height + 4
        end
        self.priceText:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        self.trendText:SetPoint("TOPLEFT", self.priceText, "BOTTOMLEFT", 0, -4)
        lastAnchor = self.trendText
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -4

        height = height + 26
        isFirst = false
    end

    -- 3. Timeframe
    if showTF and self.tfFrame then
        if not isFirst then
            yOffset = -6
            height = height + 6
        else
            yOffset = -26
        end
        self.tfFrame:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        lastAnchor = self.tfFrame
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -4

        height = height + 18
        isFirst = false
    end

    -- 4. Chart (graphFrame)
    if showChart and self.graphFrame then
        if not isFirst then
            yOffset = -4
            height = height + 4
        else
            yOffset = -26
        end
        self.graphFrame:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        lastAnchor = self.graphFrame
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -8

        height = height + 60
        isFirst = false
    end

    -- 5. Holdings
    if showHold then
        if not isFirst then
            yOffset = -8
            height = height + 8
        else
            yOffset = -26
        end
        self.holdingsText:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        self.valueText:SetPoint("TOPLEFT", self.holdingsText, "BOTTOMLEFT", 0, -4)
        lastAnchor = self.valueText
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -8

        height = height + 28
        isFirst = false
    end

    -- 6. News Feed
    if showFeed then
        if not isFirst then
            yOffset = -8
            height = height + 8
        else
            yOffset = -26
        end
        self.newsText:SetPoint("TOPLEFT", lastAnchor, relativePoint, xOffset, yOffset)
        lastAnchor = self.newsText
        relativePoint = "BOTTOMLEFT"
        xOffset = 0
        yOffset = -8

        height = height + 24
        isFirst = false
    end

    -- Set final frame height
    if isFirst then
        self.frame:SetHeight(40)
    else
        self.frame:SetHeight(height + 12)
    end
end

function ShellcoinTicker.UI:UpdateDisplay()
    if not self.frame or not ShellcoinTickerDB then return end

    -- Determine dynamically if we should show the "10Y" button (> 1 year of data)
    local show10Y = false
    local history = ShellcoinTickerDB.history
    if history and table.getn(history) > 0 then
        local oldest = history[1]
        if oldest and type(oldest) == "table" and oldest.time then
            local now = time()
            if ShellcoinTicker.speedrunMode then
                now = ShellcoinTicker.virtualTime
            end
            if now - oldest.time > 31536000 then -- 1 year in seconds
                show10Y = true
            end
        end
    end

    if self.btn10y then
        if show10Y then
            self.btn10y:Show()
        else
            self.btn10y:Hide()
            if ShellcoinTickerDB.selectedTimeframe == "10y" then
                ShellcoinTickerDB.selectedTimeframe = "1y"
                self:UpdateTimeframeButtonHighlights()
            end
        end
    end

    -- Update minimap button icon dynamically once cached
    self:UpdateMinimapIcon()

    local price = ShellcoinTickerDB.price or 0
    local change = ShellcoinTickerDB.change or 0

    -- Calculate and Display Financial Analytics (Invested & Profit/Loss)
    local totalInvested, profitLoss, profitLossPercent, costBasis = ShellcoinTicker:CalculateProfitLoss()

    local investedStr = ShellcoinTicker:FormatMoney(totalInvested)
    self.investedText:SetText("Invested: " .. investedStr)

    local plColor = "|cff00ff00" -- green
    local plSign = "+"
    if profitLoss < 0 then
        plColor = "|cffff0000" -- red
        plSign = "-"
    elseif profitLoss == 0 then
        plColor = "|cff888888" -- gray
        plSign = ""
    end

    local formattedPL = ShellcoinTicker:FormatMoney(math.abs(profitLoss))
    if profitLoss < 0 then
        formattedPL = "-" .. formattedPL
    elseif profitLoss > 0 then
        formattedPL = "+" .. formattedPL
    end

    local plPercentStr = plColor .. plSign .. string.format("%.1f%%", math.abs(profitLossPercent)) .. "|r"
    self.profitLossText:SetText("Profit/Loss: " .. plColor .. formattedPL .. " (" .. plPercentStr .. ")|r")

    -- Format current market price and change
    local buyPrice = ShellcoinTickerDB.buyPrice
    local sellPrice = ShellcoinTickerDB.sellPrice
    local priceStr
    if buyPrice and sellPrice then
        priceStr = "Buy: " ..
        ShellcoinTicker:FormatMoney(buyPrice) .. " | Sell: " .. ShellcoinTicker:FormatMoney(sellPrice)
    else
        priceStr = "Market Price: " .. ShellcoinTicker:FormatMoney(price)
    end

    local changeSign = "+"
    local changeColor = "|cff00ff00" -- green
    if change < 0 then
        changeSign = ""
        changeColor = "|cffff0000" -- red
    elseif change == 0 then
        changeColor = "|cff888888" -- gray
    end

    local changeStr = changeColor .. changeSign .. string.format("%.1f%%", change * 100) .. "|r"
    self.priceText:SetText(priceStr .. " (" .. changeStr .. ")")

    -- Build activeHistory once and cache for reuse by sparkline and graph
    local history = ShellcoinTickerDB.history
    local numPoints = history and table.getn(history) or 0
    local activeHistory = {}
    if history then
        for i = 1, numPoints do
            local entry = history[i]
            if entry and type(entry) == "table" and entry.price and entry.price > 0 then
                table.insert(activeHistory, entry)
            end
        end
    end
    self.cachedActiveHistory = activeHistory
    local numActivePoints = table.getn(activeHistory)

    -- Build trend sparkline using safe characters
    local trendStr = "Trend: "
    if numActivePoints > 1 then
        local startIdx = math.max(2, numActivePoints - 19)
        for i = startIdx, numActivePoints do
            local prevEntry = activeHistory[i - 1]
            local currEntry = activeHistory[i]
            local prev = prevEntry.price or 0
            local curr = currEntry.price or 0
            if curr > prev then
                trendStr = trendStr .. " |cff00ff00^|r"
            elseif curr < prev then
                trendStr = trendStr .. " |cffff0000v|r"
            else
                trendStr = trendStr .. " |cff888888-|r"
            end
        end
    else
        trendStr = trendStr .. "|cff888888No data|r"
    end
    self.trendText:SetText(trendStr)

    -- Update Graph Chart (delegated to UI_Graph.lua)
    self:UpdateGraph()

    -- Format holdings
    local bags = ShellcoinTicker.bagsCount or 0
    local bank = ShellcoinTicker.bankCount or 0
    local auth = bags + bank
    self.holdingsText:SetText("HODL: |cffffffff" .. auth .. "|r SHELL (Bags: " .. bags .. ", Bank: " .. bank .. ")")

    -- Calculate total value
    local totalValue = auth * price
    self.valueText:SetText("Net Worth: " .. ShellcoinTicker:FormatMoney(totalValue))

    -- Update news feed
    self.newsText:SetText("|cffffd700Feed:|r " .. (ShellcoinTicker.lastEventMsg or "HODL!"))
end
