library transport;

/*class Event {
  static const Event empty = const Event();
  const Event();
}*/

/*class EventStream<T> {
  StreamController<T> _controller = new StreamController<T>.broadcast();
  Stream<T> get stream => _controller.stream;
  
  emit([T value]) {
    _controller.add(?value ? value : Event.empty);
  }
}*/

abstract class Transport extends Stream {
  static const int CLOSED = 0;
  static const int OPENING = 1;
  static const int OPEN = 2;
  static const int PAUSING = 3;
  static const int PAUSED = 4;
  static const int CLOSING = 5;
  
  final StreamController<OpenEvent> openEvent = new StreamController<Event>.broadcast();
  final StreamController<CloseEvent> closeEvent = new StreamController<Event>.broadcast();
  final StreamController<PacketEvent> packetEvent = new StreamController<PacketEvent>.broadcast();
  final StreamController<DrainEvent> drainEvent = new StreamController<Event>.broadcast();
  final StreamController<ErrorEvent> errorEvent = new StreamController<ErrorEvent>.broadcast();
  
  Transport(Uri uri, {bool this.timestampRequests: false,
                      String this.timestampParam: ''}) {
    _path = opts.path;
    _hostname = opts.hostname;
    _port = opts.port;
    _secure = opts.secure;
    _query = opts.query;
    writable = false;
  }
  
  /// Transport name.
  String get name;
  
  Stream<Event> get onOpen => openEvent.stream;
  Stream<Event> get onClose => closeEvent.stream;
  Stream<PacketEvent> get onPacket => packetEvent.stream;
  Stream<Event> get onDrain => drainEvent.stream;
  Stream<ErrorEvent> get onError => errorEvent.stream;
  
  StreamSubscription listen(void onData(message),
                            {void onError(AsyncError error),
                             void onDone(),
                             bool unsubscribeOnError}) {
    return _controller.stream.listen(onData,
                                     onError: onError,
                                     onDone: onDone,
                                     unsubscribeOnError: unsubscribeOnError);
  }
  
  /**
   * Emits an error.
   *
   * @param {String} str
   * @return {Transport} for chaining
   */
  void _onError(String msg, String desc) {
    var err = new Error(msg);
    err.type = 'TransportError';
    err.description = desc;
    emit('error', err);
  }
  
  /**
   * Opens the transport.
   */
  void open() {
    if (readyState == CLOSED) {
      readyState = OPENING;
      doOpen();
    }
  }
  
  /**
   * Opens socket.
   */
  void doOpen();
  
  /**
   * Closes the transport.
   */
  void close() {
    if (readyState == OPENING || readyState == OPEN) {
      doClose();
      _onClose();
    }
  }
  
  /**
   * Closes socket.
   */
  void doClose();
  
  /**
   * Writes array of [packets] to socket.
   */
  void write(List packets);
  
  /**
   * Sends multiple [packets].
   */
  void send(List packets) {
    if (readyState == OPEN) {
      write(packets);
    } else {
      throw new Error('Transport not open');
    }
  }
  
  /**
   * Called upon open
   *
   * @api private
   */
  void _onOpen() {
    readyState = OPEN;
    writable = true;
    //emit('open');
    openEvent.add(Event.empty);
  }
  
  /**
   * Called with data.
   *
   * @param {String} data
   * @api private
   */
  void _onData(data) {
    _onPacket(Parser.decodePacket(data));
  }
  
  /**
   * Called with a decoded packet.
   */
  void _onPacket(packet) {
    //emit('packet', packet);
    packetEvent.add(packet);
  }
  
  /**
   * Called upon close.
   */
  void _onClose() {
    readyState = CLOSED;
    //emit('close');
    closeEvent.add(Event.empty);
  }

  String _path;
  String _hostname;
  String _port;
  String _secure;
  String _query;
  Uri uri;
  bool timestampRequests;
  String timestampParam;
  int readyState = CLOSED;
  bool writable = false;
}

