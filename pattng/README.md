# PattNG for macOS

نسخه macOS از PattNG — کلاینت V2Ray/Xray با تغییرات خاص ایرانی.

## این چیست؟

[PattNG](https://github.com/patterniha/PattNG) نسخه اندروید است. برای دسکتاپ، خود `patterniha`
فورک [v2rayN](https://github.com/patterniha/v2rayN) را نگه می‌دارد که همان تغییرات را دارد.
این ریپازیتوری آن را برای macOS بیلد و به `.dmg` پکیج می‌کند.

## اجزا

| جزء | منبع | تغییر |
|---|---|---|
| GUI | [patterniha/v2rayN](https://github.com/patterniha/v2rayN) (`master`) | پشتیبانی `cipherSuites` در تنظیمات و شیرلینک (پارامتر `cs=`)، فینگرپرینت `unsafe` |
| Core | [patterniha/Xray-core](https://github.com/patterniha/Xray-core) (`main`) | اتصال به کانفیگ‌های غیررمزنگاری‌شده روی آدرس‌های عمومی در VLESS و TROJAN |
| سایر هسته‌ها و geo data | [2dust/v2rayN-core-bin](https://github.com/2dust/v2rayN-core-bin) | sing-box, mihomo, geoip/geosite |

## بیلد

Workflow: `.github/workflows/build-pattng-macos.yml`

```
Actions → Build PattNG macOS (.dmg) → Run workflow
```

خروجی: `PattNG-macos-arm64.dmg` (Apple Silicon) و `PattNG-macos-64.dmg` (Intel) به‌عنوان artifact.

بیلد لوکال روی مک:

```bash
git clone --recursive https://github.com/patterniha/v2rayN.git
cd v2rayN/v2rayN
dotnet publish ./v2rayN.Desktop/v2rayN.Desktop.csproj -c Release -r osx-arm64 -p:SelfContained=true -o ../../out
```

سپس هسته پچ‌شده:

```bash
git clone https://github.com/patterniha/Xray-core.git
cd Xray-core && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o ../out/bin/xray/xray -trimpath -ldflags "-s -w" ./main
```

## نصب

اپ ad-hoc امضا شده است (بدون Apple Developer Certificate). بعد از نصب:

```bash
xattr -dr com.apple.quarantine /Applications/PattNG.app
```

یا راست‌کلیک روی اپ → Open → Open.

## نکته

`cipherSuites` در شیرلینک با پارامتر `cs=` منتقل می‌شود (مثل نسخه اندروید).
فینگرپرینت `unsafe` از لیست fingerprint در تنظیمات TLS انتخاب می‌شود.
