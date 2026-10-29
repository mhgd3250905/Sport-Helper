import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/measure_size.dart';
import '../theme/tokens.dart';
import '../theme/ui_polish_tokens.dart';
import 'chat_widgets.dart';

/// Owns the one menu timeline. Keyboard and menu occupy the same bottom slot,
/// so swapping them never adds their heights together.
class ChatComposerDock extends StatefulWidget {
  const ChatComposerDock({
    super.key,
    required this.panelOpen,
    required this.focusNode,
    required this.extent,
    required this.suggestions,
    required this.input,
    required this.panel,
  });

  final bool panelOpen;
  final FocusNode focusNode;
  final ValueNotifier<double> extent;
  final Widget suggestions, input;
  final ChatFeaturePanel panel;

  @override
  State<ChatComposerDock> createState() => _ChatComposerDockState();
}

class _ChatComposerDockState extends State<ChatComposerDock>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _controller = AnimationController(
    vsync: this,
    duration: SfDockPolishTokens.menuDuration,
  )..addListener(_publishExtent);
  late final _motion = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final _metrics = ValueNotifier<int>(0);
  double _composerHeight = 112;
  double _inputHeight = SfComposerTokens.inputHeight;
  double _keyboardHeight = 0, _lastKeyboardHeight = 0;
  double _safeBottom = 0, _panelHeight = 0, _preferredHeight = 0;
  double _handoffExtent = 0;
  double _settleFrom = 0, _settleTarget = 0, _settleProgress = 1;
  bool _settling = false;
  bool _openingCarry = false, _closingCarry = false;
  double _carryFrom = 0, _carryTarget = 0, _carryProgress = 0;
  bool _keyboardSizedPanel = false, _toKeyboard = false;
  bool _reduced = false;
  bool _extentScheduled = false;

  double get _safe =>
      _keyboardHeight > 0 || _keyboardSizedPanel ? 0 : _safeBottom;
  double get _visiblePanel => _settling ? 0 : _panelHeight * _motion.value;
  double get _settlingExtent =>
      _settleTarget +
      (_settleFrom - _settleTarget) *
          (_motion.value / _settleProgress).clamp(0.0, 1.0);
  double get _carryExtent {
    if (_openingCarry) {
      final progress = ((_motion.value - _carryProgress) / (1 - _carryProgress))
          .clamp(0.0, 1.0);
      return _carryFrom + (_panelHeight + _safe - _carryFrom) * progress;
    }
    if (_closingCarry) {
      return _carryTarget +
          (_carryFrom - _carryTarget) *
              (_motion.value / _carryProgress).clamp(0.0, 1.0);
    }
    return 0;
  }

  double get _bottomExtent => math.max(
    _visiblePanel + _safe,
    math.max(
      _keyboardHeight,
      math.max(_carryExtent, _settling ? _settlingExtent : _handoffExtent),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode.addListener(_focusChanged);
    _controller.addStatusListener(_statusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduced = media.disableAnimations;
    _safeBottom = media.viewPadding.bottom;
    _preferredHeight = ChatFeaturePanel.heightFor(
      width: media.size.width,
      viewportHeight: media.size.height,
      textScaler: media.textScaler,
      actionCount: widget.panel.actions.length,
    );
    if (!_keyboardSizedPanel) _panelHeight = _preferredHeight;
    _readKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishExtent();
    });
  }

  @override
  void didUpdateWidget(ChatComposerDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panelOpen == widget.panelOpen) return;
    if (widget.panelOpen) {
      final carriedExtent = _bottomExtent;
      final needsCarry = _settling || _closingCarry;
      _toKeyboard = false;
      if (needsCarry) {
        _carryFrom = carriedExtent;
        _carryProgress = _settling ? 0 : _motion.value;
        _openingCarry = true;
        _closingCarry = false;
      }
      if (_settling) {
        _settling = false;
        _controller.value = 0;
      }
      if (_keyboardHeight > 0) {
        _panelHeight = _lastKeyboardHeight;
        _keyboardSizedPanel = true;
        _handoffExtent = _keyboardHeight;
      } else if (_controller.isDismissed) {
        _keyboardSizedPanel = false;
        _panelHeight = _preferredHeight;
        _handoffExtent = 0;
      }
      widget.focusNode.unfocus(disposition: UnfocusDisposition.scope);
      if (_reduced) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else {
      final carriedExtent = _bottomExtent;
      if (_openingCarry && _motion.value > 0) {
        _closingCarry = true;
        _carryFrom = carriedExtent;
        _carryTarget = _keyboardHeight > 0 ? _keyboardHeight : _safeBottom;
        _carryProgress = _motion.value;
      }
      _openingCarry = false;
      _toKeyboard = widget.focusNode.hasFocus;
      _handoffExtent = _toKeyboard ? carriedExtent : 0;
      if (_reduced) {
        _controller.value = 0;
      } else {
        _controller.reverse();
      }
    }
  }

  void _focusChanged() {
    if (!widget.focusNode.hasFocus && _toKeyboard) {
      _toKeyboard = false;
      _handoffExtent = 0;
      _metrics.value++;
      _publishExtent();
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _openingCarry = false;
    if (status == AnimationStatus.dismissed) _closingCarry = false;
    if (status == AnimationStatus.completed && _keyboardHeight == 0) {
      _handoffExtent = 0;
    }
    if (status == AnimationStatus.dismissed && _settling) {
      _settling = false;
      _handoffExtent = 0;
      _keyboardSizedPanel = false;
    } else if (status == AnimationStatus.dismissed &&
        _toKeyboard &&
        _handoffExtent > _keyboardHeight) {
      // A different IME (or a hardware keyboard) can be shorter than the
      // remembered one. Reuse this timeline to retire only the spare slot;
      // the menu has already closed and never flashes back on screen.
      _settleFrom = _bottomExtent;
      _settleTarget = _keyboardHeight > 0 ? _keyboardHeight : _safeBottom;
      _settleProgress = 1;
      _settling = !_reduced;
      _handoffExtent = 0;
      if (_settling) {
        _controller.value = 1;
        _controller.reverse();
      } else {
        _keyboardSizedPanel = false;
      }
    } else if (status == AnimationStatus.dismissed && !_toKeyboard) {
      _keyboardSizedPanel = false;
    }
    _publishExtent();
  }

  void _readKeyboard() {
    final view = View.of(context);
    final previousExtent = _bottomExtent;
    _keyboardHeight = view.viewInsets.bottom / view.devicePixelRatio;
    if (_keyboardHeight > 0) _lastKeyboardHeight = _keyboardHeight;
    if (_settling && _motion.value > 0) {
      _settleFrom = previousExtent;
      _settleTarget = _keyboardHeight > 0 ? _keyboardHeight : _safeBottom;
      _settleProgress = _motion.value;
    }
    if (_closingCarry && _motion.value > 0) {
      _carryFrom = previousExtent;
      _carryTarget = _keyboardHeight > 0 ? _keyboardHeight : _safeBottom;
      _carryProgress = _motion.value;
    }
    if (_toKeyboard &&
        _keyboardHeight >= _handoffExtent &&
        _keyboardHeight > 0) {
      _handoffExtent = 0;
    }
  }

  @override
  void didChangeMetrics() {
    _readKeyboard();
    if (_controller.isCompleted && _keyboardHeight == 0) {
      _handoffExtent = 0;
    }
    _metrics.value++;
    _publishExtent();
  }

  void _publishExtent() {
    if (!mounted) return;
    // Reduced motion can change the timeline synchronously in didUpdateWidget.
    // A sibling viewport cannot be marked dirty during that build phase.
    // Normal animation ticks publish before build and stay in the same frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_extentScheduled) {
        _extentScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _extentScheduled = false;
          _publishExtent();
        });
      }
      return;
    }
    if (!widget.panelOpen && _controller.isDismissed && _handoffExtent == 0) {
      _keyboardSizedPanel = false;
    }
    final next = _composerHeight + _bottomExtent;
    if ((widget.extent.value - next).abs() > .01) {
      widget.extent.value = next;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_focusChanged);
    _motion.dispose();
    _controller.dispose();
    _metrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_controller, _metrics]),
    child: _composer(),
    builder: (context, composer) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        composer!,
        ColoredBox(
          color: SfDockPolishTokens.background,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: SizeTransition(
                  key: const ValueKey('chat-panel-transition'),
                  // Flutter 3.44's replacement for vertical axisAlignment: -1.
                  alignment: AlignmentDirectional.topStart,
                  sizeFactor: _motion,
                  child: SizedBox(
                    key: const ValueKey('chat-panel-fixed-content'),
                    height: _settling ? 0 : _panelHeight,
                    width: double.infinity,
                    child: IgnorePointer(
                      ignoring: !widget.panelOpen,
                      child: ExcludeSemantics(
                        excluding: !widget.panelOpen,
                        child: FadeTransition(
                          key: const ValueKey('chat-panel-fade'),
                          opacity: _motion,
                          child: AnimatedBuilder(
                            animation: _motion,
                            child: widget.panelOpen || !_controller.isDismissed
                                ? widget.panel
                                : const SizedBox.shrink(),
                            builder: (context, child) => Transform.translate(
                              key: const ValueKey('chat-panel-content-offset'),
                              offset: Offset(
                                0,
                                SfDockPolishTokens.menuRise *
                                    (1 - _motion.value),
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: math.max(0, _bottomExtent - _visiblePanel)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _composer() => SfMeasureSize(
    onSize: (size) {
      if (!mounted) return;
      if ((size.height - _composerHeight).abs() < .01) return;
      _composerHeight = size.height;
      _publishExtent();
    },
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: SfComposerTokens.outerPadding.bottom,
          height: _inputHeight + SfDockPolishTokens.fadeAboveInput,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('chat-composer-dock'),
              decoration: BoxDecoration(gradient: SfDockPolishTokens.gradient),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: SfComposerTokens.outerPadding.bottom,
          child: ColoredBox(color: SfDockPolishTokens.background),
        ),
        SafeArea(
          top: false,
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.suggestions,
              SfMeasureSize(
                onSize: (size) {
                  if (!mounted) return;
                  final height =
                      size.height - SfComposerTokens.outerPadding.vertical;
                  if ((height - _inputHeight).abs() > .5) {
                    setState(() => _inputHeight = height);
                  }
                },
                child: widget.input,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
