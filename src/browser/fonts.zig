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

//! SellGravity antidetect: the font list a launcher profile appears to have.
//!
//! Font fingerprinting measures a string in "<font>, <fallback>" and compares
//! it with the fallback alone: a different width means the font exists.
//! Lightpanda measures every family the same, which reads as "no fonts at
//! all" - impossible on the Windows/macOS/Android the UA claims. Here each
//! family of the persona's OS gets its own fixed width factor (like a real
//! face has its own metrics), unknown families fall through to the next one
//! in the list, exactly like CSS font fallback. --font-exclusion-list removes
//! families per profile, so profiles differ the way real machines do.

const std = @import("std");

const Persona = @import("../Persona.zig");

const windows_fonts = [_][]const u8{
    "arial",                  "arial black",          "arial narrow",       "bahnschrift",        "calibri",
    "calibri light",          "cambria",              "cambria math",       "candara",            "comic sans ms",
    "consolas",               "constantia",           "corbel",             "courier new",        "ebrima",
    "franklin gothic medium", "gabriola",             "gadugi",             "georgia",            "impact",
    "ink free",               "javanese text",        "leelawadee ui",      "lucida console",     "lucida sans unicode",
    "malgun gothic",          "marlett",              "microsoft himalaya", "microsoft jhenghei", "microsoft new tai lue",
    "microsoft phagspa",      "microsoft sans serif", "microsoft tai le",   "microsoft yahei",    "microsoft yi baiti",
    "mingliu-extb",           "mongolian baiti",      "ms gothic",          "mv boli",            "myanmar text",
    "nirmala ui",             "palatino linotype",    "segoe mdl2 assets",  "segoe print",        "segoe script",
    "segoe ui",               "segoe ui black",       "segoe ui emoji",     "segoe ui historic",  "segoe ui light",
    "segoe ui semibold",      "segoe ui semilight",   "segoe ui symbol",    "simsun",             "sitka small",
    "sylfaen",                "symbol",               "tahoma",             "times new roman",    "trebuchet ms",
    "verdana",                "webdings",             "wingdings",          "yu gothic",          "helvetica",
    "courier",                "times",
};

const mac_fonts = [_][]const u8{
    "american typewriter",   "andale mono", "arial",           "arial black", "arial narrow",
    "arial rounded mt bold", "avenir",      "avenir next",     "baskerville", "big caslon",
    "brush script mt",       "chalkboard",  "chalkboard se",   "charter",     "cochin",
    "comic sans ms",         "copperplate", "courier",         "courier new", "didot",
    "futura",                "geneva",      "georgia",         "gill sans",   "helvetica",
    "helvetica neue",        "herculanum",  "hoefler text",    "impact",      "lucida grande",
    "marker felt",           "menlo",       "monaco",          "noteworthy",  "optima",
    "palatino",              "papyrus",     "phosphate",       "rockwell",    "san francisco",
    "sf pro",                "skia",        "snell roundhand", "tahoma",      "times",
    "times new roman",       "trattatello", "trebuchet ms",    "verdana",     "zapfino",
};

const android_fonts = [_][]const u8{
    "roboto",           "noto sans",       "noto serif",  "droid sans",     "droid sans mono",
    "droid serif",      "cutive mono",     "coming soon", "dancing script", "carrois gothic sc",
    "noto color emoji", "source sans pro", "google sans",
};

const linux_fonts = [_][]const u8{
    "dejavu sans",     "dejavu sans mono", "dejavu serif", "liberation sans", "liberation serif",
    "liberation mono", "noto sans",        "noto serif",   "noto mono",       "ubuntu",
    "ubuntu mono",     "cantarell",        "freesans",     "freemono",        "freeserif",
};

fn installed(os: Persona.Os) []const []const u8 {
    return switch (os) {
        .windows => &windows_fonts,
        .macos, .ios => &mac_fonts,
        .android => &android_fonts,
        .linux, .chromeos => &linux_fonts,
    };
}

pub const Generic = enum { serif, sans, mono };

pub const Resolved = struct {
    /// Horizontal metrics factor relative to the bundled sans face.
    factor: f64,
    generic: Generic,
};

fn genericOf(name: []const u8) ?Generic {
    if (std.mem.eql(u8, name, "serif")) return .serif;
    if (std.mem.eql(u8, name, "monospace") or std.mem.eql(u8, name, "ui-monospace")) return .mono;
    if (std.mem.eql(u8, name, "sans-serif") or std.mem.eql(u8, name, "system-ui") or
        std.mem.eql(u8, name, "ui-sans-serif") or std.mem.eql(u8, name, "-apple-system") or
        std.mem.eql(u8, name, "blinkmacsystemfont") or std.mem.eql(u8, name, "cursive") or
        std.mem.eql(u8, name, "fantasy") or std.mem.eql(u8, name, "ui-rounded")) return .sans;
    if (std.mem.eql(u8, name, "ui-serif")) return .serif;
    return null;
}

fn genericFactor(g: Generic) f64 {
    return switch (g) {
        .sans => 1.0,
        .serif => 0.92,
        .mono => 1.16,
    };
}

fn looksMono(name: []const u8) bool {
    const marks = [_][]const u8{ "mono", "courier", "consolas", "console", "menlo", "monaco", "typewriter" };
    for (marks) |m| {
        if (std.mem.find(u8, name, m) != null) return true;
    }
    return false;
}

fn looksSerif(name: []const u8) bool {
    const marks = [_][]const u8{ "times", "georgia", "serif", "cambria", "palatino", "garamond", "baskerville", "didot", "cochin", "constantia", "book antiqua", "sylfaen" };
    for (marks) |m| {
        if (std.mem.find(u8, name, m) != null and std.mem.find(u8, name, "sans") == null) return true;
    }
    return false;
}

fn excluded(name: []const u8) bool {
    const list = Persona.get().font_exclusion orelse return false;
    var it = std.mem.splitAny(u8, list, ",;|");
    while (it.next()) |raw| {
        const e = std.mem.trim(u8, raw, " \t\"'");
        if (e.len > 0 and std.ascii.eqlIgnoreCase(e, name)) return true;
    }
    return false;
}

/// The face a CSS `font-family` list resolves to for this persona. Null when
/// the persona is off (upstream measures every family alike).
pub fn resolve(family_list: []const u8) ?Resolved {
    if (!Persona.active) return null;
    const os = Persona.get().os;
    var it = std.mem.splitScalar(u8, family_list, ',');
    while (it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\n\r\"'");
        if (trimmed.len == 0 or trimmed.len > 64) continue;
        var buf: [64]u8 = undefined;
        const name = std.ascii.lowerString(&buf, trimmed);
        if (genericOf(name)) |g| return .{ .factor = genericFactor(g), .generic = g };
        for (installed(os)) |f| {
            if (!std.mem.eql(u8, f, name)) continue;
            if (excluded(trimmed)) break;
            const g: Generic = if (looksMono(name)) .mono else if (looksSerif(name)) .serif else .sans;
            // A fixed per-face factor: the same font measures the same on
            // every profile (like real metrics), distinct fonts differ.
            const h = std.hash.Wyhash.hash(0x666f6e74, name);
            const spread: f64 = @floatFromInt(h % 2400);
            const base = genericFactor(g);
            return .{ .factor = base * (0.88 + spread / 10000.0), .generic = g };
        }
    }
    // Chrome's default standard font: Times New Roman on desktop, Roboto
    // (sans) on Android.
    return if (os == .android) .{ .factor = 1.0, .generic = .sans } else .{ .factor = genericFactor(.serif), .generic = .serif };
}

/// The family list out of a CSS `font` shorthand ("italic bold 12px/1.5 A, B").
pub fn familyFromShorthand(font: []const u8) []const u8 {
    // The family list starts after the size token (the one with a unit).
    var it = std.mem.tokenizeAny(u8, font, " \t");
    var offset: usize = 0;
    while (it.next()) |tok| {
        const start = @intFromPtr(tok.ptr) - @intFromPtr(font.ptr);
        offset = start + tok.len;
        const t = tok[0 .. std.mem.findScalar(u8, tok, '/') orelse tok.len];
        if (t.len > 0 and std.ascii.isDigit(t[0]) and (std.mem.endsWith(u8, t, "px") or std.mem.endsWith(u8, t, "pt") or
            std.mem.endsWith(u8, t, "em") or std.mem.endsWith(u8, t, "%")))
        {
            return std.mem.trim(u8, font[offset..], " \t");
        }
    }
    return font;
}

const testing = std.testing;

test "fonts: shorthand family" {
    try testing.expectEqualStrings("\"Times New Roman\"", familyFromShorthand("11pt \"Times New Roman\""));
    try testing.expectEqualStrings("Arial, sans-serif", familyFromShorthand("italic bold 12px/1.5 Arial, sans-serif"));
}
