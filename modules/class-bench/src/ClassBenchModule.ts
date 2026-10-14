import { NativeModule, requireNativeModule } from 'expo';

declare class ClassBenchModule extends NativeModule {
  classCount: number;
  report(message: string): void;
  [className: `Bench${number}`]: unknown;
}

export default requireNativeModule<ClassBenchModule>('ClassBench');
