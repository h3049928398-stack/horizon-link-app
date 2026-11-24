import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'problem_feedback_stub.dart'
    if (dart.library.io) 'problem_feedback_io.dart'
    as transport;

const feedbackMessageLimit = 2000;
final _feedbackUri = Uri.https('ninaaa.cloud', '/api/horizon-link/feedback');
final _versionPattern = RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}\+\d{1,10}$');

String? get feedbackPlatform => kIsWeb
    ? null
    : switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => null,
      };

class FeedbackReport {
  FeedbackReport({
    required this.message,
    required this.platform,
    required String installedVersion,
  }) : requestId = _newRequestId(),
       appVersion = _versionPattern.hasMatch(installedVersion)
           ? installedVersion
           : null;

  final String requestId;
  final String message;
  final String platform;
  final String? appVersion;

  Map<String, String> toJson() => {
    'requestId': requestId,
    'message': message,
    'platform': platform,
    'appVersion': ?appVersion,
  };

  static String _newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

enum FeedbackResult { sent, rateLimited, unavailable }

Future<FeedbackResult> sendProblemFeedback(
  FeedbackReport report, {
  Future<(int, String)> Function(Uri, String) post = transport.postFeedback,
}) async {
  try {
    final (status, body) = await post(
      _feedbackUri,
      jsonEncode(report.toJson()),
    );
    if (status == 429) return FeedbackResult.rateLimited;
    final receipt = status == 200 || status == 201 ? jsonDecode(body) : null;
    return receipt is Map && receipt['id'] == report.requestId
        ? FeedbackResult.sent
        : FeedbackResult.unavailable;
  } on Exception {
    return FeedbackResult.unavailable;
  }
}
