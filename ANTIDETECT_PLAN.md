# InviPanda: Lightpanda antidetect cho InviBrowser

Fork: https://github.com/SellGravity/lightpanda, nhánh `antidetect/main`. Upstream: lightpanda-io/browser.

InviPanda là một engine **headless, nhẹ** (mỗi profile ~20–120 MB RAM) dùng chung persona, proxy và bộ switch với profile Chromium của InviBrowser. Launcher điều khiển nó qua **CDP**, giống hệt Chromium.

## 1. Kết quả kiểm chứng (2026-11-18)

| Hạng mục | Kết quả |
|---|---|
| Test upstream (`make test`, chạy trên FS Linux) | **2427/2427** qua |
| **deviceandbrowserinfo** `/are_you_a_bot` (2026-11-19, bản release, có `Runtime.enable`) | **`isBot: false`**: hết `isAutomatedWithCDP` (cả worker), hết `hasInconsistentTimingResolution` |
| **fingerprint-scan.com** bot score | 100 → **77** (Browser HIGH+80 → MEDIUM+15). Phần còn lại: Network/proxy +44, Hardware +18 |
| CreepJS (bản cuối) | like-headless **31%** (bằng Chrome desktop thật), headless 0%, stealth 0% |
| **fingerprint-scan.com** (2026-11-19) | CDP check / CDP stack check / worker / iframe đều `false`; WebGPU, Widevine, mediaCapabilities, Summarizer, keyboard map, audio extended, scrollbar 15px, WebGL2 params khớp Chrome thật |
| **BrowserScan** | **100%**, Bot Detection: không phát hiện. Server trả `isBrowserCorrect=1`, kernel `windowVersion 139-140`, `liedWindow=false` |
| **pixelscan** `/fingerprint-check` | **"Your Browser Fingerprint is consistent"**, No masking / No proxy / No automated behavior. Nhận đúng "Chrome 140 on Windows", font Windows 55/55 (`osFontsStatus: true`), hash hộp đỏ WebGL trùng Chrome |
| sannysoft | Tất cả qua |
| iphey | "Your Digital Identity Looks **Trustworthy**", không có tín hiệu đáng ngờ |
| CreepJS | headless 0%, stealth 0%. like-headless 31% = đúng mức của Chrome desktop thật (ActiveText, theme sáng, 3 API chỉ Android) |
| Thứ tự header HTTP | Điều hướng / fetch / subresource đúng thứ tự Chrome, có header `priority` (`u=0, i`, `u=1, i`…) |
| **JA4** (tls.peet.ws) | `t13d1516h2_8daaf6152771_d8a2da3f94cd`, **trùng JA4 Chrome 131+** |
| **HTTP/2 Akamai** | `1:65536;2:0;4:6291456;6:262144\|15663105\|0\|m,a,s,p`, **trùng Chrome** |
| JA3 | Đổi theo từng kết nối (permute extension), giống Chrome |
| CDP e2e từ Windows qua WSL | Mọi lệnh launcher dùng (Target/Page/Runtime/DOM/Input/Network) đều OK |
| Canvas | Vẽ pixel thật. Hash khác nhau giữa các profile, ổn định trong cùng một profile |
| Font | Persona Windows thấy font Windows, Mac thấy font Mac. `--font-exclusion-list` hoạt động, kể cả khi bật `--fonts-noise` |
| WebGL / WebGL2 | Cả hai context đều có. VERSION/GLSL, tham số và extension giống Chrome. `instanceof WebGL2RenderingContext` đúng |
| Bản release qua launcher | `wsl.exe -e /opt/invipanda/invipanda` + bộ flag của `chromium-flags.builder.ts` (gồm `--load-extension`, URL khởi động): CDP sẵn sàng sau ~3,8 s, persona đầy đủ |

## 2. Hợp đồng với launcher

`src/Persona.zig` → `translateArgs()` được gọi trong `main.zig` trước `Config.parseArgs`.

- **Chế độ launcher** (không có subcommand): tự chèn `serve`. Chỉ giữ các tùy chọn đã dịch; switch chỉ Chromium có, `--load-extension` và URL khởi động đều bị bỏ.
- Các switch được dịch sang tuỳ chọn native:
  - `--remote-debugging-port=N` → `--host 127.0.0.1 --port N`
  - `--timezone`, `--lang` → `--timezone`, `--locale`
  - `--proxy-server=socks5://…` → `--http-proxy socks5h://…` (**DNS đi qua proxy**)
- Persona dùng chung cho cả process: mỗi process là một profile.
- Không có switch nào của launcher thì chạy y như upstream.

Switch được hỗ trợ:

```
--user-agent  --ua-full-version  --ua-platform-version  --hardware-concurrency
--device-memory  --device-mode=phone  --device-size  --window-size  --screen-size
--window-position  --window-scale  --max-touch-points  --webgl-vendor
--webgl-renderer  --canvas-noise  --audio-noise  --fonts-noise  --rects-noise
--fp-seed  --font-exclusion-list  --media-device-count  --webrtc-mode
--location-mode=allow|block|ask[,lat,lng]  --timezone  --lang  --proxy-server
--remote-debugging-port  --user-data-dir (seed nhiễu)
```

## 3. Các bề mặt đã giả lập

| Nhóm | Chi tiết | File |
|---|---|---|
| UA / UA-CH | UA launcher (Mozilla được phép), brand GREASE theo **thuật toán Chromium**. `Sec-Ch-Ua*` đúng thứ tự Chrome, chỉ gửi trên https/loopback. `userAgentData` + high-entropy | Persona.zig, HttpClient.zig, NavigatorUAData.zig |
| Header điều hướng | Accept của Chrome, `Upgrade-Insecure-Requests`, `Accept-Encoding: gzip, deflate, br, zstd` | Config.zig, Frame.zig, http.zig |
| TLS | GREASE, permute ext, cipher, X25519MLKEM768, sigalgs, OCSP/SCT, nén cert brotli, session ticket, ALPS (codepoint mới), ECH GREASE | network/chrome_tls.zig |
| HTTP/2 | SETTINGS, WINDOW_UPDATE, thứ tự pseudo-header của Chrome | vendor/curl/http2.c |
| navigator | platform, vendor, appVersion, productSub, hardwareConcurrency, deviceMemory (bucket), maxTouchPoints, plugins/mimeTypes (5 plugin PDF), pdfViewerEnabled, connection, mediaDevices, getBattery, 23 member chỉ Chrome có (clipboard, usb, hid, gpu…), getGamepads, share… | Navigator.zig, NavigatorExtras.zig, PluginArray.zig |
| Global | Gỡ `globalPrivacyControl` / `modelContext`. Thêm `window.chrome` (app/csi/loadTimes, toString là `[native code]`). Persona mobile gỡ API chỉ desktop có | persona_bootstrap.js |
| Màn hình / cửa sổ | screen, availHeight (trừ taskbar), outer > inner (khung trình duyệt), screenX/Y, DPR, mobile | Screen.zig, Window.zig, Browser.zig |
| Media query | pointer/hover, color-gamut, color, prefers-*, forced-colors, dynamic-range, device-* lấy theo màn hình, resolution / -webkit-device-pixel-ratio | css/MediaQuery.zig |
| WebGL | Context WebGL1 và WebGL2 với bảng `getParameter` theo nhóm GPU (desktop/Apple/mobile), extension theo đúng thứ tự Chrome, precision format, các object GL | canvas/WebGLRenderingContext.zig |
| Canvas 2D | **Raster thật** bằng tiny-skia: path, arc, chữ, gradient, 26 chế độ composite, putImageData. PNG đúng kích thước | canvas/raster.zig, rust/render/canvas.rs |
| Nhiễu | canvas (pixel theo seed), fonts (measureText), rects (getBoundingClientRect), audio (OfflineAudioContext) | raster.zig, Element.zig, Persona.zig |
| Font | Danh sách font theo OS, metric riêng cho từng font, fallback theo đúng CSS, `--font-exclusion-list` | fonts.zig, layout.zig |
| Quyền / vị trí | `permissions.query` geolocation, toạ độ từ `--location-mode` | Permissions.zig, Geolocation.zig |
| Bề mặt window | ~450 interface Chrome còn thiếu được tạo thành interface object thật (`new` → "Illegal constructor", đúng chuỗi prototype), **lọc theo phiên bản Chrome của persona**. Gỡ global riêng của Lightpanda (ModelContext, CrossOriginWindow, MemoryInfo…). Thêm attribute/operation của window Chrome (locationbar, external, clientInformation, caches, trustedTypes, on*…) | persona_bootstrap.js, js/native_shim.zig |
| navigator | Thứ tự `for..in` đúng IDL Chrome (pixelscan băm danh sách này), `serviceWorker`/`caches` có mặt, `devicePosture` (132+), `document.featurePolicy` | persona_bootstrap.js, js/Env.zig |
| CSS computed | `getComputedStyle` liệt kê đúng danh sách longhand của Chrome (theo phiên bản) + tên camelCase là own property; `::marker` / `::before` / `::after` áp dụng rule của pseudo-element | css/chrome_computed.zig, CSSStyleDeclaration.zig |
| WebGL | Rasterizer phần mềm (tam giác màu phẳng, clear, viewport, readPixels); `length` của mọi method đúng Chrome; WebGL trên OffscreenCanvas (cả trong worker) | persona_bootstrap.js, OffscreenCanvas.zig |
| Canvas / font | Nhiễu chỉ trên pixel khử răng cưa (vùng tô đặc và đường biên giữa chúng giữ nguyên). Mỗi font có độ lệch baseline dưới-pixel riêng nên các font khác nhau ra hình khác nhau | raster.zig, fonts.zig |
| iframe | `src="javascript:…"` chạy script trong about:blank cùng origin (pixelscan dùng để so sánh vân tay) | Frame.zig |
| CDP không lộ | Khi automation bật `Runtime.enable`, serialize console/exception **không bao giờ chạy getter của trang** (`stack`, `message`, `name`, Proxy, `Error.prepareStackTrace`): mẹo "Error có getter stack + console.debug" không còn bắt được CDP | cdp/domains/runtime.zig, js/Value.zig, js/TryCatch.zig |
| Đồng hồ | `performance.now()`, `event.timeStamp`, PerformanceEntry làm tròn 100µs kèm jitter như TimeClamper của Chrome, và mang đúng phần dư số thực của Chrome (1038.2999999970198); rAF chạy theo vsync 60 Hz với timestamp khung hình; `document.timeline.currentTime` | Performance.zig, Event.zig, Timers.zig |
| Runtime.enable | Automation bật `Runtime` không còn làm mọi exception chậm đi nhiều lần (V8 không dò catcher trên từng lần throw nữa): pages đo thời gian throw để nhận ra Puppeteer/Playwright | cdp/domains/runtime.zig |
| Lỗi native | Lỗi ném ra từ hàm giả lập không lộ frame của bootstrap trong `stack`; DOMException native có `stack` như Chrome | js/native_shim.zig, js/Caller.zig |
| Thứ tự window | `Object.keys(window)` / `getOwnPropertyNames(window)` đúng thứ tự Chrome 157 cho mọi tên chung; window/document/location/top/chrome không configurable | persona_bootstrap.js |
| Prototype parity | **4.938 member** của Chrome (method, getter/setter, hằng số, `length`) bổ sung cho mọi interface, **lọc theo phiên bản Chrome của persona** (dữ liệu MDN browser-compat-data). Gọi trên prototype → "Illegal invocation"; thiếu tham số → thông báo "Failed to execute … N argument(s) required" của Chrome; giá trị trả về đúng kiểu WebIDL (Promise, đối tượng interface, boolean…, lấy từ IDL spec @webref/idl) | persona_bootstrap.js `parity()`, persona_parity.txt |
| API sâu | WebGL2 có prototype riêng (không kế thừa WebGL1, như Chrome), **mọi object extension** + hằng số, tham số WebGL2; WebGPU (adapter, features/limits theo phiên bản, `info.vendor/architecture` suy từ GPU persona); EME **Widevine** (`requestMediaKeySystemAccess`), `mediaCapabilities.decodingInfo/encodingInfo`; Summarizer/Translator/LanguageDetector; `navigator.keyboard.getLayoutMap()` (48 phím); Trusted Types thật (createPolicy/createHTML…) | persona_bootstrap.js `deepApis()` |
| AnalyserNode | Node thật: cửa sổ Blackman + FFT + smoothing + dB như RealtimeAnalyser của Chrome (`reduction`, tổng time-domain khớp Chrome tới chữ số thứ 7) | webaudio/AnalyserNode.zig |
| Math | Persona Chrome < 150 dùng **fdlibm của V8 trước 2026** (biên dịch nguyên bản `ieee754.cc`) cho acos/asin/atan/atan2/cbrt/cosh/exp/expm1/log*/sinh/tan/tanh…: khớp bit-for-bit với Chrome cũ (V8 15.5 của Lightpanda đã đổi sang LLVM libm) | fdlibm/legacy_math.cc, js/native_shim.zig |
| Secure context | Trên http: gỡ đúng danh sách API chỉ có ở secure context của Chrome (navigator.gpu/keyboard/deviceMemory…, ~200 global, `crypto.subtle`) | persona_bootstrap.js |
| Scrollbar | `overflow: scroll` và root scroller trừ bề rộng thanh cuộn: 15px (Windows 11, Fluent), 17px (Windows 10), 15px Linux, 0 macOS/mobile | Element.zig, StyleManager.zig |
| Extension mặc định | `chrome-extension://ghbmnn…/page_embed_script.js` (Google Docs Offline, có sẵn trong Chrome desktop) trả đúng nội dung thật, 339 byte | network/HttpClient.zig |
| WebRTC ICE | Gathering y như Chrome: `gathering` → candidate host mDNS `<uuid>.local` → `complete` → candidate `null`, event trusted; `RTCIceCandidate` native. Không bao giờ lộ IP | RTCPeerConnection.zig |
| Chuỗi prototype window | Có object `WindowProperties`; global và cả chuỗi prototype là **immutable prototype** (setPrototypeOf ném đúng lỗi của Chrome) | persona_bootstrap.js |
| Rects | Giá trị nằm trên lưới LayoutUnit 1/64px như Chrome; nhiễu dịch đúng 1 đơn vị trên các cạnh lẻ (không bao giờ ra 59.9998…) | Element.zig |
| Khác | speechSynthesis (giọng Microsoft + Google), quota lưu trữ, `FontFace.load`, màu hệ thống, `/json/version` và `Browser.getVersion` trả lời như Chrome, `Browser.close` kết thúc process, telemetry luôn tắt | SpeechSynthesis.zig, server/http.zig, cdp/domains/browser.zig |

## 4. Giới hạn còn lại

1. **Pixel không giống hệt Chrome thật**: font DejaVu và cách khử răng cưa của tiny-skia khác Skia. Hash canvas là duy nhất cho từng profile, nhưng không trùng hash của "một máy Windows thật" nào.
2. **Layout xấp xỉ**: không có engine layout thật; vị trí, kích thước phần tử là ước lượng.
3. **WebRTC chỉ là bề mặt**: ICE gathering chạy đúng trình tự Chrome nhưng chỉ có candidate host mDNS (không srflx vì không có STUN thật), không có media thật.
8. **Cloudflare managed challenge / Turnstile chưa qua**: VM bytecode của Turnstile vẫn rơi vào nhánh lỗi (code 300010) ngay sau bước dò WebRTC. Đã sửa các khác biệt nó phát hiện (Trusted Types, ICE event, chuỗi prototype immutable, giá trị trả về đúng kiểu); phần còn lại cần dịch ngược VM.
9. CSP mới thực thi cho script inline (nonce, hash, `'unsafe-inline'`, header + meta). Script ngoài, `eval` và event handler inline chưa bị kiểm tra theo CSP.
4. **Không có bản Windows native**: chạy qua WSL2 (hoặc Docker).
5. **WebGL chỉ vẽ được hình màu phẳng**: đủ cho các bài kiểm tra kiểu "hộp đỏ"; shader phức tạp (gradient, texture) thì không ra pixel.
6. BrowserScan có bảng phiên bản CSS riêng (server) đọc ra `cssVersion 133-134` cho persona 140 (lệch 6). Không bị trừ điểm (chỉ tính khi CSS, JS và window cùng lệch), nhưng chưa khớp hẳn.
7. pixelscan so "legitimateHash" (featurePolicy + thứ tự navigator + giọng Google) với kho Chrome thật của họ: hiện trả `match:false` nhưng `legitimate:true`; không ảnh hưởng kết luận "consistent".

## 5. Tích hợp vào InviBrowser

`integrations/invibrowser/lightpanda-engine.ts`:
- Dùng lại nguyên bộ arg từ `chromiumConfig.build(...)` và spawn `wsl.exe -d <distro> -e /opt/invipanda/invipanda <args>`.
- Tự đổi `--user-data-dir` sang dạng `/mnt/c/...`.
- `waitForCdpReady` và `cdp.service.ts` giữ nguyên, vì WSL2 tự forward localhost.

Phía launcher (gravbrowser) **đã làm** trên nhánh `feat/lightpanda-engine` (worktree `InviBrower/gravbrowser-lightpanda`, dựa trên `feat/invifox-engine`, commit `d4fb8ad7`, chưa push):
- [x] `engine: 'lightpanda'` trong type, validator, chuẩn hoá; UI tạo/sửa profile có lựa chọn thứ ba "InviPanda (headless)" kèm gợi ý (en/vi).
- [x] `electron/modules/lightpanda/lightpanda-engine.ts`: spawn qua `wsl.exe -d <distro> -e /opt/invipanda/invipanda` (ghi đè bằng `INVIPANDA_WSL_DISTRO` / `INVIPANDA_BIN`), kill process Linux theo cổng debug.
- [x] Launcher: kiểm tra runtime (`INVIPANDA_RUNTIME_NOT_FOUND`), user-data-dir riêng, bỏ extension, profile giới hạn URL thì từ chối chạy; dừng êm bằng CDP `Browser.close`, dừng cưỡng bức kill cả process Linux.
- [x] `cdp.service`: chỉ Firefox là không có CDP, nên automation/API ngoài chạy được trên InviPanda.
- [x] Bản build đầy đủ: không cần truyền `--ua-full-version` nữa. UA có build đầy đủ (`Chrome/143.0.7490.0`) thì gửi UA rút gọn và dùng build cho client hints; UA đã rút gọn thì lấy build thật của bản phát hành + patch riêng từng profile.
- [ ] Phân phối runtime: `scripts/invipanda-package.sh` → `dist/invipanda-linux-x86_64.tar.gz`, cài bằng `scripts/invipanda-install-wsl.sh`.

Phía engine, để khớp đúng cách `cdp.service.ts` và API ngoài dùng CDP (chế độ launcher):
- **Một browser cho cả process, giống Chrome**: browser khởi động cùng server và có sẵn một tab `about:blank`. Client đến rồi đi, còn tab, trạng thái trang và cookie vẫn giữ nguyên. `/json` liệt kê các tab theo định dạng Chrome, mỗi tab có `webSocketDebuggerUrl` `/devtools/page/<id>`. Socket của tab nhận lệnh không cần `sessionId`, event gửi về cũng không kèm `sessionId`. `/devtools/browser/<id>` dùng cho Puppeteer/Playwright.
- Mỗi lúc chỉ có một client. Client mới (ví dụ `switchToTarget` đóng socket cũ rồi nối ngay socket mới, hoặc Puppeteer qua `cdpEndpoint`) sẽ tiếp quản browser, còn client cũ bị ngắt. Chrome cho nhiều client cùng lúc; ở đây hai client cùng chạy sẽ đá nhau.
- **Cookie lưu theo profile**: `<user-data-dir>/InviPanda/Cookies.json` được nạp khi khởi động và ghi lại khi cookie đổi (tối đa 1 lần/giây; ghi ngay khi xoá cookie hoặc khi trang tải xong). Seed cookie của launcher, vốn chỉ áp một lần, vẫn còn sau khi khởi động lại.
- **Dialog chặn script như Chrome**: `alert`/`confirm`/`prompt` chờ `Page.handleJavaScriptDialog`. Lệnh `Input.*` mở dialog được trả lời ngay, nên node "click" rồi node "accept alert" chạy đúng như trên Chrome. Nếu không ai trả lời trong 10 giây, dialog bị đóng cho script, và một `handleJavaScriptDialog` đến muộn vẫn thành công.
- `Emulation.setPageScaleFactor` có hỗ trợ.
- **Khớp thông số với Gravity Chromium.** Harness `match.mjs` gọi đúng `chromium-flags.builder.ts` của InviBrowser cho 4 profile mẫu (Windows 10, Windows 11, Android, iOS), chạy cùng bộ flag trên Gravity Chromium thật và trên InviPanda, rồi so từng giá trị JS và header. Kết quả: **0 lệch**. Các điểm đã sửa cho khớp:
  - UA giữ nguyên bản đầy đủ. Windows `platformVersion` = 10.0.0. `deviceMemory` lấy đúng giá trị của profile.
  - Số thiết bị media đúng thứ tự `audioinput,audiooutput,videoinput` và đúng số lượng.
  - WebRTC ở chế độ disable/forward không có candidate nào.
  - `Accept` có `image/jxl`. `Accept-Language` và `navigator.languages` kết thúc bằng `en-US,en`. Intl dùng locale ứng dụng của Chrome (vi-VN → vi).
  - Chế độ điện thoại: DPR 3, trang chiếm toàn màn hình thiết bị, có `ontouch*`, và khung nhìn 980px khi trang không có `<meta name=viewport>` (kèm `visualViewport.scale`).
  - Android: client hint `model` lấy từ UA. iOS: vendor Apple, không có `userAgentData`, không gửi client hint.
  - `Accept-CH` được nhớ theo origin, sau đó gửi các high-entropy hint đúng thứ tự của Chrome (cả điều hướng lẫn fetch).
  - HTTP/1.1: `Connection` đứng ngay sau `Host` (đã vendor `http.c` của curl).
  - Những chỗ Gravity tự sai thì **không bắt chước**: lộ ngôn ngữ của máy host, chèn "Mobile Safari" vào UA iOS, điện thoại có 5 plugin PDF, hướng màn hình ngang, `sec-ch-ua` rỗng trên iOS, đổi kích thước màn hình khi xếp ô cửa sổ.
- **macOS và Linux**: workflow `.github/workflows/invipanda.yml` build runtime native cho macOS (arm64, x86_64) và Linux (x86_64, aarch64), kèm smoke test chế độ launcher. Tag `invipanda-v*` phát hành bộ file tải về `invipanda-<os>-<arch>.tar.gz` kèm `.sha256`. Launcher tự cài runtime ở lần chạy đầu tiên: macOS/Linux vào `<userData>/invipanda`, Windows vào `/opt/invipanda` trong WSL.
- **Vị trí theo IP** (`--location-mode=<perm>,ip`, mặc định của InviBrowser): giống Gravity Chromium, lúc khởi động InviPanda tra toạ độ của IP đi ra **qua proxy của profile** (thử lần lượt ip-api.com, ipwho.is, ipinfo.io), trên một thread riêng, rồi trả độ chính xác cỡ thành phố (khoảng 1,5 km). Ở chế độ `ask`, `getCurrentPosition` chờ mãi như một prompt chưa ai trả lời, thay vì bị từ chối ngay (từ chối ngay trong khi quyền vẫn là "prompt" là dấu hiệu headless).
- Kiểm chứng bằng harness `invi-compat.mjs`: launch giống hệt gravbrowser, gọi hơn 55 method CDP mà app dùng, kiểm tra reconnect, takeover, switchToTarget và cookie sau khi khởi động lại. Kết quả **64/64**.

## 6. Build và test

```bash
# WSL Ubuntu 24.04 (đặt mã nguồn trên FS Linux, KHÔNG build trên /mnt/c)
make download-v8
zig fmt src build.zig      # zig build fail nếu sai format
zig build                  # bản debug
make test                  # toàn bộ test
scripts/invipanda-package.sh   # bản ReleaseFast + gói phân phối
```

Giấy phép: AGPL-3.0. Phân phối kèm InviBrowser hoặc chạy như dịch vụ thì phải công khai mã nguồn bản sửa. Fork này vốn đã public. `vendor/curl/http2.c` theo giấy phép curl (vendor/curl/COPYING).
