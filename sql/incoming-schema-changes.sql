USE ifdb;

-- use this script for pending changes to the production DB schema

-- Add column for game search filter to the users table

ALTER TABLE `users` ADD COLUMN `game_filter` VARCHAR(150) DEFAULT '';





-- Add a view to track the news items for each game.
-- "G" in the news table means the news is about a game,
-- and "A" means the news has not been deleted.
-- Do not include versions of news items that have been 
-- superseded by later edits.

CREATE VIEW `recentgamenews` AS 
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
    )
    ORDER BY news_id DESC;

  

-- Create a materialized view to store the data from the recentgamenews view

CREATE TABLE recentgamenews_mv (
  news_id BIGINT(20) unsigned NOT NULL,
  game_id VARCHAR(32) NOT NULL,
  news_create_date DATETIME NOT NULL,
  PRIMARY KEY (news_id),
  KEY (game_id)
);



-- Populate the recentgamenews_mv materialized view from the recentgamenews view

lock tables recentgamenews_mv write, recentgamenews read;
truncate table recentgamenews_mv;
insert into recentgamenews_mv select * from recentgamenews;
unlock tables;



-- Procedure to update one row of the recentgamenews_mv materialized view

DROP PROCEDURE IF EXISTS refresh_recentgamenews_mv;
DELIMITER $$

CREATE PROCEDURE refresh_recentgamenews_mv (
    IN new_newsid BIGINT(20)
)
BEGIN
select *
from recentgamenews
where news_id = new_newsid
into @news_id,
     @game_id,
     @news_create_date;
if @news_id is null then
    delete from recentgamenews_mv where news_id = new_newsid;
else
insert into recentgamenews_mv
values (
        @news_id,
        @game_id,
        @news_create_date
    ) on duplicate key
update news_id = @news_id,
    game_id = @game_id,
    news_create_date = @news_create_date;
END IF;
END;
$$

DELIMITER ;



-- Create triggers so that when a news item for a game is added to the news table,
-- the latest news date and the latest news id for that game will automatically
-- be updated in the recentgamenews_mv materialized view. [Question: How do I limit this to just game news?]

CREATE TRIGGER recentgamenews_insert
AFTER INSERT ON news FOR EACH ROW
call refresh_recentgamenews_mv(NEW.newsid);


CREATE TRIGGER recentgamenews_update
AFTER UPDATE ON news FOR EACH ROW
call refresh_recentgamenews_mv(NEW.newsid);


CREATE TRIGGER recentgamenews_delete
AFTER DELETE ON news FOR EACH ROW
call refresh_recentgamenews_mv(OLD.newsid);

DROP TABLE IF EXISTS `global_settings`;
CREATE TABLE `global_settings` ( 
  `setting_id` BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `setting_name` VARCHAR(255) NOT NULL,
  `current_value` VARCHAR(255) NOT NULL,
  PRIMARY KEY (setting_id),
  UNIQUE KEY `setting_name` (`setting_name`)
);

insert into global_settings (setting_name, current_value)
values
  ('account approval', 'normal');




DROP TABLE IF EXISTS `suspicious_domains`;
CREATE TABLE `suspicious_domains` ( 
  `suspicious_domain_id` BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `domain` VARCHAR(255) NOT NULL,
  `suspicion_level` TINYINT(1) UNSIGNED NOT NULL,
  PRIMARY KEY (suspicious_domain_id),
  UNIQUE KEY `domain` (`domain`)
);

insert into suspicious_domains (domain, suspicion_level)
values
  ('gmail.com', '1'),
  ('googlemail.com', '1'),
  ('ymail.com', '1'),
  ('hotmail.com', '1'),
  ('live.com', '1'),
  ('aol.com', '1'),
  ('windowslive.com', '1'),
  ('thes.ttct.edu.tw', '2'),
  ('bigmir.net', '3')
;

DROP TABLE IF EXISTS `suspicious_domains_history`;
CREATE TABLE `suspicious_domains_history` ( 
  `suspicious_domains_revision_id` BIGINT(2) UNSIGNED NOT NULL AUTO_INCREMENT,
  `mod_date` DATETIME NOT NULL,
  `domain` VARCHAR(255) NOT NULL,
  `suspicion_level` VARCHAR(14) NOT NULL,
  `modified_by` VARCHAR(255) NOT NULL,
  PRIMARY KEY (suspicious_domains_revision_id)
);

insert into `suspicious_domains_history` (domain, mod_date, suspicion_level, modified_by)
values
  ('gmail.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('googlemail.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('ymail.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('hotmail.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('live.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('aol.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('windowslive.com', '2007-07-31 00:00:00.000', '1', 'asdf90813lkjf09813'),
  ('thes.ttct.edu.tw', '2026-03-10 17:47:43', '2', 'oyrrw74upu8n2dds'),
  ('bigmir.net', '2007-07-31 00:00:00.000', '3', 'asdf90813lkjf09813')
;

-- Fix invalid published dates in games_history deltas (issue #1438).
-- parseDateOrYearVal used to turn empty dates into " 01:00:00"; replace with "".
UPDATE games_history
SET deltas = REPLACE(deltas, 's:9:"published";s:9:" 01:00:00"', 's:9:"published";s:0:""')
WHERE deltas LIKE '%s:9:"published";s:9:" 01:00:00"%';

