CREATE TABLE IF NOT EXISTS `evdev_devices` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind` VARCHAR(16) NOT NULL,
    `variant` VARCHAR(32) NULL DEFAULT NULL,
    `label` VARCHAR(40) NOT NULL DEFAULT '',
    `state` ENUM('placed','carried','removed') NOT NULL DEFAULT 'placed',
    `x` DOUBLE NULL DEFAULT NULL,
    `y` DOUBLE NULL DEFAULT NULL,
    `z` DOUBLE NULL DEFAULT NULL,
    `heading` DOUBLE NULL DEFAULT NULL,
    `surface` TINYINT(1) NOT NULL DEFAULT 1,
    `bucket` INT NOT NULL DEFAULT 0,
    `property_id` INT NULL DEFAULT NULL,
    `origin` ENUM('admin','item','import') NOT NULL,
    `serial` VARCHAR(16) NULL DEFAULT NULL,
    `owner_cid` VARCHAR(60) NULL DEFAULT NULL,
    `owner_name` VARCHAR(64) NULL DEFAULT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `access` LONGTEXT NOT NULL,
    `manage` LONGTEXT NOT NULL,
    `apps` LONGTEXT NOT NULL,
    `page` LONGTEXT NULL,
    `legacy_key` VARCHAR(64) NULL DEFAULT NULL,
    `created_by` VARCHAR(60) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_by` VARCHAR(60) NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `last_used_at` TIMESTAMP NULL DEFAULT NULL,
    `removed_at` TIMESTAMP NULL DEFAULT NULL,
    `version` INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_serial` (`serial`),
    UNIQUE KEY `uq_legacy` (`legacy_key`),
    KEY `ix_owner` (`owner_cid`),
    KEY `ix_property` (`property_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_apps` (
    `id` VARCHAR(32) NOT NULL,
    `resource` VARCHAR(64) NOT NULL,
    `status` ENUM('pending','allowed','blocked') NOT NULL DEFAULT 'pending',
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `options` LONGTEXT NOT NULL,
    `label` VARCHAR(64) NULL DEFAULT NULL,
    `version` VARCHAR(32) NULL DEFAULT NULL,
    `first_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen` TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_settings` (
    `k` VARCHAR(64) NOT NULL,
    `v` LONGTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_audit` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `actor_cid` VARCHAR(60) NULL DEFAULT NULL,
    `actor_name` VARCHAR(64) NULL DEFAULT NULL,
    `action` VARCHAR(32) NOT NULL,
    `device_id` INT UNSIGNED NULL DEFAULT NULL,
    `detail` LONGTEXT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_device` (`device_id`),
    KEY `ix_at` (`at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_returns` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `cid` VARCHAR(60) NOT NULL,
    `item` VARCHAR(32) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `reason` VARCHAR(32) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_cid` (`cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_device_screens` (
    `device_id` INT UNSIGNED NOT NULL,
    `settings` LONGTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_serials` (
    `serial` VARCHAR(16) NOT NULL,
    `kind` VARCHAR(16) NOT NULL,
    `dead` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`serial`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_device_pins` (
    `device_id` INT UNSIGNED NOT NULL,
    `hash` VARCHAR(128) NOT NULL,
    `set_by` VARCHAR(60) NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_notes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `device_id` INT UNSIGNED NOT NULL,
    `title` VARCHAR(80) NOT NULL DEFAULT '',
    `body` TEXT NOT NULL,
    `author` VARCHAR(64) NULL DEFAULT NULL,
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_device` (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_photos` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `device_id` INT UNSIGNED NOT NULL,
    `url` VARCHAR(320) NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `author` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_device` (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_device_apps` (
    `device_key` VARCHAR(64) NOT NULL,
    `app` VARCHAR(32) NOT NULL,
    `installed` TINYINT(1) NOT NULL DEFAULT 1,
    `changed_by` VARCHAR(60) NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`device_key`, `app`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `evdev_notices` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `cid` VARCHAR(60) NULL DEFAULT NULL,
    `device_id` INT UNSIGNED NULL DEFAULT NULL,
    `app` VARCHAR(32) NOT NULL,
    `notice_id` VARCHAR(64) NOT NULL,
    `title` VARCHAR(80) NOT NULL,
    `body` VARCHAR(240) NOT NULL DEFAULT '',
    `action` VARCHAR(32) NULL DEFAULT NULL,
    `intent` TEXT NULL DEFAULT NULL,
    `seen` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_cid` (`cid`),
    KEY `ix_device` (`device_id`),
    KEY `ix_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
