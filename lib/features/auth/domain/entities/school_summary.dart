/// The school (tenant) the signed-in user belongs to.
///
/// Mirrors the `school` object returned by `/api/auth/me`, itself a projection
/// of the `schools` table.
///
/// The school id here is **informational only**. Every request is scoped
/// server-side from the session (`getSessionSchoolId`), and the backend
/// ignores any `school_id` a client supplies. Sending one from the app would
/// be both useless and a misreading of the tenant model — see ADR-0008.
class SchoolSummary {
  /// Creates a school summary.
  const SchoolSummary({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.schoolType,
    this.logoUrl,
    this.currency = 'UGX',
    this.setupComplete = true,
  });

  /// `schools.id`. Informational — never send it as a request parameter.
  final int id;

  /// `schools.name`.
  final String name;

  /// Contact email.
  final String? email;

  /// Contact phone.
  final String? phone;

  /// Postal or physical address.
  final String? address;

  /// `schools.school_type`, e.g. primary or secondary.
  final String? schoolType;

  /// Absolute URL of the school's logo, typically Cloudinary-hosted.
  final String? logoUrl;

  /// ISO currency code. Defaults to `UGX`, matching the backend default.
  final String currency;

  /// `schools.setup_complete`. When false the backend gates most features and
  /// returns `SETUP_INCOMPLETE`; setup itself is a web-only flow.
  final bool setupComplete;

  @override
  String toString() => 'SchoolSummary($id, $name)';
}
