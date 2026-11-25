// Product thumbnail shared by the home rows, the comparison header and
// the watchlist rows.
//
// Only renders an image URL the API actually returned (Product.image_url).
// Sample data has image_url null, so sample products always show the
// placeholder. A broken/empty URL falls back to the same placeholder
// via [Image.network]'s errorBuilder — never a broken-image icon.

import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.imageUrl,
    this.size = 52,
    this.borderRadius = 10,
  });

  final String? imageUrl;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const Icon(
        Icons.shopping_bag_outlined,
        color: Color(0xFF475569),
        size: 28,
      ),
    );
  }
}
