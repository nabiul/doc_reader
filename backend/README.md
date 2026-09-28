# DocReader Office conversion service (optional/unused)

The mobile app now uses its own offline Flutter renderer and does not require
this service. This directory is retained only as an optional conversion utility.

This private API converts Word, Excel, PowerPoint, and RTF documents to PDF with
headless LibreOffice. Uploaded files and generated PDFs live only in an isolated
temporary directory and are deleted after every response.

## Start

```bash
docker compose -f backend/compose.yaml up --build
```

Health check: `http://localhost:8787/health`

Android Emulator uses `http://10.0.2.2:8787` automatically. For iOS Simulator
or a physical device, provide an address reachable from that device:

```bash
flutter run --dart-define=OFFICE_CONVERTER_URL=http://192.168.1.10:8787
```

Use HTTPS and authentication before exposing this service to the internet.
