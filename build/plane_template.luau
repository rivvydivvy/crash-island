-- Builds ServerStorage.Vehicles.StarterPlane: a placeholder-part prop plane.
-- Run in Edit mode:  node tools/mcp.js lua Edit build/plane_template.luau   (rebuilds from scratch)
--
-- Contract with VehicleService / PlaneController:
--   PrimaryPart "Body" carries FlightAttachment, FlightVelocity (LinearVelocity),
--   FlightGyro (AlignOrientation), ExitLocationAttachment and a DrivePrompt.
--   "DriverSeat" is the pilot seat. Parts tagged "Recolor" take the catalog colour.
--   Attribute GearHeight = distance from the Body centre down to the bottom of the wheels.

local ServerStorage = game:GetService("ServerStorage")

local vehicles = ServerStorage:WaitForChild("Vehicles")
local old = vehicles:FindFirstChild("StarterPlane")
if old then
	old:Destroy()
end

local plane = Instance.new("Model")
plane.Name = "StarterPlane"

local WHITE = Color3.fromRGB(240, 242, 245)
local DARK = Color3.fromRGB(45, 48, 55)

local function part(name: string, size: Vector3, cframe: CFrame, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = WHITE
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = plane
	return p
end

local body = part("Body", Vector3.new(5, 4, 18), CFrame.new(0, 0, 0), {
	CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.1),
})
body:AddTag("Recolor")

local pieces = {
	part("Nose", Vector3.new(4.4, 3.6, 3), CFrame.new(0, -0.1, -10.4)),
	part("Canopy", Vector3.new(3.6, 2, 5), CFrame.new(0, 2.6, -3.2), {
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = Color3.fromRGB(150, 200, 235),
		CanCollide = false,
	}),
	part("Wing", Vector3.new(30, 0.8, 6), CFrame.new(0, -0.4, -1)),
	part("Tailplane", Vector3.new(12, 0.6, 3.5), CFrame.new(0, 1.2, 8)),
	part("Fin", Vector3.new(0.6, 5, 4), CFrame.new(0, 4, 7.8)),
	part("Spinner", Vector3.new(1.8, 1.8, 1.8), CFrame.new(0, 0, -12.2), { Shape = Enum.PartType.Ball, Color = DARK }),
	part("Propeller", Vector3.new(0.5, 8, 0.6), CFrame.new(0, 0, -12.6), { Color = DARK, CanCollide = false }),
	part("WingStripeL", Vector3.new(4, 0.82, 6.02), CFrame.new(-13, -0.4, -1), { CanCollide = false }),
	part("WingStripeR", Vector3.new(4, 0.82, 6.02), CFrame.new(13, -0.4, -1), { CanCollide = false }),
}
for _, index in { 4, 5, 8, 9 } do -- Tailplane, Fin, wing-tip stripes
	pieces[index]:AddTag("Recolor")
end

-- Fixed landing gear: low-friction wheels, the flight controller does the "rolling".
local GEAR_HEIGHT = 4.7
local wheelPhysics = PhysicalProperties.new(0.7, 0.05, 0, 100, 1)
for _, spot in { Vector3.new(-4, 0, -1), Vector3.new(4, 0, -1), Vector3.new(0, 0, -8) } do
	table.insert(pieces, part("Strut", Vector3.new(0.5, 2.2, 0.5), CFrame.new(spot.X, -2.6, spot.Z), { Color = DARK, CanCollide = false }))
	table.insert(pieces, part("Wheel", Vector3.new(1.2, 2.6, 2.6), CFrame.new(spot.X, -3.4, spot.Z), {
		Shape = Enum.PartType.Cylinder,
		Color = DARK,
		CustomPhysicalProperties = wheelPhysics,
	}))
end

local seat = Instance.new("VehicleSeat")
seat.Name = "DriverSeat"
seat.Size = Vector3.new(2, 1, 2)
seat.CFrame = CFrame.new(0, 1.6, -3)
seat.Transparency = 1
seat.CanCollide = false
seat.MaxSpeed = 0
seat.Torque = 0
seat.TurnSpeed = 0
seat.HeadsUpDisplay = false
seat.Parent = plane
table.insert(pieces, seat)

for _, p in pieces do
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
end

local flight = Instance.new("Attachment")
flight.Name = "FlightAttachment"
flight.Parent = body

local exitLocation = Instance.new("Attachment")
exitLocation.Name = "ExitLocationAttachment"
exitLocation.Position = Vector3.new(-17, -GEAR_HEIGHT + 3, 0)
exitLocation.Parent = body

local velocity = Instance.new("LinearVelocity")
velocity.Name = "FlightVelocity"
velocity.Attachment0 = flight
velocity.RelativeTo = Enum.ActuatorRelativeTo.World
velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
velocity.MaxAxesForce = Vector3.zero
velocity.Enabled = false
velocity.Parent = body

local gyro = Instance.new("AlignOrientation")
gyro.Name = "FlightGyro"
gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
gyro.Attachment0 = flight
gyro.MaxTorque = 400000
gyro.Responsiveness = 12
gyro.Enabled = false
gyro.Parent = body

local promptAttachment = Instance.new("Attachment")
promptAttachment.Name = "DrivePromptAttachment"
promptAttachment.Position = Vector3.new(-4, 1, -2)
promptAttachment.Parent = body
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "DrivePrompt"
prompt.ActionText = "Fly"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 16
prompt.RequiresLineOfSight = false
prompt.Parent = promptAttachment

for _, d in plane:GetDescendants() do
	if d:IsA("BasePart") then
		d.CollisionGroup = "Vehicle"
	end
end

plane.PrimaryPart = body
plane.WorldPivot = body.CFrame
plane:SetAttribute("GearHeight", GEAR_HEIGHT)
plane.Parent = vehicles

return `built StarterPlane: {#plane:GetDescendants()} instances, body mass {body.Mass}`
