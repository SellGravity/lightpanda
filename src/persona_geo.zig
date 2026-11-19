// Copyright (C) 2023-2026 Lightpanda (Selecy SAS)
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

//! SellGravity antidetect: `--location-mode=<perm>,ip`. Like the Chromium
//! fork, the position comes from the profile's exit IP: looked up once at
//! startup, through the profile's proxy, off the main thread. Until it
//! answers (or if it fails) there is no position, as with a slow network
//! location provider.

const std = @import("std");
const lp = @import("lightpanda");

const App = @import("App.zig");
const http = @import("network/http.zig");
const libcurl = @import("sys/libcurl.zig");

const log = lp.log;

var ready: std.atomic.Value(bool) = .init(false);
var lat_bits: std.atomic.Value(u64) = .init(0);
var lng_bits: std.atomic.Value(u64) = .init(0);
var started: std.atomic.Value(bool) = .init(false);

pub const Coordinates = struct { latitude: f64, longitude: f64 };

/// The exit IP's position, once known.
pub fn coordinates() ?Coordinates {
    if (!ready.load(.acquire)) return null;
    return .{
        .latitude = @bitCast(lat_bits.load(.monotonic)),
        .longitude = @bitCast(lng_bits.load(.monotonic)),
    };
}

/// Starts the lookup when the persona asks for an IP-based position.
pub fn start(app: *App) void {
    if (!lp.Persona.active) return;
    const persona = lp.Persona.get();
    if (!persona.location_ip or persona.location_mode == .block) return;
    if (started.swap(true, .monotonic)) return;
    const thread = std.Thread.spawn(.{}, run, .{app}) catch |err| {
        log.warn(.app, "ip geo thread", .{ .err = err });
        return;
    };
    thread.detach();
}

// Free services the launcher's proxy checker uses too; the first answer wins.
const services = [_]struct { url: [:0]const u8, lat: []const u8, lng: []const u8 }{
    .{ .url = "http://ip-api.com/json/?fields=status,lat,lon", .lat = "lat", .lng = "lon" },
    .{ .url = "https://ipwho.is/?fields=success,latitude,longitude", .lat = "latitude", .lng = "longitude" },
    .{ .url = "https://ipinfo.io/json", .lat = "loc", .lng = "" },
};

fn run(app: *App) void {
    for (services) |service| {
        var attempt: u8 = 0;
        while (attempt < 2) : (attempt += 1) {
            if (lookup(app, service.url, service.lat, service.lng)) |c| {
                lat_bits.store(@bitCast(c.latitude), .monotonic);
                lng_bits.store(@bitCast(c.longitude), .monotonic);
                ready.store(true, .release);
                log.info(.app, "ip geo", .{});
                return;
            } else |err| {
                log.debug(.app, "ip geo lookup", .{ .err = err, .url = service.url });
            }
        }
    }
    log.warn(.app, "ip geo unavailable", .{});
}

fn lookup(app: *App, url: [:0]const u8, lat_key: []const u8, lng_key: []const u8) !Coordinates {
    var conn = try http.Connection.init(app.network.certificates, app.config, null);
    defer conn.deinit();
    try conn.setURL(url);
    try conn.setGetMode();
    try conn.setFollowLocation(true);
    try conn.setTimeout(8000);

    var body: std.Io.Writer.Allocating = .init(app.allocator);
    defer body.deinit();
    var ctx: Receiver = .{ .writer = &body.writer };
    try libcurl.curl_easy_setopt(conn._easy, .write_data, &ctx);
    try libcurl.curl_easy_setopt(conn._easy, .write_function, Receiver.drain);

    const status = try conn.perform();
    if (status != 200) return error.BadStatus;
    return parse(app.allocator, body.written(), lat_key, lng_key);
}

fn parse(allocator: std.mem.Allocator, json: []const u8, lat_key: []const u8, lng_key: []const u8) !Coordinates {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.BadBody,
    };
    // ipinfo: "loc": "21.0245,105.8412"
    if (lng_key.len == 0) {
        const loc = switch (obj.get(lat_key) orelse return error.BadBody) {
            .string => |s| s,
            else => return error.BadBody,
        };
        const comma = std.mem.indexOfScalar(u8, loc, ',') orelse return error.BadBody;
        return checked(try std.fmt.parseFloat(f64, loc[0..comma]), try std.fmt.parseFloat(f64, loc[comma + 1 ..]));
    }
    return checked(try number(obj.get(lat_key)), try number(obj.get(lng_key)));
}

fn number(v: ?std.json.Value) !f64 {
    return switch (v orelse return error.BadBody) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        .number_string => |s| std.fmt.parseFloat(f64, s),
        else => error.BadBody,
    };
}

fn checked(lat: f64, lng: f64) !Coordinates {
    if (!(lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180)) return error.BadBody;
    if (lat == 0 and lng == 0) return error.BadBody;
    return .{ .latitude = lat, .longitude = lng };
}

const Receiver = struct {
    writer: *std.Io.Writer,

    fn drain(buffer: [*]const u8, buf_count: usize, buf_len: usize, ctx: *anyopaque) callconv(.c) usize {
        _ = buf_count;
        const self: *Receiver = @ptrCast(@alignCast(ctx));
        if (self.writer.end + buf_len > 64 * 1024) return 0;
        self.writer.writeAll(buffer[0..buf_len]) catch return 0;
        return buf_len;
    }
};

const testing = std.testing;
test "persona_geo: parses the lookup services" {
    const a = testing.allocator;
    const c1 = try parse(a, "{\"status\":\"success\",\"lat\":21.0245,\"lon\":105.8412}", "lat", "lon");
    try testing.expectEqual(@as(f64, 21.0245), c1.latitude);
    try testing.expectEqual(@as(f64, 105.8412), c1.longitude);
    const c2 = try parse(a, "{\"success\":true,\"latitude\":10.8231,\"longitude\":106}", "latitude", "longitude");
    try testing.expectEqual(@as(f64, 106), c2.longitude);
    const c3 = try parse(a, "{\"ip\":\"1.2.3.4\",\"loc\":\"48.8534,2.3488\"}", "loc", "");
    try testing.expectEqual(@as(f64, 48.8534), c3.latitude);
    try testing.expectError(error.BadBody, parse(a, "{\"status\":\"fail\"}", "lat", "lon"));
    try testing.expectError(error.BadBody, parse(a, "{\"lat\":0,\"lon\":0}", "lat", "lon"));
}
