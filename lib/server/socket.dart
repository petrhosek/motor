library socket;

import 'dart:async';
import 'dart:io';
import 'dart:json';

import '../parser.dart';
import './transport.dart';

abstract class Socket implements Stream, StreamSink {
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
  static Future<Socket> connect(String url, [transports = const <String>['polling', 'websocket']]) =>
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

class _Socket extends Stream implements Socket {
  final StreamController _controller = new StreamController();
  
  String _id;
  Transport _transport;
  var _writeBuffer;
  List<Completer> _callbackBuffer;
  int _readyState;
  StreamSubscription _subscription;
  Timer _pingTimeoutTimer;
  
  static Future<Socket> connect(String url, transports, {bool upgrade,
                                                         bool timestampRequests,
                                                         String timestampParam}) {
    Uri uri = Uri.parse(url);
  }
  
  _Socket.withType(String this.url, {bool this.upgrade,
                                     bool this.timestampRequests: false,
                                     String this.timestampParam: 't'}) {
    _readyState = Socket.OPENING;
    Transport.connect('', url).then((transport) {
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
    //_setupSendCallback();
  }
  
  int get protocol => Parser.protocol;
  
  void _onOpen() {
    _readyState = Socket.OPEN;
    _send(PacketType.OPEN, stringify({
      'sid': _id,
      // if (upgrade && _transport.pause) {
      //  _upgrades.forEach((u) => probe(u));
      //}
      'upgrades': getAvailableUpgrades(),
      'pingInterval': _pingInterval,
      'pingTimeout': _pingTimeout
    }));
    _pingTimeout();
  }
  
  void _onPacket(Packet packet, EventSink sink) {
    if (_readyState != Socket.OPEN) return;
    
    _pingTimeout();
    
    // TODO: shall we only parse the data here?
    //_heartbeat.add(null);
    try {
      switch (packet.type) {
        case PacketType.PING:
          _send(PacketType.PONG);
          break;
        case PacketType.MESSAGE:
          sink.add(packet.data);
          break;
      }
    } on Exception {
    
    }
  }
  
  _pingTimeout() {
    if (_pingTimeoutTimer != null) _pingTimeoutTimer.cancel();
    _pingTimeoutTimer = new Timer(new Duration(milliseconds: _pingInterval + _pingTimeout), () {
      if (_readyState == Socket.CLOSED) return;
      _close();
    });
  }
  
  Future send(event) {
    if (_readyState != Socket.OPEN) {
      throw new Exception('Socket not open');
    }
    _send(PacketType.MESSAGE, event);
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
    if (_readyState != Socket.CLOSED && _transport.writable && !_writeBuffer.isEmpty) {
      //this.emit('flush', this.writeBuffer);
      //this.server.emit('flush', this, this.writeBuffer);
      var wbuf = this.writeBuffer;
      this.writeBuffer = [];
      if (!this.transport.supportsFraming) {
        this.sentCallbackFn.push(this.packetsFn);
      } else {
        this.sentCallbackFn.push.apply(this.sentCallbackFn, this.packetsFn);
      }
      this.packetsFn = [];
      _transport.send(_writeBuffer);
      //this.emit('drain');
      //this.server.emit('drain', this);
    }
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
  }
}