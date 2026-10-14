// The mesh pipeline's vertex shader: triangles gfx2d.goose tessellated from
// paths, already in pixels, each vertex with the point in the space it was
// drawn in (for its paint), its color, its coverage and its paint.

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_user;
layout(location = 2) in vec4 a_color;
layout(location = 3) in float a_alpha;
layout(location = 4) in uint a_paint;

layout(set = 1, binding = 0) uniform Frame { vec4 view; uint base; };

layout(location = 0) out vec2 v_user;
layout(location = 1) flat out vec4 v_color;
layout(location = 2) out float v_alpha;
layout(location = 3) flat out uint v_paint;

void main() {
    gl_Position = vec4(a_pos.x / view.x * 2.0 - 1.0, 1.0 - a_pos.y / view.y * 2.0, 0.0, 1.0);
    v_user = a_user;
    v_color = a_color;
    v_alpha = a_alpha;
    v_paint = a_paint;
}
