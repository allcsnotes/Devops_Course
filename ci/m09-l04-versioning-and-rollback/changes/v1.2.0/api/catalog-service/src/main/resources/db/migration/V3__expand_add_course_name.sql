-- 1.2.0 EXPAND: add the new column next to the old one. Nothing is renamed or dropped,
-- so 1.0.0 (which only knows title) keeps working against this schema.
alter table courses add column name text;     -- nullable: 1.0.0 never writes it
update courses set name = title;              -- backfill the rows we already have
