// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
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

const std = @import("std");

const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const Persona = @import("../../../Persona.zig");

pub fn registerTypes() []const type {
    return &.{
        WebGLRenderingContext,
        // Extension types should be runtime generated. We might want
        // to revisit this.
        Extension.Type.WEBGL_debug_renderer_info,
        Extension.Type.WEBGL_lose_context,
        ShaderPrecisionFormat,
        WebGLBuffer,
        WebGLShader,
        WebGLProgram,
        WebGLTexture,
        WebGLFramebuffer,
        WebGLRenderbuffer,
        WebGLUniformLocation,
        WebGLActiveInfo,
    };
}

const WebGLRenderingContext = @This();

// Drawing buffer size, fixed when the context is created (like Chrome, a
// later canvas resize only changes it on the next frame).
_width: u32 = 300,
_height: u32 = 150,

/// On Chrome and Safari, a call to `getSupportedExtensions` returns total of 39.
/// The reference for it lists lesser number of extensions:
/// https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/Using_Extensions#extension_list
const Extension = union(enum) {
    ANGLE_instanced_arrays: void,
    EXT_blend_minmax: void,
    EXT_clip_control: void,
    EXT_color_buffer_half_float: void,
    EXT_depth_clamp: void,
    EXT_disjoint_timer_query: void,
    EXT_float_blend: void,
    EXT_frag_depth: void,
    EXT_polygon_offset_clamp: void,
    EXT_shader_texture_lod: void,
    EXT_texture_compression_bptc: void,
    EXT_texture_compression_rgtc: void,
    EXT_texture_filter_anisotropic: void,
    EXT_texture_mirror_clamp_to_edge: void,
    EXT_sRGB: void,
    KHR_parallel_shader_compile: void,
    OES_element_index_uint: void,
    OES_fbo_render_mipmap: void,
    OES_standard_derivatives: void,
    OES_texture_float: void,
    OES_texture_float_linear: void,
    OES_texture_half_float: void,
    OES_texture_half_float_linear: void,
    OES_vertex_array_object: void,
    WEBGL_blend_func_extended: void,
    WEBGL_color_buffer_float: void,
    WEBGL_compressed_texture_astc: void,
    WEBGL_compressed_texture_etc: void,
    WEBGL_compressed_texture_etc1: void,
    WEBGL_compressed_texture_pvrtc: void,
    WEBGL_compressed_texture_s3tc: void,
    WEBGL_compressed_texture_s3tc_srgb: void,
    WEBGL_debug_renderer_info: *Type.WEBGL_debug_renderer_info,
    WEBGL_debug_shaders: void,
    WEBGL_depth_texture: void,
    WEBGL_draw_buffers: void,
    WEBGL_lose_context: *Type.WEBGL_lose_context,
    WEBGL_multi_draw: void,
    WEBGL_polygon_mode: void,

    /// Reified enum type from the fields of this union.
    const Kind = blk: {
        const names = @typeInfo(Extension).@"union".field_names;
        const Tag = std.math.IntFittingRange(0, if (names.len == 0) 0 else names.len - 1);
        break :blk @Enum(Tag, .exhaustive, names, &std.simd.iota(Tag, names.len));
    };

    /// Returns the `Extension.Kind` by its name.
    fn find(name: []const u8) ?Kind {
        // Just to make you really sad, this function has to be case-insensitive.
        // So here we copy what's being done in `std.meta.stringToEnum` but replace
        // the comparison function.
        const kvs = comptime build_kvs: {
            const T = Extension.Kind;
            const EnumKV = struct { []const u8, T };
            var kvs_array: [@typeInfo(T).@"enum".field_names.len]EnumKV = undefined;
            for (@typeInfo(T).@"enum".field_names, 0..) |field_name, i| {
                kvs_array[i] = .{ field_name, @field(T, field_name) };
            }
            break :build_kvs kvs_array[0..];
        };
        const Map = std.StaticStringMapWithEql(Extension.Kind, std.static_string_map.eqlAsciiIgnoreCase);
        const map = Map.initComptime(kvs);
        return map.get(name);
    }

    /// Extension types.
    pub const Type = struct {
        pub const WEBGL_debug_renderer_info = struct {
            _: u8 = 0,
            const UNMASKED_VENDOR_WEBGL: u64 = 0x9245;
            const UNMASKED_RENDERER_WEBGL: u64 = 0x9246;

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_debug_renderer_info);

                pub const Meta = struct {
                    pub const name = "WEBGL_debug_renderer_info";

                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const UNMASKED_VENDOR_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_VENDOR_WEBGL, .{ .template = false, .readonly = true });
                pub const UNMASKED_RENDERER_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_RENDERER_WEBGL, .{ .template = false, .readonly = true });
            };
        };

        pub const WEBGL_lose_context = struct {
            _: u8 = 0,
            fn loseContext(_: *const WEBGL_lose_context) void {}
            fn restoreContext(_: *const WEBGL_lose_context) void {}

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_lose_context);

                pub const Meta = struct {
                    pub const name = "WEBGL_lose_context";

                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const loseContext = bridge.function(WEBGL_lose_context.loseContext, .{ .noop = true });
                pub const restoreContext = bridge.function(WEBGL_lose_context.restoreContext, .{ .noop = true });
            };
        };
    };
};

// ===========================================================================
// SellGravity antidetect: a WebGL 1 context that reports the persona's GPU.
//
// Lightpanda has no GPU or rasterizer. Fingerprinting scripts only read the
// context (parameters, extensions, precision formats, attributes) and run a
// tiny draw; everything that would render is a no-op. Only exposed for
// launcher profiles (`Canvas.getContext`), upstream keeps returning null.
// ===========================================================================

/// Whether `getContext("webgl")` should hand out this context.
pub fn enabled() bool {
    return Persona.active;
}

pub fn create(frame: *Frame, width: u32, height: u32) !*WebGLRenderingContext {
    return frame._factory.create(WebGLRenderingContext{ ._width = width, ._height = height });
}

const Param = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    boolean: bool,
    int32_array: js.TypedArray(i32),
    float32_array: js.TypedArray(f32),
};

const GpuClass = enum { desktop, apple, mobile };

fn gpuClass() GpuClass {
    return switch (Persona.get().os) {
        .macos, .ios => .apple,
        .android => .mobile,
        else => .desktop,
    };
}

// Values Chrome/ANGLE reports per GPU class (D3D11 on Windows, Metal on
// macOS, GLES on Android/Adreno). Static so the typed arrays outlive the call.
const max_viewport_dims = [_]i32{ 32767, 32767 };
const max_viewport_dims_mobile = [_]i32{ 16384, 16384 };
const aliased_line_width_range = [_]f32{ 1, 1 };
const aliased_point_size_range = [_]f32{ 1, 1024 };
const aliased_point_size_range_apple = [_]f32{ 1, 511 };
const aliased_point_size_range_mobile = [_]f32{ 1, 1023 };

fn getParameter(self: *const WebGLRenderingContext, pname_value: ?f64) ?Param {
    const pname: u32 = if (pname_value) |v| (if (v >= 0 and v <= 0xFFFFFFFF) @intFromFloat(v) else return null) else return null;
    const p = Persona.get();
    const class = gpuClass();
    return switch (pname) {
        0x1F00 => .{ .string = "WebKit" }, // VENDOR
        0x1F01 => .{ .string = "WebKit WebGL" }, // RENDERER
        0x1F02 => .{ .string = "WebGL 1.0 (OpenGL ES 2.0 Chromium)" }, // VERSION
        0x8B8C => .{ .string = "WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 Chromium)" }, // SHADING_LANGUAGE_VERSION
        0x9245 => .{ .string = p.webgl_vendor }, // UNMASKED_VENDOR_WEBGL
        0x9246 => .{ .string = p.webgl_renderer }, // UNMASKED_RENDERER_WEBGL

        0x0D33, 0x851C, 0x84E8 => .{ .int = if (class == .mobile) 16384 else 16384 }, // MAX_TEXTURE_SIZE, MAX_CUBE_MAP_TEXTURE_SIZE, MAX_RENDERBUFFER_SIZE
        0x0D3A => .{ .int32_array = .{ .values = if (class == .mobile) &max_viewport_dims_mobile else &max_viewport_dims } }, // MAX_VIEWPORT_DIMS
        0x8869 => .{ .int = 16 }, // MAX_VERTEX_ATTRIBS
        0x8DFB => .{
            .int = switch (class) { // MAX_VERTEX_UNIFORM_VECTORS
                .desktop => 4096,
                .apple => 1024,
                .mobile => 256,
            },
        },
        0x8DFD => .{
            .int = switch (class) { // MAX_FRAGMENT_UNIFORM_VECTORS
                .desktop => 1024,
                .apple => 1024,
                .mobile => 256,
            },
        },
        0x8DFC => .{
            .int = switch (class) { // MAX_VARYING_VECTORS
                .desktop => 30,
                .apple => 31,
                .mobile => 31,
            },
        },
        0x8872 => .{ .int = 16 }, // MAX_TEXTURE_IMAGE_UNITS
        0x8B4C => .{ .int = 16 }, // MAX_VERTEX_TEXTURE_IMAGE_UNITS
        0x8B4D => .{ .int = 32 }, // MAX_COMBINED_TEXTURE_IMAGE_UNITS
        0x846E => .{ .float32_array = .{ .values = &aliased_line_width_range } }, // ALIASED_LINE_WIDTH_RANGE
        0x846D => .{
            .float32_array = .{
                .values = switch (class) { // ALIASED_POINT_SIZE_RANGE
                    .desktop => &aliased_point_size_range,
                    .apple => &aliased_point_size_range_apple,
                    .mobile => &aliased_point_size_range_mobile,
                },
            },
        },
        0x0D50 => .{ .int = 4 }, // SUBPIXEL_BITS
        0x0D52, 0x0D53, 0x0D54, 0x0D55 => .{ .int = 8 }, // RED/GREEN/BLUE/ALPHA_BITS
        0x0D56 => .{ .int = 24 }, // DEPTH_BITS
        0x0D57 => .{ .int = 0 }, // STENCIL_BITS (stencil: false by default)
        0x80A8 => .{ .int = 1 }, // SAMPLE_BUFFERS
        0x80A9 => .{ .int = 4 }, // SAMPLES
        0x84FF => .{ .int = 16 }, // MAX_TEXTURE_MAX_ANISOTROPY_EXT
        0x8B8D => .{ .int = 0 }, // CURRENT_PROGRAM -> null in Chrome, 0 is close enough
        0x0BA2 => .{ .int32_array = .{ .values = &.{ 0, 0, @intCast(self._width), @intCast(self._height) } } }, // VIEWPORT
        0x0C10 => .{ .int32_array = .{ .values = &.{ 0, 0, @intCast(self._width), @intCast(self._height) } } }, // SCISSOR_BOX
        0x0B71, 0x0BE2, 0x0B90, 0x0C11, 0x8037, 0x809E, 0x80A0 => .{ .boolean = false }, // DEPTH_TEST, BLEND, STENCIL_TEST, SCISSOR_TEST, POLYGON_OFFSET_FILL, SAMPLE_ALPHA_TO_COVERAGE, SAMPLE_COVERAGE
        0x0BD0 => .{ .boolean = true }, // DITHER
        0x9240 => .{ .boolean = false }, // UNPACK_FLIP_Y_WEBGL
        0x9241 => .{ .boolean = false }, // UNPACK_PREMULTIPLY_ALPHA_WEBGL
        0x0CF5, 0x0D05 => .{ .int = 4 }, // UNPACK_ALIGNMENT, PACK_ALIGNMENT
        0x8B9A => .{ .int = 0x1908 }, // IMPLEMENTATION_COLOR_READ_FORMAT (RGBA)
        0x8B9B => .{ .int = 0x1401 }, // IMPLEMENTATION_COLOR_READ_TYPE (UNSIGNED_BYTE)
        else => null,
    };
}

/// Extensions exposed per GPU class, in Chrome's order. ASTC/ETC/PVRTC only
/// exist on mobile GPUs, S3TC/BPTC/RGTC only on desktop ones: a Windows
/// persona listing ETC is an instant mismatch.
fn supportedExtensions() []const []const u8 {
    const desktop = [_][]const u8{
        "ANGLE_instanced_arrays",             "EXT_blend_minmax",                 "EXT_clip_control",
        "EXT_color_buffer_half_float",        "EXT_depth_clamp",                  "EXT_disjoint_timer_query",
        "EXT_float_blend",                    "EXT_frag_depth",                   "EXT_polygon_offset_clamp",
        "EXT_shader_texture_lod",             "EXT_texture_compression_bptc",     "EXT_texture_compression_rgtc",
        "EXT_texture_filter_anisotropic",     "EXT_texture_mirror_clamp_to_edge", "EXT_sRGB",
        "KHR_parallel_shader_compile",        "OES_element_index_uint",           "OES_fbo_render_mipmap",
        "OES_standard_derivatives",           "OES_texture_float",                "OES_texture_float_linear",
        "OES_texture_half_float",             "OES_texture_half_float_linear",    "OES_vertex_array_object",
        "WEBGL_blend_func_extended",          "WEBGL_color_buffer_float",         "WEBGL_compressed_texture_s3tc",
        "WEBGL_compressed_texture_s3tc_srgb", "WEBGL_debug_renderer_info",        "WEBGL_debug_shaders",
        "WEBGL_depth_texture",                "WEBGL_draw_buffers",               "WEBGL_lose_context",
        "WEBGL_multi_draw",                   "WEBGL_polygon_mode",
    };
    const apple = [_][]const u8{
        "ANGLE_instanced_arrays",         "EXT_blend_minmax",                   "EXT_clip_control",
        "EXT_color_buffer_half_float",    "EXT_depth_clamp",                    "EXT_disjoint_timer_query",
        "EXT_float_blend",                "EXT_frag_depth",                     "EXT_polygon_offset_clamp",
        "EXT_shader_texture_lod",         "EXT_texture_compression_bptc",       "EXT_texture_compression_rgtc",
        "EXT_texture_filter_anisotropic", "EXT_texture_mirror_clamp_to_edge",   "EXT_sRGB",
        "KHR_parallel_shader_compile",    "OES_element_index_uint",             "OES_fbo_render_mipmap",
        "OES_standard_derivatives",       "OES_texture_float",                  "OES_texture_float_linear",
        "OES_texture_half_float",         "OES_texture_half_float_linear",      "OES_vertex_array_object",
        "WEBGL_blend_func_extended",      "WEBGL_color_buffer_float",           "WEBGL_compressed_texture_astc",
        "WEBGL_compressed_texture_etc",   "WEBGL_compressed_texture_etc1",      "WEBGL_compressed_texture_pvrtc",
        "WEBGL_compressed_texture_s3tc",  "WEBGL_compressed_texture_s3tc_srgb", "WEBGL_debug_renderer_info",
        "WEBGL_debug_shaders",            "WEBGL_depth_texture",                "WEBGL_draw_buffers",
        "WEBGL_lose_context",             "WEBGL_multi_draw",                   "WEBGL_polygon_mode",
    };
    const mobile = [_][]const u8{
        "ANGLE_instanced_arrays",        "EXT_blend_minmax",               "EXT_color_buffer_half_float",
        "EXT_disjoint_timer_query",      "EXT_float_blend",                "EXT_frag_depth",
        "EXT_shader_texture_lod",        "EXT_texture_filter_anisotropic", "EXT_sRGB",
        "KHR_parallel_shader_compile",   "OES_element_index_uint",         "OES_fbo_render_mipmap",
        "OES_standard_derivatives",      "OES_texture_float",              "OES_texture_float_linear",
        "OES_texture_half_float",        "OES_texture_half_float_linear",  "OES_vertex_array_object",
        "WEBGL_color_buffer_float",      "WEBGL_compressed_texture_astc",  "WEBGL_compressed_texture_etc",
        "WEBGL_compressed_texture_etc1", "WEBGL_debug_renderer_info",      "WEBGL_debug_shaders",
        "WEBGL_depth_texture",           "WEBGL_draw_buffers",             "WEBGL_lose_context",
        "WEBGL_multi_draw",
    };
    if (!Persona.active) return @typeInfo(Extension.Kind).@"enum".field_names;
    return switch (gpuClass()) {
        .desktop => &desktop,
        .apple => &apple,
        .mobile => &mobile,
    };
}

fn isSupported(name: []const u8) bool {
    for (supportedExtensions()) |ext| {
        if (std.ascii.eqlIgnoreCase(ext, name)) return true;
    }
    return false;
}

/// Enables a WebGL extension.
fn getExtension(_: *const WebGLRenderingContext, name: []const u8, frame: *Frame) !?Extension {
    if (!isSupported(name)) return null;
    const tag = Extension.find(name) orelse return null;

    return switch (tag) {
        .WEBGL_debug_renderer_info => {
            const info = try frame._factory.create(Extension.Type.WEBGL_debug_renderer_info{});
            return .{ .WEBGL_debug_renderer_info = info };
        },
        .WEBGL_lose_context => {
            const ctx = try frame._factory.create(Extension.Type.WEBGL_lose_context{});
            return .{ .WEBGL_lose_context = ctx };
        },
        inline else => |comptime_enum| @unionInit(Extension, @tagName(comptime_enum), {}),
    };
}

/// Returns a list of all the supported WebGL extensions.
fn getSupportedExtensions(_: *const WebGLRenderingContext) []const []const u8 {
    return supportedExtensions();
}

const ContextAttributes = struct {
    alpha: bool = true,
    antialias: bool = true,
    depth: bool = true,
    desynchronized: bool = false,
    failIfMajorPerformanceCaveat: bool = false,
    powerPreference: []const u8 = "default",
    premultipliedAlpha: bool = true,
    preserveDrawingBuffer: bool = false,
    stencil: bool = false,
    xrCompatible: bool = false,
};

fn getContextAttributes(_: *const WebGLRenderingContext) ContextAttributes {
    return .{};
}

fn isContextLost(_: *const WebGLRenderingContext) bool {
    return false;
}

fn getError(_: *const WebGLRenderingContext) u32 {
    return 0;
}

fn getDrawingBufferWidth(self: *const WebGLRenderingContext) u32 {
    return self._width;
}

fn getDrawingBufferHeight(self: *const WebGLRenderingContext) u32 {
    return self._height;
}

/// WebGLShaderPrecisionFormat. Chrome on desktop/Apple GPUs reports full IEEE
/// single precision for every float precision; mobile GPUs keep mediump/lowp
/// at half precision.
pub const ShaderPrecisionFormat = struct {
    _range_min: i32,
    _range_max: i32,
    _precision: i32,

    fn getRangeMin(self: *const ShaderPrecisionFormat) i32 {
        return self._range_min;
    }
    fn getRangeMax(self: *const ShaderPrecisionFormat) i32 {
        return self._range_max;
    }
    fn getPrecision(self: *const ShaderPrecisionFormat) i32 {
        return self._precision;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ShaderPrecisionFormat);
        pub const Meta = struct {
            pub const name = "WebGLShaderPrecisionFormat";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const rangeMin = bridge.accessor(ShaderPrecisionFormat.getRangeMin, null, .{});
        pub const rangeMax = bridge.accessor(ShaderPrecisionFormat.getRangeMax, null, .{});
        pub const precision = bridge.accessor(ShaderPrecisionFormat.getPrecision, null, .{});
    };
};

fn getShaderPrecisionFormat(_: *const WebGLRenderingContext, _: ?f64, precision_type: ?f64, frame: *Frame) !?*ShaderPrecisionFormat {
    const t: u32 = if (precision_type) |v| @intFromFloat(@max(0, @min(v, 0xFFFF))) else return null;
    const mobile = gpuClass() == .mobile;
    const fmt: ShaderPrecisionFormat = switch (t) {
        0x8DF2 => .{ ._range_min = 127, ._range_max = 127, ._precision = 23 }, // HIGH_FLOAT
        0x8DF1, 0x8DF0 => if (mobile) // MEDIUM_FLOAT, LOW_FLOAT
            .{ ._range_min = 15, ._range_max = 15, ._precision = 10 }
        else
            .{ ._range_min = 127, ._range_max = 127, ._precision = 23 },
        0x8DF5 => .{ ._range_min = 31, ._range_max = 30, ._precision = 0 }, // HIGH_INT
        0x8DF4, 0x8DF3 => if (mobile) // MEDIUM_INT, LOW_INT
            .{ ._range_min = 15, ._range_max = 14, ._precision = 0 }
        else
            .{ ._range_min = 31, ._range_max = 30, ._precision = 0 },
        else => return null,
    };
    return try frame._factory.create(fmt);
}

// --- opaque GL objects -----------------------------------------------------

fn GlObject(comptime class_name: []const u8) type {
    return struct {
        _: u8 = 0,
        const Self = @This();
        pub const JsApi = struct {
            pub const bridge = js.Bridge(Self);
            pub const Meta = struct {
                pub const name = class_name;
                pub var class_id: bridge.ClassId = undefined;
            };
        };
    };
}

pub const WebGLBuffer = GlObject("WebGLBuffer");
pub const WebGLShader = GlObject("WebGLShader");
pub const WebGLProgram = GlObject("WebGLProgram");
pub const WebGLTexture = GlObject("WebGLTexture");
pub const WebGLFramebuffer = GlObject("WebGLFramebuffer");
pub const WebGLRenderbuffer = GlObject("WebGLRenderbuffer");
pub const WebGLUniformLocation = GlObject("WebGLUniformLocation");

pub const WebGLActiveInfo = struct {
    _name: []const u8 = "",
    _size: i32 = 1,
    _type: u32 = 0x1406, // FLOAT

    fn getName(self: *const WebGLActiveInfo) []const u8 {
        return self._name;
    }
    fn getSize(self: *const WebGLActiveInfo) i32 {
        return self._size;
    }
    fn getType(self: *const WebGLActiveInfo) u32 {
        return self._type;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(WebGLActiveInfo);
        pub const Meta = struct {
            pub const name = "WebGLActiveInfo";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const name = bridge.accessor(WebGLActiveInfo.getName, null, .{});
        pub const size = bridge.accessor(WebGLActiveInfo.getSize, null, .{});
        pub const @"type" = bridge.accessor(WebGLActiveInfo.getType, null, .{});
    };
};

fn createBuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLBuffer {
    return frame._factory.create(WebGLBuffer{});
}
fn createShader(_: *const WebGLRenderingContext, _: ?f64, frame: *Frame) !*WebGLShader {
    return frame._factory.create(WebGLShader{});
}
fn createProgram(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLProgram {
    return frame._factory.create(WebGLProgram{});
}
fn createTexture(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLTexture {
    return frame._factory.create(WebGLTexture{});
}
fn createFramebuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLFramebuffer {
    return frame._factory.create(WebGLFramebuffer{});
}
fn createRenderbuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLRenderbuffer {
    return frame._factory.create(WebGLRenderbuffer{});
}
fn getUniformLocation(_: *const WebGLRenderingContext, _: ?js.Value, _: ?[]const u8, frame: *Frame) !*WebGLUniformLocation {
    return frame._factory.create(WebGLUniformLocation{});
}
fn getAttribLocation(_: *const WebGLRenderingContext, _: ?js.Value, _: ?[]const u8) i32 {
    return 0;
}
fn getActiveAttrib(_: *const WebGLRenderingContext, _: ?js.Value, _: ?f64, frame: *Frame) !*WebGLActiveInfo {
    return frame._factory.create(WebGLActiveInfo{ ._name = "attrVertex" });
}
fn getActiveUniform(_: *const WebGLRenderingContext, _: ?js.Value, _: ?f64, frame: *Frame) !*WebGLActiveInfo {
    return frame._factory.create(WebGLActiveInfo{ ._name = "uniformOffset", ._type = 0x8B50 });
}
/// COMPILE_STATUS / LINK_STATUS / VALIDATE_STATUS -> true, counts -> 1.
fn getObjectParameter(_: *const WebGLRenderingContext, _: ?js.Value, pname: ?f64) Param {
    const p: u32 = if (pname) |v| @intFromFloat(@max(0, @min(v, 0xFFFF))) else 0;
    return switch (p) {
        0x8B81, 0x8B82, 0x8B83 => .{ .boolean = true },
        0x8B80 => .{ .boolean = false }, // DELETE_STATUS
        0x8B4F => .{ .int = 0x8B31 }, // SHADER_TYPE
        else => .{ .int = 1 },
    };
}
fn getInfoLog(_: *const WebGLRenderingContext, _: ?js.Value) []const u8 {
    return "";
}
fn checkFramebufferStatus(_: *const WebGLRenderingContext, _: ?f64) u32 {
    return 0x8CD5; // FRAMEBUFFER_COMPLETE
}
fn isObject(_: *const WebGLRenderingContext, v: ?js.Value) bool {
    return v != null;
}
fn noop(_: *const WebGLRenderingContext) void {}

pub const JsApi = struct {
    pub const bridge = js.Bridge(WebGLRenderingContext);

    pub const Meta = struct {
        pub const name = "WebGLRenderingContext";

        pub var class_id: bridge.ClassId = undefined;
    };

    pub const getParameter = bridge.function(WebGLRenderingContext.getParameter, .{});
    pub const getExtension = bridge.function(WebGLRenderingContext.getExtension, .{});
    pub const getSupportedExtensions = bridge.function(WebGLRenderingContext.getSupportedExtensions, .{});
    pub const getContextAttributes = bridge.function(WebGLRenderingContext.getContextAttributes, .{});
    pub const getShaderPrecisionFormat = bridge.function(WebGLRenderingContext.getShaderPrecisionFormat, .{});
    pub const isContextLost = bridge.function(WebGLRenderingContext.isContextLost, .{});
    pub const getError = bridge.function(WebGLRenderingContext.getError, .{});
    pub const drawingBufferWidth = bridge.accessor(WebGLRenderingContext.getDrawingBufferWidth, null, .{});
    pub const drawingBufferHeight = bridge.accessor(WebGLRenderingContext.getDrawingBufferHeight, null, .{});

    pub const createBuffer = bridge.function(WebGLRenderingContext.createBuffer, .{});
    pub const createShader = bridge.function(WebGLRenderingContext.createShader, .{});
    pub const createProgram = bridge.function(WebGLRenderingContext.createProgram, .{});
    pub const createTexture = bridge.function(WebGLRenderingContext.createTexture, .{});
    pub const createFramebuffer = bridge.function(WebGLRenderingContext.createFramebuffer, .{});
    pub const createRenderbuffer = bridge.function(WebGLRenderingContext.createRenderbuffer, .{});
    pub const getUniformLocation = bridge.function(WebGLRenderingContext.getUniformLocation, .{});
    pub const getAttribLocation = bridge.function(WebGLRenderingContext.getAttribLocation, .{});
    pub const getActiveAttrib = bridge.function(WebGLRenderingContext.getActiveAttrib, .{});
    pub const getActiveUniform = bridge.function(WebGLRenderingContext.getActiveUniform, .{});
    pub const getShaderParameter = bridge.function(WebGLRenderingContext.getObjectParameter, .{});
    pub const getProgramParameter = bridge.function(WebGLRenderingContext.getObjectParameter, .{});
    pub const getShaderInfoLog = bridge.function(WebGLRenderingContext.getInfoLog, .{});
    pub const getProgramInfoLog = bridge.function(WebGLRenderingContext.getInfoLog, .{});
    pub const checkFramebufferStatus = bridge.function(WebGLRenderingContext.checkFramebufferStatus, .{});
    pub const isBuffer = bridge.function(WebGLRenderingContext.isObject, .{});
    pub const isShader = bridge.function(WebGLRenderingContext.isObject, .{});
    pub const isProgram = bridge.function(WebGLRenderingContext.isObject, .{});
    pub const isTexture = bridge.function(WebGLRenderingContext.isObject, .{});

    // Everything that would touch the GPU. No-op, like a draw into a buffer
    // nobody reads back.
    pub const activeTexture = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const attachShader = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bindAttribLocation = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bindBuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bindFramebuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bindRenderbuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bindTexture = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const blendColor = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const blendEquation = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const blendEquationSeparate = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const blendFunc = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const blendFuncSeparate = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bufferData = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const bufferSubData = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const clear = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const clearColor = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const clearDepth = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const clearStencil = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const colorMask = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const compileShader = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const compressedTexImage2D = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const copyTexImage2D = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const cullFace = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteBuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteFramebuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteProgram = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteRenderbuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteShader = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const deleteTexture = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const depthFunc = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const depthMask = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const depthRange = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const detachShader = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const disable = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const disableVertexAttribArray = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const drawArrays = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const drawElements = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const enable = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const enableVertexAttribArray = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const finish = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const flush = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const framebufferRenderbuffer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const framebufferTexture2D = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const frontFace = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const generateMipmap = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const hint = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const lineWidth = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const linkProgram = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const pixelStorei = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const polygonOffset = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const readPixels = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const renderbufferStorage = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const sampleCoverage = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const scissor = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const shaderSource = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const stencilFunc = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const stencilMask = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const stencilOp = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const texImage2D = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const texParameterf = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const texParameteri = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const texSubImage2D = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform1f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform1fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform1i = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform1iv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform2f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform2fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform3f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform3fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform4f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniform4fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniformMatrix2fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniformMatrix3fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const uniformMatrix4fv = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const useProgram = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const validateProgram = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const vertexAttrib1f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const vertexAttrib4f = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const vertexAttribPointer = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const viewport = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });

    // The GLenum constants fingerprinting code reads off the context.
    pub const DEPTH_BUFFER_BIT = bridge.property(0x00000100, .{ .template = false, .readonly = true });
    pub const STENCIL_BUFFER_BIT = bridge.property(0x00000400, .{ .template = false, .readonly = true });
    pub const COLOR_BUFFER_BIT = bridge.property(0x00004000, .{ .template = false, .readonly = true });
    pub const POINTS = bridge.property(0x0000, .{ .template = false, .readonly = true });
    pub const LINES = bridge.property(0x0001, .{ .template = false, .readonly = true });
    pub const LINE_STRIP = bridge.property(0x0003, .{ .template = false, .readonly = true });
    pub const TRIANGLES = bridge.property(0x0004, .{ .template = false, .readonly = true });
    pub const TRIANGLE_STRIP = bridge.property(0x0005, .{ .template = false, .readonly = true });
    pub const TRIANGLE_FAN = bridge.property(0x0006, .{ .template = false, .readonly = true });
    pub const ARRAY_BUFFER = bridge.property(0x8892, .{ .template = false, .readonly = true });
    pub const ELEMENT_ARRAY_BUFFER = bridge.property(0x8893, .{ .template = false, .readonly = true });
    pub const STATIC_DRAW = bridge.property(0x88E4, .{ .template = false, .readonly = true });
    pub const DYNAMIC_DRAW = bridge.property(0x88E8, .{ .template = false, .readonly = true });
    pub const BYTE = bridge.property(0x1400, .{ .template = false, .readonly = true });
    pub const UNSIGNED_BYTE = bridge.property(0x1401, .{ .template = false, .readonly = true });
    pub const SHORT = bridge.property(0x1402, .{ .template = false, .readonly = true });
    pub const UNSIGNED_SHORT = bridge.property(0x1403, .{ .template = false, .readonly = true });
    pub const INT = bridge.property(0x1404, .{ .template = false, .readonly = true });
    pub const UNSIGNED_INT = bridge.property(0x1405, .{ .template = false, .readonly = true });
    pub const FLOAT = bridge.property(0x1406, .{ .template = false, .readonly = true });
    pub const RGBA = bridge.property(0x1908, .{ .template = false, .readonly = true });
    pub const RGB = bridge.property(0x1907, .{ .template = false, .readonly = true });
    pub const FRAGMENT_SHADER = bridge.property(0x8B30, .{ .template = false, .readonly = true });
    pub const VERTEX_SHADER = bridge.property(0x8B31, .{ .template = false, .readonly = true });
    pub const COMPILE_STATUS = bridge.property(0x8B81, .{ .template = false, .readonly = true });
    pub const LINK_STATUS = bridge.property(0x8B82, .{ .template = false, .readonly = true });
    pub const LOW_FLOAT = bridge.property(0x8DF0, .{ .template = false, .readonly = true });
    pub const MEDIUM_FLOAT = bridge.property(0x8DF1, .{ .template = false, .readonly = true });
    pub const HIGH_FLOAT = bridge.property(0x8DF2, .{ .template = false, .readonly = true });
    pub const LOW_INT = bridge.property(0x8DF3, .{ .template = false, .readonly = true });
    pub const MEDIUM_INT = bridge.property(0x8DF4, .{ .template = false, .readonly = true });
    pub const HIGH_INT = bridge.property(0x8DF5, .{ .template = false, .readonly = true });
    pub const VENDOR = bridge.property(0x1F00, .{ .template = false, .readonly = true });
    pub const RENDERER = bridge.property(0x1F01, .{ .template = false, .readonly = true });
    pub const VERSION = bridge.property(0x1F02, .{ .template = false, .readonly = true });
    pub const SHADING_LANGUAGE_VERSION = bridge.property(0x8B8C, .{ .template = false, .readonly = true });
    pub const MAX_TEXTURE_SIZE = bridge.property(0x0D33, .{ .template = false, .readonly = true });
    pub const MAX_VIEWPORT_DIMS = bridge.property(0x0D3A, .{ .template = false, .readonly = true });
    pub const SUBPIXEL_BITS = bridge.property(0x0D50, .{ .template = false, .readonly = true });
    pub const RED_BITS = bridge.property(0x0D52, .{ .template = false, .readonly = true });
    pub const GREEN_BITS = bridge.property(0x0D53, .{ .template = false, .readonly = true });
    pub const BLUE_BITS = bridge.property(0x0D54, .{ .template = false, .readonly = true });
    pub const ALPHA_BITS = bridge.property(0x0D55, .{ .template = false, .readonly = true });
    pub const DEPTH_BITS = bridge.property(0x0D56, .{ .template = false, .readonly = true });
    pub const STENCIL_BITS = bridge.property(0x0D57, .{ .template = false, .readonly = true });
    pub const ALIASED_POINT_SIZE_RANGE = bridge.property(0x846D, .{ .template = false, .readonly = true });
    pub const ALIASED_LINE_WIDTH_RANGE = bridge.property(0x846E, .{ .template = false, .readonly = true });
    pub const MAX_RENDERBUFFER_SIZE = bridge.property(0x84E8, .{ .template = false, .readonly = true });
    pub const MAX_CUBE_MAP_TEXTURE_SIZE = bridge.property(0x851C, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_ATTRIBS = bridge.property(0x8869, .{ .template = false, .readonly = true });
    pub const MAX_TEXTURE_IMAGE_UNITS = bridge.property(0x8872, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_TEXTURE_IMAGE_UNITS = bridge.property(0x8B4C, .{ .template = false, .readonly = true });
    pub const MAX_COMBINED_TEXTURE_IMAGE_UNITS = bridge.property(0x8B4D, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_UNIFORM_VECTORS = bridge.property(0x8DFB, .{ .template = false, .readonly = true });
    pub const MAX_VARYING_VECTORS = bridge.property(0x8DFC, .{ .template = false, .readonly = true });
    pub const MAX_FRAGMENT_UNIFORM_VECTORS = bridge.property(0x8DFD, .{ .template = false, .readonly = true });
    pub const SAMPLES = bridge.property(0x80A9, .{ .template = false, .readonly = true });
    pub const SAMPLE_BUFFERS = bridge.property(0x80A8, .{ .template = false, .readonly = true });
    pub const DEPTH_TEST = bridge.property(0x0B71, .{ .template = false, .readonly = true });
    pub const BLEND = bridge.property(0x0BE2, .{ .template = false, .readonly = true });
    pub const TEXTURE_2D = bridge.property(0x0DE1, .{ .template = false, .readonly = true });
    pub const TEXTURE0 = bridge.property(0x84C0, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER = bridge.property(0x8D40, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER = bridge.property(0x8D41, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_COMPLETE = bridge.property(0x8CD5, .{ .template = false, .readonly = true });
    pub const NO_ERROR = bridge.property(0, .{ .template = false, .readonly = true });
};
