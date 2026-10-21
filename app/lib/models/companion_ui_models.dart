import 'preview_models.dart';

/// UI-only models for the approved Phase 2 rehearsal. No callable serialization.
enum CompanionTask { walkWithMe, sitWithMe, phoneHelp, carryLightItem }

enum DemoSessionStage {
  requested,
  assigned,
  accepted,
  inProgress,
  awaitingConfirmation,
  completed,
  cancelled,
}

class CompanionDraft {
  const CompanionDraft({
    required this.intentId,
    required this.elderName,
    required this.title,
    required this.task,
    required this.startsAt,
    required this.minutes,
    required this.language,
    this.activityId,
    this.placeName = '',
    this.note = '',
  });
  final String intentId, elderName, title, language, placeName, note;
  final String? activityId;
  final CompanionTask task;
  final DateTime startsAt;
  final int minutes;
}

class DemoCompanionRequest {
  DemoCompanionRequest(this.id, this.draft, this.requestedBy);
  final String id;
  final CompanionDraft draft;
  final AppRole requestedBy;
  DemoSessionStage stage = DemoSessionStage.requested;
  bool elderConfirmed = false, helperConfirmed = false;
  String? helperName;
}
