import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View } from 'react-native';

import ClassBench from './modules/class-bench/src/ClassBenchModule';

// Requiring the module makes Expo create all of its classes. Touch each one so the
// screen proves they exist, and report whether the patched shared factory is in use.
const classCount = ClassBench.classCount;
let classesFound = 0;
for (let i = 0; i < classCount; i++) {
  if (typeof ClassBench[`Bench${i}`] === 'function') classesFound++;
}
const sharedFactory = typeof (globalThis as any).__expo_class_factory__ === 'function';
ClassBench.report(`classes=${classesFound}/${classCount} factory=${sharedFactory ? 'yes' : 'no'}`);

export default function App() {
  return (
    <View style={styles.container}>
      <Text testID="classes">{`classes: ${classesFound}/${classCount}`}</Text>
      <Text testID="factory">{`shared factory: ${sharedFactory ? 'yes' : 'no'}`}</Text>
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
