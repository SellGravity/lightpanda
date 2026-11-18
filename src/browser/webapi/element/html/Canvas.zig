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

const Frame = @import("../../../Frame.zig");
const Factory = @import("../../../Factory.zig");

const Blob = @import("../../Blob.zig");
const Node = @import("../../Node.zig");
const Element = @import("../../Element.zig");

const OffscreenCanvas = @import("../../canvas/OffscreenCanvas.zig");
const WebGLRenderingContext = @import("../../canvas/WebGLRenderingContext.zig");
const CanvasRenderingContext2D = @import("../../canvas/CanvasRenderingContext2D.zig");

const HtmlElement = @import("../Html.zig");

const js = lp.js;
const log = lp.log;
const Execution = js.Execution;
const BlankPNG = OffscreenCanvas.BlankPNG;
const raster = @import("../../canvas/raster.zig");

const Canvas = @This();

pub const Proto = HtmlElement;
_proto_canary: if (lp.IS_DEBUG) *HtmlElement else void = undefined,
_cached: ?DrawingContext = null,

pub fn asElement(self: *Canvas) *Element {
    return Factory.protoOf(self).asElement();
}
pub fn asConstElement(self: *const Canvas) *const Element {
    return Factory.protoOf(self).asElement();
}
pub fn asNode(self: *Canvas) *Node {
    return self.asElement().asNode();
}

pub fn getWidth(self: *const Canvas) u32 {
    const attr = self.asConstElement().getAttributeInterned("width") orelse return 300;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 300;
}

pub fn getHeight(self: *const Canvas) u32 {
    const attr = self.asConstElement().getAttributeInterned("height") orelse return 150;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 150;
}

/// Since there's no base class rendering contexts inherit from,
/// we're using tagged union.
const DrawingContext = union(enum) {
    @"2d": *CanvasRenderingContext2D,
    webgl: *WebGLRenderingContext,
};

fn getContext(self: *Canvas, context_type: []const u8, frame: *Frame) !?DrawingContext {
    if (self._cached) |cached| {
        const matches = switch (cached) {
            .@"2d" => std.mem.eql(u8, context_type, "2d"),
            .webgl => |gl| if (gl._version == 2)
                std.mem.eql(u8, context_type, "webgl2")
            else
                std.mem.eql(u8, context_type, "webgl") or std.mem.eql(u8, context_type, "experimental-webgl"),
        };
        return if (matches) cached else null;
    }

    const drawing_context: DrawingContext = blk: {
        if (std.mem.eql(u8, context_type, "2d")) {
            const ctx = try frame._factory.create(CanvasRenderingContext2D{ ._canvas = self });
            break :blk .{ .@"2d" = ctx };
        }

        // We only stub a tiny slice of the WebGL API (getParameter,
        // getExtension, getSupportedExtensions). Real WebGL consumers like
        // Three.js immediately call createTexture/createBuffer/etc. and
        // throw `TypeError: e.createTexture is not a function`. Pretending
        // WebGL works until the first non-stubbed call is the worst of both
        // worlds: pages that have an error boundary above the WebGL widget
        // catch the throw, reset, re-render, and loop forever.
        // Spec-correct signal for "no WebGL" is null, so apps that check
        // (Three.js does) can degrade gracefully.
        // SellGravity antidetect: launcher profiles get a WebGL 1 context
        // reporting the persona GPU; a real Chrome never lacks WebGL.
        if (WebGLRenderingContext.enabled() and isWebGL(context_type)) {
            const version: u8 = if (std.mem.eql(u8, context_type, "webgl2")) 2 else 1;
            const ctx = try WebGLRenderingContext.create(frame, self.getWidth(), self.getHeight(), version);
            break :blk .{ .webgl = ctx };
        }

        if (isWebGL(context_type)) {
            frame.page.status.noteUnsupported(.webgl);
        }
        return null;
    };
    self._cached = drawing_context;
    return drawing_context;
}

pub fn isWebGL(context_type: []const u8) bool {
    inline for (&.{ "webgl", "webgl2", "experimental-webgl" }) |needle| {
        if (std.mem.eql(u8, context_type, needle)) {
            return true;
        }
    }
    return false;
}

fn hasBitmap(self: *const Canvas) bool {
    return BlankPNG.hasBitmap(self.getWidth(), self.getHeight());
}

/// Serializes the canvas, always as the blank PNG. Per spec an unsupported
/// `type` falls back to image/png, and with nothing drawn there is no lossy
/// encoding for `quality` to control, so both arguments are ignored.
fn toDataURL(self: *const Canvas, _: ?[]const u8, _: ?f64, exec: *const Execution) ![]const u8 {
    // SellGravity antidetect: the real pixels (drawn ops + profile noise) at
    // the canvas size, like Chrome; upstream returns a 1x1 blank PNG.
    if (try self.personaPixels(exec)) |px| {
        return raster.dataUrl(exec.call_arena, px, self.getWidth(), self.getHeight());
    }
    // Per spec, a canvas with no pixels serializes to this exact string.
    return if (self.hasBitmap()) BlankPNG.data_url else "data:,";
}

/// Launcher profiles only: the canvas pixels as straight RGBA, or null to
/// keep upstream behaviour (no persona, no bitmap, or too large to encode).
fn personaPixels(self: *const Canvas, exec: *const Execution) !?[]u8 {
    if (!lp.Persona.active or !self.hasBitmap()) return null;
    const w = self.getWidth();
    const h = self.getHeight();
    if (@as(u64, w) * h > 4096 * 4096) return null;
    if (self._cached) |cached| switch (cached) {
        .@"2d" => |ctx| if (try ctx.renderPixels(exec.call_arena, exec, w, h)) |px| return px,
        .webgl => {},
    };
    const out = try exec.call_arena.alloc(u8, @as(usize, w) * h * 4);
    @memset(out, 0);
    return out;
}

/// Same image as `toDataURL`, handed to `callback` as a Blob from a task.
/// A canvas with no pixels calls back with null, per spec.
pub fn toBlob(self: *const Canvas, callback: js.Function.Global, _: ?[]const u8, _: ?f64, exec: *Execution) !void {
    // SellGravity antidetect: encode now (the spec snapshots the bitmap at
    // call time), deliver from the task.
    var png: ?[]const u8 = null;
    if (try self.personaPixels(exec)) |px| {
        png = try raster.pngBytes(exec.page_arena, px, self.getWidth(), self.getHeight());
    }
    const task = try exec._factory.create(ToBlobCallback{
        .exec = exec,
        .png = png,
        // The spec checks the bitmap now, not when the task runs.
        .has_bitmap = self.hasBitmap(),
        .callback = callback,
    });
    errdefer exec._factory.destroy(task);

    try exec._scheduler.add(task, ToBlobCallback.run, 0, .{
        .name = "canvas.toBlob",
        .finalizer = ToBlobCallback.cancelled,
    });
}

const ToBlobCallback = struct {
    exec: *Execution,
    has_bitmap: bool,
    png: ?[]const u8 = null,
    callback: js.Function.Global,

    fn cancelled(ctx: *anyopaque) void {
        const self: *ToBlobCallback = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn deinit(self: *ToBlobCallback) void {
        self.callback.release();
        self.exec._factory.destroy(self);
    }

    fn run(ctx: *anyopaque) !?u32 {
        const self: *ToBlobCallback = @ptrCast(@alignCast(ctx));
        defer self.deinit();
        const exec = self.exec;

        var blob: ?*Blob = null;
        if (self.has_bitmap) {
            const b = if (self.png) |bytes| try Blob.initFromBytes(bytes, "image/png", exec) else try BlankPNG.blob(exec);
            // The page can hold on to the Blob, in which case the JS wrapper
            // takes its own ref; ours only has to cover the call.
            b.acquireRef();
            blob = b;
        }
        defer if (blob) |b| {
            b.releaseRef(exec.page);
        };

        var ls: js.Local.Scope = undefined;
        exec.js.localScope(&ls);
        defer ls.deinit();

        ls.toLocal(self.callback).call(void, .{blob}) catch |err| {
            exec.page.recordJsError(err);
            log.debug(.js, "canvas.toBlob", .{ .err = err });
        };
        ls.local.runMicrotasks();
        return null;
    }
};

/// Transfers control of the canvas to an OffscreenCanvas.
/// Returns an OffscreenCanvas with the same dimensions.
fn transferControlToOffscreen(self: *Canvas, exec: *Execution) !*OffscreenCanvas {
    const width = self.getWidth();
    const height = self.getHeight();
    return OffscreenCanvas.constructor(width, height, exec);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Canvas);

    pub const Meta = struct {
        pub const name = "HTMLCanvasElement";
        pub var class_id: bridge.ClassId = undefined;
    };

    const reflect = Element.Reflect(Canvas);

    pub const width = reflect.unsignedLong("width", .{ .default = 300 });
    pub const height = reflect.unsignedLong("height", .{ .default = 150 });
    pub const getContext = bridge.function(Canvas.getContext, .{});
    pub const toDataURL = bridge.function(Canvas.toDataURL, .{});
    pub const toBlob = bridge.function(Canvas.toBlob, .{});
    pub const transferControlToOffscreen = bridge.function(Canvas.transferControlToOffscreen, .{});
};

const testing = @import("../../../../testing.zig");
test "WebApi: HTMLCanvasElement serialization" {
    try testing.htmlRunner("canvas/canvas_serialization.html", .{});
}
