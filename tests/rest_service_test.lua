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

-- Ports the CONTAINERIZED variant runs the service on *inside* its container. Fixed, not
-- net.free_port(): a container has its own network namespace, so there is nothing to collide with,
-- and docker publishes them to random host ports anyway (parallel-safe). The host-run variant below
-- still needs free_port(), because it shares this machine's port space.
local SERVICE_PORT    = 8080
local MANAGEMENT_PORT = 8081

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

  -- d) containerized black-box — the SAME service, but built from the archetype's OWN production
  -- Dockerfile and run as a container on the topology's network, wired to the database by DNS alias.
  --
  -- This is the variant that needs NOTHING but docker: no .NET SDK on the host, because the SDK is
  -- the Dockerfile's builder stage. It is also a strictly bigger claim than the host-run variant
  -- above. That one proves the source builds and works against a real database on *this machine*,
  -- with this machine's SDK and NuGet cache. This one proves the artifact we actually ship — the
  -- real image, its runtime base, its entrypoint, its env contract — works. The Dockerfile is under
  -- test, not just the code.
  --
  -- It renders its OWN project rather than sharing the fixture above, and deliberately so: that one
  -- is host-built, and both Dockerfiles `COPY . .` with no .dockerignore shipped, so a host build's
  -- bin/obj (whose project.assets.json carries absolute host paths) would be copied into the image
  -- build. Isolating keeps this variant from depending on fixture order. The missing .dockerignore
  -- is a real archetype gap — see README.
  local ctr_project = prova.fixture(label .. ":ctr-project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = v.persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  -- A topology, not a plain fixture: `ctx.network` (the ambient managed network resources auto-join)
  -- exists only inside a topology factory. It also means `prova up` can stand this whole thing up.
  local containerized = prova.topology(label .. ":containerized", function(ctx)
    local root = ctx:use(ctr_project):dir("example-service")

    -- Build FIRST, with the primitive, before anything with a readiness clock exists.
    --
    -- `prova.containerized{ build = … }` would build here too, and reads better — but it builds at
    -- provision time, i.e. AFTER the database below is already up and being waited on. A cold .NET
    -- image build is minutes of a saturated machine (SDK restore + publish), and that is enough to
    -- push a sibling postgres past its 60s readiness deadline: the DB is fine, its clock just ran
    -- while the builder hogged the box. Ordering the expensive step first costs one line and makes
    -- the fixture robust cold, not just warm. (This is the two-layer design paying off: the
    -- convenience never removed the primitive, so we can drop a level exactly where it matters.)
    local image = docker.build{
      context = root.path,
      dockerfile = ".platform/docker/local/Dockerfile",
    }

    local db = v.db.container(ctx)          -- auto-joins ctx.network, aliased by its recipe name

    local app = prova.containerized{
      name = "app",
      image = image,                        -- the artifact built above
      port = SERVICE_PORT,
      timeout = "120s",
      env = function(opts)
        return {
          -- Settings binds by property name, exactly as the host-run variant above — the env
          -- contract is part of what the image has to honor.
          Port           = SERVICE_PORT,
          ManagementPort = MANAGEMENT_PORT,
          -- The DB's NETWORK vantage: its alias and CONTAINER port. The host vantage
          -- (127.0.0.1:<mapped>) is meaningless in here — inside a container 127.0.0.1 is itself.
          DbHost         = opts.db_host,
          DbPort         = opts.db_port,
          DbUsername     = "prova",
          DbPassword     = "prova",
          DbDbname       = "prova",
        }
      end,
      url = function(hp) return "http://127.0.0.1:" .. hp end,
    }.container(ctx, { db_host = db.network.host, db_port = db.network.port })

    -- The app listening is not the same as the app being ready: it serves only after EnsureCreated
    -- succeeds against the database, which is the chain this variant exists to prove.
    http.wait_for(app.url .. "/health/readiness", { timeout = "120s" })

    -- `api` drives the SUT from the host over its published port; `db` cross-checks over the
    -- database's host vantage. Two vantages, one live topology.
    return { api = http.client{ base_url = app.url }, db = db.client }
  end)

  -- The acceptance bar itself — identical for both vantages, so a containerized SUT is held to
  -- exactly the bar a host-run one is. Only the fixture differs.
  local function crud_round_trip_tests(g, sut)
    g:test("created items land in " .. v.persistence, function(t)
      local svc = t:use(sut)

      -- Create through the public API...
      local created = svc.api:post("/api/v1/examples", { json = { displayName = "widget" } })
      t:expect(created.status):equals(201)
      local body = created:json()
      t:expect(body.displayName):equals("widget")
      t:expect(body.id, "created id"):is_truthy()

      -- ...and prove the row exists in the actual database, not just the API's memory.
      t:expect(svc.db:query_value(v.count_by_name, { "widget" }), "rows in DB"):equals(1)

      -- Read back through every door.
      t:expect(svc.api:get("/api/v1/examples/" .. body.id):json().displayName):equals("widget")
    end)

    g:test("updates and deletes round-trip into " .. v.persistence, function(t)
      local svc = t:use(sut)

      local body = svc.api:post("/api/v1/examples", { json = { displayName = "ephemeral" } }):json()

      local updated = svc.api:put("/api/v1/examples/" .. body.id, { json = { displayName = "renamed" } })
      t:expect(updated.status):equals(200)
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "renamed row in DB"):equals(1)
      t:expect(svc.db:query_value(v.count_by_name, { "ephemeral" }), "old name gone"):equals(0)

      t:expect(svc.api:delete("/api/v1/examples/" .. body.id).status):equals(204)
      t:expect(svc.api:get("/api/v1/examples/" .. body.id).status):equals(404)
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "row deleted from DB"):equals(0)
    end)
  end

  -- Host-run SUT: needs the SDK on this machine.
  prova.group(label .. " CRUD round-trip", { requires = { "docker", "dotnet" }, tags = { "host-sut" } },
    function(g) crud_round_trip_tests(g, service) end)

  -- Containerized SUT: needs only docker. Same bar.
  prova.group(label .. " CRUD round-trip (containerized SUT)",
    { requires = { "docker" }, tags = { "container-sut" } },
    function(g) crud_round_trip_tests(g, containerized) end)
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
