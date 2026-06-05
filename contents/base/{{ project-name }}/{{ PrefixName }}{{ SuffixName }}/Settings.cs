namespace {{ PrefixName }}{{ SuffixName }};

public class Settings
{
    public string Host { get; init; } = "0.0.0.0";
    public int Port { get; init; } = {{ service_port }};
    public int ManagementPort { get; init; } = {{ management_port }};
{% if persistence == 'PostgreSQL' %}
    // Assembled by PAO from connection secret: DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD, DB_DBNAME
    public string DbHost { get; init; } = "localhost";
    public int DbPort { get; init; } = 5432;
    public string DbUsername { get; init; } = "postgres";
    public string DbPassword { get; init; } = "postgres";
    public string DbDbname { get; init; } = "{{ project-name }}";
    public string DatabaseUrl =>
        $"Host={DbHost};Port={DbPort};Database={DbDbname};Username={DbUsername};Password={DbPassword}";
{% endif %}
{% if persistence == 'MySQL' %}
    // Assembled by PAO from connection secret: DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD, DB_DBNAME
    public string DbHost { get; init; } = "localhost";
    public int DbPort { get; init; } = 3306;
    public string DbUsername { get; init; } = "root";
    public string DbPassword { get; init; } = "root";
    public string DbDbname { get; init; } = "{{ project-name }}";
    public string DatabaseUrl =>
        $"Server={DbHost};Port={DbPort};Database={DbDbname};User={DbUsername};Password={DbPassword}";
{% endif %}
{% if cache == 'Redis' %}
    // Assembled by PAO from connection secret: CACHE_HOST, CACHE_PORT, CACHE_USERNAME, CACHE_PASSWORD
    public string CacheHost { get; init; } = "localhost";
    public int CachePort { get; init; } = 6379;
    public string CacheUsername { get; init; } = "";
    public string CachePassword { get; init; } = "";
    public string RedisUrl => string.IsNullOrEmpty(CachePassword)
        ? $"{CacheHost}:{CachePort}"
        : $"{CacheHost}:{CachePort},password={CachePassword}";
{% endif %}
{% if messaging == 'Kafka' %}
    // Injected by PAO from messaging secret: MESSAGING_BROKERS, MESSAGING_TOPIC,
    // MESSAGING_USERNAME, MESSAGING_PASSWORD, MESSAGING_SASL_MECHANISM
    public string MessagingBrokers { get; init; } = "localhost:9092";
    public string MessagingTopic { get; init; } = "{{ project-name }}";
    public string MessagingUsername { get; init; } = "";
    public string MessagingPassword { get; init; } = "";
    public string MessagingSaslMechanism { get; init; } = "PLAIN";
{% endif %}
{% if messaging == 'Pulsar' %}
    // Injected by PAO from messaging secret: MESSAGING_BROKER_URL, MESSAGING_TOPIC,
    // MESSAGING_JWT_TOKEN, MESSAGING_SUBSCRIPTION_NAME, MESSAGING_ACCESS
    public string MessagingBrokerUrl { get; init; } = "pulsar://localhost:6650";
    public string MessagingTopic { get; init; } = "persistent://public/default/{{ project-name }}";
    public string MessagingJwtToken { get; init; } = "";
    public string MessagingSubscriptionName { get; init; } = "{{ project-name }}-sub";
    public string MessagingAccess { get; init; } = "produce";
{% endif %}
{% if has_s3 %}
    public string S3Endpoint { get; init; } = "http://localhost:9000";
    public string S3Bucket { get; init; } = "{{ project-name }}";
    public string S3Prefix { get; init; } = "";
    public string S3AccessKey { get; init; } = "minioadmin";
    public string S3SecretKey { get; init; } = "minioadmin";
{% endif %}
{% if has_azure_blob %}
    public string AzureEndpoint { get; init; } = "http://localhost:10000/devstoreaccount1";
    public string AzureContainer { get; init; } = "{{ project-name }}";
    public string AzureAccountName { get; init; } = "devstoreaccount1";
    public string AzureAccountKey { get; init; } = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KkZB2M0XK3Xg==";
{% endif %}
}
