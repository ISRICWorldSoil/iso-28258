--
-- PostgreSQL database dump
--


-- Dumped from database version 18.1 (Homebrew)
-- Dumped by pg_dump version 18.1 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- Name: SCHEMA core; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA core IS 'Core entities and relations from the ISO-28258 domain model';


--
-- Name: metadata; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA metadata;


--
-- Name: SCHEMA metadata; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA metadata IS 'Meta-data model based on VCard: https://www.w3.org/TR/vcard-rdf';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: element_type; Type: TYPE; Schema: core; Owner: -
--

CREATE TYPE core.element_type AS ENUM (
    'Horizon',
    'Layer'
);


--
-- Name: TYPE element_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TYPE core.element_type IS 'Type of Profile Element';


--
-- Name: bridge_has_plot_phys_chem(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_has_plot_phys_chem() RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_phys_chem_plot'
    );
END;
$$;


--
-- Name: FUNCTION bridge_has_plot_phys_chem(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_has_plot_phys_chem() IS 'Returns TRUE if the plot phys_chem tables are installed, FALSE otherwise.';


--
-- Name: bridge_has_specimen_desc_uri(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_has_specimen_desc_uri() RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: FUNCTION bridge_has_specimen_desc_uri(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_has_specimen_desc_uri() IS 'Returns TRUE if property_desc_specimen has uri column, FALSE otherwise. Used for specimen descriptive observations.';


--
-- Name: bridge_has_spectral_extension(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_has_spectral_extension() RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_spectral_derived_specimen'
    );
END;
$$;


--
-- Name: FUNCTION bridge_has_spectral_extension(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_has_spectral_extension() IS 'Returns TRUE if the spectral extension tables are installed, FALSE otherwise. Used by bridge functions to conditionally include spectral queries.';


--
-- Name: bridge_has_text_extension(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_has_text_extension() RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core'
        AND table_name = 'result_text_plot'
    );
END;
$$;


--
-- Name: FUNCTION bridge_has_text_extension(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_has_text_extension() IS 'Returns TRUE if the text extension tables are installed, FALSE otherwise. Used for free text observations.';


--
-- Name: bridge_process_all(json, text, date); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_process_all(observation_list json DEFAULT NULL::json, observation_type text DEFAULT 'specimen'::text, creation_date date DEFAULT NULL::date) RETURNS void
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


--
-- Name: FUNCTION bridge_process_all(observation_list json, observation_type text, creation_date date); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_process_all(observation_list json, observation_type text, creation_date date) IS 'Creates all three materialized views (observation, profile, layer) in one call.
Works with or without the spectral extension installed.
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all observations)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Examples:
  SELECT core.bridge_process_all(null, ''specimen'', null);  -- All observations, snapshot
  SELECT core.bridge_process_all(null, ''specimen'', ''2026-01-06'');  -- All observations, dated
  SELECT core.bridge_process_all(''{\"3\": \"ca\", \"5\": \"mn\"}'', ''specimen'', ''2026-01-06'');  -- Specific observations';


--
-- Name: bridge_process_layer(text, date); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_process_layer(observation_type text DEFAULT 'specimen'::text, creation_date date DEFAULT NULL::date) RETURNS void
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


--
-- Name: FUNCTION bridge_process_layer(observation_type text, creation_date date); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_process_layer(observation_type text, creation_date date) IS 'This function creates a materialized view for the layer or specimen.
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


--
-- Name: bridge_process_observation(json, text, date); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_process_observation(observation_list json DEFAULT NULL::json, observation_type text DEFAULT 'specimen'::text, creation_date date DEFAULT NULL::date) RETURNS void
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


--
-- Name: FUNCTION bridge_process_observation(observation_list json, observation_type text, creation_date date); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_process_observation(observation_list json, observation_type text, creation_date date) IS 'Creates a materialized view for observation metadata.
Works with or without the spectral extension installed.
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Example: SELECT core.bridge_process_observation(''{\"3\": \"ca\", \"5\": \"mn\"}'', ''specimen'', ''2026-01-06'')';


--
-- Name: bridge_process_profile(json, text, date); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_process_profile(observation_list json DEFAULT NULL::json, observation_type text DEFAULT 'specimen'::text, creation_date date DEFAULT NULL::date) RETURNS void
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


--
-- Name: FUNCTION bridge_process_profile(observation_list json, observation_type text, creation_date date); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_process_profile(observation_list json, observation_type text, creation_date date) IS 'Creates a materialized view for profile/plot data including plot-level observations.
Includes pivoted columns for:
  - Descriptive observations (from result_desc_plot) as text values
  - Numeric observations (from result_phys_chem_plot) as numeric values
Parameters:
  - observation_list: JSON object mapping observation_phys_chem_specimen_id to code (null for all)
  - observation_type: ''specimen'' or ''element'' (element not yet implemented)
  - creation_date: date for view naming (null creates ''snapshot'' views)
Works with or without the spectral and plot phys_chem extensions installed.
Example: SELECT core.bridge_process_profile(null, ''specimen'', ''2026-01-06'')';


--
-- Name: bridge_process_profile_with_plot_numeric(date); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.bridge_process_profile_with_plot_numeric(creation_date date DEFAULT NULL::date) RETURNS void
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


--
-- Name: FUNCTION bridge_process_profile_with_plot_numeric(creation_date date); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.bridge_process_profile_with_plot_numeric(creation_date date) IS 'Creates a materialized view for profile/plot data including plot-level numeric results (e.g., RockDpth).
Requires the plot phys_chem tables.
Example: SELECT core.bridge_process_profile_with_plot_numeric(''2026-01-18'')';


--
-- Name: check_result_value(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.check_result_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    observation core.observation_phys_chem%ROWTYPE;
BEGIN
    SELECT * 
      INTO observation
      FROM core.observation_phys_chem
     WHERE observation_phys_chem_id = NEW.observation_phys_chem_id;
    
    IF NEW.value < observation.value_min OR NEW.value > observation.value_max THEN
        RAISE EXCEPTION 'Result value outside admissable bounds for the related observation.';
    ELSE
        RETURN NEW;
    END IF; 
END;
$$;


--
-- Name: FUNCTION check_result_value(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.check_result_value() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observations (fields value_min and value_max).';


--
-- Name: check_result_value_plot(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.check_result_value_plot() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    observation core.observation_phys_chem_plot%ROWTYPE;
BEGIN
    SELECT *
      INTO observation
      FROM core.observation_phys_chem_plot
     WHERE observation_phys_chem_plot_id = NEW.observation_phys_chem_plot_id;

    IF NEW.value < observation.value_min OR NEW.value > observation.value_max THEN
        RAISE EXCEPTION 'Result value outside admissable bounds for the related observation.';
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


--
-- Name: FUNCTION check_result_value_plot(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.check_result_value_plot() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observation (fields value_min and value_max).';


--
-- Name: check_result_value_specimen(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.check_result_value_specimen() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    observation core.observation_phys_chem_specimen%ROWTYPE;
BEGIN
    SELECT *
      INTO observation
      FROM core.observation_phys_chem_specimen
     WHERE observation_phys_chem_specimen_id = NEW.observation_phys_chem_specimen_id;

    IF NEW.value < observation.value_min OR NEW.value > observation.value_max THEN
        RAISE EXCEPTION 'Result value outside admissable bounds for the related observation.';
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


--
-- Name: FUNCTION check_result_value_specimen(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.check_result_value_specimen() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observation (fields value_min and value_max).';


--
-- Name: etl_bulk_insert_desc_plot_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_desc_plot_results(p_data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INT;
BEGIN
    WITH input_data AS (
        SELECT
            (r->>'plot_id')::INT AS plot_id,
            (r->>'property_uri')::TEXT AS property_uri,
            (r->>'value')::TEXT AS value
        FROM jsonb_array_elements(p_data) AS r
    ),
    inserted AS (
        INSERT INTO core.result_desc_plot (plot_id, property_desc_plot_id, thesaurus_desc_plot_id)
        SELECT
            d.plot_id,
            p.property_desc_plot_id,
            t.thesaurus_desc_plot_id
        FROM input_data d
        JOIN core.thesaurus_desc_plot t ON t.label ILIKE d.value
        JOIN core.observation_desc_plot o ON t.thesaurus_desc_plot_id = o.thesaurus_desc_plot_id
        JOIN core.property_desc_plot p ON o.property_desc_plot_id = p.property_desc_plot_id
            AND p.uri ILIKE '%' || d.property_uri
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_count FROM inserted;

    RETURN v_count;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_desc_plot_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_desc_plot_results(p_data jsonb) IS 'Bulk insert descriptive results for plots. Input is JSONB array with plot_id, property_uri, value.';


--
-- Name: etl_bulk_insert_desc_specimen_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_desc_specimen_results(p_data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INT;
BEGIN
    WITH input_data AS (
        SELECT
            (r->>'specimen_id')::INT AS specimen_id,
            (r->>'property_uri')::TEXT AS property_uri,
            (r->>'value')::TEXT AS value
        FROM jsonb_array_elements(p_data) AS r
        WHERE (r->>'value') IS NOT NULL AND (r->>'value') != '' AND (r->>'value') != 'NA'
    ),
    inserted AS (
        INSERT INTO core.result_desc_specimen (specimen_id, property_desc_specimen_id, thesaurus_desc_specimen_id)
        SELECT
            d.specimen_id,
            p.property_desc_specimen_id,
            t.thesaurus_desc_specimen_id
        FROM input_data d
        JOIN core.property_desc_specimen p ON p.uri ILIKE '%' || d.property_uri
        JOIN core.thesaurus_desc_specimen t ON t.label ILIKE d.value
        JOIN core.observation_desc_specimen o ON
            o.property_desc_specimen_id = p.property_desc_specimen_id
            AND o.thesaurus_desc_specimen_id = t.thesaurus_desc_specimen_id
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_count FROM inserted;

    RETURN v_count;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_desc_specimen_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_desc_specimen_results(p_data jsonb) IS 'Bulk insert descriptive results for specimens. Input is JSONB array with specimen_id, property_uri, value.';


--
-- Name: etl_bulk_insert_individuals(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_individuals(p_data jsonb) RETURNS TABLE(out_name text, out_individual_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH input_data AS (
        SELECT DISTINCT (r->>'name')::TEXT AS ind_name
        FROM jsonb_array_elements(p_data) AS r
        WHERE (r->>'name') IS NOT NULL AND (r->>'name') != ''
    ),
    inserted AS (
        INSERT INTO metadata.individual (name)
        SELECT d.ind_name
        FROM input_data d
        ON CONFLICT DO NOTHING
        RETURNING metadata.individual.name AS ins_name, metadata.individual.individual_id AS ins_id
    )
    SELECT
        COALESCE(i.ins_name, e.name),
        COALESCE(i.ins_id, e.individual_id)
    FROM input_data d
    LEFT JOIN inserted i ON i.ins_name = d.ind_name
    LEFT JOIN metadata.individual e ON e.name = d.ind_name;

END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_individuals(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_individuals(p_data jsonb) IS 'Bulk insert individuals. Input is JSONB array with name field.';


--
-- Name: etl_bulk_insert_phys_chem_plot_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_phys_chem_plot_results(p_data jsonb) RETURNS TABLE(inserted_count integer, skipped_count integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inserted INT := 0;
    v_total INT := 0;
BEGIN
    WITH input_data AS (
        SELECT
            (r->>'plot_id')::INT AS p_id,
            (r->>'property_uri')::TEXT AS prop_uri,
            (r->>'procedure_uri')::TEXT AS proc_uri,
            (r->>'unit_uri')::TEXT AS u_uri,
            (r->>'value')::NUMERIC AS val
        FROM jsonb_array_elements(p_data) AS r
    ),
    input_with_observation AS (
        SELECT
            d.p_id,
            d.val,
            o.observation_phys_chem_plot_id AS obs_id,
            o.value_min,
            o.value_max
        FROM input_data d
        JOIN core.observation_phys_chem_plot o ON
            o.property_phys_chem_id = (
                SELECT property_phys_chem_id
                FROM core.property_phys_chem
                WHERE uri ILIKE '%' || d.prop_uri
            )
            AND o.procedure_phys_chem_id = (
                SELECT procedure_phys_chem_id
                FROM core.procedure_phys_chem
                WHERE uri ILIKE '%' || d.proc_uri
            )
            AND o.unit_of_measure_id = (
                SELECT unit_of_measure_id
                FROM core.unit_of_measure
                WHERE uri ILIKE '%' || d.u_uri
            )
    ),
    -- Filter to only valid values (within bounds)
    valid_data AS (
        SELECT d.*
        FROM input_with_observation d
        WHERE (d.value_min IS NULL OR d.val >= d.value_min)
          AND (d.value_max IS NULL OR d.val <= d.value_max)
    ),
    inserted AS (
        INSERT INTO core.result_phys_chem_plot (
            observation_phys_chem_plot_id,
            plot_id,
            organisation_id,
            value
        )
        SELECT
            d.obs_id,
            d.p_id,
            NULL,
            d.val
        FROM valid_data d
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_inserted FROM inserted;

    SELECT jsonb_array_length(p_data)::INT INTO v_total;

    RETURN QUERY SELECT v_inserted, (v_total - v_inserted)::INT;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_phys_chem_plot_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_phys_chem_plot_results(p_data jsonb) IS 'Bulk insert physico-chemical results for plots (v1.7+ schema). Input is JSONB array with plot_id, property_uri, procedure_uri, unit_uri, value.';


--
-- Name: etl_bulk_insert_phys_chem_specimen_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_phys_chem_specimen_results(p_data jsonb) RETURNS TABLE(inserted_count integer, skipped_count integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inserted INT := 0;
    v_total INT := 0;
BEGIN
    -- Insert results with observation lookup, filtering out-of-bounds values
    WITH input_data AS (
        SELECT
            (r->>'specimen_id')::INT AS spec_id,
            (r->>'property_uri')::TEXT AS prop_uri,
            (r->>'procedure_uri')::TEXT AS proc_uri,
            (r->>'unit_uri')::TEXT AS u_uri,
            (r->>'value')::NUMERIC AS val
        FROM jsonb_array_elements(p_data) AS r
    ),
    input_with_observation AS (
        SELECT
            d.spec_id,
            d.val,
            o.observation_phys_chem_specimen_id AS obs_id,
            o.value_min,
            o.value_max,
            s.organisation_id AS org_id
        FROM input_data d
        JOIN core.observation_phys_chem_specimen o ON
            o.property_phys_chem_id = (
                SELECT property_phys_chem_id
                FROM core.property_phys_chem
                WHERE uri ILIKE '%' || d.prop_uri
            )
            AND o.procedure_phys_chem_id = (
                SELECT procedure_phys_chem_id
                FROM core.procedure_phys_chem
                WHERE uri ILIKE '%' || d.proc_uri
            )
            AND o.unit_of_measure_id = (
                SELECT unit_of_measure_id
                FROM core.unit_of_measure
                WHERE uri ILIKE '%' || d.u_uri
            )
        JOIN core.specimen s ON s.specimen_id = d.spec_id
    ),
    -- Filter to only valid values (within bounds)
    valid_data AS (
        SELECT d.*
        FROM input_with_observation d
        WHERE (d.value_min IS NULL OR d.val >= d.value_min)
          AND (d.value_max IS NULL OR d.val <= d.value_max)
    ),
    inserted AS (
        INSERT INTO core.result_phys_chem_specimen (
            observation_phys_chem_specimen_id,
            specimen_id,
            organisation_id,
            value
        )
        SELECT
            d.obs_id,
            d.spec_id,
            d.org_id,
            d.val
        FROM valid_data d
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_inserted FROM inserted;

    SELECT jsonb_array_length(p_data)::INT INTO v_total;

    RETURN QUERY SELECT v_inserted, (v_total - v_inserted)::INT;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_phys_chem_specimen_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_phys_chem_specimen_results(p_data jsonb) IS 'Bulk insert physico-chemical results for specimens. Input is JSONB array with specimen_id, property_uri, procedure_uri, unit_uri, value.';


--
-- Name: etl_bulk_insert_plot_individuals(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_plot_individuals(p_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO core.plot_individual (plot_id, individual_id)
    SELECT
        (r->>'plot_id')::INT,
        (r->>'individual_id')::INT
    FROM jsonb_array_elements(p_data) AS r
    WHERE (r->>'plot_id') IS NOT NULL AND (r->>'individual_id') IS NOT NULL
    ON CONFLICT DO NOTHING;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_plot_individuals(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_plot_individuals(p_data jsonb) IS 'Bulk insert plot_individual associations. Input is JSONB array with plot_id, individual_id.';


--
-- Name: etl_bulk_insert_plots(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_plots(p_data jsonb) RETURNS TABLE(out_row_index integer, out_plot_id integer, out_plot_code text)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY
    WITH input_data AS (
        SELECT
            (r->>'row_index')::INT AS row_idx,
            (r->>'plot_code')::TEXT AS p_code,
            (r->>'site_id')::INT AS s_id,
            (r->>'altitude')::NUMERIC AS alt,
            (r->>'time_stamp')::TEXT AS ts,
            (r->>'map_sheet_code')::TEXT AS map_code,
            (r->>'positional_accuracy')::NUMERIC AS pos_acc,
            (r->>'latitude')::TEXT AS lat,
            (r->>'longitude')::TEXT AS lon
        FROM jsonb_array_elements(p_data) AS r
    ),
    normalized_data AS (
        SELECT
            d.*,
            CASE
                WHEN d.ts ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
                    TO_DATE(
                        REGEXP_REPLACE(
                            d.ts,
                            '(\d{1,2})/(\d{1,2})/(\d{4})',
                            LPAD('\1', 2, '0') || '/' || LPAD('\2', 2, '0') || '/' || '\3'
                        ),
                        'DD/MM/YYYY'
                    )
                ELSE NULL
            END AS normalized_timestamp
        FROM input_data d
    ),
    inserted_plots AS (
        INSERT INTO core.plot (plot_code, site_id, altitude, time_stamp, map_sheet_code, positional_accuracy, "position")
        SELECT
            d.p_code,
            d.s_id,
            d.alt,
            d.normalized_timestamp,
            d.map_code,
            d.pos_acc,
            ST_GeographyFromText('POINT (' || d.lon || ' ' || d.lat || ')')
        FROM normalized_data d
        WHERE d.s_id IS NOT NULL AND d.p_code IS NOT NULL
        ON CONFLICT DO NOTHING
        RETURNING core.plot.plot_id AS ins_plot_id, core.plot.plot_code AS ins_plot_code
    )
    SELECT
        d.row_idx,
        COALESCE(i.ins_plot_id, existing.plot_id),
        d.p_code
    FROM input_data d
    LEFT JOIN inserted_plots i ON i.ins_plot_code = d.p_code
    LEFT JOIN core.plot existing ON existing.plot_code = d.p_code AND existing.site_id = d.s_id
    WHERE d.p_code IS NOT NULL;

END;
$_$;


--
-- Name: FUNCTION etl_bulk_insert_plots(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_plots(p_data jsonb) IS 'Bulk insert plots. Input is JSONB array with row_index, plot_code, site_id, altitude, time_stamp, map_sheet_code, positional_accuracy, latitude, longitude.';


--
-- Name: etl_bulk_insert_sites_projects(jsonb, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_sites_projects(p_data jsonb, p_project_name text) RETURNS TABLE(out_row_index integer, out_site_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_project_id INT;
    v_rec RECORD;
    v_site_id INT;
BEGIN
    -- Get project_id once
    SELECT p.project_id INTO v_project_id
    FROM core.project p
    WHERE p.name ILIKE p_project_name;

    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Project "%" not found', p_project_name;
    END IF;

    -- Process each record
    FOR v_rec IN
        SELECT
            (r->>'row_index')::INT AS row_idx,
            (r->>'latitude')::TEXT AS lat,
            (r->>'longitude')::TEXT AS lon,
            (r->>'site_code')::INT AS s_code,
            (r->>'typical_profile')::INT AS t_profile
        FROM jsonb_array_elements(p_data) AS r
    LOOP
        -- Insert site or get existing
        INSERT INTO core.site (site_code, typical_profile, "position")
        VALUES (
            v_rec.s_code,
            v_rec.t_profile,
            ST_GeographyFromText('POINT (' || v_rec.lon || ' ' || v_rec.lat || ')')
        )
        ON CONFLICT DO NOTHING;

        -- Get the site_id (whether just inserted or already existing)
        SELECT s.site_id INTO v_site_id
        FROM core.site s
        WHERE s."position" = ST_GeographyFromText('POINT (' || v_rec.lon || ' ' || v_rec.lat || ')');

        -- Link to project
        INSERT INTO core.site_project (site_id, project_id)
        VALUES (v_site_id, v_project_id)
        ON CONFLICT DO NOTHING;

        -- Return this mapping
        out_row_index := v_rec.row_idx;
        out_site_id := v_site_id;
        RETURN NEXT;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_sites_projects(p_data jsonb, p_project_name text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_sites_projects(p_data jsonb, p_project_name text) IS 'Bulk insert sites and link them to a project. Input is JSONB array with row_index, latitude, longitude, site_code (optional), typical_profile (optional).';


--
-- Name: etl_bulk_insert_specimens(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_specimens(p_data jsonb) RETURNS TABLE(out_row_index integer, out_specimen_id integer, out_specimen_code text, out_plot_code text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rec RECORD;
    v_specimen_id INT;
    v_org_id INT;
BEGIN
    -- Process each input row individually to handle duplicates correctly
    FOR v_rec IN
        SELECT
            (r->>'row_index')::INT AS row_idx,
            (r->>'specimen_code')::TEXT AS spec_code,
            (r->>'plot_id')::INT AS p_id,
            (r->>'plot_code')::TEXT AS p_code,
            (r->>'upper_depth')::INT AS u_depth,
            (r->>'lower_depth')::INT AS l_depth,
            (r->>'organisation_name')::TEXT AS org_name
        FROM jsonb_array_elements(p_data) AS r
    LOOP
        -- Skip rows without plot_id
        IF v_rec.p_id IS NULL THEN
            CONTINUE;
        END IF;

        -- Look up organisation_id
        v_org_id := NULL;
        IF v_rec.org_name IS NOT NULL THEN
            SELECT o.organisation_id INTO v_org_id
            FROM metadata.organisation o
            WHERE o.name ILIKE '%' || v_rec.org_name || '%'
            LIMIT 1;
        END IF;

        -- Insert specimen and get the new ID
        INSERT INTO core.specimen (code, plot_id, upper_depth, lower_depth, organisation_id)
        VALUES (v_rec.spec_code, v_rec.p_id, v_rec.u_depth, v_rec.l_depth, v_org_id)
        RETURNING specimen_id INTO v_specimen_id;

        -- Return the mapping
        out_row_index := v_rec.row_idx;
        out_specimen_id := v_specimen_id;
        out_specimen_code := v_rec.spec_code;
        out_plot_code := v_rec.p_code;
        RETURN NEXT;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_specimens(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_specimens(p_data jsonb) IS 'Bulk insert specimens with row-by-row processing. Each input row creates a new specimen (handles duplicates like standard ETL). Input is JSONB array with row_index, specimen_code, plot_id, plot_code, upper_depth, lower_depth, organisation_name.';


--
-- Name: etl_bulk_insert_text_plot_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_text_plot_results(p_data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INT;
BEGIN
    WITH input_data AS (
        SELECT
            (r->>'plot_id')::INT AS plot_id,
            (r->>'property_uri')::TEXT AS property_uri,
            (r->>'value')::TEXT AS value
        FROM jsonb_array_elements(p_data) AS r
        WHERE (r->>'value') IS NOT NULL AND (r->>'value') != '' AND (r->>'value') != 'NA'
    ),
    inserted AS (
        INSERT INTO core.result_text_plot (observation_text_plot_id, plot_id, value)
        SELECT
            o.observation_text_plot_id,
            d.plot_id,
            d.value
        FROM input_data d
        JOIN core.property_text_plot p ON p.uri ILIKE '%' || d.property_uri
        JOIN core.observation_text_plot o ON o.property_text_plot_id = p.property_text_plot_id
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_count FROM inserted;

    RETURN v_count;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_text_plot_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_text_plot_results(p_data jsonb) IS 'Bulk insert text results for plots. Input is JSONB array with plot_id, property_uri, value.';


--
-- Name: etl_bulk_insert_text_specimen_results(jsonb); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_bulk_insert_text_specimen_results(p_data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INT;
BEGIN
    WITH input_data AS (
        SELECT
            (r->>'specimen_id')::INT AS specimen_id,
            (r->>'property_uri')::TEXT AS property_uri,
            (r->>'value')::TEXT AS value
        FROM jsonb_array_elements(p_data) AS r
        WHERE (r->>'value') IS NOT NULL AND (r->>'value') != '' AND (r->>'value') != 'NA'
    ),
    inserted AS (
        INSERT INTO core.result_text_specimen (observation_text_specimen_id, specimen_id, value)
        SELECT
            o.observation_text_specimen_id,
            d.specimen_id,
            d.value
        FROM input_data d
        JOIN core.property_text_specimen p ON p.uri ILIKE '%' || d.property_uri
        JOIN core.observation_text_specimen o ON o.property_text_specimen_id = p.property_text_specimen_id
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*)::INT INTO v_count FROM inserted;

    RETURN v_count;
END;
$$;


--
-- Name: FUNCTION etl_bulk_insert_text_specimen_results(p_data jsonb); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_bulk_insert_text_specimen_results(p_data jsonb) IS 'Bulk insert text results for specimens. Input is JSONB array with specimen_id, property_uri, value.';


--
-- Name: etl_delete_project_data(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_delete_project_data(p_project_name text) RETURNS TABLE(deleted_sites integer, deleted_plots integer, deleted_specimens integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_project_id integer;
    v_site_ids integer[];
    v_deleted_sites integer := 0;
    v_deleted_plots integer := 0;
    v_deleted_specimens integer := 0;
BEGIN
    -- Find the project
    SELECT project_id INTO v_project_id
    FROM core.project
    WHERE name ILIKE p_project_name;

    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Project "%" not found', p_project_name;
    END IF;

    -- Get all site_ids linked to this project
    SELECT array_agg(site_id) INTO v_site_ids
    FROM core.site_project
    WHERE project_id = v_project_id;

    IF v_site_ids IS NULL OR array_length(v_site_ids, 1) IS NULL THEN
        RAISE NOTICE 'No sites found for project "%"', p_project_name;
        RETURN QUERY SELECT 0, 0, 0;
        RETURN;
    END IF;

    -- Count what will be deleted (for reporting)
    SELECT COUNT(*) INTO v_deleted_specimens
    FROM core.specimen s
    JOIN core.plot p ON s.plot_id = p.plot_id
    WHERE p.site_id = ANY(v_site_ids);

    SELECT COUNT(*) INTO v_deleted_plots
    FROM core.plot
    WHERE site_id = ANY(v_site_ids);

    v_deleted_sites := array_length(v_site_ids, 1);

    -- Delete site_project entries (this will CASCADE to sites, plots, specimens, results)
    DELETE FROM core.site_project
    WHERE project_id = v_project_id;

    -- Delete the sites themselves (CASCADE will handle children)
    DELETE FROM core.site
    WHERE site_id = ANY(v_site_ids);

    RETURN QUERY SELECT v_deleted_sites, v_deleted_plots, v_deleted_specimens;
END;
$$;


--
-- Name: FUNCTION etl_delete_project_data(p_project_name text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_delete_project_data(p_project_name text) IS 'Deletes all data for a specific project. Cascades through site -> plot -> specimen -> results hierarchy.';


--
-- Name: etl_erase_all_data(); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_erase_all_data() RETURNS TABLE(deleted_sites integer, deleted_plots integer, deleted_specimens integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deleted_sites integer := 0;
    v_deleted_plots integer := 0;
    v_deleted_specimens integer := 0;
BEGIN
    -- Count what will be deleted (for reporting)
    SELECT COUNT(*) INTO v_deleted_specimens FROM core.specimen;
    SELECT COUNT(*) INTO v_deleted_plots FROM core.plot;
    SELECT COUNT(*) INTO v_deleted_sites FROM core.site;

    -- Delete all site_project entries first
    DELETE FROM core.site_project;

    -- Delete all sites (CASCADE will handle all children)
    DELETE FROM core.site;

    -- Also delete profiles, elements that might be orphaned (via surface)
    DELETE FROM core.profile WHERE surface_id IS NOT NULL;
    DELETE FROM core.surface;

    RETURN QUERY SELECT v_deleted_sites, v_deleted_plots, v_deleted_specimens;
END;
$$;


--
-- Name: FUNCTION etl_erase_all_data(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_erase_all_data() IS 'Deletes all site/plot/specimen/result data from all projects. Preserves metadata (observations, properties, procedures, etc.).';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: address; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.address (
    street_address character varying NOT NULL,
    postal_code character varying NOT NULL,
    locality character varying NOT NULL,
    country character varying NOT NULL,
    address_id integer NOT NULL
);


--
-- Name: TABLE address; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.address IS 'Equivalent to the Address class in VCard, defined as delivery address for the associated object.';


--
-- Name: COLUMN address.street_address; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.street_address IS 'Street address data property in VCard, including house number, e.g. "Generaal Foulkesweg 108".';


--
-- Name: COLUMN address.postal_code; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.postal_code IS 'Equivalent to the postal-code data property in VCard, e.g. "6701 PB".';


--
-- Name: COLUMN address.locality; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.locality IS 'Locality data property in VCard, referring to a village, town, city, etc, e.g. "Wageningen".';


--
-- Name: COLUMN address.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.address_id IS 'Synthetic primary key.';


--
-- Name: etl_insert_address(text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_address(street_address text, country_iso text DEFAULT NULL::text) RETURNS SETOF metadata.address
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only insert if does not exist, in this case street_address should be unique.
    IF NOT EXISTS(SELECT a.street_address FROM metadata.address as a WHERE a.street_address = etl_insert_address.street_address) THEN
        RETURN QUERY
            INSERT INTO metadata.address (street_address)
            VALUES (etl_insert_address.street_address)
            ON CONFLICT DO NOTHING RETURNING *;
    ELSE
        RETURN QUERY
            SELECT * FROM metadata.address as a WHERE a.street_address = etl_insert_address.street_address;
    END IF;
END;
$$;


--
-- Name: FUNCTION etl_insert_address(street_address text, country_iso text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_address(street_address text, country_iso text) IS 'Inserts a new address into the metadata.address table. If the address already exists, it returns the existing record.';


--
-- Name: individual; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.individual (
    name character varying NOT NULL,
    honorific_title character varying,
    email character varying,
    telephone character varying,
    url character varying,
    address_id integer,
    individual_id integer NOT NULL
);


--
-- Name: TABLE individual; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.individual IS 'Equivalent to the Individual class in VCard, defined as a single person or entity.';


--
-- Name: COLUMN individual.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.name IS 'Name of the individual, encompasses the data properties additional-name, given-name and family-name in VCard.';


--
-- Name: COLUMN individual.honorific_title; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.honorific_title IS 'Academic title or honorific rank associated to the individual. Encompasses the data properties honorific-prefix, honorific-suffix and title in VCard.';


--
-- Name: COLUMN individual.email; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.email IS 'Electronic mail address of the individual.';


--
-- Name: COLUMN individual.url; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.url IS 'Locator to a web page associated with the individual.';


--
-- Name: COLUMN individual.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.address_id IS 'Foreign key to address associated with the individual.';


--
-- Name: COLUMN individual.individual_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.individual_id IS 'Synthetic primary key.';


--
-- Name: etl_insert_individual(text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_individual(name text, email text) RETURNS SETOF metadata.individual
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if a record with the same name or email already exists
    IF EXISTS (SELECT 1 FROM metadata.individual i WHERE i.email = etl_insert_individual.email OR i.name = etl_insert_individual.name) THEN
        -- Return the existing record
        RETURN QUERY
        SELECT * FROM metadata.individual i
        WHERE i.email = etl_insert_individual.email OR i.name = etl_insert_individual.name;
    ELSE
        -- Insert a new record, avoiding conflicts
        RETURN QUERY
        INSERT INTO metadata.individual (name, email)
        VALUES (etl_insert_individual.name, etl_insert_individual.email)
        ON CONFLICT DO NOTHING
        RETURNING *;
    END IF;
END;
$$;


--
-- Name: FUNCTION etl_insert_individual(name text, email text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_individual(name text, email text) IS 'Inserts a new individual into the metadata.individual table. If the individual already exists, it returns the existing record.';


--
-- Name: organisation; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.organisation (
    parent_id integer,
    name character varying NOT NULL,
    email character varying,
    telephone character varying,
    url character varying,
    address_id integer,
    organisation_id integer NOT NULL
);


--
-- Name: TABLE organisation; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation IS 'Equivalent to the Organisation class in VCard, defined as a single entity, might also represent a business or government, a department or division within a business or government, a club, an association, or the like.';


--
-- Name: COLUMN organisation.parent_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.parent_id IS 'Foreign key to the parent organisation, in case of a department or division of a larger organisation.';


--
-- Name: COLUMN organisation.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.name IS 'Name of the organisation.';


--
-- Name: COLUMN organisation.email; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.email IS 'Electronic mail address of the organisation.';


--
-- Name: COLUMN organisation.url; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.url IS 'Locator to a web page associated with the organisation.';


--
-- Name: COLUMN organisation.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.address_id IS 'Foreign key to address associated with the organisation.';


--
-- Name: COLUMN organisation.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.organisation_id IS 'Synthetic primary key.';


--
-- Name: etl_insert_organisation(text, text, text, text, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_organisation(name text, email text, telephone text, url text, address_id integer) RETURNS SETOF metadata.organisation
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only insert if does not exist, in this case name should be unique.
    IF NOT EXISTS(SELECT o.name FROM metadata.organisation as o WHERE o.name = etl_insert_organisation.name) THEN
        RETURN QUERY
            INSERT INTO metadata.organisation (name, email, telephone, url, address_id)
            VALUES (etl_insert_organisation.name,
                    etl_insert_organisation.email,
                    etl_insert_organisation.telephone,
                    etl_insert_organisation.url,
                    etl_insert_organisation.address_id)
            ON CONFLICT DO NOTHING RETURNING *;
    ELSE
        RETURN QUERY
            SELECT * FROM metadata.organisation as o WHERE o.name = etl_insert_organisation.name;
    END IF;

END;
$$;


--
-- Name: FUNCTION etl_insert_organisation(name text, email text, telephone text, url text, address_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_organisation(name text, email text, telephone text, url text, address_id integer) IS 'Inserts a new organisation into the metadata.organisation table. If the organisation already exists, it returns the existing record.';


--
-- Name: organisation_individual; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.organisation_individual (
    individual_id integer NOT NULL,
    organisation_id integer NOT NULL,
    organisation_unit_id integer,
    role character varying
);


--
-- Name: TABLE organisation_individual; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation_individual IS 'Relation between Individual and Organisation. Captures the object properties hasOrganisationName, org and organisation-name in VCard. In most cases means that the individual works at the organisation in the unit specified.';


--
-- Name: COLUMN organisation_individual.individual_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.individual_id IS 'Foreign key to the related individual.';


--
-- Name: COLUMN organisation_individual.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.organisation_id IS 'Foreign key to the related organisation.';


--
-- Name: COLUMN organisation_individual.organisation_unit_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.organisation_unit_id IS 'Foreign key to the organisational unit associating the individual with the organisation.';


--
-- Name: COLUMN organisation_individual.role; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.role IS 'Role of the individual within the organisation and respective organisational unit, e.g. "director", "secretary".';


--
-- Name: etl_insert_organisation_individual(integer, integer, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_organisation_individual(individual_id integer, organisation_id integer, role text) RETURNS metadata.organisation_individual
    LANGUAGE sql
    AS $$
    INSERT INTO metadata.organisation_individual ( individual_id, organisation_id, role )
    VALUES (etl_insert_organisation_individual.individual_id,
            etl_insert_organisation_individual.organisation_id,
            etl_insert_organisation_individual.role)
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_organisation_individual(individual_id integer, organisation_id integer, role text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_organisation_individual(individual_id integer, organisation_id integer, role text) IS 'Inserts a new organisation_individual into the metadata.organisation_individual table. If the organisation_individual already exists, it returns the existing record.';


--
-- Name: plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.plot (
    plot_code character varying,
    site_id integer NOT NULL,
    altitude numeric,
    time_stamp date,
    map_sheet_code character varying,
    positional_accuracy numeric,
    plot_id integer NOT NULL,
    "position" public.geography(Point,4326),
    CONSTRAINT plot_altitude_check CHECK ((altitude > ('-100'::integer)::numeric)),
    CONSTRAINT plot_altitude_check1 CHECK ((altitude < (8000)::numeric)),
    CONSTRAINT plot_time_stamp_check CHECK ((time_stamp > '1900-01-01'::date))
);


--
-- Name: TABLE plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.plot IS 'Elementary area or location where individual observations are made and/or samples are taken. Plot is the main spatial feature of interest in ISO-28258. Plot has three sub-classes: Borehole, Pit and Surface. Surface features its own table since it has its own properties and a different geometry.';


--
-- Name: COLUMN plot.plot_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.plot_code IS 'Natural key, can be null.';


--
-- Name: COLUMN plot.altitude; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.altitude IS 'Altitude at the plot in metres, if known. Property re-used from GloSIS.';


--
-- Name: COLUMN plot.time_stamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.time_stamp IS 'Time stamp of the plot, if known. Property re-used from GloSIS.';


--
-- Name: COLUMN plot.map_sheet_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.map_sheet_code IS 'Code identifying the map sheet where the plot may be positioned. Property re-used from GloSIS.';


--
-- Name: COLUMN plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.plot_id IS 'Synthetic primary key.';


--
-- Name: COLUMN plot."position"; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot."position" IS 'Geodetic coordinates of the spatial position of the plot. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- Name: etl_insert_plot(text, integer, numeric, text, text, numeric, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text) RETURNS core.plot
    LANGUAGE plpgsql
    AS $$
DECLARE
    result core.plot;
BEGIN
    INSERT INTO core.plot(
            plot_code, site_id, altitude, time_stamp, map_sheet_code, positional_accuracy, "position"
        )
        VALUES (
            plot_code,
            site_id,
            altitude,
            core.safe_parse_date_ddmmyyyy(time_stamp),
            map_sheet_code,
            positional_accuracy,
            ST_GeographyFromText('POINT ('||longitude||' '||latitude||')')
        )
        ON CONFLICT DO NOTHING
        RETURNING * INTO result;

    RETURN result;
END;
$$;


--
-- Name: FUNCTION etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text) IS 'Insert a new plot into the core.plot table. Uses safe_parse_date_ddmmyyyy for date parsing. If the plot already exists, it returns NULL.';


--
-- Name: plot_individual; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.plot_individual (
    plot_id integer NOT NULL,
    individual_id integer NOT NULL
);


--
-- Name: TABLE plot_individual; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.plot_individual IS 'Identifies the individual(s) responsible for surveying a plot';


--
-- Name: COLUMN plot_individual.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot_individual.plot_id IS 'Foreign key to the plot table, identifies the plot surveyed';


--
-- Name: COLUMN plot_individual.individual_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot_individual.individual_id IS 'Foreign key to the individual table, indicates the individual responsible for surveying the plot.';


--
-- Name: etl_insert_plot_individual(integer, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_plot_individual(plot_id integer, individual_id integer) RETURNS core.plot_individual
    LANGUAGE sql
    AS $$
    INSERT INTO core.plot_individual (plot_id, individual_id)
    VALUES (etl_insert_plot_individual.plot_id,
            etl_insert_plot_individual.individual_id)
     ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_plot_individual(plot_id integer, individual_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_plot_individual(plot_id integer, individual_id integer) IS 'Inserts a new plot_individual into the core.plot_individual table. If the plot_individual already exists, it returns the existing record.';


--
-- Name: result_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_element (
    element_id integer NOT NULL,
    property_desc_element_id integer NOT NULL,
    thesaurus_desc_element_id integer NOT NULL
);


--
-- Name: TABLE result_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_element IS 'Descriptive results for the Element feature interest.';


--
-- Name: COLUMN result_desc_element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_element.element_id IS 'Foreign key to the corresponding Element feature of interest.';


--
-- Name: etl_insert_result_desc_element(integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_desc_element(element_id integer, property_uri text, thesaurus_label text) RETURNS core.result_desc_element
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_desc_element (element_id, property_desc_element_id, thesaurus_desc_element_id)
    SELECT etl_insert_result_desc_element.element_id,
           p.property_desc_element_id,
           t.thesaurus_desc_element_id
    FROM core.thesaurus_desc_element t
    INNER JOIN core.observation_desc_element o
        ON t.thesaurus_desc_element_id = o.thesaurus_desc_element_id
    INNER JOIN core.property_desc_element p
        ON o.property_desc_element_id = p.property_desc_element_id
    WHERE p.uri ILIKE '%' || etl_insert_result_desc_element.property_uri
      AND t.label ILIKE etl_insert_result_desc_element.thesaurus_label
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_desc_element(element_id integer, property_uri text, thesaurus_label text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_desc_element(element_id integer, property_uri text, thesaurus_label text) IS 'Inserts a descriptive result for an element. Looks up the observation by property URI
and thesaurus value label. Returns the inserted record or nothing if it already exists.';


--
-- Name: result_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_plot (
    plot_id integer NOT NULL,
    property_desc_plot_id integer NOT NULL,
    thesaurus_desc_plot_id integer NOT NULL
);


--
-- Name: TABLE result_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_plot IS 'Descriptive results for the Plot feature interest.';


--
-- Name: COLUMN result_desc_plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_plot.plot_id IS 'Foreign key to the corresponding Plot feature of interest.';


--
-- Name: etl_insert_result_desc_plot(bigint, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_desc_plot(plot_id bigint, prop text, value text) RETURNS core.result_desc_plot
    LANGUAGE sql PARALLEL SAFE
    AS $$
    INSERT INTO core.result_desc_plot (plot_id, property_desc_plot_id, thesaurus_desc_plot_id)
    SELECT etl_insert_result_desc_plot.plot_id,  -- Feature of interest identifier
            p.property_desc_plot_id,
            t.thesaurus_desc_plot_id
        FROM core.thesaurus_desc_plot t
        LEFT
        JOIN core.observation_desc_plot o
            ON t.thesaurus_desc_plot_id = o.thesaurus_desc_plot_id
        LEFT
        JOIN core.property_desc_plot p
            ON o.property_desc_plot_id = p.property_desc_plot_id
        WHERE p.uri ILIKE '%'||etl_insert_result_desc_plot.prop  -- Property
        AND t.uri ILIKE '%'||etl_insert_result_desc_plot.value    -- Value (thesaurus item)
        ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_desc_plot(plot_id bigint, prop text, value text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_desc_plot(plot_id bigint, prop text, value text) IS 'Inserts a new result_desc_plot into the core.result_desc_plot table. If the result_desc_plot already exists, it returns the existing record.';


--
-- Name: result_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_specimen (
    specimen_id integer NOT NULL,
    property_desc_specimen_id integer NOT NULL,
    thesaurus_desc_specimen_id integer NOT NULL
);


--
-- Name: TABLE result_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_specimen IS 'Descriptive results for the Specimen feature interest.';


--
-- Name: COLUMN result_desc_specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.specimen_id IS 'Foreign key to the corresponding Specimen feature of interest.';


--
-- Name: COLUMN result_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.property_desc_specimen_id IS 'Partial foreign key to the corresponding Observation.';


--
-- Name: COLUMN result_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.thesaurus_desc_specimen_id IS 'Partial foreign key to the corresponding Observation.';


--
-- Name: etl_insert_result_desc_specimen(integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_desc_specimen(specimen_id integer, property_uri text, thesaurus_label text) RETURNS core.result_desc_specimen
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_desc_specimen (specimen_id, property_desc_specimen_id, thesaurus_desc_specimen_id)
    SELECT etl_insert_result_desc_specimen.specimen_id,
           p.property_desc_specimen_id,
           t.thesaurus_desc_specimen_id
    FROM core.thesaurus_desc_specimen t
    INNER JOIN core.observation_desc_specimen o
        ON t.thesaurus_desc_specimen_id = o.thesaurus_desc_specimen_id
    INNER JOIN core.property_desc_specimen p
        ON o.property_desc_specimen_id = p.property_desc_specimen_id
    WHERE p.uri ILIKE '%' || etl_insert_result_desc_specimen.property_uri
      AND t.label ILIKE etl_insert_result_desc_specimen.thesaurus_label
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_desc_specimen(specimen_id integer, property_uri text, thesaurus_label text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_desc_specimen(specimen_id integer, property_uri text, thesaurus_label text) IS 'Inserts a descriptive result for a specimen. Looks up the observation by property URI
and thesaurus value label. Returns the inserted record or nothing if it already exists.';


--
-- Name: result_phys_chem_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_phys_chem_plot (
    result_phys_chem_plot_id integer NOT NULL,
    observation_phys_chem_plot_id integer NOT NULL,
    plot_id integer NOT NULL,
    value numeric NOT NULL,
    organisation_id integer
);


--
-- Name: TABLE result_phys_chem_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_phys_chem_plot IS 'Physio-chemical results for the Plot feature of interest.';


--
-- Name: COLUMN result_phys_chem_plot.result_phys_chem_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_plot.result_phys_chem_plot_id IS 'Synthetic primary key.';


--
-- Name: COLUMN result_phys_chem_plot.observation_phys_chem_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_plot.observation_phys_chem_plot_id IS 'Foreign key to the corresponding physio-chemical observation.';


--
-- Name: COLUMN result_phys_chem_plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_plot.plot_id IS 'Foreign key to the corresponding Plot instance.';


--
-- Name: COLUMN result_phys_chem_plot.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_plot.value IS 'Numerical value resulting from applying the referred observation to the referred plot.';


--
-- Name: COLUMN result_phys_chem_plot.organisation_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_plot.organisation_id IS 'Foreign key to the organisation responsible for the measurement.';


--
-- Name: etl_insert_result_phys_chem_plot(integer, integer, integer, numeric); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_phys_chem_plot(observation_phys_chem_plot_id integer, plot_id integer, organisation_id integer, value numeric) RETURNS core.result_phys_chem_plot
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_phys_chem_plot (observation_phys_chem_plot_id, plot_id, organisation_id, value)
    VALUES (
              etl_insert_result_phys_chem_plot.observation_phys_chem_plot_id,
              etl_insert_result_phys_chem_plot.plot_id,
              etl_insert_result_phys_chem_plot.organisation_id,
              etl_insert_result_phys_chem_plot.value
           )
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_phys_chem_plot(observation_phys_chem_plot_id integer, plot_id integer, organisation_id integer, value numeric); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_phys_chem_plot(observation_phys_chem_plot_id integer, plot_id integer, organisation_id integer, value numeric) IS 'Inserts a new result_phys_chem_plot into the core.result_phys_chem_plot table. If the result_phys_chem_plot already exists, it returns the existing record.';


--
-- Name: result_phys_chem_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_phys_chem_specimen (
    result_phys_chem_specimen_id integer CONSTRAINT result_numerical_specimen_result_numerical_specimen_id_not_null NOT NULL,
    observation_phys_chem_specimen_id integer CONSTRAINT result_numerical_specimen_observation_numerical_specim_not_null NOT NULL,
    specimen_id integer CONSTRAINT result_numerical_specimen_specimen_id_not_null NOT NULL,
    value numeric CONSTRAINT result_numerical_specimen_value_not_null NOT NULL,
    organisation_id integer
);


--
-- Name: TABLE result_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_phys_chem_specimen IS 'Numerical results for the Specimen feature interest.';


--
-- Name: COLUMN result_phys_chem_specimen.result_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.result_phys_chem_specimen_id IS 'Synthetic primary key.';


--
-- Name: COLUMN result_phys_chem_specimen.observation_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.observation_phys_chem_specimen_id IS 'Foreign key to the corresponding numerical observation.';


--
-- Name: COLUMN result_phys_chem_specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.specimen_id IS 'Foreign key to the corresponding Specimen instance.';


--
-- Name: COLUMN result_phys_chem_specimen.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.value IS 'Numerical value resulting from applying the refered observation to the refered specimen.';


--
-- Name: etl_insert_result_phys_chem_specimen(integer, integer, integer, numeric); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_phys_chem_specimen(observation_phys_chem_specimen_id integer, specimen_id integer, organisation_id integer, value numeric) RETURNS core.result_phys_chem_specimen
    LANGUAGE sql PARALLEL SAFE
    AS $$
    INSERT INTO core.result_phys_chem_specimen (observation_phys_chem_specimen_id, specimen_id, organisation_id, value)
    VALUES (
              etl_insert_result_phys_chem_specimen.observation_phys_chem_specimen_id,
              etl_insert_result_phys_chem_specimen.specimen_id,
              etl_insert_result_phys_chem_specimen.organisation_id,
              etl_insert_result_phys_chem_specimen.value
              )
       ON CONFLICT DO NOTHING
       RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_phys_chem_specimen(observation_phys_chem_specimen_id integer, specimen_id integer, organisation_id integer, value numeric); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_phys_chem_specimen(observation_phys_chem_specimen_id integer, specimen_id integer, organisation_id integer, value numeric) IS 'Inserts a new result_phys_chem_specimen into the core.result_phys_chem_specimen table. If the result_phys_chem_specimen already exists, it returns the existing record.';


--
-- Name: result_text_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_text_element (
    result_text_element_id integer NOT NULL,
    observation_text_element_id integer NOT NULL,
    element_id integer NOT NULL,
    value text NOT NULL
);


--
-- Name: TABLE result_text_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_text_element IS 'Free text results for the Element feature of interest.';


--
-- Name: COLUMN result_text_element.result_text_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_element.result_text_element_id IS 'Synthetic primary key';


--
-- Name: COLUMN result_text_element.observation_text_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_element.observation_text_element_id IS 'Foreign key to the corresponding text observation';


--
-- Name: COLUMN result_text_element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_element.element_id IS 'Foreign key to the corresponding Element instance';


--
-- Name: COLUMN result_text_element.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_element.value IS 'The free text result value';


--
-- Name: etl_insert_result_text_element(integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_text_element(element_id integer, property_uri text, value text) RETURNS core.result_text_element
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_text_element (observation_text_element_id, element_id, value)
    SELECT o.observation_text_element_id,
           etl_insert_result_text_element.element_id,
           etl_insert_result_text_element.value
    FROM core.observation_text_element o
    INNER JOIN core.property_text p ON o.property_text_id = p.property_text_id
    WHERE p.uri ILIKE '%' || etl_insert_result_text_element.property_uri
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_text_element(element_id integer, property_uri text, value text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_text_element(element_id integer, property_uri text, value text) IS 'Inserts a free text result for an element. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


--
-- Name: result_text_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_text_plot (
    result_text_plot_id integer NOT NULL,
    observation_text_plot_id integer NOT NULL,
    plot_id integer NOT NULL,
    value text NOT NULL
);


--
-- Name: TABLE result_text_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_text_plot IS 'Free text results for the Plot feature of interest.';


--
-- Name: COLUMN result_text_plot.result_text_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_plot.result_text_plot_id IS 'Synthetic primary key';


--
-- Name: COLUMN result_text_plot.observation_text_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_plot.observation_text_plot_id IS 'Foreign key to the corresponding text observation';


--
-- Name: COLUMN result_text_plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_plot.plot_id IS 'Foreign key to the corresponding Plot instance';


--
-- Name: COLUMN result_text_plot.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_plot.value IS 'The free text result value';


--
-- Name: etl_insert_result_text_plot(integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_text_plot(plot_id integer, property_uri text, value text) RETURNS core.result_text_plot
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_text_plot (observation_text_plot_id, plot_id, value)
    SELECT o.observation_text_plot_id,
           etl_insert_result_text_plot.plot_id,
           etl_insert_result_text_plot.value
    FROM core.observation_text_plot o
    INNER JOIN core.property_text p ON o.property_text_id = p.property_text_id
    WHERE p.uri ILIKE '%' || etl_insert_result_text_plot.property_uri
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_text_plot(plot_id integer, property_uri text, value text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_text_plot(plot_id integer, property_uri text, value text) IS 'Inserts a free text result for a plot. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


--
-- Name: result_text_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_text_specimen (
    result_text_specimen_id integer NOT NULL,
    observation_text_specimen_id integer NOT NULL,
    specimen_id integer NOT NULL,
    value text NOT NULL
);


--
-- Name: TABLE result_text_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_text_specimen IS 'Free text results for the Specimen feature of interest.';


--
-- Name: COLUMN result_text_specimen.result_text_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_specimen.result_text_specimen_id IS 'Synthetic primary key';


--
-- Name: COLUMN result_text_specimen.observation_text_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_specimen.observation_text_specimen_id IS 'Foreign key to the corresponding text observation';


--
-- Name: COLUMN result_text_specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_specimen.specimen_id IS 'Foreign key to the corresponding Specimen instance';


--
-- Name: COLUMN result_text_specimen.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_text_specimen.value IS 'The free text result value';


--
-- Name: etl_insert_result_text_specimen(integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_result_text_specimen(specimen_id integer, property_uri text, value text) RETURNS core.result_text_specimen
    LANGUAGE sql
    AS $$
    INSERT INTO core.result_text_specimen (observation_text_specimen_id, specimen_id, value)
    SELECT o.observation_text_specimen_id,
           etl_insert_result_text_specimen.specimen_id,
           etl_insert_result_text_specimen.value
    FROM core.observation_text_specimen o
    INNER JOIN core.property_text p ON o.property_text_id = p.property_text_id
    WHERE p.uri ILIKE '%' || etl_insert_result_text_specimen.property_uri
    ON CONFLICT DO NOTHING RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_result_text_specimen(specimen_id integer, property_uri text, value text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_text_specimen(specimen_id integer, property_uri text, value text) IS 'Inserts a free text result for a specimen. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


--
-- Name: site; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.site (
    site_code character varying,
    typical_profile integer,
    site_id integer NOT NULL,
    "position" public.geography(Point,4326),
    extent public.geography(Polygon,4326),
    CONSTRAINT site_mandatory_geometry CHECK (((("position" IS NOT NULL) OR (extent IS NOT NULL)) AND (NOT (("position" IS NOT NULL) AND (extent IS NOT NULL)))))
);


--
-- Name: TABLE site; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.site IS 'Defined area which is subject to a soil quality investigation. Site is not a spatial feature of interest, but provides the link between the spatial features of interest (Plot) to the Project. The geometry can either be a location (point) or extent (polygon) but not both at the same time.';


--
-- Name: COLUMN site.site_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.site_code IS 'Natural key, can be null.';


--
-- Name: COLUMN site.typical_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.typical_profile IS 'Foreign key to a profile providing a typical characterisation of this site.';


--
-- Name: COLUMN site.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.site_id IS 'Synthetic primary key.';


--
-- Name: COLUMN site."position"; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site."position" IS 'Geodetic coordinates of the spatial position of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- Name: COLUMN site.extent; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.extent IS 'Site extent expressed with geodetic coordinates of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- Name: etl_insert_site(integer, integer, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_site(site_code integer, typical_profile integer, latitude text, longitude text) RETURNS core.site
    LANGUAGE sql
    AS $$
    INSERT INTO core.site(site_code, typical_profile, "position")
    VALUES (etl_insert_site.site_code,
            etl_insert_site.typical_profile,
            ST_GeographyFromText('POINT ('||longitude||' '||latitude||')')
            )
    ON CONFLICT DO NOTHING
    RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_site(site_code integer, typical_profile integer, latitude text, longitude text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_site(site_code integer, typical_profile integer, latitude text, longitude text) IS 'Inserts a new site into the core.site table. If the site already exists, it returns the existing record.';


--
-- Name: site_project; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.site_project (
    site_id integer NOT NULL,
    project_id integer NOT NULL
);


--
-- Name: TABLE site_project; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.site_project IS 'Many to many relation between Site and Project.';


--
-- Name: COLUMN site_project.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site_project.site_id IS 'Foreign key to Site table';


--
-- Name: COLUMN site_project.project_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site_project.project_id IS 'Foreign key to Project table';


--
-- Name: etl_insert_site_project(integer, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_site_project(site_id integer, project_id integer) RETURNS core.site_project
    LANGUAGE sql
    AS $$
    INSERT INTO core.site_project(site_id, project_id)
    VALUES (etl_insert_site_project.site_id,
            etl_insert_site_project.project_id
            )
    ON CONFLICT DO NOTHING
    RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_site_project(site_id integer, project_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_site_project(site_id integer, project_id integer) IS 'Inserts a new site_project into the core.site_project table. if the site_project already exists, it returns the existing record.';


--
-- Name: specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen (
    code character varying,
    plot_id integer NOT NULL,
    specimen_prep_process_id integer,
    upper_depth integer NOT NULL,
    lower_depth integer NOT NULL,
    organisation_id integer,
    specimen_id integer NOT NULL
);


--
-- Name: TABLE specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen IS 'Soil Specimen is defined in ISO-28258 as: "a subtype of SF_Specimen. Soil Specimen may be taken in the Site, Plot, Profile, or ProfileElement including their subtypes." In this database Specimen is for now only associated to Plot for simplification.';


--
-- Name: COLUMN specimen.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.code IS 'External code used to identify the soil Specimen (if used).';


--
-- Name: COLUMN specimen.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.plot_id IS 'Foreign key to the associated soil Plot';


--
-- Name: COLUMN specimen.specimen_prep_process_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.specimen_prep_process_id IS 'Foreign key to the preparation process used on this soil Specimen.';


--
-- Name: COLUMN specimen.upper_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.upper_depth IS 'Upper depth of this soil specimen in centimetres.';


--
-- Name: COLUMN specimen.lower_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.lower_depth IS 'Lower depth of this soil specimen in centimetres.';


--
-- Name: COLUMN specimen.organisation_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.organisation_id IS 'Individual that is responsible for, or carried out, the process that produced this result.';


--
-- Name: COLUMN specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.specimen_id IS 'Synthetic primary key.';


--
-- Name: etl_insert_specimen(text, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_specimen(specimen_code text, plot_id integer, upper_depth integer, lower_depth integer, organisation_id integer, specimen_prep_process_id integer) RETURNS core.specimen
    LANGUAGE sql
    AS $$
    INSERT INTO core.specimen (code, plot_id, upper_depth, lower_depth, organisation_id, specimen_prep_process_id)
        SELECT  etl_insert_specimen.specimen_code,
                etl_insert_specimen.plot_id,
                etl_insert_specimen.upper_depth,
                etl_insert_specimen.lower_depth,
                etl_insert_specimen.organisation_id,
                etl_insert_specimen.specimen_prep_process_id
    ON CONFLICT DO NOTHING
    RETURNING *;
$$;


--
-- Name: FUNCTION etl_insert_specimen(specimen_code text, plot_id integer, upper_depth integer, lower_depth integer, organisation_id integer, specimen_prep_process_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_specimen(specimen_code text, plot_id integer, upper_depth integer, lower_depth integer, organisation_id integer, specimen_prep_process_id integer) IS 'Inserts a new specimen into the core.specimen table. If the specimen already exists, it returns the existing record.';


--
-- Name: generate_code(text, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.generate_code(input_text text, length integer DEFAULT 4) RETURNS text
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


--
-- Name: FUNCTION generate_code(input_text text, length integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.generate_code(input_text text, length integer) IS 'This function generates a hash-based code given a string. It is used by the bridge_process_observation() function to generate observation code.';


--
-- Name: safe_parse_date_ddmmyyyy(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.safe_parse_date_ddmmyyyy(ts text) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    -- Try to parse as DD/MM/YYYY with leading zero normalization
    IF ts ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
        RETURN TO_DATE(
            REGEXP_REPLACE(
                ts,
                '(\d{1,2})/(\d{1,2})/(\d{4})',
                LPAD('\1', 2, '0') || '/' || LPAD('\2', 2, '0') || '/' || '\3'
            ),
            'DD/MM/YYYY'
        );
    END IF;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    -- Invalid date (e.g., month 14, day 32) -> return NULL
    RETURN NULL;
END;
$_$;


--
-- Name: FUNCTION safe_parse_date_ddmmyyyy(ts text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.safe_parse_date_ddmmyyyy(ts text) IS 'Safely parse a date string in DD/MM/YYYY format. Returns NULL for invalid or unparseable dates instead of raising an error. Useful for bulk ETL operations where date format may vary.';


--
-- Name: is_valid_date(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_date(date_text text, format text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    -- Attempt to cast the date using the provided format
    PERFORM TO_DATE(date_text, format);
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


--
-- Name: FUNCTION is_valid_date(date_text text, format text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_valid_date(date_text text, format text) IS 'Checks if a date string is valid according to a given format.';


--
-- Name: element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.element (
    profile_id integer NOT NULL,
    order_element integer,
    upper_depth integer NOT NULL,
    lower_depth integer NOT NULL,
    type core.element_type NOT NULL,
    element_id integer NOT NULL,
    CONSTRAINT element_check CHECK (((lower_depth > upper_depth) AND (upper_depth <= 200))),
    CONSTRAINT element_order_element_check CHECK ((order_element > 0)),
    CONSTRAINT element_upper_depth_check CHECK ((upper_depth >= 0))
);


--
-- Name: TABLE element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.element IS 'ProfileElement is the super-class of Horizon and Layer, which share the same basic properties. Horizons develop in a layer, which in turn have been developed throught geogenesis or anthropogenic action. Layers can be used to describe common characteristics of a set of adjoining horizons. For the time being no assocation is previewed between Horizon and Layer.';


--
-- Name: COLUMN element.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.profile_id IS 'Reference to the Profile to which this element belongs';


--
-- Name: COLUMN element.order_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.order_element IS 'Order of this element within the Profile';


--
-- Name: COLUMN element.upper_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.upper_depth IS 'Upper depth of this profile element in centimetres.';


--
-- Name: COLUMN element.lower_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.lower_depth IS 'Lower depth of this profile element in centimetres.';


--
-- Name: COLUMN element.type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.type IS 'Type of profile element, Horizon or Layer';


--
-- Name: COLUMN element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.element_id IS 'Synthetic primary key.';


--
-- Name: element_element_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.element ALTER COLUMN element_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.element_element_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: observation_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_element (
    property_desc_element_id integer NOT NULL,
    thesaurus_desc_element_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- Name: TABLE observation_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_element IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN observation_desc_element.property_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_element.property_desc_element_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_desc_element.thesaurus_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_element.thesaurus_desc_element_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- Name: observation_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_plot (
    property_desc_plot_id integer NOT NULL,
    thesaurus_desc_plot_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- Name: TABLE observation_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_plot IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN observation_desc_plot.property_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_plot.property_desc_plot_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_desc_plot.thesaurus_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_plot.thesaurus_desc_plot_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- Name: observation_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_profile (
    property_desc_profile_id integer NOT NULL,
    thesaurus_desc_profile_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- Name: TABLE observation_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_profile IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN observation_desc_profile.property_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_profile.property_desc_profile_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_desc_profile.thesaurus_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_profile.thesaurus_desc_profile_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- Name: observation_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_specimen (
    property_desc_specimen_id integer NOT NULL,
    thesaurus_desc_specimen_id integer NOT NULL,
    procedure_desc_id integer
);


--
-- Name: TABLE observation_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_specimen IS 'Descriptive properties for the Specimen feature of interest';


--
-- Name: COLUMN observation_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_specimen.property_desc_specimen_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_specimen.thesaurus_desc_specimen_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- Name: observation_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_surface (
    property_desc_surface_id integer NOT NULL,
    thesaurus_desc_surface_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- Name: TABLE observation_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN observation_desc_surface.property_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_surface.property_desc_surface_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_desc_surface.thesaurus_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_surface.thesaurus_desc_surface_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- Name: observation_phys_chem_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_phys_chem_specimen (
    observation_phys_chem_specimen_id integer CONSTRAINT observation_numerical_speci_observation_numerical_spec_not_null NOT NULL,
    unit_of_measure_id integer CONSTRAINT observation_numerical_specimen_unit_of_measure_id_not_null NOT NULL,
    value_min numeric,
    value_max numeric,
    property_phys_chem_id integer NOT NULL,
    procedure_phys_chem_id integer NOT NULL
);


--
-- Name: TABLE observation_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_phys_chem_specimen IS 'Numerical observations for the Specimen feature of interest';


--
-- Name: COLUMN observation_phys_chem_specimen.observation_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.observation_phys_chem_specimen_id IS 'Synthetic primary key for the observation';


--
-- Name: COLUMN observation_phys_chem_specimen.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';


--
-- Name: COLUMN observation_phys_chem_specimen.value_min; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: COLUMN observation_phys_chem_specimen.value_max; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: COLUMN observation_phys_chem_specimen.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.property_phys_chem_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_phys_chem_specimen.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';


--
-- Name: observation_numerical_specime_observation_numerical_specime_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_numerical_specime_observation_numerical_specime_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_numerical_specime_observation_numerical_specime_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_numerical_specime_observation_numerical_specime_seq OWNED BY core.observation_phys_chem_specimen.observation_phys_chem_specimen_id;


--
-- Name: observation_phys_chem_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_phys_chem_element (
    observation_phys_chem_element_id integer CONSTRAINT observation_phys_chem_observation_phys_chem_id_not_null NOT NULL,
    property_phys_chem_id integer CONSTRAINT observation_phys_chem_property_phys_chem_id_not_null NOT NULL,
    procedure_phys_chem_id integer CONSTRAINT observation_phys_chem_procedure_phys_chem_id_not_null NOT NULL,
    unit_of_measure_id integer CONSTRAINT observation_phys_chem_unit_of_measure_id_not_null NOT NULL,
    value_min numeric,
    value_max numeric
);


--
-- Name: TABLE observation_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_phys_chem_element IS 'Physio-chemical observations for the Element feature of interest';


--
-- Name: COLUMN observation_phys_chem_element.observation_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.observation_phys_chem_element_id IS 'Synthetic primary key for the observation';


--
-- Name: COLUMN observation_phys_chem_element.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.property_phys_chem_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_phys_chem_element.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';


--
-- Name: COLUMN observation_phys_chem_element.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';


--
-- Name: COLUMN observation_phys_chem_element.value_min; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: COLUMN observation_phys_chem_element.value_max; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: observation_phys_chem_observation_phys_chem_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_phys_chem_observation_phys_chem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_phys_chem_observation_phys_chem_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_phys_chem_observation_phys_chem_id_seq OWNED BY core.observation_phys_chem_element.observation_phys_chem_element_id;


--
-- Name: observation_phys_chem_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_phys_chem_plot (
    observation_phys_chem_plot_id integer CONSTRAINT observation_phys_chem_plot_observation_phys_chem_plot__not_null NOT NULL,
    property_phys_chem_id integer NOT NULL,
    procedure_phys_chem_id integer NOT NULL,
    unit_of_measure_id integer NOT NULL,
    value_min numeric,
    value_max numeric
);


--
-- Name: TABLE observation_phys_chem_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_phys_chem_plot IS 'Physio-chemical observations for the Plot feature of interest';


--
-- Name: COLUMN observation_phys_chem_plot.observation_phys_chem_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.observation_phys_chem_plot_id IS 'Synthetic primary key for the observation';


--
-- Name: COLUMN observation_phys_chem_plot.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.property_phys_chem_id IS 'Foreign key to the corresponding property';


--
-- Name: COLUMN observation_phys_chem_plot.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';


--
-- Name: COLUMN observation_phys_chem_plot.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';


--
-- Name: COLUMN observation_phys_chem_plot.value_min; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: COLUMN observation_phys_chem_plot.value_max; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_plot.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


--
-- Name: observation_phys_chem_plot_observation_phys_chem_plot_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_phys_chem_plot_observation_phys_chem_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq OWNED BY core.observation_phys_chem_plot.observation_phys_chem_plot_id;


--
-- Name: observation_text_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_text_element (
    observation_text_element_id integer NOT NULL,
    property_text_id integer NOT NULL
);


--
-- Name: TABLE observation_text_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_text_element IS 'Text observation definitions for the Element feature of interest. Links a text property.';


--
-- Name: COLUMN observation_text_element.observation_text_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_element.observation_text_element_id IS 'Synthetic primary key';


--
-- Name: COLUMN observation_text_element.property_text_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_element.property_text_id IS 'Foreign key to the corresponding text property';


--
-- Name: observation_text_element_observation_text_element_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_text_element_observation_text_element_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_text_element_observation_text_element_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_text_element_observation_text_element_id_seq OWNED BY core.observation_text_element.observation_text_element_id;


--
-- Name: observation_text_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_text_plot (
    observation_text_plot_id integer NOT NULL,
    property_text_id integer NOT NULL
);


--
-- Name: TABLE observation_text_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_text_plot IS 'Text observation definitions for the Plot feature of interest. Links a text property.';


--
-- Name: COLUMN observation_text_plot.observation_text_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_plot.observation_text_plot_id IS 'Synthetic primary key';


--
-- Name: COLUMN observation_text_plot.property_text_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_plot.property_text_id IS 'Foreign key to the corresponding text property';


--
-- Name: observation_text_plot_observation_text_plot_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_text_plot_observation_text_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_text_plot_observation_text_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_text_plot_observation_text_plot_id_seq OWNED BY core.observation_text_plot.observation_text_plot_id;


--
-- Name: observation_text_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_text_specimen (
    observation_text_specimen_id integer NOT NULL,
    property_text_id integer NOT NULL
);


--
-- Name: TABLE observation_text_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_text_specimen IS 'Text observation definitions for the Specimen feature of interest. Links a text property.';


--
-- Name: COLUMN observation_text_specimen.observation_text_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_specimen.observation_text_specimen_id IS 'Synthetic primary key';


--
-- Name: COLUMN observation_text_specimen.property_text_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_text_specimen.property_text_id IS 'Foreign key to the corresponding text property';


--
-- Name: observation_text_specimen_observation_text_specimen_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.observation_text_specimen_observation_text_specimen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_text_specimen_observation_text_specimen_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_text_specimen_observation_text_specimen_id_seq OWNED BY core.observation_text_specimen.observation_text_specimen_id;


--
-- Name: plot_plot_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.plot ALTER COLUMN plot_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.plot_plot_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: procedure_desc; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.procedure_desc (
    label character varying NOT NULL,
    reference character varying,
    uri character varying NOT NULL,
    procedure_desc_id integer CONSTRAINT procedure_desc_procedure_desc_id_not_null1 NOT NULL
);


--
-- Name: TABLE procedure_desc; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.procedure_desc IS 'Descriptive Procedures for all features of interest. In most cases the procedure is described in a document such as the FAO Guidelines for Soil Description or the World Reference Base of Soil Resources.';


--
-- Name: COLUMN procedure_desc.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.label IS 'Short label for this procedure.';


--
-- Name: COLUMN procedure_desc.reference; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.reference IS 'Long and human readable reference to the publication.';


--
-- Name: COLUMN procedure_desc.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.uri IS 'URI to the corresponding publication, optimally a DOI. Follow this URI for the full definition of the procedure.';


--
-- Name: COLUMN procedure_desc.procedure_desc_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.procedure_desc_id IS 'Synthetic primary key.';


--
-- Name: procedure_desc_procedure_desc_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.procedure_desc ALTER COLUMN procedure_desc_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.procedure_desc_procedure_desc_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: procedure_phys_chem; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.procedure_phys_chem (
    broader_id integer,
    label character varying NOT NULL,
    uri character varying NOT NULL,
    procedure_phys_chem_id integer CONSTRAINT procedure_phys_chem_procedure_phys_chem_id_not_null1 NOT NULL
);


--
-- Name: TABLE procedure_phys_chem; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.procedure_phys_chem IS 'Physio-chemical Procedures for the Profile Element feature of interest';


--
-- Name: COLUMN procedure_phys_chem.broader_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.broader_id IS 'Foreign key to brader procedure in the hierarchy';


--
-- Name: COLUMN procedure_phys_chem.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.label IS 'Short label for this procedure';


--
-- Name: COLUMN procedure_phys_chem.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.uri IS 'URI to the corresponding in a controlled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this procedure';


--
-- Name: COLUMN procedure_phys_chem.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.procedure_phys_chem_id IS 'Synthetic primary key.';


--
-- Name: procedure_phys_chem_procedure_phys_chem_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.procedure_phys_chem ALTER COLUMN procedure_phys_chem_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.procedure_phys_chem_procedure_phys_chem_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.profile (
    profile_code character varying,
    plot_id integer,
    surface_id integer,
    profile_id integer NOT NULL,
    CONSTRAINT site_mandatory_foi CHECK ((((plot_id IS NOT NULL) OR (surface_id IS NOT NULL)) AND (NOT ((plot_id IS NOT NULL) AND (surface_id IS NOT NULL)))))
);


--
-- Name: TABLE profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.profile IS 'An abstract, ordered set of soil horizons and/or layers.';


--
-- Name: COLUMN profile.profile_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.profile_code IS 'Natural primary key, if existing';


--
-- Name: COLUMN profile.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.plot_id IS 'Foreign key to Plot feature of interest';


--
-- Name: COLUMN profile.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.surface_id IS 'Foreign key to Surface feature of interest';


--
-- Name: COLUMN profile.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.profile_id IS 'Synthetic primary key.';


--
-- Name: profile_profile_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.profile ALTER COLUMN profile_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.profile_profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: project; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project (
    name character varying NOT NULL,
    project_id integer NOT NULL
);


--
-- Name: TABLE project; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.project IS 'Provides the context of the data collection as a prerequisite for the proper use or reuse of these data.';


--
-- Name: COLUMN project.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project.name IS 'Natural key with project name.';


--
-- Name: COLUMN project.project_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project.project_id IS 'Synthetic primary key.';


--
-- Name: project_organisation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project_organisation (
    project_id integer NOT NULL,
    organisation_id integer NOT NULL
);


--
-- Name: project_project_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.project ALTER COLUMN project_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.project_project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: project_related; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project_related (
    project_source_id integer NOT NULL,
    project_target_id integer NOT NULL,
    role character varying NOT NULL
);


--
-- Name: TABLE project_related; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.project_related IS 'Relationship between two projects, e.g. project B being a sub-project of project A.';


--
-- Name: COLUMN project_related.project_source_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.project_source_id IS 'Foreign key to source project.';


--
-- Name: COLUMN project_related.project_target_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.project_target_id IS 'Foreign key to targe project.';


--
-- Name: COLUMN project_related.role; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.role IS 'Role of source project in target project. This intended to be a code-list but no codes are given in the standard';


--
-- Name: property_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_element (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_element_id integer CONSTRAINT property_desc_element_property_desc_element_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_element IS 'Descriptive properties for the Element feature of interest';


--
-- Name: COLUMN property_desc_element.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.label IS 'Short label for this property';


--
-- Name: COLUMN property_desc_element.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.uri IS 'URI reference to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';


--
-- Name: COLUMN property_desc_element.property_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.property_desc_element_id IS 'Synthetic primary key.';


--
-- Name: property_desc_element_property_desc_element_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_desc_element ALTER COLUMN property_desc_element_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_desc_element_property_desc_element_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_plot (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_plot_id integer CONSTRAINT property_desc_plot_property_desc_plot_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_plot IS 'Descriptive properties for the Plot feature of interest';


--
-- Name: COLUMN property_desc_plot.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.label IS 'Short label for this property';


--
-- Name: COLUMN property_desc_plot.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- Name: COLUMN property_desc_plot.property_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.property_desc_plot_id IS 'Synthetic primary key.';


--
-- Name: property_desc_plot_property_desc_plot_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_desc_plot ALTER COLUMN property_desc_plot_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_desc_plot_property_desc_plot_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_profile (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_profile_id integer CONSTRAINT property_desc_profile_property_desc_profile_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_profile IS 'Descriptive properties for the Profile feature of interest';


--
-- Name: COLUMN property_desc_profile.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.label IS 'Short label for this property';


--
-- Name: COLUMN property_desc_profile.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- Name: COLUMN property_desc_profile.property_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.property_desc_profile_id IS 'Synthetic primary key.';


--
-- Name: property_desc_profile_property_desc_profile_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_desc_profile ALTER COLUMN property_desc_profile_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_desc_profile_property_desc_profile_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_specimen (
    label character varying NOT NULL,
    uri character varying CONSTRAINT property_desc_specimen_definition_not_null NOT NULL,
    property_desc_specimen_id integer CONSTRAINT property_desc_specimen_property_desc_specimen_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_specimen IS 'Descriptive properties for the Specimen feature of interest';


--
-- Name: COLUMN property_desc_specimen.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.label IS 'Short label for this property';


--
-- Name: COLUMN property_desc_specimen.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.uri IS 'URI reference to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';


--
-- Name: COLUMN property_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.property_desc_specimen_id IS 'Synthetic primary key.';


--
-- Name: property_desc_specimen_property_desc_specimen_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_desc_specimen ALTER COLUMN property_desc_specimen_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_desc_specimen_property_desc_specimen_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_surface (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_surface_id integer CONSTRAINT property_desc_surface_property_desc_surface_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN property_desc_surface.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.label IS 'Short label for this property';


--
-- Name: COLUMN property_desc_surface.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- Name: COLUMN property_desc_surface.property_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.property_desc_surface_id IS 'Synthetic primary key.';


--
-- Name: property_desc_surface_property_desc_surface_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_desc_surface ALTER COLUMN property_desc_surface_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_desc_surface_property_desc_surface_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_phys_chem; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_phys_chem (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_phys_chem_id integer CONSTRAINT property_phys_chem_property_phys_chem_id_not_null1 NOT NULL
);


--
-- Name: TABLE property_phys_chem; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_phys_chem IS 'Physio-chemical properties for the Element feature of interest';


--
-- Name: COLUMN property_phys_chem.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.label IS 'Short label for this property';


--
-- Name: COLUMN property_phys_chem.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- Name: COLUMN property_phys_chem.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.property_phys_chem_id IS 'Synthetic primary key.';


--
-- Name: property_phys_chem_property_phys_chem_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.property_phys_chem ALTER COLUMN property_phys_chem_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.property_phys_chem_property_phys_chem_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: property_text; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_text (
    property_text_id integer NOT NULL,
    label character varying NOT NULL,
    uri character varying
);


--
-- Name: TABLE property_text; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_text IS 'A property whose observations produce free text results (as opposed to controlled vocabulary values). Used for narrative descriptions, notes, or other text content.';


--
-- Name: COLUMN property_text.property_text_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_text.property_text_id IS 'Synthetic primary key';


--
-- Name: COLUMN property_text.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_text.label IS 'Short label for this property';


--
-- Name: COLUMN property_text.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_text.uri IS 'Optional URI to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';


--
-- Name: property_text_property_text_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.property_text_property_text_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: property_text_property_text_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.property_text_property_text_id_seq OWNED BY core.property_text.property_text_id;


--
-- Name: result_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_profile (
    profile_id integer NOT NULL,
    property_desc_profile_id integer NOT NULL,
    thesaurus_desc_profile_id integer NOT NULL
);


--
-- Name: TABLE result_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_profile IS 'Descriptive results for the Profile feature interest.';


--
-- Name: COLUMN result_desc_profile.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_profile.profile_id IS 'Foreign key to the corresponding Profile feature of interest.';


--
-- Name: result_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_surface (
    surface_id integer NOT NULL,
    property_desc_surface_id integer NOT NULL,
    thesaurus_desc_surface_id integer NOT NULL
);


--
-- Name: TABLE result_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_surface IS 'Descriptive results for the Surface feature interest.';


--
-- Name: COLUMN result_desc_surface.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_surface.surface_id IS 'Foreign key to the corresponding Surface feature of interest.';


--
-- Name: result_numerical_specimen_result_numerical_specimen_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_numerical_specimen_result_numerical_specimen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_numerical_specimen_result_numerical_specimen_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_numerical_specimen_result_numerical_specimen_id_seq OWNED BY core.result_phys_chem_specimen.result_phys_chem_specimen_id;


--
-- Name: result_phys_chem_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_phys_chem_element (
    result_phys_chem_element_id integer CONSTRAINT result_phys_chem_result_phys_chem_id_not_null NOT NULL,
    observation_phys_chem_element_id integer CONSTRAINT result_phys_chem_observation_phys_chem_id_not_null NOT NULL,
    element_id integer CONSTRAINT result_phys_chem_element_id_not_null NOT NULL,
    value numeric CONSTRAINT result_phys_chem_value_not_null NOT NULL,
    individual_id integer
);


--
-- Name: TABLE result_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_phys_chem_element IS 'Physio-chemical results for the Element feature interest.';


--
-- Name: COLUMN result_phys_chem_element.result_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.result_phys_chem_element_id IS 'Synthetic primary key.';


--
-- Name: COLUMN result_phys_chem_element.observation_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.observation_phys_chem_element_id IS 'Foreign key to the corresponding physio-chemical observation.';


--
-- Name: COLUMN result_phys_chem_element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.element_id IS 'Foreign key to the corresponding Element instance.';


--
-- Name: COLUMN result_phys_chem_element.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.value IS 'Numerical value resulting from applying the refered observation to the refered profile element.';


--
-- Name: result_phys_chem_plot_result_phys_chem_plot_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_phys_chem_plot_result_phys_chem_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_phys_chem_plot_result_phys_chem_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_phys_chem_plot_result_phys_chem_plot_id_seq OWNED BY core.result_phys_chem_plot.result_phys_chem_plot_id;


--
-- Name: result_phys_chem_result_phys_chem_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_phys_chem_result_phys_chem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_phys_chem_result_phys_chem_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_phys_chem_result_phys_chem_id_seq OWNED BY core.result_phys_chem_element.result_phys_chem_element_id;


--
-- Name: result_text_element_result_text_element_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_text_element_result_text_element_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_text_element_result_text_element_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_text_element_result_text_element_id_seq OWNED BY core.result_text_element.result_text_element_id;


--
-- Name: result_text_plot_result_text_plot_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_text_plot_result_text_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_text_plot_result_text_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_text_plot_result_text_plot_id_seq OWNED BY core.result_text_plot.result_text_plot_id;


--
-- Name: result_text_specimen_result_text_specimen_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.result_text_specimen_result_text_specimen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_text_specimen_result_text_specimen_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_text_specimen_result_text_specimen_id_seq OWNED BY core.result_text_specimen.result_text_specimen_id;


--
-- Name: site_site_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.site ALTER COLUMN site_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.site_site_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: specimen_prep_process; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_prep_process (
    specimen_transport_id integer,
    specimen_storage_id integer,
    definition character varying NOT NULL,
    specimen_prep_process_id integer NOT NULL
);


--
-- Name: TABLE specimen_prep_process; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_prep_process IS 'Describes the preparation process of a soil Specimen. Contains information that does not result from observation(s).';


--
-- Name: COLUMN specimen_prep_process.specimen_transport_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_transport_id IS 'Foreign key for the corresponding mode of transport';


--
-- Name: COLUMN specimen_prep_process.specimen_storage_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_storage_id IS 'Foreign key for the corresponding mode of storage';


--
-- Name: COLUMN specimen_prep_process.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.definition IS 'Further details necessary to define the preparation process.';


--
-- Name: COLUMN specimen_prep_process.specimen_prep_process_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_prep_process_id IS 'Synthetic primary key.';


--
-- Name: specimen_prep_process_specimen_prep_process_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.specimen_prep_process ALTER COLUMN specimen_prep_process_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.specimen_prep_process_specimen_prep_process_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: specimen_specimen_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.specimen ALTER COLUMN specimen_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.specimen_specimen_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: specimen_storage; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_storage (
    label character varying NOT NULL,
    definition character varying,
    specimen_storage_id integer NOT NULL
);


--
-- Name: TABLE specimen_storage; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_storage IS 'Modes of storage of a soil Specimen, part of the Specimen preparation process.';


--
-- Name: COLUMN specimen_storage.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.label IS 'Short label for the storage mode.';


--
-- Name: COLUMN specimen_storage.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.definition IS 'Long definition providing all the necessary details for the storage mode.';


--
-- Name: COLUMN specimen_storage.specimen_storage_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.specimen_storage_id IS 'Synthetic primary key.';


--
-- Name: specimen_storage_specimen_storage_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.specimen_storage ALTER COLUMN specimen_storage_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.specimen_storage_specimen_storage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: specimen_transport; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_transport (
    label character varying NOT NULL,
    definition character varying,
    specimen_transport_id integer NOT NULL
);


--
-- Name: TABLE specimen_transport; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_transport IS 'Modes of transport of a soil Specimen, part of the Specimen preparation process.';


--
-- Name: COLUMN specimen_transport.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.label IS 'Short label for the transport mode.';


--
-- Name: COLUMN specimen_transport.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.definition IS 'Long definition providing all the necessary details for the transport mode.';


--
-- Name: COLUMN specimen_transport.specimen_transport_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.specimen_transport_id IS 'Synthetic primary key.';


--
-- Name: specimen_transport_specimen_transport_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.specimen_transport ALTER COLUMN specimen_transport_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.specimen_transport_specimen_transport_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.surface (
    super_surface_id integer,
    site_id integer NOT NULL,
    shape public.geometry(Polygon,4326),
    time_stamp date,
    surface_id integer NOT NULL
);


--
-- Name: TABLE surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.surface IS 'Surface is a subtype of Plot with a shape geometry. Surfaces may be located within other
surfaces.';


--
-- Name: COLUMN surface.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.site_id IS 'Foreign key to Site table';


--
-- Name: COLUMN surface.shape; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.shape IS 'Site extent expressed with geodetic coordinates of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- Name: COLUMN surface.time_stamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.time_stamp IS 'Time stamp of the plot, if known. Property re-used from GloSIS.';


--
-- Name: COLUMN surface.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.surface_id IS 'Synthetic primary key.';


--
-- Name: surface_individual; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.surface_individual (
    surface_id integer NOT NULL,
    individual_id integer NOT NULL
);


--
-- Name: TABLE surface_individual; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.surface_individual IS 'Identifies the individual(s) responsible for surveying a surface';


--
-- Name: COLUMN surface_individual.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface_individual.surface_id IS 'Foreign key to the surface table, identifies the surface surveyed';


--
-- Name: COLUMN surface_individual.individual_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface_individual.individual_id IS 'Foreign key to the individual table, indicates the individual responsible for surveying the surface.';


--
-- Name: surface_surface_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.surface ALTER COLUMN surface_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.surface_surface_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thesaurus_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_element (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_element_id integer CONSTRAINT thesaurus_desc_element_thesaurus_desc_element_id_not_null1 NOT NULL
);


--
-- Name: TABLE thesaurus_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_element IS 'Vocabularies for the descriptive properties associated with the Element feature of interest. Corresponds to all GloSIS code-lists associated with the Horizon and Layer.';


--
-- Name: COLUMN thesaurus_desc_element.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.label IS 'Short label for this term';


--
-- Name: COLUMN thesaurus_desc_element.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- Name: COLUMN thesaurus_desc_element.thesaurus_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.thesaurus_desc_element_id IS 'Synthetic primary key.';


--
-- Name: thesaurus_desc_element_thesaurus_desc_element_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.thesaurus_desc_element ALTER COLUMN thesaurus_desc_element_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.thesaurus_desc_element_thesaurus_desc_element_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thesaurus_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_plot (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_plot_id integer CONSTRAINT thesaurus_desc_plot_thesaurus_desc_plot_id_not_null1 NOT NULL
);


--
-- Name: TABLE thesaurus_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_plot IS 'Descriptive properties for the Plot feature of interest';


--
-- Name: COLUMN thesaurus_desc_plot.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.label IS 'Short label for this term';


--
-- Name: COLUMN thesaurus_desc_plot.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- Name: COLUMN thesaurus_desc_plot.thesaurus_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.thesaurus_desc_plot_id IS 'Synthetic primary key.';


--
-- Name: thesaurus_desc_plot_thesaurus_desc_plot_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.thesaurus_desc_plot ALTER COLUMN thesaurus_desc_plot_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.thesaurus_desc_plot_thesaurus_desc_plot_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thesaurus_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_profile (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_profile_id integer CONSTRAINT thesaurus_desc_profile_thesaurus_desc_profile_id_not_null1 NOT NULL
);


--
-- Name: TABLE thesaurus_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_profile IS 'Vocabularies for the descriptive properties associated with the Profile feature of interest. Contains the GloSIS code-lists for Profile.';


--
-- Name: COLUMN thesaurus_desc_profile.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.label IS 'Short label for this term';


--
-- Name: COLUMN thesaurus_desc_profile.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- Name: COLUMN thesaurus_desc_profile.thesaurus_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.thesaurus_desc_profile_id IS 'Synthetic primary key.';


--
-- Name: thesaurus_desc_profile_thesaurus_desc_profile_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.thesaurus_desc_profile ALTER COLUMN thesaurus_desc_profile_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.thesaurus_desc_profile_thesaurus_desc_profile_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thesaurus_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_specimen (
    label character varying NOT NULL,
    definition character varying NOT NULL,
    thesaurus_desc_specimen_id integer CONSTRAINT thesaurus_desc_specimen_thesaurus_desc_specimen_id_not_null1 NOT NULL
);


--
-- Name: TABLE thesaurus_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_specimen IS 'Vocabularies for the descriptive properties associated with the Specimen feature of interest. This table is intended to host the code-lists necessary for descriptive observations on Specimen.';


--
-- Name: COLUMN thesaurus_desc_specimen.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.label IS 'Short label for this term';


--
-- Name: COLUMN thesaurus_desc_specimen.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.definition IS 'Full semantic definition of this term, can be a URI to the corresponding code in a controled vocabulary (e.g. GloSIS).';


--
-- Name: COLUMN thesaurus_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.thesaurus_desc_specimen_id IS 'Synthetic primary key.';


--
-- Name: thesaurus_desc_specimen_thesaurus_desc_specimen_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.thesaurus_desc_specimen ALTER COLUMN thesaurus_desc_specimen_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.thesaurus_desc_specimen_thesaurus_desc_specimen_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thesaurus_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_surface (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_surface_id integer CONSTRAINT thesaurus_desc_surface_thesaurus_desc_surface_id_not_null1 NOT NULL
);


--
-- Name: TABLE thesaurus_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- Name: COLUMN thesaurus_desc_surface.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.label IS 'Short label for this term';


--
-- Name: COLUMN thesaurus_desc_surface.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- Name: COLUMN thesaurus_desc_surface.thesaurus_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.thesaurus_desc_surface_id IS 'Synthetic primary key.';


--
-- Name: thesaurus_desc_surface_thesaurus_desc_surface_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.thesaurus_desc_surface ALTER COLUMN thesaurus_desc_surface_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.thesaurus_desc_surface_thesaurus_desc_surface_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: unit_of_measure; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.unit_of_measure (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    unit_of_measure_id integer CONSTRAINT unit_of_measure_unit_of_measure_id_not_null1 NOT NULL
);


--
-- Name: TABLE unit_of_measure; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.unit_of_measure IS 'Unit of measure';


--
-- Name: COLUMN unit_of_measure.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.label IS 'Short label for this unit of measure';


--
-- Name: COLUMN unit_of_measure.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.uri IS 'URI to the corresponding unit of measuree in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this unit of measure';


--
-- Name: COLUMN unit_of_measure.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.unit_of_measure_id IS 'Synthetic primary key.';


--
-- Name: unit_of_measure_unit_of_measure_id_seq1; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.unit_of_measure ALTER COLUMN unit_of_measure_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.unit_of_measure_unit_of_measure_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: address_address_id_seq; Type: SEQUENCE; Schema: metadata; Owner: -
--

ALTER TABLE metadata.address ALTER COLUMN address_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME metadata.address_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: individual_individual_id_seq; Type: SEQUENCE; Schema: metadata; Owner: -
--

ALTER TABLE metadata.individual ALTER COLUMN individual_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME metadata.individual_individual_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: organisation_organisation_id_seq; Type: SEQUENCE; Schema: metadata; Owner: -
--

ALTER TABLE metadata.organisation ALTER COLUMN organisation_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME metadata.organisation_organisation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: organisation_unit; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.organisation_unit (
    name character varying NOT NULL,
    organisation_id integer NOT NULL,
    organisation_unit_id integer NOT NULL
);


--
-- Name: TABLE organisation_unit; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation_unit IS 'Captures the data property organisation-unit and object property hasOrganisationUnit in VCard. Defines the internal structure of the organisation, apart from the departmental hierarchy.';


--
-- Name: COLUMN organisation_unit.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.name IS 'Name of the organisation unit.';


--
-- Name: COLUMN organisation_unit.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.organisation_id IS 'Foreign key to the enclosing organisation, in case of a department or division of a larger organisation.';


--
-- Name: COLUMN organisation_unit.organisation_unit_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.organisation_unit_id IS 'Synthetic primary key.';


--
-- Name: organisation_unit_organisation_unit_id_seq; Type: SEQUENCE; Schema: metadata; Owner: -
--

ALTER TABLE metadata.organisation_unit ALTER COLUMN organisation_unit_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME metadata.organisation_unit_organisation_unit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: observation_phys_chem_element observation_phys_chem_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element ALTER COLUMN observation_phys_chem_element_id SET DEFAULT nextval('core.observation_phys_chem_observation_phys_chem_id_seq'::regclass);


--
-- Name: observation_phys_chem_plot observation_phys_chem_plot_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot ALTER COLUMN observation_phys_chem_plot_id SET DEFAULT nextval('core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq'::regclass);


--
-- Name: observation_phys_chem_specimen observation_phys_chem_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen ALTER COLUMN observation_phys_chem_specimen_id SET DEFAULT nextval('core.observation_numerical_specime_observation_numerical_specime_seq'::regclass);


--
-- Name: observation_text_element observation_text_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_element ALTER COLUMN observation_text_element_id SET DEFAULT nextval('core.observation_text_element_observation_text_element_id_seq'::regclass);


--
-- Name: observation_text_plot observation_text_plot_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_plot ALTER COLUMN observation_text_plot_id SET DEFAULT nextval('core.observation_text_plot_observation_text_plot_id_seq'::regclass);


--
-- Name: observation_text_specimen observation_text_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_specimen ALTER COLUMN observation_text_specimen_id SET DEFAULT nextval('core.observation_text_specimen_observation_text_specimen_id_seq'::regclass);


--
-- Name: property_text property_text_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_text ALTER COLUMN property_text_id SET DEFAULT nextval('core.property_text_property_text_id_seq'::regclass);


--
-- Name: result_phys_chem_element result_phys_chem_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element ALTER COLUMN result_phys_chem_element_id SET DEFAULT nextval('core.result_phys_chem_result_phys_chem_id_seq'::regclass);


--
-- Name: result_phys_chem_plot result_phys_chem_plot_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot ALTER COLUMN result_phys_chem_plot_id SET DEFAULT nextval('core.result_phys_chem_plot_result_phys_chem_plot_id_seq'::regclass);


--
-- Name: result_phys_chem_specimen result_phys_chem_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen ALTER COLUMN result_phys_chem_specimen_id SET DEFAULT nextval('core.result_numerical_specimen_result_numerical_specimen_id_seq'::regclass);


--
-- Name: result_text_element result_text_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_element ALTER COLUMN result_text_element_id SET DEFAULT nextval('core.result_text_element_result_text_element_id_seq'::regclass);


--
-- Name: result_text_plot result_text_plot_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_plot ALTER COLUMN result_text_plot_id SET DEFAULT nextval('core.result_text_plot_result_text_plot_id_seq'::regclass);


--
-- Name: result_text_specimen result_text_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_specimen ALTER COLUMN result_text_specimen_id SET DEFAULT nextval('core.result_text_specimen_result_text_specimen_id_seq'::regclass);


--
-- Name: element element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT element_pkey PRIMARY KEY (element_id);


--
-- Name: observation_desc_element observation_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT observation_desc_element_pkey PRIMARY KEY (property_desc_element_id, thesaurus_desc_element_id);


--
-- Name: observation_desc_element observation_desc_element_property_desc_element_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT observation_desc_element_property_desc_element_id_thesaurus_key UNIQUE (property_desc_element_id, thesaurus_desc_element_id);


--
-- Name: observation_desc_plot observation_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT observation_desc_plot_pkey PRIMARY KEY (property_desc_plot_id, thesaurus_desc_plot_id);


--
-- Name: observation_desc_plot observation_desc_plot_property_desc_plot_id_thesaurus_desc__key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT observation_desc_plot_property_desc_plot_id_thesaurus_desc__key UNIQUE (property_desc_plot_id, thesaurus_desc_plot_id);


--
-- Name: observation_desc_profile observation_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT observation_desc_profile_pkey PRIMARY KEY (property_desc_profile_id, thesaurus_desc_profile_id);


--
-- Name: observation_desc_profile observation_desc_profile_property_desc_profile_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT observation_desc_profile_property_desc_profile_id_thesaurus_key UNIQUE (property_desc_profile_id, thesaurus_desc_profile_id);


--
-- Name: observation_desc_specimen observation_desc_specimen_property_desc_specimen_id_thesaur_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT observation_desc_specimen_property_desc_specimen_id_thesaur_key UNIQUE (property_desc_specimen_id, thesaurus_desc_specimen_id);


--
-- Name: observation_desc_surface observation_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT observation_desc_surface_pkey PRIMARY KEY (property_desc_surface_id, thesaurus_desc_surface_id);


--
-- Name: observation_desc_surface observation_desc_surface_property_desc_surface_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT observation_desc_surface_property_desc_surface_id_thesaurus_key UNIQUE (property_desc_surface_id, thesaurus_desc_surface_id);


--
-- Name: observation_phys_chem_specimen observation_numerical_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT observation_numerical_specimen_pkey PRIMARY KEY (observation_phys_chem_specimen_id);


--
-- Name: observation_phys_chem_element observation_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT observation_phys_chem_pkey PRIMARY KEY (observation_phys_chem_element_id);


--
-- Name: observation_phys_chem_plot observation_phys_chem_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot
    ADD CONSTRAINT observation_phys_chem_plot_pkey PRIMARY KEY (observation_phys_chem_plot_id);


--
-- Name: observation_phys_chem_plot observation_phys_chem_plot_property_procedure_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot
    ADD CONSTRAINT observation_phys_chem_plot_property_procedure_unq UNIQUE (property_phys_chem_id, procedure_phys_chem_id);


--
-- Name: observation_phys_chem_element observation_phys_chem_property_phys_chem_id_procedure_phys__key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT observation_phys_chem_property_phys_chem_id_procedure_phys__key UNIQUE (property_phys_chem_id, procedure_phys_chem_id);


--
-- Name: observation_phys_chem_specimen observation_phys_chem_specimen_property_phys_chem_id_procedure_; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT observation_phys_chem_specimen_property_phys_chem_id_procedure_ UNIQUE (property_phys_chem_id, procedure_phys_chem_id);


--
-- Name: observation_text_element observation_text_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_element
    ADD CONSTRAINT observation_text_element_pkey PRIMARY KEY (observation_text_element_id);


--
-- Name: observation_text_plot observation_text_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_plot
    ADD CONSTRAINT observation_text_plot_pkey PRIMARY KEY (observation_text_plot_id);


--
-- Name: observation_text_specimen observation_text_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_specimen
    ADD CONSTRAINT observation_text_specimen_pkey PRIMARY KEY (observation_text_specimen_id);


--
-- Name: plot_individual plot_individual_plot_id_individual_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT plot_individual_plot_id_individual_id_key UNIQUE (plot_id, individual_id);


--
-- Name: plot plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT plot_pkey PRIMARY KEY (plot_id);


--
-- Name: procedure_desc procedure_desc_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT procedure_desc_pkey PRIMARY KEY (procedure_desc_id);


--
-- Name: procedure_desc procedure_desc_uri_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT procedure_desc_uri_key UNIQUE (uri);


--
-- Name: procedure_phys_chem procedure_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT procedure_phys_chem_pkey PRIMARY KEY (procedure_phys_chem_id);


--
-- Name: profile profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT profile_pkey PRIMARY KEY (profile_id);


--
-- Name: project project_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT project_name_key UNIQUE (name);


--
-- Name: project_organisation project_organisation_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT project_organisation_pkey PRIMARY KEY (project_id, organisation_id);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (project_id);


--
-- Name: project_related project_related_project_source_id_project_target_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT project_related_project_source_id_project_target_id_key UNIQUE (project_source_id, project_target_id);


--
-- Name: property_desc_element property_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT property_desc_element_pkey PRIMARY KEY (property_desc_element_id);


--
-- Name: property_desc_plot property_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT property_desc_plot_pkey PRIMARY KEY (property_desc_plot_id);


--
-- Name: property_desc_profile property_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT property_desc_profile_pkey PRIMARY KEY (property_desc_profile_id);


--
-- Name: property_desc_specimen property_desc_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_specimen
    ADD CONSTRAINT property_desc_specimen_pkey PRIMARY KEY (property_desc_specimen_id);


--
-- Name: property_desc_surface property_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT property_desc_surface_pkey PRIMARY KEY (property_desc_surface_id);


--
-- Name: property_phys_chem property_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT property_phys_chem_pkey PRIMARY KEY (property_phys_chem_id);


--
-- Name: property_text property_text_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_text
    ADD CONSTRAINT property_text_pkey PRIMARY KEY (property_text_id);


--
-- Name: result_desc_specimen result_desc_specimen_specimen_id_property_desc_specimen_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT result_desc_specimen_specimen_id_property_desc_specimen_id_key UNIQUE (specimen_id, property_desc_specimen_id);


--
-- Name: result_phys_chem_specimen result_numerical_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_pkey PRIMARY KEY (result_phys_chem_specimen_id);


--
-- Name: result_phys_chem_specimen result_numerical_specimen_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_unq UNIQUE (observation_phys_chem_specimen_id, specimen_id);


--
-- Name: result_phys_chem_specimen result_numerical_specimen_unq_foi_obs; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_unq_foi_obs UNIQUE (specimen_id, observation_phys_chem_specimen_id);


--
-- Name: result_phys_chem_element result_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_pkey PRIMARY KEY (result_phys_chem_element_id);


--
-- Name: result_phys_chem_plot result_phys_chem_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT result_phys_chem_plot_pkey PRIMARY KEY (result_phys_chem_plot_id);


--
-- Name: result_phys_chem_plot result_phys_chem_plot_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT result_phys_chem_plot_unq UNIQUE (observation_phys_chem_plot_id, plot_id);


--
-- Name: result_phys_chem_plot result_phys_chem_plot_unq_foi_obs; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT result_phys_chem_plot_unq_foi_obs UNIQUE (plot_id, observation_phys_chem_plot_id);


--
-- Name: result_phys_chem_element result_phys_chem_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_unq UNIQUE (observation_phys_chem_element_id, element_id);


--
-- Name: result_phys_chem_element result_phys_chem_unq_foi_obs; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_unq_foi_obs UNIQUE (element_id, observation_phys_chem_element_id);


--
-- Name: result_text_element result_text_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_element
    ADD CONSTRAINT result_text_element_pkey PRIMARY KEY (result_text_element_id);


--
-- Name: result_text_plot result_text_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_plot
    ADD CONSTRAINT result_text_plot_pkey PRIMARY KEY (result_text_plot_id);


--
-- Name: result_text_specimen result_text_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_specimen
    ADD CONSTRAINT result_text_specimen_pkey PRIMARY KEY (result_text_specimen_id);


--
-- Name: site site_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (site_id);


--
-- Name: site_project site_project_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT site_project_pkey PRIMARY KEY (site_id, project_id);


--
-- Name: specimen specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT specimen_pkey PRIMARY KEY (specimen_id);


--
-- Name: specimen_prep_process specimen_prep_process_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT specimen_prep_process_definition_key UNIQUE (definition);


--
-- Name: specimen_prep_process specimen_prep_process_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT specimen_prep_process_pkey PRIMARY KEY (specimen_prep_process_id);


--
-- Name: specimen_storage specimen_storage_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT specimen_storage_definition_key UNIQUE (definition);


--
-- Name: specimen_storage specimen_storage_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT specimen_storage_pkey PRIMARY KEY (specimen_storage_id);


--
-- Name: specimen_transport specimen_transport_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT specimen_transport_definition_key UNIQUE (definition);


--
-- Name: specimen_transport specimen_transport_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT specimen_transport_pkey PRIMARY KEY (specimen_transport_id);


--
-- Name: surface_individual surface_individual_surface_id_individual_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT surface_individual_surface_id_individual_id_key UNIQUE (surface_id, individual_id);


--
-- Name: surface surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT surface_pkey PRIMARY KEY (surface_id);


--
-- Name: thesaurus_desc_element thesaurus_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_element
    ADD CONSTRAINT thesaurus_desc_element_pkey PRIMARY KEY (thesaurus_desc_element_id);


--
-- Name: thesaurus_desc_plot thesaurus_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_plot
    ADD CONSTRAINT thesaurus_desc_plot_pkey PRIMARY KEY (thesaurus_desc_plot_id);


--
-- Name: thesaurus_desc_profile thesaurus_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_profile
    ADD CONSTRAINT thesaurus_desc_profile_pkey PRIMARY KEY (thesaurus_desc_profile_id);


--
-- Name: thesaurus_desc_specimen thesaurus_desc_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_specimen
    ADD CONSTRAINT thesaurus_desc_specimen_pkey PRIMARY KEY (thesaurus_desc_specimen_id);


--
-- Name: thesaurus_desc_surface thesaurus_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_surface
    ADD CONSTRAINT thesaurus_desc_surface_pkey PRIMARY KEY (thesaurus_desc_surface_id);


--
-- Name: unit_of_measure unit_of_measure_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.unit_of_measure
    ADD CONSTRAINT unit_of_measure_pkey PRIMARY KEY (unit_of_measure_id);


--
-- Name: element unq_element_profile_order_element; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT unq_element_profile_order_element UNIQUE (profile_id, order_element);


--
-- Name: observation_text_element unq_observation_text_element_property; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_element
    ADD CONSTRAINT unq_observation_text_element_property UNIQUE (property_text_id);


--
-- Name: observation_text_plot unq_observation_text_plot_property; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_plot
    ADD CONSTRAINT unq_observation_text_plot_property UNIQUE (property_text_id);


--
-- Name: observation_text_specimen unq_observation_text_specimen_property; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_specimen
    ADD CONSTRAINT unq_observation_text_specimen_property UNIQUE (property_text_id);


--
-- Name: plot unq_plot_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT unq_plot_code UNIQUE (plot_code);


--
-- Name: procedure_desc unq_procedure_desc_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT unq_procedure_desc_label UNIQUE (label);


--
-- Name: procedure_phys_chem unq_procedure_phys_chem_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT unq_procedure_phys_chem_label UNIQUE (label);


--
-- Name: procedure_phys_chem unq_procedure_phys_chem_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT unq_procedure_phys_chem_uri UNIQUE (uri);


--
-- Name: profile unq_profile_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT unq_profile_code UNIQUE (profile_code);


--
-- Name: project unq_project_name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT unq_project_name UNIQUE (name);


--
-- Name: property_desc_element unq_property_desc_element_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT unq_property_desc_element_label UNIQUE (label);


--
-- Name: property_desc_element unq_property_desc_element_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT unq_property_desc_element_uri UNIQUE (uri);


--
-- Name: property_desc_plot unq_property_desc_plot_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT unq_property_desc_plot_label UNIQUE (label);


--
-- Name: property_desc_plot unq_property_desc_plot_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT unq_property_desc_plot_uri UNIQUE (uri);


--
-- Name: property_desc_profile unq_property_desc_profile_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT unq_property_desc_profile_label UNIQUE (label);


--
-- Name: property_desc_profile unq_property_desc_profile_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT unq_property_desc_profile_uri UNIQUE (uri);


--
-- Name: property_desc_specimen unq_property_desc_specimen_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_specimen
    ADD CONSTRAINT unq_property_desc_specimen_label UNIQUE (label);


--
-- Name: property_desc_surface unq_property_desc_surface_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT unq_property_desc_surface_label UNIQUE (label);


--
-- Name: property_desc_surface unq_property_desc_surface_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT unq_property_desc_surface_uri UNIQUE (uri);


--
-- Name: property_phys_chem unq_property_phys_chem_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT unq_property_phys_chem_label UNIQUE (label);


--
-- Name: property_phys_chem unq_property_phys_chem_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT unq_property_phys_chem_uri UNIQUE (uri);


--
-- Name: property_text unq_property_text_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_text
    ADD CONSTRAINT unq_property_text_label UNIQUE (label);


--
-- Name: property_text unq_property_text_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_text
    ADD CONSTRAINT unq_property_text_uri UNIQUE (uri);


--
-- Name: result_desc_element unq_result_desc_element; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT unq_result_desc_element UNIQUE (element_id, property_desc_element_id);


--
-- Name: result_desc_plot unq_result_desc_plot; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT unq_result_desc_plot UNIQUE (plot_id, property_desc_plot_id);


--
-- Name: result_desc_profile unq_result_desc_profile; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT unq_result_desc_profile UNIQUE (profile_id, property_desc_profile_id);


--
-- Name: result_desc_surface unq_result_desc_surface; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT unq_result_desc_surface UNIQUE (surface_id, property_desc_surface_id);


--
-- Name: result_text_element unq_result_text_element; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_element
    ADD CONSTRAINT unq_result_text_element UNIQUE (observation_text_element_id, element_id);


--
-- Name: result_text_plot unq_result_text_plot; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_plot
    ADD CONSTRAINT unq_result_text_plot UNIQUE (observation_text_plot_id, plot_id);


--
-- Name: result_text_specimen unq_result_text_specimen; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_specimen
    ADD CONSTRAINT unq_result_text_specimen UNIQUE (observation_text_specimen_id, specimen_id);


--
-- Name: site unq_site_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT unq_site_code UNIQUE (site_code);


--
-- Name: specimen_storage unq_specimen_storage_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT unq_specimen_storage_label UNIQUE (label);


--
-- Name: specimen_transport unq_specimen_transport_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT unq_specimen_transport_label UNIQUE (label);


--
-- Name: surface unq_surface_super; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT unq_surface_super UNIQUE (surface_id, super_surface_id);


--
-- Name: thesaurus_desc_element unq_thesaurus_desc_element_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_element
    ADD CONSTRAINT unq_thesaurus_desc_element_uri UNIQUE (uri);


--
-- Name: thesaurus_desc_plot unq_thesaurus_desc_plot_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_plot
    ADD CONSTRAINT unq_thesaurus_desc_plot_uri UNIQUE (uri);


--
-- Name: thesaurus_desc_profile unq_thesaurus_desc_profile_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_profile
    ADD CONSTRAINT unq_thesaurus_desc_profile_uri UNIQUE (uri);


--
-- Name: thesaurus_desc_specimen unq_thesaurus_desc_specimen_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_specimen
    ADD CONSTRAINT unq_thesaurus_desc_specimen_label UNIQUE (label);


--
-- Name: thesaurus_desc_surface unq_thesaurus_desc_surface_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_surface
    ADD CONSTRAINT unq_thesaurus_desc_surface_uri UNIQUE (uri);


--
-- Name: unit_of_measure unq_unit_of_measure_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.unit_of_measure
    ADD CONSTRAINT unq_unit_of_measure_uri UNIQUE (uri);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (address_id);


--
-- Name: individual individual_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT individual_pkey PRIMARY KEY (individual_id);


--
-- Name: organisation_individual organisation_individual_individual_id_organisation_id_key; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT organisation_individual_individual_id_organisation_id_key UNIQUE (individual_id, organisation_id);


--
-- Name: organisation organisation_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT organisation_pkey PRIMARY KEY (organisation_id);


--
-- Name: organisation_unit organisation_unit_name_organisation_id_key; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT organisation_unit_name_organisation_id_key UNIQUE (name, organisation_id);


--
-- Name: organisation_unit organisation_unit_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT organisation_unit_pkey PRIMARY KEY (organisation_unit_id);


--
-- Name: individual unique_email; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT unique_email UNIQUE (email);


--
-- Name: individual unique_name; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT unique_name UNIQUE (name);


--
-- Name: core_plot_position_geog_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX core_plot_position_geog_idx ON core.plot USING gist ("position");


--
-- Name: result_phys_chem_element trg_check_result_value; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_check_result_value BEFORE INSERT OR UPDATE ON core.result_phys_chem_element FOR EACH ROW EXECUTE FUNCTION core.check_result_value();


--
-- Name: TRIGGER trg_check_result_value ON result_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TRIGGER trg_check_result_value ON core.result_phys_chem_element IS 'Verifies if the value assigned to the result is valid. See the function core.ceck_result_valus function for implementation.';


--
-- Name: result_phys_chem_plot trg_check_result_value_plot; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_check_result_value_plot BEFORE INSERT OR UPDATE ON core.result_phys_chem_plot FOR EACH ROW EXECUTE FUNCTION core.check_result_value_plot();


--
-- Name: TRIGGER trg_check_result_value_plot ON result_phys_chem_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TRIGGER trg_check_result_value_plot ON core.result_phys_chem_plot IS 'Verifies if the value assigned to the result is valid. See the function core.check_result_value_plot function for implementation.';


--
-- Name: result_phys_chem_specimen trg_check_result_value_specimen; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_check_result_value_specimen BEFORE INSERT OR UPDATE ON core.result_phys_chem_specimen FOR EACH ROW EXECUTE FUNCTION core.check_result_value_specimen();


--
-- Name: TRIGGER trg_check_result_value_specimen ON result_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TRIGGER trg_check_result_value_specimen ON core.result_phys_chem_specimen IS 'Verifies if the value assigned to the result is valid. See the function core.ceck_result_value function for implementation.';


--
-- Name: procedure_phys_chem fk_broader; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT fk_broader FOREIGN KEY (broader_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- Name: result_desc_element fk_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT fk_element FOREIGN KEY (element_id) REFERENCES core.element(element_id) ON DELETE CASCADE;


--
-- Name: result_phys_chem_element fk_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_element FOREIGN KEY (element_id) REFERENCES core.element(element_id) ON DELETE CASCADE;


--
-- Name: result_text_element fk_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_element
    ADD CONSTRAINT fk_element FOREIGN KEY (element_id) REFERENCES core.element(element_id) ON DELETE CASCADE;


--
-- Name: plot_individual fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- Name: result_phys_chem_element fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- Name: surface_individual fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- Name: result_phys_chem_specimen fk_observation_numerical_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_observation_numerical_specimen FOREIGN KEY (observation_phys_chem_specimen_id) REFERENCES core.observation_phys_chem_specimen(observation_phys_chem_specimen_id);


--
-- Name: result_phys_chem_element fk_observation_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_observation_phys_chem FOREIGN KEY (observation_phys_chem_element_id) REFERENCES core.observation_phys_chem_element(observation_phys_chem_element_id);


--
-- Name: result_phys_chem_plot fk_observation_phys_chem_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT fk_observation_phys_chem_plot FOREIGN KEY (observation_phys_chem_plot_id) REFERENCES core.observation_phys_chem_plot(observation_phys_chem_plot_id);


--
-- Name: result_text_element fk_observation_text_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_element
    ADD CONSTRAINT fk_observation_text_element FOREIGN KEY (observation_text_element_id) REFERENCES core.observation_text_element(observation_text_element_id);


--
-- Name: result_text_plot fk_observation_text_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_plot
    ADD CONSTRAINT fk_observation_text_plot FOREIGN KEY (observation_text_plot_id) REFERENCES core.observation_text_plot(observation_text_plot_id);


--
-- Name: result_text_specimen fk_observation_text_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_specimen
    ADD CONSTRAINT fk_observation_text_specimen FOREIGN KEY (observation_text_specimen_id) REFERENCES core.observation_text_specimen(observation_text_specimen_id);


--
-- Name: project_organisation fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: result_phys_chem_plot fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: result_phys_chem_specimen fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: specimen fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: plot_individual fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: profile fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: result_desc_plot fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: result_phys_chem_plot fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_plot
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: result_text_plot fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_plot
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: specimen fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- Name: observation_desc_element fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- Name: observation_desc_plot fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- Name: observation_desc_profile fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- Name: observation_desc_specimen fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- Name: observation_desc_surface fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- Name: observation_phys_chem_element fk_procedure_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- Name: observation_phys_chem_plot fk_procedure_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot
    ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- Name: observation_phys_chem_specimen fk_procedure_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- Name: element fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id) REFERENCES core.profile(profile_id) ON DELETE CASCADE;


--
-- Name: result_desc_profile fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id) REFERENCES core.profile(profile_id) ON DELETE CASCADE;


--
-- Name: site fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT fk_profile FOREIGN KEY (typical_profile) REFERENCES core.profile(profile_id);


--
-- Name: project_organisation fk_project; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES core.project(project_id);


--
-- Name: site_project fk_project; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES core.project(project_id);


--
-- Name: project_related fk_project_source; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT fk_project_source FOREIGN KEY (project_source_id) REFERENCES core.project(project_id);


--
-- Name: project_related fk_project_target; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT fk_project_target FOREIGN KEY (project_target_id) REFERENCES core.project(project_id);


--
-- Name: observation_desc_element fk_property_desc_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_property_desc_element FOREIGN KEY (property_desc_element_id) REFERENCES core.property_desc_element(property_desc_element_id);


--
-- Name: observation_desc_plot fk_property_desc_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_property_desc_plot FOREIGN KEY (property_desc_plot_id) REFERENCES core.property_desc_plot(property_desc_plot_id);


--
-- Name: observation_desc_profile fk_property_desc_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_property_desc_profile FOREIGN KEY (property_desc_profile_id) REFERENCES core.property_desc_profile(property_desc_profile_id);


--
-- Name: observation_desc_specimen fk_property_desc_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_property_desc_specimen FOREIGN KEY (property_desc_specimen_id) REFERENCES core.property_desc_specimen(property_desc_specimen_id);


--
-- Name: observation_desc_surface fk_property_desc_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_property_desc_surface FOREIGN KEY (property_desc_surface_id) REFERENCES core.property_desc_surface(property_desc_surface_id);


--
-- Name: observation_phys_chem_element fk_property_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id) REFERENCES core.property_phys_chem(property_phys_chem_id);


--
-- Name: observation_phys_chem_plot fk_property_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot
    ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id) REFERENCES core.property_phys_chem(property_phys_chem_id);


--
-- Name: observation_phys_chem_specimen fk_property_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id) REFERENCES core.property_phys_chem(property_phys_chem_id);


--
-- Name: observation_text_element fk_property_text; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_element
    ADD CONSTRAINT fk_property_text FOREIGN KEY (property_text_id) REFERENCES core.property_text(property_text_id);


--
-- Name: observation_text_plot fk_property_text; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_plot
    ADD CONSTRAINT fk_property_text FOREIGN KEY (property_text_id) REFERENCES core.property_text(property_text_id);


--
-- Name: observation_text_specimen fk_property_text; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_text_specimen
    ADD CONSTRAINT fk_property_text FOREIGN KEY (property_text_id) REFERENCES core.property_text(property_text_id);


--
-- Name: plot fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- Name: site_project fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- Name: surface fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- Name: result_desc_specimen fk_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id) REFERENCES core.specimen(specimen_id) ON DELETE CASCADE;


--
-- Name: result_phys_chem_specimen fk_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id) REFERENCES core.specimen(specimen_id) ON DELETE CASCADE;


--
-- Name: result_text_specimen fk_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_text_specimen
    ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id) REFERENCES core.specimen(specimen_id) ON DELETE CASCADE;


--
-- Name: specimen fk_specimen_prep_process; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_specimen_prep_process FOREIGN KEY (specimen_prep_process_id) REFERENCES core.specimen_prep_process(specimen_prep_process_id);


--
-- Name: specimen_prep_process fk_specimen_storage; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT fk_specimen_storage FOREIGN KEY (specimen_storage_id) REFERENCES core.specimen_storage(specimen_storage_id);


--
-- Name: specimen_prep_process fk_specimen_transport; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT fk_specimen_transport FOREIGN KEY (specimen_transport_id) REFERENCES core.specimen_transport(specimen_transport_id);


--
-- Name: profile fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- Name: result_desc_surface fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- Name: surface fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT fk_surface FOREIGN KEY (super_surface_id) REFERENCES core.surface(surface_id);


--
-- Name: surface_individual fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- Name: observation_desc_element fk_thesaurus_desc_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_thesaurus_desc_element FOREIGN KEY (thesaurus_desc_element_id) REFERENCES core.thesaurus_desc_element(thesaurus_desc_element_id);


--
-- Name: observation_desc_plot fk_thesaurus_desc_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_thesaurus_desc_plot FOREIGN KEY (thesaurus_desc_plot_id) REFERENCES core.thesaurus_desc_plot(thesaurus_desc_plot_id);


--
-- Name: observation_desc_profile fk_thesaurus_desc_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_thesaurus_desc_profile FOREIGN KEY (thesaurus_desc_profile_id) REFERENCES core.thesaurus_desc_profile(thesaurus_desc_profile_id);


--
-- Name: observation_desc_specimen fk_thesaurus_desc_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_thesaurus_desc_specimen FOREIGN KEY (thesaurus_desc_specimen_id) REFERENCES core.thesaurus_desc_specimen(thesaurus_desc_specimen_id);


--
-- Name: observation_desc_surface fk_thesaurus_desc_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_thesaurus_desc_surface FOREIGN KEY (thesaurus_desc_surface_id) REFERENCES core.thesaurus_desc_surface(thesaurus_desc_surface_id);


--
-- Name: observation_phys_chem_element fk_unit_of_measure; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id) REFERENCES core.unit_of_measure(unit_of_measure_id);


--
-- Name: observation_phys_chem_plot fk_unit_of_measure; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_plot
    ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id) REFERENCES core.unit_of_measure(unit_of_measure_id);


--
-- Name: observation_phys_chem_specimen fk_unit_of_measure; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id) REFERENCES core.unit_of_measure(unit_of_measure_id);


--
-- Name: result_desc_element result_desc_element_property_desc_element_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT result_desc_element_property_desc_element_id_thesaurus_des_fkey FOREIGN KEY (property_desc_element_id, thesaurus_desc_element_id) REFERENCES core.observation_desc_element(property_desc_element_id, thesaurus_desc_element_id);


--
-- Name: result_desc_plot result_desc_plot_property_desc_plot_id_thesaurus_desc_plot_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT result_desc_plot_property_desc_plot_id_thesaurus_desc_plot_fkey FOREIGN KEY (property_desc_plot_id, thesaurus_desc_plot_id) REFERENCES core.observation_desc_plot(property_desc_plot_id, thesaurus_desc_plot_id);


--
-- Name: result_desc_profile result_desc_profile_property_desc_profile_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT result_desc_profile_property_desc_profile_id_thesaurus_des_fkey FOREIGN KEY (property_desc_profile_id, thesaurus_desc_profile_id) REFERENCES core.observation_desc_profile(property_desc_profile_id, thesaurus_desc_profile_id);


--
-- Name: result_desc_specimen result_desc_specimen_property_desc_specimen_id_thesaurus_des_fk; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT result_desc_specimen_property_desc_specimen_id_thesaurus_des_fk FOREIGN KEY (property_desc_specimen_id, thesaurus_desc_specimen_id) REFERENCES core.observation_desc_specimen(property_desc_specimen_id, thesaurus_desc_specimen_id);


--
-- Name: result_desc_surface result_desc_surface_property_desc_surface_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT result_desc_surface_property_desc_surface_id_thesaurus_des_fkey FOREIGN KEY (property_desc_surface_id, thesaurus_desc_surface_id) REFERENCES core.observation_desc_surface(property_desc_surface_id, thesaurus_desc_surface_id);


--
-- Name: individual fk_address; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT fk_address FOREIGN KEY (address_id) REFERENCES metadata.address(address_id);


--
-- Name: organisation fk_address; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT fk_address FOREIGN KEY (address_id) REFERENCES metadata.address(address_id);


--
-- Name: organisation_individual fk_individual; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- Name: organisation_individual fk_organisation; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: organisation_unit fk_organisation; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- Name: organisation_individual fk_organisation_unit; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_organisation_unit FOREIGN KEY (organisation_unit_id) REFERENCES metadata.organisation_unit(organisation_unit_id);


--
-- Name: organisation fk_parent; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT fk_parent FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- PostgreSQL database dump complete
--

\unrestrict dt1rbfBx4LH7h4uJecXicFNIz8u1ZBmGmZVHMB75LpDdqHTfJyhDSj00LsYpu9A

