# Security Policy

Rescripto is built around a simple promise: your text stays on your device
unless you choose otherwise. We take anything that could break that promise,
or any other security issue, seriously.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security reports.**

Instead, use GitHub's private vulnerability reporting for this repository:

1. Go to the [Security tab](https://github.com/Gr33nOps/Rescripto/security)
2. Click **Report a vulnerability**
3. Describe the issue, how to reproduce it, and its impact

If that's not available to you for some reason, open a normal issue asking
for a private contact channel (without any vulnerability details) and
we'll follow up.

## What's in scope

- Data that's supposed to stay on-device (in Local mode) leaving it
- A Privacy toggle or the network kill switch not actually blocking what it
  claims to
- API keys or other credentials stored, logged, or transmitted insecurely
- The in-app network log failing to record a request it claims to audit
- Anything that lets a malicious model file, backup file, or WebDAV
  response execute code or corrupt app state beyond its own data
- Standard app-security issues: injection, path traversal, insecure
  deserialization, etc.

## What's out of scope

- Vulnerabilities in a third-party cloud provider you've configured
  yourself (OpenAI, Anthropic, Groq, etc.). Report those to the provider
- Issues that require a rooted/compromised device or physical access with
  the device unlocked
- The known, disclosed licensing/commercial-use restriction on
  `third_party/flutter_llama` (see the [README](../README.md#license)).
  That's a licensing matter, not a vulnerability

## Response

We will acknowledge your report as soon as we can and keep you updated while
we investigate it. Please give us a reasonable window to ship a fix before
sharing details publicly.
