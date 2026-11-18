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

const std = @import("std");
const lp = @import("lightpanda");

const js = @import("../../js/js.zig");
const Page = @import("../../Page.zig");
const Frame = @import("../../Frame.zig");
const fonts = @import("../../fonts.zig");

const FontFace = @This();

_rc: lp.RC = .{},
_arena: *lp.Arena,
_family: []const u8,
// SellGravity antidetect: `local("X")` sources resolve against the persona's
// font list (fonts.zig), like Chrome resolving installed fonts.
_local: ?[]const u8 = null,
_failed: bool = false,

pub fn init(family: []const u8, source: []const u8, frame: *Frame) !*FontFace {
    const arena = try frame.getArena(.tiny, "FontFace");
    errdefer arena.release();

    const self = try arena.create(FontFace);
    self.* = .{
        ._arena = arena,
        ._family = try arena.dupe(u8, family),
    };
    if (localName(source)) |name| self._local = try arena.dupe(u8, name);
    return self;
}

pub fn deinit(self: *FontFace, _: *Page) void {
    self._arena.release();
}

pub fn releaseRef(self: *FontFace, page: *Page) void {
    self._rc.release(self, page);
}

pub fn acquireRef(self: *FontFace) void {
    self._rc.acquire();
}

fn getFamily(self: *const FontFace) []const u8 {
    return self._family;
}

/// The font name in a `local(...)` source (first one), or null.
fn localName(source: []const u8) ?[]const u8 {
    const s = std.mem.trim(u8, source, &std.ascii.whitespace);
    if (!std.ascii.startsWithIgnoreCase(s, "local(")) return null;
    const end = std.mem.findScalar(u8, s, ')') orelse return null;
    return std.mem.trim(u8, s["local(".len..end], " \t\"'");
}

fn available(self: *const FontFace) bool {
    const name = self._local orelse return true;
    return fonts.isInstalled(name) orelse true;
}

// load() resolves with the face (Chrome's shape). A local() font the
// persona does not have rejects with a NetworkError, like Chrome.
pub fn load(self: *FontFace, frame: *Frame) !js.Promise {
    if (!self.available()) {
        self._failed = true;
        return frame.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.NetworkError } });
    }
    return frame.js.local.?.resolvePromise(self);
}

fn getLoaded(self: *FontFace, frame: *Frame) !js.Promise {
    return self.load(frame);
}

fn getStatus(self: *const FontFace) []const u8 {
    return if (self._failed) "error" else "loaded";
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(FontFace);

    pub const Meta = struct {
        pub const name = "FontFace";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(FontFace.init, .{});
    pub const family = bridge.accessor(FontFace.getFamily, null, .{});
    pub const status = bridge.accessor(FontFace.getStatus, null, .{});
    pub const style = bridge.property("normal", .{ .template = false, .readonly = true });
    pub const weight = bridge.property("normal", .{ .template = false, .readonly = true });
    pub const stretch = bridge.property("normal", .{ .template = false, .readonly = true });
    pub const unicodeRange = bridge.property("U+0-10FFFF", .{ .template = false, .readonly = true });
    pub const variant = bridge.property("normal", .{ .template = false, .readonly = true });
    pub const featureSettings = bridge.property("normal", .{ .template = false, .readonly = true });
    pub const display = bridge.property("auto", .{ .template = false, .readonly = true });
    pub const loaded = bridge.accessor(FontFace.getLoaded, null, .{});
    pub const load = bridge.function(FontFace.load, .{});
};

const testing = @import("../../../testing.zig");
test "WebApi: FontFace" {
    try testing.htmlRunner("css/font_face.html", .{});
}
