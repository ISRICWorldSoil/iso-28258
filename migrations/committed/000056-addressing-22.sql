--! Previous: sha1:5cb34bb3316e40c490ccbe70d24cbdffac9f2a70
--! Hash: sha1:09797b9d01fe7f7cd1698dbb22c6d82064441997
--! Message: addressing #22

-- Bulk ETL functions for improved performance over network connections
-- These functions accept JSONB arrays and perform batch inserts

--------------------------------------------------------------------------------
-- BULK INSERT SITES WITH PROJECT
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_sites_projects(
    p_data JSONB,
    p_project_name TEXT
) RETURNS TABLE(
    out_row_index INT,
    out_site_id INT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_sites_projects(JSONB, TEXT) IS
'Bulk insert sites and link them to a project. Input is JSONB array with row_index, latitude, longitude, site_code (optional), typical_profile (optional).';

--------------------------------------------------------------------------------
-- BULK INSERT PLOTS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_plots(
    p_data JSONB
) RETURNS TABLE(
    out_row_index INT,
    out_plot_id INT,
    out_plot_code TEXT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_plots(JSONB) IS
'Bulk insert plots. Input is JSONB array with row_index, plot_code, site_id, altitude, time_stamp, map_sheet_code, positional_accuracy, latitude, longitude.';

--------------------------------------------------------------------------------
-- BULK INSERT INDIVIDUALS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_individuals(
    p_data JSONB
) RETURNS TABLE(
    out_name TEXT,
    out_individual_id INT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_individuals(JSONB) IS
'Bulk insert individuals. Input is JSONB array with name field.';

--------------------------------------------------------------------------------
-- BULK INSERT PLOT_INDIVIDUAL ASSOCIATIONS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_plot_individuals(
    p_data JSONB
) RETURNS VOID AS $$
BEGIN
    INSERT INTO core.plot_individual (plot_id, individual_id)
    SELECT
        (r->>'plot_id')::INT,
        (r->>'individual_id')::INT
    FROM jsonb_array_elements(p_data) AS r
    WHERE (r->>'plot_id') IS NOT NULL AND (r->>'individual_id') IS NOT NULL
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_plot_individuals(JSONB) IS
'Bulk insert plot_individual associations. Input is JSONB array with plot_id, individual_id.';

--------------------------------------------------------------------------------
-- BULK INSERT SPECIMENS
-- Uses row-by-row processing within the function to correctly handle duplicate
-- keys (same code, plot_id, depths). Each input row gets its own specimen,
-- matching the behavior of the standard ETL.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_specimens(
    p_data JSONB
) RETURNS TABLE(
    out_row_index INT,
    out_specimen_id INT,
    out_specimen_code TEXT,
    out_plot_code TEXT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_specimens(JSONB) IS
'Bulk insert specimens with row-by-row processing. Each input row creates a new specimen (handles duplicates like standard ETL). Input is JSONB array with row_index, specimen_code, plot_id, plot_code, upper_depth, lower_depth, organisation_name.';

--------------------------------------------------------------------------------
-- BULK INSERT PHYS_CHEM RESULTS FOR SPECIMENS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_phys_chem_specimen_results(
    p_data JSONB
) RETURNS TABLE(
    inserted_count INT,
    skipped_count INT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_phys_chem_specimen_results(JSONB) IS
'Bulk insert physico-chemical results for specimens. Input is JSONB array with specimen_id, property_uri, procedure_uri, unit_uri, value.';

--------------------------------------------------------------------------------
-- BULK INSERT DESCRIPTIVE RESULTS FOR PLOTS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_desc_plot_results(
    p_data JSONB
) RETURNS INT AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_desc_plot_results(JSONB) IS
'Bulk insert descriptive results for plots. Input is JSONB array with plot_id, property_uri, value.';

--------------------------------------------------------------------------------
-- BULK INSERT TEXT RESULTS FOR PLOTS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_text_plot_results(
    p_data JSONB
) RETURNS INT AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_text_plot_results(JSONB) IS
'Bulk insert text results for plots. Input is JSONB array with plot_id, property_uri, value.';

--------------------------------------------------------------------------------
-- BULK INSERT TEXT RESULTS FOR SPECIMENS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_text_specimen_results(
    p_data JSONB
) RETURNS INT AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_text_specimen_results(JSONB) IS
'Bulk insert text results for specimens. Input is JSONB array with specimen_id, property_uri, value.';

--------------------------------------------------------------------------------
-- BULK INSERT DESCRIPTIVE RESULTS FOR SPECIMENS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_desc_specimen_results(
    p_data JSONB
) RETURNS INT AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_desc_specimen_results(JSONB) IS
'Bulk insert descriptive results for specimens. Input is JSONB array with specimen_id, property_uri, value.';

--------------------------------------------------------------------------------
-- BULK INSERT PHYS_CHEM RESULTS FOR PLOTS (v1.7+ schema)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.etl_bulk_insert_phys_chem_plot_results(
    p_data JSONB
) RETURNS TABLE(
    inserted_count INT,
    skipped_count INT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_bulk_insert_phys_chem_plot_results(JSONB) IS
'Bulk insert physico-chemical results for plots (v1.7+ schema). Input is JSONB array with plot_id, property_uri, procedure_uri, unit_uri, value.';
