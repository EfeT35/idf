-- AutoGrabOwnBase - Minimal standalone script
-- Automatically grabs animals from your own base using proximity prompts

if not game:IsLoaded() then game.Loaded:Wait() end

-- ============================================================
-- SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- SYNCHRONIZER + GAME DATA MODULES
-- ============================================================
local Packages    = ReplicatedStorage:WaitForChild("Packages")
local Datas       = ReplicatedStorage:WaitForChild("Datas")
local Shared      = ReplicatedStorage:WaitForChild("Shared")
local Utils       = ReplicatedStorage:WaitForChild("Utils")

local Synchronizer  = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData   = require(Datas:WaitForChild("Animals"))
local AnimalsShared = require(Shared:WaitForChild("Animals"))
local NumberUtils   = require(Utils:WaitForChild("NumberUtils"))

-- ============================================================
-- STATE
-- ============================================================
local allAnimalsCache   = {}
local lastAnimalData    = {}
local PromptMemoryCache = {}
local lastOwnBaseGrabTime = 0

-- ============================================================
-- isMyBaseAnimal(animalData)
-- Returns true if the given animal belongs to the local player's plot
-- ============================================================
local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    local channel = Synchronizer:Get(plot.Name)
    if channel then
        local owner = channel:Get("Owner")
        if owner then
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "table" and owner.UserId then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "Instance" then
                return owner == LocalPlayer
            end
        end
    end
    return false
end

-- ============================================================
-- findAdorneeGlobal(animalData)
-- Finds the physical spawn part for an animal on its podium
-- ============================================================
local function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plots = Workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild(animalData.plot)
    if plot then
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            local podium = podiums:FindFirstChild(animalData.slot)
            if podium then
                local base = podium:FindFirstChild("Base")
                if base then
                    local spawn = base:FindFirstChild("Spawn")
                    if spawn then return spawn end
                    return base:FindFirstChildWhichIsA("BasePart") or base
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- findProximityPromptForAnimal(animalData)
-- Locates the proximity prompt for a given animal
-- ============================================================
local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end

    -- Return cached prompt if still valid
    local cp = PromptMemoryCache[animalData.uid]
    if cp and cp.Parent then return cp end

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end

    local ch = Synchronizer:Get(plot.Name)

    -- Fallback: no Synchronizer channel available
    if not ch then
        local podium = podiums:FindFirstChild(animalData.slot)
        if podium then
            local base = podium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if spawn then
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then
                            PromptMemoryCache[animalData.uid] = p
                            return p
                        end
                    end
                end
            end
        end
        return nil
    end

    local al = ch:Get("AnimalList")
    if not al then return nil end

    local brainrotName = animalData.name and animalData.name:lower() or ""
    local targetSlot   = animalData.slot

    -- Try to find the exact podium via AnimalList matching
    local foundPodium = nil
    for slot, ad in pairs(al) do
        if type(ad) == "table" and tostring(slot) == targetSlot then
            local aName  = ad.Index
            local aInfo  = AnimalsData[aName]
            if aInfo and (aInfo.DisplayName or aName):lower() == brainrotName then
                foundPodium = podiums:FindFirstChild(tostring(slot))
                break
            end
        end
    end

    -- Fallback: use slot directly
    if not foundPodium then
        foundPodium = podiums:FindFirstChild(animalData.slot)
    end

    if foundPodium then
        local base  = foundPodium:FindFirstChild("Base")
        local spawn = base and base:FindFirstChild("Spawn")
        if spawn then
            -- Try PromptAttachment first
            local attach = spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") and p.Enabled then
                        PromptMemoryCache[animalData.uid] = p
                        return p
                    end
                end
            end

            -- Fallback: find nearest prompt on the plot within horizontal range
            local startPos  = spawn.Position
            local slotX     = startPos.X
            local slotZ     = startPos.Z
            local nearestPrompt = nil
            local minDist   = math.huge

            for _, desc in pairs(plot:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled then
                    local part = desc.Parent
                    local promptPos = nil
                    if part and part:IsA("BasePart") then
                        promptPos = part.Position
                    elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then
                        promptPos = part.Parent.Position
                    end
                    if promptPos then
                        local checkStartY = startPos.Y
                        -- Special-case for pets whose name contains unusual substring
                        if brainrotName:find("la secret combinasion") then
                            checkStartY = startPos.Y - 5
                        end
                        local horizontalDist = math.sqrt((promptPos.X - slotX)^2 + (promptPos.Z - slotZ)^2)
                        if horizontalDist < 5 and promptPos.Y > checkStartY then
                            local yDist = promptPos.Y - checkStartY
                            if yDist < minDist then
                                minDist = yDist
                                nearestPrompt = desc
                            end
                        end
                    end
                end
            end

            if nearestPrompt then
                PromptMemoryCache[animalData.uid] = nearestPrompt
                return nearestPrompt
            end
        end
    end

    return nil
end

-- ============================================================
-- triggerOwnBaseGrab(prompt, animalUID)
-- Fires the proximity prompt to collect the animal
-- ============================================================
local function triggerOwnBaseGrab(prompt, animalUID)
    if not prompt or not prompt.Parent then return false end
    local now = os.clock()
    if now - lastOwnBaseGrabTime < 0.35 then return false end
    lastOwnBaseGrabTime = now
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, math.max(0.1, tonumber(prompt.HoldDuration) or 0))
        elseif prompt.InputHoldBegin and prompt.InputHoldEnd then
            prompt:InputHoldBegin()
            task.wait(math.max(0.1, tonumber(prompt.HoldDuration) or 0.08))
            prompt:InputHoldEnd()
        end
    end)
    return true
end

-- ============================================================
-- get_all_pets()
-- Returns a flat list of all animals currently in allAnimalsCache
-- that belong to the local player's base
-- ============================================================
local function get_all_pets()
    local out = {}
    for _, a in ipairs(allAnimalsCache) do
        if a.genValue >= 1 and isMyBaseAnimal(a) then
            table.insert(out, {
                petName   = a.name,
                mpsText   = a.genText,
                mpsValue  = a.genValue,
                owner     = a.owner,
                plot      = a.plot,
                slot      = a.slot,
                uid       = a.uid,
                mutation  = a.mutation,
                animalData = a,
            })
        end
    end
    return out
end

-- ============================================================
-- getNearestOwnBasePetIndex(pets)
-- Returns the index of the own-base animal closest to the player
-- ============================================================
local function getNearestOwnBasePetIndex(pets)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not pets then return nil end
    local bestIndex = nil
    local bestDist  = math.huge
    for i, p in ipairs(pets) do
        if p and p.animalData and isMyBaseAnimal(p.animalData) then
            local targetPart = findAdorneeGlobal(p.animalData)
            if targetPart and targetPart:IsA("BasePart") then
                local d = (hrp.Position - targetPart.Position).Magnitude
                if d < bestDist then
                    bestDist  = d
                    bestIndex = i
                end
            end
        end
    end
    return bestIndex
end

-- ============================================================
-- scanSinglePlot(plot)
-- Reads the Synchronizer data for a plot and updates allAnimalsCache
-- ============================================================
local function getAnimalHash(al, ownerName)
    if not al then return "" end
    local h = tostring(ownerName or "")
    for slot, d in pairs(al) do
        if type(d) == "table" then
            h = h .. tostring(slot) .. tostring(d.Index) .. tostring(d.Mutation)
        end
    end
    return h
end

local function scanSinglePlot(plot)
    pcall(function()
        local ch = Synchronizer:Get(plot.Name)
        if not ch then return end

        local al    = ch:Get("AnimalList")
        local owner = ch:Get("Owner")

        -- No valid owner or no animal list: clear this plot from cache
        if not owner or not owner.Name or not Players:FindFirstChild(owner.Name) then
            lastAnimalData[plot.Name] = nil
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                end
            end
            return
        end

        if not al then
            lastAnimalData[plot.Name] = nil
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                end
            end
            return
        end

        local ownerName = owner.Name
        local hash      = getAnimalHash(al, ownerName)

        -- No change since last scan
        if lastAnimalData[plot.Name] == hash then return end

        -- Remove stale entries for this plot
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end

        -- Insert updated entries
        for slot, ad in pairs(al) do
            if type(ad) == "table" then
                local aName = ad.Index
                local aInfo = AnimalsData[aName]
                if aInfo then
                    local mut = ad.Mutation or "None"
                    if mut == "Yin Yang" then mut = "YinYang" end
                    local traits = (ad.Traits and #ad.Traits > 0) and table.concat(ad.Traits, ", ") or "None"
                    local gv = AnimalsShared:GetGeneration(aName, ad.Mutation, ad.Traits, nil)
                    local gt = "$" .. NumberUtils:ToString(gv) .. "/s"

                    table.insert(allAnimalsCache, {
                        name     = aInfo.DisplayName or aName,
                        genText  = gt,
                        genValue = gv,
                        mutation = mut,
                        traits   = traits,
                        owner    = ownerName,
                        plot     = plot.Name,
                        slot     = tostring(slot),
                        uid      = plot.Name .. "_" .. tostring(slot),
                    })
                end
            end
        end

        lastAnimalData[plot.Name] = hash

        -- Keep cache sorted highest gen value first
        table.sort(allAnimalsCache, function(a, b)
            return a.genValue > b.genValue
        end)
    end)
end

-- ============================================================
-- Plot listener: scan on changes and on a periodic timer
-- ============================================================
local function setupPlotListener(plot)
    local ch, retries = nil, 0
    while not ch and retries < 50 do
        local ok, r = pcall(function() return Synchronizer:Get(plot.Name) end)
        if ok and r then
            ch = r
            break
        else
            retries = retries + 1
            task.wait(0.1)
        end
    end
    if not ch then return end

    scanSinglePlot(plot)
    plot.DescendantAdded:Connect(function()
        task.wait(0.1)
        scanSinglePlot(plot)
    end)
    plot.DescendantRemoving:Connect(function()
        task.wait(0.1)
        scanSinglePlot(plot)
    end)
    task.spawn(function()
        while plot.Parent do
            task.wait(5)
            scanSinglePlot(plot)
        end
    end)
end

local plots = Workspace:WaitForChild("Plots", 8)
if plots then
    for _, p in ipairs(plots:GetChildren()) do
        task.spawn(setupPlotListener, p)
    end
    plots.ChildAdded:Connect(function(p)
        task.wait(0.5)
        task.spawn(setupPlotListener, p)
    end)
    plots.ChildRemoved:Connect(function(p)
        lastAnimalData[p.Name] = nil
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == p.Name then
                table.remove(allAnimalsCache, i)
            end
        end
    end)
end

-- ============================================================
-- Heartbeat loop: find nearest own-base animal and grab it
-- ============================================================
local selectedTargetIndex = 1
local selectedTargetUID   = nil

RunService.Heartbeat:Connect(function()
    local pets = get_all_pets()
    if #pets == 0 then return end

    -- Update selection to nearest own-base animal each frame
    local ownBaseIndex = getNearestOwnBasePetIndex(pets)
    if ownBaseIndex then
        selectedTargetIndex = ownBaseIndex
        selectedTargetUID   = pets[ownBaseIndex].uid
    end

    -- Clamp index to valid range
    if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
    if selectedTargetIndex < 1    then selectedTargetIndex = 1     end

    local tp = pets[selectedTargetIndex]
    if not tp or not isMyBaseAnimal(tp.animalData) then return end

    -- Get cached or freshly-found prompt
    local pr = PromptMemoryCache[tp.uid]
    if not pr or not pr.Parent then
        pr = findProximityPromptForAnimal(tp.animalData)
    end

    if pr then
        triggerOwnBaseGrab(pr, tp.uid)
    end
end)
