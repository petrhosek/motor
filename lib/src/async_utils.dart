// Copyright (c) 2013, Petr Hosek. All rights reserved.
// Use of this source code is governed by a MIT-style license.

library motor.async_utils;

import 'dart:async';

Future doWhile(Iterable iterable, Future<bool> action(i)) =>
    _doWhile(iterable.iterator, action);

Future _doWhile(Iterator iterator, Future<bool> action(i)) =>
  (iterator.moveNext())
      ? action(iterator.current).then((bool result) =>
        (result)
            ? _doWhile(iterator, action)
            : new Future.immediate(false))
      : new Future.immediate(false);