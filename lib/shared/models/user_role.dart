enum UserRole {
  admin("admin"),
  driver("driver"),
  student("student");

  final String value;

  const UserRole(this.value);

  static UserRole? fromValue(String? value) {
    for (final role in UserRole.values) {
      if (role.value == value) {
        return role;
      }
    }

    return null;
  }
}
