library server;

/*var qs = require('querystring')
, parse = require('url').parse
, readFileSync = require('fs').readFileSync
, base64id = require('base64id')
, transports = require('./transports')
, EventEmitter = require('events').EventEmitter
, Socket = require('./socket')
, WebSocketServer = require('ws').Server
, debug = require('debug')('engine');*/

import 'package:logging/logging.dart';

import 'dart:async';
import 'dart:io';
import 'dart:json';

abstract class Motor {
  static const int UNKNOWN_TRANSPORT = 0;
  static const int UNKNOWN_SID = 1;
  static const int BAD_HANDSHAKE_METHOD = 2;

  /**
   * Creates an http.Server exclusively used for WS upgrades.
  *
   * @param {Number} port
   * @param {Function} callback
   * @param {Object} options
   * @return {Server} websocket.io server
   */
  static Future listen(port, {options, Function fn}) {
    return HttpServer.bind('127.0.0.1', port).then((server) {
      // create engine server
      var engine = attach(server, options);
      engine.httpServer = server;
      
      return engine;
    });
  }

  /**
   * Captures upgrade requests for a http.Server.
   *
   * @param {http.Server} server
   * @param {Object} options
   * @return {Server} engine server
   */
  static Motor attach(HttpServer server, {bool policyFile, List<String> transports, bool destroyUpgrade: true, int destroyUpgradeTimeout: 1000}) {
    var engine = new Server(options);
    var path = (options.path || '/engine.io').replace('/\/$/', '');

    // normalize path
    path += '/';

    check (req) {
      return path == req.url.substr(0, path.length);
    }

    // cache and clean up listeners
    var listeners = server.listeners('request').slice(0);
    server.removeAllListeners('request');

    // add request handler
    server.listen((HttpRequest request) {
      if (check(request)) {
        _logger.fine('intercepting request for path "$path"');
        engine.handleRequest(request, res); // TODO: use stream.liste?
      } else {
        for (var i = 0, l = listeners.length; i < l; i++) {
          listeners[i].call(server, req, res);
        }
      }
    }, onDone: () => engine.close());

    if (engine.transports.containsKey('websocket')) {
      server.transform(new WebSocketTransformer()).listen((WebSocket socket) {
        if (check(req)) {
          engine.handleUpgrade(socket);
        } else if (destroyUpgrade) {
          // default node behavior is to disconnect when no handlers
          // but by adding a handler, we prevent that
          // and if no eio thing handles the upgrade
          // then the socket needs to die!
          setTimeout(() {
            if (socket.writable && socket.bytesWritten <= 0) {
              return socket.end();
            }
          }, options.destroyUpgradeTimeout);
        }
      });
    }

    // flash policy file
    /*var trns = engine.transports;
    var policy = options.policyFile;
    if (~trns.indexOf('flashsocket') && false !== policy) {
      server.on('connection', (socket) {
        engine.handleSocket(socket);
      });
    }*/

    return engine;
  }
  
  /**
   * Returns the protocol version
   */
  int get protocol;

  /**
   * Invoking the library as a function delegates to attach
   *
   * @param {http.Server} server
   * @param {Object} options
   * @return {Server} engine server
   */
  Motor call(HttpServer server, options) => attach(server, options);
  
}

class _Motor implements Motor {
  
  Logger _logger = new Logger('Server');
  
  /**
   * Server constructor.
   *
   * @param {Object} options
   * @api public
   */
  _Motor(opts) {
    this.clients = {};
    this.clientsCount = 0;

    opts = opts || {};
    this.pingTimeout = opts.pingTimeout || 60000;
    this.pingInterval = opts.pingInterval || 25000;
    this.upgradeTimeout = opts.upgradeTimeout || 10000;
    this.transports = opts.transports || Object.keys(transports);
    this.allowUpgrades = false !== opts.allowUpgrades;
    this.cookie = false !== opts.cookie ? (opts.cookie || 'io') : false;

    // initialize websocket server
    if (~this.transports.indexOf('websocket')) {
      this.ws = new WebSocketServer({ noServer: true, clientTracking: false });
    }
  }

  /**
   * Protocol errors mappings.
   */
  static final Map errors = {
    'UNKNOWN_TRANSPORT': 0,
    'UNKNOWN_SID': 1,
    'BAD_HANDSHAKE_METHOD': 2
  };

  static final List errorMessages = [
    'Transport unknown',
    'Session ID unknown',
    'Bad handshake method'
  ];

  /// Hash of open clients
  Map _clients;

  /**
   * Returns a list of available transports for upgrade given a certain transport.
   *
   * @api public
   */
  List upgrades(transport) {
    if (!this.allowUpgrades) return [];
    return transports[transport].upgradesTo || [];
  }

  /**
   * Verifies a request.
   *
   * @param {http.ServerRequest}
   * @return whether the request is valid
   * @api private
   */
  bool verify(req) {
    // transport check
    var transport = req.query.transport;
    if (!~this.transports.indexOf(transport)) {
      _logger.fine('unknown transport "$transport"');
      return Motor.UNKNOWN_TRANSPORT;
    }

    // sid check
    if (req.query.sid) {
      return this.clients.hasOwnProperty(req.query.sid) ||
          Motor.UNKNOWN_SID;
    } else {
      // handshake is GET only
      return 'GET' == req.method ||
          Motor.BAD_HANDSHAKE_METHOD;
    }

    return true;
  }

  /**
   * Prepares a request by processing the query string.
   *
   * @api private
   */
  prepare(req) {
    // try to leverage pre-existing `req.query` (e.g: from connect)
    if (!req.query) {
      req.query = ~req.url.indexOf('?') ? qs.parse(parse(req.url).query) : {};
    }
  }

  /**
   * Closes all clients.
   *
   * @api public
   */
  close() {
    _logger.fine('closing all open clients');
    for (var i in this.clients) {
      this.clients[i].close();
    }
    return this;
  }

  /**
   * Handles an Engine.IO HTTP request.
   *
   * @param {http.ServerRequest} request
   * @param {http.ServerResponse|http.OutgoingMessage} response
   * @api public
   */
  handleRequest(req, res) {
    _logger.fine('handling "${req.method}" http request "${req.url}"');
    this.prepare(req);
    req.res = res;

    var code = this.verify(req);
    if (code != true) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(stringify({
        'code': code,
        'message': Server.errorMessages[code]
      }));
      return this;
    }

    if (req.query.sid) {
      _logger.fine('setting new request for existing client');
      this.clients[req.query.sid].transport.onRequest(req);
    } else {
      this.handshake(req.query.transport, req);
    }

    return this;
  }

  /**
   * Handshakes a new client.
   *
   * @param {String} transport name
   * @param {Object} request object
   * @api private
   */
  handshake(transport, req) {
    var id = base64id.generateId();

    _logger.fine('handshaking client "%s"', id);

    var transport = new transports[transport](req);
    var socket = new Socket(id, this, transport);
    var self = this;

    if (false != this.cookie) {
      transport.on('headers', (headers) {
        headers['Set-Cookie'] = self.cookie + '=' + id;
      });
    }

    transport.onRequest(req);

    _clients[id] = socket;
    _clientsCount++;
    //emit('connection', socket);
    emit(new Event('connection', socket));

    socket.once('close', () {
      _clients.remove(id);
      _clientsCount--;
    });
  }

  /**
   * Handles an Engine.IO HTTP Upgrade.
   *
   * @api public
   */
  handleUpgrade(req, socket, head) {
    this.prepare(req);

    if (this.verify(req) != true) {
      socket.end();
      return;
    }

    // delegate to ws
    this.ws.handleUpgrade(req, socket, head, (conn) {
      onWebSocket(req, conn);
    });
  }

  /**
   * Called upon a ws.io connection.
   *
   * @param {ws.Socket} websocket
   * @api private
   */
  onWebSocket(req, socket) {
    if (!transports[req.query.transport].prototype.handlesUpgrades) {
      _logger.fine('transport doesnt handle upgraded requests');
      socket.close();
      return;
    }

    // get client id
    var id = req.query.sid;

    // keep a reference to the ws.Socket
    req.websocket = socket;

    if (id) {
      if (!this.clients[id]) {
        _logger.fine('upgrade attempt for closed client');
        socket.close();
      } else if (this.clients[id].upgraded) {
        _logger.fine('transport had already been upgraded');
        socket.close();
      } else {
        _logger.fine('upgrading existing transport');
        var transport = new transports[req.query.transport](req);
        this.clients[id].maybeUpgrade(transport);
      }
    } else {
      this.handshake(req.query.transport, req);
    }
  }

  /**
   * Handles a regular connection to watch for flash policy requests.
   *
   * @param {net.Stream} socket
   * @api private
   */
  var policy = readFileSync(__dirname + '/transports/flashsocket.xml');

  handleSocket(socket) {
    socket.on('data', onData(data){
      // no need for buffering as node will discard subsequent packets
      // since they constitute a malformed HTTP request
      if (60 == data[0] && 23 == data.length) {
        var str = data.slice(0, 23).toString();
        if ('<policy-file-request/>\0' == str) {
          socket.end(policy);
        }
      }
      socket.removeListener('data', onData);
    });
  }
}