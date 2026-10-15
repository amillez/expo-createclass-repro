# `createClass` evaluates one JS source per class, and Hermes V1 keeps ~0.57 MiB for each

## Summary

`createClass` in expo-modules-core (C++, `common/cpp/JSI/JSIUtils.cpp`) and in expo-modules-jsi (Swift, `JavaScriptRuntime.createClass`) builds each class constructor by evaluating a new source string, `(function Name(...args) { return this.__native_constructor__(...args); })`. Under Hermes V1, memory for every evaluated source stays alive for the life of the runtime. The cost is linear in the number of classes an app's modules define.

In a blank SDK 57 app, every `Class()` adds 0.57 MiB of iOS `phys_footprint` at the first screen. A module with 200 classes takes the app from 39.3 MiB to 152.9 MiB. Android shows the same 0.58 MiB per class in Native Heap PSS. Evaluating one shared factory per runtime and calling it with the class name removes the per-class cost.

This is on react-native 0.86.3 with Hermes `250829098.0.17`, the version #46519 names as the fix for the Hermes V1 memory regression. #46519 is locked and asks for new issues, so this is a separate report.

## Environment

- expo 57.0.22, expo-modules-core 57.0.18, expo-modules-jsi 57.1.0
- react-native 0.86.3, New Architecture, Hermes V1 `250829098.0.17` (the default)
- Release builds
- iOS: iPhone 17 simulator, iOS 26.1, Xcode on an Apple Silicon Mac
- Android: Pixel 7 emulator, API 35, arm64-v8a

## Steps to reproduce

Repro: https://github.com/amillez/expo-createclass-repro

1. `npm install && npx expo prebuild --no-install`
2. Boot a simulator and run `IOS_UDID=<udid> scripts/bench.sh ios 0 off 5`, then `ios 200 off 5`.
3. Run `scripts/bench.sh ios 200 on 5`. `on` applies the fix from `patches/` with patch-package before building.
4. Android works the same way with `ANDROID_SERIAL=<serial> scripts/bench.sh android ...`.

`scripts/gen-classes.mjs` generates a local module with N empty `Class()` definitions. The first screen reads every class from JS. `bench.sh` builds Release, cold-launches 5 times, checks the screen state the app logs, and samples memory 15 seconds after launch.

## Measured impact

Median of 5 cold launches each. Raw runs are in the repro's README and `results/raw.csv`.

| Classes | iOS `phys_footprint`, unpatched | iOS, patched | Android Native Heap PSS, unpatched | Android, patched | Android TOTAL PSS, unpatched | Android, patched |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 39.3 MiB | 37.6 MiB | 11.6 MiB | 9.9 MiB | 55.0 MiB | 56.7 MiB |
| 200 | 152.9 MiB | 38.1 MiB | 127.8 MiB | 10.3 MiB | 175.5 MiB | 58.0 MiB |
| 1000 | 607.0 MiB | 39.5 MiB | 592.7 MiB | 11.9 MiB | 639.7 MiB | 58.6 MiB |

- Each unpatched class costs 0.568 MiB on iOS and 0.581 MiB of Android Native Heap. The cost is the same at 200 and 1000 classes.
- With the patch, each extra class costs about 2 KB.
- On iOS the growth is `MALLOC_LARGE`, about two 250 KB allocations per class (2017 regions, 503 MB at N=1000).
- Apps with no classes of their own pay too. Expo's base classes go through the same `createClass`, and the patch lowers the N=0 baseline by 1.7 MiB on both platforms.
- Android TOTAL PSS is noisier. The first launch after each install reads 10 to 16 MiB higher, so the 1.7 MiB difference at N=0 is lost in TOTAL PSS. Native Heap PSS is the cleaner Android signal.

## Suggested fix

Evaluate one factory per runtime, cache it, and call it with the class name:

```js
(function (name) {
  const klass = function (...args) { return this.__native_constructor__(...args); };
  Object.defineProperty(klass, 'name', { value: name });
  return klass;
})
```

The repro's `patches/` apply this to both `createClass` functions. They cache the factory on `global` under one key, so the Swift and C++ paths share it on iOS. That key is a shortcut for the repro. Runtime-owned native state would keep user code from reaching or replacing the factory.

Constructors keep their `name`, `length`, prototype chain and `new` behavior. The Swift evaluation label for each class goes away, because only the factory is evaluated.

On iOS the patch only takes effect for the C++ path when `ExpoModulesCore` builds from source (`expo.autolinking.ios.buildFromSource`). The prebuilt `ExpoModulesWorklets` then has to build from source too, or the app fails at launch with `Library not loaded: @rpath/ExpoModulesCore.framework`.

## References

- https://github.com/expo/expo/issues/46519 (Hermes V1 memory regression, locked)
- https://github.com/facebook/hermes/issues/2048 (Severe memory regression in V1)
- https://github.com/facebook/hermes/pull/2090, "Avoid storing Module/SemContext in non-debug global eval" (backport of https://github.com/facebook/hermes/pull/2053). It ships in `hermes-v250829098.0.15` and later, so the Hermes in this repro has it. Its description says sources that are still compiled lazily keep this data. The sources here are one-line functions and still cost 0.57 MiB each.
- https://github.com/software-mansion/react-native-reanimated/issues/9650 (worklets hits the same Hermes V1 per-eval cost when it evaluates its helper scripts one by one)
