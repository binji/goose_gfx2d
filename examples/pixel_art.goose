// gfx2d's pixel-art tools: a 160 x 90 canvas scaled up by whole numbers to
// the window, a camera that follows a character over a tile map, a sprite
// drawn nearest, and the tile under the mouse found through the canvas and
// the camera.
//
//   goose examples/pixel_art.goose
//   goose examples/pixel_art.goose -- --frames 60 --screenshot pixel_art.png
//
// The arrow keys move; the tile under the mouse is outlined. Escape quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

let CW = 160;
let CH = 90;
let TILE = 8;
let MAP_W = 48;
let MAP_H = 24;

fn tile_at(x: i64, y: i64) -> i64 {
    if x == 0 || y == 0 || x == MAP_W - 1 || y == MAP_H - 1 { return 2; }        // wall
    let h = ((x * 73856093) ^ (y * 19349663)) % 17;
    if h == 0 { return 2; }
    if h < 4 { return 1; }                                                      // flowers
    0                                                                           // grass
}

fn main() {
    var frames = -1;
    var screenshot: u8[>..] = [];
    let argv = args();
    var i = 1;
    while i + 1 < argv.len {
        if argv[i] == "--frames" {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames = n; }
        } else if argv[i] == "--screenshot" {
            screenshot.append(argv[i + 1]);
        }
        i += 2;
    }
    guard gfx::open("gfx2d: pixel art", 960, 540, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    // An 8 x 8 character, from a picture in text.
    let picture = ["..XXXX..", ".XooooX.", "XoWooWoX", "XooooooX", ".XoooX..", "..XXXX..", ".X.XX.X.", "X......X"];
    let sprite = gfx::texture2d(8, 8);
    var data: u8[>..] = [];
    for row in picture {
        for c in row {
            let v: u32 = if c == 'X' { 0xFF1D2B53 } else if c == 'o' { 0xFFFF77A8 } else if c == 'W' { 0xFFFFF1E8 }
                         else { 0x00000000 };
            data.append([((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8, (v >> 24) as u8]);
        }
    }
    gfx::update_texture(sprite, data);

    var hero = float2 { 40, 40 };
    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let speed: f32 = 1.0;
        if gfx::key_down("Left") { hero.x -= speed; }
        if gfx::key_down("Right") { hero.x += speed; }
        if gfx::key_down("Up") { hero.y -= speed; }
        if gfx::key_down("Down") { hero.y += speed; }
        if frames >= 0 { hero = float2 { 40 + drawn, 40 + drawn / 2 }; }   // a scripted walk
        // The camera follows the hero, on whole pixels, inside the map.
        let cam = gfx2d::Camera2D { center: float2 {
            clamp(round(hero.x), CW / 2.0, MAP_W * TILE - CW / 2),
            clamp(round(hero.y), CH / 2.0, MAP_H * TILE - CH / 2) } };
        // The mouse, from the window to the canvas to the world.
        let world_mouse = gfx2d::screen_to_world(cam, gfx2d::rect_of(0, 0, CW, CH),
                                                 gfx2d::to_canvas(gfx::mouse_pos(), CW, CH));
        let mx = floor(world_mouse.x / TILE) as i64;
        let my = floor(world_mouse.y / TILE) as i64;

        gfx2d::frame(gfx2d::rgb(0x000000)) {
            gfx2d::pixel_canvas(CW, CH, gfx2d::rgb(0x1D2B53)) {
                gfx2d::camera(cam) {
                    for ty in MAP_H {
                        for tx in MAP_W {
                            let x = tx * TILE;
                            let y = ty * TILE;
                            match tile_at(tx, ty) {
                                2 => {
                                    gfx2d::rect(x, y, TILE, TILE, gfx2d::rgb(0x5F574F));
                                    gfx2d::rect(x, y, TILE, 1, gfx2d::rgb(0xC2C3C7));
                                },
                                1 => {
                                    gfx2d::rect(x, y, TILE, TILE, gfx2d::rgb(0x008751));
                                    gfx2d::rect(x + 3, y + 3, 2, 2, gfx2d::rgb(0xFFEC27));
                                },
                                _ => gfx2d::rect(x, y, TILE, TILE, gfx2d::rgb(0x00A65C)),
                            }
                        }
                    }
                    if mx >= 0 && my >= 0 && mx < MAP_W && my < MAP_H {
                        gfx2d::rect_outline(mx * TILE + 0.5, my * TILE + 0.5, TILE - 1, TILE - 1, 1, gfx2d::WHITE);
                    }
                    gfx2d::image(sprite, round(hero.x) - 4, round(hero.y) - 4);
                };
            };
            // A HUD over the canvas, at the window's resolution: text of a
            // few canvas pixels, drawn hard-edged from its distance field,
            // would not be legible (a bitmap font is for that).
            let fit = gfx2d::pixel_canvas_fit(CW, CH);
            gfx2d::rounded_rect(fit.tx + 8, fit.ty + 8, 150, 30, 6, gfx2d::rgba(0x000000, 0.6));
            gfx2d::text(fit.tx + 18, fit.ty + 14, str("tile ", mx, ", ", my), 16, gfx2d::rgb(0xFFF1E8));
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
