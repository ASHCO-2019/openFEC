import logging
# from elasticsearch import Elasticsearch
# import boto3
from webservices import utils

logger = logging.getLogger(__name__)


def test_es_conn():

    try:
        es_service_client = utils.create_es_client()

        client = es_service_client["client"]
        # broker = es_service_client["broker"]
        document = {
            "title": "Moneyball",
            "director": "Bennett Miller",
            "year": "2011"
        }

        client.index(index="movies", id="5", body=document)

        logger.info(client.get(index="movies", id="5"))

    except Exception as err:
        logger.error('An error occurred while running the load command.{0}'.format(err))

