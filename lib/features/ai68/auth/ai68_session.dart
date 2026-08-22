final class Ai68Session {
  const Ai68Session({
    required this.apiAuthorization,
    required this.subscriptionToken,
    required this.isAdmin,
  });

  factory Ai68Session.fromJson(Map<String, dynamic> json) {
    final apiAuthorization = json['auth_data'];
    final subscriptionToken = json['token'];
    if (apiAuthorization is! String || apiAuthorization.trim().isEmpty) {
      throw const FormatException('Missing AI68 API authorization');
    }
    if (subscriptionToken is! String || subscriptionToken.trim().isEmpty) {
      throw const FormatException('Missing AI68 subscription token');
    }
    final isAdminValue = json['is_admin'];
    return Ai68Session(
      apiAuthorization: apiAuthorization.trim(),
      subscriptionToken: subscriptionToken.trim(),
      isAdmin: isAdminValue == true || isAdminValue == 1,
    );
  }

  final String apiAuthorization;
  final String subscriptionToken;
  final bool isAdmin;

  String get authorizationHeader {
    if (apiAuthorization.toLowerCase().startsWith('bearer ')) {
      return apiAuthorization;
    }
    return 'Bearer $apiAuthorization';
  }
}
