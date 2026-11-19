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

const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");
const GenericIterator = @import("collections/iterator.zig").Entry;
const Persona = @import("../../Persona.zig");
const MimeTypeArray = @import("MimeTypeArray.zig");

pub fn registerTypes() []const type {
    return &.{ PluginArray, Plugin, ValueIterator };
}

const PluginArray = @This();

/// SellGravity antidetect: what desktop Chrome (>= 94) exposes. Every entry
/// is the built-in PDF viewer under a different name, each handling the same
/// two MIME types. Chrome for Android exposes none.
pub const plugin_names = [_][]const u8{
    "PDF Viewer",
    "Chrome PDF Viewer",
    "Chromium PDF Viewer",
    "Microsoft Edge PDF Viewer",
    "WebKit built-in PDF",
};

// Created objects are cached on the Navigator (_pdf_plugins) so this struct stays one
// byte and never sits at the Navigator's offset 0 (JS identity map).
_pad: bool = false,

/// Whether this persona exposes the PDF plugins (desktop Chrome only).
pub fn exposed() bool {
    return Persona.active and !Persona.get().mobile and Persona.get().chrome_major > 0;
}

fn count() u32 {
    return if (exposed()) plugin_names.len else 0;
}

pub fn refresh(_: *const PluginArray) void {}

pub fn getAtIndex(_: *const PluginArray, index: usize, frame: *Frame) !?*Plugin {
    if (index >= count()) return null;
    const cache = &frame.window._navigator._pdf_plugins;
    if (cache[index]) |p| return p;
    const p = try frame._factory.create(Plugin{ ._index = @intCast(index) });
    cache[index] = p;
    return p;
}

pub fn getByName(self: *const PluginArray, name: []const u8, frame: *Frame) !?*Plugin {
    if (!exposed()) return null;
    for (plugin_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return self.getAtIndex(i, frame);
    }
    return null;
}

fn getLength(_: *const PluginArray) u32 {
    return count();
}

fn getIndexes(_: *const PluginArray, frame: *Frame) !js.Array {
    return indexList(count(), frame);
}

// Indexed enumerator: Object.keys / spread / for..in list "0".."n-1", as on
// Chrome's PluginArray, MimeTypeArray and Plugin.
fn indexList(n: u32, frame: *Frame) !js.Array {
    var arr = frame.js.local.?.newArray(n);
    for (0..n) |i| {
        _ = try arr.set(@intCast(i), i, .{});
    }
    return arr;
}

pub const Plugin = struct {
    _index: u8 = 0,

    fn getName(self: *const Plugin) []const u8 {
        return plugin_names[self._index];
    }
    fn getFilename(_: *const Plugin) []const u8 {
        return "internal-pdf-viewer";
    }
    fn getDescription(_: *const Plugin) []const u8 {
        return "Portable Document Format";
    }
    fn getLength(_: *const Plugin) u32 {
        return MimeTypeArray.mime_types.len;
    }
    /// The plugin's MIME types are the navigator.mimeTypes objects.
    fn item(_: *const Plugin, index: usize, frame: *Frame) !?*MimeTypeArray.MimeType {
        return frame.window._navigator._mime_types.getAtIndex(index, frame);
    }
    fn getIndexes(_: *const Plugin, frame: *Frame) !js.Array {
        return indexList(if (exposed()) MimeTypeArray.mime_types.len else 0, frame);
    }
    fn namedItem(_: *const Plugin, name: []const u8, frame: *Frame) !?*MimeTypeArray.MimeType {
        return frame.window._navigator._mime_types.getByName(name, frame);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Plugin);
        pub const Meta = struct {
            pub const name = "Plugin";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const name = bridge.accessor(Plugin.getName, null, .{});
        pub const filename = bridge.accessor(Plugin.getFilename, null, .{});
        pub const description = bridge.accessor(Plugin.getDescription, null, .{});
        pub const length = bridge.accessor(Plugin.getLength, null, .{});
        pub const @"[int]" = bridge.indexed(Plugin.item, Plugin.getIndexes, .{ .null_as_undefined = true });
        pub const item = bridge.function(struct {
            fn wrap(self: *const Plugin, index: i32, frame: *Frame) !?*MimeTypeArray.MimeType {
                if (index < 0) return null;
                return self.item(@intCast(index), frame);
            }
        }.wrap, .{});
        pub const namedItem = bridge.function(Plugin.namedItem, .{});
    };
};

fn values(self: *const PluginArray, frame: *Frame) !*ValueIterator {
    return .init(.{ .array = self }, frame);
}

const ValueIterator = GenericIterator(Iterator, null);

const Iterator = struct {
    array: *const PluginArray,
    index: usize = 0,

    pub fn next(self: *Iterator, frame: *Frame) !?*Plugin {
        const p = try self.array.getAtIndex(self.index, frame);
        if (p != null) self.index += 1;
        return p;
    }
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(PluginArray);

    pub const Meta = struct {
        pub const name = "PluginArray";
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const length = bridge.accessor(PluginArray.getLength, null, .{});
    pub const refresh = bridge.function(PluginArray.refresh, .{});
    pub const @"[int]" = bridge.indexed(PluginArray.getAtIndex, PluginArray.getIndexes, .{ .null_as_undefined = true });
    pub const @"[str]" = bridge.namedIndexed(PluginArray.getByName, null, null, null, struct {
        fn wrap(_: *const PluginArray, _: []const u8) !u32 {
            return error.NotHandled;
        }
    }.wrap, .{ .null_as_undefined = true });

    pub const item = bridge.function(struct {
        fn wrap(self: *const PluginArray, index: i32, frame: *Frame) !?*Plugin {
            if (index < 0) {
                return null;
            }
            return self.getAtIndex(@intCast(index), frame);
        }
    }.wrap, .{});

    pub const namedItem = bridge.function(PluginArray.getByName, .{});
    pub const symbol_iterator = bridge.iterator(PluginArray.values, .{});
};
