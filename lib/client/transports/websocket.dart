library websocket;

class WebSocketTransport extends Transport {
  WebSocket _socket;
  Timer _bufferTimer;
  
  WebSocketTransport(opts) : super(opts);
  
  String get name => 'websocket';
  
  /**
   * Opens socket.
   */
  void doOpen() {
    if (!WebSocket.supported) {
      return;
    }
  
    _socket = new WebSocket(uri);
    _socket.onOpen.listen((_) => _onOpen());
    _socket.onClose.listen((_) => _onClose());
    _socket.onMessage.listen((ev) => _onData(ev.data));
    _socket.onError.listen((ev) => _onError('websocket error', ev));
  }
  
  void write(List packets) {
    writable = false;
    // encodePacket is efficient as it uses WS framing
    // no need for encodePayload
    packets.forEach((p) => _socket.send(Parser.encodePacket(p)));
    // check periodically if we're done sending
    _bufferTimer = new Timer.periodic(new Duration(milliseconds:50), (timer) {
      if (_socket.bufferedAmount == 0) {
        timer.cancel();
        writable = true;
        drainEvent.add(Event.empty);
        //emit('drain');
      }
    });
  }
  
  /**
   * Called upon close
   */
  void _onClose() {
    // stop checking to see if websocket is done sending buffer
    if (_bufferTimer != null) {
      _bufferTimer.cancel();
    }
    super._onClose();
  }
  
  /**
   * Closes socket.
   */
  void doClose() {
    if (_socket != null) {
      _socket.close();
    }
  }
  
  /// Generates uri for connection.
  String get uri {
    var query = _query;
    var schema = _secure ? 'wss' : 'ws';
    var port = '';
  
    // avoid port if default for schema
    if (('wss' == schema && _port != 443) ||
        ('ws' == schema && _port != 80)) {
      port = ':$_port';
    }
  
    // append timestamp to URI
    if (timestampRequests) {
      query[timestampParam] = new DateTime.now();
    }
  
    query = util.qs(query);
  
    // prepend ? to query
    if (!query.isEmpty) {
      query = '?' + query;
    }
    
    //return '$schema://$_hostname$port$_path$query';
    
    return new Uri.fromComponents(
        scheme: schema,
        domain: _hostname,
        port: _port,
        path: _path,
        query: query).toString();
  }
}

