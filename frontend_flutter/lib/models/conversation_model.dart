// Modèle documentaire pour les conversations Solola.
class SololaConversationModel {
  final int id;
  final String type;
  final String title;
  final bool isSecure;

  const SololaConversationModel({required this.id, required this.type, required this.title, required this.isSecure});
}
