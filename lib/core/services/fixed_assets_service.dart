import 'package:drift/drift.dart';
import '../../datasources/local/app_database.dart';
import '../../datasources/local/daos/accounting_dao.dart';

/// خدمة إدارة الأصول الثابتة وحساب الإهلاك
class FixedAssetsService {
  final AppDatabase db;

  FixedAssetsService(this.db);

  /// حساب الإهلاك الشهري لأصل معين
  Future<double> calculateMonthlyDepreciation(int assetId) async {
    final asset = await db.select(db.fixedAssets).where((t) => t.id.equals(assetId)).getSingle();
    
    double depreciableAmount = asset.purchaseCost - asset.salvageValue;
    
    if (asset.depreciationMethod == 'straight_line') {
      // طريقة القسط الثابت
      return depreciableAmount / asset.usefulLifeMonths;
    } else if (asset.depreciationMethod == 'declining') {
      // طريقة الرصيد المتناقص
      final annualRate = 2.0 / asset.usefulLifeMonths * 12; // مضاعفة المعدل
      final monthlyRate = annualRate / 12;
      final bookValue = asset.purchaseCost - asset.accumulatedDepreciation;
      return bookValue * monthlyRate;
    }
    
    return 0.0;
  }

  /// تشغيل الإهلاك الشهري لجميع الأصول النشطة
  Future<List<Map<String, dynamic>>> runMonthlyDepreciation(DateTime runDate) async {
    final results = <Map<String, dynamic>>[];
    final assets = await db.select(db.fixedAssets)
        .where((t) => t.status.equals('active'))
        .get();

    for (var asset in assets) {
      // التحقق من آخر تاريخ إهلاك
      if (asset.lastDepreciationDate != null) {
        final lastRun = asset.lastDepreciationDate!;
        if (runDate.month == lastRun.month && runDate.year == lastRun.year) {
          continue; // تم تشغيل الإهلاك لهذا الشهر بالفعل
        }
      }

      final depreciationAmount = await calculateMonthlyDepreciation(asset.id);
      
      if (depreciationAmount > 0) {
        // تسجيل حركة الإهلاك
        await db.into(db.assetDepreciationLogs).insert(
          AssetDepreciationLogsCompanion.insert(
            assetId: asset.id,
            depreciationAmount: depreciationAmount,
            depreciationDate: runDate,
          ),
        );

        // تحديث الأصل
        await db.update(db.fixedAssets).replace(
          asset.copyWith(
            accumulatedDepreciation: asset.accumulatedDepreciation + depreciationAmount.toInt(),
            lastDepreciationDate: runDate,
          ),
        );

        // إنشاء قيد محاسبي تلقائي
        final journalEntryId = await _createDepreciationJournalEntry(
          asset.id,
          depreciationAmount,
          runDate,
          asset.categoryId,
        );

        // تحديث سجل الإهلاك برقم القيد
        await db.update(db.assetDepreciationLogs).replace(
          (await db.select(db.assetDepreciationLogs)
              .orderBy([(t) => OrderingTerm.desc(t.id)])
              .limit(1)
              .getSingle())
          .copyWith(journalEntryId: journalEntryId),
        );

        results.add({
          'assetId': asset.id,
          'assetName': asset.name,
          'depreciationAmount': depreciationAmount,
          'journalEntryId': journalEntryId,
        });
      }
    }

    return results;
  }

  /// إنشاء قيد محاسبي للإهلاك
  Future<int> _createDepreciationJournalEntry(
    int assetId,
    double amount,
    DateTime date,
    int categoryId,
  ) async {
    // الحصول على حسابات الإهلاك من دليل الحسابات أو إعدادات النظام
    // هنا نفترض وجود حسابات افتراضية
    final expenseAccountId = await _getDepreciationExpenseAccount(categoryId);
    final accumulatedDepreciationAccountId = await _getAccumulatedDepreciationAccount(assetId);

    // إنشاء القيد
    final entryId = await db.into(db.glEntries).insert(
      GLEntriesCompanion.insert(
        date: date,
        description: Value('قيد إهلاك شهرى للأصل #$assetId'),
        reference: Value('DEP-${date.toString().substring(0, 7)}-$assetId'),
        isPosted: Value(false),
      ),
    );

    // أسطر القيد
    await db.into(db.glLines).insertAll([
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: expenseAccountId,
        debit: amount,
        credit: 0,
        description: Value('مصروف إهلاك'),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: accumulatedDepreciationAccountId,
        debit: 0,
        credit: amount,
        description: Value('مجمع إهلاك'),
      ),
    ]);

    // ترحيل القيد
    await db.accountingDao.postJournalEntry(entryId);

    return entryId;
  }

  Future<int> _getDepreciationExpenseAccount(int categoryId) async {
    // البحث عن حساب مصروف الإهلاك في شجرة الحسابات
    // هذا تبسيط - في الواقع يتم جلبه من إعدادات النظام
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('6%')) // مصروفات
        .get();
    
    if (accounts.isNotEmpty) {
      return accounts.first.id;
    }
    
    throw Exception('لم يتم العثور على حساب مصروف الإهلاك');
  }

  Future<int> _getAccumulatedDepreciationAccount(int assetId) async {
    // البحث عن حساب مجمع الإهلاك
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('16%')) // أصول ثابتة - مجمع إهلاك
        .get();
    
    if (accounts.isNotEmpty) {
      return accounts.first.id;
    }
    
    throw Exception('لم يتم العثور على حساب مجمع الإهلاك');
  }

  /// بيع أو خروج أصل
  Future<Map<String, dynamic>> disposeAsset({
    required int assetId,
    required DateTime disposalDate,
    required String disposalType,
    double? salePrice,
    String? notes,
  }) async {
    final asset = await db.select(db.fixedAssets)
        .where((t) => t.id.equals(assetId))
        .getSingle();

    final bookValue = asset.purchaseCost - asset.accumulatedDepreciation;
    double gainOrLoss = 0;

    if (disposalType == 'sold' && salePrice != null) {
      gainOrLoss = salePrice - bookValue;
    } else if (disposalType == 'scrapped') {
      gainOrLoss = -bookValue; // خسارة كاملة
    }

    // تسجيل عملية الخروج
    final disposalId = await db.into(db.assetDisposals).insert(
      AssetDisposalsCompanion.insert(
        assetId: assetId,
        disposalDate: disposalDate,
        disposalType: disposalType,
        salePrice: Value(salePrice),
        gainOrLoss: Value(gainOrLoss),
        notes: Value(notes),
      ),
    );

    // إنشاء قيد محاسبي للخروج
    final journalEntryId = await _createDisposalJournalEntry(
      assetId,
      bookValue,
      salePrice ?? 0,
      gainOrLoss,
      disposalDate,
      disposalType,
    );

    // تحديث سجل الخروج برقم القيد
    await db.update(db.assetDisposals).write(
      db.assetDisposals.id.equals(disposalId),
      AssetDisposalsCompanion.insert(journalEntryId: journalEntryId),
    );

    // تحديث حالة الأصل
    await db.update(db.fixedAssets).replace(
      asset.copyWith(status: disposalType == 'sold' ? 'sold' : 'scrapped'),
    );

    return {
      'disposalId': disposalId,
      'journalEntryId': journalEntryId,
      'gainOrLoss': gainOrLoss,
      'bookValue': bookValue,
    };
  }

  Future<int> _createDisposalJournalEntry(
    int assetId,
    double bookValue,
    double salePrice,
    double gainOrLoss,
    DateTime date,
    String disposalType,
  ) async {
    final asset = await db.select(db.fixedAssets)
        .where((t) => t.id.equals(assetId))
        .getSingle();

    final entryId = await db.into(db.glEntries).insert(
      GLEntriesCompanion.insert(
        date: date,
        description: Value('قيد خروج أصل #$assetId - $disposalType'),
        reference: Value('DISP-$disposalType-$assetId'),
        isPosted: Value(false),
      ),
    );

    final lines = <GLLinesCompanion>[];

    // قيد إهلاك المجمع
    lines.add(GLLinesCompanion.insert(
      entryId: entryId,
      accountId: await _getAccumulatedDepreciationAccount(assetId),
      debit: asset.accumulatedDepreciation.toDouble(),
      credit: 0,
      description: Value('إلغاء مجمع الإهلاك'),
    ));

    if (disposalType == 'sold' && salePrice > 0) {
      // قيد القبض
      lines.add(GLLinesCompanion.insert(
        entryId: entryId,
        accountId: await _getCashOrBankAccount(),
        debit: salePrice,
        credit: 0,
        description: Value('تحصيل بيع الأصل'),
      ));
    }

    // قيد إلغاء قيمة الأصل
    lines.add(GLLinesCompanion.insert(
      entryId: entryId,
      accountId: await _getFixedAssetAccount(assetId),
      debit: 0,
      credit: asset.purchaseCost,
      description: Value('إلغاء قيمة الأصل'),
    ));

    // قيد الربح أو الخسارة
    if (gainOrLoss != 0) {
      final gainLossAccountId = gainOrLoss > 0 
          ? await _getGainOnDisposalAccount()
          : await _getLossOnDisposalAccount();
      
      lines.add(GLLinesCompanion.insert(
        entryId: entryId,
        accountId: gainLossAccountId,
        debit: gainOrLoss > 0 ? 0 : -gainOrLoss,
        credit: gainOrLoss > 0 ? gainOrLoss : 0,
        description: Value(gainOrLoss > 0 ? 'ربح بيع أصل' : 'خسارة بيع أصل'),
      ));
    }

    await db.into(db.glLines).insertAll(lines);
    await db.accountingDao.postJournalEntry(entryId);

    return entryId;
  }

  Future<int> _getCashOrBankAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('10%')) // نقدية وبنوك
        .get();
    return accounts.first.id;
  }

  Future<int> _getFixedAssetAccount(int assetId) async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('15%')) // أصول ثابتة
        .get();
    return accounts.first.id;
  }

  Future<int> _getGainOnDisposalAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('4%')) // إيرادات أخرى
        .get();
    return accounts.first.id;
  }

  Future<int> _getLossOnDisposalAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('6%')) // مصروفات أخرى
        .get();
    return accounts.first.id;
  }
}
