library async;

import 'dart:async';
import 'dart:io';

import '../parser.dart';

abstract class Transport implements Stream {
  /**
   * Possible states of the transport.
   */
  static const int CONNECTING = 0;
  static const int OPENING = 1;
  static const int OPEN = 2;
  static const int PAUSING = 3;
  static const int PAUSED = 4;
  static const int CLOSING = 5;
  static const int CLOSED = 6;
  
  /**
   * Create a new web socket connection. The URL supplied in [url]
   * must use the scheme [:ws:] or [:wss:]. The [protocols] argument is either
   * a [:String:] or [:List<String>:] specifying the subprotocols the
   * client is willing to speak.
   */
  static Future<Transport> connect(String type, String url) {
    switch (type) {
      case 'polling':
        return _PollingTransport.connect(url);
      case 'websocket':
      default:
        return _WebSocketTransport.connect(url);
    }
  }
  
  /**
   * Returns the transport type.
   */
  String get type;
  
  /**
   * Returns the current state of the transport.
   */
  int get readyState;
  
  /**
   * Closes the transport.
   */
  void close();
  
  /**
   * Sends data through transport. The data in [data] must
   * be either a [:Map:], or a [:List<Map>:].
   */
  Future send(data);
}

class _WebSocketTransport extends Stream implements Transport {
  final StreamController _controller = new StreamController();
  
  WebSocket _socket;
  int _readyState = Transport.CONNECTING;
  bool _writable = false;
  Timer _bufferTimer;
  
  bool timestampRequests;
  String timestampParam;
  String url;
  
  _WebSocketTransport(String this.url, {bool this.timestampRequests: false,
                                        String this.timestampParam: ''}) {
  }
  
  static Future<Transport> connect(String url) {
    Uri uri = Uri.parse(url);
    
    // append timestamp to URI
    /*if (timestampRequests) {
      query[timestampParam] = new DateTime.now();
    }
    query = util.qs(query);*/
    // prepend ? to query
    /*if (!query.isEmpty) {
      query = '?' + query;
    }
    uri = new Uri.fromComponents();*/
    
    Completer completer = new Completer();
    WebSocket socket = new WebSocket(uri.toString());
    socket.onOpen.listen(
        (_) => completer.complete(new _WebSocketTransport._fromSocket(socket)));
    return completer.future;
  }
  
  _WebSocketTransport._fromSocket(WebSocket this._socket) {
    _socket.listen((e) => _controller.add(Parser.decodePacket(e.data)),
        onError: (e) => _controller.addError(e.message),
        onDone: () => _controller.close(),
        unsubscribeOnError: false);
  }
  
  StreamSubscription listen(void onData(message),
                            {void onError(error),
                             void onDone(),
                             bool unsubscribeOnError}) {
    return _controller.stream.listen(onData,
                                     onError: onError,
                                     onDone: onDone,
                                     unsubscribeOnError: unsubscribeOnError);
  }
  
  String get type => "websocket";
  int get readyState => _readyState;
  bool get handlesUpgrade => true;
  bool get supportsFraming => true;
  
  void close() {
    if (_readyState < Transport.CLOSING) _readyState = Transport.CLOSING;
    _socket.close();
  }
  
  send(data) {
    if (_readyState != Transport.OPEN) {
      throw new Exception('Transport not open');
    }
    if (data is Packet) {
      _socket.add(Parser.encodePacket(data));
    } else if (data is List<Packet>) {
      data.forEach((p) => _socket.add(Parser.encodePacket(p)));
    }
  }
  
}

class _PollingTransport extends Stream implements Transport {
  final StreamController _controller = new StreamController();
  
  int _readyState = Transport.CLOSED;
  bool _writable = false;
  bool _polling = false;
  
  String get type => "websocket";
  int get readyState => _readyState;
}