import 'package:unittest/unittest.dart';

import '../lib/pump.dart';

import 'dart:io';
import 'package:http/http.dart' as http;

/**
 * Tests.
 */
main() {
  const int port = 8080;
  
  test('should expose protocol number', () {
    expect(Fan.protocol, new isInstanceOf<num>());
  });

  test('should be the same version as client', (){
    expect(Fan.protocol, new isInstanceOf<num>());
    //var version = require('../package').version;
    //expect(version).to.be(require('engine.io-client/package').version);
  });

  group('listen', () {
    test('should open a http server that returns 501', () {
      var done = expectAsync0(() => {});
      Fan.listen(port).then((server) {
        http.get('http://127.0.0.1:$port/').then((response) {
          expect(response.statusCode, equals(501));
          done();
        });
      });
    });
  });

  group('attach()', () {
    test('should return an engine.Server',  () {
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server);
        expect(engine, new isInstanceOf<Server>());
      });
    });

    test('should attach engine to an http server', () {
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server);
        
        http.get('http://127.0.0.1:${server.port}/engine.io/default/').then((response) {
          expect(response.statusCode, equals(501));
          expect(response.body, equals(0));
          expect(response.body, equals('Transport unknown'));
          //server.once('close', done);
          server.close();
        });
      });
    });

    test('should respond to flash policy requests', () {
      var done = expectAsync0(() => {});
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server);
        
        var client = new HttpClient();
        client.get('127.0.0.1', port, '/')
          .then((HttpClientRequest request) {
            request.write('<policy-file-request/>\0');
            request.encoding = Encoding.fromName('ascii');
            request.close();
          })
          .then((HttpClientResponse response) {
            response.listen((data) {
              expect(data, contains('<allow-access-from'));
              client.close();
              done();
            });
          });
      });
    });

    test('should not respond to borked flash policy requests', () {
      var done = expectAsync0(() => expect(false, 'Should not respond'), count:0);
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server);
        
        var client = new HttpClient();
        client.get('127.0.0.1', port, '/')
          .then((HttpClientRequest request) {
            request.write('<policy-file-req>\0');
            request.encoding = Encoding.fromName('ascii');
            request.close();
          })
          .then((HttpClientResponse response) {
            response.listen((data) {
              done();
            });
          });
        //new Timer(new Duration(miliseconds:20), done);
      });
    });

    test('should not respond to flash policy requests when policyFile:false', () {
      var done = expectAsync0(() => expect(false, 'Should not fire'), count:0);
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server, policyFile: false);
        
        var client = new HttpClient();
        client.get('127.0.0.1', port, '/')
          .then((HttpClientRequest request) {
            request.write('<policy-file-req>\0');
            request.encoding = Encoding.fromName('ascii');
            request.close();
          })
          .then((HttpClientResponse response) {
            response.listen((data) {
              done();
            });
          });
        //new Timer(new Duration(miliseconds:20), done);
      });
    });

    test('should not respond to flash policy requests when no flashsocket', () {
      var done = expectAsync0(() => expect(false, 'Should not fire'), count:0);
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server, transports: ['xhr-polling', 'websocket']);
        
        var client = new HttpClient();
        client.get('127.0.0.1', port, '/')
          .then((HttpClientRequest request) {
            request.write('<policy-file-req>\0');
            request.encoding = Encoding.fromName('ascii');
            request.close();
          })
          .then((HttpClientResponse response) {
            response.listen((data) {
              done();
            });
          });
        //new Timer(new Duration(miliseconds:20), done);
      });
    });
    
    test('should destroy upgrades not handled by engine', () {
      var done = expectAsync0(() => expect(false, 'Client should have ended'), count:0);
      HttpServer.bind('127.0.0.1', port).then((server) {
        var engine = Fan.attach(server);
        
        var client = new HttpClient();
        client.get('127.0.0.1', port, '/')
          .then((HttpClientRequest request) {
            request.encoding = Encoding.fromName('ascii');
            request.headers.add(HttpHeaders.UPGRADE, 'IRC/6.9');
            request.close();
          })
          .then((HttpClientResponse response) {
            done();
          });
        /*var check = setTimeout(() {
          done(new Error('Client should have ended'));
        }, 20);

        client.on('end',  () {
          clearTimeout(check);
          done();
        });*/
      });
    });

    /*test('should not destroy unhandled upgrades with destroyUpgrade:false', (done) {
      var server = http.createServer()
        , engine = eio.attach(server, { 'destroyUpgrade': false, 'destroyUpgradeTimeout': 50 });

      server.listen( () {
        var client = net.createConnection(server.address().port);
        client.on('connect',  () {
          client.setEncoding('ascii');
          client.write([
              'GET / HTTP/1.1'
            , 'Upgrade: IRC/6.9'
            , '', ''
          ].join('\r\n'));

          var check = setTimeout( () {
            client.removeListener('end', onEnd);
            done();
          }, 100);

           onEnd () {
            done(new Error('Client should not end'));
          }

          client.on('end', onEnd);
        });
      });
    });

    test('should destroy unhandled upgrades with after a timeout', (done) {
      var server = http.createServer()
        , engine = eio.attach(server, { 'destroyUpgradeTimeout': 200 });

      server.listen( () {
        var client = net.createConnection(server.address().port);
        client.on('connect',  () {
          client.setEncoding('ascii');
          client.write([
              'GET / HTTP/1.1'
            , 'Upgrade: IRC/6.9'
            , '', ''
          ].join('\r\n'));

          // send from client to server
          // tests that socket is still alive
          // this will not keep the socket open as the server does not handle it
          setTimeout(() {
            client.write('foo');
          }, 100);

           onEnd () {
            done();
          }

          client.on('end', onEnd);
        });
      });
    });

    test('should not destroy handled upgrades with after a timeout', (done) {
      var server = http.createServer()
        , engine = eio.attach(server, { 'destroyUpgradeTimeout': 100 });

      // write to the socket to keep engine.io from closing it by writing before the timeout
      server.on('upgrade', (req, socket) {
        socket.write('foo');
        socket.on('data', (chunk) {
          expect(chunk.toString()).to.be('foo');
          socket.end();
        });
      });

      server.listen(() {
        var client = net.createConnection(server.address().port);

        client.on('connect',  () {
          client.setEncoding('ascii');
          client.write([
              'GET / HTTP/1.1'
            , 'Upgrade: IRC/6.9'
            , '', ''
          ].join('\r\n'));

          // test that socket is still open by writing after the timeout period
          setTimeout(() {
            client.write('foo');
          }, 200);

          client.on('end', done);
        });
      });
    });

    test('should preserve original request listeners', (done) {
      var listeners = 0
        , server = http.createServer( (req, res) {
            expect(req && res).to.be.ok();
            listeners++;
          });

      server.on('request',  (req, res) {
        expect(req && res).to.be.ok();
        res.writeHead(200);
        res.end('');
        listeners++;
      });

      eio.attach(server);

      server.listen( () {
        var port = server.address().port;
        request.get('http://localhost:%d/engine.io/default/'.s(port), (res) {
          expect(res.status).to.be(400);
          expect(res.body.code).to.be(0);
          expect(res.body.message).to.be('Transport unknown');
          request.get('http://localhost:%d/test'.s(port),  (res) {
            expect(res.status).to.be(200);
            expect(listeners).to.eql(2);
            server.once('close', done);
            server.close();
          });
        });
      });
    });*/
  });
}