# Security

Report vulnerabilities through GitHub Private Vulnerability Reporting. Do not
post server URLs, tokens, passwords or library metadata in public issues.

The public source tree contains no credentials. Values passed through
`--dart-define` are embedded in the application and must be treated as
recoverable by anyone who receives the binary. Rotate any token included in a
distributed APK/AAB.

Never commit `.env`, signing keystores, `key.properties`, APK/AAB files or
Android `local.properties`.
