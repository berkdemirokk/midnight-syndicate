class_name GraphicsPreset
extends Resource
## One graphics quality level. build() fills the values in code. Only Mobile-renderer features
## that docs/research/04-godot-mobile-rendering.md lists as supported are switched on here.

@export var id: String = "medium"
## Target 3D render scale. Applied only when scaling_confirmed_on_device is true (see effective_scale()).
@export_range(0.25, 1.0, 0.01) var scaling_3d_scale: float = 0.85
## scaling_3d_scale is "Not confirmed" for Mobile in the research file. It stays false until a
## measurement on a real iPhone sets it, as ARCHITECTURE.md requires for unconfirmed features.
@export var scaling_confirmed_on_device: bool = false
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_DISABLED
@export var glow_enabled: bool = true
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.6
@export var directional_shadow_size: int = 1024
@export_range(0.0, 1.0, 0.01) var particle_amount_scale: float = 0.7
## Soft directional shadow filter (RenderingServer.directional_soft_shadow_filter_set_quality).
@export var shadow_filter: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
## Post AA on the 3D pass. High keeps MSAA only: FXAA on top would just blur it.
@export var screen_space_aa: Viewport.ScreenSpaceAA = Viewport.SCREEN_SPACE_AA_DISABLED
## city_builder.gd builds the reflection probes at track load only when this is on.
@export var reflection_probes_enabled: bool = true
@export var rain_enabled: bool = true
## Requested dynamic resolution. Settings only enables it when scaling_confirmed_on_device is true.
@export var dynamic_resolution: bool = false
@export_range(0.25, 1.0, 0.01) var min_scaling_3d_scale: float = 0.55


static func build(preset_id: String) -> GraphicsPreset:
	var p := GraphicsPreset.new()
	p.id = preset_id
	match preset_id:
		"low":
			p.scaling_3d_scale = 0.67
			p.glow_intensity = 0.35
			p.particle_amount_scale = 0.4
			p.reflection_probes_enabled = false
			p.shadow_filter = RenderingServer.SHADOW_QUALITY_HARD
			p.rain_enabled = false
			p.dynamic_resolution = true
		"high":
			p.scaling_3d_scale = 1.0
			p.msaa_3d = Viewport.MSAA_2X
			p.glow_intensity = 0.8
			p.directional_shadow_size = 2048
			p.particle_amount_scale = 1.0
			p.shadow_filter = RenderingServer.SHADOW_QUALITY_SOFT_LOW
		_:
			# "medium" keeps the defaults above, plus FXAA: it had no AA and rails and cables crawl at speed.
			p.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	return p


## The 3D scale the renderer uses: the preset value on desktop or once confirmed on device, else 1.0.
func effective_scale() -> float:
	return scale_on(is_desktop())


## Same rule with the platform given: desktop (true) or a phone build (false).
func scale_on(desktop: bool) -> float:
	return scaling_3d_scale if (scaling_confirmed_on_device or desktop) else 1.0


## True for desktop builds. Phone builds wait for a device measurement before the preset scale applies.
static func is_desktop() -> bool:
	return not (OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"))
