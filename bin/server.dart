import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _router = Router()..get('/', _rootHandler);
final _videosClient = VideoClient(YoutubeHttpClient());

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  final pipeline =
      Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders());
  final handler = pipeline.addHandler(_router);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on ${ip.address}:${server.port}');
}

Future<Response> _rootHandler(Request req) async {
  final youtubeIdOrUrl = req.url.queryParameters['v'];
  final live = bool.parse(req.url.queryParameters['live'] ?? 'false');

  if (youtubeIdOrUrl == null) {
    return Response.badRequest(
      body: jsonEncode({
        "error": "Video id or url is required parameter, pass it as ?v=..."
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  final result = await _getYoutubeVideoQualityUrls(youtubeIdOrUrl, live);
  return Response.ok(
    jsonEncode(result),
    headers: {'content-type': 'application/json'},
  );
}

class _VideoQualityUrl {
  final int quality;
  final String url;

  _VideoQualityUrl({
    required this.quality,
    required this.url,
  });

  Map<String, dynamic> toJson() => {'quality': quality, 'url': url};

  @override
  String toString() => 'VideoQualityUrl(quality: $quality, url: $url)';
}

Future<List<_VideoQualityUrl>?> _getYoutubeVideoQualityUrls(
  String youtubeIdOrUrl,
  bool live,
) async {
  try {
    final urls = <_VideoQualityUrl>[];
    if (live) {
      final url = await _videosClient.streamsClient.getHttpLiveStreamUrl(
        VideoId(youtubeIdOrUrl),
      );
      urls.add(
        _VideoQualityUrl(
          quality: 360,
          url: url,
        ),
      );
    } else {
      final manifest =
          await _videosClient.streamsClient.getManifest(youtubeIdOrUrl);
      urls.addAll(
        manifest.muxed.map(
          (element) => _VideoQualityUrl(
            quality: int.parse(element.qualityLabel.split('p')[0]),
            url: element.url.toString(),
          ),
        ),
      );
    }

    return urls;
  } catch (error) {
    if (error.toString().contains('XMLHttpRequest')) {
      print(
        '(INFO) To play youtube video in WEB, Please enable CORS in your browser',
      );
    }
    print('===== YOUTUBE API ERROR: $error ==========');
    return [];
  }
}
