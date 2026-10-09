-- Converts a fresh copy of Roblox's official "Racing" template into the Crash Island base.
-- Run once in Edit mode:  node tools/mcp.js lua Edit build/prepare_place.luau
-- Safe to re-run: every step checks before acting.
--
-- Keeps: the template's car (ReplicatedStorage.Car -> ServerStorage.Vehicles.StarterCar) with
-- all of its own scripts, SoundService.Audio (car audio listener), Lighting/Sky.
-- Removes: race track, race systems/UI, garage set dressing, the template's car spawner and
-- collision script (Crash Island's VehicleService and Collision replace them).

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local log = {}

local vehicles = ServerStorage:FindFirstChild("Vehicles")
if not vehicles then
	vehicles = Instance.new("Folder")
	vehicles.Name = "Vehicles"
	vehicles.Parent = ServerStorage
end

local car = ReplicatedStorage:FindFirstChild("Car")
if car then
	car.Name = "StarterCar"
	car.Parent = vehicles
	table.insert(log, "moved ReplicatedStorage.Car -> ServerStorage.Vehicles.StarterCar")
end

local REMOVE = {
	{ Workspace, "Garage" },
	{ Workspace, "VFX" },
	{ Workspace, "Palette" },
	{ Workspace, "Racetrack" },
	{ Workspace, "Exterior_Set_Dressing" },
	{ Workspace, "Spawners" },
	{ Workspace, "Race" },
	{ Workspace, "SpawnLocation" },
	{ ReplicatedStorage, "Client" },
	{ ReplicatedStorage, "Utility" },
	{ ReplicatedStorage, "Constants" },
	{ ServerScriptService, "CarSpawning" },
	{ ServerScriptService, "Collision" },
	{ ServerScriptService, "Racing" },
	{ StarterGui, "RaceGui" },
}
for _, item in REMOVE do
	local inst = item[1]:FindFirstChild(item[2])
	if inst then
		inst:Destroy()
		table.insert(log, "removed " .. item[1].Name .. "." .. item[2])
	end
end
-- The template's race remotes share the name of our runtime Remotes folder.
local oldRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if oldRemotes and oldRemotes:FindFirstChild("JoinRace") then
	oldRemotes:Destroy()
	table.insert(log, "removed ReplicatedStorage.Remotes (race remotes)")
end

-- The template re-skins natural materials as desert (e.g. Grass -> "Racing_Sand_Grass").
-- Remove those overrides so the island gets ordinary grass and sand.
local MaterialService = game:GetService("MaterialService")
local NATURAL = {
	[Enum.Material.Grass] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Salt] = true,
	[Enum.Material.Sandstone] = true,
	[Enum.Material.Snow] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Brick] = true,
	[Enum.Material.Marble] = true,
}
for _, variant in MaterialService:GetChildren() do
	if variant:IsA("MaterialVariant") and NATURAL[variant.BaseMaterial] then
		table.insert(log, "removed MaterialVariant " .. variant.Name)
		variant:Destroy()
	end
end
Workspace.Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(106, 168, 79))
Workspace.Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(226, 205, 150))

-- Collision groups (also registered at runtime by Collision.luau).
for _, name in { "Vehicle", "Character", "VehicleBlocker" } do
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end
for _, template in vehicles:GetChildren() do
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Vehicle"
		end
	end
end

-- Bright island afternoon with long view distance so activities are visible from HQ.
Lighting.ClockTime = 13.5
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then
	atmosphere.Density = 0.26
	atmosphere.Haze = 0.6
	atmosphere.Color = Color3.fromRGB(199, 220, 235)
	atmosphere.Decay = Color3.fromRGB(110, 140, 165)
end
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof.Enabled = false
end

Workspace.FallenPartsDestroyHeight = -300

return table.concat(log, "\n")
