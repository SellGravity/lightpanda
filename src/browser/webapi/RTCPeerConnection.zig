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

//! SellGravity antidetect: RTCPeerConnection without a network stack.
//!
//! Every Chrome has WebRTC; its absence is a headless tell. This one behaves
//! like a peer connection whose ICE agent never finds a usable interface:
//! offers/answers carry Chrome-shaped SDP (data channel m-line, per-profile
//! ufrag / pwd / DTLS fingerprint), descriptions round-trip, but no ICE
//! candidate is ever produced, so no local or public IP can leak. This is
//! what `--webrtc-mode=disable` asks for, and the safe answer for the other
//! modes too since there is no transport behind it.

const std = @import("std");

const js = @import("../js/js.zig");
const EventTarget = @import("EventTarget.zig");
const Persona = @import("../../Persona.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ RTCPeerConnection, RTCDataChannel, RTCSessionDescription };
}

const RTCPeerConnection = @This();

pub const Proto = EventTarget;

_proto: *EventTarget,
_closed: bool = false,
_local: ?*RTCSessionDescription = null,
_remote: ?*RTCSessionDescription = null,
_session_id: u64 = 0,

/// Distinct SDP session ids per connection (Chrome uses a random 64-bit id).
var session_counter: u64 = 0;

pub fn init(_: ?js.Value, exec: *Execution) !*RTCPeerConnection {
    const p = Persona.get();
    session_counter +%= 1;
    return exec._factory.eventTarget(RTCPeerConnection{
        ._proto = undefined,
        ._session_id = (p.noise(0x727463, std.mem.asBytes(&session_counter)) +% session_counter) & 0x7fffffffffffffff,
    });
}

pub fn asEventTarget(self: *RTCPeerConnection) *EventTarget {
    return self._proto;
}

fn hex(out: []u8, v: u64) void {
    const digits = "0123456789abcdef";
    var x = v;
    for (out) |*c| {
        c.* = digits[@intCast(x & 0xf)];
        x >>= 4;
    }
}

/// Chrome's data-channel-only SDP. ufrag/pwd/fingerprint are stable per
/// profile so two calls agree, like one browser instance.
fn buildSdp(self: *const RTCPeerConnection, exec: *const Execution, setup: []const u8) ![]const u8 {
    const p = Persona.get();
    var ufrag: [4]u8 = undefined;
    hex(&ufrag, p.noise(0x7566, "ufrag"));
    var pwd: [24]u8 = undefined;
    hex(pwd[0..16], p.noise(0x707764, "pwd1"));
    hex(pwd[16..24], p.noise(0x707764, "pwd2"));
    var fp: [32]u8 = undefined;
    for (0..4) |i| {
        const v = p.noise(0x6670, &.{@as(u8, @intCast(i))});
        @memcpy(fp[i * 8 ..][0..8], std.mem.asBytes(&v));
    }
    var fp_txt: [32 * 3]u8 = undefined;
    const digits = "0123456789ABCDEF";
    for (fp, 0..) |b, i| {
        fp_txt[i * 3] = digits[b >> 4];
        fp_txt[i * 3 + 1] = digits[b & 0xf];
        fp_txt[i * 3 + 2] = ':';
    }
    return exec.call_arena.print(
        "v=0\r\no=- {d} 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\n" ++
            "a=extmap-allow-mixed\r\na=msid-semantic: WMS\r\n" ++
            "m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\nc=IN IP4 0.0.0.0\r\n" ++
            "a=ice-ufrag:{s}\r\na=ice-pwd:{s}\r\na=ice-options:trickle\r\n" ++
            "a=fingerprint:sha-256 {s}\r\na=setup:{s}\r\na=mid:0\r\n" ++
            "a=sctp-port:5000\r\na=max-message-size:262144\r\n",
        .{ self._session_id, ufrag, pwd, fp_txt[0 .. fp_txt.len - 1], setup },
    );
}

fn describe(self: *RTCPeerConnection, kind: []const u8, setup: []const u8, exec: *Execution) !js.Promise {
    if (self._closed) return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.InvalidStateError } });
    const sdp = try self.buildSdp(exec, setup);
    return exec.js.local.?.resolvePromise(.{ .type = kind, .sdp = sdp });
}

fn createOffer(self: *RTCPeerConnection, _: ?js.Value, exec: *Execution) !js.Promise {
    return self.describe("offer", "actpass", exec);
}

fn createAnswer(self: *RTCPeerConnection, _: ?js.Value, exec: *Execution) !js.Promise {
    if (self._remote == null) {
        return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.InvalidStateError } });
    }
    return self.describe("answer", "active", exec);
}

// Dictionary members in lexicographic order (WebIDL, enforced by the bridge).
const DescriptionInit = struct {
    sdp: ?[]const u8 = null,
    type: ?[]const u8 = null,
};

fn toDescription(init_: ?DescriptionInit, exec: *Execution) !*RTCSessionDescription {
    const d = init_ orelse DescriptionInit{};
    return exec._factory.create(RTCSessionDescription{
        ._type = try exec.page_arena.dupe(u8, d.type orelse "offer"),
        ._sdp = try exec.page_arena.dupe(u8, d.sdp orelse ""),
    });
}

fn setLocalDescription(self: *RTCPeerConnection, desc: ?DescriptionInit, exec: *Execution) !js.Promise {
    if (self._closed) return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.InvalidStateError } });
    var d = desc orelse DescriptionInit{};
    if (d.sdp == null or d.sdp.?.len == 0) d.sdp = try self.buildSdp(exec, "actpass");
    self._local = try toDescription(d, exec);
    return exec.js.local.?.resolvePromise({});
}

fn setRemoteDescription(self: *RTCPeerConnection, desc: ?DescriptionInit, exec: *Execution) !js.Promise {
    if (self._closed) return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.InvalidStateError } });
    self._remote = try toDescription(desc, exec);
    return exec.js.local.?.resolvePromise({});
}

fn addIceCandidate(self: *RTCPeerConnection, _: ?js.Value, exec: *Execution) !js.Promise {
    if (self._closed) return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.InvalidStateError } });
    return exec.js.local.?.resolvePromise({});
}

fn getStats(_: *RTCPeerConnection, _: ?js.Value, exec: *Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(.{});
}

fn createDataChannel(self: *RTCPeerConnection, label: []const u8, _: ?js.Value, exec: *Execution) !*RTCDataChannel {
    if (self._closed) return error.InvalidStateError;
    return exec._factory.create(RTCDataChannel{ ._label = try exec.page_arena.dupe(u8, label) });
}

fn close(self: *RTCPeerConnection) void {
    self._closed = true;
}

fn getLocalDescription(self: *const RTCPeerConnection) ?*RTCSessionDescription {
    return self._local;
}
fn getRemoteDescription(self: *const RTCPeerConnection) ?*RTCSessionDescription {
    return self._remote;
}
fn getSignalingState(self: *const RTCPeerConnection) []const u8 {
    if (self._closed) return "closed";
    if (self._local != null and self._remote == null) return "have-local-offer";
    if (self._remote != null and self._local == null) return "have-remote-offer";
    return "stable";
}
fn getIceGatheringState(self: *const RTCPeerConnection) []const u8 {
    // Gathering "completes" with nothing found once a description is set.
    return if (self._local != null) "complete" else "new";
}
fn getConnectionState(self: *const RTCPeerConnection) []const u8 {
    return if (self._closed) "closed" else "new";
}
fn getCanTrickle(_: *const RTCPeerConnection) ?bool {
    return null;
}

pub const RTCSessionDescription = struct {
    _type: []const u8,
    _sdp: []const u8,

    fn getType(self: *const RTCSessionDescription) []const u8 {
        return self._type;
    }
    fn getSdp(self: *const RTCSessionDescription) []const u8 {
        return self._sdp;
    }
    fn toJSON(self: *const RTCSessionDescription) struct { type: []const u8, sdp: []const u8 } {
        return .{ .type = self._type, .sdp = self._sdp };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCSessionDescription);
        pub const Meta = struct {
            pub const name = "RTCSessionDescription";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const @"type" = bridge.accessor(RTCSessionDescription.getType, null, .{});
        pub const sdp = bridge.accessor(RTCSessionDescription.getSdp, null, .{});
        pub const toJSON = bridge.function(RTCSessionDescription.toJSON, .{});
    };
};

pub const RTCDataChannel = struct {
    _label: []const u8,
    _closed: bool = false,

    fn getLabel(self: *const RTCDataChannel) []const u8 {
        return self._label;
    }
    fn getReadyState(self: *const RTCDataChannel) []const u8 {
        return if (self._closed) "closed" else "connecting";
    }
    fn closeChannel(self: *RTCDataChannel) void {
        self._closed = true;
    }
    fn send(_: *RTCDataChannel, _: ?js.Value) !void {
        return error.InvalidStateError; // never opens
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCDataChannel);
        pub const Meta = struct {
            pub const name = "RTCDataChannel";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const label = bridge.accessor(RTCDataChannel.getLabel, null, .{});
        pub const readyState = bridge.accessor(RTCDataChannel.getReadyState, null, .{});
        pub const ordered = bridge.property(true, .{ .template = false });
        pub const protocol = bridge.property("", .{ .template = false });
        pub const negotiated = bridge.property(false, .{ .template = false });
        pub const bufferedAmount = bridge.property(0, .{ .template = false });
        pub const binaryType = bridge.property("arraybuffer", .{ .template = false, .readonly = false });
        pub const close = bridge.function(RTCDataChannel.closeChannel, .{});
        pub const send = bridge.function(RTCDataChannel.send, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(RTCPeerConnection);

    pub const Meta = struct {
        pub const name = "RTCPeerConnection";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(RTCPeerConnection.init, .{});

    pub const createOffer = bridge.function(RTCPeerConnection.createOffer, .{});
    pub const createAnswer = bridge.function(RTCPeerConnection.createAnswer, .{});
    pub const setLocalDescription = bridge.function(RTCPeerConnection.setLocalDescription, .{});
    pub const setRemoteDescription = bridge.function(RTCPeerConnection.setRemoteDescription, .{});
    pub const addIceCandidate = bridge.function(RTCPeerConnection.addIceCandidate, .{});
    pub const getStats = bridge.function(RTCPeerConnection.getStats, .{});
    pub const createDataChannel = bridge.function(RTCPeerConnection.createDataChannel, .{});
    pub const close = bridge.function(RTCPeerConnection.close, .{});
    pub const localDescription = bridge.accessor(RTCPeerConnection.getLocalDescription, null, .{});
    pub const remoteDescription = bridge.accessor(RTCPeerConnection.getRemoteDescription, null, .{});
    pub const currentLocalDescription = bridge.accessor(RTCPeerConnection.getLocalDescription, null, .{});
    pub const currentRemoteDescription = bridge.accessor(RTCPeerConnection.getRemoteDescription, null, .{});
    pub const signalingState = bridge.accessor(RTCPeerConnection.getSignalingState, null, .{});
    pub const iceGatheringState = bridge.accessor(RTCPeerConnection.getIceGatheringState, null, .{});
    pub const iceConnectionState = bridge.accessor(RTCPeerConnection.getConnectionState, null, .{});
    pub const connectionState = bridge.accessor(RTCPeerConnection.getConnectionState, null, .{});
    pub const canTrickleIceCandidates = bridge.accessor(RTCPeerConnection.getCanTrickle, null, .{});
    pub const onicecandidate = EventTarget.handlerAccessor(RTCPeerConnection, "icecandidate");
    pub const onicegatheringstatechange = EventTarget.handlerAccessor(RTCPeerConnection, "icegatheringstatechange");
    pub const oniceconnectionstatechange = EventTarget.handlerAccessor(RTCPeerConnection, "iceconnectionstatechange");
    pub const onconnectionstatechange = EventTarget.handlerAccessor(RTCPeerConnection, "connectionstatechange");
    pub const onsignalingstatechange = EventTarget.handlerAccessor(RTCPeerConnection, "signalingstatechange");
    pub const onnegotiationneeded = EventTarget.handlerAccessor(RTCPeerConnection, "negotiationneeded");
    pub const ondatachannel = EventTarget.handlerAccessor(RTCPeerConnection, "datachannel");
    pub const ontrack = EventTarget.handlerAccessor(RTCPeerConnection, "track");
};
