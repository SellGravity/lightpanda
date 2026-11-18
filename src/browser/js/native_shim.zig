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

//! SellGravity antidetect: genuine native functions for the persona
//! bootstrap.
//!
//! A JS function (or a Proxy) standing in for a builtin is what fingerprint
//! "lie" detectors look for: toString shows source, it has a `prototype`,
//! wrong `length`/`name`, construct calls succeed. `makeNative(name, length,
//! impl)` returns a real V8 API function - `function name() { [native code] }`,
//! no `prototype`, throws on `new` - whose body forwards (this, args) to
//! `impl`. The maker itself is only ever handed to the bootstrap closure.

const std = @import("std");

const js = @import("js.zig");

const v8 = js.v8;

const max_args = 16;

/// The forwarding body of every function made by `makeNative`.
fn trampoline(raw: ?*const v8.FunctionCallbackInfo) callconv(.c) void {
    const info = raw orelse return;
    const isolate = v8.v8__FunctionCallbackInfo__GetIsolate(info) orelse return;
    const context = v8.v8__Isolate__GetCurrentContext(isolate) orelse return;
    const data = v8.v8__FunctionCallbackInfo__Data(info) orelse return;
    if (!v8.v8__Value__IsFunction(data)) return;
    const impl: *const v8.Function = @ptrCast(data);

    var argv: [max_args]*const v8.Value = undefined;
    const n: usize = @intCast(@min(@max(v8.v8__FunctionCallbackInfo__Length(info), 0), max_args));
    for (0..n) |i| {
        argv[i] = v8.v8__FunctionCallbackInfo__INDEX(info, @intCast(i)).?;
    }
    const recv: *const v8.Value = @ptrCast(v8.v8__FunctionCallbackInfo__This(info).?);
    // A throw inside impl stays pending on the isolate and propagates to the
    // caller, like a builtin throwing.
    const result = v8.v8__Function__Call(impl, context, recv, @intCast(n), @ptrCast(&argv)) orelse return;
    var rv: v8.ReturnValue = undefined;
    v8.v8__FunctionCallbackInfo__GetReturnValue(info, &rv);
    v8.v8__ReturnValue__Set(rv, result);
}

/// Body of interface stubs: `new X()` and `X()` both throw, as Chrome's
/// non-constructible interfaces do.
fn illegalConstructor(raw: ?*const v8.FunctionCallbackInfo) callconv(.c) void {
    const info = raw orelse return;
    const isolate = v8.v8__FunctionCallbackInfo__GetIsolate(info) orelse return;
    const message = v8.v8__String__NewFromUtf8(isolate, "Illegal constructor", v8.kNormal, 19);
    _ = v8.v8__Isolate__ThrowException(isolate, v8.v8__Exception__TypeError(message));
}

/// makeNative(name, length, impl[, ctor]) -> native function. With `ctor`
/// truthy the result is an interface object instead: constructible (so it
/// has a `prototype`) but every call throws "Illegal constructor".
fn maker(raw: ?*const v8.FunctionCallbackInfo) callconv(.c) void {
    const info = raw orelse return;
    if (v8.v8__FunctionCallbackInfo__Length(info) < 3) return;
    const isolate = v8.v8__FunctionCallbackInfo__GetIsolate(info) orelse return;
    const context = v8.v8__Isolate__GetCurrentContext(isolate) orelse return;
    const name = v8.v8__FunctionCallbackInfo__INDEX(info, 0) orelse return;
    const length = v8.v8__FunctionCallbackInfo__INDEX(info, 1) orelse return;
    const impl = v8.v8__FunctionCallbackInfo__INDEX(info, 2) orelse return;
    if (!v8.v8__Value__IsString(name) or !v8.v8__Value__IsFunction(impl)) return;
    const ctor = v8.v8__FunctionCallbackInfo__Length(info) > 3 and
        v8.v8__Value__BooleanValue(v8.v8__FunctionCallbackInfo__INDEX(info, 3).?, isolate);

    var len: c_int = 0;
    var maybe_len: v8.MaybeU32 = undefined;
    v8.v8__Value__Uint32Value(length, context, &maybe_len);
    if (maybe_len.has_value) len = @intCast(@min(maybe_len.value, 16));

    const template = (if (ctor) v8.v8__FunctionTemplate__New__Config(isolate, &.{
        .callback = illegalConstructor,
        .length = len,
        .behavior = v8.kConstructorBehavior_Allow,
    }) else v8.v8__FunctionTemplate__New__Config(isolate, &.{
        .callback = trampoline,
        .data = impl,
        .length = len,
        .behavior = v8.kConstructorBehavior_Throw,
    })) orelse return;
    const func = v8.v8__FunctionTemplate__GetFunction(template, context) orelse return;
    v8.v8__Function__SetName(func, @ptrCast(name));
    var rv: v8.ReturnValue = undefined;
    v8.v8__FunctionCallbackInfo__GetReturnValue(info, &rv);
    v8.v8__ReturnValue__Set(rv, @ptrCast(func));
}

/// The maker as a JS function value, to pass to the bootstrap.
pub fn makerFunction(local: *const js.Local) ?js.Function {
    const handle = v8.v8__Function__New__DEFAULT(local.handle, maker) orelse return null;
    return .{ .local = local, .handle = handle };
}

/// Evaluates the persona bootstrap (a function expression) and calls it with
/// (makeNative, { timezone }). Errors are returned to the caller to log.
pub fn runPersonaBootstrap(local: *const js.Local, source: []const u8, timezone: ?[]const u8) !void {
    const fn_value = try local.exec(source, "");
    if (!v8.v8__Value__IsFunction(fn_value.handle)) return error.BootstrapNotAFunction;
    const bootstrap: *const v8.Function = @ptrCast(fn_value.handle);
    const make = makerFunction(local) orelse return error.BootstrapMaker;
    const persona = try local.zigValueToJs(.{ .timezone = timezone orelse "", .chromeMajor = @import("../../Persona.zig").get().chrome_major }, .{});
    var argv = [_]*const v8.Value{ @ptrCast(make.handle), persona.handle };
    const recv: *const v8.Value = @ptrCast(v8.v8__Context__Global(local.handle).?);
    _ = v8.v8__Function__Call(bootstrap, local.handle, recv, 2, @ptrCast(&argv)) orelse return error.BootstrapThrew;
}
