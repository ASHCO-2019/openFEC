import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY
from .base import db, BaseModel
from webservices import docs
from sqlalchemy.ext.declarative import declared_attr

# categories endpoint
class AuditBase(object):
    __table_args__ = {"schema": "auditsearch"}

# audit-category endpoint
class CategoryRelation(AuditBase, db.Model):
    __tablename__ = 'finding_rel_vw'

    category_id = db.Column(db.Integer, index=True, primary_key=True)
    sub_category_id = db.Column(db.Integer, index=True, primary_key=True)
    sub_category_name = db.Column(db.String, index=True, primary_key=True)

# audit-category endpoint
class Category(AuditBase, db.Model):
    __tablename__ = 'finding_vw'

    # category_id = db.Column('finding_pk', db.Integer, index=True, primary_key=True)
    # category_name = db.Column('finding', db.String, doc=docs.CATEGORY)
    category_id = db.Column(db.Integer, index=True, primary_key=True)
    category_name = db.Column(db.String, doc=docs.CATEGORY)
    tier = db.Column(db.Integer, doc=docs.CATEGORY)

    @declared_attr
    def sub_category(self):
        return sa.orm.relationship(
            CategoryRelation,
            primaryjoin=sa.orm.foreign(CategoryRelation.category_id) == self.category_id,
            # primaryjoin=sa.orm.foreign('auditsearch.finding_rel_jl_vw.category_id') == self.category_id,
            uselist=True,
        )

# audit-case endpoint
class AuditCaseSubCategory(db.Model):
    __tablename__ = 'ofec_audit_case_sub_category_rel_mv'
    # add the correction description of each field in the docs.py
    audit_case_id = db.Column(db.String, primary_key=True, doc=docs.AUDIT_CASE_ID)
    category_id = db.Column(db.String, primary_key=True, doc=docs.CATEGORY_ID)
    sub_category_id = db.Column(db.String, primary_key=True, doc=docs.SUBCATEGORY)
    sub_category_name = db.Column(db.String, primary_key=True, doc=docs.SUBCATEGORY)

# audit-case endpoint
class AuditCategoryRelation(db.Model):
    __tablename__ = 'ofec_audit_case_category_rel_mv'
    # add the correction description of each field in the docs.py
    audit_case_id = db.Column(db.String, primary_key=True, doc=docs.AUDIT_CASE_ID)
    category_id = db.Column(db.String, primary_key=True, doc=docs.CATEGORY_ID)
    category_name = db.Column(db.String, primary_key=True, doc=docs.CATEGORY)
    sub_category = db.relationship(
        'AuditCaseSubCategory',
        primaryjoin='''and_(
            foreign(AuditCategoryRelation.audit_case_id) == AuditCaseSubCategory.audit_case_id,
            AuditCategoryRelation.category_id == AuditCaseSubCategory.category_id
        )''',
        uselist=True,
        lazy='joined'
    )
    
# audit-case endpoint
class AuditCase(db.Model):
    __tablename__ = 'ofec_audit_case_mv'

    # idx = db.Column(db.Integer)
    audit_case_id = db.Column(db.String, primary_key=True, doc=docs.AUDIT_CASE_ID)
    cycle = db.Column(db.Integer, doc=docs.CYCLE)
    committee_id = db.Column(db.String, doc=docs.COMMITTEE_ID)
    committee_name = db.Column(db.String, doc=docs.COMMITTEE_NAME)
    committee_designation = db.Column(db.String, doc=docs.DESIGNATION)
    committee_type = db.Column(db.String, doc=docs.COMMITTEE_TYPE)
    committee_description = db.Column(db.String, doc=docs.COMMITTEE_DESCRIPTION)
    far_release_date = db.Column(db.Date, doc=docs.RELEASE_DATE)
    link_to_report = db.Column(db.String, doc=docs.REPORT_LINK)
    audit_id = db.Column(db.Integer, doc=docs.AUDIT_ID)
    candidate_id = db.Column(db.String, doc=docs.CANDIDATE_ID)
    candidate_name = db.Column(db.String, doc=docs.CANDIDATE_NAME)
    primary_category = db.relationship(
        AuditCategoryRelation,
        primaryjoin='''and_(
            foreign(AuditCategoryRelation.audit_case_id) == AuditCase.audit_case_id,
        )''',
        uselist=True,
        lazy='joined'
    )
