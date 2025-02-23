package tessera

Layout_Context :: struct {
	viewport_width: f64,
	viewport_height: f64,
	scaling_factor_inv: f64,
}

Direction :: enum {
	ROW,
	ROW_REVERSE,
	COLUMN,
	COLUMN_REVERSE,
}

Main_Align :: enum {
	START,
	CENTER,
	END,
	SPACE_BETWEEN,
	SPACE_AROUND,
	SPACE_EVENLY,
}

Cross_Align :: enum {
	START,
	CENTER,
	END,
}

Dimension_Mode :: enum {
	AUTO,
}

Unit :: enum {
	PX,
	DPX,
	VW,
	VH,
	PRATIO,
}

Unit_Value :: struct {
	unit: Unit,
	value: f64,
}

Dimension :: union {Dimension_Mode, Unit_Value}

Box_Properties :: struct {
	main_size: Dimension,
	main_grow: u32,
	main_grow_limit: Unit_Value,
	cross_size: Dimension,
	items_direction: Direction,
	items_main_align: Main_Align,
	items_cross_align: Cross_Align,
	cross_align: Cross_Align,
}

Vector2 :: distinct [2]f64

Rectangle :: struct {
	anchor: Vector2,
	width: f64,
	height: f64,
}

Box_Computed :: struct {
	main_size_basis: f64,
	main_size: f64,
	main_grow_inverse: f64,
	main_grow_limit: f64,
	cross_size: f64,
	rectangle: Rectangle,
	depth: u32,
}

Box :: struct {
	computed: Box_Computed,
	children: []Box,
	properties: Box_Properties,
}

cmpf :: #force_inline proc(a: f64, $op: string, b: f64) -> bool {
	EPSILON :: 1e-15
	when op == "==" {
		return abs(a - b) < EPSILON
	} else when op == "!=" {
		return abs(a - b) > EPSILON
	} else when op == "<" {
		return (b - a) > EPSILON
	} else when op == "<=" {
		return ((b - a) > EPSILON) || (abs(a - b) < EPSILON)
	} else when op == ">" {
		return (a - b) > EPSILON
	} else when op == ">=" {
		return ((a - b) > EPSILON) || (abs(a - b) < EPSILON)
	} else {
		#panic("Unrecognized operator!")
	}
}

compute_unit_value :: proc(lc: ^Layout_Context, unit_value: Unit_Value, parent_size: f64) -> f64 {
	switch unit_value.unit {
	case .PX:
		return unit_value.value
	case .DPX:
		return unit_value.value * lc.scaling_factor_inv
	case .VW:
		return unit_value.value * lc.viewport_width
	case .VH:
		return unit_value.value * lc.viewport_height
	case .PRATIO:
		return unit_value.value * parent_size
	}
	return 0.0
}

is_row_direction :: proc(direction: Direction) -> bool {
	return direction == .ROW || direction == .ROW_REVERSE
}

is_column_direction :: proc(direction: Direction) -> bool {
	return direction == .COLUMN || direction == .COLUMN_REVERSE
}

balance_grow_boxes :: proc(grow_boxes: []^Box, total_space: f64, grow_sum: u32) {
	space_per_grow_unit := total_space / f64(grow_sum)

	growable_sum: u32
	growable_boxes := make([dynamic]^Box, 0, len(grow_boxes))
	defer delete(growable_boxes)

	shrinkable_sum: f64
	shrinkable_boxes := make([dynamic]^Box, 0, len(grow_boxes))
	defer delete(shrinkable_boxes)

	available_space: f64

	for &box in grow_boxes {
		space := f64(box.properties.main_grow) * space_per_grow_unit

		switch {
		case cmpf(space, "<", box.computed.main_size_basis):
			available_space = available_space - (box.computed.main_size_basis - space)
			box.computed.main_size = box.computed.main_size_basis
		case cmpf(space, ">", box.computed.main_grow_limit):
			available_space = available_space + (space - box.computed.main_grow_limit)
			box.computed.main_size = box.computed.main_grow_limit
		case:
			box.computed.main_size = space
		}

		if cmpf(space, ">", box.computed.main_size_basis) {
			shrinkable_sum += box.computed.main_grow_inverse
			append(&shrinkable_boxes, box)
		}
		if cmpf(space, "<", box.computed.main_grow_limit) {
			growable_sum += box.properties.main_grow
			append(&growable_boxes, box)
		}
	}

	space_changed := true
	for space_changed {
		space_changed = false

		if cmpf(available_space, ">", 0.0) {
			space_per_growable_unit := available_space / f64(growable_sum)
			for i := len(growable_boxes) - 1; i >= 0; i -= 1 {
				box := growable_boxes[i]
				grow_space := f64(box.properties.main_grow) * space_per_growable_unit
				max_grow_space := box.computed.main_grow_limit - box.computed.main_size
				if cmpf(grow_space, ">", max_grow_space) {
					grow_space = max_grow_space
					growable_sum = growable_sum - box.properties.main_grow
					unordered_remove(&growable_boxes, i)
				}
				if cmpf(grow_space, ">", 0.0) {
					box.computed.main_size = box.computed.main_size + grow_space
					available_space = available_space - grow_space
					space_changed = true
				}
			}
		}
		if cmpf(available_space, "<", 0.0) {
			space_per_shrinkable_unit := available_space / f64(shrinkable_sum)
			for i := len(shrinkable_boxes) - 1; i >= 0; i -= 1 {
				box := shrinkable_boxes[i]
				shrink_space := box.computed.main_grow_inverse * -(space_per_shrinkable_unit)
				max_shrink_space := -(box.computed.main_size_basis - box.computed.main_size)
				if cmpf(shrink_space, ">", max_shrink_space) {
					shrink_space = max_shrink_space
					shrinkable_sum = shrinkable_sum - box.computed.main_grow_inverse
					unordered_remove(&shrinkable_boxes, i)
				}
				if cmpf(shrink_space, ">", 0.0) {
					box.computed.main_size = box.computed.main_size - shrink_space
					available_space = available_space + shrink_space
					space_changed = true
				}
			}
		}
	}
}

compute_box :: proc(
	lc: ^Layout_Context,
	target_box: ^Box,
	reserved_width: f64,
	reserved_height: f64,
	depth: u32 = 0,
) -> Vector2 {
	props := target_box.properties
	target_box.computed.depth = depth

	main_mode, uses_main_mode := props.main_size.(Dimension_Mode)
	cross_mode, uses_cross_mode := props.cross_size.(Dimension_Mode)

	main_auto := uses_main_mode && main_mode == .AUTO
	cross_auto := uses_cross_mode && cross_mode == .AUTO

	reserved_main_space: f64

	grow_boxes: [dynamic]^Box
	grow_sum: u32

	for &c_box in target_box.children {
		c_main_mode, c_uses_main_mode := c_box.properties.main_size.(Dimension_Mode)
		c_cross_mode, c_uses_cross_mode := c_box.properties.cross_size.(Dimension_Mode)

		c_main_auto := c_uses_main_mode && c_main_mode == .AUTO
		c_cross_auto := c_uses_cross_mode && c_cross_mode == .AUTO

		c_reserved_width, c_reserved_height: f64

		if is_row_direction(props.items_direction) {
			if c_main_auto {
				c_reserved_width = 0.0
			} else {
				c_reserved_width = compute_unit_value(lc, c_box.properties.main_size.(Unit_Value), reserved_width)
				c_box.computed.main_size_basis = c_reserved_width
				c_box.computed.main_size = c_reserved_width
			}
			if c_cross_auto {
				c_reserved_height = 0.0
			} else {
				c_reserved_height = compute_unit_value(lc, c_box.properties.cross_size.(Unit_Value), reserved_height)
				c_box.computed.cross_size = c_reserved_height
			}
		} else {
			if c_main_auto {
				c_reserved_height = 0.0
			} else {
				c_reserved_height = compute_unit_value(lc, c_box.properties.main_size.(Unit_Value), reserved_height)
				c_box.computed.main_size_basis = c_reserved_height
				c_box.computed.main_size = c_reserved_height
			}
			if c_cross_auto {
				c_reserved_width = 0.0
			} else {
				c_reserved_width = compute_unit_value(lc, c_box.properties.cross_size.(Unit_Value), reserved_width)
				c_box.computed.cross_size = c_reserved_width
			}
		}

		if c_main_auto || c_cross_auto {
			c_size := compute_box(lc, &c_box, c_reserved_width, c_reserved_height, depth + 1)
			if is_row_direction(props.items_direction) {
				if c_main_auto {
					c_box.computed.main_size_basis = c_size.x
					c_box.computed.main_size = c_size.x
				}
				if c_cross_auto {
					c_box.computed.cross_size = c_size.y
				}
			} else {
				if c_main_auto {
					c_box.computed.main_size_basis = c_size.y
					c_box.computed.main_size = c_size.y
				}
				if c_cross_auto {
					c_box.computed.cross_size = c_size.x
				}
			}
		}

		c_box.computed.main_grow_inverse = 1.0 / f64(c_box.properties.main_grow)
		c_box.computed.main_grow_limit = compute_unit_value(
			lc, c_box.properties.main_grow_limit,
			reserved_width if is_row_direction(props.items_direction) else reserved_height,
		)

		if c_box.properties.main_grow == 0 {
			reserved_main_space += c_box.computed.main_size_basis
		} else {
			append(&grow_boxes, &c_box)
		}

		grow_sum += c_box.properties.main_grow
	}

	free_main_space: f64
	if is_row_direction(props.items_direction) {
		free_main_space = reserved_width - reserved_main_space
	} else {
		free_main_space = reserved_height - reserved_main_space
	}

	if cmpf(free_main_space, ">", 0.0) && grow_sum > 0 {
		balance_grow_boxes(grow_boxes[:], free_main_space, grow_sum)
	}
	delete(grow_boxes)

	width, height: f64

	for &c_box in target_box.children {
		c_width, c_height: f64

		if is_row_direction(props.items_direction) {
			c_width = c_box.computed.main_size
			c_height = c_box.computed.cross_size
		} else {
			c_width = c_box.computed.cross_size
			c_height = c_box.computed.main_size
		}

		compute_box(lc, &c_box, c_width, c_height, depth + 1)

		width += c_width
		height += c_height
	}

	if is_row_direction(props.items_direction) {
		if !main_auto {
			width = reserved_width
		}
		if !cross_auto {
			height = reserved_height
		}
	} else {
		if !main_auto {
			height = reserved_height
		}
		if !cross_auto {
			width = reserved_width
		}
	}

	return { width, height }
}
