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
