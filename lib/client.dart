library motor.client;

import 'dart:async';
import 'dart:html';
import 'dart:json';
import 'dart:uri';

//import 'package:logging/logging.dart';

import 'src/query_utils.dart' as query_utils;
import 'parser.dart';

//part 'client/socket.dart';
//part 'client/transport.dart';

abstract class Socket implements Stream {
  static const int CONNECTING = 0;
  static const int OPENING = 1;
  static const int OPEN = 2;
  static const int CLOSING = 3;
  static const int CLOSED = 4;
  
  /**
   * Create a new socket connection. The URL supplied in [url]
   * must use the scheme [:ws:] or [:wss:]. The [transports] argument is either
   * a [:String:] or [:List<String>:] specifying the transports the
   * client is willing to speak.
   */
  static Future<Socket> connect(String url, [transports = const <String>[/*'polling',*/'websocket']]) =>
      _Socket.connect(url, transports);
  
  /**
   * Returns the protocol version
   */
  int get protocol;
  
  /**
   * Closes the connection.
   */
  void close();
  
  /**
   * Sends a message.
   */
  Future send(data);
}

class SocketException implements Exception {
  const SocketException([String this.message = ""]);
  String toString() => "SocketException: $message";
  final String message;
}

/*class _SocketTransformer extends StreamEventTransformer {
  static const int START = 0;
  
  _SocketTransformer(Transport this._transport) {
    
  }
  
  void handleData(Packet packet, EventSink sink) {
    // TODO: shall we only parse the data here?
    _heartbeat.add(null);
    try {
      switch (packet.type) {
        case PacketType.OPEN:
          _onHandshake(parse(packet.data), sink);
          break;
        case PacketType.PONG:
          onPing();
          break;
        // TODO: we should use stream errors in the parser
        //case PacketType.ERROR:
        //  sink.addError(new AsyncError(packet['data']));
        //  break;
        case PacketType.MESSAGE:
          sink.add(packet.data);
          break;
      }
    } on Exception {
    
    }
  }
  
  void _onHandshake(Map data, EventSink sink) {
    _id = data['sid'];
    _transport.query.sid = data['sid'];
    _upgrades = filterUpgrades(data['upgrades']);
    _pingInterval = data['pingInterval'];
    _pingTimeout = data['pingTimeout'];
    onOpen();
    onPing();
    heartbeat.listen(onHeartbeat);
  }
  
  void handleDone(EventSink sink) {
    // TODO: do we need this?
  }
  
  StreamController _heartbeat = new StreamController();
  Stream get heartbeat => _heartbeat.stream;
  
  Transport _transport;
  int _state;
  String _id;
  
  Function onOpen;
  Function onPing;
  Function onPong;
}*/

class _Socket extends Stream implements Socket {
  final StreamController _controller = new StreamController();
  
  static Future<Socket> connect(String url, transports, {bool upgrade,
                                                         bool timestampRequests,
                                                         String timestampParam}) {
    Uri uri = Uri.parse(url);
    
    /*Completer completer = new Completer();
    Transport.connect(transports[0], uri.toString()).then((transport) {
      (_) => completer.complete(new _Socket.withTransport(transport));
    });
    return completer.future;*/
    return new Future.value(new _Socket.withType(url, transports));
  }
  
  _Socket.withType(String this.url, this.transports, {bool this.upgrade,
                                                      bool this.timestampRequests: false,
                                                      String this.timestampParam: 't'}) {
    _readyState = Socket.OPENING;
    Transport.connect(transports[0], url).then((transport) {
      _setTransport(transport);
    });
  }
  
  _setTransport(Transport transport) {
    //if (_transport != null) {
    //  _logger.fine('clearing existing transport');
    //  _transport.removeAllListeners();
    //}
  
    // set up transport
    _transport = transport;
    _subscription = transport.listen(
        (data) => _controller.add(data),
        onError: (error) {
          _controller.addError(error);
          _close();
        },
        onDone: _close);
  }
  
  StreamSubscription listen(void onData(message),
                            {void onError(error),
                             void onDone(),
                             bool cancelOnError}) {
    return _controller.stream.listen(onData,
                                     onError: onError,
                                     onDone: onDone,
                                     cancelOnError: cancelOnError);
  }
  
  int get protocol => Parser.protocol;
  
  void _probe(name) {
    //var transport = createTransport(name, { 'probe': 1 });
    bool failed = false;
    Transport.connect(name, url).then((transport) {
      if (failed) return;
      var subscription = transport.take(1).listen(
          (packet) {
            if (failed) return;
            if (packet.type == PacketType.PONG && packet.data == 'probe') {
              _upgrading = true;
              // emit upgrading
              //_upgrade(transport);
            }
            // replace current transport
            _subscription.pause();
            if (_readyState > Socket.OPEN) return;
            // emit upgrade
            _setTransport(transport);
            transport.send(new Packet(PacketType.UPGRADE));
            _upgrading = false;
            _flush();
          },
          onError: (error) {
            if (failed) return;
            failed = true;
            transport.close();
          });
      transport.send(new Packet(PacketType.PING, 'probe'));
      
      once('close', () {
        if (transport != null) {
          _logger.fine('socket closed prematurely - aborting probe');
          failed = true;
          transport.close();
          transport = null;
        }
      });
      
      once('upgrading', (to) {
        if (transport != null && to.name != transport.name) {
          _logger.fine('"${to.name}" works - aborting "${transport.name}"');
          transport.close();
          transport = null;
        }
      });
    });
  }
  
  void _onOpen() {
    _readyState = Socket.OPEN;
    _flush();
    if (upgrade && _transport.pause) {
      _upgrades.forEach((u) => probe(u));
    }
  }
  
  void _onPacket(Packet packet, EventSink sink) {
    // TODO: shall we only parse the data here?
    _heartbeat.add(null);
    try {
      switch (packet.type) {
        case PacketType.OPEN:
          _onHandshake(parse(packet.data), sink);
          break;
        case PacketType.PONG:
          onPing();
          break;
        // TODO: we should use stream errors in the parser
        //case PacketType.ERROR:
        //  sink.addError(new AsyncError(packet['data']));
        //  break;
        case PacketType.MESSAGE:
          sink.add(packet.data);
          break;
      }
    } on Exception {
    
    }
  }
  
  /**
   * Resets ping timeout.
   */
  void _onHeartbeat([int timeout]) {
    if (_pingTimeoutTimer != null) _pingTimeoutTimer.cancel();
    timeout = ?timeout ? timeout : _pingInterval + _pingTimeout;
    _pingTimeoutTimer = new Timer(new Duration(milliseconds: timeout), () {
      if (_readyState == Socket.CLOSED) return;
      _close();
    });
  }
  
  /**
   * Pings server every [_pingInterval] and expects response
   * within [_pingTimeout] or closes connection.
   */
  void _onPing() {
    if (_pingIntervalTimer != null) _pingIntervalTimer.cancel();
    _pingIntervalTimer = new Timer(new Duration(milliseconds: _pingInterval), () {
      _send(PacketType.PING);
      _onHeartbeat(_pingTimeout);
    });
  }
  
  void close() {
    //if (_readyState < Socket.CLOSING) _readyState = Socket.CLOSING;
    if (_readyState > Socket.OPEN) return;
    _transport.close();
  }
  
  void _close([String reason, String desc]) {
    if (_readyState != Socket.OPEN) return;
    
    _readyState = Socket.CLOSED;
    if (_pingIntervalTimer != null) _pingIntervalTimer.cancel();
    if (_pingTimeoutTimer != null) _pingTimeoutTimer.cancel();
    new Future.delayed(new Duration(), () {
      _writeBuffer.clear();
      _callbackBuffer.clear();
    });
    _controller.close();
    _id = null;
  }
  
  Future send(data) {
    if (_readyState != Socket.OPEN) {
      throw new Exception('Socket not open');
    }
    return _send(PacketType.MESSAGE, data);
  }
  
  Future _send(int type, [data = null]) {
    var packet = new Packet(type, data);
    _writeBuffer.add(packet);
    var completer = new Completer();
    _callbackBuffer.add(completer);
    _flush();
    return completer.future;
  }
  
  void _flush() {
    if (_readyState != Socket.CLOSED && _transport.writable && !_upgrading && !_writeBuffer.isEmpty) {
      _transport.send(_writeBuffer);
      // keep track of current length of writeBuffer
      // splice writeBuffer and callbackBuffer on `drain`
      _prevBufferLen = _writeBuffer.length;
    }
  }
  
  StreamSubscription _subscription;
  
  String url;
  Uri uri;
  bool upgrade;
  bool forceJSONP;
  bool timestampRequests;
  String timestampParam;
  String flashPath;
  int policyPort;
  List<String> transports;
  
  String _id;
  
  Transport _transport;
  int _readyState;
  
  List _upgrades;
  
  int _prevBufferLen;
  List _writeBuffer;
  List<Completer> _callbackBuffer;
  
  int _pingInterval;
  Timer _pingIntervalTimer;
  int _pingTimeout;
  Timer _pingTimeoutTimer;
  
  bool _upgrading;
}

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
  
  static Future<Transport> connect(String url, {bool timestampRequests: false,
                                                String timestampParam: ''}) {
    Uri uri = Uri.parse(url);
    
    var query = query_utils.parse(uri.query);
    if (timestampRequests) {
      query[timestampParam] = new DateTime.now();
    }
    
    uri = new Uri.fromComponents(scheme: uri.scheme,
                                 userInfo: uri.userInfo,
                                 domain: uri.domain,
                                 port: uri.port,
                                 path: uri.path,
                                 query: query_utils.stringify(query),
                                 fragment: uri.fragment);
    
    //Completer completer = new Completer();
    WebSocket socket = new WebSocket(uri.toString());
    /*socket.onOpen.listen(
        (_) => completer.complete(new _WebSocketTransport._fromSocket(socket)));
    return completer.future;*/
    return new Future.value(new _WebSocketTransport._fromSocket(socket));
  }
  
  _WebSocketTransport._fromSocket(WebSocket this._socket, {bool this.timestampRequests: false,
                                                           String this.timestampParam: ''}) {
    _socket.onOpen.listen((_) =>
        _readyState = Transport.OPEN);
    _socket.onClose.listen((_) {
      _readyState = Transport.CLOSED;
      if (_bufferTimer != null) _bufferTimer.cancel();
      _controller.close();
    });
    _socket.onMessage.listen((e) =>
        _controller.add(Parser.decodePacket(e.data)));
    _socket.onError.listen((e) =>
        _controller.addError(e.message));
  }
  
  StreamSubscription listen(void onData(message),
                            {void onError(error),
                             void onDone(),
                             bool cancelOnError}) {
    return _controller.stream.listen(onData,
                                     onError: onError,
                                     onDone: onDone,
                                     cancelOnError: cancelOnError);
  }
  
  String get type => "websocket";
  int get readyState => _readyState;
  
  void close() {
    if (_readyState < Transport.CLOSING) _readyState = Transport.CLOSING;
    _socket.close();
  }
  
  Future send(data) {
    if (_readyState != Transport.OPEN) {
      throw new Exception('Transport not open');
    }
    Completer completer = new Completer();
    if (!_writable) {
      
    }
    _writable = false;
    // encodePacket is efficient as it uses WS framing so no need for encodePayload
    if (data is Packet) {
      _socket.send(Parser.encodePacket(data));
    } else if (data is List<Packet>) {
      data.forEach((p) => _socket.send(Parser.encodePacket(p)));
    }
    // check periodically if we're done sending
    _bufferTimer = new Timer.periodic(new Duration(milliseconds:50), (timer) {
      if (_socket.bufferedAmount == 0) {
        timer.cancel();
        _writable = true;
        completer.complete();
      }
    });
    return completer.future;
  }
}

class _PollingTransport extends Stream implements Transport {
  final StreamController _controller = new StreamController();
  
  int _readyState = Transport.CLOSED;
  bool _writable = false;
  bool _polling = false;
  
  bool timestampRequests;
  String timestampParam;
  String url;
  
  _PollingTransport(String this.url, {bool this.timestampRequests: false,
                                      String this.timestampParam: ''}) {
  }
  
  static Future<Transport> connect(String url, {bool timestampRequests: false,
                                                String timestampParam: ''}) {
    Uri uri = Uri.parse(url);
    if (uri.scheme != "http" && uri.scheme != "https") {
      throw new Exception("Unsupported URL scheme '${uri.scheme}'");
    }
    
    /*String query = uri.query;
    if (timestampRequests) {
      var timestamp = new DateTime.now().toString();
      if (!query.isEmpty) query += '&';
      query += '${encodeUriComponent(timestampParam)}=${encodeUriComponent(timestamp)}';
    }*/
    var query = query_utils.parse(uri.query);
    if (timestampRequests) {
      query[timestampParam] = new DateTime.now();
    }
    
    uri = new Uri.fromComponents(scheme: uri.scheme,
                                 userInfo: uri.userInfo,
                                 domain: uri.domain,
                                 port: uri.port,
                                 path: uri.path,
                                 query: query_utils.stringify(query),
                                 fragment: uri.fragment);
    
    Completer completer = new Completer();
    return completer.future;
  }
  
  _PollingTransport.from() {
    if (_readyState != Transport.CLOSED) {
      throw new Exception('Transport already open');
    }
    _readyState = Transport.OPENING;
    poll();
  }
  
  void poll() {
    _polling = true;
    _poll();
  }
  
  void _poll() {
    var req = new HttpRequest();
    req.onError.listen((e) => _controller.addError('XHR poll error'));
    req.onLoad.listen((_) {
      Parser.decodePayload(req.responseText, (packet, index, total) {
        if (_readyState == Transport.OPENING) {
          _readyState = Transport.OPEN;
          _writable = true;
        }
        if (packet.type == Packet.CLOSE) {
          _readyState = Transport.CLOSED;
          _controller.close();
          return false; // TODO: use stream in decodePayload and close it here
        }
        _controller.add(packet);
      });

      if (_readyState != Transport.CLOSED) {
        _polling = false;
        if (_readyState == Transport.OPEN) {
          poll();
        }
      }
      //_controller.add(Parser.decodePacket(req.responseText));
    });
    req.onLoadEnd.listen((_) => _polling = false);
    req.open('GET', url);
    req.send();
  }
  
  StreamSubscription listen(void onData(message),
                            {void onError(error),
                             void onDone(),
                             bool cancelOnError}) {
    return _controller.stream.listen(onData,
                                     onError: onError,
                                     onDone: onDone,
                                     cancelOnError: cancelOnError);
  }
  
  String get type => "websocket";
  int get readyState => _readyState;
  
  void close() {
    if (_readyState < Transport.CLOSING) _readyState = Transport.CLOSING;
    send(new Packet(Packet.CLOSE));
  }
  
  Future send(packet) {
    if (_readyState != Transport.OPEN) {
      throw new Exception('Transport not open');
    }
    String data;
    if (packet is Packet) {
      data = Parser.encodePacket(packet);
    } else if (packet is List<Packet>) {
      data = Parser.encodePayload(packet);
    }
    return _send(data);
  }
  
  // Future _send(int type, [String data])
  Future _send(String data) {
    if (!_writable) return new Future.immediate(null);
    _writable = false;
    var completer = new Completer();
    var req = new HttpRequest();
    req.onError.listen((e) => _controller.addError('XHR post error'));
    req.onLoad.listen((_) {
      _writable = true;
      completer.complete();
    });
    req.open('POST', url);
    req.send(data);
    return completer.future;
  }
}