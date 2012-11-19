
class APITestSuite:
    def __init__(self): pass


    def merge(self, suite): pass

class APITest:
    def __init__(self, name, impl_status):
        self.name = name
        self.results = {}
        self.todos = []

    def run(self):
        self.setup()
        for member in dir(self):
            if member[-5:] == '_test':
                # run the test fixture
                try:
                    getattr(self, member)()
                except Exception as e:
                    self.failed(member)
                    print(e)
        self.teardown()

    def ok(self, name):
        self.results[name] = True

    def failed(self, name):
        self.results[name] = False

    def todo(self, name):
        self.todos.append(name)

    def print_result(self):
        ok = 0
        failed = []
        for k,v in self.results.items():
            if v:
                #print("%s\t... ok" % k)
                ok = ok + 1
            else:
                failed.append(k)

        print("total: ok(%d) fail(%d) todo(%d)" % (ok, len(self.results) - ok, len(self.todos)))
        print("todos: %s" % self.todos)
        if failed: print("failed: %s" % failed)

    def expect(self, name, somebool_or_obj):
        if somebool_or_obj:
            self.ok(name)
            print("%s\t... ok" % name)

        else:
            self.failed(name)
            print("%s\t... ng" % k)            
