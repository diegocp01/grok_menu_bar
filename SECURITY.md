# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's **Report a vulnerability** feature rather than a public issue.

Do not include real Grok access tokens, `~/.grok/auth.json`, signing certificates, Apple app-specific passwords, or other credentials in a report. A minimal redacted reproduction is preferred.

## Credential handling

Grok CLI Usage Menu Bar reads the existing Grok CLI session in `~/.grok/auth.json` (or `$GROK_HOME/auth.json`). It may refresh the OIDC access token and write the rotated tokens back to that same file with owner-only permissions.

Tokens are held in process memory while fetching billing data. They are never logged, copied to another file, placed in Keychain, or sent to analytics or any host other than xAI (`cli-chat-proxy.grok.com` and `auth.x.ai`).
