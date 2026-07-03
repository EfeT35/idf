-- v24
if not game:IsLoaded() then game.Loaded:Wait() end

-- LPH macro fallbacks (no-ops when not running under Luraph obfuscation)
if LPH_OBFUSCATED == nil then
    local env = getfenv()
    env["LPH_NO_" .. "VIRTUALIZE"] = function(...) return ... end
    env["LPH_JIT_" .. "MAX"]       = function(...) return ... end
end

do
    for _, fn in ipairs({ setfpscap, set_fps_cap }) do
        if type(fn) == "function" then
            pcall(fn, 144)
        end
    end
end

-- =====================================================================
-- Services
-- =====================================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")

-- Game Stretcher
local _STRETCH_MAT  = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.8, 0, 0, 0, 1)
local _stretchBound = false
local function _bindStretch()
    if _stretchBound then return end
    _stretchBound = true
    pcall(function()
        RunService:BindToRenderStep("MeerkoGameStretch", 2001, function()
            if not (_G.MeerkoConfig and _G.MeerkoConfig.GameStretcher) then
                pcall(function() RunService:UnbindFromRenderStep("MeerkoGameStretch") end)
                _stretchBound = false
                return
            end
            local cam = workspace.CurrentCamera
            if cam then cam.CFrame = cam.CFrame * _STRETCH_MAT end
        end)
    end)
end
local function _unbindStretch()
    _stretchBound = false
    pcall(function() RunService:UnbindFromRenderStep("MeerkoGameStretch") end)
end
_G.MeerkoStretchEnable  = _bindStretch
_G.MeerkoStretchDisable = _unbindStretch


local LP = Players.LocalPlayer

task.spawn(function()
    if type(getconnections) ~= "function" then return end
    local getinfo = debug and debug.getinfo
    if type(getinfo) ~= "function" then return end
    local _cr = cloneref or function(x) return x end
    local lp = _cr(game:GetService("Players")).LocalPlayer
    while not lp do task.wait(0.2); lp = _cr(game:GetService("Players")).LocalPlayer end

    local function Strip()
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        for _, sig in ipairs({ "CFrame", "Position" }) do
            local okC, conns = pcall(getconnections, hrp:GetPropertyChangedSignal(sig))
            if okC and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local f = c.Function
                    if f and c.Enabled then
                        local okInfo, info = pcall(getinfo, f)
                        if okInfo and info and info.source == "=ReplicatedFirst.test" then
                            pcall(function() c:Disable() end)
                        end
                    end
                end
            end
        end
    end

    while true do
        pcall(Strip)
        task.wait(3)
    end
end)

do
    local function killAnims(char)
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok and tracks then
                for _, t in ipairs(tracks) do pcall(function() t:Stop(0) end) end
            end
        end
        local animate = char:FindFirstChild("Animate")
        if animate then pcall(function() animate.Disabled = true end) end
    end
    local function restoreAnims(char)
        if not char then return end
        local animate = char:FindFirstChild("Animate")
        if animate then pcall(function() animate.Disabled = false end) end
    end
    -- exposed so the Animations toggle can flip behaviour live
    _G.MeerkoKillAnims = killAnims
    _G.MeerkoRestoreAnims = restoreAnims
    local function setup(char)
        if not char then return end
        char:WaitForChild("Humanoid", 5)
        if _G.MeerkoAnimations and not _G.MeerkoTPForceNoAnims then restoreAnims(char); return end
        killAnims(char)
        -- Animate can re-enable itself for a moment after spawn; re-kill a few times.
        for i = 1, 6 do task.delay(i * 0.3, function() if (not _G.MeerkoAnimations) or _G.MeerkoTPForceNoAnims then killAnims(char) end end) end
    end
    if LP.Character then task.spawn(function() setup(LP.Character) end) end
    LP.CharacterAdded:Connect(function(char) task.spawn(function() setup(char) end) end)
end

-- =====================================================================
-- Fusing / machine-block helper (used by scanAllPets)
-- =====================================================================
local _BLOCKING_MACHINE_TYPES = {
    Fuse     = true,
    Duel     = true,
    Trade    = true,
    Crafting = true,
}
local function _VanishIsFusing(animalData)
    if type(animalData) ~= "table" then return false end
    local m = animalData.Machine
    if type(m) ~= "table" then return false end
    return _BLOCKING_MACHINE_TYPES[m.Type] == true
end

-- =====================================================================
-- =====================================================================
do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local getupvalue = getupvalue or debug.getupvalue

    local function getInternalTable()
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        if not Packages then return nil end
        local SynMod = Packages:FindFirstChild("Synchronizer")
        if not SynMod then return nil end
        local ok, syn = pcall(require, SynMod)
        if not ok or not syn then return nil end
        local Get = syn.Get
        if type(Get) ~= "function" then return nil end
        for i = 1, 5 do
            local s, u = pcall(getupvalue, Get, i)
            if s and type(u) == "table" then
                if u.___private or u.___channels or u.___data then return u end
                for k, v in pairs(u) do
                    if (type(k) == "string" and k:match("^Plot_")) or type(v) == "table" then
                        return u
                    end
                end
            end
        end
        local s, e = pcall(getfenv, Get)
        if s and e and e.self then return e.self end
        return nil
    end

    local SyncInt = {_cache = {}, _data = nil}
    _G.SyncInt = SyncInt

    task.spawn(function()
        for i = 1, 10 do
            SyncInt._data = getInternalTable()
            if SyncInt._data then break end
            task.wait(1)
        end
    end)

    function _G.stealthGet(n)
        if not n or type(n) ~= "string" then return nil end
        if SyncInt._cache[n] == false then return nil end
        if SyncInt._data then
            for _, k in ipairs({n, "Plot_" .. n, "Plot" .. n, n .. "_Channel", "Channel_" .. n}) do
                if SyncInt._data[k] then
                    SyncInt._cache[n] = SyncInt._data[k]
                    return SyncInt._data[k]
                end
            end
            for k, v in pairs(SyncInt._data) do
                if type(k) == "string" and (k == n or k:find(n, 1, true)) and type(v) == "table" then
                    SyncInt._cache[n] = v
                    return v
                end
            end
        end
        SyncInt._cache[n] = false
        return nil
    end

    function _G.sProp(ch, p)
        if not ch or type(ch) ~= "table" then return nil end
        if ch[p] then return ch[p] end
        if type(ch.Get) == "function" then
            local ok, r = pcall(ch.Get, ch, p)
            if ok then return r end
        end
        local alts = {
            Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
            AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"},
        }
        if alts[p] then
            for _, a in ipairs(alts[p]) do
                if ch[a] then return ch[a] end
            end
        end
        return nil
    end

    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    local SynMod = Packages and Packages:FindFirstChild("Synchronizer")
    local okReq, syn = pcall(require, SynMod)
    if okReq and typeof(syn) == "table" then
        local function HasBoolUpvalue(Fn)
            local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
            if not OkU then return false end
            for _, V in pairs(Ups) do
                if typeof(V) == "boolean" then return true end
            end
            return false
        end
        local _islc = islclosure or function() return true end
        for _, Fn in pairs(syn) do
            if typeof(Fn) == "function" and not isexecutorclosure(Fn) and _islc(Fn) then
                local OkU, Ups = pcall(debug.getupvalues, Fn)
                if OkU and type(Ups) == "table" then
                    for Idx, V in pairs(Ups) do
                        if typeof(V) == "function" and not isexecutorclosure(V) and _islc(V) and HasBoolUpvalue(V) then
                            pcall(debug.setupvalue, Fn, Idx, newcclosure(function() end))
                            break
                        end
                    end
                end
            end
        end
    end
end

-- =====================================================================
do
    if hookfunction and _G.VanishNetBypass ~= false then
        local orig
        local newHook = newcclosure(function(self, ...)
            -- Type-guard: hook could fire with weird self under some executors
            if typeof(self) ~= "Instance" then
                if orig then return orig(self, ...) end
                return
            end
            local name = self.Name
            -- Capture the first RE/* remote the game itself fires -- the
            -- heartbeat anti-cheat remote the insta-reset spams.
            if not _G.MeerkoResetRemote and name and name:sub(1, 3) == "RE/" then
                _G.MeerkoResetRemote = self
                _G.CapturedResetRemote = self
            end
            local arg1 = (...)
            if name and #name == 67 and type(arg1) == "string" and string.find(arg1, "StopTrying") then
                return
            end
            if orig then return orig(self, ...) end
        end)
        pcall(function()
            local installed = hookfunction(Instance.new("RemoteEvent").FireServer, newHook)
            if installed then
                orig = installed
                if not getgenv()._vanish_fs_original then
                    getgenv()._vanish_fs_original = installed
                end
            else
                orig = getgenv()._vanish_fs_original
            end
        end)
    end
end

-- =====================================================================
-- INSTA RESET (remote method)
local _instaResetCooldown = false
_G.MeerkoInstaReset = function()
    if _instaResetCooldown then return end
    if not _G.MeerkoResetRemote then return end
    _instaResetCooldown = true
    _G.MeerkoSkipAutoTPUntil = os.clock() + 8   -- block the auto-TP chain after a manual reset
    local LP = game:GetService("Players").LocalPlayer
    local oldChar = LP.Character
    task.spawn(function()
        local startT = os.clock()
        while LP.Character == oldChar and os.clock() - startT < 5 do
            pcall(function() _G.MeerkoResetRemote:FireServer("randomstring") end)
            task.wait()
        end
        _instaResetCooldown = false
    end)
end

-- =====================================================================
-- Sync data fetch helper
-- =====================================================================
_G.VanishGetSyncData = _G.VanishGetSyncData or function(plot)
    local plotName = type(plot) == "string" and plot or (plot and plot.Name)
    if not plotName then return nil end
    local Pkgs = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    local Sync = Pkgs and Pkgs:FindFirstChild("Synchronizer")
    if not Sync then return nil end
    local okMod, mod = pcall(require, Sync)
    if not okMod or type(mod) ~= "table" then return nil end

    local okT, data = pcall(function() return mod:GetTableFromChannel(plotName) end)
    if okT and type(data) == "table" then return data end

    local okC, ch = pcall(function() return mod:Get(plotName) end)
    if okC and ch then
        local synth = { __channel = ch }
        pcall(function() synth.AnimalList = ch:Get("AnimalList") end)
        pcall(function() synth.Owner      = ch:Get("Owner") end)
        return synth
    end
    return nil
end

-- =====================================================================
-- Module loaders
-- =====================================================================
local Synchronizer, AnimalsData, AnimalsShared, NumberUtils

local function loadModules()
    if Synchronizer then return true end
    local ok = pcall(function()
        local Packages = RS:WaitForChild("Packages", 5)
        local Datas = RS:WaitForChild("Datas", 5)
        local Shared = RS:WaitForChild("Shared", 5)
        local Utils = RS:WaitForChild("Utils", 5)
        Synchronizer = require(Packages:WaitForChild("Synchronizer"))
        AnimalsData = require(Datas:WaitForChild("Animals"))
        AnimalsShared = require(Shared:WaitForChild("Animals"))
        NumberUtils = require(Utils:WaitForChild("NumberUtils"))
    end)
    return ok and Synchronizer ~= nil
end

local NetModule
local function loadNet()
    if NetModule then return true end
    local ok, mod = pcall(function()
        return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
    end)
    if not ok or type(mod) ~= "table" then return false end
    NetModule = mod
    return true
end

local function fireGrapple()
    if not NetModule then loadNet() end
    if not NetModule then return end
    local char = LP.Character
    if not char then return end
    if not char:FindFirstChild("Grapple Hook") then
        local bp = LP:FindFirstChild("Backpack")
        local tool = bp and bp:FindFirstChild("Grapple Hook")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if tool and hum then pcall(function() hum:EquipTool(tool) end) end
    end
    if not char:FindFirstChild("Grapple Hook") then return end
    pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
end
_G.VanishFireGrapple = fireGrapple

-- ===== fast carpet mover =====
local CARPET_SPEED = 280
local INBASE_SPEED = 450
local SKY_CLONE_WAIT = 0.35
local CARPET_NAMES = { "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet" }
local function findTool(name)
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end
local GRAPPLE_NAMES = { "Grapple Hook", "Grappling Hook", "Grapple", "Hook", "Web Slinger", "Grapple Gun", "GrappleHook" }
local function findGrapple()
    for _, n in ipairs(GRAPPLE_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then return t, n end
    end
    return nil
end
local function listTools()
    local out, char, bp = {}, LP.Character, LP:FindFirstChild("Backpack")
    if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then out[#out + 1] = t.Name end end end
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then out[#out + 1] = t.Name end end end
    return table.concat(out, ", ")
end
local function equipCarpet()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    -- honor the user's chosen mount if they own it; otherwise fall back to
    -- auto-detecting whatever flying tool is available.
    local pref = _G.MeerkoCarpetTool
    if pref and pref ~= "Auto" then
        local t = findTool(pref)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return pref
        end
    end
    for _, n in ipairs(CARPET_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end
-- equip grapple -> wait -> FireServer(2) -> wait -> unequip -> wait -> equip carpet
local function carpetEngage()
    if not NetModule then pcall(loadNet) end
    local _t0 = os.clock()
    while not findTool("Grapple Hook") and os.clock() - _t0 < 5 do
        if not NetModule then pcall(loadNet) end
        RunService.Heartbeat:Wait()
    end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    -- equip grapple
    if not char:FindFirstChild("Grapple Hook") then
        local g = findTool("Grapple Hook")
        if g then pcall(function() hum:EquipTool(g) end) end
    end
    task.wait(0.01)
    -- fire server
    if NetModule and LP.Character and LP.Character:FindFirstChild("Grapple Hook") then
        pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
    end
    task.wait(0.15)
    -- unequip
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h then pcall(function() h:UnequipTools() end) end
    task.wait(0.15)
    local cn
    local _tc = os.clock()
    repeat
        cn = equipCarpet()
        local c = LP.Character
        if cn and c and c:FindFirstChild(cn) then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _tc > 1
    _G.TPEngage = "carpet=" .. tostring(cn)
    return cn
end

-- =====================================================================
-- Pet priority data tables
-- =====================================================================
local PET_PRIORITY_TIERS = {
    [1] = { pets = {"Headless Horseman"}, threshold = 0 },
    [2] = { pets = {"Signore Carapace"}, threshold = 0 },
    [3] = { pets = {"John Pork"}, threshold = 0 },
    [4] = { pets = {"Strawberry Elephant"}, threshold = 0 },
    [5] = { pets = {"Arcadragon"}, threshold = 5e9 },
    [6] = { pets = {"Elefanto Frigo"}, threshold = 10e9 },
    [7] = { pets = {"Meowl"}, threshold = 5e9 },
    [8] = { pets = {"Skibidi Toilet"}, threshold = 5e9 },
    [9] = { pets = {"Love Love Bear"}, threshold = 0 },
    [10] = { pets = {"Antonio"}, threshold = 0 },
    [11] = { pets = {"Pancake and Syrup"}, threshold = 0 },
    [12] = { pets = {"Griffin"}, threshold = 0 },
    [13] = { pets = {"Globa Steppa","La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
    [14] = { pets = {"Ginger Gerat","Pet"}, threshold = 10e9 },
    [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"}, threshold = 3e9 },
    [16] = { pets = {"Hydra Dragon Cannelloni","Dragon Cannelloni","Bunny and Eggy"}, threshold = 3e9 },
    [17] = { pets = {"Ketupat Bros","Rosey and Teddy","La Casa Boo","Fragola la la"}, threshold = 3e9 },
    [18] = { pets = {"Fragola La La La","Cerberus","Guest 666","Los Hackers"}, threshold = 1e9 },
    [19] = { pets = {"Garama and Madundung","Spooky and Pumpky","Reinito Sleighito","Burguro And Fryuro","Cooki and Milki","Fragrama and Chocrama","La Food Combinasion","Los Amigos","Foxini Lanternini","Capitano Moby","Fortunu and Cashuru","Los Sekolahs","Celestial Pegasus"}, threshold = 750e6 },
    [20] = { pets = {"La Secret Combinasion","Sammyni Fattini","Cloverat Clapat","Popcuru and Fizzuru"}, threshold = 1e9 },
}

local TIER_LOOKUP = {}
for tier, data in pairs(PET_PRIORITY_TIERS) do
    for _, name in ipairs(data.pets) do TIER_LOOKUP[name] = tier end
end

local LOCKED_TIERS = { [1]=true, [2]=true, [3]=true, [4]=true }

local DIRECT_THRESHOLDS = {
    [3] = { [4] = 10e9 },
    [4] = {},
    [5] = { [6] = math.huge },
    [6] = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
    [10] = { [12] = 20e9 },
    [11] = { [12] = 10e9 },
}

local MUTATION_PRIORITY = {
    ["Galaxy"]=1,["Candy"]=1,["Yin Yang"]=1,["YinYang"]=1,["Divine"]=1,
    ["Cursed"]=1,["Lava"]=1,["Radioactive"]=1,["Cyber"]=1,["Rainbow"]=1,["Bloodrot"]=2,
}

local MUTATED_BEATS_GRIFFIN = {
    ["Fishino Clownino"]=true,["Globa Steppa"]=true,
    ["La Supreme Combinasion"]=true,["Tirilikalika Tirilikalako"]=true,
}

local function getMutPrio(m)
    if not m or m == "" or m == "None" then return 0 end
    if MUTATION_PRIORITY[m] then return MUTATION_PRIORITY[m] end
    local n = tostring(m):lower():gsub("[%s%-_]","")
    if n == "bloodrot" then return 2 end
    if n == "yinyang" or n == "galaxy" or n == "candy" or n == "divine"
        or n == "cursed" or n == "lava" or n == "radioactive" or n == "cyber"
        or n == "rainbow" then return 1 end
    return 0
end

local function getCumThreshold(hi, lo)
    if DIRECT_THRESHOLDS[hi] and DIRECT_THRESHOLDS[hi][lo] then return DIRECT_THRESHOLDS[hi][lo] end
    if LOCKED_TIERS[hi] then return math.huge end
    local total = 0
    for t = hi + 1, lo do
        local td = PET_PRIORITY_TIERS[t]
        if td and td.threshold > 0 then total = total + td.threshold end
    end
    return total
end

local function _normName(s)
    -- lowercase + strip spaces/punctuation so "La Vacca Saturno", "lavaccasaturno",
    -- "St Patrick's" etc. all match regardless of how the priority entry was typed.
    return tostring(s):lower():gsub("[%s%-_'%.]", "")
end

local function _priIndexOf(name)
    local list = _G.SHARED_PRIORITY_ITEMS
    if type(list) ~= "table" or not name then return math.huge end
    local target = _normName(name)
    for i, entry in ipairs(list) do
        if _normName(entry) == target then return i end
    end
    return math.huge
end

local function petOutranks(aName, bName, aMut, bMut, aMPS, bMPS)
    local iA = _priIndexOf(aName)
    local iB = _priIndexOf(bName)
    if iA ~= iB then return iA < iB end
    return (aMPS or 0) > (bMPS or 0)
end

-- =====================================================================
-- Plot / channel helpers
-- =====================================================================
local function getPlotChannel(plotName)
    if not Synchronizer then return nil end
    local channel
    pcall(function() channel = Synchronizer:Get(plotName) end)
    if not channel then pcall(function() channel = Synchronizer:Wait(plotName) end) end
    return channel
end

local function channelGet(channel, key)
    if not channel then return nil end
    local v
    pcall(function() if type(channel.Get) == "function" then v = channel:Get(key) end end)
    if v == nil then pcall(function() v = channel.CacheTable and channel.CacheTable[key] end) end
    return v
end

local function isMyPlot(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local result = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            result = owner.UserId == LP.UserId
        elseif type(owner) == "table" and owner.UserId then
            result = owner.UserId == LP.UserId
        elseif typeof(owner) == "Instance" then
            result = owner == LP
        end
    end)
    return result
end

local function ownerInGame(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local inGame = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        elseif type(owner) == "number" then
            inGame = Players:GetPlayerByUserId(owner) ~= nil
        elseif type(owner) == "table" and owner.Name then
            inGame = Players:FindFirstChild(tostring(owner.Name)) ~= nil
        elseif typeof(owner) == "Instance" and owner.Name then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        end
    end)
    return inGame
end

local function getPetPosition(plot, slot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(slot))
    if not podium then return nil end

    for _, desc in ipairs(podium:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
            local hasMesh = false
            for _, c in ipairs(desc:GetDescendants()) do
                if c:IsA("MeshPart") then hasMesh = true; break end
            end
            if hasMesh then
                local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                if ok then return cf.Position end
            end
        end
    end

    local ok, cf = pcall(function() return podium:GetPivot() end)
    if ok then return cf.Position end
    return podium.Position
end

local function scanAllPets()
    local pets = {}
    if not loadModules() then return pets end

    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return pets end

    for _, plot in ipairs(Plots:GetChildren()) do
        local channel = getPlotChannel(plot.Name)
        if not channel then continue end
        if isMyPlot(channel) then continue end
        if not ownerInGame(channel) then continue end

        local animalList = channelGet(channel, "AnimalList")
        if not animalList then continue end

        for slot, animalData in pairs(animalList) do
            if type(animalData) ~= "table" then continue end
            local animalName = animalData.Index
            if not animalName then continue end
            local animalInfo = AnimalsData and AnimalsData[animalName]
            if not animalInfo then continue end
            if _VanishIsFusing(animalData) then continue end

            local mutation = animalData.Mutation or "None"
            local genValue = 0
            pcall(function()
                genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
            end)

            local displayName = (animalInfo and animalInfo.DisplayName) or animalName
            local pos = getPetPosition(plot, slot)

            if pos then
                table.insert(pets, {
                    name = displayName,
                    index = animalName,
                    mps = genValue,
                    mutation = mutation,
                    position = pos,
                    plot = plot.Name,
                    slot = tostring(slot),
                })
            end
        end
    end

    local _priLk = {}
    do
        local plist = _G.SHARED_PRIORITY_ITEMS
        if type(plist) == "table" then
            for i = #plist, 1, -1 do _priLk[_normName(plist[i])] = i end
        end
    end
    for _, p in ipairs(pets) do
        local ia = _priLk[_normName(p.name)] or math.huge
        local ib = _priLk[_normName(p.index)] or math.huge
        p._pri = (ia < ib) and ia or ib
    end
    table.sort(pets, function(a, b)
        if a._pri ~= b._pri then return a._pri < b._pri end
        return (a.mps or 0) > (b.mps or 0)
    end)

    return pets
end

-- =====================================================================
-- Sky platform coordinate tables + constants
-- =====================================================================
local UPPER = {
    B = {{coord=Vector3.new(-487.921448,16.850713,-75.768013),facing="NORTH"},{coord=Vector3.new(-332.379730,16.850722,-75.762100),facing="NORTH"},{coord=Vector3.new(-487.134918,16.850713,-18.094154),facing="SOUTH"},{coord=Vector3.new(-316.300171,16.850713,-17.845898),facing="SOUTH"}},
    C = {{coord=Vector3.new(-330.765381,16.850713,31.424425),facing="NORTH"},{coord=Vector3.new(-502.989349,16.850713,31.172430),facing="NORTH"},{coord=Vector3.new(-489.077087,16.850713,89.010147),facing="SOUTH"},{coord=Vector3.new(-330.908936,16.850713,88.930145),facing="SOUTH"}},
    D = {{coord=Vector3.new(-331.264893,16.850713,138.209167),facing="NORTH"},{coord=Vector3.new(-487.935181,16.850713,138.026321),facing="NORTH"},{coord=Vector3.new(-487.774933,16.850713,195.882538),facing="SOUTH"},{coord=Vector3.new(-330.799133,16.850575,196.022354),facing="SOUTH"}},
}
local LOWER = {
    B = {{coord=Vector3.new(-335.725586,-3.048217,-74.984589),facing="NORTH"},{coord=Vector3.new(-503.214233,-3.048217,-75.043137),facing="NORTH"},{coord=Vector3.new(-483.619385,-3.718430,-18.844337),facing="SOUTH"},{coord=Vector3.new(-316.147095,-3.048218,-18.818844),facing="SOUTH"}},
    C = {{coord=Vector3.new(-335.985413,-3.048218,32.051426),facing="NORTH"},{coord=Vector3.new(-503.277008,-3.048217,31.956175),facing="NORTH"},{coord=Vector3.new(-483.749390,-3.048218,88.147003),facing="SOUTH"},{coord=Vector3.new(-315.793823,-3.048217,88.163979),facing="SOUTH"}},
    D = {{coord=Vector3.new(-335.476654,-3.048218,139.001083),facing="NORTH"},{coord=Vector3.new(-503.710083,-3.048218,138.989883),facing="NORTH"},{coord=Vector3.new(-315.654938,-3.048218,195.302444),facing="SOUTH"},{coord=Vector3.new(-483.859253,-3.048218,195.269043),facing="SOUTH"}},
}
local UPPER_Y_THRESHOLD = 7
local TALL_PETS = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
local TALL_OFFSET = 3

local BASES_LOW = {
    [1] = Vector3.new(-476.52, -2, 220.94090270996094),
    [2] = Vector3.new(-476.52, -2, 113.77315521240234),
    [3] = Vector3.new(-476.52, -2, 6.178487777709961),
    [4] = Vector3.new(-476.52, -2, -101.07275390625),
    [5] = Vector3.new(-342.66, -2, 221.44737243652344),
    [6] = Vector3.new(-342.66, -2, 113.41409301757812),
    [7] = Vector3.new(-342.66, -2, 6.249461650848389),
    [8] = Vector3.new(-342.66, -2, -99.73458862304688),
}
local BASES_HIGH = {
    [1] = Vector3.new(-479.51, 18, 220.94090270996094),
    [2] = Vector3.new(-479.51, 18, 113.77315521240234),
    [3] = Vector3.new(-479.51, 18, 6.178487777709961),
    [4] = Vector3.new(-479.51, 18, -101.07275390625),
    [5] = Vector3.new(-339.48, 18, 221.44737243652344),
    [6] = Vector3.new(-339.48, 18, 113.41409301757812),
    [7] = Vector3.new(-339.48, 18, 6.249461650848389),
    [8] = Vector3.new(-339.48, 18, -99.73458862304688),
}
local FRONT_Y_LOW   = -3.048217   -- standalone LOWER platform layer
local FRONT_Y_HIGH  = 16.850713   -- standalone UPPER platform layer
local COLUMN_SPLIT_X = -410       -- between the west (idx 1-4) and east (idx 5-8) base columns
local FRONT_Z_CLAMP  = 18         -- front slides toward the player within +/-this of the base center (off the corner pillars)
local SIDE_NEAR_Z    = 45         -- a side platform belongs to a base if within this Z of its center (own ~25, neighbor ~80)

-- Pet's base index 1..8: planar (XZ) nearest base center, like the 400KB reference.
local function getClosestBaseIdx(pos)
    local closest, dist = 1, math.huge
    for i = 1, 8 do
        local b = BASES_LOW[i]
        local d = (pos.X - b.X)^2 + (pos.Z - b.Z)^2
        if d < dist then dist = d; closest = i end
    end
    return closest
end

-- FRONT (center of the front face) staging coord + (Vector3) facing for a base.
local function buildFrontCandidate(idx, isUpper, playerZ)
    local base = isUpper and BASES_HIGH[idx] or BASES_LOW[idx]
    local frontY = isUpper and FRONT_Y_HIGH or FRONT_Y_LOW
    local frontZ = math.clamp(playerZ - base.Z, -FRONT_Z_CLAMP, FRONT_Z_CLAMP) + base.Z
    local coord = Vector3.new(base.X, frontY, frontZ)
    local faceDir = (idx <= 4) and Vector3.new(-1, 0, 0) or Vector3.new(1, 0, 0)
    return coord, faceDir
end

local function plotSides(coordTable, idx)
    local base = BASES_LOW[idx]
    local isWest = idx <= 4
    local out = {}
    for _, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            if ((data.coord.X < COLUMN_SPLIT_X) == isWest)
               and math.abs(data.coord.Z - base.Z) < SIDE_NEAR_Z then
                out[#out + 1] = data
            end
        end
    end
    return out
end

local function _floor1LaserSolid(plotName)
    local solid = false
    pcall(function()
        local Plots = workspace:FindFirstChild("Plots")
        local plot = Plots and Plots:FindFirstChild(plotName)
        if not plot then return end
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name == "LaserHitbox" or d.Name == "Laser")
                and d.CanCollide and d.Position.Y <= 9 then
                solid = true
                break
            end
        end
    end)
    return solid
end

local function isPlotUnlocked(plotName)
    local ok, res = pcall(function()
        local channel = getPlotChannel(plotName)
        if not channel then return false end
        if channelGet(channel, "BlockEndTimeFirstFloor") ~= nil then return false end
        -- channel says open -- require the physical laser to agree before flying in
        return not _floor1LaserSolid(plotName)
    end)
    return ok and (res == true)
end

local function findClosest(petPos, coordTable)
    local best, bestKey, bestDist = nil, nil, math.huge
    for skyKey, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            local c = data.coord
            local d = math.sqrt((petPos.X - c.X)^2 + (petPos.Z - c.Z)^2)
            if d < bestDist then bestDist = d; best = data; bestKey = skyKey end
        end
    end
    return best, bestKey
end

-- =====================================================================
-- Path visualization helpers
-- =====================================================================
local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end
local function vizLine(a, b, color)
    local d = b - a
    if d.Magnitude < 0.05 then return end
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(0.4, 0.4, d.Magnitude)
    p.CFrame = CFrame.new((a + b) / 2, b)
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizDot(pos, color, sz)
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(sz, sz, sz)
    p.Position = pos
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizPath(fromPos, waypoints)
    if #waypoints == 0 then return end
    vizDot(fromPos, Color3.fromRGB(255, 255, 255), 1.8)
    local prev = fromPos
    for _, wp in ipairs(waypoints) do
        vizLine(prev, wp, Color3.fromRGB(0, 255, 120))
        vizDot(wp, Color3.fromRGB(255, 200, 0), 1.6)
        prev = wp
    end
end

-- =====================================================================
-- Velocity mover
-- =====================================================================
local SPEED = 125
local ARRIVE = 3
local _STRIP_OK = (type(getconnections) == "function")
local function _climbCap()
    local v = math.clamp(tonumber(_G.VanishClimb) or 200, 100, 250)
    if not _STRIP_OK then v = 55 end
    return v
end

local _tpLVAtt, _tpLV
local function lvDrive(hrp, v)
    if not hrp or not hrp.Parent then return end
    if not (_tpLV and _tpLV.Parent and _tpLVAtt and _tpLVAtt.Parent == hrp) then
        if _tpLV then pcall(function() _tpLV:Destroy() end) end
        if _tpLVAtt then pcall(function() _tpLVAtt:Destroy() end) end
        _tpLVAtt = Instance.new("Attachment")
        _tpLVAtt.Name = "VanishTPAtt"
        _tpLVAtt.Parent = hrp
        _tpLV = Instance.new("LinearVelocity")
        _tpLV.Name = "VanishTPLV"
        _tpLV.Attachment0 = _tpLVAtt
        _tpLV.RelativeTo = Enum.ActuatorRelativeTo.World
        pcall(function() _tpLV.ForceLimitsEnabled = false end)
        _tpLV.MaxForce = math.huge
        _tpLV.VectorVelocity = Vector3.zero
        _tpLV.Parent = hrp
    end
    _tpLV.VectorVelocity = v
end
local function lvStop(hrp)
    if _tpLV then pcall(function() _tpLV:Destroy() end); _tpLV = nil end
    if _tpLVAtt then pcall(function() _tpLVAtt:Destroy() end); _tpLVAtt = nil end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end
local function vZero(hrp)
    lvStop(hrp)
end

local function velMoveThrough(hrp, waypoints, speedOverride, allowJump, quickStart)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    local _runSpeed = speedOverride or (_G.TPVelocity and math.clamp(_G.TPVelocity, 200, 500)) or CARPET_SPEED
    local wpIdx = 1
    local done = false
    local conn
    local function finish()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            lvStop(hrp)
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
    end
    local function cancelStop()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            lvStop(hrp)
        end
        if conn then conn:Disconnect() end
    end
    local lastDist, stall = math.huge, 0

    local _ = quickStart
    do
        local peak = hrp.Position.Y
        for _, wp in ipairs(waypoints) do if wp.Y > peak then peak = wp.Y end end
        if peak > hrp.Position.Y + 3 then
            local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                pcall(function() hum.Jump = true end)
            end
        end
    end

    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end
            return
        end
        if _G.MeerkoTPCancel then cancelStop() return end
        equipCarpet()
        local target = waypoints[wpIdx]
        local diff = target - hrp.Position
        local mag = diff.Magnitude
        local _spd = _runSpeed
        if wpIdx < #waypoints and mag < 26 then
            local nxt = waypoints[wpIdx + 1]
            local b = nxt - target
            if mag > 0.1 and b.Magnitude > 0.1 and diff.Unit:Dot(b.Unit) < 0.9 then
                _spd = math.min(_spd, 240)
            end
        end
        local _arr = math.max(ARRIVE, _spd / 60 * 1.25)
        if mag < _arr then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish() return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff = target - hrp.Position
            mag = diff.Magnitude
        end

        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish() return end
        if mag >= 0.1 then
            local dir = diff.Unit
            if (allowJump or diff.Y > 10) and diff.Y > 5 and wpIdx < #waypoints then
                local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
                if hum then
                    local st = hum:GetState()
                    if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                        pcall(function() hum.Jump = true end)
                    end
                end
            end
            local _sp = _spd
            local _mc = _climbCap()
            if dir.Y > 0 and dir.Y * _sp > _mc then
                _sp = _mc / dir.Y
            end
            lvDrive(hrp, Vector3.new(dir.X * _sp, dir.Y * _sp, dir.Z * _sp))
        end
    end)
    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do
        totalDist = totalDist + (prev - wp).Magnitude
        prev = wp
    end
    local timeout = totalDist / math.min(SPEED, _runSpeed) + 2
    local elapsed = 0
    while not done and elapsed < timeout do
        task.wait(0.05)
        elapsed = elapsed + 0.05
        if _G.MeerkoTPCancel then break end
    end
    if _G.MeerkoTPCancel then cancelStop() else finish() end
    vZero(hrp)
end

-- =====================================================================
-- Raycast / route-pulling helpers
-- =====================================================================
local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _STRUCT = { ["structure base home"] = true, ["Wall"] = true, ["Floor"] = true, ["Roof"] = true }
local _SKIP_NAME = { ["DeliveryHitbox"]=true, ["StealHitbox"]=true, ["LaserHitbox"]=true,
    ["AnimalTarget"]=true, ["Multiplier"]=true, ["Laser"]=true, ["Hitbox"]=true,
    ["Spawn"]=true, ["MainRoot"]=true, ["SecondFloor"]=true, ["ThirdFloor"]=true, ["Slope"]=true }
local function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 150 then return true end
    return false
end
local function _blocksWide(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    -- Lower area threshold than _blocks (150 -> 30) so smaller non-collidable
    -- objects near the path count against the clearance margin.
    if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 30 then return true end
    return false
end
local function _block(origin, target, blockFn)
    blockFn = blockFn or _blocks
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local o = origin
    for _ = 1, 16 do
        rp.FilterDescendantsInstances = skip
        local d = target - o
        if d.Magnitude < 0.05 then return nil end
        local res = workspace:Raycast(o, d, rp)
        if not res then return nil end
        if blockFn(res.Instance) then return res end
        skip[#skip + 1] = res.Instance
        o = res.Position + d.Unit * 0.3
    end
    return nil
end
local function _clear(a, b) return _block(a, b) == nil end
local function _clearDist(origin, dir, maxD)
    local res = _block(origin, origin + dir.Unit * maxD)
    if not res then return maxD end
    return (res.Position - origin).Magnitude
end
local function _len(pts)
    local s, prev = 0, pts[1]
    for k = 2, #pts do s = s + (pts[k] - prev).Magnitude; prev = pts[k] end
    return s
end
local function _pull(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clear(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end
local function _stages(toPos)
    local st = {}
    for _, dr in ipairs(_DIRS) do
        local cd = _clearDist(toPos, dr, 46)
        if cd >= 12 then st[#st + 1] = toPos + dr * math.min(cd - 5, 38) end
    end
    return st
end
local function _routeClear(pts)
    for i = 1, #pts - 1 do
        if not _clear(pts[i], pts[i + 1]) then return false end
    end
    return true
end
local function _peakY(pts)
    local m = -math.huge
    for _, p in ipairs(pts) do if p.Y > m then m = p.Y end end
    return m
end
local function _starts(fromPos)
    local pts = { fromPos }
    if _block(fromPos, fromPos + Vector3.new(0, 40, 0)) then
        for _, dr in ipairs(_DIRS) do
            local cd = _clearDist(fromPos, dr, 40)
            if cd >= 12 then pts[#pts + 1] = fromPos + dr * math.min(cd - 5, 34) end
        end
    end
    return pts
end

local function _candidates(sp, stage, toPos)
    local list = {}
    local function add(mid)
        if mid then list[#list + 1] = { sp, mid, stage, toPos }
        else list[#list + 1] = { sp, stage, toPos } end
    end
    add(nil)
    add(Vector3.new(stage.X, sp.Y, stage.Z))
    add(Vector3.new(sp.X, stage.Y, sp.Z))
    local dir = Vector3.new(stage.X - sp.X, 0, stage.Z - sp.Z)
    if dir.Magnitude > 0.1 then
        dir = dir.Unit
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        for _, off in ipairs({ 20, -20, 40, -40 }) do
            add(sp + perp * off)
        end
    end
    return list
end

local PathfindingService = game:GetService("PathfindingService")
local _CLEARANCE = 16
local function _clearWideRay(a, b)
    return _block(a, b, _blocksWide) == nil
end
local _SWEEP_R = 4
local _ENDPOINT_SLACK = 6
local _canSphere = nil
local function _sweepDir(a, b)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local o = a
    for _ = 1, 24 do
        rp.FilterDescendantsInstances = skip
        local d = b - o
        if d.Magnitude < 0.05 then return false end
        local res
        local ok = pcall(function() res = workspace:Spherecast(o, _SWEEP_R, d, rp) end)
        if not ok then _canSphere = false; return nil end
        if not res then return false end
        if _blocks(res.Instance) then return true end
        skip[#skip + 1] = res.Instance
        local adv = (res.Distance or 0) - 0.05
        if adv > 0 then o = o + d.Unit * math.min(adv, d.Magnitude) end
    end
    return true
end
local function _sweepBlocked(a, b, slackA, slackB)
    if _canSphere == nil then
        _canSphere = pcall(function()
            workspace:Spherecast(Vector3.new(0, 10000, 0), 1, Vector3.new(0, -1, 0), RaycastParams.new())
        end)
    end
    if not _canSphere then return nil end
    local d = b - a
    local len = d.Magnitude
    if len < 0.1 then return false end
    local u = d / len
    local a2 = a + u * math.min(slackA or _ENDPOINT_SLACK, len * 0.4)
    local b2 = b - u * math.min(slackB or _ENDPOINT_SLACK, len * 0.4)
    local fwd = _sweepDir(a2, b2)
    if fwd == nil then return nil end
    if fwd then return true end
    local rev = _sweepDir(b2, a2)
    if rev == nil then return nil end
    return rev
end

local function _clearWide(a, b, slackA, slackB)
    -- Center line must be clear (normal block test).
    if not _clear(a, b) then return false end
    local sw = _sweepBlocked(a, b, slackA, slackB)
    if sw ~= nil then return not sw end
    local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
    if d.Magnitude < 0.1 then
        local ox = Vector3.new(_CLEARANCE, 0, 0)
        local oz = Vector3.new(0, 0, _CLEARANCE)
        return _clearWideRay(a + ox, b + ox) and _clearWideRay(a - ox, b - ox)
            and _clearWideRay(a + oz, b + oz) and _clearWideRay(a - oz, b - oz)
    end
    local perp = Vector3.new(-d.Z, 0, d.X).Unit * _CLEARANCE
    local up = Vector3.new(0, _CLEARANCE, 0)
    return _clearWideRay(a + perp, b + perp)
        and _clearWideRay(a - perp, b - perp)
        and _clearWideRay(a + up, b + up)
        and _clearWideRay(a - up, b - up)
end

local function _pullWide(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    local n = #pts
    while i < n do
        local j = n
        while j > i + 1 do
            local a, b = out[#out], pts[j]
            -- endpoint slack only where the merged segment touches the route's
            -- true start/end; interior corners get the full-strength sweep.
            local sA = (i == 1) and _ENDPOINT_SLACK or 0
            local sB = (j == n) and _ENDPOINT_SLACK or 0
            if _clearWide(a, b, sA, sB) then break end
            j = j - 1
        end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end

local function _pushOffWalls(pts)
    if #pts <= 2 then return pts end
    local MARGIN = 8
    local MAX_PUSH = 12
    local out = { pts[1] }
    for i = 2, #pts - 1 do
        local p = pts[i]
        local shift = Vector3.zero
        for _, dr in ipairs(_DIRS) do
            local res = _block(p, p + dr * MARGIN, _blocks)
            if res then
                local dist = (res.Position - p).Magnitude
                if dist < MARGIN then
                    shift = shift - dr * (MARGIN - dist)
                end
            end
        end
        do
            local resUp = _block(p, p + Vector3.new(0, MARGIN, 0), _blocks)
            if resUp then
                local dist = (resUp.Position - p).Magnitude
                if dist < 4 then shift = shift + Vector3.new(0, -(4 - dist), 0) end
            end
        end
        if shift.Magnitude > 0.1 then
            if shift.Magnitude > MAX_PUSH then shift = shift.Unit * MAX_PUSH end
            local moved = p + shift
            if _clear(out[#out], moved) then
                out[#out + 1] = moved
            else
                out[#out + 1] = p
            end
        else
            out[#out + 1] = p
        end
    end
    out[#out + 1] = pts[#pts]
    return out
end

local function computeRoute(fromPos, toPos, facingDir, maxLift)
    -- maxLift caps how high the over-the-top candidates may climb; small for the
    -- post-clone approach and tall for the main flight.
    maxLift = maxLift or 44
    -- Direct shot only when the whole swept volume is clear -- the old center-ray
    -- accept let the body clip corners/props on "clear" lines.
    if _clearWide(fromPos, toPos) then return { toPos } end
    local entry = facingDir and (toPos - facingDir * 14) or toPos

    -- Candidate router: build several route shapes, keep only those whose EVERY
    -- segment passes the swept-volume test, string-pull each, take the shortest.
    local best, bestLen = nil, math.huge
    local function consider(pts)
        if not pts or #pts < 2 then return end
        local n = #pts
        for i = 1, n - 1 do
            local a, b = pts[i], pts[i + 1]
            if (a - b).Magnitude > 0.5 then
                local sA = (i == 1) and _ENDPOINT_SLACK or 0
                local sB = (i == n - 1) and _ENDPOINT_SLACK or 0
                if not _clearWide(a, b, sA, sB) then return end
            end
        end
        local pulled = _pullWide(pts)
        local L = _len(pulled)
        if L < bestLen then best, bestLen = pulled, L end
    end

    do
        local baseY = math.max(fromPos.Y, entry.Y)
        local mid = (fromPos + entry) * 0.5
        for _, lift in ipairs({ 10, 16, 24, 34, maxLift }) do
            if lift <= maxLift then
                local cy = baseY + lift
                local apexMid = Vector3.new(mid.X, cy, mid.Z)
                local apexEntry = Vector3.new(entry.X, cy, entry.Z)
                consider({ fromPos, apexMid, entry })
                consider({ fromPos, apexEntry, entry })
                consider({ fromPos, apexMid, apexEntry, entry })
            end
        end
    end

    -- 1b) OVER-THE-TOP right angle (straight up, cross, drop): longer than the
    --     diagonals so it only wins when no gradual rise verifies.
    do
        local baseY = math.max(fromPos.Y, entry.Y)
        for _, lift in ipairs({ 14, 22, 32, maxLift }) do
            if lift <= maxLift then
                local cy = baseY + lift
                consider({ fromPos,
                    Vector3.new(fromPos.X, cy, fromPos.Z),
                    Vector3.new(entry.X, cy, entry.Z),
                    entry })
            end
        end
    end

    -- 2) LATERAL: sidestep around the blocker at flight height, both sides,
    --    increasing offsets (single kink, then a parallel dogleg).
    do
        local dirF = Vector3.new(entry.X - fromPos.X, 0, entry.Z - fromPos.Z)
        if dirF.Magnitude > 0.1 then
            dirF = dirF.Unit
            local perp = Vector3.new(-dirF.Z, 0, dirF.X)
            local midBase = (fromPos + entry) * 0.5
            for _, off in ipairs({ 14, -14, 24, -24, 38, -38 }) do
                consider({ fromPos, midBase + perp * off, entry })
                consider({ fromPos, fromPos + perp * off, entry + perp * off, entry })
            end
        end
    end

    -- 3) NAVMESH: PathfindingService ground route floated up, as before -- but
    --    now it competes on length and is segment-verified like the others.
    local navRaw
    do
        local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
        local path = PathfindingService:CreatePath({
            AgentRadius = 16, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 10, AgentMaxSlope = 89,
        })
        local FLOAT = 5
        local nav = { fromPos }
        local ok = pcall(function()
            path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
        end)
        if ok and path.Status == Enum.PathStatus.Success then
            local last = fromPos
            for _, wp in ipairs(path:GetWaypoints()) do
                if (wp.Position - last).Magnitude >= 8 then
                    nav[#nav + 1] = wp.Position + Vector3.new(0, FLOAT, 0)
                    last = wp.Position
                end
            end
        end
        nav[#nav + 1] = entry + Vector3.new(0, FLOAT, 0)
        nav = _pushOffWalls(nav)
        navRaw = nav
        consider(nav)
    end

    local route = best
    if not route and _clear(fromPos, toPos) then route = { toPos } end
    if not route then route = _pullWide(navRaw) end
    if (route[#route] - toPos).Magnitude > 0.5 then
        route[#route + 1] = toPos
    end
    return route
end

-- =====================================================================
-- Tool helpers
-- =====================================================================
local function equipTool(name)
    local char = LP.Character
    if not char or char:FindFirstChild(name) then return char ~= nil end
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return false end
    local tool = bp:FindFirstChild(name)
    if tool and tool:IsA("Tool") then tool.Parent = char; return true end
    return false
end

local function unequipAll()
    local char, bp = LP.Character, LP.Backpack
    if not char or not bp then return end
    for _, t in pairs(char:GetChildren()) do
        if t:IsA("Tool") then t.Parent = bp end
    end
end

-- =====================================================================
-- Clone swap
-- =====================================================================
local function doClone()
    -- xen's clone method: equip the Quantum Cloner, then fire the two remotes
    -- directly (no clone-model polling, no UI-button clicking).
    if not NetModule then pcall(loadNet) end
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return false end

    local cloner = (LP:FindFirstChild("Backpack") and LP.Backpack:FindFirstChild("Quantum Cloner"))
                or char:FindFirstChild("Quantum Cloner")
    if not cloner then return false end

    if cloner.Parent ~= char then
        pcall(function() hum:EquipTool(cloner) end)
        task.wait()
    end

    if not NetModule then return false end

    local useOk = pcall(function() NetModule:RemoteEvent("UseItem"):FireServer() end)
    task.wait(0.05)
    local telOk = pcall(function() NetModule:RemoteEvent("QuantumCloner/OnTeleport"):FireServer() end)

    return useOk and telOk
end


-- =====================================================================
-- xen-style tween-to-pet (CFrame step tween at TPTravelSpeed). Used by
-- goToBrainrot to tween directly onto the brainrot after the clone.
-- =====================================================================
local _TweenTS = game:GetService("TweenService")
local function xenTween(rootPart, hum, targetPos, lookDir)
    if not rootPart or not rootPart.Parent then return end
    local STEP = 20
    local speed = (_G.TPTravelSpeed or 100)
    local hasLook = lookDir ~= nil and lookDir.Magnitude > 0.001
    local prevAnchored = rootPart.Anchored
    lvStop(rootPart)
    pcall(function() rootPart.Anchored = true end)
    local deadline = os.clock() + 12
    while rootPart and rootPart.Parent and os.clock() < deadline do
        local pos = rootPart.Position
        local toTarget = targetPos - pos
        local d = toTarget.Magnitude
        if d < 0.5 then break end
        local stepDist = math.min(STEP, d)
        local stepGoal = pos + toTarget.Unit * stepDist
        local stepCF
        if hasLook then
            stepCF = CFrame.lookAt(stepGoal, stepGoal + lookDir)
        else
            stepCF = (rootPart.CFrame - rootPart.CFrame.Position) + stepGoal
        end
        local dur = math.clamp(stepDist / speed, 0.02, 1)
        local tw = _TweenTS:Create(rootPart, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = stepCF })
        tw:Play()
        tw.Completed:Wait()
    end
    pcall(function() rootPart.Anchored = prevAnchored end)
    if rootPart and rootPart.Parent then lvStop(rootPart) end
end

-- Tween directly to the pet after the clone (xen tween-to-pet behavior).
local function goToBrainrot(petPos)
    if not petPos then return end
    local char, hrp
    local _t0 = os.clock()
    repeat
        char = LP.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _t0 > 2
    if not hrp then return end
    pcall(function() hrp.Anchored = false end)
    equipCarpet()

    -- Fly onto the brainrot (same mover as the main TP).
    local h = petPos.Y
    local targetY = hrp.Position.Y
    if h > 23.15 then targetY = 21
    elseif h >= 11 and h <= 23.15 then targetY = 14.5
    elseif h >= -6.9 and h <= 8.9 then targetY = -4 end
    local _to = Vector3.new(petPos.X, targetY, petPos.Z)
    -- Third floor: pre-place the platform BEFORE moving there (like xen).
    if h > 23.15 then
        local _plat = Instance.new("Part")
        _plat.Name = "XenHubTempPlatform"
        _plat.Size = Vector3.new(3, 1, 3)
        _plat.Position = _to - Vector3.new(0, 5, 0)
        _plat.Anchored = true
        _plat.CanCollide = true
        _plat.Transparency = 1
        _plat.Material = Enum.Material.SmoothPlastic
        _plat.Parent = workspace
        task.spawn(function()
            local _s = tick()
            while tick() - _s < 20 do
                if LP:GetAttribute("Stealing") then break end
                task.wait(0.1)
            end
            if _plat and _plat.Parent then _plat:Destroy() end
        end)
    end
    local _route = computeRoute(hrp.Position, _to, nil, 12)
    if not _route or #_route == 0 then _route = { _to } end
    velMoveThrough(hrp, _route, math.clamp(tonumber(_G.VanishGoSpeed) or 600, 80, 700))
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

-- =====================================================================
-- Main entry: doVelocityTP
-- =====================================================================
local isTeleporting = false

local function doVelocityTP()
    if isTeleporting then return end
    isTeleporting = true
    _G.MeerkoTPCancel = false
    if not _G.MeerkoTPStartedAt then _G.MeerkoTPStartedAt = os.clock() end  -- first TP start (admin panel waits on this)
    clearViz()
    if not NetModule then pcall(loadNet) end

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then isTeleporting = false; return end

    local allPets = scanAllPets()
    if #allPets == 0 then
        local _t0 = os.clock()
        while #allPets == 0 and os.clock() - _t0 < 4 do
            if _G.MeerkoTPCancel then isTeleporting = false; return end
            task.wait(0.15)
            allPets = scanAllPets()
        end
    end
    if #allPets == 0 then isTeleporting = false; return end
    if _G.MeerkoTPCancel then isTeleporting = false; return end

    local pet = allPets[1]
    do
        local overrideUID = _G.MeerkoStealTargetUID
        local overridePet = nil
        if overrideUID then
            for _, p in ipairs(allPets) do
                if (tostring(p.plot) .. "|" .. tostring(p.slot)) == overrideUID then
                    overridePet = p
                    break
                end
            end
            if not overridePet then
                _G.MeerkoStealTargetUID = nil
            end
        end

        local mode = _G.MeerkoStealMode
        if overridePet then
            pet = overridePet
        elseif mode == "highest" then
            local best = allPets[1]
            for _, p in ipairs(allPets) do
                if (p.mps or 0) > (best.mps or 0) then best = p end
            end
            pet = best
        elseif mode == "nearest" then
            local best, bestD = nil, math.huge
            for _, p in ipairs(allPets) do
                local d = (hrp.Position - p.position).Magnitude
                if d < bestD then bestD = d; best = p end
            end
            pet = best or allPets[1]
        end
    end
    local petPos = pet.position
    local petName = pet.name

    local _animOn = _G.MeerkoAnimations == true
    local _animTok
    if _animOn then
        _animTok = (_G._tpAnimToken or 0) + 1
        _G._tpAnimToken = _animTok
        _G.MeerkoTPForceNoAnims = true
        if _G.MeerkoKillAnims and LP.Character then pcall(_G.MeerkoKillAnims, LP.Character) end
        task.delay(30, function()   -- safety: never leave anims off forever
            if _G._tpAnimToken == _animTok then
                _G.MeerkoTPForceNoAnims = false
                if _G.MeerkoAnimations and LP.Character and _G.MeerkoRestoreAnims then pcall(_G.MeerkoRestoreAnims, LP.Character) end
            end
        end)
    end
    local function _restoreAnims()
        if _animOn and _G._tpAnimToken == _animTok then
            _G.MeerkoTPForceNoAnims = false
            if _G.MeerkoAnimations and LP.Character and _G.MeerkoRestoreAnims then pcall(_G.MeerkoRestoreAnims, LP.Character) end
        end
    end

    local adjY = petPos.Y
    if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
    local coordTable = adjY > UPPER_Y_THRESHOLD and UPPER or LOWER

    if petPos.Y <= 8.9 and isPlotUnlocked(pet.plot) then
        local maxHP = hum.MaxHealth
        hum.Health = maxHP
        local healConn = RunService.Heartbeat:Connect(function()
            if hum and hum.Parent then hum.Health = maxHP end
        end)
        carpetEngage()
        vZero(hrp)
        local _to = Vector3.new(petPos.X, -4, petPos.Z)
        -- ALWAYS pathfind into the base (route through the open doorway), never a straight
        -- line -- a straight shot clips the base wall/podiums.
        local route = computeRoute(hrp.Position, _to, nil)
        if not route or #route == 0 then route = { _to } end
        -- close target (under ~100 studs, e.g. the base next door) flies at a
        -- controlled 200 for precision; farther open bases follow the slider
        local _obLen = 0
        do
            local prev = hrp.Position
            for _, wp in ipairs(route) do
                _obLen = _obLen + (wp - prev).Magnitude
                prev = wp
            end
        end
        local _obSpeed = (_obLen < 100) and 200 or math.clamp(tonumber(_G.TPVelocity) or 400, 200, 500)
        velMoveThrough(hrp, route, _obSpeed, true, true)
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect()
        isTeleporting = false
        if _G.MeerkoTPCancel then _restoreAnims(); return end
        -- steal -- NO clone.
        pcall(function()
            local vim = Instance.new("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.C, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.C, false, game)
        end)
        _restoreAnims()
        return
    end

    local closestData, skyKey = findClosest(petPos, coordTable)
    if not closestData or not skyKey then isTeleporting = false; _restoreAnims(); return end

    local destPos = closestData.coord

    local maxHP = hum.MaxHealth
    hum.Health = maxHP
    local healConn = RunService.Heartbeat:Connect(function()
        if hum and hum.Parent then hum.Health = maxHP end
    end)

    local _carpet = carpetEngage()
    vZero(hrp)

    local facingDir = closestData.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)

    do
        local isUpper = (coordTable == UPPER)
        local idx = getClosestBaseIdx(petPos)
        local frontCoord, frontFace = buildFrontCandidate(idx, isUpper, hrp.Position.Z)
        local bestCoord, bestFace = frontCoord, frontFace
        local bestDist = (hrp.Position - frontCoord).Magnitude
        for _, d in ipairs(plotSides(coordTable, idx)) do
            local dd = (hrp.Position - d.coord).Magnitude
            if dd < bestDist then
                bestDist = dd
                bestCoord = d.coord
                bestFace = d.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
            end
        end
        destPos = bestCoord
        facingDir = bestFace
    end

    local _route = computeRoute(hrp.Position, destPos, facingDir)

    local ASCEND_STEP = 10
    local _stepped = {}
    do
        local prev = hrp.Position
        for _, wp in ipairs(_route) do
            local dy = wp.Y - prev.Y
            if dy > ASCEND_STEP * 1.5 then
                local n = math.ceil(dy / ASCEND_STEP)
                for s = 1, n - 1 do
                    local t = s / n
                    _stepped[#_stepped + 1] = Vector3.new(
                        prev.X + (wp.X - prev.X) * t,
                        prev.Y + dy * t,
                        prev.Z + (wp.Z - prev.Z) * t
                    )
                end
            end
            _stepped[#_stepped + 1] = wp
            prev = wp
        end
    end
    local _routeLen = 0
    do
        local prev = hrp.Position
        for _, wp in ipairs(_route) do
            _routeLen = _routeLen + (wp - prev).Magnitude
            prev = wp
        end
    end
    local _mainSpeed = (_routeLen < 100) and 200 or math.clamp(tonumber(_G.TPVelocity) or 400, 200, 500)
    velMoveThrough(hrp, _stepped, _mainSpeed, true, true)

    if _G.MeerkoTPCancel then
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect()
        isTeleporting = false
        _restoreAnims()
        return
    end

    do
        local _t0 = os.clock()
        while os.clock() - _t0 < 4 do
            if not hrp or not hrp.Parent then break end
            if LP:GetAttribute("Stealing") then break end
            if _G.MeerkoTPCancel then break end
            equipCarpet()
            local diff = destPos - hrp.Position
            local mag = diff.Magnitude
            if mag <= 3 then break end
            lvDrive(hrp, diff.Unit * math.min(400, mag * 8))
            hrp.AssemblyAngularVelocity = Vector3.zero
            RunService.Heartbeat:Wait()
        end
        lvStop(hrp)
    end
    if _G.MeerkoTPCancel then
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect()
        isTeleporting = false
        _restoreAnims()
        return
    end
    if hrp and hrp.Parent then
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + facingDir)
    end
    vZero(hrp)

    local syncFrames = 5
    local syncConn
    syncConn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
        syncFrames = syncFrames - 1
        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if syncFrames <= 0 then syncConn:Disconnect() end
    end)

    for _ = 1, 20 do
        task.wait(0.05)
        if hum.FloorMaterial ~= Enum.Material.Air then break end
        if _G.MeerkoTPCancel then break end
    end

    healConn:Disconnect()
    isTeleporting = false

    if _G.MeerkoTPCancel then _restoreAnims(); return end

    do
        local stable = 0
        for _ = 1, 50 do
            if _G.MeerkoTPCancel then break end
            local _hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not _hrp or not _hrp.Parent then break end
            local flat = (Vector3.new(_hrp.Position.X, 0, _hrp.Position.Z) - Vector3.new(destPos.X, 0, destPos.Z)).Magnitude
            if flat <= 3.5 and math.abs(_hrp.Position.Y - destPos.Y) <= 4 then
                stable = stable + 1
                if stable >= 4 then break end
            else
                stable = 0
                pcall(function() _hrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                _hrp.AssemblyLinearVelocity = Vector3.zero
                _hrp.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end
    if _G.MeerkoTPCancel then _restoreAnims(); return end
    local _ahrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local _clonePos = (_ahrp and _ahrp.Parent and _ahrp.Position) or destPos

    local _clonePlat = Instance.new("Part")
    _clonePlat.Name = "XenHubClonePlatform"
    _clonePlat.Size = Vector3.new(12, 1, 12)
    _clonePlat.Position = Vector3.new(_clonePos.X, _clonePos.Y - 3, _clonePos.Z)
    _clonePlat.Anchored = true
    _clonePlat.CanCollide = true
    _clonePlat.Transparency = 1
    _clonePlat.Material = Enum.Material.SmoothPlastic
    _clonePlat.Parent = workspace

    -- kill leftover flight momentum at the clone spot (no anchor -- the platform holds
    -- the footing).
    if _ahrp and _ahrp.Parent then
        _ahrp.AssemblyLinearVelocity = Vector3.zero
        _ahrp.AssemblyAngularVelocity = Vector3.zero
    end

    -- Record where we are before the clone so we can verify it actually swapped.
    local _preClonePos, _preCloneChar
    do
        _preCloneChar = LP.Character
        local _h = _preCloneChar and _preCloneChar:FindFirstChild("HumanoidRootPart")
        _preClonePos = _h and _h.Position or destPos
    end
    -- Catch the character rebuild explicitly (most reliable success signal).
    local _charAdded = false
    local _caConn = LP.CharacterAdded:Connect(function() _charAdded = true end)

    -- delay before switching to the cloner + firing the clone (lets us fully settle at
    -- the spot first). Tunable: set _G.TPCloneDelay (seconds); defaults to SKY_CLONE_WAIT.
    task.wait(tonumber(_G.TPCloneDelay) or tonumber(_G.LandingDelay) or SKY_CLONE_WAIT)

    local _cloneOk = doClone()
    -- remove the footing platform right after the clone fires
    if _clonePlat then pcall(function() _clonePlat:Destroy() end); _clonePlat = nil end
    do
        local _t0 = os.clock()
        repeat
            if _G.MeerkoTPCancel then break end
            if _charAdded then break end
            if LP.Character ~= _preCloneChar then break end
            local _h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if _h then
                local _dx = _h.Position.X - _preClonePos.X
                local _dz = _h.Position.Z - _preClonePos.Z
                if (_dx * _dx + _dz * _dz) > 4 then break end
            end
            RunService.Heartbeat:Wait()
        until os.clock() - _t0 > 3
    end
    if _caConn then _caConn:Disconnect() end

    if _G.MeerkoTPCancel then _restoreAnims(); return end

    goToBrainrot(petPos)
    pcall(function()
        local vim = Instance.new("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.C, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.C, false, game)
    end)
    _restoreAnims()
end

-- =====================================================================
-- Exposure + keybind trigger (T)
-- =====================================================================
_G.VanishStartSideTP = doVelocityTP

do
_G.TPVelocity = math.clamp(tonumber(_G.TPVelocity) or 400, 200, 500)
_G.LandingDelay = math.clamp(tonumber(_G.LandingDelay) or 0.4, 0.15, 0.75)
_G._stp_tpDelay = _G._stp_tpDelay or 0
local _SAVE_FILE = "chopper_HUB.json"
local _HttpService = game:GetService("HttpService")
local _TeleportService = game:GetService("TeleportService")
local function _stp_readRoot()
	if not (readfile and isfile) then return {} end
	local ok, root = pcall(function()
		if isfile(_SAVE_FILE) then
			return _HttpService:JSONDecode(readfile(_SAVE_FILE))
		end
	end)
	return (ok and type(root) == "table") and root or {}
end
local function _stp_loadSaved()
	local data = nil

	pcall(function()
		local td = _TeleportService:GetLocalPlayerTeleportData()
		if td and td.SideTP then data = td.SideTP end
	end)

	if not data then
		local root = _stp_readRoot()
		if type(root.sideTP) == "table" then data = root.sideTP end
	end
	return data or {}
end
local function _stp_saveCurrent()
	if not writefile then return end
	local payload = {
		tpDelay = _G._stp_tpDelay or 0,
		tpVelocity = _G.TPVelocity or 400,
		landingDelay = _G.LandingDelay or 0.4,
		tpKey = _G._stp_tpKeyName or "T",
		priorityList = _G.SHARED_PRIORITY_ITEMS,
		priorityListVersion = _G._priorityListVersion or 0,
		panelX = _G._stp_panelX,
		panelY = _G._stp_panelY,
	}
	local root = _stp_readRoot()
	root.sideTP = payload
	pcall(function() writefile(_SAVE_FILE, _HttpService:JSONEncode(root)) end)
end
_G._stp_saveCurrent = _stp_saveCurrent
do
	local s = _stp_loadSaved()
	if type(s.tpDelay) == "number" then _G._stp_tpDelay = s.tpDelay end
	if type(s.tpVelocity) == "number" then _G.TPVelocity = math.clamp(s.tpVelocity, 200, 500) end
	if type(s.landingDelay) == "number" then _G.LandingDelay = math.clamp(s.landingDelay, 0.15, 0.75) end
	if type(s.tpKey) == "string" then _G._stp_tpKeyName = s.tpKey end
	if type(s.priorityList) == "table" and #s.priorityList > 0 then
		_G.SHARED_PRIORITY_ITEMS = s.priorityList
	end
	if type(s.panelX) == "number" then _G._stp_panelX = s.panelX end
	if type(s.panelY) == "number" then _G._stp_panelY = s.panelY end

	local savedVersion = tonumber(s.priorityListVersion) or 0
	if savedVersion < 2 then
		_G.SHARED_PRIORITY_ITEMS = {
			"signore carapace","headless horseman","strawberry elephant","john pork","arcadragon",
			"elefanto frigo","meowl","skibidi toilet","griffin","love love bear",
			"antonio","dragon gingerini","dragon aquanini","pancake and syrup","fishino clownino",
			"la supreme combinasion","ginger gerat","rico dinero","kalika bros","tirilikalika tirilikalako",
			"digi narwhal","hydra bunny","bunny and eggy","dragon cannelloni","hydra dragon cannelloni",
			"globa steppa","dug dug dug","los hackers","lazy ducky","duggy bros",
			"pineaplino","ketupat bros","la casa boo","cerberus","rosey and teddy",
			"foxini lanternini","spooky and pumpky","john doe","fragola la la la","guest 666",
			"cooki and milki","quackini snackini","reinito sleighito","popcuru and fizzuru","gym bros",
			"capitano moby","burguro and fryuro","garama and madundung","fragrama and chocrama",
		}
		_G._priorityListVersion = 2
		if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end
	else
		_G._priorityListVersion = savedVersion
	end
end

if type(_G.SHARED_PRIORITY_ITEMS) ~= "table" or #_G.SHARED_PRIORITY_ITEMS == 0 then
	_G.SHARED_PRIORITY_ITEMS = {
		"headless horseman","strawberry elephant","signore carapace","meowl","skibidi toilet",
		"griffin","dragon gingerini","la supreme combinasion","dragon cannelloni",
		"hydra dragon cannelloni","love love bear","elefanto frigo","ginger gerat","antonio",
		"ketupat bros","tirilikalika tirilikalako","dug dug dug","fishino clownino",
		"foxini lanternini","cerberus","la casa boo","hydra bunny",
		"boppin bunny","capitano moby","fortunu and cashuru","celestial pegasus",
		"rosey and teddy","burguro and fryuro","spooky and pumpky","cooki and milki",
		"los amigos","popcuru and fizzuru","reinito sleighito","fragrama and chocrama",
		"festive 67","garama and madundung","ketchuru and musturu","la secret combinasion",
		"tralaledon","tictac sahur","ketupat kepat","tang tang keletang","orcaledon",
		"la ginger sekolah","los spaghettis","lavadorito spinito","swaggy bros",
		"la taco combinasion","los primos","chillin chili","tuff toucan","w or l",
		"chipso and queso",
		"money money bros","cash or card","la spooky grande","los bros","los candies",
		"los sekolahs","nacho spyder","la easter grande","quackini snackini","los chillis",
		"la anniversary grande","las sis","spaghetti tualetti","ventoliero pavonero","los tacoritas",
		"rosetti tualetti","eviledon","la lucky grande","la extinct grande","john doe",
		"la romantic grande","los hackers","los planitos","los puggies","la jolly grande",
		"gym bros","swag soda","sammyni fattini","los hotspotsitos","celularcini viciosini",
		"bunny and eggy","guest 666","digi narwhal","duggy bros","globa steppa",
		"jelly moby","kalika bros","arcadragon","pancake and syrup","rico dinero",
		"john pork"
	}
end

do
	local NEW_PRIORITY_ITEMS = {
		"money money bros","cash or card","la spooky grande","los bros","los candies",
		"los sekolahs","nacho spyder","la easter grande","quackini snackini","los chillis",
		"la anniversary grande","las sis","spaghetti tualetti","ventoliero pavonero","los tacoritas",
		"rosetti tualetti","eviledon","la lucky grande","la extinct grande","john doe",
		"la romantic grande","los hackers","los planitos","los puggies","la jolly grande",
		"gym bros","swag soda","sammyni fattini","los hotspotsitos","celularcini viciosini",
		"bunny and eggy","guest 666","digi narwhal","duggy bros","globa steppa",
		"jelly moby","kalika bros","arcadragon","pancake and syrup","rico dinero",
		"john pork"
	}
	local existing = {}
	for _, name in ipairs(_G.SHARED_PRIORITY_ITEMS) do
		existing[tostring(name):lower()] = true
	end
	local changed = false
	for _, name in ipairs(NEW_PRIORITY_ITEMS) do
		if not existing[name] then
			table.insert(_G.SHARED_PRIORITY_ITEMS, name)
			existing[name] = true
			changed = true
		end
	end
	if changed and _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end
end
end

task.spawn(function()
	local _UIS = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
	if not LocalPlayer then return end
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	local TP_KEY = Enum.KeyCode.T
	pcall(function()
		local n = _G._stp_tpKeyName
		if type(n) == "string" and Enum.KeyCode[n] then TP_KEY = Enum.KeyCode[n] end
	end)
	local C_BG = Color3.fromRGB(10, 14, 26)
	local C_SURFACE = Color3.fromRGB(18, 26, 46)
	local C_SELECTED = Color3.fromRGB(40, 56, 92)
	local C_BORDER = Color3.fromRGB(50, 66, 100)
	local C_TEXT = Color3.fromRGB(225, 232, 245)
	local C_TEXT_DIM = Color3.fromRGB(120, 135, 165)
	local C_GREEN = Color3.fromRGB(100, 170, 255)
	local C_ACCENT = Color3.fromRGB(50, 85, 140)

	local sg = Instance.new("ScreenGui")
	sg.Name = "XenSideTPPanel"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local _cloneref = cloneref or function(x) return x end
	pcall(function() sg.Parent = _cloneref(game:GetService("CoreGui")) end)
	if not sg.Parent then sg.Parent = PlayerGui end

	local mf = Instance.new("Frame")
	mf.Size = UDim2.new(0, 260, 0, 280)
	mf.Position = UDim2.new(0, _G._stp_panelX or 20, 0, _G._stp_panelY or 300)
	mf.BackgroundColor3 = C_BG
	mf.BackgroundTransparency = 0.02
	mf.BorderSizePixel = 0
	mf.Parent = sg
	Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 12)
	local mfStroke = Instance.new("UIStroke", mf)
	mfStroke.Color = C_BORDER; mfStroke.Thickness = 1; mfStroke.Transparency = 0.3

	local titleLabel = Instance.new("TextLabel", mf)
	titleLabel.Size = UDim2.new(1, 0, 0, 32)
	titleLabel.Position = UDim2.new(0, 0, 0, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Meerko TP"
	titleLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBlack

	local div = Instance.new("Frame", mf)
	div.Size = UDim2.new(1, -20, 0, 1)
	div.Position = UDim2.new(0, 10, 0, 42)
	div.BackgroundColor3 = C_BORDER
	div.BackgroundTransparency = 0.5
	div.BorderSizePixel = 0

	local dg, ds, sp = false, nil, nil
	titleLabel.Active = true
	titleLabel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dg = true
			ds = input.Position
			sp = UDim2.new(0, mf.AbsolutePosition.X, 0, mf.AbsolutePosition.Y)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dg = false
					_G._stp_panelX = mf.Position.X.Offset
					_G._stp_panelY = mf.Position.Y.Offset
					if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				end
			end)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if dg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - ds
			local newX = sp.X.Offset + d.X
			local newY = sp.Y.Offset + d.Y
			local viewportSize = workspace.CurrentCamera.ViewportSize
			newX = math.clamp(newX, 0, viewportSize.X - mf.AbsoluteSize.X)
			newY = math.clamp(newY, 0, viewportSize.Y - mf.AbsoluteSize.Y)
			mf.Position = UDim2.new(0, newX, 0, newY)
		end
	end)

	local buttonArea = Instance.new("Frame", mf)
	buttonArea.Size = UDim2.new(1, -24, 0, 246)
	buttonArea.Position = UDim2.new(0, 12, 0, 48)
	buttonArea.BackgroundTransparency = 1
	local btnLayout = Instance.new("UIListLayout", buttonArea)
	btnLayout.Padding = UDim.new(0, 10)
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local tpBtn = Instance.new("TextButton", buttonArea)
	tpBtn.Size = UDim2.new(1, 0, 0, 34)
	tpBtn.BackgroundColor3 = C_SURFACE
	tpBtn.Text = "Manual TP"
	tpBtn.TextColor3 = C_TEXT_DIM
	tpBtn.TextSize = 13
	tpBtn.Font = Enum.Font.GothamBold
	tpBtn.AutoButtonColor = false
	tpBtn.LayoutOrder = 0
	tpBtn.BorderSizePixel = 0
	Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 8)
	local tpStroke = Instance.new("UIStroke", tpBtn)
	tpStroke.Color = C_BORDER; tpStroke.Thickness = 1; tpStroke.Transparency = 0.5
	tpBtn.MouseEnter:Connect(function()
		TweenService:Create(tpBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(50,56,72), TextColor3 = C_TEXT}):Play()
	end)
	tpBtn.MouseLeave:Connect(function()
		TweenService:Create(tpBtn, TweenInfo.new(0.1), {BackgroundColor3 = C_SURFACE, TextColor3 = C_TEXT_DIM}):Play()
	end)
	tpBtn.MouseButton1Click:Connect(function()
		task.spawn(function() if _G.VanishStartSideTP then _G.VanishStartSideTP() end end)
	end)

	local tpBindBtn = Instance.new("TextButton", tpBtn)
	tpBindBtn.Size = UDim2.new(0, 30, 0, 16)
	tpBindBtn.Position = UDim2.new(1, -36, 0.5, -8)
	tpBindBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	tpBindBtn.Text = TP_KEY.Name
	tpBindBtn.TextColor3 = C_ACCENT
	tpBindBtn.TextSize = 9
	tpBindBtn.Font = Enum.Font.GothamBold
	tpBindBtn.AutoButtonColor = false
	tpBindBtn.BorderSizePixel = 0
	tpBindBtn.ZIndex = 2
	Instance.new("UICorner", tpBindBtn).CornerRadius = UDim.new(0, 4)
	local tpBindStroke = Instance.new("UIStroke", tpBindBtn)
	tpBindStroke.Color = C_BORDER; tpBindStroke.Thickness = 1; tpBindStroke.Transparency = 0.5

	local listeningForTPBind = false
	tpBindBtn.MouseButton1Click:Connect(function()
		if listeningForTPBind then return end
		listeningForTPBind = true
		tpBindBtn.Text = "..."
		tpBindBtn.TextColor3 = C_TEXT_DIM
		local conn
		conn = _UIS.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				local name = input.KeyCode.Name
				if name and name ~= "Unknown" then
					TP_KEY = input.KeyCode
					tpBindBtn.Text = name
					tpBindBtn.TextColor3 = C_ACCENT
					_G._stp_tpKeyName = name
					if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				end
			end
			listeningForTPBind = false
			if conn then conn:Disconnect() end
		end)
		task.delay(5, function()
			if listeningForTPBind then
				listeningForTPBind = false
				if conn then conn:Disconnect() end
				tpBindBtn.Text = TP_KEY.Name
				tpBindBtn.TextColor3 = C_ACCENT
			end
		end)
	end)

	_G._stp_tpDelay = _G._stp_tpDelay or 0
	local _tpDelay = _G._stp_tpDelay
	local DELAY_MIN = 0
	local DELAY_MAX = 0.9
	local delayFrame = Instance.new("Frame", buttonArea)
	delayFrame.Size = UDim2.new(1, 0, 0, 38)
	delayFrame.BackgroundTransparency = 1
	delayFrame.LayoutOrder = 3

	local delayLabel = Instance.new("TextLabel", delayFrame)
	delayLabel.Size = UDim2.new(1, -60, 0, 16)
	delayLabel.Position = UDim2.new(0, 0, 0, 0)
	delayLabel.BackgroundTransparency = 1
	delayLabel.Text = "Delay Before TP (ms):"
	delayLabel.TextColor3 = C_TEXT_DIM
	delayLabel.TextSize = 12
	delayLabel.Font = Enum.Font.GothamBold
	delayLabel.TextXAlignment = Enum.TextXAlignment.Left

	local delayValueLabel = Instance.new("TextLabel", delayFrame)
	delayValueLabel.Size = UDim2.new(0, 60, 0, 16)
	delayValueLabel.Position = UDim2.new(1, -60, 0, 0)
	delayValueLabel.BackgroundTransparency = 1
	delayValueLabel.Text = "0ms"
	delayValueLabel.TextColor3 = C_TEXT
	delayValueLabel.TextSize = 12
	delayValueLabel.Font = Enum.Font.GothamBold
	delayValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local delayTrack = Instance.new("Frame", delayFrame)
	delayTrack.Size = UDim2.new(1, 0, 0, 8)
	delayTrack.Position = UDim2.new(0, 0, 0, 24)
	delayTrack.BackgroundColor3 = C_SURFACE
	delayTrack.BorderSizePixel = 0
	Instance.new("UICorner", delayTrack).CornerRadius = UDim.new(1, 0)

	local delayFill = Instance.new("Frame", delayTrack)
	delayFill.Size = UDim2.new(0, 0, 1, 0)
	delayFill.BackgroundColor3 = C_ACCENT
	delayFill.BorderSizePixel = 0
	Instance.new("UICorner", delayFill).CornerRadius = UDim.new(1, 0)

	local delayKnob = Instance.new("Frame", delayTrack)
	delayKnob.Size = UDim2.new(0, 14, 0, 14)
	delayKnob.Position = UDim2.new(0, -7, 0.5, -7)
	delayKnob.BackgroundColor3 = C_TEXT
	delayKnob.BorderSizePixel = 0
	delayKnob.ZIndex = 3
	Instance.new("UICorner", delayKnob).CornerRadius = UDim.new(1, 0)

	local function updateDelayVisual()
		local frac = (_tpDelay - DELAY_MIN) / (DELAY_MAX - DELAY_MIN)
		delayFill.Size = UDim2.new(frac, 0, 1, 0)
		delayKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		delayValueLabel.Text = string.format("%dms", math.floor(_tpDelay * 1000 + 0.5))
	end
	updateDelayVisual()

	local delayDragging = false
	local delaySliderBtn = Instance.new("TextButton", delayTrack)
	delaySliderBtn.Size = UDim2.new(1, 0, 1, 10)
	delaySliderBtn.Position = UDim2.new(0, 0, 0, -5)
	delaySliderBtn.BackgroundTransparency = 1
	delaySliderBtn.Text = ""
	delaySliderBtn.ZIndex = 2
	local function handleDelayInput(xPos)
		local tx = delayTrack.AbsolutePosition.X
		local tw = delayTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)

		local raw = DELAY_MIN + frac * (DELAY_MAX - DELAY_MIN)
		_tpDelay = math.floor(raw * 100 + 0.5) / 100
		_tpDelay = math.clamp(_tpDelay, DELAY_MIN, DELAY_MAX)
		_G._stp_tpDelay = _tpDelay
		updateDelayVisual()
	end
	delaySliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			delayDragging = true
			handleDelayInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if delayDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleDelayInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if delayDragging then
				delayDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	_G.LandingDelay = math.clamp(tonumber(_G.LandingDelay) or 0.4, 0.15, 0.75)
	local _landingDelay = _G.LandingDelay
	local LD_MIN = 0.15
	local LD_MAX = 0.75
	local ldFrame = Instance.new("Frame", buttonArea)
	ldFrame.Size = UDim2.new(1, 0, 0, 38)
	ldFrame.BackgroundTransparency = 1
	ldFrame.LayoutOrder = 4

	local ldLabel = Instance.new("TextLabel", ldFrame)
	ldLabel.Size = UDim2.new(1, -60, 0, 16)
	ldLabel.Position = UDim2.new(0, 0, 0, 0)
	ldLabel.BackgroundTransparency = 1
	ldLabel.Text = "Landing Delay Before Clone:"
	ldLabel.TextColor3 = C_TEXT_DIM
	ldLabel.TextSize = 12
	ldLabel.Font = Enum.Font.GothamBold
	ldLabel.TextXAlignment = Enum.TextXAlignment.Left

	local ldValueLabel = Instance.new("TextLabel", ldFrame)
	ldValueLabel.Size = UDim2.new(0, 60, 0, 16)
	ldValueLabel.Position = UDim2.new(1, -60, 0, 0)
	ldValueLabel.BackgroundTransparency = 1
	ldValueLabel.Text = string.format("%.2fs", _landingDelay)
	ldValueLabel.TextColor3 = C_TEXT
	ldValueLabel.TextSize = 12
	ldValueLabel.Font = Enum.Font.GothamBold
	ldValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local ldTrack = Instance.new("Frame", ldFrame)
	ldTrack.Size = UDim2.new(1, 0, 0, 8)
	ldTrack.Position = UDim2.new(0, 0, 0, 24)
	ldTrack.BackgroundColor3 = C_SURFACE
	ldTrack.BorderSizePixel = 0
	Instance.new("UICorner", ldTrack).CornerRadius = UDim.new(1, 0)

	local ldFill = Instance.new("Frame", ldTrack)
	ldFill.Size = UDim2.new(0, 0, 1, 0)
	ldFill.BackgroundColor3 = C_ACCENT
	ldFill.BorderSizePixel = 0
	Instance.new("UICorner", ldFill).CornerRadius = UDim.new(1, 0)

	local ldKnob = Instance.new("Frame", ldTrack)
	ldKnob.Size = UDim2.new(0, 14, 0, 14)
	ldKnob.Position = UDim2.new(0, -7, 0.5, -7)
	ldKnob.BackgroundColor3 = C_TEXT
	ldKnob.BorderSizePixel = 0
	ldKnob.ZIndex = 3
	Instance.new("UICorner", ldKnob).CornerRadius = UDim.new(1, 0)

	local function updateLdVisual()
		local frac = (_landingDelay - LD_MIN) / (LD_MAX - LD_MIN)
		ldFill.Size = UDim2.new(frac, 0, 1, 0)
		ldKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		ldValueLabel.Text = string.format("%.2fs", _landingDelay)
	end
	updateLdVisual()

	local ldDragging = false
	local ldSliderBtn = Instance.new("TextButton", ldTrack)
	ldSliderBtn.Size = UDim2.new(1, 0, 1, 10)
	ldSliderBtn.Position = UDim2.new(0, 0, 0, -5)
	ldSliderBtn.BackgroundTransparency = 1
	ldSliderBtn.Text = ""
	ldSliderBtn.ZIndex = 2
	local function handleLdInput(xPos)
		local tx = ldTrack.AbsolutePosition.X
		local tw = ldTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)

		local raw = LD_MIN + frac * (LD_MAX - LD_MIN)
		_landingDelay = math.floor(raw * 100 + 0.5) / 100
		_landingDelay = math.clamp(_landingDelay, LD_MIN, LD_MAX)
		_G.LandingDelay = _landingDelay
		updateLdVisual()
	end
	ldSliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ldDragging = true
			handleLdInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if ldDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleLdInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if ldDragging then
				ldDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	local VEL_MIN = 200
	local VEL_MAX = 500
	_G.TPVelocity = math.clamp(tonumber(_G.TPVelocity) or 400, VEL_MIN, VEL_MAX)
	local velFrame = Instance.new("Frame", buttonArea)
	velFrame.Size = UDim2.new(1, 0, 0, 38)
	velFrame.BackgroundTransparency = 1
	velFrame.LayoutOrder = 5

	local velLabel = Instance.new("TextLabel", velFrame)
	velLabel.Size = UDim2.new(1, -70, 0, 16)
	velLabel.Position = UDim2.new(0, 0, 0, 0)
	velLabel.BackgroundTransparency = 1
	velLabel.Text = "TP Velocity:"
	velLabel.TextColor3 = C_TEXT_DIM
	velLabel.TextSize = 12
	velLabel.Font = Enum.Font.GothamBold
	velLabel.TextXAlignment = Enum.TextXAlignment.Left

	local velValueLabel = Instance.new("TextLabel", velFrame)
	velValueLabel.Size = UDim2.new(0, 70, 0, 16)
	velValueLabel.Position = UDim2.new(1, -70, 0, 0)
	velValueLabel.BackgroundTransparency = 1
	velValueLabel.Text = tostring(_G.TPVelocity)
	velValueLabel.TextColor3 = C_TEXT
	velValueLabel.TextSize = 12
	velValueLabel.Font = Enum.Font.GothamBold
	velValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local velTrack = Instance.new("Frame", velFrame)
	velTrack.Size = UDim2.new(1, 0, 0, 8)
	velTrack.Position = UDim2.new(0, 0, 0, 24)
	velTrack.BackgroundColor3 = C_SURFACE
	velTrack.BorderSizePixel = 0
	Instance.new("UICorner", velTrack).CornerRadius = UDim.new(1, 0)

	local velFill = Instance.new("Frame", velTrack)
	velFill.Size = UDim2.new(0, 0, 1, 0)
	velFill.BackgroundColor3 = C_ACCENT
	velFill.BorderSizePixel = 0
	Instance.new("UICorner", velFill).CornerRadius = UDim.new(1, 0)

	local velKnob = Instance.new("Frame", velTrack)
	velKnob.Size = UDim2.new(0, 14, 0, 14)
	velKnob.Position = UDim2.new(0, -7, 0.5, -7)
	velKnob.BackgroundColor3 = C_TEXT
	velKnob.BorderSizePixel = 0
	velKnob.ZIndex = 3
	Instance.new("UICorner", velKnob).CornerRadius = UDim.new(1, 0)

	local function updateVelVisual()
		local frac = (_G.TPVelocity - VEL_MIN) / (VEL_MAX - VEL_MIN)
		velFill.Size = UDim2.new(frac, 0, 1, 0)
		velKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		velValueLabel.Text = tostring(_G.TPVelocity)
	end
	updateVelVisual()

	local velDragging = false
	local velSliderBtn = Instance.new("TextButton", velTrack)
	velSliderBtn.Size = UDim2.new(1, 0, 1, 10)
	velSliderBtn.Position = UDim2.new(0, 0, 0, -5)
	velSliderBtn.BackgroundTransparency = 1
	velSliderBtn.Text = ""
	velSliderBtn.ZIndex = 2
	local function handleVelInput(xPos)
		local tx = velTrack.AbsolutePosition.X
		local tw = velTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)
		local raw = VEL_MIN + frac * (VEL_MAX - VEL_MIN)

		_G.TPVelocity = math.floor(raw / 10 + 0.5) * 10
		_G.TPVelocity = math.clamp(_G.TPVelocity, VEL_MIN, VEL_MAX)
		updateVelVisual()
	end
	velSliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			velDragging = true
			handleVelInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if velDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleVelInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if velDragging then
				velDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	local customizeBtn = Instance.new("TextButton", buttonArea)
	customizeBtn.Size = UDim2.new(1, 0, 0, 34)
	customizeBtn.BackgroundColor3 = C_ACCENT
	customizeBtn.Text = "Edit Priority"
	customizeBtn.TextColor3 = C_TEXT
	customizeBtn.TextSize = 13
	customizeBtn.Font = Enum.Font.GothamBold
	customizeBtn.AutoButtonColor = false
	customizeBtn.LayoutOrder = 1
	customizeBtn.BorderSizePixel = 0
	Instance.new("UICorner", customizeBtn).CornerRadius = UDim.new(0, 8)
	customizeBtn.MouseEnter:Connect(function()
		TweenService:Create(customizeBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(100, 140, 190)}):Play()
	end)
	customizeBtn.MouseLeave:Connect(function()
		TweenService:Create(customizeBtn, TweenInfo.new(0.1), {BackgroundColor3 = C_ACCENT}):Play()
	end)

	local priorityPopup = Instance.new("Frame", sg)
	priorityPopup.Size = UDim2.new(0, 400, 0, 560)
	priorityPopup.Position = UDim2.new(0.5, -200, 0.5, -280)
	priorityPopup.BackgroundColor3 = C_BG
	priorityPopup.BackgroundTransparency = 0.02
	priorityPopup.BorderSizePixel = 0
	priorityPopup.Visible = false
	priorityPopup.ZIndex = 50
	Instance.new("UICorner", priorityPopup).CornerRadius = UDim.new(0, 12)
	local popStroke = Instance.new("UIStroke", priorityPopup)
	popStroke.Color = Color3.fromRGB(255, 255, 255); popStroke.Thickness = 1; popStroke.Transparency = 0.96

	local popTitle = Instance.new("TextLabel", priorityPopup)
	popTitle.Size = UDim2.new(1, -40, 0, 40)
	popTitle.Position = UDim2.new(0, 10, 0, 2)
	popTitle.BackgroundTransparency = 1
	popTitle.Text = "Priority List"
	popTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	popTitle.TextSize = 18
	popTitle.Font = Enum.Font.BuilderSans
	popTitle.TextXAlignment = Enum.TextXAlignment.Center
	popTitle.ZIndex = 51

	local popClose = Instance.new("TextButton", priorityPopup)
	popClose.Size = UDim2.new(0, 28, 0, 28)
	popClose.Position = UDim2.new(1, -34, 0, 8)
	popClose.BackgroundTransparency = 1
	popClose.Text = "x"
	popClose.TextColor3 = C_TEXT_DIM
	popClose.TextSize = 16
	popClose.Font = Enum.Font.BuilderSans
	popClose.AutoButtonColor = false
	popClose.ZIndex = 52
	popClose.MouseEnter:Connect(function() popClose.TextColor3 = C_TEXT end)
	popClose.MouseLeave:Connect(function() popClose.TextColor3 = C_TEXT_DIM end)

	local popDiv = Instance.new("Frame", priorityPopup)
	popDiv.Size = UDim2.new(1, -20, 0, 1)
	popDiv.Position = UDim2.new(0, 10, 0, 42)
	popDiv.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	popDiv.BackgroundTransparency = 0.92
	popDiv.BorderSizePixel = 0
	popDiv.ZIndex = 51

	local searchRow = Instance.new("Frame", priorityPopup)
	searchRow.Size = UDim2.new(1, -20, 0, 32)
	searchRow.Position = UDim2.new(0, 10, 0, 48)
	searchRow.BackgroundTransparency = 1
	searchRow.ZIndex = 51

	local searchInput = Instance.new("TextBox", searchRow)
	searchInput.Size = UDim2.new(1, 0, 1, 0)
	searchInput.BackgroundColor3 = C_SURFACE
	searchInput.Text = ""
	searchInput.PlaceholderText = "Search..."
	searchInput.PlaceholderColor3 = C_TEXT_DIM
	searchInput.TextColor3 = C_TEXT
	searchInput.TextSize = 12
	searchInput.Font = Enum.Font.BuilderSans
	searchInput.ClearTextOnFocus = false
	searchInput.TextXAlignment = Enum.TextXAlignment.Left
	searchInput.BorderSizePixel = 0
	searchInput.ZIndex = 52
	Instance.new("UICorner", searchInput).CornerRadius = UDim.new(0, 6)
	Instance.new("UIPadding", searchInput).PaddingLeft = UDim.new(0, 8)
	local searchStroke = Instance.new("UIStroke", searchInput)
	searchStroke.Color = Color3.fromRGB(255, 255, 255); searchStroke.Thickness = 1; searchStroke.Transparency = 0.96

	local popScroll = Instance.new("ScrollingFrame", priorityPopup)
	popScroll.Size = UDim2.new(1, -20, 1, -130)
	popScroll.Position = UDim2.new(0, 10, 0, 86)
	popScroll.BackgroundTransparency = 1
	popScroll.ScrollBarThickness = 4
	popScroll.ScrollBarImageColor3 = C_ACCENT
	popScroll.ScrollBarImageTransparency = 0.4
	popScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	popScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	popScroll.BorderSizePixel = 0
	popScroll.ZIndex = 51
	local popLayout = Instance.new("UIListLayout", popScroll)
	popLayout.Padding = UDim.new(0, 3)
	popLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local addDiv = Instance.new("Frame", priorityPopup)
	addDiv.Size = UDim2.new(1, -20, 0, 1)
	addDiv.Position = UDim2.new(0, 10, 1, -40)
	addDiv.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	addDiv.BackgroundTransparency = 0.92
	addDiv.BorderSizePixel = 0
	addDiv.ZIndex = 51

	local addRow = Instance.new("Frame", priorityPopup)
	addRow.Size = UDim2.new(1, -20, 0, 32)
	addRow.Position = UDim2.new(0, 10, 1, -36)
	addRow.BackgroundTransparency = 1
	addRow.ZIndex = 51

	local addInput = Instance.new("TextBox", addRow)
	addInput.Size = UDim2.new(1, -58, 1, 0)
	addInput.BackgroundColor3 = C_SURFACE
	addInput.Text = ""
	addInput.PlaceholderText = "Add brainrot name..."
	addInput.PlaceholderColor3 = C_TEXT_DIM
	addInput.TextColor3 = C_TEXT
	addInput.TextSize = 12
	addInput.Font = Enum.Font.BuilderSans
	addInput.ClearTextOnFocus = false
	addInput.TextXAlignment = Enum.TextXAlignment.Left
	addInput.BorderSizePixel = 0
	addInput.ZIndex = 52
	Instance.new("UICorner", addInput).CornerRadius = UDim.new(0, 6)
	Instance.new("UIPadding", addInput).PaddingLeft = UDim.new(0, 8)
	local addInputStroke = Instance.new("UIStroke", addInput)
	addInputStroke.Color = Color3.fromRGB(255, 255, 255); addInputStroke.Thickness = 1; addInputStroke.Transparency = 0.96

	local addBtn = Instance.new("TextButton", addRow)
	addBtn.Size = UDim2.new(0, 52, 1, 0)
	addBtn.Position = UDim2.new(1, -52, 0, 0)
	addBtn.BackgroundColor3 = C_ACCENT
	addBtn.Text = "Add"
	addBtn.TextColor3 = C_TEXT
	addBtn.TextSize = 12
	addBtn.Font = Enum.Font.BuilderSans
	addBtn.AutoButtonColor = false
	addBtn.BorderSizePixel = 0
	addBtn.ZIndex = 52
	Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 6)

	local function getPriorityList()
		if type(_G.SHARED_PRIORITY_ITEMS) ~= "table" then _G.SHARED_PRIORITY_ITEMS = {} end
		return _G.SHARED_PRIORITY_ITEMS
	end

	-- ----- Drag-to-reorder for the priority list -----
	local ROW_H, ROW_GAP = 30, 3
	local ROW_STEP = ROW_H + ROW_GAP
	local _dragState = nil -- { idx = <index in list>, row = <Frame>, grabOffsetY = <number> }
	local GuiService = game:GetService("GuiService")
	local function getMouseYInGuiSpace()
		return _UIS:GetMouseLocation().Y - GuiService:GetGuiInset().Y
	end

	-- Thin highlight bar showing where the dragged row will land.
	local dropIndicator = Instance.new("Frame", priorityPopup)
	dropIndicator.Name = "PriorityDropIndicator"
	dropIndicator.BackgroundColor3 = Color3.fromRGB(120, 180, 255)
	dropIndicator.BorderSizePixel = 0
	dropIndicator.ZIndex = 59
	dropIndicator.Visible = false
	Instance.new("UICorner", dropIndicator).CornerRadius = UDim.new(1, 0)

	local rebuildPriorityList
	rebuildPriorityList = function()
		_dragState = nil
		dropIndicator.Visible = false
		local leftover = priorityPopup:FindFirstChild("DraggingPriorityRow")
		if leftover then leftover:Destroy() end

		for _, child in ipairs(popScroll:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		local query = (searchInput.Text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		local firstMatchRow = nil
		local list = getPriorityList()
		for idx, name in ipairs(list) do
			local displayName = name:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b end)
			local isMatch = query ~= "" and name:find(query, 1, true)
			local row = Instance.new("Frame", popScroll)
			row.Size = UDim2.new(1, 0, 0, 30)
			row.BackgroundColor3 = isMatch and C_SELECTED or C_SURFACE
			row.BackgroundTransparency = 0.12
			if isMatch and not firstMatchRow then firstMatchRow = row end
			row.LayoutOrder = idx
			row.ZIndex = 52
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
			local _rowStroke = Instance.new("UIStroke", row)
			_rowStroke.Color = Color3.fromRGB(255, 255, 255); _rowStroke.Thickness = 1; _rowStroke.Transparency = 0.96

			local numLabel = Instance.new("TextLabel", row)
			numLabel.Size = UDim2.new(0, 26, 1, 0)
			numLabel.Position = UDim2.new(0, 6, 0, 0)
			numLabel.BackgroundTransparency = 1
			numLabel.Text = tostring(idx)
			numLabel.TextColor3 = C_TEXT_DIM
			numLabel.TextSize = 11
			numLabel.Font = Enum.Font.BuilderSans
			numLabel.ZIndex = 53

			local nameLabel = Instance.new("TextLabel", row)
			nameLabel.Size = UDim2.new(1, -58, 1, 0)
			nameLabel.Position = UDim2.new(0, 32, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = displayName
			nameLabel.TextColor3 = isMatch and C_GREEN or C_TEXT
			nameLabel.TextSize = 12
			nameLabel.Font = Enum.Font.BuilderSans
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 53

			local dragBtn = Instance.new("TextButton", row)
			dragBtn.Size = UDim2.new(0, 20, 0, 20)
			dragBtn.Position = UDim2.new(1, -46, 0.5, -10)
			dragBtn.BackgroundTransparency = 1
			dragBtn.Text = "☰"
			dragBtn.TextColor3 = C_TEXT_DIM
			dragBtn.TextSize = 14
			dragBtn.Font = Enum.Font.BuilderSans
			dragBtn.AutoButtonColor = false
			dragBtn.ZIndex = 54
			dragBtn.Active = true
			dragBtn.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if _dragState then return end
				local relX = popScroll.AbsolutePosition.X - priorityPopup.AbsolutePosition.X
				local relY = (row.AbsolutePosition.Y - priorityPopup.AbsolutePosition.Y)
				_dragState = {
					idx = idx,
					row = row,
					grabOffsetY = getMouseYInGuiSpace() - row.AbsolutePosition.Y,
				}
				row.Name = "DraggingPriorityRow"
				row.ZIndex = 60
				row.BackgroundColor3 = C_SELECTED
				row.BackgroundTransparency = 0
				row.Size = UDim2.new(0, popScroll.AbsoluteSize.X, 0, ROW_H)
				row.Position = UDim2.new(0, relX, 0, relY)
				row.Parent = priorityPopup
			end)

			local delBtn = Instance.new("TextButton", row)
			delBtn.Size = UDim2.new(0, 20, 0, 20)
			delBtn.Position = UDim2.new(1, -22, 0.5, -10)
			delBtn.BackgroundTransparency = 1
			delBtn.Text = "x"
			delBtn.TextColor3 = Color3.fromRGB(224, 122, 130)
			delBtn.TextSize = 12
			delBtn.Font = Enum.Font.BuilderSans
			delBtn.AutoButtonColor = false
			delBtn.ZIndex = 54
			delBtn.MouseButton1Click:Connect(function()
				table.remove(list, idx)
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				rebuildPriorityList()
			end)
		end
		if firstMatchRow then
			task.defer(function()
				local yPos = firstMatchRow.AbsolutePosition.Y - popScroll.AbsolutePosition.Y + popScroll.CanvasPosition.Y
				popScroll.CanvasPosition = Vector2.new(0, math.max(0, yPos - 10))
			end)
		end
	end

	local function computeTargetIdx(row, listLen)
		local relY = (row.AbsolutePosition.Y - popScroll.AbsolutePosition.Y) + popScroll.CanvasPosition.Y
		return math.clamp(math.floor(relY / ROW_STEP + 0.5) + 1, 1, listLen)
	end

	-- Follow the mouse while a row is being dragged, and show a drop indicator
	-- bar at the slot it would land in if released right now.
	RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
		if not _dragState then return end
		local row = _dragState.row
		if not row or not row.Parent then _dragState = nil; dropIndicator.Visible = false; return end
		local mouseY = getMouseYInGuiSpace()
		local minY = popScroll.AbsolutePosition.Y
		local maxY = popScroll.AbsolutePosition.Y + popScroll.AbsoluteSize.Y - row.AbsoluteSize.Y
		local newY = math.clamp(mouseY - _dragState.grabOffsetY, minY, math.max(minY, maxY))
		local relX = popScroll.AbsolutePosition.X - priorityPopup.AbsolutePosition.X
		local relY = newY - priorityPopup.AbsolutePosition.Y
		row.Position = UDim2.new(0, relX, 0, relY)

		local list = getPriorityList()
		local targetIdx = computeTargetIdx(row, #list)
		local indicatorScreenY = popScroll.AbsolutePosition.Y + (targetIdx - 1) * ROW_STEP - popScroll.CanvasPosition.Y
		if indicatorScreenY >= popScroll.AbsolutePosition.Y - 2
			and indicatorScreenY <= popScroll.AbsolutePosition.Y + popScroll.AbsoluteSize.Y + 2 then
			dropIndicator.Size = UDim2.new(0, popScroll.AbsoluteSize.X, 0, 3)
			dropIndicator.Position = UDim2.new(0, relX, 0, (indicatorScreenY - priorityPopup.AbsolutePosition.Y) - 1)
			dropIndicator.Visible = true
		else
			dropIndicator.Visible = false
		end
	end))

	-- Drop the dragged row: convert its Y position back into a list index and reorder.
	_UIS.InputEnded:Connect(function(input)
		if not _dragState then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local row, idx = _dragState.row, _dragState.idx
		_dragState = nil
		dropIndicator.Visible = false
		local list = getPriorityList()
		local targetIdx = computeTargetIdx(row, #list)
		row:Destroy()
		if targetIdx ~= idx and list[idx] then
			local name = table.remove(list, idx)
			table.insert(list, targetIdx, name)
			if _G._stp_saveCurrent then _G._stp_saveCurrent() end
		end
		rebuildPriorityList()
	end)

	addBtn.MouseButton1Click:Connect(function()
		local name = addInput.Text:match("^%s*(.-)%s*$"):lower()
		if name == "" then return end
		local list = getPriorityList()
		for _, existing in ipairs(list) do
			if existing == name then addInput.Text = ""; return end
		end
		table.insert(list, name)
		addInput.Text = ""
		if _G._stp_saveCurrent then _G._stp_saveCurrent() end
		rebuildPriorityList()
	end)

	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildPriorityList()
	end)

	local popupOpen = false
	customizeBtn.MouseButton1Click:Connect(function()
		popupOpen = not popupOpen
		if popupOpen then
			rebuildPriorityList()
			priorityPopup.Visible = true
			local px = mf.AbsolutePosition.X + mf.AbsoluteSize.X + 8
			local py = mf.AbsolutePosition.Y
			local cam = workspace.CurrentCamera
			if cam then
				local vp = cam.ViewportSize
				if px + 400 > vp.X - 10 then px = mf.AbsolutePosition.X - 408 end
				py = math.clamp(py, 10, vp.Y - 570)
			end
			priorityPopup.Position = UDim2.new(0, px, 0, py)
		else
			priorityPopup.Visible = false
		end
	end)

	-- Opened from the "Auto Teleport" module in the Features panel.
	_G._stp_openPriority = function()
		popupOpen = true
		rebuildPriorityList()
		priorityPopup.Visible = true
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		priorityPopup.Position = UDim2.new(0, math.floor(vp.X / 2 - 200), 0, math.floor(vp.Y / 2 - 280))
	end

	-- TP controls now live in the Features panel; hide this standalone panel
	-- (its keybind + priority popup stay active).
	mf.Visible = false

	popClose.MouseButton1Click:Connect(function()
		popupOpen = false
		priorityPopup.Visible = false
	end)

	priorityPopup.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if searchInput:IsFocused() then searchInput:ReleaseFocus() end
			if addInput:IsFocused() then addInput:ReleaseFocus() end
		end
	end)

	local popDg, popDs, popSp = false, nil, nil
	popTitle.Active = true
	popTitle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			popDg = true
			popDs = input.Position
			popSp = UDim2.new(0, priorityPopup.AbsolutePosition.X, 0, priorityPopup.AbsolutePosition.Y)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then popDg = false end
			end)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if popDg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - popDs
			local newX = popSp.X.Offset + d.X
			local newY = popSp.Y.Offset + d.Y
			local viewportSize = workspace.CurrentCamera.ViewportSize
			newX = math.clamp(newX, 0, viewportSize.X - priorityPopup.AbsoluteSize.X)
			newY = math.clamp(newY, 0, viewportSize.Y - priorityPopup.AbsoluteSize.Y)
			priorityPopup.Position = UDim2.new(0, newX, 0, newY)
		end
	end)

	_UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if _UIS:GetFocusedTextBox() then return end
		local name = _G._stp_tpKeyName
		if type(name) ~= "string" then name = "T" end
		if name == "" then return end
		if Enum.KeyCode[name] and input.KeyCode == Enum.KeyCode[name] then
			task.spawn(function() if _G.VanishStartSideTP then _G.VanishStartSideTP() end end)
		end
	end)
end)

_G.VanishFireGrapple = fireGrapple

task.spawn(function() pcall(loadModules) pcall(loadNet) end)

-- Auto-teleport on execute: wait for the character + a scannable brainrot,
-- then run the TP once.
task.spawn(function()
    local char = LP.Character or LP.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 10)
    char:WaitForChild("Humanoid", 10)
    pcall(loadModules); pcall(loadNet)
    local _t0 = os.clock()
    repeat
        local ok, pets = pcall(scanAllPets)
        if ok and pets and #pets > 0 then break end
        task.wait(0.3)
    until os.clock() - _t0 > 12
    -- delay before TP (UI slider) -- applies ONLY to this auto-TP-on-join, not the
    -- manual keypress.
    do
        local _d = tonumber(_G._stp_tpDelay) or tonumber(_G.TPDelay) or 0
        if _d > 0 then task.wait(_d) end
    end
    -- only auto-TP on load when the Auto Teleport feature is enabled
    if _G.MeerkoConfig and _G.MeerkoConfig.AutoTeleport then
        -- wait until the game is running at >= 60 FPS before TPing, so it
        -- doesn't fire mid-load and lag out. Times out after ~30s as a fallback.
        do
            local RunSvc = game:GetService("RunService")
            local fpsDeadline = os.clock() + 30
            while os.clock() < fpsDeadline do
                local frames, t0 = 0, os.clock()
                while frames < 10 do RunSvc.RenderStepped:Wait(); frames = frames + 1 end
                local dt = os.clock() - t0
                if dt > 0 and (frames / dt) >= 60 then break end
            end
        end
        pcall(doVelocityTP)
    end
end)

-- Auto-TP au join : se lance une seule fois quand le character atterrit sur la zone de collecte de la base.
local _autoTPOnJoinFired = false
local function _autoTPOnJoinForChar(char)
    if _autoTPOnJoinFired then return end
    if not (_G.MeerkoConfig and _G.MeerkoConfig.AutoTPOnJoin) then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    -- Attendre que le humanoid atterrisse (state = Landed ou Running/Swimming)
    local landed = false
    local conn
    conn = hum.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Landed
        or new == Enum.HumanoidStateType.Running
        or new == Enum.HumanoidStateType.RunningNoPhysics then
            landed = true
            if conn then conn:Disconnect(); conn = nil end
        end
    end)
    -- Timeout 10s au cas où StateChanged ne fire pas
    local t0 = os.clock()
    while not landed and os.clock() - t0 < 10 do
        task.wait(0.05)
    end
    if conn then conn:Disconnect(); conn = nil end

    if _autoTPOnJoinFired then return end
    _autoTPOnJoinFired = true
    pcall(loadModules); pcall(loadNet)
    pcall(doVelocityTP)
end

task.spawn(function()
    local char = LP.Character or LP.CharacterAdded:Wait()
    task.spawn(_autoTPOnJoinForChar, char)
end)

-- Manual trigger is handled by the Side-TP UI panel's rebindable keybind
-- (default T), so the old hardcoded handler is removed to avoid a conflict.


do
    local MK_Players   = game:GetService("Players")
    local MK_Workspace = workspace
    local MK_RS        = game:GetService("ReplicatedStorage")
    local MK_Run       = game:GetService("RunService")
    local MK_LP        = MK_Players.LocalPlayer
    local MK_PlayerGui = MK_LP:WaitForChild("PlayerGui")
    local MK_Http      = game:GetService("HttpService")

    _G.VanishStartupReady = true

    -- ===== Config + persistence ======================================
    local Config = _G.MeerkoConfig or {
        BrainrotESP     = false,
        SubspaceMineESP = false,
        LineToBase      = false,
        LineToBrainrot  = false,
        InvisOnSteal    = false,
        InvisRotation   = 225,
        InvisDepth      = 7,
        InvisWalkSpeed  = 16,
        AutoBuyCarpet   = true,
        AutoBuyMinGen   = 1000000,
        AutoKickOnSteal = false,
        AutoTPOnJoin    = false,
        GameStretcher   = false,
        AutoTPToPSOnSteal = false,
        PSLinkCode      = "",
        PSPlaceId       = "",
        ShowAdminPanel  = false,
        ClickToAP       = false,
        ProximityAP     = false,
        ProximityRange  = 15,
        SpamBaseOwner   = false,
        StealNearest    = false,
        StealHighest    = false,
        StealPriority   = false,
        InfiniteJump    = false,
        AutoTeleport    = false,
        TPBackOnHit     = false,
        AntiRagdoll     = false,
        AntiBeeDisco    = false,
        AntiBodySwap    = true,
        AutoDestroyTurrets = false,
        Animations      = false,
        CancelAPPanelOnAtlas   = true,
        CancelAPPanelOnKawaifu = true,
        CancelAPPanelOnMoby    = true,
        CancelAPPanelOnBraintopia = true,
        CancelAPPanelOnFMLY    = true,
        CloneKey        = "V",
        RejoinKey       = "",
        LeaveKey        = "",
        ResetKey        = "",
        MenuKey         = "RightShift",
        TpKey           = "T",
        InstantResetKey = "R",
        BaseTimer       = false,
        FPSBoost        = false,
        UnlockButtons   = false,
        XrayBases       = false,
        CustomTab       = {},
        CarpetSpeed     = false,
        CarpetSpeedKey  = "Q",
        ItemDropKey     = "G",
        BrainrotDropKey = "H",
        AutoBuyKey      = "N",
        CancelTPKey     = "X",
    }
    _G.MeerkoConfig = Config

    local MK_SAVE_FILE = "chopper_HUB.json"
    local function MK_readRoot()
        if not (readfile and isfile) then return {} end
        local ok, root = pcall(function()
            if isfile(MK_SAVE_FILE) then
                return MK_Http:JSONDecode(readfile(MK_SAVE_FILE))
            end
        end)
        return (ok and type(root) == "table") and root or {}
    end
    local function SaveConfig()
        if not writefile then return end
        pcall(function()
            local root = MK_readRoot()
            root.main = Config
            writefile(MK_SAVE_FILE, MK_Http:JSONEncode(root))
        end)
    end
    do
        local root = MK_readRoot()
        if type(root.main) == "table" then
            for k, v in pairs(root.main) do Config[k] = v end
        end
        -- Force the menu open bind to Left Ctrl (override whatever was saved).
        Config.MenuKey = "LeftControl"
    end
    _G.MeerkoCarpetTool = Config.CarpetTool or "Auto"
    if Config.GameStretcher then _bindStretch() end

    -- animations on/off (TP kills them by default; this flag restores them)
    _G.MeerkoAnimations = Config.Animations == true
    if _G.MeerkoAnimations and MK_LP.Character and _G.MeerkoRestoreAnims then
        pcall(_G.MeerkoRestoreAnims, MK_LP.Character)
    end

    -- =================================================================
    -- Kill stray beams on game tools (e.g. Grapple Hook) that create
    -- phantom "line to base" visuals
    -- =================================================================
    task.spawn(function()
        local LP = MK_LP
        local function killToolBeams()
            for _, container in ipairs({LP:FindFirstChild("Backpack"), LP.Character}) do
                if container then
                    for _, tool in ipairs(container:GetChildren()) do
                        if tool:IsA("Tool") then
                            for _, d in ipairs(tool:GetDescendants()) do
                                if d:IsA("Beam") then d.Enabled = false end
                            end
                        end
                    end
                end
            end
        end
        killToolBeams()
        LP.CharacterAdded:Connect(function() task.wait(1); killToolBeams() end)
        local bp = LP:WaitForChild("Backpack", 5)
        if bp then bp.ChildAdded:Connect(function(c) if c:IsA("Tool") then task.wait(0.1); killToolBeams() end end) end
    end)

    -- =================================================================
    -- LINE TO BASE  [_G.createPlotBeam / _G.resetPlotBeam]
    -- =================================================================
    task.spawn(function()
        local RunService = MK_Run
        local LocalPlayer = MK_LP
        local plotBeam, plotBeamAttachment0, plotBeamAttachment1
        local cachedPlot, cachedPlotPart

        local function findMyPlot()
            if cachedPlot and cachedPlot.Parent then return cachedPlot end
            local plots = workspace:FindFirstChild("Plots")
            if not plots then return nil end
            for _, plot in ipairs(plots:GetChildren()) do
                local sign = plot:FindFirstChild("PlotSign")
                if sign then
                    local surfaceGui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                    if surfaceGui then
                        local label = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
                        if label then
                            local text = label.Text:lower()
                            if text:find(LocalPlayer.DisplayName:lower(), 1, true) or text:find(LocalPlayer.Name:lower(), 1, true) then
                                cachedPlot = plot
                                return plot
                            end
                        end
                    end
                end
            end
            return nil
        end

        local function createPlotBeam()
            if not Config.LineToBase then return end
            local myPlot = findMyPlot()
            if not myPlot or not myPlot.Parent then return end
            local character = LocalPlayer.Character
            if not character or not character.Parent then return end
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp or not hrp.Parent then return end

            if plotBeam then pcall(function() plotBeam:Destroy() end); plotBeam = nil end
            if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end); plotBeamAttachment0 = nil end
            if plotBeamAttachment1 then pcall(function() plotBeamAttachment1:Destroy() end); plotBeamAttachment1 = nil end

            for _, d in ipairs(workspace:GetDescendants()) do
                if (d:IsA("Beam") and d.Name == "PlotBeam") or (d:IsA("Attachment") and d.Name == "PlotBeamAttach_Player") then
                    pcall(function() d:Destroy() end)
                end
            end

            plotBeamAttachment0 = Instance.new("Attachment")
            plotBeamAttachment0.Name = "PlotBeamAttach_Player"
            plotBeamAttachment0.Parent = hrp

            local plotPart = myPlot:FindFirstChild("AnimalTarget")
                or myPlot:FindFirstChild("MainRootPart")
                or myPlot:FindFirstChildWhichIsA("BasePart")
            if not plotPart or not plotPart.Parent then return end
            cachedPlotPart = plotPart

            for _, c in ipairs(plotPart:GetChildren()) do
                if c.Name == "PlotBeamAttach_Plot" then pcall(function() c:Destroy() end) end
            end
            plotBeamAttachment1 = Instance.new("Attachment")
            plotBeamAttachment1.Name = "PlotBeamAttach_Plot"
            plotBeamAttachment1.Parent = plotPart

            plotBeam = Instance.new("Beam")
            plotBeam.Name = "PlotBeam"
            plotBeam.Attachment0 = plotBeamAttachment0
            plotBeam.Attachment1 = plotBeamAttachment1
            plotBeam.FaceCamera = true
            plotBeam.LightEmission = 0.3
            plotBeam.LightInfluence = 0
            plotBeam.Brightness = 1
            plotBeam.Color = ColorSequence.new(Color3.fromRGB(0, 200, 255))
            plotBeam.Transparency = NumberSequence.new(0.3)
            plotBeam.Width0 = 0.7
            plotBeam.Width1 = 0.7
            plotBeam.TextureMode = Enum.TextureMode.Wrap
            plotBeam.TextureSpeed = 0
            plotBeam.Enabled = true
            plotBeam.Parent = hrp
        end

        local function resetPlotBeam()
            if plotBeam then pcall(function() plotBeam:Destroy() end) end
            if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
            if plotBeamAttachment1 then pcall(function() plotBeamAttachment1:Destroy() end) end
            plotBeam = nil
            plotBeamAttachment0 = nil
            plotBeamAttachment1 = nil
        end

        local function isBeamAlive()
            return plotBeam and plotBeam.Parent
                and plotBeam.Enabled
                and plotBeamAttachment0 and plotBeamAttachment0.Parent
                and plotBeamAttachment1 and plotBeamAttachment1.Parent
        end

        _G.createPlotBeam = createPlotBeam
        _G.resetPlotBeam = resetPlotBeam

        do
            local _lbFrame = 0
            RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not Config.LineToBase then return end
                _lbFrame = _lbFrame + 1
                if _lbFrame < 30 then return end
                _lbFrame = 0
                if not isBeamAlive() then
                    pcall(createPlotBeam)
                end
            end))
        end

        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            if Config.LineToBase then pcall(createPlotBeam) end
        end)

        if Config.LineToBase and LocalPlayer.Character then
            task.wait(0.2)
            pcall(createPlotBeam)
        end
    end)

    task.spawn(function()
        local RunService = MK_Run
        local LocalPlayer = MK_LP
        local brBeam, brA0, brA1, brTargetPart

        local function cleanupBrainrotOrphans(hrp)
            if hrp then
                for _, c in ipairs(hrp:GetChildren()) do
                    if c.Name == "MeerkoBrainrotBeam" or c.Name == "BrainrotBeamA0" then pcall(function() c:Destroy() end) end
                end
            end
            for _, c in ipairs(workspace:GetChildren()) do
                if c.Name == "MeerkoBrainrotBeamTarget" then pcall(function() c:Destroy() end) end
            end
        end

        local function resetBrainrotBeam()
            if brBeam then pcall(function() brBeam:Destroy() end); brBeam = nil end
            if brA0 then pcall(function() brA0:Destroy() end); brA0 = nil end
            if brA1 then pcall(function() brA1:Destroy() end); brA1 = nil end
            if brTargetPart then pcall(function() brTargetPart:Destroy() end); brTargetPart = nil end
        end

        local function buildBrainrotBeam()
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            resetBrainrotBeam()
            cleanupBrainrotOrphans(hrp)

            brTargetPart = Instance.new("Part")
            brTargetPart.Name = "MeerkoBrainrotBeamTarget"
            brTargetPart.Anchored = true; brTargetPart.CanCollide = false; brTargetPart.Transparency = 1
            brTargetPart.Size = Vector3.new(1, 1, 1)
            brTargetPart.Parent = workspace

            brA0 = Instance.new("Attachment"); brA0.Name = "BrainrotBeamA0"; brA0.Parent = hrp
            brA1 = Instance.new("Attachment"); brA1.Name = "BrainrotBeamA1"; brA1.Parent = brTargetPart

            brBeam = Instance.new("Beam")
            brBeam.Name = "MeerkoBrainrotBeam"
            brBeam.Attachment0 = brA0; brBeam.Attachment1 = brA1
            brBeam.Width0 = 0.7; brBeam.Width1 = 0.7
            brBeam.Color = ColorSequence.new(Color3.fromRGB(100, 170, 255))
            brBeam.Transparency = NumberSequence.new(0.3)
            brBeam.LightEmission = 0.3
            brBeam.LightInfluence = 0
            brBeam.Brightness = 1
            brBeam.FaceCamera = true
            brBeam.TextureMode = Enum.TextureMode.Wrap
            brBeam.TextureSpeed = 0
            brBeam.Enabled = false
            brBeam.Parent = hrp
        end

        _G.resetBrainrotBeam = resetBrainrotBeam
        _G.MeerkoBrainrotBeamSet = function(on)
            Config.LineToBrainrot = on; SaveConfig()
            if on then buildBrainrotBeam() else resetBrainrotBeam() end
        end

        do
            local _lbrFrame = 0
            RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not Config.LineToBrainrot then return end
                _lbrFrame = _lbrFrame + 1
                if _lbrFrame < 30 then return end
                _lbrFrame = 0

                if not brBeam or not brBeam.Parent or not brA0 or not brA0.Parent then
                    pcall(buildBrainrotBeam)
                    return
                end

                local isStealing = LocalPlayer:GetAttribute("Stealing") == true
                local t = _G.MeerkoCurrentSteal

                if isStealing or not t or not t.uid then
                    brBeam.Enabled = false
                    return
                end

                local ok, pets = pcall(scanAllPets)
                if ok and type(pets) == "table" then
                    for _, p in ipairs(pets) do
                        if (tostring(p.plot) .. "|" .. tostring(p.slot)) == t.uid then
                            brTargetPart.Position = p.position
                            brBeam.Enabled = true
                            return
                        end
                    end
                end
                brBeam.Enabled = false
            end))
        end

        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            if Config.LineToBrainrot then pcall(buildBrainrotBeam) end
        end)

        if Config.LineToBrainrot then task.wait(0.3); pcall(buildBrainrotBeam) end
    end)

    -- =================================================================
    -- SUBSPACE MINE ESP   [_G.MeerkoSubspaceSet]
    -- =================================================================
    task.spawn(function()
        local Players = MK_Players
        local Workspace = MK_Workspace
        local subspaceMineESPData = {}
        local FolderName = "ToolsAdds"

        local function getMineOwner(mineName)
            local ownerName = mineName:match("SubspaceTripmine(.+)")
            if not ownerName then return "Unknown" end
            local foundPlayer = Players:FindFirstChild(ownerName)
            return foundPlayer and foundPlayer.DisplayName or ownerName
        end

        local function createMineESP(mine)
            local ownerName = getMineOwner(mine.Name)
            local selectionBox = Instance.new("SelectionBox")
            selectionBox.Name = "ESP_Hitbox"
            selectionBox.Adornee = mine
            selectionBox.Color3 = Color3.fromRGB(167, 142, 255)
            selectionBox.LineThickness = 0.05
            selectionBox.Parent = mine

            local billboardGui = Instance.new("BillboardGui")
            billboardGui.Name = "ESP_Label"
            billboardGui.Adornee = mine
            billboardGui.Size = UDim2.new(0, 250, 0, 50)
            billboardGui.StudsOffset = Vector3.new(0, 2.5, 0)
            billboardGui.AlwaysOnTop = false
            billboardGui.Parent = mine

            local textLabel = Instance.new("TextLabel", billboardGui)
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.Text = ownerName .. "'s Subspace Mine"
            textLabel.TextColor3 = Color3.fromRGB(167, 142, 255)
            textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            textLabel.TextStrokeTransparency = 0
            textLabel.Font = Enum.Font.GothamBold
            textLabel.TextSize = 16

            return { selectionBox = selectionBox, billboardGui = billboardGui, mine = mine }
        end

        local function clearAll()
            for i, data in pairs(subspaceMineESPData) do
                if data.selectionBox and data.selectionBox.Parent then data.selectionBox:Destroy() end
                if data.billboardGui and data.billboardGui.Parent then data.billboardGui:Destroy() end
                subspaceMineESPData[i] = nil
            end
        end

        local function refreshSubspaceMineESP()
            if not Config.SubspaceMineESP then clearAll(); return end
            local toolsFolder = Workspace:FindFirstChild(FolderName)
            if not toolsFolder then return end
            local currentMines = {}
            for _, obj in pairs(toolsFolder:GetChildren()) do
                if obj.Name:match("^SubspaceTripmine") and obj:IsA("BasePart") then
                    currentMines[obj] = true
                    if not subspaceMineESPData[obj] then
                        subspaceMineESPData[obj] = createMineESP(obj)
                    end
                end
            end
            for mineObj, data in pairs(subspaceMineESPData) do
                if not currentMines[mineObj] or not mineObj.Parent then
                    if data.selectionBox and data.selectionBox.Parent then data.selectionBox:Destroy() end
                    if data.billboardGui and data.billboardGui.Parent then data.billboardGui:Destroy() end
                    subspaceMineESPData[mineObj] = nil
                end
            end
        end

        _G.MeerkoSubspaceSet = function(enabled)
            Config.SubspaceMineESP = enabled
            if not enabled then clearAll() end
        end

        -- SubspaceMineESP refresh 0.5s -> 1s. Mines don't move; once-per-second
        -- pickup is plenty.
        while true do
            task.wait(1)
            pcall(refreshSubspaceMineESP)
        end
    end)

    task.spawn(function()
        local Players    = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local LP         = Players.LocalPlayer
        while not LP do task.wait(0.2); LP = Players.LocalPlayer end

        local function curDepth()
            local d = tonumber(_G.VanishInvisDepth) or Config.InvisDepth or 5
            return d * 0.5
        end
        local function curRotation()
            local a = tonumber(_G.VanishInvisAngle) or Config.InvisRotation or 180
            return math.clamp(a, 0, 360)
        end
        local function curWalkSpeed()
            local w = tonumber(_G.VanishInvisWalkSpeed) or Config.InvisWalkSpeed or 16
            return math.clamp(w, 5, 32)
        end

        -- ── Anti-die (keeps the character alive while the HRP is under the camera) ──
        local antiDieConns = {}
        local lastSafePos = nil
        local function preserveState(character)
            local hum = character:FindFirstChildOfClass("Humanoid")
            if not hum then return {} end
            local state = { WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower, Tools = {} }
            for _, tool in pairs(character:GetChildren()) do
                if tool:IsA("Tool") then table.insert(state.Tools, tool:Clone()) end
            end
            return state
        end
        local function restoreState(character, state)
            local hum = character:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            hum.WalkSpeed = state.WalkSpeed; hum.JumpPower = state.JumpPower
            for _, tool in pairs(state.Tools) do tool.Parent = character end
        end
        local function teardownAntiDie()
            for _, c in pairs(antiDieConns) do if c then c:Disconnect() end end
            antiDieConns = {}
            local char = LP.Character
            if char then local ff = char:FindFirstChildOfClass("ForceField"); if ff then ff:Destroy() end end
        end
        local setupAntiDie
        setupAntiDie = function(character)
            for _, c in pairs(antiDieConns) do if c then c:Disconnect() end end
            antiDieConns = {}
            if not character then return end
            local hum = character:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            hum.BreakJointsOnDeath = false
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            local ff = Instance.new("ForceField"); ff.Visible = false; ff.Parent = character
            table.insert(antiDieConns, hum:GetPropertyChangedSignal("Health"):Connect(function()
                if _G.VanishDead then return end
                if hum.Health <= 0 then task.wait(math.random(0.05, 0.15)); hum.Health = hum.MaxHealth end
            end))
            table.insert(antiDieConns, hum.Died:Connect(function()
                if _G.VanishDead then return end
                task.wait(0.1)
                local state = preserveState(character)
                local newHum = Instance.new("Humanoid")
                newHum.Name = hum.Name; newHum.Parent = character
                newHum.Health = newHum.MaxHealth
                restoreState(character, state)
                workspace.CurrentCamera.CameraSubject = newHum
                hum:Destroy(); task.wait(0.1); setupAntiDie(character)
            end))
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                lastSafePos = root.Position
                local _adFrame = 0
                table.insert(antiDieConns, RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                    if _G.VanishDead then return end
                    _adFrame = _adFrame + 1
                    if _adFrame < 6 then return end
                    _adFrame = 0
                    if not root or not root.Parent then return end
                    local pos = root.Position
                    if pos.Y < -500 or (lastSafePos and (pos - lastSafePos).Magnitude > 100) then
                        root.CFrame = CFrame.new(lastSafePos)
                    else lastSafePos = pos end
                end)))
            end
        end

        -- ── Core ──
        local semiIsActive = false
        local invisStealConnections = {}
        local invisAnimTrack = nil
        local invisOldHRP = nil
        local invisClone = nil
        local invisHipHeight = nil
        local invisOrigWalkSpeed = nil
        local invisIsStuck = false
        local invisStuckPosition = nil
        local invisStealStopPending = false
        local invisOrigTransparency = nil
        local startInvisSteal, stopInvisSteal

        stopInvisSteal = function()
            semiIsActive = false; invisIsStuck = false; invisStuckPosition = nil
            teardownAntiDie()
            if invisOrigTransparency then
                for p, orig in pairs(invisOrigTransparency) do
                    if p and p.Parent then pcall(function() p.LocalTransparencyModifier = orig end) end
                end
                invisOrigTransparency = nil
            end
            if invisAnimTrack then
                pcall(function() invisAnimTrack:Stop() end)
                pcall(function() invisAnimTrack:Destroy() end)
                invisAnimTrack = nil
            end
            for _, conn in ipairs(invisStealConnections) do pcall(function() conn:Disconnect() end) end
            invisStealConnections = {}
            if invisOldHRP and invisOldHRP:IsDescendantOf(game.Workspace) and LP.Character and LP.Character:FindFirstChild("Humanoid") then
                local tempParent = Instance.new("Model"); tempParent.Parent = game
                LP.Character.Parent = tempParent
                invisOldHRP.Parent = LP.Character; LP.Character.PrimaryPart = invisOldHRP
                LP.Character.Parent = workspace
                invisOldHRP.CanCollide = true
                for _, v in pairs(LP.Character:GetDescendants()) do
                    if v:IsA("Weld") or v:IsA("Motor6D") then
                        if v.Part0 == invisClone then v.Part0 = invisOldHRP end
                        if v.Part1 == invisClone then v.Part1 = invisOldHRP end
                    end
                end
                if invisClone then
                    local oldPos = invisClone.CFrame; invisClone:Destroy(); invisClone = nil
                    invisOldHRP.CFrame = oldPos
                end
                if LP.Character.Humanoid then
                    LP.Character.Humanoid.HipHeight = invisHipHeight or 0
                    if invisOrigWalkSpeed then LP.Character.Humanoid.WalkSpeed = invisOrigWalkSpeed end
                end
                tempParent:Destroy()
            end
            invisOldHRP = nil; invisClone = nil; invisOrigWalkSpeed = nil
            _G.VanishInvisActive = false
            _G.MeerkoInvisOldHRP = nil
        end

        startInvisSteal = function()
            if not LP.Character or not LP.Character:FindFirstChild("Humanoid") then return false end
            local char = LP.Character; local hum = char.Humanoid
            setupAntiDie(char)
            local playerFolder = workspace:FindFirstChild(LP.Name)
            if playerFolder then
                local rigDuplo = playerFolder:FindFirstChild("DoubleRig")
                if rigDuplo then rigDuplo:Destroy() end
                local restricoes = playerFolder:FindFirstChild("Constraints")
                if restricoes then restricoes:Destroy() end
                local folderConn = playerFolder.ChildAdded:Connect(function(filho)
                    if filho.Name == "DoubleRig" or filho.Name == "Constraints" then filho:Destroy() end
                end)
                table.insert(invisStealConnections, folderConn)
            end
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            invisHipHeight = hum.HipHeight
            invisOldHRP = char:FindFirstChild("HumanoidRootPart")
            if not invisOldHRP or not invisOldHRP.Parent then return false end
            _G.MeerkoInvisOldHRP = invisOldHRP
            local tempParent = Instance.new("Model"); tempParent.Parent = game
            char.Parent = tempParent
            invisClone = invisOldHRP:Clone(); invisClone.Parent = char
            invisOldHRP.Parent = workspace.CurrentCamera
            for _, c in ipairs(invisOldHRP:GetChildren()) do
                if c.Name == "PlotBeam" or c.Name == "PlotBeamAttach_Player" or c.Name == "MeerkoBrainrotBeam" or c.Name == "BrainrotBeamA0" then
                    pcall(function() c:Destroy() end)
                end
            end
            invisClone.CFrame = invisOldHRP.CFrame
            char.PrimaryPart = invisClone
            char.Parent = workspace
            for _, v in pairs(char:GetDescendants()) do
                if v:IsA("Weld") or v:IsA("Motor6D") then
                    if v.Part0 == invisOldHRP then v.Part0 = invisClone end
                    if v.Part1 == invisOldHRP then v.Part1 = invisClone end
                end
            end
            tempParent:Destroy()
            semiIsActive = true
            local function playAnimTrick()
                if char and char:FindFirstChild("Humanoid") and hum.Health > 0 then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = "http://www.roblox.com/asset/?id=18537363391"
                    local animator = hum:FindFirstChild("Animator") or Instance.new("Animator", hum)
                    invisAnimTrack = animator:LoadAnimation(anim)
                    invisAnimTrack.Priority = Enum.AnimationPriority.Action4
                    invisAnimTrack.Looped = true
                    invisAnimTrack:Play(0, 1, 0); anim:Destroy()
                    local animStoppedConn = invisAnimTrack.Stopped:Connect(function()
                        if semiIsActive and not _G.VanishDead then playAnimTrick() end
                    end)
                    table.insert(invisStealConnections, animStoppedConn)
                    task.delay(0, function()
                        if invisAnimTrack then
                            invisAnimTrack.TimePosition = 0.8
                            task.delay(0.35, function()
                                if invisAnimTrack then invisAnimTrack:AdjustSpeed(math.huge) end
                            end)
                        end
                    end)
                end
            end
            playAnimTrick()

            invisOrigTransparency = {}
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    invisOrigTransparency[p] = p.LocalTransparencyModifier
                    p.LocalTransparencyModifier = 1
                end
            end
            local addConn = char.DescendantAdded:Connect(function(d)
                if d:IsA("BasePart") and semiIsActive then
                    if invisOrigTransparency and not invisOrigTransparency[d] then
                        invisOrigTransparency[d] = d.LocalTransparencyModifier
                    end
                    pcall(function() d.LocalTransparencyModifier = 1 end)
                end
            end)
            table.insert(invisStealConnections, addConn)

            local _healthFrame = 0
            local healthConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if _G.VanishDead then return end
                _healthFrame = _healthFrame + 1
                if _healthFrame < 12 then return end
                _healthFrame = 0
                if char and char:FindFirstChild("Humanoid") then
                    local h = char.Humanoid
                    h.Health = h.MaxHealth
                    h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                    local state = h:GetState()
                    if state == Enum.HumanoidStateType.Dead or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Ragdoll then
                        h:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end
            end))
            table.insert(invisStealConnections, healthConn)
            local lastSetPosition = nil; local skipFrames = 5
            local posConn = RunService.PreSimulation:Connect(function(dt)
                if _G.VanishDead then return end
                if char and char:FindFirstChild("Humanoid") and hum.Health > 0 and invisOldHRP then
                    local root = char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
                    if root then
                        if skipFrames > 0 then
                            skipFrames = skipFrames - 1
                            lastSetPosition = nil
                        elseif lastSetPosition then
                            local currentPos = invisOldHRP.Position
                            local jumpDistance = (currentPos - lastSetPosition).Magnitude
                            if jumpDistance > 3 and not _G.RecoveryInProgress then
                                lastSetPosition = nil
                                if _G.VanishInvisToggle then
                                    _G.RecoveryInProgress = true
                                    task.spawn(function()
                                        pcall(_G.VanishInvisToggle)
                                        task.wait(0.5)
                                        pcall(_G.VanishInvisToggle)
                                        _G.RecoveryInProgress = false
                                    end)
                                end
                            end
                        end
                        local md = hum.MoveDirection
                        if md.Magnitude > 0 then
                            local spd = curWalkSpeed()
                            local curY = root.Velocity.Y
                            root.Velocity = Vector3.new(md.X * spd, curY, md.Z * spd)
                        end
                        if invisClone then invisClone.CanCollide = true end
                        if not invisOldHRP or not invisOldHRP.Parent then return end
                        for _, c in pairs(invisOldHRP:GetChildren()) do
                            if c:IsA("Attachment") or c:IsA("Beam") then c:Destroy() end
                        end
                        if not invisOldHRP or not invisOldHRP.Parent then return end
                        local rotationAngle = curRotation()
                        local sinkAmount = curDepth()
                        local cf = root.CFrame - Vector3.new(0, sinkAmount, 0)
                        invisOldHRP.CFrame = cf * CFrame.Angles(math.rad(rotationAngle), 0, 0)
                        invisOldHRP.Velocity = root.Velocity
                        invisOldHRP.CanCollide = false
                        lastSetPosition = invisOldHRP.Position
                    end
                end
            end)
            table.insert(invisStealConnections, posConn)
            local charConn = LP.CharacterAdded:Connect(function(newChar)
                if semiIsActive then stopInvisSteal() end
            end)
            table.insert(invisStealConnections, charConn)
            _G.VanishInvisActive = true
            return true
        end

        local function toggleInvisSteal()
            if semiIsActive then stopInvisSteal()
            else startInvisSteal() end
        end

        -- ── Auto-invis: monitor the "Stealing" attribute and toggle on/off ──
        local INVIS_START_DELAY = 0.3
        local INVIS_LINGER      = 1.5
        local stealWasActive = false
        local autoInvisConn  = nil
        local invisLingerT   = nil
        local function startAutoMonitor()
            stealWasActive = false
            invisLingerT = nil
            if autoInvisConn then autoInvisConn:Disconnect() end
            local _aimFrame = 0
            autoInvisConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if _G.VanishDead then return end
                _aimFrame = _aimFrame + 1
                if _aimFrame < 6 then return end
                _aimFrame = 0
                local stealing = LP:GetAttribute("Stealing") == true
                if stealing and not stealWasActive then
                    stealWasActive = true
                    invisLingerT = nil
                    if not semiIsActive then
                        task.delay(INVIS_START_DELAY, function()
                            if _G.VanishDead then return end
                            if not autoInvisConn then return end
                            if not (Config.InvisOnSteal or _G.VanishInvisAuto) then return end
                            if LP:GetAttribute("Stealing") ~= true then return end
                            if semiIsActive then return end
                            if not startInvisSteal() then semiIsActive = false; teardownAntiDie() end
                        end)
                    end
                elseif not stealing and stealWasActive then
                    stealWasActive = false
                    if semiIsActive then stopInvisSteal(); teardownAntiDie() end
                end
                if semiIsActive and not stealing then
                    if not invisLingerT then invisLingerT = os.clock() end
                    if os.clock() - invisLingerT > INVIS_LINGER then
                        stopInvisSteal(); teardownAntiDie()
                        invisLingerT = nil
                    end
                else
                    invisLingerT = nil
                end
            end))
        end
        local function stopAutoMonitor()
            if autoInvisConn then autoInvisConn:Disconnect(); autoInvisConn = nil end
            stealWasActive = false
            if semiIsActive then stopInvisSteal(); teardownAntiDie() end
        end

        _G.VanishInvisActive    = false
        _G.VanishInvisAngle     = Config.InvisRotation or 180
        _G.VanishInvisDepth     = Config.InvisDepth or 5
        _G.VanishInvisWalkSpeed = Config.InvisWalkSpeed or 16
        _G.VanishInvisToggle    = function() toggleInvisSteal() end
        _G.VanishInvisAutoStart = function() startAutoMonitor() end
        _G.VanishInvisAutoStop  = function() stopAutoMonitor() end

        -- Universal uninvis on Stealing=false. Fires whenever the "Stealing" attribute
        -- transitions to false, so it always ends with the steal action.
        LP:GetAttributeChangedSignal("Stealing"):Connect(function()
            if LP:GetAttribute("Stealing") == false and semiIsActive then
                pcall(stopInvisSteal)
                pcall(teardownAntiDie)
            end
        end)

        if Config.InvisOnSteal then startAutoMonitor() end
    end)

    -- =================================================================
    -- AUTO BUY CARPET  [_G.MeerkoAutoBuyCarpet]
    do
        _G.MeerkoAutoBuyCarpet = function(state)
            Config.AutoBuyCarpet = state and true or false
            if SaveConfig then pcall(SaveConfig) end
        end

        local _STEAL_NAMES = { StealHitbox=true, DeliveryHitbox=true, LaserHitbox=true }
        local _autoBuyActive = false
        local _autoBuyObj    = nil
        local _autoBuyIsClick = false

        local function _findBuyTarget()
            local LP2  = game:GetService("Players").LocalPlayer
            local char = LP2 and LP2.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil, false end
            local best, bestDist = nil, math.huge
            local bestClick = false
            for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
                local isPrompt = obj:IsA("ProximityPrompt") and obj.Enabled
                local isClick  = obj:IsA("ClickDetector")
                if isPrompt or isClick then
                    local part = obj.Parent
                    local realPart = (part and part:IsA("Attachment") and part.Parent) or part
                    if realPart and realPart:IsA("BasePart") and not _STEAL_NAMES[realPart.Name] then
                        local atxt = isPrompt and (obj.ActionText or ""):lower() or ""
                        local otxt = isPrompt and (obj.ObjectText or ""):lower() or ""
                        local pname = realPart.Name:lower()
                        local hit = atxt:find("buy") or atxt:find("purchase") or atxt:find("shop")
                                 or atxt:find("carpet") or atxt:find("get") or atxt:find("acheter")
                                 or otxt:find("buy") or otxt:find("carpet") or otxt:find("shop")
                                 or pname:find("buy") or pname:find("shop") or pname:find("carpet")
                        if hit then
                            local d = (hrp.Position - realPart.Position).Magnitude
                            if d < bestDist then bestDist = d; best = obj; bestClick = isClick end
                        end
                    end
                end
            end
            -- fallback: nearest prompt/click dans 60 studs
            if not best then
                for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
                    local isPrompt = obj:IsA("ProximityPrompt") and obj.Enabled
                    local isClick  = obj:IsA("ClickDetector")
                    if isPrompt or isClick then
                        local part = obj.Parent
                        local realPart = (part and part:IsA("Attachment") and part.Parent) or part
                        if realPart and realPart:IsA("BasePart") and not _STEAL_NAMES[realPart.Name] then
                            local d = (hrp.Position - realPart.Position).Magnitude
                            if d < bestDist and d < 60 then bestDist = d; best = obj; bestClick = isClick end
                        end
                    end
                end
            end
            return best, bestClick
        end

        local function _fireObj(obj, isClick)
            if not obj or not obj.Parent then return false end
            if isClick then
                pcall(function() if fireclickdetector then fireclickdetector(obj) end end)
            else
                if not obj.Enabled then return false end
                pcall(function() if fireproximityprompt then fireproximityprompt(obj) end end)
            end
            return true
        end

        -- Watcher : dès qu'un nouveau ProximityPrompt/ClickDetector apparaît dans le workspace,
        -- si le auto buy est actif et que c'est le même objet locké, on fire immédiatement.
        -- Ça intercepte le prompt avant n'importe qui d'autre.
        local _autoBuyWatchConn = nil
        local function _startWatcher()
            if _autoBuyWatchConn then pcall(function() _autoBuyWatchConn:Disconnect() end) end
            _autoBuyWatchConn = game:GetService("Workspace").DescendantAdded:Connect(function(obj)
                if not _autoBuyActive then return end
                local isPrompt = obj:IsA("ProximityPrompt")
                local isClick  = obj:IsA("ClickDetector")
                if not isPrompt and not isClick then return end
                -- Fire immédiatement 5 fois dès l'apparition
                task.spawn(function()
                    for _ = 1, 5 do
                        if not _autoBuyActive then break end
                        _fireObj(obj, isClick)
                        task.wait()
                    end
                end)
            end)
        end
        local function _stopWatcher()
            if _autoBuyWatchConn then pcall(function() _autoBuyWatchConn:Disconnect() end); _autoBuyWatchConn = nil end
        end

        local _autoBuyHoverConn = nil
        local function _stopHover()
            if _autoBuyHoverConn then
                pcall(function() _autoBuyHoverConn:Disconnect() end)
                _autoBuyHoverConn = nil
            end
        end

        local function _startHover(targetPart)
            _stopHover()
            local RS = game:GetService("RunService")
            local LP2 = game:GetService("Players").LocalPlayer
            _autoBuyHoverConn = RS.Heartbeat:Connect(function()
                if not _autoBuyActive or not targetPart or not targetPart.Parent then
                    _stopHover(); return
                end
                local char = LP2.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local dest = targetPart.Position + Vector3.new(0, 5, 0)
                pcall(function()
                    hrp.CFrame = CFrame.new(dest, dest + hrp.CFrame.LookVector)
                    hrp.AssemblyLinearVelocity  = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end)
            end)
        end

        -- Toggle : 1er appui = snap + hover sur le brainrot + buy en boucle, 2ème appui = stop
        _G.MeerkoToggleAutoBuy = function()
            if _autoBuyActive then
                _autoBuyActive = false
                _autoBuyObj    = nil
                _stopHover()
                _stopWatcher()
                return
            end
            local obj, isClick = _findBuyTarget()
            if not obj then return end
            _autoBuyObj     = obj
            _autoBuyIsClick = isClick
            _autoBuyActive  = true
            _startWatcher()

            -- Trouver la BasePart parent pour le hover
            local part = obj.Parent
            local targetPart = (part and part:IsA("Attachment") and part.Parent) or part
            if targetPart and targetPart:IsA("BasePart") then
                -- Snap immédiat dessus
                local LP2 = game:GetService("Players").LocalPlayer
                local char = LP2 and LP2.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.CFrame = CFrame.new(targetPart.Position + Vector3.new(0, 5, 0))
                        hrp.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
                _startHover(targetPart)
            end

            -- 8 threads parallèles pour maximiser les fires par seconde
            for _ = 1, 8 do
                task.spawn(function()
                    while _autoBuyActive do
                        if not _autoBuyObj or not _autoBuyObj.Parent then
                            _autoBuyActive = false; _stopHover(); break
                        end
                        _fireObj(_autoBuyObj, _autoBuyIsClick)
                        task.wait()
                    end
                end)
            end
        end
    end



    _G.VanishDesync = _G.VanishDesync or {
        setJoin = function() end, rollback = function() end,
        setCycle = function() end, setBehind = function() end,
        suspend = function() end, resume = function() end,
        isActive = function() return false end,
    }
    _G.VanishDeltaDesync = _G.VanishDeltaDesync or {
        set = function() end, suspend = function() end,
        resume = function() end, isActive = function() return false end,
    }
    _G.MeerkoDesyncStatus = _G.MeerkoDesyncStatus or { enabled = false, active = false, remaining = 0 }


    -- =================================================================
    -- AUTO-KICK ON STEAL  (chopper_hub method: shut the server down when the
    -- "You stole" confirmation appears -- i.e. AFTER the brainrot is actually
    -- claimed, not while holding the prompt). Gated by Config.AutoKickOnSteal.
    -- =================================================================
    task.spawn(function()
        local function kickPlayer()
            local ok = pcall(function() game:Shutdown() end)
            if ok then return end
            pcall(function() MK_LP:Kick("") end)
        end
        MK_PlayerGui.DescendantAdded:Connect(function(desc)
            if not (desc:IsA("TextLabel") or desc:IsA("TextButton")) then return end
            local txt = desc.Text
            if type(txt) == "string" and string.find(txt, "You stole", 1, true) then
                if Config.AutoKickOnSteal then
                    kickPlayer()
                elseif Config.AutoTPToPSOnSteal then
                    pcall(function()
                        local code = (Config.PSLinkCode and Config.PSLinkCode ~= "") and Config.PSLinkCode or nil
                        local pid = (Config.PSPlaceId and Config.PSPlaceId ~= "") and tonumber(Config.PSPlaceId) or game.PlaceId
                        if code then
                            game:GetService("ExperienceService"):LaunchExperience({ placeId = pid, linkCode = code })
                        else
                            game:GetService("TeleportService"):Teleport(pid, MK_LP)
                        end
                    end)
                end
            end
        end)
    end)

    task.spawn(function()
        local Workspace = MK_Workspace
        local espEnabled = Config.BrainrotESP == true
        local billboards = {}   -- [model] = {bb=, hl=}
        local espFolder = Instance.new("Folder")
        espFolder.Name = "MeerkoBrainrotESP"
        espFolder.Parent = Workspace

        local function fmtGen(gv)
            gv = gv or 0
            if gv >= 1e9 then return string.format("$%.1fB/s", gv / 1e9) end
            if gv >= 1e6 then return string.format("$%.1fM/s", gv / 1e6) end
            if gv >= 1e3 then return string.format("$%.1fK/s", gv / 1e3) end
            return string.format("$%d/s", math.floor(gv))
        end

        local function getPetModel(plot, slot)
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if not podiums then return nil end
            local podium = podiums:FindFirstChild(tostring(slot))
            if not podium then return nil end
            for _, desc in ipairs(podium:GetDescendants()) do
                if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
                    local part = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart", true)
                    if part then return desc, part end
                end
            end
            local anyPart = podium:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then
                return (anyPart:FindFirstAncestorOfClass("Model") or anyPart), anyPart
            end
            return nil
        end

        local function buildCard()
            local bb = Instance.new("BillboardGui")
            bb.Name = "MeerkoBR"
            bb.Size = UDim2.new(0, 220, 0, 36)
            bb.StudsOffset = Vector3.new(0, 5, 0)
            bb.AlwaysOnTop = true
            bb.LightInfluence = 0
            bb.MaxDistance = 3000
            bb.ResetOnSpawn = false

            -- clean: just the brainrot name + money/sec, no box / outline / extras
            local nameLabel = Instance.new("TextLabel", bb)
            nameLabel.Name = "Name"
            nameLabel.Size = UDim2.new(1, 0, 0, 18)
            nameLabel.Position = UDim2.new(0, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextStrokeTransparency = 0.4
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 14
            nameLabel.TextXAlignment = Enum.TextXAlignment.Center

            local genLabel = Instance.new("TextLabel", bb)
            genLabel.Name = "Gen"
            genLabel.Size = UDim2.new(1, 0, 0, 15)
            genLabel.Position = UDim2.new(0, 0, 0, 18)
            genLabel.BackgroundTransparency = 1
            genLabel.TextColor3 = Color3.fromRGB(90, 230, 140)
            genLabel.TextStrokeTransparency = 0.4
            genLabel.Font = Enum.Font.GothamBold
            genLabel.TextSize = 12
            genLabel.TextXAlignment = Enum.TextXAlignment.Center
            return bb
        end

        local function clearAll()
            for model, e in pairs(billboards) do
                if e.bb then pcall(function() e.bb:Destroy() end) end
                billboards[model] = nil
            end
        end

        local function scanESP()
            local out = {}
            if not loadModules() then return out end
            local Plots = Workspace:FindFirstChild("Plots")
            if not Plots then return out end
            for _, plot in ipairs(Plots:GetChildren()) do
                local channel = getPlotChannel(plot.Name)
                if channel and not isMyPlot(channel) and ownerInGame(channel) then
                    local animalList = channelGet(channel, "AnimalList")
                    if animalList then
                        for slot, animalData in pairs(animalList) do
                            if type(animalData) == "table" and animalData.Index then
                                local animalInfo = AnimalsData and AnimalsData[animalData.Index]
                                if animalInfo then
                                    local mutation = animalData.Mutation or "None"
                                    local genValue = 0
                                    pcall(function()
                                        genValue = AnimalsShared:GetGeneration(animalData.Index, animalData.Mutation, animalData.Traits, nil)
                                    end)
                                    local model, part = getPetModel(plot, slot)
                                    if model and part then
                                        out[#out + 1] = {
                                            model = model,
                                            part = part,
                                            name = animalInfo.DisplayName or animalData.Index,
                                            mps = genValue,
                                            mutation = mutation,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
            table.sort(out, function(a, b)
                return petOutranks(a.name, b.name, a.mutation, b.mutation, a.mps, b.mps)
            end)
            return out
        end

        local function refresh()
            if not espEnabled then return end
            local pets = scanESP()
            local char = MK_LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local seen = {}
            for i, pet in ipairs(pets) do
                if i > 1 then break end
                local model = pet.model
                -- BillboardGui.Adornee MUST be a BasePart (a Model throws and would
                -- abort the whole refresh); the Highlight can adorn the Model.
                local adornPart = pet.part
                if model and model.Parent and adornPart and adornPart.Parent then
                    seen[model] = true
                    local e = billboards[model]
                    if not e or not e.bb or not e.bb.Parent then
                        if e and e.bb then pcall(function() e.bb:Destroy() end) end
                        local bb = buildCard()
                        bb.Adornee = adornPart
                        bb.Parent = espFolder
                        e = { bb = bb }
                        billboards[model] = e
                    end
                    e.bb.Adornee = adornPart
                    e.bb:FindFirstChild("Name", true).Text = pet.name
                    e.bb:FindFirstChild("Gen", true).Text = fmtGen(pet.mps)
                end
            end
            for model, e in pairs(billboards) do
                if not seen[model] then
                    if e.bb then pcall(function() e.bb:Destroy() end) end
                    billboards[model] = nil
                end
            end
        end

        _G.MeerkoBrainrotESPSet = function(on)
            espEnabled = on
            Config.BrainrotESP = on
            _G.MeerkoBRDebug = _G.MeerkoBRDebug or {}
            _G.MeerkoBRDebug.enabled = on
            if not on then clearAll() end
        end

        -- Inspect at any time in your console:  print(_G.MeerkoBRDebug)
        _G.MeerkoBRDebug = { enabled = espEnabled, lastScan = -1, lastError = nil, active = 0 }

        while true do
            task.wait(1)
            if espEnabled then
                local ok, err = pcall(function()
                    refresh()
                    local n = 0
                    for _ in pairs(billboards) do n = n + 1 end
                    _G.MeerkoBRDebug.active = n
                end)
                if not ok then
                    _G.MeerkoBRDebug.lastError = tostring(err)
                end
            end
        end
    end)

    -- ============================================================
    -- ADMIN PANEL  (standalone chopper_hub panel -- branded chopper_hub, red)
    -- Replaces the previous built-in admin panel. Visibility is tied to the
    -- Misc "Admin Panel" toggle via _G.MeerkoSetAdminPanel.
    -- ============================================================
    task.spawn(function()
    task.wait(3)  -- delay build ~3s after joining so it doesn't tank load-in FPS
--[[
    chopper_hub Admin Panel — Standalone (Fixed & Upgraded)

    Fixes & Upgrades:
      1. Emoji button labels (🚀 🏃‍♂️ 🔒 🎈) replaced with text labels
         (RKT / RAG / JAIL / BAL) so Gotham renders them — emojis showed as "???".
      2. Top-level pcall + print so silent errors (e.g. blocked CoreGui access
         on some executors) don't make the panel invisible with no feedback.
      3. The Highlight created in CoreGui is itself pcall-wrapped, and every
         consumer of it is now nil-safe.
      4. Added Braintopia user detection and all configurations for Braintopia
         (ESP tags, Click-to-AP, Proximity AP, AP Panel button bypasses).
      5. Added a dedicated SETTINGS tab to easily toggle all bypasses and options.
      6. Default configured all settings and functions (like Moby, Kawaifu, Atlas,
         Braintopia bypasses, Click-to-AP, Proximity AP) to ON out-of-the-box.
]]

print("[chopper_hub Admin] script loaded — initializing…")

-- ── Services ────────────────────────────────────────────────────────────────
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local UserInputService    = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local HttpService         = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

if not Players.LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- Second hookfunction removed: the first hook (line ~226) already handles
-- the StopTrying bypass and remote capture. Chaining two hooks on FireServer
-- doubled the cost of every remote call and caused FPS drops on some executors.
_G.CapturedResetRemote = _G.MeerkoResetRemote

-- ── Config (admin-panel slice only) ─────────────────────────────────────────
local FileName = "chopper_HUB.json"
local DefaultConfig = {
    Positions = {
        AdminPanel = {X = 0.1859375, Y = 0.5767123526556385},
    },
    PanelScales = {},
    MobileGuiScale = 0.5,
    UILocked = false,

    ProximityRange = 15,
    ClickToAP = true,
    ClickToAPSingleCommand = false,
    ProximityAPActive = true,

    DisableClickToAPOnMoby     = true,
    DisableClickToAPOnKawaifu  = true,
    DisableClickToAPOnAtlas    = true,
    DisableClickToAPOnBraintopia = true,
    DisableClickToAPOnWNotifier = true,
    DisableProximitySpamOnMoby     = true,
    DisableProximitySpamOnKawaifu  = true,
    DisableProximitySpamOnAtlas    = true,
    DisableProximitySpamOnBraintopia = true,
    DisableProximitySpamOnWNotifier = true,
    DisableAPPanelOnMoby     = true,
    DisableAPPanelOnKawaifu  = true,
    DisableAPPanelOnAtlas    = true,
    DisableAPPanelOnBraintopia = true,
    DisableAPPanelOnWNotifier = true,

    MobyESPInAdminPanel    = true,
    KawaifuESPInAdminPanel = true,
    AtlasESPInAdminPanel   = true,
    BraintopiaESPInAdminPanel = true,
    WNotifierESPInAdminPanel = true,

    HideKawaifuFromPanel = false,

    TpSettings = { Tool = "Flying Carpet" },

    BlacklistedUsers = {},
}

local function AP_readRoot()
    if not (readfile and isfile) then return {} end
    local ok, root = pcall(function()
        if isfile(FileName) then
            return HttpService:JSONDecode(readfile(FileName))
        end
    end)
    return (ok and type(root) == "table") and root or {}
end

local Config = DefaultConfig
if isfile and isfile(FileName) then
    pcall(function()
        local decoded = AP_readRoot().admin
        if type(decoded) == "table" then
            for k, v in pairs(DefaultConfig) do
                if decoded[k] == nil then decoded[k] = v end
            end
            if decoded.Positions then
                for k, v in pairs(DefaultConfig.Positions) do
                    if decoded.Positions[k] == nil then decoded.Positions[k] = v end
                end
            end
            if decoded.TpSettings then
                for k, v in pairs(DefaultConfig.TpSettings) do
                    if decoded.TpSettings[k] == nil then decoded.TpSettings[k] = v end
                end
            end
            Config = decoded
        end
    end)
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

local function SaveConfig()
    if writefile then
        pcall(function()
            local root = AP_readRoot()
            root.admin = deepCopy(Config)
            writefile(FileName, HttpService:JSONEncode(root))
        end)
    end
end

-- ── Theme ───────────────────────────────────────────────────────────────────
local Theme = {
    Background       = Color3.fromRGB(30, 32, 44),
    Surface          = Color3.fromRGB(43, 46, 60),
    SurfaceHighlight = Color3.fromRGB(58, 62, 82),
    Accent1          = Color3.fromRGB(140, 146, 255),
    Accent2          = Color3.fromRGB(120, 110, 222),
    TextPrimary      = Color3.fromRGB(245, 247, 252),
    TextSecondary    = Color3.fromRGB(172, 180, 206),
    Success          = Color3.fromRGB(100, 220, 140),
    Error            = Color3.fromRGB(255, 95, 105),
}

local DANGER_TOOLS = {
    ["Boogie Bomb"]       = true,
    ["Medusa's Head"]     = true,
    ["Body Swap Potion"]  = true,
    ["Laser Cape"]        = true,
    ["Rainbowrath Sword"] = true,
    ["Gummy Bear"]        = true,
}

local PRIORITY_LIST = {
    "Strawberry Elephant", "Meowl", "Skibidi Toilet", "Headless Horseman",
    "Dragon Gingerini", "Dragon Cannelloni", "Ketupat Bros",
    "Hydra Dragon Cannelloni", "La Supreme Combinasion", "Love Love Bear",
    "Ginger Gerat", "Cerberus", "Capitano Moby", "La Casa Boo",
    "Burguro and Fryuro", "Spooky and Pumpky",
}

-- ── Shared state ────────────────────────────────────────────────────────────
local SharedState = {
    AdminButtonCache = {},
    AdminProxBtn = nil,
    ProximityAPButton = nil,
    ProximityAPButtonStroke = nil,
    BalloonedPlayers = {},
    MobileScaleObjects = {},
    RefreshMobileScale = nil,
    _RefreshAdminEmptyState = nil,
}

local ProximityAPActive = Config.ProximityAPActive

-- ── Mobile detection ────────────────────────────────────────────────────────
local function isMobile()
    return UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
        and not UserInputService.MouseEnabled
end
local IS_MOBILE = isMobile()

-- ── Hub-user detectors (ESP-based) ──────────────────────────────────────────
local function isMobyUser(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChild("_moby_highlight") ~= nil
end

local KAWAIFU_HL_NAME = "KaWaifu_NeonHighlight"
local function isKawaifuUser(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChild(KAWAIFU_HL_NAME) ~= nil
end

local function isAtlasUser(player)
    if not player then return false end
    local atlasFolder = workspace:FindFirstChild("AtlasESPFolder")
    if not atlasFolder then return false end
    local espFolder = atlasFolder:FindFirstChild(player.Name .. "_ESP")
    if not espFolder then return false end
    local hl = espFolder:FindFirstChildWhichIsA("Highlight")
    if not hl then return false end
    local fc = hl.FillColor
    return fc.R > 0.99 and math.abs(fc.G - 215/255) < 0.02 and fc.B < 0.01
end

local function isBraintopiaUser(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChild("BT_ESP") ~= nil
end

local function isWNotifierUser(player)
    if not player then return false end
    if player:GetAttribute("WUser_ESP_HOOKED") then return true end
    local c = player.Character
    if c and (c:FindFirstChild("WUser_USER_ESP") or c:FindFirstChild("WUser_ESP_HOOKED")) then return true end
    return false
end

local function isBlacklisted(player)
    if not player then return false end
    local name = player.Name:lower()
    for _, n in ipairs(Config.BlacklistedUsers) do
        if n:lower() == name then return true end
    end
    return false
end

-- ── UI helpers ──────────────────────────────────────────────────────────────
local function CreateGradient(_) return nil end

local function ApplyViewportUIScale(targetFrame)
    if not targetFrame then return end
    if not IS_MOBILE then return end
    local existing = targetFrame:FindFirstChild("__MobileUIScale")
    if existing then existing:Destroy() end
    local sc = Instance.new("UIScale")
    sc.Name = "__MobileUIScale"
    sc.Parent = targetFrame
    SharedState.MobileScaleObjects[targetFrame] = sc
    if SharedState.RefreshMobileScale then
        SharedState.RefreshMobileScale()
    else
        sc.Scale = math.clamp(tonumber(Config.MobileGuiScale) or 0.5, 0, 1)
    end
end

SharedState.RefreshMobileScale = function()
    local s = math.clamp(tonumber(Config.MobileGuiScale) or 0.5, 0, 1)
    for frame, sc in pairs(SharedState.MobileScaleObjects) do
        if frame and frame.Parent and sc and sc.Parent == frame then
            sc.Scale = s
        else
            SharedState.MobileScaleObjects[frame] = nil
        end
    end
end

local function MakeDraggable(handle, target, saveKey)
    local dragging, dragInput, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if Config.UILocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if saveKey then
                        local parentSize = target.Parent.AbsoluteSize
                        Config.Positions[saveKey] = {
                            X = target.AbsolutePosition.X / parentSize.X,
                            Y = target.AbsolutePosition.Y / parentSize.Y,
                        }
                        SaveConfig()
                    end
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function AddResizeHandle(frame, panelKey, posOverride)
    if not frame or not frame.Parent then return end
    if frame:FindFirstChild("__GlobalResizeHandle") then return end
    panelKey = panelKey or frame.Name or "Panel"

    local panelScale = frame:FindFirstChild("__PanelResizeScale")
    if not panelScale then
        panelScale = Instance.new("UIScale")
        panelScale.Name = "__PanelResizeScale"
        panelScale.Parent = frame
    end

    if type(Config.PanelScales) ~= "table" then Config.PanelScales = {} end
    local savedScale = tonumber(Config.PanelScales[panelKey]) or 1.0
    panelScale.Scale = math.clamp(savedScale, 0.5, 2.0)

    local handle = Instance.new("TextButton")
    handle.Name = "__GlobalResizeHandle"
    handle.Size = UDim2.new(0, 18, 0, 18)
    local autoPos = UDim2.new(1, -22, 0, 6)
    local _hdr = frame:FindFirstChildWhichIsA("Frame")
    if _hdr and _hdr:FindFirstChild("__MobileMinimize") then
        autoPos = UDim2.new(1, -52, 0, 6)
    end
    handle.Position = posOverride or autoPos
    handle.AnchorPoint = Vector2.new(0, 0)
    handle.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
    handle.BackgroundTransparency = 0.25
    handle.AutoButtonColor = false
    handle.Text = "+"
    handle.Font = Enum.Font.GothamBold
    handle.TextSize = 14
    handle.TextColor3 = Color3.fromRGB(255, 230, 240)
    handle.BorderSizePixel = 0
    handle.ZIndex = 100
    Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 4)
    local hStroke = Instance.new("UIStroke", handle)
    hStroke.Color = Color3.fromRGB(110, 116, 200); hStroke.Thickness = 1; hStroke.Transparency = 0.4
    handle.Parent = frame

    handle.MouseEnter:Connect(function() handle.BackgroundTransparency = 0.05; hStroke.Transparency = 0.1 end)
    handle.MouseLeave:Connect(function() handle.BackgroundTransparency = 0.25; hStroke.Transparency = 0.4 end)

    local dragging, startInputPos, startScale = false, nil, 1.0
    local moveConn, endConn
    local function clampScale(v) return math.clamp(v, 0.5, 2.0) end
    local function endDrag()
        if not dragging then return end
        dragging = false
        if moveConn then moveConn:Disconnect(); moveConn = nil end
        if endConn then endConn:Disconnect(); endConn = nil end
        if type(Config.PanelScales) ~= "table" then Config.PanelScales = {} end
        Config.PanelScales[panelKey] = panelScale.Scale
        pcall(SaveConfig)
    end
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
            and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        startInputPos = inp.Position
        startScale = panelScale.Scale or 1.0
        moveConn = UserInputService.InputChanged:Connect(function(mv)
            if not dragging then return end
            if mv.UserInputType ~= Enum.UserInputType.MouseMovement
                and mv.UserInputType ~= Enum.UserInputType.Touch then return end
            local dx = mv.Position.X - startInputPos.X
            local dy = mv.Position.Y - startInputPos.Y
            panelScale.Scale = clampScale(startScale + (dx + dy) / 400)
        end)
        endConn = UserInputService.InputEnded:Connect(function(en)
            if en.UserInputType == Enum.UserInputType.MouseButton1
                or en.UserInputType == Enum.UserInputType.Touch then
                endDrag()
            end
        end)
    end)
end

local function AddMobileMinimize(frame, labelText)
    if not IS_MOBILE then return end
    if not frame or not frame.Parent then return end
    local guiParent = frame.Parent
    local header = frame:FindFirstChildWhichIsA("Frame")
    if not header then return end

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "__MobileMinimize"
    minimizeBtn.Size = UDim2.new(0, 26, 0, 26)
    minimizeBtn.Position = UDim2.new(1, -30, 0, 6)
    minimizeBtn.BackgroundColor3 = Theme.SurfaceHighlight
    minimizeBtn.Text = "-"
    minimizeBtn.Font = Enum.Font.GothamBlack
    minimizeBtn.TextSize = 18
    minimizeBtn.TextColor3 = Theme.TextPrimary
    minimizeBtn.AutoButtonColor = false
    minimizeBtn.Parent = header
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 8)

    local restoreBtn = Instance.new("TextButton")
    restoreBtn.Size = UDim2.new(0, 110, 0, 34)
    restoreBtn.Position = UDim2.new(0, 10, 1, -44)
    restoreBtn.BackgroundColor3 = Theme.SurfaceHighlight
    restoreBtn.Text = labelText or "OPEN"
    restoreBtn.Font = Enum.Font.GothamBold
    restoreBtn.TextSize = 12
    restoreBtn.TextColor3 = Theme.TextPrimary
    restoreBtn.Visible = false
    restoreBtn.AutoButtonColor = false
    restoreBtn.Parent = guiParent
    Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 10)

    MakeDraggable(restoreBtn, restoreBtn)

    minimizeBtn.MouseButton1Click:Connect(function() frame.Visible = false; restoreBtn.Visible = true end)
    restoreBtn.MouseButton1Click:Connect(function()  frame.Visible = true;  restoreBtn.Visible = false end)
end

local function ShowNotification(title, text)
    local existing = PlayerGui:FindFirstChild("XiNotif")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui", PlayerGui)
    sg.Name = "XiNotif"; sg.ResetOnSpawn = false
    sg.DisplayOrder = 100000000

    local f = Instance.new("Frame", sg)
    f.Size = UDim2.new(0, 290, 0, 54)
    f.Position = UDim2.new(0.5, -145, 0, 80)
    f.BackgroundColor3 = Color3.fromRGB(20, 8, 18)
    f.BackgroundTransparency = 0.08
    f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 9)

    local stroke = Instance.new("UIStroke", f)
    stroke.Thickness = 1; stroke.Color = Theme.Accent2; stroke.Transparency = 0.3

    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(0, 3, 1, -12); bar.Position = UDim2.new(0, 5, 0, 6)
    bar.BackgroundColor3 = Theme.Accent1; bar.BorderSizePixel = 0
    bar.BackgroundTransparency = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local t1 = Instance.new("TextLabel", f)
    t1.Size = UDim2.new(1, -22, 0, 18); t1.Position = UDim2.new(0, 16, 0, 7)
    t1.BackgroundTransparency = 1; t1.Text = title:upper()
    t1.Font = Enum.Font.GothamBlack; t1.TextSize = 11
    t1.TextColor3 = Theme.Accent1; t1.TextXAlignment = Enum.TextXAlignment.Left
    t1.TextTransparency = 0

    local t2 = Instance.new("TextLabel", f)
    t2.Size = UDim2.new(1, -22, 0, 15); t2.Position = UDim2.new(0, 16, 0, 27)
    t2.BackgroundTransparency = 1; t2.Text = text
    t2.Font = Enum.Font.GothamMedium; t2.TextSize = 10
    t2.TextColor3 = Theme.TextSecondary; t2.TextXAlignment = Enum.TextXAlignment.Left
    t2.TextTransparency = 0

    local fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(f,      fadeIn, {BackgroundTransparency = 0.08}):Play()
    TweenService:Create(stroke, fadeIn, {Transparency = 0.3}):Play()
    TweenService:Create(bar,    fadeIn, {BackgroundTransparency = 0}):Play()
    TweenService:Create(t1,     fadeIn, {TextTransparency = 0}):Play()
    TweenService:Create(t2,     fadeIn, {TextTransparency = 0}):Play()

    task.delay(2, function()
        if not sg.Parent then return end
        local fadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(f,      fadeOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(stroke, fadeOut, {Transparency = 1}):Play()
        TweenService:Create(bar,    fadeOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(t1,     fadeOut, {TextTransparency = 1}):Play()
        local last = TweenService:Create(t2, fadeOut, {TextTransparency = 1})
        last:Play(); last.Completed:Wait()
        if sg.Parent then sg:Destroy() end
    end)
end

-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN PANEL — wrapped in top-level pcall so failures aren't silent
-- ════════════════════════════════════════════════════════════════════════════
task.spawn(function()
    local ok, err = pcall(function()
    task.wait(0.15)
    print("[chopper_hub Admin] building UI…")

    local COOLDOWNS = {
        rocket = 120, ragdoll = 30, balloon = 30, inverse = 60,
        nightvision = 60, jail = 60, tiny = 60, jumpscare = 60, morph = 60,
    }
    local ALL_COMMANDS = {
        "balloon", "inverse", "jail", "jumpscare", "morph",
        "nightvision", "ragdoll", "rocket", "tiny",
    }

    local activeCooldowns = {}
    SharedState.AdminButtonCache = {}

    local adminGui = Instance.new("ScreenGui")
    adminGui.Name = "XiAdminPanel"
    adminGui.ResetOnSpawn = false
    adminGui.DisplayOrder = 99999999
    adminGui.Parent = PlayerGui

    -- Visibility gated by the host script's "Admin Panel" toggle (Misc tab)
    adminGui.Enabled = (_G.MeerkoConfig and _G.MeerkoConfig.ShowAdminPanel) == true
    _G.MeerkoSetAdminPanel = function(on)
        if _G.MeerkoConfig then _G.MeerkoConfig.ShowAdminPanel = on and true or false end
        pcall(function() adminGui.Enabled = on and true or false end)
    end

    local frame = Instance.new("Frame")
    local mobileScale = IS_MOBILE and 0.65 or 1
    frame.Size = UDim2.new(0, 480*mobileScale, 0, 480*mobileScale)
    frame.Position = UDim2.new(Config.Positions.AdminPanel.X, 0, Config.Positions.AdminPanel.Y, 0)
    frame.BackgroundColor3 = Theme.Background
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = adminGui

    local listFrame, layout, blFrame, settingsFrame
    local createPlayerRow, removePlayer
    local rebuildBlList

    ApplyViewportUIScale(frame)
    AddMobileMinimize(frame, "ADMIN")
    AddResizeHandle(frame, "AdminPanel", UDim2.new(1, -107, 0, 6))

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Theme.Accent2; stroke.Thickness = 1.5; stroke.Transparency = 0.4
    CreateGradient(stroke)

    local header = Instance.new("Frame", frame)
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundTransparency = 1
    MakeDraggable(header, frame, "AdminPanel")

    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -100, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "chopper_hub"
    title.Font = Enum.Font.GothamBlack; title.TextSize = 16
    title.TextColor3 = Theme.Accent1
    title.TextXAlignment = Enum.TextXAlignment.Left

    local refreshBtn = Instance.new("TextButton", header)
    refreshBtn.Size = UDim2.new(0, 80, 0, 30)
    refreshBtn.Position = UDim2.new(1, -85, 0.5, -15)
    refreshBtn.BackgroundColor3 = Theme.SurfaceHighlight
    refreshBtn.Text = "REFRESH"
    refreshBtn.Font = Enum.Font.GothamBold; refreshBtn.TextSize = 12
    refreshBtn.TextColor3 = Theme.TextPrimary
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)
    local refreshStroke = Instance.new("UIStroke", refreshBtn)
    refreshStroke.Color = Theme.Accent2; refreshStroke.Thickness = 1; refreshStroke.Transparency = 0.3

    -- ── Prox / Spam-Owner / Click-AP toolbar ────────────────────────────────
    local proxCont = Instance.new("Frame", frame)
    proxCont.Size = UDim2.new(1, -20, 0, 44)
    proxCont.Position = UDim2.new(0, 10, 0, 58)
    proxCont.BackgroundColor3 = Color3.fromRGB(40, 43, 58)
    proxCont.BackgroundTransparency = 0.3
    Instance.new("UICorner", proxCont).CornerRadius = UDim.new(0, 10)
    local proxContStroke = Instance.new("UIStroke", proxCont)
    proxContStroke.Color = Theme.Accent2; proxContStroke.Thickness = 1; proxContStroke.Transparency = 0.6

    local function updateProximityAPButton()
        if SharedState.ProximityAPButton then
            SharedState.ProximityAPButton.BackgroundColor3 = ProximityAPActive and Theme.Accent1 or Color3.fromRGB(48, 52, 70)
            SharedState.ProximityAPButton.TextColor3 = ProximityAPActive and Color3.new(255,255,255) or Theme.TextPrimary
            if SharedState.ProximityAPButtonStroke then
                SharedState.ProximityAPButtonStroke.Color = ProximityAPActive and Theme.Accent2 or Color3.fromRGB(78, 84, 124)
            end
        end
    end

    local proxBtn = Instance.new("TextButton", proxCont)
    proxBtn.Name = "ProximityAPButton"
    proxBtn.Size = UDim2.new(0, 70, 0, 26)
    proxBtn.Position = UDim2.new(0, 6, 0.5, -13)
    proxBtn.BackgroundColor3 = ProximityAPActive and Theme.Accent1 or Color3.fromRGB(48, 52, 70)
    proxBtn.Text = "Prox"
    proxBtn.Font = Enum.Font.GothamBold; proxBtn.TextSize = 11
    proxBtn.TextColor3 = ProximityAPActive and Color3.new(255,255,255) or Theme.TextPrimary
    Instance.new("UICorner", proxBtn).CornerRadius = UDim.new(0, 6)
    local proxBtnStroke = Instance.new("UIStroke", proxBtn)
    proxBtnStroke.Color = ProximityAPActive and Theme.Accent2 or Color3.fromRGB(78, 84, 124)
    proxBtnStroke.Transparency = 0.3
    SharedState.ProximityAPButton = proxBtn
    SharedState.ProximityAPButtonStroke = proxBtnStroke
    SharedState.AdminProxBtn = proxBtn
    updateProximityAPButton()

    local spamBaseBtn = Instance.new("TextButton", proxCont)
    spamBaseBtn.Size = UDim2.new(0, 70, 0, 26)
    spamBaseBtn.Position = UDim2.new(0, 80, 0.5, -13)
    spamBaseBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
    spamBaseBtn.Text = "Spam Owner"
    spamBaseBtn.Font = Enum.Font.GothamBold; spamBaseBtn.TextSize = 9
    spamBaseBtn.TextColor3 = Theme.TextPrimary
    Instance.new("UICorner", spamBaseBtn).CornerRadius = UDim.new(0, 6)
    local spamBaseBtnStroke = Instance.new("UIStroke", spamBaseBtn)
    spamBaseBtnStroke.Color = Color3.fromRGB(78, 84, 124); spamBaseBtnStroke.Transparency = 0.3

    local ctapPanelBtn = Instance.new("TextButton", proxCont)
    ctapPanelBtn.Size = UDim2.new(0, 60, 0, 26)
    ctapPanelBtn.Position = UDim2.new(0, 154, 0.5, -13)
    ctapPanelBtn.AutoButtonColor = false
    ctapPanelBtn.Text = "Click AP"
    ctapPanelBtn.Font = Enum.Font.GothamBold; ctapPanelBtn.TextSize = 9
    ctapPanelBtn.BorderSizePixel = 0
    local function updateCtapPanelBtn()
        ctapPanelBtn.BackgroundColor3 = Config.ClickToAP and Theme.Accent1 or Color3.fromRGB(48, 52, 70)
        ctapPanelBtn.TextColor3      = Config.ClickToAP and Color3.new(0,0,0) or Theme.TextPrimary
    end
    updateCtapPanelBtn()
    Instance.new("UICorner", ctapPanelBtn).CornerRadius = UDim.new(0, 6)
    local ctapPanelStroke = Instance.new("UIStroke", ctapPanelBtn)
    ctapPanelStroke.Color = Color3.fromRGB(78, 84, 124); ctapPanelStroke.Transparency = 0.3
    ctapPanelBtn.MouseButton1Click:Connect(function()
        Config.ClickToAP = not Config.ClickToAP
        SaveConfig()
        updateCtapPanelBtn()
        ShowNotification("CLICK TO AP", Config.ClickToAP and "ON" or "DISABLED")
    end)

    spamBaseBtn.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then ShowNotification("SPAM OWNER", "No character found"); return end

        local nearestPlot, nearestDist = nil, math.huge
        local Plots = Workspace:FindFirstChild("Plots")
        if Plots then
            for _, plot in ipairs(Plots:GetChildren()) do
                local sign = plot:FindFirstChild("PlotSign")
                if sign then
                    local yourBase = sign:FindFirstChild("YourBase")
                    if not yourBase or not yourBase.Enabled then
                        local signPos = sign:IsA("BasePart") and sign.Position
                            or (sign.PrimaryPart and sign.PrimaryPart.Position)
                        if not signPos then
                            local part = sign:FindFirstChildWhichIsA("BasePart", true)
                            signPos = part and part.Position
                        end
                        if signPos then
                            local dist = (hrp.Position - signPos).Magnitude
                            if dist < nearestDist then nearestDist = dist; nearestPlot = plot end
                        end
                    end
                end
            end
        end
        if not nearestPlot then ShowNotification("SPAM OWNER", "No nearby base found"); return end

        local targetPlayer
        local okSync, Synchronizer = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
        end)
        if okSync and Synchronizer then
            local ok, ch = pcall(function() return Synchronizer:Get(nearestPlot.Name) end)
            if ok and ch then
                local owner = ch:Get("Owner")
                if owner then
                    if typeof(owner) == "Instance" and owner:IsA("Player") then
                        targetPlayer = owner
                    elseif type(owner) == "table" and owner.Name then
                        targetPlayer = Players:FindFirstChild(owner.Name)
                    end
                end
            end
        end
        if not targetPlayer then
            local sign = nearestPlot:FindFirstChild("PlotSign")
            local textLabel = sign and sign:FindFirstChild("SurfaceGui")
                and sign.SurfaceGui:FindFirstChild("Frame")
                and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
            if textLabel then
                local nickname = textLabel.Text and textLabel.Text:match("^(.-)'") or textLabel.Text
                if nickname then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.DisplayName == nickname or p.Name == nickname then
                            targetPlayer = p; break
                        end
                    end
                end
            end
        end
        if not targetPlayer or targetPlayer == LocalPlayer then
            ShowNotification("SPAM OWNER", "Owner not found or is you"); return
        end

        spamBaseBtn.BackgroundColor3 = Theme.Accent1
        spamBaseBtn.TextColor3 = Color3.new(1,1,1)
        ShowNotification("SPAM OWNER", "Spamming " .. targetPlayer.DisplayName)

        task.spawn(function()
            local cmds = {"balloon","inverse","jail","jumpscare","morph","nightvision","ragdoll","rocket","tiny"}
            local cmdCount = 0
            local adminFunc = _G.runAdminCommand
            if not adminFunc then task.wait(0.05); adminFunc = _G.runAdminCommand end
            if not adminFunc then
                spamBaseBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
                spamBaseBtn.TextColor3 = Theme.TextPrimary
                ShowNotification("SPAM OWNER", "Admin command not ready"); return
            end
            for _, cmd in ipairs(cmds) do
                local success, result = pcall(function() return adminFunc(targetPlayer, cmd) end)
                if success and result then cmdCount = cmdCount + 1 end
                task.wait(0.15)
            end
            task.wait(0.2)
            spamBaseBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
            spamBaseBtn.TextColor3 = Theme.TextPrimary
            ShowNotification("SPAM OWNER", "Sent " .. cmdCount .. " commands to " .. targetPlayer.DisplayName)
        end)
    end)

    local proxSliderBg = Instance.new("Frame", proxCont)
    proxSliderBg.Size = UDim2.new(0, 140, 0, 5)
    proxSliderBg.Position = UDim2.new(0, 220, 0.5, -2.5)
    proxSliderBg.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
    Instance.new("UICorner", proxSliderBg).CornerRadius = UDim.new(1,0)
    local proxFill = Instance.new("Frame", proxSliderBg)
    proxFill.BackgroundColor3 = Theme.Accent1; proxFill.Size = UDim2.new(0,0,1,0)
    Instance.new("UICorner", proxFill).CornerRadius = UDim.new(1,0)
    local proxKnob = Instance.new("Frame", proxSliderBg)
    proxKnob.Size = UDim2.new(0,12,0,12); proxKnob.BackgroundColor3 = Theme.TextPrimary
    proxKnob.AnchorPoint = Vector2.new(0.5, 0.5); proxKnob.Position = UDim2.new(0,0,0.5,0)
    Instance.new("UICorner", proxKnob).CornerRadius = UDim.new(1,0)
    local proxKnobStroke = Instance.new("UIStroke", proxKnob)
    proxKnobStroke.Color = Theme.Accent1; proxKnobStroke.Thickness = 1.5; proxKnobStroke.Transparency = 0.2

    local function updateProxSlider(val)
        local min, max = 5, 50
        val = math.clamp(val, min, max)
        Config.ProximityRange = val; SaveConfig()
        local pct = (val - min)/(max - min)
        proxFill.Size = UDim2.new(pct, 0, 1, 0)
        proxKnob.Position = UDim2.new(pct, 0, 0.5, 0)
    end
    updateProxSlider(Config.ProximityRange)

    local pDragging = false
    proxSliderBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            pDragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            pDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if pDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local r = proxSliderBg.AbsolutePosition.X
            local w = proxSliderBg.AbsoluteSize.X
            local p = (i.Position.X - r) / w
            updateProxSlider(5 + (p * 45))
        end
    end)

    local proxViz = nil
    local function updateProxViz()
        if ProximityAPActive then
            if not proxViz then
                proxViz = Instance.new("Part")
                proxViz.Name = "XiProxViz"
                proxViz.Anchored = true; proxViz.CanCollide = false
                proxViz.Shape = Enum.PartType.Cylinder
                proxViz.Color = Theme.Accent1; proxViz.Transparency = 0.6
                proxViz.CastShadow = false
                proxViz.Parent = Workspace
            end
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local hrp = char.HumanoidRootPart
                proxViz.Size = Vector3.new(0.5, Config.ProximityRange * 2, Config.ProximityRange * 2)
                proxViz.CFrame = hrp.CFrame * CFrame.Angles(0,0,math.rad(90)) + Vector3.new(0, -2.5, 0)
            end
        else
            if proxViz then proxViz:Destroy(); proxViz = nil end
        end
    end
    task.spawn(function() while true do task.wait(0.25); updateProxViz() end end)

    proxBtn.MouseButton1Click:Connect(function()
        ProximityAPActive = not ProximityAPActive
        Config.ProximityAPActive = ProximityAPActive
        SaveConfig()
        updateProximityAPButton()
        ShowNotification("PROXIMITY AP", ProximityAPActive and "ENABLED" or "DISABLED")
    end)

    -- ── Tab bar ─────────────────────────────────────────────────────────────
    local tabBar = Instance.new("Frame", frame)
    tabBar.Size = UDim2.new(1, -20, 0, 28)
    tabBar.Position = UDim2.new(0, 10, 0, 108)
    tabBar.BackgroundTransparency = 1; tabBar.BorderSizePixel = 0

    local tabBarLayout = Instance.new("UIListLayout", tabBar)
    tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
    tabBarLayout.Padding = UDim.new(0, 4)
    tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local function makeTabBtn(parent, label, order)
        local btn = Instance.new("TextButton", parent)
        btn.LayoutOrder = order
        btn.Size = UDim2.new(0, 110, 0, 24)
        btn.AutoButtonColor = false
        btn.Text = label
        btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
        btn.BorderSizePixel = 0
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", btn)
        s.Thickness = 1; s.Transparency = 0.4
        return btn, s
    end

    local tabPlayers,   tabPlayersStroke   = makeTabBtn(tabBar, "PLAYERS",   1)
    local tabBlacklist, tabBlacklistStroke = makeTabBtn(tabBar, "BLACKLIST", 2)
    local tabSettings,  tabSettingsStroke  = makeTabBtn(tabBar, "SETTINGS",  3)

    local activeTab = "players"
    local function setActiveTab(name)
        activeTab = name
        if name == "players" then
            tabPlayers.BackgroundColor3 = Theme.Accent1
            tabPlayers.TextColor3 = Color3.new(0,0,0)
            tabPlayersStroke.Color = Theme.Accent1
            tabBlacklist.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabBlacklist.TextColor3 = Theme.TextPrimary
            tabBlacklistStroke.Color = Color3.fromRGB(88, 94, 138)
            tabSettings.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabSettings.TextColor3 = Theme.TextPrimary
            tabSettingsStroke.Color = Color3.fromRGB(88, 94, 138)
            listFrame.Visible = true; blFrame.Visible = false; settingsFrame.Visible = false
        elseif name == "blacklist" then
            tabBlacklist.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
            tabBlacklist.TextColor3 = Color3.fromRGB(255, 210, 210)
            tabBlacklistStroke.Color = Color3.fromRGB(180, 50, 50)
            tabPlayers.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabPlayers.TextColor3 = Theme.TextPrimary
            tabPlayersStroke.Color = Color3.fromRGB(88, 94, 138)
            tabSettings.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabSettings.TextColor3 = Theme.TextPrimary
            tabSettingsStroke.Color = Color3.fromRGB(88, 94, 138)
            listFrame.Visible = false; blFrame.Visible = true; settingsFrame.Visible = false
        elseif name == "settings" then
            tabSettings.BackgroundColor3 = Theme.Accent1
            tabSettings.TextColor3 = Color3.new(0,0,0)
            tabSettingsStroke.Color = Theme.Accent1
            tabPlayers.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabPlayers.TextColor3 = Theme.TextPrimary
            tabPlayersStroke.Color = Color3.fromRGB(88, 94, 138)
            tabBlacklist.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
            tabBlacklist.TextColor3 = Theme.TextPrimary
            tabBlacklistStroke.Color = Color3.fromRGB(88, 94, 138)
            listFrame.Visible = false; blFrame.Visible = false; settingsFrame.Visible = true
        end
        if SharedState._RefreshAdminEmptyState then SharedState._RefreshAdminEmptyState() end
    end

    tabPlayers.MouseButton1Click:Connect(function() setActiveTab("players") end)
    tabBlacklist.MouseButton1Click:Connect(function() setActiveTab("blacklist") end)
    tabSettings.MouseButton1Click:Connect(function() setActiveTab("settings") end)

    -- ── Blacklist tab ───────────────────────────────────────────────────────
    blFrame = Instance.new("Frame", frame)
    blFrame.Size = UDim2.new(1, -20, 1, -144)
    blFrame.Position = UDim2.new(0, 10, 0, 142)
    blFrame.BackgroundTransparency = 1; blFrame.BorderSizePixel = 0
    blFrame.ZIndex = 5; blFrame.Active = true; blFrame.Visible = false

    local blInput = Instance.new("TextBox", blFrame)
    blInput.Size = UDim2.new(1, -58, 0, 26); blInput.Position = UDim2.new(0, 0, 0, 0)
    blInput.ZIndex = 6; blInput.BackgroundColor3 = Color3.fromRGB(22, 22, 28); blInput.BorderSizePixel = 0
    blInput.Text = ""; blInput.PlaceholderText = "Roblox username..."
    blInput.Font = Enum.Font.Gotham; blInput.TextSize = 11
    blInput.TextColor3 = Theme.TextPrimary; blInput.PlaceholderColor3 = Color3.fromRGB(80, 80, 95)
    blInput.ClearTextOnFocus = false
    Instance.new("UICorner", blInput).CornerRadius = UDim.new(0, 6)
    local blInputStroke = Instance.new("UIStroke", blInput)
    blInputStroke.Color = Color3.fromRGB(84, 90, 132); blInputStroke.Thickness = 1; blInputStroke.Transparency = 0.3
    local blInputPad = Instance.new("UIPadding", blInput); blInputPad.PaddingLeft = UDim.new(0, 8)

    local blAddBtn = Instance.new("TextButton", blFrame)
    blAddBtn.Size = UDim2.new(0, 50, 0, 26); blAddBtn.Position = UDim2.new(1, -50, 0, 0)
    blAddBtn.ZIndex = 6; blAddBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 35)
    blAddBtn.Text = "ADD"; blAddBtn.Font = Enum.Font.GothamBold; blAddBtn.TextSize = 11
    blAddBtn.TextColor3 = Color3.fromRGB(255, 200, 200); blAddBtn.AutoButtonColor = false
    Instance.new("UICorner", blAddBtn).CornerRadius = UDim.new(0, 6)
    local blAddStroke = Instance.new("UIStroke", blAddBtn)
    blAddStroke.Color = Color3.fromRGB(180, 50, 50); blAddStroke.Thickness = 1; blAddStroke.Transparency = 0.4

    local blListScroll = Instance.new("ScrollingFrame", blFrame)
    blListScroll.Size = UDim2.new(1, 0, 1, -34); blListScroll.Position = UDim2.new(0, 0, 0, 32)
    blListScroll.BackgroundTransparency = 1; blListScroll.BorderSizePixel = 0
    blListScroll.ScrollBarThickness = 4; blListScroll.ScrollBarImageColor3 = Color3.fromRGB(140, 40, 40)
    local blListLayout = Instance.new("UIListLayout", blListScroll)
    blListLayout.Padding = UDim.new(0, 4); blListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    blListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        blListScroll.CanvasSize = UDim2.new(0, 0, 0, blListLayout.AbsoluteContentSize.Y + 4)
    end)

    rebuildBlList = function()
        for _, c in ipairs(blListScroll:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        for i, name in ipairs(Config.BlacklistedUsers) do
            local row = Instance.new("Frame", blListScroll)
            row.LayoutOrder = i
            row.Size = UDim2.new(1, 0, 0, 28)
            row.BackgroundColor3 = Color3.fromRGB(43, 46, 60)
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
            local rowStroke = Instance.new("UIStroke", row)
            rowStroke.Color = Color3.fromRGB(80, 30, 30); rowStroke.Thickness = 1; rowStroke.Transparency = 0.5

            local nameLabel = Instance.new("TextLabel", row)
            nameLabel.Size = UDim2.new(1, -36, 1, 0); nameLabel.Position = UDim2.new(0, 10, 0, 0)
            nameLabel.BackgroundTransparency = 1; nameLabel.Text = name
            nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextSize = 11
            nameLabel.TextColor3 = Color3.fromRGB(230, 180, 180)
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left

            local removeBtn = Instance.new("TextButton", row)
            removeBtn.Size = UDim2.new(0, 26, 0, 20); removeBtn.Position = UDim2.new(1, -30, 0.5, -10)
            removeBtn.BackgroundColor3 = Color3.fromRGB(100, 25, 25)
            removeBtn.Text = "X"; removeBtn.Font = Enum.Font.GothamBold; removeBtn.TextSize = 10
            removeBtn.TextColor3 = Color3.fromRGB(255, 160, 160); removeBtn.AutoButtonColor = false
            Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)

            local capName = name
            removeBtn.MouseButton1Click:Connect(function()
                for j, n in ipairs(Config.BlacklistedUsers) do
                    if n:lower() == capName:lower() then
                        table.remove(Config.BlacklistedUsers, j); break
                    end
                end
                SaveConfig(); rebuildBlList()
                ShowNotification("BLACKLIST", "Removed " .. capName)
            end)
        end
        blListScroll.CanvasSize = UDim2.new(0, 0, 0, blListLayout.AbsoluteContentSize.Y + 4)
    end

    local function addBlacklistUser(username)
        username = username:match("^%s*(.-)%s*$")
        if username == "" then return end
        local lower = username:lower()
        for _, n in ipairs(Config.BlacklistedUsers) do
            if n:lower() == lower then
                ShowNotification("BLACKLIST", username .. " is already blacklisted"); return
            end
        end
        table.insert(Config.BlacklistedUsers, username)
        SaveConfig(); rebuildBlList(); blInput.Text = ""
        ShowNotification("BLACKLIST", "Blacklisted: " .. username)
    end

    blAddBtn.MouseButton1Click:Connect(function() addBlacklistUser(blInput.Text) end)
    blInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then addBlacklistUser(blInput.Text) end
    end)
    rebuildBlList()

    -- ── Settings tab ────────────────────────────────────────────────────────
    settingsFrame = Instance.new("ScrollingFrame", frame)
    settingsFrame.Size = UDim2.new(1, -20, 1, -144)
    settingsFrame.Position = UDim2.new(0, 10, 0, 142)
    settingsFrame.BackgroundTransparency = 1; settingsFrame.BorderSizePixel = 0
    settingsFrame.ScrollBarThickness = 4; settingsFrame.ScrollBarImageColor3 = Theme.Accent1
    settingsFrame.Visible = false
    settingsFrame.ZIndex = 5; settingsFrame.Active = true

    local settingsLayout = Instance.new("UIListLayout", settingsFrame)
    settingsLayout.Padding = UDim.new(0, 6); settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        settingsFrame.CanvasSize = UDim2.new(0, 0, 0, settingsLayout.AbsoluteContentSize.Y + 4)
    end)

    local function createToggleSwitch(parent, position, defaultState, callback)
        local switchFrame = Instance.new("TextButton")
        switchFrame.Position = position
        switchFrame.Size = UDim2.new(0, 36, 0, 18)
        switchFrame.BackgroundColor3 = defaultState and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(45, 45, 60)
        switchFrame.BackgroundTransparency = 0.2
        switchFrame.Text = ""
        switchFrame.ZIndex = parent.ZIndex + 1
        switchFrame.Parent = parent
        
        local sfuc = Instance.new("UICorner")
        sfuc.CornerRadius = UDim.new(1, 0)
        sfuc.Parent = switchFrame
        
        local sfstroke = Instance.new("UIStroke")
        sfstroke.Thickness = 1.2
        sfstroke.Color = defaultState and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(110, 116, 200)
        sfstroke.Transparency = defaultState and 0.4 or 0.7
        sfstroke.Parent = switchFrame
        
        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.Position = defaultState and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.ZIndex = switchFrame.ZIndex + 1
        knob.Parent = switchFrame
        
        local kuc = Instance.new("UICorner")
        kuc.CornerRadius = UDim.new(1, 0)
        kuc.Parent = knob
        
        local isToggled = defaultState
        
        local function updateVisuals(on)
            isToggled = on
            local targetColor = on and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(45, 45, 60)
            local targetKnobPos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
            local strokeColor = on and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(110, 116, 200)
            
            TweenService:Create(switchFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundColor3 = targetColor
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = targetKnobPos
            }):Play()
            TweenService:Create(sfstroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Color = strokeColor,
                Transparency = on and 0.4 or 0.7
            }):Play()
        end
        
        switchFrame.MouseButton1Click:Connect(function()
            isToggled = not isToggled
            updateVisuals(isToggled)
            callback(isToggled, switchFrame)
        end)
        
        switchFrame.MouseEnter:Connect(function()
            TweenService:Create(sfstroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 0.2,
                Color = isToggled and Color3.fromRGB(52, 211, 153) or Theme.Accent1
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 15, 0, 15)
            }):Play()
        end)
        switchFrame.MouseLeave:Connect(function()
            TweenService:Create(sfstroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = isToggled and 0.4 or 0.7,
                Color = isToggled and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(110, 116, 200)
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 14, 0, 14)
            }):Play()
        end)
        
        return switchFrame, updateVisuals
    end

    local function createSectionHeader(parent, text)
        local headerFrame = Instance.new("Frame", parent)
        headerFrame.Size = UDim2.new(1, -4, 0, 20)
        headerFrame.BackgroundTransparency = 1

        local lbl = Instance.new("TextLabel", headerFrame)
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Position = UDim2.new(0, 4, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text:upper()
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextSize = 10
        lbl.TextColor3 = Theme.Accent1
        lbl.TextXAlignment = Enum.TextXAlignment.Left

        return headerFrame
    end

    local function createSettingToggle(parent, text, description, configKey, callback)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, -4, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(28, 12, 24)
        row.BackgroundTransparency = 0.3
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = Color3.fromRGB(90, 30, 55)
        rowStroke.Thickness = 1
        rowStroke.Transparency = 0.5

        local textContainer = Instance.new("Frame", row)
        textContainer.Size = UDim2.new(1, -60, 1, 0)
        textContainer.Position = UDim2.new(0, 10, 0, 0)
        textContainer.BackgroundTransparency = 1

        local lbl = Instance.new("TextLabel", textContainer)
        lbl.Size = UDim2.new(1, 0, 0, 20)
        lbl.Position = UDim2.new(0, 0, 0.5, -16)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = Theme.TextPrimary
        lbl.TextXAlignment = Enum.TextXAlignment.Left

        local descLbl = Instance.new("TextLabel", textContainer)
        descLbl.Size = UDim2.new(1, 0, 0, 14)
        descLbl.Position = UDim2.new(0, 0, 0.5, 2)
        descLbl.BackgroundTransparency = 1
        descLbl.Text = description
        descLbl.Font = Enum.Font.GothamMedium
        descLbl.TextSize = 8
        descLbl.TextColor3 = Theme.TextSecondary
        descLbl.TextXAlignment = Enum.TextXAlignment.Left

        local isOn = Config[configKey]
        local switchFrame, updateSwitch = createToggleSwitch(row, UDim2.new(1, -44, 0.5, -9), isOn, function(state)
            Config[configKey] = state
            SaveConfig()
            if callback then callback(state) end
        end)

        row.MouseEnter:Connect(function()
            rowStroke.Color = Theme.Accent1
            rowStroke.Transparency = 0.2
        end)
        row.MouseLeave:Connect(function()
            rowStroke.Color = Color3.fromRGB(90, 30, 55)
            rowStroke.Transparency = 0.5
        end)

        return row
    end

    createSectionHeader(settingsFrame, "ESP tag settings")
    createSettingToggle(settingsFrame, "Show Moby ESP Tag", "Displays MOBY tag next to players using Moby", "MobyESPInAdminPanel")
    createSettingToggle(settingsFrame, "Show Kawaifu ESP Tag", "Displays KAWAIFU tag next to players using Kawaifu", "KawaifuESPInAdminPanel")
    createSettingToggle(settingsFrame, "Show Atlas ESP Tag", "Displays ATLAS tag next to players using Atlas", "AtlasESPInAdminPanel")
    createSettingToggle(settingsFrame, "Show Braintopia ESP Tag", "Displays BRAINTOPIA tag next to players using Braintopia", "BraintopiaESPInAdminPanel")
    createSettingToggle(settingsFrame, "Show WNotifier ESP Tag", "Displays WNOTIFIER tag next to players using WNotifier", "WNotifierESPInAdminPanel")

    createSectionHeader(settingsFrame, "Click-to-ap bypasses")
    createSettingToggle(settingsFrame, "Disable Click AP on Moby", "Bypasses Click-to-AP for Moby users", "DisableClickToAPOnMoby")
    createSettingToggle(settingsFrame, "Disable Click AP on Kawaifu", "Bypasses Click-to-AP for Kawaifu users", "DisableClickToAPOnKawaifu")
    createSettingToggle(settingsFrame, "Disable Click AP on Atlas", "Bypasses Click-to-AP for Atlas users", "DisableClickToAPOnAtlas")
    createSettingToggle(settingsFrame, "Disable Click AP on Braintopia", "Bypasses Click-to-AP for Braintopia users", "DisableClickToAPOnBraintopia")
    createSettingToggle(settingsFrame, "Disable Click AP on WNotifier", "Bypasses Click-to-AP for WNotifier users", "DisableClickToAPOnWNotifier")

    createSectionHeader(settingsFrame, "Proximity ap bypasses")
    createSettingToggle(settingsFrame, "Disable Prox AP on Moby", "Bypasses Proximity AP for Moby users", "DisableProximitySpamOnMoby")
    createSettingToggle(settingsFrame, "Disable Prox AP on Kawaifu", "Bypasses Proximity AP for Kawaifu users", "DisableProximitySpamOnKawaifu")
    createSettingToggle(settingsFrame, "Disable Prox AP on Atlas", "Bypasses Proximity AP for Atlas users", "DisableProximitySpamOnAtlas")
    createSettingToggle(settingsFrame, "Disable Prox AP on Braintopia", "Bypasses Proximity AP for Braintopia users", "DisableProximitySpamOnBraintopia")
    createSettingToggle(settingsFrame, "Disable Prox AP on WNotifier", "Bypasses Proximity AP for WNotifier users", "DisableProximitySpamOnWNotifier")

    createSectionHeader(settingsFrame, "AP Panel button bypasses")
    createSettingToggle(settingsFrame, "Disable AP Panel on Moby", "Blocks manual AP buttons for Moby users", "DisableAPPanelOnMoby")
    createSettingToggle(settingsFrame, "Disable AP Panel on Kawaifu", "Blocks manual AP buttons for Kawaifu users", "DisableAPPanelOnKawaifu")
    createSettingToggle(settingsFrame, "Disable AP Panel on Atlas", "Blocks manual AP buttons for Atlas users", "DisableAPPanelOnAtlas")
    createSettingToggle(settingsFrame, "Disable AP Panel on Braintopia", "Blocks manual AP buttons for Braintopia users", "DisableAPPanelOnBraintopia")
    createSettingToggle(settingsFrame, "Disable AP Panel on WNotifier", "Blocks manual AP buttons for WNotifier users", "DisableAPPanelOnWNotifier")

    createSectionHeader(settingsFrame, "General settings")
    createSettingToggle(settingsFrame, "Proximity AP Active", "Runs AP commands on nearby players", "ProximityAPActive", function(state)
        ProximityAPActive = state
        updateProximityAPButton()
    end)
    createSettingToggle(settingsFrame, "Hide Kawaifu From Panel", "Removes Kawaifu users from the admin list", "HideKawaifuFromPanel")
    createSettingToggle(settingsFrame, "Single Command Click AP", "Sends only one command per click instead of all", "ClickToAPSingleCommand")

    -- Tool input row
    local toolRow = Instance.new("Frame", settingsFrame)
    toolRow.Size = UDim2.new(1, -4, 0, 36)
    toolRow.BackgroundColor3 = Color3.fromRGB(28, 12, 24)
    toolRow.BackgroundTransparency = 0.3
    toolRow.BorderSizePixel = 0
    Instance.new("UICorner", toolRow).CornerRadius = UDim.new(0, 8)
    local toolRowStroke = Instance.new("UIStroke", toolRow)
    toolRowStroke.Color = Color3.fromRGB(90, 30, 55); toolRowStroke.Thickness = 1; toolRowStroke.Transparency = 0.5

    local toolLbl = Instance.new("TextLabel", toolRow)
    toolLbl.Size = UDim2.new(0, 120, 1, 0); toolLbl.Position = UDim2.new(0, 10, 0, 0)
    toolLbl.BackgroundTransparency = 1; toolLbl.Text = "TP Tool Name"
    toolLbl.Font = Enum.Font.GothamBold; toolLbl.TextSize = 11; toolLbl.TextColor3 = Theme.TextPrimary
    toolLbl.TextXAlignment = Enum.TextXAlignment.Left

    local toolInput = Instance.new("TextBox", toolRow)
    toolInput.Size = UDim2.new(1, -140, 0, 24); toolInput.Position = UDim2.new(0, 130, 0.5, -12)
    toolInput.BackgroundColor3 = Color3.fromRGB(22, 22, 28); toolInput.BorderSizePixel = 0
    toolInput.Text = Config.TpSettings.Tool
    toolInput.Font = Enum.Font.Gotham; toolInput.TextSize = 11; toolInput.TextColor3 = Theme.TextPrimary
    Instance.new("UICorner", toolInput).CornerRadius = UDim.new(0, 6)
    local toolInputStroke = Instance.new("UIStroke", toolInput)
    toolInputStroke.Color = Color3.fromRGB(84, 90, 132); toolInputStroke.Thickness = 1; toolInputStroke.Transparency = 0.3
    
    toolInput.FocusLost:Connect(function()
        local txt = toolInput.Text:match("^%s*(.-)%s*$")
        if txt ~= "" then
            Config.TpSettings.Tool = txt
            SaveConfig()
            ShowNotification("TP TOOL", "Set tool to: " .. txt)
        else
            toolInput.Text = Config.TpSettings.Tool
        end
    end)

    -- ── Player list ─────────────────────────────────────────────────────────
    listFrame = Instance.new("ScrollingFrame", frame)
    listFrame.Size = UDim2.new(1, -20, 1, -144)
    listFrame.Position = UDim2.new(0, 10, 0, 142)
    listFrame.BackgroundTransparency = 1; listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 5; listFrame.ScrollBarImageColor3 = Theme.Accent1
    layout = Instance.new("UIListLayout", listFrame)
    layout.Padding = UDim.new(0, 10); layout.SortOrder = Enum.SortOrder.LayoutOrder

    local playerRows = {}
    local playerRowsByUserId = {}

    local emptyPlayersLbl = Instance.new("TextLabel")
    emptyPlayersLbl.Name = "_EmptyPlayersLabel"
    emptyPlayersLbl.Size = UDim2.new(1, -20, 0, 24)
    emptyPlayersLbl.Position = UDim2.new(0, 10, 0, 154)
    emptyPlayersLbl.BackgroundTransparency = 1
    emptyPlayersLbl.Text = "No players found"
    emptyPlayersLbl.Font = Enum.Font.GothamMedium; emptyPlayersLbl.TextSize = 11
    emptyPlayersLbl.TextColor3 = Color3.fromRGB(170, 80, 110)
    emptyPlayersLbl.TextXAlignment = Enum.TextXAlignment.Center
    emptyPlayersLbl.Visible = false; emptyPlayersLbl.ZIndex = 5
    emptyPlayersLbl.Parent = frame

    local function refreshEmptyPlayersState()
        if not listFrame.Visible then emptyPlayersLbl.Visible = false; return end
        local hasAny = false
        for _, r in pairs(playerRows) do
            if r and r.Parent then hasAny = true; break end
        end
        emptyPlayersLbl.Visible = not hasAny
    end
    SharedState._RefreshAdminEmptyState = refreshEmptyPlayersState

    setActiveTab("players")

    local function getAdminPanelSortKey(plr)
        if not plr or not plr.Parent then return 3, 9999, "" end
        local stealing = plr:GetAttribute("Stealing")
        local brainrotName = plr:GetAttribute("StealingIndex")
        if not stealing then return 3, 9999, plr.Name or "" end
        if brainrotName then
            for i, pName in ipairs(PRIORITY_LIST) do
                if pName == brainrotName then return 1, i, plr.Name or "" end
            end
            return 2, 9999, plr.Name or ""
        end
        return 2, 9999, plr.Name or ""
    end

    local function sortAdminPanelList()
        local rows = {}
        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") and child.Name ~= "" then
                local plr = Players:FindFirstChild(child.Name)
                if plr then table.insert(rows, {row = child, plr = plr}) end
            end
        end
        table.sort(rows, function(a, b)
            local t1, p1, n1 = getAdminPanelSortKey(a.plr)
            local t2, p2, n2 = getAdminPanelSortKey(b.plr)
            if t1 ~= t2 then return t1 < t2 end
            if p1 ~= p2 then return p1 < p2 end
            return (n1 or "") < (n2 or "")
        end)
        for i, entry in ipairs(rows) do entry.row.LayoutOrder = i end
    end

    local function fireClick(button)
        if not button then return end
        if firesignal then
            firesignal(button.MouseButton1Click)
            firesignal(button.MouseButton1Down)
            firesignal(button.Activated)
        else
            local x = button.AbsolutePosition.X + (button.AbsoluteSize.X / 2)
            local y = button.AbsolutePosition.Y + (button.AbsoluteSize.Y / 2) + 58
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true,  game, 0)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end
    end
    _G.fireClick = fireClick

    local function runAdminCommand(targetPlayer, commandName)
        if isBlacklisted(targetPlayer) then return false end
        local realAdminGui = PlayerGui:WaitForChild("AdminPanel", 5)
        if not realAdminGui then return false end
        local contentScroll = realAdminGui.AdminPanel:WaitForChild("Content"):WaitForChild("ScrollingFrame")
        local cmdBtn = contentScroll:FindFirstChild(commandName)
        if not cmdBtn then return false end
        fireClick(cmdBtn)
        task.wait(0.05)
        local profilesScroll = realAdminGui:WaitForChild("AdminPanel"):WaitForChild("Profiles"):WaitForChild("ScrollingFrame")
        local playerBtn = profilesScroll:FindFirstChild(targetPlayer.Name)
        if not playerBtn then return false end
        fireClick(playerBtn)
        return true
    end
    _G.runAdminCommand = runAdminCommand

    local isOnCooldown
    local function getNextAvailableCommand()
        local priorityCommands = {"ragdoll", "balloon", "rocket", "jail"}
        local otherCommands = {}
        for _, cmd in ipairs(ALL_COMMANDS) do
            local isPriority = false
            for _, pc in ipairs(priorityCommands) do if cmd == pc then isPriority = true; break end end
            if not isPriority then table.insert(otherCommands, cmd) end
        end
        for _, cmd in ipairs(priorityCommands) do if not isOnCooldown(cmd) then return cmd end end
        for _, cmd in ipairs(otherCommands)    do if not isOnCooldown(cmd) then return cmd end end
        return nil
    end

    isOnCooldown = function(cmd)
        local realAdminGui = PlayerGui:FindFirstChild("AdminPanel")
        if realAdminGui then
            local content = realAdminGui:FindFirstChild("AdminPanel")
            if content then
                local scrollFrame = content:FindFirstChild("Content")
                if scrollFrame then
                    local scrollingFrame = scrollFrame:FindFirstChild("ScrollingFrame")
                    if scrollingFrame then
                        local cmdButton = scrollingFrame:FindFirstChild(cmd)
                        if cmdButton then
                            local timerLabel = cmdButton:FindFirstChild("Timer")
                            if timerLabel then return timerLabel.Visible end
                        end
                    end
                end
            end
        end
        if not activeCooldowns[cmd] then return false end
        return (tick() - activeCooldowns[cmd]) < (COOLDOWNS[cmd] or 0)
    end

    local function setGlobalVisualCooldown(cmd)
        if SharedState.AdminButtonCache[cmd] then
            for _, b in ipairs(SharedState.AdminButtonCache[cmd]) do
                if b and b.Parent then
                    b.BackgroundColor3 = Theme.Error
                    task.delay(COOLDOWNS[cmd] or 5, function()
                        if b and b.Parent then
                            local hasBallooned = (cmd == "balloon"
                                and SharedState.BalloonedPlayers
                                and next(SharedState.BalloonedPlayers) ~= nil)
                            b.BackgroundColor3 = hasBallooned and Theme.Error or Theme.SurfaceHighlight
                        end
                    end)
                end
            end
        end
    end

    local function updateBalloonButtons()
        local hasBallooned = false
        for _, _ in pairs(SharedState.BalloonedPlayers) do hasBallooned = true; break end
        if SharedState.AdminButtonCache and SharedState.AdminButtonCache["balloon"] then
            for _, b in ipairs(SharedState.AdminButtonCache["balloon"]) do
                if b and b.Parent then
                    b.BackgroundColor3 = hasBallooned and Theme.Error or Theme.SurfaceHighlight
                end
            end
        end
    end

    local function triggerAll(plr)
        if isBlacklisted(plr) then return end
        local count = 0
        for _, cmd in ipairs(ALL_COMMANDS) do
            if not isOnCooldown(cmd) then
                task.delay(count * 0.1, function()
                    if runAdminCommand(plr, cmd) then
                        activeCooldowns[cmd] = tick()
                        setGlobalVisualCooldown(cmd)
                        if cmd == "balloon" then
                            SharedState.BalloonedPlayers[plr.UserId] = true
                            updateBalloonButtons()
                        end
                    end
                end)
                count = count + 1
            end
        end
    end

    local function rayToCubeIntersect(rayOrigin, rayDirection, cubeCenter, cubeSize)
        local halfSize = cubeSize / 2
        local minBounds = cubeCenter - Vector3.new(halfSize, halfSize, halfSize)
        local maxBounds = cubeCenter + Vector3.new(halfSize, halfSize, halfSize)
        if rayDirection.X == 0 then rayDirection = Vector3.new(0.0001, rayDirection.Y, rayDirection.Z) end
        if rayDirection.Y == 0 then rayDirection = Vector3.new(rayDirection.X, 0.0001, rayDirection.Z) end
        if rayDirection.Z == 0 then rayDirection = Vector3.new(rayDirection.X, rayDirection.Y, 0.0001) end
        local tmin = (minBounds.X - rayOrigin.X) / rayDirection.X
        local tmax = (maxBounds.X - rayOrigin.X) / rayDirection.X
        if tmin > tmax then tmin, tmax = tmax, tmin end
        local tymin = (minBounds.Y - rayOrigin.Y) / rayDirection.Y
        local tymax = (maxBounds.Y - rayOrigin.Y) / rayDirection.Y
        if tymin > tymax then tymin, tymax = tymax, tymin end
        if tmin > tymax or tymin > tmax then return false end
        if tymin > tmin then tmin = tymin end
        if tymax < tmax then tmax = tymax end
        local tzmin = (minBounds.Z - rayOrigin.Z) / rayDirection.Z
        local tzmax = (maxBounds.Z - rayOrigin.Z) / rayDirection.Z
        if tzmin > tzmax then tzmin, tzmax = tzmax, tzmin end
        if tmin > tzmax or tzmin > tmax then return false end
        return true
    end

    -- ── Click-to-AP highlight (CoreGui pcall'd; some executors block it) ────
    local highlight
    pcall(function()
        highlight = Instance.new("Highlight", game:GetService("CoreGui"))
        highlight.FillColor = Color3.fromRGB(255, 50, 50)
        highlight.FillTransparency = 0.3
        highlight.OutlineColor = Color3.fromRGB(255, 50, 50)
        highlight.OutlineTransparency = 0
        highlight.Adornee = nil
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end)
    if not highlight then
        warn("[chopper_hub Admin] CoreGui blocked; click-to-AP target highlight disabled")
    end

    local _ctapFrame = 0
    RunService.RenderStepped:Connect(function()
        _ctapFrame = _ctapFrame + 1
        if _ctapFrame < 12 then return end
        _ctapFrame = 0
        if Config.ClickToAP then
            local camera   = Workspace.CurrentCamera
            local mousePos = UserInputService:GetMouseLocation()
            local ray      = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
            local hitboxSize = 8
            local bestPlayer, bestDistance = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Parent then
                    local hrp = p.Character.HumanoidRootPart
                    if rayToCubeIntersect(ray.Origin, ray.Direction, hrp.Position, hitboxSize) then
                        local distance = (ray.Origin - hrp.Position).Magnitude
                        if distance < bestDistance then bestDistance = distance; bestPlayer = p end
                    end
                end
            end
            local newAdornee = bestPlayer and bestPlayer.Character or nil
            if highlight and highlight.Adornee ~= newAdornee then
                highlight.Adornee = newAdornee
                for _, child in ipairs(listFrame:GetChildren()) do
                    if child:IsA("TextButton") then
                        local s = child:FindFirstChildOfClass("UIStroke")
                        if s then
                            local hoveredName = newAdornee and newAdornee.Parent
                                and Players:GetPlayerFromCharacter(newAdornee.Parent)
                                and Players:GetPlayerFromCharacter(newAdornee.Parent).Name or ""
                            if newAdornee and child.Name == hoveredName then
                                s.Color = Color3.fromRGB(255, 50, 50)
                                s.Transparency = 0
                                child.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
                            else
                                s.Color = Theme.Accent2
                                s.Transparency = 0.7
                                child.BackgroundColor3 = Color3.fromRGB(40, 43, 58)
                            end
                        end
                    end
                end
            end
        else
            if highlight then highlight.Adornee = nil end
        end
    end)

    UserInputService.InputBegan:Connect(function(inp, g)
        if not g and inp.UserInputType == Enum.UserInputType.MouseButton1 and Config.ClickToAP then
            local camera   = Workspace.CurrentCamera
            local mousePos = UserInputService:GetMouseLocation()
            local ray      = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
            local hitboxSize = 8
            local bestPlayer, bestDistance = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Parent then
                    local hrp = p.Character.HumanoidRootPart
                    if rayToCubeIntersect(ray.Origin, ray.Direction, hrp.Position, hitboxSize) then
                        local distance = (ray.Origin - hrp.Position).Magnitude
                        if distance < bestDistance then bestDistance = distance; bestPlayer = p end
                    end
                end
            end
            if bestPlayer then
                if isBlacklisted(bestPlayer) then
                    ShowNotification("CLICK TO AP", bestPlayer.Name .. " is blacklisted"); return
                end
                if Config.DisableClickToAPOnMoby and isMobyUser(bestPlayer) then
                    ShowNotification("CLICK TO AP", "Disabled on Moby users"); return
                end
                if Config.DisableClickToAPOnKawaifu and isKawaifuUser(bestPlayer) then
                    ShowNotification("CLICK TO AP", "Disabled on Kawaifu users"); return
                end
                if Config.DisableClickToAPOnAtlas and isAtlasUser(bestPlayer) then
                    ShowNotification("CLICK TO AP", "Disabled on Atlas users"); return
                end
                if Config.DisableClickToAPOnBraintopia and isBraintopiaUser(bestPlayer) then
                    ShowNotification("CLICK TO AP", "Disabled on Braintopia users"); return
                end
                if Config.DisableClickToAPOnWNotifier and isWNotifierUser(bestPlayer) then
                    ShowNotification("CLICK TO AP", "Disabled on WNotifier users"); return
                end

                local hasAnyAvailable = false
                for _, cmd in ipairs(ALL_COMMANDS) do
                    if not isOnCooldown(cmd) then hasAnyAvailable = true; break end
                end
                if hasAnyAvailable then
                    if Config.ClickToAPSingleCommand then
                        local nextCmd = getNextAvailableCommand()
                        if nextCmd then
                            if runAdminCommand(bestPlayer, nextCmd) then
                                activeCooldowns[nextCmd] = tick()
                                setGlobalVisualCooldown(nextCmd)
                                if nextCmd == "balloon" then
                                    SharedState.BalloonedPlayers[bestPlayer.UserId] = true
                                    updateBalloonButtons()
                                end
                                ShowNotification("CLICK AP", "Sent " .. nextCmd .. " to " .. bestPlayer.Name)
                            else
                                ShowNotification("CLICK AP", "Failed to send " .. nextCmd .. " to " .. bestPlayer.Name)
                            end
                        else
                            ShowNotification("CLICK AP", "All commands on cooldown")
                        end
                    else
                        triggerAll(bestPlayer)
                        ShowNotification("CLICK AP", "Triggered on " .. bestPlayer.Name)
                    end
                else
                    local realAdminGui = PlayerGui:WaitForChild("AdminPanel", 5)
                    if realAdminGui then
                        local profilesScroll = realAdminGui:WaitForChild("AdminPanel"):WaitForChild("Profiles"):WaitForChild("ScrollingFrame")
                        local playerBtn = profilesScroll:FindFirstChild(bestPlayer.Name)
                        if playerBtn then
                            fireClick(playerBtn)
                            ShowNotification("CLICK AP", "Selected " .. bestPlayer.Name)
                        end
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)
            if ProximityAPActive then
                local myChar = LocalPlayer.Character
                if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                            local dist = (p.Character.HumanoidRootPart.Position - myChar.HumanoidRootPart.Position).Magnitude
                            if dist <= Config.ProximityRange then
                                if isBlacklisted(p)
                                    or (Config.DisableProximitySpamOnMoby    and isMobyUser(p))
                                    or (Config.DisableProximitySpamOnKawaifu and isKawaifuUser(p))
                                    or (Config.DisableProximitySpamOnAtlas   and isAtlasUser(p))
                                    or (Config.DisableProximitySpamOnBraintopia and isBraintopiaUser(p))
                                    or (Config.DisableProximitySpamOnWNotifier and isWNotifierUser(p)) then
                                else
                                    local hasAnyAvailable = false
                                    for _, cmd in ipairs(ALL_COMMANDS) do
                                        if not isOnCooldown(cmd) then hasAnyAvailable = true; break end
                                    end
                                    if hasAnyAvailable then triggerAll(p) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- ── Player row factory ──────────────────────────────────────────────────
    createPlayerRow = function(plr)
        local row = Instance.new("TextButton")
        row.Name = plr.Name; row.LayoutOrder = 0
        row.Size = UDim2.new(1, -4, 0, 74)
        row.BackgroundColor3 = Color3.fromRGB(40, 43, 58)
        row.BackgroundTransparency = 0.2; row.BorderSizePixel = 0
        row.AutoButtonColor = false; row.Text = ""
        row.Parent = listFrame
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = Theme.Accent2; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.7

        row.MouseEnter:Connect(function()
            row.BackgroundTransparency = 0.05; rowStroke.Transparency = 0.4; rowStroke.Color = Theme.Accent1
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundTransparency = 0.2;  rowStroke.Transparency = 0.7; rowStroke.Color = Theme.Accent2
        end)

        local headshot = Instance.new("ImageLabel", row)
        headshot.Size = UDim2.new(0, 42, 0, 42); headshot.Position = UDim2.new(0, 12, 0.5, -21)
        headshot.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
        headshot.Image = Players:GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        Instance.new("UICorner", headshot).CornerRadius = UDim.new(1, 0)
        local headshotStroke = Instance.new("UIStroke", headshot)
        headshotStroke.Color = Theme.Accent1; headshotStroke.Thickness = 2.5; headshotStroke.Transparency = 0.2

        local dName = Instance.new("TextLabel", row)
        dName.Size = UDim2.new(0, 160, 0, 20); dName.Position = UDim2.new(0, 58, 0, 10)
        dName.BackgroundTransparency = 1; dName.Text = plr.Name
        dName.Font = Enum.Font.GothamBold; dName.TextSize = 14
        dName.TextColor3 = Theme.TextPrimary; dName.TextXAlignment = Enum.TextXAlignment.Left

        local uName = Instance.new("TextLabel", row)
        uName.Size = UDim2.new(0, 160, 0, 16); uName.Position = UDim2.new(0, 58, 0, 30)
        uName.BackgroundTransparency = 1; uName.Text = plr.DisplayName
        uName.Font = Enum.Font.GothamBold; uName.TextSize = 10
        uName.TextColor3 = Color3.fromRGB(210, 210, 210); uName.TextXAlignment = Enum.TextXAlignment.Left

        local apToolLbl = Instance.new("TextLabel", row)
        apToolLbl.Name = "APToolLabel"
        apToolLbl.Size = UDim2.new(0, 160, 0, 14); apToolLbl.Position = UDim2.new(0, 58, 0, 44)
        apToolLbl.BackgroundTransparency = 1
        apToolLbl.Font = Enum.Font.GothamMedium; apToolLbl.TextSize = 10
        apToolLbl.TextColor3 = Color3.fromRGB(100, 210, 255); apToolLbl.TextXAlignment = Enum.TextXAlignment.Left

        local function makeHubTag(name, text, bg, width)
            local t = Instance.new("TextLabel", row)
            t.Name = "UserTag_" .. name
            t.BackgroundColor3 = bg; t.BorderSizePixel = 0
            t.Size = UDim2.fromOffset(width, 16)
            t.Position = UDim2.fromOffset(58 + 90 + 6, 11)
            t.Text = text
            t.Font = Enum.Font.GothamBold; t.TextSize = 9
            t.TextColor3 = Color3.fromRGB(255, 255, 255)
            t.TextXAlignment = Enum.TextXAlignment.Center
            t.ZIndex = 11; t.Visible = false
            Instance.new("UICorner", t).CornerRadius = UDim.new(0, 5)
            return t
        end
        local mobyTag       = makeHubTag("MOBY",       "MOBY",       Color3.fromRGB(68, 136, 255),  38)
        local kawaifuTag    = makeHubTag("KAWAIFU",    "KAWAIFU",    Color3.fromRGB(255, 105, 180), 50)
        local atlasTag      = makeHubTag("ATLAS",      "ATLAS",      Color3.fromRGB(255, 215, 0),   42)
        local braintopiaTag = makeHubTag("BRAINTOPIA", "BRAINTOPIA", Color3.fromRGB(170, 100, 255), 66)
        local wnotifierTag  = makeHubTag("WNOTIFIER",  "WNOTIFIER",  Color3.fromRGB(16, 185, 129),  68)

        local function updateHubTags()
            local entries = {
                { tag = mobyTag,       cfg = Config.MobyESPInAdminPanel,       show = function() local r=false; pcall(function() r=isMobyUser(plr)==true end); return r end },
                { tag = kawaifuTag,    cfg = Config.KawaifuESPInAdminPanel,    show = function() local r=false; pcall(function() r=isKawaifuUser(plr)==true end); return r end },
                { tag = atlasTag,      cfg = Config.AtlasESPInAdminPanel,      show = function() local r=false; pcall(function() r=isAtlasUser(plr)==true end); return r end },
                { tag = braintopiaTag, cfg = Config.BraintopiaESPInAdminPanel, show = function() local r=false; pcall(function() r=isBraintopiaUser(plr)==true end); return r end },
                { tag = wnotifierTag,  cfg = Config.WNotifierESPInAdminPanel,  show = function() local r=false; pcall(function() r=isWNotifierUser(plr)==true end); return r end },
            }
            local textW = dName.TextBounds.X
            if not textW or textW <= 0 then textW = 90 end
            local cursor = 58 + math.floor(textW) + 6
            for _, e in ipairs(entries) do
                if e.cfg and e.show() then
                    e.tag.Position = UDim2.fromOffset(cursor, 11)
                    e.tag.Visible = true
                    cursor = cursor + e.tag.Size.X.Offset + 4
                else
                    e.tag.Visible = false
                end
            end
        end
        updateHubTags()
        task.spawn(function()
            while row.Parent do
                task.wait(1)
                if not plr or not plr.Parent then break end
                updateHubTags()
            end
        end)

        do
            local ht = nil
            local c = plr.Character
            if c then for _, o in ipairs(c:GetChildren()) do if o:IsA("Tool") then ht = o.Name; break end end end
            apToolLbl.Text = ht or ""
            if ht and DANGER_TOOLS[ht] then dName.TextColor3 = Color3.fromRGB(255, 60, 60) end
        end

        local nearestBrainrotName = plr:GetAttribute("StealingIndex")
        if plr:GetAttribute("Stealing") then
            if nearestBrainrotName then
                uName.Text = nearestBrainrotName
                uName.TextColor3 = Color3.fromRGB(255, 200, 0)
                uName.Font = Enum.Font.GothamBlack; uName.TextSize = 14
            else
                uName.Text = "STEALING"
                uName.TextColor3 = Color3.fromRGB(255, 150, 0)
                uName.Font = Enum.Font.GothamBlack; uName.TextSize = 14
            end
        end

        task.spawn(function()
            while row.Parent do
                task.wait(0.5)
                if not plr or not plr.Parent or not Players:FindFirstChild(plr.Name) then
                    removePlayer(plr); break
                end
                local stealing = plr:GetAttribute("Stealing")
                nearestBrainrotName = plr:GetAttribute("StealingIndex")
                if stealing then
                    if nearestBrainrotName then
                        uName.Text = nearestBrainrotName
                        uName.TextColor3 = Color3.fromRGB(255, 200, 0)
                        uName.Font = Enum.Font.GothamBold; uName.TextSize = 11
                    else
                        uName.Text = "STEALING"
                        uName.TextColor3 = Color3.fromRGB(255, 150, 0)
                        uName.Font = Enum.Font.GothamBold; uName.TextSize = 11
                    end
                else
                    uName.Text = "(@" .. plr.Name .. ")"
                    uName.TextColor3 = Theme.TextSecondary
                    uName.Font = Enum.Font.GothamMedium; uName.TextSize = 7
                    nearestBrainrotName = nil
                end
                pcall(function()
                    local ht = nil
                    local c = plr.Character
                    if c then for _, o in ipairs(c:GetChildren()) do if o:IsA("Tool") then ht = o.Name; break end end end
                    apToolLbl.Text = ht or ""
                    if ht and DANGER_TOOLS[ht] then
                        dName.TextColor3 = Color3.fromRGB(255, 60, 60)
                    else
                        dName.TextColor3 = Theme.TextPrimary
                    end
                end)
            end
        end)

        -- ── AP command buttons — TEXT LABELS (emojis showed as "???") ───────
        local btnCont = Instance.new("Frame", row)
        btnCont.Size = UDim2.new(0, 220, 1, 0); btnCont.Position = UDim2.new(1, -225, 0, 0)
        btnCont.BackgroundTransparency = 1; btnCont.ZIndex = 10

        local buttonsDef = {
            {icon = "RKT",  cmd = "rocket"},
            {icon = "RAG",  cmd = "ragdoll"},
            {icon = "JAIL", cmd = "jail"},
            {icon = "BAL",  cmd = "balloon"},
        }

        for i, def in ipairs(buttonsDef) do
            local b = Instance.new("TextButton", btnCont)
            b.Size = UDim2.new(0, 30, 0, 30)
            b.Position = UDim2.new(0, 4 + (i-1)*34, 0.5, -15)
            b.AutoButtonColor = false
            b.Text = def.icon; b.TextSize = 11
            b.TextColor3 = Theme.TextPrimary; b.Font = Enum.Font.GothamBlack
            b.ZIndex = 11; b.Active = true
            local hasBallooned = SharedState.BalloonedPlayers and next(SharedState.BalloonedPlayers) ~= nil
            local isOnCD = isOnCooldown(def.cmd)
            b.BackgroundColor3 = ((def.cmd == "balloon" and hasBallooned) or isOnCD) and Theme.Error or Color3.fromRGB(48, 52, 70)
            b.BackgroundTransparency = 0
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
            local bStroke = Instance.new("UIStroke", b)
            bStroke.Color = ((def.cmd == "balloon" and hasBallooned) or isOnCD) and Theme.Error or Color3.fromRGB(110, 116, 200)
            bStroke.Thickness = 1.5; bStroke.Transparency = 0.4; bStroke.ZIndex = 12

            b.MouseEnter:Connect(function()
                if not isOnCD and not (def.cmd == "balloon" and hasBallooned) then
                    b.BackgroundColor3 = Color3.fromRGB(68, 24, 48); bStroke.Transparency = 0.2
                end
            end)
            b.MouseLeave:Connect(function()
                if not isOnCD and not (def.cmd == "balloon" and hasBallooned) then
                    b.BackgroundColor3 = Color3.fromRGB(48, 52, 70); bStroke.Transparency = 0.4
                end
            end)

            if not SharedState.AdminButtonCache[def.cmd] then SharedState.AdminButtonCache[def.cmd] = {} end
            table.insert(SharedState.AdminButtonCache[def.cmd], b)

            task.spawn(function()
                while b and b.Parent do
                    if not adminGui.Enabled then task.wait(3); continue end
                    task.wait(1.5)
                    if not b.Text or b.Text == "" or b.Text == "BUTTON" or b.Text == "Button" then
                        b.Text = def.icon; b.TextSize = 11
                        b.TextColor3 = Theme.TextPrimary; b.Font = Enum.Font.GothamBlack
                    end
                    local cd = isOnCooldown(def.cmd)
                    local balloon = (def.cmd == "balloon" and SharedState.BalloonedPlayers and next(SharedState.BalloonedPlayers) ~= nil)
                    if cd or balloon then
                        b.BackgroundColor3 = Theme.Error; b.BackgroundTransparency = 0
                        bStroke.Color = Theme.Error; bStroke.Transparency = 0.2
                    else
                        b.BackgroundColor3 = Color3.fromRGB(48, 52, 70); b.BackgroundTransparency = 0
                        bStroke.Color = Color3.fromRGB(110, 116, 200); bStroke.Transparency = 0.4
                    end
                    if b.Text ~= def.icon then
                        b.Text = def.icon; b.TextSize = 11
                        b.TextColor3 = Theme.TextPrimary; b.Font = Enum.Font.GothamBlack
                    end
                end
            end)

            b.MouseButton1Click:Connect(function()
                if isBlacklisted(plr) then
                    ShowNotification("ADMIN", plr.Name .. " is blacklisted"); return
                end
                if Config.DisableAPPanelOnMoby and isMobyUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Moby users"); return
                end
                if Config.DisableAPPanelOnKawaifu and isKawaifuUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Kawaifu users"); return
                end
                if Config.DisableAPPanelOnAtlas and isAtlasUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Atlas users"); return
                end
                if Config.DisableAPPanelOnBraintopia and isBraintopiaUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Braintopia users"); return
                end
                if Config.DisableAPPanelOnWNotifier and isWNotifierUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on WNotifier users"); return
                end
                ShowNotification("ADMIN", "Attempting " .. def.cmd .. " on " .. plr.Name)
                if runAdminCommand(plr, def.cmd) then
                    activeCooldowns[def.cmd] = tick()
                    setGlobalVisualCooldown(def.cmd)
                    if def.cmd == "balloon" then
                        SharedState.BalloonedPlayers[plr.UserId] = true
                        for _, btn in ipairs(SharedState.AdminButtonCache["balloon"] or {}) do
                            if btn and btn.Parent then btn.BackgroundColor3 = Theme.Error end
                        end
                    end
                    ShowNotification("ADMIN", "Sent " .. def.cmd .. " to " .. plr.Name)
                else
                    ShowNotification("ADMIN", "Failed to send " .. def.cmd .. " to " .. plr.Name)
                end
            end)
        end

        local blQuickBtn = Instance.new("TextButton", btnCont)
        blQuickBtn.Size = UDim2.new(0, 30, 0, 30)
        blQuickBtn.Position = UDim2.new(0, 4 + (#buttonsDef) * 34, 0.5, -15)
        blQuickBtn.AutoButtonColor = false
        blQuickBtn.Text = "X"; blQuickBtn.TextSize = 14
        blQuickBtn.Font = Enum.Font.GothamBlack
        blQuickBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
        blQuickBtn.ZIndex = 11; blQuickBtn.Active = true
        blQuickBtn.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
        Instance.new("UICorner", blQuickBtn).CornerRadius = UDim.new(0, 8)
        local blQuickStroke = Instance.new("UIStroke", blQuickBtn)
        blQuickStroke.Color = Color3.fromRGB(200, 50, 50); blQuickStroke.Thickness = 1.5
        blQuickStroke.Transparency = 0.3; blQuickStroke.ZIndex = 12

        blQuickBtn.MouseEnter:Connect(function()
            blQuickBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30); blQuickStroke.Transparency = 0.05
        end)
        blQuickBtn.MouseLeave:Connect(function()
            blQuickBtn.BackgroundColor3 = Color3.fromRGB(120, 20, 20); blQuickStroke.Transparency = 0.3
        end)

        blQuickBtn.MouseButton1Click:Connect(function()
            local targetName = plr.Name
            for _, n in ipairs(Config.BlacklistedUsers) do
                if n:lower() == targetName:lower() then
                    ShowNotification("BLACKLIST", targetName .. " is already blacklisted"); return
                end
            end
            table.insert(Config.BlacklistedUsers, targetName)
            SaveConfig()
            blQuickBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 50); blQuickBtn.Text = "OK"
            ShowNotification("BLACKLIST", "Blacklisted: " .. targetName)
            rebuildBlList()
            task.delay(1.2, function()
                if blQuickBtn and blQuickBtn.Parent then
                    blQuickBtn.BackgroundColor3 = Color3.fromRGB(120, 20, 20); blQuickBtn.Text = "X"
                end
            end)
        end)

        local tpBtn = Instance.new("TextButton", btnCont)
        tpBtn.Size = UDim2.new(0, 44, 0, 30)
        tpBtn.Position = UDim2.new(0, 4 + (#buttonsDef + 1) * 34, 0.5, -15)
        tpBtn.AutoButtonColor = false; tpBtn.Text = "TP"; tpBtn.TextSize = 13
        tpBtn.Font = Enum.Font.GothamBlack; tpBtn.TextColor3 = Theme.TextPrimary
        tpBtn.ZIndex = 11; tpBtn.Active = true
        tpBtn.BackgroundColor3 = Theme.Accent2
        Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 8)
        local tpStroke = Instance.new("UIStroke", tpBtn)
        tpStroke.Color = Theme.Accent1; tpStroke.Thickness = 1.5; tpStroke.Transparency = 0.4; tpStroke.ZIndex = 12

        tpBtn.MouseEnter:Connect(function() tpBtn.BackgroundColor3 = Theme.Accent1; tpStroke.Transparency = 0.1 end)
        tpBtn.MouseLeave:Connect(function() tpBtn.BackgroundColor3 = Theme.Accent2; tpStroke.Transparency = 0.4 end)

        tpBtn.MouseButton1Click:Connect(function()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChild("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then ShowNotification("TP TO BASE", "No character"); return end
            local plots = Workspace:FindFirstChild("Plots")
            if not plots then ShowNotification("TP TO BASE", "Plots not found"); return end

            local targetPlot
            local okSync, Synchronizer = pcall(function()
                return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
            end)
            if okSync and Synchronizer then
                for _, p in ipairs(plots:GetChildren()) do
                    local okCh, ch = pcall(function() return Synchronizer:Get(p.Name) end)
                    if okCh and ch then
                        local owner = ch:Get("Owner")
                        if owner then
                            if typeof(owner) == "Instance" and owner == plr then
                                targetPlot = p; break
                            elseif type(owner) == "table" and owner.UserId and plr.UserId and owner.UserId == plr.UserId then
                                targetPlot = p; break
                            elseif type(owner) == "table" and owner.Name and owner.Name == plr.Name then
                                targetPlot = p; break
                            end
                        end
                    end
                end
            end
            if not targetPlot then
                for _, p in ipairs(plots:GetChildren()) do
                    local sign = p:FindFirstChild("PlotSign")
                    local textLabel = sign and sign:FindFirstChild("SurfaceGui")
                        and sign.SurfaceGui:FindFirstChild("Frame")
                        and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
                    if textLabel then
                        local baseText = tostring(textLabel.Text or "")
                        local nickname = baseText:match("^(.-)'") or baseText
                        if nickname == plr.DisplayName or nickname == plr.Name then
                            targetPlot = p; break
                        end
                    end
                end
            end
            if not targetPlot then ShowNotification("TP TO BASE", "Base not found"); return end

            local signPart
            do
                local sign = targetPlot:FindFirstChild("PlotSign")
                if sign then
                    if sign:IsA("BasePart") then
                        signPart = sign
                    elseif sign:IsA("Model") then
                        signPart = sign.PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true)
                    else
                        signPart = sign:FindFirstChildWhichIsA("BasePart", true)
                    end
                end
            end
            if not signPart then ShowNotification("TP TO BASE", "Sign not found"); return end

            local carpetName = Config.TpSettings.Tool
            local carpet = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)
            if carpet then pcall(function() hum:EquipTool(carpet) end); task.wait(0.01) end

            local function riseToY(targetY)
                local MAX_TIME = 3.0; local startT = os.clock()
                while hrp.Parent and hrp.Position.Y < targetY do
                    local dist = targetY - hrp.Position.Y
                    local speed = math.clamp(dist * 20, 280, 310)
                    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, speed, hrp.AssemblyLinearVelocity.Z)
                    if os.clock() - startT > MAX_TIME then break end
                    RunService.Heartbeat:Wait()
                end
                hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
            end
            riseToY(40)

            local signCF = signPart.CFrame
            local FORWARD = signCF.LookVector
            local BACK = -signCF.LookVector
            local frontPoint = signPart.Position + (FORWARD * 20)
            local backPoint  = signPart.Position + (BACK * 20)

            local myFlat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
            local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - myFlat).Magnitude
            local distBack  = (Vector3.new(backPoint.X,  0, backPoint.Z)  - myFlat).Magnitude
            local chosen = (distFront < distBack) and frontPoint or backPoint
            local tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)

            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(tpPos)
            hrp.AssemblyLinearVelocity = Vector3.zero

            local t = 0
            while t < 3.0 do
                local dt = RunService.Heartbeat:Wait(); t = t + dt
                if hrp and hrp.Parent
                    and (hrp.Position - tpPos).Magnitude <= 2
                    and hum
                    and hum.FloorMaterial ~= Enum.Material.Air then
                    break
                end
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            ShowNotification("TP TO BASE", "TP'd to " .. plr.Name .. "'s base")
        end)

        local rowHighlight = Instance.new("Frame", row)
        rowHighlight.Size = UDim2.new(1, 0, 1, 0)
        rowHighlight.BackgroundColor3 = Theme.Accent1
        rowHighlight.BackgroundTransparency = 1
        rowHighlight.BorderSizePixel = 0; rowHighlight.ZIndex = 1
        Instance.new("UICorner", rowHighlight).CornerRadius = UDim.new(0, 6)
        row.MouseEnter:Connect(function() rowHighlight.BackgroundTransparency = 0.7 end)
        row.MouseLeave:Connect(function() rowHighlight.BackgroundTransparency = 1   end)

        row.MouseButton1Click:Connect(function()
            local hasAnyAvailable = false
            for _, cmd in ipairs(ALL_COMMANDS) do
                if not isOnCooldown(cmd) then hasAnyAvailable = true; break end
            end
            if hasAnyAvailable then
                if isBlacklisted(plr) then
                    ShowNotification("ADMIN", plr.Name .. " is blacklisted"); return
                end
                if Config.DisableAPPanelOnMoby and isMobyUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Moby users"); return
                end
                if Config.DisableAPPanelOnKawaifu and isKawaifuUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Kawaifu users"); return
                end
                if Config.DisableAPPanelOnAtlas and isAtlasUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Atlas users"); return
                end
                if Config.DisableAPPanelOnBraintopia and isBraintopiaUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on Braintopia users"); return
                end
                if Config.DisableAPPanelOnWNotifier and isWNotifierUser(plr) then
                    ShowNotification("ADMIN", "AP Panel disabled on WNotifier users"); return
                end
                triggerAll(plr)
                ShowNotification("ADMIN", "Triggered ALL on " .. plr.Name)
            end
        end)

        return row
    end

    local function addPlayer(plr)
        if plr == LocalPlayer or playerRowsByUserId[plr.UserId] then return end
        if not Players:FindFirstChild(plr.Name) then return end
        if Config.HideKawaifuFromPanel and isKawaifuUser(plr) then return end
        if playerRows[plr] then return end

        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") and child.Name == plr.Name then
                for cmd, buttons in pairs(SharedState.AdminButtonCache) do
                    for i = #buttons, 1, -1 do
                        if buttons[i] and buttons[i].Parent == child then
                            table.remove(buttons, i)
                        end
                    end
                end
                child:Destroy()
            end
        end

        local row = createPlayerRow(plr)
        playerRows[plr] = row
        playerRowsByUserId[plr.UserId] = {player = plr, row = row}
        listFrame.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y)
        sortAdminPanelList()
        refreshEmptyPlayersState()
    end

    removePlayer = function(plr)
        local userId = plr and plr.UserId or nil
        local entry = userId and playerRowsByUserId[userId] or nil
        local row = entry and entry.row or playerRows[plr]
        if row then
            if row.Parent then
                for cmd, buttons in pairs(SharedState.AdminButtonCache) do
                    for i = #buttons, 1, -1 do
                        if buttons[i] and buttons[i].Parent == row then
                            table.remove(buttons, i)
                        end
                    end
                end
                row:Destroy()
            end
            if plr then playerRows[plr] = nil end
            if userId then playerRowsByUserId[userId] = nil end
            if SharedState.BalloonedPlayers and userId then
                SharedState.BalloonedPlayers[userId] = nil
            end
            listFrame.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y)
            refreshEmptyPlayersState()
        end
    end

    refreshBtn.MouseButton1Click:Connect(function()
        for _, row in pairs(playerRows) do
            if row and row.Parent then
                for cmd, buttons in pairs(SharedState.AdminButtonCache) do
                    for i = #buttons, 1, -1 do
                        if buttons[i] and buttons[i].Parent == row then
                            table.remove(buttons, i)
                        end
                    end
                end
                row:Destroy()
            end
        end
        playerRows = {}; playerRowsByUserId = {}
        SharedState.AdminButtonCache = {}; SharedState.BalloonedPlayers = {}

        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        refreshEmptyPlayersState()
        task.wait(0.1)

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then addPlayer(p) end
        end
        sortAdminPanelList()
        refreshEmptyPlayersState()

        ShowNotification("ADMIN PANEL", "Completely refreshed - " .. (#Players:GetPlayers() - 1) .. " players found")
    end)

    Players.PlayerAdded:Connect(function(plr)
        task.wait(0.1)
        if plr and plr.Parent then addPlayer(plr) end
    end)
    Players.PlayerRemoving:Connect(function(plr) removePlayer(plr) end)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then addPlayer(p) end
    end
    sortAdminPanelList()
    refreshEmptyPlayersState()

    task.spawn(function()
        while listFrame and listFrame.Parent do
            task.wait(2)
            pcall(sortAdminPanelList)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(3)
            local currentPlayerIds = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Parent then currentPlayerIds[p.UserId] = true end
            end
            for userId, entry in pairs(playerRowsByUserId) do
                if not currentPlayerIds[userId] or not entry.player or not entry.player.Parent
                    or not Players:FindFirstChild(entry.player.Name) then
                    removePlayer(entry.player)
                end
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Parent and not playerRowsByUserId[p.UserId] then
                    addPlayer(p)
                end
            end
        end
    end)

    layout.Changed:Connect(function()
        listFrame.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y)
    end)

    print("[chopper_hub Admin] UI ready")
    end) -- end pcall

    if not ok then
        warn("[chopper_hub Admin] init failed: " .. tostring(err))
    end
end)

    end)

    do
        -- restore the saved mode
        if Config.StealNearest then _G.MeerkoStealMode = "nearest"
        elseif Config.StealHighest then _G.MeerkoStealMode = "highest"
        elseif Config.StealPriority then _G.MeerkoStealMode = "priority"
        else _G.MeerkoStealMode = nil end

        local function setMode(mode)
            Config.StealNearest  = (mode == "nearest")
            Config.StealHighest  = (mode == "highest")
            Config.StealPriority = (mode == "priority")
            _G.MeerkoStealMode   = mode
            SaveConfig()
        end
        _G.MeerkoSetStealMode = setMode

        local Workspace    = MK_Workspace
        local RunService   = MK_Run
        local LocalPlayer  = MK_LP
        local TweenService = game:GetService("TweenService")

        local STEAL_HOLD_MIN   = 1.3    -- min hold before the trigger can fire (matches the server's own minimum hold-time check -- going lower makes the server silently reject the steal)
        local STEAL_HOLD_MAX   = 2.6    -- give up the attempt after this
        local STEAL_RANGE      = 14     -- must be this close for the pickup to fire
        local STEAL_ENTRY_DELAY = 0.3   -- settle time after just entering range
        local ENGAGE_RANGE     = 130    -- only arm/show the bar within this of target

        local promptCache    = {}       -- [uid] = ProximityPrompt
        local stealCache     = {}       -- [prompt] = {hold,trig,ready}
        local lastFire       = {}       -- [prompt] = os.clock()
        local currentTargetUID = nil
        local activeTween    = nil
        local barActive      = false   -- true while a hold is in progress or a target is armed

        -- ----- steal bar UI (centered; only visible while arming a steal) ---
        local barSg = Instance.new("ScreenGui")
        barSg.Name = "MeerkoStealBar"
        barSg.ResetOnSpawn = false
        barSg.IgnoreGuiInset = true
        barSg.DisplayOrder = 50
        do
            local _cloneref = cloneref or function(x) return x end
            pcall(function() barSg.Parent = _cloneref(game:GetService("CoreGui")) end)
            if not barSg.Parent then barSg.Parent = MK_PlayerGui end
        end
        local barHolder = Instance.new("Frame", barSg)
        barHolder.Size = UDim2.new(0, 264, 0, 56)
        barHolder.Position = UDim2.new(0.5, -132, 0.84, 0)
        barHolder.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        barHolder.BackgroundTransparency = 0
        barHolder.BorderSizePixel = 0
        barHolder.Visible = true
        Instance.new("UICorner", barHolder).CornerRadius = UDim.new(0, 14)
        local barStroke = Instance.new("UIStroke", barHolder)
        barStroke.Color = Color3.fromRGB(48, 48, 60); barStroke.Thickness = 1; barStroke.Transparency = 0.2
        do  -- soft drop shadow
            local ps = Instance.new("ImageLabel", barHolder)
            ps.Name = "BarShadow"; ps.BackgroundTransparency = 1
            ps.Image = "rbxassetid://6014261993"; ps.ScaleType = Enum.ScaleType.Slice
            ps.SliceCenter = Rect.new(49, 49, 463, 463); ps.ImageColor3 = Color3.fromRGB(0, 0, 0)
            ps.ImageTransparency = 0.55
            ps.AnchorPoint = Vector2.new(0.5, 0.5); ps.Position = UDim2.new(0.5, 0, 0.5, 0)
            ps.Size = UDim2.new(1, 42, 1, 42); ps.ZIndex = 0
        end

        -- "Stealing..." title (top, centered)
        local barLabel = Instance.new("TextLabel", barHolder)
        barLabel.Size = UDim2.new(1, -20, 0, 16)
        barLabel.Position = UDim2.new(0, 10, 0, 7)
        barLabel.BackgroundTransparency = 1
        barLabel.Text = "Stealing..."
        barLabel.TextColor3 = Color3.fromRGB(245, 246, 250)
        barLabel.TextSize = 13
        barLabel.Font = Enum.Font.GothamBold
        barLabel.TextXAlignment = Enum.TextXAlignment.Center
        barLabel.TextTruncate = Enum.TextTruncate.AtEnd
        barLabel.ZIndex = 3

        -- progress track + pink fill + centered % text
        local barTrack = Instance.new("Frame", barHolder)
        barTrack.Size = UDim2.new(1, -20, 0, 20)
        barTrack.Position = UDim2.new(0, 10, 0, 28)
        barTrack.BackgroundColor3 = Color3.fromRGB(12, 12, 16); barTrack.BackgroundTransparency = 0
        barTrack.BorderSizePixel = 0
        barTrack.ZIndex = 2
        Instance.new("UICorner", barTrack).CornerRadius = UDim.new(1, 0)
        Instance.new("UIStroke", barTrack).Color = Color3.fromRGB(40, 40, 50)
        local barFill = Instance.new("Frame", barTrack)
        barFill.Size = UDim2.new(0, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(140, 146, 255); barFill.BackgroundTransparency = 0
        barFill.BorderSizePixel = 0
        barFill.ZIndex = 2
        Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
        do  -- purple-blue gradient on the fill (matches the admin panel)
            local gr = Instance.new("UIGradient", barFill)
            gr.Color = ColorSequence.new(Color3.fromRGB(150, 156, 255), Color3.fromRGB(120, 110, 222))
        end
        local barPct = Instance.new("TextLabel", barTrack)
        barPct.Size = UDim2.new(1, 0, 1, 0)
        barPct.BackgroundTransparency = 1
        barPct.Text = "0%"
        barPct.TextColor3 = Color3.fromRGB(255, 255, 255)
        barPct.TextSize = 12
        barPct.Font = Enum.Font.GothamBold
        barPct.TextXAlignment = Enum.TextXAlignment.Center
        barPct.TextYAlignment = Enum.TextYAlignment.Center
        barPct.ZIndex = 3
        -- live percentage from the fill's animated width
        task.spawn(function()
            while barSg.Parent do
                if barActive then
                    local p = math.clamp(barFill.Size.X.Scale, 0, 1)
                    barPct.Text = math.floor(p * 100 + 0.5) .. "%"
                    task.wait(0.05)
                else
                    task.wait(0.5)
                end
            end
        end)

        -- ----- find the Steal ProximityPrompt for a plot+slot --------------
        local function findStealPrompt(plotName, slot)
            local plots = Workspace:FindFirstChild("Plots"); if not plots then return nil end
            local plotInst = plots:FindFirstChild(plotName); if not plotInst then return nil end
            local podiums = plotInst:FindFirstChild("AnimalPodiums"); if not podiums then return nil end
            local podium = podiums:FindFirstChild(tostring(slot)); if not podium then return nil end
            local base = podium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            -- prefer an ENABLED steal prompt; otherwise keep the DISABLED one
            -- (someone else is mid-steal) so the loop keeps firing it and snipes
            -- the moment it frees up.
            local disabledFallback = nil
            if spawn then
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then
                            if p.Enabled then return p end
                            disabledFallback = disabledFallback or p
                        end
                    end
                end
                local startPos = spawn.Position
                local nearest, minDist = nil, math.huge
                for _, desc in ipairs(plotInst:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.ActionText == "Steal" then
                        local part = desc.Parent
                        local pos
                        if part and part:IsA("BasePart") then pos = part.Position
                        elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then pos = part.Parent.Position end
                        if pos then
                            local hd = math.sqrt((pos.X - startPos.X)^2 + (pos.Z - startPos.Z)^2)
                            if hd < 5 and pos.Y > startPos.Y then
                                local yd = pos.Y - startPos.Y
                                if desc.Enabled then
                                    if yd < minDist then minDist = yd; nearest = desc end
                                else
                                    disabledFallback = disabledFallback or desc
                                end
                            end
                        end
                    end
                end
                if nearest then return nearest end
            end
            for _, p in ipairs(podium:GetDescendants()) do
                if p:IsA("ProximityPrompt") then
                    if p.Enabled then return p end
                    disabledFallback = disabledFallback or p
                end
            end
            return disabledFallback
        end

        local _getconns = getconnections or get_signal_cons
        local function gatherCallbacks(signal)
            local out = {}
            if not _getconns then return out end
            local ok, conns = pcall(_getconns, signal)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local fn = c.Function or (c.Get and c:Get())
                    if type(fn) == "function" then out[#out + 1] = fn end
                end
            end
            return out
        end
        local function buildCallbacks(prompt)
            if stealCache[prompt] then return stealCache[prompt] end
            local d = {
                hold = gatherCallbacks(prompt.PromptButtonHoldBegan),
                trig = gatherCallbacks(prompt.Triggered),
                ready = true,
            }
            stealCache[prompt] = d
            return d
        end

        local function distToPos(pos)
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp or not pos then return math.huge end
            return (hrp.Position - pos).Magnitude
        end

        local function hideBar()
            if activeTween then activeTween:Cancel(); activeTween = nil end
            barFill.Size = UDim2.new(0, 0, 1, 0)
            barLabel.Text = "Steal"
            barActive = false
        end

        -- attemptSteal: hold the prompt, fill the bar over the hold window, and
        -- fire the trigger (pickup) the moment we're within STEAL_RANGE.
        local function attemptSteal(prompt, uid, animalPos, name)
            if not prompt or not prompt.Parent then return false end
            if currentTargetUID ~= uid then
                if activeTween then activeTween:Cancel(); activeTween = nil end
                barFill.Size = UDim2.new(0, 0, 1, 0)
                currentTargetUID = uid
            end
            local now = os.clock()
            if lastFire[prompt] and (now - lastFire[prompt]) < 0.5 then return true end
            lastFire[prompt] = now
            local data = buildCallbacks(prompt)
            if not (data and data.ready and (#data.hold > 0 or #data.trig > 0)) then return false end
            data.ready = false
            task.spawn(function()
                for _, fn in ipairs(data.hold) do task.spawn(fn) end
                barLabel.Text = "Stealing " .. tostring(name or "brainrot") .. "..."
                barActive = true
                barFill.Size = UDim2.new(0, 0, 1, 0)
                if activeTween then activeTween:Cancel() end
                -- fill at a constant rate that lands on 100% exactly when the
                -- hold is allowed to fire (STEAL_HOLD_MIN), instead of animating
                -- to a slower STEAL_HOLD_MAX pace and then jumping the rest of
                -- the way when it fires early.
                activeTween = TweenService:Create(barFill, TweenInfo.new(STEAL_HOLD_MIN, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 1, 0) })
                activeTween:Play()

                local startT = tick()
                while tick() - startT < STEAL_HOLD_MIN do
                    if currentTargetUID ~= uid then hideBar(); data.ready = true; return end
                    task.wait()
                end

                local alreadyInRange = distToPos(animalPos) <= STEAL_RANGE
                local fired = false
                while true do
                    if tick() - startT > STEAL_HOLD_MAX then break end
                    if not prompt.Parent then break end
                    if currentTargetUID ~= uid then break end
                    if distToPos(animalPos) <= STEAL_RANGE then
                        if not alreadyInRange then task.wait(STEAL_ENTRY_DELAY) end
                        for _, fn in ipairs(data.trig) do task.spawn(fn) end
                        if #data.trig == 0 and typeof(fireproximityprompt) == "function" then
                            pcall(fireproximityprompt, prompt)
                        end
                        fired = true
                        break
                    end
                    task.wait()
                end

                if fired then
                    if activeTween then activeTween:Cancel(); activeTween = nil end
                    barFill.Size = UDim2.new(1, 0, 1, 0)
                    task.wait(0.15)
                end
                barFill.Size = UDim2.new(0, 0, 1, 0)
                barLabel.Text = "Steal"
                task.wait(0.05)
                data.ready = true
            end)
            return true
        end

        -- target selection by mode (same rules Vanish uses)
        local function pickTarget(pets)
            -- manual override from the Steal Target panel takes priority
            -- over Nearest/Highest/Priority, same as doVelocityTP.
            local overrideUID = _G.MeerkoStealTargetUID
            if overrideUID then
                for _, p in ipairs(pets) do
                    if (tostring(p.plot) .. "|" .. tostring(p.slot)) == overrideUID then
                        return p
                    end
                end
            end

            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if Config.StealNearest then
                local best, bestD = nil, math.huge
                for _, p in ipairs(pets) do
                    local d = hrp and (hrp.Position - p.position).Magnitude or math.huge
                    if d < bestD then bestD = d; best = p end
                end
                return best
            elseif Config.StealHighest then
                local best = pets[1]
                for _, p in ipairs(pets) do
                    if (p.mps or 0) > (best.mps or 0) then best = p end
                end
                return best
            else
                -- priority: scanAllPets is already petOutranks-sorted
                return pets[1]
            end
        end

        -- the driver loop: re-arm the steal on the current target ~10x/sec
        local _lastTick = 0
        local _petsCacheT = 0
        local _petsCache = {}
        local _stealReadyAt = os.clock() + 3   -- hold off the steal scan ~3s after joining
        RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
            if os.clock() < _stealReadyAt then return end
            local active = Config.StealNearest or Config.StealHighest or Config.StealPriority or _G.MeerkoStealTargetUID ~= nil
            if not active then
                if barActive then hideBar() end
                currentTargetUID = nil
                _G.MeerkoCurrentSteal = nil
                return
            end
            if LocalPlayer:GetAttribute("Stealing") == true then return end
            local now = os.clock()
            if now - _lastTick < 0.25 then return end
            _lastTick = now

            -- scanAllPets is moderately heavy; refresh the list ~1x/sec
            if now - _petsCacheT > 1.0 then
                local ok, pets = pcall(scanAllPets)
                _petsCache = (ok and pets) or {}
                _petsCacheT = now
            end
            if #_petsCache == 0 then if barActive then hideBar() end return end

            local tp = pickTarget(_petsCache)
            if not tp then return end

            -- whatever brainrot the TP/steal engine is currently converging on,
            -- regardless of ENGAGE_RANGE -- used by the competing-thief popup
            _G.MeerkoCurrentSteal = {
                uid = tostring(tp.plot) .. "|" .. tostring(tp.slot),
                index = tp.index,
                name = tp.name,
            }

            -- only arm/show the bar when we're actually heading into the target
            if distToPos(tp.position) > ENGAGE_RANGE then
                if barActive then hideBar() end
                return
            end

            local uid = tostring(tp.plot) .. "_" .. tostring(tp.slot)
            local pr = promptCache[uid]
            if not pr or not pr.Parent then
                pr = findStealPrompt(tp.plot, tp.slot)
                promptCache[uid] = pr
            end
            if pr then
                -- always loop: while we're within steal range, fire the prompt
                -- continuously every tick so it keeps grabbing with no delay
                if distToPos(tp.position) <= STEAL_RANGE and typeof(fireproximityprompt) == "function" then
                    pcall(fireproximityprompt, pr)
                end
                attemptSteal(pr, uid, tp.position, tp.name)
            end
        end))

    end

    -- =================================================================
    -- =================================================================
    do
        local UserInputService = game:GetService("UserInputService")
        local RunService = MK_Run
        local LocalPlayer = MK_LP
        local conns = {}

        local function clearConns()
            for _, c in pairs(conns) do pcall(function() c:Disconnect() end) end
            conns = {}
        end

        local function setInfiniteJump(enabled)
            Config.InfiniteJump = enabled
            clearConns()
            if not enabled then return end

            local JUMP_BOOST   = 1.0
            local PRESS_WINDOW = 0.20
            local spaceHeld = false

            local doHop = LPH_NO_VIRTUALIZE(function()
                local char = LocalPlayer.Character
                if not char then return end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end
                _G.VanishInfJumpUntil = tick() + PRESS_WINDOW
                local cur = hrp.Velocity
                hrp.Velocity = Vector3.new(cur.X, (hum.JumpPower or 50) * JUMP_BOOST, cur.Z)
            end)

            conns[#conns + 1] = UserInputService.JumpRequest:Connect(function() doHop() end)
            conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if input.KeyCode == Enum.KeyCode.Space then spaceHeld = true end
            end)
            conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
                if input.KeyCode == Enum.KeyCode.Space then spaceHeld = false end
            end)
            conns[#conns + 1] = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not Config.InfiniteJump then return end
                if not spaceHeld then return end
                local char = LocalPlayer.Character
                if not char then return end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end
                _G.VanishInfJumpUntil = tick() + PRESS_WINDOW
                local cur = hrp.Velocity
                hrp.Velocity = Vector3.new(cur.X, (hum.JumpPower or 50) * JUMP_BOOST, cur.Z)
            end))
        end

        _G.MeerkoSetInfiniteJump = setInfiniteJump
        if Config.InfiniteJump then setInfiniteJump(true) end
    end

    do
        local RunService = MK_Run
        local LocalPlayer = MK_LP
        local conn
        local function setCarpetSpeed(enabled)
            Config.CarpetSpeed = enabled
            if conn then conn:Disconnect(); conn = nil end
            if not enabled then return end
            conn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not Config.CarpetSpeed then return end
                local c = LocalPlayer.Character
                if not c then return end
                local hum = c:FindFirstChildOfClass("Humanoid")
                local hrp = c:FindFirstChild("HumanoidRootPart")
                if not hum or not hrp then return end
                pcall(equipCarpet)
                local md = hum.MoveDirection
                local keepY = hrp.Velocity.Y
                if md.Magnitude > 0 then
                    hrp.Velocity = Vector3.new(md.X * 140, keepY, md.Z * 140)
                else
                    hrp.Velocity = Vector3.new(0, keepY, 0)
                    pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0) end)
                end
            end))
        end
        _G.MeerkoSetCarpetSpeed = setCarpetSpeed
        if Config.CarpetSpeed then setCarpetSpeed(true) end
    end

    do
        local Lighting = game:GetService("Lighting")
        local Players = MK_Players

        local function isPlayerCharacter(model)
            return Players:GetPlayerFromCharacter(model) ~= nil
        end
        local function handleAnimator(animator)
            local model = animator:FindFirstAncestorOfClass("Model")
            if model and isPlayerCharacter(model) then return end
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
            animator.AnimationPlayed:Connect(function(track) track:Stop(0) end)
        end
        local function stripVisuals(obj)
            local model = obj:FindFirstAncestorOfClass("Model")
            local isPlayer = model and isPlayerCharacter(model)
            if obj:IsA("Animator") then handleAnimator(obj) end
            if obj:IsA("Accessory") or obj:IsA("Clothing") then
                if obj:FindFirstAncestorOfClass("Model") then obj:Destroy() end
            end
            local isMeerkoBeam = obj:IsA("Beam") and (obj.Name == "PlotBeam" or obj.Name == "MeerkoBrainrotBeam")
            if not isPlayer and not isMeerkoBeam then
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or
                   obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") or
                   obj:IsA("Highlight") then
                    obj.Enabled = false
                end
                if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                    obj.Enabled = false; obj.Brightness = 0; obj.Range = 0
                    task.defer(function() pcall(function() obj:Destroy() end) end)
                end
                if obj:IsA("Explosion") then obj:Destroy() end
                if obj:IsA("MeshPart") then obj.TextureID = "" end
            end
            if obj:IsA("BasePart") then
                obj.Material = Enum.Material.Plastic; obj.Reflectance = 0; obj.CastShadow = false
            end
            if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") or obj:IsA("Decal") then
                obj:Destroy()
            end
        end

        local fpsBoostConn = nil
        local function setFPSBoost(enabled)
            Config.FPSBoost = enabled; SaveConfig()
            if fpsBoostConn then fpsBoostConn:Disconnect(); fpsBoostConn = nil end
            if not enabled then return end
            pcall(function()
                Lighting.ClockTime = 7
                Lighting.TimeOfDay = "07:00:00"
                Lighting.Brightness = 2
                Lighting.GlobalShadows = false
                Lighting.OutdoorAmbient = Color3.fromRGB(165, 165, 165)
                Lighting.FogEnd = 9e9; Lighting.FogStart = 0
                Lighting.EnvironmentDiffuseScale = 0; Lighting.EnvironmentSpecularScale = 0
                for _, v in pairs(Lighting:GetChildren()) do
                    if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("BloomEffect")
                        or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") then
                        v:Destroy()
                    end
                end
                local Terrain = workspace:FindFirstChildOfClass("Terrain")
                if Terrain then
                    Terrain.WaterWaveSize = 0; Terrain.WaterWaveSpeed = 0
                    Terrain.WaterReflectance = 0; Terrain.WaterTransparency = 1
                end
            end)
            task.spawn(function()
                local objs = workspace:GetDescendants()
                for i = 1, #objs do
                    stripVisuals(objs[i])
                    if i % 30 == 0 then task.wait() end
                end
            end)
            fpsBoostConn = workspace.DescendantAdded:Connect(function(obj)
                if not Config.FPSBoost then return end
                task.defer(function() stripVisuals(obj) end)
            end)
        end
        _G.MeerkoSetFPSBoost = setFPSBoost
        if Config.FPSBoost then setFPSBoost(true) end
    end

    do
        local LocalPlayer = MK_LP
        local TweenService = game:GetService("TweenService")
        local unlockGui, unlockBtns

        local function getHRP()
            local c = LocalPlayer.Character; if not c then return nil end
            return c:FindFirstChild("HumanoidRootPart")
        end

        local function smartInteract(number)
            local hrp = getHRP(); if not hrp then return end
            local plots = workspace:FindFirstChild("Plots"); if not plots then return end
            local closestPlot, minDist = nil, 40
            for _, plot in pairs(plots:GetChildren()) do
                local pp
                if plot:IsA("Model") then pp = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
                else pp = plot.Position end
                local d = (hrp.Position - pp).Magnitude
                if d < minDist then closestPlot = plot; minDist = d end
            end
            if closestPlot and closestPlot:FindFirstChild("Unlock") then
                local items = {}
                for _, item in pairs(closestPlot.Unlock:GetChildren()) do
                    local pos = item:IsA("Model") and item:GetPivot().Position or item.Position
                    table.insert(items, { Obj = item, Y = pos.Y })
                end
                table.sort(items, function(a, b) return a.Y < b.Y end)
                if items[number] then
                    for _, pr in pairs(items[number].Obj:GetDescendants()) do
                        if pr:IsA("ProximityPrompt") then pcall(fireproximityprompt, pr) end
                    end
                end
            end
        end

        local function destroyUnlockUI()
            if unlockGui then pcall(function() unlockGui:Destroy() end); unlockGui = nil end
            unlockBtns = nil
        end

        local function createUnlockUI()
            destroyUnlockUI()
            unlockGui = Instance.new("ScreenGui")
            unlockGui.Name = "MeerkoUnlockButtons"
            unlockGui.ResetOnSpawn = false; unlockGui.IgnoreGuiInset = true
            unlockGui.DisplayOrder = 52
            do
                local _cr = cloneref or function(x) return x end
                pcall(function() unlockGui.Parent = _cr(game:GetService("CoreGui")) end)
                if not unlockGui.Parent then unlockGui.Parent = MK_PlayerGui end
            end

            local root = Instance.new("Frame", unlockGui)
            root.AnchorPoint = Vector2.new(0.5, 0)
            root.Size = UDim2.new(0, 126, 0, 36)
            root.Position = UDim2.new(0.5, 0, 0, 92)   -- just below the header badge
            root.BackgroundTransparency = 1

            local BTN_SZ, GAP = 36, 9
            -- blue buttons (matches the admin panel / menu)
            local FG_CARD    = Color3.fromRGB(43, 46, 60)
            local FG_CARDALT = Color3.fromRGB(58, 62, 82)
            local FG_TEXT    = Color3.fromRGB(142, 148, 255)
            local FG_STROKE  = Color3.fromRGB(88, 94, 138)
            local FG_ACCENT  = Color3.fromRGB(142, 148, 255)
            unlockBtns = {}
            for i = 1, 3 do
                local b = Instance.new("TextButton", root)
                b.Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ)
                b.Position = UDim2.new(0, (i - 1) * (BTN_SZ + GAP), 0, 0)
                b.AutoButtonColor = false; b.Text = tostring(i)
                b.BackgroundColor3 = FG_CARD
                b.BorderSizePixel = 0
                b.Font = Enum.Font.GothamBold; b.TextSize = 16
                b.TextColor3 = FG_TEXT
                b.TextStrokeTransparency = 1
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
                local s = Instance.new("UIStroke", b)
                s.Color = FG_STROKE; s.Thickness = 1; s.Transparency = 0
                b.MouseButton1Click:Connect(function()
                    smartInteract(i)
                    -- click flash to accent purple
                    TweenService:Create(s, TweenInfo.new(0.08), { Color = FG_ACCENT }):Play()
                    task.delay(0.18, function()
                        TweenService:Create(s, TweenInfo.new(0.18), { Color = FG_STROKE }):Play()
                    end)
                end)
                b.MouseEnter:Connect(function()
                    TweenService:Create(b, TweenInfo.new(0.14), { BackgroundColor3 = FG_CARDALT }):Play()
                end)
                b.MouseLeave:Connect(function()
                    TweenService:Create(b, TweenInfo.new(0.14), { BackgroundColor3 = FG_CARD }):Play()
                end)
                unlockBtns[i] = b
            end

            -- drag
            local dg, ds, sp = false, nil, nil
            root.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dg = true; ds = input.Position; sp = UDim2.new(0, root.AbsolutePosition.X, 0, root.AbsolutePosition.Y)
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then dg = false end
                    end)
                end
            end)
            game:GetService("UserInputService").InputChanged:Connect(function(input)
                if dg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local d = input.Position - ds
                    root.Position = UDim2.new(0, sp.X.Offset + d.X, 0, sp.Y.Offset + d.Y)
                end
            end)
        end

        _G.MeerkoSetUnlockButtons = function(on)
            Config.UnlockButtons = on; SaveConfig()
            if on then createUnlockUI() else destroyUnlockUI() end
        end
        if Config.UnlockButtons then createUnlockUI() end
    end

    -- =================================================================
    -- X-RAY BASES  (ported from chopper_hub): make base walls translucent via
    -- LocalTransparencyModifier (client-side) + a __index spoof so the game
    -- can't read the value back. Toggleable; restores on disable.
    -- =================================================================
    task.spawn(function()
        local XRAY_TRANSPARENCY = 0.8
        local xraySpoofed = {}

        -- The __index spoof is a GLOBAL hook (every property read in the game
        -- goes through it), so only install it the first time X-Ray is turned
        -- on -- never at load. Avoids slowing everything down when it's off.
        local hookInstalled = false
        local function installSpoofHook()
            if hookInstalled then return end
            hookInstalled = true
            pcall(function()
                if hookmetamethod and newcclosure then
                    local oldIndex
                    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
                        if (not checkcaller or not checkcaller())
                            and typeof(self) == "Instance"
                            and self:IsA("BasePart")
                            and key == "LocalTransparencyModifier"
                            and xraySpoofed[self] ~= nil then
                            return xraySpoofed[self]
                        end
                        return oldIndex(self, key)
                    end))
                end
            end)
        end

        local function shouldXray(obj)
            if not obj:IsA("BasePart") then return false end
            local n = obj.Name:lower()
            local p = obj.Parent and obj.Parent.Name:lower() or ""
            return n:find("base") or n:find("claim") or p:find("base") or p:find("claim")
        end

        local function applyXray(obj)
            if not Config.XrayBases then return end
            if not shouldXray(obj) then return end
            xraySpoofed[obj] = obj.LocalTransparencyModifier or 0
            pcall(function() obj.LocalTransparencyModifier = XRAY_TRANSPARENCY end)
        end

        local function disableXray()
            for obj, origVal in pairs(xraySpoofed) do
                if obj and obj.Parent then
                    pcall(function() obj.LocalTransparencyModifier = origVal or 0 end)
                end
            end
            table.clear(xraySpoofed)
        end

        local function enableXray()
            local count = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                applyXray(obj)
                count = count + 1
                if count % 150 == 0 then task.wait() end
            end
        end

        workspace.DescendantAdded:Connect(function(obj)
            if not Config.XrayBases then return end
            task.wait()
            applyXray(obj)
        end)

        _G.MeerkoSetXray = function(on)
            Config.XrayBases = on and true or false
            if SaveConfig then pcall(SaveConfig) end
            if Config.XrayBases then installSpoofHook(); enableXray() else disableXray() end
        end

        if Config.XrayBases then installSpoofHook(); enableXray() end
    end)

    -- =================================================================
    -- =================================================================
    do
        local LocalPlayer = MK_LP
        local RunService = MK_Run

        local antiRagdollConnections = {}
        local antiRagdollCharacter, antiRagdollHumanoid, antiRagdollRootPart, antiRagdollAnimator
        local lastVelocity = Vector3.new(0, 0, 0)
        local velocityChangeThreshold = 40
        local velocityMagnitudeThreshold = 25
        local maxVelocity = 15

        local isRagdolledLocal = LPH_NO_VIRTUALIZE(function()
            if not Config.AntiRagdoll then return false end
            if not antiRagdollHumanoid then return false end
            local state = antiRagdollHumanoid:GetState()
            if state ~= Enum.HumanoidStateType.Physics
               and state ~= Enum.HumanoidStateType.Ragdoll
               and state ~= Enum.HumanoidStateType.FallingDown
               and state ~= Enum.HumanoidStateType.GettingUp then
                return false
            end
            return true
        end)

        local function enableAntiRagdollControls()
            pcall(function()
                local PlayerModule = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
                require(PlayerModule):GetControls():Enable()
            end)
        end

        local cleanupRagdoll = LPH_NO_VIRTUALIZE(function()
            if not antiRagdollCharacter then return end
            local function processChildren(parent)
                for _, obj in ipairs(parent:GetChildren()) do
                    if obj:IsA("BallSocketConstraint") or obj:IsA("NoCollisionConstraint")
                       or obj:IsA("HingeConstraint")
                       or (obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B")) then
                        obj:Destroy()
                    elseif obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                        obj:Destroy()
                    elseif obj:IsA("Motor6D") then
                        obj.Enabled = true
                    elseif obj:IsA("BasePart") then
                        for _, child in ipairs(obj:GetChildren()) do
                            if child:IsA("BallSocketConstraint") or child:IsA("NoCollisionConstraint")
                               or child:IsA("HingeConstraint") or child:IsA("Motor6D") then
                                if child:IsA("Motor6D") then child.Enabled = true else child:Destroy() end
                            elseif child:IsA("Attachment") and (child.Name == "A" or child.Name == "B") then
                                child:Destroy()
                            end
                        end
                    end
                end
            end
            pcall(function() processChildren(antiRagdollCharacter) end)
            if antiRagdollAnimator then
                for _, track in pairs(antiRagdollAnimator:GetPlayingAnimationTracks()) do
                    local animName = track.Animation and track.Animation.Name:lower() or ""
                    if animName:find("rag") or animName:find("fall") or animName:find("hurt") or animName:find("down") then
                        track:Stop(0)
                    end
                end
            end
        end)

        local function setupAntiRagdollCharacter(char)
            antiRagdollCharacter = char
            antiRagdollHumanoid = char:WaitForChild("Humanoid", 10)
            antiRagdollRootPart = char:WaitForChild("HumanoidRootPart", 10)
            antiRagdollAnimator = antiRagdollHumanoid:WaitForChild("Animator", 10)
            lastVelocity = Vector3.new(0, 0, 0)
        end

        local function clearAntiRagdollConnections()
            for _, connection in pairs(antiRagdollConnections) do pcall(function() connection:Disconnect() end) end
            antiRagdollConnections = {}
        end

        local function setupAntiRagdollConnections()
            clearAntiRagdollConnections()
            table.insert(antiRagdollConnections, antiRagdollHumanoid.StateChanged:Connect(function()
                if isRagdolledLocal() then
                    antiRagdollHumanoid:ChangeState(Enum.HumanoidStateType.Running)
                    cleanupRagdoll()
                    workspace.CurrentCamera.CameraSubject = antiRagdollHumanoid
                    enableAntiRagdollControls()
                end
            end))
            table.insert(antiRagdollConnections, antiRagdollCharacter.DescendantAdded:Connect(function()
                if isRagdolledLocal() then cleanupRagdoll() end
            end))
            local _arFrame = 0
            table.insert(antiRagdollConnections, RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                _arFrame = _arFrame + 1
                if _arFrame < 6 then return end
                _arFrame = 0
                if isRagdolledLocal() then
                    cleanupRagdoll()
                    local v = antiRagdollRootPart.AssemblyLinearVelocity
                    if (v - lastVelocity).Magnitude > velocityChangeThreshold and v.Magnitude > velocityMagnitudeThreshold then
                        antiRagdollRootPart.AssemblyLinearVelocity = v.Unit * math.min(v.Magnitude, maxVelocity)
                    end
                    lastVelocity = v
                end
            end)))
        end

        local function activateForCharacter(char)
            setupAntiRagdollCharacter(char)
            setupAntiRagdollConnections()
        end

        if LocalPlayer.Character then pcall(activateForCharacter, LocalPlayer.Character) end
        LocalPlayer.CharacterAdded:Connect(function(char) pcall(activateForCharacter, char) end)
    end

    -- =================================================================
    -- =================================================================
    do
        local LocalPlayer = MK_LP
        local RunService = MK_Run
        local Lighting = game:GetService("Lighting")
        local FORCE_FOV = 70
        local ab = {
            running = false, connections = {}, originalMoveFunction = nil, controlsProtected = false,
            badLightingNames = { Blue = true, DiscoEffect = true, BeeBlur = true, ColorCorrection = true },
        }

        local function nuke(obj)
            if obj and obj.Parent and ab.badLightingNames[obj.Name] then pcall(function() obj:Destroy() end) end
        end
        local function disconnectAll()
            for _, c in ipairs(ab.connections) do if typeof(c) == "RBXScriptConnection" then c:Disconnect() end end
            ab.connections = {}
        end
        local function protectControls()
            if ab.controlsProtected then return end
            pcall(function()
                local PlayerModule = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
                if not PlayerModule then return end
                local Controls = require(PlayerModule):GetControls()
                if not Controls then return end
                if not ab.originalMoveFunction then ab.originalMoveFunction = Controls.moveFunction end
                local function protectedMoveFunction(self, moveVector, relativeToCamera)
                    if ab.originalMoveFunction then ab.originalMoveFunction(self, moveVector, relativeToCamera) end
                end
                local _abFrame = 0
                table.insert(ab.connections, RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                    if not ab.running or not Config.AntiBeeDisco then return end
                    _abFrame = _abFrame + 1
                    if _abFrame < 6 then return end
                    _abFrame = 0
                    if Controls.moveFunction ~= protectedMoveFunction then Controls.moveFunction = protectedMoveFunction end
                end)))
                Controls.moveFunction = protectedMoveFunction
                ab.controlsProtected = true
            end)
        end
        local function restoreControls()
            if not ab.controlsProtected then return end
            pcall(function()
                local PlayerModule = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
                if not PlayerModule then return end
                local Controls = require(PlayerModule):GetControls()
                if Controls and ab.originalMoveFunction then
                    Controls.moveFunction = ab.originalMoveFunction
                    ab.controlsProtected = false
                end
            end)
        end
        local function blockBuzzingSound()
            pcall(function()
                local beeScript = LocalPlayer.PlayerScripts:FindFirstChild("Bee", true)
                if beeScript then
                    local buzzing = beeScript:FindFirstChild("Buzzing")
                    if buzzing and buzzing:IsA("Sound") then buzzing:Stop(); buzzing.Volume = 0 end
                end
            end)
        end
        local function Enable()
            if ab.running then return end
            ab.running = true
            for _, inst in ipairs(Lighting:GetDescendants()) do nuke(inst) end
            table.insert(ab.connections, Lighting.DescendantAdded:Connect(function(obj)
                if ab.running and Config.AntiBeeDisco then nuke(obj) end
            end))
            protectControls()
            local _abFovFrame = 0
            table.insert(ab.connections, RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not ab.running or not Config.AntiBeeDisco then return end
                _abFovFrame = _abFovFrame + 1
                if _abFovFrame < 12 then return end
                _abFovFrame = 0
                blockBuzzingSound()
                local cam = workspace.CurrentCamera
                if cam and cam.FieldOfView ~= FORCE_FOV then cam.FieldOfView = FORCE_FOV end
            end)))
        end
        local function Disable()
            if not ab.running then return end
            ab.running = false
            restoreControls()
            disconnectAll()
        end

        _G.MeerkoSetAntiBeeDisco = function(on)
            Config.AntiBeeDisco = on
            if on then Enable() else Disable() end
        end
        if Config.AntiBeeDisco then task.delay(1, Enable) end
    end

    -- =================================================================
    -- ACTION KEYBINDS: Auto Clone (doClone) + Rejoin (TeleportService)
    -- =================================================================
    task.spawn(function()
        local UIS = game:GetService("UserInputService")
        local TS = game:GetService("TeleportService")
        UIS.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if UIS:GetFocusedTextBox() then return end
            local kn = input.KeyCode.Name
            if Config.CloneKey and Config.CloneKey ~= "" and kn == Config.CloneKey then
                task.spawn(function() pcall(doClone) end)
            elseif Config.RejoinKey and Config.RejoinKey ~= "" and kn == Config.RejoinKey then
                pcall(function()
                    local ok = pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, game.JobId, MK_LP) end)
                    if not ok then TS:Teleport(game.PlaceId, MK_LP) end
                end)
            elseif Config.LeaveKey and Config.LeaveKey ~= "" and kn == Config.LeaveKey then
                -- same kick as auto-kick-on-steal: shut the server down, fall back to self-kick
                local ok = pcall(function() game:Shutdown() end)
                if not ok then pcall(function() MK_LP:Kick("") end) end
            elseif Config.ResetKey and Config.ResetKey ~= "" and kn == Config.ResetKey then
                if _G.MeerkoInstaReset then
                    task.spawn(function() pcall(_G.MeerkoInstaReset) end)
                end
            elseif Config.CarpetSpeedKey and Config.CarpetSpeedKey ~= "" and kn == Config.CarpetSpeedKey then
                if _G.MeerkoSetCarpetSpeed then _G.MeerkoSetCarpetSpeed(not (Config.CarpetSpeed == true)) end
            elseif Config.BrainrotDropKey and Config.BrainrotDropKey ~= "" and kn == Config.BrainrotDropKey then
                task.spawn(function()
                    pcall(function()
                        local flinging = true
                        task.delay(0.3, function() flinging = false end)
                        while flinging do
                            MK_Run.Heartbeat:Wait()
                            local character = MK_LP.Character
                            local hum = character and character:FindFirstChildOfClass("Humanoid")
                            local root = hum and hum.RootPart
                            local realRoot = _G.MeerkoInvisOldHRP
                            while flinging and not (character and character.Parent and root and root.Parent) do
                                MK_Run.Heartbeat:Wait()
                                character = MK_LP.Character
                                hum = character and character:FindFirstChildOfClass("Humanoid")
                                root = hum and hum.RootPart
                                realRoot = _G.MeerkoInvisOldHRP
                            end
                            if not (root and root.Parent) then break end
                            local vel = root.Velocity
                            root.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)
                            if realRoot and realRoot.Parent then
                                realRoot.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)
                            end
                            MK_Run.RenderStepped:Wait()
                            if character and character.Parent and root and root.Parent then
                                root.Velocity = vel
                                if realRoot and realRoot.Parent then realRoot.Velocity = vel end
                            end
                            MK_Run.Stepped:Wait()
                            if character and character.Parent and root and root.Parent then
                                root.Velocity = vel + Vector3.new(0, 0.1, 0)
                                if realRoot and realRoot.Parent then realRoot.Velocity = vel + Vector3.new(0, 0.1, 0) end
                            end
                        end
                        local character = MK_LP.Character
                        local hum = character and character:FindFirstChildOfClass("Humanoid")
                        local root = hum and hum.RootPart
                        local realRoot = _G.MeerkoInvisOldHRP
                        if root and root.Parent then root.Velocity = Vector3.new(0, 0, 0) end
                        if realRoot and realRoot.Parent then realRoot.Velocity = Vector3.new(0, 0, 0) end
                    end)
                end)
            elseif Config.ItemDropKey and Config.ItemDropKey ~= "" and kn == Config.ItemDropKey then
                task.spawn(function()
                    pcall(function()
                        local flinging = true
                        task.delay(0.3, function() flinging = false end)

                        while flinging do
                            MK_Run.Heartbeat:Wait()
                            local character = MK_LP.Character
                            local hum = character and character:FindFirstChildOfClass("Humanoid")
                            local root = hum and hum.RootPart

                            while flinging and not (character and character.Parent and root and root.Parent) do
                                MK_Run.Heartbeat:Wait()
                                character = MK_LP.Character
                                hum = character and character:FindFirstChildOfClass("Humanoid")
                                root = hum and hum.RootPart
                            end
                            if not (root and root.Parent) then break end

                            local vel = root.Velocity
                            root.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)

                            MK_Run.RenderStepped:Wait()
                            if character and character.Parent and root and root.Parent then
                                root.Velocity = vel
                            end

                            MK_Run.Stepped:Wait()
                            if character and character.Parent and root and root.Parent then
                                root.Velocity = vel + Vector3.new(0, 0.1, 0)
                            end
                        end

                        local character = MK_LP.Character
                        local hum = character and character:FindFirstChildOfClass("Humanoid")
                        local root = hum and hum.RootPart
                        if root and root.Parent then root.Velocity = Vector3.new(0, 0, 0) end
                    end)
                end)
            elseif Config.AutoBuyKey and Config.AutoBuyKey ~= "" and kn == Config.AutoBuyKey then
                if _G.MeerkoToggleAutoBuy then pcall(_G.MeerkoToggleAutoBuy) end
            elseif Config.CancelTPKey and Config.CancelTPKey ~= "" and kn == Config.CancelTPKey then
                _G.MeerkoTPCancel = true
            end
        end)
    end)

    local function runAutoTPOnce()
        task.spawn(function()
            if not Config.AutoTeleport then return end
            local _t0 = os.clock()           -- wait briefly for a scannable target
            repeat
                local ok, pets = pcall(scanAllPets)
                if ok and pets and #pets > 0 then break end
                task.wait(0.3)
            until os.clock() - _t0 > 10
            local busy = false
            pcall(function() busy = isTeleporting end)
            if Config.AutoTeleport and not busy and not MK_LP:GetAttribute("Stealing") then
                pcall(doVelocityTP)
            end
        end)
    end
    _G.MeerkoRunAutoTP = runAutoTPOnce
    -- Option: "TP Back On Hit" -- when we take damage, go back to the brainrot,
    -- but ONLY if we got knocked OUTSIDE the base. If we're still inside the base
    -- (near the brainrot) we stay put. Off by default (Config.TPBackOnHit).
    do
        local Workspace = MK_Workspace
        local BASE_RADIUS = 55   -- within this of a plot pivot counts as "inside the base"
        local function isInsideBase()
            local char = MK_LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local plots = Workspace:FindFirstChild("Plots")
            if not (hrp and plots) then return false end
            for _, plot in ipairs(plots:GetChildren()) do
                local ok, pp = pcall(function() return plot:GetPivot().Position end)
                if ok then
                    local d = math.sqrt((hrp.Position.X - pp.X) ^ 2 + (hrp.Position.Z - pp.Z) ^ 2)
                    if d < BASE_RADIUS then return true end
                end
            end
            return false
        end

        local function hookHumanoid(char)
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
            if not hum then return end
            local lastHealth = hum.Health
            local lastTP = 0
            hum.HealthChanged:Connect(function(h)
                local dropped = h < lastHealth - 0.001
                lastHealth = h
                if not dropped then return end
                if not Config.TPBackOnHit then return end        -- option is off
                if MK_LP:GetAttribute("Stealing") == true then return end
                if isInsideBase() then return end                 -- inside base: stay put
                local now = os.clock()
                if now - lastTP < 1.5 then return end             -- small cooldown
                lastTP = now
                task.spawn(function() if _G.VanishStartSideTP then pcall(_G.VanishStartSideTP) end end)
            end)
        end
        if MK_LP.Character then task.spawn(hookHumanoid, MK_LP.Character) end
        MK_LP.CharacterAdded:Connect(function(char) task.wait(0.2); pcall(hookHumanoid, char) end)
    end

    -- =================================================================
    -- BASE TIMER  (Visuals): while you're inside a base with this on, expose
    -- the time until that base's lock opens (shown on the status pill header).
    -- =================================================================
    task.spawn(function()
        local Workspace = MK_Workspace
        _G.MeerkoBaseTimer = _G.MeerkoBaseTimer or { active = false, remaining = 0 }
        -- 0.25s -> 0.5s: BaseTimer iterates ALL plots to find which one the
        -- player is in. 2Hz is plenty for a countdown display.
        while true do
            task.wait(0.5)
            local active, rem = false, 0
            if Config.BaseTimer then
                local char = MK_LP.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local plots = Workspace:FindFirstChild("Plots")
                if hrp and plots then
                    -- find the plot the player is standing in (nearest pivot, in range)
                    local best, bestD = nil, 55
                    for _, plot in ipairs(plots:GetChildren()) do
                        local ok, pp = pcall(function() return plot:GetPivot().Position end)
                        if ok then
                            local d = math.sqrt((hrp.Position.X - pp.X) ^ 2 + (hrp.Position.Z - pp.Z) ^ 2)
                            if d < bestD then bestD = d; best = plot end
                        end
                    end
                    if best then
                        local ok, endT = pcall(function()
                            local ch = getPlotChannel(best.Name)
                            return ch and channelGet(ch, "BlockEndTime")
                        end)
                        if ok and type(endT) == "number" then
                            local r = endT - Workspace:GetServerTimeNow()
                            if r > 0 then rem = r; active = true end
                        end
                    end
                end
            end
            _G.MeerkoBaseTimer.active = active
            _G.MeerkoBaseTimer.remaining = rem
        end
    end)

    -- =================================================================
    -- STATUS PILL  (top-middle): brand - [desync] - [base timer] - FPS - PING
    -- =================================================================
    task.spawn(function()
        local RunService = MK_Run
        local Stats = game:GetService("Stats")

        local sg = Instance.new("ScreenGui")
        sg.Name = "MeerkoStatusPill"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder = 55
        do
            local _cr = cloneref or function(x) return x end
            pcall(function() sg.Parent = _cr(game:GetService("CoreGui")) end)
            if not sg.Parent then sg.Parent = MK_PlayerGui end
        end

        -- ===== chopper_hub header badge (compact, menu-themed) =====
        local TweenService = game:GetService("TweenService")

        -- palette (matches the menu / admin panel)
        local COL_BG     = Color3.fromRGB(30, 32, 44)
        local COL_CARD   = Color3.fromRGB(43, 46, 60)
        local COL_ACCENT = Color3.fromRGB(142, 148, 255)
        local COL_BRAND  = Color3.fromRGB(245, 247, 252)
        local COL_MUTED  = Color3.fromRGB(150, 155, 178)
        local COL_PILL   = Color3.fromRGB(56, 60, 80)
        local GOOD = Color3.fromRGB(100, 220, 140)
        local MID  = Color3.fromRGB(245, 205, 70)
        local BAD  = Color3.fromRGB(240, 90, 100)

        local function corner(parent, r)
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = parent; return c
        end
        local function stroke(parent, color, thick, trans)
            local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = thick or 1; s.Transparency = trans or 0
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = parent; return s
        end

        -- root card (fixed, compact)
        local CARD_W, CARD_H = 150, 74
        local root = Instance.new("Frame")
        root.Name = "ChopperHubBadge"
        root.AnchorPoint = Vector2.new(0.5, 0)
        root.Position = UDim2.new(0.5, 0, 0, 12)
        root.Size = UDim2.fromOffset(CARD_W, CARD_H)
        root.BackgroundColor3 = COL_CARD
        root.BorderSizePixel = 0
        root.Parent = sg
        corner(root, 14)
        stroke(root, Color3.fromRGB(118, 125, 154), 1, 0.2)

        -- soft accent glow behind the card
        local glow = Instance.new("ImageLabel")
        glow.Name = "Glow"; glow.BackgroundTransparency = 1
        glow.Image = "rbxassetid://6014261993"; glow.ScaleType = Enum.ScaleType.Slice
        glow.SliceCenter = Rect.new(49, 49, 463, 463)
        glow.ImageColor3 = COL_ACCENT; glow.ImageTransparency = 0.6
        glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
        glow.Size = UDim2.new(1, 32, 1, 32); glow.ZIndex = 0; glow.Parent = root

        local cardGrad = Instance.new("UIGradient")
        cardGrad.Rotation = 90
        cardGrad.Color = ColorSequence.new(COL_CARD, COL_BG)
        cardGrad.Parent = root

        -- brand wordmark
        local brand = Instance.new("TextLabel")
        brand.Name = "Brand"; brand.BackgroundTransparency = 1
        brand.AnchorPoint = Vector2.new(0.5, 0); brand.Position = UDim2.new(0.5, 0, 0, 8)
        brand.Size = UDim2.fromOffset(CARD_W - 16, 16)
        brand.Font = Enum.Font.GothamBold; brand.Text = "chopper_hub"
        brand.TextSize = 13; brand.TextColor3 = COL_BRAND
        brand.TextXAlignment = Enum.TextXAlignment.Center; brand.ZIndex = 2; brand.Parent = root
        do local g = Instance.new("UIGradient", brand); g.Color = ColorSequence.new(Color3.fromRGB(176, 180, 255), Color3.fromRGB(200, 164, 255)) end

        -- optional base-timer sub-line (hidden unless active)
        local timerLbl = Instance.new("TextLabel")
        timerLbl.Name = "Timer"; timerLbl.BackgroundTransparency = 1
        timerLbl.AnchorPoint = Vector2.new(0.5, 0); timerLbl.Position = UDim2.new(0.5, 0, 0, 25)
        timerLbl.Size = UDim2.fromOffset(CARD_W - 16, 11)
        timerLbl.Font = Enum.Font.GothamMedium; timerLbl.Text = ""
        timerLbl.TextSize = 10; timerLbl.TextColor3 = COL_MUTED
        timerLbl.TextXAlignment = Enum.TextXAlignment.Center; timerLbl.Visible = false; timerLbl.ZIndex = 2; timerLbl.Parent = root

        -- two mini stat pills
        local PILL_W, PILL_H, PILL_GAP = 64, 26, 4
        local function makePill(xOffset, labelText)
            local pill = Instance.new("Frame")
            pill.Size = UDim2.fromOffset(PILL_W, PILL_H)
            pill.AnchorPoint = Vector2.new(0.5, 1); pill.Position = UDim2.new(0.5, xOffset, 1, -8)
            pill.BackgroundColor3 = COL_PILL; pill.BorderSizePixel = 0; pill.ZIndex = 2; pill.Parent = root
            corner(pill, 9); stroke(pill, Color3.fromRGB(96, 103, 128), 1, 0.35)
            local key = Instance.new("TextLabel")
            key.BackgroundTransparency = 1; key.Size = UDim2.new(1, -8, 0, 9); key.Position = UDim2.new(0, 4, 0, 2)
            key.Font = Enum.Font.GothamMedium; key.Text = labelText; key.TextSize = 8; key.TextColor3 = COL_MUTED
            key.TextXAlignment = Enum.TextXAlignment.Center; key.ZIndex = 3; key.Parent = pill
            local val = Instance.new("TextLabel")
            val.BackgroundTransparency = 1; val.Size = UDim2.new(1, -8, 0, 13); val.Position = UDim2.new(0, 4, 0, 11)
            val.Font = Enum.Font.GothamBold; val.Text = "--"; val.TextSize = 13; val.TextColor3 = COL_BRAND
            val.TextXAlignment = Enum.TextXAlignment.Center; val.ZIndex = 3; val.Parent = pill
            return val
        end
        local halfStep = (PILL_W + PILL_GAP) / 2
        local fpsVal  = makePill(-halfStep, "FPS")
        local pingVal = makePill( halfStep, "PING")

        local function fpsColor(f) if f >= 50 then return GOOD elseif f >= 30 then return MID else return BAD end end
        local function pingColor(p) if p <= 80 then return GOOD elseif p <= 160 then return MID else return BAD end end

        local frames, accum, smoothFps, smoothPing = 0, 0, 60, 0
        RunService.RenderStepped:Connect(function(dt)
            frames += 1; accum += dt
            local ok, p = pcall(function() return Stats.Network.ServerStatsItem["Network Ping"]:GetValue() end)
            if ok and type(p) == "number" then smoothPing = smoothPing + (p - smoothPing) * 0.1 end
            if accum >= 0.5 then
                smoothFps = smoothFps + ((frames / accum) - smoothFps) * 0.6
                frames = 0; accum = 0
                local fps = math.clamp(math.floor(smoothFps + 0.5), 0, 999)
                fpsVal.Text = tostring(fps); fpsVal.TextColor3 = fpsColor(fps)
                local ping = math.floor(smoothPing)
                pingVal.Text = tostring(ping); pingVal.TextColor3 = pingColor(ping)
                local bt = _G.MeerkoBaseTimer
                if type(bt) == "table" and bt.active and type(bt.remaining) == "number" then
                    timerLbl.Text = "Base " .. tostring(math.ceil(bt.remaining)) .. "s"; timerLbl.Visible = true
                else
                    timerLbl.Visible = false
                end
            end
        end)

        -- gentle accent glow pulse
        pcall(function()
            TweenService:Create(glow, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = 0.8 }):Play()
        end)
    end)

    -- =================================================================
    -- FEATURES TOGGLE PANEL  (matches the Meerko TP panel styling)
    -- =================================================================
    task.spawn(function()
        local UIS = game:GetService("UserInputService")
        local TweenService = game:GetService("TweenService")
        local PlayerGui = MK_PlayerGui

        -- Colors mirror the Figma design system (monochrome white-opacity states).
        local C_BG       = Color3.fromRGB(10, 14, 26)      -- panel: deep navy
        local C_BORDER   = Color3.fromRGB(55, 72, 110)
        local FONT       = Enum.Font.BuilderSans           -- closest built-in to Suisse Intl
        local WHITE      = Color3.fromRGB(255, 255, 255)
        local DARK       = Color3.fromRGB(18, 26, 46)      -- navy module background
        local BOX_ON     = Color3.fromRGB(28, 48, 85)     -- enabled highlight (navy-blue overlay)
        local CAT_COL    = Color3.fromRGB(115, 130, 160)

        local GROUPS = {
            { title = "MAIN", items = {
                { key = "InfiniteJump",    label = "Infinite Jump" },
            }},
            { title = "ANTI", items = {
                { key = "AntiRagdoll",        label = "Anti Ragdoll" },
                { key = "AntiBeeDisco",       label = "Anti Bee & Disco" },
            }},
            { title = "VISUALS", items = {
                { key = "BrainrotESP",     label = "Brainrot ESP" },
                { key = "SubspaceMineESP", label = "Subspace Mine ESP" },
                { key = "LineToBase",      label = "Line to Base" },
                { key = "LineToBrainrot",  label = "Line to Best Brainrot" },
                { key = "BaseTimer",       label = "Base Timer" },
            }},
            { title = "SERVER", items = {
                { key = "AutoKickOnSteal", label = "Auto-Kick on Steal" },
                { key = "AutoBuyCarpet",   label = "Auto Buy Carpet" },
            }},
            { title = "MISC", items = {
                { key = "ShowAdminPanel",  label = "Admin Panel" },
                { key = "Animations",      label = "Animations" },
                { key = "FPSBoost",        label = "FPS Boost" },
                { key = "UnlockButtons",   label = "Base Unlock Buttons" },
            }},
        }

        local function applyToggle(key, val)
            Config[key] = val
            SaveConfig()
            if key == "LineToBase" then
                if val then if _G.createPlotBeam then pcall(_G.createPlotBeam) end
                else if _G.resetPlotBeam then pcall(_G.resetPlotBeam) end end
            elseif key == "SubspaceMineESP" and _G.MeerkoSubspaceSet then
                _G.MeerkoSubspaceSet(val)
            elseif key == "InvisOnSteal" then
                if val then if _G.VanishInvisAutoStart then pcall(_G.VanishInvisAutoStart) end
                else if _G.VanishInvisAutoStop then pcall(_G.VanishInvisAutoStop) end end
            elseif key == "AutoBuyCarpet" then
                if _G.MeerkoAutoBuyCarpet then pcall(_G.MeerkoAutoBuyCarpet, val) end
            elseif key == "BrainrotESP" and _G.MeerkoBrainrotESPSet then
                _G.MeerkoBrainrotESPSet(val)
            elseif key == "InfiniteJump" and _G.MeerkoSetInfiniteJump then
                _G.MeerkoSetInfiniteJump(val)
            elseif key == "AntiBeeDisco" and _G.MeerkoSetAntiBeeDisco then
                _G.MeerkoSetAntiBeeDisco(val)
            elseif key == "Animations" then
                _G.MeerkoAnimations = val
                local ch = MK_LP.Character
                if ch then
                    if val then if _G.MeerkoRestoreAnims then pcall(_G.MeerkoRestoreAnims, ch) end
                    else if _G.MeerkoKillAnims then pcall(_G.MeerkoKillAnims, ch) end end
                end
            elseif key == "ShowAdminPanel" and _G.MeerkoSetAdminPanel then
                _G.MeerkoSetAdminPanel(val)
            elseif key == "LineToBrainrot" and _G.MeerkoBrainrotBeamSet then
                _G.MeerkoBrainrotBeamSet(val)
            elseif key == "FPSBoost" and _G.MeerkoSetFPSBoost then
                _G.MeerkoSetFPSBoost(val)
            elseif key == "UnlockButtons" and _G.MeerkoSetUnlockButtons then
                _G.MeerkoSetUnlockButtons(val)
            end
        end

        local HEAD_H = 14
        local CAT_H  = 24
        local ROW_H  = 34
        local PAD    = 6
        local _children, _body = 0, 0
        for _, g in ipairs(GROUPS) do
            _children = _children + 1 + #g.items
            _body = _body + CAT_H + #g.items * ROW_H
        end
        local panelH = HEAD_H + _body + (_children - 1) * PAD + 12

        local sg = Instance.new("ScreenGui")
        sg.Name = "FeaturesPanel"
        sg.ResetOnSpawn = false
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Enabled = false  -- legacy UI permanently hidden; new FreeGUI replaces it
        local _cloneref = cloneref or function(x) return x end
        pcall(function() sg.Parent = _cloneref(game:GetService("CoreGui")) end)
        if not sg.Parent then sg.Parent = PlayerGui end

        local mf = Instance.new("Frame")
        mf.Size = UDim2.new(0, 240, 0, panelH)
        mf.Position = UDim2.new(0, Config._featPanelX or 300, 0, Config._featPanelY or 80)
        mf.BackgroundColor3 = C_BG
        mf.BackgroundTransparency = 0.1
        mf.BorderSizePixel = 0
        mf.Parent = sg
        Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 12)
        local mfStroke = Instance.new("UIStroke", mf)   -- Figma "White 4%" stroke
        mfStroke.Color = WHITE; mfStroke.Thickness = 1; mfStroke.Transparency = 0.96
        do  -- slight soft drop shadow around the whole panel
            local ps = Instance.new("ImageLabel")
            ps.Name = "PanelShadow"; ps.BackgroundTransparency = 1
            ps.Image = "rbxassetid://6014261993"; ps.ScaleType = Enum.ScaleType.Slice
            ps.SliceCenter = Rect.new(49, 49, 463, 463); ps.ImageColor3 = Color3.fromRGB(0, 0, 0)
            ps.ImageTransparency = 0.62
            ps.AnchorPoint = Vector2.new(0.5, 0.5); ps.Position = UDim2.new(0.5, 0, 0.5, 0)
            ps.Size = UDim2.new(1, 44, 1, 44); ps.ZIndex = 0
            ps.Parent = mf
        end

        -- drag handle (thin grab strip above the tabs, replaces the old title bar)
        local dragHandle = Instance.new("Frame", mf)
        dragHandle.Size = UDim2.new(1, 0, 0, HEAD_H)
        dragHandle.Position = UDim2.new(0, 0, 0, 0)
        dragHandle.BackgroundTransparency = 1
        dragHandle.Active = true

        -- drag
        local dg, ds, sp = false, nil, nil
        dragHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dg = true; ds = input.Position
                sp = UDim2.new(0, mf.AbsolutePosition.X, 0, mf.AbsolutePosition.Y)
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dg = false
                        Config._featPanelX = mf.Position.X.Offset
                        Config._featPanelY = mf.Position.Y.Offset
                        SaveConfig()
                    end
                end)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - ds
                local newX = sp.X.Offset + d.X
                local newY = sp.Y.Offset + d.Y
                local vp = workspace.CurrentCamera.ViewportSize
                newX = math.clamp(newX, 0, vp.X - mf.AbsoluteSize.X)
                newY = math.clamp(newY, 0, vp.Y - mf.AbsoluteSize.Y)
                mf.Position = UDim2.new(0, newX, 0, newY)
            end
        end)

        -- ===== TABS: "Main" + "More" + "Custom" =======
        local W = 240
        local TAB_H = 26
        local TAB_GAP = 10
        local TAB_ROWS_H = TAB_H * 2 + 8
        local CONTENT_Y = HEAD_H + TAB_ROWS_H + TAB_GAP + 9

        local tabBar = Instance.new("Frame", mf)
        tabBar.Size = UDim2.new(1, -24, 0, TAB_ROWS_H)
        tabBar.Position = UDim2.new(0, 12, 0, HEAD_H)
        tabBar.BackgroundTransparency = 1

        local div = Instance.new("Frame", mf)
        div.Size = UDim2.new(1, 0, 0, 1)
        div.Position = UDim2.new(0, 0, 0, HEAD_H + TAB_ROWS_H + TAB_GAP)
        div.BackgroundColor3 = WHITE
        div.BackgroundTransparency = 0.92
        div.BorderSizePixel = 0

        local function makeContent()
            local cg = Instance.new("CanvasGroup", mf)
            cg.Size = UDim2.new(1, -24, 0, 0)
            cg.AutomaticSize = Enum.AutomaticSize.Y
            cg.Position = UDim2.new(0, 12, 0, CONTENT_Y)
            cg.BackgroundTransparency = 1
            cg.BorderSizePixel = 0
            local lay = Instance.new("UIListLayout", cg)
            lay.Padding = UDim.new(0, PAD)
            lay.SortOrder = Enum.SortOrder.LayoutOrder
            -- tiny inset so row outlines aren't clipped by the CanvasGroup edges
            local cgPad = Instance.new("UIPadding", cg)
            cgPad.PaddingLeft = UDim.new(0, 2); cgPad.PaddingRight = UDim.new(0, 2)
            return cg, lay
        end
        local host1, layout1 = makeContent()
        local host2, layout2 = makeContent()
        local host3, layout3 = makeContent()
        host2.Visible = false; host2.GroupTransparency = 1
        host3.Visible = false; host3.GroupTransparency = 1

        local hosts   = { host1, host2, host3 }
        local layouts = { layout1, layout2, layout3 }

        local activeTab = 1
        local TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local function activeLayout() return layouts[activeTab] end
        local function targetHeight() return CONTENT_Y + activeLayout().AbsoluteContentSize.Y + 12 end

        for i, lay in ipairs(layouts) do
            lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                if activeTab == i then mf.Size = UDim2.new(0, W, 0, targetHeight()) end
            end)
        end

        local tabBtns = {}
        local function paintTabs()
            for i, b in ipairs(tabBtns) do
                local on = (i == activeTab)
                b.BackgroundColor3 = on and Color3.fromRGB(40, 56, 92) or DARK
                b.TextTransparency = on and 0.0 or 0.2
                local st = b:FindFirstChildOfClass("UIStroke"); if st then st.Transparency = 0.96 end
            end
        end
        local function setTab(n, animate)
            local newCG = hosts[n]
            activeTab = n
            newCG.Visible = true
            paintTabs()
            if animate then
                TweenService:Create(mf, TWEEN, { Size = UDim2.new(0, W, 0, targetHeight()) }):Play()
                TweenService:Create(newCG, TWEEN, { GroupTransparency = 0 }):Play()
                for i, h in ipairs(hosts) do
                    if i ~= n then
                        local fade = TweenService:Create(h, TWEEN, { GroupTransparency = 1 })
                        fade:Play()
                        fade.Completed:Once(function()
                            if activeTab ~= i then h.Visible = false end
                        end)
                    end
                end
            else
                newCG.GroupTransparency = 0
                for i, h in ipairs(hosts) do
                    if i ~= n then h.GroupTransparency = 1; h.Visible = false end
                end
                mf.Size = UDim2.new(0, W, 0, targetHeight())
            end
        end

        local function makeTabBtn(text, idx, x, y, w)
            local b = Instance.new("TextButton", tabBar)
            b.Size = UDim2.new(0, w, 0, TAB_H); b.Position = UDim2.new(0, x, 0, y)
            b.AutoButtonColor = false; b.BackgroundColor3 = DARK; b.BackgroundTransparency = 0.12; b.BorderSizePixel = 0
            b.Selectable = false
            b.Text = text; b.Font = Enum.Font.GothamMedium; b.TextSize = 12; b.TextColor3 = WHITE
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
            local st = Instance.new("UIStroke", b); st.Color = WHITE; st.Thickness = 1; st.Transparency = 0.96
            tabBtns[idx] = b
            b.MouseButton1Click:Connect(function() setTab(idx, true) end)
        end
        local _halfW = (W - 24 - 6) / 2
        makeTabBtn("Main", 1, 0, 0, _halfW)
        makeTabBtn("More", 2, _halfW + 6, 0, _halfW)
        makeTabBtn("Custom", 3, 0, TAB_H + 8, W - 24)

        local _order = 0

        -- category sub-header (uppercase, dim)
        local function addCategory(host, text)
            _order = _order + 1
            local c = Instance.new("TextLabel", host)
            c.Size = UDim2.new(1, 0, 0, CAT_H)
            c.BackgroundTransparency = 1
            c.Text = string.upper(text)
            c.TextColor3 = WHITE
            c.TextSize = 11
            c.Font = FONT
            c.TextXAlignment = Enum.TextXAlignment.Left
            c.TextYAlignment = Enum.TextYAlignment.Bottom
            c.LayoutOrder = _order
            local pad = Instance.new("UIPadding", c)
            pad.PaddingBottom = UDim.new(0, 4)
            pad.PaddingLeft = UDim.new(0, 2)
        end

        local shadowLayer = Instance.new("Frame")
        shadowLayer.Name = "ShadowLayer"
        shadowLayer.BackgroundTransparency = 1
        shadowLayer.BorderSizePixel = 0
        shadowLayer.Size = UDim2.new(1, 0, 1, 0)
        shadowLayer.ZIndex = 0
        shadowLayer.Parent = mf
        local _shadowsByHost = {}
        local SHADOW_BASE_T = 0.32
        local function addCardShadow(card, host, baseT, pad)
            baseT = baseT or SHADOW_BASE_T
            pad = pad or 16
            local sh = Instance.new("ImageLabel")
            sh.Name = "CardShadow"
            sh.BackgroundTransparency = 1
            sh.Image = "rbxassetid://6014261993"
            sh.ScaleType = Enum.ScaleType.Slice
            sh.SliceCenter = Rect.new(49, 49, 463, 463)
            sh.ImageColor3 = Color3.fromRGB(0, 0, 0)
            sh.ImageTransparency = baseT
            sh.ZIndex = 0
            sh.Parent = shadowLayer
            local function upd()
                if not card.Parent then return end
                local m = mf.AbsolutePosition
                sh.Position = UDim2.new(0, card.AbsolutePosition.X - m.X - pad, 0, card.AbsolutePosition.Y - m.Y - pad)
                sh.Size = UDim2.new(0, card.AbsoluteSize.X + pad * 2, 0, card.AbsoluteSize.Y + pad * 2)
            end
            local function vis()
                if host then
                    sh.Visible = host.Visible
                    sh.ImageTransparency = baseT + (1 - baseT) * host.GroupTransparency
                else
                    sh.Visible = true
                    sh.ImageTransparency = baseT
                end
            end
            upd(); vis()
            card:GetPropertyChangedSignal("AbsolutePosition"):Connect(upd)
            card:GetPropertyChangedSignal("AbsoluteSize"):Connect(upd)
            if host then
                host:GetPropertyChangedSignal("Visible"):Connect(vis)
                host:GetPropertyChangedSignal("GroupTransparency"):Connect(vis)
            end
            local key = host or "static"
            local list = _shadowsByHost[key]; if not list then list = {}; _shadowsByHost[key] = list end
            table.insert(list, sh)
        end
        -- very subtle drop shadow for a text header: a dark, 1px-offset copy of
        -- the text placed behind it (in the same CanvasGroup, so it fades too).
        local function addHeaderTextShadow(card)
            local lbl = card:IsA("TextLabel") and card or card:FindFirstChildWhichIsA("TextLabel")
            if not lbl or lbl:FindFirstChild("TextShadow") then return end
            local sh = Instance.new("TextLabel")
            sh.Name = "TextShadow"
            sh.BackgroundTransparency = 1
            sh.Size = UDim2.new(1, 0, 1, 0)
            sh.Position = UDim2.new(0, 2, 0, 2)
            sh.Font = lbl.Font
            sh.TextSize = lbl.TextSize
            sh.Text = lbl.Text
            sh.RichText = lbl.RichText
            sh.TextColor3 = Color3.fromRGB(0, 0, 0)
            sh.TextTransparency = 0.42
            sh.TextXAlignment = lbl.TextXAlignment
            sh.TextYAlignment = lbl.TextYAlignment
            sh.ZIndex = lbl.ZIndex - 1
            sh.Parent = lbl
        end
        -- (re)build the shadows for a tab; clears any existing ones first
        local function applyTabShadows(host)
            local list = _shadowsByHost[host]
            if list then for _, s in ipairs(list) do pcall(function() s:Destroy() end) end end
            _shadowsByHost[host] = {}
            for _, ch in ipairs(host:GetChildren()) do
                if (ch:IsA("Frame") or ch:IsA("TextButton") or ch:IsA("TextLabel"))
                    and ch.Size.Y.Offset >= 20 and ch.Size.Y.Offset <= 45
                    and ch.Name ~= "ActionBar" and ch.Name ~= "EmptyState" then
                    if ch.Size.Y.Offset > 26 then   -- feature rows only; headers get no shadow
                        addCardShadow(ch, host)
                    end
                end
            end
        end

        local function addRow(host, def)
            _order = _order + 1
            local row = Instance.new("TextButton", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.AutoButtonColor = false
            row.Text = ""
            row.BackgroundColor3 = DARK
            row.BackgroundTransparency = 0.12
            row.BorderSizePixel = 0
            row.LayoutOrder = _order
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rstroke = Instance.new("UIStroke", row)   -- Figma "White 4%" outline
            rstroke.Color = WHITE; rstroke.Thickness = 1; rstroke.Transparency = 0.96

            local dots = Instance.new("TextLabel", row)
            dots.Size = UDim2.new(0, 10, 1, 0)
            dots.Position = UDim2.new(0, 12, 0, 0)
            dots.BackgroundTransparency = 1
            dots.Text = "⋮⋮"
            dots.TextColor3 = WHITE
            dots.TextTransparency = 0.52
            dots.TextSize = 12
            dots.Font = FONT
            dots.TextXAlignment = Enum.TextXAlignment.Center
            dots.TextYAlignment = Enum.TextYAlignment.Center

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -66, 1, 0)
            lbl.Position = UDim2.new(0, 28, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = def.label
            lbl.TextColor3 = WHITE
            lbl.TextTransparency = 0.52
            lbl.TextSize = 12
            lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.TextTruncate = Enum.TextTruncate.AtEnd

            -- toggler: 20x12 track, 8x8 knob (Figma "toggler")
            local sw = Instance.new("Frame", row)   -- visual; the whole box is the button
            sw.Size = UDim2.new(0, 20, 0, 12)
            sw.Position = UDim2.new(1, -32, 0.5, -6)
            sw.BackgroundColor3 = WHITE
            sw.BackgroundTransparency = 0.88
            sw.BorderSizePixel = 0
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

            local knob = Instance.new("Frame", sw)
            knob.Size = UDim2.new(0, 8, 0, 8)
            knob.BackgroundColor3 = WHITE
            knob.BackgroundTransparency = 0.76
            knob.BorderSizePixel = 0
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

            local ON_POS, OFF_POS = UDim2.new(1, -10, 0.5, -4), UDim2.new(0, 2, 0.5, -4)
            -- Smooth, no flash: the box stays dark; only the border, text,
            -- glow and toggler cross-fade (no dark->white colour tween).
            local TI = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
            -- outline stays a constant White 4% (rstroke) in all states; enabled
            -- is signalled by the box highlight + text + toggler only.
            local function setToggle(on, animate)
                local boxC = on and BOX_ON or DARK   -- enabled = highlighted box
                local txtT = on and 0.0  or 0.52     -- on: white; off: white 48%
                local trkT = on and 0.64 or 0.88     -- track: white 36% / white 12%
                local knbT = on and 0.0  or 0.76     -- knob: white / white 24%
                local pos  = on and ON_POS or OFF_POS
                if animate then
                    TweenService:Create(row,  TI, { BackgroundColor3 = boxC }):Play()
                    TweenService:Create(lbl,  TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(dots, TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(sw,   TI, { BackgroundTransparency = trkT }):Play()
                    TweenService:Create(knob, TI, { BackgroundTransparency = knbT, Position = pos }):Play()
                else
                    row.BackgroundColor3 = boxC
                    lbl.TextTransparency = txtT; dots.TextTransparency = txtT
                    sw.BackgroundTransparency = trkT; knob.BackgroundTransparency = knbT; knob.Position = pos
                end
            end
            setToggle(Config[def.key] == true, false)
            row.MouseButton1Click:Connect(function()
                local nv = not (Config[def.key] == true)
                setToggle(nv, true)
                task.spawn(function() pcall(applyToggle, def.key, nv) end)
            end)
        end

        -- Figma "slider": label + value header, 4px track, 36% fill, 6px white knob
        local function makeSlider(parent, labelText, minV, maxV, step, getVal, setVal, fmt)
            local holder = Instance.new("Frame", parent)
            holder.Size = UDim2.new(1, 0, 0, 30)
            holder.BackgroundTransparency = 1

            local hl = Instance.new("TextLabel", holder)
            hl.Size = UDim2.new(1, -54, 0, 14)
            hl.BackgroundTransparency = 1
            hl.Text = labelText
            hl.TextColor3 = WHITE; hl.TextTransparency = 0.0; hl.TextSize = 12; hl.Font = FONT
            hl.TextXAlignment = Enum.TextXAlignment.Left; hl.TextYAlignment = Enum.TextYAlignment.Center

            local vl = Instance.new("TextLabel", holder)
            vl.Size = UDim2.new(0, 54, 0, 14); vl.Position = UDim2.new(1, -54, 0, 0)
            vl.BackgroundTransparency = 1
            vl.TextColor3 = WHITE; vl.TextTransparency = 0.64; vl.TextSize = 12; vl.Font = FONT
            vl.TextXAlignment = Enum.TextXAlignment.Right; vl.TextYAlignment = Enum.TextYAlignment.Center

            local track = Instance.new("Frame", holder)
            track.Size = UDim2.new(1, 0, 0, 4); track.Position = UDim2.new(0, 0, 0, 22)
            track.BackgroundColor3 = WHITE; track.BackgroundTransparency = 0.96; track.BorderSizePixel = 0
            Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

            local fill = Instance.new("Frame", track)
            fill.BackgroundColor3 = WHITE; fill.BackgroundTransparency = 0.64; fill.BorderSizePixel = 0
            fill.Size = UDim2.new(0, 0, 1, 0)
            Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

            local knob = Instance.new("Frame", track)
            knob.Size = UDim2.new(0, 6, 0, 6); knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.BackgroundColor3 = WHITE; knob.BackgroundTransparency = 0; knob.BorderSizePixel = 0
            knob.ZIndex = 2
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

            local function refresh()
                local v = getVal()
                local frac = math.clamp((v - minV) / (maxV - minV), 0, 1)
                fill.Size = UDim2.new(frac, 0, 1, 0)
                knob.Position = UDim2.new(frac, 0, 0.5, 0)
                vl.Text = fmt(v)
            end
            refresh()

            local dragging = false
            local hit = Instance.new("TextButton", track)
            hit.Size = UDim2.new(1, 0, 1, 12); hit.Position = UDim2.new(0, 0, 0, -6)
            hit.BackgroundTransparency = 1; hit.Text = ""; hit.ZIndex = 3
            local function apply(px)
                local tx, tw = track.AbsolutePosition.X, track.AbsoluteSize.X
                if tw <= 0 then return end
                local frac = math.clamp((px - tx) / tw, 0, 1)
                local raw = math.floor((minV + frac * (maxV - minV)) / step + 0.5) * step
                setVal(math.clamp(raw, minV, maxV))
                refresh()
            end
            hit.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    dragging = true; apply(i.Position.X)
                end
            end)
            UIS.InputChanged:Connect(function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    apply(i.Position.X)
                end
            end)
            UIS.InputEnded:Connect(function(i)
                if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and dragging then
                    dragging = false
                    if _G._stp_saveCurrent then _G._stp_saveCurrent() end
                end
            end)
            return holder
        end

        -- expandable Side TP module (Figma "Show Settings" variant). Fixed-size
        -- (no auto-layout on the box) so the gradient glow strips work cleanly.
        local function addTpModule(host)
            _order = _order + 1
            local SETTINGS_H = 154
            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.BackgroundColor3 = DARK; row.BackgroundTransparency = 0.12
            row.BorderSizePixel = 0; row.LayoutOrder = _order
            row.ClipsDescendants = true
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rs = Instance.new("UIStroke", row); rs.Color = WHITE; rs.Thickness = 1; rs.Transparency = 0.96; rs.Enabled = false

            local header = Instance.new("Frame", row)
            header.Size = UDim2.new(1, 0, 0, ROW_H); header.Position = UDim2.new(0, 0, 0, 0)
            header.BackgroundTransparency = 1

            local dots = Instance.new("TextLabel", header)
            dots.Size = UDim2.new(0, 10, 1, 0); dots.Position = UDim2.new(0, 12, 0, 0); dots.BackgroundTransparency = 1
            dots.Text = "⋮⋮"; dots.TextColor3 = WHITE; dots.TextSize = 12; dots.Font = FONT
            dots.TextXAlignment = Enum.TextXAlignment.Center; dots.TextYAlignment = Enum.TextYAlignment.Center

            local lbl = Instance.new("TextLabel", header)
            lbl.Size = UDim2.new(1, -96, 1, 0); lbl.Position = UDim2.new(0, 28, 0, 0); lbl.BackgroundTransparency = 1
            lbl.Text = "Auto Teleport"; lbl.TextColor3 = WHITE; lbl.TextSize = 12; lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center

            local chev = Instance.new("TextButton", header)
            chev.Size = UDim2.new(0, 20, 1, 0); chev.Position = UDim2.new(1, -26, 0, 0); chev.BackgroundTransparency = 1
            chev.AutoButtonColor = false; chev.Text = "›"; chev.TextColor3 = WHITE; chev.TextTransparency = 0.4; chev.TextSize = 18; chev.Font = FONT
            chev.TextXAlignment = Enum.TextXAlignment.Center; chev.TextYAlignment = Enum.TextYAlignment.Center

            -- on/off toggler (controls Config.AutoTeleport)
            local sw = Instance.new("TextButton", header)
            sw.Size = UDim2.new(0, 20, 0, 12); sw.Position = UDim2.new(1, -54, 0.5, -6)
            sw.AutoButtonColor = false; sw.Text = ""; sw.BackgroundColor3 = WHITE; sw.BackgroundTransparency = 0.88; sw.BorderSizePixel = 0
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
            local knob = Instance.new("Frame", sw)
            knob.Size = UDim2.new(0, 8, 0, 8); knob.BackgroundColor3 = WHITE; knob.BackgroundTransparency = 0.76; knob.BorderSizePixel = 0
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
            local TT = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
            local ON_POS, OFF_POS = UDim2.new(1, -10, 0.5, -4), UDim2.new(0, 2, 0.5, -4)
            local function setToggler(on, animate)
                local boxC = on and BOX_ON or DARK
                local txtT = on and 0.0 or 0.52
                local trkT = on and 0.64 or 0.88
                local knbT = on and 0.0 or 0.76
                local pos  = on and ON_POS or OFF_POS
                if animate then
                    TweenService:Create(row, TT, { BackgroundColor3 = boxC }):Play()
                    TweenService:Create(lbl, TT, { TextTransparency = txtT }):Play()
                    TweenService:Create(dots, TT, { TextTransparency = txtT }):Play()
                    TweenService:Create(sw, TT, { BackgroundTransparency = trkT }):Play()
                    TweenService:Create(knob, TT, { BackgroundTransparency = knbT, Position = pos }):Play()
                else
                    row.BackgroundColor3 = boxC
                    lbl.TextTransparency = txtT; dots.TextTransparency = txtT
                    sw.BackgroundTransparency = trkT; knob.BackgroundTransparency = knbT; knob.Position = pos
                end
            end
            setToggler(Config.AutoTeleport == true, false)
            sw.MouseButton1Click:Connect(function()
                local nv = not (Config.AutoTeleport == true)
                Config.AutoTeleport = nv
                SaveConfig()
                setToggler(nv, true)
                if nv and _G.MeerkoRunAutoTP then _G.MeerkoRunAutoTP() end  -- fire once on enable
            end)

            local settings = Instance.new("Frame", row)
            settings.Size = UDim2.new(1, 0, 0, SETTINGS_H); settings.Position = UDim2.new(0, 0, 0, ROW_H)
            settings.BackgroundTransparency = 1; settings.Visible = false
            local slay = Instance.new("UIListLayout", settings); slay.SortOrder = Enum.SortOrder.LayoutOrder; slay.Padding = UDim.new(0, 8)
            local spad = Instance.new("UIPadding", settings)
            spad.PaddingLeft = UDim.new(0, 12); spad.PaddingRight = UDim.new(0, 12)
            spad.PaddingTop = UDim.new(0, 2); spad.PaddingBottom = UDim.new(0, 12)

            makeSlider(settings, "Delay Before TP", 0, 0.9, 0.01,
                function() return tonumber(_G._stp_tpDelay) or 0 end,
                function(v) _G._stp_tpDelay = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
                function(v) return string.format("%dms", math.floor(v * 1000 + 0.5)) end)
            makeSlider(settings, "Landing Delay", 0.15, 0.75, 0.01,
                function() return tonumber(_G.LandingDelay) or 0.4 end,
                function(v) _G.LandingDelay = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
                function(v) return string.format("%.2fs", v) end)
            makeSlider(settings, "TP Velocity", 200, 500, 10,
                function() return tonumber(_G.TPVelocity) or 400 end,
                function(v) _G.TPVelocity = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
                function(v) return string.format("%d", v) end)

            local btnRow = Instance.new("Frame", settings)
            btnRow.Size = UDim2.new(1, 0, 0, 26); btnRow.BackgroundTransparency = 1
            local blay = Instance.new("UIListLayout", btnRow)
            blay.FillDirection = Enum.FillDirection.Horizontal; blay.Padding = UDim.new(0, 6); blay.SortOrder = Enum.SortOrder.LayoutOrder
            local function mkBtn(text, order2, cb)
                local b = Instance.new("TextButton", btnRow)
                b.Size = UDim2.new(0.5, -3, 1, 0); b.LayoutOrder = order2
                b.BackgroundColor3 = WHITE; b.BackgroundTransparency = 0.9; b.AutoButtonColor = false
                b.Text = text; b.TextColor3 = WHITE; b.TextTransparency = 0.05; b.TextSize = 12; b.Font = FONT; b.BorderSizePixel = 0
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
                b.MouseButton1Click:Connect(cb)
            end
            mkBtn("Manual TP", 1, function() task.spawn(function() if _G.VanishStartSideTP then _G.VanishStartSideTP() end end) end)
            mkBtn("Edit Priority", 2, function() if _G._stp_openPriority then _G._stp_openPriority() end end)

            local expanded = false
            local EI = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            chev.MouseButton1Click:Connect(function()
                expanded = not expanded
                if expanded then settings.Visible = true end   -- show before growing
                TweenService:Create(chev, EI, { Rotation = expanded and 90 or 0 }):Play()
                local h = expanded and (ROW_H + SETTINGS_H) or ROW_H
                local tw = TweenService:Create(row, EI, { Size = UDim2.new(1, 0, 0, h) })
                tw:Play()
                if not expanded then
                    tw.Completed:Once(function()
                        if not expanded then settings.Visible = false end
                    end)
                end
            end)
        end

        -- expandable Auto Steal module: header on/off toggler + radio (mode).
        local function addAutoStealModule(host)
            _order = _order + 1
            local OPTIONS = {
                { mode = "nearest",  label = "Nearest" },
                { mode = "highest",  label = "Highest" },
                { mode = "priority", label = "Priority" },
            }
            local SETTINGS_H = 92
            local lastMode = _G.MeerkoStealMode or "priority"
            local function isOn() return _G.MeerkoStealMode ~= nil end

            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.BackgroundColor3 = DARK; row.BackgroundTransparency = 0.12
            row.BorderSizePixel = 0; row.LayoutOrder = _order
            row.ClipsDescendants = true
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rstroke = Instance.new("UIStroke", row); rstroke.Color = WHITE; rstroke.Thickness = 1; rstroke.Transparency = 0.96; rstroke.Enabled = false

            local header = Instance.new("Frame", row)
            header.Size = UDim2.new(1, 0, 0, ROW_H); header.BackgroundTransparency = 1

            local dots = Instance.new("TextLabel", header)
            dots.Size = UDim2.new(0, 10, 1, 0); dots.Position = UDim2.new(0, 12, 0, 0); dots.BackgroundTransparency = 1
            dots.Text = "⋮⋮"; dots.TextColor3 = WHITE; dots.TextSize = 12; dots.Font = FONT
            dots.TextXAlignment = Enum.TextXAlignment.Center; dots.TextYAlignment = Enum.TextYAlignment.Center

            local lbl = Instance.new("TextLabel", header)
            lbl.Size = UDim2.new(1, -96, 1, 0); lbl.Position = UDim2.new(0, 28, 0, 0); lbl.BackgroundTransparency = 1
            lbl.Text = "Auto Steal"; lbl.TextColor3 = WHITE; lbl.TextSize = 12; lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center

            local chev = Instance.new("TextButton", header)
            chev.Size = UDim2.new(0, 20, 1, 0); chev.Position = UDim2.new(1, -26, 0, 0); chev.BackgroundTransparency = 1
            chev.AutoButtonColor = false; chev.Text = "›"; chev.TextColor3 = WHITE; chev.TextTransparency = 0.4
            chev.TextSize = 18; chev.Font = FONT
            chev.TextXAlignment = Enum.TextXAlignment.Center; chev.TextYAlignment = Enum.TextYAlignment.Center

            local sw = Instance.new("TextButton", header)
            sw.Size = UDim2.new(0, 20, 0, 12); sw.Position = UDim2.new(1, -54, 0.5, -6)
            sw.AutoButtonColor = false; sw.Text = ""; sw.BackgroundColor3 = WHITE; sw.BackgroundTransparency = 0.88; sw.BorderSizePixel = 0
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
            local knob = Instance.new("Frame", sw)
            knob.Size = UDim2.new(0, 8, 0, 8); knob.BackgroundColor3 = WHITE; knob.BackgroundTransparency = 0.76; knob.BorderSizePixel = 0
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

            local TI = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
            local ON_POS, OFF_POS = UDim2.new(1, -10, 0.5, -4), UDim2.new(0, 2, 0.5, -4)
            local function setToggler(on, animate)
                local boxC = on and BOX_ON or DARK
                local txtT = on and 0.0 or 0.52
                local trkT = on and 0.64 or 0.88
                local knbT = on and 0.0 or 0.76
                local pos  = on and ON_POS or OFF_POS
                if animate then
                    TweenService:Create(row, TI, { BackgroundColor3 = boxC }):Play()
                    TweenService:Create(lbl, TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(dots, TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(sw, TI, { BackgroundTransparency = trkT }):Play()
                    TweenService:Create(knob, TI, { BackgroundTransparency = knbT, Position = pos }):Play()
                else
                    row.BackgroundColor3 = boxC
                    lbl.TextTransparency = txtT; dots.TextTransparency = txtT
                    sw.BackgroundTransparency = trkT; knob.BackgroundTransparency = knbT; knob.Position = pos
                end
            end

            local settings = Instance.new("Frame", row)
            settings.Size = UDim2.new(1, 0, 0, SETTINGS_H); settings.Position = UDim2.new(0, 0, 0, ROW_H)
            settings.BackgroundTransparency = 1; settings.Visible = false
            local slay = Instance.new("UIListLayout", settings); slay.SortOrder = Enum.SortOrder.LayoutOrder; slay.Padding = UDim.new(0, 6)
            local spad = Instance.new("UIPadding", settings)
            spad.PaddingLeft = UDim.new(0, 14); spad.PaddingRight = UDim.new(0, 14)
            spad.PaddingTop = UDim.new(0, 2); spad.PaddingBottom = UDim.new(0, 12)

            local radios = {}
            local function repaintRadios() for _, fn in pairs(radios) do fn() end end
            for i, opt in ipairs(OPTIONS) do
                local o = Instance.new("TextButton", settings)
                o.Size = UDim2.new(1, 0, 0, 22); o.BackgroundTransparency = 1; o.Text = ""; o.AutoButtonColor = false; o.LayoutOrder = i
                local ol = Instance.new("TextLabel", o)
                ol.Size = UDim2.new(1, -24, 1, 0); ol.BackgroundTransparency = 1; ol.Text = opt.label
                ol.TextColor3 = WHITE; ol.TextSize = 12; ol.Font = FONT
                ol.TextXAlignment = Enum.TextXAlignment.Left; ol.TextYAlignment = Enum.TextYAlignment.Center
                local circ = Instance.new("Frame", o)
                circ.Size = UDim2.new(0, 12, 0, 12); circ.Position = UDim2.new(1, -12, 0.5, -6)
                circ.BackgroundColor3 = WHITE; circ.BorderSizePixel = 0
                Instance.new("UICorner", circ).CornerRadius = UDim.new(1, 0)
                local cstroke = Instance.new("UIStroke", circ); cstroke.Color = WHITE; cstroke.Thickness = 1; cstroke.Transparency = 0.9
                local dot = Instance.new("Frame", circ)
                dot.Size = UDim2.new(0, 5, 0, 5); dot.Position = UDim2.new(0.5, -2.5, 0.5, -2.5)
                dot.BackgroundColor3 = WHITE; dot.BorderSizePixel = 0
                Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
                local function setSel()
                    local sel = (lastMode == opt.mode)
                    circ.BackgroundTransparency = sel and 0.64 or 0.96
                    dot.Visible = sel
                    ol.TextTransparency = sel and 0.0 or 0.52
                end
                radios[opt.mode] = setSel
                o.MouseButton1Click:Connect(function()
                    lastMode = opt.mode
                    if isOn() then pcall(_G.MeerkoSetStealMode, opt.mode) end
                    repaintRadios()
                end)
            end

            setToggler(isOn(), false)
            repaintRadios()

            sw.MouseButton1Click:Connect(function()
                if isOn() then pcall(_G.MeerkoSetStealMode, nil) else pcall(_G.MeerkoSetStealMode, lastMode) end
                setToggler(isOn(), true)
            end)

            local expanded = false
            local EI = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            chev.MouseButton1Click:Connect(function()
                expanded = not expanded
                if expanded then settings.Visible = true end
                TweenService:Create(chev, EI, { Rotation = expanded and 90 or 0 }):Play()
                local h = expanded and (ROW_H + SETTINGS_H) or ROW_H
                local tw = TweenService:Create(row, EI, { Size = UDim2.new(1, 0, 0, h) })
                tw:Play()
                if not expanded then
                    tw.Completed:Once(function() if not expanded then settings.Visible = false end end)
                end
            end)
        end

        -- expandable Invis on Steal module: header on/off toggle + sliders
        local function addInvisModule(host)
            _order = _order + 1
            local SETTINGS_H = 148
            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.BackgroundColor3 = DARK; row.BackgroundTransparency = 0.12
            row.BorderSizePixel = 0; row.LayoutOrder = _order
            row.ClipsDescendants = true
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rstroke = Instance.new("UIStroke", row); rstroke.Color = WHITE; rstroke.Thickness = 1; rstroke.Transparency = 0.96; rstroke.Enabled = false

            local header = Instance.new("Frame", row)
            header.Size = UDim2.new(1, 0, 0, ROW_H); header.BackgroundTransparency = 1

            local dots = Instance.new("TextLabel", header)
            dots.Size = UDim2.new(0, 10, 1, 0); dots.Position = UDim2.new(0, 12, 0, 0); dots.BackgroundTransparency = 1
            dots.Text = "⋮⋮"; dots.TextColor3 = WHITE; dots.TextSize = 12; dots.Font = FONT
            dots.TextXAlignment = Enum.TextXAlignment.Center; dots.TextYAlignment = Enum.TextYAlignment.Center

            local lbl = Instance.new("TextLabel", header)
            lbl.Size = UDim2.new(1, -96, 1, 0); lbl.Position = UDim2.new(0, 28, 0, 0); lbl.BackgroundTransparency = 1
            lbl.Text = "Invis on Steal"; lbl.TextColor3 = WHITE; lbl.TextSize = 12; lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center

            local chev = Instance.new("TextButton", header)
            chev.Size = UDim2.new(0, 20, 1, 0); chev.Position = UDim2.new(1, -26, 0, 0); chev.BackgroundTransparency = 1
            chev.AutoButtonColor = false; chev.Text = "›"; chev.TextColor3 = WHITE; chev.TextTransparency = 0.4
            chev.TextSize = 18; chev.Font = FONT
            chev.TextXAlignment = Enum.TextXAlignment.Center; chev.TextYAlignment = Enum.TextYAlignment.Center

            local sw = Instance.new("TextButton", header)
            sw.Size = UDim2.new(0, 20, 0, 12); sw.Position = UDim2.new(1, -54, 0.5, -6)
            sw.AutoButtonColor = false; sw.Text = ""; sw.BackgroundColor3 = WHITE; sw.BackgroundTransparency = 0.88; sw.BorderSizePixel = 0
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
            local knob = Instance.new("Frame", sw)
            knob.Size = UDim2.new(0, 8, 0, 8); knob.BackgroundColor3 = WHITE; knob.BackgroundTransparency = 0.76; knob.BorderSizePixel = 0
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

            local TI = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
            local ON_POS, OFF_POS = UDim2.new(1, -10, 0.5, -4), UDim2.new(0, 2, 0.5, -4)
            local function setToggler(on, animate)
                local boxC = on and BOX_ON or DARK
                local txtT = on and 0.0 or 0.52
                local trkT = on and 0.64 or 0.88
                local knbT = on and 0.0 or 0.76
                local pos  = on and ON_POS or OFF_POS
                if animate then
                    TweenService:Create(row, TI, { BackgroundColor3 = boxC }):Play()
                    TweenService:Create(lbl, TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(dots, TI, { TextTransparency = txtT }):Play()
                    TweenService:Create(sw, TI, { BackgroundTransparency = trkT }):Play()
                    TweenService:Create(knob, TI, { BackgroundTransparency = knbT, Position = pos }):Play()
                else
                    row.BackgroundColor3 = boxC
                    lbl.TextTransparency = txtT; dots.TextTransparency = txtT
                    sw.BackgroundTransparency = trkT; knob.BackgroundTransparency = knbT; knob.Position = pos
                end
            end

            local settings = Instance.new("Frame", row)
            settings.Size = UDim2.new(1, 0, 0, SETTINGS_H); settings.Position = UDim2.new(0, 0, 0, ROW_H)
            settings.BackgroundTransparency = 1; settings.Visible = false
            local slay = Instance.new("UIListLayout", settings); slay.SortOrder = Enum.SortOrder.LayoutOrder; slay.Padding = UDim.new(0, 6)
            local spad = Instance.new("UIPadding", settings)
            spad.PaddingLeft = UDim.new(0, 14); spad.PaddingRight = UDim.new(0, 14)
            spad.PaddingTop = UDim.new(0, 2); spad.PaddingBottom = UDim.new(0, 12)

            local function addRecLabel(parent, text)
                local r = Instance.new("TextLabel", parent)
                r.Size = UDim2.new(1, 0, 0, 10)
                r.Position = UDim2.new(0, 0, 1, -10)
                r.BackgroundTransparency = 1
                r.Text = text
                r.TextColor3 = CAT_COL; r.TextTransparency = 0.3
                r.TextSize = 9; r.Font = FONT
                r.TextXAlignment = Enum.TextXAlignment.Left
            end

            local s1 = makeSlider(settings, "Rotation", 0, 360, 1,
                function() return Config.InvisRotation or 180 end,
                function(v)
                    Config.InvisRotation = v; _G.VanishInvisAngle = v; SaveConfig()
                end,
                function(v) return tostring(math.floor(v)) .. "°" end
            )
            s1.Size = UDim2.new(1, 0, 0, 38); s1.LayoutOrder = 1
            addRecLabel(s1, "rec: 180°")

            local s2 = makeSlider(settings, "Depth", 0.5, 10, 0.1,
                function() return Config.InvisDepth or 5 end,
                function(v)
                    Config.InvisDepth = v; _G.VanishInvisDepth = v; SaveConfig()
                end,
                function(v) return string.format("%.1f", v) end
            )
            s2.Size = UDim2.new(1, 0, 0, 38); s2.LayoutOrder = 2
            addRecLabel(s2, "rec: 5")

            local s3 = makeSlider(settings, "Walk Speed", 5, 32, 1,
                function() return Config.InvisWalkSpeed or 16 end,
                function(v)
                    Config.InvisWalkSpeed = v; _G.VanishInvisWalkSpeed = v; SaveConfig()
                end,
                function(v) return tostring(math.floor(v)) end
            )
            s3.Size = UDim2.new(1, 0, 0, 38); s3.LayoutOrder = 3
            addRecLabel(s3, "rec: 16")

            setToggler(Config.InvisOnSteal == true, false)
            sw.MouseButton1Click:Connect(function()
                local nv = not (Config.InvisOnSteal == true)
                setToggler(nv, true)
                task.spawn(function() pcall(applyToggle, "InvisOnSteal", nv) end)
            end)

            local expanded = false
            local EI = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            chev.MouseButton1Click:Connect(function()
                expanded = not expanded
                if expanded then settings.Visible = true end
                TweenService:Create(chev, EI, { Rotation = expanded and 90 or 0 }):Play()
                local h = expanded and (ROW_H + SETTINGS_H) or ROW_H
                local tw = TweenService:Create(row, EI, { Size = UDim2.new(1, 0, 0, h) })
                tw:Play()
                if not expanded then
                    tw.Completed:Once(function() if not expanded then settings.Visible = false end end)
                end
            end)
        end

        local function createStealTargetPanel()
            local PW       = 258
            local HEAD_H2  = 40
            local LIST_H   = 238
            local PAD2     = 4
            local ROW_H2   = 30
            -- matches the admin panel theme (navy + purple-blue accent)
            local FG_TEXT   = Color3.fromRGB(245, 247, 252)
            local FG_SUB    = Color3.fromRGB(172, 180, 206)
            local FG_FAINT  = Color3.fromRGB(150, 155, 178)
            local FG_STROKE = Color3.fromRGB(88, 94, 138)
            local FG_SOFT   = Color3.fromRGB(64, 66, 98)
            local ACCENT    = Color3.fromRGB(140, 146, 255)
            local MONEY     = Color3.fromRGB(100, 220, 140)
            local PANEL_BG  = Color3.fromRGB(30, 32, 44)
            local HEAD_BG   = Color3.fromRGB(43, 46, 60)
            local ROW_BG    = Color3.fromRGB(43, 46, 60)

            local stp = Instance.new("ScreenGui")
            stp.Name = "MeerkoStealTargetPanel"
            stp.ResetOnSpawn = false
            stp.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            local _stpWanted = stp.Enabled
            stp.Enabled = false
            task.delay(4, function() stp.Enabled = _stpWanted end)
            do
                local _cloneref = cloneref or function(x) return x end
                pcall(function() stp.Parent = _cloneref(game:GetService("CoreGui")) end)
            end
            if not stp.Parent then stp.Parent = PlayerGui end

            local pf = Instance.new("Frame", stp)
            pf.Size = UDim2.new(0, PW, 0, HEAD_H2 + LIST_H + PAD2 * 2)
            pf.Position = UDim2.new(0, Config._stealPanelX or 300, 0, Config._stealPanelY or 380)
            pf.BackgroundColor3 = PANEL_BG
            pf.BackgroundTransparency = 0
            pf.BorderSizePixel = 0
            Instance.new("UICorner", pf).CornerRadius = UDim.new(0, 14)
            local pfStroke = Instance.new("UIStroke", pf)
            pfStroke.Color = FG_STROKE; pfStroke.Thickness = 1; pfStroke.Transparency = 0
            do  -- subtle gradient like the FreeGUI window
                local gr = Instance.new("UIGradient", pf)
                gr.Color = ColorSequence.new(Color3.fromRGB(34, 36, 50), Color3.fromRGB(24, 26, 38))
                gr.Rotation = 90
            end
            do  -- slight soft drop shadow around the whole panel (light theme)
                local ps = Instance.new("ImageLabel")
                ps.Name = "PanelShadow"; ps.BackgroundTransparency = 1
                ps.Image = "rbxassetid://6014261993"; ps.ScaleType = Enum.ScaleType.Slice
                ps.SliceCenter = Rect.new(49, 49, 463, 463); ps.ImageColor3 = Color3.fromRGB(60, 66, 110)
                ps.ImageTransparency = 0.7
                ps.AnchorPoint = Vector2.new(0.5, 0.5); ps.Position = UDim2.new(0.5, 0, 0.5, 0)
                ps.Size = UDim2.new(1, 44, 1, 44); ps.ZIndex = 0
                ps.Parent = pf
            end

            -- ── header bar (also the drag handle) ──
            local head = Instance.new("Frame", pf)
            head.Size = UDim2.new(1, 0, 0, HEAD_H2)
            head.BackgroundTransparency = 1   -- no fill; the panel is the single translucent surface
            head.BorderSizePixel = 0
            head.Active = true
            -- thin divider under the header
            local headDiv = Instance.new("Frame", head)
            headDiv.Size = UDim2.new(1, -22, 0, 1); headDiv.Position = UDim2.new(0, 11, 1, -1)
            headDiv.BackgroundColor3 = FG_STROKE; headDiv.BackgroundTransparency = 0; headDiv.BorderSizePixel = 0

            -- purple accent strip at the very top, like FreeGUI section cards
            local accentBar = Instance.new("Frame", head)
            accentBar.Size = UDim2.new(1, -22, 0, 2)
            accentBar.Position = UDim2.new(0, 11, 0, 0)
            accentBar.BackgroundColor3 = ACCENT
            accentBar.BorderSizePixel = 0
            Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)
            do
                local gr = Instance.new("UIGradient", accentBar)
                gr.Color = ColorSequence.new(ACCENT, Color3.fromRGB(168, 114, 255))
                gr.Rotation = 0
            end

            local title = Instance.new("TextLabel", head)
            title.Size = UDim2.new(1, 0, 1, 0); title.Position = UDim2.new(0, 0, 0, 0)
            title.BackgroundTransparency = 1
            title.Text = "Steal Target"
            title.TextColor3 = FG_TEXT
            title.TextSize = 15; title.Font = Enum.Font.GothamBold
            title.TextXAlignment = Enum.TextXAlignment.Center; title.TextYAlignment = Enum.TextYAlignment.Center
            title.ZIndex = 2

            -- drag the panel by its header bar; remember position like the
            -- other floating panels (Meerko TP / Features menu)
            local dg, ds, sp = false, nil, nil
            head.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dg = true
                    ds = input.Position
                    sp = UDim2.new(0, pf.AbsolutePosition.X, 0, pf.AbsolutePosition.Y)
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            dg = false
                            Config._stealPanelX = pf.Position.X.Offset
                            Config._stealPanelY = pf.Position.Y.Offset
                            SaveConfig()
                        end
                    end)
                end
            end)
            UIS.InputChanged:Connect(function(input)
                if dg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local d = input.Position - ds
                    local newX = sp.X.Offset + d.X
                    local newY = sp.Y.Offset + d.Y
                    local vp = workspace.CurrentCamera.ViewportSize
                    newX = math.clamp(newX, 0, vp.X - pf.AbsoluteSize.X)
                    newY = math.clamp(newY, 0, vp.Y - pf.AbsoluteSize.Y)
                    pf.Position = UDim2.new(0, newX, 0, newY)
                end
            end)

            local scroll = Instance.new("ScrollingFrame", pf)
            scroll.Size = UDim2.new(1, -8, 0, LIST_H)
            scroll.Position = UDim2.new(0, 4, 0, HEAD_H2 + PAD2)
            scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
            scroll.ScrollBarThickness = 3
            scroll.ScrollBarImageColor3 = FG_FAINT; scroll.ScrollBarImageTransparency = 0
            scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            local sl = Instance.new("UIListLayout", scroll)
            sl.Padding = UDim.new(0, 6); sl.SortOrder = Enum.SortOrder.LayoutOrder
            -- inset so the rows' outlines aren't clipped by the scroll edges
            local spad = Instance.new("UIPadding", scroll)
            spad.PaddingTop = UDim.new(0, 4); spad.PaddingBottom = UDim.new(0, 4)
            spad.PaddingLeft = UDim.new(0, 2); spad.PaddingRight = UDim.new(0, 6)

            local shClip = Instance.new("Frame", pf)
            shClip.Name = "ShadowClip"; shClip.BackgroundTransparency = 1; shClip.BorderSizePixel = 0
            shClip.ClipsDescendants = true; shClip.ZIndex = 0
            shClip.Position = UDim2.new(0, 0, 0, HEAD_H2 + PAD2)
            shClip.Size = UDim2.new(1, 0, 0, LIST_H)
            local _stRowShadows = {}
            local function clearStealShadows()
                for _, s in ipairs(_stRowShadows) do pcall(function() s:Destroy() end) end
                _stRowShadows = {}
            end
            local function addStealRowShadow(row)
                local sh = Instance.new("ImageLabel")
                sh.Name = "CardShadow"; sh.BackgroundTransparency = 1
                sh.Image = "rbxassetid://6014261993"; sh.ScaleType = Enum.ScaleType.Slice
                sh.SliceCenter = Rect.new(49, 49, 463, 463); sh.ImageColor3 = Color3.fromRGB(60, 66, 110)
                sh.ImageTransparency = 0.88; sh.ZIndex = 0; sh.Parent = shClip
                local function upd()
                    if not row.Parent then return end
                    local c = shClip.AbsolutePosition
                    sh.Position = UDim2.new(0, row.AbsolutePosition.X - c.X - 14, 0, row.AbsolutePosition.Y - c.Y - 14)
                    sh.Size = UDim2.new(0, row.AbsoluteSize.X + 28, 0, row.AbsoluteSize.Y + 28)
                end
                upd()
                row:GetPropertyChangedSignal("AbsolutePosition"):Connect(upd)
                row:GetPropertyChangedSignal("AbsoluteSize"):Connect(upd)
                table.insert(_stRowShadows, sh)
            end

            local function petUID(p) return tostring(p.plot) .. "|" .. tostring(p.slot) end

            local function trim1(n)
                local s = string.format("%.1f", n)
                s = s:gsub("%.0$", "")   -- 255.0 -> 255, but keep 412.5
                return s
            end
            local function fmtMps(gv)
                gv = gv or 0
                if gv >= 1e9 then return "$" .. trim1(gv / 1e9) .. "B/s" end
                if gv >= 1e6 then return "$" .. trim1(gv / 1e6) .. "M/s" end
                if gv >= 1e3 then return "$" .. trim1(gv / 1e3) .. "K/s" end
                return string.format("$%d/s", math.floor(gv))
            end

            local TweenService = game:GetService("TweenService")
            local SEL_TI = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local repaintFns = {}
            local function repaintAll() for _, fn in ipairs(repaintFns) do fn(true) end end

            local function buildRows()
                clearStealShadows()
                for _, ch in ipairs(scroll:GetChildren()) do
                    if not (ch:IsA("UIListLayout") or ch:IsA("UIPadding")) then ch:Destroy() end
                end
                repaintFns = {}

                local ok, pets = pcall(scanAllPets)
                pets = (ok and pets) or {}
                local n = math.min(#pets, 25)

                if n == 0 then
                    local e = Instance.new("TextLabel", scroll)
                    e.Size = UDim2.new(1, -4, 0, 40); e.BackgroundTransparency = 1
                    e.Text = "No brainrots found"
                    e.TextColor3 = FG_FAINT; e.TextSize = 14; e.Font = Enum.Font.GothamMedium
                    e.TextXAlignment = Enum.TextXAlignment.Center; e.TextYAlignment = Enum.TextYAlignment.Center
                    return
                end

                for i = 1, n do
                    local p = pets[i]
                    local uid = petUID(p)

                    local b = Instance.new("TextButton", scroll)
                    b.Size = UDim2.new(1, 0, 0, ROW_H2)
                    b.AutoButtonColor = false; b.Text = ""
                    b.BackgroundColor3 = ROW_BG; b.BackgroundTransparency = 0
                    b.BorderSizePixel = 0; b.LayoutOrder = i
                    b.ClipsDescendants = false
                    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
                    local bs = Instance.new("UIStroke", b)
                    bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    bs.Color = FG_STROKE
                    bs.Thickness = 1
                    bs.Transparency = 0

                    -- rank number on the left
                    local rankL = Instance.new("TextLabel", b)
                    rankL.Size = UDim2.new(0, 26, 1, 0); rankL.Position = UDim2.new(0, 10, 0, 0)
                    rankL.BackgroundTransparency = 1; rankL.Text = "#" .. tostring(i)
                    rankL.TextColor3 = FG_SUB
                    rankL.TextSize = 12; rankL.Font = Enum.Font.GothamBold
                    rankL.TextXAlignment = Enum.TextXAlignment.Left; rankL.TextYAlignment = Enum.TextYAlignment.Center

                    -- name
                    local nameL = Instance.new("TextLabel", b)
                    nameL.Size = UDim2.new(1, -126, 1, 0); nameL.Position = UDim2.new(0, 40, 0, 0)
                    nameL.BackgroundTransparency = 1; nameL.Text = p.name
                    nameL.TextColor3 = FG_TEXT; nameL.TextSize = 12; nameL.Font = Enum.Font.GothamMedium
                    nameL.TextXAlignment = Enum.TextXAlignment.Left; nameL.TextYAlignment = Enum.TextYAlignment.Center
                    nameL.TextTruncate = Enum.TextTruncate.AtEnd

                    -- money/sec
                    local mpsL = Instance.new("TextLabel", b)
                    mpsL.Size = UDim2.new(0, 78, 1, 0); mpsL.Position = UDim2.new(1, -82, 0, 0)
                    mpsL.BackgroundTransparency = 1; mpsL.Text = fmtMps(p.mps)
                    mpsL.TextColor3 = MONEY; mpsL.TextSize = 12; mpsL.Font = Enum.Font.GothamBold
                    mpsL.TextXAlignment = Enum.TextXAlignment.Right; mpsL.TextYAlignment = Enum.TextYAlignment.Center

                    local function repaint(animate)
                        local sel = (_G.MeerkoStealTargetUID == uid)
                        local bgColor = sel and FG_SOFT or ROW_BG
                        local bgT     = 0
                        local stColor = sel and ACCENT or FG_STROKE
                        local stT     = sel and 0 or 0
                        if animate then
                            TweenService:Create(b, SEL_TI, { BackgroundColor3 = bgColor, BackgroundTransparency = bgT }):Play()
                            TweenService:Create(bs, SEL_TI, { Color = stColor, Transparency = stT }):Play()
                        else
                            b.BackgroundColor3 = bgColor; b.BackgroundTransparency = bgT
                            bs.Color = stColor; bs.Transparency = stT
                        end
                    end
                    repaint(false)
                    repaintFns[#repaintFns + 1] = repaint

                    b.MouseButton1Click:Connect(function()
                        if _G.MeerkoStealTargetUID == uid then
                            _G.MeerkoStealTargetUID = nil
                        else
                            _G.MeerkoStealTargetUID = uid
                        end
                        repaintAll()
                    end)
                    addStealRowShadow(b)
                end
            end

            buildRows()

            -- keep the list (and selected highlight) fresh
            task.spawn(function()
                while true do
                    task.wait(2)
                    if stp.Enabled then pcall(buildRows) end
                end
            end)
        end
        createStealTargetPanel()

        -- ============================================================
        -- ANTI BODY SWAP  (ported from dtc) — auto swap-back when a
        -- player uses a Body Swap Potion to swap you away from your spot.
        -- Toggle via _G.AntiBodySwapEnabled (driven by the MISC toggle).
        -- ============================================================
        _G.AntiBodySwapEnabled = Config.AntiBodySwap == true
        task.spawn(function()
            local _abs_POTION_NAME     = "Body Swap Potion"
            local _abs_HOLDER_JUMP_MIN = 3
            local _abs_SWAP_RADIUS     = 5
            local _abs_LOCAL_MOVED_MIN = 3
            local _abs_PER_PLAYER_CD   = 30

            local Players    = game:GetService("Players")
            local RunService = game:GetService("RunService")
            local LocalPlayer = Players.LocalPlayer

            local hitCooldowns   = {}
            local localJustFired = false
            local prevHolderPos  = nil
            local prevLocalPos   = nil

            local function getLocalHRP()
                local char = LocalPlayer.Character
                return char and char:FindFirstChild("HumanoidRootPart")
            end

            local function getHolder()
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer
                       and plr.Character
                       and plr.Character:FindFirstChild(_abs_POTION_NAME) then
                        return plr
                    end
                end
                return nil
            end

            local function hookLocalPotion()
                local char = LocalPlayer.Character
                if not char then return end
                local function hook(potion)
                    potion.Activated:Connect(function()
                        localJustFired = true
                        task.delay(1, function() localJustFired = false end)
                    end)
                end
                local existing = char:FindFirstChild(_abs_POTION_NAME)
                if existing then hook(existing) end
                char.ChildAdded:Connect(function(child)
                    if child.Name == _abs_POTION_NAME then hook(child) end
                end)
            end
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.1)
                hookLocalPotion()
            end)
            hookLocalPotion()

            local function swapBack(targetPlayer)
                pcall(function()
                    local char = LocalPlayer.Character
                    if not char then return end
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if not hum then return end

                    local potion = char:FindFirstChild(_abs_POTION_NAME)
                                or (LocalPlayer:FindFirstChild("Backpack") and LocalPlayer.Backpack:FindFirstChild(_abs_POTION_NAME))
                    if not potion then return end

                    hum:EquipTool(potion)
                    task.wait(0.05)

                    local targetChar = targetPlayer.Character
                    local targetHRP  = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                    local localHRP   = getLocalHRP()
                    if targetHRP and localHRP then
                        localHRP.CFrame = CFrame.lookAt(
                            targetHRP.Position,
                            targetHRP.Position + targetHRP.CFrame.LookVector
                        )
                    end

                    if LocalPlayer:GetAttribute("Stealing") then
                        while LocalPlayer:GetAttribute("Stealing") do task.wait() end
                        task.wait(0.2)
                        hum:EquipTool(potion)
                        task.wait(0.05)
                        if targetPlayer.Character then
                            local tHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                            local lHRP = getLocalHRP()
                            if tHRP and lHRP then
                                lHRP.CFrame = CFrame.lookAt(
                                    tHRP.Position,
                                    tHRP.Position + tHRP.CFrame.LookVector
                                )
                            end
                        end
                    end

                    potion = char:FindFirstChild(_abs_POTION_NAME)
                    if potion then potion:Activate() end
                end)
            end

            RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                if not _G.AntiBodySwapEnabled then
                    prevHolderPos = nil
                    prevLocalPos  = nil
                    return
                end

                local holder = getHolder()
                if not holder then
                    prevHolderPos = nil
                    prevLocalPos  = nil
                    return
                end

                local cd = hitCooldowns[holder.Name]
                if cd and tick() - cd < _abs_PER_PLAYER_CD then return end

                local holderHRP = holder.Character and holder.Character:FindFirstChild("HumanoidRootPart")
                local localHRP  = getLocalHRP()
                if not holderHRP or not localHRP then return end

                local currHolder = holderHRP.Position
                local currLocal  = localHRP.Position

                if prevHolderPos and prevLocalPos then
                    local holderJumped        = (currHolder - prevHolderPos).Magnitude
                    local holderNowAtMyOldPos = (currHolder - prevLocalPos).Magnitude < _abs_SWAP_RADIUS
                    local iMoved              = (currLocal  - prevLocalPos).Magnitude > _abs_LOCAL_MOVED_MIN

                    if holderJumped > _abs_HOLDER_JUMP_MIN
                       and holderNowAtMyOldPos
                       and iMoved
                       and not localJustFired then
                        hitCooldowns[holder.Name] = tick()
                        task.spawn(function() swapBack(holder) end)
                    end
                end

                prevHolderPos = currHolder
                prevLocalPos  = currLocal
            end))
        end)

        -- ============================================================
        -- AUTO-DESTROY TURRETS  (ported from dtc) — bats enemy Sentry
        -- turrets out of existence. Gated by Config.AutoDestroyTurrets.
        -- ============================================================
        task.spawn(function()
            local RunService  = game:GetService("RunService")
            local Workspace   = game:GetService("Workspace")
            local LocalPlayer = game:GetService("Players").LocalPlayer
            local _activeSentryConns = {}

            -- Startup grace period: hold off anti-turret action for 10s after
            -- script load so an on-join auto-snipe TP isn't disrupted.
            local _antiTurretReadyAt = os.clock() + 10

            local function handleSentry(child, immediate)
                if not child.Name or not child.Name:find("Sentry") then return end
                if _activeSentryConns[child] then return end
                local sentry_owner_id = child.Name:match("Sentry_(%d+)")
                if not sentry_owner_id or tonumber(sentry_owner_id) == LocalPlayer.UserId then return end
                if not immediate then
                    local setupReady = child:FindFirstChild("SetupReady")
                    if not setupReady then
                        local waitTime = 0
                        while not setupReady and child.Parent and waitTime < 5 do
                            task.wait(0.1)
                            setupReady = child:FindFirstChild("SetupReady")
                            waitTime = waitTime + 0.1
                        end
                        if not child.Parent then return end
                    end
                    task.wait(0.1)
                end
                if _activeSentryConns[child] then return end
                local sentryPart = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart", true)
                if not sentryPart and child:IsA("Model") then
                    for _, desc in ipairs(child:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            sentryPart = desc
                            break
                        end
                    end
                end
                if sentryPart then
                    sentryPart.CanCollide = false
                    sentryPart.Transparency = 1
                    sentryPart.Size = Vector3.new(10, 10, 10)
                end
                local last_attack = 0
                local equipAttempts = 0
                local frameSkip = 0
                local heartbeat_conn
                heartbeat_conn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                    if not child.Parent then
                        if heartbeat_conn and typeof(heartbeat_conn) == "RBXScriptConnection" then
                            heartbeat_conn:Disconnect()
                        end
                        _activeSentryConns[child] = nil
                        return
                    end
                    if not Config.AutoDestroyTurrets then return end
                    if os.clock() < _antiTurretReadyAt then return end
                    frameSkip = frameSkip + 1
                    if frameSkip < 3 then return end
                    frameSkip = 0
                    local now = tick()
                    if now - last_attack < 0.05 then return end
                    last_attack = now
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local hrp = LocalPlayer.Character.HumanoidRootPart
                        local targetCFrame = hrp.CFrame * CFrame.new(0, 0, -2)
                        if child:IsA("Model") and child.PrimaryPart then
                            pcall(function() child:SetPrimaryPartCFrame(targetCFrame) end)
                        elseif sentryPart then
                            pcall(function() sentryPart.CFrame = targetCFrame end)
                        end
                        local bat = LocalPlayer.Backpack:FindFirstChild("Bat") or LocalPlayer.Character:FindFirstChild("Bat")
                        if bat then
                            if bat.Parent == LocalPlayer.Backpack then
                                equipAttempts = equipAttempts + 1
                                if equipAttempts <= 3 then
                                    pcall(function()
                                        LocalPlayer.Character.Humanoid:UnequipTools()
                                        LocalPlayer.Character.Humanoid:EquipTool(bat)
                                    end)
                                end
                            end
                            if bat.Parent == LocalPlayer.Character then
                                equipAttempts = 0
                                pcall(function() bat:Activate() end)
                            end
                        end
                    end
                end))
                _activeSentryConns[child] = heartbeat_conn
            end

            local function scanExistingSentries()
                task.spawn(function()
                    pcall(function()
                        for _, child in ipairs(Workspace:GetDescendants()) do
                            if child and child.Name and child.Name:find("Sentry") and not _activeSentryConns[child] then
                                task.spawn(function()
                                    pcall(function() handleSentry(child, true) end)
                                end)
                            end
                        end
                    end)
                end)
            end

            scanExistingSentries()
            task.delay(2, scanExistingSentries)
            task.delay(5, scanExistingSentries)

            Workspace.DescendantAdded:Connect(function(child)
                handleSentry(child, false)
            end)
        end)

        -- rebindable action keybind row (label + key button, module-styled)
        local function addKeybindRow(host, label, cfgKey)
            _order = _order + 1
            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.BackgroundColor3 = DARK; row.BackgroundTransparency = 0.12
            row.BorderSizePixel = 0; row.LayoutOrder = _order
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rs = Instance.new("UIStroke", row); rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; rs.Color = WHITE; rs.Thickness = 1; rs.Transparency = 0.93

            local dots = Instance.new("TextLabel", row)
            dots.Size = UDim2.new(0, 10, 1, 0); dots.Position = UDim2.new(0, 12, 0, 0); dots.BackgroundTransparency = 1
            dots.Text = "⋮⋮"; dots.TextColor3 = WHITE; dots.TextTransparency = 0.52; dots.TextSize = 12; dots.Font = FONT
            dots.TextXAlignment = Enum.TextXAlignment.Center; dots.TextYAlignment = Enum.TextYAlignment.Center

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -84, 1, 0); lbl.Position = UDim2.new(0, 28, 0, 0); lbl.BackgroundTransparency = 1
            lbl.Text = label; lbl.TextColor3 = WHITE; lbl.TextTransparency = 0.1; lbl.TextSize = 12; lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center

            local kb = Instance.new("TextButton", row)
            kb.Size = UDim2.new(0, 56, 0, 20); kb.Position = UDim2.new(1, -64, 0.5, -10)
            kb.BackgroundColor3 = WHITE; kb.BackgroundTransparency = 0.9; kb.AutoButtonColor = false
            kb.Font = FONT; kb.TextSize = 11; kb.TextColor3 = WHITE; kb.TextTransparency = 0.05; kb.BorderSizePixel = 0
            Instance.new("UICorner", kb).CornerRadius = UDim.new(0, 6)
            local function disp()
                local v = Config[cfgKey]
                kb.Text = (v and v ~= "") and v or "NONE"
            end
            disp()
            local listening = false
            kb.MouseButton1Click:Connect(function()
                if listening then return end
                listening = true; kb.Text = "..."
                local con
                con = UIS.InputBegan:Connect(function(inp)
                    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
                    local nm = inp.KeyCode.Name
                    if nm == "Escape" or nm == "Backspace" or nm == "Delete" then
                        Config[cfgKey] = ""
                    elseif nm and nm ~= "Unknown" then
                        Config[cfgKey] = nm
                    end
                    SaveConfig(); disp(); listening = false
                    if con then con:Disconnect() end
                end)
                task.delay(5, function()
                    if listening then listening = false; if con then con:Disconnect() end; disp() end
                end)
            end)
        end

        local byTitle = {}
        for _, g in ipairs(GROUPS) do byTitle[g.title] = g end
        local function buildGroup(host, title)
            local g = byTitle[title]; if not g then return end
            addCategory(host, title)
            for _, def in ipairs(g.items) do addRow(host, def) end
        end

        addCategory(host1, "MAIN")
        addTpModule(host1)
        addAutoStealModule(host1)
        local antiGroup = byTitle["ANTI"]
        if antiGroup then
            addCategory(host1, "ANTI")
            for _, def in ipairs(antiGroup.items) do addRow(host1, def) end
        end
        for _, def in ipairs(byTitle["MAIN"].items) do addRow(host1, def) end
        addCategory(host1, "SERVER")
        addInvisModule(host1)
        for _, def in ipairs(byTitle["SERVER"].items) do addRow(host1, def) end
        buildGroup(host2, "VISUALS")
        buildGroup(host2, "MISC")
        addCategory(host2, "KEYBINDS")
        addKeybindRow(host2, "Auto Clone", "CloneKey")
        addKeybindRow(host2, "Carpet Speed", "CarpetSpeedKey")
        addKeybindRow(host2, "Item Drop", "ItemDropKey")
        addKeybindRow(host2, "Drop Brainrot", "BrainrotDropKey")
        addKeybindRow(host2, "Auto Buy", "AutoBuyKey")
        addKeybindRow(host2, "Cancel TP", "CancelTPKey")
        addKeybindRow(host2, "Reset", "ResetKey")
        addKeybindRow(host2, "Rejoin", "RejoinKey")
        addKeybindRow(host2, "Toggle Menu", "MenuKey")

        applyTabShadows(host1); applyTabShadows(host2)
        for _, b in ipairs(tabBtns) do addCardShadow(b, nil, 0.42, 10) end

        -- ===== TAB 3 (Custom): user-curated feature list =====
        local ALL_FEATURES = {}
        for _, g in ipairs(GROUPS) do
            for _, item in ipairs(g.items) do
                ALL_FEATURES[item.key] = { key = item.key, label = item.label, type = "toggle", def = item, category = g.title }
            end
        end
        ALL_FEATURES["AutoTeleport"]  = { key = "AutoTeleport",  label = "Auto Teleport",  type = "module", builder = addTpModule }
        ALL_FEATURES["AutoSteal"]     = { key = "AutoSteal",     label = "Auto Steal",     type = "module", builder = addAutoStealModule }
        ALL_FEATURES["InvisOnSteal"]  = { key = "InvisOnSteal",  label = "Invis on Steal", type = "module", builder = addInvisModule }
        ALL_FEATURES["CloneKey"]      = { key = "CloneKey",      label = "Auto Clone (Key)",    type = "keybind", kLabel = "Auto Clone",    kConfig = "CloneKey" }
        ALL_FEATURES["CarpetSpeedKey"]= { key = "CarpetSpeedKey",label = "Carpet Speed (Key)",  type = "keybind", kLabel = "Carpet Speed",  kConfig = "CarpetSpeedKey" }
        ALL_FEATURES["ItemDropKey"]   = { key = "ItemDropKey",   label = "Item Drop (Key)",     type = "keybind", kLabel = "Item Drop",     kConfig = "ItemDropKey" }
        ALL_FEATURES["BrainrotDropKey"]= { key = "BrainrotDropKey",label = "Drop Brainrot (Key)", type = "keybind", kLabel = "Drop Brainrot", kConfig = "BrainrotDropKey" }
        ALL_FEATURES["CancelTPKey"]   = { key = "CancelTPKey",   label = "Cancel TP (Key)",     type = "keybind", kLabel = "Cancel TP",     kConfig = "CancelTPKey" }
        ALL_FEATURES["ResetKey"]      = { key = "ResetKey",      label = "Reset (Key)",         type = "keybind", kLabel = "Reset",         kConfig = "ResetKey" }
        ALL_FEATURES["RejoinKey"]     = { key = "RejoinKey",     label = "Rejoin (Key)",        type = "keybind", kLabel = "Rejoin",        kConfig = "RejoinKey" }
        ALL_FEATURES["MenuKey"]       = { key = "MenuKey",       label = "Toggle Menu (Key)",   type = "keybind", kLabel = "Toggle Menu",   kConfig = "MenuKey" }

        local customPickerOpen = false

        local function migrateCustomTab()
            if not Config.CustomTab then Config.CustomTab = {} end
            for i, v in ipairs(Config.CustomTab) do
                if type(v) == "string" then Config.CustomTab[i] = { key = v } end
            end
        end
        migrateCustomTab()

        -- ── Reorder mode + drag state ──
        local rebuildCustomTab
        local _ctRunService = game:GetService("RunService")
        local _ctReorderMode = false
        local _ctDrag = nil
        local _ctItemFrames = {}

        local function startDrag(frame, idx, label)
            if not _ctReorderMode then return end
            if _ctDrag then return end
            _ctDrag = { idx = idx, target = idx, frame = frame, label = label, held = true, dragging = false, startY = nil, frames = 0 }
        end

        _ctRunService.RenderStepped:Connect(function()
            if not _ctDrag then return end
            _ctDrag.frames = _ctDrag.frames + 1

            if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                if _ctDrag.dragging then
                    local fromIdx = _ctDrag.idx
                    local toIdx = _ctDrag.target or fromIdx
                    if _ctDrag.ghost then pcall(function() _ctDrag.ghost:Destroy() end) end
                    _ctDrag = nil
                    if toIdx ~= fromIdx and Config.CustomTab[fromIdx] then
                        local item = table.remove(Config.CustomTab, fromIdx)
                        if toIdx > fromIdx then toIdx = toIdx - 1 end
                        table.insert(Config.CustomTab, toIdx, item)
                        SaveConfig()
                    end
                    rebuildCustomTab()
                else
                    _ctDrag = nil
                end
                return
            end

            if _ctDrag.frames < 8 then return end

            if not _ctDrag.startY then
                _ctDrag.startY = UIS:GetMouseLocation().Y
                return
            end

            local mouseY = UIS:GetMouseLocation().Y

            if not _ctDrag.dragging then
                if math.abs(mouseY - _ctDrag.startY) > 12 then
                    _ctDrag.dragging = true
                    if _ct3SizeConn then _ct3SizeConn:Disconnect(); _ct3SizeConn = nil end
                    local savedH = mf.Size.Y.Offset
                    local frame = _ctDrag.frame
                    local frameH = frame.AbsoluteSize.Y
                    _ctDrag.grabOff = mouseY - frame.AbsolutePosition.Y
                    _ctDrag.dragH = math.min(frameH, ROW_H)
                    host3.AutomaticSize = Enum.AutomaticSize.None
                    mf.Size = UDim2.new(0, W, 0, savedH)
                    host3.Size = UDim2.new(1, -24, 0, savedH - CONTENT_Y)
                    local hostY = host3.AbsolutePosition.Y
                    for _, f in ipairs(_ctItemFrames) do
                        f.Position = UDim2.new(0, 0, 0, f.AbsolutePosition.Y - hostY)
                    end
                    local lay = host3:FindFirstChildOfClass("UIListLayout")
                    if lay then lay:Destroy() end
                    local itemSet = {}
                    for _, f in ipairs(_ctItemFrames) do itemSet[f] = true end
                    for _, c in ipairs(host3:GetChildren()) do
                        if c:IsA("GuiObject") and not itemSet[c] then c.Visible = false end
                    end
                    frame.BackgroundTransparency = 0.8
                    for _, d in ipairs(frame:GetDescendants()) do
                        if d:IsA("GuiObject") then pcall(function() d.Visible = false end) end
                    end
                    local ghost = Instance.new("Frame", host3)
                    ghost.Size = UDim2.new(1, 0, 0, _ctDrag.dragH)
                    ghost.BackgroundColor3 = Color3.fromRGB(40, 56, 92); ghost.BackgroundTransparency = 0.2
                    ghost.BorderSizePixel = 0; ghost.ZIndex = 20
                    Instance.new("UICorner", ghost).CornerRadius = UDim.new(0, 10)
                    local gs = Instance.new("UIStroke", ghost); gs.Color = Color3.fromRGB(100, 170, 255); gs.Thickness = 1; gs.Transparency = 0.5
                    local gLbl = Instance.new("TextLabel", ghost)
                    gLbl.Size = UDim2.new(1, -24, 1, 0); gLbl.Position = UDim2.new(0, 12, 0, 0)
                    gLbl.BackgroundTransparency = 1; gLbl.Text = _ctDrag.label; gLbl.TextColor3 = WHITE
                    gLbl.TextSize = 12; gLbl.Font = FONT; gLbl.TextXAlignment = Enum.TextXAlignment.Left; gLbl.ZIndex = 21
                    _ctDrag.ghost = ghost
                end
                return
            end

            local hostY = host3.AbsolutePosition.Y
            local relY = mouseY - hostY - _ctDrag.grabOff
            _ctDrag.ghost.Position = UDim2.new(0, 0, 0, relY)

            local count = #_ctItemFrames
            local cumY, newTarget = 0, count
            for i = 1, count do
                local h = (i == _ctDrag.idx) and (_ctDrag.dragH or ROW_H) or (_ctItemFrames[i] and _ctItemFrames[i].AbsoluteSize.Y or ROW_H)
                if relY + (_ctDrag.dragH or ROW_H) * 0.5 < cumY + h * 0.5 then
                    newTarget = i; break
                end
                cumY = cumY + h + PAD
            end
            if newTarget ~= _ctDrag.target then
                _ctDrag.target = newTarget
                local dragIdx = _ctDrag.idx
                local n = #_ctItemFrames
                local slots = {}
                for i = 1, n do if i ~= dragIdx then slots[#slots + 1] = i end end
                table.insert(slots, math.min(newTarget, #slots + 1), dragIdx)
                local tweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local cy = 0
                for _, slot in ipairs(slots) do
                    local h = (_ctItemFrames[slot] and _ctItemFrames[slot].AbsoluteSize.Y > 0) and _ctItemFrames[slot].AbsoluteSize.Y or ROW_H
                    if slot ~= dragIdx then
                        TweenService:Create(_ctItemFrames[slot], tweenInfo, { Position = UDim2.new(0, 0, 0, cy) }):Play()
                    end
                    cy = cy + h + PAD
                end
            end
        end)

        local function makeRemoveBtn(row, idx)
            local x = Instance.new("TextButton", row)
            x.Size = UDim2.new(0, 20, 0, ROW_H); x.Position = UDim2.new(0, 6, 0, 0)
            x.BackgroundTransparency = 1; x.AutoButtonColor = false; x.BorderSizePixel = 0
            x.Text = "x"; x.TextColor3 = Color3.fromRGB(255, 80, 80); x.TextTransparency = 0.5
            x.TextSize = 11; x.Font = FONT; x.ZIndex = 6
            x.MouseButton1Click:Connect(function()
                table.remove(Config.CustomTab, idx); SaveConfig(); rebuildCustomTab()
            end)
        end

        local function addCustToggle(host, feat, idx)
            _order = _order + 1
            local row = Instance.new("TextButton", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H); row.AutoButtonColor = false; row.Text = ""
            row.BackgroundColor3 = DARK; row.BackgroundTransparency = 0.12; row.BorderSizePixel = 0; row.LayoutOrder = _order
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rs2 = Instance.new("UIStroke", row); rs2.Color = WHITE; rs2.Thickness = 1; rs2.Transparency = 0.96
            if _ctReorderMode then makeRemoveBtn(row, idx) end
            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -60, 1, 0); lbl.Position = UDim2.new(0, _ctReorderMode and 26 or 12, 0, 0)
            lbl.BackgroundTransparency = 1; lbl.Text = feat.label; lbl.TextColor3 = WHITE; lbl.TextTransparency = 0.52
            lbl.TextSize = 12; lbl.Font = FONT; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            if _ctReorderMode then
                row.MouseButton1Down:Connect(function()
                    startDrag(row, idx, feat.label)
                end)
            else
                local sw = Instance.new("Frame", row)
                sw.Size = UDim2.new(0, 20, 0, 12); sw.Position = UDim2.new(1, -32, 0.5, -6)
                sw.BackgroundColor3 = WHITE; sw.BackgroundTransparency = 0.88; sw.BorderSizePixel = 0
                Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
                local knob = Instance.new("Frame", sw)
                knob.Size = UDim2.new(0, 8, 0, 8); knob.BackgroundColor3 = WHITE; knob.BackgroundTransparency = 0.76; knob.BorderSizePixel = 0
                Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
                local ON_P, OFF_P = UDim2.new(1, -10, 0.5, -4), UDim2.new(0, 2, 0.5, -4)
                local TI2 = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                local function setTog(on, anim)
                    local boxC = on and BOX_ON or DARK
                    local txtT, trkT, knbT = on and 0 or 0.52, on and 0.64 or 0.88, on and 0 or 0.76
                    local pos = on and ON_P or OFF_P
                    if anim then
                        TweenService:Create(row, TI2, { BackgroundColor3 = boxC }):Play()
                        TweenService:Create(lbl, TI2, { TextTransparency = txtT }):Play()
                        TweenService:Create(sw, TI2, { BackgroundTransparency = trkT }):Play()
                        TweenService:Create(knob, TI2, { BackgroundTransparency = knbT, Position = pos }):Play()
                    else
                        row.BackgroundColor3 = boxC; lbl.TextTransparency = txtT
                        sw.BackgroundTransparency = trkT; knob.BackgroundTransparency = knbT; knob.Position = pos
                    end
                end
                local cfgK = feat.def and feat.def.key or feat.key
                setTog(Config[cfgK] == true, false)
                row.MouseButton1Click:Connect(function()
                    local nv = not (Config[cfgK] == true); setTog(nv, true)
                    task.spawn(function() pcall(applyToggle, cfgK, nv) end)
                end)
            end
            return row
        end

        local function addCustHeader(host, text, idx)
            _order = _order + 1
            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, 24); row.BackgroundTransparency = 1; row.LayoutOrder = _order

            if _ctReorderMode then
                local xBtn = Instance.new("TextButton", row)
                xBtn.Size = UDim2.new(0, 20, 0, 24); xBtn.Position = UDim2.new(0, 4, 0, 0)
                xBtn.BackgroundTransparency = 1; xBtn.AutoButtonColor = false; xBtn.BorderSizePixel = 0
                xBtn.Text = "x"; xBtn.TextColor3 = Color3.fromRGB(255, 80, 80); xBtn.TextTransparency = 0.5
                xBtn.TextSize = 11; xBtn.Font = FONT; xBtn.ZIndex = 4
                xBtn.MouseButton1Click:Connect(function()
                    table.remove(Config.CustomTab, idx); SaveConfig(); rebuildCustomTab()
                end)
            end

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -28, 1, 0); lbl.Position = UDim2.new(0, _ctReorderMode and 24 or 2, 0, 0)
            lbl.BackgroundTransparency = 1; lbl.Text = string.upper(text)
            lbl.TextColor3 = WHITE; lbl.TextTransparency = 0.1; lbl.TextSize = 11; lbl.Font = FONT
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Bottom
            local lblPad = Instance.new("UIPadding", lbl); lblPad.PaddingBottom = UDim.new(0, 4)

            if _ctReorderMode then
                row.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        startDrag(row, idx, string.upper(text))
                    end
                end)
            end
            return row
        end

        local function addCustModule(host, feat, idx)
            feat.builder(host)

            local row
            for _, c in ipairs(host:GetChildren()) do
                if c:IsA("Frame") and c.LayoutOrder == _order and not c:IsA("UIListLayout") then
                    row = c
                end
            end
            if not row then return nil end

            if _ctReorderMode then
                for _, d in ipairs(row:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == "⋮⋮" then
                        d.Text = "x"; d.TextColor3 = Color3.fromRGB(255, 80, 80); d.TextTransparency = 0.5
                        d.TextSize = 11
                        local xOver = Instance.new("TextButton", d.Parent)
                        xOver.Size = d.Size; xOver.Position = d.Position
                        xOver.BackgroundTransparency = 1; xOver.AutoButtonColor = false; xOver.Text = ""
                        xOver.ZIndex = d.ZIndex + 1; xOver.BorderSizePixel = 0
                        xOver.MouseButton1Click:Connect(function()
                            table.remove(Config.CustomTab, idx); SaveConfig(); rebuildCustomTab()
                        end)
                        break
                    end
                end
                row.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        startDrag(row, idx, feat.label)
                    end
                end)
            else
                for _, d in ipairs(row:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == "⋮⋮" then
                        d:Destroy()
                    elseif d:IsA("TextLabel") and d.Position.X.Offset == 28 then
                        d.Position = UDim2.new(0, 12, 0, 0)
                    end
                end
            end

            return row
        end

        local function addCustKeybind(host, feat, idx)
            _order = _order + 1
            local row = Instance.new("Frame", host)
            row.Size = UDim2.new(1, 0, 0, ROW_H); row.BackgroundTransparency = 1; row.LayoutOrder = _order
            if _ctReorderMode then
                makeRemoveBtn(row, idx)
                local lbl = Instance.new("TextLabel", row)
                lbl.Size = UDim2.new(1, -12, 1, 0); lbl.Position = UDim2.new(0, 26, 0, 0)
                lbl.BackgroundTransparency = 1; lbl.Text = feat.kLabel; lbl.TextColor3 = WHITE; lbl.TextTransparency = 0.52
                lbl.TextSize = 12; lbl.Font = FONT; lbl.TextXAlignment = Enum.TextXAlignment.Left
                row.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        startDrag(row, idx, feat.kLabel)
                    end
                end)
            else
                local inner = Instance.new("Frame", row)
                inner.Size = UDim2.new(1, 0, 1, 0); inner.Position = UDim2.new(0, 0, 0, 0)
                inner.BackgroundTransparency = 1
                local iLay = Instance.new("UIListLayout", inner); iLay.SortOrder = Enum.SortOrder.LayoutOrder
                addKeybindRow(inner, feat.kLabel, feat.kConfig)
                for _, d in ipairs(inner:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == "⋮⋮" then
                        d:Destroy()
                    elseif d:IsA("TextLabel") and d.Position.X.Offset == 28 then
                        d.Position = UDim2.new(0, 12, 0, 0)
                    end
                end
            end
            return row
        end

        rebuildCustomTab = function()
            local _ok, _err = pcall(function()
            host3.AutomaticSize = Enum.AutomaticSize.Y
            for _, c in ipairs(host3:GetChildren()) do pcall(function() c:Destroy() end) end
            local newLay = Instance.new("UIListLayout", host3)
            newLay.Padding = UDim.new(0, 6); newLay.SortOrder = Enum.SortOrder.LayoutOrder
            layouts[3] = newLay
            -- re-add the edge inset (the clear above destroys the original) so row outlines aren't clipped
            local newPad = Instance.new("UIPadding", host3)
            newPad.PaddingLeft = UDim.new(0, 2); newPad.PaddingRight = UDim.new(0, 2)
            if hookLayout3Resize then hookLayout3Resize() end
            _order = 2000; _ctItemFrames = {}
            migrateCustomTab()
            local list = Config.CustomTab or {}

            if #list == 0 then
                _order = _order + 1
                local empty = Instance.new("TextLabel", host3)
                empty.Name = "EmptyState"
                empty.Size = UDim2.new(1, 0, 0, 50); empty.BackgroundTransparency = 1; empty.LayoutOrder = _order
                empty.Text = "Tap + to add features" .. string.char(10) .. "and build your layout"
                empty.TextColor3 = CAT_COL; empty.TextTransparency = 0.3
                empty.TextSize = 12; empty.Font = FONT
                empty.TextXAlignment = Enum.TextXAlignment.Center; empty.TextYAlignment = Enum.TextYAlignment.Center
            else
                for idx, item in ipairs(list) do
                    local frame
                    if item.header then
                        frame = addCustHeader(host3, item.header, idx)
                    else
                        local feat = ALL_FEATURES[item.key]
                        if feat then
                            if feat.type == "toggle" then frame = addCustToggle(host3, feat, idx)
                            elseif feat.type == "module" then frame = addCustModule(host3, feat, idx)
                            elseif feat.type == "keybind" then frame = addCustKeybind(host3, feat, idx) end
                        end
                    end
                    if frame then _ctItemFrames[idx] = frame end
                end
            end

            if not _ctReorderMode then applyTabShadows(host3) end

            _order = _order + 1
            local actionBar = Instance.new("Frame", host3)
            actionBar.Name = "ActionBar"
            actionBar.Size = UDim2.new(1, 0, 0, 28); actionBar.BackgroundTransparency = 1; actionBar.LayoutOrder = _order
            local abLay = Instance.new("UIListLayout", actionBar)
            abLay.FillDirection = Enum.FillDirection.Horizontal; abLay.Padding = UDim.new(0, 4); abLay.SortOrder = Enum.SortOrder.LayoutOrder

            local function makeActionBtn(text, ord, w, cb, bg)
                local b = Instance.new("TextButton", actionBar)
                b.Size = w; b.LayoutOrder = ord
                b.AutoButtonColor = false; b.Text = text; b.BorderSizePixel = 0
                b.BackgroundColor3 = bg or DARK; b.TextColor3 = WHITE; b.TextTransparency = 0.3; b.TextSize = 11; b.Font = FONT
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
                local s = Instance.new("UIStroke", b); s.Color = WHITE; s.Thickness = 1; s.Transparency = 0.88
                b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = BOX_ON }):Play() end)
                b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = bg or DARK }):Play() end)
                b.MouseButton1Click:Connect(cb)
                return b
            end

            if _ctReorderMode then
                makeActionBtn("Done", 1, UDim2.new(1, 0, 1, 0), function()
                    _ctReorderMode = false; rebuildCustomTab()
                end, Color3.fromRGB(40, 56, 92))
            else

            local _thirdW = UDim2.new(1/3, -3, 1, 0)
            makeActionBtn("+ Feature", 1, _thirdW, function()
                if customPickerOpen then return end
                customPickerOpen = true
                local pickerSg = Instance.new("ScreenGui")
                pickerSg.Name = "MeerkoCustomPicker"; pickerSg.ResetOnSpawn = false; pickerSg.DisplayOrder = 200
                do local _cr = cloneref or function(x) return x end
                    pcall(function() pickerSg.Parent = _cr(game:GetService("CoreGui")) end)
                    if not pickerSg.Parent then pickerSg.Parent = PlayerGui end end
                local bd = Instance.new("TextButton", pickerSg)
                bd.Size = UDim2.new(1,0,1,0); bd.BackgroundColor3 = Color3.new(0,0,0); bd.BackgroundTransparency = 0.5
                bd.Text = ""; bd.AutoButtonColor = false; bd.BorderSizePixel = 0
                local pf = Instance.new("Frame", pickerSg)
                pf.AnchorPoint = Vector2.new(0.5,0.5); pf.Position = UDim2.new(0.5,0,0.5,0); pf.Size = UDim2.new(0,260,0,360)
                pf.BackgroundColor3 = C_BG; pf.BorderSizePixel = 0
                Instance.new("UICorner", pf).CornerRadius = UDim.new(0,12)
                local pfS = Instance.new("UIStroke", pf); pfS.Color = WHITE; pfS.Thickness = 1; pfS.Transparency = 0.92
                local pt = Instance.new("TextLabel", pf)
                pt.Size = UDim2.new(1,-16,0,36); pt.Position = UDim2.new(0,8,0,0); pt.BackgroundTransparency = 1
                pt.Text = "Add Feature"; pt.TextColor3 = WHITE; pt.TextSize = 14; pt.Font = FONT
                pt.TextXAlignment = Enum.TextXAlignment.Left; pt.TextYAlignment = Enum.TextYAlignment.Center
                local cb = Instance.new("TextButton", pf)
                cb.Size = UDim2.new(0,30,0,30); cb.Position = UDim2.new(1,-34,0,3); cb.BackgroundTransparency = 1
                cb.Text = "×"; cb.TextColor3 = WHITE; cb.TextTransparency = 0.3; cb.TextSize = 18; cb.Font = FONT; cb.AutoButtonColor = false
                local pd = Instance.new("Frame", pf); pd.Size = UDim2.new(1,-16,0,1); pd.Position = UDim2.new(0,8,0,36)
                pd.BackgroundColor3 = WHITE; pd.BackgroundTransparency = 0.92; pd.BorderSizePixel = 0
                local sc = Instance.new("ScrollingFrame", pf)
                sc.Size = UDim2.new(1,-16,1,-48); sc.Position = UDim2.new(0,8,0,42); sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0
                sc.ScrollBarThickness = 3; sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.CanvasSize = UDim2.new(0,0,0,0)
                sc.ScrollBarImageColor3 = Color3.fromRGB(100,170,255)
                local sL = Instance.new("UIListLayout", sc); sL.Padding = UDim.new(0,4); sL.SortOrder = Enum.SortOrder.LayoutOrder
                local ex = {}
                for _, it in ipairs(Config.CustomTab or {}) do if it.key then ex[it.key] = true end end
                local sorted = {}
                for _, f in pairs(ALL_FEATURES) do if not ex[f.key] then sorted[#sorted+1] = f end end
                table.sort(sorted, function(a,b) return a.label < b.label end)
                local pO = 0
                for _, feat in ipairs(sorted) do
                    pO = pO + 1
                    local fb = Instance.new("TextButton", sc)
                    fb.Size = UDim2.new(1,0,0,30); fb.LayoutOrder = pO; fb.AutoButtonColor = false; fb.Text = ""; fb.BorderSizePixel = 0
                    fb.BackgroundColor3 = DARK; fb.BackgroundTransparency = 0.12
                    Instance.new("UICorner", fb).CornerRadius = UDim.new(0,8)
                    local fl = Instance.new("TextLabel", fb)
                    fl.Size = UDim2.new(1,-48,1,0); fl.Position = UDim2.new(0,12,0,0); fl.BackgroundTransparency = 1
                    fl.Text = feat.label; fl.TextColor3 = WHITE; fl.TextTransparency = 0.2; fl.TextSize = 12; fl.Font = FONT
                    fl.TextXAlignment = Enum.TextXAlignment.Left; fl.TextYAlignment = Enum.TextYAlignment.Center
                    local tl = Instance.new("TextLabel", fb)
                    tl.Size = UDim2.new(0,40,1,0); tl.Position = UDim2.new(1,-48,0,0); tl.BackgroundTransparency = 1
                    tl.Text = feat.type == "module" and "MOD" or feat.type == "keybind" and "KEY" or ""
                    tl.TextColor3 = CAT_COL; tl.TextTransparency = 0.4; tl.TextSize = 9; tl.Font = FONT; tl.TextXAlignment = Enum.TextXAlignment.Right
                    fb.MouseEnter:Connect(function() TweenService:Create(fb, TweenInfo.new(0.12), {BackgroundColor3=BOX_ON}):Play() end)
                    fb.MouseLeave:Connect(function() TweenService:Create(fb, TweenInfo.new(0.12), {BackgroundColor3=DARK}):Play() end)
                    fb.MouseButton1Click:Connect(function()
                        if not Config.CustomTab then Config.CustomTab = {} end
                        table.insert(Config.CustomTab, {key=feat.key}); SaveConfig()
                        pickerSg:Destroy(); customPickerOpen = false; rebuildCustomTab()
                    end)
                end
                local function cp() pickerSg:Destroy(); customPickerOpen = false end
                cb.MouseButton1Click:Connect(cp); bd.MouseButton1Click:Connect(cp)
            end)

            makeActionBtn("+ Header", 2, _thirdW, function()
                if customPickerOpen then return end
                customPickerOpen = true
                local hSg = Instance.new("ScreenGui")
                hSg.Name = "MeerkoHeaderInput"; hSg.ResetOnSpawn = false; hSg.DisplayOrder = 200
                do local _cr = cloneref or function(x) return x end
                    pcall(function() hSg.Parent = _cr(game:GetService("CoreGui")) end)
                    if not hSg.Parent then hSg.Parent = PlayerGui end end
                local bd = Instance.new("TextButton", hSg)
                bd.Size = UDim2.new(1,0,1,0); bd.BackgroundColor3 = Color3.new(0,0,0); bd.BackgroundTransparency = 0.5
                bd.Text = ""; bd.AutoButtonColor = false; bd.BorderSizePixel = 0
                local hf = Instance.new("Frame", hSg)
                hf.AnchorPoint = Vector2.new(0.5,0.5); hf.Position = UDim2.new(0.5,0,0.5,0); hf.Size = UDim2.new(0,240,0,120)
                hf.BackgroundColor3 = C_BG; hf.BorderSizePixel = 0
                Instance.new("UICorner", hf).CornerRadius = UDim.new(0,12)
                local hfS = Instance.new("UIStroke", hf); hfS.Color = WHITE; hfS.Thickness = 1; hfS.Transparency = 0.92
                local ht = Instance.new("TextLabel", hf)
                ht.Size = UDim2.new(1,-16,0,32); ht.Position = UDim2.new(0,8,0,0); ht.BackgroundTransparency = 1
                ht.Text = "Header Name"; ht.TextColor3 = WHITE; ht.TextSize = 13; ht.Font = FONT
                ht.TextXAlignment = Enum.TextXAlignment.Left; ht.TextYAlignment = Enum.TextYAlignment.Center
                local inp = Instance.new("TextBox", hf)
                inp.Size = UDim2.new(1,-24,0,30); inp.Position = UDim2.new(0,12,0,36)
                inp.BackgroundColor3 = DARK; inp.BorderSizePixel = 0; inp.TextColor3 = WHITE
                inp.PlaceholderText = "e.g. MY VISUALS"; inp.PlaceholderColor3 = CAT_COL
                inp.Text = ""; inp.TextSize = 12; inp.Font = FONT; inp.ClearTextOnFocus = false
                Instance.new("UICorner", inp).CornerRadius = UDim.new(0,8)
                Instance.new("UIPadding", inp).PaddingLeft = UDim.new(0,8)
                local addH = Instance.new("TextButton", hf)
                addH.Size = UDim2.new(1,-24,0,28); addH.Position = UDim2.new(0,12,0,76)
                addH.AutoButtonColor = false; addH.Text = "Add Header"; addH.BorderSizePixel = 0
                addH.BackgroundColor3 = BOX_ON; addH.TextColor3 = WHITE; addH.TextSize = 12; addH.Font = FONT
                Instance.new("UICorner", addH).CornerRadius = UDim.new(0,8)
                addH.MouseButton1Click:Connect(function()
                    local txt = inp.Text:match("^%s*(.-)%s*$")
                    if txt and #txt > 0 then
                        if not Config.CustomTab then Config.CustomTab = {} end
                        table.insert(Config.CustomTab, {header=txt}); SaveConfig()
                    end
                    hSg:Destroy(); customPickerOpen = false; rebuildCustomTab()
                end)
                local function ch() hSg:Destroy(); customPickerOpen = false end
                bd.MouseButton1Click:Connect(ch)
                task.defer(function() inp:CaptureFocus() end)
            end)

            makeActionBtn("Reorder", 3, _thirdW, function()
                _ctReorderMode = true; rebuildCustomTab()
            end)

            end -- else (not reorder mode)

            if activeTab == 3 then
                task.defer(function() mf.Size = UDim2.new(0, W, 0, targetHeight()) end)
            end
            end) -- pcall
            local _ = _ok
        end
        local _rbOk, _rbErr = pcall(rebuildCustomTab)
        local _ = _rbOk

        local _ct3SizeConn = nil
        local function hookLayout3Resize()
            if _ct3SizeConn then _ct3SizeConn:Disconnect() end
            _ct3SizeConn = layouts[3]:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                if activeTab == 3 and not _ctDrag then
                    mf.Size = UDim2.new(0, W, 0, targetHeight())
                end
            end)
        end
        hookLayout3Resize()

        setTab(1, false)

        -- Legacy "Main / More / Custom" menu fully removed: never show it, don't bind
        -- it to the menu key, and destroy it. The FreeGUI menu is the only menu now.
        sg.Enabled = false
        task.defer(function() pcall(function() sg:Destroy() end) end)
    end)

    -- =================================================================
    -- NEW UI (FreeGUI redesign) - Turn 1: foundation + simple toggles
    -- =================================================================
    task.spawn(function()
        task.wait(1.5)

        -- Disable legacy FeaturesPanel ScreenGui
        local _cloneref = cloneref or function(x) return x end
        local function hideLegacy()
            local roots = {}
            local ok, cg = pcall(function() return _cloneref(game:GetService("CoreGui")) end)
            if ok and cg then table.insert(roots, cg) end
            table.insert(roots, MK_PlayerGui)
            for _, root in ipairs(roots) do
                if root then
                    for _, child in ipairs(root:GetChildren()) do
                        if child:IsA("ScreenGui") and child.Name == "FeaturesPanel" then
                            pcall(function() child.Enabled = false end)
                        end
                    end
                end
            end
        end
        hideLegacy()

        -- ============================================================
        -- FreeGUI library (inlined from message (20).txt)
        -- ============================================================
        local TweenService = game:GetService("TweenService")
        local FG_UIS = game:GetService("UserInputService")
        local RunService = game:GetService("RunService")
        local rgb = Color3.fromRGB

        local FG_Theme = {
            Window   = rgb(240, 242, 248),
            WindowB  = rgb(248, 249, 253),
            Sidebar  = rgb(230, 233, 244),
            TopBar   = rgb(236, 238, 247),
            Card     = rgb(255, 255, 255),
            CardAlt  = rgb(245, 246, 251),
            CardAlt2 = rgb(233, 235, 245),
            Stroke   = rgb(213, 216, 230),
            StrokeS  = rgb(192, 196, 216),
            Text     = rgb(32, 34, 46),
            SubText  = rgb(78, 82, 100),
            Faint    = rgb(128, 132, 152),
            Accent   = rgb(99, 102, 241),
            Accent2  = rgb(147, 90, 235),
            AccentSoft = rgb(226, 227, 250),
            Green    = rgb(34, 170, 90),
            Green2   = rgb(58, 196, 112),
            Track    = rgb(216, 219, 232),
            Shadow   = rgb(0, 0, 0),
        }

        local function fg_new(class, props, children)
            local inst = Instance.new(class)
            if props then
                for k, v in pairs(props) do
                    if k ~= "Parent" then inst[k] = v end
                end
            end
            if children then
                for _, c in ipairs(children) do c.Parent = inst end
            end
            if props and props.Parent then inst.Parent = props.Parent end
            return inst
        end

        local function fg_tween(o, t, props, style, dir)
            local info = TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
            local tw = TweenService:Create(o, info, props)
            tw:Play()
            return tw
        end

        local function fg_corner(parent, r)
            return fg_new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
        end

        local function fg_stroke(parent, color, thick, trans)
            return fg_new("UIStroke", {
                Color = color or FG_Theme.Stroke,
                Thickness = thick or 1,
                Transparency = trans or 0,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Parent = parent,
            })
        end

        local function fg_gradient(parent, c1, c2, rot)
            return fg_new("UIGradient", {
                Color = ColorSequence.new(c1, c2),
                Rotation = rot or 0,
                Parent = parent,
            })
        end

        local function fg_pad(parent, t, b, l, r)
            return fg_new("UIPadding", {
                PaddingTop = UDim.new(0, t or 0),
                PaddingBottom = UDim.new(0, b or 0),
                PaddingLeft = UDim.new(0, l or 0),
                PaddingRight = UDim.new(0, r or 0),
                Parent = parent,
            })
        end

        local function iconGrid(size, color)
            local f = fg_new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
            local s = math.floor((size - 3) / 2)
            local positions = { { 0, 0 }, { s + 3, 0 }, { 0, s + 3 }, { s + 3, s + 3 } }
            for _, p in ipairs(positions) do
                local cell = fg_new("Frame", {
                    BackgroundColor3 = color,
                    Position = UDim2.fromOffset(p[1], p[2]),
                    Size = UDim2.fromOffset(s, s),
                    Parent = f,
                })
                fg_corner(cell, 2)
            end
            return f
        end

        local function iconDots(color)
            local f = fg_new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 16) })
            for i = 0, 2 do
                local d = fg_new("Frame", {
                    BackgroundColor3 = color,
                    AnchorPoint = Vector2.new(0.5, 0),
                    Position = UDim2.new(0.5, 0, 0, i * 6),
                    Size = UDim2.fromOffset(4, 4),
                    Parent = f,
                })
                fg_corner(d, 4)
            end
            return f
        end

        local function iconPencil(size, color)
            local f = fg_new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
            local body = fg_new("Frame", {
                BackgroundColor3 = color,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(math.floor(size * 0.7), 3),
                Rotation = -45,
                Parent = f,
            })
            fg_corner(body, 2)
            local tip = fg_new("Frame", {
                BackgroundColor3 = color,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, math.floor(size * 0.26), 0.5, math.floor(size * 0.26)),
                Size = UDim2.fromOffset(4, 4),
                Rotation = 45,
                Parent = f,
            })
            fg_corner(tip, 1)
            return f
        end

        local function iconSearch(size, color)
            local f = fg_new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
            local ring = fg_new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.fromOffset(math.floor(size * 0.66), math.floor(size * 0.66)),
                Parent = f,
            })
            fg_corner(ring, size)
            fg_stroke(ring, color, 2)
            local handle = fg_new("Frame", {
                BackgroundColor3 = color,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(1, -3, 1, -3),
                Size = UDim2.fromOffset(math.floor(size * 0.34), 2),
                Rotation = 45,
                Parent = f,
            })
            fg_corner(handle, 2)
            return f
        end

        local function fg_guiParent()
            local ok, hui = pcall(function() return gethui() end)
            if ok and hui then return hui end
            local ok2, cg = pcall(function() return _cloneref(game:GetService("CoreGui")) end)
            if ok2 and cg then return cg end
            return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        end

        -- ============= Section class =============
        local Section = {}
        Section.__index = Section

        function Section.new(column, title)
            local self = setmetatable({}, Section)
            self.order = 1
            local card = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Card,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = column,
            })
            fg_corner(card, 11)
            local accent = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Accent,
                Size = UDim2.new(1, -22, 0, 2),
                Position = UDim2.new(0, 11, 0, 0),
                Parent = card,
            })
            fg_corner(accent, 2)
            fg_gradient(accent, FG_Theme.Accent, FG_Theme.Accent2, 0)
            local body = fg_new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = card,
            })
            fg_pad(body, 12, 14, 14, 14)
            fg_new("UIListLayout", {
                Padding = UDim.new(0, 9),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = body,
            })
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = title or "section",
                Font = Enum.Font.GothamBold,
                TextSize = 14,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 0, 20),
                LayoutOrder = 1,
                Parent = body,
            })
            self.card = body
            return self
        end

        function Section:_row(h)
            self.order = self.order + 1
            local row = fg_new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, h),
                LayoutOrder = self.order,
                Parent = self.card,
            })
            return row
        end

        function Section:AddButton(o)
            o = o or {}
            local row = self:_row(34)
            local btn = fg_new("TextButton", {
                BackgroundColor3 = FG_Theme.CardAlt,
                Size = UDim2.fromScale(1, 1),
                Text = o.Text or "button",
                Font = Enum.Font.GothamSemibold,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                AutoButtonColor = false,
                Parent = row,
            })
            fg_corner(btn, 8)
            fg_stroke(btn, FG_Theme.Stroke, 1)
            btn.MouseEnter:Connect(function() fg_tween(btn, 0.16, { BackgroundColor3 = FG_Theme.CardAlt2 }) end)
            btn.MouseLeave:Connect(function() fg_tween(btn, 0.16, { BackgroundColor3 = FG_Theme.CardAlt }) end)
            btn.MouseButton1Down:Connect(function() fg_tween(btn, 0.08, { Size = UDim2.new(1, -6, 0, 30) }) end)
            btn.MouseButton1Up:Connect(function() fg_tween(btn, 0.16, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back) end)
            btn.MouseButton1Click:Connect(function()
                if o.Callback then task.spawn(o.Callback) end
            end)
            return btn
        end

        function Section:AddSlider(o)
            o = o or {}
            local min, max = o.Min or 0, o.Max or 100
            local value = o.Default or min
            local suffix = o.Suffix or ""
            local row = self:_row(44)
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "slider",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(0.6, 0, 0, 18),
                Parent = row,
            })
            local valLabel = fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = tostring(value) .. suffix,
                Font = Enum.Font.GothamSemibold,
                TextSize = 13,
                TextColor3 = FG_Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Right,
                Size = UDim2.new(1, 0, 0, 18),
                Parent = row,
            })
            local track = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Track,
                Position = UDim2.new(0, 0, 0, 30),
                Size = UDim2.new(1, 0, 0, 6),
                Parent = row,
            })
            fg_corner(track, 6)
            local fill = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Accent,
                Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
                Parent = track,
            })
            fg_corner(fill, 6)
            fg_gradient(fill, FG_Theme.Accent, FG_Theme.Accent2, 0)
            local knob = fg_new("Frame", {
                BackgroundColor3 = rgb(255, 255, 255),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                Parent = track,
            })
            fg_corner(knob, 14)
            fg_stroke(knob, FG_Theme.StrokeS, 1.5)
            local sliding = false
            local function set(v, animate)
                v = math.clamp(math.floor(v + 0.5), min, max)
                value = v
                local rel = (v - min) / (max - min)
                valLabel.Text = tostring(v) .. suffix
                if animate then
                    fg_tween(fill, 0.1, { Size = UDim2.new(rel, 0, 1, 0) })
                    fg_tween(knob, 0.1, { Position = UDim2.new(rel, 0, 0.5, 0) })
                else
                    fill.Size = UDim2.new(rel, 0, 1, 0)
                    knob.Position = UDim2.new(rel, 0, 0.5, 0)
                end
                if o.Callback then task.spawn(o.Callback, v) end
            end
            local function update(input)
                local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                set(min + (max - min) * rel)
            end
            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    fg_tween(knob, 0.12, { Size = UDim2.fromOffset(18, 18) })
                    update(input)
                end
            end)
            FG_UIS.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    update(input)
                end
            end)
            FG_UIS.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    if sliding then fg_tween(knob, 0.12, { Size = UDim2.fromOffset(14, 14) }) end
                    sliding = false
                end
            end)
            return { Set = function(_, v) set(v, true) end, Get = function() return value end }
        end

        function Section:AddToggle(o)
            o = o or {}
            local state = o.Default or false
            local row = self:_row(26)
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "toggle",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, -50, 1, 0),
                Parent = row,
            })
            local sw = fg_new("TextButton", {
                BackgroundColor3 = state and FG_Theme.Green or FG_Theme.Track,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(40, 22),
                Text = "",
                AutoButtonColor = false,
                Parent = row,
            })
            fg_corner(sw, 11)
            local g = fg_gradient(sw, FG_Theme.Green2, FG_Theme.Green, 90)
            g.Enabled = state
            local knob = fg_new("Frame", {
                BackgroundColor3 = rgb(255, 255, 255),
                AnchorPoint = Vector2.new(state and 1 or 0, 0.5),
                Position = UDim2.new(state and 1 or 0, state and -3 or 3, 0.5, 0),
                Size = UDim2.fromOffset(16, 16),
                Parent = sw,
            })
            fg_corner(knob, 16)
            fg_stroke(knob, rgb(0, 0, 0), 0, 1)
            local function set(v)
                state = v
                g.Enabled = v
                fg_tween(sw, 0.18, { BackgroundColor3 = v and FG_Theme.Green or FG_Theme.Track })
                fg_tween(knob, 0.18, {
                    AnchorPoint = Vector2.new(v and 1 or 0, 0.5),
                    Position = UDim2.new(v and 1 or 0, v and -3 or 3, 0.5, 0),
                }, Enum.EasingStyle.Back)
                if o.Callback then task.spawn(o.Callback, v) end
            end
            sw.MouseButton1Click:Connect(function() set(not state) end)
            return { Set = function(_, v) set(v) end, Get = function() return state end }
        end

        function Section:AddLabel(o)
            o = o or {}
            local row = self:_row(24)
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "label",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, -30, 1, 0),
                Parent = row,
            })
            if o.Right == "color" or typeof(o.Right) == "Color3" then
                local dot = fg_new("Frame", {
                    BackgroundColor3 = typeof(o.Right) == "Color3" and o.Right or FG_Theme.Green,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(20, 20),
                    Parent = row,
                })
                fg_corner(dot, 6)
            end
            return row
        end

        function Section:AddInput(o)
            o = o or {}
            local row = self:_row(38)
            local box = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.CardAlt,
                Size = UDim2.fromScale(1, 1),
                Parent = row,
            })
            fg_corner(box, 8)
            local bs = fg_stroke(box, FG_Theme.Stroke, 1)
            local tb = fg_new("TextBox", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 0),
                Size = UDim2.new(1, -44, 1, 0),
                Text = o.Text or "",
                PlaceholderText = o.Placeholder or "placeholder",
                PlaceholderColor3 = FG_Theme.Faint,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
                Parent = box,
            })
            local pen = iconPencil(16, FG_Theme.SubText)
            pen.AnchorPoint = Vector2.new(1, 0.5)
            pen.Position = UDim2.new(1, -12, 0.5, 0)
            pen.Parent = box
            tb.Focused:Connect(function() fg_tween(bs, 0.16, { Color = FG_Theme.Accent }) end)
            tb.FocusLost:Connect(function()
                fg_tween(bs, 0.16, { Color = FG_Theme.Stroke })
                if o.Callback then task.spawn(o.Callback, tb.Text) end
            end)
            return tb
        end

        function Section:AddDivider()
            local row = self:_row(6)
            fg_new("Frame", {
                Name = "TitleDivider",
                Size = UDim2.new(1, -16, 0, 1),
                Position = UDim2.new(0, 8, 0, 2),
                BackgroundColor3 = Color3.fromRGB(45, 50, 65),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = row,
            })
            return row
        end

        -- Float / stepped slider with custom formatter
        function Section:AddSliderF(o)
            o = o or {}
            local min, max = o.Min or 0, o.Max or 1
            local step = o.Step or 0.01
            local value = o.Default or min
            local fmt = o.Format or function(v) return tostring(v) end
            local row = self:_row(44)
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "slider",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(0.6, 0, 0, 18),
                Parent = row,
            })
            local valLabel = fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = fmt(value),
                Font = Enum.Font.GothamSemibold,
                TextSize = 13,
                TextColor3 = FG_Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Right,
                Size = UDim2.new(1, 0, 0, 18),
                Parent = row,
            })
            local track = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Track,
                Position = UDim2.new(0, 0, 0, 30),
                Size = UDim2.new(1, 0, 0, 6),
                Parent = row,
            })
            fg_corner(track, 6)
            local fill = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Accent,
                Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
                Parent = track,
            })
            fg_corner(fill, 6)
            fg_gradient(fill, FG_Theme.Accent, FG_Theme.Accent2, 0)
            local knob = fg_new("Frame", {
                BackgroundColor3 = rgb(255, 255, 255),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                Parent = track,
            })
            fg_corner(knob, 14)
            fg_stroke(knob, FG_Theme.StrokeS, 1.5)
            local sliding = false
            local function set(v, animate)
                v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
                value = v
                local rel = (max == min) and 0 or (v - min) / (max - min)
                valLabel.Text = fmt(v)
                if animate then
                    fg_tween(fill, 0.08, { Size = UDim2.new(rel, 0, 1, 0) })
                    fg_tween(knob, 0.08, { Position = UDim2.new(rel, 0, 0.5, 0) })
                else
                    fill.Size = UDim2.new(rel, 0, 1, 0)
                    knob.Position = UDim2.new(rel, 0, 0.5, 0)
                end
                if o.Callback then task.spawn(o.Callback, v) end
            end
            local function update(input)
                local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                set(min + (max - min) * rel)
            end
            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    fg_tween(knob, 0.12, { Size = UDim2.fromOffset(18, 18) })
                    update(input)
                end
            end)
            FG_UIS.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    update(input)
                end
            end)
            FG_UIS.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    if sliding then fg_tween(knob, 0.12, { Size = UDim2.fromOffset(14, 14) }) end
                    sliding = false
                end
            end)
            return { Set = function(_, v) set(v, true) end, Get = function() return value end }
        end

        function Section:AddDropdown(o)
            o = o or {}
            local options = o.Options or { "value" }
            local value = o.Default or options[1]
            self.order = self.order + 1
            local holder = fg_new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = self.order,
                Parent = self.card,
            })
            fg_new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "dropdown",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 0, 18),
                LayoutOrder = 0,
                Parent = holder,
            })
            local valBox = fg_new("TextButton", {
                BackgroundColor3 = FG_Theme.CardAlt,
                Size = UDim2.new(1, 0, 0, 34),
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = 1,
                Parent = holder,
            })
            fg_corner(valBox, 8)
            local vbs = fg_stroke(valBox, FG_Theme.Stroke, 1)
            local valText = fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = value,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.fromOffset(12, 0),
                Size = UDim2.new(1, -44, 1, 0),
                Parent = valBox,
            })
            local grid = iconGrid(16, FG_Theme.SubText)
            grid.AnchorPoint = Vector2.new(1, 0.5)
            grid.Position = UDim2.new(1, -12, 0.5, 0)
            grid.Parent = valBox
            local list = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Card,
                Size = UDim2.new(1, 0, 0, 0),
                ClipsDescendants = true,
                LayoutOrder = 2,
                Parent = holder,
            })
            fg_corner(list, 8)
            fg_stroke(list, FG_Theme.Stroke, 1)
            fg_new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
            fg_pad(list, 4, 4, 4, 4)
            local rowH = 28
            local function buildOptions()
                for _, c in ipairs(list:GetChildren()) do
                    if c:IsA("TextButton") then c:Destroy() end
                end
                for i, opt in ipairs(options) do
                    local ob = fg_new("TextButton", {
                        BackgroundColor3 = FG_Theme.CardAlt,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, rowH),
                        Text = opt,
                        Font = Enum.Font.GothamMedium,
                        TextSize = 13,
                        TextColor3 = (opt == value) and FG_Theme.Accent or FG_Theme.SubText,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        AutoButtonColor = false,
                        LayoutOrder = i,
                        Parent = list,
                    })
                    fg_corner(ob, 6)
                    fg_pad(ob, 0, 0, 8, 0)
                    ob.MouseEnter:Connect(function() fg_tween(ob, 0.12, { BackgroundTransparency = 0 }) end)
                    ob.MouseLeave:Connect(function() fg_tween(ob, 0.12, { BackgroundTransparency = 1 }) end)
                    ob.MouseButton1Click:Connect(function()
                        value = opt
                        valText.Text = opt
                        for _, c in ipairs(list:GetChildren()) do
                            if c:IsA("TextButton") then c.TextColor3 = (c.Text == opt) and FG_Theme.Accent or FG_Theme.SubText end
                        end
                        if o.Callback then task.spawn(o.Callback, opt) end
                    end)
                end
            end
            buildOptions()
            local open = false
            valBox.MouseButton1Click:Connect(function()
                open = not open
                local h = open and (#options * rowH + 8) or 0
                fg_tween(list, 0.2, { Size = UDim2.new(1, 0, 0, h) }, Enum.EasingStyle.Quart)
                fg_tween(grid, 0.2, { Rotation = open and 90 or 0 })
                fg_tween(vbs, 0.16, { Color = open and FG_Theme.Accent or FG_Theme.Stroke })
            end)
            return { Get = function() return value end }
        end

        function Section:AddKeybind(o)
            o = o or {}
            local row = self:_row(34)
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = o.Text or "keybind",
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, -116, 1, 0),
                Parent = row,
            })
            local keyBtn = fg_new("TextButton", {
                BackgroundColor3 = FG_Theme.Accent,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -32, 0.5, 0),
                Size = UDim2.fromOffset(76, 26),
                Text = "NONE",
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = rgb(255, 255, 255),
                AutoButtonColor = false,
                Parent = row,
            })
            fg_corner(keyBtn, 7)
            fg_gradient(keyBtn, FG_Theme.Accent, FG_Theme.Accent2, 45)
            local clearBtn = fg_new("TextButton", {
                BackgroundColor3 = FG_Theme.CardAlt,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(26, 26),
                Text = "✕",
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = FG_Theme.SubText,
                AutoButtonColor = false,
                Parent = row,
            })
            fg_corner(clearBtn, 7)
            fg_stroke(clearBtn, FG_Theme.Stroke, 1)

            local function refresh()
                local k = o.Get and o.Get() or ""
                keyBtn.Text = (type(k) == "string" and k ~= "") and k or "NONE"
            end
            refresh()

            keyBtn.MouseEnter:Connect(function() fg_tween(keyBtn, 0.14, { BackgroundColor3 = FG_Theme.Accent2 }) end)
            keyBtn.MouseLeave:Connect(function() fg_tween(keyBtn, 0.14, { BackgroundColor3 = FG_Theme.Accent }) end)
            clearBtn.MouseEnter:Connect(function() fg_tween(clearBtn, 0.14, { BackgroundColor3 = FG_Theme.CardAlt2 }) end)
            clearBtn.MouseLeave:Connect(function() fg_tween(clearBtn, 0.14, { BackgroundColor3 = FG_Theme.CardAlt }) end)

            keyBtn.MouseButton1Click:Connect(function()
                keyBtn.Text = "..."
                local con
                con = game:GetService("UserInputService").InputBegan:Connect(function(inp, gp)
                    if gp then return end
                    if inp.UserInputType == Enum.UserInputType.Keyboard then
                        con:Disconnect()
                        if o.Set then pcall(o.Set, inp.KeyCode.Name) end
                        refresh()
                    end
                end)
            end)
            clearBtn.MouseButton1Click:Connect(function()
                if o.Set then pcall(o.Set, "") end
                refresh()
            end)
            return { Refresh = refresh }
        end

        -- ============= Tab class =============
        local Tab = {}
        Tab.__index = Tab
        function Tab:AddSection(side, title)
            local col = (side == "right") and self.right or self.left
            return Section.new(col, title)
        end

        -- ============= Page class =============
        local Page = {}
        Page.__index = Page

        function Page:_styleTab(tab, active)
            tab.content.Visible = active
            fg_tween(tab.button, 0.18, { BackgroundColor3 = active and FG_Theme.AccentSoft or FG_Theme.TopBar })
            fg_tween(tab.button, 0.18, { BackgroundTransparency = active and 0 or 1 })
            fg_tween(tab.label, 0.18, { TextColor3 = active and FG_Theme.Accent or FG_Theme.SubText })
            tab.label.Font = active and Enum.Font.GothamBold or Enum.Font.GothamMedium
        end

        function Page:_select(tab)
            for _, t in ipairs(self.tabs) do
                self:_styleTab(t, t == tab)
            end
            self.active = tab
        end

        function Page:AddTab(o)
            o = o or {}
            local name = o.Name or "tab"
            local button = fg_new("TextButton", {
                BackgroundColor3 = FG_Theme.AccentSoft,
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 0, 1, -12),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "",
                AutoButtonColor = false,
                Parent = self.tabBar,
            })
            fg_corner(button, 8)
            fg_pad(button, 0, 0, 14, 14)
            local label = fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Text = name,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.SubText,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.new(0, 0, 1, 0),
                Parent = button,
            })
            local content = fg_new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Visible = false,
                Parent = self.pageFrame,
            })
            local left = fg_new("ScrollingFrame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(0.5, -6, 1, 0),
                Position = UDim2.fromScale(0, 0),
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = FG_Theme.Faint,
                BorderSizePixel = 0,
                Parent = content,
            })
            local right = fg_new("ScrollingFrame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(0.5, -6, 1, 0),
                Position = UDim2.new(0.5, 6, 0, 0),
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = FG_Theme.Faint,
                BorderSizePixel = 0,
                Parent = content,
            })
            for _, c in ipairs({ left, right }) do
                fg_new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
                fg_pad(c, 0, 12, 0, 0)
            end
            local tab = setmetatable({ button = button, label = label, content = content, left = left, right = right }, Tab)
            table.insert(self.tabs, tab)
            button.MouseEnter:Connect(function()
                if self.active ~= tab then fg_tween(label, 0.14, { TextColor3 = FG_Theme.Text }) end
            end)
            button.MouseLeave:Connect(function()
                if self.active ~= tab then fg_tween(label, 0.14, { TextColor3 = FG_Theme.SubText }) end
            end)
            button.MouseButton1Click:Connect(function() self:_select(tab) end)
            if #self.tabs == 1 then self:_select(tab) end
            return tab
        end

        -- ============= Library =============
        local Library = {}
        Library.__index = Library

        function Library:CreateWindow(o)
            o = o or {}
            local W, H = 720, 470
            local gui = fg_new("ScreenGui", {
                Name = "SexHub_FG",
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
                IgnoreGuiInset = true,
                DisplayOrder = 9999,
            })
            pcall(function()
                if syn and syn.protect_gui then syn.protect_gui(gui) end
            end)
            pcall(function()
                if protect_gui then protect_gui(gui) end
            end)
            gui.Parent = fg_guiParent()

            local shadow = fg_new("ImageLabel", {
                BackgroundTransparency = 1,
                Image = "rbxassetid://6014261993",
                ImageColor3 = FG_Theme.Shadow,
                ImageTransparency = 0.55,
                ScaleType = Enum.ScaleType.Slice,
                SliceCenter = Rect.new(49, 49, 450, 450),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(W + 60, H + 60),
                Parent = gui,
            })
            local main = fg_new("CanvasGroup", {
                BackgroundColor3 = FG_Theme.Window,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(W, H),
                GroupTransparency = 1,
                Parent = gui,
            })
            fg_corner(main, 14)
            fg_stroke(main, FG_Theme.Stroke, 1)
            fg_gradient(main, FG_Theme.Window, FG_Theme.WindowB, 90)

            local mainScale = fg_new("UIScale", {
                Scale = math.clamp(tonumber(Config.MainUIScale) or 1, 0.7, 1.4),
                Parent = main,
            })

            local sidebar = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Sidebar,
                Size = UDim2.new(0, 72, 1, 0),
                Parent = main,
            })
            fg_new("Frame", {
                Name = "TitleDivider",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.new(0, 1, 1, -16),
                BackgroundColor3 = Color3.fromRGB(45, 50, 65),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = sidebar,
            })
            local logo = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.Accent,
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 18),
                Size = UDim2.fromOffset(42, 42),
                Parent = sidebar,
            })
            fg_corner(logo, 12)
            fg_gradient(logo, FG_Theme.Accent, FG_Theme.Accent2, 45)
            local logoMark = fg_new("Frame", {
                BackgroundColor3 = rgb(255, 255, 255),
                BackgroundTransparency = 0.1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(16, 16),
                Rotation = 45,
                Parent = logo,
            })
            fg_corner(logoMark, 4)
            local iconHolder = fg_new("Frame", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 76),
                Size = UDim2.new(1, 0, 1, -76),
                Parent = sidebar,
            })
            fg_new("UIListLayout", {
                Padding = UDim.new(0, 10),
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = iconHolder,
            })
            fg_pad(iconHolder, 8, 0, 0, 0)

            local topbar = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.TopBar,
                Position = UDim2.new(0, 72, 0, 0),
                Size = UDim2.new(1, -72, 0, 52),
                BackgroundTransparency = 1,
                Parent = main,
            })
            fg_new("Frame", {
                Name = "TitleDivider",
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, 0),
                Size = UDim2.new(1, -16, 0, 1),
                BackgroundColor3 = Color3.fromRGB(45, 50, 65),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = topbar,
            })
            local tabZone = fg_new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(14, 0),
                Size = UDim2.new(1, -200, 1, 0),
                Parent = topbar,
            })
            local search = fg_new("Frame", {
                BackgroundColor3 = FG_Theme.CardAlt,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(170, 34),
                Parent = topbar,
            })
            fg_corner(search, 9)
            fg_stroke(search, FG_Theme.Stroke, 1)
            local sIcon = iconSearch(16, FG_Theme.SubText)
            sIcon.AnchorPoint = Vector2.new(0, 0.5)
            sIcon.Position = UDim2.new(0, 10, 0.5, 0)
            sIcon.Parent = search
            local searchBox = fg_new("TextBox", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 32, 0, 0),
                Size = UDim2.new(1, -42, 1, 0),
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = FG_Theme.Text,
                PlaceholderText = "Search features…",
                PlaceholderColor3 = FG_Theme.Faint,
                Text = "",
                ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = search,
            })
            search.MouseEnter:Connect(function() fg_tween(search, 0.14, { BackgroundColor3 = FG_Theme.CardAlt2 }) end)
            search.MouseLeave:Connect(function() fg_tween(search, 0.14, { BackgroundColor3 = FG_Theme.CardAlt }) end)

            local contentArea = fg_new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 72, 0, 52),
                Size = UDim2.new(1, -72, 1, -52),
                Parent = main,
            })
            fg_pad(contentArea, 14, 14, 14, 14)

            local window = setmetatable({
                gui = gui, main = main, pages = {}, uiScale = mainScale,
                iconHolder = iconHolder, tabZone = tabZone, contentArea = contentArea,
            }, Library)

            function window:_selectPage(page)
                for _, p in ipairs(self.pages) do
                    local on = p == page
                    p.tabBar.Visible = on
                    p.pageFrame.Visible = on
                    fg_tween(p.iconBtn, 0.18, { BackgroundColor3 = on and FG_Theme.Accent or FG_Theme.CardAlt, BackgroundTransparency = 0 })
                    p.iconGrad.Enabled = on
                    fg_tween(p.icon, 0.18, { ImageColor3 = on and rgb(255, 255, 255) or FG_Theme.SubText, ImageTransparency = 0 })
                    if p.label then fg_tween(p.label, 0.18, { TextColor3 = on and rgb(255, 255, 255) or FG_Theme.SubText }) end
                end
                self.activePage = page
                if searchBox then self:_applySearch(searchBox.Text) end
            end

            -- Search filter: hide non-matching rows + empty sections on the active tab.
            function window:_applySearch(q)
                q = tostring(q or ""):lower()
                local page = self.activePage
                local tab = page and page.active
                if not tab then return end
                for _, col in ipairs({ tab.left, tab.right }) do
                    for _, card in ipairs(col:GetChildren()) do
                        if card:IsA("Frame") then
                            local body
                            for _, ch in ipairs(card:GetChildren()) do
                                if ch:IsA("Frame") and ch:FindFirstChildOfClass("UIListLayout") then body = ch break end
                            end
                            if body then
                                local titleLbl = body:FindFirstChildOfClass("TextLabel")
                                local titleText = titleLbl and tostring(titleLbl.Text):lower() or ""
                                local sectionMatch = (q == "") or (titleText:find(q, 1, true) ~= nil)
                                local anyVisible = false
                                for _, ch in ipairs(body:GetChildren()) do
                                    if ch:IsA("Frame") then
                                        local m = sectionMatch
                                        if not m then
                                            for _, d in ipairs(ch:GetDescendants()) do
                                                if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.Text) == "string" and d.Text:lower():find(q, 1, true) then m = true break end
                                            end
                                        end
                                        ch.Visible = m
                                        if m then anyVisible = true end
                                    end
                                end
                                card.Visible = (q == "") or sectionMatch or anyVisible
                            end
                        end
                    end
                end
            end
            searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                window:_applySearch(searchBox.Text)
            end)

            function window:AddPage(po)
                po = po or {}
                local iconBtn = fg_new("TextButton", {
                    BackgroundColor3 = FG_Theme.CardAlt,
                    BackgroundTransparency = 0,          -- visible card (was invisible)
                    Size = UDim2.fromOffset(56, 54),     -- room for icon + label
                    Text = "",
                    AutoButtonColor = false,
                    Parent = iconHolder,
                })
                fg_corner(iconBtn, 12)
                fg_stroke(iconBtn, FG_Theme.Stroke, 1)
                local iconGrad = fg_gradient(iconBtn, FG_Theme.Accent, FG_Theme.Accent2, 45)
                iconGrad.Enabled = false
                local icon = fg_new("ImageLabel", {
                    BackgroundTransparency = 1,
                    Image = po.icon or "rbxassetid://11835491369",
                    ImageColor3 = FG_Theme.SubText,      -- tinted; turns white when selected
                    ImageTransparency = 0,
                    AnchorPoint = Vector2.new(0.5, 0),
                    Position = UDim2.new(0.5, 0, 0, 8),
                    Size = UDim2.fromOffset(22, 22),
                    Parent = iconBtn,
                })
                local label = fg_new("TextLabel", {
                    BackgroundTransparency = 1,
                    Text = po.name or ("Page " .. tostring(#self.pages + 1)),
                    Font = Enum.Font.GothamMedium,
                    TextSize = 10,
                    TextColor3 = FG_Theme.SubText,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    AnchorPoint = Vector2.new(0.5, 1),
                    Position = UDim2.new(0.5, 0, 1, -6),
                    Size = UDim2.new(1, -6, 0, 12),
                    Parent = iconBtn,
                })
                local tabBar = fg_new("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    Visible = false,
                    Parent = tabZone,
                })
                fg_new("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal,
                    Padding = UDim.new(0, 4),
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Parent = tabBar,
                })
                local pageFrame = fg_new("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    Visible = false,
                    Parent = contentArea,
                })
                local page = setmetatable({
                    iconBtn = iconBtn, iconGrad = iconGrad, icon = icon, label = label,
                    tabBar = tabBar, pageFrame = pageFrame, tabs = {},
                }, Page)
                table.insert(self.pages, page)
                iconBtn.MouseEnter:Connect(function()
                    if self.activePage ~= page then fg_tween(iconBtn, 0.14, { BackgroundColor3 = FG_Theme.CardAlt2 }) end
                end)
                iconBtn.MouseLeave:Connect(function()
                    if self.activePage ~= page then fg_tween(iconBtn, 0.14, { BackgroundColor3 = FG_Theme.CardAlt }) end
                end)
                iconBtn.MouseButton1Click:Connect(function() self:_selectPage(page) end)
                if #self.pages == 1 then self:_selectPage(page) end
                return page
            end

            -- Drag (smooth)
            local dragging, dragStart, startPos = false, nil, nil
            local targetPos = main.Position
            local function beginDrag(input)
                dragging = true
                dragStart = input.Position
                startPos = main.Position
                targetPos = startPos
                fg_tween(main, 0.18, { Size = UDim2.fromOffset(W - 6, H - 6) })
            end
            topbar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    beginDrag(input)
                end
            end)
            sidebar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    beginDrag(input)
                end
            end)
            FG_UIS.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local d = input.Position - dragStart
                    targetPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
            FG_UIS.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    if dragging then fg_tween(main, 0.22, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back) end
                    dragging = false
                end
            end)
            local conn
            conn = RunService.RenderStepped:Connect(function()
                if not main.Parent then conn:Disconnect() return end
                if not dragging and not gui.Enabled then return end
                local diff = targetPos.X.Offset - main.Position.X.Offset
                local diffy = targetPos.Y.Offset - main.Position.Y.Offset
                if math.abs(diff) < 0.5 and math.abs(diffy) < 0.5 and not dragging then
                    main.Position = targetPos; shadow.Position = targetPos; return
                end
                main.Position = main.Position:Lerp(targetPos, 0.2)
                shadow.Position = main.Position
            end)

            main.Size = UDim2.fromOffset(W * 0.92, H * 0.92)
            task.spawn(function()
                fg_tween(main, 0.5, { GroupTransparency = 0 })
                fg_tween(main, 0.55, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
                fg_tween(shadow, 0.5, { ImageTransparency = 0.55 })
                shadow.ImageTransparency = 1
            end)
            window._animateIn = function()
                for i, p in ipairs(window.pages) do
                    local btn = p.iconBtn
                    local fy = btn.Position
                    btn.Position = fy - UDim2.fromOffset(18, 0)
                    task.delay(0.05 * i, function()
                        fg_tween(btn, 0.4, { Position = fy }, Enum.EasingStyle.Back)
                    end)
                end
                if window.activePage then
                    for i, t in ipairs(window.activePage.tabs) do
                        local b = t.button
                        local fy = b.Position
                        b.Position = fy - UDim2.fromOffset(0, 12)
                        task.delay(0.04 * i + 0.1, function()
                            fg_tween(b, 0.4, { Position = fy }, Enum.EasingStyle.Back)
                        end)
                    end
                end
            end

            -- ── Resize handle (bottom-right corner, drags the whole window's UIScale) ──
            local resizeHandle = fg_new("Frame", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 1),
                Position = UDim2.new(1, -4, 1, -4),
                Size = UDim2.fromOffset(18, 18),
                ZIndex = 5,
                Parent = main,
            })
            fg_new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = Enum.Font.GothamBold,
                TextSize = 16,
                TextColor3 = FG_Theme.Faint,
                Text = "⤡",
                ZIndex = 5,
                Parent = resizeHandle,
            })
            do
                local RH_UIS = game:GetService("UserInputService")
                local resizing, startInput, startScale = false, nil, nil
                resizeHandle.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        resizing = true
                        startInput = i.Position
                        startScale = mainScale.Scale
                    end
                end)
                RH_UIS.InputChanged:Connect(function(i)
                    if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                        local d = i.Position - startInput
                        local newScale = math.clamp(startScale + (d.X + d.Y) / 2 / 300, 0.7, 1.4)
                        mainScale.Scale = newScale
                    end
                end)
                RH_UIS.InputEnded:Connect(function(i)
                    if resizing and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                        resizing = false
                        Config.MainUIScale = mainScale.Scale
                        if SaveConfig then pcall(SaveConfig) end
                        if window._onScaleChanged then window._onScaleChanged(mainScale.Scale) end
                    end
                end)
            end

            return window
        end

        -- ============================================================
        -- Build the new chopper_hub window
        -- ============================================================
        local Window = Library:CreateWindow({ Title = "chopper_hub" })

        local function setKey(key, val)
            Config[key] = val
            if SaveConfig then pcall(SaveConfig) end
            if key == "LineToBase" then
                if val then if _G.createPlotBeam then pcall(_G.createPlotBeam) end
                else if _G.resetPlotBeam then pcall(_G.resetPlotBeam) end end
            elseif key == "SubspaceMineESP" and _G.MeerkoSubspaceSet then
                _G.MeerkoSubspaceSet(val)
            elseif key == "InvisOnSteal" then
                if val then if _G.VanishInvisAutoStart then pcall(_G.VanishInvisAutoStart) end
                else if _G.VanishInvisAutoStop then pcall(_G.VanishInvisAutoStop) end end
            elseif key == "AutoBuyCarpet" and _G.MeerkoAutoBuyCarpet then
                pcall(_G.MeerkoAutoBuyCarpet, val)
            elseif key == "BrainrotESP" and _G.MeerkoBrainrotESPSet then
                _G.MeerkoBrainrotESPSet(val)
            elseif key == "InfiniteJump" and _G.MeerkoSetInfiniteJump then
                _G.MeerkoSetInfiniteJump(val)
            elseif key == "AntiBeeDisco" and _G.MeerkoSetAntiBeeDisco then
                _G.MeerkoSetAntiBeeDisco(val)
            elseif key == "Animations" then
                _G.MeerkoAnimations = val
                local ch = MK_LP.Character
                if ch then
                    if val then if _G.MeerkoRestoreAnims then pcall(_G.MeerkoRestoreAnims, ch) end
                    else if _G.MeerkoKillAnims then pcall(_G.MeerkoKillAnims, ch) end end
                end
            elseif key == "ShowAdminPanel" and _G.MeerkoSetAdminPanel then
                _G.MeerkoSetAdminPanel(val)
            elseif key == "LineToBrainrot" and _G.MeerkoBrainrotBeamSet then
                _G.MeerkoBrainrotBeamSet(val)
            elseif key == "FPSBoost" and _G.MeerkoSetFPSBoost then
                _G.MeerkoSetFPSBoost(val)
            elseif key == "UnlockButtons" and _G.MeerkoSetUnlockButtons then
                _G.MeerkoSetUnlockButtons(val)
            elseif key == "XrayBases" and _G.MeerkoSetXray then
                _G.MeerkoSetXray(val)
            elseif key == "AutoKickOnSteal" then
                _G.MeerkoAutoKickOnSteal = val
            elseif key == "AntiBodySwap" then
                _G.AntiBodySwapEnabled = val
            end
        end

        local function toggleRow(section, key, label)
            section:AddToggle({
                Text = label,
                Default = Config[key] == true,
                Callback = function(v) setKey(key, v) end,
            })
        end

        -- ---------- Page 1: Main ----------
        local pageMain = Window:AddPage({ name = "Main" })
        local tabMain = pageMain:AddTab({ Name = "main" })

        -- LEFT column

        -- Auto Teleport module
        local sTp = tabMain:AddSection("left", "AUTO TELEPORT")
        sTp:AddToggle({
            Text = "Enable",
            Default = Config.AutoTeleport == true,
            Callback = function(v)
                Config.AutoTeleport = v
                if SaveConfig then pcall(SaveConfig) end
                if v and _G.MeerkoRunAutoTP then pcall(_G.MeerkoRunAutoTP) end
            end,
        })
        sTp:AddToggle({
            Text = "TP Back On Hit (outside base)",
            Default = Config.TPBackOnHit == true,
            Callback = function(v)
                Config.TPBackOnHit = v
                if SaveConfig then pcall(SaveConfig) end
            end,
        })
        sTp:AddSliderF({
            Text = "Delay Before TP", Min = 0, Max = 0.9, Step = 0.01,
            Default = tonumber(_G._stp_tpDelay) or 0,
            Format = function(v) return string.format("%dms", math.floor(v * 1000 + 0.5)) end,
            Callback = function(v) _G._stp_tpDelay = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
        })
        sTp:AddSliderF({
            Text = "Landing Delay", Min = 0.15, Max = 0.75, Step = 0.01,
            Default = tonumber(_G.LandingDelay) or 0.4,
            Format = function(v) return string.format("%.2fs", v) end,
            Callback = function(v) _G.LandingDelay = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
        })
        sTp:AddSliderF({
            Text = "TP Velocity", Min = 200, Max = 500, Step = 10,
            Default = tonumber(_G.TPVelocity) or 400,
            Format = function(v) return string.format("%d", v) end,
            Callback = function(v) _G.TPVelocity = v; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end,
        })
        sTp:AddButton({
            Text = "Edit Priority",
            Callback = function() if _G._stp_openPriority then pcall(_G._stp_openPriority) end end,
        })
        sTp:AddDropdown({
            Text = "Mount (TP + Carpet Speed)",
            Options = { "Auto", "Flying Carpet", "Cupid's Wings", "Santa's Sleigh" },
            Default = Config.CarpetTool or "Auto",
            Callback = function(opt)
                Config.CarpetTool = opt
                _G.MeerkoCarpetTool = opt
                if SaveConfig then pcall(SaveConfig) end
            end,
        })

        -- RIGHT column
        -- Auto Steal module
        local sStealMode = tabMain:AddSection("right", "AUTO STEAL")
        local STEAL_MODES = { "off", "nearest", "highest", "priority" }
        local function currentStealLabel()
            return _G.MeerkoStealMode or "off"
        end
        sStealMode:AddDropdown({
            Text = "Mode",
            Options = STEAL_MODES,
            Default = currentStealLabel(),
            Callback = function(opt)
                if opt == "off" then
                    if _G.MeerkoSetStealMode then pcall(_G.MeerkoSetStealMode, nil) end
                else
                    if _G.MeerkoSetStealMode then pcall(_G.MeerkoSetStealMode, opt) end
                end
            end,
        })

        -- ---------- Page 2: Visuals ----------
        local pageVis = Window:AddPage({ name = "Visuals" })
        local tabVis  = pageVis:AddTab({ Name = "visuals" })
        local sEsp = tabVis:AddSection("left", "ESP")
        toggleRow(sEsp, "BrainrotESP",     "Brainrot ESP")
        toggleRow(sEsp, "SubspaceMineESP", "Subspace Mine ESP")
        local sBeams = tabVis:AddSection("right", "BEAMS")
        toggleRow(sBeams, "LineToBase",     "Line to Base")
        toggleRow(sBeams, "LineToBrainrot", "Line to Best Brainrot")
        toggleRow(sBeams, "BaseTimer",      "Base Timer")

        -- ---------- Page 3: Misc (includes the old Server "AUTO" items) ----------
        local pageMisc = Window:AddPage({ name = "Misc" })
        local tabMisc  = pageMisc:AddTab({ Name = "misc" })
        local sMisc = tabMisc:AddSection("left", "MISC")
        toggleRow(sMisc, "InfiniteJump",   "Infinite Jump")
        toggleRow(sMisc, "ShowAdminPanel", "Admin Panel")
        toggleRow(sMisc, "Animations",     "Animations")
        toggleRow(sMisc, "FPSBoost",       "FPS Boost")
        toggleRow(sMisc, "UnlockButtons",  "Base Unlock Buttons")
        toggleRow(sMisc, "XrayBases",      "X-Ray Bases")
        local sProt = tabMisc:AddSection("left", "PROTECTION")
        toggleRow(sProt, "AntiRagdoll",        "Anti Ragdoll")
        toggleRow(sProt, "AntiBeeDisco",       "Anti Bee & Disco")
        toggleRow(sProt, "AntiBodySwap",       "Anti Body Swap")
        toggleRow(sProt, "AutoDestroyTurrets", "Auto-Destroy Turrets")
        local sAuto = tabMisc:AddSection("right", "AUTO")
        toggleRow(sAuto, "AutoBuyCarpet",   "Auto Buy Carpet")
        toggleRow(sAuto, "AutoTPOnJoin",    "TP Immédiat au Join")
        toggleRow(sAuto, "AutoKickOnSteal", "Auto-Kick on Steal")
        toggleRow(sAuto, "AutoTPToPSOnSteal", "Auto-Join PS on Steal")
        do
            local stretchToggle = sAuto:AddToggle({ Text = "Game Stretcher", Default = Config.GameStretcher or false, Callback = function(v)
                Config.GameStretcher = v
                if SaveConfig then pcall(SaveConfig) end
                if v then _G.MeerkoStretchEnable() else _G.MeerkoStretchDisable() end
            end })
        end
        sAuto:AddInput({ Text = Config.PSLinkCode or "", Placeholder = "PS Link Code", Callback = function(v) Config.PSLinkCode = v; if SaveConfig then pcall(SaveConfig) end end })
        sAuto:AddInput({ Text = Config.PSPlaceId or "", Placeholder = "PS Place ID (optionnel)", Callback = function(v) Config.PSPlaceId = v; if SaveConfig then pcall(SaveConfig) end end })
        local sDisplay = tabMisc:AddSection("right", "DISPLAY")
        local uiScaleSlider = sDisplay:AddSliderF({
            Text = "UI Scale", Min = 0.7, Max = 1.4, Step = 0.01,
            Default = tonumber(Config.MainUIScale) or 1,
            Format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
            Callback = function(v)
                Config.MainUIScale = v
                if Window.uiScale then Window.uiScale.Scale = v end
                if SaveConfig then pcall(SaveConfig) end
            end,
        })
        Window._onScaleChanged = function(v)
            if uiScaleSlider then uiScaleSlider:Set(v) end
        end

        -- ---------- Page 4: Keybinds ----------
        local pageKeys = Window:AddPage({ name = "Keybinds" })
        local tabKeys  = pageKeys:AddTab({ Name = "keybinds" })
        local sBinds = tabKeys:AddSection("left", "KEYBINDS")
        sBinds:AddKeybind({ Text = "Manual TP",    Get = function() return _G._stp_tpKeyName or "T" end, Set = function(k) _G._stp_tpKeyName = k; if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end end })
        sBinds:AddKeybind({ Text = "Auto Clone",   Get = function() return Config.CloneKey end,       Set = function(k) Config.CloneKey = k;       if SaveConfig then pcall(SaveConfig) end end })
        sBinds:AddKeybind({ Text = "Carpet Speed", Get = function() return Config.CarpetSpeedKey end, Set = function(k) Config.CarpetSpeedKey = k; if SaveConfig then pcall(SaveConfig) end end })
        sBinds:AddKeybind({ Text = "Drop Brainrot", Get = function() return Config.BrainrotDropKey end, Set = function(k) Config.BrainrotDropKey = k; if SaveConfig then pcall(SaveConfig) end end })
        sBinds:AddKeybind({ Text = "Auto Buy",      Get = function() return Config.AutoBuyKey end,      Set = function(k) Config.AutoBuyKey = k;      if SaveConfig then pcall(SaveConfig) end end })
        local sActions = tabKeys:AddSection("right", "ACTIONS")
        sActions:AddKeybind({ Text = "Reset",       Get = function() return Config.ResetKey end,  Set = function(k) Config.ResetKey = k;  if SaveConfig then pcall(SaveConfig) end end })
        sActions:AddKeybind({ Text = "Rejoin",      Get = function() return Config.RejoinKey end, Set = function(k) Config.RejoinKey = k; if SaveConfig then pcall(SaveConfig) end end })
        sActions:AddKeybind({ Text = "Leave Game",  Get = function() return Config.LeaveKey end,  Set = function(k) Config.LeaveKey = k;  if SaveConfig then pcall(SaveConfig) end end })
        sActions:AddKeybind({ Text = "Toggle Menu", Get = function() return Config.MenuKey end,   Set = function(k) Config.MenuKey = k;   if SaveConfig then pcall(SaveConfig) end end })
        local sHow = tabKeys:AddSection("right", "HOW TO USE")
        sHow:AddLabel({ Text = "Click a key box, then press a key." })
        sHow:AddLabel({ Text = "Press ✕ to clear a bind." })

        Window._animateIn()
        -- Start hidden on load: the menu only opens when the Menu keybind is pressed.
        Window.gui.Enabled = false

        -- ===== Shared helpers for floating mini panels ================
        -- Drag-to-move (click without moving triggers onToggle) + saved position.
        local function mkPanelDraggable(header, panel, xKey, yKey, onToggle)
            local pdUIS = game:GetService("UserInputService")
            local dragging, dragStart, startPos, moved = false, nil, nil, false
            header.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    dragging = true; moved = false; dragStart = i.Position; startPos = panel.Position
                end
            end)
            pdUIS.InputChanged:Connect(function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    local d = i.Position - dragStart
                    if math.abs(d.X) > 3 or math.abs(d.Y) > 3 then moved = true end
                    panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
            pdUIS.InputEnded:Connect(function(i)
                if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and dragging then
                    dragging = false
                    if not moved then
                        if onToggle then onToggle() end
                    else
                        Config[xKey] = panel.Position.X.Offset
                        Config[yKey] = panel.Position.Y.Offset
                        if SaveConfig then pcall(SaveConfig) end
                    end
                end
            end)
        end

        -- Bottom-right resize handle that scales the panel via UIScale + saves the scale.
        local function mkPanelResizeHandle(panel, scaleKey, minS, maxS)
            minS, maxS = minS or 0.7, maxS or 1.4
            local scaleInst = Instance.new("UIScale")
            scaleInst.Scale = math.clamp(tonumber(Config[scaleKey]) or 1, minS, maxS)
            scaleInst.Parent = panel

            local handle = Instance.new("TextButton", panel)
            handle.Name = "ResizeHandle"
            handle.AnchorPoint = Vector2.new(1, 1)
            handle.Position = UDim2.new(1, -2, 1, -2)
            handle.Size = UDim2.fromOffset(14, 14)
            handle.BackgroundTransparency = 1
            handle.Text = "⤡"
            handle.TextColor3 = Color3.fromRGB(160, 165, 184)
            handle.TextSize = 12
            handle.Font = Enum.Font.GothamBold
            handle.AutoButtonColor = false
            handle.ZIndex = 10

            local rhUIS = game:GetService("UserInputService")
            local resizing, startInput, startScale = false, nil, nil
            handle.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    resizing = true; startInput = i.Position; startScale = scaleInst.Scale
                end
            end)
            rhUIS.InputChanged:Connect(function(i)
                if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    local d = i.Position - startInput
                    scaleInst.Scale = math.clamp(startScale + (d.X + d.Y) / 2 / 200, minS, maxS)
                end
            end)
            rhUIS.InputEnded:Connect(function(i)
                if resizing and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                    resizing = false
                    Config[scaleKey] = scaleInst.Scale
                    if SaveConfig then pcall(SaveConfig) end
                end
            end)
            return scaleInst
        end

        -- ===== Steal Mode mini panel (Priority / Nearest / Highest) =====
        do
            local _rgb = Color3.fromRGB
            local C_BG2   = _rgb(22, 22, 27)
            local C_CARD2 = _rgb(43, 44, 55)
            local C_STRK2 = _rgb(54, 56, 70)
            local C_TXT2  = _rgb(237, 239, 246)
            local C_SUB2  = _rgb(160, 165, 184)
            local C_ACC   = _rgb(142, 148, 255)
            local C_WHITE = _rgb(255, 255, 255)

            local smGui = Instance.new("ScreenGui")
            smGui.Name = "MeerkoStealModePanel"
            smGui.ResetOnSpawn = false
            smGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            pcall(function() smGui.Parent = (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui") end)
            if not smGui.Parent then smGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end

            local MODES = {
                { key = "priority", label = "Priority" },
                { key = "nearest",  label = "Nearest" },
                { key = "highest",  label = "Highest" },
            }
            local ROW_H, HEAD_H = 26, 30
            local EXP_H = HEAD_H + (#MODES * (ROW_H + 3)) + 8

            local panel = Instance.new("Frame")
            panel.AnchorPoint = Vector2.new(1, 0)
            panel.Position = UDim2.new(1, tonumber(Config.StealModePanelX) or -16, 0, tonumber(Config.StealModePanelY) or 96)
            panel.Size = UDim2.fromOffset(190, EXP_H)
            panel.BackgroundColor3 = C_BG2
            panel.BackgroundTransparency = 0.05
            panel.BorderSizePixel = 0
            panel.Active = true
            panel.Parent = smGui
            Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
            local pstr = Instance.new("UIStroke", panel)
            pstr.Color = C_STRK2; pstr.Thickness = 1; pstr.Transparency = 0.15

            local header = Instance.new("TextButton", panel)
            header.Size = UDim2.new(1, 0, 0, HEAD_H)
            header.BackgroundTransparency = 1
            header.Text = ""
            header.AutoButtonColor = false
            local htitle = Instance.new("TextLabel", header)
            htitle.BackgroundTransparency = 1
            htitle.Position = UDim2.new(0, 12, 0, 0)
            htitle.Size = UDim2.new(1, -40, 1, 0)
            htitle.Font = Enum.Font.GothamBold
            htitle.TextSize = 12
            htitle.TextColor3 = C_TXT2
            htitle.TextXAlignment = Enum.TextXAlignment.Left
            htitle.Text = "Steal Mode"
            local chev = Instance.new("TextLabel", header)
            chev.BackgroundTransparency = 1
            chev.AnchorPoint = Vector2.new(1, 0.5)
            chev.Position = UDim2.new(1, -12, 0.5, 0)
            chev.Size = UDim2.fromOffset(14, 14)
            chev.Font = Enum.Font.GothamBold
            chev.TextSize = 12
            chev.TextColor3 = C_SUB2
            chev.Text = "▾"

            local list = Instance.new("Frame", panel)
            list.Position = UDim2.new(0, 0, 0, HEAD_H)
            list.Size = UDim2.new(1, 0, 1, -HEAD_H)
            list.BackgroundTransparency = 1
            local llay = Instance.new("UIListLayout", list)
            llay.Padding = UDim.new(0, 3); llay.SortOrder = Enum.SortOrder.LayoutOrder
            local lpad = Instance.new("UIPadding", list)
            lpad.PaddingLeft = UDim.new(0, 10); lpad.PaddingRight = UDim.new(0, 10); lpad.PaddingBottom = UDim.new(0, 8)

            local rowBtns = {}
            local function repaint()
                local active = _G.MeerkoStealMode
                for _, r in ipairs(rowBtns) do
                    local on = (active == r.key)
                    r.btn.BackgroundColor3 = on and C_ACC or C_CARD2
                    r.lbl.TextColor3 = on and C_WHITE or C_SUB2
                    r.dot.BackgroundColor3 = on and C_WHITE or C_STRK2
                end
            end

            for i, m in ipairs(MODES) do
                local btn = Instance.new("TextButton", list)
                btn.LayoutOrder = i
                btn.Size = UDim2.new(1, 0, 0, ROW_H)
                btn.BackgroundColor3 = C_CARD2
                btn.AutoButtonColor = false
                btn.Text = ""
                btn.BorderSizePixel = 0
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
                local lbl = Instance.new("TextLabel", btn)
                lbl.BackgroundTransparency = 1
                lbl.Position = UDim2.new(0, 10, 0, 0)
                lbl.Size = UDim2.new(1, -28, 1, 0)
                lbl.Font = Enum.Font.GothamMedium
                lbl.TextSize = 12
                lbl.TextColor3 = C_SUB2
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Text = m.label
                local dot = Instance.new("Frame", btn)
                dot.AnchorPoint = Vector2.new(1, 0.5)
                dot.Position = UDim2.new(1, -9, 0.5, 0)
                dot.Size = UDim2.fromOffset(7, 7)
                dot.BackgroundColor3 = C_STRK2
                dot.BorderSizePixel = 0
                Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
                btn.MouseButton1Click:Connect(function()
                    if _G.MeerkoStealMode == m.key then
                        if _G.MeerkoSetStealMode then pcall(_G.MeerkoSetStealMode, nil) end
                    else
                        if _G.MeerkoSetStealMode then pcall(_G.MeerkoSetStealMode, m.key) end
                    end
                    repaint()
                end)
                rowBtns[#rowBtns + 1] = { key = m.key, btn = btn, lbl = lbl, dot = dot }
            end
            repaint()

            local collapsed = false
            local function toggleCollapse()
                collapsed = not collapsed
                list.Visible = not collapsed
                chev.Text = collapsed and "▸" or "▾"
                panel.Size = UDim2.fromOffset(190, collapsed and HEAD_H or EXP_H)
            end

            mkPanelDraggable(header, panel, "StealModePanelX", "StealModePanelY", toggleCollapse)
            mkPanelResizeHandle(panel, "StealModePanelScale")

            task.spawn(function() while smGui.Parent do repaint(); task.wait(1) end end)
        end

        -- ===== Admin Toggles mini panel (Click to AP / Spam Base Owner) =====
        do
            local _rgb = Color3.fromRGB
            local C_BG2   = _rgb(22, 22, 27)
            local C_CARD2 = _rgb(43, 44, 55)
            local C_STRK2 = _rgb(54, 56, 70)
            local C_TXT2  = _rgb(237, 239, 246)
            local C_SUB2  = _rgb(160, 165, 184)
            local C_GREEN = _rgb(100, 226, 142)
            local C_WHITE = _rgb(255, 255, 255)
            local C_ACC2  = _rgb(122, 128, 250)

            local atGui = Instance.new("ScreenGui")
            atGui.Name = "MeerkoAdminTogglePanel"
            atGui.ResetOnSpawn = false
            atGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            pcall(function() atGui.Parent = (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui") end)
            if not atGui.Parent then atGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end

            local ROW_H, HEAD_H = 24, 30
            local ROWS_N = 2
            local EXP_H = HEAD_H + (ROWS_N * (ROW_H + 2)) + 8

            local panel = Instance.new("Frame")
            panel.AnchorPoint = Vector2.new(1, 0)
            panel.Position = UDim2.new(1, tonumber(Config.AdminTogglePanelX) or -16, 0, tonumber(Config.AdminTogglePanelY) or 272)
            panel.Size = UDim2.fromOffset(200, EXP_H)
            panel.BackgroundColor3 = C_BG2
            panel.BackgroundTransparency = 0.05
            panel.BorderSizePixel = 0
            panel.Active = true
            panel.Parent = atGui
            Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
            local pstr = Instance.new("UIStroke", panel)
            pstr.Color = C_STRK2; pstr.Thickness = 1; pstr.Transparency = 0.15

            local header = Instance.new("TextButton", panel)
            header.Size = UDim2.new(1, 0, 0, HEAD_H)
            header.BackgroundTransparency = 1
            header.Text = ""
            header.AutoButtonColor = false
            local htitle = Instance.new("TextLabel", header)
            htitle.BackgroundTransparency = 1
            htitle.Position = UDim2.new(0, 12, 0, 0)
            htitle.Size = UDim2.new(1, -40, 1, 0)
            htitle.Font = Enum.Font.GothamBold
            htitle.TextSize = 12
            htitle.TextColor3 = C_TXT2
            htitle.TextXAlignment = Enum.TextXAlignment.Left
            htitle.Text = "Admin Toggles"
            local chev = Instance.new("TextLabel", header)
            chev.BackgroundTransparency = 1
            chev.AnchorPoint = Vector2.new(1, 0.5)
            chev.Position = UDim2.new(1, -12, 0.5, 0)
            chev.Size = UDim2.fromOffset(14, 14)
            chev.Font = Enum.Font.GothamBold
            chev.TextSize = 12
            chev.TextColor3 = C_SUB2
            chev.Text = "▾"

            local list = Instance.new("Frame", panel)
            list.Position = UDim2.new(0, 0, 0, HEAD_H)
            list.Size = UDim2.new(1, 0, 1, -HEAD_H)
            list.BackgroundTransparency = 1
            local llay = Instance.new("UIListLayout", list)
            llay.Padding = UDim.new(0, 2); llay.SortOrder = Enum.SortOrder.LayoutOrder
            local lpad = Instance.new("UIPadding", list)
            lpad.PaddingLeft = UDim.new(0, 10); lpad.PaddingRight = UDim.new(0, 10); lpad.PaddingBottom = UDim.new(0, 8)

            -- a single switch row; onClick(paint) is called on tap, refreshFn(paint)
            -- keeps the visual in sync with external state.
            local function makeRow(name, onClick)
                local row = Instance.new("Frame", list)
                row.Size = UDim2.new(1, 0, 0, ROW_H)
                row.BackgroundTransparency = 1
                local nm = Instance.new("TextLabel", row)
                nm.BackgroundTransparency = 1
                nm.Size = UDim2.new(1, -46, 1, 0)
                nm.Font = Enum.Font.GothamMedium
                nm.TextSize = 11
                nm.TextColor3 = C_SUB2
                nm.TextXAlignment = Enum.TextXAlignment.Left
                nm.Text = name
                local btn = Instance.new("TextButton", row)
                btn.AnchorPoint = Vector2.new(1, 0.5)
                btn.Position = UDim2.new(1, 0, 0.5, 0)
                btn.Size = UDim2.fromOffset(34, 16)
                btn.BackgroundColor3 = C_CARD2
                btn.AutoButtonColor = false
                btn.Text = ""
                btn.BorderSizePixel = 0
                Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
                local knob = Instance.new("Frame", btn)
                knob.Size = UDim2.fromOffset(12, 12)
                knob.AnchorPoint = Vector2.new(0, 0.5)
                knob.Position = UDim2.new(0, 2, 0.5, 0)
                knob.BackgroundColor3 = C_WHITE
                knob.BorderSizePixel = 0
                Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
                local function paint(on)
                    btn.BackgroundColor3 = on and C_GREEN or C_CARD2
                    knob.AnchorPoint = on and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
                    knob.Position = on and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
                end
                btn.MouseButton1Click:Connect(function() onClick(paint) end)
                return paint
            end

            -- Click to AP: real on/off toggle (kept in sync with Config.ClickToAP)
            local clickPaint = makeRow("Click to AP", function(paint)
                Config.ClickToAP = not (Config.ClickToAP == true)
                if SaveConfig then pcall(SaveConfig) end
                paint(Config.ClickToAP == true)
            end)
            clickPaint(Config.ClickToAP == true)

            -- Spam Base Owner: a button (tap to fire the one-shot burst)
            do
                local row = Instance.new("Frame", list)
                row.Size = UDim2.new(1, 0, 0, ROW_H)
                row.BackgroundTransparency = 1
                local nm = Instance.new("TextLabel", row)
                nm.BackgroundTransparency = 1
                nm.Size = UDim2.new(1, -64, 1, 0)
                nm.Font = Enum.Font.GothamMedium
                nm.TextSize = 11
                nm.TextColor3 = C_SUB2
                nm.TextXAlignment = Enum.TextXAlignment.Left
                nm.Text = "Spam Base Owner"
                local btn = Instance.new("TextButton", row)
                btn.AnchorPoint = Vector2.new(1, 0.5)
                btn.Position = UDim2.new(1, 0, 0.5, 0)
                btn.Size = UDim2.fromOffset(52, 18)
                btn.BackgroundColor3 = C_ACC2
                btn.AutoButtonColor = false
                btn.Text = "Fire"
                btn.Font = Enum.Font.GothamBold
                btn.TextSize = 11
                btn.TextColor3 = C_WHITE
                btn.BorderSizePixel = 0
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
                btn.MouseButton1Click:Connect(function()
                    btn.Text = "..."
                    if _G.MeerkoSpamBaseOwnerOnce then pcall(_G.MeerkoSpamBaseOwnerOnce) end
                    task.delay(0.45, function() if btn.Parent then btn.Text = "Fire" end end)
                end)
            end

            local collapsed = false
            local function toggleCollapse()
                collapsed = not collapsed
                list.Visible = not collapsed
                chev.Text = collapsed and "▸" or "▾"
                panel.Size = UDim2.fromOffset(200, collapsed and HEAD_H or EXP_H)
            end

            -- drag by the header; a quick click with no movement collapses/expands
            mkPanelDraggable(header, panel, "AdminTogglePanelX", "AdminTogglePanelY", toggleCollapse)
            mkPanelResizeHandle(panel, "AdminTogglePanelScale")

            -- keep Click to AP in sync if toggled from the admin panel
            task.spawn(function()
                while atGui.Parent do clickPaint(Config.ClickToAP == true); task.wait(1) end
            end)
        end

        -- ===== Invis Steal mini panel (Enable + Rotation / Depth / Walk Speed) =====
        do
            local _rgb = Color3.fromRGB
            local C_BG2   = _rgb(22, 22, 27)
            local C_CARD2 = _rgb(43, 44, 55)
            local C_STRK2 = _rgb(54, 56, 70)
            local C_TXT2  = _rgb(237, 239, 246)
            local C_SUB2  = _rgb(160, 165, 184)
            local C_ACC   = _rgb(142, 148, 255)
            local C_GREEN = _rgb(100, 226, 142)
            local C_WHITE = _rgb(255, 255, 255)

            local isGui = Instance.new("ScreenGui")
            isGui.Name = "MeerkoInvisStealPanel"
            isGui.ResetOnSpawn = false
            isGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            pcall(function() isGui.Parent = (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui") end)
            if not isGui.Parent then isGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end

            local ROW_H, HEAD_H, SLIDER_H = 24, 30, 40
            local EXP_H = HEAD_H + ROW_H + 4 + (3 * SLIDER_H) + 8

            local panel = Instance.new("Frame")
            panel.AnchorPoint = Vector2.new(1, 0)
            panel.Position = UDim2.new(1, tonumber(Config.InvisStealPanelX) or -16, 0, tonumber(Config.InvisStealPanelY) or 390)
            panel.Size = UDim2.fromOffset(200, EXP_H)
            panel.BackgroundColor3 = C_BG2
            panel.BackgroundTransparency = 0.05
            panel.BorderSizePixel = 0
            panel.Active = true
            panel.Parent = isGui
            Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
            local pstr = Instance.new("UIStroke", panel)
            pstr.Color = C_STRK2; pstr.Thickness = 1; pstr.Transparency = 0.15

            local header = Instance.new("TextButton", panel)
            header.Size = UDim2.new(1, 0, 0, HEAD_H)
            header.BackgroundTransparency = 1
            header.Text = ""
            header.AutoButtonColor = false
            local htitle = Instance.new("TextLabel", header)
            htitle.BackgroundTransparency = 1
            htitle.Position = UDim2.new(0, 12, 0, 0)
            htitle.Size = UDim2.new(1, -40, 1, 0)
            htitle.Font = Enum.Font.GothamBold
            htitle.TextSize = 12
            htitle.TextColor3 = C_TXT2
            htitle.TextXAlignment = Enum.TextXAlignment.Left
            htitle.Text = "Invis Steal"
            local chev = Instance.new("TextLabel", header)
            chev.BackgroundTransparency = 1
            chev.AnchorPoint = Vector2.new(1, 0.5)
            chev.Position = UDim2.new(1, -12, 0.5, 0)
            chev.Size = UDim2.fromOffset(14, 14)
            chev.Font = Enum.Font.GothamBold
            chev.TextSize = 12
            chev.TextColor3 = C_SUB2
            chev.Text = "▾"

            local list = Instance.new("Frame", panel)
            list.Position = UDim2.new(0, 0, 0, HEAD_H)
            list.Size = UDim2.new(1, 0, 1, -HEAD_H)
            list.BackgroundTransparency = 1
            local llay = Instance.new("UIListLayout", list)
            llay.Padding = UDim.new(0, 3); llay.SortOrder = Enum.SortOrder.LayoutOrder
            local lpad = Instance.new("UIPadding", list)
            lpad.PaddingLeft = UDim.new(0, 10); lpad.PaddingRight = UDim.new(0, 10); lpad.PaddingBottom = UDim.new(0, 8)

            local function makeToggleRow(name, initOn, onClick)
                local row = Instance.new("Frame", list)
                row.Size = UDim2.new(1, 0, 0, ROW_H)
                row.BackgroundTransparency = 1
                local nm = Instance.new("TextLabel", row)
                nm.BackgroundTransparency = 1
                nm.Size = UDim2.new(1, -46, 1, 0)
                nm.Font = Enum.Font.GothamMedium
                nm.TextSize = 11
                nm.TextColor3 = C_SUB2
                nm.TextXAlignment = Enum.TextXAlignment.Left
                nm.Text = name
                local btn = Instance.new("TextButton", row)
                btn.AnchorPoint = Vector2.new(1, 0.5)
                btn.Position = UDim2.new(1, 0, 0.5, 0)
                btn.Size = UDim2.fromOffset(34, 16)
                btn.BackgroundColor3 = initOn and C_GREEN or C_CARD2
                btn.AutoButtonColor = false
                btn.Text = ""
                btn.BorderSizePixel = 0
                Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
                local knob = Instance.new("Frame", btn)
                knob.Size = UDim2.fromOffset(12, 12)
                knob.AnchorPoint = initOn and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
                knob.Position = initOn and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
                knob.BackgroundColor3 = C_WHITE
                knob.BorderSizePixel = 0
                Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
                local on = initOn
                local function paint()
                    btn.BackgroundColor3 = on and C_GREEN or C_CARD2
                    knob.AnchorPoint = on and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
                    knob.Position = on and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
                end
                btn.MouseButton1Click:Connect(function()
                    on = not on
                    paint()
                    onClick(on)
                end)
            end

            makeToggleRow("Enable", Config.InvisOnSteal == true, function(v)
                Config.InvisOnSteal = v
                if SaveConfig then pcall(SaveConfig) end
                if v then if _G.VanishInvisAutoStart then pcall(_G.VanishInvisAutoStart) end
                else if _G.VanishInvisAutoStop then pcall(_G.VanishInvisAutoStop) end end
            end)

            local isSliderUIS = game:GetService("UserInputService")
            local function makeSliderRow(labelText, minV, maxV, step, initVal, fmt, onChange)
                local row = Instance.new("Frame", list)
                row.Size = UDim2.new(1, 0, 0, SLIDER_H)
                row.BackgroundTransparency = 1
                local nm = Instance.new("TextLabel", row)
                nm.BackgroundTransparency = 1
                nm.Size = UDim2.new(0.6, 0, 0, 14)
                nm.Font = Enum.Font.GothamMedium
                nm.TextSize = 11
                nm.TextColor3 = C_SUB2
                nm.TextXAlignment = Enum.TextXAlignment.Left
                nm.Text = labelText
                local valLbl = Instance.new("TextLabel", row)
                valLbl.BackgroundTransparency = 1
                valLbl.Size = UDim2.new(1, 0, 0, 14)
                valLbl.Font = Enum.Font.GothamSemibold
                valLbl.TextSize = 11
                valLbl.TextColor3 = C_TXT2
                valLbl.TextXAlignment = Enum.TextXAlignment.Right
                valLbl.Text = fmt(initVal)
                local track = Instance.new("Frame", row)
                track.Position = UDim2.new(0, 0, 0, 22)
                track.Size = UDim2.new(1, 0, 0, 5)
                track.BackgroundColor3 = C_STRK2
                track.BorderSizePixel = 0
                Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
                local fill = Instance.new("Frame", track)
                fill.BackgroundColor3 = C_ACC
                fill.BorderSizePixel = 0
                fill.Size = UDim2.new((initVal - minV) / (maxV - minV), 0, 1, 0)
                Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
                local knob = Instance.new("Frame", track)
                knob.AnchorPoint = Vector2.new(0.5, 0.5)
                knob.Size = UDim2.fromOffset(11, 11)
                knob.Position = UDim2.new((initVal - minV) / (maxV - minV), 0, 0.5, 0)
                knob.BackgroundColor3 = C_WHITE
                knob.BorderSizePixel = 0
                Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
                local dragBtn = Instance.new("TextButton", track)
                dragBtn.BackgroundTransparency = 1
                dragBtn.Text = ""
                dragBtn.Position = UDim2.new(0, 0, 0, -8)
                dragBtn.Size = UDim2.new(1, 0, 0, 20)
                local sliding = false
                local function set(v)
                    v = math.clamp(math.floor((v - minV) / step + 0.5) * step + minV, minV, maxV)
                    local rel = (maxV == minV) and 0 or (v - minV) / (maxV - minV)
                    fill.Size = UDim2.new(rel, 0, 1, 0)
                    knob.Position = UDim2.new(rel, 0, 0.5, 0)
                    valLbl.Text = fmt(v)
                    if onChange then onChange(v) end
                end
                local function update(input)
                    local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                    set(minV + (maxV - minV) * rel)
                end
                dragBtn.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        sliding = true
                        update(i)
                    end
                end)
                isSliderUIS.InputChanged:Connect(function(i)
                    if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                        update(i)
                    end
                end)
                isSliderUIS.InputEnded:Connect(function(i)
                    if sliding and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                        sliding = false
                    end
                end)
            end

            makeSliderRow("Rotation", 0, 360, 1, Config.InvisRotation or 180,
                function(v) return tostring(math.floor(v)) .. "°" end,
                function(v)
                    Config.InvisRotation = v
                    _G.VanishInvisAngle = v
                    if SaveConfig then pcall(SaveConfig) end
                end)
            makeSliderRow("Depth", 0.5, 10, 0.1, Config.InvisDepth or 5,
                function(v) return string.format("%.1f", v) end,
                function(v)
                    Config.InvisDepth = v
                    _G.VanishInvisDepth = v
                    if SaveConfig then pcall(SaveConfig) end
                end)
            makeSliderRow("Walk Speed", 5, 32, 1, Config.InvisWalkSpeed or 16,
                function(v) return tostring(math.floor(v)) end,
                function(v)
                    Config.InvisWalkSpeed = v
                    _G.VanishInvisWalkSpeed = v
                    if SaveConfig then pcall(SaveConfig) end
                end)

            local collapsed = false
            local function toggleCollapse()
                collapsed = not collapsed
                list.Visible = not collapsed
                chev.Text = collapsed and "▸" or "▾"
                panel.Size = UDim2.fromOffset(200, collapsed and HEAD_H or EXP_H)
            end

            mkPanelDraggable(header, panel, "InvisStealPanelX", "InvisStealPanelY", toggleCollapse)
            mkPanelResizeHandle(panel, "InvisStealPanelScale")
        end


        -- Bind toggle key
        _G.MeerkoToggleMenu = function()
            Window.gui.Enabled = not Window.gui.Enabled
        end
        FG_UIS.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if FG_UIS:GetFocusedTextBox() then return end
            if Config.MenuKey and Config.MenuKey ~= "" and input.KeyCode.Name == Config.MenuKey then
                Window.gui.Enabled = not Window.gui.Enabled
            end
        end)
    end)
end