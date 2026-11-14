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
	# v0.4: 256x256 (was 128x192) — sharper facades on modern phones.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var s := 0.94 + v * 0.10
			img.set_pixel(x, y, Color(base.r * s, base.g * s, base.b * s))
	# Windows: 3 columns x 4 rows, dark glass, frames, shutters, AC boxes.
	var cols := 3
	var rows := 4
	for r in range(rows):
		for c in range(cols):
			var wx := 24 + c * 76
			var wy := 16 + r * 56
			# Frame + glass + highlight.
			_fill_rect(img, wx - 4, wy - 4, 48, 60, Color(0.25, 0.22, 0.20))
			_fill_rect(img, wx, wy, 40, 52, Color(0.12, 0.16, 0.22))
			_fill_rect(img, wx + 4, wy + 4, 14, 18, Color(0.45, 0.55, 0.65))
			# Cross mullion.
			_fill_rect(img, wx + 18, wy, 4, 52, Color(0.25, 0.22, 0.20))
			_fill_rect(img, wx, wy + 24, 40, 4, Color(0.25, 0.22, 0.20))
			# Side shutters on about half the windows.
			if rng.randf() < 0.5:
				var sc := Color(0.35, 0.45, 0.35) if rng.randf() < 0.5 else Color(0.45, 0.38, 0.28)
				_fill_rect(img, wx - 16, wy, 10, 52, sc)
				_fill_rect(img, wx + 46, wy, 10, 52, sc)
			# AC box under some windows.
			if rng.randf() < 0.35:
				_fill_rect(img, wx + 4, wy + 56, 32, 16, Color(0.70, 0.70, 0.68))
		# Balcony rail line on the second row.
		if r == 1:
			_fill_rect(img, 16, 16 + r * 56 + 68, 224, 6, Color(0.20, 0.18, 0.16))
			for bx in range(16, 240, 24):
				_fill_rect(img, bx, 16 + r * 56 + 68, 4, 16, Color(0.20, 0.18, 0.16))
	# Ground-floor door with frame + step.
	_fill_rect(img, 100, 228, 56, 28, Color(0.30, 0.22, 0.16))
	_fill_rect(img, 108, 232, 40, 24, Color(0.20, 0.15, 0.11))
	_fill_rect(img, 96, 252, 64, 4, Color(0.55, 0.50, 0.44))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Islamic geometric pattern (8-pointed stars, geometric only — no text,
## no calligraphy). Used on the mosque walls.
static func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, col)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

static func _draw_star(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	# 8-pointed star = two squares, one rotated 45 degrees.
	var pts: Array[Vector2i] = []
	for k in range(4):
		var a := TAU * float(k) / 4.0
		pts.append(Vector2i(cx + int(cos(a) * r), cy + int(sin(a) * r)))
	for k in range(4):
		_draw_line(img, pts[k].x, pts[k].y, pts[(k + 1) % 4].x, pts[(k + 1) % 4].y, col)
	var pts2: Array[Vector2i] = []
	for k in range(4):
		var a := TAU * float(k) / 4.0 + PI / 4.0
		pts2.append(Vector2i(cx + int(cos(a) * r), cy + int(sin(a) * r)))
	for k in range(4):
		_draw_line(img, pts2[k].x, pts2[k].y, pts2[(k + 1) % 4].x, pts2[(k + 1) % 4].y, col)
	_draw_line(img, cx - r, cy, cx + r, cy, col)
	_draw_line(img, cx, cy - r, cx, cy + r, col)

static func geometric_pattern_texture() -> ImageTexture:
	if _cache.has("geometric"):
		return _cache["geometric"]
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.36, 0.38))
	var gold := Color(0.88, 0.68, 0.28)
	var light := Color(0.92, 0.88, 0.78)
	# Border frame.
	_draw_line(img, 6, 6, 249, 6, gold)
	_draw_line(img, 6, 249, 249, 249, gold)
	_draw_line(img, 6, 6, 6, 249, gold)
	_draw_line(img, 249, 6, 249, 249, gold)
	_draw_line(img, 14, 14, 241, 14, light)
	_draw_line(img, 14, 241, 241, 241, light)
	_draw_line(img, 14, 14, 14, 241, light)
	_draw_line(img, 241, 14, 241, 241, light)
	# 3x3 grid of 8-pointed stars with diamond centres.
	for gy in range(3):
		for gx in range(3):
			var cx := 64 + gx * 64
			var cy := 64 + gy * 64
			_draw_star(img, cx, cy, 24, gold)
			_fill_rect(img, cx - 4, cy - 4, 8, 8, light)
	var tex := ImageTexture.create_from_image(img)
	_cache["geometric"] = tex
	return tex

static func geometric_material() -> StandardMaterial3D:
	if not _cache.has("mat_geometric"):
		_cache["mat_geometric"] = _material(geometric_pattern_texture(), Vector3(2, 1, 1), 0.9)
	return _cache["mat_geometric"]

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
