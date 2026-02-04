--! Previous: sha1:8c35e35e041ce55fc4f1a16bca1553c0bbd269b2
--! Hash: sha1:ff475cf5b12d071a9159a8f565e024343ff5913d
--! Message: address #23

-- Enter migration here

------------------------------------------------------------------------------------
-- ISO 28258 Bridge Functions
------------------------------------------------------------------------------------
-- Creates materialized views for data export: observation, profile, layer
-- These views provide a simplified interface for querying soil data.
--
-- Features:
--   - Works with or without the spectral extension installed
--   - Idempotent - safe to run multiple times
--   - Project-agnostic - no hardcoded role names
--
-- Dependencies:
--   - pgcrypto extension (for hash-based code generation)
--   - ISO 28258 core schema tables
--   - Optional: spectral extension tables
--
-- After running this file, add GRANT statements to your project's permissions file.
-- See the PERMISSIONS section at the end of this file for the template.
------------------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------------------------------
-- Helper function: Check if spectral extension is installed
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_has_spectral_extension() CASCADE;
CREATE OR REPLACE FUNCTION core.bridge_has_spectral_extension()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_spectral_derived_specimen'
    );
END;
$$;

COMMENT ON FUNCTION core.bridge_has_spectral_extension() IS
'Returns TRUE if the spectral extension tables are installed, FALSE otherwise. Used by bridge functions to conditionally include spectral queries.';

------------------------------------------------------------------------------------
-- Helper function: Generate hash-based codes
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.generate_code(TEXT, INT) CASCADE;
CREATE OR REPLACE FUNCTION core.generate_code(input_text TEXT, length INT DEFAULT 4)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars TEXT := 'bcdfghjklmnpqrstvwxyz';  -- No vowels (21 consonants)
    hash_bytes BYTEA;
    result TEXT := '';
    byte_val INT;
BEGIN
    hash_bytes := public.digest(input_text, 'sha256'::text);
    FOR i IN 1..length LOOP
        byte_val := get_byte(hash_bytes, (i - 1) % 32);
        result := result || substr(chars, (byte_val % 21) + 1, 1);
    END LOOP;
    RETURN result;
END;
$$;

COMMENT ON FUNCTION core.generate_code(TEXT, INT) IS
'This function generates a hash-based code given a string. It is used by the bridge_process_observation() function to generate observation code.';


------------------------------------------------------------------------------------
-- Function: bridge_process_observation
-- Creates materialized view for observation metadata
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_process_observation(JSON, TEXT, DATE);
CREATE OR REPLACE FUNCTION core.bridge_process_observation(
    observation_list json DEFAULT NULL,
    observation_type text DEFAULT 'specimen',
    creation_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    query_text text;
    spectral_query text;
    date_text text;
    obid_list text[];
    collision_count int;
    sql_1 text;
    sql_2 text;
    has_spectral boolean;
BEGIN
    -- Validate observation type
    IF observation_type NOT IN ('specimen', 'element') THEN
        RAISE EXCEPTION 'Invalid observation type. Must be "specimen" or "element"';
    END IF;

    -- Handle element case
    IF observation_type = 'element' THEN
        RAISE NOTICE 'Element observation type not yet implemented';
        RETURN;
    END IF;

    -- Check if spectral extension is installed
    has_spectral := core.bridge_has_spectral_extension();
    IF has_spectral THEN
        RAISE NOTICE 'Spectral extension detected - including spectral derived observations';
    ELSE
        RAISE NOTICE 'Spectral extension not installed - using phys_chem observations only';
    END IF;

    IF observation_list IS NULL THEN
    ---------------observation view, case: all observations, code generated-------------------
        -- Base query for phys_chem observations
        query_text := '
        (
        SELECT
            core.generate_code(propp.uri || procp.uri || u.uri) as observation_code,
            ops.observation_phys_chem_specimen_id,
            ''phys_chem'' as observation_type,
            propp.label as property_label,
            propp.uri as property_uri,
            procp.label as procedure_label,
            procp.uri as procedure_uri,
            u.label as unit_label,
            u.uri as unit_uri,
            sp.project_id,
            p.name as project_name,
            count(DISTINCT l.plot_id) AS profile_count,
            count(DISTINCT l.specimen_id) AS layer_count
        FROM
            core.result_phys_chem_specimen rps
            INNER JOIN core.specimen l ON rps.specimen_id = l.specimen_id
            LEFT JOIN core.plot pl ON l.plot_id = pl.plot_id
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id
            LEFT JOIN core.observation_phys_chem_specimen ops ON rps.observation_phys_chem_specimen_id = ops.observation_phys_chem_specimen_id
            LEFT JOIN core.property_phys_chem propp ON ops.property_phys_chem_id = propp.property_phys_chem_id
            LEFT JOIN core.procedure_phys_chem procp ON ops.procedure_phys_chem_id = procp.procedure_phys_chem_id
            LEFT JOIN core.unit_of_measure u ON u.unit_of_measure_id = ops.unit_of_measure_id
        GROUP BY
            observation_code,
            ops.observation_phys_chem_specimen_id,
            propp.uri,
            propp.label,
            procp.uri,
            procp.label,
            u.uri,
            u.label,
            sp.project_id,
            p.name
        )';

        -- Conditionally add spectral query
        IF has_spectral THEN
            query_text := query_text || '
        UNION
        (
        SELECT
            core.generate_code(propp.uri || procp.uri || u.uri) || ''_spec'' as observation_code,
            ops.observation_phys_chem_specimen_id,
            ''spectral_derived'' as observation_type,
            propp.label as property_label,
            propp.uri as property_uri,
            procp.label as procedure_label,
            procp.uri as procedure_uri,
            u.label as unit_label,
            u.uri as unit_uri,
            sp.project_id,
            p.name as project_name,
            count(DISTINCT l.plot_id) AS profile_count,
            count(DISTINCT l.specimen_id) AS layer_count
        FROM
            core.result_spectral_derived_specimen rss
            INNER JOIN core.specimen l ON rss.specimen_id = l.specimen_id
            LEFT JOIN core.plot pl ON l.plot_id = pl.plot_id
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id
            LEFT JOIN core.observation_spectral_derived_specimen oss ON rss.observation_spectral_derived_specimen_id = oss.observation_spectral_derived_specimen_id
            LEFT JOIN core.observation_phys_chem_specimen ops ON oss.observation_phys_chem_specimen_id = ops.observation_phys_chem_specimen_id
            LEFT JOIN core.property_phys_chem propp ON ops.property_phys_chem_id = propp.property_phys_chem_id
            LEFT JOIN core.procedure_phys_chem procp ON ops.procedure_phys_chem_id = procp.procedure_phys_chem_id
            LEFT JOIN core.unit_of_measure u ON u.unit_of_measure_id = ops.unit_of_measure_id
        GROUP BY
            observation_code,
            ops.observation_phys_chem_specimen_id,
            propp.uri,
            propp.label,
            procp.uri,
            procp.label,
            u.uri,
            u.label,
            sp.project_id,
            p.name
        )';
        END IF;

    ELSE
    ----------------observation code defined----------------------------
        -------------validate observation list-----------------------
        SELECT array_agg(key) INTO obid_list
        FROM jsonb_object_keys(observation_list::jsonb) AS key;
        IF NOT (obid_list <@ ARRAY(
            SELECT observation_phys_chem_specimen_id::text
            FROM core.observation_phys_chem_specimen
        )) THEN
            RAISE EXCEPTION 'Invalid observation ids as input.';
        END IF;

        -- Base query for phys_chem observations
        query_text := format('
        (
        SELECT
            (%L::jsonb->>ops.observation_phys_chem_specimen_id::text) as observation_code,
            ops.observation_phys_chem_specimen_id,
            ''phys_chem'' as observation_type,
            propp.label as property_label,
            propp.uri as property_uri,
            procp.label as procedure_label,
            procp.uri as procedure_uri,
            u.label as unit_label,
            u.uri as unit_uri,
            sp.project_id,
            p.name as project_name,
            count(DISTINCT l.plot_id) AS profile_count,
            count(DISTINCT l.specimen_id) AS layer_count
        FROM
            core.result_phys_chem_specimen rps
            INNER JOIN core.specimen l ON rps.specimen_id = l.specimen_id
            LEFT JOIN core.plot pl ON l.plot_id = pl.plot_id
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id
            LEFT JOIN core.observation_phys_chem_specimen ops ON rps.observation_phys_chem_specimen_id = ops.observation_phys_chem_specimen_id
            LEFT JOIN core.property_phys_chem propp ON ops.property_phys_chem_id = propp.property_phys_chem_id
            LEFT JOIN core.procedure_phys_chem procp ON ops.procedure_phys_chem_id = procp.procedure_phys_chem_id
            LEFT JOIN core.unit_of_measure u ON u.unit_of_measure_id = ops.unit_of_measure_id
        WHERE ops.observation_phys_chem_specimen_id::text = ANY(%L)
        GROUP BY
            ops.observation_phys_chem_specimen_id,
            observation_code,
            propp.uri,
            propp.label,
            procp.uri,
            procp.label,
            u.uri,
            u.label,
            sp.project_id,
            p.name
        )', observation_list, obid_list);

        -- Conditionally add spectral query
        IF has_spectral THEN
            query_text := query_text || format('
        UNION
        (
        SELECT
            (%L::jsonb->>ops.observation_phys_chem_specimen_id::text) || ''_spec'' as observation_code,
            ops.observation_phys_chem_specimen_id,
            ''spectral_derived'' as observation_type,
            propp.label as property_label,
            propp.uri as property_uri,
            procp.label as procedure_label,
            procp.uri as procedure_uri,
            u.label as unit_label,
            u.uri as unit_uri,
            sp.project_id,
            p.name as project_name,
            count(DISTINCT l.plot_id) AS profile_count,
            count(DISTINCT l.specimen_id) AS layer_count
        FROM
            core.result_spectral_derived_specimen rss
            INNER JOIN core.specimen l ON rss.specimen_id = l.specimen_id
            LEFT JOIN core.plot pl ON l.plot_id = pl.plot_id
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id
            LEFT JOIN core.observation_spectral_derived_specimen oss ON rss.observation_spectral_derived_specimen_id = oss.observation_spectral_derived_specimen_id
            LEFT JOIN core.observation_phys_chem_specimen ops ON oss.observation_phys_chem_specimen_id = ops.observation_phys_chem_specimen_id
            LEFT JOIN core.property_phys_chem propp ON ops.property_phys_chem_id = propp.property_phys_chem_id
            LEFT JOIN core.procedure_phys_chem procp ON ops.procedure_phys_chem_id = procp.procedure_phys_chem_id
            LEFT JOIN core.unit_of_measure u ON u.unit_of_measure_id = ops.unit_of_measure_id
        WHERE ops.observation_phys_chem_specimen_id::text = ANY(%L)
        GROUP BY
            ops.observation_phys_chem_specimen_id,
            observation_code,
            propp.uri,
            propp.label,
            procp.uri,
            procp.label,
            u.uri,
            u.label,
            sp.project_id,
            p.name
        )', observation_list, obid_list);
        END IF;

    END IF;

    --------------create materialized view-------------------------------
    IF creation_date IS NULL THEN
        date_text := 'snapshot';
    ELSE
        date_text := replace(creation_date::text, '-', '_');
    END IF;

    sql_1 := format
    ('DROP MATERIALIZED VIEW IF EXISTS core.vw_observation_%s CASCADE;
    CREATE MATERIALIZED VIEW core.vw_observation_%s AS ', date_text, date_text);

    sql_2 := format(
    'WITH NO DATA; COMMENT ON MATERIALIZED VIEW core.vw_observation_%s
    IS ''Observation metadata for numeric results. Column observation_type indicates the source: phys_chem (from result_phys_chem_specimen) or spectral_derived (from result_spectral_derived_specimen, if spectral extension installed).'';
    REFRESH MATERIALIZED VIEW core.vw_observation_%s WITH DATA;', date_text, date_text
    );

    -- RAISE NOTICE '%', query_text;

    EXECUTE(sql_1 || query_text || sql_2);

    -- Grant read-only access to PUBLIC (these are export views, safe for all authenticated users)
    EXECUTE format('GRANT SELECT ON core.vw_observation_%s TO PUBLIC', date_text);

    -------------collision check----------------------------------------
    -- Check for hash collisions within the same project
    -- Same observation_code in different projects is expected (same observation, different project)
    -- But same observation_code + project_id for different observations is a collision
    EXECUTE format('
    SELECT COUNT(*)
    FROM (
        SELECT observation_code, project_id
        FROM core.vw_observation_%s
        GROUP BY observation_code, project_id
        HAVING COUNT(*) > 1
    ) duplicates', date_text) INTO collision_count;

    IF collision_count > 0 THEN
        RAISE EXCEPTION 'Hash code collision detected. % duplicate codes found within the same project.', collision_count;
    END IF;

    RAISE NOTICE 'Materialized view core.vw_observation_% created successfully', date_text;


END;
$$;

COMMENT ON FUNCTION core.bridge_process_observation(JSON, TEXT, DATE) IS
'Creates a materialized view for observation metadata.
Works with or without the spectral extension installed.
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Example: SELECT core.bridge_process_observation(''{\"3\": \"ca\", \"5\": \"mn\"}'', ''specimen'', ''2026-01-06'')';

------------------------------------------------------------------------------------
-- Function: bridge_process_profile
-- Creates materialized view for profile/plot data with plot-level observations
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_process_profile(json, text, date);

CREATE OR REPLACE FUNCTION core.bridge_process_profile(
    observation_list json DEFAULT NULL,
    observation_type text DEFAULT 'specimen',
    creation_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    sql_1 text;
    sql_2 text;
    query_text text;
    date_text text;
    obid_list text[];
    obid_db_list text[];
    has_spectral boolean;
    has_plot_phys_chem boolean;
    has_text_extension boolean;
    desc_pivot_columns text;
    numeric_pivot_columns text;
    text_pivot_columns text;
    all_pivot_columns text;
    join_clauses text;
    group_by_clause text;
BEGIN
    IF observation_type NOT IN ('specimen', 'element') THEN
        RAISE EXCEPTION 'Invalid observation type. Must be "specimen" or "element"';
    END IF;

    -- Check if spectral extension is installed
    has_spectral := core.bridge_has_spectral_extension();

    -- Check if plot phys_chem extension is installed
    has_plot_phys_chem := core.bridge_has_plot_phys_chem();

    -- Check if text extension is installed
    has_text_extension := core.bridge_has_text_extension();

    IF creation_date IS NULL THEN
        date_text := 'snapshot';
    ELSE
        date_text := replace(creation_date::text, '-', '_');
    END IF;

    -- Build pivot columns for descriptive plot observations (only for properties with results)
    SELECT string_agg(
        format('MAX(CASE WHEN rdp.property_desc_plot_id = %s THEN tdp.label END) AS %I',
            pdp.property_desc_plot_id,
            pdp.label
        ),
        ', ' || E'\n        '
    )
    INTO desc_pivot_columns
    FROM core.property_desc_plot pdp
    WHERE EXISTS (
        SELECT 1 FROM core.result_desc_plot r
        WHERE r.property_desc_plot_id = pdp.property_desc_plot_id
    );

    -- Build pivot columns for numeric plot observations (only for observations with results)
    IF has_plot_phys_chem THEN
        EXECUTE '
            SELECT string_agg(
                format(''MAX(CASE WHEN rpc.observation_phys_chem_plot_id = %s THEN rpc.value END) AS %I'',
                    opc.observation_phys_chem_plot_id,
                    ppc.label
                ),
                '', '' || E''\n        ''
            )
            FROM core.observation_phys_chem_plot opc
            INNER JOIN core.property_phys_chem ppc ON opc.property_phys_chem_id = ppc.property_phys_chem_id
            WHERE EXISTS (
                SELECT 1 FROM core.result_phys_chem_plot r
                WHERE r.observation_phys_chem_plot_id = opc.observation_phys_chem_plot_id
            )'
        INTO numeric_pivot_columns;
    END IF;

    -- Build pivot columns for text plot observations (only for observations with results)
    IF has_text_extension THEN
        EXECUTE '
            SELECT string_agg(
                format(''MAX(CASE WHEN rtp.observation_text_plot_id = %s THEN rtp.value END) AS %I'',
                    otp.observation_text_plot_id,
                    pt.label
                ),
                '', '' || E''\n        ''
            )
            FROM core.observation_text_plot otp
            INNER JOIN core.property_text pt ON otp.property_text_id = pt.property_text_id
            WHERE EXISTS (
                SELECT 1 FROM core.result_text_plot r
                WHERE r.observation_text_plot_id = otp.observation_text_plot_id
            )'
        INTO text_pivot_columns;
    END IF;

    -- Combine all pivot columns
    all_pivot_columns := NULL;
    IF desc_pivot_columns IS NOT NULL THEN
        all_pivot_columns := desc_pivot_columns;
    END IF;
    IF numeric_pivot_columns IS NOT NULL THEN
        IF all_pivot_columns IS NOT NULL THEN
            all_pivot_columns := all_pivot_columns || ',' || E'\n        ' || numeric_pivot_columns;
        ELSE
            all_pivot_columns := numeric_pivot_columns;
        END IF;
    END IF;
    IF text_pivot_columns IS NOT NULL THEN
        IF all_pivot_columns IS NOT NULL THEN
            all_pivot_columns := all_pivot_columns || ',' || E'\n        ' || text_pivot_columns;
        ELSE
            all_pivot_columns := text_pivot_columns;
        END IF;
    END IF;

    -- Build join clauses
    join_clauses := '
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id';

    IF desc_pivot_columns IS NOT NULL THEN
        join_clauses := join_clauses || '
            LEFT JOIN core.result_desc_plot rdp ON pl.plot_id = rdp.plot_id
            LEFT JOIN core.thesaurus_desc_plot tdp ON rdp.thesaurus_desc_plot_id = tdp.thesaurus_desc_plot_id';
    END IF;

    IF numeric_pivot_columns IS NOT NULL THEN
        join_clauses := join_clauses || '
            LEFT JOIN core.result_phys_chem_plot rpc ON pl.plot_id = rpc.plot_id';
    END IF;

    IF text_pivot_columns IS NOT NULL THEN
        join_clauses := join_clauses || '
            LEFT JOIN core.result_text_plot rtp ON pl.plot_id = rtp.plot_id';
    END IF;

    -- Build GROUP BY clause
    group_by_clause := 'pl.site_id, pl.plot_id, pl.plot_code, sp.project_id, p.name, pl.position, pl.positional_accuracy';

    IF observation_list IS NULL THEN
        -- All plots query
        IF all_pivot_columns IS NOT NULL THEN
            query_text := format('
            SELECT
                pl.site_id,
                pl.plot_id,
                pl.plot_code,
                sp.project_id,
                p.name as project_name,
                pl.position::geometry as geometry,
                ST_Y(pl.position::geometry) AS lat,
                ST_X(pl.position::geometry) AS lon,
                pl.positional_accuracy,
                %s
            FROM core.plot pl%s
            GROUP BY %s',
                all_pivot_columns, join_clauses, group_by_clause);
        ELSE
            -- No plot observations found, use simple query
            query_text := 'SELECT pl.site_id, pl.plot_id, pl.plot_code, sp.project_id,
                p.name as project_name,
                pl.position::geometry as geometry,
                ST_Y(pl.position::geometry) AS lat,
                ST_X(pl.position::geometry) AS lon,
                pl.positional_accuracy
                FROM core.plot pl
                LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
                LEFT JOIN core.project p ON sp.project_id = p.project_id';
        END IF;
    ELSE
        SELECT array_agg(key) INTO obid_list
        FROM jsonb_object_keys(observation_list::jsonb) AS key;
        RAISE NOTICE 'observation id list: %', obid_list;

        ----------------validate the observation id--------------------------------------------
        IF observation_type = 'specimen' THEN
            SELECT ARRAY_AGG(observation_phys_chem_specimen_id::text) INTO obid_db_list
            FROM core.observation_phys_chem_specimen;
        ELSE
            SELECT ARRAY_AGG(observation_phys_chem_element_id::text) INTO obid_db_list
            FROM core.observation_phys_chem_element;
        END IF;
        IF NOT (obid_list <@ obid_db_list) THEN
            RAISE EXCEPTION 'invalid observation ids';
        END IF;

        -------------select plot having results of the specified observations----------------
        IF observation_type = 'specimen' THEN
            -- Build WHERE clause for filtered plots
            IF all_pivot_columns IS NOT NULL THEN
                query_text := format('
                SELECT
                    pl.site_id,
                    pl.plot_id,
                    pl.plot_code,
                    sp.project_id,
                    p.name as project_name,
                    pl.position::geometry as geometry,
                    ST_Y(pl.position::geometry) AS lat,
                    ST_X(pl.position::geometry) AS lon,
                    pl.positional_accuracy,
                    %s
                FROM core.plot pl%s
                WHERE pl.plot_id IN
                ((SELECT plot_id FROM core.specimen s
                INNER JOIN core.result_phys_chem_specimen r ON s.specimen_id = r.specimen_id
                WHERE r.observation_phys_chem_specimen_id::text = ANY(%L)
                )', all_pivot_columns, join_clauses, obid_list);
            ELSE
                query_text := format('SELECT pl.site_id, pl.plot_id, pl.plot_code, sp.project_id,
                    p.name as project_name,
                    pl.position::geometry as geometry,
                    ST_Y(pl.position::geometry) AS lat,
                    ST_X(pl.position::geometry) AS lon,
                    pl.positional_accuracy
                    FROM core.plot pl
                    LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
                    LEFT JOIN core.project p ON sp.project_id = p.project_id
                    WHERE pl.plot_id IN
                    ((SELECT plot_id FROM core.specimen s
                    INNER JOIN core.result_phys_chem_specimen r ON s.specimen_id = r.specimen_id
                    WHERE r.observation_phys_chem_specimen_id::text = ANY(%L)
                    )', obid_list);
            END IF;

            -- Conditionally add spectral query
            IF has_spectral THEN
                query_text := query_text || format('
                UNION
                (SELECT plot_id FROM core.specimen s
                INNER JOIN core.result_spectral_derived_specimen rs ON s.specimen_id = rs.specimen_id
                INNER JOIN core.observation_spectral_derived_specimen o
                    ON rs.observation_spectral_derived_specimen_id = o.observation_spectral_derived_specimen_id
                WHERE o.observation_phys_chem_specimen_id::text = ANY(%L))', obid_list);
            END IF;

            query_text := query_text || ')';

            -- Add GROUP BY for filtered query with pivot columns
            IF all_pivot_columns IS NOT NULL THEN
                query_text := query_text || format('
                GROUP BY %s', group_by_clause);
            END IF;
        ELSE
            ----------------case element: work on it later------------------------
            RAISE EXCEPTION 'no support for the element yet, quit the function';
        END IF;

    END IF;

    sql_1 := format(
        'DROP MATERIALIZED VIEW IF EXISTS core.vw_profile_%s CASCADE;
        CREATE MATERIALIZED VIEW core.vw_profile_%s AS ', date_text, date_text);

    sql_2 := format('
        WITH NO DATA; COMMENT ON MATERIALIZED VIEW core.vw_profile_%s
        IS ''Profile/plot data with coordinates and pivoted plot-level observations. Columns include: site_id, plot_id, plot_code, project_id, project_name, geometry, lat, lon, positional_accuracy. Dynamic columns are added for each observation type with results: descriptive observations from result_desc_plot (thesaurus labels), numeric observations from result_phys_chem_plot (if plot numeric extension installed), and text observations from result_text_plot (if text extension installed).'';
        REFRESH MATERIALIZED VIEW core.vw_profile_%s WITH DATA;
        ', date_text, date_text);

    EXECUTE(sql_1 || query_text || sql_2);

    -- Grant read-only access to PUBLIC (these are export views, safe for all authenticated users)
    EXECUTE format('GRANT SELECT ON core.vw_profile_%s TO PUBLIC', date_text);

    RAISE NOTICE 'Materialized view core.vw_profile_% created successfully', date_text;
END;
$$;

COMMENT ON FUNCTION core.bridge_process_profile(json, text, date) IS
'Creates a materialized view for profile/plot data including plot-level observations.
Includes pivoted columns for:
  - Descriptive observations (from result_desc_plot) as text values
  - Numeric observations (from result_phys_chem_plot) as numeric values
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Works with or without the spectral and plot phys_chem extensions installed.
Example: SELECT core.bridge_process_profile(null, ''specimen'', ''2026-01-06'')';


------------------------------------------------------------------------------------
-- Function: bridge_process_layer
-- Creates materialized view for layer/specimen data (pivoted observations)
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_process_layer(text, date);
CREATE OR REPLACE FUNCTION core.bridge_process_layer(
    observation_type text DEFAULT 'specimen',
    creation_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    query_text text;
    pivot_columns text;
    text_pivot_columns text;
    desc_pivot_columns text;
    all_pivot_columns text;
    date_text text;
    has_spectral boolean;
    has_text_extension boolean;
    has_specimen_desc_uri boolean;
BEGIN
    -- Validate observation type
    IF observation_type NOT IN ('specimen', 'element') THEN
        RAISE EXCEPTION 'Invalid observation type. Must be "specimen" or "element"';
    END IF;

    -- Handle element case
    IF observation_type = 'element' THEN
        RAISE NOTICE 'Element observation type not yet implemented';
        RETURN;
    END IF;

    -- Check if spectral extension is installed
    has_spectral := core.bridge_has_spectral_extension();

    -- Check if text extension is installed
    has_text_extension := core.bridge_has_text_extension();

    -- Check if specimen descriptive with URI is available
    has_specimen_desc_uri := core.bridge_has_specimen_desc_uri();

    IF creation_date IS NULL THEN
        date_text := 'snapshot';
    ELSE
        date_text := replace(creation_date::text, '-', '_');
    END IF;

    -- Build pivot columns dynamically from the observation view (for numeric results)
    EXECUTE format(
        'SELECT string_agg(
            format(''MAX(CASE WHEN combined_data.observation_code = %%L THEN combined_data.value END) AS %%I'',
                vo.observation_code,
                vo.observation_code
            ),
            '', '' || E''\n        ''
        )
        FROM core.vw_observation_%s vo',
        date_text
    ) INTO pivot_columns;

    -- Build pivot columns for text results (only for observations with results)
    IF has_text_extension THEN
        EXECUTE '
            SELECT string_agg(
                format(''MAX(CASE WHEN combined_data.observation_code = %L THEN combined_data.text_value END) AS %I'',
                    ''text_'' || pt.label,
                    ''text_'' || pt.label
                ),
                '', '' || E''\n        ''
            )
            FROM core.observation_text_specimen ots
            INNER JOIN core.property_text pt ON ots.property_text_id = pt.property_text_id
            WHERE EXISTS (
                SELECT 1 FROM core.result_text_specimen r
                WHERE r.observation_text_specimen_id = ots.observation_text_specimen_id
            )'
        INTO text_pivot_columns;
    END IF;

    -- Build pivot columns for descriptive results (only for observations with results)
    IF has_specimen_desc_uri THEN
        EXECUTE '
            SELECT string_agg(
                format(''MAX(CASE WHEN combined_data.observation_code = %L THEN combined_data.text_value END) AS %I'',
                    ''desc_'' || pds.label,
                    ''desc_'' || pds.label
                ),
                '', '' || E''\n        ''
            )
            FROM core.property_desc_specimen pds
            WHERE EXISTS (
                SELECT 1 FROM core.result_desc_specimen r
                WHERE r.property_desc_specimen_id = pds.property_desc_specimen_id
            )'
        INTO desc_pivot_columns;
    END IF;

    -- Combine pivot columns
    all_pivot_columns := NULL;
    IF pivot_columns IS NOT NULL THEN
        all_pivot_columns := pivot_columns;
    END IF;
    IF text_pivot_columns IS NOT NULL THEN
        IF all_pivot_columns IS NOT NULL THEN
            all_pivot_columns := all_pivot_columns || ',' || E'\n        ' || text_pivot_columns;
        ELSE
            all_pivot_columns := text_pivot_columns;
        END IF;
    END IF;
    IF desc_pivot_columns IS NOT NULL THEN
        IF all_pivot_columns IS NOT NULL THEN
            all_pivot_columns := all_pivot_columns || ',' || E'\n        ' || desc_pivot_columns;
        ELSE
            all_pivot_columns := desc_pivot_columns;
        END IF;
    END IF;

    IF all_pivot_columns IS NULL THEN
        RAISE NOTICE 'No observations found - cannot create layer view';
        RETURN;
    END IF;

    -- Build query - base phys_chem part
    query_text := format(
        'WITH combined_data AS (
            SELECT
                s.specimen_id AS layer_id,
                s.code AS layer_code,
                s.plot_id,
                s.upper_depth,
                s.lower_depth,
                rps.value::text as value,
                NULL::text as text_value,
                o.observation_code
            FROM core.result_phys_chem_specimen rps
            INNER JOIN core.specimen s ON rps.specimen_id = s.specimen_id
            INNER JOIN core.vw_observation_%s o
                ON o.observation_phys_chem_specimen_id = rps.observation_phys_chem_specimen_id
            WHERE o.observation_type = ''phys_chem''',
        date_text);

    -- Conditionally add spectral part
    IF has_spectral THEN
        query_text := query_text || format('

            UNION ALL

            SELECT
                s.specimen_id AS layer_id,
                s.code AS layer_code,
                s.plot_id,
                s.upper_depth,
                s.lower_depth,
                rds.value::text as value,
                NULL::text as text_value,
                o.observation_code
            FROM core.result_spectral_derived_specimen rds
            INNER JOIN core.specimen s ON rds.specimen_id = s.specimen_id
            INNER JOIN core.observation_spectral_derived_specimen od
                ON od.observation_spectral_derived_specimen_id = rds.observation_spectral_derived_specimen_id
            INNER JOIN core.vw_observation_%s o
                ON o.observation_phys_chem_specimen_id = od.observation_phys_chem_specimen_id
            WHERE o.observation_type = ''spectral_derived''',
            date_text);
    END IF;

    -- Conditionally add text part
    IF has_text_extension AND text_pivot_columns IS NOT NULL THEN
        query_text := query_text || '

            UNION ALL

            SELECT
                s.specimen_id AS layer_id,
                s.code AS layer_code,
                s.plot_id,
                s.upper_depth,
                s.lower_depth,
                NULL::text as value,
                rts.value as text_value,
                ''text_'' || pt.label as observation_code
            FROM core.result_text_specimen rts
            INNER JOIN core.specimen s ON rts.specimen_id = s.specimen_id
            INNER JOIN core.observation_text_specimen ots
                ON ots.observation_text_specimen_id = rts.observation_text_specimen_id
            INNER JOIN core.property_text pt ON ots.property_text_id = pt.property_text_id';
    END IF;

    -- Conditionally add descriptive part
    IF has_specimen_desc_uri AND desc_pivot_columns IS NOT NULL THEN
        query_text := query_text || '

            UNION ALL

            SELECT
                s.specimen_id AS layer_id,
                s.code AS layer_code,
                s.plot_id,
                s.upper_depth,
                s.lower_depth,
                NULL::text as value,
                tds.label as text_value,
                ''desc_'' || pds.label as observation_code
            FROM core.result_desc_specimen rds
            INNER JOIN core.specimen s ON rds.specimen_id = s.specimen_id
            INNER JOIN core.property_desc_specimen pds
                ON rds.property_desc_specimen_id = pds.property_desc_specimen_id
            INNER JOIN core.thesaurus_desc_specimen tds
                ON rds.thesaurus_desc_specimen_id = tds.thesaurus_desc_specimen_id';
    END IF;

    -- Close the CTE and add the SELECT
    query_text := query_text || format('
        )
        SELECT
            layer_id,
            layer_code,
            plot_id,
            upper_depth,
            lower_depth,
            %s
        FROM combined_data
        GROUP BY layer_id, layer_code, plot_id, upper_depth, lower_depth',
        all_pivot_columns);

    EXECUTE format(
        'DROP MATERIALIZED VIEW IF EXISTS core.vw_layer_%s CASCADE;
         CREATE MATERIALIZED VIEW core.vw_layer_%s AS %s WITH NO DATA;
         COMMENT ON MATERIALIZED VIEW core.vw_layer_%s IS ''Layer/specimen data with pivoted observation results. Fixed columns: layer_id (specimen_id or element_id depending on observation_type), layer_code (specimen code - only for specimens, elements do not have code), plot_id, upper_depth, lower_depth. Dynamic columns are added per observation: numeric observations use 4-char hash codes (from vw_observation), text observations are prefixed with text_ (from result_text_specimen, if text extension installed), descriptive observations are prefixed with desc_ (from result_desc_specimen, if specimen descriptive URI extension installed). Spectral derived values use hash codes with _spec suffix (if spectral extension installed).'';
         REFRESH MATERIALIZED VIEW core.vw_layer_%s WITH DATA;',
        date_text, date_text, query_text, date_text, date_text
    );

    -- Grant read-only access to PUBLIC (these are export views, safe for all authenticated users)
    EXECUTE format('GRANT SELECT ON core.vw_layer_%s TO PUBLIC', date_text);

    RAISE NOTICE 'Materialized view core.vw_layer_% created successfully', date_text;
END;
$$;

COMMENT ON FUNCTION core.bridge_process_layer(text, date) IS
'This function creates a materialized view for the layer or specimen.
The input parameters are observation type(specimen or element) and creation date(null if the materialized view is created as a snapshot).
This function depends on the materialized view vw_observation_<date>. Make sure to call core.bridge_process_observation() before this function.
Works with or without the spectral extension installed.
Output columns:
  - layer_id: specimen_id or element_id (depending on observation_type)
  - layer_code: specimen code (only for specimens; elements do not have a code)
  - plot_id, upper_depth, lower_depth: layer position data
Includes pivoted columns for:
  - Numeric observations (from result_phys_chem_specimen) as numeric values
  - Spectral derived observations (from result_spectral_derived_specimen) as numeric values
  - Text observations (from result_text_specimen, prefixed with text_) as text values
  - Descriptive observations (from result_desc_specimen, prefixed with desc_) as thesaurus labels
Example: SELECT core.bridge_process_layer(''specimen'',''2026-01-06'')';

------------------------------------------------------------------------------------
-- Function: bridge_process_all
-- Convenience function to create all three materialized views at once
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_process_all(json, text, date);
CREATE OR REPLACE FUNCTION core.bridge_process_all(
    observation_list json DEFAULT NULL,
    observation_type text DEFAULT 'specimen',
    creation_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Create observation metadata view
    PERFORM core.bridge_process_observation(observation_list, observation_type, creation_date);

    -- Create profile/plot view
    PERFORM core.bridge_process_profile(observation_list, observation_type, creation_date);

    -- Create layer/specimen view (depends on observation view)
    PERFORM core.bridge_process_layer(observation_type, creation_date);

    RAISE NOTICE 'All materialized views created successfully';
END;
$$;

COMMENT ON FUNCTION core.bridge_process_all(json, text, date) IS
'Creates all three materialized views (observation, profile, layer) in one call.
Works with or without the spectral extension installed.
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all observations)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Examples:
  SELECT core.bridge_process_all(null, ''specimen'', null);  -- All observations, snapshot
  SELECT core.bridge_process_all(null, ''specimen'', ''2026-01-06'');  -- All observations, dated
  SELECT core.bridge_process_all(''{\"3\": \"ca\", \"5\": \"mn\"}'', ''specimen'', ''2026-01-06'');  -- Specific observations';


------------------------------------------------------------------------------------
-- Helper function: Check if plot phys_chem extension is installed
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_has_plot_phys_chem() CASCADE;
CREATE OR REPLACE FUNCTION core.bridge_has_plot_phys_chem()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_phys_chem_plot'
    );
END;
$$;

COMMENT ON FUNCTION core.bridge_has_plot_phys_chem() IS
'Returns TRUE if the plot phys_chem tables are installed, FALSE otherwise.';

------------------------------------------------------------------------------------
-- Helper function: Check if text extension is installed
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_has_text_extension() CASCADE;
CREATE OR REPLACE FUNCTION core.bridge_has_text_extension()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_text_plot'
    );
END;
$$;

COMMENT ON FUNCTION core.bridge_has_text_extension() IS
'Returns TRUE if the text extension tables are installed, FALSE otherwise. Used for free text observations.';

------------------------------------------------------------------------------------
-- Helper function: Check if specimen descriptive with URI is installed
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_has_specimen_desc_uri() CASCADE;
CREATE OR REPLACE FUNCTION core.bridge_has_specimen_desc_uri()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core'
        AND table_name = 'property_desc_specimen'
        AND column_name = 'uri'
    );
END;
$$;

COMMENT ON FUNCTION core.bridge_has_specimen_desc_uri() IS
'Returns TRUE if property_desc_specimen has uri column, FALSE otherwise. Used for specimen descriptive observations.';

------------------------------------------------------------------------------------
-- Function: bridge_process_profile_with_plot_numeric
-- Creates materialized view for profile/plot data including plot-level numeric results
------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.bridge_process_profile_with_plot_numeric(date);
CREATE OR REPLACE FUNCTION core.bridge_process_profile_with_plot_numeric(
    creation_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    sql_1 text;
    sql_2 text;
    query_text text;
    pivot_columns text;
    date_text text;
    has_plot_phys_chem boolean;
BEGIN
    -- Check if plot phys_chem tables exist
    has_plot_phys_chem := core.bridge_has_plot_phys_chem();

    IF NOT has_plot_phys_chem THEN
        RAISE NOTICE 'Plot phys_chem tables not installed - use bridge_process_profile() instead';
        RETURN;
    END IF;

    IF creation_date IS NULL THEN
        date_text := 'snapshot';
    ELSE
        date_text := replace(creation_date::text, '-', '_');
    END IF;

    -- Build pivot columns dynamically from plot observations (only for observations with results)
    EXECUTE '
        SELECT string_agg(
            format(''MAX(CASE WHEN rpc.observation_phys_chem_plot_id = %s THEN rpc.value END) AS %I'',
                opc.observation_phys_chem_plot_id,
                ppc.label
            ),
            '', '' || E''\n        ''
        )
        FROM core.observation_phys_chem_plot opc
        INNER JOIN core.property_phys_chem ppc ON opc.property_phys_chem_id = ppc.property_phys_chem_id
        WHERE EXISTS (
            SELECT 1 FROM core.result_phys_chem_plot r
            WHERE r.observation_phys_chem_plot_id = opc.observation_phys_chem_plot_id
        )'
    INTO pivot_columns;

    IF pivot_columns IS NULL THEN
        RAISE NOTICE 'No plot phys_chem results found - creating profile view without numeric columns';
        -- Fall back to basic profile query
        query_text := 'SELECT pl.site_id, pl.plot_id, pl.plot_code, sp.project_id,
            p.name as project_name,
            pl.position::geometry as geometry,
            ST_Y(pl.position::geometry) AS lat,
            ST_X(pl.position::geometry) AS lon,
            pl.positional_accuracy
            FROM core.plot pl
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id';
    ELSE
        -- Build full query with pivoted plot numeric results
        query_text := format('
            SELECT
                pl.site_id,
                pl.plot_id,
                pl.plot_code,
                sp.project_id,
                p.name as project_name,
                pl.position::geometry as geometry,
                ST_Y(pl.position::geometry) AS lat,
                ST_X(pl.position::geometry) AS lon,
                pl.positional_accuracy,
                %s
            FROM core.plot pl
            LEFT JOIN core.site_project sp ON pl.site_id = sp.site_id
            LEFT JOIN core.project p ON sp.project_id = p.project_id
            LEFT JOIN core.result_phys_chem_plot rpc ON pl.plot_id = rpc.plot_id
            GROUP BY pl.site_id, pl.plot_id, pl.plot_code, sp.project_id, p.name,
                     pl.position, pl.positional_accuracy',
            pivot_columns);
    END IF;

    sql_1 := format(
        'DROP MATERIALIZED VIEW IF EXISTS core.vw_profile_numeric_%s CASCADE;
        CREATE MATERIALIZED VIEW core.vw_profile_numeric_%s AS ', date_text, date_text);

    sql_2 := format('
        WITH NO DATA; COMMENT ON MATERIALIZED VIEW core.vw_profile_numeric_%s
        IS ''Profile/plot data with only plot-level numeric observations (simplified alternative to vw_profile). Fixed columns: site_id, plot_id, plot_code, project_id, project_name, geometry, lat, lon, positional_accuracy. Dynamic columns are added for each numeric observation from result_phys_chem_plot (requires plot numeric extension). Does not include descriptive or text observations - use vw_profile for the full view.'';
        REFRESH MATERIALIZED VIEW core.vw_profile_numeric_%s WITH DATA;
        ', date_text, date_text);

    EXECUTE(sql_1 || query_text || sql_2);

    -- Grant read-only access to PUBLIC
    EXECUTE format('GRANT SELECT ON core.vw_profile_numeric_%s TO PUBLIC', date_text);

    RAISE NOTICE 'Materialized view core.vw_profile_numeric_% created successfully', date_text;
END;
$$;

COMMENT ON FUNCTION core.bridge_process_profile_with_plot_numeric(date) IS
'Creates a materialized view for profile/plot data including plot-level numeric results (e.g., RockDpth).
Requires the plot phys_chem tables.
Example: SELECT core.bridge_process_profile_with_plot_numeric(''2026-01-18'')';


------------------------------------------------------------------------------------
-- Example usage (uncomment to run):
------------------------------------------------------------------------------------
-- SELECT core.bridge_process_all('{"3": "ca", "5": "mn"}', 'specimen', '2026-01-06');
-- SELECT core.bridge_process_all(null, 'specimen', '2026-01-06');
-- SELECT core.bridge_process_all(null, 'specimen', null);  -- Creates snapshot views
-- SELECT core.bridge_process_profile_with_plot_numeric(null);  -- Profile with plot numeric results


------------------------------------------------------------------------------------
-- PERMISSIONS (project-specific)
------------------------------------------------------------------------------------
-- The materialized views created by these functions are granted SELECT to PUBLIC.
--
-- To allow specific roles to execute these functions, add grants to your project's
-- permissions file (e.g., rbac_role_permissions.sql). Replace <role> with your
-- project's role names (e.g., project_r, project_w):
--
-- GRANT EXECUTE ON FUNCTION core.bridge_has_spectral_extension() TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_has_plot_phys_chem() TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_has_text_extension() TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_has_specimen_desc_uri() TO <role>;
-- GRANT EXECUTE ON FUNCTION core.generate_code(TEXT, INT) TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_process_observation(JSON, TEXT, DATE) TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_process_profile(JSON, TEXT, DATE) TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_process_layer(TEXT, DATE) TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_process_all(JSON, TEXT, DATE) TO <role>;
-- GRANT EXECUTE ON FUNCTION core.bridge_process_profile_with_plot_numeric(DATE) TO <role>;
