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

//! SellGravity antidetect: drawImage sources as straight RGBA, shared by the
//! on-screen and offscreen 2D contexts. Supported: <img> with a PNG data URL
//! (what canvas round-trip checks use), <canvas> and OffscreenCanvas (their
//! recorded drawing, rendered with the profile's noise).

const std = @import("std");

const js = @import("../../js/js.zig");
const raster = @import("raster.zig");
const Image = @import("../element/html/Image.zig");
const Canvas = @import("../element/html/Canvas.zig");
const OffscreenCanvas = @import("OffscreenCanvas.zig");

const Execution = js.Execution;

/// CanvasImageSource. Pointer variants first: the bridge probes them for an
/// exact match before the catch-all.
pub const Source = union(enum) {
    image: *Image,
    canvas: *Canvas,
    offscreen: *OffscreenCanvas,
    other: js.Value,
};

fn blank(exec: *const Execution, w: u32, h: u32) ?raster.Decoded {
    if (w == 0 or h == 0 or @as(u64, w) * h > 4096 * 4096) return null;
    const px = exec.call_arena.alloc(u8, @as(usize, w) * h * 4) catch return null;
    @memset(px, 0);
    return .{ .rgba = px, .w = w, .h = h };
}

pub fn pixels(source: Source, exec: *const Execution) ?raster.Decoded {
    switch (source) {
        .image => |img| {
            const src = img.asConstElement().getAttributeInterned("src") orelse return null;
            return raster.decodePngDataUrl(exec.call_arena, src);
        },
        .canvas => |c| {
            const w = c.getWidth();
            const h = c.getHeight();
            if (c._cached) |cached| switch (cached) {
                .@"2d" => |ctx| {
                    const px = (ctx.renderPixels(exec.call_arena, exec, w, h) catch null) orelse return blank(exec, w, h);
                    return .{ .rgba = px, .w = w, .h = h };
                },
                .webgl => {},
            };
            return blank(exec, w, h);
        },
        .offscreen => |c| {
            const w = c.getWidth();
            const h = c.getHeight();
            if (c._cached) |cached| switch (cached) {
                .@"2d" => |ctx| {
                    const px = (ctx.renderPixels(exec.call_arena, exec, w, h) catch null) orelse return blank(exec, w, h);
                    return .{ .rgba = px, .w = w, .h = h };
                },
                .webgl => {},
            };
            return blank(exec, w, h);
        },
        .other => return null,
    }
}

/// Resolves drawImage's 3 / 5 / 9 argument forms and records the draw.
pub fn record(rec: *raster.Recorder, paint: *const raster.Paint, source: Source, a: [8]?f64, exec: *const Execution) !void {
    const img = pixels(source, exec) orelse return;
    const iw: f64 = @floatFromInt(img.w);
    const ih: f64 = @floatFromInt(img.h);
    var argc: usize = 0;
    for (a) |v| {
        if (v == null) break;
        argc += 1;
    }
    switch (argc) {
        2 => try rec.drawImage(paint, img.rgba, img.w, img.h, 0, 0, iw, ih, a[0].?, a[1].?, iw, ih),
        4 => try rec.drawImage(paint, img.rgba, img.w, img.h, 0, 0, iw, ih, a[0].?, a[1].?, a[2].?, a[3].?),
        8 => try rec.drawImage(paint, img.rgba, img.w, img.h, a[0].?, a[1].?, a[2].?, a[3].?, a[4].?, a[5].?, a[6].?, a[7].?),
        else => return error.TypeError,
    }
}
