# Security Policy

Rescripto promises that your text stays on your phone unless you choose
otherwise. If you find something that breaks that promise, or any other
security problem, please tell us privately.

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
- Issues that require a rooted or compromised device, or physical access to
  an unlocked phone

## Response

We'll reply as soon as we can and keep you updated while we look into it.
Please give us reasonable time to ship a fix before sharing details
publicly.
