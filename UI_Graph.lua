-- UI_Graph.lua
-- Graph Drawing Engine for ShellcoinTicker (Vanilla WoW 1.12)

function ShellcoinTicker.UI:UpdateGraph()
    if not self.frame or not ShellcoinTickerDB then return end
    
    -- Redraw Line Graph
    -- Hide all graph elements first
    for i = 1, 15 do
        self.graphDots[i]:Hide()
        if self.graphHoverFrames and self.graphHoverFrames[i] then
            self.graphHoverFrames[i]:Hide()
        end
    end
    for i = 1, 14 do
        self.graphHLines[i]:Hide()
        self.graphVLines[i]:Hide()
        self.graphBars[i]:Hide()
    end
    if self.graphHighlightLine then
        self.graphHighlightLine:Hide()
    end
    
    local price = ShellcoinTickerDB.price or 0
    local history = ShellcoinTickerDB.history
    local numPoints = history and table.getn(history) or 0
    
    -- Filter out 0-price placeholders for sparkline and graph to avoid skewed scaling
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
    
    -- Filter history based on selected timeframe
    local tf = ShellcoinTickerDB.selectedTimeframe
    if tf == "10m" or not tf then
        tf = "1h"
        ShellcoinTickerDB.selectedTimeframe = "1h"
    end
    local duration = 3600 -- 1h
    if tf == "1d" then
        duration = 86400
    elseif tf == "1w" then
        duration = 604800 -- 1w
    elseif tf == "1mo" then
        duration = 2592000
    elseif tf == "1y" then
        duration = 31536000
    end
    
    local refTime = ShellcoinTicker.speedrunMode and ShellcoinTicker.virtualTime or time()
    local cutoff = refTime - duration
    local filtered = {}
    
    for i = 1, numActivePoints do
        local entry = activeHistory[i]
        if entry.time and entry.time >= cutoff and entry.time <= refTime then
            table.insert(filtered, entry)
        end
    end
    
    -- Dimensions of drawing area inside the 256x60 graphFrame
    local graphWidth = 256
    local graphHeight = 60
    local paddingX = 12
    local paddingY = 8
    local drawWidth = graphWidth - (paddingX * 2)
    local drawHeight = graphHeight - (paddingY * 2)
    
    local graphMode = ShellcoinTickerDB.graphMode or "area"
    
    if graphMode == "candle" then
        -- 1. CANDLESTICK GRAPH MODE (14 Candles)
        local startTime = cutoff
        local endTime = refTime
        local intervalWidth = (endTime - startTime) / 14
        
        local candles = {}
        local lastKnownPrice = price
        
        -- Find the last price before cutoff
        for i = numActivePoints, 1, -1 do
            local entry = activeHistory[i]
            if entry.time and entry.time < cutoff then
                lastKnownPrice = entry.price
                break
            end
        end
        
        for i = 1, 14 do
            local iStart = startTime + (i - 1) * intervalWidth
            local iEnd = startTime + i * intervalWidth
            
            -- Find points in this interval
            local intervalPoints = {}
            for j = 1, table.getn(filtered) do
                local t = filtered[j].time
                if t >= iStart and t < iEnd then
                    table.insert(intervalPoints, filtered[j].price)
                end
            end
            
            local c = {}
            if table.getn(intervalPoints) > 0 then
                c.open = intervalPoints[1]
                c.close = intervalPoints[table.getn(intervalPoints)]
                c.high = intervalPoints[1]
                c.low = intervalPoints[1]
                for j = 1, table.getn(intervalPoints) do
                    local p = intervalPoints[j]
                    if p > c.high then c.high = p end
                    if p < c.low then c.low = p end
                end
                lastKnownPrice = c.close
            else
                -- No points: flat candle
                c.open = lastKnownPrice
                c.close = lastKnownPrice
                c.high = lastKnownPrice
                c.low = lastKnownPrice
            end
            table.insert(candles, c)
        end
        
        -- Find overall min/max prices of all wicks
        local minPrice = candles[1].low
        local maxPrice = candles[1].high
        for i = 2, 14 do
            if candles[i].low < minPrice then minPrice = candles[i].low end
            if candles[i].high > maxPrice then maxPrice = candles[i].high end
        end
        
        -- Pad flat range to avoid division by zero
        if minPrice == maxPrice then
            minPrice = math.max(0, minPrice - 100)
            maxPrice = maxPrice + 100
        end
        
        self.graphMaxText:SetText("Max: " .. ShellcoinTicker:FormatMoney(maxPrice))
        self.graphMinText:SetText("Min: " .. ShellcoinTicker:FormatMoney(minPrice))
        self.graphMaxText:Show()
        self.graphMinText:Show()
        
        local function GetY(p)
            return paddingY + ((p - minPrice) / (maxPrice - minPrice)) * drawHeight
        end
        
        local candleWidth = drawWidth / 14
        for i = 1, 14 do
            local c = candles[i]
            local x = paddingX + (i - 1) * candleWidth + (candleWidth / 2)
            
            local yOpen = GetY(c.open)
            local yClose = GetY(c.close)
            local yHigh = GetY(c.high)
            local yLow = GetY(c.low)
            
            -- Color code: Green (rise), Red (fall), Gray (flat)
            local r, g, b = 0.6, 0.6, 0.6
            if c.close > c.open then
                r, g, b = 0.0, 1.0, 0.2 -- Bullish green
            elseif c.close < c.open then
                r, g, b = 1.0, 0.2, 0.2 -- Bearish red
            end
            
            -- 1. Wick (VLine)
            local wick = self.graphVLines[i]
            wick:ClearAllPoints()
            wick:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", x - 0.75, yLow)
            wick:SetWidth(1.5)
            wick:SetHeight(math.max(1, yHigh - yLow))
            wick:SetTexture(r, g, b, 0.8)
            wick:Show()
            
            -- 2. Body (HLines repurposed as the body box)
            local body = self.graphHLines[i]
            body:ClearAllPoints()
            local yBottom = math.min(yOpen, yClose)
            local yTop = math.max(yOpen, yClose)
            body:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", x - (candleWidth / 2 - 2), yBottom)
            body:SetWidth(math.max(2, candleWidth - 4))
            body:SetHeight(math.max(2, yTop - yBottom))
            body:SetTexture(r, g, b, 0.9)
            body:Show()

            -- 3. Hover Frame
            local hf = self.graphHoverFrames[i]
            if hf then
                local iStart = startTime + (i - 1) * intervalWidth
                local iEnd = startTime + i * intervalWidth
                hf:ClearAllPoints()
                hf:SetWidth(candleWidth)
                hf:SetHeight(graphHeight)
                hf:SetPoint("CENTER", self.graphFrame, "BOTTOMLEFT", x, graphHeight / 2)
                hf.isCandle = true
                hf.startTime = iStart
                hf.endTime = iEnd
                hf.open = c.open
                hf.close = c.close
                hf.high = c.high
                hf.low = c.low
                hf.x = x
                hf.dot = nil
                hf:Show()
            end
        end
        
    else
        -- 2. AREA GRAPH MODE (WITH RISE/FALL COLOR CODING)
        -- Determine boundary price at the cutoff time
        local priceAtCutoff = price
        if numActivePoints > 0 then
            priceAtCutoff = activeHistory[1].price
        end
        for i = numActivePoints, 1, -1 do
            local entry = activeHistory[i]
            if entry.time and entry.time < cutoff then
                priceAtCutoff = entry.price
                break
            end
        end
        
        -- Build raw points covering full boundary from cutoff to refTime without duplicates
        local tempPoints = {}
        table.insert(tempPoints, { time = cutoff, price = priceAtCutoff })
        for i = 1, table.getn(filtered) do
            local t = filtered[i].time
            if t > cutoff and t < refTime then
                table.insert(tempPoints, { time = t, price = filtered[i].price })
            end
        end
        table.insert(tempPoints, { time = refTime, price = price })
        
        -- Downsample tempPoints to at most 15 points (keeping boundary points intact)
        local points = {}
        local N = table.getn(tempPoints)
        if N <= 15 then
            for i = 1, N do
                table.insert(points, tempPoints[i])
            end
        else
            local step = (N - 1) / 14
            for i = 1, 15 do
                local index = math.floor(1 + (i - 1) * step + 0.5)
                table.insert(points, tempPoints[index])
            end
        end
        
        local graphPointsCount = table.getn(points)
        
        if graphPointsCount > 0 then
            local minPrice = points[1].price
            local maxPrice = points[1].price
            for i = 1, graphPointsCount do
                if points[i].price < minPrice then minPrice = points[i].price end
                if points[i].price > maxPrice then maxPrice = points[i].price end
            end
            
            -- Pad flat range
            if minPrice == maxPrice then
                minPrice = math.max(0, minPrice - 100)
                maxPrice = maxPrice + 100
            end
            
            self.graphMaxText:SetText("Max: " .. ShellcoinTicker:FormatMoney(maxPrice))
            self.graphMinText:SetText("Min: " .. ShellcoinTicker:FormatMoney(minPrice))
            self.graphMaxText:Show()
            self.graphMinText:Show()
            
            local function GetY(p)
                return paddingY + ((p - minPrice) / (maxPrice - minPrice)) * drawHeight
            end
            
            local lastX, lastY
            local sliceWidth = drawWidth / math.max(1, graphPointsCount - 1)
            for i = 1, graphPointsCount do
                local p = points[i].price
                local t = points[i].time
                local x = paddingX + ((t - cutoff) / duration) * drawWidth
                local y = GetY(p)
                
                -- Keep dots hidden, but position them so they can be shown on hover
                local dot = self.graphDots[i]
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", self.graphFrame, "BOTTOMLEFT", x, y)
                dot:Hide()
                
                -- Draw connectors and fill area
                if i > 1 then
                    local prevP = points[i-1].price
                    local rL, gL, bL = 0.6, 0.6, 0.6 -- Gray default
                    if p > prevP then
                        rL, gL, bL = 0.0, 1.0, 0.2 -- Green rise
                    elseif p < prevP then
                        rL, gL, bL = 1.0, 0.2, 0.2 -- Red fall
                    end
                    
                    -- Horizontal segment (+1 to width to eliminate corner gaps)
                    local hline = self.graphHLines[i-1]
                    hline:ClearAllPoints()
                    hline:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", lastX, lastY)
                    hline:SetWidth(x - lastX + 1)
                    hline:SetHeight(1.5)
                    hline:SetTexture(rL, gL, bL, 0.8)
                    hline:Show()
                    
                    -- Vertical segment
                    local vline = self.graphVLines[i-1]
                    local yMin = math.min(lastY, y)
                    local yMax = math.max(lastY, y)
                    if yMax - yMin > 0.5 then
                        vline:ClearAllPoints()
                        vline:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", x, yMin)
                        vline:SetWidth(1.5)
                        vline:SetHeight(yMax - yMin)
                        vline:SetTexture(rL, gL, bL, 0.8)
                        vline:Show()
                    else
                        vline:Hide()
                    end
                    
                    -- Shaded area fill underneath (+1 to width to eliminate corner gaps)
                    local bar = self.graphBars[i-1]
                    bar:ClearAllPoints()
                    bar:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", lastX, paddingY)
                    bar:SetWidth(x - lastX + 1)
                    bar:SetHeight(math.max(1, lastY - paddingY))
                    bar:SetGradientAlpha("VERTICAL", rL, gL, bL, 0.02, rL, gL, bL, 0.30)
                    bar:Show()
                end

                -- Position hover frame
                local hf = self.graphHoverFrames[i]
                if hf then
                    hf:ClearAllPoints()
                    hf:SetWidth(sliceWidth)
                    hf:SetHeight(graphHeight)
                    hf:SetPoint("CENTER", self.graphFrame, "BOTTOMLEFT", x, graphHeight / 2)
                    hf.isCandle = false
                    hf.time = t
                    hf.price = p
                    hf.prevPrice = (i > 1) and points[i-1].price or nil
                    hf.x = x
                    hf.dot = dot
                    hf:Show()
                end
                
                lastX, lastY = x, y
            end
        else
            self.graphMaxText:Hide()
            self.graphMinText:Hide()
        end
    end
end
