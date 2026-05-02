# دليل النشر والإعداد (Deployment Guide)

## 📋 نظرة عامة
هذا الدليل يوضح خطوات إعداد وبناء ونشر تطبيق **Supermarket ERP** بعد تطبيق تحسينات الأداء.

---

## 🔧 المتطلبات الأساسية

### 1. بيئة التطوير
- **Flutter SDK**: الإصدار 3.4.0 أو أحدث
- **Dart SDK**: الإصدار 3.4.0 أو أحدث
- **Android Studio** / **VS Code** مع إضافات Flutter
- **Git** لإدارة النسخ

### 2. الاعتماديات (Dependencies)
قبل البناء، تأكد من تثبيت جميع الحزم:
```bash
flutter pub get
```

### 3. أدوات البناء
- **Android**: Android SDK (API Level 21+)
- **iOS**: Xcode 14+ (لأنظمة Mac فقط)
- **Web**: متصفح Chrome للتحقق

---

## 🚀 خطوات البناء (Build Steps)

### 1. التحقق من الكود
```bash
# تحليل الكود للكشف عن المشاكل
flutter analyze

# تشغيل الاختبارات
flutter test
```

### 2. بناء نسخة Android
```bash
# بناء APK للتجربة
flutter build apk --release

# بناء App Bundle للنشر على Google Play
flutter build appbundle --release
```
- **مخرج الملف**: `build/app/outputs/flutter-apk/app-release.apk`
- **مخرج الملف**: `build/app/outputs/bundle/release/app-release.aab`

### 3. بناء نسخة Web
```bash
# تمكين دعم الويب (إذا لم يكن مفعلًا)
flutter config --enable-web

# بناء نسخة الويب
flutter build web --release
```
- **مخرج الملفات**: مجلد `build/web/`

### 4. بناء نسخة Windows (اختياري)
```bash
flutter config --enable-windows-desktop
flutter build windows --release
```

---

## ⚙️ إعدادات ما قبل النشر

### 1. تحديث معلومات التطبيق
في ملف `pubspec.yaml`:
```yaml
version: 2.0.0+4  # زد رقم الإصدار
```

### 2. إعداد أيقونة التطبيق
```bash
# تثبيت أداة flutter_launcher_icons
flutter pub add dev:flutter_launcher_icons

# تشغيل الأداة (بعد إعداد配置文件)
flutter pub run flutter_launcher_icons
```

### 3. إعدادات الأمان
- تأكد من تعطيل وضع التصحيح (Debug Mode) في النسخة النهائية
- راجع صلاحيات الوصول في `AndroidManifest.xml` و `Info.plist`
- تحقق من تشفير البيانات الحساسة

---

## 📦 النشر

### 1. Google Play Store
1. قم بتحميل ملف `.aab` إلى Google Play Console
2. املأ معلومات التطبيق والصور
3. أرسل للمراجعة

### 2. Apple App Store
1. افتح ملف `.xcworkspace` في Xcode
2. عدّل إعدادات التوقيع (Signing & Capabilities)
3. ارشيف التطبيق: `Product > Archive`
4. ارفع إلى App Store Connect عبر Xcode أو Transporter

### 3. الويب
1. ارفع محتويات مجلد `build/web/` إلى أي استضافة تدعم:
   - Firebase Hosting
   - Netlify
   - Vercel
   - خادم Nginx/Apache تقليدي

مثال لـ Firebase Hosting:
```bash
npm install -g firebase-tools
firebase login
firebase init hosting
flutter build web
firebase deploy
```

---

## 🔍 التحقق بعد النشر

### قائمة التحقق (Checklist):
- [ ] يعمل التطبيق بدون أخطاء في السجلات (Logs)
- [ ] قاعدة البيانات تُنشأ بشكل صحيح
- [ ] نظام التخزين المؤقت (Cache) يعمل بفعالية
- [ ] الفهارس (Indexes) محملة وتُستخدم في الاستعلامات
- [ ] واجهة المستخدم متجاوبة وسلسة
- [ ] الطباعة تعمل بشكل صحيح (الفواتير)
- [ ] المصادقة وتسجيل الدخول آمن

---

## 🛠️ الصيانة الدورية

### 1. تحديث الاعتماديات
```bash
flutter pub upgrade
```

### 2. مراقبة الأداء
- استخدم أدوات مثل **Firebase Performance Monitoring**
- راقب تقارير الأعطال (Crashlytics)

### 3. النسخ الاحتياطي
- شجع المستخدمين على تفعيل النسخ الاحتياطي السحابي
- وفر آلية لتصدير البيانات محلياً

---

## 🆘 حل المشاكل الشائعة

### المشكلة: فشل البناء بسبب إصدار SDK
**الحل**: تأكد من تطابق إصدار Flutter في `pubspec.yaml` مع المثبت محلياً.

### المشكلة: بطء الاستعلامات بعد النشر
**الحل**: تحقق من إنشاء الفهارس (Indexes) عند أول تشغيل للتطبيق.

### المشكلة: امتلاء الذاكرة المؤقتة
**الحل**: راجع إعدادات `CacheService` وتأكد من فترات الانتهاء (Expiration).

---

## 📞 الدعم الفني
للمزيد من المساعدة، راجع ملفات التوثيق في مجلد `docs/` أو تواصل مع فريق التطوير.

**آخر تحديث**: أبريل 2025
**الإصدار**: 2.0.0
