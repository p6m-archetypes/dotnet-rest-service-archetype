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

local p6m = require("p6m")

local SRC = "."

local BASE_ANSWERS = {
  project_name = "example-service",
  solution_name = "acme-platform",
  entity_name = "example",
  image_registry  = "ghcr.io/acme",
}

-- NOTE: named, and that is load-bearing. `ctx:tempdir("render1")` is ADDRESSED, not created, so every
-- unnamed call in one scope answers with the SAME directory: two renders into one destination
-- leave the first winner in place and the second silently asserts against it. That is what made
-- the hollow variant see the persistence variant's files.
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
  "ExampleService/Domain/ExampleEntity.cs",
  "ExampleService/Api/ExampleRoutes.cs",
}

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local label = "dotnet-rest[" .. persistence .. "]"

  local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = persistence },
      destination = ctx:tempdir("render1"),
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
    destination = ctx:tempdir("render2"),
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

-- CI parity (S10): the rendered project's own Build workflow path — dotnet-setup/dotnet-build's
-- exact command sequence on a fresh clone, in the toolchain image. The Dockerfile and CI are two
-- independent build paths; S10 holds the second. The hollow render suffices: resource variants
-- change dependencies, not the command path.
prova.group("dotnet-rest[None]:ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, none_project, {
    stack = "dotnet",
    project_dir = "example-service",
    name = "dotnet-rest",
  })
end)
