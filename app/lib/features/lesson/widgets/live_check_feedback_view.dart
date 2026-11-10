import 'package:flutter/material.dart';

import '../lesson_state.dart';
import 'hallucination_feedback_view.dart';
import 'web_source_list.dart';

/// The live check part of the feedback panel: what was found, missed and
/// tapped by mistake (with the original sentence and a tip, like Q2), then
/// the pages the correct answer is based on.
class LiveCheckFeedbackView extends StatelessWidget {
  const LiveCheckFeedbackView({super.key, required this.correct});

  final CorrectLiveCheck correct;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('live-check-feedback'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        HallucinationFeedbackView(review: correct.review),
        const SizedBox(height: 16),
        const Text(
          '答えのもとになった出典',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'AI がもっともらしく書いていても、出典と見くらべると本当のことが分かるよ。',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 8),
        WebSourceList(
          key: const Key('live-check-feedback-sources'),
          sources: correct.sources,
          emptyText: '出典はありませんでした。',
        ),
      ],
    );
  }
}
