using Microsoft.EntityFrameworkCore;
using {{ ProjectName }}.Domain;
using {{ ProjectName }}.Resources;

namespace {{ ProjectName }}.Api;

public record CreateItemRequest(string DisplayName);
public record UpdateItemRequest(string DisplayName);

// Sample scaffold CRUD routes for the Item entity — the persistence round trip a
// black-box test can drive. Rename alongside Domain/Item.cs when you add your real model.
public static class ItemRoutes
{
    public static IEndpointRouteBuilder MapItemRoutes(this IEndpointRouteBuilder app)
    {
        var items = app.MapGroup("/api/v1/{{ entity-name }}s");

        items.MapPost("", async (CreateItemRequest request, AppDbContext db) =>
        {
            var item = new Item { Id = Guid.NewGuid(), DisplayName = request.DisplayName };
            db.Items.Add(item);
            await db.SaveChangesAsync();
            return Results.Created($"/api/v1/{{ entity-name }}s/{item.Id}", item);
        });

        items.MapGet("", async (AppDbContext db) =>
            Results.Ok(await db.Items.OrderBy(i => i.CreatedAt).ToListAsync()));

        items.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
            await db.Items.FindAsync(id) is { } item ? Results.Ok(item) : Results.NotFound());

        items.MapPut("/{id:guid}", async (Guid id, UpdateItemRequest request, AppDbContext db) =>
        {
            var item = await db.Items.FindAsync(id);
            if (item is null) return Results.NotFound();
            item.DisplayName = request.DisplayName;
            await db.SaveChangesAsync();
            return Results.Ok(item);
        });

        items.MapDelete("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var item = await db.Items.FindAsync(id);
            if (item is null) return Results.NotFound();
            db.Items.Remove(item);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        return app;
    }
}
