# Kitaab Dost maintenance guide

Production: https://richbrokie.github.io/kitaab-dost/
Repository: git@github.com:RichBrokie/kitaab-dost.git
Database: uqotflogqjlkhozhrpdd.supabase.co

## Rules

- Preserve zero-build architecture. Frontend changes belong in index.html. Do not introduce a framework migration, package.json or bundler without an explicit request.
- The last script in index.html is readable application source. Preceding scripts are pinned upstream React 18.3.1, React DOM 18.3.1 and Supabase JS 2.117.3. Preserve licenses. Do not edit library code to fix application issues.
- Script changes require updating SHA-256 hashes in the CSP meta tag. Normalize CRLF to LF when hashing because HTML parsers normalize line endings. Do not replace hashes with unsafe-inline or unsafe-eval. Do not add inline event attributes.
- Data calls go through kd_api. Never reintroduce direct table access, client-only authorization, unconfirmed local identity or private localStorage caches. Ordinary SDK Auth token storage is the only persistent session state.
- Auth user IDs establish ownership. Names/metadata never authorize access. Only kd_admins establishes administrator authority; only an administrator approves organizations.
- Never add status to legacy pledges or relabel legacy rows as authenticated contributions. Separate kd_shipments track each dispatch and its cumulative receipt. Totals derive from the ledger.
- Use transactions, consistent request-then-pledge locks, retry IDs and version checks. Check every API error before success. Never insert receipts as pledges.
- production-schema.sql is the canonical transactional migration. It preserves legacy rows but revokes public access. Do not run old seeds or recreate unconditional policies.
- Keep tests fictional and isolated. Never use shared production credentials, manufacture live deliveries or print real private contacts into logs.

## Database

kd_profiles: account role and organization contacts; reviewed verification.
kd_admins: administrator user IDs, separate from school/donor profiles.
kd_requests: owned curriculum needs and private delivery address.
kd_pledges: owned commitments, cancellation and edit version.
kd_shipments: parcels, contact snapshots, quantities and school receipt/issue.
kd_events: recipient-scoped on-site updates.
kd_issues: reports and administrator responses.

All tables have RLS and no direct grants to anon/authenticated/PUBLIC. kd_api is SECURITY DEFINER with fixed empty search_path, qualified objects and explicit authorization. kd_public_request is a private projection helper without client execute permission. Review each new action for authorization, exposed fields, role state, null inputs, locking and retries.

Public RPC actions: health, catalog (12 per page), detail, stats.
Authenticated actions: me, profile, workspace (12 per page), issue, request_save/cancel, pledge/edit/cancel, dispatch, receive.
Administrator actions: admin_queue/review/resolve/transfer.

## Verification and deployment

Test anonymous denial, private projection, isolation with duplicate organization names, approval enforcement, stale/banned sessions, retries, quantity limits, partial receipts and administrator transfer. Exercise browser school/donor/admin fixtures, failed saves, keyboard dialogs and 360px viewport. Verify actual embedded hashes after edits.

Apply the migration before publishing its frontend. GitHub Pages deploys main; stage only reviewed application, SQL and documentation changes. Never commit service keys, tokens or personal bootstrap scripts. Rollbacks must keep the secure API: never restore unrestricted grants for an obsolete frontend.

Read README.md for operational limits, email setup and legacy handling; MANUAL.md for user workflows. Do not describe untested backups, SMTP, integrations, government verification or response headers as implemented.
