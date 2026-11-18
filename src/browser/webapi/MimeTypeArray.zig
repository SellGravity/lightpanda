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
const PluginArray = @import("PluginArray.zig");

pub fn registerTypes() []const type {
    return &.{ MimeTypeArray, MimeType, ValueIterator };
}

const MimeTypeArray = @This();

/// SellGravity antidetect: the two types desktop Chrome's PDF viewer handles.
pub const mime_types = [_][]const u8{ "application/pdf", "text/pdf" };

// Created objects are cached on the Navigator (_pdf_mimes) so this struct stays one
// byte and never sits at the Navigator's offset 0 (JS identity map).
_pad: bool = false,

fn count() u32 {
    return if (PluginArray.exposed()) mime_types.len else 0;
}

pub fn getAtIndex(_: *const MimeTypeArray, index: usize, frame: *Frame) !?*MimeType {
    if (index >= count()) return null;
    const cache = &frame.window._navigator._pdf_mimes;
    if (cache[index]) |m| return m;
    const m = try frame._factory.create(MimeType{ ._index = @intCast(index) });
    cache[index] = m;
    return m;
}

pub fn getByName(self: *const MimeTypeArray, name: []const u8, frame: *Frame) !?*MimeType {
    if (!PluginArray.exposed()) return null;
    for (mime_types, 0..) |t, i| {
        if (std.mem.eql(u8, t, name)) return self.getAtIndex(i, frame);
    }
    return null;
}

fn getLength(_: *const MimeTypeArray) u32 {
    return count();
}

pub const MimeType = struct {
    _index: u8 = 0,

    fn getType(self: *const MimeType) []const u8 {
        return mime_types[self._index];
    }
    fn getSuffixes(_: *const MimeType) []const u8 {
        return "pdf";
    }
    fn getDescription(_: *const MimeType) []const u8 {
        return "Portable Document Format";
    }
    /// Chrome points every PDF MIME type at the first plugin ("PDF Viewer").
    fn getEnabledPlugin(_: *const MimeType, frame: *Frame) !?*PluginArray.Plugin {
        return frame.window._navigator._plugins.getAtIndex(0, frame);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeType);
        pub const Meta = struct {
            pub const name = "MimeType";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const @"type" = bridge.accessor(MimeType.getType, null, .{});
        pub const suffixes = bridge.accessor(MimeType.getSuffixes, null, .{});
        pub const description = bridge.accessor(MimeType.getDescription, null, .{});
        pub const enabledPlugin = bridge.accessor(MimeType.getEnabledPlugin, null, .{});
    };
};

fn values(self: *const MimeTypeArray, frame: *Frame) !*ValueIterator {
    return .init(.{ .array = self }, frame);
}

const ValueIterator = GenericIterator(Iterator, null);

const Iterator = struct {
    array: *const MimeTypeArray,
    index: usize = 0,

    pub fn next(self: *Iterator, frame: *Frame) !?*MimeType {
        const m = try self.array.getAtIndex(self.index, frame);
        if (m != null) self.index += 1;
        return m;
    }
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(MimeTypeArray);

    pub const Meta = struct {
        pub const name = "MimeTypeArray";
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const length = bridge.accessor(MimeTypeArray.getLength, null, .{});
    pub const @"[int]" = bridge.indexed(MimeTypeArray.getAtIndex, null, .{ .null_as_undefined = true });
    pub const @"[str]" = bridge.namedIndexed(MimeTypeArray.getByName, null, null, null, struct {
        fn wrap(_: *const MimeTypeArray, _: []const u8) !u32 {
            return error.NotHandled;
        }
    }.wrap, .{ .null_as_undefined = true });

    pub const item = bridge.function(struct {
        fn wrap(self: *const MimeTypeArray, index: i32, frame: *Frame) !?*MimeType {
            if (index < 0) {
                return null;
            }
            return self.getAtIndex(@intCast(index), frame);
        }
    }.wrap, .{});

    pub const namedItem = bridge.function(MimeTypeArray.getByName, .{});
    pub const symbol_iterator = bridge.iterator(MimeTypeArray.values, .{});
};
