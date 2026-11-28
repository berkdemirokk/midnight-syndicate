extends "res://tests/test_case.gd"
## Garage pictures (ShowroomSet.attach_garage) still load; the garage scene itself now builds the STREET EMPIRE studio.

const GARAGE: String = "res://ui/garage/garage.tscn"
const PICTURES: PackedStringArray = [
	"res://assets/world/garage_photo/garage_back_wall_day.jpg",
	"res://assets/world/garage_photo/garage_back_wall_night.jpg",
	"res://assets/world/garage_photo/garage_side_wall_day.jpg",
	"res://assets/world/garage_photo/garage_side_wall_night.jpg",
	"res://assets/world/garage_photo/garage_roof_day.jpg",
	"res://assets/world/garage_photo/garage_roof_night.jpg",
	"res://assets/world/garage_photo/garage_floor_concrete.jpg",
]


func test_pictures_load() -> void:
	for p: String in PICTURES:
		check(ResourceLoader.exists(p), "%s missing" % p)
		check(load(p) is Texture2D, "%s does not load as a texture" % p)


## STREET EMPIRE (2026-11-28): the garage moved from the photo-lined workshop to the studio set shared with the main
## menu (owner: the workshop garage looked amateur). The photo lining is no longer built; ShowroomSet.attach_garage and
## the pictures stay available for any scene that wants the workshop.
func test_garage_scene_instantiates_with_the_studio() -> void:
	var garage: Node3D = (load(GARAGE) as PackedScene).instantiate() as Node3D
	check(garage != null, "garage scene does not instantiate")
	add(garage)
	await frames(3)
	check(garage.find_children("Photo_*", "MeshInstance3D", true, false).is_empty(), "no workshop photo lining in the studio garage")
	check(garage.find_child("Floor", true, false) is MeshInstance3D, "studio floor built")
	check(garage.find_child("RedWash", true, false) is MeshInstance3D, "studio red wash built")
	await cleanup([garage])
