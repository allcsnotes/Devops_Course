create table courses (
    id         text primary key,
    title      text not null,
    price_eur  int  not null,
    seats_left int  not null check (seats_left >= 0)
);

-- a seat taken for one saga: HELD, then CONFIRMED or RELEASED
create table seat_holds (
    saga_id    bigint primary key,
    course_id  text        not null references courses (id),
    status     text        not null,
    updated_at timestamptz not null default now()
);

insert into courses values
    ('SPRING-101', 'Spring Boot',   19, 30),
    ('SD-101',     'System Design', 49, 5),
    ('DSA-101',    'DSA',           29, 20);

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
