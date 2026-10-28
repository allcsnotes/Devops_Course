-- 1.2.1 MIGRATE: from now on every version reads name only.
update courses set name = title where name is null;  -- rows 1.0.0 wrote after V3
alter table courses alter column name set not null;
alter table courses alter column title drop not null; -- 1.2.1 stops writing title
