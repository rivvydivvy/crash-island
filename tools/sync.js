// Pushes src/ into the open Studio place (a minimal one-way Rojo substitute).
//
//   node tools/sync.js            sync every managed root
//   node tools/sync.js --dry      print the generated Luau instead of running it
//
// File naming:  Foo.server.luau -> Script,  Foo.client.luau -> LocalScript,  Foo.luau -> ModuleScript.
// Directories become Folders. Each managed root is mirrored exactly: instances under it that
// have no matching file are destroyed, so only list roots that this project fully owns.
const fs = require('fs');
const path = require('path');
const { callTool } = require('./mcp');

const ROOT = path.join(__dirname, '..', 'src');
const MANAGED = [
  { dir: 'ReplicatedStorage/Shared', target: ['ReplicatedStorage', 'Shared'] },
  { dir: 'ServerScriptService/CrashIsland', target: ['ServerScriptService', 'CrashIsland'] },
  { dir: 'StarterPlayerScripts/CrashIsland', target: ['StarterPlayer', 'StarterPlayerScripts', 'CrashIsland'] },
];

function classify(file) {
  if (file.endsWith('.server.luau')) return { name: file.slice(0, -'.server.luau'.length), cls: 'Script' };
  if (file.endsWith('.client.luau')) return { name: file.slice(0, -'.client.luau'.length), cls: 'LocalScript' };
  if (file.endsWith('.luau')) return { name: file.slice(0, -'.luau'.length), cls: 'ModuleScript' };
  return null;
}

function walk(dir, rel = []) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push({ path: [...rel, entry.name], cls: 'Folder' });
      out.push(...walk(full, [...rel, entry.name]));
    } else {
      const c = classify(entry.name);
      if (c) out.push({ path: [...rel, c.name], cls: c.cls, source: fs.readFileSync(full, 'utf8').replace(/\r\n/g, '\n') });
    }
  }
  return out;
}

// Long-bracket string that cannot be terminated by the content.
function longString(s) {
  let eq = '';
  while (s.includes(']' + eq + ']')) eq += '=';
  return '[' + eq + '[\n' + s + ']' + eq + ']';
}

const luaStr = (s) => JSON.stringify(s);

function generate() {
  const lines = [
    'local function resolve(parts)',
    '\tlocal inst = game:GetService(parts[1])',
    '\tfor i = 2, #parts do',
    '\t\tlocal child = inst:FindFirstChild(parts[i])',
    '\t\tif not child then child = Instance.new("Folder"); child.Name = parts[i]; child.Parent = inst end',
    '\t\tinst = child',
    '\tend',
    '\treturn inst',
    'end',
    'local function ensure(parent, name, cls)',
    '\tlocal existing = parent:FindFirstChild(name)',
    '\tif existing and existing.ClassName ~= cls then existing:Destroy(); existing = nil end',
    '\tif not existing then existing = Instance.new(cls); existing.Name = name; existing.Parent = parent end',
    '\treturn existing',
    'end',
    'local report = {}',
  ];
  let count = 0;
  for (const m of MANAGED) {
    const entries = walk(path.join(ROOT, m.dir));
    lines.push('do');
    lines.push(`\tlocal root = resolve({${m.target.map(luaStr).join(', ')}})`);
    lines.push('\tlocal keep = {}');
    for (const e of entries) {
      count++;
      const parentExpr = e.path.slice(0, -1).reduce((acc, seg) => `${acc}:FindFirstChild(${luaStr(seg)})`, 'root');
      lines.push(`\tdo local inst = ensure(${parentExpr}, ${luaStr(e.path[e.path.length - 1])}, ${luaStr(e.cls)})`);
      if (e.source !== undefined) lines.push(`\t\tinst.Source = ${longString(e.source)}`);
      lines.push('\t\tkeep[inst] = true end');
    }
    lines.push('\tfor _, d in ipairs(root:GetDescendants()) do');
    lines.push('\t\tif not keep[d] and d.Parent and (d:IsA("LuaSourceContainer") or d:IsA("Folder")) then');
    lines.push('\t\t\ttable.insert(report, "removed " .. d:GetFullName()); d:Destroy()');
    lines.push('\t\tend');
    lines.push('\tend');
    lines.push('end');
  }
  lines.push(`return "synced ${count} instances" .. (#report > 0 and ("\\n" .. table.concat(report, "\\n")) or "")`);
  return lines.join('\n');
}

(async () => {
  const code = generate();
  if (process.argv.includes('--dry')) { console.log(code); return; }
  const r = await callTool('execute_luau', { datamodel_type: 'Edit', code });
  console.log(r.text);
  process.exit(r.isError ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
