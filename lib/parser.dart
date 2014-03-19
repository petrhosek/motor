library motor.parser;

abstract class PacketType {
  static const int OPEN = 0;
  static const int CLOSE = 1;
  static const int PING = 2;
  static const int PONG = 3;
  static const int MESSAGE = 4;
  static const int UPGRADE = 5;
  static const int NOOP = 6;
}

class Packet {
  static const int OPEN = 0;
  static const int CLOSE = 1;
  static const int PING = 2;
  static const int PONG = 3;
  static const int MESSAGE = 4;
  static const int UPGRADE = 5;
  static const int NOOP = 6;
  
  final int type;
  final dynamic data;
  
  const Packet(this.type, [this.data]);
  
  Packet.from(Map<String, dynamic> map) :
    type = map['type'], data = map['data'];
  
  int get hashCode {
    int result = 17;
    result = 37 * result + type.hashCode;
    result = 37 * result + data.hashCode;
    return result;
  }
  
  bool operator==(other) {
    if (identical(other, this)) return true;
    return (other.type == type && other.data == data);
  }
}

class Parser {
  /// Protocol version
  static const int protocol = 2;
  
  /// Packet types
  static final packets = {
    'open': 0, // non-ws
    'close': 1, // non-ws
    'ping': 2,
    'pong': 3,
    'message': 4,
    'upgrade': 5,
    'noop': 6
  };
  static final packetslist = new List.from(packets.keys);
  
  /// Premade error packet
  static const Packet err = const Packet(-1, 'parser error');
 
  /**
   * Encodes a [packet].
   *
   *     <packet type id> [ `:` <data> ]
   *
   * Example:
   *
   *     5:hello world
   *     3
   *     4
   *
   */
  static String encodePacket(Packet packet) {
    StringBuffer encoded = new StringBuffer(packet.type);
    // data fragment is optional
    if (packet.data != null) {
      encoded.write(packet.data);
    }
    return encoded.toString();
  }

  /**
   * Decodes a packet [data].
   */
  static Packet decodePacket(String data) {
    try {
      int type = int.parse(data[0]);
      if (data.length > 1) {
        return new Packet(type, data.substring(1));
      } else {
        return new Packet(type);
      }
    } on FormatException {
      return err;
    } on RangeError {
      return err;
    }
  }

  /**
   * Encodes multiple [packets] (payload).
   *
   *     <length>:data
   *
   * Example:
   *
   *     11:hello world2:hi
   *
   */
  static String encodePayload(List<Packet> packets) {
    if (packets.isEmpty) return '0:';

    StringBuffer encoded = new StringBuffer();
    for (var i = 0; i < packets.length; i++) {
      String message = encodePacket(packets[i]);
      encoded.write('${message.length}:$message');
    }
    return encoded.toString();
  }

  /**
   * Decodes [data] when a payload is maybe expected.
   */
  static decodePayload(String data, callback(packet, index, total)) {
    if (data.isEmpty) return callback(err, 0, 1);

    String length = '';
    for (int i = 0; i < data.length; i++) {
      String chr = data[i];
      if (chr != ':') {
        length += chr;
      } else {
        int n;
        if (length.isEmpty || (n = int.parse(length, onError: (_) => -1)) == -1) {
          // parser error - ignoring payload
          return callback(err, 0, 1);
        }

        if (i + n >= data.length) {
          // parser error - ignoring payload
          return callback(err, 0, 1);
        }
        
        String message = data.substring(i + 1, i + 1 + n);
        if (message.length > 0) {
          Packet packet = decodePacket(message);
          if (packet == err) {
            // parser error in individual packet - ignoring payload
            return callback(err, 0, 1);
          }

          var ret = callback(packet, i + n, data.length);
          if (ret != null) return;
        }

        // advance cursor
        i += n;
        length = '';
      }
    }

    if (!length.isEmpty) {
      // parser error - ignoring payload
      return callback(err, 0, 1);
    }
  }
  
}