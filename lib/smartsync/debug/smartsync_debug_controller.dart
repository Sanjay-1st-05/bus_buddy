import 'dart:async';

import 'package:esec_bus/smartsync/debug/smartsync_debug_event.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_state.dart';

class SmartSyncDebugController {
  final int maxRecentEvents;
  final StreamController<SmartSyncDebugState> _stateController;
  SmartSyncDebugState _state;

  SmartSyncDebugController({
    SmartSyncDebugState? initialState,
    this.maxRecentEvents = 25,
  }) : _state = initialState ?? SmartSyncDebugState.initial(),
       _stateController = StreamController<SmartSyncDebugState>.broadcast();

  SmartSyncDebugState get currentState => _state;

  Stream<SmartSyncDebugState> get stream => _stateController.stream;

  void update(SmartSyncDebugState state) {
    _state = state;
    _emit();
  }

  void updateWith(
    SmartSyncDebugState Function(SmartSyncDebugState state) build,
  ) {
    update(build(_state));
  }

  void addEvent(
    String message, {
    SmartSyncDebugEventLevel level = SmartSyncDebugEventLevel.info,
    DateTime? occurredAt,
  }) {
    final nextEvent = SmartSyncDebugEvent(
      message: message,
      level: level,
      occurredAt: occurredAt ?? DateTime.now(),
    );

    final nextEvents = <SmartSyncDebugEvent>[
      nextEvent,
      ..._state.recentEvents,
    ].take(maxRecentEvents).toList(growable: false);

    update(_state.copyWith(recentEvents: nextEvents));
  }

  Future<void> dispose() async {
    await _stateController.close();
  }

  void _emit() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }
}
