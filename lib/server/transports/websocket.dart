library websocket;

import 'transport.dart';
import '../../parser.dart';

import '../../../../dart/dart-sdk/lib/io/io.dart';

/**
 * WebSocket transport
 */
class WebSocketTransport extends Transport {
  WebSocket _socket;
  bool _writable;

  WebSocketTransport(HttpRequest req) :
    super(req) {
    _socket = req.websocket;
    _socket.listen(onData,
        onError: onError,
        onDone: onClose,
        unsubscribeOnError: false);
    
    /*_socket.on('message', this.onData.bind(this));
    _socket.once('close', this.onClose.bind(this));
    _socket.on('error', this.onError.bind(this));
    _socket.on('headers', (headers) {
      _emit('headers', headers);
    });*/
    _writable = true;
    
    /*_socket = req.wsclient;

    _socket.onclose = (event) {
      this.end('socket end');
    };
    _socket.onerror = (e) {
      this.end('socket error');
    };
    _socket.onmessage = (event) {
      this.onMessage(Parser.decodePacket(event.data));
    };*/
  }
  
  /**
   * Processes the incoming data.
   *
   * @param {String} encoded packet
   */
  onData(data) {
    _logger.fine('received "$data"');
    super.onData(data);
  }

  /**
   * Writes a packet payload.
   *
   * @param {Array} packets
   * @api private
   */
  send(packets) {
    for (int i = 0, l = packets.length; i < l; i++) {
      var data = Parser.encodePacket(packets[i]);
      _logger.fine('writing "$data"');
      _writable = false;
      try {
        _socket.send(data);
        _writable = true;
        emit('drain');
      } on WebSocketException catch (e) {
        onError('write error', e.message);
      }
    }
  }

  /**
   * Closes the transport.
   *
   * @api private
   */
  doClose([Function fn]) {
    _logger.fine('closing');
    _socket.close();
    if (?fn) {
      fn();
    }
  }
}