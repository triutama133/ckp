import 'package:flutter/material.dart';

class TransactionCard extends StatelessWidget {
  final double amount;
  final String category;
  final String description;

  const TransactionCard({super.key, required this.amount, required this.category, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text('Rp ${amount.toStringAsFixed(0)}'),
        subtitle: Text('$category • $description'),
      ),
    );
  }
}
