// Breakout, with the blocks sinking: the wall creeps down, a new row slides
// in at the top each time it has sunk a row, and a block reaching the
// paddle's line ends the game. Every few rows one comes in empty, a row
// may miss a block or two, and some blocks are powerups: breaking one
// puts another ball on the paddle, launched whenever you like, while the
// others fly, and shows that ball, with a shine running around its
// edge. A block that takes more hits wears a ring for each hit left.
//
// Written to use the library's layers, paints, paths and text where a game
// would:
//
//   * the field is drawn at a base scale (set_scale) fitting the window,
//     with the mouse mapped back into field units by mouse_local;
//   * the balls glow through a blurred additive layer, and the whole scene
//     blurs behind the pause and game-over cards (layer blur);
//   * blocks are gradient-painted rounded rects, with a drop shadow from a
//     layer, and slide in under a clip nested in the field's rounded clip;
//   * a ball's trail is a translucent polyline with round joins, the
//     danger line a dashed stroke whose dashes crawl (dash_offset), and a
//     powerup's shine one dash of a rounded-rect path, chasing its outline;
//   * a broken block shatters into pieces of itself; the stars that greet
//     a new ball are one star path tessellated once (tessellate) and
//     drawn many times (draw(mesh));
//   * the score text has an outline, and the cards' text is centered
//     within a wrap box.
//
//   goose examples/breakout.goose
//   goose examples/breakout.goose -- --frames 600 --screenshot breakout.png
//
// Mouse or Left/Right move the paddle; Space or a click launches a ball;
// P pauses; R restarts; Escape quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

// The field, in its own units; the window scales it.
let FW = 480.0;
let FH = 640.0;
let COLS = 8;
let BLOCK_W = 54.0;
let BLOCK_H = 22.0;
let GAP = 6.0;
let ROW_H = BLOCK_H + GAP;
let TOP = 36.0;              // the HUD's band; the blocks come in under it
let PADDLE_Y = FH - 48.0;
let PADDLE_W = 84.0;
let PADDLE_H = 12.0;
let BALL_R = 6.0;
let BALL_SPEED = 330.0;
let TRAIL = 14;

struct Block { x: f64, y: f64, hp: i64, hue: f64, wobble: f64, power: bool, phase: f64 }
struct Ball { x: f64, y: f64, vx: f64, vy: f64, trail: float2[14], trail_n: i64, trail_at: i64 }
// A shard: a star, or a piece of a shattered block (w by h, a rounded rect).
struct Shard { pos: float2, vel: float2, spin: f64, angle: f64, life: f64, size: f64, color: gfx2d::Color,
               w: f64 = 0.0, h: f64 = 0.0 }

var random = rng { 0x5EED };
fn v(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }
fn rand() -> f64 { rand_flt(random) }
fn rand(lo: f64, hi: f64) -> f64 { lo + (hi - lo) * rand() }

var blocks: Block[>..<] = [];
var balls: Ball[>..<] = [];     // the balls in flight
var shards: Shard[>..<] = [];
var paddle_x = FW / 2;
var riding = true;              // a ball waits on the paddle
var stock = 0;                  // balls from powerups, queued behind it
var arrived = 0.0;              // a ball just put on the paddle: its ripple, fading
var lives = 3;
var score = 0;
var combo = 0;
var best_combo = 0;
var sink = 0.0;                 // how far the wall has sunk since the last row came in
var rows_in = 0;
var next_empty = 0;             // the row (counting rows_in) that comes in empty
var played = 0.0;               // seconds of play
var paused = false;
var over = false;
var shake = 0.0;
var flash = 0.0;                // a white flash on losing the balls
var shard_mesh: gfx2d::Mesh;
var autopilot = false;

// The wall sinks slowly, a little faster as the game goes on.
fn sink_speed() -> f64 { 2.2 + played * 0.08 }

fn add_row(y: f64) {
    if rows_in == next_empty {
        // An empty row, for a ball to get in between: every 4 to 8 rows.
        next_empty = rows_in + 4 + rand_int(random, 5);
        rows_in++;
        return;
    }
    let hue = rand(0, 360);
    for i in COLS {
        if rand() < 0.07 { continue; }          // a block missing, now and then
        // Tougher blocks get commoner as rows come in.
        let r = rand();
        let hp = if r < 0.12 + rows_in * 0.01 { 3 } else if r < 0.4 + rows_in * 0.01 { 2 } else { 1 };
        // A powerup about every two or three rows, broken in one hit.
        let power = rand() < 0.05;
        blocks.push(Block { GAP + i * (BLOCK_W + GAP), y, if power { 1 } else { hp }, hue + i * 9, 0.0, power,
                            rand() });
    }
    rows_in++;
}

fn new_game() {
    blocks.resize(0);
    balls.resize(0);
    shards.resize(0);
    riding = true;
    stock = 0;
    lives = 3;
    score = 0;
    combo = 0;
    best_combo = 0;
    sink = 0.0;
    rows_in = 0;
    next_empty = 4 + rand_int(random, 5);
    played = 0.0;
    over = false;
    paused = false;
    for r in 5 { add_row(TOP + GAP + r * ROW_H); }
}

// Another ball for the paddle: on it now, if it is bare, or queued.
fn stock_ball() {
    if riding { stock++; } else { arrive(); }
}
fn arrive() {
    riding = true;
    arrived = 1.0;
    for i in 8 {
        let a = -PI / 2 + rand(-1.2, 1.2);
        let sp = rand(80, 200);
        shards.push(Shard { v(paddle_x, PADDLE_Y - BALL_R - 1), v(cos(a) * sp, sin(a) * sp), rand(-10, 10),
                            rand(0, TAU), rand(0.4, 0.7), rand(4, 7), gfx2d::rgb(0xFFF1A8) });
    }
}

// A ball sent up from the paddle, at a random angle from straight up; the
// next queued one takes its place.
fn launch() {
    riding = false;
    if stock > 0 { stock--; arrive(); }
    let a = -PI / 2 + rand(-0.5, 0.5);
    balls.push(Ball { paddle_x, PADDLE_Y - BALL_R - 1, cos(a) * BALL_SPEED, sin(a) * BALL_SPEED,
                      [float2 { 0, 0 }; 14], 0, 0 });
}

fn block_color(b: Block) -> gfx2d::Color {
    gfx2d::oklch(0.8 - (b.hp - 1) * 0.14, 0.14 + (b.hp - 1) * 0.03, b.hue)
}

// The block shattered: 4 by 2 pieces, each from where it was in the block,
// flung out from the block's center and up, spinning, as the stars are.
fn burst(b: Block) {
    let c = block_color(b);
    let pw = BLOCK_W / 4;
    let ph = BLOCK_H / 2;
    for j in 2 {
        for i in 4 {
            let cx = b.x + (i + 0.5) * pw;
            let cy = b.y + (j + 0.5) * ph;
            let a = atan2(cy - (b.y + BLOCK_H / 2), cx - (b.x + BLOCK_W / 2)) + rand(-0.6, 0.6);
            let s = rand(60, 220);
            // The top pieces lighter, the bottom darker, as the block's gradient was.
            let shade = if j == 0 { gfx2d::lighten(c, 0.08) } else { gfx2d::darken(c, 0.08) };
            shards.push(Shard { v(cx, cy), v(cos(a) * s, sin(a) * s - 90), rand(-12, 12), 0.0, rand(0.6, 1.0),
                                1.0, shade, pw - 1, ph - 1 });
        }
    }
}

// The ball against one block: which side it came through, by the least
// overlap, and the bounce.
fn hit_block(ball: Ball&, b: Block) -> bool {
    let nx = clamp(ball.x, b.x, b.x + BLOCK_W);
    let ny = clamp(ball.y, b.y, b.y + BLOCK_H);
    let dx = ball.x - nx;
    let dy = ball.y - ny;
    if dx * dx + dy * dy > BALL_R * BALL_R { return false; }
    // Push out along the shallower axis, and reflect that velocity.
    let ox = if ball.x < b.x + BLOCK_W / 2 { ball.x + BALL_R - b.x } else { b.x + BLOCK_W - (ball.x - BALL_R) };
    let oy = if ball.y < b.y + BLOCK_H / 2 { ball.y + BALL_R - b.y } else { b.y + BLOCK_H - (ball.y - BALL_R) };
    if ox < oy {
        ball.vx = -ball.vx;
        ball.x += if ball.x < b.x + BLOCK_W / 2 { -ox } else { ox };
    } else {
        ball.vy = -ball.vy;
        ball.y += if ball.y < b.y + BLOCK_H / 2 { -oy } else { oy };
    }
    true
}

// One ball for one frame: walls, the paddle, the blocks; false once it has
// fallen out.
fn step_ball(ball: Ball&, dt: f64) -> bool {
    // In small steps, so it cannot skip a block.
    var left = dt;
    while left > 0 {
        let h = min(left, 1.0 / 240.0);
        left -= h;
        ball.x += ball.vx * h;
        ball.y += ball.vy * h;
        if ball.x < BALL_R { ball.x = BALL_R; ball.vx = abs(ball.vx); }
        if ball.x > FW - BALL_R { ball.x = FW - BALL_R; ball.vx = -abs(ball.vx); }
        if ball.y < BALL_R { ball.y = BALL_R; ball.vy = abs(ball.vy); }
        // The paddle: the bounce angle from where it is struck.
        if ball.vy > 0 && ball.y + BALL_R >= PADDLE_Y && ball.y - BALL_R <= PADDLE_Y + PADDLE_H &&
           abs(ball.x - paddle_x) <= PADDLE_W / 2 + BALL_R {
            let where = clamp((ball.x - paddle_x) / (PADDLE_W / 2), -1.0, 1.0);
            let a = -PI / 2 + where * 1.1;
            let speed = min(BALL_SPEED + played * 1.5, 520.0);
            ball.vx = cos(a) * speed;
            ball.vy = sin(a) * speed;
            ball.y = PADDLE_Y - BALL_R;
            combo = 0;
        }
        var i = 0;
        while i < blocks.len {
            if hit_block(ball, blocks[i]) {
                blocks[i].hp--;
                blocks[i].wobble = 1.0;
                combo++;
                best_combo = max(best_combo, combo);
                score += 10 * combo;
                if blocks[i].hp <= 0 {
                    burst(blocks[i]);
                    if blocks[i].power { stock_ball(); }
                    blocks[i] = blocks[blocks.len - 1];
                    blocks.resize(blocks.len - 1);
                } else {
                    i++;
                }
                break;
            }
            i++;
        }
    }
    // The trail: a ring of the last positions.
    ball.trail[ball.trail_at] = v(ball.x, ball.y);
    ball.trail_at = (ball.trail_at + 1) % TRAIL;
    ball.trail_n = min(ball.trail_n + 1, TRAIL);
    ball.y < FH + BALL_R * 2
}

// What fades whether or not the game runs: the shake (which the end
// sets, and which dies down over a couple of seconds), the flash, the
// ripple, and the shards' flight.
fn fade(dt: f64) {
    shake = max(shake - dt * 0.6, 0.0);
    flash = max(flash - dt * 2, 0.0);
    arrived = max(arrived - dt * 1.6, 0.0);
    for &s in shards {
        s.life -= dt;
        s.vel.y += (500 * dt) as f32;
        s.pos = s.pos + s.vel * (dt as f32);
        s.angle += s.spin * dt;
    }
    var w = 0;
    for s in shards {
        if s.life > 0 { shards[w] = s; w++; }
    }
    shards.resize(w);
}

fn step(dt: f64) {
    played += dt;

    // The paddle follows the mouse when it moves, and the keys otherwise.
    let mouse = gfx2d::mouse_local();
    if length(gfx::mouse_delta()) > 0 { paddle_x = mouse.x; }
    if gfx::key_down("Left") { paddle_x -= 520 * dt; }
    if gfx::key_down("Right") { paddle_x += 520 * dt; }
    if autopilot && balls.len > 0 { paddle_x = balls[0].x + sin(played * 3) * 20; }   // a recording plays itself
    paddle_x = clamp(paddle_x, PADDLE_W / 2, FW - PADDLE_W / 2);

    // The wall sinks; a row comes in at the top when it has sunk one.
    let dy = sink_speed() * dt;
    for &b in blocks { b.y += dy; }
    sink += dy;
    if sink >= ROW_H {
        sink -= ROW_H;
        add_row(TOP + GAP - ROW_H + sink);
    }
    for b in blocks {
        if b.y + BLOCK_H >= PADDLE_Y - 2 && !over { over = true; shake = 1.0; }
    }

    // A launch of the ball on the paddle, while others may fly.
    let fire = gfx::key_pressed("Space") || gfx::mouse_pressed(gfx::MOUSE_LEFT) || (autopilot && rand() < 0.01);
    if fire && riding { launch(); }

    var w = 0;
    for &ball in balls {
        if step_ball(ball, dt) { balls[w] = ball; w++; }
    }
    balls.resize(w);
    if balls.len == 0 && !riding {
        // The last ball lost: a life.
        lives--;
        flash = 1.0;
        shake = 0.6;
        if lives <= 0 { over = true; }
        riding = true;
    }

    for &b in blocks { b.wobble = max(b.wobble - dt * 4, 0.0); }
}

fn draw_ball(x: f64, y: f64) {
    gfx2d::circle(x, y, BALL_R, gfx2d::radial(x - 2, y - 2, BALL_R * 1.6, gfx2d::WHITE, gfx2d::rgb(0xF4A261)));
}

fn draw_field(t: f64) {
    // The backdrop: a radial glow, and a faint grid.
    gfx2d::rect(0, 0, FW, FH, gfx2d::radial(FW / 2, FH * 0.35, FH * 0.9, gfx2d::rgb(0x2B2D5B), gfx2d::rgb(0x0E0F22)));
    let faint = gfx2d::rgba(0xFFFFFF, 0.05);
    for i in 1..(FW / 40) as i64 { gfx2d::line(i * 40, 0, i * 40, FH, 1, faint); }
    for j in 1..(FH / 40) as i64 { gfx2d::line(0, j * 40, FW, j * 40, 1, faint); }

    // The blocks: gradient-painted, with one drop shadow for all of them,
    // and sliding in from under the HUD's band (a clip inside the field's).
    gfx2d::clip_rect(0, TOP, FW, FH - TOP) {
        gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.45), shadow_offset: float2 { 0, 5 },
                                        shadow_blur: 5 }) {
            for b in blocks {
                let c = block_color(b);
                let bump = sin(b.wobble * PI) * 3;
                gfx2d::rounded_rect(b.x - bump / 2, b.y - bump / 2, BLOCK_W + bump, BLOCK_H + bump, 6,
                                    gfx2d::linear(b.x, b.y, b.x, b.y + BLOCK_H, gfx2d::lighten(c, 0.12),
                                                  gfx2d::darken(c, 0.12)));
            }
        };
        // A tougher block's barrier: a faint ring just outside it for each
        // hit left beyond the first, one around the other. Analytic
        // outlines: tessellating a translucent stroke of each every frame
        // costs more than the rest of the block.
        for b in blocks {
            let rings = b.hp - 1;
            for k in rings {
                let out = 2.5 + k * 2.5;
                gfx2d::rounded_rect_outline(b.x - out, b.y - out, BLOCK_W + 2 * out, BLOCK_H + 2 * out, 6 + out, 1.5,
                                            gfx2d::rgba(0xFFFFFF, 0.14));
            }
        }
        // The powerups: the ball one holds shown in the block over a pulse
        // of light, and a shine chasing around its edge (one dash of the
        // outline's length, its offset moving with time). The shapes first
        // and the strokes after, so each makes one batch, not one draw
        // call a block.
        for b in blocks {
            if !b.power { continue; }
            let pulse = 0.5 + 0.5 * sin(t * 4 + b.phase * TAU);
            gfx2d::box_shadow(b.x, b.y, BLOCK_W, BLOCK_H, 6, 10 + pulse * 6, gfx2d::rgba(0xFFFFFF, 0.2 + pulse * 0.15));
            draw_ball(b.x + BLOCK_W / 2, b.y + BLOCK_H / 2);
        }
        var edge = gfx2d::Path {};
        for b in blocks {
            if !b.power { continue; }
            gfx2d::clear(edge);
            gfx2d::rounded_rect(edge, b.x - 2.5, b.y - 2.5, BLOCK_W + 5, BLOCK_H + 5, 8);
            let around = 2 * (BLOCK_W + 5 + BLOCK_H + 5) - 8 * 8 + TAU * 8;
            gfx2d::stroke(edge, gfx2d::Stroke { width: 2.5, cap: gfx2d::CAP_ROUND, dash: [18, around - 18],
                                                dash_offset: -t * 90 - b.wobble * 40 - b.phase * around },
                          gfx2d::rgba(0xFFFFFF, 0.9));
        }
    };
    gfx2d::line(0, TOP, FW, TOP, 1, gfx2d::rgba(0xFFFFFF, 0.12));

    // The danger line, its dashes crawling toward the paddle's side.
    var danger = gfx2d::Path {};
    gfx2d::move_to(danger, 0, PADDLE_Y - 6);
    gfx2d::line_to(danger, FW, PADDLE_Y - 6);
    gfx2d::stroke(danger, gfx2d::Stroke { width: 2, dash: [10, 8], dash_offset: -t * 30, cap: gfx2d::CAP_ROUND },
                  gfx2d::rgba(0xFF6B6B, 0.55));

    // The paddle: a glow under it, the body a gradient, and a dot on its
    // left end for each ball queued behind the one on it.
    gfx2d::box_shadow(paddle_x - PADDLE_W / 2, PADDLE_Y, PADDLE_W, PADDLE_H, 6, 16, gfx2d::rgba(0x7FDBFF, 0.5));
    gfx2d::rounded_rect(paddle_x - PADDLE_W / 2, PADDLE_Y, PADDLE_W, PADDLE_H, 6,
                        gfx2d::linear(0, PADDLE_Y, 0, PADDLE_Y + PADDLE_H, gfx2d::rgb(0xE8FBFF), gfx2d::rgb(0x7FC4E8)));
    for i in stock {
        gfx2d::circle(paddle_x - PADDLE_W / 2 + 8 + i * 9, PADDLE_Y + PADDLE_H / 2, 3.5, gfx2d::rgb(0xFFD166));
    }

    // The balls' trails: translucent polylines, drawn once where they
    // overlap themselves.
    var pts: float2[>..<] = [];
    for ball in balls {
        if ball.trail_n < 2 { continue; }
        pts.resize(0);
        for i in ball.trail_n { pts.push(ball.trail[(ball.trail_at + TRAIL - ball.trail_n + i) % TRAIL]); }
        gfx2d::polyline(pts, BALL_R * 1.6, gfx2d::rgba(0xFFF1A8, 0.3), gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);
    }
    // The balls, with their glow: the same circles again, blurred and added;
    // a ball just put on the paddle flares, and a ripple spreads from it.
    let rest_y = PADDLE_Y - BALL_R - 1;
    gfx2d::layer(gfx2d::LayerDesc { blur: 7, blend: gfx2d::BLEND_ADD, opacity: 0.9 }) {
        for ball in balls { gfx2d::circle(ball.x, ball.y, BALL_R * 2.2, gfx2d::rgba(0xFFD166, 0.8)); }
        if riding { gfx2d::circle(paddle_x, rest_y, BALL_R * (2.2 + arrived * 4), gfx2d::rgba(0xFFD166, 0.8)); }
    };
    for ball in balls { draw_ball(ball.x, ball.y); }
    if riding {
        draw_ball(paddle_x, rest_y);
        if arrived > 0 {
            let spread = 1 - arrived;
            gfx2d::circle_outline(paddle_x, rest_y, BALL_R + spread * 44, 2.5 - spread * 2,
                                  gfx2d::rgba(0xFFF1A8, arrived));
            gfx2d::circle_outline(paddle_x, rest_y, BALL_R + spread * 26, 2, gfx2d::rgba(0xFFFFFF, arrived * 0.7));
        }
    }

    // Shards. A block's pieces turn and fade; the stars (the one mesh,
    // turning and shrinking) are added to the glow.
    for s in shards {
        if s.w == 0 { continue; }
        gfx2d::translate(s.pos.x, s.pos.y) {
            gfx2d::rotate(s.angle) {
                gfx2d::rounded_rect(-s.w / 2, -s.h / 2, s.w, s.h, 3, gfx2d::with_alpha(s.color, min(s.life * 2, 1.0)));
            };
        };
    }
    if shards.len > 0 {
        gfx2d::layer(gfx2d::LayerDesc { blend: gfx2d::BLEND_ADD }) {
            for s in shards {
                if s.w > 0 { continue; }
                gfx2d::translate(s.pos.x, s.pos.y) {
                    gfx2d::rotate(s.angle) {
                        gfx2d::scale(s.size * min(s.life * 2, 1.0)) {
                            gfx2d::draw(shard_mesh, gfx2d::with_alpha(s.color, min(s.life * 2, 1.0)));
                        };
                    };
                };
            }
        };
    }
}

fn draw_hud() {
    let hud = gfx2d::TextStyle { size: 20 };
    let outlined = gfx2d::TextStyle { size: 20, outline: 1.5 };
    // The score, outlined, over its own text: a dark outline under a light face.
    gfx2d::text(12, 8, str("score ", score), outlined, gfx2d::rgba(0x000000, 0.6));
    gfx2d::text(12, 8, str("score ", score), hud, gfx2d::rgb(0xFFF7E6));
    // Lives, as balls, right-aligned.
    for i in lives { gfx2d::circle(FW - 14 - i * 18, 18, 6, gfx2d::rgb(0xFFD166)); }
    // The combo, when there is one.
    let centered = gfx2d::TextStyle { size: 22, align: gfx2d::ALIGN_CENTER };
    let centered_outline = gfx2d::TextStyle { size: 22, align: gfx2d::ALIGN_CENTER, outline: 1.5 };
    if combo >= 2 {
        gfx2d::text(FW / 2, 8, str("x", combo), centered_outline, gfx2d::rgba(0x000000, 0.6));
        gfx2d::text(FW / 2, 8, str("x", combo), centered, gfx2d::rgb(0xFFD166));
    }
}

// A card over the (blurred) field: a title and lines, centered in a box.
fn card(title: const u8[:], lines: const u8[:]) {
    let w = 300.0;
    let h = 170.0;
    let x = (FW - w) / 2;
    let y = FH * 0.38;
    gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.5), shadow_offset: float2 { 0, 10 },
                                    shadow_blur: 14 }) {
        gfx2d::rounded_rect(x, y, w, h, 18, gfx2d::rgba(0x151633, 0.92));
        gfx2d::rounded_rect_outline(x, y, w, h, 18, 2, gfx2d::rgba(0xFFFFFF, 0.25));
    };
    gfx2d::text(x, y + 26, title, gfx2d::TextStyle { size: 34, align: gfx2d::ALIGN_CENTER, wrap_width: w, outline: 2 },
                gfx2d::rgba(0x000000, 0.7));
    gfx2d::text(x, y + 26, title, gfx2d::TextStyle { size: 34, align: gfx2d::ALIGN_CENTER, wrap_width: w },
                gfx2d::rgb(0xFFD166));
    gfx2d::text(x, y + 84, lines, gfx2d::TextStyle { size: 16, align: gfx2d::ALIGN_CENTER, wrap_width: w,
                                                      line_spacing: 1.3 }, gfx2d::rgb(0xE8E9F3));
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
    guard gfx::open("gfx2d: breakout", 540, 720, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    // The star: tessellated once, at about the size it is drawn around.
    var star = gfx2d::Path {};
    gfx2d::star(star, 0, 0, 1, 0.45, 5);
    shard_mesh = gfx2d::tessellate(star, gfx2d::NONZERO, 8);
    new_game();
    autopilot = frames >= 0;

    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        if gfx::key_pressed("R") { new_game(); }
        if gfx::key_pressed("P") && !over { paused = !paused; }
        let dt = min(gfx::delta_time(), 1.0 / 30.0);
        let t = gfx::time();
        fade(dt);

        // The field fits the window at a base scale, letterboxed.
        let size = gfx::screen_size();
        let s = min(size.x / FW, size.y / FH);
        gfx2d::frame(gfx2d::rgb(0x07081A), 1, s) {
            gfx2d::translate((size.x / s - FW) / 2, (size.y / s - FH) / 2) {
                // The game steps here, under the field's transform, so that
                // mouse_local gives the mouse in field units: the paddle
                // follows it whatever the window's size and shape.
                if !paused && !over { step(dt); }
                // A shake, from a lost ball or the end.
                gfx2d::translate(sin(t * 60) * shake * 5, cos(t * 47) * shake * 4) {
                    let still = paused || over;
                    gfx2d::clip_rounded_rect(0, 0, FW, FH, 14) {
                        gfx2d::layer(gfx2d::LayerDesc { blur: if still { 9 } else { 0 } }) { draw_field(t); };
                        if flash > 0 { gfx2d::rect(0, 0, FW, FH, gfx2d::rgba(0xFFFFFF, flash * 0.35)); }
                    };
                    gfx2d::rounded_rect_outline(0, 0, FW, FH, 14, 2, gfx2d::rgba(0xFFFFFF, 0.2));
                    draw_hud();
                    if over {
                        card("GAME OVER", str("score ", score, ", best combo x", best_combo, "\nR to play again"));
                    } else if paused {
                        card("PAUSED", "P to go on\nmouse or Left and Right to move\nSpace to launch");
                    } else if riding && played < 4 {
                        gfx2d::text(0, PADDLE_Y + 24, "Space or click to launch",
                                    gfx2d::TextStyle { size: 15, align: gfx2d::ALIGN_CENTER, wrap_width: FW },
                                    gfx2d::rgba(0xFFFFFF, 0.6));
                    }
                };
            };
        };
        drawn++;
        if drawn == frames && screenshot.len > 0 { gfx::screenshot(screenshot); }
    }
    gfx::close();
}
