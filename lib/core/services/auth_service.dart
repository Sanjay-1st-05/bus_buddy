import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/shared/models/app_user.dart';
import 'session.dart';

class AuthResult {
  final bool success;
  final String? message;

  const AuthResult.success() : success = true, message = null;

  const AuthResult.failure(this.message) : success = false;
}

class AuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get firebaseUser => _auth.currentUser;

  static Future<AuthResult> login({
    required String id,
    required String password,
  }) async {
    if (id.trim().isEmpty || password.trim().isEmpty) {
      return const AuthResult.failure("Enter ID and Password");
    }

    final normalizedId = _normalizeId(id);

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: _emailFor(normalizedId),
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return const AuthResult.failure("Login failed");
      }

      final loaded = await _loadProfile(firebaseUser.uid);
      if (loaded == null) {
        await _auth.signOut();
        return const AuthResult.failure("Invalid account data");
      }
      if (!loaded.active) {
        await _auth.signOut();
        return const AuthResult.failure("Account disabled");
      }

      Session.setCurrentUser(loaded);
      return const AuthResult.success();
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_messageFor(error));
    }
  }

  static Future<bool> restoreSession() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      Session.clear();
      return false;
    }

    try {
      await firebaseUser.reload();
      final user = await _loadProfile(firebaseUser.uid);
      if (user == null || !user.active) {
        await logout();
        return false;
      }

      Session.setCurrentUser(user);
      return true;
    } on FirebaseAuthException {
      await logout();
      return false;
    } on FirebaseException {
      Session.clear();
      return false;
    }
  }

  static Future<void> logout() async {
    await _auth.signOut();
    Session.clear();
  }

  static Future<AppUser?> _loadProfile(String uid) async {
    final userDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .get();
    final data = userDoc.data();
    if (!userDoc.exists || data == null) return null;
    return _parseUser(uid, data);
  }

  static String _normalizeId(String value) => value.trim().toLowerCase();

  static String _emailFor(String id) => '$id@auth.busbuddy.bytbeta.com';

  static String _messageFor(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Invalid ID or password',
      'user-disabled' => 'Account disabled',
      'too-many-requests' => 'Too many attempts. Try again later',
      'network-request-failed' => 'Network unavailable',
      _ => 'Login failed',
    };
  }

  static AppUser? _parseUser(String id, Map<String, dynamic> data) {
    try {
      return AppUser.fromMap(id: id, data: data);
    } on FormatException {
      return null;
    }
  }
}
