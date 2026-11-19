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
//! like a peer connection on a network where STUN is unreachable: offers /
//! answers carry Chrome-shaped SDP (data channel m-line, per-profile ufrag /
//! pwd / DTLS fingerprint), descriptions round-trip, and ICE gathering runs
//! the way Chrome's does (gathering -> mDNS host candidate -> complete ->
//! null candidate) but only ever yields Chrome's random `<uuid>.local` host
//! names, so no local or public IP can leak. Bot checks (Cloudflare
//! Turnstile) wait for these events.

const std = @import("std");
const lp = @import("lightpanda");

const js = @import("../js/js.zig");
const EventTarget = @import("EventTarget.zig");
const Persona = @import("../../Persona.zig");
const Event = @import("Event.zig");
const RTCPeerConnectionIceEvent = @import("event/RTCPeerConnectionIceEvent.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ RTCPeerConnection, RTCDataChannel, RTCSessionDescription, RTCIceCandidate };
}

const RTCPeerConnection = @This();

pub const Proto = EventTarget;

_proto: *EventTarget,
_closed: bool = false,
_local: ?*RTCSessionDescription = null,
_remote: ?*RTCSessionDescription = null,
_session_id: u64 = 0,
_exec: *Execution,
_gathering: enum { new, gathering, complete } = .new,
// STUN/TURN servers configured: gathering then waits for them (and gets
// nothing back) before completing.
_has_ice_servers: bool = false,

/// Distinct SDP session ids per connection (Chrome uses a random 64-bit id).
var session_counter: u64 = 0;

pub fn init(config: ?js.Value, exec: *Execution) !*RTCPeerConnection {
    const p = Persona.get();
    session_counter +%= 1;
    var has_servers = false;
    if (config) |c| {
        if (c.isObject()) {
            if (c.toObject().get("iceServers")) |v| {
                if (v.isArray()) has_servers = v.toArray().len() > 0;
            } else |_| {}
        }
    }
    return exec._factory.eventTarget(RTCPeerConnection{
        ._proto = undefined,
        ._exec = exec,
        ._has_ice_servers = has_servers,
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
    if (self._gathering == .new) try self.startGathering(exec);
    return exec.js.local.?.resolvePromise({});
}

// ICE gathering, on later tasks like Chrome's: state "gathering", a host
// candidate under a fresh mDNS name, then (after the unanswered STUN checks
// when servers are configured) "complete" and the end-of-candidates event.
fn startGathering(self: *RTCPeerConnection, exec: *Execution) !void {
    const task = try exec._factory.create(GatherTask{ .pc = self });
    errdefer exec._factory.destroy(task);
    try exec._scheduler.add(task, GatherTask.run, 1, .{
        .name = "RTCPeerConnection.gather",
        .finalizer = GatherTask.cancelled,
    });
}

const GatherTask = struct {
    pc: *RTCPeerConnection,
    step: enum { gathering, host, complete } = .gathering,

    fn cancelled(ctx: *anyopaque) void {
        const self: *GatherTask = @ptrCast(@alignCast(ctx));
        self.pc._exec._factory.destroy(self);
    }

    fn run(ctx: *anyopaque) !?u32 {
        const self: *GatherTask = @ptrCast(@alignCast(ctx));
        const pc = self.pc;
        const exec = pc._exec;
        if (pc._closed) {
            exec._factory.destroy(self);
            return null;
        }
        switch (self.step) {
            .gathering => {
                pc._gathering = .gathering;
                self.step = .host;
                try pc.dispatchSimple("icegatheringstatechange");
                return 2;
            },
            .host => {
                self.step = .complete;
                const candidate = try RTCIceCandidate.host(exec);
                try pc.dispatchCandidate(candidate);
                return if (pc._has_ice_servers) 240 else 3;
            },
            .complete => {
                pc._gathering = .complete;
                exec._factory.destroy(self);
                try pc.dispatchSimple("icegatheringstatechange");
                try pc.dispatchCandidate(null);
                return null;
            },
        }
    }
};

fn dispatchSimple(self: *RTCPeerConnection, comptime typ: []const u8) !void {
    const exec = self._exec;
    // longer than a comptime-wrappable string: build it, then mark it trusted
    const event = try Event.init(typ, null, exec.page);
    event._is_trusted = true;
    try exec.dispatch(self.asEventTarget(), event, .{ .context = "RTC gathering state" });
}

fn dispatchCandidate(self: *RTCPeerConnection, candidate: ?*RTCIceCandidate) !void {
    const exec = self._exec;
    const event = (try RTCPeerConnectionIceEvent.initTrusted(comptime .wrap("icecandidate"), .{ .candidate = candidate }, exec.page)).asEvent();
    try exec.dispatch(self.asEventTarget(), event, .{ .context = "RTC icecandidate" });
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
    return @tagName(self._gathering);
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

pub const RTCIceCandidate = struct {
    _candidate: []const u8 = "",
    _sdp_mid: ?[]const u8 = null,
    _sdp_mline_index: ?u16 = null,
    _ufrag: ?[]const u8 = null,
    // parsed from the candidate line
    _foundation: ?[]const u8 = null,
    _component: ?[]const u8 = null,
    _priority: ?u32 = null,
    _address: ?[]const u8 = null,
    _protocol: ?[]const u8 = null,
    _port: ?u16 = null,
    _type: ?[]const u8 = null,
    _tcp_type: ?[]const u8 = null,
    _related_address: ?[]const u8 = null,
    _related_port: ?u16 = null,

    // Dictionary members in lexicographic order (WebIDL, enforced by the bridge).
    const Init = struct {
        candidate: []const u8 = "",
        sdpMLineIndex: ?u16 = null,
        sdpMid: ?[]const u8 = null,
        usernameFragment: ?[]const u8 = null,
    };

    fn constructor(init_: ?Init, exec: *Execution) !*RTCIceCandidate {
        const d = init_ orelse Init{};
        if (d.sdpMid == null and d.sdpMLineIndex == null) return error.TypeError;
        return create(exec, d.candidate, d.sdpMid, d.sdpMLineIndex, d.usernameFragment);
    }

    fn create(exec: *Execution, line: []const u8, mid: ?[]const u8, index: ?u16, ufrag: ?[]const u8) !*RTCIceCandidate {
        const arena = exec.page_arena;
        var self = RTCIceCandidate{
            ._candidate = try arena.dupe(u8, line),
            ._sdp_mid = if (mid) |m| try arena.dupe(u8, m) else null,
            ._sdp_mline_index = index,
            ._ufrag = if (ufrag) |u| try arena.dupe(u8, u) else null,
        };
        self.parse();
        return exec._factory.create(self);
    }

    // "candidate:F C P PRIO ADDR PORT typ T [raddr A rport P] [tcptype T] ... ufrag U"
    fn parse(self: *RTCIceCandidate) void {
        if (!std.mem.startsWith(u8, self._candidate, "candidate:")) return;
        var it = std.mem.tokenizeScalar(u8, self._candidate["candidate:".len..], ' ');
        self._foundation = it.next() orelse return;
        const component = it.next() orelse return;
        self._component = if (std.mem.eql(u8, component, "2")) "rtcp" else "rtp";
        const protocol = it.next() orelse return;
        self._protocol = if (std.ascii.eqlIgnoreCase(protocol, "tcp")) "tcp" else "udp";
        self._priority = std.fmt.parseInt(u32, it.next() orelse return, 10) catch null;
        self._address = it.next() orelse return;
        self._port = std.fmt.parseInt(u16, it.next() orelse return, 10) catch null;
        while (it.next()) |key| {
            const value = it.next() orelse break;
            if (std.mem.eql(u8, key, "typ")) {
                self._type = value;
            } else if (std.mem.eql(u8, key, "raddr")) {
                self._related_address = value;
            } else if (std.mem.eql(u8, key, "rport")) {
                self._related_port = std.fmt.parseInt(u16, value, 10) catch null;
            } else if (std.mem.eql(u8, key, "tcptype")) {
                self._tcp_type = value;
            } else if (std.mem.eql(u8, key, "ufrag") and self._ufrag == null) {
                self._ufrag = value;
            }
        }
    }

    /// A host candidate behind a fresh mDNS name, as Chrome hands out.
    fn host(exec: *Execution) !*RTCIceCandidate {
        var raw: [16]u8 = undefined;
        lp.io.random(&raw);
        raw[6] = (raw[6] & 0x0f) | 0x40;
        raw[8] = (raw[8] & 0x3f) | 0x80;
        const digits = "0123456789abcdef";
        var uuid: [36]u8 = undefined;
        var o: usize = 0;
        for (raw, 0..) |b, i| {
            if (i == 4 or i == 6 or i == 8 or i == 10) {
                uuid[o] = '-';
                o += 1;
            }
            uuid[o] = digits[b >> 4];
            uuid[o + 1] = digits[b & 0xf];
            o += 2;
        }
        var extra: [8]u8 = undefined;
        lp.io.random(&extra);
        const port: u32 = 49152 + std.mem.readInt(u32, extra[0..4], .little) % 16000;
        const foundation: u32 = std.mem.readInt(u32, extra[4..8], .little) | 0x10000000;
        var ufrag: [4]u8 = undefined;
        hex(&ufrag, Persona.get().noise(0x7566, "ufrag"));
        const line = try exec.call_arena.print("candidate:{d} 1 udp 2113937151 {s}.local {d} typ host generation 0 ufrag {s} network-cost 999", .{ foundation, uuid, port, ufrag });
        return create(exec, line, "0", 0, &ufrag);
    }

    fn getCandidate(self: *const RTCIceCandidate) []const u8 {
        return self._candidate;
    }
    fn getSdpMid(self: *const RTCIceCandidate) ?[]const u8 {
        return self._sdp_mid;
    }
    fn getSdpMLineIndex(self: *const RTCIceCandidate) ?u16 {
        return self._sdp_mline_index;
    }
    fn getFoundation(self: *const RTCIceCandidate) ?[]const u8 {
        return self._foundation;
    }
    fn getComponent(self: *const RTCIceCandidate) ?[]const u8 {
        return self._component;
    }
    fn getPriority(self: *const RTCIceCandidate) ?u32 {
        return self._priority;
    }
    fn getAddress(self: *const RTCIceCandidate) ?[]const u8 {
        return self._address;
    }
    fn getProtocol(self: *const RTCIceCandidate) ?[]const u8 {
        return self._protocol;
    }
    fn getPort(self: *const RTCIceCandidate) ?u16 {
        return self._port;
    }
    fn getType(self: *const RTCIceCandidate) ?[]const u8 {
        return self._type;
    }
    fn getTcpType(self: *const RTCIceCandidate) ?[]const u8 {
        return self._tcp_type;
    }
    fn getRelatedAddress(self: *const RTCIceCandidate) ?[]const u8 {
        return self._related_address;
    }
    fn getRelatedPort(self: *const RTCIceCandidate) ?u16 {
        return self._related_port;
    }
    fn getUsernameFragment(self: *const RTCIceCandidate) ?[]const u8 {
        return self._ufrag;
    }
    fn getNull(_: *const RTCIceCandidate) ?[]const u8 {
        return null;
    }
    fn toJSON(self: *const RTCIceCandidate) struct { candidate: []const u8, sdpMLineIndex: ?u16, sdpMid: ?[]const u8, usernameFragment: ?[]const u8 } {
        return .{ .candidate = self._candidate, .sdpMid = self._sdp_mid, .sdpMLineIndex = self._sdp_mline_index, .usernameFragment = self._ufrag };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCIceCandidate);
        pub const Meta = struct {
            pub const name = "RTCIceCandidate";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const constructor = bridge.constructor(RTCIceCandidate.constructor, .{});
        pub const candidate = bridge.accessor(RTCIceCandidate.getCandidate, null, .{});
        pub const sdpMid = bridge.accessor(RTCIceCandidate.getSdpMid, null, .{});
        pub const sdpMLineIndex = bridge.accessor(RTCIceCandidate.getSdpMLineIndex, null, .{});
        pub const foundation = bridge.accessor(RTCIceCandidate.getFoundation, null, .{});
        pub const component = bridge.accessor(RTCIceCandidate.getComponent, null, .{});
        pub const priority = bridge.accessor(RTCIceCandidate.getPriority, null, .{});
        pub const address = bridge.accessor(RTCIceCandidate.getAddress, null, .{});
        pub const protocol = bridge.accessor(RTCIceCandidate.getProtocol, null, .{});
        pub const port = bridge.accessor(RTCIceCandidate.getPort, null, .{});
        pub const @"type" = bridge.accessor(RTCIceCandidate.getType, null, .{});
        pub const tcpType = bridge.accessor(RTCIceCandidate.getTcpType, null, .{});
        pub const relatedAddress = bridge.accessor(RTCIceCandidate.getRelatedAddress, null, .{});
        pub const relatedPort = bridge.accessor(RTCIceCandidate.getRelatedPort, null, .{});
        pub const usernameFragment = bridge.accessor(RTCIceCandidate.getUsernameFragment, null, .{});
        pub const relayProtocol = bridge.accessor(RTCIceCandidate.getNull, null, .{});
        pub const url = bridge.accessor(RTCIceCandidate.getNull, null, .{});
        pub const toJSON = bridge.function(RTCIceCandidate.toJSON, .{});
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
