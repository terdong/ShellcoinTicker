-- UI_Graph.lua
-- Graph Drawing Engine for ShellcoinTicker (Vanilla WoW 1.12)

-- LTTB (Largest Triangle Three Buckets) Downsampling helper
-- Reduces tempPoints to at most maxPoints while preserving visual fidelity.
-- preserveStart: number of leading points to keep intact (1 or 2)
-- Returns the downsampled points array.
local function LTTBDownsample(tempPoints, maxPoints, cutoff, priceAtCutoff)
    local N = table.getn(tempPoints)
    if N <= maxPoints then return tempPoints end

    local points = {}
    -- Determine how many leading points to preserve
    local preserveStart = 1
    if tempPoints[1].isVirtual then
        preserveStart = 2
        table.insert(points, tempPoints[1])
        table.insert(points, tempPoints[2])
    else
        table.insert(points, tempPoints[1])
    end

    local activeStartPt = points[table.getn(points)]
    local activeStart = activeStartPt.time
    local activeEnd = tempPoints[N].time
    local activeDuration = activeEnd - activeStart

    local numBuckets = maxPoints - preserveStart - 1
    if numBuckets < 1 then numBuckets = 1 end
    local w = activeDuration / numBuckets

    local buckets = {}
    local bucketAverages = {}
    for b = 1, numBuckets do
        buckets[b] = {}
    end

    -- Group interior points into buckets
    local interiorStart = preserveStart + 1
    for j = interiorStart, N - 1 do
        local entry = tempPoints[j]
        if entry.time then
            local b = math.floor((entry.time - activeStart) / w) + 1
            if b >= 1 and b <= numBuckets then
                table.insert(buckets[b], entry)
            elseif b > numBuckets then
                table.insert(buckets[numBuckets], entry)
            end
        end
    end

    -- Calculate averages for each bucket
    local lastKnownPrice = activeStartPt.price
    for b = 1, numBuckets do
        local pts = buckets[b]
        local count = table.getn(pts)
        if count > 0 then
            local sumTime = 0
            local sumPrice = 0
            for k = 1, count do
                sumTime = sumTime + pts[k].time
                sumPrice = sumPrice + pts[k].price
            end
            bucketAverages[b] = { time = sumTime / count, price = sumPrice / count }
            lastKnownPrice = pts[count].price
        else
            local bStart = activeStart + (b - 1) * w
            local bEnd = activeStart + b * w
            bucketAverages[b] = { time = (bStart + bEnd) / 2, price = lastKnownPrice }
        end
    end

    -- Select 1 point per bucket maximizing triangle area
    for b = 1, numBuckets do
        local p1 = points[table.getn(points)]
        local p3_x, p3_y = tempPoints[N].time, tempPoints[N].price
        for next_b = b + 1, numBuckets do
            local next_pts = buckets[next_b]
            if table.getn(next_pts) > 0 then
                p3_x, p3_y = bucketAverages[next_b].time, bucketAverages[next_b].price
                break
            end
        end

        local pts = buckets[b]
        local count = table.getn(pts)
        if count > 0 then
            local bestPoint = pts[1]
            local maxArea = -1
            local dx1 = p1.time - cutoff
            local dy1 = p1.price - priceAtCutoff
            local dx3 = p3_x - cutoff
            local dy3 = p3_y - priceAtCutoff

            for k = 1, count do
                local p2 = pts[k]
                local dx2 = p2.time - cutoff
                local dy2 = p2.price - priceAtCutoff
                local area = math.abs(
                    dx1 * (dy2 - dy3) +
                    dx2 * (dy3 - dy1) +
                    dx3 * (dy1 - dy2)
                )
                if area > maxArea then
                    maxArea = area
                    bestPoint = p2
                end
            end
            table.insert(points, bestPoint)
        end
    end

    table.insert(points, tempPoints[N])
    return points
end

function ShellcoinTicker.UI:UpdateGraph()
    if not self.frame or not ShellcoinTickerDB then return end

    -- Redraw Line Graph
    -- Hide all graph elements first
    for i = 1, self.MAX_POINTS do
        self.graphDots[i]:Hide()
        if self.graphHoverFrames and self.graphHoverFrames[i] then
            self.graphHoverFrames[i]:Hide()
        end
    end
    for i = 1, self.MAX_POINTS - 1 do
        self.graphHLines[i]:Hide()
        self.graphVLines[i]:Hide()
        self.graphBars[i]:Hide()
    end
    if self.graphHighlightLine then
        self.graphHighlightLine:Hide()
    end

    local price = ShellcoinTickerDB.price or 0

    -- Reuse cached activeHistory from UpdateDisplay() to avoid redundant filtering
    local activeHistory = self.cachedActiveHistory
    if not activeHistory then
        -- Fallback: build it if called standalone (safety net)
        activeHistory = {}
        local history = ShellcoinTickerDB.history
        local numPoints = history and table.getn(history) or 0
        if history then
            for i = 1, numPoints do
                local entry = history[i]
                if entry and type(entry) == "table" and entry.price and entry.price > 0 then
                    table.insert(activeHistory, entry)
                end
            end
        end
    end
    local numActivePoints = table.getn(activeHistory)

    local refTime = time()
    if ShellcoinTicker.speedrunMode then
        refTime = ShellcoinTicker.virtualTime
    elseif not ShellcoinTickerDB.mockMode then
        if numActivePoints > 0 then
            refTime = activeHistory[numActivePoints].time or time()
        end
    end

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
    elseif tf == "10y" then
        duration = 315360000
    end

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

        local numFiltered = table.getn(filtered)
        for i = 1, 14 do
            local iStart = startTime + (i - 1) * intervalWidth
            local iEnd = startTime + i * intervalWidth

            -- Find points in this interval
            local intervalPoints = {}
            for j = 1, numFiltered do
                local t = filtered[j].time
                if t >= iStart and t < iEnd then
                    table.insert(intervalPoints, filtered[j].price)
                end
            end

            local c = {}
            local numInterval = table.getn(intervalPoints)
            if numInterval > 0 then
                c.open = intervalPoints[1]
                c.close = intervalPoints[numInterval]
                c.high = intervalPoints[1]
                c.low = intervalPoints[1]
                for j = 1, numInterval do
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

        local candleWidth = drawWidth / 14
        for i = 1, 14 do
            local c = candles[i]
            local x = paddingX + (i - 1) * candleWidth + (candleWidth / 2)

            local yOpen = paddingY + ((c.open - minPrice) / (maxPrice - minPrice)) * drawHeight
            local yClose = paddingY + ((c.close - minPrice) / (maxPrice - minPrice)) * drawHeight
            local yHigh = paddingY + ((c.high - minPrice) / (maxPrice - minPrice)) * drawHeight
            local yLow = paddingY + ((c.low - minPrice) / (maxPrice - minPrice)) * drawHeight

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

        -- Cache active hover frame count for OnUpdate optimization
        self.graphActiveCount = 14
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
        local numFiltered = table.getn(filtered)
        for i = 1, numFiltered do
            local t = filtered[i].time
            if t > cutoff and t < refTime then
                table.insert(tempPoints, { time = t, price = filtered[i].price })
            end
        end
        -- Always insert the current price at the current time to extend the graph to the rightmost edge
        table.insert(tempPoints, { time = refTime, price = price })

        -- Mark virtual left boundary if history starts after cutoff
        if numActivePoints > 0 and activeHistory[1].time and activeHistory[1].time > cutoff then
            tempPoints[1].isVirtual = true
        end

        -- Downsample using LTTB helper
        local points = LTTBDownsample(tempPoints, self.MAX_POINTS, cutoff, priceAtCutoff)

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

            local priceRange = maxPrice - minPrice
            local lastX, lastY
            local sliceWidth = drawWidth / math.max(1, graphPointsCount - 1)
            for i = 1, graphPointsCount do
                local p = points[i].price
                local t = points[i].time
                local x = paddingX + ((t - cutoff) / duration) * drawWidth
                local y = paddingY + ((p - minPrice) / priceRange) * drawHeight

                -- Keep dots hidden, but position them so they can be shown on hover
                local dot = self.graphDots[i]
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", self.graphFrame, "BOTTOMLEFT", x, y)
                dot:Hide()

                -- Draw connectors and fill area
                if i > 1 then
                    local prevP = points[i - 1].price
                    local rL, gL, bL = 0.6, 0.6, 0.6 -- Gray default
                    if not points[i - 1].isVirtual then
                        if p > prevP then
                            rL, gL, bL = 0.0, 1.0, 0.2   -- Green rise
                        elseif p < prevP then
                            rL, gL, bL = 1.0, 0.2, 0.2   -- Red fall
                        end
                    end

                    -- Horizontal segment (+1 to width to eliminate corner gaps)
                    local hline = self.graphHLines[i - 1]
                    hline:ClearAllPoints()
                    hline:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", lastX, lastY)
                    hline:SetWidth(x - lastX + 1)
                    hline:SetHeight(1.5)
                    hline:SetTexture(rL, gL, bL, 0.8)
                    hline:Show()

                    -- Vertical segment
                    local vline = self.graphVLines[i - 1]
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
                    local bar = self.graphBars[i - 1]
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
                    hf.prevPrice = (i > 1) and points[i - 1].price or nil
                    hf.isPrevVirtual = (i > 1) and points[i - 1].isVirtual or nil
                    hf.x = x
                    hf.dot = dot
                    hf:Show()
                end

                lastX, lastY = x, y
            end

            -- Cache active hover frame count for OnUpdate optimization
            self.graphActiveCount = graphPointsCount
        else
            self.graphMaxText:Hide()
            self.graphMinText:Hide()
            self.graphActiveCount = 0
        end
    end
end

function ShellcoinTicker.UI.Graph_OnUpdate()
    local ui = ShellcoinTicker.UI
    local scale = ui.graphFrame:GetEffectiveScale()
    local left = ui.graphFrame:GetLeft()
    if not left then return end

    local xpos, ypos = GetCursorPosition()
    local mouseX = (xpos / scale) - left

    -- Use cached active count instead of iterating all MAX_POINTS
    local numActive = ui.graphActiveCount or 0
    if numActive == 0 then return end

    local closestIndex = nil
    local minDistance = 999999

    for i = 1, numActive do
        local hf = ui.graphHoverFrames[i]
        if hf and hf.x then
            local dist = math.abs(hf.x - mouseX)
            if dist < minDistance then
                minDistance = dist
                closestIndex = i
            end
        end
    end

    if not closestIndex then return end

    if closestIndex ~= ui.activeGraphIndex then
        -- Hide only the previously active dot instead of iterating all MAX_POINTS
        local prevIndex = ui.activeGraphIndex
        if prevIndex and ui.graphDots[prevIndex] then
            ui.graphDots[prevIndex]:Hide()
        end

        ui.activeGraphIndex = closestIndex

        local hf = ui.graphHoverFrames[closestIndex]

        GameTooltip:SetOwner(ui.graphFrame, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        if hf.isCandle then
            GameTooltip:AddLine("Candle Details", 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            local startTimeStr = date("%m/%d %H:%M", hf.startTime)
            local endTimeStr = date("%m/%d %H:%M", hf.endTime)
            GameTooltip:AddDoubleLine("Time Range:", startTimeStr .. " - " .. endTimeStr, 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Open:", ShellcoinTicker:FormatMoney(hf.open), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Close:", ShellcoinTicker:FormatMoney(hf.close), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("High:", ShellcoinTicker:FormatMoney(hf.high), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Low:", ShellcoinTicker:FormatMoney(hf.low), 1, 1, 1, 1, 1, 1)

            local diff = hf.close - hf.open
            local percent = (hf.open > 0) and ((diff / hf.open) * 100) or 0
            local changeText
            if diff > 0 then
                changeText = "|cff00ff00+" ..
                ShellcoinTicker:FormatMoney(diff) .. " (+" .. string.format("%.1f%%", percent) .. ")|r"
            elseif diff < 0 then
                changeText = "|cffff0000-" ..
                ShellcoinTicker:FormatMoney(math.abs(diff)) ..
                " (-" .. string.format("%.1f%%", math.abs(percent)) .. ")|r"
            else
                changeText = "|cff8888880.0%|r"
            end
            GameTooltip:AddDoubleLine("Change:", changeText, 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine("Price Details", 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Time:", date("%Y/%m/%d %H:%M", hf.time), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Price:", ShellcoinTicker:FormatMoney(hf.price), 1, 1, 1, 1, 1, 1)

            if hf.prevPrice and hf.prevPrice > 0 and not hf.isPrevVirtual then
                local diff = hf.price - hf.prevPrice
                local percent = (diff / hf.prevPrice) * 100
                local changeText
                if diff > 0 then
                    changeText = "|cff00ff00+" ..
                    ShellcoinTicker:FormatMoney(diff) .. " (+" .. string.format("%.1f%%", percent) .. ")|r"
                elseif diff < 0 then
                    changeText = "|cffff0000-" ..
                    ShellcoinTicker:FormatMoney(math.abs(diff)) ..
                    " (-" .. string.format("%.1f%%", math.abs(percent)) .. ")|r"
                else
                    changeText = "|cff8888880.0%|r"
                end
                GameTooltip:AddDoubleLine("Change:", changeText, 1, 1, 1, 1, 1, 1)
            end
        end

        GameTooltip:Show()

        -- Show dot only for area mode
        if not hf.isCandle and ui.graphDots[closestIndex] then
            ui.graphDots[closestIndex]:Show()
        end

        if ui.graphHighlightLine and hf.x then
            ui.graphHighlightLine:ClearAllPoints()
            ui.graphHighlightLine:SetPoint("TOPLEFT", ui.graphFrame, "TOPLEFT", hf.x, -8)
            ui.graphHighlightLine:SetPoint("BOTTOMLEFT", ui.graphFrame, "BOTTOMLEFT", hf.x, 8)
            ui.graphHighlightLine:Show()
        end
    end
end
