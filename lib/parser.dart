library parser;

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
  static final err = { 'type': 'error', 'data': 'parser error' };
 
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
  static String encodePacket(Map<String, dynamic> packet) {
    StringBuffer encoded = new StringBuffer(packets[packet['type']]);

    // data fragment is optional
    if (packet['data'] != null) {
      encoded.write(packet['data']);
    }

    return encoded.toString();
  }

  /**
   * Decodes a packet [data].
   */
  static Map<String, dynamic> decodePacket(String data) {
    try {
      int type = int.parse(data[0]);
      if (data.length > 1) {
        return { 'type': packetslist[type], 'data': data.substring(1) };
      } else {
        return { 'type': packetslist[type] };
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
  static String encodePayload(List packets) {
    if (packets.isEmpty) {
      return '0:';
    }

    StringBuffer encoded = new StringBuffer();

    for (int i = 0; i < packets.length; i++) {
      String message = encodePacket(packets[i]);
      encoded.write('${message.length}:$message');
    }

    return encoded.toString();
  }

  /**
   * Decodes [data] when a payload is maybe expected.
   */
  static decodePayload(String data, bool callback(packet, index, total)) {
    Map<String, dynamic> packet;
    if (data.isEmpty) {
      // parser error - ignoring payload
      return callback(err, 0, 1);
    }

    String length = '';
    for (int i = 0; i < data.length; i++) {
      String chr = data[i];

      if (':' != chr) {
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
          packet = decodePacket(message);

          if (err['type'] == packet['type'] && err['data'] == packet['data']) {
            // parser error in individual packet - ignoring payload
            return callback(err, 0, 1);
          }

          bool ret = callback(packet, i + n, data.length);
          if (!ret) return;
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