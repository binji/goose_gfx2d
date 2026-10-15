// gfx2d's affine transforms and rectangles, without a GPU.
import std;
import vec;
import math;
import gfx2d from "../..";

fn near(a: float2, b: float2) -> bool { abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001 }

fn near(m: gfx2d::Affine, n: gfx2d::Affine) -> bool {
    near(float2 { m.a, m.b }, float2 { n.a, n.b }) && near(float2 { m.c, m.d }, float2 { n.c, n.d })
        && near(float2 { m.tx, m.ty }, float2 { n.tx, n.ty })
}

// Rounded to a thousandth, so libm's last bits do not show.
fn rounded(v: float2) -> float2 { float2 { round(v.x * 1000) / 1000, round(v.y * 1000) / 1000 } }
fn rounded(r: gfx2d::Rect) -> gfx2d::Rect {
    let p = rounded(float2 { r.x, r.y });
    let q = rounded(float2 { r.w, r.h });
    gfx2d::Rect { p.x, p.y, q.x, q.y }
}

fn main() {
    let p = float2 { 3, 4 };
    print("translation: ", gfx2d::apply(gfx2d::translation(10, 20), p));
    print("scaling: ", gfx2d::apply(gfx2d::scaling(2, 3), p));
    // y is down, so a quarter turn takes +x to +y: clockwise on the screen.
    print("rotation: ", near(gfx2d::apply(gfx2d::rotation(PI / 2), float2 { 1, 0 }),
                             float2 { 0, 1 }));
    print("rotation_about: ", near(gfx2d::apply(gfx2d::rotation_about(PI, 5, 5), float2 { 6, 5 }),
                                   float2 { 4, 5 }));
    print("skewing: ", near(gfx2d::apply(gfx2d::skewing(PI / 4, 0), float2 { 0, 2 }),
                            float2 { 2, 2 }));
    // mul(m, n) applies n first.
    let m = gfx2d::mul(gfx2d::translation(10, 0), gfx2d::scaling(2));
    print("mul: ", gfx2d::apply(m, p), " ", gfx2d::apply_vector(m, p));
    let t = gfx2d::mul(gfx2d::mul(gfx2d::translation(7, -3), gfx2d::rotation(0.7)),
                       gfx2d::mul(gfx2d::skewing(0.2, 0.1), gfx2d::scaling(1.5, 0.5)));
    let inv, ok = gfx2d::invert(t);
    print("invert: ", ok, " ", near(gfx2d::mul(t, inv), gfx2d::IDENTITY), " ",
          near(gfx2d::apply(inv, gfx2d::apply(t, p)), p));
    let _, flat = gfx2d::invert(gfx2d::scaling(0, 1));
    print("invert a flat matrix: ", flat);
    print("determinant: ", gfx2d::determinant(gfx2d::scaling(2, 3)), " angle ",
          abs(gfx2d::angle_of(gfx2d::rotation(0.5)) - 0.5) < 0.0001, " scales ",
          rounded(gfx2d::axis_scales(gfx2d::mul(gfx2d::rotation(1), gfx2d::scaling(2, 3)))));

    let r = gfx2d::Rect { 10, 10, 20, 10 };
    let s = gfx2d::Rect { 20, 0, 20, 15 };
    print("rects: ", gfx2d::center(r), " ", gfx2d::contains(r, float2 { 29, 19 }), " ",
          gfx2d::contains(r, float2 { 30, 19 }), " ", gfx2d::intersect(r, s), " ",
          gfx2d::union(r, s), " ", gfx2d::inflate(r, 2));
    print("bounds: ", rounded(gfx2d::transformed_bounds(gfx2d::rotation_about(PI / 2, 20, 15), r)));
    let src = gfx2d::Rect { 0, 0, 100, 50 };
    let dst = gfx2d::Rect { 0, 0, 200, 200 };
    print("fit: ", gfx2d::transformed_bounds(gfx2d::fit(src, dst, gfx2d::FIT_STRETCH), src), " ",
          gfx2d::transformed_bounds(gfx2d::fit(src, dst, gfx2d::FIT_CONTAIN), src), " ",
          gfx2d::transformed_bounds(gfx2d::fit(src, dst, gfx2d::FIT_COVER), src));

    // Hit testing, in the shape's own space.
    print("in_rect: ", gfx2d::in_rect(10, 10, 20, 10, float2 { 15, 15 }), " ",
          gfx2d::in_rect(10, 10, 20, 10, float2 { 30, 15 }), " flipped ",
          gfx2d::in_rect(30, 20, -20, -10, float2 { 15, 15 }));
    print("in_rounded_rect: ", gfx2d::in_rounded_rect(0, 0, 100, 50, 20, float2 { 50, 25 }), " corner ",
          gfx2d::in_rounded_rect(0, 0, 100, 50, 20, float2 { 2, 2 }), " edge ",
          gfx2d::in_rounded_rect(0, 0, 100, 50, 20, float2 { 50, 1 }));
    print("in_circle: ", gfx2d::in_circle(0, 0, 10, float2 { 7, 7 }), " ", gfx2d::in_circle(0, 0, 10, float2 { 8, 7 }),
          "; in_ellipse: ", gfx2d::in_ellipse(0, 0, 20, 5, float2 { 19, 0 }), " ",
          gfx2d::in_ellipse(0, 0, 20, 5, float2 { 0, 6 }));

    // A camera: its center in the middle of the viewport, zoomed, turned;
    // and back.
    let view = gfx2d::Rect { 0, 0, 800, 600 };
    let cam = gfx2d::Camera2D { center: float2 { 100, 50 }, zoom: 2, rotation: PI / 2 };
    print("camera: center to ", rounded(gfx2d::world_to_screen(cam, view, float2 { 100, 50 })),
          ", a unit right of it to ", rounded(gfx2d::world_to_screen(cam, view, float2 { 101, 50 })));
    let back = gfx2d::screen_to_world(cam, view, gfx2d::world_to_screen(cam, view, float2 { 123, -45 }));
    print("and back: ", rounded(back));
}
