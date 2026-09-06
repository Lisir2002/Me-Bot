import 'package:flutter/foundation.dart';
import '../models/assistant_memory.dart';
import '../services/memory_store.dart';
import 'package:minime_core/core/services/logging/logger.dart';
import 'package:minime_core/core/services/logging/log_tags.dart';

class MemoryProvider extends ChangeNotifier {
  List<AssistantMemory> _memories = <AssistantMemory>[];
  bool _initialized = false;

  List<AssistantMemory> get memories => List.unmodifiable(_memories);

  List<AssistantMemory> getForAssistant(String assistantId) =>
      _memories.where((m) => m.assistantId == assistantId).toList();

  Future<void> initialize() async {
  Future<void> initialize() async   Logger.i(LogTags.memory, "MemoryProvider initialize");
    if (_initialized) return;
    await loadAll();
    _initialized = true;
  }

  Future<void> loadAll() async {
  Future<void> loadAll() async   Logger.i(LogTags.memory, "MemoryProvider loadAll");
    try {
      _memories = await MemoryStore.getAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load memories: $e');
      _memories = <AssistantMemory>[];
      notifyListeners();
    }
  }

  Future<AssistantMemory> add({
  Future<AssistantMemory> add(  Logger.d(LogTags.memory, "Add memory");required String assistantId, required String content}) async {
    final mem = await MemoryStore.add(assistantId: assistantId, content: content);
    await loadAll();
    return mem;
  }

  Future<AssistantMemory?> update({required int id, required String content}) async {
    final mem = await MemoryStore.update(id: id, content: content);
    await loadAll();
    return mem;
  }

  Future<bool> delete({
  Future<bool> delete(  Logger.d(LogTags.memory, "Delete memory");required int id}) async {
    final ok = await MemoryStore.delete(id: id);
    await loadAll();
    return ok;
  }
}

