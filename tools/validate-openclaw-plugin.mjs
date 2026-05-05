import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();

function readJson(relativePath) {
  const fullPath = path.join(root, relativePath);
  try {
    return JSON.parse(fs.readFileSync(fullPath, 'utf8'));
  } catch (error) {
    throw new Error(`${relativePath} is not valid JSON: ${error.message}`);
  }
}

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function parseFrontmatter(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!match) {
    throw new Error(`${path.relative(root, file)} is missing YAML frontmatter`);
  }
  const frontmatter = match[1];
  if (frontmatter.includes('\n  ') || frontmatter.includes('|\n')) {
    throw new Error(
      `${path.relative(root, file)} has multi-line frontmatter; OpenClaw skill metadata must stay single-line`
    );
  }
  const fields = new Map();
  for (const line of frontmatter.split('\n')) {
    const index = line.indexOf(':');
    if (index === -1) {
      throw new Error(`${path.relative(root, file)} has invalid frontmatter line: ${line}`);
    }
    fields.set(line.slice(0, index).trim(), line.slice(index + 1).trim());
  }
  return fields;
}

const manifest = readJson('openclaw.plugin.json');
const pkg = readJson('package.json');

if (manifest.id !== 'opendeploy') {
  throw new Error('openclaw.plugin.json id must be opendeploy');
}
if (!manifest.configSchema || manifest.configSchema.type !== 'object') {
  throw new Error('openclaw.plugin.json must include an object configSchema');
}
if (!Array.isArray(manifest.skills) || manifest.skills.length === 0) {
  throw new Error('openclaw.plugin.json must list skill roots');
}
if (pkg.version !== manifest.version) {
  throw new Error(`package.json version (${pkg.version}) must match openclaw.plugin.json version (${manifest.version})`);
}
if (!pkg.openclaw?.compat?.pluginApi || !pkg.openclaw?.build?.openclawVersion) {
  throw new Error('package.json must include openclaw.compat.pluginApi and openclaw.build.openclawVersion');
}

const declaredSkillFiles = [];
for (const skillRoot of manifest.skills) {
  if (!skillRoot.startsWith('./')) {
    throw new Error(`Skill root must be relative and start with ./: ${skillRoot}`);
  }
  const resolved = path.resolve(root, skillRoot);
  if (!resolved.startsWith(root + path.sep)) {
    throw new Error(`Skill root escapes plugin directory: ${skillRoot}`);
  }
  const skillFile = path.join(resolved, 'SKILL.md');
  if (!fs.existsSync(skillFile)) {
    throw new Error(`Declared skill root is missing SKILL.md: ${skillRoot}`);
  }
  declaredSkillFiles.push(skillFile);
}

const allSkillFiles = walk(path.join(root, 'skills')).filter((file) => path.basename(file) === 'SKILL.md');
const declared = new Set(declaredSkillFiles.map((file) => path.resolve(file)));
for (const file of allSkillFiles) {
  if (!declared.has(path.resolve(file))) {
    throw new Error(`Skill exists but is not declared in openclaw.plugin.json: ${path.relative(root, file)}`);
  }
  const fields = parseFrontmatter(file);
  for (const required of ['name', 'version', 'description', 'user-invocable', 'metadata']) {
    if (!fields.has(required)) {
      throw new Error(`${path.relative(root, file)} missing frontmatter field: ${required}`);
    }
  }
  if (fields.get('version').replaceAll('"', '') !== manifest.version) {
    throw new Error(`${path.relative(root, file)} version does not match manifest version`);
  }
  try {
    const metadata = JSON.parse(fields.get('metadata'));
    const openclaw = metadata.openclaw;
    if (!openclaw?.requires?.bins?.includes('node') || !openclaw.requires.bins.includes('npm')) {
      throw new Error('metadata.openclaw.requires.bins must include node and npm');
    }
    const install = openclaw.install ?? [];
    if (!install.some((entry) => entry.kind === 'node' && entry.package === '@opendeploydev/cli')) {
      throw new Error('metadata.openclaw.install must declare @opendeploydev/cli');
    }
  } catch (error) {
    throw new Error(`${path.relative(root, file)} has invalid metadata JSON: ${error.message}`);
  }
}

console.log(`Validated ${allSkillFiles.length} OpenClaw skills`);
