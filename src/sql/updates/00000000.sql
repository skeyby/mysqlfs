-- Bogus BEGIN since TABLE definitions are not transaction-safe.
BEGIN;

-- Creating Table
CREATE TABLE `DATABASE_VERSION` (
  `CURRENT_VERSION` int(8) NOT NULL,
  `LAST_CHANGE` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- First record
INSERT INTO DATABASE_VERSION SET CURRENT_VERSION = 0, LAST_CHANGE = NOW();

-- Commit everything
COMMIT;
