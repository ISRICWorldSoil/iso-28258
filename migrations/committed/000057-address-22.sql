--! Previous: sha1:09797b9d01fe7f7cd1698dbb22c6d82064441997
--! Hash: sha1:8c35e35e041ce55fc4f1a16bca1553c0bbd269b2
--! Message: address #22

-- ============================================================
-- safe_parse_date_ddmmyyyy
-- Helper function to safely parse dates in DD/MM/YYYY format
-- Returns NULL for invalid dates (e.g., month > 12) instead of raising an error
-- ============================================================
DROP FUNCTION IF EXISTS core.safe_parse_date_ddmmyyyy(text);
CREATE OR REPLACE FUNCTION core.safe_parse_date_ddmmyyyy(ts text)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
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
$$;

COMMENT ON FUNCTION core.safe_parse_date_ddmmyyyy(ts text)
IS 'Safely parse a date string in DD/MM/YYYY format. Returns NULL for invalid or unparseable dates instead of raising an error. Useful for bulk ETL operations where date format may vary.';


-- ============================================================
-- etl_insert_plot (updated to use safe_parse_date_ddmmyyyy helper)
-- Simplified version that uses the helper function for date parsing
-- ============================================================
DROP FUNCTION IF EXISTS core.etl_insert_plot(text, integer, numeric, text, text, numeric, text, text);
CREATE OR REPLACE FUNCTION core.etl_insert_plot(
    plot_code text,
    site_id integer,
    altitude numeric,
    time_stamp text,
    map_sheet_code text,
    positional_accuracy numeric,
    latitude text,
    longitude text
)
RETURNS core.plot
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

COMMENT ON FUNCTION core.etl_insert_plot(text, integer, numeric, text, text, numeric, text, text)
IS 'Insert a new plot into the core.plot table. Uses safe_parse_date_ddmmyyyy for date parsing. If the plot already exists, it returns NULL.';
