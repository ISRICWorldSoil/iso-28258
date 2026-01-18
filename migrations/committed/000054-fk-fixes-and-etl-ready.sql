--! Previous: sha1:449d6d8c4eecc91a271400cb54e4dc5600b0a5c0
--! Hash: sha1:7d05b0a4ced079cc5f4fe1a6ecf75eb6984f6147
--! Message: fk fixes and etl ready

-- Migration: Add ON DELETE CASCADE to foreign keys for project-scoped data management
-- This enables cascading deletes from site down through the data hierarchy
-- Also adds ETL helper functions for project-scoped delete and full erase

-- ============================================================================
-- PART 1: Add ON DELETE CASCADE to ISO 28258 core schema foreign keys
-- ============================================================================

-- Helper function to add/replace FK constraint with CASCADE (idempotent)
CREATE OR REPLACE FUNCTION pg_temp.add_fk_cascade(
    p_table text,
    p_constraint text,
    p_column text,
    p_ref_table text,
    p_ref_column text
) RETURNS void AS $$
BEGIN
    -- Drop existing constraint if it exists
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', p_table, p_constraint);
    -- Add new constraint with CASCADE
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s(%I) ON DELETE CASCADE',
        p_table, p_constraint, p_column, p_ref_table, p_ref_column);
END;
$$ LANGUAGE plpgsql;

-- site_project.site_id -> site (CASCADE)
SELECT pg_temp.add_fk_cascade('core.site_project', 'fk_site', 'site_id', 'core.site', 'site_id');

-- plot.site_id -> site (CASCADE)
SELECT pg_temp.add_fk_cascade('core.plot', 'fk_site', 'site_id', 'core.site', 'site_id');

-- surface.site_id -> site (CASCADE)
SELECT pg_temp.add_fk_cascade('core.surface', 'fk_site', 'site_id', 'core.site', 'site_id');

-- profile.plot_id -> plot (CASCADE)
SELECT pg_temp.add_fk_cascade('core.profile', 'fk_plot', 'plot_id', 'core.plot', 'plot_id');

-- profile.surface_id -> surface (CASCADE)
SELECT pg_temp.add_fk_cascade('core.profile', 'fk_surface', 'surface_id', 'core.surface', 'surface_id');

-- specimen.plot_id -> plot (CASCADE)
SELECT pg_temp.add_fk_cascade('core.specimen', 'fk_plot', 'plot_id', 'core.plot', 'plot_id');

-- plot_individual.plot_id -> plot (CASCADE)
SELECT pg_temp.add_fk_cascade('core.plot_individual', 'fk_plot', 'plot_id', 'core.plot', 'plot_id');

-- result_desc_plot.plot_id -> plot (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_desc_plot', 'fk_plot', 'plot_id', 'core.plot', 'plot_id');

-- element.profile_id -> profile (CASCADE)
SELECT pg_temp.add_fk_cascade('core.element', 'fk_profile', 'profile_id', 'core.profile', 'profile_id');

-- result_desc_profile.profile_id -> profile (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_desc_profile', 'fk_profile', 'profile_id', 'core.profile', 'profile_id');

-- result_desc_element.element_id -> element (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_desc_element', 'fk_element', 'element_id', 'core.element', 'element_id');

-- result_phys_chem_element.element_id -> element (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_phys_chem_element', 'fk_element', 'element_id', 'core.element', 'element_id');

-- result_desc_specimen.specimen_id -> specimen (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_desc_specimen', 'fk_specimen', 'specimen_id', 'core.specimen', 'specimen_id');

-- result_phys_chem_specimen.specimen_id -> specimen (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_phys_chem_specimen', 'fk_specimen', 'specimen_id', 'core.specimen', 'specimen_id');

-- surface_individual.surface_id -> surface (CASCADE)
SELECT pg_temp.add_fk_cascade('core.surface_individual', 'fk_surface', 'surface_id', 'core.surface', 'surface_id');

-- result_desc_surface.surface_id -> surface (CASCADE)
SELECT pg_temp.add_fk_cascade('core.result_desc_surface', 'fk_surface', 'surface_id', 'core.surface', 'surface_id');


-- ============================================================================
-- PART 2: ETL function for project-scoped delete
-- ============================================================================

DROP FUNCTION IF EXISTS core.etl_delete_project_data(text);

CREATE OR REPLACE FUNCTION core.etl_delete_project_data(p_project_name text)
RETURNS TABLE(deleted_sites integer, deleted_plots integer, deleted_specimens integer) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_delete_project_data(text)
    IS 'Deletes all data for a specific project. Cascades through site -> plot -> specimen -> results hierarchy.';


-- ============================================================================
-- PART 3: ETL function for full erase (like truncate but project-data only)
-- ============================================================================

DROP FUNCTION IF EXISTS core.etl_erase_all_data();

CREATE OR REPLACE FUNCTION core.etl_erase_all_data()
RETURNS TABLE(deleted_sites integer, deleted_plots integer, deleted_specimens integer) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION core.etl_erase_all_data()
    IS 'Deletes all site/plot/specimen/result data from all projects. Preserves metadata (observations, properties, procedures, etc.).';


-- ============================================================================
-- PART 4: Fix trigger function for result value validation
-- Fixes old naming in check_result_value_specimen
-- ============================================================================

CREATE OR REPLACE FUNCTION core.check_result_value_specimen()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
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
$BODY$;


-- ============================================================================
-- PART 5: Drop unique constraint on specimen_code
-- One plot can have multiple specimens with the same code
-- ============================================================================

ALTER TABLE IF EXISTS core.specimen DROP CONSTRAINT IF EXISTS specimen_code_key;


-- ============================================================================
-- PART 6: Add spatial index on plot.position for query performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS core_plot_position_geog_idx
  ON core.plot
  USING GIST (position);


-- ============================================================================
-- PART 7: Schema fixes for ETL support
-- ============================================================================

-- Fix for unique constraints on metadata.individual
-- Clean up duplicates before adding constraints (idempotent)
WITH duplicates AS (
    SELECT individual_id,
           ROW_NUMBER() OVER (PARTITION BY name, email ORDER BY individual_id) AS rn
    FROM metadata.individual
)
DELETE FROM core.plot_individual
WHERE individual_id IN (
    SELECT individual_id FROM duplicates WHERE rn > 1
);

WITH duplicates AS (
    SELECT individual_id,
           ROW_NUMBER() OVER (PARTITION BY name, email ORDER BY individual_id) AS rn
    FROM metadata.individual
)
DELETE FROM metadata.individual
WHERE individual_id IN (
    SELECT individual_id FROM duplicates WHERE rn > 1
);

-- Idempotent solution to add the unique constraints
DO $$
BEGIN
    -- Check if unique_name constraint exists, then add if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'individual'
        AND table_schema = 'metadata'
        AND constraint_name = 'unique_name'
    ) THEN
        ALTER TABLE metadata.individual
        ADD CONSTRAINT unique_name UNIQUE (name);
    END IF;

    -- Check if unique_email constraint exists, then add if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'individual'
        AND table_schema = 'metadata'
        AND constraint_name = 'unique_email'
    ) THEN
        ALTER TABLE metadata.individual
        ADD CONSTRAINT unique_email UNIQUE (email);
    END IF;
END $$;

-- Add position column to site if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core'
          AND table_name = 'site'
          AND column_name = 'position'
    ) THEN
        ALTER TABLE core.site ADD COLUMN "position" public.geography(Point,4326);
    END IF;
END $$;


-- ============================================================================
-- PART 8: ETL Helper Functions for data insertion
-- ============================================================================

-- ETL Function: Insert Individual
DROP FUNCTION IF EXISTS core.etl_insert_individual(text, text);

CREATE OR REPLACE FUNCTION core.etl_insert_individual(
    name text,
    email text)
    RETURNS SETOF metadata.individual
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000
AS $BODY$
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
$BODY$;

COMMENT ON FUNCTION core.etl_insert_individual
    IS 'Inserts a new individual into the metadata.individual table. If the individual already exists, it returns the existing record.';


-- ETL Function: Insert Address
DROP FUNCTION IF EXISTS core.etl_insert_address(text, text);

CREATE OR REPLACE FUNCTION core.etl_insert_address(
    street_address text,
    country_iso text DEFAULT NULL)
    RETURNS SETOF metadata.address
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
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
$BODY$;

COMMENT ON FUNCTION core.etl_insert_address
    IS 'Inserts a new address into the metadata.address table. If the address already exists, it returns the existing record.';


-- ETL Function: Insert Organisation
DROP FUNCTION IF EXISTS core.etl_insert_organisation(text, text, text, text, integer);

CREATE OR REPLACE FUNCTION core.etl_insert_organisation(
        name text,
        email text,
        telephone text,
        url text,
        address_id integer)
    RETURNS SETOF metadata.organisation
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
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
$BODY$;

COMMENT ON FUNCTION core.etl_insert_organisation
    IS 'Inserts a new organisation into the metadata.organisation table. If the organisation already exists, it returns the existing record.';


-- ETL Function: Insert Organisation Individual
DROP FUNCTION IF EXISTS core.etl_insert_organisation_individual(integer, integer, text);

CREATE OR REPLACE FUNCTION core.etl_insert_organisation_individual(
        individual_id integer,
        organisation_id integer,
        role text)
    RETURNS metadata.organisation_individual
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
    INSERT INTO metadata.organisation_individual ( individual_id, organisation_id, role )
    VALUES (etl_insert_organisation_individual.individual_id,
            etl_insert_organisation_individual.organisation_id,
            etl_insert_organisation_individual.role)
    ON CONFLICT DO NOTHING RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_organisation_individual
    IS 'Inserts a new organisation_individual into the metadata.organisation_individual table. If the organisation_individual already exists, it returns the existing record.';


-- ETL Function: Insert Site
DROP FUNCTION IF EXISTS core.etl_insert_site(integer, integer, text, text);

CREATE OR REPLACE FUNCTION core.etl_insert_site(
        site_code integer,
        typical_profile integer,
        latitude text,
        longitude text)
    RETURNS core.site
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
    INSERT INTO core.site(site_code, typical_profile, "position")
    VALUES (etl_insert_site.site_code,
            etl_insert_site.typical_profile,
            ST_GeographyFromText('POINT ('||longitude||' '||latitude||')')
            )
    ON CONFLICT DO NOTHING
    RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_site
    IS 'Inserts a new site into the core.site table. If the site already exists, it returns the existing record.';


-- ETL Function: Insert Site Project
DROP FUNCTION IF EXISTS core.etl_insert_site_project(integer, integer);

CREATE OR REPLACE FUNCTION core.etl_insert_site_project(
        site_id integer,
        project_id integer
        )
    RETURNS core.site_project
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
    INSERT INTO core.site_project(site_id, project_id)
    VALUES (etl_insert_site_project.site_id,
            etl_insert_site_project.project_id
            )
    ON CONFLICT DO NOTHING
    RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_site_project
    IS 'Inserts a new site_project into the core.site_project table. if the site_project already exists, it returns the existing record.';


-- ETL Function: Insert Plot
DROP FUNCTION IF EXISTS core.etl_insert_plot(text, integer, numeric, text, text, numeric, text, text, numeric, numeric);
DROP FUNCTION IF EXISTS core.etl_insert_plot(text, integer, numeric, text, text, numeric, text, text);

CREATE OR REPLACE FUNCTION core.etl_insert_plot(
        plot_code text,
        site_id integer,
        altitude numeric,
        time_stamp text, -- Accept time_stamp as TEXT for preprocessing
        map_sheet_code text,
        positional_accuracy numeric,
        latitude text,
        longitude text
    )
    RETURNS core.plot
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    normalized_time_stamp DATE;
    result core.plot;
BEGIN
    -- Normalize the time_stamp to handle formats and invalid values
    BEGIN
        -- Replace single-digit days or months with leading zero
        normalized_time_stamp := (
            CASE
                WHEN time_stamp ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
                    TO_DATE(
                        REGEXP_REPLACE(
                            time_stamp,
                            '(\d{1,2})/(\d{1,2})/(\d{4})',
                            LPAD('\1', 2, '0') || '/' || LPAD('\2', 2, '0') || '/' || '\3'
                        ),
                        'DD/MM/YYYY'
                    )
                ELSE NULL
            END
        );
    EXCEPTION WHEN OTHERS THEN
        -- If normalization or casting fails, set to NULL
        normalized_time_stamp := NULL;
    END;

    -- Perform the INSERT and return the result
    INSERT INTO core.plot(
            plot_code, site_id, altitude, time_stamp, map_sheet_code, positional_accuracy, "position"
        )
        VALUES (
            plot_code,
            site_id,
            altitude,
            normalized_time_stamp, -- Use the normalized timestamp
            map_sheet_code,
            positional_accuracy,
            ST_GeographyFromText('POINT ('||longitude||' '||latitude||')')
        )
        ON CONFLICT DO NOTHING
        RETURNING * INTO result;

    RETURN result;
END;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_plot
    IS 'Insert a new plot into the core.plot table. If the plot already exists, it returns the existing record.';


-- ETL Function: Insert Plot Individual
DROP FUNCTION IF EXISTS core.etl_insert_plot_individual(integer, integer);

CREATE OR REPLACE FUNCTION core.etl_insert_plot_individual(
    plot_id integer,
    individual_id integer)
    RETURNS core.plot_individual
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
    INSERT INTO core.plot_individual (plot_id, individual_id)
    VALUES (etl_insert_plot_individual.plot_id,
            etl_insert_plot_individual.individual_id)
     ON CONFLICT DO NOTHING RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_plot_individual
    IS 'Inserts a new plot_individual into the core.plot_individual table. If the plot_individual already exists, it returns the existing record.';


-- ETL Function: Insert Result Desc Plot
DROP FUNCTION IF EXISTS core.etl_insert_result_desc_plot(integer, text, text);

CREATE OR REPLACE FUNCTION core.etl_insert_result_desc_plot(
    plot_id bigint,
    prop text,
    value text)
    RETURNS core.result_desc_plot
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL SAFE -- This function is safe to run in parallel
AS $BODY$
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
$BODY$;

COMMENT ON FUNCTION core.etl_insert_result_desc_plot
    IS 'Inserts a new result_desc_plot into the core.result_desc_plot table. If the result_desc_plot already exists, it returns the existing record.';


-- Helper Function: Is Valid Date
DROP FUNCTION IF EXISTS public.is_valid_date(text, text);

CREATE OR REPLACE FUNCTION public.is_valid_date(date_text TEXT, format TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Attempt to cast the date using the provided format
    PERFORM TO_DATE(date_text, format);
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION public.is_valid_date
    IS 'Checks if a date string is valid according to a given format.';


-- ETL Function: Insert Specimen
DROP FUNCTION IF EXISTS core.etl_insert_specimen(text, integer, integer, integer, integer, integer);

CREATE OR REPLACE FUNCTION core.etl_insert_specimen(
    specimen_code text,
    plot_id integer,
    upper_depth integer,
    lower_depth integer,
    organisation_id integer,
    specimen_prep_process_id integer)
    RETURNS core.specimen
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
    INSERT INTO core.specimen (code, plot_id, upper_depth, lower_depth, organisation_id, specimen_prep_process_id)
        SELECT  etl_insert_specimen.specimen_code,
                etl_insert_specimen.plot_id,
                etl_insert_specimen.upper_depth,
                etl_insert_specimen.lower_depth,
                etl_insert_specimen.organisation_id,
                etl_insert_specimen.specimen_prep_process_id
    ON CONFLICT DO NOTHING
    RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_specimen
    IS 'Inserts a new specimen into the core.specimen table. If the specimen already exists, it returns the existing record.';


-- ETL Function: Insert Result Phys Chem Specimen
DROP FUNCTION IF EXISTS core.etl_insert_result_phys_chem_specimen(integer, integer, integer, numeric);

CREATE OR REPLACE FUNCTION core.etl_insert_result_phys_chem_specimen(
    observation_phys_chem_specimen_id integer,
    specimen_id integer,
    organisation_id integer,
    value numeric)
    RETURNS core.result_phys_chem_specimen
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL SAFE -- This function is safe to run in parallel
AS $BODY$
    INSERT INTO core.result_phys_chem_specimen (observation_phys_chem_specimen_id, specimen_id, organisation_id, value)
    VALUES (
              etl_insert_result_phys_chem_specimen.observation_phys_chem_specimen_id,
              etl_insert_result_phys_chem_specimen.specimen_id,
              etl_insert_result_phys_chem_specimen.organisation_id,
              etl_insert_result_phys_chem_specimen.value
              )
       ON CONFLICT DO NOTHING
       RETURNING *;
$BODY$;

COMMENT ON FUNCTION core.etl_insert_result_phys_chem_specimen
    IS 'Inserts a new result_phys_chem_specimen into the core.result_phys_chem_specimen table. If the result_phys_chem_specimen already exists, it returns the existing record.';
