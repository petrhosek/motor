library socket;

abstract class Socket extends EventEmitter {
  
  Transport _transport;
  Logger _logger = new Logger('Socket');
  
  /**
   * Client class (abstract).
   */
  Socket(id, server, transport) {
    this.id = id;
    this.server = server;
    this.upgraded = false;
    this.readyState = 'opening';
    this.writeBuffer = [];
    this.packetsFn = [];
    this.sentCallbackFn = [];

    this.setTransport(transport);
    this.onOpen();
  }
  
  /**
   * Accessor for request that originated socket.
   */
  get request => _transport.request;

  /**
   * Called upon transport considered open.
   * @private
   */
  onOpen() {
    this.readyState = 'open';

    // sends an `open` packet
    this.transport.sid = this.id;
    this.sendPacket('open', JSON.stringify({
      'sid': this.id,
      'upgrades': this.getAvailableUpgrades(),
      'pingInterval': this.server.pingInterval,
      'pingTimeout': this.server.pingTimeout
    }));
  
    this.emit('open');
    this.setPingTimeout();
  }

  /**
   * Called upon transport packet.
   *
   * @param {Object} packet
   * @api private
   */
  onPacket(packet) {
    if ('open' == this.readyState) {
      // export packet event
      debug('packet');
      this.emit('packet', packet);
  
      // Reset ping timeout on any packet, incoming data is a good sign of
      // other side's liveness
      this.setPingTimeout();
  
      switch (packet.type) {
  
        case 'ping':
          debug('got ping');
          this.sendPacket('pong');
          this.emit('heartbeat');
          break;
  
        case 'error':
          this.onClose('parse error');
          break;
  
        case 'message':
          this.emit('data', packet.data);
          this.emit('message', packet.data);
          break;
      }
    } else {
      debug('packet received with closed socket');
    }
  }
  
  /**
   * Called upon transport error.
   *
   * @param {Error} error object
   * @api private
   */
  onError(err) {
    debug('transport error');
    this.onClose('transport error', err);
  }
  
  /**
   * Sets and resets ping timeout timer based on client pings.
   *
   * @api private
   */
  setPingTimeout() {
    var self = this;
    clearTimeout(self.pingTimeoutTimer);
    self.pingTimeoutTimer = setTimeout(() {
      self.onClose('ping timeout');
    }, self.server.pingInterval + self.server.pingTimeout);
  }
  
  /**
   * Attaches handlers for the given transport.
   *
   * @param {Transport} transport
   * @api private
   */
  setTransport(transport) {
    this.transport = transport;
    this.transport.once('error', this.onError.bind(this));
    this.transport.on('packet', this.onPacket.bind(this));
    this.transport.on('drain', this.flush.bind(this));
    this.transport.once('close', this.onClose.bind(this, 'transport close'));
    //this function will manage packet events (also message callbacks)
    this.setupSendCallback();
  }
  
  /**
   * Upgrades socket to the given transport
   *
   * @param {Transport} transport
   * @api private
   */
  maybeUpgrade(transport) {
    debug('might upgrade socket transport from "%s" to "%s"'
      , this.transport.name, transport.name);
  
    // set transport upgrade timer
    var checkInterval;
    var upgradeTimeout = setTimeout(function () {
      debug('client did not complete upgrade - closing transport');
      clearInterval(checkInterval);
      if ('open' == transport.readyState) {
        transport.close();
      }
    }, this.server.upgradeTimeout);
  
    var self = this;
    function onPacket (packet) {
      if ('ping' == packet.type && 'probe' == packet.data) {
        transport.send([{ 'type': 'pong', data: 'probe' }]);
  
        // we force a polling cycle to ensure a fast upgrade
        function check () {
          if ('polling' == self.transport.name && self.transport.writable) {
            debug('writing a noop packet to polling for fast upgrade');
            self.transport.send([{ 'type': 'noop' }]);
          }
        }
  
        checkInterval = setInterval(check, 100);
      } else if ('upgrade' == packet.type && self.readyState == 'open') {
        debug('got upgrade packet - upgrading');
        self.upgraded = true;
        self.emit('upgrade', transport);
        self.clearTransport();
        self.setTransport(transport);
        self.setPingTimeout();
        self.flush();
        clearInterval(checkInterval);
        clearTimeout(upgradeTimeout);
        transport.removeListener('packet', onPacket);
      } else {
        transport.close();
      }
    }
    transport.on('packet', onPacket);
  }
  
  /**
   * Clears listeners and timers associated with current transport.
   *
   * @api private
   */
  clearTransport() {
    // silence further transport errors and prevent uncaught exceptions
    this.transport.on('error', () {
      debug('error triggered by discarded transport');
    });
    clearTimeout(this.pingIntervalTimer);
    clearTimeout(this.pingTimeoutTimer);
  }
  
  /**
   * Called upon transport considered closed.
   * Possible reasons: `ping timeout`, `client error`, `parse error`,
   * `transport error`, `server close`, `transport close`
   */
  onClose(reason, description) {
    if ('closed' != this.readyState) {
      var self = this;
      // clean writeBuffer in next tick, so developers can still
      // grab the writeBuffer on 'close' event
      process.nextTick(() {
        self.writeBuffer = [];
      });
      this.packetsFn = [];
      this.sentCallbackFn = [];
      this.clearTransport();
      this.readyState = 'closed';
      this.emit('close', reason, description);
    }
  }
  
  /**
   * Setup and manage send callback
   *
   * @api private
   */
  setupSendCallback() {
    var self = this;
    //the message was sent successfully, execute the callback 
    this.transport.on('drain', () {  
      if (self.sentCallbackFn.length > 0) {
        var seqFn = self.sentCallbackFn.splice(0,1)[0];
        if ('function' == typeof seqFn) {
          debug('executing send callback');
          seqFn(self.transport);
        } else if (Array.isArray(seqFn)) {
          debug('executing batch send callback');
          for (var i in seqFn) {
            if ('function' == typeof seqFn[i]) {
              seqFn[i](self.transport);
            }
          }
        }
      }
    });
  }
  
  /**
   * Sends a message packet.
   *
   * @param {String} message
   * @param {Function} callback
   * @return {Socket} for chaining
   * @api public
   */
  send(data, callback) {
    this.sendPacket('message', data, callback);
    return this;
  }
  
  /**
   * Sends a packet.
   *
   * @param {String} packet type
   * @param {String} optional, data
   * @api private
   */
  sendPacket(type, data, callback) {
    if ('closing' != this.readyState) {
      debug('sending packet "%s" (%s)', type, data);
  
      var packet = { 'type': type };
      if (data) packet.data = data;
  
      // exports packetCreate event
      this.emit('packetCreate', packet);
  
      this.writeBuffer.push(packet);
  
      //add send callback to object
      this.packetsFn.push(callback);
  
      this.flush();
    }
  }
  
  /**
   * Attempts to flush the packets buffer.
   *
   * @api private
   */
  flush() {
    if ('closed' != this.readyState && this.transport.writable
      && this.writeBuffer.length) {
      debug('flushing buffer to transport');
      this.emit('flush', this.writeBuffer);
      this.server.emit('flush', this, this.writeBuffer);
      var wbuf = this.writeBuffer;
      this.writeBuffer = [];
      if (!this.transport.supportsFraming) {
        this.sentCallbackFn.push(this.packetsFn);
      } else {
        this.sentCallbackFn.push.apply(this.sentCallbackFn, this.packetsFn);
      }
      this.packetsFn = [];
      this.transport.send(wbuf);
      this.emit('drain');
      this.server.emit('drain', this);
    }
  }
  
  /**
   * Get available upgrades for this socket.
   *
   * @api private
   */
  getAvailableUpgrades() {
    var availableUpgrades = [];
    var allUpgrades = this.server.upgrades(this.transport.name);
    for (var i = 0, l = allUpgrades.length; i < l; ++i) {
      var upg = allUpgrades[i];
      if (this.server.transports.indexOf(upg) != -1) {
        availableUpgrades.push(upg);
      }
    }
    return availableUpgrades;
  }
  
  /**
   * Closes the socket and underlying transport.
   *
   * @return {Socket} for chaining
   * @api public
   */
  close() {
    if ('open' == this.readyState) {
      this.readyState = 'closing';
      this.transport.close(() {
        onClose('forced close');
      });
    }
  }
}