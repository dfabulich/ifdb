ALTER TABLE `users` ADD COLUMN `game_filter` VARCHAR(150) DEFAULT '';

USE ifdb;

DROP TABLE IF EXISTS `global_settings`;
CREATE TABLE `global_settings` (
  `setting_id` BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `setting_name` VARCHAR(255) NOT NULL,
  `current_value` VARCHAR(255) NOT NULL,
  PRIMARY KEY (setting_id),
  UNIQUE KEY `setting_name` (`setting_name`)
);
insert into global_settings (setting_name, current_value)
values ('account approval', 'normal');

-- Fix invalid published dates in games_history deltas (issue #1438).
-- parseDateOrYearVal used to turn empty dates into " 01:00:00"; replace with "".
UPDATE games_history
SET deltas = REPLACE(deltas, 's:9:"published";s:9:" 01:00:00"', 's:9:"published";s:0:""')
WHERE deltas LIKE '%s:9:"published";s:9:" 01:00:00"%';

-- Recent game news materialized view (needed for filtered home Games news).
CREATE OR REPLACE VIEW `recentgamenews` AS
    SELECT
        newsid AS news_id,
        sourceid AS game_id,
        created AS news_create_date
    FROM news
    WHERE source = 'G'
    AND status = 'A'
    AND newsid NOT IN (
        SELECT supersedes
        FROM news
        WHERE supersedes IS NOT NULL
    );

CREATE TABLE IF NOT EXISTS recentgamenews_mv (
  news_id BIGINT(20) unsigned NOT NULL,
  game_id VARCHAR(32) NOT NULL,
  news_create_date DATETIME NOT NULL,
  PRIMARY KEY (news_id),
  KEY (game_id)
);

LOCK TABLES recentgamenews_mv WRITE, recentgamenews READ;
TRUNCATE TABLE recentgamenews_mv;
INSERT INTO recentgamenews_mv SELECT * FROM recentgamenews;
UNLOCK TABLES;

DROP PROCEDURE IF EXISTS refresh_recentgamenews_mv;
DELIMITER $$
CREATE PROCEDURE refresh_recentgamenews_mv (
    IN new_newsid BIGINT(20)
)
BEGIN
SET @news_id = NULL;
SET @game_id = NULL;
SET @news_create_date = NULL;
SELECT news_id, game_id, news_create_date
FROM recentgamenews
WHERE news_id = new_newsid
INTO @news_id, @game_id, @news_create_date;
IF @news_id IS NULL THEN
    DELETE FROM recentgamenews_mv WHERE news_id = new_newsid;
ELSE
    INSERT INTO recentgamenews_mv
    VALUES (@news_id, @game_id, @news_create_date)
    ON DUPLICATE KEY UPDATE
        news_id = @news_id,
        game_id = @game_id,
        news_create_date = @news_create_date;
END IF;
END;
$$
DELIMITER ;

DROP TRIGGER IF EXISTS recentgamenews_insert;
CREATE TRIGGER recentgamenews_insert
AFTER INSERT ON news FOR EACH ROW
CALL refresh_recentgamenews_mv(NEW.newsid);

DROP TRIGGER IF EXISTS recentgamenews_update;
CREATE TRIGGER recentgamenews_update
AFTER UPDATE ON news FOR EACH ROW
CALL refresh_recentgamenews_mv(NEW.newsid);

DROP TRIGGER IF EXISTS recentgamenews_delete;
CREATE TRIGGER recentgamenews_delete
AFTER DELETE ON news FOR EACH ROW
CALL refresh_recentgamenews_mv(OLD.newsid);
