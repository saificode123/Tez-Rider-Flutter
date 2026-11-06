# TezRider

Existing Flutter/GetX Android and iOS app backed by Supabase. Start with
[Windows partner setup](docs/PARTNER-WINDOWS-SETUP.md) and the
[portability and FR audit](docs/FINAL-DELIVERY/FR-GITHUB-PORTABILITY-AUDIT.md).

Use `main` for all consolidated feature branches and current delivery fixes.
The owner approved consolidation on 2026-11-06. Use approved TEST configuration. A plain
`flutter run` does not load `.env`. Never commit local credentials or use the
protected production project for testing.

## Update an existing main checkout

```powershell
git pull origin main
flutter pub get
```

Keep your private `.env` and matching TEST Firebase configuration locally. If
currently on another branch, preserve local changes and switch to `main` first.
See the acceptance report for outstanding functional/device gates; consolidation
does not turn incomplete checks into passes.

## Clone and run

Install the Flutter SDK specified in the setup guide, then:

```powershell
git clone --branch main https://github.com/saificode123/Tez-Rider-Flutter.git
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
