package collider

import "core:math/rand"
import "core:slice"

BvhNode :: struct {
	box:          Aabb,
	left, right:  int,
	start, count: int,
}

Bvh :: struct {
	nodes:   [dynamic]BvhNode,
	indices: [dynamic]int,
}

bvh_build :: proc(bvh: ^Bvh, boxes: []Aabb) {
	n := len(boxes)
	bvh.indices = make([dynamic]int, n)
	for i in 0 ..< n do bvh.indices[i] = i

	if n > 0 do bvh_build_node(bvh, boxes, 0, n)
}

bvh_destroy :: proc(bvh: ^Bvh) {
	delete(bvh.nodes)
	delete(bvh.indices)
	bvh^ = {}
}


BvhBuildContext :: struct {
	boxes: []Aabb,
	axis:  int,
}

// i, j are primitive indices (elements of Bvh.indices); the permutation is what
// gets reordered, the boxes array never moves.
bvh_box_less :: proc(i, j: int, user_data: rawptr) -> bool {
	ctx := cast(^BvhBuildContext)user_data
	return(
		aabb_axis_interval(ctx.boxes[i], ctx.axis).min <
		aabb_axis_interval(ctx.boxes[j], ctx.axis).min \
	)
}

bvh_build_node :: proc(bvh: ^Bvh, boxes: []Aabb, start, end: int) -> int {
	indices := bvh.indices[:]
	span := end - start

	node_index := len(bvh.nodes)
	append(&bvh.nodes, BvhNode{left = -1, right = -1})

	box := boxes[indices[start]]
	for i in start + 1 ..< end {
		box = aabb_create(box, boxes[indices[i]])
	}
	bvh.nodes[node_index].box = box

	if span <= 2 {
		bvh.nodes[node_index].start = start
		bvh.nodes[node_index].count = span
		return node_index
	}

	// Random Axis - Quicker in the current code
	// axis := rand.int_range(0, 3)

	// Longest Axis - Even tho Book 2 states that this is a optimization, for me it made the performance worst
	// maybe was not right implemented (check later)
	axis := aabb_longest_axis(box)
	ctx := BvhBuildContext {
		boxes = boxes,
		axis  = axis,
	}
	slice.sort_by_with_data(indices[start:end], bvh_box_less, &ctx)

	mid := start + span / 2
	left := bvh_build_node(bvh, boxes, start, mid)
	right := bvh_build_node(bvh, boxes, mid, end)
	bvh.nodes[node_index].left = left
	bvh.nodes[node_index].right = right

	return node_index
}

bvh_hit :: proc(bvh: ^Bvh, space: ^ColliderSpace, ray: Ray, tmin, tmax: f64) -> (HitRecord, bool) {
	if len(bvh.nodes) == 0 do return HitRecord{}, false
	return bvh_hit_node(bvh, space, 0, ray, tmin, tmax)
}

bvh_hit_node :: proc(
	bvh: ^Bvh,
	space: ^ColliderSpace,
	node_index: int,
	ray: Ray,
	tmin, tmax: f64,
) -> (
	HitRecord,
	bool,
) {
	node := bvh.nodes[node_index]
	if !aabb_hit(node.box, ray.origin, ray.direction, {tmin, tmax}) do return HitRecord{}, false

	rec: HitRecord
	hit := false
	closest := tmax

	if node.left < 0 {
		for i in node.start ..< node.start + node.count {
			id := bvh.indices[i]
			current, ok := hit_primitive(space, id, ray, tmin, closest)

			if ok {
				hit = true
				closest = current.t
				current.object_index = id
				rec = current
			}
		}
		return rec, hit
	}

	left_rec, left_hit := bvh_hit_node(bvh, space, node.left, ray, tmin, closest)
	if left_hit {
		hit = true
		closest = left_rec.t
		rec = left_rec
	}

	right_rec, right_hit := bvh_hit_node(bvh, space, node.right, ray, tmin, closest)
	if right_hit {
		hit = true
		rec = right_rec
	}

	return rec, hit
}
