# Verification

The production site needs no build or package installation. These are optional maintainer tests; never point them at production.

Run `node verify-frontend.cjs` to verify embedded script syntax and CSP hashes. Recompute script hashes after frontend edits, normalizing CRLF to LF.

`security-tests.cjs` uses an isolated, in-memory PostgreSQL engine (PGlite), fictional Auth users and mocked auth.uid(). Install @electric-sql/pglite into an external tooling directory, not this repository; set KD_PGLITE_MODULE to its absolute installed package directory, then run `node security-tests.cjs`.

The 28 checks cover migration repeatability and preservation, anonymous denial, private helper denial, profile/role isolation, unconfirmed and retired accounts, approval enforcement, duplicate names, catalog privacy, idempotent creates, overpledge rejection, ownership, parcel limits, partial receipts, stale edits and administrator transfer. PGlite serializes work on one connection; these tests do not constitute a simultaneous multi-connection load test.

Browser verification on 13 October 2026 used the actual UI and the same migration in an isolated PGlite server, with fictional Auth fixtures. Tested catalog pagination/search, donor login, a 30-book pledge, a 12-book parcel and matching packing slip, a school receipt of 10 books with an issue, accurate impact totals, sign-out clearing private data, administrator controls, and a 360×640 request form. A simulated failed save retained inputs and showed an error; retry created one request. No test pledges or deliveries were submitted to production.

Actual SMTP delivery, recovery/confirmation email arrival, physical printing, courier delivery, multi-device refresh, infrastructure rate limiting and backup restoration require separate operator acceptance. The on-site administrator queue has a 100-record display limit.
