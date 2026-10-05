import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';

const uri = 'ui://justclick/probe.html';
const server = new McpServer({ name: 'JustClick MCP probe', version: '0.1.0' });
server.registerResource('justclick-probe-panel', uri, { mimeType: 'text/html;profile=mcp-app' }, async () => ({
  contents: [{ uri, mimeType: 'text/html;profile=mcp-app',
    text: await readFile(new URL('./panel.html', import.meta.url), 'utf8'),
    _meta: { ui: { csp: { connectDomains: [], resourceDomains: [] }, prefersBorder: true } }
  }]
}));
server.registerTool('open_justclick_probe', {
  title: 'JustClick MCP 验证面板',
  description: '打开当前聊天的 JustClick 按钮验证面板，检查宿主能力并由用户点击发送无害测试消息。不要把面板已显示当成发送已验证。',
  inputSchema: {},
  annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
  _meta: {
    ui: { resourceUri: uri, visibility: ['model', 'app'] },
    'openai/outputTemplate': uri,
    'openai/ui': { entrypoints: [{ type: 'thread' }] }
  }
}, async () => ({ content: [{ type: 'text', text: '请在当前聊天打开此面板。先查看宿主能力，再点击“发送验证消息”；只有同一聊天出现消息和对应 ACK 才算通过。' }], structuredContent: { probe: true } }));
server.registerTool('record_justclick_probe', {
  description: '保存面板的宿主能力与协议响应；不记录聊天历史、账户或提示词库。',
  inputSchema: { report: z.string().max(50_000) },
  annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
  _meta: { ui: { visibility: ['app'] } }
}, async ({ report }) => {
  let parsed;
  try { parsed = JSON.parse(report); } catch { return { isError: true, content: [{ type: 'text', text: '报告不是有效 JSON。' }] }; }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { isError: true, content: [{ type: 'text', text: '报告必须是 JSON 对象。' }] };
  }
  const allowed = ['hostInfo', 'hostCapabilities', 'phase', 'messageId', 'response', 'error'];
  const clean = Object.fromEntries(allowed.filter(k => k in parsed).map(k => [k, parsed[k]]));
  const directory = process.env.JUSTCLICK_PROBE_DIR || join(homedir(), 'Library/Application Support/JustClick');
  await mkdir(directory, { recursive: true });
  await writeFile(join(directory, 'mcp-probe-report.json'), JSON.stringify({ recordedAt: new Date().toISOString(), ...clean }, null, 2), { mode: 0o600 });
  return { content: [{ type: 'text', text: '协议报告已保存。消息响应不等于同一聊天端到端验证通过。' }] };
});
await server.connect(new StdioServerTransport());
