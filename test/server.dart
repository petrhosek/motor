import 'dart:io';

main() {
  group('verification', () {
    test('should disallow non-existent transports', (done) {
      var engine = listen((port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
        .query({ 'transport': 'tobi' }) // no tobi transport - outrageous
        .end((res) {
          expect(res.status).to.be(400);
          expect(res.body.code).to.be(0);
          expect(res.body.message).to.be('Transport unknown');
          done();
        });
      });
    });

    test('should disallow `constructor` as transports', (done) {
      // make sure we check for actual properties - not those present on every {}
      var engine = listen((port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
          .query({ 'transport': 'constructor' })
          .end((res) {
            expect(res.status).to.be(400);
            expect(res.body.code).to.be(0);
            expect(res.body.message).to.be('Transport unknown');
            done();
          });
      });
    });

    test('should disallow non-existent sids', (done) {
      var engine = listen((port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
          .query({ transport: 'polling', sid: 'test' })
          .end((res) {
            expect(res.status).to.be(400);
            expect(res.body.code).to.be(1);
            expect(res.body.message).to.be('Session ID unknown');
            done();
          });
      });
    });
  });

  group('handshake', () {
    test('should send the io cookie', (done) {
      var engine = listen((port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
          .query({ 'transport': 'polling' })
          .end((res) {
            // hack-obtain sid
            var sid = res.text.match(/"sid":"([^"]+)"/)[1];
            expect(res.headers['set-cookie'][0]).to.be('io=' + sid);
            done();
          });
      });
    });

    test('should send the io cookie custom name', (done) {
      var engine = listen({ cookie: 'woot' }, (port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
          .query({ 'transport': 'polling' })
          .end((res) {
            var sid = res.text.match(/"sid":"([^"]+)"/)[1];
            expect(res.headers['set-cookie'][0]).to.be('woot=' + sid);
            done();
          });
      });
    });

    test('should not send the io cookie', (done) {
      var engine = listen({ cookie: false }, (port) {
        request.get('http://localhost:%d/engine.io/default/'.s(port))
          .query({ 'transport': 'polling' })
          .end((res) {
            expect(res.headers['set-cookie']).to.be(undefined);
            done();
          });
      });
    });

    test('should register a new client', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        expect(Object.keys(engine.clients)).to.have.length(0);
        expect(engine.clientsCount).to.be(0);

        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('open', () {
          expect(Object.keys(engine.clients)).to.have.length(1);
          expect(engine.clientsCount).to.be(1);
          done();
        });
      });
    });

    test('should exchange handshake data', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('handshake', (obj) {
          expect(obj.sid).to.be.a('string');
          expect(obj.pingTimeout).to.be.a('number');
          expect(obj.upgrades).to.be.an('array');
          done();
        });
      });
    });

    test('should allow custom ping timeouts', (done) {
      var engine = listen({ allowUpgrades: false, pingTimeout: 123 }, (port) {
        var socket = new eioc.Socket('http://localhost:%d'.s(port));
        socket.on('handshake', (obj) {
          expect(obj.pingTimeout).to.be(123);
          done();
        });
      });
    });

    test('should trigger a connection event with a Socket', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (socket) {
          expect(socket).to.be.an(eio.Socket);
          done();
        });
      });
    });

    test('should open with polling by default', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (socket) {
          expect(socket.transport.name).to.be('polling');
          done();
        });
      });
    });

    test('should be able to open with ws directly', (done) {
      var engine = listen({ transports: ['websocket'] }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
        engine.on('connection', (socket) {
          expect(socket.transport.name).to.be('websocket');
          done();
        });
      });
    });

    test('should not suggest any upgrades for websocket', (done) {
      var engine = listen({ transports: ['websocket'] }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
        socket.on('handshake', (obj) {
          expect(obj.upgrades).to.have.length(0);
          done();
        });
      });
    });

    test('should not suggest upgrades when none are availble', (done) {
      var engine = listen({ transports: ['polling'] }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { });
        socket.on('handshake', (obj) {
          expect(obj.upgrades).to.have.length(0);
          done();
        });
      });
    });

    test('should only suggest available upgrades', (done) {
      var engine = listen({ transports: ['polling', 'flashsocket'] }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { });
        socket.on('handshake', (obj) {
          expect(obj.upgrades).to.have.length(1);
          expect(obj.upgrades).to.have.contain('flashsocket');
          done();
        });
      });
    });

    test('should suggest all upgrades when no transports are disabled', (done) {
      var engine = listen({}, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { });
        socket.on('handshake', (obj) {
          expect(obj.upgrades).to.have.length(2);
          expect(obj.upgrades).to.have.contain('flashsocket');
          expect(obj.upgrades).to.have.contain('websocket');
          done();
        });
      });
    });

    test('should allow arbitrary data through query string', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { query: { a: 'b' } });
        engine.on('connection', (conn) {
          expect(conn.request.query).to.have.keys('transport', 'a');
          expect(conn.request.query.a).to.be('b');
          done();
        });
      });
    });

    test('should allow data through query string in uri', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d?a=b&c=d'.s(port));
        engine.on('connection', (conn) {
          expect(conn.request.query.EIO).to.be.a('string');
          expect(conn.request.query.a).to.be('b');
          expect(conn.request.query.c).to.be('d');
          done();
        });
      });
    });
  });

  group('close', () {
    test('should be able to access non-empty writeBuffer at closing (server)', (done) {
      var opts = {allowUpgrades: false};
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('http://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(conn.writeBuffer.length).to.be(1);
            setTimeout(() {
              expect(conn.writeBuffer.length).to.be(0); // writeBuffer has been cleared
            }, 10);
            done();
          });
          conn.writeBuffer.push({ type: 'message', data: 'foo'});
          conn.onError('');
        });
      });
    });

    test('should be able to access non-empty writeBuffer at closing (client)', (done) {
      var opts = {allowUpgrades: false};
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('http://localhost:%d'.s(port));
        socket.on('open', () {          
          socket.on('close', (reason) {
            expect(socket.writeBuffer.length).to.be(1);
            expect(socket.callbackBuffer.length).to.be(1);
            setTimeout(() {
              expect(socket.writeBuffer.length).to.be(0);
              expect(socket.callbackBuffer.length).to.be(0);
            }, 10);
            done();
          });
          socket.writeBuffer.push({ type: 'message', data: 'foo'});
          socket.callbackBuffer.push(() {});
          socket.onError('');
        });
      });
    });

    test('should trigger on server if the client does not pong', (done) {
      var opts = { allowUpgrades: false, pingInterval: 5, pingTimeout: 5 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('http://localhost:%d'.s(port));
        socket.sendPacket = (){};
        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(reason).to.be('ping timeout');
            done();
          });
        });
      });
    });

    test('should trigger on client if server does not meet ping timeout', (done) {
      var opts = { allowUpgrades: false, pingInterval: 50, pingTimeout: 30 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('open', () {
          // override onPacket to simulate an inactive server after handshake
          socket.onPacket = (){};
          socket.on('close', (reason, err) {
            expect(reason).to.be('ping timeout');
            done();
          });
        });
      });
    });

    test('should trigger on both ends upon ping timeout', (done) {
      var opts = { allowUpgrades: false, pingTimeout: 10, pingInterval: 10 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port))
          , total = 2;

        function onClose (reason, err) {
          expect(reason).to.be('ping timeout');
          --total || done();
        }

        engine.on('connection', (conn) {
          conn.on('close', onClose);
        });

        socket.on('open', () {
          // override onPacket to simulate an inactive server after handshake
          socket.onPacket = socket.sendPacket = (){};
          socket.on('close', onClose);
        });
      });
    });

    test('should trigger when server closes a client', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port))
          , total = 2;

        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(reason).to.be('forced close');
            --total || done();
          });
          setTimeout(() {
            conn.close();
          }, 10);
        });

        socket.on('open', () {
          socket.on('close', (reason) {
            expect(reason).to.be('transport close');
            --total || done();
          });
        });
      });
    });

    test('should trigger when server closes a client (ws)', (done) {
      var opts = { allowUpgrades: false, transports: ['websocket'] };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] })
          , total = 2;

        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(reason).to.be('forced close');
            --total || done();
          });
          setTimeout(() {
            conn.close();
          }, 10);
        });

        socket.on('open', () {
          socket.on('close', (reason) {
            expect(reason).to.be('transport close');
            --total || done();
          });
        });
      });
    });

    test('should trigger when client closes', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port))
          , total = 2;

        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(reason).to.be('transport close');
            --total || done();
          });
        });

        socket.on('open', () {
          socket.on('close', (reason) {
            expect(reason).to.be('forced close');
            --total || done();
          });

          setTimeout(() {
            socket.close();
          }, 10);
        });
      });
    });

    test('should trigger when client closes (ws)', (done) {
      var opts = { allowUpgrades: false, transports: ['websocket'] };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] })
          , total = 2;

        engine.on('connection', (conn) {
          conn.on('close', (reason) {
            expect(reason).to.be('transport close');
            --total || done();
          });
        });

        socket.on('open', () {
          socket.on('close', (reason) {
            expect(reason).to.be('forced close');
            --total || done();
          });

          setTimeout(() {
            socket.close();
          }, 10);
        });
      });
    });

    test('should abort upgrade if socket is closed (GH-35)', (done) {
      var engine = listen({ allowUpgrades: true }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('open', () {
          socket.close();
          // we wait until complete to see if we get an uncaught EPIPE
          setTimeout((){
            done();
          }, 100);
        });
      });
    });

    test('should trigger if a poll request is ongoing and the underlying ' +
       'socket closes, as in a browser tab close', ($done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        // hack to access the sockets created by node-xmlhttprequest
        // see: https://github.com/driverdan/node-XMLHttpRequest/issues/44
        var request = require('http').request;
        var sockets = [];
        http.request = (opts){
          var req = request.apply(null, arguments);
          req.on('socket', (socket){
            sockets.push(socket);
          });
          return req;
        };

        function done(){
          http.request = request;
          $done();
        }

        var socket = new eioc.Socket('ws://localhost:%d'.s(port))
          , serverSocket;

        engine.on('connection', (s){
          serverSocket = s;
        });

        socket.transport.on('poll', (){
          // we set a timer to wait for the request to actually reach
          setTimeout((){
            // at this time server's `connection` should have been fired
            expect(serverSocket).to.be.an('object');

            // OPENED readyState is expected - we qre actually polling
            expect(socket.transport.pollXhr.xhr.readyState).to.be(1);

            // 2 requests sent to the server over an unique port means
            // we should have been assigned 2 sockets
            expect(sockets.length).to.be(2);

            // expect the socket to be open at this point
            expect(serverSocket.readyState).to.be('open');

            // kill the underlying connection
            sockets[1].end();
            serverSocket.on('close', (reason, err){
              expect(reason).to.be('transport error');
              expect(err.message).to.be('poll connection closed prematurely');
              done();
            });
          }, 50);
        });
      });
    });

    test('should not trigger with connection: close header', ($done){
      var engine = listen({ allowUpgrades: false }, (port){
        // intercept requests to add connection: close
        var request = http.request;
        http.request = (){
          var opts = arguments[0];
          opts.headers = opts.headers || {};
          opts.headers.Connection = 'close';
          return request.apply(this, arguments);
        };

        function done(){
          http.request = request;
          $done();
        }

        engine.on('connection', (socket){
          socket.on('message', (msg){
            expect(msg).to.equal('test');
            socket.send('woot');
          });
        });

        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('open', (){
          socket.send('test');
        });
        socket.on('message', (msg){
          expect(msg).to.be('woot');
          done();
        });
      });
    });

    test('should not trigger early with connection `ping timeout`' +
       'after post handshake timeout', (done) {
      // first timeout should trigger after `pingInterval + pingTimeout`,
      // not just `pingTimeout`.
      var opts = { allowUpgrades: false, pingInterval: 300, pingTimeout: 100 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        var clientCloseReason = null;

        socket.on('handshake', () {
          socket.onPacket = (){};
        });
        socket.on('open', () {
          socket.on('close', (reason) {
            clientCloseReason = reason;
          });
        });

        setTimeout(() {
          expect(clientCloseReason).to.be(null);
          done();
        }, 200);
      });
    });

    test('should not trigger early with connection `ping timeout` ' +
       'after post ping timeout', (done) {
      // ping timeout should trigger after `pingInterval + pingTimeout`,
      // not just `pingTimeout`.
      var opts = { allowUpgrades: false, pingInterval: 80, pingTimeout: 50 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        var clientCloseReason = null;

        engine.on('connection', (conn){
          conn.on('heartbeat', () {
            conn.onPacket = (){};
          });
        });

        socket.on('open', () {
          socket.on('close', (reason) {
            clientCloseReason = reason;
          });
        });

        setTimeout(() {
          expect(clientCloseReason).to.be(null);
          done();
        }, 100);
      });
    });

    test('should trigger early with connection `transport close` ' +
       'after missing pong', (done) {
      // ping timeout should trigger after `pingInterval + pingTimeout`,
      // not just `pingTimeout`.
      var opts = { allowUpgrades: false, pingInterval: 80, pingTimeout: 50 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        var clientCloseReason = null;

        socket.on('open', () {
          socket.on('close', (reason) {
            clientCloseReason = reason;
          });
        });

        engine.on('connection', (conn){
          conn.on('heartbeat', () {
            setTimeout(() {
              conn.close();
            }, 20);
            setTimeout(() {
              expect(clientCloseReason).to.be('transport close');
              done();
            }, 100);
          });
        });
      });
    });

    test('should trigger with connection `ping timeout` ' +
       'after `pingInterval + pingTimeout`', (done) {
      var opts = { allowUpgrades: false, pingInterval: 300, pingTimeout: 100 };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        var clientCloseReason = null;

        socket.on('open', () {
          socket.on('close', (reason) {
            clientCloseReason = reason;
          });
        });

        engine.on('connection', (conn){
          conn.once('heartbeat', () {
            setTimeout(() {
              socket.onPacket = (){};
              expect(clientCloseReason).to.be(null);
            }, 150);
            setTimeout(() {
              expect(clientCloseReason).to.be(null);
            }, 350);
            setTimeout(() {
              expect(clientCloseReason).to.be("ping timeout");
              done();
            }, 500);
          });
        });
      });
    });
  });

  group('messages', () {
    test('should arrive from server to client', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.send('a');
        });
        socket.on('open', () {
          socket.on('message', (msg) {
            expect(msg).to.be('a');
            done();
          });
        });
      });
    });

    test('should arrive from server to client (multiple)', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port))
          , expected = ['a', 'b', 'c']
          , i = 0;

        engine.on('connection', (conn) {
          conn.send('a');
          // we use set timeouts to ensure the messages are delivered as part
          // of different.
          setTimeout(() {
            conn.send('b');

            setTimeout(() {
              // here we make sure we buffer both the close packet and
              // a regular packet
              conn.send('c');
              conn.close();
            }, 50);
          }, 50);

          conn.on('close', () {
            // since close fires right after the buffer is drained
            setTimeout(() {
              expect(i).to.be(3);
              done();
            }, 50);
          });
        });
        socket.on('open', () {
          socket.on('message', (msg) {
            expect(msg).to.be(expected[i++]);
          });
        });
      });
    });

    test('should arrive from server to client (ws)', (done) {
      var opts = { allowUpgrades: false, transports: ['websocket'] };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
        engine.on('connection', (conn) {
          conn.send('a');
        });
        socket.on('open', () {
          socket.on('message', (msg) {
            expect(msg).to.be('a');
            done();
          });
        });
      });
    });

    test('should arrive from server to client with ws api', (done) {
      var opts = { allowUpgrades: false, transports: ['websocket'] };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
        engine.on('connection', (conn) {
          conn.send('a');
          conn.close();
        });
        socket.onopen = () {
          socket.onmessage = (msg) {
            expect(msg.data).to.be('a');
            expect('' + msg == 'a').to.be(true);
          };
          socket.onclose = () {
            done();
          };
        };
      });
    });

    test('should arrive from server to client (ws)', (done) {
      var opts = { allowUpgrades: false, transports: ['websocket'] };
      var engine = listen(opts, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] })
          , expected = ['a', 'b', 'c']
          , i = 0;

        engine.on('connection', (conn) {
          conn.send('a');
          setTimeout(() {
            conn.send('b');
            setTimeout(() {
              conn.send('c');
              conn.close();
            }, 50);
          }, 50);
          conn.on('close', () {
            setTimeout(() {
              expect(i).to.be(3);
              done();
            }, 50);
          });
        });

        socket.on('open', () {
          socket.on('message', (msg) {
            expect(msg).to.be(expected[i++]);
          });
        });
      });
    });

    test('should trigger a flush/drain event', (done){
      var engine = listen({ allowUpgrades: false }, (port){
        engine.on('connection', (socket){
          var totalEvents = 4;

          engine.on('flush', (sock, buf){
            expect(sock).to.be(socket);
            expect(buf).to.be.an('array');
            --totalEvents || done();
          });
          socket.on('flush', (buf){
            expect(buf).to.be.an('array');
            --totalEvents || done();
          });

          engine.on('drain', (sock){
            expect(sock).to.be(socket);
            expect(socket.writeBuffer.length).to.be(0);
            --totalEvents || done();
          });
          socket.on('drain', (){
            expect(socket.writeBuffer.length).to.be(0);
            --totalEvents || done();
          });

          socket.send('aaaa');
        });

        new eioc.Socket('ws://localhost:%d'.s(port));
      });
    });

    test('should interleave with pongs if many messages buffered ' +
       'after connection open', (done) {
      this.slow(4000);
      this.timeout(8000);

      var opts = {
        transports: ['websocket'],
        pingInterval: 200,
        pingTimeout: 100
      };

      var engine = listen(opts, (port) {
        var messageCount = 100;
        var messagePayload = new Array(1024 * 1024 * 1).join('a');
        var connection = null;
        engine.on('connection', (conn) {
          connection = conn;
        });
        var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
        socket.on('open', () {
          for (var i=0;i<messageCount;i++) {
//            connection.send('message: ' + i);   // works
            connection.send(messagePayload + '|message: ' + i);   // does not work
          }
          var receivedCount = 0;
          socket.on('message', (msg) {
            receivedCount += 1;
            if (receivedCount === messageCount) {
              done();
            }
          });
        });
      });
    });
  });

  group('send', () {
    group('writeBuffer', () {
      test('should not empty until `drain` event (polling)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });
          var totalEvents = 2;
          socket.on('open', () {
            socket.send('a');
            socket.send('b');
            // writeBuffer should be nonempty, with 'a' still in it
            expect(socket.writeBuffer.length).to.eql(2);
          });
          socket.transport.on('drain', () {
            expect(socket.writeBuffer.length).to.eql(--totalEvents);
            totalEvents || done();
          });
        });
      });

      test('should not empty until `drain` event (websocket)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
          var totalEvents = 2;
          socket.on('open', () {
            socket.send('a');
            socket.send('b');
            // writeBuffer should be nonempty, with 'a' still in it
            expect(socket.writeBuffer.length).to.eql(2);
          });
          socket.transport.on('drain', () {
            expect(socket.writeBuffer.length).to.eql(--totalEvents);
            totalEvents || done();
          });
        });
      });
    });

    group('callback', () {
      test('should execute in order when message sent (client) (polling)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.on('message', (msg) {
              conn.send(msg);
            });
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              // send another packet until we've sent 3 total
              if (++i < 3) {
                expect(i).to.eql(j);
                sendFn();
              } else {
                done();
              }
            });

            function sendFn() {
              socket.send(j, ((value) {
                j++;
              })(j));
            }

            sendFn();
          });
        });
      });

      test('should execute in order when message sent (client) (websocket)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.on('message', (msg) {
              conn.send(msg);
            });
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              // send another packet until we've sent 3 total
              if (++i < 3) {
                expect(i).to.eql(j);
                sendFn();
              } else {
                done();
              }
            });

            function sendFn() {
              socket.send(j, ((value) {
                j++;
              })(j));
            }

            sendFn();
          });
        });
      });

      test('should execute in order with payloads (client) (polling)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });
          var i = 0;
          var lastCbFired = 0;

          engine.on('connection', (conn) {
            conn.on('message', (msg) {
              conn.send(msg);
            });
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              expect(msg).to.eql(i + 1);
              i++;
            });

            function cb(value) {
              expect(value).to.eql(lastCbFired + 1);
              lastCbFired = value;
              if (value == 3) {
                done();
              }
            }

            // 2 and 3 will be in the same payload
            socket.once('flush', () {
              socket.send(2, () { cb(2); });
              socket.send(3, () { cb(3); });
            });

            socket.send(1, () { cb(1); });
          });
        });
      });

      test('should execute in order with payloads (client) (websocket)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
          var i = 0;
          var lastCbFired = 0;

          engine.on('connection', (conn) {
            conn.on('message', (msg) {
              conn.send(msg);
            });
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              expect(msg).to.eql(i + 1);
              i++;
            });

            function cb(value) {
              expect(value).to.eql(lastCbFired + 1);
              lastCbFired = value;
              if (value == 3) {
                done();
              }
            }

            // 2 and 3 will be in the same payload
            socket.once('flush', () {
              socket.send(2, () { cb(2); });
              socket.send(3, () { cb(3); });
            });

            socket.send(1, () { cb(1); });
          });
        });
      });

      test('should execute when message sent (polling)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.send('a', (transport) {
              i++;
            });
          });
          socket.on('open', () {
            socket.on('message', (msg) {
              j++;
            });
          });

          setTimeout(() {
            expect(i).to.be(j);
            done();
          }, 10);
        });
      });

      test('should execute when message sent (websocket)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['websocket'] });
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.send('a', (transport) {
              i++;
            });
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              j++;
            });
          });

          setTimeout(() {
            expect(i).to.be(j);
            done();
          }, 10);
        });
      });

      test('should execute once for each send', (done) {
        var engine = listen((port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port));
          var a = 0;
          var b = 0;
          var c = 0;
          var all = 0;

          engine.on('connection', (conn) {
            conn.send('a');
            conn.send('b');
            conn.send('c');
          });

          socket.on('open', () {
            socket.on('message', (msg) {
              if (msg === 'a') a ++;
              if (msg === 'b') b ++;
              if (msg === 'c') c ++;

              if(++all === 3) {
                expect(a).to.be(1);
                expect(b).to.be(1);
                expect(c).to.be(1);
                done();
              }
            });
          });
        });
      });

      test('should execute in multipart packet', (done) {
        var engine = listen((port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port));
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.send('b', (transport) {
              i++;
            });

            conn.send('a', (transport) {
              i++;
            });

          });
          socket.on('open', () {
            socket.on('message', (msg) {
              j++;
            });
          });

          setTimeout(() {
            expect(i).to.be(j);
            done();
          }, 200);
        });
      });

      test('should execute in multipart packet (polling)', (done) {
        var engine = listen((port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });
          var i = 0;
          var j = 0;

          engine.on('connection', (conn) {
            conn.send('d', (transport) {
              i++;
            });

            conn.send('c', (transport) {
              i++;
            });

            conn.send('b', (transport) {
              i++;
            });

            conn.send('a', (transport) {
              i++;
            });

          });
          socket.on('open', () {
            socket.on('message', (msg) {
              j++;
            });
          });

          setTimeout(() {
            expect(i).to.be(j);
            done();
          }, 200);
        });
      });

      test('should clean callback references when socket gets closed with pending callbacks', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { transports: ['polling'] });

          engine.on('connection', (conn) {
            socket.transport.on('pollComplete', () {
              conn.send('a', (transport) {
                done(new Error('Test invalidation'));
              });

              if (!conn.writeBuffer.length) {
                done(new Error('Test invalidation'));
              }

              // force to close the socket when we have one or more packet(s) in buffer
              socket.close();
            });

            conn.on('close', (reason) {
              expect(conn.packetsFn).to.be.empty();
              expect(conn.sentCallbackFn).to.be.empty();
              done();
            });
          });
        });
      });

      test('should not execute when it is not actually sent (polling)', (done) {
        var engine = listen({ allowUpgrades: false }, (port) {
          var socket = new eioc.Socket('ws://localhost:%d'.s(port), { 'transports': ['polling'] });

          socket.transport.on('pollComplete', (msg) {
            socket.close();
          });

          engine.on('connection', (conn) {
            var err = undefined;

            conn.send('a');
            conn.send('b', (transport) {
              err = new Error('Test invalidation');
            });

            conn.on('close', (reason) {
              done(err);
            });
          });
        });
      });
    });
  });

  group('packet', () {
    test('should emit when socket receives packet', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.on('packet', (packet) {
            expect(packet.type).to.be('message');
            expect(packet.data).to.be('a');
            done();
          });
        });
        socket.on('open', () {
          socket.send('a');
        });
      });
    });

    test('should emit when receives ping', (done) {
      var engine = listen({ allowUpgrades: false, pingInterval: 4 }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.on('packet', (packet) {
            conn.close();
            expect(packet.type).to.be('ping');
            done();
          });
        });
      });
    });
  });

  group('packetCreate', () {
    test('should emit before socket send message', (done) {
      var engine = listen({ allowUpgrades: false }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.on('packetCreate', (packet) {
            expect(packet.type).to.be('message');
            expect(packet.data).to.be('a');
            done();
          });
          conn.send('a');
        });
      });
    });

    test('should emit before send pong', (done) {
      var engine = listen({ allowUpgrades: false, pingInterval: 4 }, (port) {
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        engine.on('connection', (conn) {
          conn.on('packetCreate', (packet) {
            conn.close();
            expect(packet.type).to.be('pong');
            done();
          });
        });
      });
    });
  });

  group('upgrade', () {
    test('should upgrade', (done) {
      var engine = listen((port) {
        // it takes both to send 50 to verify
        var ready = 2, closed = 2;
        function finish () {
          setTimeout(() {
            socket.close();
          }, 10);
        }

        // server
        engine.on('connection', (conn) {
          var lastSent = 0, lastReceived = 0, upgraded = false;
          var interval = setInterval(() {
            lastSent++;
            conn.send(lastSent);
            if (50 == lastSent) {
              clearInterval(interval);
              --ready || finish();
            }
          }, 2);

          conn.on('message', (msg) {
            lastReceived++;
            expect(msg).to.eql(lastReceived);
          });

          conn.on('upgrade', (to) {
            upgraded = true;
            expect(to.name).to.be('websocket');
          });

          conn.on('close', (reason) {
            expect(reason).to.be('transport close');
            expect(lastSent).to.be(50);
            expect(lastReceived).to.be(50);
            expect(upgraded).to.be(true);
            --closed || done();
          });
        });

        // client
        var socket = new eioc.Socket('ws://localhost:%d'.s(port));
        socket.on('open', () {
          var lastSent = 0, lastReceived = 0, upgrades = 0;
          var interval = setInterval(() {
            lastSent++;
            socket.send(lastSent);
            if (50 == lastSent) {
              clearInterval(interval);
              --ready || finish();
            }
          }, 2);
          socket.on('upgrading', (to) {
            // we want to make sure for the sake of this test that we have a buffer
            expect(to.name).to.equal('websocket');
            upgrades++;

            // force send a few packets to ensure we test buffer transfer
            lastSent++;
            socket.send(lastSent);
            lastSent++;
            socket.send(lastSent);

            expect(socket.writeBuffer).to.not.be.empty();
          });
          socket.on('upgrade', (to) {
            expect(to.name).to.equal('websocket');
            upgrades++;
          });
          socket.on('message', (msg) {
            lastReceived++;
            expect(lastReceived).to.eql(msg);
          });
          socket.on('close', (reason) {
            expect(reason).to.be('forced close');
            expect(lastSent).to.be(50);
            expect(lastReceived).to.be(50);
            expect(upgrades).to.be(2);
            --closed || done();
          });
        });
      });

      // attach another engine to make sure it doesn't break upgrades
      var e2 = eio.attach(engine.httpServer, { path: '/foo' });
    });
  });
}