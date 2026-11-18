// Copyright (C) 2023-2026 Lightpanda (Selecy SAS)
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

const js = @import("../js/js.zig");
const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ StorageManager, StorageEstimate };
}

const StorageManager = @This();

_pad: bool = false,

/// SellGravity antidetect: a normal Chrome profile gets ~60% of the disk as
/// quota; a small quota (Lightpanda used 1 GiB) is how incognito mode is
/// detected (quota < 2 x jsHeapSizeLimit). Stable per profile.
pub fn quota() u64 {
    const Persona = @import("../../Persona.zig");
    if (!Persona.active) return 1024 * 1024 * 1024;
    const gib: u64 = 1024 * 1024 * 1024;
    const disk_gib: u64 = 238 + Persona.get().noise(0x71756f7461, "disk") % 700;
    return disk_gib * gib / 10 * 6;
}

fn estimate(_: *const StorageManager, exec: *const Execution) !js.Promise {
    const est = try exec._factory.create(StorageEstimate{
        ._usage = 0,
        ._quota = quota(),
    });
    return exec.js.local.?.resolvePromise(est);
}

const StorageEstimate = struct {
    _quota: u64,
    _usage: u64,

    fn getUsage(self: *const StorageEstimate) u64 {
        return self._usage;
    }

    fn getQuota(self: *const StorageEstimate) u64 {
        return self._quota;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(StorageEstimate);
        pub const Meta = struct {
            pub const name = "StorageEstimate";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const quota = bridge.accessor(getQuota, null, .{});
        pub const usage = bridge.accessor(getUsage, null, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(StorageManager);
    pub const Meta = struct {
        pub const name = "StorageManager";
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };
    pub const estimate = bridge.function(StorageManager.estimate, .{});
};
