-- Creates the partition of schedule B data,
DROP TABLE IF EXISTS ofec_sched_b_master_tmp CASCADE;

CREATE TABLE ofec_sched_b_master_tmp (
    cmte_id                       VARCHAR(9),
    recipient_cmte_id             VARCHAR(9),
    recipient_nm                  VARCHAR(200),
    payee_l_nm                    VARCHAR(30),
    payee_f_nm                    VARCHAR(20),
    payee_m_nm                    VARCHAR(20),
    payee_prefix                  VARCHAR(10),
    payee_suffix                  VARCHAR(10),
    payee_employer                VARCHAR(38),
    payee_occupation              VARCHAR(38),
    recipient_st1                 VARCHAR(34),
    recipient_st2                 VARCHAR(34),
    recipient_city                VARCHAR(30),
    recipient_st                  VARCHAR(2),
    recipient_zip                 VARCHAR(9),
    disb_desc                     VARCHAR(100),
    catg_cd                       VARCHAR(3),
    catg_cd_desc                  VARCHAR(40),
    entity_tp                     VARCHAR(3),
    entity_tp_desc                VARCHAR(50),
    election_tp                   VARCHAR(5),
    fec_election_tp_desc          VARCHAR(20),
    fec_election_tp_year          VARCHAR(4),
    election_tp_desc              VARCHAR(20),
    cand_id                       VARCHAR(9),
    cand_nm                       VARCHAR(90),
    cand_nm_first                 VARCHAR(38),
    cand_nm_last                  VARCHAR(38),
    cand_m_nm                     VARCHAR(20),
    cand_prefix                   VARCHAR(10),
    cand_suffix                   VARCHAR(10),
    cand_office                   VARCHAR(1),
    cand_office_desc              VARCHAR(20),
    cand_office_st                VARCHAR(2),
    cand_office_st_desc           VARCHAR(20),
    cand_office_district          VARCHAR(2),
    disb_dt                       TIMESTAMP,
    disb_amt                      NUMERIC(14,2),
    memo_cd                       VARCHAR(1),
    memo_cd_desc                  VARCHAR(50),
    memo_text                     VARCHAR(100),
    disb_tp                       VARCHAR(3),
    disb_tp_desc                  VARCHAR(90),
    conduit_cmte_nm               VARCHAR(200),
    conduit_cmte_st1              VARCHAR(34),
    conduit_cmte_st2              VARCHAR(34),
    conduit_cmte_city             VARCHAR(30),
    conduit_cmte_st               VARCHAR(2),
    conduit_cmte_zip              VARCHAR(9),
    national_cmte_nonfed_acct     VARCHAR(9),
    ref_disp_excess_flg           VARCHAR(1),
    comm_dt                       TIMESTAMP,
    benef_cmte_nm                 VARCHAR(200),
    semi_an_bundled_refund        NUMERIC(14,2),
    action_cd                     VARCHAR(1),
    action_cd_desc                VARCHAR(15),
    tran_id                       TEXT,
    back_ref_tran_id              TEXT,
    back_ref_sched_id             TEXT,
    schedule_type                 VARCHAR(2),
    schedule_type_desc            VARCHAR(90),
    line_num                      VARCHAR(12),
    image_num                     VARCHAR(18),
    file_num                      NUMERIC(7,0),
    link_id                       NUMERIC(19,0),
    orig_sub_id                   NUMERIC(19,0),
    sub_id                        NUMERIC(19,0) NOT NULL,
    filing_form                   VARCHAR(8) NOT NULL,
    rpt_tp                        VARCHAR(3),
    rpt_yr                        NUMERIC(4,0),
    election_cycle                NUMERIC(4,0),
    timestamp                     TIMESTAMP,
    pg_date                       TIMESTAMP,
    pdf_url                       TEXT,
    recipient_name_text           TSVECTOR,
    disbursement_description_text TSVECTOR,
    disbursement_purpose_category TEXT,
    clean_recipient_cmte_id       VARCHAR(9),
    two_year_transaction_period   SMALLINT,
    line_number_label             TEXT
);

-- Create the child tables.
SELECT create_itemized_schedule_partition('b', :PARTITION_START_YEAR, :PARTITION_END_YEAR);

-- Create the insert trigger so that records go into the proper child table.
DROP TRIGGER IF EXISTS insert_sched_b_trigger_tmp ON ofec_sched_b_master_tmp;
CREATE trigger insert_sched_b_trigger_tmp BEFORE INSERT ON ofec_sched_b_master_tmp FOR EACH ROW EXECUTE PROCEDURE insert_sched_master(:PARTITION_START_YEAR);

---- Insert the records from the view
INSERT INTO ofec_sched_b_master_tmp (
    cmte_id,
    recipient_cmte_id,
    recipient_nm,
    payee_l_nm,
    payee_f_nm,
    payee_m_nm,
    payee_prefix,
    payee_suffix,
    payee_employer,
    payee_occupation,
    recipient_st1,
    recipient_st2,
    recipient_city,
    recipient_st,
    recipient_zip,
    disb_desc,
    catg_cd,
    catg_cd_desc,
    entity_tp,
    entity_tp_desc,
    election_tp,
    fec_election_tp_desc,
    fec_election_tp_year,
    election_tp_desc,
    cand_id,
    cand_nm,
    cand_nm_first,
    cand_nm_last,
    cand_m_nm,
    cand_prefix,
    cand_suffix,
    cand_office,
    cand_office_desc,
    cand_office_st,
    cand_office_st_desc,
    cand_office_district,
    disb_dt,
    disb_amt,
    memo_cd,
    memo_cd_desc,
    memo_text,
    disb_tp,
    disb_tp_desc,
    conduit_cmte_nm,
    conduit_cmte_st1,
    conduit_cmte_st2,
    conduit_cmte_city,
    conduit_cmte_st,
    conduit_cmte_zip,
    national_cmte_nonfed_acct,
    ref_disp_excess_flg,
    comm_dt,
    benef_cmte_nm,
    semi_an_bundled_refund,
    action_cd,
    action_cd_desc,
    tran_id,
    back_ref_tran_id,
    back_ref_sched_id,
    schedule_type,
    schedule_type_desc,
    line_num,
    image_num,
    file_num,
    link_id,
    orig_sub_id,
    sub_id,
    filing_form,
    rpt_tp,
    rpt_yr,
    election_cycle,
    timestamp,
    pg_date,
    pdf_url,
    recipient_name_text,
    disbursement_description_text,
    disbursement_purpose_category,
    clean_recipient_cmte_id,
    two_year_transaction_period,
    line_number_label
)
SELECT
    cmte_id,
    recipient_cmte_id,
    recipient_nm,
    payee_l_nm,
    payee_f_nm,
    payee_m_nm,
    payee_prefix,
    payee_suffix,
    payee_employer,
    payee_occupation,
    recipient_st1,
    recipient_st2,
    recipient_city,
    recipient_st,
    recipient_zip,
    disb_desc,
    catg_cd,
    catg_cd_desc,
    entity_tp,
    entity_tp_desc,
    election_tp,
    fec_election_tp_desc,
    fec_election_tp_year,
    election_tp_desc,
    cand_id,
    cand_nm,
    cand_nm_first,
    cand_nm_last,
    cand_m_nm,
    cand_prefix,
    cand_suffix,
    cand_office,
    cand_office_desc,
    cand_office_st,
    cand_office_st_desc,
    cand_office_district,
    disb_dt,
    disb_amt,
    memo_cd,
    memo_cd_desc,
    memo_text,
    disb_tp,
    disb_tp_desc,
    conduit_cmte_nm,
    conduit_cmte_st1,
    conduit_cmte_st2,
    conduit_cmte_city,
    conduit_cmte_st,
    conduit_cmte_zip,
    national_cmte_nonfed_acct,
    ref_disp_excess_flg,
    comm_dt,
    benef_cmte_nm,
    semi_an_bundled_refund,
    action_cd,
    action_cd_desc,
    tran_id,
    back_ref_tran_id,
    back_ref_sched_id,
    schedule_type,
    schedule_type_desc,
    line_num,
    image_num,
    file_num,
    link_id,
    orig_sub_id,
    sub_id,
    filing_form,
    rpt_tp,
    rpt_yr,
    election_cycle,
    CURRENT_TIMESTAMP as timestamp,
    CURRENT_TIMESTAMP as pg_date,
    image_pdf_url(image_num) AS pdf_url,
    to_tsvector(concat(recipient_nm, ' ', recipient_cmte_id)) AS recipient_name_text,
    to_tsvector(disb_desc) AS disbursement_description_text,
    disbursement_purpose(disb_tp, disb_desc) AS disbursement_purpose_category,
    clean_repeated(recipient_cmte_id, cmte_id) AS clean_recipient_cmte_id,
    get_cycle(rpt_yr) AS two_year_transaction_period,
    expand_line_number(filing_form, line_num) AS line_number_label
FROM fec_fitem_sched_b_vw;

SELECT finalize_itemized_schedule_b_tables(:PARTITION_START_YEAR, :PARTITION_END_YEAR, TRUE);
SELECT rename_table_cascade('ofec_sched_b_master');
