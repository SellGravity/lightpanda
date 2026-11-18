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

//! SellGravity antidetect: navigator APIs every Chrome exposes and whose
//! absence is a headless tell: navigator.connection (NetworkInformation),
//! navigator.mediaDevices (MediaDevices / MediaDeviceInfo) and
//! navigator.getBattery() (BatteryManager).

const std = @import("std");

const js = @import("../js/js.zig");
const EventTarget = @import("EventTarget.zig");
const Persona = @import("../../Persona.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    const own = [_]type{ NetworkInformation, MediaDevices, MediaDeviceInfo, BatteryManager, MemoryInfo };
    return comptime &(own ++ stub_types);
}

// ---------------------------------------------------------------------------
// NetworkInformation
// ---------------------------------------------------------------------------

pub const NetworkInformation = struct {
    pub const Proto = EventTarget;
    _proto: *EventTarget,

    pub fn init(exec: *const Execution) !*NetworkInformation {
        return exec._factory.eventTarget(NetworkInformation{ ._proto = undefined });
    }

    pub fn asEventTarget(self: *NetworkInformation) *EventTarget {
        return self._proto;
    }

    fn getEffectiveType(_: *const NetworkInformation) []const u8 {
        return "4g";
    }
    // Chrome rounds rtt to 25 ms and downlink to 25 kbps steps and adds
    // noise; keep a stable per-profile value in the usual broadband range.
    fn getRtt(_: *const NetworkInformation) u32 {
        const p = Persona.get();
        const steps: u32 = @intCast(p.noise(0x727474, "rtt") % 5);
        return 50 + steps * 25;
    }
    fn getDownlink(_: *const NetworkInformation) f64 {
        const p = Persona.get();
        const steps: f64 = @floatFromInt(p.noise(0x646c, "downlink") % 40);
        return 1.5 + steps * 0.25;
    }
    fn getSaveData(_: *const NetworkInformation) bool {
        return false;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(NetworkInformation);
        pub const Meta = struct {
            pub const name = "NetworkInformation";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const effectiveType = bridge.accessor(NetworkInformation.getEffectiveType, null, .{});
        pub const rtt = bridge.accessor(NetworkInformation.getRtt, null, .{});
        pub const downlink = bridge.accessor(NetworkInformation.getDownlink, null, .{});
        pub const saveData = bridge.accessor(NetworkInformation.getSaveData, null, .{});
        pub const onchange = EventTarget.handlerAccessor(NetworkInformation, "change");
    };
};

// ---------------------------------------------------------------------------
// MediaDevices
// ---------------------------------------------------------------------------

pub const MediaDeviceInfo = struct {
    _kind: []const u8,

    fn getKind(self: *const MediaDeviceInfo) []const u8 {
        return self._kind;
    }
    // Before a getUserMedia grant Chrome blanks ids and labels.
    fn getEmpty(_: *const MediaDeviceInfo) []const u8 {
        return "";
    }
    fn toJSON(self: *const MediaDeviceInfo) struct {
        deviceId: []const u8,
        kind: []const u8,
        label: []const u8,
        groupId: []const u8,
    } {
        return .{ .deviceId = "", .kind = self._kind, .label = "", .groupId = "" };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MediaDeviceInfo);
        pub const Meta = struct {
            pub const name = "MediaDeviceInfo";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const kind = bridge.accessor(MediaDeviceInfo.getKind, null, .{});
        pub const deviceId = bridge.accessor(MediaDeviceInfo.getEmpty, null, .{});
        pub const label = bridge.accessor(MediaDeviceInfo.getEmpty, null, .{});
        pub const groupId = bridge.accessor(MediaDeviceInfo.getEmpty, null, .{});
        pub const toJSON = bridge.function(MediaDeviceInfo.toJSON, .{});
    };
};

pub const MediaDevices = struct {
    pub const Proto = EventTarget;
    _proto: *EventTarget,

    pub fn init(exec: *const Execution) !*MediaDevices {
        return exec._factory.eventTarget(MediaDevices{ ._proto = undefined });
    }

    pub fn asEventTarget(self: *MediaDevices) *EventTarget {
        return self._proto;
    }

    /// One entry per device of each kind, from --media-device-count
    /// (audioinput, videoinput, audiooutput). Chrome lists them in that order.
    fn enumerateDevices(_: *const MediaDevices, exec: *Execution) !js.Promise {
        const counts = Persona.get().media_device_count;
        const kinds = [_][]const u8{ "audioinput", "videoinput", "audiooutput" };
        var list: std.ArrayList(*MediaDeviceInfo) = .empty;
        const allocator = exec.call_arena;
        for (kinds, 0..) |k, i| {
            // Without a grant Chrome collapses each kind to a single entry.
            if (counts[i] > 0) {
                try list.append(allocator, try exec._factory.create(MediaDeviceInfo{ ._kind = k }));
            }
        }
        return exec.js.local.?.resolvePromise(list.items);
    }

    fn getSupportedConstraints(_: *const MediaDevices) struct {
        aspectRatio: bool = true,
        autoGainControl: bool = true,
        brightness: bool = true,
        channelCount: bool = true,
        colorTemperature: bool = true,
        contrast: bool = true,
        deviceId: bool = true,
        displaySurface: bool = true,
        echoCancellation: bool = true,
        exposureCompensation: bool = true,
        exposureMode: bool = true,
        exposureTime: bool = true,
        facingMode: bool = true,
        focusDistance: bool = true,
        focusMode: bool = true,
        frameRate: bool = true,
        groupId: bool = true,
        height: bool = true,
        iso: bool = true,
        latency: bool = true,
        noiseSuppression: bool = true,
        pan: bool = true,
        pointsOfInterest: bool = true,
        resizeMode: bool = true,
        sampleRate: bool = true,
        sampleSize: bool = true,
        saturation: bool = true,
        sharpness: bool = true,
        suppressLocalAudioPlayback: bool = true,
        tilt: bool = true,
        torch: bool = true,
        whiteBalanceMode: bool = true,
        width: bool = true,
        zoom: bool = true,
    } {
        return .{};
    }

    /// No camera or microphone can be opened: reject like a denied prompt.
    fn getUserMedia(_: *const MediaDevices, _: ?js.Value, exec: *Execution) !js.Promise {
        return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.NotAllowedError } });
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MediaDevices);
        pub const Meta = struct {
            pub const name = "MediaDevices";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const enumerateDevices = bridge.function(MediaDevices.enumerateDevices, .{});
        pub const getSupportedConstraints = bridge.function(MediaDevices.getSupportedConstraints, .{});
        pub const getUserMedia = bridge.function(MediaDevices.getUserMedia, .{});
        pub const getDisplayMedia = bridge.function(MediaDevices.getUserMedia, .{});
        pub const ondevicechange = EventTarget.handlerAccessor(MediaDevices, "devicechange");
    };
};

// ---------------------------------------------------------------------------
// BatteryManager
// ---------------------------------------------------------------------------

pub const BatteryManager = struct {
    pub const Proto = EventTarget;
    _proto: *EventTarget,

    pub fn init(exec: *const Execution) !*BatteryManager {
        return exec._factory.eventTarget(BatteryManager{ ._proto = undefined });
    }

    pub fn asEventTarget(self: *BatteryManager) *EventTarget {
        return self._proto;
    }

    // Desktops report a plugged-in full battery; phones a partly charged one.
    fn getCharging(_: *const BatteryManager) bool {
        return !Persona.get().mobile;
    }
    fn getChargingTime(_: *const BatteryManager) f64 {
        return if (Persona.get().mobile) std.math.inf(f64) else 0;
    }
    fn getDischargingTime(_: *const BatteryManager) f64 {
        return std.math.inf(f64);
    }
    fn getLevel(_: *const BatteryManager) f64 {
        const p = Persona.get();
        if (!p.mobile) return 1;
        const pct: f64 = @floatFromInt(35 + p.noise(0x626174, "level") % 60);
        return pct / 100.0;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(BatteryManager);
        pub const Meta = struct {
            pub const name = "BatteryManager";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const charging = bridge.accessor(BatteryManager.getCharging, null, .{});
        pub const chargingTime = bridge.accessor(BatteryManager.getChargingTime, null, .{});
        pub const dischargingTime = bridge.accessor(BatteryManager.getDischargingTime, null, .{});
        pub const level = bridge.accessor(BatteryManager.getLevel, null, .{});
        pub const onchargingchange = EventTarget.handlerAccessor(BatteryManager, "chargingchange");
        pub const onchargingtimechange = EventTarget.handlerAccessor(BatteryManager, "chargingtimechange");
        pub const ondischargingtimechange = EventTarget.handlerAccessor(BatteryManager, "dischargingtimechange");
        pub const onlevelchange = EventTarget.handlerAccessor(BatteryManager, "levelchange");
    };
};

// ---------------------------------------------------------------------------
// Presence-only navigator members
//
// Chrome exposes ~80 members on Navigator.prototype; fingerprinting scripts
// count them and check `typeof navigator.usb` etc. These are real platform
// classes with Chrome's names but no behaviour (nothing here can reach a
// clipboard, a USB bus or a GPU). The persona bootstrap removes the ones
// Chrome for Android does not have.
// ---------------------------------------------------------------------------

pub const stub_classes = [_][]const u8{
    "Clipboard",         "CredentialsContainer", "Keyboard",              "MediaSession",
    "WakeLock",          "USB",                  "HID",                   "Serial",
    "Bluetooth",         "GPU",                  "Scheduling",            "Ink",
    "Presentation",      "UserActivation",       "WindowControlsOverlay", "XRSystem",
    "MediaCapabilities", "VirtualKeyboard",      "StorageBucketManager",  "DevicePosture",
    "NavigatorLogin",    "NavigatorManagedData", "ProtectedAudience",     "LaunchQueue",
};

pub fn Stub(comptime idx: usize) type {
    return struct {
        _: u8 = 0,
        const Self = @This();
        pub const JsApi = struct {
            pub const bridge = js.Bridge(Self);
            pub const Meta = struct {
                pub const name = stub_classes[idx];
                pub var class_id: bridge.ClassId = undefined;
            };
        };
    };
}

pub const stub_types = blk: {
    var types: [stub_classes.len]type = undefined;
    for (0..stub_classes.len) |i| types[i] = Stub(i);
    break :blk types;
};

/// Cached per Navigator so navigator.clipboard === navigator.clipboard.
pub const StubCache = [stub_classes.len]?*anyopaque;

pub fn stubGetter(comptime Nav: type, comptime idx: usize) fn (*Nav, *Execution) anyerror!*Stub(idx) {
    return struct {
        fn get(nav: *Nav, exec: *Execution) anyerror!*Stub(idx) {
            if (nav._stubs[idx]) |p| return @ptrCast(@alignCast(p));
            const s = try exec._factory.create(Stub(idx){});
            nav._stubs[idx] = s;
            return s;
        }
    }.get;
}

// ---------------------------------------------------------------------------
// performance.memory (Chrome-only, new MemoryInfo object on every access)
// ---------------------------------------------------------------------------

pub const MemoryInfo = struct {
    _used: f64,
    _total: f64,

    fn getLimit(_: *const MemoryInfo) f64 {
        // 64-bit desktop Chrome's V8 heap limit; Android devices get less.
        return if (Persona.get().mobile) 1130364928 else 4294705152;
    }
    fn getTotal(self: *const MemoryInfo) f64 {
        return self._total;
    }
    fn getUsed(self: *const MemoryInfo) f64 {
        return self._used;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MemoryInfo);
        pub const Meta = struct {
            pub const name = "MemoryInfo";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const jsHeapSizeLimit = bridge.accessor(MemoryInfo.getLimit, null, .{});
        pub const totalJSHeapSize = bridge.accessor(MemoryInfo.getTotal, null, .{});
        pub const usedJSHeapSize = bridge.accessor(MemoryInfo.getUsed, null, .{});
    };
};

/// Chrome reports heap sizes quantized (unless --enable-precise-memory-info);
/// stable per profile, in the range of a freshly loaded page.
pub fn memoryInfo(exec: *const Execution) !*MemoryInfo {
    const p = Persona.get();
    const bucket: f64 = 100_000;
    const total = (90 + @as(f64, @floatFromInt(p.noise(0x6d656d, "total") % 250))) * bucket;
    const used = total * 0.72;
    return exec._factory.create(MemoryInfo{ ._used = @floor(used / bucket) * bucket, ._total = total });
}
