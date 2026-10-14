# Expo `createClass` memory per class under Hermes V1

This app shows that every Expo module `Class()` costs about 0.57 MiB of retained native memory at startup with Hermes V1, on iOS and on Android. Expo evaluates a separate JavaScript source for each class it creates, and Hermes keeps memory for every evaluated source for the life of the runtime. A patch that evaluates one shared factory per runtime removes the per-class cost.

The app is a blank Expo SDK 57 TypeScript project plus one local module, `modules/class-bench`, that defines N empty classes. The first screen reads every class from JavaScript and shows `classes: N/N` and whether the shared factory is in use.

## Versions

| Package | Version |
| --- | --- |
| expo | 57.0.22 |
| react-native | 0.86.3 (New Architecture) |
| Hermes | V1, `250829098.0.17` (the React Native 0.86 default) |
| expo-modules-core | 57.0.18 |
| expo-modules-jsi | 57.1.0 |
| patch-package | 8.0.1 |

`.npmrc` sets `before=2026-09-14`, so `npm install` resolves the same dependency tree later.

## How the repro works

- `scripts/gen-classes.mjs N` writes `ClassBenchModule.swift` and `ClassBenchModule.kt` with N classes named `Bench0` to `Bench<N-1>`. N=0 is the baseline. The committed module has N=200.
- Requiring the module makes Expo call `createClass` once per class. On iOS that is `JavaScriptRuntime.createClass` in expo-modules-jsi (Swift). On Android it is `expo::common::createClass` in expo-modules-core (C++). Both evaluate `(function BenchK(...args) { ... })` as a new source for each class.
- `patches/` holds the fix for both functions. `scripts/set-patch.sh on|off` applies or reverts it with patch-package, and refuses a half-applied state.
- `package.json` sets `expo.autolinking.ios.buildFromSource` to `ExpoModulesCore` and `ExpoModulesWorklets` in both arms. SDK 57 ships ExpoModulesCore prebuilt on iOS, so without this the C++ patch never compiles. The prebuilt ExpoModulesWorklets links ExpoModulesCore dynamically and crashes at launch with `Library not loaded: @rpath/ExpoModulesCore.framework` unless it builds from source too. ExpoModulesJSI always builds from `node_modules` sources.
- `scripts/bench.sh` builds Release, installs, and cold-launches the app several times. Each run waits 15 seconds, checks the app's own log line (`classbench: classes=N/N factory=yes|no`) against the expected state, then samples memory. It appends one row per run to `results/raw.csv`, which holds the runs below. Move it aside to start a fresh set.
- `scripts/summarize.mjs` prints the results table below from `results/raw.csv`.

## Run it

You need Xcode with an iOS simulator, CocoaPods, and for Android the Android SDK with a running arm64 emulator.

```sh
npm install
npx expo prebuild --no-install

# iOS: phys_footprint of the app process, from footprint(1)
export IOS_UDID=<booted simulator udid>
scripts/bench.sh ios 0 off 5
scripts/bench.sh ios 200 off 5
scripts/bench.sh ios 200 on 5

# Android: TOTAL PSS and Native Heap PSS, from dumpsys meminfo
export ANDROID_SERIAL=emulator-5554
scripts/bench.sh android 0 off 5
scripts/bench.sh android 200 off 5
scripts/bench.sh android 200 on 5

node scripts/summarize.mjs
```

Arguments are platform, N, patch state and number of runs. Add `1000 off` and `1000 on` to see the scaling. Each call rebuilds, because N and the patch both change native code. After the last run the app stays on its first screen.

## Results

Measured on 2026-10-14 on an Apple Silicon Mac. iOS ran on an iPhone 17 simulator with iOS 26.1. Android ran on a Pixel 7 emulator with API 35 (arm64-v8a). Each row is 5 cold launches of a Release build. Every run passed the first-screen check.

| Platform | Metric | Classes | Patch | Runs | Median (MiB) | Raw runs (MiB) | Native Heap PSS median (MiB) |
| --- | --- | ---: | --- | ---: | ---: | --- | ---: |
| ios | phys_footprint | 0 | off | 5 | 39.3 | 39.2, 39.4, 39.4, 39.3, 39.2 | n/a |
| ios | phys_footprint | 200 | off | 5 | 152.9 | 152.7, 152.9, 152.9, 152.8, 153.0 | n/a |
| ios | phys_footprint | 200 | on | 5 | 38.1 | 37.9, 38.3, 38.3, 38.1, 38.1 | n/a |
| ios | phys_footprint | 1000 | off | 5 | 607.0 | 606.9, 606.7, 607.0, 609.5, 607.2 | n/a |
| ios | phys_footprint | 1000 | on | 5 | 39.5 | 39.5, 39.5, 39.5, 39.6, 39.3 | n/a |
| ios | phys_footprint | 0 | on | 5 | 37.6 | 37.6, 37.6, 37.6, 37.6, 37.4 | n/a |
| android | total_pss | 0 | off | 5 | 55.0 | 68.9, 55.0, 54.8, 58.4, 54.9 | 11.6 |
| android | total_pss | 200 | off | 5 | 175.5 | 186.2, 172.0, 175.5, 175.7, 172.0 | 127.8 |
| android | total_pss | 200 | on | 5 | 58.0 | 68.5, 54.1, 58.0, 58.0, 54.6 | 10.3 |
| android | total_pss | 1000 | off | 5 | 639.7 | 640.4, 635.5, 639.6, 639.7, 639.7 | 592.7 |
| android | total_pss | 1000 | on | 5 | 58.6 | 74.9, 58.6, 64.0, 58.6, 58.6 | 11.9 |
| android | total_pss | 0 | on | 5 | 56.7 | 67.8, 53.3, 53.4, 56.8, 56.7 | 9.9 |

iOS reports `phys_footprint` from `footprint(1)`. Android reports `TOTAL PSS` and the `Native Heap` PSS row from `dumpsys meminfo <pid>`.

Cost per class, from the medians:

| Platform and metric | N=200 unpatched | N=1000 unpatched | Patched, 200 to 1000 |
| --- | ---: | ---: | ---: |
| iOS `phys_footprint` | (152.9 - 39.3) / 200 = 0.568 MiB | (607.0 - 39.3) / 1000 = 0.568 MiB | (39.5 - 38.1) / 800 = 1.8 KB |
| Android Native Heap PSS | (127.8 - 11.6) / 200 = 0.581 MiB | (592.7 - 11.6) / 1000 = 0.581 MiB | (11.9 - 10.3) / 800 = 2.0 KB |
| Android TOTAL PSS | (175.5 - 55.0) / 200 = 0.603 MiB | (639.7 - 55.0) / 1000 = 0.585 MiB | (58.6 - 58.0) / 800 = 0.8 KB |

On iOS the growth is all `MALLOC_LARGE` in `footprint`. Unpatched N=200 has 103 MB in 415 regions and N=1000 has 503 MB in 2017 regions, about two 250 KB allocations per class. Patched N=1000 has 1.1 MB in 10 regions. On Android almost all of the TOTAL PSS growth is the Native Heap row.

The first Android launch after each install reads 10 to 16 MiB higher in TOTAL PSS than the other four, in every configuration, while Native Heap moves by less than 1 MiB. The medians absorb it, and the class effect is 120 MiB at N=200.

## Conclusion

The per-class cost is clearly visible on both platforms. Each unpatched `Class()` keeps about 0.57 to 0.58 MiB of native memory for the life of the runtime, linear from 200 to 1000 classes. At N=0 and N=200 the run-to-run spread is at most 0.4 MiB on iOS and 0.6 MiB in Android Native Heap, so a few classes already show above the noise. Patched, the same 1000 classes cost about 2 KB each.

The patch also lowers the N=0 baseline by 1.7 MiB on both platforms (iOS 39.3 to 37.6 MiB, Android Native Heap 11.6 to 9.9 MiB). That is about three classes' worth. Expo creates a few base classes at startup through the same `createClass`, so every app pays something even without its own classes.

## Limits

- The numbers come from an iOS simulator and an Android emulator. This repro did not measure a physical device.
- The footprint breakdown shows where the memory is (`MALLOC_LARGE`), not the allocating call stack. `malloc_history` could not attach to the simulator process. The causal evidence is the A/B: the same build with only `createClass` changed.
- The patch caches the factory as a non-enumerable, non-writable property on `global` under `__expo_class_factory__`, shared by the Swift and C++ paths on iOS. Code that defines that key first could replace the factory. An upstream fix would keep the factory in runtime-owned native state instead. The key only matters for this repro.
- Constructors keep their `name`, `length`, prototype and `new` behavior. Two details change. Every constructor's source is the shared factory's source, and the Swift evaluation label is the factory's label instead of `<Name>.__native_constructor__`.
