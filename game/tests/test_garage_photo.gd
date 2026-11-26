extends "res://tests/test_case.gd"
## Photo-textured garage (ShowroomSet.attach_garage): the generated pictures load, the garage scene still instantiates,
## and the room carries the photo lining (back, two sides, ceiling) with the concrete floor picture.

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


func test_garage_scene_instantiates_with_photo_lining() -> void:
	var garage: Node3D = (load(GARAGE) as PackedScene).instantiate() as Node3D
	check(garage != null, "garage scene does not instantiate")
	add(garage)
	await frames(3)
	for name: String in ["Photo_back_wall", "Photo_side_wall_R", "Photo_side_wall_L", "Photo_front_wall", "Photo_roof"]:
		check(garage.find_child(name, true, false) != null, "%s not built" % name)
	var panels: Array[Node] = garage.find_children("Photo_*", "MeshInstance3D", true, false)
	check(panels.size() == 5, "expected 5 photo panels, found %d" % panels.size())
	for n: Node in panels:
		var m: ShaderMaterial = (n as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
		check(m != null and m.get_shader_parameter("albedo_tex") is Texture2D, "%s has no day picture" % n.name)
		check(m != null and m.get_shader_parameter("night_tex") is Texture2D, "%s has no lamps-on picture" % n.name)
	await cleanup([garage])
