extends RefCounted
## Fabrique les matériaux peints, avec un cache par couleur.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _cache := {}


static func toon(color: Color, brush: float = 0.22, outline: float = 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s" % [color.to_html(), brush, outline]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("brush_strength", brush)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("thickness", outline)
		m.next_pass = o
	_cache[key] = m
	return m


static func glow(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func flat(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
