// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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

// https://webaudio.github.io/web-audio-api/#AnalyserNode
//
// A pass-through node that keeps the most recent input (down-mixed to mono)
// and analyses it on demand like Chrome's RealtimeAnalyser: Blackman window,
// FFT scaled by 1/fftSize, the Nyquist bin dropped, exponential smoothing
// over successive analyses and dB conversion. Audio fingerprinting scripts
// read getFloatFrequencyData / getFloatTimeDomainData after a render.

const std = @import("std");

const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const Factory = @import("../../Factory.zig");

const EventTarget = @import("../EventTarget.zig");

const Bus = @import("dsp/Bus.zig");
const render = @import("render.zig");
const AudioNode = @import("AudioNode.zig");
const BaseAudioContext = @import("BaseAudioContext.zig");

const AnalyserNode = @This();

pub const Proto = AudioNode;

const input_size = 32768;
const max_fft = 32768;

_proto: *AudioNode,
_fft_size: u32 = 2048,
_min_db: f64 = -100,
_max_db: f64 = -30,
_smoothing: f64 = 0.8,
// ring buffer of the latest mono input
_input: []f32,
_write: usize = 0,
// smoothed magnitudes, fft_size / 2 of them
_magnitudes: []f32,
// context frame of the last analysis; one analysis per render step
_analysed_at: ?f64 = null,

const Options = struct {
    channelCount: ?u32 = null,
    channelCountMode: ?AudioNode.ChannelCountMode = null,
    channelInterpretation: ?AudioNode.ChannelInterpretation = null,
    fftSize: u32 = 2048,
    maxDecibels: f64 = -30,
    minDecibels: f64 = -100,
    smoothingTimeConstant: f64 = 0.8,
};

fn constructor(context: *BaseAudioContext, options_: ?Options) !*AnalyserNode {
    return create(context, options_ orelse .{});
}

pub fn create(context: *BaseAudioContext, options: Options) !*AnalyserNode {
    const allocator = context._arena.allocator();
    const input = try allocator.alloc(f32, input_size);
    @memset(input, 0);
    const magnitudes = try allocator.alloc(f32, max_fft / 2);
    @memset(magnitudes, 0);
    const self = try Factory.chainedWithAllocator(allocator, .{
        EventTarget{ ._type = .audio_node },
        AudioNode.init(context, .{ .type = .analyser, .inputs = 1, .outputs = 1 }),
        AnalyserNode{ ._proto = undefined, ._input = input, ._magnitudes = magnitudes },
    });
    try self.setFftSize(options.fftSize);
    if (options.minDecibels >= options.maxDecibels) return error.IndexSizeError;
    self._min_db = options.minDecibels;
    self._max_db = options.maxDecibels;
    try self.setSmoothing(options.smoothingTimeConstant);
    try self._proto.setup(.{
        .channelCount = options.channelCount,
        .channelCountMode = options.channelCountMode,
        .channelInterpretation = options.channelInterpretation,
    });
    return self;
}

pub fn process(self: *AnalyserNode, r: *render.Quantum, input: *const Bus, output: *Bus) !void {
    try output.setChannels(r.allocator, input.channels);
    for (0..input.channels) |c| {
        @memcpy(output.channel(c), input.constChannel(c));
    }
    // Down-mix to mono: the average of the channels.
    const scale: f32 = if (input.channels > 0) 1.0 / @as(f32, @floatFromInt(input.channels)) else 0;
    for (0..Bus.quantum) |i| {
        var sum: f32 = 0;
        for (0..input.channels) |c| sum += input.constChannel(c)[i];
        self._input[self._write] = sum * scale;
        self._write = (self._write + 1) % input_size;
    }
}

fn getFftSize(self: *const AnalyserNode) u32 {
    return self._fft_size;
}

fn setFftSize(self: *AnalyserNode, size: u32) !void {
    if (size < 32 or size > max_fft or !std.math.isPowerOfTwo(size)) {
        return error.IndexSizeError;
    }
    if (size != self._fft_size) {
        @memset(self._magnitudes, 0);
    }
    self._fft_size = size;
}

fn getFrequencyBinCount(self: *const AnalyserNode) u32 {
    return self._fft_size / 2;
}

fn getMinDecibels(self: *const AnalyserNode) f64 {
    return self._min_db;
}

fn setMinDecibels(self: *AnalyserNode, value: f64) !void {
    if (value >= self._max_db) return error.IndexSizeError;
    self._min_db = value;
}

fn getMaxDecibels(self: *const AnalyserNode) f64 {
    return self._max_db;
}

fn setMaxDecibels(self: *AnalyserNode, value: f64) !void {
    if (value <= self._min_db) return error.IndexSizeError;
    self._max_db = value;
}

fn getSmoothing(self: *const AnalyserNode) f64 {
    return self._smoothing;
}

fn setSmoothing(self: *AnalyserNode, value: f64) !void {
    if (!(value >= 0 and value <= 1)) return error.IndexSizeError;
    self._smoothing = value;
}

// The last `n` input samples, oldest first.
fn recent(self: *const AnalyserNode, out: []f32) void {
    const n = out.len;
    var start = (self._write + input_size - n) % input_size;
    for (out) |*o| {
        o.* = self._input[start];
        start = (start + 1) % input_size;
    }
}

fn analyse(self: *AnalyserNode) void {
    const now = self._proto._context.currentTime();
    if (self._analysed_at) |at| {
        if (at == now) return;
    }
    self._analysed_at = now;

    const n = self._fft_size;
    var re_buf: [max_fft]f32 = undefined;
    var im_buf: [max_fft]f32 = undefined;
    const re = re_buf[0..n];
    const im = im_buf[0..n];
    self.recent(re);
    @memset(im, 0);

    // Blackman window, alpha = 0.16
    const nf: f64 = @floatFromInt(n);
    for (re, 0..) |*s, i| {
        const x = @as(f64, @floatFromInt(i)) / nf;
        const w = 0.42 - 0.5 * @cos(2 * std.math.pi * x) + 0.08 * @cos(4 * std.math.pi * x);
        s.* = @floatCast(@as(f64, s.*) * w);
    }

    fft(re, im);

    const scale: f64 = 1.0 / nf;
    const k = self._smoothing;
    for (0..n / 2) |i| {
        // Chrome zeroes the Nyquist component packed into bin 0's imaginary part
        const r: f64 = re[i];
        const m: f64 = if (i == 0) @abs(r) else @sqrt(r * r + @as(f64, im[i]) * @as(f64, im[i]));
        const mag = m * scale;
        const prev: f64 = self._magnitudes[i];
        var smoothed = k * prev + (1 - k) * mag;
        if (!std.math.isFinite(smoothed)) smoothed = 0;
        self._magnitudes[i] = @floatCast(smoothed);
    }
}

// In-place iterative radix-2 complex FFT.
fn fft(re: []f32, im: []f32) void {
    const n = re.len;
    var j: usize = 0;
    for (1..n) |i| {
        var bit = n >> 1;
        while (j & bit != 0) : (bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            std.mem.swap(f32, &re[i], &re[j]);
            std.mem.swap(f32, &im[i], &im[j]);
        }
    }
    var len: usize = 2;
    while (len <= n) : (len <<= 1) {
        const angle = -2.0 * std.math.pi / @as(f64, @floatFromInt(len));
        const half = len / 2;
        var start: usize = 0;
        while (start < n) : (start += len) {
            for (0..half) |m| {
                const a = angle * @as(f64, @floatFromInt(m));
                const wr = @cos(a);
                const wi = @sin(a);
                const ur: f64 = re[start + m];
                const ui: f64 = im[start + m];
                const xr: f64 = re[start + m + half];
                const xi: f64 = im[start + m + half];
                const vr = xr * wr - xi * wi;
                const vi = xr * wi + xi * wr;
                re[start + m] = @floatCast(ur + vr);
                im[start + m] = @floatCast(ui + vi);
                re[start + m + half] = @floatCast(ur - vr);
                im[start + m + half] = @floatCast(ui - vi);
            }
        }
    }
}

fn toDecibels(linear: f32) f32 {
    return @floatCast(20.0 * std.math.log10(@as(f64, linear)));
}

fn getFloatFrequencyData(self: *AnalyserNode, array: js.Value, frame: *Frame) !void {
    if (!array.isFloat32Array()) return error.TypeError;
    const out = (js.ArrayBufferRef(.float32){ .local = frame.js.local.?, .handle = array.handle }).slice();
    self.analyse();
    const n = @min(out.len, self._fft_size / 2);
    for (out[0..n], self._magnitudes[0..n]) |*o, m| o.* = toDecibels(m);
}

fn getByteFrequencyData(self: *AnalyserNode, array: js.Value, frame: *Frame) !void {
    if (!array.isUint8Array()) return error.TypeError;
    const out = (js.ArrayBufferRef(.uint8){ .local = frame.js.local.?, .handle = array.handle }).slice();
    self.analyse();
    const n = @min(out.len, self._fft_size / 2);
    const range = self._max_db - self._min_db;
    for (out[0..n], self._magnitudes[0..n]) |*o, m| {
        const db: f64 = toDecibels(m);
        var scaled = 255.0 * (db - self._min_db) / range;
        if (!(scaled > 0)) scaled = 0;
        if (scaled > 255) scaled = 255;
        o.* = @intFromFloat(scaled);
    }
}

fn getFloatTimeDomainData(self: *AnalyserNode, array: js.Value, frame: *Frame) !void {
    if (!array.isFloat32Array()) return error.TypeError;
    const out = (js.ArrayBufferRef(.float32){ .local = frame.js.local.?, .handle = array.handle }).slice();
    const n = @min(out.len, self._fft_size);
    var buf: [max_fft]f32 = undefined;
    self.recent(buf[0..self._fft_size]);
    @memcpy(out[0..n], buf[0..n]);
}

fn getByteTimeDomainData(self: *AnalyserNode, array: js.Value, frame: *Frame) !void {
    if (!array.isUint8Array()) return error.TypeError;
    const out = (js.ArrayBufferRef(.uint8){ .local = frame.js.local.?, .handle = array.handle }).slice();
    const n = @min(out.len, self._fft_size);
    var buf: [max_fft]f32 = undefined;
    self.recent(buf[0..self._fft_size]);
    for (out[0..n], buf[0..n]) |*o, s| {
        var scaled = 128.0 * (@as(f64, s) + 1.0);
        if (!(scaled > 0)) scaled = 0;
        if (scaled > 255) scaled = 255;
        o.* = @intFromFloat(scaled);
    }
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(AnalyserNode);

    pub const Meta = struct {
        pub const name = "AnalyserNode";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(AnalyserNode.constructor, .{});
    pub const fftSize = bridge.accessor(AnalyserNode.getFftSize, AnalyserNode.setFftSize, .{});
    pub const frequencyBinCount = bridge.accessor(AnalyserNode.getFrequencyBinCount, null, .{});
    pub const minDecibels = bridge.accessor(AnalyserNode.getMinDecibels, AnalyserNode.setMinDecibels, .{});
    pub const maxDecibels = bridge.accessor(AnalyserNode.getMaxDecibels, AnalyserNode.setMaxDecibels, .{});
    pub const smoothingTimeConstant = bridge.accessor(AnalyserNode.getSmoothing, AnalyserNode.setSmoothing, .{});
    pub const getFloatFrequencyData = bridge.function(AnalyserNode.getFloatFrequencyData, .{});
    pub const getByteFrequencyData = bridge.function(AnalyserNode.getByteFrequencyData, .{});
    pub const getFloatTimeDomainData = bridge.function(AnalyserNode.getFloatTimeDomainData, .{});
    pub const getByteTimeDomainData = bridge.function(AnalyserNode.getByteTimeDomainData, .{});
};
