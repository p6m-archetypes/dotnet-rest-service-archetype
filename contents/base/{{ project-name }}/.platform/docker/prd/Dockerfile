# prd/Dockerfile — for CI/CD production builds

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder
WORKDIR /src

COPY . .
RUN dotnet restore "{{ PrefixName }}{{ SuffixName }}/{{ PrefixName }}{{ SuffixName }}.csproj" && \
    dotnet publish "{{ PrefixName }}{{ SuffixName }}/{{ PrefixName }}{{ SuffixName }}.csproj" \
        -c Release \
        -o /app/publish \
        --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Install CA certificates for TLS connections to external services
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Run as non-root user (built-in 'app' user in aspnet image, uid 1654)
USER app

COPY --from=builder --chown=app:app /app/publish .

ENV ASPNETCORE_URLS=""
EXPOSE {{ service_port }}
EXPOSE {{ management_port }}

ENTRYPOINT ["dotnet", "{{ PrefixName }}{{ SuffixName }}.dll"]
