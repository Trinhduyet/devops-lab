# Fixed .NET SDK/runtime patches; verify updates before rebuilding the release image.
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0.404-noble
ARG DOTNET_ASPNET_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0.15-noble

FROM ${DOTNET_SDK_IMAGE} AS build
WORKDIR /src
COPY DevOpsLab.SampleApi.csproj ./
RUN dotnet restore DevOpsLab.SampleApi.csproj
COPY . ./
RUN dotnet publish DevOpsLab.SampleApi.csproj \
    --configuration Release \
    --no-restore \
    --output /out \
    -p:UseAppHost=false

FROM ${DOTNET_ASPNET_IMAGE} AS runtime
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
COPY --from=build /out/ ./
USER $APP_UID
ENTRYPOINT ["dotnet", "DevOpsLab.SampleApi.dll"]
