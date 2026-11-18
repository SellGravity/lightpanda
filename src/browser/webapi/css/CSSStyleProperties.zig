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

const Frame = @import("../../Frame.zig");
const Factory = @import("../../Factory.zig");
const CSSStyleDeclaration = @import("CSSStyleDeclaration.zig");
const properties = @import("../../css/properties.zig");
const chrome_computed = @import("chrome_computed.zig");

const Allocator = std.mem.Allocator;

const CSSStyleProperties = @This();

pub const Proto = CSSStyleDeclaration;

_proto_canary: if (lp.IS_DEBUG) *CSSStyleDeclaration else void = undefined,

pub fn init(owner: CSSStyleDeclaration.Owner, frame: *Frame) !*CSSStyleProperties {
    const self = try frame._factory.chained(.{
        CSSStyleDeclaration{ ._owner = owner },
        CSSStyleProperties{},
    });
    try self.asCSSStyleDeclaration().parseInlineStyle(frame);
    return self;
}

pub fn asCSSStyleDeclaration(self: *CSSStyleProperties) *CSSStyleDeclaration {
    return Factory.protoOf(self);
}

fn setNamed(self: *CSSStyleProperties, name: []const u8, value: js.Value, frame: *Frame) !void {
    if (method_names.has(name)) {
        return error.NotHandled;
    }
    const dash_case = try camelCaseToDashCase(frame.local_arena, name);
    // `[LegacyNullToEmptyString] CSSOMString`: a JS null becomes "", which
    // removes the declaration, instead of the string "null".
    try self.asCSSStyleDeclaration().setProperty(dash_case, if (value.isNull()) "" else try value.toZig([]const u8), null, frame);
}

fn getNamed(self: *CSSStyleProperties, name: []const u8, frame: *Frame) ![]const u8 {
    if (method_names.has(name)) {
        return error.NotHandled;
    }

    const dash_case = try camelCaseToDashCase(frame.local_arena, name);

    // Only apply vendor prefix filtering for camelCase access (no dashes in input)
    // Bracket notation with dash-case (e.g., div.style['-moz-user-select']) should return the actual value
    const is_camelcase_access = std.mem.findScalar(u8, name, '-') == null;
    if (is_camelcase_access and std.mem.startsWith(u8, dash_case, "-")) {
        // We only support -webkit-, other vendor prefixes return undefined for camelCase access
        const is_webkit = std.mem.startsWith(u8, dash_case, "-webkit-");
        const is_moz = std.mem.startsWith(u8, dash_case, "-moz-");
        const is_ms = std.mem.startsWith(u8, dash_case, "-ms-");
        const is_o = std.mem.startsWith(u8, dash_case, "-o-");

        if ((is_moz or is_ms or is_o) and !is_webkit) {
            return error.NotHandled;
        }
    }

    const value = self.asCSSStyleDeclaration().getPropertyValue(dash_case, frame);

    // Known properties read '' when not set, unknown ones are undefined (and
    // so not `in` the declaration).
    if (value.len == 0 and properties.isKnown(dash_case) == false and !personaKnows(name)) {
        return error.NotHandled;
    }
    return value;
}

fn camelCaseToDashCase(allocator: Allocator, name: []const u8) ![]const u8 {
    if (name.len == 0) {
        return name;
    }

    // Special case: cssFloat -> float
    if (std.ascii.eqlIgnoreCase(name, "cssfloat")) {
        return "float";
    }

    // If already contains dashes, just return lowercased
    if (std.mem.findScalar(u8, name, '-')) |_| {
        return std.ascii.allocLowerString(allocator, name);
    }

    // The CSSOM's webkit-cased attribute: WebkitTransform -> -webkit-transform
    if (name.len > 6 and std.mem.startsWith(u8, name, "Webkit") and std.ascii.isUpper(name[6])) {
        const lowered = try allocator.dupe(u8, name);
        lowered[0] = 'w';
        return camelCaseToDashCase(allocator, lowered);
    }

    // Check if this looks like proper camelCase (starts with lowercase)
    // If not (e.g. "COLOR", "BackgroundColor"), just lowercase it
    if (name.len == 0 or !std.ascii.isLower(name[0])) {
        return std.ascii.allocLowerString(allocator, name);
    }

    // Check for vendor prefixes: webkitTransform -> -webkit-transform
    // Must have uppercase letter after the prefix
    const has_vendor_prefix = blk: {
        if (name.len > 6 and std.mem.startsWith(u8, name, "webkit") and std.ascii.isUpper(name[6])) break :blk true;
        if (name.len > 3 and std.mem.startsWith(u8, name, "moz") and std.ascii.isUpper(name[3])) break :blk true;
        if (name.len > 2 and std.mem.startsWith(u8, name, "ms") and std.ascii.isUpper(name[2])) break :blk true;
        if (name.len > 1 and std.mem.startsWith(u8, name, "o") and std.ascii.isUpper(name[1])) break :blk true;
        break :blk false;
    };

    // Every character, plus a dash before each uppercase one and the vendor
    // prefix's leading dash.
    var len = name.len + @intFromBool(has_vendor_prefix);
    for (name) |c| {
        len += @intFromBool(std.ascii.isUpper(c));
    }
    const buf = try allocator.alloc(u8, len);
    var write_pos: usize = 0;

    if (has_vendor_prefix) {
        buf[write_pos] = '-';
        write_pos += 1;
    }

    for (name, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            const skip_dash = has_vendor_prefix and i < 10 and write_pos == 1;

            if (i > 0 and !skip_dash) {
                buf[write_pos] = '-';
                write_pos += 1;
            }
            buf[write_pos] = std.ascii.toLower(c);
            write_pos += 1;
        } else {
            buf[write_pos] = c;
            write_pos += 1;
        }
    }

    return buf[0..write_pos];
}

// style[0], Object.keys(style): the declared (or, computed, enumerated)
// property names by index, as CSSStyleDeclaration's indexed getter.
fn indexedGet(self: *CSSStyleProperties, index: usize, frame: *Frame) ![]const u8 {
    const decl = self.asCSSStyleDeclaration();
    if (index >= decl.length()) return error.NotHandled;
    return decl.item(@intCast(index), frame);
}

fn getIndexes(self: *CSSStyleProperties, frame: *Frame) !js.Array {
    const len = self.asCSSStyleDeclaration().length();
    var arr = frame.js.local.?.newArray(len);
    for (0..len) |i| {
        _ = try arr.set(@intCast(i), i, .{});
    }
    return arr;
}

// SellGravity antidetect: Chrome's style objects list every supported
// property's camelCase name as an own enumerable property.
fn personaKnows(name: []const u8) bool {
    if (!lp.Persona.active) return false;
    for (chrome_computed.camelNames(lp.Persona.get().chrome_major)) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    for (chrome_computed.names(lp.Persona.get().chrome_major)) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

fn getNames(_: *CSSStyleProperties, frame: *Frame) !js.Array {
    const list: []const []const u8 = if (lp.Persona.active) chrome_computed.camelNames(lp.Persona.get().chrome_major) else &.{};
    var arr = frame.js.local.?.newArray(@intCast(list.len));
    for (list, 0..) |name, i| {
        _ = try arr.set(@intCast(i), name, .{});
    }
    return arr;
}

const method_names = std.StaticStringMap(void).initComptime(.{
    .{ "getPropertyValue", {} },
    .{ "setProperty", {} },
    .{ "removeProperty", {} },
    .{ "getPropertyPriority", {} },
    .{ "item", {} },
    .{ "cssText", {} },
    .{ "length", {} },
});

pub const JsApi = struct {
    pub const bridge = js.Bridge(CSSStyleProperties);

    pub const Meta = struct {
        pub const name = "CSSStyleProperties";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const @"[int]" = bridge.indexed(indexedGet, getIndexes, .{});
    pub const @"[]" = bridge.namedIndexed(CSSStyleProperties.getNamed, CSSStyleProperties.setNamed, null, getNames, null, .{ .ce_reactions = true });
};
