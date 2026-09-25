import 'package:flutter/material.dart';
import '../../../data/models/class_model.dart';
import '../../../controllers/auth_controller.dart';
import 'package:get/get.dart';

class ClassFormDialog extends StatefulWidget {
  final ClassModel? initialClass;

  const ClassFormDialog({super.key, this.initialClass});

  @override
  State<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _semesterCtrl;
  late TextEditingController _roomCtrl;
  late TextEditingController _scheduleCtrl;
  late TextEditingController _studentsCtrl;
  ClassType _type = ClassType.courseSection;

  @override
  void initState() {
    super.initState();
    final c = widget.initialClass;
    _codeCtrl = TextEditingController(text: c?.code ?? '');
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _semesterCtrl = TextEditingController(text: c?.semester ?? '');
    _roomCtrl = TextEditingController(text: c?.room ?? '');
    _scheduleCtrl = TextEditingController(text: c?.schedule ?? '');
    _studentsCtrl = TextEditingController(text: c?.studentCount.toString() ?? '');
    if (c != null) _type = c.type;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _semesterCtrl.dispose();
    _roomCtrl.dispose();
    _scheduleCtrl.dispose();
    _studentsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final auth = Get.find<AuthController>();
      final isEdit = widget.initialClass != null;
      
      final c = ClassModel(
        id: isEdit ? widget.initialClass!.id : DateTime.now().millisecondsSinceEpoch.toString(),
        code: _codeCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        type: _type,
        lecturerId: auth.currentUser.value?.email ?? '',
        lecturerName: auth.currentUser.value?.name ?? '',
        studentCount: int.tryParse(_studentsCtrl.text) ?? 0,
        semester: _semesterCtrl.text.trim(),
        room: _roomCtrl.text.trim(),
        schedule: _scheduleCtrl.text.trim(),
      );

      Navigator.of(context).pop(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialClass != null;
    return AlertDialog(
      title: Text(isEdit ? 'Sửa lớp học' : 'Thêm lớp học'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Mã lớp *'),
                validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Tên lớp *'),
                validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
              ),
              DropdownButtonFormField<ClassType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Loại lớp'),
                items: ClassType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.label),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              TextFormField(
                controller: _semesterCtrl,
                decoration: const InputDecoration(labelText: 'Học kỳ *'),
                validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
              ),
              TextFormField(
                controller: _roomCtrl,
                decoration: const InputDecoration(labelText: 'Phòng học'),
              ),
              TextFormField(
                controller: _scheduleCtrl,
                decoration: const InputDecoration(labelText: 'Lịch học'),
              ),
              TextFormField(
                controller: _studentsCtrl,
                decoration: const InputDecoration(labelText: 'Sĩ số'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Lưu' : 'Thêm'),
        ),
      ],
    );
  }
}
