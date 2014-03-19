import 'package:unittest/unittest.dart';
import 'package:motor/parser.dart';

/**
 * Parser test.
 */
main() {
  group('packets', () {
    group('basic functionality', () {
      test('should encode packets as strings', () {
        expect(Parser.encodePacket(new Packet(Packet.MESSAGE, 'test')), new isInstanceOf<String>());
      });

      test('should decode strings as packets', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.MESSAGE, 'test'))), new isInstanceOf<Packet>());
      });
    });

    group('encoding and decoding', () {
      test('should allow no data', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.MESSAGE))), equals(new Packet(Packet.MESSAGE)));
      });

      test('should encode an open packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.OPEN, '{"some":"json"}'))),
            equals(new Packet(Packet.OPEN, '{"some":"json"}')));
      });

      test('should encode a close packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.CLOSE))),
            equals(new Packet(Packet.CLOSE)));
      });

      test('should encode a ping packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.PING, '1'))),
            equals(new Packet(Packet.PING, '1')));
      });

      test('should encode a pong packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.PONG, '1'))),
            equals(new Packet(Packet.PONG, '1')));
      });

      test('should encode a message packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.MESSAGE, 'aaa'))),
            equals(new Packet(Packet.MESSAGE, 'aaa')));
      });

      test('should encode a message packet coercing to string', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.MESSAGE, 1))),
            equals(new Packet(Packet.MESSAGE, '1')));
      });

      test('should encode an upgrade packet', () {
        expect(Parser.decodePacket(Parser.encodePacket(new Packet(Packet.UPGRADE))),
            equals(new Packet(Packet.UPGRADE)));
      });

      test('should match the encoding format', () {
        expect(Parser.encodePacket(new Packet(Packet.MESSAGE, 'test')), matches(r'^[0-9]'));
        expect(Parser.encodePacket(new Packet(Packet.MESSAGE)), matches(r'^[0-9]$'));
      });
    });

    group('decoding error handing', () {
      Map err = { 'type': 'error', 'data': 'parser error' };

      test('should disallow bad format', () {
        expect(Parser.decodePacket(':::'), equals(err));
      });

      test('should disallow inexistent types', () {
        expect(Parser.decodePacket('94103'), equals(err));
      });
    });
  });

  group('payloads', () {
    group('basic functionality', () {
      test('should encode payloads as strings', () {
        expect(Parser.encodePayload([new Packet(Packet.PING), new Packet(Packet.PONG)]), new isInstanceOf<String>());
      });
    });

    group('encoding and decoding', () {
      test('should encode/decode packets', () {
        Parser.decodePayload(Parser.encodePayload([{ 'type': 'message', 'data': 'a' }]),
            (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(isLast, isTrue);
        });
        Parser.decodePayload(Parser.encodePayload([{'type': 'message', 'data': 'a'}, {'type': 'ping'}]),
            (packet, index, total) {
          bool isLast = index + 1 == total;
          if (!isLast) {
            expect(packet['type'], equals('message'));
          } else {
            expect(packet['type'], equals('ping'));
          }
        });
      });

      test('should encode/decode empty payloads', () {
        Parser.decodePayload(Parser.encodePayload([]), (packet, index, total) {
          // TODO: should not be called
          expect(packet.type, equals(Packet.OPEN));
          var isLast = index + 1 == total;
          expect(isLast, isTrue);
        });
      });
    });

    group('decoding error handling', () {
      Map err = { 'type': 'error', 'data': 'parser error' };

      test('should err on bad payload format', () {
        Parser.decodePayload('1!', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
        Parser.decodePayload('', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
        Parser.decodePayload('))', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
      });

      test('should err on bad payload length', () {
        Parser.decodePayload('1:', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
      });

      test('should err on bad packet format', () {
        Parser.decodePayload('3:99:', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
        Parser.decodePayload('1:aa', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
        Parser.decodePayload('1:a2:b', (packet, index, total) {
          bool isLast = index + 1 == total;
          expect(packet, equals(err));
          expect(isLast, isTrue);
        });
      });
    });
  });
}