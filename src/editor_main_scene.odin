package main

import "core:c"
import "core:fmt"
import rayt "raytracer"
import collider "raytracer/collider"
import rl "vendor:raylib"

editor_preview_color :: proc(material: rayt.Material) -> rl.Color {
	to_rl :: proc(v: rayt.Color) -> rl.Color {
		return {
			u8(clamp(v.x, 0, 1)*255),
			u8(clamp(v.y, 0, 1)*255),
			u8(clamp(v.z, 0, 1)*255),
			255,
		}
	}
	switch m in material {
	case rayt.LambertianMaterial:   return to_rl(m.albedo)
	case rayt.MetalMaterial:        return to_rl(m.albedo)
	case rayt.DieletricMaterial:    return {150, 220, 255, 255}
	case rayt.DiffuseLightMaterial: return {255, 230, 140, 255}
	}
	return rl.MAGENTA
}

editor_draw_aabb :: proc(box: collider.Aabb, color: rl.Color, thickness: f32) {
	lo := rl.Vector3{f32(box.x.min), f32(box.y.min), f32(box.z.min)}
	hi := rl.Vector3{f32(box.x.max), f32(box.y.max), f32(box.z.max)}
	corners := [8]rl.Vector3{
		{lo.x, lo.y, lo.z}, {hi.x, lo.y, lo.z},
		{hi.x, hi.y, lo.z}, {lo.x, hi.y, lo.z},
		{lo.x, lo.y, hi.z}, {hi.x, lo.y, hi.z},
		{hi.x, hi.y, hi.z}, {lo.x, hi.y, hi.z},
	}
	edges := [12][2]int{
		{0, 1}, {1, 2}, {2, 3}, {3, 0},
		{4, 5}, {5, 6}, {6, 7}, {7, 4},
		{0, 4}, {1, 5}, {2, 6}, {3, 7},
	}
	for edge in edges {
		rl.DrawCylinderEx(corners[edge.x], corners[edge.y], thickness, thickness, 4, color)
	}
}

editor_draw_bvh_nodes :: proc(nodes: []collider.BvhNode, index, depth, height, max_depth: int) {
	if index < 0 || depth > max_depth { return }
	node := nodes[index]
	colors := [3]rl.Color{
		{235, 70, 60, 220},
		{255, 165, 55, 220},
		{75, 220, 120, 220},
	}
	thickness := [3]f32{0.012, 0.008, 0.004}
	band := min(depth*3/max(height, 1), 2)
	editor_draw_aabb(node.box, colors[band], thickness[band])
	if node.count == 0 {
		editor_draw_bvh_nodes(nodes, node.left, depth+1, height, max_depth)
		editor_draw_bvh_nodes(nodes, node.right, depth+1, height, max_depth)
	}
}

editor_draw_debug_selection :: proc(state: ^Editor_State, bvh: collider.Bvh) {
	if state.debug_ray_active {
		o := state.debug_ray.origin
		d := state.debug_ray.direction
		start := rl.Vector3{f32(o.x), f32(o.y), f32(o.z)}
		finish := start+rl.Vector3{f32(d.x), f32(d.y), f32(d.z)}*1000
		rl.DrawLine3D(start, finish, rl.YELLOW)
	}
	for node_index in state.debug_hit_nodes {
		editor_draw_aabb(bvh.nodes[node_index].box, {255, 60, 210, 255}, 0.008)
	}
	if state.debug_selected_active {
		editor_draw_aabb(bvh.nodes[state.debug_selected_node].box, rl.RAYWHITE, 0.015)
	}

	sphere_count := len(state.world.space.spheres)
	for id in state.debug_object_ids {
		if id < sphere_count {
			o := state.world.space.spheres.origin[id]
			radius := abs(f32(state.world.space.spheres.radius[id]))
			rl.DrawSphereWires({f32(o.x), f32(o.y), f32(o.z)}, radius, 20, 20, rl.YELLOW)
			editor_draw_aabb(state.world.space.spheres.bbox[id], rl.YELLOW, 0.01)
		} else {
			quad_index := id-sphere_count
			if quad_index >= len(state.world.space.quads) { continue }
			editor_draw_aabb(state.world.space.quads.bbox[quad_index], rl.YELLOW, 0.01)
		}
	}
}

editor_draw_bounds :: proc(state: ^Editor_State) {
	switch grouping in state.world.space.grouping {
	case collider.Bvh:
		stats := editor_bvh_stats(state)
		if stats.nodes == 0 { return }
		editor_draw_bvh_nodes(grouping.nodes[:], 0, 0, stats.height, state.bounds_depth)
		if state.bounds_depth >= stats.height-1 {
			primitive_color := rl.Color{220, 225, 235, 180}
			for i in 0..<len(state.world.space.spheres) {
				editor_draw_aabb(state.world.space.spheres.bbox[i], primitive_color, 0.003)
			}
			for i in 0..<len(state.world.space.quads) {
				editor_draw_aabb(state.world.space.quads.bbox[i], primitive_color, 0.003)
			}
		}
		editor_draw_debug_selection(state, grouping)
	case collider.LinearGrouping:
		editor_draw_aabb(state.world.space.bbox, rl.RED, 0.012)
	}
}

editor_draw_world :: proc(state: ^Editor_State) {
	for i in 0..<len(state.world.space.spheres) {
		radius := f32(state.world.space.spheres.radius[i])
		// Negative radius reverses raytraced normals for hollow glass. It is
		// not valid raster geometry; the positive outer shell is the preview.
		if radius < 0 { continue }
		o := state.world.space.spheres.origin[i]
		center := rl.Vector3{f32(o.x), f32(o.y), f32(o.z)}
		color := editor_preview_color(state.world.materials[i])
		switch {
		case radius >= 10:
			rl.DrawSphereWires(center, radius, 16, 16, color)
		case:
			rl.DrawSphere(center, radius, color)
			rl.DrawSphereWires(center, radius, 12, 12, rl.BLACK)
		}
	}
	rl.DrawGrid(40, 1)

	to_rl :: proc(v: rayt.Vec3) -> rl.Vector3 {
		return {f32(v.x), f32(v.y), f32(v.z)}
	}
	sphere_count := len(state.world.space.spheres)
	for i in 0..<len(state.world.space.quads) {
		corner := state.world.space.quads.corner[i]
		u := state.world.space.quads.edge_u[i]
		v := state.world.space.quads.edge_v[i]
		a, b := to_rl(corner), to_rl(corner+u)
		c, d := to_rl(corner+u+v), to_rl(corner+v)
		color := editor_preview_color(state.world.materials[sphere_count+i])
		rl.DrawTriangle3D(a, b, c, color)
		rl.DrawTriangle3D(a, c, d, color)
		rl.DrawLine3D(a, b, rl.GRAY)
		rl.DrawLine3D(b, c, rl.GRAY)
		rl.DrawLine3D(c, d, rl.GRAY)
		rl.DrawLine3D(d, a, rl.GRAY)
	}
	if state.show_bounds { editor_draw_bounds(state) }
}

editor_draw_tracer_camera :: proc(cam: rayt.Camera) {
	p := rl.Vector3{f32(cam.position.x), f32(cam.position.y), f32(cam.position.z)}
	l := rl.Vector3{f32(cam.look_at.x), f32(cam.look_at.y), f32(cam.look_at.z)}
	rl.DrawCubeV(p, {0.3, 0.3, 0.3}, rl.YELLOW)
	rl.DrawLine3D(p, l, rl.YELLOW)
	du, dv := cam.pixel_delta_u, cam.pixel_delta_v
	corners := [4]rayt.Vec3{
		cam.pixel00_location,
		cam.pixel00_location+du*cam.image_width,
		cam.pixel00_location+du*cam.image_width+dv*cam.image_height,
		cam.pixel00_location+dv*cam.image_height,
	}
	for i in 0..<4 {
		a, b := corners[i], corners[(i+1)%4]
		rl.DrawLine3D(
			{f32(a.x), f32(a.y), f32(a.z)},
			{f32(b.x), f32(b.y), f32(b.z)},
			rl.SKYBLUE,
		)
	}
}

editor_draw_scene_rt :: proc(state: ^Editor_State) {
	w := max(rl.GetScreenWidth()-EDITOR_SIDEBAR_WIDTH, 8)
	h := max(rl.GetScreenHeight(), 8)
	if state.scene_rt.texture.width != w || state.scene_rt.texture.height != h {
		rl.UnloadRenderTexture(state.scene_rt)
		state.scene_rt = rl.LoadRenderTexture(w, h)
	}
	rl.BeginTextureMode(state.scene_rt)
	rl.ClearBackground({25, 25, 35, 255})
	rl.BeginMode3D(state.fly)
	editor_draw_world(state)
	editor_draw_tracer_camera(state.cam)
	rl.EndMode3D()
	rl.EndTextureMode()
}

editor_draw_texture_contained :: proc(texture: rl.Texture2D, area: rl.Rectangle) {
	tw, th := f32(texture.width), f32(texture.height)
	scale := min(area.width/tw, area.height/th)
	dst := rl.Rectangle{
		area.x+(area.width-tw*scale)/2,
		area.y+(area.height-th*scale)/2,
		tw*scale,
		th*scale,
	}
	rl.DrawTexturePro(texture, {0, 0, tw, th}, dst, {}, 0, rl.WHITE)
}

editor_draw_hud :: proc(state: ^Editor_State, area: rl.Rectangle) {
	h := f32(34)
	rl.DrawRectangleRec({area.x, 0, area.width, h}, HUD_BG)
	rl.DrawRectangleRec({area.x, h, area.width, 1}, PANEL_BORDER)
	editor_text(
		c.int(area.x)+16,
		9,
		fmt.ctprintf("%s", state.loaded.scene.name),
		16,
		TEXT_PRIMARY,
	)
	cam := state.fly
	info := fmt.ctprintf(
		"%.1f, %.1f, %.1f   fov %.0f",
		cam.position.x, cam.position.y, cam.position.z, cam.fovy,
	)
	editor_text(
		c.int(area.x+area.width)-20-editor_text_width(info, 14),
		10,
		info,
		14,
		TEXT_MUTED,
	)

	sh := f32(26)
	sy := area.y+area.height-sh
	rl.DrawRectangleRec({area.x, sy, area.width, sh}, HUD_BG)
	rl.DrawRectangleRec({area.x, sy, area.width, 1}, PANEL_BORDER)
	mode: cstring = "RENDER" if state.show_render else "PREVIEW"
	mode_color := ACCENT if state.show_render else rl.Color{120, 200, 140, 255}
	editor_text(c.int(area.x)+16, c.int(sy)+6, mode, 14, mode_color)
	hint: cstring = "ENTER raytrace   G grouping   BACKSPACE preview"
	editor_text(
		c.int(area.x+area.width)-20-editor_text_width(hint, 14),
		c.int(sy)+6,
		hint,
		14,
		TEXT_MUTED,
	)

	if state.mouse_captured && !state.show_render {
		editor_text(
			c.int(area.x)+16,
			c.int(sy)-30,
			"ESC releases the mouse",
			14,
			rl.Color{225, 228, 236, 150},
		)
	}
}

editor_draw_main :: proc(state: ^Editor_State) {
	area := rl.Rectangle{
		f32(EDITOR_SIDEBAR_WIDTH),
		0,
		f32(rl.GetScreenWidth()-EDITOR_SIDEBAR_WIDTH),
		f32(rl.GetScreenHeight()),
	}
	if state.show_render && state.has_render {
		editor_draw_texture_contained(state.render_tex, area)
	} else {
		rl.DrawTextureRec(
			state.scene_rt.texture,
			{0, 0, f32(state.scene_rt.texture.width), -f32(state.scene_rt.texture.height)},
			{f32(EDITOR_SIDEBAR_WIDTH), 0},
			rl.WHITE,
		)
	}
	editor_draw_hud(state, area)
}
