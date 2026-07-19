enum QuarkTransferTaskStatus { pending, succeeded, failed, cancelled }

class QuarkTransferTask {
  const QuarkTransferTask({
    required this.id,
    required this.status,
    this.title,
    this.savedFileIds = const <String>[],
  });

  final String id;
  final QuarkTransferTaskStatus status;
  final String? title;
  final List<String> savedFileIds;

  @override
  String toString() => 'QuarkTransferTask(id: $id, status: ${status.name})';
}
