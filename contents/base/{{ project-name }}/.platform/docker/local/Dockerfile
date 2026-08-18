# local/Dockerfile — for kind cluster local development
# Load with: kind load docker-image <image>:<tag>

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder
WORKDIR /src

COPY . .
RUN dotnet restore "{{ ProjectName }}/{{ ProjectName }}.csproj" && \
    dotnet publish "{{ ProjectName }}/{{ ProjectName }}.csproj" \
        -c Release \
        -o /app/publish \
        --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Run as non-root user (built-in 'app' user in aspnet image, uid 1654)
USER app

COPY --from=builder --chown=app:app /app/publish .

ENV ASPNETCORE_URLS=""
EXPOSE {{ service_port }}
EXPOSE {{ management_port }}

ENTRYPOINT ["dotnet", "{{ ProjectName }}.dll"]
