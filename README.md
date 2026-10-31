# Pest TIA: a test that reads a Blade view as text replays a stale pass

This repository reproduces a bug in Pest 5's Test Impact Analysis (`--tia`), and shows a proposed fix.

A test that reads a file as text, instead of rendering or executing it, is not re-run when that file changes. `--tia` replays its cached pass, while a plain `pest` run fails it.

It is a fresh Laravel 13 skeleton with PHPUnit swapped for Pest 5.3.4, plus two tests. There is no TIA configuration.

## Requirements

- PHP 8.4 with **PCOV or Xdebug** (coverage mode) loaded. Without one, Pest skips TIA and every `--tia` run is a full run. The scripts check this and stop.
- Composer and git.

## Run it

```bash
git clone https://github.com/jbraband/pest-tia-reads-reproduction.git
cd pest-tia-reads-reproduction
composer install
cp .env.example .env

bash repro.sh
# Windows PowerShell: powershell -ExecutionPolicy Bypass -File repro.ps1
```

The script runs the scenario twice: first on stock Pest (the bug), then with `patches/read-capture.patch` applied to `vendor/pestphp/pest` (the fix). On exit it puts the view and `vendor/` back as they were.

## What you will see

The two tests both touch `resources/views/welcome.blade.php`:

```php
// tests/Feature/ExampleTest.php: renders the view
it('renders the welcome page', function () {
    $this->get('/')->assertOk();
});

// tests/Feature/ConventionsTest.php: reads the view as text
it('keeps the viewport meta tag in the welcome layout', function () {
    expect(file_get_contents(resource_path('views/welcome.blade.php')))
        ->toContain('<meta name="viewport"');
});
```

The script records a TIA baseline, then renames `<meta name="viewport"` to `<meta name="x-viewport"` in the view, which breaks `ConventionsTest`.

**Bug, stock Pest.** `--tia` selects only the test that renders the view, and replays `ConventionsTest` as passed (step 3):

```
─ Experimental TIA mode enabled / 1 affected test file (from 1 changed file).
tests/Feature/ExampleTest.php

Tests:    3 passed (3 assertions, 1 affected, 2 replayed)
```

A plain run fails it (step 4):

```
 FAIL  Tests\Feature\ConventionsTest
Tests:    1 failed, 2 passed (3 assertions)
```

**Fix, patched Pest.** The same edit selects both tests and fails `ConventionsTest` (step 7):

```
─ Experimental TIA mode enabled / 2 affected test files (from 1 changed file).
tests/Feature/ConventionsTest.php
tests/Feature/ExampleTest.php

Tests:    1 failed, 2 passed (3 assertions, 2 affected, 1 replayed)
```

## Run it by hand

Bug:

```bash
vendor/bin/pest --tia --fresh      # 3 passed, baseline recorded
# in resources/views/welcome.blade.php rename <meta name="viewport" to <meta name="x-viewport"
vendor/bin/pest --tia              # 3 passed: ConventionsTest replayed
vendor/bin/pest                    # ConventionsTest fails
git checkout -- resources/views/welcome.blade.php
```

Fix:

```bash
git apply --directory=vendor/pestphp/pest patches/read-capture.patch
vendor/bin/pest --tia --fresh      # 3 passed, baseline recorded
# the same edit
vendor/bin/pest --tia              # 2 affected: ConventionsTest fails
git checkout -- resources/views/welcome.blade.php
git apply -R --directory=vendor/pestphp/pest patches/read-capture.patch
```

Record a fresh baseline (`--fresh`) after you apply or remove the patch. Otherwise TIA treats the edit as already handled and replays both tests.

## Why it happens

TIA links a test to the files it depends on through coverage, which only sees executed code, and through `BladeEdges`, which only sees rendered views. `ConventionsTest` reads the view with `file_get_contents()`, so nothing links it to the view.

The watch patterns do not catch it either. Pest's built-in Laravel default maps `resources/views/**` to the whole test directory, and the docs (Custom Watch Patterns) say: "Whenever a matching file changes, every test under that directory is invalidated." But `Graph::applyWatchPatternFallback()` (`src/Plugins/Tia/Graph.php:655`, v5.3.4) only passes files that are unknown to the graph to the watch patterns:

```php
if (! isset($this->fileIds[$rel])) {
    // ...
    $unknownToGraph[] = $rel;
}
```

`ExampleTest` renders the view, so the view is known, and no watch pattern, built-in or user-defined, is consulted for it.

## The fix

`patches/read-capture.patch` (against v5.3.4) records the files a test reads:

- `src/Plugins/Tia/ReadCapture.php` (new): a `file://` stream wrapper, registered only while a test records. It passes every operation to PHP's native wrapper, and links each file opened for reading through `Recorder::linkSource()`, the hook `BladeEdges` uses. Includes are skipped, because coverage already records executed files, and so are write-only opens. `pestphp/pest-plugin-mutate` overrides `file://` the same way (`Pest\Mutate\Support\StreamWrapper`). If another wrapper already owns `file://` (such as `dg/bypass-finals` or Patchwork), it opens through that wrapper with the original flags, including the include flag, and registers it again after the test.
- `src/Plugins/Tia/Recorder.php`: starts the capture in `beginTest()`, stops it in `endTest()` and `reset()`, and adds `linkRead()`, which keeps only project files through the existing `SourceScope`. `vendor/`, `storage/framework` and root dotfiles such as `.env` are never linked.

On this skeleton the patch adds exactly one graph edge: `tests/Feature/ConventionsTest.php -> resources/views/welcome.blade.php`. With 500 extra tests that each render `/` and read a config file, recording (`--tia --fresh`) took 28.7–29.7 s against 27.0–28.1 s on stock Pest, about 4% more. Plain runs are unaffected, because the wrapper is only registered while TIA records.

Known gaps: directory listings (`scandir`, `glob`) are not captured. While a test records, a failed open (such as `file_get_contents()` of a missing file) raises two warnings instead of one; mutate's wrapper does the same.

## Notes

- Under an AI coding agent, `laravel/pao` (part of the skeleton) switches Pest to one-line JSON output. Run the script in a plain terminal to see the output above.
- On Windows, the failure message prints the whole view. On Linux it is cut to a few lines.
- TIA keeps its state in `~/.pest/tia/pest-tia-reads-reproduction-<hash>`. Delete that directory when you are done.

## Related

Same mechanism (watch fallback skipped for a file the graph knows):

- pestphp/pest#1926: `config/*.php` linked only to the first test per worker, so the whole-suite fallback never fires.
- pestphp/pest#1935 / pestphp/pest#1936: JS modules marked resolved, so their watch patterns are skipped.

## Environment

- Pest 5.3.4, pest-plugin-laravel 5.0.1, PHPUnit 13.4.5, Laravel 13.39.0
- PHP 8.4, PCOV
- Reproduced on Windows 11 (`repro.ps1`, and `repro.sh` in Git Bash) and Linux (WSL, `repro.sh`)
