class_name NitroBar
extends RefCounted
## Round nitro button: a ring of SEGMENTS blocks that fill clockwise with the tank, a lightning mark in the middle.
## Each block fills on its own, so the tank reads at a glance. The fill glows while nitro is firing and pulses when the
## tank is full. Painted into the HUD's own canvas: the disc in the rect pass, the ring, glow and mark in the line pass.

const FULL_EPS: float = 0.999
const PULSE_HZ: float = 4.0
const SEGMENTS: int = 10  ## blocks around the ring
const SEG_GAP_RAD: float = 0.12  ## gap between two blocks, radians
const STEPS_PER_SEG: int = 6  ## chords per block
const VIOLET: Color = MSTheme.RED  ## the HUD accent (name kept from the release; STREET EMPIRE racing red)
const TRACK_RING_COL: Color = Color(0.17, 0.18, 0.2)  ## empty block: titanium 20 % over graphite, pre-blended
const GLOW_RING_COL: Color = Color(0.42, 0.13, 0.10)  ## red glow while firing, pre-blended
const BOLT_UNITS: Array[Vector2] = [Vector2(0.18, -0.55), Vector2(-0.22, 0.08), Vector2(0.04, 0.08),
	Vector2(-0.18, 0.55), Vector2(0.24, -0.06), Vector2(-0.02, -0.06)]  ## in units of the radius, from the centre

var radius_px: float = 50.0
var ring_px: float = 8.0
var amount: float = 0.0
var active: bool = false
var _pulse_t: float = 0.0


func set_state(value: float, firing: bool, t_s: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	active = firing
	_pulse_t = t_s


## Fill of each block, 0..1, for a tank at value v. Blocks fill in order, the last one part-filled.
static func segment_fills(v: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x: float = clampf(v, 0.0, 1.0) * float(count)
	for s: int in count:
		out.append(clampf(x - float(s), 0.0, 1.0))
	return out


func paint_rects(c: CanvasItem, centre: Vector2) -> void:
	c.draw_circle(centre, radius_px + ring_px, MSTheme.PLATE_BG)


## Each layer is one draw_multiline: empty blocks, the fill, the glow, the bolt (see SpeedGauge.ring_segments).
func paint_lines(c: CanvasItem, centre: Vector2) -> void:
	var a0: float = -PI * 0.5
	var span: float = TAU / float(SEGMENTS)
	var fills: PackedFloat32Array = segment_fills(amount, SEGMENTS)
	var track := PackedVector2Array()
	var fill := PackedVector2Array()
	for s: int in SEGMENTS:
		var a_from: float = a0 + span * float(s) + SEG_GAP_RAD * 0.5
		var a_to: float = a0 + span * float(s + 1) - SEG_GAP_RAD * 0.5
		track.append_array(SpeedGauge.ring_segments(centre, radius_px, a_from, a_to, STEPS_PER_SEG))
		if fills[s] > 0.0:
			fill.append_array(SpeedGauge.ring_segments(centre, radius_px, a_from, lerpf(a_from, a_to, fills[s]),
				STEPS_PER_SEG))
	c.draw_multiline(track, TRACK_RING_COL, ring_px, true)
	var col: Color = MSTheme.CYAN.lightened(0.35) if active else MSTheme.CYAN
	if amount >= FULL_EPS:
		col = MSTheme.tint(col, 0.6 + 0.4 * sin(_pulse_t * TAU * PULSE_HZ))
	if not fill.is_empty():
		if active:
			c.draw_multiline(fill, GLOW_RING_COL, ring_px + 8.0, true)
		c.draw_multiline(fill, col, ring_px, true)
	var bolt_col: Color = MSTheme.TEXT if amount > 0.0 else MSTheme.tint(MSTheme.TEXT, 0.35)
	var bolt := PackedVector2Array()
	for i: int in range(1, BOLT_UNITS.size()):
		bolt.append(centre + BOLT_UNITS[i - 1] * radius_px * 0.8)
		bolt.append(centre + BOLT_UNITS[i] * radius_px * 0.8)
	c.draw_multiline(bolt, bolt_col, 4.0, true)
