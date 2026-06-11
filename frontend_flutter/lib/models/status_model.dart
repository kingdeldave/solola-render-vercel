// Modèle documentaire pour les statuts Solola.
class SololaStatusModel {
  final int id;
  final String userId;
  final int fileId;
  final String caption;

  const SololaStatusModel({required this.id, required this.userId, required this.fileId, required this.caption});
}
