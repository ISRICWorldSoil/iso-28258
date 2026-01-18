--! Previous: sha1:7d05b0a4ced079cc5f4fe1a6ecf75eb6984f6147
--! Hash: sha1:5cb34bb3316e40c490ccbe70d24cbdffac9f2a70
--! Message: text observations and multiple improvements

-- ============================================================================
-- ISO 28258 Extension: Physico-chemical observations and results for Plot
-- ============================================================================
-- This migration adds support for numeric (phys_chem) observations at the
-- Plot level, following the same pattern as existing specimen and element
-- observations.
--
-- Use case: Properties like RockDpth (Soil Depth to Bedrock) that are
-- measured at the plot level rather than at specimen or element level.
--
-- ALL STATEMENTS ARE IDEMPOTENT - safe to run multiple times.
-- ============================================================================

-- ============================================================================
-- PART 1: Create observation_phys_chem_plot table
-- ============================================================================
-- Follows the same structure as observation_phys_chem_specimen and
-- observation_phys_chem_element. An observation is a triple of
-- (property, procedure, unit) with optional min/max bounds.

CREATE TABLE IF NOT EXISTS core.observation_phys_chem_plot (
    observation_phys_chem_plot_id integer NOT NULL,
    property_phys_chem_id integer NOT NULL,
    procedure_phys_chem_id integer NOT NULL,
    unit_of_measure_id integer NOT NULL,
    value_min numeric,
    value_max numeric
);

COMMENT ON TABLE core.observation_phys_chem_plot IS 'Physio-chemical observations for the Plot feature of interest';

COMMENT ON COLUMN core.observation_phys_chem_plot.observation_phys_chem_plot_id IS 'Synthetic primary key for the observation';

COMMENT ON COLUMN core.observation_phys_chem_plot.property_phys_chem_id IS 'Foreign key to the corresponding property';

COMMENT ON COLUMN core.observation_phys_chem_plot.procedure_phys_chem_id IS 'Foreign key to the corresponding procedure';

COMMENT ON COLUMN core.observation_phys_chem_plot.unit_of_measure_id IS 'Foreign key to the corresponding unit of measure (if applicable)';

COMMENT ON COLUMN core.observation_phys_chem_plot.value_min IS 'Minimum admissable value for this combination of property, procedure and unit of measure';

COMMENT ON COLUMN core.observation_phys_chem_plot.value_max IS 'Maximum admissable value for this combination of property, procedure and unit of measure';


-- ============================================================================
-- PART 2: Create sequence for observation_phys_chem_plot
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'observation_phys_chem_plot_observation_phys_chem_plot_id_seq') THEN
        CREATE SEQUENCE core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq
            OWNED BY core.observation_phys_chem_plot.observation_phys_chem_plot_id;
    END IF;
END $$;

ALTER TABLE core.observation_phys_chem_plot
    ALTER COLUMN observation_phys_chem_plot_id
    SET DEFAULT nextval('core.observation_phys_chem_plot_observation_phys_chem_plot_id_seq'::regclass);


-- ============================================================================
-- PART 3: Create result_phys_chem_plot table
-- ============================================================================
-- Stores actual numeric measurement values for plots.
-- Follows the same structure as result_phys_chem_specimen and
-- result_phys_chem_element.

CREATE TABLE IF NOT EXISTS core.result_phys_chem_plot (
    result_phys_chem_plot_id integer NOT NULL,
    observation_phys_chem_plot_id integer NOT NULL,
    plot_id integer NOT NULL,
    value numeric NOT NULL,
    organisation_id integer
);

COMMENT ON TABLE core.result_phys_chem_plot IS 'Physio-chemical results for the Plot feature of interest.';

COMMENT ON COLUMN core.result_phys_chem_plot.result_phys_chem_plot_id IS 'Synthetic primary key.';

COMMENT ON COLUMN core.result_phys_chem_plot.observation_phys_chem_plot_id IS 'Foreign key to the corresponding physio-chemical observation.';

COMMENT ON COLUMN core.result_phys_chem_plot.plot_id IS 'Foreign key to the corresponding Plot instance.';

COMMENT ON COLUMN core.result_phys_chem_plot.value IS 'Numerical value resulting from applying the referred observation to the referred plot.';

COMMENT ON COLUMN core.result_phys_chem_plot.organisation_id IS 'Foreign key to the organisation responsible for the measurement.';


-- ============================================================================
-- PART 4: Create sequence for result_phys_chem_plot
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'result_phys_chem_plot_result_phys_chem_plot_id_seq') THEN
        CREATE SEQUENCE core.result_phys_chem_plot_result_phys_chem_plot_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.result_phys_chem_plot_result_phys_chem_plot_id_seq
            OWNED BY core.result_phys_chem_plot.result_phys_chem_plot_id;
    END IF;
END $$;

ALTER TABLE core.result_phys_chem_plot
    ALTER COLUMN result_phys_chem_plot_id
    SET DEFAULT nextval('core.result_phys_chem_plot_result_phys_chem_plot_id_seq'::regclass);


-- ============================================================================
-- PART 5: Create check_result_value_plot() trigger function
-- ============================================================================
-- Validates that result values fall within the observation's min/max bounds.
-- Follows the same pattern as check_result_value_specimen().

CREATE OR REPLACE FUNCTION core.check_result_value_plot() RETURNS trigger
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

COMMENT ON FUNCTION core.check_result_value_plot() IS 'Checks if the value assigned to a result record is within the numerical bounds declared in the related observation (fields value_min and value_max).';


-- ============================================================================
-- PART 6: Create etl_insert_result_phys_chem_plot() helper function
-- ============================================================================
-- ETL helper function for inserting plot-level phys_chem results.
-- Follows the same pattern as etl_insert_result_phys_chem_specimen().

DROP FUNCTION IF EXISTS core.etl_insert_result_phys_chem_plot(integer, integer, integer, numeric);
CREATE FUNCTION core.etl_insert_result_phys_chem_plot(
    observation_phys_chem_plot_id integer,
    plot_id integer,
    organisation_id integer,
    value numeric
) RETURNS core.result_phys_chem_plot
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

COMMENT ON FUNCTION core.etl_insert_result_phys_chem_plot(observation_phys_chem_plot_id integer, plot_id integer, organisation_id integer, value numeric) IS 'Inserts a new result_phys_chem_plot into the core.result_phys_chem_plot table. If the result_phys_chem_plot already exists, it returns the existing record.';


-- ============================================================================
-- PART 7: Add primary key constraints (idempotent)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'observation_phys_chem_plot_pkey') THEN
        ALTER TABLE ONLY core.observation_phys_chem_plot
            ADD CONSTRAINT observation_phys_chem_plot_pkey
            PRIMARY KEY (observation_phys_chem_plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_phys_chem_plot_pkey') THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT result_phys_chem_plot_pkey
            PRIMARY KEY (result_phys_chem_plot_id);
    END IF;
END $$;


-- ============================================================================
-- PART 8: Add unique constraints (idempotent)
-- ============================================================================
-- Each observation (property + procedure combination) must be unique
-- Each result (observation + plot combination) must be unique

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'observation_phys_chem_plot_property_procedure_unq') THEN
        ALTER TABLE ONLY core.observation_phys_chem_plot
            ADD CONSTRAINT observation_phys_chem_plot_property_procedure_unq
            UNIQUE (property_phys_chem_id, procedure_phys_chem_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_phys_chem_plot_unq') THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT result_phys_chem_plot_unq
            UNIQUE (observation_phys_chem_plot_id, plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_phys_chem_plot_unq_foi_obs') THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT result_phys_chem_plot_unq_foi_obs
            UNIQUE (plot_id, observation_phys_chem_plot_id);
    END IF;
END $$;


-- ============================================================================
-- PART 9: Add foreign key constraints for observation_phys_chem_plot (idempotent)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_property_phys_chem' AND conrelid = 'core.observation_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.observation_phys_chem_plot
            ADD CONSTRAINT fk_property_phys_chem
            FOREIGN KEY (property_phys_chem_id)
            REFERENCES core.property_phys_chem(property_phys_chem_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_procedure_phys_chem' AND conrelid = 'core.observation_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.observation_phys_chem_plot
            ADD CONSTRAINT fk_procedure_phys_chem
            FOREIGN KEY (procedure_phys_chem_id)
            REFERENCES core.procedure_phys_chem(procedure_phys_chem_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_unit_of_measure' AND conrelid = 'core.observation_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.observation_phys_chem_plot
            ADD CONSTRAINT fk_unit_of_measure
            FOREIGN KEY (unit_of_measure_id)
            REFERENCES core.unit_of_measure(unit_of_measure_id);
    END IF;
END $$;


-- ============================================================================
-- PART 10: Add foreign key constraints for result_phys_chem_plot (idempotent)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_observation_phys_chem_plot' AND conrelid = 'core.result_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT fk_observation_phys_chem_plot
            FOREIGN KEY (observation_phys_chem_plot_id)
            REFERENCES core.observation_phys_chem_plot(observation_phys_chem_plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_plot' AND conrelid = 'core.result_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT fk_plot
            FOREIGN KEY (plot_id)
            REFERENCES core.plot(plot_id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_organisation' AND conrelid = 'core.result_phys_chem_plot'::regclass) THEN
        ALTER TABLE ONLY core.result_phys_chem_plot
            ADD CONSTRAINT fk_organisation
            FOREIGN KEY (organisation_id)
            REFERENCES metadata.organisation(organisation_id);
    END IF;
END $$;


-- ============================================================================
-- PART 11: Add trigger for value validation (idempotent)
-- ============================================================================

DROP TRIGGER IF EXISTS trg_check_result_value_plot ON core.result_phys_chem_plot;
CREATE TRIGGER trg_check_result_value_plot
    BEFORE INSERT OR UPDATE ON core.result_phys_chem_plot
    FOR EACH ROW
    EXECUTE FUNCTION core.check_result_value_plot();

COMMENT ON TRIGGER trg_check_result_value_plot ON core.result_phys_chem_plot IS 'Verifies if the value assigned to the result is valid. See the function core.check_result_value_plot function for implementation.';


-- ============================================================================
-- ISO 28258 Extension: Free Text Observations and Results
-- ============================================================================
-- This extension adds support for free text observations (as opposed to
-- controlled vocabulary/thesaurus-based descriptive observations).
--
-- Use case: Properties whose values are free text, such as profile
-- descriptions, notes, or other narrative content that cannot be
-- captured by a controlled vocabulary.
--
-- Based on the pattern from WoSIS (https://github.com/ISRICWorldSoil/iso-28258/issues/14)
-- ============================================================================


-- ============================================================================
-- PART 1: Create property_text table
-- ============================================================================
-- Shared property table for text observations. Unlike descriptive properties
-- that have thesaurus values, text properties have free-form text results.

CREATE TABLE IF NOT EXISTS core.property_text (
    property_text_id integer NOT NULL,
    label character varying NOT NULL,
    uri character varying
);

COMMENT ON TABLE core.property_text IS 'A property whose observations produce free text results (as opposed to controlled vocabulary values). Used for narrative descriptions, notes, or other text content.';

COMMENT ON COLUMN core.property_text.property_text_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.property_text.label IS 'Short label for this property';

COMMENT ON COLUMN core.property_text.uri IS 'Optional URI to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';


-- ============================================================================
-- PART 2: Create sequence for property_text
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'property_text_property_text_id_seq') THEN
        CREATE SEQUENCE core.property_text_property_text_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.property_text_property_text_id_seq
            OWNED BY core.property_text.property_text_id;
    END IF;
END $$;

ALTER TABLE core.property_text
    ALTER COLUMN property_text_id
    SET DEFAULT nextval('core.property_text_property_text_id_seq'::regclass);


-- ============================================================================
-- PART 3: Create observation_text_plot table
-- ============================================================================
-- Observation definitions for plot-level text properties.

CREATE TABLE IF NOT EXISTS core.observation_text_plot (
    observation_text_plot_id integer NOT NULL,
    property_text_id integer NOT NULL
);

COMMENT ON TABLE core.observation_text_plot IS 'Text observation definitions for the Plot feature of interest. Links a text property.';

COMMENT ON COLUMN core.observation_text_plot.observation_text_plot_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.observation_text_plot.property_text_id IS 'Foreign key to the corresponding text property';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'observation_text_plot_observation_text_plot_id_seq') THEN
        CREATE SEQUENCE core.observation_text_plot_observation_text_plot_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.observation_text_plot_observation_text_plot_id_seq
            OWNED BY core.observation_text_plot.observation_text_plot_id;
    END IF;
END $$;

ALTER TABLE core.observation_text_plot
    ALTER COLUMN observation_text_plot_id
    SET DEFAULT nextval('core.observation_text_plot_observation_text_plot_id_seq'::regclass);


-- ============================================================================
-- PART 4: Create observation_text_specimen table
-- ============================================================================
-- Observation definitions for specimen-level text properties.

CREATE TABLE IF NOT EXISTS core.observation_text_specimen (
    observation_text_specimen_id integer NOT NULL,
    property_text_id integer NOT NULL
);

COMMENT ON TABLE core.observation_text_specimen IS 'Text observation definitions for the Specimen feature of interest. Links a text property.';

COMMENT ON COLUMN core.observation_text_specimen.observation_text_specimen_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.observation_text_specimen.property_text_id IS 'Foreign key to the corresponding text property';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'observation_text_specimen_observation_text_specimen_id_seq') THEN
        CREATE SEQUENCE core.observation_text_specimen_observation_text_specimen_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.observation_text_specimen_observation_text_specimen_id_seq
            OWNED BY core.observation_text_specimen.observation_text_specimen_id;
    END IF;
END $$;

ALTER TABLE core.observation_text_specimen
    ALTER COLUMN observation_text_specimen_id
    SET DEFAULT nextval('core.observation_text_specimen_observation_text_specimen_id_seq'::regclass);


-- ============================================================================
-- PART 5: Create observation_text_element table
-- ============================================================================
-- Observation definitions for element-level text properties.

CREATE TABLE IF NOT EXISTS core.observation_text_element (
    observation_text_element_id integer NOT NULL,
    property_text_id integer NOT NULL
);

COMMENT ON TABLE core.observation_text_element IS 'Text observation definitions for the Element feature of interest. Links a text property.';

COMMENT ON COLUMN core.observation_text_element.observation_text_element_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.observation_text_element.property_text_id IS 'Foreign key to the corresponding text property';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'observation_text_element_observation_text_element_id_seq') THEN
        CREATE SEQUENCE core.observation_text_element_observation_text_element_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.observation_text_element_observation_text_element_id_seq
            OWNED BY core.observation_text_element.observation_text_element_id;
    END IF;
END $$;

ALTER TABLE core.observation_text_element
    ALTER COLUMN observation_text_element_id
    SET DEFAULT nextval('core.observation_text_element_observation_text_element_id_seq'::regclass);


-- ============================================================================
-- PART 6: Create result_text_plot table
-- ============================================================================
-- Stores free text results for plots.

CREATE TABLE IF NOT EXISTS core.result_text_plot (
    result_text_plot_id integer NOT NULL,
    observation_text_plot_id integer NOT NULL,
    plot_id integer NOT NULL,
    value text NOT NULL
);

COMMENT ON TABLE core.result_text_plot IS 'Free text results for the Plot feature of interest.';

COMMENT ON COLUMN core.result_text_plot.result_text_plot_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.result_text_plot.observation_text_plot_id IS 'Foreign key to the corresponding text observation';

COMMENT ON COLUMN core.result_text_plot.plot_id IS 'Foreign key to the corresponding Plot instance';

COMMENT ON COLUMN core.result_text_plot.value IS 'The free text result value';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'result_text_plot_result_text_plot_id_seq') THEN
        CREATE SEQUENCE core.result_text_plot_result_text_plot_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.result_text_plot_result_text_plot_id_seq
            OWNED BY core.result_text_plot.result_text_plot_id;
    END IF;
END $$;

ALTER TABLE core.result_text_plot
    ALTER COLUMN result_text_plot_id
    SET DEFAULT nextval('core.result_text_plot_result_text_plot_id_seq'::regclass);


-- ============================================================================
-- PART 7: Create result_text_specimen table
-- ============================================================================
-- Stores free text results for specimens.

CREATE TABLE IF NOT EXISTS core.result_text_specimen (
    result_text_specimen_id integer NOT NULL,
    observation_text_specimen_id integer NOT NULL,
    specimen_id integer NOT NULL,
    value text NOT NULL
);

COMMENT ON TABLE core.result_text_specimen IS 'Free text results for the Specimen feature of interest.';

COMMENT ON COLUMN core.result_text_specimen.result_text_specimen_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.result_text_specimen.observation_text_specimen_id IS 'Foreign key to the corresponding text observation';

COMMENT ON COLUMN core.result_text_specimen.specimen_id IS 'Foreign key to the corresponding Specimen instance';

COMMENT ON COLUMN core.result_text_specimen.value IS 'The free text result value';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'result_text_specimen_result_text_specimen_id_seq') THEN
        CREATE SEQUENCE core.result_text_specimen_result_text_specimen_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.result_text_specimen_result_text_specimen_id_seq
            OWNED BY core.result_text_specimen.result_text_specimen_id;
    END IF;
END $$;

ALTER TABLE core.result_text_specimen
    ALTER COLUMN result_text_specimen_id
    SET DEFAULT nextval('core.result_text_specimen_result_text_specimen_id_seq'::regclass);


-- ============================================================================
-- PART 8: Create result_text_element table
-- ============================================================================
-- Stores free text results for elements.

CREATE TABLE IF NOT EXISTS core.result_text_element (
    result_text_element_id integer NOT NULL,
    observation_text_element_id integer NOT NULL,
    element_id integer NOT NULL,
    value text NOT NULL
);

COMMENT ON TABLE core.result_text_element IS 'Free text results for the Element feature of interest.';

COMMENT ON COLUMN core.result_text_element.result_text_element_id IS 'Synthetic primary key';

COMMENT ON COLUMN core.result_text_element.observation_text_element_id IS 'Foreign key to the corresponding text observation';

COMMENT ON COLUMN core.result_text_element.element_id IS 'Foreign key to the corresponding Element instance';

COMMENT ON COLUMN core.result_text_element.value IS 'The free text result value';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'core' AND sequencename = 'result_text_element_result_text_element_id_seq') THEN
        CREATE SEQUENCE core.result_text_element_result_text_element_id_seq
            AS integer
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;

        ALTER SEQUENCE core.result_text_element_result_text_element_id_seq
            OWNED BY core.result_text_element.result_text_element_id;
    END IF;
END $$;

ALTER TABLE core.result_text_element
    ALTER COLUMN result_text_element_id
    SET DEFAULT nextval('core.result_text_element_result_text_element_id_seq'::regclass);


-- ============================================================================
-- PART 9: Add primary key constraints (idempotent)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'property_text_pkey') THEN
        ALTER TABLE ONLY core.property_text
            ADD CONSTRAINT property_text_pkey
            PRIMARY KEY (property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'observation_text_plot_pkey') THEN
        ALTER TABLE ONLY core.observation_text_plot
            ADD CONSTRAINT observation_text_plot_pkey
            PRIMARY KEY (observation_text_plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'observation_text_specimen_pkey') THEN
        ALTER TABLE ONLY core.observation_text_specimen
            ADD CONSTRAINT observation_text_specimen_pkey
            PRIMARY KEY (observation_text_specimen_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'observation_text_element_pkey') THEN
        ALTER TABLE ONLY core.observation_text_element
            ADD CONSTRAINT observation_text_element_pkey
            PRIMARY KEY (observation_text_element_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_text_plot_pkey') THEN
        ALTER TABLE ONLY core.result_text_plot
            ADD CONSTRAINT result_text_plot_pkey
            PRIMARY KEY (result_text_plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_text_specimen_pkey') THEN
        ALTER TABLE ONLY core.result_text_specimen
            ADD CONSTRAINT result_text_specimen_pkey
            PRIMARY KEY (result_text_specimen_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'result_text_element_pkey') THEN
        ALTER TABLE ONLY core.result_text_element
            ADD CONSTRAINT result_text_element_pkey
            PRIMARY KEY (result_text_element_id);
    END IF;
END $$;


-- ============================================================================
-- PART 10: Add unique constraints (idempotent)
-- ============================================================================
-- Each property label and URI must be unique.
-- Each observation (property) must be unique per entity type.
-- Each result (observation + foi) must be unique.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_property_text_label') THEN
        ALTER TABLE ONLY core.property_text
            ADD CONSTRAINT unq_property_text_label UNIQUE (label);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_property_text_uri') THEN
        ALTER TABLE ONLY core.property_text
            ADD CONSTRAINT unq_property_text_uri UNIQUE (uri);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_observation_text_plot_property') THEN
        ALTER TABLE ONLY core.observation_text_plot
            ADD CONSTRAINT unq_observation_text_plot_property UNIQUE (property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_observation_text_specimen_property') THEN
        ALTER TABLE ONLY core.observation_text_specimen
            ADD CONSTRAINT unq_observation_text_specimen_property UNIQUE (property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_observation_text_element_property') THEN
        ALTER TABLE ONLY core.observation_text_element
            ADD CONSTRAINT unq_observation_text_element_property UNIQUE (property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_result_text_plot') THEN
        ALTER TABLE ONLY core.result_text_plot
            ADD CONSTRAINT unq_result_text_plot UNIQUE (observation_text_plot_id, plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_result_text_specimen') THEN
        ALTER TABLE ONLY core.result_text_specimen
            ADD CONSTRAINT unq_result_text_specimen UNIQUE (observation_text_specimen_id, specimen_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unq_result_text_element') THEN
        ALTER TABLE ONLY core.result_text_element
            ADD CONSTRAINT unq_result_text_element UNIQUE (observation_text_element_id, element_id);
    END IF;
END $$;


-- ============================================================================
-- PART 11: Add foreign key constraints (idempotent)
-- ============================================================================

DO $$
BEGIN
    -- property_text -> observation_text_* foreign keys
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_property_text' AND conrelid = 'core.observation_text_plot'::regclass) THEN
        ALTER TABLE ONLY core.observation_text_plot
            ADD CONSTRAINT fk_property_text
            FOREIGN KEY (property_text_id)
            REFERENCES core.property_text(property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_property_text' AND conrelid = 'core.observation_text_specimen'::regclass) THEN
        ALTER TABLE ONLY core.observation_text_specimen
            ADD CONSTRAINT fk_property_text
            FOREIGN KEY (property_text_id)
            REFERENCES core.property_text(property_text_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_property_text' AND conrelid = 'core.observation_text_element'::regclass) THEN
        ALTER TABLE ONLY core.observation_text_element
            ADD CONSTRAINT fk_property_text
            FOREIGN KEY (property_text_id)
            REFERENCES core.property_text(property_text_id);
    END IF;

    -- result_text_* -> observation_text_* foreign keys
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_observation_text_plot' AND conrelid = 'core.result_text_plot'::regclass) THEN
        ALTER TABLE ONLY core.result_text_plot
            ADD CONSTRAINT fk_observation_text_plot
            FOREIGN KEY (observation_text_plot_id)
            REFERENCES core.observation_text_plot(observation_text_plot_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_observation_text_specimen' AND conrelid = 'core.result_text_specimen'::regclass) THEN
        ALTER TABLE ONLY core.result_text_specimen
            ADD CONSTRAINT fk_observation_text_specimen
            FOREIGN KEY (observation_text_specimen_id)
            REFERENCES core.observation_text_specimen(observation_text_specimen_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_observation_text_element' AND conrelid = 'core.result_text_element'::regclass) THEN
        ALTER TABLE ONLY core.result_text_element
            ADD CONSTRAINT fk_observation_text_element
            FOREIGN KEY (observation_text_element_id)
            REFERENCES core.observation_text_element(observation_text_element_id);
    END IF;

    -- result_text_* -> foi foreign keys (with CASCADE delete)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_plot' AND conrelid = 'core.result_text_plot'::regclass) THEN
        ALTER TABLE ONLY core.result_text_plot
            ADD CONSTRAINT fk_plot
            FOREIGN KEY (plot_id)
            REFERENCES core.plot(plot_id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_specimen' AND conrelid = 'core.result_text_specimen'::regclass) THEN
        ALTER TABLE ONLY core.result_text_specimen
            ADD CONSTRAINT fk_specimen
            FOREIGN KEY (specimen_id)
            REFERENCES core.specimen(specimen_id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_element' AND conrelid = 'core.result_text_element'::regclass) THEN
        ALTER TABLE ONLY core.result_text_element
            ADD CONSTRAINT fk_element
            FOREIGN KEY (element_id)
            REFERENCES core.element(element_id)
            ON DELETE CASCADE;
    END IF;
END $$;

-- ============================================================================
-- PART 12: Create ETL helper functions (idempotent)
-- ============================================================================
-- Functions to simplify inserting text results via the ETL.

-- ETL function for plot text results
DROP FUNCTION IF EXISTS core.etl_insert_result_text_plot(integer, text, text);
CREATE FUNCTION core.etl_insert_result_text_plot(
    plot_id integer,
    property_uri text,
    value text
) RETURNS core.result_text_plot
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

COMMENT ON FUNCTION core.etl_insert_result_text_plot(integer, text, text) IS
'Inserts a free text result for a plot. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


-- ETL function for specimen text results
DROP FUNCTION IF EXISTS core.etl_insert_result_text_specimen(integer, text, text);
CREATE FUNCTION core.etl_insert_result_text_specimen(
    specimen_id integer,
    property_uri text,
    value text
) RETURNS core.result_text_specimen
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

COMMENT ON FUNCTION core.etl_insert_result_text_specimen(integer, text, text) IS
'Inserts a free text result for a specimen. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


-- ETL function for element text results
DROP FUNCTION IF EXISTS core.etl_insert_result_text_element(integer, text, text);
CREATE FUNCTION core.etl_insert_result_text_element(
    element_id integer,
    property_uri text,
    value text
) RETURNS core.result_text_element
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

COMMENT ON FUNCTION core.etl_insert_result_text_element(integer, text, text) IS
'Inserts a free text result for an element. Looks up the observation by property URI.
Returns the inserted record or nothing if it already exists.';


-- ============================================================================
-- PART 13: Schema changes for property_desc_specimen and property_desc_element
-- ============================================================================
-- Rename 'definition' column to 'uri' for consistency with property_desc_plot.
-- This allows using URI-based lookup in ETL, matching the pattern used elsewhere.
-- Made idempotent: only renames if 'definition' column still exists.

-- Rename definition to uri in property_desc_specimen (idempotent)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core'
        AND table_name = 'property_desc_specimen'
        AND column_name = 'definition'
    ) THEN
        ALTER TABLE core.property_desc_specimen RENAME COLUMN definition TO uri;
    END IF;
END $$;

COMMENT ON COLUMN core.property_desc_specimen.uri IS
'URI reference to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';

-- Rename definition to uri in property_desc_element (idempotent)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core'
        AND table_name = 'property_desc_element'
        AND column_name = 'definition'
    ) THEN
        ALTER TABLE core.property_desc_element RENAME COLUMN definition TO uri;
    END IF;
END $$;

COMMENT ON COLUMN core.property_desc_element.uri IS
'URI reference to a corresponding code in a controlled vocabulary (e.g., GloSIS). Follow this URI for the full definition and semantics of this property.';


-- ============================================================================
-- PART 14: Create ETL helper functions for descriptive results (specimen/element)
-- ============================================================================
-- These functions simplify inserting descriptive results via the ETL.
-- Now uses URI matching, consistent with property_desc_plot pattern.

-- ETL function for specimen descriptive results
DROP FUNCTION IF EXISTS core.etl_insert_result_desc_specimen(integer, text, text);
CREATE FUNCTION core.etl_insert_result_desc_specimen(
    specimen_id integer,
    property_uri text,
    thesaurus_label text
) RETURNS core.result_desc_specimen
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

COMMENT ON FUNCTION core.etl_insert_result_desc_specimen(integer, text, text) IS
'Inserts a descriptive result for a specimen. Looks up the observation by property URI
and thesaurus value label. Returns the inserted record or nothing if it already exists.';


-- ETL function for element descriptive results
DROP FUNCTION IF EXISTS core.etl_insert_result_desc_element(integer, text, text);
CREATE FUNCTION core.etl_insert_result_desc_element(
    element_id integer,
    property_uri text,
    thesaurus_label text
) RETURNS core.result_desc_element
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

COMMENT ON FUNCTION core.etl_insert_result_desc_element(integer, text, text) IS
'Inserts a descriptive result for an element. Looks up the observation by property URI
and thesaurus value label. Returns the inserted record or nothing if it already exists.';
