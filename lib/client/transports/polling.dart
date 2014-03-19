library polling;

import '../parser.dart';
import 'transport.dart';

class PollingTransport extends Transport {
  PollingTransport(opts) : super(opts);
  
  String get name => 'polling';
  
  /**
   * Opens the socket (triggers polling). We write a PING message to determine
   * when the transport is open.
   */
  void _doOpen() {
    poll();
  }
  
  /**
   * Pauses polling.
   */
  void pause(Function onPause) {
    int pending = 0;
    readyState = PAUSING;

    pause() {
      _logger.fine('paused');
      readyState = PAUSED;
      onPause();
    }

    if (_polling || !writable) {
      int total = 0;

      if (_polling) {
        _logger.fine('we are currently polling - waiting to pause');
        total++;
        once('pollComplete', () {
          _logger.fine('pre-pause polling complete');
          --total || pause();
        });
      }

      if (!writable) {
        _logger.fine('we are currently writing - waiting to pause');
        total++;
        once('drain', () {
          debug('pre-pause writing complete');
          --total || pause();
        });
      }
    } else {
      pause();
    }
  }
  
  /**
   * Starts polling cycle.
   */
  void poll() {
    _logger.fine('polling');
    _polling = true;
    this.doPoll();
    this.emit('poll');
  }
  
  /**
   * Overloads onData to detect payloads.
   */
  void onData(data) {
    _logger.debug('polling got data $data');

    // decode payload
    Parser.decodePayload(data, (packet, index, total) {
      // if its the first message we consider the transport open
      if (readyState == OPENING) {
        _onOpen();
      }

      // if its a close packet, we close the ongoing requests
      if (packet['type'] == 'close') {
        _onClose();
        return false;
      }

      // otherwise bypass onData and handle the message
      _onPacket(packet);
    });

    // if an event did not trigger closing
    if (readyState != CLOSED) {
      // if we got data we're not polling
      _polling = false;
      emit('pollComplete');

      if (readyState == OPEN) {
        poll();
      } else {
        _logger.fine('ignoring poll - transport state "$readyState"');
      }
    }
  }
  
  /**
   * For polling, send a close packet.
   */
  void doClose() {
    send([{ 'type': 'close' }]);
  }
  
  void write(List packets) {
    writable = false;
    doWrite(Parser.encodePayload(packets), () {
      writable = true;
      emit('drain');
    });
  }
  
  void doWrite(data, Function fn);
  
  String get uri {
    var query = this.query || {};
    var schema = this.secure ? 'https' : 'http';
    var port = '';

    // cache busting is forced for IE / android / iOS6 ಠ_ಠ
    if (global.ActiveXObject || util.ua.android || util.ua.ios6 ||
        this.timestampRequests) {
      query[this.timestampParam] = +new Date;
    }

    query = util.qs(query);

    // avoid port if default for schema
    if (this.port && (('https' == schema && this.port != 443) ||
        ('http' == schema && this.port != 80))) {
      port = ':' + this.port;
    }

    // prepend ? to query
    if (query.length) {
      query = '?' + query;
    }

    return schema + '://' + this.hostname + port + this.path + query;
  }
  
  bool _polling;
}