import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../shared/design_system.dart';
import '../community/session_ui.dart';
import '../wallet/wallet_view.dart';

/// Shows the identities and times represented by the confirmed wire payload.
/// It does not query extra private records or perform a domain write.
class CoordinationReview extends StatelessWidget {
  const CoordinationReview({
    super.key,
    required this.kind,
    required this.fields,
  });
  final String kind;
  final Json fields;

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final rows = <(String, String)>[];
    String residentName(String? id) {
      if (id == c.session?.profile?.uid) return c.session!.profile!.displayName;
      return c.coordination?.elderProfiles
                  .where((e) => e['id'] == id)
                  .firstOrNull?['displayName']
              as String? ??
          c.sessions?.requests
              .where((r) => r.elderId == id)
              .firstOrNull
              ?.elderName ??
          c.t('Selected resident', 'Penduduk dipilih');
    }

    String companionName(String? id) =>
        c.sessions?.requests
            .where((r) => r.helperId == id && r.helperName != null)
            .firstOrNull
            ?.helperName ??
        (id == null
            ? c.t('Paired companion', 'Teman berpasangan')
            : '${c.t('Companion reference', 'Rujukan teman')}: $id');

    if (fields['placeId'] != null) {
      rows.add((
        c.t('Place', 'Tempat'),
        c.community?.places
                .where((p) => p.id == fields['placeId'])
                .firstOrNull
                ?.name ??
            c.t('Selected place', 'Tempat dipilih'),
      ));
    }
    if (kind == 'setPlaceWarning') {
      final warning = fields['warning'];
      rows.add((
        c.t('Action', 'Tindakan'),
        warning == null
            ? c.t('Clear recorded warning', 'Kosongkan amaran direkodkan')
            : warning['level'] == 'closed'
            ? c.t('Mark as closed', 'Tandakan ditutup')
            : c.t('Record a warning', 'Rekodkan amaran'),
      ));
      if (warning != null) {
        rows.add((
          c.t('Review due', 'Semakan perlu'),
          whenLabel(utcTimestamp(warning['expiresAt'])!, c.malay),
        ));
      }
    } else if (kind == 'blockHelper') {
      rows.add((
        c.t('Resident', 'Penduduk'),
        residentName(fields['elderId'] as String?),
      ));
      rows.add((
        c.t('Companion', 'Teman'),
        companionName(fields['helperId'] as String?),
      ));
    } else {
      rows.add((
        c.t('Report', 'Laporan'),
        fields['kind'] == 'helper_report'
            ? c.t('Companion session concern', 'Kebimbangan sesi teman')
            : c.t('Place access problem', 'Masalah akses tempat'),
      ));
      final request = c.sessions?.requests
          .where((r) => r.id == fields['requestId'])
          .firstOrNull;
      if (request != null) {
        rows.add((
          c.t('Session', 'Sesi'),
          sessionTask(request.taskType, c.malay),
        ));
        rows.add((c.t('When', 'Masa'), whenLabel(request.startsAt, c.malay)));
        rows.add((c.t('Resident', 'Penduduk'), request.elderName));
        rows.add((c.t('Companion', 'Teman'), companionName(request.helperId)));
      }
    }
    return Surface(
      key: const ValueKey('coordination-review-details'),
      color: Palette.soft,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Text(rows[i].$1, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(rows[i].$2, style: Theme.of(context).textTheme.titleMedium),
          ],
        ],
      ),
    );
  }
}
