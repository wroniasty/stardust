@tool
class_name StripClip
extends Resource
## Jedna animacja w arkuszu: ktory wiersz, ile klatek, jak szybko.
##
## Columns are frames and rows are animations, so a clip is mostly a
## name for a row. It exists as a resource rather than as a dictionary
## entry because the inspector shows an array of these as rows with
## fields, and because two of its four numbers mean "ask the strip" --
## which is a default worth stating once rather than at every reader.

## What the driver asks for: `play(&"firing")`.
@export var name: StringName = &""

## Which row of the sheet. Zero on a one-row file, which is every file
## that existed before clips did.
@export var row: int = 0

## How many of the row's columns this animation uses. Zero means all of
## them, which is what a sheet whose rows are the same length wants and
## saves repeating the number on every clip.
@export var frames: int = 0

## Frames per second at full drive, overriding the strip's `full_rate`.
## Zero means the strip's, which is the usual case: a part's animations
## mostly run at one speed.
@export var rate: float = 0.0

## Whether it wraps. False is what makes an **event** expressible: a
## muzzle flash has a beginning and an end and no "forty per cent
## fired", which is the one thing a continuous driver cannot say.
@export var loop: bool = true
