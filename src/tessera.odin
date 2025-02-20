package tessera

EPSILON :: 1e-7

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
	is_at_basis: bool,
	is_at_limit: bool,
	cross_size: f64,
	rectangle: Rectangle,
	depth: u32,
}

Box :: struct {
	computed: Box_Computed,
	children: []Box,
	properties: Box_Properties,
}

compute_unit_value :: proc(unit_value: Unit_Value, parent_size: f64) -> f64 {
	switch unit_value.unit {
	case .PX:
		return unit_value.value
	case .DPX:
		return unit_value.value * context.scaling_factor_inv
	case .VW:
		return unit_value.value * context.viewport_width
	case .VH:
		return unit_value.value * context.viewport_height
	case .PRATIO:
		return unit_value.value * parent_size
	}
}

is_row_direction :: proc(direction: Direction) -> bool {
	return direction == .ROW || direction == .ROW_REVERSE
}

is_column_direction :: proc(direction: Direction) -> bool {
	return direction == .COLUMN || direction == .COLUMN_REVERSE
}

balance_grow_boxes :: proc(grow_boxes: []^Box, total_space: f64, grow_sum: u32) {
	space_per_grow_unit := total_space / f64(grow_sum)

	for &box in grow_boxes {
		box.computed.main_size = box.properties.main_grow * space_per_grow_unit
		box.computed.is_at_basis = false
		box.computed.is_at_limit = false
	}

	redistributable_space: float64
	remaining_grow_sum: u32

	for &box in grow_boxes {
		if box.computed.main_size > box.computed.main_grow_limit {
			redistributable_space += box.computed.main_size - box.computed.main_grow_limit
			box.computed.main_size = box.computed.main_grow_limit
			box.computed.is_at_limit = true
		} else if box.computed.main_size == box.computed.main_grow_limit {
			box.computed.is_at_limit = true
		} else {
			remaining_grow_sum += box.properties.main_grow
			box.computed.is_at_limit = false
		}
	}

	space_changed := true
	for space_changed {
		space_changed = false
		space_per_remaining_grow_unit := redistributable_space / f64(remaining_grow_sum)

		for &box in grow_boxes {
			if box.computed.is_at_limit {
				continue
			}
			growth_space := box.properties.main_grow * space_per_remaining_grow_unit
			if box.computed.main_size + growth_space >= box.computed.main_grow_limit {
				growth_space = box.computed_main_grow_limit - box.computed.main_size
				remaining_grow_sum -= box.properties.main_grow
				box.computed.is_at_limit = true
			}
			if growth_space > EPSILON {
				redistributable_space -= growth_space
				box.computed.main_size += growth_space
				space_changed = true
			}
		}
	}
}

compute_box :: proc(
	target_box: ^Box,
	reserved_width: f64,
	reserved_height: f64,
	depth: u32 = 0,
) -> Vector2 {
	props := target_box.properties
	target_box.computed.depth = depth

	main_mode, uses_main_mode := main_size.(Dimension_Mode)
	cross_mode, uses_cross_mode := cross_size.(Dimension_Mode)

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
				c_reserved_width = compute_unit_value(c_box.properties.main_size, reserved_width)
				c_box.computed.main_size_basis = c_reserved_width
				c_box.computed.main_size = c_reserved_width
			}
			if c_cross_auto {
				c_reserved_height = 0.0
			} else {
				c_reserved_height = compute_unit_value(c_box.properties.cross_size, reserved_height)
				c_box.computed.cross_size = c_reserved_height
			}
		} else {
			if c_main_auto {
				c_reserved_height = 0.0
			} else {
				c_reserved_height = compute_unit_value(c_box.properties.main_size, reserved_height)
				c_box.computed.main_size_basis = c_reserved_height
				c_box.computed.main_size = c_reserved_height
			}
			if c_cross_auto {
				c_reserved_width = 0.0
			} else {
				c_reserved_width = compute_unit_value(c_box.properties.cross_size, reserved_width)
				c_box.computed.cross_size = c_reserved_width
			}
		}

		if c_main_auto || c_main_cross {
			c_size := compute_box(&box, c_reserved_width, c_reserved_height, depth + 1)
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

		c_box.computed.main_grow_inverse = 1.0 / c_box.properties.main_grow
		c_box.computed.main_grow_limit = compute_unit_value(
			c_box.properties.main_grow_limit,
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

	if free_main_space > EPSILON && grow_sum > 0 {
		balance_grow_boxes(grow_boxes[:], free_main_space, grow_sum)
	}
	delete(grow_boxes)
}
