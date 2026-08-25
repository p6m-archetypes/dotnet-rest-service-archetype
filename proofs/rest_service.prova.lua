--- Render-verification suite for the Dotnet REST service archetype: each persistence variant lays
--- out correctly and is fully rendered, and the hollow (None) rendering stays hollow.
---
--- Every rendering comes from `p6m.spec{}` + `p6m.render` — the shape harness — so the paths this
--- file expects are BUILT from the same identity the archetype was answered with, never spelled by
--- hand. A hand-spelled path list is how a scaffold file outlived the entity it was named for.
---
--- The BEHAVIORAL bar — CRUD through the production image, the platform env contract, health/
--- metrics/structured logs, both name shapes — lives in proofs/standards.prova.lua, which also owns
--- S10 CI parity. No host toolchain is invoked here (S8b).

local p6m = require("p6m")

local function spec_for(persistence)
  return p6m.spec{
    language = "dotnet", shape = "full", transport = "rest",
    project = "example-service", entity = "example", solution = "acme-platform",
    persistence = persistence, registry = "ghcr.io/acme",
  }
end

local function paths(s)
  -- The .NET project directory and every type in it follow the identity: `ProjectName` names the
  -- csproj and the solution, `EntityName` the scaffold entity the persistence variant adds.
  local P = s.id.ProjectName
  local E = s.id.EntityName
  return {
    base = {
      P .. ".sln",
      "Directory.Build.props",
      P .. "/" .. P .. ".csproj",
      P .. "/Program.cs",
      P .. "/Settings.cs",
      P .. "/appsettings.json",
      P .. ".Tests/" .. P .. ".Tests.csproj",
      ".dockerignore",
      ".platform/docker/local/Dockerfile",
      ".platform/docker/prd/Dockerfile",
    },
    scaffold = {
      P .. "/Domain/" .. E .. "Entity.cs",
      P .. "/Resources/Persistence.cs",
      P .. "/Resources/Persistence.Entities.cs",
      P .. "/Api/" .. E .. "Routes.cs",
    },
  }
end

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local s = spec_for(persistence)
  local f = paths(s)

  local expected = {}
  for _, x in ipairs(f.base) do expected[#expected + 1] = x end
  for _, x in ipairs(f.scaffold) do expected[#expected + 1] = x end

  archetect.verify{
    name = s.label,
    source = ".",
    answers = s.answers,
    project_dir = s.project_dir,
    expected_files = expected,
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  }
end

-- The hollow rendering stays hollow: no persistence, no scaffold files.
local none = spec_for("None")
local none_paths = paths(none)
local none_project = p6m.render(none)

archetect.verify(none_project, {
  name = none.label,
  project_dir = none.project_dir,
  expected_files = none_paths.base,
  absent_files = none_paths.scaffold,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
})

-- Containerized compile proof for the hollow variant (S8b): the persistence variants compile
-- inside the standards SUT image builds; None never boots there, so prove it compiles by building
-- its production image — build success IS the compile check, no boot needed.
prova.group(none.label .. ":image", { requires = { "docker" } }, function(g)
  g:test("production image builds from a clean render", function(t)
    local root = t:use(none_project):dir(none.project_dir)
    local image = docker.build{
      context = root.path,
      dockerfile = ".platform/docker/prd/Dockerfile",
    }
    t:expect(image, "built image"):never():is_nil()
  end)
end)
