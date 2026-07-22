# Security policy

## Reporting a vulnerability

Do not disclose suspected vulnerabilities in a public issue. Use GitHub's
private vulnerability-reporting flow for this repository when it is available.
If it is unavailable, contact the repository owner through GitHub and request a
private reporting channel without including exploit details in a public post.

Include the affected release or commit, a minimal reproduction, impact, and any
resource-limit settings needed to reproduce the issue. Please allow maintainers
time to investigate and prepare a fix before public disclosure.

## Supported versions

Security fixes are made for the latest published 0.x release and, when relevant,
the current `main` branch. Older releases may receive guidance, but are not
normally patched.

## Scope

This library processes untrusted RDF and JSON-LD input. Resource exhaustion,
parser differentials, unsafe output handling, and violations of documented
ownership or no-network boundaries are in scope. Applications remain responsible
for their own transport, TLS, redirects, authentication, cache, allow-list, and
deployment policy when supplying JSON-LD document loaders.
