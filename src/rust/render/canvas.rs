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

//! Canvas 2D rasterizer (SellGravity antidetect).
//!
//! The Zig side records every drawing call of a <canvas> 2D context as a flat
//! list of ops (paths already transformed to device space); when the page
//! reads pixels back (toDataURL / toBlob / getImageData) the list is replayed
//! here into a tiny-skia pixmap. A blank canvas is a headless tell and makes
//! every profile hash identically; this makes the hash depend on what was
//! drawn, and the per-profile noise is added on top by the caller.

use std::borrow::Cow;
use std::os::raw::c_void;

use parley::{FontFamily, FontStyle, FontWeight, PositionedLayoutItem, TextStyle};
use skrifa::instance::{LocationRef, Size};
use skrifa::outline::DrawSettings;
use skrifa::{GlyphId, MetadataProvider};
use tiny_skia::{
    BlendMode, Color, FillRule, GradientStop, LineCap, LineJoin, LinearGradient, Paint, Path,
    PathBuilder, Pixmap, Point, RadialGradient, Shader, SpreadMode, Stroke, Transform,
};

use crate::{LpWriteFn, Renderer, Rgb, Sink, TinyPen};

pub const OP_FILL_PATH: u32 = 0;
pub const OP_STROKE_PATH: u32 = 1;
pub const OP_CLEAR_PATH: u32 = 2;
pub const OP_FILL_TEXT: u32 = 3;
pub const OP_STROKE_TEXT: u32 = 4;
pub const OP_PUT_IMAGE: u32 = 5;
pub const OP_DRAW_IMAGE: u32 = 6;

pub const VERB_MOVE: f32 = 0.0;
pub const VERB_LINE: f32 = 1.0;
pub const VERB_QUAD: f32 = 2.0;
pub const VERB_CUBIC: f32 = 3.0;
pub const VERB_CLOSE: f32 = 4.0;

pub const TEXT_BOLD: u32 = 1;
pub const TEXT_ITALIC: u32 = 2;
pub const TEXT_SERIF: u32 = 4;
pub const TEXT_MONO: u32 = 8;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct LpStop {
    pub offset: f32,
    /// 0xRRGGBBAA, straight alpha.
    pub color: u32,
}

#[repr(C)]
pub struct LpCanvasOp {
    pub kind: u32,
    /// Index into `blend_mode` (canvas globalCompositeOperation order).
    pub composite: u32,
    /// 0 nonzero, 1 evenodd.
    pub fill_rule: u32,
    pub text_flags: u32,
    pub text_align: u32,
    pub text_baseline: u32,
    pub line_cap: u32,
    pub line_join: u32,
    /// Current transform (a b c d e f); only text uses it, paths are already
    /// in device space.
    pub transform: [f32; 6],
    /// 0xRRGGBBAA, straight alpha.
    pub color: u32,
    pub global_alpha: f32,
    pub line_width: f32,
    pub miter_limit: f32,
    /// Text: x, y, maxWidth (0 = none), font px. Image: dx, dy.
    pub rect: [f32; 4],
    pub path: *const f32,
    pub path_len: usize,
    pub text: *const u8,
    pub text_len: usize,
    /// 0 solid, 1 linear (x0 y0 x1 y1), 2 radial (x0 y0 r0 x1 y1 r1).
    pub grad_kind: u32,
    pub grad: [f32; 6],
    pub stops: *const LpStop,
    pub stops_len: usize,
    /// RGBA straight-alpha pixels for OP_PUT_IMAGE.
    pub image: *const u8,
    pub image_w: u32,
    pub image_h: u32,
}

fn blend_mode(i: u32) -> BlendMode {
    match i {
        0 => BlendMode::SourceOver,
        1 => BlendMode::SourceIn,
        2 => BlendMode::SourceOut,
        3 => BlendMode::SourceAtop,
        4 => BlendMode::DestinationOver,
        5 => BlendMode::DestinationIn,
        6 => BlendMode::DestinationOut,
        7 => BlendMode::DestinationAtop,
        8 => BlendMode::Plus, // lighter
        9 => BlendMode::Source, // copy
        10 => BlendMode::Xor,
        11 => BlendMode::Multiply,
        12 => BlendMode::Screen,
        13 => BlendMode::Overlay,
        14 => BlendMode::Darken,
        15 => BlendMode::Lighten,
        16 => BlendMode::ColorDodge,
        17 => BlendMode::ColorBurn,
        18 => BlendMode::HardLight,
        19 => BlendMode::SoftLight,
        20 => BlendMode::Difference,
        21 => BlendMode::Exclusion,
        22 => BlendMode::Hue,
        23 => BlendMode::Saturation,
        24 => BlendMode::Color,
        25 => BlendMode::Luminosity,
        _ => BlendMode::SourceOver,
    }
}

fn color_of(c: u32, global_alpha: f32) -> Color {
    let a = ((c & 0xff) as f32 / 255.0) * global_alpha.clamp(0.0, 1.0);
    Color::from_rgba(
        ((c >> 24) & 0xff) as f32 / 255.0,
        ((c >> 16) & 0xff) as f32 / 255.0,
        ((c >> 8) & 0xff) as f32 / 255.0,
        a,
    )
    .unwrap_or(Color::BLACK)
}

unsafe fn slice<'a, T>(p: *const T, len: usize) -> &'a [T] {
    if p.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(p, len)
    }
}

unsafe fn paint_for(op: &LpCanvasOp) -> Paint<'static> {
    let mut paint = Paint::default();
    paint.anti_alias = true;
    paint.blend_mode = blend_mode(op.composite);
    let stops: Vec<GradientStop> = slice(op.stops, op.stops_len)
        .iter()
        .map(|s| GradientStop::new(s.offset.clamp(0.0, 1.0), color_of(s.color, op.global_alpha)))
        .collect();
    let shader = match op.grad_kind {
        1 if stops.len() >= 2 => LinearGradient::new(
            Point::from_xy(op.grad[0], op.grad[1]),
            Point::from_xy(op.grad[2], op.grad[3]),
            stops.clone(),
            SpreadMode::Pad,
            ts(&op.transform),
        ),
        2 if stops.len() >= 2 => RadialGradient::new(
            Point::from_xy(op.grad[0], op.grad[1]),
            op.grad[2].max(0.0),
            Point::from_xy(op.grad[3], op.grad[4]),
            op.grad[5].max(0.0),
            stops.clone(),
            SpreadMode::Pad,
            ts(&op.transform),
        ),
        _ => None,
    };
    match shader {
        Some(s) => paint.shader = s,
        None => {
            // A gradient with one stop paints that stop; none paints nothing
            // visible (transparent black), like Chrome.
            let c = if op.grad_kind != 0 {
                slice(op.stops, op.stops_len)
                    .first()
                    .map(|s| color_of(s.color, op.global_alpha))
                    .unwrap_or(Color::TRANSPARENT)
            } else {
                color_of(op.color, op.global_alpha)
            };
            paint.shader = Shader::SolidColor(c);
        }
    }
    paint
}

fn ts(t: &[f32; 6]) -> Transform {
    Transform::from_row(t[0], t[1], t[2], t[3], t[4], t[5])
}

unsafe fn build_path(op: &LpCanvasOp) -> Option<Path> {
    let v = slice(op.path, op.path_len);
    let mut pb = PathBuilder::new();
    let mut i = 0;
    while i < v.len() {
        let verb = v[i];
        i += 1;
        let need = match verb as i32 {
            0 | 1 => 2,
            2 => 4,
            3 => 6,
            _ => 0,
        };
        if i + need > v.len() {
            break;
        }
        let a = &v[i..i + need];
        if a.iter().any(|f| !f.is_finite()) {
            i += need;
            continue;
        }
        match verb as i32 {
            0 => pb.move_to(a[0], a[1]),
            1 => pb.line_to(a[0], a[1]),
            2 => pb.quad_to(a[0], a[1], a[2], a[3]),
            3 => pb.cubic_to(a[0], a[1], a[2], a[3], a[4], a[5]),
            4 => pb.close(),
            _ => {}
        }
        i += need;
    }
    pb.finish()
}

fn stroke_of(op: &LpCanvasOp) -> Stroke {
    // Paths are in device space; scale the width by the transform's average
    // scale so a scaled stroke stays as thick as Chrome draws it.
    let t = &op.transform;
    let sx = (t[0] * t[0] + t[1] * t[1]).sqrt();
    let sy = (t[2] * t[2] + t[3] * t[3]).sqrt();
    let s = ((sx + sy) / 2.0).max(1e-3);
    Stroke {
        width: (op.line_width * s).max(0.0),
        miter_limit: op.miter_limit.max(1.0),
        line_cap: match op.line_cap {
            1 => LineCap::Round,
            2 => LineCap::Square,
            _ => LineCap::Butt,
        },
        line_join: match op.line_join {
            1 => LineJoin::Round,
            2 => LineJoin::Bevel,
            _ => LineJoin::Miter,
        },
        dash: None,
    }
}

impl Renderer {
    /// One line of canvas text shaped with the renderer's fonts. Returns the
    /// layout plus its advance width.
    fn canvas_layout(&mut self, text: &str, px: f32, flags: u32) -> (parley::Layout<Rgb>, f32) {
        let family = if flags & TEXT_MONO != 0 {
            "monospace"
        } else if flags & TEXT_SERIF != 0 {
            "serif"
        } else {
            "sans-serif"
        };
        let root = TextStyle {
            font_family: FontFamily::Source(Cow::Borrowed(family)),
            font_size: px.clamp(0.5, 1000.0),
            font_weight: if flags & TEXT_BOLD != 0 { FontWeight::BOLD } else { FontWeight::NORMAL },
            font_style: if flags & TEXT_ITALIC != 0 { FontStyle::Italic } else { FontStyle::Normal },
            brush: Rgb(0, 0, 0),
            ..Default::default()
        };
        let mut builder = self.lcx.tree_builder(&mut self.fcx, 1.0, true, &root);
        builder.push_text(text);
        let (mut layout, _) = builder.build();
        layout.break_all_lines(None);
        let w = layout.width();
        (layout, w)
    }

    /// Advance width of `text`, for measureText (same fonts as fillText).
    pub fn canvas_measure(&mut self, text: &str, px: f32, flags: u32) -> (f32, f32, f32) {
        let (layout, w) = self.canvas_layout(text, px, flags);
        let (mut asc, mut desc) = (px * 0.8, px * 0.2);
        if let Some(line) = layout.lines().next() {
            let m = line.metrics();
            asc = m.ascent;
            desc = m.descent;
        }
        (w, asc, desc)
    }

    unsafe fn canvas_text(&mut self, pixmap: &mut Pixmap, op: &LpCanvasOp, stroke: bool) {
        let bytes = slice(op.text, op.text_len);
        let Ok(text) = std::str::from_utf8(bytes) else { return };
        if text.is_empty() {
            return;
        }
        let px = op.rect[3];
        let (layout, width) = self.canvas_layout(text, px, op.text_flags);
        let Some(line) = layout.lines().next() else { return };
        let m = line.metrics();
        let (asc, desc) = (m.ascent, m.descent);

        // textAlign: 0 start/left, 1 end/right, 2 center.
        let mut x = op.rect[0];
        let max_w = op.rect[2];
        let squeeze = if max_w > 0.0 && width > max_w { max_w / width } else { 1.0 };
        let drawn_w = width * squeeze;
        match op.text_align {
            1 => x -= drawn_w,
            2 => x -= drawn_w / 2.0,
            _ => {}
        }
        // textBaseline: 0 alphabetic, 1 top, 2 hanging, 3 middle, 4 ideographic, 5 bottom.
        let y = op.rect[1]
            + match op.text_baseline {
                1 => asc,
                2 => asc * 0.8,
                3 => (asc - desc) / 2.0,
                4 | 5 => -desc,
                _ => 0.0,
            };
        let line_baseline = m.baseline;

        let paint = paint_for(op);
        let stroke_style = stroke_of(op);
        let ctm = ts(&op.transform);
        for item in line.items() {
            let PositionedLayoutItem::GlyphRun(gr) = item else { continue };
            let run = gr.run();
            let font = run.font();
            let Ok(font_ref) = skrifa::FontRef::from_index(font.data.as_ref(), font.index) else {
                continue;
            };
            let outlines = font_ref.outline_glyphs();
            let upem = font_ref
                .metrics(Size::unscaled(), LocationRef::default())
                .units_per_em as f32;
            if !(upem > 0.0) {
                continue;
            }
            let scale = run.font_size() / upem;
            let font_key = font.data.as_ref().as_ptr() as usize ^ (font.index as usize);
            let mut gx = gr.offset();
            for glyph in gr.glyphs() {
                let px_x = x + (gx + glyph.x) * squeeze;
                let px_y = y + (gr.baseline() - line_baseline) - glyph.y;
                gx += glyph.advance;
                let path = self
                    .glyph_cache
                    .entry((font_key, glyph.id))
                    .or_insert_with(|| {
                        let og = outlines.get(GlyphId::new(glyph.id))?;
                        let mut pen = TinyPen(PathBuilder::new());
                        og.draw(
                            DrawSettings::unhinted(Size::unscaled(), LocationRef::default()),
                            &mut pen,
                        )
                        .ok()?;
                        pen.0.finish()
                    });
                let Some(path) = path else { continue };
                let glyph_t = Transform::from_row(scale * squeeze, 0.0, 0.0, -scale, px_x, px_y);
                let t = ctm.pre_concat(glyph_t);
                if stroke {
                    let mut s = stroke_style.clone();
                    s.width = (op.line_width / scale.max(1e-6)).max(0.0);
                    pixmap.stroke_path(path, &paint, &s, t, None);
                } else {
                    pixmap.fill_path(path, &paint, FillRule::Winding, t, None);
                }
            }
        }
    }
}

unsafe fn put_image(pixmap: &mut Pixmap, op: &LpCanvasOp) {
    let (w, h) = (op.image_w as i64, op.image_h as i64);
    let data = slice(op.image, (w * h * 4) as usize);
    if data.len() != (w * h * 4) as usize {
        return;
    }
    let (pw, ph) = (pixmap.width() as i64, pixmap.height() as i64);
    let (dx, dy) = (op.rect[0].round() as i64, op.rect[1].round() as i64);
    let px = pixmap.pixels_mut();
    for y in 0..h {
        let ty = dy + y;
        if ty < 0 || ty >= ph {
            continue;
        }
        for x in 0..w {
            let tx = dx + x;
            if tx < 0 || tx >= pw {
                continue;
            }
            let s = ((y * w + x) * 4) as usize;
            // putImageData replaces pixels (no compositing); store premultiplied.
            let c = tiny_skia::ColorU8::from_rgba(data[s], data[s + 1], data[s + 2], data[s + 3]);
            px[(ty * pw + tx) as usize] = c.premultiply();
        }
    }
}

/// Replays `ops` onto a `w` x `h` transparent canvas and writes straight-alpha
/// RGBA into `out` (w*h*4 bytes). Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn lp_canvas_render(
    r: *mut Renderer,
    w: u32,
    h: u32,
    ops: *const LpCanvasOp,
    ops_len: usize,
    out: *mut u8,
) -> i32 {
    let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if w == 0 || h == 0 || w > 16384 || h > 16384 || out.is_null() {
            return 1;
        }
        let Some(mut pixmap) = Pixmap::new(w, h) else { return 1 };
        for op in slice(ops, ops_len) {
            match op.kind {
                OP_FILL_PATH => {
                    if let Some(path) = build_path(op) {
                        let rule = if op.fill_rule == 1 { FillRule::EvenOdd } else { FillRule::Winding };
                        pixmap.fill_path(&path, &paint_for(op), rule, Transform::identity(), None);
                    }
                }
                OP_STROKE_PATH => {
                    if let Some(path) = build_path(op) {
                        pixmap.stroke_path(&path, &paint_for(op), &stroke_of(op), Transform::identity(), None);
                    }
                }
                OP_CLEAR_PATH => {
                    if let Some(path) = build_path(op) {
                        let mut paint = Paint::default();
                        paint.blend_mode = BlendMode::Clear;
                        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
                    }
                }
                OP_FILL_TEXT | OP_STROKE_TEXT => {
                    if !r.is_null() {
                        (*r).canvas_text(&mut pixmap, op, op.kind == OP_STROKE_TEXT);
                    }
                }
                OP_PUT_IMAGE => put_image(&mut pixmap, op),
                OP_DRAW_IMAGE => draw_image(&mut pixmap, op),
                _ => {}
            }
        }
        let dst = std::slice::from_raw_parts_mut(out, (w * h * 4) as usize);
        for (i, p) in pixmap.pixels().iter().enumerate() {
            let c = p.demultiply();
            dst[i * 4] = c.red();
            dst[i * 4 + 1] = c.green();
            dst[i * 4 + 2] = c.blue();
            dst[i * 4 + 3] = c.alpha();
        }
        0
    }));
    caught.unwrap_or(2)
}

/// measureText with the same fonts fillText draws with. Writes width, font
/// ascent and descent (positive, CSS px). Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn lp_canvas_measure(
    r: *mut Renderer,
    text: *const u8,
    text_len: usize,
    px: f32,
    flags: u32,
    out: *mut f32,
) -> i32 {
    let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if r.is_null() || out.is_null() {
            return 1;
        }
        let Ok(s) = std::str::from_utf8(slice(text, text_len)) else { return 1 };
        let (w, a, d) = (*r).canvas_measure(s, px, flags);
        *out = w;
        *out.add(1) = a;
        *out.add(2) = d;
        0
    }));
    caught.unwrap_or(2)
}

/// Encodes straight-alpha RGBA as an 8-bit RGBA PNG, streamed to `write`.
#[no_mangle]
pub unsafe extern "C" fn lp_png_encode_rgba(
    w: u32,
    h: u32,
    rgba: *const u8,
    ctx: *mut c_void,
    write: LpWriteFn,
) -> i32 {
    let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if w == 0 || h == 0 || rgba.is_null() {
            return 1;
        }
        let data = slice(rgba, (w * h * 4) as usize);
        let mut sink = Sink { ctx, write, failed: false };
        let mut enc = png::Encoder::new(&mut sink, w, h);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        let Ok(mut writer) = enc.write_header() else { return 3 };
        if writer.write_image_data(data).is_err() {
            return 3;
        }
        if writer.finish().is_err() || sink.failed {
            return 3;
        }
        0
    }));
    caught.unwrap_or(2)
}

/// drawImage: `op.image` (straight RGBA, already cropped to the source rect)
/// scaled into rect = (dx, dy, dw, dh) under the current transform, with
/// globalAlpha and the composite mode.
unsafe fn draw_image(pixmap: &mut Pixmap, op: &LpCanvasOp) {
    let (w, h) = (op.image_w, op.image_h);
    if w == 0 || h == 0 {
        return;
    }
    let data = slice(op.image, (w as usize) * (h as usize) * 4);
    if data.len() != (w as usize) * (h as usize) * 4 {
        return;
    }
    let Some(mut src) = Pixmap::new(w, h) else { return };
    for (i, px) in src.pixels_mut().iter_mut().enumerate() {
        let c = tiny_skia::ColorU8::from_rgba(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]);
        *px = c.premultiply();
    }
    let (dx, dy, dw, dh) = (op.rect[0], op.rect[1], op.rect[2], op.rect[3]);
    if !(dw.is_finite() && dh.is_finite()) || dw == 0.0 || dh == 0.0 {
        return;
    }
    let local = Transform::from_row(dw / w as f32, 0.0, 0.0, dh / h as f32, dx, dy);
    let t = ts(&op.transform).pre_concat(local);
    let paint = tiny_skia::PixmapPaint {
        opacity: op.global_alpha.clamp(0.0, 1.0),
        blend_mode: blend_mode(op.composite),
        quality: tiny_skia::FilterQuality::Bilinear,
    };
    pixmap.draw_pixmap(0, 0, src.as_ref(), &paint, t, None);
}

/// Decodes a PNG into straight RGBA. With `out` null (or too small) only the
/// size is written and 1 is returned; call again with a w*h*4 buffer.
/// Returns 0 on success, 2 on a decode error.
#[no_mangle]
pub unsafe extern "C" fn lp_png_decode_rgba(
    data: *const u8,
    len: usize,
    w_out: *mut u32,
    h_out: *mut u32,
    out: *mut u8,
    out_cap: usize,
) -> i32 {
    let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let bytes = slice(data, len);
        let mut dec = png::Decoder::new(std::io::Cursor::new(bytes));
        dec.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
        let Ok(mut reader) = dec.read_info() else { return 2 };
        let (w, h) = (reader.info().width, reader.info().height);
        if w == 0 || h == 0 || w > 16384 || h > 16384 {
            return 2;
        }
        *w_out = w;
        *h_out = h;
        let need = (w as usize) * (h as usize) * 4;
        if out.is_null() || out_cap < need {
            return 1;
        }
        let Some(size) = reader.output_buffer_size() else { return 2 };
        let mut buf = vec![0u8; size];
        let Ok(frame) = reader.next_frame(&mut buf) else { return 2 };
        let dst = std::slice::from_raw_parts_mut(out, need);
        let src = &buf[..frame.buffer_size()];
        let px = (w as usize) * (h as usize);
        match frame.color_type {
            png::ColorType::Rgba => dst.copy_from_slice(&src[..need]),
            png::ColorType::Rgb => {
                for i in 0..px {
                    dst[i * 4..i * 4 + 3].copy_from_slice(&src[i * 3..i * 3 + 3]);
                    dst[i * 4 + 3] = 255;
                }
            }
            png::ColorType::GrayscaleAlpha => {
                for i in 0..px {
                    let g = src[i * 2];
                    dst[i * 4] = g;
                    dst[i * 4 + 1] = g;
                    dst[i * 4 + 2] = g;
                    dst[i * 4 + 3] = src[i * 2 + 1];
                }
            }
            png::ColorType::Grayscale => {
                for i in 0..px {
                    let g = src[i];
                    dst[i * 4] = g;
                    dst[i * 4 + 1] = g;
                    dst[i * 4 + 2] = g;
                    dst[i * 4 + 3] = 255;
                }
            }
            _ => return 2,
        }
        0
    }));
    caught.unwrap_or(2)
}
