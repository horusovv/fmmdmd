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

local repo         = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title            = "invertium",
    Footer           = "silent aim",
    ShowCustomCursor = true,
    NotifySide       = "Right",
})

local Tabs = {
    Main         = Window:AddTab("Main",         "crosshair"),
    ["UI Settings"] = Window:AddTab("UI Settings","settings"),
}

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
            if sz then
                for _,c in ipairs(sz:GetChildren()) do
                    if c:IsA("BasePart") then zones[#zones+1]=c end
                end
            end
        end
        if #zones==0 then
            local sz = Workspace:FindFirstChild("SafeZones")
            if sz then
                for _,c in ipairs(sz:GetChildren()) do
                    if c:IsA("BasePart") then zones[#zones+1]=c end
                end
            end
        end
        if #zones==0 then
            zones[1] = {
                Position = VZONE.center,
                Size     = VZONE.size,
                FindFirstChild = function(_,name)
                    return name=="every_single_team" and true or nil
                end,
                GetChildren = function() return {} end,
            }
        end
        zoneCache.zones      = zones
        zoneCache.lastUpdate = now
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
                if game:GetService("Teams"):FindFirstChild(child.Name) then
                    hasTeamNode = true; break
                end
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
            local zPos  = zone.Position
            local zSize = zone.Size
            for _,pName in ipairs(PARTS) do
                local part = character:FindFirstChild(pName)
                if part and part:IsA("BasePart") then
                    if PointInAABB(part.Position, zPos, zSize + part.Size) then
                        if player then
                            if IsTeamAllowedInZone(player, zone) then return true end
                        else
                            return true
                        end
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

local CurrentGun       = nil
local CurrentGunConfig = nil
local lastAutoFireTime = 0

local function UpdateCurrentGun()
    CurrentGun       = nil
    CurrentGunConfig = nil
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
    TC(char.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then task.defer(UpdateCurrentGun) end
    end))
    TC(char.ChildRemoved:Connect(function(c)
        if c:IsA("Tool") then task.defer(UpdateCurrentGun) end
    end))
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

local function GetClosestEnemyPart(aimPart, useTargetList, targetTable)
    if not (currentChar and currentHRP and currentHead) then return nil, nil end
    if currentChar:FindFirstChildOfClass("ForceField") then return nil, nil end
    if SilentAimCore.IsInSafeZone(currentChar, LocalPlayer) then return nil, nil end

    local mousePos  = UserInputService:GetMouseLocation()
    local bestDist, bestPart, bestPlayer = math.huge, nil, nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hum = plr.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                if not useTargetList or targetTable[plr.Name] then
                    if not SilentAimCore.IsInSafeZone(plr.Character, plr) then
                        if not plr.Character:FindFirstChildOfClass("ForceField") then
                            local tP = GetBodyPart(plr.Character, aimPart)
                                or plr.Character:FindFirstChild("Head")
                            if tP then
                                local p2D = Camera:WorldToViewportPoint(tP.Position)
                                if p2D.Z > 0 then
                                    local sDist = (Vector2.new(p2D.X, p2D.Y) - mousePos).Magnitude
                                    if sDist < bestDist then
                                        if SilentAim.WallbangEnabled then
                                            bestDist   = sDist
                                            bestPart   = tP
                                            bestPlayer = plr
                                        else
                                            local canHit, hitChar = SilentAimCore.FastCanSee(currentChar, tP)
                                            if canHit and hitChar == plr.Character then
                                                bestDist   = sDist
                                                bestPart   = tP
                                                bestPlayer = plr
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
    local part, plr = GetClosestEnemyPart(
        SilentAim.AimPart,
        SilentAim.UseTargetList,
        SilentAim.TargetedPlayers
    )
    if not part or not plr or not CanAutoFireAtPlayer(plr) then return false end
    local targetPos = part.Position
    if SilentAim.UsePrediction and SilentAim.PredictionAmount > 0 then
        local hrp2 = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp2 then
            targetPos = targetPos + GetPredictionVelocity(hrp2) * SilentAim.PredictionAmount
        end
    end
    pcall(function() fireEvent:FireServer(targetPos, part.Position, part) end)
    return true
end

local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if SilentAim.Enabled and self:IsA("Mouse") and key == "Hit" then
        local part, plr = GetClosestEnemyPart(
            SilentAim.AimPart,
            SilentAim.UseTargetList,
            SilentAim.TargetedPlayers
        )
        if part and plr
            and not IsPlayerSZProtected(LocalPlayer)
            and not IsPlayerSZProtected(plr)
        then
            local pos = part.Position
            if SilentAim.UsePrediction and SilentAim.PredictionAmount > 0 then
                local hrp2 = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp2 then
                    pos = pos + GetPredictionVelocity(hrp2) * SilentAim.PredictionAmount
                end
            end
            return CFrame.new(pos)
        end
    end
    return oldIndex(self, key)
end)

local GlobalBlur = TI(Instance.new("BlurEffect"))
GlobalBlur.Name   = "SilentBlur"
GlobalBlur.Size   = 0
GlobalBlur.Parent = Lighting

local function CreateTargetListWindow(targetTable)
    local WD = {}
    local sg = TI(Instance.new("ScreenGui"))
    sg.Name="SilentAimTargets"; sg.Parent=GUI_PARENT
    sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.DisplayOrder=100

    local smoothTw = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local function tw(o,p) TweenService:Create(o,smoothTw,p):Play() end

    local Main = Instance.new("Frame", sg)
    Main.Size=UDim2.new(0,640,0,390); Main.Position=UDim2.new(0.5,0,0.5,0)
    Main.AnchorPoint=Vector2.new(0.5,0.5); Main.BackgroundColor3=Color3.fromRGB(22,22,28)
    Main.BackgroundTransparency=1; Main.ClipsDescendants=true; Main.Visible=false
    Instance.new("UICorner",Main).CornerRadius=UDim.new(0,8)
    local MS = Instance.new("UIStroke",Main); MS.Color=Color3.fromRGB(55,55,65); MS.Transparency=1

    local drag,ds,dp
    Main.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true; ds=i.Position; dp=Main.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then drag=false end
            end)
        end
    end)
    TC(UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds
            Main.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y)
        end
    end))

    local Title = Instance.new("TextLabel",Main)
    Title.Size=UDim2.new(0,300,0,48); Title.Position=UDim2.new(0,18,0,0)
    Title.BackgroundTransparency=1; Title.Font=Enum.Font.GothamBold
    Title.Text="Silent Aim  /  Target List"; Title.TextColor3=Color3.new(1,1,1)
    Title.TextSize=18; Title.TextTransparency=1; Title.TextXAlignment=Enum.TextXAlignment.Left

    local CloseBtn = Instance.new("TextButton",Main)
    CloseBtn.Size=UDim2.new(0,28,0,28); CloseBtn.AnchorPoint=Vector2.new(1,0.5)
    CloseBtn.Position=UDim2.new(1,-12,0,24); CloseBtn.BackgroundTransparency=1
    CloseBtn.Font=Enum.Font.GothamBold; CloseBtn.Text="✕"
    CloseBtn.TextColor3=Color3.fromRGB(130,130,140); CloseBtn.TextSize=15; CloseBtn.TextTransparency=1
    CloseBtn.MouseEnter:Connect(function() tw(CloseBtn,{TextColor3=Color3.new(1,1,1)}) end)
    CloseBtn.MouseLeave:Connect(function() tw(CloseBtn,{TextColor3=Color3.fromRGB(130,130,140)}) end)

    local Div = Instance.new("Frame",Main)
    Div.Size=UDim2.new(1,-32,0,1); Div.Position=UDim2.new(0,16,0,48)
    Div.BackgroundColor3=Color3.new(1,1,1); Div.BackgroundTransparency=1; Div.BorderSizePixel=0

    local Scroll = Instance.new("ScrollingFrame",Main)
    Scroll.Size=UDim2.new(1,-32,1,-70); Scroll.Position=UDim2.new(0,16,0,58)
    Scroll.BackgroundTransparency=1; Scroll.ScrollBarThickness=3
    Scroll.ScrollBarImageColor3=Color3.fromRGB(70,70,80); Scroll.BorderSizePixel=0
    local Grid = Instance.new("UIGridLayout",Scroll)
    Grid.CellSize=UDim2.new(0,190,0,62); Grid.CellPadding=UDim2.new(0,7,0,7)
    Grid.SortOrder=Enum.SortOrder.LayoutOrder
    local function updScroll()
        local h=Grid.AbsoluteContentSize.Y+10
        Scroll.CanvasSize=UDim2.new(0,0,0,h)
    end
    TC(Grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updScroll))

    local Cards = {}
    local visible,animating = false,false

    local function CreateCard(plr)
        if Cards[plr.Name] then return end
        local Card = Instance.new("TextButton",Scroll)
        Card.Name=plr.Name; Card.Size=UDim2.new(1,0,1,0)
        Card.BackgroundColor3=Color3.fromRGB(30,28,36); Card.BackgroundTransparency=0.4
        Card.AutoButtonColor=false; Card.Text=""
        Instance.new("UICorner",Card).CornerRadius=UDim.new(0,6)
        local CS=Instance.new("UIStroke",Card); CS.Color=Color3.fromRGB(60,58,72); CS.Transparency=0.4; CS.Thickness=1

        local Av=Instance.new("ImageLabel",Card)
        Av.Size=UDim2.new(0,42,0,42); Av.Position=UDim2.new(0,8,0.5,0)
        Av.AnchorPoint=Vector2.new(0,0.5); Av.BackgroundColor3=Color3.fromRGB(18,18,24)
        Instance.new("UICorner",Av).CornerRadius=UDim.new(1,0)
        task.spawn(function()
            local ok,img=pcall(function()
                return Players:GetUserThumbnailAsync(plr.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
            end)
            if ok then Av.Image=img end
        end)

        local DN=Instance.new("TextLabel",Card)
        DN.Size=UDim2.new(1,-62,0,18); DN.Position=UDim2.new(0,60,0,10)
        DN.BackgroundTransparency=1; DN.Font=Enum.Font.GothamBold
        DN.Text=plr.DisplayName; DN.TextColor3=Color3.new(1,1,1)
        DN.TextSize=13; DN.TextXAlignment=Enum.TextXAlignment.Left; DN.TextTruncate=Enum.TextTruncate.AtEnd

        local UN=Instance.new("TextLabel",Card)
        UN.Size=UDim2.new(1,-62,0,14); UN.Position=UDim2.new(0,60,0,30)
        UN.BackgroundTransparency=1; UN.Font=Enum.Font.Gotham
        UN.Text="@"..plr.Name; UN.TextColor3=Color3.fromRGB(140,140,150)
        UN.TextSize=11; UN.TextXAlignment=Enum.TextXAlignment.Left; UN.TextTruncate=Enum.TextTruncate.AtEnd

        local function UpdateVis()
            if not visible then return end
            if targetTable[plr.Name] then
                tw(Card, {BackgroundColor3=Color3.fromRGB(30,70,140), BackgroundTransparency=0.05})
                tw(CS,   {Color=Color3.fromRGB(60,140,255), Transparency=0, Thickness=1.6})
            else
                tw(Card, {BackgroundColor3=Color3.fromRGB(30,28,36), BackgroundTransparency=0.4})
                tw(CS,   {Color=Color3.fromRGB(60,58,72), Transparency=0.4, Thickness=1})
            end
        end

        Card.MouseEnter:Connect(function()
            if not targetTable[plr.Name] and visible then
                tw(CS, {Color=Color3.fromRGB(110,110,120)})
            end
        end)
        Card.MouseLeave:Connect(UpdateVis)
        Card.MouseButton1Click:Connect(function()
            if not visible then return end
            targetTable[plr.Name] = not targetTable[plr.Name] or nil
            UpdateVis()
        end)
        Cards[plr.Name] = {Frame=Card, Update=UpdateVis}
    end

    for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then CreateCard(p) end end
    TC(Players.PlayerAdded:Connect(function(p) task.wait(); CreateCard(p) end))
    TC(Players.PlayerRemoving:Connect(function(p)
        if Cards[p.Name] then Cards[p.Name].Frame:Destroy(); Cards[p.Name]=nil end
    end))

    local function CloseWin()
        if animating or not visible then return end
        visible=false; animating=true
        tw(Main,{BackgroundTransparency=1}); tw(MS,{Transparency=1})
        tw(Title,{TextTransparency=1}); tw(CloseBtn,{TextTransparency=1}); tw(Div,{BackgroundTransparency=1})
        TweenService:Create(GlobalBlur,smoothTw,{Size=0}):Play()
        for _,cd in pairs(Cards) do
            local c=cd.Frame; tw(c,{BackgroundTransparency=1})
            local s=c:FindFirstChildOfClass("UIStroke"); if s then tw(s,{Transparency=1}) end
            for _,e in ipairs(c:GetChildren()) do
                if e:IsA("TextLabel") then tw(e,{TextTransparency=1})
                elseif e:IsA("ImageLabel") then tw(e,{ImageTransparency=1,BackgroundTransparency=1}) end
            end
        end
        task.wait(0.4); Main.Visible=false; animating=false
    end

    local function OpenWin()
        if animating or visible then return end
        visible=true; animating=true; Main.Visible=true
        tw(Main,{BackgroundTransparency=0.15}); tw(MS,{Transparency=0.5})
        tw(Title,{TextTransparency=0}); tw(CloseBtn,{TextTransparency=0}); tw(Div,{BackgroundTransparency=0.85})
        TweenService:Create(GlobalBlur,smoothTw,{Size=14}):Play()
        for _,cd in pairs(Cards) do
            cd.Update()
            local c=cd.Frame; tw(c,{BackgroundTransparency=0.4})
            local s=c:FindFirstChildOfClass("UIStroke"); if s then tw(s,{Transparency=0.4}) end
            for _,e in ipairs(c:GetChildren()) do
                if e:IsA("TextLabel") then tw(e,{TextTransparency=0})
                elseif e:IsA("ImageLabel") then tw(e,{ImageTransparency=0,BackgroundTransparency=0}) end
            end
        end
        task.delay(0.45,updScroll); task.wait(0.4); animating=false
    end

    CloseBtn.MouseButton1Click:Connect(CloseWin)
    WD.Toggle = function() if visible then CloseWin() else OpenWin() end end
    return WD
end

local TargetListWin = CreateTargetListWindow(SilentAim.TargetedPlayers)

local GLeft  = Tabs.Main:AddLeftGroupbox("Silent Aim", "crosshair")
local GRight = Tabs.Main:AddRightGroupbox("Remote")

GLeft:AddToggle("SAEnabled", {
    Text="Enable Silent Aim", Default=false,
    Callback=function(v) SilentAim.Enabled=v end,
})
GLeft:AddDivider()
GLeft:AddDropdown("SAAimPart", {
    Values={"Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg"},
    Default="Head", Text="Aim Part",
    Callback=function(v) SilentAim.AimPart=v end,
})
GLeft:AddDivider()
GLeft:AddToggle("SAPred", {
    Text="Prediction", Default=false,
    Callback=function(v) SilentAim.UsePrediction=v end,
})
GLeft:AddSlider("SAPredAmt", {
    Text="Prediction Amount", Default=0, Min=0, Max=1, Rounding=2,
    Callback=function(v) SilentAim.PredictionAmount=v end,
})
GLeft:AddDivider()
GLeft:AddToggle("SAWallbang", {
    Text="Wallbang", Default=false,
    Callback=function(v) SilentAim.WallbangEnabled=v end,
})


-- Wallbang V2
local WallbangV2 = {
    Enabled = false,
    DropDistance = 15,
    FloatHold = true,
    Duration = 10,
    RestorePosition = true,
    Running = false,
    SavedCFrame = nil,
    FloatConnection = nil,
}

local function StopWallbangV2()
    if WallbangV2.FloatConnection then
        WallbangV2.FloatConnection:Disconnect()
        WallbangV2.FloatConnection = nil
    end

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

    -- Drop by the configured distance.
    hrp.CFrame = hrp.CFrame + Vector3.new(0, -WallbangV2.DropDistance, 0)

    -- Optional float hold.
    if WallbangV2.FloatHold then
        local floatY = hrp.Position.Y

        WallbangV2.FloatConnection = RunService.Heartbeat:Connect(function()
            if not WallbangV2.Running then return end

            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")

            if not root then
                StopWallbangV2()
                return
            end

            local pos = root.Position
            local rx, ry, rz = root.CFrame:ToOrientation()

            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(pos.X, floatY, pos.Z) * CFrame.Angles(rx, ry, rz)
        end)
    end

    task.delay(WallbangV2.Duration, function()
        if WallbangV2.Running then
            StopWallbangV2()
        end
    end)
end

local WallbangV2Group = Tabs.Main:AddLeftGroupbox("Wallbang V2", "move")

local WBV2Enabled = WallbangV2Group:AddToggle("WBV2Enabled", {
    Text = "Enabled",
    Default = false,
    Callback = function(v)
        WallbangV2.Enabled = v

        if v then
            StartWallbangV2()
        elseif WallbangV2.Running then
            StopWallbangV2()
        end
    end,
})

WBV2Enabled:AddKeyPicker("WBV2Keybind", {
    Default = "",
    NoUI = false,
    Text = "Keybind",
    Mode = "Toggle",
    Callback = function()
        WallbangV2.Enabled = not WallbangV2.Enabled
        if WallbangV2.Enabled then
            StartWallbangV2()
        elseif WallbangV2.Running then
            StopWallbangV2()
        end
    end,
})

WallbangV2Group:AddSlider("WBV2DropDistance", {
    Text = "Drop Distance",
    Default = 15,
    Min = 1,
    Max = 50,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(v)
        WallbangV2.DropDistance = v
    end,
})

WallbangV2Group:AddToggle("WBV2FloatHold", {
    Text = "Float Hold",
    Default = true,
    Callback = function(v)
        WallbangV2.FloatHold = v
    end,
})

WallbangV2Group:AddSlider("WBV2Duration", {
    Text = "Duration",
    Default = 10,
    Min = 1,
    Max = 60,
    Rounding = 0,
    Suffix = " seconds",
    Callback = function(v)
        WallbangV2.Duration = v
    end,
})

WallbangV2Group:AddToggle("WBV2RestorePosition", {
    Text = "Restore Position",
    Default = true,
    Callback = function(v)
        WallbangV2.RestorePosition = v
    end,
})

GRight:AddToggle("SAAutoFire", {
    Text="Enable Auto Fire", Default=false,
    Callback=function(v) SilentAim.AutoFireEnabled=v end,
})

local TListGroup = Tabs.Main:AddRightGroupbox("Target List")
TListGroup:AddToggle("SAUseList", {
    Text="Use Target List", Default=false,
    Callback=function(v) SilentAim.UseTargetList=v end,
})
TListGroup:AddButton({ Text="Open Target List", Func=function() TargetListWin:Toggle() end })

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddToggle("ShowCustomCursor", {
    Text="Custom Cursor", Default=true,
    Callback=function(v) Library.ShowCustomCursor=v end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values={"Left","Right"}, Default="Right", Text="Notification Side",
    Callback=function(v) Library:SetNotifySide(v) end,
})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
    Default="RightShift", NoUI=true, Text="Menu keybind",
})
MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("invertium")
SaveManager:SetFolder("invertium/configs")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

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
        and currentChar and currentHRP and CurrentGun and CurrentGunConfig
    then
        DirectFireSilentAim()
    end
end))

if LocalPlayer.Character then HookCharacter(LocalPlayer.Character) end
TC(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    HookCharacter(char)
end))

Library:Notify({
    Title       = "invertium",
    Description = "loaded — stay cold.",
    Time        = 3,
})
