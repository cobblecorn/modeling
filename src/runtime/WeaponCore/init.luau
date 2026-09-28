--[[
	WeaponCore
	Shared runtime for the weapons pack. Every Tool carries its own copy, so a
	weapon works on its own: drop the Tool into StarterPack and play.

	  Rig         Motor6D grips, stow welds, holstered copies
	  Combat      melee hit windows, damage, blocking, team checks, kill tags
	  Projectile  server-simulated physics projectiles (arrows, bolts, knives)
	  Effects     sparks, flashes, explosions, joint pose tweens
	  Server      base object for a weapon's server Script
	  Client      base object for a weapon's LocalScript (input, animation, HUD)
]]

local WeaponCore = {
	Util = require(script.Util),
	Rig = require(script.Rig),
	Combat = require(script.Combat),
	Projectile = require(script.Projectile),
	Effects = require(script.Effects),
	Server = require(script.Server),
	Client = require(script.Client),
}

return WeaponCore
