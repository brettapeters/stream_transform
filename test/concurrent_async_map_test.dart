// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';

import 'package:stream_transform/stream_transform.dart';

void main() {
  var streamTypes = {
    'single subscription': () => StreamController(),
    'broadcast': () => StreamController.broadcast()
  };
  StreamController streamController;
  List emittedValues;
  bool valuesCanceled;
  bool isDone;
  List errors;
  Stream transformed;
  StreamSubscription subscription;

  List<Completer> finishWork;
  List<dynamic> values;

  Future convert(dynamic value) {
    values.add(value);
    var completer = Completer();
    finishWork.add(completer);
    return completer.future;
  }

  for (var streamType in streamTypes.keys) {
    group('concurrentAsyncMap for stream type: [$streamType]', () {
      setUp(() {
        valuesCanceled = false;
        streamController = streamTypes[streamType]()
          ..onCancel = () {
            valuesCanceled = true;
          };
        emittedValues = [];
        errors = [];
        isDone = false;
        finishWork = [];
        values = [];
        transformed =
            streamController.stream.transform(concurrentAsyncMap(convert));
        subscription = transformed
            .listen(emittedValues.add, onError: errors.add, onDone: () {
          isDone = true;
        });
      });

      test('does not emit before convert finishes', () async {
        streamController.add(1);
        await Future(() {});
        expect(emittedValues, isEmpty);
        expect(values, [1]);
        finishWork.first.complete(1);
        await Future(() {});
        expect(emittedValues, [1]);
      });

      test('allows calls to convert before the last one finished', () async {
        streamController.add(1);
        streamController.add(2);
        streamController.add(3);
        await Future(() {});
        expect(values, [1, 2, 3]);
      });

      test('forwards errors directly without waiting for previous convert',
          () async {
        streamController.add(1);
        await Future(() {});
        streamController.addError('error');
        await Future(() {});
        expect(errors, ['error']);
      });

      test('forwards errors which occur during the convert', () async {
        streamController.add(1);
        await Future(() {});
        finishWork.first.completeError('error');
        await Future(() {});
        expect(errors, ['error']);
      });

      test('can continue handling events after an error', () async {
        streamController.add(1);
        await Future(() {});
        finishWork[0].completeError('error');
        streamController.add(2);
        await Future(() {});
        expect(values, [1, 2]);
        finishWork[1].completeError('another');
        await Future(() {});
        expect(errors, ['error', 'another']);
      });

      test('cancels value subscription when output canceled', () async {
        expect(valuesCanceled, false);
        await subscription.cancel();
        expect(valuesCanceled, true);
      });

      test('closes when values end if no conversion is pending', () async {
        expect(isDone, false);
        await streamController.close();
        await Future(() {});
        expect(isDone, true);
      });

      if (streamType == 'broadcast') {
        test('multiple listeners all get values', () async {
          var otherValues = [];
          transformed.listen(otherValues.add);
          streamController.add(1);
          await Future(() {});
          finishWork.first.complete('result');
          await Future(() {});
          expect(emittedValues, ['result']);
          expect(otherValues, ['result']);
        });

        test('multiple listeners get done when values end', () async {
          var otherDone = false;
          transformed.listen(null, onDone: () => otherDone = true);
          streamController.add(1);
          await Future(() {});
          await streamController.close();
          expect(isDone, false);
          expect(otherDone, false);
          finishWork.first.complete();
          await Future(() {});
          expect(isDone, true);
          expect(otherDone, true);
        });

        test('can cancel and relisten', () async {
          streamController.add(1);
          await Future(() {});
          finishWork.first.complete('first');
          await Future(() {});
          await subscription.cancel();
          streamController.add(2);
          await Future(() {});
          subscription = transformed.listen(emittedValues.add);
          streamController.add(3);
          await Future(() {});
          expect(values, [1, 3]);
          finishWork[1].complete('second');
          await Future(() {});
          expect(emittedValues, ['first', 'second']);
        });
      }
    });
  }
}
