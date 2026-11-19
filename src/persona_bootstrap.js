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

  const parityTable = persona && persona.parity;
  // Chrome's window chain: Window.prototype -> WindowProperties (the named
  // properties object) -> EventTarget.prototype. Lightpanda serves named
  // access from the global itself, so only the object is missing.
  if (typeof Window === 'function' && typeof EventTarget === 'function' && Object.getPrototypeOf(Window.prototype) === EventTarget.prototype) {
    const wp = Object.create(EventTarget.prototype);
    Object.defineProperty(wp, Symbol.toStringTag, { value: 'WindowProperties', writable: false, enumerable: false, configurable: true });
    Object.setPrototypeOf(Window.prototype, wp);
  }
  immutableGlobalChain();
  if (typeof window === 'undefined') {
    if (major > 0) {
      webgl2Split();
      deepApis(major, parityTable, parity(major, parityTable));
    }
    insecureContext();
    return;
  }

  webgl2Split();
  chromeSurface(makeNative, major);
  if (major > 0) deepApis(major, parityTable, parity(major, parityTable));
  insecureContext();

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
    // configurable until reorderWindow() has put it in place
    value: { app, csi, loadTimes }, writable: true, enumerable: true, configurable: true,
  });
  for (const k of tail) {
    const d = Object.getOwnPropertyDescriptor(window, k);
    if (!d || !d.configurable) continue;
    try {
      delete window[k];
      Object.defineProperty(window, k, d);
    } catch (e) { /* keep going */ }
  }
  reorderWindow(parityTable);

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

  // ---------------------------------------------------------------------
  // Secure-context-only surface. Chrome exposes these only to https (and
  // loopback) documents; on http they are simply absent.
  // ---------------------------------------------------------------------
  function insecureContext() {
    const G = self;
    if (G.isSecureContext !== false) return;
    const N = typeof Navigator !== 'undefined' ? Navigator.prototype : (typeof WorkerNavigator !== 'undefined' ? WorkerNavigator.prototype : null);
    if (N) {
      for (const k of ['cpuPerformance', 'bluetooth', 'clipboard', 'credentials', 'keyboard', 'managed', 'mediaDevices', 'serviceWorker',
        'virtualKeyboard', 'wakeLock', 'deviceMemory', 'userAgentData', 'locks', 'storage', 'gpu', 'login', 'devicePosture', 'hid',
        'presentation', 'serial', 'usb', 'xr', 'storageBuckets', 'canShare', 'share', 'clearAppBadge', 'getBattery', 'getUserMedia',
        'requestMIDIAccess', 'requestMediaKeySystemAccess', 'setAppBadge', 'webkitGetUserMedia', 'getInstalledRelatedApps',
        'registerProtocolHandler', 'unregisterProtocolHandler']) { try { delete N[k]; } catch (e) { /* keep */ } }
    }
    if (typeof Document !== 'undefined') {
      for (const k of ['onpointerrawupdate', 'browsingTopics', 'hasPrivateToken', 'hasRedemptionRecord']) { try { delete Document.prototype[k]; } catch (e) { /* keep */ } }
    }
    if (G.crypto && typeof Crypto !== 'undefined') {
      try { Object.defineProperty(Crypto.prototype, 'subtle', { get: makeNative('get subtle', 0, function () { return undefined; }), enumerable: true, configurable: true }); } catch (e) { /* keep */ }
    }
    const names = ('cookieStore ondevicemotion ondeviceorientation ondeviceorientationabsolute onpointerrawupdate caches documentPictureInPicture ' +
      'AbsoluteOrientationSensor Accelerometer AudioDecoder AudioEncoder AudioWorklet BatteryManager Cache CacheStorage ClipboardChangeEvent ' +
      'CookieChangeEvent CookieStore CookieStoreManager CreateMonitor Credential CredentialsContainer CryptoKey DeviceMotionEvent ' +
      'DeviceMotionEventAcceleration DeviceMotionEventRotationRate DeviceOrientationEvent FederatedCredential GPU GPUAdapter GPUAdapterInfo ' +
      'GPUBindGroup GPUBindGroupLayout GPUBuffer GPUBufferUsage GPUCanvasContext GPUColorWrite GPUCommandBuffer GPUCommandEncoder ' +
      'GPUCompilationInfo GPUCompilationMessage GPUComputePassEncoder GPUComputePipeline GPUDevice GPUDeviceLostInfo GPUError ' +
      'GPUExternalTexture GPUInternalError GPUMapMode GPUOutOfMemoryError GPUPipelineError GPUPipelineLayout GPUQuerySet GPUQueue ' +
      'GPURenderBundle GPURenderBundleEncoder GPURenderPassEncoder GPURenderPipeline GPUSampler GPUShaderModule GPUShaderStage ' +
      'GPUSupportedFeatures GPUSupportedLimits GPUTexture GPUTextureUsage GPUTextureView GPUUncapturedErrorEvent GPUValidationError ' +
      'GravitySensor Gyroscope IdleDetector ImageCapture ImageDecoder ImageTrack ImageTrackList Keyboard KeyboardLayoutMap ' +
      'LinearAccelerationSensor Lock LockManager MIDIAccess MIDIConnectionEvent MIDIInput MIDIInputMap MIDIMessageEvent MIDIOutput ' +
      'MIDIOutputMap MIDIPort MediaDeviceInfo MediaDevices MediaKeyMessageEvent MediaKeySession MediaKeyStatusMap MediaKeySystemAccess ' +
      'MediaKeys NavigationPreloadManager NavigatorManagedData OrientationSensor PasswordCredential ProtectedAudience ' +
      'RelativeOrientationSensor ScreenDetailed ScreenDetails Sensor SensorErrorEvent ServiceWorkerRegistration StorageManager ' +
      'SubtleCrypto VideoDecoder VideoEncoder VirtualKeyboard WGSLLanguageFeatures WebTransport WebTransportBidirectionalStream ' +
      'WebTransportDatagramDuplexStream WebTransportError Worklet XRDOMOverlayState XRLayer XRWebGLBinding AudioPlaybackStats ' +
      'AuthenticatorAssertionResponse AuthenticatorAttestationResponse AuthenticatorResponse PublicKeyCredential Bluetooth ' +
      'BluetoothCharacteristicProperties BluetoothDevice BluetoothRemoteGATTCharacteristic BluetoothRemoteGATTDescriptor ' +
      'BluetoothRemoteGATTServer BluetoothRemoteGATTService CaptureController Clipboard ClipboardItem ServiceWorker ' +
      'ServiceWorkerContainer DevicePosture DigitalCredential DocumentPictureInPicture EyeDropper FetchLaterResult ' +
      'FileSystemDirectoryHandle FileSystemFileHandle FileSystemHandle FileSystemWritableFileStream FileSystemObserver FontData HID ' +
      'HIDConnectionEvent HIDDevice HIDInputReportEvent IdentityCredential IdentityCredentialError IdentityProvider NavigatorLogin ' +
      'LanguageDetector LanguageModel OTPCredential PaymentAddress PaymentRequest PaymentRequestUpdateEvent PaymentResponse ' +
      'PaymentManager PaymentMethodChangeEvent Presentation PresentationAvailability PresentationConnection ' +
      'PresentationConnectionAvailableEvent PresentationConnectionCloseEvent PresentationConnectionList PresentationReceiver ' +
      'PresentationRequest PressureObserver PressureRecord Serial SerialPort SpeechRecognitionPhrase StorageBucket ' +
      'StorageBucketManager Summarizer Translator USB USBAlternateInterface USBConfiguration USBConnectionEvent USBDevice USBEndpoint ' +
      'USBInTransferResult USBInterface USBIsochronousInTransferPacket USBIsochronousInTransferResult USBIsochronousOutTransferPacket ' +
      'USBIsochronousOutTransferResult USBOutTransferResult WakeLock WakeLockSentinel XRAnchor XRAnchorSet XRBoundedReferenceSpace ' +
      'XRCPUDepthInformation XRCamera XRDepthInformation XRFrame XRHand XRHitTestResult XRHitTestSource XRInputSource ' +
      'XRInputSourceArray XRInputSourceEvent XRInputSourcesChangeEvent XRJointPose XRJointSpace XRLightEstimate XRLightProbe XRPose ' +
      'XRRay XRReferenceSpace XRReferenceSpaceEvent XRRenderState XRRigidTransform XRSession XRSessionEvent XRSpace XRSystem ' +
      'XRTransientInputHitTestResult XRTransientInputHitTestSource XRView XRViewerPose XRViewport XRWebGLDepthInformation ' +
      'XRWebGLLayer XRCompositionLayer XRProjectionLayer XRCubeLayer XRCylinderLayer XREquirectLayer XRLayerEvent XRQuadLayer ' +
      'XRSubImage XRWebGLSubImage XRPlane XRPlaneSet XRVisibilityMaskChangeEvent fetchLater getScreenDetails queryLocalFonts ' +
      'showDirectoryPicker showOpenFilePicker showSaveFilePicker').split(' ');
    for (const k of names) {
      if (Object.prototype.hasOwnProperty.call(G, k)) { try { delete G[k]; } catch (e) { /* keep */ } }
    }
  }

  // ---------------------------------------------------------------------
  // WebGL2RenderingContext is its own interface in Chrome: its prototype
  // does not inherit from WebGLRenderingContext's, and a WebGL 1 context has
  // none of the WebGL 2 members. Lightpanda serves both from one native
  // class; give webgl2 contexts a separate prototype carrying the same
  // natives.
  // ---------------------------------------------------------------------
  function webgl2Split() {
    const G = self;
    const GL1 = G.WebGLRenderingContext;
    if (typeof GL1 !== 'function') return null;
    const existing = G.WebGL2RenderingContext;
    if (existing && existing.prototype && existing.prototype !== GL1.prototype) return existing;
    const ctor = makeNative('WebGL2RenderingContext', 0, function () {}, true);
    const proto = ctor.prototype;
    for (const k of Reflect.ownKeys(GL1.prototype)) {
      if (k === 'constructor') continue;
      Object.defineProperty(proto, k, Object.getOwnPropertyDescriptor(GL1.prototype, k));
    }
    Object.defineProperty(proto, Symbol.toStringTag, { value: 'WebGL2RenderingContext', writable: false, enumerable: false, configurable: true });
    Object.defineProperty(ctor, 'prototype', { writable: false, enumerable: false });
    Object.defineProperty(G, 'WebGL2RenderingContext', { value: ctor, writable: true, enumerable: false, configurable: true });
    for (const C of [G.HTMLCanvasElement, G.OffscreenCanvas]) {
      if (typeof C !== 'function' || !C.prototype.getContext) continue;
      const orig = C.prototype.getContext;
      Object.defineProperty(C.prototype, 'getContext', {
        value: makeNative('getContext', 1, function (type) {
          const ctx = orig.apply(this, arguments);
          if (ctx && String(type) === 'webgl2' && Object.getPrototypeOf(ctx) === GL1.prototype) Object.setPrototypeOf(ctx, proto);
          return ctx;
        }),
        writable: true, enumerable: true, configurable: true,
      });
    }
    return ctor;
  }

  // ---------------------------------------------------------------------
  // Prototype parity: every member Chrome has on an interface Lightpanda
  // exposes, gated by the release that shipped it. Table format (one entry
  // per interface, ";" separated): "Iface>name:kind@since,..." and
  // "Iface.s>" for static members.
  //   m<n> method (n = WebIDL length)  g/gs/s accessor  c<v> constant
  //   L<n> correct a method's length   A/AS data property -> accessor
  //   S    add the setter Chrome has
  // Calls on the prototype itself throw "Illegal invocation" like Blink's
  // bindings; attributes a script sets read back per instance. The returned
  // `slots` map lets real implementations below answer those getters.
  // ---------------------------------------------------------------------
  function parity(major, table) {
    const slots = new WeakMap();
    if (!table || !major) return slots;
    const G = self;
    const hop = Object.prototype.hasOwnProperty;
    const branded = (C, o) => o !== null && (typeof o === 'object' || typeof o === 'function') && o instanceof C && !hop.call(o, 'constructor');
    const illegal = () => { throw new TypeError('Illegal invocation'); };
    const inherited = (T, k) => { for (let p = Object.getPrototypeOf(T); p; p = Object.getPrototypeOf(p)) { const d = Object.getOwnPropertyDescriptor(p, k); if (d) return d; } return null; };
    const slot = (o) => { let s = slots.get(o); if (!s) { s = {}; slots.set(o, s); } return s; };
    const argc = (iname, k, len, n) => {
      if (n < len) throw new TypeError("Failed to execute '" + k + "' on '" + iname + "': " + len + ' argument' + (len > 1 ? 's' : '') + ' required, but only ' + n + ' present.');
    };
    // A default of the member's WebIDL return type (code from the table):
    // feature-detecting code that calls a member must get the kind of value
    // it expects (a Promise, an object), never undefined.
    const gated = /^(Clipboard|CredentialsContainer|WakeLock|USB|HID|Serial|Bluetooth|Presentation|PresentationRequest|EyeDropper|PaymentRequest|IdleDetector|IdentityCredential|DigitalCredential|NavigatorLogin|XRSystem|DocumentPictureInPicture|StorageAccessHandle|MediaDevices)$/;
    const defaultFor = (tc, iname) => {
      if (!tc) return undefined;
      switch (tc[0]) {
        case 'b': return false;
        case 'n': return 0;
        case 's': return '';
        case 'a': return [];
        case 'N': return null;
        case 'I': { const I = G[tc.slice(1)]; return typeof I === 'function' && I.prototype ? Object.create(I.prototype) : null; }
        case 'P':
          if (gated.test(iname)) return Promise.reject(new DOMException('The request is not allowed by the user agent or the platform in the current context.', 'NotAllowedError'));
          return Promise.resolve(defaultFor(tc.slice(1), iname));
        default: return undefined;
      }
    };
    const main = table.split('\n#EXT\n')[0];
    for (const seg of main.split(';')) {
      const gt = seg.indexOf('>');
      if (gt < 0) continue;
      let iname = seg.slice(0, gt);
      const stat = iname.endsWith('.s');
      if (stat) iname = iname.slice(0, -2);
      const C = G[iname];
      if (typeof C !== 'function') continue;
      const T = stat ? C : C.prototype;
      if (!T || typeof T !== 'object' && typeof T !== 'function') continue;
      for (const it of seg.slice(gt + 1).split(',')) {
        const at = it.lastIndexOf('@');
        if (at >= 0 && +it.slice(at + 1) > major) continue;
        const body = at < 0 ? it : it.slice(0, at);
        const c = body.lastIndexOf(':');
        const k = body.slice(0, c), full = body.slice(c + 1);
        const eq = full.indexOf('=');
        const code = eq < 0 ? full : full.slice(0, eq), tc = eq < 0 ? '' : full.slice(eq + 1), kind = code[0];
        try {
          const own = Object.getOwnPropertyDescriptor(T, k);
          if (kind === 'c') {
            if (!own) Object.defineProperty(T, k, { value: +code.slice(1), writable: false, enumerable: true, configurable: false });
          } else if (kind === 'm') {
            if (own) continue;
            const len = +code.slice(1);
            const up = inherited(T, k);
            let impl;
            if (up && typeof up.value === 'function') {
              const f = up.value;
              impl = function () { return f.apply(this, arguments); };
            } else if (stat) {
              impl = function () { argc(iname, k, len, arguments.length); return defaultFor(tc, iname); };
            } else if (tc[0] === 'P') {
              // Promise-returning operations reject instead of throwing.
              impl = function () {
                if (!branded(C, this)) return Promise.reject(new TypeError('Illegal invocation'));
                try { argc(iname, k, len, arguments.length); } catch (e) { return Promise.reject(e); }
                return defaultFor(tc, iname);
              };
            } else {
              impl = function () { if (!branded(C, this)) illegal(); argc(iname, k, len, arguments.length); return defaultFor(tc, iname); };
            }
            Object.defineProperty(T, k, { value: makeNative(k, len, impl), writable: true, enumerable: true, configurable: true });
          } else if (kind === 'g' || kind === 's') {
            if (own) continue;
            const up = inherited(T, k);
            const hasSet = code === 'gs' || code === 's';
            let get, set;
            if (up && (up.get || up.set)) {
              const ug = up.get, us = up.set;
              get = function () { return ug ? ug.call(this) : undefined; };
              set = function (v) { if (us) us.call(this, v); };
            } else {
              const handler = k.startsWith('on');
              get = function () {
                if (!stat && !branded(C, this)) illegal();
                const s = slots.get(this);
                if (s && hop.call(s, k)) return s[k];
                if (handler || !tc || tc === 'N' || tc === 'u') return null;
                // Same object on every read, like a real attribute.
                const v = defaultFor(tc, iname);
                if (v !== null && typeof v === 'object') slot(this)[k] = v;
                return v;
              };
              set = function (v) {
                if (!stat && !branded(C, this)) illegal();
                slot(this)[k] = handler ? (typeof v === 'function' || (v && typeof v === 'object') ? v : null) : v;
              };
            }
            const d = { get: makeNative('get ' + k, 0, get), enumerable: true, configurable: true };
            if (hasSet) d.set = makeNative('set ' + k, 1, set);
            Object.defineProperty(T, k, d);
          } else if (kind === 'L') {
            if (own && typeof own.value === 'function') Object.defineProperty(own.value, 'length', { value: +code.slice(1), configurable: true });
          } else if (kind === 'A') {
            if (!own || !('value' in own)) continue;
            const val = own.value;
            const d = {
              get: makeNative('get ' + k, 0, function () {
                if (!stat && !branded(C, this)) illegal();
                const s = slots.get(this);
                return s && hop.call(s, k) ? s[k] : val;
              }),
              enumerable: own.enumerable, configurable: true,
            };
            if (code === 'AS') d.set = makeNative('set ' + k, 1, function (v) { if (!stat && !branded(C, this)) illegal(); slot(this)[k] = v; });
            Object.defineProperty(T, k, d);
          } else if (kind === 'S') {
            if (!own || !own.get || own.set) continue;
            let set = function () {};
            if (k === 'style') set = function (v) { const st = this.style; if (st) st.cssText = String(v); };
            else if (k === 'selectionDirection') set = function (v) { try { this.setSelectionRange(this.selectionStart, this.selectionEnd, String(v)); } catch (e) { /* not a text control */ } };
            Object.defineProperty(T, k, { get: own.get, set: makeNative('set ' + k, 1, set), enumerable: own.enumerable, configurable: true });
          }
        } catch (e) { /* leave this member as it is */ }
      }
    }
    return slots;
  }

  // ---------------------------------------------------------------------
  // Real behaviour for the APIs fingerprinting and bot-detection scripts
  // call (Lightpanda only had empty interface objects for them).
  // ---------------------------------------------------------------------
  function deepApis(major, table, slots) {
    const G = self;
    const hop = Object.prototype.hasOwnProperty;
    const inst = (C, values) => { const o = Object.create(C.prototype); if (values) slots.set(o, values); return o; };
    const method = (T, k, len, impl) => Object.defineProperty(T, k, { value: makeNative(k, len, impl), writable: true, enumerable: true, configurable: true });
    const getter = (T, k, impl) => Object.defineProperty(T, k, { get: makeNative('get ' + k, 0, impl), enumerable: true, configurable: true });
    const argc = (iface, k, len, n) => { if (n < len) throw new TypeError("Failed to execute '" + k + "' on '" + iface + "': " + len + ' argument' + (len > 1 ? 's' : '') + ' required, but only ' + n + ' present.'); };
    const reject = (err) => Promise.reject(err);
    const mobile = !!(G.navigator && navigator.userAgentData && navigator.userAgentData.mobile);

    // setlike / maplike backing: Blink's read-only collections.
    const collection = (C, kind) => {
      if (typeof C !== 'function') return;
      const P = C.prototype;
      const data = (o) => { const s = slots.get(o); if (!s || !s.__data) throw new TypeError('Illegal invocation'); return s.__data; };
      getter(P, 'size', function () { return data(this).size; });
      method(P, 'has', 1, function (k) { return data(this).has(k); });
      method(P, 'forEach', 1, function (cb, thisArg) { const m = data(this); m.forEach((v, k) => cb.call(thisArg, v, k, this)); });
      method(P, 'entries', 0, function () { return data(this).entries(); });
      method(P, 'keys', 0, function () { return data(this).keys(); });
      method(P, 'values', 0, function () { return data(this).values(); });
      if (kind === 'map') method(P, 'get', 1, function (k) { return data(this).get(k); });
      const iter = kind === 'map' ? P.entries : P.values;
      Object.defineProperty(P, Symbol.iterator, { value: iter, writable: true, enumerable: false, configurable: true });
    };

    // --- document.timeline: the current animation frame's time ------------
    // (60 Hz vsync, whole 100µs, the value rAF callbacks get), never null.
    if (typeof G.AnimationTimeline === 'function' && typeof G.DocumentTimeline === 'function') {
      const period = 1000 / 60;
      const perfNow = performance.now.bind(performance), later = G.setTimeout.bind(G);
      // only advances between tasks (at rendering), like Chrome's
      let frameTime = null;
      getter(G.AnimationTimeline.prototype, 'currentTime', function () {
        if (!(this instanceof G.AnimationTimeline)) throw new TypeError('Illegal invocation');
        if (frameTime === null) {
          frameTime = Math.round(Math.floor(perfNow() / period) * period * 10) / 10;
          later(() => { frameTime = null; }, 0);
        }
        return frameTime;
      });
      getter(G.AnimationTimeline.prototype, 'duration', function () {
        if (!(this instanceof G.AnimationTimeline)) throw new TypeError('Illegal invocation');
        return null;
      });
    }

    // --- Trusted Types ----------------------------------------------------
    // Loaders (Cloudflare Turnstile among them) create a policy whenever
    // trustedTypes exists and pass its output to innerHTML / script.src.
    if (typeof G.TrustedTypePolicyFactory === 'function' && typeof G.TrustedTypePolicy === 'function') {
      const kinds = [['TrustedHTML', 'createHTML'], ['TrustedScript', 'createScript'], ['TrustedScriptURL', 'createScriptURL']];
      const values = new WeakMap();
      const make = (iface, v) => { const o = Object.create(G[iface].prototype); values.set(o, String(v)); return o; };
      for (const [iface] of kinds) {
        const I = G[iface];
        if (typeof I !== 'function') continue;
        const str = function () { if (!values.has(this)) throw new TypeError('Illegal invocation'); return values.get(this); };
        method(I.prototype, 'toString', 0, str);
        method(I.prototype, 'toJSON', 0, str);
      }
      const PP = G.TrustedTypePolicy.prototype;
      getter(PP, 'name', function () { const s = slots.get(this); if (!s) throw new TypeError('Illegal invocation'); return s.name; });
      for (const [iface, fn] of kinds) {
        method(PP, fn, 1, function (input) {
          const s = slots.get(this);
          if (!s) throw new TypeError('Illegal invocation');
          const rule = s.rules && s.rules[fn];
          if (typeof rule !== 'function') throw new TypeError("Failed to execute '" + fn + "' on 'TrustedTypePolicy': Policy " + s.name + "'s TrustedTypePolicyOptions did not specify a '" + fn + "' member.");
          const r = rule.apply(undefined, [String(input), ...Array.prototype.slice.call(arguments, 1)]);
          return make(iface, r == null ? '' : r);
        });
      }
      const FP = G.TrustedTypePolicyFactory.prototype;
      let defaultPolicy = null;
      method(FP, 'createPolicy', 1, function (name, rules) {
        if (arguments.length < 1) throw new TypeError("Failed to execute 'createPolicy' on 'TrustedTypePolicyFactory': 1 argument required, but only 0 present.");
        const n = String(name);
        if (n === 'default' && defaultPolicy) throw new TypeError("Failed to execute 'createPolicy' on 'TrustedTypePolicyFactory': Policy with name \"default\" already exists.");
        const p = inst(G.TrustedTypePolicy, { name: n, rules: rules ? { createHTML: rules.createHTML, createScript: rules.createScript, createScriptURL: rules.createScriptURL } : {} });
        if (n === 'default') defaultPolicy = p;
        return p;
      });
      const isA = (iface) => function (v) { return v !== null && typeof v === 'object' && values.has(v) && v instanceof G[iface]; };
      method(FP, 'isHTML', 1, isA('TrustedHTML'));
      method(FP, 'isScript', 1, isA('TrustedScript'));
      method(FP, 'isScriptURL', 1, isA('TrustedScriptURL'));
      const emptyHTML = make('TrustedHTML', ''), emptyScript = make('TrustedScript', '');
      getter(FP, 'emptyHTML', function () { return emptyHTML; });
      getter(FP, 'emptyScript', function () { return emptyScript; });
      getter(FP, 'defaultPolicy', function () { return defaultPolicy; });
      const attrTypes = { script: { src: 'TrustedScriptURL' }, iframe: { srcdoc: 'TrustedHTML' }, embed: { src: 'TrustedScriptURL' }, object: { data: 'TrustedScriptURL', codebase: 'TrustedScriptURL' } };
      method(FP, 'getAttributeType', 2, function (tag, attr) {
        const t = attrTypes[String(tag).toLowerCase()];
        const a = String(attr).toLowerCase();
        if (t && t[a]) return t[a];
        return a.startsWith('on') ? 'TrustedScript' : null;
      });
      method(FP, 'getPropertyType', 2, function (tag, prop) {
        const p = String(prop);
        if (p === 'innerHTML' || p === 'outerHTML') return 'TrustedHTML';
        const tg = String(tag).toLowerCase();
        if (tg === 'script' && (p === 'text' || p === 'textContent' || p === 'innerText')) return 'TrustedScript';
        if (tg === 'script' && p === 'src') return 'TrustedScriptURL';
        if (tg === 'iframe' && p === 'srcdoc') return 'TrustedHTML';
        return null;
      });
    }

    // --- WebGL: extension objects and WebGL 2 parameters ------------------
    const GL1 = G.WebGLRenderingContext, GL2 = G.WebGL2RenderingContext;
    if (typeof GL1 === 'function') {
      const extDefs = new Map();
      const extPart = ((table || '').split('\n#EXT\n')[1] || '').split('\n#WIN\n')[0];
      for (const e of extPart.split(';')) { const i = e.indexOf('|'); if (i > 0) extDefs.set(e.slice(0, i), e.slice(i + 1)); }
      const extProtos = new Map();
      const extProto = (name) => {
        let p = extProtos.get(name);
        if (p) return p;
        const ctor = makeNative(name, 0, function () {}, true);
        p = ctor.prototype;
        for (const part of (extDefs.get(name) || '').split(' ').filter(Boolean)) {
          const eq = part.indexOf('='), paren = part.indexOf('(');
          if (eq > 0) Object.defineProperty(p, part.slice(0, eq), { value: +part.slice(eq + 1), writable: false, enumerable: true, configurable: false });
          else if (paren > 0) {
            const m = part.slice(0, paren), len = +part.slice(paren + 1);
            method(p, m, len, function () {
              if (!(this instanceof ctor)) throw new TypeError('Illegal invocation');
              argc(name, m, len, arguments.length);
              if (m.startsWith('is')) return false;
              if (m.startsWith('create') || m.startsWith('get')) return null;
              return undefined;
            });
          }
        }
        Object.defineProperty(p, Symbol.toStringTag, { value: name, writable: false, enumerable: false, configurable: true });
        extProtos.set(name, p);
        return p;
      };
      const enabled = new WeakMap();
      const gl2Params = {
        MAX_3D_TEXTURE_SIZE: 2048, MAX_ELEMENTS_VERTICES: 2147483647, MAX_ELEMENTS_INDICES: 2147483647, MAX_TEXTURE_LOD_BIAS: 2,
        MAX_DRAW_BUFFERS: 8, MAX_FRAGMENT_UNIFORM_COMPONENTS: 4096, MAX_VERTEX_UNIFORM_COMPONENTS: 16384, MAX_ARRAY_TEXTURE_LAYERS: 2048,
        MIN_PROGRAM_TEXEL_OFFSET: -8, MAX_PROGRAM_TEXEL_OFFSET: 7, MAX_VARYING_COMPONENTS: 120,
        MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS: 4, MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS: 120,
        MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS: 4, MAX_COLOR_ATTACHMENTS: 8, MAX_SAMPLES: 8, MAX_VERTEX_UNIFORM_BLOCKS: 12,
        MAX_FRAGMENT_UNIFORM_BLOCKS: 12, MAX_COMBINED_UNIFORM_BLOCKS: 24, MAX_UNIFORM_BUFFER_BINDINGS: 24, MAX_UNIFORM_BLOCK_SIZE: 65536,
        MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS: 212992, MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS: 200704,
        UNIFORM_BUFFER_OFFSET_ALIGNMENT: 256, MAX_VERTEX_OUTPUT_COMPONENTS: 120, MAX_FRAGMENT_INPUT_COMPONENTS: 120,
        MAX_SERVER_WAIT_TIMEOUT: 0, MAX_ELEMENT_INDEX: 4294967294, MAX_CLIENT_WAIT_TIMEOUT_WEBGL: 0,
      };
      let gl2ByEnum = null;
      for (const C of [GL1, GL2]) {
        if (typeof C !== 'function') continue;
        const P = C.prototype;
        const nativeGet = P.getExtension, nativeParam = P.getParameter, supported = P.getSupportedExtensions;
        if (typeof nativeGet !== 'function' || typeof nativeParam !== 'function') continue;
        method(P, 'getExtension', 1, function (name) {
          argc(C === GL2 ? 'WebGL2RenderingContext' : 'WebGLRenderingContext', 'getExtension', 1, arguments.length);
          const r = nativeGet.call(this, name);
          const want = String(name).toLowerCase();
          const list = supported.call(this) || [];
          const canonical = list.find((n) => n.toLowerCase() === want);
          if (!canonical) return r || null;
          let m = enabled.get(this);
          if (!m) { m = new Map(); enabled.set(this, m); }
          if (r) { m.set(canonical, r); return r; }
          if (!m.has(canonical)) m.set(canonical, Object.create(extProto(canonical)));
          return m.get(canonical);
        });
        method(P, 'getParameter', 1, function (pname) {
          const v = nativeParam.apply(this, arguments);
          if (v !== null && v !== undefined) return v;
          const n = +pname;
          if (n === 0x84FF) { const m = enabled.get(this); return m && m.has('EXT_texture_filter_anisotropic') ? 16 : null; }
          if (GL2 && this instanceof GL2) {
            if (!gl2ByEnum) {
              gl2ByEnum = new Map();
              for (const [k, val] of Object.entries(gl2Params)) { const e = GL2.prototype[k]; if (typeof e === 'number') gl2ByEnum.set(e, val); }
            }
            if (gl2ByEnum.has(n)) return gl2ByEnum.get(n);
          }
          return v;
        });
      }
    }

    // --- WebGPU -----------------------------------------------------------
    if (typeof G.GPU === 'function' && typeof G.GPUAdapter === 'function') {
      const vendorInfo = () => {
        let r = '';
        try {
          const c = (typeof OffscreenCanvas === 'function') ? new OffscreenCanvas(1, 1) : document.createElement('canvas');
          const g = c.getContext('webgl');
          if (g) r = String(g.getParameter(0x9246) || '');
        } catch (e) { /* no context */ }
        const s = r.toLowerCase();
        if (s.includes('nvidia')) {
          const arch = /rtx\s*50/.test(s) ? 'blackwell' : /rtx\s*40|rtx\s*\d+\s*ada/.test(s) ? 'lovelace' : /rtx\s*30|rtx a\d/.test(s) ? 'ampere'
            : /rtx\s*20|gtx\s*16|titan rtx/.test(s) ? 'turing' : /gtx\s*10|titan x/.test(s) ? 'pascal' : /gtx\s*9/.test(s) ? 'maxwell' : '';
          return { vendor: 'nvidia', architecture: arch, min: 32, max: 32 };
        }
        if (s.includes('amd') || s.includes('radeon')) {
          const arch = /rx\s*9\d{3}/.test(s) ? 'rdna-4' : /rx\s*7\d{3}|780m|760m/.test(s) ? 'rdna-3' : /rx\s*6\d{3}|680m|660m/.test(s) ? 'rdna-2'
            : /rx\s*5\d{3}/.test(s) ? 'rdna-1' : /vega/.test(s) ? 'gcn-5' : /rx\s*[45]\d0/.test(s) ? 'gcn-4' : '';
          return { vendor: 'amd', architecture: arch, min: arch.startsWith('rdna') ? 32 : 64, max: 64 };
        }
        if (s.includes('intel')) {
          const arch = /arc/.test(s) ? 'xe-hpg' : /iris\(r\) xe|iris xe|uhd graphics 7\d\d|uhd graphics 77\d|graphics 7\d\d/.test(s) ? 'gen-12lp'
            : /uhd graphics 6\d\d|hd graphics 6\d\d|iris plus|uhd graphics 6/.test(s) ? 'gen-9' : /hd graphics 5\d\d/.test(s) ? 'gen-9' : 'gen-12lp';
          return { vendor: 'intel', architecture: arch, min: 8, max: 32 };
        }
        if (s.includes('apple')) return { vendor: 'apple', architecture: 'metal-3', min: 4, max: 64 };
        if (s.includes('qualcomm') || s.includes('adreno')) return { vendor: 'qualcomm', architecture: '', min: 64, max: 128 };
        if (s.includes('arm') || s.includes('mali')) return { vendor: 'arm', architecture: '', min: 4, max: 64 };
        return { vendor: '', architecture: '', min: 4, max: 128 };
      };
      const featureList = [['depth-clip-control', 0], ['depth32float-stencil8', 0], ['texture-compression-bc', 0], ['texture-compression-bc-sliced-3d', 131],
        ['timestamp-query', 0], ['indirect-first-instance', 0], ['shader-f16', 0], ['rg11b10ufloat-renderable', 0], ['bgra8unorm-storage', 0],
        ['float32-filterable', 0], ['float32-blendable', 132], ['clip-distances', 131], ['dual-source-blending', 130], ['subgroups', 134],
        ['core-features-and-limits', 135], ['texture-formats-tier1', 138], ['texture-formats-tier2', 139], ['primitive-index', 145],
        ['texture-component-swizzle', 147], ['subgroup-size-control', 148], ['texture-compression-unaligned', 148]];
      const wgslList = [['readonly_and_readwrite_storage_textures', 0], ['packed_4x8_integer_dot_product', 0], ['unrestricted_pointer_parameters', 0],
        ['pointer_composite_access', 0], ['uniform_buffer_standard_layout', 143], ['subgroup_id', 144], ['subgroup_uniformity', 144],
        ['texture_and_sampler_let', 144], ['texture_formats_tier1', 145], ['linear_indexing', 146], ['swizzle_assignment', 147],
        ['buffer_view', 148], ['immediate_address_space', 148]];
      const limitList = [['maxTextureDimension1D', 16384], ['maxTextureDimension2D', 16384], ['maxTextureDimension3D', 2048], ['maxTextureArrayLayers', 2048],
        ['maxBindGroups', 4], ['maxBindGroupsPlusVertexBuffers', 24], ['maxBindingsPerBindGroup', 1000], ['maxDynamicUniformBuffersPerPipelineLayout', 10],
        ['maxDynamicStorageBuffersPerPipelineLayout', 8], ['maxSampledTexturesPerShaderStage', 48], ['maxSamplersPerShaderStage', 16],
        ['maxStorageBuffersPerShaderStage', 16], ['maxStorageTexturesPerShaderStage', 8], ['maxUniformBuffersPerShaderStage', 12],
        ['maxUniformBufferBindingSize', 65536], ['maxStorageBufferBindingSize', 2147483644], ['minUniformBufferOffsetAlignment', 256],
        ['minStorageBufferOffsetAlignment', 256], ['maxVertexBuffers', 8], ['maxBufferSize', 2147483648], ['maxVertexAttributes', 30],
        ['maxVertexBufferArrayStride', 2048], ['maxInterStageShaderVariables', 28], ['maxColorAttachments', 8],
        ['maxColorAttachmentBytesPerSample', 128], ['maxComputeWorkgroupStorageSize', 32768], ['maxComputeInvocationsPerWorkgroup', 1024],
        ['maxComputeWorkgroupSizeX', 1024], ['maxComputeWorkgroupSizeY', 1024], ['maxComputeWorkgroupSizeZ', 64],
        ['maxComputeWorkgroupsPerDimension', 65535], ['maxImmediateSize', 64], ['maxStorageBuffersInFragmentStage', 16],
        ['maxStorageTexturesInFragmentStage', 8], ['maxStorageBuffersInVertexStage', 16], ['maxStorageTexturesInVertexStage', 8]];
      collection(G.GPUSupportedFeatures, 'set');
      collection(G.WGSLLanguageFeatures, 'set');
      const features = () => inst(G.GPUSupportedFeatures, { __data: new Set(featureList.filter(([, v]) => v <= major).map(([k]) => k)) });
      const limits = () => {
        const L = G.GPUSupportedLimits;
        const values = {};
        for (const [k, v] of limitList) if (L && k in L.prototype) values[k] = v;
        return inst(L, values);
      };
      let wgsl = null;
      let adapterInfo = null;
      const info = () => {
        if (adapterInfo) return adapterInfo;
        const v = vendorInfo();
        adapterInfo = inst(G.GPUAdapterInfo, { vendor: v.vendor, architecture: v.architecture, device: '', description: '',
          subgroupMinSize: v.min, subgroupMaxSize: v.max, isFallbackAdapter: false });
        return adapterInfo;
      };
      const GP = G.GPU.prototype;
      method(GP, 'requestAdapter', 0, function () {
        const adapter = inst(G.GPUAdapter, { features: features(), limits: limits(), info: info(), isFallbackAdapter: false });
        return Promise.resolve(adapter);
      });
      method(GP, 'getPreferredCanvasFormat', 0, function () { return mobile ? 'rgba8unorm' : 'bgra8unorm'; });
      getter(GP, 'wgslLanguageFeatures', function () {
        if (!wgsl) wgsl = inst(G.WGSLLanguageFeatures, { __data: new Set(wgslList.filter(([, v]) => v <= major).map(([k]) => k)) });
        return wgsl;
      });
      const AP = G.GPUAdapter.prototype;
      method(AP, 'requestDevice', 0, function () {
        const s = slots.get(this);
        if (!s) return reject(new TypeError('Illegal invocation'));
        if (s.consumed) return reject(new DOMException('The adapter is consumed.', 'OperationError'));
        s.consumed = true;
        const device = inst(G.GPUDevice, {
          features: s.features, limits: s.limits, adapterInfo: s.info, label: '', onuncapturederror: null,
          queue: typeof G.GPUQueue === 'function' ? inst(G.GPUQueue, { label: '' }) : null,
          lost: new Promise(() => {}),
        });
        return Promise.resolve(device);
      });
    }

    // --- Encrypted Media Extensions --------------------------------------
    const NP = typeof Navigator !== 'undefined' ? Navigator.prototype : null;
    const canPlay = (type) => {
      if (!type) return true;
      try {
        const el = typeof document !== 'undefined' ? document.createElement(String(type).startsWith('audio') ? 'audio' : 'video') : null;
        return !el || el.canPlayType(String(type)) !== '';
      } catch (e) { return false; }
    };
    if (NP && hop.call(NP, 'requestMediaKeySystemAccess') && typeof G.MediaKeySystemAccess === 'function') {
      const KP = G.MediaKeySystemAccess.prototype;
      method(KP, 'getConfiguration', 0, function () { const s = slots.get(this); if (!s) throw new TypeError('Illegal invocation'); return JSON.parse(JSON.stringify(s.configuration)); });
      method(KP, 'createMediaKeys', 0, function () {
        if (!slots.get(this)) return reject(new TypeError('Illegal invocation'));
        return Promise.resolve(typeof G.MediaKeys === 'function' ? inst(G.MediaKeys, {}) : {});
      });
      method(NP, 'requestMediaKeySystemAccess', 2, function (keySystem, configs) {
        if (arguments.length < 2) return reject(new TypeError("Failed to execute 'requestMediaKeySystemAccess' on 'Navigator': 2 arguments required, but only " + arguments.length + ' present.'));
        const ks = String(keySystem);
        if (!ks) return reject(new TypeError("Failed to execute 'requestMediaKeySystemAccess' on 'Navigator': The keySystem parameter is empty."));
        const list = configs && typeof configs[Symbol.iterator] === 'function' ? Array.from(configs) : null;
        if (!list) return reject(new TypeError("Failed to execute 'requestMediaKeySystemAccess' on 'Navigator': The provided value cannot be converted to a sequence."));
        if (!list.length) return reject(new TypeError("Failed to execute 'requestMediaKeySystemAccess' on 'Navigator': The supportedConfigurations parameter is empty."));
        const unsupported = () => reject(new DOMException('Unsupported keySystem or supportedConfigurations.', 'NotSupportedError'));
        if (ks !== 'com.widevine.alpha' && ks !== 'org.w3.clearkey') return unsupported();
        for (const cfg of list) {
          const c = cfg || {};
          const caps = (k) => Array.isArray(c[k]) ? c[k] : [];
          const video = caps('videoCapabilities').filter((v) => v && canPlay(v.contentType));
          const audio = caps('audioCapabilities').filter((v) => v && canPlay(v.contentType));
          if (caps('videoCapabilities').length && !video.length) continue;
          if (caps('audioCapabilities').length && !audio.length) continue;
          const init = (Array.isArray(c.initDataTypes) ? c.initDataTypes : []).filter((t) => ['cenc', 'keyids', 'webm'].includes(t));
          if (Array.isArray(c.initDataTypes) && c.initDataTypes.length && !init.length) continue;
          const cap = (v) => ({ contentType: String(v.contentType || ''), encryptionScheme: v.encryptionScheme == null ? null : String(v.encryptionScheme), robustness: String(v.robustness || '') });
          const configuration = {
            audioCapabilities: audio.map(cap), distinctiveIdentifier: 'not-allowed', initDataTypes: init, label: String(c.label || ''),
            persistentState: c.persistentState === 'required' ? 'required' : 'not-allowed',
            sessionTypes: Array.isArray(c.sessionTypes) && c.sessionTypes.length ? c.sessionTypes.map(String) : ['temporary'],
            videoCapabilities: video.map(cap),
          };
          return Promise.resolve(inst(G.MediaKeySystemAccess, { keySystem: ks, configuration }));
        }
        return unsupported();
      });
    }

    // --- Media Capabilities ----------------------------------------------
    if (typeof G.MediaCapabilities === 'function') {
      const MP = G.MediaCapabilities.prototype;
      const info = (op, types, config) => {
        const where = "Failed to execute '" + op + "' on 'MediaCapabilities': ";
        if (!config || typeof config !== 'object') return reject(new TypeError(where + "1 argument required, but only 0 present."));
        if (!types.includes(config.type)) return reject(new TypeError(where + "Failed to read the 'type' property from 'MediaConfiguration': The provided value '" + config.type + "' is not a valid enum value of type " + (op === 'decodingInfo' ? 'MediaDecodingType' : 'MediaEncodingType') + '.'));
        if (!config.video && !config.audio) return reject(new TypeError(where + 'The configuration dictionary has neither |video| nor |audio| specified.'));
        let ok = true;
        if (config.video) ok = ok && canPlay(config.video.contentType);
        if (config.audio) ok = ok && canPlay(config.audio.contentType);
        const big = config.video && (+config.video.width * +config.video.height > 3840 * 2160 || +config.video.framerate > 120);
        const res = { powerEfficient: ok && !big, smooth: ok && !big, supported: ok };
        if (op === 'decodingInfo') res.keySystemAccess = null;
        res.configuration = config;
        return Promise.resolve(res);
      };
      method(MP, 'decodingInfo', 1, function (c) { return info('decodingInfo', ['file', 'media-source', 'webrtc'], c); });
      method(MP, 'encodingInfo', 1, function (c) { return info('encodingInfo', ['record', 'webrtc'], c); });
    }

    // --- Built-in AI (Summarizer, Translator, LanguageDetector) ------------
    const gesture = () => reject(new DOMException('Requires a user gesture when availability is "downloading" or "downloadable".', 'NotAllowedError'));
    if (typeof G.Summarizer === 'function') {
      method(G.Summarizer, 'availability', 0, function () { return Promise.resolve('downloadable'); });
      method(G.Summarizer, 'create', 0, gesture);
    }
    if (typeof G.Translator === 'function') {
      method(G.Translator, 'availability', 1, function (o) {
        if (!o || !o.sourceLanguage || !o.targetLanguage) return reject(new TypeError("Failed to execute 'availability' on 'Translator': Failed to read the 'sourceLanguage' property from 'TranslatorCreateCoreOptions': Required member is undefined."));
        return Promise.resolve(o.sourceLanguage === o.targetLanguage ? 'unavailable' : 'downloadable');
      });
      method(G.Translator, 'create', 1, gesture);
    }
    if (typeof G.LanguageDetector === 'function') {
      const LD = G.LanguageDetector;
      method(LD, 'availability', 0, function () { return Promise.resolve('available'); });
      method(LD, 'create', 0, function () { return Promise.resolve(inst(LD, { inputQuota: Infinity, expectedInputLanguages: null })); });
      method(LD.prototype, 'detect', 1, function (text) {
        if (!slots.get(this)) return reject(new TypeError('Illegal invocation'));
        const t = String(text || '');
        const guess = /[À-ỹ]/.test(t) && /[ăâđêôơư]/i.test(t) ? 'vi' : /[a-z]/i.test(t) ? 'en' : 'und';
        return Promise.resolve(guess === 'und' ? [{ detectedLanguage: 'und', confidence: 1 }] : [{ detectedLanguage: guess, confidence: 0.9 }, { detectedLanguage: 'und', confidence: 0.1 }]);
      });
      method(LD.prototype, 'measureInputUsage', 1, function (t) { return Promise.resolve(String(t || '').length); });
    }

    // --- Keyboard map -----------------------------------------------------
    if (typeof G.Keyboard === 'function' && typeof G.KeyboardLayoutMap === 'function') {
      collection(G.KeyboardLayoutMap, 'map');
      const keys = [];
      for (const ch of 'abcdefghijklmnopqrstuvwxyz') keys.push(['Key' + ch.toUpperCase(), ch]);
      for (let d = 0; d < 10; d++) keys.push(['Digit' + d, String(d)]);
      for (const [k, v] of [['Backquote', '`'], ['Minus', '-'], ['Equal', '='], ['BracketLeft', '['], ['BracketRight', ']'], ['Backslash', '\\'],
        ['Semicolon', ';'], ['Quote', "'"], ['Comma', ','], ['Period', '.'], ['Slash', '/'], ['IntlBackslash', '\\']]) keys.push([k, v]);
      const KP = G.Keyboard.prototype;
      method(KP, 'getLayoutMap', 0, function () {
        if (typeof window !== 'undefined' && window.top !== window) return reject(new DOMException('getLayoutMap() must be called from a top-level browsing context or allowed by the permission policy.', 'InvalidStateError'));
        return Promise.resolve(inst(G.KeyboardLayoutMap, { __data: new Map(keys) }));
      });
      method(KP, 'lock', 0, function () { return reject(new DOMException('Must be in fullscreen mode to lock the keyboard.', 'InvalidStateError')); });
      method(KP, 'unlock', 0, function () {});
    }

    // NodeFilter is a callback interface: a function without a prototype.
    if (typeof G.NodeFilter === 'function' && G.NodeFilter.prototype && typeof window !== 'undefined') {
      const NF = makeNative('NodeFilter', 0, function () { throw new TypeError('Illegal constructor'); });
      for (const k of Object.getOwnPropertyNames(G.NodeFilter)) {
        if (/^[A-Z_]+$/.test(k)) Object.defineProperty(NF, k, Object.getOwnPropertyDescriptor(G.NodeFilter, k));
      }
      Object.defineProperty(G, 'NodeFilter', { value: NF, writable: true, enumerable: false, configurable: true });
    }
    for (const k of ['WEBGL_debug_renderer_info', 'WEBGL_lose_context']) {
      if (hop.call(G, k)) { try { delete G[k]; } catch (e) { /* keep */ } }
    }
  }

  // ---------------------------------------------------------------------
  // The global object and every object on its prototype chain have an
  // immutable [[Prototype]] (HTML "immutable prototype exotic objects"; V8
  // SetImmutableProto): setting it to anything else throws. Lightpanda's
  // templates don't set the flag, and bot checks probe exactly this.
  // ---------------------------------------------------------------------
  function immutableGlobalChain() {
    const G = self;
    const locked = new Map();
    const label = (o) => {
      const c = o && Object.prototype.hasOwnProperty.call(o, 'constructor') ? o.constructor : Object.getPrototypeOf(o) && Object.getPrototypeOf(o).constructor;
      return c && c.name ? c.name : 'Object';
    };
    for (let o = G; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) {
      // window and Window.prototype both report as #<Window>
      locked.set(o, o === G ? label(Object.getPrototypeOf(G)) : label(o));
    }
    const fail = (o) => new TypeError("Immutable prototype object '#<" + locked.get(o) + ">' cannot have their prototype set");
    const blocked = (o, proto) => locked.has(o) && proto !== Object.getPrototypeOf(o);
    const setProto = Object.setPrototypeOf, reflectSet = Reflect.setPrototypeOf;
    Object.defineProperty(Object, 'setPrototypeOf', {
      value: makeNative('setPrototypeOf', 2, function (o, proto) {
        if (blocked(o, proto)) throw fail(o);
        return setProto(o, proto);
      }),
      writable: true, enumerable: false, configurable: true,
    });
    Object.defineProperty(Reflect, 'setPrototypeOf', {
      value: makeNative('setPrototypeOf', 2, function (o, proto) {
        if (blocked(o, proto)) return false;
        return reflectSet(o, proto);
      }),
      writable: true, enumerable: false, configurable: true,
    });
    const d = Object.getOwnPropertyDescriptor(Object.prototype, '__proto__');
    if (d && d.set) {
      const set = d.set;
      Object.defineProperty(Object.prototype, '__proto__', {
        get: d.get,
        set: makeNative('set __proto__', 1, function (proto) {
          if (blocked(this, proto)) throw fail(this);
          return set.call(this, proto);
        }),
        enumerable: false, configurable: true,
      });
    }
  }

  // ---------------------------------------------------------------------
  // window's own properties in Chrome's creation order (Object.keys(window)
  // and getOwnPropertyNames(window) are hashed by fingerprinters). The JS
  // builtins already match (same V8); everything after them is re-added in
  // the order a Chrome 157 window has, names Chrome lacks go last. Then the
  // [LegacyUnforgeable] ones and window.chrome become non-configurable.
  // ---------------------------------------------------------------------
  function reorderWindow(table) {
    const W = window;
    const section = (table || '').split('\n#WIN\n')[1];
    if (section) {
      const order = section.split(',');
      const start = order.indexOf('isNaN') + 1;
      const listed = new Set(order);
      const extras = Object.getOwnPropertyNames(W).filter((k) => !listed.has(k));
      const move = (k) => {
        const d = Object.getOwnPropertyDescriptor(W, k);
        if (!d || !d.configurable) return;
        // own but not enumerable in Chrome
        if (k === 'CSS' || k === 'offscreenBuffering') d.enumerable = false;
        try {
          delete W[k];
          Object.defineProperty(W, k, d);
        } catch (e) { /* keep it where it is */ }
      };
      if (start > 0) {
        for (let i = start; i < order.length; i++) move(order[i]);
        for (const k of extras) move(k);
      }
    }
    for (const k of ['window', 'document', 'location', 'top', 'chrome']) {
      const d = Object.getOwnPropertyDescriptor(W, k);
      if (d && d.configurable) { try { Object.defineProperty(W, k, { configurable: false }); } catch (e) { /* keep */ } }
    }
  }
})
