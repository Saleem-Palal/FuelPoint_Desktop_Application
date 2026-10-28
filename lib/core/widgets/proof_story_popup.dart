import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dispensr_theme.dart';

Future<void> showProofStoryPopup(
  BuildContext context, {
  required String imagePath,
}) {
  final String path = imagePath.trim();
  if (path.isEmpty) {
    return Future<void>.value();
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close screenshot',
    barrierColor: const Color(0xE0000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return _ProofStoryPage(path: path);
        },
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
            ),
          );
        },
  );
}

class LedgerProofThumb extends StatelessWidget {
  const LedgerProofThumb({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String path = imagePath.trim();
    if (path.isEmpty) {
      return Text('—', style: TextStyle(color: tokens.inkMuted));
    }
    final File file = File(path);
    if (!file.existsSync()) {
      return Text('—', style: TextStyle(color: tokens.inkMuted));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(showProofStoryPopup(context, imagePath: path));
        },
        borderRadius: BorderRadius.circular(7),
        child: Tooltip(
          message: 'View screenshot',
          child: Ink(
            width: 28,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: tokens.line, width: 1.2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5.5),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) {
                      return Icon(
                        Icons.hide_image_outlined,
                        size: 14,
                        color: tokens.inkMuted,
                      );
                    },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProofStoryPage extends StatelessWidget {
  const _ProofStoryPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final double height = (screen.height * 0.88).clamp(420, 920);
    final double width = (height * 9 / 16).clamp(240, 460);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: <Widget>[
                Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 28,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              const ColoredBox(color: Color(0xFF111111)),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  8,
                                  28,
                                  8,
                                  16,
                                ),
                                child: Image.file(
                                  File(path),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder:
                                      (
                                        BuildContext context,
                                        Object error,
                                        StackTrace? stack,
                                      ) {
                                        return const Center(
                                          child: Icon(
                                            Icons.hide_image_outlined,
                                            color: Color(0x99FFFFFF),
                                            size: 48,
                                          ),
                                        );
                                      },
                                ),
                              ),
                              const Positioned(
                                top: 10,
                                left: 14,
                                right: 14,
                                child: _StoryProgressBar(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 22),
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

class _StoryProgressBar extends StatelessWidget {
  const _StoryProgressBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0x55FFFFFF),
        borderRadius: BorderRadius.circular(99),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 1,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xEEFFFFFF),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}
