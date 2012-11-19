'''

# pycoverage

Use python 2.7 (not 3.x for boto)

prequisites: Setup Riak CS, get key_id and key_secret and write it down to pycoverage/tests.cfg

    $ cd pycoverage
    $ virtualenv .
    $ source bin/activate
    $ pip install boto
    $ python runner.py

to clean up the data when when any test failed:

    $ python cosmo_cleaner.py


'''
