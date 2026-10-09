--!strict
-- Collision groups:
--   Vehicle  <-> Vehicle         collide (crashing into friends is the point)
--   Vehicle  <-> Character       no collision (no running people over; no touch-to-sit)
--   Character<-> Character       no collision
--   VehicleBlocker <-> Vehicle   collide (protects the HQ plaza, airfield, garages)
--   VehicleBlocker <-> Character no collision (people walk straight through)

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Groups = Config.CollisionGroups

local Collision = {}

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

function Collision.setGroup(root: Instance, group: string)
	if root:IsA("BasePart") then
		root.CollisionGroup = group
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

local function onCharacterAdded(character: Model)
	Collision.setGroup(character, Groups.Character)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = Groups.Character
		end
	end)
end

function Collision.init()
	for _, name in Groups do
		register(name)
	end
	PhysicsService:CollisionGroupSetCollidable(Groups.Vehicle, Groups.Vehicle, true)
	PhysicsService:CollisionGroupSetCollidable(Groups.Vehicle, Groups.Character, false)
	PhysicsService:CollisionGroupSetCollidable(Groups.Character, Groups.Character, false)
	PhysicsService:CollisionGroupSetCollidable(Groups.VehicleBlocker, Groups.Vehicle, true)
	PhysicsService:CollisionGroupSetCollidable(Groups.VehicleBlocker, Groups.Character, false)

	local function onBlocker(inst: Instance)
		Collision.setGroup(inst, Groups.VehicleBlocker)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.VehicleBlocker):Connect(onBlocker)
	for _, inst in CollectionService:GetTagged(Config.Tags.VehicleBlocker) do
		onBlocker(inst)
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Collision
