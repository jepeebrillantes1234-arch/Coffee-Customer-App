double dbl(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

String peso(num v) => '₱${v.toStringAsFixed(2)}';

String timeText(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String dateTimeText(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.month}/${d.day} ${timeText(iso)}';
}

List<Map<String, dynamic>> mapList(dynamic v) =>
    (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

String payLabel(dynamic method) {
  switch ('$method') {
    case 'cod':
      return 'Cash on Delivery';
    case 'cash':
      return 'Cash sa shop';
    case 'gcash':
      return 'QRPh';
    default:
      return '$method'.toUpperCase();
  }
}
