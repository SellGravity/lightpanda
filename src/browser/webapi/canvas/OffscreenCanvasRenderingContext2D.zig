// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
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

const std = @import("std");
const lp = @import("lightpanda");

const js = @import("../../js/js.zig");

const OffscreenCanvas = @import("OffscreenCanvas.zig");
const ImageData = @import("../ImageData.zig");
const context2d = @import("context2d.zig");
const raster = @import("raster.zig");
const draw_image = @import("draw_image.zig");
const TextMetrics = @import("TextMetrics.zig");
const CanvasGradient = @import("CanvasGradient.zig");
const CanvasPattern = @import("CanvasPattern.zig");

const Execution = js.Execution;

/// This class doesn't implement a `constructor`.
/// It can be obtained with a call to `OffscreenCanvas#getContext`.
/// https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvasRenderingContext2D
const OffscreenCanvasRenderingContext2D = @This();
/// Reference to the parent canvas element.
/// https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvasRenderingContext2D/canvas
_canvas: *OffscreenCanvas,
_state: context2d.State = .{},
// SellGravity antidetect: paint state + recorded drawing (launcher profiles
// only), replayed by raster.zig when pixels are read back.
_paint: raster.Paint = .{},
_rec: ?*raster.Recorder = null,

fn recorder(self: *OffscreenCanvasRenderingContext2D, exec: *const Execution) ?*raster.Recorder {
    if (!lp.Persona.active) return null;
    if (self._rec) |r| return r;
    const r = raster.Recorder.init(exec.page_arena) catch return null;
    self._rec = r;
    return r;
}

/// The pixels as Chrome would hand them out: replayed ops plus the profile's
/// canvas noise. Null when nothing was recorded (upstream behaviour).
pub fn renderPixels(self: *const OffscreenCanvasRenderingContext2D, allocator: std.mem.Allocator, exec: *const Execution, w: u32, h: u32) !?[]u8 {
    const rec = self._rec orelse return null;
    const renderer = raster.rendererFor(exec.session.browser);
    return try rec.render(allocator, renderer, w, h);
}

fn getCanvas(self: *const OffscreenCanvasRenderingContext2D) *OffscreenCanvas {
    return self._canvas;
}

fn getFillStyle(self: *const OffscreenCanvasRenderingContext2D, exec: *const Execution) !context2d.StyleOutput {
    return self._state.getStyle(.fill, exec);
}

fn setFillStyle(self: *OffscreenCanvasRenderingContext2D, value: context2d.StyleInput) void {
    self._state.setStyle(.fill, value);
}

fn getStrokeStyle(self: *const OffscreenCanvasRenderingContext2D, exec: *const Execution) !context2d.StyleOutput {
    return self._state.getStyle(.stroke, exec);
}

fn setStrokeStyle(self: *OffscreenCanvasRenderingContext2D, value: context2d.StyleInput) void {
    self._state.setStyle(.stroke, value);
}

// --- paint state accessors (plain data properties upstream) ---------------

fn getGlobalAlpha(self: *const OffscreenCanvasRenderingContext2D) f64 {
    return self._paint.global_alpha;
}
fn setGlobalAlpha(self: *OffscreenCanvasRenderingContext2D, v: f64) void {
    if (v >= 0 and v <= 1) self._paint.global_alpha = v;
}
fn getComposite(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return raster.composite_names[self._paint.composite];
}
fn setComposite(self: *OffscreenCanvasRenderingContext2D, v: []const u8) void {
    if (raster.indexOf(&raster.composite_names, v)) |i| self._paint.composite = i;
}
fn getLineWidth(self: *const OffscreenCanvasRenderingContext2D) f64 {
    return self._paint.line_width;
}
fn setLineWidth(self: *OffscreenCanvasRenderingContext2D, v: f64) void {
    if (v > 0 and std.math.isFinite(v)) self._paint.line_width = v;
}
fn getLineCap(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return raster.line_cap_names[self._paint.line_cap];
}
fn setLineCap(self: *OffscreenCanvasRenderingContext2D, v: []const u8) void {
    if (raster.indexOf(&raster.line_cap_names, v)) |i| self._paint.line_cap = i;
}
fn getLineJoin(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return raster.line_join_names[self._paint.line_join];
}
fn setLineJoin(self: *OffscreenCanvasRenderingContext2D, v: []const u8) void {
    if (raster.indexOf(&raster.line_join_names, v)) |i| self._paint.line_join = i;
}
fn getMiterLimit(self: *const OffscreenCanvasRenderingContext2D) f64 {
    return self._paint.miter_limit;
}
fn setMiterLimit(self: *OffscreenCanvasRenderingContext2D, v: f64) void {
    if (v > 0 and std.math.isFinite(v)) self._paint.miter_limit = v;
}
fn getTextAlign(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return raster.text_align_names[self._paint.text_align];
}
fn setTextAlign(self: *OffscreenCanvasRenderingContext2D, v: []const u8) void {
    if (raster.indexOf(&raster.text_align_names, v)) |i| self._paint.text_align = i;
}
fn getTextBaseline(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return raster.text_baseline_names[self._paint.text_baseline];
}
fn setTextBaseline(self: *OffscreenCanvasRenderingContext2D, v: []const u8) void {
    if (raster.indexOf(&raster.text_baseline_names, v)) |i| self._paint.text_baseline = i;
}

const WidthOrImageData = union(enum) {
    width: u32,
    image_data: *ImageData,
};

fn createImageData(
    _: *const OffscreenCanvasRenderingContext2D,
    width_or_image_data: WidthOrImageData,
    /// If `ImageData` variant preferred, this is null.
    maybe_height: ?u32,
    /// Can be used if width and height provided.
    maybe_settings: ?ImageData.ConstructorSettings,
    exec: *Execution,
) !*ImageData {
    switch (width_or_image_data) {
        .width => |width| {
            const height = maybe_height orelse return error.TypeError;
            return ImageData.init(width, height, maybe_settings, exec);
        },
        .image_data => |image_data| {
            return ImageData.init(image_data._width, image_data._height, null, exec);
        },
    }
}

fn putImageData(self: *OffscreenCanvasRenderingContext2D, img: *ImageData, dx: f64, dy: f64, _: ?f64, _: ?f64, _: ?f64, _: ?f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    const data = img._data.local(exec.js.local.?).slice();
    try rec.putImage(data, img._width, img._height, dx, dy);
}

// drawImage(image, dx, dy[, dw, dh]) or (image, sx, sy, sw, sh, dx, dy, dw, dh).
// Launcher profiles draw PNG data-URL images, canvases and offscreen canvases
// (see draw_image.zig); other sources draw nothing.
fn drawImage(self: *OffscreenCanvasRenderingContext2D, source: draw_image.Source, a0: f64, a1: f64, a2: ?f64, a3: ?f64, a4: ?f64, a5: ?f64, a6: ?f64, a7: ?f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try draw_image.record(rec, &self._paint, source, .{ a0, a1, a2, a3, a4, a5, a6, a7 }, exec);
}

fn getImageData(
    self: *const OffscreenCanvasRenderingContext2D,
    sx: i32,
    sy: i32,
    sw: i32,
    sh: i32,
    exec: *Execution,
) !*ImageData {
    if (sw <= 0 or sh <= 0) {
        return error.IndexSizeError;
    }
    const img = try ImageData.init(@intCast(sw), @intCast(sh), null, exec);
    const cw: i64 = self._canvas.getWidth();
    const ch: i64 = self._canvas.getHeight();
    if (cw == 0 or ch == 0) return img;
    const pixels = (try self.renderPixels(exec.call_arena, exec, @intCast(cw), @intCast(ch))) orelse return img;
    const dst = img._data.local(exec.js.local.?).slice();
    const w: i64 = sw;
    const h: i64 = sh;
    var y: i64 = 0;
    while (y < h) : (y += 1) {
        const src_y = @as(i64, sy) + y;
        if (src_y < 0 or src_y >= ch) continue;
        var x: i64 = 0;
        while (x < w) : (x += 1) {
            const src_x = @as(i64, sx) + x;
            if (src_x < 0 or src_x >= cw) continue;
            const s: usize = @intCast((src_y * cw + src_x) * 4);
            const d: usize = @intCast((y * w + x) * 4);
            @memcpy(dst[d..][0..4], pixels[s..][0..4]);
        }
    }
    return img;
}

fn getFont(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return self._state.font();
}

pub fn setFont(self: *OffscreenCanvasRenderingContext2D, value: []const u8, exec: *const Execution) !void {
    return self._state.setFont(value, exec);
}

pub fn measureText(self: *const OffscreenCanvasRenderingContext2D, text: []const u8, exec: *const Execution) !*TextMetrics {
    if (lp.Persona.active) {
        if (raster.rendererFor(exec.session.browser)) |r| {
            if (raster.measure(r, text, &self._state)) |m| {
                return TextMetrics.init(m[0], self._state.font_size, exec);
            }
        }
    }
    return self._state.measureText(text, exec);
}

pub fn setLineDash(self: *OffscreenCanvasRenderingContext2D, segments: []const f64, exec: *const Execution) !void {
    return self._state.setLineDash(segments, exec);
}

fn getLineDash(self: *const OffscreenCanvasRenderingContext2D) []const f64 {
    return self._state.lineDash();
}

fn radiusOf(v: ?js.Value) f64 {
    const val = v orelse return 0;
    return val.toF64() catch 0;
}

fn roundRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, w: f64, h: f64, radii: ?js.Value, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.roundRect(&self._paint, x, y, w, h, radiusOf(radii));
}
pub fn ellipse(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, rx: f64, ry: f64, rot: f64, start: f64, end: f64, ccw: ?bool, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.ellipse(&self._paint, x, y, rx, ry, rot, start, end, ccw orelse false);
}
fn isPointInPath(_: *const OffscreenCanvasRenderingContext2D, _: js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) bool {
    return false;
}
fn isPointInStroke(_: *const OffscreenCanvasRenderingContext2D, _: js.Value, _: ?js.Value, _: ?js.Value) bool {
    return false;
}

fn createLinearGradient(_: *const OffscreenCanvasRenderingContext2D, x0: f64, y0: f64, x1: f64, y1: f64, exec: *const Execution) !*CanvasGradient {
    return CanvasGradient.initGeometry(1, .{ x0, y0, x1, y1, 0, 0 }, exec);
}

fn createRadialGradient(_: *const OffscreenCanvasRenderingContext2D, x0: f64, y0: f64, r0: f64, x1: f64, y1: f64, r1: f64, exec: *const Execution) !*CanvasGradient {
    if (r0 < 0 or r1 < 0) return error.IndexSizeError;
    return CanvasGradient.initGeometry(2, .{ x0, y0, r0, x1, y1, r1 }, exec);
}

fn createConicGradient(_: *const OffscreenCanvasRenderingContext2D, _: f64, _: f64, _: f64, exec: *const Execution) !*CanvasGradient {
    return CanvasGradient.init(exec);
}

fn createPattern(_: *const OffscreenCanvasRenderingContext2D, _: js.Value, repetition_: ?[]const u8, exec: *const Execution) !*CanvasPattern {
    const repetition = repetition_ orelse "repeat";
    const known = [_][]const u8{ "", "repeat", "repeat-x", "repeat-y", "no-repeat" };
    for (known) |k| {
        if (std.mem.eql(u8, repetition, k)) return CanvasPattern.init(k, exec);
    }
    return error.SyntaxError;
}

// --- transform -------------------------------------------------------------

fn finite6(v: [6]f64) bool {
    for (v) |x| {
        if (!std.math.isFinite(x)) return false;
    }
    return true;
}

fn multiply(self: *OffscreenCanvasRenderingContext2D, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
    if (!finite6(.{ a, b, c, d, e, f })) return;
    const m = self._paint.ctm;
    self._paint.ctm = .{
        m[0] * a + m[2] * b,
        m[1] * a + m[3] * b,
        m[0] * c + m[2] * d,
        m[1] * c + m[3] * d,
        m[0] * e + m[2] * f + m[4],
        m[1] * e + m[3] * f + m[5],
    };
}

pub fn save(self: *OffscreenCanvasRenderingContext2D, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.save(&self._paint, &self._state);
}
pub fn restore(self: *OffscreenCanvasRenderingContext2D) void {
    const rec = self._rec orelse return;
    rec.restore(&self._paint, &self._state);
}
pub fn scale(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    self.multiply(x, 0, 0, y, 0, 0);
}
pub fn rotate(self: *OffscreenCanvasRenderingContext2D, angle: f64) void {
    const c = @cos(angle);
    const s = @sin(angle);
    self.multiply(c, s, -s, c, 0, 0);
}
pub fn translate(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    self.multiply(1, 0, 0, 1, x, y);
}
pub fn transform(self: *OffscreenCanvasRenderingContext2D, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
    self.multiply(a, b, c, d, e, f);
}
fn setTransform(self: *OffscreenCanvasRenderingContext2D, a: ?f64, b: ?f64, c: ?f64, d: ?f64, e: ?f64, f: ?f64) void {
    const v = [6]f64{ a orelse 1, b orelse 0, c orelse 0, d orelse 1, e orelse 0, f orelse 0 };
    if (!finite6(v)) return;
    self._paint.ctm = v;
}
fn resetTransform(self: *OffscreenCanvasRenderingContext2D) void {
    self._paint.ctm = .{ 1, 0, 0, 1, 0, 0 };
}

// --- drawing ---------------------------------------------------------------

fn clearRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, w: f64, h: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.rectOp(raster.op_clear_path, &self._paint, &self._state, x, y, w, h);
}
fn fillRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, w: f64, h: f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.rectOp(raster.op_fill_path, &self._paint, &self._state, x, y, w, h);
}
fn strokeRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, w: f64, h: f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.rectOp(raster.op_stroke_path, &self._paint, &self._state, x, y, w, h);
}
fn beginPath(self: *OffscreenCanvasRenderingContext2D) void {
    if (self._rec) |r| r.beginPath();
}
fn closePath(self: *OffscreenCanvasRenderingContext2D) !void {
    if (self._rec) |r| try r.closePath();
}
fn moveTo(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.moveTo(&self._paint, x, y);
}
fn lineTo(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.lineTo(&self._paint, x, y);
}
fn quadraticCurveTo(self: *OffscreenCanvasRenderingContext2D, cx: f64, cy: f64, x: f64, y: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.quadTo(&self._paint, cx, cy, x, y);
}
fn bezierCurveTo(self: *OffscreenCanvasRenderingContext2D, c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.cubicTo(&self._paint, c1x, c1y, c2x, c2y, x, y);
}
pub fn arc(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, r: f64, start: f64, end: f64, ccw: ?bool, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.arc(&self._paint, x, y, r, start, end, ccw orelse false);
}
fn arcTo(self: *OffscreenCanvasRenderingContext2D, x1: f64, y1: f64, x2: f64, y2: f64, r: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.arcTo(&self._paint, x1, y1, x2, y2, r);
}
pub fn rect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, w: f64, h: f64, exec: *const Execution) !void {
    const rec = self.recorder(exec) orelse return;
    try rec.rect(&self._paint, x, y, w, h);
}

/// fill() / fill(fillRule) / fill(path, fillRule). A Path2D is not replayed.
fn isEvenOdd(a: ?js.Value, b: ?[]const u8) bool {
    if (b) |rule| return std.mem.eql(u8, rule, "evenodd");
    const v = a orelse return false;
    if (v.isString() == null) return false;
    const s = v.toStringSlice() catch return false;
    return std.mem.eql(u8, s, "evenodd");
}

pub fn fill(self: *OffscreenCanvasRenderingContext2D, a: ?js.Value, b: ?[]const u8, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.fillPath(&self._paint, &self._state, isEvenOdd(a, b));
}
pub fn stroke(self: *OffscreenCanvasRenderingContext2D, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.strokePath(&self._paint, &self._state);
}
pub fn clip(_: *OffscreenCanvasRenderingContext2D) void {}
fn fillText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.text(false, &self._paint, &self._state, text, x, y, max_width);
}
fn strokeText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64, exec: *const Execution) !void {
    painted(exec);
    const rec = self.recorder(exec) orelse return;
    try rec.text(true, &self._paint, &self._state, text, x, y, max_width);
}

fn painted(exec: *const Execution) void {
    exec.page.status.noteUnsupported(.canvas2d);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(OffscreenCanvasRenderingContext2D);

    pub const Meta = struct {
        pub const name = "OffscreenCanvasRenderingContext2D";

        pub var class_id: bridge.ClassId = undefined;
    };

    pub const canvas = bridge.accessor(OffscreenCanvasRenderingContext2D.getCanvas, null, .{});
    pub const font = bridge.accessor(OffscreenCanvasRenderingContext2D.getFont, OffscreenCanvasRenderingContext2D.setFont, .{});
    pub const measureText = bridge.function(OffscreenCanvasRenderingContext2D.measureText, .{});
    pub const setLineDash = bridge.function(OffscreenCanvasRenderingContext2D.setLineDash, .{});
    pub const getLineDash = bridge.function(OffscreenCanvasRenderingContext2D.getLineDash, .{});
    pub const lineDashOffset = bridge.property(0.0, .{ .template = false, .readonly = false });
    pub const roundRect = bridge.function(OffscreenCanvasRenderingContext2D.roundRect, .{});
    pub const ellipse = bridge.function(OffscreenCanvasRenderingContext2D.ellipse, .{});
    pub const isPointInPath = bridge.function(OffscreenCanvasRenderingContext2D.isPointInPath, .{});
    pub const isPointInStroke = bridge.function(OffscreenCanvasRenderingContext2D.isPointInStroke, .{});
    pub const createLinearGradient = bridge.function(OffscreenCanvasRenderingContext2D.createLinearGradient, .{});
    pub const createRadialGradient = bridge.function(OffscreenCanvasRenderingContext2D.createRadialGradient, .{});
    pub const createConicGradient = bridge.function(OffscreenCanvasRenderingContext2D.createConicGradient, .{});
    pub const createPattern = bridge.function(OffscreenCanvasRenderingContext2D.createPattern, .{});
    pub const shadowBlur = bridge.property(0.0, .{ .template = false, .readonly = false });
    pub const shadowColor = bridge.property("rgba(0, 0, 0, 0)", .{ .template = false, .readonly = false });
    pub const shadowOffsetX = bridge.property(0.0, .{ .template = false, .readonly = false });
    pub const shadowOffsetY = bridge.property(0.0, .{ .template = false, .readonly = false });
    pub const filter = bridge.property("none", .{ .template = false, .readonly = false });
    pub const imageSmoothingEnabled = bridge.property(true, .{ .template = false, .readonly = false });
    pub const imageSmoothingQuality = bridge.property("low", .{ .template = false, .readonly = false });
    pub const direction = bridge.property("ltr", .{ .template = false, .readonly = false });
    pub const letterSpacing = bridge.property("0px", .{ .template = false, .readonly = false });
    pub const wordSpacing = bridge.property("0px", .{ .template = false, .readonly = false });
    pub const fontKerning = bridge.property("auto", .{ .template = false, .readonly = false });
    pub const globalAlpha = bridge.accessor(OffscreenCanvasRenderingContext2D.getGlobalAlpha, OffscreenCanvasRenderingContext2D.setGlobalAlpha, .{});
    pub const globalCompositeOperation = bridge.accessor(OffscreenCanvasRenderingContext2D.getComposite, OffscreenCanvasRenderingContext2D.setComposite, .{});
    pub const strokeStyle = bridge.accessor(OffscreenCanvasRenderingContext2D.getStrokeStyle, OffscreenCanvasRenderingContext2D.setStrokeStyle, .{});
    pub const lineWidth = bridge.accessor(OffscreenCanvasRenderingContext2D.getLineWidth, OffscreenCanvasRenderingContext2D.setLineWidth, .{});
    pub const lineCap = bridge.accessor(OffscreenCanvasRenderingContext2D.getLineCap, OffscreenCanvasRenderingContext2D.setLineCap, .{});
    pub const lineJoin = bridge.accessor(OffscreenCanvasRenderingContext2D.getLineJoin, OffscreenCanvasRenderingContext2D.setLineJoin, .{});
    pub const miterLimit = bridge.accessor(OffscreenCanvasRenderingContext2D.getMiterLimit, OffscreenCanvasRenderingContext2D.setMiterLimit, .{});
    pub const textAlign = bridge.accessor(OffscreenCanvasRenderingContext2D.getTextAlign, OffscreenCanvasRenderingContext2D.setTextAlign, .{});
    pub const textBaseline = bridge.accessor(OffscreenCanvasRenderingContext2D.getTextBaseline, OffscreenCanvasRenderingContext2D.setTextBaseline, .{});
    pub const fillStyle = bridge.accessor(OffscreenCanvasRenderingContext2D.getFillStyle, OffscreenCanvasRenderingContext2D.setFillStyle, .{});
    pub const createImageData = bridge.function(OffscreenCanvasRenderingContext2D.createImageData, .{});
    pub const putImageData = bridge.function(OffscreenCanvasRenderingContext2D.putImageData, .{});
    pub const drawImage = bridge.function(OffscreenCanvasRenderingContext2D.drawImage, .{});
    pub const getImageData = bridge.function(OffscreenCanvasRenderingContext2D.getImageData, .{});
    pub const save = bridge.function(OffscreenCanvasRenderingContext2D.save, .{});
    pub const restore = bridge.function(OffscreenCanvasRenderingContext2D.restore, .{});
    pub const scale = bridge.function(OffscreenCanvasRenderingContext2D.scale, .{});
    pub const rotate = bridge.function(OffscreenCanvasRenderingContext2D.rotate, .{});
    pub const translate = bridge.function(OffscreenCanvasRenderingContext2D.translate, .{});
    pub const transform = bridge.function(OffscreenCanvasRenderingContext2D.transform, .{});
    pub const setTransform = bridge.function(OffscreenCanvasRenderingContext2D.setTransform, .{});
    pub const resetTransform = bridge.function(OffscreenCanvasRenderingContext2D.resetTransform, .{});
    pub const clearRect = bridge.function(OffscreenCanvasRenderingContext2D.clearRect, .{});
    pub const fillRect = bridge.function(OffscreenCanvasRenderingContext2D.fillRect, .{});
    pub const strokeRect = bridge.function(OffscreenCanvasRenderingContext2D.strokeRect, .{});
    pub const beginPath = bridge.function(OffscreenCanvasRenderingContext2D.beginPath, .{});
    pub const closePath = bridge.function(OffscreenCanvasRenderingContext2D.closePath, .{});
    pub const moveTo = bridge.function(OffscreenCanvasRenderingContext2D.moveTo, .{});
    pub const lineTo = bridge.function(OffscreenCanvasRenderingContext2D.lineTo, .{});
    pub const quadraticCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.quadraticCurveTo, .{});
    pub const bezierCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.bezierCurveTo, .{});
    pub const arc = bridge.function(OffscreenCanvasRenderingContext2D.arc, .{});
    pub const arcTo = bridge.function(OffscreenCanvasRenderingContext2D.arcTo, .{});
    pub const rect = bridge.function(OffscreenCanvasRenderingContext2D.rect, .{});
    pub const fill = bridge.function(OffscreenCanvasRenderingContext2D.fill, .{});
    pub const stroke = bridge.function(OffscreenCanvasRenderingContext2D.stroke, .{});
    pub const clip = bridge.function(OffscreenCanvasRenderingContext2D.clip, .{ .noop = true });
    pub const fillText = bridge.function(OffscreenCanvasRenderingContext2D.fillText, .{});
    pub const strokeText = bridge.function(OffscreenCanvasRenderingContext2D.strokeText, .{});
};
