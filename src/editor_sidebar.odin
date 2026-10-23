package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"

import collider "raytracer/collider"
import rl "vendor:raylib"

// Sidebar layout: rows are label-left, control-right.
SIDEBAR_PAD :: 16
SIDEBAR_ROW_H :: 26
SIDEBAR_ROW_GAP :: 8
SIDEBAR_LABEL_W :: 92
SIDEBAR_INNER :: EDITOR_SIDEBAR_WIDTH - SIDEBAR_PAD*2

editor_gui_section :: proc(y: ^f32, title: cstring) {
	w := f32(SIDEBAR_INNER)
	rl.DrawRectangle(SIDEBAR_PAD, c.int(y^), SIDEBAR_INNER, 26, PANEL_SECTION_BG)
	rl.DrawRectangleLinesEx({f32(SIDEBAR_PAD), y^, w, 26}, 1, PANEL_BORDER)
	editor_text(SIDEBAR_PAD+10, c.int(y^)+7, title, 14, ACCENT)
	y^ += 38
}

editor_gui_slider :: proc(
	y: f32,
	label: cstring,
	value: ^f32,
	min_value, max_value: f32,
) -> bool {
	before := value^
	editor_text(SIDEBAR_PAD+2, c.int(y)+7, label, 14, TEXT_MUTED)
	slider_x := f32(SIDEBAR_PAD + SIDEBAR_LABEL_W)
	slider_w := f32(SIDEBAR_INNER - SIDEBAR_LABEL_W - 58)
	rl.DrawRectangle(c.int(slider_x), c.int(y)+9, c.int(slider_w), 4, CONTROL_BASE)
	_ = rl.GuiSlider(
		{slider_x, y+3, slider_w, 16},
		nil,
		nil,
		value,
		min_value,
		max_value,
	)
	value_text := fmt.ctprintf("%.0f", value^) if value^ == math.round(value^) && abs(value^) < 10000 else fmt.ctprintf("%.2f", value^)
	editor_text(c.int(slider_x+slider_w+8), c.int(y)+4, value_text, 14, TEXT_PRIMARY)
	return before != value^
}

editor_gui_stat :: proc(y: f32, label: cstring, value: cstring) {
	editor_text(SIDEBAR_PAD+2, c.int(y)+4, label, 14, TEXT_MUTED)
	editor_text(SIDEBAR_PAD+SIDEBAR_LABEL_W, c.int(y)+4, value, 14, TEXT_PRIMARY)
}

editor_gui_camera :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 78
	pos := [3]f32{f32(state.params.position.x), f32(state.params.position.y), f32(state.params.position.z)}
	look := [3]f32{f32(state.params.look_at.x), f32(state.params.look_at.y), f32(state.params.look_at.z)}

	editor_gui_section(&y, "CAMERA")
	for i in 0..<3 {
		labels := [3]cstring{"pos x", "pos y", "pos z"}
		limit := max(f32(25), abs(pos[i])*2)
		if editor_gui_slider(y, labels[i], &pos[i], -limit, limit) {
			state.params.position[i] = f64(pos[i])
			action.camera_changed = true
		}
		y += SIDEBAR_ROW_H + SIDEBAR_ROW_GAP
	}
	for i in 0..<3 {
		labels := [3]cstring{"look x", "look y", "look z"}
		limit := max(f32(25), abs(look[i])*2)
		if editor_gui_slider(y, labels[i], &look[i], -limit, limit) {
			state.params.look_at[i] = f64(look[i])
			action.camera_changed = true
		}
		y += SIDEBAR_ROW_H + SIDEBAR_ROW_GAP
	}
	vfov := f32(state.params.vfov)
	if editor_gui_slider(y, "vfov", &vfov, 1, 120) {
		state.params.vfov = f64(vfov)
		action.camera_changed = true
	}
	y += 34
	defocus := f32(state.params.defocus_angle)
	if editor_gui_slider(y, "defocus", &defocus, 0, 10) {
		state.params.defocus_angle = f64(defocus)
		action.camera_changed = true
	}
	y += 34
	focus := f32(state.params.focus_dist)
	if editor_gui_slider(y, "focus", &focus, 0.1, 30) {
		state.params.focus_dist = f64(focus)
		action.camera_changed = true
	}
	y += 42

	editor_gui_section(&y, "QUALITY")
	samples := f32(state.params.samples)
	if editor_gui_slider(y, "samples", &samples, 1, 500) {
		state.params.samples = int(samples)
		action.camera_changed = true
	}
	y += 34
	depth := f32(state.params.max_depth)
	if editor_gui_slider(y, "depth", &depth, 1, 50) {
		state.params.max_depth = int(depth)
		action.camera_changed = true
	}
	y += 42

	editor_gui_section(&y, "OUTPUT")
	width := f32(state.loaded.render.width)
	if editor_gui_slider(y, "width", &width, 64, 4000) {
		state.loaded.render.width = math.round(f64(width))
		action.render_settings_changed = true
	}
	y += 34
	ratio := f32(state.loaded.render.ratio)
	if editor_gui_slider(y, "aspect", &ratio, 0.5, 3) {
		state.loaded.render.ratio = f64(ratio)
		action.render_settings_changed = true
	}
	y += 34
	upscale := f32(state.loaded.render.upscale)
	if editor_gui_slider(y, "upscale", &upscale, 1, 16) {
		state.loaded.render.upscale = f64(upscale)
		action.render_settings_changed = true
	}
	y += 34
	threads := f32(state.loaded.render.threads)
	if editor_gui_slider(y, "threads", &threads, 1, 64) {
		state.loaded.render.threads = max(1, int(math.round(threads)))
	}
	y += 30
	editor_gui_stat(y, "format", "RGBA8 (fixed)")
	y += 38
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 30}, fmt.ctprintf("accelerator: %v", collider.grouping_kind(state.world.space.grouping))) {
		action.toggle_grouping = true
	}
	y += 42
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 32}, "reset preview") {
		action.reset_view = true
	}
	y += 42
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 32}, "capture preview camera") {
		action.capture_view = true
	}
	return
}

editor_gui_render :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 78
	editor_gui_section(&y, "RENDER")
	y += 36
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 36}, "raytrace render  (ENTER)") {
		action.render = true
	}
	y += 48
	if state.has_render {
		editor_gui_stat(y, "last render", fmt.ctprintf("%.2f ms", state.render_ms))
		y += 36
		if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER/2-4), 30}, "view render") {
			action.show_render = true
		}
		if rl.GuiButton({SIDEBAR_PAD+SIDEBAR_INNER/2+4, y, f32(SIDEBAR_INNER/2-4), 30}, "view preview") {
			action.show_preview = true
		}
	} else {
		_ = rl.GuiLabel({SIDEBAR_PAD, y+3, 320, 24}, "no render yet")
	}
	y += 46

	editor_gui_section(&y, "BOUNDS")
	bounds_label: cstring = "hide bounding boxes" if state.show_bounds else "show bounding boxes"
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 30}, bounds_label) {
		action.toggle_bounds = true
	}
	if state.show_bounds {
		stats := editor_bvh_stats(state)
		if stats.nodes > 0 {
			y += 40
			depth := f32(state.bounds_depth)
			max_depth := max(stats.height-1, 0)
			if max_depth > 0 && editor_gui_slider(y, "tree depth", &depth, 0, f32(max_depth)) {
				state.bounds_depth = clamp(int(math.round(depth)), 0, max_depth)
				editor_clear_bvh_inspection(state)
			}
			y += 32
			editor_gui_stat(y, "ray boxes", fmt.ctprintf("%d", len(state.debug_hit_nodes)))
			y += 26
			editor_gui_stat(y, "selected", fmt.ctprintf("%d", len(state.debug_object_ids)))
			y += 26
			if state.debug_selected_active {
				editor_gui_stat(y, "node depth", fmt.ctprintf("%d", state.debug_selected_depth))
				y += 26
				editor_text(
					SIDEBAR_PAD+2,
					c.int(y)+4,
					fmt.ctprintf("ids: %v", state.debug_object_ids[:]),
					14,
					TEXT_MUTED,
				)
				y += 26
			}
		}
	}
	y += 44

	editor_gui_section(&y, "SHORTCUTS")
	editor_gui_stat(y, "ENTER", "raytrace")
	y += 24
	editor_gui_stat(y, "BACKSPACE", "preview")
	y += 24
	editor_gui_stat(y, "LMB", "fly camera")
	y += 24
	editor_gui_stat(y, "RMB", "inspect BVH")
	y += 24
	editor_gui_stat(y, "G", "grouping")
	y += 24
	editor_gui_stat(y, "ESC", "release mouse")
	return
}

editor_gui_stats :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 78
	editor_gui_section(&y, "RUNTIME")
	editor_gui_stat(y, "fps", fmt.ctprintf("%d", rl.GetFPS()))
	y += 26
	editor_gui_stat(y, "frame", fmt.ctprintf("%.2f ms", rl.GetFrameTime()*1000))
	y += 26
	editor_gui_stat(y, "threads", fmt.ctprintf("%d", os.get_processor_core_count()))
	y += 26
	editor_gui_stat(y, "accelerator", fmt.ctprintf("%v", collider.grouping_kind(state.world.space.grouping)))
	y += 26
	editor_gui_stat(y, "spheres", fmt.ctprintf("%d", len(state.world.space.spheres)))
	y += 26
	editor_gui_stat(y, "quads", fmt.ctprintf("%d", len(state.world.space.quads)))
	y += 26
	editor_gui_stat(y, "image", fmt.ctprintf("%dx%d", int(state.cam.image_width), int(state.cam.image_height)))
	y += 38

	stats := editor_bvh_stats(state)
	if stats.nodes > 0 {
		editor_gui_section(&y, "BVH TREE")
		editor_gui_stat(y, "height", fmt.ctprintf("%d", stats.height))
		y += 26
		editor_gui_stat(y, "nodes", fmt.ctprintf("%d", stats.nodes))
		y += 26
		editor_gui_stat(y, "internal", fmt.ctprintf("%d", stats.internal_nodes))
		y += 26
		editor_gui_stat(y, "leaves", fmt.ctprintf("%d", stats.leaves))
		y += 38
	}
	if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 32}, "toggle Linear / BVH  (G)") {
		action.toggle_grouping = true
	}
	return
}

editor_gui_scenes :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 78
	if state.load_error != "" {
		editor_text(
			SIDEBAR_PAD,
			c.int(y),
			fmt.ctprintf("load failed: %s", state.load_error),
			14,
			rl.Color{255, 120, 110, 255},
		)
		y += 30
	}
	editor_gui_section(&y, "SCENES")
	for path in state.scene_files {
		if y+30 > f32(rl.GetScreenHeight()-16) { break }
		if rl.GuiButton({SIDEBAR_PAD, y, f32(SIDEBAR_INNER), 28}, path) {
			action.scene_path = string(path)
		}
		y += 34
	}
	return
}

editor_draw_sidebar :: proc(state: ^Editor_State) -> Editor_Action {
	rl.DrawRectangle(0, 0, EDITOR_SIDEBAR_WIDTH, rl.GetScreenHeight(), PANEL_BG)
	rl.DrawRectangleLinesEx(
		{f32(EDITOR_SIDEBAR_WIDTH-1), 0, 1, f32(rl.GetScreenHeight())},
		1,
		PANEL_BORDER,
	)
	_ = rl.GuiToggleGroup(
		{12, 16, 81, 30},
		"Params;Render;Stats;Scenes",
		&state.tab,
	)
	switch state.tab {
	case 0: return editor_gui_camera(state)
	case 1: return editor_gui_render(state)
	case 2: return editor_gui_stats(state)
	case:   return editor_gui_scenes(state)
	}
}
