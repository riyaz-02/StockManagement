/// Bilingual display of names.
///
/// The app language is chosen on the login screen ('bn' or 'en'). When a
/// Bengali name is saved, the language the user picked comes first and the
/// other one follows in brackets:
///
///   Bengali selected:  রাহুল দাস (Rahul Das)
///   English selected:  Rahul Das (রাহুল দাস)
///
/// If only one of the two exists, that one is shown on its own.
String bilingualName(String? english, String? bengali, String language) {
  final en = (english ?? '').trim();
  final bn = (bengali ?? '').trim();
  if (bn.isEmpty) return en;
  if (en.isEmpty) return bn;
  if (bn == en) return en;
  return language == 'bn' ? '$bn ($en)' : '$en ($bn)';
}
