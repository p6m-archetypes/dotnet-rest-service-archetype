namespace {{ PrefixName }}{{ SuffixName }}.Domain;

// Sample scaffold entity proving the persistence round trip end-to-end.
// Replace with your real domain model (and rename the routes in Api/ItemRoutes.cs to match).
public class Item
{
    public Guid Id { get; set; }
    public required string DisplayName { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
