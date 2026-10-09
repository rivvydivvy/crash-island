-- Builds the graybox Crash Island: terrain, loop road, HQ, car bay, stunt park, crash yard,
-- airfield and the (placeholder) garage neighbourhood.
-- Run in Edit mode:  node tools/mcp.js lua Edit build/map.luau
-- Rebuilds Workspace.Map, Workspace.Props and the terrain from scratch every run.
--
-- Coordinates: +X east, -Z north, ground surface at Y = 0. Island ~2800 x 2200 studs.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local terrain = Workspace.Terrain
for _, name in { "Map", "Props" } do
	local old = Workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
terrain:Clear()

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = Workspace
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = Workspace

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = map
	return f
end

local COLORS = {
	road = Color3.fromRGB(58, 60, 66),
	concrete = Color3.fromRGB(196, 196, 190),
	car = Color3.fromRGB(46, 160, 67),
	plane = Color3.fromRGB(33, 118, 214),
	stunt = Color3.fromRGB(255, 140, 26),
	crash = Color3.fromRGB(214, 59, 59),
	garage = Color3.fromRGB(140, 82, 214),
	hq = Color3.fromRGB(255, 196, 40),
	white = Color3.fromRGB(245, 245, 245),
	blocker = Color3.fromRGB(255, 200, 0),
}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Flat slab whose top surface sits at `top`.
local function slab(parent: Instance, name: string, center: Vector3, sizeX: number, sizeZ: number, top: number, props: { [string]: any }?): Part
	local thickness = 2
	return block(parent, name, Vector3.new(sizeX, thickness, sizeZ), CFrame.new(center.X, top - thickness / 2, center.Z), props)
end

local ROAD_TOP = 0.2
local function road(parent: Instance, a: Vector3, b: Vector3, width: number)
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = delta.Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, ROAD_TOP - 1, mid.Z), Vector3.new(b.X, ROAD_TOP - 1, b.Z))
	-- Extend by half the width so joints and corner segments overlap without gaps.
	return block(parent, "Road", Vector3.new(width, 2, length + width * 0.5), cf, {
		Material = Enum.Material.Asphalt,
		Color = COLORS.road,
	})
end

local function sign(parent: Instance, text: string, color: Color3, position: Vector3, facing: Vector3, size: Vector2, poleHeight: number?)
	local height = poleHeight or 8
	local model = Instance.new("Model")
	model.Name = "Sign_" .. text:gsub("%W", "")
	local boardCenter = position + Vector3.new(0, height + size.Y / 2, 0)
	local board = block(model, "Board", Vector3.new(size.X, size.Y, 1), CFrame.lookAt(boardCenter, boardCenter + facing), {
		Color = color,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.PixelsPerStud = 20
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = surface
		surface.Parent = board
	end
	for _, side in if height > 0 then { -1, 1 } else {} do
		local x = side * (size.X / 2 - 1)
		local polePos = (CFrame.lookAt(position, position + facing) * CFrame.new(x, height / 2, 0)).Position
		block(model, "Pole", Vector3.new(1, height, 1), CFrame.new(polePos), { Color = COLORS.white })
	end
	model.Parent = parent
	return model
end

-- Vehicle-only wall: characters walk through it (see Collision.luau).
local function blocker(parent: Instance, a: Vector3, b: Vector3, height: number)
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local mid = (a + b) / 2
	local p = block(parent, "VehicleBlocker", Vector3.new(1.5, height, delta.Magnitude), CFrame.lookAt(Vector3.new(mid.X, height / 2, mid.Z), Vector3.new(b.X, height / 2, b.Z)), {
		Color = COLORS.blocker,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CastShadow = false,
		CollisionGroup = "VehicleBlocker",
	})
	CollectionService:AddTag(p, "VehicleBlocker")
	return p
end

local function pad(parent: Instance, name: string, category: string, center: Vector3, size: Vector2, facing: Vector3, color: Color3)
	local top = 0.6
	local cf = CFrame.lookAt(Vector3.new(center.X, top - 0.5, center.Z), Vector3.new(center.X, top - 0.5, center.Z) + facing)
	local p = block(parent, name, Vector3.new(size.X, 1, size.Y), cf, {
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	p:SetAttribute("SpawnCategory", category)
	CollectionService:AddTag(p, "VehiclePad")
	-- Arrow showing which way the vehicle will face.
	block(parent, name .. "Arrow", Vector3.new(4, 0.2, size.Y * 0.5), cf * CFrame.new(0, 0.55, 0), {
		Color = COLORS.white,
		CanCollide = false,
		CanQuery = false,
	})
	return p
end

-- Ramp: a tilted slab whose low edge is flush with the ground at `start`, rising along `dir`.
local function ramp(parent: Instance, name: string, start: Vector3, dir: Vector3, width: number, length: number, angleDeg: number, color: Color3)
	local angle = math.rad(angleDeg)
	local thickness = 3
	local base = CFrame.lookAt(start, start + dir)
	local surfaceMid = base * CFrame.new(0, length * math.sin(angle) / 2 - 0.15, -length * math.cos(angle) / 2)
	local tilted = CFrame.new(surfaceMid.Position) * (base - base.Position) * CFrame.Angles(angle, 0, 0)
	local cf = tilted * CFrame.new(0, -thickness / 2, 0)
	block(parent, name, Vector3.new(width, thickness, length), cf, { Color = color, Material = Enum.Material.DiamondPlate })
	-- Solid support under the high end so the ramp reads as a structure.
	local topHeight = length * math.sin(angle)
	local runLength = length * math.cos(angle)
	-- Kept below the slab's underside so it never pokes through the driving surface.
	local supportHeight = topHeight - 4
	local supportCF = base * CFrame.new(0, supportHeight / 2, -runLength + 4)
	block(parent, name .. "Support", Vector3.new(width, supportHeight, 6), supportCF, { Color = COLORS.concrete, Material = Enum.Material.Concrete })
	return topHeight, runLength
end

local function target(parent: Instance, name: string, center: Vector3, radius: number)
	for i, ring in { { radius, COLORS.white }, { radius * 0.66, COLORS.crash }, { radius * 0.33, COLORS.white } } do
		block(parent, name .. "Ring" .. i, Vector3.new(0.2 + i * 0.02, ring[1] * 2, ring[1] * 2), CFrame.new(center.X, ROAD_TOP + 0.1 + i * 0.02, center.Z) * CFrame.Angles(0, 0, math.rad(90)), {
			Shape = Enum.PartType.Cylinder,
			Color = ring[2],
			CanCollide = false,
			CanQuery = false,
		})
	end
end

----------------------------------------------------------------------------------------------
-- Terrain: grass island with a sand beach in open water.
----------------------------------------------------------------------------------------------
local HX, HZ, R = 1400, 1100, 350
local function islandShape(material: Enum.Material, grow: number, top: number, depth: number)
	local cy = top - depth / 2
	terrain:FillBlock(CFrame.new(0, cy, 0), Vector3.new((HX + grow) * 2, depth, (HZ - R) * 2), material)
	terrain:FillBlock(CFrame.new(0, cy, 0), Vector3.new((HX - R) * 2, depth, (HZ + grow) * 2), material)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			terrain:FillCylinder(CFrame.new(sx * (HX - R), cy, sz * (HZ - R)), depth, R + grow, material)
		end
	end
end
terrain:FillBlock(CFrame.new(0, -10, 0), Vector3.new(5000, 16, 4400), Enum.Material.Water)
terrain:FillBlock(CFrame.new(0, -24, 0), Vector3.new(5000, 12, 4400), Enum.Material.Sand)
islandShape(Enum.Material.Sand, 80, 0, 16)
islandShape(Enum.Material.Grass, 0, 0, 20)

----------------------------------------------------------------------------------------------
-- Roads: loop road, main street (N-S), cross road (E-W).
----------------------------------------------------------------------------------------------
local roads = folder("Roads")
local LX, LZ, LR, LW = 850, 650, 220, 44
road(roads, Vector3.new(-(LX - LR), 0, -LZ), Vector3.new(LX - LR, 0, -LZ), LW)
road(roads, Vector3.new(-(LX - LR), 0, LZ), Vector3.new(LX - LR, 0, LZ), LW)
road(roads, Vector3.new(LX, 0, -(LZ - LR)), Vector3.new(LX, 0, LZ - LR), LW)
road(roads, Vector3.new(-LX, 0, -(LZ - LR)), Vector3.new(-LX, 0, LZ - LR), LW)
for _, sx in { -1, 1 } do
	for _, sz in { -1, 1 } do
		local center = Vector3.new(sx * (LX - LR), 0, sz * (LZ - LR))
		local startAngle = math.atan2(sz, sx) - math.pi / 4
		local segments = 10
		for i = 0, segments - 1 do
			local a0 = startAngle + (i / segments) * (math.pi / 2)
			local a1 = startAngle + ((i + 1) / segments) * (math.pi / 2)
			road(roads, center + Vector3.new(math.cos(a0), 0, math.sin(a0)) * LR, center + Vector3.new(math.cos(a1), 0, math.sin(a1)) * LR, LW)
		end
	end
end
road(roads, Vector3.new(0, 0, -LZ), Vector3.new(0, 0, LZ), LW) -- Main Street
road(roads, Vector3.new(-LX, 0, 0), Vector3.new(LX, 0, 0), LW) -- Cross Road

----------------------------------------------------------------------------------------------
-- HQ: protected pedestrian plaza, building, dealership kiosk, challenge board. Car bay east.
----------------------------------------------------------------------------------------------
local hq = folder("HQ")
local plazaMin, plazaMax = Vector3.new(-270, 0, 330), Vector3.new(-40, 0, 520)
local plazaCenter = (plazaMin + plazaMax) / 2
slab(hq, "Plaza", plazaCenter, plazaMax.X - plazaMin.X, plazaMax.Z - plazaMin.Z, 0.3, {
	Material = Enum.Material.Concrete,
	Color = COLORS.concrete,
})
local corners = {
	Vector3.new(plazaMin.X, 0, plazaMin.Z),
	Vector3.new(plazaMax.X, 0, plazaMin.Z),
	Vector3.new(plazaMax.X, 0, plazaMax.Z),
	Vector3.new(plazaMin.X, 0, plazaMax.Z),
}
for i = 1, 4 do
	blocker(hq, corners[i], corners[i % 4 + 1], 4)
end
block(hq, "HQBuilding", Vector3.new(150, 40, 40), CFrame.new(-155, 20, 300), { Material = Enum.Material.Concrete, Color = Color3.fromRGB(235, 232, 220) })
sign(hq, "CRASH ISLAND HQ", COLORS.hq, Vector3.new(-155, 40, 300), Vector3.new(0, 0, 1), Vector2.new(110, 18), 0)

local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "HqSpawn"
spawnLocation.Anchored = true
spawnLocation.Size = Vector3.new(14, 1, 14)
spawnLocation.CFrame = CFrame.new(-155, 0.5, 470)
spawnLocation.Duration = 2
spawnLocation.Neutral = true
spawnLocation.Color = COLORS.hq
spawnLocation.Material = Enum.Material.Neon
spawnLocation.Parent = hq
CollectionService:AddTag(spawnLocation, "HqSpawn")

local kiosk = block(hq, "DealershipKiosk", Vector3.new(10, 8, 4), CFrame.new(-90, 4.3, 430), { Color = COLORS.hq })
local promptAttachment = Instance.new("Attachment")
promptAttachment.Position = Vector3.new(0, 0, 3)
promptAttachment.Parent = kiosk
local dealerPrompt = Instance.new("ProximityPrompt")
dealerPrompt.ActionText = "Open Vehicles"
dealerPrompt.ObjectText = "Dealership"
dealerPrompt.HoldDuration = 0
dealerPrompt.RequiresLineOfSight = false
dealerPrompt.MaxActivationDistance = 14
dealerPrompt:SetAttribute("OpensVehicleMenu", true)
dealerPrompt.Parent = promptAttachment
sign(hq, "VEHICLES", COLORS.hq, Vector3.new(-90, 8.3, 430), Vector3.new(0, 0, 1), Vector2.new(16, 5), 0)
sign(hq, "CHALLENGES - COMING SOON", COLORS.stunt, Vector3.new(-220, 0, 400), Vector3.new(0, 0, 1), Vector2.new(34, 10), 4)

local carBay = folder("CarBay")
slab(carBay, "Lot", Vector3.new(90, 0, 440), 136, 170, ROAD_TOP, { Material = Enum.Material.Asphalt, Color = COLORS.road })
pad(carBay, "CarPad1", "car", Vector3.new(90, 0, 405), Vector2.new(18, 26), Vector3.new(0, 0, -1), COLORS.car)
pad(carBay, "CarPad2", "car", Vector3.new(90, 0, 475), Vector2.new(18, 26), Vector3.new(0, 0, -1), COLORS.car)
sign(carBay, "CAR BAY", COLORS.car, Vector3.new(140, 0, 440), Vector3.new(-1, 0, 0), Vector2.new(30, 9), 6)

----------------------------------------------------------------------------------------------
-- Stunt Park (north-east): two ramp lanes off the cross road with landing targets.
----------------------------------------------------------------------------------------------
local stunt = folder("StuntPark")
for _, lane in { { x = 380, name = "SmallLane" }, { x = 560, name = "LargeLane" } } do
	road(stunt, Vector3.new(lane.x, 0, -LW / 2), Vector3.new(lane.x, 0, -(LZ - LW / 2)), 50)
end
local smallTop, smallRun = ramp(stunt, "SmallRamp", Vector3.new(380, 0, -120), Vector3.new(0, 0, -1), 34, 40, 18, COLORS.stunt)
target(stunt, "SmallTarget", Vector3.new(380, 0, -120 - smallRun - 52), 24)
local largeTop, largeRun = ramp(stunt, "LargeRamp", Vector3.new(560, 0, -200), Vector3.new(0, 0, -1), 40, 70, 24, COLORS.stunt)
target(stunt, "LargeTarget", Vector3.new(560, 0, -200 - largeRun - 90), 42)
sign(stunt, "STUNT PARK", COLORS.stunt, Vector3.new(470, 0, -40), Vector3.new(0, 0, 1), Vector2.new(60, 16), 24)

----------------------------------------------------------------------------------------------
-- Crash Yard (north-west): crash lane into a wall, loose props to smash.
----------------------------------------------------------------------------------------------
local crash = folder("CrashYard")
road(crash, Vector3.new(-450, 0, -LW / 2), Vector3.new(-450, 0, -420), 60)
block(crash, "CrashWall", Vector3.new(90, 24, 8), CFrame.new(-450, 12, -428), { Material = Enum.Material.Concrete, Color = COLORS.concrete })
for i = -2, 2 do
	block(crash, "WallStripe", Vector3.new(8, 24.2, 8.2), CFrame.new(-450 + i * 18, 12, -428), { Color = COLORS.crash, Material = Enum.Material.SmoothPlastic })
end
sign(crash, "CRASH YARD", COLORS.crash, Vector3.new(-450, 0, -40), Vector3.new(0, 0, 1), Vector2.new(60, 16), 24)
-- Loose crates and barrels (unanchored props live outside Map so they never block pads).
local crateColor = Color3.fromRGB(176, 128, 72)
for row = 0, 2 do
	for col = 0, 3 - row do
		local crate = Instance.new("Part")
		crate.Name = "Crate"
		crate.Size = Vector3.new(6, 6, 6)
		crate.Material = Enum.Material.WoodPlanks
		crate.Color = crateColor
		crate.CFrame = CFrame.new(-470 + col * 6.2 + row * 3.1, 3.2 + row * 6.1, -300)
		crate.Parent = props
	end
end
for i = 0, 5 do
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(5, 3.5, 3.5)
	barrel.Color = COLORS.crash
	barrel.CFrame = CFrame.new(-430 + (i % 3) * 4, 2.7, -360 - math.floor(i / 3) * 4) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Parent = props
end

----------------------------------------------------------------------------------------------
-- Airfield (west coast): runway, apron with aircraft pad, hangar; fenced off from cars.
----------------------------------------------------------------------------------------------
local air = folder("Airfield")
slab(air, "Runway", Vector3.new(-1160, 0, 0), 110, 1640, ROAD_TOP, { Material = Enum.Material.Asphalt, Color = Color3.fromRGB(45, 47, 52) })
for z = -760, 760, 80 do
	block(air, "CenterLine", Vector3.new(2, 0.1, 40), CFrame.new(-1160, ROAD_TOP + 0.05, z), { Color = COLORS.white, CanCollide = false, CanQuery = false })
end
for _, z in { -800, 800 } do
	block(air, "Threshold", Vector3.new(100, 0.1, 6), CFrame.new(-1160, ROAD_TOP + 0.05, z), { Color = COLORS.white, CanCollide = false, CanQuery = false })
end
slab(air, "Apron", Vector3.new(-1022, 0, 130), 166, 470, ROAD_TOP + 0.05, { Material = Enum.Material.Concrete, Color = COLORS.concrete })
pad(air, "PlanePad1", "plane", Vector3.new(-1010, 0, 270), Vector2.new(40, 36), Vector3.new(0, 0, -1), COLORS.plane)
local hangar = Instance.new("Model")
hangar.Name = "Hangar"
block(hangar, "Back", Vector3.new(84, 30, 2), CFrame.new(-1010, 15, 440), { Color = COLORS.concrete, Material = Enum.Material.CorrodedMetal })
block(hangar, "SideW", Vector3.new(2, 30, 60), CFrame.new(-1052, 15, 410), { Color = COLORS.concrete, Material = Enum.Material.CorrodedMetal })
block(hangar, "SideE", Vector3.new(2, 30, 60), CFrame.new(-968, 15, 410), { Color = COLORS.concrete, Material = Enum.Material.CorrodedMetal })
block(hangar, "Roof", Vector3.new(86, 2, 62), CFrame.new(-1010, 31, 410), { Color = COLORS.plane, Material = Enum.Material.CorrodedMetal })
hangar.Parent = air
sign(air, "AIRFIELD", COLORS.plane, Vector3.new(-935, 0, 40), Vector3.new(1, 0, 0), Vector2.new(50, 14), 22)
blocker(air, Vector3.new(-905, 0, -1150), Vector3.new(-905, 0, 1150), 6)

----------------------------------------------------------------------------------------------
-- Garage neighbourhood (south-east, placeholder until Milestone 4).
----------------------------------------------------------------------------------------------
local garages = folder("Garages")
road(garages, Vector3.new(0, 0, LZ), Vector3.new(0, 0, 820), LW)
road(garages, Vector3.new(0, 0, 820), Vector3.new(860, 0, 820), 36)
for i = 0, 7 do
	slab(garages, "PlotPlaceholder" .. (i + 1), Vector3.new(130 + i * 95, 0, 905), 80, 110, 0.25, {
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(210, 200, 230),
	})
end
sign(garages, "GARAGES - COMING SOON", COLORS.garage, Vector3.new(60, 0, 790), Vector3.new(0, 0, -1), Vector2.new(50, 12), 10)

----------------------------------------------------------------------------------------------
-- Direction signs at the HQ junction.
----------------------------------------------------------------------------------------------
local signs = folder("Signs")
sign(signs, "^ STUNT PARK / CRASH YARD", COLORS.stunt, Vector3.new(-40, 0, 300), Vector3.new(0, 0, 1), Vector2.new(46, 7), 10)
sign(signs, "< AIRFIELD  (loop road west)", COLORS.plane, Vector3.new(-40, 0, 560), Vector3.new(0, 0, 1), Vector2.new(46, 7), 10)

----------------------------------------------------------------------------------------------
-- Terrain voxels are 4 studs, so the filled ground surface lands at Y = 2, not 0. Everything
-- above was laid out relative to Y = 0; lift it onto the real surface.
----------------------------------------------------------------------------------------------
local GROUND = 2
for _, root in { map, props } do
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame += Vector3.new(0, GROUND, 0)
		end
	end
end

return string.format(
	"map built: %d map parts, %d props; small ramp top %.1f, large ramp top %.1f",
	#map:GetDescendants(),
	#props:GetChildren(),
	smallTop,
	largeTop
)
