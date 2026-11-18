// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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

const js = @import("../../js/js.zig");
const color = @import("../../color.zig");

const Execution = js.Execution;

/// A gradient keeps its geometry and stops so the SellGravity canvas
/// rasterizer (raster.zig) can paint it.
const CanvasGradient = @This();

pub const Stop = struct {
    offset: f64,
    color: color.RGBA,
};

const max_stops = 16;

/// 0 none (conic: painted as its first stop), 1 linear, 2 radial.
_kind: u32 = 0,
/// linear: x0 y0 x1 y1; radial: x0 y0 r0 x1 y1 r1.
_coords: [6]f64 = @splat(0),
_stops: [max_stops]Stop = undefined,
_stops_len: u8 = 0,

pub fn init(exec: *const Execution) !*CanvasGradient {
    return exec._factory.create(CanvasGradient{});
}

pub fn initGeometry(kind: u32, coords: [6]f64, exec: *const Execution) !*CanvasGradient {
    return exec._factory.create(CanvasGradient{ ._kind = kind, ._coords = coords });
}

fn addColorStop(self: *CanvasGradient, offset: f64, value: []const u8) !void {
    if (!(offset >= 0 and offset <= 1)) return error.IndexSizeError;
    const c = color.parseCanvasColor(value) orelse return error.SyntaxError;
    if (self._stops_len < max_stops) {
        self._stops[self._stops_len] = .{ .offset = offset, .color = c };
        self._stops_len += 1;
    }
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(CanvasGradient);

    pub const Meta = struct {
        pub const name = "CanvasGradient";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const addColorStop = bridge.function(CanvasGradient.addColorStop, .{});
};
