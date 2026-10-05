#!/usr/bin/env python3
"""Read-only Codex history discovery. Never starts, resumes, or steers a turn."""
import argparse, collections, hashlib, json, math, os, pathlib, queue, re, shutil, subprocess, threading, time, unicodedata

class RPC:
    ALLOWED = {'initialize', 'thread/list', 'thread/read', 'thread/turns/list', 'thread/items/list'}
    def __init__(self, executable):
        self.p = subprocess.Popen([executable, 'app-server', '--stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.q = queue.Queue(); self.serial = 0
        def read():
            for line in self.p.stdout:
                try: self.q.put(json.loads(line))
                except (ValueError, UnicodeError): continue
            self.q.put(None)
        threading.Thread(target=read, daemon=True).start()
        try: self.call('initialize', {'clientInfo': {'name':'justclick_history','version':'0.7.0'}, 'capabilities': {'experimentalApi':True}})
        except Exception:
            self.close(); raise
        self.p.stdin.write(b'{"method":"initialized","params":{}}\n'); self.p.stdin.flush()
    def call(self, method, params, timeout=30):
        if method not in self.ALLOWED: raise ValueError('Method is not read-only')
        self.serial += 1; request_id = self.serial
        self.p.stdin.write((json.dumps({'id':request_id,'method':method,'params':params})+'\n').encode()); self.p.stdin.flush()
        deadline = time.monotonic()+timeout
        while time.monotonic()<deadline:
            try: message = self.q.get(timeout=max(0.01,deadline-time.monotonic()))
            except queue.Empty: break
            if message is None: raise RuntimeError('App Server exited')
            if message.get('id') == request_id:
                if 'error' in message: raise RuntimeError('RPC error '+str(message['error'].get('code')))
                return message['result']
            if 'method' in message and 'id' in message:
                self.p.stdin.write((json.dumps({'id':message['id'],'error':{'code':-32601,'message':'Read-only history client'}})+'\n').encode()); self.p.stdin.flush()
        raise TimeoutError(method+' timeout')
    def close(self):
        if self.p.poll() is None:
            self.p.terminate()
            try: self.p.wait(timeout=5)
            except subprocess.TimeoutExpired: self.p.kill(); self.p.wait()

INTERNAL = ('<codex_internal_context','<environment_context','<send_user_message_question_reply','<external_codex_apps_open_page','<system_reminder','<subagent','<turn_aborted','<permissions instructions','<developer','<system>')

def normalize(text):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFKC', text)).strip().rstrip('。.!！?？')

def eligible(text):
    stripped = text.strip()
    if not 4 <= len(stripped) <= 1200: return False
    low = stripped.lower()
    if any(tag in low for tag in INTERNAL): return False
    if low.startswith(('# agents.md', '# skills', '[automated', 'you are a', 'you are an')): return False
    if any(x in low for x in ['jc_ax_e2e_', 'justclick library ui check', 'justclick save visibility check']): return False
    if re.search(r'(?i)(sk-[a-z0-9_-]{16,}|gh[pousr]_[a-z0-9]{20,}|-----begin .*private key|bearer\s+[a-z0-9._-]{15,}|(?:password|api[_ -]?key|token)\s*[:=]\s*\S+)', stripped): return False
    if re.search(r'https?://|/(?:Users|home|var|tmp)/|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', stripped): return False
    if stripped.count('\n') > 10 or '```' in stripped: return False
    return True


def curate(candidates):
    # Only explicit, reviewed equivalences. Never strip negation or branch names.
    families = {
        '继续任务': ('继续任务', '继续任务'),
        '继续完成任务': ('继续任务', '继续任务'),
        '请你继续任务': ('继续任务', '继续任务'),
        '提交到 github': ('提交到 GitHub', '提交到 github。'),
        '请你提交代码到 github': ('提交到 GitHub', '提交到 github。'),
        '提交代码到 github': ('提交到 GitHub', '提交到 github。'),
        '请你直接提交到 github main': ('提交到 GitHub main', '请你直接提交到 github main.'),
        '请你启动服务': ('启动服务', '请你启动服务。'),
        '这是什么问题': ('分析当前问题', '这是什么问题？'),
    }
    grouped = {}
    for candidate in candidates:
        if len(candidate['body']) > 120 or candidate['body'].count('\n') > 1: continue
        normalized = normalize(candidate['body']).lower()
        title, body = families.get(normalized, (candidate['body'].splitlines()[0][:24],candidate['body']))
        key=hashlib.sha256(normalize(body).encode()).hexdigest()
        if key not in grouped:
            grouped[key] = dict(candidate, title=title, body=body, key=key, count=0, threadKeys=set(), variants=[])
        merged=grouped[key]; merged['count']+=candidate['count']; merged['threadKeys'].update(candidate['threadKeys'])
        merged['variants'].append({'body':candidate['body'],'count':candidate['count'],'threadCount':candidate['threadCount']})
        merged['lastUsedAt']=max(merged['lastUsedAt'],candidate['lastUsedAt'])
    for item in grouped.values():
        item['threadCount']=len(item['threadKeys']); item['threadKeys']=sorted(item['threadKeys'])
        item['score']=item['threadCount']*10+math.log2(item['count']+1)
    return list(grouped.values())

def collect(rpc, max_threads=500):
    threads=[]; ids=set(); counts=collections.Counter(); failures=[]
    for archived in [False,True]:
        cursor=None
        while len(threads)<max_threads:
            params={'limit':100,'sortKey':'updated_at','sortDirection':'desc','sourceKinds':['cli','vscode','appServer','unknown'],'archived':archived,'useStateDbOnly':True}
            if cursor: params['cursor']=cursor
            result=rpc.call('thread/list',params)
            for item in result.get('data',[]):
                if item.get('parentThreadId') or item.get('agentRole'):
                    counts['excluded_agent_threads']+=1; continue
                if item['id'] not in ids:
                    ids.add(item['id']); threads.append(item)
            cursor=result.get('nextCursor')
            if not cursor: break
        if cursor: counts['thread_limit_reached']+=1
    groups={}; seen=set(); deadline=time.monotonic()+180
    for n,thread in enumerate(threads[:max_threads]):
        if time.monotonic()>deadline:
            counts['time_limit_reached']+=1; break
        tid=thread['id']; root=thread.get('sessionId') or thread.get('forkedFromId') or tid
        try:
            cursor=None; pages=0
            while True:
                params={'threadId':tid,'limit':100,'sortDirection':'desc','itemsView':'full'}
                if cursor: params['cursor']=cursor
                try: result=rpc.call('thread/turns/list',params)
                except RuntimeError:
                    if pages: raise
                    result={'data':rpc.call('thread/read',{'threadId':tid,'includeTurns':True})['thread'].get('turns',[])}
                for turn in result.get('data',[]):
                    for item in turn.get('items',[]):
                        if item.get('type')!='userMessage': continue
                        counts['user_messages']+=1
                        text='\n'.join(x.get('text','') for x in item.get('content',[]) if x.get('type')=='text').strip()
                        if not eligible(text): counts['excluded_messages']+=1; continue
                        normalized=normalize(text); digest=hashlib.sha256(normalized.encode()).hexdigest()
                        identity=(root,turn.get('id'),item.get('id'),digest)
                        if identity in seen: counts['duplicate_messages']+=1; continue
                        seen.add(identity)
                        group=groups.setdefault(digest,{'body':text,'count':0,'threads':set(),'lastUsedAt':0,'language':'zh' if re.search(r'[\u3400-\u9fff]',text) else 'en'})
                        group['count']+=1; group['threads'].add(root)
                        group['lastUsedAt']=max(group['lastUsedAt'],thread.get('updatedAt',0))
                pages+=1; cursor=result.get('nextCursor')
                if time.monotonic()>deadline and cursor:
                    counts['time_limit_reached']+=1; break
                if not cursor: break
                if pages>=200: counts['turn_page_limit_reached']+=1; break
            counts['threads_read']+=1
        except (RuntimeError,TimeoutError,KeyError) as error:
            failures.append({'thread':hashlib.sha256(tid.encode()).hexdigest()[:12],'error':str(error)[:100]}); counts['threads_failed']+=1
        if (n+1)%10==0: print(json.dumps({'progress':n+1,'total':min(len(threads),max_threads)}),file=__import__('sys').stderr,flush=True)
    ranked=[]
    for digest,group in groups.items():
        roots=group.pop('threads'); group['threadCount']=len(roots)
        group['threadKeys']=sorted(hashlib.sha256(x.encode()).hexdigest()[:24] for x in roots)
        if group['threadCount']<2 or group['count']<2: continue
        group['key']=digest; group['score']=group['threadCount']*10+math.log2(group['count']+1)
        ranked.append(group)
    ranked=curate(ranked)
    ranked.sort(key=lambda g:(g['score'],g['lastUsedAt']),reverse=True)
    return {'version':1,'provider':'codex-app-server','scannedAt':int(time.time()),'coverage':dict(counts),'threadCount':len(threads),'failures':failures,'candidates':ranked[:100]}

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--output',required=True); parser.add_argument('--codex',default=shutil.which('codex')); parser.add_argument('--max-threads',type=int,default=500); parser.add_argument('--probe',action='store_true'); args=parser.parse_args()
    os.umask(0o077)
    if not args.codex: raise SystemExit('Codex CLI not found')
    rpc=RPC(args.codex)
    try:
        if args.probe:
            result=rpc.call('thread/list',{'limit':3,'sourceKinds':['cli','vscode','appServer','unknown'],'useStateDbOnly':True})
            print(json.dumps({'threads_in_probe':len(result.get('data',[])),'has_more':bool(result.get('nextCursor')),'thread_fields':list(result.get('data',[{}])[0].keys()) if result.get('data') else []}))
            return
        result=collect(rpc,args.max_threads)
        out=pathlib.Path(args.output).expanduser();out.parent.mkdir(parents=True,exist_ok=True)
        temp=out.with_suffix('.tmp');temp.write_text(json.dumps(result,ensure_ascii=False,indent=2));temp.replace(out)
        print(json.dumps({'coverage':result['coverage'],'candidate_count':len(result['candidates']),'output':str(out)}))
    finally: rpc.close()
if __name__=='__main__': main()
