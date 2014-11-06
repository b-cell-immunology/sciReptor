SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='TRADITIONAL,ALLOW_INVALID_DATES';

SHOW WARNINGS;
SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `species_library`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `species_library` (
  `species_id` VARCHAR(10) NOT NULL,
  `trivial_name` VARCHAR(45) NOT NULL,
  `species_name` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`species_id`),
  UNIQUE INDEX `species_id_UNIQUE` (`species_id` ASC),
  UNIQUE INDEX `species_name_UNIQUE` (`species_name` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `plate_layout_library`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `plate_layout_library` (
  `plate_layout_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `n_rows` INT UNSIGNED NOT NULL,
  `n_cols` INT UNSIGNED NOT NULL,
  `n_wells` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`plate_layout_id`),
  UNIQUE INDEX `plate_layout_id_UNIQUE` (`plate_layout_id` ASC),
  UNIQUE INDEX `n_wells_UNIQUE` (`n_wells` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `constant_library`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `constant_library` (
  `constant_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `species_id` VARCHAR(10) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  `haplotype` VARCHAR(45) NULL,
  `allele` VARCHAR(45) NULL,
  `locus` CHAR NOT NULL,
  `sequence` VARCHAR(2000) NOT NULL,
  `ref_assembly` VARCHAR(45) NOT NULL,
  `ref_chromosome` VARCHAR(45) NULL,
  `ref_pos_centro` VARCHAR(45) NULL,
  `ref_pos_telo` VARCHAR(45) NULL,
  `ref_ori` VARCHAR(45) NULL,
  PRIMARY KEY (`constant_id`),
  INDEX `fk_constant_library_species_library1` (`species_id` ASC),
  UNIQUE INDEX `constant_id_UNIQUE` (`constant_id` ASC),
  UNIQUE INDEX `unique_id` (`species_id` ASC, `name` ASC, `allele` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `VDJ_library`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `VDJ_library` (
  `VDJ_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `species_id` VARCHAR(10) NOT NULL,
  `locus` CHAR NOT NULL,
  `seg_type` CHAR NOT NULL,
  `seg_name` VARCHAR(20) NOT NULL,
  `seg_family` VARCHAR(20) NULL,
  `seg_gene` VARCHAR(20) NULL,
  `seg_allele` VARCHAR(20) NULL,
  `haplotype` VARCHAR(45) NULL,
  `ref_assembly` VARCHAR(20) NOT NULL,
  `ref_chromosome` VARCHAR(20) NULL,
  `ref_pos1` INT(11) NULL,
  `ref_pos2` INT(11) NULL,
  `ref_ori` INT(11) NULL,
  `seg_pseudo` CHAR(1) NOT NULL,
  `seg_sequence` VARCHAR(2000) NOT NULL,
  `seg_frame` INT UNSIGNED NULL,
  `fwr1_start` INT UNSIGNED NULL,
  `fwr1_stop` INT UNSIGNED NULL,
  `cdr1_start` INT UNSIGNED NULL,
  `cdr1_stop` INT UNSIGNED NULL,
  `fwr2_start` INT UNSIGNED NULL,
  `fwr2_stop` INT UNSIGNED NULL,
  `cdr2_start` INT UNSIGNED NULL,
  `cdr2_stop` INT UNSIGNED NULL,
  `fwr3_start` INT UNSIGNED NULL,
  `fwr3_stop` INT UNSIGNED NULL,
  PRIMARY KEY (`VDJ_id`),
  INDEX `fk_VDJ_library_species_library` (`species_id` ASC),
  UNIQUE INDEX `VDJ_id_UNIQUE` (`VDJ_id` ASC),
  UNIQUE INDEX `unique_id` (`species_id` ASC, `seg_name` ASC))
ENGINE = MyISAM;

SHOW WARNINGS;

-- -----------------------------------------------------
-- Table `tags_library`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `tags_library` (
  `tag_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NOT NULL,
  `sequence` VARCHAR(20) NOT NULL,
  `matrix` VARCHAR(20) NOT NULL,
  `batch` VARCHAR(20) NOT NULL,
  PRIMARY KEY (`tag_id`),
  UNIQUE INDEX `tag_id_UNIQUE` (`tag_id` ASC),
  UNIQUE INDEX `unique_id` (`name` ASC, `matrix` ASC, `batch` ASC))
ENGINE = InnoDB;

SHOW WARNINGS;

SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
