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

//! SellGravity antidetect persona.
//!
//! The InviBrowser launcher starts every engine with the same Chromium-style
//! switches (`--user-agent=...`, `--hardware-concurrency=8`, `--window-size=W,H`,
//! `--proxy-server=socks5://u:p@h:p`, ...; see gravbrowser
//! electron/modules/chromium/chromium-flags.builder.ts). `translateArgs` takes
//! those out of argv before Config parsing, fills the process-wide persona,
//! and rewrites the few that map onto native Lightpanda options (`--port`,
//! `--timezone`, `--locale`, `--http-proxy`). One Lightpanda process serves
//! one launcher profile, so a process-global persona is the right scope.
//!
//! When no launcher switch is present `active` stays false and every getter
//! returns upstream's behaviour, so the upstream test-suite keeps passing.

const std = @import("std");
const builtin = @import("builtin");

const Viewport = @import("browser/Viewport.zig");

const Allocator = std.mem.Allocator;

const Persona = @This();

pub const Os = enum { windows, macos, linux, android, ios, chromeos };

pub const Brand = struct {
    brand: []const u8,
    version: []const u8,
};

pub const WebRtcMode = enum { default, disable, forward, replace };

pub const LocationMode = enum { default, block, allow, ask };

/// True once any launcher switch was seen.
pub var active: bool = false;
/// The process-wide persona. Written once in `translateArgs`, read-only after.
pub var current: Persona = .{};

// --- identity --------------------------------------------------------------
user_agent: ?[:0]const u8 = null,
os: Os = hostOs(),
mobile: bool = false,
/// Chrome major version parsed from the UA, 0 when the UA is not Chrome.
chrome_major: u32 = 0,
/// Full Chrome version for high-entropy client hints ("140.0.7339.128").
full_version: []const u8 = "",
platform_version: []const u8 = "",
model: []const u8 = "",
brands: [3]Brand = undefined,
brands_full: [3]Brand = undefined,
brand_count: usize = 0,
sec_ch_ua: ?[:0]const u8 = null,
sec_ch_ua_platform: ?[:0]const u8 = null,
app_version: ?[]const u8 = null,

// --- hardware --------------------------------------------------------------
hardware_concurrency: u32 = 4,
device_memory: f64 = 8.0,
max_touch_points: u32 = 0,

// --- screen / window -------------------------------------------------------
screen_width: ?u32 = null,
screen_height: ?u32 = null,
/// Pixels the OS reserves at the bottom/top (taskbar, menu bar, status bar).
avail_height_reserved: u32 = 0,
outer_width: ?u32 = null,
outer_height: ?u32 = null,
inner_width: ?u32 = null,
inner_height: ?u32 = null,
screen_x: i32 = 0,
screen_y: i32 = 0,
device_scale: f32 = 1.0,

// --- graphics --------------------------------------------------------------
webgl_vendor: []const u8 = "",
webgl_renderer: []const u8 = "",

// --- noise -----------------------------------------------------------------
/// Per-profile seed; derived from --user-data-dir when not given.
seed: u64 = 0,
canvas_noise: bool = false,
audio_noise: bool = false,
fonts_noise: bool = false,
rects_noise: bool = false,

// --- network / permissions -------------------------------------------------
webrtc_mode: WebRtcMode = .default,
location_mode: LocationMode = .default,
latitude: ?f64 = null,
longitude: ?f64 = null,
media_device_count: [3]u8 = .{ 1, 1, 1 }, // audioinput, videoinput, audiooutput
/// --font-exclusion-list: families this profile does not have.
font_exclusion: ?[]const u8 = null,
/// --timezone, as given (IANA id), for Intl.
timezone: ?[]const u8 = null,
/// --speech-voices: full (OS + Chrome network voices), os, none.
speech_voices: enum { full, os, none } = .full,

/// Classic scrollbar thickness in CSS px for the persona's platform, 0
/// without a persona (Lightpanda's own behaviour) and where scrollbars
/// overlay the content (macOS, mobile). Chrome on Windows 11 draws the
/// thinner Fluent scrollbars.
pub fn scrollbarWidth() f64 {
    if (!active) return 0;
    const p = &current;
    if (p.mobile) return 0;
    return switch (p.os) {
        .windows => blk: {
            const major = std.fmt.parseInt(u32, std.mem.sliceTo(p.platform_version, '.'), 10) catch 0;
            break :blk if (major >= 13 and p.chrome_major >= 124) 15 else 17;
        },
        .linux, .chromeos => 15,
        else => 0,
    };
}

pub fn get() *const Persona {
    return &current;
}

// ===========================================================================
// argv translation
// ===========================================================================

const Kind = enum { flag, value };

const Switch = struct {
    name: []const u8,
    kind: Kind,
};

/// Every switch the launcher may pass. Anything listed here never reaches
/// Config (which would reject the Chromium `--name=value` form).
const launcher_switches = [_]Switch{
    .{ .name = "user-agent", .kind = .value },
    .{ .name = "ua-full-version", .kind = .value },
    .{ .name = "ua-platform-version", .kind = .value },
    .{ .name = "hardware-concurrency", .kind = .value },
    .{ .name = "device-memory", .kind = .value },
    .{ .name = "device-mode", .kind = .value },
    .{ .name = "device-size", .kind = .value },
    .{ .name = "window-size", .kind = .value },
    .{ .name = "screen-size", .kind = .value },
    .{ .name = "window-position", .kind = .value },
    .{ .name = "window-scale", .kind = .value },
    .{ .name = "force-device-scale-factor", .kind = .value },
    .{ .name = "max-touch-points", .kind = .value },
    .{ .name = "webgl-vendor", .kind = .value },
    .{ .name = "webgl-renderer", .kind = .value },
    .{ .name = "webgpu-vendor", .kind = .value },
    .{ .name = "webgpu-renderer", .kind = .value },
    .{ .name = "canvas-noise", .kind = .flag },
    .{ .name = "audio-noise", .kind = .flag },
    .{ .name = "fonts-noise", .kind = .flag },
    .{ .name = "rects-noise", .kind = .flag },
    .{ .name = "webgl-noise", .kind = .flag },
    .{ .name = "fp-seed", .kind = .value },
    .{ .name = "font-exclusion-list", .kind = .value },
    .{ .name = "speech-voices", .kind = .value },
    .{ .name = "media-device-count", .kind = .value },
    .{ .name = "webrtc-mode", .kind = .value },
    .{ .name = "location-mode", .kind = .value },
    .{ .name = "timezone", .kind = .value },
    .{ .name = "lang", .kind = .value },
    .{ .name = "accept-lang", .kind = .value },
    .{ .name = "proxy-server", .kind = .value },
    .{ .name = "remote-debugging-port", .kind = .value },
    .{ .name = "remote-debugging-address", .kind = .value },
    .{ .name = "user-data-dir", .kind = .value },
    .{ .name = "taskbar-title", .kind = .value },
    .{ .name = "gra-taskbar", .kind = .value },
    .{ .name = "headless", .kind = .flag },
};

/// Chromium-only switches the launcher adds that have no meaning here.
const ignored_prefixes = [_][]const u8{
    "disable-",
    "enable-",
    "no-first-run",
    "no-default-browser-check",
    "no-sandbox",
    "test-type",
    "password-store",
    "use-mock-keychain",
    "metrics-recording-only",
    "allow-pre-commit-input",
    "hide-crash-restore-bubble",
    "force-color-profile",
    "autoplay-policy",
    "remote-allow-origins",
    "lang-detect",
    "start-maximized",
};

const Parsed = struct {
    name: []const u8,
    value: ?[]const u8,
};

fn splitSwitch(arg: []const u8) ?Parsed {
    if (!std.mem.startsWith(u8, arg, "--") or arg.len < 3) return null;
    const body = arg[2..];
    if (std.mem.findScalar(u8, body, '=')) |eq| {
        return .{ .name = body[0..eq], .value = body[eq + 1 ..] };
    }
    return .{ .name = body, .value = null };
}

fn findSwitch(name: []const u8) ?Switch {
    for (launcher_switches) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

/// Lightpanda's own options that share a Chromium prefix; never swallowed.
fn isNativeOption(name: []const u8) bool {
    const native = [_][]const u8{ "disable-subframes", "disable-workers", "enable-external-stylesheets", "no-llm" };
    for (native) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

fn isIgnored(name: []const u8) bool {
    for (ignored_prefixes) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return false;
}

const commands = [_][]const u8{ "serve", "fetch", "mcp", "agent", "run", "help", "version", "completion", "skills", "docs", "snapshot" };

fn isCommand(arg: []const u8) bool {
    for (commands) |c| {
        if (std.mem.eql(u8, c, arg)) return true;
    }
    return false;
}

/// Collected launcher values, applied after all of argv was read so the order
/// of switches does not matter.
const Raw = struct {
    user_agent: ?[]const u8 = null,
    ua_full_version: ?[]const u8 = null,
    ua_platform_version: ?[]const u8 = null,
    hardware_concurrency: ?[]const u8 = null,
    device_memory: ?[]const u8 = null,
    device_mode: ?[]const u8 = null,
    device_size: ?[]const u8 = null,
    window_size: ?[]const u8 = null,
    screen_size: ?[]const u8 = null,
    window_position: ?[]const u8 = null,
    window_scale: ?[]const u8 = null,
    max_touch_points: ?[]const u8 = null,
    webgl_vendor: ?[]const u8 = null,
    webgl_renderer: ?[]const u8 = null,
    fp_seed: ?[]const u8 = null,
    media_device_count: ?[]const u8 = null,
    webrtc_mode: ?[]const u8 = null,
    location_mode: ?[]const u8 = null,
    timezone: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    font_exclusion: ?[]const u8 = null,
    speech_voices: ?[]const u8 = null,
    proxy_server: ?[]const u8 = null,
    port: ?[]const u8 = null,
    address: ?[]const u8 = null,
    user_data_dir: ?[]const u8 = null,
    canvas_noise: bool = false,
    audio_noise: bool = false,
    fonts_noise: bool = false,
    rects_noise: bool = false,
};

/// Launcher switch -> Raw field, for switches that carry a value.
const value_switches = [_]struct { []const u8, []const u8 }{
    .{ "user-agent", "user_agent" },
    .{ "ua-full-version", "ua_full_version" },
    .{ "ua-platform-version", "ua_platform_version" },
    .{ "hardware-concurrency", "hardware_concurrency" },
    .{ "device-memory", "device_memory" },
    .{ "device-mode", "device_mode" },
    .{ "device-size", "device_size" },
    .{ "window-size", "window_size" },
    .{ "screen-size", "screen_size" },
    .{ "window-position", "window_position" },
    .{ "window-scale", "window_scale" },
    .{ "force-device-scale-factor", "window_scale" },
    .{ "max-touch-points", "max_touch_points" },
    .{ "webgl-vendor", "webgl_vendor" },
    .{ "webgl-renderer", "webgl_renderer" },
    .{ "fp-seed", "fp_seed" },
    .{ "font-exclusion-list", "font_exclusion" },
    .{ "speech-voices", "speech_voices" },
    .{ "media-device-count", "media_device_count" },
    .{ "webrtc-mode", "webrtc_mode" },
    .{ "location-mode", "location_mode" },
    .{ "timezone", "timezone" },
    .{ "lang", "lang" },
    .{ "accept-lang", "lang" },
    .{ "proxy-server", "proxy_server" },
    .{ "remote-debugging-port", "port" },
    .{ "remote-debugging-address", "address" },
    .{ "user-data-dir", "user_data_dir" },
};

/// Launcher flag switch -> Raw bool field.
const flag_switches = [_]struct { []const u8, []const u8 }{
    .{ "canvas-noise", "canvas_noise" },
    .{ "audio-noise", "audio_noise" },
    .{ "fonts-noise", "fonts_noise" },
    .{ "rects-noise", "rects_noise" },
};

fn store(raw: *Raw, name: []const u8, value: ?[]const u8) void {
    inline for (value_switches) |s| {
        if (std.mem.eql(u8, name, s[0])) {
            @field(raw, s[1]) = value orelse "";
            return;
        }
    }
    inline for (flag_switches) |s| {
        if (std.mem.eql(u8, name, s[0])) {
            @field(raw, s[1]) = true;
            return;
        }
    }
}

/// Rewrites a launcher-style argv into a Lightpanda argv and fills `current`.
/// Allocations live for the process (pass main's arena).
pub fn translateArgs(allocator: Allocator, proc_args: std.process.Args) !std.process.Args {
    if (comptime builtin.os.tag == .windows) return proc_args;

    const argv = proc_args.vector;
    if (argv.len < 2) return proc_args;

    var raw: Raw = .{};
    var seen = false;
    var out: std.ArrayList([*:0]const u8) = .empty;
    try out.append(allocator, argv[0]);

    var has_command = false;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = std.mem.span(argv[i]);
        if (i == 1 and isCommand(arg)) has_command = true;

        const parsed = splitSwitch(arg) orelse {
            // Launcher mode (no subcommand): startup URLs have no meaning for
            // the CDP server; Chromium-only switches neither. Keep only what
            // was translated, so an unknown launcher arg never aborts startup.
            if (has_command) try out.append(allocator, argv[i]);
            continue;
        };

        if (findSwitch(parsed.name)) |sw| {
            // Chromium form is always `--name=value`. Lightpanda's own
            // `--timezone X` / `--user-agent X` (space form) is kept for the
            // ones Config also knows, so plain upstream usage still works.
            if (sw.kind == .value and parsed.value == null) {
                if (std.mem.eql(u8, parsed.name, "timezone") or std.mem.eql(u8, parsed.name, "user-agent")) {
                    if (i + 1 < argv.len) {
                        i += 1;
                        store(&raw, parsed.name, std.mem.span(argv[i]));
                        seen = true;
                    }
                    continue;
                }
            }
            store(&raw, parsed.name, parsed.value);
            seen = true;
            continue;
        }

        if (isIgnored(parsed.name) and !isNativeOption(parsed.name)) {
            seen = true;
            continue;
        }

        if (has_command) try out.append(allocator, argv[i]);
    }

    if (!seen) return proc_args;
    active = true;

    // A launcher spawn has no subcommand: it is always the CDP server.
    if (!has_command) {
        try out.insert(allocator, 1, "serve");
    }

    // A real browser loads every sub-resource: no iframes / workers / images
    // is a headless tell (CreepJS "Worker: blocked"), and so is a page whose
    // images and beacons never hit the network.
    if (!has_command) {
        try appendOpt(allocator, &out, "--load-resources", "image,iframe,worker,stylesheet,beacon");
    }

    // Native options Lightpanda implements itself.
    const host: []const u8 = raw.address orelse "127.0.0.1";
    if (raw.port) |port| {
        try appendOpt(allocator, &out, "--host", host);
        try appendOpt(allocator, &out, "--port", port);
    }
    if (raw.timezone) |tz| {
        if (tz.len > 0) try appendOpt(allocator, &out, "--timezone", tz);
    }
    if (raw.lang) |lang| {
        const tag = firstLanguage(lang);
        if (tag.len > 0) try appendOpt(allocator, &out, "--locale", tag);
    }
    if (raw.proxy_server) |proxy| {
        if (try normalizeProxy(allocator, proxy)) |p| {
            try appendOpt(allocator, &out, "--http-proxy", p);
        }
    }

    try apply(allocator, &raw);

    return .{ .vector = try out.toOwnedSlice(allocator) };
}

fn appendOpt(allocator: Allocator, out: *std.ArrayList([*:0]const u8), name: [:0]const u8, value: []const u8) !void {
    try out.append(allocator, name.ptr);
    const v = try allocator.dupeSentinel(u8, value, 0);
    try out.append(allocator, v.ptr);
}

/// `--lang=vi-VN,vi;q=0.9` or `--lang=vi_VN` -> `vi-VN`.
fn firstLanguage(value: []const u8) []const u8 {
    const end = std.mem.findAny(u8, value, ",;") orelse value.len;
    return std.mem.trim(u8, value[0..end], " \t");
}

/// Chromium resolves DNS through a SOCKS5 proxy; libcurl only does with
/// `socks5h://`. Without this rewrite every hostname leaks to the local DNS
/// resolver, i.e. the real ISP sees the browsing.
pub fn normalizeProxy(allocator: Allocator, proxy: []const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, proxy, " \t");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "direct://")) return null;
    // Chromium also accepts "host:port" (http) and "scheme=..." rules; only
    // a single proxy is supported here, take the first rule.
    const first = trimmed[0 .. std.mem.findScalar(u8, trimmed, ';') orelse trimmed.len];

    if (std.mem.startsWith(u8, first, "socks5://")) {
        return try std.mem.concat(allocator, u8, &.{ "socks5h://", first["socks5://".len..] });
    }
    if (std.mem.startsWith(u8, first, "socks4://")) {
        return try std.mem.concat(allocator, u8, &.{ "socks4a://", first["socks4://".len..] });
    }
    if (std.mem.startsWith(u8, first, "socks://")) {
        return try std.mem.concat(allocator, u8, &.{ "socks5h://", first["socks://".len..] });
    }
    if (std.mem.find(u8, first, "://") == null) {
        return try std.mem.concat(allocator, u8, &.{ "http://", first });
    }
    return try allocator.dupe(u8, first);
}

// ===========================================================================
// persona construction
// ===========================================================================

fn apply(allocator: Allocator, raw: *const Raw) !void {
    var p: Persona = .{};

    // --- seed: stable per profile ----------------------------------------
    if (raw.fp_seed) |s| {
        p.seed = std.fmt.parseInt(u64, s, 10) catch std.hash.Wyhash.hash(0x5347, s);
    } else if (raw.user_data_dir) |dir| {
        p.seed = std.hash.Wyhash.hash(0x5347, dir);
    } else if (raw.user_agent) |ua| {
        p.seed = std.hash.Wyhash.hash(0x5348, ua);
    }
    p.canvas_noise = raw.canvas_noise;
    p.audio_noise = raw.audio_noise;
    p.fonts_noise = raw.fonts_noise;
    p.rects_noise = raw.rects_noise;

    // --- user agent -------------------------------------------------------
    var ua_full_build: ?[]const u8 = null;
    if (raw.user_agent) |ua_in| {
        if (ua_in.len > 0) {
            // Chrome 110+ sends the reduced UA ("Chrome/143.0.0.0") and keeps
            // the build for client hints. A launcher UA carrying the full
            // build ("Chrome/143.0.7490.0") gives both.
            var ua = ua_in;
            if (chromeVersionToken(ua_in)) |tok| {
                if (!std.mem.endsWith(u8, tok, ".0.0.0") and std.mem.count(u8, tok, ".") == 3) {
                    ua_full_build = try allocator.dupe(u8, tok);
                    const major_end = std.mem.findScalar(u8, tok, '.').?;
                    const start = @intFromPtr(tok.ptr) - @intFromPtr(ua_in.ptr);
                    ua = try std.mem.concat(allocator, u8, &.{ ua_in[0..start], tok[0..major_end], ".0.0.0", ua_in[start + tok.len ..] });
                }
            }
            p.user_agent = try allocator.dupeSentinel(u8, ua, 0);
            p.os = detectOs(ua);
            p.mobile = p.os == .android or p.os == .ios or std.mem.find(u8, ua, "Mobile") != null;
            p.chrome_major = chromeMajor(ua);
            if (std.mem.startsWith(u8, ua, "Mozilla/")) {
                p.app_version = p.user_agent.?["Mozilla/".len..];
            }
            p.platform_version = defaultPlatformVersion(p.os, ua);
            // Chrome always reports three components ("14" -> "14.0.0").
            const dots = std.mem.count(u8, p.platform_version, ".");
            if (dots < 2) {
                const pad: []const u8 = if (dots == 0) ".0.0" else ".0";
                p.platform_version = try std.mem.concat(allocator, u8, &.{ p.platform_version, pad });
            }
        }
    }
    if (raw.device_mode) |m| {
        if (std.mem.eql(u8, m, "phone") or std.mem.eql(u8, m, "mobile")) p.mobile = true;
    }
    if (raw.ua_platform_version) |v| {
        if (v.len > 0) p.platform_version = try allocator.dupe(u8, v);
    }

    if (p.chrome_major > 0) {
        // Real Chrome never reports "N.0.0.0" as its full version: without
        // one from the launcher, use the release's real build number and a
        // per-profile patch level.
        p.full_version = if (raw.ua_full_version) |v|
            try allocator.dupe(u8, v)
        else if (ua_full_build) |v|
            v
        else
            try allocator.print("{d}.0.{d}.{d}", .{ p.chrome_major, chromeBuild(p.chrome_major), 40 + p.seed % 160 });
        try p.buildBrands(allocator);
    }

    // --- hardware ---------------------------------------------------------
    if (raw.hardware_concurrency) |v| {
        const n = std.fmt.parseInt(u32, v, 10) catch 0;
        if (n > 0 and n <= 256) p.hardware_concurrency = n;
    }
    if (raw.device_memory) |v| {
        p.device_memory = clampDeviceMemory(std.fmt.parseFloat(f64, v) catch 8.0);
    }
    p.max_touch_points = if (p.mobile) 5 else 0;
    if (raw.max_touch_points) |v| {
        const n = std.fmt.parseInt(u32, v, 10) catch p.max_touch_points;
        if (n <= 10) p.max_touch_points = n;
    }

    // --- screen / window --------------------------------------------------
    if (raw.window_scale) |v| {
        const s = std.fmt.parseFloat(f32, v) catch 0;
        if (s >= 0.5 and s <= 5.0) p.device_scale = s;
    } else if (p.mobile) {
        p.device_scale = 2.625;
    }

    var sw: u32 = 0;
    var sh: u32 = 0;
    const screen_src = if (p.mobile) (raw.device_size orelse raw.screen_size orelse raw.window_size) else (raw.screen_size orelse raw.window_size);
    if (screen_src) |s| _ = parsePair(s, &sw, &sh);
    if (sw > 0 and sh > 0) {
        if (p.mobile and sw > sh) std.mem.swap(u32, &sw, &sh);
        p.screen_width = sw;
        p.screen_height = sh;
        p.avail_height_reserved = switch (p.os) {
            .windows => 40, // taskbar at 100% scale
            .macos => 25, // menu bar (dock auto-hidden)
            .linux, .chromeos => 0,
            .android, .ios => 0,
        };
        if (p.mobile) {
            p.outer_width = sw;
            p.outer_height = sh;
            p.inner_width = sw;
            // status bar + collapsed address bar of Chrome for Android
            p.inner_height = sh -| 80;
        } else {
            // A maximized Chrome window: fills the available area, minus the
            // tab strip + toolbar (~87 CSS px on Windows/Linux, ~80 on macOS).
            const avail_h = sh -| p.avail_height_reserved;
            var ow = sw;
            var oh = avail_h;
            var ww: u32 = 0;
            var wh: u32 = 0;
            if (raw.screen_size != null) {
                if (raw.window_size) |w| {
                    if (parsePair(w, &ww, &wh) and ww > 0 and wh > 0) {
                        ow = @min(ww, sw);
                        oh = @min(wh, avail_h);
                    }
                }
            }
            p.outer_width = ow;
            p.outer_height = oh;
            p.inner_width = ow;
            p.inner_height = oh -| @as(u32, if (p.os == .macos) 80 else 87);
        }
    }
    if (raw.window_position) |s| {
        var x: u32 = 0;
        var y: u32 = 0;
        if (parsePair(s, &x, &y)) {
            p.screen_x = @intCast(@min(x, 100_000));
            p.screen_y = @intCast(@min(y, 100_000));
        }
    }

    // --- graphics ---------------------------------------------------------
    if (raw.font_exclusion) |v| p.font_exclusion = try allocator.dupe(u8, v);
    if (raw.speech_voices) |v| {
        if (std.mem.eql(u8, v, "os")) p.speech_voices = .os else if (std.mem.eql(u8, v, "none")) p.speech_voices = .none;
    }
    if (raw.timezone) |v| {
        if (v.len > 0) p.timezone = try allocator.dupe(u8, v);
    }
    if (raw.webgl_vendor) |v| p.webgl_vendor = try allocator.dupe(u8, v);
    if (raw.webgl_renderer) |v| p.webgl_renderer = try allocator.dupe(u8, v);
    if (p.webgl_vendor.len == 0) p.webgl_vendor = defaultWebglVendor(p.os);
    if (p.webgl_renderer.len == 0) p.webgl_renderer = defaultWebglRenderer(p.os);

    // --- permissions / devices -------------------------------------------
    if (raw.webrtc_mode) |m| {
        p.webrtc_mode = std.meta.stringToEnum(WebRtcMode, m) orelse .default;
    }
    if (raw.location_mode) |m| p.parseLocation(m);
    if (raw.media_device_count) |m| {
        var it = std.mem.splitScalar(u8, m, ',');
        var idx: usize = 0;
        while (it.next()) |part| : (idx += 1) {
            if (idx >= p.media_device_count.len) break;
            p.media_device_count[idx] = std.fmt.parseInt(u8, std.mem.trim(u8, part, " "), 10) catch p.media_device_count[idx];
        }
    }

    current = p;
}

fn parseLocation(self: *Persona, value: []const u8) void {
    var it = std.mem.splitScalar(u8, value, ',');
    const mode = it.next() orelse return;
    self.location_mode = std.meta.stringToEnum(LocationMode, mode) orelse .default;
    const lat = it.next() orelse return;
    const lng = it.next() orelse return;
    self.latitude = std.fmt.parseFloat(f64, lat) catch null;
    self.longitude = std.fmt.parseFloat(f64, lng) catch null;
}

fn parsePair(s: []const u8, a: *u32, b: *u32) bool {
    const sep = std.mem.findAny(u8, s, ",x") orelse return false;
    a.* = std.fmt.parseInt(u32, std.mem.trim(u8, s[0..sep], " "), 10) catch return false;
    b.* = std.fmt.parseInt(u32, std.mem.trim(u8, s[sep + 1 ..], " "), 10) catch return false;
    return true;
}

/// navigator.deviceMemory is bucketed by Chrome to a power of two in
/// [0.25, 8] (desktop). Anything else is a fingerprint in itself.
fn clampDeviceMemory(v: f64) f64 {
    const buckets = [_]f64{ 0.25, 0.5, 1, 2, 4, 8 };
    var best: f64 = 8;
    for (buckets) |b| {
        if (b <= v) best = b;
    }
    return if (v < 0.25) 0.25 else best;
}

fn hostOs() Os {
    return switch (builtin.target.os.tag) {
        .macos => .macos,
        .windows => .windows,
        else => .linux,
    };
}

pub fn detectOs(ua: []const u8) Os {
    // Order matters: Android UAs contain "Linux", iOS UAs "Mac OS X".
    if (std.mem.find(u8, ua, "Android") != null) return .android;
    if (std.mem.find(u8, ua, "iPhone") != null or std.mem.find(u8, ua, "iPad") != null) return .ios;
    if (std.mem.find(u8, ua, "CrOS") != null) return .chromeos;
    if (std.mem.find(u8, ua, "Windows") != null) return .windows;
    if (std.mem.find(u8, ua, "Macintosh") != null or std.mem.find(u8, ua, "Mac OS X") != null) return .macos;
    return .linux;
}

/// "Chrome/140.0.0.0" -> 140. Edge/Opera UAs still carry Chrome/<n>.
fn chromeMajor(ua: []const u8) u32 {
    const needle = "Chrome/";
    const pos = std.mem.find(u8, ua, needle) orelse
        (std.mem.find(u8, ua, "CriOS/") orelse return 0);
    const start = pos + needle.len;
    var end = start;
    while (end < ua.len and std.ascii.isDigit(ua[end])) end += 1;
    return std.fmt.parseInt(u32, ua[start..end], 10) catch 0;
}

/// "…Chrome/143.0.7490.0 Safari…" -> "143.0.7490.0".
fn chromeVersionToken(ua: []const u8) ?[]const u8 {
    const needle = "Chrome/";
    const pos = std.mem.find(u8, ua, needle) orelse return null;
    const start = pos + needle.len;
    var end = start;
    while (end < ua.len and (std.ascii.isDigit(ua[end]) or ua[end] == '.')) end += 1;
    if (end == start) return null;
    return ua[start..end];
}

/// BUILD in Chrome's MAJOR.0.BUILD.PATCH for a stable release; beyond the
/// table, Chrome's ~4-week cadence advances BUILD by ~55 per release.
fn chromeBuild(major: u32) u32 {
    const known = [_]struct { u32, u32 }{
        .{ 120, 6099 }, .{ 121, 6167 }, .{ 122, 6261 }, .{ 123, 6312 }, .{ 124, 6367 }, .{ 125, 6422 },
        .{ 126, 6478 }, .{ 127, 6533 }, .{ 128, 6613 }, .{ 129, 6668 }, .{ 130, 6723 }, .{ 131, 6778 },
        .{ 132, 6834 }, .{ 133, 6943 }, .{ 134, 6998 }, .{ 135, 7049 }, .{ 136, 7103 }, .{ 137, 7151 },
        .{ 138, 7204 }, .{ 139, 7258 }, .{ 140, 7339 }, .{ 141, 7390 }, .{ 142, 7444 }, .{ 143, 7499 },
    };
    for (known) |k| {
        if (k[0] == major) return k[1];
    }
    if (major > 143) return 7499 + (major - 143) * 55;
    if (major < 120) return 6099 -| (120 - major) * 60;
    return 6099;
}

fn defaultPlatformVersion(os: Os, ua: []const u8) []const u8 {
    return switch (os) {
        // Windows 11 reports 13.0.0+ / Windows 10 "10.0.0". The reduced UA
        // says "Windows NT 10.0" for both; Windows 11 is the common case.
        .windows => "15.0.0",
        .macos => "15.5.0",
        .linux => "6.8.0",
        .chromeos => "16093.68.0",
        .android => androidVersion(ua),
        .ios => "18.5.0",
    };
}

fn androidVersion(ua: []const u8) []const u8 {
    const pos = std.mem.find(u8, ua, "Android ") orelse return "14.0.0";
    const start = pos + "Android ".len;
    var end = start;
    while (end < ua.len and (std.ascii.isDigit(ua[end]) or ua[end] == '.')) end += 1;
    return if (end > start) ua[start..end] else "14.0.0";
}

fn defaultWebglVendor(os: Os) []const u8 {
    return switch (os) {
        .macos => "Google Inc. (Apple)",
        .android => "Qualcomm",
        else => "Google Inc. (Intel)",
    };
}

fn defaultWebglRenderer(os: Os) []const u8 {
    return switch (os) {
        .macos => "ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)",
        .android => "Adreno (TM) 740",
        .linux, .chromeos => "ANGLE (Intel, Mesa Intel(R) UHD Graphics 620 (KBL GT2), OpenGL 4.6)",
        else => "ANGLE (Intel, Intel(R) UHD Graphics 620 (0x00005917) Direct3D11 vs_5_0 ps_5_0, D3D11)",
    };
}

/// Chromium's GREASE brand (components/embedder_support/user_agent_utils.cc,
/// GetGreasedUserAgentBrandVersion + ShuffleBrandList): both the greasy
/// characters and the brand order are a function of the major version, so a
/// fixed "Not_A Brand" list next to the wrong version is a detection signal.
fn buildBrands(self: *Persona, allocator: Allocator) !void {
    const seed = self.chrome_major;
    const greasey_chars = [_][]const u8{ " ", "(", ":", "-", ".", "/", ")", ";", "=", "?", "_" };
    const greased_versions = [_][]const u8{ "8", "99", "24" };
    const orders = [6][3]usize{
        .{ 0, 1, 2 }, .{ 0, 2, 1 }, .{ 1, 0, 2 },
        .{ 1, 2, 0 }, .{ 2, 0, 1 }, .{ 2, 1, 0 },
    };

    const grease_brand = try std.mem.concat(allocator, u8, &.{
        "Not", greasey_chars[seed % 11], "A", greasey_chars[(seed + 1) % 11], "Brand",
    });
    const grease_version = greased_versions[seed % 3];
    const grease_full = try std.mem.concat(allocator, u8, &.{ grease_version, ".0.0.0" });
    const major = try allocator.print("{d}", .{seed});

    const product: []const u8 = "Google Chrome";
    // [grease, Chromium, product] placed at positions order[0..3].
    const input = [3]Brand{
        .{ .brand = grease_brand, .version = grease_version },
        .{ .brand = "Chromium", .version = major },
        .{ .brand = product, .version = major },
    };
    const input_full = [3]Brand{
        .{ .brand = grease_brand, .version = grease_full },
        .{ .brand = "Chromium", .version = self.full_version },
        .{ .brand = product, .version = self.full_version },
    };
    const order = orders[seed % 6];
    for (0..3) |k| {
        self.brands[order[k]] = input[k];
        self.brands_full[order[k]] = input_full[k];
    }
    self.brand_count = 3;

    var w: std.Io.Writer.Allocating = .init(allocator);
    for (self.brands[0..3], 0..) |b, k| {
        if (k > 0) try w.writer.writeAll(", ");
        try w.writer.print("\"{s}\";v=\"{s}\"", .{ b.brand, b.version });
    }
    self.sec_ch_ua = try allocator.dupeSentinel(u8, w.written(), 0);
    self.sec_ch_ua_platform = try allocator.printSentinel("\"{s}\"", .{self.uaPlatform()}, 0);
}

// ===========================================================================
// getters used by the web APIs
// ===========================================================================

/// navigator.platform
pub fn navigatorPlatform(self: *const Persona) []const u8 {
    return switch (self.os) {
        .windows => "Win32",
        .macos => "MacIntel",
        .linux => "Linux x86_64",
        .chromeos => "Linux x86_64",
        .android => "Linux armv81",
        .ios => "iPhone",
    };
}

/// navigator.userAgentData.platform / Sec-CH-UA-Platform
pub fn uaPlatform(self: *const Persona) []const u8 {
    return switch (self.os) {
        .windows => "Windows",
        .macos => "macOS",
        .linux => "Linux",
        .chromeos => "Chrome OS",
        .android => "Android",
        .ios => "iOS",
    };
}

pub fn uaArchitecture(self: *const Persona) []const u8 {
    return switch (self.os) {
        .android, .ios => "",
        .macos => "arm",
        else => "x86",
    };
}

pub fn uaBitness(self: *const Persona) []const u8 {
    return switch (self.os) {
        .android, .ios => "",
        else => "64",
    };
}

pub fn secChUaMobile(self: *const Persona) [:0]const u8 {
    return if (self.mobile) "?1" else "?0";
}

/// The viewport the browser starts with: the persona's inner window when
/// set, upstream's 1920x1080 otherwise. CDP Emulation still overrides it.
pub fn defaultViewport(self: *const Persona) Viewport {
    if (!active) return Viewport.default;
    return .{
        .width = self.inner_width orelse Viewport.default.width,
        .height = self.inner_height orelse Viewport.default.height,
        .scale = self.device_scale,
        .screen_width = self.screen_width,
        .screen_height = self.screen_height,
    };
}

// ===========================================================================
// deterministic noise helpers (seeded per profile)
// ===========================================================================

/// A stable pseudo-random 64-bit value for (`salt`, `key`) in this profile.
pub fn noise(self: *const Persona, salt: u64, key: []const u8) u64 {
    return std.hash.Wyhash.hash(self.seed ^ salt, key);
}

/// A tiny, stable offset in [-amplitude, amplitude] for (`salt`, `key`).
pub fn noiseOffset(self: *const Persona, salt: u64, key: []const u8, amplitude: f64) f64 {
    const n = self.noise(salt, key);
    const unit = @as(f64, @floatFromInt(n >> 11)) / @as(f64, @floatFromInt(@as(u64, 1) << 53));
    return (unit * 2.0 - 1.0) * amplitude;
}

pub const salt_canvas: u64 = 0x63616e766173;
pub const salt_audio: u64 = 0x617564696f;
pub const salt_fonts: u64 = 0x666f6e7473;
pub const salt_rects: u64 = 0x7265637473;

// ===========================================================================
// tests
// ===========================================================================

const testing = std.testing;

test "Persona: GREASE brands match real Chrome" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cases = [_]struct { major: u32, expected: []const u8 }{
        .{ .major = 120, .expected = "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"" },
        .{ .major = 131, .expected = "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"" },
        .{ .major = 138, .expected = "\"Not)A;Brand\";v=\"8\", \"Chromium\";v=\"138\", \"Google Chrome\";v=\"138\"" },
        .{ .major = 140, .expected = "\"Chromium\";v=\"140\", \"Not=A?Brand\";v=\"24\", \"Google Chrome\";v=\"140\"" },
    };
    for (cases) |c| {
        var p: Persona = .{ .chrome_major = c.major, .os = .windows };
        p.full_version = try a.print("{d}.0.0.0", .{c.major});
        try p.buildBrands(a);
        try testing.expectEqualStrings(c.expected, p.sec_ch_ua.?);
    }
}

test "Persona: proxy normalization keeps DNS on the proxy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("socks5h://u:p@1.2.3.4:1080", (try normalizeProxy(a, "socks5://u:p@1.2.3.4:1080")).?);
    try testing.expectEqualStrings("socks4a://1.2.3.4:1080", (try normalizeProxy(a, "socks4://1.2.3.4:1080")).?);
    try testing.expectEqualStrings("http://1.2.3.4:8080", (try normalizeProxy(a, "1.2.3.4:8080")).?);
    try testing.expectEqualStrings("http://u:p@h:1", (try normalizeProxy(a, "http://u:p@h:1")).?);
    try testing.expect((try normalizeProxy(a, "direct://")) == null);
}

test "Persona: OS detection and device memory buckets" {
    try testing.expectEqual(Os.android, detectOs("Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"));
    try testing.expectEqual(Os.windows, detectOs("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"));
    try testing.expectEqual(Os.macos, detectOs("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"));
    try testing.expectEqual(@as(u32, 140), chromeMajor("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"));
    try testing.expectEqual(@as(f64, 8), clampDeviceMemory(16));
    try testing.expectEqual(@as(f64, 4), clampDeviceMemory(6));
    try testing.expectEqual(@as(f64, 0.25), clampDeviceMemory(0.1));
}

test "Persona: translateArgs rewrites a launcher argv" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const saved_active = active;
    const saved = current;
    defer {
        active = saved_active;
        current = saved;
    }

    const argv = [_][*:0]const u8{
        "lightpanda",
        "--remote-debugging-port=9333",
        "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
        "--hardware-concurrency=12",
        "--device-memory=16",
        "--window-size=1536,864",
        "--timezone=Asia/Ho_Chi_Minh",
        "--lang=vi-VN",
        "--proxy-server=socks5://u:p@1.2.3.4:1080",
        "--disable-features=Translate",
        "--no-first-run",
        "--canvas-noise",
        "--user-data-dir=/tmp/profile-1",
        "--load-extension=/tmp/ext-a,/tmp/ext-b",
        "--webrtc-ip-handling-policy=disable_non_proxied_udp",
        "https://example.com/startup",
    };
    const out = try translateArgs(a, .{ .vector = &argv });
    const v = out.vector;

    try testing.expect(active);
    try testing.expectEqualStrings("serve", std.mem.span(v[1]));
    var joined: std.ArrayList(u8) = .empty;
    for (v[1..]) |arg| {
        try joined.appendSlice(a, std.mem.span(arg));
        try joined.append(a, ' ');
    }
    try testing.expectEqualStrings(
        "serve --load-resources image,iframe,worker,stylesheet,beacon --host 127.0.0.1 --port 9333 --timezone Asia/Ho_Chi_Minh --locale vi-VN --http-proxy socks5h://u:p@1.2.3.4:1080 ",
        joined.items,
    );

    const p = get();
    try testing.expectEqual(Os.windows, p.os);
    try testing.expectEqual(@as(u32, 12), p.hardware_concurrency);
    try testing.expectEqual(@as(f64, 8), p.device_memory);
    try testing.expectEqual(@as(?u32, 1536), p.screen_width);
    try testing.expectEqual(@as(?u32, 824), p.outer_height);
    try testing.expectEqual(@as(?u32, 737), p.inner_height);
    try testing.expect(p.canvas_noise);
    try testing.expectEqualStrings("Win32", p.navigatorPlatform());
}

/// Evaluated in every frame's JS context when the persona is active, before
/// page scripts: removes APIs Chrome does not have and adds `window.chrome`.
/// Functions are bound so their toString() reads "[native code]".
pub const bootstrap_js: []const u8 = @embedFile("persona_bootstrap.js");

/// Chrome prototype members Lightpanda lacks, for the bootstrap to fill in:
/// generated from a Chrome dump, Lightpanda's own surface and MDN's
/// browser-compat-data (the release that shipped each member). Format in
/// persona_bootstrap.js, parity().
pub const parity_table: []const u8 = @embedFile("persona_parity.txt");

/// https/wss, or a loopback http origin (what Chrome calls potentially
/// trustworthy for client hints).
pub fn isTrustworthyUrl(url: []const u8) bool {
    if (std.ascii.startsWithIgnoreCase(url, "https://") or std.ascii.startsWithIgnoreCase(url, "wss://")) return true;
    const loopback = [_][]const u8{ "http://localhost", "http://127.0.0.1", "http://[::1]", "ws://localhost", "ws://127.0.0.1" };
    for (loopback) |prefix| {
        if (std.ascii.startsWithIgnoreCase(url, prefix)) {
            if (url.len == prefix.len) return true;
            const next = url[prefix.len];
            if (next == '/' or next == ':') return true;
        }
    }
    return false;
}

test "Persona: client hints only on trustworthy origins" {
    try testing.expect(isTrustworthyUrl("https://example.com/"));
    try testing.expect(isTrustworthyUrl("http://localhost:8080/x"));
    try testing.expect(!isTrustworthyUrl("http://example.com/"));
    try testing.expect(!isTrustworthyUrl("http://localhost.evil.com/"));
}

/// --audio-noise: scale every non-silent sample by 1 ± ~1e-7, stable per
/// (profile, sample index). Audio fingerprints sum rendered samples, so the
/// hash changes per profile while the sound is unchanged.
pub fn audioNoise(self: *const Persona, samples: []f32) void {
    if (!active or !self.audio_noise) return;
    const base = self.seed ^ salt_audio;
    for (samples, 0..) |*s, i| {
        if (s.* == 0) continue;
        var z = (base +% i) +% 0x9E3779B97F4A7C15;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        z ^= z >> 31;
        const unit = @as(f32, @floatFromInt(z >> 40)) / @as(f32, @floatFromInt(@as(u64, 1) << 24));
        s.* *= 1.0 + (unit * 2.0 - 1.0) * 1.0e-7;
    }
}

test "Persona: full build from the UA, reduced UA, synthesized build" {
    try testing.expectEqualStrings("143.0.7490.0", chromeVersionToken("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.7490.0 Safari/537.36").?);
    try testing.expectEqual(@as(u32, 7339), chromeBuild(140));
    try testing.expectEqual(@as(u32, 7499 + 55 * 4), chromeBuild(147));
    try testing.expect(chromeVersionToken("Mozilla/5.0 (Macintosh) Firefox/140.0") == null);
}
