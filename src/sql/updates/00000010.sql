DROP TRIGGER IF EXISTS `before_inodes_update`;

/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;

DELIMITER ;;
/*!50003 SET SESSION SQL_MODE="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION" */;;
/*!50003 CREATE TRIGGER `before_inodes_update` BEFORE UPDATE ON `inodes` FOR EACH ROW BEGIN
    IF OLD.size <> NEW.size THEN
        UPDATE statistics
        SET statistics.value = statistics.value - OLD.size + NEW.size
        WHERE statistics.key = 'total_inodes_size';
    END IF;
END */;;
DELIMITER ;
/*!50003 SET SESSION SQL_MODE=@OLD_SQL_MODE */;
