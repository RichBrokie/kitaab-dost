# Kitaab Dost Network

A book donation network for Pakistani schools, NGOs and individual donors.

[Open the website](https://richbrokie.github.io/kitaab-dost/) · [User manual](MANUAL.md) · [Maintenance guide](AGENTS.md)

Schools describe exact curriculum needs. Approved donors pledge copies, record individual parcels and see school-confirmed receipts. Requested, pledged, dispatched and received quantities are separate; the site does not infer student reach from promises.

## Security model

- Supabase Auth identifies each account by its immutable user ID. Organization names and editable Auth metadata never authorize access.
- Public catalog responses exclude phone numbers, contact names and delivery addresses. Contacts are shared with pledge participants, and organization contacts with the administrator for review.
- All client table access is revoked. RLS is enabled with no permissive policies. The kd_api database function is the only client data API, with explicit checks for every action.
- Profile approval is a recorded administrator decision. Registration or an EMIS number does not establish verification.
- Request locks prevent overpledging. Quantities and transitions are validated in a database transaction. Request, pledge and parcel creation support retry identifiers; edits use versions.
- Existing shared demo accounts are retired. There are no production demo passwords or automatic sample records.

## Deployment

This is a zero-build static website. index.html contains the UI, CSS and pinned copies of React 18.3.1, React DOM 18.3.1 and Supabase JS 2.117.3. No runtime Babel, Tailwind compiler, floating CDN URL or package installation is needed to serve it. The CSP authorizes each embedded script by its SHA-256 content hash.

1. Review and run production-schema.sql as the database owner. It is transactional and repeatable: it creates the kd_* model, removes legacy permissive policies, revokes direct access and preserves legacy rows.
2. Appoint the initial administrator by an exact, confirmed Auth user ID in kd_admins. Do this privately in the SQL Editor; never publish personal bootstrap scripts or service keys. The app has **Admin → Transfer admin role** for subsequent changes.
3. In Supabase Authentication URL Configuration, set the Site URL and allowed redirect to the exact production URL above, including its trailing slash. Require email confirmation and configure reliable email delivery. Test confirmation and recovery with an account you control.
4. Deploy the matching index.html to GitHub Pages main after the migration succeeds. The old frontend is incompatible with the restricted database.
5. Verify kd_api('health') reports version 2, public table reads fail, and public catalog responses contain no contacts.

For local preview, serve the repository with any static server, for example `py -m http.server 3000`. Avoid test donations against production. Use a separate Supabase project or isolated PostgreSQL fixtures for workflow tests.

## Existing records and operational limits

The legacy book_requests and pledges tables remain intact but private. They lack trustworthy account ownership and contain unreliable aggregates/statuses, so they are **not automatically attributed or included in the new catalog or impact totals**. Verify ownership, book requirements and quantities before recreating requests under actual owners. Never match ownership solely by organization name or invent missing parcel/receipt information.

The app provides recent on-site updates and help reports; it does not send automatic pledge emails, book couriers or validate tracking numbers with carriers. Verification is an organizational review, not a government certification. Received quantities are school-reported.

The administrator queue displays up to 100 organizations and 100 unresolved reports. Account-level daily limits cover request creation, pledges and reports; infrastructure-level abuse protection and Auth rate limits need operational monitoring. Configure and test backups, email delivery and a support process before wider recruitment.

GitHub Pages does not let this repository set arbitrary response headers. Meta CSP cannot enforce frame-ancestors; a host with response-header controls is needed for framing protection and other server headers. Do not claim those headers exist based on the meta tag.
