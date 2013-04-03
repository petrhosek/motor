import 'package:unittest/unittest.dart';
import 'package:motor/parser.dart';

/**
 * Parser test.
 */
main() {
  group('packets', () {
    group('basic functionality', () {
      test('should encode packets as strings', () {
        expect(Parser.encodePacket({ 'type': 'message', 'data': 'test' }), new isInstanceOf<String>());
      });

      test('should decode packets as objects', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'message', 'data': 'test' })), new isInstanceOf<Object>());
      });
    });

    group('encoding and decoding', () {
      test('should allow no data', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'message' })), equals({ 'type': 'message' }));
      });

      test('should encode an open packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'open', 'data': '{"some":"json"}' })),
            equals({ 'type': 'open', 'data': '{"some":"json"}' }));
      });

      test('should encode a close packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'close' })),
            equals({ 'type': 'close' }));
      });

      test('should encode a ping packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'ping', 'data': '1' })),
            equals({ 'type': 'ping', 'data': '1' }));
      });

      test('should encode a pong packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'pong', 'data': '1' })),
            equals({ 'type': 'pong', 'data': '1' }));
      });

      test('should encode a message packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'message', 'data': 'aaa' })),
            equals({ 'type': 'message', 'data': 'aaa' }));
      });

      test('should encode a message packet coercing to string', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'message', 'data': 1 })),
            equals({ 'type': 'message', 'data': '1' }));
      });

      test('should encode an upgrade packet', () {
        expect(Parser.decodePacket(Parser.encodePacket({ 'type': 'upgrade' })),
            equals({ 'type': 'upgrade' }));
      });

      test('should match the encoding format', () {
        expect(Parser.encodePacket({ 'type': 'message', 'data': 'test' }), matches(r'^[0-9]'));
        expect(Parser.encodePacket({ 'type': 'message' }), matches(r'^[0-9]$'));
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
        expect(Parser.encodePayload([{ 'type': 'ping' }, { 'type': 'post' }]), new isInstanceOf<String>());
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
          expect(packet['type'], equals('open'));
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