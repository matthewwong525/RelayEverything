/// One calendar on the phone: Google, iCloud, Outlook, work or subscribed. [account] is where it comes from, such as
/// an email address, to tell two calendars of the same name apart.
class PhoneCalendar {
  const PhoneCalendar({required this.id, required this.name, this.account});

  final String id;
  final String name;
  final String? account;
}
