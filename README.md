# Expo `createClass` memory per class under Hermes V1

This app shows that every Expo module `Class()` costs about 0.57 MiB of retained native memory on iOS at startup with Hermes V1. Expo evaluates a separate JavaScript source for each class it creates, and Hermes keeps memory for every evaluated source for the life of the runtime. A patch that evaluates one shared factory per runtime removes the per-class cost.

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
- `scripts/bench.sh` builds Release, installs, and cold-launches the app several times. Each run waits 15 seconds, checks the app's own log line (`classbench: classes=N/N factory=yes|no`) against the expected state, then samples memory. It appends one row per run to `results/raw.csv`.
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

<!-- results -->

## Conclusion

<!-- conclusion -->

## Limits

- iOS numbers come from the simulator. The allocations are in the app process, so a device should show the same per-class growth, but this repro did not measure one.
- The footprint breakdown shows where the memory is (`MALLOC_LARGE`), not the allocating call stack. `malloc_history` could not attach to the simulator process. The causal evidence is the A/B: the same build with only `createClass` changed.
- The patch caches the factory as a non-enumerable, non-writable property on `global` under `__expo_class_factory__`, shared by the Swift and C++ paths on iOS. Code that defines that key first could replace the factory. An upstream fix would keep the factory in runtime-owned native state instead. The key only matters for this repro.
- Constructors keep their `name`, `length`, prototype and `new` behavior. Two details change. The constructor's source text is the shared factory's, which Hermes does not expose because `Function.prototype.toString` prints `[bytecode]`. The Swift evaluation label is now the factory's label instead of `<Name>.__native_constructor__`.
