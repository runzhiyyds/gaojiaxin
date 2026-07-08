import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/mall/mall_good_model.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/mall/preset_mall_goods.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';

class MallGoodEditScreen extends StatefulWidget {
  const MallGoodEditScreen({super.key, this.goodId});

  final String? goodId;

  @override
  State<MallGoodEditScreen> createState() => _MallGoodEditScreenState();
}

class _MallGoodEditScreenState extends State<MallGoodEditScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _pointsController = TextEditingController(text: '10');
  final _stockController = TextEditingController();
  bool _unlimitedStock = true;
  bool _loading = false;
  String? _category;
  bool get _isCreate => widget.goodId == null;

  @override
  void initState() {
    super.initState();
    if (widget.goodId != null) _load();
  }

  Future<void> _load() async {
    if (widget.goodId == null) return;
    final good = await context.read<MallRepository>().getGood(widget.goodId!);
    if (good != null && mounted) {
      _nameController.text = good.name;
      _descController.text = good.description ?? '';
      _pointsController.text = good.pointsRequired.toString();
      _unlimitedStock = good.stock == null;
      _stockController.text = good.stock?.toString() ?? '';
      _category = good.category;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _pointsController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入商品名称')));
      return;
    }
    final points = int.tryParse(_pointsController.text);
    if (points == null || points < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所需心意值至少为 1')));
      return;
    }
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    int? stock;
    if (!_unlimitedStock) {
      final s = int.tryParse(_stockController.text);
      if (s == null || s < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效库存')));
        return;
      }
      stock = s;
    }
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<MallRepository>();
      if (_isCreate) {
        await repo.createGood(
          coupleSpaceId: spaceId,
          ownerId: userId,
          name: name,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          pointsRequired: points,
          stock: stock,
          category: _category?.isEmpty ?? true ? null : _category,
        );
      } else {
        await repo.updateGood(
          id: widget.goodId!,
          name: name,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          pointsRequired: points,
          stock: stock,
          category: _category?.isEmpty ?? true ? null : _category,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'MallGoodEditScreen.save'))));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goodId == null ? '添加商品' : '编辑商品'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '商品名称', hintText: '如：一次按摩'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: '描述（选填）'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pointsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '所需心意值'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category?.isEmpty ?? true ? null : _category,
              decoration: const InputDecoration(labelText: '品类（选填）'),
              items: [
                const DropdownMenuItem(value: null, child: Text('无')),
                ...MallCategory.all.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('不限库存'),
              value: _unlimitedStock,
              onChanged: (v) => setState(() => _unlimitedStock = v),
            ),
            if (!_unlimitedStock) ...[
              TextField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '库存数量'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
