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
    // A throw inside impl propagates to the caller like a builtin's. An Error
    // made by impl would carry impl's own frames in its stack (the bootstrap
    // showing through); it is thrown again as a fresh error of the same type
    // and message, made here, whose stack starts at the caller.
    var replacement: ?*const v8.Value = null;
    const result = blk: {
        var tc: v8.TryCatch = undefined;
        v8.v8__TryCatch__CONSTRUCT(&tc, isolate);
        defer v8.v8__TryCatch__DESTRUCT(&tc);
        if (v8.v8__Function__Call(impl, context, recv, @intCast(n), @ptrCast(&argv))) |r| break :blk r;
        if (!v8.v8__TryCatch__HasCaught(&tc)) return;
        const exception = v8.v8__TryCatch__Exception(&tc) orelse return;
        replacement = freshError(isolate, context, exception);
        if (replacement == null) _ = v8.v8__TryCatch__ReThrow(&tc);
        break :blk null;
    } orelse {
        if (replacement) |e| _ = v8.v8__Isolate__ThrowException(isolate, e);
        return;
    };
    var rv: v8.ReturnValue = undefined;
    v8.v8__FunctionCallbackInfo__GetReturnValue(info, &rv);
    v8.v8__ReturnValue__Set(rv, result);
}

/// The same error as `exception`, created from native code, or null when it
/// isn't a plain Error / TypeError / RangeError / SyntaxError / ReferenceError.
fn freshError(isolate: *v8.Isolate, context: *const v8.Context, exception: *const v8.Value) ?*const v8.Value {
    if (!v8.v8__Value__IsNativeError(exception)) return null;
    const object: *const v8.Object = @ptrCast(exception);
    const key = v8.v8__String__NewFromUtf8(isolate, "message", v8.kNormal, 7) orelse return null;
    const message_value = v8.v8__Object__Get(object, context, @ptrCast(key)) orelse return null;
    const message = v8.v8__Value__ToString(message_value, context) orelse return null;
    const ctor = v8.v8__Object__GetConstructorName(object) orelse return null;
    var buf: [16]u8 = undefined;
    const len = v8.v8__String__WriteUtf8(ctor, isolate, &buf, buf.len, v8.WRITE_REPLACE_INVALID_UTF8, null);
    const name = buf[0..@min(len, buf.len)];
    if (std.mem.eql(u8, name, "TypeError")) return v8.v8__Exception__TypeError(message);
    if (std.mem.eql(u8, name, "RangeError")) return v8.v8__Exception__RangeError(message);
    if (std.mem.eql(u8, name, "SyntaxError")) return v8.v8__Exception__SyntaxError(message);
    if (std.mem.eql(u8, name, "ReferenceError")) return v8.v8__Exception__ReferenceError(message);
    if (std.mem.eql(u8, name, "Error")) return v8.v8__Exception__Error(message);
    return null;
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

// V8's pre-2026 fdlibm (src/fdlibm/legacy_math.cc).
extern fn lp_legacy_math(id: c_int, x: f64, y: f64) f64;

/// Chrome's Math functions moved from fdlibm to std/LLVM libm in 2026 (around
/// Chrome 148-150), changing results in the last bit. Personas of an older
/// Chrome get the fdlibm versions, so math fingerprints match that release.
/// sin/cos stay: Chrome already used glibc's for those, which agree with
/// what this V8 computes.
const legacy_math = [_]struct { name: []const u8, id: c_int, length: c_int }{
    .{ .name = "acos", .id = 0, .length = 1 },   .{ .name = "acosh", .id = 1, .length = 1 },
    .{ .name = "asin", .id = 2, .length = 1 },   .{ .name = "asinh", .id = 3, .length = 1 },
    .{ .name = "atan", .id = 4, .length = 1 },   .{ .name = "atanh", .id = 5, .length = 1 },
    .{ .name = "atan2", .id = 6, .length = 2 },  .{ .name = "cbrt", .id = 7, .length = 1 },
    .{ .name = "cosh", .id = 8, .length = 1 },   .{ .name = "exp", .id = 9, .length = 1 },
    .{ .name = "expm1", .id = 10, .length = 1 }, .{ .name = "log", .id = 11, .length = 1 },
    .{ .name = "log1p", .id = 12, .length = 1 }, .{ .name = "log10", .id = 13, .length = 1 },
    .{ .name = "log2", .id = 14, .length = 1 },  .{ .name = "sinh", .id = 15, .length = 1 },
    .{ .name = "tan", .id = 16, .length = 1 },   .{ .name = "tanh", .id = 17, .length = 1 },
};

/// The Chrome release whose V8 first shipped the libm Math.
pub const libm_math_since = 150;

fn legacyMathCallback(raw: ?*const v8.FunctionCallbackInfo) callconv(.c) void {
    const info = raw orelse return;
    const isolate = v8.v8__FunctionCallbackInfo__GetIsolate(info) orelse return;
    const context = v8.v8__Isolate__GetCurrentContext(isolate) orelse return;
    const data = v8.v8__FunctionCallbackInfo__Data(info) orelse return;
    const id: c_int = @intCast(v8.v8__Integer__Value(@ptrCast(data)));
    const argc = v8.v8__FunctionCallbackInfo__Length(info);
    var args: [2]f64 = .{ std.math.nan(f64), std.math.nan(f64) };
    // ToNumber on each argument in order, as the builtin does (valueOf runs,
    // a Symbol or BigInt throws).
    const wanted: c_int = if (id == 6) 2 else 1;
    var i: c_int = 0;
    while (i < wanted) : (i += 1) {
        if (i >= argc) break;
        var out: v8.MaybeF64 = undefined;
        v8.v8__Value__NumberValue(v8.v8__FunctionCallbackInfo__INDEX(info, i).?, context, &out);
        if (!out.has_value) return;
        args[@intCast(i)] = out.value;
    }
    const result = lp_legacy_math(id, args[0], args[1]);
    var rv: v8.ReturnValue = undefined;
    v8.v8__FunctionCallbackInfo__GetReturnValue(info, &rv);
    v8.v8__ReturnValue__Set(rv, @ptrCast(v8.v8__Number__New(isolate, result)));
}

/// Replaces the Math functions with the fdlibm ones, as native functions
/// with the builtins' names, lengths and attributes.
pub fn installLegacyMath(local: *const js.Local) void {
    const isolate = local.isolate.handle;
    const context = local.handle;
    const global = v8.v8__Context__Global(context) orelse return;
    const math_key = v8.v8__String__NewFromUtf8(isolate, "Math", v8.kNormal, 4) orelse return;
    const math_value = v8.v8__Object__Get(global, context, @ptrCast(math_key)) orelse return;
    if (!v8.v8__Value__IsObject(math_value)) return;
    const math: *const v8.Object = @ptrCast(math_value);
    for (legacy_math) |entry| {
        const template = v8.v8__FunctionTemplate__New__Config(isolate, &.{
            .callback = legacyMathCallback,
            .data = @ptrCast(v8.v8__Integer__New(isolate, entry.id)),
            .length = entry.length,
            .behavior = v8.kConstructorBehavior_Throw,
        }) orelse continue;
        const func = v8.v8__FunctionTemplate__GetFunction(template, context) orelse continue;
        const name = v8.v8__String__NewFromUtf8(isolate, entry.name.ptr, v8.kNormal, @intCast(entry.name.len)) orelse continue;
        v8.v8__Function__SetName(func, name);
        var out: v8.MaybeBool = undefined;
        v8.v8__Object__DefineOwnProperty(math, context, @ptrCast(name), @ptrCast(func), v8.DontEnum, &out);
    }
}

/// Keeps the pristine Error.captureStackTrace on the context (see
/// Context.persona_capture_stack).
fn rememberCaptureStackTrace(local: *const js.Local) void {
    const isolate = local.isolate.handle;
    const context = local.handle;
    const global = v8.v8__Context__Global(context) orelse return;
    const error_key = v8.v8__String__NewFromUtf8(isolate, "Error", v8.kNormal, 5) orelse return;
    const error_ctor = v8.v8__Object__Get(global, context, @ptrCast(error_key)) orelse return;
    if (!v8.v8__Value__IsObject(error_ctor)) return;
    const key = v8.v8__String__NewFromUtf8(isolate, "captureStackTrace", v8.kNormal, 17) orelse return;
    const capture = v8.v8__Object__Get(@ptrCast(error_ctor), context, @ptrCast(key)) orelse return;
    if (!v8.v8__Value__IsFunction(capture)) return;
    const func: js.Function = .{ .local = local, .handle = @ptrCast(capture) };
    local.ctx.persona_capture_stack = func.persist() catch null;
}

/// The maker as a JS function value, to pass to the bootstrap.
pub fn makerFunction(local: *const js.Local) ?js.Function {
    const handle = v8.v8__Function__New__DEFAULT(local.handle, maker) orelse return null;
    return .{ .local = local, .handle = handle };
}

/// Evaluates the persona bootstrap (a function expression) and calls it with
/// (makeNative, { timezone }). Errors are returned to the caller to log.
pub fn runPersonaBootstrap(local: *const js.Local, source: []const u8, timezone: ?[]const u8) !void {
    const major = @import("../../Persona.zig").get().chrome_major;
    if (major > 0 and major < libm_math_since) installLegacyMath(local);
    const fn_value = try local.exec(source, "");
    if (!v8.v8__Value__IsFunction(fn_value.handle)) return error.BootstrapNotAFunction;
    const bootstrap: *const v8.Function = @ptrCast(fn_value.handle);
    const make = makerFunction(local) orelse return error.BootstrapMaker;
    const Persona = @import("../../Persona.zig");
    const persona = try local.zigValueToJs(.{ .timezone = timezone orelse "", .chromeMajor = Persona.get().chrome_major, .parity = Persona.parity_table }, .{});
    var argv = [_]*const v8.Value{ @ptrCast(make.handle), persona.handle };
    const recv: *const v8.Value = @ptrCast(v8.v8__Context__Global(local.handle).?);
    _ = v8.v8__Function__Call(bootstrap, local.handle, recv, 2, @ptrCast(&argv)) orelse return error.BootstrapThrew;
    rememberCaptureStackTrace(local);
}
