--! Previous: sha1:ff475cf5b12d071a9159a8f565e024343ff5913d
--! Hash: sha1:63618012a9b850bbc814dd07f86e28ec6e59d662
--! Message: fix bridge_process_layer duplicate pivot columns closes 27

-- Enter migration here

------------------------------------------------------------------------------------
-- Fix: bridge_process_layer produced duplicate pivot columns (issue #27)
------------------------------------------------------------------------------------
-- core.vw_observation_<date> holds one row per (observation_code, project_id).
-- The numeric pivot builder in core.bridge_process_layer() aggregated over those
-- rows directly, so an observation code used in N projects produced N identical
-- "MAX(CASE ...) AS <code>" entries in the SELECT list. With two projects
-- CREATE MATERIALIZED VIEW failed with "column <code> specified more than once";
-- with many projects it failed with "target lists can have at most 1000 entries".
--
-- The builder now reads DISTINCT observation codes from the view. The rest of the
-- function is unchanged; CREATE OR REPLACE keeps existing grants and the comment.
------------------------------------------------------------------------------------

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

    -- Build pivot columns dynamically from the observation view (for numeric results).
    -- vw_observation holds one row per (observation_code, project_id), so a code shared
    -- by several projects appears several times. Pivot over DISTINCT codes so each
    -- observation yields exactly one column (issue #27).
    EXECUTE format(
        'SELECT string_agg(
            format(''MAX(CASE WHEN combined_data.observation_code = %%L THEN combined_data.value END) AS %%I'',
                vo.observation_code,
                vo.observation_code
            ),
            '', '' || E''\n        ''
        )
        FROM (SELECT DISTINCT observation_code FROM core.vw_observation_%s) vo',
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
