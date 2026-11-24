import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AgentOfficeApp());

class AgentOfficeApp extends StatelessWidget {
  const AgentOfficeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Agent Office',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true,
        ),
        home: const OfficePage(),
      );
}

class OfficeTask {
  OfficeTask({
    required this.id,
    required this.goal,
    required this.steps,
    this.results = const [],
    this.status = 'Needs approval',
    this.error,
  });

  final String id;
  final String goal;
  final List<String> steps;
  List<String> results;
  String status;
  String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'steps': steps,
        'results': results,
        'status': status,
        'error': error,
      };

  factory OfficeTask.fromJson(Map<String, dynamic> json) => OfficeTask(
        id: json['id'] as String,
        goal: json['goal'] as String,
        steps: List<String>.from(json['steps'] as List? ?? const []),
        results: List<String>.from(json['results'] as List? ?? const []),
        status: json['status'] as String? ?? 'Needs approval',
        error: json['error'] as String?,
      );
}

class LocalAgent {
  LocalAgent({required this.endpoint, required this.model});

  final String endpoint;
  final String model;

  Future<String> _chat(String prompt, {bool jsonFormat = false}) async {
    final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/chat');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'model': model,
        'stream': false,
        if (jsonFormat) 'format': 'json',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }));

      final response = await request.close().timeout(const Duration(seconds: 120));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Ollama returned HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final content = (decoded['message'] as Map<String, dynamic>?)?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw Exception('The local model returned an empty response.');
      }
      return content.trim();
    } on SocketException catch (error) {
      throw Exception('Cannot reach Ollama at $endpoint. Check the address and make sure Ollama is running. Details: $error');
    } on TimeoutException {
      throw Exception('The local model took too long to respond.');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> makePlan(String goal) async {
    final response = await _chat(
      'Create a practical plan for this task: "$goal". '
      'Return JSON only in this exact shape: '
      '{"steps":["short actionable step","another step"]}. '
      'Use 2 to 6 steps. Do not claim to have performed any work.',
      jsonFormat: true,
    );
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    final rawSteps = decoded['steps'];
    if (rawSteps is! List) throw Exception('The model did not return valid plan steps.');

    final steps = rawSteps
        .whereType<String>()
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .take(6)
        .toList();
    if (steps.isEmpty) throw Exception('The model returned an empty plan. Try again.');
    return steps;
  }

  Future<String> doStep({
    required String goal,
    required String step,
    required List<String> previousResults,
  }) {
    final previous = previousResults.isEmpty
        ? 'No previous work has been done.'
        : previousResults.asMap().entries.map((entry) => 'Step ${entry.key + 1} result:\n${entry.value}').join('\n\n');
    return _chat(
      'You are a helpful local project agent. Work on this one step of the user-approved task.\n\n'
      'Overall task: $goal\nCurrent step: $step\n\nPrevious work:\n$previous\n\n'
      'Provide the actual useful output for this step. Be clear about assumptions and limitations. '
      'Do not claim to access files, the web, or external services unless their contents were provided.',
    );
  }
}

class OfficePage extends StatefulWidget {
  const OfficePage({super.key});

  @override
  State<OfficePage> createState() => _OfficePageState();
}

class _OfficePageState extends State<OfficePage> {
  static const _tasksKey = 'agent_office_tasks';
  static const _endpointKey = 'agent_office_endpoint';
  static const _modelKey = 'agent_office_model';

  List<OfficeTask> _tasks = [];
  String _endpoint = 'http://10.0.2.2:11434';
  String _model = 'qwen2.5:3b';
  bool _loading = true;
  bool _creating = false;
  final Set<String> _runningTasks = {};

  LocalAgent get _agent => LocalAgent(endpoint: _endpoint, model: _model);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTasks = prefs.getString(_tasksKey);
    if (!mounted) return;
    setState(() {
      _endpoint = prefs.getString(_endpointKey) ?? _endpoint;
      _model = prefs.getString(_modelKey) ?? _model;
      if (savedTasks != null) {
        try {
          final decoded = jsonDecode(savedTasks) as List<dynamic>;
          _tasks = decoded.map((item) => OfficeTask.fromJson(item as Map<String, dynamic>)).toList();
        } catch (_) {
          _tasks = [];
        }
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tasksKey, jsonEncode(_tasks.map((task) => task.toJson()).toList()));
    await prefs.setString(_endpointKey, _endpoint);
    await prefs.setString(_modelKey, _model);
  }

  Future<void> _newTask() async {
    final controller = TextEditingController();
    final goal = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Describe the result you want...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create plan')),
        ],
      ),
    );
    controller.dispose();
    if (goal == null || goal.isEmpty || !mounted) return;

    setState(() => _creating = true);
    try {
      final steps = await _agent.makePlan(goal);
      if (!mounted) return;
      final task = OfficeTask(id: DateTime.now().microsecondsSinceEpoch.toString(), goal: goal, steps: steps);
      setState(() {
        _tasks.insert(0, task);
        _creating = false;
      });
      await _save();
    } catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create plan: $error')));
    }
  }

  Future<void> _runNextStep(OfficeTask task) async {
    if (_runningTasks.contains(task.id) || task.results.length >= task.steps.length) return;
    setState(() {
      _runningTasks.add(task.id);
      task.status = 'Working';
      task.error = null;
    });
    await _save();

    try {
      final result = await _agent.doStep(
        goal: task.goal,
        step: task.steps[task.results.length],
        previousResults: task.results,
      );
      if (!mounted) return;
      setState(() {
        task.results.add(result);
        task.status = task.results.length >= task.steps.length ? 'Done' : 'Approved';
        _runningTasks.remove(task.id);
      });
      await _save();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        task.status = 'Approved';
        task.error = error.toString();
        _runningTasks.remove(task.id);
      });
      await _save();
    }
  }

  Future<void> _approve(OfficeTask task) async {
    setState(() {
      task.status = 'Approved';
      task.error = null;
    });
    await _save();
  }

  Future<void> _delete(OfficeTask task) async {
    setState(() => _tasks.removeWhere((item) => item.id == task.id));
    await _save();
  }

  Future<void> _settings() async {
    final endpointController = TextEditingController(text: _endpoint);
    final modelController = TextEditingController(text: _model);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local model settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: endpointController, decoration: const InputDecoration(labelText: 'Ollama address', hintText: 'http://10.0.2.2:11434')),
          const SizedBox(height: 12),
          TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Installed model name', hintText: 'qwen2.5:3b')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, (endpointController.text.trim(), modelController.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    endpointController.dispose();
    modelController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _endpoint = result.$1;
      _model = result.$2;
    });
    await _save();
  }

  Widget _taskCard(OfficeTask task) {
    final running = _runningTasks.contains(task.id);
    final nextStep = task.results.length < task.steps.length ? task.steps[task.results.length] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(task.goal, style: Theme.of(context).textTheme.titleMedium)),
            PopupMenuButton<String>(
              onSelected: (value) { if (value == 'delete') _delete(task); },
              itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('Delete task'))],
            ),
          ]),
          const SizedBox(height: 8),
          Chip(label: Text(running ? 'Working' : task.status)),
          const SizedBox(height: 8),
          const Text('Plan', style: TextStyle(fontWeight: FontWeight.bold)),
          ...task.steps.asMap().entries.map((entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.key < task.results.length ? Icons.check_circle : Icons.radio_button_unchecked, size: 20),
                title: Text(entry.value),
              )),
          if (task.error != null) ...[
            const SizedBox(height: 8),
            Text(task.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (task.status == 'Needs approval') ...[
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: () => _approve(task), icon: const Icon(Icons.check), label: const Text('Approve plan')),
          ],
          if (task.status == 'Approved' && nextStep != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: running ? null : () => _runNextStep(task),
              icon: running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(running ? 'Working...' : 'Run next step'),
            ),
          ],
          for (var i = 0; i < task.results.length; i++) ...[
            const Divider(height: 24),
            Text('Result — ${task.steps[i]}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SelectableText(task.results[i]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Agent Office'),
          actions: [IconButton(tooltip: 'Local model settings', onPressed: _settings, icon: const Icon(Icons.settings))],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _creating ? null : _newTask,
          icon: _creating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(_creating ? 'Planning...' : 'New task'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tasks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No tasks yet.\n\nCreate a task to get a plan from your local AI model. Review and approve it before the agent starts.', textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Text('Local model: $_model', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      ..._tasks.map(_taskCard),
                    ],
                  ),
      );
}
