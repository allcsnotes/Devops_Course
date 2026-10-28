create table wallets (
    student_id  text primary key,
    balance_eur int  not null check (balance_eur >= 0)
);

-- one charge per saga
create table payments (
    id         bigint generated always as identity primary key,
    saga_id    bigint unique,
    student_id text        not null,
    amount_eur int         not null,
    status     text        not null,
    reason     text,
    created_at timestamptz not null default now()
);

insert into wallets values ('priya', 100), ('lukas', 30);

create table outbox (
    id           bigint generated always as identity primary key,
    topic        text        not null,
    msg_key      text        not null,
    payload      jsonb       not null,
    traceparent  text,
    created_at   timestamptz not null default now(),
    published_at timestamptz
);
create index outbox_unpublished on outbox (id) where published_at is null;

create table processed_messages (
    message_id   text primary key,
    processed_at timestamptz not null default now()
);
