enum ProductMediaRole { sellerEvidence, sellerWorn, demoCatalog }

extension ProductMediaRolePresentation on ProductMediaRole {
  String get label => switch (this) {
    ProductMediaRole.sellerEvidence => 'SELLER PHOTO',
    ProductMediaRole.sellerWorn => 'SELLER WORN',
    ProductMediaRole.demoCatalog => 'DEMO IMAGE',
  };

  String get disclosure => switch (this) {
    ProductMediaRole.sellerEvidence =>
      'Seller-provided photo. Inspect every image and request labels, measurements, and flaw close-ups before buying.',
    ProductMediaRole.sellerWorn =>
      'Seller-provided worn photo. Use it for styling context, then verify the item in clear product and detail photos.',
    ProductMediaRole.demoCatalog =>
      'Demo catalog image for this preview—not verified evidence of a one-of-one seller item.',
  };
}

class Product {
  final String id;
  final String name;
  final String brand;
  final double price;
  final String image;
  final bool isAssetImage;
  final ProductMediaRole mediaRole;
  final String category;
  final String condition;
  final String seller;
  final String sellerHandle;
  final String vibe;
  final String description;
  final List<String> tags;
  final List<String> sizes;

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.image,
    this.isAssetImage = false,
    this.mediaRole = ProductMediaRole.demoCatalog,
    required this.category,
    required this.condition,
    required this.seller,
    required this.sellerHandle,
    required this.vibe,
    required this.description,
    required this.tags,
    required this.sizes,
  });

  bool matches(String value) {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = [
      name,
      brand,
      category,
      condition,
      seller,
      sellerHandle,
      vibe,
      description,
      price.toStringAsFixed(0),
      ...tags,
      ...sizes,
    ].join(' ').toLowerCase();
    final tokens = needle
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty);
    return tokens.every(haystack.contains);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'price': price,
    'image': image,
    'isAssetImage': isAssetImage,
    'mediaRole': mediaRole.name,
    'category': category,
    'condition': condition,
    'seller': seller,
    'sellerHandle': sellerHandle,
    'vibe': vibe,
    'description': description,
    'tags': tags,
    'sizes': sizes,
  };

  factory Product.fromJson(Map<String, Object?> json) => Product(
    id: json['id']! as String,
    name: json['name']! as String,
    brand: json['brand']! as String,
    price: (json['price']! as num).toDouble(),
    image: json['image']! as String,
    isAssetImage: json['isAssetImage'] as bool? ?? false,
    mediaRole: ProductMediaRole.values.firstWhere(
      (role) => role.name == json['mediaRole'],
      orElse: () => ProductMediaRole.demoCatalog,
    ),
    category: json['category']! as String,
    condition: json['condition']! as String,
    seller: json['seller']! as String,
    sellerHandle: json['sellerHandle']! as String,
    vibe: json['vibe']! as String,
    description: json['description']! as String,
    tags: (json['tags']! as List).cast<String>(),
    sizes: (json['sizes']! as List).cast<String>(),
  );
}

class SellerStory {
  final String seller;
  final String handle;
  final String title;
  final String accent;
  final List<String> productIds;

  const SellerStory({
    required this.seller,
    required this.handle,
    required this.title,
    required this.accent,
    required this.productIds,
  });
}

class ShopperRank {
  final int rank;
  final String name;
  final String handle;
  final double spent;
  final int orders;

  const ShopperRank({
    required this.rank,
    required this.name,
    required this.handle,
    required this.spent,
    required this.orders,
  });
}
