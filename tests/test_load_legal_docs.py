import unittest
from mock import patch
from webservices.legal_docs import (
    delete_advisory_opinions_from_s3,
    delete_murs_from_es,
    delete_murs_from_s3,
    index_advisory_opinions,
    index_regulations,
    index_statutes,
    load_advisory_opinions_into_s3,
    load_archived_murs,
    initialize_legal_docs
)

from webservices.legal_docs.load_legal_docs import (
    get_subject_tree,
    get_title_26_statutes,
    get_title_52_statutes,
    get_xml_tree_from_url,
)
from webservices.legal_docs import DOCS_INDEX

from zipfile import ZipFile
from tempfile import NamedTemporaryFile
import json

def test_get_subject_tree():
    assert get_subject_tree("foo") == [{"text": "Foo"}]
    assert get_subject_tree("<li>foo</li>") == [{"text": "Foo"}]
    assert get_subject_tree(
        "foo<ul class='no-top-margin'><li>bar</li><li>baz</li></ul>") == [
            {"text": "Foo", "children": [{"text": "Bar"}, {"text": "Baz"}]}]

class ElasticSearchMock:
    class ElasticSearchIndicesMock:
        def delete(self, index):
            assert index == 'docs'

        def create(self, index, mappings):
            assert index == 'docs'
            assert mappings

    def __init__(self, dictToIndex):
        self.dictToIndex = dictToIndex
        self.indices = ElasticSearchMock.ElasticSearchIndicesMock()

    def search():
        pass

    def index(self, index, doc_type, doc, id):
        assert self.dictToIndex == doc

    def delete_by_query(self, index, body, doc_type):
        assert index == DOCS_INDEX


def get_es_with_doc(doc):
    def get_es():
        return ElasticSearchMock(doc)
    return get_es

def mock_xml(xml):
    def request_zip(url, stream=False):
        with NamedTemporaryFile('w+') as f:
            f.write(xml)
            f.seek(0)
            with NamedTemporaryFile('w+') as n:
                with ZipFile(n.name, 'w') as z:
                    z.write(f.name)
                    return open(n.name, 'rb')

    return request_zip

def mock_archived_murs_get_request(html):
    def request_murs_data(url, stream=False):
        if stream:
            return [b'ABC', b'def']
        else:
            return RequestResult(html)
    return request_murs_data

class Engine:
    def __init__(self, legal_loaded):
        self.legal_loaded = legal_loaded

    def __iter__(self):
        return self.result.__iter__()

    def __next__(self):
        return self.result.__next__()

    def fetchone(self):
        return self.result[0]

    def fetchall(self):
        return self.result

    def connect(self):
        return self

    def execution_options(self, stream_results):
        return self

    def execute(self, sql):
        if sql == 'select document_id from document':
            self.result = [(1,), (2,)]
        if 'fileimage' in sql:
            return [(1, 'ABC'.encode('utf8'))]
        if 'EXISTS' in sql:
            self.result = [(self.legal_loaded,)]
        if 'COUNT' in sql:
            self.result = [(5,)]
        if 'aouser.players' in sql:
            self.result = [{'name': 'Charles Babbage', 'description': 'Individual'},
                            {'name': 'Ada Lovelace', 'description': 'Individual'}]
        if 'SELECT ao_no, category, ocrtext' in sql:
            self.result = [{'ao_no': '1993-01', 'category': 'Votes', 'ocrtext': 'test 1993-01 test 2015-05 and 2014-1'},
                         {'ao_no': '2007-05', 'category': 'Final Opinion', 'ocrtext': 'test2 1993-01 test2'}]
        if 'SELECT ao_no, name FROM' in sql:
            self.result = [{'ao_no': '1993-01', 'name': 'RNC'}, {'ao_no': '2007-05', 'name': 'Church'},
                            {'ao_no': '2014-01', 'name': 'DNC'}, {'ao_no': '2015-05', 'name': 'Outkast'}]
        if 'document_id' in sql:
            self.result = [{'document_id': 123, 'ocrtext': 'textAB', 'description': 'description123',
                           'category': 'Votes', 'ao_id': 'id123',
                           'name': 'name4U', 'summary': 'summaryABC', 'tags': 'tags123',
                           'ao_no': '1993-01', 'document_date': 'date123', 'is_pending': True}]
        return self


class Db:
    def __init__(self, legal_loaded=True):
        self.engine = Engine(legal_loaded)

def get_credential_mock(var, default):
    return 'https://eregs.api.com/'

class RequestResult:
    def __init__(self, result):
        self.result = result
        self.text = result

    def json(self):
        return self.result

def mock_get_regulations(url):
    if url.endswith('regulation'):
        return RequestResult({'versions': [{'version': 'versionA',
                             'regulation': 'reg104'}]})
    if url.endswith('reg104/versionA'):
        return RequestResult({'children': [{'children': [{'label': ['104', '1'],
                               'title': 'Section 104.1 Title',
                               'text': 'sectionContentA',
                               'children': [{'text': 'sectionContentB',
                               'children': []}]}]}]})

class obj:
    def __init__(self, key):
        self.key = key

    def delete(self):
        pass

class S3Objects:
    def __init__(self, objects):
        self.objects = objects

    def filter(self, Prefix):
        return [o for o in self.objects if o.key.startswith(Prefix)]

class BucketMock:
    def __init__(self, existing_pdfs, key):
        self.objects = S3Objects(existing_pdfs)
        self.key = key

    def put_object(self, Key, Body, ContentType, ACL):
        assert Key == self.key

def get_bucket_mock(existing_pdfs, key):
    def get_bucket():
        return BucketMock(existing_pdfs, key)
    return get_bucket

class IndexStatutesTest(unittest.TestCase):
    @patch('webservices.legal_docs.load_legal_docs.requests.get', mock_xml('<test></test>'))
    def test_get_xml_tree_from_url(self):
        etree = get_xml_tree_from_url('anything.com')
        assert etree.getroot().tag == 'test'

    @patch('webservices.utils.get_elasticsearch_connection',
            get_es_with_doc({'name': 'title',
            'chapter': '1', 'title': '26', 'no': '123',
            'text': '   title  content ', 'doc_id': '/us/usc/t26/s123',
            'url': 'http://api.fdsys.gov/link?collection=uscode&title=26&' +
                    'year=mostrecent&section=123'}))
    @patch('webservices.legal_docs.load_legal_docs.requests.get', mock_xml(
        """<?xml version="1.0" encoding="UTF-8"?>
            <uscDoc xmlns="http://xml.house.gov/schemas/uslm/1.0">
            <subtitle identifier="/us/usc/t26/stH">
            <chapter identifier="/us/usc/t26/stH/ch1">
            <section identifier="/us/usc/t26/s123">
            <heading>title</heading>
            <subsection>content</subsection>
            </section></chapter></subtitle></uscDoc>
            """))
    def test_title_26(self):
        get_title_26_statutes()

    @patch('webservices.utils.get_elasticsearch_connection',
            get_es_with_doc({'subchapter': 'I',
            'doc_id': '/us/usc/t52/s123', 'chapter': '1',
            'text': '   title  content ',
            'url': 'http://api.fdsys.gov/link?collection=uscode&title=52&' +
                   'year=mostrecent&section=123',
            'title': '52', 'name': 'title', 'no': '123'}))
    @patch('webservices.legal_docs.load_legal_docs.requests.get', mock_xml(
        """<?xml version="1.0" encoding="UTF-8"?>
            <uscDoc xmlns="http://xml.house.gov/schemas/uslm/1.0">
            <subtitle identifier="/us/usc/t52/stIII">
            <subchapter identifier="/us/usc/t52/stIII/ch1/schI">
            <section identifier="/us/usc/t52/s123">
            <heading>title</heading>
            <subsection>content</subsection>
            </section></subchapter></subtitle></uscDoc>
            """))
    def test_title_52(self):
        get_title_52_statutes()

    @patch('webservices.legal_docs.load_legal_docs.get_title_52_statutes', lambda: '')
    @patch('webservices.legal_docs.load_legal_docs.get_title_26_statutes', lambda: '')
    def test_index_statutes(self):
        index_statutes()

class IndexRegulationsTest(unittest.TestCase):
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', get_credential_mock)
    @patch('webservices.legal_docs.load_legal_docs.requests.get', mock_get_regulations)
    @patch('webservices.utils.get_elasticsearch_connection',
            get_es_with_doc({'text': 'sectionContentA sectionContentB',
            'no': '104.1', 'name': 'Title',
            'url': '/regulations/104-1/versionA#104-1',
            'doc_id': '104_1'}))
    def test_index_regulations(self):
        index_regulations()

    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e, d: '')
    def test_no_env_variable(self):
        index_regulations()

class IndexAdvisoryOpinionsTest(unittest.TestCase):
    @patch('webservices.legal_docs.load_legal_docs.db', Db())
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential',
        lambda cred: cred + '123')
    @patch('webservices.utils.get_elasticsearch_connection',
            get_es_with_doc({'category': 'Votes',
            'summary': 'summaryABC', 'no': '1993-01', 'date': 'date123',
            'name': 'name4U', 'text': 'textAB',
            'description': 'description123',
            'url': 'https://bucket123.s3.amazonaws.com/legal/aos/123.pdf',
            'doc_id': 123, 'is_pending': True,
            'requestor_names': ['Charles Babbage', 'Ada Lovelace'],
            'requestor_types': ['Individual'],
            'citations': [{'name': 'DNC', 'no': '2014-01'}, {'name': 'Outkast', 'no': '2015-05'}],
                'cited_by': [{'name': 'Church', 'no': '2007-05'}]}))
    def test_advisory_opinion_load(self):
        index_advisory_opinions()


class LoadAdvisoryOpinionsIntoS3Test(unittest.TestCase):
    @patch('webservices.legal_docs.load_legal_docs.db', Db())
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
     get_bucket_mock([obj('legal/aos/2.pdf')], 'legal/aos/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential',
        lambda cred: cred + '123')
    def test_load_advisory_opinions_into_s3(self):
        load_advisory_opinions_into_s3()

    @patch('webservices.legal_docs.load_legal_docs.db', Db())
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
     get_bucket_mock([obj('legal/aos/1.pdf'), obj('legal/aos/2.pdf')],
     'legal/aos/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential',
        lambda cred: cred + '123')
    def test_load_advisory_opinions_into_s3_already_loaded(self):
        load_advisory_opinions_into_s3()

    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
     get_bucket_mock([obj('legal/aos/2.pdf')], 'legal/aos/1.pdf'))
    def test_delete_advisory_opinions_from_s3(self):
        delete_advisory_opinions_from_s3()

class InitializeLegalDocsTest(unittest.TestCase):
    @patch('webservices.utils.get_elasticsearch_connection',
    get_es_with_doc({}))
    def test_initialize_legal_docs(self):
        initialize_legal_docs()

def raise_pdf_exception(PDF):
    raise Exception('Could not parse PDF')

class LoadArchivedMursTest(unittest.TestCase):
    @patch('webservices.utils.get_elasticsearch_connection',
        get_es_with_doc(json.load(open('tests/data/archived_mur_doc.json'))))
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.slate.PDF', lambda t: ['page1', 'page2'])
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e: 'bucket123')
    @patch('webservices.legal_docs.load_legal_docs.requests.get',
        mock_archived_murs_get_request(open('tests/data/archived_mur_data.html').read()))
    def test_base_case(self):
        load_archived_murs()

    @patch('webservices.utils.get_elasticsearch_connection',
        get_es_with_doc(json.load(open('tests/data/archived_mur_empty_doc.json'))))
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.slate.PDF', lambda t: ['page1', 'page2'])
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e: 'bucket123')
    @patch('webservices.legal_docs.load_legal_docs.requests.get',
        mock_archived_murs_get_request(open('tests/data/archived_mur_empty_data.html').read()))
    def test_with_empty_data(self):
        load_archived_murs()

    @patch('webservices.utils.get_elasticsearch_connection',
        get_es_with_doc(json.load(open('tests/data/archived_mur_empty_doc.json'))))
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.slate.PDF', lambda t: ['page1', 'page2'])
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e: 'bucket123')
    @patch('webservices.legal_docs.load_legal_docs.requests.get',
        mock_archived_murs_get_request(open('tests/data/archived_mur_bad_subject.html').read()))
    def test_bad_parse(self):
        with self.assertRaises(Exception):
            load_archived_murs()

    @patch('webservices.utils.get_elasticsearch_connection',
        get_es_with_doc(json.load(open('tests/data/archived_mur_empty_doc.json'))))
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.slate.PDF', lambda t: ['page1', 'page2'])
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e: 'bucket123')
    @patch('webservices.legal_docs.load_legal_docs.requests.get',
        mock_archived_murs_get_request(open('tests/data/archived_mur_bad_citation.html').read()))
    def test_bad_citation(self):
        with self.assertRaises(Exception):
            load_archived_murs()

    @patch('webservices.utils.get_elasticsearch_connection',
        get_es_with_doc(json.load(open('tests/data/archived_mur_bad_pdf_doc.json'))))
    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    @patch('webservices.legal_docs.load_legal_docs.env.get_credential', lambda e: 'bucket123')
    @patch('webservices.legal_docs.load_legal_docs.requests.get',
        mock_archived_murs_get_request(open('tests/data/archived_mur_data.html').read()))
    @patch('webservices.legal_docs.load_legal_docs.slate.PDF', raise_pdf_exception)
    def test_with_bad_pdf(self):
        load_archived_murs()

    @patch('webservices.legal_docs.load_legal_docs.get_bucket',
        get_bucket_mock([obj('legal/murs/2.pdf')], 'legal/murs/1.pdf'))
    def test_delete_murs_from_s3(self):
        delete_murs_from_s3()

    @patch('webservices.utils.get_elasticsearch_connection', get_es_with_doc({}))
    def test_delete_murs_from_es(self):
        delete_murs_from_es()
