extends Control

# ─── Constants ────────────────────────────────
const MAP_W := 70
const MAP_H := 36
const CELL_W := 12
const CELL_H := 18
const FOV_R  := 8

const WALL  := 0
const FLOOR := 1
const STAIR := 2

const C_BG        := Color(0.020, 0.020, 0.032)
const C_WALL      := Color(0.06, 0.10, 0.06)
const C_WALL_VIS  := Color(0.15, 0.35, 0.15)
const C_FLOOR     := Color(0.04, 0.05, 0.04)
const C_FLOOR_VIS := Color(0.07, 0.10, 0.07)
const C_STAIR     := Color(0.40, 0.22, 0.0)
const C_STAIR_VIS := Color(1.0,  0.60, 0.0)
const C_PLAYER    := Color(1.0,  1.0,  1.0)
const C_SAN_HI    := Color(0.0,  1.0,  0.27)
const C_SAN_MID   := Color(1.0,  1.0,  0.0)
const C_SAN_LO    := Color(1.0,  0.13, 0.0)

const ENEMY_COLORS: Dictionary = {
	"Deep One": Color(0.0,  1.0,  0.80),   # neon teal
	"Cultist":  Color(1.0,  0.13, 0.0),    # neon red
	"Lurker":   Color(0.80, 0.0,  1.0),    # neon purple
	"Watcher":  Color(1.0,  1.0,  0.0),    # neon yellow
	"Shoggoth": Color(0.0,  1.0,  0.27),   # neon green
}
const ITEM_COLORS: Dictionary = {
	"Laudanum":       Color(1.0,  0.0,  0.47),  # hot pink
	"Sanity Draught": Color(0.67, 0.0,  1.0),   # electric violet
	"Forbidden Tome": Color(0.0,  0.60, 1.0),   # electric blue
	"Eldritch Relic": Color(1.0,  0.53, 0.0),  # neon orange  (char: %)
	"Warding Sigil":  Color(0.0,  0.80, 1.0),  # electric cyan (char: #) — raises DEF

	"Elder Sign":     Color(0.67, 1.0,  0.67),  # pale neon green
}

const ENEMY_TEMPLATES: Array = [
	# atk/def balanced against player atk=3, def=1, hp=15
	# damage formula: max(0, atk - def + [-1,0,1])
	{name="Deep One", ch="d", hp=6,  atk=2, def=0, prox=0, sight=0,
	 lore="A fish-eyed thing regards you with ancient, lightless patience."},
	{name="Cultist",  ch="c", hp=5,  atk=2, def=0, prox=0, sight=0,
	 lore="He mutters syllables that leave bruises on the inside of your skull."},
	{name="Lurker",   ch="l", hp=5,  atk=2, def=0, prox=1, sight=1,
	 lore="It occupies a space slightly outside the one you are in."},
	{name="Watcher",  ch="W", hp=10, atk=3, def=1, prox=2, sight=2,
	 lore="An eyeless face turns toward you. Your nose bleeds."},
	{name="Shoggoth", ch="S", hp=14, atk=5, def=2, prox=3, sight=3,
	 lore="Iä! Iä! The protoplasmic mass pulses with a thousand borrowed eyes."},
]

const HALLUCINATIONS: Array = [
	"The walls breathe.",
	"Someone whispers your childhood name.",
	"The geometry here is wrong.",
	"Your shadow moves before you do.",
	"You taste copper. The lantern dims.",
	"For a moment you see through something else's eyes.",
]

const HELP_LINES: Array = [
	"WASD / ARROWS — move", "bump enemy   — attack",
	"G — pick up item",     "1-5 — use item",
	". — wait",             "",
	"Find the Elder Sign",  "(*) and escape.",
]

# ─── State ────────────────────────────────────
var map:      Array = []
var seen:     Array = []
var vis:      Array = []
var entities: Array = []
var items:    Array = []
var rooms:    Array = []
var player:   Dictionary = {}
var messages: Array = []
var turn:     int   = 0
var game_over: bool = false
var won:       bool = false

var font: Font
var sidebar_x: float
const SIDE_W := 400.0

# ─── Lifecycle ────────────────────────────────
func _ready() -> void:
	font = ThemeDB.fallback_font
	sidebar_x = MAP_W * CELL_W + 16.0
	custom_minimum_size = Vector2(sidebar_x + SIDE_W, MAP_H * CELL_H)
	new_game()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	_draw_map()
	_draw_items()
	_draw_entities()
	_draw_player()
	_draw_sidebar()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var ev := event as InputEventKey
	if game_over:
		if ev.keycode == KEY_R:
			new_game()
		return
	match ev.keycode:
		KEY_W, KEY_UP:    _try_move(0, -1)
		KEY_S, KEY_DOWN:  _try_move(0,  1)
		KEY_A, KEY_LEFT:  _try_move(-1, 0)
		KEY_D, KEY_RIGHT: _try_move( 1, 0)
		KEY_PERIOD:       _wait()
		KEY_G:            _pickup()
		KEY_U:            _use_item(0)
		KEY_1:            _use_item(0)
		KEY_2:            _use_item(1)
		KEY_3:            _use_item(2)
		KEY_4:            _use_item(3)
		KEY_5:            _use_item(4)

# ─── New game ─────────────────────────────────
func new_game() -> void:
	_build_map()
	var s: Dictionary = rooms[0]
	player = {
		x = s.x + s.w / 2,
		y = s.y + s.h / 2,
		hp = 15, max_hp = 15,
		sanity = 100, max_sanity = 100,
		atk = 3, def = 1,
		inv = [],
		kill_counts = {}
	}
	messages = []
	turn     = 0
	game_over = false
	won       = false
	_spawn_entities()
	_spawn_items()
	_compute_fov()
	_msg("The darkness swallows the stairs behind you.", "lore")
	_msg("Somewhere deeper, something opens its eyes.", "lore")
	queue_redraw()

# ─── Map generation ───────────────────────────
func _build_map() -> void:
	map   = []
	seen  = []
	vis   = []
	rooms = []
	for y in MAP_H:
		map.append([])
		seen.append([])
		vis.append([])
		for _x in MAP_W:
			map[y].append(WALL)
			seen[y].append(false)
			vis[y].append(false)

	for _attempt in 300:
		if rooms.size() >= 14:
			break
		var w: int = 4 + randi() % 8
		var h: int = 4 + randi() % 7
		var x: int = 1 + randi() % (MAP_W - w - 2)
		var y: int = 1 + randi() % (MAP_H - h - 2)

		var overlaps := false
		for q: Dictionary in rooms:
			if x < q.x + q.w + 1 and x + w + 1 > q.x \
			and y < q.y + q.h + 1 and y + h + 1 > q.y:
				overlaps = true
				break
		if overlaps:
			continue

		for ry in range(y, y + h):
			for rx in range(x, x + w):
				map[ry][rx] = FLOOR

		if rooms.size() > 0:
			var p: Dictionary = rooms[rooms.size() - 1]
			var cx1: int = p.x + p.w / 2
			var cy1: int = p.y + p.h / 2
			var cx2: int = x + w / 2
			var cy2: int = y + h / 2
			if randf() < 0.5:
				_h_line(cx1, cy1, cx2)
				_v_line(cx2, cy1, cy2)
			else:
				_v_line(cx1, cy1, cy2)
				_h_line(cx1, cy2, cx2)
		rooms.append({x = x, y = y, w = w, h = h})

	var last: Dictionary = rooms[rooms.size() - 1]
	var sx: int = last.x + last.w / 2
	var sy: int = last.y + last.h / 2
	map[sy][sx] = STAIR

func _h_line(x1: int, y: int, x2: int) -> void:
	var step: int = 1 if x2 >= x1 else -1
	var x: int = x1
	while x != x2 + step:
		if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
			if map[y][x] == WALL:
				map[y][x] = FLOOR
		x += step

func _v_line(x: int, y1: int, y2: int) -> void:
	var step: int = 1 if y2 >= y1 else -1
	var y: int = y1
	while y != y2 + step:
		if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
			if map[y][x] == WALL:
				map[y][x] = FLOOR
		y += step

# ─── Spawn ────────────────────────────────────
func _spawn_entities() -> void:
	entities = []
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var count: int = 1 + randi() % 2
		for _j in count:
			var t: Dictionary
			var attempts := 0
			while true:
				t = ENEMY_TEMPLATES[randi() % ENEMY_TEMPLATES.size()].duplicate()
				attempts += 1
				if t.name != "Shoggoth" or i >= 6 or attempts > 20:
					break
			var ex: int = r.x + 1 + randi() % (r.w - 2)
			var ey: int = r.y + 1 + randi() % (r.h - 2)
			if map[ey][ex] == FLOOR and _ent_at(ex, ey) == null:
				t.x      = ex
				t.y      = ey
				t.max_hp = t.hp
				t.id     = randi()
				t.fresh  = true   # true = player hasn't seen it yet this sighting
				entities.append(t)

func _spawn_items() -> void:
	items = []
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var is_last: bool = (i == rooms.size() - 1)
		if not is_last and randf() > 0.55:
			continue
		var tmpl: Dictionary
		if is_last:
			tmpl = {name = "Elder Sign", ch = "*", kind = "elder"}
		else:
			var pool: Array = [
				{name = "Laudanum",       ch = "!", kind = "elixir"},
				{name = "Sanity Draught", ch = "!", kind = "san"},
				{name = "Forbidden Tome", ch = "?", kind = "tome"},
				{name = "Eldritch Relic", ch = "%", kind = "relic"},
				{name = "Warding Sigil",  ch = "#", kind = "ward"},
			]
			tmpl = pool[randi() % pool.size()].duplicate()
		var ix: int = r.x + 1 + randi() % (r.w - 2)
		var iy: int = r.y + 1 + randi() % (r.h - 2)
		if map[iy][ix] == FLOOR and _item_at(ix, iy) == null:
			tmpl.x  = ix
			tmpl.y  = iy
			tmpl.id = randi()
			items.append(tmpl)

# ─── FOV ──────────────────────────────────────
func _compute_fov() -> void:
	for y in MAP_H:
		for x in MAP_W:
			vis[y][x] = false
	vis[player.y][player.x] = true
	seen[player.y][player.x] = true

	var inv_step: float = 1.0 / 0.42
	var max_steps: int  = int(FOV_R * inv_step)
	for deg in range(0, 360, 2):
		var rad: float = deg * PI / 180.0
		var dx: float  = cos(rad) * 0.42
		var dy: float  = sin(rad) * 0.42
		var fx: float  = float(player.x) + 0.5
		var fy: float  = float(player.y) + 0.5
		for _s in max_steps:
			var mx: int = int(fx)
			var my: int = int(fy)
			if mx < 0 or mx >= MAP_W or my < 0 or my >= MAP_H:
				break
			vis[my][mx]  = true
			seen[my][mx] = true
			if map[my][mx] == WALL:
				break
			fx += dx
			fy += dy

# ─── Drawing ──────────────────────────────────
func _draw_map() -> void:
	var san_ratio: float = float(player.sanity) / float(player.max_sanity)
	for y in MAP_H:
		for x in MAP_W:
			if not seen[y][x]:
				continue
			var v: bool = vis[y][x]
			var t: int  = map[y][x]
			var ch: String
			var col: Color
			match t:
				WALL:
					ch  = "#"
					col = C_WALL_VIS if v else C_WALL
				STAIR:
					ch  = ">"
					col = C_STAIR_VIS if v else C_STAIR
				_:
					ch  = "."
					col = C_FLOOR_VIS if v else C_FLOOR
			if v and san_ratio < 0.3 and randf() < 0.004:
				ch  = char(33 + randi() % 90)
				col = Color(0.60, 0.0, 0.20)
			_dc(x, y, ch, col)

func _draw_items() -> void:
	for it: Dictionary in items:
		if not vis[it.y][it.x]:
			continue
		_dc(it.x, it.y, it.ch, ITEM_COLORS.get(it.name, Color.WHITE))

func _draw_entities() -> void:
	var san_ratio: float = float(player.sanity) / float(player.max_sanity)
	for e: Dictionary in entities:
		if not vis[e.y][e.x]:
			continue
		var col: Color = ENEMY_COLORS.get(e.name, Color.WHITE)
		if san_ratio < 0.35 and randf() < 0.08:
			col = Color(1.0, 0.0, 0.0)
		_dc(e.x, e.y, e.ch, col)

func _draw_player() -> void:
	var san_ratio: float = float(player.sanity) / float(player.max_sanity)
	var col: Color = Color(1.0, 0.0, 0.0) if san_ratio < 0.25 else C_PLAYER
	_dc(player.x, player.y, "@", col)

func _dc(cx: int, cy: int, ch: String, col: Color) -> void:
	draw_char(font, Vector2(cx * CELL_W, cy * CELL_H + CELL_H - 3), ch, CELL_H - 2, col)

func _draw_sidebar() -> void:
	var sx: float  = sidebar_x
	var sw: float  = SIDE_W - 20.0   # usable sidebar width
	var lbl: Color = Color(0.35, 0.35, 0.35)
	var val: Color = Color(0.95, 0.95, 0.95)
	var lh: float  = 22.0
	var y: float   = 12.0
	var sep: Color = Color(0.12, 0.20, 0.12)

	# ── Stats ──────────────────────────────────
	_dt(sx,       y, "HP", lbl, 12);     _dt(sx + 40,  y, "%d / %d" % [player.hp, player.max_hp], val, 12);      y += lh
	_dt(sx,       y, "SANITY", lbl, 12); _dt(sx + 60,  y, str(player.sanity), val, 12);                           y += lh

	var san_pct: float = float(player.sanity) / float(player.max_sanity)
	draw_rect(Rect2(sx, y, sw, 6), Color(0.08, 0.08, 0.08))
	var bcol: Color = C_SAN_HI if san_pct > 0.6 else (C_SAN_MID if san_pct > 0.3 else C_SAN_LO)
	draw_rect(Rect2(sx, y, sw * san_pct, 6), bcol)
	y += 14.0

	_dt(sx, y, "DEPTH", lbl, 12);  _dt(sx + 55, y, "1", val, 12);       y += lh
	_dt(sx, y, "TURN",  lbl, 12);  _dt(sx + 55, y, str(turn), val, 12); y += lh + 4.0

	# ── Inventory ──────────────────────────────
	draw_line(Vector2(sx, y), Vector2(sx + sw, y), sep); y += 10.0
	_dt(sx, y, "CARRYING", lbl, 11); y += 18.0
	if player.inv.is_empty():
		_dt(sx + 8, y, "nothing", Color(0.20, 0.20, 0.20), 11); y += lh
	else:
		for i in player.inv.size():
			var it: Dictionary = player.inv[i]
			var ic: Color = ITEM_COLORS.get(it.name, val)
			_dt(sx + 8, y, "%d. %s" % [i + 1, it.name], ic, 12); y += lh
	y += 4.0

	# ── Messages ───────────────────────────────
	draw_line(Vector2(sx, y), Vector2(sx + sw, y), sep); y += 10.0
	var max_msgs := 8
	for i in mini(messages.size(), max_msgs):
		var m: Dictionary = messages[i]
		var mc: Color
		match m.kind:
			"danger": mc = Color(1.0,  0.27, 0.07)
			"lore":   mc = Color(0.27, 0.53, 0.87)
			"good":   mc = Color(0.13, 1.0,  0.40)
			_:        mc = Color(0.90, 0.90, 0.90) if i == 0 else Color(0.45, 0.45, 0.45)
		var line_h: float = _dt_wrap(sx + 8, y, m.text, mc, sw - 8.0, 11)
		y += line_h + 2.0
		if y > MAP_H * CELL_H - 80:
			break
	y += 4.0

	# ── Knowledge ──────────────────────────────
	if not player.kill_counts.is_empty():
		draw_line(Vector2(sx, y), Vector2(sx + sw, y), sep); y += 10.0
		_dt(sx, y, "KNOWLEDGE", lbl, 11); y += 18.0
		for ename: String in player.kill_counts:
			var k: int  = int(player.kill_counts[ename])
			var m: Dictionary = _mastery(ename)
			var bonus: String = ""
			if m.atk > 0: bonus += " ATK+%d" % m.atk
			if m.def > 0: bonus += " DEF+%d" % m.def
			var ec: Color = ENEMY_COLORS.get(ename, Color.WHITE)
			_dt(sx + 8, y, "%s ×%d%s" % [ename, k, bonus], ec, 11)
			y += 17.0
		y += 4.0

	# ── Controls ───────────────────────────────
	draw_line(Vector2(sx, y), Vector2(sx + sw, y), sep); y += 10.0
	var dim: Color = Color(0.22, 0.22, 0.22)
	var hi:  Color = Color(0.27, 0.60, 0.27)
	for line: String in HELP_LINES:
		var hc: Color = hi if (line.begins_with("(") or line.begins_with("Find")) else dim
		_dt(sx + 8, y, line, hc, 11); y += 17.0

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.027, 0.027, 0.059, 0.88))
		var mid_x: float = MAP_W * CELL_W * 0.5
		var mid_y: float = MAP_H * CELL_H * 0.5
		if won:
			_dtc(mid_x, mid_y - 40, "YOU ENDURE", Color(0.47, 0.80, 0.33), 22)
			_dtc(mid_x, mid_y,       "The Elder Sign burns the angles shut.",  Color(0.27, 0.40, 0.20))
			_dtc(mid_x, mid_y + 22,  "You surface into grey Arkham dawn,",    Color(0.27, 0.40, 0.20))
			_dtc(mid_x, mid_y + 44,  "clutching a truth you will spend",       Color(0.27, 0.40, 0.20))
			_dtc(mid_x, mid_y + 66,  "your life trying to forget.",            Color(0.27, 0.40, 0.20))
		else:
			var by_sanity: bool = player.sanity <= 0
			_dtc(mid_x, mid_y - 40, "YOU ARE LOST", Color(0.60, 0.13, 0.07), 22)
			if by_sanity:
				_dtc(mid_x, mid_y,      "You did not die.",                         Color(0.27, 0.13, 0.07))
				_dtc(mid_x, mid_y + 22, "You became something that no longer",      Color(0.27, 0.13, 0.07))
				_dtc(mid_x, mid_y + 44, "needs a name like death.",                 Color(0.27, 0.13, 0.07))
			else:
				_dtc(mid_x, mid_y,      "They find you three days later,",          Color(0.27, 0.13, 0.07))
				_dtc(mid_x, mid_y + 22, "cold and empty-eyed, smiling at nothing.", Color(0.27, 0.13, 0.07))
		_dtc(mid_x, mid_y + 100, "[ R — play again ]", Color(0.40, 0.40, 0.40))

func _dt(x: float, y: float, text: String, col: Color, sz: int = 13) -> void:
	draw_string(font, Vector2(x, y + sz), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _dtc(x: float, y: float, text: String, col: Color, sz: int = 13) -> void:
	draw_string(font, Vector2(x, y + sz), text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, col)

func _dt_wrap(x: float, y: float, text: String, col: Color, max_w: float, sz: int = 12) -> float:
	var char_w: float = sz * 0.60
	if text.length() * char_w <= max_w:
		_dt(x, y, text, col, sz)
		return sz + 2.0
	var words: Array = text.split(" ")
	var line: String = ""
	var ly: float    = y
	for word: String in words:
		var test: String = (line + " " + word).strip_edges()
		if test.length() * char_w > max_w and line != "":
			_dt(x, ly, line, col, sz)
			ly  += sz + 3.0
			line = word
		else:
			line = test
	if line != "":
		_dt(x, ly, line, col, sz)
	return ly - y + sz + 2.0

# ─── Actions ──────────────────────────────────
func _try_move(dx: int, dy: int) -> void:
	var nx: int = int(player.x) + dx
	var ny: int = int(player.y) + dy
	if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H:
		return
	var e = _ent_at(nx, ny)
	if e != null:
		_player_attack(e)
		_tick()
		return
	if map[ny][nx] == WALL:
		return
	player.x = nx
	player.y = ny
	_tick()

func _wait() -> void:
	_msg("You hold your breath.", "lore")
	_tick()

func _pickup() -> void:
	var it = _item_at(int(player.x), int(player.y))
	if it == null:
		_msg("Nothing here.")
		return
	if player.inv.size() >= 5:
		_msg("Your arms are full.")
		return
	player.inv.append(it.duplicate())
	var item_id = it.id
	items = items.filter(func(i: Dictionary) -> bool: return i.id != item_id)
	_msg("Taken: %s." % it.name, "good")
	_tick()

func _use_item(index: int) -> void:
	if index >= player.inv.size():
		_msg("Nothing in slot %d." % (index + 1))
		return
	var it: Dictionary = player.inv.pop_at(index)
	_msg("You use the %s." % it.name)
	_apply_item(it)
	_tick()

func _apply_item(it: Dictionary) -> void:
	match it.kind:
		"elixir":
			var h: int = 5 + randi() % 5
			player.hp = mini(int(player.max_hp), int(player.hp) + h)
			_msg("HP +%d." % h, "good")
		"san":
			var s: int = 15 + randi() % 10
			player.sanity = mini(int(player.max_sanity), int(player.sanity) + s)
			_msg("Your thoughts slow and clarify. Sanity +%d." % s, "good")
		"tome":
			player.atk = int(player.atk) + 1
			player.sanity = maxi(0, int(player.sanity) - 20)
			_msg("Your mind fractures. But now you understand. ATK +1, Sanity -20.", "danger")
			_sanity_check()
		"ward":
			player.def = int(player.def) + 1
			_msg("The sigil burns itself into your skin. DEF +1.", "good")
		"relic":
			if randf() < 0.5:
				player.hp = mini(int(player.max_hp), int(player.hp) + 5)
				_msg("The relic pulses with warmth. HP +5.", "good")
			else:
				player.sanity = maxi(0, int(player.sanity) - 15)
				_msg("The relic screams at frequencies felt in your teeth. Sanity -15.", "danger")
				_sanity_check()
		"elder":
			_msg("The Elder Sign blazes. The angles close. You are free.", "good")
			won       = true
			game_over = true

func _tick() -> void:
	turn += 1
	if not game_over:
		for e: Dictionary in entities:
			if vis[e.y][e.x]:
				# One-shot sight drain: only on first sighting, resets when out of FOV
				if e.fresh and int(e.sight) > 0:
					player.sanity = maxi(0, int(player.sanity) - int(e.sight))
					e.fresh = false
			else:
				e.fresh = true  # out of sight — will drain again next time seen
		_sanity_check()
		if not game_over:
			_enemy_turn()
	_compute_fov()
	queue_redraw()

# ─── Combat ───────────────────────────────────
func _roll(atk: int, def: int) -> int:
	return maxi(0, atk - def + randi() % 3 - 1)

func _mastery(enemy_name: String) -> Dictionary:
	var k: int = int(player.kill_counts.get(enemy_name, 0))
	return {atk = mini(k / 3, 3), def = mini(k / 5, 2)}

func _record_kill(enemy_name: String) -> void:
	var prev: int = int(player.kill_counts.get(enemy_name, 0))
	var next: int = prev + 1
	player.kill_counts[enemy_name] = next
	# Announce threshold crossings
	var m: Dictionary = _mastery(enemy_name)
	var prev_atk: int = mini(prev / 3, 3)
	var prev_def: int = mini(prev / 5, 2)
	if m.atk > prev_atk:
		_msg("You understand the %s better. ATK +%d vs them." % [enemy_name, m.atk], "good")
	elif m.def > prev_def:
		_msg("You read the %s's patterns. DEF +%d vs them." % [enemy_name, m.def], "good")

func _player_attack(e: Dictionary) -> void:
	var m: Dictionary = _mastery(e.name)
	var d: int = _roll(int(player.atk) + m.atk, int(e.def))
	e.hp = int(e.hp) - d
	_msg("You strike the %s for %d." % [e.name, d])
	if int(e.hp) <= 0:
		if randf() < 0.35:
			_msg(e.lore, "lore")
		else:
			_msg("The %s is destroyed." % e.name, "danger")
		if randf() < 0.35:
			_drop_loot(int(e.x), int(e.y))
		var eid = e.id
		entities = entities.filter(func(q: Dictionary) -> bool: return q.id != eid)
		_record_kill(e.name)
	else:
		var ed: int = _roll(int(e.atk), int(player.def) + m.def)
		player.hp = int(player.hp) - ed
		if ed > 0:
			_msg("The %s retaliates for %d." % [e.name, ed], "danger")
		if int(player.hp) <= 0:
			player.hp = 0
			_msg("You fall. The dark is absolute.", "danger")
			game_over = true

func _drop_loot(x: int, y: int) -> void:
	var pool: Array = [
		{name = "Laudanum",       ch = "!", kind = "elixir"},
		{name = "Sanity Draught", ch = "!", kind = "san"},
		{name = "Forbidden Tome", ch = "?", kind = "tome"},
		{name = "Warding Sigil",  ch = "#", kind = "ward"},
		{name = "Eldritch Relic", ch = "*", kind = "relic"},
	]
	var it: Dictionary = pool[randi() % pool.size()].duplicate()
	it.x  = x
	it.y  = y
	it.id = randi()
	items.append(it)

# ─── Enemy AI ─────────────────────────────────
func _enemy_turn() -> void:
	for e: Dictionary in entities:
		if not vis[e.y][e.x]:
			continue
		var dist: int = abs(int(e.x) - int(player.x)) + abs(int(e.y) - int(player.y))

		if int(e.prox) > 0 and dist <= 3:
			player.sanity = maxi(0, int(player.sanity) - int(e.prox))
			_sanity_check()
			if game_over:
				return

		if dist == 1:
			var d: int = _roll(int(e.atk), int(player.def))
			player.hp = int(player.hp) - d
			if d > 0:
				_msg("The %s tears at you for %d." % [e.name, d], "danger")
			if int(player.hp) <= 0:
				player.hp = 0
				game_over = true
				_msg("You are undone. The darkness takes you.", "danger")
				return
		elif dist < 12:
			var dx: int = sign(int(player.x) - int(e.x))
			var dy: int = sign(int(player.y) - int(e.y))
			var moves: Array[Vector2i] = []
			if dx != 0: moves.append(Vector2i(dx, 0))
			if dy != 0: moves.append(Vector2i(0, dy))
			if dx != 0 and dy != 0: moves.append(Vector2i(dx, dy))
			for mv: Vector2i in moves:
				var nx: int = int(e.x) + mv.x
				var ny: int = int(e.y) + mv.y
				if nx >= 0 and nx < MAP_W and ny >= 0 and ny < MAP_H \
				and map[ny][nx] != WALL \
				and _ent_at(nx, ny) == null \
				and not (nx == int(player.x) and ny == int(player.y)):
					e.x = nx
					e.y = ny
					break

# ─── Sanity ───────────────────────────────────
func _sanity_check() -> void:
	if int(player.sanity) <= 0:
		player.sanity = 0
		_msg("Your mind tears like wet paper. You are no longer alone in your skull.", "danger")
		game_over = true
	elif int(player.sanity) <= 25 and randf() < 0.35:
		_msg(HALLUCINATIONS[randi() % HALLUCINATIONS.size()], "lore")

# ─── Helpers ──────────────────────────────────
func _msg(text: String, kind: String = "normal") -> void:
	messages.push_front({text = text, kind = kind})
	if messages.size() > 24:
		messages.pop_back()

func _ent_at(x: int, y: int) -> Variant:
	for e: Dictionary in entities:
		if int(e.x) == x and int(e.y) == y:
			return e
	return null

func _item_at(x: int, y: int) -> Variant:
	for it: Dictionary in items:
		if int(it.x) == x and int(it.y) == y:
			return it
	return null
