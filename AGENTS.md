# AGENTS.md — Camera App Reverse Engineering & iOS Port

This repository contains compiled Android camera APK/XAPK binaries, **not** source code. The goal is to decompile them, extract reusable camera assets (LUTs, filters, fonts, shaders), and port the filter pipeline to an iPhone UIKit camera app.

## Repository Contents (8 files in D:\learn)

| File | Size | Role |
|---|---|---|
| `oneplus-camera-3.102.28.apk` | ~111 MB | OnePlus camera app — **decompiled** |
| `oneplus.apk` | 5.5 KB | Stub (not the camera app) |
| `vivo-camera-12.1.15.602.apk` | ~201 MB | Vivo camera app — **decompiled** |
| `vivo-13.5.8.0.apk` | ~189 MB | Vivo camera app — **decompiled** |
| `vivo.apk` | ~293 MB | Vivo camera app — **decompiled** (14,691 classes) |
| `xiaomi.apk` | ~199 MB | Xiaomi camera app — **decompiled** (22,140 Java files) |
| `phocus-mobile-1.1.0.xapk` | ~178 MB | Xiaomi/Phocus camera bundle — not yet decompiled |
| `phocus.xapk` | 5.5 KB | Stub |

No git repo, no README, no build/test/lint/CI config, no existing instruction files.

## Tooling (Verified Installed)

| Tool | Version | Location |
|---|---|---|
| jadx | 1.5.6 | `C:\Users\Admin\.local\share\jadx\bin\jadx.bat` |
| Java | 26.0.2 (Zulu) | `java.exe` on PATH |
| Python | 3.x | `python.exe` / `python3.exe` on PATH |

## Exact Decompilation Commands

All decompiled output goes to `C:\Users\Admin\AppData\Local\Temp\opencode\` — **do not pollute `D:\learn` with scratch work**.

```powershell
# Initial decompile (code only, faster)
& "C:\Users\Admin\.local\share\jadx\bin\jadx.bat" -d "$env:TEMP\oneplus_decompiled" -r -j 4 "D:\learn\oneplus-camera-3.102.28.apk"

# Deobfuscation pass (recommended for obfuscated apps)
& "C:\Users\Admin\.local\share\jadx\bin\jadx.bat" -d "$env:TEMP\<out>" -r -j 4 --deobf "<apk>"

# Compare jadx vs fernflower (requires dex2jar)
& "C:\Users\Admin\.local\share\jadx\bin\jadx.bat" --engine both -d "$env:TEMP\<out>" "<apk>"
```

**Exit codes**: jadx exits with code 1 even on success (non-fatal decompilation errors are normal — count ~10-100 is expected). Check that `.java` files were produced in `<out>/sources/`.

## Deobfuscation Status (Verified)

| APK | Classes | Errors | Output Dir |
|---|---|---|---|
| oneplus-camera-3.102.28.apk | 1,897 | 10 | `$env:TEMP\oneplus_decompiled` |
| vivo-camera-12.1.15.602.apk | 7,252 | 10 | `$env:TEMP\vivo12_decompiled` |
| vivo-13.5.8.0.apk | 13,955 | 101 | `$env:TEMP\vivo13_decompiled` |

**Non-obfuscated anchor classes** (use as entry points — do not guess obfuscated names):

| Class | Package | Role |
|---|---|---|
| `MyApplication` | `com.oplus.camera` | Application entry |
| `EntryProvider` | `com.oplus.camera.entry` | ContentProvider entry |
| `CameraConfig` | `com.oplus.camera.config` | Camera config init |
| `OplusFilter` | `com.oplus.camera.filter` | Filter JNI bridge |
| `CameraFilterNodeProcessor` | `com.vivo.viengine.process.nodeprocessor` | Vivo LUT filter node |
| `LookupFilterParams` | `com.vivo.viengine.node.params` | LUT/mask/noise/light/frame paths |
| `AIFilterNodeProcessor` | `com.vivo.viengine.process.nodeprocessor` | Vivo AI scene filters |

## Filter Pipeline Architecture (Verified from Decompiled Code)

**Vivo LUT pipeline** (`com.vivo.viengine`):
```
RenderRequest → CameraFilterNodeProcessor ("VICameraLUTNode")
  → LookupFilterParams {lookupLutPath, maskPath, noisePath, lightPath, framePath, intensity}
  → CameraLookupTableRenderNode.updateRenderEngineParam().setEffect(intensity)
  → drawToTexture()
```

**OnePlus JNI pipeline** (`com.oplus.camera.filter.OplusFilter`):
```
init() → applyYuvFilter(byte[], int) → setFilterType(String) → setSize() → release()
  → loads libOplusFilterLUTJni.so + libPolarrRender.so
```

**GLSL shaders recovered** (`com.oplus.camera.gl`): texture sampling with `sampler2D`/`samplerExternalOES`, alpha blending, color uniforms (`uRed`/`uGreen`/`uBlue`), framebuffer attachments, vertex shaders with `uMatrix`/`uTextureMatrix`.

## Extracted Reusable Assets → iOS Mapping

Stage all assets to `C:\Users\Admin\AppData\Local\Temp\opencode\ios-camera-assets\`:

| Asset Source | iOS Reuse |
|---|---|
| `lut_all_points.png`, `filter_*.png`, `new_filter_*.png` | `CIColorCube` LUT or Metal texture |
| `lut1.png.bin`, `daily_lut.png.bin` | LUT 3D texture data |
| `film_grain_small.bin` (4MB), `texPerlinNoise.pkm` | Film grain noise texture |
| `Gotham-Bold.otf`, `Gilroy-Medium.otf`, `Roboto-Bold.ttf` | `UIFont` for camera controls |
| `overlay_p4_3_weak.png`, `filter_night_style_*.png` | Vignette/light-leak `CALayer` overlays |
| Sticker PNGs + ZIPs in `sticker/material/` | Sticker overlays |
| GLSL shaders (`frag_tex.sh`, `vertex_tex.sh`, etc.) | Port GLSL → Metal Shading Language (MSL) |
| `M_SenseME_Action_5.2.12.model` (3.6MB) | Core ML action detection (if convertible) |

## iOS Camera App (SwiftUI + UIKit, iPhone 17+)

**UI kit**: CameraKit (SwiftUI, from `CameraKit.zip` AGENT_BRIEF.md) integrated into `ios-camera-app/CameraKit/`

Structure:
```
ios-camera-app/
├── AppDelegate.swift             # App entry, preloads LUTs
├── SceneDelegate.swift           # Sets CameraViewController as root
├── CameraViewController.swift    # UIHostingController wrapping CameraKit CameraScreen
├── CameraKit/
│   ├── Tokens.swift              # CKColor, CKFont, CKMetrics, CKShape (design tokens)
│   ├── Motion.swift              # CKMotion curves, transitions, PressScaleStyle
│   ├── Controls.swift            # ShutterButton, RoundButton, RawChip, ModeKey, ThumbnailButton, TopBar
│   ├── DialRuler.swift           # DialMath, DialRuler, ExposureBar, FocusRow
│   ├── Overlays.swift            # GridOverlay, HistogramPanel, PeakingOverlay, ViewfinderTools
│   ├── CameraModel.swift         # @Observable CameraModel, CameraEngine protocol, MockHistogram
│   ├── CameraScreen.swift        # Assembled screen + previews
│   └── RealCameraEngine.swift    # AVFoundation behind CameraEngine (ISO/shutter/focus/zoom/capture)
├── FilterPipeline.swift          # CIColorCube LUT + CIColorControls + CIColorMatrix + CISharpenLuminance
├── LUTManager.swift              # Load LUT PNGs from asset bundle
├── StickerOverlayView.swift      # CALayer-based sticker overlays
├── FilmGrainView.swift           # Noise texture from film_grain_small.bin
├── Info.plist                    # Camera + microphone permissions
├── Main.storyboard / LaunchScreen.storyboard
└── Assets.xcassets               # Extracted fonts, LUTs, overlays, film grain
```

**Capture**: `AVFoundation` via `RealCameraEngine` (`AVCaptureSession`, `AVCaptureDevice`, `AVCaptureVideoDataOutput`, `AVCapturePhotoOutput`)

**Modes** (CameraKit):
- **Photo** (A): exposure rulers visible, LUT filters + color adjustments, watermarks
- **Video**: video recording via `AVCaptureMovieFileOutput`
- **Pro** (M): minimal UI, manual ISO (50-3200), shutter (1-1/8000s), focus distance (0-2m), white balance (2800-7000K)

**Filters** (ported from decompiled Android APKs — OnePlus, Vivo, Xiaomi):
- `CIColorCube` for LUTs (from Vivo `CameraLookupTableRenderNode` / OnePlus `libOplusFilterLUTJni.so`)
- `CIColorControls` for brightness/contrast/saturation
- `CIColorMatrix` for temperature (2000-10000K) and tint (green-magenta)
- `CISharpenLuminance` for sharpness
- Film grain from `film_grain_small.bin`

**GPU Support** (Metal Shading Language — ported from recovered GLSL in `com.oplus.camera.gl`):
- `MetalFilterPipeline.swift` — GPU-accelerated filter pipeline using Metal
- `Shaders.metal` — fragment shaders: `vertex_pass_through`, `fragment_color_cube`, `fragment_color_controls`, `fragment_temperature_tint`, `fragment_sharpen`, `fragment_film_grain`
- `FilterPipeline.useMetal` — auto-detects Metal availability; falls back to Core Image
- `MetalFilterPipeline.isMetalAvailable` — checks `MTLCreateSystemDefaultDevice() != nil`
- Shader pipeline: full-screen quad → color cube (LUT) → color controls → temperature/tint → sharpen → film grain

**LUT Assets** (extracted from APKs, in `Assets.xcassets/LUTs.lutcollection/`):
| LUT | Source APK | Asset |
|---|---|---|
| `lut_all_points` | oneplus-camera-3.102.28.apk | `assets/filters_res/lut_all_points.png` |
| `cartoon1_lut` | vivo-camera-12.1.15.602.apk | `assets/cartoon1/cartoon1_lut.png` |
| `dv_record_lut` | vivo-camera-12.1.15.602.apk | `assets/DVFilter/DVRecordLut.png` |
| `dv_screen_lut` | vivo-camera-12.1.15.602.apk | `assets/DVFilter/DVScreenLut.png` |
| `aifilter_beach` | vivo-camera-12.1.15.602.apk | `assets/aifilter/aifilter_beach.png` |
| `aifilter_cyberpunk` | vivo-camera-12.1.15.602.apk | `assets/aifilter/aifilter_cyberpunk.png` |
| `aifilter_night` | vivo-camera-12.1.15.602.apk | `assets/aifilter/aifilter_night.png` |
| `aifilter_portrait` | vivo-camera-12.1.15.602.apk | `assets/aifilter/aifilter_portrait.png` |
| `aifilter_sunset` | vivo-camera-12.1.15.602.apk | `assets/aifilter/aifilter_sunset.png` |

**Watermark Assets** (extracted from APKs, in `Assets.xcassets/Watermarks.imageset/`):
| Watermark | Source APK | Asset |
|---|---|---|
| `wm_leica_signature_black` | xiaomi.apk | `assets/watermarks/leica/88/icon_signature_black.webp` |
| `wm_leica_signature_white` | xiaomi.apk | `assets/watermarks/leica/88/icon_signature_white.webp` |
| `wm_xiaomi_black` | xiaomi.apk | `assets/watermarks/classic/17/xiaomi_black.webp` |
| `wm_xiaomi_white` | xiaomi.apk | `assets/watermarks/classic/17/xiaomi_white.webp` |
| `wm_poco_black` | xiaomi.apk | `assets/watermarks/classic/17/poco_black.webp` |
| `wm_poco_white` | xiaomi.apk | `assets/watermarks/classic/17/poco_white.webp` |
| `wm_redmi_black` | xiaomi.apk | `assets/watermarks/classic/17/redmi_black.webp` |
| `wm_redmi_white` | xiaomi.apk | `assets/watermarks/classic/17/redmi_white.webp` |
| `wm_bg_white` | xiaomi.apk | `assets/watermarks/classic/17/icon_background_white.webp` |
| `wm_bg_black` | xiaomi.apk | `assets/watermarks/classic/17/icon_background_black.webp` |
| `wm_vivo_tail` | vivo-camera-12.1.15.602.apk | `assets/vlogeffect/tail/tail_02/images/watermark2_49.jpg` |

**Watermark Styles** (`WatermarkStyle`):
| Style | Source | Description |
|---|---|---|
| `leicaSignature` | Xiaomi (Leica) | Leica camera signature watermark |
| `xiaomiBrand` | Xiaomi | Xiaomi brand logo watermark |
| `pocoBrand` | Xiaomi | POCO brand logo watermark |
| `redmiBrand` | Xiaomi | Redmi brand logo watermark |
| `vivoTail` | Vivo | Vivo video tail/end-screen watermark |

**Watermark Pipeline**: `WatermarkManager` composites watermark PNGs onto camera frames using `CISourceOverCompositing` with adjustable opacity (0-1) and scale (0.05-0.5). Applied both to live preview (per-frame) and captured photos.

**Histogram**: 48-bin luminance histogram computed per frame from `AVCaptureVideoDataOutput`

**LUT Pipeline**: `RealCameraEngine` applies `FilterPipeline` (CIColorCube LUT or Metal shader) to each `AVCaptureVideoDataOutput` frame and dispatches the filtered `UIImage` to the main thread via `onFilteredFrame` callback.

**Capture Formats** (`CameraModel.CaptureFormat`):
| Format | Description | AVFoundation setting |
|---|---|---|
| `JPG` | Standard JPEG | `settings.jpegQuality = 1.0` |
| `HEVC` | HEIF/HEVC compressed | `settings.isHEVCPhotoQualityPrioritizationEnabled = true` |
| `DNG` | RAW (Bayer) | `AVCapturePhotoSettings(rawPixelFormatType:)` |

**Photo Save**: Captured photos (with LUT + watermark applied) are saved to the device photo library via `PHPhotoLibrary`.

**Overlays**: `CALayer` / `UIImage` for stickers and vignettes
**Fonts**: Gotham-Bold, Gilroy for UI text

## Staging Rule

All decompiled output, extracted assets, and scratch work go to `C:\Users\Admin\AppData\Local\Temp\opencode\ios-camera-assets\`. Never write scratch files to `D:\learn` except the final `AGENTS.md` and the iOS project.

## GitHub Repo & CI

**Repo**: JACA (Just Another Camera App) — create at github.com, then:

```powershell
git remote add origin https://github.com/<your-username>/JACA.git
git branch -M main
git push -u origin main
```

**CI**: `.github/workflows/ios-ci.yml` runs on macOS-latest with Xcode 15:
- Builds Debug (iphonesimulator, iPhone 15) and Release (iphoneos, generic device)
- Cannot compile on this Windows machine — CI is the build path
- If a Podfile exists, CocoaPods install runs before build

**To compile locally** (macOS only):
```bash
xcodebuild -workspace ios-camera-app/ios-camera-app.xcworkspace \
  -scheme ios-camera-app \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```
