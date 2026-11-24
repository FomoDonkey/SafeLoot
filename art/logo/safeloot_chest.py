"""SafeLoot logo, painted version: the chest that watches. Original artwork, no game assets.

    blender -b --python art/logo/safeloot_chest.py -- OUT.png [size] [samples]

A heavy old chest with horns; its lock is an eye whose pupil is the keyhole. Nothing here is lit by a renderer: every
material is a small "painter" that mixes a hand-picked palette from the direction of the light, the hollows, the worn
edges and brush noise, so the result is flat painted planes with light on the edges instead of shiny plastic.
art/logo/paint.py then repaints it with brush strokes and exports every size.
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "chest_raw.png"
SIZE = int(argv[1]) if len(argv) > 1 else 1024
SAMPLES = int(argv[2]) if len(argv) > 2 else 32
random.seed(5)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
YAW, PITCH_ROLL = math.radians(-17), 0.0
ROOT = Matrix.Rotation(YAW, 4, "Z")
EYE_LOCAL = Vector((0.0, -1.16, -0.4))
EYE_W = ROOT @ EYE_LOCAL
GAP_W = ROOT @ Vector((0, -0.95, 0.1))
KEY = Vector((-0.62, -0.62, 0.78)).normalized()
RIM = Vector((0.85, 0.15, 0.45)).normalized()
FILL = Vector((0.9, -0.35, 0.1)).normalized()


def lin(hexa):
    out = []
    for i in (0, 2, 4):
        c = int(hexa[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1)


# A tiny node language -----------------------------------------------------------------------------------------------
class P:
    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.nt = self.m.node_tree
        self.nt.nodes.clear()

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def put(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, (tuple, list, Vector)):
            sock.default_value = v if len(sock.default_value) == len(v) else (*v, 1)
        else:
            self.nt.links.new(v, sock)

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        return n.outputs[0]

    def add(self, a, b):
        return self.math("ADD", a, b)

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def vec(self, op, a, b=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[3 if op == "SCALE" else 1], b)
        return n.outputs["Value"] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs["Vector"]

    def remap(self, v, a, b, c=0.0, d=1.0, smooth=False):
        n = self.node("ShaderNodeMapRange", clamp=True, interpolation_type="SMOOTHSTEP" if smooth else "LINEAR")
        self.put(n.inputs["Value"], v)
        for key, val in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            n.inputs[key].default_value = val
        return n.outputs["Result"]

    def noise(self, vector, scale, detail=3.0, rough=0.55):
        n = self.node("ShaderNodeTexNoise")
        self.put(n.inputs["Vector"], vector)
        n.inputs["Scale"].default_value, n.inputs["Detail"].default_value, n.inputs["Roughness"].default_value = scale, detail, rough
        return n.outputs[0], n.outputs[1]

    def ramp(self, fac, stops):
        n = self.node("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = "EASE"
        while len(cr.elements) > 1:
            cr.elements.remove(cr.elements[0])
        cr.elements[0].position, cr.elements[0].color = stops[0][0], lin(stops[0][1])
        for pos, col in stops[1:]:
            cr.elements.new(pos).color = lin(col)
        self.put(n.inputs["Fac"], fac)
        return n.outputs["Color"]

    def mix(self, fac, a, b, mode="MIX"):
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=mode)
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def out(self, color, strength=1.0):
        e = self.node("ShaderNodeEmission")
        self.put(e.inputs["Color"], color)
        self.put(e.inputs["Strength"], strength)
        o = self.node("ShaderNodeOutputMaterial")
        self.nt.links.new(e.outputs[0], o.inputs[0])
        return self.m


def painted(name, palette, edge, wood=None, metal=0.0, brush=0.2, brush_scale=3.2, edge_width=0.06, ao_dist=0.7, rim=0.3, grad=None,
            bevel=0.035, eye_glow=0.9, gold_glow=0.6, scratch=0.0):
    """palette: five colours from the darkest shadow to the painted light; edge: colour of the worn edges."""
    p = P(name)
    geo = p.node("ShaderNodeNewGeometry")
    coord = p.node("ShaderNodeTexCoord").outputs["Object"]
    bev = p.node("ShaderNodeBevel", samples=8)
    bev.inputs["Radius"].default_value = bevel
    n0 = bev.outputs["Normal"]
    _, wob = p.noise(coord, brush_scale, 2.5)
    n = p.vec("NORMALIZE", p.vec("ADD", n0, p.vec("SCALE", p.vec("SUBTRACT", wob, (0.5, 0.5, 0.5)), 0.55 if metal else 0.42)))
    key = p.add(p.mul(p.vec("DOT_PRODUCT", n, KEY), 0.5), 0.5)
    key = p.add(key, p.mul(p.math("MAXIMUM", p.vec("DOT_PRODUCT", n, FILL), 0.0), 0.3))
    ao = p.node("ShaderNodeAmbientOcclusion", samples=8)
    ao.inputs["Distance"].default_value = ao_dist
    occ = ao.outputs["AO"]
    conv = p.node("ShaderNodeAmbientOcclusion", samples=8, inside=True, only_local=True)
    conv.inputs["Distance"].default_value = edge_width
    convex = p.math("SUBTRACT", 1.0, conv.outputs["AO"])
    sep = p.node("ShaderNodeSeparateXYZ")
    p.put(sep.inputs[0], geo.outputs["Position"])
    height = p.remap(sep.outputs["Z"], -1.6, 1.6, 0.72, 1.08)
    streak, _ = p.noise(p.vec("MULTIPLY", coord, (1.0, 1.0, 2.6)), brush_scale * 0.9, 4, 0.6)
    fine, _ = p.noise(coord, brush_scale * 5.5, 4, 0.65)
    fac = p.mul(p.mul(key, p.remap(occ, 0.2, 1.0, 0.16, 1.0)), height)
    fac = p.add(fac, p.mul(p.math("SUBTRACT", streak, 0.5), brush * 1.5))
    fac = p.add(fac, p.mul(p.math("SUBTRACT", fine, 0.5), brush * 0.7))
    if grad:
        fac = p.add(fac, p.remap(sep.outputs["Z"], grad[0], grad[1], grad[2], grad[3]))
    if wood:
        sx, sy, sz = wood
        grain, _ = p.noise(p.vec("MULTIPLY", coord, (sx, sy, sz)), 1.0, 5, 0.62)
        lines = p.remap(p.math("ABSOLUTE", p.math("SUBTRACT", p.math("FRACT", p.mul(grain, 5.0)), 0.5)), 0.0, 0.2, 0.0, 1.0, True)
        fac = p.mul(fac, p.add(0.56, p.mul(lines, 0.5)))
        knots, _ = p.noise(p.vec("MULTIPLY", coord, (sx * 0.55, sy * 0.55, sz * 0.4)), 1.3, 2)
        fac = p.add(fac, p.mul(p.math("SUBTRACT", knots, 0.5), 0.5))
    if scratch:
        sc, _ = p.noise(p.vec("MULTIPLY", coord, (2.2, 2.2, 14.0)), 2.4, 2, 0.5)
        fac = p.add(fac, p.mul(p.remap(sc, 0.63, 0.7), scratch))
        pit, _ = p.noise(coord, 7.0, 3, 0.7)
        fac = p.math("SUBTRACT", fac, p.mul(p.remap(pit, 0.62, 0.74), scratch * 0.9))
    col = p.ramp(fac, list(zip((0.09, 0.3, 0.49, 0.67, 0.89), palette)))
    # painted glints of old metal: broken by the brush, never a mirror
    if metal:
        refl = p.vec("REFLECT", p.vec("SCALE", KEY, -1.0), n)
        hit = p.math("MAXIMUM", p.vec("DOT_PRODUCT", refl, geo.outputs["Incoming"]), 0.0)
        glint = p.remap(p.add(p.math("POWER", hit, 7.0), p.mul(p.math("SUBTRACT", fine, 0.5), 0.5)), 0.34, 0.62, 0.0, metal, True)
        col = p.mix(glint, col, lin(edge))
    # worn edges: light where the key reaches, broken into strokes
    worn = p.mul(p.remap(convex, 0.22, 0.5, 0, 1, True), p.remap(streak, 0.34, 0.6, 0.15, 1))
    worn = p.mul(worn, p.remap(key, 0.3, 0.8, 0.12, 1.0))
    col = p.mix(p.mul(worn, p.remap(occ, 0.2, 0.7, 0.2, 1.0)), col, lin(edge))
    # hollows: not black, a warm violet dark
    col = p.mix(p.mul(p.remap(occ, 0.62, 0.1, 0, 0.82, True), 1.0), col, lin("120a12"))
    # violet light from behind
    facing = p.math("SUBTRACT", 1.0, p.math("ABSOLUTE", p.vec("DOT_PRODUCT", n0, geo.outputs["Incoming"])))
    back = p.mul(p.mul(p.math("POWER", facing, 2.2), p.remap(convex, 0.12, 0.4, 0.06, 1.0, True)), p.math("MAXIMUM", p.vec("DOT_PRODUCT", n, RIM), 0.0))
    col = p.mix(p.mul(p.remap(back, 0.1, 0.45, 0, rim * 2.2, True), p.remap(fine, 0.3, 0.6, 0.6, 1)), col, lin("9a6ad8"))

    # light of the eye and of the gold on what surrounds them
    def lamp(pos, reach, colour, power, col):
        d = p.vec("SUBTRACT", pos, geo.outputs["Position"])
        dist = p.vec("LENGTH", d)
        lam = p.remap(p.vec("DOT_PRODUCT", n, p.vec("NORMALIZE", d)), -0.25, 0.8)
        amt = p.mul(p.mul(lam, p.remap(dist, reach, 0.25, 0, 1, True)), power)
        return p.mix(p.math("MINIMUM", amt, 0.95), col, colour, "SCREEN")

    if eye_glow:
        col = lamp(EYE_W + (ROOT @ Vector((0, -0.45, 0))), 1.35, lin("6a22b8"), eye_glow * 0.5, col)
    if gold_glow:
        col = lamp(GAP_W, 0.75, lin("e8912a"), gold_glow, col)
    return p.out(col)


WOOD_PAL = ("140909", "2c140d", "4f2813", "77421d", "a3642f")
WOOD = painted("wood", WOOD_PAL, "d8a05c", wood=(1.1, 1.1, 9.0), brush=0.24, edge_width=0.05)
WOOD_LID = painted("wood lid", ("1a0c0a", "3a1c10", "64361a", "8e5527", "b87a3e"), "e3ae66", wood=(1.0, 8.0, 8.0), brush=0.24, edge_width=0.05)
IRON = painted("iron", ("0b0a12", "191823", "2e2e3b", "4a4b59", "717482"), "c3c4c4", metal=0.5, brush=0.3, scratch=0.34, edge_width=0.06)
BRASS = painted("brass", ("1a0b07", "43210d", "7c4814", "b47a22", "dfae45"), "fff0a8", metal=0.8, brush=0.26, scratch=0.22, edge_width=0.07)
COIN = painted("coin", ("2a1206", "6a3a0c", "a9701a", "dba432", "f3cf5c"), "ffe99a", metal=0.4, brush=0.22, edge_width=0.045, eye_glow=0.3, rim=0.25)
COIN_MARK = P("coin mark").out(lin("4a230a"))
BONE = painted("horn", ("0f080a", "2a1a18", "573c2b", "94704a", "d6b67e"), "f8e9c0", brush=0.3, edge_width=0.06, rim=0.5, gold_glow=0.0, bevel=0.03, grad=(0.5, 2.1, -0.3, 0.16))
HIDE = painted("hide", ("0b0607", "1d0f0c", "372016", "583a26", "82603e"), "dcb483", metal=0.2, brush=0.34, scratch=0.3, edge_width=0.06, eye_glow=0.45, rim=0.15)


def flat(name, colour, strength=1.0):
    return P(name).out(lin(colour), strength)


def iris_material():
    p = P("iris")
    coord = p.node("ShaderNodeTexCoord").outputs["Object"]
    sep = p.node("ShaderNodeSeparateXYZ")
    p.put(sep.inputs[0], coord)
    x, z = sep.outputs["X"], sep.outputs["Z"]
    r = p.math("SQRT", p.add(p.mul(x, x), p.mul(z, z)))
    ang = p.math("ARCTAN2", z, x)
    comb = p.node("ShaderNodeCombineXYZ")
    p.put(comb.inputs[0], p.mul(p.math("COSINE", ang), 4.2))
    p.put(comb.inputs[1], p.mul(p.math("SINE", ang), 4.2))
    p.put(comb.inputs[2], p.mul(r, 1.1))
    fib, _ = p.noise(comb.outputs[0], 2.0, 5, 0.65)
    wob, _ = p.noise(coord, 5.0, 3)
    t = p.add(p.mul(r, 1.36), p.add(p.mul(p.math("SUBTRACT", fib, 0.5), 0.5), p.mul(p.math("SUBTRACT", wob, 0.5), 0.12)))
    # light comes from above: the upper part lies in the shadow of the lid, the lower part glows
    t = p.add(t, p.remap(z, 0.02, 0.36, 0.0, 0.34))
    col = p.ramp(t, ((0.1, "fff3d8"), (0.24, "f7a9ff"), (0.4, "c25cf5"), (0.58, "7a25c4"), (0.78, "3a0f74"), (0.97, "12052a")))
    return p.out(col)


IRIS = iris_material()


# Geometry -----------------------------------------------------------------------------------------------------------
def finish(ob, mat, angle=38, local=True):
    me = ob.data
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(angle))
    scene.collection.objects.link(ob)
    if local:
        ob.matrix_world = ROOT @ ob.matrix_world
    return ob


def rough(bm, amount, freq=1.7, seed=0.0):
    for v in bm.verts:
        q = v.co * freq + Vector((seed, seed * 1.7, -seed))
        v.co += Vector(noise.noise_vector(q)) * amount


def taper(co):
    k = 1 + 0.1 * min(0.0, co.z) / 1.15
    return Vector((co.x * k, co.y * k, co.z))


def box(size, loc, mat, rot=(0, 0, 0), jitter=0.016, cuts=5, tap=False, seed=None, matrix=None, bev=0.03):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=1, affect="EDGES", profile=0.5)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=cuts, use_grid_fill=True)
    rough(bm, jitter, 1.6, seed if seed is not None else random.uniform(0, 50))
    m = (matrix or Matrix()) @ Matrix.Translation(loc) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
    for v in bm.verts:
        v.co = m @ v.co
        if tap:
            v.co = taper(v.co)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("box")
    bm.to_mesh(me)
    bm.free()
    return finish(bpy.data.objects.new("box", me), mat)


XF = None


def mesh(verts, faces, mat, angle=38, jitter=0.0, freq=1.7, matrix=None, tap=False):
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    if jitter:
        rough(bm, jitter, freq, random.uniform(0, 50))
    for v in bm.verts:
        if matrix is not None:
            v.co = matrix @ v.co
        if tap:
            v.co = taper(v.co)
        if XF is not None:
            v.co = XF @ v.co
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("mesh")
    bm.to_mesh(me)
    bm.free()
    return finish(bpy.data.objects.new("mesh", me), mat, angle)


def rivet(loc, r, mat, normal=(0, -1, 0), matrix=None, tap=False):
    """A fat hammered dome."""
    v, f, R, S = [], [], 5, 14
    for j in range(R + 1):
        a = math.pi / 2 * j / R
        for i in range(S):
            b = 2 * math.pi * i / S
            v.append((r * math.cos(a) * math.cos(b), r * math.cos(a) * math.sin(b), 0.75 * r * math.sin(a)))
    for j in range(R):
        for i in range(S):
            k = (i + 1) % S
            f.append((j * S + i, j * S + k, (j + 1) * S + k, (j + 1) * S + i))
    q = Vector(normal).to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = (matrix or Matrix()) @ Matrix.Translation(loc) @ q
    return mesh(v, f, mat, 60, 0.006, 4, m, tap)


def sweep(path, width, thick, mat, x=0.0, matrix=None, tap=False, jitter=0.012, along_x=False):
    """A flat bar that follows a path of (y, z) points at a given x."""
    pts = [Vector((0, y, z)) for y, z in path]
    v, f, n, W = [], [], len(pts), 4
    for i, q in enumerate(pts):
        tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = Vector((0, -tan.z, tan.y))
        if nrm.y > 0 and abs(nrm.z) < 0.3 and q.y < 0:
            nrm = -nrm
        for sx, sn in ((-1, 0), (-1, 0.75), (-0.82, 1), (0.82, 1), (1, 0.75), (1, 0)):
            v.append(tuple(q + nrm * (thick * sn) + Vector((x + sx * width / 2, 0, 0))))
    for i in range(n - 1):
        for k in range(6):
            b = (k + 1) % 6
            f.append((i * 6 + k, i * 6 + b, (i + 1) * 6 + b, (i + 1) * 6 + k))
    f.append(tuple(range(6)))
    f.append(tuple(range((n - 1) * 6, n * 6)))
    return mesh(v, f, mat, 35, jitter, 2.2, matrix, tap)


# Chest: base --------------------------------------------------------------------------------------------------------
HX, HY, H = 1.32, 0.9, 1.2
for k in range(3):
    z = -H + (k + 0.5) * H / 3
    h = H / 3 - 0.03
    box((2 * HX + random.uniform(-0.02, 0.02), 0.14, h), (0, -HY + 0.07 + random.uniform(-0.012, 0.012), z), WOOD, (0, random.uniform(-0.008, 0.008), 0), 0.02, 7, True)
    for s in (-1, 1):
        box((0.14, 2 * HY - 0.2, h), (s * (HX - 0.07), 0, z), WOOD, (0, 0, 0), 0.02, 6, True)
box((2 * HX - 0.2, 2 * HY - 0.2, H - 0.1), (0, 0.02, -H / 2 - 0.02), flat("inside", "0c0608"), (0, 0, 0), 0, 1, True)
# iron: bottom and top rims, corner posts with claws
for zc, hh, th in ((-H + 0.11, 0.26, 0.1), (-0.1, 0.24, 0.12)):
    box((2 * HX + 0.2, th + 0.06, hh), (0, -HY - 0.03, zc), IRON, (0, 0, 0), 0.015, 7, True)
    for s in (-1, 1):
        box((th + 0.06, 2 * HY + 0.1, hh), (s * (HX + 0.03), 0, zc), IRON, (0, 0, 0), 0.015, 6, True)
for s in (-1, 1):
    box((0.3, 0.3, H + 0.04), (s * (HX - 0.05), -HY + 0.05, -H / 2), IRON, (0, 0, 0), 0.018, 6, True)
    box((0.26, 0.26, H + 0.04), (s * (HX - 0.04), HY - 0.05, -H / 2), IRON, (0, 0, 0), 0.018, 6, True)
    box((0.4, 0.42, 0.24), (s * (HX - 0.03), -HY + 0.02, -H - 0.06), IRON, (0, 0, 0), 0.02, 4, True, bev=0.07)
    for z in (-1.02, -0.6, -0.2):
        rivet((s * (HX - 0.05), -HY - 0.12, z), 0.085, BRASS, tap=True)
for x in (-0.62, 0.62):
    rivet((x * 1.35, -HY - 0.11, -H + 0.12), 0.07, BRASS, tap=True)

# Chest: lid, opened a crack --------------------------------------------------------------------------------------------
HINGE = Vector((0, HY, 0.02))
LID = Matrix.Translation(HINGE) @ Matrix.Rotation(math.radians(-7.5), 4, "X") @ Matrix.Translation(-HINGE)
LH = 0.86


def arc(a, grow=0.0):
    return (-(HY + grow) * math.cos(a), 0.06 + (LH + grow) * math.sin(a) ** 0.82)


STAVES = 6
for k in range(STAVES):
    a0, a1 = math.pi * k / STAVES + 0.012, math.pi * (k + 1) / STAVES - 0.012
    v, f, N = [], [], 18
    seg = 5
    for i in range(N + 1):
        x = -HX + 2 * HX * i / N
        for j in range(seg + 1):
            a = a0 + (a1 - a0) * j / seg
            # each stave is a plank: flatter than the arc
            y0, z0 = arc(a0)
            y1, z1 = arc(a1)
            t = j / seg
            yy, zz = arc(a)
            fy, fz = y0 + (y1 - y0) * t, z0 + (z1 - z0) * t
            v.append((x, yy * 0.45 + fy * 0.55, zz * 0.45 + fz * 0.55))
        for j in range(seg, -1, -1):
            a = a0 + (a1 - a0) * j / seg
            y, z = arc(a, -0.14)
            v.append((x, y, z))
    ring = 2 * (seg + 1)
    for i in range(N):
        for j in range(ring):
            b = (j + 1) % ring
            f.append((i * ring + j, i * ring + b, (i + 1) * ring + b, (i + 1) * ring + j))
    f.append(tuple(range(ring)))
    f.append(tuple(range(N * ring, (N + 1) * ring)))
    mesh(v, f, WOOD_LID, 30, 0.022, 1.5, LID)
for s in (-1, 1):
    v, f, N = [], [], 24
    for i in range(N + 1):
        y, z = arc(math.pi * i / N, -0.02)
        v += [(s * (HX - 0.06), y, z), (s * (HX + 0.06), y, z)]
    f.append([2 * i for i in range(N + 1)])
    f.append([2 * i + 1 for i in range(N + 1)])
    for i in range(N):
        f.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
    f.append((0, 1, 2 * N + 1, 2 * N))
    mesh(v, f, WOOD, 30, 0.012, 2, LID)
    arch = [arc(math.pi * i / 22, 0.0) for i in range(23)]
    sweep(arch, 0.32, 0.13, IRON, s * (HX - 0.06), LID, jitter=0.016)
    for a in (0.35, 0.9, 1.5, 2.1):
        y, z = arc(a, 0.12)
        rivet((s * (HX - 0.06), y, z), 0.075, BRASS, (0, -math.cos(a), math.sin(a)), LID)
for x in (-0.62, 0.62):
    arch = [arc(math.pi * i / 22, 0.0) for i in range(23)]
    sweep(arch, 0.25, 0.1, IRON, x, LID, jitter=0.014)
    for a in (0.4, 1.0, 1.6):
        y, z = arc(a, 0.09)
        rivet((x, y, z), 0.068, BRASS, (0, -math.cos(a), math.sin(a)), LID)
box((2 * HX + 0.2, 0.17, 0.22), (0, -HY - 0.02, 0.15), IRON, (0, 0, 0), 0.015, 7, matrix=LID)
for s in (-1, 1):
    box((0.17, 2 * HY + 0.05, 0.22), (s * (HX + 0.02), 0, 0.15), IRON, (0, 0, 0), 0.015, 6, matrix=LID)

# the gold inside, seen through the crack
box((2 * HX - 0.34, 1.4, 0.05), (0, 0.1, 0.03), flat("gold light", "ffd873", 1.15), (0, 0, 0), 0, 1)


def coin(loc, rot, r=0.24, mat=COIN):
    prof = [(0.0, 0.036), (0.62, 0.036), (0.68, 0.06), (0.8, 0.06), (0.86, 0.04), (0.9, 0.075), (1.0, 0.06), (1.0, -0.06), (0.9, -0.075), (0.0, -0.05)]
    S, v, f = 22, [], []
    for pr, ph in prof:
        for i in range(S):
            a = 2 * math.pi * i / S
            v.append((pr * r * math.cos(a), pr * r * math.sin(a), ph * 0.95 * (r / 0.24) * 0.6))
    for j in range(len(prof) - 1):
        for i in range(S):
            k = (i + 1) % S
            f.append((j * S + i, j * S + k, (j + 1) * S + k, (j + 1) * S + i))
    m = Matrix.Translation(loc) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
    ob = mesh(v, f, mat, 30, 0.012, 3)
    ob.matrix_world = ROOT @ m
    k = r * 1.5
    pts = [(0.15 * k * math.cos(math.radians(a)), 0.13 * k + 0.15 * k * math.sin(math.radians(a))) for a in range(-60, 241, 20)]
    pts += [(-0.07 * k, -0.02 * k), (-0.14 * k, -0.3 * k), (0.14 * k, -0.3 * k), (0.07 * k, -0.02 * k)]
    top = 0.036 * 0.95 * (r / 0.24) * 0.6 + 0.012
    mark = mesh([(x, z, top) for x, z in pts], [tuple(range(len(pts)))], COIN_MARK, 30)
    mark.matrix_world = ROOT @ m
    return ob


for i in range(13):
    x = -1.1 + 2.2 * i / 12
    coin((x + random.uniform(-0.05, 0.05), -HY + 0.12 + random.uniform(-0.06, 0.1), 0.06), (random.uniform(-0.2, 0.5), random.uniform(-0.3, 0.3), random.uniform(0, 6)), 0.19)

# Lock: a heavy brass plate with an eye ------------------------------------------------------------------------------
PLATE = [(-0.98, 0.3), (-0.74, 0.56), (-0.3, 0.62), (0, 0.7), (0.3, 0.62), (0.74, 0.56), (0.98, 0.3), (0.94, -0.18), (0.62, -0.56), (0, -0.86), (-0.62, -0.56), (-0.94, -0.18)]


def prism(poly, y_back, y_front, inset, mat, center, jitter=0.014):
    """Polygon plate with a fat chamfer, subdivided so it can be dented."""
    def dense(pts, per=7):
        out = []
        for i, p0 in enumerate(pts):
            p1 = pts[(i + 1) % len(pts)]
            for k in range(per):
                t = k / per
                out.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
        return out
    d = dense(poly)
    n = len(d)
    cx = sum(x for x, _ in d) / n
    cz = sum(z for _, z in d) / n
    rings = [(1.0, y_back), (1.0, y_front + inset), (1 - inset * 1.05, y_front), (0.66, y_front - 0.004), (0.33, y_front - 0.006)]
    v, f = [], []
    for k, y in rings:
        for x, z in d:
            v.append((center[0] + cx + (x - cx) * k, y, center[1] + cz + (z - cz) * k))
    for j in range(len(rings) - 1):
        for i in range(n):
            b = (i + 1) % n
            f.append((j * n + i, j * n + b, (j + 1) * n + b, (j + 1) * n + i))
    v.append((center[0] + cx, y_front - 0.006, center[1] + cz))
    for i in range(n):
        f.append(((len(rings) - 1) * n + i, (len(rings) - 1) * n + (i + 1) % n, len(v) - 1))
    return mesh(v, f, mat, 28, jitter, 2.4)


EX, EZ = EYE_LOCAL.x, EYE_LOCAL.z
BIG = 1.17
XF = Matrix.Translation((EX, 0, EZ)) @ Matrix.Diagonal((BIG, 1, BIG, 1)) @ Matrix.Translation((-EX, 0, -EZ))
prism(PLATE, -0.9, -1.1, 0.09, BRASS, (EX, EZ))
prism([(x * 0.86, z * 0.84) for x, z in PLATE], -1.06, -1.13, 0.05, IRON, (EX, EZ), 0.01)
for x, z in ((-0.86, 0.26), (0.86, 0.26), (-0.8, -0.2), (0.8, -0.2), (-0.36, -0.6), (0.36, -0.6), (0, 0.6)):
    rivet((EX + x, -1.1, EZ + z), 0.075, BRASS)

EW, EU, ED = 0.72, 0.36, 0.43


def almond(t, grow=0.0):
    c, s = math.cos(t), math.sin(t)
    w, h = EW + grow, (EU if s > 0 else ED) + grow
    x = w * abs(c) ** 0.86 * (1 if c >= 0 else -1)
    z = h * abs(s) ** 1.25 * (1 if s >= 0 else -1)
    return x, z + 0.1 * (abs(x) / EW) ** 1.6


# lids: thick dragon hide folded around the eye
N, M, v, f = 120, 12, [], []
for j in range(M + 1):
    u = j / M
    for i in range(N):
        t = 2 * math.pi * i / N
        x, z = almond(t, 0.145 * u)
        fold = 0.02 * math.sin(u * 13) + 0.012 * math.sin(t * 34) * math.sin(math.pi * u)
        v.append((EX + x, -1.13 - 0.16 * math.sin(math.pi * min(1, 0.22 + u * 0.78)) - fold, EZ + z))
for j in range(M):
    for i in range(N):
        b = (i + 1) % N
        f.append((j * N + i, j * N + b, (j + 1) * N + b, (j + 1) * N + i))
mesh(v, f, HIDE, 60, 0.02, 3.2)
# the ball
XF = None
v, f, R, S = [], [], 24, 80
for j in range(R + 1):
    r = 0.78 * j / R
    for i in range(S):
        a = 2 * math.pi * i / S
        v.append((r * math.cos(a), -0.2 * math.cos(min(1, r / 0.78) * math.pi / 2), 0.66 * r * math.sin(a)))
for j in range(R):
    for i in range(S):
        b = (i + 1) % S
        f.append((j * S + i, j * S + b, (j + 1) * S + b, (j + 1) * S + i))
ball = mesh(v, f, IRIS, 80)
ball.matrix_world = ROOT @ Matrix.Translation((EX, -1.09, EZ)) @ Matrix.Diagonal((BIG, 1, BIG, 1))
XF = Matrix.Translation((EX, 0, EZ)) @ Matrix.Diagonal((BIG, 1, BIG, 1)) @ Matrix.Translation((-EX, 0, -EZ))


def shape(points, y, mat, dy=0.02):
    n = len(points)
    v = [(x, y, z) for x, z in points] + [(x, y + dy, z) for x, z in points]
    f = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return mesh(v, f, mat, 30)


def keyhole(k, dz=0.0):
    pts = [(0.15 * k * math.cos(math.radians(a)), 0.1 + 0.15 * k * math.sin(math.radians(a))) for a in range(-60, 241, 10)]
    pts += [(-0.075 * k, -0.06), (-0.135 * k - 0.01, -0.335 * (1 + (k - 1) * 0.5)), (0.135 * k + 0.01, -0.335 * (1 + (k - 1) * 0.5)), (0.075 * k, -0.06)]
    return [(EX + x, EZ + z + dz - 0.005) for x, z in pts]


shape(keyhole(1.2), -1.31, flat("key edge", "fff0c0"), 0.01)
shape(keyhole(1.0), -1.325, flat("key hole", "0a0308"), 0.01)
# a spark of gold deep inside
shape([(EX - 0.07, EZ - 0.26), (EX + 0.07, EZ - 0.26), (EX + 0.03, EZ - 0.12), (EX - 0.03, EZ - 0.12)], -1.33, flat("key spark", "8a4a10"), 0.004)
# painted catchlights
for cx, cz, w, h, rr in ((-0.28, 0.15, 0.07, 0.03, 0.5),):
    shape([(EX + cx + w * math.cos(a) * math.cos(rr) - h * math.sin(a) * math.sin(rr), EZ + cz + w * math.cos(a) * -math.sin(rr) * -1 * 0.6 + h * math.sin(a) * math.cos(rr))
           for a in [2 * math.pi * i / 20 for i in range(20)]], -1.335, flat("spark", "f6e6ff"), 0.004)
no_ink = bpy.data.collections.new("no ink")
no_ink.objects.link(scene.collection.objects[-1])


# brow: two slabs of iron that frown
def slab(side):
    """One half of the brow: a thick wedge of brass, wide in the middle, that rises to a point."""
    n, v, f = 24, [], []
    for i in range(n):
        q = i / (n - 1)
        x = -0.03 + 1.1 * q
        z = 0.3 + 0.2 * q + 0.27 * q ** 2.4
        w = 0.29 * (1 - q) ** 0.8 + 0.015
        y = -1.3 + 0.2 * q ** 1.5
        dz, dx = 0.2 + 0.27 * 2.4 * q ** 1.4, 1.1
        l = math.hypot(dx, dz)
        nx, nz = -dz / l, dx / l
        for o, d in ((0.0, 0.12), (0.0, -0.02), (0.22, -0.1), (0.72, -0.1), (1.0, 0.0), (1.0, 0.12)):
            v.append((EX + side * (x + nx * w * o), y + d * (1 - 0.5 * q), EZ + z + nz * w * o))
    for i in range(n - 1):
        for k in range(6):
            c = (k + 1) % 6
            f.append((i * 6 + k, i * 6 + c, (i + 1) * 6 + c, (i + 1) * 6 + k))
    f += [tuple(range(6)), tuple(range((n - 1) * 6, n * 6))]
    mesh(v, f, BRASS, 26, 0.012, 2.6)


slab(1)
slab(-1)
prism([(0, 0.27), (0.17, 0.06), (0.11, -0.1), (0, -0.17), (-0.11, -0.1), (-0.17, 0.06)], -1.2, -1.47, 0.1, BRASS, (EX, EZ + 0.5), 0.008)
rivet((EX, -1.47, EZ + 0.53), 0.075, IRON)


XF = None
# Horns --------------------------------------------------------------------------------------------------------------
def catmull(pts, per):
    out, n = [], len(pts)
    for i in range(n - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n - 1)]
        for k in range(per):
            t = k / per
            out.append(Vector([0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3)
                               for a, b, c, d in zip(p0, p1, p2, p3)]))
    out.append(Vector(pts[-1]))
    return out


def horn(side):
    path = catmull([(side * 1.2, 0.0, 0.5), (side * 1.62, -0.06, 0.56), (side * 1.98, -0.2, 0.9), (side * 1.98, -0.36, 1.42), (side * 1.62, -0.46, 1.86)], 22)
    n, S, v, f = len(path), 22, [], []
    for i, q in enumerate(path):
        u = i / (n - 1)
        tan = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        a1 = Vector((0, 1, 0))
        a2 = tan.cross(a1).normalized()
        step = (u * 9) % 1.0
        rad = 0.3 * (1 - u) ** 0.68 * (1 + 0.15 * (1 - step) ** 1.4 * (1 - u)) + 0.012
        for k in range(S):
            a = 2 * math.pi * k / S
            rr = rad * (1 + 0.07 * math.sin(2 * a + 1))
            v.append(tuple(q + a1 * (math.cos(a) * rr) + a2 * (math.sin(a) * rr)))
    for i in range(n - 1):
        for k in range(S):
            b = (k + 1) % S
            f.append((i * S + k, i * S + b, (i + 1) * S + b, (i + 1) * S + k))
    f += [tuple(range(S)), tuple(range((n - 1) * S, n * S))]
    mesh(v, f, BONE, 34, 0.03, 2.2, LID)
    for u0, rad, thick in ((0.03, 0.37, 0.15), (0.13, 0.35, 0.09)):
        i = int(u0 * (n - 1))
        tan = (path[i + 1] - path[max(0, i - 1)]).normalized()
        a1 = Vector((0, 1, 0))
        a2 = tan.cross(a1).normalized()
        vv, ff, K = [], [], 30
        prof = ((0.9, -1), (1.0, -0.8), (1.04, 0), (1.0, 0.8), (0.9, 1))
        for pr, ph in prof:
            for k in range(K):
                a = 2 * math.pi * k / K
                vv.append(tuple(path[i] + tan * (ph * thick) + a1 * (math.cos(a) * rad * pr) + a2 * (math.sin(a) * rad * pr)))
        for j in range(len(prof) - 1):
            for k in range(K):
                b = (k + 1) % K
                ff.append((j * K + k, j * K + b, (j + 1) * K + b, (j + 1) * K + k))
        ff += [tuple(range(K)), tuple(range((len(prof) - 1) * K, len(prof) * K))]
        mesh(vv, ff, IRON if thick > 0.1 else BRASS, 30, 0.014, 3, LID)


horn(1)
horn(-1)

# Coins on the floor: few and big -------------------------------------------------------------------------------------
FLOOR = -H - 0.2
heap = random.Random(23)
for cx, cy, count, spread in ((-1.35, -1.25, 17, 0.42), (1.3, -1.2, 15, 0.4)):
    for i in range(count):
        u = i / count
        a = heap.uniform(0, 6.28)
        d = spread * (1 - u * 0.75) * heap.uniform(0.3, 1.0)
        coin((cx + d * math.cos(a) * 1.15, cy + d * math.sin(a) * 0.75, FLOOR + 0.04 + 0.34 * u), (heap.gauss(0.22, 0.2), heap.gauss(0, 0.25), heap.uniform(-0.6, 0.6)),
             heap.uniform(0.21, 0.25))
for x, y, rz in ((-0.6, -1.66, 0.2), (-0.15, -1.78, -0.3), (0.42, -1.72, 0.4), (0.86, -1.62, -0.2)):
    coin((x, y, FLOOR + 0.03), (heap.gauss(0.08, 0.08), heap.gauss(0, 0.1), rz), 0.22)
coin((-1.74, -0.95, FLOOR + 0.27), (1.25, 0.0, 0.3), 0.25)
coin((1.72, -0.92, FLOOR + 0.26), (1.2, 0.1, -0.3), 0.25)
coin((0.98, -1.46, FLOOR + 0.2), (1.0, 0.25, -0.15), 0.25)

# Camera -------------------------------------------------------------------------------------------------------------
cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 70
cam = bpy.data.objects.new("cam", cam_data)
cam.location = (0.1, -9.3, 2.1)
cam.rotation_euler = (Vector((0.04, 0, 0.1)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 0
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.view_settings.view_transform = "Standard"
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = OUT
# ink: dark broken outlines
scene.render.use_freestyle = True
scene.render.line_thickness_mode = "ABSOLUTE"
scene.render.line_thickness = 2.6 * SIZE / 1024
fs = scene.view_layers[0].freestyle_settings
fs.crease_angle = math.radians(128)
ls = fs.linesets[0] if fs.linesets else fs.linesets.new("ink")
ls.select_by_collection = True
ls.collection = no_ink
ls.collection_negation = "EXCLUSIVE"
ls.select_silhouette = ls.select_border = ls.select_crease = True
style = ls.linestyle or bpy.data.linestyles.new("ink")
ls.linestyle = style
style.color = lin("0d0609")[:3]
style.alpha = 0.85
style.thickness = 2.6 * SIZE / 1024
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
