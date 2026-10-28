create table enrollments (
    id           bigint generated always as identity primary key,
    student_id   text        not null,
    course_id    text        not null,
    course_title text        not null,
    price_eur    int         not null,
    status       text        not null,
    reason       text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- one saga per enrollment: where it is, and until when it may wait
create table saga_instance (
    id         bigint primary key references enrollments (id),
    state      text        not null,
    amount_eur int         not null,
    deadline   timestamptz not null,
    updated_at timestamptz not null default now()
);

create table shedlock (
    name       varchar(64)  primary key,
    lock_until timestamp    not null,
    locked_at  timestamp    not null,
    locked_by  varchar(255) not null
);

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
