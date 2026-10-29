class_name LowPoly
extends RefCounted
## Low-poly models built from simple shapes, with flat (faceted) shading:
## the 3D battlefield's trees, rocks and, later, buildings and troops.
## Sizes are in world units (1 = 100 map pixels).

static var _materials := {}


## A copy of `mesh` with one normal per face, for the faceted look.
static func flat(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		for v in verts:
			st.add_vertex(v)
	else:
		for i in index:
			st.add_vertex(verts[i])
	st.generate_normals()
	return st.commit()


## A matte material in `color`, shared by everything of that color.
static func material(color: Color, use_vertex_color := false) -> StandardMaterial3D:
	var key := [color, use_vertex_color]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		m.vertex_color_use_as_albedo = use_vertex_color
		_materials[key] = m
	return _materials[key]


static func cone(radius: float, height: float, sides := 6) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	c.cap_bottom = false
	return flat(c)


static func prism(radius: float, height: float, sides := 6, top := -1.0) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return flat(c)


static func blob(radius: float, squash := 1.0, sides := 7, rings := 4) -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 * squash
	s.radial_segments = sides
	s.rings = rings
	return flat(s)


static func box(size: Vector3) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	return flat(b)


## Many copies of one mesh in one draw: `xforms` places each, `colors`
## (optional) tints each.
static func scatter(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material(Color.WHITE, mm.use_colors)
	return node


## Trees at `spots` (ground points): trunks, then crowns of two stacked
## faceted blobs in varied greens. Leafy round trees, or pines with
## `pines`. `rng` varies their size and turn.
static func forest(spots: Array[Vector3], rng: RandomNumberGenerator, pines := false) -> Node3D:
	var root := Node3D.new()
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var tops: Array[Transform3D] = []
	var greens: Array[Color] = []
	var top_greens: Array[Color] = []
	for p in spots:
		var k := rng.randf_range(0.85, 1.2)
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		trunks.append(Transform3D(turn.scaled(Vector3(k, k, k)), p + Vector3(0, 0.09 * k, 0)))
		crowns.append(Transform3D(turn.scaled(Vector3(k, k, k)), p + Vector3(0, (0.3 if not pines else 0.26) * k, 0)))
		tops.append(Transform3D(turn.rotated(Vector3.UP, 0.5).scaled(Vector3(k, k, k)), p + Vector3(0, (0.42 if not pines else 0.44) * k, 0)))
		var g := Color("#4f8f37") if not pines else Color("#2f6b3a")
		g = g.lerp(Color("#6fb34d") if not pines else Color("#3f7f45"), rng.randf() * 0.6).darkened(rng.randf() * 0.12)
		greens.append(g)
		top_greens.append(g.lightened(0.12))
	root.add_child(scatter(prism(0.035, 0.18, 5, 0.025), trunks, _repeat(Color("#6b4426"), trunks.size())))
	if pines:
		root.add_child(scatter(cone(0.17, 0.3, 7), crowns, greens))
		root.add_child(scatter(cone(0.12, 0.24, 7), tops, top_greens))
	else:
		root.add_child(scatter(blob(0.17, 0.85), crowns, greens))
		root.add_child(scatter(blob(0.11, 0.9, 6, 3), tops, top_greens))
	return root


static func rocks(spots: Array[Vector3], rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var xf: Array[Transform3D] = []
	var greys: Array[Color] = []
	for p in spots:
		var k := rng.randf_range(0.5, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k * rng.randf_range(0.9, 1.4), k * 0.7, k))
		xf.append(Transform3D(b, p + Vector3(0, 0.02 * k, 0)))
		greys.append(Color("#8c8f8a").darkened(rng.randf() * 0.25))
	return scatter(blob(0.07, 0.8, 5, 3), xf, greys)


static func _repeat(c: Color, n: int) -> Array[Color]:
	var out: Array[Color] = []
	for i in n:
		out.append(c)
	return out


## A closed solid from convex faces (each a list of corners); every face is
## turned to point away from `inside`, so corner order doesn't matter.
static func solid(faces: Array, inside: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for face in faces:
		var mid := Vector3.ZERO
		for p in face:
			mid += p
		mid /= face.size()
		for i in range(1, face.size() - 1):
			var a: Vector3 = face[0]
			var b: Vector3 = face[i]
			var c: Vector3 = face[i + 1]
			# Godot's face normal is (c - a) x (b - a): make it point outward.
			if (c - a).cross(b - a).dot(mid - inside) < 0.0:
				var t := b
				b = c
				c = t
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	st.generate_normals()
	return st.commit()


## A gable roof: `w` along x (the ridge), `d` deep, `h` high, base at y 0.
static func gable(w: float, d: float, h: float) -> ArrayMesh:
	var x := w / 2.0
	var z := d / 2.0
	var a := Vector3(-x, 0, -z)
	var b := Vector3(x, 0, -z)
	var c := Vector3(x, 0, z)
	var e := Vector3(-x, 0, z)
	var r1 := Vector3(-x, h, 0)
	var r2 := Vector3(x, h, 0)
	return solid([[e, c, r2, r1], [a, b, r2, r1], [a, e, r1], [b, c, r2], [a, b, c, e]], Vector3(0, h / 3.0, 0))


## A pyramid roof over a `w` x `d` base, `h` high.
static func pyramid(w: float, d: float, h: float) -> ArrayMesh:
	var x := w / 2.0
	var z := d / 2.0
	var a := Vector3(-x, 0, -z)
	var b := Vector3(x, 0, -z)
	var c := Vector3(x, 0, z)
	var e := Vector3(-x, 0, z)
	var top := Vector3(0, h, 0)
	return solid([[a, b, top], [b, c, top], [c, e, top], [e, a, top], [a, b, c, e]], Vector3(0, h / 4.0, 0))


## A lean-to roof: high at the back (-z), low at the front.
static func shed(w: float, d: float, back: float, front: float) -> ArrayMesh:
	var x := w / 2.0
	var z := d / 2.0
	var pts := [Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z), Vector3(-x, 0, z),
		Vector3(-x, back, -z), Vector3(x, back, -z), Vector3(x, front, z), Vector3(-x, front, z)]
	return solid([[pts[0], pts[1], pts[2], pts[3]], [pts[4], pts[5], pts[6], pts[7]], [pts[0], pts[1], pts[5], pts[4]],
		[pts[3], pts[2], pts[6], pts[7]], [pts[0], pts[3], pts[7], pts[4]], [pts[1], pts[2], pts[6], pts[5]]],
		Vector3(0, (back + front) / 4.0, 0))


## A material whose color comes from each vertex (merged models, batches).
static func vertex_material() -> StandardMaterial3D:
	if not _materials.has("vertex"):
		var m := StandardMaterial3D.new()
		m.roughness = 0.95
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_materials["vertex"] = m
	return _materials["vertex"]


## Merge a model's parts into one mesh, each part's color kept in its
## vertices: one draw instead of dozens. Parts are MeshInstance3Ds, or
## Node3Ds carrying "mesh" and "color" metadata (Figures' parts). Moving
## parts stay separate: anything in the "spin" group or named "Flame".
static func merge(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for n in root.find_children("*", "Node3D", true, false):
		if _moving(n, root):
			continue
		var mesh: Mesh
		var color := Color.WHITE
		if n is MeshInstance3D:
			mesh = n.mesh
			var mat := n.material_override as StandardMaterial3D
			if mat:
				color = mat.albedo_color
		elif n.has_meta("mesh"):
			mesh = n.get_meta("mesh")
			color = n.get_meta("color")
		if mesh == null:
			continue
		_append(st, mesh, color, _relative(n, root))
		any = true
		if n is MeshInstance3D and n.get_child_count() == 0:
			n.free()  # each node is visited once, so this is safe here
		elif n is MeshInstance3D:
			n.mesh = null
		else:
			n.remove_meta("mesh")
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = st.commit()
	mi.material_override = vertex_material()
	root.add_child(mi)


## Add `mesh`'s triangles, moved by `t` and painted `color`.
static func _append(st: SurfaceTool, mesh: Mesh, color: Color, t: Transform3D) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors = arrays[Mesh.ARRAY_COLOR]
	var index = arrays[Mesh.ARRAY_INDEX]  # none on flat-shaded meshes
	var order := PackedInt32Array(range(verts.size()))
	if index is PackedInt32Array and not index.is_empty():
		order = index
	for i in order:
		var c := color
		if colors is PackedColorArray and not colors.is_empty():
			c = colors[i] * color
		st.set_color(c)
		st.set_normal((t.basis * normals[i]).normalized())
		st.add_vertex(t * verts[i])


## `n`'s transform within `root` (works before either is in the tree).
static func _relative(n: Node3D, root: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _moving(n: Node, root: Node) -> bool:
	while n != root and n != null:
		if n.is_in_group("spin") or n.name == "Flame":
			return true
		n = n.get_parent()
	return false
