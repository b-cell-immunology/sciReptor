SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='TRADITIONAL,ALLOW_INVALID_DATES';

SHOW WARNINGS;
SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `donor`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `donor` (
  `donor_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `donor_identifier` VARCHAR(45) NOT NULL,
  `background_treatment` VARCHAR(2000) NULL,
  `project` VARCHAR(45) NOT NULL,
  `strain` VARCHAR(45) NULL,
  `add_donor_info` VARCHAR(2000) NULL,
  `species_id` VARCHAR(20) NOT NULL,
  PRIMARY KEY (`donor_id`),
  INDEX `fk_donor_species_library1` (`species_id` ASC),
  UNIQUE INDEX `donor_id_UNIQUE` (`donor_id` ASC),
  UNIQUE INDEX `unique_id` (`donor_identifier` ASC, `project` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `sample`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `sample` (
  `sample_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `donor_id` INT NOT NULL,
  `tissue` VARCHAR(45) NOT NULL,
  `sampling_date` DATETIME NOT NULL,
  `add_sample_info` VARCHAR(500) NULL,
  PRIMARY KEY (`sample_id`),
  INDEX `fk_sample_patient1_idx` (`donor_id` ASC),
  UNIQUE INDEX `sample_id_UNIQUE` (`sample_id` ASC),
  UNIQUE INDEX `unique_id` (`donor_id` ASC, `sampling_date` ASC, `tissue` ASC, `add_sample_info` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `sort`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `sort` (
  `sort_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `antigen` VARCHAR(45) NULL,
  `population` VARCHAR(45) NOT NULL,
  `sorting_date` DATETIME NOT NULL,
  `add_sort_info` VARCHAR(2000) NULL,
  `sample_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`sort_id`),
  INDEX `fk_sort_sample1` (`sample_id` ASC),
  UNIQUE INDEX `sort_id_UNIQUE` (`sort_id` ASC),
  UNIQUE INDEX `unique_id` (`sample_id` ASC, `sorting_date` ASC, `antigen` ASC, `population` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `event`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `event` (
  `event_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `well` INT NOT NULL,
  `plate` INT NOT NULL,
  `row` INT NOT NULL,
  `col` INT NOT NULL,
  `sequencing_run_sanger` VARCHAR(20) NULL COMMENT 'optional for Sanger sequences',
  `add_event_info` VARCHAR(2000) NULL,
  `sort_id` INT UNSIGNED NOT NULL,
  `plate_layout_id` INT UNSIGNED NOT NULL,
  `plate_barcode` VARCHAR(45) NULL,
  PRIMARY KEY (`event_id`),
  INDEX `fk_event_sort1` (`sort_id` ASC),
  UNIQUE INDEX `event_id_UNIQUE` (`event_id` ASC),
  INDEX `fk_event_plate_layout_library1` (`plate_layout_id` ASC),
  UNIQUE INDEX `unique_id` (`sort_id` ASC, `plate_barcode` ASC, `row` ASC, `col` ASC, `well` ASC, `plate` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `sequences`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `sequences` (
  `seq_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NOT NULL,
  `consensus_rank` INT NULL,
  `locus` CHAR NULL,
  `length` INT UNSIGNED NOT NULL,
  `orient` CHAR NULL,
  `igblast_productive` TINYINT(1) NULL DEFAULT NULL,
  `seq` VARCHAR(1000) NOT NULL,
  `quality` VARCHAR(3000) NULL,
  `event_id` INT UNSIGNED NULL,
  PRIMARY KEY (`seq_id`),
  INDEX `fk_sequences_event1_idx` (`event_id` ASC),
  UNIQUE INDEX `seq_id_UNIQUE` (`seq_id` ASC),
  UNIQUE INDEX `unique_id` (`event_id` ASC, `length` ASC, `locus` ASC, `name` ASC, `consensus_rank` ASC),
  UNIQUE INDEX `name_UNIQUE` (`name` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `constant_segments`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `constant_segments` (
  `constant_segments_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(20) NOT NULL,
  `percid` FLOAT NOT NULL,
  `length` INT UNSIGNED NOT NULL,
  `gapopens` INT UNSIGNED NOT NULL,
  `readstart` INT UNSIGNED NOT NULL,
  `readend` INT UNSIGNED NOT NULL,
  `eval` FLOAT NOT NULL,
  `score` FLOAT NOT NULL,
  `constant_id` INT UNSIGNED NOT NULL,
  INDEX `fk_constant_segments_sequences_idx` (`seq_id` ASC),
  INDEX `fk_constant_segments_constant_library1` (`constant_id` ASC),
  UNIQUE INDEX `seq_id_UNIQUE` (`seq_id` ASC),
  PRIMARY KEY (`constant_segments_id`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `VDJ_segments`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `VDJ_segments` (
  `VDJ_segments_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `type` CHAR(1) NOT NULL,
  `locus` CHAR(1) NOT NULL,
  `igblast_rank` INT(1) UNSIGNED NOT NULL,
  `name` VARCHAR(20) NOT NULL,
  `eval` DOUBLE NOT NULL,
  `score` FLOAT NOT NULL,
  `VDJ_id` INT UNSIGNED NOT NULL,
  INDEX `fk_VDJ_segments_sequences1_idx` (`seq_id` ASC),
  INDEX `fk_VDJ_segments_VDJ_library1` (`VDJ_id` ASC),
  UNIQUE INDEX `unique_id` (`seq_id` ASC, `type` ASC, `locus` ASC, `igblast_rank` ASC),
  PRIMARY KEY (`VDJ_segments_id`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `CDR_FWR`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `CDR_FWR` (
  `CDR_FWR_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `region` VARCHAR(20) NOT NULL,
  `start` INT UNSIGNED NOT NULL,
  `end` INT UNSIGNED NOT NULL,
  `dna_seq` VARCHAR(300) NOT NULL,
  `prot_seq` VARCHAR(100) NOT NULL,
  `prot_length` INT UNSIGNED NOT NULL,
  `stop_codon` TINYINT NOT NULL,
  INDEX `fk_CDR_FWR_sequences1_idx` (`seq_id` ASC),
  UNIQUE INDEX `unique_id` (`seq_id` ASC, `region` ASC, `start` ASC),
  PRIMARY KEY (`CDR_FWR_id`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `warnings`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `warnings` (
  `warnings_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `quality_score` INT NULL,
  `FWR3_igblast_output` TINYINT(1) NOT NULL,
  `CDR3_start_C` TINYINT(1) NOT NULL,
  `CDR3_end` TINYINT(1) NOT NULL,
  `alt_CDR3_end` TINYINT(1) NOT NULL,
  `J_end` TINYINT(1) NOT NULL,
  PRIMARY KEY (`warnings_id`),
  INDEX `fk_warnings_1` (`seq_id` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `consensus_stats`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `consensus_stats` (
  `consensus_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sequences_seq_id` INT UNSIGNED NULL,
  `locus` CHAR NOT NULL,
  `n_seq` INT NULL DEFAULT 0,
  `best_V` INT NULL,
  `best_J` INT NULL,
  `col_tag` VARCHAR(45) NOT NULL,
  `row_tag` VARCHAR(45) NOT NULL,
  `experiment_id` VARCHAR(10) NOT NULL COMMENT 'Required to distinguish reads that map to the same well but come from different sequencing runs. Reads with the same experiment_id will be assembled into one consensus, irrespective of the run origin Typical scenario for this is the re-sequencing of an am /* comment truncated */ /*plicon pool.

*/',
  PRIMARY KEY (`consensus_id`),
  INDEX `fk_consensus_stats_sequences1_idx` (`sequences_seq_id` ASC),
  UNIQUE INDEX `consensus_id_UNIQUE` (`consensus_id` ASC),
  UNIQUE INDEX `unique_id` (`col_tag` ASC, `row_tag` ASC, `locus` ASC, `experiment_id` ASC, `best_J` ASC, `best_V` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `sequencing_run`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `sequencing_run` (
  `sequencing_run_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `date` DATETIME NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  `processed_by` VARCHAR(45) NOT NULL,
  `experiment_id` VARCHAR(10) NOT NULL,
  `add_sequencing_info` VARCHAR(100) NULL,
  `plate_layout_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`sequencing_run_id`),
  UNIQUE INDEX `sequencing_run_id_UNIQUE` (`sequencing_run_id` ASC),
  INDEX `fk_sequencing_run_plate_layout_library1` (`plate_layout_id` ASC),
  UNIQUE INDEX `unique_id` (`date` ASC, `name` ASC, `add_sequencing_info` ASC, `processed_by` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `reads`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `reads` (
  `seq_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NOT NULL,
  `locus` CHAR NULL,
  `length` INT UNSIGNED NOT NULL,
  `orient` CHAR NULL,
  `igblast_productive` TINYINT(1) NULL DEFAULT NULL,
  `seq` VARCHAR(1000) NOT NULL,
  `quality` VARCHAR(3000) NOT NULL,
  `sequencing_run_id` INT UNSIGNED NOT NULL,
  `well_id` INT(7) ZEROFILL NULL,
  `consensus_id` INT UNSIGNED NULL,
  PRIMARY KEY (`seq_id`),
  INDEX `fk_reads_consensus_stats1_idx` (`consensus_id` ASC),
  INDEX `fk_reads_sequencing_run1` (`sequencing_run_id` ASC),
  UNIQUE INDEX `seq_id_UNIQUE` (`seq_id` ASC),
  UNIQUE INDEX `unique_id` (`name` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `reads_constant_segments`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `reads_constant_segments` (
  `reads_constant_segments_id` INT(11) NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(20) NOT NULL,
  `percid` FLOAT NOT NULL,
  `length` INT NOT NULL,
  `gapopens` INT NOT NULL,
  `readstart` INT NOT NULL,
  `readend` INT NOT NULL,
  `eval` FLOAT NOT NULL,
  `score` FLOAT NOT NULL,
  `constant_id` INT NOT NULL,
  INDEX `fk_reads_constant_segments_reads1_idx` (`seq_id` ASC),
  INDEX `fk_reads_constant_segments_constant_library1` (`constant_id` ASC),
  UNIQUE INDEX `seq_id_UNIQUE` (`seq_id` ASC),
  PRIMARY KEY (`reads_constant_segments_id`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `reads_VDJ_segments`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `reads_VDJ_segments` (
  `reads_VDJ_segments_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `type` CHAR(1) NOT NULL,
  `locus` CHAR(1) NOT NULL,
  `igblast_rank` INT UNSIGNED NOT NULL,
  `name` VARCHAR(20) NOT NULL,
  `eval` DOUBLE NOT NULL,
  `score` FLOAT NOT NULL,
  `VDJ_id` INT UNSIGNED NOT NULL,
  INDEX `fk_reads_VDJ_segments_reads1_idx` (`seq_id` ASC),
  INDEX `fk_reads_VDJ_segments_VDJ_library1` (`VDJ_id` ASC),
  UNIQUE INDEX `unique_id` (`seq_id` ASC, `type` ASC, `locus` ASC, `igblast_rank` ASC),
  PRIMARY KEY (`reads_VDJ_segments_id`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `reads_tags`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `reads_tags` (
  `reads_tagid` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `percid` FLOAT NOT NULL,
  `direction` CHAR NOT NULL,
  `insertion` INT UNSIGNED NULL,
  `deletion` INT UNSIGNED NULL,
  `replacement` INT UNSIGNED NULL,
  `start` INT UNSIGNED NOT NULL,
  `end` INT UNSIGNED NOT NULL,
  `tag_id` INT UNSIGNED NOT NULL,
  INDEX `fk_reads_tags_reads1_idx` (`seq_id` ASC),
  INDEX `fk_reads_tags_tags_library1` (`tag_id` ASC),
  UNIQUE INDEX `unique_id` (`seq_id` ASC, `tag_id` ASC, `start` ASC),
  PRIMARY KEY (`reads_tagid`))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `log_table`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `log_table` (
  `log_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `date` DATETIME NOT NULL,
  `pipeline_version` VARCHAR(45) NOT NULL,
  `user` VARCHAR(45) NOT NULL,
  `dbuser` VARCHAR(45) NOT NULL,
  `command` VARCHAR(100) NOT NULL,
  `output` BLOB NULL,
  PRIMARY KEY (`log_id`),
  UNIQUE INDEX `log_id_UNIQUE` (`log_id` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `mutations`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `mutations` (
  `mutations_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `position_codonstart_on_seq` INT UNSIGNED NOT NULL,
  `replacement` INT NOT NULL DEFAULT 0,
  `silent` INT NOT NULL DEFAULT 0,
  `insertion` INT NOT NULL DEFAULT 0,
  `deletion` INT NOT NULL DEFAULT 0,
  `undef_add_mutation` INT NOT NULL DEFAULT 0,
  `stop_codon_germline` INT NOT NULL DEFAULT 0,
  `stop_codon_sequence` INT NOT NULL DEFAULT 0,
  `in_status` INT NOT NULL DEFAULT 0,
  `del_status` INT NOT NULL DEFAULT 0,
  INDEX `fk_warnings_sequences1_idx` (`seq_id` ASC),
  PRIMARY KEY (`mutations_id`),
  UNIQUE INDEX `unique` (`seq_id` ASC, `position_codonstart_on_seq` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `igblast_alignment`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `igblast_alignment` (
  `igblast_alignment_id` INT NOT NULL AUTO_INCREMENT,
  `seq_id` INT UNSIGNED NOT NULL,
  `query_start` INT UNSIGNED NOT NULL,
  `germline_start` INT UNSIGNED NOT NULL,
  `query_seq` VARCHAR(500) NOT NULL,
  `germline_seq` VARCHAR(500) NOT NULL,
  INDEX `fk_warnings_sequences1_idx` (`seq_id` ASC),
  PRIMARY KEY (`igblast_alignment_id`),
  INDEX `unique` (`seq_id` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `flow_meta`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `flow_meta` (
  `channel_id` INT NOT NULL AUTO_INCREMENT,
  `detector_name` VARCHAR(45) NULL,
  `detector_scale` VARCHAR(45) NULL,
  `detector_spec` VARCHAR(45) NULL,
  `detector_voltage` INT NULL,
  `marker_name` VARCHAR(45) NULL,
  `marker_fluorochrome` VARCHAR(45) NULL,
  `sort_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`channel_id`),
  INDEX `fk_flow_meta_sort1_idx` (`sort_id` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `flow`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `flow` (
  `flow_id` INT NOT NULL AUTO_INCREMENT,
  `event_id` INT UNSIGNED NOT NULL,
  `value` FLOAT NULL,
  `channel_id` INT NOT NULL,
  PRIMARY KEY (`flow_id`),
  UNIQUE KEY `idx_flow_event_id_channel_id` (`event_id`,`channel_id`),
  INDEX `fk_flow_event1_idx` (`event_id` ASC),
  INDEX `fk_flow_flow_meta1_idx` (`channel_id` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
