class_name BayFit
extends Resource
## Jedna zatoka na modul: jak duza i co w niej lezy na starcie.
##
## A bay has no kind (see `ModuleBay`), so there is nothing here saying
## what sort of machine belongs: only how big the hole is and what the
## ship leaves the yard with in it. Which means a preset can give a
## freighter four big holes and an interceptor one small one, which is
## the whole reason these moved out of `ship.tscn`.

## How much module fits, against `ModuleData.bulk`.
@export var size: float = 1.0

## What is in it when the ship is built, or null for an empty hole.
##
## Part of the preset because a preset is a ready ship rather than a
## chassis: the cell, the tank, the scanner and the drive are as much the
## ship as its engines are. A loaded save overwrites these afterwards,
## which is correct -- `SaveGame` restores what the pilot was actually
## carrying.
@export var installed: ModuleData = null

## Where the hole sits in the ship's own frame. Only the schematic and the
## centre-of-mass sum read it, but both of them read it.
@export var at: Vector2 = Vector2.ZERO
