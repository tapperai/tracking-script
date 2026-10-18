import assert from 'node:assert/strict';
import { test } from 'node:test';

import { CONFIG, parseArgs, pathsFromNameStatus, select } from './test-changed.mjs';

test('a docs-only change reaches no check', () => {
  assert.deepEqual(select(CONFIG, ['README.md', 'docs/x/SPEC.md']), []);
});

test('a code change reaches the checks whose paths it touches', () => {
  const names = select(CONFIG, ['src/root.ts']).map((c) => c.name);
  assert.ok(names.length >= 1);
});

test('a rename lists both paths', () => {
  assert.deepEqual(pathsFromNameStatus('R100\ta.ts\tb.ts\nM\tc.ts\n'), ['a.ts', 'b.ts', 'c.ts']);
});

test('arguments', () => {
  assert.deepEqual(parseArgs(['--list', '--base', 'origin/dev']), { list: true, base: 'origin/dev' });
  assert.throws(() => parseArgs(['--nope']));
});
