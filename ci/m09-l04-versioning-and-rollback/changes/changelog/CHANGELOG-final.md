## [1.2.2] - 2026-10-20

### Refactor

- *(db)* Contract, drop courses.title
## [1.2.1] - 2026-10-20

### Refactor

- *(catalog)* Migrate, read and write only courses.name
## [1.2.0] - 2026-10-20

### Features

- *(catalog)* Instructors can add a course

### Refactor

- *(db)* Expand, add courses.name next to courses.title

### Miscellaneous Tasks

- Add the git-cliff changelog config

### Revert

- Undo 1.1.0, the one-step rename of courses.title
## [1.1.0] - 2026-10-20

### Features

- *(catalog)* Instructors can add a course

### Refactor

- *(db)* Rename courses.title to name
## [1.0.0] - 2026-10-20

### Features

- *(catalog)* Show the version and git commit in /actuator/info

### Other

- The whole platform, hardened and health-gated
- Pin h11 like the old prototype
- Measured first run, release and failure drill
- Ship the Flyway migrations as a versioned image
- Release catalog by git tag and deploy it by digest (make release, make deploy)
