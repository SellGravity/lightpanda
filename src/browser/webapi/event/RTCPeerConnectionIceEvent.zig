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

//! SellGravity antidetect: the event RTCPeerConnection fires for each ICE
//! candidate it gathers (and once with a null candidate when done).

const lp = @import("lightpanda");

const Page = @import("../../Page.zig");
const Event = @import("../Event.zig");
const RTCPeerConnection = @import("../RTCPeerConnection.zig");

const String = lp.String;
const RTCIceCandidate = RTCPeerConnection.RTCIceCandidate;

const RTCPeerConnectionIceEvent = @This();

pub const Proto = Event;
_proto: *Event,
_candidate: ?*RTCIceCandidate = null,

const IceEventOptions = struct {
    candidate: ?*RTCIceCandidate = null,
};

const Options = Event.inheritOptions(RTCPeerConnectionIceEvent, IceEventOptions);

pub fn init(typ: []const u8, _opts: ?Options, page: *Page) !*RTCPeerConnectionIceEvent {
    const arena = try page.getArena(.tiny, "RTCPeerConnectionIceEvent");
    errdefer arena.release();
    const type_string = try String.init(arena.allocator(), typ, .{});
    return initWithTrusted(arena, type_string, _opts, false, page);
}

pub fn initTrusted(typ: String, _opts: ?Options, page: *Page) !*RTCPeerConnectionIceEvent {
    const arena = try page.getArena(.tiny, "RTCPeerConnectionIceEvent.trusted");
    errdefer arena.release();
    return initWithTrusted(arena, typ, _opts, true, page);
}

fn initWithTrusted(arena: *lp.Arena, typ: String, _opts: ?Options, trusted: bool, page: *Page) !*RTCPeerConnectionIceEvent {
    const opts = _opts orelse Options{};
    const event = try page.factory.event(arena, typ, RTCPeerConnectionIceEvent{
        ._proto = undefined,
        ._candidate = opts.candidate,
    });
    Event.populatePrototypes(event, opts, trusted);
    return event;
}

pub fn asEvent(self: *RTCPeerConnectionIceEvent) *Event {
    return self._proto;
}

fn getCandidate(self: *const RTCPeerConnectionIceEvent) ?*RTCIceCandidate {
    return self._candidate;
}

pub const JsApi = struct {
    const js = @import("../../js/js.zig");
    pub const bridge = js.Bridge(RTCPeerConnectionIceEvent);

    pub const Meta = struct {
        pub const name = "RTCPeerConnectionIceEvent";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(RTCPeerConnectionIceEvent.init, .{});
    pub const candidate = bridge.accessor(RTCPeerConnectionIceEvent.getCandidate, null, .{});
};
