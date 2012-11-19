import runner

'''
CAUTION!!! this script deletes ALL objects and buckets at the site.
'''

if __name__ == '__main__':
    config = runner.S3TestConfig(runner.config_file_name)
    conn = runner.get_conn(config.key, config.secret, config.host, config.port)
    
    config.p()

    for b in conn.get_all_buckets():
        bucket = conn.get_bucket(b)
        print("%s:" % bucket.name)
        for key in bucket.list():
            print("deleted %s" % key.name)
            key.delete()
        bucket.delete()
        print("deleted %s" % bucket.name)
        
