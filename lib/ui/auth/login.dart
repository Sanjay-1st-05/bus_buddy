import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_entry.dart';
import '../../services/session.dart';
import '../widgets/primary_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  Future<void> _login() async {
    final id = idController.text.trim();
    final password = passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      _showMessage("Enter ID and Password");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(id)
          .get();

      if (!userDoc.exists) {
        _showMessage("Invalid ID");
        setState(() => isLoading = false);
        return;
      }

      final data = userDoc.data()!;

      final role = data["role"];
      final active = data["active"] ?? false;

      if (active != true) {
        _showMessage("Account Disabled");
        setState(() => isLoading = false);
        return;
      }

      /// ADMIN / DRIVER LOGIN
      if (role == "admin" || role == "driver") {
        final dbPassword = data["password"];

        if (dbPassword == null || password != dbPassword) {
          _showMessage("Wrong Password");
          setState(() => isLoading = false);
          return;
        }
      }

      /// STUDENT LOGIN
      if (role == "student") {
        final configDoc = await FirebaseFirestore.instance
            .collection("app_settings")
            .doc("student_config")
            .get();

        if (!configDoc.exists) {
          _showMessage("Student config missing");
          setState(() => isLoading = false);
          return;
        }

        final defaultPassword = configDoc.data()?["defaultPassword"];

        if (password != defaultPassword) {
          _showMessage("Wrong Password");
          setState(() => isLoading = false);
          return;
        }
      }

      /// SAVE SESSION
      Session.role = role;
      Session.userId = id;

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppEntry()),
        (route) => false,
      );
    } catch (e) {
      print("LOGIN ERROR: $e");
      _showMessage("Login Failed");
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    idController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,

        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 80),

                /// LOGO
                Container(
                  height: 150,
                  width: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset("assets/logo.jpeg", fit: BoxFit.cover),
                  ),
                ),

                const SizedBox(height: 25),

                const Text(
                  "ESEC BUS",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 40),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Column(
                      children: [
                        /// ID FIELD
                        TextField(
                          controller: idController,
                          decoration: const InputDecoration(
                            labelText: "College ID",
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        /// PASSWORD FIELD
                        TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  obscurePassword = !obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),

                        /// LOGIN BUTTON
                        isLoading
                            ? const CircularProgressIndicator()
                            : PrimaryButton(
                                text: "Login",
                                icon: Icons.login,
                                onPressed: _login,
                              ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  "Powered by CODE INHALERS",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
