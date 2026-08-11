# Security policy

## Reporting a vulnerability

Report privately through [GitHub's security advisory form](https://github.com/jiezhuzzz/harder/security/advisories/new), or by email to <jiezhu@uchicago.edu> if you would rather not use GitHub. Please do not open a public issue for a vulnerability.

Include what you need to make the problem reproducible: the affected version or commit, the steps, and what an attacker gets out of it. A proof of concept helps but is not required.

You can expect an acknowledgement within a week. If the report is valid, you will get an estimate for a fix and credit in the advisory unless you ask otherwise.

## Supported versions

Only the tip of `main` is supported. Fixes land there, and older tags are not backported.

## Scope

The build and automation surface counts, not just the application code: a workflow that leaks secrets or grants more permission than it needs, a hook or script that executes untrusted input, and problems in how dependencies are pinned are all in scope.

Vulnerabilities in the upstream tools this repository depends on belong to those projects. Report them there, and open an issue here if this repository should pin around the problem in the meantime.
