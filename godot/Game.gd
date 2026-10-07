extends Node2D

## Sunny Pasture is a hand-painted, fixed-layout sorting puzzle.
## Column arrays are stored bottom-to-top so the top run is always the last item.

const VIEW_SIZE := Vector2(540.0, 960.0)
const COLUMN_COUNT := 5
const ROW_COUNT := 6
const CELL_SIZE := 48.0
const COLUMN_WIDTH := 76.0
const COLUMN_STEP := 92.0
const BOARD_LEFT := 40.0
const BOARD_TOP := 245.0
const BOARD_BOTTOM := 574.0
const MAX_TEMP_SLOTS := 8

const COLORS := {
    "ink": Color("#613a25"),
    "muted": Color("#976c4a"),
    "cream": Color("#fff7e1"),
    "cream_2": Color("#f5dfad"),
    "sky": Color("#69ccef"),
    "sky_dark": Color("#3fa8d4"),
    "grass": Color("#83c95d"),
    "grass_dark": Color("#5a9f43"),
    "wood": Color("#d58d3b"),
    "wood_dark": Color("#aa6129"),
    "orange": Color("#ed8640"),
    "yellow": Color("#ffe980"),
    "white": Color("#fffdf5"),
}

const PIECE_COLORS := {
    "carrot": Color("#f47d36"),
    "hay": Color("#e7ad46"),
    "mushroom": Color("#e6503b"),
}

var columns: Array = [
    ["carrot", "hay", "mushroom"],
    ["mushroom", "carrot", "hay", "carrot"],
    ["hay", "mushroom", "carrot"],
    ["carrot", "mushroom", "hay", "mushroom"],
    ["hay", "carrot", "hay", "mushroom"],
]
var locked: Array = [false, false, false, false, false]
var selected_column := -1
var selected_temp := -1
var temporary: Array = [null, null]
var sheep_baskets := 0
var undo_stack: Array = []
var shuffle_used := false
var undo_used := false
var game_finished := false
var message := "点击一列，再点目标列"
var message_time := 0.0
var animation_time := 0.0
var sound_on := true
var font: Font

func _ready() -> void:
    font = ThemeDB.fallback_font
    get_viewport().size_changed.connect(queue_redraw)
    queue_redraw()

func _process(delta: float) -> void:
    animation_time += delta
    if message_time > 0.0:
        message_time -= delta
    queue_redraw()

func _input(event: InputEvent) -> void:
    var point := Vector2.ZERO
    var pressed := false
    if event is InputEventScreenTouch:
        point = event.position
        pressed = event.pressed
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        point = event.position
        pressed = event.pressed
    if not pressed:
        return
    if point.x < 0.0 or point.y < 0.0 or point.x > VIEW_SIZE.x or point.y > VIEW_SIZE.y:
        return
    if game_finished:
        if Rect2(120, 500, 140, 48).has_point(point):
            _reset_level()
        elif Rect2(280, 500, 140, 48).has_point(point):
            _reset_level()
        return
    if _column_at(point) >= 0:
        _handle_column(_column_at(point))
        return
    var temp_index := _temp_at(point)
    if temp_index >= 0:
        _handle_temp(temp_index)
        return
    if Rect2(32, 873, 220, 52).has_point(point):
        _use_shuffle()
        return
    if Rect2(268, 873, 220, 52).has_point(point):
        _use_undo()
        return
    if Rect2(409, 751, 91, 35).has_point(point):
        _add_temp_slot()
        return
    if Rect2(430, 46, 44, 44).has_point(point):
        sound_on = not sound_on
        _say("音效已" + ("开启" if sound_on else "关闭"))

func _column_at(point: Vector2) -> int:
    if point.y < BOARD_TOP - 10.0 or point.y > BOARD_BOTTOM + 10.0:
        return -1
    for index in range(COLUMN_COUNT):
        var rect := Rect2(BOARD_LEFT + index * COLUMN_STEP, BOARD_TOP - 8.0, COLUMN_WIDTH, BOARD_BOTTOM - BOARD_TOP + 20.0)
        if rect.has_point(point):
            return index
    return -1

func _temp_at(point: Vector2) -> int:
    for index in range(temporary.size()):
        var rect := Rect2(276.0 + index * 30.0, 755.0, 25.0, 38.0)
        if rect.has_point(point):
            return index
    return -1

func _top_type(index: int) -> String:
    if columns[index].is_empty():
        return ""
    return columns[index].back()

func _top_run(index: int) -> int:
    if columns[index].is_empty():
        return 0
    var type: String = _top_type(index)
    var count := 0
    for position in range(columns[index].size() - 1, -1, -1):
        if columns[index][position] != type:
            break
        count += 1
    return count

func _column_locked(index: int) -> bool:
    if columns[index].size() != ROW_COUNT:
        return false
    var first: String = columns[index][0]
    for type in columns[index]:
        if type != first:
            return false
    return true

func _update_locks() -> void:
    for index in range(COLUMN_COUNT):
        if not locked[index] and _column_locked(index):
            locked[index] = true
            _say("这一列整理完成啦")

func _handle_column(index: int) -> void:
    if locked[index]:
        _say("这一列已经锁定")
        return
    if selected_temp >= 0:
        _move_from_temp(selected_temp, index)
        return
    if selected_column < 0:
        if columns[index].is_empty():
            _say("空列可以作为周转位")
            return
        selected_column = index
        _say("已选第 %d 列 · 再点目标列" % (index + 1))
        return
    if selected_column == index:
        selected_column = -1
        _say("已取消选择")
        return
    _move_column(selected_column, index)

func _can_receive(type: String, target: int) -> bool:
    if target < 0 or target >= COLUMN_COUNT or locked[target]:
        return false
    if columns[target].size() >= ROW_COUNT:
        return false
    return columns[target].is_empty() or _top_type(target) == type

func _move_column(source: int, target: int) -> void:
    var type := _top_type(source)
    if not _can_receive(type, target):
        _say("只能放到空列或同样的棋子上")
        return
    var run := _top_run(source)
    var free: int = ROW_COUNT - columns[target].size()
    var moved: int = mini(run, free)
    if moved <= 0:
        return
    _save_state()
    for _i in range(moved):
        columns[target].append(columns[source].pop_back())
    selected_column = -1
    selected_temp = -1
    _update_locks()
    _say("%s移动成功" % _piece_name(type))
    _check_state()

func _handle_temp(index: int) -> void:
    if selected_column >= 0:
        if temporary[index] != null:
            _say("这个临时位已经有棋子了")
            return
        if columns[selected_column].is_empty():
            return
        _save_state()
        temporary[index] = columns[selected_column].pop_back()
        selected_column = -1
        _update_locks()
        _say("已放入临时位")
        _check_state()
        return
    if selected_temp == index:
        selected_temp = -1
        _say("已取消选择")
        return
    if temporary[index] == null:
        _say("空临时位")
        return
    selected_temp = index
    _say("已选临时棋子 · 再点目标列")

func _move_from_temp(slot: int, target: int) -> void:
    var type = temporary[slot]
    if type == null:
        return
    if not _can_receive(type, target):
        _say("只能放到空列或同样的棋子上")
        return
    _save_state()
    columns[target].append(type)
    temporary[slot] = null
    selected_temp = -1
    _update_locks()
    _say("临时棋子回到棋盘")
    _check_state()

func _save_state() -> void:
    var copied: Array = []
    for column in columns:
        copied.append(column.duplicate())
    undo_stack.append({"columns": copied, "locked": locked.duplicate(), "temporary": temporary.duplicate()})
    if undo_stack.size() > 30:
        undo_stack.pop_front()

func _use_undo() -> void:
    if undo_used or undo_stack.is_empty() or game_finished:
        _say("撤回道具暂时不可用")
        return
    var previous: Dictionary = undo_stack.pop_back()
    columns = previous["columns"]
    locked = previous["locked"]
    temporary = previous["temporary"]
    selected_column = -1
    selected_temp = -1
    undo_used = true
    _say("已经撤回一步")

func _add_temp_slot() -> void:
    if temporary.size() >= MAX_TEMP_SLOTS:
        _say("临时位已经达到 8 格")
        return
    temporary.append(null)
    _say("看广告后新增 1 个临时位")

func _use_shuffle() -> void:
    if shuffle_used or game_finished:
        _say("整理道具暂时不可用")
        return
    shuffle_used = true
    _save_state()
    for index in range(COLUMN_COUNT):
        if locked[index] or columns[index].size() < 2:
            continue
        var order: Array = []
        for type in columns[index]:
            if not order.has(type):
                order.append(type)
        var grouped: Array = []
        for type in order:
            for item in columns[index]:
                if item == type:
                    grouped.append(item)
        columns[index] = grouped
    _update_locks()
    _say("同类棋子已整理到一起")
    _check_state()

func _is_win() -> bool:
    for index in range(COLUMN_COUNT):
        if not columns[index].is_empty() and not locked[index]:
            return false
    for item in temporary:
        if item != null:
            return false
    return true

func _has_move() -> bool:
    for source in range(COLUMN_COUNT):
        if locked[source] or columns[source].is_empty():
            continue
        var type := _top_type(source)
        for target in range(COLUMN_COUNT):
            if source != target and _can_receive(type, target):
                return true
        for item in temporary:
            if item == null:
                return true
    for item in temporary:
        if item == null:
            continue
        for target in range(COLUMN_COUNT):
            if _can_receive(item, target):
                return true
    return false

func _check_state() -> void:
    if _is_win():
        game_finished = true
        _say("闯关成功！")
        return
    if not _has_move():
        game_finished = true
        _say("棋子卡住啦")

func _reset_level() -> void:
    columns = [
        ["carrot", "hay", "mushroom"],
        ["mushroom", "carrot", "hay", "carrot"],
        ["hay", "mushroom", "carrot"],
        ["carrot", "mushroom", "hay", "mushroom"],
        ["hay", "carrot", "hay", "mushroom"],
    ]
    locked = [false, false, false, false, false]
    selected_column = -1
    selected_temp = -1
    temporary = [null, null]
    sheep_baskets = 0
    undo_stack.clear()
    shuffle_used = false
    undo_used = false
    game_finished = false
    _say("点击一列，再点目标列")

func _say(text: String) -> void:
    message = text
    message_time = 2.4

func _piece_name(type: String) -> String:
    return {"carrot": "胡萝卜", "hay": "干草卷", "mushroom": "蘑菇"}.get(type, "棋子")

func _draw() -> void:
    _draw_background()
    _draw_header()
    _draw_board()
    _draw_sheep_zone()
    _draw_temp_zone()
    _draw_tools()
    if game_finished:
        _draw_finished_overlay()

func _style(color: Color, radius := 14, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.corner_radius_top_left = radius
    box.corner_radius_top_right = radius
    box.corner_radius_bottom_left = radius
    box.corner_radius_bottom_right = radius
    if border_width > 0:
        box.border_width_left = border_width
        box.border_width_top = border_width
        box.border_width_right = border_width
        box.border_width_bottom = border_width
        box.border_color = border
    return box

func _panel(rect: Rect2, color: Color, radius := 14, border := Color.TRANSPARENT, border_width := 0) -> void:
    draw_style_box(_style(color, radius, border, border_width), rect)

func _label(text: String, position: Vector2, size: int, color: Color = COLORS.ink, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
    draw_string(font, position, text, align, -1, size, color)

func _draw_background() -> void:
    draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("#83d9f3"))
    draw_rect(Rect2(0, 235, 540, 185), Color("#72cbed"))
    draw_rect(Rect2(0, 405, 540, 555), Color("#a5d76e"))
    # soft cloud groups
    _cloud(Vector2(55, 105), 1.0, 0.72)
    _cloud(Vector2(446, 174), 0.86, 0.58)
    _cloud(Vector2(315, 70), 0.5, 0.35)
    # rolling hills
    draw_colored_polygon(PackedVector2Array([Vector2(0, 253), Vector2(74, 202), Vector2(150, 248), Vector2(230, 190), Vector2(338, 253), Vector2(428, 209), Vector2(540, 253), Vector2(540, 420), Vector2(0, 420)]), Color("#9ccb79"))
    draw_colored_polygon(PackedVector2Array([Vector2(0, 295), Vector2(102, 245), Vector2(206, 294), Vector2(295, 229), Vector2(395, 286), Vector2(540, 238), Vector2(540, 425), Vector2(0, 425)]), Color("#b1d883"))
    # lake with little ripples
    draw_rect(Rect2(0, 315, 540, 120), Color("#72ccef"))
    for y in range(330, 430, 17):
        draw_line(Vector2(0, y), Vector2(540, y - 4), Color(1, 1, 1, 0.18), 2.0)
    # distant farm house
    draw_rect(Rect2(446, 250, 42, 34), Color("#e9a46c"))
    draw_colored_polygon(PackedVector2Array([Vector2(438, 251), Vector2(468, 225), Vector2(499, 251)]), Color("#d56e4f"))
    draw_rect(Rect2(460, 264, 10, 20), Color("#795040"))
    # grass field texture
    for x in range(7, 540, 31):
        draw_line(Vector2(x, 458 + (x % 21)), Vector2(x + 6, 450 + (x % 21)), Color(0.34, 0.60, 0.25, 0.35), 2.0)
    # wooden fence
    draw_line(Vector2(-20, 426), Vector2(560, 407), Color("#a96b37"), 7.0)
    draw_line(Vector2(-20, 447), Vector2(560, 428), Color("#bd7c3d"), 6.0)
    for x in range(-5, 570, 82):
        draw_rect(Rect2(x, 392 + (x % 19), 11, 73), Color("#b9763b"))
    # flowers
    for x in range(26, 540, 58):
        draw_circle(Vector2(x, 490 + (x % 24)), 4.2, Color("#fff9d9"))
        draw_circle(Vector2(x + 3, 489 + (x % 24)), 2.0, Color("#f0a34d"))

func _cloud(center: Vector2, scale: float, alpha: float) -> void:
    var color := Color(1, 1, 1, alpha)
    draw_circle(center + Vector2(-32, 5) * scale, 26 * scale, color)
    draw_circle(center + Vector2(0, -7) * scale, 34 * scale, color)
    draw_circle(center + Vector2(36, 5) * scale, 23 * scale, color)
    draw_rect(Rect2(center + Vector2(-50, 5) * scale, Vector2(100, 28) * scale), color)

func _draw_header() -> void:
    _panel(Rect2(18, 18, 250, 55), COLORS.cream, 18, Color("#d79c5e"), 2)
    draw_circle(Vector2(46, 46), 17, COLORS.grass_dark)
    draw_line(Vector2(40, 48), Vector2(53, 41), COLORS.cream, 3)
    _label("A / 晴空牧场", Vector2(69, 54), 23, COLORS.ink)
    _panel(Rect2(382, 23, 42, 42), COLORS.cream, 21, Color("#d79c5e"), 2)
    _label("⚙", Vector2(391, 53), 22, COLORS.wood_dark)
    _panel(Rect2(432, 23, 42, 42), COLORS.cream, 21, Color("#d79c5e"), 2)
    _label("···", Vector2(438, 50), 20, COLORS.wood_dark)
    _label("救救小羊", Vector2(28, 111), 19, COLORS.grass_dark)
    _label("初见 · 第 1 关", Vector2(28, 143), 28, COLORS.ink)
    _panel(Rect2(398, 94, 108, 49), COLORS.cream, 16, Color("#e1a25a"), 2)
    _draw_sheep(Vector2(423, 118), 0.42)
    _label("%d / 4" % sheep_baskets, Vector2(446, 125), 16, COLORS.ink)

func _draw_board() -> void:
    _panel(Rect2(17, 168, 506, 425), Color(0.30, 0.72, 0.89, 0.73), 24, Color(1, 1, 1, 0.72), 3)
    _panel(Rect2(183, 178, 174, 29), Color(0.21, 0.55, 0.70, 0.75), 14)
    _label("点击一列 · 再点目标列", Vector2(202, 198), 12, COLORS.white)
    for index in range(COLUMN_COUNT):
        var left := BOARD_LEFT + index * COLUMN_STEP
        var line_color := Color(1, 1, 1, 0.9) if selected_column != index else COLORS.yellow
        draw_line(Vector2(left, BOARD_TOP - 4), Vector2(left, BOARD_BOTTOM + 4), line_color, 3.0)
        draw_line(Vector2(left + COLUMN_WIDTH, BOARD_TOP - 4), Vector2(left + COLUMN_WIDTH, BOARD_BOTTOM + 4), line_color, 3.0)
        if locked[index]:
            draw_circle(Vector2(left + COLUMN_WIDTH / 2.0, BOARD_TOP - 13), 12, COLORS.orange)
            _label("✓", Vector2(left + COLUMN_WIDTH / 2.0 - 7, BOARD_TOP - 7), 15, COLORS.white)
        if selected_column >= 0 and selected_column != index and _can_receive(_top_type(selected_column), index):
            draw_rect(Rect2(left + 3, BOARD_BOTTOM - 5, COLUMN_WIDTH - 6, 5), Color(1, 0.91, 0.45, 0.75))
        for slot in range(ROW_COUNT):
            var slot_y := BOARD_BOTTOM - (slot + 1) * CELL_SIZE + 4
            if slot >= columns[index].size():
                draw_style_box(_style(Color(1, 1, 1, 0.10), 7, Color(1, 1, 1, 0.20), 1), Rect2(left + 8, slot_y, COLUMN_WIDTH - 16, CELL_SIZE - 5))
        var run_start: int = columns[index].size() - _top_run(index)
        for item_index in range(columns[index].size()):
            var y := BOARD_BOTTOM - (item_index + 1) * CELL_SIZE + 3
            var lifting: bool = selected_column == index and item_index >= run_start
            if lifting:
                y -= 8.0 + sin(animation_time * 5.0) * 2.0
            _draw_piece(columns[index][item_index], Rect2(left + 7, y, COLUMN_WIDTH - 14, CELL_SIZE - 5), lifting)
    _label("● 已选择", Vector2(30, 578), 11, COLORS.yellow)
    _label("○ 已锁定", Vector2(100, 578), 11, COLORS.white)
    _label("12 个空位", Vector2(434, 578), 11, COLORS.yellow)

func _draw_piece(type: String, rect: Rect2, lifted := false) -> void:
    var bg := Color("#fffdf0") if not lifted else Color("#fff9c9")
    _panel(rect, bg, 8, Color("#bd874c"), 2)
    draw_line(rect.position + Vector2(5, 7), rect.position + Vector2(rect.size.x - 5, 7), Color(1, 1, 1, 0.80), 1.0)
    match type:
        "carrot": _draw_carrot(rect.get_center())
        "hay": _draw_hay(rect.get_center())
        "mushroom": _draw_mushroom(rect.get_center())

func _draw_carrot(center: Vector2) -> void:
    draw_colored_polygon(PackedVector2Array([center + Vector2(-6, -6), center + Vector2(12, -13), center + Vector2(5, 15), center + Vector2(-9, 15)]), COLORS.orange)
    draw_colored_polygon(PackedVector2Array([center + Vector2(-7, -10), center + Vector2(-3, -22), center + Vector2(2, -11), center + Vector2(6, -22), center + Vector2(9, -7)]), COLORS.grass_dark)
    draw_line(center + Vector2(-2, -5), center + Vector2(5, 8), Color("#ffa658"), 2)

func _draw_hay(center: Vector2) -> void:
    _panel(Rect2(center - Vector2(20, 16), Vector2(40, 32)), Color("#eab34e"), 8, Color("#bd7a2e"), 2)
    for offset in [-12, -4, 4, 12]:
        draw_line(center + Vector2(offset, -13), center + Vector2(offset + 4, 13), Color("#f7d06f"), 2)
    draw_line(center + Vector2(-19, 0), center + Vector2(19, 0), Color("#c9862b"), 2)

func _draw_mushroom(center: Vector2) -> void:
    draw_rect(Rect2(center + Vector2(-7, 0), Vector2(14, 19)), Color("#f1c99c"))
    draw_arc(center + Vector2(0, 1), 22, PI, TAU, 20, Color("#d74736"), 2)
    draw_colored_polygon(PackedVector2Array([center + Vector2(-22, 2), center + Vector2(-13, -13), center + Vector2(0, -20), center + Vector2(15, -12), center + Vector2(22, 2)]), Color("#db4b38"))
    draw_circle(center + Vector2(-9, -10), 3, COLORS.white)
    draw_circle(center + Vector2(7, -14), 3, COLORS.white)
    draw_circle(center + Vector2(13, -4), 2.5, COLORS.white)

func _draw_sheep_zone() -> void:
    _panel(Rect2(17, 607, 506, 115), Color(1, 0.97, 0.86, 0.88), 20, Color(0.65, 0.44, 0.26, 0.20), 2)
    _label("小羊区", Vector2(32, 638), 18, COLORS.ink)
    _label("棋盘最上面的小羊，会自动回到这里", Vector2(32, 658), 11, COLORS.muted)
    for index in range(4):
        var center := Vector2(127 + index * 93, 693)
        _draw_basket(center, index < sheep_baskets)

func _draw_basket(center: Vector2, filled: bool) -> void:
    draw_arc(center + Vector2(0, -5), 31, PI, TAU, 20, COLORS.wood_dark, 3)
    draw_colored_polygon(PackedVector2Array([center + Vector2(-31, -4), center + Vector2(31, -4), center + Vector2(23, 23), center + Vector2(-23, 23)]), COLORS.wood)
    for offset in [-18, -7, 5, 16]:
        draw_line(center + Vector2(offset, -3), center + Vector2(offset + 4, 20), Color("#efa951"), 2)
    if filled:
        _draw_sheep(center + Vector2(0, -11), 0.55)

func _draw_sheep(center: Vector2, scale: float) -> void:
    draw_circle(center, 17 * scale, COLORS.white)
    draw_circle(center + Vector2(13, 2) * scale, 9 * scale, Color("#6b4430"))
    draw_circle(center + Vector2(18, -1) * scale, 2 * scale, COLORS.ink)
    draw_circle(center + Vector2(-10, -13) * scale, 7 * scale, COLORS.white)
    draw_circle(center + Vector2(3, -16) * scale, 7 * scale, COLORS.white)
    draw_line(center + Vector2(-8, 12) * scale, center + Vector2(-8, 19) * scale, COLORS.ink, 2)
    draw_line(center + Vector2(7, 12) * scale, center + Vector2(7, 19) * scale, COLORS.ink, 2)

func _draw_temp_zone() -> void:
    _panel(Rect2(17, 735, 506, 86), Color(1, 0.97, 0.87, 0.88), 20, Color(0.65, 0.44, 0.26, 0.20), 2)
    _label("临时空位", Vector2(32, 765), 18, COLORS.ink)
    _label("先放一下，再找同色列", Vector2(32, 785), 11, COLORS.muted)
    for index in range(MAX_TEMP_SLOTS):
        if index >= temporary.size():
            break
        var rect := Rect2(276 + index * 30, 755, 25, 38)
        _panel(rect, Color(1, 1, 1, 0.58), 6, Color(0.60, 0.40, 0.23, 0.32), 1)
        if temporary[index] != null:
            _draw_piece(str(temporary[index]), rect.grow(-2), selected_temp == index)
    _panel(Rect2(409, 751, 91, 35), Color("#fff1ba"), 10, Color("#e3a052"), 2)
    _label("▶ 看广告 +1", Vector2(419, 774), 11, COLORS.wood_dark)

func _draw_tools() -> void:
    _panel(Rect2(17, 834, 506, 103), Color(1, 0.97, 0.86, 0.78), 20, Color(0.65, 0.44, 0.26, 0.16), 2)
    _label("牧场道具", Vector2(32, 861), 18, COLORS.ink)
    _panel(Rect2(32, 873, 220, 52), Color("#ffe4aa"), 15, Color("#cf8137"), 2)
    _panel(Rect2(268, 873, 220, 52), Color("#ffe4aa"), 15, Color("#cf8137"), 2)
    _label("↝", Vector2(52, 910), 32, COLORS.wood_dark)
    _label("整理", Vector2(94, 901), 17, COLORS.ink)
    _label("广告可用", Vector2(94, 918), 10, COLORS.muted)
    _label("↶", Vector2(286, 910), 32, COLORS.wood_dark)
    _label("撤回", Vector2(328, 901), 17, COLORS.ink)
    _label("广告可用", Vector2(328, 918), 10, COLORS.muted)

func _draw_finished_overlay() -> void:
    draw_rect(Rect2(0, 0, 540, 960), Color(0.15, 0.23, 0.18, 0.47))
    _panel(Rect2(52, 310, 436, 270), COLORS.cream, 26, Color("#fff9dc"), 3)
    var success := _is_win()
    _label("🎉" if success else "😵", Vector2(245, 375), 48, COLORS.ink)
    _label("闯关成功！" if success else "棋子卡住啦", Vector2(160, 423), 27, COLORS.ink)
    _label("固定布局已经全部整理完成" if success else "顶部没有可以移动的位置", Vector2(132, 458), 14, COLORS.muted)
    _panel(Rect2(120, 500, 140, 48), COLORS.orange, 13, COLORS.wood_dark, 2)
    _panel(Rect2(280, 500, 140, 48), COLORS.cream_2, 13, Color("#d19a5c"), 2)
    _label("再玩一次", Vector2(155, 531), 16, COLORS.white if success else COLORS.ink)
    _label("继续", Vector2(331, 531), 16, COLORS.ink)
