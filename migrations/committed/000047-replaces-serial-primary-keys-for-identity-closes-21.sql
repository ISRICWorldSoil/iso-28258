--! Previous: sha1:d01fa494cdb9a27ccd377a8d304fd35daaac9b1c
--! Hash: sha1:0fd9b97a305a2836215a416053816366ebe20b57
--! Message: Replaces serial primary keys for identity (closes #21)

-- Enter migration here

-- element

ALTER TABLE core.result_phys_chem DROP CONSTRAINT IF EXISTS fk_element;
ALTER TABLE core.result_desc_element DROP CONSTRAINT IF EXISTS fk_element;

ALTER TABLE core.element DROP COLUMN IF EXISTS element_id;
ALTER TABLE core.element ADD COLUMN element_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.element.element_id IS 'Synthetic primary key.';

ALTER TABLE core.result_phys_chem 
  ADD CONSTRAINT fk_element FOREIGN KEY (element_id)
      REFERENCES core.element (element_id);

ALTER TABLE core.result_desc_element    
  ADD CONSTRAINT fk_element FOREIGN KEY (element_id)
      REFERENCES core.element (element_id);

-- plot

ALTER TABLE core.specimen DROP CONSTRAINT IF EXISTS fk_plot;
ALTER TABLE core.plot_individual DROP CONSTRAINT IF EXISTS fk_plot;
ALTER TABLE core.profile DROP CONSTRAINT IF EXISTS fk_plot_id;
ALTER TABLE core.profile DROP CONSTRAINT IF EXISTS fk_plot;
ALTER TABLE core.result_desc_plot DROP CONSTRAINT IF EXISTS fk_plot;

ALTER TABLE core.plot DROP COLUMN IF EXISTS plot_id;
ALTER TABLE core.plot ADD COLUMN plot_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.plot.plot_id IS 'Synthetic primary key.';

ALTER TABLE core.specimen 
  ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id)
      REFERENCES core.plot (plot_id);

ALTER TABLE core.plot_individual    
  ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id)
      REFERENCES core.plot (plot_id);

ALTER TABLE core.profile
  ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id)
      REFERENCES core.plot (plot_id);

ALTER TABLE core.result_desc_plot    
  ADD CONSTRAINT fk_plot FOREIGN KEY (plot_id)
      REFERENCES core.plot (plot_id);

-- procedure_desc

ALTER TABLE core.observation_desc_element DROP CONSTRAINT IF EXISTS fk_procedure_desc;
ALTER TABLE core.observation_desc_plot DROP CONSTRAINT IF EXISTS fk_procedure_desc;
ALTER TABLE core.observation_desc_profile DROP CONSTRAINT IF EXISTS fk_procedure_desc;
ALTER TABLE core.observation_desc_specimen DROP CONSTRAINT IF EXISTS fk_procedure_desc;
ALTER TABLE core.observation_desc_surface DROP CONSTRAINT IF EXISTS fk_procedure_desc;

ALTER TABLE core.procedure_desc DROP CONSTRAINT IF EXISTS procedure_desc_pkey;
ALTER TABLE core.procedure_desc RENAME COLUMN procedure_desc_id TO procedure_desc_id_old;
ALTER TABLE core.procedure_desc ADD COLUMN procedure_desc_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.procedure_desc.procedure_desc_id IS 'Synthetic primary key.';

UPDATE core.procedure_desc
   SET procedure_desc_id = procedure_desc_id_old;

ALTER TABLE core.procedure_desc DROP COLUMN IF EXISTS procedure_desc_id_old;
ALTER TABLE core.procedure_desc
  ADD CONSTRAINT procedure_desc_pkey PRIMARY KEY (procedure_desc_id);

ALTER TABLE core.observation_desc_element 
  ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id)
      REFERENCES core.procedure_desc (procedure_desc_id);

ALTER TABLE core.observation_desc_plot    
  ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id)
      REFERENCES core.procedure_desc (procedure_desc_id);

ALTER TABLE core.observation_desc_profile    
  ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id)
      REFERENCES core.procedure_desc (procedure_desc_id);

ALTER TABLE core.observation_desc_specimen 
  ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id)
      REFERENCES core.procedure_desc (procedure_desc_id);

ALTER TABLE core.observation_desc_surface
  ADD CONSTRAINT fk_procedure_desc FOREIGN KEY (procedure_desc_id)
      REFERENCES core.procedure_desc (procedure_desc_id);

-- procedure_numerical_specimen

ALTER TABLE core.procedure_numerical_specimen DROP CONSTRAINT IF EXISTS fk_broader;
ALTER TABLE core.observation_numerical_specimen DROP CONSTRAINT IF EXISTS fk_procedure_numerical_specimen;

ALTER TABLE core.procedure_numerical_specimen DROP COLUMN IF EXISTS procedure_numerical_specimen_id;
ALTER TABLE core.procedure_numerical_specimen ADD COLUMN procedure_numerical_specimen_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.procedure_numerical_specimen.procedure_numerical_specimen_id IS 'Synthetic primary key.';

ALTER TABLE core.procedure_numerical_specimen
  ADD CONSTRAINT fk_broader FOREIGN KEY (broader_id)
      REFERENCES core.procedure_numerical_specimen (procedure_numerical_specimen_id);

ALTER TABLE core.observation_numerical_specimen    
  ADD CONSTRAINT fk_procedure_numerical_specimen FOREIGN KEY (procedure_numerical_specimen_id)
      REFERENCES core.procedure_numerical_specimen (procedure_numerical_specimen_id);

-- procedure_phys_chem

ALTER TABLE core.observation_phys_chem DROP CONSTRAINT IF EXISTS fk_procedure_phys_chem;

ALTER TABLE core.procedure_phys_chem DROP CONSTRAINT IF EXISTS fk_broader;
ALTER TABLE core.procedure_phys_chem DROP CONSTRAINT IF EXISTS procedure_phys_chem_pkey;

ALTER TABLE core.procedure_phys_chem RENAME COLUMN procedure_phys_chem_id TO procedure_phys_chem_id_old;

ALTER TABLE core.procedure_phys_chem ADD COLUMN procedure_phys_chem_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.procedure_phys_chem.procedure_phys_chem_id IS 'Synthetic primary key.';

UPDATE core.procedure_phys_chem
   SET procedure_phys_chem_id = procedure_phys_chem_id_old;

ALTER TABLE core.procedure_phys_chem DROP COLUMN IF EXISTS procedure_phys_chem_id_old;

ALTER TABLE core.procedure_phys_chem
  ADD CONSTRAINT procedure_phys_chem_pkey PRIMARY KEY (procedure_phys_chem_id);

ALTER TABLE core.procedure_phys_chem 
  ADD CONSTRAINT fk_broader FOREIGN KEY (broader_id)
      REFERENCES core.procedure_phys_chem (procedure_phys_chem_id);

ALTER TABLE core.observation_phys_chem    
  ADD CONSTRAINT fk_procedure_phys_chem FOREIGN KEY (procedure_phys_chem_id)
      REFERENCES core.procedure_phys_chem (procedure_phys_chem_id);

-- profile

ALTER TABLE core.element DROP CONSTRAINT IF EXISTS fk_profile;
ALTER TABLE core.result_desc_profile DROP CONSTRAINT IF EXISTS fk_profile;
ALTER TABLE core.site DROP CONSTRAINT IF EXISTS fk_profile;
ALTER TABLE core.site DROP CONSTRAINT IF EXISTS country_geom_country_id_fkey;

ALTER TABLE core.profile DROP COLUMN IF EXISTS profile_id;
ALTER TABLE core.profile ADD COLUMN profile_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.profile.profile_id IS 'Synthetic primary key.';

ALTER TABLE core.element 
  ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id)
      REFERENCES core.profile (profile_id);

ALTER TABLE core.result_desc_profile    
  ADD CONSTRAINT fk_profile FOREIGN KEY (profile_id)
      REFERENCES core.profile (profile_id);

ALTER TABLE core.site
  ADD CONSTRAINT fk_profile FOREIGN KEY (typical_profile)
      REFERENCES core.profile (profile_id);

-- project

ALTER TABLE core.site_project DROP CONSTRAINT IF EXISTS fk_project;
ALTER TABLE core.project_related DROP CONSTRAINT IF EXISTS fk_project_source;
ALTER TABLE core.project_related DROP CONSTRAINT IF EXISTS fk_project_target;

ALTER TABLE core.project DROP COLUMN IF EXISTS project_id;
ALTER TABLE core.project ADD COLUMN project_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.project.project_id IS 'Synthetic primary key.';

ALTER TABLE core.site_project 
  ADD CONSTRAINT fk_project FOREIGN KEY (project_id)
      REFERENCES core.project (project_id);

ALTER TABLE core.project_related
  ADD CONSTRAINT fk_project_source FOREIGN KEY (project_source_id)
        REFERENCES core.project (project_id);    
        
ALTER TABLE core.project_related
  ADD CONSTRAINT fk_project_target FOREIGN KEY (project_target_id)
        REFERENCES core.project (project_id);    

-- property_desc_element

ALTER TABLE core.observation_desc_element DROP CONSTRAINT IF EXISTS fk_property_desc_element;

ALTER TABLE core.property_desc_element DROP CONSTRAINT IF EXISTS property_desc_element_pkey;
ALTER TABLE core.property_desc_element RENAME COLUMN property_desc_element_id TO property_desc_element_id_old;
ALTER TABLE core.property_desc_element ADD COLUMN property_desc_element_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_desc_element.property_desc_element_id IS 'Synthetic primary key.';

UPDATE core.property_desc_element
   SET property_desc_element_id = property_desc_element_id_old;

ALTER TABLE core.property_desc_element DROP COLUMN IF EXISTS property_desc_element_id_old;
ALTER TABLE core.property_desc_element
  ADD CONSTRAINT property_desc_element_pkey PRIMARY KEY (property_desc_element_id);

ALTER TABLE core.observation_desc_element    
  ADD CONSTRAINT fk_property_desc_element FOREIGN KEY (property_desc_element_id)
      REFERENCES core.property_desc_element (property_desc_element_id);

-- property_desc_plot

ALTER TABLE core.observation_desc_plot DROP CONSTRAINT IF EXISTS fk_property_desc_plot;

ALTER TABLE core.property_desc_plot DROP CONSTRAINT IF EXISTS property_desc_plot_pkey;
ALTER TABLE core.property_desc_plot RENAME COLUMN property_desc_plot_id TO property_desc_plot_id_old;
ALTER TABLE core.property_desc_plot ADD COLUMN property_desc_plot_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_desc_plot.property_desc_plot_id IS 'Synthetic primary key.';

UPDATE core.property_desc_plot
   SET property_desc_plot_id = property_desc_plot_id_old;

ALTER TABLE core.property_desc_plot DROP COLUMN IF EXISTS property_desc_plot_id_old;
ALTER TABLE core.property_desc_plot
  ADD CONSTRAINT property_desc_plot_pkey PRIMARY KEY (property_desc_plot_id);

ALTER TABLE core.observation_desc_plot    
  ADD CONSTRAINT fk_property_desc_plot FOREIGN KEY (property_desc_plot_id)
      REFERENCES core.property_desc_plot (property_desc_plot_id);

-- property_desc_profile

ALTER TABLE core.observation_desc_profile DROP CONSTRAINT IF EXISTS fk_property_desc_profile;

ALTER TABLE core.property_desc_profile DROP CONSTRAINT IF EXISTS property_desc_profile_pkey;
ALTER TABLE core.property_desc_profile RENAME COLUMN property_desc_profile_id TO property_desc_profile_id_old;
ALTER TABLE core.property_desc_profile ADD COLUMN property_desc_profile_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_desc_profile.property_desc_profile_id IS 'Synthetic primary key.';

UPDATE core.property_desc_profile
   SET property_desc_profile_id = property_desc_profile_id_old;

ALTER TABLE core.property_desc_profile DROP COLUMN IF EXISTS property_desc_profile_id_old;
ALTER TABLE core.property_desc_profile
  ADD CONSTRAINT property_desc_profile_pkey PRIMARY KEY (property_desc_profile_id);

ALTER TABLE core.observation_desc_profile    
  ADD CONSTRAINT fk_property_desc_profile FOREIGN KEY (property_desc_profile_id)
      REFERENCES core.property_desc_profile (property_desc_profile_id);

-- property_desc_specimen

ALTER TABLE core.observation_desc_specimen DROP CONSTRAINT IF EXISTS fk_property_desc_specimen;

ALTER TABLE core.property_desc_specimen DROP CONSTRAINT IF EXISTS property_desc_specimen_pkey;
ALTER TABLE core.property_desc_specimen RENAME COLUMN property_desc_specimen_id TO property_desc_specimen_id_old;
ALTER TABLE core.property_desc_specimen ADD COLUMN property_desc_specimen_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_desc_specimen.property_desc_specimen_id IS 'Synthetic primary key.';

UPDATE core.property_desc_specimen
   SET property_desc_specimen_id = property_desc_specimen_id_old;

ALTER TABLE core.property_desc_specimen DROP COLUMN IF EXISTS property_desc_specimen_id_old;
ALTER TABLE core.property_desc_specimen
  ADD CONSTRAINT property_desc_specimen_pkey PRIMARY KEY (property_desc_specimen_id);

ALTER TABLE core.observation_desc_specimen    
  ADD CONSTRAINT fk_property_desc_specimen FOREIGN KEY (property_desc_specimen_id)
      REFERENCES core.property_desc_specimen (property_desc_specimen_id);

-- property_desc_surface

ALTER TABLE core.observation_desc_surface DROP CONSTRAINT IF EXISTS fk_property_desc_surface;

ALTER TABLE core.property_desc_surface DROP CONSTRAINT IF EXISTS property_desc_surface_pkey;
ALTER TABLE core.property_desc_surface RENAME COLUMN property_desc_surface_id TO property_desc_surface_id_old;
ALTER TABLE core.property_desc_surface ADD COLUMN property_desc_surface_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_desc_surface.property_desc_surface_id IS 'Synthetic primary key.';

UPDATE core.property_desc_surface
   SET property_desc_surface_id = property_desc_surface_id_old;

ALTER TABLE core.property_desc_surface DROP COLUMN IF EXISTS property_desc_surface_id_old;
ALTER TABLE core.property_desc_surface
  ADD CONSTRAINT property_desc_surface_pkey PRIMARY KEY (property_desc_surface_id);

ALTER TABLE core.observation_desc_surface    
  ADD CONSTRAINT fk_property_desc_surface FOREIGN KEY (property_desc_surface_id)
      REFERENCES core.property_desc_surface (property_desc_surface_id);

-- property_phys_chem

ALTER TABLE core.observation_phys_chem DROP CONSTRAINT IF EXISTS fk_property_phys_chem;

ALTER TABLE core.property_phys_chem DROP CONSTRAINT IF EXISTS property_phys_chem_pkey;

ALTER TABLE core.property_phys_chem RENAME COLUMN property_phys_chem_id TO property_phys_chem_id_old;

ALTER TABLE core.property_phys_chem ADD COLUMN property_phys_chem_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.property_phys_chem.property_phys_chem_id IS 'Synthetic primary key.';

UPDATE core.property_phys_chem
   SET property_phys_chem_id = property_phys_chem_id_old;

ALTER TABLE core.property_phys_chem DROP COLUMN IF EXISTS property_phys_chem_id_old;

ALTER TABLE core.property_phys_chem
  ADD CONSTRAINT property_phys_chem_pkey PRIMARY KEY (property_phys_chem_id);

ALTER TABLE core.observation_phys_chem    
  ADD CONSTRAINT fk_property_phys_chem FOREIGN KEY (property_phys_chem_id)
      REFERENCES core.property_phys_chem (property_phys_chem_id);

-- site

ALTER TABLE core.surface DROP CONSTRAINT IF EXISTS fk_site;
ALTER TABLE core.plot DROP CONSTRAINT IF EXISTS fk_site;
ALTER TABLE core.site_project DROP CONSTRAINT IF EXISTS fk_site;

ALTER TABLE core.site DROP COLUMN IF EXISTS site_id;
ALTER TABLE core.site ADD COLUMN site_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.site.site_id IS 'Synthetic primary key.';

ALTER TABLE core.surface
  ADD CONSTRAINT fk_site FOREIGN KEY (site_id)
      REFERENCES core.site (site_id);

ALTER TABLE core.plot
  ADD CONSTRAINT fk_site FOREIGN KEY (site_id)
      REFERENCES core.site (site_id);

ALTER TABLE core.site_project
  ADD CONSTRAINT fk_site FOREIGN KEY (site_id)
      REFERENCES core.site (site_id);

-- specimen

ALTER TABLE core.result_desc_specimen DROP CONSTRAINT IF EXISTS fk_specimen;
ALTER TABLE core.result_numerical_specimen DROP CONSTRAINT IF EXISTS fk_specimen;

ALTER TABLE core.specimen DROP COLUMN IF EXISTS specimen_id;
ALTER TABLE core.specimen ADD COLUMN specimen_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.specimen.specimen_id IS 'Synthetic primary key.';

ALTER TABLE core.result_desc_specimen
  ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id)
      REFERENCES core.specimen (specimen_id);

ALTER TABLE core.result_numerical_specimen
  ADD CONSTRAINT fk_specimen FOREIGN KEY (specimen_id)
      REFERENCES core.specimen (specimen_id);

-- specimen_prep_process

ALTER TABLE core.specimen DROP CONSTRAINT IF EXISTS fk_specimen_prep_process;

ALTER TABLE core.specimen_prep_process DROP COLUMN IF EXISTS specimen_prep_process_id;
ALTER TABLE core.specimen_prep_process ADD COLUMN specimen_prep_process_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.specimen_prep_process.specimen_prep_process_id IS 'Synthetic primary key.';

ALTER TABLE core.specimen
  ADD CONSTRAINT fk_specimen_prep_process FOREIGN KEY (specimen_prep_process_id)
      REFERENCES core.specimen_prep_process (specimen_prep_process_id);

-- specimen_storage

ALTER TABLE core.specimen_prep_process DROP CONSTRAINT IF EXISTS fk_specimen_storage;

ALTER TABLE core.specimen_storage DROP COLUMN IF EXISTS specimen_storage_id;
ALTER TABLE core.specimen_storage ADD COLUMN specimen_storage_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.specimen_storage.specimen_storage_id IS 'Synthetic primary key.';

ALTER TABLE core.specimen_prep_process
  ADD CONSTRAINT fk_specimen_storage FOREIGN KEY (specimen_storage_id)
      REFERENCES core.specimen_storage (specimen_storage_id);

-- specimen_transport

ALTER TABLE core.specimen_prep_process DROP CONSTRAINT IF EXISTS fk_specimen_transport;

ALTER TABLE core.specimen_transport DROP COLUMN IF EXISTS specimen_transport_id;
ALTER TABLE core.specimen_transport ADD COLUMN specimen_transport_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.specimen_transport.specimen_transport_id IS 'Synthetic primary key.';

ALTER TABLE core.specimen_prep_process
  ADD CONSTRAINT fk_specimen_transport FOREIGN KEY (specimen_transport_id)
      REFERENCES core.specimen_transport (specimen_transport_id);

-- surface

ALTER TABLE core.profile DROP CONSTRAINT IF EXISTS fk_surface;
ALTER TABLE core.profile DROP CONSTRAINT IF EXISTS fk_surface_id;
ALTER TABLE core.result_desc_surface DROP CONSTRAINT IF EXISTS fk_surface;
ALTER TABLE core.surface_individual DROP CONSTRAINT IF EXISTS fk_surface;
ALTER TABLE core.surface DROP CONSTRAINT IF EXISTS unq_surface_super;
ALTER TABLE core.surface DROP CONSTRAINT IF EXISTS fk_surface;

ALTER TABLE core.surface DROP COLUMN IF EXISTS surface_id;
ALTER TABLE core.surface ADD COLUMN surface_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN core.surface.surface_id IS 'Synthetic primary key.';

ALTER TABLE core.profile
  ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id)
      REFERENCES core.surface (surface_id);

ALTER TABLE core.result_desc_surface
  ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id)
      REFERENCES core.surface (surface_id);

ALTER TABLE core.surface_individual
  ADD CONSTRAINT fk_surface FOREIGN KEY (surface_id)
      REFERENCES core.surface (surface_id);

ALTER TABLE core.surface
  ADD CONSTRAINT fk_surface FOREIGN KEY (super_surface_id)
        REFERENCES core.surface (surface_id);

ALTER TABLE core.surface
  ADD CONSTRAINT unq_surface_super UNIQUE (surface_id, super_surface_id);       

-- thesaurus_desc_element

ALTER TABLE core.observation_desc_element DROP CONSTRAINT IF EXISTS fk_thesaurus_desc_element;

ALTER TABLE core.thesaurus_desc_element DROP CONSTRAINT IF EXISTS thesaurus_desc_element_pkey;
ALTER TABLE core.thesaurus_desc_element RENAME COLUMN thesaurus_desc_element_id TO thesaurus_desc_element_id_old;
ALTER TABLE core.thesaurus_desc_element ADD COLUMN thesaurus_desc_element_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.thesaurus_desc_element.thesaurus_desc_element_id IS 'Synthetic primary key.';

UPDATE core.thesaurus_desc_element
   SET thesaurus_desc_element_id = thesaurus_desc_element_id_old;

ALTER TABLE core.thesaurus_desc_element DROP COLUMN IF EXISTS thesaurus_desc_element_id_old;
ALTER TABLE core.thesaurus_desc_element
  ADD CONSTRAINT thesaurus_desc_element_pkey PRIMARY KEY (thesaurus_desc_element_id);

ALTER TABLE core.observation_desc_element    
  ADD CONSTRAINT fk_thesaurus_desc_element FOREIGN KEY (thesaurus_desc_element_id)
      REFERENCES core.thesaurus_desc_element (thesaurus_desc_element_id);

-- thesaurus_desc_plot

ALTER TABLE core.observation_desc_plot DROP CONSTRAINT IF EXISTS fk_thesaurus_desc_plot;

ALTER TABLE core.thesaurus_desc_plot DROP CONSTRAINT IF EXISTS thesaurus_desc_plot_pkey;
ALTER TABLE core.thesaurus_desc_plot RENAME COLUMN thesaurus_desc_plot_id TO thesaurus_desc_plot_id_old;
ALTER TABLE core.thesaurus_desc_plot ADD COLUMN thesaurus_desc_plot_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.thesaurus_desc_plot.thesaurus_desc_plot_id IS 'Synthetic primary key.';

UPDATE core.thesaurus_desc_plot
   SET thesaurus_desc_plot_id = thesaurus_desc_plot_id_old;

ALTER TABLE core.thesaurus_desc_plot DROP COLUMN IF EXISTS thesaurus_desc_plot_id_old;
ALTER TABLE core.thesaurus_desc_plot
  ADD CONSTRAINT thesaurus_desc_plot_pkey PRIMARY KEY (thesaurus_desc_plot_id);

ALTER TABLE core.observation_desc_plot    
  ADD CONSTRAINT fk_thesaurus_desc_plot FOREIGN KEY (thesaurus_desc_plot_id)
      REFERENCES core.thesaurus_desc_plot (thesaurus_desc_plot_id);

-- thesaurus_desc_profile

ALTER TABLE core.observation_desc_profile DROP CONSTRAINT IF EXISTS fk_thesaurus_desc_profile;

ALTER TABLE core.thesaurus_desc_profile DROP CONSTRAINT IF EXISTS thesaurus_desc_profile_pkey;
ALTER TABLE core.thesaurus_desc_profile RENAME COLUMN thesaurus_desc_profile_id TO thesaurus_desc_profile_id_old;
ALTER TABLE core.thesaurus_desc_profile ADD COLUMN thesaurus_desc_profile_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.thesaurus_desc_profile.thesaurus_desc_profile_id IS 'Synthetic primary key.';

UPDATE core.thesaurus_desc_profile
   SET thesaurus_desc_profile_id = thesaurus_desc_profile_id_old;

ALTER TABLE core.thesaurus_desc_profile DROP COLUMN IF EXISTS thesaurus_desc_profile_id_old;
ALTER TABLE core.thesaurus_desc_profile
  ADD CONSTRAINT thesaurus_desc_profile_pkey PRIMARY KEY (thesaurus_desc_profile_id);

ALTER TABLE core.observation_desc_profile    
  ADD CONSTRAINT fk_thesaurus_desc_profile FOREIGN KEY (thesaurus_desc_profile_id)
      REFERENCES core.thesaurus_desc_profile (thesaurus_desc_profile_id);

-- thesaurus_desc_specimen

ALTER TABLE core.observation_desc_specimen DROP CONSTRAINT IF EXISTS fk_thesaurus_desc_specimen;

ALTER TABLE core.thesaurus_desc_specimen DROP CONSTRAINT IF EXISTS thesaurus_desc_specimen_pkey;
ALTER TABLE core.thesaurus_desc_specimen RENAME COLUMN thesaurus_desc_specimen_id TO thesaurus_desc_specimen_id_old;
ALTER TABLE core.thesaurus_desc_specimen ADD COLUMN thesaurus_desc_specimen_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.thesaurus_desc_specimen.thesaurus_desc_specimen_id IS 'Synthetic primary key.';

UPDATE core.thesaurus_desc_specimen
   SET thesaurus_desc_specimen_id = thesaurus_desc_specimen_id_old;

ALTER TABLE core.thesaurus_desc_specimen DROP COLUMN IF EXISTS thesaurus_desc_specimen_id_old;
ALTER TABLE core.thesaurus_desc_specimen
  ADD CONSTRAINT thesaurus_desc_specimen_pkey PRIMARY KEY (thesaurus_desc_specimen_id);

ALTER TABLE core.observation_desc_specimen    
  ADD CONSTRAINT fk_thesaurus_desc_specimen FOREIGN KEY (thesaurus_desc_specimen_id)
      REFERENCES core.thesaurus_desc_specimen (thesaurus_desc_specimen_id);

-- thesaurus_desc_surface

ALTER TABLE core.observation_desc_surface DROP CONSTRAINT IF EXISTS fk_thesaurus_desc_surface;

ALTER TABLE core.thesaurus_desc_surface DROP CONSTRAINT IF EXISTS thesaurus_desc_surface_pkey;
ALTER TABLE core.thesaurus_desc_surface RENAME COLUMN thesaurus_desc_surface_id TO thesaurus_desc_surface_id_old;
ALTER TABLE core.thesaurus_desc_surface ADD COLUMN thesaurus_desc_surface_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.thesaurus_desc_surface.thesaurus_desc_surface_id IS 'Synthetic primary key.';

UPDATE core.thesaurus_desc_surface
   SET thesaurus_desc_surface_id = thesaurus_desc_surface_id_old;

ALTER TABLE core.thesaurus_desc_surface DROP COLUMN IF EXISTS thesaurus_desc_surface_id_old;
ALTER TABLE core.thesaurus_desc_surface
  ADD CONSTRAINT thesaurus_desc_surface_pkey PRIMARY KEY (thesaurus_desc_surface_id);

ALTER TABLE core.observation_desc_surface    
  ADD CONSTRAINT fk_thesaurus_desc_surface FOREIGN KEY (thesaurus_desc_surface_id)
      REFERENCES core.thesaurus_desc_surface (thesaurus_desc_surface_id);

-- unit_of_measure

ALTER TABLE core.observation_numerical_specimen DROP CONSTRAINT IF EXISTS fk_unit_of_measure;
ALTER TABLE core.observation_phys_chem DROP CONSTRAINT IF EXISTS fk_unit_of_measure;

ALTER TABLE core.unit_of_measure DROP CONSTRAINT IF EXISTS unit_of_measure_pkey;
ALTER TABLE core.unit_of_measure RENAME COLUMN unit_of_measure_id TO unit_of_measure_id_old;
ALTER TABLE core.unit_of_measure ADD COLUMN unit_of_measure_id INTEGER GENERATED BY DEFAULT AS IDENTITY;
COMMENT ON COLUMN core.unit_of_measure.unit_of_measure_id IS 'Synthetic primary key.';

UPDATE core.unit_of_measure
   SET unit_of_measure_id = unit_of_measure_id_old;

ALTER TABLE core.unit_of_measure DROP COLUMN IF EXISTS unit_of_measure_id_old;
ALTER TABLE core.unit_of_measure
  ADD CONSTRAINT unit_of_measure_pkey PRIMARY KEY (unit_of_measure_id);

ALTER TABLE core.observation_numerical_specimen    
  ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id)
      REFERENCES core.unit_of_measure (unit_of_measure_id);

ALTER TABLE core.observation_phys_chem    
  ADD CONSTRAINT fk_unit_of_measure FOREIGN KEY (unit_of_measure_id)
      REFERENCES core.unit_of_measure (unit_of_measure_id);

-- address

ALTER TABLE metadata.individual DROP CONSTRAINT IF EXISTS fk_address;
ALTER TABLE metadata.organisation DROP CONSTRAINT IF EXISTS fk_address;
ALTER TABLE metadata.individual DROP CONSTRAINT IF EXISTS fk_address_id;
ALTER TABLE metadata.organisation DROP CONSTRAINT IF EXISTS fk_address_id;

ALTER TABLE metadata.address DROP COLUMN IF EXISTS address_id;
ALTER TABLE metadata.address ADD COLUMN address_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN metadata.address.address_id IS 'Synthetic primary key.';

ALTER TABLE metadata.individual 
  ADD CONSTRAINT fk_address FOREIGN KEY (address_id)
      REFERENCES metadata.address (address_id);

ALTER TABLE metadata.organisation    
  ADD CONSTRAINT fk_address FOREIGN KEY (address_id)
      REFERENCES metadata.address (address_id);

-- individual

ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_individual;
ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_individual_id;
ALTER TABLE core.result_phys_chem DROP CONSTRAINT IF EXISTS fk_individual_id;
ALTER TABLE core.result_phys_chem DROP CONSTRAINT IF EXISTS fk_individual;
ALTER TABLE core.surface_individual DROP CONSTRAINT IF EXISTS fk_individual;
ALTER TABLE core.plot_individual DROP CONSTRAINT IF EXISTS fk_individual;

ALTER TABLE metadata.individual DROP COLUMN IF EXISTS individual_id;
ALTER TABLE metadata.individual ADD COLUMN individual_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN metadata.individual.individual_id IS 'Synthetic primary key.';

ALTER TABLE core.surface_individual 
  ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id)
      REFERENCES metadata.individual (individual_id);

ALTER TABLE core.plot_individual 
  ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id)
      REFERENCES metadata.individual (individual_id);

ALTER TABLE core.result_phys_chem
  ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id)
      REFERENCES metadata.individual (individual_id);

ALTER TABLE metadata.organisation_individual    
  ADD CONSTRAINT fk_individual FOREIGN KEY (individual_id)
      REFERENCES metadata.individual (individual_id);

-- organisation

ALTER TABLE metadata.organisation DROP CONSTRAINT IF EXISTS fk_parent_id;
ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_organisation_id;
ALTER TABLE metadata.organisation_unit DROP CONSTRAINT IF EXISTS fk_organisation_id;
ALTER TABLE core.project DROP CONSTRAINT IF EXISTS fk_organisation_id;
ALTER TABLE core.result_numerical_specimen DROP CONSTRAINT IF EXISTS fk_organisation_id;
ALTER TABLE core.specimen DROP CONSTRAINT IF EXISTS fk_organisation_id;

ALTER TABLE metadata.organisation DROP CONSTRAINT IF EXISTS fk_parent;
ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_organisation;
ALTER TABLE metadata.organisation_unit DROP CONSTRAINT IF EXISTS fk_organisation;
ALTER TABLE core.project DROP CONSTRAINT IF EXISTS fk_organisation;
ALTER TABLE core.result_numerical_specimen DROP CONSTRAINT IF EXISTS fk_organisation;
ALTER TABLE core.specimen DROP CONSTRAINT IF EXISTS fk_organisation;

ALTER TABLE metadata.organisation DROP COLUMN IF EXISTS organisation_id;
ALTER TABLE metadata.organisation ADD COLUMN organisation_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN metadata.organisation.organisation_id IS 'Synthetic primary key.';

ALTER TABLE core.project 
  ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

ALTER TABLE core.result_numerical_specimen 
  ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

ALTER TABLE core.specimen
  ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

ALTER TABLE metadata.organisation_individual    
  ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

ALTER TABLE metadata.organisation    
  ADD CONSTRAINT fk_parent FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

ALTER TABLE metadata.organisation_unit 
  ADD CONSTRAINT fk_organisation FOREIGN KEY (organisation_id)
      REFERENCES metadata.organisation (organisation_id);

-- organisation_unit

ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_organisation_unit;
ALTER TABLE metadata.organisation_individual DROP CONSTRAINT IF EXISTS fk_organisation_unit_id;

ALTER TABLE metadata.organisation_unit DROP COLUMN IF EXISTS organisation_unit_id;
ALTER TABLE metadata.organisation_unit ADD COLUMN organisation_unit_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY;
COMMENT ON COLUMN metadata.organisation_unit.organisation_unit_id IS 'Synthetic primary key.';

ALTER TABLE metadata.organisation_individual 
  ADD CONSTRAINT fk_organisation_unit FOREIGN KEY (organisation_unit_id)
      REFERENCES metadata.organisation_unit (organisation_unit_id);