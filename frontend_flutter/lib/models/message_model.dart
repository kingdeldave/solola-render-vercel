// Modèle documentaire pour les messages Solola.
class SololaMessageModel {
  final int id;
  final int conversationId;
  final String senderId;
  final String messageType;
  final String? content;

  const SololaMessageModel({required this.id, required this.conversationId, required this.senderId, required this.messageType, this.content});
}
