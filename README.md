# Data model for the ISO28258:2013 domain model

This software proposes (and deploys) a [PostGres](https://postgres.org/) database implementing the [ISO28258:2013](https://www.iso.org/standard/44595.html) domain model. ISO28258:2013 proposes a domain model to store & exchange data related to soil and land observations, observed on-site or analysed in a laboratory. 

Storing data according to the ISO28258:2013 model facilitates efficient and consistent storage of soil and land data across various observation campaigns. Continue reading on the background to this initiative in an [accompanying document](Glossary.md). ISRIC - World Soil endorses the use of standardised domain models, to facilitate efficient cooperation in the soil domain.

The software is released under an [MIT license](./Licence.md)

Copyright (C) 2022-2025 ISRIC - World Soil Information

Citation: de Sousa, L. M., Calisto, L., van Genuchten P., Turdukulov, U., Kempen, B., 2023. Data model for the ISO 28258 domain model. ISRIC World Soil Information. Available at: [https://iso28258.isric.org/](https://iso28258.isric.org/)


# Datamodel Documentation

The iso28258 datamodel includes a number of concepts. Most of these are included in this database implementation:

- Project: An organisational clustering of a set of observations, like a sampling campaign
- Site: A defined area where a phenomena is observed
- Plot: A location within the site where an observation is made
- Surface: The boundary between soil and air/water
- Profile: A cross section through the layers of the soil by drilling a hole or digging a pit
- Element: A layer or horizon in a soil profile
- Specimen: A physical sample, typically analysed in a laboratory
- Property: A property being observed or measured, e.g. texture, pH, volume percentage of pores
- Procedure: A procedure how the observation has been made
- Observation: The act of observing or measuring a property
- Result: The observed value or class for a property

However we've decided to **not** inclode:

- Horizon & Layer: as they are essentially the same in the domain, for now only ProfileElement is included.
- Sample: because in soil science it is often not distinguishable from the specimen.
- SoilMap, SoilMappingUnit, SoilTopologicalUnit: This part may be added in future

Diagrams
--------

The diagrams below explain how the concepts relate to each other.

### Project and Site

```mermaid
erDiagram
  project {
    INTEGER project_id
    VARCHAR name
  }
  site_project {
    INTEGER site_id
    INTEGER project_id
  }
  project_related {
    INTEGER project_source_id
    INTEGER project_target_id
    VARCHAR role
  }
  site {
    INTEGER site_id
    VARCHAR site_code
    unknown position
    unknown extent
  }
  site_project ||--o{ site : fk_site
  site_project ||--o{ project : fk_project
  project_related ||--o{ project : fk_project_source
  project_related ||--o{ project : fk_project_target
```

### Features of Interest

```mermaid
erDiagram
  surface {
    INTEGER surface_id
    INTEGER super_surface_id
    INTEGER site_id
    NULL shape
  }
  specimen {
    INTEGER specimen_id
    VARCHAR code
    INTEGER plot_id
    INTEGER specimen_prep_process_id
    INTEGER depth
  }
  site {
    INTEGER site_id
    VARCHAR site_code
    NULL position
    NULL extent
  }
  element {
    INTEGER element_id
    VARCHAR type
    INTEGER profile_id
    INTEGER order_element
    INTEGER upper_depth
    INTEGER lower_depth
  }
  specimen_prep_process {
    INTEGER specimen_prep_process_id
    INTEGER specimen_transport_id
    INTEGER specimen_storage_id
    VARCHAR definition
  }
  profile {
    INTEGER profile_id
    VARCHAR profile_code
    INTEGER plot_id
    INTEGER surface_id
  }
  plot {
    INTEGER plot_id
    VARCHAR plot_code
    INTEGER site_id
    NUMERIC altitude
    DATE time_stamp
    VARCHAR map_sheet_code
    NUMERIC positional_accuracy
    NULL position
  }
  plot ||--o{ site : fk_site
  surface ||--o{ surface : fk_surface
  surface ||--o{ site : fk_site
  profile ||--o{ plot : fk_plot_id
  profile ||--o{ surface : fk_surface_id
  element ||--o{ profile : fk_profile
  specimen ||--o{ plot : fk_plot
  specimen ||--o{ specimen_prep_process : fk_specimen_prep_process
```

### Descriptive Observations

A similar structure applies to the main Features of Interest: Surface, Plot, Profile, Element and Specimen. 

```mermaid
erDiagram
  observation_desc_surface {
    INTEGER property_desc_surface_id
    INTEGER thesaurus_desc_surface_id
  }
  surface {
    INTEGER surface_id
    INTEGER super_surface_id
    INTEGER site_id
    unknown shape
  }
  property_desc_surface {
    INTEGER property_desc_surface_id
    VARCHAR label
    VARCHAR uri
  }
  result_desc_surface {
    INTEGER surface_id
    INTEGER property_desc_surface_id
    INTEGER thesaurus_desc_surface_id
  }
  thesaurus_desc_surface {
    INTEGER thesaurus_desc_surface_id
    VARCHAR label
    VARCHAR uri
  }
  observation_desc_surface ||--o{ thesaurus_desc_surface : fk_thesaurus_desc_surface
  observation_desc_surface ||--o{ property_desc_surface : fk_property_desc_surface
  result_desc_surface ||--o{ observation_desc_surface : result_desc_surface_property_desc_surface_id_thesaurus_des_fkey
  result_desc_surface ||--o{ observation_desc_surface : result_desc_surface_property_desc_surface_id_thesaurus_des_fkey
  result_desc_surface ||--o{ surface : fk_surface
```

### Physio-chemical Observations

These observations only apply to Element. Surface, Plot and Profile have no physio-chemical observations for the time being. Specimen has its own structure, around the table `observation_numeric_specimen`, but it is empty, since its nature remains unknown. 

```mermaid
erDiagram
  result_phys_chem {
    INTEGER result_phys_chem_id
    INTEGER observation_phys_chem_id
    INTEGER element_id
    NUMERIC value
  }
  property_phys_chem {
    INTEGER property_phys_chem_id
    VARCHAR label
    VARCHAR uri
  }
  unit_of_measure {
    INTEGER unit_of_measure_id
    VARCHAR label
    VARCHAR uri
  }
  observation_phys_chem {
    INTEGER observation_phys_chem_id
    INTEGER property_phys_chem_id
    INTEGER procedure_phys_chem_id
    INTEGER unit_of_measure_id
    NUMERIC value_min
    NUMERIC value_max
  }
  element {
    INTEGER element_id
    element_type type
    INTEGER profile_id
    INTEGER order_element
    INTEGER upper_depth
    INTEGER lower_depth
  }
  procedure_phys_chem {
    INTEGER procedure_phys_chem_id
    INTEGER broader_id
    VARCHAR label
    VARCHAR uri
  }
  observation_phys_chem ||--o{ procedure_phys_chem : fk_procedure_phys_chem
  observation_phys_chem ||--o{ unit_of_measure : fk_unit_of_measure
  observation_phys_chem ||--o{ property_phys_chem : fk_property_phys_chem
  result_phys_chem ||--o{ element : fk_element
  result_phys_chem ||--o{ observation_phys_chem : fk_observation_phys_chem
```

Meta-data model (VCard)
=======================

Concepts derived from the [VCard specification](https://www.w3.org/TR/vcard-rdf):
- Address
- Individual
- Organisation
- Organisation unit

```mermaid
erDiagram
  organisation_individual {
    INTEGER individual_id
    INTEGER organisation_id
    INTEGER organisation_unit_id
    VARCHAR role
  }
  organisation {
    INTEGER organisation_id
    INTEGER parent_id
    VARCHAR name
    VARCHAR email
    VARCHAR telephone
    VARCHAR url
    INTEGER address_id
  }
  organisation_unit {
    INTEGER organisation_unit_id
    VARCHAR name
    INTEGER organisation_id
  }
  address {
    INTEGER address_id
    VARCHAR street_address
    VARCHAR postal_code
    VARCHAR locality
    VARCHAR country
  }
  individual {
    INTEGER individual_id
    VARCHAR name
    VARCHAR honorific_title
    VARCHAR email
    VARCHAR telephone
    VARCHAR url
    INTEGER address_id
  }
  individual ||--o{ address : fk_address_id
  organisation ||--o{ address : fk_address_id
  organisation ||--o{ organisation : fk_parent_id
  organisation_unit ||--o{ organisation : fk_organisation_id
  organisation_individual ||--o{ organisation_unit : fk_organisation_unit_id
  organisation_individual ||--o{ individual : fk_individual_id
  organisation_individual ||--o{ organisation : fk_organisation_id

```


# Installation instructions

The tool uses [graphile-migrate](https://github.com/graphile/migrate) as a database configuration/migration tool. In order to launch and update the database:

### Using it the 1º time

1. Copy [.env.dist](.env.dist) into `.env`and make sure you edit the correct parameters according to your needs: `user` `password` `database name`
2. Make sure you have NodeJS installed on your system and run `corepack enable` from the terminal.
3. From inside the terminal, go to this repo root folder `yarn install`
4. After the previous step run `yarn run graphile-migrate reset --erase` 
5. You should now have a new database ready to go.

### Using it for development 

After running the previous batch you should have a new database ready to go. In a quick resume any SQL code can be done as:

1. Edit [migrations/current.sql](migrations/current.sql) and insert your code
2. Run `yarn run graphile-migrate watch` and once you are satisfied with your code commit it using `yarn run graphile-migrate commit --message "Your message"`
3. Check and test your implementation.

Please read carefully [migrations.md](migrations.md) in order to understand how the migration tool is configured.



