# spec_ai

MCP server gem: drives Selenium, records the session, exports RSpec or Capybara specs.

## Working rules

- Commits are authored solely by the repo owner (Augustin Gottlieb). Never add `Co-Authored-By`, `Generated-with`, or any AI/tool attribution trailers or branding to commits, PRs, or files.
- No em dashes anywhere: prose, docs, code comments, or user-facing message strings. Use `-`, commas, or separate sentences.
- Style: double-quoted strings (RuboCop-enforced). Run `bundle exec rspec && bundle exec rubocop` before committing; browser suite via `BROWSER_TESTS=1`.
- Renderers (`lib/spec_ai/codegen/`) stay pure: no selenium/capybara requires, IR in, source out. Golden files in `spec/fixtures/golden/` are the codegen contract; fix renderers, never golden files.
- Generated specs must run green on first try; the CI meta-test enforces this claim.
