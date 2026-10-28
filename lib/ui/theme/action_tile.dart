import 'package:flutter/material.dart';

import 'polish_card.dart';
import 'tokens.dart';
import 'ui_polish_tokens.dart';

/// Square transparent artwork, a reserved two-line title and a bottom label.
class SfActionTile extends StatelessWidget {
  const SfActionTile({
    super.key,
    required this.artwork,
    required this.title,
    required this.metadata,
  });

  final Widget artwork;
  final String title;
  final String metadata;

  static double heightFor(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    return width +
        SfCardTokens.inset +
        scaler.scale(SfCardTokens.title.fontSize!) *
            SfCardTokens.title.height! *
            SfCardTokens.titleLines +
        SfSpace.x1 +
        scaler.scale(SfCardTokens.metadata.fontSize!) *
            SfCardTokens.metadata.height!;
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = SfCardTokens.title;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) *
        titleStyle.height!;
    return SfPolishCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: SfCardTokens.imageAspectRatio,
            child: artwork,
          ),
          const SizedBox(height: SfCardTokens.inset),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lineHeight * SfCardTokens.titleLines,
                  child: Text(
                    title,
                    style: titleStyle,
                    maxLines: SfCardTokens.titleLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Text(
                  metadata,
                  style: SfCardTokens.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
