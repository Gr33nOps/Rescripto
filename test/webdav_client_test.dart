import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rescripto/services/sync/webdav_client.dart';
import 'package:rescripto/services/sync/webdav_exception.dart';

void main() {
  final url = Uri.parse('https://cloud.example.com/remote.php/dav/files/me/rescripto-sync.rescriptobackup');

  group('WebDavClient.put', () {
    test('sends a PUT with basic auth and the exact bytes', () async {
      http.Request? captured;
      final client = WebDavClient(MockClient((request) async {
        captured = request;
        return http.Response('', 201);
      }));

      await client.put(url, 'alice', 'secret', Uint8List.fromList([1, 2, 3]));

      expect(captured!.method, 'PUT');
      expect(captured!.url, url);
      expect(captured!.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('alice:secret'))}');
      expect(captured!.bodyBytes, [1, 2, 3]);
    });

    test('throws WebDavException on a 4xx/5xx response', () async {
      final client = WebDavClient(MockClient((request) async => http.Response('nope', 507)));

      await expectLater(
        client.put(url, 'alice', 'secret', Uint8List(0)),
        throwsA(isA<WebDavException>().having((e) => e.statusCode, 'statusCode', 507)),
      );
    });
  });

  group('WebDavClient.get', () {
    test('returns the response bytes on 200', () async {
      final client = WebDavClient(MockClient((request) async => http.Response.bytes([9, 8, 7], 200)));

      final bytes = await client.get(url, 'alice', 'secret');

      expect(bytes, [9, 8, 7]);
    });

    test('returns null on 404 rather than throwing', () async {
      final client = WebDavClient(MockClient((request) async => http.Response('', 404)));

      final bytes = await client.get(url, 'alice', 'secret');

      expect(bytes, isNull);
    });

    test('throws WebDavException on an auth failure', () async {
      final client = WebDavClient(MockClient((request) async => http.Response('', 401)));

      await expectLater(
        client.get(url, 'alice', 'secret'),
        throwsA(isA<WebDavException>().having((e) => e.isAuthFailure, 'isAuthFailure', isTrue)),
      );
    });
  });

  group('WebDavClient.lastModified', () {
    test('parses getlastmodified out of a multistatus PROPFIND response', () async {
      final client = WebDavClient(MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['Depth'], '0');
        return http.Response('''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/rescripto-sync.rescriptobackup</D:href>
    <D:propstat>
      <D:prop>
        <D:getlastmodified>Mon, 12 Jan 2026 10:00:00 GMT</D:getlastmodified>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
      }));

      final modified = await client.lastModified(url, 'alice', 'secret');

      expect(modified, DateTime.utc(2026, 1, 12, 10, 0, 0));
    });

    test('returns null when the file does not exist yet', () async {
      final client = WebDavClient(MockClient((request) async => http.Response('', 404)));

      expect(await client.lastModified(url, 'alice', 'secret'), isNull);
    });

    test('returns null rather than throwing on malformed XML', () async {
      final client = WebDavClient(MockClient((request) async => http.Response('not xml', 207)));

      expect(await client.lastModified(url, 'alice', 'secret'), isNull);
    });
  });
}
