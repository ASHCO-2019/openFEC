import boto
import boto3
import logging
from webservices.env import env
from boto.s3.key import Key

logging.getLogger('boto3').setLevel(logging.CRITICAL)
logging.getLogger('smart_open').setLevel(logging.CRITICAL)

def get_app():
    from webservices.rest import app
    return app

def get_bucket():
    session = boto3.Session(
        aws_access_key_id=env.get_credential('access_key_id'),
        aws_secret_access_key=env.get_credential('secret_access_key'),
        region_name=env.get_credential('region')
    )
    s3 = session.resource('s3')
    return s3.Bucket(env.get_credential('bucket'))

def get_object(key):
    return get_bucket().Object(key=key)

def get_s3_key(name):
    connection = boto.s3.connect_to_region(
        env.get_credential('region'),
        aws_access_key_id=env.get_credential('access_key_id'),
        aws_secret_access_key=env.get_credential('secret_access_key'),
    )
    bucket = connection.get_bucket(env.get_credential('bucket'))
    key = Key(bucket=bucket, name=name)
    return key
