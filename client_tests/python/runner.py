import ConfigParser
from boto.s3.connection import S3Connection

import bucket_test
import key_test

config_file_name = 'tests.cfg'

class S3TestConfig:
    def __init__(self, filename):
        self.c = ConfigParser.ConfigParser()
        self.c.readfp(open(filename))
        self.host = self.c.get('s3', 'host')
        self.port = int(self.c.get('s3', 'port'))
        self.key  = self.c.get('s3', 'key_id')
        self.secret = self.c.get('s3', 'key_secret')
        self.name = 'riak_cs'

    def p(self):
        print("testing onto http://%s:%d/ with key:%s secret:%s" % (self.host, self.port, self.key, self.secret[:10]))


def get_conn(key, secret, host, port):
    print(host)
    print(port)
    conn = S3Connection(aws_access_key_id=key,
                        aws_secret_access_key=secret,
                        proxy=host, proxy_port=port, is_secure=False)
    return conn


if __name__ == '__main__':
    print('==================================================')

    config = S3TestConfig(config_file_name)
    conn = get_conn(config.key, config.secret, config.host, config.port)
    
    config.p()
    print('start')

    t = key_test.KeyTests(config, conn)
    t.run()
    t.print_result()

    t0 = bucket_test.BucketTests(config, conn)
    t0.run()
    t0.print_result()
    print('done.')
    conn.close()
