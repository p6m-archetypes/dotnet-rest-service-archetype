using System.Net;
using {{ PrefixName }}{{ SuffixName }};
{% if persistence ~= 'None' or cache ~= 'None' or messaging ~= 'None' or has_s3 or has_azure_blob %}
using {{ PrefixName }}{{ SuffixName }}.Resources;
{% endif %}
{% if persistence ~= 'None' %}
using {{ PrefixName }}{{ SuffixName }}.Api;
using Microsoft.EntityFrameworkCore;
{% endif %}
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Prometheus;
using Serilog;
using Serilog.Formatting.Json;

// Configure Serilog early so bootstrap errors are captured.
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console(new JsonFormatter())
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);
    var settings = builder.Configuration.Get<Settings>() ?? new Settings();

    // Structured logging via Serilog (JSON when LOGGING_STRUCTURED=true)
    builder.Host.UseSerilog((ctx, services, cfg) =>
    {
        var structured = ctx.Configuration["LOGGING_STRUCTURED"]?.Equals("true", StringComparison.OrdinalIgnoreCase) ?? false;
        if (structured)
            cfg.WriteTo.Console(new JsonFormatter());
        else
            cfg.WriteTo.Console();
        cfg.ReadFrom.Configuration(ctx.Configuration);
    });

    // OpenTelemetry tracing (fail-open: no-op when OTEL_EXPORTER_OTLP_ENDPOINT is absent)
    var otlpEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService(
            serviceName: builder.Configuration["OTEL_SERVICE_NAME"] ?? "{{ project-name }}"))
        .WithTracing(t =>
        {
            t.AddAspNetCoreInstrumentation();
            if (!string.IsNullOrEmpty(otlpEndpoint))
                t.AddOtlpExporter(o => o.Endpoint = new Uri(otlpEndpoint));
        });

{% if persistence ~= 'None' %}
    if (!builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddPersistence(settings);
{% endif %}
{% if cache ~= 'None' %}
    if (!builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddCache(settings);
{% endif %}
{% if messaging ~= 'None' %}
    if (!builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddMessaging(settings);
{% endif %}
{% if has_s3 %}
    if (!builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddStorageS3(settings);
{% endif %}
{% if has_azure_blob %}
    if (!builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddStorageAzure(settings);
{% endif %}

    // Two Kestrel endpoints: service traffic on service_port, management on management_port.
    // Skipped in Testing so the test HTTP client uses a single in-process server.
    if (!builder.Environment.IsEnvironment("Testing"))
    {
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.Listen(IPAddress.Any, settings.Port);
            options.Listen(IPAddress.Any, settings.ManagementPort);
        });
    }

    var app = builder.Build();

    // Management endpoints: health + Prometheus metrics.
    // In production these are only reachable on management_port; in Testing the
    // test client accesses them on the single shared in-process server.
    app.MapGet("/health/readiness", () => Results.Ok(new { status = "ok" }));
    app.MapGet("/health/liveness", () => Results.Ok(new { status = "ok" }));
    app.UseMetricServer(settings.ManagementPort); // prometheus-net: GET /metrics on management_port

    // TODO: Add your service routes here
    app.MapGet("/", () => "{{ project-name }}");
{% if persistence ~= 'None' %}

    // Sample scaffold: create the schema and serve CRUD for the Item entity
    // (Domain/Item.cs, Api/ItemRoutes.cs). Replace with your real model and routes.
    if (!builder.Environment.IsEnvironment("Testing"))
    {
        using (var scope = app.Services.CreateScope())
            scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();
        app.MapItemRoutes();
    }
{% endif %}

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
    return 1;
}
finally
{
    Log.CloseAndFlush();
}

return 0;

public partial class Program { }
