using Microsoft.EntityFrameworkCore;
using {{ ProjectName }}.Domain;
using {{ ProjectName }}.Resources;

namespace {{ ProjectName }}.Api;

public record CreateItemRequest(string DisplayName);
public record UpdateItemRequest(string DisplayName);

// Sample scaffold CRUD routes for the {{ EntityName }} entity — the persistence round trip a
// black-box test can drive. Rename alongside Domain/{{ EntityName }}.cs when you add your real model.
public static class {{ EntityName }}Routes
{
    public static IEndpointRouteBuilder MapItemRoutes(this IEndpointRouteBuilder app)
    {
        var {{ entity_name }}s = app.MapGroup("/api/v1/{{ entity-name }}s");

        {{ entity_name }}s.MapPost("", async (CreateItemRequest request, AppDbContext db) =>
        {
            var item = new {{ EntityName }} { Id = Guid.NewGuid(), DisplayName = request.DisplayName };
            db.{{ EntityName }}s.Add(item);
            await db.SaveChangesAsync();
            return Results.Created($"/api/v1/{{ entity-name }}s/{item.Id}", item);
        });

        {{ entity_name }}s.MapGet("", async (AppDbContext db) =>
            Results.Ok(await db.{{ EntityName }}s.OrderBy(i => i.CreatedAt).ToListAsync()));

        {{ entity_name }}s.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
            await db.{{ EntityName }}s.FindAsync(id) is { } item ? Results.Ok(item) : Results.NotFound());

        {{ entity_name }}s.MapPut("/{id:guid}", async (Guid id, UpdateItemRequest request, AppDbContext db) =>
        {
            var item = await db.{{ EntityName }}s.FindAsync(id);
            if (item is null) return Results.NotFound();
            item.DisplayName = request.DisplayName;
            await db.SaveChangesAsync();
            return Results.Ok(item);
        });

        {{ entity_name }}s.MapDelete("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var item = await db.{{ EntityName }}s.FindAsync(id);
            if (item is null) return Results.NotFound();
            db.{{ EntityName }}s.Remove(item);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        return app;
    }
}
