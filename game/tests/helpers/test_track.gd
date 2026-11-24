extends RefCounted
## Test helper: builds the flat test circuit (about 1.2 km) in code and returns a Track that is not yet in a tree.
## Two straights, a hairpin, a fast sweep and a chicane. Start on the straight heading -Z, grid behind it.
## No art: a flat ground from flat_world.gd and a closed RacingLine Path3D (last point repeats the first).
## Usage: const TestTrack = preload("res://tests/helpers/test_track.gd"); var track: Track = TestTrack.build()

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const SCALE: float = 0.8  ## shrinks the layout so the loop is about 1.2 km
const GRID_Y: float = 0.47  ## car origin height at rest
const GRID_COLUMN_X: float = 3.5  ## m, grid columns at -3.5 and +3.5
const GRID_FIRST_Z: float = 8.0  ## m behind the start line (positive Z is behind)
const GRID_ROW_SPACING: float = 9.0  ## m between grid rows
const GRID_COUNT: int = 8


## Control points in x and z, before SCALE. Point 0 is the start/finish line.
static func control_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.0, -250.0),
		Vector2(80.0, -350.0),
		Vector2(200.0, -390.0),
		Vector2(300.0, -370.0),
		Vector2(345.0, -310.0),  # hairpin apex
		Vector2(320.0, -270.0),
		Vector2(260.0, -260.0),
		Vector2(180.0, -250.0),
		Vector2(110.0, -200.0),  # chicane
		Vector2(150.0, -140.0),
		Vector2(110.0, -80.0),
		Vector2(110.0, 60.0),
		Vector2(40.0, 130.0),
		Vector2(0.0, 160.0),
	])


static func build() -> Track:
	var track := Track.new()
	track.name = "TestCircuit"
	track.add_child(FlatWorld.make_ground(0.0))
	var path := Path3D.new()
	path.name = "RacingLine"
	path.curve = _make_curve()
	track.add_child(path)
	var grid := Node3D.new()
	grid.name = "StartGrid"
	track.add_child(grid)
	for i: int in GRID_COUNT:
		var marker := Marker3D.new()
		marker.name = "Grid%d" % i
		var row: int = i / 2
		var x: float = -GRID_COLUMN_X if i % 2 == 0 else GRID_COLUMN_X
		marker.position = Vector3(x, GRID_Y, GRID_FIRST_Z + GRID_ROW_SPACING * float(row))
		grid.add_child(marker)
	return track


## Catmull-Rom handles through the control points, so the curve passes through every point.
static func _make_curve() -> Curve3D:
	var pts: PackedVector2Array = control_points()
	var n: int = pts.size()
	var curve := Curve3D.new()
	for i: int in n + 1:
		var k: int = i % n
		var prev: Vector2 = pts[(k - 1 + n) % n]
		var nxt: Vector2 = pts[(k + 1) % n]
		var handle: Vector3 = Vector3(nxt.x - prev.x, 0.0, nxt.y - prev.y) * (SCALE / 6.0)
		var p: Vector3 = Vector3(pts[k].x, 0.0, pts[k].y) * SCALE
		curve.add_point(p, -handle, handle)
	return curve
