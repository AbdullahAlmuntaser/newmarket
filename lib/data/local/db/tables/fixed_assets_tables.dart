import 'package:drift/drift.dart';

// جدول فئات الأصول الثابتة
class AssetCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 100)();
  TextColumn get code => text().withLength(min: 2, max: 50)();
  RealColumn get defaultDepreciationRate => real().withDefault(const Constant(0.0))(); // نسبة الإهلاك السنوية الافتراضية
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول الأصول الثابتة
class FixedAssets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 150)();
  TextColumn get serialNumber => text().nullable()();
  IntColumn get categoryId => integer().references(AssetCategories, #id)();
  RealColumn get purchaseCost => real()(); // تكلفة الشراء
  DateTimeColumn get purchaseDate => dateTime()();
  DateTimeColumn get acquisitionDate => dateTime()(); // تاريخ البدء في الإهلاك
  RealColumn get salvageValue => real().withDefault(const Constant(0.0))(); // قيمة الخردة
  IntColumn get usefulLifeMonths => integer()(); // العمر الإنتاجي بالشهور
  TextColumn get depreciationMethod => text().withDefault(const Constant('straight_line'))(); // straight_line, declining
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, sold, scrapped
  IntColumn get accumulatedDepreciation => integer().withDefault(const Constant(0))();
  // ملاحظة: currentBookValue يُحسب برمجياً
  DateTimeColumn get lastDepreciationDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول حركات إهلاك الأصول
class AssetDepreciationLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get assetId => integer().references(FixedAssets, #id)();
  RealColumn get depreciationAmount => real()();
  DateTimeColumn get depreciationDate => dateTime()();
  IntColumn get journalEntryId => integer().nullable(); // ربط بالقيد المحاسبي (سيتم الربط يدوياً أو عبر خدمة)
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول بيع أو خروج الأصول
class AssetDisposals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get assetId => integer().references(FixedAssets, #id)();
  DateTimeColumn get disposalDate => dateTime()();
  RealColumn get salePrice => real().nullable()();
  TextColumn get disposalType => text()(); // sold, scrapped
  RealColumn get gainOrLoss => real().nullable()(); // الربح أو الخسارة
  IntColumn get journalEntryId => integer().nullable();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
