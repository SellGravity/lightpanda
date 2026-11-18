# InviPanda: Lightpanda antidetect cho InviBrowser

Fork: https://github.com/SellGravity/lightpanda, nhánh `antidetect/main`. Upstream: lightpanda-io/browser.

InviPanda là một engine **headless, nhẹ** (mỗi profile ~20–120 MB RAM) dùng chung persona, proxy và bộ switch với profile Chromium của InviBrowser. Launcher điều khiển nó qua **CDP**, giống hệt Chromium.

## 1. Kết quả kiểm chứng (2026-11-18)

| Hạng mục | Kết quả |
|---|---|
| Test upstream (`make test`, chạy trên FS Linux) | 2424/2425 qua. Test còn lại khẳng định *không có* `getBattery` (kiểu Firefox), đã sửa test theo hành vi Chrome |
| **JA4** (tls.peet.ws) | `t13d1516h2_8daaf6152771_d8a2da3f94cd`, **trùng JA4 Chrome 131+** |
| **HTTP/2 Akamai** | `1:65536;2:0;4:6291456;6:262144\|15663105\|0\|m,a,s,p`, **trùng Chrome** |
| JA3 | Đổi theo từng kết nối (permute extension), giống Chrome |
| CDP e2e từ Windows qua WSL | Mọi lệnh launcher dùng (Target/Page/Runtime/DOM/Input/Network) đều OK |
| Canvas | Vẽ pixel thật. Hash khác nhau giữa các profile, ổn định trong cùng một profile |
| Font | Persona Windows thấy font Windows, Mac thấy font Mac. `--font-exclusion-list` hoạt động |

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
| WebGL | Context WebGL1 với bảng `getParameter` theo nhóm GPU (desktop/Apple/mobile), extension theo đúng thứ tự Chrome, precision format, các object GL | canvas/WebGLRenderingContext.zig |
| Canvas 2D | **Raster thật** bằng tiny-skia: path, arc, chữ, gradient, 26 chế độ composite, putImageData. PNG đúng kích thước | canvas/raster.zig, rust/render/canvas.rs |
| Nhiễu | canvas (pixel theo seed), fonts (measureText), rects (getBoundingClientRect), audio (OfflineAudioContext) | raster.zig, Element.zig, Persona.zig |
| Font | Danh sách font theo OS, metric riêng cho từng font, fallback theo đúng CSS, `--font-exclusion-list` | fonts.zig, layout.zig |
| Quyền / vị trí | `permissions.query` geolocation, toạ độ từ `--location-mode` | Permissions.zig, Geolocation.zig |
| Khác | `/json/version` trả lời như Chrome. Telemetry luôn tắt. `Page.getFrameOwner` (Invi dùng) | server/http.zig, telemetry.zig, cdp/page.zig |

## 4. Giới hạn còn lại

1. **Pixel không giống hệt Chrome thật**: font DejaVu và cách khử răng cưa của tiny-skia khác Skia. Hash canvas là duy nhất cho từng profile, nhưng không trùng hash của "một máy Windows thật" nào.
2. **WebGL2**: `getContext('webgl2')` trả `null`, trong khi Chrome desktop luôn có.
3. **Layout xấp xỉ**: không có engine layout thật; vị trí, kích thước phần tử là ước lượng.
4. **Không có WebRTC, speechSynthesis**: thiếu API chứ không rò IP.
5. **Không có bản Windows native**: chạy qua WSL2 (hoặc Docker).
6. Timezone: `Intl.resolvedOptions().timeZone` trả tên canonical của ICU (ví dụ `Asia/Saigon`), giống V8 cùng thế hệ.

## 5. Tích hợp vào InviBrowser

`integrations/invibrowser/lightpanda-engine.ts`:
- Dùng lại nguyên bộ arg từ `chromiumConfig.build(...)` và spawn `wsl.exe -d <distro> -e /opt/invipanda/invipanda <args>`.
- Tự đổi `--user-data-dir` sang dạng `/mnt/c/...`.
- `waitForCdpReady` và `cdp.service.ts` giữ nguyên, vì WSL2 tự forward localhost.

Còn phải làm phía launcher:
- [ ] Thêm `engine: 'lightpanda'` vào profile và UI, rồi gọi `spawnLightpanda(finalArgs)` thay cho `spawn(chromeExe, …)`.
- [ ] Truyền `--ua-full-version` (bản build Chrome đầy đủ) từ fingerprint.
- [ ] Phân phối runtime: `scripts/invipanda-package.sh` → `dist/invipanda-linux-x86_64.tar.gz`, cài bằng `scripts/invipanda-install-wsl.sh`.

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
