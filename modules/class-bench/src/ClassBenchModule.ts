import { NativeModule, requireNativeModule } from 'expo';

declare class ClassBenchModule extends NativeModule {
  classCount: number;
  [className: `Bench${number}`]: unknown;
}

export default requireNativeModule<ClassBenchModule>('ClassBench');
