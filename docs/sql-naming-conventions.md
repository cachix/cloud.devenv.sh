Taken from https://launchbylunch.com/posts/2014/Feb/16/sql-naming-conventions

### Why Naming Conventions Are Important

1. **Names Are Long-Lived**
   Data structures often outlast application code; schemas endure across rewrites. :contentReference[oaicite:2]{index=2}
2. **Names Are Contracts**
   Object names are part of your API—renaming breaks dependent apps. :contentReference[oaicite:3]{index=3}
3. **Developer Context Switching**
   Consistent names mean less time hunting down identifiers; e.g. `person_id` is always a FK to `person.id`. :contentReference[oaicite:4]{index=4}

### Core Naming Conventions

- **Avoid quoted identifiers** (no `"FirstName"` or `"All Employees"`): they complicate hand-written and dynamic SQL.
- **Lowercase & snake_case** for all tables, views, columns, etc. (`first_name`, not `FirstName`).
- **Use full English words**, not cryptic abbreviations (`middle_name`, not `mid_nm`), except for very common ones (`i18n`, `l10n`).
- **Underscores separate words**; never jam words together or use mixedCase.
- **Don’t use data-type names** as identifiers (`text`, `timestamp`)—choose descriptive nouns.
- **Avoid reserved words** (`user`, `lock`, `table`) entirely. :contentReference[oaicite:5]{index=5}

### Relation Naming

- **Singular names** for tables/views (`team`, not `teams`): avoids pluralization ambiguity and aligns with object models. :contentReference[oaicite:6]{index=6}

### Key-Field Naming

- **Primary keys**: always `id` (omit redundant prefixes like `person_id`).
- **Foreign keys**: `{referenced_table}_id` (e.g. `person_id` referencing `person.id`). :contentReference[oaicite:7]{index=7}

### Prefixes & Suffixes (Are Bad)

1. **Relation-type prefixes** (`tb_`, `vw_`, `sp_`): bad—object types can change without renaming.
2. **Application-name prefixes** (`Foobar_users`): unnecessary with schemas; only for cross-DB frameworks/plugins.
3. **Data-type suffixes** (`name_tx`, `created_dt`): bad—field types evolve. :contentReference[oaicite:8]{index=8}

### Explicit Naming of Derived Objects

- **Indexes**: name them yourself, including table and column names (e.g. `person_ix_first_name_last_name`) for clear EXPLAIN plans.
- **Constraints**: give descriptive names (e.g. `person_ck_email_lower_case`, `team_member_pkey`) to surface meaningful errors. :contentReference[oaicite:9]{index=9}

### Final Thoughts

- **New projects**: adopt these conventions uniformly from the start.
- **Existing schemas**: avoid mixing styles—if you must diverge, follow the existing pattern sparingly. :contentReference[oaicite:10]{index=10}
