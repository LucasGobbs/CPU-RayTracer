package main

import "core:fmt"
import "core:math"
import "core:os"

import collider "raytracer/collider"
import rl "vendor:raylib"

editor_gui_slider :: proc(
	y: f32,
	label: cstring,
	value: ^f32,
	min_value, max_value: f32,
) -> bool {
	before := value^
	_ = rl.GuiSlider(
		{100, y, 225, 24},
		label,
		fmt.ctprintf("%.2f", value^),
		value,
		min_value,
		max_value,
	)
	return before != value^
}

editor_gui_camera :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 74
	pos := [3]f32{f32(state.params.position.x), f32(state.params.position.y), f32(state.params.position.z)}
	look := [3]f32{f32(state.params.look_at.x), f32(state.params.look_at.y), f32(state.params.look_at.z)}
	for i in 0..<3 {
		labels := [3]cstring{"pos x", "pos y", "pos z"}
		limit := max(f32(25), abs(pos[i])*2)
		if editor_gui_slider(y, labels[i], &pos[i], -limit, limit) {
			state.params.position[i] = f64(pos[i])
			action.camera_changed = true
		}
		y += 38
	}
	for i in 0..<3 {
		labels := [3]cstring{"look x", "look y", "look z"}
		limit := max(f32(25), abs(look[i])*2)
		if editor_gui_slider(y, labels[i], &look[i], -limit, limit) {
			state.params.look_at[i] = f64(look[i])
			action.camera_changed = true
		}
		y += 38
	}
	vfov := f32(state.params.vfov)
	if editor_gui_slider(y, "vfov", &vfov, 1, 120) {
		state.params.vfov = f64(vfov)
		action.camera_changed = true
	}
	y += 38
	defocus := f32(state.params.defocus_angle)
	if editor_gui_slider(y, "defocus", &defocus, 0, 10) {
		state.params.defocus_angle = f64(defocus)
		action.camera_changed = true
	}
	y += 38
	focus := f32(state.params.focus_dist)
	if editor_gui_slider(y, "focus", &focus, 0.1, 30) {
		state.params.focus_dist = f64(focus)
		action.camera_changed = true
	}
	y += 38
	samples := f32(state.params.samples)
	if editor_gui_slider(y, "samples", &samples, 1, 500) {
		state.params.samples = int(samples)
		action.camera_changed = true
	}
	y += 38
	depth := f32(state.params.max_depth)
	if editor_gui_slider(y, "depth", &depth, 1, 50) {
		state.params.max_depth = int(depth)
		action.camera_changed = true
	}
	y += 38
	width := f32(state.loaded.render.width)
	if editor_gui_slider(y, "width", &width, 64, 4000) {
		state.loaded.render.width = math.round(f64(width))
		action.render_settings_changed = true
	}
	y += 38
	ratio := f32(state.loaded.render.ratio)
	if editor_gui_slider(y, "aspect", &ratio, 0.5, 3) {
		state.loaded.render.ratio = f64(ratio)
		action.render_settings_changed = true
	}
	y += 38
	upscale := f32(state.loaded.render.upscale)
	if editor_gui_slider(y, "upscale", &upscale, 1, 16) {
		state.loaded.render.upscale = f64(upscale)
		action.render_settings_changed = true
	}
	y += 38
	threads := f32(state.loaded.render.threads)
	if editor_gui_slider(y, "threads", &threads, 1, 64) {
		state.loaded.render.threads = max(1, int(math.round(threads)))
	}
	y += 34
	_ = rl.GuiLabel({20, y, 320, 24}, "color format: RGBA8 (4, renderer-fixed)")
	y += 34
	if rl.GuiButton({20, y, 320, 28}, fmt.ctprintf("accelerator: %v", collider.grouping_kind(state.world.space.grouping))) {
		action.toggle_grouping = true
	}
	y += 42
	if rl.GuiButton({20, y, f32(EDITOR_SIDEBAR_WIDTH-40), 30}, "reset preview") {
		action.reset_view = true
	}
	y += 40
	if rl.GuiButton({20, y, f32(EDITOR_SIDEBAR_WIDTH-40), 30}, "capture preview camera") {
		action.capture_view = true
	}
	return
}

editor_gui_render :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 82
	_ = rl.GuiLabel({20, y, 320, 24}, "CPU path tracing is intentionally blocking.")
	y += 38
	if rl.GuiButton({20, y, 320, 36}, "raytrace render (ENTER)") {
		action.render = true
	}
	y += 48
	if state.has_render {
		_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf("last render: %.2f ms", state.render_ms))
		y += 34
		if rl.GuiButton({20, y, 155, 30}, "view render") { action.show_render = true }
		if rl.GuiButton({185, y, 155, 30}, "view preview") { action.show_preview = true }
	} else {
		_ = rl.GuiLabel({20, y, 320, 24}, "no render yet")
	}
	y += 42
	bounds_label: cstring = "hide bounding boxes" if state.show_bounds else "show bounding boxes"
	if rl.GuiButton({20, y, 320, 30}, bounds_label) {
		action.toggle_bounds = true
	}
	if state.show_bounds {
		stats := editor_bvh_stats(state)
		if stats.nodes > 0 {
			y += 38
			depth := f32(state.bounds_depth)
			max_depth := max(stats.height-1, 0)
			if max_depth > 0 && editor_gui_slider(y, "tree depth", &depth, 0, f32(max_depth)) {
				state.bounds_depth = clamp(int(math.round(depth)), 0, max_depth)
				editor_clear_bvh_inspection(state)
			}
			y += 34
			_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf(
				"ray boxes: %d   selected objects: %d",
				len(state.debug_hit_nodes), len(state.debug_object_ids),
			))
			y += 28
			if state.debug_selected_active {
				_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf(
					"selected depth: %d", state.debug_selected_depth,
				))
				_ = rl.GuiLabel({20, y+24, 320, 24}, fmt.ctprintf(
					"object ids: %v", state.debug_object_ids[:],
				))
				y += 24
			}
		}
	}
	y += 64
	_ = rl.GuiLine({20, y, 320, 20}, "shortcuts")
	y += 30
	_ = rl.GuiLabel({20, y, 320, 24}, "ENTER render    BACKSPACE preview")
	y += 24
	_ = rl.GuiLabel({20, y, 320, 24}, "LMB fly; RMB inspect; SPACE up; CTRL down; ESC release")
	return
}

editor_gui_stats :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 82
	kind := collider.grouping_kind(state.world.space.grouping)
	labels := [?]cstring{
		fmt.ctprintf("fps: %d", rl.GetFPS()),
		fmt.ctprintf("frame: %.2f ms", rl.GetFrameTime()*1000),
		fmt.ctprintf("threads: %d", os.get_processor_core_count()),
		fmt.ctprintf("accelerator: %v", kind),
		fmt.ctprintf("spheres: %d", len(state.world.space.spheres)),
		fmt.ctprintf("quads: %d", len(state.world.space.quads)),
		fmt.ctprintf("render image: %dx%d", int(state.cam.image_width), int(state.cam.image_height)),
	}
	for label in labels {
		_ = rl.GuiLabel({20, y, 320, 24}, label)
		y += 30
	}
	stats := editor_bvh_stats(state)
	if stats.nodes > 0 {
		_ = rl.GuiLine({20, y, 320, 20}, "BVH tree")
		y += 26
		_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf("height: %d", stats.height))
		y += 26
		_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf("nodes: %d", stats.nodes))
		y += 26
		_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf("internal: %d   leaves: %d", stats.internal_nodes, stats.leaves))
		y += 30
	}
	y += 12
	if rl.GuiButton({20, y, 320, 32}, "toggle Linear / BVH (G)") {
		action.toggle_grouping = true
	}
	return
}

editor_gui_scenes :: proc(state: ^Editor_State) -> (action: Editor_Action) {
	y: f32 = 76
	if state.load_error != "" {
		_ = rl.GuiLabel({20, y, 320, 24}, fmt.ctprintf("load failed: %s", state.load_error))
		y += 32
	}
	_ = rl.GuiLabel({20, y, 320, 24}, "select a JSON scene")
	y += 34
	for path in state.scene_files {
		if y+32 > f32(rl.GetScreenHeight()-20) { break }
		if rl.GuiButton({20, y, 320, 28}, path) {
			action.scene_path = string(path)
		}
		y += 34
	}
	return
}

editor_draw_sidebar :: proc(state: ^Editor_State) -> Editor_Action {
	_ = rl.GuiPanel({0, 0, EDITOR_SIDEBAR_WIDTH, f32(rl.GetScreenHeight())}, nil)
	_ = rl.GuiToggleGroup(
		{12, 12, 82, 30},
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
