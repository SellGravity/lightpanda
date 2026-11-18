// SellGravity antidetect: evaluated in every frame before page scripts, as
// (function (makeNative, persona) {...}). `makeNative(name, length, impl)`
// returns a genuine V8 native function (native-code toString, no prototype,
// throws on `new`) forwarding to `impl`, so nothing here looks patched.
(function (makeNative, persona) {
  // Runs in windows and in workers (WorkerNavigator there).
  const N = typeof Navigator !== 'undefined' ? Navigator.prototype : null;
  if (N) {
    delete N.globalPrivacyControl;
    delete N.modelContext;
    // Chrome for Android has no desktop-only hardware / window APIs.
    if (navigator.userAgentData && navigator.userAgentData.mobile) {
      for (const k of ['hid', 'serial', 'keyboard', 'windowControlsOverlay', 'ink', 'managed', 'getInstalledRelatedApps', 'setAppBadge', 'clearAppBadge']) delete N[k];
    } else if (((persona && persona.chromeMajor) || 999) < 132) {
      // Device Posture API: Chrome 132+.
      delete N.devicePosture;
    }
    // Retired with the Privacy Sandbox ad APIs; absent from current Chrome.
    delete N.protectedAudience;
    if (typeof window !== 'undefined') {
      // for..in navigator walks Navigator.prototype in creation order, which
      // in Chrome is its IDL order; pixelscan hashes that list and compares it
      // with real builds. Re-create the members in Chrome's order.
      const order = ['maxTouchPoints', 'scheduling', 'userActivation', 'geolocation', 'ink', 'doNotTrack', 'mediaCapabilities', 'permissions',
        'webkitTemporaryStorage', 'webkitPersistentStorage', 'windowControlsOverlay', 'hardwareConcurrency', 'cookieEnabled', 'appCodeName',
        'appName', 'appVersion', 'platform', 'product', 'productSub', 'userAgent', 'vendor', 'vendorSub', 'language', 'languages', 'onLine',
        'webdriver', 'plugins', 'mimeTypes', 'pdfViewerEnabled', 'connection', 'getGamepads', 'javaEnabled', 'sendBeacon', 'vibrate',
        'mediaSession', 'cpuPerformance', 'bluetooth', 'clipboard', 'credentials', 'keyboard', 'managed', 'mediaDevices', 'serviceWorker',
        'virtualKeyboard', 'wakeLock', 'deviceMemory', 'userAgentData', 'locks', 'storage', 'gpu', 'login', 'devicePosture', 'hid',
        'presentation', 'serial', 'usb', 'xr', 'storageBuckets', 'canShare', 'share', 'clearAppBadge', 'getBattery', 'getUserMedia',
        'requestMIDIAccess', 'requestMediaKeySystemAccess', 'setAppBadge', 'webkitGetUserMedia', 'getInstalledRelatedApps',
        'registerProtocolHandler', 'unregisterProtocolHandler'];
      for (const k of order) {
        const d = Object.getOwnPropertyDescriptor(N, k);
        if (!d || !d.configurable) continue;
        delete N[k];
        Object.defineProperty(N, k, d);
      }
    }
  }

  // JS builtins newer than the persona's Chrome: Lightpanda's V8 is ahead of
  // most Chrome releases, and version detectors (CreepJS-style "jsVersion")
  // map each builtin to the Chrome that shipped it. [owner, key, first Chrome]
  const major = (persona && persona.chromeMajor) || 0;
  if (major > 0) {
    const gates = [
      ['Math', 'sumPrecise', 143],
      ['Iterator', 'concat', 145],
      ['Iterator', 'zip', 999], ['Iterator', 'zipKeyed', 999],
      ['Iterator.prototype', 'join', 999], ['Iterator.prototype', 'includes', 999],
      ['Map.prototype', 'getOrInsert', 145], ['Map.prototype', 'getOrInsertComputed', 145],
      ['WeakMap.prototype', 'getOrInsert', 145], ['WeakMap.prototype', 'getOrInsertComputed', 145],
      ['Uint8Array', 'fromBase64', 140], ['Uint8Array', 'fromHex', 140],
      ['Uint8Array.prototype', 'toBase64', 140], ['Uint8Array.prototype', 'toHex', 140],
      ['Uint8Array.prototype', 'setFromBase64', 140], ['Uint8Array.prototype', 'setFromHex', 140],
      ['RegExp', 'escape', 136], ['Math', 'f16round', 135], ['Error', 'isError', 134],
      ['Atomics', 'pause', 133], ['Promise', 'try', 128],
    ];
    const resolve = (path) => path.split('.').reduce((o, k) => (o == null ? o : o[k]), self);
    for (const [owner, key, since] of gates) {
      if (major >= since) continue;
      const o = resolve(owner);
      if (o && Object.prototype.hasOwnProperty.call(o, key)) {
        try { delete o[key]; } catch (e) { /* non-configurable */ }
      }
    }
    for (const [g, since] of [['Float16Array', 135], ['DisposableStack', 134], ['AsyncDisposableStack', 134], ['SuppressedError', 134]]) {
      if (major < since && g in self) { try { delete self[g]; } catch (e) { /* keep */ } }
    }
  }

  // Intl reports the persona's IANA id exactly. V8's bundled ICU canonicalizes
  // to legacy ids (Asia/Ho_Chi_Minh -> Asia/Saigon), which then mismatches the
  // IP time zone scanners compare against.
  const want = persona && persona.timezone;
  if (want) {
    const DTF = Intl.DateTimeFormat;
    const proto = DTF.prototype;
    const orig = proto.resolvedOptions;
    let alias = null;
    try { alias = new DTF('en', { timeZone: want }).resolvedOptions().timeZone; } catch (e) { alias = null; }
    if (alias && alias !== want) {
      const fixed = makeNative('resolvedOptions', 0, function () {
        const o = orig.call(this);
        if (o.timeZone === alias) o.timeZone = want;
        return o;
      });
      Object.defineProperty(proto, 'resolvedOptions', { value: fixed, writable: true, configurable: true, enumerable: false });
    }
  }


  // WebGL: Chrome's method set and arities, plus a small software rasterizer
  // (flat-colour triangles, clear, viewport, readPixels). Lightpanda's WebGL
  // methods are no-ops of length 0; scanners hash a drawn red box through
  // readPixels (pixelscan) and lie detectors compare Function.length.
  if (typeof WebGLRenderingContext !== 'undefined') webgl(makeNative);
  function webgl(makeNative) {
    const P = WebGLRenderingContext.prototype;
    const lengths = 'activeTexture:1 attachShader:2 bindAttribLocation:3 bindRenderbuffer:2 blendColor:4 blendEquation:1 blendEquationSeparate:2 blendFunc:2 blendFuncSeparate:4 bufferData:3 bufferSubData:3 checkFramebufferStatus:1 compileShader:1 compressedTexImage2D:7 compressedTexSubImage2D:8 copyTexImage2D:8 copyTexSubImage2D:8 createBuffer:0 createFramebuffer:0 createProgram:0 createRenderbuffer:0 createShader:1 createTexture:0 cullFace:1 deleteBuffer:1 deleteFramebuffer:1 deleteProgram:1 deleteRenderbuffer:1 deleteShader:1 deleteTexture:1 depthFunc:1 depthMask:1 depthRange:2 detachShader:2 disable:1 enable:1 finish:0 flush:0 framebufferRenderbuffer:4 framebufferTexture2D:5 frontFace:1 generateMipmap:1 getActiveAttrib:2 getActiveUniform:2 getAttachedShaders:1 getAttribLocation:2 getBufferParameter:2 getContextAttributes:0 getError:0 getExtension:1 getFramebufferAttachmentParameter:3 getParameter:1 getProgramInfoLog:1 getProgramParameter:2 getRenderbufferParameter:2 getShaderInfoLog:1 getShaderParameter:2 getShaderPrecisionFormat:2 getShaderSource:1 getSupportedExtensions:0 getTexParameter:2 getUniform:2 getUniformLocation:2 getVertexAttrib:2 getVertexAttribOffset:2 hint:2 isBuffer:1 isContextLost:0 isEnabled:1 isFramebuffer:1 isProgram:1 isRenderbuffer:1 isShader:1 isTexture:1 lineWidth:1 linkProgram:1 pixelStorei:2 polygonOffset:2 readPixels:7 renderbufferStorage:4 sampleCoverage:2 shaderSource:2 stencilFunc:3 stencilFuncSeparate:4 stencilMask:1 stencilMaskSeparate:2 stencilOp:3 stencilOpSeparate:4 texImage2D:6 texParameterf:3 texParameteri:3 texSubImage2D:7 useProgram:1 validateProgram:1 bindBuffer:2 bindFramebuffer:2 bindTexture:2 clear:1 clearColor:4 clearDepth:1 clearStencil:1 colorMask:4 disableVertexAttribArray:1 drawArrays:3 drawElements:4 enableVertexAttribArray:1 scissor:4 uniform1f:2 uniform1fv:2 uniform1i:2 uniform1iv:2 uniform2f:3 uniform2fv:2 uniform2i:3 uniform2iv:2 uniform3f:4 uniform3fv:2 uniform3i:4 uniform3iv:2 uniform4f:5 uniform4fv:2 uniform4i:5 uniform4iv:2 uniformMatrix2fv:3 uniformMatrix3fv:3 uniformMatrix4fv:3 vertexAttrib1f:2 vertexAttrib1fv:2 vertexAttrib2f:3 vertexAttrib2fv:2 vertexAttrib3f:4 vertexAttrib3fv:2 vertexAttrib4f:5 vertexAttrib4fv:2 vertexAttribPointer:6 viewport:4 drawingBufferStorage:3 constructor:0 makeXRCompatible:0 texElementSubImage2D:5';
    const st = new WeakMap();
    const S = (gl) => {
      let o = st.get(gl);
      if (!o) {
        o = { clear: [0, 0, 0, 0], vp: null, buf: new WeakMap(), bound: {}, src: new WeakMap(), progShaders: new WeakMap(), prog: null,
          attrs: [], locs: new Map(), uniforms: new Map(), uloc: new WeakMap(), fb: null, w: 0, h: 0 };
        st.set(gl, o);
      }
      const w = gl.drawingBufferWidth | 0, h = gl.drawingBufferHeight | 0;
      if (!o.fb || o.w !== w || o.h !== h) { o.fb = new Uint8Array(Math.max(0, w * h * 4)); o.w = w; o.h = h; }
      if (!o.vp) o.vp = [0, 0, w, h];
      return o;
    };
    const orig = {};
    const wrap = (k, len, impl) => {
      const d = Object.getOwnPropertyDescriptor(P, k);
      orig[k] = d && typeof d.value === 'function' ? d.value : null;
      Object.defineProperty(P, k, { value: makeNative(k, len, impl), writable: true, enumerable: true, configurable: true });
    };
    const call = (k, self, args) => (orig[k] ? orig[k].apply(self, args) : undefined);
    const clamp8 = (v) => Math.round(Math.max(0, Math.min(1, +v || 0)) * 255);
    // Fragment colour: a literal vec4, or a vec4 uniform set via uniform4f(v).
    const fragColor = (o) => {
      const shaders = (o.prog && o.progShaders.get(o.prog)) || [];
      for (const sh of shaders) {
        const src = o.src.get(sh) || '';
        const m = /gl_FragColor\s*=\s*vec4\s*\(([^;]*)\)\s*;/.exec(src);
        if (!m) continue;
        const parts = m[1].split(',').map((x) => x.trim());
        if (parts.length === 4 && parts.every((x) => /^[-+]?[0-9.]+$/.test(x))) return parts.map(clamp8);
        if (parts.length === 1 && o.uniforms.has(parts[0])) return o.uniforms.get(parts[0]).map(clamp8);
      }
      return [255, 255, 255, 255];
    };
    const vertex = (o, i) => {
      const a = o.attrs.find((x) => x && x.enabled && x.data);
      if (!a) return null;
      const size = a.size || 2;
      const stride = a.stride ? a.stride / 4 : size;
      const base = (a.offset || 0) / 4 + i * stride;
      return [a.data[base] || 0, a.data[base + 1] || 0];
    };
    const raster = (o, tri, color) => {
      const [vx, vy, vw, vh] = o.vp;
      const pts = tri.map(([x, y]) => [(x + 1) / 2 * vw + vx, (y + 1) / 2 * vh + vy]);
      const area = (pts[1][0] - pts[0][0]) * (pts[2][1] - pts[0][1]) - (pts[2][0] - pts[0][0]) * (pts[1][1] - pts[0][1]);
      if (area === 0) return;
      const minX = Math.max(0, Math.floor(Math.min(pts[0][0], pts[1][0], pts[2][0])));
      const maxX = Math.min(o.w - 1, Math.ceil(Math.max(pts[0][0], pts[1][0], pts[2][0])));
      const minY = Math.max(0, Math.floor(Math.min(pts[0][1], pts[1][1], pts[2][1])));
      const maxY = Math.min(o.h - 1, Math.ceil(Math.max(pts[0][1], pts[1][1], pts[2][1])));
      const edge = (a, b, x, y) => (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]);
      const sgn = area > 0 ? 1 : -1;
      for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
          const cx = x + 0.5, cy = y + 0.5;
          const e0 = edge(pts[1], pts[2], cx, cy) * sgn, e1 = edge(pts[2], pts[0], cx, cy) * sgn, e2 = edge(pts[0], pts[1], cx, cy) * sgn;
          if (e0 >= 0 && e1 >= 0 && e2 >= 0 && !(e0 === 0 && e1 === 0)) {
            const i = (y * o.w + x) * 4;
            o.fb[i] = color[0]; o.fb[i + 1] = color[1]; o.fb[i + 2] = color[2]; o.fb[i + 3] = color[3];
          }
        }
      }
    };
    const draw = (o, mode, indices) => {
      const color = fragColor(o);
      const v = indices.map((i) => vertex(o, i));
      if (v.some((x) => !x)) return;
      if (mode === 4) for (let i = 0; i + 2 < v.length; i += 3) raster(o, [v[i], v[i + 1], v[i + 2]], color);
      else if (mode === 5) for (let i = 0; i + 2 < v.length; i++) raster(o, [v[i], v[i + 1], v[i + 2]], color);
      else if (mode === 6) for (let i = 1; i + 1 < v.length; i++) raster(o, [v[0], v[i], v[i + 1]], color);
    };

    wrap('bindBuffer', 2, function (target, b) { S(this).bound[target] = b; return call('bindBuffer', this, arguments); });
    wrap('bufferData', 3, function (target, data) {
      const o = S(this); const b = o.bound[target];
      if (b && data && typeof data === 'object' && 'length' in data) o.buf.set(b, data.slice ? data.slice() : data);
      return call('bufferData', this, arguments);
    });
    wrap('shaderSource', 2, function (sh, src) { S(this).src.set(sh, String(src)); return call('shaderSource', this, arguments); });
    wrap('getShaderSource', 1, function (sh) { const v = S(this).src.get(sh); return v === undefined ? null : v; });
    wrap('attachShader', 2, function (prog, sh) {
      const o = S(this); const list = o.progShaders.get(prog) || []; list.push(sh); o.progShaders.set(prog, list);
      return call('attachShader', this, arguments);
    });
    wrap('useProgram', 1, function (prog) { S(this).prog = prog; return call('useProgram', this, arguments); });
    wrap('getAttribLocation', 2, function (prog, name) {
      const o = S(this); const key = String(name);
      if (!o.locs.has(key)) o.locs.set(key, o.locs.size);
      return o.locs.get(key);
    });
    wrap('vertexAttribPointer', 6, function (idx, size, type, norm, stride, offset) {
      const o = S(this); const a = o.attrs[idx] || (o.attrs[idx] = {});
      const b = o.bound[0x8892];
      a.data = b ? o.buf.get(b) : null; a.size = size; a.stride = stride; a.offset = offset;
      return call('vertexAttribPointer', this, arguments);
    });
    wrap('enableVertexAttribArray', 1, function (idx) { const o = S(this); (o.attrs[idx] || (o.attrs[idx] = {})).enabled = true; return call('enableVertexAttribArray', this, arguments); });
    wrap('disableVertexAttribArray', 1, function (idx) { const o = S(this); if (o.attrs[idx]) o.attrs[idx].enabled = false; return call('disableVertexAttribArray', this, arguments); });
    wrap('clearColor', 4, function (r, g, b, a) { S(this).clear = [r, g, b, a].map(clamp8); return call('clearColor', this, arguments); });
    wrap('viewport', 4, function (x, y, w, h) { S(this).vp = [x | 0, y | 0, w | 0, h | 0]; return call('viewport', this, arguments); });
    wrap('clear', 1, function (mask) {
      const o = S(this);
      if (mask & 0x4000) for (let i = 0; i < o.fb.length; i += 4) { o.fb[i] = o.clear[0]; o.fb[i + 1] = o.clear[1]; o.fb[i + 2] = o.clear[2]; o.fb[i + 3] = o.clear[3]; }
      return call('clear', this, arguments);
    });
    wrap('getUniformLocation', 2, function (prog, name) {
      const loc = call('getUniformLocation', this, arguments);
      if (loc && typeof loc === 'object') S(this).uloc.set(loc, String(name));
      return loc;
    });
    for (const k of ['uniform4f', 'uniform4fv']) {
      wrap(k, k === 'uniform4f' ? 5 : 2, function (loc, a, b, c, d) {
        const o = S(this); const name = loc && typeof loc === 'object' ? o.uloc.get(loc) : null;
        if (name) o.uniforms.set(name, k === 'uniform4f' ? [a, b, c, d] : Array.from(a || []).slice(0, 4));
        return call(k, this, arguments);
      });
    }
    wrap('drawArrays', 3, function (mode, first, count) {
      const o = S(this); const idx = []; for (let i = 0; i < count; i++) idx.push(first + i);
      draw(o, mode, idx); return call('drawArrays', this, arguments);
    });
    wrap('drawElements', 4, function (mode, count, type, offset) {
      const o = S(this); const b = o.bound[0x8893]; const data = b && o.buf.get(b);
      if (data) {
        const start = (offset || 0) / (type === 0x1405 ? 4 : type === 0x1401 ? 1 : 2);
        draw(o, mode, Array.from(data.slice(start, start + count)));
      }
      return call('drawElements', this, arguments);
    });
    wrap('readPixels', 7, function (x, y, w, h, format, type, out) {
      const o = S(this);
      if (out && out.length !== undefined) {
        for (let row = 0; row < h; row++) {
          for (let col = 0; col < w; col++) {
            const sx = x + col, sy = y + row, di = (row * w + col) * 4;
            if (sx < 0 || sy < 0 || sx >= o.w || sy >= o.h) continue;
            const si = (sy * o.w + sx) * 4;
            out[di] = o.fb[si]; out[di + 1] = o.fb[si + 1]; out[di + 2] = o.fb[si + 2]; out[di + 3] = o.fb[si + 3];
          }
        }
      }
    });

    // Chrome's arity for every method; the ones Lightpanda lacks become
    // inert natives.
    for (const pair of lengths.split(' ')) {
      const [k, n] = pair.split(':');
      const d = Object.getOwnPropertyDescriptor(P, k);
      if (d && typeof d.value === 'function') {
        if (d.value.length !== +n) { try { Object.defineProperty(d.value, 'length', { value: +n }); } catch (e) { /* keep */ } }
      } else if (!d) {
        Object.defineProperty(P, k, {
          value: makeNative(k, +n, function () { return k.startsWith('is') ? false : k.startsWith('get') ? null : undefined; }),
          writable: true, enumerable: true, configurable: true,
        });
      }
    }
  }

  if (typeof window === 'undefined') return;

  // getContext('webgl2') hands out the same native context class with WebGL2
  // answers; expose the constructor so `instanceof` checks hold.
  if (typeof WebGL2RenderingContext === 'undefined' && typeof WebGLRenderingContext !== 'undefined') {
    const ctor = makeNative('WebGL2RenderingContext', 0, function () { throw new TypeError('Illegal constructor'); });
    Object.defineProperty(ctor, 'prototype', { value: WebGLRenderingContext.prototype, writable: false, configurable: false, enumerable: false });
    Object.defineProperty(window, 'WebGL2RenderingContext', { value: ctor, writable: true, configurable: true, enumerable: false });
  }

  chromeSurface(makeNative, major);

  if ('chrome' in window) return;
  const t0 = Date.now() / 1000;
  const app = {
    isInstalled: false,
    InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
    RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
    getDetails: makeNative('getDetails', 0, function () { return null; }),
    getIsInstalled: makeNative('getIsInstalled', 0, function () { return false; }),
    installState: makeNative('installState', 1, function () { return 'not_installed'; }),
    runningState: makeNative('runningState', 0, function () { return 'cannot_run'; }),
  };
  const csi = makeNative('', 0, function () {
    return { startE: Math.round(t0 * 1000), onloadT: Math.round(t0 * 1000) + 120, pageT: performance.now(), tran: 15 };
  });
  const loadTimes = makeNative('', 0, function () {
    return {
      requestTime: t0, startLoadTime: t0, commitLoadTime: t0 + 0.05, finishDocumentLoadTime: t0 + 0.12,
      finishLoadTime: t0 + 0.2, firstPaintTime: t0 + 0.13, firstPaintAfterLoadTime: 0, navigationType: 'Other',
      wasFetchedViaSpdy: true, wasNpnNegotiated: true, npnNegotiatedProtocol: 'h2', wasAlternateProtocolAvailable: false,
      connectionInfo: 'h2',
    };
  });
  // In Chrome `chrome` is installed while the global is built, so it sits
  // among the early own properties; defined last it lands in the final 50
  // keys, which is how stealth plugins are spotted (CreepJS
  // hasHighChromeIndex). Re-append the trailing properties after it.
  // Both orders matter: own names (mostly non-enumerable constructors at the
  // end) and enumerable keys.
  const tail = Array.from(new Set([...Object.getOwnPropertyNames(window).slice(-200), ...Object.keys(window).slice(-80)]));
  Object.defineProperty(window, 'chrome', {
    value: { app, csi, loadTimes }, writable: true, enumerable: true, configurable: false,
  });
  for (const k of tail) {
    const d = Object.getOwnPropertyDescriptor(window, k);
    if (!d || !d.configurable) continue;
    try {
      delete window[k];
      Object.defineProperty(window, k, d);
    } catch (e) { /* keep going */ }
  }

  // Chrome's window surface. Version detectors (CreepJS "windowVersion",
  // BrowserScan kernel check) map own window names to the Chrome release that
  // shipped them, and headless detectors count what's missing. Interfaces
  // Lightpanda doesn't implement become genuine-looking interface objects
  // (native, `new` throws "Illegal constructor", right prototype chain);
  // Lightpanda-only globals go. Entries: "Name:Parent:sinceChrome".
  function chromeSurface(makeNative, major) {
    const W = window;
    const v = major || 999;
    const own = (k) => Object.prototype.hasOwnProperty.call(W, k);
    const hidden = (k, value) => Object.defineProperty(W, k, { value, writable: true, enumerable: false, configurable: true });

    // Chrome's style objects are plain CSSStyleDeclarations.
    if (own('CSSStyleProperties') && W.CSSStyleDeclaration) {
      const sp = W.CSSStyleProperties.prototype;
      Object.defineProperty(sp, 'constructor', { value: W.CSSStyleDeclaration, writable: true, enumerable: false, configurable: true });
      Object.defineProperty(sp, Symbol.toStringTag, { value: 'CSSStyleDeclaration', writable: false, enumerable: false, configurable: true });
    }
    for (const k of ['StorageEstimate', 'CSSStyleProperties', 'SVGGenericElement', 'VTTRegion', 'ModelContext', 'ModelContextClient',
      'ToolActivatedEvent', 'ToolCancelEvent', 'ReadableStreamAsyncIterator', 'CrossOriginWindow', 'MemoryInfo', 'DeprecatedStorageQuota']) {
      if (own(k)) { try { delete W[k]; } catch (e) { /* keep */ } }
    }
    if (own('SharedArrayBuffer') && !W.crossOriginIsolated) { try { delete W.SharedArrayBuffer; } catch (e) { /* keep */ } }
    // Chrome inherits these from EventTarget.prototype; they aren't own.
    for (const k of ['addEventListener', 'removeEventListener', 'dispatchEvent']) {
      if (own(k) && typeof EventTarget !== 'undefined' && EventTarget.prototype[k]) { try { delete W[k]; } catch (e) { /* keep */ } }
    }

    const ifaces = (
      'AnimationEffect AnimationTimeline:: DocumentTimeline:AnimationTimeline ScrollTimeline:AnimationTimeline:115 ViewTimeline:ScrollTimeline:115 ' +
      'KeyframeEffect:AnimationEffect CSSAnimation:Animation CSSTransition:Animation FeaturePolicy WindowControlsOverlayGeometryChangeEvent:Event ' +
      'WebGLObject WebGLVertexArrayObject:WebGLObject WebGLTransformFeedback:WebGLObject WebGLSync:WebGLObject WebGLSampler:WebGLObject ' +
      'WebGLQuery:WebGLObject WebGLContextEvent:Event AudioNode:EventTarget AudioScheduledSourceNode:AudioNode WaveShaperNode:AudioNode ' +
      'PerformanceEntry VisibilityStateEntry:PerformanceEntry VirtualKeyboardGeometryChangeEvent:Event ViewTransitionTypeSet::125 ' +
      'ViewTransition::111 VideoPlaybackQuality TrustedTypePolicyFactory TrustedTypePolicy TrustedScriptURL TrustedScript TrustedHTML ' +
      'TransitionEvent:Event TrackEvent:Event TimeRanges TextUpdateEvent:Event:121 TextFormatUpdateEvent:Event:121 TextFormat::121 ' +
      'CharacterBoundsUpdateEvent:Event:121 EditContext:EventTarget:121 TaskAttributionTiming:PerformanceEntry SyncManager ' +
      'Observable::135 Subscriber::135 StyleSheet StylePropertyMapReadOnly StylePropertyMap:StylePropertyMapReadOnly ' +
      'StereoPannerNode:AudioNode SourceBufferList:EventTarget SourceBuffer:EventTarget ScriptProcessorNode:AudioNode ' +
      'SVGUnitTypes SVGStyleElement:SVGElement SVGAnimationElement:SVGElement SVGSetElement:SVGAnimationElement ' +
      'SVGAnimateElement:SVGAnimationElement SVGAnimateMotionElement:SVGAnimationElement SVGAnimateTransformElement:SVGAnimationElement ' +
      'SVGScriptElement:SVGElement SVGRect SVGPoint SVGNumberList SVGMatrix SVGMPathElement:SVGElement SVGLengthList SVGFilterElement:SVGElement ' +
      'SVGComponentTransferFunctionElement:SVGElement SVGFEFuncRElement:SVGComponentTransferFunctionElement ' +
      'SVGFEFuncGElement:SVGComponentTransferFunctionElement SVGFEFuncBElement:SVGComponentTransferFunctionElement ' +
      'SVGFEFuncAElement:SVGComponentTransferFunctionElement SVGFETurbulenceElement:SVGElement SVGFETileElement:SVGElement ' +
      'SVGFESpotLightElement:SVGElement SVGFESpecularLightingElement:SVGElement SVGFEPointLightElement:SVGElement SVGFEOffsetElement:SVGElement ' +
      'SVGFEMorphologyElement:SVGElement SVGFEMergeNodeElement:SVGElement SVGFEMergeElement:SVGElement SVGFEImageElement:SVGElement ' +
      'SVGFEGaussianBlurElement:SVGElement SVGFEFloodElement:SVGElement SVGFEDropShadowElement:SVGElement SVGFEDistantLightElement:SVGElement ' +
      'SVGFEDisplacementMapElement:SVGElement SVGFEDiffuseLightingElement:SVGElement SVGFEConvolveMatrixElement:SVGElement ' +
      'SVGFECompositeElement:SVGElement SVGFEComponentTransferElement:SVGElement SVGFEColorMatrixElement:SVGElement SVGFEBlendElement:SVGElement ' +
      'SVGAnimatedRect SVGAnimatedNumberList SVGAnimatedLengthList SVGAnimatedInteger SVGAnimatedBoolean SVGAnimatedAngle ' +
      'ReportingObserver ReportBody CSPViolationReportBody:ReportBody IntegrityViolationReportBody:ReportBody:138 ' +
      'ReadableStreamBYOBRequest ReadableStreamBYOBReader ReadableByteStreamController ' +
      'RTCTrackEvent:Event RTCStatsReport RTCSctpTransport:EventTarget RTCRtpTransceiver RTCRtpSender RTCRtpReceiver ' +
      'RTCPeerConnectionIceEvent:Event RTCPeerConnectionIceErrorEvent:Event RTCIceTransport:EventTarget RTCIceCandidate RTCErrorEvent:Event ' +
      'RTCError:DOMException RTCEncodedVideoFrame RTCEncodedAudioFrame RTCDtlsTransport:EventTarget RTCDataChannelEvent:Event ' +
      'RTCDTMFToneChangeEvent:Event RTCDTMFSender:EventTarget RTCCertificate RTCRtpScriptTransform ' +
      'PictureInPictureWindow:EventTarget PictureInPictureEvent:Event PerformanceServerTiming PerformancePaintTiming:PerformanceEntry ' +
      'PerformanceLongTaskTiming:PerformanceEntry PerformanceEventTiming:PerformanceEntry PerformanceElementTiming:PerformanceEntry ' +
      'LayoutShift:PerformanceEntry LayoutShiftAttribution LargestContentfulPaint:PerformanceEntry ' +
      'PerformanceLongAnimationFrameTiming:PerformanceEntry:123 PerformanceScriptTiming:PerformanceEntry:123 ' +
      'PerformanceTimingConfidence::145 PerformanceSoftNavigation:PerformanceEntry:150 InteractionContentfulPaint:PerformanceEntry:150 ' +
      'PermissionsPolicy::150 PannerNode:AudioNode PageRevealEvent:Event:123 PageSwapEvent:Event:124 OverconstrainedError:DOMException ' +
      'NavigationTransition NavigationPrecommitController::141 MediaStreamTrack:EventTarget MediaStreamTrackVideoStats ' +
      'MediaStreamTrackAudioStats::125 MediaStreamTrackProcessor MediaStreamTrackGenerator:MediaStreamTrack MediaStreamTrackEvent:Event ' +
      'MediaStreamEvent:Event MediaStream:EventTarget MediaStreamAudioSourceNode:AudioNode MediaStreamAudioDestinationNode:AudioNode ' +
      'CanvasCaptureMediaStreamTrack:MediaStreamTrack BrowserCaptureMediaStreamTrack:MediaStreamTrack MediaSourceHandle MediaSource:EventTarget ' +
      'MediaRecorder:EventTarget MediaList MediaEncryptedEvent:Event MediaElementAudioSourceNode:AudioNode MathMLElement:Element ' +
      'InterestEvent:Event:142 InputDeviceInfo:MediaDeviceInfo InputDeviceCapabilities ImageBitmapRenderingContext ImageBitmap ' +
      'IIRFilterNode:AudioNode HighlightRegistry Highlight HTMLSelectedContentElement:HTMLElement:135 HTMLMenuElement:HTMLElement ' +
      'GamepadHapticActuator GamepadButton Gamepad FontFaceSetLoadEvent:Event External DelegatedInkTrailPresenter DelayNode:AudioNode ' +
      'DOMRectList DOMQuad DOMError ContentVisibilityAutoStateChangeEvent:Event CommandEvent:Event:135 CloseWatcher:EventTarget:126 ' +
      'CaretPosition::128 ChannelSplitterNode:AudioNode ChannelMergerNode:AudioNode ' +
      'CSSGroupingRule:CSSRule CSSConditionRule:CSSGroupingRule CSSMediaRule:CSSConditionRule CSSSupportsRule:CSSConditionRule ' +
      'CSSContainerRule:CSSConditionRule CSSViewTransitionRule:CSSRule:126 CSSStartingStyleRule:CSSGroupingRule:119 ' +
      'CSSScopeRule:CSSGroupingRule:118 CSSPropertyRule:CSSRule CSSPositionTryRule:CSSRule:125 ' +
      'CSSPositionTryDescriptors:CSSStyleDeclaration:125 CSSPageRule:CSSGroupingRule CSSNestedDeclarations:CSSRule:130 ' +
      'CSSNamespaceRule:CSSRule CSSMarginRule:CSSRule:131 CSSLayerStatementRule:CSSRule CSSLayerBlockRule:CSSGroupingRule ' +
      'CSSKeyframesRule:CSSRule CSSKeyframeRule:CSSRule CSSImportRule:CSSRule CSSFontPaletteValuesRule:CSSRule CSSFontFaceRule:CSSRule ' +
      'CSSCounterStyleRule:CSSRule CSSFontFeatureValuesRule:CSSRule CSSFunctionRule:CSSGroupingRule:139 ' +
      'CSSFunctionDeclarations:CSSRule:139 CSSFunctionDescriptors:CSSStyleDeclaration:139 CSSPseudoElement::150 ' +
      'CSSStyleValue CSSVariableReferenceValue CSSUnparsedValue:CSSStyleValue CSSNumericValue:CSSStyleValue CSSUnitValue:CSSNumericValue ' +
      'CSSMathValue:CSSNumericValue CSSMathSum:CSSMathValue CSSMathProduct:CSSMathValue CSSMathNegate:CSSMathValue CSSMathMin:CSSMathValue ' +
      'CSSMathMax:CSSMathValue CSSMathInvert:CSSMathValue CSSMathClamp:CSSMathValue CSSNumericArray CSSKeywordValue:CSSStyleValue ' +
      'CSSImageValue:CSSStyleValue CSSPositionValue:CSSStyleValue CSSTransformValue:CSSStyleValue CSSTransformComponent ' +
      'CSSTranslate:CSSTransformComponent CSSSkewY:CSSTransformComponent CSSSkewX:CSSTransformComponent CSSSkew:CSSTransformComponent ' +
      'CSSScale:CSSTransformComponent CSSRotate:CSSTransformComponent CSSPerspective:CSSTransformComponent ' +
      'CSSMatrixComponent:CSSTransformComponent BlobEvent:Event BiquadFilterNode:AudioNode BeforeInstallPromptEvent:Event BarProp ' +
      'AudioWorkletNode:AudioNode AudioSinkInfo::110 AudioProcessingEvent:Event AudioParamMap AudioListener AnalyserNode:AudioNode ' +
      'Sensor:EventTarget OrientationSensor:Sensor AbsoluteOrientationSensor:OrientationSensor RelativeOrientationSensor:OrientationSensor ' +
      'Accelerometer:Sensor LinearAccelerationSensor:Accelerometer GravitySensor:Accelerometer Gyroscope:Sensor SensorErrorEvent:Event ' +
      'Worklet AudioWorklet:Worklet ClipboardChangeEvent:Event:144 CookieStoreManager CreateMonitor:EventTarget:138 ' +
      'Credential FederatedCredential:Credential PasswordCredential:Credential PublicKeyCredential:Credential IdentityCredential:Credential ' +
      'OTPCredential:Credential DigitalCredential:Credential:141 DeviceMotionEventAcceleration DeviceMotionEventRotationRate ' +
      'GPU GPUAdapter GPUAdapterInfo GPUBindGroup GPUBindGroupLayout GPUBuffer GPUCanvasContext GPUCommandBuffer GPUCommandEncoder ' +
      'GPUCompilationInfo GPUCompilationMessage GPUComputePassEncoder GPUComputePipeline GPUDevice:EventTarget GPUDeviceLostInfo GPUError ' +
      'GPUExternalTexture GPUInternalError:GPUError GPUOutOfMemoryError:GPUError GPUValidationError:GPUError GPUPipelineError:DOMException ' +
      'GPUPipelineLayout GPUQuerySet GPUQueue GPURenderBundle GPURenderBundleEncoder GPURenderPassEncoder GPURenderPipeline GPUSampler ' +
      'GPUShaderModule GPUSupportedFeatures GPUSupportedLimits GPUTexture GPUTextureView GPUUncapturedErrorEvent:Event WGSLLanguageFeatures ' +
      'IdleDetector:EventTarget ImageCapture ImageDecoder ImageTrack ImageTrackList KeyboardLayoutMap MIDIAccess:EventTarget ' +
      'MIDIConnectionEvent:Event MIDIPort:EventTarget MIDIInput:MIDIPort MIDIOutput:MIDIPort MIDIInputMap MIDIOutputMap MIDIMessageEvent:Event ' +
      'MediaKeyMessageEvent:Event MediaKeySession:EventTarget MediaKeyStatusMap MediaKeySystemAccess MediaKeys NavigationPreloadManager ' +
      'ScreenDetailed:Screen ScreenDetails:EventTarget WebTransport WebTransportBidirectionalStream WebTransportDatagramDuplexStream ' +
      'WebTransportError:DOMException XRSpace:EventTarget XRReferenceSpace:XRSpace XRBoundedReferenceSpace:XRReferenceSpace ' +
      'XRJointSpace:XRSpace XRAnchor XRAnchorSet XRDepthInformation XRCPUDepthInformation:XRDepthInformation ' +
      'XRWebGLDepthInformation:XRDepthInformation XRCamera XRFrame XRHand XRHitTestResult XRHitTestSource XRInputSource XRInputSourceArray ' +
      'XRInputSourceEvent:Event XRInputSourcesChangeEvent:Event XRPose XRJointPose:XRPose XRViewerPose:XRPose XRLightEstimate ' +
      'XRLightProbe:EventTarget XRRay XRReferenceSpaceEvent:Event XRRenderState XRRigidTransform XRSession:EventTarget XRSessionEvent:Event ' +
      'XRTransientInputHitTestResult XRTransientInputHitTestSource XRView XRViewport XRLayer:EventTarget XRWebGLLayer:XRLayer XRWebGLBinding ' +
      'XRDOMOverlayState XRSystem:EventTarget XRCompositionLayer:XRLayer:150 XRProjectionLayer:XRCompositionLayer:150 ' +
      'XRCubeLayer:XRCompositionLayer:150 XRCylinderLayer:XRCompositionLayer:150 XREquirectLayer:XRCompositionLayer:150 ' +
      'XRQuadLayer:XRCompositionLayer:150 XRLayerEvent:Event:150 XRSubImage::150 XRWebGLSubImage:XRSubImage:150 XRPlane::150 ' +
      'XRPlaneSet::150 XRVisibilityMaskChangeEvent:Event:150 AudioPlaybackStats::150 AuthenticatorResponse ' +
      'AuthenticatorAssertionResponse:AuthenticatorResponse AuthenticatorAttestationResponse:AuthenticatorResponse ' +
      'BluetoothCharacteristicProperties BluetoothDevice:EventTarget BluetoothRemoteGATTCharacteristic:EventTarget ' +
      'BluetoothRemoteGATTDescriptor BluetoothRemoteGATTServer BluetoothRemoteGATTService:EventTarget BluetoothUUID ' +
      'CanvasPaintEvent:Event:150 ElementGeometryUpdateEvent:Event:150 ElementImage::150 CaptureController:EventTarget ClipboardItem ' +
      'CrashReportContext::150 DocumentPictureInPicture:EventTarget:116 DocumentPictureInPictureEvent:Event:116 EyeDropper ' +
      'FetchLaterResult::135 FileSystemHandle FileSystemDirectoryHandle:FileSystemHandle FileSystemFileHandle:FileSystemHandle ' +
      'FileSystemWritableFileStream:WritableStream FileSystemObserver::150 FontData FragmentDirective HIDConnectionEvent:Event ' +
      'HIDDevice:EventTarget HIDInputReportEvent:Event IdentityCredentialError:DOMException IdentityProvider LanguageDetector::138 ' +
      'LanguageModel::150 Summarizer::138 Translator::138 NotRestoredReasonDetails NotRestoredReasons PaymentAddress PaymentManager ' +
      'PresentationAvailability:EventTarget PresentationConnection:EventTarget PresentationConnectionAvailableEvent:Event ' +
      'PresentationConnectionCloseEvent:Event PresentationConnectionList:EventTarget PresentationReceiver PresentationRequest:EventTarget ' +
      'PressureObserver::125 PressureRecord::125 SerialPort:EventTarget SpeechRecognitionPhrase::150 StorageBucket::122 ' +
      'USBAlternateInterface USBConfiguration USBConnectionEvent:Event USBDevice USBEndpoint USBInTransferResult USBInterface ' +
      'USBIsochronousInTransferPacket USBIsochronousInTransferResult USBIsochronousOutTransferPacket USBIsochronousOutTransferResult ' +
      'USBOutTransferResult WakeLockSentinel:EventTarget XSLTProcessor AnimationTrigger::150 TimelineTrigger::150 ' +
      'TimelineTriggerRange::150 TimelineTriggerRangeList::150 BackgroundFetchManager BackgroundFetchRecord ' +
      'BackgroundFetchRegistration:EventTarget ChapterInformation::124 CropTarget RestrictionTarget::132 Fence FencedFrameConfig ' +
      'HTMLFencedFrameElement:HTMLElement HTMLCameraElement:HTMLElement:150 HTMLMicrophoneElement:HTMLElement:150 ' +
      'HTMLGeolocationElement:HTMLElement:150 HTMLUserMediaElement:HTMLElement:150 LaunchParams MediaMetadata NodeRange::150 ' +
      'OpaqueRange::150 Origin::150 PeriodicSyncManager Profiler:EventTarget PushManager PushSubscription PushSubscriptionOptions ' +
      'RemotePlayback:EventTarget SnapEvent:Event:129 SpeechGrammar SpeechGrammarList SpeechRecognition:EventTarget ' +
      'SpeechRecognitionErrorEvent:Event SpeechRecognitionEvent:Event SpeechSynthesisEvent:Event ' +
      'SpeechSynthesisErrorEvent:SpeechSynthesisEvent TrustedHTMLParserOptions::150 Viewport::138 WebSocketError:DOMException:124 ' +
      'WebSocketStream::124 LaunchQueue CacheStorage StyleMedia'
    ).split(' ');
    const made = [];
    for (const entry of ifaces) {
      const [name, parent, since] = entry.split(':');
      if (!name || own(name) || name in W) continue;
      if (since && v < +since) continue;
      const P = parent ? W[parent] : null;
      const ctor = makeNative(name, 0, function () {}, true);
      const proto = ctor.prototype;
      if (typeof P === 'function' && P.prototype) {
        Object.setPrototypeOf(ctor, P);
        Object.setPrototypeOf(proto, P.prototype);
      }
      Object.defineProperty(proto, Symbol.toStringTag, { value: name, writable: false, enumerable: false, configurable: true });
      Object.defineProperty(ctor, 'prototype', { writable: false, enumerable: false });
      hidden(name, ctor);
      made.push(name);
    }

    // GPU*Usage-style namespaces are plain objects of constants.
    const ns = (name, consts) => {
      if (own(name)) return;
      const o = {};
      for (const [k, val] of Object.entries(consts)) Object.defineProperty(o, k, { value: val, enumerable: true });
      Object.defineProperty(o, Symbol.toStringTag, { value: name, configurable: true });
      hidden(name, o);
    };
    ns('GPUBufferUsage', { MAP_READ: 1, MAP_WRITE: 2, COPY_SRC: 4, COPY_DST: 8, INDEX: 16, VERTEX: 32, UNIFORM: 64, STORAGE: 128, INDIRECT: 256, QUERY_RESOLVE: 512 });
    ns('GPUColorWrite', { RED: 1, GREEN: 2, BLUE: 4, ALPHA: 8, ALL: 15 });
    ns('GPUMapMode', { READ: 1, WRITE: 2 });
    ns('GPUShaderStage', { VERTEX: 1, FRAGMENT: 2, COMPUTE: 4 });
    ns('GPUTextureUsage', { COPY_SRC: 1, COPY_DST: 2, TEXTURE_BINDING: 4, STORAGE_BINDING: 8, RENDER_ATTACHMENT: 16 });

    // Legacy aliases: the same function object under a second name.
    for (const [alias, target] of [['WebKitMutationObserver', 'MutationObserver'], ['WebKitCSSMatrix', 'DOMMatrix'], ['webkitURL', 'URL'],
      ['webkitRTCPeerConnection', 'RTCPeerConnection'], ['webkitMediaStream', 'MediaStream'], ['webkitSpeechGrammar', 'SpeechGrammar'],
      ['webkitSpeechGrammarList', 'SpeechGrammarList'], ['webkitSpeechRecognition', 'SpeechRecognition'],
      ['webkitSpeechRecognitionError', 'SpeechRecognitionErrorEvent'], ['webkitSpeechRecognitionEvent', 'SpeechRecognitionEvent']]) {
      if (!own(alias) && typeof W[target] === 'function') hidden(alias, W[target]);
    }

    // Window attributes and operations Chrome has as own properties.
    const inst = (name) => Object.create(W[name] ? W[name].prototype : Object.prototype);
    const attr = (k, get, set) => {
      if (own(k)) return;
      const d = { get: makeNative('get ' + k, 0, get), enumerable: true, configurable: true };
      d.set = makeNative('set ' + k, 1, set || function () {});
      Object.defineProperty(W, k, d);
    };
    const op = (k, len, impl) => {
      if (own(k)) return;
      Object.defineProperty(W, k, { value: makeNative(k, len, impl), writable: true, enumerable: true, configurable: true });
    };
    if (!own('console') && typeof console !== 'undefined') hidden('console', console);
    if (W.BarProp && !Object.getOwnPropertyDescriptor(W.BarProp.prototype, 'visible')) {
      Object.defineProperty(W.BarProp.prototype, 'visible', { get: makeNative('get visible', 0, function () { return true; }), enumerable: true, configurable: true });
    }
    for (const k of ['locationbar', 'menubar', 'personalbar', 'scrollbars', 'statusbar', 'toolbar']) {
      const bar = inst('BarProp');
      attr(k, function () { return bar; });
    }
    let status = '';
    attr('status', function () { return status; }, function (val) { status = String(val); });
    const external = inst('External');
    if (W.External) {
      for (const m of ['AddSearchProvider', 'IsSearchProviderInstalled']) {
        Object.defineProperty(W.External.prototype, m, { value: makeNative(m, 0, function () { return undefined; }), writable: true, enumerable: true, configurable: true });
      }
    }
    attr('external', function () { return external; });
    attr('clientInformation', function () { return navigator; });
    let offscreen = true;
    attr('offscreenBuffering', function () { return offscreen; }, function (val) { offscreen = val; });
    const styleMedia = inst('StyleMedia');
    if (W.StyleMedia) {
      Object.defineProperty(W.StyleMedia.prototype, 'type', { get: makeNative('get type', 0, function () { return 'screen'; }), enumerable: true, configurable: true });
      Object.defineProperty(W.StyleMedia.prototype, 'matchMedium', { value: makeNative('matchMedium', 0, function (q) { return W.matchMedia(String(q)).matches; }), writable: true, enumerable: true, configurable: true });
    }
    attr('styleMedia', function () { return styleMedia; });
    if (made.includes('StyleMedia')) delete W.StyleMedia;
    const handlers = ['onsearch', 'onappinstalled', 'onbeforeinstallprompt', 'onmousewheel', 'onwebkitanimationend', 'onwebkitanimationiteration',
      'onwebkitanimationstart', 'onwebkittransitionend', 'onbeforexrselect', 'ondevicemotion', 'ondeviceorientation', 'ondeviceorientationabsolute',
      'ongamepadconnected', 'ongamepaddisconnected'];
    if (v >= 129) handlers.push('onscrollsnapchange', 'onscrollsnapchanging');
    for (const k of handlers) {
      let h = null;
      attr(k, function () { return h; }, function (fn) { h = typeof fn === 'function' || (fn && typeof fn === 'object') ? fn : null; });
    }
    attr('crossOriginIsolated', function () { return false; });
    attr('originAgentCluster', function () { return false; });
    attr('credentialless', function () { return false; });
    const trusted = inst('TrustedTypePolicyFactory');
    attr('trustedTypes', function () { return trusted; });
    const caches = inst('CacheStorage');
    attr('caches', function () { return caches; });
    if (v >= 116) { const pip = inst('DocumentPictureInPicture'); attr('documentPictureInPicture', function () { return pip; }); }
    const launchQueue = inst('LaunchQueue');
    attr('launchQueue', function () { return launchQueue; });
    if (v >= 138) { const viewport = inst('Viewport'); attr('viewport', function () { return viewport; }); }
    attr('fence', function () { return null; });

    const noop = function () {};
    for (const k of ['captureEvents', 'releaseEvents', 'print']) op(k, 0, noop);
    for (const k of ['moveBy', 'moveTo', 'resizeBy', 'resizeTo']) op(k, 2, noop);
    op('find', 0, function () { return false; });
    op('webkitRequestAnimationFrame', 1, function (cb) { return W.requestAnimationFrame(cb); });
    op('webkitCancelAnimationFrame', 1, function (id) { return W.cancelAnimationFrame(id); });
    const notAllowed = (what) => function () { return Promise.reject(new DOMException(what, 'NotAllowedError')); };
    op('createImageBitmap', 1, function () { return Promise.reject(new TypeError("Failed to execute 'createImageBitmap' on 'Window': The provided value is not of type '(Blob or HTMLCanvasElement or HTMLImageElement or HTMLVideoElement or ImageBitmap or ImageData or OffscreenCanvas or SVGImageElement or VideoFrame)'.")); });
    op('getScreenDetails', 0, notAllowed('Permission denied.'));
    op('queryLocalFonts', 0, notAllowed('Permission denied.'));
    for (const k of ['showDirectoryPicker', 'showOpenFilePicker', 'showSaveFilePicker']) {
      op(k, 0, function () { return Promise.reject(new DOMException("Failed to execute '" + k + "' on 'Window': Must be handling a user gesture to show a file picker.", 'SecurityError')); });
    }
    if (v >= 135) op('fetchLater', 1, function () { throw new DOMException('fetchLater is not allowed in this context.', 'NotAllowedError'); });
    op('webkitRequestFileSystem', 3, noop);
    op('webkitResolveLocalFileSystemURL', 2, noop);

    // document.featurePolicy: Chrome's allowed-feature list for a top-level
    // document (its own order), minus features newer than the persona.
    if (W.FeaturePolicy && typeof Document !== 'undefined' && !('featurePolicy' in Document.prototype)) {
      const late = { 'local-network-access': 141, 'digital-credentials-get': 141, 'on-device-speech-recognition': 142, 'local-network': 142,
        'loopback-network': 142, 'aria-notify': 145, 'digital-credentials-create': 145, 'media-playback-while-not-visible': 145,
        'language-detector': 138, 'translator': 138, 'summarizer': 138, 'language-model': 138, 'deferred-fetch': 135, 'deferred-fetch-minimal': 135 };
      const all = ('geolocation ch-ua-full-version-list cross-origin-isolated screen-wake-lock on-device-speech-recognition translator ' +
        'publickey-credentials-get ch-ua-arch bluetooth compute-pressure ch-prefers-reduced-transparency deferred-fetch usb ch-save-data ' +
        'publickey-credentials-create deferred-fetch-minimal ch-downlink ch-ua-form-factors otp-credentials payment ch-ua ch-ua-model ch-ect ' +
        'autoplay camera language-detector private-state-token-issuance digital-credentials-get accelerometer ch-ua-platform-version ' +
        'idle-detection language-model speaker-selection interest-cohort ch-viewport-height captured-surface-control local-fonts ' +
        'ch-ua-platform midi ch-ua-full-version xr-spatial-tracking clipboard-read gamepad display-capture keyboard-map aria-notify ' +
        'local-network ch-ua-high-entropy-values ch-width ch-prefers-reduced-motion browsing-topics encrypted-media local-network-access ' +
        'gyroscope serial ch-rtt ch-ua-mobile window-management unload ch-dpr ch-prefers-color-scheme ch-ua-wow64 fullscreen ' +
        'identity-credentials-get private-state-token-redemption hid summarizer ch-ua-bitness digital-credentials-create storage-access ' +
        'sync-xhr ch-device-memory ch-viewport-width picture-in-picture loopback-network magnetometer clipboard-write ' +
        'media-playback-while-not-visible microphone').split(' ').filter((f) => !(late[f] && v < late[f]));
      const FP = W.FeaturePolicy.prototype;
      const method = (k, len, impl) => Object.defineProperty(FP, k, { value: makeNative(k, len, impl), writable: true, enumerable: true, configurable: true });
      method('allowedFeatures', 0, function () { return all.slice(); });
      method('allowsFeature', 1, function (f) { return all.includes(String(f)); });
      method('features', 0, function () { return all.slice(); });
      method('getAllowlistForFeature', 1, function (f) { return all.includes(String(f)) ? [location.origin] : []; });
      const policies = new WeakMap();
      Object.defineProperty(Document.prototype, 'featurePolicy', {
        get: makeNative('get featurePolicy', 0, function () {
          let p = policies.get(this);
          if (!p) { p = Object.create(FP); policies.set(this, p); }
          return p;
        }),
        enumerable: true, configurable: true,
      });
    }
    return made;
  }
})
