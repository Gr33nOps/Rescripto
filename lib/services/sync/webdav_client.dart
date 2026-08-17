import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'webdav_exception.dart';

/// A minimal WebDAV client: GET, PUT, and a `PROPFIND` for
/// `getlastmodified` — everything [SyncService] needs to treat one remote
/// file as the sync target, and nothing more. Deliberately not a general
/// WebDAV library; Nextcloud/ownCloud and any RFC 4918-compliant server
/// only ever see these three request shapes from this app.
///
/// Takes whatever [http.Client] the caller hands it — in production that's
/// always `NetworkGuard.httpClientFor(NetworkFeature.sync)`, so every
/// request here is policy-checked and logged the same as any other
/// egress; this class has no opinion about that and no fallback of its
/// own if the guard refuses one.
class WebDavClient {
  const WebDavClient(this._client);

  final http.Client _client;

  /// [ifMatchEtag], when given, makes this a conditional PUT: the server is
  /// asked to reject the write (412) rather than accept it if the file's
  /// current ETag no longer matches — see [SyncService]'s conflict check for
  /// why a caller passes this rather than just PUTting unconditionally.
  Future<void> put(
    Uri url,
    String username,
    String password,
    Uint8List bytes, {
    String? ifMatchEtag,
  }) async {
    final response = await _client.put(
      url,
      headers: {
        'Authorization': _basicAuth(username, password),
        'Content-Type': 'application/octet-stream',
        'If-Match': ?ifMatchEtag,
      },
      body: bytes,
    );
    if (response.statusCode >= 400) {
      throw WebDavException(response.statusCode, response.reasonPhrase);
    }
  }

  /// Returns null if nothing exists at [url] yet — a first sync from a
  /// fresh install or a fresh server both look like this.
  Future<Uint8List?> get(Uri url, String username, String password) async {
    final response = await _client.get(
      url,
      headers: {'Authorization': _basicAuth(username, password)},
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) {
      throw WebDavException(response.statusCode, response.reasonPhrase);
    }
    return response.bodyBytes;
  }

  /// The server's `getlastmodified` for [url], or null if nothing exists
  /// there yet. What [SyncService] compares against the last push this
  /// device made to decide whether the server is ahead.
  Future<DateTime?> lastModified(Uri url, String username, String password) async {
    return (await stat(url, username, password)).lastModified;
  }

  /// `getlastmodified` and `getetag` for [url] in one PROPFIND, or both null
  /// if nothing exists there yet. `getetag` isn't guaranteed by every WebDAV
  /// server — [SyncService]'s conflict check falls back to the timestamp
  /// when it's absent.
  Future<({DateTime? lastModified, String? etag})> stat(
    Uri url,
    String username,
    String password,
  ) async {
    final request = http.Request('PROPFIND', url)
      ..headers['Authorization'] = _basicAuth(username, password)
      ..headers['Depth'] = '0'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8" ?>'
          '<D:propfind xmlns:D="DAV:"><D:prop><D:getlastmodified/><D:getetag/></D:prop></D:propfind>';

    final streamed = await _client.send(request);
    if (streamed.statusCode == 404) return (lastModified: null, etag: null);
    if (streamed.statusCode >= 400) {
      throw WebDavException(streamed.statusCode, streamed.reasonPhrase);
    }

    final body = await streamed.stream.bytesToString();
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } catch (_) {
      return (lastModified: null, etag: null);
    }
    // namespace: '*' matches by local name regardless of the server's
    // chosen prefix — Nextcloud uses `d:`, some servers `D:` or `DAV:`.
    final modified = document.findAllElements('getlastmodified', namespace: '*');
    final etag = document.findAllElements('getetag', namespace: '*');
    return (
      lastModified: modified.isEmpty ? null : _parseHttpDate(modified.first.innerText.trim()),
      etag: etag.isEmpty ? null : etag.first.innerText.trim(),
    );
  }

  String _basicAuth(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// `getlastmodified` is specified (RFC 4918 §15.7) to use the same
  /// RFC 1123 date format as HTTP's own `Last-Modified` header.
  DateTime? _parseHttpDate(String raw) {
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
