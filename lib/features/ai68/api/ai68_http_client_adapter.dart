import 'dart:io';

import 'package:dio/io.dart';

IOHttpClientAdapter createAi68HttpClientAdapter() {
  return IOHttpClientAdapter(createHttpClient: createAi68HttpClient);
}

HttpClient createAi68HttpClient() {
  final client = _DefaultHttpClientFactory().create();
  client.badCertificateCallback = (_, _, _) => false;
  client.findProxy = (_) => 'DIRECT';
  return client;
}

final class _DefaultHttpClientFactory extends HttpOverrides {
  HttpClient create() {
    return super.createHttpClient(null);
  }
}
