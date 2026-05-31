<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### مساحة عمل بواجهة رسومية لاستخدام كاميرات Prophesee الحدثية على AMD Kria KV260

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
