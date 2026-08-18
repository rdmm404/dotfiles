Perform a code review of the current changes under two axes:
- **Spec adherence:** Inspect `docs/dot-cli-spec.md`, `docs/migration-plan.md`, `docs/migration-tasks.md` and `docs/migration-overview.md`. Ensure the code hasn't deviated from the specification, either by missing a requirement or doing unnecessary work.
- **Code Quality:** Ensure that the implemented code follows best practices, is clean, functional, simple and understandable.

## Guidelines
- Channel YAGNI principles. Avoid and discourage unnecessary complexity.
- Follow the "Code & Testing thoroughness" section in `migration-overview.md`
- Once a review is completed, save it as a markdown file under `docs/.reviews/<review-slug>.md`. Use a unique, identifyable slug.
- Before performing the review, check `docs/.reviews/` for previous reviews and read them. That way you can confirm that previous issues were addressed, and also avoid repeating yourself.
- Ensure your reviews are high-signal, only flag real concerns and clearly differentiate between "Must haves" and "Nice to haves".
- If a review is approved, do not create a markdown review, instead just reply with "APPROVED"