import Fluent
import FluentPostgresDriver
import Vapor
import VaporSkeletonKit

func configure(_ app: Application) throws {
    app.databases.use(
        try makePostgresConfiguration(from: PostgresEnvironmentConfig(
            databaseURL: Environment.get("DATABASE_URL"),
            host: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DATABASE_USERNAME") ?? "postgres",
            password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
            database: Environment.get("DATABASE_NAME") ?? "postgres",
            tlsDisabled: Environment.get("DATABASE_TLS") == "disable"
        )),
        as: .psql
    )
}
