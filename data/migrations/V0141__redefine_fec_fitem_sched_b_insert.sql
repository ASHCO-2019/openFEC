
/*
column election_cycle and two_year_transaction_period in public.ofec_sched_b_master tables has exactly the same data
So disclosure.fec_fitem_sched_b does not add the extra column two_year_transaction_period
However, since existing API referencing column two_year_transaction_period a lot, rename election_cycle to two_year_transaction_period
  to mitigate impact to API when switching from using public.ofec_sched_b_master tables to disclosure.fec_fitem_sched_b table

redefine *._text triggers to replace all non-word characters with ' ' for better search specificity.
*/

-- ----------------------------
-- ----------------------------
-- disclosure.fec_fitem_sched_b
-- ----------------------------
-- ----------------------------

DO $$
BEGIN
    EXECUTE format('alter table disclosure.fec_fitem_sched_b rename column election_cycle to two_year_transaction_period');
    EXCEPTION 
             WHEN undefined_column THEN 
                null;
             WHEN others THEN 
                RAISE NOTICE 'some other error: %, %',  sqlstate, sqlerrm;  
END$$;



/*
redefine tsvector specification for fec_fitem_sched_b_insert
*/

CREATE OR REPLACE FUNCTION disclosure.fec_fitem_sched_b_insert()
  RETURNS trigger AS
$BODY$
begin
	new.pdf_url := image_pdf_url(new.image_num);
	new.disbursement_description_text := to_tsvector(regexp_replace(new.disb_desc, '[^a-zA-Z0-9]', ' ', 'g'));
	new.recipient_name_text := to_tsvector(concat(regexp_replace(new.recipient_nm, '[^a-zA-Z0-9]', ' ', 'g'), ' ', new.clean_recipient_cmte_id));
	new.disbursement_purpose_category := disbursement_purpose(new.disb_tp, new.disb_desc);
	new.line_number_label := expand_line_number(new.filing_form, new.line_num);
  return new;
end
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION disclosure.fec_fitem_sched_b_insert()
  OWNER TO fec;

DROP TRIGGER IF EXISTS tri_fec_fitem_sched_b ON disclosure.fec_fitem_sched_b;

CREATE TRIGGER tri_fec_fitem_sched_b
  BEFORE INSERT
  ON disclosure.fec_fitem_sched_b
  FOR EACH ROW
  EXECUTE PROCEDURE disclosure.fec_fitem_sched_b_insert();


-- ----------------------------
-- ----------------------------
-- disclosure.fec_fitem_sched_f
-- ----------------------------
-- ----------------------------
DO $$
BEGIN
    EXECUTE format('ALTER TABLE disclosure.fec_fitem_sched_f ADD COLUMN payee_name_text tsvector');
    EXCEPTION 
             WHEN duplicate_column THEN 
                null;
             WHEN others THEN 
                RAISE NOTICE 'some other error: %, %',  sqlstate, sqlerrm;  
END$$;

CREATE OR REPLACE FUNCTION disclosure.fec_fitem_sched_f_insert()
  RETURNS trigger AS
$BODY$
begin
	new.payee_name_text := to_tsvector(regexp_replace(new.pye_nm::text, '[^a-zA-Z0-9]', ' ', 'g'));

    	return new;
end
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION disclosure.fec_fitem_sched_f_insert()
  OWNER TO fec;

DROP TRIGGER IF EXISTS tri_fec_fitem_sched_f ON disclosure.fec_fitem_sched_f;

CREATE TRIGGER tri_fec_fitem_sched_f
  BEFORE INSERT
  ON disclosure.fec_fitem_sched_f
  FOR EACH ROW
  EXECUTE PROCEDURE disclosure.fec_fitem_sched_f_insert();

/*

update to_tsvector to confirm to new search functionality (omit special characters, replace with whitespace, vectorize)
*/

CREATE OR REPLACE VIEW ofec_rad_analyst_vw AS
    SELECT row_number() OVER () AS idx,
        ra.cmte_id AS committee_id,
        cv.cmte_nm AS committee_name,
        an.anlyst_id AS analyst_id,
        (an.valid_id::numeric) AS analyst_short_id,
        CASE
            WHEN an.branch_id = 1 THEN 'Authorized'
            WHEN an.branch_id = 2 THEN 'Party/Non Party'
            ELSE NULL::text
        END AS rad_branch,
        an.firstname AS first_name,
        an.lastname AS last_name,
        to_tsvector(((regexp_replace(an.firstname, '[^a-zA-Z0-9]', ' ', 'g')::text || ' '::text) || regexp_replace(an.lastname, '[^a-zA-Z0-9]', ' ', 'g')::text)) AS name_txt,
        an.telephone_ext,
        t.anlyst_title_desc AS analyst_title,
        an.email AS analyst_email,
        ra.last_rp_change_dt AS assignment_update_date
    FROM rad_pri_user.rad_anlyst an
    JOIN rad_pri_user.rad_assgn ra
        ON an.anlyst_id = ra.anlyst_id
    JOIN disclosure.cmte_valid_fec_yr cv
        ON ra.cmte_id = cv.cmte_id
    JOIN rad_pri_user.rad_lkp_anlyst_title t
        ON an.anlyst_title_seq = t.anlyst_title_seq
    WHERE an.status_id = 1
        AND an.anlyst_id <> 999
        AND cv.fec_election_yr = get_cycle(date_part('year', current_date)::integer);

ALTER TABLE ofec_rad_analyst_vw OWNER TO fec;
GRANT SELECT ON TABLE ofec_rad_analyst_vw TO fec_read;
GRANT SELECT ON TABLE ofec_rad_analyst_vw TO openfec_read;


/*
update to_tsvector definition for ofec_commite_fulltext_audit_mv
    a) `create or replace ofec_committee_fulltext_audit_mvw` to use new `MV` logic
    b) drop old `MV`
    c) recreate `MV` with new logic
    d) `create or replace ofec_committee_fulltext_audit_mv` -> `select all` from new `MV`
*/


-- a) `create or replace ofec_committee_fulltext_audit_mv` to use new `MV` logic

CREATE OR REPLACE VIEW ofec_committee_fulltext_audit_vw AS
WITH
cmte_info AS (
    SELECT DISTINCT dc.cmte_id,
        dc.cmte_nm,
        dc.fec_election_yr,
        dc.cmte_dsgn,
        dc.cmte_tp,
        b.FILED_CMTE_TP_DESC::text AS cmte_desc
    FROM auditsearch.audit_case aa, disclosure.cmte_valid_fec_yr dc, staging.ref_filed_cmte_tp b
    WHERE btrim(aa.cmte_id) = dc.cmte_id 
      AND aa.election_cycle = dc.fec_election_yr
      AND dc.cmte_tp IN ('H', 'S', 'P', 'X', 'Y', 'Z', 'N', 'Q', 'I', 'O', 'U', 'V', 'W')
      AND dc.cmte_tp = b.filed_cmte_tp_cd
)
SELECT DISTINCT ON (cmte_id, cmte_nm)
    row_number() over () AS idx,
    cmte_id AS id,
    cmte_nm AS name,
CASE
    WHEN cmte_nm IS NOT NULL THEN
        setweight(to_tsvector(regexp_replace(cmte_nm, '[^a-zA-Z0-9]', ' ', 'g')), 'A') ||
        setweight(to_tsvector(regexp_replace(cmte_id, '[^a-zA-Z0-9]', ' ', 'g')), 'B')
    ELSE NULL::tsvector
END AS fulltxt
FROM cmte_info 
ORDER BY cmte_id;


-- b) drop old mv
DROP MATERIALIZED VIEW ofec_committee_fulltext_audit_mv;


-- c) create new mv
CREATE MATERIALIZED VIEW ofec_committee_fulltext_audit_mv AS
WITH
cmte_info AS (
    SELECT DISTINCT dc.cmte_id,
        dc.cmte_nm,
        dc.fec_election_yr,
        dc.cmte_dsgn,
        dc.cmte_tp,
        b.FILED_CMTE_TP_DESC::text AS cmte_desc
    FROM auditsearch.audit_case aa, disclosure.cmte_valid_fec_yr dc, staging.ref_filed_cmte_tp b
    WHERE btrim(aa.cmte_id) = dc.cmte_id 
      AND aa.election_cycle = dc.fec_election_yr
      AND dc.cmte_tp IN ('H', 'S', 'P', 'X', 'Y', 'Z', 'N', 'Q', 'I', 'O', 'U', 'V', 'W')
      AND dc.cmte_tp = b.filed_cmte_tp_cd
)
SELECT DISTINCT ON (cmte_id, cmte_nm)
    row_number() over () AS idx,
    cmte_id AS id,
    cmte_nm AS name,
CASE
    WHEN cmte_nm IS NOT NULL THEN
        setweight(to_tsvector(regexp_replace(cmte_nm, '[^a-zA-Z0-9]', ' ', 'g')), 'A') ||
        setweight(to_tsvector(regexp_replace(cmte_id, '[^a-zA-Z0-9]', ' ', 'g')), 'B')
    ELSE NULL::tsvector
END AS fulltxt
FROM cmte_info 
ORDER BY cmte_id
WITH DATA;

ALTER TABLE ofec_committee_fulltext_audit_mv OWNER TO fec;

CREATE UNIQUE INDEX ON ofec_committee_fulltext_audit_mv(idx);
CREATE INDEX ON ofec_committee_fulltext_audit_mv using gin(fulltxt);

GRANT ALL ON TABLE public.ofec_committee_fulltext_audit_mv TO fec;
GRANT SELECT ON TABLE public.ofec_committee_fulltext_audit_mv TO fec_read;

-- d) `create or replace ofec_committee_fulltext_audit_vw` -> `select all` from new `MV`
CREATE OR REPLACE VIEW ofec_committee_fulltext_audit_vw AS SELECT * FROM ofec_committee_fulltext_audit_mv;
ALTER VIEW ofec_committee_fulltext_audit_vw OWNER TO fec;
GRANT SELECT ON ofec_committee_fulltext_audit_vw TO fec_read;


/*
update to_tsvector definition for fec_fitem_sched_a
*/
CREATE OR REPLACE FUNCTION disclosure.ju_fec_fitem_sched_a_insert()
    RETURNS trigger AS
$BODY$
begin
	new.pdf_url := image_pdf_url(new.image_num);
	new.contributor_name_text := to_tsvector(concat(regexp_replace(new.contbr_nm, '[^a-zA-Z0-9]', ' ', 'g'), ' ', regexp_replace(new.clean_contbr_id, '[^a-zA-Z0-9]', ' ', 'g')));
	new.contributor_employer_text := to_tsvector(regexp_replace(new.contbr_employer, '[^a-zA-Z0-9]', ' ', 'g'));
	new.contributor_occupation_text := to_tsvector(regexp_replace(new.contbr_occupation, '[^a-zA-Z0-9]', ' ', 'g'));
	new.is_individual := is_individual(new.contb_receipt_amt, new.receipt_tp, new.line_num, new.memo_cd, new.memo_text);
	new.line_number_label := expand_line_number(new.filing_form, new.line_num);

    return new;
end
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100;

ALTER FUNCTION disclosure.ju_fec_fitem_sched_a_insert()
OWNER TO fec;


/*
update to_tsvector definition for ofec_candidate_fulltext_audit_mv
*/

/*
update to_tsvector definition for ofec_candidate_fulltext_audit_mv
    a) `create or replace ofec_candidate_fulltext_audit_vw` to use new `MV` logic
    b) drop old `MV`
    c) recreate `MV` with new logic
    d) `create or replace ofec_candidate_fulltext_audit_mv` -> `select all` from new `MV`
*/
-- a) `create or replace ofec_candidate_fulltext_audit_vw` to use new `MV` logic
CREATE OR REPLACE VIEW ofec_candidate_fulltext_audit_vw AS
WITH
cand_info AS (
    SELECT DISTINCT dc.cand_id,
        dc.cand_name,
        "substring"(dc.cand_name::text, 1,
            CASE
                WHEN strpos(dc.cand_name::text, ','::text) > 0 THEN strpos(dc.cand_name::text, ','::text) - 1
                ELSE strpos(dc.cand_name::text, ','::text)
            END) AS last_name,
        "substring"(dc.cand_name::text, strpos(dc.cand_name::text, ','::text) + 1) AS first_name,
        dc.fec_election_yr
    FROM auditsearch.audit_case aa JOIN disclosure.cand_valid_fec_yr dc
    ON (btrim(aa.cand_id) = dc.cand_id AND aa.election_cycle = dc.fec_election_yr)
)
SELECT DISTINCT ON (cand_id, cand_name)
    row_number() over () AS idx,
    cand_id AS id,
    cand_name AS name,
CASE
    WHEN cand_name IS NOT NULL THEN
        setweight(to_tsvector(regexp_replace(cand_name, '[^a-zA-Z0-9]', ' ', 'g')), 'A') ||
        setweight(to_tsvector(regexp_replace(cand_id, '[^a-zA-Z0-9]', ' ', 'g')), 'B')
    ELSE NULL::tsvector
END AS fulltxt
FROM cand_info
ORDER BY cand_id;

--    b) drop old `MV`
DROP MATERIALIZED VIEW ofec_candidate_fulltext_audit_mv;

--    c) recreate `MV` with new logic
CREATE MATERIALIZED VIEW ofec_candidate_fulltext_audit_mv AS
WITH
cand_info AS (
    SELECT DISTINCT dc.cand_id,
        dc.cand_name,
        "substring"(dc.cand_name::text, 1,
            CASE
                WHEN strpos(dc.cand_name::text, ','::text) > 0 THEN strpos(dc.cand_name::text, ','::text) - 1
                ELSE strpos(dc.cand_name::text, ','::text)
            END) AS last_name,
        "substring"(dc.cand_name::text, strpos(dc.cand_name::text, ','::text) + 1) AS first_name,
        dc.fec_election_yr
    FROM auditsearch.audit_case aa JOIN disclosure.cand_valid_fec_yr dc
    ON (btrim(aa.cand_id) = dc.cand_id AND aa.election_cycle = dc.fec_election_yr)
)
SELECT DISTINCT ON (cand_id, cand_name)
    row_number() over () AS idx,
    cand_id AS id,
    cand_name AS name,
CASE
    WHEN cand_name IS NOT NULL THEN
        setweight(to_tsvector(regexp_replace(cand_name, '[^a-zA-Z0-9]', ' ', 'g')), 'A') ||
        setweight(to_tsvector(regexp_replace(cand_id, '[^a-zA-Z0-9]', ' ', 'g')), 'B')
    ELSE NULL::tsvector
END AS fulltxt
FROM cand_info
ORDER BY cand_id
WITH DATA;

ALTER TABLE ofec_candidate_fulltext_audit_mv OWNER TO fec;

CREATE UNIQUE INDEX ON ofec_candidate_fulltext_audit_mv(idx);
CREATE INDEX ON ofec_candidate_fulltext_audit_mv using gin(fulltxt);


GRANT ALL ON TABLE ofec_candidate_fulltext_audit_mv TO fec;
GRANT SELECT ON TABLE ofec_candidate_fulltext_audit_mv TO fec_read;

-- d) `create or replace ofec_candidate_fulltext_audit_vw` -> `select all` from new `MV`
CREATE OR REPLACE VIEW ofec_candidate_fulltext_audit_vw AS SELECT * FROM ofec_candidate_fulltext_audit_mv;
ALTER VIEW ofec_candidate_fulltext_audit_vw OWNER TO fec;
GRANT SELECT ON ofec_candidate_fulltext_audit_vw TO fec_read;


/*
update to_tsvector for fec_fitem_sched_c
*/

DO $$
BEGIN
    EXECUTE format('ALTER TABLE disclosure.fec_fitem_sched_c ADD COLUMN candidate_name_text tsvector');
    EXECUTE format('ALTER TABLE disclosure.fec_fitem_sched_c ADD COLUMN loan_source_name_text tsvector');
    EXCEPTION 
             WHEN duplicate_column THEN 
                null;
             WHEN others THEN 
                RAISE NOTICE 'some other error: %, %',  sqlstate, sqlerrm;  
END$$;


CREATE OR REPLACE FUNCTION disclosure.fec_fitem_sched_c_insert()
  RETURNS trigger AS
$BODY$
begin
	new.candidate_name_text := to_tsvector(regexp_replace(new.cand_nm::text, '[^a-zA-Z0-9]', ' ', 'g'));
	new.loan_source_name_text := to_tsvector(regexp_replace(new.loan_src_nm::text, '[^a-zA-Z0-9]', ' ', 'g'));

    	return new;
end
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION disclosure.fec_fitem_sched_c_insert()
  OWNER TO fec;

DROP TRIGGER IF EXISTS tri_fec_fitem_sched_c ON disclosure.fec_fitem_sched_c;

CREATE TRIGGER tri_fec_fitem_sched_c
  BEFORE INSERT
  ON disclosure.fec_fitem_sched_c
  FOR EACH ROW
  EXECUTE PROCEDURE disclosure.fec_fitem_sched_c_insert();



/*
update to_tsvector definition for ofec_committee_fulltext_mv
    a) `create or replace ofec_committee_fulltext_vw` to use new `MV` logic
    b) drop old `MV`
    c) recreate `MV` with new logic
    d) `create or replace ofec_candidate_fulltext_audit_mv` -> `select all` from new `MV`
*/
-- a) `create or replace ofec_committee_fulltext_vw` to use new `MV` logic
CREATE OR REPLACE VIEW public.ofec_committee_fulltext_vw AS
 WITH pacronyms AS (
         SELECT ofec_pacronyms."ID NUMBER" AS committee_id,
            string_agg(ofec_pacronyms."PACRONYM", ' '::text) AS pacronyms
           FROM public.ofec_pacronyms
          GROUP BY ofec_pacronyms."ID NUMBER"
        ), totals AS (
         SELECT ofec_totals_combined_vw.committee_id,
            sum(ofec_totals_combined_vw.receipts) AS receipts,
            sum(ofec_totals_combined_vw.disbursements) AS disbursements,
            sum(ofec_totals_combined_vw.independent_expenditures) AS independent_expenditures
           FROM public.ofec_totals_combined_vw
          GROUP BY ofec_totals_combined_vw.committee_id
        )
 SELECT DISTINCT ON (committee_id) row_number() OVER () AS idx,
    committee_id AS id,
    cd.name,
        CASE
            WHEN (cd.name IS NOT NULL) THEN ((setweight(to_tsvector(regexp_replace((cd.name)::text, '[^a-zA-Z0-9]', ' ', 'g')), 'A'::"char") || setweight(to_tsvector(COALESCE(regexp_replace(pac.pacronyms, '[^a-zA-Z0-9]', ' ', 'g'), ''::text)), 'A'::"char")) || setweight(to_tsvector(regexp_replace((committee_id)::text, '[^a-zA-Z0-9]', ' ', 'g')), 'B'::"char"))
            ELSE NULL::tsvector
        END AS fulltxt,
    COALESCE(totals.receipts, (0)::numeric) AS receipts,
    COALESCE(totals.disbursements, (0)::numeric) AS disbursements,
    COALESCE(totals.independent_expenditures, (0)::numeric) AS independent_expenditures,
    ((COALESCE(totals.receipts, (0)::numeric) + COALESCE(totals.disbursements, (0)::numeric)) + COALESCE(totals.independent_expenditures, (0)::numeric)) AS total_activity
   FROM ((public.ofec_committee_detail_vw cd
     LEFT JOIN pacronyms pac USING (committee_id))
     LEFT JOIN totals USING (committee_id));

-- b) drop old MV
DROP MATERIALIZED VIEW ofec_committee_fulltext_mv;

-- c) recreate `MV` with new logic
CREATE MATERIALIZED VIEW public.ofec_committee_fulltext_mv AS
 WITH pacronyms AS (
         SELECT ofec_pacronyms."ID NUMBER" AS committee_id,
            string_agg(ofec_pacronyms."PACRONYM", ' '::text) AS pacronyms
           FROM public.ofec_pacronyms
          GROUP BY ofec_pacronyms."ID NUMBER"
        ), totals AS (
         SELECT ofec_totals_combined_vw.committee_id,
            sum(ofec_totals_combined_vw.receipts) AS receipts,
            sum(ofec_totals_combined_vw.disbursements) AS disbursements,
            sum(ofec_totals_combined_vw.independent_expenditures) AS independent_expenditures
           FROM public.ofec_totals_combined_vw
          GROUP BY ofec_totals_combined_vw.committee_id
        )
 SELECT DISTINCT ON (committee_id) row_number() OVER () AS idx,
    committee_id AS id,
    cd.name,
        CASE
            WHEN (cd.name IS NOT NULL) THEN ((setweight(to_tsvector(regexp_replace((cd.name)::text, '[^a-zA-Z0-9]', ' ', 'g')), 'A'::"char") || setweight(to_tsvector(COALESCE(regexp_replace(pac.pacronyms, '[^a-zA-Z0-9]', ' ', 'g'), ''::text)), 'A'::"char")) || setweight(to_tsvector(regexp_replace((committee_id)::text, '[^a-zA-Z0-9]', ' ', 'g')), 'B'::"char"))
            ELSE NULL::tsvector
        END AS fulltxt,
    COALESCE(totals.receipts, (0)::numeric) AS receipts,
    COALESCE(totals.disbursements, (0)::numeric) AS disbursements,
    COALESCE(totals.independent_expenditures, (0)::numeric) AS independent_expenditures,
    ((COALESCE(totals.receipts, (0)::numeric) + COALESCE(totals.disbursements, (0)::numeric)) + COALESCE(totals.independent_expenditures, (0)::numeric)) AS total_activity
   FROM ((public.ofec_committee_detail_vw cd
     LEFT JOIN pacronyms pac USING (committee_id))
     LEFT JOIN totals USING (committee_id))
  WITH DATA;

ALTER TABLE public.ofec_committee_fulltext_mv OWNER TO fec;

CREATE INDEX ofec_committee_fulltext_mv_disbursements_idx1 ON public.ofec_committee_fulltext_mv USING btree (disbursements);
CREATE INDEX ofec_committee_fulltext_mv_fulltxt_idx1 ON public.ofec_committee_fulltext_mv USING gin (fulltxt);
CREATE UNIQUE INDEX ofec_committee_fulltext_mv_idx_idx1 ON public.ofec_committee_fulltext_mv USING btree (idx);
CREATE INDEX ofec_committee_fulltext_mv_independent_expenditures_idx1 ON public.ofec_committee_fulltext_mv USING btree (independent_expenditures);
CREATE INDEX ofec_committee_fulltext_mv_receipts_idx1 ON public.ofec_committee_fulltext_mv USING btree (receipts);
CREATE INDEX ofec_committee_fulltext_mv_total_activity_idx1 ON public.ofec_committee_fulltext_mv USING btree (total_activity);

GRANT ALL ON TABLE ofec_committee_fulltext_mv TO fec;
GRANT SELECT ON TABLE ofec_committee_fulltext_mv TO fec_read;

-- d) `create or replace ofec_committee_fulltext_mv` -> `select all` from new `MV`
CREATE OR REPLACE VIEW ofec_committee_fulltext_vw AS SELECT * FROM ofec_committee_fulltext_mv;
ALTER VIEW ofec_committee_fulltext_vw OWNER TO fec;
GRANT SELECT ON ofec_committee_fulltext_vw TO fec_read;
