--!strict
-- Server entry point: boots every Crash Island service in order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Collision = require(script.Parent.Collision)
local VehicleService = require(script.Parent.VehicleService)

Workspace.Gravity = Config.World.Gravity
Net.createAll()
Collision.init()
VehicleService.init()
