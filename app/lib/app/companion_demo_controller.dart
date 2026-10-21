import 'package:flutter/foundation.dart';
import '../models/companion_ui_models.dart';
import '../models/preview_models.dart';
import '../models/community_models.dart';

/// Explicitly in-memory rehearsal, never used by the Firebase adapter.
class CompanionDemoController extends ChangeNotifier {
  DateTime seededAt = DateTime.now();
  final List<DemoCompanionRequest> _requests = [];
  List<DemoCompanionRequest> get requests =>
      List.unmodifiable(_requests.reversed);
  bool familyBooking = true, helperAvailable = true;
  int _intent = 0;
  String nextIntent() => 'sample-intent-${++_intent}';
  void setFamilyBooking(AppRole actor, bool value) {
    _require(actor == AppRole.elder, 'Only the elder changes booking consent.');
    familyBooking = value;
    notifyListeners();
  }

  void setHelperAvailable(bool value) {
    helperAvailable = value;
    notifyListeners();
  }

  DemoCompanionRequest create(AppRole actor, CompanionDraft draft) {
    _require(
      actor == AppRole.elder || (actor == AppRole.family && familyBooking),
      'Booking consent is required.',
    );
    final existing = _requests
        .where((r) => r.draft.intentId == draft.intentId)
        .firstOrNull;
    if (existing != null) return existing;
    final request = DemoCompanionRequest(
      'sample-request-${_requests.length + 1}',
      draft,
      actor,
    );
    _requests.add(request);
    notifyListeners();
    return request;
  }

  void assign(AppRole actor, DemoCompanionRequest r) {
    _require(
      _requests.contains(r) && actor == AppRole.coordinator && canAssign(r),
      'An available paired helper is required.',
    );
    r.helperName = 'Kak Lina';
    r.stage = DemoSessionStage.assigned;
    notifyListeners();
  }

  bool canAssign(DemoCompanionRequest r) {
    final start = malaysiaWallTime(r.draft.startsAt);
    final end = start.add(Duration(minutes: r.draft.minutes));
    return r.stage == DemoSessionStage.requested &&
        helperAvailable &&
        start.hour >= 8 &&
        end.year == start.year &&
        end.month == start.month &&
        end.day == start.day &&
        end.hour * 60 + end.minute <= 18 * 60;
  }

  void accept(AppRole actor, DemoCompanionRequest r) =>
      _advance(actor, r, DemoSessionStage.assigned, DemoSessionStage.accepted);
  void start(AppRole actor, DemoCompanionRequest r) => _advance(
    actor,
    r,
    DemoSessionStage.accepted,
    DemoSessionStage.inProgress,
  );
  void finish(AppRole actor, DemoCompanionRequest r) => _advance(
    actor,
    r,
    DemoSessionStage.inProgress,
    DemoSessionStage.awaitingConfirmation,
  );
  void _advance(
    AppRole actor,
    DemoCompanionRequest r,
    DemoSessionStage before,
    DemoSessionStage after,
  ) {
    _require(
      _requests.contains(r) && actor == AppRole.helper && r.stage == before,
      'This session action is not available.',
    );
    r.stage = after;
    notifyListeners();
  }

  void confirm(AppRole actor, DemoCompanionRequest r) {
    _require(
      _requests.contains(r) &&
          (actor == AppRole.elder || actor == AppRole.helper) &&
          (r.stage == DemoSessionStage.awaitingConfirmation ||
              r.stage == DemoSessionStage.completed),
      'Only the two participants can confirm.',
    );
    if (actor == AppRole.elder) r.elderConfirmed = true;
    if (actor == AppRole.helper) r.helperConfirmed = true;
    if (r.elderConfirmed && r.helperConfirmed) {
      r.stage = DemoSessionStage.completed;
    }
    notifyListeners();
  }

  void cancel(AppRole actor, DemoCompanionRequest r) {
    final early = [
      DemoSessionStage.requested,
      DemoSessionStage.assigned,
      DemoSessionStage.accepted,
    ].contains(r.stage);
    _require(
      _requests.contains(r) &&
          early &&
          (actor == AppRole.elder ||
              actor == AppRole.coordinator ||
              (actor == AppRole.family && familyBooking)),
      'This request cannot be cancelled.',
    );
    r.stage = DemoSessionStage.cancelled;
    notifyListeners();
  }

  void reset() {
    _requests.clear();
    familyBooking = true;
    helperAvailable = true;
    seededAt = DateTime.now();
    notifyListeners();
  }

  void _require(bool allowed, String message) {
    if (!allowed) throw StateError(message);
  }
}
