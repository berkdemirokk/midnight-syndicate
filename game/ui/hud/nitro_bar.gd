class_name NitroBar
extends RefCounted
## Round nitro gauge: eight segments around the button, lit clockwise with the tank in racing red, and a bolt in the
## middle. The ring gets a red halo while nitro is firing, and the lit segments pulse when the tank is full.
## Painted into the HUD's own canvas: the disc in the rect pass, the segments, halo and bolt in the line pass.

const FULL_EPS: float = 0.999
const PULSE_HZ: float = 4.0
const SEGMENTS: int = 8
const GAP_RAD: float = 0.16  ## gap between two segments, in radians
const ARC_STEPS: int = 8  ## chords per segment
const BOLT_UNITS: Array[Vector2] = [Vector2(0.18, -0.55), Vector2(-0.22, 0.08), Vector2(0.04, 0.08),
	Vector2(-0.18, 0.55), Vector2(0.24, -0.06), Vector2(-0.02, -0.06)]  ## in units of the radius, from the centre
## Opaque pre-blends: an empty segment is titanium at 20 percent over graphite, the halo is racing red over graphite.
static var TRACK_SEG_COL: Color = MSTheme.GRAPHITE_3.lerp(MSTheme.TITANIUM, 0.2)
static var HALO_COL: Color = MSTheme.GRAPHITE_2.lerp(MSTheme.RED, 0.5)

var radius_px: float = 50.0
var ring_px: float = 8.0
var amount: float = 0.0
var active: bool = false
var _pulse_t: float = 0.0


func set_state(value: float, firing: bool, t_s: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	active = firing
	_pulse_t = t_s


func paint_rects(c: CanvasItem, centre: Vector2) -> void:
	c.draw_circle(centre, radius_px + ring_px, MSTheme.PLATE_BG)


## Each draw_multiline is one draw call: empty segments, lit segments (chords joined in one array), halo, bolt.
func paint_lines(c: CanvasItem, centre: Vector2) -> void:
	var step: float = TAU / float(SEGMENTS)
	var span: float = step - GAP_RAD
	var a0: float = -PI * 0.5
	var empty := PackedVector2Array()
	var lit := PackedVector2Array()
	for i: int in SEGMENTS:
		var start: float = a0 + step * float(i) + GAP_RAD * 0.5
		empty.append_array(SpeedGauge.ring_segments(centre, radius_px, start, start + span, ARC_STEPS))
		var f: float = clampf(amount * float(SEGMENTS) - float(i), 0.0, 1.0)
		if f > 0.0:
			lit.append_array(SpeedGauge.ring_segments(centre, radius_px, start, start + span * f, ARC_STEPS))
	c.draw_multiline(empty, TRACK_SEG_COL, ring_px, true)
	if not lit.is_empty():
		var col: Color = MSTheme.RED
		if amount >= FULL_EPS:
			col = MSTheme.tint(col, 0.6 + 0.4 * sin(_pulse_t * TAU * PULSE_HZ))
		c.draw_multiline(lit, col, ring_px, true)
	if active:
		c.draw_multiline(SpeedGauge.ring_segments(centre, radius_px + ring_px * 0.5 + 3.0, 0.0, TAU, 64),
			HALO_COL, 3.0, true)
	var bolt_col: Color = MSTheme.PEARL if amount > 0.0 else MSTheme.tint(MSTheme.PEARL, 0.35)
	var bolt := PackedVector2Array()
	for i: int in range(1, BOLT_UNITS.size()):
		bolt.append(centre + BOLT_UNITS[i - 1] * radius_px * 0.8)
		bolt.append(centre + BOLT_UNITS[i] * radius_px * 0.8)
	c.draw_multiline(bolt, bolt_col, 4.0, true)
