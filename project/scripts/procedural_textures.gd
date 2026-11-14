extends RefCounted
class_name ProceduralTextures
## Procedural textures for Phantom Ops v0.2 — no external assets.
## Everything is generated at runtime from seeded noise / drawing, so the
## APK stays small and the city is reproducible. Textures are cached in
## static vars so every building / road shares the same few materials
## (low draw-call / memory cost on mobile).

static var _cache: Dictionary = {}

static func _noise(seed_value: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.08
	return n

static func _speckle(img: Image, rng: RandomNumberGenerator, count: int, col_a: Color, col_b: Color) -> void:
	for i in range(count):
		var c: Color = col_a if rng.randf() < 0.5 else col_b
		img.set_pixel(rng.randi_range(0, img.get_width() - 1), rng.randi_range(0, img.get_height() - 1), c)

static func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	var x1: int = mini(x0 + w, img.get_width())
	var y1: int = mini(y0 + h, img.get_height())
	for y in range(maxi(y0, 0), y1):
		for x in range(maxi(x0, 0), x1):
			img.set_pixel(x, y, col)

static func asphalt_texture() -> ImageTexture:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var n := _noise(101)
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var base := 0.16 + v * 0.07
			img.set_pixel(x, y, Color(base, base, base + 0.008))
	_speckle(img, rng, 900, Color(0.22, 0.22, 0.22), Color(0.10, 0.10, 0.10))
	# Worn patches / cracks.
	for pi in range(6):
		_fill_rect(img, rng.randi_range(0, 220), rng.randi_range(0, 220), rng.randi_range(14, 36), rng.randi_range(8, 18), Color(0.11, 0.11, 0.11))
	var tex := ImageTexture.create_from_image(img)
	_cache["asphalt"] = tex
	return tex

static func sand_texture() -> ImageTexture:
	if _cache.has("sand"):
		return _cache["sand"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var n := _noise(202)
	n.frequency = 0.05
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			img.set_pixel(x, y, Color(0.80 + v * 0.10, 0.68 + v * 0.08, 0.48 + v * 0.06))
	_speckle(img, rng, 1200, Color(0.88, 0.78, 0.60), Color(0.70, 0.58, 0.40))
	var tex := ImageTexture.create_from_image(img)
	_cache["sand"] = tex
	return tex

static func sidewalk_texture() -> ImageTexture:
	if _cache.has("sidewalk"):
		return _cache["sidewalk"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.62, 0.58, 0.52))
	# 4x4 paving tiles with darker joints.
	for ty in range(4):
		for tx in range(4):
			var shade := 0.58 + rng.randf() * 0.10
			_fill_rect(img, tx * 32 + 1, ty * 32 + 1, 30, 30, Color(shade, shade * 0.94, shade * 0.86))
	_speckle(img, rng, 300, Color(0.70, 0.66, 0.60), Color(0.50, 0.47, 0.42))
	var tex := ImageTexture.create_from_image(img)
	_cache["sidewalk"] = tex
	return tex

static func plaza_texture() -> ImageTexture:
	if _cache.has("plaza"):
		return _cache["plaza"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.72, 0.55, 0.38))
	# Terracotta / sand checker tiles.
	for ty in range(8):
		for tx in range(8):
			var warm := (tx + ty) % 2 == 0
			var c := Color(0.78, 0.58, 0.38) if warm else Color(0.66, 0.55, 0.42)
			var shade := 0.94 + rng.randf() * 0.10
			_fill_rect(img, tx * 32 + 1, ty * 32 + 1, 30, 30, Color(c.r * shade, c.g * shade, c.b * shade))
	_speckle(img, rng, 500, Color(0.85, 0.68, 0.48), Color(0.55, 0.44, 0.32))
	var tex := ImageTexture.create_from_image(img)
	_cache["plaza"] = tex
	return tex

## Facade palettes: sand / white / ochre / terracotta. Each texture is a
## full building face: plaster + rows of windows, some with shutters,
## a ground-floor door. Index 0..3.
static func facade_texture(index: int) -> ImageTexture:
	var key := "facade_%d" % index
	if _cache.has(key):
		return _cache[key]
	var palettes: Array[Color] = [
		Color(0.82, 0.72, 0.55), Color(0.92, 0.89, 0.82),
		Color(0.78, 0.60, 0.36), Color(0.72, 0.45, 0.32),
	]
	var base: Color = palettes[clampi(index, 0, 3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + index * 17
	var n := _noise(500 + index * 17)
	var img := Image.create(128, 192, false, Image.FORMAT_RGBA8)
	for y in range(192):
		for x in range(128):
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var s := 0.94 + v * 0.10
			img.set_pixel(x, y, Color(base.r * s, base.g * s, base.b * s))
	# Windows: 3 columns x 4 rows, dark glass, frames, shutters, AC boxes.
	var cols := 3
	var rows := 4
	for r in range(rows):
		for c in range(cols):
			var wx := 12 + c * 38
			var wy := 14 + r * 42
			# Frame + glass + highlight.
			_fill_rect(img, wx - 2, wy - 2, 24, 30, Color(0.25, 0.22, 0.20))
			_fill_rect(img, wx, wy, 20, 26, Color(0.12, 0.16, 0.22))
			_fill_rect(img, wx + 2, wy + 2, 7, 9, Color(0.45, 0.55, 0.65))
			# Cross mullion.
			_fill_rect(img, wx + 9, wy, 2, 26, Color(0.25, 0.22, 0.20))
			_fill_rect(img, wx, wy + 12, 20, 2, Color(0.25, 0.22, 0.20))
			# Side shutters on about half the windows.
			if rng.randf() < 0.5:
				var sc := Color(0.35, 0.45, 0.35) if rng.randf() < 0.5 else Color(0.45, 0.38, 0.28)
				_fill_rect(img, wx - 8, wy, 5, 26, sc)
				_fill_rect(img, wx + 23, wy, 5, 26, sc)
			# AC box under some windows.
			if rng.randf() < 0.35:
				_fill_rect(img, wx + 2, wy + 28, 16, 8, Color(0.70, 0.70, 0.68))
		# Balcony rail line on the second row.
		if r == 1:
			_fill_rect(img, 8, 14 + r * 42 + 34, 112, 3, Color(0.20, 0.18, 0.16))
			for bx in range(8, 120, 12):
				_fill_rect(img, bx, 14 + r * 42 + 34, 2, 8, Color(0.20, 0.18, 0.16))
	# Ground-floor door with frame + step.
	_fill_rect(img, 50, 166, 28, 26, Color(0.30, 0.22, 0.16))
	_fill_rect(img, 54, 170, 20, 22, Color(0.20, 0.15, 0.11))
	_fill_rect(img, 48, 190, 32, 2, Color(0.55, 0.50, 0.44))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _material(tex: ImageTexture, uv_scale: Vector3, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_scale = uv_scale
	return m

static func asphalt_material() -> StandardMaterial3D:
	if not _cache.has("mat_asphalt"):
		_cache["mat_asphalt"] = _material(asphalt_texture(), Vector3(1, 1, 1))
	return _cache["mat_asphalt"]

static func sand_material() -> StandardMaterial3D:
	if not _cache.has("mat_sand"):
		_cache["mat_sand"] = _material(sand_texture(), Vector3(28, 28, 1))
	return _cache["mat_sand"]

static func sidewalk_material() -> StandardMaterial3D:
	if not _cache.has("mat_sidewalk"):
		_cache["mat_sidewalk"] = _material(sidewalk_texture(), Vector3(6, 6, 1))
	return _cache["mat_sidewalk"]

static func plaza_material() -> StandardMaterial3D:
	if not _cache.has("mat_plaza"):
		_cache["mat_plaza"] = _material(plaza_texture(), Vector3(4, 4, 1))
	return _cache["mat_plaza"]

static func facade_material(index: int) -> StandardMaterial3D:
	var key := "mat_facade_%d" % index
	if not _cache.has(key):
		_cache[key] = _material(facade_texture(index), Vector3(1, 1, 1), 0.95)
	return _cache[key]

static func flat_material(col: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m
