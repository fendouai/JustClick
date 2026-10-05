import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import vm from 'node:vm';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const directory = await mkdtemp(join(tmpdir(),'justclick-mcp-check-'));
const client = new Client({name:'JustClick protocol check',version:'0.1.0'});
let tests=0;
try {
  await client.connect(new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('./server.mjs',import.meta.url))],env:{PATH:process.env.PATH,JUSTCLICK_PROBE_DIR:directory}}));
  const {tools}=await client.listTools();
  const opener=tools.find(t=>t.name==='open_justclick_probe');
  assert.equal(opener._meta.ui.resourceUri,'ui://justclick/probe.html');
  assert.equal(opener._meta['openai/ui'].entrypoints[0].type,'thread');
  tests++;console.log('PASS MCP tool and thread entrypoint metadata');
  const result=await client.callTool({name:'open_justclick_probe',arguments:{}});
  assert.equal(result.structuredContent.probe,true);tests++;console.log('PASS MCP panel tool call');
  const resource=await client.readResource({uri:opener._meta.ui.resourceUri});
  const html=resource.contents[0].text;
  assert.equal(resource.contents[0].mimeType,'text/html;profile=mcp-app');
  assert.ok(html.includes('ui/initialize')&&html.includes('ui/message'));
  tests++;console.log('PASS registered MCP App resource');
  const report={phase:'initialized',hostInfo:{name:'test-host'},hostCapabilities:{message:{text:{}}},secret:'must-not-persist'};
  await client.callTool({name:'record_justclick_probe',arguments:{report:JSON.stringify(report)}});
  const saved=JSON.parse(await readFile(join(directory,'mcp-probe-report.json'),'utf8'));
  assert.equal(saved.phase,'initialized');assert.equal(saved.secret,undefined);
  tests++;console.log('PASS diagnostic report allowlist');
  const bad=await client.callTool({name:'record_justclick_probe',arguments:{report:'not-json'}});
  assert.equal(bad.isError,true);tests++;console.log('PASS invalid report rejected');

  // These are deliberately mock hosts, not proof of real desktop support.
  const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
  async function mockHost(capabilities) {
    const elements=Object.fromEntries(['probe','progress','status','details'].map(id=>[id,{disabled:true,textContent:''}]));
    const requests=[];let listener;const parent={postMessage(message){
      requests.push(message);
      if(message.id===undefined)return;
      const result=message.method==='ui/initialize'?{hostInfo:{name:'MOCK'},hostCapabilities:capabilities}:{};
      queueMicrotask(()=>listener({source:parent,data:{jsonrpc:'2.0',id:message.id,result}}));
    }};
    const context=vm.createContext({document:{getElementById:id=>elements[id]},window:{parent,addEventListener:(_,fn)=>{listener=fn;}},setTimeout,clearTimeout,crypto:{randomUUID},console});
    vm.runInContext(script,context);
    await new Promise(r=>setTimeout(r,10));
    return {elements,requests};
  }
  const unavailable=await mockHost({});
  assert.equal(unavailable.elements.probe.disabled,true);
  assert.ok(!unavailable.requests.some(r=>r.method==='ui/message'));
  tests++;console.log('PASS missing capability disables buttons (mock)');
  const supported=await mockHost({message:{text:{}},experimental:{'openai/message':{}}});
  assert.equal(supported.elements.probe.disabled,false);
  await supported.elements.probe.onclick();
  const message=supported.requests.find(r=>r.method==='ui/message');
  assert.equal(message.params._meta['openai/message'].target,'active');
  assert.equal(message.params._meta['openai/message'].send,true);
  assert.match(message.params.content[0].text,/ACK JC_MCP_/);
  assert.ok(supported.elements.status.textContent.includes('仍')||supported.elements.status.textContent.includes('请确认'));
  tests++;console.log('PASS active-chat message and cautious status (mock)');
  console.log(`${tests} checks passed; actual desktop bridge NOT tested by these checks.`);
} finally { await client.close(); await rm(directory,{recursive:true,force:true}); }
