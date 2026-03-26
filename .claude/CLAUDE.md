

# Memory Bank Integration
You have access to a persistent Memory Bank via MCP. Before beginning any task, you MUST invoke the appropriate tools (e.g. `list_projects`, `memory_bank_read`) to identify current project constraints and user preferences. 

**Rule Precedence:**
- If a project-specific rule (`rules.md` in the project folder) contradicts a global rule (`global_rules.md`), the **project-specific rule takes precedence**.
- Do not assume you have full context until this sync is complete.

