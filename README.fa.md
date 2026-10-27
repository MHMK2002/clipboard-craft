<div dir="rtl">

<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="آیکن Clipboard Craft">
</p>

<h1 align="center">Clipboard Craft</h1>

<p align="center">
  <b>Your smarter clipboard companion</b><br>
  یک مدیر کلیپ‌بورد کامل و بومی برای macOS؛ متن، لینک، کد، رنگ، عکس و <b>خودِ فایل‌ها</b>، همه با یک میانبر در دسترس.
</p>

<p align="center">
  <a href="https://github.com/MHMK2002/clipboard-craft/raw/main/releases/ClipboardCraft-1.0.0.dmg"><b>⬇︎ دانلود نسخه‌ی ۱.۰.۰ (DMG)</b></a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/screenshots/quick-panel.jpg" alt="پنل سریع" width="820">
</p>

## نصب

۱. فایل **[ClipboardCraft-1.0.0.dmg](https://github.com/MHMK2002/clipboard-craft/raw/main/releases/ClipboardCraft-1.0.0.dmg)** (یا [نسخه‌ی ZIP](https://github.com/MHMK2002/clipboard-craft/raw/main/releases/ClipboardCraft-1.0.0.zip)) را دانلود کنید و **Clipboard Craft** را داخل پوشه‌ی **Applications** بکشید.

۲. اپ توسط اپل notarize نشده، پس macOS بار اول جلوی اجرایش را می‌گیرد. به **System Settings › Privacy & Security** بروید و روی **Open Anyway** بزنید. یا این دستور را در ترمینال اجرا کنید:

<div dir="ltr">

```sh
xattr -dr com.apple.quarantine "/Applications/Clipboard Craft.app"
```

</div>

۳. برای اینکه Enter محتوا را مستقیم در برنامه‌ی فعال Paste کند، در **System Settings › Privacy & Security › Accessibility** به Clipboard Craft دسترسی بدهید.

نیازمندی: macOS 26 یا جدیدتر. فایل اجرایی Universal است و روی مک‌های اپل سیلیکون و اینتل اجرا می‌شود.

## تصاویر

| پنل سریع | پیش‌نمایش عکس |
|---|---|
| ![پنل سریع](docs/screenshots/quick-panel.jpg) | ![پیش‌نمایش عکس](docs/screenshots/quick-panel-image.jpg) |
| **پنجره‌ی اصلی** | **نمای شبکه‌ای** |
| ![پنجره‌ی اصلی](docs/screenshots/library.jpg) | ![نمای شبکه‌ای](docs/screenshots/library-grid.jpg) |
| **حالت تاریک** | **فایل‌ها در پنل سریع** |
| ![حالت تاریک](docs/screenshots/library-dark.jpg) | ![فایل‌ها](docs/screenshots/quick-panel-dark.jpg) |

## قابلیت‌ها

**تاریخچه‌ی هوشمند**
- ثبت خودکار هر چیزی که کپی می‌شود، همراه با برنامه‌ی مبدأ
- تشخیص نوع محتوا: متن، متن فرمت‌دار، لینک، کد (با تشخیص زبان)، رنگ (HEX/RGB/HSL)، عکس، فایل و داده‌های ناشناخته
- مدیریت موارد تکراری و گروه‌بندی زمانی
- جست‌وجوی فوری که فارسی را درست می‌فهمد: «ی» و «ي»، «ک» و «ك»، نیم‌فاصله و اعداد فارسی فرقی نمی‌کنند. فیلترهایی مثل `type:image`، `is:pinned`، `app:safari` و `in:work` هم پشتیبانی می‌شوند.
- Pin، علاقه‌مندی‌ها و Collection
- پاک‌سازی خودکار بر اساس زمان، تعداد یا حجم؛ آیتم‌های Pin‌شده، علاقه‌مندی‌ها و آیتم‌های داخل Collection هیچ‌وقت خودکار حذف نمی‌شوند.

**فایل و عکس واقعی**
- از فایل‌های کپی‌شده یک نسخه‌ی مستقل ذخیره می‌شود. اگر فایل اصلی جابه‌جا یا حذف شود، همان نسخه Paste می‌شود.
- Paste مجدد یک یا چند فایل در Finder و هر برنامه‌ی دیگری
- Thumbnail و پیش‌نمایش با QuickLook، و نمایش نام، نوع، حجم، مسیر و وضعیت فایل اصلی

**پنل سریع**
- پنل شیشه‌ای (Liquid Glass) که برنامه‌ای که در آن کار می‌کنید را از حالت فعال خارج نمی‌کند
- میانبر پیش‌فرض <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd>؛ از Settings › Shortcuts می‌شود **چند میانبر مختلف** برایش تعریف کرد.
- جست‌وجو، فیلتر نوع با <kbd>⇥</kbd>، پیش‌نمایش زنده، و Paste با <kbd>↩</kbd>

**پنجره‌ی اصلی و تنظیمات**
- نمای لیستی و شبکه‌ای، انتخاب چندتایی، عملیات گروهی، ویرایش متن، Export و Drag & Drop
- Undo برای حذف، تم روشن/تاریک، اجرا هنگام Login، و نمایش فضای اشغال‌شده
- حریم خصوصی: رمزهای عبور ثبت نمی‌شوند، لیست برنامه‌های نادیده‌گرفته‌شده و امکان توقف موقت ثبت

## ساخت از سورس

<div dir="ltr">

```sh
git clone git@github.com:MHMK2002/clipboard-craft.git
cd clipboard-craft
./build.sh --install --run
./test.sh
Scripts/package.sh   # DMG و ZIP در پوشه‌ی releases
```

</div>

برای ساخت فقط Command Line Tools لازم است. اسکریپت ساخت اپ را با یک امضای محلی ثابت (در پوشه‌ی `.signing/`) امضا می‌کند، به همین دلیل دسترسی Accessibility بعد از build‌های بعدی هم باقی می‌ماند.

</div>
