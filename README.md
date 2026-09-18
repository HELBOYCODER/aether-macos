# Aether for macOS (menu bar app)

نسخه فعلی: **1.0.1**

[دانلود آخرین نسخه برای Apple Silicon (M1/M2/M3/M4)](https://github.com/HELBOYCODER/aether-macos/releases/download/v1.0.1/Aether-arm64.dmg)

[دانلود آخرین نسخه برای Intel](https://github.com/HELBOYCODER/aether-macos/releases/download/v1.0.1/Aether-x86_64.dmg)

یک رپر بومی SwiftUI برای macOS که دو حالت اتصال دارد:

- Aether CLI با حالت‌های MASQUE / WireGuard / WARP-in-WARP
- SSH tunnel با OpenSSH Dynamic Forwarding

## ✨ امکانات

- آیتم وضعیت در منوبار با اتصال/قطع و وضعیت زنده
- انتخاب حالت اتصال بین Aether و SSH
- برای SSH: هاست، کاربر، پورت و فایل کلید خصوصی از داخل GUI
- ساخت SOCKS5 فقط روی `127.0.0.1`
- اختیاری: فعال‌کردن System SOCKS Proxy روی سرویس شبکه فعال
- پنجره لاگ زنده + پنل تنظیمات
- اجرای خودکار هنگام ورود به سیستم
- هیچ رمز عبور SSH در اپ ذخیره یا جمع‌آوری نمی‌شود؛ حالت SSH از key/ssh-agent استفاده می‌کند و `BatchMode=yes` دارد

## 🔐 SSH mode

حالت SSH یک VPN لایه‌۳ کامل نیست. این حالت از `ssh -N -D 127.0.0.1:<port>` استفاده می‌کند و یک SOCKS5 tunnel می‌سازد. با روشن‌کردن گزینه System Proxy، برنامه از `networksetup` برای اشاره‌دادن proxy سیستم به همان loopback استفاده می‌کند.

برای اتصال:

1. در منوبار، **Connection → SSH tunnel** را انتخاب کنید.
2. در Settings، Host و User را وارد کنید.
3. در صورت نیاز فایل private key را انتخاب کنید، یا از ssh-agent استفاده کنید.
4. Connect را بزنید.
5. در صورت نیاز **Set system proxy** را فعال کنید.

نکته: اولین اتصال به یک host جدید از سیاست استاندارد OpenSSH برای `known_hosts` استفاده می‌کند. اگر کلید میزبان تغییر کرده باشد، OpenSSH طبق تنظیمات محلی خودش اتصال را متوقف می‌کند.

## 🛠 بیلد و انتشار

GitHub Actions برای هر دو معماری macOS یک DMG جدا می‌سازد:

- Apple Silicon / arm64
- Intel / x86_64

باینری Aether از release رسمی نسخه v1.6.0 با SHA-256 بررسی می‌شود. حالت SSH به OpenSSH موجود در خود macOS متکی است.

با افزایش `CFBundleShortVersionString` در `AetherApp/Resources/Info.plist`، workflow به‌صورت خودکار نسخه جدید را build می‌کند و یک GitHub Release با همان شماره نسخه می‌سازد.

## 📦 نصب

برای نصب نسخه جدید، DMG متناسب با معماری Mac را از بخش Releases دانلود کنید، بازش کنید و `AetherApp.app` را داخل Applications بکشید.

در buildهای ad-hoc ممکن است macOS در اولین اجرا هشدار امنیتی بدهد. برای signing و notarization واقعی می‌توانید secretهای Apple را در repository اضافه کنید.

## 📄 لایسنس

رپر اپلیکیشن: MIT — باینری `aether`: AGPL-3.0
