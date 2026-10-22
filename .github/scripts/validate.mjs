// Checks the repo invariants that break silently, complementing the
// "plugin validate" step the workflow runs. Run locally with
// "node .github/scripts/validate.mjs" from the repo root.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const errors = [];
const report = (file, line, message) =>
  errors.push(line ? `${file}:${line} ${message}` : `${file} ${message}`);

const read = (file) => readFileSync(file, 'utf8');

// Prose covered by the link and typography checks. CLAUDE.md is gitignored
// and LICENSE is frozen legal text, so neither is in scope.
const proseFiles = ['README.md', 'CHANGELOG.md'];
const collectMarkdown = (dir) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const child = path.join(dir, entry.name);
    if (entry.isDirectory()) collectMarkdown(child);
    else if (entry.name.endsWith('.md')) proseFiles.push(child);
  }
};
collectMarkdown('skills');

// 1. Frontmatter of each SKILL.md: name equal to its folder, description
// present and under 300 characters. The runtime reads only these two fields.
for (const skillName of readdirSync('skills')) {
  const dir = path.join('skills', skillName);
  if (!statSync(dir).isDirectory()) continue;
  const file = path.join(dir, 'SKILL.md');
  if (!existsSync(file)) {
    report(dir, null, 'missing SKILL.md');
    continue;
  }
  const block = read(file).match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!block) {
    report(file, 1, 'missing frontmatter');
    continue;
  }
  const fields = {};
  for (const line of block[1].split(/\r?\n/)) {
    const m = line.match(/^(\w+)\s*:\s*(.*)$/);
    if (m) fields[m[1]] = m[2].trim();
  }
  if (fields.name !== skillName) {
    report(file, 2, `name "${fields.name}" differs from folder "${skillName}"`);
  }
  if (!fields.description) {
    report(file, 3, 'description missing from frontmatter');
  } else if ([...fields.description].length > 300) {
    report(file, 3, `description is ${[...fields.description].length} characters, maximum 300`);
  }
}

// 2. Relative links: every target exists, and a link written from inside a
// skill folder stays confined to it, since a manual install copies only
// that folder.
const LINK_PATTERN = /\[[^\]]*\]\(([^)\s]+)\)/g;
for (const file of proseFiles) {
  const text = read(file);
  for (const m of text.matchAll(LINK_PATTERN)) {
    const target = m[1].split('#')[0];
    if (!target || /^(https?:|mailto:)/.test(target)) continue;
    const line = text.slice(0, m.index).split('\n').length;
    const resolved = path.resolve(path.dirname(file), target);
    if (!existsSync(resolved)) {
      report(file, line, `dead link to ${target}`);
      continue;
    }
    const segments = file.split(path.sep);
    if (segments[0] === 'skills' && segments.length > 2) {
      const skillDir = path.resolve(segments[0], segments[1]);
      if (!resolved.startsWith(skillDir + path.sep) && resolved !== skillDir) {
        report(file, line, `link to ${target}, outside the skill's installable folder`);
      }
    }
  }
}

// 3. Typography: no em dash, nor the spaced en dash or double hyphen that
// stand in for it. Syntactic exceptions: frontmatter, code fences and spans,
// link targets, URLs, table separators.
const CHECKS = [
  [/—/, 'em dash in prose; use a comma, a period, or parentheses'],
  [/\s(?:–|--)\s/, 'spaced en dash or double hyphen standing in for an em dash; use a comma, a period, or parentheses'],
];
for (const file of proseFiles) {
  const lines = read(file).split(/\r?\n/);
  let inFence = false;
  let inFrontmatter = false;
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (i === 0 && raw === '---') {
      inFrontmatter = true;
      continue;
    }
    if (inFrontmatter) {
      if (raw === '---') inFrontmatter = false;
      continue;
    }
    if (/^\s*(```|~~~)/.test(raw)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (/^\s*\|(\s*:?-{3,}:?\s*\|)+\s*$/.test(raw)) continue;
    const cleaned = raw
      .replace(/`[^`]*`/g, '')
      .replace(/\]\([^)]*\)/g, ']')
      .replace(/https?:\/\/\S+/g, '');
    for (const [pattern, message] of CHECKS) {
      if (pattern.test(cleaned)) report(file, i + 1, message);
    }
  }
}

// 4. Every script a hook command names exists, since a missing one fails
// only at session start, on the user's machine.
const hooks = JSON.parse(read('hooks/hooks.json'));
for (const groups of Object.values(hooks.hooks ?? {})) {
  for (const group of groups) {
    for (const hook of group.hooks ?? []) {
      for (const m of (hook.command ?? '').matchAll(/\$\{CLAUDE_PLUGIN_ROOT\}\/([^"\s]+)/g)) {
        if (!existsSync(m[1])) report('hooks/hooks.json', null, `hook command names ${m[1]}, which does not exist`);
      }
    }
  }
}

// 5. Once a version is released, the plugin version tracks the latest
// released CHANGELOG version (the agreement a manual release lets drift
// first).
const manifest = JSON.parse(read('.claude-plugin/plugin.json'));
const released = read('CHANGELOG.md').match(/^## \[(\d+\.\d+\.\d+)\]/m);
if (released && manifest.version !== released[1]) {
  report(
    '.claude-plugin/plugin.json',
    null,
    `version ${manifest.version} differs from the latest released CHANGELOG version ${released[1]}`,
  );
}

// 6. The marketplace entry repeats the plugin description, since the
// install listing reads the first and the runtime the second.
const marketplace = JSON.parse(read('.claude-plugin/marketplace.json'));
for (const entry of marketplace.plugins ?? []) {
  if (entry.name === manifest.name && entry.description !== manifest.description) {
    report('.claude-plugin/marketplace.json', null, `description of plugin ${entry.name} differs from plugin.json`);
  }
}

if (errors.length > 0) {
  console.error(`${errors.length} invariant error(s):`);
  for (const e of errors) console.error(`  ${e}`);
  process.exit(1);
}
console.log(`Invariants checked on ${proseFiles.length} files: frontmatter, links, typography, hook scripts, version, descriptions.`);
