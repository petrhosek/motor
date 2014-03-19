library transport;

import '../../../../dart/dart-sdk/lib/async/async.dart';
import '../../../../dart/dart-sdk/lib/io/io.dart';

import '../../../../../.pub-cache/hosted/pub.dartlang.org/logging-0.4.3+5/lib/logging.dart';

import '../../parser.dart';
import '../../eventemitter.dart';

abstract class Transport extends EventEmitter {
  
  String _readyState = 'opening';
  HttpRequest _req = null;
  HttpRequest _request = null;
  Logger _logger = new Logger('Transport');
  
  Transport(this._req);

  /**
   * Called with an incoming HTTP request.
   *
   * @param {http.ServerRequest} request
   * @api private
   */
  onRequest(HttpRequest req) {
    _logger.fine('setting request');
    if (_req == null) {
      _logger.fine('setting handshake request');
      _request = req;
    }
    _req = req;
  }

  /**
   * Closes the transport.
   *
   * @api private
   */
  close([Function fn]) {
    _readyState = 'closing';
    doClose(?fn ? fn : () {});
  }

  /**
   * Called with a transport error.
   *
   * @param {String} message error
   * @param {Object} error description
   * @api private
   */
  onError(AsyncError error) {
    if (listeners('error').length > 0) {
      var err = new Error(msg);
      err.type = 'TransportError';
      err.description = desc;
      this.emit('error', err);
    } else {
      _logger.fine('ignored transport error $msg ($desc)');
    }
  }

  /**
   * Called with parsed out a packets from the data stream.
   *
   * @param {Object} packet
   * @api private
   */
  onPacket(packet) {
    emit('packet', packet);
  }

  /**
   * Called with the encoded packet data.
  *
   * @param {String} data
   * @api private
   */
  onData(data) {
    onPacket(Parser.decodePacket(data));
  }

  /**
   * Called upon transport close.
   */
  onClose() {
    _readyState = 'closed';
    emit('close');
  }
  
}