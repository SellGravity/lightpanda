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

//! SellGravity antidetect: make the TLS ClientHello look like Chrome's.
//!
//! Lightpanda already speaks TLS through BoringSSL, the same library Chrome
//! uses, so the ClientHello can be shaped with BoringSSL's own knobs from
//! libcurl's CURLOPT_SSL_CTX_FUNCTION: GREASE, extension permutation,
//! Chrome's cipher / group / signature-algorithm lists, OCSP + SCT requests,
//! brotli certificate compression, and (per connection, from the info
//! callback that runs right before the ClientHello is built) ALPS for h2 on
//! the new codepoint and ECH GREASE. That covers what JA3/JA4 hash.

const std = @import("std");

const crypto = @import("../sys/libcrypto.zig");
const libcurl = @import("../sys/libcurl.zig");

const SSL = opaque {};
const CRYPTO_BUFFER = opaque {};

extern fn SSL_CTX_clear_options(ctx: *crypto.SSL_CTX, options: u32) u32;
extern fn SSL_CTX_set_grease_enabled(ctx: *crypto.SSL_CTX, enabled: c_int) void;
extern fn SSL_CTX_set_permute_extensions(ctx: *crypto.SSL_CTX, enabled: c_int) void;
extern fn SSL_CTX_set_strict_cipher_list(ctx: *crypto.SSL_CTX, str: [*:0]const u8) c_int;
extern fn SSL_CTX_set_verify_algorithm_prefs(ctx: *crypto.SSL_CTX, prefs: [*]const u16, num_prefs: usize) c_int;
extern fn SSL_CTX_enable_ocsp_stapling(ctx: *crypto.SSL_CTX) void;
extern fn SSL_CTX_enable_signed_cert_timestamps(ctx: *crypto.SSL_CTX) void;
extern fn SSL_CTX_set_info_callback(ctx: *crypto.SSL_CTX, cb: ?*const fn (ssl: *const SSL, kind: c_int, value: c_int) callconv(.c) void) void;
extern fn SSL_CTX_add_cert_compression_alg(
    ctx: *crypto.SSL_CTX,
    alg_id: u16,
    compress: ?*const anyopaque,
    decompress: ?*const fn (ssl: *SSL, out: *?*CRYPTO_BUFFER, uncompressed_len: usize, in: [*]const u8, in_len: usize) callconv(.c) c_int,
) c_int;
extern fn SSL_add_application_settings(ssl: *SSL, proto: [*]const u8, proto_len: usize, settings: ?[*]const u8, settings_len: usize) c_int;
extern fn SSL_set_alps_use_new_codepoint(ssl: *SSL, use_new: c_int) void;
extern fn SSL_set_enable_ech_grease(ssl: *SSL, enable: c_int) void;
extern fn CRYPTO_BUFFER_alloc(out_data: *[*]u8, len: usize) ?*CRYPTO_BUFFER;
extern fn CRYPTO_BUFFER_free(buf: *CRYPTO_BUFFER) void;
extern fn BrotliDecoderDecompress(encoded_size: usize, encoded: [*]const u8, decoded_size: *usize, decoded: [*]u8) c_int;

const SSL_CB_HANDSHAKE_START: c_int = 0x10;
const SSL_OP_NO_TICKET: u32 = 0x00004000;
const TLSEXT_cert_compression_brotli: u16 = 2;

/// Chrome's TLS 1.2 cipher suites, in order (TLS 1.3 suites are fixed by
/// BoringSSL and already in Chrome's order).
const chrome_ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:" ++
    "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:" ++
    "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:" ++
    "ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:" ++
    "AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA";

/// Chrome 131+ key shares / supported groups.
pub const chrome_groups = "X25519MLKEM768:X25519:P-256:P-384";

/// Chrome's signature_algorithms extension.
const chrome_sigalgs = [_]u16{
    0x0403, // ecdsa_secp256r1_sha256
    0x0804, // rsa_pss_rsae_sha256
    0x0401, // rsa_pkcs1_sha256
    0x0503, // ecdsa_secp384r1_sha384
    0x0805, // rsa_pss_rsae_sha384
    0x0501, // rsa_pkcs1_sha384
    0x0806, // rsa_pss_rsae_sha512
    0x0601, // rsa_pkcs1_sha512
};

fn decompressBrotli(_: *SSL, out: *?*CRYPTO_BUFFER, uncompressed_len: usize, in: [*]const u8, in_len: usize) callconv(.c) c_int {
    // Certificates over 16 MiB are refused, like BoringSSL's own limit.
    if (uncompressed_len == 0 or uncompressed_len > 16 * 1024 * 1024) return 0;
    var data: [*]u8 = undefined;
    const buf = CRYPTO_BUFFER_alloc(&data, uncompressed_len) orelse return 0;
    var decoded: usize = uncompressed_len;
    if (BrotliDecoderDecompress(in_len, in, &decoded, data) != 1 or decoded != uncompressed_len) {
        CRYPTO_BUFFER_free(buf);
        return 0;
    }
    out.* = buf;
    return 1;
}

fn infoCallback(ssl: *const SSL, kind: c_int, _: c_int) callconv(.c) void {
    if (kind & SSL_CB_HANDSHAKE_START == 0) return;
    // Runs in do_start_connect, before the ClientHello is serialized.
    const s: *SSL = @constCast(ssl);
    _ = SSL_add_application_settings(s, "h2", 2, null, 0);
    SSL_set_alps_use_new_codepoint(s, 1);
    SSL_set_enable_ech_grease(s, 1);
}

/// Shapes `ctx` like Chrome. Returns false if BoringSSL refused a setting.
pub fn configure(ctx: *crypto.SSL_CTX) bool {
    SSL_CTX_set_grease_enabled(ctx, 1);
    // curl sets SSL_OP_NO_TICKET; Chrome offers session_ticket (35).
    _ = SSL_CTX_clear_options(ctx, SSL_OP_NO_TICKET);
    SSL_CTX_set_permute_extensions(ctx, 1);
    if (SSL_CTX_set_strict_cipher_list(ctx, chrome_ciphers) != 1) return false;
    if (crypto.SSL_CTX_set1_curves_list(ctx, chrome_groups) != 1) return false;
    if (SSL_CTX_set_verify_algorithm_prefs(ctx, &chrome_sigalgs, chrome_sigalgs.len) != 1) return false;
    SSL_CTX_enable_ocsp_stapling(ctx);
    SSL_CTX_enable_signed_cert_timestamps(ctx);
    _ = SSL_CTX_add_cert_compression_alg(ctx, TLSEXT_cert_compression_brotli, null, decompressBrotli);
    SSL_CTX_set_info_callback(ctx, infoCallback);
    return true;
}

/// ctx_data when no certificate store is installed (TLS verification off).
pub var no_store: u8 = 0;

/// CURLOPT_SSL_CTX_FUNCTION for launcher profiles: installs the certificate
/// store (when verification is on) and the Chrome ClientHello shape.
pub fn sslCtxFunction(_: *libcurl.Curl, raw_ssl_ctx: *anyopaque, data: *anyopaque) callconv(.c) libcurl.CurlCode {
    const ssl_ctx: *crypto.SSL_CTX = @ptrCast(raw_ssl_ctx);
    if (data != @as(*anyopaque, @ptrCast(&no_store))) {
        const store: *crypto.X509_STORE = @ptrCast(data);
        if (crypto.SSL_CTX_set1_verify_cert_store(ssl_ctx, store) != 1) {
            return libcurl.CURLE.ABORTED_BY_CALLBACK;
        }
    }
    if (!configure(ssl_ctx)) {
        return libcurl.CURLE.ABORTED_BY_CALLBACK;
    }
    return libcurl.CURLE.OK;
}
