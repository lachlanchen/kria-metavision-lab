<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner — apps and four buddies](https://lazying.art/media/brand/lazyingart-intro.gif)](https://lazying.art)

# Kria Metavision Lab

### مساحة عمل بواجهة رسومية لاستخدام كاميرات Prophesee الحدثية على AMD Kria KV260

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## ما هذا المشروع

**Kria Metavision Lab** هو مساحة عمل عملية لتحويل عدة Prophesee AMD Kria KV260 إلى محطة تجارب للرؤية الحدثية. يجمع هذا المستودع ملاحظات PetaLinux، ومراجع التعريفات، وسكربتات سطح المكتب، وأدوات التشخيص، وتطبيق عرض مخصص للكاميرا.

الهدف هو تشغيل الكاميرا، فتح عنصر سطح المكتب، مشاهدة الأحداث مباشرة، تسجيل البيانات بأسماء ملفات واضحة، وإغلاق العارض بدون ترك عمليات عالقة.

## الواجهة المخصصة

| الميزة | الوصف |
| --- | --- |
| معاينة مباشرة | تفتح تدفق V4L2 وتعرض نشاط الأحداث على شاشة HDMI |
| إغلاق نظيف | تحرر جهاز الكاميرا ليعمل التشغيل التالي بشكل طبيعي |
| تسجيل | تحفظ بايتات الأحداث الخام للتحليل |
| بيانات وصفية | تكتب ملف JSON مرافق لكل تسجيل |
| مشغل سطح مكتب | تضيف عنصر قائمة بسيط على Matchbox/X11 |
| استعادة | تنظف حالة العارض أو الكاميرا عند التعطل |

## محتويات المستودع

| المسار | الغرض |
| --- | --- |
| `scripts/` | العارض، المشغلات، فحص الكاميرا، سطح المكتب، RDP، والاستعادة |
| `references/` | ملاحظات البحث، روابط Prophesee، وتوثيق الإعداد |
| `fpga-projects/` | لقطة مشروع FPGA الخاص ب Prophesee على KV260 |
| `petalinux-projects/` | لقطة مشروع PetaLinux ومراجع بناء الصورة |
| `linux-sensor-drivers/` | تعريفات IMX636 و GenX320 |
| `zynq-video-drivers/` | تعريفات مسار الفيديو على Zynq |
| `event-vitisai-app/` | لقطة مثال Vitis AI الحدثي |

## بدء سريع

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## معلومات GitHub

اسم المستودع المقترح هو `lachlanchen/kria-metavision-lab`، والصفحة الرئيسية هي `https://flow.lazying.art`. قبل النشر العام، أزل كلمات المرور المحلية، وعناوين IP الخاصة، وتنزيلات حساب Prophesee، وأي إعداد خاص بالجهاز.

<!-- support:start -->
[![GitHub Sponsors](https://img.shields.io/badge/GitHub-Sponsors-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/lachlanchen)
[![LazyingArt Support](https://img.shields.io/badge/LazyingArt-Support-0EA5E9?style=for-the-badge)](https://chat.lazying.art/donate)
[![PayPal Support](https://img.shields.io/badge/PayPal-Support-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen)
[![Stripe Support](https://img.shields.io/badge/Stripe-Support-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400)
<!-- support:end -->
