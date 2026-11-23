using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.IncludeScopes = true;
    options.TimestampFormat = "O";
    options.UseUtcTimestamp = true;
});

builder.Services.AddSingleton<ReadinessState>();
builder.Services.AddHostedService<LifecycleService>();

var app = builder.Build();
var serviceName = builder.Configuration["APP_NAME"] ?? "devops-lab-sample-api";
var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";

app.MapGet("/", (ILogger<Program> logger) =>
{
    logger.LogInformation("Root endpoint requested for {Service}", serviceName);
    return Results.Ok(new { service = serviceName, version, status = "ok" });
});

app.MapGet("/health/live", () => Results.Ok(new { status = "live" }));

app.MapGet("/health/ready", (ReadinessState readiness) =>
    readiness.IsReady
        ? Results.Ok(new { status = "ready" })
        : Results.StatusCode(StatusCodes.Status503ServiceUnavailable));

app.Run();

internal sealed class ReadinessState
{
    private int _isReady;

    public bool IsReady => Volatile.Read(ref _isReady) == 1;

    public void SetReady(bool ready) => Volatile.Write(ref _isReady, ready ? 1 : 0);
}

internal sealed class LifecycleService(
    ReadinessState readiness,
    ILogger<LifecycleService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        readiness.SetReady(true);
        logger.LogInformation("Application started and is ready");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        readiness.SetReady(false);
        logger.LogInformation("Application shutdown completed gracefully");
        return Task.CompletedTask;
    }
}
