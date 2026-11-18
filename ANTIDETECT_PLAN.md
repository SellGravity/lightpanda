# InviPanda: Lightpanda antidetect cho InviBrowser

Fork: https://github.com/SellGravity/lightpanda, nhánh `antidetect/main`. Upstream: lightpanda-io/browser.

Mục tiêu giống InviFox (SellGravity/firefox): engine nhận **đúng bộ switch** mà launcher đang truyền cho Chromium (`gravbrowser/electron/modules/chromium/chromium-flags.builder.ts`), nên phía launcher chỉ phải sửa rất ít.

## 0. Lightpanda hợp với vai trò gì (đọc trước)

| | Lightpanda | Chromium fork / InviFox |
|---|---|---|
| RAM mỗi profile | ~20–120 MB | 300 MB – 1 GB+ |
| Giao diện | **không có** (headless) | có cửa sổ |
| Render pixel (canvas, ảnh, font) | **chưa có**: canvas trả về PNG trắng, layout ước lượng | thật |
| WebGL | `getContext('webgl')` trả `null` | thật |
| CDP | **có sẵn** (launcher dùng lại `cdp.service.ts`) | có (Chromium) / không (Firefox) |
| TLS/HTTP2 fingerprint | libcurl + BoringSSL, **khác Chrome** | Chrome thật |
| Windows | **không có bản native**, chạy qua WSL2/Docker | có |

Vì vậy Lightpanda **không thể 100% giống Chrome trước các anti-bot mạnh** (FB, TikTok, Cloudflare Turnstile, Akamai) cho tới khi xong P3–P5. Vai trò hợp lý: **worker headless nhẹ** cho các tác vụ hàng loạt (crawl, check tài khoản, scrape, tự động hoá form) chạy hàng trăm profile trên một máy, mỗi profile vẫn giữ cùng persona và proxy như profile Chromium.

## 1. Hợp đồng với launcher

`src/Persona.zig` → `translateArgs()` được gọi trong `main.zig` trước `Config.parseArgs`:

1. Gỡ các switch của launcher ra khỏi argv và ghi vào persona dùng chung cho cả process (mỗi process là một profile).
2. Không có subcommand thì tự chèn `serve`, vì launcher luôn chạy ở chế độ CDP server.
3. Dịch các switch sang tuỳ chọn native của Lightpanda:
   - `--remote-debugging-port=N` → `--host 127.0.0.1 --port N`
   - `--timezone=X` → `--timezone X`
   - `--lang=vi-VN` → `--locale vi-VN` (Accept-Language và navigator.languages)
   - `--proxy-server=socks5://u:p@h:p` → `--http-proxy socks5h://...`. **DNS đi qua proxy.** libcurl chỉ làm vậy với `socks5h://`, còn Chromium luôn làm vậy.
4. Nuốt bỏ các switch chỉ Chromium có (`--disable-*`, `--no-first-run`…).
5. Không có switch nào của launcher thì `Persona.active = false` và mọi thứ chạy y như upstream, nên test upstream vẫn qua.

Lệnh launcher sẽ chạy (mẫu):

```
lightpanda --remote-debugging-port=9333 --user-data-dir=/profiles/p1 \
  --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36" \
  --ua-full-version=140.0.7339.128 --hardware-concurrency=8 --device-memory=8 \
  --window-size=1536,864 --timezone=Asia/Ho_Chi_Minh --lang=vi-VN \
  --webgl-vendor="Google Inc. (Intel)" --webgl-renderer="ANGLE (Intel, ...)" \
  --proxy-server=socks5://u:p@1.2.3.4:1080 --location-mode=allow,10.77,106.70 --canvas-noise
```

## 2. Trạng thái P1 (đã code, CHƯA build: máy chưa có Zig/WSL)

| Bề mặt | Cách làm | Trạng thái |
|---|---|---|
| `--user-agent` (HTTP + `navigator.userAgent`) | Lấy từ persona, cho phép chuỗi Mozilla (upstream chặn). CDP `setUserAgentOverride` cũng được nhận | xong |
| UA-CH: `Sec-Ch-Ua`, `-Mobile`, `-Platform` | Brand GREASE **theo đúng thuật toán Chromium** (ký tự và thứ tự phụ thuộc major version, có test so với Chrome 120/131/138/140). Bỏ `Full-Version-List` mặc định (Chrome chỉ gửi khi trang yêu cầu). Header đặt trước User-Agent | xong |
| `navigator.userAgentData` | brands, mobile, platform, `getHighEntropyValues` (platformVersion, uaFullVersion, fullVersionList, architecture, bitness, formFactors) | xong. Cần launcher truyền `--ua-full-version` |
| `navigator.platform/appVersion/vendor/productSub/vendorSub` | Suy ra từ UA (`Win32`, `MacIntel`, `Linux armv81`…); vendor `Google Inc.` | xong |
| `hardwareConcurrency`, `deviceMemory` | Persona. deviceMemory được làm tròn về bucket của Chrome (0.25…8) | xong (cả worker) |
| `maxTouchPoints`, mobile | Lấy từ `--device-mode=phone` / UA Android: 5 điểm chạm, DPR 2.625 | xong |
| Màn hình, cửa sổ | `screen.*` từ `--window-size` (desktop) hoặc `--device-size` (mobile). `availHeight` trừ taskbar. `outerWidth/Height` cộng thêm khung tab + toolbar (lộ kiểu headless là outer == inner). `screenX/Y` lấy từ `--window-position`. `devicePixelRatio` lấy từ `--window-scale` | xong |
| Timezone | `--timezone` native của Lightpanda | xong |
| Ngôn ngữ | `--locale` native | xong |
| Proxy | `socks5h` / `socks4a` để DNS không rò rỉ | xong |
| Geolocation | `--location-mode=allow,lat,lng`: tự cấp quyền và trả toạ độ, accuracy thêm nhiễu ổn định theo profile | xong (`permissions.query` để P2) |
| WebGL vendor/renderer | `getParameter` trả VENDOR/RENDERER/VERSION/UNMASKED_* | chuỗi xong, **nhưng `getContext('webgl')` vẫn trả null** (P2) |
| Telemetry | Tắt hẳn khi chạy profile của launcher (nếu bật, mọi profile sẽ bị gắn cùng một install id) | xong |
| `navigator.webdriver` | upstream đã trả `false` | xong |
| Seed nhiễu | `--fp-seed`, hoặc hash của `--user-data-dir` | đã có helper; thuật toán để P3 |

## 3. Các dấu hiệu còn lộ (theo mức độ)

1. **TLS JA3/JA4 và HTTP/2 fingerprint**: libcurl/BoringSSL khác Chrome. Cloudflare và Akamai chặn ngay ở tầng mạng. → P4: dùng curl-impersonate / cấu hình BoringSSL theo Chrome (thứ tự cipher, extension, GREASE, ALPS, cert compression, SETTINGS frame và thứ tự pseudo-header của H2). Upstream đã có sẵn `--http-curves`.
2. **Canvas trả PNG trắng y hệt nhau** ở mọi profile. Đây vừa là dấu hiệu bot vừa khiến các profile bị liên kết với nhau. → P3: rasterizer Canvas2D dựa trên `tiny-skia` + `parley` (đã có trong `src/rust/render`), cộng nhiễu theo seed.
3. **Không có WebGL** → P2: context WebGL giả, có bảng `getParameter` đầy đủ (MAX_TEXTURE_SIZE…), danh sách extension và `getShaderPrecisionFormat` theo GPU trong persona.
4. **API thừa hoặc thiếu so với Chrome**: `navigator.globalPrivacyControl` và `navigator.modelContext` (Chrome không có), thiếu `chrome.*`, `navigator.connection`, `getBattery`, `mediaDevices`. → P2: ẩn hoặc thêm theo persona.
5. **Layout xấp xỉ**: `getBoundingClientRect` và font metrics không khớp Chrome. → P5 (khó).
6. Header `Sec-Ch-Ua` đang gửi cả trên http://, trong khi Chrome chỉ gửi trên secure context. → P2.
7. WebRTC: Lightpanda không có RTCPeerConnection, nên không rò IP, nhưng việc thiếu API này cũng là một dấu hiệu. → P4: giả API theo `--webrtc-mode`.

## 4. Lộ trình

- **P1** (xong code): persona, switch, UA/UA-CH, navigator, màn hình, proxy, geolocation, telemetry.
- **P1.5**: build và chạy test. `make download-v8 && make fmt && make test`, sau đó test trên CreepJS, BrowserScan, pixelscan, sannysoft.
- **P2**: WebGL giả, `permissions.query`, `chrome.*` / `connection` / `mediaDevices` / `getBattery`, ẩn API không phải Chrome, client hints chỉ gửi trên https.
- **P3**: Canvas2D thật (tiny-skia) + nhiễu canvas/rects/fonts theo seed, AudioContext/OfflineAudioContext + nhiễu audio.
- **P4**: TLS/H2 impersonation giống Chrome theo version trong UA; WebRTC giả.
- **P5**: font metrics và layout gần với Chrome.

## 5. Việc phía launcher (gravbrowser)

- [ ] Thêm engine `lightpanda` vào profile và runtime. Bản build Linux x86_64 chạy trong **WSL2** (Windows không có bản native). Launcher gọi `wsl.exe -d <distro> -- /opt/invipanda/lightpanda <flags>`; WSL tự forward `localhost:<port>`.
  - Hoặc dùng Docker: `docker run -p 127.0.0.1:<port>:<port> sellgravity/invipanda <flags>`.
- [ ] Đổi đường dẫn `--user-data-dir` sang dạng `/mnt/c/...` khi chạy qua WSL (hiện chỉ dùng làm seed; lưu cookie lâu dài để P2).
- [ ] Truyền thêm `--ua-full-version=<bản build Chrome đầy đủ>` để high-entropy UA-CH không còn `x.0.0.0`.
- [ ] `cdp.service.ts` dùng được ngay. Lightpanda chưa có đủ mọi domain CDP, nên cần test từng workflow (Page, Runtime, Network, Input, DOM).
- [ ] Không gửi `--window-size` theo kích thước ô xếp cửa sổ cho engine này (headless không có cửa sổ). Gửi `--screen-size=W,H` của màn hình giả.

## 6. Build

```bash
# Ubuntu 24.04 (WSL2) hoặc Docker (Dockerfile có sẵn)
make download-v8
make fmt          # BẮT BUỘC: zig build fail nếu code chưa đúng format
make build        # hoặc: zig build -Doptimize=ReleaseFast
make test F="Persona"
```

Giấy phép: AGPL-3.0. Nếu cung cấp InviPanda cho người dùng qua mạng, hoặc phân phối kèm InviBrowser, thì **phải công khai mã nguồn bản sửa**. Fork này vốn đã public.
