# catalog 1.2.0 - release notes

## What's new
- Instructors can add a course themselves (an internal admin call).

## Who needs to do something
- Nobody. Students see the same course list, and the API is unchanged.

## Safe to roll back?
- Yes, to 1.0.0. This release only adds a column (courses.name).
- Courses added in 1.2.0 stay visible after a rollback: 1.2.0 writes
  both title and name.

## Coming next
- 1.2.1 reads and writes name only. 1.2.2 drops title.
