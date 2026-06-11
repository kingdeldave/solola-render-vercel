// Modèle documentaire pour structurer les données utilisateur côté Flutter.
// Le runtime actuel consomme encore les Maps JSON afin de rester compatible avec l'API existante.
class SololaUserModel {
  final String id;
  final String phoneNumber;
  final String pseudo;
  final String? avatarUrl;

  const SololaUserModel({required this.id, required this.phoneNumber, required this.pseudo, this.avatarUrl});
}
