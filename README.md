# gy-ingest

Small ingestion scripts for syncing useful sources into `gy-wiki`.

The first working pipeline is RSS:

```text
RSS feed
  -> fetch XML
  -> parse entries
  -> deduplicate by guid/url
  -> save raw feed XML and item JSON
  -> append a daily inbox Markdown file
  -> optionally commit and push gy-wiki
```

## Repository Roles

- `gy-ingest`: scripts, source configuration, scheduled jobs.
- `gy-wiki`: captured source material and later knowledge processing.

## Initialize gy-wiki

Clone your empty wiki repository next to this project, then initialize its folder layout:

```powershell
git clone https://github.com/zhazi77/gy-wiki.git ..\gy-wiki
python scripts\init_wiki.py ..\gy-wiki
```

If `python` is not on PATH, use your installed Python executable.

Commit the initial wiki structure:

```powershell
cd ..\gy-wiki
git add .
git commit -m "initialize wiki structure"
git push -u origin main
```

## Sync RSS Once

From `gy-ingest`:

```powershell
python -m gy_ingest.sync_rss --wiki-root ..\gy-wiki
```

To also commit and push changes in `gy-wiki`:

```powershell
python -m gy_ingest.sync_rss --wiki-root ..\gy-wiki --git --push
```

## Add Sources

Edit `config/sources.yaml`:

```yaml
sources:
  - name: openai-news
    type: rss
    url: https://openai.com/news/rss.xml
    tags: ai, openai, research
```

The YAML parser is intentionally tiny in this first version. Keep each source as simple `key: value` lines, and keep tags comma-separated.

## Output Layout

`gy-wiki` receives:

```text
raw/rss/feeds/<source>/<timestamp>.xml
raw/rss/items/<source>/<year>/<month>/<id-title>.json
inbox/rss/<date>.md
index/manifest.json
```

## Run Tests

```powershell
python -m unittest discover -s tests
```

## Scheduling

On Windows, create a Task Scheduler job that runs every 4 hours:

```powershell
python -m gy_ingest.sync_rss --wiki-root C:\path\to\gy-wiki --git --push
```

Set the task's working directory to the `gy-ingest` repository.

## Server Health Check

On the server, run:

```bash
cd ~/gy-ingest
bash scripts/check_server.sh
```

The health check:

- pulls the latest `gy-ingest`
- runs unit tests
- creates a temporary wiki
- runs a full RSS sync into that temporary wiki
- prints the real `gy-wiki` git status

It does not write test data into the real `gy-wiki`.

## Server Sync Command

After the health check passes, run the real sync with:

```bash
cd ~/gy-ingest
python3 -m gy_ingest.sync_rss --wiki-root ~/gy-wiki --git --push
```
