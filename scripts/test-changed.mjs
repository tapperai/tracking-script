#!/usr/bin/env node
/**
 * TEST CHANGED: run, on your machine, ONLY the checks your change can reach (testing policy 2026-10-18; this repo's
 * CLAUDE.md "Testing a change"). This repo's test set is small, so "only what changed" is a short list of checks, each
 * with the paths that make it relevant; a docs-only change reaches none.
 *
 *   node scripts/test-changed.mjs                  base = merge-base of HEAD with origin/dev (else origin/master)
 *   node scripts/test-changed.mjs -- --list        print the selection and stop (exit 0)
 *   node scripts/test-changed.mjs -- --base <ref>  measure from <ref> instead
 *
 * The changed set is every commit since the base, plus staged, unstaged and untracked files (a rename lists both
 * paths). Exit code = the first failing check's. On success it prints the trailer to put in the commit and the PR
 * description. The CHECKS below are the same commands tests.yml runs.
 */
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

export const CONFIG = {
  command: 'node scripts/test-changed.mjs',
  /** Changes that no test can reach (prose). */
  docsOnly: /^(docs\/|.*\.md$)/,
  /** [{ name, cmd: [bin, ...args], when: RegExp | null }]: `when` null = always (any non-docs change). */
  checks: [
    { name: 'Validate template structure, grants and Gallery sha', cmd: ['python3', 'scripts/validate_template.py', 'template.tpl', '--metadata', 'metadata.yaml'], when: null },
    { name: 'The ___TESTS___ scenarios (GTM permission semantics)', cmd: ['node', 'scripts/run_template_tests.mjs', 'template.tpl'], when: null },
  ],
};

export function pathsFromNameStatus(out) {
  const files = [];
  for (const line of out.split('\n')) {
    if (!line.trim()) continue;
    const [status, ...paths] = line.split('\t');
    if (/^[RC]/.test(status)) files.push(...paths);
    else if (paths[0]) files.push(paths[0]);
  }
  return files;
}

export function parseArgs(argv) {
  const opts = { list: false, base: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--list') opts.list = true;
    else if (a === '--base') opts.base = argv[++i] ?? '';
    else if (a.startsWith('--base=')) opts.base = a.slice('--base='.length);
    else throw new Error(`unknown argument ${a} (use --list, --base <ref>)`);
  }
  if (argv.includes('--base') && !opts.base) throw new Error('--base needs a ref');
  return opts;
}

/** The checks a change reaches: [] for a docs-only change. */
export function select(config, files) {
  const code = files.filter((f) => !config.docsOnly.test(f));
  if (code.length === 0) return [];
  return config.checks.filter((c) => c.when === null || code.some((f) => c.when.test(f)));
}

const git = (args, cwd) => spawnSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });

export function findBase(cwd, explicit) {
  const candidates = explicit ? [explicit] : ['origin/dev', 'origin/master', 'origin/main', 'dev', 'master', 'main'];
  for (const ref of candidates) {
    const r = git(['merge-base', 'HEAD', ref], cwd);
    if (r.status === 0 && r.stdout.trim()) return { ref, sha: r.stdout.trim() };
  }
  return null;
}

export function changedFiles(cwd, baseSha) {
  const diff = git(['diff', '--name-status', '-M', baseSha], cwd);
  if (diff.status !== 0) throw new Error(`git diff failed: ${diff.stderr}`);
  const untracked = git(['ls-files', '--others', '--exclude-standard'], cwd);
  if (untracked.status !== 0) throw new Error(`git ls-files failed: ${untracked.stderr}`);
  return [...new Set([...pathsFromNameStatus(diff.stdout), ...untracked.stdout.split('\n').filter(Boolean)])];
}

function main() {
  const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); } catch (e) { console.error(e.message); return 2; }
  const base = findBase(root, opts.base);
  if (!base) {
    console.error(`No base found (${opts.base || 'origin/dev, origin/master'}). Run: git fetch origin dev   or pass --base <ref>.`);
    return 2;
  }
  const files = changedFiles(root, base.sha);
  console.log(`Base: ${base.ref} (${base.sha.slice(0, 12)}); ${files.length} changed file(s).`);
  if (files.length === 0) { console.log('Nothing changed since the base: nothing to test.'); return 0; }
  const checks = select(CONFIG, files);
  console.log(`Tests selected: ${checks.length} check(s) of ${CONFIG.checks.length}`);
  for (const c of checks) console.log(`  ${c.name}: ${c.cmd.join(' ')}`);
  if (checks.length === 0) {
    console.log('A docs-only change: no check can reach it. Put in the commit and the PR description: Tests: skip (docs only)');
    return 0;
  }
  if (opts.list) return 0;
  for (const c of checks) {
    console.log(`\n$ ${c.cmd.join(' ')}   (${c.name})`);
    const r = spawnSync(c.cmd[0], c.cmd.slice(1), { stdio: 'inherit' });
    if ((r.status ?? 1) !== 0) return r.status ?? 1;
  }
  const flags = opts.base ? ` -- --base ${opts.base}` : '';
  console.log(`\nPASSED. Put in the commit and the PR description: Tests: local (${CONFIG.command}${flags})`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exit(main());
