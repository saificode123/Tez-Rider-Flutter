# TezRider

Existing Flutter/GetX Android and iOS app backed by Supabase. Start with
[Windows partner setup](docs/PARTNER-WINDOWS-SETUP.md) and the
[portability and FR audit](docs/FINAL-DELIVERY/FR-GITHUB-PORTABILITY-AUDIT.md).

Use the reviewed `main` branch and approved TEST configuration. A plain
`flutter run` does not load `.env`. Never commit local credentials or use the
protected production project for testing.

## Clone and run

Install the Flutter SDK specified in the setup guide, then:

```powershell
git clone https://github.com/saificode123/Tez-Rider-Flutter.git
cd Tez-Rider-Flutter
Copy-Item .env.example .env
# Fill .env with the approved public TEST configuration supplied privately.
flutter pub get
flutter run -d chrome --dart-define-from-file=.env
```

In VS Code with the Flutter extension, select **TezRider Chrome (.env)** and
press F5. The tracked launch configuration passes `.env` automatically.
For Android, follow the guide to add the TEST Firebase client file and select
**TezRider Android TEST (.env)** with an Android device selected. Server-side
secrets stay on the existing Supabase backend. Do not commit local `.env` files.
