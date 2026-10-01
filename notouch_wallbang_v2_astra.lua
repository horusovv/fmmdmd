if shared.InvertiumCleanup then pcall(shared.InvertiumCleanup) end
local _conns, _insts = {}, {}
local function TC(c) _conns[#_conns+1] = c; return c end
local function TI(i) _insts[#_insts+1] = i; return i end
shared.InvertiumCleanup = function()
    for _, c in ipairs(_conns) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(_insts) do pcall(function() i:Destroy() end) end
    _conns, _insts = {}, {}
end

local _dbg = getfenv().debug.info
if not shared.OriginalDebugInfo then shared.OriginalDebugInfo = _dbg end
do
    local real   = shared.OriginalDebugInfo
    local busy   = false
    if not shared.DebugInfoHooked then
        shared.DebugInfoHooked = true
        pcall(function()
            hookfunction(_dbg, newcclosure(function(...)
                if busy then return real(...) end
                busy = true
                local r = table.pack(real(...))
                busy = false
                local args = {...}
                local fmt  = type(args[1])=="string" and args[1] or type(args[2])=="string" and args[2]
                if fmt then
                    if fmt:find("s") then
                        for i,v in ipairs(r) do
                            if type(v)=="string" and (v=="[C]" or v=="=[C]") then r[i]="[C]" end
                        end
                    end
                    if fmt:find("n") then
                        for i,v in ipairs(r) do
                            if type(v)=="string" and v~="[C]" then r[i]="" end
                        end
                    end
                    if fmt:find("l") then
                        for i,v in ipairs(r) do
                            if type(v)=="number" then r[i]=-1 end
                        end
                    end
                end
                return table.unpack(r, 1, r.n)
            end))
        end)
    end
end

--==============================================================
-- SERVICES + LOCALS
--==============================================================
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Ali-lov3/AstraUiLib/refs/heads/main/Source.lua"
))()

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local Lighting            = game:GetService("Lighting")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local TweenService        = game:GetService("TweenService")
local CoreGui             = game:GetService("CoreGui")
local Workspace           = game:GetService("Workspace")

local LocalPlayer  = Players.LocalPlayer
local Camera       = Workspace.CurrentCamera
local Mouse        = LocalPlayer:GetMouse()
local GUI_PARENT   = (type(gethui)=="function" and pcall(gethui) and gethui()) or CoreGui

local currentChar, currentHRP, currentHead

--==============================================================
-- FIRE REMOTE LOOKUP
--==============================================================
local fireEvent
do
    local rm = ReplicatedStorage:FindFirstChild("ReplicationManager")
    fireEvent = rm and rm:FindFirstChild("Fire")
    if not fireEvent then
        local rems = ReplicatedStorage:FindFirstChild("rems")
        local evs  = rems and rems:FindFirstChild("events")
        local sev  = evs  and evs:FindFirstChild("server")
        fireEvent  = sev  and sev:FindFirstChild("fire")
    end
end

--==============================================================
-- SILENT AIM CORE (safezone, raycast, cansee)
--==============================================================
local function GetPredictionVelocity(hrp)
    local v = hrp.AssemblyLinearVelocity
    return Vector3.new(v.X, 0, v.Z)
end

local SilentAimCore = {}
do
    local PARTS = {"HumanoidRootPart","Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg"}
    local VZONE = {
        center = Vector3.new(-108.075, 5.321, 253.103),
        size   = Vector3.new(17.5, 10.643, 14.145),
    }
    local zoneCache = {zones=nil, lastUpdate=0, lifetime=2}
    local abs = math.abs

    local function PointInAABB(point, zonePos, zoneSize)
        local rel = point - zonePos
        return abs(rel.X)<=zoneSize.X*0.5
           and abs(rel.Y)<=zoneSize.Y*0.5
           and abs(rel.Z)<=zoneSize.Z*0.5
    end

    local function CollectSafeZones()
        local now = tick()
        if zoneCache.zones and (now-zoneCache.lastUpdate)<zoneCache.lifetime then
            return zoneCache.zones
        end
        local zones = {}
        local durka = Workspace:FindFirstChild("\208\180\209\131\209\128\208\186\208\176")
        if durka then
            local sz = durka:FindFirstChild("SafeZones")
            if sz then for _,c in ipairs(sz:GetChildren()) do if c:IsA("BasePart") then zones[#zones+1]=c end end end
        end
        if #zones==0 then
            local sz = Workspace:FindFirstChild("SafeZones")
            if sz then for _,c in ipairs(sz:GetChildren()) do if c:IsA("BasePart") then zones[#zones+1]=c end end end
        end
        if #zones==0 then
            zones[1] = {
                Position = VZONE.center, Size = VZONE.size,
                FindFirstChild = function(_,name) return name=="every_single_team" and true or nil end,
                GetChildren = function() return {} end,
            }
        end
        zoneCache.zones = zones; zoneCache.lastUpdate = now
        return zones
    end

    local function IsTeamAllowedInZone(plr, zone)
        if not plr or not zone then return false end
        if zone:FindFirstChild("every_single_team") then return true end
        local team = plr.Team
        if team and zone:FindFirstChild(tostring(team)) then return true end
        local hasTeamNode = false
        for _,child in ipairs((zone.GetChildren and zone:GetChildren()) or {}) do
            if child.Name ~= "every_single_team" then
                if game:GetService("Teams"):FindFirstChild(child.Name) then hasTeamNode=true; break end
            end
        end
        return not hasTeamNode
    end

    local function IsInSafeZone(character, player)
        if not character then return false end
        player = player or Players:GetPlayerFromCharacter(character)
        if player and player:GetAttribute("SafeZone") then return true end
        if character:FindFirstChildOfClass("ForceField") then return true end
        local zones = CollectSafeZones()
        for _,zone in ipairs(zones) do
            local zPos, zSize = zone.Position, zone.Size
            for _,pName in ipairs(PARTS) do
                local part = character:FindFirstChild(pName)
                if part and part:IsA("BasePart") then
                    if PointInAABB(part.Position, zPos, zSize + part.Size) then
                        if player then if IsTeamAllowedInZone(player, zone) then return true end
                        else return true end
                    end
                end
            end
        end
        return false
    end

    local function GameRay(from, dir, ignore)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = ignore
        params.FilterType = Enum.RaycastFilterType.Exclude
        local mgr = Workspace:FindFirstChild("Manager")
        if mgr then params:AddToFilter(mgr) end
        local res = Workspace:Raycast(from, dir, params)
        if not res then return nil, from+dir, nil end
        local hp = res.Instance
        if hp.Parent:FindFirstChild("not_ignore_ray") then return hp, res.Position, res.Normal end
        if not hp.Parent:FindFirstChild("Humanoid") then
            if hp.CollisionGroupId~=0 or not hp.CanCollide then
                local n={}; for i=1,#ignore do n[i]=ignore[i] end; n[#n+1]=hp
                return GameRay(from, dir, n)
            end
        end
        if hp.Parent:IsA("Accessory") or hp.Parent:IsA("Hat") then
            local n={}; for i=1,#ignore do n[i]=ignore[i] end; n[#n+1]=hp.Parent
            return GameRay(from, dir, n)
        end
        return hp, res.Position, res.Normal
    end

    local function FastCanSee(fromChar, targetPart)
        if not fromChar or not targetPart then return false, nil end
        local head = fromChar:FindFirstChild("Head")
        if not head then return false, nil end
        local dir = (targetPart.Position - head.Position).Unit * 1000
        local hp  = GameRay(head.Position, dir, {fromChar, Camera})
        if not hp then return false, nil end
        if hp.Parent == targetPart.Parent then return true, hp.Parent end
        if hp.Parent:FindFirstChild("Humanoid") then return true, hp.Parent end
        return false, nil
    end

    SilentAimCore.IsInSafeZone = IsInSafeZone
    SilentAimCore.FastCanSee   = FastCanSee
    SilentAimCore.GameRay      = GameRay
end

local function GetBodyPart(char, name)
    local p = char:FindFirstChild(name)
    return (p and p:IsA("BasePart")) and p or nil
end

local function IsPlayerSZProtected(plr)
    if not plr or not plr.Character then return false end
    return SilentAimCore.IsInSafeZone(plr.Character, plr)
end

local function CanAutoFireAtPlayer(target)
    if not target or not target.Character then return false end
    local hum = target.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if IsPlayerSZProtected(LocalPlayer) or IsPlayerSZProtected(target) then return false end
    return true
end

--==============================================================
-- GUN STATE
--==============================================================
local CurrentGun       = nil
local CurrentGunConfig = nil
local lastAutoFireTime = 0

local function UpdateCurrentGun()
    CurrentGun = nil; CurrentGunConfig = nil
    local char = LocalPlayer.Character
    if not char then return end
    for _,child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and child:FindFirstChild("ConfigGun") then
            CurrentGun = child
            local ok, cfg = pcall(require, child:FindFirstChild("ConfigGun"))
            if ok and type(cfg)=="table" then CurrentGunConfig = cfg end
            break
        end
    end
end

local function HookCharacter(char)
    TC(char.ChildAdded:Connect(function(c) if c:IsA("Tool") then task.defer(UpdateCurrentGun) end end))
    TC(char.ChildRemoved:Connect(function(c) if c:IsA("Tool") then task.defer(UpdateCurrentGun) end end))
    task.defer(UpdateCurrentGun)
end

local function CanAutoFireNow()
    local cfg = CurrentGunConfig
    if not cfg then return false end
    local delay = (cfg.FireDelay or 0.1)
    if cfg.TimeWaitAfterShootPump then delay = delay + cfg.TimeWaitAfterShootPump end
    local now = time()
    if now - lastAutoFireTime < delay then return false end
    lastAutoFireTime = now
    return true
end

--==============================================================
-- SILENT AIM STATE
--==============================================================
local SilentAim = {
    Enabled         = false,
    AutoFireEnabled = false,
    UsePrediction   = false,
    PredictionAmount= 0,
    AimPart         = "Head",
    UseTargetList   = false,
    TargetedPlayers = {},
    WallbangEnabled = false,
}

--==============================================================
-- KROVOSOS SILENT AIM
--==============================================================
local KrovososSA = { Enabled = false, AimPart = "Head" }

local function GetKrovososTarget()
    local mousePos = UserInputService:GetMouseLocation()
    local bestDist, bestPart = math.huge, nil
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "Krovosos" then
            local part = nil
            if obj:IsA("BasePart") then part = obj
            elseif obj:IsA("Model") then
                part = obj:FindFirstChild(KrovososSA.AimPart) or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            end
            if part and part:IsA("BasePart") then
                local p2D = Camera:WorldToViewportPoint(part.Position)
                if p2D.Z > 0 then
                    local d = (Vector2.new(p2D.X, p2D.Y) - mousePos).Magnitude
                    if d < bestDist then bestDist = d; bestPart = part end
                end
            end
        end
    end
    return bestPart
end

--==============================================================
-- GET CLOSEST ENEMY PART
--==============================================================
local function GetClosestEnemyPart(aimPart, useTargetList, targetTable)
    if not (currentChar and currentHRP and currentHead) then return nil, nil end
    if currentChar:FindFirstChildOfClass("ForceField") then return nil, nil end
    if SilentAimCore.IsInSafeZone(currentChar, LocalPlayer) then return nil, nil end

    local mousePos = UserInputService:GetMouseLocation()
    local bestDist, bestPart, bestPlayer = math.huge, nil, nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hum = plr.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                if not useTargetList or targetTable[plr.Name] then
                    if not SilentAimCore.IsInSafeZone(plr.Character, plr) then
                        if not plr.Character:FindFirstChildOfClass("ForceField") then
                            local tP = GetBodyPart(plr.Character, aimPart) or plr.Character:FindFirstChild("Head")
                            if tP then
                                local p2D = Camera:WorldToViewportPoint(tP.Position)
                                if p2D.Z > 0 then
                                    local sDist = (Vector2.new(p2D.X, p2D.Y) - mousePos).Magnitude
                                    if sDist < bestDist then
                                        if SilentAim.WallbangEnabled then
                                            bestDist=sDist; bestPart=tP; bestPlayer=plr
                                        else
                                            local canHit, hitChar = SilentAimCore.FastCanSee(currentChar, tP)
                                            if canHit and hitChar == plr.Character then
                                                bestDist=sDist; bestPart=tP; bestPlayer=plr
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestPlayer
end

--==============================================================
-- AUTO FIRE
--==============================================================
local function DirectFireSilentAim()
    if not SilentAim.Enabled or not SilentAim.AutoFireEnabled then return false end
    if not fireEvent or not (currentChar and currentHRP) then return false end
    local gun, cfg = CurrentGun, CurrentGunConfig
    if not gun or not cfg then return false end
    if (cfg.AmmoInMag or 0) <= 0 or cfg.SafeMode or cfg.FullDelay then return false end
    if gun.Parent ~= currentChar then return false end
    if currentChar:FindFirstChildOfClass("ForceField") then return false end
    if SilentAimCore.IsInSafeZone(currentChar, LocalPlayer) then return false end
    if not CanAutoFireNow() then return false end
    local part, plr = GetClosestEnemyPart(SilentAim.AimPart, SilentAim.UseTargetList, SilentAim.TargetedPlayers)
    if not part or not plr or not CanAutoFireAtPlayer(plr) then return false end
    local targetPos = part.Position
    if SilentAim.UsePrediction and SilentAim.PredictionAmount > 0 then
        local hrp2 = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp2 then targetPos = targetPos + GetPredictionVelocity(hrp2) * SilentAim.PredictionAmount end
    end
    pcall(function() fireEvent:FireServer(targetPos, part.Position, part) end)
    return true
end

--==============================================================
-- MOUSE.HIT HOOK
--==============================================================
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if self:IsA("Mouse") and key == "Hit" then
        if KrovososSA.Enabled and not IsPlayerSZProtected(LocalPlayer) then
            local kpart = GetKrovososTarget()
            if kpart then return CFrame.new(kpart.Position) end
        end
        if SilentAim.Enabled then
            local part, plr = GetClosestEnemyPart(SilentAim.AimPart, SilentAim.UseTargetList, SilentAim.TargetedPlayers)
            if part and plr and not IsPlayerSZProtected(LocalPlayer) and not IsPlayerSZProtected(plr) then
                local pos = part.Position
                if SilentAim.UsePrediction and SilentAim.PredictionAmount > 0 then
                    local hrp2 = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                    if hrp2 then pos = pos + GetPredictionVelocity(hrp2) * SilentAim.PredictionAmount end
                end
                return CFrame.new(pos)
            end
        end
    end
    return oldIndex(self, key)
end)

--==============================================================
-- TARGET LIST WINDOW (Astra SearchDropdown-powered)
--==============================================================
-- Target list uses a ScreenGui overlay so it's library-independent
-- and opens via keybind. Players added/removed are tracked live.
-- Selection state stored in SilentAim.TargetedPlayers.

local GlobalBlur = TI(Instance.new("BlurEffect"))
GlobalBlur.Name = "SilentBlur"; GlobalBlur.Size = 0; GlobalBlur.Parent = Lighting

local function CreateTargetListWindow(targetTable)
    local WD = {}
    local sg = TI(Instance.new("ScreenGui"))
    sg.Name = "AstraTargetList"
    sg.Parent = GUI_PARENT
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 200

    local smoothTw = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local function tw(o, p) TweenService:Create(o, smoothTw, p):Play() end

    -- root frame
    local Main = Instance.new("Frame", sg)
    Main.Size = UDim2.new(0, 560, 0, 420)
    Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main.AnchorPoint = Vector2.new(0.5, 0.5)
    Main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    Main.BackgroundTransparency = 1
    Main.ClipsDescendants = true
    Main.Visible = false
    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

    -- outer stroke
    local MS = Instance.new("UIStroke", Main)
    MS.Color = Color3.fromRGB(40, 40, 52)
    MS.Transparency = 1
    MS.Thickness = 1.5

    -- drag logic
    local drag, ds, dp
    Main.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true; ds = i.Position; dp = Main.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then drag = false end
            end)
        end
    end)
    TC(UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            Main.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y)
        end
    end))

    -- accent top bar
    local TopBar = Instance.new("Frame", Main)
    TopBar.Size = UDim2.new(1, 0, 0, 52)
    TopBar.Position = UDim2.new(0, 0, 0, 0)
    TopBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    TopBar.BackgroundTransparency = 1
    TopBar.BorderSizePixel = 0
    Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 10)

    -- title
    local Title = Instance.new("TextLabel", TopBar)
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 18, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Font = Enum.Font.GothamBold
    Title.Text = "Target List"
    Title.TextColor3 = Color3.fromRGB(220, 220, 235)
    Title.TextSize = 15
    Title.TextTransparency = 1
    Title.TextXAlignment = Enum.TextXAlignment.Left

    -- subtitle
    local SubTitle = Instance.new("TextLabel", TopBar)
    SubTitle.Size = UDim2.new(1, -60, 0, 16)
    SubTitle.Position = UDim2.new(0, 18, 0, 30)
    SubTitle.BackgroundTransparency = 1
    SubTitle.Font = Enum.Font.Gotham
    SubTitle.Text = "silent aim"
    SubTitle.TextColor3 = Color3.fromRGB(90, 110, 180)
    SubTitle.TextSize = 11
    SubTitle.TextTransparency = 1
    SubTitle.TextXAlignment = Enum.TextXAlignment.Left

    -- close btn
    local CloseBtn = Instance.new("TextButton", TopBar)
    CloseBtn.Size = UDim2.new(0, 28, 0, 28)
    CloseBtn.AnchorPoint = Vector2.new(1, 0.5)
    CloseBtn.Position = UDim2.new(1, -14, 0.5, 0)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
    CloseBtn.BackgroundTransparency = 1
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Color3.fromRGB(100, 100, 115)
    CloseBtn.TextSize = 13
    CloseBtn.TextTransparency = 1
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(1, 0)
    CloseBtn.MouseEnter:Connect(function() tw(CloseBtn, {TextColor3 = Color3.fromRGB(220, 220, 235), BackgroundTransparency = 0.4}) end)
    CloseBtn.MouseLeave:Connect(function() tw(CloseBtn, {TextColor3 = Color3.fromRGB(100, 100, 115), BackgroundTransparency = 1}) end)

    -- divider
    local Div = Instance.new("Frame", Main)
    Div.Size = UDim2.new(1, -28, 0, 1)
    Div.Position = UDim2.new(0, 14, 0, 52)
    Div.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    Div.BackgroundTransparency = 1
    Div.BorderSizePixel = 0

    -- count label
    local CountLabel = Instance.new("TextLabel", Main)
    CountLabel.Size = UDim2.new(1, -28, 0, 20)
    CountLabel.Position = UDim2.new(0, 14, 0, 60)
    CountLabel.BackgroundTransparency = 1
    CountLabel.Font = Enum.Font.Gotham
    CountLabel.Text = "0 targeted"
    CountLabel.TextColor3 = Color3.fromRGB(75, 100, 165)
    CountLabel.TextSize = 11
    CountLabel.TextTransparency = 1
    CountLabel.TextXAlignment = Enum.TextXAlignment.Left

    -- scroll
    local Scroll = Instance.new("ScrollingFrame", Main)
    Scroll.Size = UDim2.new(1, -28, 1, -92)
    Scroll.Position = UDim2.new(0, 14, 0, 86)
    Scroll.BackgroundTransparency = 1
    Scroll.ScrollBarThickness = 2
    Scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 110)
    Scroll.BorderSizePixel = 0

    local Grid = Instance.new("UIGridLayout", Scroll)
    Grid.CellSize = UDim2.new(0, 166, 0, 58)
    Grid.CellPadding = UDim2.new(0, 6, 0, 6)
    Grid.SortOrder = Enum.SortOrder.LayoutOrder

    local function UpdateCountLabel()
        local n = 0
        for _ in pairs(targetTable) do n = n + 1 end
        CountLabel.Text = n .. " targeted"
    end

    local function updScroll()
        Scroll.CanvasSize = UDim2.new(0, 0, 0, Grid.AbsoluteContentSize.Y + 10)
    end
    TC(Grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updScroll))

    local Cards = {}
    local visible, animating = false, false

    local function CreateCard(plr)
        if Cards[plr.Name] then return end

        local Card = Instance.new("TextButton", Scroll)
        Card.Name = plr.Name
        Card.Size = UDim2.new(1, 0, 1, 0)
        Card.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        Card.BackgroundTransparency = 0.3
        Card.AutoButtonColor = false
        Card.Text = ""
        Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 7)

        local CS = Instance.new("UIStroke", Card)
        CS.Color = Color3.fromRGB(40, 40, 55)
        CS.Transparency = 0.3
        CS.Thickness = 1

        -- avatar
        local Av = Instance.new("ImageLabel", Card)
        Av.Size = UDim2.new(0, 38, 0, 38)
        Av.Position = UDim2.new(0, 8, 0.5, 0)
        Av.AnchorPoint = Vector2.new(0, 0.5)
        Av.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
        Av.BackgroundTransparency = 0.1
        Instance.new("UICorner", Av).CornerRadius = UDim.new(1, 0)
        task.spawn(function()
            local ok, img = pcall(function()
                return Players:GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
            end)
            if ok then Av.Image = img end
        end)

        -- selected indicator dot
        local Dot = Instance.new("Frame", Card)
        Dot.Size = UDim2.new(0, 7, 0, 7)
        Dot.AnchorPoint = Vector2.new(1, 0)
        Dot.Position = UDim2.new(1, -6, 0, 6)
        Dot.BackgroundColor3 = Color3.fromRGB(55, 120, 255)
        Dot.BackgroundTransparency = 1
        Dot.BorderSizePixel = 0
        Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

        -- display name
        local DN = Instance.new("TextLabel", Card)
        DN.Size = UDim2.new(1, -58, 0, 16)
        DN.Position = UDim2.new(0, 54, 0, 10)
        DN.BackgroundTransparency = 1
        DN.Font = Enum.Font.GothamBold
        DN.Text = plr.DisplayName
        DN.TextColor3 = Color3.fromRGB(210, 210, 225)
        DN.TextSize = 12
        DN.TextXAlignment = Enum.TextXAlignment.Left
        DN.TextTruncate = Enum.TextTruncate.AtEnd

        -- username
        local UN = Instance.new("TextLabel", Card)
        UN.Size = UDim2.new(1, -58, 0, 13)
        UN.Position = UDim2.new(0, 54, 0, 28)
        UN.BackgroundTransparency = 1
        UN.Font = Enum.Font.Gotham
        UN.Text = "@" .. plr.Name
        UN.TextColor3 = Color3.fromRGB(90, 90, 110)
        UN.TextSize = 10
        UN.TextXAlignment = Enum.TextXAlignment.Left
        UN.TextTruncate = Enum.TextTruncate.AtEnd

        local function UpdateVis()
            if not visible then return end
            if targetTable[plr.Name] then
                tw(Card, {BackgroundColor3 = Color3.fromRGB(18, 36, 80), BackgroundTransparency = 0.05})
                tw(CS, {Color = Color3.fromRGB(55, 120, 255), Transparency = 0, Thickness = 1.5})
                tw(DN, {TextColor3 = Color3.fromRGB(255, 255, 255)})
                tw(UN, {TextColor3 = Color3.fromRGB(80, 130, 220)})
                tw(Dot, {BackgroundTransparency = 0})
            else
                tw(Card, {BackgroundColor3 = Color3.fromRGB(22, 22, 30), BackgroundTransparency = 0.3})
                tw(CS, {Color = Color3.fromRGB(40, 40, 55), Transparency = 0.3, Thickness = 1})
                tw(DN, {TextColor3 = Color3.fromRGB(210, 210, 225)})
                tw(UN, {TextColor3 = Color3.fromRGB(90, 90, 110)})
                tw(Dot, {BackgroundTransparency = 1})
            end
        end

        Card.MouseEnter:Connect(function()
            if not targetTable[plr.Name] and visible then
                tw(CS, {Color = Color3.fromRGB(70, 80, 120), Transparency = 0.1})
                tw(Card, {BackgroundTransparency = 0.1})
            end
        end)
        Card.MouseLeave:Connect(UpdateVis)
        Card.MouseButton1Click:Connect(function()
            if not visible then return end
            targetTable[plr.Name] = not targetTable[plr.Name] or nil
            UpdateVis()
            UpdateCountLabel()
        end)

        Cards[plr.Name] = { Frame = Card, Update = UpdateVis }
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then CreateCard(p) end
    end
    TC(Players.PlayerAdded:Connect(function(p) task.wait(); CreateCard(p) end))
    TC(Players.PlayerRemoving:Connect(function(p)
        if Cards[p.Name] then Cards[p.Name].Frame:Destroy(); Cards[p.Name] = nil end
    end))

    local function CloseWin()
        if animating or not visible then return end
        visible = false; animating = true
        tw(Main, {BackgroundTransparency = 1})
        tw(MS, {Transparency = 1})
        tw(TopBar, {BackgroundTransparency = 1})
        tw(Title, {TextTransparency = 1})
        tw(SubTitle, {TextTransparency = 1})
        tw(CloseBtn, {TextTransparency = 1, BackgroundTransparency = 1})
        tw(Div, {BackgroundTransparency = 1})
        tw(CountLabel, {TextTransparency = 1})
        TweenService:Create(GlobalBlur, TweenInfo.new(0.35), {Size = 0}):Play()
        for _, cd in pairs(Cards) do
            local c = cd.Frame
            tw(c, {BackgroundTransparency = 1})
            local s = c:FindFirstChildOfClass("UIStroke"); if s then tw(s, {Transparency = 1}) end
            for _, e in ipairs(c:GetChildren()) do
                if e:IsA("TextLabel") then tw(e, {TextTransparency = 1})
                elseif e:IsA("ImageLabel") then tw(e, {ImageTransparency = 1, BackgroundTransparency = 1})
                elseif e:IsA("Frame") then tw(e, {BackgroundTransparency = 1}) end
            end
        end
        task.wait(0.38)
        Main.Visible = false; animating = false
    end

    local function OpenWin()
        if animating or visible then return end
        visible = true; animating = true; Main.Visible = true
        tw(Main, {BackgroundTransparency = 0.04})
        tw(MS, {Transparency = 0.4})
        tw(TopBar, {BackgroundTransparency = 0.0})
        tw(Title, {TextTransparency = 0})
        tw(SubTitle, {TextTransparency = 0})
        tw(CloseBtn, {TextTransparency = 0})
        tw(Div, {BackgroundTransparency = 0.6})
        tw(CountLabel, {TextTransparency = 0})
        TweenService:Create(GlobalBlur, TweenInfo.new(0.35), {Size = 12}):Play()
        UpdateCountLabel()
        for _, cd in pairs(Cards) do
            cd.Update()
            local c = cd.Frame
            tw(c, {BackgroundTransparency = 0.3})
            local s = c:FindFirstChildOfClass("UIStroke"); if s then tw(s, {Transparency = 0.3}) end
            for _, e in ipairs(c:GetChildren()) do
                if e:IsA("TextLabel") then tw(e, {TextTransparency = 0})
                elseif e:IsA("ImageLabel") then tw(e, {ImageTransparency = 0, BackgroundTransparency = 0.1})
                elseif e:IsA("Frame") and e.Name ~= "" then
                    if targetTable[c.Name] then tw(e, {BackgroundTransparency = 0})
                    else tw(e, {BackgroundTransparency = 1}) end
                end
            end
        end
        task.delay(0.4, updScroll)
        task.wait(0.38); animating = false
    end

    CloseBtn.MouseButton1Click:Connect(CloseWin)
    WD.Toggle = function() if visible then CloseWin() else OpenWin() end end
    return WD
end

local TargetListWin = CreateTargetListWindow(SilentAim.TargetedPlayers)

--==============================================================
-- WALLBANG V2
--==============================================================
local WallbangV2 = {
    Enabled = false, DropDistance = 15, FloatHold = true,
    Duration = 10, RestorePosition = true, Running = false,
    SavedCFrame = nil, FloatConnection = nil,
}

local function StopWallbangV2()
    if WallbangV2.FloatConnection then WallbangV2.FloatConnection:Disconnect(); WallbangV2.FloatConnection = nil end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and WallbangV2.RestorePosition and WallbangV2.SavedCFrame then
        hrp.CFrame = WallbangV2.SavedCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    WallbangV2.SavedCFrame = nil
    WallbangV2.Running = false
end

local function StartWallbangV2()
    if WallbangV2.Running then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    WallbangV2.Running = true
    WallbangV2.SavedCFrame = hrp.CFrame
    hrp.CFrame = hrp.CFrame + Vector3.new(0, -WallbangV2.DropDistance, 0)
    if WallbangV2.FloatHold then
        local floatY = hrp.Position.Y
        WallbangV2.FloatConnection = RunService.Heartbeat:Connect(function()
            if not WallbangV2.Running then return end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then StopWallbangV2(); return end
            local pos = root.Position
            local rx, ry, rz = root.CFrame:ToOrientation()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(pos.X, floatY, pos.Z) * CFrame.Angles(rx, ry, rz)
        end)
    end
    task.delay(WallbangV2.Duration, function()
        if WallbangV2.Running then StopWallbangV2() end
    end)
end

--==============================================================
-- WALLBANG V3
--==============================================================
local WallbangV3 = { Enabled = false, Method = "Origin Spoof" }

local _wbv3Old
local _wbv3Hooked = false

local function _WBV3_GetTarget()
    return GetClosestEnemyPart(SilentAim.AimPart, SilentAim.UseTargetList, SilentAim.TargetedPlayers)
end

local function _WBV3_ApplyHook()
    if _wbv3Hooked then return end
    _wbv3Hooked = true
    _wbv3Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if WallbangV3.Enabled
        and (m == "FireServer" or m == "InvokeServer")
        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            local args = {...}
            local vecIdxs = {}
            for i, v in ipairs(args) do if typeof(v) == "Vector3" then vecIdxs[#vecIdxs+1]=i end end
            local method = WallbangV3.Method

            if method == "Origin Spoof" then
                if #vecIdxs >= 2 then args[vecIdxs[#vecIdxs]] = args[vecIdxs[1]] end

            elseif method == "HRP Redirect" then
                local part = _WBV3_GetTarget()
                if part and vecIdxs[1] then args[vecIdxs[1]] = part.Position end

            elseif method == "TP Bang" then
                local part = _WBV3_GetTarget()
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if part and hrp then
                    local realCF = hrp.CFrame
                    hrp.CFrame = CFrame.new(part.Position + Vector3.new(2, 0, 2))
                    local result = _wbv3Old(self, table.unpack(args))
                    task.defer(function() hrp.CFrame = realCF end)
                    return result
                end

            elseif method == "Smart Detect" then
                local part = _WBV3_GetTarget()
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if part and hrp and #vecIdxs >= 2 then
                    local myPos, targetPos = hrp.Position, part.Position
                    local originIdx, hitIdx
                    local bestOriginDist = math.huge
                    for _, idx in ipairs(vecIdxs) do
                        local d = (args[idx] - myPos).Magnitude
                        if d < bestOriginDist then bestOriginDist=d; originIdx=idx end
                    end
                    local bestHitDist = math.huge
                    for _, idx in ipairs(vecIdxs) do
                        if idx ~= originIdx then
                            local d = (args[idx] - targetPos).Magnitude
                            if d < bestHitDist then bestHitDist=d; hitIdx=idx end
                        end
                    end
                    if originIdx and hitIdx then args[originIdx] = args[hitIdx] end
                end

            elseif method == "Zero Distance" then
                local part = _WBV3_GetTarget()
                if part then for _, idx in ipairs(vecIdxs) do args[idx] = part.Position end end
            end

            return _wbv3Old(self, table.unpack(args))
        end
        return _wbv3Old(self, ...)
    end))
end

local function StartWallbangV3() WallbangV3.Enabled = true; _WBV3_ApplyHook() end
local function StopWallbangV3()  WallbangV3.Enabled = false end

--==============================================================
-- ASTRA UI
--==============================================================
local Window = Library.CreateWindow({
    Title        = "invertium",
    Logo         = 0,
    Anonymous    = false,
    ConfigFolder = "InvertiumConfigs",
})

local MainTab     = Window:CreateTab({ Name = "Main",     Icon = "crosshair" })
local WBTab       = Window:CreateTab({ Name = "Wallbang", Icon = "zap" })
local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })

--==============================================================
-- MAIN TAB — Silent Aim (Left)
--==============================================================
local SASection = MainTab:CreateSection({ Name = "Silent Aim", Side = "Left" })

SASection:AddToggle({
    Name      = "Enable Silent Aim",
    Default   = false,
    ConfigKey = "sa_enabled",
    Callback  = function(v) SilentAim.Enabled = v end,
})

SASection:AddDropdown({
    Name      = "Aim Part",
    Options   = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"},
    Default   = "Head",
    ConfigKey = "sa_aimpart",
    Callback  = function(v) SilentAim.AimPart = v end,
})

SASection:AddToggle({
    Name      = "Prediction",
    Default   = false,
    ConfigKey = "sa_prediction",
    Callback  = function(v) SilentAim.UsePrediction = v end,
})

SASection:AddSlider({
    Name      = "Prediction Amount",
    Min       = 0,
    Max       = 1,
    Default   = 0,
    ConfigKey = "sa_predamt",
    Callback  = function(v) SilentAim.PredictionAmount = v end,
})

SASection:AddToggle({
    Name      = "Wallbang (SA)",
    Default   = false,
    ConfigKey = "sa_wallbang",
    Callback  = function(v) SilentAim.WallbangEnabled = v end,
})

SASection:AddToggle({
    Name      = "Auto Fire",
    Default   = false,
    ConfigKey = "sa_autofire",
    Callback  = function(v) SilentAim.AutoFireEnabled = v end,
})

SASection:AddToggle({
    Name      = "Use Target List",
    Default   = false,
    ConfigKey = "sa_usetargetlist",
    Callback  = function(v) SilentAim.UseTargetList = v end,
})

SASection:AddKeybind({
    Name      = "Open Target List",
    Default   = Enum.KeyCode.F,
    ConfigKey = "sa_targetlistkey",
    Callback  = function(_) TargetListWin:Toggle() end,
})

--==============================================================
-- MAIN TAB — Krovosos SA (Right)
--==============================================================
local KSASection = MainTab:CreateSection({ Name = "Krovosos SA", Side = "Right" })

KSASection:AddToggle({
    Name      = "Enable Krovosos SA",
    Default   = false,
    ConfigKey = "ksa_enabled",
    Callback  = function(v) KrovososSA.Enabled = v end,
})

KSASection:AddDropdown({
    Name      = "Aim Part",
    Options   = {"Head", "HumanoidRootPart", "Torso"},
    Default   = "Head",
    ConfigKey = "ksa_aimpart",
    Callback  = function(v) KrovososSA.AimPart = v end,
})

--==============================================================
-- WALLBANG TAB — V2 (Left)
--==============================================================
local WBV2Section = WBTab:CreateSection({ Name = "Wallbang V2", Side = "Left" })

WBV2Section:AddToggle({
    Name      = "Enable Wallbang V2",
    Default   = false,
    ConfigKey = "wbv2_enabled",
    Callback  = function(v)
        WallbangV2.Enabled = v
        if v then StartWallbangV2() elseif WallbangV2.Running then StopWallbangV2() end
    end,
})

WBV2Section:AddKeybind({
    Name      = "Wallbang V2 Key",
    Default   = Enum.KeyCode.Unknown,
    ConfigKey = "wbv2_key",
    Callback  = function(_)
        WallbangV2.Enabled = not WallbangV2.Enabled
        if WallbangV2.Enabled then StartWallbangV2() elseif WallbangV2.Running then StopWallbangV2() end
    end,
})

WBV2Section:AddSlider({
    Name      = "Drop Distance",
    Min       = 1,
    Max       = 50,
    Default   = 15,
    ConfigKey = "wbv2_drop",
    Callback  = function(v) WallbangV2.DropDistance = v end,
})

WBV2Section:AddToggle({
    Name      = "Float Hold",
    Default   = true,
    ConfigKey = "wbv2_float",
    Callback  = function(v) WallbangV2.FloatHold = v end,
})

WBV2Section:AddSlider({
    Name      = "Duration (s)",
    Min       = 1,
    Max       = 60,
    Default   = 10,
    ConfigKey = "wbv2_dur",
    Callback  = function(v) WallbangV2.Duration = v end,
})

WBV2Section:AddToggle({
    Name      = "Restore Position",
    Default   = true,
    ConfigKey = "wbv2_restore",
    Callback  = function(v) WallbangV2.RestorePosition = v end,
})

--==============================================================
-- WALLBANG TAB — V3 (Right)
--==============================================================
local WBV3Section = WBTab:CreateSection({ Name = "Wallbang V3", Side = "Right" })

WBV3Section:AddToggle({
    Name      = "Enable Wallbang V3",
    Default   = false,
    ConfigKey = "wbv3_enabled",
    Callback  = function(v)
        if v then StartWallbangV3() else StopWallbangV3() end
    end,
})

WBV3Section:AddKeybind({
    Name      = "Wallbang V3 Key",
    Default   = Enum.KeyCode.Unknown,
    ConfigKey = "wbv3_key",
    Callback  = function(_)
        WallbangV3.Enabled = not WallbangV3.Enabled
        if WallbangV3.Enabled then StartWallbangV3() else StopWallbangV3() end
    end,
})

WBV3Section:AddDropdown({
    Name      = "Method",
    Options   = {"Origin Spoof", "HRP Redirect", "TP Bang", "Smart Detect", "Zero Distance"},
    Default   = "Origin Spoof",
    ConfigKey = "wbv3_method",
    Callback  = function(v) WallbangV3.Method = v end,
})

--==============================================================
-- SETTINGS TAB
--==============================================================
local MenuSection = SettingsTab:CreateSection({ Name = "Menu", Side = "Left" })

MenuSection:AddKeybind({
    Name      = "Toggle Menu",
    Default   = Enum.KeyCode.RightShift,
    ConfigKey = "menu_keybind",
    Callback  = function(_) Library.ToggleUI() end,
})

local ConfigSection = SettingsTab:CreateSection({ Name = "Config", Side = "Right" })
ConfigSection:ApplyConfigManager({})

--==============================================================
-- HEARTBEAT
--==============================================================
TC(RunService.Heartbeat:Connect(function()
    local c = LocalPlayer.Character
    currentChar = c
    if c then
        currentHRP  = c:FindFirstChild("HumanoidRootPart")
        currentHead = c:FindFirstChild("Head")
    else
        currentHRP = nil; currentHead = nil
    end
    if SilentAim.Enabled and SilentAim.AutoFireEnabled
    and currentChar and currentHRP and CurrentGun and CurrentGunConfig then
        DirectFireSilentAim()
    end
end))

if LocalPlayer.Character then HookCharacter(LocalPlayer.Character) end
TC(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    HookCharacter(char)
end))

Library.Notify({
    Title    = "invertium",
    Text     = "loaded successfully.",
    Icon     = "check",
    Duration = 3,
})
