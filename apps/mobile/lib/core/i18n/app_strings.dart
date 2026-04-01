import 'package:dispatch_mobile/core/i18n/app_locale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appStringsProvider = Provider<AppStrings>(
  (ref) => AppStrings(ref.watch(appLocaleProvider)),
);

class AppStrings {
  const AppStrings(this.locale);

  final AppLocale locale;

  bool get _isFil => locale == AppLocale.fil;

  String get language => _isFil ? 'Wika' : 'Language';
  String get english => 'English';
  String get filipino => 'Filipino';
  String get signOut => _isFil ? 'Mag-sign out' : 'Sign out';

  String get myReports => _isFil ? 'Aking Mga Ulat' : 'My Reports';
  String get newReport => _isFil ? 'Bagong Ulat' : 'New Report';
  String get emergencySos => _isFil ? 'Pang-emergency na SOS' : 'Emergency SOS';
  String get meshNetwork => _isFil ? 'Mesh Network' : 'Mesh Network';
  String get offlineComms => _isFil ? 'Offline Comms' : 'Offline Comms';
  String get feed => 'Feed';
  String get notifications => _isFil ? 'Mga Abiso' : 'Notifications';
  String get profile => 'Profile';
  String get noReportsYet =>
      _isFil ? 'Wala pang ulat. Pindutin ang + para magsumite.' : 'No reports yet. Tap + to submit one.';

  String reportTitle(String reportId) =>
      _isFil ? 'Ulat #$reportId' : 'Report #$reportId';
  String get reportNotFound =>
      _isFil ? 'Hindi nakita ang ulat.' : 'Report not found.';
  String get severity => _isFil ? 'Tindi' : 'Severity';
  String severityValue(String severity) =>
      '${_isFil ? 'Tindi' : 'Severity'}: ${severityLabel(severity)}';
  String get location => _isFil ? 'Lokasyon' : 'Location';
  String get photos => _isFil ? 'Mga Larawan' : 'Photos';
  String get escalated => _isFil ? 'Na-escalate' : 'Escalated';
  String get statusHistory => _isFil ? 'Kasaysayan ng Status' : 'Status History';
  String get noStatusUpdatesYet =>
      _isFil ? 'Wala pang update sa status.' : 'No status updates yet.';
  String get departmentResponses =>
      _isFil ? 'Mga Tugon ng Departamento' : 'Department Responses';
  String get unknownDepartment =>
      _isFil ? 'Hindi kilalang departamento' : 'Unknown';

  String get departmentTitle => _isFil ? 'Departamento' : 'Department';
  String get noDepartmentProfileFound =>
      _isFil ? 'Walang nakitang department profile.' : 'No department profile found.';
  String get awaitingVerification =>
      _isFil ? 'Naghihintay ng Beripikasyon' : 'Awaiting Verification';
  String pendingDepartmentMessage(String name) => _isFil
      ? 'Ang rehistro ng $name ay naghihintay ng pag-apruba ng munisipyo.'
      : 'Your registration for $name is pending municipality approval.';
  String get registrationRejected =>
      _isFil ? 'Tinanggihan ang Rehistro' : 'Registration Rejected';
  String rejectionReason(String reason) =>
      _isFil ? 'Dahilan: $reason' : 'Reason: $reason';
  String get resubmitPrompt => _isFil
      ? 'Maaari mong i-update ang mga detalye at muling magsumite para sa beripikasyon.'
      : 'You can update your details and resubmit for verification.';
  String get editAndResubmit =>
      _isFil ? 'I-edit at Muling Isumite' : 'Edit & Resubmit';
  String get organizationName =>
      _isFil ? 'Pangalan ng organisasyon' : 'Organization name';
  String get contactNumber =>
      _isFil ? 'Numero ng kontak' : 'Contact number';
  String get contact => _isFil ? 'Kontak' : 'Contact';
  String get address => _isFil ? 'Address' : 'Address';
  String get areaOfResponsibility =>
      _isFil ? 'Saklaw na lugar' : 'Area of responsibility';
  String get area => _isFil ? 'Lugar' : 'Area';
  String get type => _isFil ? 'Uri' : 'Type';
  String get resubmit => _isFil ? 'Muling Isumite' : 'Resubmit';
  String get cancel => _isFil ? 'Kanselahin' : 'Cancel';
  String get verified => _isFil ? 'Beripikado' : 'Verified';
  String get incidentBoard => _isFil ? 'Lupon ng Insidente' : 'Incident Board';
  String get incidentBoardSubtitle =>
      _isFil ? 'Tingnan at tugunan ang mga ulat' : 'View and respond to reports';
  String get createPost => _isFil ? 'Gumawa ng Post' : 'Create Post';
  String get createPostSubtitle =>
      _isFil ? 'Maglabas ng anunsyo' : 'Publish an announcement';
  String get damageAssessment =>
      _isFil ? 'Pagtatasa ng Pinsala' : 'Damage Assessment';
  String get damageAssessmentSubtitle =>
      _isFil ? 'Magsumite ng field assessments' : 'Submit field assessments';
  String get communityFeed => _isFil ? 'Community Feed' : 'Community Feed';
  String get communityFeedSubtitle =>
      _isFil ? 'Basahin ang mga pampublikong anunsyo' : 'Browse public announcements';
  String get notificationsSubtitle =>
      _isFil ? 'Tingnan ang alerts at updates' : 'Check alerts and updates';
  String unreadMeshMessages(int count) => _isFil
      ? '$count hindi pa nababasang mesh message'
      : '$count unread mesh messages';
  String get meshPostsSubtitle => _isFil
      ? 'Broadcasts, usapan ng departamento, at mesh posts'
      : 'Broadcasts, department chatter, and mesh posts';
  String get meshSar => _isFil ? 'Mesh at SAR' : 'Mesh & SAR';
  String get meshSarSubtitle =>
      _isFil ? 'Offline relay, sync status, at survivor feed' : 'Offline relay, sync status, and survivor feed';
  String get emergencySosSubtitle =>
      _isFil ? 'Magpadala ng distress signal (walang login)' : 'Send distress signal (no login)';

  String get municipalityKicker =>
      _isFil ? 'Municipality shell' : 'Municipality shell';
  String get municipalityTitle =>
      _isFil ? 'Pundasyon ng Pangangasiwa' : 'Oversight foundation';
  String get municipalityPlaceholderVerification => _isFil
      ? 'Mananatiling web-first ang beripikasyon ng departamento sa Phase 1.'
      : 'Department verification remains web-first in Phase 1.';
  String get municipalityPlaceholderMobile => _isFil
      ? 'Maaaring manatili rito ang magaang na municipality placeholders sa mobile.'
      : 'Lightweight municipality placeholders can still live here on mobile.';
  String get municipalityPlaceholderPhase3 => _isFil
      ? 'Mas magiging mahalaga ang analytics at assessments sa mga susunod na phase.'
      : 'Analytics and assessments become meaningful in later phases.';

  String get assessmentScreenTitle =>
      _isFil ? 'Pagtatasa ng Pinsala' : 'Damage Assessment';
  String get newAssessment => _isFil ? 'Bagong Pagtatasa' : 'New Assessment';
  String get assessmentSubmitted =>
      _isFil ? 'Naipasa ang pagtatasa' : 'Assessment submitted';
  String get affectedArea => _isFil ? 'Apektadong Lugar *' : 'Affected Area *';
  String get damageLevel => _isFil ? 'Antas ng Pinsala' : 'Damage Level';
  String get estimatedCasualties =>
      _isFil ? 'Tinatayang Nasawi' : 'Estimated Casualties';
  String get displacedPersons =>
      _isFil ? 'Mga Lumikas' : 'Displaced Persons';
  String get description => _isFil ? 'Paglalarawan' : 'Description';
  String get submitAssessment =>
      _isFil ? 'Isumite ang Pagtatasa' : 'Submit Assessment';
  String get submitting => _isFil ? 'Isinusumite...' : 'Submitting...';
  String get previousAssessments =>
      _isFil ? 'Mga Naunang Pagtatasa' : 'Previous Assessments';
  String get noAssessmentsSubmittedYet => _isFil
      ? 'Wala pang naisumiteng pagtatasa.'
      : 'No assessments submitted yet.';
  String get required => _isFil ? 'Kailangan' : 'Required';

  String casualtiesAndDisplaced(int casualties, int displaced) => _isFil
      ? 'Nasawi: $casualties  |  Lumikas: $displaced'
      : 'Casualties: $casualties  |  Displaced: $displaced';

  String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return _isFil ? 'Nakabinbin' : 'Pending';
      case 'accepted':
        return _isFil ? 'Tinanggap' : 'Accepted';
      case 'responding':
        return _isFil ? 'Tumutugon' : 'Responding';
      case 'resolved':
        return _isFil ? 'Nalutas' : 'Resolved';
      case 'declined':
        return _isFil ? 'Tinanggihan' : 'Declined';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String categoryLabel(String category) {
    switch (category) {
      case 'fire':
        return _isFil ? 'Sunog' : 'Fire';
      case 'flood':
        return _isFil ? 'Baha' : 'Flood';
      case 'earthquake':
        return _isFil ? 'Lindol' : 'Earthquake';
      case 'road_accident':
        return _isFil ? 'Aksidente sa Kalsada' : 'Road accident';
      case 'medical':
        return _isFil ? 'Medikal' : 'Medical';
      case 'structural':
        return _isFil ? 'Istruktural' : 'Structural';
      case 'other':
        return _isFil ? 'Iba pa' : 'Other';
      default:
        return category.replaceAll('_', ' ');
    }
  }

  String severityLabel(String severity) {
    switch (severity) {
      case 'low':
        return _isFil ? 'Mababa' : 'Low';
      case 'medium':
        return _isFil ? 'Katamtaman' : 'Medium';
      case 'high':
        return _isFil ? 'Mataas' : 'High';
      case 'critical':
        return _isFil ? 'Kritikal' : 'Critical';
      default:
        return severity.replaceAll('_', ' ');
    }
  }

  String damageLevelLabel(String level) {
    switch (level) {
      case 'minor':
        return _isFil ? 'Magaan' : 'Minor';
      case 'moderate':
        return _isFil ? 'Katamtaman' : 'Moderate';
      case 'severe':
        return _isFil ? 'Malubha' : 'Severe';
      case 'critical':
        return _isFil ? 'Kritikal' : 'Critical';
      default:
        return level.replaceAll('_', ' ');
    }
  }

  String responseActionLabel(String action) {
    switch (action) {
      case 'accepted':
        return _isFil ? 'Tinanggap' : 'Accepted';
      case 'declined':
        return _isFil ? 'Tinanggihan' : 'Declined';
      case 'pending':
        return _isFil ? 'Nakabinbin' : 'Pending';
      default:
        return action.replaceAll('_', ' ');
    }
  }
}
