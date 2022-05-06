--! Previous: sha1:45fa121afc09bc92ed3559466280676579609808
--! Hash: sha1:edbd0b791b8ca3d8f1c4ce64670c1f0d4fdaf5a2
--! Message: Adds common properties to descriptive properties

-- Enter migration here

DELETE FROM core.property_desc_surface;

INSERT INTO core.property_desc_surface (label, uri) VALUES ('SaltCoverProperty', 'http://w3id.org/glosis/model/v1.0.0/surface#saltCoverProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('saltPresenceProperty', 'http://w3id.org/glosis/model/v1.0.0/surface#saltPresenceProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('SaltThicknessProperty', 'http://w3id.org/glosis/model/v1.0.0/surface#saltThicknessProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('sealingConsistenceProperty', 'http://w3id.org/glosis/model/v1.0.0/surface#sealingConsistenceProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('sealingThicknessProperty', 'http://w3id.org/glosis/model/v1.0.0/surface#sealingThicknessProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('bleachedSandProperty', 'http://w3id.org/glosis/model/v1.0.0/common#bleachedSandProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('colourDryProperty', 'http://w3id.org/glosis/model/v1.0.0/common#colourDryProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('colourWetProperty', 'http://w3id.org/glosis/model/v1.0.0/common#colourWetProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('cracksDepthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksDepthProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('cracksDistanceProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksDistanceProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('cracksWidthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksWidthProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('fragmentCoverProperty', 'http://w3id.org/glosis/model/v1.0.0/common#fragmentCoverProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('fragmentSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#fragmentSizeProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('organicMatterClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#organicMatterClassProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('rockAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockAbundanceProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('rockShapeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockShapeProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('rockSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockSizeProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('textureProperty', 'http://w3id.org/glosis/model/v1.0.0/common#textureProperty');
INSERT INTO core.property_desc_surface (label, uri) VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/v1.0.0/common#weatheringFragmentsProperty');


DELETE FROM core.property_desc_plot;

INSERT INTO core.property_desc_plot (label, uri) VALUES ('ForestAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#ForestAbundanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('GrassAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#GrassAbundanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('PavedAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#PavedAbundanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('ShrubsAbundaceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#ShrubsAbundanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('bareCoverAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#bareCoverAbundanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('erosionActivityPeriodProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#erosionActivityPeriodProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('erosionAreaAffectedProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#erosionAreaAffectedProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('erosionCategoryProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#erosionCategoryProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('erosionDegreeProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#erosionDegreeProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('erosionTotalAreaAffectedProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#erosionTotalAreaAffectedProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('floodDurationProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#floodDurationProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('floodFrequencyProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#floodFrequencyProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('geologyProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#geologyProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('groundwaterDepthProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#groundwaterDepthProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('humanInfluenceClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#humanInfluenceClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('koeppenClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#koeppenClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('landUseClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#landUseClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('LandformComplexProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#landformComplexProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('lithologyProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#lithologyProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('MajorLandFormProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#majorLandFormProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('ParentDepositionProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#parentDepositionProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('parentLithologyProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#parentLithologyProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('parentTextureUnconsolidatedProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#parentTextureUnconsolidatedProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('PhysiographyProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#physiographyProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('rockOutcropsCoverProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#rockOutcropsCoverProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('rockOutcropsDistanceProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#rockOutcropsDistanceProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopeFormProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopeFormProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopeGradientClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopeGradientClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopeGradientProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopeGradientProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopeOrientationClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopeOrientationClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopeOrientationProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopeOrientationProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('slopePathwaysProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#slopePathwaysProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('surfaceAgeProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#surfaceAgeProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('treeDensityProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#treeDensityProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('VegetationClassProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#vegetationClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('weatherConditionsCurrentProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#weatherConditionsCurrentProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('weatherConditionsPastProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#weatherConditionsPastProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('weatheringRockProperty', 'http://w3id.org/glosis/model/v1.0.0/siteplot#weatheringRockProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('soilDepthBedrockProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthBedrockProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('soilDepthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('soilDepthRootableClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthRootableClassProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('soilDepthRootableProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthRootableProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('soilDepthSampledProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthSampledProperty');
INSERT INTO core.property_desc_plot (label, uri) VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/v1.0.0/common#weatheringFragmentsProperty');


DELETE FROM core.property_desc_profile;

INSERT INTO core.property_desc_profile (label, uri) VALUES ('profileDescriptionStatusProperty', 'http://w3id.org/glosis/model/v1.0.0/profile#profileDescriptionStatusProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilClassificationFAOProperty', 'http://w3id.org/glosis/model/v1.0.0/profile#soilClassificationFAOProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilClassificationUSDAProperty', 'http://w3id.org/glosis/model/v1.0.0/profile#soilClassificationUSDAProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilClassificationWRBProperty', 'http://w3id.org/glosis/model/v1.0.0/profile#soilClassificationWRBProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('infiltrationRateClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#infiltrationRateClassProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('infiltrationRateNumericProperty', 'http://w3id.org/glosis/model/v1.0.0/common#infiltrationRateNumericProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilDepthBedrockProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthBedrockProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilDepthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilDepthRootableClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthRootableClassProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilDepthRootableProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthRootableProperty');
INSERT INTO core.property_desc_profile (label, uri) VALUES ('soilDepthSampledProperty', 'http://w3id.org/glosis/model/v1.0.0/common#soilDepthSampledProperty');


DELETE FROM core.property_desc_element;

INSERT INTO core.property_desc_element (label, uri) VALUES ('biologicalAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#biologicalAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('biologicalFeaturesProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#biologicalFeaturesProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('boundaryDistinctnessProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#boundaryDistinctnessProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('boundaryTopographyProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#boundaryTopographyProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('bulkDensityMineralProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#bulkDensityMineralProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('bulkDensityPeatProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#bulkDensityPeatProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('carbonatesContentProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#carbonatesContentProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('carbonatesFormsProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#carbonatesFormsProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cationExchangeCapacityEffectiveProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cationExchangeCapacityEffectiveProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cationExchangeCapacityProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cationExchangeCapacityProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cationsSumProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cationsSumProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cementationContinuityProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cementationContinuityProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cementationDegreeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cementationDegreeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cementationFabricProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cementationFabricProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cementationNatureProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#cementationNatureProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('coatingAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#coatingAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('coatingContrastProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#coatingContrastProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('coatingFormProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#coatingFormProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('coatingLocationProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#coatingLocationProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('coatingNatureProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#coatingNatureProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('consistenceDryProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#consistenceDryProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('consistenceMoistProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#consistenceMoistProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('dryConsistencyProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#dryConsistencyProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('gypsumContentProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#gypsumContentProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('gypsumFormsProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#gypsumFormsProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('gypsumWeightProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#gypsumWeightProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcColourProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcColourProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcHardnessProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcHardnessProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcKindProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcKindProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcNatureProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcNatureProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcShapeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcShapeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcSizeeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralConcVolumeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralConcVolumeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralContentProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralContentProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mineralFragmentsProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mineralFragmentsProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('moistConsistencyProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#moistConsistencyProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesBoundaryClassificationProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesBoundaryClassificationProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesColourProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesColourProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesContrastProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesContrastProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesPresenceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesPresenceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('mottlesSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#mottlesSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('oxalateExtractableOpticalDensityProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#oxalateExtractableOpticalDensityProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('ParticleSizeFractionsSumProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#particleSizeFractionsSumProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('peatDecompostionProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#peatDecompostionProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('peatDrainageProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#peatDrainageProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('peatVolumeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#peatVolumeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('plasticityProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#plasticityProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('poresAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#poresAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('poresSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#poresSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('porosityClassProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#porosityClassProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('rootsAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#rootsAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('RootsPresenceProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#rootsPresenceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('saltContentProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#saltContentProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('saltProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#saltProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('sandyTextureProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#sandyTextureProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('solubleAnionsTotalProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#solubleAnionsTotalProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('solubleCationsTotalProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#solubleCationsTotalProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('stickinessProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#stickinessProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('structureGradeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#structureGradeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('structureSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#structureSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('textureFieldClassProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#textureFieldClassProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('textureLabClassProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#textureLabClassProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('VoidsClassificationProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#voidsClassificationProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('voidsDiameterProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#voidsDiameterProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('wetPlasticityProperty', 'http://w3id.org/glosis/model/v1.0.0/layerhorizon#wetPlasticityProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('bleachedSandProperty', 'http://w3id.org/glosis/model/v1.0.0/common#bleachedSandProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('colourDryProperty', 'http://w3id.org/glosis/model/v1.0.0/common#colourDryProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('colourWetProperty', 'http://w3id.org/glosis/model/v1.0.0/common#colourWetProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cracksDepthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksDepthProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cracksDistanceProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksDistanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('cracksWidthProperty', 'http://w3id.org/glosis/model/v1.0.0/common#cracksWidthProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('fragmentCoverProperty', 'http://w3id.org/glosis/model/v1.0.0/common#fragmentCoverProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('fragmentSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#fragmentSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('infiltrationRateClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#infiltrationRateClassProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('infiltrationRateNumericProperty', 'http://w3id.org/glosis/model/v1.0.0/common#infiltrationRateNumericProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('organicMatterClassProperty', 'http://w3id.org/glosis/model/v1.0.0/common#organicMatterClassProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('rockAbundanceProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockAbundanceProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('rockShapeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockShapeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('rockSizeProperty', 'http://w3id.org/glosis/model/v1.0.0/common#rockSizeProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('textureProperty', 'http://w3id.org/glosis/model/v1.0.0/common#textureProperty');
INSERT INTO core.property_desc_element (label, uri) VALUES ('weatheringFragmentsProperty', 'http://w3id.org/glosis/model/v1.0.0/common#weatheringFragmentsProperty');
