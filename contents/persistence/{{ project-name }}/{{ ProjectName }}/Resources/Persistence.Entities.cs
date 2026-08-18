using Microsoft.EntityFrameworkCore;
using {{ ProjectName }}.Domain;

namespace {{ ProjectName }}.Resources;

// The entity half of AppDbContext. The resource library owns provider wiring
// (Persistence.cs); the service owns its entities here, via the partial-class seam.
public partial class AppDbContext
{
    public DbSet<Item> Items => Set<Item>();
}
