// Copyright (C) 2026 SellGravity
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

//! SellGravity antidetect: records a 2D context's drawing calls and replays
//! them through the Rust rasterizer (src/rust/render/canvas.rs) when pixels
//! are read back. Paths are flattened into device space as they are built,
//! like Skia does with the current transform at each call.

const std = @import("std");

const color = @import("../../color.zig");
const screenshot = @import("../../screenshot.zig");
const Persona = @import("../../../Persona.zig");
const CanvasGradient = @import("CanvasGradient.zig");
const context2d = @import("context2d.zig");
const fonts = @import("../../fonts.zig");

const Allocator = std.mem.Allocator;

pub const Stop = extern struct {
    offset: f32,
    color: u32,
};

/// Mirrors LpCanvasOp in canvas.rs.
pub const Op = extern struct {
    kind: u32,
    composite: u32 = 0,
    fill_rule: u32 = 0,
    text_flags: u32 = 0,
    text_align: u32 = 0,
    text_baseline: u32 = 0,
    line_cap: u32 = 0,
    line_join: u32 = 0,
    transform: [6]f32 = .{ 1, 0, 0, 1, 0, 0 },
    color: u32 = 0x000000ff,
    global_alpha: f32 = 1,
    line_width: f32 = 1,
    miter_limit: f32 = 10,
    rect: [4]f32 = .{ 0, 0, 0, 0 },
    path: ?[*]const f32 = null,
    path_len: usize = 0,
    text: ?[*]const u8 = null,
    text_len: usize = 0,
    grad_kind: u32 = 0,
    grad: [6]f32 = .{ 0, 0, 0, 0, 0, 0 },
    stops: ?[*]const Stop = null,
    stops_len: usize = 0,
    image: ?[*]const u8 = null,
    image_w: u32 = 0,
    image_h: u32 = 0,
};

pub const op_fill_path: u32 = 0;
pub const op_stroke_path: u32 = 1;
pub const op_clear_path: u32 = 2;
pub const op_fill_text: u32 = 3;
pub const op_stroke_text: u32 = 4;
pub const op_put_image: u32 = 5;
pub const op_draw_image: u32 = 6;

const verb_move: f32 = 0;
const verb_line: f32 = 1;
const verb_quad: f32 = 2;
const verb_cubic: f32 = 3;
const verb_close: f32 = 4;

pub const text_bold: u32 = 1;
pub const text_italic: u32 = 2;
pub const text_serif: u32 = 4;
pub const text_mono: u32 = 8;

extern "c" fn lp_canvas_render(r: ?*screenshot.Renderer, w: u32, h: u32, ops: [*]const Op, n: usize, out: [*]u8) i32;
extern "c" fn lp_png_decode_rgba(data: [*]const u8, len: usize, w_out: *u32, h_out: *u32, out: ?[*]u8, out_cap: usize) i32;
extern "c" fn lp_canvas_measure(r: *screenshot.Renderer, text: [*]const u8, len: usize, px: f32, flags: u32, out: *[3]f32) i32;
extern "c" fn lp_png_encode_rgba(
    w: u32,
    h: u32,
    rgba: [*]const u8,
    ctx: *anyopaque,
    write: *const fn (ctx: *anyopaque, data: [*]const u8, len: usize) callconv(.c) bool,
) i32;

/// globalCompositeOperation values, in canvas.rs `blend_mode` order.
pub const composite_names = [_][]const u8{
    "source-over",    "source-in",       "source-out",       "source-atop", "destination-over",
    "destination-in", "destination-out", "destination-atop", "lighter",     "copy",
    "xor",            "multiply",        "screen",           "overlay",     "darken",
    "lighten",        "color-dodge",     "color-burn",       "hard-light",  "soft-light",
    "difference",     "exclusion",       "hue",              "saturation",  "color",
    "luminosity",
};
pub const line_cap_names = [_][]const u8{ "butt", "round", "square" };
pub const line_join_names = [_][]const u8{ "miter", "round", "bevel" };
pub const text_align_names = [_][]const u8{ "start", "end", "left", "right", "center" };
pub const text_baseline_names = [_][]const u8{ "alphabetic", "top", "hanging", "middle", "ideographic", "bottom" };

pub fn indexOf(comptime names: []const []const u8, value: []const u8) ?u8 {
    for (names, 0..) |n, i| {
        if (std.mem.eql(u8, n, value)) return @intCast(i);
    }
    return null;
}

/// Paint state that save()/restore() covers, besides context2d.State.
pub const Paint = struct {
    ctm: [6]f64 = .{ 1, 0, 0, 1, 0, 0 },
    global_alpha: f64 = 1,
    composite: u8 = 0,
    line_width: f64 = 1,
    line_cap: u8 = 0,
    line_join: u8 = 0,
    miter_limit: f64 = 10,
    text_align: u8 = 0,
    text_baseline: u8 = 0,
};

const Saved = struct {
    paint: Paint,
    state: context2d.State,
};

/// Ops beyond this are dropped: an animation that never clears would
/// otherwise grow the list for the life of the page.
const max_ops = 20_000;

pub const Recorder = struct {
    allocator: Allocator,
    ops: std.ArrayList(Op) = .empty,
    path: std.ArrayList(f32) = .empty,
    stack: std.ArrayList(Saved) = .empty,
    // Current point and subpath start, in user space, for arc continuity.
    has_point: bool = false,
    cur: [2]f64 = .{ 0, 0 },
    start: [2]f64 = .{ 0, 0 },

    pub fn init(allocator: Allocator) !*Recorder {
        const r = try allocator.create(Recorder);
        r.* = .{ .allocator = allocator };
        return r;
    }

    fn map(paint: *const Paint, x: f64, y: f64) [2]f32 {
        const m = paint.ctm;
        return .{ @floatCast(m[0] * x + m[2] * y + m[4]), @floatCast(m[1] * x + m[3] * y + m[5]) };
    }

    fn pushVerb(self: *Recorder, verb: f32, pts: []const [2]f32) !void {
        try self.path.append(self.allocator, verb);
        for (pts) |p| {
            try self.path.appendSlice(self.allocator, &p);
        }
    }

    pub fn beginPath(self: *Recorder) void {
        self.path.clearRetainingCapacity();
        self.has_point = false;
    }

    pub fn moveTo(self: *Recorder, paint: *const Paint, x: f64, y: f64) !void {
        if (!finite(&.{ x, y })) return;
        try self.pushVerb(verb_move, &.{map(paint, x, y)});
        self.cur = .{ x, y };
        self.start = .{ x, y };
        self.has_point = true;
    }

    pub fn lineTo(self: *Recorder, paint: *const Paint, x: f64, y: f64) !void {
        if (!finite(&.{ x, y })) return;
        if (!self.has_point) return self.moveTo(paint, x, y);
        try self.pushVerb(verb_line, &.{map(paint, x, y)});
        self.cur = .{ x, y };
    }

    pub fn quadTo(self: *Recorder, paint: *const Paint, cx: f64, cy: f64, x: f64, y: f64) !void {
        if (!finite(&.{ cx, cy, x, y })) return;
        if (!self.has_point) try self.moveTo(paint, cx, cy);
        try self.pushVerb(verb_quad, &.{ map(paint, cx, cy), map(paint, x, y) });
        self.cur = .{ x, y };
    }

    pub fn cubicTo(self: *Recorder, paint: *const Paint, c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64) !void {
        if (!finite(&.{ c1x, c1y, c2x, c2y, x, y })) return;
        if (!self.has_point) try self.moveTo(paint, c1x, c1y);
        try self.pushVerb(verb_cubic, &.{ map(paint, c1x, c1y), map(paint, c2x, c2y), map(paint, x, y) });
        self.cur = .{ x, y };
    }

    pub fn closePath(self: *Recorder) !void {
        if (!self.has_point) return;
        try self.path.append(self.allocator, verb_close);
        self.cur = self.start;
    }

    pub fn rect(self: *Recorder, paint: *const Paint, x: f64, y: f64, w: f64, h: f64) !void {
        if (!finite(&.{ x, y, w, h })) return;
        try self.moveTo(paint, x, y);
        try self.lineTo(paint, x + w, y);
        try self.lineTo(paint, x + w, y + h);
        try self.lineTo(paint, x, y + h);
        try self.closePath();
        try self.moveTo(paint, x, y);
    }

    /// Elliptical arc around (cx, cy) as cubic segments of at most 90°,
    /// optionally rotated, in user space then mapped through the CTM.
    pub fn ellipse(self: *Recorder, paint: *const Paint, cx: f64, cy: f64, rx: f64, ry: f64, rotation: f64, start_in: f64, end_in: f64, ccw: bool) !void {
        if (!finite(&.{ cx, cy, rx, ry, rotation, start_in, end_in })) return;
        if (rx < 0 or ry < 0) return error.IndexSizeError;
        const tau = 2 * std.math.pi;
        const start = start_in;
        var end = end_in;
        // Blink's AdjustEndAngle: arc(0, 2π, true) is a full circle, not an
        // empty arc.
        if (!ccw and end - start >= tau) {
            end = start + tau;
        } else if (ccw and start - end >= tau) {
            end = start - tau;
        } else if (!ccw and start > end) {
            end = start + (tau - @mod(start - end, tau));
        } else if (ccw and start < end) {
            end = start - (tau - @mod(end - start, tau));
        }
        const cos_r = @cos(rotation);
        const sin_r = @sin(rotation);
        const point = struct {
            fn f(c_x: f64, c_y: f64, r_x: f64, r_y: f64, cr: f64, sr: f64, a: f64) [2]f64 {
                const px = r_x * @cos(a);
                const py = r_y * @sin(a);
                return .{ c_x + px * cr - py * sr, c_y + px * sr + py * cr };
            }
        }.f;
        const p0 = point(cx, cy, rx, ry, cos_r, sin_r, start);
        if (self.has_point) try self.lineTo(paint, p0[0], p0[1]) else try self.moveTo(paint, p0[0], p0[1]);

        const total = end - start;
        const segs: usize = @intFromFloat(@max(1, @ceil(@abs(total) / (std.math.pi / 2.0))));
        const step = total / @as(f64, @floatFromInt(segs));
        const k = 4.0 / 3.0 * @tan(step / 4.0);
        var a = start;
        for (0..segs) |_| {
            const b = a + step;
            const ca = @cos(a);
            const sa = @sin(a);
            const cb = @cos(b);
            const sb = @sin(b);
            // Control points on the unit circle, then scaled/rotated.
            const c1 = [2]f64{ ca - k * sa, sa + k * ca };
            const c2 = [2]f64{ cb + k * sb, sb - k * cb };
            const xf = struct {
                fn f(c_x: f64, c_y: f64, r_x: f64, r_y: f64, cr: f64, sr: f64, u: [2]f64) [2]f64 {
                    const px = r_x * u[0];
                    const py = r_y * u[1];
                    return .{ c_x + px * cr - py * sr, c_y + px * sr + py * cr };
                }
            }.f;
            const q1 = xf(cx, cy, rx, ry, cos_r, sin_r, c1);
            const q2 = xf(cx, cy, rx, ry, cos_r, sin_r, c2);
            const q3 = xf(cx, cy, rx, ry, cos_r, sin_r, .{ cb, sb });
            try self.cubicTo(paint, q1[0], q1[1], q2[0], q2[1], q3[0], q3[1]);
            a = b;
        }
    }

    pub fn arc(self: *Recorder, paint: *const Paint, x: f64, y: f64, r: f64, start: f64, end: f64, ccw: bool) !void {
        return self.ellipse(paint, x, y, r, r, 0, start, end, ccw);
    }

    /// arcTo: a circular arc of radius r tangent to (cur->p1) and (p1->p2).
    pub fn arcTo(self: *Recorder, paint: *const Paint, x1: f64, y1: f64, x2: f64, y2: f64, r: f64) !void {
        if (!finite(&.{ x1, y1, x2, y2, r })) return;
        if (r < 0) return error.IndexSizeError;
        if (!self.has_point) try self.moveTo(paint, x1, y1);
        const x0 = self.cur[0];
        const y0 = self.cur[1];
        const v1 = [2]f64{ x0 - x1, y0 - y1 };
        const v2 = [2]f64{ x2 - x1, y2 - y1 };
        const l1 = @sqrt(v1[0] * v1[0] + v1[1] * v1[1]);
        const l2 = @sqrt(v2[0] * v2[0] + v2[1] * v2[1]);
        const cross = v1[0] * v2[1] - v1[1] * v2[0];
        if (r == 0 or l1 == 0 or l2 == 0 or @abs(cross) < 1e-9) {
            return self.lineTo(paint, x1, y1);
        }
        const cos_t = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2);
        const theta = std.math.acos(std.math.clamp(cos_t, -1, 1));
        const dist = r / @tan(theta / 2);
        const t1 = [2]f64{ x1 + v1[0] / l1 * dist, y1 + v1[1] / l1 * dist };
        const t2 = [2]f64{ x1 + v2[0] / l2 * dist, y1 + v2[1] / l2 * dist };
        // Center: from t1 perpendicular towards the inside of the corner.
        const bis = [2]f64{ v1[0] / l1 + v2[0] / l2, v1[1] / l1 + v2[1] / l2 };
        const bl = @sqrt(bis[0] * bis[0] + bis[1] * bis[1]);
        const cd = r / @sin(theta / 2);
        const c = [2]f64{ x1 + bis[0] / bl * cd, y1 + bis[1] / bl * cd };
        const a0 = std.math.atan2(t1[1] - c[1], t1[0] - c[0]);
        const a1 = std.math.atan2(t2[1] - c[1], t2[0] - c[0]);
        try self.lineTo(paint, t1[0], t1[1]);
        try self.ellipse(paint, c[0], c[1], r, r, 0, a0, a1, cross > 0);
    }

    pub fn roundRect(self: *Recorder, paint: *const Paint, x: f64, y: f64, w: f64, h: f64, radius: f64) !void {
        if (!finite(&.{ x, y, w, h, radius })) return;
        const r = @min(@max(radius, 0), @min(@abs(w), @abs(h)) / 2);
        if (r == 0) return self.rect(paint, x, y, w, h);
        const hp = std.math.pi / 2.0;
        try self.moveTo(paint, x + r, y);
        try self.lineTo(paint, x + w - r, y);
        try self.ellipse(paint, x + w - r, y + r, r, r, 0, -hp, 0, false);
        try self.lineTo(paint, x + w, y + h - r);
        try self.ellipse(paint, x + w - r, y + h - r, r, r, 0, 0, hp, false);
        try self.lineTo(paint, x + r, y + h);
        try self.ellipse(paint, x + r, y + h - r, r, r, 0, hp, 2 * hp, false);
        try self.lineTo(paint, x, y + r);
        try self.ellipse(paint, x + r, y + r, r, r, 0, 2 * hp, 3 * hp, false);
        try self.closePath();
    }

    fn baseOp(kind: u32, paint: *const Paint) Op {
        var op: Op = .{ .kind = kind };
        for (0..6) |i| op.transform[i] = @floatCast(paint.ctm[i]);
        op.composite = paint.composite;
        op.global_alpha = @floatCast(paint.global_alpha);
        op.line_width = @floatCast(paint.line_width);
        op.line_cap = paint.line_cap;
        op.line_join = paint.line_join;
        op.miter_limit = @floatCast(paint.miter_limit);
        op.text_align = switch (paint.text_align) {
            1, 3 => 1, // end, right
            4 => 2, // center
            else => 0,
        };
        op.text_baseline = paint.text_baseline;
        return op;
    }

    fn applyStyle(self: *Recorder, op: *Op, style: context2d.Style) !void {
        switch (style) {
            .color => |c| op.color = packColor(c),
            .pattern => op.color = 0x00000000, // images are never decoded
            .gradient => |g| {
                op.grad_kind = g._kind;
                for (0..6) |i| op.grad[i] = @floatCast(g._coords[i]);
                const stops = try self.allocator.alloc(Stop, g._stops_len);
                for (g._stops[0..g._stops_len], 0..) |s, i| {
                    stops[i] = .{ .offset = @floatCast(s.offset), .color = packColor(s.color) };
                }
                // Stops are kept in insertion order; the spec sorts by offset
                // with ties keeping insertion order.
                std.sort.insertion(Stop, stops, {}, struct {
                    fn lt(_: void, a: Stop, b: Stop) bool {
                        return a.offset < b.offset;
                    }
                }.lt);
                op.stops = stops.ptr;
                op.stops_len = stops.len;
            },
        }
    }

    fn push(self: *Recorder, op: Op) !void {
        if (self.ops.items.len >= max_ops) return;
        try self.ops.append(self.allocator, op);
    }

    fn snapshotPath(self: *Recorder) ![]const f32 {
        return self.allocator.dupe(f32, self.path.items);
    }

    pub fn fillPath(self: *Recorder, paint: *const Paint, state: *const context2d.State, evenodd: bool) !void {
        if (self.path.items.len == 0) return;
        var op = baseOp(op_fill_path, paint);
        op.fill_rule = if (evenodd) 1 else 0;
        try self.applyStyle(&op, state.fill_style);
        const p = try self.snapshotPath();
        op.path = p.ptr;
        op.path_len = p.len;
        try self.push(op);
    }

    pub fn strokePath(self: *Recorder, paint: *const Paint, state: *const context2d.State) !void {
        if (self.path.items.len == 0) return;
        var op = baseOp(op_stroke_path, paint);
        try self.applyStyle(&op, state.stroke_style);
        const p = try self.snapshotPath();
        op.path = p.ptr;
        op.path_len = p.len;
        try self.push(op);
    }

    /// fillRect / strokeRect / clearRect draw their own rectangle without
    /// touching the current path.
    pub fn rectOp(self: *Recorder, kind: u32, paint: *const Paint, state: *const context2d.State, x: f64, y: f64, w: f64, h: f64) !void {
        if (!finite(&.{ x, y, w, h })) return;
        if (kind == op_clear_path and isIdentity(paint) and x <= 0 and y <= 0 and w >= 16384 and h >= 16384) {
            self.ops.clearRetainingCapacity();
            return;
        }
        const pts = [_][2]f32{ map(paint, x, y), map(paint, x + w, y), map(paint, x + w, y + h), map(paint, x, y + h) };
        var buf = try self.allocator.alloc(f32, 3 + 3 * 3 + 1);
        buf[0] = verb_move;
        buf[1] = pts[0][0];
        buf[2] = pts[0][1];
        for (1..4) |i| {
            buf[3 * i] = verb_line;
            buf[3 * i + 1] = pts[i][0];
            buf[3 * i + 2] = pts[i][1];
        }
        buf[12] = verb_close;
        var op = baseOp(kind, paint);
        switch (kind) {
            op_fill_path => try self.applyStyle(&op, state.fill_style),
            op_stroke_path => try self.applyStyle(&op, state.stroke_style),
            else => {},
        }
        op.path = buf.ptr;
        op.path_len = buf.len;
        try self.push(op);
    }

    pub fn text(self: *Recorder, stroke: bool, paint: *const Paint, state: *const context2d.State, str: []const u8, x: f64, y: f64, max_width: ?f64) !void {
        if (!finite(&.{ x, y })) return;
        if (max_width) |m| {
            if (!(m > 0) or std.math.isNan(m)) return;
        }
        var op = baseOp(if (stroke) op_stroke_text else op_fill_text, paint);
        try self.applyStyle(&op, if (stroke) state.stroke_style else state.fill_style);
        const t = try self.allocator.dupe(u8, str);
        op.text = t.ptr;
        op.text_len = t.len;
        op.text_flags = personaFontFlags(state.font());
        // The persona face's metrics: stretch horizontally around (x, y).
        if (fonts.resolve(fonts.familyFromShorthand(state.font()))) |r| {
            const k = r.factor;
            const m = paint.ctm;
            op.transform[0] = @floatCast(m[0] * k);
            op.transform[1] = @floatCast(m[1] * k);
            op.transform[4] = @floatCast(m[0] * (x - k * x) + m[2] * r.shift + m[4]);
            op.transform[5] = @floatCast(m[1] * (x - k * x) + m[3] * r.shift + m[5]);
        }
        op.rect = .{ @floatCast(x), @floatCast(y), if (max_width) |m| @floatCast(m) else 0, @floatCast(state.font_size) };
        try self.push(op);
    }

    pub fn putImage(self: *Recorder, rgba: []const u8, w: u32, h: u32, dx: f64, dy: f64) !void {
        if (!finite(&.{ dx, dy })) return;
        const copy = try self.allocator.dupe(u8, rgba);
        var op: Op = .{ .kind = op_put_image };
        op.image = copy.ptr;
        op.image_w = w;
        op.image_h = h;
        op.rect = .{ @floatCast(dx), @floatCast(dy), 0, 0 };
        try self.push(op);
    }

    /// drawImage of straight-RGBA `src` (iw x ih): the source rect (sx, sy,
    /// sw, sh) is cropped here, then scaled into (dx, dy, dw, dh) by Rust.
    pub fn drawImage(self: *Recorder, paint: *const Paint, src: []const u8, iw: u32, ih: u32, sx: f64, sy: f64, sw: f64, sh: f64, dx: f64, dy: f64, dw: f64, dh: f64) !void {
        if (!finite(&.{ sx, sy, sw, sh, dx, dy, dw, dh })) return;
        if (iw == 0 or ih == 0 or sw == 0 or sh == 0 or dw == 0 or dh == 0) return;
        const x0: u32 = @intFromFloat(std.math.clamp(@floor(@min(sx, sx + sw)), 0, @as(f64, @floatFromInt(iw))));
        const y0: u32 = @intFromFloat(std.math.clamp(@floor(@min(sy, sy + sh)), 0, @as(f64, @floatFromInt(ih))));
        const x1: u32 = @intFromFloat(std.math.clamp(@ceil(@max(sx, sx + sw)), 0, @as(f64, @floatFromInt(iw))));
        const y1: u32 = @intFromFloat(std.math.clamp(@ceil(@max(sy, sy + sh)), 0, @as(f64, @floatFromInt(ih))));
        if (x1 <= x0 or y1 <= y0) return;
        const cw = x1 - x0;
        const ch = y1 - y0;
        const crop = try self.allocator.alloc(u8, @as(usize, cw) * ch * 4);
        for (0..ch) |row| {
            const s = ((y0 + row) * iw + x0) * 4;
            @memcpy(crop[row * cw * 4 ..][0 .. cw * 4], src[s..][0 .. cw * 4]);
        }
        var op = baseOp(op_draw_image, paint);
        op.image = crop.ptr;
        op.image_w = cw;
        op.image_h = ch;
        op.rect = .{ @floatCast(dx), @floatCast(dy), @floatCast(dw), @floatCast(dh) };
        try self.push(op);
    }

    pub fn save(self: *Recorder, paint: *const Paint, state: *const context2d.State) !void {
        if (self.stack.items.len >= 512) return;
        try self.stack.append(self.allocator, .{ .paint = paint.*, .state = state.* });
    }

    pub fn restore(self: *Recorder, paint: *Paint, state: *context2d.State) void {
        const s = self.stack.pop() orelse return;
        paint.* = s.paint;
        state.* = s.state;
    }

    /// Replays the ops into `w` x `h` straight-alpha RGBA (allocated with
    /// `allocator`), adding the profile's canvas noise.
    pub fn render(self: *const Recorder, allocator: Allocator, renderer: ?*screenshot.Renderer, w: u32, h: u32) ![]u8 {
        const out = try allocator.alloc(u8, @as(usize, w) * h * 4);
        @memset(out, 0);
        if (self.ops.items.len > 0) {
            const rc = lp_canvas_render(renderer, w, h, self.ops.items.ptr, self.ops.items.len, out.ptr);
            if (rc != 0) @memset(out, 0);
        }
        // Pixels a page wrote itself with putImageData read back verbatim
        // (CreepJS compares them to spot "rgba noise").
        var skip: [16][4]i64 = undefined;
        var skip_len: usize = 0;
        for (self.ops.items) |op| {
            if (skip_len == skip.len) break;
            if (op.kind == op_put_image) {
                const x0: i64 = @intFromFloat(@round(op.rect[0]));
                const y0: i64 = @intFromFloat(@round(op.rect[1]));
                skip[skip_len] = .{ x0, y0, x0 + op.image_w, y0 + op.image_h };
                skip_len += 1;
            } else if (op.kind == op_draw_image) {
                // Drawn images already carry their noise (e.g. a canvas
                // exported and drawn back): bounding box in device space.
                const t = op.transform;
                const xs = [_]f32{ op.rect[0], op.rect[0] + op.rect[2] };
                const ys = [_]f32{ op.rect[1], op.rect[1] + op.rect[3] };
                var min_x: f32 = std.math.floatMax(f32);
                var min_y: f32 = std.math.floatMax(f32);
                var max_x: f32 = -std.math.floatMax(f32);
                var max_y: f32 = -std.math.floatMax(f32);
                for (xs) |px| for (ys) |py| {
                    const dx = t[0] * px + t[2] * py + t[4];
                    const dy = t[1] * px + t[3] * py + t[5];
                    min_x = @min(min_x, dx);
                    min_y = @min(min_y, dy);
                    max_x = @max(max_x, dx);
                    max_y = @max(max_y, dy);
                };
                if (!std.math.isFinite(min_x) or !std.math.isFinite(max_y)) continue;
                skip[skip_len] = .{
                    @intFromFloat(@floor(std.math.clamp(min_x, -1e6, 1e6))),
                    @intFromFloat(@floor(std.math.clamp(min_y, -1e6, 1e6))),
                    @intFromFloat(@ceil(std.math.clamp(max_x, -1e6, 1e6))),
                    @intFromFloat(@ceil(std.math.clamp(max_y, -1e6, 1e6))),
                };
                skip_len += 1;
            }
        }
        applyNoise(out, w, skip[0..skip_len]);
        return out;
    }
};

fn isIdentity(paint: *const Paint) bool {
    const m = paint.ctm;
    return m[0] == 1 and m[1] == 0 and m[2] == 0 and m[3] == 1 and m[4] == 0 and m[5] == 0;
}

fn finite(values: []const f64) bool {
    for (values) |v| {
        if (!std.math.isFinite(v)) return false;
    }
    return true;
}

pub fn packColor(c: color.RGBA) u32 {
    return (@as(u32, c.r) << 24) | (@as(u32, c.g) << 16) | (@as(u32, c.b) << 8) | c.a;
}

/// fontFlags, with the face (serif / mono / sans) the persona's font list
/// resolves the family to.
pub fn personaFontFlags(font: []const u8) u32 {
    var flags = fontFlags(font);
    if (fonts.resolve(fonts.familyFromShorthand(font))) |r| {
        flags &= ~(text_mono | text_serif);
        switch (r.generic) {
            .mono => flags |= text_mono,
            .serif => flags |= text_serif,
            .sans => {},
        }
    }
    return flags;
}

/// bold / italic / generic family out of a CSS font shorthand.
pub fn fontFlags(font: []const u8) u32 {
    var flags: u32 = 0;
    var it = std.mem.tokenizeAny(u8, font, " ,\t");
    while (it.next()) |raw| {
        const tok = std.mem.trim(u8, raw, "\"'");
        if (std.ascii.eqlIgnoreCase(tok, "bold") or std.ascii.eqlIgnoreCase(tok, "bolder") or
            std.mem.eql(u8, tok, "600") or std.mem.eql(u8, tok, "700") or std.mem.eql(u8, tok, "800") or std.mem.eql(u8, tok, "900"))
        {
            flags |= text_bold;
        } else if (std.ascii.eqlIgnoreCase(tok, "italic") or std.ascii.eqlIgnoreCase(tok, "oblique")) {
            flags |= text_italic;
        } else if (std.ascii.eqlIgnoreCase(tok, "monospace") or std.ascii.eqlIgnoreCase(tok, "courier") or std.ascii.eqlIgnoreCase(tok, "consolas")) {
            flags |= text_mono;
        } else if (std.ascii.eqlIgnoreCase(tok, "serif") or std.ascii.eqlIgnoreCase(tok, "times") or std.ascii.eqlIgnoreCase(tok, "georgia")) {
            flags |= text_serif;
        }
    }
    return flags;
}

fn splitmix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

/// --canvas-noise: nudge ~4% of the painted edge pixels by one level in one
/// channel, from the profile seed. Stable for a profile (same drawing, same
/// hash), different across profiles; transparent pixels stay untouched so a
/// blank canvas still reads as blank.
pub fn applyNoise(rgba: []u8, width: u32, skip: []const [4]i64) void {
    const p = Persona.get();
    if (!Persona.active or !p.canvas_noise) return;
    const base = p.seed ^ Persona.salt_canvas;
    var i: usize = 0;
    while (i + 3 < rgba.len) : (i += 4) {
        // Opaque pixels only: a semi-transparent value nudged after
        // demultiplying does not survive the premultiplied round trip
        // (toDataURL -> Image -> drawImage -> getImageData must match).
        if (rgba[i + 3] != 255) continue;
        // Solid areas stay exact, borders between solid fills included (a
        // filled rect reads back its exact color, which tamper checks such as
        // pixelscan's colour-strip round trip verify). Only anti-aliased
        // pixels - unlike every 4-neighbour, the ones that already vary
        // across GPUs - carry the noise.
        const stride: usize = @as(usize, width) * 4;
        const col = (i >> 2) % width;
        const px4 = rgba[i..][0..4];
        if (col + 1 < width and i + 7 < rgba.len and std.mem.eql(u8, px4, rgba[i + 4 ..][0..4])) continue;
        if (col > 0 and std.mem.eql(u8, px4, rgba[i - 4 ..][0..4])) continue;
        if (i + stride + 3 < rgba.len and std.mem.eql(u8, px4, rgba[i + stride ..][0..4])) continue;
        if (i >= stride and std.mem.eql(u8, px4, rgba[i - stride ..][0..4])) continue;
        if (skip.len > 0) {
            const px: i64 = @intCast((i >> 2) % width);
            const py: i64 = @intCast((i >> 2) / width);
            var inside = false;
            for (skip) |r| {
                if (px >= r[0] and px < r[2] and py >= r[1] and py < r[3]) {
                    inside = true;
                    break;
                }
            }
            if (inside) continue;
        }
        const h = splitmix(base ^ (i >> 2));
        if (h % 25 != 0) continue;
        const ch = i + @as(usize, @intCast((h >> 8) % 3));
        // Set the low bit from the seed instead of +-1: idempotent, so pixels
        // exported and drawn back (or noised twice) read back identically.
        rgba[ch] = (rgba[ch] & 0xFE) | @as(u8, @intCast((h >> 16) & 1));
    }
}

/// measureText through the rasterizer's fonts, with --fonts-noise. Null when
/// no renderer is available (caller falls back to the estimate).
pub fn measure(renderer: *screenshot.Renderer, str: []const u8, state: *const context2d.State) ?[3]f64 {
    var out: [3]f32 = undefined;
    if (lp_canvas_measure(renderer, str.ptr, str.len, @floatCast(state.font_size), personaFontFlags(state.font()), &out) != 0) return null;
    var width: f64 = out[0];
    if (fonts.resolve(fonts.familyFromShorthand(state.font()))) |r| width *= r.factor;
    const p = Persona.get();
    if (Persona.active and p.fonts_noise and width > 0) {
        // Sub-pixel, stable per (profile, resolved face, text). Keyed on the
        // exact un-noised width, not the font string: "'NoSuchFont',
        // monospace" resolves to monospace and must measure exactly like it,
        // or every probed font would look installed.
        var key_buf: [8 + 256]u8 = undefined;
        @memcpy(key_buf[0..8], std.mem.asBytes(&width));
        const m = @min(str.len, key_buf.len - 8);
        @memcpy(key_buf[8..][0..m], str[0..m]);
        width += p.noiseOffset(Persona.salt_fonts, key_buf[0 .. 8 + m], width * 0.0006);
    }
    return .{ width, out[1], out[2] };
}

/// PNG bytes for straight-alpha RGBA.
pub fn pngBytes(allocator: Allocator, rgba: []const u8, w: u32, h: u32) ![]const u8 {
    var png: std.Io.Writer.Allocating = .init(allocator);
    const Ctx = struct {
        fn write(ctx: *anyopaque, data: [*]const u8, len: usize) callconv(.c) bool {
            const wr: *std.Io.Writer.Allocating = @ptrCast(@alignCast(ctx));
            wr.writer.writeAll(data[0..len]) catch return false;
            return true;
        }
    };
    if (lp_png_encode_rgba(w, h, rgba.ptr, &png, Ctx.write) != 0) return error.EncodeFailed;
    return png.written();
}

/// PNG data URL for straight-alpha RGBA.
pub fn dataUrl(allocator: Allocator, rgba: []const u8, w: u32, h: u32) ![]const u8 {
    const bytes = try pngBytes(allocator, rgba, w, h);
    const prefix = "data:image/png;base64,";
    const enc = std.base64.standard.Encoder;
    const out = try allocator.alloc(u8, prefix.len + enc.calcSize(bytes.len));
    @memcpy(out[0..prefix.len], prefix);
    _ = enc.encode(out[prefix.len..], bytes);
    return out;
}

/// The browser's font renderer, created on first use (shared with
/// screenshots).
pub fn rendererFor(browser: anytype) ?*screenshot.Renderer {
    if (browser.renderer) |r| return r;
    const r = screenshot.Renderer.init(browser.app.render_fonts.files) catch return null;
    browser.renderer = r;
    return r;
}

const testing = std.testing;

test "raster: fontFlags" {
    try testing.expectEqual(text_bold | text_italic, fontFlags("italic bold 12px Arial"));
    try testing.expectEqual(text_mono, fontFlags("14px 'Courier New', monospace"));
    try testing.expectEqual(@as(u32, 0), fontFlags("10px sans-serif"));
}

pub const Decoded = struct {
    rgba: []u8,
    w: u32,
    h: u32,
};

/// A `data:image/png;base64,...` URL decoded to straight RGBA, or null.
pub fn decodePngDataUrl(allocator: Allocator, url: []const u8) ?Decoded {
    const prefix = "data:image/png;base64,";
    if (!std.ascii.startsWithIgnoreCase(url, prefix)) return null;
    const b64 = url[prefix.len..];
    const dec = std.base64.standard.Decoder;
    const size = dec.calcSizeForSlice(b64) catch return null;
    const bytes = allocator.alloc(u8, size) catch return null;
    dec.decode(bytes, b64) catch return null;
    var w: u32 = 0;
    var h: u32 = 0;
    if (lp_png_decode_rgba(bytes.ptr, bytes.len, &w, &h, null, 0) != 1) return null;
    const out = allocator.alloc(u8, @as(usize, w) * h * 4) catch return null;
    if (lp_png_decode_rgba(bytes.ptr, bytes.len, &w, &h, out.ptr, out.len) != 0) return null;
    return .{ .rgba = out, .w = w, .h = h };
}
