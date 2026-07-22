--- Render-verification suite for the .NET REST service archetype: each persistence variant lays
--- out correctly and is fully rendered, and the hollow (None) rendering stays hollow.
---
--- The BEHAVIORAL bar — CRUD through the production image, the platform env contract, health/
--- metrics/structured logs, both name shapes — lives in tests/standards_test.lua (the shared
--- p6m standards suite), fully containerized: docker is the only requirement. Compile coverage
--- is containerized too: the standards SUT image builds compile the persistence variants, and
--- the hollow rendering is proven compilable by building its production Dockerfile here — no
--- host SDK is ever required.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

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

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local label = "dotnet-rest[" .. persistence .. "]"

  local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  archetect.verify(project, {
    name = label,
    project_dir = "example-service",
    expected_files = {
      "ExampleService.sln",
      "ExampleService/Program.cs",
      "ExampleService/Settings.cs",
      "ExampleService/appsettings.json",
      "ExampleService/ExampleService.csproj",
      ".dockerignore",
      SCAFFOLD_FILES[1], SCAFFOLD_FILES[2], SCAFFOLD_FILES[3], SCAFFOLD_FILES[4],
      ".github/workflows/build.yaml",
    },
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  })
end

-- The hollow rendering stays hollow: no persistence, no scaffold files.
local none_project = prova.fixture("dotnet-rest[None]:project", Scope.File, function(ctx)
  return archetect.render{
    source = SRC,
    answers = answers_with{ persistence = "None" },
    destination = ctx:tempdir(),
    defaults = true,
  }
end)

archetect.verify(none_project, {
  name = "dotnet-rest[None]",
  project_dir = "example-service",
  expected_files = {
    "ExampleService.sln",
    "ExampleService/Program.cs",
  },
  absent_files = SCAFFOLD_FILES,
})

-- Containerized compile proof for the hollow rendering: the persistence variants are compiled by
-- the standards suite's SUT image builds; None never boots there, so prove it compiles by
-- building its production Dockerfile (build success = it compiles; no boot needed).
prova.group("dotnet-rest[None]:image", { requires = { "docker" } }, function(g)
  g:test("production image builds (compiles the hollow rendering)", function(t)
    local root = t:use(none_project):dir("example-service")
    local image = docker.build{
      context = root.path,
      dockerfile = ".platform/docker/prd/Dockerfile",
    }
    t:expect(image, "built image ref"):never():is_empty()
  end)
end)
