using System.Net;
using {{ ProjectName }};
{% if persistence ~= 'None' or cache ~= 'None' or messaging ~= 'None' or has_s3 or has_azure_blob %}
using {{ ProjectName }}.Resources;
{% endif %}
{% if persistence ~= 'None' %}
using {{ ProjectName }}.Api;
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

    // The platform env contract: PAO injects UPPER_SNAKE variables (SERVER_PORT, MANAGEMENT_PORT,
    // DB_HOST, ...). .NET's default binder matches property names, not those, so map every
    // contract variable that is present onto its Settings key before binding. Property-name env
    // (Port=...) still works — the contract layers on top.
    var platformEnv = new Dictionary<string, string>
    {
        ["HOST"] = "Host",
        ["SERVER_PORT"] = "Port",
        ["MANAGEMENT_PORT"] = "ManagementPort",
        ["DB_HOST"] = "DbHost",
        ["DB_PORT"] = "DbPort",
        ["DB_USERNAME"] = "DbUsername",
        ["DB_PASSWORD"] = "DbPassword",
        ["DB_DBNAME"] = "DbDbname",
        ["CACHE_HOST"] = "CacheHost",
        ["CACHE_PORT"] = "CachePort",
        ["CACHE_USERNAME"] = "CacheUsername",
        ["CACHE_PASSWORD"] = "CachePassword",
        ["MESSAGING_BROKERS"] = "MessagingBrokers",
        ["MESSAGING_BROKER_URL"] = "MessagingBrokerUrl",
        ["MESSAGING_TOPIC"] = "MessagingTopic",
        ["MESSAGING_USERNAME"] = "MessagingUsername",
        ["MESSAGING_PASSWORD"] = "MessagingPassword",
        ["MESSAGING_SASL_MECHANISM"] = "MessagingSaslMechanism",
        ["MESSAGING_JWT_TOKEN"] = "MessagingJwtToken",
        ["MESSAGING_SUBSCRIPTION_NAME"] = "MessagingSubscriptionName",
        ["MESSAGING_ACCESS"] = "MessagingAccess",
        ["S3_ENDPOINT"] = "S3Endpoint",
        ["S3_BUCKET"] = "S3Bucket",
        ["S3_PREFIX"] = "S3Prefix",
        ["S3_ACCESS_KEY"] = "S3AccessKey",
        ["S3_SECRET_KEY"] = "S3SecretKey",
        ["AZURE_ENDPOINT"] = "AzureEndpoint",
        ["AZURE_CONTAINER"] = "AzureContainer",
        ["AZURE_ACCOUNT_NAME"] = "AzureAccountName",
        ["AZURE_ACCOUNT_KEY"] = "AzureAccountKey",
    };
    var contractOverrides = new Dictionary<string, string?>();
    foreach (var (env, key) in platformEnv)
    {
        if (builder.Configuration[env] is { Length: > 0 } value) contractOverrides[key] = value;
    }
    builder.Configuration.AddInMemoryCollection(contractOverrides);

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

    // Sample scaffold: create the schema and serve CRUD for the {{ EntityName }} entity
    // (Domain/{{ EntityName }}.cs, Api/{{ EntityName }}Routes.cs). Replace with your real model and routes.
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
