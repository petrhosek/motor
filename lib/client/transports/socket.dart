library client;

import 'dart:async';
import 'dart:json';
import 'dart:uri';

import 'package:logging/logging.dart';

import '../parser.dart';
import '../event.dart';
import 'transport.dart';  

/**
 * Noop function.
 *
 * @api private
 */
noop () {}

class Socket extends EventTarget {
  static const int CLOSED = 0;
  static const int OPENING = 1;
  static const int OPEN = 2;
  static const int CLOSING = 3;
  
  /// Protocol version
  int get protocol => Parser.protocol;
  
  Uri uri;
  bool upgrade;
  bool forceJSONP;
  bool timestampRequests;
  String timestampParam;
  String flashPath;
  int policyPort;
  List<String> transports;
  
  static const EventStreamProvider<T> openEvent = const EventStreamProvider<T>('open');
  Stream<T> get onopen => openEvent.forTarget(this);
  
  String _id;
  
  Transport _transport;
  String _readyState;
  
  List _upgrades;
  
  int _prevBufferLen;
  List _writeBuffer;
  List<Completer> _callbackBuffer;
  
  int _pingInterval;
  Timer _pingIntervalTimer;
  int _pingTimeout;
  Timer _pingTimeoutTimer;
  
  bool _upgrading;
  
  static List sockets = [];
  
  Logger _logger = new Logger('Socket');
  
  /**
   * Socket constructor.
   *
   * @param {String|Object} uri or options
   * @param {Object} options
   * @api public
   */
  Socket(String uri, {bool this.upgrade: true,
                      bool this.forceJSONP: true,
                      bool this.timestampRequests: false,
                      String this.timestampParam: '',
                      String this.flashPath: '',
                      int this.policyPort: 843,
                      List<String> this.transports: const <String>['polling', 'websocket', 'flashsocket']}) {
    _uri = new Uri.fromString(uri);
    /*if (uri) {
      uri = util.parseUri(uri);
      opts.host = uri.host;
      opts.secure = uri.protocol == 'https' || uri.protocol == 'wss';
      opts.port = uri.port;
      if (uri.query) opts.query = uri.query;
    }*/
  
    this.secure = null != opts.secure ? opts.secure :
      (global.location && 'https:' == location.protocol);
  
    if (opts.host) {
      var pieces = opts.host.split(':');
      opts.hostname = pieces.shift();
      if (pieces.length) opts.port = pieces.pop();
    }
  
    this.hostname = opts.hostname ||
      (global.location ? location.hostname : 'localhost');
    this.port = opts.port || (global.location && location.port ?
         location.port :
         (this.secure ? 443 : 80));
    this.query = opts.query || {};
    if ('string' == typeof this.query) this.query = util.qsParse(this.query);
    this.path = (opts.path || '/engine.io').replace(/\/$/, '') + '/';
    _readyState = '';
    _writeBuffer = [];
    _callbackBuffer = [];
    this.policyPort = opts.policyPort || 843;
    this.open();
  
    _sockets.add(this);
    Socket.sockets.evs.emit('add', this);
  }
  
  /**
   * Creates transport of the given type [name].
   */
  Transport _createTransport(name) {
    _logger.fine('creating transport "%s"', name);
    var query = clone(this.query);
  
    // append engine.io protocol identifier
    query.EIO = Parser.protocol;
  
    // transport name
    query.transport = name;
  
    // session id if we already have one
    if (this.id) query.sid = this.id;
  
    var transport = new transports[name](
      hostname: this.hostname,
      port: this.port,
      secure: this.secure,
      path: this.path,
      query: query,
      forceJSONP: this.forceJSONP,
      timestampRequests: timestampRequests,
      timestampParam: timestampParam,
      flashPath: this.flashPath,
      policyPort: this.policyPort
    );
  
    return transport;
  }
  
  /**
   * Initializes transport to use and starts probe.
   */
  open() {
    _readyState = 'opening';
    var transport = _createTransport(transports[0]);
    transport.open();
    _setTransport(transport);
  }
  
  /**
   * Sets the current [transport]. Disables the existing one (if any).
   */
  _setTransport(Transport transport) {
    if (_transport != null) {
      _logger.fine('clearing existing transport');
      _transport.removeAllListeners();
    }
  
    // set up transport
    _transport = transport;
  
    // set up transport listeners
    //transport.onDrain.listen((_) {});
    //transport.onPacket.listen((_) {});
    //transport.onError.listen((_) {});
    //transport.onClose.listen((_) {});
    transport
      .on('drain', () {
        this.onDrain();
      })
      .on('packet', (packet) {
        this.onPacket(packet);
      })
      .on('error', (e) {
        this.onError(e);
      })
      .on('close', () {
        this.onClose('transport close');
      });
  }
  
  /**
   * Probes a transport.
   *
   * @param {String} transport name
   * @api private
   */
  probe(name) {
    _logger.fine('probing transport "$name"');
    var transport = _createTransport(name, { 'probe': 1 });
    var failed = false;
  
    transport.once('open', () {
      if (failed) return;
  
      _logger.fine('probe transport "$name" opened');
      transport.send([{ 'type': 'ping', 'data': 'probe' }]);
      transport.once('packet', (msg) {
        if (failed) return;
        if ('pong' == msg.type && 'probe' == msg.data) {
          _logger.fine('probe transport "$name" pong');
          _upgrading = true;
          emit('upgrading', transport);
  
          _logger.fine('pausing current transport "${_transport.name}"');
          _transport.pause(() {
            if (failed) return;
            if ('closed' == _readyState || 'closing' == _readyState) {
              return;
            }
            _logger.fine('changing transport and sending upgrade packet');
            transport.removeListener('error', onerror);
            emit('upgrade', transport);
            _setTransport(transport);
            transport.send([{ 'type': 'upgrade' }]);
            transport = null;
            _upgrading = false;
            _flush();
          });
        } else {
          _logger.fine('probe transport "$name" failed');
          var err = new Error('probe error');
          err.transport = transport.name;
          emit('error', err);
        }
      });
    });
  
    transport.once('error', onerror);
    onerror(err) {
      if (failed) return;
  
      // Any callback called by transport should be ignored since now
      failed = true;
  
      var error = new Error('probe error: $err');
      error.transport = transport.name;
  
      transport.close();
      transport = null;
  
      _logger.fine('probe transport "$name" failed because of error: $err');
  
      emit('error', error);
    };
  
    transport.open();
  
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
  }
  
  /**
   * Called when connection is deemed open.
   */
  void onOpen() {
    _logger.fine('socket open');
    _readyState = 'open';
    emit('open');
    //this.onopen && this.onopen.call(this);
    _flush();
  
    // we check for `readyState` in case an `open` listener alreay closed the socket
    if ('open' == _readyState && upgrade && _transport.pause) {
      _logger.fine('starting upgrade probes');
      _upgrades.forEach((u) => probe(u));
    }
  }
  
  /**
   * Handles a [packet].
   */
  onPacket(packet) {
    if ('opening' == _readyState || 'open' == _readyState) {
      _logger.fine('socket receive: type "${packet.type}", data "${packet.data}"');
  
      emit('packet', packet);
  
      // Socket is live - any packet counts
      emit('heartbeat');
  
      switch (packet.type) {
        case 'open':
          onHandshake(parse(packet.data));
          break;
  
        case 'pong':
          this.ping();
          break;
  
        case 'error':
          var err = new Error('server error');
          err.code = packet.data;
          emit('error', err);
          break;
  
        case 'message':
          emit('data', packet.data);
          emit('message', packet.data);
          var event = { 'data': packet.data };
          event.toString = () {
            return packet.data;
          };
          //this.onmessage && this.onmessage.call(this, event);
          break;
      }
    } else {
      _logger.fine('packet received with socket readyState "$_readyState"');
    }
  }
  
  /**
   * Called upon handshake completion.
   *
   * @param {Object} handshake obj
   * @api private
   */
  void onHandshake(Map data) {
    emit('handshake', data);
    _id = data['sid'];
    _transport.query.sid = data['sid'];
    _upgrades = filterUpgrades(data['upgrades']);
    _pingInterval = data['pingInterval'];
    _pingTimeout = data['pingTimeout'];
    onOpen();
    ping();
  
    // Prolong liveness of socket on heartbeat
    removeListener('heartbeat', onHeartbeat);
    on('heartbeat', onHeartbeat);
  }
  
  /**
   * Resets ping timeout.
   */
  void onHeartbeat({int timeout: _pingInterval + _pingTimeout}) {
    if (_pingTimeoutTimer != null) {
      _pingTimeoutTimer.cancel();
    }
    _pingTimeoutTimer = new Timer(new Duration(milliseconds: timeout), () {
      if ('closed' == _readyState) return;
      onClose('ping timeout');
    });
  }
  
  /**
   * Pings server every [_pingInterval] and expects response
   * within [_pingTimeout] or closes connection.
   */
  void ping() {
    if (_pingIntervalTimer != null) {
      _pingIntervalTimer.cancel();
    }
    _pingIntervalTimer = new Timer(new Duration(milliseconds: _pingInterval), () {
      _logger.fine('writing ping packet - expecting pong within $_pingTimeout');
      sendPacket('ping');
      onHeartbeat(_pingTimeout);
    });
  }
  
  /**
   * Called on `drain` event.
   */
  onDrain() {
    _callbacks();
    _writeBuffer.removeRange(0, _prevBufferLen);
    _callbackBuffer.removeRange(0, _prevBufferLen);
    // setting prevBufferLen = 0 is very important
    // for example, when upgrading, upgrade packet is sent over,
    // and a nonzero prevBufferLen could cause problems on `drain`
    _prevBufferLen = 0;
    if (_writeBuffer.isEmpty) {
      emit('drain');
    } else {
      _flush();
    }
  }
  
  /**
   * Calls all the callback functions associated with sending packets.
   */
  _callbacks() =>
    _callbackBuffer.take(_prevBufferLen).forEach((c) => c.complete());
  
  /**
   * Flush write buffers.
   */
  void _flush() {
    if ('closed' != _readyState && _transport.writable &&
      !this.upgrading && !_writeBuffer.isEmpty) {
      _logger.fine('flushing ${_writeBuffer.length} packets in socket');
      _transport.send(_writeBuffer);
      // keep track of current length of writeBuffer
      // splice writeBuffer and callbackBuffer on `drain`
      _prevBufferLen = _writeBuffer.length;
      emit('flush');
    }
  }
  
  /**
   * Sends a [message].
   */
  Future write(msg) =>
    sendPacket('message', msg);
  
  /**
   * Sends a packet with [type] and [data].
   */
  Future sendPacket(String type, [String data = '']) {
    var packet = { 'type': type, 'data': data };
    emit('packetCreate', packet);
    _writeBuffer.add(packet);
    var completer = new Completer();
    _callbackBuffer.add(completer);
    flush();
    return completer.future;
  }
  
  /**
   * Closes the connection.
   */
  void close() {
    if ('opening' == _readyState || 'open' == _readyState) {
      onClose('forced close');
      _logger.fine('socket closing - telling transport to close');
      _transport.close();
      _transport.removeAllListeners();
    }
  }
  
  /**
   * Called upon transport error.
   */
  void onError(err) {
    _logger.fine('socket error $err');
    emit('error', err);
    onClose('transport error', err);
  }
  
  /**
   * Called upon transport close.
   */
  void onClose(String reason, [String desc]) {
    if ('opening' == _readyState || 'open' == _readyState) {
      _logger.fine('socket close with reason: "$reason"');
      if (_pingIntervalTimer != null) {
        _pingIntervalTimer.cancel();
      }
      if (_pingTimeoutTimer != null) {
        _pingTimeoutTimer.cancel();
      }
      // clean buffers in next tick, so developers can still
      // grab the buffers on `close` event
      new Future.delayed(new Duration(), () {
        _writeBuffer.clear();
        _callbackBuffer.clear();
      });
      _readyState = 'closed';
      emit('close', reason, desc);
      //this.onclose && this.onclose.call(this);
      _id = null;
    }
  }
  
  /**
   * Filters [upgrades], returning only those matching client transports.
   */
  List filterUpgrades(List<String> upgrades) =>
    upgrades.where((u) => transports.contains(u));

}

