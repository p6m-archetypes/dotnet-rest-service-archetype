--- Acceptance suite for the .NET REST service archetype: renders each persistence variant,
--- verifies the layout, builds it, boots it against a real database container, and proves REST
--- CRUD calls round-trip into that database. This suite defines the archetype's acceptance bar —
--- its job is to fill the gaps and keep them filled.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova
--- requires docker + dotnet (SDK 9); skips cleanly without them.

local postgres = require("postgres")
local mysql    = require("mysql")

local SRC = "."

local BASE_ANSWERS = {
  author_name     = "Test Author",
  author_email    = "test@example.com",
  org_name        = "acme",
  solution_name   = "platform",
  prefix_name     = "Example",
  suffix_name     = "Service",
  image_registry  = "ghcr.io/acme",
}

local function answers_with(extra)
  local out = {}
  for k, v in pairs(BASE_ANSWERS) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end

-- Files the persistence scaffold must produce (relative to the rendered project root).
local SCAFFOLD_FILES = {
  "ExampleService/Resources/Persistence.cs",
  "ExampleService/Resources/Persistence.Entities.cs",
  "ExampleService/Domain/Item.cs",
  "ExampleService/Api/ItemRoutes.cs",
}

-- One entry per rendering variant. `db` is the container recipe namespace; the SQL strings
-- carry each backend's identifier quoting and placeholder syntax.
local VARIANTS = {
  {
    persistence = "PostgreSQL",
    db = postgres,
    count_by_name = [[SELECT count(*) FROM "Items" WHERE "DisplayName" = $1]],
    count_all     = [[SELECT count(*) FROM "Items"]],
  },
  {
    persistence = "MySQL",
    db = mysql,
    count_by_name = "SELECT count(*) FROM `Items` WHERE `DisplayName` = ?",
    count_all     = "SELECT count(*) FROM `Items`",
  },
}

for _, v in ipairs(VARIANTS) do
  local label = "dotnet-rest[" .. v.persistence .. "]"

  -- a) render — one fixture per variant, shared by verify and the black-box tests.
  local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = v.persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  -- b) verify — layout, fully-rendered, and build checks against that rendering.
  archetect.verify(project, {
    name = label,
    project_dir = "example-service",
    expected_files = {
      "ExampleService.sln",
      "ExampleService/Program.cs",
      "ExampleService/Settings.cs",
      "ExampleService/appsettings.json",
      "ExampleService/ExampleService.csproj",
      SCAFFOLD_FILES[1], SCAFFOLD_FILES[2], SCAFFOLD_FILES[3], SCAFFOLD_FILES[4],
      ".github/workflows/build.yaml",
    },
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
    requires = { "dotnet" },
    build_steps = { "dotnet build ExampleService.sln" },
  })

  -- c) black-box — provision the database, boot the built service against it.
  local service = prova.fixture(label .. ":service", Scope.File, function(ctx)
    local root = ctx:use(project):dir("example-service")
    local db = v.db.container(ctx)

    shell.run("dotnet build ExampleService.sln -c Release", {
      cwd = root.path, timeout = "600s", check = true,
    })

    local port, mgmt = net.free_port(), net.free_port()
    ctx:manage(shell.spawn("dotnet ExampleService.dll", {
      cwd = root.path .. "/ExampleService/bin/Release/net9.0",
      env = {
        -- Settings binds by property name from configuration (env provider included).
        Port           = port,
        ManagementPort = mgmt,
        DbHost         = db.host,
        DbPort         = db.port,
        DbUsername     = "prova",
        DbPassword     = "prova",
        DbDbname       = "prova",
      },
    }))

    local api = http.client{ base_url = "http://127.0.0.1:" .. port }
    -- Readiness proves the chain: the app only serves after EnsureCreated succeeded against the DB.
    api:wait_for("/health/readiness", { timeout = "60s" })
    return { api = api, db = db.client }
  end)

  prova.group(label .. " CRUD round-trip", { requires = { "docker", "dotnet" } }, function(g)
    g:test("created items land in " .. v.persistence, function(t)
      local svc = t:use(service)

      -- Create through the public API...
      local created = svc.api:post("/api/items", { json = { displayName = "widget" } })
      t:expect(created.status):equals(201)
      local body = created:json()
      t:expect(body.displayName):equals("widget")
      t:expect(body.id, "created id"):is_truthy()

      -- ...and prove the row exists in the actual database, not just the API's memory.
      t:expect(svc.db:query_value(v.count_by_name, { "widget" }), "rows in DB"):equals(1)

      -- Read back through every door.
      t:expect(svc.api:get("/api/items/" .. body.id):json().displayName):equals("widget")
    end)

    g:test("updates and deletes round-trip into " .. v.persistence, function(t)
      local svc = t:use(service)

      local body = svc.api:post("/api/items", { json = { displayName = "ephemeral" } }):json()

      local updated = svc.api:put("/api/items/" .. body.id, { json = { displayName = "renamed" } })
      t:expect(updated.status):equals(200)
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "renamed row in DB"):equals(1)
      t:expect(svc.db:query_value(v.count_by_name, { "ephemeral" }), "old name gone"):equals(0)

      t:expect(svc.api:delete("/api/items/" .. body.id).status):equals(204)
      t:expect(svc.api:get("/api/items/" .. body.id).status):equals(404)
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "row deleted from DB"):equals(0)
    end)
  end)
end

-- The hollow rendering stays hollow: no persistence, no scaffold files.
archetect.verify{
  name = "dotnet-rest[None]",
  source = SRC,
  answers = answers_with{ persistence = "None" },
  project_dir = "example-service",
  expected_files = {
    "ExampleService.sln",
    "ExampleService/Program.cs",
  },
  absent_files = SCAFFOLD_FILES,
  requires = { "dotnet" },
  build_steps = { "dotnet build ExampleService.sln" },
}
