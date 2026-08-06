import 'package:esec_bus/features/authentication/presentation/login.dart';
import 'package:flutter/material.dart';

import 'package:esec_bus/core/services/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      onPressed: () async {
        await AuthService.logout();

        if (!context.mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      },
    );
  }
}
