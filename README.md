# Motor

[Motor](http://github.com/petrh/motor) is clone of
[Engine.IO](https://github.com/learnboost/engine.io) in Dart which aims
to be protocol-level compatible with the original implementation.

## Installing

First, add the library to the list of dependencies in your __pubspec.yaml__ file:

```yaml
motor:
    git: git://github.com/petrh/motor.git
```

Then, run `pub install` to install the package.

## Usage

Here is Motor used on server-side with Dart's built-in HTTP server:

```dart
#import('package:motor/server.dart');

main() {
  Motor.listen('127.0.0.1', 8080).then((server) {
    server.listen(
      (data) { /* Process data. */ },
      onError: (error) { /* Error on input. */ },
      onDone: () { /* No more data. */ });
    server.send('a string');
  });
}
```

The corresponding client-side code looks as follows:

```dart
#import('package:motor/client.dart');

void main() {
  Motor.connect('ws://localhost/').then((socket) {
    socket.listen(
      (data) { /* Process data. */ },
      onError: (error) { /* Error on input. */ },
      onDone: () { /* No more data. */ });
  });
}
```

## Contributing

Motor is at still at the early stage of development and all contribution
are more than welcome. Fork Motor on GitHub, make it awesomer and send a
pull request when it is ready.

Please note that one of the Motor's design goals is to use as many Dart
idioms as possible while retaining the Engine.IO compatibility.

## Contributors

* [petrh](http://github.com/petrh) ([+Petr Hosek](https://plus.google.com/u/0/110287390291502183886))

## License

This software is licensed under the MIT License.

Copyright Petr Hosek, 2013.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
