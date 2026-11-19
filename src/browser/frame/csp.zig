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

//! SellGravity antidetect: Content-Security-Policy for inline scripts.
//!
//! Chrome refuses an inline <script> its document's policy doesn't allow (no
//! matching nonce or hash, or no 'unsafe-inline'). An engine that runs it
//! anyway is easy to tell apart: inject a script without the nonce, see if
//! it ran. Only inline scripts are checked (script-src-elem, else
//! script-src, else default-src, per CSP3); every policy, from the response
//! header and from <meta http-equiv>, has to allow the script.

const std = @import("std");

const Frame = @import("../Frame.zig");
const Element = @import("../webapi/Element.zig");

/// Whether `script` (inline, with `text`) may run in `frame`.
pub fn allowsInlineScript(frame: *Frame, script: *Element, text: []const u8) bool {
    const nonce = script.getAttributeSafe(comptime .wrap("nonce"));
    if (frame._csp_header) |header| {
        // several policies arrive comma-joined
        var policies = std.mem.splitScalar(u8, header, ',');
        while (policies.next()) |policy| {
            if (!policyAllows(policy, nonce, text)) return false;
        }
    }
    const head = frame.document.getHead() orelse return true;
    var child = head.firstElementChild();
    while (child) |el| : (child = el.nextElementSibling()) {
        if (el.getTag() != .meta) continue;
        const equiv = el.getAttributeSafe(comptime .wrap("http-equiv")) orelse continue;
        if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, equiv, &std.ascii.whitespace), "content-security-policy")) continue;
        const content = el.getAttributeSafe(comptime .wrap("content")) orelse continue;
        if (!policyAllows(content, nonce, text)) return false;
    }
    return true;
}

fn policyAllows(policy: []const u8, nonce: ?[]const u8, text: []const u8) bool {
    const sources = directive(policy, "script-src-elem") orelse
        directive(policy, "script-src") orelse
        directive(policy, "default-src") orelse return true;

    var has_nonce_or_hash = false;
    var unsafe_inline = false;
    var it = std.mem.tokenizeAny(u8, sources, &std.ascii.whitespace);
    while (it.next()) |token| {
        if (std.ascii.eqlIgnoreCase(token, "'unsafe-inline'")) {
            unsafe_inline = true;
            continue;
        }
        if (token.len > 2 and token[0] == '\'' and token[token.len - 1] == '\'') {
            const inner = token[1 .. token.len - 1];
            if (std.ascii.startsWithIgnoreCase(inner, "nonce-")) {
                has_nonce_or_hash = true;
                if (nonce) |n| {
                    if (n.len > 0 and std.mem.eql(u8, inner["nonce-".len..], n)) return true;
                }
            } else if (hashAlgorithm(inner)) |alg| {
                has_nonce_or_hash = true;
                if (hashMatches(alg, inner[alg.prefix.len..], text)) return true;
            }
        }
    }
    // A nonce or hash source turns 'unsafe-inline' off.
    return unsafe_inline and !has_nonce_or_hash;
}

/// The value of directive `name` in `policy`, null when it's absent.
fn directive(policy: []const u8, name: []const u8) ?[]const u8 {
    var directives = std.mem.splitScalar(u8, policy, ';');
    while (directives.next()) |raw| {
        const d = std.mem.trim(u8, raw, &std.ascii.whitespace);
        const end = std.mem.indexOfAny(u8, d, &std.ascii.whitespace) orelse d.len;
        if (std.ascii.eqlIgnoreCase(d[0..end], name)) return d[end..];
    }
    return null;
}

const Algorithm = struct { prefix: []const u8, kind: enum { sha256, sha384, sha512 } };

fn hashAlgorithm(source: []const u8) ?Algorithm {
    const all = [_]Algorithm{
        .{ .prefix = "sha256-", .kind = .sha256 },
        .{ .prefix = "sha384-", .kind = .sha384 },
        .{ .prefix = "sha512-", .kind = .sha512 },
    };
    for (all) |a| {
        if (std.ascii.startsWithIgnoreCase(source, a.prefix)) return a;
    }
    return null;
}

fn hashMatches(alg: Algorithm, expected: []const u8, text: []const u8) bool {
    var digest_buf: [64]u8 = undefined;
    const digest: []const u8 = switch (alg.kind) {
        .sha256 => blk: {
            std.crypto.hash.sha2.Sha256.hash(text, digest_buf[0..32], .{});
            break :blk digest_buf[0..32];
        },
        .sha384 => blk: {
            std.crypto.hash.sha2.Sha384.hash(text, digest_buf[0..48], .{});
            break :blk digest_buf[0..48];
        },
        .sha512 => blk: {
            std.crypto.hash.sha2.Sha512.hash(text, digest_buf[0..64], .{});
            break :blk digest_buf[0..64];
        },
    };
    var enc_buf: [88]u8 = undefined;
    const std_b64 = std.base64.standard.Encoder.encode(&enc_buf, digest);
    if (std.mem.eql(u8, std_b64, expected)) return true;
    // CSP also accepts base64url
    var url_buf: [88]u8 = undefined;
    const url_b64 = std.base64.url_safe.Encoder.encode(&url_buf, digest);
    return std.mem.eql(u8, url_b64, expected);
}

const testing = std.testing;

test "csp: inline script policy" {
    try testing.expect(policyAllows("default-src 'none'", null, "x") == false);
    try testing.expect(policyAllows("img-src *", null, "x"));
    try testing.expect(policyAllows("script-src 'unsafe-inline'", null, "x"));
    try testing.expect(policyAllows("script-src 'unsafe-inline' 'nonce-abc'", null, "x") == false);
    try testing.expect(policyAllows("script-src 'nonce-abc' 'unsafe-eval'", "abc", "x"));
    try testing.expect(policyAllows("script-src 'nonce-abc'", "abd", "x") == false);
    try testing.expect(policyAllows("default-src 'self'; script-src-elem 'unsafe-inline'; script-src 'none'", null, "x"));
    // sha256 of "alert(1)"
    try testing.expect(policyAllows("script-src 'sha256-bhHHL3z2vDgxUt0W3dWQOrprscmda2Y5pLsLg4GF+pI='", null, "alert(1)"));
    try testing.expect(policyAllows("script-src 'sha256-bhHHL3z2vDgxUt0W3dWQOrprscmda2Y5pLsLg4GF+pI='", null, "alert(2)") == false);
}
