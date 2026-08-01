# CHATDOX production cutover runbook

This runbook separates preparation from mutation. Do not run a gated command without the matching HQ/Tommy signal.

## START: read-only preparation

```bash
git status --short
git rev-parse HEAD
railway status
railway ssh -- printenv RAILWAY_GIT_COMMIT_SHA CHATDOX_CONTENT_SOURCE
railway ssh -- bin/rails chapter_progress:backfill_chatdox_s01
```

The inventory command is dry-run by default. Save its JSON without adding user identifiers. Confirm a current database backup/restore point through the existing admin backup flow and Railway database controls. Do not print `DATABASE_URL`.

Build an inactive artifact from the clean approved HQ commit:

```bash
bin/content-snapshot --inspect --repository <CLEAN_HQ_REPOSITORY> --source <CHATDOX_SOURCE_PATH>
bin/content-snapshot --build <INACTIVE_ARTIFACT> --repository <CLEAN_HQ_REPOSITORY> --source <CHATDOX_SOURCE_PATH>
CHATDOX_CONTENT_SOURCE=seasoned CHATDOX_SNAPSHOT_PATH=<INACTIVE_ARTIFACT> \
CHATDOX_EXPECTED_SOURCE_COMMIT=<APPROVED_FULL_SHA> bin/chatdox-release verify
```

Expected: JSON `state=ready`, matching abbreviated commits, S01 public 20, S02 public 0. Build rejects dirty, detached, shallow and non-full-SHA sources. The inactive artifact must live on storage that survives restart; the current Docker image filesystem itself is ephemeral. Confirm Railway volume mounting before choosing the production target.

Build web assets before starting a production-like server from a source checkout. Docker does this during image build, but a direct `bin/rails server` does not:

```bash
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

## Production-like smoke

Start a separate server with `RAILS_ENV=production`, the inactive artifact and expected SHA. Verify:

```text
/                         200
/pricing                  200
/chatdox                  200
/chatdox/s01              200
/chatdox/s01/01           200
/chatdox/s02              200
/docs                     200
/docs/01                  200
/chatdox/s01/1            404, generic, private no-store
invalid snapshot          503, generic, private no-store
```

Also verify the S01 image content type/cache, S02 private-title absence, login return path, checkout, other products and admin readiness. A failed item blocks cutover.

Run the machine-readable route and static-asset gate against the server:

```bash
bin/chatdox-smoke --base-url http://127.0.0.1:3002
```

It discovers fingerprinted CSS/JS from `/chatdox`, requires every asset to return 200 with `text/css` or JavaScript content type, and fails when no assets are found.

For a local-only admin readiness preview, use the same isolated production-like DB environment as the server:

```bash
CONFIRM_LOCAL=1 PREVIEW_PASSWORD='<12+ character local password>' bin/rails chatdox:readiness_preview:setup
bin/rails chatdox:readiness_preview:cleanup
```

The setup task refuses to run when `RAILWAY_ENVIRONMENT` is present. Sign in with the printed `.invalid` address, then open `/admin/chatdox_readiness`.

## CUTOVER APPROVE gate

Only after the literal `0010 CUTOVER APPROVE` signal:

The production `web` service follows GitHub `main`; a matching push creates a
deployment. For this release, the validated public artifact is committed under
`runtime/chatdox` and copied into `/rails/runtime/chatdox` by the normal Docker
build. The Docker image sets the seasoned mode, artifact path and approved HQ
SHA as one immutable default contract. No runtime install, web volume or Railway
variable edit is required for activation.

The artifact contains S01's 20 published bodies and referenced images, plus S02
public metadata with zero published bodies. Draft/review bodies are excluded by
the snapshot builder. Public source methods also exclude unpublished seasons and
episodes, and direct unpublished episode routes return 404.

1. Confirm approved DEV full SHA, clean tree, packaged manifest SHA and tests.
2. Push the approved application commit to `main` once. Do not also run a manual
   deploy. Wait for the matching Railway deployment SHA and `/up` 200.
3. Run the production smoke and open `/admin/chatdox_readiness`. Require `ready`,
   matching commits, S01 public 20 and S02 upcoming/public 0.
4. On any failure, set the Railway `CHATDOX_CONTENT_SOURCE=legacy` override. That
   variable takes precedence over the image default and triggers the rollback
   deployment. Stop and do not backfill.

Exact operator order:

```bash
git status --short
git rev-parse HEAD
railway status --json

git push origin main
railway deployment list --service web --limit 1 --json
curl --fail --silent --show-error https://leedox.up.railway.app/up
bin/chatdox-smoke --base-url https://leedox.up.railway.app
railway ssh -- bin/chatdox-release readiness
```

The existing runtime install CLI remains available for a future persistent
artifact workflow, but is not a dependency of this image-bundled release.

## Source rollback

Set the Railway `CHATDOX_CONTENT_SOURCE=legacy` override and allow its automatic
deployment. Require `/up`, `/chatdox`, `/docs`, `/docs/01`, checkout and other
products to pass. The packaged artifact remains inert inside the image.

```bash
railway variable set CHATDOX_CONTENT_SOURCE=legacy --service web --environment production
```

To try seasoned mode again in a later approved release, remove the Railway
override so the image default applies. Canonical progress remains readable
through the legacy compatibility layer.

## BACKFILL APPLY gate

Only after the literal `0010 BACKFILL APPLY` signal, a successful cutover smoke and an approved inventory:

```bash
railway ssh -- /bin/bash -lc 'CONFIRM_PRODUCTION=1 APPLY=1 BATCH_SIZE=<APPROVED_SIZE> bin/rails chapter_progress:backfill_chatdox_s01'
railway ssh -- bin/rails chapter_progress:backfill_chatdox_s01
```

The first output must match approved converted/collision counts. The second must report zero convertible rows. Other-product count must remain unchanged. Unknown rows are retained. Do not attempt an automatic reverse conversion: if incident recovery is required, keep user visibility through dual-read and use the approved database restore point with incident-specific approval.

## Legacy traffic observation

For at least 30 days, aggregate `legacy_chatdox_route family=<index|episode|image> status=<code>` application log events by UTC/KST date, family and status. The event contains no query, session, user, email or token. Separate `/up` health traffic; classify obvious bots only from existing platform metadata without adding raw user-agent storage. A redirect requires a later HQ decision; `/docs/images/*` remains a longer-lived compatibility candidate.
