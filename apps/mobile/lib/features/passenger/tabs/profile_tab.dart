import 'package:flutter/material.dart';

import '../../account/account_page.dart';
import '../../booking/ui/booking_scope.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
        token: BookingScope.of(context).session.token, role: 'passenger');
  }
}
