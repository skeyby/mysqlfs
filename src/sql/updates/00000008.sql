# MySQL 5.6 or higher compatibility

ALTER TABLE `data_blocks` CHANGE `seq` `seq` INT(10)  UNSIGNED  NOT NULL  DEFAULT '0';

CREATE TABLE `statistics` (
  `key` varchar(200) NOT NULL DEFAULT '',
  `value` varchar(200) NOT NULL DEFAULT '',
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `statistics` (`key`, `value`)
VALUES
	('total_inodes_count', '0'),
	('total_inodes_size', '0');

/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;

DELIMITER ;;
/*!50003 SET SESSION SQL_MODE="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION" */;;
/*!50003 CREATE TRIGGER `before_inodes_insert` BEFORE INSERT ON `inodes` FOR EACH ROW BEGIN
    UPDATE statistics
    SET statistics.value = statistics.value + NEW.size
    WHERE statistics.key = 'total_inodes_size';

    UPDATE statistics
    SET statistics.value = statistics.value + 1
    WHERE statistics.key = 'total_inodes_count';

END */;;
/*!50003 SET SESSION SQL_MODE="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION" */;;
/*!50003 CREATE TRIGGER `before_inodes_update` BEFORE UPDATE ON `inodes` FOR EACH ROW BEGIN
    UPDATE statistics
    SET statistics.value = statistics.value - OLD.size + NEW.size
    WHERE statistics.key = 'total_inodes_size';
END */;;
/*!50003 SET SESSION SQL_MODE="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION" */;;
/*!50003 CREATE TRIGGER `before_inodes_delete` BEFORE DELETE ON `inodes` FOR EACH ROW BEGIN

    UPDATE statistics
    SET statistics.value = statistics.value - OLD.size
    WHERE statistics.key = 'total_inodes_size';

    UPDATE statistics
    SET statistics.value = statistics.value - 1
    WHERE statistics.key = 'total_inodes_count';

END */;;
DELIMITER ;
/*!50003 SET SESSION SQL_MODE=@OLD_SQL_MODE */;


DELIMITER ;;
/*!50003 SET SESSION SQL_MODE="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION" */;;
/*!50003 CREATE TRIGGER `before_tree_delete` BEFORE DELETE ON `tree` FOR EACH ROW BEGIN

    UPDATE statistics, inodes
    SET statistics.value = statistics.value - inodes.size
    WHERE statistics.key = 'total_inodes_size'
    AND inodes.inode = OLD.inode;

    UPDATE statistics
    SET statistics.value = statistics.value - 1
    WHERE statistics.key = 'total_inodes_count';
END */;;
DELIMITER ;
/*!50003 SET SESSION SQL_MODE=@OLD_SQL_MODE */;

UPDATE statistics SET statistics.value = (select COUNT(*) from inodes) WHERE statistics.key = 'total_inodes_count';
UPDATE statistics SET statistics.value = (select COALESCE(sum(size), 0) from inodes) WHERE statistics.key = 'total_inodes_size';

REPLACE INTO SW_DETAILS SET `KEY` = "VERSION", `VALUE` = "1.0.0";
