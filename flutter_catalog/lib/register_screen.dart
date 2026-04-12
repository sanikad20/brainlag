//import 'dart:convert';
import 'package:flutter/material.dart';
//import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

//import 'config/api_config.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  Future<void> registerUser() async {
  final name = nameController.text.trim();
  final email = emailController.text.trim();
  final password = passwordController.text.trim();

  if (name.isEmpty || email.isEmpty || password.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please fill all fields')),
    );
    return;
  }

  setState(() => isLoading = true);

  try {
    UserCredential userCredential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Optional: store name
    await userCredential.user?.updateDisplayName(name);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registration successful')),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  } on FirebaseAuthException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message ?? 'Registration failed')),
    );
  } finally {
    if (!mounted) return;
    setState(() => isLoading = false);
  }
}

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F3F3),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Register',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: 95,
                    height: 95,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : registerUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF45199D),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Register',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    child: const Text('Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}