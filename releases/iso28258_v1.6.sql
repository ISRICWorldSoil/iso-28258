--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 8 (class 2615 OID 23078165)
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- TOC entry 5379 (class 0 OID 0)
-- Dependencies: 8
-- Name: SCHEMA core; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA core IS 'Core entities and relations from the ISO-28258 domain model';


--
-- TOC entry 7 (class 2615 OID 23078136)
-- Name: graphile_migrate; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphile_migrate;


--
-- TOC entry 9 (class 2615 OID 23080089)
-- Name: metadata; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA metadata;


--
-- TOC entry 5380 (class 0 OID 0)
-- Dependencies: 9
-- Name: SCHEMA metadata; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA metadata IS 'Meta-data model based on VCard: https://www.w3.org/TR/vcard-rdf';


--
-- TOC entry 2 (class 3079 OID 23078166)
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- TOC entry 5381 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- TOC entry 1873 (class 1247 OID 23080269)
-- Name: element_type; Type: TYPE; Schema: core; Owner: -
--

CREATE TYPE core.element_type AS ENUM (
    'Horizon',
    'Layer'
);


--
-- TOC entry 5382 (class 0 OID 0)
-- Dependencies: 1873
-- Name: TYPE element_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TYPE core.element_type IS 'Type of Profile Element';


--
-- TOC entry 987 (class 1255 OID 23079673)
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
-- TOC entry 5383 (class 0 OID 0)
-- Dependencies: 987
-- Name: FUNCTION check_result_value(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.check_result_value() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observations (fields value_min and value_max).';


--
-- TOC entry 1054 (class 1255 OID 23080087)
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
-- TOC entry 5384 (class 0 OID 0)
-- Dependencies: 1054
-- Name: FUNCTION check_result_value_specimen(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.check_result_value_specimen() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observation (fields value_min and value_max).';


--
-- TOC entry 916 (class 1255 OID 23081037)
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
-- TOC entry 5385 (class 0 OID 0)
-- Dependencies: 916
-- Name: FUNCTION etl_delete_project_data(p_project_name text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_delete_project_data(p_project_name text) IS 'Deletes all data for a specific project. Cascades through site -> plot -> specimen -> results hierarchy.';


--
-- TOC entry 979 (class 1255 OID 23081038)
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
-- TOC entry 5386 (class 0 OID 0)
-- Dependencies: 979
-- Name: FUNCTION etl_erase_all_data(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_erase_all_data() IS 'Deletes all site/plot/specimen/result data from all projects. Preserves metadata (observations, properties, procedures, etc.).';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 275 (class 1259 OID 23080091)
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
-- TOC entry 5387 (class 0 OID 0)
-- Dependencies: 275
-- Name: TABLE address; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.address IS 'Equivalent to the Address class in VCard, defined as delivery address for the associated object.';


--
-- TOC entry 5388 (class 0 OID 0)
-- Dependencies: 275
-- Name: COLUMN address.street_address; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.street_address IS 'Street address data property in VCard, including house number, e.g. "Generaal Foulkesweg 108".';


--
-- TOC entry 5389 (class 0 OID 0)
-- Dependencies: 275
-- Name: COLUMN address.postal_code; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.postal_code IS 'Equivalent to the postal-code data property in VCard, e.g. "6701 PB".';


--
-- TOC entry 5390 (class 0 OID 0)
-- Dependencies: 275
-- Name: COLUMN address.locality; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.locality IS 'Locality data property in VCard, referring to a village, town, city, etc, e.g. "Wageningen".';


--
-- TOC entry 5391 (class 0 OID 0)
-- Dependencies: 275
-- Name: COLUMN address.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.address.address_id IS 'Synthetic primary key.';


--
-- TOC entry 533 (class 1255 OID 23081045)
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
-- TOC entry 5392 (class 0 OID 0)
-- Dependencies: 533
-- Name: FUNCTION etl_insert_address(street_address text, country_iso text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_address(street_address text, country_iso text) IS 'Inserts a new address into the metadata.address table. If the address already exists, it returns the existing record.';


--
-- TOC entry 276 (class 1259 OID 23080105)
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
-- TOC entry 5393 (class 0 OID 0)
-- Dependencies: 276
-- Name: TABLE individual; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.individual IS 'Equivalent to the Individual class in VCard, defined as a single person or entity.';


--
-- TOC entry 5394 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.name IS 'Name of the individual, encompasses the data properties additional-name, given-name and family-name in VCard.';


--
-- TOC entry 5395 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.honorific_title; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.honorific_title IS 'Academic title or honorific rank associated to the individual. Encompasses the data properties honorific-prefix, honorific-suffix and title in VCard.';


--
-- TOC entry 5396 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.email; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.email IS 'Electronic mail address of the individual.';


--
-- TOC entry 5397 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.url; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.url IS 'Locator to a web page associated with the individual.';


--
-- TOC entry 5398 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.address_id IS 'Foreign key to address associated with the individual.';


--
-- TOC entry 5399 (class 0 OID 0)
-- Dependencies: 276
-- Name: COLUMN individual.individual_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.individual.individual_id IS 'Synthetic primary key.';


--
-- TOC entry 355 (class 1255 OID 23081044)
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
-- TOC entry 5400 (class 0 OID 0)
-- Dependencies: 355
-- Name: FUNCTION etl_insert_individual(name text, email text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_individual(name text, email text) IS 'Inserts a new individual into the metadata.individual table. If the individual already exists, it returns the existing record.';


--
-- TOC entry 277 (class 1259 OID 23080121)
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
-- TOC entry 5401 (class 0 OID 0)
-- Dependencies: 277
-- Name: TABLE organisation; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation IS 'Equivalent to the Organisation class in VCard, defined as a single entity, might also represent a business or government, a department or division within a business or government, a club, an association, or the like.';


--
-- TOC entry 5402 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.parent_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.parent_id IS 'Foreign key to the parent organisation, in case of a department or division of a larger organisation.';


--
-- TOC entry 5403 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.name IS 'Name of the organisation.';


--
-- TOC entry 5404 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.email; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.email IS 'Electronic mail address of the organisation.';


--
-- TOC entry 5405 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.url; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.url IS 'Locator to a web page associated with the organisation.';


--
-- TOC entry 5406 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.address_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.address_id IS 'Foreign key to address associated with the organisation.';


--
-- TOC entry 5407 (class 0 OID 0)
-- Dependencies: 277
-- Name: COLUMN organisation.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation.organisation_id IS 'Synthetic primary key.';


--
-- TOC entry 867 (class 1255 OID 23081046)
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
-- TOC entry 5408 (class 0 OID 0)
-- Dependencies: 867
-- Name: FUNCTION etl_insert_organisation(name text, email text, telephone text, url text, address_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_organisation(name text, email text, telephone text, url text, address_id integer) IS 'Inserts a new organisation into the metadata.organisation table. If the organisation already exists, it returns the existing record.';


--
-- TOC entry 279 (class 1259 OID 23080160)
-- Name: organisation_individual; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.organisation_individual (
    individual_id integer NOT NULL,
    organisation_id integer NOT NULL,
    organisation_unit_id integer,
    role character varying
);


--
-- TOC entry 5409 (class 0 OID 0)
-- Dependencies: 279
-- Name: TABLE organisation_individual; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation_individual IS 'Relation between Individual and Organisation. Captures the object properties hasOrganisationName, org and organisation-name in VCard. In most cases means that the individual works at the organisation in the unit specified.';


--
-- TOC entry 5410 (class 0 OID 0)
-- Dependencies: 279
-- Name: COLUMN organisation_individual.individual_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.individual_id IS 'Foreign key to the related individual.';


--
-- TOC entry 5411 (class 0 OID 0)
-- Dependencies: 279
-- Name: COLUMN organisation_individual.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.organisation_id IS 'Foreign key to the related organisation.';


--
-- TOC entry 5412 (class 0 OID 0)
-- Dependencies: 279
-- Name: COLUMN organisation_individual.organisation_unit_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.organisation_unit_id IS 'Foreign key to the organisational unit associating the individual with the organisation.';


--
-- TOC entry 5413 (class 0 OID 0)
-- Dependencies: 279
-- Name: COLUMN organisation_individual.role; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_individual.role IS 'Role of the individual within the organisation and respective organisational unit, e.g. "director", "secretary".';


--
-- TOC entry 740 (class 1255 OID 23081047)
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
-- TOC entry 5414 (class 0 OID 0)
-- Dependencies: 740
-- Name: FUNCTION etl_insert_organisation_individual(individual_id integer, organisation_id integer, role text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_organisation_individual(individual_id integer, organisation_id integer, role text) IS 'Inserts a new organisation_individual into the metadata.organisation_individual table. If the organisation_individual already exists, it returns the existing record.';


--
-- TOC entry 236 (class 1259 OID 23079310)
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
-- TOC entry 5415 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.plot IS 'Elementary area or location where individual observations are made and/or samples are taken. Plot is the main spatial feature of interest in ISO-28258. Plot has three sub-classes: Borehole, Pit and Surface. Surface features its own table since it has its own properties and a different geometry.';


--
-- TOC entry 5416 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot.plot_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.plot_code IS 'Natural key, can be null.';


--
-- TOC entry 5417 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot.altitude; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.altitude IS 'Altitude at the plot in metres, if known. Property re-used from GloSIS.';


--
-- TOC entry 5418 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot.time_stamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.time_stamp IS 'Time stamp of the plot, if known. Property re-used from GloSIS.';


--
-- TOC entry 5419 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot.map_sheet_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.map_sheet_code IS 'Code identifying the map sheet where the plot may be positioned. Property re-used from GloSIS.';


--
-- TOC entry 5420 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot.plot_id IS 'Synthetic primary key.';


--
-- TOC entry 5421 (class 0 OID 0)
-- Dependencies: 236
-- Name: COLUMN plot."position"; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot."position" IS 'Geodetic coordinates of the spatial position of the plot. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- TOC entry 683 (class 1255 OID 23081050)
-- Name: etl_insert_plot(text, integer, numeric, text, text, numeric, text, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text) RETURNS core.plot
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- TOC entry 5422 (class 0 OID 0)
-- Dependencies: 683
-- Name: FUNCTION etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_plot(plot_code text, site_id integer, altitude numeric, time_stamp text, map_sheet_code text, positional_accuracy numeric, latitude text, longitude text) IS 'Insert a new plot into the core.plot table. If the plot already exists, it returns the existing record.';


--
-- TOC entry 281 (class 1259 OID 23080229)
-- Name: plot_individual; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.plot_individual (
    plot_id integer NOT NULL,
    individual_id integer NOT NULL
);


--
-- TOC entry 5423 (class 0 OID 0)
-- Dependencies: 281
-- Name: TABLE plot_individual; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.plot_individual IS 'Identifies the individual(s) responsible for surveying a plot';


--
-- TOC entry 5424 (class 0 OID 0)
-- Dependencies: 281
-- Name: COLUMN plot_individual.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot_individual.plot_id IS 'Foreign key to the plot table, identifies the plot surveyed';


--
-- TOC entry 5425 (class 0 OID 0)
-- Dependencies: 281
-- Name: COLUMN plot_individual.individual_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.plot_individual.individual_id IS 'Foreign key to the individual table, indicates the individual responsible for surveying the plot.';


--
-- TOC entry 815 (class 1255 OID 23081051)
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
-- TOC entry 5426 (class 0 OID 0)
-- Dependencies: 815
-- Name: FUNCTION etl_insert_plot_individual(plot_id integer, individual_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_plot_individual(plot_id integer, individual_id integer) IS 'Inserts a new plot_individual into the core.plot_individual table. If the plot_individual already exists, it returns the existing record.';


--
-- TOC entry 260 (class 1259 OID 23079692)
-- Name: result_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_plot (
    plot_id integer NOT NULL,
    property_desc_plot_id integer NOT NULL,
    thesaurus_desc_plot_id integer NOT NULL
);


--
-- TOC entry 5427 (class 0 OID 0)
-- Dependencies: 260
-- Name: TABLE result_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_plot IS 'Descriptive results for the Plot feature interest.';


--
-- TOC entry 5428 (class 0 OID 0)
-- Dependencies: 260
-- Name: COLUMN result_desc_plot.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_plot.plot_id IS 'Foreign key to the corresponding Plot feature of interest.';


--
-- TOC entry 899 (class 1255 OID 23081052)
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
-- TOC entry 5429 (class 0 OID 0)
-- Dependencies: 899
-- Name: FUNCTION etl_insert_result_desc_plot(plot_id bigint, prop text, value text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_desc_plot(plot_id bigint, prop text, value text) IS 'Inserts a new result_desc_plot into the core.result_desc_plot table. If the result_desc_plot already exists, it returns the existing record.';


--
-- TOC entry 274 (class 1259 OID 23080065)
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
-- TOC entry 5430 (class 0 OID 0)
-- Dependencies: 274
-- Name: TABLE result_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_phys_chem_specimen IS 'Numerical results for the Specimen feature interest.';


--
-- TOC entry 5431 (class 0 OID 0)
-- Dependencies: 274
-- Name: COLUMN result_phys_chem_specimen.result_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.result_phys_chem_specimen_id IS 'Synthetic primary key.';


--
-- TOC entry 5432 (class 0 OID 0)
-- Dependencies: 274
-- Name: COLUMN result_phys_chem_specimen.observation_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.observation_phys_chem_specimen_id IS 'Foreign key to the corresponding numerical observation.';


--
-- TOC entry 5433 (class 0 OID 0)
-- Dependencies: 274
-- Name: COLUMN result_phys_chem_specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.specimen_id IS 'Foreign key to the corresponding Specimen instance.';


--
-- TOC entry 5434 (class 0 OID 0)
-- Dependencies: 274
-- Name: COLUMN result_phys_chem_specimen.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_specimen.value IS 'Numerical value resulting from applying the refered observation to the refered specimen.';


--
-- TOC entry 360 (class 1255 OID 23081055)
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
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 360
-- Name: FUNCTION etl_insert_result_phys_chem_specimen(observation_phys_chem_specimen_id integer, specimen_id integer, organisation_id integer, value numeric); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_result_phys_chem_specimen(observation_phys_chem_specimen_id integer, specimen_id integer, organisation_id integer, value numeric) IS 'Inserts a new result_phys_chem_specimen into the core.result_phys_chem_specimen table. If the result_phys_chem_specimen already exists, it returns the existing record.';


--
-- TOC entry 234 (class 1259 OID 23079282)
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
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE site; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.site IS 'Defined area which is subject to a soil quality investigation. Site is not a spatial feature of interest, but provides the link between the spatial features of interest (Plot) to the Project. The geometry can either be a location (point) or extent (polygon) but not both at the same time.';


--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN site.site_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.site_code IS 'Natural key, can be null.';


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN site.typical_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.typical_profile IS 'Foreign key to a profile providing a typical characterisation of this site.';


--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN site.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.site_id IS 'Synthetic primary key.';


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN site."position"; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site."position" IS 'Geodetic coordinates of the spatial position of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN site.extent; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site.extent IS 'Site extent expressed with geodetic coordinates of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- TOC entry 1012 (class 1255 OID 23081048)
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
-- TOC entry 5442 (class 0 OID 0)
-- Dependencies: 1012
-- Name: FUNCTION etl_insert_site(site_code integer, typical_profile integer, latitude text, longitude text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_site(site_code integer, typical_profile integer, latitude text, longitude text) IS 'Inserts a new site into the core.site table. If the site already exists, it returns the existing record.';


--
-- TOC entry 235 (class 1259 OID 23079292)
-- Name: site_project; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.site_project (
    site_id integer NOT NULL,
    project_id integer NOT NULL
);


--
-- TOC entry 5443 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE site_project; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.site_project IS 'Many to many relation between Site and Project.';


--
-- TOC entry 5444 (class 0 OID 0)
-- Dependencies: 235
-- Name: COLUMN site_project.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site_project.site_id IS 'Foreign key to Site table';


--
-- TOC entry 5445 (class 0 OID 0)
-- Dependencies: 235
-- Name: COLUMN site_project.project_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.site_project.project_id IS 'Foreign key to Project table';


--
-- TOC entry 552 (class 1255 OID 23081049)
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
-- TOC entry 5446 (class 0 OID 0)
-- Dependencies: 552
-- Name: FUNCTION etl_insert_site_project(site_id integer, project_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_site_project(site_id integer, project_id integer) IS 'Inserts a new site_project into the core.site_project table. if the site_project already exists, it returns the existing record.';


--
-- TOC entry 267 (class 1259 OID 23079919)
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
-- TOC entry 5447 (class 0 OID 0)
-- Dependencies: 267
-- Name: TABLE specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen IS 'Soil Specimen is defined in ISO-28258 as: "a subtype of SF_Specimen. Soil Specimen may be taken in the Site, Plot, Profile, or ProfileElement including their subtypes." In this database Specimen is for now only associated to Plot for simplification.';


--
-- TOC entry 5448 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.code IS 'External code used to identify the soil Specimen (if used).';


--
-- TOC entry 5449 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.plot_id IS 'Foreign key to the associated soil Plot';


--
-- TOC entry 5450 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.specimen_prep_process_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.specimen_prep_process_id IS 'Foreign key to the preparation process used on this soil Specimen.';


--
-- TOC entry 5451 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.upper_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.upper_depth IS 'Upper depth of this soil specimen in centimetres.';


--
-- TOC entry 5452 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.lower_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.lower_depth IS 'Lower depth of this soil specimen in centimetres.';


--
-- TOC entry 5453 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.organisation_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.organisation_id IS 'Individual that is responsible for, or carried out, the process that produced this result.';


--
-- TOC entry 5454 (class 0 OID 0)
-- Dependencies: 267
-- Name: COLUMN specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen.specimen_id IS 'Synthetic primary key.';


--
-- TOC entry 1087 (class 1255 OID 23081054)
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
-- TOC entry 5455 (class 0 OID 0)
-- Dependencies: 1087
-- Name: FUNCTION etl_insert_specimen(specimen_code text, plot_id integer, upper_depth integer, lower_depth integer, organisation_id integer, specimen_prep_process_id integer); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.etl_insert_specimen(specimen_code text, plot_id integer, upper_depth integer, lower_depth integer, organisation_id integer, specimen_prep_process_id integer) IS 'Inserts a new specimen into the core.specimen table. If the specimen already exists, it returns the existing record.';


--
-- TOC entry 952 (class 1255 OID 23081053)
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
-- TOC entry 5456 (class 0 OID 0)
-- Dependencies: 952
-- Name: FUNCTION is_valid_date(date_text text, format text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_valid_date(date_text text, format text) IS 'Checks if a date string is valid according to a given format.';


--
-- TOC entry 239 (class 1259 OID 23079376)
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
-- TOC entry 5457 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.element IS 'ProfileElement is the super-class of Horizon and Layer, which share the same basic properties. Horizons develop in a layer, which in turn have been developed throught geogenesis or anthropogenic action. Layers can be used to describe common characteristics of a set of adjoining horizons. For the time being no assocation is previewed between Horizon and Layer.';


--
-- TOC entry 5458 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.profile_id IS 'Reference to the Profile to which this element belongs';


--
-- TOC entry 5459 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.order_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.order_element IS 'Order of this element within the Profile';


--
-- TOC entry 5460 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.upper_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.upper_depth IS 'Upper depth of this profile element in centimetres.';


--
-- TOC entry 5461 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.lower_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.lower_depth IS 'Lower depth of this profile element in centimetres.';


--
-- TOC entry 5462 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.type IS 'Type of profile element, Horizon or Layer';


--
-- TOC entry 5463 (class 0 OID 0)
-- Dependencies: 239
-- Name: COLUMN element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.element.element_id IS 'Synthetic primary key.';


--
-- TOC entry 283 (class 1259 OID 23080312)
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
-- TOC entry 253 (class 1259 OID 23079587)
-- Name: observation_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_element (
    property_desc_element_id integer NOT NULL,
    thesaurus_desc_element_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- TOC entry 5464 (class 0 OID 0)
-- Dependencies: 253
-- Name: TABLE observation_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_element IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5465 (class 0 OID 0)
-- Dependencies: 253
-- Name: COLUMN observation_desc_element.property_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_element.property_desc_element_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5466 (class 0 OID 0)
-- Dependencies: 253
-- Name: COLUMN observation_desc_element.thesaurus_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_element.thesaurus_desc_element_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- TOC entry 251 (class 1259 OID 23079543)
-- Name: observation_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_plot (
    property_desc_plot_id integer NOT NULL,
    thesaurus_desc_plot_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- TOC entry 5467 (class 0 OID 0)
-- Dependencies: 251
-- Name: TABLE observation_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_plot IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5468 (class 0 OID 0)
-- Dependencies: 251
-- Name: COLUMN observation_desc_plot.property_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_plot.property_desc_plot_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5469 (class 0 OID 0)
-- Dependencies: 251
-- Name: COLUMN observation_desc_plot.thesaurus_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_plot.thesaurus_desc_plot_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- TOC entry 252 (class 1259 OID 23079565)
-- Name: observation_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_profile (
    property_desc_profile_id integer NOT NULL,
    thesaurus_desc_profile_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- TOC entry 5470 (class 0 OID 0)
-- Dependencies: 252
-- Name: TABLE observation_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_profile IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5471 (class 0 OID 0)
-- Dependencies: 252
-- Name: COLUMN observation_desc_profile.property_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_profile.property_desc_profile_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5472 (class 0 OID 0)
-- Dependencies: 252
-- Name: COLUMN observation_desc_profile.thesaurus_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_profile.thesaurus_desc_profile_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- TOC entry 270 (class 1259 OID 23079967)
-- Name: observation_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_specimen (
    property_desc_specimen_id integer NOT NULL,
    thesaurus_desc_specimen_id integer NOT NULL,
    procedure_desc_id integer
);


--
-- TOC entry 5473 (class 0 OID 0)
-- Dependencies: 270
-- Name: TABLE observation_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_specimen IS 'Descriptive properties for the Specimen feature of interest';


--
-- TOC entry 5474 (class 0 OID 0)
-- Dependencies: 270
-- Name: COLUMN observation_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_specimen.property_desc_specimen_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5475 (class 0 OID 0)
-- Dependencies: 270
-- Name: COLUMN observation_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_specimen.thesaurus_desc_specimen_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- TOC entry 250 (class 1259 OID 23079521)
-- Name: observation_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.observation_desc_surface (
    property_desc_surface_id integer NOT NULL,
    thesaurus_desc_surface_id integer NOT NULL,
    procedure_desc_id integer NOT NULL
);


--
-- TOC entry 5476 (class 0 OID 0)
-- Dependencies: 250
-- Name: TABLE observation_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5477 (class 0 OID 0)
-- Dependencies: 250
-- Name: COLUMN observation_desc_surface.property_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_surface.property_desc_surface_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5478 (class 0 OID 0)
-- Dependencies: 250
-- Name: COLUMN observation_desc_surface.thesaurus_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_desc_surface.thesaurus_desc_surface_id IS 'Foreign key to the corresponding thesaurus entry';


--
-- TOC entry 272 (class 1259 OID 23080035)
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
-- TOC entry 5479 (class 0 OID 0)
-- Dependencies: 272
-- Name: TABLE observation_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_phys_chem_specimen IS 'Numerical observations for the Specimen feature of interest';


--
-- TOC entry 5480 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.observation_phys_chem_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.observation_phys_chem_specimen_id IS 'Synthetic primary key for the observation';


--
-- TOC entry 5481 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';


--
-- TOC entry 5482 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.value_min; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';


--
-- TOC entry 5483 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.value_max; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


--
-- TOC entry 5484 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.property_phys_chem_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5485 (class 0 OID 0)
-- Dependencies: 272
-- Name: COLUMN observation_phys_chem_specimen.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_specimen.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';


--
-- TOC entry 271 (class 1259 OID 23080034)
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
-- TOC entry 5486 (class 0 OID 0)
-- Dependencies: 271
-- Name: observation_numerical_specime_observation_numerical_specime_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_numerical_specime_observation_numerical_specime_seq OWNED BY core.observation_phys_chem_specimen.observation_phys_chem_specimen_id;


--
-- TOC entry 256 (class 1259 OID 23079621)
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
-- TOC entry 5487 (class 0 OID 0)
-- Dependencies: 256
-- Name: TABLE observation_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.observation_phys_chem_element IS 'Physio-chemical observations for the Element feature of interest';


--
-- TOC entry 5488 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.observation_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.observation_phys_chem_element_id IS 'Synthetic primary key for the observation';


--
-- TOC entry 5489 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.property_phys_chem_id IS 'Foreign key to the corresponding property';


--
-- TOC entry 5490 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';


--
-- TOC entry 5491 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';


--
-- TOC entry 5492 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.value_min; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';


--
-- TOC entry 5493 (class 0 OID 0)
-- Dependencies: 256
-- Name: COLUMN observation_phys_chem_element.value_max; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.observation_phys_chem_element.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


--
-- TOC entry 255 (class 1259 OID 23079620)
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
-- TOC entry 5494 (class 0 OID 0)
-- Dependencies: 255
-- Name: observation_phys_chem_observation_phys_chem_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.observation_phys_chem_observation_phys_chem_id_seq OWNED BY core.observation_phys_chem_element.observation_phys_chem_element_id;


--
-- TOC entry 284 (class 1259 OID 23080331)
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
-- TOC entry 263 (class 1259 OID 23079832)
-- Name: procedure_desc; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.procedure_desc (
    label character varying NOT NULL,
    reference character varying,
    uri character varying NOT NULL,
    procedure_desc_id integer CONSTRAINT procedure_desc_procedure_desc_id_not_null1 NOT NULL
);


--
-- TOC entry 5495 (class 0 OID 0)
-- Dependencies: 263
-- Name: TABLE procedure_desc; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.procedure_desc IS 'Descriptive Procedures for all features of interest. In most cases the procedure is described in a document such as the FAO Guidelines for Soil Description or the World Reference Base of Soil Resources.';


--
-- TOC entry 5496 (class 0 OID 0)
-- Dependencies: 263
-- Name: COLUMN procedure_desc.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.label IS 'Short label for this procedure.';


--
-- TOC entry 5497 (class 0 OID 0)
-- Dependencies: 263
-- Name: COLUMN procedure_desc.reference; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.reference IS 'Long and human readable reference to the publication.';


--
-- TOC entry 5498 (class 0 OID 0)
-- Dependencies: 263
-- Name: COLUMN procedure_desc.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.uri IS 'URI to the corresponding publication, optimally a DOI. Follow this URI for the full definition of the procedure.';


--
-- TOC entry 5499 (class 0 OID 0)
-- Dependencies: 263
-- Name: COLUMN procedure_desc.procedure_desc_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_desc.procedure_desc_id IS 'Synthetic primary key.';


--
-- TOC entry 285 (class 1259 OID 23080362)
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
-- TOC entry 241 (class 1259 OID 23079408)
-- Name: procedure_phys_chem; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.procedure_phys_chem (
    broader_id integer,
    label character varying NOT NULL,
    uri character varying NOT NULL,
    procedure_phys_chem_id integer CONSTRAINT procedure_phys_chem_procedure_phys_chem_id_not_null1 NOT NULL
);


--
-- TOC entry 5500 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE procedure_phys_chem; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.procedure_phys_chem IS 'Physio-chemical Procedures for the Profile Element feature of interest';


--
-- TOC entry 5501 (class 0 OID 0)
-- Dependencies: 241
-- Name: COLUMN procedure_phys_chem.broader_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.broader_id IS 'Foreign key to brader procedure in the hierarchy';


--
-- TOC entry 5502 (class 0 OID 0)
-- Dependencies: 241
-- Name: COLUMN procedure_phys_chem.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.label IS 'Short label for this procedure';


--
-- TOC entry 5503 (class 0 OID 0)
-- Dependencies: 241
-- Name: COLUMN procedure_phys_chem.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.uri IS 'URI to the corresponding in a controlled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this procedure';


--
-- TOC entry 5504 (class 0 OID 0)
-- Dependencies: 241
-- Name: COLUMN procedure_phys_chem.procedure_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.procedure_phys_chem.procedure_phys_chem_id IS 'Synthetic primary key.';


--
-- TOC entry 286 (class 1259 OID 23080419)
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
-- TOC entry 238 (class 1259 OID 23079350)
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
-- TOC entry 5505 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.profile IS 'An abstract, ordered set of soil horizons and/or layers.';


--
-- TOC entry 5506 (class 0 OID 0)
-- Dependencies: 238
-- Name: COLUMN profile.profile_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.profile_code IS 'Natural primary key, if existing';


--
-- TOC entry 5507 (class 0 OID 0)
-- Dependencies: 238
-- Name: COLUMN profile.plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.plot_id IS 'Foreign key to Plot feature of interest';


--
-- TOC entry 5508 (class 0 OID 0)
-- Dependencies: 238
-- Name: COLUMN profile.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.surface_id IS 'Foreign key to Surface feature of interest';


--
-- TOC entry 5509 (class 0 OID 0)
-- Dependencies: 238
-- Name: COLUMN profile.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.profile.profile_id IS 'Synthetic primary key.';


--
-- TOC entry 287 (class 1259 OID 23080440)
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
-- TOC entry 232 (class 1259 OID 23079249)
-- Name: project; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project (
    name character varying NOT NULL,
    project_id integer NOT NULL
);


--
-- TOC entry 5510 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE project; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.project IS 'Provides the context of the data collection as a prerequisite for the proper use or reuse of these data.';


--
-- TOC entry 5511 (class 0 OID 0)
-- Dependencies: 232
-- Name: COLUMN project.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project.name IS 'Natural key with project name.';


--
-- TOC entry 5512 (class 0 OID 0)
-- Dependencies: 232
-- Name: COLUMN project.project_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project.project_id IS 'Synthetic primary key.';


--
-- TOC entry 311 (class 1259 OID 23080922)
-- Name: project_organisation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project_organisation (
    project_id integer NOT NULL,
    organisation_id integer NOT NULL
);


--
-- TOC entry 288 (class 1259 OID 23080466)
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
-- TOC entry 233 (class 1259 OID 23079261)
-- Name: project_related; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.project_related (
    project_source_id integer NOT NULL,
    project_target_id integer NOT NULL,
    role character varying NOT NULL
);


--
-- TOC entry 5513 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE project_related; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.project_related IS 'Relationship between two projects, e.g. project B being a sub-project of project A.';


--
-- TOC entry 5514 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN project_related.project_source_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.project_source_id IS 'Foreign key to source project.';


--
-- TOC entry 5515 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN project_related.project_target_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.project_target_id IS 'Foreign key to targe project.';


--
-- TOC entry 5516 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN project_related.role; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.project_related.role IS 'Role of source project in target project. This intended to be a code-list but no codes are given in the standard';


--
-- TOC entry 245 (class 1259 OID 23079461)
-- Name: property_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_element (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_element_id integer CONSTRAINT property_desc_element_property_desc_element_id_not_null1 NOT NULL
);


--
-- TOC entry 5517 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE property_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_element IS 'Descriptive properties for the Element feature of interest';


--
-- TOC entry 5518 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN property_desc_element.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.label IS 'Short label for this property';


--
-- TOC entry 5519 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN property_desc_element.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- TOC entry 5520 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN property_desc_element.property_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_element.property_desc_element_id IS 'Synthetic primary key.';


--
-- TOC entry 289 (class 1259 OID 23080493)
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
-- TOC entry 243 (class 1259 OID 23079437)
-- Name: property_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_plot (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_plot_id integer CONSTRAINT property_desc_plot_property_desc_plot_id_not_null1 NOT NULL
);


--
-- TOC entry 5521 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE property_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_plot IS 'Descriptive properties for the Plot feature of interest';


--
-- TOC entry 5522 (class 0 OID 0)
-- Dependencies: 243
-- Name: COLUMN property_desc_plot.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.label IS 'Short label for this property';


--
-- TOC entry 5523 (class 0 OID 0)
-- Dependencies: 243
-- Name: COLUMN property_desc_plot.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- TOC entry 5524 (class 0 OID 0)
-- Dependencies: 243
-- Name: COLUMN property_desc_plot.property_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_plot.property_desc_plot_id IS 'Synthetic primary key.';


--
-- TOC entry 290 (class 1259 OID 23080509)
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
-- TOC entry 244 (class 1259 OID 23079449)
-- Name: property_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_profile (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_profile_id integer CONSTRAINT property_desc_profile_property_desc_profile_id_not_null1 NOT NULL
);


--
-- TOC entry 5525 (class 0 OID 0)
-- Dependencies: 244
-- Name: TABLE property_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_profile IS 'Descriptive properties for the Profile feature of interest';


--
-- TOC entry 5526 (class 0 OID 0)
-- Dependencies: 244
-- Name: COLUMN property_desc_profile.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.label IS 'Short label for this property';


--
-- TOC entry 5527 (class 0 OID 0)
-- Dependencies: 244
-- Name: COLUMN property_desc_profile.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- TOC entry 5528 (class 0 OID 0)
-- Dependencies: 244
-- Name: COLUMN property_desc_profile.property_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_profile.property_desc_profile_id IS 'Synthetic primary key.';


--
-- TOC entry 291 (class 1259 OID 23080525)
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
-- TOC entry 268 (class 1259 OID 23079943)
-- Name: property_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_specimen (
    label character varying NOT NULL,
    definition character varying NOT NULL,
    property_desc_specimen_id integer CONSTRAINT property_desc_specimen_property_desc_specimen_id_not_null1 NOT NULL
);


--
-- TOC entry 5529 (class 0 OID 0)
-- Dependencies: 268
-- Name: TABLE property_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_specimen IS 'Descriptive properties for the Specimen feature of interest';


--
-- TOC entry 5530 (class 0 OID 0)
-- Dependencies: 268
-- Name: COLUMN property_desc_specimen.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.label IS 'Short label for this property';


--
-- TOC entry 5531 (class 0 OID 0)
-- Dependencies: 268
-- Name: COLUMN property_desc_specimen.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.definition IS 'Full semantic definition of this property, can be a URI to the corresponding code in a controled vocabulary (e.g. GloSIS).';


--
-- TOC entry 5532 (class 0 OID 0)
-- Dependencies: 268
-- Name: COLUMN property_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_specimen.property_desc_specimen_id IS 'Synthetic primary key.';


--
-- TOC entry 292 (class 1259 OID 23080541)
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
-- TOC entry 242 (class 1259 OID 23079425)
-- Name: property_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_desc_surface (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_desc_surface_id integer CONSTRAINT property_desc_surface_property_desc_surface_id_not_null1 NOT NULL
);


--
-- TOC entry 5533 (class 0 OID 0)
-- Dependencies: 242
-- Name: TABLE property_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5534 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN property_desc_surface.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.label IS 'Short label for this property';


--
-- TOC entry 5535 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN property_desc_surface.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- TOC entry 5536 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN property_desc_surface.property_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_desc_surface.property_desc_surface_id IS 'Synthetic primary key.';


--
-- TOC entry 293 (class 1259 OID 23080556)
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
-- TOC entry 240 (class 1259 OID 23079396)
-- Name: property_phys_chem; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.property_phys_chem (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    property_phys_chem_id integer CONSTRAINT property_phys_chem_property_phys_chem_id_not_null1 NOT NULL
);


--
-- TOC entry 5537 (class 0 OID 0)
-- Dependencies: 240
-- Name: TABLE property_phys_chem; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.property_phys_chem IS 'Physio-chemical properties for the Element feature of interest';


--
-- TOC entry 5538 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN property_phys_chem.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.label IS 'Short label for this property';


--
-- TOC entry 5539 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN property_phys_chem.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this property';


--
-- TOC entry 5540 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN property_phys_chem.property_phys_chem_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.property_phys_chem.property_phys_chem_id IS 'Synthetic primary key.';


--
-- TOC entry 294 (class 1259 OID 23080572)
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
-- TOC entry 262 (class 1259 OID 23079726)
-- Name: result_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_element (
    element_id integer NOT NULL,
    property_desc_element_id integer NOT NULL,
    thesaurus_desc_element_id integer NOT NULL
);


--
-- TOC entry 5541 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE result_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_element IS 'Descriptive results for the Element feature interest.';


--
-- TOC entry 5542 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN result_desc_element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_element.element_id IS 'Foreign key to the corresponding Element feature of interest.';


--
-- TOC entry 261 (class 1259 OID 23079709)
-- Name: result_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_profile (
    profile_id integer NOT NULL,
    property_desc_profile_id integer NOT NULL,
    thesaurus_desc_profile_id integer NOT NULL
);


--
-- TOC entry 5543 (class 0 OID 0)
-- Dependencies: 261
-- Name: TABLE result_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_profile IS 'Descriptive results for the Profile feature interest.';


--
-- TOC entry 5544 (class 0 OID 0)
-- Dependencies: 261
-- Name: COLUMN result_desc_profile.profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_profile.profile_id IS 'Foreign key to the corresponding Profile feature of interest.';


--
-- TOC entry 280 (class 1259 OID 23080189)
-- Name: result_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_specimen (
    specimen_id integer NOT NULL,
    property_desc_specimen_id integer NOT NULL,
    thesaurus_desc_specimen_id integer NOT NULL
);


--
-- TOC entry 5545 (class 0 OID 0)
-- Dependencies: 280
-- Name: TABLE result_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_specimen IS 'Descriptive results for the Specimen feature interest.';


--
-- TOC entry 5546 (class 0 OID 0)
-- Dependencies: 280
-- Name: COLUMN result_desc_specimen.specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.specimen_id IS 'Foreign key to the corresponding Specimen feature of interest.';


--
-- TOC entry 5547 (class 0 OID 0)
-- Dependencies: 280
-- Name: COLUMN result_desc_specimen.property_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.property_desc_specimen_id IS 'Partial foreign key to the corresponding Observation.';


--
-- TOC entry 5548 (class 0 OID 0)
-- Dependencies: 280
-- Name: COLUMN result_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_specimen.thesaurus_desc_specimen_id IS 'Partial foreign key to the corresponding Observation.';


--
-- TOC entry 259 (class 1259 OID 23079675)
-- Name: result_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.result_desc_surface (
    surface_id integer NOT NULL,
    property_desc_surface_id integer NOT NULL,
    thesaurus_desc_surface_id integer NOT NULL
);


--
-- TOC entry 5549 (class 0 OID 0)
-- Dependencies: 259
-- Name: TABLE result_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_desc_surface IS 'Descriptive results for the Surface feature interest.';


--
-- TOC entry 5550 (class 0 OID 0)
-- Dependencies: 259
-- Name: COLUMN result_desc_surface.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_desc_surface.surface_id IS 'Foreign key to the corresponding Surface feature of interest.';


--
-- TOC entry 273 (class 1259 OID 23080064)
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
-- TOC entry 5551 (class 0 OID 0)
-- Dependencies: 273
-- Name: result_numerical_specimen_result_numerical_specimen_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_numerical_specimen_result_numerical_specimen_id_seq OWNED BY core.result_phys_chem_specimen.result_phys_chem_specimen_id;


--
-- TOC entry 258 (class 1259 OID 23079651)
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
-- TOC entry 5552 (class 0 OID 0)
-- Dependencies: 258
-- Name: TABLE result_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.result_phys_chem_element IS 'Physio-chemical results for the Element feature interest.';


--
-- TOC entry 5553 (class 0 OID 0)
-- Dependencies: 258
-- Name: COLUMN result_phys_chem_element.result_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.result_phys_chem_element_id IS 'Synthetic primary key.';


--
-- TOC entry 5554 (class 0 OID 0)
-- Dependencies: 258
-- Name: COLUMN result_phys_chem_element.observation_phys_chem_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.observation_phys_chem_element_id IS 'Foreign key to the corresponding physio-chemical observation.';


--
-- TOC entry 5555 (class 0 OID 0)
-- Dependencies: 258
-- Name: COLUMN result_phys_chem_element.element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.element_id IS 'Foreign key to the corresponding Element instance.';


--
-- TOC entry 5556 (class 0 OID 0)
-- Dependencies: 258
-- Name: COLUMN result_phys_chem_element.value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.result_phys_chem_element.value IS 'Numerical value resulting from applying the refered observation to the refered profile element.';


--
-- TOC entry 257 (class 1259 OID 23079650)
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
-- TOC entry 5557 (class 0 OID 0)
-- Dependencies: 257
-- Name: result_phys_chem_result_phys_chem_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.result_phys_chem_result_phys_chem_id_seq OWNED BY core.result_phys_chem_element.result_phys_chem_element_id;


--
-- TOC entry 295 (class 1259 OID 23080588)
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
-- TOC entry 266 (class 1259 OID 23079896)
-- Name: specimen_prep_process; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_prep_process (
    specimen_transport_id integer,
    specimen_storage_id integer,
    definition character varying NOT NULL,
    specimen_prep_process_id integer NOT NULL
);


--
-- TOC entry 5558 (class 0 OID 0)
-- Dependencies: 266
-- Name: TABLE specimen_prep_process; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_prep_process IS 'Describes the preparation process of a soil Specimen. Contains information that does not result from observation(s).';


--
-- TOC entry 5559 (class 0 OID 0)
-- Dependencies: 266
-- Name: COLUMN specimen_prep_process.specimen_transport_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_transport_id IS 'Foreign key for the corresponding mode of transport';


--
-- TOC entry 5560 (class 0 OID 0)
-- Dependencies: 266
-- Name: COLUMN specimen_prep_process.specimen_storage_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_storage_id IS 'Foreign key for the corresponding mode of storage';


--
-- TOC entry 5561 (class 0 OID 0)
-- Dependencies: 266
-- Name: COLUMN specimen_prep_process.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.definition IS 'Further details necessary to define the preparation process.';


--
-- TOC entry 5562 (class 0 OID 0)
-- Dependencies: 266
-- Name: COLUMN specimen_prep_process.specimen_prep_process_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_prep_process.specimen_prep_process_id IS 'Synthetic primary key.';


--
-- TOC entry 297 (class 1259 OID 23080635)
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
-- TOC entry 296 (class 1259 OID 23080614)
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
-- TOC entry 265 (class 1259 OID 23079883)
-- Name: specimen_storage; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_storage (
    label character varying NOT NULL,
    definition character varying,
    specimen_storage_id integer NOT NULL
);


--
-- TOC entry 5563 (class 0 OID 0)
-- Dependencies: 265
-- Name: TABLE specimen_storage; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_storage IS 'Modes of storage of a soil Specimen, part of the Specimen preparation process.';


--
-- TOC entry 5564 (class 0 OID 0)
-- Dependencies: 265
-- Name: COLUMN specimen_storage.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.label IS 'Short label for the storage mode.';


--
-- TOC entry 5565 (class 0 OID 0)
-- Dependencies: 265
-- Name: COLUMN specimen_storage.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.definition IS 'Long definition providing all the necessary details for the storage mode.';


--
-- TOC entry 5566 (class 0 OID 0)
-- Dependencies: 265
-- Name: COLUMN specimen_storage.specimen_storage_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_storage.specimen_storage_id IS 'Synthetic primary key.';


--
-- TOC entry 298 (class 1259 OID 23080651)
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
-- TOC entry 264 (class 1259 OID 23079870)
-- Name: specimen_transport; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.specimen_transport (
    label character varying NOT NULL,
    definition character varying,
    specimen_transport_id integer NOT NULL
);


--
-- TOC entry 5567 (class 0 OID 0)
-- Dependencies: 264
-- Name: TABLE specimen_transport; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.specimen_transport IS 'Modes of transport of a soil Specimen, part of the Specimen preparation process.';


--
-- TOC entry 5568 (class 0 OID 0)
-- Dependencies: 264
-- Name: COLUMN specimen_transport.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.label IS 'Short label for the transport mode.';


--
-- TOC entry 5569 (class 0 OID 0)
-- Dependencies: 264
-- Name: COLUMN specimen_transport.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.definition IS 'Long definition providing all the necessary details for the transport mode.';


--
-- TOC entry 5570 (class 0 OID 0)
-- Dependencies: 264
-- Name: COLUMN specimen_transport.specimen_transport_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.specimen_transport.specimen_transport_id IS 'Synthetic primary key.';


--
-- TOC entry 299 (class 1259 OID 23080668)
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
-- TOC entry 237 (class 1259 OID 23079329)
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
-- TOC entry 5571 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.surface IS 'Surface is a subtype of Plot with a shape geometry. Surfaces may be located within other
surfaces.';


--
-- TOC entry 5572 (class 0 OID 0)
-- Dependencies: 237
-- Name: COLUMN surface.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.site_id IS 'Foreign key to Site table';


--
-- TOC entry 5573 (class 0 OID 0)
-- Dependencies: 237
-- Name: COLUMN surface.shape; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.shape IS 'Site extent expressed with geodetic coordinates of the site. Note the uncertainty associated with the WGS84 datum ensemble.';


--
-- TOC entry 5574 (class 0 OID 0)
-- Dependencies: 237
-- Name: COLUMN surface.time_stamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.time_stamp IS 'Time stamp of the plot, if known. Property re-used from GloSIS.';


--
-- TOC entry 5575 (class 0 OID 0)
-- Dependencies: 237
-- Name: COLUMN surface.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface.surface_id IS 'Synthetic primary key.';


--
-- TOC entry 282 (class 1259 OID 23080246)
-- Name: surface_individual; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.surface_individual (
    surface_id integer NOT NULL,
    individual_id integer NOT NULL
);


--
-- TOC entry 5576 (class 0 OID 0)
-- Dependencies: 282
-- Name: TABLE surface_individual; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.surface_individual IS 'Identifies the individual(s) responsible for surveying a surface';


--
-- TOC entry 5577 (class 0 OID 0)
-- Dependencies: 282
-- Name: COLUMN surface_individual.surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface_individual.surface_id IS 'Foreign key to the surface table, identifies the surface surveyed';


--
-- TOC entry 5578 (class 0 OID 0)
-- Dependencies: 282
-- Name: COLUMN surface_individual.individual_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.surface_individual.individual_id IS 'Foreign key to the individual table, indicates the individual responsible for surveying the surface.';


--
-- TOC entry 300 (class 1259 OID 23080685)
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
-- TOC entry 249 (class 1259 OID 23079509)
-- Name: thesaurus_desc_element; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_element (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_element_id integer CONSTRAINT thesaurus_desc_element_thesaurus_desc_element_id_not_null1 NOT NULL
);


--
-- TOC entry 5579 (class 0 OID 0)
-- Dependencies: 249
-- Name: TABLE thesaurus_desc_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_element IS 'Vocabularies for the descriptive properties associated with the Element feature of interest. Corresponds to all GloSIS code-lists associated with the Horizon and Layer.';


--
-- TOC entry 5580 (class 0 OID 0)
-- Dependencies: 249
-- Name: COLUMN thesaurus_desc_element.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.label IS 'Short label for this term';


--
-- TOC entry 5581 (class 0 OID 0)
-- Dependencies: 249
-- Name: COLUMN thesaurus_desc_element.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- TOC entry 5582 (class 0 OID 0)
-- Dependencies: 249
-- Name: COLUMN thesaurus_desc_element.thesaurus_desc_element_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_element.thesaurus_desc_element_id IS 'Synthetic primary key.';


--
-- TOC entry 301 (class 1259 OID 23080717)
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
-- TOC entry 247 (class 1259 OID 23079485)
-- Name: thesaurus_desc_plot; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_plot (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_plot_id integer CONSTRAINT thesaurus_desc_plot_thesaurus_desc_plot_id_not_null1 NOT NULL
);


--
-- TOC entry 5583 (class 0 OID 0)
-- Dependencies: 247
-- Name: TABLE thesaurus_desc_plot; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_plot IS 'Descriptive properties for the Plot feature of interest';


--
-- TOC entry 5584 (class 0 OID 0)
-- Dependencies: 247
-- Name: COLUMN thesaurus_desc_plot.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.label IS 'Short label for this term';


--
-- TOC entry 5585 (class 0 OID 0)
-- Dependencies: 247
-- Name: COLUMN thesaurus_desc_plot.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- TOC entry 5586 (class 0 OID 0)
-- Dependencies: 247
-- Name: COLUMN thesaurus_desc_plot.thesaurus_desc_plot_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_plot.thesaurus_desc_plot_id IS 'Synthetic primary key.';


--
-- TOC entry 302 (class 1259 OID 23080732)
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
-- TOC entry 248 (class 1259 OID 23079497)
-- Name: thesaurus_desc_profile; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_profile (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_profile_id integer CONSTRAINT thesaurus_desc_profile_thesaurus_desc_profile_id_not_null1 NOT NULL
);


--
-- TOC entry 5587 (class 0 OID 0)
-- Dependencies: 248
-- Name: TABLE thesaurus_desc_profile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_profile IS 'Vocabularies for the descriptive properties associated with the Profile feature of interest. Contains the GloSIS code-lists for Profile.';


--
-- TOC entry 5588 (class 0 OID 0)
-- Dependencies: 248
-- Name: COLUMN thesaurus_desc_profile.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.label IS 'Short label for this term';


--
-- TOC entry 5589 (class 0 OID 0)
-- Dependencies: 248
-- Name: COLUMN thesaurus_desc_profile.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- TOC entry 5590 (class 0 OID 0)
-- Dependencies: 248
-- Name: COLUMN thesaurus_desc_profile.thesaurus_desc_profile_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_profile.thesaurus_desc_profile_id IS 'Synthetic primary key.';


--
-- TOC entry 303 (class 1259 OID 23080747)
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
-- TOC entry 269 (class 1259 OID 23079955)
-- Name: thesaurus_desc_specimen; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_specimen (
    label character varying NOT NULL,
    definition character varying NOT NULL,
    thesaurus_desc_specimen_id integer CONSTRAINT thesaurus_desc_specimen_thesaurus_desc_specimen_id_not_null1 NOT NULL
);


--
-- TOC entry 5591 (class 0 OID 0)
-- Dependencies: 269
-- Name: TABLE thesaurus_desc_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_specimen IS 'Vocabularies for the descriptive properties associated with the Specimen feature of interest. This table is intended to host the code-lists necessary for descriptive observations on Specimen.';


--
-- TOC entry 5592 (class 0 OID 0)
-- Dependencies: 269
-- Name: COLUMN thesaurus_desc_specimen.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.label IS 'Short label for this term';


--
-- TOC entry 5593 (class 0 OID 0)
-- Dependencies: 269
-- Name: COLUMN thesaurus_desc_specimen.definition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.definition IS 'Full semantic definition of this term, can be a URI to the corresponding code in a controled vocabulary (e.g. GloSIS).';


--
-- TOC entry 5594 (class 0 OID 0)
-- Dependencies: 269
-- Name: COLUMN thesaurus_desc_specimen.thesaurus_desc_specimen_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_specimen.thesaurus_desc_specimen_id IS 'Synthetic primary key.';


--
-- TOC entry 304 (class 1259 OID 23080762)
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
-- TOC entry 246 (class 1259 OID 23079473)
-- Name: thesaurus_desc_surface; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.thesaurus_desc_surface (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    thesaurus_desc_surface_id integer CONSTRAINT thesaurus_desc_surface_thesaurus_desc_surface_id_not_null1 NOT NULL
);


--
-- TOC entry 5595 (class 0 OID 0)
-- Dependencies: 246
-- Name: TABLE thesaurus_desc_surface; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.thesaurus_desc_surface IS 'Descriptive properties for the Surface feature of interest';


--
-- TOC entry 5596 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN thesaurus_desc_surface.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.label IS 'Short label for this term';


--
-- TOC entry 5597 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN thesaurus_desc_surface.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.uri IS 'URI to the corresponding code in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this term';


--
-- TOC entry 5598 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN thesaurus_desc_surface.thesaurus_desc_surface_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.thesaurus_desc_surface.thesaurus_desc_surface_id IS 'Synthetic primary key.';


--
-- TOC entry 305 (class 1259 OID 23080777)
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
-- TOC entry 254 (class 1259 OID 23079609)
-- Name: unit_of_measure; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.unit_of_measure (
    label character varying NOT NULL,
    uri character varying NOT NULL,
    unit_of_measure_id integer CONSTRAINT unit_of_measure_unit_of_measure_id_not_null1 NOT NULL
);


--
-- TOC entry 5599 (class 0 OID 0)
-- Dependencies: 254
-- Name: TABLE unit_of_measure; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.unit_of_measure IS 'Unit of measure';


--
-- TOC entry 5600 (class 0 OID 0)
-- Dependencies: 254
-- Name: COLUMN unit_of_measure.label; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.label IS 'Short label for this unit of measure';


--
-- TOC entry 5601 (class 0 OID 0)
-- Dependencies: 254
-- Name: COLUMN unit_of_measure.uri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.uri IS 'URI to the corresponding unit of measuree in a controled vocabulary (e.g. GloSIS). Follow this URI for the full definition and semantics of this unit of measure';


--
-- TOC entry 5602 (class 0 OID 0)
-- Dependencies: 254
-- Name: COLUMN unit_of_measure.unit_of_measure_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.unit_of_measure.unit_of_measure_id IS 'Synthetic primary key.';


--
-- TOC entry 306 (class 1259 OID 23080792)
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
-- TOC entry 226 (class 1259 OID 23078153)
-- Name: current; Type: TABLE; Schema: graphile_migrate; Owner: -
--

CREATE TABLE graphile_migrate.current (
    filename text DEFAULT 'current.sql'::text NOT NULL,
    content text NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 225 (class 1259 OID 23078137)
-- Name: migrations; Type: TABLE; Schema: graphile_migrate; Owner: -
--

CREATE TABLE graphile_migrate.migrations (
    hash text NOT NULL,
    previous_hash text,
    filename text NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 307 (class 1259 OID 23080812)
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
-- TOC entry 308 (class 1259 OID 23080832)
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
-- TOC entry 309 (class 1259 OID 23080862)
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
-- TOC entry 278 (class 1259 OID 23080142)
-- Name: organisation_unit; Type: TABLE; Schema: metadata; Owner: -
--

CREATE TABLE metadata.organisation_unit (
    name character varying NOT NULL,
    organisation_id integer NOT NULL,
    organisation_unit_id integer NOT NULL
);


--
-- TOC entry 5603 (class 0 OID 0)
-- Dependencies: 278
-- Name: TABLE organisation_unit; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON TABLE metadata.organisation_unit IS 'Captures the data property organisation-unit and object property hasOrganisationUnit in VCard. Defines the internal structure of the organisation, apart from the departmental hierarchy.';


--
-- TOC entry 5604 (class 0 OID 0)
-- Dependencies: 278
-- Name: COLUMN organisation_unit.name; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.name IS 'Name of the organisation unit.';


--
-- TOC entry 5605 (class 0 OID 0)
-- Dependencies: 278
-- Name: COLUMN organisation_unit.organisation_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.organisation_id IS 'Foreign key to the enclosing organisation, in case of a department or division of a larger organisation.';


--
-- TOC entry 5606 (class 0 OID 0)
-- Dependencies: 278
-- Name: COLUMN organisation_unit.organisation_unit_id; Type: COMMENT; Schema: metadata; Owner: -
--

COMMENT ON COLUMN metadata.organisation_unit.organisation_unit_id IS 'Synthetic primary key.';


--
-- TOC entry 310 (class 1259 OID 23080902)
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
-- TOC entry 4862 (class 2604 OID 23079624)
-- Name: observation_phys_chem_element observation_phys_chem_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element ALTER COLUMN observation_phys_chem_element_id SET DEFAULT nextval('core.observation_phys_chem_observation_phys_chem_id_seq'::regclass);


--
-- TOC entry 4864 (class 2604 OID 23080038)
-- Name: observation_phys_chem_specimen observation_phys_chem_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen ALTER COLUMN observation_phys_chem_specimen_id SET DEFAULT nextval('core.observation_numerical_specime_observation_numerical_specime_seq'::regclass);


--
-- TOC entry 4863 (class 2604 OID 23079654)
-- Name: result_phys_chem_element result_phys_chem_element_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element ALTER COLUMN result_phys_chem_element_id SET DEFAULT nextval('core.result_phys_chem_result_phys_chem_id_seq'::regclass);


--
-- TOC entry 4865 (class 2604 OID 23080068)
-- Name: result_phys_chem_specimen result_phys_chem_specimen_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen ALTER COLUMN result_phys_chem_specimen_id SET DEFAULT nextval('core.result_numerical_specimen_result_numerical_specimen_id_seq'::regclass);


--
-- TOC entry 5301 (class 0 OID 23079376)
-- Dependencies: 239
-- Data for Name: element; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5315 (class 0 OID 23079587)
-- Dependencies: 253
-- Data for Name: observation_desc_element; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.observation_desc_element VALUES (107, 97, 1);
INSERT INTO core.observation_desc_element VALUES (107, 98, 1);
INSERT INTO core.observation_desc_element VALUES (107, 99, 1);
INSERT INTO core.observation_desc_element VALUES (107, 100, 1);
INSERT INTO core.observation_desc_element VALUES (107, 101, 1);
INSERT INTO core.observation_desc_element VALUES (107, 102, 1);
INSERT INTO core.observation_desc_element VALUES (107, 103, 1);
INSERT INTO core.observation_desc_element VALUES (107, 104, 1);
INSERT INTO core.observation_desc_element VALUES (107, 105, 1);
INSERT INTO core.observation_desc_element VALUES (107, 106, 1);
INSERT INTO core.observation_desc_element VALUES (107, 107, 1);
INSERT INTO core.observation_desc_element VALUES (107, 108, 1);
INSERT INTO core.observation_desc_element VALUES (107, 109, 1);
INSERT INTO core.observation_desc_element VALUES (107, 110, 1);
INSERT INTO core.observation_desc_element VALUES (107, 111, 1);
INSERT INTO core.observation_desc_element VALUES (107, 112, 1);
INSERT INTO core.observation_desc_element VALUES (107, 113, 1);
INSERT INTO core.observation_desc_element VALUES (107, 114, 1);
INSERT INTO core.observation_desc_element VALUES (100, 50, 1);
INSERT INTO core.observation_desc_element VALUES (100, 51, 1);
INSERT INTO core.observation_desc_element VALUES (100, 52, 1);
INSERT INTO core.observation_desc_element VALUES (100, 53, 1);
INSERT INTO core.observation_desc_element VALUES (100, 54, 1);
INSERT INTO core.observation_desc_element VALUES (100, 55, 1);
INSERT INTO core.observation_desc_element VALUES (104, 80, 1);
INSERT INTO core.observation_desc_element VALUES (104, 81, 1);
INSERT INTO core.observation_desc_element VALUES (104, 82, 1);
INSERT INTO core.observation_desc_element VALUES (88, 1, 1);
INSERT INTO core.observation_desc_element VALUES (88, 2, 1);
INSERT INTO core.observation_desc_element VALUES (88, 3, 1);
INSERT INTO core.observation_desc_element VALUES (88, 4, 1);
INSERT INTO core.observation_desc_element VALUES (152, 286, 1);
INSERT INTO core.observation_desc_element VALUES (152, 287, 1);
INSERT INTO core.observation_desc_element VALUES (152, 288, 1);
INSERT INTO core.observation_desc_element VALUES (152, 289, 1);
INSERT INTO core.observation_desc_element VALUES (152, 290, 1);
INSERT INTO core.observation_desc_element VALUES (117, 162, 1);
INSERT INTO core.observation_desc_element VALUES (117, 163, 1);
INSERT INTO core.observation_desc_element VALUES (117, 164, 1);
INSERT INTO core.observation_desc_element VALUES (117, 165, 1);
INSERT INTO core.observation_desc_element VALUES (117, 166, 1);
INSERT INTO core.observation_desc_element VALUES (117, 167, 1);
INSERT INTO core.observation_desc_element VALUES (117, 168, 1);
INSERT INTO core.observation_desc_element VALUES (117, 169, 1);
INSERT INTO core.observation_desc_element VALUES (117, 170, 1);
INSERT INTO core.observation_desc_element VALUES (92, 25, 1);
INSERT INTO core.observation_desc_element VALUES (92, 26, 1);
INSERT INTO core.observation_desc_element VALUES (92, 27, 1);
INSERT INTO core.observation_desc_element VALUES (92, 28, 1);
INSERT INTO core.observation_desc_element VALUES (92, 29, 1);
INSERT INTO core.observation_desc_element VALUES (103, 73, 1);
INSERT INTO core.observation_desc_element VALUES (103, 74, 1);
INSERT INTO core.observation_desc_element VALUES (103, 75, 1);
INSERT INTO core.observation_desc_element VALUES (103, 76, 1);
INSERT INTO core.observation_desc_element VALUES (103, 77, 1);
INSERT INTO core.observation_desc_element VALUES (103, 78, 1);
INSERT INTO core.observation_desc_element VALUES (103, 79, 1);
INSERT INTO core.observation_desc_element VALUES (108, 115, 1);
INSERT INTO core.observation_desc_element VALUES (108, 116, 1);
INSERT INTO core.observation_desc_element VALUES (108, 117, 1);
INSERT INTO core.observation_desc_element VALUES (108, 118, 1);
INSERT INTO core.observation_desc_element VALUES (108, 119, 1);
INSERT INTO core.observation_desc_element VALUES (108, 120, 1);
INSERT INTO core.observation_desc_element VALUES (108, 121, 1);
INSERT INTO core.observation_desc_element VALUES (108, 122, 1);
INSERT INTO core.observation_desc_element VALUES (108, 123, 1);
INSERT INTO core.observation_desc_element VALUES (112, 138, 1);
INSERT INTO core.observation_desc_element VALUES (112, 139, 1);
INSERT INTO core.observation_desc_element VALUES (112, 140, 1);
INSERT INTO core.observation_desc_element VALUES (112, 141, 1);
INSERT INTO core.observation_desc_element VALUES (118, 171, 1);
INSERT INTO core.observation_desc_element VALUES (118, 172, 1);
INSERT INTO core.observation_desc_element VALUES (118, 173, 1);
INSERT INTO core.observation_desc_element VALUES (118, 174, 1);
INSERT INTO core.observation_desc_element VALUES (118, 175, 1);
INSERT INTO core.observation_desc_element VALUES (118, 176, 1);
INSERT INTO core.observation_desc_element VALUES (118, 177, 1);
INSERT INTO core.observation_desc_element VALUES (118, 178, 1);
INSERT INTO core.observation_desc_element VALUES (118, 179, 1);
INSERT INTO core.observation_desc_element VALUES (118, 180, 1);
INSERT INTO core.observation_desc_element VALUES (118, 181, 1);
INSERT INTO core.observation_desc_element VALUES (118, 182, 1);
INSERT INTO core.observation_desc_element VALUES (118, 183, 1);
INSERT INTO core.observation_desc_element VALUES (118, 184, 1);
INSERT INTO core.observation_desc_element VALUES (90, 17, 1);
INSERT INTO core.observation_desc_element VALUES (90, 18, 1);
INSERT INTO core.observation_desc_element VALUES (90, 19, 1);
INSERT INTO core.observation_desc_element VALUES (90, 20, 1);
INSERT INTO core.observation_desc_element VALUES (101, 56, 1);
INSERT INTO core.observation_desc_element VALUES (101, 57, 1);
INSERT INTO core.observation_desc_element VALUES (101, 58, 1);
INSERT INTO core.observation_desc_element VALUES (101, 59, 1);
INSERT INTO core.observation_desc_element VALUES (130, 210, 1);
INSERT INTO core.observation_desc_element VALUES (130, 211, 1);
INSERT INTO core.observation_desc_element VALUES (130, 212, 1);
INSERT INTO core.observation_desc_element VALUES (130, 213, 1);
INSERT INTO core.observation_desc_element VALUES (139, 243, 1);
INSERT INTO core.observation_desc_element VALUES (139, 244, 1);
INSERT INTO core.observation_desc_element VALUES (139, 245, 1);
INSERT INTO core.observation_desc_element VALUES (139, 246, 1);
INSERT INTO core.observation_desc_element VALUES (139, 247, 1);
INSERT INTO core.observation_desc_element VALUES (125, 204, 1);
INSERT INTO core.observation_desc_element VALUES (125, 205, 1);
INSERT INTO core.observation_desc_element VALUES (125, 206, 1);
INSERT INTO core.observation_desc_element VALUES (125, 207, 1);
INSERT INTO core.observation_desc_element VALUES (125, 208, 1);
INSERT INTO core.observation_desc_element VALUES (125, 209, 1);
INSERT INTO core.observation_desc_element VALUES (153, 291, 1);
INSERT INTO core.observation_desc_element VALUES (153, 292, 1);
INSERT INTO core.observation_desc_element VALUES (153, 293, 1);
INSERT INTO core.observation_desc_element VALUES (153, 294, 1);
INSERT INTO core.observation_desc_element VALUES (153, 295, 1);
INSERT INTO core.observation_desc_element VALUES (153, 296, 1);
INSERT INTO core.observation_desc_element VALUES (153, 297, 1);
INSERT INTO core.observation_desc_element VALUES (153, 298, 1);
INSERT INTO core.observation_desc_element VALUES (148, 275, 1);
INSERT INTO core.observation_desc_element VALUES (148, 276, 1);
INSERT INTO core.observation_desc_element VALUES (148, 277, 1);
INSERT INTO core.observation_desc_element VALUES (148, 278, 1);
INSERT INTO core.observation_desc_element VALUES (148, 279, 1);
INSERT INTO core.observation_desc_element VALUES (89, 5, 1);
INSERT INTO core.observation_desc_element VALUES (89, 6, 1);
INSERT INTO core.observation_desc_element VALUES (89, 7, 1);
INSERT INTO core.observation_desc_element VALUES (89, 8, 1);
INSERT INTO core.observation_desc_element VALUES (89, 9, 1);
INSERT INTO core.observation_desc_element VALUES (89, 10, 1);
INSERT INTO core.observation_desc_element VALUES (89, 11, 1);
INSERT INTO core.observation_desc_element VALUES (89, 12, 1);
INSERT INTO core.observation_desc_element VALUES (89, 13, 1);
INSERT INTO core.observation_desc_element VALUES (138, 291, 1);
INSERT INTO core.observation_desc_element VALUES (138, 292, 1);
INSERT INTO core.observation_desc_element VALUES (138, 293, 1);
INSERT INTO core.observation_desc_element VALUES (138, 294, 1);
INSERT INTO core.observation_desc_element VALUES (138, 295, 1);
INSERT INTO core.observation_desc_element VALUES (138, 296, 1);
INSERT INTO core.observation_desc_element VALUES (138, 297, 1);
INSERT INTO core.observation_desc_element VALUES (138, 298, 1);
INSERT INTO core.observation_desc_element VALUES (149, 280, 1);
INSERT INTO core.observation_desc_element VALUES (149, 281, 1);
INSERT INTO core.observation_desc_element VALUES (149, 282, 1);
INSERT INTO core.observation_desc_element VALUES (149, 283, 1);
INSERT INTO core.observation_desc_element VALUES (149, 284, 1);
INSERT INTO core.observation_desc_element VALUES (149, 285, 1);
INSERT INTO core.observation_desc_element VALUES (119, 185, 1);
INSERT INTO core.observation_desc_element VALUES (119, 186, 1);
INSERT INTO core.observation_desc_element VALUES (119, 187, 1);
INSERT INTO core.observation_desc_element VALUES (119, 188, 1);
INSERT INTO core.observation_desc_element VALUES (119, 189, 1);
INSERT INTO core.observation_desc_element VALUES (134, 223, 1);
INSERT INTO core.observation_desc_element VALUES (134, 224, 1);
INSERT INTO core.observation_desc_element VALUES (134, 225, 1);
INSERT INTO core.observation_desc_element VALUES (134, 226, 1);
INSERT INTO core.observation_desc_element VALUES (144, 259, 1);
INSERT INTO core.observation_desc_element VALUES (144, 260, 1);
INSERT INTO core.observation_desc_element VALUES (144, 261, 1);
INSERT INTO core.observation_desc_element VALUES (144, 262, 1);
INSERT INTO core.observation_desc_element VALUES (144, 263, 1);
INSERT INTO core.observation_desc_element VALUES (144, 264, 1);
INSERT INTO core.observation_desc_element VALUES (144, 265, 1);
INSERT INTO core.observation_desc_element VALUES (144, 266, 1);
INSERT INTO core.observation_desc_element VALUES (144, 267, 1);
INSERT INTO core.observation_desc_element VALUES (144, 268, 1);
INSERT INTO core.observation_desc_element VALUES (102, 60, 1);
INSERT INTO core.observation_desc_element VALUES (102, 61, 1);
INSERT INTO core.observation_desc_element VALUES (102, 62, 1);
INSERT INTO core.observation_desc_element VALUES (102, 63, 1);
INSERT INTO core.observation_desc_element VALUES (102, 64, 1);
INSERT INTO core.observation_desc_element VALUES (102, 65, 1);
INSERT INTO core.observation_desc_element VALUES (102, 66, 1);
INSERT INTO core.observation_desc_element VALUES (102, 67, 1);
INSERT INTO core.observation_desc_element VALUES (102, 68, 1);
INSERT INTO core.observation_desc_element VALUES (102, 69, 1);
INSERT INTO core.observation_desc_element VALUES (102, 70, 1);
INSERT INTO core.observation_desc_element VALUES (102, 71, 1);
INSERT INTO core.observation_desc_element VALUES (102, 72, 1);
INSERT INTO core.observation_desc_element VALUES (93, 30, 1);
INSERT INTO core.observation_desc_element VALUES (93, 31, 1);
INSERT INTO core.observation_desc_element VALUES (93, 32, 1);
INSERT INTO core.observation_desc_element VALUES (93, 33, 1);
INSERT INTO core.observation_desc_element VALUES (93, 34, 1);
INSERT INTO core.observation_desc_element VALUES (123, 201, 1);
INSERT INTO core.observation_desc_element VALUES (123, 202, 1);
INSERT INTO core.observation_desc_element VALUES (123, 203, 1);
INSERT INTO core.observation_desc_element VALUES (126, 14, 1);
INSERT INTO core.observation_desc_element VALUES (126, 15, 1);
INSERT INTO core.observation_desc_element VALUES (126, 16, 1);
INSERT INTO core.observation_desc_element VALUES (133, 214, 1);
INSERT INTO core.observation_desc_element VALUES (133, 215, 1);
INSERT INTO core.observation_desc_element VALUES (133, 216, 1);
INSERT INTO core.observation_desc_element VALUES (133, 217, 1);
INSERT INTO core.observation_desc_element VALUES (133, 218, 1);
INSERT INTO core.observation_desc_element VALUES (133, 219, 1);
INSERT INTO core.observation_desc_element VALUES (133, 220, 1);
INSERT INTO core.observation_desc_element VALUES (133, 221, 1);
INSERT INTO core.observation_desc_element VALUES (133, 222, 1);
INSERT INTO core.observation_desc_element VALUES (135, 227, 1);
INSERT INTO core.observation_desc_element VALUES (135, 228, 1);
INSERT INTO core.observation_desc_element VALUES (135, 229, 1);
INSERT INTO core.observation_desc_element VALUES (135, 230, 1);
INSERT INTO core.observation_desc_element VALUES (135, 231, 1);
INSERT INTO core.observation_desc_element VALUES (91, 21, 1);
INSERT INTO core.observation_desc_element VALUES (91, 22, 1);
INSERT INTO core.observation_desc_element VALUES (91, 23, 1);
INSERT INTO core.observation_desc_element VALUES (91, 24, 1);
INSERT INTO core.observation_desc_element VALUES (94, 35, 1);
INSERT INTO core.observation_desc_element VALUES (94, 36, 1);
INSERT INTO core.observation_desc_element VALUES (94, 37, 1);
INSERT INTO core.observation_desc_element VALUES (94, 38, 1);
INSERT INTO core.observation_desc_element VALUES (94, 39, 1);
INSERT INTO core.observation_desc_element VALUES (115, 142, 1);
INSERT INTO core.observation_desc_element VALUES (115, 143, 1);
INSERT INTO core.observation_desc_element VALUES (115, 144, 1);
INSERT INTO core.observation_desc_element VALUES (115, 145, 1);
INSERT INTO core.observation_desc_element VALUES (115, 146, 1);
INSERT INTO core.observation_desc_element VALUES (115, 147, 1);
INSERT INTO core.observation_desc_element VALUES (115, 148, 1);
INSERT INTO core.observation_desc_element VALUES (115, 149, 1);
INSERT INTO core.observation_desc_element VALUES (115, 150, 1);
INSERT INTO core.observation_desc_element VALUES (115, 151, 1);
INSERT INTO core.observation_desc_element VALUES (115, 152, 1);
INSERT INTO core.observation_desc_element VALUES (115, 153, 1);
INSERT INTO core.observation_desc_element VALUES (115, 154, 1);
INSERT INTO core.observation_desc_element VALUES (115, 155, 1);
INSERT INTO core.observation_desc_element VALUES (115, 156, 1);
INSERT INTO core.observation_desc_element VALUES (115, 157, 1);
INSERT INTO core.observation_desc_element VALUES (115, 158, 1);
INSERT INTO core.observation_desc_element VALUES (136, 232, 1);
INSERT INTO core.observation_desc_element VALUES (136, 233, 1);
INSERT INTO core.observation_desc_element VALUES (136, 234, 1);
INSERT INTO core.observation_desc_element VALUES (136, 235, 1);
INSERT INTO core.observation_desc_element VALUES (136, 236, 1);
INSERT INTO core.observation_desc_element VALUES (136, 237, 1);
INSERT INTO core.observation_desc_element VALUES (128, 130, 1);
INSERT INTO core.observation_desc_element VALUES (128, 131, 1);
INSERT INTO core.observation_desc_element VALUES (128, 132, 1);
INSERT INTO core.observation_desc_element VALUES (109, 124, 1);
INSERT INTO core.observation_desc_element VALUES (109, 125, 1);
INSERT INTO core.observation_desc_element VALUES (109, 126, 1);
INSERT INTO core.observation_desc_element VALUES (109, 127, 1);
INSERT INTO core.observation_desc_element VALUES (109, 128, 1);
INSERT INTO core.observation_desc_element VALUES (109, 129, 1);
INSERT INTO core.observation_desc_element VALUES (121, 194, 1);
INSERT INTO core.observation_desc_element VALUES (121, 195, 1);
INSERT INTO core.observation_desc_element VALUES (121, 196, 1);
INSERT INTO core.observation_desc_element VALUES (121, 197, 1);
INSERT INTO core.observation_desc_element VALUES (121, 198, 1);
INSERT INTO core.observation_desc_element VALUES (121, 199, 1);
INSERT INTO core.observation_desc_element VALUES (121, 200, 1);
INSERT INTO core.observation_desc_element VALUES (142, 253, 1);
INSERT INTO core.observation_desc_element VALUES (142, 254, 1);
INSERT INTO core.observation_desc_element VALUES (142, 255, 1);
INSERT INTO core.observation_desc_element VALUES (142, 256, 1);
INSERT INTO core.observation_desc_element VALUES (142, 257, 1);
INSERT INTO core.observation_desc_element VALUES (142, 258, 1);
INSERT INTO core.observation_desc_element VALUES (111, 133, 1);
INSERT INTO core.observation_desc_element VALUES (111, 134, 1);
INSERT INTO core.observation_desc_element VALUES (111, 135, 1);
INSERT INTO core.observation_desc_element VALUES (111, 136, 1);
INSERT INTO core.observation_desc_element VALUES (111, 137, 1);
INSERT INTO core.observation_desc_element VALUES (105, 83, 1);
INSERT INTO core.observation_desc_element VALUES (105, 84, 1);
INSERT INTO core.observation_desc_element VALUES (105, 85, 1);
INSERT INTO core.observation_desc_element VALUES (105, 86, 1);
INSERT INTO core.observation_desc_element VALUES (105, 87, 1);
INSERT INTO core.observation_desc_element VALUES (105, 88, 1);
INSERT INTO core.observation_desc_element VALUES (116, 159, 1);
INSERT INTO core.observation_desc_element VALUES (116, 160, 1);
INSERT INTO core.observation_desc_element VALUES (116, 161, 1);
INSERT INTO core.observation_desc_element VALUES (137, 238, 1);
INSERT INTO core.observation_desc_element VALUES (137, 239, 1);
INSERT INTO core.observation_desc_element VALUES (137, 240, 1);
INSERT INTO core.observation_desc_element VALUES (137, 241, 1);
INSERT INTO core.observation_desc_element VALUES (137, 242, 1);
INSERT INTO core.observation_desc_element VALUES (120, 190, 1);
INSERT INTO core.observation_desc_element VALUES (120, 191, 1);
INSERT INTO core.observation_desc_element VALUES (120, 192, 1);
INSERT INTO core.observation_desc_element VALUES (120, 193, 1);
INSERT INTO core.observation_desc_element VALUES (147, 269, 1);
INSERT INTO core.observation_desc_element VALUES (147, 270, 1);
INSERT INTO core.observation_desc_element VALUES (147, 271, 1);
INSERT INTO core.observation_desc_element VALUES (147, 272, 1);
INSERT INTO core.observation_desc_element VALUES (147, 273, 1);
INSERT INTO core.observation_desc_element VALUES (147, 274, 1);
INSERT INTO core.observation_desc_element VALUES (106, 89, 1);
INSERT INTO core.observation_desc_element VALUES (106, 90, 1);
INSERT INTO core.observation_desc_element VALUES (106, 91, 1);
INSERT INTO core.observation_desc_element VALUES (106, 92, 1);
INSERT INTO core.observation_desc_element VALUES (106, 93, 1);
INSERT INTO core.observation_desc_element VALUES (106, 94, 1);
INSERT INTO core.observation_desc_element VALUES (106, 95, 1);
INSERT INTO core.observation_desc_element VALUES (106, 96, 1);
INSERT INTO core.observation_desc_element VALUES (95, 40, 1);
INSERT INTO core.observation_desc_element VALUES (95, 41, 1);
INSERT INTO core.observation_desc_element VALUES (95, 42, 1);
INSERT INTO core.observation_desc_element VALUES (95, 43, 1);
INSERT INTO core.observation_desc_element VALUES (95, 44, 1);
INSERT INTO core.observation_desc_element VALUES (95, 45, 1);
INSERT INTO core.observation_desc_element VALUES (95, 46, 1);
INSERT INTO core.observation_desc_element VALUES (140, 248, 1);
INSERT INTO core.observation_desc_element VALUES (140, 249, 1);
INSERT INTO core.observation_desc_element VALUES (140, 250, 1);
INSERT INTO core.observation_desc_element VALUES (140, 251, 1);
INSERT INTO core.observation_desc_element VALUES (140, 252, 1);
INSERT INTO core.observation_desc_element VALUES (99, 47, 1);
INSERT INTO core.observation_desc_element VALUES (99, 48, 1);
INSERT INTO core.observation_desc_element VALUES (99, 49, 1);
INSERT INTO core.observation_desc_element VALUES (162, 320, 1);
INSERT INTO core.observation_desc_element VALUES (162, 321, 1);
INSERT INTO core.observation_desc_element VALUES (162, 322, 1);
INSERT INTO core.observation_desc_element VALUES (162, 323, 1);
INSERT INTO core.observation_desc_element VALUES (162, 324, 1);
INSERT INTO core.observation_desc_element VALUES (162, 325, 1);
INSERT INTO core.observation_desc_element VALUES (158, 299, 1);
INSERT INTO core.observation_desc_element VALUES (158, 300, 1);
INSERT INTO core.observation_desc_element VALUES (158, 301, 1);
INSERT INTO core.observation_desc_element VALUES (158, 302, 1);
INSERT INTO core.observation_desc_element VALUES (159, 303, 1);
INSERT INTO core.observation_desc_element VALUES (159, 304, 1);
INSERT INTO core.observation_desc_element VALUES (159, 305, 1);
INSERT INTO core.observation_desc_element VALUES (159, 306, 1);
INSERT INTO core.observation_desc_element VALUES (159, 307, 1);
INSERT INTO core.observation_desc_element VALUES (160, 308, 1);
INSERT INTO core.observation_desc_element VALUES (160, 309, 1);
INSERT INTO core.observation_desc_element VALUES (160, 310, 1);
INSERT INTO core.observation_desc_element VALUES (160, 311, 1);
INSERT INTO core.observation_desc_element VALUES (160, 312, 1);
INSERT INTO core.observation_desc_element VALUES (166, 326, 1);
INSERT INTO core.observation_desc_element VALUES (166, 327, 1);
INSERT INTO core.observation_desc_element VALUES (166, 328, 1);
INSERT INTO core.observation_desc_element VALUES (166, 329, 1);
INSERT INTO core.observation_desc_element VALUES (166, 330, 1);
INSERT INTO core.observation_desc_element VALUES (166, 331, 1);
INSERT INTO core.observation_desc_element VALUES (166, 332, 1);
INSERT INTO core.observation_desc_element VALUES (166, 333, 1);
INSERT INTO core.observation_desc_element VALUES (167, 334, 1);
INSERT INTO core.observation_desc_element VALUES (167, 335, 1);
INSERT INTO core.observation_desc_element VALUES (167, 336, 1);
INSERT INTO core.observation_desc_element VALUES (167, 337, 1);
INSERT INTO core.observation_desc_element VALUES (168, 338, 1);
INSERT INTO core.observation_desc_element VALUES (168, 339, 1);
INSERT INTO core.observation_desc_element VALUES (168, 340, 1);
INSERT INTO core.observation_desc_element VALUES (168, 341, 1);
INSERT INTO core.observation_desc_element VALUES (168, 342, 1);
INSERT INTO core.observation_desc_element VALUES (168, 343, 1);
INSERT INTO core.observation_desc_element VALUES (168, 344, 1);
INSERT INTO core.observation_desc_element VALUES (168, 345, 1);
INSERT INTO core.observation_desc_element VALUES (168, 346, 1);
INSERT INTO core.observation_desc_element VALUES (168, 347, 1);
INSERT INTO core.observation_desc_element VALUES (168, 348, 1);
INSERT INTO core.observation_desc_element VALUES (168, 349, 1);
INSERT INTO core.observation_desc_element VALUES (168, 350, 1);
INSERT INTO core.observation_desc_element VALUES (168, 351, 1);
INSERT INTO core.observation_desc_element VALUES (168, 352, 1);
INSERT INTO core.observation_desc_element VALUES (168, 353, 1);
INSERT INTO core.observation_desc_element VALUES (168, 354, 1);
INSERT INTO core.observation_desc_element VALUES (168, 355, 1);
INSERT INTO core.observation_desc_element VALUES (170, 356, 1);
INSERT INTO core.observation_desc_element VALUES (170, 357, 1);
INSERT INTO core.observation_desc_element VALUES (170, 358, 1);
INSERT INTO core.observation_desc_element VALUES (161, 313, 1);
INSERT INTO core.observation_desc_element VALUES (161, 314, 1);
INSERT INTO core.observation_desc_element VALUES (161, 315, 1);
INSERT INTO core.observation_desc_element VALUES (161, 316, 1);
INSERT INTO core.observation_desc_element VALUES (161, 317, 1);
INSERT INTO core.observation_desc_element VALUES (161, 318, 1);
INSERT INTO core.observation_desc_element VALUES (161, 319, 1);


--
-- TOC entry 5313 (class 0 OID 23079543)
-- Dependencies: 251
-- Data for Name: observation_desc_plot; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.observation_desc_plot VALUES (84, 16, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 8, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 24, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 4, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 20, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 12, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 2, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 18, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 10, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 22, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 6, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 14, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 1, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 11, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 19, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 3, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 23, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 7, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 15, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 25, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 9, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 17, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 5, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 21, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 13, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 26, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 27, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 28, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 29, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 30, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 31, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 32, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 33, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 34, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 35, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 36, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 37, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 38, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 39, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 40, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 41, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 42, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 43, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 44, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 45, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 46, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 47, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 48, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 49, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 50, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 51, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 52, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 53, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 54, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 55, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 56, 1);
INSERT INTO core.observation_desc_plot VALUES (84, 57, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 63, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 64, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 65, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 66, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 67, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 68, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 69, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 70, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 71, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 72, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 73, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 74, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 75, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 76, 1);
INSERT INTO core.observation_desc_plot VALUES (47, 77, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 182, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 183, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 184, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 185, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 186, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 187, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 188, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 189, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 190, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 191, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 192, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 193, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 194, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 195, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 196, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 197, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 198, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 199, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 200, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 201, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 202, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 203, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 204, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 205, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 206, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 207, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 208, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 209, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 210, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 211, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 212, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 213, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 214, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 215, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 216, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 217, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 218, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 219, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 220, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 221, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 222, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 223, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 224, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 225, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 226, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 227, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 228, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 229, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 230, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 231, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 232, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 233, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 234, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 235, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 236, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 237, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 238, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 239, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 240, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 241, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 242, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 243, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 244, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 245, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 246, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 247, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 248, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 249, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 250, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 251, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 252, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 253, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 254, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 255, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 256, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 257, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 258, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 259, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 260, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 261, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 262, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 263, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 264, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 265, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 266, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 267, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 268, 1);
INSERT INTO core.observation_desc_plot VALUES (61, 269, 1);
INSERT INTO core.observation_desc_plot VALUES (48, 78, 1);
INSERT INTO core.observation_desc_plot VALUES (48, 79, 1);
INSERT INTO core.observation_desc_plot VALUES (48, 80, 1);
INSERT INTO core.observation_desc_plot VALUES (48, 81, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 173, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 174, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 175, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 176, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 177, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 178, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 179, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 180, 1);
INSERT INTO core.observation_desc_plot VALUES (57, 181, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 63, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 64, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 65, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 66, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 67, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 68, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 69, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 70, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 71, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 72, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 73, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 74, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 75, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 76, 1);
INSERT INTO core.observation_desc_plot VALUES (60, 77, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 88, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 89, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 90, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 91, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 92, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 93, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 94, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 95, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 96, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 97, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 98, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 99, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 100, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 101, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 102, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 103, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 104, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 105, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 106, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 107, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 108, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 109, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 110, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 111, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 112, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 113, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 114, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 115, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 116, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 117, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 118, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 119, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 120, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 121, 1);
INSERT INTO core.observation_desc_plot VALUES (54, 122, 1);
INSERT INTO core.observation_desc_plot VALUES (45, 58, 1);
INSERT INTO core.observation_desc_plot VALUES (45, 59, 1);
INSERT INTO core.observation_desc_plot VALUES (45, 60, 1);
INSERT INTO core.observation_desc_plot VALUES (45, 61, 1);
INSERT INTO core.observation_desc_plot VALUES (45, 62, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 82, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 83, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 84, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 85, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 86, 1);
INSERT INTO core.observation_desc_plot VALUES (49, 87, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 123, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 124, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 125, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 126, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 127, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 128, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 129, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 130, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 131, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 132, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 133, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 134, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 135, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 136, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 137, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 138, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 139, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 140, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 141, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 142, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 143, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 144, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 145, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 146, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 147, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 148, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 149, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 150, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 151, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 152, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 153, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 154, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 155, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 156, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 157, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 158, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 159, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 160, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 161, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 162, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 163, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 164, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 165, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 166, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 167, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 168, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 169, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 170, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 171, 1);
INSERT INTO core.observation_desc_plot VALUES (56, 172, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 182, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 183, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 184, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 185, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 186, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 187, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 188, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 189, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 190, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 191, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 192, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 193, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 194, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 195, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 196, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 197, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 198, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 199, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 200, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 201, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 202, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 203, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 204, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 205, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 206, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 207, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 208, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 209, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 210, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 211, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 212, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 213, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 214, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 215, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 216, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 217, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 218, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 219, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 220, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 221, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 222, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 223, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 224, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 225, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 226, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 227, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 228, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 229, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 230, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 231, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 232, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 233, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 234, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 235, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 236, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 237, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 238, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 239, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 240, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 241, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 242, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 243, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 244, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 245, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 246, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 247, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 248, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 249, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 250, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 251, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 252, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 253, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 254, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 255, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 256, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 257, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 258, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 259, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 260, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 261, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 262, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 263, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 264, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 265, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 266, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 267, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 268, 1);
INSERT INTO core.observation_desc_plot VALUES (52, 269, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 332, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 333, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 334, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 335, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 336, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 337, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 338, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 339, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 340, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 341, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 342, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 343, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 344, 1);
INSERT INTO core.observation_desc_plot VALUES (72, 345, 1);
INSERT INTO core.observation_desc_plot VALUES (77, 387, 1);
INSERT INTO core.observation_desc_plot VALUES (77, 388, 1);
INSERT INTO core.observation_desc_plot VALUES (77, 389, 1);
INSERT INTO core.observation_desc_plot VALUES (66, 308, 1);
INSERT INTO core.observation_desc_plot VALUES (66, 309, 1);
INSERT INTO core.observation_desc_plot VALUES (66, 310, 1);
INSERT INTO core.observation_desc_plot VALUES (66, 311, 1);
INSERT INTO core.observation_desc_plot VALUES (66, 312, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 313, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 314, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 315, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 316, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 317, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 318, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 319, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 320, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 321, 1);
INSERT INTO core.observation_desc_plot VALUES (67, 322, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 375, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 376, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 377, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 378, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 379, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 380, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 381, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 382, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 383, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 384, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 385, 1);
INSERT INTO core.observation_desc_plot VALUES (76, 386, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 296, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 297, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 298, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 299, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 300, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 301, 1);
INSERT INTO core.observation_desc_plot VALUES (64, 302, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 286, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 287, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 288, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 289, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 290, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 291, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 292, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 293, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 294, 1);
INSERT INTO core.observation_desc_plot VALUES (63, 295, 1);
INSERT INTO core.observation_desc_plot VALUES (65, 303, 1);
INSERT INTO core.observation_desc_plot VALUES (65, 304, 1);
INSERT INTO core.observation_desc_plot VALUES (65, 305, 1);
INSERT INTO core.observation_desc_plot VALUES (65, 306, 1);
INSERT INTO core.observation_desc_plot VALUES (65, 307, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 323, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 324, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 325, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 326, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 327, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 328, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 329, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 330, 1);
INSERT INTO core.observation_desc_plot VALUES (71, 331, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 270, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 271, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 272, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 273, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 274, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 275, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 276, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 277, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 278, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 279, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 280, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 281, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 282, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 283, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 284, 1);
INSERT INTO core.observation_desc_plot VALUES (59, 285, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 182, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 183, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 184, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 185, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 186, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 187, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 188, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 189, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 190, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 191, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 192, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 193, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 194, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 195, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 196, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 197, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 198, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 199, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 200, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 201, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 202, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 203, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 204, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 205, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 206, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 207, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 208, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 209, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 210, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 211, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 212, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 213, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 214, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 215, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 216, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 217, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 218, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 219, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 220, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 221, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 222, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 223, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 224, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 225, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 226, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 227, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 228, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 229, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 230, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 231, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 232, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 233, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 234, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 235, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 236, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 237, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 238, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 239, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 240, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 241, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 242, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 243, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 244, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 245, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 246, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 247, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 248, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 249, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 250, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 251, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 252, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 253, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 254, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 255, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 256, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 257, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 258, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 259, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 260, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 261, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 262, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 263, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 264, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 265, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 266, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 267, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 268, 1);
INSERT INTO core.observation_desc_plot VALUES (58, 269, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 375, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 376, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 377, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 378, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 379, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 380, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 381, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 382, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 383, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 384, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 385, 1);
INSERT INTO core.observation_desc_plot VALUES (75, 386, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 346, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 347, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 348, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 349, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 350, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 351, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 352, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 353, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 354, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 355, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 356, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 357, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 358, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 359, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 360, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 361, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 362, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 363, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 364, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 365, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 366, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 367, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 368, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 369, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 370, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 371, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 372, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 373, 1);
INSERT INTO core.observation_desc_plot VALUES (74, 374, 1);
INSERT INTO core.observation_desc_plot VALUES (83, 387, 1);
INSERT INTO core.observation_desc_plot VALUES (83, 388, 1);
INSERT INTO core.observation_desc_plot VALUES (83, 389, 1);


--
-- TOC entry 5314 (class 0 OID 23079565)
-- Dependencies: 252
-- Data for Name: observation_desc_profile; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.observation_desc_profile VALUES (5, 4, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 8, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 2, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 6, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 1, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 7, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 3, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 9, 1);
INSERT INTO core.observation_desc_profile VALUES (5, 5, 1);


--
-- TOC entry 5332 (class 0 OID 23079967)
-- Dependencies: 270
-- Data for Name: observation_desc_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5312 (class 0 OID 23079521)
-- Dependencies: 250
-- Data for Name: observation_desc_surface; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.observation_desc_surface VALUES (8, 63, 1);
INSERT INTO core.observation_desc_surface VALUES (8, 64, 1);
INSERT INTO core.observation_desc_surface VALUES (8, 65, 1);
INSERT INTO core.observation_desc_surface VALUES (8, 66, 1);
INSERT INTO core.observation_desc_surface VALUES (8, 67, 1);
INSERT INTO core.observation_desc_surface VALUES (9, 68, 1);
INSERT INTO core.observation_desc_surface VALUES (9, 69, 1);
INSERT INTO core.observation_desc_surface VALUES (9, 70, 1);
INSERT INTO core.observation_desc_surface VALUES (9, 71, 1);
INSERT INTO core.observation_desc_surface VALUES (6, 58, 1);
INSERT INTO core.observation_desc_surface VALUES (6, 59, 1);
INSERT INTO core.observation_desc_surface VALUES (6, 60, 1);
INSERT INTO core.observation_desc_surface VALUES (6, 61, 1);
INSERT INTO core.observation_desc_surface VALUES (6, 62, 1);
INSERT INTO core.observation_desc_surface VALUES (10, 72, 1);
INSERT INTO core.observation_desc_surface VALUES (10, 73, 1);
INSERT INTO core.observation_desc_surface VALUES (10, 74, 1);
INSERT INTO core.observation_desc_surface VALUES (10, 75, 1);
INSERT INTO core.observation_desc_surface VALUES (10, 76, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 22, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 23, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 24, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 25, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 26, 1);
INSERT INTO core.observation_desc_surface VALUES (18, 27, 1);
INSERT INTO core.observation_desc_surface VALUES (14, 1, 1);
INSERT INTO core.observation_desc_surface VALUES (14, 2, 1);
INSERT INTO core.observation_desc_surface VALUES (14, 3, 1);
INSERT INTO core.observation_desc_surface VALUES (14, 4, 1);
INSERT INTO core.observation_desc_surface VALUES (15, 5, 1);
INSERT INTO core.observation_desc_surface VALUES (15, 6, 1);
INSERT INTO core.observation_desc_surface VALUES (15, 7, 1);
INSERT INTO core.observation_desc_surface VALUES (15, 8, 1);
INSERT INTO core.observation_desc_surface VALUES (15, 9, 1);
INSERT INTO core.observation_desc_surface VALUES (16, 10, 1);
INSERT INTO core.observation_desc_surface VALUES (16, 11, 1);
INSERT INTO core.observation_desc_surface VALUES (16, 12, 1);
INSERT INTO core.observation_desc_surface VALUES (16, 13, 1);
INSERT INTO core.observation_desc_surface VALUES (16, 14, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 28, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 29, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 30, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 31, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 32, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 33, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 34, 1);
INSERT INTO core.observation_desc_surface VALUES (20, 35, 1);
INSERT INTO core.observation_desc_surface VALUES (21, 36, 1);
INSERT INTO core.observation_desc_surface VALUES (21, 37, 1);
INSERT INTO core.observation_desc_surface VALUES (21, 38, 1);
INSERT INTO core.observation_desc_surface VALUES (21, 39, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 40, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 41, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 42, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 43, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 44, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 45, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 46, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 47, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 48, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 49, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 50, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 51, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 52, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 53, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 54, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 55, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 56, 1);
INSERT INTO core.observation_desc_surface VALUES (22, 57, 1);
INSERT INTO core.observation_desc_surface VALUES (24, 77, 1);
INSERT INTO core.observation_desc_surface VALUES (24, 78, 1);
INSERT INTO core.observation_desc_surface VALUES (24, 79, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 15, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 16, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 17, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 18, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 19, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 20, 1);
INSERT INTO core.observation_desc_surface VALUES (17, 21, 1);


--
-- TOC entry 5318 (class 0 OID 23079621)
-- Dependencies: 256
-- Data for Name: observation_phys_chem_element; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.observation_phys_chem_element VALUES (1, 1, 73, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (2, 1, 74, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (3, 1, 75, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (4, 1, 76, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (5, 1, 77, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (6, 1, 78, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (7, 1, 79, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (8, 3, 80, 17, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (9, 3, 81, 17, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (10, 3, 82, 17, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (11, 4, 83, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (12, 4, 84, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (13, 40, 85, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (14, 40, 86, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (15, 40, 87, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (16, 40, 88, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (17, 40, 89, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (18, 40, 90, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (19, 40, 91, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (20, 40, 92, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (21, 40, 93, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (22, 40, 94, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (23, 41, 95, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (24, 41, 96, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (25, 41, 97, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (26, 41, 98, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (27, 41, 99, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (28, 41, 100, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (29, 41, 101, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (30, 41, 102, 13, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (31, 43, 103, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (32, 43, 104, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (33, 10, 105, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (34, 10, 106, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (35, 10, 107, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (36, 10, 108, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (37, 10, 109, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (38, 10, 110, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (39, 10, 111, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (40, 10, 112, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (41, 10, 113, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (42, 10, 114, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (43, 10, 115, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (44, 10, 116, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (45, 10, 117, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (46, 10, 118, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (47, 10, 119, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (48, 10, 120, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (49, 10, 121, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (50, 10, 122, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (51, 10, 123, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (52, 10, 124, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (53, 10, 125, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (54, 10, 126, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (55, 10, 127, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (56, 10, 128, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (57, 11, 129, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (58, 11, 130, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (59, 11, 131, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (60, 11, 132, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (61, 11, 133, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (62, 45, 153, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (63, 45, 154, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (64, 45, 155, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (65, 46, 156, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (66, 46, 157, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (67, 47, 158, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (68, 47, 159, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (69, 47, 160, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (70, 47, 161, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (71, 47, 162, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (72, 47, 163, 11, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (73, 50, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (74, 50, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (75, 50, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (76, 50, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (77, 50, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (78, 50, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (79, 50, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (80, 50, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (81, 50, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (82, 50, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (83, 50, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (84, 29, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (85, 29, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (86, 29, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (87, 29, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (88, 29, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (89, 29, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (90, 29, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (91, 29, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (92, 29, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (93, 29, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (94, 29, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (95, 14, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (96, 14, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (97, 14, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (98, 14, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (99, 14, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (100, 14, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (101, 14, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (102, 14, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (103, 14, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (104, 14, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (105, 14, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (106, 26, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (107, 26, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (108, 26, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (109, 26, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (110, 26, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (111, 26, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (112, 26, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (113, 26, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (114, 26, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (115, 26, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (116, 26, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (117, 2, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (118, 2, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (119, 2, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (120, 2, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (121, 2, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (122, 2, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (123, 2, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (124, 2, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (125, 2, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (126, 2, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (127, 2, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (128, 7, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (129, 7, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (130, 7, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (131, 7, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (132, 7, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (133, 7, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (134, 7, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (135, 7, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (136, 7, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (137, 7, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (138, 7, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (139, 17, 164, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (140, 17, 165, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (141, 17, 166, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (142, 17, 167, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (143, 17, 168, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (144, 17, 169, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (145, 17, 170, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (146, 17, 171, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (147, 17, 172, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (148, 17, 173, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (149, 17, 174, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (150, 20, 175, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (151, 20, 176, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (152, 20, 177, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (153, 20, 178, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (154, 20, 179, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (155, 20, 180, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (156, 20, 181, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (157, 20, 182, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (158, 20, 183, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (159, 20, 184, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (160, 20, 185, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (161, 20, 186, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (162, 20, 187, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (163, 20, 188, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (164, 20, 189, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (165, 20, 190, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (166, 20, 191, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (167, 20, 192, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (168, 20, 193, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (169, 20, 194, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (170, 20, 195, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (171, 20, 196, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (172, 20, 197, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (173, 20, 198, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (174, 20, 199, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (175, 5, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (176, 5, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (177, 5, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (178, 5, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (179, 5, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (180, 5, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (181, 5, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (182, 5, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (183, 5, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (184, 5, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (185, 5, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (186, 5, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (187, 5, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (188, 5, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (189, 5, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (190, 5, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (191, 5, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (192, 5, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (193, 5, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (194, 5, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (195, 5, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (196, 5, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (197, 5, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (198, 5, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (199, 5, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (200, 51, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (201, 51, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (202, 51, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (203, 51, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (204, 51, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (205, 51, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (206, 51, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (207, 51, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (208, 51, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (209, 51, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (210, 51, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (211, 51, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (212, 51, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (213, 51, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (214, 51, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (215, 51, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (216, 51, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (217, 51, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (218, 51, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (219, 51, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (220, 51, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (221, 51, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (222, 51, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (223, 51, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (224, 51, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (225, 27, 175, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (226, 27, 176, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (227, 27, 177, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (228, 27, 178, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (229, 27, 179, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (230, 27, 180, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (231, 27, 181, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (232, 27, 182, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (233, 27, 183, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (234, 27, 184, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (235, 27, 185, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (236, 27, 186, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (237, 27, 187, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (238, 27, 188, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (239, 27, 189, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (240, 27, 190, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (241, 27, 191, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (242, 27, 192, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (243, 27, 193, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (244, 27, 194, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (245, 27, 195, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (246, 27, 196, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (247, 27, 197, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (248, 27, 198, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (249, 27, 199, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (250, 18, 175, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (251, 18, 176, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (252, 18, 177, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (253, 18, 178, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (254, 18, 179, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (255, 18, 180, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (256, 18, 181, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (257, 18, 182, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (258, 18, 183, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (259, 18, 184, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (260, 18, 185, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (261, 18, 186, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (262, 18, 187, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (263, 18, 188, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (264, 18, 189, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (265, 18, 190, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (266, 18, 191, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (267, 18, 192, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (268, 18, 193, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (269, 18, 194, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (270, 18, 195, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (271, 18, 196, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (272, 18, 197, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (273, 18, 198, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (274, 18, 199, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (275, 32, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (276, 32, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (277, 32, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (278, 32, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (279, 32, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (280, 32, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (281, 32, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (282, 32, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (283, 32, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (284, 32, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (285, 32, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (286, 32, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (287, 32, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (288, 32, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (289, 32, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (290, 32, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (291, 32, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (292, 32, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (293, 32, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (294, 32, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (295, 32, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (296, 32, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (297, 32, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (298, 32, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (299, 32, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (300, 12, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (301, 12, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (302, 12, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (303, 12, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (304, 12, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (305, 12, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (306, 12, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (307, 12, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (308, 12, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (309, 12, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (310, 12, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (311, 12, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (312, 12, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (313, 12, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (314, 12, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (315, 12, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (316, 12, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (317, 12, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (318, 12, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (319, 12, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (320, 12, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (321, 12, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (322, 12, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (323, 12, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (324, 12, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (325, 8, 175, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (326, 8, 176, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (327, 8, 177, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (328, 8, 178, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (329, 8, 179, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (330, 8, 180, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (331, 8, 181, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (332, 8, 182, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (333, 8, 183, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (334, 8, 184, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (335, 8, 185, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (336, 8, 186, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (337, 8, 187, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (338, 8, 188, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (339, 8, 189, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (340, 8, 190, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (341, 8, 191, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (342, 8, 192, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (343, 8, 193, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (344, 8, 194, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (345, 8, 195, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (346, 8, 196, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (347, 8, 197, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (348, 8, 198, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (349, 8, 199, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (350, 15, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (351, 15, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (352, 15, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (353, 15, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (354, 15, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (355, 15, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (356, 15, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (357, 15, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (358, 15, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (359, 15, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (360, 15, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (361, 15, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (362, 15, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (363, 15, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (364, 15, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (365, 15, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (366, 15, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (367, 15, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (368, 15, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (369, 15, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (370, 15, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (371, 15, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (372, 15, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (373, 15, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (374, 15, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (375, 30, 175, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (376, 30, 176, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (377, 30, 177, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (378, 30, 178, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (379, 30, 179, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (380, 30, 180, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (381, 30, 181, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (382, 30, 182, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (383, 30, 183, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (384, 30, 184, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (385, 30, 185, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (386, 30, 186, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (387, 30, 187, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (388, 30, 188, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (389, 30, 189, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (390, 30, 190, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (391, 30, 191, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (392, 30, 192, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (393, 30, 193, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (394, 30, 194, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (395, 30, 195, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (396, 30, 196, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (397, 30, 197, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (398, 30, 198, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (399, 30, 199, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (400, 37, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (401, 37, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (402, 37, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (403, 37, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (404, 37, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (405, 37, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (406, 37, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (407, 37, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (408, 37, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (409, 37, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (410, 37, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (411, 37, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (412, 37, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (413, 37, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (414, 37, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (415, 37, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (416, 37, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (417, 37, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (418, 37, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (419, 37, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (420, 37, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (421, 37, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (422, 37, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (423, 37, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (424, 37, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (425, 42, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (426, 42, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (427, 42, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (428, 42, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (429, 42, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (430, 42, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (431, 42, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (432, 42, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (433, 42, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (434, 42, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (435, 42, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (436, 42, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (437, 42, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (438, 42, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (439, 42, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (440, 42, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (441, 42, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (442, 42, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (443, 42, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (444, 42, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (445, 42, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (446, 42, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (447, 42, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (448, 42, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (449, 42, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (450, 23, 175, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (451, 23, 176, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (452, 23, 177, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (453, 23, 178, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (454, 23, 179, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (455, 23, 180, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (456, 23, 181, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (457, 23, 182, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (458, 23, 183, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (459, 23, 184, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (460, 23, 185, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (461, 23, 186, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (462, 23, 187, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (463, 23, 188, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (464, 23, 189, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (465, 23, 190, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (466, 23, 191, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (467, 23, 192, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (468, 23, 193, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (469, 23, 194, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (470, 23, 195, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (471, 23, 196, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (472, 23, 197, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (473, 23, 198, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (474, 23, 199, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (475, 48, 200, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (476, 48, 201, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (477, 48, 202, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (478, 48, 203, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (479, 48, 204, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (480, 48, 205, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (481, 48, 206, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (482, 49, 207, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (483, 49, 208, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (484, 49, 209, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (485, 49, 210, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (486, 49, 211, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (487, 49, 212, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (488, 49, 213, 8, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (489, 22, 223, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (490, 22, 224, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (491, 22, 225, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (492, 22, 226, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (493, 22, 1, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (494, 22, 2, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (495, 22, 3, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (496, 22, 227, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (497, 22, 228, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (498, 22, 229, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (499, 22, 230, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (500, 22, 231, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (501, 22, 232, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (502, 22, 233, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (503, 52, 234, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (504, 52, 235, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (505, 52, 236, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (506, 52, 237, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (507, 38, 238, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (508, 38, 4, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (509, 38, 5, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (510, 38, 6, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (511, 38, 7, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (512, 38, 8, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (513, 38, 9, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (514, 38, 239, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (515, 38, 10, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (516, 38, 11, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (517, 38, 12, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (518, 38, 13, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (519, 38, 14, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (520, 38, 15, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (521, 38, 16, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (522, 38, 240, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (523, 38, 17, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (524, 38, 18, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (525, 38, 19, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (526, 38, 20, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (527, 38, 21, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (528, 38, 241, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (529, 38, 242, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (530, 38, 22, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (531, 38, 23, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (532, 38, 24, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (533, 38, 25, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (534, 38, 26, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (535, 38, 27, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (536, 53, 238, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (537, 53, 4, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (538, 53, 5, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (539, 53, 6, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (540, 53, 7, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (541, 53, 8, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (542, 53, 9, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (543, 53, 239, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (544, 53, 10, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (545, 53, 11, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (546, 53, 12, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (547, 53, 13, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (548, 53, 14, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (549, 53, 15, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (550, 53, 16, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (551, 53, 240, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (552, 53, 17, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (553, 53, 18, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (554, 53, 19, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (555, 53, 20, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (556, 53, 21, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (557, 53, 241, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (558, 53, 242, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (559, 53, 22, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (560, 53, 23, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (561, 53, 24, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (562, 53, 25, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (563, 53, 26, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (564, 53, 27, 14, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (565, 24, 243, 16, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (566, 24, 244, 16, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (567, 54, 245, 17, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (568, 55, 246, 15, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (569, 55, 247, 15, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (570, 35, 248, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (571, 35, 28, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (572, 35, 29, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (573, 35, 30, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (574, 35, 31, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (575, 35, 32, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (576, 35, 33, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (577, 35, 34, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (578, 35, 35, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (579, 35, 36, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (580, 35, 37, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (581, 35, 38, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (582, 35, 39, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (583, 35, 40, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (584, 35, 41, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (585, 35, 42, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (586, 35, 249, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (587, 35, 43, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (588, 35, 44, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (589, 35, 45, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (590, 35, 46, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (591, 35, 47, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (592, 35, 48, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (593, 35, 49, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (594, 35, 50, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (595, 35, 51, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (596, 35, 52, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (597, 35, 53, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (598, 35, 54, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (599, 35, 55, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (600, 35, 56, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (601, 35, 57, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (602, 35, 250, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (603, 35, 58, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (604, 35, 59, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (605, 35, 60, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (606, 35, 61, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (607, 35, 62, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (608, 35, 63, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (609, 35, 64, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (610, 35, 65, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (611, 35, 66, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (612, 35, 67, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (613, 35, 68, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (614, 35, 69, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (615, 35, 70, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (616, 35, 71, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (617, 35, 72, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (618, 34, 248, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (619, 34, 28, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (620, 34, 29, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (621, 34, 30, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (622, 34, 31, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (623, 34, 32, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (624, 34, 33, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (625, 34, 34, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (626, 34, 35, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (627, 34, 36, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (628, 34, 37, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (629, 34, 38, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (630, 34, 39, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (631, 34, 40, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (632, 34, 41, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (633, 34, 42, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (634, 34, 249, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (635, 34, 43, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (636, 34, 44, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (637, 34, 45, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (638, 34, 46, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (639, 34, 47, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (640, 34, 48, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (641, 34, 49, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (642, 34, 50, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (643, 34, 51, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (644, 34, 52, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (645, 34, 53, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (646, 34, 54, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (647, 34, 55, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (648, 34, 56, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (649, 34, 57, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (650, 34, 250, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (651, 34, 58, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (652, 34, 59, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (653, 34, 60, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (654, 34, 61, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (655, 34, 62, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (656, 34, 63, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (657, 34, 64, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (658, 34, 65, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (659, 34, 66, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (660, 34, 67, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (661, 34, 68, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (662, 34, 69, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (663, 34, 70, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (664, 34, 71, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (665, 34, 72, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (666, 36, 248, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (667, 36, 28, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (668, 36, 29, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (669, 36, 30, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (670, 36, 31, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (671, 36, 32, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (672, 36, 33, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (673, 36, 34, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (674, 36, 35, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (675, 36, 36, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (676, 36, 37, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (677, 36, 38, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (678, 36, 39, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (679, 36, 40, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (680, 36, 41, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (681, 36, 42, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (682, 36, 249, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (683, 36, 43, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (684, 36, 44, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (685, 36, 45, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (686, 36, 46, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (687, 36, 47, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (688, 36, 48, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (689, 36, 49, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (690, 36, 50, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (691, 36, 51, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (692, 36, 52, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (693, 36, 53, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (694, 36, 54, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (695, 36, 55, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (696, 36, 56, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (697, 36, 57, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (698, 36, 250, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (699, 36, 58, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (700, 36, 59, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (701, 36, 60, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (702, 36, 61, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (703, 36, 62, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (704, 36, 63, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (705, 36, 64, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (706, 36, 65, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (707, 36, 66, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (708, 36, 67, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (709, 36, 68, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (710, 36, 69, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (711, 36, 70, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (712, 36, 71, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (713, 36, 72, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (714, 56, 252, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (715, 56, 253, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (716, 56, 254, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (717, 56, 255, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (718, 56, 256, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (719, 56, 257, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (720, 56, 258, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (721, 56, 259, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (722, 56, 260, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (723, 56, 261, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (724, 56, 262, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (725, 56, 263, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (726, 56, 264, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (727, 56, 265, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (728, 56, 266, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (729, 56, 267, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (730, 56, 268, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (731, 56, 269, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (732, 56, 270, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (733, 56, 271, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (734, 56, 272, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (735, 56, 273, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (736, 56, 274, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (737, 56, 275, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (738, 56, 276, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (739, 56, 277, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (740, 56, 278, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (741, 56, 279, 12, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (742, 28, 280, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (743, 28, 281, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (744, 28, 282, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (745, 28, 283, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (746, 28, 284, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (747, 28, 285, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (748, 28, 286, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (749, 28, 287, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (750, 28, 288, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (751, 28, 289, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (752, 28, 290, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (753, 28, 291, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (754, 28, 292, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (755, 28, 293, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (756, 28, 294, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (757, 28, 295, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (758, 28, 296, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (759, 28, 297, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (760, 28, 298, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (761, 19, 280, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (762, 19, 281, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (763, 19, 282, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (764, 19, 283, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (765, 19, 284, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (766, 19, 285, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (767, 19, 286, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (768, 19, 287, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (769, 19, 288, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (770, 19, 289, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (771, 19, 290, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (772, 19, 291, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (773, 19, 292, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (774, 19, 293, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (775, 19, 294, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (776, 19, 295, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (777, 19, 296, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (778, 19, 297, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (779, 19, 298, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (780, 51, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (781, 51, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (782, 51, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (783, 51, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (784, 51, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (785, 51, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (786, 51, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (787, 51, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (788, 51, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (789, 51, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (790, 51, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (791, 51, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (792, 51, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (793, 51, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (794, 51, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (795, 51, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (796, 51, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (797, 51, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (798, 51, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (799, 6, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (800, 6, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (801, 6, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (802, 6, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (803, 6, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (804, 6, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (805, 6, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (806, 6, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (807, 6, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (808, 6, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (809, 6, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (810, 6, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (811, 6, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (812, 6, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (813, 6, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (814, 6, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (815, 6, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (816, 6, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (817, 6, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (818, 33, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (819, 33, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (820, 33, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (821, 33, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (822, 33, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (823, 33, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (824, 33, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (825, 33, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (826, 33, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (827, 33, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (828, 33, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (829, 33, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (830, 33, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (831, 33, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (832, 33, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (833, 33, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (834, 33, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (835, 33, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (836, 33, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (837, 13, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (838, 13, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (839, 13, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (840, 13, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (841, 13, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (842, 13, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (843, 13, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (844, 13, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (845, 13, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (846, 13, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (847, 13, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (848, 13, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (849, 13, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (850, 13, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (851, 13, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (852, 13, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (853, 13, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (854, 13, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (855, 13, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (856, 57, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (857, 57, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (858, 57, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (859, 57, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (860, 57, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (861, 57, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (862, 57, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (863, 57, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (864, 57, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (865, 57, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (866, 57, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (867, 57, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (868, 57, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (869, 57, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (870, 57, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (871, 57, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (872, 57, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (873, 57, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (874, 57, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (875, 42, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (876, 42, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (877, 42, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (878, 42, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (879, 42, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (880, 42, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (881, 42, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (882, 42, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (883, 42, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (884, 42, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (885, 42, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (886, 42, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (887, 42, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (888, 42, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (889, 42, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (890, 42, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (891, 42, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (892, 42, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (893, 42, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (894, 25, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (895, 25, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (896, 25, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (897, 25, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (898, 25, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (899, 25, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (900, 25, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (901, 25, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (902, 25, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (903, 25, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (904, 25, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (905, 25, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (906, 25, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (907, 25, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (908, 25, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (909, 25, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (910, 25, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (911, 25, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (912, 25, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (913, 39, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (914, 39, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (915, 39, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (916, 39, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (917, 39, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (918, 39, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (919, 39, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (920, 39, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (921, 39, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (922, 39, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (923, 39, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (924, 39, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (925, 39, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (926, 39, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (927, 39, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (928, 39, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (929, 39, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (930, 39, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (931, 39, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (932, 16, 280, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (933, 16, 281, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (934, 16, 282, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (935, 16, 283, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (936, 16, 284, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (937, 16, 285, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (938, 16, 286, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (939, 16, 287, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (940, 16, 288, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (941, 16, 289, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (942, 16, 290, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (943, 16, 291, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (944, 16, 292, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (945, 16, 293, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (946, 16, 294, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (947, 16, 295, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (948, 16, 296, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (949, 16, 297, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (950, 16, 298, 9, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (951, 9, 280, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (952, 9, 281, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (953, 9, 282, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (954, 9, 283, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (955, 9, 284, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (956, 9, 285, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (957, 9, 286, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (958, 9, 287, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (959, 9, 288, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (960, 9, 289, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (961, 9, 290, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (962, 9, 291, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (963, 9, 292, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (964, 9, 293, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (965, 9, 294, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (966, 9, 295, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (967, 9, 296, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (968, 9, 297, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (969, 9, 298, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (970, 31, 280, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (971, 31, 281, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (972, 31, 282, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (973, 31, 283, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (974, 31, 284, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (975, 31, 285, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (976, 31, 286, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (977, 31, 287, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (978, 31, 288, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (979, 31, 289, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (980, 31, 290, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (981, 31, 291, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (982, 31, 292, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (983, 31, 293, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (984, 31, 294, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (985, 31, 295, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (986, 31, 296, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (987, 31, 297, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (988, 31, 298, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (989, 21, 280, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (990, 21, 281, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (991, 21, 282, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (992, 21, 283, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (993, 21, 284, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (994, 21, 285, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (995, 21, 286, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (996, 21, 287, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (997, 21, 288, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (998, 21, 289, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (999, 21, 290, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1000, 21, 291, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1001, 21, 292, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1002, 21, 293, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1003, 21, 294, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1004, 21, 295, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1005, 21, 296, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1006, 21, 297, 10, NULL, NULL);
INSERT INTO core.observation_phys_chem_element VALUES (1007, 21, 298, 10, NULL, NULL);


--
-- TOC entry 5334 (class 0 OID 23080035)
-- Dependencies: 272
-- Data for Name: observation_phys_chem_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5298 (class 0 OID 23079310)
-- Dependencies: 236
-- Data for Name: plot; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5343 (class 0 OID 23080229)
-- Dependencies: 281
-- Data for Name: plot_individual; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5325 (class 0 OID 23079832)
-- Dependencies: 263
-- Data for Name: procedure_desc; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.procedure_desc VALUES ('FAO GfSD 2006', 'Food and Agriculture Organisation of the United Nations, Guidelines for Soil Description, Fourth Edition, 2006.', 'https://www.fao.org/publications/card/en/c/903943c7-f56a-521a-8d32-459e7e0cdae9/', 1);


--
-- TOC entry 5303 (class 0 OID 23079408)
-- Dependencies: 241
-- Data for Name: procedure_phys_chem; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_dc-ht-dumas', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_dc-ht-dumas', 1);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O', 239);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca10', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca10', 276);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca11', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca11', 277);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca12', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca12', 278);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_calcul-tc-oc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_calcul-tc-oc', 279);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_h2so4', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_h2so4', 280);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_hcl', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_hcl', 281);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_hcl-aquaregia', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_hcl-aquaregia', 282);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_hclo4', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_hclo4', 283);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_hno3-aquafortis', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_hno3-aquafortis', 284);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_nh4-6mo7o24', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_nh4-6mo7o24', 285);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp03', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp03', 286);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp04', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp04', 287);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp05', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp05', 288);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp06', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp06', 289);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp07', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp07', 290);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp08', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp08', 291);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp09', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp09', 292);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_tp10', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_tp10', 293);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_unkn', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_unkn', 294);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_xrd', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_xrd', 295);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_xrf', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_xrf', 296);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_xrf-p', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_xrf-p', 297);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Total_xtf-t', 'http://w3id.org/glosis/model/procedure/totalElementsProcedure-Total_xtf-t', 298);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_dc-ht-leco', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_dc-ht-leco', 2);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_dc-spec', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_dc-spec', 3);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_ratio1-1', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_ratio1-1', 4);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_ratio1-10', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_ratio1-10', 5);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_ratio1-2', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_ratio1-2', 6);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_ratio1-2.5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_ratio1-2.5', 7);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_ratio1-5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_ratio1-5', 8);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2_sat', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2_sat', 9);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_ratio1-1', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_ratio1-1', 10);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_ratio1-10', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_ratio1-10', 11);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_ratio1-2', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_ratio1-2', 12);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_ratio1-2.5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_ratio1-2.5', 13);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_ratio1-5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_ratio1-5', 14);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_sat', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_sat', 15);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHH2O_unkn-spec', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHH2O_unkn-spec', 16);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_ratio1-1', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_ratio1-1', 17);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_ratio1-10', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_ratio1-10', 18);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_ratio1-2', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_ratio1-2', 19);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_ratio1-2.5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_ratio1-2.5', 20);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_ratio1-5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_ratio1-5', 21);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_ratio1-1', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_ratio1-1', 22);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_ratio1-10', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_ratio1-10', 23);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_ratio1-2', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_ratio1-2', 24);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_ratio1-2.5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_ratio1-2.5', 25);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_ratio1-5', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_ratio1-5', 26);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF_sat', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF_sat', 27);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-20-2000u-adj100', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-adj100', 28);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-20-2000u-disp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp', 29);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-beaker', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-beaker', 30);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-hydrometer', 31);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-hydrometer-bouy', 32);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-laser', 33);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-pipette', 34);
INSERT INTO core.procedure_phys_chem VALUES (29, 'SaSiCl_2-20-2000u-disp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-disp-spec', 35);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-20-2000u-fld', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-fld', 36);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-20-2000u-nodisp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp', 37);
INSERT INTO core.procedure_phys_chem VALUES (37, 'SaSiCl_2-20-2000u-nodisp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp-hydrometer', 38);
INSERT INTO core.procedure_phys_chem VALUES (37, 'SaSiCl_2-20-2000u-nodisp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp-hydrometer-bouy', 39);
INSERT INTO core.procedure_phys_chem VALUES (37, 'SaSiCl_2-20-2000u-nodisp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp-laser', 40);
INSERT INTO core.procedure_phys_chem VALUES (37, 'SaSiCl_2-20-2000u-nodisp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp-pipette', 41);
INSERT INTO core.procedure_phys_chem VALUES (37, 'SaSiCl_2-20-2000u-nodisp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u-nodisp-spec', 42);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-50-2000u-adj100', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-adj100', 43);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-50-2000u-disp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp', 44);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-beaker', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-beaker', 45);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-hydrometer', 46);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-hydrometer-bouy', 47);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-laser', 48);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-pipette', 49);
INSERT INTO core.procedure_phys_chem VALUES (44, 'SaSiCl_2-50-2000u-disp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-disp-spec', 50);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-50-2000u-fld', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-fld', 51);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-50-2000u-nodisp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp', 52);
INSERT INTO core.procedure_phys_chem VALUES (52, 'SaSiCl_2-50-2000u-nodisp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp-hydrometer', 53);
INSERT INTO core.procedure_phys_chem VALUES (52, 'SaSiCl_2-50-2000u-nodisp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp-hydrometer-bouy', 54);
INSERT INTO core.procedure_phys_chem VALUES (52, 'SaSiCl_2-50-2000u-nodisp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp-laser', 55);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_ud', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_ud', 220);
INSERT INTO core.procedure_phys_chem VALUES (52, 'SaSiCl_2-50-2000u-nodisp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp-pipette', 56);
INSERT INTO core.procedure_phys_chem VALUES (52, 'SaSiCl_2-50-2000u-nodisp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u-nodisp-spec', 57);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-64-2000u-adj100', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-adj100', 58);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-64-2000u-disp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp', 59);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-beaker', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-beaker', 60);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-hydrometer', 61);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-hydrometer-bouy', 62);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-laser', 63);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-pipette', 64);
INSERT INTO core.procedure_phys_chem VALUES (59, 'SaSiCl_2-64-2000u-disp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-disp-spec', 65);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-64-2000u-fld', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-fld', 66);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-64-2000u-nodisp', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp', 67);
INSERT INTO core.procedure_phys_chem VALUES (67, 'SaSiCl_2-64-2000u-nodisp-hydrometer', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp-hydrometer', 68);
INSERT INTO core.procedure_phys_chem VALUES (67, 'SaSiCl_2-64-2000u-nodisp-hydrometer-bouy', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp-hydrometer-bouy', 69);
INSERT INTO core.procedure_phys_chem VALUES (67, 'SaSiCl_2-64-2000u-nodisp-laser', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp-laser', 70);
INSERT INTO core.procedure_phys_chem VALUES (67, 'SaSiCl_2-64-2000u-nodisp-pipette', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp-pipette', 71);
INSERT INTO core.procedure_phys_chem VALUES (67, 'SaSiCl_2-64-2000u-nodisp-spec', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u-nodisp-spec', 72);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph0-kcl1m', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph0-kcl1m', 73);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph0-nh4cl', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph0-nh4cl', 74);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph0-unkn', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph0-unkn', 75);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph7-caoac', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph7-caoac', 76);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph7-unkn', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph7-unkn', 77);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph8-bacl2tea', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph8-bacl2tea', 78);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchAcid_ph8-unkn', 'http://w3id.org/glosis/model/procedure/acidityExchangeableProcedure-ExchAcid_ph8-unkn', 79);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'PAWHC_calcul-fc100wp', 'http://w3id.org/glosis/model/procedure/availableWaterHoldingCapacityProcedure-PAWHC_calcul-fc100wp', 80);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'PAWHC_calcul-fc200wp', 'http://w3id.org/glosis/model/procedure/availableWaterHoldingCapacityProcedure-PAWHC_calcul-fc200wp', 81);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'PAWHC_calcul-fc300wp', 'http://w3id.org/glosis/model/procedure/availableWaterHoldingCapacityProcedure-PAWHC_calcul-fc300wp', 82);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BSat_calcul-cec', 'http://w3id.org/glosis/model/procedure/baseSaturationProcedure-BSat_calcul-cec', 83);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BSat_calcul-ecec', 'http://w3id.org/glosis/model/procedure/baseSaturationProcedure-BSat_calcul-ecec', 84);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-cl-fc', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-cl-fc', 85);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-cl-od', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-cl-od', 86);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-cl-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-cl-unkn', 87);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-co-fc', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-co-fc', 88);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-co-od', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-co-od', 89);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-co-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-co-unkn', 90);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-rpl-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-rpl-unkn', 91);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-unkn', 92);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-unkn-fc', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-unkn-fc', 93);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensF_fe-unkn-od', 'http://w3id.org/glosis/model/procedure/bulkDensityFineEarthProcedure-BlkDensF_fe-unkn-od', 94);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-cl-fc', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-cl-fc', 95);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-cl-od', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-cl-od', 96);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-cl-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-cl-unkn', 97);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-co-fc', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-co-fc', 98);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-co-od', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-co-od', 99);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-co-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-co-unkn', 100);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-rpl-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-rpl-unkn', 101);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'BlkDensW_we-unkn', 'http://w3id.org/glosis/model/procedure/bulkDensityWholeSoilProcedure-BlkDensW_we-unkn', 102);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'InOrgC_calcul-caco3', 'http://w3id.org/glosis/model/procedure/carbonInorganicProcedure-InOrgC_calcul-caco3', 103);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'InOrgC_calcul-tc-oc', 'http://w3id.org/glosis/model/procedure/carbonInorganicProcedure-InOrgC_calcul-tc-oc', 104);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc', 105);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-ht', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-ht', 106);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-ht-analyser', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-ht-analyser', 107);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-lt', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-lt', 108);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-lt-loi', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-lt-loi', 109);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-mt', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-mt', 110);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_acid-dc-spec', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_acid-dc-spec', 111);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_calcul-tc-ic', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_calcul-tc-ic', 112);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc', 113);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-ht', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-ht', 114);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-ht-analyser', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-ht-analyser', 115);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-lt', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-lt', 116);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-lt-loi', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-lt-loi', 117);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-mt', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-mt', 118);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_dc-spec', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_dc-spec', 119);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc', 120);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-jackson', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-jackson', 121);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-kalembra', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-kalembra', 122);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-knopp', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-knopp', 123);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-kurmies', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-kurmies', 124);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-nelson', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-nelson', 125);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-nrcs6a1c', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-nrcs6a1c', 126);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-tiurin', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-tiurin', 127);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgC_wc-cro3-walkleyblack', 'http://w3id.org/glosis/model/procedure/carbonOrganicProcedure-OrgC_wc-cro3-walkleyblack', 128);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotC_calcul-ic-oc', 'http://w3id.org/glosis/model/procedure/carbonTotalProcedure-TotC_calcul-ic-oc', 129);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotC_dc-ht', 'http://w3id.org/glosis/model/procedure/carbonTotalProcedure-TotC_dc-ht', 130);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotC_dc-ht-analyser', 'http://w3id.org/glosis/model/procedure/carbonTotalProcedure-TotC_dc-ht-analyser', 131);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotC_dc-ht-spec', 'http://w3id.org/glosis/model/procedure/carbonTotalProcedure-TotC_dc-ht-spec', 132);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotC_dc-mt', 'http://w3id.org/glosis/model/procedure/carbonTotalProcedure-TotC_dc-mt', 133);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph-unkn-cacl2', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph-unkn-cacl2', 134);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph-unkn-lioac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph-unkn-lioac', 135);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph-unkn-m3', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph-unkn-m3', 136);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-ag-thioura', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-ag-thioura', 137);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-bacl2', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-bacl2', 138);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-cohex', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-cohex', 139);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-kcl', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-kcl', 140);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-nh4cl', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-nh4cl', 141);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-nh4oac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-nh4oac', 142);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph0-unkn', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph0-unkn', 143);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph7-edta', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph7-edta', 144);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph7-nh4oac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph7-nh4oac', 145);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph7-unkn', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph7-unkn', 146);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-bacl2tea', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-bacl2tea', 147);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-baoac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-baoac', 148);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-licl2tea', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-licl2tea', 149);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-naoac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-naoac', 150);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-nh4oac', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-nh4oac', 151);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CEC_ph8-unkn', 'http://w3id.org/glosis/model/procedure/cationExchangeCapacitySoilProcedure-CEC_ph8-unkn', 152);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CrsFrg_fld', 'http://w3id.org/glosis/model/procedure/coarseFragmentsProcedure-CrsFrg_fld', 153);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CrsFrg_fldcls', 'http://w3id.org/glosis/model/procedure/coarseFragmentsProcedure-CrsFrg_fldcls', 154);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CrsFrg_lab', 'http://w3id.org/glosis/model/procedure/coarseFragmentsProcedure-CrsFrg_lab', 155);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EffCEC_calcul-b', 'http://w3id.org/glosis/model/procedure/effectiveCecProcedure-EffCEC_calcul-b', 156);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EffCEC_calcul-ba', 'http://w3id.org/glosis/model/procedure/effectiveCecProcedure-EffCEC_calcul-ba', 157);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EC_ratio1-1', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-EC_ratio1-1', 158);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EC_ratio1-10', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-EC_ratio1-10', 159);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EC_ratio1-2', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-EC_ratio1-2', 160);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EC_ratio1-2.5', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-EC_ratio1-2.5', 161);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'EC_ratio1-5', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-EC_ratio1-5', 162);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ECe_sat', 'http://w3id.org/glosis/model/procedure/electricalConductivityProcedure-ECe_sat', 163);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph-unkn-edta', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph-unkn-edta', 164);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph-unkn-m3', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph-unkn-m3', 165);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph-unkn-m3-spec', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph-unkn-m3-spec', 166);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph0-cohex', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph0-cohex', 167);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph0-nh4cl', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph0-nh4cl', 168);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph7-nh4oac', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph7-nh4oac', 169);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph7-nh4oac-aas', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph7-nh4oac-aas', 170);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph7-nh4oac-fp', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph7-nh4oac-fp', 171);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph7-unkn', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph7-unkn', 172);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph8-bacl2tea', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph8-bacl2tea', 173);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'ExchBases_ph8-unkn', 'http://w3id.org/glosis/model/procedure/exchangeableBasesProcedure-ExchBases_ph8-unkn', 174);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_ap14', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_ap14', 175);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_ap15', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_ap15', 176);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_ap20', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_ap20', 177);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_ap21', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_ap21', 178);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_c6h8o7-reeuwijk', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_c6h8o7-reeuwijk', 179);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_cacl2', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_cacl2', 180);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_capo4', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_capo4', 181);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_dtpa', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_dtpa', 182);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_edta', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_edta', 183);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_h2so4-truog', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_h2so4-truog', 184);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hcl-h2so4-nelson', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hcl-h2so4-nelson', 185);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hcl-nh4f-bray1', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hcl-nh4f-bray1', 186);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hcl-nh4f-bray2', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hcl-nh4f-bray2', 187);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hcl-nh4f-kurtz-bray', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hcl-nh4f-kurtz-bray', 188);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hno3', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hno3', 189);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_hotwater', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_hotwater', 190);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_m1', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_m1', 191);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_m2', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_m2', 192);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_m3', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_m3', 193);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_m3-spec', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_m3-spec', 194);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_nahco3-olsen', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_nahco3-olsen', 195);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_nahco3-olsen-dabin', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_nahco3-olsen-dabin', 196);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_naoac-morgan', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_naoac-morgan', 197);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_nh4-co3-2-ambic1', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_nh4-co3-2-ambic1', 198);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Extr_nh4ch3ch-oh-cooh-leuven', 'http://w3id.org/glosis/model/procedure/extractableElementsProcedure-Extr_nh4ch3ch-oh-cooh-leuven', 199);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy01', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy01', 200);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy02', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy02', 201);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy03', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy03', 202);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy04', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy04', 203);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy05', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy05', 204);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy06', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy06', 205);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaSO4_gy07', 'http://w3id.org/glosis/model/procedure/gypsumProcedure-CaSO4_gy07', 206);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'KSat_calcul-ptf', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-KSat_calcul-ptf', 207);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'KSat_calcul-ptf-genuchten', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-KSat_calcul-ptf-genuchten', 208);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'KSat_calcul-ptf-saxton', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-KSat_calcul-ptf-saxton', 209);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Ksat_bhole', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-Ksat_bhole', 210);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Ksat_column', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-Ksat_column', 211);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Ksat_dblring', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-Ksat_dblring', 212);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Ksat_invbhole', 'http://w3id.org/glosis/model/procedure/hydraulicConductivityProcedure-Ksat_invbhole', 213);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_calcul-ptf', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_calcul-ptf', 214);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_calcul-ptf-brookscorey', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_calcul-ptf-brookscorey', 215);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_d', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_d', 216);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_d-cl', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_d-cl', 217);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_d-cl-ww', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_d-cl-ww', 218);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_d-ww', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_d-ww', 219);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_ud-cl', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_ud-cl', 221);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'VMC_ud-co', 'http://w3id.org/glosis/model/procedure/moistureContentProcedure-VMC_ud-co', 222);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_bremner', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_bremner', 223);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_calcul', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_calcul', 224);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_calcul-oc10', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_calcul-oc10', 225);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_dc', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_dc', 226);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_h2so4', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_h2so4', 227);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_kjeldahl', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_kjeldahl', 228);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_kjeldahl-nh4', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_kjeldahl-nh4', 229);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_nelson', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_nelson', 230);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_tn04', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_tn04', 231);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_tn06', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_tn06', 232);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotalN_tn08', 'http://w3id.org/glosis/model/procedure/nitrogenTotalProcedure-TotalN_tn08', 233);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'FulAcidC_unkn', 'http://w3id.org/glosis/model/procedure/organicMatterProcedure-FulAcidC_unkn', 234);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'HumAcidC_unkn', 'http://w3id.org/glosis/model/procedure/organicMatterProcedure-HumAcidC_unkn', 235);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'OrgM_calcul-oc1.73', 'http://w3id.org/glosis/model/procedure/organicMatterProcedure-OrgM_calcul-oc1.73', 236);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'TotHumC_unkn', 'http://w3id.org/glosis/model/procedure/organicMatterProcedure-TotHumC_unkn', 237);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHCaCl2', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHCaCl2', 238);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl', 240);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHKCl_sat', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHKCl_sat', 241);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'pHNaF', 'http://w3id.org/glosis/model/procedure/pHProcedure-pHNaF', 242);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'RetentP_blakemore', 'http://w3id.org/glosis/model/procedure/phosphorusRetentionProcedure-RetentP_blakemore', 243);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'RetentP_unkn-spec', 'http://w3id.org/glosis/model/procedure/phosphorusRetentionProcedure-RetentP_unkn-spec', 244);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'Poros_calcul-pf0', 'http://w3id.org/glosis/model/procedure/porosityProcedure-Poros_calcul-pf0', 245);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SlbAn_calcul-unkn', 'http://w3id.org/glosis/model/procedure/solubleSaltsProcedure-SlbAn_calcul-unkn', 246);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SlbCat_calcul-unkn', 'http://w3id.org/glosis/model/procedure/solubleSaltsProcedure-SlbCat_calcul-unkn', 247);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-20-2000u', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-20-2000u', 248);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-50-2000u', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-50-2000u', 249);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SaSiCl_2-64-2000u', 'http://w3id.org/glosis/model/procedure/textureProcedure-SaSiCl_2-64-2000u', 250);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'SumTxtr_calcul', 'http://w3id.org/glosis/model/procedure/textureSumProcedure-SumTxtr_calcul', 251);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-ch3cooh-dc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-ch3cooh-dc', 252);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-ch3cooh-nodc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-ch3cooh-nodc', 253);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-ch3cooh-unkn', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-ch3cooh-unkn', 254);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-dc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-dc', 255);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h2so4-dc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h2so4-dc', 256);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h2so4-nodc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h2so4-nodc', 257);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h2so4-unkn', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h2so4-unkn', 258);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h3po4-dc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h3po4-dc', 259);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h3po4-nodc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h3po4-nodc', 260);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-h3po4-unkn', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-h3po4-unkn', 261);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-hcl-dc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-hcl-dc', 262);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-hcl-nodc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-hcl-nodc', 263);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-hcl-unkn', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-hcl-unkn', 264);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-nodc', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-nodc', 265);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_acid-unkn', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_acid-unkn', 266);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca01', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca01', 267);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca02', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca02', 268);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca03', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca03', 269);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca04', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca04', 270);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca05', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca05', 271);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca06', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca06', 272);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca07', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca07', 273);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca08', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca08', 274);
INSERT INTO core.procedure_phys_chem VALUES (NULL, 'CaCO3_ca09', 'http://w3id.org/glosis/model/procedure/totalCarbonateEquivalentProcedure-CaCO3_ca09', 275);


--
-- TOC entry 5300 (class 0 OID 23079350)
-- Dependencies: 238
-- Data for Name: profile; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5294 (class 0 OID 23079249)
-- Dependencies: 232
-- Data for Name: project; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5373 (class 0 OID 23080922)
-- Dependencies: 311
-- Data for Name: project_organisation; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5295 (class 0 OID 23079261)
-- Dependencies: 233
-- Data for Name: project_related; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5307 (class 0 OID 23079461)
-- Dependencies: 245
-- Data for Name: property_desc_element; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.property_desc_element VALUES ('saltProperty', 'http://w3id.org/glosis/model/layerhorizon/saltProperty', 143);
INSERT INTO core.property_desc_element VALUES ('biologicalAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/biologicalAbundanceProperty', 88);
INSERT INTO core.property_desc_element VALUES ('biologicalFeaturesProperty', 'http://w3id.org/glosis/model/layerhorizon/biologicalFeaturesProperty', 89);
INSERT INTO core.property_desc_element VALUES ('boundaryDistinctnessProperty', 'http://w3id.org/glosis/model/layerhorizon/boundaryDistinctnessProperty', 90);
INSERT INTO core.property_desc_element VALUES ('boundaryTopographyProperty', 'http://w3id.org/glosis/model/layerhorizon/boundaryTopographyProperty', 91);
INSERT INTO core.property_desc_element VALUES ('bulkDensityMineralProperty', 'http://w3id.org/glosis/model/layerhorizon/bulkDensityMineralProperty', 92);
INSERT INTO core.property_desc_element VALUES ('bulkDensityPeatProperty', 'http://w3id.org/glosis/model/layerhorizon/bulkDensityPeatProperty', 93);
INSERT INTO core.property_desc_element VALUES ('carbonatesContentProperty', 'http://w3id.org/glosis/model/layerhorizon/carbonatesContentProperty', 94);
INSERT INTO core.property_desc_element VALUES ('carbonatesFormsProperty', 'http://w3id.org/glosis/model/layerhorizon/carbonatesFormsProperty', 95);
INSERT INTO core.property_desc_element VALUES ('cationExchangeCapacityEffectiveProperty', 'http://w3id.org/glosis/model/layerhorizon/cationExchangeCapacityEffectiveProperty', 96);
INSERT INTO core.property_desc_element VALUES ('cationExchangeCapacityProperty', 'http://w3id.org/glosis/model/layerhorizon/cationExchangeCapacityProperty', 97);
INSERT INTO core.property_desc_element VALUES ('cationsSumProperty', 'http://w3id.org/glosis/model/layerhorizon/cationsSumProperty', 98);
INSERT INTO core.property_desc_element VALUES ('cementationContinuityProperty', 'http://w3id.org/glosis/model/layerhorizon/cementationContinuityProperty', 99);
INSERT INTO core.property_desc_element VALUES ('cementationDegreeProperty', 'http://w3id.org/glosis/model/layerhorizon/cementationDegreeProperty', 100);
INSERT INTO core.property_desc_element VALUES ('cementationFabricProperty', 'http://w3id.org/glosis/model/layerhorizon/cementationFabricProperty', 101);
INSERT INTO core.property_desc_element VALUES ('cementationNatureProperty', 'http://w3id.org/glosis/model/layerhorizon/cementationNatureProperty', 102);
INSERT INTO core.property_desc_element VALUES ('coatingAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/coatingAbundanceProperty', 103);
INSERT INTO core.property_desc_element VALUES ('coatingContrastProperty', 'http://w3id.org/glosis/model/layerhorizon/coatingContrastProperty', 104);
INSERT INTO core.property_desc_element VALUES ('coatingFormProperty', 'http://w3id.org/glosis/model/layerhorizon/coatingFormProperty', 105);
INSERT INTO core.property_desc_element VALUES ('coatingLocationProperty', 'http://w3id.org/glosis/model/layerhorizon/coatingLocationProperty', 106);
INSERT INTO core.property_desc_element VALUES ('coatingNatureProperty', 'http://w3id.org/glosis/model/layerhorizon/coatingNatureProperty', 107);
INSERT INTO core.property_desc_element VALUES ('consistenceDryProperty', 'http://w3id.org/glosis/model/layerhorizon/consistenceDryProperty', 108);
INSERT INTO core.property_desc_element VALUES ('consistenceMoistProperty', 'http://w3id.org/glosis/model/layerhorizon/consistenceMoistProperty', 109);
INSERT INTO core.property_desc_element VALUES ('dryConsistencyProperty', 'http://w3id.org/glosis/model/layerhorizon/dryConsistencyProperty', 110);
INSERT INTO core.property_desc_element VALUES ('gypsumContentProperty', 'http://w3id.org/glosis/model/layerhorizon/gypsumContentProperty', 111);
INSERT INTO core.property_desc_element VALUES ('gypsumFormsProperty', 'http://w3id.org/glosis/model/layerhorizon/gypsumFormsProperty', 112);
INSERT INTO core.property_desc_element VALUES ('gypsumWeightProperty', 'http://w3id.org/glosis/model/layerhorizon/gypsumWeightProperty', 113);
INSERT INTO core.property_desc_element VALUES ('mineralConcAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcAbundanceProperty', 114);
INSERT INTO core.property_desc_element VALUES ('mineralConcColourProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcColourProperty', 115);
INSERT INTO core.property_desc_element VALUES ('mineralConcHardnessProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcHardnessProperty', 116);
INSERT INTO core.property_desc_element VALUES ('mineralConcKindProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcKindProperty', 117);
INSERT INTO core.property_desc_element VALUES ('mineralConcNatureProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcNatureProperty', 118);
INSERT INTO core.property_desc_element VALUES ('mineralConcShapeProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcShapeProperty', 119);
INSERT INTO core.property_desc_element VALUES ('mineralConcSizeeProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcSizeProperty', 120);
INSERT INTO core.property_desc_element VALUES ('mineralConcVolumeProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralConcVolumeProperty', 121);
INSERT INTO core.property_desc_element VALUES ('mineralContentProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralContentProperty', 122);
INSERT INTO core.property_desc_element VALUES ('mineralFragmentsProperty', 'http://w3id.org/glosis/model/layerhorizon/mineralFragmentsProperty', 123);
INSERT INTO core.property_desc_element VALUES ('moistConsistencyProperty', 'http://w3id.org/glosis/model/layerhorizon/moistConsistencyProperty', 124);
INSERT INTO core.property_desc_element VALUES ('mottlesAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesAbundanceProperty', 125);
INSERT INTO core.property_desc_element VALUES ('mottlesColourProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesColourProperty', 127);
INSERT INTO core.property_desc_element VALUES ('mottlesBoundaryClassificationProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesBoundaryClassificationProperty', 126);
INSERT INTO core.property_desc_element VALUES ('mottlesContrastProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesContrastProperty', 128);
INSERT INTO core.property_desc_element VALUES ('mottlesPresenceProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesPresenceProperty', 129);
INSERT INTO core.property_desc_element VALUES ('mottlesSizeProperty', 'http://w3id.org/glosis/model/layerhorizon/mottlesSizeProperty', 130);
INSERT INTO core.property_desc_element VALUES ('oxalateExtractableOpticalDensityProperty', 'http://w3id.org/glosis/model/layerhorizon/oxalateExtractableOpticalDensityProperty', 131);
INSERT INTO core.property_desc_element VALUES ('ParticleSizeFractionsSumProperty', 'http://w3id.org/glosis/model/layerhorizon/particleSizeFractionsSumProperty', 132);
INSERT INTO core.property_desc_element VALUES ('peatDecompostionProperty', 'http://w3id.org/glosis/model/layerhorizon/peatDecompostionProperty', 133);
INSERT INTO core.property_desc_element VALUES ('peatDrainageProperty', 'http://w3id.org/glosis/model/layerhorizon/peatDrainageProperty', 134);
INSERT INTO core.property_desc_element VALUES ('peatVolumeProperty', 'http://w3id.org/glosis/model/layerhorizon/peatVolumeProperty', 135);
INSERT INTO core.property_desc_element VALUES ('plasticityProperty', 'http://w3id.org/glosis/model/layerhorizon/plasticityProperty', 136);
INSERT INTO core.property_desc_element VALUES ('poresAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/poresAbundanceProperty', 137);
INSERT INTO core.property_desc_element VALUES ('poresSizeProperty', 'http://w3id.org/glosis/model/layerhorizon/poresSizeProperty', 138);
INSERT INTO core.property_desc_element VALUES ('porosityClassProperty', 'http://w3id.org/glosis/model/layerhorizon/porosityClassProperty', 139);
INSERT INTO core.property_desc_element VALUES ('rootsAbundanceProperty', 'http://w3id.org/glosis/model/layerhorizon/rootsAbundanceProperty', 140);
INSERT INTO core.property_desc_element VALUES ('RootsPresenceProperty', 'http://w3id.org/glosis/model/layerhorizon/rootsPresenceProperty', 141);
INSERT INTO core.property_desc_element VALUES ('saltContentProperty', 'http://w3id.org/glosis/model/layerhorizon/saltContentProperty', 142);
INSERT INTO core.property_desc_element VALUES ('sandyTextureProperty', 'http://w3id.org/glosis/model/layerhorizon/sandyTextureProperty', 144);
INSERT INTO core.property_desc_element VALUES ('solubleAnionsTotalProperty', 'http://w3id.org/glosis/model/layerhorizon/solubleAnionsTotalProperty', 145);
INSERT INTO core.property_desc_element VALUES ('solubleCationsTotalProperty', 'http://w3id.org/glosis/model/layerhorizon/solubleCationsTotalProperty', 146);
INSERT INTO core.property_desc_element VALUES ('stickinessProperty', 'http://w3id.org/glosis/model/layerhorizon/stickinessProperty', 147);
INSERT INTO core.property_desc_element VALUES ('structureGradeProperty', 'http://w3id.org/glosis/model/layerhorizon/structureGradeProperty', 148);
INSERT INTO core.property_desc_element VALUES ('structureSizeProperty', 'http://w3id.org/glosis/model/layerhorizon/structureSizeProperty', 149);
INSERT INTO core.property_desc_element VALUES ('textureFieldClassProperty', 'http://w3id.org/glosis/model/layerhorizon/textureFieldClassProperty', 150);
INSERT INTO core.property_desc_element VALUES ('textureLabClassProperty', 'http://w3id.org/glosis/model/layerhorizon/textureLabClassProperty', 151);
INSERT INTO core.property_desc_element VALUES ('VoidsClassificationProperty', 'http://w3id.org/glosis/model/layerhorizon/voidsClassificationProperty', 152);
INSERT INTO core.property_desc_element VALUES ('voidsDiameterProperty', 'http://w3id.org/glosis/model/layerhorizon/voidsDiameterProperty', 153);
INSERT INTO core.property_desc_element VALUES ('wetPlasticityProperty', 'http://w3id.org/glosis/model/layerhorizon/wetPlasticityProperty', 154);
INSERT INTO core.property_desc_element VALUES ('bleachedSandProperty', 'http://w3id.org/glosis/model/common/bleachedSandProperty', 155);
INSERT INTO core.property_desc_element VALUES ('colourDryProperty', 'http://w3id.org/glosis/model/common/colourDryProperty', 156);
INSERT INTO core.property_desc_element VALUES ('colourWetProperty', 'http://w3id.org/glosis/model/common/colourWetProperty', 157);
INSERT INTO core.property_desc_element VALUES ('cracksDepthProperty', 'http://w3id.org/glosis/model/common/cracksDepthProperty', 158);
INSERT INTO core.property_desc_element VALUES ('cracksDistanceProperty', 'http://w3id.org/glosis/model/common/cracksDistanceProperty', 159);
INSERT INTO core.property_desc_element VALUES ('cracksWidthProperty', 'http://w3id.org/glosis/model/common/cracksWidthProperty', 160);
INSERT INTO core.property_desc_element VALUES ('fragmentCoverProperty', 'http://w3id.org/glosis/model/common/fragmentCoverProperty', 161);
INSERT INTO core.property_desc_element VALUES ('fragmentSizeProperty', 'http://w3id.org/glosis/model/common/fragmentSizeProperty', 162);
INSERT INTO core.property_desc_element VALUES ('infiltrationRateClassProperty', 'http://w3id.org/glosis/model/common/infiltrationRateClassProperty', 163);
INSERT INTO core.property_desc_element VALUES ('infiltrationRateNumericProperty', 'http://w3id.org/glosis/model/common/infiltrationRateNumericProperty', 164);
INSERT INTO core.property_desc_element VALUES ('organicMatterClassProperty', 'http://w3id.org/glosis/model/common/organicMatterClassProperty', 165);
INSERT INTO core.property_desc_element VALUES ('rockAbundanceProperty', 'http://w3id.org/glosis/model/common/rockAbundanceProperty', 166);
INSERT INTO core.property_desc_element VALUES ('rockShapeProperty', 'http://w3id.org/glosis/model/common/rockShapeProperty', 167);
INSERT INTO core.property_desc_element VALUES ('rockSizeProperty', 'http://w3id.org/glosis/model/common/rockSizeProperty', 168);
INSERT INTO core.property_desc_element VALUES ('textureProperty', 'http://w3id.org/glosis/model/common/textureProperty', 169);
INSERT INTO core.property_desc_element VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/common/weatheringFragmentsProperty', 170);


--
-- TOC entry 5305 (class 0 OID 23079437)
-- Dependencies: 243
-- Data for Name: property_desc_plot; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.property_desc_plot VALUES ('ForestAbundanceProperty', 'http://w3id.org/glosis/model/siteplot/ForestAbundanceProperty', 40);
INSERT INTO core.property_desc_plot VALUES ('GrassAbundanceProperty', 'http://w3id.org/glosis/model/siteplot/GrassAbundanceProperty', 41);
INSERT INTO core.property_desc_plot VALUES ('PavedAbundanceProperty', 'http://w3id.org/glosis/model/siteplot/PavedAbundanceProperty', 42);
INSERT INTO core.property_desc_plot VALUES ('ShrubsAbundaceProperty', 'http://w3id.org/glosis/model/siteplot/ShrubsAbundanceProperty', 43);
INSERT INTO core.property_desc_plot VALUES ('bareCoverAbundanceProperty', 'http://w3id.org/glosis/model/siteplot/bareCoverAbundanceProperty', 44);
INSERT INTO core.property_desc_plot VALUES ('erosionActivityPeriodProperty', 'http://w3id.org/glosis/model/siteplot/erosionActivityPeriodProperty', 45);
INSERT INTO core.property_desc_plot VALUES ('erosionAreaAffectedProperty', 'http://w3id.org/glosis/model/siteplot/erosionAreaAffectedProperty', 46);
INSERT INTO core.property_desc_plot VALUES ('erosionCategoryProperty', 'http://w3id.org/glosis/model/siteplot/erosionCategoryProperty', 47);
INSERT INTO core.property_desc_plot VALUES ('erosionDegreeProperty', 'http://w3id.org/glosis/model/siteplot/erosionDegreeProperty', 48);
INSERT INTO core.property_desc_plot VALUES ('erosionTotalAreaAffectedProperty', 'http://w3id.org/glosis/model/siteplot/erosionTotalAreaAffectedProperty', 49);
INSERT INTO core.property_desc_plot VALUES ('floodDurationProperty', 'http://w3id.org/glosis/model/siteplot/floodDurationProperty', 50);
INSERT INTO core.property_desc_plot VALUES ('floodFrequencyProperty', 'http://w3id.org/glosis/model/siteplot/floodFrequencyProperty', 51);
INSERT INTO core.property_desc_plot VALUES ('geologyProperty', 'http://w3id.org/glosis/model/siteplot/geologyProperty', 52);
INSERT INTO core.property_desc_plot VALUES ('groundwaterDepthProperty', 'http://w3id.org/glosis/model/siteplot/groundwaterDepthProperty', 53);
INSERT INTO core.property_desc_plot VALUES ('humanInfluenceClassProperty', 'http://w3id.org/glosis/model/siteplot/humanInfluenceClassProperty', 54);
INSERT INTO core.property_desc_plot VALUES ('koeppenClassProperty', 'http://w3id.org/glosis/model/siteplot/koeppenClassProperty', 55);
INSERT INTO core.property_desc_plot VALUES ('landUseClassProperty', 'http://w3id.org/glosis/model/siteplot/landUseClassProperty', 56);
INSERT INTO core.property_desc_plot VALUES ('LandformComplexProperty', 'http://w3id.org/glosis/model/siteplot/landformComplexProperty', 57);
INSERT INTO core.property_desc_plot VALUES ('lithologyProperty', 'http://w3id.org/glosis/model/siteplot/lithologyProperty', 58);
INSERT INTO core.property_desc_plot VALUES ('MajorLandFormProperty', 'http://w3id.org/glosis/model/siteplot/majorLandFormProperty', 59);
INSERT INTO core.property_desc_plot VALUES ('ParentDepositionProperty', 'http://w3id.org/glosis/model/siteplot/parentDepositionProperty', 60);
INSERT INTO core.property_desc_plot VALUES ('parentLithologyProperty', 'http://w3id.org/glosis/model/siteplot/parentLithologyProperty', 61);
INSERT INTO core.property_desc_plot VALUES ('parentTextureUnconsolidatedProperty', 'http://w3id.org/glosis/model/siteplot/parentTextureUnconsolidatedProperty', 62);
INSERT INTO core.property_desc_plot VALUES ('PhysiographyProperty', 'http://w3id.org/glosis/model/siteplot/physiographyProperty', 63);
INSERT INTO core.property_desc_plot VALUES ('rockOutcropsCoverProperty', 'http://w3id.org/glosis/model/siteplot/rockOutcropsCoverProperty', 64);
INSERT INTO core.property_desc_plot VALUES ('rockOutcropsDistanceProperty', 'http://w3id.org/glosis/model/siteplot/rockOutcropsDistanceProperty', 65);
INSERT INTO core.property_desc_plot VALUES ('slopeFormProperty', 'http://w3id.org/glosis/model/siteplot/slopeFormProperty', 66);
INSERT INTO core.property_desc_plot VALUES ('slopeGradientClassProperty', 'http://w3id.org/glosis/model/siteplot/slopeGradientClassProperty', 67);
INSERT INTO core.property_desc_plot VALUES ('slopeGradientProperty', 'http://w3id.org/glosis/model/siteplot/slopeGradientProperty', 68);
INSERT INTO core.property_desc_plot VALUES ('slopeOrientationClassProperty', 'http://w3id.org/glosis/model/siteplot/slopeOrientationClassProperty', 69);
INSERT INTO core.property_desc_plot VALUES ('slopeOrientationProperty', 'http://w3id.org/glosis/model/siteplot/slopeOrientationProperty', 70);
INSERT INTO core.property_desc_plot VALUES ('slopePathwaysProperty', 'http://w3id.org/glosis/model/siteplot/slopePathwaysProperty', 71);
INSERT INTO core.property_desc_plot VALUES ('surfaceAgeProperty', 'http://w3id.org/glosis/model/siteplot/surfaceAgeProperty', 72);
INSERT INTO core.property_desc_plot VALUES ('treeDensityProperty', 'http://w3id.org/glosis/model/siteplot/treeDensityProperty', 73);
INSERT INTO core.property_desc_plot VALUES ('VegetationClassProperty', 'http://w3id.org/glosis/model/siteplot/vegetationClassProperty', 74);
INSERT INTO core.property_desc_plot VALUES ('weatherConditionsCurrentProperty', 'http://w3id.org/glosis/model/siteplot/weatherConditionsCurrentProperty', 75);
INSERT INTO core.property_desc_plot VALUES ('weatherConditionsPastProperty', 'http://w3id.org/glosis/model/siteplot/weatherConditionsPastProperty', 76);
INSERT INTO core.property_desc_plot VALUES ('weatheringRockProperty', 'http://w3id.org/glosis/model/siteplot/weatheringRockProperty', 77);
INSERT INTO core.property_desc_plot VALUES ('soilDepthBedrockProperty', 'http://w3id.org/glosis/model/common/soilDepthBedrockProperty', 78);
INSERT INTO core.property_desc_plot VALUES ('soilDepthProperty', 'http://w3id.org/glosis/model/common/soilDepthProperty', 79);
INSERT INTO core.property_desc_plot VALUES ('soilDepthRootableClassProperty', 'http://w3id.org/glosis/model/common/soilDepthRootableClassProperty', 80);
INSERT INTO core.property_desc_plot VALUES ('soilDepthRootableProperty', 'http://w3id.org/glosis/model/common/soilDepthRootableProperty', 81);
INSERT INTO core.property_desc_plot VALUES ('soilDepthSampledProperty', 'http://w3id.org/glosis/model/common/soilDepthSampledProperty', 82);
INSERT INTO core.property_desc_plot VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/common/weatheringFragmentsProperty', 83);
INSERT INTO core.property_desc_plot VALUES ('cropClassProperty', 'http://w3id.org/glosis/model/siteplot/cropClassProperty', 84);


--
-- TOC entry 5306 (class 0 OID 23079449)
-- Dependencies: 244
-- Data for Name: property_desc_profile; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.property_desc_profile VALUES ('profileDescriptionStatusProperty', 'http://w3id.org/glosis/model/profile/profileDescriptionStatusProperty', 5);
INSERT INTO core.property_desc_profile VALUES ('soilClassificationFAOProperty', 'http://w3id.org/glosis/model/profile/soilClassificationFAOProperty', 6);
INSERT INTO core.property_desc_profile VALUES ('soilClassificationUSDAProperty', 'http://w3id.org/glosis/model/profile/soilClassificationUSDAProperty', 7);
INSERT INTO core.property_desc_profile VALUES ('soilClassificationWRBProperty', 'http://w3id.org/glosis/model/profile/soilClassificationWRBProperty', 8);
INSERT INTO core.property_desc_profile VALUES ('infiltrationRateClassProperty', 'http://w3id.org/glosis/model/common/infiltrationRateClassProperty', 9);
INSERT INTO core.property_desc_profile VALUES ('infiltrationRateNumericProperty', 'http://w3id.org/glosis/model/common/infiltrationRateNumericProperty', 10);
INSERT INTO core.property_desc_profile VALUES ('soilDepthBedrockProperty', 'http://w3id.org/glosis/model/common/soilDepthBedrockProperty', 11);
INSERT INTO core.property_desc_profile VALUES ('soilDepthProperty', 'http://w3id.org/glosis/model/common/soilDepthProperty', 12);
INSERT INTO core.property_desc_profile VALUES ('soilDepthRootableClassProperty', 'http://w3id.org/glosis/model/common/soilDepthRootableClassProperty', 13);
INSERT INTO core.property_desc_profile VALUES ('soilDepthRootableProperty', 'http://w3id.org/glosis/model/common/soilDepthRootableProperty', 14);
INSERT INTO core.property_desc_profile VALUES ('soilDepthSampledProperty', 'http://w3id.org/glosis/model/common/soilDepthSampledProperty', 15);


--
-- TOC entry 5330 (class 0 OID 23079943)
-- Dependencies: 268
-- Data for Name: property_desc_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5304 (class 0 OID 23079425)
-- Dependencies: 242
-- Data for Name: property_desc_surface; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.property_desc_surface VALUES ('SaltCoverProperty', 'http://w3id.org/glosis/model/surface/saltCoverProperty', 6);
INSERT INTO core.property_desc_surface VALUES ('saltPresenceProperty', 'http://w3id.org/glosis/model/surface/saltPresenceProperty', 7);
INSERT INTO core.property_desc_surface VALUES ('SaltThicknessProperty', 'http://w3id.org/glosis/model/surface/saltThicknessProperty', 8);
INSERT INTO core.property_desc_surface VALUES ('sealingConsistenceProperty', 'http://w3id.org/glosis/model/surface/sealingConsistenceProperty', 9);
INSERT INTO core.property_desc_surface VALUES ('sealingThicknessProperty', 'http://w3id.org/glosis/model/surface/sealingThicknessProperty', 10);
INSERT INTO core.property_desc_surface VALUES ('bleachedSandProperty', 'http://w3id.org/glosis/model/common/bleachedSandProperty', 11);
INSERT INTO core.property_desc_surface VALUES ('colourDryProperty', 'http://w3id.org/glosis/model/common/colourDryProperty', 12);
INSERT INTO core.property_desc_surface VALUES ('colourWetProperty', 'http://w3id.org/glosis/model/common/colourWetProperty', 13);
INSERT INTO core.property_desc_surface VALUES ('cracksDepthProperty', 'http://w3id.org/glosis/model/common/cracksDepthProperty', 14);
INSERT INTO core.property_desc_surface VALUES ('cracksDistanceProperty', 'http://w3id.org/glosis/model/common/cracksDistanceProperty', 15);
INSERT INTO core.property_desc_surface VALUES ('cracksWidthProperty', 'http://w3id.org/glosis/model/common/cracksWidthProperty', 16);
INSERT INTO core.property_desc_surface VALUES ('fragmentCoverProperty', 'http://w3id.org/glosis/model/common/fragmentCoverProperty', 17);
INSERT INTO core.property_desc_surface VALUES ('fragmentSizeProperty', 'http://w3id.org/glosis/model/common/fragmentSizeProperty', 18);
INSERT INTO core.property_desc_surface VALUES ('organicMatterClassProperty', 'http://w3id.org/glosis/model/common/organicMatterClassProperty', 19);
INSERT INTO core.property_desc_surface VALUES ('rockAbundanceProperty', 'http://w3id.org/glosis/model/common/rockAbundanceProperty', 20);
INSERT INTO core.property_desc_surface VALUES ('rockShapeProperty', 'http://w3id.org/glosis/model/common/rockShapeProperty', 21);
INSERT INTO core.property_desc_surface VALUES ('rockSizeProperty', 'http://w3id.org/glosis/model/common/rockSizeProperty', 22);
INSERT INTO core.property_desc_surface VALUES ('textureProperty', 'http://w3id.org/glosis/model/common/textureProperty', 23);
INSERT INTO core.property_desc_surface VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/common/weatheringFragmentsProperty', 24);


--
-- TOC entry 5302 (class 0 OID 23079396)
-- Dependencies: 240
-- Data for Name: property_phys_chem; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.property_phys_chem VALUES ('aluminiumProperty', 'http://w3id.org/glosis/model/layerhorizon/aluminiumProperty', 39);
INSERT INTO core.property_phys_chem VALUES ('Calcium (Ca++) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Caltot', 9);
INSERT INTO core.property_phys_chem VALUES ('Carbon (C) - organic', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Carorg', 10);
INSERT INTO core.property_phys_chem VALUES ('Carbon (C) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Cartot', 11);
INSERT INTO core.property_phys_chem VALUES ('Copper (Cu) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Copext', 12);
INSERT INTO core.property_phys_chem VALUES ('Copper (Cu) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Coptot', 13);
INSERT INTO core.property_phys_chem VALUES ('Hydrogen (H+) - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Hydexc', 14);
INSERT INTO core.property_phys_chem VALUES ('Iron (Fe) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Iroext', 15);
INSERT INTO core.property_phys_chem VALUES ('Iron (Fe) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Irotot', 16);
INSERT INTO core.property_phys_chem VALUES ('Magnesium (Mg++) - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Magexc', 17);
INSERT INTO core.property_phys_chem VALUES ('Magnesium (Mg) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Magext', 18);
INSERT INTO core.property_phys_chem VALUES ('Magnesium (Mg) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Magtot', 19);
INSERT INTO core.property_phys_chem VALUES ('Manganese (Mn) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Manext', 20);
INSERT INTO core.property_phys_chem VALUES ('Manganese (Mn) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Mantot', 21);
INSERT INTO core.property_phys_chem VALUES ('Nitrogen (N) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Nittot', 22);
INSERT INTO core.property_phys_chem VALUES ('Phosphorus (P) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Phoext', 23);
INSERT INTO core.property_phys_chem VALUES ('Phosphorus (P) - retention', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Phoret', 24);
INSERT INTO core.property_phys_chem VALUES ('Phosphorus (P) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Photot', 25);
INSERT INTO core.property_phys_chem VALUES ('Potassium (K+) - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Potexc', 26);
INSERT INTO core.property_phys_chem VALUES ('Potassium (K) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Potext', 27);
INSERT INTO core.property_phys_chem VALUES ('Potassium (K) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Pottot', 28);
INSERT INTO core.property_phys_chem VALUES ('Sodium (Na+) - exchangeable %', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Sodexp', 29);
INSERT INTO core.property_phys_chem VALUES ('Sodium (Na) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Sodext', 30);
INSERT INTO core.property_phys_chem VALUES ('Sodium (Na) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Sodtot', 31);
INSERT INTO core.property_phys_chem VALUES ('Sulfur (S) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Sulext', 32);
INSERT INTO core.property_phys_chem VALUES ('Sulfur (S) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Sultot', 33);
INSERT INTO core.property_phys_chem VALUES ('Clay texture fraction', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Textclay', 34);
INSERT INTO core.property_phys_chem VALUES ('Sand texture fraction', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Textsand', 35);
INSERT INTO core.property_phys_chem VALUES ('Silt texture fraction', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Textsilt', 36);
INSERT INTO core.property_phys_chem VALUES ('Zinc (Zn) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Zinext', 37);
INSERT INTO core.property_phys_chem VALUES ('pH - Hydrogen potential', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-pH', 38);
INSERT INTO core.property_phys_chem VALUES ('bulkDensityFineEarthProperty', 'http://w3id.org/glosis/model/layerhorizon/bulkDensityFineEarthProperty', 40);
INSERT INTO core.property_phys_chem VALUES ('bulkDensityWholeSoilProperty', 'http://w3id.org/glosis/model/layerhorizon/bulkDensityWholeSoilProperty', 41);
INSERT INTO core.property_phys_chem VALUES ('cadmiumProperty', 'http://w3id.org/glosis/model/layerhorizon/cadmiumProperty', 42);
INSERT INTO core.property_phys_chem VALUES ('carbonInorganicProperty', 'http://w3id.org/glosis/model/layerhorizon/carbonInorganicProperty', 43);
INSERT INTO core.property_phys_chem VALUES ('cationExchangeCapacitycSoilProperty', 'http://w3id.org/glosis/model/layerhorizon/cationExchangeCapacitycSoilProperty', 44);
INSERT INTO core.property_phys_chem VALUES ('coarseFragmentsProperty', 'http://w3id.org/glosis/model/layerhorizon/coarseFragmentsProperty', 45);
INSERT INTO core.property_phys_chem VALUES ('effectiveCecProperty', 'http://w3id.org/glosis/model/layerhorizon/effectiveCecProperty', 46);
INSERT INTO core.property_phys_chem VALUES ('electricalConductivityProperty', 'http://w3id.org/glosis/model/layerhorizon/electricalConductivityProperty', 47);
INSERT INTO core.property_phys_chem VALUES ('gypsumProperty', 'http://w3id.org/glosis/model/layerhorizon/gypsumProperty', 48);
INSERT INTO core.property_phys_chem VALUES ('hydraulicConductivityProperty', 'http://w3id.org/glosis/model/layerhorizon/hydraulicConductivityProperty', 49);
INSERT INTO core.property_phys_chem VALUES ('manganeseProperty', 'http://w3id.org/glosis/model/layerhorizon/manganeseProperty', 50);
INSERT INTO core.property_phys_chem VALUES ('molybdenumProperty', 'http://w3id.org/glosis/model/layerhorizon/molybdenumProperty', 51);
INSERT INTO core.property_phys_chem VALUES ('organicMatterProperty', 'http://w3id.org/glosis/model/layerhorizon/organicMatterProperty', 52);
INSERT INTO core.property_phys_chem VALUES ('pHProperty', 'http://w3id.org/glosis/model/layerhorizon/pHProperty', 53);
INSERT INTO core.property_phys_chem VALUES ('porosityProperty', 'http://w3id.org/glosis/model/layerhorizon/porosityProperty', 54);
INSERT INTO core.property_phys_chem VALUES ('solubleSaltsProperty', 'http://w3id.org/glosis/model/layerhorizon/solubleSaltsProperty', 55);
INSERT INTO core.property_phys_chem VALUES ('totalCarbonateEquivalentProperty', 'http://w3id.org/glosis/model/layerhorizon/totalCarbonateEquivalentProperty', 56);
INSERT INTO core.property_phys_chem VALUES ('zincProperty', 'http://w3id.org/glosis/model/layerhorizon/zincProperty', 57);
INSERT INTO core.property_phys_chem VALUES ('Acidity - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Aciexc', 1);
INSERT INTO core.property_phys_chem VALUES ('Boron (B) - total', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Bortot', 6);
INSERT INTO core.property_phys_chem VALUES ('Aluminium (Al+++) - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Aluexc', 2);
INSERT INTO core.property_phys_chem VALUES ('Available water capacity - volumetric (FC to WP)', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Avavol', 3);
INSERT INTO core.property_phys_chem VALUES ('Base saturation - calculated', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Bascal', 4);
INSERT INTO core.property_phys_chem VALUES ('Boron (B) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Borext', 5);
INSERT INTO core.property_phys_chem VALUES ('Calcium (Ca++) - exchangeable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Calexc', 7);
INSERT INTO core.property_phys_chem VALUES ('Calcium (Ca++) - extractable', 'http://w3id.org/glosis/model/codelists/physioChemicalPropertyCode-Calext', 8);


--
-- TOC entry 5324 (class 0 OID 23079726)
-- Dependencies: 262
-- Data for Name: result_desc_element; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5322 (class 0 OID 23079692)
-- Dependencies: 260
-- Data for Name: result_desc_plot; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5323 (class 0 OID 23079709)
-- Dependencies: 261
-- Data for Name: result_desc_profile; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5342 (class 0 OID 23080189)
-- Dependencies: 280
-- Data for Name: result_desc_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5321 (class 0 OID 23079675)
-- Dependencies: 259
-- Data for Name: result_desc_surface; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5320 (class 0 OID 23079651)
-- Dependencies: 258
-- Data for Name: result_phys_chem_element; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5336 (class 0 OID 23080065)
-- Dependencies: 274
-- Data for Name: result_phys_chem_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5296 (class 0 OID 23079282)
-- Dependencies: 234
-- Data for Name: site; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5297 (class 0 OID 23079292)
-- Dependencies: 235
-- Data for Name: site_project; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5329 (class 0 OID 23079919)
-- Dependencies: 267
-- Data for Name: specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5328 (class 0 OID 23079896)
-- Dependencies: 266
-- Data for Name: specimen_prep_process; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5327 (class 0 OID 23079883)
-- Dependencies: 265
-- Data for Name: specimen_storage; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5326 (class 0 OID 23079870)
-- Dependencies: 264
-- Data for Name: specimen_transport; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5299 (class 0 OID 23079329)
-- Dependencies: 237
-- Data for Name: surface; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5344 (class 0 OID 23080246)
-- Dependencies: 282
-- Data for Name: surface_individual; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5311 (class 0 OID 23079509)
-- Dependencies: 249
-- Data for Name: thesaurus_desc_element; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.thesaurus_desc_element VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-A', 313);
INSERT INTO core.thesaurus_desc_element VALUES ('Common ', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-C', 314);
INSERT INTO core.thesaurus_desc_element VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-D', 315);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-F', 316);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-M', 317);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-N', 318);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-V', 319);
INSERT INTO core.thesaurus_desc_element VALUES ('Boulders', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-B', 320);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-C', 321);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-F', 322);
INSERT INTO core.thesaurus_desc_element VALUES ('Large boulders', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-L', 323);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-M', 324);
INSERT INTO core.thesaurus_desc_element VALUES ('Stones', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-S', 325);
INSERT INTO core.thesaurus_desc_element VALUES ('Abundant ', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-A', 326);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-C', 327);
INSERT INTO core.thesaurus_desc_element VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-D', 328);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-F', 329);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-M', 330);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-N', 331);
INSERT INTO core.thesaurus_desc_element VALUES ('Stone line', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-S', 332);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-V', 333);
INSERT INTO core.thesaurus_desc_element VALUES ('Angular', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-A', 334);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/biologicalAbundanceValueCode-C', 1);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/biologicalAbundanceValueCode-F', 2);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/biologicalAbundanceValueCode-M', 3);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/biologicalAbundanceValueCode-N', 4);
INSERT INTO core.thesaurus_desc_element VALUES ('Artefacts', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-A', 5);
INSERT INTO core.thesaurus_desc_element VALUES ('Burrows (unspecified)', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-B', 6);
INSERT INTO core.thesaurus_desc_element VALUES ('Infilled large burrows', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-BI', 7);
INSERT INTO core.thesaurus_desc_element VALUES ('Open large burrows', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-BO', 8);
INSERT INTO core.thesaurus_desc_element VALUES ('Charcoal', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-C', 9);
INSERT INTO core.thesaurus_desc_element VALUES ('Earthworm channels', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-E', 10);
INSERT INTO core.thesaurus_desc_element VALUES ('Other insect activity', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-I', 11);
INSERT INTO core.thesaurus_desc_element VALUES ('Pedotubules', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-P', 12);
INSERT INTO core.thesaurus_desc_element VALUES ('Termite or ant channels and nests', 'http://w3id.org/glosis/model/codelists/biologicalFeaturesValueCode-T', 13);
INSERT INTO core.thesaurus_desc_element VALUES ('Clear', 'http://w3id.org/glosis/model/codelists/boundaryClassificationValueCode-C', 14);
INSERT INTO core.thesaurus_desc_element VALUES ('Diffuse', 'http://w3id.org/glosis/model/codelists/boundaryClassificationValueCode-D', 15);
INSERT INTO core.thesaurus_desc_element VALUES ('Sharp', 'http://w3id.org/glosis/model/codelists/boundaryClassificationValueCode-S', 16);
INSERT INTO core.thesaurus_desc_element VALUES ('Abrupt', 'http://w3id.org/glosis/model/codelists/boundaryDistinctnessValueCode-A', 17);
INSERT INTO core.thesaurus_desc_element VALUES ('Clear', 'http://w3id.org/glosis/model/codelists/boundaryDistinctnessValueCode-C', 18);
INSERT INTO core.thesaurus_desc_element VALUES ('Diffuse', 'http://w3id.org/glosis/model/codelists/boundaryDistinctnessValueCode-D', 19);
INSERT INTO core.thesaurus_desc_element VALUES ('Gradual', 'http://w3id.org/glosis/model/codelists/boundaryDistinctnessValueCode-G', 20);
INSERT INTO core.thesaurus_desc_element VALUES ('Broken', 'http://w3id.org/glosis/model/codelists/boundaryTopographyValueCode-B', 21);
INSERT INTO core.thesaurus_desc_element VALUES ('Irregular', 'http://w3id.org/glosis/model/codelists/boundaryTopographyValueCode-I', 22);
INSERT INTO core.thesaurus_desc_element VALUES ('Smooth', 'http://w3id.org/glosis/model/codelists/boundaryTopographyValueCode-S', 23);
INSERT INTO core.thesaurus_desc_element VALUES ('Wavy', 'http://w3id.org/glosis/model/codelists/boundaryTopographyValueCode-W', 24);
INSERT INTO core.thesaurus_desc_element VALUES ('Many pores, moist materials drop easily out of the auger.', 'http://w3id.org/glosis/model/codelists/bulkDensityMineralValueCode-BD1', 25);
INSERT INTO core.thesaurus_desc_element VALUES ('Sample disintegrates into numerous fragments after application of weak pressure.', 'http://w3id.org/glosis/model/codelists/bulkDensityMineralValueCode-BD2', 26);
INSERT INTO core.thesaurus_desc_element VALUES ('Knife can be pushed into the moist soil with weak pressure, sample disintegrates into few fragments, which may be further divided.', 'http://w3id.org/glosis/model/codelists/bulkDensityMineralValueCode-BD3', 27);
INSERT INTO core.thesaurus_desc_element VALUES ('Knife penetrates only 1–2 cm into the moist soil, some effort required, sample disintegrates into few fragments, which cannot be subdivided further.', 'http://w3id.org/glosis/model/codelists/bulkDensityMineralValueCode-BD4', 28);
INSERT INTO core.thesaurus_desc_element VALUES ('Very large pressure necessary to force knife into the soil, no further disintegration of sample.', 'http://w3id.org/glosis/model/codelists/bulkDensityMineralValueCode-BD5', 29);
INSERT INTO core.thesaurus_desc_element VALUES ('< 0.04g cm-3', 'http://w3id.org/glosis/model/codelists/bulkDensityPeatValueCode-BD1', 30);
INSERT INTO core.thesaurus_desc_element VALUES ('0.04–0.07g cm-3', 'http://w3id.org/glosis/model/codelists/bulkDensityPeatValueCode-BD2', 31);
INSERT INTO core.thesaurus_desc_element VALUES ('0.07–0.11g cm-3', 'http://w3id.org/glosis/model/codelists/bulkDensityPeatValueCode-BD3', 32);
INSERT INTO core.thesaurus_desc_element VALUES ('0.11–0.17g cm-3', 'http://w3id.org/glosis/model/codelists/bulkDensityPeatValueCode-BD4', 33);
INSERT INTO core.thesaurus_desc_element VALUES ('> 0.17g cm-3', 'http://w3id.org/glosis/model/codelists/bulkDensityPeatValueCode-BD5', 34);
INSERT INTO core.thesaurus_desc_element VALUES ('≈ > 25 Extremely calcareous Extremely strong reaction. Thick foam forms quickly.', 'http://w3id.org/glosis/model/codelists/carbonatesContentValueCode-EX', 35);
INSERT INTO core.thesaurus_desc_element VALUES ('≈ 2–10 Moderately calcareous Visible effervescence.', 'http://w3id.org/glosis/model/codelists/carbonatesContentValueCode-MO', 36);
INSERT INTO core.thesaurus_desc_element VALUES ('0 Non-calcareous No detectable visible or audible effervescence.', 'http://w3id.org/glosis/model/codelists/carbonatesContentValueCode-N', 37);
INSERT INTO core.thesaurus_desc_element VALUES ('≈ 0–2 Slightly calcareous Audible effervescence but not visible.', 'http://w3id.org/glosis/model/codelists/carbonatesContentValueCode-SL', 38);
INSERT INTO core.thesaurus_desc_element VALUES ('≈ 10–25 Strongly calcareous Strong visible effervescence. Bubbles form a low foam.', 'http://w3id.org/glosis/model/codelists/carbonatesContentValueCode-ST', 39);
INSERT INTO core.thesaurus_desc_element VALUES ('disperse powdery lime', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-D', 40);
INSERT INTO core.thesaurus_desc_element VALUES ('hard concretions', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-HC', 41);
INSERT INTO core.thesaurus_desc_element VALUES ('hard hollow concretions', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-HHC', 42);
INSERT INTO core.thesaurus_desc_element VALUES ('Carbonates (calcareous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-K', 178);
INSERT INTO core.thesaurus_desc_element VALUES ('hard cemented layer or layers of carbonates (less than 10 cm thick)', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-HL', 43);
INSERT INTO core.thesaurus_desc_element VALUES ('marl layer', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-M', 44);
INSERT INTO core.thesaurus_desc_element VALUES ('pseudomycelia* (carbonate infillings in pores, resembling mycelia)', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-PM', 45);
INSERT INTO core.thesaurus_desc_element VALUES ('soft concretions', 'http://w3id.org/glosis/model/codelists/carbonatesFormsValueCode-SC', 46);
INSERT INTO core.thesaurus_desc_element VALUES ('Broken', 'http://w3id.org/glosis/model/codelists/cementationContinuityValueCode-B', 47);
INSERT INTO core.thesaurus_desc_element VALUES ('Continuous', 'http://w3id.org/glosis/model/codelists/cementationContinuityValueCode-C', 48);
INSERT INTO core.thesaurus_desc_element VALUES ('Discontinuous', 'http://w3id.org/glosis/model/codelists/cementationContinuityValueCode-D', 49);
INSERT INTO core.thesaurus_desc_element VALUES ('Cemented', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-C', 50);
INSERT INTO core.thesaurus_desc_element VALUES ('Indurated', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-I', 51);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderately cemented', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-M', 52);
INSERT INTO core.thesaurus_desc_element VALUES ('Non-cemented and non-compacted', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-N', 53);
INSERT INTO core.thesaurus_desc_element VALUES ('Weakly cemented', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-W', 54);
INSERT INTO core.thesaurus_desc_element VALUES ('Compacted but non-cemented', 'http://w3id.org/glosis/model/codelists/cementationDegreeValueCode-Y', 55);
INSERT INTO core.thesaurus_desc_element VALUES ('Nodular', 'http://w3id.org/glosis/model/codelists/cementationFabricValueCode-D', 56);
INSERT INTO core.thesaurus_desc_element VALUES ('Pisolithic', 'http://w3id.org/glosis/model/codelists/cementationFabricValueCode-Pi', 57);
INSERT INTO core.thesaurus_desc_element VALUES ('Platy', 'http://w3id.org/glosis/model/codelists/cementationFabricValueCode-Pl', 58);
INSERT INTO core.thesaurus_desc_element VALUES ('Vesicular', 'http://w3id.org/glosis/model/codelists/cementationFabricValueCode-V', 59);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-C', 60);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay–sesquioxides', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-CS', 61);
INSERT INTO core.thesaurus_desc_element VALUES ('Iron', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-F', 62);
INSERT INTO core.thesaurus_desc_element VALUES ('Iron–manganese (sesquioxides)', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-FM', 63);
INSERT INTO core.thesaurus_desc_element VALUES ('Iron–organic matter', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-FO', 64);
INSERT INTO core.thesaurus_desc_element VALUES ('Gypsum', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-GY', 65);
INSERT INTO core.thesaurus_desc_element VALUES ('Ice', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-I', 66);
INSERT INTO core.thesaurus_desc_element VALUES ('Carbonates', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-K', 67);
INSERT INTO core.thesaurus_desc_element VALUES ('Carbonates–silica', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-KQ', 68);
INSERT INTO core.thesaurus_desc_element VALUES ('Mechanical', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-M', 69);
INSERT INTO core.thesaurus_desc_element VALUES ('Not known', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-NK', 70);
INSERT INTO core.thesaurus_desc_element VALUES ('Ploughing', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-P', 71);
INSERT INTO core.thesaurus_desc_element VALUES ('Silica', 'http://w3id.org/glosis/model/codelists/cementationNatureValueCode-Q', 72);
INSERT INTO core.thesaurus_desc_element VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-A', 73);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-C', 74);
INSERT INTO core.thesaurus_desc_element VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-D', 75);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-F', 76);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-M', 77);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-N', 78);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few ', 'http://w3id.org/glosis/model/codelists/coatingAbundanceValueCode-V', 79);
INSERT INTO core.thesaurus_desc_element VALUES ('Distinct', 'http://w3id.org/glosis/model/codelists/coatingContrastValueCode-D', 80);
INSERT INTO core.thesaurus_desc_element VALUES ('Faint', 'http://w3id.org/glosis/model/codelists/coatingContrastValueCode-F', 81);
INSERT INTO core.thesaurus_desc_element VALUES ('Prominent', 'http://w3id.org/glosis/model/codelists/coatingContrastValueCode-P', 82);
INSERT INTO core.thesaurus_desc_element VALUES ('Continuous', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-C', 83);
INSERT INTO core.thesaurus_desc_element VALUES ('Continuous irregular (non-uniform, heterogeneous)', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-CI', 84);
INSERT INTO core.thesaurus_desc_element VALUES ('Discontinuous circular', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-DC', 85);
INSERT INTO core.thesaurus_desc_element VALUES ('Dendroidal', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-DE', 86);
INSERT INTO core.thesaurus_desc_element VALUES ('Discontinuous irregular', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-DI', 87);
INSERT INTO core.thesaurus_desc_element VALUES ('Other', 'http://w3id.org/glosis/model/codelists/coatingFormValueCode-O', 88);
INSERT INTO core.thesaurus_desc_element VALUES ('Bridges between sand grains', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-BR', 89);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse fragments', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-CF', 90);
INSERT INTO core.thesaurus_desc_element VALUES ('Lamellae (clay bands)', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-LA', 91);
INSERT INTO core.thesaurus_desc_element VALUES ('No specific location', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-NS', 92);
INSERT INTO core.thesaurus_desc_element VALUES ('Pedfaces', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-P', 93);
INSERT INTO core.thesaurus_desc_element VALUES ('Horizontal pedfaces', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-PH', 94);
INSERT INTO core.thesaurus_desc_element VALUES ('Vertical pedfaces', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-PV', 95);
INSERT INTO core.thesaurus_desc_element VALUES ('Voids', 'http://w3id.org/glosis/model/codelists/coatingLocationValueCode-VO', 96);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-C', 97);
INSERT INTO core.thesaurus_desc_element VALUES ('Calcium carbonate', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-CC', 98);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay and humus (organic matter)', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-CH', 99);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay and sesquioxides', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-CS', 100);
INSERT INTO core.thesaurus_desc_element VALUES ('Gibbsite', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-GB', 101);
INSERT INTO core.thesaurus_desc_element VALUES ('Humus', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-H', 102);
INSERT INTO core.thesaurus_desc_element VALUES ('Hypodermic coatings (Hypodermic coatings, as used here, are field-scale features, commonly only expressed as hydromorphic features. Micromorphological hypodermic coatings include non-redox features [Bullock et al., 1985].)', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-HC', 103);
INSERT INTO core.thesaurus_desc_element VALUES ('Jarosite', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-JA', 104);
INSERT INTO core.thesaurus_desc_element VALUES ('Manganese', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-MN', 105);
INSERT INTO core.thesaurus_desc_element VALUES ('Pressure faces', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-PF', 106);
INSERT INTO core.thesaurus_desc_element VALUES ('Sesquioxides', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-S', 107);
INSERT INTO core.thesaurus_desc_element VALUES ('Sand coatings', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SA', 108);
INSERT INTO core.thesaurus_desc_element VALUES ('Shiny faces (as in nitic horizon)', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SF', 109);
INSERT INTO core.thesaurus_desc_element VALUES ('Slickensides, predominantly intersecting (Slickensides are polished and grooved ped surfaces that are produced by aggregates sliding one past another.)', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SI', 110);
INSERT INTO core.thesaurus_desc_element VALUES ('Silica (opal)', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SL', 111);
INSERT INTO core.thesaurus_desc_element VALUES ('Slickensides, non intersecting', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SN', 112);
INSERT INTO core.thesaurus_desc_element VALUES ('Slickensides, partly intersecting', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-SP', 113);
INSERT INTO core.thesaurus_desc_element VALUES ('Silt coatings', 'http://w3id.org/glosis/model/codelists/coatingNatureValueCode-ST', 114);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-EHA', 115);
INSERT INTO core.thesaurus_desc_element VALUES ('Hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-HA', 116);
INSERT INTO core.thesaurus_desc_element VALUES ('hard to very hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-HVH', 117);
INSERT INTO core.thesaurus_desc_element VALUES ('Loose', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-LO', 118);
INSERT INTO core.thesaurus_desc_element VALUES ('Slightly hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-SHA', 119);
INSERT INTO core.thesaurus_desc_element VALUES ('slightly hard to hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-SHH', 120);
INSERT INTO core.thesaurus_desc_element VALUES ('Soft', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-SO', 121);
INSERT INTO core.thesaurus_desc_element VALUES ('soft to slightly hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-SSH', 122);
INSERT INTO core.thesaurus_desc_element VALUES ('Very hard', 'http://w3id.org/glosis/model/codelists/consistenceDryValueCode-VHA', 123);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely firm', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-EFI', 124);
INSERT INTO core.thesaurus_desc_element VALUES ('Firm', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-FI', 125);
INSERT INTO core.thesaurus_desc_element VALUES ('Friable', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-FR', 126);
INSERT INTO core.thesaurus_desc_element VALUES ('Loose', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-LO', 127);
INSERT INTO core.thesaurus_desc_element VALUES ('Very firm ', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-VFI', 128);
INSERT INTO core.thesaurus_desc_element VALUES ('Very friable', 'http://w3id.org/glosis/model/codelists/consistenceMoistValueCode-VFR', 129);
INSERT INTO core.thesaurus_desc_element VALUES ('Distinct', 'http://w3id.org/glosis/model/codelists/contrastValueCode-D', 130);
INSERT INTO core.thesaurus_desc_element VALUES ('Faint', 'http://w3id.org/glosis/model/codelists/contrastValueCode-F', 131);
INSERT INTO core.thesaurus_desc_element VALUES ('Prominent', 'http://w3id.org/glosis/model/codelists/contrastValueCode-P', 132);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely gypsiric', 'http://w3id.org/glosis/model/codelists/gypsumContentValueCode-EX', 133);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderately gypsiric', 'http://w3id.org/glosis/model/codelists/gypsumContentValueCode-MO', 134);
INSERT INTO core.thesaurus_desc_element VALUES ('Non-gypsiric', 'http://w3id.org/glosis/model/codelists/gypsumContentValueCode-N', 135);
INSERT INTO core.thesaurus_desc_element VALUES ('Slightly gypsiric', 'http://w3id.org/glosis/model/codelists/gypsumContentValueCode-SL', 136);
INSERT INTO core.thesaurus_desc_element VALUES ('Strongly gypsiric', 'http://w3id.org/glosis/model/codelists/gypsumContentValueCode-ST', 137);
INSERT INTO core.thesaurus_desc_element VALUES ('disperse powdery gypsum', 'http://w3id.org/glosis/model/codelists/gypsumFormsValueCode-D', 138);
INSERT INTO core.thesaurus_desc_element VALUES ('“gazha” (clayey water-saturated layer with high gypsum content)', 'http://w3id.org/glosis/model/codelists/gypsumFormsValueCode-G', 139);
INSERT INTO core.thesaurus_desc_element VALUES ('hard cemented layer or layers of gypsum (less than 10 cm thick)', 'http://w3id.org/glosis/model/codelists/gypsumFormsValueCode-HL', 140);
INSERT INTO core.thesaurus_desc_element VALUES ('soft concretions', 'http://w3id.org/glosis/model/codelists/gypsumFormsValueCode-SC', 141);
INSERT INTO core.thesaurus_desc_element VALUES ('Bluish-black', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-BB', 142);
INSERT INTO core.thesaurus_desc_element VALUES ('Black', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-BL', 143);
INSERT INTO core.thesaurus_desc_element VALUES ('Brown', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-BR', 144);
INSERT INTO core.thesaurus_desc_element VALUES ('Brownish', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-BS', 145);
INSERT INTO core.thesaurus_desc_element VALUES ('Blue', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-BU', 146);
INSERT INTO core.thesaurus_desc_element VALUES ('Greenish', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-GE', 147);
INSERT INTO core.thesaurus_desc_element VALUES ('Grey', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-GR', 148);
INSERT INTO core.thesaurus_desc_element VALUES ('Greyish', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-GS', 149);
INSERT INTO core.thesaurus_desc_element VALUES ('Multicoloured', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-MC', 150);
INSERT INTO core.thesaurus_desc_element VALUES ('Reddish brown', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-RB', 151);
INSERT INTO core.thesaurus_desc_element VALUES ('Red', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-RE', 152);
INSERT INTO core.thesaurus_desc_element VALUES ('Reddish', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-RS', 153);
INSERT INTO core.thesaurus_desc_element VALUES ('Reddish yellow', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-RY', 154);
INSERT INTO core.thesaurus_desc_element VALUES ('White', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-WH', 155);
INSERT INTO core.thesaurus_desc_element VALUES ('Yellowish brown', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-YB', 156);
INSERT INTO core.thesaurus_desc_element VALUES ('Yellow', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-YE', 157);
INSERT INTO core.thesaurus_desc_element VALUES ('Yellowish red', 'http://w3id.org/glosis/model/codelists/mineralConcColourValueCode-YR', 158);
INSERT INTO core.thesaurus_desc_element VALUES ('Both hard and soft.', 'http://w3id.org/glosis/model/codelists/mineralConcHardnessValueCode-B', 159);
INSERT INTO core.thesaurus_desc_element VALUES ('Hard', 'http://w3id.org/glosis/model/codelists/mineralConcHardnessValueCode-H', 160);
INSERT INTO core.thesaurus_desc_element VALUES ('Soft', 'http://w3id.org/glosis/model/codelists/mineralConcHardnessValueCode-S', 161);
INSERT INTO core.thesaurus_desc_element VALUES ('Concretion', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-C', 162);
INSERT INTO core.thesaurus_desc_element VALUES ('Crack infillings', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-IC', 163);
INSERT INTO core.thesaurus_desc_element VALUES ('Pore infillings', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-IP', 164);
INSERT INTO core.thesaurus_desc_element VALUES ('Nodule', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-N', 165);
INSERT INTO core.thesaurus_desc_element VALUES ('Other', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-O', 166);
INSERT INTO core.thesaurus_desc_element VALUES ('Residual rock fragment', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-R', 167);
INSERT INTO core.thesaurus_desc_element VALUES ('Soft segregation (or soft accumulation)', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-S', 168);
INSERT INTO core.thesaurus_desc_element VALUES ('Soft concretion', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-SC', 169);
INSERT INTO core.thesaurus_desc_element VALUES ('Crystal', 'http://w3id.org/glosis/model/codelists/mineralConcKindValueCode-T', 170);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay (argillaceous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-C', 171);
INSERT INTO core.thesaurus_desc_element VALUES ('Clay–sesquioxides', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-CS', 172);
INSERT INTO core.thesaurus_desc_element VALUES ('Iron (ferruginous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-F', 173);
INSERT INTO core.thesaurus_desc_element VALUES ('Iron–manganese (sesquioxides)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-FM', 174);
INSERT INTO core.thesaurus_desc_element VALUES ('Gibbsite', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-GB', 175);
INSERT INTO core.thesaurus_desc_element VALUES ('Gypsum (gypsiferous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-GY', 176);
INSERT INTO core.thesaurus_desc_element VALUES ('Jarosite', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-JA', 177);
INSERT INTO core.thesaurus_desc_element VALUES ('Carbonates–silica', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-KQ', 179);
INSERT INTO core.thesaurus_desc_element VALUES ('Manganese (manganiferous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-M', 180);
INSERT INTO core.thesaurus_desc_element VALUES ('Not known', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-NK', 181);
INSERT INTO core.thesaurus_desc_element VALUES ('Silica (siliceous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-Q', 182);
INSERT INTO core.thesaurus_desc_element VALUES ('Sulphur (sulphurous)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-S', 183);
INSERT INTO core.thesaurus_desc_element VALUES ('Salt (saline)', 'http://w3id.org/glosis/model/codelists/mineralConcNatureValueCode-SA', 184);
INSERT INTO core.thesaurus_desc_element VALUES ('Angular', 'http://w3id.org/glosis/model/codelists/mineralConcShapeValueCode-A', 185);
INSERT INTO core.thesaurus_desc_element VALUES ('Elongated', 'http://w3id.org/glosis/model/codelists/mineralConcShapeValueCode-E', 186);
INSERT INTO core.thesaurus_desc_element VALUES ('Flat', 'http://w3id.org/glosis/model/codelists/mineralConcShapeValueCode-F', 187);
INSERT INTO core.thesaurus_desc_element VALUES ('Irregular', 'http://w3id.org/glosis/model/codelists/mineralConcShapeValueCode-I', 188);
INSERT INTO core.thesaurus_desc_element VALUES ('Rounded (spherical)', 'http://w3id.org/glosis/model/codelists/mineralConcShapeValueCode-R', 189);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse', 'http://w3id.org/glosis/model/codelists/mineralConcSizeValueCode-C', 190);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine', 'http://w3id.org/glosis/model/codelists/mineralConcSizeValueCode-F', 191);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/mineralConcSizeValueCode-M', 192);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine', 'http://w3id.org/glosis/model/codelists/mineralConcSizeValueCode-V', 193);
INSERT INTO core.thesaurus_desc_element VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-A', 194);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-C', 195);
INSERT INTO core.thesaurus_desc_element VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-D', 196);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-F', 197);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-M', 198);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-N', 199);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/mineralConcVolumeValueCode-V', 200);
INSERT INTO core.thesaurus_desc_element VALUES ('Feldspar', 'http://w3id.org/glosis/model/codelists/mineralFragmentsValueCode-FE', 201);
INSERT INTO core.thesaurus_desc_element VALUES ('Mica', 'http://w3id.org/glosis/model/codelists/mineralFragmentsValueCode-MI', 202);
INSERT INTO core.thesaurus_desc_element VALUES ('<Quartz', 'http://w3id.org/glosis/model/codelists/mineralFragmentsValueCode-QU', 203);
INSERT INTO core.thesaurus_desc_element VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-A', 204);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-C', 205);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-F', 206);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-M', 207);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-N', 208);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/mottlesAbundanceValueCode-V', 209);
INSERT INTO core.thesaurus_desc_element VALUES ('A Coarse', 'http://w3id.org/glosis/model/codelists/mottlesSizeValueCode-A', 210);
INSERT INTO core.thesaurus_desc_element VALUES ('F Fine', 'http://w3id.org/glosis/model/codelists/mottlesSizeValueCode-F', 211);
INSERT INTO core.thesaurus_desc_element VALUES ('M Medium', 'http://w3id.org/glosis/model/codelists/mottlesSizeValueCode-M', 212);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine', 'http://w3id.org/glosis/model/codelists/mottlesSizeValueCode-V', 213);
INSERT INTO core.thesaurus_desc_element VALUES ('very low', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D1', 214);
INSERT INTO core.thesaurus_desc_element VALUES ('low', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D2', 215);
INSERT INTO core.thesaurus_desc_element VALUES ('moderate', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D3', 216);
INSERT INTO core.thesaurus_desc_element VALUES ('strong', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D4', 217);
INSERT INTO core.thesaurus_desc_element VALUES ('moderately strong', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D5.1', 218);
INSERT INTO core.thesaurus_desc_element VALUES ('very strong', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-D5.2', 219);
INSERT INTO core.thesaurus_desc_element VALUES ('Fibric', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-Fibric', 220);
INSERT INTO core.thesaurus_desc_element VALUES ('Hemic', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-Hemic', 221);
INSERT INTO core.thesaurus_desc_element VALUES ('Sapric', 'http://w3id.org/glosis/model/codelists/peatDecompostionValueCode-Sapric', 222);
INSERT INTO core.thesaurus_desc_element VALUES ('Undrained', 'http://w3id.org/glosis/model/codelists/peatDrainageValueCode-DC1', 223);
INSERT INTO core.thesaurus_desc_element VALUES ('Weakly drained', 'http://w3id.org/glosis/model/codelists/peatDrainageValueCode-DC2', 224);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderately drained', 'http://w3id.org/glosis/model/codelists/peatDrainageValueCode-DC3', 225);
INSERT INTO core.thesaurus_desc_element VALUES ('Well drained', 'http://w3id.org/glosis/model/codelists/peatDrainageValueCode-DC4', 226);
INSERT INTO core.thesaurus_desc_element VALUES ('< 3%', 'http://w3id.org/glosis/model/codelists/peatVolumeValueCode-SV1', 227);
INSERT INTO core.thesaurus_desc_element VALUES ('3– < 5%', 'http://w3id.org/glosis/model/codelists/peatVolumeValueCode-SV2', 228);
INSERT INTO core.thesaurus_desc_element VALUES ('5– < 8%', 'http://w3id.org/glosis/model/codelists/peatVolumeValueCode-SV3', 229);
INSERT INTO core.thesaurus_desc_element VALUES ('8– < 12%', 'http://w3id.org/glosis/model/codelists/peatVolumeValueCode-SV4', 230);
INSERT INTO core.thesaurus_desc_element VALUES ('≥ 12%', 'http://w3id.org/glosis/model/codelists/peatVolumeValueCode-SV5', 231);
INSERT INTO core.thesaurus_desc_element VALUES ('Non-plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-NPL', 232);
INSERT INTO core.thesaurus_desc_element VALUES ('Plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-PL', 233);
INSERT INTO core.thesaurus_desc_element VALUES ('plastic to very plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-PVP', 234);
INSERT INTO core.thesaurus_desc_element VALUES ('Slightly plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-SPL', 235);
INSERT INTO core.thesaurus_desc_element VALUES ('slightly plastic to plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-SPP', 236);
INSERT INTO core.thesaurus_desc_element VALUES ('Very plastic', 'http://w3id.org/glosis/model/codelists/plasticityValueCode-VPL', 237);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/poresAbundanceValueCode-C', 238);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/poresAbundanceValueCode-F', 239);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/poresAbundanceValueCode-M', 240);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/poresAbundanceValueCode-N', 241);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/poresAbundanceValueCode-V', 242);
INSERT INTO core.thesaurus_desc_element VALUES ('Very low', 'http://w3id.org/glosis/model/codelists/porosityClassValueCode-1', 243);
INSERT INTO core.thesaurus_desc_element VALUES ('Low', 'http://w3id.org/glosis/model/codelists/porosityClassValueCode-2', 244);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/porosityClassValueCode-3', 245);
INSERT INTO core.thesaurus_desc_element VALUES ('High', 'http://w3id.org/glosis/model/codelists/porosityClassValueCode-4', 246);
INSERT INTO core.thesaurus_desc_element VALUES ('Very high', 'http://w3id.org/glosis/model/codelists/porosityClassValueCode-5', 247);
INSERT INTO core.thesaurus_desc_element VALUES ('Common', 'http://w3id.org/glosis/model/codelists/rootsAbundanceValueCode-C', 248);
INSERT INTO core.thesaurus_desc_element VALUES ('Few', 'http://w3id.org/glosis/model/codelists/rootsAbundanceValueCode-F', 249);
INSERT INTO core.thesaurus_desc_element VALUES ('Many', 'http://w3id.org/glosis/model/codelists/rootsAbundanceValueCode-M', 250);
INSERT INTO core.thesaurus_desc_element VALUES ('None', 'http://w3id.org/glosis/model/codelists/rootsAbundanceValueCode-N', 251);
INSERT INTO core.thesaurus_desc_element VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/rootsAbundanceValueCode-V', 252);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-EX', 253);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderately salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-MO', 254);
INSERT INTO core.thesaurus_desc_element VALUES ('(nearly)Not salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-N', 255);
INSERT INTO core.thesaurus_desc_element VALUES ('Slightly salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-SL', 256);
INSERT INTO core.thesaurus_desc_element VALUES ('Strongly salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-ST', 257);
INSERT INTO core.thesaurus_desc_element VALUES ('Very strongly salty', 'http://w3id.org/glosis/model/codelists/saltContentValueCode-VST', 258);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-CS', 259);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse sandy loam', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-CSL', 260);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-FS', 261);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine sandy loam', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-FSL', 262);
INSERT INTO core.thesaurus_desc_element VALUES ('Loamy coarse sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-LCS', 263);
INSERT INTO core.thesaurus_desc_element VALUES ('Loamy fine sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-LFS', 264);
INSERT INTO core.thesaurus_desc_element VALUES ('Loamy very fine sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-LVFS', 265);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-MS', 266);
INSERT INTO core.thesaurus_desc_element VALUES ('Sand, unsorted', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-US', 267);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine sand', 'http://w3id.org/glosis/model/codelists/sandyTextureValueCode-VFS', 268);
INSERT INTO core.thesaurus_desc_element VALUES ('Non-sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-NST', 269);
INSERT INTO core.thesaurus_desc_element VALUES ('slightly sticky to sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-SSS', 270);
INSERT INTO core.thesaurus_desc_element VALUES ('Slightly sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-SST', 271);
INSERT INTO core.thesaurus_desc_element VALUES ('Sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-ST', 272);
INSERT INTO core.thesaurus_desc_element VALUES ('sticky to very sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-SVS', 273);
INSERT INTO core.thesaurus_desc_element VALUES ('Very sticky', 'http://w3id.org/glosis/model/codelists/stickinessValueCode-VST', 274);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderate', 'http://w3id.org/glosis/model/codelists/structureGradeValueCode-MO', 275);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderate to strong', 'http://w3id.org/glosis/model/codelists/structureGradeValueCode-MS', 276);
INSERT INTO core.thesaurus_desc_element VALUES ('Strong', 'http://w3id.org/glosis/model/codelists/structureGradeValueCode-ST', 277);
INSERT INTO core.thesaurus_desc_element VALUES ('Weak', 'http://w3id.org/glosis/model/codelists/structureGradeValueCode-WE', 278);
INSERT INTO core.thesaurus_desc_element VALUES ('Weak to moderate', 'http://w3id.org/glosis/model/codelists/structureGradeValueCode-WM', 279);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse/thick', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-CO', 280);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely coarse', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-EC', 281);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine/thin', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-FI', 282);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-ME', 283);
INSERT INTO core.thesaurus_desc_element VALUES ('Very coarse/thick', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-VC', 284);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine/thin', 'http://w3id.org/glosis/model/codelists/structureSizeValueCode-VF', 285);
INSERT INTO core.thesaurus_desc_element VALUES ('Vesicular', 'http://w3id.org/glosis/model/codelists/voidsClassificationValueCode-B', 286);
INSERT INTO core.thesaurus_desc_element VALUES ('Channels', 'http://w3id.org/glosis/model/codelists/voidsClassificationValueCode-C', 287);
INSERT INTO core.thesaurus_desc_element VALUES ('Interstitial', 'http://w3id.org/glosis/model/codelists/voidsClassificationValueCode-I', 288);
INSERT INTO core.thesaurus_desc_element VALUES ('Planes', 'http://w3id.org/glosis/model/codelists/voidsClassificationValueCode-P', 289);
INSERT INTO core.thesaurus_desc_element VALUES ('Vughs', 'http://w3id.org/glosis/model/codelists/voidsClassificationValueCode-V', 290);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-C', 291);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-F', 292);
INSERT INTO core.thesaurus_desc_element VALUES ('fine and very fine', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-FF', 293);
INSERT INTO core.thesaurus_desc_element VALUES ('fine and medium', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-FM', 294);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-M', 295);
INSERT INTO core.thesaurus_desc_element VALUES ('medium and coarse', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-MC', 296);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-V', 297);
INSERT INTO core.thesaurus_desc_element VALUES ('Very coarse', 'http://w3id.org/glosis/model/codelists/voidsDiameterValueCode-VC', 298);
INSERT INTO core.thesaurus_desc_element VALUES ('Deep 10–20', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-D', 299);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium 2–10', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-M', 300);
INSERT INTO core.thesaurus_desc_element VALUES ('Surface < 2', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-S', 301);
INSERT INTO core.thesaurus_desc_element VALUES ('Very deep > 20', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-V', 302);
INSERT INTO core.thesaurus_desc_element VALUES ('Very closely spaced < 0.2', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-C', 303);
INSERT INTO core.thesaurus_desc_element VALUES ('Closely spaced 0.2–0.5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-D', 304);
INSERT INTO core.thesaurus_desc_element VALUES ('Moderately widely spaced 0.5–2', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-M', 305);
INSERT INTO core.thesaurus_desc_element VALUES ('Very widely spaced > 5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-V', 306);
INSERT INTO core.thesaurus_desc_element VALUES ('Widely spaced 2–5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-W', 307);
INSERT INTO core.thesaurus_desc_element VALUES ('Extremely wide > 10cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-E', 308);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine < 1cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-F', 309);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium 1cm–2cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-M', 310);
INSERT INTO core.thesaurus_desc_element VALUES ('Very wide 5cm–10cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-V', 311);
INSERT INTO core.thesaurus_desc_element VALUES ('Wide 2cm–5cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-W', 312);
INSERT INTO core.thesaurus_desc_element VALUES ('Flat', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-F', 335);
INSERT INTO core.thesaurus_desc_element VALUES ('Rounded', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-R', 336);
INSERT INTO core.thesaurus_desc_element VALUES ('Subrounded', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-S', 337);
INSERT INTO core.thesaurus_desc_element VALUES ('Artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-A', 338);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AC', 339);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AF', 340);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AM', 341);
INSERT INTO core.thesaurus_desc_element VALUES ('Very fine artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AV', 342);
INSERT INTO core.thesaurus_desc_element VALUES ('Boulders and large boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-BL', 343);
INSERT INTO core.thesaurus_desc_element VALUES ('Combination of classes', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-C', 344);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse gravel and stones', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-CS', 345);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine and medium gravel/artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-FM', 346);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium and coarse gravel/artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-MC', 347);
INSERT INTO core.thesaurus_desc_element VALUES ('Rock fragments', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-R', 348);
INSERT INTO core.thesaurus_desc_element VALUES ('Boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RB', 349);
INSERT INTO core.thesaurus_desc_element VALUES ('Coarse gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RC', 350);
INSERT INTO core.thesaurus_desc_element VALUES ('Fine gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RF', 351);
INSERT INTO core.thesaurus_desc_element VALUES ('Large boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RL', 352);
INSERT INTO core.thesaurus_desc_element VALUES ('Medium gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RM', 353);
INSERT INTO core.thesaurus_desc_element VALUES ('Stones', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RS', 354);
INSERT INTO core.thesaurus_desc_element VALUES ('Stones and boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-SB', 355);
INSERT INTO core.thesaurus_desc_element VALUES ('Fresh or slightly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-F', 356);
INSERT INTO core.thesaurus_desc_element VALUES ('Strongly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-S', 357);
INSERT INTO core.thesaurus_desc_element VALUES ('Weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-W', 358);


--
-- TOC entry 5309 (class 0 OID 23079485)
-- Dependencies: 247
-- Data for Name: thesaurus_desc_plot; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.thesaurus_desc_plot VALUES ('Cereals', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce', 1);
INSERT INTO core.thesaurus_desc_plot VALUES ('Mass movement', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-M', 68);
INSERT INTO core.thesaurus_desc_plot VALUES ('sunny/clear', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-SU', 380);
INSERT INTO core.thesaurus_desc_plot VALUES ('no rain in the last month', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC1', 381);
INSERT INTO core.thesaurus_desc_plot VALUES ('no rain in the last week', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC2', 382);
INSERT INTO core.thesaurus_desc_plot VALUES ('no rain in the last 24 hours', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC3', 383);
INSERT INTO core.thesaurus_desc_plot VALUES ('rainy without heavy rain in the last 24 hours', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC4', 384);
INSERT INTO core.thesaurus_desc_plot VALUES ('heavier rain for some days or rainstorm in the last 24 hours', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC5', 385);
INSERT INTO core.thesaurus_desc_plot VALUES ('extremely rainy time or snow melting', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-WC6', 386);
INSERT INTO core.thesaurus_desc_plot VALUES ('Fresh or slightly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-F', 387);
INSERT INTO core.thesaurus_desc_plot VALUES ('Strongly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-S', 388);
INSERT INTO core.thesaurus_desc_plot VALUES ('Weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-W', 389);
INSERT INTO core.thesaurus_desc_plot VALUES ('shale', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC4', 224);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rye', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Ry', 8);
INSERT INTO core.thesaurus_desc_plot VALUES ('Extreme', 'http://w3id.org/glosis/model/codelists/erosionDegreeValueCode-E', 78);
INSERT INTO core.thesaurus_desc_plot VALUES ('sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UM1', 257);
INSERT INTO core.thesaurus_desc_plot VALUES ('Barley', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Ba', 2);
INSERT INTO core.thesaurus_desc_plot VALUES ('Maize', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Ma', 3);
INSERT INTO core.thesaurus_desc_plot VALUES ('Millet', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Mi', 4);
INSERT INTO core.thesaurus_desc_plot VALUES ('Oats', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Oa', 5);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rice, paddy', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Pa', 6);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rice, dry', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Ri', 7);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sorghum', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_So', 9);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wheat', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ce_Wh', 10);
INSERT INTO core.thesaurus_desc_plot VALUES ('Fibre crops', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fi', 11);
INSERT INTO core.thesaurus_desc_plot VALUES ('Cotton', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fi_Co', 12);
INSERT INTO core.thesaurus_desc_plot VALUES ('Jute', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fi_Ju', 13);
INSERT INTO core.thesaurus_desc_plot VALUES ('Fodder plants', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo', 14);
INSERT INTO core.thesaurus_desc_plot VALUES ('Alfalfa', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Al', 15);
INSERT INTO core.thesaurus_desc_plot VALUES ('Clover', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Cl', 16);
INSERT INTO core.thesaurus_desc_plot VALUES ('Grasses', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Gr', 17);
INSERT INTO core.thesaurus_desc_plot VALUES ('Hay', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Ha', 18);
INSERT INTO core.thesaurus_desc_plot VALUES ('Leguminous', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Le', 19);
INSERT INTO core.thesaurus_desc_plot VALUES ('Maize', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Ma', 20);
INSERT INTO core.thesaurus_desc_plot VALUES ('Pumpkins', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fo_Pu', 21);
INSERT INTO core.thesaurus_desc_plot VALUES ('Fruits and melons', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr', 22);
INSERT INTO core.thesaurus_desc_plot VALUES ('Apples', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Ap', 23);
INSERT INTO core.thesaurus_desc_plot VALUES ('Bananas', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Ba', 24);
INSERT INTO core.thesaurus_desc_plot VALUES ('Citrus', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Ci', 25);
INSERT INTO core.thesaurus_desc_plot VALUES ('Grapes, Wine, Raisins', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Gr', 26);
INSERT INTO core.thesaurus_desc_plot VALUES ('Mangoes', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Ma', 27);
INSERT INTO core.thesaurus_desc_plot VALUES ('Melons', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Fr_Me', 28);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-luxury foods and tobacco', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Lu', 29);
INSERT INTO core.thesaurus_desc_plot VALUES ('Cocoa', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Lu_Cc', 30);
INSERT INTO core.thesaurus_desc_plot VALUES ('Coffee', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Lu_Co', 31);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tea', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Lu_Te', 32);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tobacco', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Lu_To', 33);
INSERT INTO core.thesaurus_desc_plot VALUES ('Oilcrops', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi', 34);
INSERT INTO core.thesaurus_desc_plot VALUES ('Coconuts', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Cc', 35);
INSERT INTO core.thesaurus_desc_plot VALUES ('Groundnuts', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Gr', 36);
INSERT INTO core.thesaurus_desc_plot VALUES ('Linseed', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Li', 37);
INSERT INTO core.thesaurus_desc_plot VALUES ('Oil-palm', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Op', 38);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rape', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Ra', 39);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sesame', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Se', 40);
INSERT INTO core.thesaurus_desc_plot VALUES ('Soybeans', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_So', 41);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sunflower', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Oi_Su', 42);
INSERT INTO core.thesaurus_desc_plot VALUES ('Olives', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ol', 43);
INSERT INTO core.thesaurus_desc_plot VALUES ('Other crops', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ot', 44);
INSERT INTO core.thesaurus_desc_plot VALUES ('Palm (fibres, kernels)', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ot_Pa', 45);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rubber', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ot_Ru', 46);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sugar cane', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ot_Sc', 47);
INSERT INTO core.thesaurus_desc_plot VALUES ('Pulses', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Pu', 48);
INSERT INTO core.thesaurus_desc_plot VALUES ('Beans', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Pu_Be', 49);
INSERT INTO core.thesaurus_desc_plot VALUES ('Lentils', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Pu_Le', 50);
INSERT INTO core.thesaurus_desc_plot VALUES ('Peas', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Pu_Pe', 51);
INSERT INTO core.thesaurus_desc_plot VALUES ('Roots and tubers', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ro', 52);
INSERT INTO core.thesaurus_desc_plot VALUES ('Cassava', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ro_Ca', 53);
INSERT INTO core.thesaurus_desc_plot VALUES ('Potatoes', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ro_Po', 54);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sugar beets', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ro_Su', 55);
INSERT INTO core.thesaurus_desc_plot VALUES ('Yams', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ro_Ya', 56);
INSERT INTO core.thesaurus_desc_plot VALUES ('Vegetables', 'http://w3id.org/glosis/model/codelists/cropClassValueCode-Ve', 57);
INSERT INTO core.thesaurus_desc_plot VALUES ('Active at present', 'http://w3id.org/glosis/model/codelists/erosionActivityPeriodValueCode-A', 58);
INSERT INTO core.thesaurus_desc_plot VALUES ('Active in historical times', 'http://w3id.org/glosis/model/codelists/erosionActivityPeriodValueCode-H', 59);
INSERT INTO core.thesaurus_desc_plot VALUES ('Period of activity not known', 'http://w3id.org/glosis/model/codelists/erosionActivityPeriodValueCode-N', 60);
INSERT INTO core.thesaurus_desc_plot VALUES ('Active in recent past', 'http://w3id.org/glosis/model/codelists/erosionActivityPeriodValueCode-R', 61);
INSERT INTO core.thesaurus_desc_plot VALUES ('Accelerated and natural erosion not distinguished', 'http://w3id.org/glosis/model/codelists/erosionActivityPeriodValueCode-X', 62);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wind (aeolian) erosion or deposition', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-A', 63);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wind deposition', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-AD', 64);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wind erosion and deposition', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-AM', 65);
INSERT INTO core.thesaurus_desc_plot VALUES ('Shifting sands', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-AS', 66);
INSERT INTO core.thesaurus_desc_plot VALUES ('Salt deposition', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-AZ', 67);
INSERT INTO core.thesaurus_desc_plot VALUES ('No evidence of erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-N', 69);
INSERT INTO core.thesaurus_desc_plot VALUES ('Not known', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-NK', 70);
INSERT INTO core.thesaurus_desc_plot VALUES ('Water erosion or deposition', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-W', 71);
INSERT INTO core.thesaurus_desc_plot VALUES ('Water and wind erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WA', 72);
INSERT INTO core.thesaurus_desc_plot VALUES ('Deposition by water', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WD', 73);
INSERT INTO core.thesaurus_desc_plot VALUES ('Gully erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WG', 74);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rill erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WR', 75);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sheet erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WS', 76);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tunnel erosion', 'http://w3id.org/glosis/model/codelists/erosionCategoryValueCode-WT', 77);
INSERT INTO core.thesaurus_desc_plot VALUES ('Moderate', 'http://w3id.org/glosis/model/codelists/erosionDegreeValueCode-M', 79);
INSERT INTO core.thesaurus_desc_plot VALUES ('Slight', 'http://w3id.org/glosis/model/codelists/erosionDegreeValueCode-S', 80);
INSERT INTO core.thesaurus_desc_plot VALUES ('Severe', 'http://w3id.org/glosis/model/codelists/erosionDegreeValueCode-V', 81);
INSERT INTO core.thesaurus_desc_plot VALUES ('0', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-0', 82);
INSERT INTO core.thesaurus_desc_plot VALUES ('0–5', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-1', 83);
INSERT INTO core.thesaurus_desc_plot VALUES ('5–10', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-2', 84);
INSERT INTO core.thesaurus_desc_plot VALUES ('10–25', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-3', 85);
INSERT INTO core.thesaurus_desc_plot VALUES ('25–50', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-4', 86);
INSERT INTO core.thesaurus_desc_plot VALUES ('> 50', 'http://w3id.org/glosis/model/codelists/erosionTotalAreaAffectedValueCode-5', 87);
INSERT INTO core.thesaurus_desc_plot VALUES ('Archaeological (burial mound, midden)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-AC', 88);
INSERT INTO core.thesaurus_desc_plot VALUES ('Artificial drainage', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-AD', 89);
INSERT INTO core.thesaurus_desc_plot VALUES ('Borrow pit', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-BP', 90);
INSERT INTO core.thesaurus_desc_plot VALUES ('Burning', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-BR', 91);
INSERT INTO core.thesaurus_desc_plot VALUES ('Bunding', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-BU', 92);
INSERT INTO core.thesaurus_desc_plot VALUES ('Clearing', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-CL', 93);
INSERT INTO core.thesaurus_desc_plot VALUES ('Impact crater', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-CR', 94);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dump (not specified)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-DU', 95);
INSERT INTO core.thesaurus_desc_plot VALUES ('Application of fertilizers', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-FE', 96);
INSERT INTO core.thesaurus_desc_plot VALUES ('Border irrigation', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-IB', 97);
INSERT INTO core.thesaurus_desc_plot VALUES ('Drip irrigation', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-ID', 98);
INSERT INTO core.thesaurus_desc_plot VALUES ('Furrow irrigation', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-IF', 99);
INSERT INTO core.thesaurus_desc_plot VALUES ('Flood irrigation', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-IP', 100);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sprinkler irrigation', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-IS', 101);
INSERT INTO core.thesaurus_desc_plot VALUES ('Irrigation (not specified)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-IU', 102);
INSERT INTO core.thesaurus_desc_plot VALUES ('Landfill (also sanitary)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-LF', 103);
INSERT INTO core.thesaurus_desc_plot VALUES ('Levelling', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-LV', 104);
INSERT INTO core.thesaurus_desc_plot VALUES ('Raised beds (engineering purposes)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-ME', 105);
INSERT INTO core.thesaurus_desc_plot VALUES ('Mine (surface, including openpit, gravel and quarries)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MI', 106);
INSERT INTO core.thesaurus_desc_plot VALUES ('Organic additions (not specified)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MO', 107);
INSERT INTO core.thesaurus_desc_plot VALUES ('Plaggen', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MP', 108);
INSERT INTO core.thesaurus_desc_plot VALUES ('Raised beds (agricultural purposes)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MR', 109);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sand additions', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MS', 110);
INSERT INTO core.thesaurus_desc_plot VALUES ('Mineral additions (not specified)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-MU', 111);
INSERT INTO core.thesaurus_desc_plot VALUES ('No influence', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-N', 112);
INSERT INTO core.thesaurus_desc_plot VALUES ('Not known', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-NK', 113);
INSERT INTO core.thesaurus_desc_plot VALUES ('Ploughing', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-PL', 114);
INSERT INTO core.thesaurus_desc_plot VALUES ('Pollution', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-PO', 115);
INSERT INTO core.thesaurus_desc_plot VALUES ('Scalped area', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-SA', 116);
INSERT INTO core.thesaurus_desc_plot VALUES ('SS', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-SS', 327);
INSERT INTO core.thesaurus_desc_plot VALUES ('Surface compaction', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-SC', 117);
INSERT INTO core.thesaurus_desc_plot VALUES ('Terracing', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-TE', 118);
INSERT INTO core.thesaurus_desc_plot VALUES ('Vegetation strongly disturbed', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-VE', 119);
INSERT INTO core.thesaurus_desc_plot VALUES ('Vegetation moderately disturbed', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-VM', 120);
INSERT INTO core.thesaurus_desc_plot VALUES ('Vegetation slightly disturbed', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-VS', 121);
INSERT INTO core.thesaurus_desc_plot VALUES ('Vegetation disturbed (not specified)', 'http://w3id.org/glosis/model/codelists/humanInfluenceClassValueCode-VU', 122);
INSERT INTO core.thesaurus_desc_plot VALUES ('A = Crop agriculture (cropping)', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-A', 123);
INSERT INTO core.thesaurus_desc_plot VALUES ('Annual field cropping', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA', 124);
INSERT INTO core.thesaurus_desc_plot VALUES ('Shifting cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA1', 125);
INSERT INTO core.thesaurus_desc_plot VALUES ('Fallow system cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA2', 126);
INSERT INTO core.thesaurus_desc_plot VALUES ('Ley system cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA3', 127);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rainfed arable cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA4', 128);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wet rice cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA5', 129);
INSERT INTO core.thesaurus_desc_plot VALUES ('Irrigated cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AA6', 130);
INSERT INTO core.thesaurus_desc_plot VALUES ('Perennial field cropping', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AP', 131);
INSERT INTO core.thesaurus_desc_plot VALUES ('Non-irrigated cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AP1', 132);
INSERT INTO core.thesaurus_desc_plot VALUES ('Irrigated cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AP2', 133);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tree and shrub cropping', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AT', 134);
INSERT INTO core.thesaurus_desc_plot VALUES ('Non-irrigated tree crop cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AT1', 135);
INSERT INTO core.thesaurus_desc_plot VALUES ('Irrigated tree crop cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AT2', 136);
INSERT INTO core.thesaurus_desc_plot VALUES ('Non-irrigated shrub crop cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AT3', 137);
INSERT INTO core.thesaurus_desc_plot VALUES ('Irrigated shrub crop cultivation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-AT4', 138);
INSERT INTO core.thesaurus_desc_plot VALUES ('F = Forestry', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-F', 139);
INSERT INTO core.thesaurus_desc_plot VALUES ('Natural forest and woodland', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-FN', 140);
INSERT INTO core.thesaurus_desc_plot VALUES ('Selective felling', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-FN1', 141);
INSERT INTO core.thesaurus_desc_plot VALUES ('Clear felling', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-FN2', 142);
INSERT INTO core.thesaurus_desc_plot VALUES ('Plantation forestry', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-FP', 143);
INSERT INTO core.thesaurus_desc_plot VALUES ('H = Animal husbandry', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-H', 144);
INSERT INTO core.thesaurus_desc_plot VALUES ('Extensive grazing', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HE', 145);
INSERT INTO core.thesaurus_desc_plot VALUES ('Nomadism', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HE1', 146);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-nomadism', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HE2', 147);
INSERT INTO core.thesaurus_desc_plot VALUES ('Ranching', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HE3', 148);
INSERT INTO core.thesaurus_desc_plot VALUES ('Intensive grazing', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HI', 149);
INSERT INTO core.thesaurus_desc_plot VALUES ('Animal production', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HI1', 150);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dairying', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-HI2', 151);
INSERT INTO core.thesaurus_desc_plot VALUES ('M = Mixed farming', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-M', 152);
INSERT INTO core.thesaurus_desc_plot VALUES ('Agroforestry', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-MF', 153);
INSERT INTO core.thesaurus_desc_plot VALUES ('Agropastoralism', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-MP', 154);
INSERT INTO core.thesaurus_desc_plot VALUES ('Other land uses', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-Oi', 155);
INSERT INTO core.thesaurus_desc_plot VALUES ('P = Nature protection', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-P', 156);
INSERT INTO core.thesaurus_desc_plot VALUES ('Degradation control', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PD', 157);
INSERT INTO core.thesaurus_desc_plot VALUES ('Without interference', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PD1', 158);
INSERT INTO core.thesaurus_desc_plot VALUES ('With interference', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PD2', 159);
INSERT INTO core.thesaurus_desc_plot VALUES ('Nature and game preservation', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PN', 160);
INSERT INTO core.thesaurus_desc_plot VALUES ('Reserves', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PN1', 161);
INSERT INTO core.thesaurus_desc_plot VALUES ('Parks', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PN2', 162);
INSERT INTO core.thesaurus_desc_plot VALUES ('Wildlife management', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-PN3', 163);
INSERT INTO core.thesaurus_desc_plot VALUES ('S = Settlement, industry', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-S', 164);
INSERT INTO core.thesaurus_desc_plot VALUES ('Recreational use', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-SC', 165);
INSERT INTO core.thesaurus_desc_plot VALUES ('Disposal sites', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-SD', 166);
INSERT INTO core.thesaurus_desc_plot VALUES ('Industrial use', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-SI', 167);
INSERT INTO core.thesaurus_desc_plot VALUES ('Residential use', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-SR', 168);
INSERT INTO core.thesaurus_desc_plot VALUES ('Transport', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-ST', 169);
INSERT INTO core.thesaurus_desc_plot VALUES ('Excavations', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-SX', 170);
INSERT INTO core.thesaurus_desc_plot VALUES ('Not used and not managed', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-U', 171);
INSERT INTO core.thesaurus_desc_plot VALUES ('Military area', 'http://w3id.org/glosis/model/codelists/landUseClassValueCode-Y', 172);
INSERT INTO core.thesaurus_desc_plot VALUES ('Cuesta-shaped', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-CU', 173);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dome-shaped', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-DO', 174);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dune-shaped', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-DU', 175);
INSERT INTO core.thesaurus_desc_plot VALUES ('With intermontane plains (occupying > 15%) ', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-IM', 176);
INSERT INTO core.thesaurus_desc_plot VALUES ('Inselberg covered (occupying > 1% of level land) ', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-IN', 177);
INSERT INTO core.thesaurus_desc_plot VALUES ('Strong karst', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-KA', 178);
INSERT INTO core.thesaurus_desc_plot VALUES ('Ridged ', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-RI', 179);
INSERT INTO core.thesaurus_desc_plot VALUES ('Terraced', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-TE', 180);
INSERT INTO core.thesaurus_desc_plot VALUES ('With wetlands (occupying > 15%)', 'http://w3id.org/glosis/model/codelists/landformComplexValueCode-WE', 181);
INSERT INTO core.thesaurus_desc_plot VALUES ('igneous rock', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-I', 182);
INSERT INTO core.thesaurus_desc_plot VALUES ('acid igneous', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IA', 183);
INSERT INTO core.thesaurus_desc_plot VALUES ('diorite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IA1', 184);
INSERT INTO core.thesaurus_desc_plot VALUES ('grano-diorite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IA2', 185);
INSERT INTO core.thesaurus_desc_plot VALUES ('quartz-diorite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IA3', 186);
INSERT INTO core.thesaurus_desc_plot VALUES ('rhyolite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IA4', 187);
INSERT INTO core.thesaurus_desc_plot VALUES ('basic igneous', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IB', 188);
INSERT INTO core.thesaurus_desc_plot VALUES ('gabbro', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IB1', 189);
INSERT INTO core.thesaurus_desc_plot VALUES ('basalt', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IB2', 190);
INSERT INTO core.thesaurus_desc_plot VALUES ('dolerite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IB3', 191);
INSERT INTO core.thesaurus_desc_plot VALUES ('intermediate igneous', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-II', 192);
INSERT INTO core.thesaurus_desc_plot VALUES ('andesite, trachyte, phonolite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-II1', 193);
INSERT INTO core.thesaurus_desc_plot VALUES ('diorite-syenite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-II2', 194);
INSERT INTO core.thesaurus_desc_plot VALUES ('pyroclastic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IP', 195);
INSERT INTO core.thesaurus_desc_plot VALUES ('tuff, tuffite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IP1', 196);
INSERT INTO core.thesaurus_desc_plot VALUES ('volcanic scoria/breccia', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IP2', 197);
INSERT INTO core.thesaurus_desc_plot VALUES ('volcanic ash', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IP3', 198);
INSERT INTO core.thesaurus_desc_plot VALUES ('ignimbrite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IP4', 199);
INSERT INTO core.thesaurus_desc_plot VALUES ('ultrabasic igneous', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IU', 200);
INSERT INTO core.thesaurus_desc_plot VALUES ('peridotite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IU1', 201);
INSERT INTO core.thesaurus_desc_plot VALUES ('pyroxenite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IU2', 202);
INSERT INTO core.thesaurus_desc_plot VALUES ('ilmenite, magnetite, ironstone, serpentine', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-IU3', 203);
INSERT INTO core.thesaurus_desc_plot VALUES ('metamorphic rock', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-M', 204);
INSERT INTO core.thesaurus_desc_plot VALUES ('acid metamorphic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MA', 205);
INSERT INTO core.thesaurus_desc_plot VALUES ('quartzite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MA1', 206);
INSERT INTO core.thesaurus_desc_plot VALUES ('gneiss, migmatite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MA2', 207);
INSERT INTO core.thesaurus_desc_plot VALUES ('slate, phyllite (pelitic rocks)', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MA3', 208);
INSERT INTO core.thesaurus_desc_plot VALUES ('schist', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MA4', 209);
INSERT INTO core.thesaurus_desc_plot VALUES ('basic metamorphic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB', 210);
INSERT INTO core.thesaurus_desc_plot VALUES ('slate, phyllite (pelitic rocks)', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB1', 211);
INSERT INTO core.thesaurus_desc_plot VALUES ('(green)schist', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB2', 212);
INSERT INTO core.thesaurus_desc_plot VALUES ('gneiss rich in Fe–Mg minerals', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB3', 213);
INSERT INTO core.thesaurus_desc_plot VALUES ('metamorphic limestone (marble)', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB4', 214);
INSERT INTO core.thesaurus_desc_plot VALUES ('amphibolite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB5', 215);
INSERT INTO core.thesaurus_desc_plot VALUES ('eclogite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MB6', 216);
INSERT INTO core.thesaurus_desc_plot VALUES ('ultrabasic metamorphic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MU', 217);
INSERT INTO core.thesaurus_desc_plot VALUES ('serpentinite, greenstone', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-MU1', 218);
INSERT INTO core.thesaurus_desc_plot VALUES ('sedimentary rock (consolidated)', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-S', 219);
INSERT INTO core.thesaurus_desc_plot VALUES ('clastic sediments', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC', 220);
INSERT INTO core.thesaurus_desc_plot VALUES ('conglomerate, breccia', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC1', 221);
INSERT INTO core.thesaurus_desc_plot VALUES ('sandstone, greywacke, arkose', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC2', 222);
INSERT INTO core.thesaurus_desc_plot VALUES ('silt-, mud-, claystone', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC3', 223);
INSERT INTO core.thesaurus_desc_plot VALUES ('ironstone', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SC5', 225);
INSERT INTO core.thesaurus_desc_plot VALUES ('evaporites', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SE', 226);
INSERT INTO core.thesaurus_desc_plot VALUES ('anhydrite, gypsum', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SE1', 227);
INSERT INTO core.thesaurus_desc_plot VALUES ('halite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SE2', 228);
INSERT INTO core.thesaurus_desc_plot VALUES ('carbonatic, organic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SO', 229);
INSERT INTO core.thesaurus_desc_plot VALUES ('limestone, other carbonate rock', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SO1', 230);
INSERT INTO core.thesaurus_desc_plot VALUES ('marl and other mixtures', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SO2', 231);
INSERT INTO core.thesaurus_desc_plot VALUES ('coals, bitumen and related rocks', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-SO3', 232);
INSERT INTO core.thesaurus_desc_plot VALUES ('sedimentary rock (unconsolidated)', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-U', 233);
INSERT INTO core.thesaurus_desc_plot VALUES ('anthropogenic/technogenic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UA', 234);
INSERT INTO core.thesaurus_desc_plot VALUES ('redeposited natural material', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UA1', 235);
INSERT INTO core.thesaurus_desc_plot VALUES ('industrial/artisanal deposits', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UA2', 236);
INSERT INTO core.thesaurus_desc_plot VALUES ('colluvial', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UC', 237);
INSERT INTO core.thesaurus_desc_plot VALUES ('slope deposits', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UC1', 238);
INSERT INTO core.thesaurus_desc_plot VALUES ('lahar', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UC2', 239);
INSERT INTO core.thesaurus_desc_plot VALUES ('eolian', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UE', 240);
INSERT INTO core.thesaurus_desc_plot VALUES ('loess', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UE1', 241);
INSERT INTO core.thesaurus_desc_plot VALUES ('sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UE2', 242);
INSERT INTO core.thesaurus_desc_plot VALUES ('fluvial', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UF', 243);
INSERT INTO core.thesaurus_desc_plot VALUES ('sand and gravel', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UF1', 244);
INSERT INTO core.thesaurus_desc_plot VALUES ('clay, silt and loam', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UF2', 245);
INSERT INTO core.thesaurus_desc_plot VALUES ('glacial', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UG', 246);
INSERT INTO core.thesaurus_desc_plot VALUES ('moraine', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UG1', 247);
INSERT INTO core.thesaurus_desc_plot VALUES ('UG2 glacio-fluvial sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UG2', 248);
INSERT INTO core.thesaurus_desc_plot VALUES ('UG3 glacio-fluvial gravel', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UG3', 249);
INSERT INTO core.thesaurus_desc_plot VALUES ('kryogenic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UK', 250);
INSERT INTO core.thesaurus_desc_plot VALUES ('periglacial rock debris', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UK1', 251);
INSERT INTO core.thesaurus_desc_plot VALUES ('periglacial solifluction layer', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UK2', 252);
INSERT INTO core.thesaurus_desc_plot VALUES ('lacustrine', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UL', 253);
INSERT INTO core.thesaurus_desc_plot VALUES ('sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UL1', 254);
INSERT INTO core.thesaurus_desc_plot VALUES ('silt and clay', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UL2', 255);
INSERT INTO core.thesaurus_desc_plot VALUES ('marine, estuarine', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UM', 256);
INSERT INTO core.thesaurus_desc_plot VALUES ('clay and silt', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UM2', 258);
INSERT INTO core.thesaurus_desc_plot VALUES ('organic', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UO', 259);
INSERT INTO core.thesaurus_desc_plot VALUES ('rainwater-fed moor peat', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UO1', 260);
INSERT INTO core.thesaurus_desc_plot VALUES ('groundwater-fed bog peat', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UO2', 261);
INSERT INTO core.thesaurus_desc_plot VALUES ('weathered residuum', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UR', 262);
INSERT INTO core.thesaurus_desc_plot VALUES ('bauxite, laterite', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UR1', 263);
INSERT INTO core.thesaurus_desc_plot VALUES ('unspecified deposits', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU', 264);
INSERT INTO core.thesaurus_desc_plot VALUES ('clay', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU1', 265);
INSERT INTO core.thesaurus_desc_plot VALUES ('loam and silt', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU2', 266);
INSERT INTO core.thesaurus_desc_plot VALUES ('sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU3', 267);
INSERT INTO core.thesaurus_desc_plot VALUES ('gravelly sand', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU4', 268);
INSERT INTO core.thesaurus_desc_plot VALUES ('gravel, broken rock', 'http://w3id.org/glosis/model/codelists/lithologyValueCode-UU5', 269);
INSERT INTO core.thesaurus_desc_plot VALUES ('level land ', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-L', 270);
INSERT INTO core.thesaurus_desc_plot VALUES ('depression', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-LD', 271);
INSERT INTO core.thesaurus_desc_plot VALUES ('plateau', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-LL', 272);
INSERT INTO core.thesaurus_desc_plot VALUES ('plain', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-LP', 273);
INSERT INTO core.thesaurus_desc_plot VALUES ('valley floor', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-LV', 274);
INSERT INTO core.thesaurus_desc_plot VALUES ('sloping land ', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-S', 275);
INSERT INTO core.thesaurus_desc_plot VALUES ('medium-gradient escarpment zone', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-SE', 276);
INSERT INTO core.thesaurus_desc_plot VALUES ('medium-gradient hill', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-SH', 277);
INSERT INTO core.thesaurus_desc_plot VALUES ('medium-gradient mountain', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-SM', 278);
INSERT INTO core.thesaurus_desc_plot VALUES ('dissected plain', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-SP', 279);
INSERT INTO core.thesaurus_desc_plot VALUES ('medium-gradient valley', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-SV', 280);
INSERT INTO core.thesaurus_desc_plot VALUES ('steep land', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-T', 281);
INSERT INTO core.thesaurus_desc_plot VALUES ('high-gradient escarpment zone', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-TE', 282);
INSERT INTO core.thesaurus_desc_plot VALUES ('high-gradient hill', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-TH', 283);
INSERT INTO core.thesaurus_desc_plot VALUES ('high-gradient mountain', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-TM', 284);
INSERT INTO core.thesaurus_desc_plot VALUES ('high-gradient valley', 'http://w3id.org/glosis/model/codelists/majorLandFormValueCode-TV', 285);
INSERT INTO core.thesaurus_desc_plot VALUES ('Bottom (drainage line)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-BOdl', 286);
INSERT INTO core.thesaurus_desc_plot VALUES ('Bottom (flat)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-BOf', 287);
INSERT INTO core.thesaurus_desc_plot VALUES ('Crest (summit)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-CR', 288);
INSERT INTO core.thesaurus_desc_plot VALUES ('Higher part (rise)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-HI', 289);
INSERT INTO core.thesaurus_desc_plot VALUES ('Intermediate part (talf)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-IN', 290);
INSERT INTO core.thesaurus_desc_plot VALUES ('Lower part (and dip)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-LO', 291);
INSERT INTO core.thesaurus_desc_plot VALUES ('Lower slope (foot slope)', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-LS', 292);
INSERT INTO core.thesaurus_desc_plot VALUES ('Middle slope (back slope) ', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-MS', 293);
INSERT INTO core.thesaurus_desc_plot VALUES ('Toe slope', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-TS', 294);
INSERT INTO core.thesaurus_desc_plot VALUES ('Upper slope (shoulder) ', 'http://w3id.org/glosis/model/codelists/physiographyValueCode-UP', 295);
INSERT INTO core.thesaurus_desc_plot VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-A', 296);
INSERT INTO core.thesaurus_desc_plot VALUES ('Common', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-C', 297);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-D', 298);
INSERT INTO core.thesaurus_desc_plot VALUES ('Few', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-F', 299);
INSERT INTO core.thesaurus_desc_plot VALUES ('Many', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-M', 300);
INSERT INTO core.thesaurus_desc_plot VALUES ('None', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-N', 301);
INSERT INTO core.thesaurus_desc_plot VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/rockOutcropsCoverValueCode-V', 302);
INSERT INTO core.thesaurus_desc_plot VALUES ('> 50', 'http://w3id.org/glosis/model/codelists/rockOutcropsDistanceValueCode-1', 303);
INSERT INTO core.thesaurus_desc_plot VALUES ('20–50', 'http://w3id.org/glosis/model/codelists/rockOutcropsDistanceValueCode-2', 304);
INSERT INTO core.thesaurus_desc_plot VALUES ('5–20', 'http://w3id.org/glosis/model/codelists/rockOutcropsDistanceValueCode-3', 305);
INSERT INTO core.thesaurus_desc_plot VALUES ('2–5', 'http://w3id.org/glosis/model/codelists/rockOutcropsDistanceValueCode-4', 306);
INSERT INTO core.thesaurus_desc_plot VALUES ('< 2', 'http://w3id.org/glosis/model/codelists/rockOutcropsDistanceValueCode-5', 307);
INSERT INTO core.thesaurus_desc_plot VALUES ('concave', 'http://w3id.org/glosis/model/codelists/slopeFormValueCode-C', 308);
INSERT INTO core.thesaurus_desc_plot VALUES ('straight', 'http://w3id.org/glosis/model/codelists/slopeFormValueCode-S', 309);
INSERT INTO core.thesaurus_desc_plot VALUES ('terraced', 'http://w3id.org/glosis/model/codelists/slopeFormValueCode-T', 310);
INSERT INTO core.thesaurus_desc_plot VALUES ('convex', 'http://w3id.org/glosis/model/codelists/slopeFormValueCode-V', 311);
INSERT INTO core.thesaurus_desc_plot VALUES ('complex (irregular)', 'http://w3id.org/glosis/model/codelists/slopeFormValueCode-X', 312);
INSERT INTO core.thesaurus_desc_plot VALUES ('Flat', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-01', 313);
INSERT INTO core.thesaurus_desc_plot VALUES ('Level', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-02', 314);
INSERT INTO core.thesaurus_desc_plot VALUES ('Nearly level', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-03', 315);
INSERT INTO core.thesaurus_desc_plot VALUES ('Very gently sloping ', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-04', 316);
INSERT INTO core.thesaurus_desc_plot VALUES ('Gently sloping', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-05', 317);
INSERT INTO core.thesaurus_desc_plot VALUES ('Sloping', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-06', 318);
INSERT INTO core.thesaurus_desc_plot VALUES ('Strongly sloping', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-07', 319);
INSERT INTO core.thesaurus_desc_plot VALUES ('Moderately steep', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-08', 320);
INSERT INTO core.thesaurus_desc_plot VALUES ('Steep', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-09', 321);
INSERT INTO core.thesaurus_desc_plot VALUES ('Very steep', 'http://w3id.org/glosis/model/codelists/slopeGradientClassValueCode-10', 322);
INSERT INTO core.thesaurus_desc_plot VALUES ('CC', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-CC', 323);
INSERT INTO core.thesaurus_desc_plot VALUES ('CS', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-CS', 324);
INSERT INTO core.thesaurus_desc_plot VALUES ('CV', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-CV', 325);
INSERT INTO core.thesaurus_desc_plot VALUES ('SC', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-SC', 326);
INSERT INTO core.thesaurus_desc_plot VALUES ('SV', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-SV', 328);
INSERT INTO core.thesaurus_desc_plot VALUES ('VC', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-VC', 329);
INSERT INTO core.thesaurus_desc_plot VALUES ('VS', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-VS', 330);
INSERT INTO core.thesaurus_desc_plot VALUES ('VV', 'http://w3id.org/glosis/model/codelists/slopePathwaysValueCode-VV', 331);
INSERT INTO core.thesaurus_desc_plot VALUES ('Holocene anthropogeomorphic', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-Ha', 332);
INSERT INTO core.thesaurus_desc_plot VALUES ('Holocene natural', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-Hn', 333);
INSERT INTO core.thesaurus_desc_plot VALUES ('Older, pre-Tertiary land surfaces', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-O', 334);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tertiary land surfaces', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-T', 335);
INSERT INTO core.thesaurus_desc_plot VALUES ('Young anthropogeomorphic', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-Ya', 336);
INSERT INTO core.thesaurus_desc_plot VALUES ('Young natural', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-Yn', 337);
INSERT INTO core.thesaurus_desc_plot VALUES ('Late Pleistocene, without periglacial influence.', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-lPf', 338);
INSERT INTO core.thesaurus_desc_plot VALUES ('Late Pleistocene, ice covered', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-lPi', 339);
INSERT INTO core.thesaurus_desc_plot VALUES ('Late Pleistocene, periglacial', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-lPp', 340);
INSERT INTO core.thesaurus_desc_plot VALUES ('Older Pleistocene, without periglacial influence.', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-oPf', 341);
INSERT INTO core.thesaurus_desc_plot VALUES ('Older Pleistocene, ice covered', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-oPi', 342);
INSERT INTO core.thesaurus_desc_plot VALUES ('Older Pleistocene, with periglacial influence', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-oPp', 343);
INSERT INTO core.thesaurus_desc_plot VALUES ('Very young anthropogeomorphic', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-vYa', 344);
INSERT INTO core.thesaurus_desc_plot VALUES ('Very young natural', 'http://w3id.org/glosis/model/codelists/surfaceAgeValueCode-vYn', 345);
INSERT INTO core.thesaurus_desc_plot VALUES ('Groundwater-fed bog peat', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-B', 346);
INSERT INTO core.thesaurus_desc_plot VALUES ('Dwarf shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-D', 347);
INSERT INTO core.thesaurus_desc_plot VALUES ('Deciduous dwarf shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-DD', 348);
INSERT INTO core.thesaurus_desc_plot VALUES ('Evergreen dwarf shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-DE', 349);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-deciduous dwarf shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-DS', 350);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tundra', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-DT', 351);
INSERT INTO core.thesaurus_desc_plot VALUES ('Xermomorphic dwarf shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-DX', 352);
INSERT INTO core.thesaurus_desc_plot VALUES ('Closed forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-F', 353);
INSERT INTO core.thesaurus_desc_plot VALUES ('Coniferous forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-FC', 354);
INSERT INTO core.thesaurus_desc_plot VALUES ('Deciduous forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-FD', 355);
INSERT INTO core.thesaurus_desc_plot VALUES ('Evergreen broad-leaved forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-FE', 356);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-deciduous forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-FS', 357);
INSERT INTO core.thesaurus_desc_plot VALUES ('Xeromorphic forest', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-FX', 358);
INSERT INTO core.thesaurus_desc_plot VALUES ('Herbaceous', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-H', 359);
INSERT INTO core.thesaurus_desc_plot VALUES ('Forb', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-HF', 360);
INSERT INTO core.thesaurus_desc_plot VALUES ('Medium grassland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-HM', 361);
INSERT INTO core.thesaurus_desc_plot VALUES ('Short grassland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-HS', 362);
INSERT INTO core.thesaurus_desc_plot VALUES ('Tall grassland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-HT', 363);
INSERT INTO core.thesaurus_desc_plot VALUES ('Rainwater-fed moor peat', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-M', 364);
INSERT INTO core.thesaurus_desc_plot VALUES ('Shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-S', 365);
INSERT INTO core.thesaurus_desc_plot VALUES ('Deciduous shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-SD', 366);
INSERT INTO core.thesaurus_desc_plot VALUES ('Evergreen shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-SE', 367);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-deciduous shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-SS', 368);
INSERT INTO core.thesaurus_desc_plot VALUES ('Xeromorphic shrub', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-SX', 369);
INSERT INTO core.thesaurus_desc_plot VALUES ('Woodland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-W', 370);
INSERT INTO core.thesaurus_desc_plot VALUES ('Deciduous woodland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-WD', 371);
INSERT INTO core.thesaurus_desc_plot VALUES ('Evergreen woodland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-WE', 372);
INSERT INTO core.thesaurus_desc_plot VALUES ('Semi-deciduous woodland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-WS', 373);
INSERT INTO core.thesaurus_desc_plot VALUES ('Xeromorphic woodland', 'http://w3id.org/glosis/model/codelists/vegetationClassValueCode-WX', 374);
INSERT INTO core.thesaurus_desc_plot VALUES ('overcast', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-OV', 375);
INSERT INTO core.thesaurus_desc_plot VALUES ('partly cloudy', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-PC', 376);
INSERT INTO core.thesaurus_desc_plot VALUES ('rain', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-RA', 377);
INSERT INTO core.thesaurus_desc_plot VALUES ('sleet', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-SL', 378);
INSERT INTO core.thesaurus_desc_plot VALUES ('snow', 'http://w3id.org/glosis/model/codelists/weatherConditionsValueCode-SN', 379);


--
-- TOC entry 5310 (class 0 OID 23079497)
-- Dependencies: 248
-- Data for Name: thesaurus_desc_profile; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.thesaurus_desc_profile VALUES ('Reference profile description', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-1', 1);
INSERT INTO core.thesaurus_desc_profile VALUES ('Reference profile description - no sampling', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-1.1', 2);
INSERT INTO core.thesaurus_desc_profile VALUES ('Routine profile description ', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-2', 3);
INSERT INTO core.thesaurus_desc_profile VALUES ('Routine profile description - no sampling', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-2.1', 4);
INSERT INTO core.thesaurus_desc_profile VALUES ('Incomplete description ', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-3', 5);
INSERT INTO core.thesaurus_desc_profile VALUES ('Incomplete description - no sampling', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-3.1', 6);
INSERT INTO core.thesaurus_desc_profile VALUES ('Soil augering description ', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-4', 7);
INSERT INTO core.thesaurus_desc_profile VALUES ('Soil augering description - no sampling', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-4.1', 8);
INSERT INTO core.thesaurus_desc_profile VALUES ('Other descriptions ', 'http://w3id.org/glosis/model/codelists/profileDescriptionStatusValueCode-5', 9);


--
-- TOC entry 5331 (class 0 OID 23079955)
-- Dependencies: 269
-- Data for Name: thesaurus_desc_specimen; Type: TABLE DATA; Schema: core; Owner: -
--



--
-- TOC entry 5308 (class 0 OID 23079473)
-- Dependencies: 246
-- Data for Name: thesaurus_desc_surface; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.thesaurus_desc_surface VALUES ('Deep 10–20', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-D', 1);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium 2–10', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-M', 2);
INSERT INTO core.thesaurus_desc_surface VALUES ('Surface < 2', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-S', 3);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very deep > 20', 'http://w3id.org/glosis/model/codelists/cracksDepthValueCode-V', 4);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very closely spaced < 0.2', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-C', 5);
INSERT INTO core.thesaurus_desc_surface VALUES ('Closely spaced 0.2–0.5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-D', 6);
INSERT INTO core.thesaurus_desc_surface VALUES ('Moderately widely spaced 0.5–2', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-M', 7);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very widely spaced > 5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-V', 8);
INSERT INTO core.thesaurus_desc_surface VALUES ('Widely spaced 2–5', 'http://w3id.org/glosis/model/codelists/cracksDistanceValueCode-W', 9);
INSERT INTO core.thesaurus_desc_surface VALUES ('Extremely wide > 10cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-E', 10);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fine < 1cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-F', 11);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium 1cm–2cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-M', 12);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very wide 5cm–10cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-V', 13);
INSERT INTO core.thesaurus_desc_surface VALUES ('Wide 2cm–5cm', 'http://w3id.org/glosis/model/codelists/cracksWidthValueCode-W', 14);
INSERT INTO core.thesaurus_desc_surface VALUES ('Abundant', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-A', 15);
INSERT INTO core.thesaurus_desc_surface VALUES ('Common ', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-C', 16);
INSERT INTO core.thesaurus_desc_surface VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-D', 17);
INSERT INTO core.thesaurus_desc_surface VALUES ('Few', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-F', 18);
INSERT INTO core.thesaurus_desc_surface VALUES ('Many', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-M', 19);
INSERT INTO core.thesaurus_desc_surface VALUES ('None', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-N', 20);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/fragmentCoverValueCode-V', 21);
INSERT INTO core.thesaurus_desc_surface VALUES ('Boulders', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-B', 22);
INSERT INTO core.thesaurus_desc_surface VALUES ('Coarse gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-C', 23);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fine gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-F', 24);
INSERT INTO core.thesaurus_desc_surface VALUES ('Large boulders', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-L', 25);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium gravel', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-M', 26);
INSERT INTO core.thesaurus_desc_surface VALUES ('Stones', 'http://w3id.org/glosis/model/codelists/fragmentSizeValueCode-S', 27);
INSERT INTO core.thesaurus_desc_surface VALUES ('Abundant ', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-A', 28);
INSERT INTO core.thesaurus_desc_surface VALUES ('Common', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-C', 29);
INSERT INTO core.thesaurus_desc_surface VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-D', 30);
INSERT INTO core.thesaurus_desc_surface VALUES ('Few', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-F', 31);
INSERT INTO core.thesaurus_desc_surface VALUES ('Many', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-M', 32);
INSERT INTO core.thesaurus_desc_surface VALUES ('None', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-N', 33);
INSERT INTO core.thesaurus_desc_surface VALUES ('Stone line', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-S', 34);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very few', 'http://w3id.org/glosis/model/codelists/rockAbundanceValueCode-V', 35);
INSERT INTO core.thesaurus_desc_surface VALUES ('Angular', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-A', 36);
INSERT INTO core.thesaurus_desc_surface VALUES ('Flat', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-F', 37);
INSERT INTO core.thesaurus_desc_surface VALUES ('Rounded', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-R', 38);
INSERT INTO core.thesaurus_desc_surface VALUES ('Subrounded', 'http://w3id.org/glosis/model/codelists/rockShapeValueCode-S', 39);
INSERT INTO core.thesaurus_desc_surface VALUES ('Artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-A', 40);
INSERT INTO core.thesaurus_desc_surface VALUES ('Coarse artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AC', 41);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fine artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AF', 42);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AM', 43);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very fine artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-AV', 44);
INSERT INTO core.thesaurus_desc_surface VALUES ('Boulders and large boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-BL', 45);
INSERT INTO core.thesaurus_desc_surface VALUES ('Combination of classes', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-C', 46);
INSERT INTO core.thesaurus_desc_surface VALUES ('Coarse gravel and stones', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-CS', 47);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fine and medium gravel/artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-FM', 48);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium and coarse gravel/artefacts', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-MC', 49);
INSERT INTO core.thesaurus_desc_surface VALUES ('Rock fragments', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-R', 50);
INSERT INTO core.thesaurus_desc_surface VALUES ('Boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RB', 51);
INSERT INTO core.thesaurus_desc_surface VALUES ('Coarse gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RC', 52);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fine gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RF', 53);
INSERT INTO core.thesaurus_desc_surface VALUES ('Large boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RL', 54);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium gravel', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RM', 55);
INSERT INTO core.thesaurus_desc_surface VALUES ('Stones', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-RS', 56);
INSERT INTO core.thesaurus_desc_surface VALUES ('Stones and boulders', 'http://w3id.org/glosis/model/codelists/rockSizeValueCode-SB', 57);
INSERT INTO core.thesaurus_desc_surface VALUES ('None', 'http://w3id.org/glosis/model/codelists/saltCoverValueCode-0', 58);
INSERT INTO core.thesaurus_desc_surface VALUES ('Low', 'http://w3id.org/glosis/model/codelists/saltCoverValueCode-1', 59);
INSERT INTO core.thesaurus_desc_surface VALUES ('Moderate', 'http://w3id.org/glosis/model/codelists/saltCoverValueCode-2', 60);
INSERT INTO core.thesaurus_desc_surface VALUES ('High', 'http://w3id.org/glosis/model/codelists/saltCoverValueCode-3', 61);
INSERT INTO core.thesaurus_desc_surface VALUES ('Dominant', 'http://w3id.org/glosis/model/codelists/saltCoverValueCode-4', 62);
INSERT INTO core.thesaurus_desc_surface VALUES ('Thick', 'http://w3id.org/glosis/model/codelists/saltThicknessValueCode-C', 63);
INSERT INTO core.thesaurus_desc_surface VALUES ('Thin', 'http://w3id.org/glosis/model/codelists/saltThicknessValueCode-F', 64);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/saltThicknessValueCode-M', 65);
INSERT INTO core.thesaurus_desc_surface VALUES ('None', 'http://w3id.org/glosis/model/codelists/saltThicknessValueCode-N', 66);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very thick', 'http://w3id.org/glosis/model/codelists/saltThicknessValueCode-V', 67);
INSERT INTO core.thesaurus_desc_surface VALUES ('Extremely hard', 'http://w3id.org/glosis/model/codelists/sealingConsistenceValueCode-E', 68);
INSERT INTO core.thesaurus_desc_surface VALUES ('Hard', 'http://w3id.org/glosis/model/codelists/sealingConsistenceValueCode-H', 69);
INSERT INTO core.thesaurus_desc_surface VALUES ('Slightly hard', 'http://w3id.org/glosis/model/codelists/sealingConsistenceValueCode-S', 70);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very hard', 'http://w3id.org/glosis/model/codelists/sealingConsistenceValueCode-V', 71);
INSERT INTO core.thesaurus_desc_surface VALUES ('Thick', 'http://w3id.org/glosis/model/codelists/sealingThicknessValueCode-C', 72);
INSERT INTO core.thesaurus_desc_surface VALUES ('Thin', 'http://w3id.org/glosis/model/codelists/sealingThicknessValueCode-F', 73);
INSERT INTO core.thesaurus_desc_surface VALUES ('Medium', 'http://w3id.org/glosis/model/codelists/sealingThicknessValueCode-M', 74);
INSERT INTO core.thesaurus_desc_surface VALUES ('None', 'http://w3id.org/glosis/model/codelists/sealingThicknessValueCode-N', 75);
INSERT INTO core.thesaurus_desc_surface VALUES ('Very thick', 'http://w3id.org/glosis/model/codelists/sealingThicknessValueCode-V', 76);
INSERT INTO core.thesaurus_desc_surface VALUES ('Fresh or slightly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-F', 77);
INSERT INTO core.thesaurus_desc_surface VALUES ('Strongly weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-S', 78);
INSERT INTO core.thesaurus_desc_surface VALUES ('Weathered', 'http://w3id.org/glosis/model/codelists/weatheringValueCode-W', 79);


--
-- TOC entry 5316 (class 0 OID 23079609)
-- Dependencies: 254
-- Data for Name: unit_of_measure; Type: TABLE DATA; Schema: core; Owner: -
--

INSERT INTO core.unit_of_measure VALUES ('Centimetre Per Hour', 'http://qudt.org/vocab/unit/CentiM-PER-HR', 8);
INSERT INTO core.unit_of_measure VALUES ('Percent', 'http://qudt.org/vocab/unit/PERCENT', 9);
INSERT INTO core.unit_of_measure VALUES ('Centimole per kilogram', 'http://qudt.org/vocab/unit/CentiMOL-PER-KiloGM', 10);
INSERT INTO core.unit_of_measure VALUES ('decisiemens per metre', 'http://qudt.org/vocab/unit/DeciS-PER-M', 11);
INSERT INTO core.unit_of_measure VALUES ('Gram Per Kilogram', 'http://qudt.org/vocab/unit/GM-PER-KiloGM', 12);
INSERT INTO core.unit_of_measure VALUES ('Kilogram Per Cubic Decimetre', 'http://qudt.org/vocab/unit/KiloGM-PER-DeciM3', 13);
INSERT INTO core.unit_of_measure VALUES ('Acidity', 'http://qudt.org/vocab/unit/PH', 14);
INSERT INTO core.unit_of_measure VALUES ('Centimol Per Litre', 'http://w3id.org/glosis/model/unit/CentiMOL-PER-L', 15);
INSERT INTO core.unit_of_measure VALUES ('Gram Per Hectogram', 'http://w3id.org/glosis/model/unit/GM-PER-HectoGM', 16);
INSERT INTO core.unit_of_measure VALUES ('Cubic metre per one hundred cubic metre', 'http://w3id.org/glosis/model/unit/M3-PER-HundredM3', 17);


--
-- TOC entry 5293 (class 0 OID 23078153)
-- Dependencies: 226
-- Data for Name: current; Type: TABLE DATA; Schema: graphile_migrate; Owner: -
--



--
-- TOC entry 5292 (class 0 OID 23078137)
-- Dependencies: 225
-- Data for Name: migrations; Type: TABLE DATA; Schema: graphile_migrate; Owner: -
--

INSERT INTO graphile_migrate.migrations VALUES ('sha1:8f3adf5418f6a8a1c4065f1972d9ef18bb98a2ca', NULL, '000001.sql', '2026-01-18 00:55:32.399878+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:3ff289c28c97d5a6439586ca4b0ed7aa49a876b3', 'sha1:8f3adf5418f6a8a1c4065f1972d9ef18bb98a2ca', '000002.sql', '2026-01-18 00:55:32.400906+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:5170c2cef1301bc025bd87db6083244b0a78d9e6', 'sha1:3ff289c28c97d5a6439586ca4b0ed7aa49a876b3', '000003.sql', '2026-01-18 00:55:32.720684+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:5f0b39346b051a1241bd10b6f8601249c890e77f', 'sha1:5170c2cef1301bc025bd87db6083244b0a78d9e6', '000004.sql', '2026-01-18 00:55:32.723443+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:013ce77c80875a35bd57625ff5b2f653239fa51f', 'sha1:5f0b39346b051a1241bd10b6f8601249c890e77f', '000005.sql', '2026-01-18 00:55:32.725192+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:6d221e634c0cee82c9087bd8fa98cc8fdd8d0717', 'sha1:013ce77c80875a35bd57625ff5b2f653239fa51f', '000006.sql', '2026-01-18 00:55:32.726537+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:21eb696f197d2382b2f32ca939e0c63744407d13', 'sha1:6d221e634c0cee82c9087bd8fa98cc8fdd8d0717', '000007.sql', '2026-01-18 00:55:32.727837+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:7c11261f47530390efbc9708cbde789edbb54fbb', 'sha1:21eb696f197d2382b2f32ca939e0c63744407d13', '000008.sql', '2026-01-18 00:55:32.729371+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:47d4488a16827c121f95b85ae440cc607b8c49ee', 'sha1:7c11261f47530390efbc9708cbde789edbb54fbb', '000010.sql', '2026-01-18 00:55:32.730872+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:9cbc614ce74fde0e4a0c8ee5878074de5bcce423', 'sha1:47d4488a16827c121f95b85ae440cc607b8c49ee', '000011.sql', '2026-01-18 00:55:32.732142+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:c26e4467b186275059bc275272f82f4885bfbfe7', 'sha1:9cbc614ce74fde0e4a0c8ee5878074de5bcce423', '000012.sql', '2026-01-18 00:55:32.733451+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:d6cec89b7ebe9a0943de917059fafa5862174af9', 'sha1:c26e4467b186275059bc275272f82f4885bfbfe7', '000013.sql', '2026-01-18 00:55:32.736484+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:b845aaf9d1e0c5004d5598eb0d76f310f714d137', 'sha1:d6cec89b7ebe9a0943de917059fafa5862174af9', '000014.sql', '2026-01-18 00:55:32.739455+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:89461e95c2364bc1606e190ea185efc7ccd7863e', 'sha1:b845aaf9d1e0c5004d5598eb0d76f310f714d137', '000015.sql', '2026-01-18 00:55:32.74236+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:ea9d98f9093e33ade805c30f00f1a583cf51c4ed', 'sha1:89461e95c2364bc1606e190ea185efc7ccd7863e', '000016.sql', '2026-01-18 00:55:32.744103+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:fd9d2777699ec643268f3e12b835590a0568ae5f', 'sha1:ea9d98f9093e33ade805c30f00f1a583cf51c4ed', '000017.sql', '2026-01-18 00:55:32.745793+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:1415df6697495728de48edf9ab6a080a74e1a98c', 'sha1:fd9d2777699ec643268f3e12b835590a0568ae5f', '000018.sql', '2026-01-18 00:55:32.747921+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:6b396e3c5a3f83de9bde83ad56961c6ee4adb9a8', 'sha1:1415df6697495728de48edf9ab6a080a74e1a98c', '000019.sql', '2026-01-18 00:55:32.752217+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:45fa121afc09bc92ed3559466280676579609808', 'sha1:6b396e3c5a3f83de9bde83ad56961c6ee4adb9a8', '000020.sql', '2026-01-18 00:55:32.755852+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:edbd0b791b8ca3d8f1c4ce64670c1f0d4fdaf5a2', 'sha1:45fa121afc09bc92ed3559466280676579609808', '000021.sql', '2026-01-18 00:55:32.758158+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:cbb91e43842f87195c37b3bc08464a04f7c061b5', 'sha1:edbd0b791b8ca3d8f1c4ce64670c1f0d4fdaf5a2', '000022.sql', '2026-01-18 00:55:32.761584+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:dcab707873885f9817388f6a534b0b0efceebc6c', 'sha1:cbb91e43842f87195c37b3bc08464a04f7c061b5', '000023.sql', '2026-01-18 00:55:32.770807+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:bfeb693624ef99c42e19a63c0330e2e11fa6cc28', 'sha1:dcab707873885f9817388f6a534b0b0efceebc6c', '000024.sql', '2026-01-18 00:55:32.800261+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:c3e801f1045e773aa4d9746208c4fa5917b16cdd', 'sha1:bfeb693624ef99c42e19a63c0330e2e11fa6cc28', '000025.sql', '2026-01-18 00:55:32.801294+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:4967c7d84d9fe40019e443afc28ee23bedda5d86', 'sha1:c3e801f1045e773aa4d9746208c4fa5917b16cdd', '000026.sql', '2026-01-18 00:55:32.802288+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:906d8b08c68a3d23272ffe8856e34075a3732527', 'sha1:4967c7d84d9fe40019e443afc28ee23bedda5d86', '000027.sql', '2026-01-18 00:55:32.809243+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:a504ba67640774cc57014a0fc5df1d7d4d8ce745', 'sha1:906d8b08c68a3d23272ffe8856e34075a3732527', '000028.sql', '2026-01-18 00:55:32.809958+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:dfa6fec946f81c49aec915bfad9e86e64a712f99', 'sha1:a504ba67640774cc57014a0fc5df1d7d4d8ce745', '000029.sql', '2026-01-18 00:55:32.812351+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:07a0ec67b6da94ec8903be6cad135934303d67a1', 'sha1:dfa6fec946f81c49aec915bfad9e86e64a712f99', '000030.sql', '2026-01-18 00:55:32.863836+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:fff32570d3896eaf0d361fb6b9e053caa63aaa67', 'sha1:07a0ec67b6da94ec8903be6cad135934303d67a1', '000031.sql', '2026-01-18 00:55:32.865827+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:3a76d60d831c24215b1b3109f770f81b1fbc1c84', 'sha1:fff32570d3896eaf0d361fb6b9e053caa63aaa67', '000032.sql', '2026-01-18 00:55:32.866912+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:ccbb4754ff05edb22ab65a646b38596a1d46d061', 'sha1:3a76d60d831c24215b1b3109f770f81b1fbc1c84', '000033.sql', '2026-01-18 00:55:32.872345+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:b5c2dc771cb6465ee251fe5074333baff62e5e8f', 'sha1:ccbb4754ff05edb22ab65a646b38596a1d46d061', '000034.sql', '2026-01-18 00:55:32.875629+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:f979f6e6b90faf2561a4fa4924ba4877893f79e6', 'sha1:b5c2dc771cb6465ee251fe5074333baff62e5e8f', '000035.sql', '2026-01-18 00:55:32.878074+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:6e4f9b01affa25f0c88cf558dd2d665091ca29f2', 'sha1:f979f6e6b90faf2561a4fa4924ba4877893f79e6', '000036.sql', '2026-01-18 00:55:32.881303+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:b9d7712ae8e016f3ddad08868ad32b1e040309ad', 'sha1:6e4f9b01affa25f0c88cf558dd2d665091ca29f2', '000037.sql', '2026-01-18 00:55:32.884999+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:31f323326690ed633409553e5173a0748d1635b1', 'sha1:b9d7712ae8e016f3ddad08868ad32b1e040309ad', '000038.sql', '2026-01-18 00:55:32.88692+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:a32a1133975549dea1d85334a15d2d6489b4b2bb', 'sha1:31f323326690ed633409553e5173a0748d1635b1', '000039.sql', '2026-01-18 00:55:32.887698+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:c90680791caaed4a91769aafb1b2a0a58d10fd7c', 'sha1:a32a1133975549dea1d85334a15d2d6489b4b2bb', '000040.sql', '2026-01-18 00:55:32.888485+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:e6cef9fae3d43dc4774cab0183d9a65cadb51970', 'sha1:c90680791caaed4a91769aafb1b2a0a58d10fd7c', '000041.sql', '2026-01-18 00:55:32.890676+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:fdcb8ef6da91b6e93f8e56a91d478d3fe1e54bc7', 'sha1:e6cef9fae3d43dc4774cab0183d9a65cadb51970', '000042.sql', '2026-01-18 00:55:32.891717+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:c8c8b36b4619213ef513f7a6a223cd2eb9febc72', 'sha1:fdcb8ef6da91b6e93f8e56a91d478d3fe1e54bc7', '000043.sql', '2026-01-18 00:55:32.892439+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:1b896ce5aa7d9b8b65863184d3fe5cc448d048d0', 'sha1:c8c8b36b4619213ef513f7a6a223cd2eb9febc72', '000044.sql', '2026-01-18 00:55:32.893112+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:a2b72c713a38b5b8ede960a596a6b0bd2b042a06', 'sha1:1b896ce5aa7d9b8b65863184d3fe5cc448d048d0', '000045.sql', '2026-01-18 00:55:32.894492+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:fc7caa8cf0122b9e4ca8d0569a8569590fca8824', 'sha1:a2b72c713a38b5b8ede960a596a6b0bd2b042a06', '000046.sql', '2026-01-18 00:55:32.895549+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:a23ee981beee66cda248a8c50805d23a841bc0ec', 'sha1:fc7caa8cf0122b9e4ca8d0569a8569590fca8824', '000047.sql', '2026-01-18 00:55:32.898862+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:b1bbaddedb0cf78e301de48918813c510238f3fe', 'sha1:a23ee981beee66cda248a8c50805d23a841bc0ec', '000048.sql', '2026-01-18 00:55:32.963515+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:70e638b6587543aaf5f6869a501feaef9292ce32', 'sha1:b1bbaddedb0cf78e301de48918813c510238f3fe', '000049.sql', '2026-01-18 00:55:32.966982+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:f2adbfcb10b7e36e34bd50d9fab542c670403701', 'sha1:70e638b6587543aaf5f6869a501feaef9292ce32', '000050.sql', '2026-01-18 00:55:32.968298+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:c9c275d05d2129663e981695311fee2c58122384', 'sha1:f2adbfcb10b7e36e34bd50d9fab542c670403701', '000051.sql', '2026-01-18 00:55:32.970282+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:cfc109c5a85c2664107aab6a7e7fd582df1932bf', 'sha1:c9c275d05d2129663e981695311fee2c58122384', '000052.sql', '2026-01-18 00:55:32.971494+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:449d6d8c4eecc91a271400cb54e4dc5600b0a5c0', 'sha1:cfc109c5a85c2664107aab6a7e7fd582df1932bf', '000053.sql', '2026-01-18 00:55:32.974193+00');
INSERT INTO graphile_migrate.migrations VALUES ('sha1:7d05b0a4ced079cc5f4fe1a6ecf75eb6984f6147', 'sha1:449d6d8c4eecc91a271400cb54e4dc5600b0a5c0', '000054.sql', '2026-01-18 00:55:32.994594+00');


--
-- TOC entry 5337 (class 0 OID 23080091)
-- Dependencies: 275
-- Data for Name: address; Type: TABLE DATA; Schema: metadata; Owner: -
--



--
-- TOC entry 5338 (class 0 OID 23080105)
-- Dependencies: 276
-- Data for Name: individual; Type: TABLE DATA; Schema: metadata; Owner: -
--



--
-- TOC entry 5339 (class 0 OID 23080121)
-- Dependencies: 277
-- Data for Name: organisation; Type: TABLE DATA; Schema: metadata; Owner: -
--



--
-- TOC entry 5341 (class 0 OID 23080160)
-- Dependencies: 279
-- Data for Name: organisation_individual; Type: TABLE DATA; Schema: metadata; Owner: -
--



--
-- TOC entry 5340 (class 0 OID 23080142)
-- Dependencies: 278
-- Data for Name: organisation_unit; Type: TABLE DATA; Schema: metadata; Owner: -
--



--
-- TOC entry 4858 (class 0 OID 23078485)
-- Dependencies: 228
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- TOC entry 5607 (class 0 OID 0)
-- Dependencies: 283
-- Name: element_element_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.element_element_id_seq', 1, false);


--
-- TOC entry 5608 (class 0 OID 0)
-- Dependencies: 271
-- Name: observation_numerical_specime_observation_numerical_specime_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.observation_numerical_specime_observation_numerical_specime_seq', 1, false);


--
-- TOC entry 5609 (class 0 OID 0)
-- Dependencies: 255
-- Name: observation_phys_chem_observation_phys_chem_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.observation_phys_chem_observation_phys_chem_id_seq', 1007, true);


--
-- TOC entry 5610 (class 0 OID 0)
-- Dependencies: 284
-- Name: plot_plot_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.plot_plot_id_seq', 1, false);


--
-- TOC entry 5611 (class 0 OID 0)
-- Dependencies: 285
-- Name: procedure_desc_procedure_desc_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.procedure_desc_procedure_desc_id_seq1', 1, true);


--
-- TOC entry 5612 (class 0 OID 0)
-- Dependencies: 286
-- Name: procedure_phys_chem_procedure_phys_chem_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.procedure_phys_chem_procedure_phys_chem_id_seq1', 298, true);


--
-- TOC entry 5613 (class 0 OID 0)
-- Dependencies: 287
-- Name: profile_profile_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.profile_profile_id_seq', 1, false);


--
-- TOC entry 5614 (class 0 OID 0)
-- Dependencies: 288
-- Name: project_project_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.project_project_id_seq', 1, false);


--
-- TOC entry 5615 (class 0 OID 0)
-- Dependencies: 289
-- Name: property_desc_element_property_desc_element_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_desc_element_property_desc_element_id_seq1', 170, true);


--
-- TOC entry 5616 (class 0 OID 0)
-- Dependencies: 290
-- Name: property_desc_plot_property_desc_plot_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_desc_plot_property_desc_plot_id_seq1', 84, true);


--
-- TOC entry 5617 (class 0 OID 0)
-- Dependencies: 291
-- Name: property_desc_profile_property_desc_profile_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_desc_profile_property_desc_profile_id_seq1', 15, true);


--
-- TOC entry 5618 (class 0 OID 0)
-- Dependencies: 292
-- Name: property_desc_specimen_property_desc_specimen_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_desc_specimen_property_desc_specimen_id_seq1', 1, false);


--
-- TOC entry 5619 (class 0 OID 0)
-- Dependencies: 293
-- Name: property_desc_surface_property_desc_surface_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_desc_surface_property_desc_surface_id_seq1', 24, true);


--
-- TOC entry 5620 (class 0 OID 0)
-- Dependencies: 294
-- Name: property_phys_chem_property_phys_chem_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.property_phys_chem_property_phys_chem_id_seq1', 57, true);


--
-- TOC entry 5621 (class 0 OID 0)
-- Dependencies: 273
-- Name: result_numerical_specimen_result_numerical_specimen_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.result_numerical_specimen_result_numerical_specimen_id_seq', 1, false);


--
-- TOC entry 5622 (class 0 OID 0)
-- Dependencies: 257
-- Name: result_phys_chem_result_phys_chem_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.result_phys_chem_result_phys_chem_id_seq', 1, false);


--
-- TOC entry 5623 (class 0 OID 0)
-- Dependencies: 295
-- Name: site_site_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.site_site_id_seq', 1, false);


--
-- TOC entry 5624 (class 0 OID 0)
-- Dependencies: 297
-- Name: specimen_prep_process_specimen_prep_process_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.specimen_prep_process_specimen_prep_process_id_seq', 1, false);


--
-- TOC entry 5625 (class 0 OID 0)
-- Dependencies: 296
-- Name: specimen_specimen_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.specimen_specimen_id_seq', 1, false);


--
-- TOC entry 5626 (class 0 OID 0)
-- Dependencies: 298
-- Name: specimen_storage_specimen_storage_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.specimen_storage_specimen_storage_id_seq', 1, false);


--
-- TOC entry 5627 (class 0 OID 0)
-- Dependencies: 299
-- Name: specimen_transport_specimen_transport_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.specimen_transport_specimen_transport_id_seq', 1, false);


--
-- TOC entry 5628 (class 0 OID 0)
-- Dependencies: 300
-- Name: surface_surface_id_seq; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.surface_surface_id_seq', 1, false);


--
-- TOC entry 5629 (class 0 OID 0)
-- Dependencies: 301
-- Name: thesaurus_desc_element_thesaurus_desc_element_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.thesaurus_desc_element_thesaurus_desc_element_id_seq1', 358, true);


--
-- TOC entry 5630 (class 0 OID 0)
-- Dependencies: 302
-- Name: thesaurus_desc_plot_thesaurus_desc_plot_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.thesaurus_desc_plot_thesaurus_desc_plot_id_seq1', 389, true);


--
-- TOC entry 5631 (class 0 OID 0)
-- Dependencies: 303
-- Name: thesaurus_desc_profile_thesaurus_desc_profile_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.thesaurus_desc_profile_thesaurus_desc_profile_id_seq1', 9, true);


--
-- TOC entry 5632 (class 0 OID 0)
-- Dependencies: 304
-- Name: thesaurus_desc_specimen_thesaurus_desc_specimen_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.thesaurus_desc_specimen_thesaurus_desc_specimen_id_seq1', 1, false);


--
-- TOC entry 5633 (class 0 OID 0)
-- Dependencies: 305
-- Name: thesaurus_desc_surface_thesaurus_desc_surface_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.thesaurus_desc_surface_thesaurus_desc_surface_id_seq1', 79, true);


--
-- TOC entry 5634 (class 0 OID 0)
-- Dependencies: 306
-- Name: unit_of_measure_unit_of_measure_id_seq1; Type: SEQUENCE SET; Schema: core; Owner: -
--

SELECT pg_catalog.setval('core.unit_of_measure_unit_of_measure_id_seq1', 17, true);


--
-- TOC entry 5635 (class 0 OID 0)
-- Dependencies: 307
-- Name: address_address_id_seq; Type: SEQUENCE SET; Schema: metadata; Owner: -
--

SELECT pg_catalog.setval('metadata.address_address_id_seq', 1, false);


--
-- TOC entry 5636 (class 0 OID 0)
-- Dependencies: 308
-- Name: individual_individual_id_seq; Type: SEQUENCE SET; Schema: metadata; Owner: -
--

SELECT pg_catalog.setval('metadata.individual_individual_id_seq', 1, false);


--
-- TOC entry 5637 (class 0 OID 0)
-- Dependencies: 309
-- Name: organisation_organisation_id_seq; Type: SEQUENCE SET; Schema: metadata; Owner: -
--

SELECT pg_catalog.setval('metadata.organisation_organisation_id_seq', 1, false);


--
-- TOC entry 5638 (class 0 OID 0)
-- Dependencies: 310
-- Name: organisation_unit_organisation_unit_id_seq; Type: SEQUENCE SET; Schema: metadata; Owner: -
--

SELECT pg_catalog.setval('metadata.organisation_unit_organisation_unit_id_seq', 1, false);


--
-- TOC entry 4909 (class 2606 OID 23080315)
-- Name: element element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT element_pkey PRIMARY KEY (element_id);


--
-- TOC entry 4977 (class 2606 OID 23079750)
-- Name: observation_desc_element observation_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT observation_desc_element_pkey PRIMARY KEY (property_desc_element_id, thesaurus_desc_element_id);


--
-- TOC entry 4979 (class 2606 OID 23079597)
-- Name: observation_desc_element observation_desc_element_property_desc_element_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT observation_desc_element_property_desc_element_id_thesaurus_key UNIQUE (property_desc_element_id, thesaurus_desc_element_id);


--
-- TOC entry 4969 (class 2606 OID 23079746)
-- Name: observation_desc_plot observation_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT observation_desc_plot_pkey PRIMARY KEY (property_desc_plot_id, thesaurus_desc_plot_id);


--
-- TOC entry 4971 (class 2606 OID 23079553)
-- Name: observation_desc_plot observation_desc_plot_property_desc_plot_id_thesaurus_desc__key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT observation_desc_plot_property_desc_plot_id_thesaurus_desc__key UNIQUE (property_desc_plot_id, thesaurus_desc_plot_id);


--
-- TOC entry 4973 (class 2606 OID 23079748)
-- Name: observation_desc_profile observation_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT observation_desc_profile_pkey PRIMARY KEY (property_desc_profile_id, thesaurus_desc_profile_id);


--
-- TOC entry 4975 (class 2606 OID 23079575)
-- Name: observation_desc_profile observation_desc_profile_property_desc_profile_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT observation_desc_profile_property_desc_profile_id_thesaurus_key UNIQUE (property_desc_profile_id, thesaurus_desc_profile_id);


--
-- TOC entry 5035 (class 2606 OID 23079977)
-- Name: observation_desc_specimen observation_desc_specimen_property_desc_specimen_id_thesaur_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT observation_desc_specimen_property_desc_specimen_id_thesaur_key UNIQUE (property_desc_specimen_id, thesaurus_desc_specimen_id);


--
-- TOC entry 4965 (class 2606 OID 23079744)
-- Name: observation_desc_surface observation_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT observation_desc_surface_pkey PRIMARY KEY (property_desc_surface_id, thesaurus_desc_surface_id);


--
-- TOC entry 4967 (class 2606 OID 23079531)
-- Name: observation_desc_surface observation_desc_surface_property_desc_surface_id_thesaurus_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT observation_desc_surface_property_desc_surface_id_thesaurus_key UNIQUE (property_desc_surface_id, thesaurus_desc_surface_id);


--
-- TOC entry 5037 (class 2606 OID 23080046)
-- Name: observation_phys_chem_specimen observation_numerical_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT observation_numerical_specimen_pkey PRIMARY KEY (observation_phys_chem_specimen_id);


--
-- TOC entry 4985 (class 2606 OID 23079630)
-- Name: observation_phys_chem_element observation_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT observation_phys_chem_pkey PRIMARY KEY (observation_phys_chem_element_id);


--
-- TOC entry 4987 (class 2606 OID 23079632)
-- Name: observation_phys_chem_element observation_phys_chem_property_phys_chem_id_procedure_phys__key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT observation_phys_chem_property_phys_chem_id_procedure_phys__key UNIQUE (property_phys_chem_id, procedure_phys_chem_id);


--
-- TOC entry 5039 (class 2606 OID 23080953)
-- Name: observation_phys_chem_specimen observation_phys_chem_specimen_property_phys_chem_id_procedure_; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT observation_phys_chem_specimen_property_phys_chem_id_procedure_ UNIQUE (property_phys_chem_id, procedure_phys_chem_id);


--
-- TOC entry 5065 (class 2606 OID 23080235)
-- Name: plot_individual plot_individual_plot_id_individual_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT plot_individual_plot_id_individual_id_key UNIQUE (plot_id, individual_id);


--
-- TOC entry 4897 (class 2606 OID 23080334)
-- Name: plot plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT plot_pkey PRIMARY KEY (plot_id);


--
-- TOC entry 5003 (class 2606 OID 23080372)
-- Name: procedure_desc procedure_desc_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT procedure_desc_pkey PRIMARY KEY (procedure_desc_id);


--
-- TOC entry 5005 (class 2606 OID 23079842)
-- Name: procedure_desc procedure_desc_uri_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT procedure_desc_uri_key UNIQUE (uri);


--
-- TOC entry 4919 (class 2606 OID 23080429)
-- Name: procedure_phys_chem procedure_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT procedure_phys_chem_pkey PRIMARY KEY (procedure_phys_chem_id);


--
-- TOC entry 4905 (class 2606 OID 23080443)
-- Name: profile profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT profile_pkey PRIMARY KEY (profile_id);


--
-- TOC entry 4882 (class 2606 OID 23079260)
-- Name: project project_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT project_name_key UNIQUE (name);


--
-- TOC entry 5069 (class 2606 OID 23080928)
-- Name: project_organisation project_organisation_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT project_organisation_pkey PRIMARY KEY (project_id, organisation_id);


--
-- TOC entry 4884 (class 2606 OID 23080469)
-- Name: project project_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (project_id);


--
-- TOC entry 4888 (class 2606 OID 23079270)
-- Name: project_related project_related_project_source_id_project_target_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT project_related_project_source_id_project_target_id_key UNIQUE (project_source_id, project_target_id);


--
-- TOC entry 4943 (class 2606 OID 23080503)
-- Name: property_desc_element property_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT property_desc_element_pkey PRIMARY KEY (property_desc_element_id);


--
-- TOC entry 4931 (class 2606 OID 23080519)
-- Name: property_desc_plot property_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT property_desc_plot_pkey PRIMARY KEY (property_desc_plot_id);


--
-- TOC entry 4937 (class 2606 OID 23080535)
-- Name: property_desc_profile property_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT property_desc_profile_pkey PRIMARY KEY (property_desc_profile_id);


--
-- TOC entry 5027 (class 2606 OID 23080550)
-- Name: property_desc_specimen property_desc_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_specimen
    ADD CONSTRAINT property_desc_specimen_pkey PRIMARY KEY (property_desc_specimen_id);


--
-- TOC entry 4925 (class 2606 OID 23080566)
-- Name: property_desc_surface property_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT property_desc_surface_pkey PRIMARY KEY (property_desc_surface_id);


--
-- TOC entry 4913 (class 2606 OID 23080582)
-- Name: property_phys_chem property_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT property_phys_chem_pkey PRIMARY KEY (property_phys_chem_id);


--
-- TOC entry 5063 (class 2606 OID 23080196)
-- Name: result_desc_specimen result_desc_specimen_specimen_id_property_desc_specimen_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT result_desc_specimen_specimen_id_property_desc_specimen_id_key UNIQUE (specimen_id, property_desc_specimen_id);


--
-- TOC entry 5041 (class 2606 OID 23080076)
-- Name: result_phys_chem_specimen result_numerical_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_pkey PRIMARY KEY (result_phys_chem_specimen_id);


--
-- TOC entry 5043 (class 2606 OID 23080921)
-- Name: result_phys_chem_specimen result_numerical_specimen_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_unq UNIQUE (observation_phys_chem_specimen_id, specimen_id);


--
-- TOC entry 5045 (class 2606 OID 23080275)
-- Name: result_phys_chem_specimen result_numerical_specimen_unq_foi_obs; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT result_numerical_specimen_unq_foi_obs UNIQUE (specimen_id, observation_phys_chem_specimen_id);


--
-- TOC entry 4989 (class 2606 OID 23079662)
-- Name: result_phys_chem_element result_phys_chem_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_pkey PRIMARY KEY (result_phys_chem_element_id);


--
-- TOC entry 4991 (class 2606 OID 23080919)
-- Name: result_phys_chem_element result_phys_chem_unq; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_unq UNIQUE (observation_phys_chem_element_id, element_id);


--
-- TOC entry 4993 (class 2606 OID 23080277)
-- Name: result_phys_chem_element result_phys_chem_unq_foi_obs; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT result_phys_chem_unq_foi_obs UNIQUE (element_id, observation_phys_chem_element_id);


--
-- TOC entry 4890 (class 2606 OID 23080591)
-- Name: site site_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (site_id);


--
-- TOC entry 4894 (class 2606 OID 23079298)
-- Name: site_project site_project_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT site_project_pkey PRIMARY KEY (site_id, project_id);


--
-- TOC entry 5025 (class 2606 OID 23080617)
-- Name: specimen specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT specimen_pkey PRIMARY KEY (specimen_id);


--
-- TOC entry 5021 (class 2606 OID 23079907)
-- Name: specimen_prep_process specimen_prep_process_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT specimen_prep_process_definition_key UNIQUE (definition);


--
-- TOC entry 5023 (class 2606 OID 23080638)
-- Name: specimen_prep_process specimen_prep_process_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT specimen_prep_process_pkey PRIMARY KEY (specimen_prep_process_id);


--
-- TOC entry 5015 (class 2606 OID 23079894)
-- Name: specimen_storage specimen_storage_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT specimen_storage_definition_key UNIQUE (definition);


--
-- TOC entry 5017 (class 2606 OID 23080654)
-- Name: specimen_storage specimen_storage_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT specimen_storage_pkey PRIMARY KEY (specimen_storage_id);


--
-- TOC entry 5009 (class 2606 OID 23079881)
-- Name: specimen_transport specimen_transport_definition_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT specimen_transport_definition_key UNIQUE (definition);


--
-- TOC entry 5011 (class 2606 OID 23080671)
-- Name: specimen_transport specimen_transport_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT specimen_transport_pkey PRIMARY KEY (specimen_transport_id);


--
-- TOC entry 5067 (class 2606 OID 23080252)
-- Name: surface_individual surface_individual_surface_id_individual_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT surface_individual_surface_id_individual_id_key UNIQUE (surface_id, individual_id);


--
-- TOC entry 4901 (class 2606 OID 23080688)
-- Name: surface surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT surface_pkey PRIMARY KEY (surface_id);


--
-- TOC entry 4961 (class 2606 OID 23080726)
-- Name: thesaurus_desc_element thesaurus_desc_element_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_element
    ADD CONSTRAINT thesaurus_desc_element_pkey PRIMARY KEY (thesaurus_desc_element_id);


--
-- TOC entry 4953 (class 2606 OID 23080741)
-- Name: thesaurus_desc_plot thesaurus_desc_plot_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_plot
    ADD CONSTRAINT thesaurus_desc_plot_pkey PRIMARY KEY (thesaurus_desc_plot_id);


--
-- TOC entry 4957 (class 2606 OID 23080756)
-- Name: thesaurus_desc_profile thesaurus_desc_profile_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_profile
    ADD CONSTRAINT thesaurus_desc_profile_pkey PRIMARY KEY (thesaurus_desc_profile_id);


--
-- TOC entry 5031 (class 2606 OID 23080771)
-- Name: thesaurus_desc_specimen thesaurus_desc_specimen_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_specimen
    ADD CONSTRAINT thesaurus_desc_specimen_pkey PRIMARY KEY (thesaurus_desc_specimen_id);


--
-- TOC entry 4949 (class 2606 OID 23080786)
-- Name: thesaurus_desc_surface thesaurus_desc_surface_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_surface
    ADD CONSTRAINT thesaurus_desc_surface_pkey PRIMARY KEY (thesaurus_desc_surface_id);


--
-- TOC entry 4981 (class 2606 OID 23080801)
-- Name: unit_of_measure unit_of_measure_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.unit_of_measure
    ADD CONSTRAINT unit_of_measure_pkey PRIMARY KEY (unit_of_measure_id);


--
-- TOC entry 4911 (class 2606 OID 23080289)
-- Name: element unq_element_profile_order_element; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT unq_element_profile_order_element UNIQUE (profile_id, order_element);


--
-- TOC entry 4899 (class 2606 OID 23079824)
-- Name: plot unq_plot_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT unq_plot_code UNIQUE (plot_code);


--
-- TOC entry 5007 (class 2606 OID 23080291)
-- Name: procedure_desc unq_procedure_desc_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_desc
    ADD CONSTRAINT unq_procedure_desc_label UNIQUE (label);


--
-- TOC entry 4921 (class 2606 OID 23079820)
-- Name: procedure_phys_chem unq_procedure_phys_chem_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT unq_procedure_phys_chem_label UNIQUE (label);


--
-- TOC entry 4923 (class 2606 OID 23079822)
-- Name: procedure_phys_chem unq_procedure_phys_chem_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT unq_procedure_phys_chem_uri UNIQUE (uri);


--
-- TOC entry 4907 (class 2606 OID 23079826)
-- Name: profile unq_profile_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT unq_profile_code UNIQUE (profile_code);


--
-- TOC entry 4886 (class 2606 OID 23079828)
-- Name: project unq_project_name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project
    ADD CONSTRAINT unq_project_name UNIQUE (name);


--
-- TOC entry 4945 (class 2606 OID 23079800)
-- Name: property_desc_element unq_property_desc_element_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT unq_property_desc_element_label UNIQUE (label);


--
-- TOC entry 4947 (class 2606 OID 23079802)
-- Name: property_desc_element unq_property_desc_element_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_element
    ADD CONSTRAINT unq_property_desc_element_uri UNIQUE (uri);


--
-- TOC entry 4933 (class 2606 OID 23079792)
-- Name: property_desc_plot unq_property_desc_plot_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT unq_property_desc_plot_label UNIQUE (label);


--
-- TOC entry 4935 (class 2606 OID 23079794)
-- Name: property_desc_plot unq_property_desc_plot_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_plot
    ADD CONSTRAINT unq_property_desc_plot_uri UNIQUE (uri);


--
-- TOC entry 4939 (class 2606 OID 23079796)
-- Name: property_desc_profile unq_property_desc_profile_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT unq_property_desc_profile_label UNIQUE (label);


--
-- TOC entry 4941 (class 2606 OID 23079798)
-- Name: property_desc_profile unq_property_desc_profile_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_profile
    ADD CONSTRAINT unq_property_desc_profile_uri UNIQUE (uri);


--
-- TOC entry 5029 (class 2606 OID 23080295)
-- Name: property_desc_specimen unq_property_desc_specimen_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_specimen
    ADD CONSTRAINT unq_property_desc_specimen_label UNIQUE (label);


--
-- TOC entry 4927 (class 2606 OID 23079788)
-- Name: property_desc_surface unq_property_desc_surface_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT unq_property_desc_surface_label UNIQUE (label);


--
-- TOC entry 4929 (class 2606 OID 23079790)
-- Name: property_desc_surface unq_property_desc_surface_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_desc_surface
    ADD CONSTRAINT unq_property_desc_surface_uri UNIQUE (uri);


--
-- TOC entry 4915 (class 2606 OID 23080299)
-- Name: property_phys_chem unq_property_phys_chem_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT unq_property_phys_chem_label UNIQUE (label);


--
-- TOC entry 4917 (class 2606 OID 23080301)
-- Name: property_phys_chem unq_property_phys_chem_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.property_phys_chem
    ADD CONSTRAINT unq_property_phys_chem_uri UNIQUE (uri);


--
-- TOC entry 5001 (class 2606 OID 23079786)
-- Name: result_desc_element unq_result_desc_element; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT unq_result_desc_element UNIQUE (element_id, property_desc_element_id);


--
-- TOC entry 4997 (class 2606 OID 23079768)
-- Name: result_desc_plot unq_result_desc_plot; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT unq_result_desc_plot UNIQUE (plot_id, property_desc_plot_id);


--
-- TOC entry 4999 (class 2606 OID 23079777)
-- Name: result_desc_profile unq_result_desc_profile; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT unq_result_desc_profile UNIQUE (profile_id, property_desc_profile_id);


--
-- TOC entry 4995 (class 2606 OID 23079759)
-- Name: result_desc_surface unq_result_desc_surface; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT unq_result_desc_surface UNIQUE (surface_id, property_desc_surface_id);


--
-- TOC entry 4892 (class 2606 OID 23079830)
-- Name: site unq_site_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT unq_site_code UNIQUE (site_code);


--
-- TOC entry 5019 (class 2606 OID 23080303)
-- Name: specimen_storage unq_specimen_storage_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_storage
    ADD CONSTRAINT unq_specimen_storage_label UNIQUE (label);


--
-- TOC entry 5013 (class 2606 OID 23080305)
-- Name: specimen_transport unq_specimen_transport_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_transport
    ADD CONSTRAINT unq_specimen_transport_label UNIQUE (label);


--
-- TOC entry 4903 (class 2606 OID 23080716)
-- Name: surface unq_surface_super; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT unq_surface_super UNIQUE (surface_id, super_surface_id);


--
-- TOC entry 4963 (class 2606 OID 23079818)
-- Name: thesaurus_desc_element unq_thesaurus_desc_element_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_element
    ADD CONSTRAINT unq_thesaurus_desc_element_uri UNIQUE (uri);


--
-- TOC entry 4955 (class 2606 OID 23079810)
-- Name: thesaurus_desc_plot unq_thesaurus_desc_plot_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_plot
    ADD CONSTRAINT unq_thesaurus_desc_plot_uri UNIQUE (uri);


--
-- TOC entry 4959 (class 2606 OID 23079814)
-- Name: thesaurus_desc_profile unq_thesaurus_desc_profile_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_profile
    ADD CONSTRAINT unq_thesaurus_desc_profile_uri UNIQUE (uri);


--
-- TOC entry 5033 (class 2606 OID 23080309)
-- Name: thesaurus_desc_specimen unq_thesaurus_desc_specimen_label; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_specimen
    ADD CONSTRAINT unq_thesaurus_desc_specimen_label UNIQUE (label);


--
-- TOC entry 4951 (class 2606 OID 23079806)
-- Name: thesaurus_desc_surface unq_thesaurus_desc_surface_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.thesaurus_desc_surface
    ADD CONSTRAINT unq_thesaurus_desc_surface_uri UNIQUE (uri);


--
-- TOC entry 4983 (class 2606 OID 23080311)
-- Name: unit_of_measure unq_unit_of_measure_uri; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.unit_of_measure
    ADD CONSTRAINT unq_unit_of_measure_uri UNIQUE (uri);


--
-- TOC entry 4878 (class 2606 OID 23078164)
-- Name: current current_pkey; Type: CONSTRAINT; Schema: graphile_migrate; Owner: -
--

ALTER TABLE ONLY graphile_migrate.current
    ADD CONSTRAINT current_pkey PRIMARY KEY (filename);


--
-- TOC entry 4876 (class 2606 OID 23078147)
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: graphile_migrate; Owner: -
--

ALTER TABLE ONLY graphile_migrate.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (hash);


--
-- TOC entry 5047 (class 2606 OID 23080815)
-- Name: address address_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (address_id);


--
-- TOC entry 5049 (class 2606 OID 23080835)
-- Name: individual individual_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT individual_pkey PRIMARY KEY (individual_id);


--
-- TOC entry 5061 (class 2606 OID 23080168)
-- Name: organisation_individual organisation_individual_individual_id_organisation_id_key; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT organisation_individual_individual_id_organisation_id_key UNIQUE (individual_id, organisation_id);


--
-- TOC entry 5055 (class 2606 OID 23080865)
-- Name: organisation organisation_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT organisation_pkey PRIMARY KEY (organisation_id);


--
-- TOC entry 5057 (class 2606 OID 23080154)
-- Name: organisation_unit organisation_unit_name_organisation_id_key; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT organisation_unit_name_organisation_id_key UNIQUE (name, organisation_id);


--
-- TOC entry 5059 (class 2606 OID 23080905)
-- Name: organisation_unit organisation_unit_pkey; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT organisation_unit_pkey PRIMARY KEY (organisation_unit_id);


--
-- TOC entry 5051 (class 2606 OID 23081043)
-- Name: individual unique_email; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT unique_email UNIQUE (email);


--
-- TOC entry 5053 (class 2606 OID 23081041)
-- Name: individual unique_name; Type: CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT unique_name UNIQUE (name);


--
-- TOC entry 4895 (class 1259 OID 23081039)
-- Name: core_plot_position_geog_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX core_plot_position_geog_idx ON core.plot USING gist ("position");


--
-- TOC entry 5138 (class 2620 OID 23079674)
-- Name: result_phys_chem_element trg_check_result_value; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_check_result_value BEFORE INSERT OR UPDATE ON core.result_phys_chem_element FOR EACH ROW EXECUTE FUNCTION core.check_result_value();


--
-- TOC entry 5639 (class 0 OID 0)
-- Dependencies: 5138
-- Name: TRIGGER trg_check_result_value ON result_phys_chem_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TRIGGER trg_check_result_value ON core.result_phys_chem_element IS 'Verifies if the value assigned to the result is valid. See the function core.ceck_result_valus function for implementation.';


--
-- TOC entry 5139 (class 2620 OID 23080088)
-- Name: result_phys_chem_specimen trg_check_result_value_specimen; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_check_result_value_specimen BEFORE INSERT OR UPDATE ON core.result_phys_chem_specimen FOR EACH ROW EXECUTE FUNCTION core.check_result_value_specimen();


--
-- TOC entry 5640 (class 0 OID 0)
-- Dependencies: 5139
-- Name: TRIGGER trg_check_result_value_specimen ON result_phys_chem_specimen; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TRIGGER trg_check_result_value_specimen ON core.result_phys_chem_specimen IS 'Verifies if the value assigned to the result is valid. See the function core.ceck_result_value function for implementation.';


--
-- TOC entry 5082 (class 2606 OID 23080430)
-- Name: procedure_phys_chem fk_broader; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.procedure_phys_chem
    ADD CONSTRAINT fk_broader FOREIGN KEY (broader_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- TOC entry 5107 (class 2606 OID 23081007)
-- Name: result_desc_element fk_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT fk_element FOREIGN KEY (element_id) REFERENCES core.element(element_id) ON DELETE CASCADE;


--
-- TOC entry 5098 (class 2606 OID 23081012)
-- Name: result_phys_chem_element fk_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_element FOREIGN KEY (element_id) REFERENCES core.element(element_id) ON DELETE CASCADE;


--
-- TOC entry 5134 (class 2606 OID 23080842)
-- Name: surface_individual fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- TOC entry 5132 (class 2606 OID 23080847)
-- Name: plot_individual fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- TOC entry 5099 (class 2606 OID 23080852)
-- Name: result_phys_chem_element fk_individual; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- TOC entry 5120 (class 2606 OID 23080077)
-- Name: result_phys_chem_specimen fk_observation_numerical_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_observation_numerical_specimen FOREIGN KEY (observation_phys_chem_specimen_id) REFERENCES core.observation_phys_chem_specimen(observation_phys_chem_specimen_id);


--
-- TOC entry 5100 (class 2606 OID 23079663)
-- Name: result_phys_chem_element fk_observation_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_element
    ADD CONSTRAINT fk_observation_phys_chem FOREIGN KEY (observation_phys_chem_element_id) REFERENCES core.observation_phys_chem_element(observation_phys_chem_element_id);


--
-- TOC entry 5121 (class 2606 OID 23080877)
-- Name: result_phys_chem_specimen fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- TOC entry 5111 (class 2606 OID 23080882)
-- Name: specimen fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- TOC entry 5136 (class 2606 OID 23080929)
-- Name: project_organisation fk_organisation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- TOC entry 5079 (class 2606 OID 23080972)
-- Name: profile fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- TOC entry 5112 (class 2606 OID 23080982)
-- Name: specimen fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- TOC entry 5133 (class 2606 OID 23080987)
-- Name: plot_individual fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot_individual
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- TOC entry 5103 (class 2606 OID 23080992)
-- Name: result_desc_plot fk_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id) REFERENCES core.plot(plot_id) ON DELETE CASCADE;


--
-- TOC entry 5092 (class 2606 OID 23080373)
-- Name: observation_desc_element fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- TOC entry 5086 (class 2606 OID 23080378)
-- Name: observation_desc_plot fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- TOC entry 5089 (class 2606 OID 23080383)
-- Name: observation_desc_profile fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- TOC entry 5114 (class 2606 OID 23080388)
-- Name: observation_desc_specimen fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- TOC entry 5083 (class 2606 OID 23080393)
-- Name: observation_desc_surface fk_procedure_desc; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id) REFERENCES core.procedure_desc(procedure_desc_id);


--
-- TOC entry 5095 (class 2606 OID 23080435)
-- Name: observation_phys_chem_element fk_procedure_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- TOC entry 5117 (class 2606 OID 23080947)
-- Name: observation_phys_chem_specimen fk_procedure_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id) REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);


--
-- TOC entry 5073 (class 2606 OID 23080461)
-- Name: site fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT fk_profile FOREIGN KEY (typical_profile) REFERENCES core.profile(profile_id);


--
-- TOC entry 5081 (class 2606 OID 23080997)
-- Name: element fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.element
    ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id) REFERENCES core.profile(profile_id) ON DELETE CASCADE;


--
-- TOC entry 5105 (class 2606 OID 23081002)
-- Name: result_desc_profile fk_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id) REFERENCES core.profile(profile_id) ON DELETE CASCADE;


--
-- TOC entry 5074 (class 2606 OID 23080478)
-- Name: site_project fk_project; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES core.project(project_id);


--
-- TOC entry 5137 (class 2606 OID 23080934)
-- Name: project_organisation fk_project; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_organisation
    ADD CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES core.project(project_id);


--
-- TOC entry 5071 (class 2606 OID 23080483)
-- Name: project_related fk_project_source; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT fk_project_source FOREIGN KEY (project_source_id) REFERENCES core.project(project_id);


--
-- TOC entry 5072 (class 2606 OID 23080488)
-- Name: project_related fk_project_target; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.project_related
    ADD CONSTRAINT fk_project_target FOREIGN KEY (project_target_id) REFERENCES core.project(project_id);


--
-- TOC entry 5093 (class 2606 OID 23080504)
-- Name: observation_desc_element fk_property_desc_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_property_desc_element FOREIGN KEY (property_desc_element_id) REFERENCES core.property_desc_element(property_desc_element_id);


--
-- TOC entry 5087 (class 2606 OID 23080520)
-- Name: observation_desc_plot fk_property_desc_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_property_desc_plot FOREIGN KEY (property_desc_plot_id) REFERENCES core.property_desc_plot(property_desc_plot_id);


--
-- TOC entry 5090 (class 2606 OID 23080536)
-- Name: observation_desc_profile fk_property_desc_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_property_desc_profile FOREIGN KEY (property_desc_profile_id) REFERENCES core.property_desc_profile(property_desc_profile_id);


--
-- TOC entry 5115 (class 2606 OID 23080551)
-- Name: observation_desc_specimen fk_property_desc_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_property_desc_specimen FOREIGN KEY (property_desc_specimen_id) REFERENCES core.property_desc_specimen(property_desc_specimen_id);


--
-- TOC entry 5084 (class 2606 OID 23080567)
-- Name: observation_desc_surface fk_property_desc_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_property_desc_surface FOREIGN KEY (property_desc_surface_id) REFERENCES core.property_desc_surface(property_desc_surface_id);


--
-- TOC entry 5096 (class 2606 OID 23080583)
-- Name: observation_phys_chem_element fk_property_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id) REFERENCES core.property_phys_chem(property_phys_chem_id);


--
-- TOC entry 5118 (class 2606 OID 23080941)
-- Name: observation_phys_chem_specimen fk_property_phys_chem; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id) REFERENCES core.property_phys_chem(property_phys_chem_id);


--
-- TOC entry 5075 (class 2606 OID 23080957)
-- Name: site_project fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site_project
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- TOC entry 5076 (class 2606 OID 23080962)
-- Name: plot fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.plot
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- TOC entry 5077 (class 2606 OID 23080967)
-- Name: surface fk_site; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT fk_site FOREIGN KEY (site_id) REFERENCES core.site(site_id) ON DELETE CASCADE;


--
-- TOC entry 5130 (class 2606 OID 23081017)
-- Name: result_desc_specimen fk_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id) REFERENCES core.specimen(specimen_id) ON DELETE CASCADE;


--
-- TOC entry 5122 (class 2606 OID 23081022)
-- Name: result_phys_chem_specimen fk_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_phys_chem_specimen
    ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id) REFERENCES core.specimen(specimen_id) ON DELETE CASCADE;


--
-- TOC entry 5113 (class 2606 OID 23080646)
-- Name: specimen fk_specimen_prep_process; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen
    ADD CONSTRAINT fk_specimen_prep_process FOREIGN KEY (specimen_prep_process_id) REFERENCES core.specimen_prep_process(specimen_prep_process_id);


--
-- TOC entry 5109 (class 2606 OID 23080663)
-- Name: specimen_prep_process fk_specimen_storage; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT fk_specimen_storage FOREIGN KEY (specimen_storage_id) REFERENCES core.specimen_storage(specimen_storage_id);


--
-- TOC entry 5110 (class 2606 OID 23080680)
-- Name: specimen_prep_process fk_specimen_transport; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.specimen_prep_process
    ADD CONSTRAINT fk_specimen_transport FOREIGN KEY (specimen_transport_id) REFERENCES core.specimen_transport(specimen_transport_id);


--
-- TOC entry 5078 (class 2606 OID 23080710)
-- Name: surface fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface
    ADD CONSTRAINT fk_surface FOREIGN KEY (super_surface_id) REFERENCES core.surface(surface_id);


--
-- TOC entry 5080 (class 2606 OID 23080977)
-- Name: profile fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.profile
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- TOC entry 5135 (class 2606 OID 23081027)
-- Name: surface_individual fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.surface_individual
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- TOC entry 5101 (class 2606 OID 23081032)
-- Name: result_desc_surface fk_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id) REFERENCES core.surface(surface_id) ON DELETE CASCADE;


--
-- TOC entry 5094 (class 2606 OID 23080727)
-- Name: observation_desc_element fk_thesaurus_desc_element; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_element
    ADD CONSTRAINT fk_thesaurus_desc_element FOREIGN KEY (thesaurus_desc_element_id) REFERENCES core.thesaurus_desc_element(thesaurus_desc_element_id);


--
-- TOC entry 5088 (class 2606 OID 23080742)
-- Name: observation_desc_plot fk_thesaurus_desc_plot; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_plot
    ADD CONSTRAINT fk_thesaurus_desc_plot FOREIGN KEY (thesaurus_desc_plot_id) REFERENCES core.thesaurus_desc_plot(thesaurus_desc_plot_id);


--
-- TOC entry 5091 (class 2606 OID 23080757)
-- Name: observation_desc_profile fk_thesaurus_desc_profile; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_profile
    ADD CONSTRAINT fk_thesaurus_desc_profile FOREIGN KEY (thesaurus_desc_profile_id) REFERENCES core.thesaurus_desc_profile(thesaurus_desc_profile_id);


--
-- TOC entry 5116 (class 2606 OID 23080772)
-- Name: observation_desc_specimen fk_thesaurus_desc_specimen; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_specimen
    ADD CONSTRAINT fk_thesaurus_desc_specimen FOREIGN KEY (thesaurus_desc_specimen_id) REFERENCES core.thesaurus_desc_specimen(thesaurus_desc_specimen_id);


--
-- TOC entry 5085 (class 2606 OID 23080787)
-- Name: observation_desc_surface fk_thesaurus_desc_surface; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_desc_surface
    ADD CONSTRAINT fk_thesaurus_desc_surface FOREIGN KEY (thesaurus_desc_surface_id) REFERENCES core.thesaurus_desc_surface(thesaurus_desc_surface_id);


--
-- TOC entry 5119 (class 2606 OID 23080802)
-- Name: observation_phys_chem_specimen fk_unit_of_measure; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_specimen
    ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id) REFERENCES core.unit_of_measure(unit_of_measure_id);


--
-- TOC entry 5097 (class 2606 OID 23080807)
-- Name: observation_phys_chem_element fk_unit_of_measure; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.observation_phys_chem_element
    ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id) REFERENCES core.unit_of_measure(unit_of_measure_id);


--
-- TOC entry 5108 (class 2606 OID 23079780)
-- Name: result_desc_element result_desc_element_property_desc_element_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_element
    ADD CONSTRAINT result_desc_element_property_desc_element_id_thesaurus_des_fkey FOREIGN KEY (property_desc_element_id, thesaurus_desc_element_id) REFERENCES core.observation_desc_element(property_desc_element_id, thesaurus_desc_element_id);


--
-- TOC entry 5104 (class 2606 OID 23079762)
-- Name: result_desc_plot result_desc_plot_property_desc_plot_id_thesaurus_desc_plot_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_plot
    ADD CONSTRAINT result_desc_plot_property_desc_plot_id_thesaurus_desc_plot_fkey FOREIGN KEY (property_desc_plot_id, thesaurus_desc_plot_id) REFERENCES core.observation_desc_plot(property_desc_plot_id, thesaurus_desc_plot_id);


--
-- TOC entry 5106 (class 2606 OID 23079771)
-- Name: result_desc_profile result_desc_profile_property_desc_profile_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_profile
    ADD CONSTRAINT result_desc_profile_property_desc_profile_id_thesaurus_des_fkey FOREIGN KEY (property_desc_profile_id, thesaurus_desc_profile_id) REFERENCES core.observation_desc_profile(property_desc_profile_id, thesaurus_desc_profile_id);


--
-- TOC entry 5131 (class 2606 OID 23080202)
-- Name: result_desc_specimen result_desc_specimen_property_desc_specimen_id_thesaurus_des_fk; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_specimen
    ADD CONSTRAINT result_desc_specimen_property_desc_specimen_id_thesaurus_des_fk FOREIGN KEY (property_desc_specimen_id, thesaurus_desc_specimen_id) REFERENCES core.observation_desc_specimen(property_desc_specimen_id, thesaurus_desc_specimen_id);


--
-- TOC entry 5102 (class 2606 OID 23079753)
-- Name: result_desc_surface result_desc_surface_property_desc_surface_id_thesaurus_des_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.result_desc_surface
    ADD CONSTRAINT result_desc_surface_property_desc_surface_id_thesaurus_des_fkey FOREIGN KEY (property_desc_surface_id, thesaurus_desc_surface_id) REFERENCES core.observation_desc_surface(property_desc_surface_id, thesaurus_desc_surface_id);


--
-- TOC entry 5070 (class 2606 OID 23078148)
-- Name: migrations migrations_previous_hash_fkey; Type: FK CONSTRAINT; Schema: graphile_migrate; Owner: -
--

ALTER TABLE ONLY graphile_migrate.migrations
    ADD CONSTRAINT migrations_previous_hash_fkey FOREIGN KEY (previous_hash) REFERENCES graphile_migrate.migrations(hash);


--
-- TOC entry 5123 (class 2606 OID 23080822)
-- Name: individual fk_address; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.individual
    ADD CONSTRAINT fk_address FOREIGN KEY (address_id) REFERENCES metadata.address(address_id);


--
-- TOC entry 5124 (class 2606 OID 23080827)
-- Name: organisation fk_address; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT fk_address FOREIGN KEY (address_id) REFERENCES metadata.address(address_id);


--
-- TOC entry 5127 (class 2606 OID 23080857)
-- Name: organisation_individual fk_individual; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id) REFERENCES metadata.individual(individual_id);


--
-- TOC entry 5128 (class 2606 OID 23080887)
-- Name: organisation_individual fk_organisation; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- TOC entry 5126 (class 2606 OID 23080897)
-- Name: organisation_unit fk_organisation; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_unit
    ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- TOC entry 5129 (class 2606 OID 23080913)
-- Name: organisation_individual fk_organisation_unit; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation_individual
    ADD CONSTRAINT fk_organisation_unit FOREIGN KEY (organisation_unit_id) REFERENCES metadata.organisation_unit(organisation_unit_id);


--
-- TOC entry 5125 (class 2606 OID 23080892)
-- Name: organisation fk_parent; Type: FK CONSTRAINT; Schema: metadata; Owner: -
--

ALTER TABLE ONLY metadata.organisation
    ADD CONSTRAINT fk_parent FOREIGN KEY (organisation_id) REFERENCES metadata.organisation(organisation_id);


--
-- PostgreSQL database dump complete
--
