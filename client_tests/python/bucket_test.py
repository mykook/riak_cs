import boto
import uuid
from boto.s3.key import Key as S3Key

import t

class BucketTests(t.APITest):
    def __init__(self, config, conn):
        t.APITest.__init__(self, 'keytests', {})
        self.config = config
        self.conn   = conn

    def setup(self):
        self.bucket = self.conn.create_bucket(uuid.uuid4().hex)
        newkey = uuid.uuid4().hex
    #assert(not bucket.exists(newkey))
        self.k = self.bucket.new_key(newkey)
        assert(not self.k.exists())
        self.k.set_contents_from_string('hogehoge')
        assert(self.k.exists())

    def teardown(self):
        self.k.delete()
        assert(not self.k.exists())

        self.bucket.delete()

    def cd_test(self):
        bucket = self.conn.create_bucket(uuid.uuid4().hex)
        self.expect('create bucket', bucket)

    # Delete Bucket
    # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketDELETE.html
        bucket.delete()
        self.ok('delete bucket')

    def get_all_buckets_test(self):
        # GET Service
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTServiceGET.html
        l0 = self.conn.get_all_buckets()
        bucket = self.conn.create_bucket(uuid.uuid4().hex)
        l = self.conn.get_all_buckets()
        self.expect('GET Service', len(l) == len(l0)+1 )
        bucket.delete()

    def get_list_objects_test(self):
        # GET List Objects
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketGET.html
        self.expect('GET List Objects', len(self.bucket.get_all_keys()) == 1)

    def head_bucket_test(self):
        # HEAD Bucket
        res = self.conn.make_request('HEAD', self.bucket.name, '')
        res.read()
        self.expect('HEAD bucket',  res.status == 200)

    def cors_test(self):
        # Cross-Origin Resource Sharing
        # http://docs.amazonwebservices.com/AmazonS3/latest/dev/cors.html
        self.todo('GET/PUT/DELETE cors')

        # GET cors
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketGETcors.html
        try:    bucket.get_cors()
        except: self.todo('GET cors')
        else:   self.ok('GET cors')

        # DELETE cors
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketDELETEcors.html
        try: bucket.delete_cors()
        except: self.todo('DELETE cors')
        else:   self.ok('DELETE cors')

        # PUT cors
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketPUTcors.html
        try:
            config = boto.s3.cors.CORSConfiguration()
            self.bucket.put_cors(config)
        except: self.todo('PUT cors')
        else:   self.ok('PUT cors')

    def expiration_test(self):
        # Object Expiration
        # http://docs.amazonwebservices.com/AmazonS3/latest/dev/ObjectExpiration.html
        # GET lifecycle
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketGETlifecycle.html
        try: bucket.get_lifecycle_config()
        except: self.todo('GET lifecycle')
        else:   self.ok('GET lifecycle')

        # PUT lifecycle
        try:
            lifecycle = boto.s3.lifecycle.Lifecycle()
            bucket.put_lifecycle_config(lifecycle)
        except: self.todo('PUT lifecycle')
        else:   self.ok('PUT lifecycle')

        # DELETE lifecycle
        try:    bucket.delete_lifecycle_config()
        except: self.todo('DELETE lifecycle')
        else:   self.ok('DELETE lifecycle')

    def policy_test(self):
        # Bucket Policies
        # http://docs.amazonwebservices.com/AmazonS3/latest/dev/ObjectExpiration.html
        policy = self.bucket.get_policy() # FIXME: some XML will be returned
        self.bucket.set_policy(policy)
        # FIXME: delete_policy DELETE /?policy deletes the bucket itself - oops.
        # if key exists this succeeds and bucket is not deleted, without any error.
        try: self.bucket.delete_policy()
        except: pass
        else: assert False
        self.todo('GET/PUT/DELETE policy')

    def tagging_test(self):
        # GET/PUT/DELETE Tagging
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketDELETEtagging.html
        try: tags = self.bucket.get_tags()
        except: pass
        else:   assert False

        try: self.bucket.set_tags(['tagtest'])
        except: pass
        else:   assert False

        try: self.bucket.delete_tags()
        except: pass
        else:   assert False

    def website_test(self):
    # GET/PUT Website
    # http://docs.amazonwebservices.com/AmazonS3/latest/dev/WebsiteHosting.html
    # bug: c = bucket.get_website_configuration()
        c = self.bucket.get_website_configuration_with_xml()
        self.bucket.configure_website("example.com") # FIXME: not working
        c = self.bucket.get_website_configuration_with_xml()
    # FIXME: this deletes the whole bucket /?website will be ignored
    # if key exists this succeeds and bucket is not deleted, without any error.
        try: self.bucket.delete_website_configuration()
        except: pass
        else:   assert False
        self.todo('GET/PUT website')

    def bucket_acl_test(self):
    # GET/PUT Bucket ACL
        acl = self.bucket.get_acl()
        acl.to_xml()
        self.bucket.set_acl(acl)

    
    def bucket_location_test(self):
    # GET Bucket Location
        try: print(self.bucket.get_location())
        except: self.todo('GET location')
        else:   self.ok('GET location')

    def logging_test(self):
    # GET/PUT Bucket Logging
        self.bucket.get_logging_status().to_xml() # => Disbaled
        assert self.bucket.enable_logging(self.bucket.name)
        self.bucket.get_logging_status().to_xml() # => Enabled (FIXME)
        assert self.bucket.disable_logging()
        self.todo('GET/PUT bucket logging')

    def notification_test(self): pass
    # GET/PUT Bucket Notification
    # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketPUTnotification.html
    # looks not implemented in boto => SNS

    def versions_test(self):
    # GET Bucket Object Versions
    # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTBucketGETVersion.html
        self.expect('GET bucket object version', len(self.bucket.get_all_versions()) == 0)

    def versioning_test(self):
    # GET/PUT Bucket Versioning
        self.bucket.configure_versioning(True)
        self.bucket.get_versioning_status() # => {}
        self.bucket.configure_versioning(False)
        self.todo('GET/PUT bucket versioning')

    def request_payment_test(self):
    # GET/PUT Bucket Request Payment
        self.bucket.set_request_payment(payer='superman')
        self.bucket.get_request_payment()
        self.todo('GET/PUT Bucket Request Payment')

    def list_multipart_uploads_test(self):
    # List multipart Uploads
        self.bucket.list_multipart_uploads()
        self.todo('List multipart uploads')
