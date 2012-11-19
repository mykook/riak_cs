 # -*- coding: utf-8 -*-

import boto
import ConfigParser
import uuid
from boto.s3.connection import S3Connection
from boto.s3.key import Key as S3Key

import t

class KeyTests(t.APITest):
    def __init__(self, config, conn):
        t.APITest.__init__(self, 'keytests', {})
        self.config = config
        self.conn   = conn

    def setup(self):
        self.bucket = self.conn.create_bucket(uuid.uuid4().hex)

    def teardown(self):
        self.bucket.delete()

    def object_test(self):
        # GET/PUT/DELETE/HEAD/OPTIONS/POST Object
        key = S3Key(bucket=self.bucket, name=uuid.uuid4().hex)

        # check not existing
        try:
            key.get_contents_as_string()
        except boto.exception.S3ResponseError as e:
            self.expect('GET object 404', e.status == 404)
            
        self.expect('GET object fail', not key.exists())

        # PUT
        key.set_contents_from_string('hogehogehoge')
        self.expect('PUT object', key.exists())

        key.close()
        assert(key.closed)
        key_name = key.name
    
        # GET
        key = S3Key(bucket=self.bucket, name=key_name)
        self.expect('GET object', 'hogehogehoge' == key.get_contents_as_string())

        key.get_metadata('x-amz-version-id') # => None, is it right?

        # HEAD key
        res = self.conn.make_request('HEAD', self.bucket.name, key.name)
        res.read()
        self.expect('HEAD object', res.status == 200 and int(res.getheader('Content-Length')) == len('hogehogehoge'))
        ( res.getheader('Content-Type') ) # default => application/octet-stream
    
        # OPTIONS
        self.todo('OPTIONS object')
        # POST
        self.todo('POST object')

        # DELETE
        key.delete()
        self.expect('DELETE object', not key.exists())

    def unicode_objectkey_test(self):
        unicode_keyname = u"埼玉"
        key = S3Key(bucket=self.bucket, name=unicode_keyname)
        key.set_contents_from_string("mmmmm")
        all_keys = [ tmpkey.name for tmpkey in self.bucket.get_all_keys() ]
        self.expect("unicode keyname via 'ls'", unicode_keyname in all_keys)
        key.delete()
        self.expect("removal", not key.exists())

    def object_copy_test(self):
        # PUT Object - copy
        self.todo('PUT object - copy')

    def object_multi_delete_test(self):
        # Delete Multiple Objects
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/multiobjectdeleteapi.html

        # first of all create
        keys = [ uuid.uuid4().hex for x in xrange(10) ]
        for k in keys:
            self.bucket.new_key(k).set_contents_from_string(k)
            assert(self.bucket.get_key(k).exists())
    
        try: self.bucket.delete_keys(keys) # => 405 method not allowed
        except: self.todo('DELETE multiple objects')
        else: assert False #self.ok('DELETE multiple objects')

        # delete all keys by hand instead
        for k in keys:
            self.bucket.delete_key(k)
        

    def object_acl_test(self):
        # GET/PUT/DELETE Object ACL
        key = S3Key(bucket=self.bucket, name=uuid.uuid4().hex)
        key.set_contents_from_string('keykeykey')
        acl = key.get_acl()
        acl.to_xml()
        key.set_acl(acl)
        key.delete()
        self.todo('GET/PUT/DELETE object ACL')
        assert(not key.exists())

    def multipart_test(self):
        # Initiate/Complete/Upload/Abort multiple upload
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/mpUploadInitiate.html
        key_name = uuid.uuid4().hex
        try: mp = self.bucket.initiate_multipart_upload(key_name)
        except: self.todo('initiate/complete/upload/abort multipart') # => currently 405 returned
        else:   self.ok('initate/complete/upload/abort multipart')
        # mp.cancel_upload()
        # mp.complete_upload()

        # List parts
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/mpUploadListParts.html
        self.bucket.get_all_multipart_uploads()
        for mp in self.bucket.list_multipart_uploads():
            print(mp)
    
        # Upload part - copy
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/mpUploadUploadPartCopy.html
        # no good function with API :'(

    def torrent_test(self): pass
    # GET Object torrent
    # try: key.get_torrent()
    # except: pass
    # else: assert False
