import 'package:flutter/material.dart';

import '../services/problem_feedback.dart';
import '../services/release_info.dart';

class ProblemFeedbackPage extends StatefulWidget {
  const ProblemFeedbackPage({
    super.key,
    required this.english,
    required this.platform,
    this.send = sendProblemFeedback,
  });

  final bool english;
  final String platform;
  final Future<FeedbackResult> Function(FeedbackReport) send;

  @override
  State<ProblemFeedbackPage> createState() => _ProblemFeedbackPageState();
}

class _ProblemFeedbackPageState extends State<ProblemFeedbackPage> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  FeedbackReport? _report;
  FeedbackResult? _result;
  bool _sending = false;

  String _text(String zh, String en) => widget.english ? en : zh;

  Future<void> _submit() async {
    if (_sending || _result == FeedbackResult.sent) return;
    if (!_form.currentState!.validate()) return;
    final message = _message.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _result = null;
    });
    var result = FeedbackResult.unavailable;
    try {
      if (_report?.message != message) {
        final version = await ReleaseInfo.installedVersion();
        if (!mounted) return;
        _report = FeedbackReport(
          message: message,
          platform: widget.platform,
          installedVersion: version,
        );
      }
      result = await widget.send(_report!);
    } on Exception {
      // Keep the draft and let the user retry the same submission.
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _result = result;
        });
      }
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _result == FeedbackResult.sent;
    final status = switch (_result) {
      FeedbackResult.sent => _text(
        '反馈已送达开发者。',
        'Feedback sent to the developer.',
      ),
      FeedbackResult.rateLimited => _text(
        '发送过于频繁，请稍后重试。',
        'Too many submissions. Please try again later.',
      ),
      FeedbackResult.unavailable => _text(
        '未能确认送达，内容已保留，请稍后重试。',
        'Delivery could not be confirmed. Your draft is here. Please try again.',
      ),
      null => null,
    };
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(title: Text(_text('问题反馈', 'Report a problem'))),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!sent) ...[
                  Text(
                    _text(
                      '点击发送后，问题描述、平台和应用版本会提交给开发者网站 ninaaa.cloud。请勿填写密码或个人信息。',
                      'Send your description, platform and app version to the developer at ninaaa.cloud. Please leave out passwords and personal information.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _message,
                    readOnly: _sending,
                    minLines: 5,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      errorMaxLines: 3,
                      labelText: _text('问题描述', 'Problem description'),
                      hintText: _text(
                        '发生了什么？如何重现？',
                        'What happened? How can we reproduce it?',
                      ),
                    ),
                    validator: (value) {
                      final message = value?.trim() ?? '';
                      if (message.isEmpty) {
                        return _text('请输入问题描述。', 'Enter a description.');
                      }
                      if (message.runes.length > feedbackMessageLimit) {
                        return _text(
                          '请将描述缩短至 $feedbackMessageLimit 字以内。',
                          'Keep the description within $feedbackMessageLimit characters.',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _sending
                      ? null
                      : sent
                      ? () => Navigator.pop(context)
                      : _submit,
                  child: Text(
                    _sending
                        ? _text('正在发送…', 'Sending…')
                        : sent
                        ? _text('完成', 'Done')
                        : _text('发送反馈', 'Send feedback'),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(status)),
                ],
                if (sent)
                  SelectableText(
                    _text(
                      '反馈编号：${_report!.requestId}',
                      'Reference: ${_report!.requestId}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
