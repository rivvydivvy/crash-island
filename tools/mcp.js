// Tiny client for Roblox Studio's built-in MCP server (Assistant > ... > Settings > MCP Servers).
//
//   node tools/mcp.js <tool> [json-args | @args.json]
//   node tools/mcp.js lua <Edit|Server|Client> <file.luau>   (execute_luau with the file's contents)
//
// Target Studio: $STUDIO_ID, else the connected Studio whose name matches $STUDIO_NAME
// (default "CrashIsland"). Refuses to guess so it can never touch an unrelated place.
// Images returned by tools are written to tools/.captures/.
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

function findStudioMcpExe() {
  const versions = path.join(process.env.LOCALAPPDATA, 'Roblox', 'Versions');
  const candidates = fs.readdirSync(versions)
    .map((d) => path.join(versions, d, 'StudioMCP.exe'))
    .filter((p) => fs.existsSync(p))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (!candidates.length) throw new Error('StudioMCP.exe not found under ' + versions);
  return candidates[0];
}

function parseArgs(argv) {
  const [tool, a1, a2] = argv;
  if (!tool) throw new Error('usage: node tools/mcp.js <tool> [json|@file]  |  lua <Edit|Server|Client> <file>');
  if (tool === 'lua') return { tool: 'execute_luau', args: { datamodel_type: a1, code: fs.readFileSync(a2, 'utf8') } };
  if (!a1) return { tool, args: {} };
  return { tool, args: a1.startsWith('@') ? JSON.parse(fs.readFileSync(a1.slice(1), 'utf8')) : JSON.parse(a1) };
}

// Calls one tool. Returns { text, images, isError }.
async function callTool(tool, args, { timeoutMs = 560000 } = {}) {
  const proc = spawn(findStudioMcpExe(), [], { stdio: ['pipe', 'pipe', 'pipe'] });
  let buf = '';
  let nextId = 0;
  const pending = new Map();
  proc.stdout.on('data', (d) => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      try {
        const m = JSON.parse(line);
        if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
      } catch { /* non-JSON log line */ }
    }
  });
  proc.stderr.on('data', () => {});
  const req = (method, params) => new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const timer = setTimeout(() => { proc.kill(); console.error('TIMEOUT'); process.exit(2); }, timeoutMs);
  try {
    await req('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'crash-island-tools', version: '1' } });
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');

    // Studio attaches to a freshly spawned proxy asynchronously; poll until it shows up.
    let studios = [];
    for (let k = 0; k < 40 && !studios.length; k++) {
      const l = await req('tools/call', { name: 'list_roblox_studios', arguments: {} });
      const txt = (l.result?.content || []).map((c) => c.text || '').join('');
      try { studios = JSON.parse(txt).studios || []; } catch { studios = []; }
      if (!studios.length) await new Promise((r) => setTimeout(r, 500));
    }
    if (tool === 'list_roblox_studios') return { text: JSON.stringify({ studios }), images: [], isError: false };

    let studioId = process.env.STUDIO_ID;
    if (!studioId) {
      const want = new RegExp(process.env.STUDIO_NAME || 'CrashIsland', 'i');
      const match = studios.filter((s) => want.test(s.name));
      if (match.length !== 1) {
        return { text: `Could not pick a Studio (want /${want.source}/): ${JSON.stringify(studios)}`, images: [], isError: true };
      }
      studioId = match[0].id;
    }
    const res = await req('tools/call', { name: tool, arguments: { ...args, studio_id: studioId } });
    if (res.error) return { text: 'RPC ERROR ' + JSON.stringify(res.error), images: [], isError: true };
    const texts = [];
    const images = [];
    for (const c of res.result.content || []) {
      if (c.type === 'text') texts.push(c.text);
      else if (c.type === 'image') images.push(c);
    }
    return { text: texts.join('\n'), images, isError: !!res.result.isError };
  } finally {
    clearTimeout(timer);
    proc.kill();
  }
}

module.exports = { callTool };

if (require.main === module) {
  (async () => {
    const { tool, args } = parseArgs(process.argv.slice(2));
    const r = await callTool(tool, args);
    console.log(r.text);
    if (r.images.length) {
      const dir = path.join(__dirname, '.captures');
      fs.mkdirSync(dir, { recursive: true });
      r.images.forEach((img, n) => {
        const f = path.join(dir, `cap_${Date.now()}_${n}.${(img.mimeType || 'image/png').split('/')[1]}`);
        fs.writeFileSync(f, Buffer.from(img.data, 'base64'));
        console.log('IMAGE ->', f);
      });
    }
    process.exit(r.isError ? 1 : 0);
  })().catch((e) => { console.error(e.message); process.exit(1); });
}
