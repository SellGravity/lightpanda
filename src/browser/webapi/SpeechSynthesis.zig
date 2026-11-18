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

//! SellGravity antidetect: window.speechSynthesis with the voice list the
//! persona's Chrome would report (OS voices + Chrome's Google network voices
//! on desktop). Scanners feed getVoices() into browser/OS consistency checks;
//! a missing speechSynthesis reads as "not Chrome". Nothing is ever spoken.

const std = @import("std");

const js = @import("../js/js.zig");
const EventTarget = @import("EventTarget.zig");
const Persona = @import("../../Persona.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ SpeechSynthesis, SpeechSynthesisVoice, SpeechSynthesisUtterance };
}

const SpeechSynthesis = @This();

pub const Proto = EventTarget;

_proto: *EventTarget,

pub fn init(exec: *const Execution) !*SpeechSynthesis {
    return exec._factory.eventTarget(SpeechSynthesis{ ._proto = undefined });
}

pub fn asEventTarget(self: *SpeechSynthesis) *EventTarget {
    return self._proto;
}

const Voice = struct { name: []const u8, lang: []const u8, local: bool };

const google_voices = [_]Voice{
    .{ .name = "Google Deutsch", .lang = "de-DE", .local = false },
    .{ .name = "Google US English", .lang = "en-US", .local = false },
    .{ .name = "Google UK English Female", .lang = "en-GB", .local = false },
    .{ .name = "Google UK English Male", .lang = "en-GB", .local = false },
    .{ .name = "Google español", .lang = "es-ES", .local = false },
    .{ .name = "Google español de Estados Unidos", .lang = "es-US", .local = false },
    .{ .name = "Google français", .lang = "fr-FR", .local = false },
    .{ .name = "Google हिन्दी", .lang = "hi-IN", .local = false },
    .{ .name = "Google Bahasa Indonesia", .lang = "id-ID", .local = false },
    .{ .name = "Google italiano", .lang = "it-IT", .local = false },
    .{ .name = "Google 日本語", .lang = "ja-JP", .local = false },
    .{ .name = "Google 한국의", .lang = "ko-KR", .local = false },
    .{ .name = "Google Nederlands", .lang = "nl-NL", .local = false },
    .{ .name = "Google polski", .lang = "pl-PL", .local = false },
    .{ .name = "Google português do Brasil", .lang = "pt-BR", .local = false },
    .{ .name = "Google русский", .lang = "ru-RU", .local = false },
    .{ .name = "Google 普通话（中国大陆）", .lang = "zh-CN", .local = false },
    .{ .name = "Google 粤語（香港）", .lang = "zh-HK", .local = false },
    .{ .name = "Google 國語（臺灣）", .lang = "zh-TW", .local = false },
};

const windows_voices = [_]Voice{
    .{ .name = "Microsoft David - English (United States)", .lang = "en-US", .local = true },
    .{ .name = "Microsoft Mark - English (United States)", .lang = "en-US", .local = true },
    .{ .name = "Microsoft Zira - English (United States)", .lang = "en-US", .local = true },
};

const mac_voices = [_]Voice{
    .{ .name = "Samantha", .lang = "en-US", .local = true },
    .{ .name = "Alex", .lang = "en-US", .local = true },
    .{ .name = "Daniel", .lang = "en-GB", .local = true },
    .{ .name = "Karen", .lang = "en-AU", .local = true },
    .{ .name = "Moira", .lang = "en-IE", .local = true },
    .{ .name = "Rishi", .lang = "en-IN", .local = true },
    .{ .name = "Tessa", .lang = "en-ZA", .local = true },
    .{ .name = "Fred", .lang = "en-US", .local = true },
    .{ .name = "Thomas", .lang = "fr-FR", .local = true },
    .{ .name = "Anna", .lang = "de-DE", .local = true },
    .{ .name = "Monica", .lang = "es-ES", .local = true },
    .{ .name = "Alice", .lang = "it-IT", .local = true },
    .{ .name = "Kyoko", .lang = "ja-JP", .local = true },
    .{ .name = "Yuna", .lang = "ko-KR", .local = true },
    .{ .name = "Linh", .lang = "vi-VN", .local = true },
    .{ .name = "Tingting", .lang = "zh-CN", .local = true },
};

const android_voices = [_]Voice{
    .{ .name = "English United States", .lang = "en-US", .local = true },
    .{ .name = "English United Kingdom", .lang = "en-GB", .local = true },
    .{ .name = "English India", .lang = "en-IN", .local = true },
    .{ .name = "Tiếng Việt Việt Nam", .lang = "vi-VN", .local = true },
    .{ .name = "español Estados Unidos", .lang = "es-US", .local = true },
    .{ .name = "français France", .lang = "fr-FR", .local = true },
    .{ .name = "Deutsch Deutschland", .lang = "de-DE", .local = true },
    .{ .name = "日本語 日本", .lang = "ja-JP", .local = true },
    .{ .name = "한국어 대한민국", .lang = "ko-KR", .local = true },
    .{ .name = "中文 中国", .lang = "zh-CN", .local = true },
};

/// Vietnamese Windows installs also ship "Microsoft An".
const windows_vi = Voice{ .name = "Microsoft An - Vietnamese (Vietnam)", .lang = "vi-VN", .local = true };

fn getVoices(_: *const SpeechSynthesis, exec: *Execution) ![]*SpeechSynthesisVoice {
    var list: std.ArrayList(*SpeechSynthesisVoice) = .empty;
    const a = exec.call_arena;
    const p = Persona.get();
    if (p.speech_voices == .none) return list.items;
    const os_voices: []const Voice = switch (p.os) {
        .windows => &windows_voices,
        .macos, .ios => &mac_voices,
        .android => &android_voices,
        .linux, .chromeos => &.{},
    };
    var first = true;
    for (os_voices) |v| {
        try list.append(a, try exec._factory.create(SpeechSynthesisVoice{ ._v = v, ._default = first }));
        first = false;
    }
    if (p.os == .windows and p.timezone != null and std.mem.eql(u8, p.timezone.?, "Asia/Ho_Chi_Minh")) {
        try list.append(a, try exec._factory.create(SpeechSynthesisVoice{ ._v = windows_vi }));
    }
    // Chrome for Android has no network voices; desktop Chrome adds them.
    if (p.speech_voices == .full and p.os != .android and p.os != .ios) {
        for (google_voices) |v| {
            try list.append(a, try exec._factory.create(SpeechSynthesisVoice{ ._v = v, ._default = first }));
            first = false;
        }
    }
    return list.items;
}

fn speak(_: *SpeechSynthesis, _: ?js.Value) void {}
fn cancel(_: *SpeechSynthesis) void {}
fn pause(_: *SpeechSynthesis) void {}
fn resumeSpeech(_: *SpeechSynthesis) void {}
fn getFalse(_: *const SpeechSynthesis) bool {
    return false;
}

pub const SpeechSynthesisVoice = struct {
    _v: Voice,
    _default: bool = false,

    fn getName(self: *const SpeechSynthesisVoice) []const u8 {
        return self._v.name;
    }
    fn getLang(self: *const SpeechSynthesisVoice) []const u8 {
        return self._v.lang;
    }
    fn getLocal(self: *const SpeechSynthesisVoice) bool {
        return self._v.local;
    }
    fn getDefault(self: *const SpeechSynthesisVoice) bool {
        return self._default;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(SpeechSynthesisVoice);
        pub const Meta = struct {
            pub const name = "SpeechSynthesisVoice";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const voiceURI = bridge.accessor(SpeechSynthesisVoice.getName, null, .{});
        pub const name = bridge.accessor(SpeechSynthesisVoice.getName, null, .{});
        pub const lang = bridge.accessor(SpeechSynthesisVoice.getLang, null, .{});
        pub const localService = bridge.accessor(SpeechSynthesisVoice.getLocal, null, .{});
        pub const default = bridge.accessor(SpeechSynthesisVoice.getDefault, null, .{});
    };
};

pub const SpeechSynthesisUtterance = struct {
    _text: []const u8 = "",

    pub fn init(text: ?[]const u8, exec: *Execution) !*SpeechSynthesisUtterance {
        return exec._factory.create(SpeechSynthesisUtterance{ ._text = try exec.page_arena.dupe(u8, text orelse "") });
    }
    fn getText(self: *const SpeechSynthesisUtterance) []const u8 {
        return self._text;
    }
    fn setText(self: *SpeechSynthesisUtterance, value: []const u8, exec: *Execution) !void {
        self._text = try exec.page_arena.dupe(u8, value);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(SpeechSynthesisUtterance);
        pub const Meta = struct {
            pub const name = "SpeechSynthesisUtterance";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const constructor = bridge.constructor(SpeechSynthesisUtterance.init, .{});
        pub const text = bridge.accessor(SpeechSynthesisUtterance.getText, SpeechSynthesisUtterance.setText, .{});
        pub const lang = bridge.property("", .{ .template = false, .readonly = false });
        pub const volume = bridge.property(1.0, .{ .template = false, .readonly = false });
        pub const rate = bridge.property(1.0, .{ .template = false, .readonly = false });
        pub const pitch = bridge.property(1.0, .{ .template = false, .readonly = false });
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(SpeechSynthesis);

    pub const Meta = struct {
        pub const name = "SpeechSynthesis";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const getVoices = bridge.function(SpeechSynthesis.getVoices, .{});
    pub const speak = bridge.function(SpeechSynthesis.speak, .{});
    pub const cancel = bridge.function(SpeechSynthesis.cancel, .{});
    pub const pause = bridge.function(SpeechSynthesis.pause, .{});
    pub const @"resume" = bridge.function(SpeechSynthesis.resumeSpeech, .{});
    pub const pending = bridge.accessor(SpeechSynthesis.getFalse, null, .{});
    pub const speaking = bridge.accessor(SpeechSynthesis.getFalse, null, .{});
    pub const paused = bridge.accessor(SpeechSynthesis.getFalse, null, .{});
    pub const onvoiceschanged = EventTarget.handlerAccessor(SpeechSynthesis, "voiceschanged");
};
