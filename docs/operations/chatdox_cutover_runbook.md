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

## CUTOVER APPROVE gate

Only after the literal `0010 CUTOVER APPROVE` signal:

1. Confirm approved DEV full SHA, clean tree, production deploy commit and backup/restore point.
2. Deploy the approved application release and wait for `/up` 200. Confirm whether GitHub push auto-deploy is enabled in Railway service settings before pushing any later release.
3. Build/transfer the approved artifact to an inactive persistent target.
4. Install it under a single-process lock:

   ```bash
   CONFIRM_PRODUCTION=1 bin/chatdox-release install \
     --artifact <INACTIVE_ARTIFACT> --target <PERSISTENT_TARGET> \
     --expected-commit <APPROVED_FULL_SHA>
   ```

5. Set the release contract together in Railway, then restart/redeploy:

   ```text
   CHATDOX_SNAPSHOT_PATH=<PERSISTENT_TARGET>
   CHATDOX_EXPECTED_SOURCE_COMMIT=<APPROVED_FULL_SHA>
   CHATDOX_CONTENT_SOURCE=seasoned
   ```

   Railway variable changes are not assumed atomic. Install and verify the inactive target first; set path and expected SHA before setting source mode; use one controlled restart as the activation point.
6. Run the production smoke list and open `/admin/chatdox_readiness`. Require `ready` and matching commits.
7. On any failure, stop. Do not backfill.

## Source rollback

Set `CHATDOX_CONTENT_SOURCE=legacy`, restart, require `/up`, `/chatdox`, `/docs`, `/docs/01`, checkout and other products to pass. Confirm the intended value before activation:

```bash
CONFIRM_PRODUCTION=1 CHATDOX_CONTENT_SOURCE=legacy bin/chatdox-release rollback-legacy
```

Keep the failed artifact inactive for diagnosis; do not overwrite the last approved artifact. Canonical progress remains readable through the legacy compatibility layer.

## BACKFILL APPLY gate

Only after the literal `0010 BACKFILL APPLY` signal, a successful cutover smoke and an approved inventory:

```bash
railway ssh -- /bin/bash -lc 'CONFIRM_PRODUCTION=1 APPLY=1 BATCH_SIZE=<APPROVED_SIZE> bin/rails chapter_progress:backfill_chatdox_s01'
railway ssh -- bin/rails chapter_progress:backfill_chatdox_s01
```

The first output must match approved converted/collision counts. The second must report zero convertible rows. Other-product count must remain unchanged. Unknown rows are retained. Do not attempt an automatic reverse conversion: if incident recovery is required, keep user visibility through dual-read and use the approved database restore point with incident-specific approval.

## Legacy traffic observation

For at least 30 days, aggregate `legacy_chatdox_route family=<index|episode|image> status=<code>` application log events by UTC/KST date, family and status. The event contains no query, session, user, email or token. Separate `/up` health traffic; classify obvious bots only from existing platform metadata without adding raw user-agent storage. A redirect requires a later HQ decision; `/docs/images/*` remains a longer-lived compatibility candidate.
