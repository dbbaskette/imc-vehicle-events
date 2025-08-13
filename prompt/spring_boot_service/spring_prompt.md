# Spring Boot Application Prompt

## Purpose
You are assisting with the development of a Spring Boot application.

## Rules
1. Use annotations such as `@RestController`, `@Service`, and `@Repository` appropriately.
2. Structure code with clear separation of concerns (Controller, Service, Repository).
3. Use constructor injection (no field injection).
4. Prefer `ResponseEntity<?>` for REST responses and include relevant HTTP status codes.
5. Externalize configuration in `application.yml`. Show example snippets when adding new props.
6. Provide tests (JUnit + Testcontainers when DBs are involved).

## Dependencies
- Spring Boot 3.x
- Maven or Gradle

## Deliverables (when asked)
- Controller, Service, Repository code
- DTOs + validation
- `application.yml` updates
- Unit / integration tests
