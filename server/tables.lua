-- whip_jobs: our tables (whip_core EnsureTable: made once, migrations recorded).
ESJ = ESJ or {}

local TABLES = {
    { 'es_jobs_businesses', [[CREATE TABLE IF NOT EXISTS `es_jobs_businesses` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(48) NOT NULL,
        `short` VARCHAR(12) NOT NULL,
        `color` VARCHAR(7) NOT NULL DEFAULT '#4f8ff7',
        `blurb` VARCHAR(200) NULL,
        `logo` MEDIUMTEXT NULL,
        `logoVer` INT UNSIGNED NOT NULL DEFAULT 0,
        `ownerCharId` INT UNSIGNED NULL,
        `createdBy` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_es_jobs_biz_job` (`jobId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_stations', [[CREATE TABLE IF NOT EXISTS `es_jobs_stations` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(48) NOT NULL,
        `jobs` TEXT NOT NULL,
        `blip` TEXT NULL,
        `spots` LONGTEXT NOT NULL,
        `rev` INT UNSIGNED NOT NULL DEFAULT 1,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `updatedBy` INT UNSIGNED NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_station_history', [[CREATE TABLE IF NOT EXISTS `es_jobs_station_history` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `stationId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(48) NOT NULL,
        `snapshot` LONGTEXT NOT NULL,
        `action` VARCHAR(40) NOT NULL,
        `byCharId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_hist_station` (`stationId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_pay', [[CREATE TABLE IF NOT EXISTS `es_jobs_pay` (
        `roleId` INT UNSIGNED NOT NULL,
        `jobId` INT UNSIGNED NOT NULL,
        `amount` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`roleId`),
        KEY `idx_es_jobs_pay_job` (`jobId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_ledger', [[CREATE TABLE IF NOT EXISTS `es_jobs_ledger` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `kind` VARCHAR(16) NOT NULL,
        `amount` INT NOT NULL,
        `charId` INT UNSIGNED NULL,
        `note` VARCHAR(120) NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_ledger_job` (`jobId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_lockers', [[CREATE TABLE IF NOT EXISTS `es_jobs_lockers` (
        `charId` INT UNSIGNED NOT NULL,
        `containerId` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`charId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_uniforms', [[CREATE TABLE IF NOT EXISTS `es_jobs_uniforms` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(40) NOT NULL,
        `body` VARCHAR(6) NOT NULL,
        `minLevel` INT UNSIGNED NOT NULL DEFAULT 0,
        `parts` TEXT NOT NULL,
        `sort` INT NOT NULL DEFAULT 0,
        `updatedBy` INT UNSIGNED NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_uni_job` (`jobId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_wardrobe', [[CREATE TABLE IF NOT EXISTS `es_jobs_wardrobe` (
        `charId` INT UNSIGNED NOT NULL,
        `own` TEXT NOT NULL,
        `uniformId` INT UNSIGNED NULL,
        `jobId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`charId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_medical', [[CREATE TABLE IF NOT EXISTS `es_jobs_medical` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(80) NOT NULL,
        `kind` VARCHAR(16) NOT NULL,
        `injury` VARCHAR(200) NULL,
        `treatment` VARCHAR(200) NULL,
        `notes` VARCHAR(1000) NULL,
        `jobId` INT UNSIGNED NULL,
        `bill` INT UNSIGNED NOT NULL DEFAULT 0,
        `byCharId` INT UNSIGNED NULL,
        `byName` VARCHAR(80) NULL,
        `place` VARCHAR(120) NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_med_char` (`charId`, `id`),
        KEY `idx_es_jobs_med_name` (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_med_bills', [[CREATE TABLE IF NOT EXISTS `es_jobs_med_bills` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `jobId` INT UNSIGNED NOT NULL,
        `amount` INT UNSIGNED NOT NULL,
        `reason` VARCHAR(120) NOT NULL,
        `status` VARCHAR(8) NOT NULL DEFAULT 'unpaid',
        `recordId` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `paidAt` TIMESTAMP NULL,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_bills_char` (`charId`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

function ESJ.ensureTables()
    for _, t in ipairs(TABLES) do
        local ok, why = Whip.core:EnsureTable(t[1], t[2], {})
        if not ok then return false, ('%s: %s'):format(t[1], tostring(why)) end
    end
    return true
end
