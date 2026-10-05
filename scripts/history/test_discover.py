import unittest
import discover

def msg(text,id='user-1'):
    return {'id':id,'type':'userMessage','content':[{'type':'text','text':text}]}
class FakeRPC:
    def call(self,method,params):
        assert method in discover.RPC.ALLOWED
        if method=='thread/list':
            if params['archived']: return {'data':[],'nextCursor':None}
            if not params.get('cursor'): return {'data':[{'id':'a','sessionId':'a','updatedAt':1},{'id':'sub','parentThreadId':'a'}],'nextCursor':'page2'}
            return {'data':[{'id':'b','sessionId':'b','updatedAt':2},{'id':'fork','sessionId':'a','updatedAt':3}],'nextCursor':None}
        if method=='thread/turns/list':
            items=[msg('继续任务'),msg('<codex_internal_context source="goal">continue</codex_internal_context>','auto'),{'id':'tool','type':'agentMessage','text':'继续任务'}]
            return {'data':[{'id':'turn-1','items':items}],'nextCursor':None}
        raise AssertionError(method)
class Checks(unittest.TestCase):
    def test_filters(self):
        for body in ['可以','token=abcdefghijklmno','https://private.example/path','请读取 /Users/someone/private.txt','<environment_context>secret</environment_context>']:
            self.assertFalse(discover.eligible(body))
        self.assertTrue(discover.eligible('继续任务'))
    def test_pagination_sources_and_fork_dedup(self):
        report=discover.collect(FakeRPC())
        self.assertEqual(report['coverage']['threads_read'],3)
        self.assertEqual(report['coverage']['excluded_agent_threads'],1)
        self.assertEqual(report['coverage']['duplicate_messages'],1)
        self.assertEqual(len(report['candidates']),1)
        self.assertEqual(report['candidates'][0]['count'],2)
        self.assertEqual(report['candidates'][0]['threadCount'],2)
    def test_branch_and_negation_are_not_merged(self):
        def row(body): return {'body':body,'count':2,'threadCount':2,'threadKeys':['a','b'],'lastUsedAt':1,'language':'zh','key':'unused','score':20}
        values=discover.curate([row('提交到 github。'),row('请你直接提交到 github main.'),row('不要提交到 github。')])
        self.assertEqual(len(values),3)
    def test_write_methods_blocked(self):
        client=discover.RPC.__new__(discover.RPC)
        with self.assertRaises(ValueError): client.call('turn/start',{})
if __name__=='__main__': unittest.main()
