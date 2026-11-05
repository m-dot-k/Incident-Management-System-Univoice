import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../theme.dart';
import '../utils/ui.dart';
import '../widgets/home_scope.dart';
import '../widgets/status_text.dart';

class CreateIncidentScreen extends StatefulWidget {
  final User user;
  const CreateIncidentScreen({super.key, required this.user});

  @override
  State<CreateIncidentScreen> createState() => _CreateIncidentScreenState();
}

class _CreateIncidentScreenState extends State<CreateIncidentScreen> with SafeState<CreateIncidentScreen> {
  String _type = 'Жалоба';
  String _category = 'оборудование';
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _picker = ImagePicker();
  String _msg = '';
  bool _ok = false, _sending = false;
  File? _image;

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
      if (file != null) safeSetState(() => _image = File(file.path));
    } catch (e) {
      if (mounted) snack(context, pickErrorText(e));
    }
  }

  Future<void> _submit() async {
    if (_titleC.text.trim().length < 5 || _descC.text.trim().length < 20) {
      setState(() {
        _ok = false;
        _msg = 'Заполните заголовок (мин.5) и описание (мин.20)';
      });
      return;
    }
    setState(() {
      _sending = true;
      _msg = '';
    });

    final r = await Api.post('/incidents', {
      'type': _type,
      'category': _category,
      'title': _titleC.text.trim(),
      'description': _descC.text.trim(),
    });
    if (!mounted) return;

    String? photoError;
    if (r.status == 201 && _image != null && r.data is Map) {
      final up = await Api.uploadImage(
        '/incidents/${r.data['id']}/attachments',
        {},
        _image!,
      );
      if (!mounted) return;
      if (!up.ok) photoError = up.error('ошибка загрузки');
    }

    setState(() {
      _sending = false;
      _ok = r.status == 201;
      _msg = !_ok
          ? 'Ошибка: ${r.error('Не удалось создать')}'
          : photoError == null
              ? 'Обращение успешно создано!'
              : 'Обращение создано, но фото не загружено: $photoError';
      if (_ok) {
        _titleC.clear();
        _descC.clear();
        _image = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: HomeScope.backButton(context), title: const Text('Новое обращение')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: const [
                DropdownMenuItem(value: 'Жалоба', child: Text('Жалоба')),
                DropdownMenuItem(value: 'Предложение', child: Text('Предложение')),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
              decoration: const InputDecoration(labelText: 'Тип обращения', prefixIcon: Icon(Icons.category)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: const [
                DropdownMenuItem(value: 'оборудование', child: Text('Оборудование')),
                DropdownMenuItem(value: 'учебный процесс', child: Text('Учебный процесс')),
                DropdownMenuItem(value: 'инфраструктура', child: Text('Инфраструктура')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
              decoration: const InputDecoration(labelText: 'Категория', prefixIcon: Icon(Icons.folder)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleC,
              decoration: const InputDecoration(labelText: 'Заголовок (мин. 5 символов)', prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descC,
              decoration: const InputDecoration(
                labelText: 'Описание (минимум 20 символов)',
                prefixIcon: Icon(Icons.description),
                helperText: 'Опишите проблему подробно',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text('Доказательства (фото):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _image == null
                      ? const Center(key: ValueKey('empty'), child: Icon(Icons.photo_camera_outlined, size: 36, color: kMuted))
                      : ClipRRect(key: ValueKey(_image!.path), borderRadius: BorderRadius.circular(8), child: Image.file(_image!, fit: BoxFit.cover, width: 100, height: 100))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Сделать фото'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kSurface2,
                            foregroundColor: kText,
                            minimumSize: const Size(double.infinity, 40)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Выбрать из галереи'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_image != null)
              TextButton(
                onPressed: () => setState(() => _image = null),
                child: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sending ? null : _submit,
              icon: const Icon(Icons.send),
              label: const Text('Отправить обращение'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
            ),
            const SizedBox(height: 16),
            StatusText(_msg, ok: _ok),
          ],
        ),
      ),
    );
  }
}
