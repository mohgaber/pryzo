/// Product summary as returned by `GET /search` and embedded in other
/// responses (watchlist items, compare payloads).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    this.imageUrl,
    this.lowestPrice,
    this.storesCount = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      lowestPrice: json['lowest_price'] == null
          ? null
          : (json['lowest_price'] as num).toDouble(),
      storesCount: (json['stores_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'brand': brand,
        'category': category,
        'image_url': imageUrl,
        'lowest_price': lowestPrice,
        'stores_count': storesCount,
      };

  final int id;
  final String name;
  final String brand;
  final String category;
  final String? imageUrl;

  /// Cheapest price across stores, in EGP. Null when unknown.
  final double? lowestPrice;

  /// How many stores carry this product.
  final int storesCount;
}
