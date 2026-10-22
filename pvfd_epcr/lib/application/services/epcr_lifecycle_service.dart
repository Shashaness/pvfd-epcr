import 'dart:async';
import 'package:flutter/widgets.dart';
import '../controllers/epcr_controller.dart';

/// Lifecycle adapter; controller remains usable without a widget binding.
class EpcrLifecycleService with WidgetsBindingObserver {
  EpcrLifecycleService(this.controller);
  final EpcrController controller;
  bool _attached = false;
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(controller.flush());
  }
}
